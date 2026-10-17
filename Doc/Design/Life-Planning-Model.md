# Plenact Life Planning and Management Model

**Status:** Current product foundation and approved future direction, updated October 16, 2026. Today's Plan and the first guided Today's Vision flow are implemented; Today's Review is also implemented; weekly and periodic experiences remain approved direction

## Purpose

**Help people turn intentions into action, notice their progress, and begin again with a clear plan**

Lists organize, Cards and Notes hold useful content, and checklist items express manageable actions. People can use undated ideas, personal subjects, or dated plans without adopting a fixed hierarchy of life areas

## Current organizing model

| Concept | Current role |
| --- | --- |
| List | Ordered Cards, Notes, and dividers in a personal collection or dated planning week |
| Board | A collection of Lists with user-controlled order and presentation |
| Card / Note | One canonical record with an action-oriented Card or writing-oriented Note interface; presentation is not a second data store |
| Checklist item | An action within an item, optionally linked or detailed according to existing contracts |
| Today | Daily capture, focus, shortcuts, and access to the current Day List |
| Day / Week / Calendar | Views over local dated planning weeks and their date-to-List mappings |
| Plans / Library | Plans is the lower-toolbar destination; Library is its on-screen title and collection/label browsing hub |
| Activity | Recent work, saved bookmarks, due-soon and label browsing, plus retained-content access |
| Planning Rhythm | Proposed connected review experiences, daily priorities, reflections, and summaries |

Owner context matters: Card IDs are collection-local, not globally unique. Views open or mutate the original item with its owner context rather than copying it into a separate Today or review task store

## The three working Lists

| List | Purpose | Future review relationship |
| --- | --- | --- |
| On the Table | Things the user hopes to accomplish today, time permitting | Morning selection, midday adjustment, evening carry-forward decisions |
| In the Queue | Waiting, unfinished, and repeatedly deferred backburner work worth keeping | Daily deferral and deliberate weekly reconsideration |
| Scheduled | Commitments or tasks with a chosen date or time | Morning candidates and explicit scheduling decisions |

Fresh installations and creation through Starter Lists provide one editable tutorial Card in each of these Lists, with a Reference label, a List-specific subtitle, and a Try it checklist. Existing Lists are not reseeded when emptied. Default personal List banners, Today shortcuts, Library identities, and offline photos provide visual continuity; custom choices take precedence

These names are starting points, not required lifecycle states. Users can rename or remove Lists. Future review setup must use selected identities and offer repair instead of relying on these names as permanent identifiers

Scheduled is a personal List, not an external calendar or reminder service. Being placed there does not assign a date, time, recurrence, or notification

## Planning loop and review direction

Capture → organize → choose a useful next step → act → adjust → reflect → begin again

The [Planning Rhythm vision](Planning-Rhythm.md) connects five moments:

- Today's Vision: choose a realistic daily plan
- Today's Check-in: adjust to progress and changed circumstances
- Today's Review: recognize progress and decide where unfinished work belongs
- Weekly Review: reconsider the Queue and establish next-week direction
- Periodic Review: assess and revise objectives at selected dates or checkpoints

Processing and clearing means giving items deliberate decisions, not forcing empty Lists. Keep and Leave in place are valid. A user should be able to return after missed reviews without review debt, punitive messaging, or automatic rescheduling

Today's Plan now saves daily priorities linked to existing items, together with optional intention, constraints, and concerns. It replaces the static targets preview and shows live item status. Today's Vision now guides morning planning with saved step progress and confirmed transfers. The four remaining review flows, review histories, objectives, and cadence preferences do not yet exist

## Content lifecycle and data boundaries

- A confirmed move changes one canonical item's location while preserving content and relevant links; a priority reference does not create another task
- Personal collections and dated weeks remain separate owners, even when shown together in Search, Calendar, Activity, or a future review
- Date-only and date-with-time values retain their explicit meanings; titles are not parsed into appointments
- Archive retains discoverable content; permanent Delete requires confirmation and persistence before removal is published
- Media cleanup must account for all retained references. Cover selection, hiding covers, and removing a cover are distinct from deleting an attachment
- The full-month example feature saves a verified offline workspace copy before replacement and exposes Restore User Data while active. This purpose-specific local recovery copy is not multi-device sync or protection against device loss
- Reference/tutorial Cards and dividers should be excluded from automatic unfinished-work review candidates; Notes are not presumed incomplete tasks
- Saved reviews will retain dated reflection and decision context separately from live source content, with a deliberate versioned model

## Optional starter and example content

The Library + menu separates New List / New Board, Starter Lists / Starter Boards, Templates, and Examples. Starter guidance and populated examples have different purposes

Ordinary examples create independent editable collection drafts; canceling adds nothing. Full-month examples offer a read-only preview or an explicitly confirmed workspace replacement with offline restoration. Do not describe all examples as append-only or all Load Example flows as equivalent

## Product principles

- Clarity over ceremony: familiar content, visible next steps, and optional structure
- Choice over prescription: no mandatory goal hierarchy, dates, cadence, or empty Lists
- Continuity over duplication: source-owned edits and explicit navigation
- Retention over disappearance: archive is distinct from delete and from backup
- Reflection without judgment: recorded facts and user interpretation are different
- Predictability and accessibility: readable content, comfortable controls, explicit alternatives to gestures, and respect for Reduce Motion
- Honest boundaries: local planning is not external-calendar sync, private cloud storage, or a claim of medical benefit

## Related references

- [Operating vision](Planning-Rhythm.md)
- [Delivery and engineering plan](Planning-Rhythm-Delivery.md)
- [Today interaction design](Today-View-UI.md)
- [Application architecture](Today-View-Architecture.md)
- [Board and scheduled planning](Board-and-Scheduled-Views.md)
- [Board feature guide](../../Src/Features/Boards/README.md)
