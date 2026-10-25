# Your Planning Rhythm

> **Data-model context — October 24, 2026:** The [current application/data plan](../Application-Data-Plan.md) supersedes older cloud, ownership and cross-device assumptions below. Model 1.0 is published for iOS/web/Windows; runtime synchronization remains unimplemented. Dated feature/design evidence below retains its original scope.

See [Review invitations and reminders](Review-Rhythm-Invitations.md) for the implemented daily/weekly invitation and optional local-notification contract, including its current scheduling boundaries. This supersedes earlier statements that review reminders are entirely future work.


**Status:** Approved product direction, October 16, 2026. Today's Plan and the first guided Today's Vision flow are implemented; Today's Review is also implemented; Weekly Review is implemented; the first Periodic Review flow is implemented. This document defines the shared operating vision for five connected reviews. It is not a release announcement or a promise of automated scheduling

## First implemented increment — October 16, 2026

Today's date now opens a saved Today's Plan instead of the static targets sample. Users can select and order links to existing Cards/Notes, write optional intention/constraints/concerns, explicitly Save, and reopen the plan after relaunch. The plan shows live source status and opens the original item. Removing a priority removes only its link

The foundation is now joined by a first guided Today's Vision flow. Today's Review is also available with saved steps, reflections, and confirmed unfinished-work decisions. Check-in is now available for live progress, shared plan adjustments, and an optional next focus. Weekly Review is now available with saved week browsing; the first Periodic Review flow is implemented. It has explicit Save and unsaved-change dismissal protection, not automatic draft recovery after termination. Within-owner List moves remain resolvable; cross-owner moves or unavailable sources retain a historical title with a repair explanation. Broader review history, cadence, weekly summaries, and objectives remain future work

## The product promise

**Plenact helps you turn intentions into action, notice your progress, and begin again with a clear plan**

Plenact gives every plan a place, every day a direction, and every return a fresh starting point. Your Planning Rhythm connects everyday action with reflection and longer-term direction without requiring a rigid productivity system

> Choose a direction → take action → adjust → reflect → choose the next direction

The five experiences are one conversation continued at different moments. They share priorities, source items, decisions, and earlier reflections; they do not ask users to re-enter the same plan five times

## One connected rhythm

| Experience | Suggested moment | Central question | Saved outcome |
| --- | --- | --- | --- |
| Today's Vision | Beginning of the user's day | What matters today? | A realistic daily plan, chosen priorities, constraints, and risks |
| Today's Check-in | Midday or whenever circumstances change | What makes sense for the rest of today? | Progress against the current plan and deliberate adjustments |
| Today's Review | End of the user's day | What did today teach me, and what belongs next? | A daily summary, reflection, and explicit carry-forward decisions |
| Weekly Review | Sunday evening by default, configurable | Are my days moving me toward what matters? | Achievements, reviewed Queue items, and priorities for the coming week |
| Periodic Review | Chosen dates, intervals, or milestones | Is this still the direction I want? | Reviewed objectives, achievements, risks, and next steps for a new period |

Suggested moments are invitations, not deadlines. No automatic notification, required attendance, or missed-review debt is implied

## Today's Vision

Start with existing plans and the user's available attention, rather than a blank form

1. Review relevant Scheduled items and the dated Day List for today
2. Choose priorities and identify any time, energy, or practical constraints
3. Note risks or obstacles where useful; this is optional reflection, not a risk score
4. Confirm which Scheduled items to move to On the Table, retaining dates, times, and supporting details
5. Save the day's intended outcomes and begin work

Present Scheduled items as candidates using explicit dates, not just List names. Undated items require a user decision. A matching date is not permission to move an item. Explain the destination before applying a confirmed transfer

**Result:** a small, realistic plan linked to the original Cards and Notes, with no mandatory number of priorities

## Today's Check-in

Make this the lightest experience: a quick progress glance and a useful adjustment

- Show the current daily priorities and recorded completion, including changes since morning
- Ask what changed or is getting in the way, with optional written context
- Let the user keep, reduce, reorder, defer, or replace their remaining priorities
- Save the adjustment while retaining the earlier intention in the day's history

**Result:** a manageable plan for the time remaining. This is a status check, not a new planning session or a demand to explain low activity

## Today's Review

Recognize what happened before processing what remains

1. Show recorded achievements alongside the day's chosen priorities
2. Offer an optional reflection: what helped, what was difficult, and what to carry forward
3. Review unfinished actionable items from the Day List and On the Table
4. Confirm each desired action: complete, carry into tomorrow, return to In the Queue, choose a date, archive, or leave in place
5. Save a dated summary and make the next morning easier to begin

A clean reset means decisions have been made, not that every item must be removed. Reference/tutorial items and dividers should not appear in the unfinished-task queue. Other Notes can be included when explicitly relevant to a priority or selected by the user; a Note is not automatically an incomplete task

**Result:** today can be closed without discarding unfinished work or interpreting it as failure

## Weekly Review

Connect daily experience to the direction of the next week

- Review the week's daily summaries, recorded achievements, highlights, and optional reflections
- Compare progress with chosen weekly priorities and any linked objectives
- Process In the Queue: keep, activate, schedule, archive, or deliberately delete through the existing confirmation flow
- Choose a manageable direction for the coming week
- Save a weekly summary that remains useful even if some daily reviews were skipped

Sunday evening is the initial suggestion. Users can choose a different cadence; week boundaries must respect the user's planning-calendar preference. A worthwhile backburner idea can remain in the Queue after a deliberate Keep decision

**Result:** a considered Queue and a clearer next week, not a forced empty List

## Periodic Review

Support reflection at a meaningful date, interval, or checkpoint, such as the end of a quarter or a project milestone

- Review the selected period's objectives, weekly summaries, achievements, and highlights
- Consider what changed, what remains relevant, and which risks or constraints need attention
- Continue, revise, retire, or introduce objectives through explicit user choices
- Define next-period milestones and useful first steps
- Save the assessment and next direction without overwriting the historical record

**Result:** updated direction grounded in actual experience. Do not require quarterly reviews, goals, or milestones to use daily planning

## The working surface

| Existing place | Meaning in the rhythm |
| --- | --- |
| On the Table | Things the user hopes to accomplish today, time permitting |
| In the Queue | Waiting, unfinished, and backburner work worth keeping |
| Scheduled | Commitments or tasks with an intended date or time; the List name alone does not set dates or reminders |
| Day and Week | Canonical dated planning Lists and their surrounding calendar context |
| Plans tab / Library screen | Access to the user's Lists, Boards, labels, and broader planning content |
| Activity | Existing recent work, bookmarks, and browsing; not yet a saved review history |

These roles describe intent, not identity. Users may rename, remove, or replace default Lists. Future review configuration must retain owner-qualified List identities and offer repair when a chosen destination disappears, rather than creating or matching Lists silently by title

## Where the experience belongs

Today remains the daily home: Quick capture, Today's Focus, shortcuts, and direct routes into current work

**Implemented foundation:** tapping the date opens **Today's Plan** with saved priorities, live source status, and optional daily context. **Proposed next:** make this the outcome of Today's Vision and add the relevant plan/check-in/review actions as those workflows become functional

**Proposed:** a Planning Rhythm page, accessible from Today, provides all five experiences, resumable drafts, and saved review history. The exact entry control and presentation remain design decisions. Do not add five new bottom tabs or force a review on every launch

## Shared operating principles

- Begin with information already present; ask only what helps the next decision
- Save draft progress and let users pause, resume, skip, or revisit a session
- Keep changing plans separate from making a reflection; suggestions are not applied mutations
- Preserve original item identity, ownership, details, and media when a confirmed action moves it
- Distinguish recorded facts, user reflection, and proposed next steps
- Keep earlier intentions and summaries interpretable after later edits to the plan
- Treat clearing as deciding; Keep and Leave in place are valid outcomes
- Exclude Reference/tutorial Cards from automatic unfinished-work candidates, while allowing deliberate viewing
- Use calm language without scores, streak pressure, punitive overdue messaging, or mandatory explanations
- Make all important actions accessible without gestures; support Dynamic Type, VoiceOver, contrast, and Reduce Motion
- Keep the local planning experience usable without account setup, network access, or notification permission

## Connected information, not duplicated tasks

The proposed relationship is:

> Objectives → weekly priorities → daily priorities → existing Cards and Notes

A person can use daily planning alone. Review sessions retain dated decisions, reflections, and enough display context to explain history; they must not become a second editable task store. A saved summary reflects the period assessed and does not silently recalculate into a different historical outcome after later edits

See [Delivery and engineering plan](Planning-Rhythm-Delivery.md) for identity, persistence, migration, and acceptance requirements

## How we will assess the first release

Primary question: **Can someone finish a day with less uncertainty, then return the next morning knowing how to begin?**

Evaluate through hands-on use: can users understand a proposed move, resume an interrupted review, leave unfinished work safely, and return without catching up on missed sessions? Completion counts alone do not establish usefulness. Any future analytics or automated summaries require separate decisions; none are introduced by this documentation

## Delivery sequence

1. Daily foundation: Today's Plan, Today's Vision, and Today's Review
2. Midday adjustment: Today's Check-in using the same daily plan
3. Weekly direction: summaries, Queue processing, and next-week priorities
4. Longer-term direction: objectives, milestones, and Periodic Review

Each stage requires its own tested, reviewable implementation. No dates or release commitments are set here

## Related documentation

- [Life planning model](Life-Planning-Model.md)
- [Today interaction design](Today-View-UI.md)
- [Application architecture](Today-View-Architecture.md)
- [Documentation index](../README.md)
