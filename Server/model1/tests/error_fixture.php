<?php
require_once __DIR__.'/../private/data.php';
$errors=[];
foreach([[401,'unauthenticated','reauthenticate'],[404,'not_found','none'],[409,'conflict','resolve_conflict'],[503,'invalid_document','retry_later']] as $args)
 $errors[]=\Plenact\PrivateData\errorBody(new \Plenact\PrivateData\ApiFailure(...$args),'11111111-1111-4111-8111-111111111111');
echo json_encode($errors,JSON_THROW_ON_ERROR);
