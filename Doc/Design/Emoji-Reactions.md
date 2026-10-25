# Personal emoji reactions

> **Data-model context — October 24, 2026:** The [current application/data plan](../Application-Data-Plan.md) supersedes older cloud, ownership and cross-device assumptions below. Model 1.0 is published for iOS/web/Windows; runtime synchronization remains unimplemented. Dated feature/design evidence below retains its original scope.

Reactions let people express how something feels alongside what needs doing.
Anticipation, appreciation, difficulty, and celebration belong to the person; Plenact
does not assign those meanings or turn emoji into a priority score.

## First implementation

Cards and Notes expose Add reaction in their + add menu and options menu.
The detail reaction bar appears only while reactions exist; removing the last
reaction hides the entire bar and its spacing. Existing reaction bars also offer
Add reaction. The Note uses its existing lower-toolbar + menu.
A starter palette offers common emoji; Another emoji accepts one typed or pasted
extended grapheme, including supported skin tones, flags, families, and keycaps.
Choosing an emoji toggles it immediately through the existing item-edit save path.
Canceling the picker does not change the item.

A quiet horizontal strip shows one chip per distinct emoji, preserving first-added
order. Tap an owned chip to remove your reaction. Other authors' entries are retained;
the data and chip grouping can represent their counts, although this release has no
shared reaction transport. Touch targets are at least 44 points high. VoiceOver gets
the emoji, count, and add/remove action. Reactions remain optional and independent
of completion (including the ✅ emoji), labels, importance, bookmarks, schedules,
and Today's Focus eligibility.

The reaction strip is outside configurable Card sections, so hiding Quick Actions
does not hide existing reactions. Notes show it between the title area and body.
List card tiles, flat Note List rows, and gallery tiles show read-only emoji summaries
with counts, collapsing to a compact summary when space is limited. Each item has a
Show reactions in previews toggle in its detail options and card tile menu, enabled
by default for legacy and new items. Hiding previews retains all reactions and keeps
the detail strip available. Location changes and other edits preserve this preference.
Comment reactions, review reactions, and shared/council feedback remain future work.

## Identity and persistence

`ItemEmojiReaction` stores an entry UUID, emoji, author UUID, and creation date.
`KanbanCard.reactions` is optional and defaults to nil for existing records. Empty
reaction state is stored as nil. Full item snapshots retain reaction state during
other edits. Location remapping and archive/restore preserve the records. Template
capture clears them, and fresh template instances do not inherit reactions.

`Plenact.LocalReactionAuthor.v1` holds a stable local author UUID. Reading or opening
a picker never creates it; the first explicit reaction action does. It is independent
of profile creation, so adding a profile does not orphan earlier personal reactions.
Existing workspace backup/restore includes the author key and serialized items.

This is a local single-user feature. Stable authorship is a foundation for a future
account mapping, not account authentication, multi-device synchronization, or shared
editing. Future shared reactions need explicit account identity mapping, permissions,
conflict handling, and transport rather than treating the local UUID as a verified user.

## Verification

Focused tests cover single-emoji validation, per-author toggle/removal, legacy JSON,
round-trip metadata, stable read-only identity behavior, movement, archive/restore,
fresh template capture, unchanged completion/labels, and Card/Note and light/dark
picker rendering. Final touch interactions and keyboard emoji entry are exercised
through the simulator/device trial.
