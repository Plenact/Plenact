<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
use PDO;
// Validator callbacks must enforce pinned request/document schemas and the complete resulting graph.
// The HTTP router does not expose this engine until those production validators are installed.
final class Transactions {
    public function __construct(private PDO $pdo,private \Closure $validateRequest,private \Closure $validateGraph) {}
    public function commit(string $account,string $workspace,string $idempotencyKey,string $raw): array {
        if (strlen($raw)>8388608) throw new ApiFailure(413,'payload_too_large');
        ($this->validateRequest)($raw); // Must reject duplicate JSON keys, invalid scalars, depth and schema.
        $request=json_decode($raw,true,64,JSON_THROW_ON_ERROR);
        $wire=json_decode($raw,false,64,JSON_THROW_ON_ERROR);
        if ($request['workspace_id']!==$workspace || $request['transaction_id']!==$idempotencyKey) throw new ApiFailure(400,'invalid_document');
        $this->pdo->beginTransaction();
        try {
            $s=$this->pdo->prepare("SELECT w.* FROM m1_workspaces w JOIN m1_accounts a ON a.account_id=w.owner_account_id WHERE w.workspace_id=? AND w.owner_account_id=? AND a.account_status='active' FOR UPDATE");
            $s->execute([$workspace,$account]);$w=$s->fetch(PDO::FETCH_ASSOC);
            if (!$w) throw new ApiFailure(404,'not_found');
            if ($w['epoch']!==$request['epoch']) throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
            $digest=hash('sha256',$raw);
            $s=$this->pdo->prepare('SELECT HEX(request_sha256) AS digest, receipt FROM m1_transaction_receipts WHERE workspace_id=? AND transaction_id=?');
            $s->execute([$workspace,$idempotencyKey]);$receipt=$s->fetch(PDO::FETCH_ASSOC);
            if ($receipt) {
                if (!hash_equals(strtolower($receipt['digest']),$digest)) throw new ApiFailure(409,'idempotency_mismatch','resolve_conflict');
                $this->pdo->commit();return json_decode($receipt['receipt'],true,64,JSON_THROW_ON_ERROR);
            }
            $s=$this->pdo->prepare('SELECT * FROM m1_record_heads WHERE workspace_id=?');$s->execute([$workspace]);
            $heads=[];foreach ($s->fetchAll(PDO::FETCH_ASSOC) as $head) $heads[$head['record_id']]=$head;
            $candidate=$heads;$results=[];$envelopes=[];$seenRecords=[];$seenOperations=[];
            $sequence=(int)$w['change_sequence'];$now=(new \DateTimeImmutable('now',new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.v\Z');
            foreach ($request['operations'] as $index=>$op) {
                $id=$op['record_id'];$opId=$op['operation_id'];$type=$op['record_type'];
                if (isset($seenRecords[$id]) || isset($seenOperations[$opId]) || in_array($type,['account','workspace'],true)) throw new ApiFailure(422,'validation_failed');
                $seenRecords[$id]=true;$seenOperations[$opId]=true;
                $s=$this->pdo->prepare('SELECT 1 FROM m1_operation_receipts WHERE workspace_id=? AND operation_id=?');$s->execute([$workspace,$opId]);
                if ($s->fetchColumn()!==false) throw new ApiFailure(409,'idempotency_mismatch','resolve_conflict');
                $s=$this->pdo->prepare('SELECT 1 FROM m1_asset_operations WHERE workspace_id=? AND operation_id=?');$s->execute([$workspace,$opId]);
                if($s->fetchColumn()!==false)throw new ApiFailure(409,'idempotency_mismatch','resolve_conflict');
                $head=$heads[$id] ?? null;
                if (($head && ($head['record_type']!==$type || (bool)$head['deleted'] || (string)$head['revision']!==$op['base_revision']))
                    || (!$head && ($op['base_revision']!==null || $op['kind']!=='put'))) throw new ApiFailure(409,'conflict','resolve_conflict',[[
                    'record_type'=>$head['record_type'] ?? $type,'record_id'=>$id,
                    'current_revision'=>$head ? (string)$head['revision'] : null,'deleted'=>$head ? (bool)$head['deleted'] : false]]);
                if ($head && $head['epoch']!==$w['epoch']) throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
                if ($sequence===PHP_INT_MAX || ($head && (int)$head['revision']===PHP_INT_MAX)) throw new ApiFailure(503,'quota_exceeded','retry_later');
                $revision=$head ? (int)$head['revision']+1 : 1;$sequence++;
                $deleted=$op['kind']==='delete';$document=$deleted ? null : $op['document'];
                $wireDocument=$deleted ? null : $wire->operations[$index]->document;
                if (!$deleted && ($document['id']!==$id || $document['record_type']!==$type || $document['workspace_id']!==$workspace)) throw new ApiFailure(422,'validation_failed');
                $asset=$type==='asset' && !$deleted ? ($head ? json_decode($head['asset_content'],true) : ['state'=>'unavailable','byte_length'=>null,'sha256'=>null,'verified_at_utc'=>null]) : null;
                // Asset byte-state changes must use the upload/commit boundary, never ordinary puts.
                if ($type==='asset' && $head && !$deleted && ($asset['state'] ?? '')==='verified'
                    && (($document['payload']['content_state'] ?? '')!=='described'
                        || ($document['payload']['byte_length'] ?? null)!==$asset['byte_length']
                        || ($document['payload']['sha256'] ?? null)!==$asset['sha256'])) throw new ApiFailure(422,'validation_failed');
                $e=['user_data_model_version'=>'1.0','workspace_id'=>$workspace,'record_type'=>$type,'record_id'=>$id,'epoch'=>$w['epoch'],
                    'revision'=>(string)$revision,'change_sequence'=>(string)$sequence,'stored_at_utc'=>$now,'stored_by_account_id'=>$account,
                    'deleted'=>$deleted,'document'=>$wireDocument,'asset_content'=>$asset];
                $envelopes[]=$e;
                $candidate[$id]=['workspace_id'=>$workspace,'record_id'=>$id,'record_type'=>$type,'epoch'=>$w['epoch'],'revision'=>$revision,'change_sequence'=>$sequence,'deleted'=>$deleted,'stored_at_utc'=>$now,'stored_by_account_id'=>$account,
                    'document'=>$document===null ? null : json_encode($wireDocument,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),'asset_content'=>$asset===null ? null : json_encode($asset,JSON_THROW_ON_ERROR)];
                $results[]=['operation_id'=>$opId,'record_type'=>$type,'record_id'=>$id,'revision'=>(string)$revision,'change_sequence'=>(string)$sequence,'deleted'=>$deleted];
            }
            ($this->validateGraph)($candidate,$account,$workspace); // Under workspace lock, before any content/receipt writes.
            $sqlTime=substr(str_replace('T',' ',$now),0,-1);
            foreach ($envelopes as $e) {
                $h=$candidate[$e['record_id']];
                $s=$this->pdo->prepare('INSERT INTO m1_record_heads VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE revision=VALUES(revision), change_sequence=VALUES(change_sequence), deleted=VALUES(deleted), document=VALUES(document), asset_content=VALUES(asset_content), stored_at_utc=VALUES(stored_at_utc), stored_by_account_id=VALUES(stored_by_account_id)');
                $s->execute([$workspace,$e['record_id'],$e['record_type'],$w['epoch'],$e['revision'],$e['change_sequence'],(int)$e['deleted'],$h['document'],$h['asset_content'],$sqlTime,$account]);
                $this->pdo->prepare('INSERT INTO m1_record_revisions VALUES (?, ?, ?, ?, ?, ?, ?, ?)')->execute([$workspace,$w['epoch'],$e['record_id'],$e['record_type'],$e['revision'],$e['change_sequence'],json_encode($e,JSON_THROW_ON_ERROR),$sqlTime]);
                $this->pdo->prepare('INSERT INTO m1_changes VALUES (?, ?, ?, ?, ?, ?)')->execute([$workspace,$w['epoch'],$e['change_sequence'],$e['record_id'],$e['revision'],$sqlTime]);
            }
            $receipt=['protocol_version'=>'1.0','workspace_id'=>$workspace,'epoch'=>$w['epoch'],'transaction_id'=>$idempotencyKey,'request_sha256'=>$digest,
                'receipt_sequence'=>(string)$sequence,'stored_at_utc'=>$now,'results'=>$results];
            $this->pdo->prepare('INSERT INTO m1_transaction_receipts VALUES (?, ?, ?, UNHEX(?), ?, ?, ?)')->execute([$workspace,$idempotencyKey,$w['epoch'],$digest,$sequence,json_encode($receipt,JSON_THROW_ON_ERROR),$sqlTime]);
            foreach ($results as $r) $this->pdo->prepare('INSERT INTO m1_operation_receipts VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')->execute([$workspace,$r['operation_id'],$idempotencyKey,$w['epoch'],$r['record_id'],$r['record_type'],$r['revision'],$r['change_sequence'],(int)$r['deleted']]);
            $this->pdo->prepare('UPDATE m1_workspaces SET change_sequence=?, updated_at_utc=? WHERE workspace_id=?')->execute([$sequence,$sqlTime,$workspace]);
            $this->pdo->commit();return $receipt;
        } catch (\Throwable $e) { if ($this->pdo->inTransaction()) $this->pdo->rollBack();throw $e; }
    }
}
