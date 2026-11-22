<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') {http_response_code(404);exit;}
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/transactions.php';
use function Plenact\PrivateAuth\{connect,uuid};
use Plenact\PrivateData\{Transactions,ApiFailure};
function txCheck(bool $ok): void {if (!$ok) throw new RuntimeException('Check failed');}
function txFailure(callable $fn,string $code): void {
    try {$fn();throw new LogicException('Expected failure');}catch(ApiFailure $e){txCheck($e->errorCode===$code);}
}
$pdo=null;$a=uuid();$w=uuid();$epoch=uuid();$failed=false;
try {
    $pdo=connect(getenv('HOME').'/plenact-private/model1-staging/config/database.json');
    $pdo->beginTransaction();
    $pdo->prepare("INSERT INTO m1_accounts VALUES (?, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))")->execute([$a]);
    $pdo->prepare('INSERT INTO m1_workspaces VALUES (?, ?, ?, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$w,$a,$epoch]);
    $pdo->commit();
    // Deliberately synthetic storage-only payload. Production schema and graph validation not claimed.
    $engine=new Transactions($pdo,static function(string $raw):void{json_decode($raw,true,64,JSON_THROW_ON_ERROR);},static function(array $candidate):void{});
    $id=uuid();$op=uuid();$tid=uuid();
    $request=['protocol_version'=>'1.0','user_data_model_version'=>'1.0','workspace_id'=>$w,'epoch'=>$epoch,'device_id'=>uuid(),'transaction_id'=>$tid,
        'operations'=>[['operation_id'=>$op,'kind'=>'put','record_type'=>'card','record_id'=>$id,'base_revision'=>null,'document'=>['id'=>$id,'record_type'=>'card','workspace_id'=>$w,'payload'=>['synthetic'=>'storage test']]]]];
    $raw=json_encode($request,JSON_THROW_ON_ERROR);$receipt=$engine->commit($a,$w,$tid,$raw);
    txCheck($receipt['receipt_sequence']==='1' && $receipt['results'][0]['revision']==='1');
    txCheck($engine->commit($a,$w,$tid,$raw)==$receipt);
    txFailure(fn()=>$engine->commit($a,$w,$tid,$raw.' '),'idempotency_mismatch');
    txFailure(fn()=>$engine->commit(uuid(),$w,$tid,$raw),'not_found');
    $request['transaction_id']=uuid();$request['operations'][0]['operation_id']=uuid();
    txFailure(fn()=>$engine->commit($a,$w,$request['transaction_id'],json_encode($request)),'conflict');
    $request['operations'][0]['base_revision']='1';
    $request['operations'][0]['document']['payload']['synthetic']='updated';
    $receipt2=$engine->commit($a,$w,$request['transaction_id'],json_encode($request));
    txCheck($receipt2['receipt_sequence']==='2' && $receipt2['results'][0]['revision']==='2');
    $request['transaction_id']=uuid();$request['operations'][0]['operation_id']=uuid();$request['operations'][0]['base_revision']='2';
    $reject=new Transactions($pdo,static function(string $raw):void{},static function(array $candidate):void{throw new ApiFailure(422,'validation_failed');});
    txFailure(fn()=>$reject->commit($a,$w,$request['transaction_id'],json_encode($request)),'validation_failed');
    $s=$pdo->prepare('SELECT change_sequence FROM m1_workspaces WHERE workspace_id=?');$s->execute([$w]);txCheck((int)$s->fetchColumn()===2);
    $request['operations'][0]['kind']='delete';$request['operations'][0]['document']=null;
    $receipt3=$engine->commit($a,$w,$request['transaction_id'],json_encode($request));txCheck($receipt3['results'][0]['deleted']===true);
    $request['transaction_id']=uuid();$request['operations'][0]['operation_id']=uuid();$request['operations'][0]['base_revision']='3';
    $request['operations'][0]['kind']='put';$request['operations'][0]['document']=['id'=>$id,'record_type'=>'card','workspace_id'=>$w];
    txFailure(fn()=>$engine->commit($a,$w,$request['transaction_id'],json_encode($request)),'conflict');
    echo "PASS: commit, exact-byte replay, changed-byte rejection and owner authorization.\nPASS: revision conflicts, graph-rejection rollback, tombstones and no resurrection.\n";
} catch(Throwable $e){$failed=true;if($pdo instanceof PDO && $pdo->inTransaction())$pdo->rollBack();if($e instanceof PDOException) echo 'Database category: ',(string)($e->errorInfo[0] ?? ''),'/',(int)($e->errorInfo[1] ?? 0),"\n"; fwrite(STDERR,"Transaction storage diagnostic failed; no private details displayed.\n");}
finally {
    if($pdo instanceof PDO){try{
        $pdo->beginTransaction();
        foreach(['m1_operation_receipts','m1_transaction_receipts','m1_changes','m1_record_revisions','m1_record_heads','m1_workspaces'] as $table){
            $pdo->prepare("DELETE FROM $table WHERE workspace_id=?")->execute([$w]);
        }
        $pdo->prepare('DELETE FROM m1_accounts WHERE account_id=?')->execute([$a]);$pdo->commit();
        $s=$pdo->prepare('SELECT COUNT(*) FROM m1_accounts WHERE account_id=?');$s->execute([$a]);txCheck((int)$s->fetchColumn()===0);
        echo "PASS: dedicated synthetic account and workspace removed. No invited workspace changed.\n";
    }catch(Throwable $e){$failed=true;if($pdo->inTransaction())$pdo->rollBack();fwrite(STDERR,"Synthetic transaction cleanup not confirmed.\n");}}
}
if($failed)exit(1);
echo "Storage-engine diagnostic passed. Production typed/graph validators and HTTP writes remain unavailable.\n";
