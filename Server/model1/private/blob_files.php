<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
final class BlobFiles {
    private string $root;
    public function __construct(string $root) {
        $real=realpath($root);
        if($real===false||!is_dir($real)||is_link($root))throw new \RuntimeException('Private storage unavailable');
        $this->root=$real;
    }
    private function directory(string $workspace):string {
        if(!uuidValid($workspace))throw new \InvalidArgumentException('Invalid storage identity');
        $dir=$this->root.'/'.$workspace;
        if(!is_dir($dir)&&!mkdir($dir,0700))throw new \RuntimeException('Private storage unavailable');
        if(is_link($dir)||realpath($dir)!==$dir)throw new \RuntimeException('Invalid private storage');
        return $dir;
    }
    public function path(string $workspace,string $blob):string {
        if(!uuidValid($blob))throw new \InvalidArgumentException('Invalid blob identity');
        return $this->directory($workspace).'/'.$blob;
    }
    public function temporary(string $workspace):array {
        $path=$this->directory($workspace).'/.partial-'.\Plenact\PrivateAuth\uuid();
        $stream=fopen($path,'x+b');if(!$stream)throw new \RuntimeException('Cannot stage verified bytes');
        if(!chmod($path,0600)){fclose($stream);unlink($path);throw new \RuntimeException('Cannot protect private bytes');}
        return [$path,$stream];
    }
    public function publish(string $temporary,string $workspace,string $blob):string {
        $path=$this->path($workspace,$blob);
        if(dirname($temporary)!==$this->directory($workspace)||!str_starts_with(basename($temporary),'.partial-')||is_link($temporary))throw new \RuntimeException('Invalid staging path');
        if(!link($temporary,$path))throw new \RuntimeException('Cannot atomically publish private bytes');
        unlink($temporary);return $path;
    }
    public function open(string $workspace,string $blob,int $length,string $digest) {
        $path=$this->path($workspace,$blob);
        if(is_link($path)||!is_file($path))throw new ApiFailure(503,'asset_unavailable','retry_later');
        $stream=fopen($path,'rb');if(!$stream)throw new ApiFailure(503,'asset_unavailable','retry_later');
        try{
            $stat=fstat($stream);
            if(!$stat||($stat['mode']&0170000)!==0100000||$stat['size']!==$length)throw new ApiFailure(503,'integrity_mismatch','retry_later');
            $hash=hash_init('sha256');$count=hash_update_stream($hash,$stream);
            if($count!==$length||!hash_equals($digest,hash_final($hash)))throw new ApiFailure(503,'integrity_mismatch','retry_later');
            rewind($stream);return $stream;
        }catch(\Throwable $e){fclose($stream);throw $e;}
    }
}
final class ByteRange {
    private static function cap(string $digits,int $maximum):int {
        $digits=ltrim($digits,'0');if($digits==='')return 0;
        if(strlen($digits)>strlen((string)$maximum)||(strlen($digits)===strlen((string)$maximum)&&strcmp($digits,(string)$maximum)>0))return $maximum;
        return (int)$digits;
    }
    public static function select(int $length,?string $range,?string $ifRange,string $etag):array {
        if($range===null||($ifRange!==null&&!hash_equals($etag,$ifRange)))return [200,0,$length];
        if($length===0||!preg_match('/\Abytes=([0-9]*)-([0-9]*)\z/D',$range,$m)||($m[1]===''&&$m[2]===''))throw new ApiFailure(416,'invalid_document');
        if($m[1]===''){$suffix=self::cap($m[2],$length);if($suffix===0)throw new ApiFailure(416,'invalid_document');return [206,$length-$suffix,$suffix];}
        $start=self::cap($m[1],$length);if($start>=$length)throw new ApiFailure(416,'invalid_document');
        $end=$m[2]===''?$length-1:self::cap($m[2],$length-1);if($end<$start)throw new ApiFailure(416,'invalid_document');
        return [206,$start,$end-$start+1];
    }
}
