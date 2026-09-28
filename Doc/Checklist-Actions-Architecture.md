# Checklist Actions Architecture

**Status:** Stable action persistence, linked-card navigation, reduced Action Detail editing, and seeded demonstrations are implemented. User-facing controls to create or convert rich action types are not yet implemented.

## Product Model

Plenact uses three levels of planning information:

- **Lists organize** related activities and plans.
- **Cards describe activities** and hold their working context.
- **Checklist items express actions** needed to move an activity forward.

An action should remain simple by default and gain more structure only when the user asks for it.

## Action Types

1. **Standard action:** editable text and completion state, such as “Go do laundry.”
2. **Linked-card action:** references an existing Plenact card by stable card ID. Activating the item opens that card without copying or moving it.
3. **Action Detail:** owns a reduced detail record for an action that needs description, checklists, or comments but should not appear as an independent Board card.

The UI should default to a standard action. Linking a card or adding detail should be an explicit enhancement, not a required choice for every item.

## Implemented Foundation

`KanbanChecklistItem` now provides:

- A stable UUID independent of item position.
- Editable action text.
- Direct completion state.
- Explicit standard, linked-card, or Action Detail content.
- Codable and Hashable behavior for persistence and value updates.

`KanbanChecklist.items` stores item records instead of strings. The current checklist UI still uses its existing index-based callbacks through a computed `completedItemIndices` compatibility bridge. Editing text preserves item identity.

## Revision 0 Migration

Existing `Plenact.Board.v1` snapshots encode checklist items as `[String]` and completion as `completedItemIndices`. Custom decoding now:

1. Tries the current item-record format.
2. Falls back to the revision 0 string format.
3. Creates a repeatable UUID from the checklist identity and legacy item position.
4. Transfers each legacy completion index into the corresponding item's completion state.

New snapshots encode item records and no longer write `completedItemIndices`. The board storage key remains unchanged because the decoder accepts both representations.

The active `PlenactTests` target verifies nested legacy board decoding, deterministic migration IDs, arbitrary completion positions, earlier stable-item compatibility, rich action round trips, and seeded demonstration coverage.

## Starter Demonstrations

Every seeded non-divider card receives the following examples in its first checklist:

- One linked-card action targeting a valid card in the next Board list.
- A preparation Action Detail with description, two nested standard actions, and a comment.
- A review Action Detail with description, two nested standard actions, and a comment.

Divider cards remain structural and do not receive rich actions. These examples appear only when `SampleData` initializes a new board; existing persisted boards are not overwritten.

## Linked-Card Rules

Current linked-card behavior follows these rules:

- Store the linked card's stable ID, not its title, list index, or copied content.
- Keep checklist completion independent from card completion by default.
- Resolve the current card at navigation time so moves and renames remain safe.
- Show a recoverable unavailable state when the target card has been deleted.
- Do not silently delete the checklist item or redirect to a different card.

## Action Detail Rules

Current Action Detail behavior follows these rules:

- The detail belongs to its checklist item and does not appear independently on the Board.
- The owning checklist item supplies the title; the sheet edits description, nested checklist completion, and comments.
- Seeded nested checklists contain standard actions only.
- Save writes the complete detail back to its owning item; Cancel discards local edits.

Remaining Action Detail work includes creation/conversion controls, nested checklist authoring, destructive-removal confirmation for populated details, and any explicit promotion to a full Board card.

## Accessibility and Cognitive Load

- Keep standard text actions visually quiet.
- Use a small text-supported indicator for linked or detailed actions.
- Keep the checkbox target separate from the title-navigation target.
- Provide visible alternatives to swipe and long-press actions.
- Announce unavailable links and action type through VoiceOver without relying on color alone.