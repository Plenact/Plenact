<?php
require_once __DIR__.'/../private/bootstrap.php';
echo json_encode(\Plenact\PrivateData\initialEnvelopes([
    'workspace_id'=>'33333333-3333-4333-8333-333333333333',
    'owner_account_id'=>'11111111-1111-4111-8111-111111111111',
    'epoch'=>'55555555-5555-4555-8555-555555555555'],
    '2026-11-21T00:00:00.000Z','2026-11-21T01:00:00.000Z'),JSON_THROW_ON_ERROR);
