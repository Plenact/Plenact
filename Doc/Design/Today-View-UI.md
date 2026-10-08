# Today View UI Proposal

**Status:** Today and Board tabs are implemented. This document records the current first version and possible follow-up refinements. The attached weekly board is the reference for how Today serves the existing day-by-day planning method. The broader [Life Planning & Management model](Life-Planning-Model.md) is a product direction; weekly review is not an implemented Today feature.

## Design Goal

Make the first screen calm and immediately useful: show the date, the list selected for today's plan, and a direct way into that list. Keep the full board accessible, including every weekday and open-work list. The ordered day list remains the plan; Today should not replace it with an unrelated “top three” task list.

## First-Version Layout

```text
Today
Sunday, September 27

Today's plan
Choose one of your existing board lists for today's plan.
[ Choose today's list ]

Your board
Open any existing list, including open work and custom lists.
[ Browse all lists ]

Today                         Board
```

After selection, Today shows the chosen list title and card count, an “Open today's list” button, and “Choose a different list.” The selection is stored locally for the current date. “Browse all lists” opens a readable picker; selecting a row opens that exact list in Board. The Board tab keeps the whole kanban one tap away.

Today does not silently infer the day from a list title: titles are editable and the model has no weekday/date field. If the selected list is missing, Today offers the choose-list path rather than silently substituting a different plan.

## Later, When Supported

Once schedule events and notes are real app features, Today can optionally include:

- **Next up:** the next structured scheduled event, its actual time, and a clear route to event details. Until then, use the ordering and text of the selected day list without presenting a card as a verified timed event.
- **Recent notes:** a small list of the user's own recent notes, hidden when empty or disabled.
- **Capture:** a compact action menu for Task, Note, and Idea, showing only types that can actually be saved.
- **Navigation:** Today and Board are implemented. Add Scheduled after its behavior is validated; add Projects, Notes, and Team only as those destinations become functional.

Each section should be independently hideable or configurable where that helps the person control screen density. Keep optional sections out of the initial layout until there is real content to show.

A future weekly review may offer a deliberate way to revisit plans, but it should not be conflated with Today or Scheduled. If explored, it should operate on existing Board records, require the person's choice for changes, and remain optional rather than adding automatic rescheduling or pressure.

## Interaction Rules

- “Open today's list” opens the existing Board positioned at the selected day list. “Browse all lists” exposes every existing list by its stable ID, including lists not assigned to Today.
- Preserve the list's manually chosen card order and divider rows in Today and when opening Board.
- In the opened Today list, “Reorder cards” exposes native drag handles for both cards and divider rows; completing the move updates the same canonical Week list order.
- Tapping a task navigates to its existing card details where possible; completion updates the same persisted card, not a Today-only copy.
- Card row/detail controls offer Archive and confirmed permanent Delete. Today list choices, Search, label results, Calendar, and Saved bookmarks delegate their lifecycle actions to the same canonical Week records rather than removing a projection-only copy. Archived content can be inspected and deleted through the retained-content browsers.
- Deletion removes the owning bookmark and saves the complete remaining Week snapshot before publishing removal. It does not delete separate personal/archived copies or remove the permanent Week workspace. See [archive/deletion entry points and media safety](../Src/Features/Boards/README.md#archive-and-permanent-deletion).
- Add task, if included in the first increment, creates a card in an explicitly selected existing list.
- If the selected list was removed or cannot be resolved, ask the person to choose another list; do not silently pick the first list.
- When Quick capture is focused, the custom lower navigation toolbar stays anchored at the screen bottom and the keyboard covers it; the toolbar must not rise above the keyboard.
- Avoid reminders, calendar permissions, or background scheduling in this first screen proposal.

## Accessibility and Cognitive Load

- Use a stable vertical reading order: date, today's plan, plan-list actions, board-list browser, tab navigation.
- Use plain text labels alongside icons for important actions. Provide VoiceOver names and meaningful accessibility order.
- Support Dynamic Type without truncating task titles or overlapping controls.
- Keep interactive targets comfortably sized, with at least 44-by-44-point targets where practical.
- Maintain sufficient contrast in light and dark appearances; never communicate completion or category by color alone.
- Avoid dense badges, auto-rotating content, unnecessary animation, and hidden essential actions. Honor Reduce Motion.
- Provide useful empty states without suggesting that calendar, notes, or sharing is available before it is implemented.
- Keep the selected day list and “All lists” route visible; neither should depend on swipe-only navigation or remembering the board's horizontal position.

## Responsive Behavior

On iPhone, use a single-column scroll view and keep today's list actions and board-list browser easy to reach without covering content. On larger displays, retain the same order and reading hierarchy. Validate with larger accessibility text sizes and VoiceOver as well as the default presentation.

The shared lower navigation bar uses a compact-height layout in landscape: icon/caption groups are horizontal, the New button is 44 points, and controls remain within the 52-point content area above the bottom safe area. Portrait keeps the raised New presentation. Both layouts retain keyboard overlay behavior rather than moving the toolbar above Quick capture's keyboard.

The paper background extends through the horizontal and bottom container safe areas so it fills the screen width in either landscape direction. Only the decorative background extends into these areas; navigation controls retain safe-area protection from the camera cutout and home indicator.

The root destinations are Today, Week, **Library**, and Saved, with New retaining its existing capture behavior. Library replaces the former Lists tab label and uses a books-style icon. It opens the Week directory and local personal collections, not a standalone Notes workflow; see [Life Planning Model](Life-Planning-Model.md#library-and-personal-collections).