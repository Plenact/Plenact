-- -------------------------------------------------------------------------------------------------
-- @file       001_core.sql
-- @brief      Initial private Model 1.0 core storage, targeting the new staging database only
-- @details    MySQL/Percona 5.7-compatible foundation. Not a complete Model 1.0 service.
--             Authentication, snapshot/media leases and lifecycle jobs require later implementation.
--             All table references are schema-qualified; no current-database context is trusted.
--             DDL is not transactional in MySQL 5.7. Run once after the empty-schema preflight.
--             Application code must enforce signed-counter bounds, ownership and graph validation;
--             MySQL 5.7 CHECK declarations are deliberately not used as enforcement.
-- -------------------------------------------------------------------------------------------------
ALTER DATABASE `justirl2_plenact_m1_stage` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_schema_migrations` (
    migration_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    applied_at_utc DATETIME(6) NOT NULL,
    applied_by VARCHAR(255) NOT NULL,
    PRIMARY KEY (migration_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Operational identities only; credentials and session issuance are not editable user records.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_accounts` (
    account_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_status VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at_utc DATETIME(6) NOT NULL,
    updated_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (account_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_workspaces` (
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    owner_account_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    change_sequence BIGINT NOT NULL DEFAULT 0,
    created_at_utc DATETIME(6) NOT NULL,
    updated_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (workspace_id),
    UNIQUE KEY m1_workspace_owner (owner_account_id),
    CONSTRAINT m1_workspace_account_fk FOREIGN KEY (owner_account_id) REFERENCES `justirl2_plenact_m1_stage`.`m1_accounts`(account_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_record_heads` (
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record_type VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision BIGINT NOT NULL,
    change_sequence BIGINT NOT NULL,
    deleted TINYINT UNSIGNED NOT NULL,
    document JSON NULL,
    asset_content JSON NULL,
    stored_at_utc DATETIME(6) NOT NULL,
    stored_by_account_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    PRIMARY KEY (workspace_id, record_id),
    UNIQUE KEY m1_record_identity (workspace_id, record_id, record_type),
    KEY m1_head_snapshot_order (workspace_id, record_type, record_id),
    CONSTRAINT m1_head_workspace_fk FOREIGN KEY (workspace_id) REFERENCES `justirl2_plenact_m1_stage`.`m1_workspaces`(workspace_id),
    CONSTRAINT m1_head_actor_fk FOREIGN KEY (stored_by_account_id) REFERENCES `justirl2_plenact_m1_stage`.`m1_accounts`(account_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_record_revisions` (
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record_type VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision BIGINT NOT NULL,
    change_sequence BIGINT NOT NULL,
    server_envelope JSON NOT NULL,
    stored_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (workspace_id, epoch, record_id, revision),
    UNIQUE KEY m1_revision_sequence (workspace_id, epoch, change_sequence),
    KEY m1_revision_record_type (workspace_id, record_id, record_type),
    CONSTRAINT m1_revision_head_fk FOREIGN KEY (workspace_id, record_id, record_type)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_record_heads`(workspace_id, record_id, record_type)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_changes` (
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    change_sequence BIGINT NOT NULL,
    record_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision BIGINT NOT NULL,
    stored_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (workspace_id, epoch, change_sequence),
    KEY m1_change_revision (workspace_id, epoch, record_id, revision),
    KEY m1_change_retention (stored_at_utc),
    CONSTRAINT m1_change_revision_fk FOREIGN KEY (workspace_id, epoch, record_id, revision)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_record_revisions`(workspace_id, epoch, record_id, revision)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_transaction_receipts` (
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    transaction_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_sha256 BINARY(32) NOT NULL,
    receipt_sequence BIGINT NOT NULL,
    receipt JSON NOT NULL,
    stored_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (workspace_id, transaction_id),
    CONSTRAINT m1_receipt_workspace_fk FOREIGN KEY (workspace_id) REFERENCES `justirl2_plenact_m1_stage`.`m1_workspaces`(workspace_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_operation_receipts` (
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    operation_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    transaction_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record_type VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision BIGINT NOT NULL,
    change_sequence BIGINT NOT NULL,
    deleted TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (workspace_id, operation_id),
    UNIQUE KEY m1_transaction_record (workspace_id, transaction_id, record_id),
    CONSTRAINT m1_operation_transaction_fk FOREIGN KEY (workspace_id, transaction_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_transaction_receipts`(workspace_id, transaction_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Record only after every preceding DDL statement has succeeded. Stop on any import error.
INSERT INTO `justirl2_plenact_m1_stage`.`m1_schema_migrations` (migration_id, source_sha256, applied_at_utc, applied_by)
VALUES ('001_core', 'cb58318d79e2afe764400390012abf85bbd6bf34940e12da8556f75fed025fc8', UTC_TIMESTAMP(6), CURRENT_USER());

SELECT migration_id, source_sha256, applied_at_utc FROM `justirl2_plenact_m1_stage`.`m1_schema_migrations`;
SELECT TABLE_NAME, ENGINE, TABLE_COLLATION FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'justirl2_plenact_m1_stage' ORDER BY TABLE_NAME;
