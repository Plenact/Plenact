<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') { http_response_code(404);exit; }
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/bootstrap.php';
use function Plenact\PrivateAuth\{connect,uuid};
use Plenact\PrivateData\{ReadService,ApiFailure};
function need(bool $ok): void { if (!$ok) throw new RuntimeException('Check failed'); }
$pdo=null;$identities=[];
try {
    $pdo=connect(getenv('HOME').'/plenact-private/model1-staging/config/database.json');
    $pdo->beginTransaction();$service=new ReadService($pdo);
    foreach ([1,2] as $_) {
        $a=uuid();$w=uuid();$epoch=uuid();$identities[]=[$a,$w,$epoch];
        $pdo->prepare("INSERT INTO m1_accounts VALUES (?, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))")->execute([$a]);
        $pdo->prepare('INSERT INTO m1_workspaces VALUES (?, ?, ?, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))')->execute([$w,$a,$epoch]);
        $now='2026-11-21T00:00:00.000Z';
        foreach (\Plenact\PrivateData\initialEnvelopes(['workspace_id'=>$w,'owner_account_id'=>$a,'epoch'=>$epoch],$now,$now) as $e) {
            $pdo->prepare('INSERT INTO m1_record_heads VALUES (?, ?, ?, ?, 1, ?, 0, ?, NULL, UTC_TIMESTAMP(6), ?)')->execute([$w,$e['record_id'],$e['record_type'],$epoch,$e['change_sequence'],json_encode($e['document'],JSON_THROW_ON_ERROR),$a]);
            $pdo->prepare('INSERT INTO m1_record_revisions VALUES (?, ?, ?, ?, 1, ?, ?, UTC_TIMESTAMP(6))')->execute([$w,$epoch,$e['record_id'],$e['record_type'],$e['change_sequence'],json_encode($e,JSON_THROW_ON_ERROR)]);
        }
        need($service->account($a)['record_id']===$a);need($service->workspace($a)['record_id']===$w);
    }
    [$a,$w,$epoch]=$identities[0];[$other,$otherW]=$identities[1];
    foreach ([[$other,$w,'account',$a],[$a,$otherW,'workspace',$otherW],[$a,$w,'card',uuid()]] as $args) {
        try { $service->read(...$args);throw new LogicException('Expected not found'); }
        catch (ApiFailure $e) { need($e->status===404 && $e->errorCode==='not_found'); }
    }
    $pdo->rollBack();
    foreach ($identities as [$a,$w,$epoch]) {
        $s=$pdo->prepare('SELECT COUNT(*) FROM m1_accounts WHERE account_id=?');$s->execute([$a]);need((int)$s->fetchColumn()===0);
        $s=$pdo->prepare('SELECT COUNT(*) FROM m1_record_heads WHERE workspace_id=?');$s->execute([$w]);need((int)$s->fetchColumn()===0);
    }
    echo "PASS: MySQL account/workspace record reads.\nPASS: foreign and unknown records share generic 404.\nPASS: synthetic rows rolled back. No existing workspace modified.\n";
} catch (Throwable $e) {
    if ($pdo instanceof PDO && $pdo->inTransaction()) $pdo->rollBack();
    fwrite(STDERR,"Data read diagnostic failed; no private details displayed.\n");exit(1);
}
