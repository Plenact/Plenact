# Native Board, List and Card migration preview

**Supported User Data Model versions:** 1.0. Private journal formats 1/2/3; preview/source-backup format 1.
**Status:** Working-branch content converters with synthetic schema/semantic verification. Full workspace conversion, verified cloud ownership and synchronization remain pending.

## Try the expanded preview

In **Plenact Import Test**, build/run the current source, then open Today → Settings → Your data → Local backup. Prepare a fresh local backup of the test Simulator's currently saved data. Select **Central — America/Chicago** as the original timezone, then prepare the migration preview. Justin confirmed Central time for the supplied backup; the app still requires that explicit selection per export instead of assuming the device's current zone.

Save the backup/preview folder to Files. It retains `Preferences.plist`, original media and native integrity evidence alongside canonical `MigrationPreview/Records`, `ContentGraph.json`, `SourcePrecision.json`, the coverage report and updated identity journal. A content blocker is shown in plain language; machine details remain in the report. An unresolved source is not quietly omitted from a successful complete-workspace claim.

The preview converts the currently prepared source snapshot. The earlier Simulator source restore is a separate local recovery path; it does not itself produce Model 1.0 data. A full `workspace-export` is still not emitted by this slice.

## Converted content

| Domain | Mapped values |
| --- | --- |
| Collections | Title, List/Board kind, icon, RGB/legacy color provenance, description, archive state, appearance and authored List order. Computed preferred-focus behavior is not invented as a saved override. |
| Lists | Title, null/empty subtitle, archive flag, explicit new-item presentation override, appearance, ordered active and archived Card memberships. |
| Cards/Notes/dividers | Writing, presentation/display format, completion/lock, location, dates/kinds, due-date visibility, original creation time, checklists, assignees, labels, comments/reactions, media metadata/cover/caption, dismissed activity IDs, appearance, section order/visibility and history. |
| Nested action content | Standard, linked Card, Action Detail and web link; inactive retained values; identical active/retained mirrors; source-attribution text and nullable authenticated authorship. |
| History | Original encoded old/new value bytes remain tagged base64, with null versus empty Data preserved; no import-generated user history. |

Canonical records contain every required payload field. Original preference bytes and original media remain the recovery evidence. Finer-than-millisecond timestamps are recorded in `SourcePrecision.json`, rather than silently discarded while declaring conversion complete. Empty reactions/appearance objects are recovered from raw source when compatible native constructors would normalize them away.

## Ownership and projection rules

The active Board is a projection of the declared current calendar Week. Both native equality and stored-value comparison (normalizing only actual set order) must agree before deduplicating it. Divergence blocks the entire content slice for review. A bare legacy Board without owner/calendar metadata also requires review; the converter does not invent a Board title/color/owner to fill missing source context.

Week/personal Collection identities use their original UUID. Template-owned Collection snapshots additionally qualify their identity by the Template UUID: different templates can legally retain the same legacy Collection UUID and must become independent owners. Current List/Card identities are qualified under that stable original owner; Card creation provenance is included when known. Owned nested values are remapped within the original Card scope. Title, array index and an unqualified Card integer are not cross-owner identity keys.

Links resolve only under explicit source ownership. Self-links inside a template resolve to that template's independent content. Ambiguous external owner links become explicit unavailable targets; they are not assigned to whichever matching numeric ID appears first. Duplicate current owner/List/Card identities and duplicate owned nested values block conversion. Identical retained detail mirrors reuse their canonical values rather than being counted twice.

## Unresolved references and remaining work

Saved labels are converted by the existing metadata adapter without replacement by defaults. When content exists and `Plenact.LabelLibrary.v1` is absent, the native app itself uses `LabelLibrary.starter.includingDayAreas`. The preview now explicitly snapshots that application fallback into `ApplicationDefaultLabels.json` and reports `label_catalog_origin: application_default_catalog`. This is current-build fallback evidence, not proof of a historically saved or customized catalog. The original Preferences bytes remain unchanged. The same source label IDs retain their journal mappings; previously unresolved built-in targets resolve to actual label records. Unknown custom label IDs still become `unavailable_reference` records. A present but malformed saved catalog fails instead of invoking the fallback. Supplementing a present custom catalog with runtime-added built-ins remains future work. Original attachment/drawing/surface file references receive file-qualified IDs using preserved hashes where available, but remain explicit pending Asset targets until the owned-Asset/account adapter exists. This does not claim the original bytes were missing or uploaded. Bundled illustration tokens remain tokens.

The coverage report therefore includes unavailable-reference records. Its `source_content_summary` separates live Weeks, personal collections and template owners, with active/archive counts. It marks the standalone Board content store converted when reconciliation succeeds. Calendar, personal collection and template stores remain listed as partially converted because their Week/template metadata, selections or other workspace-level relationships still need adapters. Complete conversion stays false and cloud linking stays false.

Unknown source fields, divergent retained mirrors, unsupported rich-text attributes, unsupported dates/URLs and invalid identities are blocked. Malformed rich-text prefixes remain literal text. Missing checklist storage that would trigger native sample generation, and legacy manual-assignee strings that would allocate random native IDs, require explicit future handling. These cases do not fabricate content or reset the journal.

## Dates and private journal compatibility

Pinned IANA 2025b data supports America/Chicago and UTC (including known GMT/UTC aliases), for source instants from 1900-01-01T00:00:00Z through the end of 2100. Other zones/ranges block this first converter. Date-only/time-only/full timestamp intent stays distinct. Full values retain local components, zone/rules version, exact selected occurrence, saved offset and millisecond UTC instant. The implementation does not relabel installed OS timezone rules as a different release. See [pinned-data provenance](IANA-Migration-Rules.md).

Private journal format 2 adds owned nested identity kinds. Format 1 mappings load intact, upgrade without replacing existing UUIDs, and cannot be downgraded over a newer journal. This is not a Model 1.0 wire-version change. Older journal readers must block unsupported formats instead of resetting them. Local source restore accepts both supported journal versions.

## Verification

Forty-three focused native tests pass: thirteen content/selection tests, fifteen identity/metadata tests, seven source-backup tests, six restore tests and two existing dataset-recovery regressions. The content fixture includes all six bundled template variants and complex synthetic source fields. Actual emitted canonical records and graph are independently checked against the published schemas/semantic rules; the full fixture emitted 172 records. Native fold/spring-transition examples pass the same reference date checks. Seventy-one Python model/tooling tests pass, including projection-data offsets and graph/reference rejection cases.

An early test failed on legacy color representation, then its assertion incorrectly indexed missing output and crashed the synthetic test host. Both were corrected: legacy palette tokens map explicitly to RGB plus provenance, and failed output assertions stop safely. No personal backup was imported during those tests. The successful source restore/undo acceptance from the prior milestone remains separate from this new content-preview acceptance.

Next: owner-driven fresh preview inspection, then the remaining calendar/planning/review, profile/preferences, selection and owned-Asset adapters; verified account/workspace binding; complete-export comparison; and full migration/recovery acceptance. Passing this content slice does not complete Step 1 or enable Steps 2–4.


## Labels and personal selection preparation

`SelectionPreview.json` is a **local review artifact**, format 1 targeting User Data Model 1.0; it is not a canonical `content_selection` document. Its `account_binding_pending` remains true and it has no account ID. Canonical selections require authenticated account ownership, which this migration preview cannot yet establish. Selection records are therefore not included in the canonical record count or declared fully converted stores.

Each prepared entry carries original Collection ID, original owner namespace, numeric Card ID, resolved canonical Card ID when known, bookmark state and importance. Collection `savedCardIDs` include retained/archived targets. `Plenact.SavedCardIDs.v1` is reconciled only against the current Week: disagreement or missing owner context is an explicit review issue, never a union across Weeks. Owner-qualified `Plenact.LibraryImportant.v1` entries merge into the same Card selection. Missing legacy levels mean one star; explicit zero is retained. Duplicate, malformed or out-of-range levels require review rather than being clamped. Unknown or ambiguous targets remain explicit evidence; copied template Collection IDs cannot spread one importance entry across multiple owners. Invalid or ambiguous importance remains null/unknown in affected bookmark drafts rather than being mislabeled zero. Original source stores remain preserved and listed pending until canonical account-bound conversion is accepted.

The UI shows prepared personal-selection and review-item counts. The report includes `selection_preview_entry_count`, `selection_preview_issues`, `selection_account_binding_pending`, `label_catalog_origin` and `unresolved_label_reference_count`. Native tests cover original-byte preservation, stable retry IDs, known/unknown labels, bookmarked importance, legacy one-star values, orphan targets, projection conflicts, invalid levels and ambiguous copied owners. Actual native output with the default catalog emitted 179 synthetic canonical records plus one separately prepared bookmarked three-star selection; independent checks validate both artifacts. No personal source backup was converted or restored by these automated tests.

Manual acceptance: rebuild **Plenact Import Test**, prepare a fresh local backup, confirm Central time, prepare the preview, inspect the selection/review counts, and export under a new name. Compare the exported label targets and personal selections with the source snapshot. Keep earlier backups. Complete workspace conversion, account binding and cloud synchronization remain pending.


## Calendar and template metadata update

The current content slice now includes `calendar_week`, `calendar_index`, `planning_template` and `template_library`. The UI separates their count as **Calendar and template records**. Saved cross-Week checklist overrides are respected in both Card links and the calendar index. See [current metadata mapping and verification](iOS-Calendar-Template-Migration.md). The current focused suite passes 47 native tests and 74 model/tooling checks; earlier counts above describe earlier content/selection checkpoints. Complete workspace conversion remains pending.


### Verified original-file and Asset preparation update

Supported User Data Model versions: 1.0. Native preview now emits account-unbound `AssetPreview.json`, linking attachment/background references and all preserved originals to stable media identities with verified size/checksum, explicit missing-file review and drawing derivation. Canonical account-owned Assets and cloud transfers remain pending. See [file verification and manual test](iOS-Asset-Migration.md). The current focused suites pass 51 native tests and 77 model/tooling checks; earlier counts describe prior checkpoints.


### Profile/preferences and Today shortcut checkpoint

Supported User Data Model versions: 1.0. Native previews now prepare local profile/effective preference drafts with explicit source/default provenance and avatar links, and convert saved Today shortcuts using exact owner-qualified membership/order. Account-required profile/preferences remain unbound; Studio and other appearance/planning/review adapters remain pending. See [current settings mapping and acceptance](iOS-Settings-Migration.md). Current focused checks pass 56 native tests and 80 model/tooling tests.


### Studio and remaining appearance preparation

Supported User Data Model versions: 1.0. Previews now convert saved artwork payloads and prepare Studio/global Week appearance with exact surface/file references. Global Week defaults and multi-artwork ordering lack complete canonical destinations in the immutable released contract; they are retained in local evidence with explicit mapping-review notices, not silently merged or dropped. See [Studio mapping, representation gaps and acceptance](iOS-Studio-Migration.md). Current focused checks pass 60 native tests and 83 model/tooling tests. These representation gaps, account binding, daily plans/reviews and complete workspace recovery remain pending.


### Daily plans, check-ins and review history checkpoint

Supported User Data Model versions: 1.0. Native previews now convert daily plans, weekly/periodic reviews and reminder intent while retaining historical writing/progress, exact source-creation references and nullable history. Missing/deleted targets stay explicit; review decisions and notifications are never executed. See [planning mapping and acceptance](iOS-Planning-Review-Migration.md). Current focused coverage passes 65 native tests and 86 model/tooling checks. Appearance representation gaps, verified ownership and complete portable recovery remain pending.


### Additive appearance representation update

The global Week/theme and artwork-order gaps described at earlier checkpoints now have working Model 1.1 records, emitted separately from base records. See [versioned representation and compatibility](Version-1.1.md). Publication, ownership binding and complete workspace recovery remain pending.
