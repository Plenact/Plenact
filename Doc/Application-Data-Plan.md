# Current application and data plan

**Supported User Data Model versions:** 1.0; Version 0 historical reference only.
**Updated:** October 24, 2026.

This page is the current cross-document status reference. Dated design/handoff documents retain their original feature history; their older data/cloud assumptions do not supersede this plan or the final [Model 1.0 specification](User-Data-Model/Specification.md).

## Secured decisions

- First owner: Justin Reina, identified by a verified stable account UUID, not a display name.
- Clients: native iOS, Plenact.com web and an upcoming C# Windows application. .NET/WinUI 3 and SQLite are the recommended desktop implementation direction; no Windows repository/application is created here.
- Indefinite offline use: no application-imposed expiration of local content or pending edits. Returning devices reauthenticate/resnapshot and reconcile without discarding work.
- Settings follow the user by default. Credentials, permissions, operational state, viewport, unfinished drafts and recovery machinery remain device-local.
- Conflicts preserve local/base/remote versions. Exact-byte retry receipts and deletion evidence remain for the account lifetime. Owned original media uses verified resumable transfer.

## Current evidence and boundaries

| Area | Current state |
| --- | --- |
| Model 1.0 definition | [Published on GitHub](https://github.com/Plenact/Plenact/releases/tag/user-data-model-v1.0): 24 record types, 48 schemas and the HTTP/asset/migration contract. |
| Specification conformance | 58 regression tests and 167 fixture expectations at publication; Swift/C#/JavaScript each preserved 67 valid examples. See [frozen evidence](User-Data-Model/Conformance.md). |
| Native iOS backup preparation | Implemented in the current working branch, seven focused simulator tests passed. Settings can prepare/save original stores/media with native-decoder preflight, plus a partial canonical label/display preview with durable identities. See [iOS milestone](User-Data-Model/iOS-Migration-Export.md). |
| Complete native portable conversion | Not implemented. A source backup is not a canonical workspace-export. |
| Existing cloud demo | Version 0; repository evidence reports October 3 deployment with synthetic data. No fresh live verification here. |
| Model 1.0 production API | Not deployed or connected to the applications by this work. |
| Web/Windows synchronization | Contract targets, not implemented client integrations. |
| Personal data | Tests use isolated synthetic data; no personal workspace was migrated or uploaded. |

## Delivery sequence

1. Finish local migration: durable owner-qualified ID journal, native field conversion, timezone decisions, projection reconciliation, valid complete Model 1.0 export and tested local recovery.
2. Audit Bluehost read-only and select isolated staging resources; retain Version 0 independently.
3. Implement the Model 1.0 private API, transactional persistence, receipts/tombstones, snapshots and verified assets in staging.
4. Integrate durable iOS outbox/pull/conflicts, then web and Windows against the same acceptance suite.
5. Pilot synthetic work before explicitly opted-in personal migration/synchronization. Publish deployment evidence separately from definition readiness.

The [database overview](Database/README.md), [implementation plan](User-Data-Model/Integration-Plan.md) and [versioned examples](User-Data-Model/Doc/Examples/README.md) develop these boundaries.

## Simulator recovery test

The working branch now provides an explicit [reviewed source-backup restore and undo](User-Data-Model/iOS-Local-Restore-Test.md) in Simulator builds only. It uses the preserved source format, keeps a verified pre-import destination snapshot and does not claim Model 1.0/account synchronization. Owner-driven acceptance is in progress.

## Expanded native content preview

Board, List and Card converters now emit a validated partial content graph, including archived and nested content, with original timezone confirmation and explicit unresolved dependencies. See [current evidence and limits](User-Data-Model/iOS-Content-Migration.md). Remaining workspace adapters and verified account binding still prevent a complete Model 1.0 export claim.


### Calendar/template metadata implementation checkpoint

Supported User Data Model versions: 1.0. iOS preview conversion now includes retained calendar Week/index metadata and saved template/library metadata. Explicit mappings, template order/defaults, example Focus markers and cross-Week checklist ownership are preserved. This extends the partial native preview; full portable workspace import/export and authenticated synchronization remain pending. See [current mapping and acceptance steps](User-Data-Model/iOS-Calendar-Template-Migration.md).


### Original-file verification checkpoint

Supported User Data Model versions: 1.0. Local migration previews now verify exact original media, preserve unreferenced files, prepare attachment/drawing links and expose missing/conflicting evidence. Assets remain local drafts until verified account binding; no cloud transfers or full portable import are enabled. See [current Asset boundary and manual acceptance](User-Data-Model/iOS-Asset-Migration.md).


### Saved planning preferences, profile and Today shortcuts

Supported User Data Model versions: 1.0. The native preview now prepares account-unbound profile/preference drafts, distinguishes saved settings from compatibility/application defaults, and converts saved Today shortcut order and parent membership. Avatar originals link through verified local Asset evidence. Other appearance/Studio and planning/review domains plus verified account binding and complete portable import/export remain pending. See [current settings slice](User-Data-Model/iOS-Settings-Migration.md).


### Studio appearance checkpoint and remaining contract representation

Supported User Data Model versions: 1.0. Saved artwork payloads and Studio/global appearance evidence are now prepared with exact file links. Global Week-theme semantics and saved-artwork ordering still need a separately reviewed versioned canonical representation; local evidence retains them with visible mapping-review notices. Released schemas are unchanged. See [Studio boundaries and verification](User-Data-Model/iOS-Studio-Migration.md). Daily plans/reviews, ownership binding and complete workspace import/export remain pending.


### Planning and review-history checkpoint

Supported User Data Model versions: 1.0. Native adapters now convert saved daily/check-in, weekly/periodic review and reminder-intent data. Original snapshots, nullable history and exact owner/creation provenance are preserved without replaying actions or notifications. See [current planning boundary](User-Data-Model/iOS-Planning-Review-Migration.md). Global appearance representation gaps, ownership binding and whole-workspace export/import/recovery acceptance remain pending.


### Closing appearance representation gaps with working Model 1.1

Supported User Data Model versions: 1.0 published base and working 1.1 appearance composition. Global Week defaults and authored artwork order now have separate new records, preserving the immutable base and existing identities. The new definition remains local/unpublished; explicit 1.1 capabilities, verified ownership and full portable import/recovery remain integration work. See [versioned mapping and evidence](User-Data-Model/Version-1.1.md).


## Editable iOS migration checkpoint

Supported User Data Model versions: 1.0 base and working 1.1. The Simulator now has confirmed portable-to-editable activation with full pre-import backup, verified reload and undo. Local format-two backups retain current edits and canonical baseline/identity evidence. Fresh portable export after editing is intentionally disabled until canonical reconciliation is complete. Real account ownership, production activation and cloud synchronization remain separate pending work. See [editable import status](User-Data-Model/Editable-Import.md).
