# Returning from the Home screen

This device-local behavior applies while the current app process remains alive. Justin selected background returns first; restoring navigation and every unsaved draft after iOS terminates the app is deferred. A fresh process retains the existing launch screen → Today behavior.

| Current context | Less than five minutes away | Five minutes or longer away |
| --- | --- | --- |
| Today | Resume | Resume |
| Open Card/Note, presented editor/sheet, or active inline writing | Preserve the current item/editor | Preserve the current item/editor |
| Week browsing | Same List and scroll positions | First available dated List of that stored Week, at the top |
| Library browsing | Same filter/search/position | All filter, cleared search, top of listings |
| Activity browsing | Same section/search/position | Saved, cleared search, top of browser |

Only the active tab receives a reset. Open work takes priority; there is no deferred timeout reset after its editor closes. Modal contexts are preserved conservatively. Week rollover is not performed while the return guard detects open work. First-day selection follows the stored Week's date mappings, so it respects its actual Monday/Sunday boundary and does not depend on visual List reordering.

The timer begins at `scenePhase.background`, not transient inactivity such as Control Center. It uses `ContinuousClock`, includes sleep, and does not depend on wall-clock/time-zone changes. Repeated background notifications do not extend the interval; an arrival consumes it once. The five-minute threshold itself is inclusive.

`AppReturnBehavior.swift` owns the in-memory policy and scene-specific protection. Scoped reset requests reach the Week, Library and Activity independently. Existing owner-qualified Board viewport memory resets offsets while retaining zoom and presentation choices. Native scroll probes reposition already mounted scrollers; resetting a dictionary alone is insufficient. Inline writing and navigated Card/Note content report protected lifetimes, while the scene-window probe protects modal editors.

No new shared preference, portable schema, cloud field or persistent navigation key is introduced. The only persisted change from a reset is the existing device-local Board viewport state, which is already excluded from shared portable records. User content, backups and recovery history are not reset. The launch behavior does not promise reopening an editor after process termination.

Validation: eight new `AppReturnTests` cases plus four existing viewport/Library checks passed (12 tests). Coverage includes threshold/one-shot behavior, protected departures/arrivals, fresh activation, Monday/Sunday and reordered/undated List selection, owner-isolated viewport memory, mounted horizontal/vertical resets, actual zoomed Week reset and modal detection. Native test evidence: `/private/tmp/plenact-app-return-final.log` (temporary).

For the focused manual check, rebuild Plenact Import Test, browse down a later Week List, return via Home within five minutes and confirm the same position. Then repeat after at least five minutes and confirm the first dated List at its top. Open Cards/Notes and editors should remain open across a return; Library and Activity should follow the table. If iOS terminated the app instead, Today on fresh launch is expected under this first version. No package export/re-import is needed for this navigation-only change.
