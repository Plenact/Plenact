<?php
declare(strict_types=1);
require_once __DIR__.'/../private/data.php';require_once __DIR__.'/../private/validation.php';require_once __DIR__.'/../private/bootstrap.php';
use Plenact\PrivateData\{ValidationProcess,ApiFailure};
$root=dirname(__DIR__,3);
$v=new ValidationProcess($argv[1] ?? '/private/tmp/plenact-api-venv/bin/python',__DIR__.'/../validation/validator.py');
$v->request(file_get_contents($root.'/Doc/Strategy/Architecture/User-Data-Model/Contracts/1.0/Fixtures/transaction-create.json'));
foreach (['{"protocol_version":"1.0","protocol_version":"1.0"}','{"x":NaN}'] as $raw) {
    try {$v->request($raw);throw new LogicException('Validation unexpectedly passed');}
    catch(ApiFailure $e){if($e->status!==422)throw $e;}
}
$w=['workspace_id'=>'33333333-3333-4333-8333-333333333333','owner_account_id'=>'11111111-1111-4111-8111-111111111111','epoch'=>'55555555-5555-4555-8555-555555555555'];
$heads=[];
foreach(\Plenact\PrivateData\initialEnvelopes($w,'2026-11-21T00:00:00.000Z','2026-11-21T01:00:00.000Z') as $e){$e['document']=json_encode($e['document'],JSON_THROW_ON_ERROR);$heads[$e['record_id']]=$e;}
$v->graph($heads,$w['owner_account_id'],$w['workspace_id']);
try{$v->graph($heads,'22222222-2222-4222-8222-222222222222',$w['workspace_id']);throw new LogicException('Foreign owner passed');}
catch(ApiFailure $e){if($e->status!==422)throw $e;}
echo "PASS: PHP/private-process request and graph validation; malformed JSON and owner mismatch rejected.\n";
