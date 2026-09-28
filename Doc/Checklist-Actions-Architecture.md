# Checklist Actions Architecture

**Status:** Phase 1 persistence foundation is implemented. Linked-card actions and Action Details are proposed and not yet available in the UI.

## Product Model

Plenact uses three levels of planning information:

- **Lists organize** related activities and plans.
- **Cards describe activities** and hold their working context.
- **Checklist items express actions** needed to move an activity forward.

An action should remain simple by default and gain more structure only when the user asks for it.

## Proposed Action Types

1. **Standard action:** editable text and completion state, such as “Go do laundry.” This is the only implemented checklist-item type today.
2. **Linked-card action:** references an existing Plenact card by stable card ID. Activating the item opens that card without copying or moving it.
3. **Action Detail:** owns a reduced detail record for an action that needs description, checklists, or comments but should not appear as an independent Board card.

The UI should default to a standard action. Linking a card or adding detail should be an explicit enhancement, not a required choice for every item.

## Implemented Foundation

`KanbanChecklistItem` now provides:

- A stable UUID independent of item position.
- Editable action text.
- Direct completion state.
- Codable and Hashable behavior for persistence and value updates.

`KanbanChecklist.items` stores item records instead of strings. The current checklist UI still uses its existing index-based callbacks through a computed `completedItemIndices` compatibility bridge. Editing text preserves item identity.

## Revision 0 Migration

Existing `Plenact.Board.v1` snapshots encode checklist items as `[String]` and completion as `completedItemIndices`. Custom decoding now:

1. Tries the current item-record format.
2. Falls back to the revision 0 string format.
3. Creates a repeatable UUID from the checklist identity and legacy item position.
4. Transfers each legacy completion index into the corresponding item's completion state.

New snapshots encode item records and no longer write `completedItemIndices`. The board storage key remains unchanged because the decoder accepts both representations.

The active `PlenactTests` target verifies nested legacy board decoding, deterministic migration IDs, arbitrary completion positions, and current-format round trips.

## Linked-Card Rules

When Phase 2 is designed:

- Store the linked card's stable ID, not its title, list index, or copied content.
- Keep checklist completion independent from card completion by default.
- Resolve the current card at navigation time so moves and renames remain safe.
- Show a recoverable unavailable state when the target card has been deleted.
- Do not silently delete the checklist item or redirect to a different card.

## Action Detail Rules

When Phase 3 is designed:

- The detail belongs to its checklist item and does not appear independently on the Board.
- Start with title, description, checklist groups, and comments.
- Avoid recursive Action Details in the first version.
- Confirm destructive removal when the detail contains user content.
- Define promotion to a full Board card separately rather than making conversion implicit.

## Accessibility and Cognitive Load

- Keep standard text actions visually quiet.
- Use a small text-supported indicator for linked or detailed actions.
- Keep the checkbox target separate from the title-navigation target.
- Provide visible alternatives to swipe and long-press actions.
- Announce unavailable links and action type through VoiceOver without relying on color alone.