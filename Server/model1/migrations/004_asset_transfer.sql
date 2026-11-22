-- Model 1.0 staging asset transfer. Requires verified migrations 001-003.
-- Run once after an explicit absence preflight. DDL is not transactional on MySQL 5.7.
-- Chunks are private unverified staging bytes; only a verified commit may publish a blob.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_asset_uploads` (
    upload_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    asset_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    asset_revision BIGINT NOT NULL,
    byte_length BIGINT NOT NULL,
    sha256 BINARY(32) NOT NULL,
    chunk_count INT NOT NULL,
    created_at_utc DATETIME(6) NOT NULL,
    expires_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (upload_id),
    KEY m1_upload_workspace (workspace_id),
    KEY m1_upload_expiry (expires_at_utc),
    CONSTRAINT m1_upload_workspace_fk FOREIGN KEY (workspace_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_workspaces`(workspace_id),
    CONSTRAINT m1_upload_account_fk FOREIGN KEY (account_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_accounts`(account_id),
    CONSTRAINT m1_upload_asset_fk FOREIGN KEY (workspace_id, asset_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_record_heads`(workspace_id, record_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `justirl2_plenact_m1_stage`.`m1_asset_chunks` (
    upload_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    chunk_index INT NOT NULL,
    sha256 BINARY(32) NOT NULL,
    chunk_bytes MEDIUMBLOB NOT NULL,
    PRIMARY KEY (upload_id, chunk_index),
    CONSTRAINT m1_chunk_upload_fk FOREIGN KEY (upload_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_asset_uploads`(upload_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Private locator is generated server-side, never derived from a client filename or digest.
-- Multiple historical originals remain until explicit purge/account deletion, not ordinary edits.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_asset_blobs` (
    blob_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    asset_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    published_revision BIGINT NOT NULL,
    byte_length BIGINT NOT NULL,
    sha256 BINARY(32) NOT NULL,
    verified_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (blob_id),
    KEY m1_blob_asset (workspace_id, asset_id, published_revision),
    CONSTRAINT m1_blob_asset_fk FOREIGN KEY (workspace_id, asset_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_record_heads`(workspace_id, record_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Durable exact-request deduplication for asset operations, separate from editable content.
CREATE TABLE `justirl2_plenact_m1_stage`.`m1_asset_operations` (
    workspace_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    operation_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    operation_kind VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    epoch CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_sha256 BINARY(32) NOT NULL,
    result JSON NOT NULL,
    stored_at_utc DATETIME(6) NOT NULL,
    PRIMARY KEY (workspace_id, operation_id),
    CONSTRAINT m1_asset_operation_workspace_fk FOREIGN KEY (workspace_id)
        REFERENCES `justirl2_plenact_m1_stage`.`m1_workspaces`(workspace_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
