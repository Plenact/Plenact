This directory contains ordered schema migrations for the new Plenact shared-demo database

## Current Migration

- [`001_plenact_demo_core.sql`](001_plenact_demo_core.sql): applied schema for demo users/sessions, the shared Board head, immutable Board JSON revisions, migration history, and import batches

**Status:** Migration `001` was applied on 2026-10-03 to the dedicated `justirl2_plenact` database after a successful disposable-database test. The import reported 9 queries executed; verification showed all 7 expected base tables using InnoDB. Its `schema_migrations` row is recorded with the filename, SHA-256 checksum, operator, and UTC timestamp. The Jim editor account is provisioned and the synthetic Board is initialized as revision 1; readback confirms a completed `demo_seed` batch with 49 cards, 7 lists, and 13 labels

**Compatibility test:** Migration `001` first imported successfully into the disposable `justirl2_test_Plenact` database on the Bluehost server reporting version `5.7.44-48`; all 7 expected tables were verified as InnoDB

The DDL is confirmed against the reported server version. The deployed API's dummy-token smoke test confirms database connectivity and session SELECT access, but not authenticated operations or write privileges

Migration `001` stores each complete Plenact Board state as an immutable snapshot revision. Jim is the sole canonical content editor. Other active registered demo users may browse and append revisions changing only their own assignment. The API enforces those permissions and uses expected-revision checks to reject stale writes. Registration is invite/admin-created

## Migration Rules

- Never run these migrations against the Database Demo database
- Record migration version, filename, SHA-256 checksum, operator, and UTC application time in `schema_migrations`
- Back up the target database before applying a migration and verify recovery procedures
- Do not rerun a partially applied migration without inspecting actual database state
- Keep SQL administrator credentials separate from the API runtime account
- For the closed synthetic demo, the cPanel runtime user may receive database-scoped `SELECT`, `INSERT`, `UPDATE`, and `DELETE` on the dedicated Plenact database. Do not grant schema/admin privileges such as `CREATE`, `ALTER`, `DROP`, `INDEX`, `REFERENCES`, `TRIGGER`, or `GRANT OPTION`; keep those with a separate operator account. Database-scoped DML does allow modifying or deleting any row, including immutable revisions, so use only synthetic data and keep the API's role/revision checks enabled. Before public launch or storing real user data, replace this with reviewed table/column-level grants and a production security review
- Use synthetic seed content only; do not import a local personal Board or attachment files by default