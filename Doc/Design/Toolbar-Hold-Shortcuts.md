# Bottom toolbar hold shortcuts

> **Data-model context — October 24, 2026:** The [current application/data plan](../Application-Data-Plan.md) supersedes older cloud, ownership and cross-device assumptions below. Model 1.0 is published for iOS/web/Windows; runtime synchronization remains unimplemented. Dated feature/design evidence below retains its original scope.

Single taps keep their existing contextual behavior: New captures a Card on Today,
opens a personal List draft from Plans, and opens the Card composer elsewhere.
Today selects Today; Week returns to the current Week/day as before.

Holding New opens a native contextual menu with New Note, New Card, New List, and
New Board. This replaces the earlier hold/shake Week-list creation action. The
menu itself creates nothing; choosing an option opens an existing draft form.
Note creation from Plans uses its registered personal-List/directory Note route.
From Today, explicit Card/Note creation starts on today’s Day list. The shared Week
composer elsewhere retains its last-viewed-list destination picker. New List and
New Board open the existing Plans collection form, with explicit kind and defaults.
Cancel keeps content unchanged. Attachment and checked-save paths are reused.

Today and Week use exclusive long-press-versus-tap gestures, preventing a successful
hold from also running tab-selection or Week-reset behavior. A hold opens Today’s
Plan or Calendar respectively, retaining the originating tab. Calendar’s own Week
and Today actions keep their existing destinations. Native menu and accessibility
custom actions expose the same shortcuts without requiring touch-and-hold discovery.

The New menu intentionally follows iOS’s native presentation rather than copying
Awesome Note’s radial layout. Device trial should cover quick taps, successful holds,
canceled holds/drags, choosing/canceling each draft, and returning from the two
planning shortcuts in both portrait and compact landscape layouts.

## Plans and Activity

Hold Plans opens the shared cross-workspace Search directly, preserving its existing
result navigation and query behavior. It does not change the selected tab.

Hold Activity opens Revisit, a compact popover anchored to Activity. It offers
Recently viewed, Bookmarked, and Archived content, with descriptive text and icons.
Choosing a row selects Activity and scopes it to its existing recent shelf,
bookmarks, or archived collections. Search resets on scope entry, and changing scope
starts at the top. All Activity or a normal Activity tab tap restores the full view.
Tapping outside the popover changes nothing. Individual item archives remain in
their owning list/board archive interfaces; this shortcut currently browses retained
collections rather than introducing a new aggregate archive store.

Both controls use the same exclusive hold-versus-tap gesture as Today and Week,
with corresponding accessibility actions. The popover contains no counts, previews,
or completion history; existing history and bookmarks remain canonical.
