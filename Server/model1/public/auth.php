<?php
declare(strict_types=1);
// Separate identity-service boundary; this does not implement the pinned user-data routes.
ini_set('display_errors','0');
header('Content-Type: application/json');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
function reply(int $status, array $body): never {
    http_response_code($status); echo json_encode($body, JSON_THROW_ON_ERROR); exit;
}
if (($_SERVER['HTTPS'] ?? '') !== 'on') reply(400,['error'=>'https_required']);
// Native bearer only. Browser cookie flows need a separately implemented Origin/CSRF boundary.
if (isset($_SERVER['HTTP_COOKIE']) || isset($_SERVER['HTTP_ORIGIN'])) reply(403,['error'=>'forbidden']);
try {
    $root='/home2/justirl2/plenact-private/model1-staging';
    require_once $root.'/private/auth.php';
    $c=json_decode(file_get_contents($root.'/config/auth.json'),true,512,JSON_THROW_ON_ERROR);
    if (($c['enabled'] ?? false)!==true) reply(503,['error'=>'service_unavailable']);
    $key=hex2bin($c['limiter_key_hex'] ?? '');
    if ($key===false || strlen($key)!==32 || !is_string($c['dummy_password_hash'] ?? null)) throw new RuntimeException();
    $pdo=\Plenact\PrivateAuth\connect($root.'/config/database.json');
    $action=$_GET['action'] ?? '';
    $method=$_SERVER['REQUEST_METHOD'] ?? '';
    if ($action==='login' && $method==='POST') {
        if (strtolower(trim(explode(';',$_SERVER['CONTENT_TYPE'] ?? '')[0]))!=='application/json') reply(415,['error'=>'invalid_request']);
        $raw=file_get_contents('php://input',false,null,0,4097);
        if ($raw===false || strlen($raw)>4096) reply(413,['error'=>'invalid_request']);
        try { $b=json_decode($raw,true,16,JSON_THROW_ON_ERROR); }
        catch (JsonException $e) { reply(400,['error'=>'invalid_request']); }
        if (!is_array($b) || !is_string($b['email'] ?? null) || !is_string($b['password'] ?? null)) reply(400,['error'=>'invalid_request']);
        try { \Plenact\PrivateAuth\email($b['email']); }
        catch (RuntimeException $e) { reply(401,['error'=>'unauthenticated']); }
        $token=\Plenact\PrivateAuth\login($pdo,$b['email'],$b['password'],$_SERVER['REMOTE_ADDR'] ?? '',$key,$c['dummy_password_hash']);
        if ($token===null) reply(401,['error'=>'unauthenticated']);
        reply(200,['access_token'=>$token,'token_type'=>'Bearer','expires_in'=>604800]);
    }
    if (!(($action==='me' && $method==='GET') || ($action==='logout' && $method==='POST'))) reply(404,['error'=>'not_found']);
    $header=$_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/\ABearer ([a-f0-9]{64})\z/D',$header,$m)) reply(401,['error'=>'unauthenticated']);
    $actor=\Plenact\PrivateAuth\authenticate($pdo,$m[1]);
    if ($actor===null) reply(401,['error'=>'unauthenticated']);
    if ($action==='logout') { \Plenact\PrivateAuth\logout($pdo,$m[1]); reply(200,['signed_out'=>true]); }
    reply(200,$actor);
} catch (Throwable $e) {
    if ($e instanceof RuntimeException && $e->getMessage()==='rate_limited') {
        header('Retry-After: 900'); reply(429,['error'=>'rate_limited']);
    }
    reply(503,['error'=>'service_unavailable']);
}
