# Day sections: give the day a shape

Plenact helps you give shape to your attention. A section expresses the context or
rhythm that connects a set of items. It may describe time (Morning, Midday,
Evening), a process (Setup, Build, Teardown), or an experience (Prepare, Workout,
Return home). No time range, priority, or prescribed routine is required.

## Ownership and identity

A named divider starts a section. It owns the following content until the next
named divider; items before the first heading remain ungrouped. An unnamed plain
divider remains a visual separator inside its current section. Repeated heading
names are allowed: the divider's stable item ID identifies each section.

The existing `--- Heading` syntax continues to work, and Add section is available
beside content creation in Day, focused List, Board columns, and Gallery layouts.
Tap a heading to rename it. Leave the name empty to return to a plain separator.
Deleting a divider removes only that divider, preserving the existing delete
behavior; it does not delete its contents.

## Presentation and controls

- Optional color belongs to the heading's existing appearance accent. The heading,
  separator line, and thin rail beside member items use it. Card appearance,
  completion, labels, importance, bookmarks, and reactions retain their meanings.
- The section's arrow collapses or expands its contents. The heading stays visible.
  The same setting is available in the divider editor. Collapse is persisted as an
  optional `ItemAppearance.sectionCollapsed` value; older data remains expanded.
- Section options offer color selection and Move section earlier/later. Movement
  carries the heading and all of its content together, including plain dividers,
  retaining every item's identity and metadata. Items before the first section stay
  in place. Native heading reordering also preserves the entire block.
- Individual row reordering is available when sections are expanded; expand sections
  first to avoid ambiguous offsets in the collapsed projection. Whole-section menu
  movement remains available while collapsed.
- Creating content inside a collapsed section expands its owner in the saved
  snapshot so existing scroll-to-new-item behavior can reveal it.

Collapsing is a presentation choice. All records remain in storage, search,
completion totals, and schedule summaries. Today's Focus retains named-section
context across plain separators and does not inherit Day's collapse state. Its
existing grouping and ordering preferences remain in control.

## Optional bundled examples

Plan Settings → Day & Week Templates includes three additional Day templates:

1. **A day in chapters:** Morning, Midday, Evening.
2. **A build session:** Setup, Build, Teardown.
3. **A workout journey:** Prepare, Workout, Return home.

Each has three colored sections and six example items. Apply one explicitly to a
chosen day using the existing Add to existing or Replace workflow. Existing days,
custom templates, and the default Jmr week are not rewritten. Library revision 3
adds only missing example IDs during loading; loading does not write stored data.
Once a user saves the upgrade, deleting an example does not make it return.

## Verification

Regression checks cover named boundaries through plain separators, collapse and
legacy decoding, preserved content and appearance, whole-block reordering,
new-content reveal, Focus context, and example upgrades without rewriting saved
routines. Hosted views are inspected in light/dark mode with accessibility text.
The example templates are also applied to a different day to check their item
order, appearance, and unique identities.

Try on device: create sections, rename and color them, collapse and reopen, move a
section, create content beneath a collapsed final section, and reopen the app.

## Move a section to another Day or List

Use **Move section to…** in the section's options or its divider editor. Choose an
existing Week/Calendar/Plans list, or choose another day with the calendar picker.
A previously unscheduled target week is prepared only as part of a successful
move. The source list itself is not removed.

The heading and everything through the next named heading move as one block,
including completed items, Notes, plain separators, and their retained metadata.
The destination receives the section at its end, with its color and collapse
setting intact. A pending reveal brings the heading into view when that
destination is opened. ID collisions across owners are remapped against active
and archived IDs. Bookmarks, importance marks, active and retained checklist links
(including nested details), and saved Today's Plan priority links follow the items.
Links from moved items back to content left behind remain source-qualified.
Historical review decisions remain historical records.

For Day destinations, **Shift dates to destination day** is optional and off by
default. Dated start/due values shift by calendar days from the source Day while
preserving their relative offsets and wall-clock times through daylight saving.
For a general source List, the earliest dated item supplies the anchor. Time-only
schedules retain their clock values. Without the option, dates remain unchanged.

The entire workspace update is checked and journaled before publication. Calendar,
current Week, personal Lists/Boards, bookmarks, importance, and saved plan priorities
roll back together after a failed write. Older recovery journals remain compatible
and do not clear importance data they never captured.

### Quick Undo

A confirmation offers **Undo** and dismiss, and remains visible across navigation,
sheets, and full-screen views for the current app session. It receives touches
only within its own panel. Dismissal or a later transfer confirmation replaces the
available action; it is not an unlimited history or a restart-persistent journal.

Undo restores original ownership, list order, dates, appearance, links, flags,
and priority data. It checks the affected owners and captured flag/plan data first;
subsequent changes there cause Undo to refuse the restoration and retain current
content. Unrelated owners are left untouched. A newly prepared empty destination
week may remain in the calendar after Undo.

Tests cover cross-owner ID collisions, nested and inactive retained references,
bookmarks, attachment metadata, priority links, exact restoration, conflict refusal,
same-owner moves, keep/shift dates across DST, invalid destinations without mutation,
transaction rollback and legacy recovery, and the chooser/Undo touch boundaries.

### Library discovery

The Library’s **Examples** filter includes a searchable **Day section examples** group with all three routines and their section names. The upper-right **+ → Examples → Day section examples** menu offers the same choices. Preview sections shows the colored headings and member rails without creating content. **Use on a day…** opens the existing Day template preview/apply workflow, including its destination, Add/Replace controls, and confirmation safeguards. Browsing does not change saved templates or scheduled plans.
