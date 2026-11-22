# Stage 2: Bluehost capability inventory

Status: **Isolated staging schema 001–003, authentication and core native data HTTPS acceptance verified. Routes are disabled outside diagnostics. Asset/lifecycle operations, backup/restore acceptance and client synchronization remain pending.** Updated November 21, 2026.

The next task in the [Desktop Extension Plan](../Core/Plenact-Desktop-Extension-Plan.md) is a read-only inventory before defining private Model 1.0 staging. The existing shared demo must remain separate.

## Current evidence

- Repository deployment records describe MySQL `5.7.44-48`, PHP 8.2, and the shared Version 0 demo. These are historical records, not a current hosting inventory.
- The operator confirmed access to cPanel Terminal.
- On November 20, 2026, operator-supplied output from `php -v` and `php -m` confirms PHP CLI **8.3.37**, Zend Engine 4.3.37, OPcache 8.3.37, and ionCube Loader 15.5.1. Required CLI capabilities are present: PDO/pdo_mysql, mysqli/mysqlnd, openssl, curl, mbstring, fileinfo, intl, sodium, and JSON. GD, Imagick, and ZIP are also available. This does not establish the web/FPM PHP version, database server version, or database grants.
- Operator-supplied CLI settings confirm `memory_limit=512M`, `max_execution_time=0` (CLI), `upload_max_filesize=64M`, `post_max_size=64M`, and `max_file_uploads=20`. Web/FPM limits and account quotas remain unverified.
- The initial depth-five `*/api/common.php` lookup returned no path. The deployed API location is unresolved; this is not evidence that the API or database is absent.
- A broader depth-eight home-directory lookup found unrelated WordPress/vendor `common.php` files but no Plenact API helper. The operator confirmed home `/home2/justirl2` and web directory `/home2/justirl2/public_html`. The `plenact.com` document root and expected private configuration directory still need verification. Unrelated application files were not inspected or used.
- The cPanel API 2 lookup with `--user=justirl2` failed with a normal-user `setuid` error. Its downstream “No document root returned” message does not establish domain absence. Do not repeat the user-switching flag in this account terminal.
- Directory discovery confirms `/home2/justirl2/plenact-private` (and an additional `.cpanel/ea-php-cli/plenact-private` path). No configuration contents have been shared. The existing runtime configuration can now be tested in place with PDO, independently of the missing API-helper lookup.
- Operator-provided PDO results confirm a successful connection using the existing private runtime configuration, server version **5.7.44-48**, and **seven InnoDB base tables**. No authored rows or credentials were returned.
- SHOW GRANTS reported global `USAGE` without grant option, plus `SELECT, INSERT, UPDATE, DELETE` without grant option on a scope the initial probe labeled `other_or_table`. Global USAGE is not global DML permission. Exact applicability to the connected database remains to be verified; escaped underscores in database grant patterns can cause the initial exact comparison to misclassify scope.
- A subsequent `information_schema.SCHEMA_PRIVILEGES` lookup filtered by `DATABASE()` and the current grantee returned an empty array. This is inconclusive: successful earlier SELECTs prove read access, and SHOW GRANTS explicitly returned DML privileges. Direct normalization/comparison of SHOW GRANTS scope is still needed before assigning the grant to the selected schema.
- The direct SHOW GRANTS comparison, normalizing escaped literal underscores/percent signs, confirms `SELECT, INSERT, UPDATE, DELETE` at the **connected database** scope, without `GRANT OPTION`. A separate global `USAGE` entry also has no grant option. This verifies declared runtime privileges; no DML or DDL was executed, and migration-operator privileges remain unverified.
- Operator-provided cPanel screenshots confirm the `plenact.com` domain row is configured for **PHP 8.2 (`ea-php82`), marked Inherited**. PHP-FPM shows the disabled indicator. The system default shown above is PHP 8.3, and CLI is separately verified as PHP 8.3.37; do not substitute either for the domain's displayed PHP 8.2 assignment. Web patch version, extensions, and request limits remain unverified.
- cPanel Statistics displays **10.2 GB / 50 GB disk usage (20.39%)**, **15 / 100 databases**, and **317,082 files / infinity**. Thus roughly 39.8 GB of the displayed disk allocation and 85 database slots remain; this is a snapshot, not a guarantee of inode, database-size, or provider resource policies.
- Backup Wizard offers Back Up and Restore, with database and home-directory coverage described. The screenshot does not show a completed backup, backup date, retention policy, off-host copy, or successful restore rehearsal.
- The Bluehost domain-registration screen shows `plenact.com` active but does not show its hosting document root. Use **Domains inside cPanel Tools** to identify that mapping; do not infer it from the registration page or private-config location.
- Additional operator screenshots identify the database as **Percona Server 5.7.44-48**, with phpMyAdmin 5.2.3. phpMyAdmin's cPanel-served runtime reports PHP 8.4.28; this is separate from both the domain's configured PHP 8.2 and Terminal PHP 8.3.37.
- The database tree shows existing `justirl2_plenact`, `justirl2_plenact_community`, `justirl2_plenact_dev`, and `justirl2_test_Plenact` entries. Their names do not establish disposable staging status; do not overwrite or reuse any without inspecting its purpose and contents through an agreed staging review. Existing user entries include the known limited runtime account; the confirmed runtime grants came from its connection, not from these user-list labels.
- These screenshots show Backup Wizard, phpMyAdmin, and Manage My Databases; they still do not show the cPanel Domains table or Plenact document root.
- cPanel Domains now confirms **`/home2/justirl2/public_html/plenact`** as the `plenact.com` document root, with no redirect. The File Manager view of that folder shows `.archived`, `assets`, `community`, `tools`, `index.html`, and `README.md`; no root `api` or `staging` directory is visible in that screenshot. This is a directory snapshot, not proof that every older API route is absent.
- The confirmed `/home2/justirl2/plenact-private` directory is outside that document root. Permissions and service write behavior still need verification before using a separate staging subdirectory.
- No local SSH connection is configured. Browser automation failed before reading the hosting session; no live hosting inspection or changes were performed.
- `Server/cli/inventory_host.php` is prepared and locally checked. Local PHP output describes the development Mac, not Bluehost.

## Run the inventory

Keep the tool outside `public_html`; it also rejects non-CLI execution. Transfer it through the hosting account's existing file-management workflow. It does not deploy an API, initialize staging, or alter schemas, grants, records, or files.

First inspect the CLI runtime:

```sh
php /private/path/inventory_host.php --runtime-only
```

Then inspect the existing connection using its existing private configuration. Substitute the actual deployed helper and existing private storage directory:

```sh
php /private/path/inventory_host.php \
  --common=/actual/deployed/api/common.php \
  --config=plenact-database.json \
  --storage=/existing/private/storage
```

The helper already honors `PLENACT_PRIVATE_DIR` if the deployment needs it. Do not put credentials into shell arguments or the report. The default configuration is the existing runtime account, not the schema administrator.

Output contains allowlisted PHP metadata, database server version, aggregate table-engine counts, redacted grant scopes/privileges, and storage permission/filesystem-free-space metadata. It does not read authored Card/Note records or print DB identities, credentials, hashes, filesystem paths, or raw grants. A database probe failure is reported generically; inspect private configuration locally rather than sharing its contents.

## Evidence still required

| Area | Required evidence | Current status |
| --- | --- | --- |
| Database | MySQL 5.7.44-48; seven InnoDB tables; database-wide SELECT/INSERT/UPDATE/DELETE, no grant option | Runtime metadata verified; separate migration-operator grants pending |
| CLI runtime | PHP CLI 8.3.37, required extensions, 512M memory, 64M upload/post limits, 20 files; CLI execution time 0 | Verified from operator-provided output |
| Web runtime | Domain row shows inherited ea-php82 / PHP 8.2; PHP-FPM disabled | Assignment verified; patch version, extensions and web limits pending |
| Capacity | 10.2/50 GB disk; 15/100 databases; 317,082 files with no finite UI limit displayed | cPanel snapshot verified; database-size/provider resource limits unverified |
| Private storage | Existing directory permissions and separation from public web paths | Pending |
| Staging boundary | Document root confirmed; isolated candidate layout below | Local preparation; no remote resources created |
| Recovery | Backup Wizard Back Up/Restore controls present | UI availability verified; actual backups, retention and restore rehearsal pending |

A read-only probe cannot prove transactional writes, grant enforcement, successful backups/restores, or synchronized clients. Those require the subsequent isolated staging acceptance work. Do not mark Stage 2 complete based on this inventory alone.

## Local verification

```sh
php -l Server/cli/inventory_host.php
php Server/tests/host_inventory_test.php
php Server/cli/inventory_host.php --runtime-only
```

The tests cover secret/identifier redaction, precise privilege classification, column-limited grants, delegation flags, and metadata-only storage inspection.


## Isolated staging layout prepared for implementation

These are candidate names/paths, not deployed resources or permission grants. Verify absence before creating anything, and never overwrite an existing resource.

| Resource | Candidate |
| --- | --- |
| New staging database | `justirl2_plenact_m1_stage` |
| New restore-rehearsal database | `justirl2_plenact_m1_restore` |
| HTTPS staging base | `https://plenact.com/staging/api/user-data/v1` |
| Public entry-point directory | `/home2/justirl2/public_html/plenact/staging/api/user-data/v1` |
| Private staging root | `/home2/justirl2/plenact-private/model1-staging` |
| Private configuration, assets, tools and backup area | Separate children of the private staging root; credentials and dumps never enter the public entry-point directory |

The contract reserves `https://plenact.com/api/user-data/v1`; staging uses an explicit environment-specific base with unchanged relative endpoint paths. Do not edit the pinned OpenAPI publication to masquerade staging as production.

Keep the existing Version 0 database, private runtime configuration, and website/community paths intact. Do not assume `justirl2_plenact_dev` or `justirl2_test_Plenact` is disposable. Provision separate staging runtime and migration identities; actual usernames and privileges remain to be prepared with the migration, and no new credentials or grants have been created.

The contract is pinned by `Server/model1/contract-pin.json` and checked with `python3 Server/model1/verify_contract.py`. This protects the implementation input version, not runtime behavior. Next implementation work is a MySQL 5.7-compatible schema and migration preflight, followed by the authenticated API and client integration. The published example SQL is illustrative and must not be imported as the staging implementation.

Remaining hosting verification: the intended staging namespace must be unused; web-runtime modules/limits and HTTPS must be tested at that namespace; private directory permissions must be checked; and a staging backup/restore rehearsal must succeed before Stage 2 acceptance.


## November 21: staging database created

The operator supplied cPanel's success confirmation for **`justirl2_plenact_m1_stage`**. The database list shows that exact name, approximately **4.06 KB**, and no assigned privileged users in its displayed row. Database size alone does not prove that the schema is empty; no table, routine, trigger, or event inventory has yet been returned for this new database.

`Server/model1/migrations/000_preflight.sql` is prepared as a read-only phpMyAdmin check. Select the exact staging database, run the file's SELECT statements, and confirm `inspected_database = justirl2_plenact_m1_stage` with all object counts zero. Record the charset/collation as well. Do not import the illustrative model SQL or Version 0 migration. Existing database credentials/grants must not be reused or broadened for staging by assumption.

No Model 1.0 schema, account/session service, API deployment, client synchronization, backup, or restore has been verified. The runtime identity and migration identity for staging have not been provisioned by this work.


### Corrected preflight scope

The first phpMyAdmin result reported `selected_database = information_schema`, 76 tables/views, zero routines/triggers/events, and `utf8 / utf8_general_ci`. Those results describe **information_schema**, not the staging database. They do not establish staging emptiness or its character set. The preflight has been corrected to use the literal `justirl2_plenact_m1_stage` for the schema lookup and every object count, with no dependency on `DATABASE()`. A single returned row identifies the exact schema being inspected; no returned row means existence/visibility remains unresolved.


### Staging emptiness confirmed

On November 21 the corrected explicit-schema query returned **`justirl2_plenact_m1_stage`, `utf8`, `utf8_unicode_ci`, 0 tables/views, 0 routines, 0 triggers, and 0 events**. This verifies the intended staging schema was empty at that observation. The earlier 76-table `information_schema` result is superseded for staging preflight purposes, not reinterpreted as staging evidence.

The first core migration is prepared locally under `Server/model1/migrations/001_core.sql`, with a generated phpMyAdmin import (`001_core_import.sql`) carrying the source SHA-256 in its migration ledger. It explicitly selects the staging database and changes its default to `utf8mb4_unicode_ci`. It creates eight InnoDB core tables only; no users, credentials, grants, accounts, synthetic workspaces, or API routes are provisioned by it. Live SQL execution/constraint checks, the remaining operational schema, and backup/restore verification are still pending. Local static review is not MySQL execution evidence.


### Initial core import failed: current-database context

The operator's phpMyAdmin screenshot shows a green “14 queries executed” banner **and** error 1044 on `CREATE TABLE m1_schema_migrations`: access denied to `information_schema`. Do not count the banner as successful migration evidence. No permission expansion is indicated; the SQL must not attempt DDL in information_schema.

The initial files depended on USE plus unqualified table names. Their exact bytes and hashes are retained under `Server/model1/migrations/archive/`. The replacement core/import fully qualifies every CREATE, REFERENCES, ledger INSERT and ledger read with `justirl2_plenact_m1_stage`. The updated source gets a new checksum; do not rewrite any previously accepted ledger entry to match it.

**Before retry:** re-run the explicit-schema object/charset preflight. If any objects exist, inspect their exact names/structure and any migration-ledger rows before proceeding. Do not rerun or drop partial objects blindly. The earlier ALTER DATABASE might have applied even if CREATE failed. No retry or successful import has yet been verified.


### Follow-up after failed import

The operator's explicit-schema query returned **zero table/view rows** for `justirl2_plenact_m1_stage`, and its default is now **utf8mb4 / utf8mb4_unicode_ci**. Thus the default-charset change applied, but no core tables or migration ledger were observed in the target. This is not a completed migration.

The corrected, fully qualified import is generated under the distinct name **`001_core_import_qualified.sql`** to prevent selecting a cached/downloaded copy of the context-dependent import. Local preparation checks pass. Retry only this newly generated artifact; verify the resulting eight tables and checksum ledger rather than relying solely on phpMyAdmin's green banner.


### Core migration successfully applied — November 21

The corrected import returned successful DDL results, one inserted migration row, and all **eight expected `m1_` tables**, each **InnoDB / utf8mb4_unicode_ci**. The supplied migration INSERT identifies source SHA-256 **`cb58318d79e2afe764400390012abf85bbd6bf34940e12da8556f75fed025fc8`**, matching the local immutable `001_core.sql`; the readback row shows that migration and reported UTC application time **2026-11-21 11:24:14.344813**. The full checksum equality is included in the next read-only ledger check within the storage probe.

The observed application is recorded in `Server/model1/migrations/applied-staging.json`. Freeze this source; future schema changes require a new migration, not edits to 001 or another import of it. No runtime account, authenticated service, snapshot/media/lifecycle storage, client sync or recovery rehearsal is established by the successful core DDL.

Next: `Server/model1/tests/core_storage_probe.sql` checks the ledger checksum, inserts fresh synthetic diagnostic identities and linked rows within a single InnoDB transaction, checks exact non-BMP UTF-8 JSON bytes and receipt hashing, then ROLLBACKs and reports remaining probe rows. It changes no schema and contains no COMMIT, DELETE, or real-user data. Its `storage_probe` JSON is deliberately an operator-only physical test, not a valid Model 1.0 wire payload or an API/graph-validation test. Success requires checksum equality 1, all three in-transaction checks 1, and all seven post-rollback counts 0. Live execution of this probe is pending.


### Staging storage and runtime verified — November 21

Operator-provided output confirms the physical storage probe returned checksum equality **1**, Unicode/link/hash checks **1 / 1 / 1**, and all seven synthetic-row counts **0** after rollback. This establishes those physical storage checks, not protocol conformance or account isolation.

The operator created the staging public entry-point directory `/home2/justirl2/public_html/plenact/staging/api/user-data/v1` with permissions **755**, and private root `/home2/justirl2/plenact-private/model1-staging` with `config`, `assets`, `tools`, and `backups` children, all **700**. A dedicated user, `justirl2_m1_stage_app`, was created and assigned to `justirl2_plenact_m1_stage`. The privilege screen showed only SELECT, INSERT, UPDATE, DELETE selected; the subsequent database list showed the assignment. Direct SHOW GRANTS verification for this new identity remains pending.

The operator's configuration-creation script successfully connected as that new user and read **1** migration ledger row. Configuration was saved at `/home2/justirl2/plenact-private/model1-staging/config/database.json`; a separate listing confirms **600**, owned by the hosting account. No password or configuration contents were supplied to this repository or chat. This proves CLI access, not yet access from the web worker.

An HTTPS request to a temporary random diagnostic under the staging entry-point directory returned PHP **8.2.36**, SAPI **litespeed**, and `pdo_mysql`, `openssl`, `mbstring`, `fileinfo`, `sodium`, `json` all **true**. Web limits: memory **512M**, execution **60 seconds**, upload **64M**, post **64M**. The supplied command registered EXIT cleanup for the diagnostic; a separate absence check was not supplied. No API service is deployed by this diagnostic.

Next: choose the initial identity/sign-in flow (not prescribed by Protocol 1.0), implement its private operational storage and session boundary, and test unauthorized access and account/workspace isolation before exposing record routes. Backup/restore rehearsal and client synchronization remain outstanding.


### Private authentication and initial API-engine checks

Operator output confirms migration 002 source checksum equality **1** and three InnoDB/utf8mb4 authentication tables. Private account creation succeeded; credentials were entered only at a hidden terminal prompt. Private storage/session, actual login/logout, sequential limits, concurrent limits and HTTPS auth diagnostics passed. HTTP authentication is disabled after those tests. No account password/session token was shared.

After operator-authorized SSH access, the agent ran private read and transaction storage diagnostics on fresh synthetic workspaces. Reads verified owner resolution and generic foreign/unknown 404. Transactions verified replay/hash conflicts, revision conflicts, graph-callback rejection rollback, deletion/no resurrection, and exact synthetic cleanup. Those tests establish storage behavior only; production request/whole-graph validators are not connected. Public data router deployment and complete API remain pending. No invited workspace content was modified.


### Snapshot storage applied and private retrieval tests passed

Operator import output and SSH exact-fingerprint readback confirm migration 003, its two snapshot tables, and InnoDB/utf8mb4 attributes. Private MySQL tests passed frozen multi-page snapshots across a later write, final-fence change retrieval, stable retries, empty deltas, cursor ownership/tamper rejection, lease expiry and missing-history resnapshot behavior. Synthetic response artifacts passed pinned schema and semantic validation. Diagnostic leases/records/workspace/account were removed; the invited workspace was unchanged. Public data HTTP acceptance and service activation remain pending.

### Core native data HTTPS routes verified

A separate synthetic account/session exercised owner/unknown/foreign reads, strict transactions and exact-byte retries, revision and graph conflicts, multi-page frozen snapshots, ordered/empty changes and revoked bearer rejection through the staging HTTPS router. The final 17 response artifacts passed pinned JSON schemas and semantic validation. Diagnostic data was removed, authentication/data flags restored to disabled, and private data configuration permissions confirmed 600. Full capabilities remain unavailable while assets/lifecycle are incomplete. The invited workspace is unchanged.


### Asset staging applied and privately tested

Operator import plus exact SSH fingerprint/table checks verified migration 004. Native MySQL prepared statements preserved complete null/non-UTF-8 synthetic chunks and passed resumability, replay/conflict, digest/length/index, owner, expiry and zero-byte checks. Described Asset metadata was created through strict typed/whole-graph validation. Diagnostic rows were removed; no existing workspace changed and no blob was published. Verified commit/download/purge/deletion and recovery remain incomplete.


### Verified assets tested through HTTPS

Synthetic private MySQL/file and HTTPS tests passed assembled SHA-256/length verification, atomic verified revision publication, commit deduplication, owner isolation, full/Range/If-Range retrieval, empty originals and unavailable-original errors. PHP's ETag was removed by hosting; an API-local response-header rule restored strong verified digests, confirmed by live tests. No global/parent configuration changed. All 11 captured asset JSON responses passed pinned schema/semantic validation, and the existing core HTTPS diagnostic passed again. All diagnostic rows/files were removed and routes disabled; the invited workspace is unchanged. Explicit purge/account deletion and recoverable backup/restore remain pending.
