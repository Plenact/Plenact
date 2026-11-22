<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') { http_response_code(404); exit; }
ini_set('display_errors','0');
require_once __DIR__.'/../private/auth.php';
use function Plenact\PrivateAuth\{connect,reserveAttempts};
function requireCheck(bool $ok): void { if (!$ok) throw new RuntimeException('Check failed'); }
// No PDO connection crosses a fork. Each child connects after receiving the start signal.
function phase(array $jobs, string $key, string $config, int $expected): void {
    $children=[];
    try {
        foreach ($jobs as $batch) {
            $pair=stream_socket_pair(STREAM_PF_UNIX,STREAM_SOCK_STREAM,STREAM_IPPROTO_IP);
            requireCheck($pair!==false);
            $pid=pcntl_fork(); requireCheck($pid!==-1);
            if ($pid===0) {
                fclose($pair[0]);
                foreach ($children as $child) fclose($child['socket']);
                stream_set_timeout($pair[1],30);
                try {
                    requireCheck(fread($pair[1],1)==='G');
                    $pdo=connect($config);
                    $pdo->exec('SET SESSION innodb_lock_wait_timeout=5');
                    $results='';
                    foreach ($batch as [$email,$ip]) $results.=reserveAttempts($pdo,$email,$ip,$key) ? '1' : '0';
                    requireCheck(fwrite($pair[1],$results)===strlen($results));
                    fclose($pair[1]); exit(0);
                } catch (Throwable $e) {
                    $category='worker_check';
                    if ($e instanceof PDOException) {
                        $state=(string)($e->errorInfo[0] ?? $e->getCode());
                        $driver=(int)($e->errorInfo[1] ?? 0);
                        $category=preg_match('/\A[A-Z0-9]{5}\z/D',$state) ? 'database_'.$state.'_'.$driver : 'database_other';
                    }
                    fwrite($pair[1],'E:'.$category); fclose($pair[1]); exit(1);
                }
            }
            fclose($pair[1]); stream_set_timeout($pair[0],30);
            $children[]=['pid'=>$pid,'socket'=>$pair[0],'count'=>count($batch)];
        }
        foreach ($children as $child) requireCheck(fwrite($child['socket'],'G')===1);
        $accepted=0; $attempts=0;
        foreach ($children as $child) {
            $result=stream_get_contents($child['socket']);
            if (is_string($result) && preg_match('/\AE:([A-Za-z0-9_]+)\z/D',$result,$safe)) {
                echo 'Worker category: ',$safe[1],"\n";
            }
            if (stream_get_meta_data($child['socket'])['timed_out']) echo "Worker category: socket_timeout\n";
            requireCheck(is_string($result) && strlen($result)===$child['count'] && preg_match('/\A[01]+\z/D',$result)===1);
            $accepted+=substr_count($result,'1'); $attempts+=strlen($result);
        }
        foreach ($children as $index=>$child) {
            requireCheck(pcntl_waitpid($child['pid'],$status)===$child['pid']);
            $children[$index]['pid']=0;
            requireCheck(pcntl_wifexited($status) && pcntl_wexitstatus($status)===0);
        }
        echo 'Observed accepted count: ',$accepted,'; expected: ',$expected,"\n";
        requireCheck($accepted===$expected);
        echo "PASS: concurrent attempts ",$attempts,"; accepted ",$accepted,"; rejected ",$attempts-$accepted,".\n";
    } finally {
        foreach ($children as $child) {
            fclose($child['socket']);
            if ($child['pid']>0) {
                // Reap all workers before cleaning their diagnostic database rows.
                posix_kill($child['pid'],SIGTERM);
                pcntl_waitpid($child['pid'],$status);
            }
        }
    }
}
$key=random_bytes(32); $keys=[]; $failed=false;
$config=getenv('HOME').'/plenact-private/model1-staging/config/database.json';
try {
    foreach (['pcntl_fork','pcntl_waitpid','posix_kill','stream_socket_pair'] as $capability) {
        echo 'Capability ',$capability,': ',function_exists($capability) ? 'available' : 'unavailable',"\n";
        requireCheck(function_exists($capability));
    }
    $email=bin2hex(random_bytes(16)).'@example.invalid';
    $jobs=array_fill(0,4,[]);
    for ($i=0;$i<20;$i++) $jobs[$i%4][]=[$email,'192.0.2.10'];
    $keys[]=hash_hmac('sha256','email:'.$email,$key);
    $keys[]=hash_hmac('sha256','ip:192.0.2.10',$key);
    phase($jobs,$key,$config,10);
    $jobs=array_fill(0,4,[]);
    for ($i=0;$i<60;$i++) {
        $email=bin2hex(random_bytes(16)).'@example.invalid';
        $jobs[$i%4][]=[$email,'192.0.2.11'];
        $keys[]=hash_hmac('sha256','email:'.$email,$key);
    }
    $keys[]=hash_hmac('sha256','ip:192.0.2.11',$key);
    phase($jobs,$key,$config,50);
} catch (Throwable $e) {
    $failed=true;
    fwrite(STDERR,"Concurrent limit check failed; no private details displayed. Stop and report this status.\n");
} finally {
    try {
        $pdo=connect($config);
        foreach ($keys as $bucket) {
            $pdo->prepare('DELETE FROM m1_login_limits WHERE bucket_key=UNHEX(?)')->execute([$bucket]);
            $s=$pdo->prepare('SELECT COUNT(*) FROM m1_login_limits WHERE bucket_key=UNHEX(?)');
            $s->execute([$bucket]); requireCheck((int)$s->fetchColumn()===0);
        }
        echo "PASS: diagnostic limit entries removed. No accounts or sessions created.\n";
    } catch (Throwable $e) { $failed=true; fwrite(STDERR,"Diagnostic cleanup could not be confirmed. Stop and report this status.\n"); }
}
if ($failed) exit(1);
echo "Concurrent rate-limit diagnostic passed. HTTP login remains disabled.\n";
