# Editable application import bridge

**Current implementation status — November 7, 2026:** [Step 1 beta closeout](Step-1-Beta-Closeout.md) is complete for the bounded local beta and handoff to **Step 2 synthetic staging**, with v25 owner-accepted. Deferred operations and production migration/authentication/synchronization gates remain explicit. Cloud synchronization is disabled; Model 1.0 is unchanged and working 1.1 is unpublished. Earlier implementation checkpoints below are historical.

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

Cross-collection/Board transfers, new collections/Weeks/templates, List deletion, unsupported creation paths without reserved aliases, newly added media, new comments/members/reactions on created Cards, and edits to existing nested content/settings/planning/artwork still require further adapters. Existing List metadata reconciliation was added at the later checkpoint below. A transfer that renumbers a Card is not silently exported as deletion plus unrelated creation; a new record reusing an existing creation timestamp is rejected. This remains complete-snapshot test export, not an incremental synchronization outbox or server acknowledgement mechanism.

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


## Existing List metadata reconciliation — October 25, 2026

Supported models: immutable 1.0 List records inside working 1.1 packages. Existing Lists now reconcile title, nullable/empty subtitle, archive flag, new-item presentation default and authored appearance. Changed fields update the retained List record; unchanged payload fields, owner, List identity and Card identities remain preserved. Derived Card List titles are reconstructed from the renamed canonical List. Existing ordering and local deletion-overlay handling remain in effect.

Appearance conversion uses verified canonical Asset references for artwork rather than copying native filenames into the contract. Unsupported references or divergent native Board/calendar copies stop export. Clearing authored subtitle/appearance/default values is represented explicitly and does not revive the original values. Cross-Board transfers, List deletion, new collections/Weeks and global settings/planning edits remain separate work. No released schema changes or cloud ownership claims are introduced.

All 52 affected native tests and 112 Python tests pass, and the synthetic List package passes independent schema/reference/manifest/original validation. The isolated acceptance test changes an existing List, checks metadata and retained Card identities, installs the exported result into a separate native test workspace and verifies identical re-export bytes. It also clears the authored values and checks their absence after reconstruction. Synthetic package evidence is retained for independent schema, relationship, manifest and original-file review.

Owner test: rebuild the current Import Test Simulator, edit an existing List title/subtitle and its appearance or new-item default, then use **Export supported Card edits to Files…** and save a new package. Do not Undo first. For the later re-import check, save and verify the export before using **Undo editable workspace import…**, choose the new package, then import into the editable workspace. The earlier v4 existing-Card manual round trip is confirmed complete; full Step 1 remains unfinished.


### Personal List and Board Collection editor coverage

The Library's **Edit Collection** sheet edits the owning Collection, even when presented as a personal List such as a built-in capture destination. Existing Collection title, description, icon, color, archive flag and Board appearance now reconcile against their retained canonical owner record. A single-list rename also reconciles its internal List and derived Card context. Collection identities and kinds cannot change, and ownership transfers/new Collections remain unsupported.

The 52 affected native tests pass with Collection title, description and Board appearance changes included in the fresh installation/identical re-export test. Independent List package evidence additionally checks its Collection metadata. The owner's earlier Collection rename was blocked before this adapter existed; retain that edit and retry export after rebuilding. No Undo or recreation is required. Cloud synchronization remains off.


## Saved preference edits — October 26, 2026

Supported models: retained Model 1.0 user-preferences record inside working 1.1 packages. Edits to an existing saved planning-preferences store now update its retained canonical record using the reviewed explicit preference field map. Today Focus ordering tokens are translated explicitly and a default List numeric alias must resolve to a retained canonical List. Canonical account/workspace ownership and record identity remain unchanged. Candidate reconstruction and the complete native inverse comparison still reject unknown or divergent stored values, including mismatched embedded profile preferences.

The synthetic acceptance changes content density and Focus row count, reconstructs the settings, installs into an isolated native workspace and checks byte-identical re-export. Profile creation/detail changes, Studio settings/artwork changes, device-only settings and planning/review reconciliation are not claimed by this preference slice. This is an incremental Step 1 checkpoint, not production account binding or cloud synchronization.

Owner test: on the current Import Test workspace, change **Visible rows in Today's Focus** in Plan Settings, tap **Save**, and use **Export supported Card edits to Files…**. Keep the verified v5 package. No Undo is needed before editing/exporting. Do not combine this test with unimplemented Studio or profile-detail edits.


## Automatic Week rollover export — October 26, 2026

Supported models: retained 1.0 calendar/content records in working 1.1 packages. The exporter can add newly dated Weeks created by the normal calendar rollover while retaining the prior Weeks and saved preference edits. It validates dates/day ownership through the existing content/calendar converters, retains the native Collection UUID, and allocates deterministic workspace-qualified portable identities from explicit source identity families and owner scope. Card/List numeric values are not treated as globally unique source identities: newly added Weeks receive separate comparison aliases even when their local numbers overlap older Weeks or each other across types.

Only the frozen comparison candidate is normalized. List/Card alias references, day mappings, bookmarks and owner-qualified importance are translated together. Equivalent legacy palette tokens are compared as RGB and an unset archive flag as false for new Week owners. Exact original native values, runtime baseline and media remain in `EditedNativeBackup`; preparation writes no live workspace or alias store. Repeated export produces identical canonical assembly bytes. Re-import installs globally distinct editor aliases under the usual protected import/Undo coordinator.

The boundary remains explicit: retained Weeks cannot disappear, existing first-weekday policy cannot change, changed cross-Week checklist overrides are rejected, and a non-null default List without owner provenance stops rollover export. Full inverse comparison rejects other unaccounted-for settings, planning or template changes. Cross-Board transfers and List/Week deletion are not enabled by this adapter. No authenticated ownership or server synchronization is established.

All 52 affected native tests pass. The acceptance fixture adds a new Week and Card reusing an older Card number, retains edited Focus preferences, exports twice identically, verifies the source calendar is unchanged, imports into an isolated native workspace and re-exports identical canonical bytes. `RolloverPackage` passes independent schemas, references, manifests and original-file checks. Owner action: rebuild the existing Import Test Simulator and retry **Export supported Card edits to Files…** with the current Week and saved preferences intact. No Undo, re-import or recreation is needed before export.


### Rollover bookmark comparison correction

The owner-operated rollover exposed seven saved Cards in the newly generated Week. The first synthetic rollover fixture had no bookmarks. Its frozen comparison must use the same sorted top-level `Plenact.SavedCardIDs.v1` representation as the candidate; arbitrary Set iteration order is not authored ordering and must not block export. The corrected regression uses seven bookmarked Cards, checks all seven after reconstruction, repeated export and fresh re-import/re-export. Canonical selection identities remain owner-qualified; source bookmark state is not modified. This correction does not relax content, reference or original-file validation.


## Profile and Studio edited export — October 26, 2026

Supported definitions: unchanged Model 1.0 profile/Studio/artwork records inside working Model 1.1 appearance/library composition. The exporter now reconciles profile creation and edits to display name, email, context and avatar choices, retaining the source-created time and record identity. Profile name/email/source identity remain descriptive values; the synthetic account is not authenticated or replaced. Existing profile identity/creation-time changes are rejected. Unchanged profile fields retain their canonical payloads. Recognized legacy avatar palette encodings compare by their RGB values rather than being confused with a different authored color.

Studio support covers view wallpapers, new Card/Note defaults, coordinated color/header variety and palette, global Week appearance, saved-look creation/editing/removal and authored library order. Existing singleton/library/artwork IDs are seeded before invoking the reviewed Studio converter; new library metadata uses deterministic workspace-qualified identities and new artwork retains its authored UUID. Clearing a view, avatar or saved-look library remains cleared after reconstruction. This remains complete-snapshot export, not a server tombstone/outbox implementation.

New avatar and wallpaper originals use the existing verified-media enrichment. Export-only path aliases connect the current native media areas to the already verified Asset identities; ambiguous duplicate basenames are rejected rather than guessed. The frozen backup independently checks active media references, and inverse native reconstruction verifies actual placements and bytes. Normal migration callers use the original journal path; export aliases are opt-in and are not persisted as new identity claims. Removed originals remain retained for recovery.

All 52 affected native tests pass. The combined synthetic case creates a profile with an avatar, changes a photo wallpaper and Studio defaults, adds/reorders a saved look and changes Week defaults. It verifies profile/artwork identity, exact avatar/wallpaper bytes, fresh import and byte-identical re-export. It then edits the existing profile, clears its avatar and Today wallpaper, empties the saved-look library and verifies the cleared values. The subsequent seven-bookmark Week rollover remains valid. Independent schemas/references/manifests/original checks pass for the personalization and rollover artifacts (six original files). All 112 Python tests pass.

Owner test: rebuild the existing Import Test Simulator, save a small profile change and a Studio wallpaper or saved-look change, then export a new package with **Export supported Card edits to Files…**. Keep v6; no Undo is needed before editing/export. Profile controls may also save the shared preferences, which are already supported. New drawing derivations, broader calendar/planning edits, cross-Board transfers and real account/workspace binding remain outside this checkpoint; cloud synchronization remains off.


## Owner acceptance: preferences and Studio variety — October 26, 2026

The owner exported v7 from the existing editable Simulator workspace, then independently validated it against v6 before Undo and re-import. General package schema/reference/manifest/original validation passed. Exactly two canonical values changed: `preferred_maps_app` from `apple` to `google`, and Studio `varies_new_surfaces` from true to false. All five prior originals were byte-preserved; native preferences, media and runtime hashes passed with no native review codes. Content records, two retained Weeks and Today Focus row count remained unchanged.

The owner confirmed successful Undo and editable re-import, with screenshots showing Google Maps selected and Studio “Vary new item colors” off. v7 is the latest owner-accepted checkpoint; retain v6 and recovery history. This accepts shared-preference and Studio variety round trips. It does not establish manual acceptance of profile detail/avatar edits, new wallpaper originals or saved-look edits; those retain synthetic automated coverage. No personal archive, screenshot or extracted content is stored in repository fixtures. Step 1 remains in progress and cloud synchronization remains disabled.


## Owner acceptance: profile creation — October 26, 2026

The owner exported v8 from the accepted v7 workspace after creating a local profile. Independent general package validation passed. Comparison with v7 found exactly one new canonical profile and no other canonical changes. Display name, email and planning context matched the owner-provided evidence; profile source identity matched the record identity and source creation time was retained. All five prior originals were byte-preserved. Native preferences/media/runtime hashes passed with no review codes; prior preferences and Studio settings were unchanged.

After validation, the owner performed editable-workspace Undo and v8 re-import and confirmed success. Screenshots show the restored profile's three fields and creation date, plus successful recovery/import messages. Review shows 285 portable records, 163 nondeleted Cards, 37 Lists and five verified originals; the retained pending-deletion Card remains outside the visible count. The separate isolated inspection copy is not the editable workspace and was not replaced by this operation.

v8 is now the latest owner-accepted checkpoint; retain v7 and earlier recovery checkpoints. This accepts profile creation and field restoration. Existing-profile changes, avatar/new wallpaper originals and saved-look edits retain automated coverage but are not manually established by this test. Step 1 remains in progress; cloud synchronization remains disabled. Personal field values and media remain outside repository fixtures.


## Review-rhythm edited export — October 26, 2026

Supported definitions: unchanged Model 1.0 review-rhythm records in working 1.1 packages. Edited export now reconciles the seven saved invitation/time/weekday/notification-intent fields, including first creation of the recognized native rhythm store. Retained singleton identity is preserved; newly saved stores use deterministic workspace-qualified identities. Unchanged stores retain canonical values. Missing retained stores, unknown/missing fields, wrong types and invalid minute/weekday ranges are rejected. No notification scheduling or review action runs during conversion. Other planning stores are not added to the new-store allowance.

A separate isolated native test covers new/default and retained/edited settings, all seven choices, unchanged daily-plan writing and other canonical data, runtime/source immutability, repeated export, fresh installation and identical re-export. Malformed fields and retained-store removal fail closed. All 59 affected native tests pass, including six planning tests; all 112 tooling tests pass. NewRhythmPackage and RetainedRhythmPackage pass independent schema/reference/manifest/original validation with two synthetic originals each. Personal Simulator acceptance is pending; v8 remains the current owner-accepted checkpoint.

Owner test: rebuild Plenact Import Test, open Settings → Planning rhythm → Review invitations & reminders, change and save one in-app invitation choice, then export v9 using Export supported Card edits to Files…. Keep v8 and do not Undo before editing/exporting. Validate v9 against v8 before Undo and editable re-import. This accepts invitation preferences only; broader planning/review writing and cloud ownership remain pending.


## Daily-plan writing and check-in edited export — October 26, 2026

Supported definitions: unchanged Model 1.0 daily-plan records within working 1.1 packages. Edited export now reconciles saved intentions, constraints, concerns, priorities, updated time, vision progress and check-in snapshots/history, including new dated plans. Existing plan identities and unchanged canonical payload fields are retained; new identities derive deterministically from the retained workspace, saved date and explicit timezone. Removed retained plans and changed retained date/timezone identities fail closed. The native daily store is explicitly recognized; unrelated new planning stores remain unsupported. Evening-review changes are deliberately rejected in this checkpoint, while existing review history is preserved without replaying actions.

The existing strict planning converter accepts an optional export-only reference resolver. Ordinary migration still uses its source journal. Export references require an exact native alias, owner and source-created-time match against declared canonical historical snapshots or verified retained/new Card records. Unknown or ambiguous references are rejected without allocating substitute targets or creating inferred unavailable records. Export-only journals are seeded with daily identities in memory and are never saved into source/runtime evidence.

A separate `MigrationPlanningTests.testDailyPlanEditedExport` exercises rich retained history, changed writing and a new mood/check-in snapshot, a new dated plan, stable unchanged canonical data, clearing, repeated export, frozen defaults/runtime immutability, fresh installation and identical re-export. It rejects unknown fields, owner/numeric/creation mismatches, bad date/timezone/progress, evening-review edits and retained-plan removal. The package fixture begins with resolvable references and exactly representable Card creation seconds; existing migration tests continue to cover unavailable/reused references and fractional precision. No package review gate was relaxed.

All 60 affected native tests and 112 tooling tests pass. Independent `--daily-plan-package` validation checks all schemas/references/manifests, deterministic new identity and authored check-in history. This planning-only synthetic fixture contains zero original files; personal v9 retains five originals. The regression does not schedule notifications, execute review decisions or operate the owner's Simulator.

Owner acceptance is pending: rebuild Plenact Import Test, open Today and tap the date beneath the Today heading to open Today's Plan. Save a small Your intention change, then export v10 through Export supported Card edits to Files…. Keep v9 and do not Undo first. Independently compare v10 with v9 before the later Undo/import and field check. Step 1 continues; cloud synchronization stays disabled.


## Daily-plan timestamp precision correction — October 26, 2026

The owner encountered an edited-export rejection after saving an intention. Private read-only backup inspection confirmed the writing was saved, native hashes/review were valid, and the newly saved plan used ordinary submillisecond `updatedAt` precision. Calendar/template differences were unordered Set encodings, not additional authored changes. No Undo or repeated edit was requested.

The earlier synthetic case used an already-millisecond timestamp and missed this comparison gap. Changing it to a synthetic submillisecond save/check-in timestamp reproduced the same unsupported-export failure. Daily-store comparison now normalizes only declared planning timestamps (`updatedAt`, `savedAt`, `visionCompletedAt`, `completedAt`, `recordedAt`, `sourceCreatedAt`) to integer canonical epoch milliseconds. The opt-in historical resolver compares creation instants at the same wire precision while still requiring exact owner/alias matches and a unique target. Exact source timestamp bits remain in the accompanying native backup; the regression explicitly compares its Preferences.plist bytes against the frozen capture. No live source or runtime values are rewritten.

The corrected full round trip passes with submillisecond plan/check-in values. An additional regression distinguishes same-millisecond representation differences from changed milliseconds, reflection writing/counts and unrelated-store numbers. All 61 affected native tests and 112 tooling tests pass; the updated DailyPlanPackage again passes independent schema/reference/hash validation. Owner retry: rebuild and retry edited export of the already saved intention; retain existing packages/native backup and do not Undo first. Personal portable v10 validation and re-import acceptance remain pending.


## Owner acceptance: daily-plan writing — October 26, 2026

After the timestamp precision correction, the owner exported portable v10. Independent validation against v9 passed schemas, references, manifests and originals. The only canonical addition was a daily plan dated 2026-10-26; the prior daily record and all other canonical data were unchanged. The intention matched owner-provided evidence, the new identity matched the deterministic workspace/date/timezone rule, and the saved timestamp projected correctly to canonical milliseconds. All five originals were byte-preserved. Native preferences/media/runtime hashes passed with no review codes; the exact daily source bytes also matched the earlier independently verified native backup.

The owner then confirmed editable-workspace Undo, v10 package selection and successful editable re-import. Screenshots show the restored intention and saved time in Today's Plan. v10 is the latest owner-accepted checkpoint; retain v9 and earlier recovery packages. This establishes daily-plan creation/writing round-trip acceptance and the real-save precision fix. Check-in history, priority changes and clearing retain synthetic coverage and were not manually exercised by this test. Review-rhythm values were preserved in the verified package; their separate final toggle inspection remains unrecorded. Step 1 continues, with cloud synchronization disabled. Personal writing, screenshots and archives are not repository fixtures.


## Evening-review writing and history edited export — October 26, 2026

Supported definitions: immutable Model 1.0 evening-review objects inside daily-plan records within working 1.1 packages. New/existing reflection writing, step/completion, achievements and recorded decision history now reconcile through the reviewed daily adapter. The former evening-change rejection is removed; strict conversion, owner/alias/creation reference resolution and final inverse verification remain. Recorded actions are data only: export never executes them. Unsupported cross-Board outcomes and weekly/periodic edits remain blocked.

A separate `MigrationPlanningTests.testEveningReviewEditedExport` shares a resolvable portable planning fixture. It covers creation/edits, achievement snapshots, all eight retained action kinds plus a new dated decision, stable IDs/order, submillisecond completion/decision/save times, unchanged other daily fields/native stores, frozen defaults/runtime, exact native-backup preferences, fresh import and identical re-export. Empty and nullable-cleared reviews reconstruct correctly. Invalid progress, unknown nested fields, duplicate decision IDs and invalid dates reject export.

All 62 affected native tests and 112 tooling tests pass. Independent `--evening-review-package` validation checks full schemas/references/manifests, reflections, achievements and action/timestamp history. This synthetic fixture contains zero originals; personal media and archives are not fixtures. v10 remains the latest owner-accepted checkpoint.

Pending owner test: rebuild Plenact Import Test, open Today, tap the date, then Start today's review (moon/stars), or Resume/Revisit today's review if already saved. Daily review opens read-only history and is not the evening editor. Use Save and continue through two steps without applying item decisions. Enter a short What helped? reflection, then Save today's review. Export v11 using Export supported Card edits to Files…; keep v10 and do not Undo first. Independently validate before later Undo/re-import and reflection inspection. Step 1 continues; cloud synchronization remains off.


## Owner acceptance: evening-review writing — October 26, 2026

Portable v11 independently validates against v10: the existing current daily plan changes only constraints, evening review, updated time and vision-completion time. Reflection fields match owner evidence; constraints and vision completion match the frozen native source. Other canonical data and all five originals are unchanged; native preferences/media/runtime hashes pass with no review codes. No item decisions or achievements were added in this personal test.

The owner confirmed successful editable re-import and screenshots show all three restored reflection values and saved completion time. v11 is the latest owner-accepted checkpoint; retain v10 and prior recovery packages. This accepts evening-review reflection writing and completion restoration, not personal decision-action or achievement edits. Those have synthetic coverage. Earlier field-focus failure stopped reproducing after reopening the editor; cause remains unconfirmed, with no product UI fix claimed. Standalone and nested hosted focus/typing tests passed individually on the automated Simulator. Step 1 continues, with cloud synchronization disabled. Personal archives and screenshots remain outside repository fixtures.


## Weekly-review writing and history edited export — October 26, 2026

Supported definitions: unchanged Model 1.0 weekly-review records within working 1.1 packages. The daily/weekly `planningEdits` adapter now reconciles weekly highlights, learning, direction, constraints, risks, priorities, saved decisions, progress and completion. Existing canonical IDs and unchanged payload fields remain retained. Newly saved reviews use deterministic workspace-qualified identities derived from the complete native review key (start date, timezone and first-weekday policy). Removed retained records, changed identity/context, unknown fields and invalid dates/progress remain rejected. Only the explicitly recognized weekly store is added to the native new-store allowance; periodic reviews remain unsupported.

The same explicit owner/alias/source-created resolver applies to priorities and historical decision snapshots. Export does not execute recorded actions; unsupported cross-Board outcomes still fail comparison. Daily and weekly store comparisons use canonical millisecond timestamp precision, retaining exact original native bytes in the accompanying backup. Existing daily/evening logic uses the shared adapter with unchanged identity rules.

`MigrationPlanningTests.testWeeklyReviewEditedExport` covers new and retained reviews, all reflection fields, retained priority/action history plus a new saved decision, submillisecond timestamps, clearing and strict invalid metadata/removal rejection. It verifies retained canonical identity, unchanged other canonical domains and native stores, frozen defaults/runtime, exact native backup preferences, repeated export and fresh import with identical re-export. All 65 affected native tests and 112 tooling tests pass; the native suite also includes both hosted standalone/nested reflection focus tests. Independent `--weekly-review-package` validation verifies complete schemas/references/manifests, writing/history/timestamps and deterministic new identity. This fixture contains zero originals and no personal content.

Owner acceptance remains pending; v11 is the current accepted checkpoint. Focused test: rebuild Plenact Import Test, open Today, tap the date, then Weekly review. On the first step, enter a short Your highlights value and use Save progress near the bottom. Leave item decisions unchanged. Export v12 with Export supported Card edits to Files…; keep v11 and do not Undo first. Validate v12 independently against v11 before the later Undo/import and highlights inspection. Step 1 continues; cloud synchronization remains off.


## Owner acceptance: weekly-review writing — October 26, 2026

Portable v12 independently validates against v11: it adds one completed weekly review for the week starting 2026-10-26 with all five reflection fields matching owner-provided evidence, valid deterministic identity and correct native-to-canonical timestamp projection. The only other canonical difference is the current daily plan's updated time, matching the frozen native source. Daily/evening content, prior records and all five original files are unchanged. Native preferences/media/runtime hashes pass with no review codes. No weekly priorities or item decisions were added in this personal test.

The owner confirmed editable Undo and successful v12 re-import. Screenshots show all five restored weekly fields across steps 3 and 1, and retained daily intention/evening reflections in the weekly summary. Review counts show 288 portable records, 163 nondeleted Cards, 37 Lists and five verified originals. The separate older isolated inspection copy is not the editable workspace. v12 is the latest owner-accepted checkpoint; retain v11 and earlier packages/recovery history. This accepts weekly-review creation/writing and saved completed-review reconstruction. Priorities and decision-history edits retain synthetic coverage, not manual acceptance from this test. Step 1 continues and cloud synchronization remains disabled; personal archives/screenshots/writing remain outside repository fixtures.


## Periodic-review writing and objective edited export — October 26, 2026

Supported definitions: immutable Model 1.0 periodic-review records within working 1.1 packages. The explicit `PlanningFamily` selection extends shared planning reconciliation to periodic titles, reflection writing, progress/completion, priorities and independent starting/current objective snapshots. Retained IDs remain stable. New reviews retain the authored native UUID, matching editable reconstruction; export does not replace it with a derived date identity. Retained date-range/timezone changes and record removal are rejected, while new records require canonical UUID keys, nonempty titles and valid dates/zones/ranges. Only the reviewed periodic store is newly recognized. No account ownership, server revision or deletion metadata is fabricated.

Objective IDs, statuses, progress, next steps and order are preserved separately in starting and current arrays. The adapter never reconstructs starting snapshots from current objectives. Unknown/duplicate objective identities, unsupported statuses/fields and malformed source values fail closed through the reviewed converter and final inverse comparison. Historical priorities use the existing explicit owner/alias/creation resolver. Planning timestamp comparison retains the established wire-millisecond policy while exact source values remain in the native backup.

`MigrationPlanningTests.testPeriodicReviewEditedExport` covers existing title/writing edits, achieved/released objective changes and additions, unchanged starting snapshots, creation with the authored UUID, real-save timestamp precision, clearing, retained canonical identity, unchanged other native/canonical domains, frozen defaults/runtime, exact native backup preferences, repeated export and fresh import with identical re-export. It rejects invalid title/progress/range/context, duplicate objectives, unknown status/fields and retained-record removal. The full suite initially exposed keyboard sequencing in an existing hosted focus test; the harness now dismisses the keyboard before hit-testing the next field. No product focus fix is claimed.

All 66 affected native tests and 112 tooling tests pass. Independent `--periodic-review-package` checks validate complete schemas/references/manifests, reflection writing and objective snapshot identities/statuses/progress. The synthetic fixture contains zero originals; personal archives/media remain private and are not fixtures. v12 remains the owner-accepted checkpoint.

Pending owner test: rebuild Plenact Import Test, open Today, tap the date, then Periodic review. Name a checkpoint, keep a valid date range and use Begin review. Enter a short Highlights and achievements value, use Save and continue to step 2, then add one objective and Save progress. Export v13 through Export supported Card edits to Files…; retain v12 and do not Undo first. Independently validate against v12 before later Undo/import and checking the highlight/objective. Step 1 continues; cloud synchronization remains disabled.


## Owner acceptance: periodic-review writing and objectives — October 26, 2026

Portable v13 independently validates against v12: its only canonical addition is one completed periodic review, with saved title, period, reflection writing and four ordered objectives matching the native source. Objective UUIDs, statuses, progress and next-step values are preserved. Starting objectives are explicitly empty for this first checkpoint; this personal test does not establish inherited starting-snapshot behavior, which retains synthetic coverage. Prior canonical data and all five originals are unchanged; native preferences/media/runtime hashes pass with no review codes.

The owner confirmed editable Undo, package review and successful v13 editable re-import. Screenshots show the restored saved checkpoint, period, direction/risks, objective values/statuses and highlights, with earlier weekly reflections still available. Package review shows 289 records, 163 nondeleted Cards, 37 Lists and five verified originals. The separate older isolated inspection copy was not replaced. v13 is now the latest owner-accepted checkpoint; retain v12 and prior packages/recovery history. No further manual test is required for this checkpoint. Step 1 continues and cloud synchronization remains disabled. Personal writing, screenshots and archives remain outside repository fixtures.


## Retained template metadata edited export — October 26, 2026

Supported definitions: immutable Model 1.0 planning-template/template-library records within working 1.1 packages. Edited export now reconciles retained template names, authored library order and default Week selection (including clearing the default), preserving all template/library and owned-content identities. Content reconciliation runs first; metadata reconciliation then updates only the supported retained name/library fields. New library/template creation, template removal, changed kind, anchor/timezone/first-weekday policy, weekday mappings, example-focus metadata and bundled revision remain outside this adapter. Unsupported source changes still fail the final inverse comparison.

`MigrationStudioTests.testTemplateMetadataEditedExport`, located with calendar/content tests, uses the existing isolated complete-package fixture with two Week templates and one Day template. It checks rename, reversed order, switching the default, clearing it, stable canonical IDs and unchanged other canonical/native domains and owned content. Repeated export, exact native backup preferences, frozen defaults/runtime, fresh installation and identical re-export pass. Unknown template fields, retained-template removal, invalid Day default and changed anchor/timezone/bundled revision reject export. No personal data or live workspace is used.

All 67 affected native tests and 112 tooling tests pass. Independent `--template-metadata-package` validation checks complete schemas/references/manifests/originals and expected retained name/order/default values; the synthetic fixture contains two originals. Personal v13 retains five originals and remains the latest owner-accepted checkpoint.

Pending owner test: rebuild Plenact Import Test, open Settings → Day & Week Templates, choose an existing template's ellipsis menu → Edit template, change only Name and Save. Export v14 with Export supported Card edits to Files…; keep v13 and do not Undo first. Validate v14 independently before later Undo/import and inspection of the renamed template. The focused owner test covers rename only; order/default behavior retains synthetic coverage. Step 1 continues; cloud synchronization remains disabled.


## Template editor presentation correction — October 26, 2026

Owner rename acceptance was blocked when Edit template opened and immediately disappeared. A synthetic hosted library reproduced the disappearance and logged multiple simultaneous sheet-presentation attempts. The library applied task/sheet/dialog modifiers to a multi-section Group inside List; SwiftUI distributed the modifiers to multiple presentation owners, and library loading replaced the initial presenting content.

The library now attaches loading, editor/apply sheets and dialogs to one persistent zero-height presentation row. The row survives the unavailable-to-loaded content transition and does not change template data or storage formats. Library defaults are injectable so the regression uses an isolated synthetic suite. The regression verifies that the editor remains presented across loading, the Name input accepts typing, programmatic dismissal works and saved template bytes remain unchanged without Save.

All 69 selected native checks pass, comprising the affected migration/export/recovery suites and the existing template-screen rendering/no-save check. The retained-template package contract is unchanged. Owner retry: rebuild and reopen the same retained template editor, save the intended name, then export v14. v13 remains the latest accepted checkpoint; no Undo or repeated migration procedure is needed before export.


## Owner acceptance: retained template rename — October 26, 2026

Portable v14 independently validates against v13. Its only canonical change is one retained planning-template name; template/owner IDs, library order/default selection, all prior content and planning values remain unchanged. All five original files are byte-preserved, and native preferences/media/runtime hashes pass with no review codes.

After editable Undo and package review, the owner initially inspected the restored pre-import workspace. Completing the editable import then restored the renamed template, confirmed by the owner's success report and screenshot of its Name field. v14 is the latest owner-accepted checkpoint; retain v13 and prior recovery packages. The editor presentation fix also allowed the rename to be saved and exported. This manual test accepts retained-template rename; library ordering/default changes retain synthetic coverage. Step 1 remains in progress, cloud synchronization stays disabled, and personal archives/screenshots are not fixtures.


## Captured and duplicated template creation edited export — October 26, 2026

Supported definitions: unchanged Model 1.0 planning-template/content records within working 1.1 packages. Edited export now accepts newly captured Day/Week templates and duplicates within an existing retained template library. Authored template UUIDs are retained. Independent template-owner UUIDs and owner-qualified List/Card/nested identities derive deterministically from the retained workspace and explicit source identity. This separates a template copy from the live Week or retained template even when capture/duplicate retains their Collection UUID and local List/Card numbers.

The existing reviewed content/calendar-template converter processes each new owner in isolation with verified labels/originals. Unknown or unresolved references fail closed. Only frozen comparison stores receive translated Collection/numeric/nested identities, same-owner checklist references, cover attachment IDs, weekday maps and example-focus aliases. Opaque edit-history bytes remain unchanged. Omitted empty archive fields remain omitted. Live stores, original files, runtime evidence and migration journals are not rewritten by preparation. The new canonical library membership is then reconstructed before existing structural/metadata reconciliation.

`MigrationStudioTests.testNewTemplateEditedExport` uses real capture plus duplicate operations against isolated imported data. It covers Week and Day capture, duplication with reused owner UUIDs, deliberate List/Card-number overlap, copied checklists, a same-owner link to another copied Card, a new verified photo/cover/caption, example focus and selecting the new Week as default. It checks authored template IDs, independent owners/nested IDs, retained content, exact native backup preferences, defaults/runtime immutability, repeated export, a fresh installation with independently allocated aliases and identical canonical re-export. Unknown fields and removal of a newly retained template reject export.

Validation: 68 export/recovery/template checks pass, plus the two existing hosted focus checks in a separate run; all 112 tooling tests pass. The initial combined run exited unexpectedly in the existing nested keyboard test and was stopped after runner restart/finalization stalled; no product cause or fix is claimed for that incident. Separate runs and the final linked-copy regression passed. Independent `--new-template-package` validation checks complete schemas/references/manifests, independent owner identities, copied content/default/focus and three synthetic originals. Personal v14 retains five originals and remains the latest owner-accepted checkpoint.

Limits remain: removal of retained templates, changed retained date/kind/weekday/focus policy, creation of an initially absent library store, ambiguous nested identities, unresolved external references and new drawing derivations are not enabled. This is complete-snapshot local export, not a server creation/deletion protocol or authenticated ownership claim.

Pending owner test: rebuild Plenact Import Test, open Settings → Day & Week Templates, scroll to Source day / week and choose Save week as template. Give the new template a distinct Name and Save without changing its content. Export v15 using Export supported Card edits to Files…; keep v14 and do not Undo first. Independently validate before later editable Undo/import and checking the new template. Step 1 continues; cloud synchronization remains disabled.


## Owner acceptance: captured Day-template creation — October 26, 2026

Portable v15 independently validates against v14: it adds one authored Day template, one independent Collection, one List and four owned Cards. All retained records are unchanged. The authored template UUID matches the native source; the new owner identity follows the deterministic workspace/template rule. Library membership appends the new template while retaining its identity, prior order and default Week. All five originals are byte-preserved, and native preferences/media/runtime hashes pass with no review codes.

After editable Undo, the owner completed v15 editable import and confirmed success. The screenshot shows the new Day template with four items in the library. This establishes captured Day-template creation and library/count restoration; the screenshot does not independently establish every internal Card field or template application behavior. Week capture, duplication, copied links/nested content and photo/cover behavior retain synthetic coverage. v15 is the latest owner-accepted checkpoint; retain v14 and earlier recovery packages. No repeat test is required for this checkpoint. Step 1 continues with cloud synchronization disabled, and personal archives/screenshots remain outside repository fixtures.


## Template deletion edited export — October 26, 2026

Edited export now supports deletion from an existing template library as a complete local snapshot operation. It removes the template and its exclusively owned Collection, Lists, Cards and content selections. Deleting the default Week clears that default; deleting every template retains an explicit empty library. This does not add server tombstones or change published Model 1.0. Prior packages and exact native/runtime recovery evidence retain the earlier state. Verified originals remain preserved even when a removed template was their last user.

The adapter runs after rollover and before new-template conversion. It blocks surviving canonical references into the removed owner/content/nested identities, reuse of removed numeric aliases in surviving native owners, and intersecting pending Card-deletion intent. Newly captured templates are qualified separately because capture can legitimately borrow source numbers. Unknown source changes still encounter the final inverse projection checks. Missing-library creation, changed retained template context, cross-Board transfer and new drawing derivations remain unsupported. A reference cleared concurrently can still require a separate checkpoint rather than rewriting historical records.

`MigrationStudioTests.testTemplateDeletionEditedExport` covers default deletion, deleting all templates, unchanged live Week values and original media, exact native backup preferences, source/runtime immutability, repeated export and fresh import with identical canonical re-export. A current bundled revision proves loading the explicit empty library does not resurrect deleted templates. Negative checks cover a surviving typed reference, pending Card deletion and a transferred Card alias. The creation regression also deletes a newly retained rich template, preserving its original image file.

Validation: 69 export/recovery/template checks pass; 112 tooling tests pass. The two previously isolated keyboard-focus tests were excluded from this export run and were not repeated. Independent `--deleted-template-package` validation passes complete schema/reference/manifest/original checks with an empty template library, retained live content and two synthetic originals. Personal v15 has five originals and remains the accepted owner checkpoint.

Pending focused owner test: rebuild Plenact Import Test, open Settings → Day & Week Templates, find the custom Day template created in v15, and use its … menu → Delete template. Delete only that custom template, then export using Export supported Card edits to Files… as v16. Do not Undo first. Independently verify the archive against v15 before editable Undo/import and checking that the template stays absent while retained templates and the current Week remain available. Step 1 continues; cloud synchronization is disabled.


## Template deletion confirmation repair — October 26, 2026

Personal v16 passes general package integrity and native preferences/media/runtime hash validation, with all five originals preserved, but is canonically identical to v15. The custom Day template remains in both its native backup and the saved Simulator library. It is not deletion acceptance. The owner reports tapping Delete template merely dismissed the menu without showing confirmation.

A hosted isolated test reproduced the missing confirmation while it was attached to the invisible trailing presentation row. The confirmation now belongs to the visible template row, qualified by template identity. Editor/apply sheets retain their existing stable presentation anchor. The regression fails before the move and passes afterward, checking the confirmation title/destructive action and unchanged saved bytes before confirmation and after dismissal. Three affected hosted/export tests pass, including editor stability and template deletion recovery. No Simulator data was changed by these tests. Pending owner retry: rebuild, delete the custom template, confirm the second dialog, verify its row disappears and export v17 before any Undo. v15 remains the accepted checkpoint; retain v16 as well.


## Owner export verification: template deletion v17 — October 26, 2026

The owner screenshots confirm that the repaired deletion dialog appears and the custom Day-template row disappears after confirmation. Independent general validation of personal v17 against accepted v15 passes schemas, references, manifests and originals. Exactly one Day template, one exclusively owned Collection, one List and four Cards are removed. Every surviving canonical value is unchanged, including library order/default, Weeks, earlier planning/reviews, profile, Studio and preferences. The package retains 164 Card records, 37 Lists and 11 Collections; the existing pending-deletion Card remains retained as before.

All five original files are byte-preserved. Exact native preferences, media and runtime hashes pass with no review codes; native template membership matches the portable library. Cloud upload remains disabled and ownership remains unverified. v16 was valid but unchanged from v15; retain it and earlier recovery packages. v17 is independently verified for the intended deletion, with editable Undo/re-import acceptance still pending. No personal archives or extracted records were added to repository fixtures.


## Owner acceptance: template deletion v17 — October 26, 2026

After independent v17 validation, the owner completed editable Undo, reviewed the package, confirmed editable import and reported success. Screenshots show the successful editable import and the template library with the deleted custom Day template absent while neighboring retained templates remain. This accepts the focused deletion/export/re-import checkpoint. The screenshots do not independently establish every retained template field or current Week contents; their unchanged canonical values were verified in the private package comparison.

v17 is the latest owner-accepted checkpoint. Keep v15, v16 and earlier recovery packages. No repeat manual deletion test is needed. Step 1 remains in progress; cloud synchronization is disabled and working Model 1.1 remains unpublished. Personal archives and screenshots remain outside repository fixtures.


## Retained template Card content checkpoint — October 26, 2026

The existing generic content adapter was verified explicitly for title/details changes inside a retained template. No production exporter change was needed. `MigrationStudioTests.testRetainedTemplateContentEditedExport` uses the checked template store save path and imported owner-qualified aliases. It checks that only the intended Card title, description and authored edit history change; every other canonical field remains equal, aside from the established explicit empty local-deletion overlay. Retained template/owner/Card identities, sibling template copies, live Week content, library metadata/default and originals remain unchanged.

The isolated test verifies exact native backup preferences, source/defaults/runtime immutability, repeat export, fresh import and identical canonical re-export. History UUIDs and opaque changes are preserved; new native history timestamps compare within the canonical millisecond precision. The new test passes. All 112 tooling tests pass, and independent `--retained-template-content-package` validation passes with two synthetic originals and an edited template owner separate from the retained live Week. Earlier native suite results are retained; no new full-suite count is claimed.

Pending owner test from accepted v17: edit one existing Card title inside the retained custom Week template, return to its template editor and Save, then export v18 without Undo. Keep template name, dates, membership and default unchanged. Independently compare v18 with v17 before editable Undo/import and checking the edited title. This checkpoint does not establish template item addition/deletion or changed weekday/focus mappings. Step 1 remains in progress; synchronization remains disabled.


## Owner export verification: retained template Card v18 — October 26, 2026

Independent general package validation of personal v18 against accepted v17 passes schemas, references, manifests and originals. Exactly one retained template Card changes, with only its intended title and edit history differing. All prior history entries remain exact and two new entries are retained. Template/Card/owner identities, live Weeks, sibling templates, library/default and all other canonical values remain unchanged.

All five original files are byte-preserved. Exact native preferences/media/runtime hashes pass with no review codes, and the native template source contains the intended edited title. Cloud upload remains disabled and ownership unverified. v18 is independently verified for the intended edit; editable Undo/re-import acceptance remains pending. v17 remains the accepted checkpoint. Personal archives and screenshots remain outside repository fixtures.


## Owner acceptance: retained template Card v18 — October 26, 2026

Following independent v18 validation, the owner completed editable Undo, package review and editable re-import. Screenshots show successful activation and the intended edited Monday Card title in the retained Week-template editor. This accepts the focused retained-template Card title/export/re-import checkpoint. The private package comparison separately verified unchanged live Weeks, sibling templates, library/default, all other canonical values and all five originals, with valid native recovery hashes.

v18 is the latest owner-accepted checkpoint. Keep v17, v18 and prior recovery packages; no repeat manual test is required. This does not establish template item addition/deletion, application behavior or changed weekday/focus mappings. Step 1 remains in progress; synchronization is disabled and working Model 1.1 remains unpublished. Personal archives/screenshots remain outside repository fixtures.


## New Cards and Notes inside retained templates — October 26, 2026

The template editor now reserves new item identities through `PortableCreationIdentity` and records an authored creation instant. Previously its template-local maximum could overlap imported owners and the new Card had no creation timestamp, so generic structural export correctly rejected it. `PlanningTemplateItemCreation.append` is shared by the real editor and isolated tests. Portable reservations are durable before append; cancelling a draft leaves its unused reservation consumed. Ordinary nonportable libraries retain local numbering. Failure shows an error on the visible Add item control and leaves the draft unchanged. No live Week is edited by creating template content.

The existing structural exporter accepts these reserved new Cards/Notes within retained template owners; no schema relaxation or additional exporter creation heuristic is introduced. Relative schedule policy, retained weekday/focus mappings, missing-library creation and cross-owner transfer boundaries remain unchanged. This checkpoint does not establish List creation/deletion or template Card deletion.

`MigrationStudioTests.testRetainedTemplateItemCreationEditedExport`, in `Test/TemplateEditedExportTests.swift`, uses the production allocator and checked library save. It verifies a cancelled reservation is not reused or exported, Card/Note identities are distinct from all imported aliases, new authored creation values are present, and exactly two new Card records plus the intended List membership are added. Existing content, live Weeks, sibling templates and library metadata remain unchanged. It checks original preservation, exact native backup preferences, frozen source/runtime immutability, repeated export, fresh import/identical re-export and a malformed-runtime failure leaving the draft unchanged. The test file is registered in the existing Xcode test target; the shared synthetic retained-template fixture is internal for reuse.

Validation passes 72 affected native export/recovery/template checks and all 112 tooling tests. The two previously isolated keyboard-focus tests were excluded from this export run. Independent `--template-item-creation-package` validation passes full contract/schema/reference/manifest/original checks, new item membership/order, Note presentation and separate template ownership, with two synthetic originals. v18 remains the latest owner-accepted checkpoint and has five originals.

Pending one focused owner test: rebuild Plenact Import Test, open the retained custom Week template, use Monday's Add item → Card, open the appended item and give it a distinct Title, return to Edit template and Save. Export v19 without Undo. Verify independently against v18 before editable Undo/import and checking the added Card remains in the template. Keep prior packages and recovery history. Step 1 continues; cloud synchronization remains disabled.


## Owner export verification: new template Card v19 — October 26, 2026

Independent general validation of personal v19 against accepted v18 passes schemas, references, manifests and originals. Exactly one authored Card is appended to Monday in the retained Week template. Its durable portable identity matches the native Card alias retained in runtime evidence, and its native/canonical creation time is present. All retained Cards, template metadata, live Weeks, planning, preferences and other canonical values remain unchanged; only the owning List's membership extends by the new Card.

All five original files are byte-preserved. Native preferences/media/runtime hashes pass with no review codes. The package retains 165 Card records, 37 Lists and 11 Collections, including the existing pending-deletion Card record. Cloud upload remains disabled and ownership unverified. v19 is independently verified for the intended addition; editable Undo/re-import acceptance remains pending, with v18 still accepted. Personal archives/screenshots remain outside repository fixtures.


## Owner acceptance: new template Card v19 — October 26, 2026

Following independent v19 validation, the owner reports successful editable re-import. Screenshots show package review, the retained Week template with its count increased from 42 to 43, and the new Card restored under Monday alongside the previously edited title. This accepts the focused new template Card creation/export/re-import checkpoint. The private package comparison separately verifies durable identity, the single intended membership addition, unchanged retained canonical values and all five originals, with valid native recovery hashes.

v19 is the latest owner-accepted checkpoint. Retain v18, v19 and earlier recovery packages; no repeat test is needed. New Note creation and cancellation/failure boundaries retain synthetic coverage. This acceptance does not establish template item deletion, application behavior, new Lists or changed weekday/focus mappings. Step 1 remains in progress; cloud synchronization is disabled and working Model 1.1 remains unpublished. Personal archives/screenshots remain outside repository fixtures.


## Retained template item deletion checkpoint — October 26, 2026

The existing generic local Card-deletion overlay now has explicit retained-template item coverage. No production exporter/editor change was needed. Deleting an ordinary item from a retained template keeps its canonical Card and original List membership intact while adding its UUID to working 1.1 `local_card_deletions`. Reconstruction omits the item from the editable template. This differs from whole-template snapshot removal: it does not remove the underlying record or introduce a server tombstone. Original files, prior packages and exact native/runtime backup evidence remain retained.

`MigrationStudioTests.testRetainedTemplateItemDeletionEditedExport` removes an item through the same library mutation and checked save used by the editor. It verifies the entire canonical assembly is unchanged except the one deletion-overlay UUID, preserving live Weeks, sibling templates, library/default and authored content/history. It checks source/runtime immutability, exact native backup preferences, repeated export, fresh import with the item absent and identical canonical re-export. A separate baseline with example focus on the target confirms export rejects deletion when unchanged retained focus metadata still requires that Card; source/runtime evidence remains unchanged on failure. Other retained references are preserved through canonical record retention, not silently rewritten or discarded.

The new isolated native regression passes, all 112 tooling tests pass, and independent `--template-item-deletion-package` validation passes schemas/references/manifests/originals plus retained template ownership/membership under the local overlay (two synthetic originals). The earlier 72-test native run remains the broader baseline; it was not repeated for this test-only checkpoint. Whole-template removal intersecting pending Card-deletion intent still rejects export as previously documented. No universal template deletion/application support is claimed.

Pending focused owner test from accepted v19: open the retained custom Week template, remove only the newly added Monday Card using the item editor's Edit/delete controls, and Save the template. Export v20 before any Undo. Independently verify v20 against v19, expecting unchanged canonical base content plus one additional local-deletion UUID and all five original files preserved. Only afterward perform editable Undo/import and verify the item remains absent while the earlier edited title remains. No rebuild is needed for this unchanged production path. Step 1 continues; synchronization is disabled.


## Owner export verification: template item deletion v20 — October 27, 2026

Independent general validation of personal v20 against accepted v19 passes schemas, references, manifests and originals. Exactly the intended template Card UUID is added to `local_card_deletions`; the prior deletion remains retained. The complete canonical base is unchanged, including all 165 Card records, template metadata, List membership, live Weeks, planning and preferences. Two local deletion UUIDs are now retained. The native template source omits the intended Card while keeping the earlier edited title.

All five originals are byte-preserved. Native preferences/media/runtime hashes pass with no review codes. Cloud upload remains disabled and ownership unverified. v20 is independently verified for the intended deletion; editable Undo/re-import acceptance is pending, and v19 remains the accepted checkpoint. Personal archives/screenshots remain outside repository fixtures.


## Owner acceptance: template item deletion v20 — October 27, 2026

The owner reports successful editable v20 re-import, with screenshots showing the import confirmation. Read-only inspection of the current app container's saved template library independently confirms the intended deleted item remains absent and the earlier edited title remains. The saved per-List Card counts match the native v20 backup; raw counts include template dividers. This accepts the focused template item deletion/export/re-import checkpoint. v20 is the latest accepted package; retain v19, v20 and earlier recovery packages. No repeat deletion test is needed.

The screenshots additionally show template preview/application and a populated live Week. Read-only inspection confirms more active Week entries are saved than in the exported v20 backup. Those later live changes are outside the verified v20 package; no claim is made that template application/export has passed. Preserve the current workspace and recovery history for diagnosis/validation before any further Undo or replacement. Personal archives, screenshots and extracted records remain outside repository fixtures. Step 1 continues, with synchronization disabled and working Model 1.1 unpublished.


## Additive template application to retained Weeks — October 27, 2026

Applying a template previously allocated fresh numbers only within the target Week. Those numbers could collide with other portable owners and were not reserved in runtime evidence. `PortableTemplateApplication.reserve` now runs at the existing checked Apply/save boundary for retained imported Weeks. Preview/Refresh remain read-only and allocate no durable identities. The helper reserves a single range for newly copied Lists/Cards, translates their explicit copied Card links, bookmark sets, day mappings and example importance markers, and preserves the exact preview's nested UUIDs, created dates and authored values. Existing item aliases and opaque history bytes are not rewritten. Failed save attempts can consume unused reservations; they do not mutate the retained Week through this helper.

The Apply view keeps its existing baseline checks and checked save callbacks, passing the remapped Week and importance set only after reservation succeeds. Reservation failure leaves the preview open with an error. Ordinary nonportable previews and the existing initially absent/new-Week path keep their prior behavior; this checkpoint does not establish new-Week application support. Additive application to retained Weeks is the tested boundary. Replacement, broad calendar context changes, cross-owner transfers, new drawing derivations and other unsupported paths are not implied.

The real apply operation also sets `explicitlySaved` on the retained Week. Export now reconciles only the one-way false-to-true transition for the same retained owner/Week key; clearing that intent still rejects export. Unknown or other changed calendar fields continue through final inverse verification. No immutable schema was changed.

`MigrationStudioTests.testTemplateApplicationEditedExport` applies a synthetic template twice in Add mode using real application, the production commit helper, calendar save and importance-selection functions. It checks distinct reserved identities, copied local links, independently fresh checklist UUIDs preserved across commit, bookmarks/importance, source template/library and retained Card preservation, and the one-way saved-Week flag. It verifies exact native backup preferences, frozen source/runtime immutability, repeated export, fresh import and identical canonical re-export. Negative cases reject clearing saved intent and malformed runtime reservation without changing saved calendar bytes. This test uses isolated stores/containers; it does not claim to exercise the full UI save transaction.

Validation passes 74 affected native export/recovery/template checks and 112 tooling tests. The two previously isolated keyboard-focus tests were excluded from this export run. Independent `--template-application-package` validation passes schemas/references/manifests/originals and checks copied links, independent nested identities, bookmarks/importance and saved-Week intent, with two synthetic originals.

Read-only inspection after the owner's return to v20 shows the same aggregate active Week and source-template entry counts as v20; no additional application count increase is present at that inspection. Pending focused owner test: rebuild Plenact Import Test, preview the retained custom Week template for the current Week, explicitly choose Add to existing, Apply exactly once and export v21 without Undo. Independently verify against v20 before later editable Undo/import and checking the copied Week content. Preserve v20 and recovery history. Step 1 remains in progress, synchronization stays disabled and working Model 1.1 remains unpublished.


## Applied-template importance ordering repair — October 27, 2026

The owner's first application export attempt stopped with the unsupported-change alert. Read-only inspection of the current app container found exactly 49 added active Week entries, all with reserved numeric aliases; no retained Week Cards changed and no active media references were missing. Seven new importance selections were saved in nonascending Set-iteration order. Template example-focus differences were only Set ordering. No source stores or originals were changed during this inspection.

The initial application fixture exercised one important item per application and missed within-application ordering. The revised fixture marks both copied items important and persists their selections in descending order. It reproduces the same unsupported export failure before the fix. `PortableEditedExport.nativeJSON` now normalizes only the frozen `Plenact.LibraryImportant.v1` comparison by owner-qualified Card identity, alongside its existing implicit-level normalization. It preserves all entries, levels and unknown fields; live selection storage and runtime evidence are not reordered. Existing structural duplicate/level guards and final inverse verification remain active.

`testImportanceComparisonKeepsIdentityAndUnknownValues` verifies order-independent comparison without collapsing duplicate identities or dropping unknown values. The revised real application round trip verifies copied links, bookmarks and multiple importance markers through repeat export, fresh import and identical re-export. All 75 affected native tests, 112 tooling tests and independent application-package validation pass (two synthetic originals). The two previously isolated keyboard-focus checks were excluded from this native run.

The owner's current application remains saved and has not been independently exported yet. Pending retry: rebuild Plenact Import Test and run Export supported Card edits to Files… again as v21. Do not apply the template again and do not Undo. Independently verify the resulting archive against accepted v20 before re-import. No personal records, media or archives were added to fixtures. Step 1 remains in progress; synchronization is off.


## Owner export verification: additive template application v22 — October 27, 2026

Independent general validation of personal v22 against accepted v20 passes schemas, references, manifests and originals. It adds exactly 49 independent copied Card records across the seven current-Week Lists, plus fourteen new selections: seven bookmarked targets and seven important targets. All retained Card records and selection records remain exact. No Lists, templates, owners or originals are created/removed; only the seven destination List memberships extend. All other canonical base values and both prior local deletion UUIDs remain unchanged.

Private comparison maps the active source template's authored item order to the newly reserved aliases per weekday. Source records hidden by the local-deletion overlay are excluded, so the previously deleted template item is not copied. Source titles/kinds match, copied checklist/item UUIDs are fresh, and copied attachments preserve their original asset references and metadata. Local copied links are checked when present; explicit link remapping also retains synthetic coverage. Bookmarks/importance map to the expected new targets with deterministic selection identities. Native copied titles and numeric aliases match the canonical additions.

All five original files are byte-preserved. Native preferences/media/runtime hashes pass with no review codes. This confirms the saved application now exports after the frozen importance-order repair. Cloud upload remains disabled and ownership unverified. v22 is independently verified for one additive application; editable Undo/re-import acceptance remains pending, with v20 still the accepted package. No reapplication is needed. Personal archives/screenshots/records remain outside repository fixtures.


## Owner acceptance: additive template application v22 — October 27, 2026

After independent v22 verification, the owner completed editable Undo, package review and editable re-import. Screenshots show 353 reviewed records, 212 nondeleted Cards, 37 Lists and five verified originals, followed by successful activation. The Monday Week view shows original scheduled items alongside the copied template content; the opened copied Card shows the intended edited title, importance display and visible artwork/gallery. This accepts the focused additive retained-Week template application/export/re-import checkpoint. Screenshots do not independently establish every copied field, all seven days or every original file; the private package comparison and synthetic tests supply their separately documented evidence.

v22 is the latest owner-accepted checkpoint. Keep v20, v22 and earlier recovery packages; no repeat application test is required. The package retains 214 canonical Card records, with two prior local deletions explaining the 212 nondeleted review count. Replacement and initially absent/new-Week application remain outside this acceptance, alongside the other remaining Step 1 calendar, transfer, drawing, ownership and final reconciliation/recovery boundaries. Synchronization stays disabled and working Model 1.1 remains unpublished. Personal archives/screenshots remain outside repository fixtures.


## Week-template replacement checkpoint — October 27, 2026

Replace mode now has explicit end-to-end synthetic evidence through the existing application, commit-time reservation and local Card-deletion overlay. No new exporter heuristic was needed. Replaced active dated Cards remain exact canonical records with their original content/history and selection evidence, while their IDs enter the local deletion overlay. New copies have independent reserved identities. Archives and undated Lists remain in the native Week. This is local complete-snapshot/recovery behavior, not a server tombstone protocol.

`testTemplateReplacementEditedExport` shares the production application fixture with the additive regression, avoiding duplicated test plumbing. The replacement baseline contains active work on Monday and Tuesday, an archived Card, undated work, and existing bookmarks/importance. Importance is established after owner-qualified import and re-imported as the retained baseline; ambiguous legacy capture-owner references are not guessed and no migration guards are relaxed. The test verifies exactly the replaced dated IDs enter the overlay, every old canonical Card stays exact, archives/undated work remain exact in the reconstructed native Week, new linked Cards/bookmarks/importance remain independent, and fresh import/identical re-export succeeds. Native backup preferences, originals and frozen source/runtime evidence remain preserved.

Validation passes 76 affected native export/recovery/template checks, 112 tooling tests and independent `--template-replacement-package` contract validation with two synthetic originals. The two previously isolated keyboard-focus checks were excluded from this native run. The replacement confirmation text now distinguishes Week-wide dated-List replacement from Day-only replacement; the existing template-screen render check passes after that wording change.

Pending focused owner test from accepted v22: rebuild, preview the retained custom Week template for the current Week, select Replace, Apply and confirm Replace with that template. This intentionally replaces active dated items in the editable Week; v22 preserves the prior accepted state. Apply once, then export v23 before Undo. Independently verify prior canonical records/deletion intent, new copies, originals and native recovery evidence before editable re-import. Keep v22 and earlier recovery packages. This checkpoint does not establish Day replacement, initially absent/new-Week application, cross-Board transfers or final Step 1 reconciliation. Cloud synchronization remains disabled and working Model 1.1 remains unpublished.


## Resume: preserve the newer Week before replacement — November 7, 2026

Repository inspection found a clean `feature/ios-local-backup` checkout at `e7b5fe8` before these resume notes. v22 remains the latest owner-accepted package. No v23 archive was present in the known Files storage at inspection.

Read-only inspection located the app data container by bundle metadata after Simulator-service discovery reported a shutdown device. The saved calendar now retains Weeks beginning October 19, October 26 and November 2, with November 2 selected as current. It has 133 active entries across retained Weeks, compared with 105 in v22. Against the retained runtime native baseline, both earlier Weeks remain unchanged after normalizing known Set encodings. Changed baseline stores are limited to Board, calendar, importance and top-level bookmarks. This is consistent with a new 28-entry Week; the corresponding portable rollover has not yet been independently reviewed.

The documented validation requirements were restored into `/private/tmp/plenact-review-2026-11-07-venv` because the earlier temporary environment had lost its configuration/dependencies. All 112 tooling tests pass in the restored environment. A recreated private read-only reviewer revalidated v22's portable schemas/references/manifests/originals and native preferences/media/runtime hashes. v22 still retains 214 canonical Cards, 37 Lists, two Weeks and five originals. No native suite or completed owner round trip was repeated, and no personal data was added to fixtures.

The immediate next action supersedes the older v23 replacement instruction: launch Plenact Import Test and export the current saved workspace as v23 before any Replace or Undo. Independently compare that export with v22 to preserve and verify the newer Week. Then choose the replacement target using the verified current state and use the next archive version for the replacement checkpoint. No extra migration-preview or backup procedure is requested. Step 1 remains in progress; synchronization is disabled and working Model 1.1 remains unpublished.


## Resume steering and Simulator disruption — November 7, 2026

The owner explicitly identified the generated beta state as disposable and chose to skip the additional preservation export. The next artifact is therefore v23 for Replace on the retained Week beginning November 2, with v22 retained. This supersedes the extra pre-replacement export proposed in the preceding resume note. No additional backup/migration-preview procedure is required.

During the manual preview/Replace attempt, Xcode reported its LLDB RPC server had exited and Simulator showed the device as unavailable. Read-only diagnostics found simultaneous SIGBUS/KERN_MEMORY_ERROR reports for SpringBoard, DTServiceHub, gamed, chronod and liveactivitiesd. No Plenact crash report was found in the inspected report locations. The iOS 27.2 runtime became installed during this session; a causal connection to the failures is not established. These observations indicate a Simulator/tooling disruption rather than establishing an application defect.

The existing Plenact Import Test device remains available under iOS 27.0 and is shut down. Saved active entry counts remain 28 for October 19, 77 for October 26 and 28 for November 2; the replacement has not persisted. Earlier Weeks match the retained runtime baseline after known Set normalization. Inspection changed no application data, imports or recovery history.

The next recovery action is user-operated: dismiss the debugger alert, quit/reopen Xcode and Simulator, select the existing Plenact Import Test device and run Plenact. Resume the pending Replace test once the app opens normally; do not repeat application if a successful replacement is subsequently saved. No Simulator erasure, cache removal, restore or code change was performed. v22 remains accepted and v23 replacement acceptance is pending.


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
