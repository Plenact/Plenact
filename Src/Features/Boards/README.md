This directory owns Plenact's implemented kanban Board feature: ordered lists organize work, cards represent activities, and checklist items represent actions

## Current Files

- [`ContentView.swift`](ContentView.swift): Board screen, board settings, list/card presentation, member management, and list-target navigation from Today
- [`CardDetailView.swift`](CardDetailView.swift): card details, dates, descriptions, checklists, comments, members, labels, and attachment interactions
- [`Models.swift`](Models.swift): Codable Board models, local persistence, deterministic sample data, and checklist-item migration

The filenames reflect the current implementation. `ContentView` is the Board view in code; renaming and splitting it should be a separate, behavior-preserving change

## Starter Board

When no valid saved Board exists, `SampleData` creates seven ordered lists from Monday through Sunday. Each day contains six realistic planning activities, one divider, one linked-card demonstration, and two Action Detail demonstrations per activity card

Starter data is a first-launch fallback only. Existing persisted boards are loaded unchanged and are not renamed or replaced when sample content evolves

## Ownership

The Board is the current source of truth for lists and cards. `AppRootView` in `../../App.swift` owns the shared list snapshot used by Today and Board, while this feature owns Board mutations and card-detail workflows

Labels and attachments remain sibling features because they have their own models, persistence, and reusable UI:

- [`../Labels/`](../Labels/README.md)
- [`../Attachments/`](../Attachments/README.md)

## Persistence

`KanbanBoardPersistence` stores lists and cards as local JSON under the versioned `Plenact.Board.v1` key. Persisted Codable fields, stable card/list/checklist IDs, and attachment filenames are compatibility contracts

The app loads its initial Board with `loadListsInBackground` and submits edits with `saveListsInBackground`. JSON encoding/decoding and UserDefaults access run on a serial background queue, preserving save order without blocking UI animation. Board value models conform to `Sendable` for safe snapshot transfer. A shared busy banner is shown on the app shell, focused Today list, Board/card editing sheets, and Account & Settings. Local persistence errors remain visible until dismissed; stored data is not deleted on a decoding failure. The synchronous helpers remain available for non-UI use.

Revision 0 string checklist items migrate to stable `KanbanChecklistItem` records during decoding. Checklist actions can contain standard text, a stable link to another Board card, or reduced Action Detail content. See [`../../../Doc/Checklist-Actions-Architecture.md`](../../../Doc/Checklist-Actions-Architecture.md) and [`../../../Test/`](../../../Test/README.md)

Do not clear saved data to resolve decoding failures. Add compatibility tests before changing stored models or IDs

## Archived Cards

List Actions includes **View Archived Cards** above **Archive completed cards**. Archiving completed cards moves their complete records into the list's local `archivedCards` collection, retaining IDs, completion state, checklist content, and attachments. Restore returns a card to the end of its original list without unchecking it. Archived cards do not appear in active Board/Today/search results; new card IDs and attachment cleanup include them.

The card detail screen's upper-right **Card actions** menu also includes **Archive Card**, for both completed and incomplete cards. It saves current detail edits, moves the card into its list's archive, and closes the detail screen. This works from the Week board, personal collections, and the focused Today list. Section dividers cannot be individually archived.

Card rows also offer **Archive Card** above **Delete Card** in their `...` menu, both on Board lists and in **Open today's list**. Row archiving uses the same saved archive without opening card details or changing completion status. Existing delete confirmation, rename, and card-info actions remain available.

Older saved lists default to an empty archive, and empty archives are omitted from JSON to preserve the existing remote payload shape. Nonempty local archives are rejected by shared-Board validation because the remote schema does not support them. Copying a list copies only its active cards. Cards removed by the previous archive implementation cannot be recovered.

## Adding Cards

**List Actions → Add card** closes the actions sheet before presenting the new-card form for that same list. The form's Add action creates the card; Cancel leaves the list unchanged. The direct **+ Add card** row uses the same form.

## Reordering Lists

Touch and hold a list's title/header text for about half a second, then drag horizontally to reorder it. The held list lifts visually and gives selection feedback. Holding within the left or right edge of the board viewport moves it one position in that direction every 550 ms and scrolls it into view, allowing a restored list to travel across the entire board. Release to finish; the existing Board persistence path saves the updated order.

Only the title area starts a list drag; card-reordering controls and list action buttons retain their existing behavior. Ordinary swipes before the hold threshold still scroll the board. Reduce Motion disables the lift scaling and reorder animations. **List Actions → Move list → Move earlier / Move later** remains available, with equivalent VoiceOver actions on the title. The same behavior applies to Week and personal boards.

## Archived Lists and Boards

The board's **Board options** (`...`) menu provides **Board Settings**, **View Archived Lists**, and **Archive Board** (for the Week Board and personal boards). List archiving sets a backward-compatible `isArchived` marker on the original list rather than deleting it. **View Archived Lists** restores lists to the end of their original board, preserving list/card IDs, archived cards, completion, and attachments. Archived lists are hidden from Today, active searches, card counts, and navigation choices. New IDs and attachment cleanup still account for archived content. Existing snapshots without the marker remain active; archived lists cannot be published through the current remote schema.

**Archive Board** asks for confirmation and keeps the complete local board, including archived lists/cards and bookmarks. Archived boards are hidden from Lists and shown in **Saved → Archived Boards** with Restore actions. Restoration returns a personal board to Lists with a unique title, without changing its contents. Archived Week Boards restore as separate personal boards named **Week Board (Restored)**, **Week Board (Restored) (2)**, etc.; the current Week Board is never replaced. Archiving the Week Board leaves an empty Week workspace for new lists. Archived boards retain attachment files.

Personal-board archiving persists the complete updated collection snapshot before changing the in-memory archive flag or dismissing the board. If encoding fails, the board remains open and active, the previous stored snapshot is unchanged, and an error banner is shown.

The app root shares the personal-collection state between Lists and Saved and persists the complete Week snapshot, including archived lists. Archive flags and content are stored together, so active-only views cannot overwrite the archives. Loading Example replaces active and archived Week lists together; Undo Last Load restores both.

## Product Boundary

The Board is local to this app installation. Members are currently free-text assignments rather than accounts. A future registered-user directory and typed card-assignment model are described in [`../../../Doc/Users/README.md`](../../../Doc/Users/README.md); they are not implemented. The feature does not provide cloud synchronization, shared permissions, calendar synchronization, or a remote database

## Future Modularization

Keep this directory flat while the files remain easy to scan. Likely future extractions from `ContentView.swift` include:

- `BoardView.swift`
- `BoardSettingsView.swift`
- `KanbanListView.swift`
- `KanbanCardView.swift`

Extract these incrementally with focused tests and builds. Avoid adding `Views/`, `Models/`, or `Components/` subdirectories until the number of files makes those divisions useful