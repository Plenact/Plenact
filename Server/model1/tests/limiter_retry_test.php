<?php
declare(strict_types=1);
require_once __DIR__.'/../private/auth.php';
class RetryStatement extends PDOStatement {
    public function execute(?array $params=null): bool { return true; }
    public function fetch(int $mode=PDO::FETCH_DEFAULT,int $orientation=PDO::FETCH_ORI_NEXT,int $offset=0): mixed {
        return ['attempt_count'=>0,'expired'=>0];
    }
}
class RetryPDO extends PDO {
    public int $begins=0; public int $commits=0; public int $rollbacks=0;
    public int $failures=0; public int $driver=1213; private bool $active=false;
    public function __construct() {}
    public function beginTransaction(): bool { $this->begins++; $this->active=true; return true; }
    public function inTransaction(): bool { return $this->active; }
    public function rollBack(): bool { $this->rollbacks++; $this->active=false; return true; }
    public function commit(): bool { $this->commits++; $this->active=false; return true; }
    public function prepare(string $query,array $options=[]): PDOStatement|false {
        if ($this->failures>0) {
            $this->failures--; $e=new PDOException('Synthetic database failure');
            $e->errorInfo=['40001',$this->driver,'Synthetic']; throw $e;
        }
        return new RetryStatement();
    }
}
function verifyRetry(bool $ok): void { if (!$ok) throw new RuntimeException('Retry check failed'); }
foreach ([1213,1205] as $code) {
    $pdo=new RetryPDO(); $pdo->driver=$code; $pdo->failures=2;
    verifyRetry(\Plenact\PrivateAuth\reserveAttempts($pdo,'test@example.invalid','192.0.2.1',str_repeat('x',32)));
    verifyRetry($pdo->begins===3 && $pdo->rollbacks===2 && $pdo->commits===1);
}
$pdo=new RetryPDO(); $pdo->failures=20;
try { \Plenact\PrivateAuth\reserveAttempts($pdo,'test@example.invalid','192.0.2.1',str_repeat('x',32)); throw new LogicException('Unbounded retries'); }
catch (PDOException $e) { verifyRetry($pdo->begins===5 && $pdo->rollbacks===5 && $pdo->commits===0); }
$pdo=new RetryPDO(); $pdo->failures=1; $pdo->driver=1142;
try { \Plenact\PrivateAuth\reserveAttempts($pdo,'test@example.invalid','192.0.2.1',str_repeat('x',32)); throw new LogicException('Retried unrelated error'); }
catch (PDOException $e) { verifyRetry($pdo->begins===1 && $pdo->rollbacks===1 && $pdo->commits===0); }
echo "PASS: whole-transaction retries, bounded exhaustion, and unrelated errors. No live database exercised.\n";
