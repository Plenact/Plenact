# Plenact revision history

User-facing changes for each tagged repository version. Version dates below are the tagged commits' dates; they do not claim App Store availability or the original publication date of a GitHub Release. Older entries were reconstructed from the commits included in each tag.

Published versions: [GitHub Releases](https://github.com/Plenact/Plenact/releases). Maintainer instructions: [Release process](Doc/Releases/README.md).

## Unreleased

Changes after v1.4; no new version number has been assigned.

### Added

- Give bundled Gym Cards the Oshkosh Planet Fitness location and Work Cards Mercury Marine Plant 33. Fill matching empty locations once across existing editable Cards and routines, preserving custom locations and keeping a pre-update backup.

- Find Card locations with an embedded Apple Maps search, selectable place results, and a map preview. “Use this location” fills the editor draft; Save remains the only action that changes the Card.

- Add optional Card locations with a tappable place link, separate edit/remove controls, and an app-wide Apple Maps or Google Maps preference. Apple Maps is the default; location changes use normal Card history and locking rules.

- Keep Day Lists and Today’s Focus in time order by default, placing untimed Cards last. Turn off “Keep Day Lists in time order” in settings for manual Day ordering; section boundaries and equal-time order are preserved.

- Edit a Card’s start or due date directly from its Today’s Focus date or time label; saved changes immediately refresh the listing.

- Tap a bookmark in Today’s Focus to remove it without opening the Card, with a brief Undo notice above the bottom toolbar.

- Personalize Cards, Notes, Lists, Boards, and primary workspace views with colors, gradients, paper, linen, dot grids, graph paper, illustrated canvases, or imported images. Control strength, readability, photo framing, and Card preview visibility.
- Reuse named artwork and complete looks in My art, choose separate new-Card and new-Note defaults, and optionally vary newly created item colors and headers. Unsplash search is optional and requires a developer access key; imported artwork remains device-local.
- Edit start and due dates directly from Card and Note previews without leaving the List.
- Open a Card or Note's Edit history from its menu to see saved content updates and timestamps. Previous and new field values are retained for future reversal; restoration controls and personal Saved/importance marks are not included yet.
- Choose italic subtitles with a Board default and inherited or explicit Regular/Italic overrides for Lists, Cards, and Notes.
- Give Today's Focus item selections a gold glow following the text and symbols before opening the selected Card. Reduce Motion uses a simple highlight.

### Changed

- Use each Today’s Focus item’s icon as its completion control, with a check badge when completed. Custom icons and picture previews replace the default Card or Note symbol, leaving more room for titles.

- Keep Today’s Focus in sync with saved Card edits, completion, bookmarks, and importance without waiting for its clock refresh or recreating the panel.

- Clarify Today's Focus with a softly fading selection explanation, stronger title styling and contrast, and an inviting “See today’s list” action. Show times and quiet whole-list completion counts only for All items or selections including Up Next; remove the prominent progress bar.
- Tap Recent in Activity to switch between full-size and square previews. The Activity browser now stays within the available space, with its contents scrolling independently above the lower toolbar.
- Refine built-in List information-card entrance and header-toggle motion, including synchronized Add controls and compact spacing when retracted.

### Fixed

- Keep the lower toolbar background covering the home-indicator area.

### Maintenance

- Reorganize Swift sources into focused feature files with a target of at most 1,200 meaningful source lines per file.
- Resolve Swift return-expression warnings introduced by formatting.
- Establish this tagged revision history and a GitHub Release publishing workflow.

[Changes since v1.4](https://github.com/Plenact/Plenact/compare/v1.4...main)

## v1.4 — 2026-10-23

### Added

- Organize a Day into named, colored sections. Collapse sections or move a whole section to another general or Day List, with Undo.
- Mark Cards and Notes read-only to protect their content from editing.
- Express importance in one-step increments up to five stars, with overlapping Tucked and Fanned styles. Tucked is the default; tap to increase and hold to decrease importance in Card detail and previews.
- Create Cards quickly by entering a title in a List's Add row. Use the + control to open the full composer with the entered title, and customize the Add text and + color for each view.
- Use the lower-left corner as a configurable Back shortcut in views with a return action; enabled by default.
- Hold a picture attachment to make it the Card or Note's cover image.
- Show completion badges on picture-based Card previews.
- See a Day overview with planned time and completion by tag, and a quiet perspective section beneath Today's action area.
- Hold bottom-toolbar controls for shortcuts, including Plans Search and Activity Revisit.

### Changed

- Replace persistent built-in List welcome Cards with temporary, read-only session guidance for On the Table, In the Queue, and Scheduled. Header taps reveal or retract the guide, and the Add controls remain available after retraction.
- Name newly added Lists directly in their Board headers, with the title selected for immediate typing.
- Reserve the rightmost quarter of a Card preview for Board navigation while retaining swipe actions in the remaining region.
- Add overflow cues at both ends of manually scrollable titles.
- Unify Card and Note creation through the shared full-feature composer.
- Simplify Activity headings, open Saved items directly, and return from those items to Activity.
- Dismiss Today's Focus filters by tapping their checkmark, simplify section creation, and remove redundant generic header subtitles.

### Fixed

- Keep Today's Focus populated consistently when applying examples and templates.
- Remove duplicate dates from Day headers and preserve Card reordering while simplifying sections.

### Maintenance

- Align trailing Swift comments and declaration types, complete function headers, and standardize source documentation and spacing.
- Group Planning sources into their own folder in the Xcode navigator.

[Compare v1.3 → v1.4](https://github.com/Plenact/Plenact/compare/v1.3...v1.4)

## v1.3 — 2026-10-21

### Added

- Choose Note List mode for Day and standalone List views.
- Personalize Today's Focus ordering, section grouping, and filters, and open Today's Plan from its heading.
- Follow a daily and weekly review rhythm from Today.
- Add personal emoji reactions to Cards and Notes.
- Scroll long titles and subtitles manually with the optional slide-to-read setting.
- Attach media while creating a Card or Note.
- Use the shared context-aware keyboard toolbar for editing.
- Choose optional random colors for newly created Cards.
- Scroll Today's slogan interactively and swipe Today's Focus items to reveal Delete.

### Changed

- Reveal newly created Cards and Notes automatically in their containing List.
- Adapt List and Board header spacing to long text.
- Refine Note layout, keyboard-toolbar appearance, launch-shadow direction, and closing motion.
- Refine Today's Focus filters, item context, and scrolling.

### Fixed

- Restore confirmed swipe-to-delete across Card and Note Lists.

[Compare v1.2 → v1.3](https://github.com/Plenact/Plenact/compare/v1.2...v1.3)

## v1.2 — 2026-10-18

### Added

- Open dedicated Plan Settings and configure Today's Focus.
- Open Cards and Notes directly from Today's Focus.
- Reset List checkmarks with a restoration option that preserves unrelated content.
- Choose icons and icon colors for List and Day title bars.
- Adjust List background opacity.

### Changed

- Make the main New button follow the current view's creation context.
- Unify main List views and extend header icon controls across Lists.
- Refine Today's Focus layout and text capitalization.
- Add a soft offset fade behind the launch icon.

[Compare v1.1 → v1.2](https://github.com/Plenact/Plenact/compare/v1.1...v1.2)

## v1.1 — 2026-10-18

### Added

- Browse reusable Day and Week templates in Library, including the Jmr week routine and catalog filters.
- View Check-in history, perform a Daily review, and optionally record moods.
- Expand Quick capture with media and editable drawings; add Drawing to attachments.
- Open a Day from its Week List title or subtitle and highlight today's List in Week.
- See planned and scheduled content in the Week calendar picker.
- Use a gentle welcome glow and an optional daily planning reminder.
- Access Today's Plan in the iPad Today view.

### Changed

- Enlarge iPad bottom-toolbar controls and refine Today layout across device sizes.

### Fixed

- Let Today use the available iPad width and restore its spacing above the toolbar.
- Prevent lower-toolbar clipping on iPad and restore iPhone Today spacing.
- Correct Sunday dates in Week layouts.

[Compare v1.0 → v1.1](https://github.com/Plenact/Plenact/compare/v1.0...v1.1)

## v1.0 — 2026-10-16

Initial tagged development baseline, covering the repository's history through v1.0.

### Added

- Plan from Today, navigate horizontally through Week, and organize personal Lists and Boards in Plans and Library.
- Create Cards, Notes, dividers, pictures, Title items, and Text items, with editable titles and subtitles.
- Write rich text, add comments, and use checklists with multiple item types, linked Cards, and nested action details.
- Set optional start and due dates with date-only, time-only, or combined precision and contextual schedule badges.
- Attach photos and clipboard images, use captioned galleries, and choose optional covers from attachments or a searchable offline library of 400 illustrations.
- Customize Card, Note, List, and Board appearance, backgrounds, preview text colors, display profiles, and per-Card section layouts.
- Reorder Cards and Lists, move items between Week and personal Lists, and copy or move Lists between Boards.
- Archive and restore Cards, Lists, and Boards, with separate confirmed permanent-deletion controls.
- Browse Activity with Recent, Saved, Due soon, and label-focused views; bookmark personal collection items and open them directly.
- Search across planning content, browse by label, choose weeks and days from calendar headers, and configure Sunday or Monday week starts.
- Use Board zoom, Standard/Overview presentation, Gallery browsing, and compact weekly Card previews.
- Try bundled Board, List, mixed-format, and full-month examples, with offline restoration of the user's pre-example data.
- Use local profiles with custom avatars, personalized Today shortcuts, daily slogans, quick capture, and an automatically current weekday focus.
- Include shared demo account/API synchronization infrastructure and background persistence with visible database activity.
- Access introductory List tutorials and planning-rhythm help.

### Changed

- Establish adaptive iPhone/iPad and landscape layouts, a branded launch experience, and a persistent lower navigation toolbar.
- Default personal Library Lists to Notes while retaining mixed item formats.
- Keep optional cover and layout controls in contextual actions and consolidate Library creation and filtering menus.

### Fixed

- Restore source-specific return navigation from Cards and Notes and open the selected item rather than only its List.
- Keep the lower toolbar anchored across keyboard changes and preserve Board/List zoom and scroll positions.
- Correct keyboard-focus editing freezes, comment dismissal while typing, profile photo crop alignment, and native divider dragging.
- Avoid duplicate headings, source names, cover thumbnails, and redundant same-day date badges.
- Preserve creation drafts, consecutive week dates, and shared Card/Note draft content.

### Maintenance

- Establish persistence, synchronization contracts, database payload limits, source documentation conventions, and regression coverage for the initial planning workspace.

[Browse the v1.0 source](https://github.com/Plenact/Plenact/tree/v1.0)
