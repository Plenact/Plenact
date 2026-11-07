# Step 1 beta closeout — November 7, 2026

**Supported User Data Model versions:** 1.0 published base and working 1.1 composition; Version 0 is historical only.

**Decision: Step 1 is complete for the bounded local beta milestone and handoff to Step 2 synthetic staging.**

This is a scope decision backed by the existing implementation and evidence, not a declaration that every native edit is portable or that production migration/synchronization is ready. Justin explicitly chose to prioritize bringing the cross-platform application to life over completing every adapter first. The deferred items below remain real work, but do not block synthetic backend development.

**Accepted owner checkpoint: v25.** Model 1.0 remains immutable. Working Model 1.1 remains unpublished. Personal cloud upload and synchronization remain disabled. This decision does not deploy anything, publish a model, approve uploading personal data, or claim a production app release.

## The finite exit criteria

| Beta exit criterion | Evidence | Result |
| --- | --- | --- |
| Preserve the reviewed local source and originals before conversion | Frozen native preferences; four explicit media areas; hashed migration/runtime evidence; source-change and unsafe-file rejection | Passed within the reviewed inventory |
| Convert/import the supported portable graph with explicit identities | Owner-qualified identities, typed references, calendar/templates/planning/settings/media reconstruction; general schema/reference validation | Passed for the supported contract and package scope |
| Export supported edits without silently discarding changes | Retained baseline verification, explicit adapters, complete inverse projection of portable stores, unknown/unsupported changes rejected | Passed within the supported operation set |
| Reopen with equivalent content/settings and verified files | Repeated export, fresh import/identical re-export regressions; independent original-file checks; owner round trips through v25 | Passed |
| Recover the previous workspace and preserve imported edits | Retained pre-import backup, transactional rollback, Undo and recovery-history checks; user-operated Undo/re-import acceptance | Passed in the tested Simulator workflow |
| Keep test data separate from real ownership and remote writes | Synthetic owner, `ownership_verified=false`, `cloud_upload_allowed=false`, no cloud deployment or data upload | Passed |
| Make limitations explicit instead of endlessly expanding Step 1 | Supported inventory, deferred operations, local-only classifications and later-stage gates below | Recorded by this closeout |

The evidence is sufficient to build the backend against synthetic fixtures. It is not evidence that an arbitrary future workspace or unsupported app version can be migrated without further review.

## Coverage audit

The current reviewed-source inventory is defined in `LegacyStoreValidation`; unknown Plenact preference keys receive review codes rather than being guessed safe. Export preparation rejects nonempty native review codes. The frozen Model 1.0 source catalogue is historical definition evidence, not a claim that today's source files still match its original hashes.

| Source family | Portable treatment | Beta boundary |
| --- | --- | --- |
| Board, dated Weeks, personal Collections/Lists | Stable canonical owners/content, archive/order metadata, current-Week projection | Retained ownership and duplicate projections are checked; unsupported owner lifecycle changes stop export |
| Cards/Notes and nested values | Content, dates, checklists/links, comments, members, reactions, appearance, attachment metadata and history | Supported edited fields are reconciled; new drawing derivations are deferred |
| Label catalogue/categories and shared display choices | Initial migration and reconstruction exist | Subsequent edits without a dedicated verified adapter remain guarded; not a new beta feature commitment |
| Bookmarks and importance | Explicit owner-qualified selections and local Card-deletion recovery evidence | Retained deleted targets may remain canonical; no server tombstones are fabricated |
| Profile, app preferences, Studio, artwork and global Week defaults | Model 1.0 records plus explicit working 1.1 composition | Profile identity is local authored identity, never authenticated account ownership |
| Daily plans, check-ins and evening/weekly/periodic reviews | Authored writing, progress, historical references, objective snapshots and supported edits | Export does not replay review decisions or schedule notifications |
| Review rhythm and Today shortcuts | Shared intent and explicit ordered owner/List references | Shortcut reorder owner-accepted in v25; creation/clearing/rollover also have synthetic evidence |
| Template library and application | Bounded capture/duplication/removal/content/metadata adapters; Week/Day application and rollover | Remaining context/weekday/focus and reference-dependent lifecycle changes are deferred |
| Owned original files | Complete regular-file inventory within the four reviewed areas, with byte lengths/hashes | New image originals supported in reviewed paths; changed old bytes, ambiguous paths and unsafe files reject |
| Local navigation, recovery machinery and unfinished drafts | See the local-only policy below | Retained as native evidence when reviewed; not represented as shared user records |

No field is declared portable merely because the initial migration can decode its containing store. For edited export, unmatched differences still stop preparation. A rejection preserves the active workspace; it is not successful export of a reduced subset.

## Source/export reconciliation and files

`PortableEditedExport.prepare` validates the retained package, aliases and native baseline before applying adapters. It checks store presence, active media references and verified originals, constructs the candidate, then performs a second complete native projection to reject missed fields or divergent saved copies. Comparison-only alias/Set/timestamp normalization does not rewrite live stores or originals. The output includes the exact frozen `EditedNativeBackup` in addition to the portable package.

The reviewed media areas are:

- `Documents/CardAttachments`
- `Documents/ProfileAvatars`
- `Library/Application Support/PlenactStudioArtwork`
- `Library/Application Support/PlenactCollectionBackgrounds`

The native capture also retains the reviewed migration identity journal and the three portable runtime evidence files: `CanonicalPackage.bin`, `IdentityAliases.json` and `NativeStores.plist`. The explicit 256 MiB preparation ceiling rejects oversized snapshots; it does not truncate them.

This is not an arbitrary filesystem backup. Files outside those areas and unknown preference values are not certified as preserved by this exporter. Unknown Plenact keys are reported and block portable preparation; keep the original workspace until they are classified. Do not erase a source on the strength of a partial or rejected package.

## Local-only and recovery policy

Shared preference choices remain shared by default. The following are deliberately not shared user-data records:

| Class | Current handling |
| --- | --- |
| Library/Activity recents, recent searches, viewport/scroll position, last-viewed List, welcome departure state | Device navigation history; reviewed values remain in native backup. Changes covered by the exporter's explicit exclusion list need not alter portable records |
| Local reaction-author token | Local attribution machinery, distinct from canonical reaction data and real account identity; preserved as reviewed native evidence |
| Example-location application/backup markers | Native recovery evidence; not portable user records |
| Review-invitation dismissals and unfinished creation drafts | Initial migration classifies these as device-local. Edited export does not currently exempt every such value; their presence/change may conservatively block export. Do not clear them automatically to force success |
| Pending daily-review transaction, example Undo state and other recovery machinery | Retain source/recovery evidence; pending or unmapped state may require resolution before portable export. Never replay it during conversion |
| OS notification permissions/delivery, credentials, tokens and platform caches | Not shared via a workspace package. Keychain/server secrets are outside this workspace backup; importing shared notification intent must not grant OS permission or activate delivery |

These exclusions do not turn preferences such as maps choice, appearance, review intent or shortcut order into device-only settings. Cross-device recents and draft migration can be designed later as explicit features if desired.

## Accepted limitations and deferred work

The user has accepted a beta scope rather than complete portability for every editing operation. The following are deferred; current rejection/recovery behavior remains in force:

- Cross-Board transfers and owner-changing operations, including their linked-reference consequences.
- Retained List/Week/Collection deletion and arbitrary Collection creation outside supported paths.
- Changed first-weekday policy, retained calendar/day mappings and cross-Week checklist overrides.
- Remaining template context/weekday/focus changes, initially absent template-library creation and reference-dependent removal.
- Label/category and other store edits that do not yet have a dedicated verified reconciliation path.
- New drawing derivations or changes to previously verified original bytes.
- Broad app/device/version coverage and owner acceptance of every automated-only path, including all avatar/artwork variants and Day addition.

This list is not an implicit implementation queue before Step 2. Revisit an item when required by a concrete beta workflow, and retain the fail-closed behavior until its adapter and evidence exist. Do not bypass guards simply to make an export succeed.

## Acceptance evidence and practical limits

The latest broad affected native run passed **80 tests**, and the tooling suite passed **112 tests**. The same two previously isolated keyboard-focus tests were excluded from that native run. These counts describe the affected migration/export/recovery suites, not every application test.

Relevant persistent regressions include `testProtectedEditableWorkspaceActivationAndRecovery`, the template application/replacement tests, `testRolloverReplacementReconcilesUnretainedImportance`, `testTodayShortcutEditedExport`, and the source-backup/restore tests. They use synthetic isolated preferences and temporary containers. Independent package checks validate actual emitted synthetic assemblies, references, manifests and original bytes.

Temporary evidence, when still present:

- `/private/tmp/plenact-shortcuts-full.log`
- `/private/tmp/plenact-shortcuts-python.log`
- `/private/tmp/plenact-shortcuts-evidence`

Owner-operated acceptance progressed through v25. The latest package has **430 reviewed records, 257 nondeleted Cards, 44 Lists and five verified originals**. Its shortcut record preserves identity and swaps only the first two destinations. All other retained canonical values, original bytes and the local deletion overlay are unchanged. Its independent comparison used the complete validated v24 import snapshot embedded in v25's hashed recovery evidence because the separate v24 ZIP was no longer in the checked locations. The successful re-import and restored order are owner-confirmed.

Tests and acceptance apply to the named iOS 27 Simulator workflow. They do not establish physical-device migration, older/newer runtime compatibility, operating-system-loss recovery, real authentication, server restore or multi-client conflict behavior. Native keyboard-focus exclusions are not data-conversion certification failures, but remain UI test debt.

This closeout describes the working tree above `e7b5fe8` on `feature/ios-local-backup`. The changes remain uncommitted unless Justin commits them. No new release/tag or immutable build artefact is claimed by this document. Keep the accepted package and recovery history private; no personal content belongs in repository fixtures or publication assets.

## Handoff to Steps 2–4

1. **Step 2 — backend/API staging:** begin with a read-only Bluehost inventory of runtime, database, isolation and backup/restore capabilities. Establish a separate synthetic staging namespace. Implement/test the contract with synthetic records and verified media; owner authorization, atomic receipts, retries, server restore and account/workspace binding belong to that running-service evidence. PHP remains a hosting-dependent implementation candidate, not a verified deployment assumption.
2. **Step 3 — iOS synchronization:** add durable offline changes/outbox, conflict handling, cursor/restart recovery and verified media transfers. Preserve indefinite offline use. A local snapshot exporter is not an offline synchronization engine.
3. **Step 4 — other clients:** connect web and subsequent clients to the tested contract. The current desktop direction is C++/Qt for Windows, macOS and Linux, superseding the earlier Windows C# recommendation; see [platform decisions](../Lessons/Platform-Languages-and-Desktop-Architecture.md). iOS remains Swift; other client work is not implemented by this milestone.

Before any personal-cloud pilot, require authenticated stable account/workspace ownership, an explicit reviewed import/binding transition from synthetic test ownership, safe handling of working 1.1 capabilities and local deletion intent, tested server/iOS recovery, and owner authorization for that pilot. Display names/emails do not establish ownership. Local pending-deletion overlays are not server tombstone acknowledgements.

Working Model 1.1 must not be silently substituted into published 1.0 schemas or advertised as a published release. Stage against a pinned, explicitly supported contract set; publication remains a separate explicitly authorized action. Do not upload v25 or recovery archives to synthetic staging.

**Step 1 beta exit is closed. Production migration and synchronization gates remain open. Step 2 may proceed with synthetic data; no cloud activation is part of this closeout.**
