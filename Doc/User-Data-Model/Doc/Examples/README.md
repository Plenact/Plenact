# Version-specific Bluehost data examples

**Supported User Data Model versions:** 0 historical SQL; 1.0 synthetic contract/storage examples.
**Updated:** October 24, 2026.

These are **synthetic educational examples**, not exports of Justin's account or a dump of the deployed host. MySQL manages database files internally; the SQL files here illustrate schema/seed representation, while JSON shows portable record values/API/export representations. They must not be installed in a public web folder.

| Example | What it represents |
| --- | --- |
| [Version 0 SQL](0/historical-demo-schema.sql) | Exact historical migration 001: seven shared-demo tables. No credentials, password hashes, sessions or live rows. |
| [Version 1.0 complete workspace](1.0/complete-workspace.json) | Complete valid synthetic portable workspace with content, planning, settings, identity and asset metadata. It is an export format, not the physical database layout. |
| [Version 1.0 Card server frame](1.0/card-server-record.json) | A separately valid Card revision example with server provenance; its actor/IDs are independent of the full-workspace example. |
| [Version 1.0 SQL illustration](1.0/illustrative-record-storage.sql) | Four example tables and 30 canonical records extracted from the complete workspace, each with a revision and consecutive change sequence. This is an initial synthetic baseline, not a replayable client transaction. |

The SQL uses JSON columns inside relational tables, demonstrating why JSON and MySQL work together. Hex UTF-8 literals avoid SQL quoting-mode ambiguity; normal runtime code must use parameterized statements. All IDs/documents in the SQL derive from the full workspace. The example has no authentication, receipt store, upload/snapshot leases, tombstones or deletion jobs and therefore is **not** a complete production database or Model 1.0 service. Asset metadata does not mean original bytes are uploaded or verified.

The reference checker validates the JSON with the final schemas/semantic rules, extracts and compares SQL embedded documents/frames, and checks the historical schema copy. SQL has not been executed against Bluehost or certified for a specific database engine/version. A future staged database integration must verify actual DDL, constraints, isolation, permissions and recovery.

See [JSON versus SQL/MySQL](../../../Database/JSON-SQL-and-MySQL.md), [physical implementation plan](../../../Database/Model-1.0-MySQL-Plan.md), [normative storage](../../Logical-Storage.md) and [current app/data plan](../../../Application-Data-Plan.md).
