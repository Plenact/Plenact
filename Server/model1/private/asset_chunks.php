<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
use PDO;
final class AssetChunks {
    public const CHUNK_BYTES=262144;
    public function __construct(private PDO $pdo,private \Closure $clock,private \Closure $validateRequest,
        private int $maxUploadBytes=67108864) {
        if($maxUploadBytes<1 || $maxUploadBytes>1073741824)throw new \InvalidArgumentException('Invalid upload limit');
    }
    private function owner(string $account,string $workspace,bool $lock=false):array {
        $s=$this->pdo->prepare("SELECT w.* FROM m1_workspaces w JOIN m1_accounts a ON a.account_id=w.owner_account_id WHERE w.workspace_id=? AND w.owner_account_id=? AND a.account_status='active'".($lock?' FOR UPDATE':''));
        $s->execute([$workspace,$account]);$w=$s->fetch(PDO::FETCH_ASSOC);
        if(!$w)throw new ApiFailure(404,'not_found');return $w;
    }
    private function lease(string $account,string $workspace,string $upload,bool $lock=false):array {
        $w=$this->owner($account,$workspace,$lock);
        $s=$this->pdo->prepare('SELECT * FROM m1_asset_uploads WHERE upload_id=? AND workspace_id=? AND account_id=?'.($lock?' FOR UPDATE':''));
        $s->execute([$upload,$workspace,$account]);$lease=$s->fetch(PDO::FETCH_ASSOC);
        if(!$lease)throw new ApiFailure(404,'not_found');
        if($lease['epoch']!==$w['epoch'])throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
        if(strtotime($lease['expires_at_utc'].' UTC')<=($this->clock)())throw new ApiFailure(410,'upload_expired');
        return $lease;
    }
    public function start(string $account,string $workspace,string $raw):array {
        ($this->validateRequest)($raw);$r=json_decode($raw,true,64,JSON_THROW_ON_ERROR);
        if($r['workspace_id']!==$workspace)throw new ApiFailure(400,'invalid_document');
        $length=$r['byte_length'];
        if(strlen($length)>strlen((string)$this->maxUploadBytes)||(strlen($length)===strlen((string)$this->maxUploadBytes)&&strcmp($length,(string)$this->maxUploadBytes)>0))throw new ApiFailure(413,'payload_too_large');
        $this->pdo->beginTransaction();
        try{
            $w=$this->owner($account,$workspace,true);
            if($w['epoch']!==$r['epoch'])throw new ApiFailure(409,'epoch_mismatch','resnapshot_and_reconcile');
            $s=$this->pdo->prepare("SELECT * FROM m1_record_heads WHERE workspace_id=? AND record_id=? AND record_type='asset'");$s->execute([$workspace,$r['asset_id']]);$head=$s->fetch(PDO::FETCH_ASSOC);
            if(!$head)throw new ApiFailure(404,'not_found');
            if((bool)$head['deleted'] || (string)$head['revision']!==$r['asset_revision'])throw new ApiFailure(409,'conflict','resolve_conflict');
            $doc=json_decode($head['document'],true,64,JSON_THROW_ON_ERROR);$p=$doc['payload'];
            if($p['content_state']!=='described'||$p['byte_length']!==$length||!hash_equals($p['sha256'],$r['sha256']))throw new ApiFailure(422,'integrity_mismatch');
            $upload=\Plenact\PrivateAuth\uuid();$now=($this->clock)();$count=intdiv((int)$length+self::CHUNK_BYTES-1,self::CHUNK_BYTES);
            $this->pdo->prepare('INSERT INTO m1_asset_uploads VALUES (?, ?, ?, ?, ?, ?, ?, UNHEX(?), ?, ?, ?)')->execute([
                $upload,$workspace,$account,$w['epoch'],$r['asset_id'],$r['asset_revision'],$length,$r['sha256'],$count,gmdate('Y-m-d H:i:s',$now),gmdate('Y-m-d H:i:s',$now+86400)]);
            $this->pdo->commit();return $this->read($account,$workspace,$upload);
        }catch(\Throwable $e){if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
    }
    public function read(string $account,string $workspace,string $upload):array {
        $l=$this->lease($account,$workspace,$upload);
        $s=$this->pdo->prepare('SELECT chunk_index FROM m1_asset_chunks WHERE upload_id=? ORDER BY chunk_index');$s->execute([$upload]);
        return ['protocol_version'=>'1.0','workspace_id'=>$workspace,'epoch'=>$l['epoch'],'asset_id'=>$l['asset_id'],'asset_revision'=>(string)$l['asset_revision'],
            'upload_id'=>$upload,'chunk_bytes'=>self::CHUNK_BYTES,'chunk_count'=>(int)$l['chunk_count'],'byte_length'=>(string)$l['byte_length'],
            'received_chunks'=>array_map('intval',$s->fetchAll(PDO::FETCH_COLUMN)),
            'expires_at_utc'=>gmdate('Y-m-d\TH:i:s',strtotime($l['expires_at_utc'].' UTC')).'.000Z'];
    }
    public function put(string $account,string $workspace,string $upload,int $index,string $bytes,string $digest):void {
        if(!preg_match('/\A[a-f0-9]{64}\z/D',$digest)||!hash_equals(hash('sha256',$bytes),$digest))throw new ApiFailure(422,'integrity_mismatch');
        if(strlen($bytes)>self::CHUNK_BYTES)throw new ApiFailure(413,'payload_too_large');
        $this->pdo->beginTransaction();
        try{
            $l=$this->lease($account,$workspace,$upload,true);
            if($index<0||$index>=(int)$l['chunk_count'])throw new ApiFailure(400,'invalid_document');
            $expected=min(self::CHUNK_BYTES,(int)$l['byte_length']-$index*self::CHUNK_BYTES);
            if(strlen($bytes)!==$expected)throw new ApiFailure(422,'integrity_mismatch');
            $s=$this->pdo->prepare('SELECT sha256,chunk_bytes FROM m1_asset_chunks WHERE upload_id=? AND chunk_index=?');$s->execute([$upload,$index]);$old=$s->fetch(PDO::FETCH_ASSOC);
            if($old){if(!hash_equals($old['sha256'],hex2bin($digest))||!hash_equals($old['chunk_bytes'],$bytes))throw new ApiFailure(409,'conflict','resolve_conflict');}
            else $this->pdo->prepare('INSERT INTO m1_asset_chunks VALUES (?, ?, UNHEX(?), ?)')->execute([$upload,$index,$digest,$bytes]);
            $this->pdo->commit();
        }catch(\Throwable $e){if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
    }
}
