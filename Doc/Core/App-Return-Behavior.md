# Returning from the Home screen

The device-local five-minute resume behavior applies while the current app process remains alive. Restoring navigation and every unsaved draft after iOS terminates the app is deferred. After more than eight hours in the background, an eligible opening goes directly to **Today**, including after a process relaunch. This consumes the daily Week opening for that local date. Open Cards, Notes and editors remain protected. Otherwise, the first eligible opening of each local calendar day opens **Week → today's List → top**, across process launches as well as background returns. Later fresh launches on that same day retain launch screen → Today behavior.

| Current context | Less than five minutes away | Five minutes or longer away |
| --- | --- | --- |
| Today | Resume | Resume |
| Open Card/Note, presented editor/sheet, or active inline writing | Preserve the current item/editor | Preserve the current item/editor |
| Week browsing | Same List and scroll positions | First available dated List of that stored Week, at the top |
| Library browsing | Same filter/search/position | All filter, cleared search, top of listings |
| Activity browsing | Same section/search/position | Saved, cleared search, top of browser |

The daily-opening rule takes priority over the table when a local date has not yet been handled. Its day begins at midnight in the phone's current time zone, not at a fixed UTC boundary. Open work or an unavailable/archived destination defers the daily rule until a later eligible opening; closing an editor does not itself trigger a jump. A mere Control Center interruption is not a daily opening.

Otherwise, only the active tab receives a reset. Open work takes priority; there is no deferred timeout reset after its editor closes. Modal contexts are preserved conservatively. Week rollover is not performed while the return guard detects open work. First-day selection follows the stored Week's date mappings, so it respects its actual Monday/Sunday boundary and does not depend on visual List reordering.

The timer begins at `scenePhase.background`, not transient inactivity such as Control Center. It uses `ContinuousClock`, includes sleep, and does not depend on wall-clock/time-zone changes. Repeated background notifications do not extend the interval; an arrival consumes it once. The five-minute threshold itself is inclusive.

`AppReturnBehavior.swift` owns the in-memory policy and scene-specific protection. Scoped reset requests reach the Week, Library and Activity independently. Existing owner-qualified Board viewport memory resets offsets while retaining zoom and presentation choices. Native scroll probes reposition already mounted scrollers; resetting a dictionary alone is insufficient. Inline writing and navigated Card/Note content report protected lifetimes, while the scene-window probe protects modal editors.

No new shared preference, portable schema or cloud field is introduced. `AppDailyOpening` stores the last handled local-day key and a background-departure timestamp in the separate `com.plenact.app.device-navigation` preference domain. It is not added to the workspace's preferences or portable/native workspace packages. Browsing resets also update the existing device-local Board viewport state, which is already excluded from shared portable records. User content, backups and recovery history are not reset. The launch behavior does not promise reopening an editor after process termination.

The original return behavior passed eight new `AppReturnTests` cases plus four existing viewport/Library checks (12 tests). Daily-opening coverage adds local-midnight boundaries, store reopening, protected/missing-target deferral, the repeated DST hour and explicit today's-List targeting in the mounted Board test. The updated run passes 16 focused native tests: 12 return/daily-opening cases and four existing viewport/Library checks. All 112 tooling checks pass. Updated evidence is `/private/tmp/plenact-daily-opening-tests.log` and `/private/tmp/plenact-daily-opening-python.log` (temporary). Coverage includes threshold/one-shot behavior, protected departures/arrivals, fresh activation, Monday/Sunday and reordered/undated List selection, owner-isolated viewport memory, mounted horizontal/vertical resets, actual zoomed Week reset and modal detection. Native test evidence: `/private/tmp/plenact-app-return-final.log` (temporary).

For the focused manual check, rebuild Plenact Import Test, browse down a later Week List, return via Home within five minutes and confirm the same position. Then repeat after at least five minutes and confirm the first dated List at its top. Open Cards/Notes and editors should remain open across a return; Library and Activity should follow the table. The first rebuild after adding the daily marker should open today's Week List at the top. Later same-day fresh launches go to Today; the next local day gets a new daily opening. The rule does not restore editors after process termination. No package export/re-import is needed for this navigation-only change.

## Untouched daily overview

Only the first eligible daily opening offers a 1.25-second Week overview. The countdown starts after Week is visible and its requested List has been reached. If untouched, the app switches to Today beneath a 0.4375-second fade. Reduce Motion switches directly.

Any touch (including scrolling), text editing, tab departure, protected editor, or loss of active foreground cancels this opening permanently. Normal same-day returns never start the countdown. The countdown is monotonic and in memory; stale callbacks cannot trigger another opening. The fade uses a noninteractive in-memory snapshot, removed on backgrounding; no image is saved.

For manual acceptance, the next first daily opening should show today's List, then Today after 1.25 untouched seconds. Interaction during a later daily opening should keep Week visible. Rebuilding does not reset an already-consumed daily marker; do not erase data or change the device clock to repeat the check.

## Physical-device launch investigation — November 7, 2026

A physical iPhone stopped with `EXC_BAD_ACCESS (code=2)` at `0x16b6cfff0` inside Foundation formatting, reached from `AppRootView.navigationContent`. The supplied backtrace had no recursive cycle. The guard-shaped address and large debug view construction values indicate stack pressure; the formatter location alone does not establish a formatting defect.

`AppNavigationSurface` now defers root navigation and Today/Week/Activity content construction to separate SwiftUI body evaluations. It stores only a builder closure and preserves the original bindings, environments and stable view boundaries. No date formatting, workspace data, or build optimization settings are changed.

On the automated arm64 Simulator, root body value size fell from 19,944 to 2,024 bytes; navigation value size fell from 18,187 to 7,947 bytes. `AppReturnTests.testRootNavigationValueSize` guards an 8 KiB limit for each value. These value sizes are a stack-pressure regression indicator, not a measurement of total runtime stack use. All 16 focused navigation tests passed; the owner must confirm physical-device launch separately.

## Manual Week-template completion — November 8, 2026

A successfully applied Week template now opens the leftmost active List at its top when it creates a Week or replaces an existing Week. Selection follows the stored visual List order, including an undated List before the dated Lists; it does not use today's date or the first-weekday mapping. The owner-specific viewport resets before a cold mount and through the existing scoped reset request for a mounted Board. The daily overview timer is cancelled for this explicit operation.

The preview reports success to its presenter only after checked saving succeeds. After the preview sheet dismisses, the presenter routes to the Week and shows **Week created** or **Week replaced**, with an **OK** button. Save errors retain the preview and show the existing failure message. Day templates, additive edits to an existing Week, ordinary saves and automatic weekly rollover do not invoke this completion flow.

Validation: 21 focused native tests passed, including completion eligibility, visual-order selection, archived/empty List handling, owner-isolated viewport reset, existing mounted Board resets, root-view size limits and template rendering/copying. Manual acceptance remains: replace a Week with a Week template from Library, confirm the completion popup, then verify the leftmost List is visible at its top. No export/re-import is required for this navigation change.


## Eight-hour absence override — November 8, 2026

More than eight elapsed hours away selects Today directly, before the daily Week preview or five-minute tab reset. Exactly eight hours retains the existing behavior. The departure timestamp is recorded only on actual background entry and consumed once on arrival; repeated notifications retain the first timestamp. A normal background/termination/relaunch therefore retains the rule without restoring old navigation. No prior timestamp means existing first-opening behavior applies. Protected work consumes the absence without navigating or scheduling a later jump.

This persisted interval uses absolute wall-clock dates, so changing the clock can affect it; future timestamps do not trigger the override. The existing five-minute in-process timer remains monotonic. Automated tests cover both sides of the boundary, repeated departure notifications, a fresh defaults instance, daily-preview suppression, protected work, and missing/future timestamps.

## Today quick-add preview

Today’s empty or whitespace-only quick-add Plus opens a new Card composer without creating a record. A typed title keeps the inline creation and Week reveal. After the newly created Card has scrolled into view, an untouched Week preview returns to Today after 1.5 seconds using the existing fade and Reduce Motion behavior. Touches, scrolling, typing, protected editors, navigation away, or leaving the foreground cancel that return. Full-editor saves retain their existing navigation behavior. The transient preview adds no persistence keys and does not change the daily opening’s 1.25-second delay.
