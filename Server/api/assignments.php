<?php
/**************************************************************************************************
 * @file       assignments.php
 * @brief      Add or remove registered-user assignments on shared Board cards
 * @details    Members may change only their own assignment; Jim may manage any active user
 *
 **************************************************************************************************/
declare(strict_types=1);

require_once __DIR__ . '/common.php';

try {
    require_https();
    require_method(['POST']);
    $pdo     = database_connection();    /* Runtime database connection */
    $actor   = authenticated_user($pdo); /* Verified request identity   */
    $request = read_json_body();         /* Decoded assignment request  */

    $expectedRevision = $request['expected_revision'] ?? null; /* Client's last-seen revision */
    $cardID           = $request['card_id'] ?? null;           /* Target Board-card identity  */
    $action           = $request['action'] ?? null;            /* Requested assignment change */
    $requestedUserID  = $request['user_id'] ?? null;           /* Optional account target      */

    if (!is_int($expectedRevision) || $expectedRevision < 1
        || !is_int($cardID) || $cardID < 0
        || !in_array($action, ['assign', 'unassign'], true)) {
        respond_json(422, ['error' => 'invalid_assignment_operation']);
    }

    [$targetUserID, $assignmentError] = resolve_assignment_target_user_id($actor, $requestedUserID); /* Authorized target and error */
    if ($assignmentError !== null) {
        respond_json($assignmentError === 'target_user_required' ? 422 : 403, ['error' => $assignmentError]);
    }
    $requestedUserID = $targetUserID; /* Use the server-authorized identity */

    $pdo->beginTransaction();
    $targetQuery = $pdo->prepare( /* Lock the active target account */
        "SELECT user_id, display_name FROM demo_users
         WHERE user_id = :user_id AND account_status = 'active' FOR UPDATE"
    );
    $targetQuery->execute(['user_id' => $requestedUserID]);
    $targetUser = $targetQuery->fetch(); /* Target identity and display name */

    if ($targetUser === false) {
        $pdo->rollBack();
        respond_json(422, ['error' => 'target_user_unavailable']);
    }

    $boardQuery = $pdo->prepare( /* Lock the current shared snapshot */
        'SELECT b.board_id, b.current_revision, b.content_editor_user_id,
                r.schema_version, r.board_document
         FROM demo_boards b
         INNER JOIN demo_board_revisions r
            ON r.board_id = b.board_id AND r.revision = b.current_revision
         WHERE b.board_key = :board_key FOR UPDATE'
    );
    $boardQuery->execute(['board_key' => 'shared-demo']);
    $board = $boardQuery->fetch(); /* Board head and current document */

    if ($board === false) {
        $pdo->rollBack();
        respond_json(404, ['error' => 'board_not_seeded']);
    }

    if (($actor['account_role'] ?? null) === 'board_editor'
        && strtolower($board['content_editor_user_id']) !== strtolower($actor['user_id'])) {
        $pdo->rollBack();
        respond_json(403, ['error' => 'forbidden']);
    }

    $currentRevision = (int)$board['current_revision']; /* Locked revision number */
    if ($currentRevision !== $expectedRevision) {
        $pdo->rollBack();
        respond_json(409, ['error' => 'revision_conflict', 'current_revision' => $currentRevision]);
    }

    $document   = json_decode($board['board_document'], true, PLENACT_JSON_DEPTH, JSON_THROW_ON_ERROR); /* Editable snapshot copy */
    $cardFound  = false; /* Matching card exists in the document */
    $changed    = false; /* Assignment state requires a revision */

    foreach ($document['lists'] as &$list) { /* Search the ordered Board lists */
        foreach ($list['cards'] as &$card) { /* Search cards in the current list */
            if (($card['id'] ?? null) !== $cardID) {
                continue;
            }

            $cardFound       = true; /* Requested card was found */
            $members         = $card['members'] ?? []; /* Existing card assignments */
            $alreadyAssigned = false; /* Target already has an assignment */

            foreach ($members as $member) { /* Check registered-user assignments */
                if (($member['kind'] ?? null) === 'registeredUser'
                    && strtolower((string)($member['userID'] ?? '')) === strtolower($targetUser['user_id'])) {
                    $alreadyAssigned = true; /* Target account is already assigned */
                    break;
                }
            }

            if ($action === 'assign' && !$alreadyAssigned) {
                $members[] = [ /* New stable registered-user assignment */
                    'id' => new_uuid(),
                    'kind' => 'registeredUser',
                    'userID' => $targetUser['user_id'],
                    'displayName' => $targetUser['display_name'],
                ];
                $card['members'] = $members; /* Updated assignment collection */
                $changed = true;             /* Mark the snapshot as changed */
            } elseif ($action === 'unassign' && $alreadyAssigned) {
                $card['members'] = array_values(array_filter( /* Remove matching user assignment */
                    $members,
                    static fn ($member /* Assignment retained unless it targets this user */): bool => !(($member['kind'] ?? null) === 'registeredUser'
                        && strtolower((string)($member['userID'] ?? '')) === strtolower($targetUser['user_id']))
                ));
                $changed = true; /* Mark the snapshot as changed */
            }
            break 2;
        }
        unset($card);
    }
    unset($list);

    if (!$cardFound) {
        $pdo->rollBack();
        respond_json(404, ['error' => 'card_not_found']);
    }

    if (!$changed) {
        $pdo->commit();
        respond_json(200, ['revision' => $currentRevision, 'changed' => false]);
    }

    $activeUserIDs   = $pdo->query("SELECT user_id FROM demo_users WHERE account_status = 'active'")->fetchAll(PDO::FETCH_COLUMN); /* Current account IDs */
    $activeUserIDSet = array_fill_keys(array_map('strtolower', $activeUserIDs), true); /* Fast active-user lookup */
    $validationError = validate_board_document($document, $activeUserIDSet); /* Updated snapshot validation */

    if ($validationError !== null) {
        $pdo->rollBack();
        respond_json(500, ['error' => 'stored_board_invalid']);
    }

    $encodedDocument = json_encode( /* Server-serialized revision payload */
        $document,
        JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_SUBSTITUTE | JSON_UNESCAPED_SLASHES
    );
    $nextRevision = $currentRevision + 1; /* Next immutable revision number */
    $origin       = ($actor['account_role'] ?? null) === 'board_editor' ? 'jim_edit' : 'member_assignment'; /* Controlled provenance value */
    $insert       = $pdo->prepare( /* Append-only revision insert */
        'INSERT INTO demo_board_revisions (
            board_id, revision, schema_version, board_document, document_sha256,
            stored_at_utc, stored_by_user_id, storage_origin, import_batch_id
         ) VALUES (
            :board_id, :revision, :schema_version, :document, :digest,
            UTC_TIMESTAMP(6), :actor_id, :origin, NULL
         )'
    );
    $insert->execute([
        'board_id' => $board['board_id'],
        'revision' => $nextRevision,
        'schema_version' => (int)$board['schema_version'],
        'document' => $encodedDocument,
        'digest' => hash('sha256', $encodedDocument),
        'actor_id' => $actor['user_id'],
        'origin' => $origin,
    ]);

    $update = $pdo->prepare( /* Compare-and-swap Board-head update */
        'UPDATE demo_boards SET current_revision = :new_revision,
         updated_at_utc = UTC_TIMESTAMP(6), updated_by_user_id = :actor_id
         WHERE board_id = :board_id AND current_revision = :expected_revision'
    );
    $update->execute([
        'new_revision' => $nextRevision,
        'actor_id' => $actor['user_id'],
        'board_id' => $board['board_id'],
        'expected_revision' => $currentRevision,
    ]);

    if ($update->rowCount() !== 1) {
        $pdo->rollBack();
        respond_json(409, ['error' => 'revision_conflict']);
    }

    $pdo->commit();
    respond_json(200, ['revision' => $nextRevision, 'changed' => true]);
} catch (Throwable) { /* Return a generic response for unexpected failures */
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    respond_json(500, ['error' => 'server_error']);
}
