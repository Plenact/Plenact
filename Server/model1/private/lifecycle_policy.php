<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
use PDO;
final class LifecyclePolicy {
    // Authentication proofs are operational state; clients cannot provide an accepted timestamp.
    public static function recentActor(PDO $pdo,string $token,\Closure $clock):array {
        $actor=\Plenact\PrivateAuth\authenticate($pdo,$token);
        if($actor===null)throw new ApiFailure(401,'unauthenticated','reauthenticate');
        $s=$pdo->prepare('SELECT created_at_utc FROM m1_private_sessions WHERE token_sha256=UNHEX(?)');$s->execute([hash('sha256',$token)]);$created=$s->fetchColumn();
        $issued=$created===false?false:strtotime($created.' UTC');$age=$issued===false?PHP_INT_MAX:($clock)()-$issued;
        if($age<0||$age>=300)throw new ApiFailure(403,'forbidden','reauthenticate');
        return $actor;
    }
    public static function receipt(string $kind,string $account,string $workspace,?string $asset,string $operation,int $accepted):array {
        if(!in_array($kind,['asset_purge','account_delete'],true)||!uuidValid($account)||!uuidValid($workspace)||!uuidValid($operation)
            ||($kind==='asset_purge'&&($asset===null||!uuidValid($asset))))throw new \InvalidArgumentException('Invalid lifecycle identities');
        $stamp=static fn(int $t):string=>gmdate('Y-m-d\TH:i:s',$t).'.000Z';
        $r=['protocol_version'=>'1.0','operation_id'=>$operation,'accepted_at_utc'=>$stamp($accepted),
            'primary_delete_deadline_utc'=>$stamp($accepted+86400),'backup_delete_deadline_utc'=>$stamp($accepted+30*86400)];
        return $kind==='asset_purge' ? ['protocol_version'=>'1.0','workspace_id'=>$workspace,'asset_id'=>$asset]+$r
            : ['protocol_version'=>'1.0','account_id'=>$account]+$r;
    }
}
