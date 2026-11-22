<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') { http_response_code(404); exit; }
require_once __DIR__.'/../private/auth.php';
umask(0077);
try {
    $path=getenv('HOME').'/plenact-private/model1-staging/config/auth.json';
    $json=json_encode(['enabled'=>false,'limiter_key_hex'=>bin2hex(random_bytes(32)),
        'dummy_password_hash'=>\Plenact\PrivateAuth\passwordHash(bin2hex(random_bytes(32)))], JSON_THROW_ON_ERROR | JSON_PRETTY_PRINT)."\n";
    $f=fopen($path,'x');
    if (!$f) throw new RuntimeException();
    if (fwrite($f,$json)!==strlen($json)) { fclose($f); unlink($path); throw new RuntimeException(); }
    fclose($f);
    echo "Private authentication configuration created. HTTP login remains disabled.\n";
} catch (Throwable $e) { fwrite(STDERR,"Initialization failed; no private details displayed. Existing configuration was not overwritten.\n"); exit(1); }
