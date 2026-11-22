-- Read-only. Expect core_source_matches=1, auth_migration_rows=0, auth_tables_present=0.
SELECT source_sha256 = 'cb58318d79e2afe764400390012abf85bbd6bf34940e12da8556f75fed025fc8' AS core_source_matches
FROM `justirl2_plenact_m1_stage`.`m1_schema_migrations` WHERE migration_id = '001_core';
SELECT COUNT(*) AS auth_migration_rows FROM `justirl2_plenact_m1_stage`.`m1_schema_migrations`
WHERE migration_id = '002_invite_auth';
SELECT COUNT(*) AS auth_tables_present FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'justirl2_plenact_m1_stage'
AND TABLE_NAME IN ('m1_password_credentials', 'm1_private_sessions', 'm1_login_limits');
