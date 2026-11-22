<?php
declare(strict_types=1);
namespace Plenact\PrivateAuth;
use PDO;
use RuntimeException;

function email(string $value): string {
    $value = strtolower(trim($value));
    if (strlen($value) > 254 || !preg_match('/\A[\x21-\x7e]+\z/D', $value)
        || !filter_var($value, FILTER_VALIDATE_EMAIL)) {
        throw new RuntimeException('Invalid email');
    }
    return $value;
}
function passwordHash(string $password): string {
    if (strlen($password) < 15 || strlen($password) > 1024 || str_contains($password, "\0")) {
        throw new RuntimeException('Use a password of 15–1024 bytes without null characters');
    }
    // Sodium is required on staging; never silently fall back to truncated bcrypt passwords.
    return sodium_crypto_pwhash_str($password, SODIUM_CRYPTO_PWHASH_OPSLIMIT_INTERACTIVE,
        SODIUM_CRYPTO_PWHASH_MEMLIMIT_INTERACTIVE);
}
function uuid(): string {
    $b = random_bytes(16);
    $b[6] = chr((ord($b[6]) & 15) | 64);
    $b[8] = chr((ord($b[8]) & 63) | 128);
    $h = bin2hex($b);
    return substr($h,0,8).'-'.substr($h,8,4).'-'.substr($h,12,4).'-'.substr($h,16,4).'-'.substr($h,20);
}
function connect(string $path): PDO {
    $c = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
    if (($c['database'] ?? '') !== 'justirl2_plenact_m1_stage' || ($c['host'] ?? '') !== 'localhost') {
        throw new RuntimeException('Staging configuration required');
    }
    $pdo = new PDO('mysql:host=localhost;dbname=justirl2_plenact_m1_stage;charset=utf8mb4',
        $c['username'], $c['password'], [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_EMULATE_PREPARES=>false, PDO::ATTR_TIMEOUT=>5]);
    $pdo->exec("SET time_zone = '+00:00'");
    return $pdo;
}
function provision(PDO $pdo, string $address, string $password): array {
    $address = email($address);
    $hash = passwordHash($password);
    $account = uuid(); $workspace = uuid(); $epoch = uuid();
    $pdo->beginTransaction();
    try {
        $pdo->prepare("INSERT INTO m1_accounts VALUES (?, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))")
            ->execute([$account]);
        $pdo->prepare('INSERT INTO m1_workspaces VALUES (?, ?, ?, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')
            ->execute([$workspace,$account,$epoch]);
        $pdo->prepare('INSERT INTO m1_password_credentials VALUES (?, ?, ?, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')
            ->execute([$account,$address,$hash]);
        $pdo->commit();
        return ['account_id'=>$account,'workspace_id'=>$workspace];
    } catch (\Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $e; }
}
// Reserve attempts in a separate committed transaction; failed passwords must not roll these back.
function reserveAttempts(PDO $pdo, string $address, string $ip, string $key): bool {
    if (strlen($key) < 32 || !filter_var($ip, FILTER_VALIDATE_IP)) throw new RuntimeException('Invalid limiter configuration');
    $buckets = [hash_hmac('sha256', 'email:'.$address, $key)=>10,
        hash_hmac('sha256', 'ip:'.$ip, $key)=>50];
    ksort($buckets);
    for ($attempt=0; $attempt<5; $attempt++) {
    $pdo->beginTransaction();
    try {
        $allowed = true;
        foreach ($buckets as $bucket=>$limit) {
            $pdo->prepare('INSERT IGNORE INTO m1_login_limits VALUES (UNHEX(?), UTC_TIMESTAMP(6), 0)')->execute([$bucket]);
            $s=$pdo->prepare('SELECT attempt_count, window_started_at_utc <= UTC_TIMESTAMP(6) - INTERVAL 15 MINUTE AS expired FROM m1_login_limits WHERE bucket_key=UNHEX(?) FOR UPDATE');
            $s->execute([$bucket]); $r=$s->fetch(PDO::FETCH_ASSOC);
            $count = $r['expired'] ? 0 : (int)$r['attempt_count'];
            $allowed = $allowed && $count < $limit;
            $s=$pdo->prepare('UPDATE m1_login_limits SET attempt_count=?, window_started_at_utc=IF(?, UTC_TIMESTAMP(6), window_started_at_utc) WHERE bucket_key=UNHEX(?)');
            $s->execute([min($count+1,1000000),(int)$r['expired'],$bucket]);
        }
        $pdo->commit(); return $allowed;
    } catch (\Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        // A rolled-back attempt has consumed no quota. Never retry a successful commit.
        $driver=$e instanceof \PDOException ? (int)($e->errorInfo[1] ?? 0) : 0;
        if (!in_array($driver,[1213,1205],true) || $attempt===4) throw $e;
        usleep(random_int(10000,40000) * ($attempt+1));
    }
    }
    throw new RuntimeException('Limiter retry exhausted');
}
function login(PDO $pdo, string $address, string $password, string $ip, string $key, string $dummyHash): ?string {
    $address=email($address);
    if (!reserveAttempts($pdo,$address,$ip,$key)) throw new RuntimeException('rate_limited');
    if (strlen($password)>1024 || str_contains($password,"\0")) return null;
    $s=$pdo->prepare('SELECT c.*, a.account_status FROM m1_password_credentials c JOIN m1_accounts a ON a.account_id=c.account_id WHERE email_normalized=?');
    $s->execute([$address]); $r=$s->fetch(PDO::FETCH_ASSOC);
    $valid=sodium_crypto_pwhash_str_verify($r ? $r['password_hash'] : $dummyHash,$password);
    if (!$r || !$valid || $r['account_status']!=='active') return null;
    $token=bin2hex(random_bytes(32));
    // Lock credentials/account through issuance so password changes cannot race session creation.
    $pdo->beginTransaction();
    try {
        $s=$pdo->prepare('SELECT c.credential_version, c.password_hash, a.account_status FROM m1_password_credentials c JOIN m1_accounts a ON a.account_id=c.account_id WHERE c.account_id=? FOR UPDATE');
        $s->execute([$r['account_id']]); $current=$s->fetch(PDO::FETCH_ASSOC);
        if (!$current || $current['password_hash']!==$r['password_hash'] || $current['account_status']!=='active') {
            $pdo->rollBack(); return null;
        }
        $pdo->prepare('INSERT INTO m1_private_sessions VALUES (UNHEX(?), ?, ?, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6) + INTERVAL 7 DAY, NULL)')
            ->execute([hash('sha256',$token),$r['account_id'],$current['credential_version']]);
        $pdo->commit(); return $token;
    } catch (\Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $e; }
}
function authenticate(PDO $pdo, string $token): ?array {
    if (!preg_match('/\A[a-f0-9]{64}\z/D',$token)) return null;
    $s=$pdo->prepare("SELECT a.account_id, w.workspace_id FROM m1_private_sessions s JOIN m1_accounts a ON a.account_id=s.account_id JOIN m1_password_credentials c ON c.account_id=a.account_id JOIN m1_workspaces w ON w.owner_account_id=a.account_id WHERE s.token_sha256=UNHEX(?) AND s.revoked_at_utc IS NULL AND s.expires_at_utc>UTC_TIMESTAMP(6) AND s.credential_version=c.credential_version AND a.account_status='active'");
    $s->execute([hash('sha256',$token)]);
    return $s->fetch(PDO::FETCH_ASSOC) ?: null;
}
function logout(PDO $pdo, string $token): void {
    if (!preg_match('/\A[a-f0-9]{64}\z/D',$token)) return;
    $pdo->prepare('UPDATE m1_private_sessions SET revoked_at_utc=UTC_TIMESTAMP(6) WHERE token_sha256=UNHEX(?) AND revoked_at_utc IS NULL')
        ->execute([hash('sha256',$token)]);
}
