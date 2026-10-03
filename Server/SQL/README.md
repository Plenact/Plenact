This directory contains ordered schema migrations for the new Plenact shared-demo database

## Current Migration

- [`001_plenact_demo_core.sql`](001_plenact_demo_core.sql): draft schema for demo users/sessions, the shared Board head, immutable Board JSON revisions, migration history, and import batches

**Do not apply yet.** The SQL has received a static structural check only. It has not been executed against the Bluehost Percona/MySQL version. Review and test it on a disposable database before applying it once to the new Plenact database

Migration `001` stores each complete Plenact Board state as an immutable snapshot revision. Jim is the sole canonical content editor. Other active registered demo users may browse and append revisions changing only their own assignment. The API enforces those permissions and uses expected-revision checks to reject stale writes. Registration is invite/admin-created

## Migration Rules

- Never run these migrations against the Database Demo database
- Record migration version, filename, SHA-256 checksum, operator, and UTC application time in `schema_migrations`
- Back up the target database before applying a migration and verify recovery procedures
- Do not rerun a partially applied migration without inspecting actual database state
- Keep SQL administrator credentials separate from the API runtime account
- Give the runtime API account only the required access: SELECT/INSERT on users, sessions, login limits, import batches, Board heads, and revisions; UPDATE only `revoked_at_utc` on sessions, the failure/lockout fields on login limits, `current_revision`/`updated_at_utc`/`updated_by_user_id` on Board heads, and completion fields on import batches; DELETE only login-limit rows. Never grant UPDATE/DELETE on immutable Board revisions or UPDATE/DELETE on user identities through the API account
- Use synthetic seed content only; do not import a local personal Board or attachment files by default