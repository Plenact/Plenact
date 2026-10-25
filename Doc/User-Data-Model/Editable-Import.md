# Editable application import bridge

**Supported User Data Model versions:** 1.0 content; working 1.1 package input.

**Current status:** The Simulator can now import a supported portable package into its normal editable workspace with a full pre-import backup and undo. This remains a synthetic-owner test flow. The guarded edited export now supports Board-created Cards/Lists, movement within one existing Board/collection, List/Card ordering, and Card text, completion, scheduling, deletion, lock/display flags, nested Card content, attachment metadata/covers and history. Other edits stop export explicitly. Native backups preserve every saved change and canonical baseline evidence. This does not yet complete Step 1 or enable production ownership/synchronization.

## Implemented content bridge

`PortableEditableContent.swift` and `PortableEditableNested.swift` reconstruct actual `PersonalCollection`, `KanbanList` and `KanbanCard` values directly from canonical records, without reading `Preferences.plist`, a source backup, example loaders or live defaults. Collection UUIDs remain explicit; numeric editor aliases for portable Card/List UUIDs are allocated independently of titles. The adapter returns its alias map. Existing aliases can be supplied to subsequent reconstruction so newly added records never renumber retained identities; deleted identities remain reserved. Persisting and integrating that map with the active workspace is coordinator work still pending.

Collection List order, active/archive Card order, derived List titles and bookmarked membership are reconstructed. Content handling covers text, completion/lock/presentation values, labels, comments, assignments, reactions, recursive checklist actions, inactive retained detail/links, file references, covers, appearance and layout overrides, and edit history. Opaque history data is decoded as retained bytes, including distinct absent and zero-length values; it is never interpreted or executed. Importance remains a separate canonical selection and requires the selection-store adapter.

The bridge requires explicit timezone/day context for civil dates and time-only scheduling, rather than guessing from List titles or device defaults. Timed values use their retained UTC instant. Missing day context, invalid wall times and tested repeated/skipped Central DST hours are rejected. The coordinator must derive day ownership from canonical calendar metadata, not weekday names; renamed Lists remain legitimate. Canonical metadata must remain retained alongside the native projection because the current editor models cannot represent every portable setting or date provenance field.

## Fail-closed scope

Unknown/missing mapped fields, mixed workspaces, duplicate identities, unsafe file aliases, missing original-file mappings and out-of-range appearance values reject reconstruction. This pure mapper requires a preceding package/record validation boundary and verified Asset-file placement; passing a filename dictionary is not proof that bytes were copied. Account-authenticated author/member semantics unsupported by the current editor are rejected rather than downgraded to demo or manual identities. An authored focused-List override cannot be persisted by the current computed native property, so non-null portable overrides are rejected in this bridge.

Existing native Codable constructors still normalize some semantically equivalent default values. This adapter is not a replacement for the retained canonical records, and tests do not claim byte-identical native re-encoding of every portable field. An active-workspace coordinator must preserve canonical values, apply actual editor changes explicitly, and refuse unsupported semantic mappings.

## Automated evidence

The focused native suite passes 73 tests. New rich synthetic content tests reconstruct real editable models and verify title whitespace, ownership separation for identical titles, active/archive order, location, completion/locking, scheduling instants, appearance flags, nested retained actions, comments/reactions/assignments, files/cover identity and opaque history bytes. Alias allocation is stable across input reordering and retained-map expansion. Unknown fields, missing original mappings, missing date context and DST gaps/folds fail closed. The final additional workspace/range guards pass the content suite.

No application workspace was installed, replaced or made editable in this checkpoint. Existing Simulator isolated installation remains read-only. No new owner-operated export test is requested.

## Remaining active-workspace integration

1. Reconstruct calendar/index and template ownership, planning/review data, account/profile/preferences, labels, Studio and selection stores into a complete coordinated workspace. Retain canonical identities and provenance alongside native editing projections.
2. Place verified originals into their appropriate native media areas with collision-free names and persistent Asset mappings.
3. Connect the complete result to navigation teardown, guarded activation, reopen verification and retained recovery. Only a complete supported result may switch the main editable workspace.
4. Run one owner-operated end-to-end acceptance test after integration. Keep authenticated ownership and synchronization separate from the current synthetic package.

## Calendar and personal metadata reconstruction checkpoint

**Supported User Data Model versions:** 1.0 calendar/settings/template records and working 1.1 appearance metadata.

`PortableEditableCalendar.swift` now reconstructs `PlanningCalendarDocument` and `PlanningRoutineLibrary`. Explicit canonical week/day mappings drive date ownership, preserving renamed List titles independently. Week and routine order, current Week, first weekday, saved flags, template timezone/anchor/kind, selected default routine and example-focus membership are retained. Checklist cross-Week mappings resolve canonical metadata Week IDs to native collection identities; duplicate, missing or ambiguous matches fail closed. Template-only content remains separate from live Week ownership.

`PortableEditableSettings.swift` reconstructs `LocalProfilePreferences`, `LocalProfile`, `LabelLibrary`, ordered Today shortcuts and positive `LibraryImportanceItem` entries. Account-qualified inputs require the expected workspace/account context. Effective preferences are mapped explicitly, including false/zero values and default-List aliases. Profile identity uses the canonical profile record ID for its local projection; original source-profile provenance remains in the canonical record and is never used as authentication. A profile without explicit preferences is rejected rather than manufacturing native defaults. Avatar filenames require an Asset mapping.

Labels retain canonical identifiers to match reconstructed Card label references. Shortcut ownership and order are checked against collection membership. Bookmark membership is reconstructed on native collections; positive importance is reconstructed separately, while explicit zero intent remains retained in canonical selections. These are projections, not a new authoritative account identity.

The same metadata adapter reconstructs Studio destination surfaces, default Card/Note surfaces, saved palette order/duplicates, variety flags, authored reusable-look order and separate global Week defaults. Model 1.1 artwork-library membership is required for saved looks. Reusable look IDs use their canonical record identities. Global defaults are not copied into each collection override.

### Current automated evidence

New native tests compare reconstructed calendar and routine metadata against isolated source-model oracles, verify profile/effective preferences and distinct shortcut owners, and compare native Studio settings and global Week appearance exactly. Card selection tests check reconstructed importance and bookmark membership. All tests remain synthetic; no owner-operated export cycle is requested. The focused suite now passes 76 tests.

### Remaining integration boundaries

Planning/review documents and reminder intent still need native reconstruction. The coordinator must preserve canonical provenance, retain the numeric identity map, place verified media in the appropriate areas, handle runtime timezone policy (the legacy live calendar derives its runtime calendar from device settings), and activate the complete editable workspace through protected navigation teardown/reload. No reconstruction method writes application stores. The protected main-workspace switch and real account authentication remain unimplemented.

## Planning/review reconstruction and original-file staging

**Supported User Data Model versions:** 1.0 planning/reviews/Assets; working 1.1 appearance references.

`PortableEditablePlanning.swift` now reconstructs native Daily Plan, Weekly Review, Periodic Review and Review Rhythm documents directly from canonical records. It preserves historical priority titles/locations, explicit null versus empty check-in history, submitted progress/moods, saved workflow steps, decisions, achievements and independent starting/current objectives. Reference-epoch timestamps are derived from the retained UTC instants. Unavailable historical references receive reserved aliases and are not rebound to current same-title or reused numeric Cards. Live references must agree with owner and source-creation evidence.

Review actions are decoded into native history values but never applied. Reminder preferences are retained as values but no notifications are scheduled. Unknown fields, invalid progress/counts, duplicate logical store keys and malformed focus values reject reconstruction. Native periodic-review IDs use the canonical record identity; original source provenance stays in retained canonical evidence. An empty canonical planning array becomes an empty native document rather than invoking a loader or synthesizing example content.

`PortableMediaPlacement.swift` now prepares a collision-free filename per verified Asset UUID, retaining a safe original extension when available. It derives required media areas from actual canonical file references and also preserves unreferenced originals in their declared owned area. Shared Assets are copied to multiple native areas only when those references require it. The returned filename map feeds the editable model adapters; filenames are never inferred from Card titles.

Staging requires a new isolated directory and refuses existing destinations. Exact bytes and complete file inventory are checked after writing, with the same bounded export ceiling; failures remove only the newly created candidate. Missing/undeclared/corrupted/nonregular entries fail verification. These methods do not replace active media, write app preferences, authenticate ownership or switch the workspace.

### Evidence

The focused native suite passes 78 tests. New planning reconstruction checks preserve actual submitted historical text, nullable history, all eight decision actions as data, distinct unavailable results, independent objective snapshots and zero-minute/notification preference intent. Invalid progress is rejected. Media tests verify UUID filename separation, exact staged bytes, original-source preservation, existing-destination refusal and corrupted-file rejection.

### Next coordination work

The individual reconstruction and staging components must now be assembled into one complete candidate, retaining canonical records/provenance, record identities and numeric aliases. The coordinator must resolve store presence, timezone policy and all supported references before any activation. Only then may it connect to navigation teardown, protected main-workspace switching, reopen verification and retained recovery. Runtime editing must preserve canonical provenance rather than treating a normalized native projection as a complete replacement. The protected main-workspace switch is not yet implemented; no additional manual export test is requested.

## Coordinated candidate and editable Simulator activation

**Supported User Data Model versions:** 1.0 base and working 1.1; frozen native backup formats 1/2.

`PortableWorkspaceCandidate.swift` assembles the complete supported native projection from one reviewed package. It closes the expected export/container shapes, reconstructs all supported stores through the existing adapters, checks native decoding/media references, and privately stages stores, original bytes, canonical package and identity aliases together. It requires an existing current calendar, one live calendar timezone and non-shared live/template ownership; unsupported tombstones or model contexts reject this first importer rather than being silently discarded.

`PortableWorkspaceActivation.swift` routes explicit Simulator-only import through root navigation teardown, pending Board-save flushing and the existing complete dataset recovery journal. The candidate is re-prepared from the frozen package, staged, installed and reloaded before commit. The legacy root currently requires the Simulator timezone to match the imported live-calendar timezone. Active installation replaces managed stores and owned media only inside the protected transaction. Unrelated platform preferences are retained. No source `Preferences.plist` is read from the portable package.

The complete pre-import workspace is retained as `BeforePortableImport`, separately from the earlier native source-recovery test. Undo restores that full snapshot and reloads normal views. Before undo, the imported workspace including any edits is also copied to `PortableImportHistory`; it is not destroyed by successful transaction cleanup. Failed installation/reload invokes the recovery journal before the old navigation tree is shown again. This is not production account binding or synchronization.

### Current export limitation and recovery preservation

Normal editor stores remain the current editable projection. The original portable package and identity map remain immutable import evidence; they must not be exported as though they already include subsequent edits. A fresh portable export after editing therefore stays disabled. Canonical change reconciliation/export remains outstanding, so Step 1 is not complete.

`PortableRuntimeEvidence.swift` preserves the canonical baseline, baseline native stores and identity aliases. Native source backups use format 2 only when this runtime evidence exists; ordinary legacy snapshots remain format 1. Modern readers verify/restore the extra evidence. Legacy capture tooling refuses it rather than stripping the identity context. The old migration-preview path refuses remigration of the normalized imported projection. Local backups retain current saved native edits plus the baseline evidence needed for later reconciliation.

### Automated acceptance

All 79 focused native tests pass. The protected integration test uses an isolated destination containing a different Card title and unrelated document/preference, installs the coordinated portable projection, reads native stores and media, captures/verifies a format-two native backup, restores the full previous workspace with undo, exercises recovery of the imported native backup, and injects an activation failure to prove rollback. The test also verifies retention of post-import history and canonical evidence. All 111 Python tooling tests pass, including refusal to discard portable runtime evidence. No personal Simulator data was installed by these automated tests.

### Owner-operated editable test

1. Rebuild **Plenact Import Test**. Open **Settings → Your data → Local backup** and choose the existing **v12 folder** under **Portable package review**. No new export is required.
2. In **Editable Simulator workspace**, tap **Import into editable Simulator workspace…**, then confirm **Back up and import editable workspace**. This is different from installing the isolated read-only copy.
3. Inspect familiar content in normal Week/Card views, including a saved location, importance, artwork and the drawing attachment. A small edit may be made to exercise the native editor; keep the original package.
4. To return, reopen **Local backup → Editable Simulator workspace → Undo editable workspace import…** and confirm. Verify the original workspace returns.

### Remaining Step 1 work

Canonical reconciliation and fresh portable export after native editing, broader runtime-context support, authenticated account/workspace binding, working Model 1.1 publication and final complete import/export acceptance remain pending. The editable Simulator test is a significant integration checkpoint, not completion of production migration.


## Edited export checkpoint — October 25, 2026

**Supported User Data Model versions:** immutable 1.0 base and working 1.1 composition; synthetic-owner Simulator package format 1.

`PortableEditedExport.swift` consumes a newly captured native backup containing the retained canonical package, numeric alias map and baseline native stores. It reconstructs the baseline independently, compares decoded stores rather than encoded JSON key order, and reconciles only explicitly supported Card fields. Canonical Card/List IDs, collection ownership, ordering, planning, settings, selections, artwork, Assets and untouched payloads remain retained. Unknown/unconverted edits, new/deleted/reordered structure, changed settings, stale duplicate Card copies, changed media, incomplete identity evidence and source review issues stop preparation. Device-only viewport, recents, recent searches, last-viewed and departure state do not become portable records.

The export contains `PortableTestPackage/` with a newly hashed Assembly/Manifest and unchanged original blobs, plus `EditedNativeBackup/` containing the exact current native backup, canonical baseline and alias evidence. History UUIDs and opaque previous/new value bytes survive; wire history timestamps use the established millisecond UTC representation. The native backup retains finer source timestamp precision. The active workspace, its import baseline and pre-import Undo are never changed by export. The complete serialized output is bounded to 256 MB.

The package is reviewed again and projected back into native stores. Every supported user-data value must match the captured current stores (history timestamp comparison uses canonical millisecond precision). This second projection rejects edits that were not fully represented, including inconsistent Board/calendar copies. The first implementation does not allocate new Card/List IDs or silently remap new structure.

The owner-operated import/edit/Undo test succeeded on October 25: the normal editable Card opened, an edit was made, Undo restored the pre-import workspace, and `Gym — Undo Test` with its bookmark, importance, location and dates returned. This is manual recovery evidence, not proof of fresh edited export yet.

Automated edited export coverage uses only synthetic isolated containers: title/description export, exact history UUIDs and value bytes, submillisecond source preservation in the accompanying native backup, null description removal, completion, unchanged output, unsupported insertions, stale duplicate rejection, stable aliases, original-file equality and unchanged import baseline. The affected content/export/backup/recovery suites pass 46 tests. The independent Python schema and relationship validator also accepts the edited canonical assembly; `check_synthetic_assembly.py --edited-package` checks the complete synthetic package, manifest and originals from XCTest attachments.

### Owner test

1. Rebuild **Plenact Import Test** and import the existing v12 folder through **Editable Simulator workspace**.
2. Edit a Card description, leave the Card to finish saving, and open **Settings → Your data → Local backup**.
3. Select **Export supported Card edits to Files…**. Save the resulting folder separately; preserve v12.
4. Share the resulting ZIP for independent review. No additional legacy migration preview/export is needed.

Full editable export still needs adapters for nested content, structural changes, settings/planning/Studio and newly added original files. Verified real ownership, broader destination contexts, working 1.1 publication and final production migration acceptance also remain separate open work. Cloud synchronization stays off.


### Set encoding comparison correction

The first owner-operated edited export surfaced a baseline consistency rejection. Native `Set` properties can serialize in different orders across runs. Edited export now normalizes the reviewed native Set fields (`savedCardIDs`, `dismissedActivityIDs`, and template example-focus markers), and native UUID checklist-link dictionary pairs, before comparison. It preserves duplicates for rejection and retains authored Card/List/artwork ordering. A regression checks reordered sets, changed authored order and duplicate membership. The focused Studio/export/recovery suite passes 14 tests. Unsupported scheduling edits remain blocked separately; this correction does not add scheduling export or modify the owner’s saved workspace.


### Edited scheduling export

Supported versions: Model 1.0 tagged dates inside working 1.1 composition. Edited export now reconciles start/finish dates with their native precision (`date`, `time`, `dateAndTime`), including explicit removal. It reuses the pinned IANA 2025b converter, preserves an existing timed field’s explicit zone or otherwise uses the retained owning calendar zone, and converts the native reference epoch explicitly to Unix epoch. Date-only values remain civil dates; time-only values remain wall-clock times; timed values carry UTC instant, offset and daylight-saving occurrence. Unsupported zones/ranges still fail closed. No scheduling decision or cloud action is executed.

The complete inverse projection still requires the reconstructed native date and its precision to agree with current saved stores. Unsupported structural reorderings remain blocked even when triggered by a time edit; this checkpoint does not silently change Card order. Exact current source precision remains in the accompanying `EditedNativeBackup`.

The focused Studio/export/recovery suite passes 15 tests, including a scheduled edit round trip with stable aliases and UTC/date/time/clear/repeated-hour conversion checks. The complete generated edited package passes independent schema, relationship, manifest and original-file validation. The owner can rebuild and retry Export on the existing imported workspace, without Undo, re-import or another migration preview.


### Structural edit diagnosis

Read-only comparison of the owner’s test Simulator identified one removed Card plus supported title/time/history edits. The app had also introduced its example-location applied flag and recovery backup after import. Those two known recovery values are now retained only in the accompanying exact native backup, not treated as authored portable content or dropped from recovery. Unsupported array structure now raises an explicit structural-change alert instead of the generic unsupported-field message. The synthetic protected import/export/recovery regression passes with recovery values present and verifies structural edits remain blocked. No owner workspace was modified during diagnosis. Card deletion/tombstone and reference reconciliation remains unimplemented; the owner need not repeat this known-blocked test until that adapter is ready.


### Pending local Card deletion export — implemented

Supported versions: 1.0 retained records inside working 1.1 composition, with optional `local_card_deletions`. The exporter compares all retained native content owners before identifying removed Card aliases. Missing Cards become explicit local deletion intents; it does not invent server tombstones or erase their canonical pre-import records. An effective native projection applies those intents before reconciling the remaining text/time/history edits. Every store must still match the final inverse projection; stale Board/calendar copies, unsupported List deletion/additions/moves/reordering and unconverted fields remain blocked.

The deletion UUID stays reserved, while its Card is excluded from editable active/archive rows and bookmarks. Retained importance, canonical references and historical snapshots are preserved without execution; original files remain verified rather than garbage-collected. Re-import and re-export keep the same intent and cannot resurrect the Card. The isolated inspector and review Card counts apply the same overlay. See [Version-1.1.md](Version-1.1.md#pending-local-card-deletion-overlay) for wire semantics and compatibility limits.

Validation: 48 affected native content/export/backup/recovery tests pass; 112 Python tests pass. Both edited and deletion synthetic packages pass independent complete schema, relationship, manifest and original-file validation. Tests include a bookmarked/important Card deletion, retained aliases/files/importance, absent active bookmark, repeated import/export and existing full Undo. All tests use isolated synthetic containers. No personal Simulator data was changed automatically.

The owner can rebuild and retry **Export supported Card edits to Files…** on the existing workspace. No Undo, re-import or new migration preview is required. This checkpoint adds Card deletion, not complete structural editing or production sync readiness.


## Structural editing checkpoint — October 25, 2026

**Supported User Data Model versions:** immutable 1.0 records within working 1.1 composition, including the existing pending-local-deletion overlay. Private alias evidence remains format 1; the UUID-to-number map may include unused reserved identities.

`PortableStructuralEdits.swift` reconstructs owner-qualified native collections from the frozen calendar, personal-collection and template stores. It reconciles collection List order, active/archive Card order and same-owner Card membership against retained canonical UUIDs. Existing records keep their identity and authored payloads; later field reconciliation applies supported text/time/history changes. Calendar/template metadata, historical references, labels, selections, appearance and original files must still agree in the complete inverse projection. Deleted imported Cards retain their prior membership only under the explicit local deletion overlay, never as visible duplicates.

Board-view List/Card creation now calls `PortableCreationIdentity.reserve` before publishing new native items. When a portable runtime exists, it atomically reserves globally unused numeric aliases with persistent UUIDs in `IdentityAliases.json`. A canceled creation leaves reserved gaps; retries and restart do not reuse them. A normal nonportable workspace retains its existing allocator. Batch creation reserves its full title count. Missing/corrupt evidence or failed atomic reservation stops creation instead of publishing an untracked identity. This mutates private identity bookkeeping, not Card/List content or the immutable canonical import baseline.

Export reads those reservations from the frozen backup, creates new canonical List/Card records under their explicit existing collection, and reuses the new UUID across repeated exports. New Card conversion uses the actual item factory’s default checklists, stable native nested UUIDs, explicit label/existing-file references, and retained history. Created-at wire precision is milliseconds; exact native precision remains in the accompanying native backup. Existing source fields and unmapped edits are never discarded merely because a new record was decoded through a native model.

### Current supported boundary

- Creation through the rebuilt Board views, within an existing imported collection/calendar. New Lists may be named before export. Ordinary newly created Cards/Notes and their initial checklists/history are supported.
- Moving existing Cards between Lists within that same collection/Board, with their identity unchanged.
- Reordering existing/new Lists and active/archive Card membership within that owner.
- Existing supported Card edits and pending local deletions remain available.

Cross-collection/Board transfers, new collections/Weeks/templates, List deletion, unsupported creation paths without reserved aliases, newly added media, new comments/members/reactions on created Cards, and edits to existing nested content/settings/planning/artwork still require further adapters. Existing List metadata edits beyond structural membership are still rejected by inverse comparison. A transfer that renumbers a Card is not silently exported as deletion plus unrelated creation; a new record reusing an existing creation timestamp is rejected. This remains complete-snapshot test export, not an incremental synchronization outbox or server acknowledgement mechanism.

### Verification

48 affected native content/export/backup/recovery tests pass, including the actual `KanbanList.makeItem` factory with its default checklists. The combined synthetic test reserves identities, leaves a canceled reservation, creates a List and Card, moves an existing Card, reorders Lists/Cards, exports twice identically, installs into a separate temporary native container and exports again with identical canonical assembly bytes. Original identities/files and full Undo are retained. Normal nonportable allocation and rejection of unreserved new identities are also exercised. All 112 Python tests pass, and structural, edited and deletion artifacts pass independent schema, relationship, manifest and original-file validation.

The prior owner-operated edited export/re-import succeeded: the renamed Card and changed start time appeared correctly and the deleted Card stayed absent. The new structural checkpoint has automated evidence; owner-operated acceptance is still pending.

### Next owner test

Rebuild the existing **Plenact Import Test** Simulator; no Undo or re-import is needed. In **Week**, add a List using **+ Add list**, create a Card in it, and move/reorder an existing Card within the same Board if desired. Use **Export supported Card edits to Files…** and save a new ZIP. Keep this test to those operations so unsupported settings/media or cross-Board changes do not obscure structural acceptance.


## Rich newly created Card export — October 25, 2026

**Supported User Data Model versions:** 1.0 Card/Asset/selection records inside working 1.1 composition; native backup format 2. No published 1.0 schema is changed.

`PortableRichCardExport.swift` adds frozen newly owned originals to the retained package before structural reconciliation. Existing originals must remain present and byte-identical. New Asset UUIDs use an explicit workspace-qualified UUIDv5 name containing source path and SHA-256, so repeated export of the same saved original retains identity. Exact blob bytes, lengths, hashes, source-name metadata, manifest mappings and Asset evidence are updated together. Signature detection is a conservative type hint, not an image-decoder or playback certificate. The package remains synthetic-owned with cloud upload disabled.

The native comparison projection receives explicit safe source-filename overrides for the new files. Normal user import continues to use canonical UUID filenames. This comparison-only mechanism prevents a correct portable Asset remapping from being mistaken for lost native attachment content. Unsafe overrides, collisions, missing originals, changed imported originals and oversized inventories stop preparation. No filename or photo bytes are rewritten in the user's workspace.

Newly created Cards now preserve photo/attachment metadata and cover identity, comments, initial/custom checklists and progress, appearance, completion and edit history through the existing complete Card converter. Native nested UUIDs are seeded in their actual identity families rather than regenerated per export. Personal bookmark/importance state is reconciled from explicit owner-qualified native collections and importance items; new selection UUIDs use the same account-qualified UUIDv5 rule as the original assembler. Existing explicit selection records remain preserved. Legacy missing importance level means one star only within the importance-store comparison, not arbitrary content dictionaries.

Comment/attachment/creation timestamps compare at the established portable millisecond precision; their exact finer native precision remains in `EditedNativeBackup`. Opaque history bytes are unchanged. Native originals and complete edited source stores stay alongside the portable output. Newly created drawing originals still require a role/derivation adapter and are rejected; existing imported drawings remain retained. Cross-Board transfers, global settings/planning/artwork changes and unclassified creation paths remain separate work. This is not full Step 1 completion or synchronization activation.

### Evidence and next owner action

52 affected native tests pass, covering the actual item factory plus a valid new PNG, caption, cover, comment, four checklists/progress, completion, bookmark, legacy one-star importance and history. The new Card survives fresh native installation and another export with identical canonical assembly bytes. Tests also reject modified imported originals and unsafe filename overrides. All 112 Python tests pass. Structural/rich, edited and deletion packages pass independent schemas, relationships, manifests and original-file validation; the rich artifact includes three verified originals rather than its two-original baseline. Tests use synthetic temporary containers, not personal Simulator data.

The supplied owner v2 ZIP was independently confirmed to be a native backup, containing the new Card's photo, comment, four checklists and history, with valid source/media/runtime integrity. Its existing new List/Card aliases were already reserved; no recreation is needed. No personal source content or image was added to repository fixtures. Rebuild **Plenact Import Test**, then choose **Export supported Card edits to Files…** on the current workspace. Do not use **Prepare local backup** as the portable-export action. The saved portable folder should contain `PortableTestPackage` and `EditedNativeBackup`; keep the existing v2 native backup as well.


## Existing Card content reconciliation checkpoint

Supported versions: immutable Model 1.0 records within the working Model 1.1 test package. Already imported Cards now export edits to comments, checklists and progress, assignments, reactions, appearance, attachment metadata and covers, alongside the existing text, scheduling and history support. Reconciliation replaces only changed Card payload fields; untouched canonical fields and retained Card/nested identities remain stable. Checklist links use explicit owner and calendar-week references.

New supported original files are captured and verified. Removing an attachment or clearing nested content remains cleared after re-import. An unreferenced imported original may remain available from the verified canonical package even when its native file was removed; export does not recreate that source file or restore its attachment row. Active media references are independently checked against the frozen backup, and changed original bytes still stop export. Device-local reaction-author preferences remain in the native backup; source reaction author identifiers are preserved without claiming authenticated ownership.

All 52 affected native tests and 112 Python tests pass. The synthetic existing-Card package independently passes schemas, references, manifest and original-file checks. Tests cover stable identities, unchanged canonical fields, repeated export, fresh import/export, clearing nested content and retaining removed originals. The owner-operated rich new-Card export/re-import also succeeded before this checkpoint. No personal content is included in repository fixtures.

Rebuild the existing Import Test Simulator and edit a Card already present in the imported workspace. Change a comment, checklist progress or photo/caption, then use **Export supported Card edits to Files…**. No preliminary Undo, re-import or Card recreation is needed. New drawing derivations, cross-Board transfers, List deletion and broader settings/planning/artwork reconciliation remain outside this checkpoint. Account/workspace binding and full Step 1 acceptance are still pending; cloud synchronization stays off.
