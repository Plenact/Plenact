-- -------------------------------------------------------------------------------------------------
-- @file       core_storage_probe.sql
-- @brief      Synthetic physical-storage checks followed by rollback in Model 1.0 staging only
-- @details    This is NOT a migration or wire-protocol fixture. No credentials, user content, schema
--             changes or commits. Fresh UUIDs isolate all temporary rows. Run once and share results.
--             All table references are qualified; the connection's current database is irrelevant.
-- -------------------------------------------------------------------------------------------------
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
SELECT migration_id, source_sha256,
       source_sha256 = 'cb58318d79e2afe764400390012abf85bbd6bf34940e12da8556f75fed025fc8' AS expected_source_matches
FROM `justirl2_plenact_m1_stage`.`m1_schema_migrations` WHERE migration_id = '001_core';

SET @probe_account = UUID(), @probe_workspace = UUID(), @probe_epoch = UUID(),
    @probe_record = UUID(), @probe_transaction = UUID(), @probe_operation = UUID();
-- Exact UTF-8 bytes for 'Plenact [seedling emoji] cafe-with-acute'; ASCII source avoids paste encoding.
SET @probe_text = CONVERT(0x506c656e61637420f09f8cb120636166c3a9 USING utf8mb4);
START TRANSACTION;

INSERT INTO `justirl2_plenact_m1_stage`.`m1_accounts`
    (account_id, account_status, created_at_utc, updated_at_utc)
VALUES (@probe_account, 'active', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6));
INSERT INTO `justirl2_plenact_m1_stage`.`m1_workspaces`
    (workspace_id, owner_account_id, epoch, change_sequence, created_at_utc, updated_at_utc)
VALUES (@probe_workspace, @probe_account, @probe_epoch, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6));
INSERT INTO `justirl2_plenact_m1_stage`.`m1_record_heads`
    (workspace_id, record_id, record_type, epoch, revision, change_sequence, deleted,
     document, asset_content, stored_at_utc, stored_by_account_id)
VALUES (@probe_workspace, @probe_record, 'storage_probe', @probe_epoch, 1, 1, 0,
        JSON_OBJECT('probe_text', @probe_text), NULL, UTC_TIMESTAMP(6), @probe_account);
INSERT INTO `justirl2_plenact_m1_stage`.`m1_record_revisions`
    (workspace_id, epoch, record_id, record_type, revision, change_sequence, server_envelope, stored_at_utc)
VALUES (@probe_workspace, @probe_epoch, @probe_record, 'storage_probe', 1, 1,
        JSON_OBJECT('storage_probe', @probe_text), UTC_TIMESTAMP(6));
INSERT INTO `justirl2_plenact_m1_stage`.`m1_changes`
    (workspace_id, epoch, change_sequence, record_id, revision, stored_at_utc)
VALUES (@probe_workspace, @probe_epoch, 1, @probe_record, 1, UTC_TIMESTAMP(6));
INSERT INTO `justirl2_plenact_m1_stage`.`m1_transaction_receipts`
    (workspace_id, transaction_id, epoch, request_sha256, receipt_sequence, receipt, stored_at_utc)
VALUES (@probe_workspace, @probe_transaction, @probe_epoch,
        UNHEX(SHA2('synthetic storage probe only', 256)), 1,
        JSON_OBJECT('storage_probe', 1), UTC_TIMESTAMP(6));
INSERT INTO `justirl2_plenact_m1_stage`.`m1_operation_receipts`
    (workspace_id, operation_id, transaction_id, epoch, record_id, record_type, revision, change_sequence, deleted)
VALUES (@probe_workspace, @probe_operation, @probe_transaction, @probe_epoch, @probe_record, 'storage_probe', 1, 1, 0);

SELECT
    BINARY JSON_UNQUOTE(JSON_EXTRACT(h.document, '$.probe_text')) = BINARY @probe_text AS unicode_bytes_match,
    h.record_id = r.record_id AND r.record_id = c.record_id
        AND h.record_id = o.record_id AND t.transaction_id = o.transaction_id AS linked_rows_match,
    t.request_sha256 = UNHEX(SHA2('synthetic storage probe only', 256)) AS receipt_hash_matches
FROM `justirl2_plenact_m1_stage`.`m1_record_heads` h
JOIN `justirl2_plenact_m1_stage`.`m1_record_revisions` r
    ON r.workspace_id = h.workspace_id AND r.record_id = h.record_id AND r.revision = h.revision
JOIN `justirl2_plenact_m1_stage`.`m1_changes` c
    ON c.workspace_id = r.workspace_id AND c.epoch = r.epoch AND c.change_sequence = r.change_sequence
JOIN `justirl2_plenact_m1_stage`.`m1_transaction_receipts` t ON t.workspace_id = h.workspace_id
JOIN `justirl2_plenact_m1_stage`.`m1_operation_receipts` o
    ON o.workspace_id = t.workspace_id AND o.transaction_id = t.transaction_id
WHERE h.workspace_id = @probe_workspace;

ROLLBACK;

SELECT
    (SELECT COUNT(*) FROM `justirl2_plenact_m1_stage`.`m1_accounts` WHERE account_id = @probe_account) AS accounts_remaining,
    (SELECT COUNT(*) FROM `justirl2_plenact_m1_stage`.`m1_workspaces` WHERE workspace_id = @probe_workspace) AS workspaces_remaining,
    (SELECT COUNT(*) FROM `justirl2_plenact_m1_stage`.`m1_record_heads` WHERE workspace_id = @probe_workspace) AS heads_remaining,
    (SELECT COUNT(*) FROM `justirl2_plenact_m1_stage`.`m1_record_revisions` WHERE workspace_id = @probe_workspace) AS revisions_remaining,
    (SELECT COUNT(*) FROM `justirl2_plenact_m1_stage`.`m1_changes` WHERE workspace_id = @probe_workspace) AS changes_remaining,
    (SELECT COUNT(*) FROM `justirl2_plenact_m1_stage`.`m1_transaction_receipts` WHERE workspace_id = @probe_workspace) AS transactions_remaining,
    (SELECT COUNT(*) FROM `justirl2_plenact_m1_stage`.`m1_operation_receipts` WHERE workspace_id = @probe_workspace) AS operations_remaining;
