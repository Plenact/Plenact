<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
// Operational acceptance ledger outside the database and service-backup directory.
// Restore tooling must replay/verify this ledger before reopening any network routes.
final class DeletionJournal {
    private string $root;
    public function __construct(string $root,private string $key) {
        $real=realpath($root);
        if(strlen($key)!==32||$real===false||!is_dir($real)||is_link($root)||(fileperms($real)&0777)!==0700)throw new \RuntimeException('Private deletion journal unavailable');
        $this->root=$real;
    }
    private function path(string $job):string {
        if(!uuidValid($job))throw new \InvalidArgumentException('Invalid guard identity');return $this->root.'/'.$job.'.json';
    }
    private function validate(array $event):void {
        $expected=['job_id','job_kind','account_id','workspace_id','asset_id','operation_id','request_sha256','requesting_session_sha256','receipt','blob_targets'];
        if(array_diff($expected,array_keys($event))||array_diff(array_keys($event),$expected))throw new \RuntimeException('Invalid guard fields');
        foreach(['job_id','account_id','workspace_id','operation_id']as$key)if(!is_string($event[$key])||!uuidValid($event[$key]))throw new \RuntimeException('Invalid guard identity');
        if(!in_array($event['job_kind'],['asset_purge','account_delete'],true)||!is_array($event['receipt'])||!is_array($event['blob_targets']))throw new \RuntimeException('Invalid guard kind');
        if($event['job_kind']==='asset_purge'&&(!is_string($event['asset_id'])||!uuidValid($event['asset_id'])))throw new \RuntimeException('Invalid purge target');
        if($event['job_kind']==='account_delete'&&$event['asset_id']!==null)throw new \RuntimeException('Invalid deletion target');
        foreach(['request_sha256','requesting_session_sha256']as$key)if(!is_string($event[$key])||!preg_match('/\A[0-9a-f]{64}\z/D',$event[$key]))throw new \RuntimeException('Invalid guard digest');
        if(($event['receipt']['operation_id']??null)!==$event['operation_id']||($event['receipt']['protocol_version']??null)!=='1.0')throw new \RuntimeException('Invalid receipt identity');
        if($event['job_kind']==='account_delete'&&($event['receipt']['account_id']??null)!==$event['account_id'])throw new \RuntimeException('Invalid deletion receipt');
        if($event['job_kind']==='asset_purge'&&(($event['receipt']['workspace_id']??null)!==$event['workspace_id']||($event['receipt']['asset_id']??null)!==$event['asset_id']))throw new \RuntimeException('Invalid purge receipt');
        foreach($event['blob_targets']as$target){if(!is_array($target)||array_keys($target)!==['blob_id','workspace_id','asset_id']||$target['workspace_id']!==$event['workspace_id'])throw new \RuntimeException('Invalid blob guard');foreach($target as$id)if(!is_string($id)||!uuidValid($id))throw new \RuntimeException('Invalid blob guard identity');}
    }
    public function append(array $event):void {
        $this->validate($event);$path=$this->path($event['job_id']);
        $payload=json_encode($event,JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES);
        $bytes=json_encode(['payload'=>$payload,'hmac'=>hash_hmac('sha256',$payload,$this->key)],JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES)."\n";
        if(file_exists($path)){if($this->read($event['job_id'])!==$event)throw new \RuntimeException('Guard identity already accepted');return;}
        $temp=$this->root.'/.pending-'.\Plenact\PrivateAuth\uuid();$stream=fopen($temp,'x+b');if(!$stream)throw new \RuntimeException('Cannot persist deletion guard');
        try{
            if(!chmod($temp,0600)||fwrite($stream,$bytes)!==strlen($bytes)||!fflush($stream)||(function_exists('fsync')&&!fsync($stream)))throw new \RuntimeException('Cannot persist deletion guard');
            fclose($stream);$stream=null;
            if(!link($temp,$path))throw new \RuntimeException('Cannot publish deletion guard');
        }finally{if(is_resource($stream))fclose($stream);if(is_file($temp))unlink($temp);}
    }
    public function read(string $job):array {
        $path=$this->path($job);if(is_link($path)||!is_file($path)||(fileperms($path)&0777)!==0600)throw new \RuntimeException('Invalid deletion guard file');
        $wrapper=json_decode(file_get_contents($path),true,64,JSON_THROW_ON_ERROR);
        if(!is_string($wrapper['payload']??null)||!is_string($wrapper['hmac']??null)||!hash_equals(hash_hmac('sha256',$wrapper['payload'],$this->key),$wrapper['hmac']))throw new \RuntimeException('Invalid deletion guard signature');
        $event=json_decode($wrapper['payload'],true,64,JSON_THROW_ON_ERROR);if(!is_array($event))throw new \RuntimeException('Invalid guard event');$this->validate($event);
        if($event['job_id']!==$job)throw new \RuntimeException('Deletion guard identity mismatch');return $event;
    }
    public function all():array {
        $events=[];foreach(glob($this->root.'/*.json')?:[]as$path)$events[]=$this->read(basename($path,'.json'));return $events;
    }
}
