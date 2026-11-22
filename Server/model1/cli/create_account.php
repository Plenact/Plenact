<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once __DIR__.'/../private/auth.php';
// Passwords are read only from a controlling terminal, never argv, environment or a public route.
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
try {
    $email=prompt('Invited account email: ');
    $password=prompt('Password (15+ characters): ',true);
    $confirm=prompt('Repeat password: ',true);
    if (!hash_equals($password,$confirm)) throw new RuntimeException('Passwords differ');
    $pdo=\Plenact\PrivateAuth\connect(getenv('HOME').'/plenact-private/model1-staging/config/database.json');
    $s=$pdo->query("SELECT source_sha256 FROM m1_schema_migrations WHERE migration_id='002_invite_auth'");
    if ($s->fetchColumn()!=='cfd94e68ba8b7675386aa4e9507886d71d71749cb04ba7bfc79efb2f1eca0feb') throw new RuntimeException('Migration mismatch');
    $result=\Plenact\PrivateAuth\provision($pdo,$email,$password);
    sodium_memzero($password); sodium_memzero($confirm);
    echo "Invited account and private workspace created. No session issued.\n";
} catch (Throwable $e) {
    fwrite(STDERR,"Account creation failed; no private details displayed. Check migration, connection, email, password length and whether the account already exists.\n");
    exit(1);
}
