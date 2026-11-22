<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
use PDO;
final class SyncReads {
    private const MAX_BYTES=8388608;
    public function __construct(private PDO $pdo,private CursorCodec $codec,private \Closure $clock,
        private \Closure $validateOffer,private int $pageSize=100) {
        if($pageSize<1||$pageSize>100)throw new \InvalidArgumentException('Invalid page size');
    }
    private function owned(string $account,string $workspace,bool $lock=false):array {
        $s=$this->pdo->prepare("SELECT w.* FROM m1_workspaces w JOIN m1_accounts a ON a.account_id=w.owner_account_id WHERE w.workspace_id=? AND w.owner_account_id=? AND a.account_status='active'".($lock?' FOR UPDATE':''));
        $s->execute([$workspace,$account]);$w=$s->fetch(PDO::FETCH_ASSOC);
        if(!$w)throw new ApiFailure(404,'not_found');return $w;
    }
    private function changeCursor(string $a,string $w,string $e,string $sequence):string {
        return $this->codec->issue('c',$a,$w,$e,$sequence,($this->clock)()+90*86400);
    }
    public function start(string $account,string $workspace,string $rawOffer):array {
        ($this->validateOffer)($rawOffer);
        $offer=json_decode($rawOffer,true,64,JSON_THROW_ON_ERROR);
        if(!in_array('1.0',$offer['read_model_versions'],true))throw new ApiFailure(426,'unsupported_version','update_client');
        $snapshot=\Plenact\PrivateAuth\uuid();$created=($this->clock)();$expires=$created+1800;
        $this->pdo->beginTransaction();
        try {
            $w=$this->owned($account,$workspace,true);
            // All writes lock this workspace too, so the copy has one immutable fence.
            $s=$this->pdo->prepare('SELECT h.record_type,h.record_id,h.change_sequence,r.server_envelope FROM m1_record_heads h JOIN m1_record_revisions r ON r.workspace_id=h.workspace_id AND r.epoch=h.epoch AND r.record_id=h.record_id AND r.record_type=h.record_type AND r.revision=h.revision WHERE h.workspace_id=? AND h.epoch=? ORDER BY h.record_type,h.record_id');
            $s->execute([$workspace,$w['epoch']]);$rows=$s->fetchAll(PDO::FETCH_ASSOC);
            $headCount=$this->pdo->prepare('SELECT COUNT(*) FROM m1_record_heads WHERE workspace_id=?');$headCount->execute([$workspace]);
            if((int)$headCount->fetchColumn()!==count($rows))throw new ApiFailure(503,'invalid_document','retry_later');
            // Return the complete snapshot even for unsupported record types; clients preserve them opaquely.
            $this->pdo->prepare('INSERT INTO m1_snapshot_leases VALUES (?, ?, ?, ?, ?, ?, ?, ?)')->execute([
                $snapshot,$workspace,$account,$w['epoch'],$w['change_sequence'],count($rows),gmdate('Y-m-d H:i:s',$created),gmdate('Y-m-d H:i:s',$expires)]);
            foreach($rows as $i=>$row){
                if((int)$row['change_sequence']>(int)$w['change_sequence'])throw new ApiFailure(503,'invalid_document','retry_later');
                $this->pdo->prepare('INSERT INTO m1_snapshot_records VALUES (?, ?, ?, ?, ?)')->execute([$snapshot,$i,$row['record_type'],$row['record_id'],$row['server_envelope']]);
            }
            $this->pdo->commit();
            $cursor=$this->codec->issue('s',$account,$workspace,$w['epoch'],'0',$expires,$snapshot);
            return $this->page($account,$workspace,$snapshot,$cursor);
        }catch(\Throwable $e){if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
    }
    public function page(string $account,string $workspace,string $snapshot,string $cursor):array {
        $w=$this->owned($account,$workspace);
        $c=$this->codec->read($cursor,'s',$account,$workspace,$snapshot);
        if($c['e']!==$w['epoch'])throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
        $s=$this->pdo->prepare('SELECT * FROM m1_snapshot_leases WHERE snapshot_id=? AND workspace_id=? AND account_id=? AND epoch=?');
        $s->execute([$snapshot,$workspace,$account,$w['epoch']]);$lease=$s->fetch(PDO::FETCH_ASSOC);
        if(!$lease || strtotime($lease['expires_at_utc'].' UTC')<=($this->clock)())throw new ApiFailure(410,'snapshot_expired','resnapshot');
        $position=(int)$c['p'];$count=(int)$lease['record_count'];
        if($position>$count || ($position===$count && $count!==0))throw new ApiFailure(400,'invalid_document');
        $s=$this->pdo->prepare('SELECT ordinal,server_envelope FROM m1_snapshot_records WHERE snapshot_id=? AND ordinal>=? ORDER BY ordinal LIMIT '.($this->pageSize));
        $s->execute([$snapshot,$position]);$rows=$s->fetchAll(PDO::FETCH_ASSOC);$records=[];
        $page=['protocol_version'=>'1.0','workspace_id'=>$workspace,'epoch'=>$w['epoch'],'snapshot_id'=>$snapshot,
            'fence_sequence'=>(string)$lease['fence_sequence'],'expires_at_utc'=>gmdate('Y-m-d\TH:i:s',strtotime($lease['expires_at_utc'].' UTC')).'.000Z',
            'records'=>[],'next_page_cursor'=>null,'next_change_cursor'=>null];
        foreach($rows as $row){
            if((int)$row['ordinal']!==$position+count($records))throw new ApiFailure(503,'invalid_document','retry_later');
            $record=json_decode($row['server_envelope'],false,64,JSON_THROW_ON_ERROR);
            if($record->workspace_id!==$workspace || $record->epoch!==$w['epoch'] || (int)$record->change_sequence>(int)$lease['fence_sequence'])throw new ApiFailure(503,'invalid_document','retry_later');
            $candidate=$page;$candidate['records']=[...$records,$record];
            $this->snapshotCursors($candidate,$account,$lease,$position+count($candidate['records']));
            if(strlen(json_encode($candidate,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES))>self::MAX_BYTES){
                if(!$records)throw new ApiFailure(413,'payload_too_large');break;
            }
            $records[]=$record;
        }
        if(!$records && $count>0)throw new ApiFailure(503,'invalid_document','retry_later');
        $page['records']=$records;$this->snapshotCursors($page,$account,$lease,$position+count($records));return $page;
    }
    private function snapshotCursors(array &$page,string $account,array $lease,int $next):void {
        if($next<(int)$lease['record_count']){
            $page['next_page_cursor']=$this->codec->issue('s',$account,$lease['workspace_id'],$lease['epoch'],(string)$next,strtotime($lease['expires_at_utc'].' UTC'),$lease['snapshot_id']);$page['next_change_cursor']=null;
        }else{
            $page['next_page_cursor']=null;$page['next_change_cursor']=$this->changeCursor($account,$lease['workspace_id'],$lease['epoch'],(string)$lease['fence_sequence']);
        }
    }
    public function changes(string $account,string $workspace,string $cursor):array {
        $c=$this->codec->read($cursor,'c',$account,$workspace);
        $this->pdo->beginTransaction();
        try{
            $w=$this->owned($account,$workspace,true);
            if($w['epoch']!==$c['e'])throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
            $after=(int)$c['p'];$counter=(int)$w['change_sequence'];
            if($after>$counter)throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
            $s=$this->pdo->prepare('SELECT c.change_sequence,r.server_envelope FROM m1_changes c JOIN m1_record_revisions r ON r.workspace_id=c.workspace_id AND r.epoch=c.epoch AND r.record_id=c.record_id AND r.revision=c.revision WHERE c.workspace_id=? AND c.epoch=? AND c.change_sequence>? AND c.stored_at_utc>=? ORDER BY c.change_sequence LIMIT '.$this->pageSize);
            $s->execute([$workspace,$w['epoch'],$after,gmdate('Y-m-d H:i:s',($this->clock)()-90*86400)]);$rows=$s->fetchAll(PDO::FETCH_ASSOC);
            $records=[];$through=$after;
            $page=['protocol_version'=>'1.0','workspace_id'=>$workspace,'epoch'=>$w['epoch'],'after_sequence'=>(string)$after,'through_sequence'=>(string)$after,
                'records'=>[],'has_more'=>false,'next_cursor'=>''];
            foreach($rows as $row){
                if((int)$row['change_sequence']!==$through+1)throw new ApiFailure(410,'cursor_expired','resnapshot');
                $record=json_decode($row['server_envelope'],false,64,JSON_THROW_ON_ERROR);
                if($record->workspace_id!==$workspace || $record->epoch!==$w['epoch'] || (string)$record->change_sequence!==(string)$row['change_sequence'])throw new ApiFailure(503,'invalid_document','retry_later');
                $candidate=$page;$candidate['records']=[...$records,$record];$candidate['through_sequence']=(string)$row['change_sequence'];
                $candidate['has_more']=(int)$row['change_sequence']<$counter;$candidate['next_cursor']=$this->changeCursor($account,$workspace,$w['epoch'],(string)$row['change_sequence']);
                if(strlen(json_encode($candidate,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES))>self::MAX_BYTES){if(!$records)throw new ApiFailure(413,'payload_too_large');break;}
                $records[]=$record;$through=(int)$row['change_sequence'];
            }
            if(!$records && $counter>$after)throw new ApiFailure(410,'cursor_expired','resnapshot');
            $page['records']=$records;$page['through_sequence']=(string)$through;$page['has_more']=$through<$counter;
            $page['next_cursor']=$this->changeCursor($account,$workspace,$w['epoch'],(string)$through);
            $this->pdo->commit();return $page;
        }catch(\Throwable $e){if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
    }
}
