-- Model 1.0 staging lifecycle foundation. Requires verified migrations 001-004.
-- Run once after an explicit absence preflight. MySQL 5.7 DDL is not transactional.
-- No deletion is scheduled or performed by this migration. Runtime enforces deadline relationships.
-- Intentionally no account/workspace FK: minimal deletion receipts/guards must survive primary cleanup.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_lifecycle_jobs` (
    job_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    job_kind VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    asset_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    operation_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_sha256 BINARY(32) NOT NULL,
    requesting_session_sha256 BINARY(32) NOT NULL,
    receipt JSON NOT NULL,
    accepted_at_utc DATETIME(6) NOT NULL,
    primary_deadline_utc DATETIME(6) NOT NULL,
    backup_deadline_utc DATETIME(6) NOT NULL,
    primary_completed_at_utc DATETIME(6) NULL,
    backup_completed_at_utc DATETIME(6) NULL,
    failed_attempt_count BIGINT NOT NULL DEFAULT 0,
    last_error_code VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    PRIMARY KEY (job_id),
    UNIQUE KEY m1_lifecycle_account_operation (account_id, operation_id),
    KEY m1_lifecycle_primary_due (primary_completed_at_utc, primary_deadline_utc),
    KEY m1_lifecycle_backup_due (backup_completed_at_utc, backup_deadline_utc)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Capture only generated storage identities. No client filenames, credentials or byte copies.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_lifecycle_blob_targets` (
    job_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    blob_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    asset_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    PRIMARY KEY (job_id, blob_id),
    CONSTRAINT m1_lifecycle_target_job_fk FOREIGN KEY (job_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_lifecycle_jobs`(job_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Inventory only service-managed backups; this does not govern unrelated cPanel/provider backups.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_backup_artifacts` (
    backup_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at_utc DATETIME(6) NOT NULL,
    expires_at_utc DATETIME(6) NOT NULL,
    byte_length BIGINT NOT NULL,
    sha256 BINARY(32) NOT NULL,
    removed_at_utc DATETIME(6) NULL,
    PRIMARY KEY (backup_id),
    KEY m1_backup_expiry (removed_at_utc, expires_at_utc)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO `justirl2_plenact_m1_stage`.`m1_schema_migrations`
    (migration_id, source_sha256, applied_at_utc, applied_by)
VALUES ('005_lifecycle_jobs', '339df2a670804b97958e804aa4aab579d9fbdf59ac30024d0a8d423232889f92', UTC_TIMESTAMP(6), CURRENT_USER());
SELECT migration_id, source_sha256 FROM `justirl2_plenact_m1_stage`.`m1_schema_migrations`
WHERE migration_id='005_lifecycle_jobs';
SELECT TABLE_NAME, ENGINE, TABLE_COLLATION FROM information_schema.TABLES
WHERE TABLE_SCHEMA='justirl2_plenact_m1_stage'
AND TABLE_NAME IN ('m1_lifecycle_jobs','m1_lifecycle_blob_targets','m1_backup_artifacts');
