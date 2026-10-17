# Planning Rhythm: Delivery and Engineering Plan

**Status:** Proposed implementation plan supporting the approved [Planning Rhythm vision](Planning-Rhythm.md), October 16, 2026. Daily-plan persistence and a source-linked Today's Plan screen are now implemented; the first guided Today's Vision flow is implemented; Today's Review is also implemented; Weekly Review is implemented; Periodic Review and checkpoint objectives are implemented; review scheduling remains planned

## Delivery gates

| Stage | Deliverable | Acceptance gate |
| --- | --- | --- |
| 1 — Daily foundation | Today's Plan, Today's Vision, Today's Review, resumable drafts, confirmed carry-forward decisions | A user can plan, act, close a day, relaunch, and resume without lost content or duplicated transfers |
| 2 — Midday adjustment | Today's Check-in tied to the saved daily plan | Progress and revisions use the same priorities; morning intent remains understandable |
| 3 — Weekly direction | Weekly Review, daily-summary aggregation, Queue decisions, next-week priorities | Works with missing daily reviews, configurable week boundaries, and a Queue that legitimately retains items |
| 4 — Longer-term direction | Optional objectives, milestones, periodic checkpoints, linked summaries | Period boundaries and revised goals preserve historical meaning without making goals mandatory |

Build only functional entry points. The static targets preview has been replaced by the first working daily-plan screen. The first Vision and Review sessions now include saved progress and explicit carry-forward decisions. Do not introduce automatic notifications or remote persistence as incidental dependencies

## Shared concepts to design before coding

These are semantic requirements, not finalized Swift types or storage keys

| Concept | Required meaning |
| --- | --- |
| Daily plan | Stable identity, local planning date, selected priorities, optional constraints/risks, current revisions, linked review sessions |
| Priority reference | Stable reference to a canonical Card/Note or an explicitly designed written outcome; no duplicate task body |
| Review session | Stable identity, kind, period, draft/completed state, timestamps, optional reflection, decisions, and resumable position |
| Review decision | Source identity, intended destination/action, proposed/applied state, unique operation identity, and result |
| Saved summary | Dated assessment with recorded facts separated from reflection and enough context to remain understandable later |
| Rhythm preferences | Optional cadence, weekly review day, periodic checkpoints, chosen working Lists, and accessibility-aware presentation |
| Objective or milestone | Optional longer-term direction linked to priorities; introduced only in stage 4 with a deliberate versioned model |

Use owner-qualified references: a personal collection or dated-week owner plus its List and Card identity. Existing integer Card IDs are not globally unique. If movement remaps an ID, update links deliberately using the movement result; never resolve a missing reference to an unrelated item with the same integer ID

## Source ownership and mutation contract

- `AppRootView` currently coordinates dated weeks, personal collections, bookmarks, and cross-owner moves
- Reuse the canonical movement and checked-persistence boundaries; extract a focused application service when required rather than duplicate their logic inside review views
- Read the source record again before applying a decision; it may have been edited, moved, archived, or deleted since the review began
- Show the action and destination before confirmation. Applying it must preserve titles, rich text, dates and date kinds, checklists, attachments, labels, and ownership-aware bookmarks
- Validate and save affected stores before publishing a successful move or decision
- Persist an operation identity/result so retrying after interruption cannot move or duplicate the item twice
- Define the recovery boundary between source mutation and session progress. A saved task move plus an unsaved decision must be reconcilable on relaunch
- Keep recorded review text distinct from live task data. An archived/deleted source can be shown as unavailable with historical context; never resurrect it automatically
- Cancellation or skipping leaves unapplied suggestions unapplied. Already confirmed actions remain saved and clearly identified
- Permanent deletion uses the existing explicit confirmation; completing a review must never imply deletion

A morning move from Scheduled to On the Table is a transfer of the original record, not a clone. Showing it as a daily priority does not require another move into a Day List. When users choose a dated Day destination instead, retain one canonical location and explain it

## Dates, periods, and eligibility

- Reuse `PlanningDate`, dated-week mappings, and the document's first-weekday preference
- Define and record the local date/time-zone context used for each review period before implementation
- Separate suggested review time, actual session time, and the day/week being assessed
- Handle midnight, daylight-saving transitions, year boundaries, and time-zone changes without duplicate sessions or unintended shifts of saved dates
- Allow reviewing yesterday or an earlier week without changing the currently displayed Day/Week unexpectedly
- Do not interpret date-only values as timed events, parse timing from titles, or assign dates because an item is in Scheduled
- Deduplicate candidates by owner-qualified identity when an item is both a priority and part of a source List
- Exclude dividers and Reference/tutorial items from automatic unfinished-task processing. Define a durable semantic exclusion before coding; do not rely only on a label's editable display name
- A Note is not automatically unfinished. Include relevant Notes through explicit selection or links rather than treating every unchecked-looking record as a task
- Missing default Lists require a user-visible destination choice or repair path, not silent recreation by name

## Local storage and compatibility

The daily-plan foundation uses the versioned local store described below. Evening review reflections, achievement snapshots, and decisions are stored in the daily plan; a transaction journal covers evening source mutations and review saves. Broader session schemas remain open

- Existing installations decode without requiring review data or activating a new routine
- Opening a review must not seed, replace, or migrate unrelated planning content
- Preserve unreadable or unsupported stored bytes and show a recoverable error
- Draft persistence, completed-session edits, summary revisions, and retention rules must be defined explicitly
- Extend the full-month example workspace switch to include any new files/stores and in-memory state before releasing reviews
- The current example backup captures app preferences, Documents, and Application Support; confirm any new storage remains covered and restoration reloads it correctly
- Demonstration reviews must be clearly fictional and must never be merged into restored user history
- Removing Local Profile does not imply deleting plans or review history
- No remote schema, endpoint, sync behavior, external-calendar permission, or notification registration is authorized by this plan

## Stage acceptance scenarios

### Stage 1

- Start with existing data and with the three fresh-install tutorial Lists
- Plan with zero, one, or several priorities; save and reopen without creating duplicate Cards
- Confirm a Scheduled-to-On-the-Table move with dates/times, rich text, attachments, and bookmarks intact
- Cancel a proposed move; interrupt and retry a confirmed operation without duplicate effects
- Review unfinished work; keep, carry, queue, date, complete, or archive through the correct source owner
- Delete or rename a selected destination and repair the selection explicitly
- Skip a review, return days later, and begin without processing every missed session
- Preserve Reference/tutorial Cards, dividers, custom ordering, and unselected Notes
- Exercise decode/write failure, app termination, and full-month example load/restore with review drafts present
- Validate Dynamic Type, VoiceOver, Reduce Motion, both orientations, keyboard behavior, and physical-device navigation

### Stages 2–4

- Check-in reflects live completion and records changed priorities without erasing morning intent
- Weekly summaries work with incomplete daily history and either supported week start
- Queue Keep decisions count as processed while preserving retained ideas
- Periodic review handles arbitrary intervals, milestones, DST, leap dates, and quarter/year boundaries
- Revised objectives preserve the historical meaning of earlier summaries and links

## Decisions still open

- Exact Planning Rhythm entry control and review presentation
- Priority representation, optional ordering, and how users express an outcome without an existing Card
- Draft/completed-session editing and history retention
- Default review-time suggestions and whether reminders are desirable later
- Durable Reference/tutorial exclusion semantics and source-link repair after moves
- Concrete versioned storage, operation journal, migration, and export strategy
- How users choose non-default Lists for the three working roles

Resolve each decision in its relevant stage; do not treat an unanswered design detail as permission for automatic behavior

## Daily-plan foundation now available

`Src/Features/Planning/TodayPlan.swift` owns the daily model, linked priorities, local store, and UI. `Plenact.DailyPlans.v1` stores a versioned document keyed by local Gregorian date with the captured time zone. Saving one day merges into the latest document and rejects stale same-day edits. Unsupported/corrupt data is retained without overwrite

Priority references contain owner UUID, collection-local Card ID, known creation time, and fallback title/location. They resolve live status and within-owner List moves; cross-owner moves are explicitly unavailable until relinked. Save leaves source content and locations unchanged. More comprehensive durable reference repair remains required for review-driven transfers

Plans use explicit Save; Cancel/discard and interactive-dismiss guards protect unsaved work while open. Automatic draft recovery after app termination is not implemented. The plan's date is fixed while its sheet is open, including across midnight. The existing offline example workspace captures/restores the new preference key and rebuilds the view state; a regression test checks restoration of the original plan after demo edits

## Today's Vision implementation milestone

The three-step morning flow now saves progress on the shared daily plan, resumes saved steps, offers existing/new priorities, and saves completion after optional daily context. It includes user-confirmed Scheduled-to-On-the-Table moves through root coordination, returning the actual moved Card identity to the current plan

Stage 1 is still incomplete: durable review-history browsing and configurable working-List identities remain to be implemented; evening actions now have a crash-recovery journal. In-memory/store-error rollback is not proof of recovery after termination between source transfer and daily-plan save. Existing source data remains discoverable, but an older link can require deliberate repair in that interruption window

## Implemented midday check-in — October 16

Today's Plan now opens Today's Check-in at any time, including without a morning plan. It reports live priority task completion separately from Notes/unavailable links, supports choosing/adding/reordering/removing priority links, and records optional changed circumstances and one next focus. Intention, constraints, concerns, and priorities are the shared daily-plan fields. Explicit Save persists the adjustments and latest check-in timestamp with the existing same-day conflict check; leaving the sheet retains edits in the parent plan until saved or discarded

Check-in metadata is optional in version-1 plans. Focus is valid only for a still-selected, available Note or unfinished Card; a completed/removed/unavailable focus is no longer displayed and is cleared on the next check-in save. No automatic task moves, check-in schedule, notifications, or separate check-in history are introduced

## Implemented Weekly Review — October 16

Weekly Review is available from Today's Plan with a date-based week selector and saved-week menu. It aggregates available daily reflections, check-in changes, and saved achievement snapshots, accepts weekly highlights/lessons, offers confirmed live Queue decisions, and stores next-week direction/priorities/constraints/risks. The Queue may retain items; missing days need no repair

`Plenact.WeeklyReviews.v1` stores one latest record per week-start/time-zone/first-weekday identity. The shared review journal protects source mutations and weekly decisions together. Saved weeks are revisitable, with explicit disclosure that Queue actions operate on current items. Daily aggregation reads current saved daily records; it is not an immutable weekly snapshot. Cadence/reminders and revision history remain future work; the first Periodic Review flow is implemented

## Implemented Periodic Review — October 16

The first Periodic Review flow supports named custom date ranges and single-date checkpoints, saved checkpoint browsing, overlapping weekly reflections, objective progress assessment, and next-period direction/priorities/risks. It uses `Plenact.PeriodicReviews.v1` in local preferences, with explicit saves, conflict protection, and offline example backup coverage

Objectives retain stable identities across a new checkpoint's copy of the latest preceding saved review. Each record keeps both starting objectives and its updated assessment; past records remain independent. Current-period progress starts empty while prior evidence remains visible. This is a first objective-carry-forward model, not a global goal catalog or immutable revision history. Saved checkpoint dates are fixed; create a new checkpoint for another range. Overlapping weekly reviews are included in full and remain live source records. Cadence, reminders, objective-to-Card automation, and cross-device sync remain future work

## v1.0 daily-use trial and follow-up backlog — October 16, 2026

Justin will use Plenact 1.0 on his iPhone over the next few days, returning with feedback and questions throughout the day. Prioritize real-use findings before adding major features. All five initial Planning Rhythm flows are implemented; this is a hands-on validation period, not a claim that all acceptance checks are complete

Keep the following items open for future review and completion:

- Add a daily-history date selector to reopen past saved plans and reflections
- Extend interruption recovery to morning transfers so source moves and priority-link saves recover together
- Let users assign working roles to custom Lists by stable identity instead of relying on default names
- Complete physical-device validation of all five flows: accessibility, Dynamic Type, keyboard behavior, navigation, explicit save/discard, reopening, and interruption/resume
- Revisit optional reminders/cadence, export, and cloud sync after initial daily-use feedback

For each real-use finding, capture the flow, expected behavior, actual behavior, approximate date/time, and a screenshot when useful. Record fixes and remaining questions here or in linked issue notes. Do not treat unsaved edits as persisted drafts; existing flows require explicit saves. Preserve the user's installed dataset when installing updates

## First-use Help — October 16

Library → selector → Help now provides bundled, searchable guidance for using Plenact in life, individual app operations, all five Planning Rhythm flows, and the first v1.0 trial week. Guides include save/immediate-action semantics, source-link behavior, objective carry-forward, live Queue handling in historical reviews, local storage, and offline example restoration. Relevant articles open Today's Plan. This supports the trial without altering user data; revise guidance with real-use feedback
