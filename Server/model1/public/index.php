<?php
declare(strict_types=1);
ini_set('display_errors','0');
header('Content-Type: application/json');header('Cache-Control: no-store');header('X-Content-Type-Options: nosniff');
$root='/home2/justirl2/plenact-private/model1-staging';
require_once $root.'/private/auth.php';require_once $root.'/private/data.php';
use Plenact\PrivateData\{ApiFailure,ReadService,Transactions,ValidationProcess,CursorCodec,SyncReads};
$requestId=\Plenact\PrivateAuth\uuid();
function sendData(int $status,array $value): never {http_response_code($status);echo json_encode($value,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);exit;}
function requestBody():string {
    if(strtolower(trim(explode(';',$_SERVER['CONTENT_TYPE'] ?? '')[0]))!=='application/json')throw new ApiFailure(415,'invalid_document');
    if(strtolower($_SERVER['HTTP_CONTENT_ENCODING'] ?? 'identity')!=='identity')throw new ApiFailure(415,'invalid_document');
    $raw=file_get_contents('php://input',false,null,0,8388609);
    if($raw===false)throw new ApiFailure(400,'invalid_document');
    if(strlen($raw)>8388608)throw new ApiFailure(413,'payload_too_large');
    return $raw;
}
try {
    if(($_SERVER['HTTPS'] ?? '')!=='on')throw new ApiFailure(400,'invalid_document');
    if(isset($_SERVER['HTTP_COOKIE']) || isset($_SERVER['HTTP_ORIGIN']))throw new ApiFailure(403,'forbidden');
    $config=json_decode(file_get_contents($root.'/config/data-api.json'),true,512,JSON_THROW_ON_ERROR);
    if(($config['read_enabled'] ?? false)!==true)throw new ApiFailure(503,'invalid_document','retry_later');
    $path=$_SERVER['PATH_INFO'] ?? '';$method=$_SERVER['REQUEST_METHOD'] ?? '';
    // Full capabilities remain unavailable until asset and lifecycle routes are implemented.
    if($path==='/capabilities')throw new ApiFailure(503,'invalid_document','retry_later');
    $pdo=\Plenact\PrivateAuth\connect($root.'/config/database.json');
    $header=$_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if(!preg_match('/\ABearer ([a-f0-9]{64})\z/D',$header,$m))throw new ApiFailure(401,'unauthenticated','reauthenticate');
    $actor=\Plenact\PrivateAuth\authenticate($pdo,$m[1]);
    if($actor===null)throw new ApiFailure(401,'unauthenticated','reauthenticate');
    $service=new ReadService($pdo);
    if($method==='GET' && $path==='/me')sendData(200,$service->account($actor['account_id']));
    if($method==='GET' && $path==='/workspaces')sendData(200,$service->workspace($actor['account_id']));
    if($method==='GET' && preg_match('~\A/workspaces/([0-9a-f-]{36})/records/([a-z_]{1,64})/([0-9a-f-]{36})\z~D',$path,$parts))sendData(200,$service->read($actor['account_id'],$parts[1],$parts[2],$parts[3]));
    require_once $root.'/private/transactions.php';require_once $root.'/private/validation.php';require_once $root.'/private/cursors.php';require_once $root.'/private/sync_reads.php';
    $validator=new ValidationProcess('/usr/bin/python3',$root.'/validation-20261121-v1/Server/model1/validation/validator.py');
    $key=hex2bin($config['cursor_key_hex'] ?? '');
    if($key===false || strlen($key)!==32)throw new ApiFailure(503,'invalid_document','retry_later');
    $clock=static fn():int=>time();$codec=new CursorCodec($key,$clock);
    $sync=new SyncReads($pdo,$codec,$clock,$validator->offer(...));
    if($method==='POST' && preg_match('~\A/workspaces/([0-9a-f-]{36})/snapshots\z~D',$path,$parts))sendData(200,$sync->start($actor['account_id'],$parts[1],requestBody()));
    if($method==='GET' && preg_match('~\A/workspaces/([0-9a-f-]{36})/snapshots/([0-9a-f-]{36})\z~D',$path,$parts)){
        if(!is_string($_GET['page_cursor'] ?? null))throw new ApiFailure(400,'invalid_document');
        sendData(200,$sync->page($actor['account_id'],$parts[1],$parts[2],$_GET['page_cursor']));
    }
    if($method==='GET' && preg_match('~\A/workspaces/([0-9a-f-]{36})/changes\z~D',$path,$parts)){
        if(!is_string($_GET['cursor'] ?? null))throw new ApiFailure(400,'invalid_document');
        sendData(200,$sync->changes($actor['account_id'],$parts[1],$_GET['cursor']));
    }
    if(preg_match('~\A/workspaces/([0-9a-f-]{36})/assets/~D',$path)){
        if(($config['assets_enabled'] ?? false)!==true)throw new ApiFailure(503,'invalid_document','retry_later');
        if($method!=='GET' && ($config['write_enabled'] ?? false)!==true)throw new ApiFailure(503,'invalid_document','retry_later');
        require_once $root.'/private/asset_chunks.php';require_once $root.'/private/blob_files.php';require_once $root.'/private/asset_content.php';
        $chunks=new \Plenact\PrivateData\AssetChunks($pdo,$clock,$validator->uploadRequest(...));
        $content=new \Plenact\PrivateData\AssetContent($pdo,new \Plenact\PrivateData\BlobFiles($root.'/assets'),$clock,$validator->uploadCommit(...));
        if($method==='POST' && preg_match('~\A/workspaces/([0-9a-f-]{36})/assets/uploads\z~D',$path,$parts))sendData(200,$chunks->start($actor['account_id'],$parts[1],requestBody()));
        if($method==='GET' && preg_match('~\A/workspaces/([0-9a-f-]{36})/assets/uploads/([0-9a-f-]{36})\z~D',$path,$parts))sendData(200,$chunks->read($actor['account_id'],$parts[1],$parts[2]));
        if($method==='PUT' && preg_match('~\A/workspaces/([0-9a-f-]{36})/assets/uploads/([0-9a-f-]{36})/chunks/([0-9]{1,10})\z~D',$path,$parts)){
            if(strtolower(trim(explode(';',$_SERVER['CONTENT_TYPE'] ?? '')[0]))!=='application/octet-stream'||strtolower($_SERVER['HTTP_CONTENT_ENCODING'] ?? 'identity')!=='identity')throw new ApiFailure(415,'invalid_document');
            if((int)$parts[3]>2147483647)throw new ApiFailure(400,'invalid_document');
            $hash=$_SERVER['HTTP_X_CHUNK_SHA256'] ?? '';if(!preg_match('/\A[a-f0-9]{64}\z/D',$hash))throw new ApiFailure(400,'invalid_document');
            $bytes=file_get_contents('php://input',false,null,0,262145);if($bytes===false)throw new ApiFailure(400,'invalid_document');
            $chunks->put($actor['account_id'],$parts[1],$parts[2],(int)$parts[3],$bytes,$hash);http_response_code(204);exit;
        }
        if($method==='POST' && preg_match('~\A/workspaces/([0-9a-f-]{36})/assets/uploads/([0-9a-f-]{36})/commit\z~D',$path,$parts)){
            $id=$_SERVER['HTTP_IDEMPOTENCY_KEY'] ?? '';if(!\Plenact\PrivateData\uuidValid($id))throw new ApiFailure(400,'invalid_document');
            sendData(200,$content->commit($actor['account_id'],$parts[1],$parts[2],$id,requestBody()));
        }
        if($method==='GET' && preg_match('~\A/workspaces/([0-9a-f-]{36})/assets/([0-9a-f-]{36})/content\z~D',$path,$parts)){
            $download=$content->download($actor['account_id'],$parts[1],$parts[2]);$size=$download['byte_length'];
            try{[$status,$start,$length]=\Plenact\PrivateData\ByteRange::select($size,$_SERVER['HTTP_RANGE'] ?? null,$_SERVER['HTTP_IF_RANGE'] ?? null,$download['etag']);}
            catch(ApiFailure $e){fclose($download['stream']);if($e->status===416)header('Content-Range: bytes */'.$size);throw $e;}
            http_response_code($status);header('Content-Type: application/octet-stream');header('Content-Disposition: attachment; filename="asset.bin"');
            header('ETag: '.$download['etag']);header('X-Plenact-Verified-ETag: '.$download['etag']);header('Accept-Ranges: bytes');header('Content-Length: '.$length);
            if($status===206)header('Content-Range: bytes '.$start.'-'.($start+$length-1).'/'.$size);
            if(fseek($download['stream'],$start)!==0){fclose($download['stream']);exit;}
            while($length>0){$part=fread($download['stream'],min(65536,$length));if($part===false||$part==='')break;echo $part;$length-=strlen($part);}
            fclose($download['stream']);exit;
        }
    }
    if($method==='POST' && preg_match('~\A/workspaces/([0-9a-f-]{36})/transactions\z~D',$path,$parts)){
        if(($config['write_enabled'] ?? false)!==true)throw new ApiFailure(503,'invalid_document','retry_later');
        $id=$_SERVER['HTTP_IDEMPOTENCY_KEY'] ?? '';
        if(!\Plenact\PrivateData\uuidValid($id))throw new ApiFailure(400,'invalid_document');
        $engine=new Transactions($pdo,$validator->request(...),$validator->graph(...));
        sendData(200,$engine->commit($actor['account_id'],$parts[1],$id,requestBody()));
    }
    throw new ApiFailure(404,'not_found');
}catch(ApiFailure $e){sendData($e->status,\Plenact\PrivateData\errorBody($e,$requestId));}
catch(Throwable $e){$failure=new ApiFailure(503,'invalid_document','retry_later');sendData(503,\Plenact\PrivateData\errorBody($failure,$requestId));}
