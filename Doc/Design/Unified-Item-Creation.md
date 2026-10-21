# One full Card/Note creation experience

All Add card / New Card routes now use QuickNoteComposer, the shared full-size
Card/Note editor. The old NewKanbanCardSheet form is removed. Board columns,
focused Day/List footers, and their list-action Add commands use ListItemComposer,
a destination-scoped adapter rather than another form. Personal List/directory
Note creation also adapts to this same editor, starting in Note mode.

The common editor supports switching Card/Note, rich text, subtitle for Cards,
attachments, keyboard checklist insertion, start/stop dates, and the existing
capture/template features. Personal destinations map through stable owner UUIDs;
their local numeric list IDs are never used as cross-collection identities.

List-scoped routes retain their fixed target and existing owner/list text draft
keys. Text drafts survive view reconstruction/interrupted dismissal; explicit
Cancel, keyboard Exit, and successful Add clear them. Failure leaves the complete
live editor and media draft open. Optional dates, checklist actions, item kind,
and attachments travel in QuickCaptureSubmission without being discarded.

Creation allocates IDs beyond active and retained records. Board and Day routes
commit owner snapshots before publishing or requesting scroll-to-new-item.
Attachment preparation uses the existing rollback-aware media transaction. Blank,
stale, archived, wrong-destination, and invalid-schedule submissions do not create
records. Existing list defaults and new-card appearance preferences still apply.

Validation covers full-submission materialization, Note/Card differences, personal
List checklist/date retention, invalid schedule rejection, live text draft editing,
shared composer rendering, and media rollback behavior.
