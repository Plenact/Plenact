This directory contains Plenact-owned server/API source and database migrations. It is separate from the read-only Database Demo reference project

## Status

Migration `001` was tested in the disposable `justirl2_test_Plenact` database, then applied on 2026-10-03 to the dedicated `justirl2_plenact` database on the Bluehost server reporting version `5.7.44-48`. All 7 expected tables are InnoDB; the migration filename, checksum, operator, and UTC timestamp are recorded in `schema_migrations`. The PHP API is deployed at `https://plenact.com/api/` on PHP 8.2. Editor and member accounts can sign in and read revision 1. Database provenance confirms a completed seed batch with 49 cards, 7 lists, and 13 labels; the app reported local data unchanged. Member-write authorization, stale-revision, and restore checks remain

## Layout

- [`SQL/`](SQL/README.md) - ordered schema migrations and database-specific setup notes
- [`api/`](api/) - HTTPS login/logout, invite-created user directory, shared Board snapshots, assignment operations, and the [route contract](api/README.md)
- [`tests/`](tests/) - local contract-validator checks

The current implementation phase uses a new shared demo database: Jim is the only canonical Board-content editor; other active users can browse the Board and manage only their own assignments. Production tenant isolation and private Boards are out of scope

## Security Boundary

- The app never connects directly to MySQL
- Runtime DB credentials stay outside the web root and source control
- Schema administration uses a separate privileged operator; the runtime DB user receives only needed DML permissions
- Passwords are accepted only over HTTPS and stored only as server-generated password hashes
- Bearer sessions are random, returned once, and stored on the server only as SHA-256 hashes. All API requests require HTTPS
- The current API strips device-local photo/video attachment references from shared Board snapshots; it does not synchronize attachment files

## Local Deployment Preparation

1. Migration `001` has been tested against Bluehost version `5.7.44-48` and applied to the dedicated `justirl2_plenact` database; do not rerun it
2. Use the separate `justirl2_plenact_limited` user for runtime access, granting only database-scoped `SELECT`, `INSERT`, `UPDATE`, and `DELETE` on `justirl2_plenact`. Uncheck `ALL PRIVILEGES` and leave schema/admin rights disabled. Keep `justirl2_plenact` out of `plenact-database.json`; this closed-demo DML grant is for synthetic data only and must be tightened before public launch
3. Deploy `api/*.php` under the chosen HTTPS-only web path and keep the private configuration directory outside `public_html`. `plenact-database.json` is for the runtime account; `admin-database.json` is a separate, temporary provisioning credential file
4. Run `cli/provision_board_editor.php` from an interactive PHP CLI terminal. It prompts without echo for Jim's unique password, creates the only `board_editor`, and prints the stable user ID. Remove `admin-database.json` after provisioning
5. In the app's Xcode build settings, set `PLENACT_API_BASE_URL` to the HTTPS API directory ending in `/`. Do not use an HTTP URL or commit populated credentials/configuration
6. Sign in as Jim in Account & Settings and explicitly initialize SampleData. The app maps the one known starter assignment (`Justin Reina`) to Jim's authenticated server ID; it does not upload the current local Board, local profile, or photo/video files
7. Verify reads, assignment restrictions, stale-revision conflicts, and backup/restore with synthetic accounts before inviting other demo users

The CLI provisioner requires `PLENACT_API_COMMON` only when the deployed `api/common.php` is not adjacent to the checked-out `Server/cli` folder. No Bluehost action has been performed by this repository tooling
- Never commit, log, or paste passwords, tokens, private configuration, or hosting session URLs
- Demo data is shared and non-private; use only synthetic, approved content