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
