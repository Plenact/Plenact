// -------------------------------------------------------------------------------------------------
// @file       App.swift
// @brief      Application entry point for the Plenact Today and Board experience
// @details    Creates the root navigation, shared Board state, and local profile session
//
// @author     Justin Reina, Firmware/Systems Engineering
// @created    9/24/26
// @last rev   9/26/26
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

    /// @brief      Build the primary Today and Board tab navigation
    /// @details    Shares board lists between the Today front door and the existing kanban screen
    var body: some View { /* Primary Today and Board navigation shell */

        TabView(selection: $selectedDestination) {

            TodayHomeView(
                lists:   lists,
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
                onOpenBoardList: { listID in
                    boardTargetListID   = listID
                    selectedDestination = .board
                }
            )
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }
            .tag(AppDestination.today)

            ContentView(lists: $lists, boardTargetListID: $boardTargetListID)
                .tabItem {
                    Label("Board", systemImage: "rectangle.3.group")
                }
                .tag(AppDestination.board)
        }
    }

        private func addCard(to listID: Int, title: String, description: String) {

            guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* Destination list index */

            let nextCardID = (lists.flatMap { $0.cards.map(\.id) }.max() ?? -1) + 1 /* Board-wide next card ID */
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

    let lists: [KanbanList]                        /* Current board lists available to Today             */
    let profile: LocalProfile?                     /* Current local profile and preferences              */
    let onSaveProfile: (LocalProfile) -> Void      /* Save local identity and personalization            */
    let onRemoveProfile: () -> Void                /* Remove only local profile information              */
    let onAddCard: (Int, String, String) -> Void   /* Add a card to an existing Board list                */
    let onOpenBoardList: (Int) -> Void             /* Route to Board at the selected list ID             */

    @State private var selectedTodayListID: Int?            /* Board list selected for today's plan     */
    @State private var listPickerMode: TodayListPickerMode? /* Active list picker presentation mode     */
    @State private var showsAccountSettings = false         /* Account & Settings sheet presentation    */
    @State private var quickCaptureTitle = ""               /* Draft title for inline card capture      */
    @State private var showsQuickNoteEditor = false         /* Full-size quick card editor presentation */

    /// @brief      Resolve today's saved list selection against the current board
    /// @details    Returns no list when the saved identifier is missing or no longer exists
    private var selectedTodayList: KanbanList? { /* Board list selected for the current date */

        let resolvedListID = selectedTodayListID ?? profile?.preferences.defaultListID   /* Effective list ID */

        guard let resolvedListID else { return nil } /* No saved or default list selection */

        return lists.first { $0.id == resolvedListID }
    }

    /// Return the preferred height for primary Today controls.
    private var primaryControlHeight: CGFloat {   /* Personalized control height */
        profile?.preferences.usesLargeControls == true ? 52 : 44
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
        lists:           [KanbanList],
        profile:         LocalProfile?,
        onSaveProfile:   @escaping (LocalProfile) -> Void,
        onRemoveProfile: @escaping () -> Void,
        onAddCard:       @escaping (Int, String, String) -> Void,
        onOpenBoardList: @escaping (Int) -> Void
    ) {

        self.lists           = lists
        self.profile         = profile
        self.onSaveProfile   = onSaveProfile
        self.onRemoveProfile = onRemoveProfile
        self.onAddCard       = onAddCard
        self.onOpenBoardList = onOpenBoardList

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
        
        listPickerMode = nil
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

                VStack(alignment: .leading, spacing: 24) {

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
                            showsAccountSettings = true
                        } label: {
                            ProfileAvatarView(profile: profile, size: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(profile == nil ? "Create local profile" : "Open Account and Settings")
                    }

                    quickCaptureSection

                    VStack(alignment: .leading, spacing: 14) {

                        Text("Today's plan")
                            .font(.title2.weight(.semibold))

                        if let selectedTodayList { /* Resolved Today plan list */

                            VStack(alignment: .leading, spacing: 8) {
                                Text(selectedTodayList.title)
                                    .font(.headline)

                                if profile?.preferences.usesReducedContent != true {
                                    Text("\(cardCount(in: selectedTodayList)) items on this list")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Button {
                                    onOpenBoardList(selectedTodayList.id)
                                } label: {
                                    Label("Open today's list", systemImage: "arrow.up.right.square")
                                        .frame(maxWidth: .infinity, minHeight: primaryControlHeight)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Choose a different list") {
                                    listPickerMode = .chooseToday
                                }
                                .frame(minHeight: 44)
                            }
                        } else {

                            if profile?.preferences.usesReducedContent != true {
                                Text("Choose one of your existing board lists for today's plan.")
                                    .foregroundStyle(.secondary)
                            }

                            Button("Choose today's list", systemImage: "list.bullet") {
                                listPickerMode = .chooseToday
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: primaryControlHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your board")
                            .font(.title2.weight(.semibold))

                        if profile?.preferences.usesReducedContent != true {
                            Text("Open any existing list, including open work and custom lists.")
                                .foregroundStyle(.secondary)
                        }

                        Button("Browse all lists", systemImage: "rectangle.3.group") {
                            listPickerMode = .browseAll
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: primaryControlHeight)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
            .sheet(isPresented: $showsQuickNoteEditor) {
                if let selectedTodayList {
                    QuickNoteComposer(listTitle: selectedTodayList.title) { title, description in
                        onAddCard(selectedTodayList.id, title, description)
                    }
                }
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
            .background(.background, in: RoundedRectangle(cornerRadius: 8))

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

    let listTitle: String /* Destination list displayed in the editor */
    let onSave: (String, String) -> Void /* Create the card in the selected list */

    @Environment(\.dismiss) private var dismiss /* Close the full-size editor */
    @State private var title = "" /* New card title */
    @State private var description = "" /* Optional card detail */

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
