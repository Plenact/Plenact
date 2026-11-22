# Plenact database checkpoint — November 22, 2026

Database work is paused at the user's request while product ideas are discussed. Do not resume hosting changes merely because this checkpoint is read.

## Exact resume point

Migration **005_lifecycle_jobs** is prepared locally; its phpMyAdmin import has **not been confirmed**. The last verified read-only preflight found zero 005 ledger rows and zero new lifecycle tables. That observation predates this checkpoint; inspect current state before importing, since the user may have performed the import independently.

- Target database: `justirl2_plenact_m1_stage` only.
- Import artifact: `Server/model1/migrations/005_lifecycle_jobs_import_qualified.sql`.
- Source: `Server/model1/migrations/005_lifecycle_jobs.sql`.
- Expected source SHA-256: `339df2a670804b97958e804aa4aab579d9fbdf59ac30024d0a8d423232889f92`.
- New tables: `m1_lifecycle_jobs`, `m1_lifecycle_blob_targets`, `m1_backup_artifacts`.
- Expected import evidence: one ledger row plus three InnoDB / utf8mb4_unicode_ci table rows. The import creates storage only and schedules no deletion.
- If partially applied, stop and inspect; MySQL 5.7 DDL is not transactional. Never rerun blindly, drop partial tables, broaden runtime DDL privileges, or edit applied migration sources.

## Verified state before pause

Migrations 001–004 were applied and their exact hashes checked. Invite-only email/password authentication, core native data reads/writes, snapshots/change feeds, verified binary upload/commit/download and HTTP Range behavior passed synthetic staging integration tests. Diagnostic accounts, rows and files were cleaned up; the actual invited workspace was untouched. Last remote verification showed authentication, data reads/writes and assets disabled. No remote state was rechecked or changed merely to create this checkpoint.

Lifecycle confirmation/recent-auth/deadline helpers and a signed append-only deletion journal are locally prepared/tested. No real deletion journal/key, accepted deletion, lifecycle worker schedule, restore guard activation, public purge or account-deletion route has been established.

## After the import is verified

Freeze 005 in `Server/model1/migrations/applied-staging.json`, provision the private lifecycle journal safely, implement/test acceptance, cleanup workers, restore guards and exact receipt recovery with synthetic accounts only. Verify immediate session revocation, referenced-asset refusal, retry safety and primary/backup deadlines before activating lifecycle routes. Backup/restore rehearsal, full capability publication, client activation/outbox synchronization and cross-platform acceptance remain outstanding.

## Access and repository boundaries

Authorized SSH access uses a dedicated local key outside the repository; do not copy private keys, passwords, tokens, cPanel session URLs or runtime config contents into notes. Hosting account access is account-wide technically; work remains scoped to the agreed staging roots/database. Existing website/community/Version 0 demo and unrelated databases/backups must be preserved.

This checkpoint was written without staging or committing changes. Existing staged updates were left as found.

See `Stage-2-Bluehost-Inventory.md` and `Server/model1/README.md` for detailed evidence and implementation history.
