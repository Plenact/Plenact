# Today: Current Experience and Planning Rhythm Direction

**Status:** Current UI reference with approved proposed additions, updated October 16, 2026. Today's Plan and the first guided Today's Vision flow are implemented. Today's Review is also implemented. Today's Check-in is now implemented; Weekly Review is now available with saved week browsing; the first Periodic Review flow is implemented

## Current experience

Today is the daily home of Plenact. The toolbar destinations are Today, Week, New, Plans, and Activity. Plans opens a screen titled Library

The main Today experience includes:

- Date, Search, Calendar access, and Account & Settings
- A softly styled daily slogan that scrolls with accessibility and reduced-motion considerations
- Quick capture into the current dated Day List, with a direct add action and full-editor path
- Today's Focus with up to four actionable items and Open today
- Up to six My shortcuts List destinations, configured through Account & Settings
- Browse this week as the route into the broader current-week plan

Tapping the Today date opens Today's Plan. Users choose links to existing Cards and Notes, order/remove priorities, add optional daily context, and explicitly Save. Reopening restores the local day's saved plan; source completion is live. Removing a link keeps its item. Unsaved edits require Save or an explicit discard while the sheet is open. Full daily reviews and automatic draft recovery after termination are not implemented. Day and Week headers have separate date/week pickers for selecting the displayed planning period

Fresh installations offer On the Table, In the Queue, and Scheduled in shortcut order, with one tutorial Card per List. Cards and Notes retain their canonical owners when opened through shortcuts, Search, Activity, or labels

## Proposed daily planning experience

See [Your Planning Rhythm](Planning-Rhythm.md) for the shared product contract

The implemented **Today's Plan** is the foundation for the future saved outcome of Today's Vision. It should show priorities, live source status, and a relevant next action while retaining the current Today screen for fast capture and execution

| Entry | Intended behavior |
| --- | --- |
| Today's Vision | Review existing work, choose priorities, note optional constraints/risks, confirm Scheduled-to-On-the-Table moves |
| Today's Check-in | Glance at progress and adjust the remaining plan without re-entering it |
| Today's Review | Recognize achievements and explicitly carry, queue, schedule, complete, archive, or retain unfinished work |
| Planning Rhythm | Proposed shared page for all five reviews, resumable drafts, and saved history; exact entry control remains open |

Do not add five bottom tabs, open reviews automatically on every launch, or replace Quick capture with mandatory planning forms. Suggested times are optional and user-adjustable; no notifications are part of this documentation change

## Interaction contract

- Reuse the dated week's date-to-List mapping; editable List titles are not calendar identity
- Retain canonical ordering, dividers, ownership, date kinds, rich text, and media
- Quick capture and its full-editor path share the typed title and create one record after an explicit add
- Keep New Card/Note destination selection, Cancel, and draft recovery behavior intact
- Back returns to the actual presenting context, including Search and Activity
- A proposed review move displays its source/action/destination and requires confirmation
- Reference/tutorial Cards and dividers are excluded from automatic unfinished-task processing
- Keep, Leave in place, Pause, and Skip are legitimate review actions
- A missed review must not block starting today or require completing every missed day
- Changes during a review update its live source status without silently rewriting a saved historical summary

## Accessibility and presentation

Keep a stable reading hierarchy with useful labels, comfortable touch targets, Dynamic Type, VoiceOver, contrast, and Reduce Motion support. Color and imagery reinforce identity but do not carry essential meaning alone

Retain the compact landscape lower-toolbar treatment and the keyboard behavior that keeps the lower toolbar anchored at the screen bottom. Decorative backgrounds may extend into safe areas; controls must retain safe-area protection

The default personal List photos and banners do not change dated Week/Day backgrounds. User-selected Appearance colors and backgrounds remain respected

Validate review drafts and navigation with keyboards, both landscape directions, accessibility text sizes, and a physical device before treating a new review flow as accepted

## Acceptance focus

Stage 1 must support planning a day, pausing/relaunching, applying confirmed moves once, and closing the day without losing unfinished work. Later stages reuse this foundation rather than introducing disconnected priority lists

See [delivery gates and scenarios](Planning-Rhythm-Delivery.md) and the [application architecture](Today-View-Architecture.md)

## Today's Vision — first guided morning flow

Open Today’s Plan from Today’s date, then choose Start/Resume/Revisit today’s vision. Three steps cover what is ahead, chosen priorities, and realistic daily context. Save and continue persists progress in the same daily plan; the final step saves a completion timestamp. Back to plan retains in-memory edits; only completed Save actions survive relaunch

Dated suggestions include the selected Day List and active items whose start/due date matches or spans today. Completed and Reference/tutorial items are excluded. Users can choose any other existing Card/Note in step two or create a new one. Movement is separate from selection: a Scheduled item offers an explicit confirmation before moving to an available On the Table List and replacing its priority link with the returned destination identity

The initial transfer action recognizes the default standalone List names. Missing destinations leave items in place. Configurable working-List roles remain future work. Confirmed moves are immediate; leaving the flow does not undo them. If saving the plan after a move fails, its link remains in the open draft and the user is told to review/retry

## iPad Today's Plan panel — October 17, 2026

On iPad, the Today sequence is Today's Plan, slogan/Quick capture, Today's Focus, List shortcuts, and Browse this week. The plan summary replaces the large upper spacer and makes chosen priorities distinct from items in the dated day List. Show saved intention, live status for up to three ordered priorities, optional next focus, and an explicit route to the complete plan. A missing plan prompts “What would make today meaningful?” with Plan today. Saved state comes from the existing daily-plan store; no second plan is created. iPhone retains its existing layout
