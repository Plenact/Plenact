// --------------------------------------------------------------------------------------------------
// @file       BoardView.swift
// @brief      Horizontally browsed Board composition
// @details    Coordinates canonical List bindings, owner callbacks, creation, and Board
//             presentation while delegating shared components to focused files.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


// -------------------------------------- MARK: - Card Detail Preview --------------------------- //

///
/// @fcn        CardDetailView.Preview
/// @brief      Render a representative card detail screen in the Xcode canvas
/// @details    Wraps the first deterministic sample card in a NavigationStack so navigation-dependent
///             presentation, including the detail navigation bar and sheets, has its required context
///
/// @return     (some View) navigable card detail preview
///
/// @pre        SampleData contains at least one list with one card
/// @post       Preview rendering does not mutate the production board state
///
#Preview
{

    NavigationStack
    {

        CardDetailView(card: SampleData.lists[0].cards[0])
    }

}


// -------------------------------------- MARK: - Board View ------------------------------------ //


///
/// Displays the horizontally scrollable Plenact kanban board
///
/// @section    Purpose
///     Install the board background, header, paged list surface, and navigation path into card details
///
struct ContentView: View
{


    @ObservedObject var creationReveal = CreatedContentReveal.shared

    @Binding var lists: [KanbanList] /* Shared kanban board lists                        */
    /// Archived lists belonging to the same board.
    @Binding var archivedLists:     [KanbanList]  /* Archived partition belonging to this Board      */
    @Binding var boardTargetListID: Int?          /* Requested list to reveal after board navigation */
    /// Optional card identity to open after navigating to its containing list.
    @Binding var boardTargetCardID: Int? /* Pending card identity to open after revealing its list */
    /// Explicit parent requests to return from Card Detail to this Board's root.
    let boardRootRequest:      Int       /* Changing request value returns card navigation to the Board root */
    @Binding var savedCardIDs: Set<Int>  /* Locally bookmarked card identities                               */
    /// Reports which list is nearest the center of the visible board.
    let onListViewed: (Int) -> Void /* Reports the list nearest the viewport center */
    /// Title displayed in the board header.
    let boardTitle: String /* Primary heading displayed above the Board */
    /// Supporting text displayed beneath the board title.
    let boardSubtitle: String /* Supporting text displayed beneath the Board heading */
    /// Whether the board offers list creation.
    let allowsAddingLists: Bool /* Whether the board offers list creation */
    /// Lets a single-list personal collection fill the Standard viewport without changing Overview.
    let fillsAvailableListWidth: Bool /* Whether a single personal List fills the Standard viewport */
    @State var standaloneListActionsRequest = 0
    var isStandaloneListView: Bool
    {
        fillsAvailableListWidth && lists.count == 1
    }

    var standaloneViewMode: Binding<SingleListViewMode>?
    {

        guard isStandaloneListView else
        {
            return nil
        }

        return Binding(
            get:
            {
                lists.first?.singleListViewMode ?? .cards
            },
            set:
            {
                mode in
                guard !lists.isEmpty else
                {
                    return
                }

                lists[0].setSingleListViewMode(mode)
                isGallery = false
            })
    }

    var standaloneSubtitle: String
    {

        guard isStandaloneListView, let description = lists.first?.subtitleOverride,
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else
        {
            return boardSubtitle
        }

        return description
    }

    /// Optional action that returns to the parent collection view.
    let onClose: (() -> Void)? /* Optional return action to the parent collection directory */
    /// Optional parent-owned action for archiving the complete board.
    let onArchiveBoard: (() -> Void)? /* Parent-owned action archiving the complete Board */
    /// Optional parent-owned permanent Board deletion.
    let onDeleteBoard: (() -> Void)? /* Parent-owned action permanently removing Board content */
    /// Names the special Week clearing action without implying removal of its tab.
    let deleteBoardTitle: String /* Context-specific label for the Board deletion action */
    /// Optional save-first boundary for confirmed card/list removal.
    let onCommitDeletion:
    (([KanbanList], Set<Int>) throws -> Void)? /* Checked persistence boundary for confirmed content removal */
    /// Receives active-list snapshots for caller-owned persistence.
    let onListsChanged:
    @MainActor ([KanbanList]) -> Void /* Publishes active-list snapshots for caller-owned persistence */
    /// Supplies other retained snapshots whose attachment files must not be pruned.
    let retainedAttachmentLists: () -> [KanbanList]  /* Supplies external snapshots protecting referenced media */
    let personalCollectionID:    UUID?               /* Owning personal collection; nil for the Week workspace  */
    let appearanceBinding:       Binding<BoardAppearance?>?
    @AppStorage(BoardAppearance.weekStorageKey) var weekAppearanceData = Data()
    @State var showsBoardAppearance = false
    @State var focusedDayListID: Int?

    var storedBoardAppearance: BoardAppearance
    {

        var appearance: BoardAppearance
        if let appearanceBinding
        {

            appearance = appearanceBinding.wrappedValue ?? BoardAppearance()
        }
        else if personalCollectionID == nil
        {

            appearance = (try? BoardAppearance.decodeWeek(weekAppearanceData)) ?? BoardAppearance()
        }
        else
        {

            appearance = BoardAppearance()
        }

        return appearance
    }


    var currentBoardAppearance: BoardAppearance
    {

        var appearance = storedBoardAppearance
        let isPlanningWeek =
        personalCollectionID == nil
        || planningCalendarAccess?.document.weeks.contains(where:
            {
                $0.id == personalCollectionID
            }) == true
        if appearance.cardDetail == nil
        {
            appearance.cardDetail = isPlanningWeek ? .compact : .detailed
        }

        if isStandaloneListView, !isPlanningWeek, appearance.bannerBackground == nil
        {

            appearance.bannerBackground = DefaultListTutorial.defaultBanner(for: lists.first?.title ?? boardTitle)
        }

        return appearance
    }


    var displayedCollectionBackground: CollectionBackground?
    {

        guard allowsCollectionBackground else
        {
            return nil
        }

        return isStandaloneListView
        ? CollectionBackground.defaultListBackground(
            for: lists.first?.title ?? boardTitle, overriding: storedBoardAppearance.collectionBackground)
        : storedBoardAppearance.collectionBackground
    }


    var allowsCollectionBackground: Bool
    {

        CollectionBackground.isAllowed(
            collectionID: personalCollectionID,
            datedWeekIDs: Set(planningCalendarAccess?.document.weeks.map(\.id) ?? []),
            isDatedView: displayedWeekKey != nil)
    }


    let availablePersonalLists: [PersonalCollection] /* Personal Lists available for moving Notes                 */
    let onMoveNoteToPersonalList:
    ((KanbanCard, UUID, UUID) -> KanbanCard?)? /* Moves a Note and returns its persisted destination record */
    let onUpdateMovedNote:
    ((UUID, KanbanCard) -> Bool)? /* Persists edits to a Note after collection movement        */
    let onArchiveMovedNote:
    ((UUID, KanbanCard) -> Bool)? /* Archives a Note under its current collection owner        */
    let onDeleteMovedNote:
    ((UUID, KanbanCard) -> Bool)? /* Deletes a Note under its current collection owner         */
    let onToggleMovedNoteBookmark:
    ((UUID, Int, Bool) -> Bool)? /* Persists a relocated Note's collection-local saved state  */
    /// Controls presentation of the calendar sheet.
    @Environment(\.planningCalendarAccess) var planningCalendarAccess
    @Environment(\.planningHomeExit) var planningHomeExit
    @Environment(\.planningDisplayedWeekKey) var displayedWeekKey
    var calendarOpeningDate: Date
    {

        if let displayedWeekKey, let date = PlanningDate.date(displayedWeekKey)
        {
            return date
        }

        guard let week = planningCalendarAccess?.document.weeks.first(where:
            {
                $0.id == personalCollectionID
            }),
        week.startKey != planningCalendarAccess?.document.currentWeekKey
        else
        {
            return .now
        }

        return PlanningDate.date(week.startKey) ?? .now
    }

    @State var showsSharedSearch = false
    @State var showsWeekSelector = false
    @State var showsCalendar = false                            /* Calendar sheet presentation state         */
    @State var calendarCardTarget: (listID: Int, cardID: Int)?  /* Selection opened after Calendar dismissal */
    /// Controls presentation of archived lists.
    @State var showsArchivedLists = false /* Archived-list browser presentation state */
    /// Navigation stack path for card-detail destinations.
    @State var listToCopy:      KanbanList?
    @State var listToMove:      KanbanList?
    @State var namingNewListID: Int?
    @Environment(\.planningDirectItemReturn) var directItemReturn
    @State var openedDirectItem = false
    @State var navigationPath = NavigationPath()  /* Card-detail destinations in the Board navigation stack       */
    @State var boardBoundaryJumpRequest = 0       /* Trigger distinguishing repeated boundary-navigation requests */
    @State var boardBoundaryJumpTarget:
    BoardListReordering.BoardListBoundary? /* First or last list boundary requested for navigation         */
    /// Last visible list identity sent through `onListViewed`.
    @State var lastReportedVisibleListID: Int? /* Last centered list reported to the parent */
    /// Currently centered list identity.
    @State var visibleListID: Int? /* List identity currently centered in the viewport */
    /// List identity currently being dragged for reordering.
    @State var draggedListID: Int? /* List identity participating in active reordering */
    /// Measured horizontal centers keyed by list identity.
    @State var dragGeometry = BoardDragGeometryCache()
    @State var dragGeometryRevision = 0
    // /* Measured horizontal centers keyed by list identity */
    /// Current horizontal location of an active list drag.
    @State var listDragLocation: CGFloat? /* Horizontal pointer position during list reordering */
    /// Horizontal offset between the drag start and the grabbed list center.
    @State var listDragGrabOffset:    CGFloat = 0 /* Offset between the initial pointer and grabbed list center */
    @State var listDragInitialCenter: CGFloat?    // Center before the temporary drag overview.
    @State var listDragTilt:          Double = 0
    @State var viewportMemory:        BoardViewportMemory
    @State var isPanoramic = false
    @State var isGallery = false
    @State var todayHighlightDate = Date.now
    @State var boardScale: CGFloat = 1
    @GestureState var boardPinch = BoardPinchState()
    var boardZoomScale: CGFloat
    {

        BoardPanoramicZoom.scale(start: boardScale, magnification: boardPinch.magnification)
    }

    var usesFreeBoardScrolling: Bool
    {
        isPanoramic || boardPinch.active || abs(boardZoomScale - 1) > 0.001
    }

    var boardPinchGesture: some Gesture
    {

        MagnifyGesture(minimumScaleDelta: 0.01)
        .updating($boardPinch)
        {
            value, state, transaction in
            guard !isGallery, draggedListID == nil, draggedCardID == nil else
            {
                return
            }

            transaction.disablesAnimations = true
            state.active = true
            state.magnification = value.magnification
        }
        .onEnded
        {
            value in
            guard !isGallery, draggedListID == nil, draggedCardID == nil else
            {
                return
            }

            boardScale = BoardPanoramicZoom.scale(start: boardScale, magnification: value.magnification)
        }

    }

    var listDragScale: CGFloat
    {

        boardZoomScale * (draggedListID != nil && !reducesMotion ? (isPanoramic ? 0.94 : 0.72) : 1)
    }

    @State var draggedCardID:    Int?             /* Card identity participating in the native drag session    */
    @State var cardDragLocation: CGPoint?         /* Current card-drag pointer in global coordinates           */
    @State var cardDragToken = UUID().uuidString  /* Per-Board token rejecting drags from other Board surfaces */
    /// Environment preference used to reduce or remove animated transitions.
    @Environment(\.accessibilityReduceMotion)
    var reducesMotion /* Accessibility preference limiting animated transitions */
    /// Current Dynamic Type size used when selecting Board dimensions.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize  /* Text-size category informing Board dimensions            */
    @Environment(\.scenePhase) var scenePhase            /* Scene lifecycle used to cancel interrupted drag sessions */
    /// Locally persisted choice between Standard and Overview Board layouts.
    @State var presentation = BoardPresentation.standard  /* Persisted Standard or Overview layout selection  */
    @State var labelLibrary = LabelLibraryStore.load()    /* Label library containing all available labels    */
    @State var displaySettings = BoardDisplaySettings()   /* Board display settings                           */
    @State var memberColors: [String: Color] = [:]        /* Mapping of member names to their assigned colors */
    @State var currentUserName = "Justin Reina"           /* Current user's name                              */


    ///
    /// @fcn        ContentView.init
    /// @brief      Configure the shared Board surface, routing, and mutation callbacks
    /// @details    Accepts caller-owned active/archive partitions and optional list/card targets.
    ///             Defaults support standalone Week previews; app-root and personal-board callers
    ///             override persistence and retained attachment references for their complete snapshots
    ///
    /// @param[in]  lists                      Binding to active Board lists
    /// @param[in]  archivedLists              Binding to archived Board lists
    /// @param[in]  boardTargetListID          Pending active list ID to reveal
    /// @param[in]  boardTargetCardID          Pending card ID to open within the target list
    /// @param[in]  boardRootRequest           Changing request value returns navigation to the Board root
    /// @param[in]  savedCardIDs               Binding to this Board's bookmarked card identities
    /// @param[in]  onListViewed               Callback reporting the nearest visible list
    /// @param[in]  boardTitle                 Header title
    /// @param[in]  boardSubtitle              Header supporting text
    /// @param[in]  allowsAddingLists          Whether the header normally offers list creation
    /// @param[in]  fillsAvailableListWidth    Whether Standard list panels fill the usable viewport
    /// @param[in]  onClose                    Optional action returning to the collection directory
    /// @param[in]  onArchiveBoard             Optional parent-owned full-board archive action
    /// @param[in]  onListsChanged             Main-actor callback receiving active-list changes
    /// @param[in]  retainedAttachmentLists    Provider of other snapshots whose photo files must survive pruning
    ///
    /// @param[in]  onDeleteBoard              Optional checked owner callback permanently deleting this Board
    /// @param[in]  deleteBoardTitle           User-facing title identifying the Board in deletion
    ///             confirmation
    /// @param[in]  onCommitDeletion           Optional throwing persistence callback for complete List and
    ///             bookmark snapshots
    /// @param[in]  personalCollectionID       Optional personal owner identity; absent uses the active
    ///             Week context
    /// @param[in]  availablePersonalLists     Active personal List destinations available for Note
    ///             movement
    /// @param[in]  onMoveNoteToPersonalList   Optional checked owner callback moving a Note to a
    ///             personal List
    /// @param[in]  onUpdateMovedNote          Optional checked callback saving further edits after a Note
    ///             moves to another owner
    /// @param[in]  onArchiveMovedNote         Optional owner callback archiving a Note after it moves
    /// @param[in]  onDeleteMovedNote          Optional checked callback deleting a Note after it moves
    /// @param[in]  onToggleMovedNoteBookmark  Optional callback changing a moved Note's personal
    ///             bookmark
    /// @param[in]  boardAppearance            Inherited Board-level presentation and color defaults
    /// @param[in]  viewportOwnerID            Optional owner identity used to isolate retained Board scroll
    ///             positions
    ///
    /// @return     (ContentView) configured kanban board screen
    ///
    /// @pre        lists contains the board state to display
    /// @post       Bindings and callbacks are installed without editing Board content
    /// @note       The archive binding defaults to constant empty state; persistent archives require
    ///             a writable binding. An empty board exposes Add list even when normally disabled
    ///
    init(
        lists: Binding<[KanbanList]>,
        archivedLists: Binding<[KanbanList]> = .constant([]),
        boardTargetListID: Binding<Int?> = .constant(nil),
        boardTargetCardID: Binding<Int?> = .constant(nil),
        boardRootRequest: Int = 0,
        savedCardIDs: Binding<Set<Int>> = .constant([]),
        onListViewed: @escaping (Int) -> Void =
        {
            _ in
        },
        boardTitle: String = "Plenact",
        boardSubtitle: String = "Work Week Board",
        allowsAddingLists: Bool = true,
        fillsAvailableListWidth: Bool = false,
        onClose: (() -> Void)? = nil,
        onArchiveBoard: (() -> Void)? = nil,
        onDeleteBoard: (() -> Void)? = nil,
        deleteBoardTitle: String = "Delete Board",

        onCommitDeletion: (([KanbanList], Set<Int>) throws -> Void)? = nil,
        onListsChanged: @escaping @MainActor ([KanbanList]) -> Void = KanbanBoardPersistence.saveListsInBackground,

        retainedAttachmentLists: @escaping () -> [KanbanList] =
        {

            PersonalCollectionStore.load().flatMap(\.lists) + (ExampleLoadUndoStore.load()?.lists ?? [])
        },
        personalCollectionID: UUID? = nil,
        availablePersonalLists: [PersonalCollection] = [],
        onMoveNoteToPersonalList: ((KanbanCard, UUID, UUID) -> KanbanCard?)? = nil,
        onUpdateMovedNote: ((UUID, KanbanCard) -> Bool)? = nil,
        onArchiveMovedNote: ((UUID, KanbanCard) -> Bool)? = nil,
        onDeleteMovedNote: ((UUID, KanbanCard) -> Bool)? = nil,
        onToggleMovedNoteBookmark: ((UUID, Int, Bool) -> Bool)? = nil,
        boardAppearance: Binding<BoardAppearance?>? = nil,
        viewportOwnerID: UUID? = nil
    )
    {


        let memory = BoardViewportMemory(owner: (viewportOwnerID ?? personalCollectionID)?.uuidString ?? "week.current")
        _viewportMemory = State(initialValue: memory)
        _boardScale = State(initialValue: CGFloat(memory.state.scale))
        _isPanoramic = State(initialValue: memory.state.panoramic)
        _isGallery = State(initialValue: memory.state.gallery)
        let savedList = memory.state.visibleListID.flatMap
        {
            id in
            lists.wrappedValue.contains(where:
                {
                    $0.id == id
                }) ? id : nil
        }

        _visibleListID = State(initialValue: savedList)
        _presentation = State(
            initialValue: BoardPresentation(
                rawValue: memory.state.presentation ?? UserDefaults.standard.string(
                    forKey: BoardPresentation.storageKey) ?? "") ?? .standard)
        _lists = lists
        _archivedLists = archivedLists
        _boardTargetListID = boardTargetListID
        _boardTargetCardID = boardTargetCardID
        self.boardRootRequest = boardRootRequest
        _savedCardIDs = savedCardIDs
        self.onListViewed = onListViewed
        self.boardTitle = boardTitle
        self.boardSubtitle = boardSubtitle
        self.allowsAddingLists = allowsAddingLists
        self.fillsAvailableListWidth = fillsAvailableListWidth
        self.onClose = onClose
        self.onArchiveBoard = onArchiveBoard
        self.onDeleteBoard = onDeleteBoard
        self.deleteBoardTitle = deleteBoardTitle
        self.onCommitDeletion = onCommitDeletion
        self.onListsChanged = onListsChanged
        self.retainedAttachmentLists = retainedAttachmentLists
        self.appearanceBinding = boardAppearance
        self.personalCollectionID = personalCollectionID
        self.availablePersonalLists = availablePersonalLists
        self.onMoveNoteToPersonalList = onMoveNoteToPersonalList
        self.onUpdateMovedNote = onUpdateMovedNote
        self.onArchiveMovedNote = onArchiveMovedNote
        self.onDeleteMovedNote = onDeleteMovedNote
        self.onToggleMovedNoteBookmark = onToggleMovedNoteBookmark
    }


    ///
    /// @fcn        ContentView.activeMembers
    /// @brief      Return unique users assigned to active cards
    /// @details    Traverses cards in board order, excludes divider items, trims surrounding whitespace,
    ///             and retains the first occurrence of each member name using case-insensitive matching
    ///
    /// @return     ([String]) ordered member names currently assigned to non-divider cards
    ///
    /// @pre        lists contains the current in-memory board state
    /// @post       No board data is modified; duplicate and empty names are omitted from the result
    ///
    var activeMembers: [String]
    {  /* Unique names assigned to non-divider cards */


        var seenMembers: Set<String> = [] /* Track unique members to avoid duplicates */

        return
        lists
        .flatMap(\.cards)
        .filter
        {
            !$0.isSectionDivider
        }
        .flatMap(\.members)
        .compactMap
        {
            assignee in

            let trimmedMember = assignee.displayName.trimmingCharacters(
                in: .whitespacesAndNewlines) /* Display name                                              */
            let normalizedMember =
            trimmedMember.lowercased() /* Normalize the member name for case-insensitive comparison */

            guard !trimmedMember.isEmpty, seenMembers.insert(normalizedMember).inserted else
            {


                return nil
            }


            return trimmedMember
        }

    }


    var cardDropTarget: BoardCardDropTarget?
    {

        _ = dragGeometryRevision /* Valid list and insertion anchor under the card-drag pointer */
        guard let location = cardDragLocation, let draggedCardID
        else
        {  /* Active pointer position and dragged record identity         */


            return nil
        }


        return BoardCardMovement.target(
            for: draggedCardID, at: location, viewport: dragGeometry.viewport,
            lists: lists, listFrames: dragGeometry.lists, cardFrames: dragGeometry.cards)
    }


    ///
    /// @fcn        ContentView.body
    /// @brief      Compose the Board scene, horizontal list viewport, and detail navigation
    /// @details    Wires list/card actions, geometry-based visible-list reporting, pending targets,
    ///             archive/calendar sheets, and title-hold reordering. A held list disables normal
    ///             scrolling and moves/scrolls at viewport edges every 550 milliseconds
    ///
    /// @return     (some View) Board navigation stack and shared list panels
    /// @pre        Caller supplies consistent active/archive bindings and Board-unique IDs
    /// @post       Active-list changes invoke onListsChanged; label changes save locally.
    ///             Drag release/disappearance cancels edge work; unexpected movement errors reach the banner
    /// @note       Reduce Motion suppresses drag lift scaling and reorder/edge-scroll animations
    ///
    var body: some View
    {  /* Board scene and list collection */


        NavigationStack(path: $navigationPath)
        {


            GeometryReader
            {
                _ in

                ZStack
                {

                    CollectionBackgroundSurface(background: displayedCollectionBackground)
                    .ignoresSafeArea()

                    VStack(spacing: 0)
                    {


                        BoardHeader(
                            settings: $displaySettings,
                            presentation: $presentation,
                            activeMembers: activeMembers,
                            memberColors: memberColors,
                            onRenameMember: renameMember,
                            onDeleteMember: removeMember,
                            onSetMemberColor: setMemberColor,
                            onOpenCalendar:
                            {
                                showsCalendar = true
                            },
                            title: boardTitle,
                            subtitle: standaloneSubtitle,
                            allowsAddingLists: allowsAddingLists || lists.isEmpty,
                            onClose: onClose,
                            onViewArchivedLists:
                            {
                                showsArchivedLists = true
                            },
                            onArchiveBoard: onArchiveBoard,
                            onDeleteBoard: onDeleteBoard,
                            deleteBoardTitle: deleteBoardTitle,
                            onJumpToFirstList: !isGallery && lists.count > 1 ?
                            {
                                requestBoundaryJump(.first)
                            } : nil,
                            onJumpToLastList: !isGallery && lists.count > 1 ?
                            {
                                requestBoundaryJump(.last)
                            } : nil,
                            listViewMode: standaloneViewMode,
                            titleAppearance: isStandaloneListView
                            ? lists.first?.headerAppearance(
                                collectionIcon: planningCalendarAccess?.library.first(where:
                                    {

                                        $0.id == personalCollectionID
                                    })?.icon,
                                collectionColor: planningCalendarAccess?.library.first(where:
                                    {

                                        $0.id == personalCollectionID
                                    })?.color) : nil,
                            onAppearance:
                            {
                                showsBoardAppearance = true
                            },
                            onListActions: isStandaloneListView
                            ?
                            {

                                isGallery = false;
                                standaloneListActionsRequest += 1
                            } : nil,
                            onSearch:
                            {
                                showsSharedSearch = true
                            },
                            onToggleZoom: isGallery ? nil : toggleBoardZoom,
                            onToggleGallery:
                            {
                                isGallery.toggle()
                            },
                            isGallery: isGallery,
                            isPanoramic: isPanoramic,
                            zoomPercentage: Int((boardZoomScale * 100).rounded()),
                            onResetZoom: !isGallery ? resetBoardZoom : nil,
                            onAdjustZoom: adjustBoardZoom,
                            calendarAccessibilityTitle: calendarOpeningDate.formatted(.dateTime.month(.wide))
                            + " calendar",
                            onSubtitleTap: (displayedWeekKey != nil || personalCollectionID == nil
                                || planningCalendarAccess?.document.weeks.contains(where:
                                    {

                                        $0.id == personalCollectionID
                                    }) == true) ?
                            {
                                showsWeekSelector = true
                            } : nil,
                            onAddList: addList
                        )
                        .background(
                            isStandaloneListView
                            ? (currentBoardAppearance.resolved(lists.first?.appearance).background?.darkHeaderColor
                                ?? .clear)
                            : .clear)

                        if isGallery
                        {

                            BoardGalleryView(
                                lists: lists,
                                listTitle:
                                {
                                    list in
                                    dayDate(for: list.id).map
                                    {
                                        PlanningDate.listTitle(list.title, on: $0)
                                    }

                                    ?? list.title
                                },
                                onOpen:
                                {
                                    card, listID in
                                    visibleListID = listID
                                    onListViewed(listID)
                                    navigationPath.append(card)
                                }, onUpdate: updateCard, onMoveSection: moveSection,
                                showsListHeadings: !isStandaloneListView, boardAppearance: currentBoardAppearance
                            )
                            .environment(\.cardMovementSource, personalCollectionID)
                            .environment(\.boardViewportMemory, viewportMemory)
                        }
                        else
                        {

                            GeometryReader
                            {
                                listArea in
                                let columnWidth = presentation.columnWidth(
                                    viewportWidth: listArea.size.width,
                                    accessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                    fillsAvailableWidth: fillsAvailableListWidth
                                )
                                let tabletScale = BoardTabletSizing.scale(
                                    viewportWidth: listArea.size.width, columnWidth: columnWidth,
                                    isTablet: UIDevice.current.userInterfaceIdiom == .pad,
                                    enabled: presentation == .standard && !fillsAvailableListWidth
                                    && !dynamicTypeSize.isAccessibilitySize)
                                let layoutZoomScale = boardZoomScale * tabletScale
                                let layoutListScale = listDragScale * tabletScale
                                let horizontalInset =
                                presentation == .standard && !isPanoramic
                                ? max(14, (listArea.size.width - columnWidth * layoutListScale) / 2)
                                : 14
                                ScrollViewReader
                                {
                                    listProxy in

                                    ScrollView(.horizontal, showsIndicators: false)
                                    {


                                        LazyHStack(
                                            alignment: .top,
                                            spacing: (presentation == .standard ? 17 : 12)
                                            * (usesFreeBoardScrolling ? layoutZoomScale : tabletScale)
                                        )
                                        {


                                            ForEach(Array(lists.enumerated()), id: \.element.id)
                                            {
                                                listIndex, list in

                                                ZStack
                                                {

                                                    KanbanListView(
                                                        list: list,
                                                        availableListHeight: listArea.size.height / layoutZoomScale,
                                                        displaySettings: displaySettings,
                                                        presentation: presentation,
                                                        labelLibrary: labelLibrary,
                                                        toggleCardTitle:
                                                        {
                                                            cardID in
                                                            toggleCardTitle(in: listIndex, cardID: cardID)
                                                        },
                                                        canMoveEarlier: listIndex > 0,
                                                        canMoveLater: listIndex < lists.count - 1,
                                                        onAddCard:
                                                        {
                                                            capture in
                                                            addCard(capture)
                                                        },
                                                        onCopyList:
                                                        {

                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)
                                                            {

                                                                listToCopy = list
                                                            }

                                                        },
                                                        onMoveToBoard: planningCalendarAccess?.moveList != nil
                                                        && planningCalendarAccess?.library.first(where:
                                                            {

                                                                $0.id == personalCollectionID
                                                            })?.kind != .list
                                                        ?
                                                        {

                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)
                                                            {

                                                                listToMove = list
                                                            }

                                                        } : nil,
                                                        onMoveList:
                                                        {
                                                            offset in
                                                            moveList(with: list.id, by: offset)
                                                        },
                                                        onSortList:
                                                        {
                                                            ascending in
                                                            sortList(with: list.id, ascending: ascending)
                                                        },
                                                        onArchiveCompleted:
                                                        {
                                                            archiveCompletedCards(in: list.id)
                                                        },
                                                        archivedCards: Binding(
                                                            get:
                                                            {

                                                                lists.first(where:
                                                                    {
                                                                        $0.id == list.id
                                                                    })?.archivedCards
                                                                ?? []
                                                            },
                                                            set:
                                                            {
                                                                archivedCards in
                                                                guard
                                                                let index = lists.firstIndex(
                                                                    where:
                                                                    {  /* Position of the list receiving its updated archive partition */


                                                                        $0.id == list.id
                                                                    })
                                                                else
                                                                {

                                                                    return
                                                                }

                                                                lists[index].archivedCards = archivedCards
                                                            }
                                                        ),
                                                        onRestoreArchivedCard:
                                                        {
                                                            cardID in
                                                            restoreArchivedCard(in: list.id, cardID: cardID)
                                                        },
                                                        onDeleteArchivedCard:
                                                        {
                                                            cardID in
                                                            deleteCard(cardID)
                                                        },
                                                        onArchiveList:
                                                        {
                                                            archiveList(with: list.id)
                                                        },
                                                        onDeleteList:
                                                        {
                                                            deleteList(list.id)
                                                        },
                                                        onDeleteCard:
                                                        {
                                                            cardID in
                                                            deleteCard(cardID)
                                                        },
                                                        onArchiveCard: archiveCard,
                                                        onUpdateCard: updateCard,
                                                        onMoveCard:
                                                        {
                                                            cardID, destinationIndex in
                                                            moveCard(
                                                                in: list.id, cardID: cardID, toIndex: destinationIndex)
                                                        },
                                                        onListDragChanged:
                                                        {
                                                            value in
                                                            updateListDrag(list.id, value: value)
                                                        },
                                                        onListDragEnded:
                                                        {
                                                            endListDrag(list.id)
                                                        },
                                                        draggedCardID: draggedCardID,
                                                        dropBeforeCardID: cardDropTarget?.listID == list.id
                                                        ? cardDropTarget?.beforeCardID : nil,
                                                        isCardDropTarget: cardDropTarget?.listID == list.id,
                                                        onMoveSection:
                                                        {
                                                            sectionID, offset in
                                                            moveSection(
                                                                in: list.id, sectionID: sectionID, offset: offset)
                                                        },
                                                        onCardDragBegan: beginCardDrag,
                                                        onCardDragChanged: updateCardDrag,
                                                        onCardDragEnded:
                                                        {
                                                            cardID, commit, point in
                                                            endCardDrag(cardID, commit: commit, location: point)
                                                        },
                                                        cardDragToken: cardDragToken,
                                                        onCardDrop:
                                                        {
                                                            point in
                                                            guard let cardID = draggedCardID
                                                            else
                                                            {  /* Active card identity submitted for the native drop */


                                                                return false
                                                            }

                                                            return endCardDrag(cardID, commit: true, location: point)
                                                        },
                                                        cardMoveDestinations: lists.filter
                                                        {
                                                            $0.id != list.id
                                                        },
                                                        onMoveCardToList:
                                                        {
                                                            cardID, listID in
                                                            moveCard(cardID, toListID: listID)
                                                        },
                                                        onEditList:
                                                        {
                                                            title, subtitle, defaultPresentation in
                                                            editBoardList(
                                                                list.id, title: title, subtitle: subtitle,
                                                                newItemPresentation: defaultPresentation, in: &lists)
                                                        },
                                                        isNamingNewList: namingNewListID == list.id,
                                                        onFinishNaming:
                                                        {

                                                            if namingNewListID == list.id
                                                            {
                                                                namingNewListID = nil
                                                            }

                                                        },
                                                        onOpenDayView:
                                                        {
                                                            focusedDayListID = list.id
                                                        },
                                                        boardAppearance: currentBoardAppearance,
                                                        onAppearance:
                                                        {
                                                            appearance in
                                                            setListAppearance(
                                                                list.id, appearance: appearance, in: &lists)
                                                        },
                                                        isCurrentDay: WeekDayHighlight.isToday(
                                                            dayDate(for: list.id), now: todayHighlightDate,
                                                            calendar: planningCalendarAccess?.document.calendar
                                                            ?? .current),
                                                        assignedDate: dayDate(for: list.id),
                                                        datedTitle: dayDate(for: list.id).map
                                                        {

                                                            PlanningDate.listTitle(list.title, on: $0)
                                                        },
                                                        hidesPanelHeader: isStandaloneListView,
                                                        listActionsRequest: standaloneListActionsRequest,
                                                        onConsumeListActions:
                                                        {
                                                            standaloneListActionsRequest = 0
                                                        }
                                                    )
                                                    .frame(
                                                        width: presentation.columnWidth(
                                                            viewportWidth: listArea.size.width,
                                                            accessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                                            fillsAvailableWidth: fillsAvailableListWidth)
                                                    )
                                                    .environment(\.cardMovementSource, personalCollectionID)
                                                    .environment(\.boardViewportMemory, viewportMemory)
                                                    .scaleEffect(
                                                        layoutListScale
                                                        * (draggedListID == list.id && !reducesMotion ? 1.04 : 1),
                                                        anchor: .top
                                                    )
                                                    .frame(
                                                        width: columnWidth * layoutListScale,
                                                        height: (listArea.size.height / layoutZoomScale)
                                                        * layoutListScale, alignment: .top
                                                    )
                                                    .rotationEffect(
                                                        .degrees(draggedListID == list.id ? listDragTilt : 0),
                                                        anchor: .top
                                                    )
                                                    .shadow(
                                                        color: .black.opacity(draggedListID == list.id ? 0.4 : 0),
                                                        radius: 18, y: 8
                                                    )
                                                    .offset(x: listDragOffset(for: list.id))
                                                }

                                                .frame(width: columnWidth * layoutListScale)
                                                .background
                                                {

                                                    GeometryReader
                                                    {
                                                        geometry in
                                                        Color.clear.preference(
                                                            key: BoardListCenterPreferenceKey.self,
                                                            value: [
                                                                list.id: geometry.frame(in: .named("WeekListsViewport"))
                                                                    .midX
                                                            ]
                                                        )
                                                        .preference(
                                                            key: BoardListFramePreferenceKey.self,
                                                            value: [list.id: geometry.frame(in: .global)])
                                                    }

                                                }

                                                .id(list.id)
                                                .zIndex(draggedListID == list.id ? 1 : 0)
                                            }


                                            if allowsAddingLists || lists.isEmpty
                                            {

                                                Button(action: addList)
                                                {

                                                    Label("Add list", systemImage: "plus")
                                                    .font(.headline)
                                                    .foregroundStyle(.white)
                                                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                                    .padding(.horizontal, 20)
                                                    .background(
                                                        .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .frame(width: columnWidth * layoutListScale)
                                                .accessibilityIdentifier("board.addList")
                                                .id(Int.min)
                                            }

                                        }

                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .scrollTargetLayout()
                                        .background(
                                            BoardViewportScrollProbe(
                                                memory: viewportMemory, key: "horizontal", horizontal: true))
                                    }

                                    .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
                                    .scrollTargetBehavior(BoardZoomScrollBehavior(panoramic: usesFreeBoardScrolling))
                                    .scrollPosition(
                                        id: $visibleListID,
                                        anchor: presentation == .standard && !isPanoramic ? .center : .leading
                                    )
                                    .scrollDisabled(draggedListID != nil || boardPinch.active)
                                    .simultaneousGesture(boardPinchGesture)
                                    .coordinateSpace(name: "WeekListsViewport")
                                    .onPreferenceChange(BoardListCenterPreferenceKey.self)
                                    {
                                        centers in
                                        dragGeometry.centers = centers
                                        refreshActiveDragGeometry()
                                    }

                                    .onPreferenceChange(BoardListFramePreferenceKey.self)
                                    {

                                        dragGeometry.lists = $0;
                                        refreshActiveDragGeometry()
                                    }
                                    .onPreferenceChange(BoardCardFramePreferenceKey.self)
                                    {

                                        dragGeometry.cards = $0;
                                        refreshActiveDragGeometry()
                                    }
                                    .background
                                    {

                                        GeometryReader
                                        {
                                            geometry in
                                            Color.clear.onAppear
                                            {

                                                dragGeometry.viewport = geometry.frame(in: .global)
                                            }

                                            .onChange(of: geometry.frame(in: .global))
                                            {
                                                _, frame in
                                                dragGeometry.viewport = frame
                                            }

                                        }

                                    }

                                    .onChange(of: visibleListID)
                                    {
                                        _, listID in
                                        guard draggedListID == nil,
                                        let listID, /* Centered list identity reported outside list reordering */
                                        lists.contains(where:
                                            {
                                                $0.id == listID
                                            }),
                                        listID != lastReportedVisibleListID
                                        else
                                        {
                                            return
                                        }

                                        lastReportedVisibleListID = listID
                                        onListViewed(listID)
                                    }

                                    .onChange(of: presentation)
                                    {
                                        _, _ in
                                        if let listID = draggedListID
                                        {  /* Interrupted list drag requiring state cleanup */


                                            endListDrag(listID)
                                        }


                                        if let cardID = draggedCardID
                                        {  /* Interrupted card drag requiring state cleanup */


                                            endCardDrag(cardID, commit: false)
                                        }

                                    }

                                    .onChange(of: scenePhase)
                                    {
                                        _, phase in
                                        if phase != .active, let cardID = draggedCardID
                                        {  /* Card drag canceled when the scene becomes inactive */


                                            endCardDrag(cardID, commit: false)
                                        }

                                    }

                                    .onChange(of: listArea.size)
                                    {
                                        _, _ in
                                        if let listID = draggedListID
                                        {  /* Active list drag canceled before boundary navigation */


                                            endListDrag(listID)
                                        }


                                        if let cardID = draggedCardID
                                        {  /* Active card drag canceled before boundary navigation */


                                            endCardDrag(cardID, commit: false)
                                        }

                                    }

                                    .task(id: creationReveal.target?.id)
                                    {

                                        guard let target = creationReveal.target,
                                        lists.contains(where: target.matches)
                                        else
                                        {
                                            return
                                        }

                                        viewportMemory.horizontalRestoreAllowed = false
                                        do
                                        {
                                            try await Task.sleep(for: .milliseconds(100))
                                        }
                                        catch
                                        {
                                            return
                                        }

                                        guard !Task.isCancelled else
                                        {
                                            return
                                        }

                                        visibleListID = target.listID
                                        listProxy.scrollTo(
                                            target.listID, anchor: presentation == .standard ? .center : .leading)
                                    }

                                    .onChange(of: boardTargetListID)
                                    {
                                        _, targetListID in
                                        guard targetListID != nil else
                                        {


                                            return
                                        }


                                        withAnimation(.easeInOut(duration: 0.25))
                                        {

                                            openPendingBoardTarget(using: listProxy)
                                        }

                                    }

                                    .onChange(of: boardTargetCardID)
                                    {
                                        _, cardID in
                                        guard cardID != nil else
                                        {


                                            return
                                        }


                                        withAnimation(.easeInOut(duration: 0.25))
                                        {

                                            openPendingBoardTarget(using: listProxy)
                                        }

                                    }

                                    .onChange(of: boardBoundaryJumpRequest)
                                    {
                                        _, _ in

                                        guard
                                        let target =
                                        boardBoundaryJumpTarget, /* Requested first or last list boundary          */
                                        let listID = BoardListReordering.boundaryListID(target, in: lists)
                                        else
                                        {  /* Active list resolved at the requested boundary */


                                            return
                                        }


                                        withAnimation(.easeInOut(duration: 0.25))
                                        {

                                            listProxy.scrollTo(
                                                listID, anchor: presentation == .standard ? .center : .leading)
                                            visibleListID = listID
                                        }

                                    }

                                    .onAppear
                                    {

                                        if visibleListID == nil
                                        {


                                            visibleListID = lists.first?.id
                                        }


                                        openPendingBoardTarget(using: listProxy)
                                    }

                                    .task(id: draggedListID)
                                    {

                                        guard let listID = draggedListID
                                        else
                                        {  /* List identity captured for the edge-navigation loop */


                                            return
                                        }


                                        do
                                        {


                                            while !Task.isCancelled
                                            {


                                                try await Task.sleep(for: .milliseconds(550))

                                                guard draggedListID == listID,
                                                let location =
                                                listDragLocation, /* Latest pointer position during list edge navigation */
                                                let source = lists.firstIndex(where:
                                                    {
                                                        $0.id == listID
                                                    })
                                                else
                                                {

                                                    continue
                                                }  /* Current dragged-list position                       */

                                                let direction = BoardListReordering.edgeDirection(
                                                    at: location, viewportWidth: listArea.size.width) /* Activated left or right viewport edge               */
                                                let destination =
                                                source
                                                + direction /* Neighbor position reached by edge navigation        */

                                                guard direction != 0, lists.indices.contains(destination) else
                                                {


                                                    continue
                                                }


                                                withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2))
                                                {

                                                    _ = BoardListReordering.move(listID, to: destination, in: &lists)
                                                }


                                                await Task.yield()

                                                guard !Task.isCancelled, draggedListID == listID else
                                                {


                                                    return
                                                }


                                                withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2))
                                                {

                                                    listProxy.scrollTo(listID, anchor: .center)
                                                }

                                            }

                                        }
                                        catch is CancellationError
                                        {


                                        // Releasing the header cancels edge scrolling.

                                        }
                                        catch
                                        {

                                            DatabaseActivity.shared.report(
                                                                                                                                    "Could not move the list: \(error.localizedDescription)")
                                        }

                                    }

                                    .task(id: draggedCardID)
                                    {

                                        guard let cardID = draggedCardID
                                        else
                                        {  /* Card identity captured for the edge-navigation loop */


                                            return
                                        }


                                        do
                                        {


                                            while !Task.isCancelled
                                            {


                                                try await Task.sleep(for: .milliseconds(550))

                                                guard draggedCardID == cardID, let location = cardDragLocation
                                                else
                                                {  /* Latest global pointer position during card edge navigation */


                                                    continue
                                                }


                                                let direction =
                                                BoardListReordering.edgeDirection( /* Activated edge relative to the card-drag viewport */
                                                    at: location.x - dragGeometry.viewport.minX,
                                                    viewportWidth: dragGeometry.viewport.width
                                                )
                                                guard direction != 0,
                                                let current = lists.firstIndex(where:
                                                    {
                                                        $0.id == visibleListID
                                                    }
                                                ), /* Position of the currently visible list */

                                                lists.indices.contains(current + direction)
                                                else
                                                {
                                                    continue
                                                }

                                                let nextID = lists[current + direction]
                                                .id /* Adjacent list identity to reveal during the card drag */

                                                withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2))
                                                {

                                                    listProxy.scrollTo(
                                                        nextID, anchor: presentation == .standard ? .center : .leading)
                                                    visibleListID = nextID
                                                }

                                            }

                                        }
                                        catch is CancellationError
                                        {


                                        // Release or cancellation stops edge scrolling without moving a card.

                                        }
                                        catch
                                        {

                                            DatabaseActivity.shared.report(
                                                                                                                                    "Could not scroll while moving the card: \(error.localizedDescription)")
                                        }

                                    }
                                    .onDisappear
                                    {

                                        if let listID = draggedListID
                                        {  /* List drag canceled before opening a card destination */


                                            endListDrag(listID)
                                        }


                                        if let cardID = draggedCardID
                                        {  /* Card drag canceled before opening a card destination */


                                            endCardDrag(cardID, commit: false)
                                        }

                                    }

                                }

                            }

                            .overlay(alignment: .bottomTrailing)
                            {

                                if usesFreeBoardScrolling
                                {

                                    BoardZoomHint(percentage: Int((boardZoomScale * 100).rounded()))
                                    .padding(.trailing, 16)
                                }

                            }
                            .padding(.bottom, 32)
                        }

                    }

                }

            }

            .toolbar(.hidden, for: .navigationBar)
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect())
            {
                todayHighlightDate = $0
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
            {

            _ in
                todayHighlightDate = .now
            }
            .onChange(of: boardScale)
            {
                _, value in
                viewportMemory.state.scale = Double(value);
                viewportMemory.scheduleSave()
            }
            .onChange(of: isPanoramic)
            {
                _, value in
                viewportMemory.state.panoramic = value;
                viewportMemory.scheduleSave()
            }
            .onChange(of: isGallery)
            {
                _, value in
                viewportMemory.state.gallery = value;
                viewportMemory.scheduleSave()
            }
            .onChange(of: presentation)
            {
                _, value in
                viewportMemory.state.presentation = value.rawValue;
                viewportMemory.scheduleSave()
            }
            .onChange(of: visibleListID)
            {
                _, value in
                viewportMemory.state.visibleListID = value;
                viewportMemory.scheduleSave()
            }
            .onChange(of: scenePhase)
            {
                _, value in
                if value != .active
                {
                    persistViewport()
                }
                else
                {
                    todayHighlightDate = .now
                }

            }
            .onDisappear
            {
                persistViewport()
            }
            .onChange(of: navigationPath.count)
            {
                old, new in
                if openedDirectItem && old > 0 && new == 0
                {

                    openedDirectItem = false
                    directItemReturn?()
                }

            }
            .onChange(of: boardRootRequest)
            {
                _, _ in
                navigationPath = NavigationPath()
            }
            .onChange(of: boardTargetListID)
            {
                _, target in
                if target != nil
                {
                    isGallery = false
                }

            }
            .navigationDestination(for: KanbanCard.self)
            {
                card in
                CardDetailView(
                    card: card,
                    labelLibrary: $labelLibrary,
                    availableLists: lists.filter
                    {
                        list in
                        !list.cards.contains(where:
                            {
                                $0.id == card.id
                            })
                    },
                    memberColors: memberColors,
                    currentUserName: currentUserName,
                    savedCardIDs: $savedCardIDs,
                    onTitleToggle:
                    {
                        updatedCard in
                        updateCard(updatedCard)
                    },
                    onMoveToList:
                    {
                        destinationListID in
                        moveCard(card.id, toListID: destinationListID)
                    },
                    personalCollectionID: personalCollectionID,
                    availablePersonalLists: availablePersonalLists,
                    onMoveNoteToPersonalList: onMoveNoteToPersonalList,
                    onUpdateMovedNote: onUpdateMovedNote,
                    onArchiveMovedNote: onArchiveMovedNote,
                    onDeleteMovedNote: onDeleteMovedNote,
                    onToggleMovedNoteBookmark: onToggleMovedNoteBookmark,
                    onArchive:
                    {

                        archiveCard(card.id)
                    },
                    onDelete:
                    {

                        deleteCard(card.id)
                    },
                    listedOnDate: lists.first(where:
                        {
                            $0.cards.contains(where:
                                {
                                    $0.id == card.id
                                })
                        }).flatMap
                    {

                        dayDate(for: $0.id)
                    }
                )
                .id(card.id)
                .environment(\.cardKeyboardNavigation, keyboardNavigation(for: card))
                .environment(\.cardMovementSource, personalCollectionID)
            }

            .fullScreenCover(
                isPresented: Binding(
                    get:
                    {
                        focusedDayListID != nil
                    },
                    set:
                    {
                        if !$0
                        {
                            focusedDayListID = nil
                        }

                    }
                )
            )
            {

                if let listID = focusedDayListID
                {

                    TodayListDetailView(
                        lists: $lists,
                        reservedLists: archivedLists,
                        labelLibrary: $labelLibrary,
                        savedCardIDs: $savedCardIDs,
                        listID: listID,
                        currentUserName: currentUserName,
                        onClose:
                        {
                            focusedDayListID = nil
                        },
                        onOpenWeek:
                        {

                            boardTargetListID = listID
                            focusedDayListID = nil
                        },
                        onPermanentDelete: deleteCard,
                        boardAppearance: storedBoardAppearance,
                        returnDestinationTitle: personalCollectionID == nil ? "Week" : boardTitle,
                        boardViewActionTitle: personalCollectionID == nil
                        ? "Switch to Week View" : "Switch to Board View",
                        representedDate: dayDate(for: listID)
                    )
                    .environment(\.workspaceBottomBarHeight, 0)
                    .environment(\.cardMovementSource, personalCollectionID)
                }

            }
            .sheet(item: $listToMove)
            {
                source in
                MoveListDestinationSheet(
                    source: source, access: planningCalendarAccess, currentID: personalCollectionID
                )
                .databaseActivityOverlay()
            }
            .sheet(item: $listToCopy)
            {
                source in
                CopyListDestinationSheet(
                    source: source, access: planningCalendarAccess, currentID: personalCollectionID
                )
                {

                    copyList(with: source.id)
                    return true
                }

            }
            .sheet(isPresented: $showsBoardAppearance)
            {

                BoardAppearanceSheet(
                    appearance: storedBoardAppearance, presentation: presentation,
                    onSavePresentation:
                    {
                        presentation = $0
                    },
                    allowsCollectionBackground: allowsCollectionBackground,
                    defaultCollectionBackground: isStandaloneListView
                    ? CollectionBackground.defaultListBackground(for: lists.first?.title ?? boardTitle) : nil,
                    listSurface: isStandaloneListView ? lists.first : nil,
                    listHeaderIcon: planningCalendarAccess?.library.first(where:
                        {
                            $0.id == personalCollectionID
                        })?
                    .icon,
                    onSaveListSurface:
                    {
                        value, showsHeaderIcon, icon, iconColor in
                        guard isStandaloneListView, !lists.isEmpty else
                        {
                            return
                        }

                        var appearance = lists[0].appearance ?? ItemAppearance()
                        appearance.listBackgroundOpacity = value
                        appearance.showsIconInHeader = showsHeaderIcon
                        appearance.icon = icon
                        appearance.iconColor = iconColor
                        lists[0].appearance = appearance
                    },
                    onSave: saveBoardAppearance)
            }
            .modifier(LowerCornerBackShortcut(action: onClose))
            .modifier(
                PlanningSharedSearchPresentation(
                    isPresented: $showsSharedSearch,
                    onLeaveForHome:
                    {

                        onClose?();
                        planningHomeExit?()
                    })
            )
            .sheet(isPresented: $showsWeekSelector)
            {

                if let access = planningCalendarAccess
                {

                    PlanningWeekSelector(
                        initialDate: dayDate(for: visibleListID ?? lists.first?.id ?? -1) ?? calendarOpeningDate,
                        document: access.document,
                        selectedWeekKey: personalCollectionID.flatMap
                        {
                            id in
                            access.document.weeks.first
                            {
                                $0.id == id
                            }?.startKey
                        }

                        ?? PlanningDate.weekKey(calendarOpeningDate, calendar: access.document.calendar),
                        sources: access.searchableItems
                    )
                    {
                        week, date in
                        showsWeekSelector = false
                        if let open = access.openWeekOnDay
                        {
                            open(week, date)
                        }
                        else
                        {
                            access.openWeek(week)
                        }

                    }

                }

            }
            .sheet(
                isPresented: $showsCalendar,
                onDismiss:
                {

                    guard let target = calendarCardTarget else
                    {
                        return
                    }

                    calendarCardTarget = nil
                    guard let list = lists.first(where:
                        {
                            $0.id == target.listID && !$0.isArchived
                        }),
                    let card = list.cards.first(where:
                        {
                            $0.id == target.cardID && !$0.isSectionDivider
                        })
                    else
                    {

                        DatabaseActivity.shared.report(
                                                                        "Could not open this Calendar card because it is no longer in the active list. Its retained content has not been changed."
                        )
                        return
                    }

                    visibleListID = list.id
                    navigationPath = NavigationPath()
                    navigationPath.append(card)
                }
            )
            {

                if planningCalendarAccess != nil
                {

                    PlanningCalendarView(
                        initialDate: calendarOpeningDate,
                        onLeaveForHome:
                        {

                            showsCalendar = false;
                            onClose?();
                            planningHomeExit?()
                        }
                    )
                    .presentationDetents([.large])
                }
                else
                {

                    TodayCalendarView(
                        lists: lists,
                        onArchiveCard: archiveCard,
                        onDeleteCard:
                        {
                            deleteCard($0)
                        }
                    )
                    {
                        listID, cardID in
                        calendarCardTarget = (listID: listID, cardID: cardID)
                        showsCalendar = false
                    }

                    .presentationDetents([.large])
                }

            }

            .sheet(isPresented: $showsArchivedLists)
            {

                ArchivedListsView(
                    lists: $archivedLists, onRestore: restoreArchivedList, onDelete: deleteList,
                    onDeleteCard:
                    {
                        _, cardID in
                        deleteCard(cardID)
                    }
                )
                .databaseActivityOverlay()
            }

            .environment(\.checklistLinkCandidates, lists.flatMap(\.cards))
            .onChange(of: lists)
            {
                _, updatedLists in
                onListsChanged(updatedLists)
            }

            .onChange(of: labelLibrary)
            {
                _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }

        }

    }

}


// -------------------------------------- MARK: - Previews -------------------------------------- //

/// Preview the complete board presentation with deterministic sample data
#Preview
{

    ContentView(lists: .constant(SampleData.lists))
}
