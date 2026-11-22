<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') { http_response_code(404); exit; }
ini_set('display_errors','0');
require_once __DIR__.'/../private/auth.php';
function prompt(string $label, bool $secret=false): string {
    $tty=fopen('/dev/tty','r+');
    if (!$tty) throw new RuntimeException('Interactive terminal required');
    fwrite($tty,$label);
    $mode=null;
    try {
        if ($secret) {
            $mode=trim((string)shell_exec('stty -g < /dev/tty'));
            if ($mode==='' || !preg_match('/\A[0-9a-f:;]+\z/i',$mode)) throw new RuntimeException('Cannot hide input');
            exec('stty -echo < /dev/tty', $out, $status);
            if ($status!==0) throw new RuntimeException('Cannot hide input');
        }
        $line=fgets($tty,2048);
        if ($line===false || !str_ends_with($line,"\n")) throw new RuntimeException('Input incomplete');
        return rtrim($line,"\r\n");
    } finally {
        if ($mode!==null && $mode!=='') exec('stty '.escapeshellarg($mode).' < /dev/tty');
        if ($secret) fwrite($tty,"\n");
        fclose($tty);
    }
}
function requireHttp(bool $ok): void { if (!$ok) throw new RuntimeException('Unexpected response'); }
function requestHttp(string $action,string $method='GET',?array $body=null,?string $token=null,array $extra=[]): array {
    $ch=curl_init('https://plenact.com/staging/api/user-data/v1/auth.php?action='.$action);
    $headers=$extra;
    if ($body!==null) $headers[]='Content-Type: application/json';
    elseif ($method==='POST') $headers[]='Content-Type: text/plain';
    if ($token!==null) $headers[]='Authorization: Bearer '.$token;
    $responseHeaders=[];
    curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>false,
        CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>20,CURLOPT_CUSTOMREQUEST=>$method,
        CURLOPT_HTTPHEADER=>$headers,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2,
        CURLOPT_HEADERFUNCTION=>function($ch,$line) use (&$responseHeaders) {
            if (str_contains($line,':')) { [$k,$v]=explode(':',$line,2); $responseHeaders[strtolower(trim($k))]=trim($v); }
            return strlen($line);
        }]);
    if ($body!==null) curl_setopt($ch,CURLOPT_POSTFIELDS,json_encode($body,JSON_THROW_ON_ERROR));
    elseif ($method==='POST') curl_setopt($ch,CURLOPT_POSTFIELDS,'{}');
    $raw=curl_exec($ch); $status=curl_getinfo($ch,CURLINFO_HTTP_CODE); curl_close($ch);
    echo 'HTTP check ',$action,' ',$method,': status ',$status,
        '; transport ',is_string($raw) ? 'ok' : 'failed',
        '; no-store ',str_contains(strtolower($responseHeaders['cache-control'] ?? ''),'no-store') ? 'yes' : 'no',"\n";
    requireHttp(is_string($raw) && strlen($raw)<16384);
    try { $json=json_decode($raw,true,16,JSON_THROW_ON_ERROR); }
    catch (JsonException $e) { echo "Response format: not JSON\n"; throw $e; }
    $error=is_array($json) ? ($json['error'] ?? null) : null;
    if (is_string($error) && in_array($error,['https_required','forbidden','service_unavailable','unauthenticated','invalid_request','not_found','rate_limited'],true)) {
        echo 'Response category: ',$error,"\n";
    }
    requireHttp(is_array($json) && str_contains(strtolower($responseHeaders['cache-control'] ?? ''),'no-store'));
    return [$status,$json];
}
function saveConfig(string $path,string $bytes): void {
    $tmp=$path.'.check-'.bin2hex(random_bytes(8));
    try {
        requireHttp(file_put_contents($tmp,$bytes,LOCK_EX)===strlen($bytes));
        requireHttp(chmod($tmp,0600)); requireHttp(rename($tmp,$path));
    } finally { if (file_exists($tmp)) unlink($tmp); }
}
$path=getenv('HOME').'/plenact-private/model1-staging/config/auth.json';
$original=null; $enabled=false; $token=null; $failed=false; $lock=null;
try {
    umask(0077);
    $lock=fopen($path.'.diagnostic-lock','c');
    requireHttp($lock!==false && flock($lock,LOCK_EX|LOCK_NB));
    $original=file_get_contents($path); requireHttp(is_string($original));
    $config=json_decode($original,true,512,JSON_THROW_ON_ERROR);
    requireHttp(($config['enabled'] ?? null)===false);
    $address=prompt('Existing invited account email: ');
    $password=prompt('Existing account password: ',true);
    $config['enabled']=true;
    saveConfig($path,json_encode($config,JSON_THROW_ON_ERROR|JSON_PRETTY_PRINT)."\n"); $enabled=true;
    echo "Staging HTTP login temporarily enabled for diagnostic.\n";
    [$status,$body]=requestHttp('me'); requireHttp($status===401 && ($body['error'] ?? '')==='unauthenticated');
    [$status,$body]=requestHttp('me','GET',null,null,['Origin: https://example.invalid']); requireHttp($status===403);
    [$status,$body]=requestHttp('me','GET',null,null,['Cookie: diagnostic=1']); requireHttp($status===403);
    [$status,$body]=requestHttp('login','POST'); requireHttp($status===415);
    echo "PASS: missing session, browser Origin/cookie and invalid media rejected.\n";
    [$status,$body]=requestHttp('login','POST',['email'=>$address,'password'=>bin2hex(random_bytes(24))]);
    requireHttp($status===401 && ($body['error'] ?? '')==='unauthenticated');
    [$status,$body]=requestHttp('login','POST',['email'=>$address,'password'=>$password]);
    sodium_memzero($password);
    $token=$body['access_token'] ?? null;
    requireHttp($status===200 && is_string($token) && preg_match('/\A[a-f0-9]{64}\z/D',$token));
    [$status,$actor]=requestHttp('me','GET',null,$token); requireHttp($status===200);
    $pdo=\Plenact\PrivateAuth\connect(getenv('HOME').'/plenact-private/model1-staging/config/database.json');
    requireHttp($actor===\Plenact\PrivateAuth\authenticate($pdo,$token));
    echo "PASS: incorrect password rejected; correct password and bearer session resolve to expected workspace.\n";
    [$status,$body]=requestHttp('logout','POST',null,$token); requireHttp($status===200 && ($body['signed_out'] ?? null)===true);
    [$status,$body]=requestHttp('me','GET',null,$token); requireHttp($status===401);
    echo "PASS: HTTP logout invalidates bearer access; responses use no-store.\n";
} catch (Throwable $e) {
    $failed=true; fwrite(STDERR,"HTTPS diagnostic failed; no credentials or raw response displayed. Stop and report this status.\n");
} finally {
    try {
        // Disable the public route before any database cleanup, even after a failed request.
        if ($enabled && is_string($original)) { saveConfig($path,$original); echo "HTTP login disabled again.\n"; }
        if (is_string($token)) {
            $pdo=\Plenact\PrivateAuth\connect(getenv('HOME').'/plenact-private/model1-staging/config/database.json');
            \Plenact\PrivateAuth\logout($pdo,$token);
            requireHttp(\Plenact\PrivateAuth\authenticate($pdo,$token)===null);
            echo "Diagnostic session revoked.\n";
        }
    } catch (Throwable $e) { $failed=true; fwrite(STDERR,"Cleanup could not be confirmed; disable auth.json enabled flag before continuing.\n"); }
    if (is_resource($lock)) { flock($lock,LOCK_UN); fclose($lock); }
}
if ($failed) exit(1);
[$status,$body]=requestHttp('me');
requireHttp($status===503 && ($body['error'] ?? '')==='service_unavailable');
echo "PASS: disabled endpoint returns HTTP 503. HTTPS authentication diagnostic passed.\n";
