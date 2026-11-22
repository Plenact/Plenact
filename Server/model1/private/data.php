<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
use PDO;
use RuntimeException;
final class ApiFailure extends RuntimeException {
    public function __construct(public readonly int $status, public readonly string $errorCode,
        public readonly string $recovery='none',public readonly array $conflicts=[]) { parent::__construct($errorCode); }
}
function errorBody(ApiFailure $error, string $requestId): array {
    return ['protocol_version'=>'1.0','request_id'=>$requestId,'error'=>[
        'code'=>$error->errorCode,'message'=>'The request could not be completed.','recovery'=>$error->recovery,'conflicts'=>$error->conflicts]];
}
function uuidValid(string $value): bool {
    return preg_match('/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/D',$value)===1;
}
final class ReadService {
    public function __construct(private PDO $pdo) {}
    private function ownedWorkspace(string $account, ?string $workspace=null): array {
        $sql="SELECT w.workspace_id, w.owner_account_id, w.epoch FROM m1_workspaces w JOIN m1_accounts a ON a.account_id=w.owner_account_id WHERE w.owner_account_id=? AND a.account_status='active'";
        $params=[$account];
        if ($workspace!==null) { $sql.=' AND w.workspace_id=?'; $params[]=$workspace; }
        $s=$this->pdo->prepare($sql); $s->execute($params); $row=$s->fetch(PDO::FETCH_ASSOC);
        if (!$row) throw new ApiFailure(404,'not_found');
        return $row;
    }
    public function read(string $account,string $workspace,string $type,string $id): array {
        // Ownership is checked against stored identities, never client-supplied claims.
        $owned=$this->ownedWorkspace($account,$workspace);
        if (!uuidValid($id) || !preg_match('/\A[a-z_]{1,64}\z/D',$type)) throw new ApiFailure(404,'not_found');
        $s=$this->pdo->prepare('SELECT r.server_envelope FROM m1_record_heads h JOIN m1_record_revisions r ON r.workspace_id=h.workspace_id AND r.epoch=h.epoch AND r.record_id=h.record_id AND r.record_type=h.record_type AND r.revision=h.revision WHERE h.workspace_id=? AND h.record_id=? AND h.record_type=? AND h.epoch=?');
        $s->execute([$workspace,$id,$type,$owned['epoch']]); $raw=$s->fetchColumn();
        if ($raw===false) throw new ApiFailure(404,'not_found');
        $decoded=json_decode($raw,false,64,JSON_THROW_ON_ERROR);
        $value=$decoded instanceof \stdClass ? (array)$decoded : null;
        if (!is_array($value) || ($value['workspace_id'] ?? null)!==$workspace || ($value['record_id'] ?? null)!==$id
            || ($value['record_type'] ?? null)!==$type || ($value['epoch'] ?? null)!==$owned['epoch']) {
            throw new ApiFailure(503,'invalid_document','retry_later');
        }
        return $value;
    }
    public function account(string $account): array {
        $w=$this->ownedWorkspace($account);
        return $this->read($account,$w['workspace_id'],'account',$account);
    }
    public function workspace(string $account): array {
        $w=$this->ownedWorkspace($account);
        return $this->read($account,$w['workspace_id'],'workspace',$w['workspace_id']);
    }
}
