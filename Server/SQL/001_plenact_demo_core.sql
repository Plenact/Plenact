-- Plenact shared-demo schema, version 1.
-- Apply once to the new Plenact database after testing against Bluehost Percona.
-- This migration creates tables only; it does not seed users or Board content.
-- All *_at_utc columns are UTC DATETIME(6) values written by the server/API.

CREATE TABLE schema_migrations (
    migration_version INT UNSIGNED NOT NULL,
    migration_name VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    checksum_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    applied_at_utc DATETIME(6) NOT NULL,
    applied_by VARCHAR(80) NOT NULL,
    PRIMARY KEY (migration_version),
    UNIQUE KEY uq_schema_migration_name (migration_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE demo_users (
    user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    username VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    email VARCHAR(254) NULL,
    password_hash VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_status ENUM('active', 'disabled') NOT NULL DEFAULT 'active',
    account_role ENUM('board_editor', 'member') NOT NULL DEFAULT 'member',
    schema_version SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    record_revision INT UNSIGNED NOT NULL DEFAULT 1,
    created_at_utc DATETIME(6) NOT NULL,
    updated_at_utc DATETIME(6) NOT NULL,
    created_by_user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    updated_by_user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    storage_origin VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_demo_users_username (username),
    UNIQUE KEY uq_demo_users_email (email),
    KEY ix_demo_users_status (account_status),
    CONSTRAINT fk_demo_users_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES demo_users (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_demo_users_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES demo_users (user_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE demo_user_sessions (
    session_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    token_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    issued_at_utc DATETIME(6) NOT NULL,
    expires_at_utc DATETIME(6) NOT NULL,
    revoked_at_utc DATETIME(6) NULL,
    PRIMARY KEY (session_id),
    UNIQUE KEY uq_demo_session_token (token_sha256),
    KEY ix_demo_sessions_user_expiry (user_id, expires_at_utc),
    CONSTRAINT fk_demo_sessions_user FOREIGN KEY (user_id)
        REFERENCES demo_users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE demo_login_limits (
    username_key_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    failure_count SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    window_started_at_utc DATETIME(6) NOT NULL,
    locked_until_utc DATETIME(6) NULL,
    updated_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (username_key_sha256)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE demo_import_batches (
    import_batch_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    idempotency_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_name VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    batch_status ENUM('started', 'completed', 'failed') NOT NULL,
    source_item_count INT UNSIGNED NOT NULL DEFAULT 0,
    result_item_count INT UNSIGNED NOT NULL DEFAULT 0,
    created_at_utc DATETIME(6) NOT NULL,
    completed_at_utc DATETIME(6) NULL,
    created_by_user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    PRIMARY KEY (import_batch_id),
    UNIQUE KEY uq_demo_import_idempotency (idempotency_key),
    CONSTRAINT fk_demo_import_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES demo_users (user_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE demo_boards (
    board_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    board_key VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    title VARCHAR(160) NOT NULL,
    visibility ENUM('shared_demo') NOT NULL DEFAULT 'shared_demo',
    content_editor_user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    current_revision BIGINT UNSIGNED NULL,
    created_at_utc DATETIME(6) NOT NULL,
    updated_at_utc DATETIME(6) NOT NULL,
    created_by_user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    updated_by_user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    storage_origin VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    PRIMARY KEY (board_id),
    UNIQUE KEY uq_demo_boards_key (board_key),
    CONSTRAINT fk_demo_boards_editor FOREIGN KEY (content_editor_user_id)
        REFERENCES demo_users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_demo_boards_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES demo_users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_demo_boards_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES demo_users (user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE demo_board_revisions (
    board_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision BIGINT UNSIGNED NOT NULL,
    schema_version SMALLINT UNSIGNED NOT NULL,
    board_document JSON NOT NULL,
    document_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    stored_at_utc DATETIME(6) NOT NULL,
    stored_by_user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    storage_origin ENUM('demo_seed', 'jim_edit', 'member_assignment', 'admin_action', 'migration') NOT NULL,
    import_batch_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    PRIMARY KEY (board_id, revision),
    KEY ix_demo_board_revisions_actor_time (stored_by_user_id, stored_at_utc),
    CONSTRAINT fk_demo_board_revisions_board FOREIGN KEY (board_id)
        REFERENCES demo_boards (board_id) ON DELETE CASCADE,
    CONSTRAINT fk_demo_board_revisions_user FOREIGN KEY (stored_by_user_id)
        REFERENCES demo_users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_demo_board_revisions_batch FOREIGN KEY (import_batch_id)
        REFERENCES demo_import_batches (import_batch_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE demo_boards
    ADD CONSTRAINT fk_demo_boards_current_revision
    FOREIGN KEY (board_id, current_revision)
    REFERENCES demo_board_revisions (board_id, revision)
    ON DELETE RESTRICT;

-- demo_board_revisions rows are immutable. The runtime DB user should have
-- SELECT/INSERT on revisions and only the required UPDATE on the Board head.