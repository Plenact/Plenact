# Board, Day, Calendar, and Scheduled Planning

**Status:** Current local planning reference and approved future review direction, updated October 16, 2026. The first guided Today's Vision flow is implemented. A separate Scheduled agenda destination and weekly and periodic Planning Rhythm reviews remain planned; Today's Review is now implemented

## Canonical planning content

Dated weeks and personal collections own ordered Lists, Cards, Notes, and dividers. Today, Calendar, Search, Activity, and future reviews present or mutate those canonical records with owner context; they do not maintain duplicate task bodies

Dated weeks retain explicit date-to-List mappings in `PlanningCalendarDocument`. List titles remain editable. Cards can hold date-only or date-with-time values; neither a typed title nor membership in Scheduled creates an appointment or notification

## Current views

- Week shows the dated week's ordered Lists and supports changing the displayed week
- Day opens a chosen date's List and allows changing the displayed day
- Calendar browses local dated planning content; it is not external-calendar synchronization
- Plans opens Library, which browses personal Lists, Boards, and labels
- Standalone personal Lists use one screen title rather than repeating the same panel heading; List actions remain accessible
- Standard/Overview presentation, continuous zoom, Gallery, and viewport memory provide complementary ways to navigate content
- Appearance supports optional Board/List/item preview colors and personal backgrounds; dated Week/Day backgrounds retain their established treatment

Source locations, archives, bookmarks, and cross-owner movements must preserve identity and metadata. Back returns to the real presenter rather than an assumed tab

## Scheduled List versus a future agenda

**Scheduled** is an implemented default personal List for dated commitments or tasks. Its tutorial explains that users must set dates explicitly

**ScheduledView** is an older proposal for an optional ordered agenda projection. It is not a shipped destination or a prerequisite for Planning Rhythm. If developed, it should reuse canonical dates and preserve source ordering/context rather than parse times from titles or create parallel events

External calendar events, import/sync, recurrence, and notification delivery require separate design and authorization

## Planning Rhythm relationship

The [five reviews](Planning-Rhythm.md) connect the existing working surfaces:

- Morning: choose priorities and confirm any Scheduled-to-On-the-Table transfers
- Midday: inspect live progress and adjust expectations
- Evening: decide where unfinished Day/On-the-Table items belong
- Weekly: reflect on summaries and process In the Queue without requiring an empty List
- Periodic: assess direction and revise optional objectives or milestones

The review record stores decisions and reflection, not another Board. A daily priority reference may point to an item in a personal List or dated week without moving it. A confirmed move must retain the original item and resolve any changed owner-qualified identity

## Navigation and acceptance

Use owner-qualified List/Card references, preserve ordering and divider placement, and provide a repair path for missing targets. Do not resolve destinations solely by their editable title

Support explicit controls alongside drag/swipe gestures, Dynamic Type, VoiceOver, contrast, Reduce Motion, and both orientations. Check real keyboard and Back behavior. Validate canceled and interrupted moves, archives, media references, and local restoration before releasing review integrations

## Related references

- [Planning Rhythm vision](Planning-Rhythm.md)
- [Delivery plan](Planning-Rhythm-Delivery.md)
- [Today UI](Today-View-UI.md)
- [Architecture](Today-View-Architecture.md)
- [Board presentation history](Board-Presentation.md)

## Legacy Sunday date repair — October 17, 2026

A legacy Monday-through-Sunday List order could be initialized using the device's Sunday-start calendar, placing the preceding Sunday's date at the end of the displayed Week. Startup detects that exact dated order and repartitions the calendar to Monday-start using existing date associations. The current Saturday/Sunday sequence is then October 17/18 in the reported case; October 11 records remain in the preceding week instead of being relabelled. Canonical Sunday-first calendars remain unchanged. New initial Week workspaces use Monday-start; the existing week-start setting can still choose Sunday
