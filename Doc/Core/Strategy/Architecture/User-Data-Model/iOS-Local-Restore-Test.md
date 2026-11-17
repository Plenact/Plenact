# Simulator-only local backup recovery test

**Supported User Data Model versions:** 1.0 preparation; native source-backup format 1.
**Status:** Working-branch local recovery workflow. This restores legacy source bytes, not a portable Model 1.0 workspace or cloud account.

## Owner-driven acceptance

Use the separate **Plenact Import Test** Simulator. The owner selects that destination in Xcode and builds/runs the latest code. No real backup is automatically imported by development tools.

1. Open Today → Settings → Your data → Local backup.
2. Scroll to **Simulator recovery test** and choose **Choose backup folder…**.
3. Select the extracted **Plenact Backup** folder, not the ZIP or its MigrationPreview subfolder. It must be available in that Simulator's Files storage.
4. Inspect reviewed store/List/Card/media counts. For the supplied source export, the inspected archive contained 16 stores, 7 active Board Lists, 28 active Board Cards and no media files.
5. Only after checking those counts, choose **Restore into this Simulator…** and confirm. The app removes its old navigation tree, flushes queued Board writes, retains a verified pre-import snapshot, installs reviewed source bytes, and reloads workspace state.
6. Compare Week content, personal collections, importance/bookmarks, settings and templates. A later source export can provide stored-byte/semantic comparison evidence; viewing counts alone does not establish complete recovery acceptance.
7. **Undo last test restore** restores the retained previous destination. Repeated imports are refused while that undo copy remains, preventing silent replacement of recovery evidence.

If the test Simulator cannot see the folder, copy it through Finder into that Simulator's local Files storage. The original Mac ZIP/source folder remains the recovery reference. Do not select the original working Simulator as the restore destination.

## Boundaries

The control is compiled only for Simulator builds. It does not create an authenticated account, import Model 1.0 records, enable sync or carry account credentials. Saved source settings/profile, when present, replace their local counterparts; a fresh local test profile can be created separately after restoring. Device/recovery evidence is restored as source state, not synchronized as commands.

Review reads a bounded private snapshot, rejects symlinks/nonregular entries and oversized data, verifies source/media hashes and declared media membership, uses native source decoders, requires a consistent active Board/Week projection and checks retained preview identity lineage. Pending recovery/review issues block installation. Unknown destination/platform values remain; reviewed app-owned stores and media areas are replaced. Installed media and journal bytes are verified before preference commit.

The transaction reuses FullMonthExampleStore's verified snapshot/Transition format. Failed installation restores the pre-change state; an interrupted operation recovers at launch through the existing recovery gate. A committed workspace that cannot reload blocks stale UI. Pre-import data is kept separately from the example-month user backup and is removed only after successful undo cleanup.

Synthetic tests cover review without mutation, exact preference/media restore and undo, failed-install rollback, tampered preference bytes, undeclared media/symlink rejection and preservation of undo evidence across repeated-import attempts. Existing backup/migration and dataset-recovery regressions run alongside them. Real Files-provider interaction and owner-driven inspection remain manual acceptance work.


## Imported portable-runtime evidence

Supported User Data Model versions: 1.0 base and working 1.1; native backup formats 1/2. Source recovery now also verifies/restores format-two backups containing current native values plus portable canonical baseline/identity evidence. This remains source recovery, distinct from the [editable portable importer](Editable-Import.md). Old format-one captures cannot represent the new runtime evidence and must not strip it.
