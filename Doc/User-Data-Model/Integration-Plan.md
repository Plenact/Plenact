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


### Existing List metadata export checkpoint

Supported models: unchanged Model 1.0 records in working 1.1 packages. Existing List titles, subtitles, archive state, new-item defaults and appearance now reconcile while preserving identity and unchanged fields. Fresh re-import/re-export and clearing authored values pass the 52 affected native tests; the existing 112 Python tests pass, and synthetic List package evidence passes independent schemas, references, manifest and original-file checks. See [Editable import](Editable-Import.md#existing-list-metadata-reconciliation--october-25-2026). Owner acceptance is next; broader workspace reconciliation and verified account binding remain pending.


### Saved preference reconciliation checkpoint — October 26, 2026

The edited exporter now updates existing saved app preferences through the explicit 1.0 preference field map, retaining record and owner identity inside working 1.1 packages. Focus row count/content-density changes and fresh native installation/re-export are covered. Profile-detail edits and Studio/artwork reconciliation remain subsequent slices. See [scope and owner test](Editable-Import.md#saved-preference-edits--october-26-2026).


### Automatic Week rollover checkpoint — October 26, 2026

Newly retained calendar Weeks now export with owner-qualified identities and frozen-only editor alias normalization; older Weeks and edited preferences remain preserved. Repeated export, source immutability and fresh re-import/re-export pass in the 52 affected native tests. The synthetic package passes independent schema/reference/original validation. See [rollover scope and limits](Editable-Import.md#automatic-week-rollover-export--october-26-2026). Production binding and broader planning/personalization reconciliation remain pending.


### Profile and Studio reconciliation checkpoint — October 26, 2026

Edited export now preserves profile details/avatars, Studio defaults/wallpapers, global Week appearance and saved-artwork content/order using unchanged 1.0 records in working 1.1 composition. New verified originals, clearing values, fresh import/re-export and rollover compatibility pass the 52 affected native checks, 112 Python checks and independent package validation. See [scope, identity rules and owner test](Editable-Import.md#profile-and-studio-edited-export--october-26-2026). Broader planning/calendar reconciliation and verified account binding remain pending.


### Owner-accepted preferences and Studio variety — October 26, 2026

The owner successfully re-imported independently verified v7 and confirmed Google Maps plus disabled Studio new-item color variety. Comparison with v6 found exactly those two canonical changes, preserved all five originals and verified native backup hashes with no review codes. v7 is the current accepted checkpoint; retain v6. See [acceptance scope](Editable-Import.md#owner-acceptance-preferences-and-studio-variety--october-26-2026). Profile detail/avatar and other personalization manual acceptance remain separate; broader Step 1 reconciliation and verified account binding remain pending. Cloud synchronization is disabled.


### Owner-accepted local profile creation — October 26, 2026

Independently verified v8 adds exactly one local profile relative to v7 and preserves all five originals, prior preferences and Studio values. The owner confirmed Undo, editable re-import and restoration of display name, email and planning context. v8 is the latest accepted checkpoint. See [profile acceptance scope](Editable-Import.md#owner-acceptance-profile-creation--october-26-2026). Existing-profile edits and new personalization media retain synthetic coverage; broader reconciliation, real account/workspace binding and final recovery acceptance remain pending. Step 1 continues; cloud synchronization remains off.


### Post-v8 edited-export inventory — October 26, 2026

The [code/evidence inventory](Edited-Export-Inventory.md) separates migration/import from subsequent edits and records manual versus synthetic evidence. Planning history, review rhythm and template metadata already import but lack dedicated edit reconciliation. Review-rhythm preferences are the recommended next bounded adapter, followed by daily-plan/review writing. No owner test is required for this documentation review. v8 remains the current accepted workspace; Step 1 remains in progress and cloud synchronization stays disabled.


### Review-rhythm export checkpoint — October 26, 2026

Review-rhythm creation and edits now reconcile saved invitation/time/weekday/notification intent while retaining singleton identity, preserving other planning history and rejecting malformed/unknown values. No scheduler runs during export. The 59 affected native tests, 112 tooling tests and independent new/retained-rhythm package checks pass. See [scope and pending owner test](Editable-Import.md#review-rhythm-edited-export--october-26-2026). v8 remains the accepted personal checkpoint. Daily-plan and review-history edits remain next; Step 1 continues and cloud synchronization remains disabled.


### Daily-plan writing/check-in export checkpoint — October 26, 2026

Daily writing, priorities, vision progress and check-in snapshots now reconcile on edited export, including newly saved dates. Explicit owner/alias/creation provenance prevents rebinding references; existing identity and unchanged canonical fields are retained. Unknown references, plan removal/date-zone identity changes and evening-review edits fail closed. All 60 affected native and 112 tooling tests pass, along with independent daily-package validation. See [scope and pending owner test](Editable-Import.md#daily-plan-writing-and-check-in-edited-export--october-26-2026). v9 was independently verified and re-imported; the final rhythm-toggle confirmation remains unrecorded. v8 is the last fully documented owner acceptance. Evening/weekly/periodic review edits and template metadata remain follow-up work; cloud synchronization is off.


### Daily-plan precision fix — October 26, 2026

A real owner save exposed submillisecond timestamp comparison missing from the original daily-plan fixture. A synthetic submillisecond save reproduced the rejection and now passes after daily-store comparison normalization at canonical millisecond precision. Exact native backup bytes remain preserved; distinct milliseconds and content/reference mismatches remain checked. All 61 affected native and 112 tooling tests plus independent updated package validation pass. See [cause and retry scope](Editable-Import.md#daily-plan-timestamp-precision-correction--october-26-2026). Owner portable v10 retry is pending; no repeat intention edit or Undo is needed.


### Owner-accepted daily-plan writing — October 26, 2026

The owner successfully re-imported independently verified portable v10 and confirmed restoration of the saved intention. v10 adds only the expected dated plan relative to v9, retains prior canonical data and all five original files, and passes native backup hashes. It is now the latest owner-accepted checkpoint. See [acceptance scope](Editable-Import.md#owner-acceptance-daily-plan-writing--october-26-2026). Check-in/priority/clearing paths retain synthetic coverage. Evening/weekly/periodic review edits, template/calendar/structural gaps, verified account binding and final reconciliation/recovery acceptance remain pending. Step 1 is not complete; cloud synchronization remains off.


### Evening-review export checkpoint — October 26, 2026

Evening-review creation, reflection writing, progress/completion, achievements and decision history now reconcile as saved data without executing actions. All 62 affected native and 112 tooling tests plus independent evening-package checks pass. See [scope and pending owner test](Editable-Import.md#evening-review-writing-and-history-edited-export--october-26-2026). v10 remains the accepted checkpoint. Unsupported cross-Board outcomes, weekly/periodic edits and structural gaps remain pending; Step 1 continues and cloud synchronization is off.


### Owner-accepted evening-review writing — October 26, 2026

The owner re-imported independently verified v11 and confirmed all three evening reflection fields and completion time. v11 is the latest owner-accepted checkpoint. See [acceptance scope](Editable-Import.md#owner-acceptance-evening-review-writing--october-26-2026). Next bounded work is weekly-review writing/progress/history reconciliation, followed by periodic reviews and template metadata. Unsupported action outcomes, structural/calendar gaps, authenticated binding and final reconciliation/recovery acceptance remain pending. Step 1 remains in progress and cloud synchronization remains off.


### Weekly-review export checkpoint — October 26, 2026

Weekly-review writing, priorities, decision history, progress/completion and new reviews now reconcile using the shared daily/weekly adapter. Explicit identity/context/reference guards remain; no review action executes during export. All 65 affected native tests, 112 tooling tests and independent weekly-package checks pass. See [scope and pending owner test](Editable-Import.md#weekly-review-writing-and-history-edited-export--october-26-2026). v11 remains the accepted checkpoint. Periodic reviews and template/calendar/structural gaps remain pending; Step 1 continues and cloud synchronization remains disabled.


### Owner-accepted weekly-review writing — October 26, 2026

The owner re-imported independently verified v12 and confirmed all five weekly reflection fields, with prior daily/evening writing retained. v12 is the latest owner-accepted checkpoint. See [scope and evidence](Editable-Import.md#owner-acceptance-weekly-review-writing--october-26-2026). Next bounded work is periodic-review writing and objective snapshots, followed by template metadata and remaining calendar/structural gaps. Authenticated ownership and final reconciliation/compatibility/recovery acceptance remain pending. Step 1 is not complete; cloud synchronization remains off.
