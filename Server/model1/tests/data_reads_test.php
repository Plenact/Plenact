<?php
declare(strict_types=1);
require_once __DIR__.'/../private/data.php';
use Plenact\PrivateData\{ReadService,ApiFailure};
function checkRead(bool $ok,string $label): void { if (!$ok) throw new RuntimeException($label); }
function failure(callable $fn,int $status): void {
    try { $fn(); throw new LogicException('Expected failure'); }
    catch (ApiFailure $e) { checkRead($e->status===$status && $e->errorCode==='not_found','Generic not-found boundary'); }
}
$pdo=new PDO('sqlite::memory:',null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->exec('CREATE TABLE m1_accounts(account_id TEXT PRIMARY KEY,account_status TEXT); CREATE TABLE m1_workspaces(workspace_id TEXT PRIMARY KEY,owner_account_id TEXT,epoch TEXT); CREATE TABLE m1_record_heads(workspace_id TEXT,record_id TEXT,record_type TEXT,epoch TEXT,revision INTEGER); CREATE TABLE m1_record_revisions(workspace_id TEXT,epoch TEXT,record_id TEXT,record_type TEXT,revision INTEGER,server_envelope TEXT);');
$a='11111111-1111-4111-8111-111111111111';$b='22222222-2222-4222-8222-222222222222';
$wa='33333333-3333-4333-8333-333333333333';$wb='44444444-4444-4444-8444-444444444444';
$epoch='55555555-5555-4555-8555-555555555555';$id='66666666-6666-4666-8666-666666666666';
foreach ([[$a,$wa],[$b,$wb]] as [$account,$workspace]) {
    $pdo->prepare('INSERT INTO m1_accounts VALUES (?,?)')->execute([$account,'active']);
    $pdo->prepare('INSERT INTO m1_workspaces VALUES (?,?,?)')->execute([$workspace,$account,$epoch]);
}
$base=['user_data_model_version'=>'1.0','workspace_id'=>$wa,'record_type'=>'card','record_id'=>$id,
    'epoch'=>$epoch,'revision'=>'1','change_sequence'=>'1','stored_at_utc'=>'2026-11-21T00:00:00Z',
    'stored_by_account_id'=>$a,'deleted'=>true,'document'=>null,'asset_content'=>null];
$pdo->prepare('INSERT INTO m1_record_heads VALUES (?,?,?,?,?)')->execute([$wa,$id,'card',$epoch,1]);
$pdo->prepare('INSERT INTO m1_record_revisions VALUES (?,?,?,?,?,?)')->execute([$wa,$epoch,$id,'card',1,json_encode($base)]);
$service=new ReadService($pdo);
checkRead($service->read($a,$wa,'card',$id)===$base,'Owner reads immutable envelope/tombstone');
failure(fn()=>$service->read($b,$wa,'card',$id),404);
failure(fn()=>$service->read($a,$wb,'card',$id),404);
failure(fn()=>$service->read($a,$wa,'list',$id),404);
failure(fn()=>$service->read($a,$wa,'card',$b),404);
failure(fn()=>$service->read($a,$wa,"card' OR 1=1",$id),404);
$pdo->exec("UPDATE m1_accounts SET account_status='disabled' WHERE account_id='$a'");
failure(fn()=>$service->read($a,$wa,'card',$id),404);
$pdo->exec("UPDATE m1_accounts SET account_status='active' WHERE account_id='$a'");
$broken=$base;$broken['workspace_id']=$wb;
$pdo->prepare('UPDATE m1_record_revisions SET server_envelope=?')->execute([json_encode($broken)]);
try { $service->read($a,$wa,'card',$id); throw new LogicException('Expected integrity failure'); }
catch (ApiFailure $e) { checkRead($e->status===503,'Corrupt stored ownership fails closed'); }
echo "PASS: owned reads, tombstones, foreign/unknown/type boundaries, disabled owners, and envelope integrity. SQLite query integration only; MySQL/HTTP checks pending.\n";
