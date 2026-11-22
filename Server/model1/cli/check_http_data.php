<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');umask(0077);
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/bootstrap.php';
use function Plenact\PrivateAuth\{connect,uuid,passwordHash};
function httpNeed(bool $ok):void{if(!$ok)throw new RuntimeException('Unexpected HTTP result');}
function dataRequest(string $path,string $method='GET',?string $raw=null,?string $token=null,array $extra=[]):array{
 $ch=curl_init('https://plenact.com/staging/api/user-data/v1'.$path);$headers=$extra;
 if($raw!==null)$headers[]='Content-Type: application/json';
 elseif($method==='POST')$headers[]='Content-Type: text/plain';
 if($token!==null)$headers[]='Authorization: Bearer '.$token;
 $cache='';curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_CUSTOMREQUEST=>$method,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>55,
 CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2,CURLOPT_HTTPHEADER=>$headers,
 CURLOPT_HEADERFUNCTION=>function($ch,$line)use(&$cache){if(stripos($line,'Cache-Control:')===0)$cache=trim(substr($line,14));return strlen($line);}]);
 if($raw!==null)curl_setopt($ch,CURLOPT_POSTFIELDS,$raw);elseif($method==='POST')curl_setopt($ch,CURLOPT_POSTFIELDS,'{}');
 $response=curl_exec($ch);$status=curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);
 echo 'HTTP data check: ',$method,' status ',$status,'; no-store ',str_contains(strtolower($cache),'no-store')?'yes':'no',"\n";
 httpNeed(is_string($response)&&strlen($response)<=8388608&&str_contains(strtolower($cache),'no-store'));
 $body=json_decode($response,false,64,JSON_THROW_ON_ERROR);httpNeed($body instanceof stdClass);
 return [$status,$body];
}
$root=getenv('HOME').'/plenact-private/model1-staging';$configPath=$root.'/config/data-api.json';
$pdo=null;$created=false;$original=null;$enabled=false;$failed=false;$lock=null;$artifacts=[];
try{
 $lock=fopen($configPath.'.diagnostic-lock','c');httpNeed($lock!==false&&flock($lock,LOCK_EX|LOCK_NB));
 $original=file_get_contents($configPath);$config=json_decode($original,true,512,JSON_THROW_ON_ERROR);
 httpNeed($config['read_enabled']===false&&$config['write_enabled']===false);
 $fixture=json_decode(file_get_contents(__DIR__.'/../tests/write_integration_fixture.json'),false,64,JSON_THROW_ON_ERROR);
 $a=$fixture->account_id;$w=$fixture->workspace_id;$epoch=$fixture->epoch;
 $pdo=connect($root.'/config/database.json');$pdo->beginTransaction();
 $pdo->prepare("INSERT INTO m1_accounts VALUES (?, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))")->execute([$a]);
 $pdo->prepare('INSERT INTO m1_workspaces VALUES (?, ?, ?, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$w,$a,$epoch]);
 $pdo->prepare('INSERT INTO m1_password_credentials VALUES (?, ?, ?, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$a,$a.'@example.invalid',passwordHash(bin2hex(random_bytes(32)))]);
 $token=bin2hex(random_bytes(32));
 $pdo->prepare('INSERT INTO m1_private_sessions VALUES (UNHEX(?), ?, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)+INTERVAL 1 HOUR, NULL)')->execute([hash('sha256',$token),$a]);
 $pdo->commit();$created=true;\Plenact\PrivateData\bootstrapWorkspace($pdo,$a);
 $config['read_enabled']=true;$config['write_enabled']=true;
 httpNeed(file_put_contents($configPath,json_encode($config,JSON_THROW_ON_ERROR),LOCK_EX)!==false);$enabled=true;
 [$status,$body]=dataRequest('/me');httpNeed($status===401&&$body->error->code==='unauthenticated');$artifacts['errors'][]=$body;
 [$status,$body]=dataRequest('/me','GET',null,$token);httpNeed($status===200&&$body->record_id===$a);$artifacts['records'][]=$body;
 [$status,$body]=dataRequest('/workspaces','GET',null,$token);httpNeed($status===200&&$body->record_id===$w);$artifacts['records'][]=$body;
 foreach(['/'.uuid(),'/'.$w] as $target){[$status,$body]=dataRequest('/workspaces'.$target.'/records/card/'.uuid(),'GET',null,$token);httpNeed($status===404&&$body->error->code==='not_found');$artifacts['errors'][]=$body;}
 echo "PASS: HTTPS owner records and generic foreign/unknown denial.\n";
 $ops=[];$card=null;$label=null;
 foreach($fixture->records as $doc){if(in_array($doc->record_type,['account','workspace'],true))continue;
 $ops[]=['operation_id'=>uuid(),'kind'=>'put','record_type'=>$doc->record_type,'record_id'=>$doc->id,'base_revision'=>null,'document'=>$doc];if($doc->record_type==='card')$card=$doc;if($doc->record_type==='label')$label=$doc;}
 $request=['protocol_version'=>'1.0','user_data_model_version'=>'1.0','workspace_id'=>$w,'epoch'=>$epoch,'device_id'=>uuid(),'transaction_id'=>uuid(),'operations'=>$ops];
 $raw=json_encode($request,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);$headers=['Idempotency-Key: '.$request['transaction_id']];
 [$status,$receipt]=dataRequest('/workspaces/'.$w.'/transactions','POST',$raw,$token,$headers);httpNeed($status===200);$artifacts['receipts'][]=$receipt;
 [$status,$replay]=dataRequest('/workspaces/'.$w.'/transactions','POST',$raw,$token,$headers);httpNeed($status===200&&$replay==$receipt);
 [$status,$body]=dataRequest('/workspaces/'.$w.'/transactions','POST',$raw.' ',$token,$headers);httpNeed($status===409&&$body->error->code==='idempotency_mismatch');$artifacts['errors'][]=$body;
 echo "PASS: validated HTTPS transaction, exact-byte replay and changed-byte rejection.\n";
 $stale=$request;$stale['transaction_id']=uuid();$stale['operations']=[['operation_id'=>uuid(),'kind'=>'put','record_type'=>'card','record_id'=>$card->id,'base_revision'=>null,'document'=>$card]];
 [$status,$body]=dataRequest('/workspaces/'.$w.'/transactions','POST',json_encode($stale,JSON_THROW_ON_ERROR),$token,['Idempotency-Key: '.$stale['transaction_id']]);
 httpNeed($status===409&&$body->error->code==='conflict'&&count($body->error->conflicts)===1&&$body->error->conflicts[0]->current_revision==='1');$artifacts['errors'][]=$body;
 $orphan=clone $card;$orphan->payload=clone $card->payload;$orphan->payload->list_id=uuid();
 $stale['transaction_id']=uuid();$stale['operations'][0]['operation_id']=uuid();$stale['operations'][0]['base_revision']='1';$stale['operations'][0]['document']=$orphan;
 [$status,$body]=dataRequest('/workspaces/'.$w.'/transactions','POST',json_encode($stale,JSON_THROW_ON_ERROR),$token,['Idempotency-Key: '.$stale['transaction_id']]);
 httpNeed($status===422&&$body->error->code==='validation_failed');$artifacts['errors'][]=$body;
 echo "PASS: HTTPS revision conflict includes current state; orphan membership rejected.\n";

 $more=[];httpNeed($label instanceof stdClass);
 for($i=0;$i<80;$i++){$copy=clone $label;$copy->id=uuid();$more[]=['operation_id'=>uuid(),'kind'=>'put','record_type'=>'label','record_id'=>$copy->id,'base_revision'=>null,'document'=>$copy];}
 $request['transaction_id']=uuid();$request['operations']=$more;
 [$status,$receipt]=dataRequest('/workspaces/'.$w.'/transactions','POST',json_encode($request,JSON_THROW_ON_ERROR),$token,['Idempotency-Key: '.$request['transaction_id']]);httpNeed($status===200);$artifacts['receipts'][]=$receipt;
 $offer=json_encode(['protocol_version'=>'1.0','device_id'=>uuid(),'platform'=>'ios','application_version'=>'https-diagnostic','read_model_versions'=>['1.0'],'write_model_versions'=>[],'read_record_types'=>[],'write_record_types'=>[]],JSON_THROW_ON_ERROR);
 [$status,$first]=dataRequest('/workspaces/'.$w.'/snapshots','POST',$offer,$token);httpNeed($status===200&&$first->next_page_cursor!==null&&$first->next_change_cursor===null);
 $artifacts['snapshots'][]=$first;
 $request['transaction_id']=uuid();$request['operations']=[['operation_id'=>uuid(),'kind'=>'put','record_type'=>'card','record_id'=>$card->id,'base_revision'=>'1','document'=>$card]];
 [$status,$receipt]=dataRequest('/workspaces/'.$w.'/transactions','POST',json_encode($request,JSON_THROW_ON_ERROR),$token,['Idempotency-Key: '.$request['transaction_id']]);httpNeed($status===200);$artifacts['receipts'][]=$receipt;
 $page=$first;$records=$first->records;
 while($page->next_page_cursor!==null){[$status,$page]=dataRequest('/workspaces/'.$w.'/snapshots/'.$first->snapshot_id.'?page_cursor='.rawurlencode($page->next_page_cursor),'GET',null,$token);httpNeed($status===200);$artifacts['snapshots'][]=$page;$records=[...$records,...$page->records];}
 httpNeed(count($records)===count($fixture->records)+80&&count(array_unique(array_map(fn($r)=>$r->record_id,$records)))===count($records));
 foreach($records as $record)httpNeed($record->revision==='1');
 [$status,$delta]=dataRequest('/workspaces/'.$w.'/changes?cursor='.rawurlencode($page->next_change_cursor),'GET',null,$token);httpNeed($status===200&&count($delta->records)===1&&$delta->records[0]->revision==='2');$artifacts['changes'][]=$delta;
 [$status,$empty]=dataRequest('/workspaces/'.$w.'/changes?cursor='.rawurlencode($delta->next_cursor),'GET',null,$token);httpNeed($status===200&&$empty->records===[]&&!$empty->has_more);$artifacts['changes'][]=$empty;
 echo "PASS: multi-page HTTPS snapshot stayed frozen across a write; ordered and empty changes followed its fence.\n";
 $pdo->prepare('UPDATE m1_private_sessions SET revoked_at_utc=UTC_TIMESTAMP(6) WHERE token_sha256=UNHEX(?)')->execute([hash('sha256',$token)]);
 [$status,$body]=dataRequest('/me','GET',null,$token);httpNeed($status===401);$artifacts['errors'][]=$body;
 file_put_contents($root.'/tools/http-data-diagnostic-responses.json',json_encode($artifacts,JSON_THROW_ON_ERROR));
 echo "PASS: revoked bearer rejected over HTTPS.\n";
}catch(Throwable $e){$failed=true;if($pdo instanceof PDO&&$pdo->inTransaction())$pdo->rollBack();fwrite(STDERR,"HTTPS data diagnostic failed; no private details displayed.\n");}
finally{
 try{if($enabled&&is_string($original)){httpNeed(file_put_contents($configPath,$original,LOCK_EX)!==false);echo "Data API read/write routes disabled again.\n";}
 if($created&&$pdo instanceof PDO){$pdo->beginTransaction();
 $pdo->prepare('DELETE r FROM m1_snapshot_records r JOIN m1_snapshot_leases l ON l.snapshot_id=r.snapshot_id WHERE l.workspace_id=?')->execute([$w]);
 $pdo->prepare('DELETE FROM m1_snapshot_leases WHERE workspace_id=?')->execute([$w]);
 foreach(['m1_operation_receipts','m1_transaction_receipts','m1_changes','m1_record_revisions','m1_record_heads','m1_workspaces'] as $table)$pdo->prepare("DELETE FROM $table WHERE workspace_id=?")->execute([$w]);
 foreach(['m1_private_sessions','m1_password_credentials','m1_accounts'] as $table)$pdo->prepare("DELETE FROM $table WHERE account_id=?")->execute([$a]);
 $pdo->commit();echo "Synthetic account, sessions, snapshots and workspace removed; invited workspace untouched.\n";}
 }catch(Throwable $e){$failed=true;if($pdo instanceof PDO&&$pdo->inTransaction())$pdo->rollBack();fwrite(STDERR,"Cleanup not confirmed; stop and inspect staging flags.\n");}
 if(is_resource($lock)){flock($lock,LOCK_UN);fclose($lock);}
}
if($failed)exit(1);
[$status,$body]=dataRequest('/me');httpNeed($status===503);$artifacts['errors'][]=$body;
file_put_contents($root.'/tools/http-data-diagnostic-responses.json',json_encode($artifacts,JSON_THROW_ON_ERROR));
echo "HTTPS data API diagnostic passed. Routes are disabled.\n";
