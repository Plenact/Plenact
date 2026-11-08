# Current Step 1 inventory — November 7, 2026

**Current accepted checkpoint: v25. Step 1 beta exit is closed for Step 2 synthetic staging; production migration/synchronization readiness remains open. Cloud synchronization is disabled.** Published Model 1.0 remains immutable; working 1.1 is unpublished. The October audit and dated updates below remain historical evidence; use this current summary together with the latest implementation and acceptance sections.

The [beta closeout](Step-1-Beta-Closeout.md) defines the accepted scope, reviewed inventory, device-only exclusions, evidence and deferred work. Remaining gaps below are recorded limitations rather than an endless prerequisite queue before synthetic staging.

| Area | Current evidence and boundary |
| --- | --- |
| Card content, nested content/media, same-Board structure, Collection/List metadata | Supported within the explicit adapters; owner-accepted checkpoints retained. Cross-Board transfers and arbitrary owner lifecycle changes remain guarded. |
| Preferences, local profile, Studio | Supported adapters with synthetic creation/edit/clearing/media recovery. Owner acceptance covers saved preferences, profile creation and Studio variety; it does not establish every avatar/artwork UI path. |
| Planning/reviews | Review rhythm, daily writing/check-ins, evening reviews, weekly and periodic reviews/objectives now have explicit edited-export evidence, with owner round trips through v13. These earlier audit gaps are no longer wholly pending. |
| Templates | Retained metadata/order/default, capture/duplication, unreferenced removal, Card edits/new items/deletion have bounded adapters and owner evidence through v20. Context/weekday/focus changes, absent-library creation and reference-dependent removals remain separate limits. |
| Template application and rollover | Week addition to a retained Week is accepted in v22. New-Week rollover followed by Week replacement is accepted in v23, including independent originals/recovery validation. Day addition/replacement passes focused synthetic tests and independent validation; Day replacement is owner-accepted in v24. |
| Calendar and structural lifecycle | Changed first-weekday policy, retained day mappings/checklist overrides, cross-Board transfers and List/Week/Collection deletion still need explicit reference-wide reconciliation. A supported path must not be inferred from successful migration alone. |
| Today shortcuts | Creation, order/selection changes and clearing now have a dedicated owner-qualified adapter, including new-Week rollover references. Synthetic and independent package checks pass; shortcut reorder is owner-accepted in v25. |
| Other domains and final gates | Labels and other store edits require a field-level inventory; new drawing derivations remain unsupported. Real account/workspace binding, complete source/export reconciliation, explicit device-only exclusions, compatibility and recovery acceptance remain open. |

The **Day-template replacement into Tuesday of the retained November 2 Week** checkpoint is owner-accepted in v24. Retain v23 as the prior recovery checkpoint; no completed manual tests should be repeated. The new Day tests reuse the application fixture and cover two additive applications or one replacement, retained selection/deletion evidence, archives/undated work, copied links, frozen/native/runtime preservation, fresh import and identical re-export. No production adapter changes were required. Four affected Day/Week tests and 112 tooling tests pass; both Day packages independently validate with two synthetic originals.

---

# Edited portable export inventory — October 26, 2026

**Supported User Data Model versions:** 1.0 base and working 1.1 composition.

Scope: current uncommitted implementation on `feature/ios-local-backup`, following owner acceptance of v8. This is a code/evidence inventory, not a claim that Step 1 is complete. Immutable Model 1.0 and unpublished working 1.1 remain unchanged by this review. Cloud synchronization remains disabled.

Migration/import support does not imply support for later edits. `PortableEditedExport.prepare` reconstructs a candidate, reconciles explicitly supported changes, and compares every retained native store. Remaining differences reject export. Its new-store allowance is limited to recognized personalization stores; a newly saved planning store is not implicitly accepted.

| Domain | Migration / editable reconstruction | Subsequent edited export and evidence |
| --- | --- | --- |
| Existing Card content, nested values, attachment metadata | Implemented | Reconciled with inverse projection; owner-accepted content/media checkpoints through v4 |
| Board-created Cards/Lists; same-owner moves/order | Implemented for retained/imported content | Reserved identities supported; owner-accepted rich structural checkpoint v3 |
| Collection/List metadata and appearance | Implemented | Reconciled; owner-accepted Collection rename v5 |
| Automatic dated Week rollover | Implemented | Explicit bounded adapter; owner-accepted v6 with bookmarks and saved preference |
| Shared app preferences | Implemented | Reconciled; owner-accepted Focus row count and Maps preference v6/v7 |
| Local profile | Implemented | Creation/edits/clearing have synthetic coverage; creation and three fields owner-accepted v8 |
| Studio/artwork/global Week appearance | Implemented | Synthetic creation/edit/clearing/media/order coverage; owner-accepted color-variety toggle v7. New avatar/wallpaper and saved-look owner acceptance remains unestablished |
| Daily plans, check-ins and evening reviews | Implemented by migration/planning adapters | No dedicated post-import planning-record reconciliation; writing/history changes remain a gap |
| Weekly/periodic reviews and objective history | Implemented | No dedicated post-import review reconciliation; saved decisions must remain history and never execute during export |
| Review rhythm | Implemented for invitation/time/notification intent | No dedicated edited-export reconciliation; a bounded first planning-preference adapter is recommended |
| Template definitions/library | Implemented, including order/default and explicit mappings | Generic retained Collection/List/Card reconciliation reaches template-owned content, but does not reconcile template name/kind/anchor/weekday/focus metadata or library order/default/creation/removal. Do not claim complete template-edit support |
| Existing calendar metadata | Implemented | Rollover is bounded; changes to retained Week/day mappings, first-weekday policy and checklist overrides have no general reconciliation adapter |
| Cross-Board movement | Existing ownership imports | Rejected by retained List/Card owner checks |
| Card deletion | Retained records plus working 1.1 local overlay | Supported pending local deletion; owner-accepted earlier checkpoint. No server tombstones/acknowledgements |
| List/Week/Collection removal and arbitrary Collection creation | Existing records import | Retained owner/List membership guards reject unsupported changes; rollover is the explicit new-Week exception |
| New original image files | Verified asset enrichment and placement | Supported in reviewed areas; prior bytes retained; ambiguous basenames rejected. New drawing derivations unsupported |
| Labels, shortcuts and other saved stores | Migration/reconstruction paths exist | No blanket edit support: only explicitly reconciled fields pass; changed stores require separate evidence |
| Account/workspace binding and final source reconciliation | Synthetic owner used for test packages | Real authenticated ownership, complete exclusions/compatibility/recovery acceptance remain Step 1 work |

## Source and test evidence

- `Src/Persistence/PortableEditedExport.swift`: native-store presence gate, explicit device/recovery exclusions, baseline verification, recursive reconciliation, media and final inverse verification.
- `Src/Persistence/PortableStructuralEdits.swift`: owner-qualified content traversal, retained owner checks, bounded rollover, preferences and personalization reconciliation.
- `Src/Persistence/MigrationPlanningPreview.swift` and `MigrationPlanningValues.swift`: initial planning conversion, unknown-field checks, historical reference evidence and no action execution.
- `Src/Persistence/PortableEditablePlanning.swift`: actual reconstruction of daily/weekly/periodic documents and review rhythm.
- `Src/Persistence/MigrationCalendarTemplates.swift` and `PortableEditableCalendar.swift`: calendar/template conversion and reconstruction; these are not edited-export adapters.
- `Test/MigrationPlanningTests.swift`: six migration/reconstruction cases, including absent/empty distinction, historical references and malformed records.
- `Test/MigrationContentTests.swift`: calendar/template mapping and reconstruction cases.
- `Test/MigrationStudioTests.swift`: protected synthetic activation/edit/export/recovery integration, personalization and rollover; this does not establish arbitrary planning edits.

This review did not rerun unchanged suites or repeat owner tests. Retained automated evidence remains 52 affected native and 112 tooling tests; future planning work must include affected planning tests.

## Recommended implementation sequence

1. Add review-rhythm edited export as a separate focused adapter. Preserve the existing singleton identity, allocate deterministic identity only for a genuinely newly saved store, validate all seven fields and ranges, and preserve unchanged canonical values. Recognize only this additional new store. No scheduler or notification API should run during conversion.
2. Verify changed and newly created rhythm stores, absent versus explicit defaults, invalid/unknown fields, unchanged planning history, frozen-source immutability, repeated export, fresh installation and identical re-export. Use isolated synthetic stores and an independent package check before one owner test.
3. Extend daily-plan writing/check-ins next, then weekly/periodic review history. Resolve owner/creation-qualified references, stable identities, null/empty history and deleted targets explicitly; never infer historical values from current Cards or replay review decisions.
4. Reconcile template metadata/order/default selection and remaining calendar changes separately, then ownership-changing transfers and deletion lifecycles. These require reference-wide analysis rather than relaxed comparison guards.

Personal archives and screenshots remain private and are not fixtures. Keep v8 as the current owner checkpoint; no new manual test is needed for this inventory.

## Review-rhythm implementation update

Following this inventory, review-rhythm edited export was implemented and passed 59 affected native tests, 112 tooling tests and independent new/retained-package checks. The review-rhythm row and recommended sequence above describe the pre-implementation audit. See [current checkpoint](Editable-Import.md#review-rhythm-edited-export--october-26-2026) for support and the pending owner test. Daily-plan/review-history edit reconciliation remains pending.


## Daily-plan implementation update

The [daily-plan checkpoint](Editable-Import.md#daily-plan-writing-and-check-in-edited-export--october-26-2026) now supports saved writing, priorities, vision progress, check-ins and new dated plans, with strict provenance and identity/removal boundaries. All 60 affected native and 112 tooling tests and independent package checks pass; owner acceptance remains pending. Evening-review and weekly/periodic review edits, template metadata and remaining calendar/structural gaps are still pending. The audit table above records the earlier pre-implementation state.


## Evening-review implementation update

The [evening-review checkpoint](Editable-Import.md#evening-review-writing-and-history-edited-export--october-26-2026) adds creation, reflection writing, progress/completion, achievements and recorded history. All 62 affected native/112 tooling tests and independent validation pass; manual acceptance remains pending. v10 remains accepted. Weekly/periodic edits, templates and remaining calendar/structural gaps remain follow-up work.


## Weekly-review implementation update

The [weekly checkpoint](Editable-Import.md#weekly-review-writing-and-history-edited-export--october-26-2026) adds writing, priorities, decision history, progress/completion and new reviews to edited export. It retains explicit identity/context/reference boundaries and does not execute actions. All 65 affected native and 112 tooling tests and independent weekly-package checks pass. Manual acceptance remains pending; v11 remains accepted. Periodic reviews, templates and other calendar/structural gaps remain follow-up work.


## Periodic-review implementation update

The [periodic checkpoint](Editable-Import.md#periodic-review-writing-and-objective-edited-export--october-26-2026) adds periodic writing, title/progress/completion, priorities and independent objective snapshots, preserving authored UUIDs for new reviews. All 66 affected native and 112 tooling tests and independent package checks pass. Manual acceptance remains pending; v12 remains accepted. Templates and remaining calendar/structural gaps, ownership and final reconciliation/recovery are still follow-up work.


## Retained-template metadata implementation update

The [template metadata checkpoint](Editable-Import.md#retained-template-metadata-edited-export--october-26-2026) adds retained names, authored library order and default Week selection/clearing. All 67 affected native and 112 tooling tests and independent package checks pass. Manual rename acceptance is pending; v13 remains accepted. Template creation/removal, date/weekday/focus changes and remaining calendar/structural gaps still need separate reconciliation, alongside ownership and final recovery acceptance.


## New-template creation implementation update

The [creation checkpoint](Editable-Import.md#captured-and-duplicated-template-creation-edited-export--october-26-2026) adds Day/Week capture and duplication within an existing retained library, preserving authored template IDs and independent copied content/reference/media identities. Validation passes 68 export/recovery/template checks, two isolated hosted focus checks, 112 tooling tests and independent package checks. Manual acceptance is pending; v14 remains accepted. Retained-template removal/context changes, absent-library creation, unresolved external references, calendar/structural gaps, ownership and final reconciliation/recovery remain follow-up work.


## Template deletion follow-up — October 26, 2026

The [deletion checkpoint](Editable-Import.md#template-deletion-edited-export--october-26-2026) supports unreferenced template removal in complete local snapshots, default clearing and explicit empty libraries. It preserves originals/recovery and rejects surviving references, transferred aliases and pending Card-deletion intersections. Automated export/recovery and independent package checks pass; owner acceptance is pending with v15 retained. Remaining work includes broader calendar operations, cross-Board transfers, List/Week deletion, drawing derivations, real ownership binding and final source/export/recovery reconciliation. Step 1 remains in progress.


## Owner acceptance update — October 26, 2026

Template deletion/export/editable re-import is owner-confirmed in v17. The deleted custom Day template remains absent and neighboring retained templates remain visible. Independent comparison verifies unchanged surviving canonical values and all five originals. This closes the focused manual deletion checkpoint; remaining Step 1 boundaries listed above still apply. See [v17 acceptance](Editable-Import.md#owner-acceptance-template-deletion-v17--october-26-2026).


## Retained template content evidence update — October 26, 2026

Title/details edits to an existing template Card now have explicit isolated round-trip evidence through the existing generic adapter, including authored history, stable identities and unchanged live Week/sibling copies. The new test and independent package validation pass; owner acceptance is pending from v17. This does not establish item creation/deletion or changed weekday/focus mappings. See [the checkpoint](Editable-Import.md#retained-template-card-content-checkpoint--october-26-2026).


## Owner acceptance update: retained template Card v18 — October 26, 2026

The owner confirmed the edited title after editable v18 re-import. Retained-template Card title editing is now owner-accepted; details/history retain synthetic and independent package evidence as documented. v18 is the latest accepted checkpoint. Template item creation/deletion, changed context/mappings and other remaining Step 1 gaps are not implied by this acceptance. See [v18 evidence](Editable-Import.md#owner-acceptance-retained-template-card-v18--october-26-2026).


## Retained template item creation update — October 26, 2026

New Cards/Notes authored in a retained template now receive durable portable aliases and an authored creation instant. The existing structural adapter then preserves their independent ownership and order. Automated cancellation/failure, source/runtime recovery and fresh import/re-export checks pass; 72 native export/recovery/template tests and 112 tooling tests pass, with independent synthetic package validation. Owner acceptance is pending from v18. Item deletion and remaining mapping/calendar/transfer/ownership/reconciliation boundaries remain separate work. See [checkpoint](Editable-Import.md#new-cards-and-notes-inside-retained-templates--october-26-2026).


## Owner acceptance update: new template Card v19 — October 26, 2026

New Card creation inside a retained template is owner-confirmed after editable v19 re-import, with the expected 43-item count and new Monday Card visible. v19 is now the accepted checkpoint; no repeat test is required. New Notes, cancelled reservations and allocation failure retain synthetic evidence. Template item deletion, application behavior and remaining Step 1 gaps are not implied by this acceptance. See [v19 evidence](Editable-Import.md#owner-acceptance-new-template-card-v19--october-26-2026).


## Retained template item deletion evidence update — October 26, 2026

Ordinary template Card deletion now has explicit isolated coverage through the existing working 1.1 local overlay. Canonical Card/List membership remains retained, the editable template omits the target, and fresh import/re-export is stable. Required example-focus references reject deletion. The new native regression, 112 tooling tests and independent synthetic validation pass; focused owner acceptance is pending from v19. Whole-template deletion with pending Card-deletion intent and other remaining structural/ownership/recovery boundaries remain separate work. See [checkpoint](Editable-Import.md#retained-template-item-deletion-checkpoint--october-26-2026).


## Owner acceptance update: template item deletion v20 — October 27, 2026

The v20 template item deletion round trip is owner-confirmed and verified in the saved template library. No repeat test is required. Later live template application changes extend beyond the accepted package and require separate application/export validation; preserve the current workspace for that follow-up. See [acceptance and scope](Editable-Import.md#owner-acceptance-template-item-deletion-v20--october-27-2026). Step 1 remains in progress.


## Additive template application implementation — October 27, 2026

Applying to a retained imported Week now reserves new List/Card aliases at commit, translates copied links/bookmarks/importance and preserves read-only previews. The explicit saved-Week intent false-to-true transition is reconciled separately. Two-addition synthetic round trips, failure guards and independent package validation pass; 74 native/112 tooling checks pass, excluding the two previously isolated keyboard-focus tests from this native run. Focused owner acceptance is pending from v20. Replacement, initially absent/new-Week application, wider calendar operations and remaining transfer/identity/recovery boundaries are not implied. See [checkpoint](Editable-Import.md#additive-template-application-to-retained-weeks--october-27-2026).


## Application importance ordering repair — October 27, 2026

A multi-importance application exposed arbitrary native selection-array order omitted by the initial fixture. The revised test fails before frozen owner-qualified comparison normalization and passes afterward. Duplicates, levels and unknown fields remain retained for rejection checks. All 75 native/112 tooling tests and independent synthetic validation pass; owner export retry is pending on the already applied workspace, without reapplication or Undo. v20 remains accepted. See [the repair checkpoint](Editable-Import.md#applied-template-importance-ordering-repair--october-27-2026).


## Owner acceptance update: additive application v22 — October 27, 2026

Additive application to a retained Week is owner-confirmed after editable v22 re-import. Original Monday items and the copied edited template Card are visible together. v22 is the latest accepted package; no repeat test is needed. Replacement, initially absent/new-Week application, wider calendar operations, cross-owner transfers, drawing derivations, authenticated ownership and final reconciliation/recovery remain separate boundaries. See [v22 evidence](Editable-Import.md#owner-acceptance-additive-template-application-v22--october-27-2026).


## Week-template Replace mode evidence — October 27, 2026

Replace on a retained Week has explicit synthetic recovery coverage: dated items enter the local deletion overlay with old canonical records exact, while archives/undated work remain unchanged and new copies retain independent identities/references. All 76 native/112 tooling checks and independent replacement validation pass. Confirmation wording now describes the selected Day/Week scope accurately. Owner replacement acceptance is pending from v22; Day replacement and initially absent/new-Week application remain unaccepted. See [checkpoint](Editable-Import.md#week-template-replacement-checkpoint--october-27-2026).
