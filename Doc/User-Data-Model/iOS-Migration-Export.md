# iOS native migration and export milestone

**Supported User Data Model versions:** 1.0; Version 0 historical reference only.
**Updated:** October 24, 2026.

**Runtime status:** Native source backup, durable migration identities and the first partial canonical converters are implemented on the current working branch. Twenty-two focused iOS simulator tests pass. Complete portable workspace conversion, production-device restore and cloud integration remain unimplemented. A separate Simulator-only source recovery test is now available below.

Open **Settings → Your data → Local backup**, or **Account & Settings → Settings → Privacy & Data → Local backup**. Choose **Prepare local backup**, inspect counts/review status, then **Save backup to Files…** and choose a trusted destination. Finish editing/importing first; the backup includes saved changes only. Canceling the system chooser does not modify the workspace.

The main-actor capture waits behind queued Board persistence, reads the actual persistent preference domain (not registered defaults/fallback loaders), preserves allowlisted native values and exact embedded Data in `Preferences.plist`, and copies originals—including unreferenced files—from all four owned media areas. Double-reading preference/media state detects overlapping background changes and rejects that attempt.

`NativePreflight.json` identifies `plenact.ios-frozen-backup`, format 1, target Model 1.0, creation time, store/media counts, digests and review codes. It always declares `portable_conversion_complete: false`. This is a frozen source backup layout, distinct from both a canonical workspace-export and the Python capture tool's own manifest format. The [offline capture tool](Read-Only-Export.md) can consume source-only folders. Its older capture format 1 now refuses folders containing migration journal/preview evidence rather than silently dropping those files; retain the original native folder.

Native decoders inspect saved Board/calendar/personal content, labels/profile/preferences, templates/plans/reviews, Studio, selections and recent history without rewriting their outputs. Corrupt/wrong-type/future-version stores remain preserved with review diagnostics. Pending review recovery is reported, never executed. Unknown app preference keys are excluded and reported for classification; this is not an unqualified complete-device backup. Missing/unsafe file references are reported; unsafe filesystem entries or unreadable media abort export rather than yielding a silently partial backup. Nothing is uploaded.

Current preparation uses an in-memory folder snapshot with an explicit 256 MiB source-byte ceiling. Larger input fails clearly without truncation; a streaming export is future work. The snapshot can briefly occupy the main actor while copying/hashing. Files may use a provider chosen by the user, including a cloud-backed Files destination; the app itself sends no synchronization request.

## Verified and unverified

Seven isolated native backup tests cover absent/registered stores, corrupt/recovery byte preservation, unknown-key review, all original-media areas, symlink refusal, native type/version checks and missing/unsafe media references. App/test targets built successfully. Tests never read the personal preference domain or media container.

Real-device Files provider behavior, interruption/low-memory handling and the complete prepare/save/reopen experience still need hands-on acceptance. Existing unrelated actor-isolation warnings in PlanningReviewTests and Xcode's no-AppIntents metadata notice remain outside this change.

## Migration preview now available

After preparing a backup, choose **Prepare migration preview**. The app converts saved label categories, labels and shared display choices into canonical Model 1.0 documents. It does not manufacture a label library or display record when those stores are absent. Unset values remain null; false remains false; whitespace/Unicode writing and authored label order are preserved. Duplicate IDs, missing categories, unknown source fields and incorrectly typed preferences block this conversion.

The preview adds `MigrationPreview/Records`, `Report.json` and `IdentityJournal.json` alongside the original source backup. The report explicitly records incomplete conversion, an unlinked cloud account, local-only workspace identity, remaining synchronized stores and separately preserved device/recovery data. **Save backup and preview to Files…** saves that combined directory. No record is uploaded.

The app privately persists `Library/Application Support/PlenactMigration/source-identities-v1.json` before making preview output available. Subsequent source backups preserve/hash that journal at `Migration/IdentityJournal.json`; the latest preview also includes its updated journal. Corrupt/incompatible journals are not reset, stale writers are rejected and existing mappings cannot be removed/reassigned. See [identity and preview details](iOS-Migration-Identity.md).

Fifteen migration tests cover retry/restart identity, owner/kind/creation distinctions, stale writes, immutable namespaces, corruption/future fields, duplicate labels, exact text, category references, unset/Boolean choices, source integrity, pending review recovery, lifecycle classification and resumed backup identity. Actual Swift-generated category/label/display documents were exported from XCTest attachments and independently passed the published Python/schema validator. This checks three canonical record types, not a complete workspace or server authorization.

## Next conversion milestone

Extend native conversion to content/collections, calendar/planning/reviews, profile/preferences and assets. Preserve original source ownership through moves, reconcile Week/Board projections, resolve ambiguous dates/references, implement verified account/workspace binding, emit a complete validated workspace-export, compare all fields/counts/bytes and prove local recovery. No completion flag is a substitute for those adapters.

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


## Review-rhythm edited export checkpoint

Supported User Data Model versions: immutable 1.0 review-rhythm payloads within working 1.1 composition. Saved invitation, time, weekday and notification-intent changes now export, including creation of the recognized rhythm store. Existing identity and untouched history are retained; malformed/unknown values and retained-store removal are rejected. The 59 affected native tests and 112 tooling tests pass; both new/retained synthetic packages validate independently. No notification scheduling runs during export. See [scope and pending owner acceptance](Editable-Import.md#review-rhythm-edited-export--october-26-2026). v8 remains the latest accepted owner checkpoint; cloud synchronization remains off.


## Daily-plan writing/check-in export checkpoint

Supported User Data Model versions: immutable 1.0 daily-plan records within working 1.1 packages. Edited export now supports saved daily writing, priorities, vision progress, check-ins and newly saved dates, preserving explicit historical reference provenance and unchanged values. Unsupported references, retained-plan removal/date-zone identity changes and evening-review edits are rejected. All 60 affected native and 112 tooling tests pass; the synthetic daily package validates independently. See [current scope and pending owner test](Editable-Import.md#daily-plan-writing-and-check-in-edited-export--october-26-2026). No review action or scheduler runs during conversion; Step 1 remains in progress and cloud synchronization remains disabled.


## Evening-review edited export checkpoint

Supported User Data Model versions: unchanged 1.0 evening-review objects within working 1.1. Reflection creation/edits, progress/completion, achievements and recorded history now export without executing decisions. All 62 affected native tests, 112 tooling tests and independent evening-package checks pass. See [scope and pending acceptance](Editable-Import.md#evening-review-writing-and-history-edited-export--october-26-2026). v10 remains accepted; unsupported cross-Board outcomes and weekly/periodic edits remain pending, with cloud synchronization disabled.


## Weekly-review edited export checkpoint

Supported User Data Model versions: immutable 1.0 weekly-review records within working 1.1. Edited export now reconciles saved weekly writing, priorities, decision history, progress/completion and newly saved reviews with stable identity and explicit source context. No action executes; unsupported outcomes still fail closed. All 65 affected native tests, 112 tooling tests and independent weekly-package checks pass. See [current scope and pending owner test](Editable-Import.md#weekly-review-writing-and-history-edited-export--october-26-2026). v11 remains accepted; cloud synchronization stays disabled.
