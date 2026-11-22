<?php
declare(strict_types=1);
require_once __DIR__.'/../private/auth.php';require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/blob_files.php';
use Plenact\PrivateData\{BlobFiles,ByteRange,ApiFailure};
function blobNeed(bool $ok):void{if(!$ok)throw new RuntimeException('Blob test failed');}
$root=sys_get_temp_dir().'/plenact-blob-test-'.bin2hex(random_bytes(8));mkdir($root,0700);
$w=\Plenact\PrivateAuth\uuid();$blob=\Plenact\PrivateAuth\uuid();$files=new BlobFiles($root);$path=null;$temp=null;
try{
 [$temp,$stream]=$files->temporary($w);$bytes="\0\xffopaque bytes\0";blobNeed(fwrite($stream,$bytes)===strlen($bytes));fflush($stream);fclose($stream);
 $path=$files->publish($temp,$w,$blob);blobNeed(!file_exists($temp)&&(fileperms($path)&0777)===0600);
 $stream=$files->open($w,$blob,strlen($bytes),hash('sha256',$bytes));blobNeed(stream_get_contents($stream)===$bytes);fclose($stream);
 try{$files->path('../outside',$blob);throw new LogicException('Traversal accepted');}catch(InvalidArgumentException $e){}
 $etag='"'.hash('sha256',$bytes).'"';
 foreach([[null,null,[200,0,10]],['bytes=2-4',null,[206,2,3]],['bytes=7-',null,[206,7,3]],['bytes=-3',null,[206,7,3]],['bytes=0-999999999999999999999999',null,[206,0,10]],['bytes=-999999999999999999999999',null,[206,0,10]],['bytes=2-4','"other"',[200,0,10]],['bytes=2-4','W/'.$etag,[200,0,10]]] as [$range,$if,$expected])blobNeed(ByteRange::select(10,$range,$if,$etag)===$expected);
 foreach(['bytes=10-','bytes=7-2','bytes=-0','bytes=0-1,3-4','garbage','bytes=-'] as $bad){try{ByteRange::select(10,$bad,null,$etag);throw new LogicException('Invalid range accepted');}catch(ApiFailure $e){blobNeed($e->status===416);}}
 blobNeed(ByteRange::select(0,null,null,$etag)===[200,0,0]);
 file_put_contents($path,'corrupt');try{$files->open($w,$blob,strlen($bytes),hash('sha256',$bytes));throw new LogicException('Corruption accepted');}catch(ApiFailure $e){blobNeed($e->errorCode==='integrity_mismatch');}
 echo "PASS: private binary publication/read, path guards, corruption detection, bounded/open/suffix/If-Range behavior and malformed ranges.\n";
}finally{if($temp&&is_file($temp))unlink($temp);if($path&&is_file($path))unlink($path);if(is_dir($root.'/'.$w))rmdir($root.'/'.$w);rmdir($root);}
