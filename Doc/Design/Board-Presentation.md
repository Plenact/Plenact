# Board Presentation: Orientation and Density

**Status:** Implemented first version, October 4, 2026. Standard and Overview are local Board-presentation presets. Automated geometry and hosted-view checks are available; physical-device rotation, gesture, sheet-draft, and VoiceOver acceptance checks remain necessary before release.

## Purpose

Give people two complementary ways to work with their plans:

- **Standard:** read and edit one list comfortably, with supporting card summaries.
- **Overview:** scan neighboring lists and compare plans using concise cards.

This supports the [Life Planning & Management model](Life-Planning-Model.md) without adding another task store. An overview can help someone reconsider a week, but it does not score, automatically rebalance, move, or reschedule their work.

## Using the feature

Open the Week Board or a personal collection, then open **Board options** (the header's ellipsis menu). Choose **Standard** or **Overview** under **Board presentation**.

The same choice is also available in **Board options > Board Settings > Presentation**. It takes effect immediately and is remembered on this installation across app launches. Week and personal collections using the shared Board renderer use the same preference.

Rotate the iPhone to portrait or either landscape direction. Rotation changes the available layout space, not the selected presentation. Device orientation lock may prevent rotation.

No pinch gesture or continuous zoom slider is implemented. These presets adjust layout density, not the scale of the entire interface.

## Layout contract

The lower navigation bar keeps its existing control positions and fixed-height layout while its paper/tint background extends to the screen edge through the bottom safe area. In portrait, only the background's top edge is inset 20 points: the New circle retains its 14-point offset and overlaps that edge by 6 points. Compact-height landscape keeps the full-height background. Check the overlap and home-indicator region in portrait and both landscape directions; keyboard presentation must retain the existing bottom-anchored toolbar behavior.

| Behavior | Standard | Overview |
| --- | --- | --- |
| List width at ordinary text sizes | Up to 360 points; phone widths reserve 15-point neighbor previews and 17-point gaps on each side | Up to 240 points |
| Narrow viewport | Fits within the viewport with 28 points reserved for horizontal margins | Same margin constraint |
| Personal List-kind collection | Fills usable viewport width, retaining the same 28-point horizontal margins | Keeps the compact 240-point cap |
| Card minimum height at default text size | 112 points | 80 points |
| Title summary | Up to three lines | Up to two lines |
| Supporting subtitle and label summary | Shown | Omitted from the summary only |
| Explicitly selected card cover, when enabled | 128-point decorative preview | 72-point decorative preview |
| Enabled comment/checklist/date badges | Shown | Shown |
| Completion and card actions | Available | Available |

Cards grow to fit their displayed content; these heights are minimums, not clipping bounds. A card with long text or labels can be taller than a neighboring card. Measured row heights contribute to list-panel sizing, and long lists remain vertically scrollable with the Add card action retained.

Single-list personal collections use the full available Standard width rather than leaving space for a neighboring column that does not exist. Week and Board-kind collections retain the normal Standard cap. This is presentation-only and does not change collection kind, cards, or persistence.

List titles and counts occupy their own header row, separate from reordering and list actions. Overview omits the list subtitle as well as the card subtitle. Card actions appear beside the badges below the title rather than consuming title width. Summaries explicitly fit their vertical content so a tall list does not stretch each card. Badge counts remain visible alongside their icons even inside a navigation link.

In a 393-point-wide portrait viewport, Standard centers a 329-point List with equal 15-point neighbor previews beyond the 17-point gaps. Standard snapping, explicit List/Card navigation, boundary jumps, and drag-edge scrolling all use centered alignment. Symmetric scroll-content margins allow the first and last Lists to center too; their missing-neighbor side remains empty rather than wrapping. Wider viewports retain the 360-point column cap and show more adjacent content. Overview retains its compact widths, 12-point gaps, and leading alignment. Counts depend on actual safe-area width and text settings, not on a hardcoded device orientation.

Dynamic Type continues to control text size. At accessibility text sizes, both presets use the available column width, titles are not line-limited, and badges stack vertically. Label summaries fall back to a count if individual chips do not fit. Completion and card-menu controls retain 44-point targets.

The focused **Open today's list** screen continues to use Standard-style summaries, now with a content-fitting 112-point minimum instead of a viewport-height proportion. It does not become a multi-column overview.

**Board Settings → Show card covers** stores a separate device-only preference under `Plenact.CardCovers.enabled` (default on). It hides row images, not attachment records or cover selections. Existing cards remain text-only until explicitly selected. Card detail provides Add Photo as Cover, a visual attached-photo chooser, and Remove Cover; removing a cover never deletes the photo. See [Card Covers](../Src/Features/Boards/README.md#optional-card-covers).

## Content and state safety

- Presentation is stored separately under `Plenact.BoardPresentation.v1` in local preferences. It is not part of a Board document, profile, or remote payload.
- Changing presentation or orientation does not alter card/list IDs, ordering, dates, completion, bookmarks, archives, checklist content, or attachment filenames.
- Overview hides supporting text and label chips only in the card summary. The underlying content remains available in card detail and Standard presentation.
- The Board uses stable list/card identities and an ID-bound scroll position so re-layout can retain the visible list rather than rebuilding a different Board.
- Card detail navigation and list/card editing sheets are not deliberately dismissed or recreated by rotation or preset changes. Their draft retention still needs hands-on verification.
- A list drag ends if presentation or viewport size changes, because its previous drag coordinates no longer describe the new layout. Ordinary menu and VoiceOver movement alternatives remain available.
- A card drag cancels on re-layout, preset changes, backgrounding, or leaving the Board. Its record stays unchanged until a valid drop. Native whole-card drag sources support same-Board movement in both presets; horizontal edge scrolling reveals neighboring lists without reordering them. See [Dragging Cards Between Lists](../Src/Features/Boards/README.md#dragging-cards-between-lists).
- This feature does not reset saved Boards, load examples, migrate stored content, synchronize data, or require a backend.

Exact pixel offsets and the number of visible cards can change on rotation. Preserving context means retaining the same source list/card and edits, not freezing the old geometry.

## Orientation support

The iPhone configuration declares portrait, landscape left, and landscape right. The explicit source plist now matches the project declarations. This does not add iPad support or establish that every app screen has completed landscape QA.

Both presets use the shared renderer for Week and personal Lists/Boards. The Board header, root navigation bar, keyboards, and modal forms must also be checked on short landscape screens.

In compact-height layouts, the root navigation bar uses a 52-point content height, horizontal icon/caption groups, and a 44-point New button without the portrait floating offsets. The controls and captions stay within the bar above the bottom safe area. Portrait retains the existing raised New presentation. The bar still remains anchored under the keyboard rather than rising with Quick capture.

## Validation and acceptance

Automated tests in the active Board suite cover:

- Exact column widths and landscape column-count thresholds.
- Narrow, nonfinite, and undersized geometry.
- Accessibility-width behavior.
- Local preset persistence independent of Week and personal collection snapshots.
- Actual hosted card sizing at normal and accessibility text sizes.
- Card sizing under short and tall height proposals, plus actual navigation-linked List row heights.
- Hosted Board re-layout across portrait/landscape-sized frames and both presets, retaining the requested middle-list identity, active/archived records, and bookmarks without requesting a Board save.

Hosted re-layout is not a physical-device rotation test or end-to-end gesture test.

The initial implementation passed the full iPhone 17 simulator suite on October 4, 2026: **61 tests, 0 failures**, using `xcodebuild test -project Plenact.xcodeproj -scheme Plenact -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO`. The built app's iPhone orientation declarations were also checked for portrait and both landscape directions. Owner-provided screenshots subsequently confirmed that both presets rendered in portrait and landscape, but exposed title compression, excessive card spacing, and a crowded landscape toolbar; the layout was refined in response. Screenshots alone do not establish draft retention or gesture accessibility.

The refined implementation passed the same full simulator command with **63 tests, 0 failures**. The added regression checks compare card heights under 300- and 900-point height proposals and verify bounded row heights inside actual navigation-linked Lists. The compact toolbar and revised header/title arrangement still require another hands-on visual and keyboard check.

Before calling this release-verified, check on compact and large supported iPhones:

1. Switch presets and rotate both ways while positioned on a middle and last list; confirm the same planning context remains visible.
2. Open card detail, type an unsaved draft, rotate, and finish or cancel normally.
3. Repeat with New card, Rename Card, and Update Card Info; ensure drafts and save/cancel behavior survive.
4. Scroll a long list and reach Add card; test large titles, labels, empty lists, and dividers.
5. Exercise card/list reordering in both presets, including viewport-edge scrolling and rotation during a drag.
6. Verify completion, archive/restore, bookmarks, and attachment access across Week and personal collections.
7. Test Dynamic Type, VoiceOver reading/focus, Reduce Motion, dark mode, keyboard presentation, and toolbar clearance.
8. Relaunch and confirm the presentation preference and unchanged user content.

Continuous zoom, per-Board density preferences, and pinch interactions remain deferred rather than implied by this feature.
