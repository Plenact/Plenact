This directory contains Plenact-owned server/API source and database migrations. It is separate from the read-only Database Demo reference project

## Status

The initial SQL schema and PHP API are local drafts. No migration has been applied to Bluehost, no endpoint is deployed, and no account or Board content has been uploaded

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

1. Test `SQL/001_plenact_demo_core.sql` against a disposable server matching the Bluehost MySQL/Percona version; do not apply this unverified draft to the live database
2. Deploy `api/*.php` under the chosen HTTPS-only web path and keep the private configuration directory outside `public_html`. `database.json` is for the least-privilege runtime account; `admin-database.json` is a separate, temporary provisioning credential file
3. Run `cli/provision_board_editor.php` from an interactive PHP CLI terminal. It prompts without echo for Jim's unique password, creates the only `board_editor`, and prints the stable user ID. Remove `admin-database.json` after provisioning
4. In the app's Xcode build settings, set `PLENACT_API_BASE_URL` to the HTTPS API directory ending in `/`. Do not use an HTTP URL or commit populated credentials/configuration
5. Sign in as Jim in Account & Settings and explicitly initialize SampleData. The app maps the one known starter assignment (`Justin Reina`) to Jim's authenticated server ID; it does not upload the current local Board, local profile, or photo/video files
6. Verify reads, assignment restrictions, stale-revision conflicts, and backup/restore with synthetic accounts before inviting other demo users

The CLI provisioner requires `PLENACT_API_COMMON` only when the deployed `api/common.php` is not adjacent to the checked-out `Server/cli` folder. No Bluehost action has been performed by this repository tooling
- Never commit, log, or paste passwords, tokens, private configuration, or hosting session URLs
- Demo data is shared and non-private; use only synthetic, approved content