// --------------------------------------------------------------------------------------------------
// @file       TodayHomeView.swift
// @brief      Today's main composition and capture entry points
// @details    Presents the selected Day, shortcuts, planning context, and full capture
//             destinations without duplicating canonical tasks. Focus observes live workspace edits
//             directly; a separate clock advances time-sensitive selections and weekday changes.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Presents today's plan selection and direct access to existing board lists
///
/// @section    Purpose
///     Provide a calm entry point into the user's existing day list without duplicating task data
///
/// @note   The selected list is stored locally for the current calendar date
///
struct TodayHomeView: View
{


    @ScaledMetric(relativeTo: .subheadline) private var browseIconSize: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var browseTextSize: CGFloat = 18.75
    @AppStorage(PlanPreferencesStore.key) private var planPreferencesData = Data()
    @EnvironmentObject private var welcomeCue: TodayWelcomeCue
    @Environment(\.accessibilityReduceMotion) private var reduceWelcomeMotion
    @Environment(\.planningCalendarAccess) private var planningCalendarAccess


    ///
    /// @fcn        TodayHomeView.calendarDayList
    /// @brief      Resolve the active list representing a particular day
    /// @details    Uses the available current-week snapshot or retained calendar mapping and returns nil when no
    ///             active matching list is available.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  snapshot  Snapshot values or directory used for the operation
    ///
    /// @return     (KanbanList?) active list mapped to the requested date, or nil when unavailable
    ///
    private func calendarDayList(_ date: Date, in snapshot: [KanbanList]? = nil) -> KanbanList?
    {

        let lists = snapshot ?? self.lists
        if let id = planningCalendarAccess?.document.week(for: date)?.dayListIDs[PlanningDate.key(date)],
        let list = lists.first(where:
            {
                $0.id == id && !$0.isArchived
            })
        {

            return list
        }

        return TodayListSelection.currentDayList(in: lists, date: date)
    }


    @Binding var lists:         [KanbanList]            /* Shared local Board lists                           */
    @Binding var archivedLists: [KanbanList]            /* Archived Week lists retained for example-load undo */
    @Binding var savedCardIDs:  Set<Int>                /* Device-local bookmarks used by card details        */
    let profile:                LocalProfile?           /* Current local profile and preferences              */
    let onSaveProfile:          (LocalProfile) -> Void  /* Save local identity and personalization            */
    let onRemoveProfile:        () -> Void              /* Remove only local profile information              */
    let onAddCard:
    (Int, String, String, String, ItemPresentation?, [String]?) ->
    Void /* Create canonical Week records                      */
    let onAddCapture:           (QuickCaptureSubmission) -> Bool
    let onToggleCardCompletion: (Int, Int) -> Void  /* Toggle local card completion                  */
    let onOpenBoardList:        (Int) -> Void       /* Route to Board at the selected list ID        */
    let onOpenBoardCard:        (Int, Int) -> Void  /* Route to a Week card by list/card IDs         */
    let onArchiveCard:          (Int) -> Void       /* Retain a canonical Week card                  */
    let onDeleteCard:           (Int) -> Bool       /* Report successful confirmed Week card removal */
    let onArchiveList:          (Int) -> Void       /* Retain a canonical Week list                  */
    let onDeleteList:           (Int) -> Bool       /* Report successful confirmed Week list removal */
    let quickCreateRequest:     Int                 /* Center-bar requests for the Today composer    */

    @State private var selectedTodayListID: Int?                  /* Board list selected for today's plan  */
    @State private var listPickerMode:      TodayListPickerMode?  /* Active list picker presentation mode  */
    @State private var showsAccountSettings = false               /* Account & Settings sheet presentation */
    @AppStorage("Plenact.LibraryImportant.v1") private var focusImportantData = Data()
    @Environment(\.workspaceBottomBarHeight) private var focusToolbarHeight
    @State private var removedFocusBookmark: Int?
    @State private var bookmarkNoticeRevision = UUID()
    @State private var focusDate = Date.now
    @State private var focusFiltersChangedAt:  Date?
    @State private var perspectiveSectionTop:  CGFloat = 0
    @State private var shortcutsSectionBottom: CGFloat = 0
    @State private var openedFocusCard:        KanbanCard?
    @State private var showsTodayList = false /* Focused single-list presentation         */
    @State private var showsTodayPlan = false
    @State private var perspectivePlanDate: Date = .now
    @State private var showsPerspectivePlan = false
    @ObservedObject private var reviewNotifications = ReviewRhythmNotifications.shared
    @State private var reviewRoute: ReviewRhythmRoute?
    @State private var showsReviewRhythmSettings = false
    @AppStorage(TodayListPins.key) private var listPinData = Data()
    @State private var openedShortcut: WorkspaceListReference?

    @State private var focusedListID: Int?             /* Current-day list selected when opening Focus */
    @State private var quickCaptureTitle = ""          /* Draft title for inline card capture          */
    @State private var quickComposerInitialTitle = ""  /* Quick-capture title handed to full editor    */
    @State private var showsQuickNoteEditor = false    /* Full-size quick card editor presentation     */
    @State private var showsTemplates = false
    @State private var pendingTemplate:             QuickCaptureTemplate?
    @State private var composerInitialPresentation: ItemPresentation?
    @State private var composerTemplate:            QuickCaptureTemplate?
    @State private var captureAction:               TodayCaptureAction?
    @State private var showsPlanSettings = false
    @State private var showsSearch = false                      /* Local Board search presentation          */
    @State private var presentComposerAfterListChoice = false   /* Deferred center-plus request             */
    @State private var labelLibrary = LabelLibraryStore.load()  /* Local categorized label definitions      */
    @State private var isContentScrolled = false                /* If content is passing beneath the header */


    ///
    /// @fcn        TodayHomeView.selectedTodayList
    /// @brief      Resolve today's saved list selection against the current board
    /// @details    Uses the in-memory date selection, or the profile default when no selection is set;
    ///             an unavailable effective ID returns no list rather than choosing another destination
    ///
    /// @return     (KanbanList?) selected list from the supplied active snapshot
    /// @post       No preference is read or changed during resolution
    ///
    private var selectedTodayList: KanbanList?
    {  /* Board list selected for the current date */


        let resolvedListID = selectedTodayListID /* Calendar-derived or explicitly chosen Today list */

        guard let resolvedListID else
        {  /* Available Week destination for new content */


            return nil
        }  /* No saved or default list selection */


        return lists.first
        {
            $0.id == resolvedListID
        }

    }


    ///
    /// @fcn        TodayHomeView.todayHeader
    /// @brief      Build the Today title, current date, search, and profile controls
    /// @details    Presents accessible entry buttons for Board search and local Account & Settings
    ///             within the shared maximum content width
    ///
    /// @return     (some View) Today header content
    /// @post       Tapping controls updates sheet-presentation state without modifying Board data
    ///
    private var todayHeader: some View
    {  /* Today's heading and account controls */


        HStack(alignment: .center, spacing: 0)
        {

            VStack(alignment: .leading, spacing: 4)
            {

                Text("Today")
                .font(.largeTitle.weight(.bold))
                Button
                {

                    showsTodayPlan = true
                }
                label:
                {

                    Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(
                    TodayWelcomeGlow(
                        highlighted: UIDevice.current.userInterfaceIdiom != .pad && welcomeCue.highlights(.plan))
                )
                .accessibilityLabel("Today's Plan, " + Date.now.formatted(date: .complete, time: .omitted))
                .accessibilityHint("Opens your saved priorities and context for today")
                .accessibilityIdentifier("today.plan")
            }


            Spacer()

            Button
            {

                showsSearch = true
            }
            label:
            {

                WorkspaceHeaderIcon(systemName: "magnifyingglass")
            }

            .buttonStyle(.plain)
            .accessibilityLabel("Search Plenact")

            Button
            {

                showsPlanSettings = true
            }
            label:
            {

                WorkspaceHeaderIcon(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plan Settings")
            .accessibilityHint("Configure Today, planning, and templates")

            Button
            {

                showsAccountSettings = true
            }
            label:
            {

                ProfileAvatarView(profile: profile, size: 44)
                .modifier(TodayWelcomeGlow(highlighted: welcomeCue.highlights(.profile), circular: true))
            }

            .buttonStyle(.plain)
            .accessibilityLabel(profile == nil ? "Create local profile" : "Open Account and Settings")
        }

        .frame(maxWidth: .infinity, alignment: .leading)
    }


    ///
    /// @fcn        TodayHomeView.todayHeaderPanel
    /// @brief      Place the Today header on a clipped paper-backed panel
    /// @details    Extends decoration through the top safe area and shows a bottom fade
    ///             when observed scroll content moves beneath the header
    ///
    /// @return     (some View) padded header with noninteractive background and fade
    /// @post       Rendering does not change scroll or navigation state
    ///
    private var todayHeaderPanel: some View
    {  /* Styled container for Today's heading */


        todayHeader
        .padding(.horizontal, 20)
        .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? -22 : 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background
        {

            GeometryReader
            {
                geometry in
                ZStack(alignment: .top)
                {

                    Color(.systemBackground)

                    Image("TodayPaper")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.width * (2796.0 / 1290.0),
                        alignment: .top
                    )
                    .clipped()
                }

                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
            }

            .clipped()
            .ignoresSafeArea(edges: .top)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }

        .overlay(alignment: .bottom)
        {

            if isContentScrolled
            {


                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 10)
                .offset(y: 8)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

        }

        .animation(.easeOut(duration: 0.15), value: isContentScrolled)
    }


    ///
    /// @fcn        TodayHomeView.focusBookmarkUndoNotice
    /// @brief      Offer a short-lived way to restore the last Focus bookmark
    /// @details    Anchored to the screen above the workspace toolbar, independently of scrolling content.
    ///             Lives outside the filtered rows so removing their membership cannot dismiss Undo.
    ///             Slides into and out of its fixed position; Reduce Motion uses a short fade.
    ///             Restores only the removed identifier, preserving any other bookmark edits.
    ///
    /// @return     (some View) accessible bottom notice while a removal is pending
    ///
    @ViewBuilder
    private var focusBookmarkUndoNotice: some View
    {
        if let cardID = removedFocusBookmark
        {
            HStack
            {
                Text("Bookmark removed")
                Spacer()
                Button("Undo")
                {
                    savedCardIDs.insert(cardID)
                    removedFocusBookmark = nil
                    bookmarkNoticeRevision = UUID()
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("today.focus.bookmark.undo")
            }
            .font(.subheadline)
            .padding(16)
            .background(
                .regularMaterial,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 14
                )
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .accessibilityElement(children: .contain)
            .transition(
                reduceWelcomeMotion
                ? .opacity
                : .offset(y: 90).combined(with: .opacity)
            )
        }
    }


    ///
    /// @fcn        TodayHomeView.init
    /// @brief      Initialize Today with Board lists, local profile state, and callbacks
    /// @details    Restores the date-specific list selection and connects profile persistence and
    ///             Board navigation actions
    ///
    /// @param[in]  lists                   Binding to active Week lists
    /// @param[in]  archivedLists           Binding to archived Week lists retained for example-load undo
    /// @param[in]  savedCardIDs            Binding to device-local Week bookmarks
    /// @param[in]  profile                 Optional local identity and personalization
    /// @param[in]  onSaveProfile           Callback that saves a complete local profile
    /// @param[in]  onRemoveProfile         Callback that removes only local profile data
    /// @param[in]  onAddCard               Callback receiving destination ID, title, and description
    /// @param[in]  onToggleCardCompletion  Callback receiving list/card identities to toggle
    /// @param[in]  onOpenBoardList         Callback opening a Week list by ID
    /// @param[in]  onOpenBoardCard         Callback opening a Week card by list/card IDs
    /// @param[in]  quickCreateRequest      Observable request counter for the central New control
    ///
    /// @param[in]  onAddCapture            Checked callback creating the complete capture submission in its
    ///             destination
    /// @param[in]  onArchiveCard           Optional owner action retaining the selected Card in its archive
    /// @param[in]  onDeleteCard            Checked owner action permanently removing the selected Card
    /// @param[in]  onArchiveList           Optional owner action retaining the selected List in its archive
    /// @param[in]  onDeleteList            Checked owner action permanently removing the selected List
    ///
    /// @return     (TodayHomeView) configured Today screen
    ///
    /// @pre        lists reflects the current in-memory board state
    /// @post       The initial selection is resolved; when neither saved nor profile choice exists,
    ///             a resolved starter selection is stored for today. Board content is unchanged
    ///
    init(
        lists: Binding<[KanbanList]>,
        archivedLists: Binding<[KanbanList]>,
        savedCardIDs: Binding<Set<Int>>,
        profile: LocalProfile?,
        onSaveProfile: @escaping (LocalProfile) -> Void,
        onRemoveProfile: @escaping () -> Void,
        onAddCard: @escaping (Int, String, String, String, ItemPresentation?, [String]?) -> Void,
        onAddCapture: @escaping (QuickCaptureSubmission) -> Bool,
        onToggleCardCompletion: @escaping (Int, Int) -> Void,
        onOpenBoardList: @escaping (Int) -> Void,
        onOpenBoardCard: @escaping (Int, Int) -> Void,
        onArchiveCard: @escaping (Int) -> Void,
        onDeleteCard: @escaping (Int) -> Bool,
        onArchiveList: @escaping (Int) -> Void,
        onDeleteList: @escaping (Int) -> Bool,
        quickCreateRequest: Int
    )
    {


        self._lists = lists
        self._archivedLists = archivedLists
        self._savedCardIDs = savedCardIDs
        self.profile = profile
        self.onSaveProfile = onSaveProfile
        self.onRemoveProfile = onRemoveProfile
        self.onAddCard = onAddCard
        self.onAddCapture = onAddCapture
        self.onToggleCardCompletion = onToggleCardCompletion
        self.onOpenBoardList = onOpenBoardList
        self.onOpenBoardCard = onOpenBoardCard
        self.onArchiveCard = onArchiveCard
        self.onDeleteCard = onDeleteCard
        self.onArchiveList = onArchiveList
        self.onDeleteList = onDeleteList
        self.quickCreateRequest = quickCreateRequest

        _selectedTodayListID = State(
            initialValue: TodayListSelection.currentDayList(in: lists.wrappedValue, date: .now)?.id)
    }


    ///
    /// @fcn        TodayHomeView.cardCount(in:)
    /// @brief      Count actionable cards in a board list
    /// @details    Excludes divider rows because they organize content rather than represent tasks
    ///
    /// @param[in]  list  Board list whose cards are counted
    ///
    /// @return     (Int) number of non-divider cards in the list
    ///
    /// @pre        list contains its current card collection
    /// @post       No list data is modified
    ///
    private func cardCount(in list: KanbanList) -> Int
    {


        list.cards.filter
        {
            !$0.isSectionDivider
        } .count
    }


    /// Pinned, owner-qualified list shortcuts chosen by the user and persisted across launches.
    private var yourShortcutsSection: some View
    {

        let owners = WorkspaceBrowseIndex.owners(
            document: planningCalendarAccess?.document, library: planningCalendarAccess?.library ?? [])
        let available = WorkspaceBrowseIndex.lists(in: owners)
        let pinned = TodayListPins.decode(listPinData).compactMap
        {
            reference in
            available.first
            {
                $0.reference == reference
            }

        }

        return TodayShortcutGrid(pinned: pinned, onOpen:
            {
                openedShortcut = $0
            })
    }


    ///
    /// @fcn        TodayHomeView.browseListsAction
    /// @brief      Provide the Browse this week entry point
    /// @details    Opens the shared list picker in navigation mode rather than Today-selection mode
    ///
    /// @return     (some View) accessible list-browsing button
    /// @post       Tapping sets listPickerMode to browseAll
    ///
    private var browseListsAction: some View
    {  /* Library navigation action */


        Button
        {

            listPickerMode = .browseAll
        }
        label:
        {

            HStack(spacing: 10)
            {

                Spacer(minLength: 0)
                Text("Browse this week")
                .font(.system(size: browseTextSize))
                Image(systemName: "rectangle.3.group")
                .font(.system(size: browseIconSize))
                Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            }

            .font(.subheadline)
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }

        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }


    ///
    /// @fcn        TodayHomeView.addQuickCard()
    /// @brief      Submit a nonempty inline title to today's selected list
    /// @details    Trims surrounding whitespace and adds a card with no description. With no
    ///             selected list, opens the picker and keeps the draft for later submission
    ///
    /// @return     (Void) invokes onAddCard and clears the title when a destination resolves
    ///
    /// @post       Blank input does nothing; missing selection does not create or discard a card
    ///
    private func addQuickCard()
    {


        let title = quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines) /* Clean card title */

        guard !title.isEmpty else
        {


            return
        }


        guard let selectedTodayList else
        {  /* Current list targeted by Today actions */


            listPickerMode = .chooseToday

            return
        }


        onAddCard(selectedTodayList.id, title, "", "", nil, nil)
        quickCaptureTitle = ""
    }


    ///
    /// @fcn        TodayHomeView.openQuickNoteEditor()
    /// @brief      Request the full composer after ensuring a Today destination exists
    /// @details    Opens immediately for a resolved selection; otherwise records a deferred
    ///             composer request and presents the Today list picker
    ///
    /// @return     (Void) updates composer or list-picker presentation state
    ///
    /// @post       No card is created until the composer submits its content
    ///
    private func openQuickNoteEditor()
    {


        composerTemplate = nil
        captureAction = nil
        guard selectedTodayList != nil else
        {


            presentComposerAfterListChoice = true
            listPickerMode = .chooseToday

            return
        }


        presentQuickNoteEditor()
    }


    ///
    /// @fcn        TodayHomeView.openCapture(_:)
    /// @brief      Prepare the selected quick-capture mode
    /// @details    Cancels the welcome cue, clears the template, and retains the capture action.
    ///             Requests a Today List first when no destination is selected; otherwise opens the
    ///             full composer.
    ///
    /// @param[in]  action  Requested quick-capture mode, including photo, voice, or drawing entry
    ///
    /// @return     (Void) opens capture or requests its missing destination
    ///
    private func openCapture(_ action: TodayCaptureAction)
    {

        welcomeCue.cancel()
        composerTemplate = nil
        captureAction = action
        guard selectedTodayList != nil else
        {

            presentComposerAfterListChoice = true
            listPickerMode = .chooseToday
            return
        }

        presentQuickNoteEditor()
    }


    ///
    /// @fcn        TodayHomeView.presentQuickNoteEditor
    /// @brief      Open the full-featured quick capture editor
    /// @details    Selects the current quick-note creation presentation from the Today home view.
    ///
    /// @return     (Void) no return value
    ///
    private func presentQuickNoteEditor()
    {


        quickComposerInitialTitle = quickCaptureTitle
        quickCaptureTitle = ""
        showsQuickNoteEditor = true
    }


    ///
    /// @fcn        TodayHomeView.selectTodayList(_:)
    /// @brief      Save a board list as today's plan
    /// @details    Updates view state and the current date preference, dismisses the list picker,
    ///             and yields before opening any deferred full-composer request
    ///
    /// @param[in]  list  Existing board list selected for today
    ///
    /// @return     (Void) updates the local Today preference and dismisses the picker
    ///
    /// @pre        list is present in the current board list collection
    /// @post       The selected list ID is stored locally for the current date
    ///
    private func selectTodayList(_ list: KanbanList)
    {


        selectedTodayListID = list.id

        let shouldPresentComposer = presentComposerAfterListChoice /* Deferred New-button action */

        presentComposerAfterListChoice = false
        listPickerMode = nil

        if shouldPresentComposer
        {


            Task
            {
                @MainActor in
                await Task.yield()
                presentQuickNoteEditor()
            }

        }

    }


    ///
    /// @fcn        TodayHomeView.ensureCurrentWeekdayList()
    /// @brief      Ensure Quick capture targets an active list for the real local weekday
    /// @details    Recreates a missing or renamed weekday list as a new blank list, retaining all
    ///             existing active and archived records and reserving IDs across both partitions
    ///
    /// @return     (Void) updates Today selection and the shared Week snapshots when necessary
    ///
    /// @post       No existing list or card is replaced or removed
    ///
    private func ensureCurrentWeekdayList()
    {

        if let current = calendarDayList(.now)
        {
            selectedTodayListID = current.id;
            return
        }

        let result = TodayListSelection.ensureCurrentDayList(lists: lists + archivedLists)
        let activeLists = result.lists.filter
        {
            !$0.isArchived
        }  /* Updated active Week lists     */

        let retainedLists = result.lists.filter(\.isArchived) /* Preserved archived Week lists */

        if activeLists != lists
        {


            lists = activeLists
        }


        if retainedLists != archivedLists
        {


            archivedLists = retainedLists
        }


        selectedTodayListID = result.dayList.id
    }


    ///
    /// @fcn        TodayHomeView.body
    /// @brief      Build the Today front-door screen
    /// @details    Composes quick capture, Today focus, applied labels, and list browsing.
    ///             Coordinates profile, example-load/undo, focused-list, search, label, and composer sheets
    ///
    /// @return     (some View) scrollable Today content and its list picker sheet
    ///
    /// @pre        lists contains the current board state and callbacks are configured
    /// @post       Callbacks route Board edits/navigation; label changes persist locally,
    ///             and example-load/undo callbacks replace both active and archived Week partitions
    ///
    var body: some View
    {  /* Today screen and list-selection sheets */


        NavigationStack
        {


            ScrollView
            {


                GeometryReader
                {
                    geometry in
                    Color.clear.preference(
                        key: TodayScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("TodayScroll")).minY
                    )
                }

                .frame(height: 0)

                VStack(alignment: .leading, spacing: 16)
                {

                    if UIDevice.current.userInterfaceIdiom == .pad
                    {

                        TimelineView(.everyMinute)
                        {
                            context in
                            TodayPlanSummaryPanel(
                                date: context.date, calendar: planningCalendarAccess?.document.calendar ?? .current,
                                sources: planningCalendarAccess?.searchableItems ?? [],
                                welcomesPlan: welcomeCue.highlights(.plan), onOpen:
                                {
                                    showsTodayPlan = true
                                }
                            )
                            .padding(16)
                        }
                        // Reclaim the action row’s 52 points from the space before capture.
                        .padding(.bottom, -16)
                    }

                    VStack(spacing: 0)
                    {

                        TodaySloganView()
                        .frame(minHeight: 40)
                        quickCaptureSection
                        .modifier(TodayPanelSurface(backgroundOpacity: 0.5))
                    }


                    // Read live workspace inputs directly; the clock only advances time-based selection.
                    let focusLists = lists
                    let focusBookmarks = savedCardIDs
                    let importantFocusIDs =
                    planningCalendarAccess?.document.weeks.first(where:
                        {

                            $0.startKey == planningCalendarAccess?.document.currentWeekKey
                        }).map
                    {
                        LibraryImportanceSelection.cardIDs(collectionID: $0.id, data: focusImportantData)
                    }

                    ?? []
                    // Keep the Focus identity stable while its contents and preferences change.
                    let focusPreferences =
                    (try? JSONDecoder().decode(LocalProfilePreferences.self, from: planPreferencesData))
                    ?? PlanPreferencesStore.load()
                    Group
                    {
                        let focus = calendarDayList(
                            focusDate, in: focusLists) /* Active list matching the current weekday */
                        let cards =
                        focus?.cards.filter
                        {
                            !$0.isSectionDivider
                        }

                        ?? [] /* Actionable records in the weekday list   */

                        TodayFocusSection(
                            list: focus,
                            cards: cards,
                            entries: focusPreferences.todayFocusEntries(
                                in: focus?.cards ?? [], on: focusDate,
                                calendar: planningCalendarAccess?.document.calendar ?? .current,
                                importantCardIDs: importantFocusIDs,
                                bookmarkedCardIDs: focusBookmarks),
                            groupsBySection: focusPreferences.todayFocusGroupsBySection,
                            visibleItemCount: focusPreferences.todayFocusItemCount,
                            chronological: focusPreferences.keepsDayListsInTimeOrder || focusPreferences.todayFocusOrder == .chronological,
                            includesImportant: focusPreferences.todayFocusIncludesImportant,
                            includesBookmarked: focusPreferences.todayFocusIncludesBookmarked,
                            includesUpNext: focusPreferences.todayFocusIncludesUpNext,
                            filtersChangedAt: focusFiltersChangedAt,
                            bookmarkedCardIDs: focusBookmarks,
                            importantCardIDs: importantFocusIDs,
                            onChangeFilters:
                            {
                                important, bookmarked, upNext in
                                var updated = PlanPreferencesStore.load()
                                updated.todayFocusIncludesImportant = important
                                updated.todayFocusIncludesBookmarked = bookmarked
                                updated.todayFocusIncludesUpNext = upNext
                                PlanPreferencesStore.save(updated)
                                if var profile
                                {
                                    profile.preferences = updated;
                                    onSaveProfile(profile)
                                }

                                focusFiltersChangedAt = .now
                            },
                            onRemoveBookmark:
                            {
                                cardID in
                                guard savedCardIDs.remove(cardID) != nil else
                                {
                                    return
                                }
                                removedFocusBookmark = cardID
                                bookmarkNoticeRevision = UUID()
                            },
                            onUpdateDate:
                            {
                                edited, isStart in
                                TodayFocusDateUpdate.apply(edited, isStart: isStart, to: &lists)
                            },
                            onToggleCard:
                            {
                                cardID in
                                if let focus
                                {  /* Weekday list available for navigation */


                                    onToggleCardCompletion(focus.id, cardID)
                                }

                            },
                            onOpenCard:
                            {
                                card in
                                openedFocusCard = card
                            },
                            onDeleteCard: onDeleteCard,
                            onOpenTodayList:
                            {

                                focusedListID = focus?.id
                                showsTodayList = focus != nil
                            }
                        )
                        .onChange(of: Calendar.current.startOfDay(for: focusDate))
                        {
                            _, _ in
                            ensureCurrentWeekdayList()
                        }

                    }

                    yourShortcutsSection
                    .onGeometryChange(for: CGFloat.self)
                    {

                        $0.frame(in: .named("TodaySectionContent")).maxY
                    }
                    action:
                    {

                        shortcutsSectionBottom = $0
                    }

                    browseListsAction
                    TimelineView(.everyMinute)
                    {
                        context in
                        let calendar = planningCalendarAccess?.document.calendar ?? .current
                        let tomorrow = calendar.date(byAdding: .day, value: 1, to: context.date) ?? context.date
                        let tomorrowList = planningCalendarAccess?.document.weeks.compactMap
                        {
                            $0.list(on: tomorrow)
                        }
                        .first
                        TodayPerspectiveSection(
                            completed: calendarDayList(context.date)?.cards.filter
                            {

                                !$0.isSectionDivider && $0.isTitleChecked
                            }
                            ?? [],
                            tomorrowList: tomorrowList,
                            onReview:
                            {
                                reviewRoute = $0
                            },
                            onSettings:
                            {
                                showsReviewRhythmSettings = true
                            },
                            onReflect:
                            {
                                showsTodayPlan = true
                            },
                            onPrepare:
                            {

                                perspectivePlanDate = tomorrow
                                showsPerspectivePlan = true
                            })
                    }
                    .padding(.top, 16)
                    .onGeometryChange(for: CGFloat.self)
                    {

                        $0.frame(in: .named("TodaySectionContent")).minY
                    }
                    action:
                    {

                        perspectiveSectionTop = $0
                    }

                }
                .padding(20)
                // Restore the space reclaimed by removing capture’s heading and destination caption on iPhone.
                .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 0 : 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 112)
                .coordinateSpace(name: "TodaySectionContent")
            }
            .scrollTargetBehavior(
                TodaySectionSnapBehavior(
                    perspectiveTop: perspectiveSectionTop,
                    shortcutsBottom: shortcutsSectionBottom, enabled: !reduceWelcomeMotion)
            )
            .modifier(TodayScrollFadeTracking(isScrolled: $isContentScrolled))
            .safeAreaInset(edge: .top, spacing: 0)
            {

                HStack(spacing: 0)
                {

                    Spacer(minLength: 0)
                    todayHeaderPanel
                    Spacer(minLength: 0)
                }

                .frame(maxWidth: .infinity)
                .zIndex(1)
            }
            .task
            {
                // Advance Up Next and the weekday at least once a minute without caching Card data.
                while !Task.isCancelled
                {
                    focusDate = .now
                    do
                    {
                        try await Task.sleep(for: .seconds(60))
                    }
                    catch
                    {
                        return
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification))
            {
                _ in
                focusDate = .now
            }
            .task(id: welcomeCue.requestID)
            {

                await welcomeCue.play(
                    reduceMotion: reduceWelcomeMotion,
                    planPulseSpeed: UIDevice.current.userInterfaceIdiom == .pad ? 1 : 1.3)
            }
            .onDisappear
            {
                welcomeCue.cancel()
            }
            .onChange(of: reduceWelcomeMotion)
            {
                _, _ in
                welcomeCue.cancel()
            }
            .simultaneousGesture(TapGesture().onEnded
                {
                    welcomeCue.cancel()
                })
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged
                {
                    _ in
                    welcomeCue.cancel()
                })
            .onChange(of: quickCaptureTitle)
            {
                _, _ in
                welcomeCue.cancel()
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollIndicators(.hidden)
            .onChange(of: planningCalendarAccess?.document.currentWeekKey)
            {
                _, _ in
                removedFocusBookmark = nil
                bookmarkNoticeRevision = UUID()
            }
            .task(id: bookmarkNoticeRevision)
            {
                guard removedFocusBookmark != nil else
                {
                    return
                }
                do
                {
                    try await Task.sleep(for: .seconds(1.5))
                }
                catch
                {
                    return
                }
                removedFocusBookmark = nil
            }
            .onDisappear
            {
                removedFocusBookmark = nil
                bookmarkNoticeRevision = UUID()
            }
            .background
            {

                GeometryReader
                {
                    geometry in
                    Image("TodayPaper")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay { StudioWorkspaceBackground(destination: .today) }
                    .accessibilityHidden(true)
                }

                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $openedShortcut)
            {
                reference in
                WorkspacePinnedListView(reference: reference)
                .environment(\.workspaceBottomBarHeight, 0)
            }
            .sheet(item: $reviewRoute)
            {
                ReviewRhythmDestination(route: $0)
            }
            .sheet(isPresented: $showsReviewRhythmSettings)
            {
                ReviewRhythmSettingsView()
            }
            .task(id: reviewNotifications.pending?.id)
            {

                // Preserve a tapped reminder until the current editor/sheet is closed.
                while let pending = reviewNotifications.pending, !Task.isCancelled
                {

                    let root = UIApplication.shared.connectedScenes.compactMap
                    {
                        $0 as? UIWindowScene
                    }
                    .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
                    if UIApplication.shared.applicationState == .active, root != nil,
                    root?.presentedViewController == nil,
                    reviewRoute == nil
                    {

                        reviewRoute = pending
                        reviewNotifications.pending = nil
                        break
                    }

                    try? await Task.sleep(for: .milliseconds(500))
                }

            }
            .sheet(isPresented: $showsTodayPlan)
            {

                TodayPlanView(calendar: planningCalendarAccess?.document.calendar ?? .current)
            }
            .sheet(isPresented: $showsPerspectivePlan)
            {

                TodayPlanView(
                    date: perspectivePlanDate, calendar: planningCalendarAccess?.document.calendar ?? .current)
            }
            .sheet(isPresented: $showsAccountSettings)
            {


                AccountSettingsView(
                    profile: profile,
                    lists: lists,
                    onSave: onSaveProfile,
                    onRemove: onRemoveProfile
                )
            }

            .fullScreenCover(item: $openedFocusCard)
            {
                card in
                TodayFocusCardDetailView(
                    card: card, lists: $lists, labelLibrary: $labelLibrary,
                    savedCardIDs: $savedCardIDs, currentUserName: profile?.displayName ?? "Justin Reina",
                    onDelete: onDeleteCard
                )
                .environment(\.workspaceBottomBarHeight, 0)
            }
            .fullScreenCover(isPresented: $showsTodayList)
            {

                if let focusedList = lists.first(where:
                    {
                        $0.id == focusedListID
                    })
                {  /* Current list associated with the focus selection */


                    TodayListDetailView(
                        lists: $lists,
                        reservedLists: archivedLists,
                        labelLibrary: $labelLibrary,
                        savedCardIDs: $savedCardIDs,
                        listID: focusedList.id,
                        currentUserName: profile?.displayName ?? "Justin Reina",
                        onClose:
                        {

                            showsTodayList = false
                        },
                        onOpenWeek:
                        {

                            showsTodayList = false
                            onOpenBoardList(focusedList.id)
                        },
                        onPermanentDelete: onDeleteCard,
                        focusesFirstUncheckedTask: true,
                        representedDate: .now
                    )
                    .environment(\.workspaceBottomBarHeight, 0)
                }

            }

            .sheet(
                isPresented: $showsQuickNoteEditor,
                onDismiss:
                {

                    if !quickComposerInitialTitle.isEmpty && quickCaptureTitle.isEmpty
                    {


                        quickCaptureTitle = quickComposerInitialTitle
                    }


                    quickComposerInitialTitle = ""
                    composerTemplate = nil
                    composerInitialPresentation = nil
                    captureAction = nil
                }
            )
            {


                if let selectedTodayList
                {  /* Current list receiving the Today edit */


                    QuickNoteComposer(
                        lists: $lists,
                        initialListID: selectedTodayList.id,
                        initialTitle: quickComposerInitialTitle,
                        template: composerTemplate,
                        captureAction: captureAction,
                        initialPresentation: composerInitialPresentation,
                        onSaveCapture:
                        {
                            capture in
                            let saved = onAddCapture(capture)
                            if saved
                            {
                                quickComposerInitialTitle = ""
                            }

                            return saved
                        }
                    )
                    {
                        listID, title, description, subtitle, presentation, actions in
                        onAddCard(listID, title, description, subtitle, presentation, actions)
                        quickComposerInitialTitle = ""
                    }

                    .databaseActivityOverlay()
                }

            }

            .sheet(
                isPresented: $showsTemplates,
                onDismiss:
                {

                    guard let template = pendingTemplate else
                    {
                        return
                    }

                    pendingTemplate = nil
                    ensureCurrentWeekdayList()
                    composerTemplate = template
                    captureAction = nil
                    presentQuickNoteEditor()
                }
            )
            {

                QuickCaptureTemplatesView
                {
                    template in
                    pendingTemplate = template
                    showsTemplates = false
                }

            }

            .modifier(PlanningSharedSearchPresentation(isPresented: $showsSearch))
            .sheet(isPresented: $showsPlanSettings)
            {

                PlanSettingsView(lists: lists, onSaveProfile: onSaveProfile)
            }


            .onAppear
            {

                labelLibrary = LabelLibraryStore.load()
                ensureCurrentWeekdayList()
            }

            .onChange(of: quickCreateRequest)
            {
                _, _ in
                composerInitialPresentation = .card
                openQuickNoteEditor()
            }

            .onChange(of: lists)
            {
                _, _ in
                ensureCurrentWeekdayList()
                if showsTodayList
                {
                    focusedListID = calendarDayList(.now)?.id
                }

            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
            {

            _ in
                focusDate = .now
                ensureCurrentWeekdayList()
                if showsTodayList
                {
                    focusedListID = calendarDayList(.now)?.id
                }

            }

            .onChange(of: labelLibrary)
            {
                _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }

            .sheet(item: $listPickerMode)
            {
                mode in

                NavigationStack
                {


                    List
                    {


                        ForEach(lists)
                        {
                            list in

                            Button
                            {

                                switch mode
                                {


                                case .chooseToday:
                                    selectTodayList(list)
                                case .browseAll:
                                    listPickerMode = nil
                                    onOpenBoardList(list.id)
                                }

                            }
                            label:
                            {

                                HStack
                                {

                                    VStack(alignment: .leading, spacing: 4)
                                    {


                                        Text(list.title)
                                        .foregroundStyle(.primary)

                                        Text("\(cardCount(in: list)) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }


                                    Spacer()

                                    if selectedTodayListID == list.id
                                    {


                                        Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                    }

                                }

                                .contentShape(Rectangle())
                            }

                            .buttonStyle(.plain)
                            .accessibilityHint(
                                mode == .chooseToday ? "Sets this as today's plan" : "Opens this list on the board"
                            )
                            .modifier(
                                ContentLifecycleActions(
                                    title: list.title, kind: "List",
                                    onArchive:
                                    {
                                        onArchiveList(list.id)
                                    }, onDelete:
                                    {
                                        onDeleteList(list.id)
                                    }
                                ))
                        }

                    }

                    .navigationTitle(mode.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar
                    {


                        ToolbarItem(placement: .confirmationAction)
                        {


                            Button("Done")
                            {

                                listPickerMode = nil
                            }

                        }

                    }

                }

                .presentationDetents([.medium, .large])
            }

        }
        .overlay
        {
            GeometryReader
            {
                geometry in
                VStack
                {
                    Spacer(minLength: 0)
                    focusBookmarkUndoNotice
                    .padding(.horizontal, 20)
                    .padding(.bottom, max(0, focusToolbarHeight - geometry.safeAreaInsets.bottom) + 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(
                    .easeInOut(duration:
                        reduceWelcomeMotion ? 0.15 : (removedFocusBookmark != nil ? 0.5 : 1.75)),
                    value: removedFocusBookmark != nil
                )
            }
        }

    }


    ///
    /// @fcn        TodayHomeView.quickCaptureSection
    /// @brief      Build inline card capture and full-editor access
    /// @details    Disables submission for whitespace-only titles and prompts for a missing
    ///             destination. The field's accessibility hint identifies the selected Today list
    ///
    /// @return     (some View) title field, composer button, and quick-add controls
    /// @post       Submission and selection actions delegate to the Today capture helpers
    ///
    private var quickCaptureSection: some View
    {  /* Inline capture controls for the selected list */


        VStack(alignment: .leading, spacing: 8)
        {


            HStack(spacing: 8)
            {


                Button
                {

                    showsTemplates = true
                }
                label:
                {

                    Image(systemName: "plus.square")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .offset(x: -16)
                .buttonStyle(.plain)
                .accessibilityLabel("Browse templates")

                TextField("Add a card to today…", text: $quickCaptureTitle).textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(addQuickCard)
                .accessibilityLabel("Quick capture card title")
                .accessibilityHint(
                    selectedTodayList.map
                    {
                                                "Adds to \($0.title)."
                    }
                    ?? "Choose today's list before adding a card."
                )
                .offset(x: -31)

                HStack(spacing: 0)
                {


                    Button(action: addQuickCard)
                    {


                        Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }

                    .offset(x: 35)
                    .buttonStyle(.plain)
                    .disabled(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add card to today's list")

                    Button(action: openQuickNoteEditor)
                    {


                        Image(systemName: "arrow.up.right")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }

                    .offset(x: 18)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open full card editor")
                }

            }

            .padding(.horizontal, 12)
            .background
            {

                RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .allowsHitTesting(false)
            }


            TodayCaptureActions(onSelect: openCapture)

            if selectedTodayList == nil
            {  /* Keep an explicit way to choose a missing destination */


                Button("Choose today's list first")
                {

                    listPickerMode = .chooseToday
                }

                .font(.caption)
                .buttonStyle(.plain)
            }

        }

        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
