# Read-only export milestone

**Supported User Data Model versions:** 1.0 target definitions; legacy source capture only. Capture format `plenact.read-only-capture`, version 1.
**Status:** Remaining workspace definitions and frozen-backup capture/preflight implemented and tested with synthetic workspaces. A native saved-source snapshot/export boundary is now implemented on the working branch; legacy-to-portable conversion, restore and cloud upload remain unimplemented.

## What is ready

The remaining [account](Contracts/1.0/account.schema.json), [profile](Contracts/1.0/user-profile.schema.json), [label/category](Contracts/1.0/label.schema.json), [Studio settings](Contracts/1.0/studio-settings.schema.json), [saved artwork](Contracts/1.0/studio-artwork.schema.json), [Today shortcuts](Contracts/1.0/today-shortcuts.schema.json) and [display preferences](Contracts/1.0/workspace-display-preferences.schema.json) have final definitions. A [workspace export](Contracts/1.0/workspace-export.schema.json) joins these to planning/content/assets with ownership and reference checks. This is a synthetic target contract; no current user workspace has yet been converted into it.

The [capture tool](../../Tools/UserDataModel/capture_export.py) reads a caller-supplied frozen backup directly. It does not run app loaders that might supply defaults/examples, normalize source values, execute review/recovery decisions or save migrations. Known preferences are stored in type-preserving binary-plist wrappers; embedded Data remains byte-for-byte unchanged. All files in the four app-owned media areas are copied, including unreferenced originals. Neither live app containers nor credentials are discovered automatically.

**A complete source capture is not a completed Model 1.0 conversion.** Every capture declares `portable_conversion_complete: false`. The full workspace fixture is manually constructed synthetic data, not the output of a migration adapter.

## Frozen input boundary

The offline input directory must contain:

```text
frozen-backup/
├── Preferences.plist
├── Documents/
│   ├── CardAttachments/
│   └── ProfileAvatars/
└── Library/Application Support/
    ├── PlenactStudioArtwork/
    └── PlenactCollectionBackgrounds/
```

`Preferences.plist` is an explicitly prepared copy of the app-owned persistent preference domain. The media directories are optional, but referenced missing files are reported. Do not rename an actively changing app container “frozen” and assume atomicity: obtaining a coordinated mobile snapshot is a separate native integration step. No backup from a real installation was read during this milestone.

The reader detects input replacement/changes during capture, checks media inventory and hashes again, and aborts instead of publishing a successful result. These checks do not make a live multi-store filesystem snapshot transactional. The caller must supply a consistent frozen source.

## Capture output

```text
new-private-capture/
├── manifest.json
├── Values/
│   └── <hash-of-preference-key>.plist
└── Blobs/
    └── <sha256-of-exact-file-bytes>.bin
```

Each value file contains one property-list key named `value`, retaining its original Data/array/dictionary/string/Boolean/integer/real/date type. This wrapper is not a re-encoded Swift model. The source domain file's digest is retained in the manifest, but the entire domain file is not copied because it may contain unclassified values. Current source values can be recovered from the wrappers; a restore command is not implemented.

The manifest records store classification, original relative media paths, byte lengths, digests, excluded key names and issue codes. Identical binary files can share one blob while preserving distinct source paths. Private output directories use mode 0700 and files mode 0600 on the tested platform. Outputs are new: existing directories are rejected. Failures remove only this attempt's newly created directory.

Input and output cannot overlap. Symlink media/manifests, traversal paths and nonregular media files are rejected. The verifier checks manifest shape, value wrappers, exact hashes and file sizes. Hashes detect mismatched bytes; there is no authenticated signature or encryption in this local capture format.

## Inventory and diagnostic behavior

- Known user-data stores include Board, calendar, personal collections, labels, profile/preferences, templates, plans/reviews, Studio, appearance, bookmarks/importance, shortcuts and recent-history values. The exact allowlist is in the tool's `JSON_STORES`/`NATIVE_STORES` declarations.
- Device-only navigation/viewport/cadence dismissal values are captured as device state, not promised cross-device settings.
- Recovery journals, example-load undo and migration backups are retained separately as recovery data. A pending daily-review transaction raises a blocking review issue; capture never executes or clears it.
- Unclassified preference values are excluded and reported for review, rather than guessed safe to publish. Standard NS/Apple preference keys are excluded. Keychain and private server configuration are never opened by this tool. This is not arbitrary-content secret redaction: approved user-data stores retain their exact private contents.
- Corrupt JSON Data, unsupported document versions, unexpected top-level/native types, unsafe filename references and missing media produce `needs_review`. Saved bytes remain preserved. Absent stores remain absent; no starter content or default settings are created.
- `captured` means this allowlisted source capture passed its byte/inventory checks with no recorded issues. It does not prove native decoding semantics, field mapping, source completeness beyond the reviewed allowlist, account linkage, timezone interpretation, or portable synchronization compatibility.

The current tooling bounds the preference domain at 64 MiB and the JSON manifest reader at 8 MiB. Oversized input fails explicitly rather than truncating data. These are local tooling limits, separate from the finalized network limits. Updating the source inventory/allowlist is required when new application stores are introduced.

## Remaining field mappings now defined

| Current source | Target meaning |
| --- | --- |
| Local profile ID/name/email | Preserve source profile ID and source creation time; name/email are profile text, never proof of authenticated identity. |
| Local profile preferences | Separate portable user preferences. Standalone planning preferences take precedence under the existing resolver; an adapter must preserve conflicting source bytes for review. |
| Avatar colors/icon/photo | Portable color/icon plus asset reference; original local filename stays in the private journal. |
| Label/category string IDs | Scoped, durable UUID mapping with category references; authored names and palette tokens retained. |
| Studio view dictionary | Explicit stable destination entries; repeated destinations rejected. Display labels map to stable lowercase tokens. |
| Studio surfaces/artwork | Retain all material/framing/preview/header/text/italic fields; replace filenames with asset references. Imported assets and reusable artwork remain separate. |
| Today shortcuts | Ordered owner-qualified List references; source normalization caps presentation at six, but an adapter must report extra stored entries instead of silently truncating the source. |
| Saved display preferences | Preserve unset values as null instead of assuming the current platform's defaults. |
| Remote account | Verified stable account ID remains separate from local profile identity. Current definition is server-owned, not a client signup or authentication implementation. |

The full workspace validator checks shared ownership/workspace IDs, category/label references, default List and shortcut references, selections, and profile/Studio assets. It does not infer ownership from Justin Reina's display name. Schemas for these records do not establish a live account or authorization policy.

## Reproduce synthetic checks

Use the Python environment described in the [tool guide](../../Tools/UserDataModel/README.md):

```sh
python Tools/UserDataModel/capture_export.py --snapshot /path/to/explicit-frozen-backup --output /path/to/new-private-capture
python Tools/UserDataModel/capture_export.py --verify /path/to/new-private-capture
python -m unittest discover -s Tools/UserDataModel -p 'test_*.py'
```

The first command exits 0 for a verified capture, 2 when a review report is written, and 1 on a failure with no successful artifact. It never prints raw preference values. The verify command checks the captured artifact; it does not revisit or prove the historical state of an unavailable source backup.

## Verification evidence — October 24, 2026

See [Conformance](Conformance.md) for current schema, fixture and cross-language results. Regression tests include exact Data/native-type/media preservation, unknown/corrupt stores, missing files, all media areas, duplicate file content, recovery journals, concurrent source change, output collisions, symlinks, unsafe paths, failed copies and truncated captures.

All capture tests use synthetic temporary backups. No personal snapshot, live UserDefaults, Keychain, iPhone data or remote database was read or changed. The existing app executable and server routes are unchanged.

## What comes next

1. Exercise the new native saved-source snapshot/export on a device, including Files cancellation, background imports and retained recovery diagnostics.
2. Implement native legacy decoding and durable owner-qualified identity maps, exposing ambiguous dates, projection conflicts and missing references for explicit resolution.
3. Convert a captured workspace into the workspace-export contract, checking field/reference counts and byte hashes against capture evidence. A real complete export requires this step; it is not achieved by changing the manifest's completion flag.
4. Verify an explicitly opted-in personal backup locally, then build staging transport/restore procedures before any upload.

## Current implementation follow-up

See [native iOS backup/export](iOS-Migration-Export.md), [versioned SQL/JSON examples](Doc/Examples/README.md) and the [current application/data plan](../Application-Data-Plan.md). The frozen GitHub Model 1.0 release remains unchanged; this working-branch documentation records subsequent implementation progress.

## New native migration evidence

The native iOS preview now retains private identity journals and partial conversion records. The older Python capture format 1 cannot represent these extra artifacts. The tool refuses source folders containing `Migration`, `MigrationPreview` or the native migration-support directory before creating output, instead of claiming a capture while omitting identity evidence. Preserve the original native folder; see [native migration status](iOS-Migration-Identity.md).
