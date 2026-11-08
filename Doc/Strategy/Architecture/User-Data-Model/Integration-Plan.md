# Model 1.0 implementation and acceptance plan

**Current implementation status — November 7, 2026:** [Step 1 beta closeout](Step-1-Beta-Closeout.md) is complete for the bounded local beta and handoff to **Step 2 synthetic staging**, with v25 owner-accepted. Deferred operations and production migration/authentication/synchronization gates remain explicit. Cloud synchronization is disabled; Model 1.0 is unchanged and working 1.1 is unpublished. Earlier implementation checkpoints below are historical.

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


### Periodic-review/objective export checkpoint — October 26, 2026

Periodic-review title/writing, progress/completion, priorities and independent starting/current objectives now reconcile with retained IDs and authored UUIDs for new reviews. Removed records, changed retained ranges/zones and malformed objective data fail closed. All 66 affected native tests, 112 tooling tests and independent periodic-package checks pass. See [scope and pending owner test](Editable-Import.md#periodic-review-writing-and-objective-edited-export--october-26-2026). v12 remains accepted. Template metadata, calendar/structural gaps, authenticated binding and final reconciliation/recovery acceptance remain pending; Step 1 continues with cloud synchronization off.


### Owner-accepted periodic-review writing/objectives — October 26, 2026

The owner re-imported independently verified v13 and confirmed restored periodic writing, period and objective values/statuses, with earlier weekly reflections retained. v13 is the latest accepted checkpoint. See [scope and evidence](Editable-Import.md#owner-acceptance-periodic-review-writing-and-objectives--october-26-2026). The first checkpoint has empty starting objectives; inherited starting/current snapshot behavior retains synthetic coverage. Next is template metadata/library reconciliation, beginning with a bounded retained-template edit. Remaining calendar/structural gaps, ownership and final reconciliation/recovery acceptance remain pending; Step 1 continues and cloud synchronization remains off.


### Retained-template metadata checkpoint — October 26, 2026

Retained template names and library order/default Week selection now reconcile with stable template/library/content IDs, including clearing the default. Creation/removal and template date/weekday/focus policy changes remain unsupported. All 67 affected native tests, 112 tooling tests and independent two-original synthetic package checks pass. See [scope and pending owner test](Editable-Import.md#retained-template-metadata-edited-export--october-26-2026). v13 remains accepted; remaining template lifecycle, calendar/structural gaps, authenticated binding and final reconciliation/recovery acceptance remain pending. Step 1 continues with cloud synchronization off.


### Template editor presentation fix — October 26, 2026

The owner encountered immediate editor dismissal before the rename acceptance test. A synthetic hosted library reproduced duplicate presentations from Group-distributed modifiers. One persistent presentation anchor now retains the editor across library loading; isolated tests verify typing/dismissal without changing saved bytes. All 69 selected native checks pass. See [cause and retry scope](Editable-Import.md#template-editor-presentation-correction--october-26-2026). v13 remains accepted; v14 rename export/round-trip is pending, with cloud synchronization off.


### Owner-accepted retained-template rename — October 26, 2026

The owner completed editable re-import of independently verified v14 and confirmed the retained template's renamed Name field. v14 is the latest accepted checkpoint. Only that canonical name changed from v13; identities, library order/defaults, prior data and all five originals were preserved. See [acceptance scope](Editable-Import.md#owner-acceptance-retained-template-rename--october-26-2026). Template lifecycle/context changes and remaining calendar/structural, ownership and final reconciliation/recovery work remain pending. Step 1 continues with cloud synchronization off.


### New-template creation export checkpoint — October 26, 2026

New Day/Week captures and duplicates in a retained library now export with authored template UUIDs, independent deterministic owner/content identities, verified media and frozen-only alias translation. Copied same-owner references remain attached to copied Cards. Retained-template deletion, context changes, absent-library creation and unresolved references remain blocked. Validation passes 68 export/recovery/template checks, two separately run hosted focus checks, 112 tooling tests and independent three-original package checks. The initial combined runner exited during the existing nested keyboard test; its cause remains unconfirmed. See [scope and pending owner test](Editable-Import.md#captured-and-duplicated-template-creation-edited-export--october-26-2026). v14 remains accepted. Step 1 continues; cloud synchronization is off.


### Owner-accepted Day-template creation — October 26, 2026

The owner completed editable re-import of independently verified v15 and confirmed the new Day template with four items in the library. v15 is the latest accepted checkpoint. Its only additions are the template and independent Collection/List/four Cards; all retained data, default/order and five originals are preserved. See [acceptance scope](Editable-Import.md#owner-acceptance-captured-day-template-creation--october-26-2026). Template application, retained-template removal/context changes, absent-library creation, calendar/structural gaps, authenticated binding and final reconciliation/recovery acceptance remain pending. Step 1 continues with cloud synchronization off.


## Template deletion checkpoint — October 26, 2026

Complete-snapshot edited export now removes unreferenced templates and exclusively owned content, clears a deleted default, retains explicit empty libraries and preserves originals plus native/runtime recovery evidence. Surviving references, transferred aliases and intersecting pending Card-deletion intent reject export. No server tombstones, published schema changes or authenticated ownership claims are introduced.

Validation passes 69 export/recovery/template checks, 112 tooling tests and independent deleted-template package validation (two synthetic originals). The two existing hosted keyboard-focus checks were excluded from this export run. Default/all-template deletion, no resurrection on load, live Week preservation, repeated export, fresh import/re-export and rejection boundaries have isolated coverage. The latest owner-accepted package remains v15; one focused custom-template deletion/export/re-import test is pending. See [the detailed checkpoint](Editable-Import.md#template-deletion-edited-export--october-26-2026). Step 1 remains in progress; synchronization stays off.


## Template deletion UI follow-up — October 26, 2026

v16 is structurally valid but unchanged from v15; the attempted deletion never reached a confirmation dialog. A failing hosted regression reproduced the invisible trailing-anchor problem. Moving confirmation to the visible template row passes that regression plus editor stability and deletion export/recovery checks. Owner retry/export v17 is pending, with no Undo first. v15 remains accepted. See [the repair checkpoint](Editable-Import.md#template-deletion-confirmation-repair--october-26-2026).


## Owner acceptance: template deletion v17 — October 26, 2026

The owner completed editable v17 re-import and confirmed the custom Day template stays absent while neighboring retained templates remain. The independent comparison already verified that only the intended template-owned subgraph was removed and all surviving canonical records, five originals and native recovery hashes were preserved. v17 is the latest accepted checkpoint; no repeat test is required. Step 1 remains in progress, with cloud synchronization disabled. See [acceptance evidence](Editable-Import.md#owner-acceptance-template-deletion-v17--october-26-2026).


## Retained template Card edit verification — October 26, 2026

A new isolated test verifies the existing adapter for retained template Card title/details and edit history, stable owner/content identity, unchanged live Week/sibling templates, source/runtime recovery preservation and fresh import/identical re-export. No production exporter change was required. The new native test, 112 tooling tests and independent package validation (two synthetic originals) pass. One focused owner title edit/export v18 is pending from accepted v17; no Undo first. See [checkpoint boundaries](Editable-Import.md#retained-template-card-content-checkpoint--october-26-2026).


## Owner acceptance: retained template Card v18 — October 26, 2026

The owner confirmed editable v18 re-import and the edited Card title in the retained Week template. This closes the focused title-edit acceptance checkpoint; v18 is now accepted. Independent comparison establishes that only the intended Card title/history changed, preserving all other canonical values, five originals and native recovery integrity. No repeat test is required. Template item creation/deletion and other Step 1 boundaries remain separate work. See [acceptance evidence](Editable-Import.md#owner-acceptance-retained-template-card-v18--october-26-2026).


## New template item creation checkpoint — October 26, 2026

The template editor now uses durable portable reservations and an authored creation instant for new Cards/Notes. This closes its local-ID collision and missing-timestamp gaps through the existing structural exporter. Cancellation consumes unused reservations; allocation failure leaves drafts unchanged. Synthetic tests prove unchanged retained/live content and library metadata, Card/Note presentation/order, exact native/runtime recovery, fresh import and identical re-export.

Validation: 72 affected native tests, 112 tooling tests and independent package validation pass (two synthetic originals); the two previously isolated keyboard-focus tests were excluded from this export run. A focused new template Card test/export v19 is pending from accepted v18, with no Undo first. See [scope and evidence](Editable-Import.md#new-cards-and-notes-inside-retained-templates--october-26-2026). Step 1 remains in progress; cloud synchronization is disabled.


## Owner acceptance: new template Card v19 — October 26, 2026

The owner reports successful editable v19 re-import. Screenshots confirm the retained Week template now has 43 items and the new Monday Card is restored. The independently verified addition preserves durable identity, prior canonical values, five originals and native recovery integrity. v19 is the latest accepted checkpoint; no repeat test is required. Notes and cancellation/failure retain synthetic coverage; item deletion and other Step 1 boundaries remain separate work. See [acceptance evidence](Editable-Import.md#owner-acceptance-new-template-card-v19--october-26-2026).


## Retained template item deletion verification — October 26, 2026

The existing local Card-deletion overlay supports ordinary retained-template item removal without deleting canonical content or changing live Weeks/sibling templates. A new isolated native regression verifies complete assembly preservation except the overlay UUID, source/runtime/native recovery integrity, fresh import with the item absent and identical re-export. Retained focus requiring the target blocks export rather than silently changing that metadata.

The new test, 112 tooling tests and independent deletion-package validation pass (two synthetic originals). No production change or new full-suite count is claimed; the earlier 72-test run remains the broad baseline. Owner removal/export v20 is pending from accepted v19, with no Undo first. See [scope and limits](Editable-Import.md#retained-template-item-deletion-checkpoint--october-26-2026). Step 1 remains in progress with synchronization off.


## Owner acceptance and live application follow-up — October 27, 2026

Template item deletion is accepted in v20: the owner completed editable re-import, and read-only saved-template inspection confirms the item stays absent while the earlier title remains. v20 is now the latest accepted package. The owner also explored template application; saved live Week content now extends beyond the v20 export. Preserve that current state and inspect application/export behavior before further replacement. No application acceptance or Step 1 completion is claimed. See [the checkpoint](Editable-Import.md#owner-acceptance-template-item-deletion-v20--october-27-2026).


## Additive template application checkpoint — October 27, 2026

Template Apply now reserves and remaps newly copied identities at commit time for retained portable Weeks, preserving read-only preview behavior, copied links, bookmarks and example importance. The structural exporter handles only the explicit false-to-true saved-Week intent transition; other calendar metadata remains guarded. The existing initially absent/new-Week path is unchanged; replacement and wider calendar behavior are not accepted by this checkpoint.

Validation passes 74 affected native tests, 112 tooling tests and independent application-package validation (two synthetic originals). Tests cover two additive applications, nested/reference/selection identity, retained source content, frozen/native recovery evidence, fresh import/re-export and failure guards. The two hosted keyboard-focus checks were excluded from this export run. Owner application/export v21 is pending from accepted v20; no Undo first. See [detailed scope](Editable-Import.md#additive-template-application-to-retained-weeks--october-27-2026). Step 1 continues; cloud synchronization remains disabled.


## Applied-template importance ordering follow-up — October 27, 2026

The owner's first application export failed despite valid reserved new item identities. Read-only diagnosis found multiple newly applied importance selections in arbitrary Set order. An expanded synthetic fixture reproduces the unsupported export failure, which is fixed by owner-qualified sorting only in the frozen importance-store comparison. All values/duplicates/unknown fields remain preserved for validation; live stores and runtime evidence are unchanged.

Validation passes 75 native/112 tooling tests and independent synthetic application-package checks. Owner retry is pending: rebuild and export the already applied workspace as v21, with no further Apply or Undo. v20 remains accepted. See [repair evidence](Editable-Import.md#applied-template-importance-ordering-repair--october-27-2026). Step 1 continues with synchronization off.


## Owner acceptance: additive template application v22 — October 27, 2026

The owner completed editable v22 re-import and confirmed the copied template title/content alongside original Monday items. Package review shows the expected 353 records, 212 nondeleted Cards, 37 Lists and five originals. Independent comparison already verified the 49 independent copies, seven bookmarks, seven importance markers, unchanged retained canonical values and valid native recovery evidence. v22 is now the accepted checkpoint; no repeat application is needed. Replacement/new-Week application and other Step 1 boundaries remain separate work. See [acceptance evidence](Editable-Import.md#owner-acceptance-additive-template-application-v22--october-27-2026).


## Retained Week replacement verification — October 27, 2026

Week-template Replace mode passes explicit synthetic round-trip coverage using existing application/reservation and local deletion behavior. Replaced dated work remains canonical/recoverable; archives and undated work remain native; copied links/bookmarks/importance and original files survive fresh import/re-export. The shared fixture seeds owner-qualified prior importance without weakening ambiguous legacy-reference guards.

Validation passes 76 native/112 tooling tests and independent replacement-package validation (two originals). The two hosted keyboard-focus checks were excluded from this native run. Clarified Week/Day confirmation wording passes the template-screen render test. One owner replacement/export v23 is pending from accepted v22; v22 preserves the Week before the intentional replacement. No Undo before export. See [scope and evidence](Editable-Import.md#week-template-replacement-checkpoint--october-27-2026). Step 1 remains in progress, synchronization off.


## Resume after the break — November 7, 2026

v22 remains accepted and replacement acceptance is still pending. Read-only saved-state inspection found a newly retained November 2 Week with 28 additional active entries; both earlier Weeks remain unchanged against runtime evidence. Preserve this newer state with a current-workspace v23 export before replacement or Undo. The earlier instruction to use v23 for replacement is superseded; independently review this rollover/preservation export first, then use the next version for replacement. No completed manual tests need repeating.

The restored temporary validator environment passes 112 tooling tests, and private general validation rechecks v22's package/originals/native recovery integrity. The prior 76-test native result remains historical evidence and was not rerun during this inspection. See [resume details](Editable-Import.md#resume-preserve-the-newer-week-before-replacement--november-7-2026). Step 1 continues with synchronization disabled.


## Replacement retry and tooling incident — November 7, 2026

The owner elected to skip the extra preservation export for disposable generated beta content and proceed directly with November 2 Week replacement/export v23, retaining v22. During the attempt, the debugger exited and several Simulator system processes produced simultaneous SIGBUS reports. Saved state confirms the replacement has not persisted; the existing iOS 27.0 test device remains available and shut down. A newly installed iOS 27.2 runtime is correlated in time but not established as the cause. No application fault or replacement acceptance is established. User-operated Xcode/Simulator relaunch is the next step; no data reset or repeat import is requested. See [diagnosis and steering](Editable-Import.md#resume-steering-and-simulator-disruption--november-7-2026).


## New-Week replacement importance reconciliation — November 7, 2026

The owner completed a Replace application into the automatically generated November 2 Week, but edited export rejected inconsistent saved references. Read-only inspection found importance entries belonging to removed Cards in that newly generated Week. Unlike the previously tested retained-Week replacement, this Week had not yet been exported.

The checked Week-save path now removes missing importance targets for that owner only when they are absent from the retained native import baseline. Previously exported selection evidence (including local deletion recovery), archive/undated targets and other owners remain preserved. Unknown or duplicate source entries fail closed. Export preparation still never repairs or mutates live stores.

A combined rollover/replacement regression reproduces the rejection, applies the checked-save reconciliation, and checks repeated export, source/runtime immutability, exact native backup preferences and fresh import with identical re-export. Validation passed: 77 affected native tests (the two previously excluded keyboard-focus tests remain excluded), 112 tooling tests, and independent retained-Week replacement package validation with two synthetic originals. Native log: `/private/tmp/plenact-rollover-replacement-full.log`; tooling log: `/private/tmp/plenact-rollover-replacement-python.log`. The existing saved owner workspace will require one checked replacement save after rebuilding; v22 remains the accepted checkpoint and v23 has not been accepted. Step 1 remains in progress, Model 1.0 is unchanged, and cloud synchronization remains disabled.


## Linked checklist rollover comparison — November 7, 2026

After the owner rebuilt and repeated the November 2 replacement, read-only inspection confirmed zero orphan importance targets. Export then reached a different unsupported-change guard. The copied Week contains linked checklist actions and retained Card-reference mirrors; the earlier combined rollover fixture contained only ordinary checklist text. Adding linked actions reproduced the rejection in isolated synthetic data.

Rollover now translates explicit nested `cardID` and `retainedCardID` references through the same owner-qualified mapping used for Card identities, only in the frozen comparison. Opaque edit-history evidence stays untouched, unresolved references still reject export, and live source/runtime files are unchanged. The richer fixture also exposed nondeterministic append order for newly added selections from multiple owners. Iterating owners by stable identity fixes new-record order without reordering retained selection records.

The regression checks repeated exports, exact source/native-backup preservation, fresh import, restored active/retained link targets and identical re-export. All 77 affected native tests passed, including eight additional same-snapshot export retries in the linked rollover case (the same two keyboard-focus tests remain excluded). Native log: `/private/tmp/plenact-rollover-links-final.log`. The next owner action is rebuild and export only; another replacement, Undo or import is unnecessary. v22 remains the accepted checkpoint.


## Owner v23 export independently verified — November 7, 2026

The supplied v23 archive passed the general portable package reader (schemas, references, manifest and original-file integrity) and independent native Preferences/media/runtime hash checks. Native review codes are empty; synthetic ownership remains unverified and cloud upload remains disabled. The private comparison reads the archives in memory and emits aggregate evidence only. No personal archive or extracted content was added to the repository.

Compared with v22, v23 adds one November 2 Week, one Collection, seven Lists, 49 Cards and 14 content selections. No retained records were removed; only the calendar index payload changes to add/select the new Week. All other retained portable record payloads and the existing local-deletion overlay remain unchanged. All five previous originals are byte-for-byte preserved, with no new originals. The new Week has seven bookmarks, seven importance selections and no orphan importance references. Its native Board matches the current Week.

Expected package-review counts: 425 portable records, 261 nondeleted Cards, 44 Lists and five originals. Canonical storage retains 263 Card records, including the two existing local-deletion targets. There are three retained Weeks. Numeric editor aliases and native timestamp precision can differ from the prior pre-import native backup; stable canonical records are the comparison authority.

Export validation is complete for v23; owner-operated re-import acceptance remains pending. Keep v22 as the previously accepted checkpoint. Next: Undo editable workspace import, choose the unzipped v23 folder, import into the editable Simulator workspace, then verify the November 2 replacement and a copied linked checklist action. Do not repeat template application. Step 1 remains in progress.


## Owner v23 re-import acceptance — November 7, 2026

The owner reported completion after restoring the pre-import workspace, reviewing v23 and importing it into the editable Simulator workspace. Supplied screenshots confirm the expected 425 records, 261 nondeleted Cards, 44 Lists and five verified originals, the successful import receipt with cloud synchronization off, and the November 2–8 replacement Week restored in normal Board views. Monday and Saturday show the six task rows and retained divider layout, appearance and importance indicators.

The owner reported the requested acceptance sequence complete. The screenshots do not show a linked checklist action opened; exact active/retained link targets are independently covered by the synthetic fresh-import regression, while v23 passed the general reference validator. No further repeat of this manual checkpoint is requested. v23 is now the latest owner-accepted export/re-import checkpoint; retain v22 and earlier recovery packages. Step 1 remains in progress, with the remaining inventory and ownership/reconciliation gates still open.


## Day-template application boundary — November 7, 2026

Two isolated regressions now cover Day-template addition and replacement into Tuesday of a retained Week. They reuse the production Apply/reservation/save/export path and the existing shared fixture rather than introducing a parallel adapter. Two additive copies and one replacement preserve other dated Lists and their bookmarks/importance, the selected day's archive, undated work, retained canonical Cards and local deletion evidence. Copied Card/Note links, source/runtime immutability, exact native recovery, fresh import and identical re-export pass. No production code change was required for this evidence checkpoint.

Validation: all four selected Day/Week application/replacement tests pass; 112 tooling tests pass. Independent `DayTemplateApplicationPackage` and `DayTemplateReplacementPackage` checks pass with two synthetic originals each. The previous broad 77-test run remains the broad baseline; do not describe this focused run as a new 79-test full run. Native log: `/private/tmp/plenact-day-template-focused.log`; tooling log: `/private/tmp/plenact-day-template-python.log`.

One focused owner test is pending from accepted v23: use Vacation Day → Preview & apply, destination November 3, 2026, Apply as Replace, confirm, then export v24. The other days must remain unchanged. The current build already contains the application path; no rebuild or Undo is needed before applying/exporting. Independently validate v24 against v23 before re-import. Step 1 and its remaining inventory gates remain open.


## Template settings navigate to Library — November 7, 2026

At the owner's request, Plan Settings → Day & Week Templates no longer repeats individual template rows. It keeps the existing default-Week and capture controls and presents **Open Templates in Library**. The redundant **Reload saved templates** action is also hidden in this Settings sheet and retained beside the Library listings. The action dismisses the nested template sheet, then Plan Settings, before selecting Plans/Library with the Templates filter and cleared search. Library remains the shared browsing/editing/application location; saved templates are not deleted or reclassified as Examples.

Actual unsaved Plan Settings changes offer save/discard/keep-editing; an unchanged Settings draft routes directly. The checked save action is shared with the existing Save button. Navigation is transient and does not change the portable model or recovery state.

The build and three existing Settings/Library/template rendering checks pass (`/private/tmp/plenact-template-settings-navigation-final.log`), including render-without-saving assertions. User-operated end-to-end navigation remains pending. Rebuild Plenact Import Test to check the new button, then continue the pending Vacation Day → November 3 Replace/export v24 test from Library → Templates. v23 remains accepted; no Undo/import is required before the new export.


## Owner v24 Day replacement export verified — November 7, 2026

The supplied v24 archive passed the general package schema/reference/manifest/original validator and native Preferences/media/runtime hash verification, with empty native review codes. The private in-memory comparison against accepted v23 confirms exactly three new Cards and two content selections, no removed canonical records, and one retained Tuesday List update (Card membership and subtitle). The seven old Tuesday entries are exactly the newly added local deletion targets; the two prior targets remain. All other retained canonical records and all five original files are unchanged. No personal archive or content was added to fixtures.

One native importance marker points to an intentionally deleted retained Tuesday Card. Its identity resolves through retained runtime aliases into the explicit local-deletion overlay; this is preserved recovery evidence, distinct from the previously fixed unexported orphan markers. The complete package reference validation passes. Screenshots confirm the three Day-template items on November 3 and the neighboring Monday task/divider layout retained before export.

Expected v24 review counts: 430 records, 257 nondeleted Cards, 44 Lists and five verified originals. Storage retains 266 canonical Card records, nine local deletion targets and three Weeks. Cloud synchronization remains off. Owner-operated editable re-import is pending: Undo editable workspace import, choose the unzipped v24 folder, import into editable Simulator workspace, then verify Tuesday's three items and Monday unchanged. No rebuild or repeated template application is required. v23 remains the accepted checkpoint until that focused acceptance completes.


## Owner v24 Day replacement acceptance — November 7, 2026

The owner reported the editable re-import acceptance sequence complete. Supplied screenshots confirm pre-import workspace restoration, the expected v24 review counts (430 records, 257 nondeleted Cards, 44 Lists, five originals), availability of editable import, and the three Vacation Day items restored on Tuesday November 3. No import-success alert or post-import Monday screenshot was supplied; the owner completion report establishes the completed sequence, while the earlier pre-export Monday screenshot and independent retained-record comparison establish the neighboring-day evidence.

v24 is now the latest owner-accepted export/re-import checkpoint, with v23 retained as the prior checkpoint. This closes the focused Day-template replacement acceptance; no repeat of this test is requested. Day addition retains synthetic evidence and is not separately owner-accepted. Step 1 remains in progress, with remaining calendar/structural, drawing, ownership and final reconciliation/recovery gates still open. Cloud synchronization remains disabled.


## Today shortcuts edited export — November 7, 2026

The next bounded settings adapter supports **My shortcuts** after editable import: explicit empty-store creation, selected owner/List references, authored order, replacement, removal and clearing. Retained singleton identity and unchanged canonical payloads are preserved; a genuinely new singleton gets a deterministic workspace-qualified identity. Only this recognized native store is newly allowed. Missing retained stores, unknown fields, duplicate/excess pins, invalid numbers and unresolved/mismatched ownership reject export rather than being normalized by the UI helper. Explicit `[]` is supported; removing a retained store is not.

The adapter resolves each List through verified numeric aliases plus its explicit Collection owner and membership. Rollover translates shortcuts into newly dated Week Lists only in the frozen comparison, alongside the existing owner-qualified List/Card mappings. Live stores and runtime files remain untouched during export. No authenticated ownership is inferred from a local profile.

A synthetic isolated fixture covers new empty presence, creation, reorder, six-item selection, clearing and references spanning a new Week, an older Week and a personal Collection. It verifies stable singleton identity, authored order, unchanged other canonical groups, exact native preferences/media, frozen-source/runtime immutability, repeated export, fresh installation and identical re-export. Malformed, duplicate, unknown, missing and wrong-owner targets reject without source/runtime changes. Independent `ShortcutsPackage` validation checks the general schemas/references/manifest/originals and the three-owner ordered rollover targets, with two synthetic originals. Tooling passes 112 tests. All 80 affected native tests pass (the same two previously excluded keyboard-focus tests remain excluded). Native log: `/private/tmp/plenact-shortcuts-full.log`; tooling log: `/private/tmp/plenact-shortcuts-python.log`.

One focused owner test is pending from accepted v24: rebuild Plenact Import Test, open Today → gear → My shortcuts, swap the first two Pinned rows, tap Done, then use Your data → Local backup → Export supported Card edits to Files… and save v25. My shortcuts has its own Done save. No Undo or re-import before the export. Independently compare v25 with v24 before the later re-import phase. Step 1 remains in progress; model publication and cloud synchronization stay disabled.


## Owner v25 shortcut reorder export verified — November 7, 2026

The owner supplied v25 and screenshots showing a swap of the first two Pinned shortcuts, with the third unchanged. The supplied Downloads path was unavailable; the same-version ZIP was read from the known Simulator Files storage. The separate v24 archive was no longer present in the checked locations, so comparison used the complete retained v24 import snapshot inside v25's verified native runtime evidence. The snapshot and v25 portable package both pass the general schema/reference/manifest/original validator; v25's native preference, media and runtime hashes pass with empty review codes. The retained baseline has the expected 266 canonical Cards and nine local deletion targets.

Only the `today_shortcuts` record changes: singleton identity is exact, the first two of its three owner/List references swap positions, and the third remains exact. No records are added or removed. All other retained canonical values, the local deletion overlay and five original files are unchanged. Private comparison and snapshot decoding operate outside the repository and do not import or mutate the Simulator. No personal content was added to fixtures.

Expected review counts remain 430 records, 257 nondeleted Cards, 44 Lists and five verified originals. Editable re-import acceptance is pending: Undo editable workspace import, review the unzipped v25 folder, import into editable Simulator workspace, then open My shortcuts and verify the swapped order without reordering it again. v24 remains the accepted checkpoint until that completes. Step 1 remains in progress and synchronization remains disabled.


## Owner v25 shortcut reorder acceptance — November 7, 2026

The owner supplied the completed Undo/review/editable-import sequence. Screenshots confirm the expected 430 records, 257 nondeleted Cards, 44 Lists and five verified originals; the successful editable import receipt explicitly states synchronization is off. The post-import My shortcuts screen confirms the first two pinned destinations retain their swapped order and the third remains in place. This closes the focused owner reorder round trip.

v25 is now the latest accepted export/re-import checkpoint; retain its ZIP and recovery history. No repeat of this manual test is requested. Shortcut creation, clearing and new-Week destinations retain isolated synthetic evidence rather than separate owner acceptance. Step 1 remains in progress with the remaining calendar/structural, drawing, ownership and final reconciliation/recovery gates open. No staging, commit, publication or synchronization was performed.
