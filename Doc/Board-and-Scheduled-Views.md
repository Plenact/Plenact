# BoardView and ScheduledView

**Status:** `ContentView` is the implemented Board screen, and Today/Board navigation is implemented. `ScheduledView` remains a proposal aligned to the current local kanban model and the supplied weekly-planning reference.

## Shared Planning Model

The Board is the source of truth. A list contains ordered cards; cards hold task content, completion, dates, checklist data, labels, and attachments. Today and Scheduled should be views of those same lists and cards, not separate task stores.

This fits the broader [Life Planning & Management model](Life-Planning-Model.md): **Lists organize; Cards describe activities; checklist items express actions.** A weekly review is a separate proposed workflow for reconsidering existing plans, not another Board, task store, or scheduled-event system. Any future review should preserve source collection context and leave changes under the person's control.

The reference workflow uses a list for each day of the week, a separate open-work list, card order to express sequence, and divider cards to separate parts of the day. Some card titles include human-entered times. Plenact's current `KanbanList` has only an integer ID, title, and cards; it does not store a weekday/date assignment. Cards have date-only start/due dates but no structured time-of-day event fields. The supplied Trello JSON is a design reference and is not currently imported into app persistence.

## BoardView

### Purpose

BoardView is the complete, editable kanban workspace. It should preserve the existing board's horizontally navigable lists and provide access to every list, including day plans, open work, and lists the person creates later.

### Layout and Behavior

- Keep the board title and board-level actions in a consistent header.
- Present lists as horizontally navigable columns/pages, with clear list title, card count, and list actions.
- Keep cards vertically ordered within each list. Divider cards remain in the order and position chosen by the user.
- Keep card creation, editing, completion, movement, labels, checklists, attachments, and list management in the Board/card-detail workflows already implemented.
- Provide a list index or list picker so users can reach a named list without relying on repeated horizontal swipes. A deep link from Today or Scheduled targets a list by `KanbanList.id`, never by title or current array index.
- Preserve the board's current local persistence and attachment-file references. Future changes to stored models need a compatibility and migration plan.

### Relationship to Today

Today selects a day list and opens Board at that exact list by ID. “Browse all lists” offers all existing lists and opens the selected one. Board remains the place to inspect and edit the full kanban. Today must not hide the open-work list or create duplicate focus-card records.

## ScheduledView

### Purpose

ScheduledView is a time-oriented presentation of the weekly planning method. It should help scan the chosen day or week in the order the person planned it, while retaining a direct route back to the source list and cards.

### First, With Existing Data

Before structured event times exist, ScheduledView can be an agenda-style projection over selected day lists:

- Let the person choose a day or browse the week; use the same list-to-day choice as Today rather than guessing from editable list titles.
- Preserve the manually ordered cards and section dividers from each source list.
- Display time text that a person entered in a card title as ordinary title text. Do not parse it as a guaranteed start/end time or create reminders from it.
- Keep unscheduled/open work distinguishable from day plans. A date-only due date may be shown as a date, but not as a timed appointment.
- Open a card or its source list without losing the underlying board organization.

This first agenda projection requires no calendar permission, external service, or second copy of task data. If the source list has no day assignment, ask the person to choose it.

### Later, With Structured Events

If users need true calendar-style scheduling, first define a separate event model. At minimum, decide how it represents stable identity, calendar date, start/end times, time zone, all-day events, recurrence, and an optional relationship to a task. Decide conflicts and edits explicitly: changing an event time must not accidentally change a task's due date or reorder its board list.

Calendar import/sync, notifications, and background reminders are separate product and privacy decisions. Do not imply they exist until implemented, authorized, and validated. Local day-list planning should remain usable without calendar access.

## Navigation Contract

- Today -> selected day list -> Board at that list (implemented).
- Today -> Browse all lists -> selected existing list in Board (implemented).
- Scheduled -> source day list or source card in Board (proposed).
- Board -> Today through the tab bar (implemented); add Scheduled navigation when that view is implemented.

All routes use current list/card identities and must handle removed items with a clear fallback. A missing target should return to the list picker, not silently route to a different list.

## Accessibility and Cognitive Load

- Keep view names and navigation placement consistent. Label “Today,” “Board,” and “Scheduled” in text, not icons alone.
- Preserve a predictable reading order and support Dynamic Type, VoiceOver, sufficient contrast, and comfortable touch targets.
- Provide explicit list selection and card actions in addition to horizontal paging, swipe, or drag gestures.
- Keep the agenda concise by default; do not fill empty space with extra events or unrequested metrics.
- Respect Reduce Motion and preserve user-controlled card order.

## Suggested Delivery Order

1. Add Today as a focused entry point and direct, list-ID-based access to every existing Board list.
2. Make today's list selection explicit and recoverable when a list is renamed or removed.
3. Add ScheduledView as an ordered projection of day lists, without claiming structured times.
4. Validate list navigation, ordering, divider preservation, and existing-data compatibility with an active test target before adding event persistence or calendar integrations.