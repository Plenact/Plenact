<?php
declare(strict_types=1);
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/validation.php';require_once __DIR__.'/../private/asset_chunks.php';
use Plenact\PrivateData\{ApiFailure,AssetChunks,ValidationProcess};
function chunkCheck(bool $ok):void{if(!$ok)throw new RuntimeException('Chunk test failed');}
function chunkFailure(callable $fn,int $status):void{try{$fn();throw new LogicException('Expected failure');}catch(ApiFailure $e){chunkCheck($e->status===$status);}}
class ChunkPDO extends PDO{public function prepare(string $query,array $options=[]):PDOStatement|false{return parent::prepare(str_replace(' FOR UPDATE','',$query),$options);}}
$p=new ChunkPDO('sqlite::memory:',null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$p->sqliteCreateFunction('UNHEX',fn($s)=>hex2bin($s),1);
$p->exec('CREATE TABLE m1_accounts(account_id TEXT,account_status TEXT);CREATE TABLE m1_workspaces(workspace_id TEXT,owner_account_id TEXT,epoch TEXT);CREATE TABLE m1_record_heads(workspace_id TEXT,record_id TEXT,record_type TEXT,revision INTEGER,deleted INTEGER,document TEXT);CREATE TABLE m1_asset_uploads(upload_id TEXT,workspace_id TEXT,account_id TEXT,epoch TEXT,asset_id TEXT,asset_revision INTEGER,byte_length INTEGER,sha256 BLOB,chunk_count INTEGER,created_at_utc TEXT,expires_at_utc TEXT);CREATE TABLE m1_asset_chunks(upload_id TEXT,chunk_index INTEGER,sha256 BLOB,chunk_bytes BLOB);');
$a='11111111-1111-4111-8111-111111111111';$w='33333333-3333-4333-8333-333333333333';$e='55555555-5555-4555-8555-555555555555';$id='66666666-6666-4666-8666-666666666666';
$p->prepare('INSERT INTO m1_accounts VALUES (?,?)')->execute([$a,'active']);$p->prepare('INSERT INTO m1_workspaces VALUES (?,?,?)')->execute([$w,$a,$e]);
$bytes=str_repeat("\0\xffx",87381).'a';chunkCheck(strlen($bytes)===262144);$tail="tail\0opaque\xff";
$all=$bytes.$tail;$hash=hash('sha256',$all);
$p->prepare('INSERT INTO m1_record_heads VALUES (?,?,?,1,0,?)')->execute([$w,$id,'asset',json_encode(['payload'=>['content_state'=>'described','byte_length'=>(string)strlen($all),'sha256'=>$hash]])]);
$now=strtotime('2026-11-21 00:00:00 UTC');$clock=static function()use(&$now):int{return $now;};
$v=new ValidationProcess('/private/tmp/plenact-api-venv/bin/python',__DIR__.'/../validation/validator.py');
$chunks=new AssetChunks($p,$clock,$v->uploadRequest(...));
$r=['protocol_version'=>'1.0','workspace_id'=>$w,'epoch'=>$e,'asset_id'=>$id,'asset_revision'=>'1','byte_length'=>(string)strlen($all),'sha256'=>$hash];
$raw=json_encode($r);$session=$chunks->start($a,$w,$raw);chunkCheck($session['chunk_count']===2&&$session['received_chunks']===[]);
$upload=$session['upload_id'];$chunks->put($a,$w,$upload,1,$tail,hash('sha256',$tail));$chunks->put($a,$w,$upload,1,$tail,hash('sha256',$tail));
chunkCheck($chunks->read($a,$w,$upload)['received_chunks']===[1]);
$other=str_repeat('x',strlen($tail));chunkFailure(fn()=>$chunks->put($a,$w,$upload,1,$other,hash('sha256',$other)),409);
chunkFailure(fn()=>$chunks->put($a,$w,$upload,0,$bytes,str_repeat('0',64)),422);
chunkFailure(fn()=>$chunks->put($a,$w,$upload,0,'short',hash('sha256','short')),422);
chunkFailure(fn()=>$chunks->put($a,$w,$upload,2,'',hash('sha256','')),400);
chunkFailure(fn()=>$chunks->read('22222222-2222-4222-8222-222222222222',$w,$upload),404);
$chunks->put($a,$w,$upload,0,$bytes,hash('sha256',$bytes));$complete=$chunks->read($a,$w,$upload);chunkCheck($complete['received_chunks']===[0,1]);
$s=$p->prepare('SELECT chunk_bytes FROM m1_asset_chunks WHERE upload_id=? ORDER BY chunk_index');$s->execute([$upload]);chunkCheck(implode('',$s->fetchAll(PDO::FETCH_COLUMN))===$all);
$oversized=[...$r,'byte_length'=>'18446744073709551615'];chunkFailure(fn()=>$chunks->start($a,$w,json_encode($oversized)),413);
$stale=[...$r,'asset_revision'=>'2'];chunkFailure(fn()=>$chunks->start($a,$w,json_encode($stale)),409);
$now+=86400;chunkFailure(fn()=>$chunks->read($a,$w,$upload),410);
// A known empty file creates a zero-chunk lease, never a fake missing-file substitute.
$zero='77777777-7777-4777-8777-777777777777';
$p->prepare('INSERT INTO m1_record_heads VALUES (?,?,?,1,0,?)')->execute([$w,$zero,'asset',json_encode(['payload'=>['content_state'=>'described','byte_length'=>'0','sha256'=>hash('sha256','')]])]);
$z=[...$r,'asset_id'=>$zero,'byte_length'=>'0','sha256'=>hash('sha256','')];$empty=$chunks->start($a,$w,json_encode($z));chunkCheck($empty['chunk_count']===0&&$empty['received_chunks']===[]);
file_put_contents('/private/tmp/plenact-upload-session-responses.json',json_encode([$session,$complete,$empty],JSON_THROW_ON_ERROR));
echo "PASS: resumable binary chunks, exact retries/conflicts, digest/size/index checks, ownership, stale metadata, quota, expiry and known-empty upload. SQLite integration; no blobs published.\n";
