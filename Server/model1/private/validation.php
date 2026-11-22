<?php
declare(strict_types=1);
namespace Plenact\PrivateData;
final class ValidationProcess {
    public function __construct(private string $python,private string $script) {}
    public function purgeRequest(string $raw): void {if(strlen($raw)>8388608)throw new ApiFailure(413,'payload_too_large');$this->run('purge-request',$raw);}
    public function deletionRequest(string $raw): void {if(strlen($raw)>8388608)throw new ApiFailure(413,'payload_too_large');$this->run('account-deletion-request',$raw);}
    public function request(string $raw): void {$this->run('request',$raw);}
    public function uploadCommit(string $raw): void {if(strlen($raw)>8388608)throw new ApiFailure(413,'payload_too_large');$this->run('upload-commit',$raw);}
    public function uploadRequest(string $raw): void {if(strlen($raw)>8388608)throw new ApiFailure(413,'payload_too_large');$this->run('upload-request',$raw);}
    public function offer(string $raw): void {if(strlen($raw)>8388608)throw new ApiFailure(413,'payload_too_large');$this->run('offer',$raw);}
    public function graph(array $heads,string $account,string $workspace): void {
        $this->run('graph',json_encode(['account_id'=>$account,'workspace_id'=>$workspace,'heads'=>(object)$heads],JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
    }
    private function run(string $mode,string $input): void {
        $process=proc_open([$this->python,$this->script,$mode],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes,null,null,['bypass_shell'=>true]);
        if (!is_resource($process)) throw new ApiFailure(503,'invalid_document','retry_later');
        $output='';$offset=0;$deadline=microtime(true)+30;$exit=null;
        foreach ($pipes as $pipe) stream_set_blocking($pipe,false);
        try {
            while (true) {
                if(microtime(true)>$deadline)throw new ApiFailure(503,'invalid_document','retry_later');
                if (isset($pipes[0]) && $offset===strlen($input)) {fclose($pipes[0]);unset($pipes[0]);}
                $read=[];foreach ([1,2] as $i)if(isset($pipes[$i])&&!feof($pipes[$i]))$read[]=$pipes[$i];
                $write=isset($pipes[0])?[$pipes[0]]:[];$except=[];
                if($read || $write){$selected=stream_select($read,$write,$except,0,100000);if($selected===false)throw new ApiFailure(503,'invalid_document','retry_later');}
                foreach ($write as $pipe) {$written=fwrite($pipe,substr($input,$offset,65536));if($written===false)throw new ApiFailure(503,'invalid_document','retry_later');$offset+=$written;}
                foreach ($read as $pipe) {$chunk=fread($pipe,65536);if($pipe===$pipes[1])$output.=$chunk;if(strlen($output)>4096)throw new ApiFailure(503,'invalid_document','retry_later');}
                $status=proc_get_status($process);
                if(!$status['running']){$exit=$status['exitcode'];$output.=stream_get_contents($pipes[1]);break;}
            }
        } finally {
            foreach($pipes as $pipe)fclose($pipe);
            if($exit===null)proc_terminate($process,9);
            proc_close($process);
        }
        $value=json_decode($output,true);
        if($exit===0 && ($value['valid'] ?? null)===true)return;
        if($exit===2 && ($value['category'] ?? '')==='validation_failed')throw new ApiFailure(422,'validation_failed');
        throw new ApiFailure(503,'invalid_document','retry_later');
    }
}
