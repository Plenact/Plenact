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

Default working roles currently recognize standalone Lists by their names. Missing Lists are not recreated automatically. Named-role configuration, durable reference repair across all plans, and a full review history remain future work

## Today's Review

Start, resume, or revisit the evening review from Today's Plan. Three steps recognize completed work, offer explicit decisions for unfinished work, and save optional reflections. Decisions can leave an item in place, carry it to tomorrow or a chosen calendar day, return it to In the Queue, mark a Card complete, or archive it. Moves preserve dates and details. Reference-labelled content is excluded; Notes enter processing only when deliberately selected as priorities. No List must be empty to finish

Each confirmed action saves its source change and review decision together using a preference transaction journal. Startup rolls back interrupted transactions before loading workspace state; failed writes restore the previous source and plan. Steps and reflections save with the daily plan, and example workspace backup includes them. Unconfirmed text remains a draft until Save and continue or the plan's Save. Historical browsing and configurable working roles remain future work

## Today's Check-in

Start/revisit the midday check-in from Today's Plan. Live progress separates tasks, Notes, and unavailable references. Edit reorders or sets priority links aside; Choose/Add reuse the existing pickers/composer. A selected unfinished Card or Note may be the optional next focus, displayed in Today's Plan. Completed, removed, or unavailable focus links are not presented as current focus

Save updates the same plan, preserving Vision and Review metadata, recording optional changed circumstances and the latest check-in timestamp. Return to Plan retains open edits for Save/discard. Explicitly added canonical items remain saved even if later plan edits are discarded. There is no automatic source movement or historical sequence of check-ins; revisiting updates the latest check-in

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
