<?php
/**************************************************************************************************
 * @file       board_contract_test.php
 * @brief      Verify Plenact Board document and identity invariants
 * @details    Run with PHP CLI; tests use pure helpers and do not require a database connection
 *
 **************************************************************************************************/
declare(strict_types=1);

require_once __DIR__ . '/../api/common.php';

// -------------------------------------- MARK: - Test Assertion ------------------------------- //

/**
 * @fcn        check
 * @brief      Stop the test process when one contract expectation is false
 *
 * @param[in]  $condition Assertion result
 * @param[in]  $message Failure description
 *
 * @return     (void) continues only when the assertion passes
 */
function check(bool $condition, string $message): void
{
    if (!$condition) {
        fwrite(STDERR, $message . PHP_EOL);
        exit(1);
    }
}

// -------------------------------------- MARK: - Valid Board Fixture ------------------------- //

$activeUserID = 'fb13a9ee-9107-47c3-bb4f-dff07fe57eba'; /* Registered test account identity */
$document     = [ /* Valid version-one Board fixture */
    'schema_version' => 1,
    'board_key' => 'shared-demo',
    'lists' => [[
        'id' => 1,
        'title' => 'Monday',
        'cards' => [[
            'id' => 10,
            'word' => 'Sample activity',
            'listTitle' => 'Monday',
            'isDivider' => false,
            'isTitleChecked' => false,
            'members' => [[
                'id' => 'a7b0a1d2-8b9e-4a5c-9d0e-123456789abc',
                'kind' => 'registeredUser',
                'userID' => $activeUserID,
                'displayName' => 'Jim',
            ]],
            'labelIDs' => ['work-scheduled'],
            'checklists' => [[
                'id' => '9a9d98d1-8c4d-4d1b-a09e-d0a42d3f0abc',
                'title' => 'Focus',
                'items' => [[
                    'id' => '4d0c6de8-418b-47f5-95c4-e289ce5fb87b',
                    'title' => 'Review the plan',
                    'isCompleted' => false,
                    'content' => ['kind' => 'standard'],
                ]],
            ]],
            'comments' => [],
            'dismissedActivityIDs' => [],
        ]],
    ]],
    'label_library' => [
        'categories' => [['id' => 'work', 'name' => 'Work']],
        'labels' => [[
            'id' => 'work-scheduled',
            'name' => 'Scheduled',
            'categoryID' => 'work',
            'color' => 'blue',
        ]],
    ],
];

$activeUsers = [strtolower($activeUserID) => true]; /* Active-user lookup fixture */
check(
    validate_board_document($document, $activeUsers) === null,
    'Valid v1 Board document was rejected.'
);
check(
    is_json_body_within_limit(str_repeat('x', PLENACT_MAX_JSON_BODY_BYTES)),
    'A JSON body at the maximum byte limit was rejected.'
);
check(
    !is_json_body_within_limit(str_repeat('x', PLENACT_MAX_JSON_BODY_BYTES + 1)),
    'A JSON body above the maximum byte limit was accepted.'
);

// -------------------------------------- MARK: - Identity And Label Validation --------------- //

$unknownAssignee = $document; /* Snapshot with an unresolved account reference */
$unknownAssignee['lists'][0]['cards'][0]['members'][0]['userID'] = '702e32b4-ef43-49ea-a29d-169c468381fe'; /* Missing account fixture */
check(
    validate_board_document($unknownAssignee, $activeUsers) === 'unknown_card_assignee',
    'Unknown registered assignee was not rejected.'
);

$duplicateCard = $document; /* Snapshot with a duplicated list identity */
$duplicateCard['lists'][] = $duplicateCard['lists'][0]; /* Append duplicate list identity */
check(
    validate_board_document($duplicateCard, $activeUsers) === 'invalid_board_list',
    'Duplicate list ID was not rejected.'
);

$legacyIdentity = $document; /* Malformed manual assignment fixture */
$legacyIdentity['lists'][0]['cards'][0]['members'][0]['kind'] = 'manual'; /* Change assignment kind */
$legacyIdentity['lists'][0]['cards'][0]['members'][0]['userID'] = $activeUserID; /* Keep invalid account reference */
check(
    validate_board_document($legacyIdentity, $activeUsers) === 'invalid_manual_assignee',
    'Manual assignee with account ID was not rejected.'
);

$unknownLabel = $document; /* Snapshot with a missing label reference */
$unknownLabel['lists'][0]['cards'][0]['labelIDs'] = ['missing-label']; /* Add unresolved label ID */
check(
    validate_board_document($unknownLabel, $activeUsers) === 'unknown_card_label',
    'Unknown label reference was not rejected.'
);

// -------------------------------------- MARK: - Checklist And Attachment Validation --------- //

$actionDetail = $document; /* Snapshot with a valid reduced Action Detail */
$actionDetail['lists'][0]['cards'][0]['checklists'][0]['items'][0]['content'] = [ /* Replace with reduced detail */
    'kind' => 'actionDetail',
    'detail' => [
        'id' => '93d343a6-bc63-4bfd-9121-95154119b7aa',
        'description' => 'Supporting detail',
        'checklists' => [],
        'comments' => [],
    ],
];
check(
    validate_board_document($actionDetail, $activeUsers) === null,
    'Valid Action Detail was rejected.'
);

$malformedDetail = $actionDetail; /* Action Detail missing required comments */
unset($malformedDetail['lists'][0]['cards'][0]['checklists'][0]['items'][0]['content']['detail']['comments']);
check(
    validate_board_document($malformedDetail, $activeUsers) === 'invalid_comments',
    'Malformed Action Detail comments were not rejected.'
);

$httpAttachment = $document; /* Snapshot with an insecure web attachment */
$httpAttachment['lists'][0]['cards'][0]['attachments'] = [[ /* Non-HTTPS link fixture */
    'id' => '12f046dd-d81b-456c-b471-474637617628',
    'url' => 'http://example.test/page',
    'mediaKind' => 'link',
    'addedAt' => 1.0,
]];
check(
    validate_board_document($httpAttachment, $activeUsers) === 'invalid_shared_attachment',
    'Non-HTTPS shared link was not rejected.'
);

$withLocalPhoto = $document; /* Snapshot mixing local media and a remote link */
$withLocalPhoto['lists'][0]['cards'][0]['attachments'] = [
    [
        'id' => '12f046dd-d81b-456c-b471-474637617628',
        'fileName' => 'local-photo.jpg',
        'mediaKind' => 'photo',
        'addedAt' => 1.0,
    ],
    [
        'id' => '1dfc480e-1a4d-49d5-b2c1-23bb7ef42b8c',
        'url' => 'https://example.test/page',
        'mediaKind' => 'link',
        'addedAt' => 1.0,
    ],
];
$normalized = shared_board_document($withLocalPhoto); /* Shared form after local-media removal */
check(
    count($normalized['lists'][0]['cards'][0]['attachments']) === 1,
    'Device-local media was not stripped.'
);
check(
    validate_board_document($normalized, $activeUsers) === null,
    'Valid HTTPS link was not retained in shared document.'
);

$malformedEnvelope = ['lists' => 'not-a-list']; /* Malformed envelope for safe normalization */
check(
    shared_board_document($malformedEnvelope) === $malformedEnvelope,
    'Media normalization modified an invalid Board envelope.'
);

// -------------------------------------- MARK: - Seed And Account Invariants ----------------- //

$batchID = deterministic_uuid('sample_data_v1'); /* Deterministic import identity */
check($batchID === deterministic_uuid('sample_data_v1'), 'Seed batch UUID is not deterministic.');
check(
    preg_match('/\A[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/', $batchID) === 1,
    'Seed batch UUID is not RFC 4122 version 5.'
);
check(utf8_character_count(str_repeat('😀', 100)) === 100, 'Unicode character count does not match SQL character limits.');
check(is_demo_password(str_repeat('a', 12)), 'Minimum-length password was rejected.');
check(
    !is_demo_password(str_repeat('a', PLENACT_MAX_PASSWORD_BYTES + 1)),
    'Password exceeding the hash limit was accepted.'
);

// -------------------------------------- MARK: - Assignment Authorization -------------------- //

$memberActor = ['user_id' => $activeUserID, 'account_role' => 'member']; /* Authenticated member fixture */
[$ownTarget, $ownError] = resolve_assignment_target_user_id($memberActor, null); /* Implicit self target */
check($ownTarget === $activeUserID && $ownError === null, 'Member without an explicit target was not scoped to self.');
[$otherTarget, $otherError] = resolve_assignment_target_user_id($memberActor, '702e32b4-ef43-49ea-a29d-169c468381fe'); /* Foreign target attempt */
check(
    $otherTarget === null && $otherError === 'members_may_change_own_assignment_only',
    'Member was allowed to target another account.'
);
[$malformedTarget, $malformedError] = resolve_assignment_target_user_id($memberActor, ['user_id' => $activeUserID]); /* Non-string target attempt */
check(
    $malformedTarget === null && $malformedError === 'members_may_change_own_assignment_only',
    'Non-string member target was not safely rejected.'
);

$editorActor = ['user_id' => $activeUserID, 'account_role' => 'board_editor']; /* Authenticated Board-editor fixture */
[$editorTarget, $editorError] = resolve_assignment_target_user_id($editorActor, '702E32B4-EF43-49EA-A29D-169C468381FE'); /* Valid alternate account target */
check(
    $editorTarget === '702e32b4-ef43-49ea-a29d-169c468381fe' && $editorError === null,
    'Board editor could not target another active account ID.'
);

// -------------------------------------- MARK: - Test Completion ------------------------------ //

echo "Board contract tests passed.\n";
