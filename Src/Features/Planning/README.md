# Today’s Plan

**Implemented first Planning Rhythm increment — October 16, 2026**

Tap the date beneath Today to open Today’s Plan. Choose priorities from active Cards and Notes across dated weeks and Library collections, optionally add an intention, constraints, and concerns, then tap Save. Edit supports ordering; removing a link leaves its source unchanged. Cancel offers explicit discard when changes exist

`TodayPlan.swift` contains the local model/store, source-linked priority UI, and picker. `Plenact.DailyPlans.v1` stores one plan per local date with its captured time zone. Loading never writes. Saving merges other days, checks same-day conflicts, and preserves unsupported/corrupt data. References resolve by owner/Card identity and known creation time, ignoring within-owner List changes. Cross-owner moves or unavailable sources retain saved title/context and require deliberate relinking

The view uses existing presenter-preserving Week and Library wrappers to open originals. Source completion is live, with Notes identified separately from incomplete tasks. This feature does not move tasks or implement automatic draft recovery after termination. Explicit Save is required

The existing offline example workspace snapshot covers the new preference key; root remounting reloads the original plan on restoration. Tests cover persistence, conflict, corruption, owner identity, creation-time reuse, live completion, example restoration, and actual hosted rendering

Automatic review scheduling remains proposed. See [vision](../../../Doc/Design/Planning-Rhythm.md) and [delivery plan](../../../Doc/Design/Planning-Rhythm-Delivery.md)

## Add priority

Add priority sits beneath Choose priorities. Its shared Card/Note draft saves into On the Table by default when that standalone List exists; otherwise choose an available List. Destinations include dated-week and personal Lists. Add saves the canonical item and selects a link in the open plan; Save on Today's Plan persists that link. Canceling the plan later removes its unsaved link but keeps the explicitly added item. Failed source saves retain the composer draft and add no priority link

## Today's Vision

Today's Plan provides Start/Resume/Revisit today's vision. The three steps review real dated work, choose/order priorities, and record optional intention/constraints/concerns. Save and continue saves the daily plan plus `visionStep`; finishing clears the step and records `visionCompletedAt`. Existing version-1 daily plans decode with those optional values absent

Candidates exclude completed, divider, and Reference-labelled content. Scheduling suggestions use date mappings and explicit dates, including spanning ranges. The optional Scheduled → On the Table transfer uses the root move callback and updates the current priority reference from the actual destination result. Root checked writes restore previous preference values on a reported store-write failure. This is not a crash-safe multi-store operation journal: termination between a committed move and plan save can leave an unavailable old link requiring manual repair, while the item remains at its saved destination

Default working roles currently recognize standalone Lists by their names. Missing Lists are not recreated automatically. Named-role configuration, durable reference repair across all plans, and a history of every review edit remain future work; submitted Check-in history is available in Daily review

## Today's Review

Start, resume, or revisit the evening review from Today's Plan. Three steps recognize completed work, offer explicit decisions for unfinished work, and save optional reflections. Decisions can leave an item in place, carry it to tomorrow or a chosen calendar day, return it to In the Queue, mark a Card complete, or archive it. Moves preserve dates and details. Reference-labelled content is excluded; Notes enter processing only when deliberately selected as priorities. No List must be empty to finish

Each confirmed action saves its source change and review decision together using a preference transaction journal. Startup rolls back interrupted transactions before loading workspace state; failed writes restore the previous source and plan. Steps and reflections save with the daily plan, and example workspace backup includes them. Unconfirmed text remains a draft until Save and continue or the plan's Save. Historical browsing and configurable working roles remain future work

## Today's Check-in

Start a fresh Check-in with Check in now from Today's Plan. Live progress separates tasks, Notes, and unavailable references. Edit reorders or sets priority links aside; Choose/Add reuse the existing pickers/composer. A selected unfinished Card or Note may be the optional next focus, displayed in Today's Plan. Completed, removed, or unavailable focus links are not presented as current focus

Each Save appends a timestamped Check-in with its note, next focus, plan fields, ordered priority snapshots, and progress counts, while updating the shared plan and preserving Vision/Review metadata. A new Check-in starts with an empty note and carries forward the current plan/focus. Save the note before leaving; leaving a nonempty unsaved note requires explicit discard. Explicitly added canonical items remain saved even if plan edits are discarded. No automatic source movement occurs

Daily review sits immediately above Weekly review. It reads saved plans, shows live progress and next focus for today, and retains Check-in snapshots and evening reflections for earlier days via Review day and Saved days. Browsing never saves or creates records. Optional `checkIns` extends the existing v1 document; legacy single Check-ins are presented without writing, then retained exactly once on the first new Check-in save. Legacy progress/plan snapshots are unavailable and labeled explicitly. `checkIn` remains the latest summary for current-focus compatibility. Existing same-day conflict protection prevents stale sheets overwriting newer Check-ins

## Weekly Review

Open Weekly review from Today's Plan. Choose a week using the app calendar's first weekday or open a saved review. Three saved steps gather available daily plans/reflections and achievement snapshots, process live unfinished In the Queue Cards, and record next-week direction, linked priorities, constraints, and risks. Missing daily records are valid. Reference-labelled Cards, Notes, completed Cards, and already-decided sources stay out of automatic Queue processing

Weekly records use `Plenact.WeeklyReviews.v1` in local preferences. Identity includes start date, time zone, and first weekday; saved records retain those boundaries. Latest saves replace that week's record with same-record conflict checks and preserve other weeks. Explicit Save progress and Save and continue persist drafts; closing unsaved edits asks before discarding. Confirmed Queue actions save immediately with the review decision through the shared recovery journal. Example backup/restoration includes the weekly store

Past reviews display saved reflections/decisions and aggregate currently saved daily records; the Queue is explicitly live, not a historical reconstruction. Next-week links do not automatically populate daily plans or move tasks. There is no scheduled Sunday reminder, immutable review revision history, or automatic weekly goal system in this increment

## Periodic Review

Open Periodic review after Weekly review in Today's Plan. Begin a named date range (or single-date checkpoint), look back at overlapping saved weekly reflections, assess objectives, and record next-period direction, linked priorities, and risks/constraints. All reflections and objectives are optional. Save progress persists the current step; Save and continue advances. Saved checkpoints are available through the checkpoint menu; unsaved edits block switching and require confirmation before dismissal

`PeriodicReview.swift` contains the interface and versioned `Plenact.PeriodicReviews.v1` local store. Each checkpoint has a UUID, captured date boundaries and time zone, saved progress, and timestamps. New checkpoints inherit objective identities/status/next steps from the latest saved review ending strictly before their start, while preserving an independent starting snapshot. Current-period progress begins empty. Changing a past review never silently rewrites later checkpoints. Achieved/paused/let-go statuses keep an objective's history without deleting it

Weekly references are read live and include entire overlapping weeks, clearly disclosed in the UI. Missing weekly reviews do not block reflection. Existing checkpoint objectives are local snapshots, not shared mutable global goals. No objective automatically creates or moves Cards, schedules reminders, or populates daily/weekly priorities. Example workspace backup includes the new key. Tests cover carry-forward identity and snapshots, conflict/corruption handling, range overlap, read-only opening, and backup restoration

## Library Help

`LibraryHelp.swift` bundles searchable offline reference articles grouped into life planning, individual app use, the five Planning Rhythm flows, and first-week v1.0 guidance. LibraryBrowseFilter.help excludes user collections and uses the same selection/checkmark/dismissal behavior as the other filters. Help hides the recent/Coming Soon shelves and searches guide bodies instead of user Cards

The Library owns article presentation so sheets remain stable while rows scroll. Articles use native text with scalable fonts, selectable paragraphs, headings, and an optional Today’s Plan entry point. Reading/searching Help does not mutate planning records or create tutorial content. Update the guide catalog alongside feature behavior

## iPad Today plan summary — October 17

Today on iPad presents a read-only Today's Plan panel beneath the heading, replacing the former large adaptive upper spacer. It shows the saved intention, up to three ordered priority links with live completion/Note/unavailable states, and a valid next focus from Check-in. Additional priorities are disclosed with a count. Open today's plan uses the existing editor and Planning Rhythm entry points; the empty state offers Plan today

The panel observes the daily-plan preference data, reloads on foregrounding and local date changes, and resolves sources through the current calendar access. It does not create or save a plan merely by appearing. Unreadable saved data produces an explicit message and remains unchanged. iPhone's panel order and spacing are unchanged; overflowing iPad content scrolls naturally


### Check-in moods

Each Check-in optionally records a `CheckInMood` value (emoji and label) on its history entry. The menu offers Great, Good, Okay, Low, Struggling, and Custom. Custom accepts one emoji grapheme and a nonempty trimmed feeling of up to 40 characters; Save waits for both fields. New Check-ins always start with no mood selection. Mood-only entries are valid; leaving unsaved mood input prompts for explicit discard. Daily review shows the saved mood next to the entry time. Optional decoding preserves earlier entries without a mood, and mood values remain independent of future preset changes. No mood score or inferred assessment is recorded.

## Day and Week templates

Library → Templates (or + → Templates → Browse all templates) manages local routines. `PlanningTemplates.swift` stores versioned independent snapshots under `Plenact.PlanningTemplates.v1`; `PlanningTemplatesView.swift` provides capture, edit, duplicate/delete, default selection, and preview/apply. The default is Jmr, a timed seven-day routine. Work Week (a reusable copy of the original example layout) and Vacation Day remain editable starting points. Example Week remains available separately. An absent store reads bundled starting points without writing; choosing Empty week persists automatic loading off. Existing content is never migrated or refilled.

Capturing excludes archived content and activity, resets completion, and retains list/board appearance, mixed Card/Note presentation, checklists and attachment references. Applying assigns fresh item/checklist/action/attachment identities, remaps local links, removes external card links, shifts date-bearing schedules using source and destination calendars, and preserves time-only values. Drawing preview/stroke files remain editable and protected by template-aware media cleanup.

Default routines apply only when creating an unsaved week (rollover, Week selection, Calendar or Day navigation). Existing weeks take precedence, including saved empty weeks. Manual preview is read-only; Add preserves active items, while Replace requires confirmation and clears only active items in the selected dated day/week. Archives and undated destination lists remain. Preview detects target changes before saving; calendar/current-Board publication uses the existing recovery journal. Template edits use optimistic store comparison and preserve corrupt bytes. Full workspace backup/restore includes templates and media.

Template edits affect future applications; planned days/weeks are independent. Use the item editor for template text, kind, dates and checklists, or capture a planned day/week for richer layout/media changes.

## Library catalog filters

Library offers All, Lists, Boards, Labels, Examples, Templates and Help. Templates embeds the same stateful Day/Week manager used by the standalone view, adds mixed List starters and the existing Card/Note starting points, and marks the default Week. Examples groups optional List/Board/Week/full-month content with previews, draft creation and the existing confirmed load/undo/restore callbacks. Both catalog filters search their own content and omit the personal recents/Coming Soon shelves. + menu browse shortcuts select these views.

Card/Note starters reuse QuickNoteComposer and create in a chosen Week list only after Add. `LibraryTemplateCapture` resolves the latest owning week, reserves archived IDs and retains existing content; checked Week saving handles publication. Browsing and searching are read-only.

Jmr contains four timed Cards per day (28 total), with date-and-time schedules rendered as time ranges on dated lists. Weekdays include Wake 04:00–04:30, Morning Starbucks Pow-wow 05:00–06:30, Work 07:00–17:00 and Gym 17:00–18:00. Saturday includes Wake 05:00–05:30, Starbucks 06:00–07:30, Gym 09:00–11:00 and Car Wash 12:00–12:30. Sunday includes Wake 04:00–04:30, Starbucks 05:00–06:30, Gym 07:00–08:30 and Church 09:00–12:30. Gym descriptions preserve the user's flexible daily routine. Source times use America/Chicago and apply as local wall-clock times in the destination calendar.

The optional `bundledRoutineRevision` field upgrades older v1 template libraries in memory, retaining their templates and adding/selecting Jmr once. Read-only loading does not rewrite preferences or scheduled weeks. Explicit edits persist the revision, so subsequent default choices and deletion are respected.


## Review invitations and reminders

`ReviewRhythm.swift` adds configurable evening/weekly invitations on Today, manual
review entry, per-period Later/Skip, and optional local notifications (off initially).
Tap Today → Planning rhythm to try either review now or configure its cadence.
Today's Review now distinguishes keeping an item on the Table for tomorrow from
moving it into tomorrow's dated Day list. Weekly Review can bring a Queue item onto
the Table. Due dates remain visible in both decision flows and are never reset by
carrying work. See [the full contract](../../../Doc/Design/Review-Rhythm-Invitations.md),
including the distinction between in-app suppression and repeating notifications.
