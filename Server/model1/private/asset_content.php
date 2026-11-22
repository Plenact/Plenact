<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
use PDO;
final class AssetContent {
    public function __construct(private PDO $pdo,private BlobFiles $files,private \Closure $clock,private \Closure $validateCommit){}
    private function owner(string $account,string $workspace,bool $lock=false):array {
        $s=$this->pdo->prepare("SELECT w.* FROM m1_workspaces w JOIN m1_accounts a ON a.account_id=w.owner_account_id WHERE w.workspace_id=? AND w.owner_account_id=? AND a.account_status='active'".($lock?' FOR UPDATE':''));
        $s->execute([$workspace,$account]);$w=$s->fetch(PDO::FETCH_ASSOC);if(!$w)throw new ApiFailure(404,'not_found');return $w;
    }
    public function commit(string $account,string $workspace,string $upload,string $idempotencyKey,string $raw):array {
        ($this->validateCommit)($raw);$r=json_decode($raw,true,64,JSON_THROW_ON_ERROR);
        if($r['workspace_id']!==$workspace||$r['upload_id']!==$upload||$r['operation_id']!==$idempotencyKey)throw new ApiFailure(400,'invalid_document');
        $temporary=null;$stream=null;$published=null;$commitStarted=false;
        $this->pdo->beginTransaction();
        try{
            $w=$this->owner($account,$workspace,true);
            if($r['epoch']!==$w['epoch'])throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
            $digest=hash('sha256',$raw);
            $s=$this->pdo->prepare('SELECT operation_kind,HEX(request_sha256) AS digest,result FROM m1_asset_operations WHERE workspace_id=? AND operation_id=?');$s->execute([$workspace,$idempotencyKey]);$old=$s->fetch(PDO::FETCH_ASSOC);
            if($old){if($old['operation_kind']!=='upload_commit'||!hash_equals(strtolower($old['digest']),$digest))throw new ApiFailure(409,'idempotency_mismatch','resolve_conflict');$this->pdo->commit();$result=(array)json_decode($old['result'],false,64,JSON_THROW_ON_ERROR);$result['asset_content']=(array)$result['asset_content'];return $result;}
            $s=$this->pdo->prepare('SELECT 1 FROM m1_operation_receipts WHERE workspace_id=? AND operation_id=?');$s->execute([$workspace,$idempotencyKey]);if($s->fetchColumn()!==false)throw new ApiFailure(409,'idempotency_mismatch','resolve_conflict');
            $s=$this->pdo->prepare('SELECT * FROM m1_asset_uploads WHERE upload_id=? AND workspace_id=? AND account_id=? FOR UPDATE');$s->execute([$upload,$workspace,$account]);$l=$s->fetch(PDO::FETCH_ASSOC);
            if(!$l)throw new ApiFailure(404,'not_found');
            if($l['epoch']!==$w['epoch'])throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
            if(strtotime($l['expires_at_utc'].' UTC')<=($this->clock)())throw new ApiFailure(410,'upload_expired');
            $s=$this->pdo->prepare("SELECT * FROM m1_record_heads WHERE workspace_id=? AND record_id=? AND record_type='asset'");$s->execute([$workspace,$l['asset_id']]);$head=$s->fetch(PDO::FETCH_ASSOC);
            if(!$head||(bool)$head['deleted']||(string)$head['revision']!==(string)$l['asset_revision'])throw new ApiFailure(409,'conflict','resolve_conflict');
            $doc=json_decode($head['document'],false,64,JSON_THROW_ON_ERROR);
            if($doc->payload->content_state!=='described'||$doc->payload->byte_length!==(string)$l['byte_length']||!hash_equals($doc->payload->sha256,bin2hex($l['sha256'])))throw new ApiFailure(422,'integrity_mismatch');
            if((int)$head['revision']===PHP_INT_MAX||(int)$w['change_sequence']===PHP_INT_MAX)throw new ApiFailure(503,'quota_exceeded','retry_later');
            [$temporary,$stream]=$this->files->temporary($workspace);$hash=hash_init('sha256');$length=0;$index=0;
            $s=$this->pdo->prepare('SELECT chunk_index,sha256,chunk_bytes FROM m1_asset_chunks WHERE upload_id=? ORDER BY chunk_index');$s->execute([$upload]);
            while($chunk=$s->fetch(PDO::FETCH_ASSOC)){
                $bytes=$chunk['chunk_bytes'];$expected=min(AssetChunks::CHUNK_BYTES,(int)$l['byte_length']-$index*AssetChunks::CHUNK_BYTES);
                if((int)$chunk['chunk_index']!==$index||strlen($bytes)!==$expected||!hash_equals(hash('sha256',$bytes,true),$chunk['sha256']))throw new ApiFailure(422,'integrity_mismatch');
                if(fwrite($stream,$bytes)!==strlen($bytes))throw new ApiFailure(503,'asset_unavailable','retry_later');
                hash_update($hash,$bytes);$length+=strlen($bytes);$index++;
            }
            if($index!==(int)$l['chunk_count']||$length!==(int)$l['byte_length']||!hash_equals(hash_final($hash,true),$l['sha256']))throw new ApiFailure(422,'integrity_mismatch');
            if(!fflush($stream)||(function_exists('fsync')&&!fsync($stream)))throw new ApiFailure(503,'asset_unavailable','retry_later');
            fclose($stream);$stream=null;$blob=\Plenact\PrivateAuth\uuid();$published=$this->files->publish($temporary,$workspace,$blob);$temporary=null;
            $now=gmdate('Y-m-d\TH:i:s',($this->clock)()).'.000Z';$sqlTime=gmdate('Y-m-d H:i:s',($this->clock)());
            $revision=(int)$head['revision']+1;$sequence=(int)$w['change_sequence']+1;
            $state=['state'=>'verified','byte_length'=>(string)$length,'sha256'=>bin2hex($l['sha256']),'verified_at_utc'=>$now];
            $e=['user_data_model_version'=>'1.0','workspace_id'=>$workspace,'record_type'=>'asset','record_id'=>$l['asset_id'],'epoch'=>$w['epoch'],
                'revision'=>(string)$revision,'change_sequence'=>(string)$sequence,'stored_at_utc'=>$now,'stored_by_account_id'=>$account,'deleted'=>false,'document'=>$doc,'asset_content'=>$state];
            $json=json_encode($e,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
            $this->pdo->prepare('INSERT INTO m1_asset_blobs VALUES (?, ?, ?, ?, ?, ?, ?)')->execute([$blob,$workspace,$l['asset_id'],$revision,$length,$l['sha256'],$sqlTime]);
            $this->pdo->prepare('UPDATE m1_record_heads SET revision=?,change_sequence=?,asset_content=?,stored_at_utc=?,stored_by_account_id=? WHERE workspace_id=? AND record_id=?')->execute([$revision,$sequence,json_encode($state,JSON_THROW_ON_ERROR),$sqlTime,$account,$workspace,$l['asset_id']]);
            $this->pdo->prepare('INSERT INTO m1_record_revisions VALUES (?, ?, ?, ?, ?, ?, ?, ?)')->execute([$workspace,$w['epoch'],$l['asset_id'],'asset',$revision,$sequence,$json,$sqlTime]);
            $this->pdo->prepare('INSERT INTO m1_changes VALUES (?, ?, ?, ?, ?, ?)')->execute([$workspace,$w['epoch'],$sequence,$l['asset_id'],$revision,$sqlTime]);
            $this->pdo->prepare('UPDATE m1_workspaces SET change_sequence=?,updated_at_utc=? WHERE workspace_id=?')->execute([$sequence,$sqlTime,$workspace]);
            $this->pdo->prepare("INSERT INTO m1_asset_operations VALUES (?, ?, 'upload_commit', ?, UNHEX(?), ?, ?)")->execute([$workspace,$idempotencyKey,$w['epoch'],$digest,$json,$sqlTime]);
            $commitStarted=true;$this->pdo->commit();return $e;
        }catch(\Throwable $e){
            if($this->pdo->inTransaction())$this->pdo->rollBack();
            if(is_resource($stream))fclose($stream);
            if($temporary!==null&&is_file($temporary))unlink($temporary);
            // If commit acknowledgement is ambiguous, preserve the immutable file for receipt recovery.
            if(!$commitStarted&&$published!==null&&is_file($published))unlink($published);
            throw $e;
        }
    }
    public function download(string $account,string $workspace,string $asset):array {
        $this->owner($account,$workspace);
        $s=$this->pdo->prepare("SELECT * FROM m1_record_heads WHERE workspace_id=? AND record_id=? AND record_type='asset' AND deleted=0");$s->execute([$workspace,$asset]);$head=$s->fetch(PDO::FETCH_ASSOC);
        if(!$head)throw new ApiFailure(404,'not_found');
        $state=json_decode($head['asset_content'],true,64,JSON_THROW_ON_ERROR);
        if(($state['state']??'')!=='verified')throw new ApiFailure(404,'asset_unavailable');
        $s=$this->pdo->prepare('SELECT * FROM m1_asset_blobs WHERE workspace_id=? AND asset_id=? AND published_revision<=? AND byte_length=? AND sha256=UNHEX(?) ORDER BY published_revision DESC LIMIT 1');
        $s->execute([$workspace,$asset,$head['revision'],$state['byte_length'],$state['sha256']]);$blob=$s->fetch(PDO::FETCH_ASSOC);
        if(!$blob)throw new ApiFailure(503,'asset_unavailable','retry_later');
        return ['stream'=>$this->files->open($workspace,$blob['blob_id'],(int)$blob['byte_length'],$state['sha256']),
            'byte_length'=>(int)$blob['byte_length'],'etag'=>'"'.$state['sha256'].'"'];
    }
}
