# Today's Focus: give shape to your attention

> Plenact helps you give shape to your attention. Today's Focus honors that shape.

## Product intent

Today's Focus reflects **you**: your chosen sequence, commitments, energy, interests,
contexts, and reasons for acting. It helps you return to the shape you gave today.
Time is one useful signal, not the definition of focus. The most important item,
the most anticipated item, a demanding responsibility, and an opportunity with a
meaningful reward may each deserve attention for different reasons.

Plenact must not reduce those reasons to an opaque urgency score. A person's own
arrangement carries information that a generic rule may miss. There is no single
correct ranking for every customer or every day.

## Current implementation

The initial experience remains one calm list that dwindles as you finish:

| Choice | Initial value | Optional behavior |
| --- | --- | --- |
| Order | Day list order | Chronological |
| Grouping | Continuous list | Day list sections |
| Inclusion filters | All eligible items | Up Next, Important, Bookmarked, or any combination |
| Completed items | Hidden | Keep visible and allow unchecking |
| Item limit | Four | 1–12 or all eligible items |

These preferences persist locally through the existing planning-preferences store,
including installations without an account profile. Missing fields in older data
receive the initial values above. Both Account & Settings and Plan Settings expose
a dedicated **Today's Focus** section with normal Save/Cancel behavior. There is
a small inclusion-filter chooser on the Today panel: tap **Today's Focus** to switch
Up Next, Important, or Bookmarked independently, or choose All items to clear all
three switches. The title no longer opens Today's Plan; the Today date/subheader
still does. The completion count and Open today retain their existing Day navigation.
Choosing a filter applies immediately and persists; other settings retain Save/Cancel.
An active filter label appears beneath the title, and an empty match says “No items
match your Focus choices,” distinct from the entire Day list being complete.

### A user's existing structure is meaningful

Day list order is the default and remains authoritative unless the user chooses
another preview arrangement. Focus derives a presentation; it never sorts, moves,
or rewrites the underlying Cards, Notes, dates, headings, or Day list.

Optional grouping reads the existing Day list section dividers **before** filtering
completed items. Named sections retain their titles and source sequence. Sections
with no eligible items disappear. Items before the first divider use “Before first
section”; an unnamed divider uses “Untitled section.” Repeated heading text does
not merge distinct sections. Dividers are context, never actionable Focus items.

This lets the user express “Must happen,” “Looking forward to,” “Heavy lifting,”
“Family,” or any other pattern using their own words. Plenact does not assign an
importance level, emotional meaning, or ranking to a heading's text.

### Ordering and grouping are independent

Chronological ordering uses a start date when present, otherwise a due date.
Time-only values are interpreted on the displayed Today date in the local calendar;
date-only values use the beginning of their date. Full dates retain their dates.
Equal schedule values keep Day list order; undated items follow scheduled items
and keep their relative Day list order.

With grouping enabled, chronology applies **within** each section. Section order
still follows the Day list. Without grouping, chronology applies across the preview.
This choice does not add an extra overdue boost, create overdue sections,
or change the order as the clock advances within the day.

Chronological rows show a quiet Start/Due label honoring the saved date kind.
The default presentation remains compact and does not add schedule metadata.

### Filtering, limits, and completion

Inclusion filters use **OR**: enabling Important and Bookmarked includes an item
matching either signal, once. With all three switches off, all non-divider Day
items are eligible. These filters do not search other days or Library lists.
Importance uses the existing owner-qualified Library importance store; bookmarks
use the current Week owner's saved-card IDs. Mark important is available in dated
Day/Week Card and Note details as well as Library details. Reused card IDs in other
owners cannot supply a match. Hide completed items remains independent and applies
even to important, bookmarked, and Up Next matches.

**Up Next** includes active schedule windows and schedules still ahead today. Ended
time slots are excluded even when unchecked. A start without a finish remains Up
Next until its start passes; a due-only time remains until due. Date-only targets
remain eligible through their calendar day. Time-only values use today's local
wall clock. Unscheduled items do not match Up Next but can match Important or
Bookmarked. Source ordering remains authoritative unless Chronological is selected;
Up Next is an eligibility filter, not a separate sort. The minute timeline refreshes
schedule eligibility. Explicit importance/bookmarks may retain an ended item when
those switches are also enabled.

Fresh default-week data marks existing Work and Gym entries important after the
initial checked save. Full-month demonstration data marks its existing dinner and
Call the accountant examples important. Demo matching also recognizes the exact
titles Dinner and Call Accountant. This does not add those records to Jmr, rewrite
existing weeks, reapply importance on every launch, or change the user's bookmarks.

Filtering happens first, preview ordering second, and the configured item limit
last. Limits count Cards and Notes, never headings. When grouping is enabled,
the limit may end partway through a section; later sections are reachable by
increasing the limit. This is deliberate, not a quota of items from each group.

With Hide completed items enabled, checking an item removes it and reveals the
next eligible item. With the preference disabled, completed items stay in place
with a checked control and struck-through title; users can uncheck them directly.
Progress always counts all non-divider items in today's source Day list.

Up to four items are visible before the inner list scrolls. Visible section labels
receive additional space instead of squeezing those items. The panel shrinks with
fewer items and preserves the existing padding beneath its section. All-complete
and empty-list messages remain distinct. Card/Note navigation, checkbox actions,
and confirmed swipe deletion operate on the original records through existing
save paths. Nothing in the derived preview owns a second copy of an item.

## Design directions, not implemented promises

The following need further exploration with users and should not be inferred from
this implementation:

- Explicit personal order inside Focus independent of Day list order.
- Grouping or selecting by existing labels, including handling multiple labels
  without silently duplicating an item or choosing one label for the user.
- Deliberate signals for importance, anticipation, burden, risk, and reward.
  First determine whether existing sections, labels, and Today's Plan priorities
  already express the need before adding more fields to every Card.
- An optional, quiet place for missed targets or submitted deliverables in or near
  Focus. No guilt-driven default backlog, automatic carryover, or alerts.
- Different arrangements on different days, saved patterns, and explicit links
  between Today's Plan and Focus. Today's Plan priorities are currently a separate
  feature; this work does not silently promote them into the Focus preview.
- Alternate visual presentations. The current calm list is a useful starting point,
  not a prohibition on exploration.

## Acceptance principles

1. Existing users see the same ordered, unfinished-item preview until opting in.
2. Each optional arrangement has explainable rules and stable ties.
3. Source order and section membership survive filtering and preview sorting.
4. No automatic interpretation of excitement, burden, risk, or reward.
5. Completion is visible or hidden by choice, initially hidden.
6. Detailed settings remain away from daily action; the title offers only a compact inclusion-filter chooser.
7. Preview interactions retain canonical ownership and checked saves.
8. Improvements serve the user's attention, rather than asking the user to serve
   a ranking system.
