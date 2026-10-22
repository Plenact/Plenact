# Examples and Today's Focus

Today's Focus reads today's canonical Day list with the user's existing filters.
A standalone Library List or Board is not automatically part of that Day. Applying
a template to another date affects that date, not today. Loading examples does not
silently switch Focus to All.

## Bundled demonstrations

Bundled Day/Week templates include optional `PlanningExampleFocus` metadata. It
identifies example items for Important, Bookmarked, and an all-day Up Next example.
Application remaps those identities beyond active and archived IDs. An explicitly
marked untimed example receives a date-only due date on its destination Day, so
Up Next remains meaningful through that day. Existing scheduled times are retained.
The Jmr routine retains its timed schedule: Work/Gym demonstrate importance and Gym
is bookmarked; Up Next can legitimately empty after that day's activities end.

Captured custom templates have no demo metadata. Their unscheduled items do not
receive invented dates or importance marks. Template bookmarks, when present, are
remapped into the destination collection. Applying a built-in example explains
its Focus markers before confirmation.

Library revision 4 adds metadata to recognizable bundled layouts in memory. It
preserves custom-named or changed layouts and does not rewrite stored templates,
scheduled weeks, or current user content during loading. Metadata affects future
explicit applications only.

## Saving and refreshing

Previewing remains read-only. Explicit application saves the calendar, current Week,
bookmarks, and owner-qualified importance marks in the same checked transaction.
Current bindings and AppStorage then refresh Focus without replacing its saved
filter configuration. Focus uses the planning calendar for date-sensitive matching.
New weeks generated from a marked default template carry their mapped flags too.

The legacy Load into current Week action now uses the dated Work Week template
application instead of assigning raw starter lists. Undo includes the original
week, bookmarks, and current owner's importance marks. Legacy undo records remain
readable.

The full-month demonstration includes unfinished Important, Bookmarked, and all-day
Up Next items for today. It preserves existing Focus filter/display choices while
retaining the dataset switch's existing reset/backup behavior for other settings.
Restoring User Data restores the original preference domain and files.

## Valid empty states

Completion, expired scheduled activities, or a deliberate filter can still produce
no matches. Focus explains that no unfinished items match the filters and offers
Show all items as an explicit user action. It never fills itself from unrelated
Library examples or silently changes filters.

## Checks

Tests exercise every filter combination late in the day (including a DST date),
custom templates without injected dates/flags, ID remapping, preserved month Focus
choices, complete week undo, bundled metadata migration without writes, and month
backup restoration.
