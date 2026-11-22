<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
umask(0077);
try{
 $path=getenv('HOME').'/plenact-private/model1-staging/config/data-api.json';
 $value=json_encode(['read_enabled'=>false,'write_enabled'=>false,'assets_enabled'=>false,'cursor_key_hex'=>bin2hex(random_bytes(32))],JSON_THROW_ON_ERROR|JSON_PRETTY_PRINT)."\n";
 $file=fopen($path,'x');if(!$file)throw new RuntimeException();
 if(fwrite($file,$value)!==strlen($value)){fclose($file);unlink($path);throw new RuntimeException();}
 fclose($file);echo "Private data API configuration created; read/write routes disabled.\n";
}catch(Throwable $e){fwrite(STDERR,"Data API initialization failed; no private details displayed and existing configuration not overwritten.\n");exit(1);}
