# Plenact Life Planning & Management Model

**Status:** Product-model reference and approved direction for exploration. The model describes how Plenact's existing planning concepts fit together; a weekly-review workflow is proposed, not implemented. This document is not a commitment to a new screen, data store, or release milestone.

## Purpose

Plenact should help a person move between capturing what matters, giving it a useful place, understanding the activity, choosing manageable actions, focusing on the present, and reviewing plans over time.

The product should make this possible without requiring every idea to be a dated task, every activity to have checklist steps, or every list to follow a prescribed set of “life areas.”

## Information hierarchy

Plenact's organizing model is:

> **Lists organize. Cards describe activities. Checklist items express actions.**

| Concept | Role in the model | Current boundary |
| --- | --- | --- |
| **List** | Organizes related cards in a meaningful context, such as a day, project, or personal subject. | A Week list belongs to the Week Board. Personal collections are stored separately. |
| **Card** | Describes an activity, plan, intention, or useful context. | A card can have optional dates and supporting details. A date is not a calendar event or a requirement. |
| **Checklist item** | Expresses a concrete action that can move a card forward. | Checklist items belong to their card; they are not a separate task database. |
| **Today** | Helps focus on a selected existing Week list for a particular date. | It projects canonical Board records and does not own duplicate cards. |
| **Week / Board** | Shows and organizes the larger ordered planning workspace. | Existing card and list order remains user-controlled. |
| **Library** | Provides access to the Week Board and the person's own collections. | Personal collections remain local lists or Boards, not a standalone Notes store. |
| **Saved** | Provides access to locally bookmarked Week and active personal-collection items, plus archived personal collections. | Bookmark stores remain independent and local; archive retains discoverable, restorable content, while confirmed Delete is permanent and archives are not backups. |
| **Review** | Offers a deliberate opportunity to reconsider plans and choose what to do next. | A weekly-review workflow is a proposed direction, not an implemented feature. |

These are complementary ways to organize and view work, not a set of required lifecycle states. A card can remain an idea, have no date, or have no checklist. People may use personal collections as their context without adopting a fixed set of “life areas.”

## Library and personal collections

The former Lists tab is now **Library**, with a books-style navigation icon. Its Week Board entry remains separate from **Personal collections**. Collection rows use the person's chosen title, icon, and color, with an explicit active-card count; Board subtitles count active lists. Search, list/Board creation, editing, ordering, and opening the existing content remain available. The empty state explains personal spaces and offers the existing list-creation form. Archived Boards and personal lists remain in Saved's **Archived Collections** section.

This is a presentation update, not a new hierarchy or migration. Lists still organize cards. In an open personal List, the center New action opens an explicit-save Note draft scoped to that List; Cancel creates nothing. From the Library directory, New opens the same Note composer and targets the most recently opened active personal List, falling back to the first visible active personal List. A Note's location label opens a destination picker for active personal Lists; moving preserves its content and bookmark and leaves the editor open. Personal Boards and other destinations retain the Week composer. Collection names or note-like icons do not establish standalone notes.

Saved includes bookmarks from active personal collections alongside Week bookmarks. Personal bookmark IDs remain collection-local; each Saved row retains collection and List provenance and opens the original record in place. Archived collections and archived Lists are not included as active bookmark rows; archived collections remain available through the separate restore section.

Collection titles wrap, card counts include text rather than color-only cues, and accessibility text sizes place counts below the title. Validation on October 5, 2026: `xcodebuild test -project Plenact.xcodeproj -scheme Plenact -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' -parallel-testing-enabled NO -only-testing:PlenactTests/PlenactBoardDocumentTests` passed **45 tests, 0 failures**, including hosted Library rows at portrait/landscape widths and accessibility text sizes. The earlier iPhone 17 destination was unavailable. Physical-device appearance, full create/edit/reorder/navigation interactions, and VoiceOver remain acceptance checks, not established by row measurements.

**Notes and Cards:** an item now chooses its own Card or writing-first Note interface while retaining the same underlying Card record. Library collection settings can choose a new-item default for each list without converting existing content. Make into Note/Card is an explicit, in-place presentation change that preserves supporting data; Note Details keeps action-oriented fields available. Before saving a new personal Note, its List label selects any active personal List without creating or moving stored content. After creation, the Note location label moves that record between active personal Lists and remains open at the destination. Existing records remain Cards when the optional preference is absent. This is not a standalone Notes store or bulk migration. Moving a personal Note into Week remains a separate, deferred data-safety milestone. See [Note behavior and compatibility](../Src/Features/Boards/README.md#notes-and-cards-one-record-two-interfaces).

The saved Note's bottom toolbar separates navigation, Details, attachments, user-initiated text sharing, and Add actions from the writing area. Its upper toolbar retains the single bookmark and lifecycle/presentation menu. Sharing exports only the current title, written body, and attached web links through the system share sheet; it does not enable synchronization or send hidden Card metadata or local media.

New items retain their actual creation timestamp, shown below a Note's title as localized date/time. New Note displays the draft's creation time before saving and retains that same time in the saved Note, including after destination changes or save retries. Cancel creates no record. Existing undated records remain undated rather than being assigned an estimated or opening date. Creation time is not a scheduled start/due date and does not change when an item is edited, moved, or restored.

### Optional personal-list examples

**Examples** appears beside **Create a list** in the empty Library state and remains available from Library's upper **+** menu after collections exist. The buttons stack when horizontal space or larger text requires it.

The chooser offers **On the Table**, **In the Queue**, **Scheduled**, **Shopping**, **Up for Brew**, and **Misc.**, each with eight synthetic cards and supporting descriptions. Expand a preview, choose **Use …**, then review the existing collection form and its included-card list. Only **Save** adds a new personal list; canceling the chooser or form does not add it. Each selection receives a fresh collection identity and an initially collision-safe title. The person can edit the title, icon, or color before saving.

These examples do not replace Week or existing collections, reference personal attachment files, assign people, create bookmarks, or automatically set dates/reminders. On the Table, In the Queue, and Up for Brew each include one original bundled illustration as an optional cover; previewing or canceling a draft writes no media files. Scheduled is a planning context, not a calendar service. Misc. demonstrates reference-style cards, not a separate Notes type. After saving, the cards are ordinary editable local content. This feature is separate from Today's **Load Example**, which has different Week replacement/undo semantics.

Validation: the same targeted iPhone 15 Pro Max command above passed **47 tests, 0 failures** after adding the examples. New tests check all six names, card-count bounds, identities, optional-field safety, round trips, no writes during draft creation, collision-safe names, and preservation of existing collection/Week snapshots after an explicit append/save. The actual chooser-to-form transition, Cancel/Save interaction, both entry points, and adaptive button appearance remain hands-on acceptance checks.

## User-directed content lifecycle

Card covers are an optional visual aid, not a new content type. People explicitly choose an attached photo or add a photo as a cover. Removing a cover keeps its attachment; a device display preference can hide all row covers without changing their selections. Existing saved work is not automatically given images. Details and behavior are documented in [Optional Card Covers](../Src/Features/Boards/README.md#optional-card-covers).

The offline **Cover Library** offers 48 original illustrations in six artwork categories, eight per category, plus All Covers browsing. Categories do not classify or restrict cards. Choosing is explicit, Cancel leaves content unchanged, and no card analysis or network service is involved. Color customization, search, and recommendations remain proposed follow-ups.

Cards, lists, and collections offer confirmed permanent deletion alongside their existing archive controls, including retained-content browsers. Archive means keep for later; Delete removes the selected record, its contained content, and its owning bookmarks. Other retained copies remain independent. Week can be archived or have its contents deleted, but its workspace remains available.

Deletion operates on the canonical local records, saves before publishing removal, and protects media still referenced by other retained content or the existing Load Example undo snapshot. It does not introduce remote synchronization or change the hierarchy. See the [lifecycle action matrix and safety boundaries](../Src/Features/Boards/README.md#archive-and-permanent-deletion).

Hands-on acceptance still needs confirmation/Cancel, restoration, deletion followed by relaunch, focused-editor failure/dismissal, photo import during deletion, shared attachments, both landscape directions, large text, and VoiceOver. Helper tests alone do not establish those interactions.

## Planning loop

The model can be understood as a flexible loop:

1. **Capture** an activity or idea when it comes to mind.
2. **Organize** it in a list or board that gives it context.
3. **Describe** it with a card and add useful details when needed.
4. **Choose actions** by adding checklist items if that makes the work more manageable.
5. **Focus** through Today or the Week Board without copying the underlying records.
6. **Review** plans periodically and decide whether to keep, change, complete, or set aside work.

This is a way to explain the product, not a required sequence. A person may start with a list, add details later, skip checklist actions, or leave an item undated.

## Weekly review direction

A weekly review is a high-value workflow to explore because it could connect day-to-day planning with longer-term organization while reusing the existing Lists, Cards, actions, and archive behavior.

The initial direction is a calm, user-invoked review of the Week Board. For each item the person chooses to consider, the app could make it easy to:

- Leave it where it is.
- Move it to another list.
- Add or revise a checklist action.
- Add or change an optional date.
- Mark it complete.
- Archive it when it should be set aside but retained.

Any future design should preserve user control:

- Do not move, archive, complete, or reschedule content automatically.
- Do not treat missed dates as failure or use scores, streaks, or guilt-based prompts.
- Make it clear what a proposed action will change and where the content will remain.
- Allow the person to stop and return without implying that unfinished review work is lost.
- Keep archived content discoverable and restorable; do not describe an archive as a backup.

These interaction details remain proposals. Review scope, cadence, entry point, progress/resume behavior, and whether personal collections participate should be decided before implementing a review UI.

## Views are projections, not competing stores

Today and future planning views should use the canonical records they present. They must not introduce a parallel Today task list or copy cards into a review-only store. Moving or editing an item through a view should update the same record, preserve its stable identity, and respect its owning Week Board or personal collection.

Personal collections remain distinct from Week data. A review should not silently merge their contents, and card IDs from different Boards must not be treated as globally unique. Cross-collection search, linked-card navigation, or review would need to preserve the source collection context.

Optional card dates remain dates on planning content. A date does not establish a time of day, recurrence, reminder, external calendar event, or synchronization.

## Product principles

- **Clarity over ceremony:** use familiar Lists, Cards, and actions instead of adding hierarchy for its own sake.
- **Choice over prescription:** allow different planning styles and undated work.
- **Continuity over duplication:** Today, Week, Search, and any future review surface should point to existing records.
- **Retention over disappearance:** archive means retained, discoverable, restorable content.
- **Manageable next steps:** checklist actions can help break down an activity but are optional.
- **Predictability and accessibility:** keep navigation understandable, state changes explicit, and important actions available without relying only on gestures.
- **Honest boundaries:** local storage is not synchronization, private cloud storage, or a guaranteed backup. Do not make medical, treatment, clinical-validation, or regulatory claims.

## What this model does not imply

This product direction does not establish or promise:

- A new task, goal, event, note, or review data store.
- Automatic scheduling, prioritization, reminders, recurrence, or task movement.
- Calendar integration, accounts, team collaboration, cloud synchronization, or backup.
- That all users need the same life categories or weekly routine.
- Medical, treatment, clinical-efficacy, recovery-outcome, or regulatory benefits.

## Related references

- [Today View Architecture](Today-View-Architecture.md) — current ownership and projection boundaries.
- [Today View UI](Today-View-UI.md) — implemented Today experience and possible follow-ups.
- [Board and Scheduled Views](Board-and-Scheduled-Views.md) — Board source of truth and proposed time-oriented projection.
- [Checklist Actions Architecture](Checklist-Actions-Architecture.md) — action identity and detail boundaries.
