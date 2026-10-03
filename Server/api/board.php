<?php
/**************************************************************************************************
 * @file       board.php
 * @brief      Read the shared Plenact Board and append editor-only snapshots
 * @details    Revision checks prevent silent overwrite; only Jim's account may replace content
 *
 **************************************************************************************************/
declare(strict_types=1);

require_once __DIR__ . '/common.php';


// -------------------------------------- MARK: - Shared Board Route --------------------------- //

try {
    require_https();
    require_method(['GET', 'PUT']);
    $pdo   = database_connection();   /* Runtime database connection */
    $actor = authenticated_user($pdo); /* Verified request identity   */

    if (strtoupper($_SERVER['REQUEST_METHOD'] ?? '') === 'GET') {
        // -------------------------------------- MARK: - Snapshot Read ------------------------ //

        $statement = $pdo->prepare( /* Current snapshot read query */
            'SELECT r.revision, r.board_document, r.stored_at_utc,
                    r.stored_by_user_id, r.storage_origin
             FROM demo_boards b
             INNER JOIN demo_board_revisions r
                ON r.board_id = b.board_id AND r.revision = b.current_revision
             WHERE b.board_key = :board_key LIMIT 1'
        );
        $statement->execute(['board_key' => 'shared-demo']);
        $revision = $statement->fetch(); /* Current revision metadata */

        if ($revision === false) {
            respond_json(404, ['error' => 'board_not_seeded']);
        }

        if (!is_json_body_within_limit((string)$revision['board_document'])) { /* Stored snapshot byte ceiling */
            respond_json(500, ['error' => 'server_error']);
        }

        $document = json_decode($revision['board_document'], true, PLENACT_JSON_DEPTH, JSON_THROW_ON_ERROR); /* Stored Board payload */
        respond_json(200, [
            'revision' => (int)$revision['revision'],
            'document' => $document,
            'stored_at_utc' => $revision['stored_at_utc'],
            'stored_by_user_id' => $revision['stored_by_user_id'],
            'storage_origin' => $revision['storage_origin'],
        ]);
    }

    // -------------------------------------- MARK: - Snapshot Write --------------------------- //

    require_board_editor($actor);
    $request          = read_json_body();                      /* Decoded snapshot request */
    $expectedRevision = $request['expected_revision'] ?? null; /* Client's last-seen revision */

    if (!is_int($expectedRevision) || $expectedRevision < 0 || !is_array($request['document'] ?? null)) {
        respond_json(422, ['error' => 'invalid_board_write']);
    }

    $seedKind = $request['seed_kind'] ?? null; /* Explicit initial seed marker */
    if (($expectedRevision === 0 && $seedKind !== 'sample_data_v1')
        || ($expectedRevision > 0 && $seedKind !== null)) {
        respond_json(422, ['error' => 'invalid_seed_request']);
    }

    $document        = shared_board_document($request['document']); /* Remove device-local media references */
    $activeUsers     = $pdo->query("SELECT user_id FROM demo_users WHERE account_status = 'active'")->fetchAll(PDO::FETCH_COLUMN); /* Valid directory identities */
    $activeUserIDs   = array_fill_keys(array_map('strtolower', $activeUsers), true); /* Fast membership lookup */
    $validationError = validate_board_document($document, $activeUserIDs); /* Snapshot validation result */

    if ($validationError !== null) {
        respond_json(422, ['error' => $validationError]);
    }

    $encodedDocument = json_encode( /* Exact payload bytes used for the digest */
        $document,
        JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_SUBSTITUTE | JSON_UNESCAPED_SLASHES
    );
    if (!is_json_body_within_limit($encodedDocument)) {
        respond_json(413, ['error' => 'request_too_large']);
    }

    $digest     = hash('sha256', $encodedDocument); /* Snapshot integrity digest */
    $cardCount  = array_sum(array_map(static fn ($list /* Board list being counted */): int => count($list['cards']), $document['lists'])); /* Imported card count */

    // -------------------------------------- MARK: - Seed Transaction ------------------------- //

    $pdo->beginTransaction();
    $importBatchID = $expectedRevision === 0 ? deterministic_uuid('sample_data_v1') : null; /* Stable first-seed batch ID */
    if ($importBatchID !== null) {
        $batchInsert = $pdo->prepare( /* Idempotent seed-batch insert */
            'INSERT INTO demo_import_batches (
                import_batch_id, idempotency_key, source_name, batch_status,
                source_item_count, result_item_count, created_at_utc, created_by_user_id
             ) VALUES (
                :batch_id, :idempotency_key, \'sample_data_v1\', \'started\',
                :source_count, 0, UTC_TIMESTAMP(6), :actor_id
             ) ON DUPLICATE KEY UPDATE import_batch_id = VALUES(import_batch_id)'
        );
        $batchInsert->execute([
            'batch_id' => $importBatchID,
            'idempotency_key' => hash('sha256', 'plenact:sample_data_v1'),
            'source_count' => $cardCount,
            'actor_id' => $actor['user_id'],
        ]);
    }

    $boardQuery = $pdo->prepare( /* Lock the shared Board head */
        'SELECT board_id, content_editor_user_id, current_revision
         FROM demo_boards WHERE board_key = :board_key FOR UPDATE'
    );
    $boardQuery->execute(['board_key' => 'shared-demo']);
    $board       = $boardQuery->fetch(); /* Existing head, when initialized */
    $initialSeed = false;                /* Whether this request creates revision one */

    if ($board === false) {
        if ($expectedRevision !== 0) {
            $pdo->rollBack();
            respond_json(404, ['error' => 'board_not_seeded']);
        }

        $boardID     = new_uuid();            /* New shared Board identity */
        $boardInsert = $pdo->prepare(         /* Initial Board-head insert */
            'INSERT INTO demo_boards (
                board_id, board_key, title, visibility, content_editor_user_id,
                current_revision, created_at_utc, updated_at_utc,
                created_by_user_id, updated_by_user_id, storage_origin
             ) VALUES (
                :board_id, \'shared-demo\', \'Plenact Shared Demo Board\', \'shared_demo\',
                :editor_id, NULL, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6),
                :created_by, :updated_by, \'demo_seed\'
             )'
        );
        $boardInsert->execute([
            'board_id' => $boardID,
            'editor_id' => $actor['user_id'],
            'created_by' => $actor['user_id'],
            'updated_by' => $actor['user_id'],
        ]);
        $board = [ /* New Board head awaiting revision one */
            'board_id' => $boardID,
            'content_editor_user_id' => $actor['user_id'],
            'current_revision' => null,
        ];
        $initialSeed = true; /* Mark the first snapshot transaction */
    } elseif ($board['current_revision'] === null && $expectedRevision === 0) {
        $initialSeed = true; /* Complete a pre-created empty Board */
    }

    if (strtolower($board['content_editor_user_id']) !== strtolower($actor['user_id'])) {
        $pdo->rollBack();
        respond_json(403, ['error' => 'forbidden']);
    }

    $currentRevision = $board['current_revision'] === null ? 0 : (int)$board['current_revision']; /* Locked revision number */
    if ($currentRevision !== $expectedRevision || ($expectedRevision === 0 && !$initialSeed)) {
        $pdo->rollBack();
        respond_json(409, ['error' => 'revision_conflict', 'current_revision' => $currentRevision]);
    }

    // -------------------------------------- MARK: - Append Revision ------------------------- //

    $nextRevision = $expectedRevision + 1; /* Monotonic snapshot revision */
    $insert       = $pdo->prepare(          /* Immutable revision insert */
        'INSERT INTO demo_board_revisions (
            board_id, revision, schema_version, board_document, document_sha256,
            stored_at_utc, stored_by_user_id, storage_origin, import_batch_id
         ) VALUES (
            :board_id, :revision, :schema_version, :document, :digest,
                UTC_TIMESTAMP(6), :actor_id, :origin, :import_batch_id
         )'
    );
    $insert->execute([
        'board_id' => $board['board_id'],
        'revision' => $nextRevision,
        'schema_version' => $document['schema_version'],
        'document' => $encodedDocument,
        'digest' => $digest,
        'actor_id' => $actor['user_id'],
        'origin' => $initialSeed ? 'demo_seed' : 'jim_edit',
        'import_batch_id' => $importBatchID,
    ]);

    // -------------------------------------- MARK: - Advance Board Head ---------------------- //

    if ($initialSeed) {
        $update = $pdo->prepare( /* Initialize the Board head */
            'UPDATE demo_boards SET current_revision = :new_revision,
             updated_at_utc = UTC_TIMESTAMP(6), updated_by_user_id = :actor_id
             WHERE board_id = :board_id AND current_revision IS NULL'
        );
        $update->execute([
            'new_revision' => $nextRevision,
            'actor_id' => $actor['user_id'],
            'board_id' => $board['board_id'],
        ]);
        $batchUpdate = $pdo->prepare( /* Complete seed-batch metadata */
            'UPDATE demo_import_batches SET batch_status = \'completed\',
             result_item_count = :result_count, completed_at_utc = UTC_TIMESTAMP(6)
             WHERE import_batch_id = :batch_id'
        );
        $batchUpdate->execute(['result_count' => $cardCount, 'batch_id' => $importBatchID]);
    } else {
        $update = $pdo->prepare( /* Compare-and-swap revision update */
            'UPDATE demo_boards SET current_revision = :new_revision,
             updated_at_utc = UTC_TIMESTAMP(6), updated_by_user_id = :actor_id
             WHERE board_id = :board_id AND current_revision = :expected_revision'
        );
        $update->execute([
            'new_revision' => $nextRevision,
            'actor_id' => $actor['user_id'],
            'board_id' => $board['board_id'],
            'expected_revision' => $expectedRevision,
        ]);
    }

    if ($update->rowCount() !== 1) {
        $pdo->rollBack();
        respond_json(409, ['error' => 'revision_conflict']);
    }

    $pdo->commit();
    respond_json(200, ['revision' => $nextRevision, 'document' => $document]);
} catch (Throwable) { /* Return a generic response for unexpected failures */
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    respond_json(500, ['error' => 'server_error']);
}
