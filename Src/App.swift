// -------------------------------------------------------------------------------------------------
// @file       App.swift
// @brief      Application entry point for the Plenact App kanban board
// @details    Creates the window hierarchy and installs the board as the root view
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
///     Create the app scene and install the board as the initial root view
///
@main
struct Plenact: App {

    ///
    /// @brief      Build the application's initial scene
    /// @details    Provides the root window and installs ContentView as the initial board surface
    ///
    /// @return     (some Scene) configured application scene
    ///
    var body: some Scene {

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
    var id: String { rawValue }

    /// @brief      Return the user-facing title for the picker mode
    /// @details    Keeps the sheet heading aligned with the action being performed
    var title: String {
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
    @State private var selectedDestination: AppDestination = .today           /* Currently selected primary destination                  */
    @State private var boardTargetListID: Int?                                /* List requested by a Today-to-Board navigation           */

    /// @brief      Build the primary Today and Board tab navigation
    /// @details    Shares board lists between the Today front door and the existing kanban screen
    var body: some View {

        TabView(selection: $selectedDestination) {

            TodayHomeView(lists: lists) { listID in
                boardTargetListID   = listID
                selectedDestination = .board
            }
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
    let onOpenBoardList: (Int) -> Void             /* Route to Board at the selected list ID             */

    @State private var selectedTodayListID: Int?            /* Board list selected for today's plan     */
    @State private var listPickerMode: TodayListPickerMode? /* Active list picker presentation mode     */

    /// @brief      Resolve today's saved list selection against the current board
    /// @details    Returns no list when the saved identifier is missing or no longer exists
    private var selectedTodayList: KanbanList? {

        guard let selectedTodayListID else { return nil }

        return lists.first { $0.id == selectedTodayListID }
    }

    ///
    /// @fcn        TodayHomeView.init(lists:onOpenBoardList:)
    /// @brief      Initialize Today with the available board lists and navigation callback
    /// @details    Restores the list selection stored for the current local calendar date
    ///
    /// @param[in]  lists             Current board lists to offer and resolve
    /// @param[in]  onOpenBoardList   Callback that opens Board at a selected list ID
    ///
    /// @return     (TodayHomeView) configured Today screen
    ///
    /// @pre        lists reflects the current in-memory board state
    /// @post       The saved selection is restored when available; board data is unchanged
    ///
    init(lists: [KanbanList], onOpenBoardList: @escaping (Int) -> Void) {

        self.lists           = lists
        self.onOpenBoardList = onOpenBoardList

        let savedListID = UserDefaults.standard.object(forKey: Self.todayListStorageKey(for: .now)) as? Int
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

        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)

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
    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(alignment: .leading, spacing: 24) {

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today")
                            .font(.largeTitle.weight(.bold))

                        Text(Date.now.formatted(date: .complete, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {

                        Text("Today's plan")
                            .font(.title2.weight(.semibold))

                        if let selectedTodayList {

                            VStack(alignment: .leading, spacing: 8) {
                                Text(selectedTodayList.title)
                                    .font(.headline)

                                Text("\(cardCount(in: selectedTodayList)) items on this list")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button {
                                    onOpenBoardList(selectedTodayList.id)
                                } label: {
                                    Label("Open today's list", systemImage: "arrow.up.right.square")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Choose a different list") {
                                    listPickerMode = .chooseToday
                                }
                                .frame(minHeight: 44)
                            }
                        } else {

                            Text("Choose one of your existing board lists for today's plan.")
                                .foregroundStyle(.secondary)

                            Button("Choose today's list", systemImage: "list.bullet") {
                                listPickerMode = .chooseToday
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your board")
                            .font(.title2.weight(.semibold))

                        Text("Open any existing list, including open work and custom lists.")
                            .foregroundStyle(.secondary)

                        Button("Browse all lists", systemImage: "rectangle.3.group") {
                            listPickerMode = .browseAll
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationBarTitleDisplayMode(.inline)
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
}
