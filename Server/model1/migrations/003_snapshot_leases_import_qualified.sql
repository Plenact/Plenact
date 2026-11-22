-- Model 1.0 staging only. Requires verified 001_core and 002_invite_auth.
-- Run once after checking both new table names and migration ledger are absent.
-- DDL is nontransactional on MySQL 5.7; stop and inspect on any error.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_snapshot_leases` (
    snapshot_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    fence_sequence BIGINT NOT NULL,
    record_count BIGINT NOT NULL,
    created_at_utc DATETIME(6) NOT NULL,
    expires_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (snapshot_id),
    KEY m1_snapshot_workspace (workspace_id),
    KEY m1_snapshot_expiry (expires_at_utc),
    CONSTRAINT m1_snapshot_workspace_fk FOREIGN KEY (workspace_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_workspaces`(workspace_id),
    CONSTRAINT m1_snapshot_account_fk FOREIGN KEY (account_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_accounts`(account_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_snapshot_records` (
    snapshot_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    ordinal BIGINT NOT NULL,
    record_type VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    server_envelope JSON NOT NULL,
    PRIMARY KEY (snapshot_id, ordinal),
    UNIQUE KEY m1_snapshot_record_identity (snapshot_id, record_type, record_id),
    CONSTRAINT m1_snapshot_record_lease_fk FOREIGN KEY (snapshot_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_snapshot_leases`(snapshot_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO `justirl2_plenact_m1_stage`.`m1_schema_migrations`
    (migration_id, source_sha256, applied_at_utc, applied_by)
VALUES ('003_snapshot_leases', '61acedc898e6d7e0b42413414552a48c9d5e6f53b31ff1ffcf186cb2fd831e86', UTC_TIMESTAMP(6), CURRENT_USER());
SELECT migration_id, source_sha256 FROM `justirl2_plenact_m1_stage`.`m1_schema_migrations`
WHERE migration_id = '003_snapshot_leases';
SELECT TABLE_NAME, ENGINE, TABLE_COLLATION FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'justirl2_plenact_m1_stage'
AND TABLE_NAME IN ('m1_snapshot_leases', 'm1_snapshot_records');
