# User data storage inventory

**Supported User Data Model versions:** Version 0 reference; Version 1.0 final mapping.
**Status:** Source-based inventory, October 24, 2026. The final field map is [Source-Coverage.json](Source-Coverage.json); runtime adapters remain unimplemented.

| Domain | Current source/store | Version 1.0 treatment |
| --- | --- | --- |
| Active Board | `Src/Persistence/BoardPersistence.swift`; `Plenact.Board.v1` | Determine whether it is a projection of a calendar week; never import the same Cards twice. |
| Calendar and dated weeks | `Src/Features/Calendar/CalendarStore.swift`; `Plenact.CalendarWeeks.v1` | Synchronize dated content, stable identity, List membership and ordering. |
| Personal Boards and Lists | `Src/Persistence/CollectionPersistence.swift`; `Plenact.PersonalCollections.v1` | Synchronize collections and content, including archives. |
| Card/Note content | `Src/Models/KanbanCard.swift`, `KanbanList.swift`, related models | Titles, subtitles, description, completion, dates/kinds, location, checklists, comments, assignees, labels, sections, reactions, appearance, lock state, and history require explicit field mappings. |
| Reusable labels | `Src/Features/Labels/LabelModels.swift`; `Plenact.LabelLibrary.v1` | Synchronize stable label/category identities and references. |
| Bookmarks | `Src/Persistence/BookmarkStore.swift`; `Plenact.SavedCardIDs.v1` | Per-user synchronized references; legacy integers must gain an unambiguous owner mapping. |
| Importance | `Src/Features/Importance/ImportanceStore.swift`; `Plenact.LibraryImportant.v1` | Per-user levels 0–5 with stable content references; preserve incremental UI semantics. |
| Templates | `Src/Features/Planning/PlanningTemplates.swift`; `Plenact.PlanningTemplates.v1` | Synchronize user templates; distinguish bundled example revision from user edits. |
| Daily plans and reviews | `TodayPlan.swift`, `TodayReview.swift`, `PeriodicReview.swift`; `Plenact.DailyPlans.v1`, `Plenact.WeeklyReviews.v1`, `Plenact.PeriodicReviews.v1` | Private synchronized planning/reflection records with canonical source references. |
| Profile and planning preferences | `LocalProfileStore.swift`; `Plenact.LocalProfile.v1`, `Plenact.PlanPreferences.v1` | User preferences synchronize by default; represent platform/device overrides explicitly. Remote account identity is separate. |
| Appearance and artwork | `AppearanceModels.swift`, `StudioModels.swift`; Week appearance, Studio settings/artwork stores | Synchronize portable materials and asset references; upload owned media separately. |
| Review cadence and shortcuts | `ReviewRhythm.swift`, `TodayShortcuts.swift` | Separate shared preferences from device notification scheduling and local dismissal state. |
| Attachments, covers, avatar, imported artwork | App-managed files plus Codable metadata | Portable asset IDs, authorized upload/download, digest and missing-file states; filenames alone are not cloud assets. |
| Recent history and navigation | `RecentHistory.swift`, `WorkspaceNavigation.swift` | Treat saved user preference choices as shared by default; classify transient recents/navigation separately during the field audit. Cross-device recents remain undecided. |
| Recovery, example backups and migration markers | `ReviewTransactions.swift`, `ExampleUndoStore.swift`, `ExampleCardLocations.swift` | Keep device-local; preserve recovery before migration. Never upload recovery journals as user records. |
| Credentials and provider secrets | Keychain and private server configuration | Device/server-local secrets; exclude from workspace export and synchronization. |

## Audit required before freezing the model

For every Codable field, record wire name, type, required/optional/default behavior, legacy decoding, owner, privacy scope, validation, merge/delete behavior, and fixture coverage. Inventory all persisted preferences and files, including keys not listed above. This table groups stores; it is not a claim that all fields or assets have already been audited.

Legacy integer Card/List IDs are not globally unique across collections, weeks, templates, or devices. Resolve owner-qualified identity and linked references before assigning transport UUIDs. Saved projections must not create duplicate canonical records.

## Post-definition native migration state

`Library/Application Support/PlenactMigration/source-identities-v1.json` is private migration/recovery machinery, not a canonical user-data record. Native backups preserve it and previews include the updated journal. The frozen 96-type definition audit remains historical; see [new source identities and lifecycle](iOS-Migration-Identity.md).
