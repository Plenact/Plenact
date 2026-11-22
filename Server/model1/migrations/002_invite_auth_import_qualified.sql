-- Invite-only identity storage, staging only. No accounts are created by this migration.
-- Requires applied 001_core. MySQL 5.7 DDL is not transactional; stop on any error.
-- Credentials and sessions are operational data, never editable user-model records.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_password_credentials` (
    account_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    email_normalized VARCHAR(254) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    password_hash VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    credential_version BIGINT NOT NULL DEFAULT 1,
    created_at_utc DATETIME(6) NOT NULL,
    updated_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (account_id),
    UNIQUE KEY m1_password_email (email_normalized),
    CONSTRAINT m1_password_account_fk FOREIGN KEY (account_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_accounts`(account_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_private_sessions` (
    token_sha256 BINARY(32) NOT NULL,
    account_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    credential_version BIGINT NOT NULL,
    created_at_utc DATETIME(6) NOT NULL,
    expires_at_utc DATETIME(6) NOT NULL,
    revoked_at_utc DATETIME(6) NULL,
    PRIMARY KEY (token_sha256),
    KEY m1_session_account (account_id),
    KEY m1_session_expiry (expires_at_utc),
    CONSTRAINT m1_private_session_account_fk FOREIGN KEY (account_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_accounts`(account_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- HMAC-derived account/IP keys; never store raw passwords, session tokens, or IP addresses here.
-- Runtime must atomically reserve attempts before password verification, including unknown emails.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_login_limits` (
    bucket_key BINARY(32) NOT NULL,
    window_started_at_utc DATETIME(6) NOT NULL,
    attempt_count BIGINT NOT NULL,
    PRIMARY KEY (bucket_key),
    KEY m1_login_limit_expiry (window_started_at_utc)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO `justirl2_plenact_m1_stage`.`m1_schema_migrations`
    (migration_id, source_sha256, applied_at_utc, applied_by)
VALUES ('002_invite_auth', 'cfd94e68ba8b7675386aa4e9507886d71d71749cb04ba7bfc79efb2f1eca0feb', UTC_TIMESTAMP(6), CURRENT_USER());
SELECT migration_id, source_sha256 FROM `justirl2_plenact_m1_stage`.`m1_schema_migrations`
WHERE migration_id = '002_invite_auth';
