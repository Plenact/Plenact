# A teammate for unfinished work

Plenact helps unfinished work become a conscious next choice, instead of something
the user has to keep remembering. A plan is useful when it supports action and
helps the person reconsider what remains when life interrupts it.

## The daily and weekly surfaces

- **On the Table** is the persistent daily working surface. It is not a new list
  created for every date. Keeping a grocery Card for tomorrow records a decision;
  it does not require a duplicate or a move to another Table.
- **In the Queue** holds worthwhile work to reconsider during the weekly review.
  A park date, an unfinished responsibility, or a backburner idea can remain there
  deliberately. The Queue is not required to become empty.
- Dated Day lists still hold scheduled work. Carrying into tomorrow's Day list is
  distinct from keeping an item on the Table for tomorrow.

## Implemented invitations

Today includes a quiet **Planning rhythm** menu below the existing shortcuts and
Browse this week. It offers Review On the Table now, Review In the Queue now, and
Review invitations & reminders. These manual routes remain available at any time.

An evening invitation initially appears from **8:30 PM**, and a weekly invitation
from **Sunday at 6 PM**. Users can independently disable either in-app invitation,
change either time, and choose the weekly weekday. Local wall-clock time is used.
The weekly invitation appears only on the selected weekday, not as a missed-review
backlog on subsequent days. Planning-calendar first weekday determines the reviewed
week; it does not change the chosen reminder weekday.

Review now opens the existing saved daily or weekly review. The daily route opens
Today's Review through its existing plan owner, so draft saving, confirmations,
conflict checks, and cancellation still belong to the established flow. It does not
create a saved morning plan just by opening. The daily review includes its existing
Day-list candidates and deliberately chosen priorities as well as the Table; the
weekly review processes live Queue Cards. These are not new copies of tasks.

Completed reviews suppress that period's in-app invitation. **Later** postpones it
for one hour on Today; **Skip today / Skip this week** suppresses it for that period.
Tomorrow or the next review period starts fresh. Skipping or postponing never moves,
completes, archives, or deletes content. No list must be emptied to finish a review.

## Decisions and deadlines

Today's Review adds **Keep on the Table for tomorrow** for an unfinished item that
still belongs to the active Table. The checked review transaction records a distinct
`keepTomorrow` decision, with the same source and result reference. The source Card
or Note, identity, completion, dates, attachments, and list position remain intact.
The existing Carry into tomorrow action is labeled **Carry into tomorrow's Day list**
to make its different destination explicit.

Weekly Review adds **Bring onto the Table**. It is disabled when the active Table
is unavailable. Confirmation uses the existing owner-aware move and review journal,
preserving details and dates. The existing Queue action from the daily review works
in the other direction. No destination is silently created.

Both review decision lists show existing due dates, even when a normal Card preview
is configured to omit them. Keeping or moving a tax-filing Card does not erase or
extend its deadline. Decisions and sources are persisted through the existing
recovery transaction; failed saves retain the draft and roll back owner state.

Current destination discovery follows the existing default-list implementation:
active standalone Lists titled On the Table and In the Queue. Source actions use
owner-qualified references. Custom role assignment and repair after renaming these
special Lists remain future work; no fuzzy title matching is introduced.

## Optional local notifications

Notification switches are **off initially**, separate from the in-app invitations.
Permission is requested only after the user enables a switch and explicitly saves
Review rhythm. No remote service, APNs registration, or message to another person
is involved. Notifications contain general review copy, never item titles or counts.

At most two repeating calendar notification requests are owned by this feature:
one daily and one weekly, with stable identifiers. Resaving replaces those requests;
disabling removes them. Scheduling never removes unrelated notifications. Dates and
times follow the device's local calendar/time zone. Startup, foreground return, and
saved preference changes reconcile the feature's requests, including example-workspace
switching and restoration.

**First-version boundary:** notification reminders repeat at the chosen cadence
regardless of completed reviews or skipped in-app invitations. Later postpones only
the invitation on Today. The settings form explicitly explains this difference.
Suppressing individual future notifications after a completed/ skipped review would
require a different rolling schedule and is not claimed here.

Denied permission leaves in-app invitations usable and shows a saved-choice message
with a route to iOS Settings. Scheduling errors keep the settings editor open with
an explanation. Permission is never requested merely by opening the app or editor.

Tapping a notification routes to the review for its delivery date. An old notification
can therefore open the earlier day's or week's review, rather than writing a decision
into a different period. The route is retained while an editor or sheet is open and
presented after it closes; an unsaved editor is not forcibly dismissed. Notifications
do not perform any item action themselves.

## Persistence and verification

`Plenact.ReviewRhythm.v1` stores invitation/reminder choices independently of account
profiles. `Plenact.ReviewRhythmDismissals.v1` stores period-specific postponements and
skips, bounded to 64 recent periods. Keys include date/week, time zone, and first
weekday. Read-only opening does not save. Existing corrupt settings are not replaced
by an explicit Save. Full-month backup/restoration already includes all Plenact keys.

Focused tests cover timing boundaries, no Monday catch-up for a missed Sunday,
completed/deferred suppression, independent notification switches, stable request IDs,
local calendar components, route payloads, no task details in notifications, preference
round trips and corrupt-setting retention, skip/later scope, decision persistence,
existing review recovery, and light/dark invitation rendering. Actual iOS permission
prompts and tapping a delivered notification need device/simulator interaction.
