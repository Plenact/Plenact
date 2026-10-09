// --------------------------------------------------------------------------------------------------
// @file       App.swift
// @brief      Application entry point and Today-first navigation shell
// @details    Owns the shared Week snapshot, personal collections, local profile, and bookmarks.
//             Composes Today, Week, Library, and Saved; implements date-scoped list selection,
//             quick card capture, local search, label browsing, and card-date calendar views.
//             Coordinates board archive/restore operations and local persistence callbacks
//
// @author     Justin Reina, Firmware/Systems Engineering
// @created    9/24/26
// @last rev   10/8/26
//
// @notes      Archived lists remain in the complete Week snapshot but are excluded from active
//             view bindings. Restored Week archives become separate personal boards.
//             Remote authentication and transport remain in the Sync feature; this shell does
//             not publish local Board, profile, bookmark, or archive data to the shared API
//
// @section    Opens
//     - Consider re-modularizing source into shorter files
//     - Consider extracting navigation, Today search, collection, and calendar surfaces into
//       focused files while preserving their shared state and persistence ownership
//     - Consider making re-order lists button more intuitive to find
//
// --------------------------------------------------------------------------------------------------
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
    /// @fcn        Plenact.body
    /// @brief      Build the application's initial scene
    /// @details    Provides the root window and installs AppRootView as the Today-first surface
    ///
    /// @return     (some Scene) configured application scene
    ///
    /// @post       Each window installs its own AppRootView navigation shell
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
    case today       /* Today's planning entry point             */
    case board       /* Complete kanban workspace                */
    case lists       /* Library of Week and personal collections */
    case saved       /* Device-local saved cards                 */
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

    ///
    /// @fcn        TodayListPickerMode.id
    /// @brief      Return the stable identity for picker presentation
    /// @details    Uses the enum raw value so SwiftUI can identify the active sheet
    ///
    /// @return     (String) picker-mode raw value
    /// @post       No presentation or stored state is changed
    ///
    var id: String { rawValue } /* Stable tab-selection identity */

    ///
    /// @fcn        TodayListPickerMode.title
    /// @brief      Return the user-facing title for the picker mode
    /// @details    Keeps the sheet heading aligned with the action being performed
    ///
    /// @return     (String) heading for choosing today's list or browsing Board lists
    /// @post       No selection is changed
    ///
    var title: String { /* User-facing list-picker title */
        switch self {

            case .chooseToday: "Choose today's list"
            case .browseAll:   "Board lists"
        }
    }
}


///
/// Resolves a valid default destination for the Today screen
///
/// @section    Purpose
///     Keep initial list-choice precedence independent from view construction
///
enum TodayListSelection {


    ///
    /// @fcn        TodayListSelection.currentDayList(in:date:calendar:)
    /// @brief      Resolve the active Week list for the supplied local day
    /// @details    Matches canonical weekday titles without consulting manual Today preferences.
    ///             Missing, archived, renamed, or ambiguous weekday lists produce no focus.
    ///
    /// @param[in]  lists     Canonical Week list records
    /// @param[in]  date      Date whose local weekday is resolved
    /// @param[in]  calendar  Calendar and time zone used to determine the weekday
    ///
    /// @return     (KanbanList?) unique active weekday list, or nil when unavailable
    ///
    static func currentDayList(in lists: [KanbanList], date: Date, calendar: Calendar = .current) -> KanbanList? {

        let title = weekdayTitle(for: date, calendar: calendar) /* List title matching the requested day */
        
        let matches  = lists.filter { /* Active lists matching the weekday */

            !$0.isArchived && $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
            
                .caseInsensitiveCompare(title) == .orderedSame
        }

        return matches.count == 1 ? matches.first : nil
    }


    ///
    /// @fcn        TodayListSelection.ensureCurrentDayList(in:date:calendar:)
    /// @brief      Find today's active Week list or append a new blank weekday list
    /// @details    Preserves every supplied active and archived list, reserving a fresh ID across
    ///             both partitions when the real-world weekday has no active matching title
    ///
    /// @param[in]  lists     Active and archived Week lists
    /// @param[in]  date      Date whose local weekday is required
    /// @param[in]  calendar  Calendar and time zone used to determine the weekday
    ///
    /// @return     Updated complete list snapshot and the active weekday list
    ///
    /// @post       Existing list and card records remain unchanged
    ///
    static func ensureCurrentDayList(
        lists: [KanbanList],
        date: Date = .now,
        calendar: Calendar = .current
    ) -> (lists: [KanbanList], dayList: KanbanList) {

        let title = weekdayTitle(for: date, calendar: calendar) /* Required weekday list title */

        if let existing = lists.first(where: {
            !$0.isArchived && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(title) == .orderedSame
        }) {

            return (lists, existing)
        }

        let nextID = (lists.map(\.id).max() ?? -1) + 1 /* Fresh ID reserved across active and archived lists */
        let dayList = KanbanList(id: nextID, title: title, cards: []) /* New empty list for the actual weekday */

        return (lists + [dayList], dayList)
    }


    ///
    /// @fcn        TodayListSelection.weekdayTitle(for:calendar:)
    /// @brief      Resolve the canonical weekday title for a local calendar date
    /// @details    Uses Calendar's weekday component so local time zone and midnight determine the day
    /// @param[in]  date      Date whose weekday title is needed
    /// @param[in]  calendar  Calendar and time zone used to determine the weekday
    /// @return     (String) canonical weekday list title
    ///
    private static func weekdayTitle(for date: Date, calendar: Calendar) -> String {

        let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"] /* Calendar-indexed weekday names */
        return weekdays[calendar.component(.weekday, from: date) - 1]
    }
}


/// Persists device-local bookmarks without changing the shared Board document.
///
/// @section    Purpose
///     Isolate bookmark preference reads and writes from the shared Board snapshot
///
private enum SavedCardPersistence {

    private static let storageKey = "Plenact.SavedCardIDs.v1" /* Versioned local bookmark key */


    ///
    /// @fcn        SavedCardPersistence.load()
    /// @brief      Restore device-local card bookmarks
    /// @details    Reads integer IDs from the versioned standard-preferences key and removes
    ///             duplicate values through Set construction; missing or incompatible data yields
    ///             no bookmarks
    ///
    /// @return     (Set<Int>) stored card identities
    ///
    /// @post       Stored preferences and Board content are unchanged
    ///
    static func load() -> Set<Int> {

        Set(UserDefaults.standard.array(forKey: storageKey) as? [Int] ?? [])
    }


    ///
    /// @fcn        SavedCardPersistence.save(_:)
    /// @brief      Store the current device-local bookmark set
    /// @details    Writes IDs as a sorted integer array for deterministic preference representation
    ///
    /// @param[in]  cardIDs  Complete set of bookmarked card IDs
    ///
    /// @return     (Void) replaces the stored bookmark array
    ///
    /// @post       The shared Board document is not modified
    ///
    static func save(_ cardIDs: Set<Int>) {

        UserDefaults.standard.set(cardIDs.sorted(), forKey: storageKey)
    }
}


///
/// Persists the most recently viewed Week list identity
///
/// @section    Purpose
///     Reuse a valid destination for subsequent card creation
///
enum LastViewedListStore {

    private static let key = "Plenact.LastViewedList.v1" /* Versioned last-viewed-list preference key */


    ///
    /// @fcn        LastViewedListStore.load(from:)
    /// @brief      Read the most recently viewed Week list identity
    /// @details    Uses an injectable preferences store to support isolated persistence tests
    ///
    /// @param[in]  defaults  Preferences containing the last-viewed key
    ///
    /// @return     (Int?) stored integer ID, or nil for a missing or incompatible value
    ///
    /// @post       No preferences are changed or list existence validated
    ///
    static func load(from defaults: UserDefaults = .standard) -> Int? {

        defaults.object(forKey: key) as? Int
    }


    ///
    /// @fcn        LastViewedListStore.save(_:to:)
    /// @brief      Remember the most recently viewed Week list
    /// @details    Stores the supplied identity without changing the list or validating its
    ///             existence
    ///
    /// @param[in]  listID    List identity to remember
    /// @param[in]  defaults  Preferences receiving the last-viewed key
    ///
    /// @return     (Void) replaces the stored list ID
    ///
    static func save(_ listID: Int, to defaults: UserDefaults = .standard) {

        defaults.set(listID, forKey: key)
    }


    ///
    /// @fcn        LastViewedListStore.resolve(in:fallback:from:)
    /// @brief      Choose an existing list for a new-card destination
    /// @details    Uses the stored last-viewed list when present in the supplied collection,
    ///             otherwise a valid fallback, then the first list
    ///
    /// @param[in]  lists     Available destination lists
    /// @param[in]  fallback  Optional preferred ID when the saved ID is unavailable
    /// @param[in]  defaults  Preferences supplying the last-viewed ID
    ///
    /// @return     (Int?) existing destination ID, or nil for an empty collection
    ///
    /// @post       Preferences and list order are unchanged
    ///
    static func resolve(in lists: [KanbanList], fallback: Int? = nil, from defaults: UserDefaults = .standard) -> Int? {

        if let lastViewed = load(from: defaults), lists.contains(where: { /* Remembered new-card destination */

            $0.id == lastViewed
        }) {
            return lastViewed
        }

        if let fallback, lists.contains(where: { /* Alternate new-card destination */

            $0.id == fallback
        }) {
            return fallback
        }

        return lists.first?.id
    }
}


///
/// Carries the latest vertical offset reported by Today content
///
/// @section    Purpose
///     Bridge child scroll geometry to the header's fade observer
///
private struct TodayScrollOffsetPreferenceKey: PreferenceKey {

    ///
    /// @section    Purpose
    ///     Carry the latest vertical scroll offset from Today content to its observer
    ///
    /// Latest vertical offset reported by Today scroll content.
    static var defaultValue: CGFloat = 0 /* Unmeasured bottom navigation height */


    ///
    /// @fcn        TodayScrollOffsetPreferenceKey.reduce(value:nextValue:)
    /// @brief      Accept the latest reported Today content offset
    /// @details    Replaces the accumulated preference rather than adding nested offsets
    ///
    /// @param[in,out] value      Accumulated vertical offset
    /// @param[in]     nextValue  Provider for the next child preference
    ///
    /// @return     (Void) updates value with the next offset
    ///
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {

        value = nextValue()
    }
}


/// Reports actual content movement using native scroll geometry when available.
///
/// Tracks Today scroll movement to control the header fade
///
/// @section    Purpose
///     Use native scroll geometry where available and a coordinate-space fallback otherwise
///
private struct TodayScrollFadeTracking: ViewModifier {

    @Binding var isScrolled: Bool           /* Header fade visibility state */


    ///
    /// @fcn        TodayScrollFadeTracking.body(content:)
    /// @brief      Track whether Today content has moved beneath its header
    /// @details    Uses inset-adjusted native scroll geometry on iOS 18 and later; earlier systems
    ///             use the named coordinate-space offset preference
    ///
    /// @param[in]  content  Scroll content receiving tracking behavior
    ///
    /// @return     (some View) content with scroll-observation modifiers
    ///
    /// @post       Scroll callbacks set isScrolled beyond the two-point threshold
    ///
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

    @State private var lists: [KanbanList]                 = []                             /* Complete in-memory Week snapshot                    */
    @State private var collections                         = PersonalCollectionStore.load()	/* Device-local personal collections                   */
    @State private var hasLoadedBoard                      = false                          /* Whether the initial Week snapshot has loaded        */
    @State private var profile                             = LocalProfileStore.load()       /* Optional local identity and settings                */
    @State private var selectedDestination: AppDestination = .today                         /* Currently selected primary destination              */ 
    @State private var weekRootRequest                     = 0                              /* Explicit Week toolbar taps return to the Board root */
    @State private var savedCardIDs                        = SavedCardPersistence.load()    /* Device-local saved cards                            */
    @State private var savedPersonalCardTarget: PersonalSavedCardTarget?                    /* Personal bookmark requested from Saved             */
    @State private var quickCreateRequest                  = 0                              /* Center-bar quick-create request                     */
    @State private var showsCenterNewCardSheet             = false                          /* Destination picker for New outside Today            */
    @State private var isWeekListRequestArmed              = false                          /* Whether New's long press will create a Week list    */
    @State private var weekListShakeTrigger                = 0                              /* Trigger for long-press confirmation animation       */

    @State private var boardTargetListID:                  Int?                             /* List requested by a Today-to-Board navigation       */
    @State private var boardTargetCardID:                  Int?                             /* Card requested by a Today-to-Board navigation       */
    @State private var activePersonalListNewNote:          (() -> Void)?					/* Callback to create a new note in active pers list   */

    @Environment(\.verticalSizeClass) private var verticalSizeClass                         /* Layout size class used to compact the landscape bar */


    ///
    /// @fcn        AppRootView.body
    /// @brief      Load the Week snapshot before exposing the navigation shell
    /// @details    Presents a background surface until asynchronous local loading completes,
    ///             then installs navigation content; database activity feedback covers both states
    ///
    /// @return     (some View) loading surface or configured app navigation
    /// @post       The task assigns the loaded snapshot and marks initial loading complete
    ///
    var body: some View {           /* Primary Today and Board navigation shell */

        Group {
            if hasLoadedBoard {

                navigationContent
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }
        }

        .databaseActivityOverlay()
        .task {
            guard !hasLoadedBoard else {

                return
            }

            lists = await KanbanBoardPersistence.loadListsInBackground()
            hasLoadedBoard = true
        }
    }


    ///
    /// @fcn        AppRootView.navigationContent
    /// @brief      Compose the four primary destinations and persistence observers
    /// @details    Supplies active/archive list partitions, shared collections, profile callbacks,
    ///             bookmarks, and navigation targets; saves complete snapshots when state changes
    ///
    /// @return     (some View) tab shell, custom navigation bar, and new-card sheet
    /// 
    /// @pre        Initial Week loading has completed
    /// @post       User edits flow through shared bindings; collection-save errors reach the activity banner
    ///
    private var navigationContent: some View { /* Active tab with shared navigation chrome */

        TabView(selection: $selectedDestination) {

            TodayHomeView(
                lists:                  $lists.activeLists,
                archivedLists:          $lists.archivedLists,
                savedCardIDs:           $savedCardIDs,
                profile:                profile,
                onSaveProfile:          { updatedProfile in
                    profile = updatedProfile
                    LocalProfileStore.save(updatedProfile)
                },
                onRemoveProfile:        {
                    profile = nil
                    LocalProfileStore.remove()
                },
                onAddCard:              { listID, title, description, presentation, actions in
                    addCard(to: listID, title: title, description: description, presentation: presentation, actions: actions)
                },
                onToggleCardCompletion: toggleCardCompletion,
                onOpenBoardList:        openBoardList,
                onOpenBoardCard:        openBoardCard,
                onArchiveCard:          archiveWeekCard,
                onDeleteCard:           deleteWeekCard,
                onArchiveList:          archiveWeekList,
                onDeleteList:           deleteWeekList,
                quickCreateRequest:     quickCreateRequest
            )
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }

            .tag(AppDestination.today)
            .toolbar(.hidden, for: .tabBar)

            ContentView(
                lists:             $lists.activeLists,
                archivedLists:     $lists.archivedLists,
                boardTargetListID: $boardTargetListID,
                boardTargetCardID: $boardTargetCardID,
                boardRootRequest:  weekRootRequest,
                savedCardIDs:      $savedCardIDs,
                onListViewed:      rememberLastViewedList,
                onArchiveBoard:    archiveWeekBoard,
                onDeleteBoard:     deleteWeekContents,
                deleteBoardTitle:  "Delete Week contents",
                onCommitDeletion:  commitWeekDeletion,
                onListsChanged:    { _ in }
            )
                .tabItem {
                    Label("Board", systemImage: "rectangle.3.group")
                }

                .tag(AppDestination.board)
                .toolbar(.hidden, for: .tabBar)

            libraryTab

            SavedCardsView(
                lists:           lists.filter { !$0.isArchived },
                savedCardIDs:    savedCardIDs,
                collections:     $collections,
                onOpenBoardList: openBoardList,
                onOpenPersonalCard: { target in
                    savedPersonalCardTarget = target
                    selectedDestination = .lists
                },
                onRestoreBoard:  restoreBoard,
                onDeleteBoard:   deletePersonalBoard,
                onArchiveCard:   archiveWeekCard,
                onDeleteCard:    deleteWeekCard
            )
                .tabItem {
                    Label("Saved", systemImage: "bookmark")
                }

                .tag(AppDestination.saved)
                .toolbar(.hidden, for: .tabBar)
        }

        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: verticalSizeClass == .compact ? 52 : 74)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                bottomNavigationBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }

        .onChange(of: savedCardIDs) { _, updatedIDs in
            SavedCardPersistence.save(updatedIDs)
        }

        .onChange(of: lists) { old, updated in
            guard hasLoadedBoard else {

                return
            }

            let candidates = CardAttachmentStore.fileNames(in: old).subtracting(CardAttachmentStore.fileNames(in: updated)) /* Media removed by the collection update */

            KanbanBoardPersistence.enqueueSave(updated, onSuccess: { cleanDeletedMedia(candidates) })
        }

        .onChange(of: collections) { old, updated in
            do {

                try PersonalCollectionStore.saveChecked(updated)
                cleanDeletedMedia(CardAttachmentStore.fileNames(in: old.flatMap(\.lists))
                    .subtracting(CardAttachmentStore.fileNames(in: updated.flatMap(\.lists))))
            } catch {
                DatabaseActivity.shared.report("Could not save your boards: \(error.localizedDescription)")
            }
        }

        .sheet(isPresented: $showsCenterNewCardSheet) {
            QuickNoteComposer(
                lists:         $lists.activeLists,
                initialListID: LastViewedListStore.resolve(in: lists.filter { !$0.isArchived }, fallback: profile?.preferences.defaultListID)
            ) { listID, title, description, presentation, actions in
                addCard(to: listID, title: title, description: description, presentation: presentation, actions: actions)
            }

            .databaseActivityOverlay()
        }
    }


    private var libraryTab: some View { /* Personal collection directory and creation actions */

        BoardListsView(
            retainedWeekLists:   lists,
            collections:         $collections,
            registerListNewNote: registerPersonalListNewNote,
            onOpenSaved:         openSavedDestination,
            savedPersonalCardTarget: savedPersonalCardTarget,
            onClearSavedPersonalCardTarget: { savedPersonalCardTarget = nil }
        )
        .tabItem {
            Label("Library", systemImage: "books.vertical")
        }
        .tag(AppDestination.lists)
        .toolbar(.hidden, for: .tabBar)
    }


    ///
    /// @fcn        AppRootView.bottomNavigationBar
    /// @brief      Build the custom destination bar and central New control
    /// @details    Honors navigation-label preferences and remains anchored at the screen bottom
    ///             while the keyboard overlays it. The decorative background extends through the
    ///             bottom safe area independently of the fixed-height controls. In portrait,
    ///             its top edge is inset 20 points so New overlaps it without moving any controls.
    ///             New requests Today capture, a Library Note, or a Week-card destination picker;
    ///             a long press arms Week-list creation and shake feedback
    ///
    /// @return     (some View) paper-backed navigation controls
    /// @post       Button and gesture callbacks update navigation and creation-request state
    ///
    private var bottomNavigationBar: some View { /* Shared tab and quick-creation controls */
        let isCompact = verticalSizeClass == .compact /* Landscape-height navigation layout */

        return ZStack(alignment: isCompact ? .center : .top) {
            HStack(spacing: 4) {
                tabButton(.today, title: "Today", systemImage: "sun.max.fill")
                tabButton(.board, title: "Week", systemImage: "rectangle.3.group.fill")

                Color.clear
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 44 : 54)
                    .accessibilityHidden(true)

                tabButton(.lists, title: "Library", systemImage: "books.vertical.fill")
                tabButton(.saved, title: "Saved",   systemImage: "bookmark.fill")
            }

            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .offset(y: isCompact ? 0 : 25)

            let newLayout = isCompact /* Adaptive arrangement of creation actions */
                ? AnyLayout(HStackLayout(spacing: 6))
                : AnyLayout(VStackLayout(spacing: 6))
            newLayout {
                Button {
                    if isWeekListRequestArmed {

                        isWeekListRequestArmed = false
                        addWeekList()
                    } else if selectedDestination == .today {
                        quickCreateRequest += 1
                    } else if selectedDestination == .lists, let activePersonalListNewNote { /* Registered List-scoped Note action */
                        activePersonalListNewNote()
                    } else {
                        showsCenterNewCardSheet = true
                    }
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-7))
                        .frame(width: isCompact ? 44 : 68, height: isCompact ? 44 : 68)
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

                .accessibilityLabel(activePersonalListNewNote == nil ? "Create a new card" : "Create a new Note")
                .accessibilityHint(
                    activePersonalListNewNote == nil
                        ? "Tap to create a card. Touch and hold until New shakes, then release to add a Week list."
                        : "Creates a Note in the open personal List, or the most recently opened personal List from Library. Touch and hold until New shakes, then release to add a Week list."
                )

                    if profile?.preferences.showsNavigationLabels ?? true {

                        Text("New")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.92))
                    }
            }

            .offset(y: isCompact ? 0 : 14)
            .zIndex(2)
        }

        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 52 : 74)
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

            .padding(.top, isCompact ? 0 : 20)
            .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            .allowsHitTesting(false)
        }

        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: -4)
    }


    ///
    /// @fcn        AppRootView.tabButton(_:title:systemImage:)
    /// @brief      Render one primary destination button
    /// @details    Applies selected styling and accessibility traits, and conditionally displays
    ///             the caption according to local profile preferences
    ///
    /// @param[in]  destination  Destination selected when tapped
    /// @param[in]  title        Visible caption and accessibility label
    /// @param[in]  systemImage  SF Symbol naming the destination
    ///
    /// @return     (some View) configured destination button
    ///
    /// @post       Week returns to the Board root at the actual local weekday list,
    ///             creating a blank weekday list if missing without replacing existing content
    ///
    private func tabButton(_ destination: AppDestination, title: String, systemImage: String) -> some View {

        let isSelected = selectedDestination == destination /* Current tab selection */

        return Button {

            if destination == .board {

                let result = TodayListSelection.ensureCurrentDayList(lists: lists)
                if result.lists != lists {
                    lists = result.lists
                }
                boardTargetCardID = nil
                boardTargetListID = result.dayList.id
                weekRootRequest += 1
            }

            selectedDestination = destination

        } label: {

            let layout = verticalSizeClass == .compact /* Adaptive quick-creation action layout */
                ? AnyLayout(HStackLayout(spacing: 6))
                : AnyLayout(VStackLayout(spacing: 4))
            layout {

                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .semibold))

                if profile?.preferences.showsNavigationLabels ?? true {

                    Text(title)
                        .font(.caption)
                }
            }

            .frame(maxWidth: .infinity, minHeight: verticalSizeClass == .compact ? 44 : 54)
            .contentShape(Rectangle())
        }

        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.82))
        .accessibilityLabel(title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }


    ///
    /// @fcn        AppRootView.openBoardList(_:)
    /// @brief      Route to a specific list in Week
    /// @details    Remembers an existing list, clears any pending card target, and selects Week;
    ///             ContentView consumes and validates the pending list request
    ///
    /// @param[in]  listID  Requested Week list identity
    ///
    /// @return     (Void) updates navigation targets and selected destination
    ///
    /// @post       Board content remains unchanged
    ///
    private func openBoardList(_ listID: Int) {

        rememberLastViewedList(listID)
        boardTargetCardID = nil
        boardTargetListID   = listID
        selectedDestination = .board
    }


    ///
    /// @fcn        AppRootView.registerPersonalListNewNote(_:)
    /// @brief      Register the New action supplied by an open personal List
    /// @details    The Library directory and personal Boards register nil and retain Week creation
    /// @param[in]  action  Optional List-scoped New Note presentation action
    /// @return     (Void) updates the current toolbar route only
    ///
    private func registerPersonalListNewNote(_ action: (() -> Void)?) {

        activePersonalListNewNote = action
    }


    ///
    /// @fcn        AppRootView.openSavedDestination()
    /// @brief      Select the existing Saved tab from Library
    /// @return     (Void) changes navigation destination without duplicating Saved content
    ///
    private func openSavedDestination() {

        selectedDestination = .saved
    }


    ///
    /// @fcn        AppRootView.archiveWeekBoard()
    /// @brief      Preserve the complete Week Board as an archived personal board
    /// @details    Saves the recovery collection before clearing Week lists and bookmarks,
    ///             including archived lists/cards; errors are presented through DatabaseActivity
    ///
    /// @return     (Void) archives Week and navigates to Saved after saving the recovery collection
    ///
    /// @post       Success clears pending targets; failure leaves the active Week snapshot intact
    /// @note       Restoring this archive creates a separate board rather than replacing Week
    ///
    private func archiveWeekBoard() {

        let archived = PersonalCollection.archivedWeekBoard(lists: lists, savedCardIDs: savedCardIDs) /* Retained copy of the current Week workspace */
        let updated = collections + [archived] /* Directory snapshot including the archived Week */

        do {

            // Persist the recovery copy before clearing the active Week snapshot.
            try PersonalCollectionStore.saveChecked(updated)
            collections = updated
            lists = []
            savedCardIDs = []
            boardTargetListID = nil
            boardTargetCardID = nil
            selectedDestination = .saved
        } catch {

            DatabaseActivity.shared.report("Could not archive the Week Board: \(error.localizedDescription) The board has not been removed.")
        }
    }


    ///
    /// @fcn        AppRootView.cleanDeletedMedia(_:)
    /// @brief      Clean saved removal candidates against all retained content
    /// @details    Includes in-memory and persisted Week/collections plus the retained undo
    ///             snapshot; unreadable persisted references block cleanup and produce an explicit
    ///             notice
    ///
    /// @param[in]  candidates  Filenames removed by a successfully saved mutation
    ///
    /// @return     (Void) clean saved removal candidates against all retained content
    ///
    private func cleanDeletedMedia(_ candidates: Set<String>) {

        guard !candidates.isEmpty else {

            return
        }

        do {

            let persistedWeek = try UserDefaults.standard.data(forKey: "Plenact.Board.v1") /* Stored Week lists protecting referenced media */
                .map { try JSONDecoder().decode([KanbanList].self, from: $0) } ?? []
            let persistedCollections = try UserDefaults.standard.data(forKey: "Plenact.PersonalCollections.v1") /* Stored personal collections protecting referenced media */
                .map { try JSONDecoder().decode([PersonalCollection].self, from: $0) } ?? []
            let undo = try UserDefaults.standard.data(forKey: "Plenact.ExampleLoadUndo.v1") /* Stored example-load recovery snapshot */
                .map { try JSONDecoder().decode(ExampleLoadUndoSnapshot.self, from: $0) }
            let retained = lists + collections.flatMap(\.lists) + persistedWeek /* All snapshots whose media must remain available */
                + persistedCollections.flatMap(\.lists) + (undo?.lists ?? [])

            try CardAttachmentStore.removeDeletedFiles(candidates, keeping: CardAttachmentStore.fileNames(in: retained))
        } catch {

            DatabaseActivity.shared.report("Content was saved, but some unused media could not be removed: \(error.localizedDescription)")
        }
    }


    ///
    /// @fcn        AppRootView.deleteWeekContents()
    /// @brief      Clear confirmed Week content without removing the workspace
    /// @details    Keeps separate personal/archive copies and resets pending navigation
    ///
    /// @return     (Void) clear confirmed Week content without removing the workspace
    ///
    private func deleteWeekContents() {

        do {

            try commitWeekDeletion([], [])
            boardTargetListID = nil
            boardTargetCardID = nil
        } catch {

            DatabaseActivity.shared.report("Could not delete Week contents: \(error.localizedDescription) They have been retained.")
        }
    }


    ///
    /// @fcn        AppRootView.commitWeekDeletion(_:_:)
    /// @brief      Persist confirmed Week removal before updating bindings
    /// @details    Cleans only saved removal candidates and preserves retained media references
    ///
    /// @param[in]  snapshot   Complete remaining Week snapshot
    /// @param[in]  bookmarks  Remaining Week bookmarks
    ///
    /// @return     (Void) persist confirmed Week removal before updating bindings
    ///
    /// @throws     Encoding or preference errors; visible state stays unchanged
    ///
    private func commitWeekDeletion(_ snapshot: [KanbanList], _ bookmarks: Set<Int>) throws {

        let candidates = CardAttachmentStore.fileNames(in: lists).subtracting(CardAttachmentStore.fileNames(in: snapshot)) /* Media removed by clearing Week content */

        try KanbanBoardPersistence.saveListsChecked(snapshot)
        lists = snapshot
        savedCardIDs = bookmarks
        SavedCardPersistence.save(bookmarks)
        cleanDeletedMedia(candidates)
    }


    ///
    /// @fcn        AppRootView.deletePersonalBoard(_:)
    /// @brief      Save removal of a confirmed personal collection before publishing it
    /// @details    Failure leaves the collection retained and reports an error
    ///
    /// @param[in]  id  Collection UUID, not a Board-local card ID
    ///
    /// @return     (Bool) whether the confirmed removal was saved and published successfully
    ///
    @discardableResult
    private func deletePersonalBoard(_ id: UUID) -> Bool {

        let updated = collections.filter { $0.id != id } /* Directory snapshot excluding the deleted collection */

        do {

            try PersonalCollectionStore.saveChecked(updated)
            collections = updated

            return true
        } catch {

            DatabaseActivity.shared.report("Could not delete the collection: \(error.localizedDescription) It has been retained.")

            return false
        }
    }


    ///
    /// @fcn        AppRootView.archiveWeekList(_:)
    /// @brief      Retain a Week list outside active navigation
    /// @details    Changes only its archive marker
    ///
    /// @param[in]  id  Week list identity
    ///
    /// @return     (Void) retain a Week list outside active navigation
    ///
    private func archiveWeekList(_ id: Int) {

        if let index = lists.firstIndex(where: { /* Position of the Week list to archive */

            $0.id == id
        }) {
            lists[index].isArchived = true
        }
    }


    ///
    /// @fcn        AppRootView.deleteWeekList(_:)
    /// @brief      Remove confirmed Week list content and bookmarks
    /// @details    Applies the shared complete-snapshot deletion helper
    ///
    /// @param[in]  id  Week list identity
    ///
    /// @return     (Bool) whether the confirmed removal was saved and published successfully
    ///
    @discardableResult
    private func deleteWeekList(_ id: Int) -> Bool {

        var snapshot = lists /* Week snapshot for checked deletion */
        var bookmarks = savedCardIDs /* Bookmarks pruned alongside removed content */

        BoardContentDeletion.list(id, in: &snapshot, savedCardIDs: &bookmarks)

        do {

            try commitWeekDeletion(snapshot, bookmarks)

            return true
        } catch {

            DatabaseActivity.shared.report("Could not delete the list: \(error.localizedDescription) It has been retained.")

            return false
        }
    }


    ///
    /// @fcn        AppRootView.archiveWeekCard(_:)
    /// @brief      Archive a bookmarked Week card without removing its bookmark
    /// @details    Finds the owning list by Board-local identity
    ///
    /// @param[in]  id  Week card identity
    ///
    /// @return     (Void) archive a bookmarked Week card without removing its bookmark
    ///
    private func archiveWeekCard(_ id: Int) {

        if let index = lists.firstIndex(where: { /* Week list containing the card to archive */

            $0.cards.contains(where: { $0.id == id })
        }) {
            lists[index].archiveCard(id: id)
        }
    }


    ///
    /// @fcn        AppRootView.deleteWeekCard(_:)
    /// @brief      Permanently remove a confirmed bookmarked Week card
    /// @details    Includes archive partitions and removes its bookmark
    ///
    /// @param[in]  id  Week card identity
    ///
    /// @return     (Bool) whether the confirmed removal was saved and published successfully
    ///
    @discardableResult
    private func deleteWeekCard(_ id: Int) -> Bool {

        var snapshot = lists /* Week snapshot for checked deletion */
        var bookmarks = savedCardIDs /* Bookmarks pruned alongside removed content */

        BoardContentDeletion.card(id, in: &snapshot, savedCardIDs: &bookmarks)

        do {

            try commitWeekDeletion(snapshot, bookmarks)

            return true
        } catch {

            DatabaseActivity.shared.report("Could not delete the card: \(error.localizedDescription) It has been retained.")

            return false
        }
    }


    ///
    /// @fcn        AppRootView.restoreBoard(_:)
    /// @brief      Reactivate an archived board under a unique title
    /// @details    Computes the restored collection snapshot and saves it before updating the UI;
    ///             archived Week copies remain separate from the current Week workspace
    ///
    /// @param[in]  id  Archived collection identity
    ///
    /// @return     (Void) updates collections after successful persistence
    ///
    /// @post       Missing/nonarchived IDs do nothing; save failures leave state unchanged and show
    ///             an error
    ///
    private func restoreBoard(_ id: UUID) {

        guard let index = collections.firstIndex(where: { /* Position of the archived Board to restore */

            $0.id == id && $0.isArchived == true
        }) else {

            return
        }

        var updated = collections /* Directory snapshot carrying the restored Board */

        updated[index].restore(existingTitles: ["Week Board"] + collections.filter { $0.id != id }.map(\.title))
        do {

            try PersonalCollectionStore.saveChecked(updated)
            collections = updated
        } catch {

            DatabaseActivity.shared.report("Could not restore the board: \(error.localizedDescription)")
        }
    }


    ///
    /// @fcn        AppRootView.openBoardCard(listID:cardID:)
    /// @brief      Request a list and card detail destination in Week
    /// @details    Remembers the list and supplies stable targets for ContentView to validate and
    ///             open
    ///
    /// @param[in]  listID  Containing Week list identity
    /// @param[in]  cardID  Card identity to open within the list
    ///
    /// @return     (Void) selects Week and updates both navigation targets
    ///
    /// @post       No card or list content is modified
    ///
    private func openBoardCard(listID: Int, cardID: Int) {

        rememberLastViewedList(listID)
        boardTargetCardID = cardID
        boardTargetListID = listID
        selectedDestination = .board
    }


    ///
    /// @fcn        AppRootView.rememberLastViewedList(_:)
    /// @brief      Persist an existing Week list as the last-viewed destination
    /// @details    Avoids redundant preference writes and ignores IDs absent from the complete
    ///             snapshot
    ///
    /// @param[in]  listID  List identity reported by navigation or the Board viewport
    ///
    /// @return     (Void) updates the last-viewed preference when necessary
    ///
    /// @post       Board content and current navigation remain unchanged
    ///
    private func rememberLastViewedList(_ listID: Int) {

        guard lists.contains(where: {

            $0.id == listID
        }), LastViewedListStore.load() != listID else {

            return
        }

        LastViewedListStore.save(listID)
    }


    ///
    /// @fcn        AppRootView.toggleCardCompletion(in:cardID:)
    /// @brief      Toggle completion of a card in the shared Week snapshot
    /// @details    Locates list and active-card indices by ID; root state observation handles
    ///             persistence
    ///
    /// @param[in]  listID  Containing list identity
    /// @param[in]  cardID  Active card identity
    ///
    /// @return     (Void) flips the title-completion flag
    ///
    /// @post       Missing list/card identities leave state unchanged
    ///
    private func toggleCardCompletion(in listID: Int, cardID: Int) {

        guard let listIndex = lists.firstIndex(where: { /* Position of the card's containing Week list */

            $0.id == listID
        }),
              let cardIndex = lists[listIndex].cards.firstIndex(where: { $0.id == cardID }) else { /* Position of the requested Week card */

            return
        }

        lists[listIndex].cards[cardIndex].isTitleChecked.toggle()
    }


    ///
    /// @fcn        AppRootView.addWeekList()
    /// @brief      Append a uniquely identified blank Week list and reveal it
    /// @details    Reserves IDs across active and archived lists and chooses an unused
    ///             case-insensitive New List title, adding a numeric suffix when necessary
    ///
    /// @return     (Void) appends the list and selects Week with a pending list target
    ///
    /// @post       Existing list/card contents remain unchanged; root observation saves the new
    ///             snapshot
    ///
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
        boardTargetListID = nextListID
        selectedDestination = .board
    }


        ///
        /// @fcn        AppRootView.addCard(to:title:description:)
        /// @brief      Append a new card to the requested Week list
        /// @details    Allocates an ID across active and archived cards/lists, recognizes divider
        ///             titles, and stores an empty description as no override; persistence follows
        ///             root observation
        ///
        /// @param[in]  listID       Existing destination list identity
        /// @param[in]  title        Card title supplied by the composer or quick capture
        /// @param[in]  description  Optional supporting text; empty text becomes nil
        ///
        /// @return     (Void) appends the new card when the list exists
        ///
        /// @pre        The caller has validated and trimmed the title
        /// @post       An absent list leaves the snapshot unchanged
        ///
        private func addCard(to listID: Int, title: String, description: String, presentation: ItemPresentation? = nil, actions: [String]? = nil) {

            guard let listIndex = lists.firstIndex(where: { /* Destination list index */

                $0.id == listID
            }) else {

                return
            }

            let nextCardID  = (lists.flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1 /* Board-wide next card ID */
            var updatedList = lists[listIndex] /* Mutable destination-list copy */

            let item = updatedList.makeItem(
                id: nextCardID, title: title, description: description.isEmpty ? nil : description,
                presentationOverride: presentation, actions: actions
            )
            updatedList.cards.append(item)

            lists[listIndex] = updatedList

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

    @Binding var lists:     [KanbanList]                    /* Shared local Board lists                           */
    @Binding var archivedLists: [KanbanList]                   /* Archived Week lists retained for example-load undo */
    @Binding var savedCardIDs: Set<Int>                     /* Device-local bookmarks used by card details        */
    let profile:            LocalProfile?                   /* Current local profile and preferences              */
    let onSaveProfile:      (LocalProfile)        -> Void   /* Save local identity and personalization            */
    let onRemoveProfile:    ()                    -> Void   /* Remove only local profile information              */
    let onAddCard: (Int, String, String, ItemPresentation?, [String]?) -> Void /* Create canonical Week records */
    let onToggleCardCompletion: (Int, Int) -> Void          /* Toggle local card completion                       */
    let onOpenBoardList:    (Int)                 -> Void   /* Route to Board at the selected list ID             */
    let onOpenBoardCard:    (Int, Int)             -> Void      /* Route to a Week card by list/card IDs */
    let onArchiveCard: (Int) -> Void /* Retain a canonical Week card */
    let onDeleteCard: (Int) -> Bool /* Report successful confirmed Week card removal */
    let onArchiveList: (Int) -> Void /* Retain a canonical Week list */
    let onDeleteList: (Int) -> Bool /* Report successful confirmed Week list removal */
    let quickCreateRequest: Int                             /* Center-bar requests for the Today composer         */

    @State private var selectedTodayListID: Int?            /* Board list selected for today's plan     */
    @State private var listPickerMode: TodayListPickerMode? /* Active list picker presentation mode     */
    @State private var showsAccountSettings = false         /* Account & Settings sheet presentation    */
    @State private var showsTodayList = false               /* Focused single-list presentation         */
    @State private var focusedListID: Int?                  /* Current-day list selected when opening Focus */
    @State private var quickCaptureTitle    = ""            /* Draft title for inline card capture      */
    @State private var quickComposerInitialTitle = ""       /* Quick-capture title handed to full editor */
    @State private var showsQuickNoteEditor = false         /* Full-size quick card editor presentation */
    @State private var showsTemplates = false
    @State private var pendingTemplate: QuickCaptureTemplate?
    @State private var composerTemplate: QuickCaptureTemplate?
    @State private var showsSearch          = false         /* Local Board search presentation          */
    @State private var presentComposerAfterListChoice = false /* Deferred center-plus request           */
    @State private var labelLibrary = LabelLibraryStore.load() /* Local categorized label definitions   */
    @State private var selectedLabelCategoryID: String? = nil /* Category selected in Your Labels       */
    @State private var selectedLabel: KanbanLabel? = nil    /* If label opened to its applied cards     */
    @State private var isContentScrolled = false            /* If content is passing beneath the header */


    ///
    /// @fcn        TodayHomeView.selectedTodayList
    /// @brief      Resolve today's saved list selection against the current board
    /// @details    Uses the in-memory date selection, or the profile default when no selection is set;
    ///             an unavailable effective ID returns no list rather than choosing another destination
    ///
    /// @return     (KanbanList?) selected list from the supplied active snapshot
    /// @post       No preference is read or changed during resolution
    ///
    private var selectedTodayList: KanbanList? {                                                /* Board list selected for the current date */

        let resolvedListID = selectedTodayListID                                                /* Calendar-derived or explicitly chosen Today list */

        guard let resolvedListID else { /* Available Week destination for new content */

            return nil
        }                                            /* No saved or default list selection */

        return lists.first { $0.id == resolvedListID }
    }


    ///
    /// @fcn        TodayHomeView.usedLabelCategories
    /// @brief      Group currently applied labels by their library category
    /// @details    Finds matching active cards for each label and omits labels and categories
    ///             with no usage, preserving the label library's ordering
    ///
    /// @return     ([TodayLabelCategoryUsage]) populated categories and their matching cards
    /// @post       Neither label definitions nor card assignments are changed
    ///
    private var usedLabelCategories: [TodayLabelCategoryUsage] { /* Label categories with matching active cards */

        labelLibrary.categories.compactMap { category in

            let labels: [TodayLabelUsage] = labelLibrary.labels /* Assigned labels grouped under this category */
            
                .filter { $0.categoryID == category.id }
                .compactMap { label in
                    let cards = cards(using: label.id) /* Active cards assigned this label */

                    guard !cards.isEmpty else {

                        return nil
                    }

                    return TodayLabelUsage(label: label, cards: cards)
                }

            guard !labels.isEmpty else {

                return nil
            }

            return TodayLabelCategoryUsage(category: category, labels: labels)
        }
    }


    ///
    /// @fcn        TodayHomeView.selectedUsedLabelCategory
    /// @brief      Resolve the visible applied-label category
    /// @details    Uses the selected category when still populated, otherwise the first used category
    ///
    /// @return     (TodayLabelCategoryUsage?) resolved category, or nil when no labels are used
    /// @post       The stored category selection is not modified
    ///
    private var selectedUsedLabelCategory: TodayLabelCategoryUsage? { /* Selected category resolved against current usage */
        usedLabelCategories.first { $0.id == selectedLabelCategoryID } ?? usedLabelCategories.first
    }


    ///
    /// @fcn        TodayHomeView.primaryControlHeight
    /// @brief      Resolve the profile's preferred primary-control height
    /// @details    Uses 52 points for larger controls and 44 points otherwise, including no-profile state
    ///
    /// @return     (CGFloat) preferred height in points
    /// @post       Profile preferences remain unchanged
    ///
    private var primaryControlHeight: CGFloat {                                                 /* Personalized control height */

        profile?.preferences.usesLargeControls == true ? 52 : 44
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
    private var todayHeader: some View { /* Today's heading and account controls */

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


    ///
    /// @fcn        TodayHomeView.todayHeaderPanel
    /// @brief      Place the Today header on a clipped paper-backed panel
    /// @details    Extends decoration through the top safe area and shows a bottom fade
    ///             when observed scroll content moves beneath the header
    ///
    /// @return     (some View) padded header with noninteractive background and fade
    /// @post       Rendering does not change scroll or navigation state
    ///
    private var todayHeaderPanel: some View { /* Styled container for Today's heading */

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
                                width:     geometry.size.width,
                                height:    geometry.size.width * (2796.0 / 1290.0),
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
                        colors:     [.clear, Color.black.opacity(0.14)],
                        startPoint: .top,
                        endPoint:   .bottom
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
    /// @return     (TodayHomeView) configured Today screen
    ///
    /// @pre        lists reflects the current in-memory board state
    /// @post       The initial selection is resolved; when neither saved nor profile choice exists,
    ///             a resolved starter selection is stored for today. Board content is unchanged
    ///
    init(
        lists:           Binding<[KanbanList]>,
        archivedLists: Binding<[KanbanList]>,
        savedCardIDs:    Binding<Set<Int>>,
        profile:         LocalProfile?,
        onSaveProfile:   @escaping (LocalProfile) -> Void,
        onRemoveProfile: @escaping () -> Void,
        onAddCard: @escaping (Int, String, String, ItemPresentation?, [String]?) -> Void,
        onToggleCardCompletion: @escaping (Int, Int) -> Void,
        onOpenBoardList: @escaping (Int) -> Void,
        onOpenBoardCard: @escaping (Int, Int) -> Void,
        onArchiveCard: @escaping (Int) -> Void,
        onDeleteCard: @escaping (Int) -> Bool,
        onArchiveList: @escaping (Int) -> Void,
        onDeleteList: @escaping (Int) -> Bool,
        quickCreateRequest: Int
    ) {

        self._lists          = lists
        self._archivedLists = archivedLists
        self._savedCardIDs   = savedCardIDs
        self.profile         = profile
        self.onSaveProfile   = onSaveProfile
        self.onRemoveProfile = onRemoveProfile
        self.onAddCard       = onAddCard
        self.onToggleCardCompletion = onToggleCardCompletion
        self.onOpenBoardList = onOpenBoardList
        self.onOpenBoardCard = onOpenBoardCard
        self.onArchiveCard = onArchiveCard
        self.onDeleteCard = onDeleteCard
        self.onArchiveList = onArchiveList
        self.onDeleteList = onDeleteList
        self.quickCreateRequest = quickCreateRequest

        _selectedTodayListID = State(initialValue: TodayListSelection.currentDayList(in: lists.wrappedValue, date: .now)?.id)
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
    /// @fcn        TodayHomeView.cards(using:)
    /// @brief      Find active cards assigned a specific label
    /// @details    Traverses supplied lists in order, excludes dividers, and includes list
    ///             provenance so matching cards can route back to their existing Board locations
    ///
    /// @param[in]  labelID  Stable label identity to match
    ///
    /// @return     ([TodayLabelCard]) matching card/list pairs
    ///
    /// @post       No card assignments or label definitions are changed
    ///
    private func cards(using labelID: String) -> [TodayLabelCard] {

        lists.flatMap { list in
            list.cards.compactMap { card in
                guard !card.isSectionDivider, card.labelIDs.contains(labelID) else {

                    return nil
                }

                return TodayLabelCard(card: card, listID: list.id, listTitle: list.title)
            }
        }
    }


    ///
    /// @fcn        TodayHomeView.yourLabelsSection
    /// @brief      Present applied labels and counts for the selected category
    /// @details    Offers a category menu, populated label rows, and an empty-state explanation;
    ///             selecting a label opens its matching-card sheet
    ///
    /// @return     (some View) Today label-browsing section
    /// @post       Interactions update category or label presentation state, not card assignments
    ///
    private var yourLabelsSection: some View { /* Assigned-label browsing and category controls */

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Labels")
                    .font(.title2.weight(.semibold))

                Spacer()

                if let selectedUsedLabelCategory { /* Category whose assigned labels are displayed */

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
            } else if let selectedUsedLabelCategory { /* Category shown in the empty-state context */
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


    ///
    /// @fcn        TodayHomeView.browseListsAction
    /// @brief      Provide the Browse all lists entry point
    /// @details    Opens the shared list picker in navigation mode rather than Today-selection mode
    ///
    /// @return     (some View) accessible list-browsing button
    /// @post       Tapping sets listPickerMode to browseAll
    ///
    private var browseListsAction: some View { /* Library navigation action */

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
    private func addQuickCard() {

        let title = quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines) /* Clean card title */

        guard !title.isEmpty else {

            return
        }

        guard let selectedTodayList else { /* Current list targeted by Today actions */

            listPickerMode = .chooseToday

            return
        }

        onAddCard(selectedTodayList.id, title, "", nil, nil)
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
    private func openQuickNoteEditor() {

        composerTemplate = nil
        guard selectedTodayList != nil else {

            presentComposerAfterListChoice = true
            listPickerMode = .chooseToday

            return
        }

        presentQuickNoteEditor()
    }


    ///
    /// @fcn        TodayHomeView.presentQuickNoteEditor()
    /// @brief      Move the inline draft into the full card composer
    /// @details    Clears inline capture while the composer owns the draft; an unsubmitted title
    ///             is restored when that composer is dismissed
    ///
    /// @return     (Void) opens the full editor with the current quick-capture title
    ///
    private func presentQuickNoteEditor() {

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
    private func selectTodayList(_ list: KanbanList) {

        selectedTodayListID = list.id

        let shouldPresentComposer = presentComposerAfterListChoice /* Deferred New-button action */

        presentComposerAfterListChoice = false
        listPickerMode = nil

        if shouldPresentComposer {

            Task { @MainActor in
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
    private func ensureCurrentWeekdayList() {

        let result = TodayListSelection.ensureCurrentDayList(lists: lists + archivedLists)
        let activeLists = result.lists.filter { !$0.isArchived } /* Updated active Week lists */
        let retainedLists = result.lists.filter(\.isArchived) /* Preserved archived Week lists */

        if activeLists != lists {

            lists = activeLists
        }

        if retainedLists != archivedLists {

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
    var body: some View { /* Today screen and list-selection sheets */

        NavigationStack {

            ScrollView {

                    GeometryReader { geometry in
                        Color.clear.preference(
                            key:   TodayScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("TodayScroll")).minY
                        )
                    }

                    .frame(height: 0)

                    VStack(alignment: .leading, spacing: 16) {

                    quickCaptureSection
                        .modifier(TodayPanelSurface())

                    TimelineView(.everyMinute) { context in
                        let focus = TodayListSelection.currentDayList(in: lists, date: context.date) /* Active list matching the current weekday */
                        let cards = focus?.cards.filter { !$0.isSectionDivider } ?? [] /* Actionable records in the weekday list */

                        TodayFocusSection(
                            list:            focus,
                            cards:           cards,
                            openCards:       Array(cards.filter { !$0.isTitleChecked }.prefix(3)),
                            onToggleCard:    { cardID in
                                if let focus { /* Weekday list available for navigation */

                                    onToggleCardCompletion(focus.id, cardID)
                                }
                            },
                            onOpenTodayList: {
                                focusedListID = focus?.id
                                showsTodayList = focus != nil
                            }
                        )
                        .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in
                            ensureCurrentWeekdayList()
                        }
                    }

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
                    profile:           profile,
                    lists:             lists,
                    onSave:            onSaveProfile,
                    onRemove:          onRemoveProfile,
                    onLoadExample:     {
                        guard ExampleLoadUndoStore.save(lists: lists + archivedLists, todayListID: selectedTodayListID) else {

                            return false
                        }
                        let exampleLists = SampleData.lists /* Replacement Week content from the example set */
                        archivedLists = []
                        lists = exampleLists
                        if let firstList = exampleLists.first { /* Initial Today selection after loading examples */

                            selectTodayList(firstList)
                        }
                        return true
                    },
                    onUndoExampleLoad: {
                        guard let snapshot = ExampleLoadUndoStore.load() else { /* Saved Week state preceding example loading */

                            return false
                        }
                        archivedLists = snapshot.lists.filter(\.isArchived)
                        lists = snapshot.lists.filter { !$0.isArchived }
                        ensureCurrentWeekdayList()
                        ExampleLoadUndoStore.clear()
                        return true
                    }
                )
            }

            .fullScreenCover(isPresented: $showsTodayList) {
                if let focusedList = lists.first(where: { $0.id == focusedListID }) { /* Current list associated with the focus selection */

                    TodayListDetailView(
                        lists:             $lists,
                        reservedLists:     archivedLists,
                        labelLibrary:      $labelLibrary,
                        savedCardIDs:      $savedCardIDs,
                        listID:            focusedList.id,
                        currentUserName:   profile?.displayName ?? "Justin Reina",
                        onClose:           {
                            showsTodayList = false
                        },
                        onOpenWeek:        {
                            showsTodayList = false
                            onOpenBoardList(focusedList.id)
                        },
                        onPermanentDelete: onDeleteCard
                    )
                }
            }

            .sheet(isPresented: $showsQuickNoteEditor, onDismiss: {
                if !quickComposerInitialTitle.isEmpty && quickCaptureTitle.isEmpty {

                    quickCaptureTitle = quickComposerInitialTitle
                }

                quickComposerInitialTitle = ""
                composerTemplate = nil
            }) {

                if let selectedTodayList { /* Current list receiving the Today edit */

                    QuickNoteComposer(
                        lists:         $lists,
                        initialListID: selectedTodayList.id,
                        initialTitle:  quickComposerInitialTitle,
                        template:      composerTemplate
                    ) { listID, title, description, presentation, actions in
                        onAddCard(listID, title, description, presentation, actions)
                        quickComposerInitialTitle = ""
                    }

                    .databaseActivityOverlay()
                }
            }

            .sheet(isPresented: $showsTemplates, onDismiss: {
                guard let template = pendingTemplate else { return }
                pendingTemplate = nil
                ensureCurrentWeekdayList()
                composerTemplate = template
                presentQuickNoteEditor()
            }) {
                QuickCaptureTemplatesView { template in
                    pendingTemplate = template
                    showsTemplates = false
                }
            }

            .sheet(isPresented: $showsSearch) {
                TodaySearchView(
                    lists:           lists,
                    onOpenBoardList: onOpenBoardList,
                    onOpenBoardCard: onOpenBoardCard,
                    onArchiveCard: onArchiveCard, onDeleteCard: onDeleteCard,
                    onArchiveList: onArchiveList, onDeleteList: onDeleteList
                )
            }

            .sheet(item: $selectedLabel) { label in
                TodayLabelCardsView(
                    label: label, cards: cards(using: label.id), onOpenBoardList: onOpenBoardList,
                    onArchiveCard: onArchiveCard, onDeleteCard: onDeleteCard
                )
            }
            .onAppear {
                labelLibrary = LabelLibraryStore.load()
                ensureCurrentWeekdayList()

                if !usedLabelCategories.contains(where: {

                    $0.id == selectedLabelCategoryID
                }) {

                    selectedLabelCategoryID = usedLabelCategories.first(where: { $0.id == "work" })?.id
                        ?? usedLabelCategories.first?.id
                }
            }

            .onChange(of: quickCreateRequest) { _, _ in
                openQuickNoteEditor()
            }

            .onChange(of: lists) { _, _ in
                ensureCurrentWeekdayList()
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
                            .modifier(ContentLifecycleActions(
                                title: list.title, kind: "List",
                                onArchive: { onArchiveList(list.id) }, onDelete: { onDeleteList(list.id) }
                            ))
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


    ///
    /// @fcn        TodayHomeView.quickCaptureSection
    /// @brief      Build inline card capture and full-editor access
    /// @details    Disables submission for whitespace-only titles and identifies the selected
    ///             Today destination, or prompts the user to choose one
    ///
    /// @return     (some View) title field, composer button, and quick-add controls
    /// @post       Submission and selection actions delegate to the Today capture helpers
    ///
    private var quickCaptureSection: some View { /* Inline capture controls for the selected list */

        VStack(alignment: .leading, spacing: 8) {

            Text("Quick capture")
                .font(.title2.weight(.semibold))

            HStack(spacing: 8) {

                Button {
                    showsTemplates = true
                } label: {
                    Image(systemName: "plus.square")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse templates")

                TextField("Add a card to today…", text: $quickCaptureTitle)
                    .submitLabel(.done)
                    .onSubmit(addQuickCard)
                    .accessibilityLabel("Quick capture card title")

                HStack(spacing: 0) {

                    Button(action: addQuickCard) {

                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }

                    .buttonStyle(.plain)
                    .disabled(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add card to today's list")

                    Button(action: openQuickNoteEditor) {

                        Image(systemName: "arrow.up.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }

                    .buttonStyle(.plain)
                    .accessibilityLabel("Open full card editor")
                }
            }

            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .allowsHitTesting(false)
            }

            if let selectedTodayList { /* Selected list available for quick capture */

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


/// Offers local starting points without creating or replacing stored content.
struct QuickCaptureTemplatesView: View {
    let onSelect: (QuickCaptureTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ItemPresentation?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose a starting point. Make it your own.")
                        .foregroundStyle(.secondary)
                    Picker("Template type", selection: $filter) {
                        Text("All").tag(nil as ItemPresentation?)
                        Text("Cards").tag(Optional(ItemPresentation.card))
                        Text("Notes").tag(Optional(ItemPresentation.note))
                    }
                    .pickerStyle(.segmented)

                    ForEach(QuickCaptureTemplate.allCases.filter {
                        $0 != .blankCard && $0 != .blankNote && (filter == nil || $0.presentation == filter)
                    }) { template in
                        templateButton(template)
                    }

                    Text("Or start with a blank page")
                        .font(.headline)
                    ForEach([QuickCaptureTemplate.blankCard, .blankNote].filter {
                        filter == nil || $0.presentation == filter
                    }) { template in
                        templateButton(template)
                    }
                    Text("Templates stay on this device. Nothing is added until you review the draft and tap Add.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background { TodayPaperBackground() }
            .navigationTitle("Start from a template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func templateButton(_ template: QuickCaptureTemplate) -> some View {
        Button {
            onSelect(template)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(template.title, systemImage: template.presentation == .note ? "note.text" : "rectangle")
                    .font(.headline)
                Text(template.presentation.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(template.summary)
                    .font(.subheadline)
                if !template.body.isEmpty {
                    Text(([template.body] + template.actions).joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(16)
            .modifier(TodayPanelSurface())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens an editable draft. Does not add an item yet.")
    }
}


/// Creates a card with optional supporting detail in a chosen board list.
///
/// @section    Purpose
///     Collect card text and destination before submitting through the parent callback
///
struct QuickNoteComposer: View {

    @Binding var lists: [KanbanList]                         /* Current destination lists */
    let onSave: (Int, String, String, ItemPresentation?, [String]?) -> Void
    let template: QuickCaptureTemplate?

    @Environment(\.dismiss) private var dismiss /* Close the full-size editor */

    @State private var title = ""               /* New card title */
    @State private var description = ""         /* Optional card detail */
    @State private var selectedListID: Int?      /* Destination selected in the form */
    @State private var actions: [KanbanChecklistItem]


    ///
    /// @fcn        QuickNoteComposer.init(lists:initialListID:initialTitle:template:onSave:)
    /// @brief      Configure the card composer with destinations and a submission callback
    /// @details    Seeds the optional destination without mutating lists; the form validates
    ///             that the selected identity still exists before permitting Add
    ///
    /// @param[in]  lists          Binding to available destination lists
    /// @param[in]  initialListID  Optional initially selected destination identity
    /// @param[in]  initialTitle   Existing inline title transferred into the composer
    /// @param[in]  template       Optional local starting point with explicit Card/Note presentation
    /// @param[in]  onSave         Callback receiving destination, text, and optional template presentation/actions
    /// @return     (QuickNoteComposer) initialized unsaved composer
    ///
    init(
        lists: Binding<[KanbanList]>,
        initialListID: Int?,
        initialTitle: String = "",
        template: QuickCaptureTemplate? = nil,
        onSave: @escaping (Int, String, String, ItemPresentation?, [String]?) -> Void
    ) {

        _lists = lists
        _title = State(initialValue: template?.draftTitle(capturedTitle: initialTitle) ?? initialTitle)
        _description = State(initialValue: template?.body ?? "")
        _actions = State(initialValue: (template?.actions ?? []).map { KanbanChecklistItem(title: $0) })
        _selectedListID = State(initialValue: initialListID)
        self.template = template
        self.onSave = onSave
    }


    ///
    /// @fcn        QuickNoteComposer.trimmedTitle
    /// @brief      Normalize the card title for validation and submission
    /// @details    Removes leading and trailing whitespace/newlines without altering internal text
    ///
    /// @return     (String) normalized title
    /// @post       The editable title draft remains unchanged
    ///
    private var trimmedTitle: String { /* Card title without surrounding whitespace */
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        QuickNoteComposer.body
    /// @brief      Present card text entry and destination selection
    /// @details    Disables Add until a nonempty trimmed title and an existing list resolve;
    ///             Add trims the title/Card description but preserves Note body whitespace
    ///             before submitting to the callback and dismissing the composer
    ///
    /// @return     (some View) large-sheet navigation form with Cancel and Add actions
    /// @post       Cancel discards the draft; creating/persisting a submitted card belongs to onSave
    ///
    var body: some View { /* New-card form and destination controls */

        let presentation = template?.presentation ?? lists.first(where: { $0.id == selectedListID })?.newItemPresentation ?? .card

        NavigationStack {
            Form {
                Section(presentation.title) {
                    TextField("Title", text: $title)
                    TextField("Details (optional)", text: $description, axis: .vertical)
                        .lineLimit(4...8)
                }

                if template != nil && presentation == .card {
                    Section("Actions") {
                        ForEach($actions) { $action in
                            TextField("Action", text: $action.title)
                        }
                        .onDelete { actions.remove(atOffsets: $0) }
                        Button("Add action", systemImage: "plus") {
                            actions.append(KanbanChecklistItem(title: ""))
                        }
                    }
                }

                Section("Add to") {
                    if lists.isEmpty {

                        Text("Create a list in Week before adding a card.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("List", selection: $selectedListID) {
                            Text("Choose a list").tag(nil as Int?)
                            ForEach(lists) { list in
                                Text(list.title).tag(Optional(list.id))
                            }
                        }

                        .pickerStyle(.menu)
                    }
                }
            }

            .navigationTitle("New \(presentation.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {

                    Button("Add") {
                        guard let selectedListID, /* Chosen Week destination identity */
                              lists.contains(where: { $0.id == selectedListID }) else { return }
                        let editedActions = actions.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        onSave(selectedListID, trimmedTitle, presentation == .note ? description : description.trimmingCharacters(in: .whitespacesAndNewlines), template?.presentation, template == nil ? nil : editedActions)
                        dismiss()
                    }

                    .disabled(trimmedTitle.isEmpty || selectedListID == nil || !lists.contains(where: { $0.id == selectedListID }))
                }
            }
        }

        .presentationDetents([.large])
    }
}


///
/// Creates a Note draft with a selectable personal List destination
///
/// @section    Purpose
///     Offer a roomy, writing-first draft that is committed only after explicit Save
///
private struct NewPersonalNoteComposer: View {

    let availablePersonalLists: [PersonalCollection] /* Personal List destinations offered by the composer */
    let onSave: (UUID, String, String, Date) throws -> Void /* Checked Note creation callback */

    @Environment(\.dismiss) private var dismiss /* Composer dismissal action */
    @FocusState private var focusedField: Field? /* Input currently receiving keyboard focus */
    @State private var draft: PersonalListNoteDraft /* Unsaved Note content and destination */


    ///
    /// @fcn        NewPersonalNoteComposer.init(initialCollectionID:availablePersonalLists:onSave:)
    /// @brief      Initialize a Note draft for the selected personal List
    /// @details    Captures the available destination Lists and save callback while creating draft
    ///             state with the initially selected destination
    ///
    /// @param[in]  initialCollectionID      Stable identity of the initially selected List
    /// @param[in]  availablePersonalLists  Active personal Lists offered by the composer
    /// @param[in]  onSave                  Callback that persists the completed Note draft
    ///
    /// @return     (NewPersonalNoteComposer) configured Note composer
    ///
    init(
        initialCollectionID: UUID,
        availablePersonalLists: [PersonalCollection],
        onSave: @escaping (UUID, String, String, Date) throws -> Void
    ) {

        _draft = State(initialValue: PersonalListNoteDraft(destinationID: initialCollectionID))
        self.availablePersonalLists = availablePersonalLists
        self.onSave = onSave
    }


    ///
    /// Identifies the editable field currently receiving keyboard focus
    ///
    /// @section    Purpose
    ///     Let the composer manage title and body focus independently
    ///
    private enum Field {
        case title
        case body
    }

    private var destinations: [PersonalCollection] { /* Active personal Lists accepting a new Note */
        PersonalListNoteDraft.destinations(in: availablePersonalLists)
    }


    ///
    /// @fcn        NewPersonalNoteComposer.save()
    /// @brief      Validate and submit the Note draft to its selected List
    /// @details    Dismisses the composer only after persistence succeeds; a failure is reported
    ///             while keeping the draft available for correction or retry
    ///
    /// @return     (Void) reports save failures and retains the composer when saving fails
    ///
    /// @post       Successful saves dismiss the composer; unsuccessful saves preserve draft state
    ///
    private func save() {

        do {

            try draft.save(in: availablePersonalLists, onSave: onSave)
            dismiss()
        } catch {

            DatabaseActivity.shared.report("Could not save the Note: \(error.localizedDescription) The draft remains open.")
        }
    }

    var body: some View { /* Note draft editor and destination picker */

        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Menu {
                    ForEach(destinations) { collection in
                        Button {
                            draft.destinationID = collection.id
                        } label: {
                            Label(
                                collection.title,
                                systemImage: draft.destinationID == collection.id ? "checkmark" : "folder"
                            )
                        }
                    }
                } label: {
                    Label(
                        draft.destination(in: availablePersonalLists)?.title ?? "List unavailable",
                        systemImage: "chevron.down"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .disabled(destinations.isEmpty)
                .accessibilityLabel("Note destination List")
                .accessibilityValue(draft.destination(in: availablePersonalLists)?.title ?? "List unavailable")
                .accessibilityHint("Choose the personal List where this Note will be saved")
                .accessibilityIdentifier("library.newNoteLocationPicker")

                TextField("Note title", text: $draft.title, axis: .vertical)
                    .font(.largeTitle.weight(.bold))
                    .focused($focusedField, equals: .title)
                    .accessibilityLabel("Note title")

                NoteCreationDateLabel(createdAt: draft.createdAt)
                    .accessibilityIdentifier("library.newNoteCreationDate")

                TextField("Start writing...", text: $draft.body, axis: .vertical)
                    .font(.body)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                    .focused($focusedField, equals: .body)
                    .accessibilityLabel("Note body")

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.canSave(in: availablePersonalLists))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField != nil {

                        Spacer()
                        Button("Done") { focusedField = nil }
                    }
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("library.newNoteComposer")
    }
}


///
/// Represents a local search match with navigation provenance
///
/// @section    Purpose
///     Keep the result identity and containing list available to result rows
///
struct TodaySearchResult: Identifiable {

    let listID: Int /* Board list opened when this result is selected */
    let cardID: Int? /* Stable card identity, or nil for a list result */
    let cardTitle: String /* Matching card title */
    let listTitle: String /* Containing list title */
    let detail: String /* Supporting detail shown under the title */

    ///
    /// @fcn        TodaySearchResult.id
    /// @brief      Identify a result within its containing list
    /// @details    Combines the list ID with a card ID or a list-result marker
    ///
    /// @return     (String) composite result identity
    /// @post       Result contents remain unchanged
    ///
    var id: String { "\(listID):\(cardID.map(String.init) ?? "list")" } /* Composite search-result identity */
}


///
/// Limits local search to supported kinds of Board content
///
/// @section    Purpose
///     Supply stable picker choices for the Today search screen
///
enum TodaySearchScope: String, CaseIterable, Identifiable {
    case all = "All"
    case boards = "Boards"
    case labels = "Labels"
    case users = "Users"

    ///
    /// @fcn        TodaySearchScope.id
    /// @brief      Identify a selectable local-search scope
    /// @details    Uses the display raw value for segmented-picker identity
    ///
    /// @return     (String) scope raw value
    /// @post       The selected scope is unchanged
    ///
    var id: String { rawValue } /* Stable search-scope identity */
}


///
/// Stores the device-local history of recent search terms
///
/// @section    Purpose
///     Centralize bounded, deduplicated search-history preference access
///
enum RecentSearchStore {
    private static let key = "Plenact.RecentSearches.v1" /* Versioned local search-history key */


    ///
    /// @fcn        RecentSearchStore.load(from:)
    /// @brief      Read device-local recent search terms
    /// @details    Returns the stored string array without normalization, or an empty array when
    ///             the preferences key is absent or incompatible
    ///
    /// @param[in]  defaults  Preferences store containing recent searches
    ///
    /// @return     ([String]) stored terms in most-recent-first order
    ///
    /// @post       No preferences are modified
    ///
    static func load(from defaults: UserDefaults = .standard) -> [String] {

        defaults.stringArray(forKey: key) ?? []
    }


    ///
    /// @fcn        RecentSearchStore.remember(_:in:)
    /// @brief      Move a nonempty search term to the front of local history
    /// @details    Trims surrounding whitespace, removes case-insensitive duplicates, and persists
    ///             at most ten terms; blank input returns existing history unchanged
    ///
    /// @param[in]  query     User-entered search term
    /// @param[in]  defaults  Preferences store receiving updated history
    ///
    /// @return     ([String]) resulting most-recent-first history
    ///
    /// @post       Only nonempty normalized input writes the history key
    ///
    @discardableResult
    static func remember(_ query: String, in defaults: UserDefaults = .standard) -> [String] {

        let term = query.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized query to remember */
        var searches = load(from: defaults) /* Recent queries updated in recency order */

        guard !term.isEmpty else {

            return searches
        }
        searches.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        searches.insert(term, at: 0)
        searches = Array(searches.prefix(10))
        defaults.set(searches, forKey: key)

        return searches
    }


    ///
    /// @fcn        RecentSearchStore.clear(in:)
    /// @brief      Remove device-local search history
    /// @details    Deletes only the versioned recent-searches preference key
    ///
    /// @param[in]  defaults  Preferences store to clear
    ///
    /// @return     (Void) removes the history key
    ///
    /// @post       Board content, bookmarks, and other preferences are untouched
    ///
    static func clear(in defaults: UserDefaults = .standard) {

        defaults.removeObject(forKey: key)
    }
}


///
/// Searches a supplied local Board snapshot and returns matching destinations
///
/// @section    Purpose
///     Keep query matching independent from search presentation and persistence
///
enum TodaySearchIndex {


    ///
    /// @fcn        TodaySearchIndex.results(query:scope:lists:library:)
    /// @brief      Search a supplied local Board snapshot without modifying it
    /// @details    Trims the query and uses localized-standard substring matching. Boards scope
    ///             matches list titles/subtitles; other scopes match non-divider cards by
    ///             label/category, member names, or combined card/checklist/comment content
    ///
    /// @param[in]  query    Search text; blank input yields no results
    /// @param[in]  scope    Fields and result kind to search
    /// @param[in]  lists    Snapshot to traverse in list/card order
    /// @param[in]  library  Definitions resolving assigned label and category names
    ///
    /// @return     ([TodaySearchResult]) matching list or card results with navigation provenance
    ///
    /// @post       No archive filtering, storage writes, ranking, or network requests are performed
    /// @note       Callers supply the intended list partition; archivedCards are not searched
    ///
    static func results(query: String, scope: TodaySearchScope, lists: [KanbanList], library: LabelLibrary) -> [TodaySearchResult] {

        let term = query.trimmingCharacters(in: .whitespacesAndNewlines) /* Nonblank text matched against the chosen scope */

        guard !term.isEmpty else {

            return []
        }

        if scope == .boards {

            return lists.compactMap { list in
                guard list.title.localizedStandardContains(term) || list.subtitle.localizedStandardContains(term) else {

                    return nil
                }

                return TodaySearchResult(
                    listID: list.id, cardID: nil, cardTitle: list.title, listTitle: list.title,
                    detail: "\(list.cards.filter { !$0.isSectionDivider }.count) cards"
                )
            }
        }

        return lists.flatMap { list in
            list.cards.compactMap { card -> TodaySearchResult? in
                guard !card.isSectionDivider else {

                    return nil
                }

                let checklistText = card.checklists.flatMap { [$0.title] + $0.items.map(\.title) } /* Searchable checklist and action titles */
                let commentText = card.comments.flatMap { [$0.author, $0.body] } /* Searchable discussion authors and content */
                let users = card.members.map(\.displayName) /* Searchable assignee names */
                let labels = library.labels.filter { card.labelIDs.contains($0.id) } /* Definitions of labels assigned to this card */
                let labelText = labels.flatMap { label in /* Searchable label and category names */
                    [label.name] + library.categories.filter { $0.id == label.categoryID }.map(\.name)
                }

                let searchableText: [String] /* Card fields selected by the search scope */

                switch scope {

                    case .labels: searchableText = labelText
                    case .users: searchableText = users
                    case .all:
                        searchableText = [list.title, card.word, card.descriptionOverride ?? "", card.subtitleOverride ?? ""]
                            + checklistText + commentText + users + labelText
                    case .boards: searchableText = []
                }

                guard searchableText.contains(where: {

                    $0.localizedStandardContains(term)
                }) else {

                    return nil
                }

                let detail: String /* Supporting text displayed beneath a matching card */

                switch scope {

                    case .labels: detail = labels.map(\.name).joined(separator: ", ")
                    case .users: detail = users.joined(separator: ", ")
                    default:
                        detail = [card.subtitleOverride, card.descriptionOverride].compactMap { $0 }
                            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                            ?? checklistText.first ?? ""
                }

                return TodaySearchResult(
                    listID: list.id, cardID: card.id, cardTitle: card.word, listTitle: list.title, detail: detail
                )
            }
        }
    }
}


/// Searches card content in the local Board and opens results in their existing lists.
///
/// Searches the local Board and presents matching destinations
///
/// @section    Purpose
///     Keep query, filter, recent-history, and result navigation state in one sheet
///
private struct TodaySearchView: View {

    let lists: [KanbanList] /* Current locally stored Board snapshot */
    let onOpenBoardList: (Int) -> Void /* Navigate to a result's containing list */
    let onOpenBoardCard: (Int, Int) -> Void /* Route to a Week card by list/card IDs */
    let onArchiveCard: (Int) -> Void /* Canonical Week archive */
    let onDeleteCard: (Int) -> Bool /* Confirmed canonical Week deletion result */
    let onArchiveList: (Int) -> Void /* Canonical Week list archive */
    let onDeleteList: (Int) -> Bool /* Confirmed canonical list deletion result */

    @Environment(\.dismiss) private var dismiss /* Close the search sheet */
    @FocusState private var searchFieldFocused: Bool /* Search field focus state */
    @State private var query = "" /* User-entered search text */
    @State private var scope: TodaySearchScope = .all             /* Selected local-search scope */
    @State private var recentSearches = RecentSearchStore.load()  /* Device-local recent terms */
    @State private var labelLibrary = LabelLibraryStore.load()    /* Definitions used for label matches */


    ///
    /// @fcn        TodaySearchView.results
    /// @brief      Resolve matches for the current query and selected scope
    /// @details    Delegates to the local search index using the supplied Board and label snapshots
    ///
    /// @return     ([TodaySearchResult]) current display-order matches
    /// @post       Search history and Board state are unchanged
    ///
    private var results: [TodaySearchResult] { /* Matches for the current query and scope */
        TodaySearchIndex.results(query: query, scope: scope, lists: lists, library: labelLibrary)
    }


    ///
    /// @fcn        TodaySearchView.rememberSearch()
    /// @brief      Persist the current nonblank query and refresh displayed history
    /// @details    Uses the shared recent-search store's trimming, deduplication, and ten-term
    ///             limit
    ///
    /// @return     (Void) replaces recentSearches with the store result
    ///
    /// @post       Blank queries leave stored history intact
    ///
    private func rememberSearch() {

        recentSearches = RecentSearchStore.remember(query)
    }


    ///
    /// @fcn        TodaySearchView.recentSearchList
    /// @brief      Display reusable recent terms with a clear-history action
    /// @details    Choosing a term sets the query, refreshes its history position, and releases
    ///             field focus; Clear removes both persisted and displayed history
    ///
    /// @return     (some View) plain recent-search list
    /// @post       Interactions affect search state only, not Board content
    ///
    private var recentSearchList: some View { /* Previously entered queries available for reuse */
        List {
            Section {
                ForEach(recentSearches, id: \.self) { search in
                    Button {
                        query = search
                        rememberSearch()
                        searchFieldFocused = false
                    } label: {
                        Label(search, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }

                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text("Recent searches")
                    Spacer()
                    Button("Clear") {
                        RecentSearchStore.clear()
                        recentSearches = []
                    }

                    .accessibilityLabel("Clear recent searches")
                }
            }
        }

        .listStyle(.plain)
    }


    ///
    /// @fcn        TodaySearchView.body
    /// @brief      Present local Board search, scope controls, and matching destinations
    /// @details    Switches between history, empty states, and indexed matches.
    ///             Result selection remembers the query, routes to its list/card, then dismisses
    ///
    /// @return     (some View) large-sheet search navigation surface
    /// @post       Submission, result selection, and disappearance remember nonblank queries;
    ///             search alone does not modify Board content
    ///
    var body: some View { /* Board search controls and matching destinations */

        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search", text: $query)
                        .focused($searchFieldFocused)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityLabel("Search local Board")
                        .onSubmit {
                            rememberSearch()
                            searchFieldFocused = false
                        }

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

                Picker("Search filter", selection: $scope) {
                    ForEach(TodaySearchScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }

                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 12)

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                    if recentSearches.isEmpty {

                        searchEmptyState(title: "No recent searches", detail: "")
                    } else {
                        recentSearchList
                    }
                } else if results.isEmpty {
                    searchEmptyState(title: "No results", detail: "Try another word or phrase.")
                } else {
                    List(results) { result in
                        Button {
                            rememberSearch()

                            if let cardID = result.cardID { /* Matching card identity for direct navigation */

                                onOpenBoardCard(result.listID, cardID)
                            } else {
                                onOpenBoardList(result.listID)
                            }

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
                        .modifier(ContentLifecycleActions(
                            title: result.cardTitle, kind: result.cardID == nil ? "List" : "Card",
                            onArchive: {
                                if let id = result.cardID { /* Card identity targeted by the search action */

                                    onArchiveCard(id)
                                } else {
                                    onArchiveList(result.listID)
                                }
                            },
                            onDelete:  {
                                if let id = result.cardID { /* Card identity targeted by the search action */

                                    return onDeleteCard(id)
                                }
                                return onDeleteList(result.listID)
                            }
                        ))
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
        .onDisappear { rememberSearch() }
    }


    ///
    /// @fcn        TodaySearchView.searchEmptyState(title:detail:)
    /// @brief      Render a centered search explanation
    /// @details    Uses a search symbol, heading, and multiline supporting text for empty states
    ///
    /// @param[in]  title   Empty-state heading
    /// @param[in]  detail  Supporting explanation, which may be empty
    ///
    /// @return     (some View) noninteractive empty-state content
    ///
    /// @post       Query, focus, and history remain unchanged
    ///
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


///
/// Associates a matched card with the list that contains it
///
/// @section    Purpose
///     Preserve routing context for label results
///
private struct TodayLabelCard: Identifiable {

    let card: KanbanCard /* Matched Board card */
    let listID: Int /* List opened when selected */
    let listTitle: String /* Containing list name */

    ///
    /// @fcn        TodayLabelCard.id
    /// @brief      Identify a label match by its list and card
    /// @details    Combines both numeric identities for stable matching-card rows
    ///
    /// @return     (String) composite list/card identity
    /// @post       The matched card is unchanged
    ///
    var id: String { "\(listID):\(card.id)" } /* Stable list-qualified label-result identity */
}


///
/// Represents one label and its matching cards in Today browsing
///
/// @section    Purpose
///     Keep the reusable label and its current Board matches together
///
private struct TodayLabelUsage: Identifiable {

    let label: KanbanLabel /* Reusable label definition */
    let cards: [TodayLabelCard] /* Cards currently carrying this label */

    ///
    /// @fcn        TodayLabelUsage.id
    /// @brief      Identify an applied-label usage row
    /// @details    Reuses the underlying reusable-label identity
    ///
    /// @return     (String) label identity
    /// @post       Label definitions and matches remain unchanged
    ///
    var id: String { label.id } /* Assigned label's stable identity */
}


///
/// Represents one populated label category and its applied labels
///
/// @section    Purpose
///     Provide grouped data for Today label browsing
///
private struct TodayLabelCategoryUsage: Identifiable {

    let category: KanbanLabelCategory /* Label category */
    let labels: [TodayLabelUsage] /* Labels in use in this category */

    ///
    /// @fcn        TodayLabelCategoryUsage.id
    /// @brief      Identify a populated label category
    /// @details    Reuses the underlying library-category identity
    ///
    /// @return     (String) category identity
    /// @post       Category contents remain unchanged
    ///
    var id: String { category.id } /* Assigned category's stable identity */

    ///
    /// @fcn        TodayLabelCategoryUsage.cardCount
    /// @brief      Count distinct matched cards across this category's labels
    /// @details    Deduplicates composite list/card IDs so a card with several labels counts once
    ///
    /// @return     (Int) distinct card count
    /// @post       Usage collections remain unchanged
    ///
    var cardCount: Int { Set(labels.flatMap { $0.cards.map(\.id) }).count } /* Distinct cards using labels in this category */
}


/// Opens the cards currently assigned one label.
///
/// Presents the cards currently assigned one selected label
///
/// @section    Purpose
///     Show matching cards with their list provenance and route to the containing Week list
///
private struct TodayLabelCardsView: View {

    let label: KanbanLabel /* Selected label */
    let cards: [TodayLabelCard] /* Matching Board cards */
    let onOpenBoardList: (Int) -> Void /* Navigate to the card's Board list */
    let onArchiveCard: (Int) -> Void /* Archive the canonical label match */
    let onDeleteCard: (Int) -> Bool /* Report confirmed canonical label-match removal */

    @Environment(\.dismiss) private var dismiss /* Close the label card list */


    ///
    /// @fcn        TodayLabelCardsView.body
    /// @brief      Display cards carrying the selected label
    /// @details    Shows card titles and containing-list names; selection opens the containing
    ///             Week list rather than card detail and dismisses this sheet
    ///
    /// @return     (some View) labeled card-results navigation list
    /// @post       Done only dismisses; result selection delegates navigation without changing labels
    ///
    var body: some View { /* Label-filtered card results */
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
                .modifier(ContentLifecycleActions(
                    title: result.card.word, kind: "Card",
                    onArchive: { onArchiveCard(result.card.id) }, onDelete: { onDeleteCard(result.card.id) }
                ))
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


///
/// Identifies one dated-card result in the calendar
///
/// @section    Purpose
///     Carry card and list identity with the title and matching-date marker
///
private struct CalendarCardResult: Identifiable {

    let cardID: Int /* Stable card identity */
    let title: String /* Card title shown on the selected date */
    let listID: Int /* Board list opened when selected */
    let listTitle: String /* Containing Board list */
    let dateLabel: String /* Start/due marker for this date */

    ///
    /// @fcn        CalendarCardResult.id
    /// @brief      Identify a dated-card result
    /// @details    Reuses the underlying card ID within the supplied Board snapshot
    ///
    /// @return     (Int) card identity
    /// @pre        Card IDs are unique within the displayed Board
    /// @post       Card dates and result content remain unchanged
    ///
    var id: Int { cardID } /* Stable card identity for the destination */
}


///
/// Displays a recognizable organizing space within the Library
///
/// @section    Purpose
///     Share readable collection identity and card counts across Week and personal entries
///
struct LibraryCollectionRow: View {

    let title: String      /* User-owned collection or Week Board title       */
    let subtitle: String   /* Collection kind and active-list context         */
    let icon: String       /* SF Symbol representing the organizing space     */
    let color: Color       /* Collection accent, not its only identifying cue */
    let count: Int         /* Active non-divider card count                   */

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize /* Adapt text arrangement for accessibility sizes */

    ///
    /// @fcn        LibraryCollectionRow.body
    /// @brief      Present the space's name, kind, and labeled card count
    /// @details    Uses a tinted icon and accent strip; accessibility text sizes place the count
    ///             below the title rather than compressing it into a trailing column
    /// @return     (some View) content-fitting directory row with combined accessibility text
    /// @post       Rendering does not modify the owning Board or collection
    ///
    var body: some View { /* Adaptive collection directory row with a labeled card count */

        HStack(spacing: 12) {

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 48)
                .accessibilityHidden(true)

            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            let layout = dynamicTypeSize.isAccessibilitySize /* Accessible arrangement of the collection name and count */
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))

            layout {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                .frame(maxWidth: .infinity, alignment: .leading)
                Text(count == 1 ? "1 card" : "\(count) cards")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            .frame(maxWidth: .infinity, alignment: .leading)
        }

        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}


///
/// Presents personal collections in the Library
///
/// @section    Purpose
///     Browse personal organizing spaces independently from the dedicated Week destination
///
struct BoardListsView: View {

    let retainedWeekLists: [KanbanList]                        /* Week references protect shared attachments */

    @Binding var collections: [PersonalCollection]             /* Shared device-local collections             */
    let registerListNewNote: ((() -> Void)?) -> Void /* Registers the directory's scoped Note action */
    let onOpenSaved: () -> Void                                /* Select the existing canonical Saved destination */
    var savedPersonalCardTarget: PersonalSavedCardTarget? = nil /* Saved bookmark waiting for Library navigation */
    var onClearSavedPersonalCardTarget: () -> Void = {} /* Acknowledge a handled or invalid Saved request */
    @State private var archivingCollection: PersonalCollection? /* Collection awaiting archive confirmation */
    @State private var searchText = ""                         /* Directory search query                      */
    @State private var editingCollection: PersonalCollection?  /* Collection draft being edited               */
    @State private var openedCollection: PersonalCollection?   /* Collection board presented full-screen      */
    @State private var boardTargetListID: Int?                 /* Exact collection list requested from Saved    */
    @State private var boardTargetCardID: Int?                 /* Exact collection card requested from Saved    */
    @State private var deletingCollection: PersonalCollection? /* Collection awaiting delete confirmation     */
    @State private var newNoteDraftDestination: PersonalCollection? /* Personal List selected for the presented Note draft */
    @State private var mostRecentlyOpenedListID: UUID? /* Last opened List used as the next Note destination */
    @State private var showsExamples = false                   /* Present the synthetic list chooser          */
    @State private var pendingExample: PersonalCollection?     /* Unsaved draft waiting for chooser dismissal */


    ///
    /// @fcn        BoardListsView.filteredCollections
    /// @brief      Select active personal collections matching the directory query
    /// @details    Delegates collection matching to the model and preserves collection order
    ///
    /// @return     ([PersonalCollection]) visible active collections
    /// @post       Archived collections remain stored but are not returned
    ///
    private var filteredCollections: [PersonalCollection] { /* Active directory entries matching the search */
        collections.filter { $0.isActive && $0.matches(searchText) }
    }


    ///
    /// @fcn        BoardListsView.collectionEntry(_:)
    /// @brief      Build one personal-collection row and its existing lifecycle actions
    /// @details    Keeps the Library directory view builder small as navigation callbacks grow
    /// @param[in]  collection  Active directory collection
    /// @return     (some View) collection entry with edit/archive/delete affordances
    ///
    private func collectionEntry(_ collection: PersonalCollection) -> some View {

        let collectionSubtitle = collection.kind == .board /* Kind-specific directory row summary */
            ? "Board · \(collection.lists.filter { !$0.isArchived }.count) lists"
            : "List"

        return Button {
            if collection.kind == .list {

                mostRecentlyOpenedListID = collection.id
            }

            openedCollection = collection
        } label: {
            row(
                title:    collection.title,
                subtitle: collectionSubtitle,
                icon:     collection.icon.rawValue,
                color:    collection.color.color,
                count:    collection.cardCount
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(collection.color.color.opacity(0.08))
        .accessibilityHint("Opens this personal collection")
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingCollection = collection }
            Button("Archive", systemImage: "archivebox") { archivingCollection = collection }
            Button("Delete", systemImage: "trash", role: .destructive) { deletingCollection = collection }
        }
        .accessibilityActions {
            Button("Edit Collection") { editingCollection = collection }
            Button("Archive Collection") { archivingCollection = collection }
            Button("Delete Collection") { deletingCollection = collection }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { deletingCollection = collection }
            Button("Archive") { archivingCollection = collection }
            Button("Edit") { editingCollection = collection }
                .tint(.blue)
        }
    }


    private var directoryNoteDestination: PersonalCollection? { /* Active List resolved for directory-level Note creation */

        Self.resolveNoteDestination(
            mostRecentlyOpenedListID: mostRecentlyOpenedListID,
            collections:              collections,
            visibleCollections:       filteredCollections
        )
    }


    ///
    /// @fcn        BoardListsView.resolveNoteDestination(mostRecentlyOpenedListID:collections:visibleCollections:)
    /// @brief      Select the active personal List for directory-level Note creation
    /// @details    Prefer the most recently opened active List; otherwise use the first visible List
    /// 
    /// @param[in]  mostRecentlyOpenedListID  Last opened personal List identity, if still active
    /// @param[in]  collections               Complete local collection snapshot
    /// @param[in]  visibleCollections        Active collections currently shown by Library search
    /// 
    /// @return     (PersonalCollection?) destination List, or nil when none is available
    ///
    static func resolveNoteDestination(
        mostRecentlyOpenedListID: UUID?,
        collections:             [PersonalCollection],
        visibleCollections:      [PersonalCollection]
    ) -> PersonalCollection? {

        if let mostRecentlyOpenedListID, /* Remembered personal List identity */
           let recentList = collections.first(where: { /* Remembered List still available for Note creation */
               $0.id == mostRecentlyOpenedListID && $0.kind == .list && $0.isActive
           }) {
            return recentList
        }

        return visibleCollections.first(where: { $0.kind == .list && $0.isActive })
    }


    ///
    /// @fcn        BoardListsView.openDirectoryNewNote()
    /// @brief      Start a Library-level Note draft in the resolved destination List
    /// @details    Uses the current directory destination and reports an actionable error if no
    ///             active personal List is available
    ///
    /// @return     (Void) presents the draft for the resolved List or reports why it cannot open
    ///
    private func openDirectoryNewNote() {

        guard let destination = directoryNoteDestination else { /* Available personal List for the new draft */

            DatabaseActivity.shared.report("Create a personal List before adding a Note from Library.")

            return
        }

        newNoteDraftDestination = destination
    }


    ///
    /// @fcn        BoardListsView.registerDirectoryNewNote()
    /// @brief      Register the Library-level action for creating a Note
    /// @details    Routes the directory action through the shared List Note registration helper
    ///             so its presentation behavior matches other List-scoped entry points
    ///
    /// @return     (Void) registers a callback that opens a directory Note draft
    ///
    private func registerDirectoryNewNote() {

        registerListNewNote { openDirectoryNewNote() }
    }


    ///
    /// @fcn        BoardListsView.saveCollection(_:)
    /// @brief      Insert or replace a personal collection by identity
    /// @details    Updates the shared binding; app-root observation owns persistence and error
    ///             reporting
    ///
    /// @param[in]  collection  Complete collection submitted by its settings form
    ///
    /// @return     (Void) replaces the matching entry or appends a new one
    ///
    /// @post       Other collections and the Week snapshot remain unchanged
    ///
    private func saveCollection(_ collection: PersonalCollection) {

        if let index = collections.firstIndex(where: { /* Position of the collection submitted by its form */

            $0.id == collection.id
        }) {
            collections[index] = collection
        } else {

            collections.append(collection)
        }
    }


    ///
    /// @fcn        BoardListsView.createNote(in:title:body:)
    /// @brief      Save a new Note into an active personal List before publishing it
    /// @details    Resolves the current collection by stable identity, allocates within that
    ///             collection's retained records, and leaves all content unchanged on save failure
    /// @param[in]  collectionID  Active personal List identity
    /// @param[in]  title         Validated Note title
    /// @param[in]  body          Note body preserved as entered
    /// @param[in]  createdAt     Creation time retained from the unsaved draft
    /// @return     (Void) saves and publishes one new Note record
    /// @throws     CocoaError for unavailable destinations; encoding error for failed persistence
    ///
    private func createNote(in collectionID: UUID, title: String, body: String, createdAt: Date) throws {

        guard let collectionIndex = collections.firstIndex(where: { /* Active personal List receiving the new Note */

            $0.id == collectionID && $0.kind == .list && $0.isActive
        }) else {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var updated = collections[collectionIndex] /* Destination collection receiving the new Note */

        try updated.addNote(title: title, body: body, createdAt: createdAt)

        var snapshot = collections /* Collection snapshot saved before publishing the new Note */

        snapshot[collectionIndex] = updated
        try PersonalCollectionStore.saveChecked(snapshot)
        collections = snapshot
    }


    ///
    /// @fcn        BoardListsView.moveNote(_:from:to:)
    /// @brief      Move a Note between personal Lists and persist the resulting collection snapshot
    /// @details    Delegates identity and collision handling to the collection movement operation,
    ///             then publishes the new snapshot only after checked persistence succeeds
    ///
    /// @param[in]  noteID         Identity of the Note being moved
    /// @param[in]  sourceID       Identity of the Note's current collection
    /// @param[in]  destinationID  Identity of the target personal List
    ///
    /// @return     (KanbanCard) moved Note with its resulting destination-local identity
    ///
    /// @throws     Collection movement or persistence errors without publishing an unsaved snapshot
    ///
    private func moveNote(_ noteID: Int, from sourceID: UUID, to destinationID: UUID) throws -> KanbanCard {

        var snapshot = collections /* Collection snapshot carrying both sides of the Note move */
        let moved = try PersonalCollectionNoteMovement.move( /* Note returned with its destination-local identity */
            noteID: noteID, from: sourceID, to: destinationID, in: &snapshot
        )
        try PersonalCollectionStore.saveChecked(snapshot)
        collections = snapshot

        return moved
    }


    ///
    /// @fcn        BoardListsView.persistMovedNoteCollection(_:failureMessage:)
    /// @brief      Persist and publish a changed personal collection
    /// @details    Replaces the matching collection in a temporary snapshot and updates the shared
    ///             collection binding only after checked storage succeeds
    ///
    /// @param[in]  updated         Collection value to persist
    /// @param[in]  failureMessage  Operation-specific message prefix for reported errors
    ///
    /// @return     (Bool) true when storage and publication succeed; otherwise false
    ///
    /// @post       A failed save leaves the published collection snapshot unchanged
    ///
    private func persistMovedNoteCollection(
        _ updated: PersonalCollection,
        failureMessage: String
    ) -> Bool {

        guard let index = collections.firstIndex(where: { $0.id == updated.id }) else { /* Existing collection to replace after checked persistence */

            DatabaseActivity.shared.report("\(failureMessage) The collection is no longer available.")
            return false
        }

        var snapshot = collections /* Collection snapshot saved before publishing moved-Note changes */

        snapshot[index] = updated

        do {

            try PersonalCollectionStore.saveChecked(snapshot)
            collections = snapshot
            return true
        } catch {

            DatabaseActivity.shared.report("\(failureMessage) \(error.localizedDescription)")
            return false
        }
    }


    ///
    /// @fcn        BoardListsView.updateMovedNote(_:in:)
    /// @brief      Replace an existing Note in its active personal List
    /// @details    Resolves the collection and non-archived record by stable identity, then routes
    ///             the updated value through checked collection persistence
    ///
    /// @param[in]  note          Edited Note value to store
    /// @param[in]  collectionID  Identity of the Note's owning collection
    ///
    /// @return     (Bool) true when the Note update is persisted; otherwise false
    ///
    /// @post       Missing or archived records are not recreated
    ///
    private func updateMovedNote(_ note: KanbanCard, in collectionID: UUID) -> Bool {

        guard let index = collections.firstIndex(where: { $0.id == collectionID && $0.isActive }) else { /* Active collection owning the moved Note */

            DatabaseActivity.shared.report("Could not save the Note edit. Its destination List is unavailable.")
            return false
        }

        var updated = collections[index] /* Owning collection receiving the edited Note */

        guard let listIndex = updated.lists.firstIndex(where: { /* Active column containing the moved Note */

            !$0.isArchived && $0.cards.contains(where: { $0.id == note.id && !$0.isSectionDivider })
        }), let cardIndex = updated.lists[listIndex].cards.firstIndex(where: { /* Position of the moved Note to replace */
            $0.id == note.id && !$0.isSectionDivider
        }) else {

            DatabaseActivity.shared.report("Could not save the item edit. It is no longer in its destination List.")
            return false
        }

        updated.lists[listIndex].cards[cardIndex] = note
        return persistMovedNoteCollection(updated, failureMessage: "Could not save the Note edit.")
    }


    ///
    /// @fcn        BoardListsView.archiveMovedNote(_:in:)
    /// @brief      Archive an existing Note within its personal List
    /// @details    Resolves the active collection and non-archived containing List, marks the Note
    ///             archived, and persists the updated collection
    ///
    /// @param[in]  note          Note whose retained record should be archived
    /// @param[in]  collectionID  Identity of the Note's owning collection
    ///
    /// @return     (Bool) true when the archive state is persisted; otherwise false
    ///
    /// @post       The Note remains retained in the collection archive
    ///
    private func archiveMovedNote(_ note: KanbanCard, in collectionID: UUID) -> Bool {

        guard let index = collections.firstIndex(where: { $0.id == collectionID && $0.isActive }) else { /* Active collection owning the Note to archive */

            DatabaseActivity.shared.report("Could not archive the Note. Its destination List is unavailable.")
            return false
        }

        var updated = collections[index] /* Owning collection receiving the Note archive */

        guard let listIndex = updated.lists.firstIndex(where: { /* Active column containing the Note to archive */

            !$0.isArchived && $0.cards.contains(where: { $0.id == note.id && !$0.isSectionDivider })
        }) else {

            DatabaseActivity.shared.report("Could not archive the item. It is no longer in its destination List.")
            return false
        }

        updated.lists[listIndex].archiveCard(id: note.id)
        return persistMovedNoteCollection(updated, failureMessage: "Could not archive the Note.")
    }


    ///
    /// @fcn        BoardListsView.deleteMovedNote(_:in:)
    /// @brief      Delete a Note from its personal List after checked persistence
    /// @details    Removes the matching record and bookmark, persists the collection, then removes
    ///             attachment files only when no retained Board references them
    ///
    /// @param[in]  note          Note whose record should be removed
    /// @param[in]  collectionID  Identity of the Note's owning collection
    ///
    /// @return     (Bool) true when deletion is persisted; otherwise false
    ///
    /// @post       Referenced attachment files are retained across all known local snapshots
    ///
    private func deleteMovedNote(_ note: KanbanCard, in collectionID: UUID) -> Bool {

        guard let index = collections.firstIndex(where: { $0.id == collectionID && $0.isActive }) else { /* Active collection owning the Note to delete */

            DatabaseActivity.shared.report("Could not delete the Note. Its destination List is unavailable.")
            return false
        }

        var updated = collections[index] /* Owning collection receiving the Note deletion */

        guard let listIndex = updated.lists.firstIndex(where: { /* Active column containing the Note to delete */

            !$0.isArchived && $0.cards.contains(where: { $0.id == note.id && !$0.isSectionDivider })
        }) else {

            DatabaseActivity.shared.report("Could not delete the item. It is no longer in its destination List.")
            return false
        }

        updated.lists[listIndex].cards.removeAll { $0.id == note.id }
        updated.savedCardIDs.remove(note.id)
        guard persistMovedNoteCollection(updated, failureMessage: "Could not delete the Note.") else {

            return false
        }

        let retainedLists = collections.flatMap(\.lists) /* Retained lists considered before deleting Note media */
            + retainedWeekLists
            + (ExampleLoadUndoStore.load()?.lists ?? [])
        let retainedFileNames = Set(retainedLists.flatMap(\.allCards) /* Attachment filenames still referenced by retained records */
            .flatMap { $0.attachments ?? [] }
            .compactMap(\.fileName))
        CardAttachmentStore.removeUnreferencedFiles(keeping: retainedFileNames)

        return true
    }


    ///
    /// @fcn        BoardListsView.setMovedNoteBookmark(_:in:isSaved:)
    /// @brief      Set the saved state of a Note in its personal List
    /// @details    Confirms the Note still belongs to an active collection before changing its
    ///             bookmark, then persists the updated collection snapshot
    ///
    /// @param[in]  noteID        Identity of the Note to update
    /// @param[in]  collectionID  Identity of the Note's owning collection
    /// @param[in]  isSaved       True to bookmark the Note; false to remove its bookmark
    ///
    /// @return     (Bool) true when the bookmark update is persisted; otherwise false
    ///
    private func setMovedNoteBookmark(_ noteID: Int, in collectionID: UUID, isSaved: Bool) -> Bool {

        guard let index = collections.firstIndex(where: { $0.id == collectionID && $0.isActive }), /* Active collection owning the Note bookmark */
              collections[index].lists.contains(where: {
                  !$0.isArchived && $0.cards.contains(where: { $0.id == noteID && !$0.isSectionDivider })
              }) else {

            DatabaseActivity.shared.report("Could not update the item bookmark. The item is no longer available.")
            return false
        }

        var updated = collections[index] /* Owning collection receiving the bookmark change */

        if isSaved {

            updated.savedCardIDs.insert(noteID)
        } else {

            updated.savedCardIDs.remove(noteID)
        }

        return persistMovedNoteCollection(updated, failureMessage: "Could not update the Note bookmark.")
    }


    ///
    /// @fcn        BoardListsView.presentedCollectionBoard(_:)
    /// @brief      Wire a personal collection to its live directory records
    /// @details    Supplies retained-attachment protection, save-before-delete/note callbacks,
    ///             and the scoped bottom-toolbar Note action
    /// @param[in]  collection  Full-screen collection snapshot selected from the Library
    /// @return     (some View) collection Board wired to canonical collection persistence
    ///
    private func presentedCollectionBoard(_ collection: PersonalCollection) -> some View {

        let otherCollectionLists = collections /* Lists outside the presented collection protecting shared media */
            .filter { $0.id != collection.id }
            .flatMap(\.lists)
        let retainedLists = retainedWeekLists /* External and undo snapshots protecting referenced attachments */
            + otherCollectionLists
            + (ExampleLoadUndoStore.load()?.lists ?? [])
        let activePersonalLists = collections.filter { $0.kind == .list && $0.isActive } /* Available Note destinations across the directory */

        return PersonalCollectionBoardView(
            collection:                collectionBinding(for: collection),
            boardTargetListID:         $boardTargetListID,
            boardTargetCardID:         $boardTargetCardID,
            retainedLists:             retainedLists,
            availablePersonalLists:    activePersonalLists,
            onArchive:                 {
                collections = try PersonalCollectionStore.archiveCollection(id: collection.id, in: collections)
            },
            onDelete:                  {
                let updated = collections.filter { $0.id != collection.id } /* Directory snapshot excluding the deleted collection */
                try PersonalCollectionStore.saveChecked(updated)
                collections = updated
            },
            onCommitDeletion:          { updated in
                guard let index = collections.firstIndex(where: { $0.id == updated.id }) else { /* Position of the collection with confirmed removals */
                    throw CocoaError(.validationMissingMandatoryProperty)
                }
                var snapshot = collections /* Directory snapshot saved before publishing removals */
                snapshot[index] = updated
                try PersonalCollectionStore.saveChecked(snapshot)
                collections = snapshot
            },
            onCreateNote:              { destinationID, title, body, createdAt in
                try createNote(in: destinationID, title: title, body: body, createdAt: createdAt)
            },
            onMoveNote:                { note, sourceID, destinationID in
                try moveNote(note.id, from: sourceID, to: destinationID)
            },
            onUpdateMovedNote:         { id, note in updateMovedNote(note, in: id) },
            onArchiveMovedNote:        { id, note in archiveMovedNote(note, in: id) },
            onDeleteMovedNote:         { id, note in deleteMovedNote(note, in: id) },
            onToggleMovedNoteBookmark: { id, noteID, isSaved in
                setMovedNoteBookmark(noteID, in: id, isSaved: isSaved)
            },
            registerNewNote:           registerListNewNote
        )
    }


    ///
    /// @fcn        BoardListsView.collectionBinding(for:)
    /// @brief      Resolve a presented collection back to shared directory state
    /// @details    Getter finds the current entry or returns the supplied snapshot; setter replaces
    ///             an existing entry only and does not recreate removed collections
    ///
    /// @param[in]  collection  Presented snapshot providing identity and getter fallback
    ///
    /// @return     (Binding<PersonalCollection>) live getter/setter for the shared collection array
    ///
    /// @post       Constructing the binding does not modify or persist any collection
    ///
    private func collectionBinding(for collection: PersonalCollection) -> Binding<PersonalCollection> {

        Binding(
            get: { collections.first(where: { $0.id == collection.id }) ?? collection },
            set: { updated in
                guard let index = collections.firstIndex(where: { /* Current position of the bound collection */

                    $0.id == updated.id
                }) else {

                    return
                }
                collections[index] = updated
            }
        )
    }


    ///
    /// @fcn        BoardListsView.row(title:subtitle:icon:color:count:)
    /// @brief      Render a consistent collection-directory row
    /// @details    Combines a collection accent, readable title/type, and an explicitly labeled
    ///             count; the caller supplies navigation or editing interaction
    ///
    /// @param[in]  title     Primary collection name
    /// @param[in]  subtitle  Supporting type or list-count text
    /// @param[in]  icon      SF Symbol name
    /// @param[in]  color     Icon tint and background accent
    /// @param[in]  count     Card count displayed at the trailing edge
    ///
    /// @return     (some View) full-row hit-test content
    ///
    /// @post       Rendering does not change collection state
    ///
    private func row(title: String, subtitle: String, icon: String, color: Color, count: Int) -> some View {

        LibraryCollectionRow(title: title, subtitle: subtitle, icon: icon, color: color, count: count)
    }


    ///
    /// @fcn        BoardListsView.createMenu
    /// @brief      Offer blank and starter personal collections
    /// @details    New List, New Board, and named starters seed an editable collection draft
    ///             with the appropriate kind/icon; nothing is inserted until the form saves
    ///
    /// @return     (some View) accessible toolbar creation menu
    /// @post       Choosing an entry sets editingCollection without changing stored collections
    ///
    private var createMenu: some View { /* Directory actions for creating Lists and Boards */
        Menu {

            Button("New List", systemImage: "list.bullet") {
                editingCollection = PersonalCollection(title: "", kind: .list)
            }

            Button("New Board", systemImage: "rectangle.3.group") {
                editingCollection = PersonalCollection(title: "", kind: .board, icon: .project)
            }

            Button("Examples", systemImage: "plus") {
                showsExamples = true
            }

            Menu("Starter Lists") {
                ForEach(["On the table", "In the queue", "Upcoming", "Shopping", "Reminders"], id: \.self) { title in
                    Button(title) {
                        editingCollection = PersonalCollection(
                            title: title, kind: .list,
                            icon: title == "Shopping" ? .shopping : (title == "Reminders" ? .reminders : .tasks)
                        )
                    }
                }
            }

            Menu("Starter Boards") {
                ForEach(["General Notes", "Girlfriend Important Details", "New Project Notes"], id: \.self) { title in
                    Button(title) {
                        editingCollection = PersonalCollection(
                            title: title, kind: .board,
                            icon: title == "Girlfriend Important Details" ? .heart : .notes
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
        }

        .accessibilityLabel("Create list or board")
    }


    ///
    /// @fcn        BoardListsView.body
    /// @brief      Present the personal-collection directory without duplicate Week access
    /// @details    Supports search, create/edit, confirmed deletion, and unfiltered active-collection
    ///             reordering. Presented boards retain attachment references from other boards and undo state
    ///
    /// @return     (some View) searchable directory with settings and board presentations
    /// @post       Directory edits update the shared collections binding; archival uses save-first
    ///             persistence and does not alter Week. Archived collections remain outside active rows
    ///
    var body: some View { /* Personal collection directory and management sheets */

        NavigationStack {

            List {

                Section {
                    Button(action: onOpenSaved) {
                        HStack(spacing: 12) {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Saved")
                                    .font(.headline)
                                Text("Bookmarked items and archived collections")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 68)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.openSaved")
                    .accessibilityHint("Switches to the Saved tab")
                }

                Section {

                    ForEach(filteredCollections) { collection in

                        collectionEntry(collection)
                    }
                    .onMove { source, destination in
                        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {

                            return
                        }

                        var active = collections.filter(\.isActive) /* Active directory entries reordered by the user */

                        active.move(fromOffsets: source, toOffset: destination)
                        collections = active + collections.filter { !$0.isActive }
                    }

                    if filteredCollections.isEmpty {

                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Your own organizing spaces" : "No matching collections",
                                systemImage: "books.vertical"
                            )
                            .font(.headline)
                            Text(
                                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Keep ideas, projects, and everyday plans together in personal lists and boards."
                                    : "Try another collection name or card title."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) { collectionCreationButtons }
                                    VStack(alignment: .leading, spacing: 12) { collectionCreationButtons }
                                }
                            }
                        }

                        .padding(.vertical, 12)
                    }
                } header: {
                    Text("Personal collections")
                } footer: {
                    Text("Lists organize cards. Boards bring several lists together. Archived boards are in Saved.")
                }
            }

            .scrollContentBackground(.hidden)
            .background { TodayPaperBackground() }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Find a collection or card")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton().disabled(!searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) { createMenu }
            }

            .sheet(item: $editingCollection) { collection in
                PersonalCollectionSettingsView(
                    collection: collection,
                    isNew:      !collections.contains(where: { $0.id == collection.id }),
                    onSave:     saveCollection
                )
            }

            .sheet(isPresented: $showsExamples, onDismiss: {
                if let pendingExample { /* Example selected for collection creation */

                    editingCollection = pendingExample
                    self.pendingExample = nil
                }
            }) {
                PersonalListExamplesView { example in
                    pendingExample = example.makeCollection(existingTitles: collections.map(\.title))
                    showsExamples = false
                }
            }

            .sheet(item: $newNoteDraftDestination) { collection in
                NewPersonalNoteComposer(
                    initialCollectionID:    collection.id,
                    availablePersonalLists: collections
                ) { destinationID, title, body, createdAt in
                    try createNote(in: destinationID, title: title, body: body, createdAt: createdAt)
                }
                .databaseActivityOverlay()
            }

            .fullScreenCover(item: $openedCollection, onDismiss: registerDirectoryNewNote) { collection in
                presentedCollectionBoard(collection)
            }

            .alert("Delete collection?", isPresented: Binding(
                get: { deletingCollection != nil },
                set: { if !$0 { deletingCollection = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let deletingCollection { /* Collection awaiting permanent deletion */

                        do {

                            let updated = collections.filter { $0.id != deletingCollection.id } /* Directory snapshot excluding the confirmed deletion */

                            try PersonalCollectionStore.saveChecked(updated)
                            collections = updated
                        } catch {
                            DatabaseActivity.shared.report("Could not delete the collection: \(error.localizedDescription) It has been retained.")
                        }
                    }

                    deletingCollection = nil
                }

                Button("Cancel", role: .cancel) { deletingCollection = nil }
            } message: {
                Text("Permanently deletes this collection, all active and archived lists/cards, and its bookmarks. This cannot be undone. Your Week board is not affected.")
            }

            .confirmationDialog("Archive \(archivingCollection?.title ?? "collection")?", isPresented: Binding(
                get: { archivingCollection != nil }, set: { if !$0 { archivingCollection = nil } }
            ), titleVisibility: .visible) {
                Button("Archive") {
                    if let archivingCollection { /* Collection awaiting archive confirmation */

                        do {

                            collections = try PersonalCollectionStore.archiveCollection(id: archivingCollection.id, in: collections)
                        } catch {
                            DatabaseActivity.shared.report("Could not archive the collection: \(error.localizedDescription)")
                        }
                    }

                    archivingCollection = nil
                }

                Button("Cancel", role: .cancel) { archivingCollection = nil }
            } message: {
                Text("Keeps all content on this device. Restore it from Saved.")
            }

        }
        .onAppear {
            registerDirectoryNewNote()
            if let savedPersonalCardTarget {

                openSavedPersonalCard(savedPersonalCardTarget)
            }
        }
        .onChange(of: savedPersonalCardTarget) { _, target in
            guard let target else {

                return
            }

            openSavedPersonalCard(target)
        }
    }


    ///
    /// @fcn        BoardListsView.openSavedPersonalCard(_:)
    /// @brief      Open a bookmarked personal record in its canonical collection
    /// @details    Resolves against current active collection/list/card data and forwards the
    ///             collection-local Board targets before presenting the full-screen Board
    ///
    /// @param[in]  target  Collection/list/card identity selected from Saved
    /// @return     (Void) presents the owning collection and consumes the Saved request
    ///
    /// @post       No record is copied, moved, or unbookmarked
    ///
    private func openSavedPersonalCard(_ target: PersonalSavedCardTarget) {

        guard let collection = collections.first(where: { $0.id == target.collectionID && $0.isActive }),
              let list = collection.lists.first(where: { $0.id == target.listID && !$0.isArchived }),
              list.cards.contains(where: { $0.id == target.cardID && !$0.isSectionDivider }) else {

            onClearSavedPersonalCardTarget()
            DatabaseActivity.shared.report("This saved item is no longer available in its collection.")
            return
        }

        boardTargetListID = target.listID
        boardTargetCardID = target.cardID
        mostRecentlyOpenedListID = collection.kind == .list ? collection.id : nil
        openedCollection = collection
        onClearSavedPersonalCardTarget()
    }


    ///
    /// @fcn        BoardListsView.collectionCreationButtons
    /// @brief      Offer blank-list creation alongside optional examples
    /// @details    Shared content fits horizontally or vertically without changing creation semantics
    /// @return     (some View) two independently accessible creation buttons
    /// @post       Actions present an unsaved form or chooser; collections remain unchanged
    ///
    private var collectionCreationButtons: some View { /* List and Board creation shortcuts */

        Group {
            Button("Create a list", systemImage: "plus") {
                editingCollection = PersonalCollection(title: "", kind: .list)
            }

            Button("Examples", systemImage: "plus") {
                showsExamples = true
            }
        }

        .buttonStyle(.bordered)
    }
}


///
/// Presents optional synthetic list examples with an inspectable card preview
///
/// @section    Purpose
///     Let people choose a draft without writing data or replacing their existing work
///
private struct PersonalListExamplesView: View {

    let onSelect: (PersonalListExample) -> Void /* Delegate draft creation to the owning Library */
    @Environment(\.dismiss) private var dismiss /* Cancel the chooser without selecting */


    ///
    /// @fcn        PersonalListExamplesView.body
    /// @brief      Show all six organizing examples and their card titles
    /// @details    Expanding a preview is read-only; Use example opens the save-before-adding flow
    /// @return     (some View) scrollable chooser with an explicit Cancel action
    ///
    var body: some View { /* Personal List example chooser with expandable card previews */
        NavigationStack {
            List {
                Section {
                    Text("Synthetic examples to explore and make your own. Selecting one opens a draft; only Save adds a new personal list. Your Week Board and existing collections stay unchanged.")
                        .foregroundStyle(.secondary)
                }

                ForEach(PersonalListExample.allCases) { example in
                    Section(example.rawValue) {
                        Text(example.summary)
                        DisclosureGroup("Preview \(example.cards.count) example cards") {
                            ForEach(example.cards.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 4) {
                                    if index == 0, let illustration = example.coverIllustration { /* Example's featured offline cover image */

                                        CardCoverPreview(attachment: KanbanAttachment(
                                            mediaKind: .photo, exampleImage: illustration
                                        ))
                                        Text("Optional example cover")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(example.cards[index].0).font(.headline)
                                    Text(example.cards[index].1)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                .padding(.vertical, 4)
                            }
                        }

                        Button("Use \(example.rawValue)", systemImage: "plus") {
                            onSelect(example)
                        }
                    }
                }
            }

            .navigationTitle("Example Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}


///
/// Presents a personal collection through the shared Board interface
///
/// @section    Purpose
///     Reuse Board behavior while binding edits and archive actions to the collection
///
struct PersonalCollectionBoardView: View {

    @Binding var collection: PersonalCollection     /* Live collection shown by the shared Board view */
    @Binding var boardTargetListID: Int? /* Collection-local list requested from Saved */
    @Binding var boardTargetCardID: Int? /* Collection-local card requested from Saved */
    let retainedLists: [KanbanList]                 /* Other lists retaining possible attachments */
    let availablePersonalLists: [PersonalCollection] /* Personal Lists offered as Note destinations */
    let onArchive: () throws -> Void                /* Persist archival of this collection */
    let onDelete: () throws -> Void /* Persist permanent removal of this collection */
    let onCommitDeletion: (PersonalCollection) throws -> Void /* Save nested deletion against current shared state */
    let onCreateNote: (UUID, String, String, Date) throws -> Void /* Checked creation callback for a destination List */
    let onMoveNote: (KanbanCard, UUID, UUID) throws -> KanbanCard /* Checked movement callback returning the relocated Note */
    let onUpdateMovedNote: (UUID, KanbanCard) -> Bool /* Persists edits in the Note's current collection */
    let onArchiveMovedNote: (UUID, KanbanCard) -> Bool /* Archives the Note in its current collection */
    let onDeleteMovedNote: (UUID, KanbanCard) -> Bool /* Permanently removes the Note from its current collection */
    let onToggleMovedNoteBookmark: (UUID, Int, Bool) -> Bool /* Persists the Note's collection-local saved state */
    let registerNewNote: ((() -> Void)?) -> Void /* Registers or clears the presented List's Note action */
    @Environment(\.dismiss) private var dismiss     /* Close the collection board */
    @State private var showsNewNoteComposer = false /* Presentation state of the List-scoped Note draft */

    ///
    /// @fcn        PersonalCollectionBoardView.body
    /// @brief      Adapt a personal collection to the shared Board surface
    /// @details    Supplies active/archive list bindings, collection bookmarks, and retained attachment
    ///             references. Full boards allow list creation; single-list collections fill the
    ///             Standard viewport while Overview retains the shared compact column width
    ///
    /// @return     (some View) collection-backed Board with database activity feedback
    /// @post       Successful archive dismisses after onArchive returns; failure reports an error
    ///             and keeps the Board open
    ///
    var body: some View { /* Collection Board wired to canonical persistence callbacks */
        ContentView(
            lists:                     $collection.lists.activeLists,
            archivedLists:             $collection.lists.archivedLists,
            boardTargetListID:         $boardTargetListID,
            boardTargetCardID:         $boardTargetCardID,
            savedCardIDs:              $collection.savedCardIDs,
            boardTitle:                collection.title,
            boardSubtitle:             collection.kind.rawValue,
            allowsAddingLists:         collection.kind == .board,
            fillsAvailableListWidth:   collection.kind == .list,
            onClose:                   { dismiss() },
            onArchiveBoard:            {
                do {

                    try onArchive()
                    dismiss()
                } catch {
                    DatabaseActivity.shared.report("Could not archive the board: \(error.localizedDescription) The board has not been removed.")
                }
            },
            onDeleteBoard:             {
                do {

                    try onDelete()
                    dismiss()
                } catch {
                    DatabaseActivity.shared.report("Could not delete the collection: \(error.localizedDescription) It has been retained.")
                }
            },
            deleteBoardTitle:          collection.kind == .board ? "Delete Board" : "Delete Collection",
            onCommitDeletion:          { lists, bookmarks in
                var updated = collection /* Collection snapshot receiving Board removals */
                updated.lists = lists
                updated.savedCardIDs = bookmarks
                try onCommitDeletion(updated)
            },
            onListsChanged:            { updatedLists in
                if collection.kind == .list, let list = updatedLists.first {
                    collection.title = list.title
                }
            },
            retainedAttachmentLists:   { retainedLists },
            personalCollectionID:      collection.id,
            availablePersonalLists:    availablePersonalLists,
            onMoveNoteToPersonalList:  { note, sourceID, destinationID in
                do {
                    return try onMoveNote(note, sourceID, destinationID)
                } catch {
                    DatabaseActivity.shared.report("Could not move the Note: \(error.localizedDescription) Its content remains in the current List.")
                    return nil
                }
            },
            onUpdateMovedNote:         onUpdateMovedNote,
            onArchiveMovedNote:        onArchiveMovedNote,
            onDeleteMovedNote:         onDeleteMovedNote,
            onToggleMovedNoteBookmark: onToggleMovedNoteBookmark
        )
        .databaseActivityOverlay()
        .onAppear {
            if collection.kind == .list {

                var noteCollection = collection /* Personal List receiving its Note-only creation default */

                noteCollection.useNoteDefaultsForPersonalLists()

                if noteCollection != collection {

                    collection = noteCollection
                }

                registerNewNote { showsNewNoteComposer = true }
            }
        }
        .onDisappear {
            registerNewNote(nil)
        }
        .sheet(isPresented: $showsNewNoteComposer) {
            NewPersonalNoteComposer(
                initialCollectionID:    collection.id,
                availablePersonalLists: availablePersonalLists,
                onSave:                 onCreateNote
            )
            .databaseActivityOverlay()
        }
    }
}


///
/// Edits a local personal collection using an isolated draft
///
/// @section    Purpose
///     Apply collection naming and appearance only after explicit Save
///
private struct PersonalCollectionSettingsView: View {

    let isNew: Bool                               /* Whether this form creates a new collection */
    let onSave: (PersonalCollection) -> Void      /* Submit the complete collection draft */
    @State private var draft: PersonalCollection  /* Isolated editable collection copy */
    @Environment(\.dismiss) private var dismiss   /* Close the settings sheet */


    ///
    /// @fcn        PersonalCollectionSettingsView.init(collection:isNew:onSave:)
    /// @brief      Seed an isolated personal-collection settings draft
    /// @details    Copies the supplied value into local State so Cancel does not submit partial edits
    ///
    /// @param[in]  collection  Existing collection or newly created starter draft
    /// @param[in]  isNew       Whether to display a creation heading
    /// @param[in]  onSave      Callback receiving the complete renamed draft
    /// @return     (PersonalCollectionSettingsView) initialized settings form
    /// @post       The source collection remains unchanged until onSave is invoked
    ///
    init(collection: PersonalCollection, isNew: Bool, onSave: @escaping (PersonalCollection) -> Void) {

        _draft = State(initialValue: collection)
        self.isNew = isNew
        self.onSave = onSave
    }


    ///
    /// @fcn        PersonalCollectionSettingsView.trimmedTitle
    /// @brief      Normalize the collection name for validation and save
    /// @details    Trims outer whitespace/newlines without mutating the draft text
    ///
    /// @return     (String) normalized collection title
    /// @post       The draft remains unchanged
    ///
    private var trimmedTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) } /* Validated collection name without surrounding whitespace */


    ///
    /// @fcn        PersonalCollectionSettingsView.save()
    /// @brief      Submit the normalized collection draft and close settings
    /// @details    Uses the model's rename helper to keep single-list collection naming consistent,
    ///             then calls the parent submission callback before dismissal
    ///
    /// @return     (Void) updates the draft, submits it, and dismisses the form
    ///
    /// @pre        The form has verified trimmedTitle is nonempty
    /// @post       Persistence and save-error reporting remain the parent's responsibility
    ///
    private func save() {

        draft.rename(to: trimmedTitle)
        onSave(draft)
        dismiss()
    }


    ///
    /// @fcn        PersonalCollectionSettingsView.body
    /// @brief      Present collection name, icon, and color editing
    /// @details    Displays a fixed collection type and distinguishes create/edit headings;
    ///             whitespace-only names disable Save, while Cancel dismisses without submission
    ///
    /// @return     (some View) navigation form with draft-bound settings and toolbar actions
    /// @post       Changes remain local until Save invokes the parent callback
    ///
    var body: some View { /* Collection name, kind, icon, and color form */
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.title)
                    LabeledContent("Type", value: draft.kind.rawValue)
                    Picker("Icon", selection: $draft.icon) {
                        ForEach(PersonalCollectionIcon.allCases, id: \.self) { icon in
                            Label(icon.title, systemImage: icon.rawValue).tag(icon)
                        }
                    }

                    .pickerStyle(.menu)
                    Picker("Color", selection: $draft.color) {
                        ForEach([
                            ("Teal", ProfileColor.teal), ("Blue", .blue), ("Green", .green),
                            ("Orange", .orange), ("Coral", .coral), ("Graphite", .graphite)
                        ], id: \.0) { name, color in
                            HStack {
                                Circle().fill(color.color).frame(width: 16, height: 16)
                                Text(name)
                            }

                            .tag(color)
                        }
                    }

                    .pickerStyle(.menu)
                }
                
                Section("New item defaults") {
                    if draft.kind == .list {

                        Text("New items in personal Lists are Notes. Existing Cards and Notes keep their current presentation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {

                        ForEach($draft.lists) { $list in
                            Picker(list.title, selection: $list.newItemPresentation) {
                                ForEach(ItemPresentation.allCases) { presentation in
                                    Text(presentation.title).tag(presentation)
                                }
                            }
                        }

                        Text("Applies only to new items. Existing Notes and Cards keep their own presentation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if isNew && draft.cardCount > 0 {

                    Section("Cards included") {
                        Text("These example cards will be added only when you save this new personal list.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(draft.lists.flatMap(\.cards)) { card in
                            if let cover = card.coverAttachment { /* Featured attachment displayed above the card preview */

                                CardCoverPreview(attachment: cover, height: 96)
                            }

                            Text(card.word)
                        }
                    }
                }
            }

            .navigationTitle(isNew ? "New \(draft.kind.rawValue)" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save).disabled(trimmedTitle.isEmpty)
                }
            }
        }

        .presentationDetents([.medium, .large])
    }
}


///
/// Provides display names for the personal-collection icon choices
///
/// @section    Purpose
///     Keep picker labels alongside the collection icon type
///
extension PersonalCollectionIcon {

    ///
    /// @fcn        PersonalCollectionIcon.title
    /// @brief      Translate a collection icon into its display name
    /// @details    Maps each icon case to a readable name for the settings picker
    ///
    /// @return     (String) icon display title
    /// @post       No collection state is changed
    ///
    var title: String { /* User-facing name of the collection icon */
        switch self {

            case .notes: "Notes"
            case .tasks: "Tasks"
            case .shopping: "Shopping"
            case .reminders: "Reminders"
            case .project: "Project"
            case .home: "Home"
            case .heart: "Heart"
            case .upcoming: "Upcoming"
        }
    }
}


///
/// Browses card start and due dates using the user's local calendar
///
/// @section    Purpose
///     Show dated cards by month and route selections to their exact Board records
///
struct TodayCalendarView: View {

    let lists: [KanbanList] /* Current Board snapshot */
    let onArchiveCard: (Int) -> Void /* Canonical archive callback */
    let onDeleteCard: (Int) -> Bool /* Confirmed deletion result */
    let onOpenBoardCard: (Int, Int) -> Void /* Navigate using containing list and card identities */

    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now /* Visible month */
    @State private var selectedDate = Calendar.current.startOfDay(for: .now) /* Selected local day */

    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7) /* Seven localized calendar columns */

    ///
    /// @fcn        TodayCalendarView.weekdaySymbols
    /// @brief      Order localized weekday headings for the user's calendar
    /// @details    Rotates very-short standalone symbols so the configured first weekday leads
    ///
    /// @return     ([String]) weekday headings in calendar-column order
    /// @post       Calendar preferences are unchanged
    ///
    private var weekdaySymbols: [String] { /* Locale weekday headings ordered by the calendar */
        let calendar = Calendar.current /* User's local calendar */
        let symbols = calendar.veryShortStandaloneWeekdaySymbols /* Locale weekday labels */

        return (0..<symbols.count).map { symbols[(calendar.firstWeekday - 1 + $0) % symbols.count] }
    }

    ///
    /// @fcn        TodayCalendarView.monthDays
    /// @brief      Build complete calendar-grid rows for the displayed month
    /// @details    Uses the current calendar's month boundaries and first weekday,
    ///             adding nil placeholders before and after dates to complete seven-column rows
    ///
    /// @return     ([Date?]) grid cells, or an empty array when month metadata cannot be resolved
    /// @post       Displayed month and selection remain unchanged
    ///
    private var monthDays: [Date?] { /* Month grid dates with leading alignment placeholders */
        let calendar = Calendar.current /* User's local calendar */

        guard let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start, /* First date in the displayed month */
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { /* Valid day numbers for the displayed month */

            return []
        }

        let leadingDays = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7 /* Empty cells before day one */
        var days: [Date?] = Array(repeating: nil, count: leadingDays) /* Grid cells assembled after weekday alignment */

        days += dayRange.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        days += Array(repeating: nil, count: (7 - days.count % 7) % 7)

        return days
    }

    ///
    /// @fcn        TodayCalendarView.selectedDayCards
    /// @brief      Resolve cards starting or due on the selected local day
    /// @details    Delegates date comparison and result construction to cards(on:)
    ///
    /// @return     ([CalendarCardResult]) selected-day results in list/card order
    /// @post       Dates and selection remain unchanged
    ///
    private var selectedDayCards: [CalendarCardResult] { /* Cards scheduled for the chosen calendar date */
        cards(on: selectedDate)
    }


    ///
    /// @fcn        TodayCalendarView.body
    /// @brief      Present monthly card-date browsing and selected-day results
    /// @details    Combines month navigation, localized weekday columns, selectable date cells,
    ///             and starting/due cards; result rows route to their containing Board lists
    ///
    /// @return     (some View) paper-backed calendar surface
    /// @post       Date/month controls update local display state; navigation does not edit card dates
    ///
    var body: some View { /* Calendar grid and selected-day card results */

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
                                if let date = monthDays[index] { /* Actual date represented by this grid cell */

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
                                    onOpenBoardCard(result.listID, result.cardID)
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
                                .modifier(ContentLifecycleActions(
                                    title: result.title, kind: "Card",
                                    onArchive: { onArchiveCard(result.cardID) },
                                    onDelete:  { onDeleteCard(result.cardID) }
                                ))
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


    ///
    /// @fcn        TodayCalendarView.calendarDayButton(_:)
    /// @brief      Render an accessible calendar date cell
    /// @details    Distinguishes today and the selected day, marks dates containing cards, and
    ///             announces the full date with its dated-card count
    ///
    /// @param[in]  date  Calendar-grid date to represent
    ///
    /// @return     (some View) day-selection button
    ///
    /// @post       Tapping selects the date's local start of day without changing card dates
    ///
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


    ///
    /// @fcn        TodayCalendarView.cards(on:)
    /// @brief      Find active cards starting or due on a local calendar day
    /// @details    Excludes dividers, compares dates with the user's current calendar, and emits
    ///             one result per matching card, including a combined start/due marker
    ///
    /// @param[in]  date  Day whose starting and due cards are requested
    ///
    /// @return     ([CalendarCardResult]) dated-card results in supplied list/card order
    ///
    /// @pre        The caller supplies the intended list partition with Board-unique card IDs
    /// @post       No date, completion, or archived-card data is modified
    ///
    private func cards(on date: Date) -> [CalendarCardResult] {

        let calendar = Calendar.current /* User's local calendar */

        return lists.flatMap { list in
            list.cards.compactMap { card in
                guard !card.isSectionDivider else {

                    return nil
                }

                let starts = card.startDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false /* Start date marker */
                let due = card.dueDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false /* Due date marker */

                guard starts || due else {

                    return nil
                }

                let dateLabel = starts && due ? "Starts & due" : (due ? "Due" : "Starts") /* Display-only date meaning */

                return CalendarCardResult(cardID: card.id, title: card.word, listID: list.id, listTitle: list.title, dateLabel: dateLabel)
            }
        }
    }


    ///
    /// @fcn        TodayCalendarView.moveMonth(by:)
    /// @brief      Shift the displayed calendar month and reset day selection
    /// @details    Adds the signed month offset using the current calendar; if date arithmetic
    ///             fails, leaves both displayedMonth and selectedDate unchanged
    ///
    /// @param[in]  amount  Signed number of months to move
    ///
    /// @return     (Void) selects the local start of day for the shifted month date
    ///
    /// @post       Card dates and Board contents remain unchanged
    ///
    private func moveMonth(by amount: Int) {

        guard let nextMonth = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) else { /* Month reached by the navigation offset */

            return
        }

        displayedMonth = nextMonth
        selectedDate = Calendar.current.startOfDay(for: nextMonth)
    }
}


///
/// Associates a bookmarked card with its containing Week list
///
/// @section    Purpose
///     Preserve navigation context for Saved card rows
///
struct PersonalSavedCardTarget: Equatable {

    let collectionID: UUID /* Owning personal collection */
    let listID: Int /* Containing collection-local list */
    let cardID: Int /* Collection-local bookmarked record */
}


private struct SavedCardResult: Identifiable {

    let card: KanbanCard /* Saved card data */
    let listID: Int /* List opened when selected */
    let listTitle: String /* Containing list title */

    ///
    /// @fcn        SavedCardResult.id
    /// @brief      Identify a bookmarked-card row
    /// @details    Reuses the card's stable identity in the Week snapshot
    ///
    /// @return     (Int) card identity
    /// @pre        Card IDs are unique within the displayed Week Board
    /// @post       Bookmark membership and card content remain unchanged
    ///
    var id: Int { card.id } /* Saved card's stable Board-local identity */
}


/// Shows device-local bookmarks for cards in the current Board.
///
/// Presents local card bookmarks and archived board snapshots
///
/// @section    Purpose
///     Provide access to saved cards and save-first board restoration
///
private struct SavedCardsView: View {

    let lists: [KanbanList] /* Current Board snapshot */
    let savedCardIDs: Set<Int> /* Local bookmark set */
    @Binding var collections: [PersonalCollection] /* Collections whose archived boards can be restored */
    let onOpenBoardList: (Int) -> Void /* Navigate to the containing list */
    let onOpenPersonalCard: (PersonalSavedCardTarget) -> Void /* Navigate to a bookmarked personal record */
    let onRestoreBoard: (UUID) -> Void /* Restore a saved board by identity */
    let onDeleteBoard: (UUID) -> Bool /* Save permanent collection removal and report success */
    let onArchiveCard: (Int) -> Void /* Archive a Week bookmark's canonical card */
    let onDeleteCard: (Int) -> Bool /* Report confirmed Week bookmark-card removal */
    @State private var deletingBoard: PersonalCollection? /* Saved collection awaiting removal */
    @State private var deletingCard: KanbanCard? /* Week bookmark awaiting removal */
    @State private var inspectingBoard: PersonalCollection? /* Archived collection being browsed */

    ///
    /// @fcn        SavedCardsView.savedCards
    /// @brief      Resolve bookmarks against available active cards
    /// @details    Traverses supplied lists in order, includes bookmarked non-divider cards,
    ///             and retains containing-list provenance; stale bookmark IDs produce no rows
    ///
    /// @return     ([SavedCardResult]) currently available bookmarked cards
    /// @pre        The caller supplies active Week lists
    /// @post       Stale bookmark IDs are not removed from the stored set
    ///
    private var savedCards: [SavedCardResult] { /* Bookmarked cards paired with their containing lists */
        lists.flatMap { list in
            list.cards.compactMap { card in
                guard savedCardIDs.contains(card.id), !card.isSectionDivider else {

                    return nil
                }

                return SavedCardResult(card: card, listID: list.id, listTitle: list.title)
            }
        }
    }

    ///
    /// @fcn        SavedCardsView.personalSavedCards
    /// @brief      Resolve active personal bookmarks without merging their local ID spaces
    /// @details    PersonalCollection supplies collection/list provenance and filters archived or
    ///             divider content before these results are rendered
    ///
    /// @return     ([PersonalCollectionBookmarkedCard]) available personal bookmark rows
    ///
    private var personalSavedCards: [PersonalCollectionBookmarkedCard] { /* Active personal bookmarks for Saved */
        collections.filter(\.isActive).flatMap(\.bookmarkedCards)
    }


    ///
    /// @fcn        SavedCardsView.body
    /// @brief      Present device-local bookmarks and archived full boards
    /// @details    Shows available bookmarked cards with list navigation and, when present,
    ///             archived board snapshots with Restore actions and nested-content counts
    ///
    /// @return     (some View) paper-backed Saved surface
    /// @post       Restore delegates to the root save-first callback; bookmarked-card selection
    ///             opens its containing Week list without removing the bookmark
    ///
    var body: some View { /* Saved-card directory and navigation destinations */

        ZStack {
            TodayPaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saved")
                            .font(.largeTitle.weight(.bold))
                        Text("Bookmarks and archived collections on this device")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        if savedCards.isEmpty && personalSavedCards.isEmpty {

                            Label("No saved items yet", systemImage: "bookmark")
                                .font(.headline)
                            Text("Open a card and tap the bookmark to keep it here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            if !savedCards.isEmpty {
                                Text("Week")
                                    .font(.headline)
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
                                    .contextMenu {
                                        Button("Archive Card", systemImage: "archivebox") { onArchiveCard(result.card.id) }
                                        Button("Delete Card", systemImage: "trash", role: .destructive) { deletingCard = result.card }
                                    }
                                    .accessibilityActions {
                                        Button("Archive Card") { onArchiveCard(result.card.id) }
                                        Button("Delete Card") { deletingCard = result.card }
                                    }
                                }
                            }

                            if !personalSavedCards.isEmpty {
                                Text("Library")
                                    .font(.headline)
                                ForEach(personalSavedCards) { result in
                                    Button {
                                        onOpenPersonalCard(PersonalSavedCardTarget(
                                            collectionID: result.collectionID,
                                            listID: result.listID,
                                            cardID: result.card.id
                                        ))
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "bookmark.fill")
                                                .foregroundStyle(.orange)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(result.card.word)
                                                    .foregroundStyle(.primary)
                                                Text("\(result.collectionTitle) · \(result.listTitle)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
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
                                    .accessibilityHint("Opens this item in \(result.collectionTitle), \(result.listTitle).")
                                }
                            }
                        }
                    }

                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .modifier(TodayPanelSurface())

                    if collections.contains(where: {

                        $0.isArchived == true
                    }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Archived Collections").font(.title2.weight(.semibold))
                            ForEach(collections.filter { $0.isArchived == true }) { board in
                                HStack {
                                    Image(systemName: "archivebox").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Button(board.title) { inspectingBoard = board }
                                            .font(.headline)
                                        Text("\(board.lists.count) lists · \(board.lists.flatMap(\.allCards).filter { !$0.isSectionDivider }.count) cards")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                    Button("Restore") { onRestoreBoard(board.id) }
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("Restore \(board.title)")
                                    Button("Delete", systemImage: "trash", role: .destructive) { deletingBoard = board }
                                        .labelStyle(.iconOnly)
                                        .accessibilityLabel("Delete \(board.title)")
                                }
                            }

                            Text("Restored boards appear in Library. Restoring a Week Board creates a separate board and leaves your current Week unchanged.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        .padding(16)
                        .modifier(TodayPanelSurface())
                    }
                }

                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            .background(.clear)
        }

        .confirmationDialog("Delete \(deletingBoard?.title ?? "collection")?", isPresented: Binding(
            get: { deletingBoard != nil }, set: { if !$0 { deletingBoard = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                if let deletingBoard { /* Archived collection awaiting permanent deletion */

                    _ = onDeleteBoard(deletingBoard.id)
                }

                deletingBoard = nil
            }

            Button("Cancel", role: .cancel) { deletingBoard = nil }
        } message: {
            Text("Permanently deletes this retained collection, active and archived lists/cards, and bookmarks. This cannot be undone.")
        }

        .confirmationDialog("Delete \(deletingCard?.word ?? "card")?", isPresented: Binding(
            get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) {
                if let deletingCard { /* Saved Week card awaiting permanent deletion */

                    _ = onDeleteCard(deletingCard.id)
                }

                deletingCard = nil
            }

            Button("Cancel", role: .cancel) { deletingCard = nil }
        } message: {
            Text("Permanently deletes the card and its bookmark from Week. This cannot be undone.")
        }

        .sheet(item: $inspectingBoard) { board in
            ArchivedCollectionContentsView(
                collection:     Binding(
                    get: { collections.first { $0.id == board.id } ?? board },
                    set: { updated in
                        guard let index = collections.firstIndex(where: { /* Position of the archived collection to mutate */

                            $0.id == updated.id
                        }) else {
                            return
                        }
                        do {

                            var snapshot = collections /* Directory snapshot saved before publishing archive changes */
                            snapshot[index] = updated
                            try PersonalCollectionStore.saveChecked(snapshot)
                            collections = snapshot
                        } catch {
                            DatabaseActivity.shared.report("Could not delete archived content: \(error.localizedDescription) It has been retained.")
                        }
                    }
                ),
                onDeleteBoard:  { onDeleteBoard(board.id) },
                onRestoreBoard: { onRestoreBoard(board.id) }
            )
            .databaseActivityOverlay()
        }
    }
}


///
/// Browses all retained content inside an archived personal collection
///
/// @section    Purpose
///     Provide confirmed list/card deletion without restoring or duplicating the Board
///
private struct ArchivedCollectionContentsView: View {
    @Binding var collection: PersonalCollection /* Canonical retained collection */
    let onDeleteBoard: () -> Bool /* Parent reports saved collection removal */
    let onRestoreBoard: () -> Void /* Parent saves restoration */
    @Environment(\.dismiss) private var dismiss /* Return to Saved */
    @State private var deletingList: KanbanList? /* Nested list awaiting removal */
    @State private var deletingCard: KanbanCard? /* Retained card awaiting removal */
    @State private var confirmsDeleteBoard = false /* Entire collection removal confirmation */


    ///
    /// @fcn        ArchivedCollectionContentsView.deleteCard(_:)
    /// @brief      Save complete retained-card and bookmark removal through the canonical binding
    /// @details    The owner reports save errors; failed saves leave its binding unchanged
    ///
    /// @param[in]  id  Card identity within this collection
    ///
    /// @return     (Bool) whether the canonical card was removed
    ///
    @discardableResult
    private func deleteCard(_ id: Int) -> Bool {

        var updated = collection /* Archived Board snapshot receiving the requested change */

        BoardContentDeletion.card(id, in: &updated.lists, savedCardIDs: &updated.savedCardIDs)
        collection = updated

        return !collection.lists.contains { $0.allCards.contains { $0.id == id } }
    }

    ///
    /// @fcn        ArchivedCollectionContentsView.body
    /// @brief      Inspect archived collection lists and their active/archive cards
    /// @details    Deletion updates the owning collection's complete snapshot and local bookmarks
    /// @return     (some View) retained-content browser with restore and deletion controls
    ///
    var body: some View { /* Archived Board lists and retained card management */
        NavigationStack {
            List {
                ForEach(collection.lists) { list in
                    Section(list.title + (list.isArchived ? " (archived)" : "")) {
                        ForEach(list.allCards) { card in
                            NavigationLink(card.word) {
                                ArchivedCardInspectionView(card: card) {
                                    deleteCard(card.id)
                                }
                            }
                            .contextMenu {
                                Button("Delete Card", systemImage: "trash", role: .destructive) { deletingCard = card }
                            }

                            .accessibilityAction(named: "Delete Card") { deletingCard = card }
                        }

                        Button("Delete List", systemImage: "trash", role: .destructive) { deletingList = list }
                    }
                }
            }

            .navigationTitle(collection.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Collection actions", systemImage: "ellipsis.circle") {
                        Button("Restore") { onRestoreBoard(); dismiss() }
                        Button("Delete Collection", systemImage: "trash", role: .destructive) { confirmsDeleteBoard = true }
                    }
                }
            }

            .confirmationDialog("Delete \(deletingList?.title ?? "list")?", isPresented: Binding(
                get: { deletingList != nil }, set: { if !$0 { deletingList = nil } }
            ), titleVisibility: .visible) {
                Button("Delete List", role: .destructive) {
                    if let deletingList { /* Archived list awaiting permanent deletion */

                        var updated = collection /* Archived Board snapshot excluding the removed list */

                        BoardContentDeletion.list(deletingList.id, in: &updated.lists, savedCardIDs: &updated.savedCardIDs)
                        collection = updated
                    }

                    deletingList = nil
                }

                Button("Cancel", role: .cancel) { deletingList = nil }
            } message: {
                Text("Permanently deletes this list, all retained cards, and bookmarks. This cannot be undone.")
            }

            .confirmationDialog("Delete Collection?", isPresented: $confirmsDeleteBoard, titleVisibility: .visible) {
                Button("Delete Collection", role: .destructive) { if onDeleteBoard() { dismiss() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently deletes all content in this retained collection. This cannot be undone.")
            }

            .confirmationDialog("Delete \(deletingCard?.word ?? "card")?", isPresented: Binding(
                get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Card", role: .destructive) {
                    if let deletingCard { /* Archived card awaiting permanent deletion */

                        deleteCard(deletingCard.id)
                    }

                    deletingCard = nil
                }

                Button("Cancel", role: .cancel) { deletingCard = nil }
            } message: {
                Text("Permanently deletes this card, its details, and its bookmark. This cannot be undone.")
            }
        }
    }
}


///
/// Shows the current weekday list's progress and next open cards
///
/// @section    Purpose
///     Summarize the current focus and expose completion and list-navigation actions
///
private struct TodayFocusSection: View {

    let list: KanbanList? /* Canonical Week list matching the current local weekday */
    let cards: [KanbanCard] /* Non-divider cards on that list */
    let openCards: [KanbanCard] /* First three incomplete cards */
    let onToggleCard: (Int) -> Void /* Toggle local completion state */
    let onOpenTodayList: () -> Void /* Open the focused single-list Today view */


    ///
    /// @fcn        TodayFocusSection.body
    /// @brief      Summarize the current weekday list and preview unfinished cards
    /// @details    Displays title-completion progress, distinct empty/all-complete states,
    ///             quick completion controls, and an action to open today's list
    ///
    /// @return     (some View) raised Today focus panel
    /// @pre        cards and openCards describe the supplied list and exclude section dividers
    /// @post       Completion and navigation are delegated to supplied callbacks
    ///
    var body: some View { /* Weekday-list progress and unfinished-card shortcuts */
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Focus")
                .font(.title2.weight(.semibold))

            if list != nil {

                let completedCount = cards.filter(\.isTitleChecked).count /* Completed records counted for Today's progress */

                HStack {
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
                Text("No list for today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TodayPanelSurface())
    }
}


///
/// Draws the shared paper texture behind Today surfaces
///
/// @section    Purpose
///     Keep the decorative background consistent and noninteractive
///
private struct TodayPaperBackground: View {

    ///
    /// @fcn        TodayPaperBackground.body
    /// @brief      Fill the available surface with the shared Today paper texture
    /// @details    Scales and clips the image to geometry, extends through safe areas,
    ///             and excludes decoration from accessibility and hit testing
    ///
    /// @return     (some View) noninteractive full-surface background
    /// @post       Rendering does not affect app or navigation state
    ///
    var body: some View { /* Noninteractive paper texture behind Today surfaces */
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


///
/// Gives Today sections a readable raised surface over the full-screen paper texture
///
/// @section    Purpose
///     Apply one consistent panel treatment without intercepting content interaction
///
private struct TodayPanelSurface: ViewModifier {


    ///
    /// @fcn        TodayPanelSurface.body(content:)
    /// @brief      Give Today content a padded raised material surface
    /// @details    Adds a rounded material background, light outline, and shadow; decorative layers
    ///             do not intercept the content's interactions
    ///
    /// @param[in]  content  Section content to decorate
    ///
    /// @return     (some View) padded content with the shared panel treatment
    ///
    /// @post       Content behavior and model state remain unchanged
    ///
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
