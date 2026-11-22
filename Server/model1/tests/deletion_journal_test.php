<?php
declare(strict_types=1);
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/lifecycle_policy.php';require_once __DIR__.'/../private/deletion_journal.php';
use Plenact\PrivateData\{LifecyclePolicy,DeletionJournal};
function journalNeed(bool $ok):void{if(!$ok)throw new RuntimeException('Journal test failed');}
function journalReject(callable$fn):void{try{$fn();throw new LogicException('Invalid guard accepted');}catch(RuntimeException|InvalidArgumentException$e){}}
$root=sys_get_temp_dir().'/plenact-journal-test-'.bin2hex(random_bytes(8));mkdir($root,0700);$key=random_bytes(32);$journal=new DeletionJournal($root,$key);
$a=\Plenact\PrivateAuth\uuid();$w=\Plenact\PrivateAuth\uuid();$op=\Plenact\PrivateAuth\uuid();$job=\Plenact\PrivateAuth\uuid();
$event=['job_id'=>$job,'job_kind'=>'account_delete','account_id'=>$a,'workspace_id'=>$w,'asset_id'=>null,'operation_id'=>$op,
 'request_sha256'=>hash('sha256','synthetic request'),'requesting_session_sha256'=>hash('sha256','synthetic token'),
 'receipt'=>LifecyclePolicy::receipt('account_delete',$a,$w,null,$op,1763683200),'blob_targets'=>[]];
try{
 $journal->append($event);$journal->append($event);journalNeed($journal->read($job)===$event&&count($journal->all())===1);
 $changed=$event;$changed['request_sha256']=str_repeat('0',64);journalReject(fn()=>$journal->append($changed));
 journalReject(fn()=>$journal->read('../outside'));
 journalReject(fn()=>(new DeletionJournal($root,random_bytes(32)))->read($job));
 $path=$root.'/'.$job.'.json';$wrapper=json_decode(file_get_contents($path),true);$wrapper['payload'].=' ';file_put_contents($path,json_encode($wrapper));journalReject(fn()=>$journal->read($job));
 echo "PASS: owner-only append-only guard, idempotent acceptance, conflicting rewrite/path/key/tamper rejection. Temporary journal only; no account deletion accepted.\n";
}finally{foreach(glob($root.'/*')?:[]as$path)if(is_file($path))unlink($path);foreach(glob($root.'/.pending-*')?:[]as$path)if(is_file($path))unlink($path);rmdir($root);}
