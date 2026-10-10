This directory owns Plenact's implemented kanban Board feature: ordered lists organize work, cards represent activities, and checklist items represent actions

## Current Files

- [`ContentView.swift`](ContentView.swift): Board screen, board settings, list/card presentation, member management, and list-target navigation from Today
- [`CardDetailView.swift`](CardDetailView.swift): card details, dates, descriptions, checklists, comments, members, labels, and attachment interactions
- [`Models.swift`](Models.swift): Codable Board models, local persistence, deterministic sample data, and checklist-item migration

The filenames reflect the current implementation. `ContentView` is the Board view in code; renaming and splitting it should be a separate, behavior-preserving change

## Starter Board

When no valid saved Board exists, `SampleData` creates seven ordered lists from Monday through Sunday. Each day contains six realistic planning activities, one divider, one linked-card demonstration, and two Action Detail demonstrations per activity card

Starter data is a first-launch fallback only. Existing persisted boards are loaded unchanged and are not renamed or replaced when sample content evolves

## Ownership

The Board is the current source of truth for lists and cards. `AppRootView` in `../../App.swift` owns the shared list snapshot used by Today and Board, while this feature owns Board mutations and card-detail workflows

Labels and attachments remain sibling features because they have their own models, persistence, and reusable UI:

- [`../Labels/`](../Labels/README.md)
- [`../Attachments/`](../Attachments/README.md)

## Persistence

`KanbanBoardPersistence` stores lists and cards as local JSON under the versioned `Plenact.Board.v1` key. Persisted Codable fields, stable card/list/checklist IDs, and attachment filenames are compatibility contracts

The app loads its initial Board with `loadListsInBackground` and submits normal edits with `saveListsInBackground`. JSON encoding/decoding and UserDefaults access run on a serial background queue, preserving save order without blocking UI animation. Confirmed permanent Week deletion uses `saveListsChecked`, waiting behind earlier queued writes before publishing the remaining content and bookmarks; this synchronous boundary may briefly block interaction on large Boards. Board value models conform to `Sendable` for safe snapshot transfer. A shared busy banner is shown on the app shell, focused Today list, Board/card editing sheets, and Account & Settings. Local persistence errors remain visible until dismissed; stored data is not deleted on a decoding failure.

Revision 0 string checklist items migrate to stable `KanbanChecklistItem` records during decoding. Checklist actions can contain standard text, a stable link to another Board card, or reduced Action Detail content. See [`../../../Doc/Checklist-Actions-Architecture.md`](../../../Doc/Checklist-Actions-Architecture.md) and [`../../../Test/`](../../../Test/README.md)

Do not clear saved data to resolve decoding failures. Add compatibility tests before changing stored models or IDs

## Archived Cards

List Actions includes **View Archived Cards** above **Archive completed cards**. Archiving completed cards moves their complete records into the list's local `archivedCards` collection, retaining IDs, completion state, checklist content, and attachments. Restore returns a card to the end of its original list without unchecking it. Archived cards do not appear in active Board/Today/search results; new card IDs and attachment cleanup include them.

The card detail screen's upper-right **Card actions** menu also includes **Archive Card**, for both completed and incomplete cards. It saves current detail edits, moves the card into its list's archive, and closes the detail screen. This works from the Week board, personal collections, and the focused Today list. Section dividers cannot be individually archived.

Card rows also offer **Archive Card** above **Delete Card** in their `...` menu, both on Board lists and in **Open today's list**. Row archiving uses the same saved archive without opening card details or changing completion status. Existing delete confirmation, rename, and card-info actions remain available.

Older saved lists default to an empty archive, and empty archives are omitted from JSON to preserve the existing remote payload shape. Nonempty local archives are rejected by shared-Board validation because the remote schema does not support them. Copying a list copies only its active cards. Cards removed by the previous archive implementation cannot be recovered.

## Adding Cards

**List Actions → Add card** closes the actions sheet before presenting the new-card form for that same list. The form's Add action creates the card; Cancel leaves the list unchanged. The direct **+ Add card** row uses the same form.

Today's Quick capture square-plus opens an offline Card/Note template gallery. Its six optional starting points and Blank Card/Note choices create only editor drafts until Add is tapped. Card actions are editable; Notes contain writing prompts without action checklists. Template presentation applies to the new record regardless of the destination List's default, without changing that default or any existing records. New records and checklist actions receive fresh identities; no dates, assignments, attachments, or network calls are supplied by templates.

## Optional Title Appearance

Cards, Notes, and Lists can optionally have a full-width header background and a leading icon. Open **Card/Note actions (ellipsis) → Appearance**, **List actions → Appearance**, or **Today day options → Appearance**. The shared chooser previews the current title and offers six named background colors and the existing eight collection symbols. **None** is the default for each choice, and background/icon work independently. **Reset appearance** clears the draft; **Save** applies it, while **Cancel** discards it. The former vertical title-accent bar and its picker have been removed.

**Banner background → Background color** fills the full Card header (including completion, subtitle, and location), Note header (location, title, and creation date), and Board List header (title, count, subtitle, and controls). Card/Note upper navigation bars use the same tint. The Appearance preview title and compact Board/Today Card/Note rows retain their normal backgrounds; optional leading icons remain visible. The focused Today day view colors its entire upper bar with a darker version of the chosen color to retain white-title contrast. Background-only choices need no icon. Other text retains its existing foreground colors; increased-contrast mode reduces soft tints. Default title layout is unchanged when no background is selected. Reset clears all appearance metadata only when saved. The optional `appearance.background` enum is additive: earlier appearance objects decode without it, and nil backgrounds omit the key. Photo and texture backgrounds remain deferred.

Appearance is shown in Card/Note editors, standard/Overview Board rows, focused Today rows, Today Focus, and Board/day List headers. It does not change checkboxes, Card/Note presentation, covers, or Galleries. Decorative symbols are hidden from VoiceOver; titles and the named picker options remain accessible. The existing temporary List panel tint is separate from this persisted header background. Personal collections retain their existing directory color/icon settings; their internal Lists can have independent header appearance.

An optional `appearance` object contains optional typed `icon`/`background` values; the earlier `accent` field remains decodable and retained but is no longer rendered or offered in the chooser. Legacy records decode without appearance and default records omit its JSON key. No storage key, stable identity, media filename, or attachment reference changes. Record edits, Card/Note switches, relocation, List copying/renaming, archives, and both local stores preserve it. No appearance is applied automatically to existing content or inherited by new Cards. Image and texture banners are deferred; existing selected photo covers remain available.

## Optional Card Covers

Card/Note editors use their existing custom upper action row, with the native navigation bar hidden for both colored and uncolored headers. Choosing a background must not insert an empty navigation bar, add vertical space above the buttons, or shift the controls.

Open the card or Note's upper **actions (ellipsis) → Appearance → Card Cover** settings. The upper actions menu no longer has a separate cover entry or Mark complete/incomplete action; the Card header checkbox remains available.

Cover settings retain immediate-save behavior. **Done** returns to Appearance; canceling the Appearance icon/background draft does not undo cover changes. Personal List appearance offers only icon/background options, not Card covers.

In Card and Note editors, the selected cover is shown once as a separate preview, not repeated in the horizontal photo Gallery. Tap it to open its full-photo preview. Other photos remain in the Gallery; videos and links remain in the Attachments grid. If the cover is the only attachment, the Gallery is omitted. This is display-only filtering: the cover remains attached, available in cover settings, and retained in saved content. Removing or changing the cover returns the former cover photo to the Gallery. The Note paperclip browser uses the same separation.

- **Browse Cover Library** offers all 48 bundled illustrations or six category filters with eight choices each. Tap an illustration to select it; Cancel leaves the card unchanged. Earlier photos and illustration attachments remain available.
- **Add Photo as Cover** imports one explicitly chosen photo through the system picker and attaches/selects it.
- **Choose Attached Photo / Change Cover** opens a visual chooser of that card's existing photos. Cancel changes nothing. Gallery photo menus also offer **Set as Cover**.
- **Remove Cover** disables this card's preview without removing its photo. It is also available in the Board/Today card-row menu. No replacement image is selected automatically.
- **Board Settings → Show card covers** hides all Board/Today row covers on this installation without changing selections or attachment records. Card and Note editors retain a selected cover's preview; cover setup controls and explanation live only in the actions-menu settings sheet. Uncovered items show no cover section, empty preview, or setup prompt. Notes keep cover setup out of their writing area and Details.

The shared [photo Gallery](../Attachments/README.md#photo-gallery) supports adding/removing photos, optional bottom-overlay captions, drag-and-drop order, and accessible menu/native-list reorder alternatives. It edits the same canonical attachment records through complete Card/Note synchronization, without duplicating media or changing retained attachment identities.

Standard and focused Today rows use a 128-point decorative cover; Overview uses 72 points. Titles, completion, badges, and menus remain available. Media is downsampled off the main actor to at most 960 pixels on its longest edge. Missing/invalid images show **Cover unavailable**, not another photo or a network fallback.

The optional `coverAttachmentID` references an existing photo attachment UUID. Older saved cards decode without a cover, nil selections omit the new JSON key, and neither storage keys nor existing filenames/IDs change. Removing the selected attachment also clears its cover; deleting an unrelated attachment does not. Videos, links, missing IDs, and dividers cannot be selected as covers. Archive/restore, list copying, renaming, and detail synchronization retain the selection. Superseded or removed cover-import requests cannot re-enable a cover when their photo transfer finishes.

Three new starter-Board cards and the first card in **On the Table**, **In the Queue**, and **Up for Brew** demonstrate original bundled illustrations. Example previews/drafts create no personal media files; most cards stay text-only. Existing saved Boards/collections are not changed or retrofitted. Load Example keeps its existing explicit replacement/undo behavior. Bundled illustration references are separate from deletable Documents filenames. The dormant shared-demo seed omits local covers/illustrations and its existing server contract is unchanged.

The example Week Board also includes three editable, three-photo Galleries: **Monday → Review the week ahead**, **Friday → Plan the weekend**, and **Saturday → Spend time outdoors**. Eight photos have optional captions; the final outdoor photo demonstrates an uncaptioned image. Monday's existing cover remains separate. All images reuse offline bundled artwork without writing personal media files. These appear in newly initialized examples or after the owner's explicit **Load Example** action, not as an update to existing saved Boards. Load Example replaces the current Week Board and retains its existing undo snapshot; it should not be used merely to retrofit Galleries into personal work.

Open **Library → + Examples → Load Example Week View** to load the Week example. Its separate Week section explains the replacement and requires confirmation; the six personal List examples still open unsaved drafts without replacing Week. **Undo Last Load** appears in the same chooser when a retained snapshot is available, including snapshots saved by the former profile-settings entry. Undo also requires confirmation because it replaces edits made since loading. Both actions save the replacement Week snapshot before updating app state; failed saves report an error, and a failed restore keeps its undo snapshot for retry. Personal collections remain unchanged. Today resolves the current weekday from the updated canonical Week records.

Selecting a personal List closes Examples and opens its unsaved draft. A successfully confirmed Week load or undo also closes Examples; canceled confirmations and failed operations leave the chooser open.

This is a local presentation feature, not remote media storage or backup. See [attachment boundaries](../Attachments/README.md) and [cover validation/device acceptance](../../../Test/README.md).

The library uses the existing typed bundled-image field rather than a new storage format. Repeated choices reuse the card's attachment identity. Its 48-image catalog does not change the three seeded demo selections. Color customization and automatic recommendations are not implemented.

## Board Presentation

**Board options > Board presentation** and **Board Settings > Presentation** offer **Standard** and **Overview**. The preference is stored locally, shared by Week and personal collections, and does not change Board JSON. Standard uses columns up to 360 points wide with supporting card summaries; Overview uses columns up to 240 points wide and omits subtitle/label summaries. Cards fit their displayed content with minimum heights of 112/80 points, scaled for Dynamic Type on Board lists. List titles have a separate header row; card actions sit beside the badges rather than squeezing the title. Both landscape directions and portrait are declared for iPhone.

At accessibility text sizes, columns expand to the available width, titles are not line-limited, and badges stack. Controls are not scaled down. The focused Today list keeps Standard-style content-fitting cards. See [Board Presentation](../../../Doc/Board-Presentation.md) for context-preservation boundaries and device acceptance checks; a continuous zoom slider is not implemented.

## Reordering Lists

Touch and hold a list's title/header text for about half a second, then drag horizontally to reorder it. The held list lifts visually and gives selection feedback. Holding within the left or right edge of the board viewport moves it one position in that direction every 550 ms and scrolls it into view, allowing a restored list to travel across the entire board. Release to finish; the existing Board persistence path saves the updated order.

Only the title area starts a list drag; card-reordering controls and list action buttons retain their existing behavior. Ordinary swipes before the hold threshold still scroll the board. Reduce Motion disables the lift scaling and reorder animations. **List Actions → Move list → Move earlier / Move later** remains available, with equivalent VoiceOver actions on the title. The same behavior applies to Week and personal boards.

For Boards with more than one active list, **Board options** offers **Jump to First List** and **Jump to Last List**. You can also swipe left or right on the Board title/subtitle area, including the unused header space beside it: left jumps to the last active list; right jumps to the first, matching ordinary horizontal content scrolling. The swipe region fills the available width between the back control (when present) and the trailing Board controls, with a minimum 44-point height. The title-area drag has priority over competing view gestures but does not cover the back, calendar, add, or options controls. It ignores short or mostly vertical drags. Both methods animate to the current endpoints without reordering or editing content. The title's accessibility hint describes the gesture, and the Board options menu remains the accessible direct-action alternative. On the Week Board, the endpoints are the first and last weekday lists when the default order is retained; on personal Boards, they are the current endpoints.

## Notes and Cards: One Record, Two Editors

Each item has its own **Card** or **Note** presentation. A Note is the same local `KanbanCard` record, not a separate Notes store. Opening it through existing item navigation uses a writing-first title/body editor; its List label begins 20 points closer to the top controls than the original uniform 20-point inset, while retaining horizontal and bottom padding. **Show Details** exposes its retained dates, labels, members, checklists, covers, and activity. Attachments remain available in the Note view. Text changes use the existing complete-record update callback and caller-owned local persistence.

Use the item's row **Display as** menu or detail **actions → Appearance → Display as** chooser to select **Note** or **Card**. This changes only its interface, in place: identity, title, body, completion, dates, checklists, comments, assignments, labels, bookmark IDs, covers, and attachment filenames remain intact. Note rows show a note icon instead of a completion checkbox. Converting an existing Card with no written description does not turn its generated display copy into a Note body.

New personal Lists initially create Notes by default. Their bottom Add action follows the chosen Card/Note default, which is configurable through **List actions → Edit list → New item default** or **Library → Edit Collection → New item defaults**. Reopening a List preserves that choice. Personal Boards and Week Lists also support per-List Card/Note defaults; changing a default affects only subsequently created items. New Notes start with an empty body and no synthetic checklist groups. Divider-marker titles remain dividers. While an actual personal List is open, the center **New** button opens a blank, writing-first **New Note** draft for that List. From the Library directory, **New** opens the same Note composer, targeting the most recently opened active personal List; if none has been opened, it targets the first visible active personal List. **Save** requires a nonblank title and persists the Note before publishing it; **Cancel** discards the draft. Body whitespace is preserved. If Library contains no active personal List, the app explains that one must be created first. Personal Boards and other destinations keep the existing Week-card composer behavior.

In the **New Note** composer opened from Library or a personal List, tap the List name above the title to choose any active personal List. The initial List remains preselected; selecting another changes only the unsaved draft's destination, not any stored content. **Save** creates one Note in the selected List; **Cancel** creates nothing in either List. A failed Save retains the selected destination and text for retry. If the selected List becomes unavailable, choose another active List before saving; the composer never silently redirects the draft. Week and personal Boards are not destinations in this picker.

In a personal Note, tap the List name above its title to move that same Note into any active personal List. The move saves the complete record and bookmark change together, leaves the Note editor open, and updates its location label. IDs are local to each collection: the existing ID is retained unless the destination already uses it, in which case the move assigns the next unused destination ID. Attachments stay with the record; deletion cleanup continues to check all remaining collection, Week, archive, and undo references.

The saved **Note** editor has a bottom toolbar: **Back**, **Details**, **Attachments**, **Share**, and **Add**. Back returns to the presenting view. Details toggles the retained fields and scrolls them into view without converting or rewriting the Note. Attachments opens the current thumbnail gallery and the existing attachment-add flow; attached thumbnails also remain in the writing view. Share opens the system share sheet with the current title, written body, and attached web links; Messages/Mail availability depends on the device. It does not include local photo/video files, list identity, checklist details, comments, members, labels, or profile data, and does not send anything automatically. Add offers the existing checklist, date, and comment actions, not creation of a separate Note. The bookmark remains only in the upper toolbar. Card-style editing and the explicit-save New Note composer retain their existing layout.

Newly created items record an optional `createdAt` timestamp, displayed beneath the title in both the New Note composer and saved Note interface using the device's locale and time zone. New Note captures this time once when the draft begins; editing, choosing another List, and retrying a failed Save keep the same displayed time, which is passed unchanged to the saved record. Cancel persists neither the draft nor its timestamp. Both interfaces share the same adaptive date label, and the composer scrolls to keep fields accessible with larger text or the keyboard open. The timestamp is independent of start/due dates and retained through editing, Card/Note conversion, movement (including ID collisions), copying retained content, and archive/restore. Older and synthetic example records without a known timestamp remain undated; opening or converting them does not invent one. The optional key uses the existing Codable date representation and is omitted when unknown. There is no backfill, storage-key change, or launch-time migration. Sharing text excludes the timestamp. Older builds ignore the new optional key but may discard it on subsequent writes; this affects only creation metadata, not the existing content.

**Compatibility and recovery:** presentation is stored as optional `itemPresentation` on items and `defaultItemPresentation` on lists. Missing keys mean Card; default Card keys are omitted when saving. No bulk rewrite, storage-key change, or destructive migration runs at launch. Invalid nonempty presentation values fail decoding rather than silently selecting an interface. Archive/restore and collection rename retain both preferences. To return an item to its Card interface, choose **Appearance → Display as → Card → Save**; to stop creating Notes, change the list default to Card. Neither action deletes content. Older app versions do not understand these preferences and may discard the interface choices when saving, although established content fields remain the same; downgrading is not an interface-preserving recovery mechanism.

**Deferred:** relocation between personal collections and the Week Board is not implemented. The existing Move action still targets lists within the owning Board; the Note location menu targets only personal Lists. Conversion does not copy, delete, upload, or move the item.

## Calendar Navigation

Calendar result taps open the exact selected Card or Note after the Calendar sheet dismisses, rather than merely revealing its containing List. Navigation resolves the current record by both List and Card ID within the displayed Week or personal Board. If the record is no longer active in that List, an error is shown without opening a different record or changing content. Device acceptance: select start-date and due-date results in different Lists, including multiple results on one day; confirm the correct detail opens and Back returns to its containing List. Repeat in a personal Board.

## Editing List Titles and Subtitles

Use **List actions → Edit list** in Week or Library, or **Day options → Edit list** in the focused Day view. The form edits a draft; Cancel/dismiss does not save. Save requires a nonblank title and permits an empty subtitle to hide supporting copy. Changes use the existing local persistence paths and retain IDs, active/archived cards, dividers, bookmarks, attachments, and creation defaults. A single-list Library collection's directory title follows its edited List title; multi-list Board titles remain independent.

List `subtitleOverride` is an optional Codable field. Older snapshots without it retain generated subtitles and omit the field on save until the subtitle changes; an explicit empty string hides the subtitle. No destructive migration, storage reset, or media operation is needed. List copies and collection renames preserve the override.

Weekday routing remains title-based by product choice: renaming “Thursday” to “My plans” makes it an ordinary List. Today recreates a blank Thursday List when needed, preserving the renamed List and its work.

## Dragging Cards Between Lists

In Week or a personal Board, **hold the Card, Note, or divider itself**, then drag it to another list or another position in its current list. iOS provides a native row preview; the destination list is outlined and a line marks the insertion boundary. Drop on an empty list to add its first record. There is no separate drag handle. The focused Day list supports the same long-press reordering within that list.

Hold near either horizontal screen edge to scroll to neighboring lists every 550 ms. This scrolls the viewport; it does not reorder lists. Scrolling the source list offscreen does not cancel the active drag. Release on the highlighted destination to move the original card. Hovering never edits or saves content. Releasing outside the Board, losing the gesture, leaving the Board, backgrounding, rotation, or a presentation change cancels without moving it.

The row has a native `UIDragInteraction`; each list's underlying collection view has one shared native drop receiver, registered for both `UIDropInteraction` and collection-view drop callbacks. Visible card/divider/Add card rows install and update that receiver, so it does not depend on Add card being on-screen. Ordinary taps, completion controls, swipe deletion, and menus remain available, but their physical interactions need acceptance testing with the native drag installed. Card accessibility actions offer **Move to [list title]** directly. Native List reordering is disabled outside explicit **Reorder cards** edit mode; in edit mode, cross-list sources/receivers are disabled and the original collection drop delegate is restored for within-list reorder controls. **Card detail → Move to List** remains the non-drag alternative. On long lists, scroll to the desired vertical area before beginning the drag; custom edge scrolling is horizontal.

The drag item contains only a random local Board token, not card content or attachment filenames. Its representation is restricted to this process and the native session is restricted to this app. The drop receiver validates the native item's local source coordinator, active session, and matching Board token before invoking canonical movement. The correctly registered `dragInteraction(_:session:didEndWith:)` callback cleans up cancellation or release outside a valid target. A retained local coordinator lets a session finish if its source row leaves the viewport.

Drop detection compares the finger, Board viewport, list panels, and card rows in the same global screen-coordinate space, and validates the final release point before moving the canonical record. Movement preserves card IDs, covers, attachments/filenames, descriptions, dates, completion, assignments, labels, checklists, comments, and Board-local bookmarks. Only position and the destination list title change. The existing Week/personal persistence path saves the result; no new format or media operation is introduced. Archives are not draggable, and dragging never moves content between separate Boards or sends it to a service.

Automated model, persistence, geometry, and hosted-layout checks are documented in [Tests](../../../Test/README.md). Touch gestures, edge scrolling, cancellation, and VoiceOver still require hands-on acceptance.

## Archived Lists and Boards

The board's **Board options** (`...`) menu provides **Board Settings**, **View Archived Lists**, and **Archive Board** (for the Week Board and personal boards). List archiving sets a backward-compatible `isArchived` marker on the original list rather than deleting it. **View Archived Lists** restores lists to the end of their original board, preserving list/card IDs, archived cards, completion, and attachments. Archived lists are hidden from Today, active searches, card counts, and navigation choices. New IDs and attachment cleanup still account for archived content. Existing snapshots without the marker remain active; archived lists cannot be published through the current remote schema.

**Archive Board** asks for confirmation and keeps the complete local board, including archived lists/cards and bookmarks. Personal lists can also be archived from their collection menu or Library row. Archived collections are hidden from Library and shown in **Saved → Archived Collections** with Restore and Delete actions. Restoration returns a personal collection to Library with a unique title, without changing its contents. Archived Week Boards restore as separate personal boards named **Week Board (Restored)**, **Week Board (Restored) (2)**, etc.; the current Week Board is never replaced. Archiving the Week Board leaves an empty Week workspace for new lists. Archived collections retain attachment files.

Personal-board archiving persists the complete updated collection snapshot before changing the in-memory archive flag or dismissing the board. If encoding fails, the board remains open and active, the previous stored snapshot is unchanged, and an error banner is shown.

The app root shares the personal-collection state between Library and Saved and persists the complete Week snapshot, including archived lists. Archive flags and content are stored together, so active-only views cannot overwrite the archives. Loading Example replaces active and archived Week lists together; Undo Last Load restores both.

## Product Boundary

### Today's Focus

Today's Focus automatically resolves the active Week list whose title matches the current local weekday (Sunday through Saturday, ignoring case and surrounding whitespace). It has no Change control or redundant weekday title. The minute-based timeline refreshes across midnight; it projects canonical Week records rather than maintaining another card store. Opening or completing a preview card acts on that day's list.

If the day's list is missing, renamed, archived, or ambiguous, the panel shows **No list for today.** with no card checkboxes, completion count, progress bar, or list-opening action. It never substitutes another weekday. Quick Capture and its existing destination preferences remain independent and unchanged.

### Archive and permanent deletion

**Archive retains content; Delete permanently removes it.** Archives are not backups. Every new permanent-deletion entry point asks for confirmation and describes the affected content. Deletion has no undo guarantee and never deletes an independent retained Board/collection copy.

| Content | Active entry points | Retained-content entry points |
| --- | --- | --- |
| Card | Board/Today row actions and detail; Search, label results, Calendar, and Saved bookmarks through context actions | Archived-card rows/details; cards within archived lists and Saved archived collections |
| List | Board List Actions; Today picker and Search row context actions | View Archived Lists rows and retained-list detail; lists inside archived collections |
| Personal Board/list collection | Collection menu and Library row context/swipe actions | Saved Archived Collections rows and contents menu |
| Week Board | Week Board menu: Archive Board or **Delete Week contents** | Its separate archived copy has normal collection deletion in Saved |

Deleting a list includes its active and archived cards. Deleting a collection includes every retained list/card and that collection's bookmarks. Deleting a card removes only its owning Board's bookmark; equal numeric IDs in other collections are unrelated. Section dividers have Delete controls but are not individually archivable.

The Week workspace/tab is permanent. **Delete Week contents** clears its active and archived lists/cards/bookmarks without removing Week or replacing/deleting separate personal or archived copies. Load Example's previously retained undo snapshot is also separate and remains protected.

Library organizes personal lists and Boards, including separately restored Week archives, and offers a compact **Saved Items** bookmark button beside Edit and Create. The button switches to the existing Saved tab for bookmarked cards and archived collections; it does not create, copy, or persist a collection. It remains available during Library search and editing, outside the reorderable personal rows. The current Week Board is accessed through the dedicated Week tab, not a duplicate Library section. Library search matches personal collections only. Week records still protect shared attachment references when editing personal collections; hiding Week from Library never removes or migrates its data.

Tapping the lower toolbar's **Week** destination returns to the Week Board root even when Card Detail is already open in that tab. It preserves the current list position and canonical card edits; ordinary card/list navigation requests continue to open their specific destinations.

Production deletion persists the complete remaining snapshot before publishing removal. A failed checked save reports an error and retains the canonical content. Card detail keeps the editor/drafts open if deletion fails; successful deletion suppresses delayed editor synchronization and photo imports so stale details cannot recreate content. Archive inspectors are read-only and do not synchronize stale card snapshots.

Media cleanup considers only filenames referenced by the removed content, and runs after a successful save. Current and persisted Week/collections, nested archives, and Load Example undo references protect shared files. Unrelated files are not scanned or removed. Unreadable retained snapshots block cleanup and produce a notice; file removal errors are reported. This is reference-aware local cleanup, not secure erasure, a complete orphan sweep, or a backup/recovery system.

Compatibility fields, stable IDs, attachment filenames, and storage keys are unchanged. The known corrupt-data fallback/recovery gap is not resolved by these controls.

The Board is local to this app installation. Members are currently free-text assignments rather than accounts. A future registered-user directory and typed card-assignment model are described in [`../../../Doc/Users/README.md`](../../../Doc/Users/README.md); they are not implemented. The feature does not provide cloud synchronization, shared permissions, calendar synchronization, or a remote database

## Future Modularization

Keep this directory flat while the files remain easy to scan. Likely future extractions from `ContentView.swift` include:

- `BoardView.swift`
- `BoardSettingsView.swift`
- `KanbanListView.swift`
- `KanbanCardView.swift`

Extract these incrementally with focused tests and builds. Avoid adding `Views/`, `Models/`, or `Components/` subdirectories until the number of files makes those divisions useful

## Mixed item display formats

Each canonical `KanbanCard` can be displayed as **Card**, **Note**, **Divider**, or **Picture**. Open its detail ellipsis → **Appearance → Display as** and Save. Cancel discards the display/icon/background draft. Row menus also offer **Display as**. Divider details have the same Appearance menu; focused Today dividers now open their detail screen.

Picture rows in standard/Overview Boards and focused Today Lists use the explicitly selected Card Cover at its natural aspect ratio, independent of the optional ordinary-row cover visibility switch. Picture rows have zero internal padding and no visible title/footer or ellipsis; the image fills the rounded row at its natural proportions. Tapping opens the same record, where editing and Appearance remain available. Stored titles and captions identify the image to VoiceOver. Without a selected photo, **Choose picture** opens the existing Appearance/Card Cover path in detail. Missing bytes show **Picture unavailable**. There is no fallback photo, second media store, file operation, or upload. Picture detail retains the Card editing controls; its list row omits activity badges and completion controls.

The optional `listDisplayFormat` Codable field overrides legacy `isDivider`/dash-title rendering. Missing metadata preserves old Card/Note/divider behavior and omits the new key. Explicit Card/Note choices allow a legacy `---` record to change format without renaming or clearing hidden content. Divider display retains dates, completion, checklists, comments, bookmarks, and cover/attachment references, while keeping existing separator exclusion from activity projections, counts, and individual archiving. Switching back reveals the retained record. Copies, relocation, rename, archives, Week persistence, and personal persistence retain the override.

Every List has a **Card/Note new item default** in **List actions → Edit list** (or focused Today → Edit list). Personal collection editing exposes the same choices. New personal Lists initially default to Note; reopening them no longer forces an explicitly chosen Card default back to Note. Changing the default does not convert existing items. Divider/Picture are deliberate per-item choices. Reset appearance clears only icon/background decoration; it keeps the chosen display format.

Hands-on acceptance remains necessary for mixed-format row navigation and gestures, Display as Save/Cancel, divider conversion, Picture cover imports/nested sheets, VoiceOver, relaunch, and layout at device/accessibility sizes.

The local starter Week and **Load Example Week View** include three Picture examples: Tuesday’s **Capture a new idea** (Writing notes), Wednesday’s **Take a walk** (Forest path), and Sunday’s **Capture notes and ideas** (Flower bouquet). They retain their activity text/actions and use bundled, offline cover references. Existing saved Weeks are unchanged. Loading the Example Week is still a confirmed replacement of the current Week, with the existing local undo snapshot; personal collections stay unchanged. The dormant shared-demo seed excludes these local Picture choices along with their media.

List actions groups ordering, alphabetic sorting, copying, and movement at the top. Archive and deletion controls use a compact footer. List background now lives in Appearance and persists as optional listBackground metadata independently of Banner background; Default clears only the panel tint, and Save/Cancel applies or discards the draft. Existing Lists without this field keep the neutral panel. Copies and archived Lists retain their Appearance.

Board options → Appearance sets independent List banner and panel defaults. Week stores its local theme under Plenact.WeekAppearance.v1; personal Boards store optional boardAppearance within their own collection snapshot. Existing data without theme metadata keeps its prior rendering. Explicit List colors override Board defaults, and new Lists inherit dynamically. List Appearance offers Use Board default; the panel’s Default option explicitly overrides a colored Board with neutral. Apply to all Lists clears only banner/panel overrides across active and archived Lists, preserving icons and content. Save commits the draft; Cancel makes no changes. Week Day headers resolve the same banner defaults. These preferences remain local and do not change the shared-demo schema.

Board Appearance also offers optional Card background: soft panel tints for Card and Note rows in Week, personal Boards, and the Week Day view. It persists with the Board theme, leaves per-item banner metadata untouched, and does not tint Picture rows or Dividers. Default restores the adaptive system card surface; legacy themes without cardBackground preserve that surface.

List actions → Switch to Day View focuses any active List, including custom Lists, using the same live content and Board theme. The actions sheet dismisses before the focused screen opens. Day options → Switch to Week View returns to that List in Week; personal collection Lists return via Switch to Board View. Today’s existing entry and return remain available. The initial List actions height accommodates the additional navigation row.

Today’s Open today’s list entry initially scrolls to the first unchecked Card in saved order, skipping Notes, Pictures, Dividers, and completed Cards. Completed or empty Lists open normally at the top. This is a one-time opening scroll, not a filter or reorder; completing a task never triggers another automatic scroll. Day entry from Week/Boards retains the normal top-of-list opening.
