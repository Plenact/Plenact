<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}ini_set('display_errors','0');umask(0077);
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/bootstrap.php';require_once __DIR__.'/../private/validation.php';require_once __DIR__.'/../private/transactions.php';require_once __DIR__.'/../private/blob_files.php';
use function Plenact\PrivateAuth\{connect,uuid,passwordHash};
use Plenact\PrivateData\{Transactions,ValidationProcess,BlobFiles};
function assetNeed(bool $ok):void{if(!$ok)throw new RuntimeException('HTTP asset assertion');}
$artifacts=['sessions'=>[],'records'=>[],'errors'=>[]];
function assetHttp(string $path,string $method,string $token,?string $raw=null,array $headers=[]):array{
 global $artifacts;
 $ch=curl_init('https://plenact.com/staging/api/user-data/v1'.$path);$headers[]='Authorization: Bearer '.$token;$responseHeaders=[];
 curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_CUSTOMREQUEST=>$method,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>55,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2,CURLOPT_HTTPHEADER=>$headers,
 CURLOPT_HEADERFUNCTION=>function($ch,$line)use(&$responseHeaders){if(str_contains($line,':')){[$k,$v]=explode(':',$line,2);$responseHeaders[strtolower(trim($k))]=trim($v);}return strlen($line);}]);
 if($raw!==null)curl_setopt($ch,CURLOPT_POSTFIELDS,$raw);
 $bytes=curl_exec($ch);$status=curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);
 echo 'HTTPS asset check: ',$method,' status ',$status,"\n";
 assetNeed(is_string($bytes)&&str_contains(strtolower($responseHeaders['cache-control']??''),'no-store')&&strtolower($responseHeaders['x-content-type-options']??'')==='nosniff');
 $body=null;if(str_starts_with(strtolower($responseHeaders['content-type']??''),'application/json')){$body=json_decode($bytes,false,64,JSON_THROW_ON_ERROR);if(isset($body->error))$artifacts['errors'][]=$body;}
 return [$status,$body,$bytes,$responseHeaders];
}
function jsonAsset(string $path,string $token,array $body,array $extra=[]):array{return assetHttp($path,'POST',$token,json_encode($body,JSON_THROW_ON_ERROR),['Content-Type: application/json',...$extra]);}
$root=getenv('HOME').'/plenact-private/model1-staging';$configPath=$root.'/config/data-api.json';$pdo=null;$created=false;$enabled=false;$original=null;$failed=false;$lock=null;$phase='setup';
$a=uuid();$w=uuid();$epoch=uuid();$other=uuid();$otherW=uuid();
try{
 $lock=fopen($configPath.'.diagnostic-lock','c');assetNeed($lock!==false&&flock($lock,LOCK_EX|LOCK_NB));
 $original=file_get_contents($configPath);$config=json_decode($original,true,512,JSON_THROW_ON_ERROR);assetNeed(!$config['read_enabled']&&!$config['write_enabled']&&!($config['assets_enabled']??false));
 $pdo=connect($root.'/config/database.json');$pdo->beginTransaction();$tokens=[];
 foreach([[$a,$w,$epoch],[$other,$otherW,uuid()]]as[$account,$workspace,$ep]){
  $pdo->prepare("INSERT INTO m1_accounts VALUES (?, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))")->execute([$account]);
  $pdo->prepare('INSERT INTO m1_workspaces VALUES (?, ?, ?, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$workspace,$account,$ep]);
  $pdo->prepare('INSERT INTO m1_password_credentials VALUES (?, ?, ?, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$account,$account.'@example.invalid',passwordHash(bin2hex(random_bytes(32)))]);
  $token=bin2hex(random_bytes(32));$tokens[]=$token;$pdo->prepare('INSERT INTO m1_private_sessions VALUES (UNHEX(?), ?, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)+INTERVAL 1 HOUR, NULL)')->execute([hash('sha256',$token),$account]);
 }
 $pdo->commit();$created=true;[$token,$foreignToken]=$tokens;\Plenact\PrivateData\bootstrapWorkspace($pdo,$a);
 $validator=new ValidationProcess('/usr/bin/python3',$root.'/validation-20261121-v1/Server/model1/validation/validator.py');$engine=new Transactions($pdo,$validator->request(...),$validator->graph(...));
 $doc=json_decode(file_get_contents($root.'/validation-20261121-v1/Doc/Strategy/Architecture/User-Data-Model/Contracts/1.0/Fixtures/asset-opaque-original.json'));
 $first=str_repeat("\0\xffx",87381).'a';$tail="tail\0opaque\xff";$bytes=$first.$tail;
 $doc->id=uuid();$doc->workspace_id=$w;$doc->payload->account_id=$a;$doc->payload->byte_length=(string)strlen($bytes);$doc->payload->sha256=hash('sha256',$bytes);
 $transaction=['protocol_version'=>'1.0','user_data_model_version'=>'1.0','workspace_id'=>$w,'epoch'=>$epoch,'device_id'=>uuid(),'transaction_id'=>uuid(),'operations'=>[['operation_id'=>uuid(),'kind'=>'put','record_type'=>'asset','record_id'=>$doc->id,'base_revision'=>null,'document'=>$doc]]];
 $engine->commit($a,$w,$transaction['transaction_id'],json_encode($transaction,JSON_THROW_ON_ERROR));
 $config['read_enabled']=true;$config['write_enabled']=true;$config['assets_enabled']=true;assetNeed(file_put_contents($configPath,json_encode($config),LOCK_EX)!==false);$enabled=true;
 $base='/workspaces/'.$w.'/assets';$request=['protocol_version'=>'1.0','workspace_id'=>$w,'epoch'=>$epoch,'asset_id'=>$doc->id,'asset_revision'=>'1','byte_length'=>$doc->payload->byte_length,'sha256'=>$doc->payload->sha256];
 $phase='upload-session';[$status,$session]=jsonAsset($base.'/uploads',$token,$request);assetNeed($status===200&&$session->chunk_count===2);$artifacts['sessions'][]=$session;$upload=$session->upload_id;
 foreach([[1,$tail],[1,$tail],[0,$first]]as[$index,$chunk]){[$status]=assetHttp($base.'/uploads/'.$upload.'/chunks/'.$index,'PUT',$token,$chunk,['Content-Type: application/octet-stream','X-Chunk-SHA256: '.hash('sha256',$chunk)]);assetNeed($status===204);}
 [$status,$resume]=assetHttp($base.'/uploads/'.$upload,'GET',$token);assetNeed($status===200&&$resume->received_chunks===[0,1]);$artifacts['sessions'][]=$resume;
 [$status]=assetHttp($base.'/uploads/'.$upload,'GET',$foreignToken);assetNeed($status===404);
 [$status]=assetHttp($base.'/uploads/'.$upload.'/chunks/1','PUT',$token,str_repeat('x',strlen($tail)),['Content-Type: application/octet-stream','X-Chunk-SHA256: '.hash('sha256',str_repeat('x',strlen($tail)))]);assetNeed($status===409);
 [$status]=assetHttp($base.'/'.$doc->id.'/content','GET',$token);assetNeed($status===404);
 $phase='verified-commit';$commit=['protocol_version'=>'1.0','workspace_id'=>$w,'epoch'=>$epoch,'upload_id'=>$upload,'operation_id'=>uuid()];$raw=json_encode($commit,JSON_THROW_ON_ERROR);$headers=['Content-Type: application/json','Idempotency-Key: '.$commit['operation_id']];
 [$status,$verified]=assetHttp($base.'/uploads/'.$upload.'/commit','POST',$token,$raw,$headers);assetNeed($status===200&&$verified->revision==='2'&&$verified->asset_content->state==='verified');$artifacts['records'][]=$verified;
 [$status,$replay]=assetHttp($base.'/uploads/'.$upload.'/commit','POST',$token,$raw,$headers);assetNeed($status===200&&$replay==$verified);
 [$status]=assetHttp($base.'/uploads/'.$upload.'/commit','POST',$token,$raw.' ',$headers);assetNeed($status===409);
 $phase='range-download';[$status,$unused,$full,$h]=assetHttp($base.'/'.$doc->id.'/content','GET',$token);echo 'Synthetic ETag header: ',json_encode($h['etag']??null),"\n";echo 'Response server: ',preg_replace('/[^a-zA-Z0-9 ._-]/','',substr($h['server']??'',0,80)),"\n";echo 'Full download checks: bytes=',($full===$bytes?'yes':'no'),'; ETag=',(($h['etag']??'')==='"'.hash('sha256',$bytes).'"'?'yes':'no'),'; length=',(($h['content-length']??'')===(string)strlen($bytes)?'yes':'no'),'; attachment=',(str_starts_with($h['content-disposition']??'','attachment')?'yes':'no'),"\n";assetNeed($status===200&&$full===$bytes&&$h['etag']==='"'.hash('sha256',$bytes).'"'&&$h['content-length']===(string)strlen($bytes)&&str_starts_with($h['content-disposition'],'attachment'));
 $etag=$h['etag'];
 foreach([['bytes=2-9',$etag,206,substr($bytes,2,8)],['bytes=262144-',$etag,206,$tail],['bytes=-4',$etag,206,substr($bytes,-4)],['bytes=2-9','"other"',200,$bytes]]as[$range,$ifRange,$expected,$body]){[$status,$unused,$partial,$h]=assetHttp($base.'/'.$doc->id.'/content','GET',$token,null,['Range: '.$range,'If-Range: '.$ifRange]);assetNeed($status===$expected&&$partial===$body);if($status===206)assetNeed(isset($h['content-range']));}
 [$status,$unused,$rawError,$h]=assetHttp($base.'/'.$doc->id.'/content','GET',$token,null,['Range: bytes=999999999-']);assetNeed($status===416&&$h['content-range']==='bytes */'.strlen($bytes));
 [$status]=assetHttp($base.'/'.$doc->id.'/content','GET',$foreignToken);assetNeed($status===404);
 echo "PASS: HTTPS resume/replay/conflict, verified commit, full byte integrity, strong ETag, Range/If-Range and cross-account denial.\n";
 $phase='known-empty';$empty=clone$doc;$empty->payload=clone$doc->payload;$empty->id=uuid();$empty->payload->byte_length='0';$empty->payload->sha256=hash('sha256','');
 $transaction['transaction_id']=uuid();$transaction['operations']=[['operation_id'=>uuid(),'kind'=>'put','record_type'=>'asset','record_id'=>$empty->id,'base_revision'=>null,'document'=>$empty]];$engine->commit($a,$w,$transaction['transaction_id'],json_encode($transaction,JSON_THROW_ON_ERROR));
 $zeroRequest=[...$request,'asset_id'=>$empty->id,'byte_length'=>'0','sha256'=>hash('sha256','')];[$status,$zero]=jsonAsset($base.'/uploads',$token,$zeroRequest);assetNeed($status===200&&$zero->chunk_count===0);$artifacts['sessions'][]=$zero;
 $zeroCommit=[...$commit,'upload_id'=>$zero->upload_id,'operation_id'=>uuid()];[$status,$zeroVerified]=jsonAsset($base.'/uploads/'.$zero->upload_id.'/commit',$token,$zeroCommit,['Idempotency-Key: '.$zeroCommit['operation_id']]);assetNeed($status===200);$artifacts['records'][]=$zeroVerified;
 [$status,$unused,$body,$h]=assetHttp($base.'/'.$empty->id.'/content','GET',$token);assetNeed($status===200&&$body===''&&$h['content-length']==='0');
 echo "PASS: explicit known-empty original commits/downloads; unavailable content never masquerades as an empty success.\n";
 file_put_contents($root.'/tools/http-asset-diagnostic-responses.json',json_encode($artifacts,JSON_THROW_ON_ERROR));
}catch(Throwable$e){$failed=true;if($pdo instanceof PDO&&$pdo->inTransaction())$pdo->rollBack();echo 'Failed diagnostic phase: ',$phase,"\n";fwrite(STDERR,"HTTPS asset diagnostic failed; private details omitted.\n");}
finally{
 try{if($enabled&&is_string($original)){assetNeed(file_put_contents($configPath,$original,LOCK_EX)!==false);echo "Data and asset routes disabled again.\n";}
 if($created&&$pdo instanceof PDO){$pdo->beginTransaction();$files=new BlobFiles($root.'/assets');$s=$pdo->prepare('SELECT blob_id FROM m1_asset_blobs WHERE workspace_id=?');$s->execute([$w]);foreach($s->fetchAll(PDO::FETCH_COLUMN)as$blob){$path=$files->path($w,$blob);if(is_file($path))unlink($path);}foreach(glob($root.'/assets/'.$w.'/.partial-*')?:[]as$path)if(is_file($path))unlink($path);if(is_dir($root.'/assets/'.$w))rmdir($root.'/assets/'.$w);
 $pdo->prepare('DELETE c FROM m1_asset_chunks c JOIN m1_asset_uploads u ON u.upload_id=c.upload_id WHERE u.workspace_id=?')->execute([$w]);
 foreach(['m1_asset_uploads','m1_asset_blobs','m1_asset_operations','m1_operation_receipts','m1_transaction_receipts','m1_changes','m1_record_revisions','m1_record_heads']as$table)$pdo->prepare("DELETE FROM $table WHERE workspace_id=?")->execute([$w]);
 foreach([[$a,$w],[$other,$otherW]]as[$account,$workspace]){$pdo->prepare('DELETE FROM m1_workspaces WHERE workspace_id=?')->execute([$workspace]);foreach(['m1_private_sessions','m1_password_credentials','m1_accounts']as$table)$pdo->prepare("DELETE FROM $table WHERE account_id=?")->execute([$account]);}
 $pdo->commit();echo "Synthetic files/chunks/leases/receipts/accounts removed; invited workspace untouched.\n";}
 }catch(Throwable$e){$failed=true;if($pdo instanceof PDO&&$pdo->inTransaction())$pdo->rollBack();fwrite(STDERR,"Asset diagnostic cleanup not confirmed.\n");}
 if(is_resource($lock)){flock($lock,LOCK_UN);fclose($lock);}
}
if($failed)exit(1);echo "HTTPS verified-asset diagnostic passed. Routes remain disabled.\n";
