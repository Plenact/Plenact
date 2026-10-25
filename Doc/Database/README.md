# Plenact database and cloud storage

**Supported User Data Model versions:** 1.0; Version 0 historical reference only.
**Updated:** October 24, 2026.

Start with the final [Model 1.0 specification](../User-Data-Model/Specification.md) and [current application/data plan](../Application-Data-Plan.md). The published definition supports one private owner across iOS, web and Windows, including indefinite offline work. The older shared Board demo is **Version 0**, not the current private-workspace design.

| Layer | Representation | Current state |
| --- | --- | --- |
| Shared application contract | Versioned JSON documents, JSON Schemas and HTTPS requests | Final Model 1.0 definition published. |
| Server persistence | MySQL-compatible relational tables, indexes and atomic SQL transactions | Logical requirements defined; production Model 1.0 DDL/API not deployed. |
| Original media | Private owned files/blobs plus verified metadata in the database | Transfer/retention contract defined; integration pending. |
| iOS | Existing preference/file formats; native backup preparation | Local source export implemented on the current branch; portable conversion pending. |
| Windows | C# with recommended SQLite local persistence | Upcoming implementation. |
| Web | Shared HTTPS interface with durable browser storage | Upcoming integration. |

## Current documents

- [Current data contract overview](Plenact-Data-Contract.md).
- [JSON, SQL and MySQL](JSON-SQL-and-MySQL.md): what each layer does.
- [MySQL implementation plan](Model-1.0-MySQL-Plan.md): physical design and acceptance boundaries.
- [Versioned database examples](../User-Data-Model/Doc/Examples/README.md): synthetic SQL and portable JSON, with explanations.
- [Logical storage obligations](../User-Data-Model/Logical-Storage.md): normative transaction, retention and identity invariants.

## Historical Version 0

[Archived contract](Version-0/Plenact-Data-Contract.md), [synthetic import/deployment record](Initial-Demo-Import-Plan.md), [migration 001](../../Server/SQL/001_plenact_demo_core.sql) and [recorded server status](../../Server/SQL/README.md) describe the initial shared demo. Repository records report deployment on October 3, 2026; this update did not inspect the live host. Keep that database/routes separate from the private Model 1.0 namespace. Do not replay migration 001 as a Model 1.0 upgrade.

No database was created, cleared or changed, and no endpoint was deployed by this documentation work. Runtime credentials remain outside source and `public_html`; applications call authenticated HTTPS APIs rather than connecting directly to MySQL.
