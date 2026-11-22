<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');umask(0077);
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/bootstrap.php';require_once __DIR__.'/../private/validation.php';require_once __DIR__.'/../private/transactions.php';require_once __DIR__.'/../private/asset_chunks.php';
use function Plenact\PrivateAuth\{connect,uuid};
use Plenact\PrivateData\{ApiFailure,AssetChunks,ValidationProcess,Transactions};
function uploadNeed(bool $ok):void{if(!$ok)throw new RuntimeException('Upload check failed');}
function uploadFailure(callable $fn,int $status):void{try{$fn();throw new LogicException('Expected failure');}catch(ApiFailure $e){uploadNeed($e->status===$status);}}
$p=null;$created=false;$failed=false;$a=uuid();$w=uuid();$epoch=uuid();
try{
 $root=getenv('HOME').'/plenact-private/model1-staging';$p=connect($root.'/config/database.json');
 $hash=$p->query("SELECT source_sha256 FROM m1_schema_migrations WHERE migration_id='004_asset_transfer'")->fetchColumn();uploadNeed($hash==='bdced641119b900fc91c4016ec400f3e03665ae091c62072912e02e454e6d26a');
 $p->beginTransaction();$p->prepare("INSERT INTO m1_accounts VALUES (?, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))")->execute([$a]);
 $p->prepare('INSERT INTO m1_workspaces VALUES (?, ?, ?, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$w,$a,$epoch]);$p->commit();$created=true;\Plenact\PrivateData\bootstrapWorkspace($p,$a);
 $validator=new ValidationProcess('/usr/bin/python3',$root.'/validation-20261121-v1/Server/model1/validation/validator.py');$engine=new Transactions($p,$validator->request(...),$validator->graph(...));
 $doc=json_decode(file_get_contents($root.'/validation-20261121-v1/Doc/Strategy/Architecture/User-Data-Model/Contracts/1.0/Fixtures/asset-opaque-original.json'));
 $first=str_repeat("\0\xffx",87381).'a';$tail="tail\0opaque\xff";$bytes=$first.$tail;
 $doc->id=uuid();$doc->workspace_id=$w;$doc->payload->account_id=$a;$doc->payload->byte_length=(string)strlen($bytes);$doc->payload->sha256=hash('sha256',$bytes);
 $request=['protocol_version'=>'1.0','user_data_model_version'=>'1.0','workspace_id'=>$w,'epoch'=>$epoch,'device_id'=>uuid(),'transaction_id'=>uuid(),
 'operations'=>[['operation_id'=>uuid(),'kind'=>'put','record_type'=>'asset','record_id'=>$doc->id,'base_revision'=>null,'document'=>$doc]]];
 $engine->commit($a,$w,$request['transaction_id'],json_encode($request,JSON_THROW_ON_ERROR));
 $now=time();$clock=static function()use(&$now):int{return $now;};$chunks=new AssetChunks($p,$clock,$validator->uploadRequest(...));
 $r=['protocol_version'=>'1.0','workspace_id'=>$w,'epoch'=>$epoch,'asset_id'=>$doc->id,'asset_revision'=>'1','byte_length'=>$doc->payload->byte_length,'sha256'=>$doc->payload->sha256];
 $session=$chunks->start($a,$w,json_encode($r,JSON_THROW_ON_ERROR));$upload=$session['upload_id'];uploadNeed($session['chunk_count']===2&&$session['received_chunks']===[]);
 $chunks->put($a,$w,$upload,1,$tail,hash('sha256',$tail));$chunks->put($a,$w,$upload,1,$tail,hash('sha256',$tail));uploadNeed($chunks->read($a,$w,$upload)['received_chunks']===[1]);
 $other=str_repeat('x',strlen($tail));uploadFailure(fn()=>$chunks->put($a,$w,$upload,1,$other,hash('sha256',$other)),409);
 uploadFailure(fn()=>$chunks->put($a,$w,$upload,0,$first,str_repeat('0',64)),422);
 uploadFailure(fn()=>$chunks->put($a,$w,$upload,0,'short',hash('sha256','short')),422);
 uploadFailure(fn()=>$chunks->put($a,$w,$upload,2,'',hash('sha256','')),400);
 uploadFailure(fn()=>$chunks->read(uuid(),$w,$upload),404);
 $chunks->put($a,$w,$upload,0,$first,hash('sha256',$first));$complete=$chunks->read($a,$w,$upload);uploadNeed($complete['received_chunks']===[0,1]);
 $s=$p->prepare('SELECT chunk_bytes FROM m1_asset_chunks WHERE upload_id=? ORDER BY chunk_index');$s->execute([$upload]);uploadNeed(hash_equals($bytes,implode('',$s->fetchAll(PDO::FETCH_COLUMN))));
 $now+=86400;uploadFailure(fn()=>$chunks->read($a,$w,$upload),410);$now=time();
 $empty=clone $doc;$empty->payload=clone $doc->payload;$empty->id=uuid();$empty->payload->byte_length='0';$empty->payload->sha256=hash('sha256','');
 $request['transaction_id']=uuid();$request['operations']=[['operation_id'=>uuid(),'kind'=>'put','record_type'=>'asset','record_id'=>$empty->id,'base_revision'=>null,'document'=>$empty]];
 $engine->commit($a,$w,$request['transaction_id'],json_encode($request,JSON_THROW_ON_ERROR));
 $z=[...$r,'asset_id'=>$empty->id,'byte_length'=>'0','sha256'=>hash('sha256','')];$zero=$chunks->start($a,$w,json_encode($z,JSON_THROW_ON_ERROR));uploadNeed($zero['chunk_count']===0&&$zero['received_chunks']===[]);
 file_put_contents($root.'/tools/asset-upload-diagnostic-responses.json',json_encode([$session,$complete,$zero],JSON_THROW_ON_ERROR));
 echo "PASS: described Asset metadata committed with strict schema/graph validation.\nPASS: binary MySQL chunks preserve null/non-UTF-8 bytes; out-of-order resume and identical retries succeed.\nPASS: conflicting retries, wrong digest/length/index, foreign owner and expired lease rejected.\nPASS: known-empty original has zero chunks. No blob published or download enabled.\n";
}catch(Throwable $e){$failed=true;if($p instanceof PDO&&$p->inTransaction())$p->rollBack();if($e instanceof ApiFailure)echo 'Failure category: ',$e->errorCode,'/',$e->status,"\n";fwrite(STDERR,"Asset upload diagnostic failed; private details omitted.\n");}
finally{if($created&&$p instanceof PDO){try{$p->beginTransaction();
 $p->prepare('DELETE c FROM m1_asset_chunks c JOIN m1_asset_uploads u ON u.upload_id=c.upload_id WHERE u.workspace_id=?')->execute([$w]);
 foreach(['m1_asset_uploads','m1_asset_blobs','m1_asset_operations','m1_operation_receipts','m1_transaction_receipts','m1_changes','m1_record_revisions','m1_record_heads','m1_workspaces']as$table)$p->prepare("DELETE FROM $table WHERE workspace_id=?")->execute([$w]);
 $p->prepare('DELETE FROM m1_accounts WHERE account_id=?')->execute([$a]);$p->commit();echo "PASS: all synthetic upload chunks, leases, records and workspace removed. Invited workspace untouched.\n";
 }catch(Throwable $e){$failed=true;if($p->inTransaction())$p->rollBack();fwrite(STDERR,"Upload diagnostic cleanup not confirmed.\n");}}}
if($failed)exit(1);
echo "Private MySQL asset staging test passed. Public asset routes remain unavailable.\n";
