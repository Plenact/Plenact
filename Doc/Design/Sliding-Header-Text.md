# Slide to read long headers

Long names should remain readable in their current context. Borrow the Today
slogan's direct manipulation, with no automatic movement in working headers.

## Initial scope

- Card detail title and subtitle, independently.
- Card/Note list-location labels.
- Focused Day/List title bars and standalone List subtitles.
- Board title bars and subtitles, including the tappable Week selector.

The Note editor's title already expands across lines and keeps that behavior.
Board-column headings, Card/Note row previews, gallery tiles, and Today's Focus
rows retain their existing layouts and gestures in this first pass.

## User preference and Library rows

**Scroll overflowing titles and subtitles** is available in Plan Settings → Display
and Account & Settings → Accessibility. It starts enabled, including older saved
profiles. Save/Cancel follows the surrounding editor. The canonical local planning
preferences store also supports users without a profile.

Turning the switch off replaces these header readers with single-line text and
trailing ellipses. Full accessibility text and tap-to-edit/menu actions remain.
Mounted readers update immediately on a saved preference change; Board header
boundary swipes become available again when the readers are disabled. This setting
does not change the Today slogan's behavior or turn Card-row gestures into readers.

Library directory names use at most two lines at ordinary text sizes to keep one
long name from dominating the list. Accessibility sizes retain full wrapping and
the existing stacked count layout. VoiceOver retains the complete name. Directory
rows do not gain horizontal readers in this pass.

## Behavior

`SlideableHeaderText` uses a native horizontal ScrollView only enabled when its
full text exceeds its measured viewport. Font, color, Dynamic Type, and baseline
height follow the surrounding header. Short text stays still. There is no timer,
auto-scroll, or delayed reset. User-driven scrolling has native momentum and edge
bounds; the position remains while that reader stays mounted. Changing the text
resets its reader. Leaving/recreating a screen may reset its reading position.

The Card location/move control sits in the upper toolbar immediately before the
bookmark, leaving the title row its full available width. The Note location retains
its existing position above its expanding title.

Titles and subtitles own separate reading positions. VoiceOver receives the full
text as one accessible element; a drag is not required to hear clipped content.
Optional tap actions remain available through accessibility activation. No model,
source date, sort order, or persisted preference changes while reading.

Card title/subtitle taps enter the existing editor, including its focus, keyboard,
capitalization, submission, and checked-save callbacks. Scrolling is a reading
action; no keyboard should appear after a horizontal drag. The subtitle placeholder
remains directly editable when empty. Editing stops on the normal Done/dismiss path.

The Board title region previously accepted swipes to jump to the first/last column.
When either header line overflows, its parent boundary swipe yields to subview
readers. First/last navigation remains in Board options. Short Board headings retain
the boundary swipe. Week subtitle taps retain their date-selection action.

Native horizontal scrolling is used instead of introducing freeform dragging into
Card rows, where swipe deletion, vertical scrolling, and drag/reorder already have
established meanings. Extending to those previews requires separate gesture testing.

## Verification

Hosted tests verify overflow-only scroll enablement, no initial movement, end-of-text
reachability, retained reading position, independent List/Board readers, unchanged
Card/Note records during layout, and existing header sizing/boundary classification.
Synthetic previews cover the long titles and subtitles from the reported scenario.
Actual finger drags, tap-to-edit, vertical scrolling, and Week selector taps remain
part of the hands-on simulator/device acceptance check.


## Conditional header spacing

Focused Day/List and Board title bars retain their ordinary gaps when both heading
lines fit. When the intrinsic heading width would exceed the space left by those
gaps and controls, a shared Layout removes the extra inter-control spacing. It
retains each control's existing frame/touch region and the outer header margins.
It does not shrink icons, overlap hit targets, or hide actions. Very long text can
still scroll (or truncate when the preference is off) after the gaps are reclaimed.

The decision uses intrinsic heading width, including subtitles, rather than the
previous rendered overflow flag. This keeps the compact state stable when the
extra space makes a heading fit. Layout recalculates for changed text, available
width, and type size, and mirrors placement for right-to-left interfaces. Short
headings keep the previous 8-point Board / 12-point focused Day/List gaps.

## Trailing overflow cue

Scrollable titles and subtitles display a fixed trailing ellipsis while additional text remains beyond the reading edge. A short transparent fade masks the moving text before the dots without covering the header background. The cue disappears at the end and returns when scrolling back. It follows the surrounding font, color, and layout direction, ignores touches, and is excluded from accessibility text. The text keeps its full scrollable width; tapping still opens editing where supported.

Both reading edges now use the same cue: hidden earlier text produces a leading ellipsis, hidden later text produces a trailing ellipsis, and both appear in the middle. Each edge clears independently when that end of the text is reached.
