# iOS original-file verification and Asset preparation

**Supported User Data Model versions:** 1.0. Native source/preview format 1; local Asset-preview format 1; private identity journal formats 1/2/3.
**Status:** Working-branch, account-unbound preparation. Exact files and content references are verified; canonical account-owned Asset records, complete workspace import/export and cloud transfers remain pending.

## What this adds

`MigrationPreview/AssetPreview.json` connects converted attachment/background references to the exact original files preserved beside `Preferences.plist`. It inventories **all** original files under the four owned areas, including currently unreferenced originals:

- `Documents/CardAttachments`
- `Documents/ProfileAvatars`
- `Library/Application Support/PlenactStudioArtwork`
- `Library/Application Support/PlenactCollectionBackgrounds`

Each local entry retains its stable Asset target ID, source-relative path, basename, described/unavailable state, decimal byte length, SHA-256, conservative media kind/MIME hints, source format where explicitly known, nullable derivation and exact converted record/field-path references. Same filenames in separate owned areas remain distinct; equal file bytes do not merge source identities. Asset IDs use the existing owned-media path plus saved digest discriminator, so repeated preparation of the same source reuses IDs. A missing source file has no digest discriminator; newly available or changed bytes are separately qualified evidence, not a silent overwrite of an older file identity.

The UI shows **Verified original files**, **Missing original files**, and nonzero **File review items**. The report exposes `verified_original_file_count`, `missing_original_file_count`, `asset_review_item_count` and `asset_account_binding_pending`. These are local verification/preparation counts, not uploaded files or canonical Asset record counts.

## Account boundary and canonical compatibility

Model 1.0 `asset` requires a verified `account_id`. This preview does not have authenticated ownership. It therefore emits an explicitly local `plenact.ios-asset-preview` artifact with `account_binding_pending: true`, rather than manufacturing an account or weakening the released schema. The local source path and file references are evidence for future packaging; they never enter canonical `Records` as an Asset payload. The canonical account-bound payload will later require verified ownership and final validation.

Converted Cards retain original attachment metadata, captions, cover-attachment identity, remote links and bundled artwork tokens. Their canonical Asset references still have explicit pending `unavailable_reference` records while account-bound Asset publication is incomplete. Such a pending reference does **not** mean the file is missing: the local Asset entry separately reports whether its bytes are present and hash-verified. Remote URLs and bundled illustration tokens are not downloaded or invented as local files. Remote attribution already retained by content/appearance conversion remains there; this slice does not infer attribution or file-creation timestamps from an attachment's added date.

## Drawings and type evidence

A native drawing attachment has a rendered image and a distinct editable PencilKit file. Both originals retain separate IDs and hashes. The image's prepared `derived_from_asset_id` points to its source strokes when that relationship is unambiguous. Contradictory parents, self-dependencies, cycles and conflicting media roles produce explicit review issues; cyclic claims are removed instead of exported as valid dependency edges. Shared source files remain shared targets with multiple content references.

Known image/audio/video signatures provide **hints**, not decoder, playback, rendering or malware validation. PencilKit provenance comes from the native drawing-file role and is identified as `source_role`. Unrecognized bytes remain binary/octet-stream; filename extensions alone do not establish a format. Described means byte length and checksum are verified, not that every decoder accepts the media. Missing files retain null size/checksum and an explicit review item. Source-derived format/role information remains distinguishable from signature hints.

## Integrity boundaries

Preparation verifies every manifest-declared original's exact byte length and SHA-256 and walks every owned media subtree. Changed files, missing declared files, undeclared originals, symlinks, nonregular entries, unsafe paths and oversized evidence block preparation before the durable journal is written. A referenced filename absent from the captured inventory instead remains a legitimate unavailable entry; valid originals continue to be prepared. Originals are never resized, recompressed, decoded/re-encoded or replaced by thumbnails. Unreferenced and zero-length originals are retained.

Hashes prove agreement with the frozen manifest, not authenticated publisher identity. Source backup review, Simulator source recovery/undo and future portable workspace import are separate boundaries. The existing bounded in-memory export limit remains 256 MiB; no truncation is introduced.

## Verification

The focused native suite passes **51 tests**: the earlier 47 checks plus four Asset cases. The model/tooling suite passes **77 checks**. Native fixtures include a generated PNG, real empty PencilKit serialization, audio/video **signature probes** (not playback fixtures), an empty binary file, repeated basenames across all four roots, preserved unreferenced originals, a deliberately missing photo, changed/undeclared/symlink media and contradictory drawing cycles. Test preferences/files are isolated; no personal backup is imported or restored by these tests.

Actual native output includes the full original fixture bytes as a synthetic test attachment. Independent checking validates all emitted canonical records, compares all nine file hashes/lengths with those exact bytes, verifies every content field pointer and drawing derivation, and confirms that four unreferenced originals remain present. The local Asset artifact does not pretend to satisfy authenticated ownership. Released Model 1.0 schemas and tags remain unchanged.

## Owner-driven Simulator test

1. Rebuild/run **Plenact Import Test**.
2. Add and save a small drawing to a test Card. Optionally add a photo or another supported attachment. The earlier owner backup contained no media, so this creates a meaningful file-link test.
3. Open Today → Settings → Your data → Local backup and prepare a fresh backup.
4. Choose **Central — America/Chicago**, then prepare the migration preview.
5. Inspect verified/missing-file and review counts, then save the combined backup under a new name for ZIP verification. Keep earlier backups.

A normal new drawing should preserve its PNG preview and editable strokes as separate files. Actual totals depend on retained originals and other saved media. Source backups may legitimately retain older unreferenced files; verification does not delete them.

Remaining Step 1 work includes other settings/profile/shortcuts and planning/review adapters, authenticated account/workspace binding, canonical selections/Assets, a complete portable workspace export/import path and full recovery acceptance. Cloud staging, synchronization and other clients remain later steps.


### Additive appearance representation update

The global Week/theme and artwork-order gaps described at earlier checkpoints now have working Model 1.1 records, emitted separately from base records. See [versioned representation and compatibility](Version-1.1.md). Publication, ownership binding and complete workspace recovery remain pending.
