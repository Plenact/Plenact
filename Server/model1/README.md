# Private Model 1.0 staging preparation

**Status: migrations 001–003 and private authentication/core native data routes are deployed on isolated Bluehost staging and have passed synthetic HTTPS acceptance on November 21, 2026. Routes are disabled outside diagnostics. Explicit purge/account deletion, recovery acceptance, and client synchronization remain incomplete; verified asset upload/download HTTPS checks now pass.**

The existing `Server/api` and `Server/SQL/001_plenact_demo_core.sql` remain the separate Version 0 shared demo. Do not use its session tokens, database migration, or SampleData seeding as private Model 1.0 authentication or synchronization.

`contract-pin.json` identifies the exact 218 published JSON inputs (OpenAPI, schemas and fixtures) reviewed for the staging implementation. Verify them without changing either contract or server:

```sh
python3 Server/model1/verify_contract.py
```

An added, removed or changed contract input fails verification. A contract revision needs explicit compatibility review and a reviewed pin update. Passing this check does not imply schema validation, authorization, synchronization, backup recovery, or cross-device acceptance has passed.

The [live hosting inventory and candidate layout](../../Doc/Database/Stage-2-Bluehost-Inventory.md) record the current evidence, staging boundaries and remaining verification. Implementation must follow the published [logical storage obligations](../../Doc/Strategy/Architecture/User-Data-Model/Logical-Storage.md) and [synchronization contract](../../Doc/Strategy/Architecture/User-Data-Model/Synchronization.md).


## Staging database preflight

On November 21, the operator confirmed creation of `justirl2_plenact_m1_stage` in cPanel. Creation is distinct from schema deployment or runtime readiness. In phpMyAdmin select that database and run `migrations/000_preflight.sql`. It uses SELECT statements only and explicitly inspects `justirl2_plenact_m1_stage` and reports its name, object counts, and default character set/collation regardless of connection context. Continue only when that exact schema is returned and every object count is zero. This preflight does not grant privileges or apply a migration.


## Core migration preparation history (now applied)

The explicit-schema preflight returned zero objects and default `utf8 / utf8_unicode_ci` on November 21. `migrations/001_core.sql` fully qualifies every table and targets **only** `justirl2_plenact_m1_stage`, changes its default to `utf8mb4 / utf8mb4_unicode_ci`, and creates eight InnoDB tables:

- Migration ledger; operational accounts and private-workspace ownership/counters.
- Current record heads/tombstones; complete immutable server revisions; ordered change references.
- Successful transaction and operation receipts with exact request-byte SHA-256 and unique request identities.

This is a storage foundation, not a complete or conformant service. Authentication/session stores, frozen snapshots, upload/media verification and lifecycle/deletion/recovery stores still need migrations and implementation. API code must enforce ownership, immutable types/epochs, positive signed-64-bit revisions, gap-free sequence allocation, JSON schema and whole-graph validity, and atomic commits of content plus receipts. MySQL 5.7 does not enforce CHECK constraints, so the migration does not rely on them. A schema alone does not prove these semantics.

Prepare the reproducible phpMyAdmin import:

```sh
python3 Server/model1/verify_contract.py
python3 Server/model1/build_core_import.py
```

`migrations/001_core_import_qualified.sql` contains that DDL plus an exact-source-checksum ledger entry and readback queries. Re-run the explicit empty-schema preflight immediately before importing. Import once through phpMyAdmin with stop-on-error behavior. MySQL 5.7 DDL is not transactional: on any error, stop and inspect partial state rather than rerunning or dropping objects. Do not run Version 0 migration 001 or the illustrative model SQL. No existing database is upgraded or reused.

No MySQL server is available in the current local test environment, so the prepared DDL has not yet been executed against MySQL/Percona. Its first live import and constraint tests must be recorded separately. No runtime login should be enabled until the service and remaining storage are ready.


### Corrected import after context error

The first live attempt reported an information_schema access-denied error despite a generic green import banner. Archived context-dependent files are forensic records, not imports to run. The current source and generated import use schema-qualified table and foreign-key references and never depend on USE. Repeat the explicit preflight before any retry; inspect partial tables/ledger entries if present. Do not grant information_schema write privileges or erase a partial schema as a workaround. The revised import remains unexecuted until the operator supplies new results.


### Core applied; next storage checks

The operator's corrected-import readback confirms eight InnoDB tables and the core migration ledger entry. `migrations/applied-staging.json` freezes the applied source fingerprint. Do not edit or rerun applied migration 001; use a new migration for subsequent work. Earlier unexecuted/pending notes above describe the preparation and failed-attempt history.

Import `tests/core_storage_probe.sql` through the same phpMyAdmin workflow to test physical JSON/Unicode storage, linked records, receipt-hash bytes, and rollback. It generates fresh diagnostic UUIDs, inserts only temporary operator fixtures, and ends with ROLLBACK plus seven zero-count checks. There is no COMMIT or schema change. The diagnostic `storage_probe` data is not a protocol fixture and cannot demonstrate typed validation, conflicts, idempotent HTTP requests, concurrent counter allocation, authentication, or account isolation. Those remain required API/transaction integration tests.


### Storage probe and hosting readiness confirmed

On November 21, operator readback confirmed the core checksum, all three physical storage checks, and all seven zero counts after rollback. The separate staging runtime database user connects successfully through CLI; its private configuration file is permission 600. The staging HTTPS diagnostic returned PHP 8.2.36/LiteSpeed with the checked PDO/crypto/Unicode/JSON extensions. See the inventory for precise evidence and remaining checks. These results do not deploy authentication or demonstrate protocol conformance. Initial sign-in selection and private service implementation are next.


### Invite-only email/password selected

The operator selected invite-only email/password for the initial service, superseding Google-first preparation. Google and Apple remain future possibilities; no OAuth configuration is needed now. Accounts will be provisioned privately by an operator, with no public registration or implied email verification. Account linking must never occur solely because email addresses match.

Migration 002 is prepared, not applied: separate password credentials, hashed opaque native sessions, and atomic login-attempt buckets. The service must enforce normalized ASCII email policy, password hashing and verification, generic login failures, per-account and per-IP limits, expiry/revocation and credential-version checks. Session expiry never removes local work. Browser cookie authentication is not enabled by this native-client foundation. Password-reset delivery and public registration remain outside this invite-only phase.

Run `migrations/002_preflight.sql` first and inspect its three results (1, 0, 0). Do not import 002 until reviewed preflight evidence is returned. DDL is not transactional; stop on any error and inspect partial state. No login route, credential tool, test account or session has been deployed by these files.


### Invite authentication implementation (local; not deployed)

Migration 002 was applied and its full checksum equality and three InnoDB/utf8mb4 tables confirmed by operator output. Applied sources 001 and 002 are frozen. `private/auth.php` implements staging-only PDO access, sodium Argon2id password hashing, atomic account/workspace provisioning, committed account/IP attempt reservations, seven-day hashed opaque sessions, authentication and revocation. `cli/create_account.php` reads passwords from a hidden controlling terminal, rejects duplicate accounts atomically, and issues no session. No email verification is implied. Initial policy uses lowercased ASCII email addresses and passwords of 15–1024 bytes.

`cli/init_auth.php` creates owner-only authentication configuration without overwriting it and keeps HTTP login disabled. `public/auth.php` is a native-client identity boundary using `?action=login` (POST JSON email/password), `?action=me` (GET bearer) and `?action=logout` (POST bearer). It requires HTTPS, rejects browser Origin/cookie requests, sends no-store JSON, and uses generic authorization errors. It must not be enabled until database/login/rate-limit and HTTP integration checks pass. It is separate from the pinned user-data OpenAPI. No record routes are implemented. Hosting proxy behavior, rate-limit concurrency, session lifecycle, and timing behavior require live verification. Initial rate limits are ten attempts per normalized email and fifty per source IP in fifteen minutes; forwarding headers are not trusted.

The private preparation archive includes only `private/auth.php`, three CLI tools and `cli/check_auth_storage.php`, never credentials or public endpoints. Upload/extract beneath the private staging root; preserve `config/database.json`. First run the storage checker, which uses fresh synthetic identities in one transaction and rolls them back even on failures. It checks sodium passwords, session ownership mapping, invalid tokens, expiry, revocation, disabled accounts and credential changes, and post-rollback absence. It does not test the committing login/provisioning paths or assert full API isolation. Stop on failure. No live authentication test has yet been returned.


### API implementation milestone — November 21

Invite authentication has now passed operator-supplied HTTPS tests (401 unauthenticated, 403 Origin/cookie, 415 unsupported media, 200 login/me/logout, subsequent 401, final disabled 503). Sequential and four-worker concurrent attempt limits passed after bounded whole-transaction deadlock retries were added. The empty-POST diagnostic originally received hosting HTTP 406; explicit text/plain with a body reached the application and returned 415. HTTP authentication remains disabled between diagnostics.

A dedicated Mac SSH key was authorized by the operator for the hosting account. Its private key is outside the repository. This is account-level access, not filesystem-enforced staging confinement; operations remain scoped to the two agreed staging roots/database. No key material, passwords, tokens, cPanel session URLs or auth configuration contents belong in this repository.

`private/data.php` implements owner-authorized immutable head/revision reads for account/workspace and individual records/tombstones. SQLite integration checks exercise foreign/unknown/type boundaries and fail-closed stored identity checks. The uploaded private MySQL diagnostic passed two-account reads and generic foreign/unknown 404 responses and rolled back its synthetic records. `private/bootstrap.php` prepares explicit initialization of account/workspace canonical records only in an untouched workspace; its envelopes pass the pinned Model 1.0 schema and semantic validators with millisecond UTC timestamps. No existing invited workspace has been initialized by this work.

`private/transactions.php` is an internal engine requiring explicit request and complete-candidate graph validator callbacks. It locks the owned workspace, compares epoch/revisions, hashes exact input bytes, preserves successful receipt/operation identities, validates the proposed graph before writes, and atomically appends revisions/changes/receipts/counters. An isolated live MySQL diagnostic passed exact-byte replay, changed-byte rejection, ownership denial, revision conflicts, validator-rejection rollback, tombstones, and no resurrection. The diagnostic deliberately uses storage-only synthetic payloads and permissive callbacks: **it does not establish production typed or graph validation**. Its dedicated synthetic workspace/account and dependent rows were removed. It never touched the invited workspace. Asset metadata changes in this draft are conservatively rejected pending the proper upload/commit boundary; this is not complete contract behavior.

`public/index.php` and `.htaccess` are prepared locally, not deployed. Read routes are disabled by default and do not advertise full capabilities. Writes are not wired to HTTP. Production request/whole-graph validation, snapshots/cursors, asset upload/content, lifecycle routes, full HTTP data isolation, and backup/restore testing remain required before calling this a complete Model 1.0 API. Existing public auth.php remains separate. No client synchronization is implemented by this milestone.


### Strict write validation milestone

`validation/validator.py` rejects duplicate JSON keys, nonfinite numbers, invalid Unicode, request/schema limits, server-owned writes and document identity errors using the published Model 1.0 validator. It projects the complete locked candidate into the Model 1.0 workspace-export schema and existing membership/ownership/reference semantic checks, including explicit proven external-reference status and tombstones. This code does not import the working Model 1.1 assembler. PHP preserves nested object/array identity on storage and reads.

`private/validation.php` invokes that private process using argv without a shell, nonblocking pipes, a 30-second deadline, bounded diagnostic output and generic errors. Invalid content returns 422; worker/dependency failures fail closed with 503. The HTTP write route remains unwired.

Bluehost Python 3.9.25 has a virtual-environment creation issue (empty venv/bin); dependencies were instead installed with `pip --target` into the owner-only `validation-20261121-v1/dependencies` directory. System packages were not modified. The adjacent manifest fingerprints the deployed 218 JSON inputs, four validator modules, requirements and bridge script; those executable tooling sources are additional implementation inputs beyond the original contract JSON pin. Local schema/semantic, PHP process-bridge, object identity and negative graph tests pass.

The live `check_validated_writes.php` diagnostic committed all documents in an entirely synthetic 30-record candidate using real strict request and complete graph callbacks, validated exact-byte replay, card JSON round-trip and rejection of an orphan membership edit without mutation/receipt. It removed that diagnostic workspace/account and all dependent rows. The actual invited workspace is unchanged. Public data routes, snapshots/change cursors, assets/lifecycle and recovery acceptance still remain; this milestone does not establish a complete sync service.


### Snapshot/change-read preparation (migration 003 pending)

`private/cursors.php` authenticates compact base64url cursors with a separate 32-byte HMAC key; claims bind account/workspace/epoch, cursor kind, position, expiry and snapshot identity. `private/sync_reads.php` copies every current head/tombstone and its immutable server envelope under the workspace write lock into 30-minute snapshot leases. Continuations page frozen ordinals sorted by type/ID, preserve unsupported types opaquely, limit response count to 100 and encoded JSON bytes to 8 MiB, and expose the fence change cursor only on the final page. Change reads require consecutive revisions, retain the cursor sequence on empty pages, fail on expired or missing history, and bind restore epochs. Account ownership is checked against the database.

SQLite integration tests and pinned-schema/semantic validation pass for frozen paging across a later write, tombstones, retries, final cursor, ordered and empty changes, tampered/foreign/snapshot-mismatched cursors, expiry, and missing history. These are not MySQL or HTTP tests. Capability-offer validation was added to the private worker; this modified worker has not yet been redeployed.

Migration 003 adds only `m1_snapshot_leases` and `m1_snapshot_records` to the existing staging database. Read-only SSH preflight confirmed both earlier source hashes, zero 003 ledger rows and zero new tables. The source and qualified import are prepared and statically checked, not applied. The runtime login remains DML-only. The operator must import the new migration through phpMyAdmin; do not broaden runtime schema privileges. After exact ledger and engine/collation readback, freeze migration 003, deploy the private runtime update/key, and run synthetic MySQL sync-read tests before exposing these data routes. No invited workspace or public data router has been changed by this preparation.


### Snapshot migration and private MySQL integration verified

The operator imported 003 successfully; SSH readback confirmed its complete source fingerprint `61acedc898e6d7e0b42413414552a48c9d5e6f53b31ff1ffcf186cb2fd831e86` and InnoDB/utf8mb4 table attributes. Applied migration 003 is now frozen. The updated offer validator and private cursor/sync-read services were uploaded.

`cli/check_sync_reads.php` creates a dedicated synthetic workspace, uses strict request/graph validation to populate it, starts a snapshot with seven-record pages, writes a later revision, retries/follows frozen pages, retrieves that revision after the final fence cursor, and checks empty deltas, owner/tamper rejection, lease expiry and missing-history recovery. Live MySQL execution passed; every returned snapshot/change page also passed the pinned JSON schemas and semantic protocol checks locally. The test removed its snapshot rows/leases and all workspace/account dependencies and left the actual invited workspace untouched. Tombstone inclusion is separately covered by the SQLite integration test.

The 30-minute lease does not expire local client data; missing/90-day-expired change history requires resnapshot while preserving pending edits. Cursor keys used by these diagnostics are ephemeral, not production service keys. Public data-router wiring, HTTP data acceptance, persistent cursor-key provisioning, assets/lifecycle operations and recovery rehearsal remain pending. Authentication and public data writes remain disabled.


### Core data HTTPS acceptance passed

The previously unused staging `index.php` and `.htaccess` now route the native data endpoints. Owner-only `config/data-api.json` holds a separate persistent random cursor key and independently disabled read/write flags. The native bearer router connects `/me`, `/workspaces`, owner record reads, transactions, snapshot creation/continuation and changes to the tested services. JSON request limits, unsupported Content-Encoding rejection, Idempotency-Key matching, no-store responses, generic errors and Origin/cookie rejection are enforced. Full `/capabilities` remains unavailable because asset/lifecycle routes are unfinished. This is not complete Protocol 1.0 support.

`cli/check_http_data.php` temporarily enables only the data flags, provisions a synthetic account/session and canonical workspace, performs real HTTPS calls, then restores disabled flags and removes synthetic sessions/credentials/snapshot rows/leases/content/receipts/workspace/account. No existing invited workspace is initialized or modified. Tests passed owner `/me` and workspace records, unauthenticated/revoked-session 401, generic foreign/unknown 404, strict validated transactions, exact-byte replay, changed-byte idempotency rejection, current-revision conflict summaries, whole-graph rejection, a snapshot spanning two pages (>100 records) frozen across a later write, the matching post-fence change and an empty change page. Every response used no-store. Final disabled-mode read returned 503.

Schema validation caught a required empty `error.conflicts` field missing from early diagnostic error responses; this was corrected, covered by durable schema tests, redeployed and rerun. All **17** captured final HTTPS responses (records, errors, receipts, snapshot pages, change pages) then passed the pinned schemas and semantic validators. Read/write and authentication flags were independently confirmed disabled; data configuration permissions were 600. Asset upload/content/purge, account deletion/recent-auth flows, backup/restore and client outbox/sync acceptance remain. No staging promotion or app-facing activation has been performed.


### Asset transfer preparation (migration 004 pending)

`private/asset_chunks.php` prepares owner/epoch-bound 24-hour upload leases for existing described Asset revisions, a 64 MiB staging upload limit, exact 262144-byte chunks (short final chunk), sorted resumable indexes, binary-safe identical retries and conflicting-byte rejection. Unknown/foreign owners fail generically, stale metadata conflicts, checksums/length/indexes are checked, expired leases return upload_expired, and known empty files have zero chunks. Staging chunks are not verified originals. The strict upload request validator is prepared locally, not yet deployed.

SQLite binary integration and pinned session schema/semantic tests passed; MySQL/HTTP asset tests remain pending. Migration 004 prepares four tables for upload leases, chunk bytes, private blob locators and lifetime asset-operation receipts. It seeds nothing and alters no existing tables. Static guards and exact import provenance pass. Read-only staging preflight verified migrations 001-003, zero 004 ledger rows and zero new tables, with max_allowed_packet 268435456 bytes (well above one 256 KiB chunk). Operator phpMyAdmin import is required because runtime credentials remain DML-only. Do not edit an applied migration or grant runtime DDL. Verified file assembly/commit, authorized Range downloads, purge/account-deletion jobs and their deadlines are still implementation work, not established by this prepared schema. Public data routes remain disabled.


### Asset staging schema and private MySQL checks passed

Migration 004 was imported by the operator and independently verified through SSH: exact source SHA-256 `bdced641119b900fc91c4016ec400f3e03665ae091c62072912e02e454e6d26a`, four InnoDB/utf8mb4 tables. Its source is now frozen. Private upload request validation and chunk service were deployed; no public asset routes were wired.

`cli/check_asset_uploads.php` uses a fresh synthetic account/workspace, creates described opaque Asset metadata through real strict request/whole-graph transactions, then tests null/non-UTF-8 byte preservation, out-of-order resume, exact replay, conflicting replay, wrong digest/length/index, foreign owner, lease expiry and known-empty content. The live MySQL run passed and removed all diagnostic chunks, leases, records, receipts and account/workspace rows. The invited workspace was untouched. Responses satisfy the pinned upload-session schema and semantics. This establishes private **unverified chunk staging**, not committed blob verification or format validity (including PencilKit). Verified assembly/publication, authorized Range downloads, explicit purge and account deletion remain pending; no deletion deadline or recovery readiness is claimed. Public data/authentication flags remain disabled.


### Verified asset publication/download HTTPS acceptance passed

`private/blob_files.php` uses server-generated workspace/blob UUID paths under the private assets root, owner-only files, exclusive temporary creation and atomic no-overwrite publication. `private/asset_content.php` commits only after unchanged epoch/Asset revision, every chunk index/digest/length, assembled exact length and SHA-256 match. A verified descriptor, immutable revision/change, counter and exact-request operation result are committed together. If commit acknowledgement is ambiguous, the file is preserved for receipt recovery rather than removed. Ordinary metadata operations and asset commits share operation-ID uniqueness checks. Successful commit proof survives upload lease expiry. Original-byte metadata is immutable once verified; new original bytes require a fresh Asset UUID.

Owner-authorized retrieval opens the private file, checks its regular-file type, length and complete SHA-256 on that handle before returning bytes, then supports bounded/open/suffix ranges, strong If-Range matching, explicit invalid-range 416, safe attachment disposition and nosniff/no-store. Empty verified originals return a real zero-length 200; unavailable content returns an error. All bytes are served as application/octet-stream and are not rendered/decoded as native formats.

Private MySQL/file tests passed full verification, exact retry and changed-byte rejection, stale revision, incomplete assembly, foreign retrieval, proof after lease expiry, binary integrity and known-empty originals. HTTPS acceptance then passed upload staging/204 binary PUT, out-of-order resume, exact/conflicting retries, pre-verification unavailability, commit/replay, strong ETag, full/bounded/open/suffix download, If-Range mismatch restart, invalid-range 416, a second real synthetic account's denial, and empty-file publication/retrieval. All **11** captured asset JSON responses passed pinned schemas/semantics; binary bytes and headers were checked live. Core HTTPS data regression also passed after these shared changes.

A temporary random header probe established that PHP generated ETag while the hosting layer stripped it; the probe was removed. An API-directory-only `Header always set ETag` rule copies the application-generated verified ETag response header, preserving its strong digest through the hosting filter. No parent/global hosting rule or security setting was changed. Apache header-table behavior is documented at https://httpd.apache.org/docs/2.4/en/mod/mod_headers.html and expression response-header access at https://httpd.apache.org/docs/2.4/expr.html.

Public native asset routes are wired but gated by `assets_enabled` plus existing data flags. Diagnostics restore disabled settings and remove their synthetic files/chunks/leases/operations/content/accounts/sessions. The invited workspace remains untouched. Purge and account-deletion confirmation/recent-auth flows, deadline jobs/deletion guards, backup/restore acceptance, full capability advertisement, app activation and native sync remain incomplete. This is not a production launch or a full four-step-plan completion.


### Lifecycle foundation prepared (migration 005 pending)

Migration 005 adds three staging-only stores: lifecycle jobs with exact request/session digests and deadline receipts, generated blob targets, and service-managed backup artifact inventory. Jobs intentionally have no account/workspace foreign keys so minimal deletion receipts/restore guards can survive primary cleanup; blob targets reference jobs only. No account, purge, backup or deletion job is created by this DDL. It does not control unrelated cPanel/provider backups.

`private/lifecycle_policy.php` prepares server-side recent-auth checks: an active opaque session tied to current credentials and password-authenticated issuance less than five minutes old; the boundary, revocation and credential-change tests pass. Strict request modes require the exact deletion/purge literals and the explicit history-media acknowledgement. Synthetic receipt fixtures pass the pinned 24-hour primary and 30-day backup deadline semantics. These fixtures do not represent accepted real deletions.

`private/deletion_journal.php` prepares a signed owner-only append-only acceptance ledger outside the database/service-backup directory. It stores only generated target identities/digests/receipts, rejects conflicting overwrite/path/key/tamper attempts, and is intended to be verified/replayed before restored service activation. Tests use an ephemeral local journal only; no real journal/key has been provisioned or deletion accepted. Worker scheduling, restore gating, complete reference checks, immediate revocation and revoked-session exact-receipt recovery are still implementation requirements, not established behavior. Public lifecycle routes remain unavailable.

Read-only SSH preflight confirms migrations 001-004 match their frozen source hashes, zero 005 ledger rows, and zero new lifecycle tables. The non-destructive qualified import is prepared and statically checked; an operator phpMyAdmin import is required because runtime credentials remain DML-only. Do not grant runtime DDL or run deletes manually. No invited workspace or public route was changed by this preparation.
