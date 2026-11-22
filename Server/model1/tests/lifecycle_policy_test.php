<?php
declare(strict_types=1);
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/lifecycle_policy.php';require_once __DIR__.'/../private/validation.php';
use Plenact\PrivateData\{LifecyclePolicy,ValidationProcess,ApiFailure};
function lifeNeed(bool $ok):void{if(!$ok)throw new RuntimeException('Lifecycle policy check failed');}
function lifeFailure(callable $fn,int $status):void{try{$fn();throw new LogicException('Expected rejection');}catch(ApiFailure $e){lifeNeed($e->status===$status);}}
$p=class_exists('Pdo\\Sqlite')?new \Pdo\Sqlite('sqlite::memory:'):new PDO('sqlite::memory:');$p->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
$now=strtotime('2026-11-21 00:00:00 UTC');$clock=static function()use(&$now):int{return $now;};
$functions=['UNHEX'=>[fn($s)=>hex2bin($s),1],'UTC_TIMESTAMP'=>[static function($precision)use(&$now){return gmdate('Y-m-d H:i:s',$now);},1]];
foreach($functions as$name=>[$fn,$argc]){if(method_exists($p,'createFunction'))$p->createFunction($name,$fn,$argc);else$p->sqliteCreateFunction($name,$fn,$argc);}
$p->exec('CREATE TABLE m1_accounts(account_id TEXT,account_status TEXT);CREATE TABLE m1_workspaces(workspace_id TEXT,owner_account_id TEXT);CREATE TABLE m1_password_credentials(account_id TEXT,credential_version INTEGER);CREATE TABLE m1_private_sessions(token_sha256 BLOB,account_id TEXT,credential_version INTEGER,created_at_utc TEXT,expires_at_utc TEXT,revoked_at_utc TEXT);');
$a='11111111-1111-4111-8111-111111111111';$w='33333333-3333-4333-8333-333333333333';$asset='55555555-5555-4555-8555-555555555555';$op='66666666-6666-4666-8666-666666666666';$token=str_repeat('a',64);
$p->prepare('INSERT INTO m1_accounts VALUES (?,?)')->execute([$a,'active']);$p->prepare('INSERT INTO m1_workspaces VALUES (?,?)')->execute([$w,$a]);$p->prepare('INSERT INTO m1_password_credentials VALUES (?,1)')->execute([$a]);
$p->prepare('INSERT INTO m1_private_sessions VALUES (UNHEX(?),?,1,?,?,NULL)')->execute([hash('sha256',$token),$a,gmdate('Y-m-d H:i:s',$now),gmdate('Y-m-d H:i:s',$now+3600)]);
lifeNeed(LifecyclePolicy::recentActor($p,$token,$clock)['account_id']===$a);$now+=299;lifeNeed(LifecyclePolicy::recentActor($p,$token,$clock)['workspace_id']===$w);$now++;lifeFailure(fn()=>LifecyclePolicy::recentActor($p,$token,$clock),403);
$now-=300;$p->exec("UPDATE m1_private_sessions SET revoked_at_utc='2026-11-21 00:00:00'");lifeFailure(fn()=>LifecyclePolicy::recentActor($p,$token,$clock),401);
$p->exec('UPDATE m1_private_sessions SET revoked_at_utc=NULL;UPDATE m1_password_credentials SET credential_version=2');lifeFailure(fn()=>LifecyclePolicy::recentActor($p,$token,$clock),401);
lifeFailure(fn()=>LifecyclePolicy::recentActor($p,'invalid',$clock),401);
$receipts=['purge'=>LifecyclePolicy::receipt('asset_purge',$a,$w,$asset,$op,$now),'account'=>LifecyclePolicy::receipt('account_delete',$a,$w,null,$op,$now)];
file_put_contents('/private/tmp/plenact-lifecycle-receipts.json',json_encode($receipts,JSON_THROW_ON_ERROR));
$v=new ValidationProcess('/private/tmp/plenact-api-venv/bin/python',__DIR__.'/../validation/validator.py');$base=dirname(__DIR__,3).'/Doc/Strategy/Architecture/User-Data-Model/Contracts/1.0/Fixtures/';
$purge=json_decode(file_get_contents($base.'asset-purge-request.json'),true);$delete=json_decode(file_get_contents($base.'account-deletion-request.json'),true);
$v->purgeRequest(json_encode($purge));$v->deletionRequest(json_encode($delete));
$purge['accept_history_media_unavailable']=false;lifeFailure(fn()=>$v->purgeRequest(json_encode($purge)),422);
$delete['confirmation']='DELETE';lifeFailure(fn()=>$v->deletionRequest(json_encode($delete)),422);
echo "PASS: five-minute recent-auth boundary, revoked/changed-credential rejection, explicit confirmation/history acknowledgement, and deterministic deadline receipts. No deletion scheduled.\n";
