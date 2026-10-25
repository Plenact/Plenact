# Model 1.0 implementation and acceptance plan

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

The definition is complete: 48 schemas, 24 canonical record types, the source mapping, HTTP contract, asset protocol, migration rules and shared conformance suite are frozen together. See [publication](Publication.md) and [evidence](Conformance.md).

## Next implementation milestone

The **app-owned saved-source snapshot/export boundary** is implemented on the current working branch; see [native iOS status](iOS-Migration-Export.md). The durable source-qualified identity journal and first label/display converters are also implemented; see [partial conversion](iOS-Migration-Identity.md). Board/List/Card content adapters now exist as an independently validated partial slice; continue calendar/planning/review metadata, profile/preferences, selections and owned-Asset adapters next. Preserve original preferences/files, exercise native legacy decoders and create durable owner-qualified identity maps. Convert a synthetic full workspace, compare every mapped field/reference and asset hash, prove rollback, then offer an explicitly opted-in personal backup conversion. The existing capture tool does not perform that conversion.

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

## Expanded content conversion

The working branch now includes [Board/List/Card content conversion](iOS-Content-Migration.md), with explicit timezone selection, owner-qualified template copies, archive/history/media-reference preservation and independent graph checks. Full workspace conversion and cloud integration remain pending. The earlier first-slice status above is historical; the new guide is the current content-adapter evidence.


### Label and personal-selection preview update

Supported User Data Model versions: 1.0. The content preview now records an explicit current-build default label catalog only when the saved catalog is absent. It also prepares owner-qualified bookmarks/importance in local `SelectionPreview.json`, with unresolved targets and conflicts reported. These drafts remain pending verified account binding; they are not yet canonical selections. See [content and selection evidence](iOS-Content-Migration.md). Full workspace export/import and synchronization remain pending.


### Calendar and template metadata update

Supported User Data Model versions: 1.0. Native previews now convert saved Week/index and template/library metadata with explicit original owner mappings, template order/defaults and cross-Week checklist ownership. See [calendar/template conversion evidence and manual test](iOS-Calendar-Template-Migration.md). Other planning/review data, canonical account-bound selections and complete workspace export/import remain pending.


### Verified original-file and Asset preparation update

Supported User Data Model versions: 1.0. Native preview now emits account-unbound `AssetPreview.json`, linking attachment/background references and all preserved originals to stable media identities with verified size/checksum, explicit missing-file review and drawing derivation. Canonical account-owned Assets and cloud transfers remain pending. See [file verification and manual test](iOS-Asset-Migration.md). The current focused suites pass 51 native tests and 77 model/tooling checks; earlier counts describe prior checkpoints.


### Profile/preferences and Today shortcut checkpoint

Supported User Data Model versions: 1.0. Native previews now prepare local profile/effective preference drafts with explicit source/default provenance and avatar links, and convert saved Today shortcuts using exact owner-qualified membership/order. Account-required profile/preferences remain unbound; Studio and other appearance/planning/review adapters remain pending. See [current settings mapping and acceptance](iOS-Settings-Migration.md). Current focused checks pass 56 native tests and 80 model/tooling tests.


### Studio and remaining appearance preparation

Supported User Data Model versions: 1.0. Previews now convert saved artwork payloads and prepare Studio/global Week appearance with exact surface/file references. Global Week defaults and multi-artwork ordering lack complete canonical destinations in the immutable released contract; they are retained in local evidence with explicit mapping-review notices, not silently merged or dropped. See [Studio mapping, representation gaps and acceptance](iOS-Studio-Migration.md). Current focused checks pass 60 native tests and 83 model/tooling tests. These representation gaps, account binding, daily plans/reviews and complete workspace recovery remain pending.


### Daily plans, check-ins and review history checkpoint

Supported User Data Model versions: 1.0. Native previews now convert daily plans, weekly/periodic reviews and reminder intent while retaining historical writing/progress, exact source-creation references and nullable history. Missing/deleted targets stay explicit; review decisions and notifications are never executed. See [planning mapping and acceptance](iOS-Planning-Review-Migration.md). Current focused coverage passes 65 native tests and 86 model/tooling checks. Appearance representation gaps, verified ownership and complete portable recovery remain pending.


## Working Model 1.1 appearance composition

Supported User Data Model versions: 1.0 base and working 1.1. Global Week defaults and artwork order now have separately versioned records over an unchanged 1.0 base. Require explicit 1.1 support, preserve both record namespaces and reject lossy downgrade. New schemas/preview support do not upgrade protocol 1.0, deploy a service or publish a release. See [definition, journal compatibility and acceptance](Version-1.1.md). Current focused checks pass 68 native tests and 93 model/tooling tests.


## Canonical export assembly checkpoint

Supported User Data Model versions: 1.0 base and 1.1 working composition. An offline [canonical record assembler](Export-Assembly.md) now reconstructs a complete synthetic export with exact payload preservation and full schema/reference checks. All 98 Python tooling tests pass. Native draft binding, original-file bundle assembly, portable import/recovery and authenticated personal ownership remain pending. No application data was changed.


## Synthetic draft binding checkpoint

Supported User Data Model versions: 1.0 base and working 1.1 appearance composition. The [offline synthetic binding adapter](Export-Assembly.md) now assembles validated settings/profile, Studio, selection and verified Asset drafts into canonical exports. It retains original draft evidence, rejects review issues and makes no verified personal ownership claim. All 103 Python tests pass, plus acceptance checks on native-generated media/settings/Studio slices with 9/1/2 original files and corruption rejection. Complete source coverage, packaged original bytes, native UI integration and portable import/recovery remain pending. No personal backup was changed or uploaded.


## Synthetic original-file package checkpoint

Supported User Data Model versions: 1.0 base and working 1.1 composition. The [synthetic export package](Export-Assembly.md) now retains canonical records, draft evidence and exact original bytes in one verified archive. Creation/reopen tests pass on native-generated synthetic slices, with corruption rejection and overwrite protection. All 110 Python tooling tests pass. Combined native-source completeness, application integration and portable import/recovery remain pending; no user workspace or cloud data was modified.


## Native Simulator export preparation checkpoint

Supported User Data Model versions: 1.0 base and working 1.1 composition. The [Simulator package-preparation workflow](Export-Assembly.md) is now connected to Local backup. A combined synthetic native package passes independent complete schema/reference and original-file validation; 70 focused native tests pass. Personal manual package review, portable import/recovery and verified account binding remain pending. The new controls prepare and save a folder; they install no data and enable no synchronization.


## Portable read-only review checkpoint

Supported User Data Model versions: 1.0 base and working 1.1. The Simulator now offers [read-only portable package review](Export-Assembly.md), verifying package inventory, original bytes and core record relationships without reading the native backup for restoration. No portable installation or recovery action is available yet. Full contract validation remains a separate tooling check; owner-operated review of the v11 folder is next.


## Isolated portable installation checkpoint

Supported User Data Model versions: 1.0 base and working 1.1. The Simulator can now explicitly install a reviewed portable package into an isolated test store, reopen it for read-only inspection and undo to the prior test state. The main editable workspace is not replaced. [Installation scope and manual acceptance](Export-Assembly.md) explain the boundary. All 71 focused native tests pass, including atomic activation failure and corrupted-undo rejection. Main application import adapters and personal account binding remain pending.


## Editable content adapter checkpoint

Supported User Data Model versions: 1.0 content and working 1.1 package input. The [editable import bridge](Editable-Import.md) now reconstructs actual Collection/List/Card editor models with explicit UUID/numeric aliases, nested content/history/file references and date context. All 73 focused native tests pass. This is not yet connected to active workspace installation: calendar/settings/planning/selection coordination, canonical provenance retention and media placement remain pending. No additional manual export test is needed at this stage.


## Editable calendar/settings/appearance checkpoint

Supported User Data Model versions: 1.0 base and working 1.1 appearance metadata. [Editable reconstruction](Editable-Import.md) now includes calendar/index, ordered template libraries, effective preferences, profile, labels, shortcuts, bookmarks/importance and Studio/artwork/global Week defaults. The focused suite passes 76 synthetic native tests. Planning/review reconstruction, verified media placement and complete active-workspace coordination remain pending. No application store is changed by these pure adapters.


## Planning and media candidate checkpoint

Supported User Data Model versions: 1.0 base and working 1.1 appearance references. The [editable import components](Editable-Import.md) now reconstruct planning/review history and prepare verified collision-free original-file placement in a fresh staging directory. All 78 focused native tests pass. These components do not activate a main workspace or execute reviews/reminders. Complete candidate coordination, canonical provenance retention and protected active-workspace switching remain pending.


## Editable Simulator activation checkpoint

Supported User Data Model versions: 1.0 base and working 1.1; native source-backup formats 1/2. The [coordinated editable importer](Editable-Import.md) now reconstructs and privately stages the complete supported candidate, then uses root teardown, verified reload, full backup and undo to activate it in the Simulator’s normal views. Imported edits are retained in recovery history on undo. All 79 focused native tests and 111 Python tooling tests pass. Fresh portable export after native editing remains disabled; local backups preserve edits and canonical baseline/aliases in native format 2. Canonical reconciliation, real ownership binding and complete production acceptance remain pending.


### Latest edited export checkpoint

Supported versions: Model 1.0 base and working 1.1, synthetic-owner Simulator test packages. A first bounded export now reconciles Card text, scheduling, pending local Card deletion, completion/lock/display flags and history back to retained canonical IDs, verifies an inverse native projection, and includes the exact edited native backup. Unsupported edits stop preparation. See [Editable-Import.md](Editable-Import.md#edited-export-checkpoint--october-25-2026) for limits, automated evidence and the single owner test. This is not full Step 1 completion or cloud activation.


### Latest structural export checkpoint

Supported versions: Model 1.0 retained records and working 1.1 composition. Board-view creation now reserves durable native aliases/UUIDs; export supports new Lists/Cards, movement within an existing Board and List/Card order, subject to complete inverse verification. Existing identities and original files remain retained. New collections/Weeks, cross-Board transfers, List deletion, broader nested/media/settings edits, verified ownership and final release acceptance remain outstanding. See [Editable-Import.md](Editable-Import.md#structural-editing-checkpoint--october-25-2026) for exact scope and automated evidence.


### Latest rich Card checkpoint

Supported versions: unchanged Model 1.0 records in working 1.1, native backup format 2. Newly created rich Cards can now export verified new originals, attachment/cover metadata, comments, checklists/progress, bookmarks/importance, completion and history. Original bytes and identities are retained; import filename translation is explicit. The exact scope, 52 native/112 tooling test evidence, and remaining unsupported operations are documented in [Editable-Import.md](Editable-Import.md#rich-newly-created-card-export--october-25-2026). Production ownership, broader existing-record edits and final migration acceptance remain unfinished.


### Existing imported Card edits checkpoint

Supported models: 1.0 records and working 1.1 package composition. Edited export now reconciles existing Card comments, checklists/progress, members, reactions, appearance and attachment metadata/covers while retaining identities and untouched canonical fields. Independent original-file checks, clearing and fresh import/export are covered by 52 affected native tests and 112 Python tests. See [Editable import](Editable-Import.md) for scope and remaining Step 1 work. This does not enable cloud synchronization.
