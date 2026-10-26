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
