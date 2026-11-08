# Version 1.1 — Appearance, artwork order and pending local Card deletions

**Supported User Data Model versions:** 1.1 composition and immutable 1.0 base.
**Status:** Working definition and native migration preview, not yet published on GitHub or deployed as a synchronization protocol. The existing `user-data-model-v1.0` release/tag and every file under `Contracts/1.0` remain unchanged.

## Why an additive version

Native migration exposed two source semantics with no complete destination in the released base model: the global Week Board theme and the order of multiple saved artwork looks. Version 1.1 adds dedicated records for these values. It does not add undeclared fields to 1.0 records or copy a global theme into currently retained Collections.

A complete 1.1 export uses the closed [1.1 workspace schema](Contracts/1.1/workspace-export.schema.json):

```text
1.1 workspace export
├── user_data_model_version: "1.1"
├── payload_schema_version: 1
├── base_workspace: unchanged complete 1.0 workspace export
├── workspace_appearance: nullable 1.1 workspace_appearance record
└── artwork_library: nullable 1.1 artwork_library record
```

The base workspace and its records explicitly retain version 1.0. New appearance records explicitly carry version 1.1 and payload schema 1. This composition is intentional, not an untagged mixture of versions in the original record stream. It lets future clients reuse the original 1.0 content/ownership validation while requiring explicit support for the extra semantics.

## Record definitions

### `workspace_appearance`

[Schema](Contracts/1.1/workspace-appearance.schema.json). A singleton per workspace. Its required `payload.week_board_defaults` is the complete immutable 1.0 Board appearance value shape. Global banner, List/Card defaults, backgrounds/surfaces, text colors and nullable subtitle italics remain global Week settings, applicable to future retained Weeks through the client's Week-Board inheritance path. Existing Card/List overrides and explicit Collection metadata remain independent. This migration changes no rendering, Collection appearance or future-Week creation behavior.

An absent source theme yields null/absent record. An explicitly saved empty theme yields an existing record whose complete appearance shape contains null inherited values. These meanings are not silently merged. The record belongs to the workspace, whose authenticated owner remains established through the base workspace; no new account identity is inferred.

### `artwork_library`

[Schema](Contracts/1.1/artwork-library.schema.json). A singleton per workspace. Required `payload.artwork_ids` is the exact authored sequence of active canonical 1.0 `studio_artwork` IDs. It contains every artwork in the base workspace exactly once, no duplicate, missing, deleted or foreign IDs. UUID sorting is never a replacement for this order.

An absent source library with no artwork yields null. A present empty source library yields an existing record with `artwork_ids: []`. A nonempty base artwork set requires a library record in a complete 1.1 export. The source native array supplies migration order. A previously unordered 1.0 export with multiple looks cannot gain a purported original order merely by sorting IDs; conversion needs original source evidence or a deliberate user-approved order.

## Integrity and compatibility

All new records must use the same workspace ID as the base. Their record IDs must be distinct from each other and all base record/tombstone IDs. Background photo references must resolve to base Assets or explicit unavailable/deleted Asset evidence. Complete base ownership, label/reference and planning checks still run unchanged before 1.1 relationships are accepted.

Readers/writers must explicitly advertise 1.1 support. App version ordering does not establish data-model capability. Base-only clients must reject unsupported composite exports without stripping the wrapper or silently editing/re-exporting its base. A downgrade is rejected whenever either appearance record exists, including an explicitly empty library. A composition with no added metadata and no artwork can expose its unchanged base without data loss.

The existing protocol 1.0 registry/API and Swift/Web/C# base codecs are not silently upgraded by these definitions. New record transport, capability negotiation and complete 1.1 import/export require explicit future integration. `appearance_contract.require_capability` is the working conformance gate, not a claim that a deployed service negotiates 1.1 today. The current 1.0 publication tooling is not a 1.1 release publisher; publish a separately reviewed 1.1 release rather than relabeling an archive or changing the existing tag.

## Native preview and journal compatibility

The current native migration keeps individual 1.0 records in `MigrationPreview/Records`. New records are in **`AppearancePreview.json`**, a local `plenact.ios-appearance-preview` format-1 envelope with explicit target 1.1, base 1.0 and `workspace_identity_scope: local_preview`. This is not yet a complete 1.1 export or proof of authenticated ownership.

`StudioPreview.json` local format 2 declares `appearance_model_version: "1.1"`. It keeps the original local Studio/global appearance evidence and checks it against the separately versioned records. Old local format 1 remains independently readable by tooling and continues to expose the former representation-gap notices. New format 2 requires matching appearance evidence before accepting the gap as closed. Asset evidence retains pointers to both the local draft and the new global record when relevant.

The UI adds **Model 1.1 appearance records**; it separates those records from the base **Converted preview records** count. Reports expose `appearance_model_record_count` and `supplemental_user_data_model_versions`. The source stores remain pending full workspace/account integration even though these representation gaps are now mapped.

Private journal format 3 adds `workspace_appearance` and `artwork_library` identity kinds. Readers support formats 1/2/3; allocating either new kind upgrades the journal without replacing source installation, preview workspace or existing 1.0 record UUIDs. Nested-ID allocation must never downgrade a format-3 journal to format 2. A format-1/2 document containing new kinds is rejected. Older readers that do not support format 3 must leave it intact and fail closed. The journal's legacy `targetModelVersion: "1.0"` still names the base model; separately versioned 1.1 identities and record payloads are explicit. Source backups preserve the journal as before.

## Verification and acceptance

The focused native suite passes **68 tests**; model/tooling checks pass **93 tests**. Three new native cases cover exact source artwork order, distinct version streams, format-3 upgrade/retry/downgrade safety and absent-versus-explicit-empty libraries. Existing Studio tests now verify the mapped global record instead of expecting an unresolved representation gap. Independent checks validate both actual native 1.1 records, original file pointers/hashes and unchanged base records. All frozen 1.0 contract file hashes are unchanged.

Three new schemas and three synthetic examples are checked independently with:

```sh
python Tools/UserDataModel/appearance_contract.py
```

The 1.1 conformance tests cover complete composition, explicit empty library, exact artwork membership/order preservation, workspace/record identity mismatches, base-only reader rejection, and prevention of lossy downgrade. This is working-branch evidence, not publication or real workspace recovery acceptance.

In **Plenact Import Test**, rebuild the app, retain or add a second saved Studio look, prepare a fresh backup/preview with Central time and inspect **Model 1.1 appearance records** plus any appearance review items. To exercise the global theme as well, save a Week Board Appearance choice through the Week board's Appearance controls. A Studio per-view wallpaper is a different stored setting. Export under a new name for direct source-by-source verification.

Remaining Step 1 integration: owner-driven checks of this new representation, verified account/workspace binding, canonical account-required drafts, complete 1.1 portable export/import and original-versus-restored recovery comparison. Publishing the new definition and staging a compatible API remain separate authorized follow-up actions.


## Pending local Card deletion overlay

**Supported versions:** working 1.1 composite only; immutable base 1.0 records and server protocol are unchanged.

The optional `local_card_deletions` property is a unique array of canonical Card UUIDs. Absence means no pending local deletions. Every UUID must resolve to a retained Card in `base_workspace.planning.content.cards`; unknown targets, duplicates and wrong types fail validation. For example, `"local_card_deletions": ["20000000-0000-4000-8000-000000000004"]` suppresses that retained Card in the editable projection.

This is offline deletion intent, not a server tombstone, acknowledgement, accepted revision, change sequence or durable synchronization outbox. The export cannot fabricate those server values. The base keeps the last imported record, original membership, personal selection intent, reference targets, history and Assets for recovery. It is not claimed to recover edits made after import and then permanently discarded before export. The accompanying exact native backup retains the complete currently available source evidence.

A 1.1 reader must apply this overlay when presenting active and archived Cards. Native import validates retained Card content/ownership, keeps its UUID/numeric alias reserved, omits the Card from both editable partitions and omits its active bookmark membership. Retained positive importance and historical/planning/checklist references remain owner-qualified metadata; no action is executed and no reference is rebound to a different Card. Original media remains verified and retained, including originals no longer used by a visible Card. The read-only portable inspector and review counts likewise suppress deleted Cards.

Re-export retains the same deletion IDs. Re-import must not resurrect the Card or allocate replacement identities. Model 1.0 downgrade is refused when this overlay is nonempty. Readers using an older closed 1.1 shape must reject the additional field; they must not discard it. This working definition must be frozen and published before production cross-platform use. Real server-confirmed deletion and acknowledgement remain future synchronization work.

Native tests cover deletion of a bookmarked, important Card, retention of its canonical record/aliases/originals, suppression of its bookmark, repeated import/export with no resurrection, and unchanged source Undo. Independent schema/relationship/manifest/original-file checks accept the generated deletion package. Python checks reject unknown/duplicate deletion targets and loss on downgrade.
