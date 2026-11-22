<?php
declare(strict_types=1);
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/bootstrap.php';require_once __DIR__.'/../private/cursors.php';require_once __DIR__.'/../private/sync_reads.php';
use Plenact\PrivateData\{ApiFailure,CursorCodec,SyncReads};
function ensureSync(bool $ok,string $label='check'):void{if(!$ok)throw new RuntimeException($label);}
function syncFailure(callable $fn,int $status,string $code):void{try{$fn();throw new LogicException('Expected failure');}catch(ApiFailure $e){ensureSync($e->status===$status && $e->errorCode===$code,$code);}}
class SyncPDO extends PDO {
 public function prepare(string $query,array $options=[]):PDOStatement|false{return parent::prepare(str_replace(' FOR UPDATE','',$query),$options);}
}
$pdo=new SyncPDO('sqlite::memory:',null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->exec('CREATE TABLE m1_accounts(account_id TEXT,account_status TEXT);CREATE TABLE m1_workspaces(workspace_id TEXT,owner_account_id TEXT,epoch TEXT,change_sequence INTEGER);CREATE TABLE m1_record_heads(workspace_id TEXT,record_id TEXT,record_type TEXT,epoch TEXT,revision INTEGER,change_sequence INTEGER);CREATE TABLE m1_record_revisions(workspace_id TEXT,epoch TEXT,record_id TEXT,record_type TEXT,revision INTEGER,server_envelope TEXT);CREATE TABLE m1_changes(workspace_id TEXT,epoch TEXT,change_sequence INTEGER,record_id TEXT,revision INTEGER,stored_at_utc TEXT);CREATE TABLE m1_snapshot_leases(snapshot_id TEXT,workspace_id TEXT,account_id TEXT,epoch TEXT,fence_sequence INTEGER,record_count INTEGER,created_at_utc TEXT,expires_at_utc TEXT);CREATE TABLE m1_snapshot_records(snapshot_id TEXT,ordinal INTEGER,record_type TEXT,record_id TEXT,server_envelope TEXT);');
$a='11111111-1111-4111-8111-111111111111';$w='33333333-3333-4333-8333-333333333333';$e='55555555-5555-4555-8555-555555555555';$card='66666666-6666-4666-8666-666666666666';
$now=strtotime('2026-11-21 00:00:00 UTC');$clock=static function()use(&$now):int{return $now;};
$codec=new CursorCodec(str_repeat('k',32),$clock);
$pdo->prepare('INSERT INTO m1_accounts VALUES (?,?)')->execute([$a,'active']);$pdo->prepare('INSERT INTO m1_workspaces VALUES (?,?,?,3)')->execute([$w,$a,$e]);
$envelopes=\Plenact\PrivateData\initialEnvelopes(['workspace_id'=>$w,'owner_account_id'=>$a,'epoch'=>$e],'2026-11-21T00:00:00.000Z','2026-11-21T00:00:00.000Z');
$tombstone=[...$envelopes[0],'record_type'=>'card','record_id'=>$card,'revision'=>'1','change_sequence'=>'3','deleted'=>true,'document'=>null];$envelopes[]=$tombstone;
foreach($envelopes as $r){$pdo->prepare('INSERT INTO m1_record_heads VALUES (?,?,?,?,?,?)')->execute([$w,$r['record_id'],$r['record_type'],$e,$r['revision'],$r['change_sequence']]);$pdo->prepare('INSERT INTO m1_record_revisions VALUES (?,?,?,?,?,?)')->execute([$w,$e,$r['record_id'],$r['record_type'],$r['revision'],json_encode($r)]);$pdo->prepare('INSERT INTO m1_changes VALUES (?,?,?,?,?,?)')->execute([$w,$e,$r['change_sequence'],$r['record_id'],$r['revision'],'2026-11-21 00:00:00']);}
$sync=new SyncReads($pdo,$codec,$clock,static function(string $raw):void{},1);
$offer=json_encode(['read_model_versions'=>['1.0'],'read_record_types'=>['account','workspace','card']]);
$first=$sync->start($a,$w,$offer);$pages=[$first];ensureSync($first['fence_sequence']==='3' && $first['next_change_cursor']===null);
// Append a later immutable revision after first page; frozen pages must retain the earlier one.
$new=[...$envelopes[1],'revision'=>'2','change_sequence'=>'4'];
$pdo->prepare('INSERT INTO m1_record_revisions VALUES (?,?,?,?,?,?)')->execute([$w,$e,$w,'workspace',2,json_encode($new)]);
$pdo->prepare('INSERT INTO m1_changes VALUES (?,?,?,?,?,?)')->execute([$w,$e,4,$w,2,'2026-11-21 00:00:00']);$pdo->exec("UPDATE m1_record_heads SET revision=2,change_sequence=4 WHERE record_type='workspace';UPDATE m1_workspaces SET change_sequence=4;");
$page=$first;
while($page['next_page_cursor']!==null){$next=$sync->page($a,$w,$first['snapshot_id'],$page['next_page_cursor']);ensureSync($sync->page($a,$w,$first['snapshot_id'],$page['next_page_cursor'])==$next,'Stable retry');$pages[]=$next;$page=$next;}
$records=array_merge(...array_column($pages,'records'));ensureSync(count($records)===3);
ensureSync(count(array_unique(array_map(fn($r)=>$r->record_id,$records)))===3);
foreach($records as $r)ensureSync($r->revision==='1','Frozen revision');
ensureSync($page['next_change_cursor']!==null && $page['next_page_cursor']===null);
$delta=$sync->changes($a,$w,$page['next_change_cursor']);ensureSync($delta['after_sequence']==='3' && $delta['through_sequence']==='4' && count($delta['records'])===1 && !$delta['has_more']);
$empty=$sync->changes($a,$w,$delta['next_cursor']);ensureSync($empty['records']===[] && $empty['after_sequence']==='4' && $empty['through_sequence']==='4' && !$empty['has_more']);
$token=$first['next_page_cursor'];$changed=($token[0]==='A'?'B':'A').substr($token,1);
syncFailure(fn()=>$sync->page($a,$w,$first['snapshot_id'],$changed),400,'invalid_document');
syncFailure(fn()=>$codec->read($token,'s','22222222-2222-4222-8222-222222222222',$w,$first['snapshot_id']),404,'not_found');
syncFailure(fn()=>$codec->read($token,'s',$a,$w,'22222222-2222-4222-8222-222222222222'),404,'not_found');
$pdo->exec('DELETE FROM m1_changes WHERE change_sequence=4');syncFailure(fn()=>$sync->changes($a,$w,$page['next_change_cursor']),410,'cursor_expired');
$now+=1800;syncFailure(fn()=>$sync->page($a,$w,$first['snapshot_id'],$token),410,'snapshot_expired');
$now+=90*86400;syncFailure(fn()=>$sync->changes($a,$w,$delta['next_cursor']),410,'cursor_expired');
file_put_contents('/private/tmp/plenact-sync-read-responses.json',json_encode(['snapshots'=>$pages,'changes'=>[$delta,$empty]],JSON_THROW_ON_ERROR));
echo "PASS: frozen pages/tombstones, stable retries, final fence cursor, ordered/empty deltas, tamper/owner/snapshot binding, missing-history and expiry. SQLite integration; MySQL checks pending.\n";
