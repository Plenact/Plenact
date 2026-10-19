# Today: Current Experience and Planning Rhythm Direction

**Status:** Current UI reference with approved proposed additions, updated October 16, 2026. Today's Plan and the first guided Today's Vision flow are implemented. Today's Review is also implemented. Today's Check-in is now implemented; Weekly Review is now available with saved week browsing; the first Periodic Review flow is implemented

## Current experience

Today is the daily home of Plenact. The toolbar destinations are Today, Week, New, Plans, and Activity. Plans opens a screen titled Library

The main Today experience includes:

- Date, Search, Calendar access, and Account & Settings
- A softly styled daily slogan that scrolls with accessibility and reduced-motion considerations

The Today slogan supports unrestricted horizontal dragging for manual reading, including blank space beyond either end. If released completely offscreen, it reenters from the right when automatic movement resumes. Automatic movement pauses during a horizontal drag and resumes from the released position after one second. Tapping still opens the complete message; vertical dragging remains available to scroll Today. Reduce Motion and accessibility text sizes show stationary, readable text with the same full-message action. Other collection previews retain their existing scrolling behavior.
- Quick capture into the current dated Day List, with a direct add action and full-editor path
- Today's Focus with up to four actionable items and Open today
- Up to six My shortcuts List destinations, configured through Account & Settings
- Browse this week as the route into the broader current-week plan

Tapping the Today date opens Today's Plan. Users choose links to existing Cards and Notes, order/remove priorities, add optional daily context, and explicitly Save. Reopening restores the local day's saved plan; source completion is live. Removing a link keeps its item. Unsaved edits require Save or an explicit discard while the sheet is open. Full daily reviews and automatic draft recovery after termination are not implemented. Day and Week headers have separate date/week pickers for selecting the displayed planning period

Fresh installations offer On the Table, In the Queue, and Scheduled in shortcut order, with one tutorial Card per List. Cards and Notes retain their canonical owners when opened through shortcuts, Search, Activity, or labels

## Proposed daily planning experience

See [Your Planning Rhythm](Planning-Rhythm.md) for the shared product contract

The implemented **Today's Plan** is the foundation for the future saved outcome of Today's Vision. It should show priorities, live source status, and a relevant next action while retaining the current Today screen for fast capture and execution

| Entry | Intended behavior |
| --- | --- |
| Today's Vision | Review existing work, choose priorities, note optional constraints/risks, confirm Scheduled-to-On-the-Table moves |
| Today's Check-in | Glance at progress and adjust the remaining plan without re-entering it |
| Today's Review | Recognize achievements and explicitly carry, queue, schedule, complete, archive, or retain unfinished work |
| Planning Rhythm | Proposed shared page for all five reviews, resumable drafts, and saved history; exact entry control remains open |

Do not add five bottom tabs, open reviews automatically on every launch, or replace Quick capture with mandatory planning forms. Suggested times are optional and user-adjustable; no notifications are part of this documentation change

## Interaction contract

- Reuse the dated week's date-to-List mapping; editable List titles are not calendar identity
- Retain canonical ordering, dividers, ownership, date kinds, rich text, and media
- Quick capture and its full-editor path share the typed title and create one record after an explicit add
- Keep New Card/Note destination selection, Cancel, and draft recovery behavior intact
- Back returns to the actual presenting context, including Search and Activity
- A proposed review move displays its source/action/destination and requires confirmation
- Reference/tutorial Cards and dividers are excluded from automatic unfinished-task processing
- Keep, Leave in place, Pause, and Skip are legitimate review actions
- A missed review must not block starting today or require completing every missed day
- Changes during a review update its live source status without silently rewriting a saved historical summary

## Accessibility and presentation

Keep a stable reading hierarchy with useful labels, comfortable touch targets, Dynamic Type, VoiceOver, contrast, and Reduce Motion support. Color and imagery reinforce identity but do not carry essential meaning alone

Retain the compact landscape lower-toolbar treatment and the keyboard behavior that keeps the lower toolbar anchored at the screen bottom. Decorative backgrounds may extend into safe areas; controls must retain safe-area protection

The default personal List photos and banners do not change dated Week/Day backgrounds. User-selected Appearance colors and backgrounds remain respected

Validate review drafts and navigation with keyboards, both landscape directions, accessibility text sizes, and a physical device before treating a new review flow as accepted

## Acceptance focus

Stage 1 must support planning a day, pausing/relaunching, applying confirmed moves once, and closing the day without losing unfinished work. Later stages reuse this foundation rather than introducing disconnected priority lists

See [delivery gates and scenarios](Planning-Rhythm-Delivery.md) and the [application architecture](Today-View-Architecture.md)

## Today's Vision — first guided morning flow

Open Today’s Plan from Today’s date, then choose Start/Resume/Revisit today’s vision. Three steps cover what is ahead, chosen priorities, and realistic daily context. Save and continue persists progress in the same daily plan; the final step saves a completion timestamp. Back to plan retains in-memory edits; only completed Save actions survive relaunch

Dated suggestions include the selected Day List and active items whose start/due date matches or spans today. Completed and Reference/tutorial items are excluded. Users can choose any other existing Card/Note in step two or create a new one. Movement is separate from selection: a Scheduled item offers an explicit confirmation before moving to an available On the Table List and replacing its priority link with the returned destination identity

The initial transfer action recognizes the default standalone List names. Missing destinations leave items in place. Configurable working-List roles remain future work. Confirmed moves are immediate; leaving the flow does not undo them. If saving the plan after a move fails, its link remains in the open draft and the user is told to review/retry

## iPad Today's Plan panel — October 17, 2026

On iPad, the Today sequence is Today's Plan, slogan/Quick capture, Today's Focus, List shortcuts, and Browse this week. The plan summary replaces the large upper spacer and makes chosen priorities distinct from items in the dated day List. Show saved intention, live status for up to three ordered priorities, optional next focus, and an explicit route to the complete plan. A missing plan prompts “What would make today meaningful?” with Plan today. Saved state comes from the existing daily-plan store; no second plan is created. iPhone retains its existing layout


### iPad lower content spacing — October 17

The iPad plan summary has 36 points of bottom padding before the slogan/Quick capture group, replacing the earlier -24-point overlap. This moves the slogan, Quick capture, Today's Focus, and shortcuts down together by 60 points to restore the lower labels near the toolbar after the compact-header adjustment. In the standard portrait layout, Browse this week starts below the toolbar and remains reachable by scrolling. The iPhone spacing and toolbar geometry are unchanged. Longer plan summaries, larger accessibility text, or additional shortcuts can extend the scrollable content further.


### Launch and return welcome cue — October 17

The cue uses a muted pale-gold tint with a low-opacity fill and diffuse halo. On each process launch, Today softly glows the profile avatar twice, pauses half a second, then glows the Today's Plan heading twice on iPad or the tappable date subtitle on iPhone. A brief initial delay lets Today settle after loading. Within the same process, another greeting is eligible after at least four hours away from the foreground. Inactive/background transitions record one departure timestamp in `Plenact.Welcome.lastDeparture.v1`; brief app switches and returning to the Today tab do not replay a consumed cue. A pending greeting waits for Today to be visible.

Tapping, dragging/scrolling, typing in Quick capture, leaving Today, or backgrounding cancels the sequence. It finishes without repeating or changing saved planning data, toolbar spacing, or target hit areas. Reduce Motion uses one brief static highlight per target without scaling or pulsing. No notifications or mood/plan completion conditions are involved. Launch playback is enabled by default for the initial trial.

The iPhone date subtitle pulses at 1.3× the original speed: fade duration and pulse intervals are divided by 1.3. Profile pulses, iPad plan-heading pulses, the half-second inter-target pause, and Reduce Motion highlight durations retain their existing timing.


### Quick capture actions — October 17

An icon-only Note, Checklist, Photo, Voice, and Drawing row sits below the title input on iPhone and iPad. Each icon retains its spoken accessibility label and 44-point minimum tap height. Each action carries the current typed title into the existing composer and retains the Today destination. Note opens writing-first presentation; Checklist opens a Card with an editable blank action and Add action. Template and full-editor entry points remain available. Cancelling restores the original inline title; no item is created merely by opening an action.

Photo opens a composer with Take photo and Photo library choices, supports up to six images with previews/removal, and retains media when changing Card/Note presentation. Camera access is requested only after Take photo; unavailable/denied access offers explanatory feedback and the library remains available. Photos stay in memory until explicit Add. A checked, journaled save commits the current Week and compatibility Board together; rejected saves retain the draft and clean the new attachment files. The first created Card receives the media/cover when a multiline title creates multiple items, matching existing title-splitting behavior. Hardware camera acceptance still requires a physical device. Voice and dates are implemented below. Drawing replaces the Date shortcut; scheduling stays in the editor.

The extra action row increases the Quick capture panel's height by 52 points at standard text size. That space is reclaimed above capture: iPad summary bottom padding changes from 36 to -16, and iPhone content starts 40 points higher, retaining room for the slogan below the header. Internal spacing below capture and toolbar geometry are preserved. Longer plan summaries and accessibility text can still extend the scrollable content.


### Date and Voice capture — October 17

The capture editor offers independent optional Start and Stop toggles, plus optional times. Stop maps to the existing due date, so dates remain visible in Calendar and item details. A Stop before Start is rejected; date-only comparisons use the local calendar day. Other Today capture modes offer the same dates in a collapsed section. Dates apply to all items created by a multiline title. Typed titles, writing, and destination selection carry forward.

Voice records up to 60 seconds to a temporary AAC/M4A file after explicit microphone permission. Audio, Text, and Both determine whether Add retains a playable local attachment, appends the reviewed transcript to existing writing, or saves both. Styled writing is preserved when appending. Text/Both attempt transcription after stopping while active; retry and editable transcript controls remain available. Recording again explicitly confirms replacement. Speech authorization is requested only for transcription; on-device recognition is requested where supported, otherwise the system recognizer may use Apple’s service and require connectivity. Denied/unavailable recognition leaves Audio and manual transcript entry available. Recording/playback stop on backgrounding. Dismissal cleans temporary recording and cancels transcription; generation checks reject late permission/delegate/recognition callbacks.

Date, Photo, and Voice saves use a typed capture submission and the checked Week/Board transaction. Audio files share the existing attachment directory, backup, retained-reference cleanup, and Card/Note media gallery. Audio is excluded from covers and photo decoding. Saved recordings have a waveform thumbnail and playback controls. The five shortcuts retain a 44-point minimum hit height.

Automated checks cover all capture layouts without requesting permissions, optional date combinations and ordering across daylight-saving boundaries, Audio/Text/Both content selection with styled writing, playable AAC persistence and cleanup on rejected saves, and existing transaction recovery. Live microphone quality, speech availability/permissions, and interruption behavior require physical-device acceptance testing.

### Editable drawing capture — October 17

Drawing replaces the Date shortcut on both devices without changing the action row height. It opens a PencilKit canvas using finger or Apple Pencil, with native tools, colors and widths. Undo/redo and confirmed Clear are in the actions menu. Done inserts the drawing into the pending Card or Note; Cancel discards only after confirmation when changed. The original typed title and destination remain intact. Up to six drawings can be added, edited or removed before Add.

Each saved drawing is a photo attachment with a PNG preview and an optional `drawingFileName` referencing native PencilKit strokes. Legacy photo records decode without that field. Reference retention, deletion and backup include both files. Failed capture commits remove both new files. Editing a saved drawing writes new files before replacing metadata, retaining identity and old files until normal reference cleanup. Opening/rendering does not save.

Saved previews open in the attachment viewer; Edit drawing reopens the strokes. The editor Export menu offers PNG with white or transparent background and JPEG with white background. Exports crop to the marks plus padding and cap the longest raster edge at 4096 pixels. The system share sheet handles Files, Photos and sharing; export never changes the stored strokes. Temporary exports are removed after sharing. Date fields remain available in the capture editor.

Automated checks cover editable-stroke/metadata round trips, dual-file retention and rejected/partial-save cleanup, legacy photo decoding, PNG/JPEG output and transparency, and hosted phone/tablet layouts without saving. Physical finger/Pencil interaction and destination share activities require device acceptance.

### Compact capture and lighter panels — October 17

Quick capture omits its visible heading and “Adding to…” destination caption; the input placeholder provides the context. Its accessibility label and destination hint remain, and a missing destination still shows Choose today's list first. Quick capture and Today's Focus use the shared material panel at 50% background opacity on both iPhone and iPad; text, icons, input controls and other panels retain their existing opacity. Removing the redundant labels lets subsequent Today content move upward naturally.

The iPhone Today content stack adds 50 points of top spacing relative to the compact-capture revision (top adjustment -40 → 10). This moves the slogan, capture, focus and shortcuts down together, bringing the shortcut count labels close to the raised New button again, with a final 6-point upward nudge for a little breathing room. The header, toolbar and iPad spacing are unchanged; content remains scrollable.

### Today focus preview preference — October 18

Account & Settings → Settings → Today provides Items in Today's Focus (1–12 or All open items). The default remains four for new and existing profiles. The setting follows normal profile Save/Cancel behavior, applies to both devices, and controls only the ordered unfinished-item preview. Progress continues to count the whole day. The focus panel grows naturally with longer previews; no toolbar offsets change.


The Today header gear replaces its Calendar shortcut and opens Plan Settings.
The adjacent avatar continues to open Account & Settings. Plan Settings includes
Today preview count/default list, week start, new-card due date defaults, display
preferences, and links to shortcut and template management.

Today's Focus grows to four visible task rows. Higher preview limits scroll only the
task listing; the title, progress and Open today link stay fixed. Row height scales
with Dynamic Type. Both Plan Settings and Profile Settings explain this behavior.

The Focus panel fits its visible content. Compensating padding outside and below
the panel reserves the remaining space up to four rows, including empty and
completed lists, keeping the shortcut icons below it in place.

Tap the Focus completion count to open Today’s list at its first unchecked task.
If all items are complete, the same action opens the list without a task target.

Day options and list actions offer Clear all checkmarks with confirmation. It
resets active card and nested checklist completion only, retaining archived items.
The action becomes Restore previous checkmarks until a checkmark changes or the
user leaves the list. Restore applies only completion flags, preserving other edits.

Focus task titles open the Card or Note directly; its return arrow dismisses to Today.
Checkboxes still toggle completion; progress and Open today still open the Day list.

Focus typography uses separate iPhone/iPad values: task text 18/20 points and
rows 48/54 points before Dynamic Type scaling. Title and tappable progress share
a header row, stacking when space is constrained. The thin progress bar remains
below, with a quieter footer. Four-row scrolling and exterior balancing space remain.

List Appearance and personal List settings include Show icon in title bar. It is
off for ordinary lists and on for On the Table, In the Queue and Scheduled,
including older saved lists without an explicit choice. Explicit choices persist.
The option controls the opened standalone List and Day headers; Library and Today
shortcut icons remain independent.

List Appearance includes a 0–100% background opacity slider and an illustrative
live preview. It changes only the List panel surface behind its cards, revealing
the workspace background at 0%. Cards, text, controls and the independent banner
remain opaque. Existing lists default to 100%; Save/Cancel use the appearance draft.

Library personal List settings expose the same per-list opacity value and preview,
including On the Table, In the Queue and Scheduled. Both entry points edit the
same appearance property using Save/Cancel drafts.

Opened standalone Library Lists also expose this same opacity value directly in
their main Appearance sheet under List surface, alongside the workspace background.

All lists support the header icon option, including custom Lists created in Plans.
The opened standalone List's main Appearance sheet includes visibility and icon
selection alongside opacity. Day headers and Board list headers honor the same
flag; enabled lists without a selected or collection icon use the Notes symbol.

On the Table, In the Queue and Scheduled always show their header icons. Header
icon visibility controls are hidden in Library settings, List Appearance and Day
Appearance for these three names. Other Lists retain editable visibility controls.

Opening On the Table, In the Queue or Scheduled from Plans now uses the same
focused List view as its Today shortcut: shared header, subtitle, card layout,
background and Day options. Back returns to the originating Plans or Today view.
Other collections and targeted Card navigation retain their existing routes.

List Appearance and Library List settings include an independent icon-color picker.
The choice persists with the List and applies to List/Day headers, Board columns,
Today shortcuts and Library List icons. Default follows the collection color where
available. On the Table, In the Queue and Scheduled show a read-only fixed color:
their existing burgundy, teal and graphite identities, independent of saved overrides.

On the Table uses a soft gold header icon for contrast against its burgundy banner.
Its Today shortcut and Library icon retain their burgundy identity.

The central New button creates a Card from Today, Week and Activity, regardless
of the destination List's default item format. From Plans it opens a new personal
List draft in the existing Library creation form. Cancel creates nothing. Existing
quick-capture formats and the long-press Week-list shortcut remain available.

Single-list screens offer View as → Cards / Note List in their options. Day views
apply it to the represented day's list, including past and future dates. Standalone
Library Lists offer the same selection in their options and Library edit form.
The per-list choice defaults to Cards and is shared across entry points. Note List
uses flat separated rows, Card checkboxes, Note symbols, short text previews,
optional dates and cover thumbnails. Row taps open the existing editors; archive,
confirmed deletion, reorder and checkmark reset continue using their canonical owners.
Switching presentation never converts, reorders or duplicates saved items.

Text inputs share a native keyboard accessory with Return, previous/next item,
focused-field undo/redo, attachments, checklist, font/formatting and keyboard dismiss.
Return and Dismiss stay visible; middle actions scroll on narrow screens. Card and
Note editors provide contextual actions; unrelated forms disable unavailable actions.
Previous/Next follows active item order in the same list, skipping section dividers
and stopping at boundaries, synchronizing edits before switching. Week/Board, Day
and direct Today Focus details supply their owner-specific navigation callbacks.
Rich-text areas persist font family, size, bold, italic and color using optional
backwards-compatible run fields; plain titles and specialized inputs stay plain.
New Card drafts also support keyboard checklist creation and photo/drawing capture;
media is committed only when Add succeeds. Formatting changes support undo/redo.


Creating Cards and Notes now publishes a one-shot reveal request for the exact new record (List ID, Card ID, and creation time). Day and single-list screens reveal its row in Cards or Note List mode; Boards reveal the destination column and then its row, and Gallery reveals the tile. Today capture and the central New action open the receiving Week list after successful creation; personal Notes created from the Library directory open their saved destination after the composer closes. Library quick-template capture opens the saved Week. Multi-line entry reveals the first item in the new batch. Existing first-unchecked navigation, ordinary editing, checkmarks, and saved viewport restoration retain their separate behavior. Reveal movement respects Reduce Motion.


All Card/Note creation forms now offer Add Attachment, including list-level and Day creation, Quick Capture/the central New composer, personal List Note creation, and Today's Plan priority creation. The shared source menu supports the same Photos/video, drawing, link, and clipboard sources as existing item details. Users can reopen the menu to add more attachments and remove individual draft entries before saving; picker batches do not impose a total draft attachment count. Existing unavailable source choices remain unavailable. Media remains in the unsaved draft until explicit Add/Save; failed commits remove only files written by that attempt and retain the draft for retry. Keyboard paperclip actions open the same menu. Existing typed camera, voice, and drawing capture actions continue to work alongside additional attachments. New items still reveal their saved destination through the existing creation navigation.


Tapping the Today's Focus title opens the existing Today's Plan sheet, using the same route as the Today date and iPad plan summary. Its touch area is at least 44 points high without adding height to the compact focus header. The completion count still opens the Day list at its first unfinished item, and the Open today footer retains its Day navigation.


Day, single-list, Week, and Board column screens support swiping left directly on Card and Note rows to reveal a red Delete action in both Cards and Note List layouts. Full-swipe deletion is disabled. Delete opens confirmation on the owning screen and delegates confirmed removal to the existing checked persistence callback; cancelling keeps the item in place. Swipe actions are disabled while reordering. Swiping directly on a Card or Note reveals its Delete action; the surrounding Board surface and list headers retain horizontal Board navigation, and long-press dragging remains available.


Within Week and Library Boards, native List pan recognizers receive priority over their enclosing horizontal Board pager. This lets row swipe actions begin before the Board moves, while retaining enabled vertical List scrolling, horizontal navigation outside rows, and native long-press dragging.
