# Day schedule overview

> **Data-model context — October 24, 2026:** The [current application/data plan](../Application-Data-Plan.md) supersedes older cloud, ownership and cross-device assumptions below. Model 1.0 is published for iOS/web/Windows; runtime synchronization remains unimplemented. Dated feature/design evidence below retains its original scope.

The dated Day list begins with a scroll-away banner: the saved day intention (if
present), a compact planned-time doughnut, task completion, and a link to that date’s
plan. Existing first-unfinished, restored-position, and newly-created-item navigation
still target the appropriate item rather than forcing the banner into view.

The main ring divides planned task-hours by label. The thin outer ring shows the
planned duration attached to checked tasks within each label. Neither is time
tracking, elapsed time, a productivity score, or a claim about actual effort.
Tapping the chart opens a complete labeled breakdown with durations and progress.

## Accounting

- Only task-format Cards count; Notes, pictures, headings, and dividers do not.
- A task needs a timed start and end with a positive interval. Date-only values and
  incomplete/invalid intervals contribute to task counts but not planned hours.
- Time-only values resolve on the represented date in the planning calendar. A
  reversed time-only interval crosses midnight; equal endpoints are invalid.
- Dated reversed intervals are invalid. Valid intervals are clipped to the local
  day boundaries, including daylight-saving days. This describes items assigned to
  the Day list, not an aggregation of adjacent lists.
- Distinct assigned labels split duration equally, avoiding double counting.
  Missing/deleted labels fall back to Uncategorized when none remain resolvable.
- Overlapping tasks remain additive task-hours; details explicitly disclose overlap.
- A blank day offers guidance instead of manufacturing data. Dates other than today
  use neutral copy and open their own plan.

## Default week examples

The bundled Jmr default week now assigns broad Work, Health, Personal, Home, and
Spirit tags. Catalog loading supplies these stable definitions without replacing
user labels. Bundled routine revision 2 adds missing tags only to known, untagged
Jmr example titles in the reusable template. Custom assignments, other templates,
default-template selection, scheduled weeks, and completion state remain unchanged.
Newly created default weeks can demonstrate the chart; the current user’s schedule
is not silently rewritten.

Tests cover equal splits, duplicate tags, task/Note separation, overlap, midnight,
invalid intervals, default-template upgrade, and light/dark/empty rendering without
plan writes. Final finger interactions remain part of the simulator trial.
