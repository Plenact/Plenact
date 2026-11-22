<?php
declare(strict_types=1);
require_once __DIR__.'/../private/auth.php';
function check(bool $ok,string $message): void { if (!$ok) throw new RuntimeException($message); }
check(\Plenact\PrivateAuth\email(' Test.User@Example.COM ')==='test.user@example.com','Email normalization');
foreach (['bad','a@b\n.com','é@example.com',str_repeat('a',255).'@example.com'] as $bad) {
    try { \Plenact\PrivateAuth\email($bad); throw new LogicException('Accepted invalid email'); }
    catch (RuntimeException $e) {}
}
$pw='A test password longer than seventy-two bytes '.str_repeat('x',80);
$hash=\Plenact\PrivateAuth\passwordHash($pw);
check(sodium_crypto_pwhash_str_verify($hash,$pw),'Correct password');
check(!sodium_crypto_pwhash_str_verify($hash,$pw.'different'),'No password truncation');
check(!sodium_crypto_pwhash_str_verify($hash,'wrong'),'Wrong password');
check($hash!==\Plenact\PrivateAuth\passwordHash($pw),'Random salts');
foreach (['short',str_repeat('x',1025),"long enough password\0"] as $bad) {
    try { \Plenact\PrivateAuth\passwordHash($bad); throw new LogicException('Accepted invalid password'); }
    catch (RuntimeException $e) {}
}
$ids=[];
for ($i=0;$i<100;$i++) { $id=\Plenact\PrivateAuth\uuid(); check((bool)preg_match('/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/',$id),'UUID format'); $ids[]=$id; }
check(count(array_unique($ids))===100,'UUID uniqueness');
echo "Authentication primitive checks passed. Database and HTTP integration not exercised.\n";
