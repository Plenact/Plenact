# Portable workspace assembly

**Supported User Data Model versions:** 1.0 base; 1.1 working appearance composition.

## Current implementation

`Tools/UserDataModel/assemble_workspace.py` assembles already-canonical records in memory into the complete Model 1.1 export structure. It retains the unchanged Model 1.0 base, global Week defaults and ordered artwork library. It preserves record payloads and input array order without mutating the caller’s records. Complete schema and relationship validation runs before returning an export.

Unknown record kinds, migration drafts, duplicate identities, multiple singleton records, missing ownership, mixed workspaces, invalid account references and unresolved artwork membership are rejected. The assembler does not mint identities, repair references or silently omit records.

This is an offline tooling component, not an iOS export button or import implementation. A canonical account passed to this function is an input, not proof of authenticated ownership. Production callers must establish account/workspace ownership separately. Asset metadata does not prove that original files are present: byte verification remains a separate prerequisite.

## Verification

Five synthetic tests cover exact complete-export roundtrip, input independence, unknown drafts, duplicate identities, absent and multiple owners, mixed workspaces and artwork membership. The full Python tooling suite passes 98 tests at this checkpoint. No personal backup was bound, imported or uploaded. Native application code is unchanged by this checkpoint.

## Remaining work

1. Connect the tested offline synthetic binding adapter to a complete native backup inventory and report. Reject omitted required slices and pending review issues before presenting a complete-backup claim.
2. Extend the tested per-slice assembly to a single end-to-end native-generated workspace, packaging exact original bytes and provenance with the validated export.
3. Implement a reviewed portable import with retained recovery data, then guide the owner through the separate Simulator test. The earlier native source restore is not this portable import.
4. Require authenticated personal account/workspace binding before personal cloud export or synchronization. The Version 0 demo is not that authority.

Model 1.1 remains a working definition. This checkpoint publishes no release and enables no cloud synchronization.

## Synthetic native-draft binding checkpoint

`bind_synthetic_preview.bind_preview` now validates and binds supplied settings/profile, Studio, personal selection and Asset drafts to a fixed synthetic owner in memory. Existing preview workspace and content identities remain unchanged. Stable selection identities derive from the synthetic owner and target Card; uncertain bookmark/importance values and reported review issues block assembly. All originals must match the Asset inventory, byte counts, checksums and emitted field references. Verified canonical Assets replace matching temporary unavailable-reference records; the original placeholders and full drafts remain in separate evidence.

The result is explicitly wrapped as `plenact.synthetic-assembly-test`, with `ownership_verified: false` and `cloud_upload_allowed: false`. The nested workspace passes the complete contract; it is not a production-authenticated artifact. The adapter does not certify source completeness when draft categories are omitted, package original file bytes for transfer, install data, or expose new iOS controls. A caller must not extract the nested workspace and treat its synthetic account as authenticated ownership.

Five binding regression tests pass; the complete Python suite now passes 103 tests. `check_synthetic_assembly.py <xcresult-attachments-directory>` separately passed existing Swift-generated media, settings/profile and Studio evidence with 9, 1 and 2 originals respectively. It checks stable retry, unchanged content, exact file inventory and rejection after corrupting each original. A synthetic bookmark/importance selection on a native-generated Card also passes. These are separate synthetic slices, not one combined personal workspace or a portable recovery test. Native application sources were unchanged in this checkpoint.

## Synthetic package checkpoint

Supported User Data Model versions: 1.0 base and working 1.1 composition. `synthetic_export_package.py` now packages a validated synthetic assembly, its original bytes and evidence into a reproducible ZIP. `Manifest.json` declares exact members, byte lengths, checksums and Asset-to-original mappings; `Assembly.json` retains the explicitly synthetic wrapper and migration evidence. `Originals/<sha256>.bin` stores each distinct byte sequence once while preserving separate source paths and Asset identities. This local transport is not a new synchronization API or published Model 1.1 release.

The verifier reads the archive in memory and extracts nothing. It rejects duplicate/unsafe/undeclared members, unsupported versions, changed bytes, missing originals, mismatched Asset metadata, unexpected owner context and bounded-size violations. Checksums detect corruption, not authenticated provenance. The writer verifies serialized output and disk bytes before atomically publishing a new destination; existing files are never overwritten. Original backup files are never opened for writing.

Seven package regression tests pass, bringing the Python suite to 110 tests. The repeatable native-evidence checker now packages and reopens the Swift-generated media, settings/profile and Studio slices with exact evidence and original-byte equality, deterministic retries and corruption rejection. These remain separate synthetic cases with 9/1/2 originals. They do not establish that a combined native backup includes every required source slice.

Remaining work is a single complete native-source coverage gate and integration of package preparation into the application, followed by reviewed portable import and recovery in the separate Simulator. No portable package has been installed into an app, and no personal identity has been authenticated by this tooling.

## Native Simulator package preparation

**Supported User Data Model versions:** 1.0 base and working 1.1 composition; portable test package format 1.

The Simulator Local backup screen now offers **Prepare portable test package** after migration preview preparation. `MigrationTestPackage.swift` checks source integrity, reported adapter blockers, review counts, known remaining draft stores, explicit settings/Studio readiness, selection values and exact original-file inventory. Unknown source stores or review requirements block preparation. It assembles account-bound records using the fixed synthetic account, retains preview identities, replaces verified Asset placeholders, and retains draft evidence. UUIDv5 selection identities match the independent Python assembler.

The Files export is a folder containing the unchanged native source backup and migration preview, plus `PortableTestPackage/Manifest.json`, `Assembly.json` and `Originals/`. It is intentionally a folder for the existing iOS Files exporter; the Python test transport serializes those package members as a ZIP for verification. It uses no external Python runtime inside the app. Changing the selected original timezone clears stale previews and prepared packages. Preparing a fresh backup or preview also discards stale package state.

The native preparation gate does not replace independent full schema/reference validation. The interface explicitly requests independent review before portable import and makes no claim of authenticated ownership or successful recovery. There is no portable import control yet, no personal account binding, and no cloud upload. The existing Simulator recovery buttons continue to restore the native source backup only.

### Manual test

1. Build and run the updated app on **Plenact Import Test**.
2. Open **Settings → Your data → Local backup**.
3. Tap **Prepare local backup**, choose **Central — America/Chicago**, then tap **Prepare migration preview**.
4. Tap **Prepare portable test package**. If review is required, export the existing backup/preview for inspection; do not treat it as complete.
5. On success tap **Save portable test package to Files…**, using a new name, then share the saved folder for independent inspection. No restore action is needed for this checkpoint.

### Acceptance evidence

The focused native suites pass 70 tests, including a new combined calendar/Card/bookmark/importance/profile/preferences/Daily Plan/Studio/artwork/global-appearance package and an unknown-source rejection case. The native test verifies exact original preferences, deterministic package bytes and file-byte equality. Its actual emitted assembly and manifest independently pass complete Model 1.1 schema/reference and package-integrity validation with two original files. Separate native media/settings/Studio package cases remain passing. All 110 Python tests pass. This is a synthetic package-preparation checkpoint; manual personal-export review and portable recovery remain pending.

Repeat the combined native evidence check with:

```sh
python Tools/UserDataModel/check_synthetic_assembly.py --native-package /absolute/path/to/synthetic-xcresult-attachments
```

## Read-only portable import review boundary

**Supported User Data Model versions:** 1.0 base and working 1.1; synthetic package format 1.

The Simulator Local backup screen now has **Portable package review → Choose portable test package…**. Choose the previously exported folder or its `PortableTestPackage` subfolder, not its ZIP. The reader selects only portable members; it does not read or restore `Preferences.plist`, native source media directories or migration-journal state. Selection reads a bounded frozen tree and performs manifest/member checks, exact original-byte verification, synthetic ownership/version checks, unique record identities, core membership/reference checks and authored artwork membership checks. It displays portable record, Card, List and original-file counts.

This is a read-only boundary for a future importer. It does not implement the entire independent JSON Schema validator inside Swift, certify all field mappings, install portable records, issue an import receipt or prove portable recovery. The existing source-backup restore controls remain a separate mechanism. Selecting a package grants no permission to write data.

Native combined-package tests now also exercise this reader and reject a changed assembly and unsupported package version. Independent full contract validation of the actual saved v11 package had already passed before this review UI was introduced. Manual review of that same folder in the rebuilt Simulator is the next owner-operated checkpoint.

## Isolated portable test installation and undo

**Supported User Data Model versions:** 1.0 base and working 1.1; isolated test-store format 1.

After review, the Simulator offers **Install isolated portable test copy…**, followed by explicit confirmation. The installer consumes the frozen portable snapshot, not `Preferences.plist` or source media directories. It writes an immutable generation under application support `PlenactPortableTest`, records its checksum, reopens and verifies its package/files, and only then atomically changes a small activation file. The preceding generation is retained for undo. Undo validates the retained previous package before changing activation; undoing the first installation returns the isolated store to empty. Reopening Settings reads the retained test selection from disk.

The main app's existing workspace, native preferences, migration identities, original backup and source-recovery controls are unchanged. The new store and install/undo actions are restricted to the Simulator. The installed inspector reads canonical portable records directly and displays Lists, Cards, completion, bookmarked/importance values, artwork names, Daily Plan intentions and summary counts. It is read-only. It does not yet adapt the portable store into the main app's editing views or enable synchronization.

### Owner-operated test

1. Rebuild **Plenact Import Test**. Open **Settings → Your data → Local backup**.
2. Under **Portable package review**, choose the existing **v12 folder** and confirm the familiar counts. A new export is unnecessary.
3. Tap **Install isolated portable test copy…**, then **Install isolated test copy** in its confirmation.
4. Under **Isolated portable test workspace**, open **Inspect installed test workspace**. Compare Card titles/completion, saved importance/bookmarks, artwork names, plan intention and original-file counts.
5. Leave and reopen Local backup to verify persistence across view reconstruction.
6. Tap **Undo last portable test installation**. The isolated store returns to its previous state (empty for a first installation). The main workspace should remain unchanged throughout.

### Automated evidence and remaining limits

The focused native suite passes 71 tests. The combined native fixture now verifies installation, reopening through a fresh store instance, undo to empty, retained-state restoration, and a failure injected immediately before activation leaving the old activation bytes unchanged. A separate test corrupts the previous generation and proves undo rejects it without changing the active selection. Build validation also passes for the inspector. These checks exercise a local test-store transaction, not power-loss fault injection or live cloud recovery.

Manual installation/undo of the actual v12 package remains to be performed by the owner. Step 1 is still incomplete: full semantic import into the active editable application model, authenticated account/workspace binding, complete import acceptance and subsequent cloud integration remain pending. This checkpoint must not be represented as a production migration or active-workspace restore.


## Editable main-workspace test integration

Supported User Data Model versions: 1.0 base and working 1.1. The new **Editable Simulator workspace** section now provides a separate, confirmed main-workspace import with complete prior-state undo. It uses portable reconstruction, not native source-backup restoration. [Scope, recovery and manual instructions](Editable-Import.md) are authoritative for this newer checkpoint. The isolated inspector remains read-only. Fresh portable export after editable changes is still pending and disabled; native format-two backups preserve current changes and canonical import evidence.
