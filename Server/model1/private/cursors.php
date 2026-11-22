<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
final class CursorCodec {
    public function __construct(private string $key,private \Closure $clock) {
        if(strlen($key)!==32)throw new \InvalidArgumentException('A dedicated 32-byte cursor key is required');
    }
    private static function encode64(string $bytes):string{return rtrim(strtr(base64_encode($bytes),'+/','-_'),'=');}
    private static function decode64(string $value):string {
        $decoded=base64_decode(strtr($value,'-_','+/'),true);
        if($decoded===false || self::encode64($decoded)!==$value)throw new ApiFailure(400,'invalid_document');
        return $decoded;
    }
    public function issue(string $kind,string $account,string $workspace,string $epoch,string $position,int $expires,?string $snapshot=null):string {
        if(!in_array($kind,['s','c'],true)||!ctype_digit($position)||strlen($position)>19||!uuidValid($account)||!uuidValid($workspace)||!uuidValid($epoch)
            || ($kind==='s' && ($snapshot===null || !uuidValid($snapshot))))throw new \InvalidArgumentException('Invalid cursor claims');
        $claims=['v'=>1,'k'=>$kind,'a'=>$account,'w'=>$workspace,'e'=>$epoch,'p'=>$position,'x'=>$expires];
        if($snapshot!==null)$claims['s']=$snapshot;
        $body=json_encode($claims,JSON_THROW_ON_ERROR);
        $value=self::encode64($body.hash_hmac('sha256',$body,$this->key,true));
        if(strlen($value)>512)throw new \RuntimeException('Cursor exceeds contract limit');
        return $value;
    }
    public function read(string $token,string $kind,string $account,string $workspace,?string $snapshot=null):array {
        if(strlen($token)>512 || !preg_match('/\A[A-Za-z0-9_-]+\z/D',$token))throw new ApiFailure(400,'invalid_document');
        $packed=self::decode64($token);
        if(strlen($packed)<=32)throw new ApiFailure(400,'invalid_document');
        $body=substr($packed,0,-32);$mac=substr($packed,-32);
        if(!hash_equals(hash_hmac('sha256',$body,$this->key,true),$mac))throw new ApiFailure(400,'invalid_document');
        $c=json_decode($body,true,16,JSON_THROW_ON_ERROR);
        if(($c['v']??null)!==1 || ($c['k']??null)!==$kind || ($c['a']??null)!==$account || ($c['w']??null)!==$workspace
            || ($kind==='s' && ($c['s']??null)!==$snapshot))throw new ApiFailure(404,'not_found');
        if(!is_string($c['e']??null)||!uuidValid($c['e'])||!is_string($c['p']??null)||!preg_match('/\A(?:0|[1-9][0-9]{0,18})\z/D',$c['p'])
            || strlen($c['p'])===19 && strcmp($c['p'],(string)PHP_INT_MAX)>0 || !is_int($c['x']??null))throw new ApiFailure(400,'invalid_document');
        if($c['x']<=($this->clock)())throw new ApiFailure(410,$kind==='s'?'snapshot_expired':'cursor_expired','resnapshot');
        return $c;
    }
}
