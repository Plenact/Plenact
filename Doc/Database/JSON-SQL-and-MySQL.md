# Why JSON and SQL/MySQL work together

**Supported User Data Model versions:** 1.0; Version 0 historical reference only.
**Updated:** October 24, 2026.

**We use both.** They solve different problems.

| Term | Role in Plenact |
| --- | --- |
| JSON | Portable data representation sent over HTTPS and used in examples/exports. Swift, JavaScript and C# can share its fields and values. |
| JSON Schema | Machine-checkable structure, types, bounds and allowed fields; semantic graph/date/authorization checks are additional. |
| SQL | Language for defining/querying tables and performing transactional changes. |
| MySQL | Planned Bluehost server database storing account/workspace identities, record state, revisions, changes, receipts and operational metadata. |
| SQLite | Recommended Windows local database for durable offline records and outbox; not the Bluehost server. |

A Card may be transmitted as a JSON document while MySQL stores owner/workspace/UUID/revision in indexed columns and the complete canonical document in a JSON-capable column. MySQL supports [native JSON columns](https://dev.mysql.com/doc/refman/8.0/en/json.html). The exact hosting product/version, JSON behavior, constraints, SQL modes and transactional support still need a read-only hosting audit; do not assume MariaDB behaves identically.

SQL transactions must atomically update heads, immutable revisions, ordered changes and successful-write receipts. JSON syntax validation in a database does not implement Model 1.0 validation or owner authorization. Selected fields can gain indexed projections after profiling without changing the wire contract.

Exact-byte request retries are a separate case: store the request digest and durable identity/results; if retaining request bytes, keep them as binary bytes. Do not hash reserialized MySQL JSON and call it the original HTTP request. Database JSON storage may normalize representations.

Owned media originals are private files/blobs with exact SHA-256/length verification. Their metadata belongs in MySQL; large originals do not need to become base64 JSON columns. Devices access authorized endpoints, never raw server filesystem paths or direct database credentials.

The example `.sql` files are readable, disposable schema/seed illustrations, not files each device edits on Bluehost. MySQL manages its own database storage. JSON exports and SQL dumps can be generated for controlled backups; private database dumps/media must not live in public web folders.
