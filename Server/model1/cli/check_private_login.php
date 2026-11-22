<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once __DIR__.'/../private/auth.php';
use function Plenact\PrivateAuth\{connect,email,login,authenticate,logout,reserveAttempts};
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
function verify(bool $ok): void { if (!$ok) throw new RuntimeException('Check failed'); }
$pdo=null; $token=null; $keys=[]; $failed=false;
try {
    $address=email(prompt('Existing invited account email: '));
    $password=prompt('Existing account password: ',true);
    $root=getenv('HOME').'/plenact-private/model1-staging';
    $config=json_decode(file_get_contents($root.'/config/auth.json'),true,512,JSON_THROW_ON_ERROR);
    verify(($config['enabled'] ?? null)===false);
    $pdo=connect($root.'/config/database.json');
    // Fresh diagnostic HMAC namespace avoids consuming or clearing real login limits.
    $key=random_bytes(32); $ip='192.0.2.1';
    $unknown=bin2hex(random_bytes(16)).'@example.invalid';
    $emailLimited=bin2hex(random_bytes(16)).'@example.invalid';
    foreach ([$address,$unknown,$emailLimited] as $a) $keys[]=hash_hmac('sha256','email:'.$a,$key);
    $keys[]=hash_hmac('sha256','ip:'.$ip,$key);
    verify(login($pdo,$unknown,bin2hex(random_bytes(24)),$ip,$key,$config['dummy_password_hash'])===null);
    verify(login($pdo,$address,bin2hex(random_bytes(24)),$ip,$key,$config['dummy_password_hash'])===null);
    echo "PASS: unknown account and incorrect password rejected.\n";
    $token=login($pdo,$address,$password,$ip,$key,$config['dummy_password_hash']);
    sodium_memzero($password);
    verify(is_string($token));
    $actor=authenticate($pdo,$token); verify($actor!==null);
    $s=$pdo->prepare('SELECT c.account_id, w.workspace_id FROM m1_password_credentials c JOIN m1_workspaces w ON w.owner_account_id=c.account_id WHERE c.email_normalized=?');
    $s->execute([$address]); verify($actor===$s->fetch(PDO::FETCH_ASSOC));
    $s=$pdo->prepare('SELECT token_sha256, revoked_at_utc, expires_at_utc > UTC_TIMESTAMP(6) AS live FROM m1_private_sessions WHERE token_sha256=UNHEX(?)');
    $s->execute([hash('sha256',$token)]); $row=$s->fetch(PDO::FETCH_ASSOC);
    verify($row!==false && hash_equals(hash('sha256',$token,true),$row['token_sha256']) && $row['revoked_at_utc']===null && (int)$row['live']===1);
    echo "PASS: correct password issued a hashed session for the expected private workspace.\n";
    logout($pdo,$token); verify(authenticate($pdo,$token)===null);
    logout($pdo,$token); verify(authenticate($pdo,$token)===null);
    echo "PASS: logout revoked the session; repeat logout is harmless.\n";
    for ($i=0;$i<10;$i++) verify(reserveAttempts($pdo,$emailLimited,$ip,$key));
    verify(!reserveAttempts($pdo,$emailLimited,$ip,$key));
    echo "PASS: email attempt limit rejected attempt eleven.\n";
    // Independently exercise source-IP cap, without reaching any individual email cap.
    $ip2='192.0.2.2'; $keys[]=hash_hmac('sha256','ip:'.$ip2,$key);
    for ($i=0;$i<51;$i++) {
        $a=bin2hex(random_bytes(16)).'@example.invalid';
        $keys[]=hash_hmac('sha256','email:'.$a,$key);
        verify(reserveAttempts($pdo,$a,$ip2,$key)===($i<50));
    }
    echo "PASS: source-IP attempt limit rejected attempt fifty-one.\n";
} catch (Throwable $e) {
    $failed=true;
    fwrite(STDERR,"Login diagnostic failed; no password, token or private error details displayed. Stop and report this status.\n");
} finally {
    if ($pdo instanceof PDO) {
        try {
            if (is_string($token)) {
                logout($pdo,$token); verify(authenticate($pdo,$token)===null);
            }
            foreach ($keys as $bucket) $pdo->prepare('DELETE FROM m1_login_limits WHERE bucket_key=UNHEX(?)')->execute([$bucket]);
            echo "Diagnostic limits cleared; any diagnostic session revoked. HTTP login remains disabled.\n";
        } catch (Throwable $e) {
            $failed=true; fwrite(STDERR,"Cleanup could not be confirmed; stop and report this status.\n");
        }
    }
}
if ($failed) exit(1);
echo "Private login diagnostic passed. HTTP and concurrent rate-limit tests remain pending.\n";
