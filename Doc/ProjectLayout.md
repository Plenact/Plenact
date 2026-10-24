# Plenact project layout

Swift files are organized by feature and responsibility within the existing application target.
Each file is limited to **1,200 source lines**, excluding comments, blank lines, and lines
containing only braces, brackets, parentheses, commas, or semicolons. Imports and declarations count.
Counts describe physical source lines, not a number of executable statements.

`Doc/Style/style.swift` remains the formatting and documentation reference. Blocks use expanded
braces on their own lines; closures inside single-line string interpolation retain required syntax.
Declaration types and consecutive trailing block comments retain their vertical alignment.

## Ownership and visibility

The existing views retain their stored state and persistence callbacks. The app root, Board, and
Card detail views have focused same-module behavior extensions. Helpers used across these files
use internal visibility where Swift file-private access would prevent the move; no public API is
introduced. Calendar and Library records remain owned and saved through the same checked paths.

The two obsolete root-level model/detail copies were removed; they were outside the app target.
The shared XCTest suite retains its class and method identities, with coverage grouped into
feature-specific extension files and shared hosted-view fixtures.

## Swift file map

Files are grouped by feature and responsibility. Each description summarizes its purpose;
individual file headers document the details.

```text
Plenact/
├── Design/
│   └── CoverLibrary/
│       └── GenerateCovers.swift                  — Offline illustration generation from authored cover metadata
├── Doc/
│   └── Style/
│       └── style.swift                           — Swift style template with disciplined, human-readable engineering headers
├── Src/
│   ├── App/
│   │   ├── AppRootView.swift                     — Workspace composition and view-owned presentation state
│   │   ├── BottomToolbar.swift                   — Device-specific bottom-toolbar layout
│   │   ├── LaunchPresentation.swift              — Launch progress, loading artwork, and welcome cues
│   │   ├── WorkspaceActions.swift                — Calendar ownership and checked workspace operations
│   │   ├── WorkspaceContentActions.swift         — Workspace content creation and restoration actions
│   │   └── WorkspaceNavigation.swift             — Workspace destination identities and direct List navigation
│   ├── Features/
│   │   ├── Activity/
│   │   │   ├── ActivityView.swift                — Recent, bookmarked, and focused Activity presentation
│   │   │   └── ArchiveViews.swift                — Read-only inspection of retained archives
│   │   ├── Appearance/
│   │   │   ├── AppearanceEditors.swift           — Draft appearance and List surface controls
│   │   │   ├── AppearanceModels.swift            — Persisted appearance choices and inheritance policy
│   │   │   └── BackgroundSurfaces.swift          — Appearance rendering and independent background storage
│   │   ├── Attachments/
│   │   │   ├── AttachmentStore.swift             — Retained attachment metadata and local media files
│   │   │   ├── AttachmentViews.swift             — Media sources, galleries, captions, ordering, and playback
│   │   │   ├── CoverLibrary.swift                — Offline illustration catalog and cover selection
│   │   │   ├── CreationAttachments.swift         — In-memory attachment capture before item creation
│   │   │   └── DrawingEditor.swift               — Editable PencilKit capture and drawing export
│   │   ├── Boards/
│   │   │   ├── BoardActions.swift                — Board, focused List, and reusable workspace presentation
│   │   │   ├── BoardBindings.swift               — Active and archived Board binding projections
│   │   │   ├── BoardGallery.swift                — Section-aware Board gallery presentation
│   │   │   ├── BoardHeader.swift                 — Board header, options, and display settings
│   │   │   ├── BoardInteractions.swift           — Native Board drag, drop, and swipe routing
│   │   │   ├── BoardView.swift                   — Horizontally browsed Board composition
│   │   │   └── BoardViewport.swift               — Board sizing, zoom, and retained scroll position
│   │   ├── Calendar/
│   │   │   ├── CalendarModels.swift              — Dated Week ownership and stable local calendar keys
│   │   │   ├── CalendarNavigation.swift          — Dated owner access and caller-specific return routes
│   │   │   ├── CalendarStore.swift               — Validated dated workspace persistence
│   │   │   ├── CalendarViews.swift               — Calendar browsing and Week or Day selection
│   │   │   └── CardDateBrowser.swift             — Card start-date and due-date calendar browsing
│   │   ├── Capture/
│   │   │   ├── CaptureModels.swift               — Full capture submissions and creation policy values
│   │   │   ├── CreatedContentReveal.swift        — One-shot navigation to newly committed items
│   │   │   ├── InlineListCapture.swift           — Inline List creation and full-composer handoff
│   │   │   ├── MediaCapture.swift                — Camera and voice capture lifecycle
│   │   │   └── NewItemComposer.swift             — Full-featured Card and Note creation drafts
│   │   ├── Cards/
│   │   │   ├── CardActivity.swift                — Card comments, generated activity, and emoji controls
│   │   │   ├── CardDetailActions.swift           — Owner-scoped Card editing and attachment operations
│   │   │   ├── CardDetailSections.swift          — Reusable Card detail sections and controls
│   │   │   ├── CardDetailView.swift              — Card and Note detail composition and retained editor state
│   │   │   ├── CardEditors.swift                 — Explicit Card metadata editing drafts
│   │   │   ├── CardPreview.swift                 — Shared Card, Note, and picture List previews
│   │   │   ├── CardSectionRendering.swift        — Card detail toolbar and section rendering
│   │   │   ├── ChecklistViews.swift              — Typed checklist action presentation and editing
│   │   │   └── ReadOnlyCardContent.swift         — Locked Card and Note reading surfaces
│   │   ├── Examples/
│   │   │   ├── CollectionExamples.swift          — Offline personal List and Board example drafts
│   │   │   ├── ExampleViews.swift                — Searchable example discovery and read-only previews
│   │   │   ├── FullMonthExamples.swift           — Reversible demonstration-workspace generation
│   │   │   └── StarterContent.swift              — Deterministic Week starters and built-in List guidance
│   │   ├── Importance/
│   │   │   ├── ImportanceControls.swift          — Layered importance stars and deliberate gesture controls
│   │   │   └── ImportanceStore.swift             — Personal owner-qualified importance persistence
│   │   ├── Labels/
│   │   │   ├── CardLabelsSheet.swift             — Draft label catalog browsing and Card assignment editing
│   │   │   └── LabelModels.swift                 — Reusable label identities, catalog storage, and chip presentation
│   │   ├── Library/
│   │   │   ├── CollectionViews.swift             — Personal collection presentation and settings
│   │   │   ├── LibraryBrowse.swift               — Derived Library filters and owner-qualified browsing
│   │   │   └── LibraryView.swift                 — Plans directory and personal collection workflows
│   │   ├── Lists/
│   │   │   ├── BoardListColumn.swift             — One Board List column and its canonical Card rows
│   │   │   ├── ListActions.swift                 — List options and owner-qualified destination selection
│   │   │   ├── ListCheckmarkReset.swift          — Temporary completion-only restoration snapshots
│   │   │   ├── ListDetailView.swift              — Focused Day and personal List presentation
│   │   │   ├── ListEditors.swift                 — Inline List naming and explicit metadata drafts
│   │   │   ├── ListGuidance.swift                — Temporary read-only built-in List guidance
│   │   │   └── ListMutation.swift                — Validated canonical List metadata updates
│   │   ├── Movement/
│   │   │   ├── CardMovement.swift                — Canonical Card movement, ordering, and deletion transforms
│   │   │   ├── ListMovement.swift                — Canonical whole-List copy and transfer transforms
│   │   │   └── MovementDestinations.swift        — Owner-qualified Card and section destination controls
│   │   ├── Planning/
│   │   │   ├── DailyCheckIn.swift                — Morning guidance, submitted check-ins, and retained history
│   │   │   ├── LibraryHelp.swift                 — Offline help catalog and article presentation
│   │   │   ├── PeriodicReview.swift              — Custom-period reflection, objectives, and review persistence
│   │   │   ├── PlanningTemplates.swift           — Reusable routine snapshots, bundled starters, and application policy
│   │   │   ├── PlanningTemplatesView.swift       — Reusable routine browsing, draft editing, and checked application
│   │   │   ├── ReviewRhythm.swift                — Daily and weekly review invitations and optional reminders
│   │   │   ├── ReviewTransactions.swift          — Recovery boundary for multi-store review mutations
│   │   │   ├── TodayPlan.swift                   — Daily intentions, owner-qualified priorities, check-ins, and history
│   │   │   └── TodayReview.swift                 — Daily and weekly reflections with checked content decisions
│   │   ├── Profile/
│   │   │   ├── AccountSettingsView.swift         — Local identity editing and standalone planning settings
│   │   │   ├── LocalProfileStore.swift           — Device-local profile, avatar files, and planning preference storage
│   │   │   ├── ProfileColorEditors.swift         — Local avatar and accessible color editing
│   │   │   └── ProfileModels.swift               — Local identity, compatible preferences, and Today Focus projections
│   │   ├── Search/
│   │   │   ├── WorkspaceSearch.swift             — Shared matching, scopes, and owner provenance
│   │   │   └── WorkspaceSearchView.swift         — Common workspace search presentation
│   │   ├── Sections/
│   │   │   ├── DaySections.swift                 — Named section membership and ordering policy
│   │   │   ├── SectionTransfer.swift             — Checked whole-section transfer and guarded Undo
│   │   │   └── SectionViews.swift                — Named divider headings and section presentation
│   │   ├── Sync/
│   │   │   ├── DatabaseActivity.swift            — Database activity presentation and content-transfer confirmations
│   │   │   ├── PlenactAPIClient.swift            — HTTPS transport and Keychain sessions for the shared demo API
│   │   │   ├── PlenactBoardDocument.swift        — Versioned Board payload and shared-demo response contracts
│   │   │   └── PlenactDemoAccountSection.swift   — Explicit shared-demo authentication, directory, and sample Board controls
│   │   └── Today/
│   │       ├── DayScheduleOverview.swift         — Read-only planned-time and Day schedule summaries
│   │       ├── TodayEncouragement.swift          — Authored daily encouragement and readable motion
│   │       ├── TodayFocus.swift                  — Derived Focus entries, filtering, and direct detail access
│   │       ├── TodayHomeView.swift               — Today's main composition and capture entry points
│   │       ├── TodayPerspective.swift            — Read-only overview of the represented Day
│   │       ├── TodayScrolling.swift              — Today header fading and deliberate section settling
│   │       └── TodayShortcuts.swift              — Retained owner-qualified Today List shortcuts
│   ├── Models/
│   │   ├── ChecklistModels.swift                 — Stable checklist records and typed action content
│   │   ├── ItemMetadata.swift                    — Shared item presentation and authored metadata
│   │   ├── KanbanCard.swift                      — Canonical Card, Note, and divider records
│   │   ├── KanbanList.swift                      — Canonical List records and item construction
│   │   └── PersonalCollection.swift              — User-owned personal Lists and Boards
│   ├── Persistence/
│   │   ├── BoardPersistence.swift                — Checked local Board snapshot storage
│   │   ├── BookmarkStore.swift                   — Device-local bookmark persistence
│   │   ├── CollectionPersistence.swift           — Local personal collection storage and migration
│   │   ├── ExampleUndoStore.swift                — Pre-example workspace restoration snapshots
│   │   └── RecentHistory.swift                   — Owner-qualified viewed-item and search history
│   ├── SharedUI/
│   │   ├── ContentLifecycleActions.swift         — Confirmed content archive and deletion presentation
│   │   ├── KeyboardToolbar.swift                 — Shared native editing context and accessory controls
│   │   ├── NavigationShortcuts.swift             — Shared Back behavior and navigation presentation helpers
│   │   ├── PaperSurfaces.swift                   — Shared decorative Today paper and panel surfaces
│   │   ├── PreviewText.swift                     — Measured overflowing preview text presentation
│   │   ├── RichTextEditor.swift                  — Rich-text serialization and native editing bridge
│   │   ├── TransferNotices.swift                 — Transient content-transfer confirmations and guarded Undo
│   │   └── WorkspaceHeaders.swift                — Adaptive workspace headings and manual overflow reading
│   └── App.swift                                 — Application entry point and scene recovery
└── Test/
    ├── Support/
    │   └── PresentationFixtures.swift            — Presentation Fixtures
    ├── AttachmentTests.swift                     — Attachment regression tests
    ├── AttachmentTests2.swift                    — Attachment regression tests2
    ├── BoardContentTests.swift                   — Board Content regression tests
    ├── BoardContentTests2.swift                  — Board Content regression tests2
    ├── BoardDocumentTests.swift                  — Board Document regression tests
    ├── BoardInteractionTests.swift               — Board Interaction regression tests
    ├── BoardInteractionTests2.swift              — Board Interaction regression tests2
    ├── BoardInteractionTests3.swift              — Board Interaction regression tests3
    ├── BoardPersistenceTests.swift               — Board Persistence regression tests
    ├── CalendarTests.swift                       — Calendar regression tests
    ├── CaptureTests.swift                        — Capture regression tests
    ├── CardEditingTests.swift                    — Card Editing regression tests
    ├── CardEditingTests2.swift                   — Card Editing regression tests2
    ├── ChecklistMigrationTests.swift             — Checklist Migration regression tests
    ├── ContentMovementTests.swift                — Content Movement regression tests
    ├── ImportanceActivityTests.swift             — Importance Activity regression tests
    ├── LocalProfileStoreTests.swift              — Local Profile Store regression tests
    ├── PlanningReviewTests.swift                 — Planning Review regression tests
    ├── PlanningReviewTests2.swift                — Planning Review regression tests2
    ├── ReviewRecoveryTests.swift                 — Review Recovery regression tests
    ├── SectionTests.swift                        — Section regression tests
    └── TemplateExampleTests.swift                — Template Example regression tests
```

## Validation of this reorganization

- Application and test targets compile successfully with the reorganized Xcode groups.
- All 136 Swift file references resolve; every Swift file is at or below 1,200 counted code lines.
- File, type, function, initializer, and parameter-header checks pass.
- SwiftSyntax comparison preserves all 1,336 original active application/test function and
  initializer token sequences, excluding the intentional private-to-internal visibility adjustments.
- Across the broad regression run and two targeted reruns, 401 of 408 tests passed. The seven
  failing tests were reproduced on the original sources:
  `testDayViewNativeDragReordersCanonicalNotesAndPreservesCancelledDrags`,
  `testFreshInstallationSeedsTutorialListsAndOrderedShortcutsOnlyOnce`,
  `testHostedStandardBoardCentersRequestedListWithEqualNeighborPreviews`,
  `testPersonalCollectionListWidthReachesTheHostedCardContainer`,
  `testPlanningDayReplacementKeepsOtherDaysArchivesAndBookmarks`,
  `testPlanningDefaultWeekAppliesOnceAndCanBeDisabled`, and
  `testPlanningTemplatesSeedStoreConflictAndCorruptDataRetention`.
  The fresh-install fixture also indexes an empty Card array after its outdated assertion fails.
  These existing failures were preserved rather than changing feature behavior in a source-layout pass.
- Xcode emitted an SDK metadata error and stalled while finalizing the broad-run and baseline
  result bundles after their test processes exited. Those reporting processes were stopped;
  this run is not represented as a clean full-suite pass.
