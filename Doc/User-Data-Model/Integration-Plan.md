# Model 1.0 implementation and acceptance plan

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

The definition is complete: 48 schemas, 24 canonical record types, the source mapping, HTTP contract, asset protocol, migration rules and shared conformance suite are frozen together. See [publication](Publication.md) and [evidence](Conformance.md).

## Next implementation milestone

The **app-owned saved-source snapshot/export boundary** is implemented on the current working branch; see [native iOS status](iOS-Migration-Export.md). The durable source-qualified identity journal and first label/display converters are also implemented; see [partial conversion](iOS-Migration-Identity.md). Continue the **lossless local migration adapters** next. Preserve original preferences/files, exercise native legacy decoders and create durable owner-qualified identity maps. Convert a synthetic full workspace, compare every mapped field/reference and asset hash, prove rollback, then offer an explicitly opted-in personal backup conversion. The existing capture tool does not perform that conversion.

Next audit Bluehost read-only with authorized operator access: deployed code/runtime/database, grants, applied migrations and tested backup/restore. Keep Version 0 isolated. Build Model 1.0 in a separate staging route/database/storage namespace, implementing the [HTTP contract](Synchronization.md), [logical storage](Logical-Storage.md), owner authorization, atomic receipts/outbox, retained tombstones, frozen snapshots and verified assets.

Implement iOS, web and Windows adapters against the same frozen contract. C#/.NET is the accepted Windows direction; WinUI 3 and SQLite remain implementation recommendations. The Windows repository name, supported OS/app releases and hosting capacity are implementation choices, not unresolved wire fields. No Windows repository was created here.

## Runtime acceptance

| Scenario | Required evidence |
| --- | --- |
| Legacy conversion and rollback | All writing, dates, memberships, archives, settings, history and original files survive; ambiguous values are reported. |
| iOS ↔ web ↔ Windows | Stable identity and equivalent records after creates, edits, moves and deletes. |
| Indefinite offline/restart | Durable local content/outbox; expired sessions/cursors trigger safe reconciliation. |
| Concurrent edits | Both versions retained; no silent overwrite or resurrection. |
| Lost responses | Exact request retry returns the original result once. |
| Pull interruption / server restore | Atomic cursor application; fresh epoch forces reconciliation. |
| Unsupported schemas / rich text / zones | Preserve bytes and block unsafe writes. |
| Asset interruption/corruption | Resume safely; original bytes are verified before publication. |
| Foreign IDs / expired session / CSRF | Owner isolation and authentication enforced by the running service. |
| Account deletion / asset purge / backup restore | Explicit consent, verified retention deadlines and recovery behavior. |
| Notification scheduling | Shared intent remains separate from per-device delivery and permissions. |

Pilot synthetic work first. Record app/model/protocol support and staging evidence before an explicitly opted-in personal workspace sync. Publishing this definition does not authorize clearing the demo, deploying a production API or uploading personal data.

## Current implementation follow-up

See [native iOS backup/export](iOS-Migration-Export.md), [versioned SQL/JSON examples](Doc/Examples/README.md) and the [current application/data plan](../Application-Data-Plan.md). The frozen GitHub Model 1.0 release remains unchanged; this working-branch documentation records subsequent implementation progress.

## Local recovery acceptance follow-up

A [Simulator-only reviewed source-restore test](iOS-Local-Restore-Test.md) is now available on the working branch. The owner chooses the backup and confirms installation into the separate test Simulator; previous destination data is retained for undo. This exercises local recovery, not full Model 1.0 conversion or cloud account import.
