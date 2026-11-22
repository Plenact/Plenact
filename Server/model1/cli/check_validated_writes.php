<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/bootstrap.php';require_once __DIR__.'/../private/transactions.php';require_once __DIR__.'/../private/validation.php';
use function Plenact\PrivateAuth\{connect,uuid};
use Plenact\PrivateData\{ValidationProcess,Transactions,ReadService,ApiFailure};
function validCheck(bool $ok):void{if(!$ok)throw new RuntimeException('Check failed');}
$pdo=null;$created=false;$failed=false;
try{
 $root=getenv('HOME').'/plenact-private/model1-staging';
 $f=json_decode(file_get_contents(__DIR__.'/../tests/write_integration_fixture.json'),false,64,JSON_THROW_ON_ERROR);
 $a=$f->account_id;$w=$f->workspace_id;$epoch=$f->epoch;
 $pdo=connect($root.'/config/database.json');
 $pdo->beginTransaction();
 $pdo->prepare("INSERT INTO m1_accounts VALUES (?, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))")->execute([$a]);
 $pdo->prepare('INSERT INTO m1_workspaces VALUES (?, ?, ?, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$w,$a,$epoch]);
 $pdo->commit();$created=true;
 \Plenact\PrivateData\bootstrapWorkspace($pdo,$a);
 $v=new ValidationProcess('/usr/bin/python3',$root.'/validation-20261121-v1/Server/model1/validation/validator.py');
 $engine=new Transactions($pdo,$v->request(...),$v->graph(...));
 $ops=[];$card=null;
 foreach($f->records as $doc){if(in_array($doc->record_type,['account','workspace'],true))continue;
  $ops[]=['operation_id'=>uuid(),'kind'=>'put','record_type'=>$doc->record_type,'record_id'=>$doc->id,'base_revision'=>null,'document'=>$doc];
  if($doc->record_type==='card')$card=$doc;
 }
 $request=['protocol_version'=>'1.0','user_data_model_version'=>'1.0','workspace_id'=>$w,'epoch'=>$epoch,'device_id'=>uuid(),'transaction_id'=>uuid(),'operations'=>$ops];
 $raw=json_encode($request,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
 $r=$engine->commit($a,$w,$request['transaction_id'],$raw);
 validCheck(count($r['results'])===count($ops));validCheck($engine->commit($a,$w,$request['transaction_id'],$raw)==$r);
 echo "PASS: strict request and whole-graph validation committed a complete synthetic workspace; exact-byte replay returned its receipt.\n";
 $service=new ReadService($pdo);$read=$service->read($a,$w,'card',$card->id);
 validCheck($read['document']==$card);
 echo "PASS: stored card JSON round-trips without changing object/array identity.\n";
 $broken=clone $card;$broken->payload=clone $card->payload;$broken->payload->list_id=uuid();
 $request['transaction_id']=uuid();$request['operations']=[['operation_id'=>uuid(),'kind'=>'put','record_type'=>'card','record_id'=>$card->id,'base_revision'=>'1','document'=>$broken]];
 try{$engine->commit($a,$w,$request['transaction_id'],json_encode($request,JSON_THROW_ON_ERROR));throw new LogicException('Invalid graph passed');}
 catch(ApiFailure $e){validCheck($e->status===422);}
 $read=$service->read($a,$w,'card',$card->id);validCheck($read['revision']==='1' && $read['document']==$card);
 $s=$pdo->prepare('SELECT COUNT(*) FROM m1_transaction_receipts WHERE workspace_id=? AND transaction_id=?');$s->execute([$w,$request['transaction_id']]);validCheck((int)$s->fetchColumn()===0);
 echo "PASS: orphan membership rejected; previous record and receipt state preserved.\n";
}catch(Throwable $e){$failed=true;if($pdo instanceof PDO && $pdo->inTransaction())$pdo->rollBack();if($e instanceof ApiFailure)echo 'Failure category: ',$e->errorCode,'/',$e->status,"\n";fwrite(STDERR,"Validated write diagnostic failed; private details omitted.\n");}
finally{
 if($created && $pdo instanceof PDO){try{$pdo->beginTransaction();
 foreach(['m1_operation_receipts','m1_transaction_receipts','m1_changes','m1_record_revisions','m1_record_heads','m1_workspaces'] as $table)$pdo->prepare("DELETE FROM $table WHERE workspace_id=?")->execute([$w]);
 $pdo->prepare('DELETE FROM m1_accounts WHERE account_id=?')->execute([$a]);$pdo->commit();
 echo "PASS: dedicated synthetic workspace removed; invited workspace untouched.\n";
 }catch(Throwable $e){$failed=true;if($pdo->inTransaction())$pdo->rollBack();fwrite(STDERR,"Diagnostic cleanup not confirmed.\n");}}
}
if($failed)exit(1);
echo "Validated MySQL writes passed privately. Public data writes remain disabled.\n";
