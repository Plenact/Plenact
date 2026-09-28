# Boards

This directory owns Plenact's implemented kanban Board feature: ordered lists organize work, cards represent activities, and checklist items represent actions.

## Current Files

- [`ContentView.swift`](ContentView.swift): Board screen, board settings, list/card presentation, member management, and list-target navigation from Today.
- [`CardDetailView.swift`](CardDetailView.swift): card details, dates, descriptions, checklists, comments, members, labels, and attachment interactions.
- [`Models.swift`](Models.swift): Codable Board models, local persistence, deterministic sample data, and checklist-item migration.

The filenames reflect the current implementation. `ContentView` is the Board view in code; renaming and splitting it should be a separate, behavior-preserving change.

## Starter Board

When no valid saved Board exists, `SampleData` creates seven ordered lists from Monday through Sunday. Each day contains six realistic planning activities, one divider, one linked-card demonstration, and two Action Detail demonstrations per activity card.

Starter data is a first-launch fallback only. Existing persisted boards are loaded unchanged and are not renamed or replaced when sample content evolves.

## Ownership

The Board is the current source of truth for lists and cards. `AppRootView` in `../../App.swift` owns the shared list snapshot used by Today and Board, while this feature owns Board mutations and card-detail workflows.

Labels and attachments remain sibling features because they have their own models, persistence, and reusable UI:

- [`../Labels/`](../Labels/README.md)
- [`../Attachments/`](../Attachments/README.md)

## Persistence

`KanbanBoardPersistence` stores lists and cards as local JSON under the versioned `Plenact.Board.v1` key. Persisted Codable fields, stable card/list/checklist IDs, and attachment filenames are compatibility contracts.

Revision 0 string checklist items migrate to stable `KanbanChecklistItem` records during decoding. Checklist actions can contain standard text, a stable link to another Board card, or reduced Action Detail content. See [`../../../Doc/Checklist-Actions-Architecture.md`](../../../Doc/Checklist-Actions-Architecture.md) and [`../../../Test/`](../../../Test/README.md).

Do not clear saved data to resolve decoding failures. Add compatibility tests before changing stored models or IDs.

## Product Boundary

The Board is local to this app installation. Members are free-text assignments rather than accounts. The feature does not provide cloud synchronization, shared permissions, calendar synchronization, or a remote database.

## Future Modularization

Keep this directory flat while the files remain easy to scan. Likely future extractions from `ContentView.swift` include:

- `BoardView.swift`
- `BoardSettingsView.swift`
- `KanbanListView.swift`
- `KanbanCardView.swift`

Extract these incrementally with focused tests and builds. Avoid adding `Views/`, `Models/`, or `Components/` subdirectories until the number of files makes those divisions useful.