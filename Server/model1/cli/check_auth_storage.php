<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') { http_response_code(404); exit; }
require_once __DIR__.'/../private/auth.php';
use function Plenact\PrivateAuth\{connect,uuid,passwordHash,authenticate,logout};
function expect(bool $ok): void { if (!$ok) throw new RuntimeException('Check failed'); }
$pdo=null;
try {
    $pdo=connect(getenv('HOME').'/plenact-private/model1-staging/config/database.json');
    $ledger=$pdo->query("SELECT source_sha256 FROM m1_schema_migrations WHERE migration_id='002_invite_auth'")->fetchColumn();
    expect($ledger==='cfd94e68ba8b7675386aa4e9507886d71d71749cb04ba7bfc79efb2f1eca0feb');
    $password=bin2hex(random_bytes(24)); $hash=passwordHash($password);
    expect(sodium_crypto_pwhash_str_verify($hash,$password));
    expect(!sodium_crypto_pwhash_str_verify($hash,$password.'wrong'));
    $pdo->beginTransaction(); $fixtures=[];
    for ($i=0;$i<2;$i++) {
        $a=uuid(); $w=uuid(); $token=bin2hex(random_bytes(32)); $fixtures[]=[$a,$w,$token];
        $pdo->prepare("INSERT INTO m1_accounts VALUES (?, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))")->execute([$a]);
        $pdo->prepare('INSERT INTO m1_workspaces VALUES (?, ?, ?, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$w,$a,uuid()]);
        $pdo->prepare('INSERT INTO m1_password_credentials VALUES (?, ?, ?, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$a,$a.'@example.invalid',$hash]);
        $pdo->prepare('INSERT INTO m1_private_sessions VALUES (UNHEX(?), ?, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6) + INTERVAL 1 HOUR, NULL)')->execute([hash('sha256',$token),$a]);
    }
    foreach ($fixtures as [$a,$w,$token]) expect(authenticate($pdo,$token)===['account_id'=>$a,'workspace_id'=>$w]);
    expect(authenticate($pdo,'bad')===null);
    expect(authenticate($pdo,bin2hex(random_bytes(32)))===null);
    [$a,$w,$token]=$fixtures[0];
    $pdo->prepare('UPDATE m1_password_credentials SET credential_version=2 WHERE account_id=?')->execute([$a]);
    expect(authenticate($pdo,$token)===null);
    $pdo->prepare('UPDATE m1_password_credentials SET credential_version=1 WHERE account_id=?')->execute([$a]);
    $pdo->prepare("UPDATE m1_accounts SET account_status='disabled' WHERE account_id=?")->execute([$a]);
    expect(authenticate($pdo,$token)===null);
    $pdo->prepare("UPDATE m1_accounts SET account_status='active' WHERE account_id=?")->execute([$a]);
    $pdo->prepare('UPDATE m1_private_sessions SET expires_at_utc=UTC_TIMESTAMP(6) - INTERVAL 1 SECOND WHERE account_id=?')->execute([$a]);
    expect(authenticate($pdo,$token)===null);
    [$a,$w,$token]=$fixtures[1]; logout($pdo,$token); expect(authenticate($pdo,$token)===null);
    $pdo->rollBack();
    foreach ($fixtures as [$a,$w,$token]) {
        foreach (['m1_accounts','m1_workspaces','m1_password_credentials','m1_private_sessions'] as $table) {
            $column=$table==='m1_workspaces' ? 'owner_account_id' : 'account_id';
            $s=$pdo->prepare("SELECT COUNT(*) FROM $table WHERE $column=?"); $s->execute([$a]); expect((int)$s->fetchColumn()===0);
        }
    }
    echo "PASS: migration checksum and password hashing.\nPASS: two sessions resolve to their own account/workspace.\nPASS: malformed/unknown tokens, expiry, revocation, disabled accounts and credential changes rejected.\nPASS: rollback left no synthetic account, workspace, credential or session rows.\nHTTP login and concurrent rate-limit checks remain pending.\n";
} catch (Throwable $e) {
    if ($pdo instanceof PDO && $pdo->inTransaction()) $pdo->rollBack();
    fwrite(STDERR,"Authentication storage check failed; no private details displayed. Stop and report this status.\n"); exit(1);
}
