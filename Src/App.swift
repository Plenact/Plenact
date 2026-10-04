// -------------------------------------------------------------------------------------------------
// @file       App.swift
// @brief      Application entry point for the Plenact Today and Board experience
// @details    Creates the root navigation, shared Board state, and local profile session
//
// @author     Justin Reina, Firmware/Systems Engineering
// @created    9/24/26
// @last rev   9/26/26
//
// @section    Opens
//.    Consider modularizing into multiple files for length
//
// -------------------------------------------------------------------------------------------------
import SwiftUI


// -------------------------------------- MARK: - Entry Point ----------------------------------- //

///
/// Application entry point for the Plenact Application
///
/// @section    Purpose
///     Create the app scene and install the primary navigation shell
///
@main
struct Plenact: App {

    ///
    /// @brief      Build the application's initial scene
    /// @details    Provides the root window and installs AppRootView as the Today-first surface
    ///
    /// @return     (some Scene) configured application scene
    ///
    var body: some Scene { /* Root window scene */

        WindowGroup {
            AppRootView()
        }
    }
}


///
/// Identifies a primary destination in the application tab bar
///
/// @section    Purpose
///     Keep tab selection explicit and type-safe
///
/// @note   Add cases only when the corresponding application view is implemented
///
private enum AppDestination: Hashable {
    case today       /* Today's planning entry point */
    case board       /* Complete kanban workspace   */
    case calendar    /* Date-oriented card view      */
    case saved       /* Device-local saved cards     */
}


///
/// Identifies the operation shown by the Today list picker
///
/// @section    Purpose
///     Distinguish choosing today's plan from browsing directly to a board list
///
/// @note   Both picker modes operate on existing board lists
///
private enum TodayListPickerMode: String, Identifiable {
    case chooseToday   /* Set the selected list as today's plan   */
    case browseAll     /* Open a selected list on the Board       */

    /// @brief      Return the stable identity for picker presentation
    /// @details    Uses the enum raw value so SwiftUI can identify the active sheet
    var id: String { rawValue } /* Stable tab-selection identity */

    /// @brief      Return the user-facing title for the picker mode
    /// @details    Keeps the sheet heading aligned with the action being performed
    var title: String { /* User-facing list-picker title */
        switch self {
            case .chooseToday: "Choose today's list"
            case .browseAll:   "Board lists"
        }
    }
}


/// Persists device-local bookmarks without changing the shared Board document.
private enum SavedCardPersistence {

    private static let storageKey = "Plenact.SavedCardIDs.v1" /* Versioned local bookmark key */

    static func load() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: storageKey) as? [Int] ?? [])
    }

    static func save(_ cardIDs: Set<Int>) {
        UserDefaults.standard.set(cardIDs.sorted(), forKey: storageKey)
    }
}


private struct TodayScrollOffsetPreferenceKey: PreferenceKey {

    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


/// Reports actual content movement using native scroll geometry when available.
private struct TodayScrollFadeTracking: ViewModifier {

    @Binding var isScrolled: Bool /* Header fade visibility state */

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 2
            } action: { _, contentIsScrolled in
                isScrolled = contentIsScrolled
            }
        } else {
            content
                .coordinateSpace(name: "TodayScroll")
                .onPreferenceChange(TodayScrollOffsetPreferenceKey.self) { verticalOffset in
                    isScrolled = verticalOffset < -2
                }
        }
    }
}


///
/// Owns the primary app navigation and shared board state
///
/// @section    Purpose
///     Keep Today and Board in the same navigation shell and share one in-memory board snapshot
///
/// @note   Board persistence remains owned by the existing board persistence path
///
private struct AppRootView: View {

    @State private var lists = KanbanBoardPersistence.loadLists()             /* Shared board state loaded from local persistence        */
    @State private var profile = LocalProfileStore.load()                     /* Optional local identity and settings                    */
    @State private var selectedDestination: AppDestination = .today           /* Currently selected primary destination                  */
    @State private var boardTargetListID: Int?                                /* List requested by a Today-to-Board navigation           */
    @State private var savedCardIDs = SavedCardPersistence.load()              /* Device-local saved cards                              */
    @State private var quickCreateRequest = 0                                  /* Center-bar quick-create request                       */
    @State private var showsCenterNewCardSheet = false                       /* Destination picker for New outside Today              */
    @State private var isWeekListRequestArmed = false
    @State private var weekListShakeTrigger = 0

    /// @brief      Build the primary Today and Board tab navigation
    /// @details    Shares board lists between the Today front door and the existing kanban screen
    var body: some View { /* Primary Today and Board navigation shell */

        TabView(selection: $selectedDestination) {

            TodayHomeView(
                lists:   $lists,
                savedCardIDs: $savedCardIDs,
                profile: profile,
                onSaveProfile: { updatedProfile in
                    profile = updatedProfile
                    LocalProfileStore.save(updatedProfile)
                },
                onRemoveProfile: {
                    profile = nil
                    LocalProfileStore.remove()
                },
                onAddCard: { listID, title, description in
                    addCard(to: listID, title: title, description: description)
                },
                onToggleCardCompletion: toggleCardCompletion,
                onOpenBoardList: openBoardList,
                quickCreateRequest: quickCreateRequest
            )
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }
            .tag(AppDestination.today)
            .toolbar(.hidden, for: .tabBar)

            ContentView(
                lists: $lists,
                boardTargetListID: $boardTargetListID,
                savedCardIDs: $savedCardIDs
            )
                .tabItem {
                    Label("Board", systemImage: "rectangle.3.group")
                }
                .tag(AppDestination.board)
                .toolbar(.hidden, for: .tabBar)

            TodayCalendarView(lists: lists, onOpenBoardList: openBoardList)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(AppDestination.calendar)
                .toolbar(.hidden, for: .tabBar)

            SavedCardsView(lists: lists, savedCardIDs: savedCardIDs, onOpenBoardList: openBoardList)
                .tabItem {
                    Label("Saved", systemImage: "bookmark")
                }
                .tag(AppDestination.saved)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomNavigationBar
        }
        .onChange(of: savedCardIDs) { _, updatedIDs in
            SavedCardPersistence.save(updatedIDs)
        }
        .sheet(isPresented: $showsCenterNewCardSheet) {
            CenterNewCardSheet(lists: lists) { listID, title, description in
                addCard(to: listID, title: title, description: description)
            }
        }
    }

    private var bottomNavigationBar: some View {

        ZStack(alignment: .top) {
            HStack(spacing: 4) {
                tabButton(.today, title: "Today", systemImage: "sun.max.fill")
                tabButton(.board, title: "Week", systemImage: "rectangle.3.group.fill")

                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .accessibilityHidden(true)

                tabButton(.calendar, title: "Calendar", systemImage: "calendar")
                tabButton(.saved, title: "Saved", systemImage: "bookmark.fill")
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .offset(y: 25)

            VStack(spacing: 6) {
                Button {
                    if isWeekListRequestArmed {
                        isWeekListRequestArmed = false
                        addWeekList()
                    } else if selectedDestination == .today {
                        quickCreateRequest += 1
                    } else {
                        showsCenterNewCardSheet = true
                    }
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-7))
                        .frame(width: 68, height: 68)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 2, y: 4)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55, maximumDistance: 24)
                        .onEnded { _ in
                            isWeekListRequestArmed = true
                            weekListShakeTrigger += 1
                        }
                )
                .phaseAnimator([0.0, -8.0, 8.0, -8.0, 8.0, 0.0], trigger: weekListShakeTrigger) { content, angle in
                    content.rotationEffect(.degrees(angle))
                } animation: { _ in
                    .easeInOut(duration: 0.07)
                }
                .accessibilityLabel("Create a new card")
                .accessibilityHint("Tap to create a card. Touch and hold until New shakes, then release to add a Week list.")

                    if profile?.preferences.showsNavigationLabels ?? true {
                        Text("New")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.92))
                    }
            }
            .offset(y: 14)
            .zIndex(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(alignment: .bottom) {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    Image("TodayPaper")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    Color(red: 0.24, green: 0.17, blue: 0.12).opacity(0.54)
                    Rectangle()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: 1)
                }
            }
            .frame(height: 85)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: -4)
    }

    private func tabButton(_ destination: AppDestination, title: String, systemImage: String) -> some View {

        let isSelected = selectedDestination == destination /* Current tab selection */

        return Button {

            selectedDestination = destination

        } label: {

            VStack(spacing: 4) {

                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .semibold))

                if profile?.preferences.showsNavigationLabels ?? true {
                    Text(title)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.82))
        .accessibilityLabel(title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func openBoardList(_ listID: Int) {
        boardTargetListID   = listID
        selectedDestination = .board
    }

    private func toggleCardCompletion(in listID: Int, cardID: Int) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }),
              let cardIndex = lists[listIndex].cards.firstIndex(where: { $0.id == cardID }) else {
            return
        }

        lists[listIndex].cards[cardIndex].isTitleChecked.toggle()
        KanbanBoardPersistence.saveLists(lists)
    }

    private func addWeekList() {
        let nextListID = (lists.map(\.id).max() ?? -1) + 1 /* Board-wide next list ID */
        let existingTitles = Set(lists.map { $0.title.lowercased() }) /* Existing normalized titles */
        var title = "New List" /* First candidate list title */
        var suffix = 2 /* Duplicate-title suffix */

        while existingTitles.contains(title.lowercased()) {
            title = "New List \(suffix)"
            suffix += 1
        }

        lists.append(KanbanList(id: nextListID, title: title, cards: []))
        KanbanBoardPersistence.saveLists(lists)
        boardTargetListID = nextListID
        selectedDestination = .board
    }

        private func addCard(to listID: Int, title: String, description: String) {

            guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* Destination list index */

            let nextCardID  = (lists.flatMap { $0.cards.map(\.id) }.max() ?? -1) + 1 /* Board-wide next card ID */
            var updatedList = lists[listIndex] /* Mutable destination-list copy */

            updatedList.cards.append(
                KanbanCard(
                    id:                  nextCardID,
                    word:                title,
                    listTitle:           updatedList.title,
                    isDivider:           KanbanCard.isDividerTitle(title),
                    descriptionOverride: description.isEmpty ? nil : description
                )
            )

            lists[listIndex] = updatedList

            KanbanBoardPersistence.saveLists(lists)
        }
}


///
/// Presents today's plan selection and direct access to existing board lists
///
/// @section    Purpose
///     Provide a calm entry point into the user's existing day list without duplicating task data
///
/// @note   The selected list is stored locally for the current calendar date
///
private struct TodayHomeView: View {

    @Binding var lists:     [KanbanList]                    /* Shared local Board lists                            */
    @Binding var savedCardIDs: Set<Int>                     /* Device-local bookmarks used by card details          */
    let profile:            LocalProfile?                   /* Current local profile and preferences              */
    let onSaveProfile:      (LocalProfile)        -> Void   /* Save local identity and personalization            */
    let onRemoveProfile:    ()                    -> Void   /* Remove only local profile information              */
    let onAddCard:          (Int, String, String) -> Void   /* Add a card to an existing Board list               */
    let onToggleCardCompletion: (Int, Int) -> Void          /* Toggle local card completion                        */
    let onOpenBoardList:    (Int)                 -> Void   /* Route to Board at the selected list ID             */
    let quickCreateRequest: Int                             /* Center-bar requests for the Today composer         */

    @State private var selectedTodayListID: Int?            /* Board list selected for today's plan     */
    @State private var listPickerMode: TodayListPickerMode? /* Active list picker presentation mode     */
    @State private var showsAccountSettings = false         /* Account & Settings sheet presentation    */
    @State private var showsTodayList = false               /* Focused single-list presentation         */
    @State private var quickCaptureTitle    = ""            /* Draft title for inline card capture      */
    @State private var showsQuickNoteEditor = false         /* Full-size quick card editor presentation */
    @State private var showsSearch          = false         /* Local Board search presentation          */
    @State private var presentComposerAfterListChoice = false /* Deferred center-plus request            */
    @State private var labelLibrary = LabelLibraryStore.load() /* Local categorized label definitions    */
    @State private var selectedLabelCategoryID: String? = nil /* Category selected in Your Labels          */
    @State private var selectedLabel: KanbanLabel? = nil   /* Label opened into its applied cards        */
    @State private var isContentScrolled = false            /* Whether Today content is passing beneath the header */


    ///
    /// @brief      Resolve today's saved list selection against the current board
    /// @details    Returns no list when the saved identifier is missing or no longer exists
    ///
    private var selectedTodayList: KanbanList? {                                                /* Board list selected for the current date */

        let resolvedListID = selectedTodayListID ?? profile?.preferences.defaultListID          /* Effective list ID */

        guard let resolvedListID else { return nil }                                            /* No saved or default list selection */

        return lists.first { $0.id == resolvedListID }
    }

    private var selectedTodayCards: [KanbanCard] {
        selectedTodayList?.cards.filter { !$0.isSectionDivider } ?? []
    }

    private var openTodayCards: [KanbanCard] {
        Array(selectedTodayCards.filter { !$0.isTitleChecked }.prefix(3))
    }

    private var usedLabelCategories: [TodayLabelCategoryUsage] {
        labelLibrary.categories.compactMap { category in
            let labels: [TodayLabelUsage] = labelLibrary.labels
                .filter { $0.categoryID == category.id }
                .compactMap { label in
                    let cards = cards(using: label.id)
                    guard !cards.isEmpty else { return nil }
                    return TodayLabelUsage(label: label, cards: cards)
                }

            guard !labels.isEmpty else { return nil }
            return TodayLabelCategoryUsage(category: category, labels: labels)
        }
    }

    private var selectedUsedLabelCategory: TodayLabelCategoryUsage? {
        usedLabelCategories.first { $0.id == selectedLabelCategoryID } ?? usedLabelCategories.first
    }

    /// Return the preferred height for primary Today controls
    private var primaryControlHeight: CGFloat {                                                 /* Personalized control height */

        profile?.preferences.usesLargeControls == true ? 52 : 44
    }

    private var todayHeader: some View {

        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.largeTitle.weight(.bold))
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showsSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search Board")

            Button {
                showsAccountSettings = true
            } label: {
                ProfileAvatarView(profile: profile, size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(profile == nil ? "Create local profile" : "Open Account and Settings")
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var todayHeaderPanel: some View {

        todayHeader
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: 560)
            .background {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
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
            .overlay(alignment: .bottom) {
                if isContentScrolled {
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
    /// @fcn        TodayHomeView.init(lists:profile:onSaveProfile:onRemoveProfile:onOpenBoardList:)
    /// @brief      Initialize Today with Board lists, local profile state, and callbacks
    /// @details    Restores the date-specific list selection and connects profile persistence and
    ///             Board navigation actions
    ///
    /// @param[in]  lists             Current board lists to offer and resolve
    /// @param[in]  profile           Optional local identity and personalization
    /// @param[in]  onSaveProfile     Callback that saves a complete local profile
    /// @param[in]  onRemoveProfile   Callback that removes only local profile data
    /// @param[in]  onOpenBoardList   Callback that opens Board at a selected list ID
    ///
    /// @return     (TodayHomeView) configured Today screen
    ///
    /// @pre        lists reflects the current in-memory board state
    /// @post       The saved selection is restored when available; board data is unchanged
    ///
    init(
        lists:           Binding<[KanbanList]>,
        savedCardIDs:    Binding<Set<Int>>,
        profile:         LocalProfile?,
        onSaveProfile:   @escaping (LocalProfile) -> Void,
        onRemoveProfile: @escaping () -> Void,
        onAddCard:       @escaping (Int, String, String) -> Void,
        onToggleCardCompletion: @escaping (Int, Int) -> Void,
        onOpenBoardList: @escaping (Int) -> Void,
        quickCreateRequest: Int
    ) {

        self._lists          = lists
        self._savedCardIDs   = savedCardIDs
        self.profile         = profile
        self.onSaveProfile   = onSaveProfile
        self.onRemoveProfile = onRemoveProfile
        self.onAddCard       = onAddCard
        self.onToggleCardCompletion = onToggleCardCompletion
        self.onOpenBoardList = onOpenBoardList
        self.quickCreateRequest = quickCreateRequest

        let savedListID = UserDefaults.standard.object(forKey: Self.todayListStorageKey(for: .now)) as? Int /* Persisted date-specific selection */
        _selectedTodayListID = State(initialValue: savedListID)
    }

    ///
    /// @fcn        TodayHomeView.todayListStorageKey(for:)
    /// @brief      Create the local preference key for a calendar date
    /// @details    Uses the user's current calendar to scope the selected list to one day
    ///
    /// @param[in]  date  Calendar date whose Today selection is being stored
    ///
    /// @return     (String) date-specific UserDefaults key
    ///
    /// @pre        date is a valid Foundation date value
    /// @post       No persistent data is read or modified
    ///
    private static func todayListStorageKey(for date: Date) -> String {

        let components = Calendar.current.dateComponents([.year, .month, .day], from: date) /* Local calendar date components */

        return "Plenact.Today.List.\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
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
    private func cardCount(in list: KanbanList) -> Int {

        list.cards.filter { !$0.isSectionDivider }.count
    }

    private func cards(using labelID: String) -> [TodayLabelCard] {
        lists.flatMap { list in
            list.cards.compactMap { card in
                guard !card.isSectionDivider, card.labelIDs.contains(labelID) else { return nil }
                return TodayLabelCard(card: card, listID: list.id, listTitle: list.title)
            }
        }
    }

    private var yourLabelsSection: some View {

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Labels")
                    .font(.title2.weight(.semibold))

                Spacer()

                if let selectedUsedLabelCategory {
                    Menu {
                        ForEach(usedLabelCategories) { category in
                            Button {
                                selectedLabelCategoryID = category.id
                            } label: {
                                if selectedUsedLabelCategory.id == category.id {
                                    Label(category.category.name, systemImage: "checkmark")
                                } else {
                                    Text(category.category.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedUsedLabelCategory.category.name)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(.thinMaterial, in: Capsule())
                    }
                    .accessibilityLabel("Choose label category")
                }
            }

            if usedLabelCategories.isEmpty {
                Text("Labels applied to your cards will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let selectedUsedLabelCategory {
                VStack(spacing: 0) {
                    ForEach(selectedUsedLabelCategory.labels) { usage in
                        Button {
                            selectedLabel = usage.label
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(usage.label.color.color)
                                    .frame(width: 10, height: 10)
                                Text(usage.label.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(usage.cards.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if usage.id != selectedUsedLabelCategory.labels.last?.id {
                            Divider()
                        }
                    }
                }
            }

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TodayPanelSurface())
    }

    private var browseListsAction: some View {

        Button {
            listPickerMode = .browseAll
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.3.group")
                Text("Browse all lists")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    /// Add the inline capture to the current Today list, prompting for a list when none is selected.
    private func addQuickCard() {

        let title = quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines) /* Clean card title */
        guard !title.isEmpty else { return }

        guard let selectedTodayList else {
            listPickerMode = .chooseToday
            return
        }

        onAddCard(selectedTodayList.id, title, "")
        quickCaptureTitle = ""
    }

    /// Open the detailed composer only after a destination list is selected.
    private func openQuickNoteEditor() {

        guard selectedTodayList != nil else {
            presentComposerAfterListChoice = true
            listPickerMode = .chooseToday
            return
        }

        showsQuickNoteEditor = true
    }

    ///
    /// @fcn        TodayHomeView.selectTodayList(_:)
    /// @brief      Save a board list as today's plan
    /// @details    Updates view state and stores the selected list ID under the current date key
    ///
    /// @param[in]  list  Existing board list selected for today
    ///
    /// @return     (Void) updates the local Today preference and dismisses the picker
    ///
    /// @pre        list is present in the current board list collection
    /// @post       The selected list ID is stored locally for the current date
    ///
    private func selectTodayList(_ list: KanbanList) {

        selectedTodayListID = list.id

        UserDefaults.standard.set(list.id, forKey: Self.todayListStorageKey(for: .now))
        let shouldPresentComposer = presentComposerAfterListChoice /* Deferred New-button action */
        presentComposerAfterListChoice = false
        listPickerMode = nil

        if shouldPresentComposer {
            Task { @MainActor in
                await Task.yield()
                showsQuickNoteEditor = true
            }
        }
    }

    ///
    /// @fcn        TodayHomeView.body
    /// @brief      Build the Today front-door screen
    /// @details    Shows the selected day list, list selection, and access to all board lists
    ///
    /// @return     (some View) scrollable Today content and its list picker sheet
    ///
    /// @pre        lists contains the current board state and callbacks are configured
    /// @post       User actions either update the local date-scoped selection or navigate to Board
    ///
    var body: some View { /* Today screen and list-selection sheets */

        NavigationStack {

            ScrollView {

                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TodayScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("TodayScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    VStack(alignment: .leading, spacing: 16) {

                    quickCaptureSection
                        .modifier(TodayPanelSurface())

                    TodayFocusSection(
                        list:         selectedTodayList,
                        cards:        selectedTodayCards,
                        openCards:    openTodayCards,
                        onChooseList: { listPickerMode = .chooseToday },
                        onToggleCard: { cardID in
                            guard let selectedTodayList else { return }
                            onToggleCardCompletion(selectedTodayList.id, cardID)
                        },
                        onOpenTodayList: {
                            showsTodayList = true
                        }
                    )

                    yourLabelsSection
                    browseListsAction
                }
                        .padding(20)
                        .frame(maxWidth: 560, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 112)
            }
                .modifier(TodayScrollFadeTracking(isScrolled: $isContentScrolled))
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        todayHeaderPanel
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .zIndex(1)
                }
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollIndicators(.hidden)
            .background {
                GeometryReader { geometry in
                    Image("TodayPaper")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsAccountSettings) {

                AccountSettingsView(
                    profile:  profile,
                    lists:    lists,
                    onSave:   onSaveProfile,
                    onRemove: onRemoveProfile
                )
            }
            .fullScreenCover(isPresented: $showsTodayList) {
                if let selectedTodayList {
                    TodayListDetailView(
                        lists: $lists,
                        labelLibrary: $labelLibrary,
                        savedCardIDs: $savedCardIDs,
                        listID: selectedTodayList.id,
                        currentUserName: profile?.displayName ?? "Justin Reina",
                        onClose: {
                            showsTodayList = false
                        },
                        onOpenWeek: {
                            showsTodayList = false
                            onOpenBoardList(selectedTodayList.id)
                        }
                    )
                }
            }
            .sheet(isPresented: $showsQuickNoteEditor) {

                if let selectedTodayList {

                    QuickNoteComposer(listTitle: selectedTodayList.title) { title, description in
                        onAddCard(selectedTodayList.id, title, description)
                    }
                }
            }
            .sheet(isPresented: $showsSearch) {
                TodaySearchView(lists: lists, onOpenBoardList: onOpenBoardList)
            }
            .sheet(item: $selectedLabel) { label in
                TodayLabelCardsView(label: label, cards: cards(using: label.id), onOpenBoardList: onOpenBoardList)
            }
            .onAppear {
                labelLibrary = LabelLibraryStore.load()

                if !usedLabelCategories.contains(where: { $0.id == selectedLabelCategoryID }) {

                    selectedLabelCategoryID = usedLabelCategories.first(where: { $0.id == "work" })?.id
                        ?? usedLabelCategories.first?.id
                }
            }
            .onChange(of: quickCreateRequest) { _, _ in
                openQuickNoteEditor()
            }
            .onChange(of: labelLibrary) { _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }
            .sheet(item: $listPickerMode) { mode in

                NavigationStack {

                    List {

                        ForEach(lists) { list in

                            Button {
                                switch mode {
                                    case .chooseToday:
                                        selectTodayList(list)
                                    case .browseAll:
                                        listPickerMode = nil
                                        onOpenBoardList(list.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {

                                        Text(list.title)
                                            .foregroundStyle(.primary)

                                        Text("\(cardCount(in: list)) items")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if selectedTodayListID == list.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(mode == .chooseToday ? "Sets this as today's plan" : "Opens this list on the board")
                        }
                    }
                    .navigationTitle(mode.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {

                        ToolbarItem(placement: .confirmationAction) {

                            Button("Done") {
                                listPickerMode = nil
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var quickCaptureSection: some View {

        VStack(alignment: .leading, spacing: 8) {

            Text("Quick capture")
                .font(.title2.weight(.semibold))

            HStack(spacing: 8) {

                Image(systemName: "plus.square")
                    .foregroundStyle(.secondary)

                TextField("Add a card to today…", text: $quickCaptureTitle)
                    .submitLabel(.done)
                    .onSubmit(addQuickCard)
                    .accessibilityLabel("Quick capture card title")

                Button(action: openQuickNoteEditor) {

                    Image(systemName: "arrow.up.right")
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full card editor")

                Button(action: addQuickCard) {

                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add card to today's list")
            }
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .allowsHitTesting(false)
            }

            if let selectedTodayList {

                Text("Adding to \(selectedTodayList.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } else {

                Button("Choose today's list first") {
                    listPickerMode = .chooseToday
                }
                .font(.caption)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Creates a card with optional supporting detail for the selected Today list.
private struct QuickNoteComposer: View {

    let listTitle: String                       /* Dest list displayed in the editor    */
    let onSave: (String, String) -> Void        /* Create the card in the selected list */

    @Environment(\.dismiss) private var dismiss /* Close the full-size editor           */

    @State private var title = ""               /* New card title                       */
    @State private var description = ""         /* Optional card detail                 */

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {

        NavigationStack {
            Form {
                Section("Card") {
                    TextField("Title", text: $title)
                    TextField("Details (optional)", text: $description, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Add to") {
                    Label(listTitle, systemImage: "list.bullet")
                }
            }
            .navigationTitle("New card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {

                    Button("Add") {
                        onSave(trimmedTitle, description.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}


/// Lets the center New action choose a destination without changing the active tab.
private struct CenterNewCardSheet: View {

    let lists: [KanbanList] /* Existing lists available for card creation */
    let onCreate: (Int, String, String) -> Void /* Add the new card to the chosen list */

    @Environment(\.dismiss) private var dismiss /* Close the destination picker */
    @State private var selectedListID: Int? /* List selected for this new card */
    @State private var title = "" /* New card title */
    @State private var details = "" /* Optional new card details */

    private var selectedList: KanbanList? {
        lists.first { $0.id == selectedListID }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedList {
                    Form {
                        Section("Card") {
                            TextField("Title", text: $title)
                            TextField("Details (optional)", text: $details, axis: .vertical)
                                .lineLimit(3...6)
                        }

                        Section("Add to") {
                            Button {
                                selectedListID = nil
                            } label: {
                                Label(selectedList.title, systemImage: "list.bullet")
                            }
                        }
                    }
                } else {
                    List(lists) { list in
                        Button {
                            selectedListID = list.id
                        } label: {
                            HStack {
                                Text(list.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(list.cards.filter { !$0.isSectionDivider }.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(selectedList?.title ?? "Add card to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedList == nil ? "Cancel" : "Lists") {
                        if selectedList == nil {
                            dismiss()
                        } else {
                            selectedListID = nil
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let selectedList {
                        Button("Add") {
                            onCreate(
                                selectedList.id,
                                trimmedTitle,
                                details.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            dismiss()
                        }
                        .disabled(trimmedTitle.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}


private struct TodaySearchResult: Identifiable {

    let listID: Int /* Board list opened when this result is selected */
    let cardID: Int /* Stable card identity */
    let cardTitle: String /* Matching card title */
    let listTitle: String /* Containing list title */
    let detail: String /* Supporting detail shown under the title */

    var id: String { "\(listID):\(cardID)" }
}


/// Searches card content in the local Board and opens results in their existing lists.
private struct TodaySearchView: View {

    let lists: [KanbanList] /* Current locally stored Board snapshot */
    let onOpenBoardList: (Int) -> Void /* Navigate to a result's containing list */

    @Environment(\.dismiss) private var dismiss /* Close the search sheet */
    @FocusState private var searchFieldFocused: Bool /* Search field focus state */
    @State private var query = "" /* User-entered search text */

    private var results: [TodaySearchResult] {

        let searchTerm = query.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized search term */
        guard !searchTerm.isEmpty else { return [] }

        return lists.flatMap { list in
            list.cards.compactMap { card in
                guard !card.isSectionDivider else { return nil }

                let checklistText = card.checklists.flatMap { checklist in
                    [checklist.title] + checklist.items.map(\.title)
                }
                let commentText = card.comments.flatMap { [$0.author, $0.body] }
                let assigneeText = card.members.map(\.displayName)
                let searchableText = [
                    list.title,
                    card.word,
                    card.descriptionOverride ?? "",
                    card.subtitleOverride ?? ""
                ] + checklistText + commentText + assigneeText

                guard searchableText.contains(where: { $0.localizedStandardContains(searchTerm) }) else {
                    return nil
                }

                let detail = [card.subtitleOverride, card.descriptionOverride]
                    .compactMap { $0 }
                    .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    ?? checklistText.first
                    ?? ""

                return TodaySearchResult(
                    listID: list.id,
                    cardID: card.id,
                    cardTitle: card.word,
                    listTitle: list.title,
                    detail: detail
                )
            }
        }
    }

    var body: some View {

        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search cards and lists", text: $query)
                        .focused($searchFieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityLabel("Search local Board")

                    if !query.isEmpty {
                        Button {
                            query = ""
                            searchFieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .padding()

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchEmptyState(
                        title: "Search your Board",
                        detail: "Find cards by title, list, details, checklist, comment, or assignee."
                    )
                } else if results.isEmpty {
                    searchEmptyState(title: "No results", detail: "Try another word or phrase.")
                } else {
                    List(results) { result in
                        Button {
                            onOpenBoardList(result.listID)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.cardTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(result.detail.isEmpty ? result.listTitle : "\(result.listTitle) · \(result.detail)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            searchFieldFocused = true
        }
    }

    private func searchEmptyState(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


private struct TodayLabelCard: Identifiable {

    let card: KanbanCard /* Matched Board card */
    let listID: Int /* List opened when selected */
    let listTitle: String /* Containing list name */

    var id: String { "\(listID):\(card.id)" }
}


private struct TodayLabelUsage: Identifiable {

    let label: KanbanLabel /* Reusable label definition */
    let cards: [TodayLabelCard] /* Cards currently carrying this label */

    var id: String { label.id }
}


private struct TodayLabelCategoryUsage: Identifiable {

    let category: KanbanLabelCategory /* Label category */
    let labels: [TodayLabelUsage] /* Labels in use in this category */

    var id: String { category.id }
    var cardCount: Int { Set(labels.flatMap { $0.cards.map(\.id) }).count }
}


/// Opens the cards currently assigned one label.
private struct TodayLabelCardsView: View {

    let label: KanbanLabel /* Selected label */
    let cards: [TodayLabelCard] /* Matching Board cards */
    let onOpenBoardList: (Int) -> Void /* Navigate to the card's Board list */

    @Environment(\.dismiss) private var dismiss /* Close the label card list */

    var body: some View {
        NavigationStack {
            List(cards) { result in
                Button {
                    onOpenBoardList(result.listID)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.card.word)
                            .foregroundStyle(.primary)
                        Text(result.listTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(label.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}


private struct CalendarCardResult: Identifiable {

    let cardID: Int /* Stable card identity */
    let title: String /* Card title shown on the selected date */
    let listID: Int /* Board list opened when selected */
    let listTitle: String /* Containing Board list */
    let dateLabel: String /* Start/due marker for this date */

    var id: Int { cardID }
}


/// Shows a month grid from existing card start/due dates and routes into Board lists.
private struct TodayCalendarView: View {

    let lists: [KanbanList] /* Current Board snapshot */
    let onOpenBoardList: (Int) -> Void /* Navigate to the card's list */

    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now /* Visible month */
    @State private var selectedDate = Calendar.current.startOfDay(for: .now) /* Selected local day */

    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current /* User's local calendar */
        let symbols = calendar.veryShortStandaloneWeekdaySymbols /* Locale weekday labels */
        return (0..<symbols.count).map { symbols[(calendar.firstWeekday - 1 + $0) % symbols.count] }
    }

    private var monthDays: [Date?] {
        let calendar = Calendar.current /* User's local calendar */
        guard let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start,
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let leadingDays = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7 /* Empty cells before day one */
        var days: [Date?] = Array(repeating: nil, count: leadingDays)
        days += dayRange.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        days += Array(repeating: nil, count: (7 - days.count % 7) % 7)
        return days
    }

    private var selectedDayCards: [CalendarCardResult] {
        cards(on: selectedDate)
    }

    var body: some View {

        ZStack {
            TodayPaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calendar")
                            .font(.largeTitle.weight(.bold))
                        Text("Dates from your existing cards")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        HStack {
                            Button {
                                moveMonth(by: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("Previous month")

                            Spacer()
                            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                                .font(.headline)
                            Spacer()

                            Button {
                                moveMonth(by: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("Next month")
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: weekdayColumns, spacing: 4) {
                            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                                Text(symbol)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 24)
                            }

                            ForEach(monthDays.indices, id: \.self) { index in
                                if let date = monthDays[index] {
                                    calendarDayButton(date)
                                } else {
                                    Color.clear.frame(height: 40)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .modifier(TodayPanelSurface())

                    VStack(alignment: .leading, spacing: 10) {
                        Text(selectedDate.formatted(date: .complete, time: .omitted))
                            .font(.title3.weight(.semibold))

                        if selectedDayCards.isEmpty {
                            Text("No cards with a start or due date on this day.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(selectedDayCards) { result in
                                Button {
                                    onOpenBoardList(result.listID)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "calendar")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(result.title)
                                                .foregroundStyle(.primary)
                                            Text("\(result.listTitle) · \(result.dateLabel)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .modifier(TodayPanelSurface())
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(.clear)
        }
    }

    private func calendarDayButton(_ date: Date) -> some View {
        let calendar = Calendar.current /* User's local calendar */
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate) /* Selected day state */
        let isToday = calendar.isDateInToday(date) /* Current day state */
        let cardCount = cards(on: date).count /* Dated cards on this day */

        return Button {
            selectedDate = calendar.startOfDay(for: date)
        } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Circle()
                    .fill(cardCount > 0 ? Color.accentColor : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected ? Color.accentColor.opacity(0.12) : .clear, in: Circle())
            .overlay {
                if isToday {
                    Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(cardCount) dated cards")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cards(on date: Date) -> [CalendarCardResult] {
        let calendar = Calendar.current /* User's local calendar */

        return lists.flatMap { list in
            list.cards.compactMap { card in
                guard !card.isSectionDivider else { return nil }
                let starts = card.startDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false /* Start date marker */
                let due = card.dueDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false /* Due date marker */
                guard starts || due else { return nil }

                let dateLabel = starts && due ? "Starts & due" : (due ? "Due" : "Starts") /* Display-only date meaning */
                return CalendarCardResult(cardID: card.id, title: card.word, listID: list.id, listTitle: list.title, dateLabel: dateLabel)
            }
        }
    }

    private func moveMonth(by amount: Int) {
        guard let nextMonth = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        displayedMonth = nextMonth
        selectedDate = Calendar.current.startOfDay(for: nextMonth)
    }
}


private struct SavedCardResult: Identifiable {

    let card: KanbanCard /* Saved card data */
    let listID: Int /* List opened when selected */
    let listTitle: String /* Containing list title */

    var id: Int { card.id }
}


/// Shows device-local bookmarks for cards in the current Board.
private struct SavedCardsView: View {

    let lists: [KanbanList] /* Current Board snapshot */
    let savedCardIDs: Set<Int> /* Local bookmark set */
    let onOpenBoardList: (Int) -> Void /* Navigate to the containing list */

    private var savedCards: [SavedCardResult] {
        lists.flatMap { list in
            list.cards.compactMap { card in
                guard savedCardIDs.contains(card.id), !card.isSectionDivider else { return nil }
                return SavedCardResult(card: card, listID: list.id, listTitle: list.title)
            }
        }
    }

    var body: some View {

        ZStack {
            TodayPaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saved")
                            .font(.largeTitle.weight(.bold))
                        Text("Bookmarked on this device")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        if savedCards.isEmpty {
                            Label("No saved cards yet", systemImage: "bookmark")
                                .font(.headline)
                            Text("Open a card and tap the bookmark to keep it here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(savedCards) { result in
                                Button {
                                    onOpenBoardList(result.listID)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(result.card.word)
                                                .foregroundStyle(.primary)
                                            Text(result.listTitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .modifier(TodayPanelSurface())
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(.clear)
        }
    }
}


/// Shows the selected Today list's progress and next open cards.
private struct TodayFocusSection: View {

    let list: KanbanList? /* List selected as the current Today focus */
    let cards: [KanbanCard] /* Non-divider cards on that list */
    let openCards: [KanbanCard] /* First three incomplete cards */
    let onChooseList: () -> Void /* Select another list for Today */
    let onToggleCard: (Int) -> Void /* Toggle local completion state */
    let onOpenTodayList: () -> Void /* Open the focused single-list Today view */

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's Focus")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Change", action: onChooseList)
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.plain)
            }

            if let list {
                let completedCount = cards.filter(\.isTitleChecked).count

                HStack {
                    Text(list.title)
                        .font(.headline)
                    Spacer()
                    Text("\(completedCount) of \(cards.count) complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !cards.isEmpty {
                    ProgressView(value: Double(completedCount), total: Double(cards.count))
                        .tint(.accentColor)
                }

                if cards.isEmpty {
                    Text("This list is ready for its first card.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if openCards.isEmpty {
                    Label("Everything on this list is complete", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 40, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(openCards) { card in
                            HStack(spacing: 8) {
                                Button {
                                    onToggleCard(card.id)
                                } label: {
                                    Image(systemName: "square")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, height: 42)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Mark \(card.word) complete")

                                Button(action: onOpenTodayList) {
                                    HStack {
                                        Text(card.word)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open \(card.word) in today's list")
                            }

                            if card.id != openCards.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                Button(action: onOpenTodayList) {
                    Label("Open today's list", systemImage: "arrow.right")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            } else {
                Text("Choose a Board list to focus on today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Choose list", systemImage: "list.bullet", action: onChooseList)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TodayPanelSurface())
    }
}

private struct TodayPaperBackground: View {

    var body: some View {
        GeometryReader { geometry in
            Image("TodayPaper")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}


/// Gives Today sections a readable raised surface over the full-screen paper texture.
private struct TodayPanelSurface: ViewModifier {

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.68), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 5)
    }
}
