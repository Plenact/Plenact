<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
use PDO;
use RuntimeException;
function initialEnvelopes(array $workspace,string $accountCreated,string $now): array {
    $account=$workspace['owner_account_id']; $id=$workspace['workspace_id']; $epoch=$workspace['epoch'];
    $documents=[['record_type'=>'account','id'=>$account,'payload'=>[
        'display_name'=>'','account_kind'=>'personal','created_at_utc'=>$accountCreated]],
        ['record_type'=>'workspace','id'=>$id,'payload'=>[
        'owner_account_id'=>$account,'display_name'=>'Personal workspace','calendar_system'=>'gregorian','state'=>'active']]];
    $out=[];
    foreach ($documents as $i=>$document) {
        $document=['user_data_model_version'=>'1.0','payload_schema_version'=>1,'workspace_id'=>$id]+$document;
        $out[]=['user_data_model_version'=>'1.0','workspace_id'=>$id,'record_type'=>$document['record_type'],
            'record_id'=>$document['id'],'epoch'=>$epoch,'revision'=>'1','change_sequence'=>(string)($i+1),
            'stored_at_utc'=>$now,'stored_by_account_id'=>$account,'deleted'=>false,'document'=>$document,'asset_content'=>null];
    }
    return $out;
}
// Operator-only initialization of an untouched invited workspace, never an implicit read mutation.
function bootstrapWorkspace(PDO $pdo,string $account): void {
    $pdo->beginTransaction();
    try {
        $s=$pdo->prepare("SELECT w.*, a.created_at_utc AS account_created FROM m1_workspaces w JOIN m1_accounts a ON a.account_id=w.owner_account_id WHERE w.owner_account_id=? AND a.account_status='active' FOR UPDATE");
        $s->execute([$account]);$w=$s->fetch(PDO::FETCH_ASSOC);
        if (!$w || (string)$w['change_sequence']!=='0') throw new RuntimeException('Workspace is not untouched');
        $s=$pdo->prepare('SELECT COUNT(*) FROM m1_record_heads WHERE workspace_id=?');$s->execute([$w['workspace_id']]);
        if ((int)$s->fetchColumn()!==0) throw new RuntimeException('Workspace is not empty');
        $now=(new \DateTimeImmutable('now',new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.v\Z');
        $created=(new \DateTimeImmutable($w['account_created'],new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.v\Z');
        foreach (initialEnvelopes($w,$created,$now) as $e) {
            $json=json_encode($e,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
            $doc=json_encode($e['document'],JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
            $pdo->prepare('INSERT INTO m1_record_heads VALUES (?, ?, ?, ?, 1, ?, 0, ?, NULL, ?, ?)')->execute([
                $w['workspace_id'],$e['record_id'],$e['record_type'],$w['epoch'],$e['change_sequence'],$doc,$nowSQL=substr(str_replace('T',' ',$now),0,-1),$account]);
            $pdo->prepare('INSERT INTO m1_record_revisions VALUES (?, ?, ?, ?, 1, ?, ?, ?)')->execute([
                $w['workspace_id'],$w['epoch'],$e['record_id'],$e['record_type'],$e['change_sequence'],$json,$nowSQL]);
            $pdo->prepare('INSERT INTO m1_changes VALUES (?, ?, ?, ?, 1, ?)')->execute([
                $w['workspace_id'],$w['epoch'],$e['change_sequence'],$e['record_id'],$nowSQL]);
        }
        $pdo->prepare('UPDATE m1_workspaces SET change_sequence=2, updated_at_utc=? WHERE workspace_id=?')->execute([$nowSQL,$w['workspace_id']]);
        $pdo->commit();
    } catch (\Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $e; }
}
