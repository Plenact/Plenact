# Plenact Application Architecture

**Status:** Today and Board navigation are implemented. This document records the current architecture and proposed follow-up work.

## Product Intent

Plenact helps a person plan a day, capture tasks and ideas, and organize work over time. The launch experience should orient the person to today's plan while keeping the full board and its lists one clear action away.

The originating workflow is a weekly kanban board: one list per day, ordered cards for that day's routine and work, divider cards between parts of the day, and a separate open-work list. Today makes this existing list-based method easier to enter; it does not replace it with a separate focus-task system. Plenact is not a treatment product, and this design makes no clinical or regulatory claims.

## Current Foundation

- `App.swift` installs a tab root with Today and Board destinations. Today can select a board list for the current date or browse all lists; opening a list switches to Board and targets its stable ID.
- `Src/Features/Profile/` provides the local Today avatar, Account & Settings, personalization, and profile persistence without online authentication.
- `Src/Features/Boards/ContentView.swift` implements the Board destination and owns board interactions, label state, and navigation to card details. Board lists are shared with the root view and persisted through the existing local store.
- `Src/Features/Boards/Models.swift` defines Codable lists, cards, checklists, comments, and board persistence. Cards have stable IDs, list membership, optional start and due dates, and a title-completion flag.
- The board is stored as a JSON snapshot in local `UserDefaults`; the label library is also local. Photo files live in the app's private Documents directory, with attachment metadata on cards.
- There is no implemented calendar integration, standalone notes feature, online account system, team sync, or remote database.
- The supplied Trello screenshot and JSON export illustrate the user's planning method. They are reference material, not data currently imported by Plenact. New installations receive Monday-through-Sunday starter lists, but `KanbanList` still has no structured weekday or date property.

These existing persistence formats are user-data contracts. New work should preserve them or include a deliberate, tested migration. Do not silently replace unreadable saved data with sample content or delete attachment files as a migration shortcut.

## Proposed App Shape

Keep the existing SwiftUI app and add navigation incrementally:

```text
PlenactApp
└── AppRootView
    ├── TodayView                 implemented launch view
    ├── BoardView                 current kanban experience (`ContentView` in code)
    └── ScheduledView             proposed agenda projection (not implemented)
```

Today and Board are implemented as complementary ways into the existing planning data. Today stores the selected list ID under a date-specific local preference key and provides a picker for every board list. Scheduled remains a documented direction, not an app destination yet. Add Projects, Notes, or Team navigation only when those destinations have real data and workflows; do not ship navigation to placeholders.

### Responsibilities

**Presentation:** SwiftUI views render state and send explicit user actions. Today presents the selected day list and direct links into all board lists. Board remains the place to browse and organize lists and cards. Scheduled presents an ordered agenda projection without creating duplicate tasks.

**Application state:** Introduce a small observable planner store when extracting state from `ContentView` becomes necessary. It should coordinate board mutations, Today preferences, and persistence. Keep it focused on app state; do not add a networking or generic repository framework before there is a concrete need.

**Domain:** Continue using `KanbanList` and `KanbanCard` as the source of truth for board tasks. Today and Scheduled should project those records, not create second copies. Use each list's stable `id` for navigation; do not deep-link by list title or array index.

**Persistence:** Initially reuse the local board and label stores. Store Today preferences locally. Evaluate a more suitable on-device store only with a documented migration plan and round-trip tests for existing board data and attachment references. No cloud storage or synchronization is part of this proposal.

## Today and Schedule Data Boundaries

Today should orient around the list used for the current day. Because the current model has no day/date assignment and list titles are user-editable, do not silently guess from a title. Provide a simple way to choose today's list from existing `KanbanList` values, then offer a visible “Open today's list” action into Board. Include an explicit “Browse all lists” route that can open any existing list by stable ID. If a day-to-list convention is added later, selection may be suggested, but the user must be able to correct it.

The selected day's list is the plan: preserve its card ordering and divider rows. A Scheduled view can present the same cards as an agenda while keeping their order. Some card titles contain human-entered time text, but the current model does not parse or validate it. A card's `dueDate` is a date, not a time slot or event. Do not invent event times or claim calendar integration.

If structured scheduling is later needed, add an explicit event model with its own stable ID, date, start and end time, time zone, and optional link to a task. Define recurrence and all-day behavior only when required by the user workflow. Calendar access and synchronization require separate product and privacy approval.

Notes and ideas should have their own model and persistence rules when that feature is designed. Do not store private notes in card descriptions merely to populate a Today preview. Keep personal and shared/team ownership explicit before implementing collaboration; shared views should not expose personal content by default.

## First Increment

1. Today as the launch destination, Board access, per-date list selection, and list browsing are implemented.
2. Add an active test target and cover board Codable round trips, Today list selection, list-specific navigation, and behavior when a selected list is removed.
3. Implement Scheduled only after its ordered-list projection and interaction design are validated.
4. Keep true calendar events, standalone notes, ideas, and team features out of scope until their data models and workflows are separately designed.

## Quality and Privacy Principles

- Keep local-only behavior clear in product copy. Do not describe local persistence as sync, backup, or secure sharing.
- Preserve user data through decoding failures and model changes; provide recoverable errors and tested migrations.
- Support Dynamic Type, VoiceOver labels and order, high contrast, and comfortable touch targets. Do not make swipe gestures the only way to complete an action.
- Respect a reduced-motion preference and keep the Today layout predictable.
- Keep personal and shared content visibly distinct if collaboration is later designed. Do not make clinical efficacy, compliance, or treatment claims.