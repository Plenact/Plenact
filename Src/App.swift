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
import PhotosUI
import AVFoundation
import Speech


// -------------------------------------- MARK: - Entry Point ----------------------------------- //


///
/// Application entry point for the Plenact Application
///
/// @section    Purpose
///     Create the app scene and install the primary navigation shell
///
@main
struct Plenact: App {
    @State private var recoveryError: String?
    init() {
        do {
            try DailyReviewTransaction.recover()
            try FullMonthExampleStore.live().recoverInterruptedSwitch()
            _recoveryError = State(initialValue: nil)
        } catch {
            _recoveryError = State(initialValue: error.localizedDescription)
        }
    }

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
            if let recoveryError {
                VStack(spacing: 20) {
                    Text("Your saved data needs recovery").font(.headline)
                    Text(recoveryError).foregroundStyle(.secondary)
                    Button("Retry recovery") {
                        do { try DailyReviewTransaction.recover(); try FullMonthExampleStore.live().recoverInterruptedSwitch(); self.recoveryError = nil }
                        catch { self.recoveryError = error.localizedDescription }
                    }
                }.padding()
            } else { AppRootView() }
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
enum PlenactLaunchStage: Int, CaseIterable {
    case restore, plans, ready, welcome
    var symbol: String {
        switch self { case .restore: "folder"; case .plans: "calendar"; case .ready: "slider.horizontal.3"; case .welcome: "sun.max" }
    }
    var label: String {
        switch self {
        case .restore: "Restoring your workspace"
        case .plans: "Preparing your plans"
        case .ready: "Readying the app"
        case .welcome: "Welcoming you in"
        }
    }
}

struct PlenactLaunchProgress: Equatable {
    enum Status { case waiting, running, complete }
    var stage: PlenactLaunchStage = .restore
    var finished = false
    func paced(elapsed: TimeInterval) -> Self {
        let index = min(3, max(0, Int(max(0, elapsed) / 0.22)))
        return Self(stage: PlenactLaunchStage(rawValue: index) ?? .restore,
                    finished: finished && elapsed >= 0.84)
    }

    func status(for step: PlenactLaunchStage) -> Status {
        if finished || step.rawValue < stage.rawValue { return .complete }
        return step == stage ? .running : .waiting
    }
}

struct PlenactLaunchIndicators: View {
    let progress: PlenactLaunchProgress
    var animates = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 44) {
            ForEach(PlenactLaunchStage.allCases, id: \.rawValue) { step in
                let status = progress.status(for: step)
                Image(systemName: step.symbol)
                    .font(.system(size: 25.3, weight: .light))
                    .frame(width: 30.8, height: 35.2)
                    .foregroundStyle(.white)
                    .phaseAnimator(status == .running && animates && !reduceMotion ? [false, true] : [false]) { icon, bright in
                        icon.opacity(status == .waiting ? 0 : (status == .complete ? 0.85 : (bright ? 0.9 : 0.4)))
                    } animation: { _ in .easeInOut(duration: 1.4) }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: status)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PlenactLaunchSequence: View {
    let progress: PlenactLaunchProgress
    var animates: Bool
    @State private var startedAt = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            PlenactLaunchIndicators(progress: animates ? progress.paced(elapsed: context.date.timeIntervalSince(startedAt)) : progress,
                                    animates: animates)
        }
    }
}

struct PlenactLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animatesLogo = true
    var progress = PlenactLaunchProgress()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
            ZStack {
                Image("LaunchShadow")
                    .resizable().scaledToFit()
                    .frame(width: 240, height: 240)
                    .opacity(0.8)
                    .offset(x: 4, y: 12)
                Image("LaunchLogo")
                    .resizable().scaledToFit()
                    .frame(width: 136, height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
                .phaseAnimator(reduceMotion || !animatesLogo ? [false] : [false, true]) { logo, expanded in
                    logo.scaleEffect(expanded ? 1.035 : 1)
                        .opacity(expanded ? 1 : 0.94)
                } animation: { _ in .easeInOut(duration: 1.8) }
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Plenact").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                Text("Planning your life into action").font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
            }
            .offset(y: 124)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .offset(y: -geometry.size.height * 0.125)
            .overlay(alignment: .bottom) {
                PlenactLaunchSequence(progress: progress, animates: animatesLogo)
                    // Compensate for the wider row so the first icon stays anchored.
                    .offset(x: -8)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 24) + 36)
            }
        }
        .background(Color("LaunchBackground"))
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plenact is loading")
        .accessibilityValue(progress.finished ? "Your workspace is ready" : progress.stage.label)
        .accessibilityIdentifier("app.loading")
    }
}

/// Independent device-specific toolbar geometry. Keep each preset explicit when tuning a device.
struct BottomToolbarLayout {
    var height: CGFloat
    var safeAreaAllowance: CGFloat
    var rowSpacing: CGFloat
    var horizontalPadding: CGFloat
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    var tabsOffset: CGFloat
    var newOffset: CGFloat
    var tabMinimumHeight: CGFloat
    var tabIconSize: CGFloat
    var newButtonSize: CGFloat
    var newIconSize: CGFloat
    var tabLabelSpacing: CGFloat
    var newLabelSpacing: CGFloat
    var backgroundTopInset: CGFloat
    var horizontalLabels: Bool
    var labelStyle: Font.TextStyle

    // iPhone layouts: edits here do not affect iPad.
    static let phoneRegular = Self(height: 74, safeAreaAllowance: 34, rowSpacing: 4, horizontalPadding: 12, topPadding: 4, bottomPadding: 4, tabsOffset: 25, newOffset: 14, tabMinimumHeight: 54, tabIconSize: 23, newButtonSize: 68, newIconSize: 24, tabLabelSpacing: 4, newLabelSpacing: 6, backgroundTopInset: 28, horizontalLabels: false, labelStyle: .caption)
    static let phoneCompact = Self(height: 52, safeAreaAllowance: 0, rowSpacing: 4, horizontalPadding: 12, topPadding: 4, bottomPadding: 4, tabsOffset: 0, newOffset: 0, tabMinimumHeight: 44, tabIconSize: 23, newButtonSize: 44, newIconSize: 24, tabLabelSpacing: 6, newLabelSpacing: 6, backgroundTopInset: 0, horizontalLabels: true, labelStyle: .caption)

    // iPad layouts: independently configurable, including compact-height windows.
    static let padRegular = Self(height: 84, safeAreaAllowance: 34, rowSpacing: 4, horizontalPadding: 12, topPadding: 4, bottomPadding: 4, tabsOffset: 25, newOffset: 14, tabMinimumHeight: 59, tabIconSize: 28, newButtonSize: 78, newIconSize: 29, tabLabelSpacing: 4, newLabelSpacing: 6, backgroundTopInset: 20, horizontalLabels: false, labelStyle: .caption)
    static let padCompact = Self(height: 86, safeAreaAllowance: 0, rowSpacing: 4, horizontalPadding: 12, topPadding: 4, bottomPadding: 4, tabsOffset: 0, newOffset: 0, tabMinimumHeight: 78, tabIconSize: 28, newButtonSize: 78, newIconSize: 29, tabLabelSpacing: 6, newLabelSpacing: 6, backgroundTopInset: 0, horizontalLabels: true, labelStyle: .caption)

    static func configuration(isTablet: Bool, compact: Bool) -> Self {
        if isTablet { return compact ? padCompact : padRegular }
        return compact ? phoneCompact : phoneRegular
    }
    func reservedHeight(bottomInset: CGFloat) -> CGFloat {
        height + max(0, safeAreaAllowance - bottomInset)
    }
}

/// One greeting per process launch, then only after a meaningful foreground absence.
@MainActor
final class TodayWelcomeCue: ObservableObject {
    enum Target: Equatable { case profile, plan }
    static let lastDepartureKey = "Plenact.Welcome.lastDeparture.v1"
    static let returnInterval: TimeInterval = 4 * 60 * 60
    @Published private(set) var requestID = 0
    @Published private(set) var target: Target?
    @Published private(set) var illuminated = false
    private(set) var pending = false
    private var hasActivated = false
    private var departure: Date?
    private var generation = 0
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func becameActive(at now: Date = .now) {
        let shouldGreet = !hasActivated || departure.map { now.timeIntervalSince($0) >= Self.returnInterval } == true
        hasActivated = true
        departure = nil
        if shouldGreet { pending = true; requestID += 1 }
    }
    func leftForeground(at now: Date = .now) {
        if departure == nil {
            departure = now
            defaults.set(now.timeIntervalSince1970, forKey: Self.lastDepartureKey)
        }
        cancel()
    }
    func cancel() {
        generation += 1
        pending = false
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { illuminated = false; target = nil }
    }
    func highlights(_ candidate: Target) -> Bool { target == candidate && illuminated }

    func play(reduceMotion: Bool, planPulseSpeed: Double = 1, pause: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async {
        guard pending else { return }
        pending = false
        let token = generation
        func current() -> Bool { token == generation && !Task.isCancelled }
        func light(_ value: Bool) {
            if reduceMotion { illuminated = value }
            else { withAnimation(.easeInOut(duration: 0.5 / (target == .plan ? planPulseSpeed : 1))) { illuminated = value } }
        }
        defer { if token == generation { illuminated = false; target = nil } }
        do {
            try await pause(.milliseconds(650))
            for cue in [Target.profile, .plan] {
                guard current() else { return }
                target = cue
                if reduceMotion {
                    light(true)
                    try await pause(.milliseconds(1000))
                    guard current() else { return }
                    light(false)
                } else {
                    for _ in 0..<2 {
                        guard current() else { return }
                        light(true)
                        try await pause(.seconds(0.6 / (cue == .plan ? planPulseSpeed : 1)))
                        guard current() else { return }
                        light(false)
                        try await pause(.seconds(0.6 / (cue == .plan ? planPulseSpeed : 1)))
                    }
                }
                guard current() else { return }
                target = nil
                if cue == .profile { try await pause(.milliseconds(500)) }
            }
        } catch { /* View disappearance/backgrounding cancels the finite sequence. */ }
    }
}

/// Decoration only: does not change layout, intercept gestures, or add accessibility elements.
struct TodayWelcomeGlow: ViewModifier {
    let highlighted: Bool
    var circular = false
    private let softGold = Color(red: 0.94, green: 0.79, blue: 0.44)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: circular ? 100 : 10)
                    .fill(softGold.opacity(highlighted ? 0.12 : 0))
                    .padding(-5)
                    .blur(radius: 8)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .shadow(color: softGold.opacity(highlighted ? 0.32 : 0), radius: highlighted ? 14 : 0)
            .scaleEffect(highlighted && !reduceMotion ? 1.035 : 1, anchor: circular ? .center : .leading)
    }
}

private struct AppRootView: View {
    @AppStorage(PlanPreferencesStore.key) private var planPreferencesData = Data()
    @StateObject private var welcomeCue = TodayWelcomeCue()
    @Environment(\.accessibilityReduceMotion) private var reduceLaunchMotion

    @State private var isSwitchingWorkspace = false
    @State private var isRestoringWorkspace = false
    @State private var workspaceRecoveryError: String?
    @State private var workspaceGeneration = UUID()
    @State private var confirmsExampleMonth = false
    @State private var confirmsRestoreUserData = false
    @State private var workspaceNotice: String?
    @State private var lists: [KanbanList]                 = []                             /* Complete in-memory Week snapshot                    */
    @State private var collections                         = TodayListPins.loadInitialCollections()	/* Device-local personal collections                   */
    @State private var calendarDocument: PlanningCalendarDocument?
    @State private var displayedPlanningWeek: DatedPlanningWeek?
    @State private var displayedPlanningListID: Int?
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchProgress = PlenactLaunchProgress()
    @State private var hasLoadedBoard                      = false                          /* Whether the initial Week snapshot has loaded        */
    @State private var profile                             = LocalProfileStore.load()       /* Optional local identity and settings                */
    @State private var selectedDestination: AppDestination = .today                         /* Currently selected primary destination              */ 
    @State private var bottomNavigationSafeInset: CGFloat = 34
    private var bottomToolbarLayout: BottomToolbarLayout {
        .configuration(isTablet: UIDevice.current.userInterfaceIdiom == .pad, compact: verticalSizeClass == .compact)
    }
    private var bottomNavigationHeight: CGFloat {
        bottomToolbarLayout.reservedHeight(bottomInset: bottomNavigationSafeInset)
    }
    @State private var visibleNoteIDs: Set<UUID> = []
    private var isNotePresented: Bool { !visibleNoteIDs.isEmpty }
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
            if let workspaceRecoveryError {
                VStack(spacing: 20) {
                    Text("Your saved data needs recovery").font(.headline)
                    Text(workspaceRecoveryError).foregroundStyle(.secondary)
                    Button("Retry recovery") { recoverWorkspace() }.disabled(isSwitchingWorkspace)
                }.padding()
            } else if isSwitchingWorkspace {
                ProgressView("Preparing your workspace…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await performMonthExampleSwitch(restoring: isRestoringWorkspace) }
            } else if hasLoadedBoard {

                navigationContent
                    .id(workspaceGeneration)
                    .transition(.opacity)
            } else {
                PlenactLoadingView(progress: launchProgress)
                    .transition(.opacity)
            }
        }

        .animation(reduceLaunchMotion ? nil : .easeInOut(duration: 0.45), value: hasLoadedBoard)
        .environmentObject(welcomeCue)
        .databaseActivityOverlay()
        .confirmationDialog("Load an example month?", isPresented: $confirmsExampleMonth, titleVisibility: .visible) {
            Button("Back Up and Load Example Month") { switchMonthExample(restoring: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current Plenact data and local files will first be copied to an offline backup. The example month will replace your active plans. To return, choose Library + → Examples → Restore User Data. An existing original backup will be kept.")
        }
        .confirmationDialog("Restore your saved data?", isPresented: $confirmsRestoreUserData, titleVisibility: .visible) {
            Button("Restore User Data") { switchMonthExample(restoring: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores the complete offline copy saved before the example month. Changes made in the example workspace will be replaced.")
        }
        .alert("Plenact workspace", isPresented: Binding(get: { workspaceNotice != nil }, set: { if !$0 { workspaceNotice = nil } })) {
            Button("OK") { workspaceNotice = nil }
        } message: { Text(workspaceNotice ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { welcomeCue.becameActive(); advancePlanningWeekIfNeeded() }
            else { welcomeCue.leftForeground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            advancePlanningWeekIfNeeded()
        }
        .task {
            if scenePhase == .active { welcomeCue.becameActive() }
            guard !hasLoadedBoard else {

                return
            }

            let launchDeadline = ContinuousClock.now.advanced(by: .milliseconds(900))
            launchProgress = PlenactLaunchProgress()
            let legacy = await KanbanBoardPersistence.loadListsInBackground()
            launchProgress.stage = .plans
            await Task.yield()
            var preparedDocument: PlanningCalendarDocument?
            var preparedWeek: DatedPlanningWeek?
            do {
                if var document = try PlanningCalendarStore.load() {
                    try document.repairLegacyMondayFirstLayout()
                    let previous = document.weeks.first { $0.startKey == document.currentWeekKey }!
                    let newWeek = document.week(for: .now) == nil ? try PlanningRoutineStore.newWeek(for: .now, calendar: document.calendar) : nil
                    preparedWeek = document.rollForward(to: .now, currentLists: previous.collection.lists, saved: previous.collection.savedCardIDs, newWeek: newWeek)
                    preparedDocument = document
                } else {
                    if let data = UserDefaults.standard.data(forKey: "Plenact.Board.v1") {
                        _ = try JSONDecoder().decode([KanbanList].self, from: data)
                    }
                    var calendar = Calendar.current
                    calendar.firstWeekday = 2
                    let current = UserDefaults.standard.data(forKey: "Plenact.Board.v1") == nil
                        ? try PlanningRoutineStore.newWeek(for: .now, calendar: calendar)
                        : DatedPlanningWeek.make(for: .now, lists: legacy, saved: savedCardIDs, calendar: calendar)
                    preparedWeek = current
                    preparedDocument = PlanningCalendarDocument(currentWeekKey: current.startKey, firstWeekday: 2, weeks: [current])
                }
            } catch {
                lists = legacy
                DatabaseActivity.shared.report("Could not open your calendar weeks: \(error.localizedDescription) Your saved data has been retained.")
            }
            launchProgress.stage = .ready
            await Task.yield()
            if let document = preparedDocument, let current = preparedWeek {
                do {
                    try DailyReviewTransaction.perform {
                        try PlanningCalendarStore.save(document)
                        try KanbanBoardPersistence.saveListsChecked(current.collection.lists)
                    }
                    lists = current.collection.lists
                    savedCardIDs = current.collection.savedCardIDs
                    calendarDocument = document
                } catch {
                    lists = legacy
                    DatabaseActivity.shared.report("Could not open your calendar weeks: \(error.localizedDescription) Your saved data has been retained.")
                }
            }
            SavedCardPersistence.save(savedCardIDs)
            launchProgress.stage = .welcome
            await Task.yield()
            // Preparation is complete; keep the steady icons visible during the existing minimum launch time.
            launchProgress.finished = true
            do { try await ContinuousClock().sleep(until: launchDeadline) }
            catch { return }
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
                onAddCard:              { listID, title, description, subtitle, presentation, actions in
                    addCard(to: listID, title: title, description: description, subtitle: subtitle, presentation: presentation, actions: actions)
                },
                onAddCapture: { capture in
                    addCard(to: capture.listID, title: capture.title, description: capture.body, subtitle: capture.subtitle, presentation: capture.presentation, actions: capture.actions, attachments: capture.attachments, schedule: capture.schedule, checkedSave: true)
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

            Group {
                if let displayedPlanningWeek {
                    PlanningCalendarWeekView(week: displayedPlanningWeek, initialDayID: nil, initialCardID: nil,
                        onLeaveForHome: { self.displayedPlanningWeek = nil }, isWeekTab: true, initialBoardListID: displayedPlanningListID)
                        .id(displayedPlanningWeek.startKey)
                } else {
            ContentView(
                lists:             $lists.activeLists,
                archivedLists:     $lists.archivedLists,
                boardTargetListID: $boardTargetListID,
                boardTargetCardID: $boardTargetCardID,
                boardRootRequest:  weekRootRequest,
                savedCardIDs:      $savedCardIDs,
                onListViewed:      rememberLastViewedList,
                boardSubtitle: "This Week • " + (calendarDocument?.weeks.first { $0.startKey == calendarDocument?.currentWeekKey }?.compactRangeTitle ?? ""),
                onArchiveBoard:    archiveWeekBoard,
                onDeleteBoard:     deleteWeekContents,
                deleteBoardTitle:  "Delete Week contents",
                onCommitDeletion:  commitWeekDeletion,
                onListsChanged:    { _ in },
                viewportOwnerID: calendarDocument?.weeks.first { $0.startKey == calendarDocument?.currentWeekKey }?.id
            )
            .id(calendarDocument?.currentWeekKey ?? "week.current")
                }
            }
                .tabItem {
                    Label("Board", systemImage: "rectangle.3.group")
                }

                .tag(AppDestination.board)
                .toolbar(.hidden, for: .tabBar)

            libraryTab

            SavedCardsView(
                planningDocument: calendarDocument,
                lists:           lists.filter { !$0.isArchived },
                savedCardIDs:    savedCardIDs,
                collections:     $collections,
                onOpenBoardCard: openBoardCard,
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
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }

                .tag(AppDestination.saved)
                .toolbar(.hidden, for: .tabBar)
        }

        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: isNotePresented ? 0 : bottomNavigationHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if !isNotePresented { bottomNavigationBar }
                }
                .onAppear { bottomNavigationSafeInset = geometry.safeAreaInsets.bottom }
                .onChange(of: geometry.safeAreaInsets.bottom) { _, inset in bottomNavigationSafeInset = inset }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }

        .environment(\.workspaceNoteVisibility, { id, visible in
            if visible { visibleNoteIDs.insert(id) } else { visibleNoteIDs.remove(id) }
        })
        .environment(\.workspaceBottomBarHeight, isNotePresented ? 0 : bottomNavigationHeight)
        .environment(\.cardMovementAccess, cardMovementAccess)
        .environment(\.planningCalendarAccess, planningCalendarAccess)
        .environment(\.calendar, calendarDocument?.calendar ?? .current)

        .onChange(of: savedCardIDs) { _, updatedIDs in
            SavedCardPersistence.save(updatedIDs)
            persistCurrentPlanningWeek()
        }

        .onChange(of: lists) { old, updated in
            guard hasLoadedBoard else {

                return
            }

            let candidates = CardAttachmentStore.fileNames(in: old).subtracting(CardAttachmentStore.fileNames(in: updated)) /* Media removed by the collection update */

            persistCurrentPlanningWeek()
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
                initialListID: LastViewedListStore.resolve(in: lists.filter { !$0.isArchived }, fallback: PlanPreferencesStore.load().defaultListID)
            ) { listID, title, description, subtitle, presentation, actions in
                addCard(to: listID, title: title, description: description, subtitle: subtitle, presentation: presentation, actions: actions)
            }

            .databaseActivityOverlay()
        }
    }


    private var planningCalendarAccess: PlanningCalendarAccess? {
        guard let document = calendarDocument else { return nil }
        return PlanningCalendarAccess(document: document, library: collections, saveWeek: savePlanningWeek,
            openCurrentWeek: {
                displayedPlanningListID = nil
                displayedPlanningWeek = nil
                selectedDestination = .board
                weekRootRequest += 1
                boardTargetListID = nil; boardTargetCardID = nil
            }, openToday: { selectedDestination = .today },
            openLibraryCard: { target in savedPersonalCardTarget = target; selectedDestination = .lists },
            saveLibrary: { collection in
                guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return false }
                var snapshot = collections; snapshot[index] = collection
                do { try PersonalCollectionStore.saveChecked(snapshot); collections = snapshot; return true }
                catch { DatabaseActivity.shared.report("Could not save this Plans collection: \(error.localizedDescription)"); return false }
            }, applyWeeklyReview: applyWeeklyReview, applyDailyReview: applyDailyReview, moveForDailyPlan: movePriorityForVision, setFirstWeekday: setPlanningFirstWeekday, openWeek: { requestedWeek in
                guard let week = preparePlanningWeek(requestedWeek) else { return }
                displayedPlanningListID = nil
                weekRootRequest += 1
                displayedPlanningWeek = week.startKey == calendarDocument?.currentWeekKey ? nil : week
                boardTargetListID = nil; boardTargetCardID = nil
                selectedDestination = .board
            }, moveList: movePlanningList, openWeekOnDay: { requestedWeek, date in
                guard let week = preparePlanningWeek(requestedWeek) else { return }
                let listID = week.dayListIDs[PlanningDate.key(date, calendar: document.calendar)]
                weekRootRequest += 1
                displayedPlanningListID = listID
                displayedPlanningWeek = week.startKey == calendarDocument?.currentWeekKey ? nil : week
                boardTargetCardID = nil
                boardTargetListID = week.startKey == calendarDocument?.currentWeekKey ? listID : nil
                selectedDestination = .board
            })
    }

    private func setPlanningFirstWeekday(_ weekday: Int) -> Bool {
        guard let previous = calendarDocument else { return false }
        guard previous.firstWeekday != weekday else { return true }
        var updated = previous
        if var current = updated.weeks.first(where: { $0.startKey == updated.currentWeekKey }) {
            current.collection.lists = lists
            current.collection.savedCardIDs = savedCardIDs
            updated.upsert(current)
        }
        do {
            try updated.changeFirstWeekday(to: weekday)
            let current = updated.weeks.first { $0.startKey == updated.currentWeekKey }!
            try PlanningCalendarStore.save(updated)
            do { try KanbanBoardPersistence.saveListsChecked(current.collection.lists) }
            catch { try PlanningCalendarStore.save(previous); throw error }
            calendarDocument = updated
            lists = current.collection.lists
            savedCardIDs = current.collection.savedCardIDs
            SavedCardPersistence.save(savedCardIDs)
            boardTargetListID = nil; boardTargetCardID = nil
            weekRootRequest += 1
            return true
        } catch {
            DatabaseActivity.shared.report("Could not change the start of the week: \(error.localizedDescription) Your plans have been retained.")
            return false
        }
    }

    private func persistCurrentPlanningWeek() {
        guard hasLoadedBoard, var document = calendarDocument,
              var current = document.weeks.first(where: { $0.startKey == document.currentWeekKey }) else { return }
        current.collection.lists = lists
        current.collection.savedCardIDs = savedCardIDs
        // If a weekday was archived/deleted, its replacement receives the date association.
        for date in PlanningDate.days(in: current.startKey) where current.list(on: date) == nil {
            if let replacement = TodayListSelection.currentDayList(in: lists, date: date) {
                current.dayListIDs[PlanningDate.key(date)] = replacement.id
            }
        }
        document.upsert(current)
        guard document != calendarDocument else { return }
        do { try PlanningCalendarStore.save(document); calendarDocument = document }
        catch { DatabaseActivity.shared.report("Could not save calendar weeks: \(error.localizedDescription)") }
    }

    private func advancePlanningWeekIfNeeded() {
        guard !isSwitchingWorkspace, hasLoadedBoard, var document = calendarDocument,
              document.currentWeekKey != PlanningDate.weekKey(.now, calendar: document.calendar) else { return }
        do {
            let newWeek = document.week(for: .now) == nil ? try PlanningRoutineStore.newWeek(for: .now, calendar: document.calendar) : nil
            let next = document.rollForward(to: .now, currentLists: lists, saved: savedCardIDs, newWeek: newWeek)
            try DailyReviewTransaction.perform {
                try PlanningCalendarStore.save(document)
                try KanbanBoardPersistence.saveListsChecked(next.collection.lists)
            }
            calendarDocument = document
            lists = next.collection.lists; savedCardIDs = next.collection.savedCardIDs
            boardTargetListID = nil; boardTargetCardID = nil
            weekRootRequest += 1
        } catch { DatabaseActivity.shared.report("Could not advance this week: \(error.localizedDescription)") }
    }

    private func preparePlanningWeek(_ requested: DatedPlanningWeek) -> DatedPlanningWeek? {
        guard let document = calendarDocument else { return nil }
        if let existing = document.weeks.first(where: { $0.startKey == requested.startKey }) { return existing }
        do {
            guard let date = PlanningDate.date(requested.startKey, calendar: document.calendar) else { return nil }
            let prepared = try PlanningRoutineStore.newWeek(for: date, calendar: document.calendar)
            return savePlanningWeek(prepared) ? prepared : nil
        } catch {
            DatabaseActivity.shared.report("Could not prepare this week from its template. Your saved plans were retained.")
            return nil
        }
    }

    private func savePlanningWeek(_ week: DatedPlanningWeek) -> Bool {
        guard var document = calendarDocument else { return false }
        if let existing = document.weeks.first(where: { $0.startKey == week.startKey }), existing.id != week.id { return false }
        document.upsert(week)
        if document == calendarDocument { return true }
        do {
            try DailyReviewTransaction.perform {
                try PlanningCalendarStore.save(document)
                if week.startKey == document.currentWeekKey { try KanbanBoardPersistence.saveListsChecked(week.collection.lists) }
            }
            calendarDocument = document
            if week.startKey == document.currentWeekKey {
                lists = week.collection.lists; savedCardIDs = week.collection.savedCardIDs
            }
            return true
        } catch {
            DatabaseActivity.shared.report("Could not save this week: \(error.localizedDescription) Your content has been retained.")
            return false
        }
    }

    private var cardMovementAccess: CardMovementAccess {
        let currentID = calendarDocument?.weeks.first { $0.startKey == calendarDocument?.currentWeekKey }?.id
        let weekDestinations = lists.filter { !$0.isArchived }.map {
            CardMoveDestination(collectionID: nil, listID: $0.id, title: $0.title, group: "Week")
        }
        let calendarDestinations = (calendarDocument?.weeks ?? []).filter { $0.id != currentID }.flatMap { week in
            week.collection.lists.filter { !$0.isArchived }.map {
                CardMoveDestination(collectionID: week.id, listID: $0.id, title: "\(week.rangeTitle) / \($0.title)", group: "Calendar", columnTitle: $0.title)
            }
        }
        let libraryDestinations = collections.filter(\.isActive).flatMap { collection in
            collection.lists.filter { !$0.isArchived }.map {
                CardMoveDestination(collectionID: collection.id, listID: $0.id,
                    title: collection.kind == .list ? collection.title : "\(collection.title) / \($0.title)", group: "Plans", columnTitle: $0.title)
            }
        }
        return CardMovementAccess(destinations: weekDestinations + calendarDestinations + libraryDestinations,
            move: { card, source, destination in
                movePlanningCard(card, source: source, destination: destination)
            }, moveToDate: { card, source, date in
                guard var document = calendarDocument else { return false }
                var week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: document.calendar)
                let listID = week.prepareDay(date)
                guard let list = week.collection.lists.first(where: { $0.id == listID }) else { return false }
                document.upsert(week)
                return movePlanningCard(card, source: source,
                    destination: CardMoveDestination(collectionID: week.id, listID: list.id, title: "\(week.rangeTitle) / \(list.title)", group: "Calendar"),
                    documentOverride: document)
            })
    }

    private func movePlanningList(_ listID: Int, sourceID: UUID, destinationID: UUID?) -> Bool {
        do {
            guard var document = calendarDocument else { return false }
            if let current = document.weeks.firstIndex(where: { $0.startKey == document.currentWeekKey }) {
                document.weeks[current].collection.lists = lists
                document.weeks[current].collection.savedCardIDs = savedCardIDs
            }
            let datedSource = document.weeks.first { $0.id == sourceID }
            let emptiedDates = datedSource?.dayListIDs.filter { $0.value == listID }.map(\.key) ?? []
            var combined = collections + document.weeks.map(\.collection)
            let moved: KanbanList
            let newStandalone: PersonalCollection?
            if let destinationID {
                moved = try CrossBoardListMovement.move(listID: listID, from: sourceID, to: destinationID, collections: &combined)
                newStandalone = nil
            } else {
                let standalone = try CrossBoardListMovement.detach(listID: listID, from: sourceID, collections: &combined)
                moved = standalone.lists[0]
                newStandalone = standalone
            }
            for index in document.weeks.indices {
                if let updated = combined.first(where: { $0.id == document.weeks[index].id }) {
                    document.weeks[index].collection = updated
                }
                if document.weeks[index].id == sourceID {
                    for key in emptiedDates {
                        if let date = PlanningDate.date(key, calendar: document.calendar) {
                            _ = document.weeks[index].prepareDay(date)
                        }
                    }
                }
            }
            let updatedLibrary = combined.filter { candidate in
                candidate.id == newStandalone?.id || collections.contains { $0.id == candidate.id }
            }
            guard let current = document.weeks.first(where: { $0.startKey == document.currentWeekKey }) else { return false }
            // Validate all payloads and retained stores before any writes or publication.
            _ = try JSONEncoder().encode(document)
            _ = try JSONEncoder().encode(updatedLibrary)
            _ = try JSONEncoder().encode(current.collection.lists)
            _ = try PlanningCalendarStore.load()
            if let data = UserDefaults.standard.data(forKey: "Plenact.Board.v1") { _ = try JSONDecoder().decode([KanbanList].self, from: data) }
            if let data = UserDefaults.standard.data(forKey: "Plenact.PersonalCollections.v1") { _ = try JSONDecoder().decode([PersonalCollection].self, from: data) }
            let defaults = UserDefaults.standard
            let keys = [PlanningCalendarStore.key, "Plenact.Board.v1", "Plenact.PersonalCollections.v1", "Plenact.SavedCardIDs.v1"]
            let previous = keys.map { defaults.object(forKey: $0) }
            do {
                try PlanningCalendarStore.save(document)
                try PersonalCollectionStore.saveChecked(updatedLibrary)
                try KanbanBoardPersistence.saveListsChecked(current.collection.lists)
                SavedCardPersistence.save(current.collection.savedCardIDs)
            } catch {
                for (key, value) in zip(keys, previous) {
                    if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
                }
                throw error
            }
            calendarDocument = document
            collections = updatedLibrary
            lists = current.collection.lists
            savedCardIDs = current.collection.savedCardIDs
            let destination = newStandalone != nil ? "Plans as a standalone List"
                : (document.weeks.first(where: { $0.id == destinationID })?.rangeTitle
                    ?? updatedLibrary.first(where: { $0.id == destinationID })?.title ?? "another board")
            TransferConfirmationPresenter.shared.show(TransferConfirmation(title: moved.title, destination: destination))
            return true
        } catch {
            DatabaseActivity.shared.report("Could not move this list: \(error.localizedDescription) Its content has been retained.")
            return false
        }
    }

    private func mutateReviewItem(_ live: PlanningSearchResult, action: DailyReviewAction, anchor: String) throws -> PlanningSearchResult {
        var result = live
        switch action {
        case .keep: break
        case .queue:
            guard let queue = collections.first(where: { $0.isActive && $0.kind == .list && $0.title == "In the Queue" }),
                  let list = queue.lists.first(where: { !$0.isArchived }) else { throw CocoaError(.fileNoSuchFile) }
            if queue.id != live.collectionID || list.id != live.listID {
                guard let moved = movePriorityForVision(live, destination: WorkspaceListReference(ownerID: queue.id, listID: list.id)) else { throw CocoaError(.fileWriteUnknown) }
                result = moved
            }
        case .tomorrow, .date:
            guard var document = calendarDocument else { throw CocoaError(.fileReadCorruptFile) }
            let targetDate: Date
            if case .date(let key) = action {
                guard let date = PlanningDate.date(key, calendar: document.calendar) else { throw CocoaError(.coderInvalidValue) }
                targetDate = date
            } else {
                guard let date = PlanningDate.date(anchor, calendar: document.calendar),
                      let next = document.calendar.date(byAdding: .day, value: 1, to: date) else { throw CocoaError(.coderInvalidValue) }
                targetDate = next
            }
            var week = document.week(for: targetDate) ?? DatedPlanningWeek.make(for: targetDate, calendar: document.calendar)
            let targetID = week.prepareDay(targetDate)
            if week.id != live.collectionID || targetID != live.listID {
                let before = Set(week.collection.lists.first { $0.id == targetID }!.cards.map(\.id))
                document.upsert(week)
                let target = CardMoveDestination(collectionID: week.id, listID: targetID, title: week.rangeTitle, group: "Calendar")
                guard movePlanningCard(live.card, source: live.collectionID, destination: target, documentOverride: document),
                      let updated = calendarDocument?.weeks.first(where: { $0.id == week.id }),
                      let list = updated.collection.lists.first(where: { $0.id == targetID }),
                      let moved = list.cards.first(where: { !before.contains($0.id) && $0.createdAt == live.card.createdAt }) else { throw CocoaError(.fileWriteUnknown) }
                result = PlanningSearchResult(weekKey: updated.startKey, collectionID: updated.id, collectionTitle: updated.rangeTitle, listID: list.id, listTitle: list.title, card: moved)
            }
        case .complete, .archive:
            let dated = calendarDocument?.weeks.first { $0.id == live.collectionID }
            guard var owner = dated?.collection ?? collections.first(where: { $0.id == live.collectionID && $0.isActive }),
                  let index = owner.lists.firstIndex(where: { $0.id == live.listID && !$0.isArchived }),
                  let cardIndex = owner.lists[index].cards.firstIndex(where: { $0.id == live.card.id }) else { throw CocoaError(.fileNoSuchFile) }
            if action == .archive { owner.lists[index].archiveCard(id: live.card.id) }
            else {
                guard live.card.presentation == .card else { throw CocoaError(.coderInvalidValue) }
                owner.lists[index].cards[cardIndex].isTitleChecked = true
                result = PlanningSearchResult(weekKey: live.weekKey, collectionID: owner.id, collectionTitle: live.collectionTitle, listID: live.listID, listTitle: live.listTitle, card: owner.lists[index].cards[cardIndex])
            }
            if var week = dated, var document = calendarDocument {
                week.collection = owner; document.upsert(week)
                try PlanningCalendarStore.save(document)
                if week.startKey == document.currentWeekKey { try KanbanBoardPersistence.saveListsChecked(owner.lists) }
                calendarDocument = document
                if week.startKey == document.currentWeekKey { lists = owner.lists }
            } else {
                guard let index = collections.firstIndex(where: { $0.id == owner.id }) else { throw CocoaError(.fileNoSuchFile) }
                var updated = collections; updated[index] = owner
                try PersonalCollectionStore.saveChecked(updated)
                collections = updated
            }
        }
        return result
    }

    private func applyWeeklyReview(_ source: PlanningSearchResult, action: DailyReviewAction, draft: WeeklyReviewRecord, baseline: WeeklyReviewRecord?) -> WeeklyReviewRecord? {
        let oldDocument = calendarDocument, oldLists = lists, oldCollections = collections, oldSaved = savedCardIDs
        do {
            guard let live = planningCalendarAccess?.searchableItems.first(where: { $0.collectionID == source.collectionID && $0.card.id == source.card.id && $0.card.createdAt == source.card.createdAt }),
                  collections.contains(where: { $0.id == live.collectionID && $0.isActive && $0.kind == .list && $0.title == "In the Queue" }),
                  try WeeklyReviewStore.load().records[draft.id] == baseline,
                  !draft.decisions.contains(where: { $0.source.resolve(in: [live]) != nil }) else { throw DailyPlanStore.Failure.conflict }
            return try DailyReviewTransaction.perform {
                let result = try mutateReviewItem(live, action: action, anchor: draft.startKey)
                var updated = draft
                updated.decisions.append(DailyReviewDecision(source: DailyPlanPriority(live), result: DailyPlanPriority(result), action: action))
                if let index = updated.priorities.firstIndex(where: { $0.resolve(in: [live]) != nil }) { updated.priorities[index] = DailyPlanPriority(result) }
                return try WeeklyReviewStore.save(updated, replacing: baseline)
            }
        } catch {
            calendarDocument = oldDocument; lists = oldLists; collections = oldCollections; savedCardIDs = oldSaved
            if UserDefaults.standard.object(forKey: DailyReviewTransaction.key) != nil { workspaceRecoveryError = error.localizedDescription }
            return nil
        }
    }

    private func applyDailyReview(_ source: PlanningSearchResult, action: DailyReviewAction, draft: DailyPlan, baseline: DailyPlan?) -> DailyPlan? {
        let previousDocument = calendarDocument
        let previousLists = lists
        let previousCollections = collections
        let previousSaved = savedCardIDs
        do {
            guard let live = planningCalendarAccess?.searchableItems.first(where: {
                $0.collectionID == source.collectionID && $0.card.id == source.card.id && $0.card.createdAt == source.card.createdAt
            }), try DailyPlanStore.load().plans[draft.id] == baseline else { throw DailyPlanStore.Failure.conflict }
            return try DailyReviewTransaction.perform {
                let result = try mutateReviewItem(live, action: action, anchor: draft.id)
                var updatedPlan = draft
                let original = DailyPlanPriority(live)
                let destination = DailyPlanPriority(result)
                if let index = updatedPlan.priorities.firstIndex(where: { $0.resolve(in: [live]) != nil }) { updatedPlan.priorities[index] = destination }
                var review = updatedPlan.eveningReview ?? DailyEveningReview()
                guard !review.decisions.contains(where: { $0.source == original }) else { throw DailyPlanStore.Failure.conflict }
                review.decisions.append(DailyReviewDecision(source: original, result: destination, action: action))
                updatedPlan.eveningReview = review
                return try DailyPlanStore.save(updatedPlan, replacing: baseline)
            }
        } catch {
            calendarDocument = previousDocument; lists = previousLists; collections = previousCollections; savedCardIDs = previousSaved
            if UserDefaults.standard.object(forKey: DailyReviewTransaction.key) != nil { workspaceRecoveryError = error.localizedDescription }
            return nil
        }
    }

    private func movePriorityForVision(_ source: PlanningSearchResult, destination: WorkspaceListReference) -> PlanningSearchResult? {
        guard let live = planningCalendarAccess?.searchableItems.first(where: {
            $0.collectionID == source.collectionID && $0.card.id == source.card.id && $0.card.createdAt == source.card.createdAt
        }), let owner = collections.first(where: { $0.id == destination.ownerID && $0.isActive }),
              let target = owner.lists.first(where: { $0.id == destination.listID && !$0.isArchived }) else { return nil }
        let before = Set(target.cards.map(\.id))
        let route = CardMoveDestination(collectionID: owner.id, listID: target.id, title: owner.title, group: "Plans", columnTitle: target.title)
        guard movePlanningCard(live.card, source: live.collectionID, destination: route),
              let updatedOwner = collections.first(where: { $0.id == owner.id }),
              let updatedList = updatedOwner.lists.first(where: { $0.id == target.id }),
              let moved = updatedList.cards.first(where: { !before.contains($0.id) && $0.createdAt == live.card.createdAt }) else { return nil }
        return PlanningSearchResult(weekKey: nil, collectionID: owner.id, collectionTitle: updatedOwner.title,
                                    listID: updatedList.id, listTitle: updatedList.title, card: moved)
    }

    private func movePlanningCard(_ card: KanbanCard, source: UUID?, destination: CardMoveDestination,
                                  documentOverride: PlanningCalendarDocument? = nil) -> Bool {
        do {
            var document = documentOverride ?? calendarDocument
            let currentID = document?.weeks.first { $0.startKey == document?.currentWeekKey }?.id
            let normalizedSource = source == currentID ? nil : source
            let normalizedDestination = CardMoveDestination(collectionID: destination.collectionID == currentID ? nil : destination.collectionID,
                listID: destination.listID, title: destination.title, group: destination.group)
            var updatedWeek = lists
            var updatedSaved = savedCardIDs
            let dated = (document?.weeks ?? []).filter { $0.id != currentID }
            var combined = collections + dated.map(\.collection)
            try CrossBoardCardMovement.move(card, from: normalizedSource, to: normalizedDestination,
                week: &updatedWeek, collections: &combined, saved: &updatedSaved)
            let libraryIDs = Set(collections.map(\.id))
            let updatedLibrary = combined.filter { libraryIDs.contains($0.id) }
            if var next = document {
                for var week in next.weeks {
                    if week.id == currentID { week.collection.lists = updatedWeek; week.collection.savedCardIDs = updatedSaved }
                    else if let collection = combined.first(where: { $0.id == week.id }) { week.collection = collection }
                    next.upsert(week)
                }
                document = next
            }
            _ = try JSONEncoder().encode(updatedWeek)
            _ = try JSONEncoder().encode(updatedLibrary)
            if let document { _ = try JSONEncoder().encode(document); _ = try PlanningCalendarStore.load() }
            if let data = UserDefaults.standard.data(forKey: "Plenact.Board.v1") { _ = try JSONDecoder().decode([KanbanList].self, from: data) }
            if let data = UserDefaults.standard.data(forKey: "Plenact.PersonalCollections.v1") { _ = try JSONDecoder().decode([PersonalCollection].self, from: data) }
            let defaults = UserDefaults.standard
            let keys = [PlanningCalendarStore.key, "Plenact.Board.v1", "Plenact.PersonalCollections.v1", "Plenact.SavedCardIDs.v1"]
            let previous = keys.map { defaults.object(forKey: $0) }
            do {
                if let document { try PlanningCalendarStore.save(document) }
                try KanbanBoardPersistence.saveListsChecked(updatedWeek)
                try PersonalCollectionStore.saveChecked(updatedLibrary)
                SavedCardPersistence.save(updatedSaved)
            } catch {
                for (key, value) in zip(keys, previous) {
                    if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
                }
                throw error
            }
            calendarDocument = document
            lists = updatedWeek; collections = updatedLibrary; savedCardIDs = updatedSaved
            if normalizedSource != normalizedDestination.collectionID {
                TransferConfirmationPresenter.shared.show(TransferConfirmation(title: card.word, destination: destination.title))
            }
            return true
        } catch {
            DatabaseActivity.shared.report("Could not move this item: \(error.localizedDescription) Its content has been retained.")
            return false
        }
    }

    private var libraryTab: some View { /* Personal collection directory and creation actions */

        BoardListsView(
            retainedWeekLists:   lists + (calendarDocument?.weeks.flatMap { $0.collection.lists } ?? []),
            collections:         $collections,
            registerListNewNote: registerPersonalListNewNote,
            onOpenSaved:         openSavedDestination,
            onLoadExampleWeek:   loadExampleWeek,
            onUndoExampleWeek:   undoExampleWeek,
            onLoadExampleMonth: { confirmsExampleMonth = true },
            onRestoreUserData: { confirmsRestoreUserData = true },
            hasUserDataBackup: (try? FullMonthExampleStore.live().hasUserData) ?? false,
            savedPersonalCardTarget: savedPersonalCardTarget,
            onClearSavedPersonalCardTarget: { savedPersonalCardTarget = nil }
        )
        .tabItem {
            Label("Plans", systemImage: "books.vertical")
        }
        .tag(AppDestination.lists)
        .toolbar(.hidden, for: .tabBar)
    }

    private func switchMonthExample(restoring: Bool) {
        guard !isSwitchingWorkspace else { return }
        isRestoringWorkspace = restoring
        isSwitchingWorkspace = true
    }

    @MainActor
    private func performMonthExampleSwitch(restoring: Bool) async {
        // Runs only after the navigation tree has disappeared and flushed its saved state.
        do {
            guard var savedDocument = calendarDocument,
                  let currentIndex = savedDocument.weeks.firstIndex(where: { $0.startKey == savedDocument.currentWeekKey }) else { throw CocoaError(.fileReadCorruptFile) }
            savedDocument.weeks[currentIndex].collection.lists = lists
            savedDocument.weeks[currentIndex].collection.savedCardIDs = savedCardIDs
            try PlanningCalendarStore.save(savedDocument)
            calendarDocument = savedDocument
            try KanbanBoardPersistence.saveListsChecked(lists)
            try PersonalCollectionStore.saveChecked(collections)
            SavedCardPersistence.save(savedCardIDs)
            let store = try FullMonthExampleStore.live()
            let example = FullMonthExample.make(calendar: calendarDocument?.calendar ?? .current)
            try await Task.detached(priority: .userInitiated) {
                if restoring { try store.restoreUserData() }
                else { try store.loadExample(example) }
            }.value
            try reloadWorkspaceFromStorage()
            workspaceNotice = restoring
                ? "Your saved Plenact data and local files have been restored. Changes made while exploring the example month have been replaced."
                : "Your original Plenact data is saved offline on this device. Explore the example month, then return to Library + → Examples → Restore User Data to bring it back. Loading another example month will keep that original backup."
        } catch {
            if (try? FullMonthExampleStore.live().needsRecovery) == true {
                workspaceRecoveryError = error.localizedDescription
            }
            workspaceNotice = "The data switch could not finish: \(error.localizedDescription) Your saved data and any existing offline backup have been retained. Please retry."
        }
        isSwitchingWorkspace = false
    }

    private func reloadWorkspaceFromStorage() throws {
        let document = try PlanningCalendarStore.load()
        guard let current = document?.weeks.first(where: { $0.startKey == document?.currentWeekKey }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        calendarDocument = document
        lists = current.collection.lists
        savedCardIDs = SavedCardPersistence.load()
        collections = PersonalCollectionStore.load()
        profile = LocalProfileStore.load()
        displayedPlanningWeek = nil
        displayedPlanningListID = nil
        boardTargetListID = nil
        boardTargetCardID = nil
        savedPersonalCardTarget = nil
        activePersonalListNewNote = nil
        visibleNoteIDs = []
        selectedDestination = .lists
        workspaceGeneration = UUID()
    }

    private func recoverWorkspace() {
        isSwitchingWorkspace = true
        Task { @MainActor in
            do {
                try DailyReviewTransaction.recover()
                let store = try FullMonthExampleStore.live()
                try await Task.detached(priority: .userInitiated) { try store.recoverInterruptedSwitch() }.value
                try reloadWorkspaceFromStorage()
                workspaceRecoveryError = nil
            } catch { workspaceRecoveryError = error.localizedDescription }
            isSwitchingWorkspace = false
        }
    }

    private func loadExampleWeek() -> Bool {
        let todayListID = TodayListSelection.currentDayList(in: lists.filter { !$0.isArchived }, date: .now)?.id
        guard ExampleLoadUndoStore.save(lists: lists, todayListID: todayListID) else {
            DatabaseActivity.shared.report("Could not save the previous Week Board, so the example was not loaded.")
            return false
        }
        do {
            try KanbanBoardPersistence.saveListsChecked(SampleData.lists)
            lists = SampleData.lists
            return true
        } catch {
            DatabaseActivity.shared.report("Could not load the example Week Board: \(error.localizedDescription)")
            return false
        }
    }

    private func undoExampleWeek() -> Bool {
        guard let snapshot = ExampleLoadUndoStore.load() else {
            DatabaseActivity.shared.report("The saved Week Board snapshot could not be restored.")
            return false
        }
        do {
            try KanbanBoardPersistence.saveListsChecked(snapshot.lists)
            lists = snapshot.lists
            ExampleLoadUndoStore.clear()
            return true
        } catch {
            DatabaseActivity.shared.report("Could not restore the previous Week Board: \(error.localizedDescription)")
            return false
        }
    }


    ///
    /// @fcn        AppRootView.bottomNavigationBar
    /// @brief      Build the custom destination bar and central New control
    /// @details    Honors navigation-label preferences and remains anchored at the screen bottom
    ///             while the keyboard overlays it. The decorative background extends through the
    ///             bottom safe area independently of the measured controls. In portrait,
    ///             its top edge is inset 20 points so New overlaps it without moving any controls.
    ///             New requests Today capture, a Library Note, or a Week-card destination picker;
    ///             a long press arms Week-list creation and shake feedback
    ///
    /// @return     (some View) paper-backed navigation controls
    /// @post       Button and gesture callbacks update navigation and creation-request state
    ///
    private var bottomNavigationBar: some View { /* Shared tab and quick-creation controls */
        let layout = bottomToolbarLayout
        let isCompact = layout.horizontalLabels /* Landscape-height navigation layout */

        return ZStack(alignment: isCompact ? .center : .top) {
            HStack(spacing: layout.rowSpacing) {
                tabButton(.today, title: "Today", systemImage: "sun.max.fill")
                tabButton(.board, title: "Week", systemImage: "rectangle.3.group.fill")

                Color.clear
                    .frame(maxWidth: .infinity, minHeight: layout.tabMinimumHeight)
                    .accessibilityHidden(true)

                tabButton(.lists, title: "Plans", systemImage: "books.vertical.fill")
                tabButton(.saved, title: "Activity", systemImage: "clock.arrow.circlepath")
            }

            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, layout.topPadding)
            .padding(.bottom, layout.bottomPadding)
            .frame(maxWidth: .infinity)
            .offset(y: layout.tabsOffset)

            let newLayout = isCompact /* Adaptive arrangement of creation actions */
                ? AnyLayout(HStackLayout(spacing: layout.newLabelSpacing))
                : AnyLayout(VStackLayout(spacing: layout.newLabelSpacing))
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
                        .font(.system(size: layout.newIconSize, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-7))
                        .frame(width: layout.newButtonSize, height: layout.newButtonSize)
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
                        : "Creates a Note in the open personal List, or the most recently opened personal List from Plans. Touch and hold until New shakes, then release to add a Week list."
                )

                    if PlanPreferencesStore.load().showsNavigationLabels {

                        Text("New")
                            .font(.system(layout.labelStyle))
                            .foregroundStyle(.white.opacity(0.92))
                    }
            }

            .offset(y: layout.newOffset)
            .zIndex(2)
        }

        .frame(maxWidth: .infinity)
        .frame(height: bottomNavigationHeight, alignment: isCompact ? .center : .top)
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

            .padding(.top, layout.backgroundTopInset)
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

        let geometry = bottomToolbarLayout
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

            let layout = geometry.horizontalLabels /* Adaptive quick-creation action layout */
                ? AnyLayout(HStackLayout(spacing: geometry.tabLabelSpacing))
                : AnyLayout(VStackLayout(spacing: geometry.tabLabelSpacing))
            layout {

                Image(systemName: systemImage)
                    .font(.system(size: geometry.tabIconSize, weight: .semibold))

                if PlanPreferencesStore.load().showsNavigationLabels {

                    Text(title)
                        .font(.system(geometry.labelStyle))
                }
            }

            .frame(maxWidth: .infinity, minHeight: geometry.tabMinimumHeight)
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
        displayedPlanningWeek = nil

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

        guard !isSwitchingWorkspace, !candidates.isEmpty else {

            return
        }

        do {

            let persistedWeek = try UserDefaults.standard.data(forKey: "Plenact.Board.v1") /* Stored Week lists protecting referenced media */
                .map { try JSONDecoder().decode([KanbanList].self, from: $0) } ?? []
            let persistedCollections = try UserDefaults.standard.data(forKey: "Plenact.PersonalCollections.v1") /* Stored personal collections protecting referenced media */
                .map { try JSONDecoder().decode([PersonalCollection].self, from: $0) } ?? []
            let undo = try UserDefaults.standard.data(forKey: "Plenact.ExampleLoadUndo.v1") /* Stored example-load recovery snapshot */
                .map { try JSONDecoder().decode(ExampleLoadUndoSnapshot.self, from: $0) }
            let calendarLists = try PlanningCalendarStore.load()?.weeks.flatMap { $0.collection.lists } ?? []
            let retained = calendarLists + lists + collections.flatMap(\.lists) + persistedWeek /* All snapshots whose media must remain available */
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

        if var document = calendarDocument,
           var current = document.weeks.first(where: { $0.startKey == document.currentWeekKey }) {
            current.collection.lists = snapshot; current.collection.savedCardIDs = bookmarks
            document.upsert(current)
            try PlanningCalendarStore.save(document)
            calendarDocument = document
        }
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
        displayedPlanningWeek = nil

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
        displayedPlanningWeek = nil
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
        @discardableResult
        private func addCard(to listID: Int, title: String, description: String, subtitle: String, presentation: ItemPresentation? = nil, actions: [String]? = nil, attachments: [KanbanAttachment] = [], schedule: QuickCaptureSchedule? = nil, checkedSave: Bool = false) -> Bool {

            guard let listIndex = lists.firstIndex(where: { /* Destination list index */

                $0.id == listID
            }) else {

                return false
            }

            let nextCardID  = (lists.flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1 /* Board-wide next card ID */
            var updatedList = lists[listIndex] /* Mutable destination-list copy */

            var created = updatedList.makeItems(
                startingAt: nextCardID, titles: title, description: description.isEmpty ? nil : description,
                subtitle: subtitle, presentation: presentation, actions: actions
            )
            guard !created.isEmpty, schedule?.isValid() != false else { return false }
            for index in created.indices { schedule?.apply(to: &created[index]) }
            if !attachments.isEmpty { created[0].attachments = attachments; created[0].coverAttachmentID = attachments.first(where: { $0.kind == .photo })?.id }
            updatedList.cards.append(contentsOf: created)
            var updatedLists = lists
            updatedLists[listIndex] = updatedList
            if checkedSave || !attachments.isEmpty || schedule != nil {
                guard var document = calendarDocument,
                      let weekIndex = document.weeks.firstIndex(where: { $0.startKey == document.currentWeekKey }) else { return false }
                document.weeks[weekIndex].collection.lists = updatedLists
                do {
                    try DailyReviewTransaction.perform {
                        try PlanningCalendarStore.save(document)
                        try KanbanBoardPersistence.saveListsChecked(updatedLists)
                    }
                    calendarDocument = document
                } catch {
                    if UserDefaults.standard.object(forKey: DailyReviewTransaction.key) != nil {
                        workspaceRecoveryError = "The capture could not be saved. Retry recovery before continuing."
                    }
                    return false
                }
            }
            lists = updatedLists
            return true

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
    @AppStorage(PlanPreferencesStore.key) private var planPreferencesData = Data()
    @EnvironmentObject private var welcomeCue: TodayWelcomeCue
    @Environment(\.accessibilityReduceMotion) private var reduceWelcomeMotion
    @Environment(\.planningCalendarAccess) private var planningCalendarAccess
    private func calendarDayList(_ date: Date, in snapshot: [KanbanList]? = nil) -> KanbanList? {
        let lists = snapshot ?? self.lists
        if let id = planningCalendarAccess?.document.week(for: date)?.dayListIDs[PlanningDate.key(date)],
           let list = lists.first(where: { $0.id == id && !$0.isArchived }) { return list }
        return TodayListSelection.currentDayList(in: lists, date: date)
    }


    @Binding var lists:     [KanbanList]                    /* Shared local Board lists                           */
    @Binding var archivedLists: [KanbanList]                   /* Archived Week lists retained for example-load undo */
    @Binding var savedCardIDs: Set<Int>                     /* Device-local bookmarks used by card details        */
    let profile:            LocalProfile?                   /* Current local profile and preferences              */
    let onSaveProfile:      (LocalProfile)        -> Void   /* Save local identity and personalization            */
    let onRemoveProfile:    ()                    -> Void   /* Remove only local profile information              */
    let onAddCard: (Int, String, String, String, ItemPresentation?, [String]?) -> Void /* Create canonical Week records */
    let onAddCapture: (QuickCaptureSubmission) -> Bool
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
    @State private var openedFocusCard: KanbanCard?
    @State private var showsTodayList = false               /* Focused single-list presentation         */
    @State private var showsTodayPlan = false
    @AppStorage(TodayListPins.key) private var listPinData = Data()
    @State private var openedShortcut: WorkspaceListReference?

    @State private var focusedListID: Int?                  /* Current-day list selected when opening Focus */
    @State private var quickCaptureTitle    = ""            /* Draft title for inline card capture      */
    @State private var quickComposerInitialTitle = ""       /* Quick-capture title handed to full editor */
    @State private var showsQuickNoteEditor = false         /* Full-size quick card editor presentation */
    @State private var showsTemplates = false
    @State private var pendingTemplate: QuickCaptureTemplate?
    @State private var composerTemplate: QuickCaptureTemplate?
    @State private var captureAction: TodayCaptureAction?
    @State private var showsPlanSettings = false
    @State private var showsSearch          = false         /* Local Board search presentation          */
    @State private var presentComposerAfterListChoice = false /* Deferred center-plus request           */
    @State private var labelLibrary = LabelLibraryStore.load() /* Local categorized label definitions   */
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
    /// @fcn        TodayHomeView.todayHeader
    /// @brief      Build the Today title, current date, search, and profile controls
    /// @details    Presents accessible entry buttons for Board search and local Account & Settings
    ///             within the shared maximum content width
    ///
    /// @return     (some View) Today header content
    /// @post       Tapping controls updates sheet-presentation state without modifying Board data
    ///
    private var todayHeader: some View { /* Today's heading and account controls */

        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.largeTitle.weight(.bold))
                Button { showsTodayPlan = true } label: {
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(TodayWelcomeGlow(highlighted: UIDevice.current.userInterfaceIdiom != .pad && welcomeCue.highlights(.plan)))
                .accessibilityLabel("Today's Plan, " + Date.now.formatted(date: .complete, time: .omitted))
                .accessibilityHint("Opens your saved priorities and context for today")
                .accessibilityIdentifier("today.plan")
            }

            Spacer()

            Button {
                showsSearch = true
            } label: {
                WorkspaceHeaderIcon(systemName: "magnifyingglass")
            }

            .buttonStyle(.plain)
            .accessibilityLabel("Search Plenact")

            Button { showsPlanSettings = true } label: {
                WorkspaceHeaderIcon(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plan Settings")
            .accessibilityHint("Configure Today, planning, and templates")

            Button {
                showsAccountSettings = true
            } label: {
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
    private var todayHeaderPanel: some View { /* Styled container for Today's heading */

        todayHeader
            .padding(.horizontal, 20)
            .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? -22 : 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
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
    ) {

        self._lists          = lists
        self._archivedLists = archivedLists
        self._savedCardIDs   = savedCardIDs
        self.profile         = profile
        self.onSaveProfile   = onSaveProfile
        self.onRemoveProfile = onRemoveProfile
        self.onAddCard       = onAddCard
        self.onAddCapture = onAddCapture
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


    /// Pinned, owner-qualified list shortcuts chosen by the user and persisted across launches.
    private var yourShortcutsSection: some View {
        let owners = WorkspaceBrowseIndex.owners(document: planningCalendarAccess?.document, library: planningCalendarAccess?.library ?? [])
        let available = WorkspaceBrowseIndex.lists(in: owners)
        let pinned = TodayListPins.decode(listPinData).compactMap { reference in available.first { $0.reference == reference } }
        return TodayShortcutGrid(pinned: pinned, onOpen: { openedShortcut = $0 })
    }


    ///
    /// @fcn        TodayHomeView.browseListsAction
    /// @brief      Provide the Browse this week entry point
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
                Text("Browse this week")
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
    private func openQuickNoteEditor() {

        composerTemplate = nil
        captureAction = nil
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
    private func openCapture(_ action: TodayCaptureAction) {
        welcomeCue.cancel()
        composerTemplate = nil
        captureAction = action
        guard selectedTodayList != nil else {
            presentComposerAfterListChoice = true
            listPickerMode = .chooseToday
            return
        }
        presentQuickNoteEditor()
    }

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
        if let current = calendarDayList(.now) { selectedTodayListID = current.id; return }
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
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        TimelineView(.everyMinute) { context in
                            TodayPlanSummaryPanel(date: context.date, calendar: planningCalendarAccess?.document.calendar ?? .current,
                                sources: planningCalendarAccess?.searchableItems ?? [], welcomesPlan: welcomeCue.highlights(.plan), onOpen: { showsTodayPlan = true })
                                .padding(16)
                        }
                        // Reclaim the action row’s 52 points from the space before capture.
                        .padding(.bottom, -16)
                    }
                    VStack(spacing: 0) {
                        TodaySloganView()
                            .frame(minHeight: 40)
                        quickCaptureSection
                            .modifier(TodayPanelSurface(backgroundOpacity: 0.5))
                    }

                    // Capture the current binding value outside TimelineView so list edits
                    // invalidate its content as well as its minute-based date updates.
                    let focusLists = lists
                    TimelineView(.everyMinute) { context in
                        let focus = calendarDayList(context.date, in: focusLists) /* Active list matching the current weekday */
                        let cards = focus?.cards.filter { !$0.isSectionDivider } ?? [] /* Actionable records in the weekday list */

                        TodayFocusSection(
                            list:            focus,
                            cards:           cards,
                            openCards:       PlanPreferencesStore.load().todayFocusItems(in: cards),
                            onToggleCard:    { cardID in
                                if let focus { /* Weekday list available for navigation */

                                    onToggleCardCompletion(focus.id, cardID)
                                }
                            },
                            onOpenCard: { card in openedFocusCard = card },
                            onOpenTodayList: {
                                focusedListID = focus?.id
                                showsTodayList = focus != nil
                            }
                        )
                        .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in
                            ensureCurrentWeekdayList()
                        }
                    }
                    // A covered TimelineView can retain its last rendered completion state.
                    // Recreate the preview on return without resetting the outer Today scroll.
                    .id(showsTodayList || openedFocusCard != nil)

                    yourShortcutsSection
                    browseListsAction
                }
                        .padding(20)
                        // Restore the space reclaimed by removing capture’s heading and destination caption on iPhone.
                        .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 0 : 10)
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

                    .frame(maxWidth: .infinity)
                    .zIndex(1)
                }
            .task(id: welcomeCue.requestID) { await welcomeCue.play(reduceMotion: reduceWelcomeMotion, planPulseSpeed: UIDevice.current.userInterfaceIdiom == .pad ? 1 : 1.3) }
            .onDisappear { welcomeCue.cancel() }
            .onChange(of: reduceWelcomeMotion) { _, _ in welcomeCue.cancel() }
            .simultaneousGesture(TapGesture().onEnded { welcomeCue.cancel() })
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in welcomeCue.cancel() })
            .onChange(of: quickCaptureTitle) { _, _ in welcomeCue.cancel() }
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
            .fullScreenCover(item: $openedShortcut) { reference in
                WorkspacePinnedListView(reference: reference)
            }
            .sheet(isPresented: $showsTodayPlan) {
                TodayPlanView(calendar: planningCalendarAccess?.document.calendar ?? .current)
            }
            .sheet(isPresented: $showsAccountSettings) {

                AccountSettingsView(
                    profile:           profile,
                    lists:             lists,
                    onSave:            onSaveProfile,
                    onRemove:          onRemoveProfile
                )
            }

            .fullScreenCover(item: $openedFocusCard) { card in
                TodayFocusCardDetailView(card: card, lists: $lists, labelLibrary: $labelLibrary,
                    savedCardIDs: $savedCardIDs, currentUserName: profile?.displayName ?? "Justin Reina",
                    onDelete: onDeleteCard)
                    .environment(\.workspaceBottomBarHeight, 0)
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
                        onPermanentDelete: onDeleteCard,
                        focusesFirstUncheckedTask: true,
                        representedDate: .now,
                        includesDateInTitle: false
                    )
                    .environment(\.workspaceBottomBarHeight, 0)
                }
            }

            .sheet(isPresented: $showsQuickNoteEditor, onDismiss: {
                if !quickComposerInitialTitle.isEmpty && quickCaptureTitle.isEmpty {

                    quickCaptureTitle = quickComposerInitialTitle
                }

                quickComposerInitialTitle = ""
                composerTemplate = nil
                captureAction = nil
            }) {

                if let selectedTodayList { /* Current list receiving the Today edit */

                    QuickNoteComposer(
                        lists:         $lists,
                        initialListID: selectedTodayList.id,
                        initialTitle:  quickComposerInitialTitle,
                        template:      composerTemplate,
                        captureAction: captureAction,
                        onSaveCapture: { capture in
                            let saved = onAddCapture(capture)
                            if saved { quickComposerInitialTitle = "" }
                            return saved
                        }
                    ) { listID, title, description, subtitle, presentation, actions in
                        onAddCard(listID, title, description, subtitle, presentation, actions)
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
                captureAction = nil
                presentQuickNoteEditor()
            }) {
                QuickCaptureTemplatesView { template in
                    pendingTemplate = template
                    showsTemplates = false
                }
            }

            .modifier(PlanningSharedSearchPresentation(isPresented: $showsSearch))
            .sheet(isPresented: $showsPlanSettings) {
                PlanSettingsView(lists: lists, onSaveProfile: onSaveProfile)
            }


            .onAppear {
                labelLibrary = LabelLibraryStore.load()
                ensureCurrentWeekdayList()
            }

            .onChange(of: quickCreateRequest) { _, _ in
                openQuickNoteEditor()
            }

            .onChange(of: lists) { _, _ in
                ensureCurrentWeekdayList()
                if showsTodayList { focusedListID = calendarDayList(.now)?.id }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                ensureCurrentWeekdayList()
                if showsTodayList { focusedListID = calendarDayList(.now)?.id }
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
    /// @details    Disables submission for whitespace-only titles and prompts for a missing
    ///             destination. The field's accessibility hint identifies the selected Today list
    ///
    /// @return     (some View) title field, composer button, and quick-add controls
    /// @post       Submission and selection actions delegate to the Today capture helpers
    ///
    private var quickCaptureSection: some View { /* Inline capture controls for the selected list */

        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 8) {

                Button {
                    showsTemplates = true
                } label: {
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
                    .accessibilityHint(selectedTodayList.map { "Adds to \($0.title)." } ?? "Choose today's list before adding a card.")
                    .offset(x: -31)

                HStack(spacing: 0) {

                    Button(action: addQuickCard) {

                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }

                    .offset(x: 35)
                    .buttonStyle(.plain)
                    .disabled(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add card to today's list")

                    Button(action: openQuickNoteEditor) {

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
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .allowsHitTesting(false)
            }

            TodayCaptureActions(onSelect: openCapture)

            if selectedTodayList == nil { /* Keep an explicit way to choose a missing destination */

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
struct ContentCreationKindPicker: View {
    @Binding var presentation: ItemPresentation
    var body: some View {
        Picker("Create as", selection: $presentation) {
            Label("Card", systemImage: "rectangle").tag(ItemPresentation.card)
            Label("Note", systemImage: "note.text").tag(ItemPresentation.note)
        }.pickerStyle(.segmented).accessibilityLabel("Create as Card or Note")
    }
}

enum TodayCaptureAction: String, CaseIterable, Identifiable {
    case note, checklist, photo, voice, drawing
    var id: Self { self }
    var title: String { switch self { case .note: "Note"; case .checklist: "Checklist"; case .photo: "Photo"; case .voice: "Voice"; case .drawing: "Drawing" } }
    var symbol: String { switch self { case .note: "square.and.pencil"; case .checklist: "checklist"; case .photo: "camera"; case .voice: "mic"; case .drawing: "pencil.tip.crop.circle.badge.plus" } }
    var presentation: ItemPresentation { self == .note ? .note : .card }
}

struct TodayCaptureActions: View {
    let onSelect: (TodayCaptureAction) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(TodayCaptureAction.allCases) { action in
                Button { onSelect(action) } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 19))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Capture " + action.title.lowercased())
            }
        }
    }
}

struct QuickCaptureSchedule: Equatable {
    var start: Date?
    var stop: Date?
    var includesTime = false
    func isValid(calendar: Calendar = .current) -> Bool {
        guard let start, let stop else { return true }
        return includesTime ? stop >= start : calendar.startOfDay(for: stop) >= calendar.startOfDay(for: start)
    }
    func apply(to card: inout KanbanCard, calendar: Calendar = .current) {
        let kind: CardDateKind = includesTime ? .dateAndTime : .date
        card.startDate = start.map { kind.normalized($0, calendar: calendar) }
        card.dueDate = stop.map { kind.normalized($0, calendar: calendar) }
        card.startDateKind = kind; card.dueDateKind = kind
    }
}

struct QuickCaptureSubmission {
    let listID: Int
    let title: String
    let body: String
    let subtitle: String
    let presentation: ItemPresentation
    let actions: [String]?
    let attachments: [KanbanAttachment]
    let schedule: QuickCaptureSchedule?
}

enum VoiceCaptureSaveOption: String, CaseIterable, Identifiable {
    case audio = "Audio", text = "Text", both = "Both"
    var id: Self { self }
    var savesAudio: Bool { self != .text }
    var savesText: Bool { self != .audio }
    func body(existing: String, transcript: String) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard savesText, !text.isEmpty else { return existing }
        let result = NSMutableAttributedString(attributedString: PlanRichText.attributed(existing))
        result.append(NSAttributedString(string: (result.length == 0 ? "" : "\n\n") + text))
        return PlanRichText.encode(result)
    }
}

@MainActor
final class QuickCaptureVoice: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var recordingURL: URL?
    @Published var transcript = ""
    @Published var errorMessage: String?
    private var recorder: AVAudioRecorder?
    private var speechTask: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var generation = 0

    func start() async {
        guard !isStarting, !isRecording else { return }
        isStarting = true
        let permissionToken = generation
        NotificationCenter.default.post(name: Notification.Name("Plenact.StopAudioPreview"), object: nil)
        defer { isStarting = false }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { errorMessage = "Microphone access is unavailable. You can allow it in Settings → Plenact."; return }
        guard !Task.isCancelled, permissionToken == generation else { return }
        cleanup()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-voice-" + UUID().uuidString + ".m4a")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            recorder.delegate = self
            guard recorder.record(forDuration: 60) else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder; recordingURL = url; isRecording = true
        } catch {
            try? FileManager.default.removeItem(at: url)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            errorMessage = "Recording couldn't start. Your draft is still here; please try again."
        }
    }
    func stop() {
        guard isRecording else { return }
        recorder?.stop(); recorder = nil; isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording, self.recordingURL == recorder.url else { return }
            self.stop()
            if !flag { self.errorMessage = "Recording was interrupted. Preview the recording before saving." }
        }
    }
    func transcribe() async {
        guard let url = recordingURL, !isRecording, !isTranscribing else { return }
        isTranscribing = true; errorMessage = nil
        generation += 1
        let token = generation
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled, token == generation, recordingURL == url else { return }
        guard status == .authorized else {
            isTranscribing = false
            errorMessage = "Speech recognition is unavailable. You can enable it in Settings, keep the recording as Audio, or enter the transcript yourself."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            isTranscribing = false; errorMessage = "Speech recognition isn't available right now. Retry later or save Audio instead."; return
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let text { self.transcript = text }
                if final || failed {
                    self.generation += 1
                    self.isTranscribing = false; self.speechTask = nil; self.timeout?.cancel()
                    if failed && !final { self.errorMessage = "Transcription couldn't finish. Review any text below, retry, or save Audio instead." }
                }
            }
        }
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.generation == token, self.isTranscribing else { return }
            self.cancelTranscription()
            self.errorMessage = "Transcription took too long. Retry, enter text yourself, or save Audio instead."
        }
    }
    func cancelTranscription() {
        generation += 1; speechTask?.cancel(); speechTask = nil
        timeout?.cancel(); timeout = nil; isTranscribing = false
    }
    func audioData() throws -> Data {
        guard let recordingURL, !isRecording else { throw CocoaError(.fileReadNoSuchFile) }
        return try Data(contentsOf: recordingURL)
    }
    func cleanup() {
        cancelTranscription(); stop()
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil; transcript = ""
    }
}

struct QuickCapturePhoto: Identifiable {
    let id = UUID()
    let data: Data
    let fileExtension: String
    var image: UIImage? { UIImage(data: data) }
}

/// Store media only on explicit Add; a failed handoff removes just this draft's files.
@MainActor
enum QuickCaptureMediaCommit {
    static func save(_ photos: [QuickCapturePhoto], audio: Data? = nil, drawings: [DrawingCaptureDraft] = [], commit: ([KanbanAttachment]) -> Bool) throws -> Bool {
        var saved: [KanbanAttachment] = []
        do {
            for photo in photos {
                guard photo.image != nil else { throw CocoaError(.fileReadCorruptFile) }
                saved.append(try CardAttachmentStore.saveMedia(photo.data, kind: .photo, fileExtension: photo.fileExtension))
            }
            for drawing in drawings { saved.append(try DrawingAttachmentStore.save(drawing)) }
            if let audio {
                guard !audio.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                saved.append(try CardAttachmentStore.saveMedia(audio, kind: .audio, fileExtension: "m4a"))
            }
            if commit(saved) { return true }
            try CardAttachmentStore.removeDeletedFiles(Set(saved.flatMap(\.storedFileNames)), keeping: [])
            return false
        } catch {
            try? CardAttachmentStore.removeDeletedFiles(Set(saved.flatMap(\.storedFileNames)), keeping: [])
            throw error
        }
    }
}

struct QuickCaptureCamera: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: QuickCaptureCamera
        init(parent: QuickCaptureCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            parent.dismiss()
        }
    }
}

struct QuickNoteComposer: View {

    @Binding var lists: [KanbanList]                         /* Current destination lists */
    let onSave: (Int, String, String, String, ItemPresentation?, [String]?) -> Void
    let template: QuickCaptureTemplate?
    let captureAction: TodayCaptureAction?
    let onSaveCapture: ((QuickCaptureSubmission) -> Bool)?
    @State private var drawings: [DrawingCaptureDraft] = []
    @State private var drawingToEdit: DrawingCaptureDraft?
    @State private var offeredDrawing = false
    @State private var photos: [QuickCapturePhoto] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsPhotoSources = false
    @State private var showsPhotoLibrary = false
    @State private var showsCamera = false
    @State private var offeredPhotoSources = false
    @State private var importingPhotos = false
    @State private var mediaError: String?
    @StateObject private var voice = QuickCaptureVoice()
    @State private var voiceSaveOption: VoiceCaptureSaveOption = .both
    @State private var replaceRecording = false
    @State private var hasStartDate = false
    @State private var hasStopDate = false
    @State private var startDate = Date.now
    @State private var stopDate = Date.now
    @State private var includesDateTime = false
    @Environment(\.scenePhase) private var scenePhase
    private var schedule: QuickCaptureSchedule {
        QuickCaptureSchedule(start: hasStartDate ? startDate : nil, stop: hasStopDate ? stopDate : nil, includesTime: includesDateTime)
    }
    private var voiceReady: Bool {
        guard captureAction == .voice else { return true }
        return !voice.isStarting && !voice.isRecording && !voice.isTranscribing
            && (!voiceSaveOption.savesAudio || voice.recordingURL != nil)
            && (!voiceSaveOption.savesText || !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Environment(\.dismiss) private var dismiss /* Close the full-size editor */

    @State private var presentation: ItemPresentation
    @State private var createdAt = Date.now
    @State private var subtitle = ""
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
        captureAction: TodayCaptureAction? = nil,
        onSaveCapture: ((QuickCaptureSubmission) -> Bool)? = nil,
        onSave: @escaping (Int, String, String, String, ItemPresentation?, [String]?) -> Void
    ) {

        _lists = lists
        _presentation = State(initialValue: captureAction?.presentation ?? template?.presentation ?? lists.wrappedValue.first(where: { $0.id == initialListID })?.newItemPresentation ?? .card)
        _title = State(initialValue: template?.draftTitle(capturedTitle: initialTitle) ?? initialTitle)
        _description = State(initialValue: template?.body ?? "")
        _actions = State(initialValue: captureAction == .checklist ? [KanbanChecklistItem(title: "")] : (template?.actions ?? []).map { KanbanChecklistItem(title: $0) })
        _selectedListID = State(initialValue: initialListID)
        self.template = template
        self.captureAction = captureAction
        self.onSaveCapture = onSaveCapture
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
    private var destinationPicker: some View {
        Picker("List", selection: $selectedListID) {
            Text("Choose a list").tag(nil as Int?)
            ForEach(lists) { list in Text(list.title).tag(Optional(list.id)) }
        }.pickerStyle(.menu)
    }

    private var drawingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(drawings) { drawing in
                HStack {
                    Button { drawingToEdit = drawing } label: {
                        Image(uiImage: drawing.preview).resizable().scaledToFit().frame(maxHeight: 150)
                    }.buttonStyle(.plain).accessibilityLabel("Edit drawing")
                    Button("Remove drawing", systemImage: "trash", role: .destructive) { drawings.removeAll { $0.id == drawing.id } }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
            }
            Button("Add drawing", systemImage: "pencil.tip") { drawingToEdit = DrawingCaptureDraft() }
                .frame(minHeight: 44).disabled(drawings.count >= 6)
            Text("Drawings stay editable. Tap a preview to edit or export it. They are attached when you tap Add.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var dateControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Start date", isOn: $hasStartDate)
            if hasStartDate {
                DatePicker("Start", selection: $startDate, displayedComponents: includesDateTime ? [.date, .hourAndMinute] : [.date])
            }
            Toggle("Stop date", isOn: $hasStopDate)
            if hasStopDate {
                DatePicker("Stop", selection: $stopDate, displayedComponents: includesDateTime ? [.date, .hourAndMinute] : [.date])
            }
            Toggle("Include times", isOn: $includesDateTime)
            Text("Both dates are optional. Stop sets the item's due date, so it appears in Calendar.")
                .font(.caption).foregroundStyle(.secondary)
            if !schedule.isValid() { Text("Stop must be on or after Start.").foregroundStyle(.red) }
        }
    }
    private var voiceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Save as", selection: $voiceSaveOption) {
                ForEach(VoiceCaptureSaveOption.allCases) { option in Text(option.rawValue).tag(option) }
            }.pickerStyle(.segmented)
            if voice.isRecording {
                Label("Recording · up to 60 seconds", systemImage: "record.circle").foregroundStyle(.red)
                Button("Stop recording", systemImage: "stop.circle") { voice.stop() }.frame(minHeight: 44)
            } else {
                Button(voice.recordingURL == nil ? "Record a thought" : "Record again", systemImage: "mic") {
                    if voice.recordingURL != nil { replaceRecording = true }
                    else { Task { await voice.start() } }
                }.frame(minHeight: 44).disabled(voice.isStarting || voice.isTranscribing)
                if voice.isStarting { ProgressView("Preparing microphone…") }
                if let url = voice.recordingURL { AudioAttachmentPlayer(url: url) }
            }
            if voiceSaveOption.savesText {
                if voice.isTranscribing {
                    ProgressView("Transcribing…")
                    Button("Cancel transcription") { voice.cancelTranscription() }
                } else if voice.recordingURL != nil {
                    Button(voice.transcript.isEmpty ? "Transcribe recording" : "Transcribe again", systemImage: "text.bubble") { Task { await voice.transcribe() } }
                        .disabled(voice.isRecording)
                }
                TextField("Transcript · review or edit before saving", text: $voice.transcript, axis: .vertical).textInputAutocapitalization(.sentences)
                    .lineLimit(3...10).disabled(voice.isRecording || voice.isTranscribing)
            }
            if let error = voice.errorMessage { Text(error).font(.callout).foregroundStyle(.secondary) }
            Text("Audio keeps the recording; Text adds your reviewed transcript to the item's writing; Both keeps each. Transcription uses Apple’s speech recognition and may need an internet connection. Nothing is added to your List until you tap Add.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var photoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if importingPhotos { ProgressView("Preparing photos…") }
            ForEach(photos) { photo in
                HStack {
                    if let image = photo.image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 140)
                            .accessibilityLabel("Photo to attach")
                    }
                    Button("Remove photo", systemImage: "trash", role: .destructive) { photos.removeAll { $0.id == photo.id } }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
            }
            Button("Add photo", systemImage: "camera") { showsPhotoSources = true }
                .frame(minHeight: 44).disabled(importingPhotos || photos.count >= 6)
            Text("Photos are attached when you tap Add. Cancelling leaves your original Quick capture title in place.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @MainActor private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            mediaError = "A camera isn't available on this device. Choose Photo library instead."
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        if allowed { showsCamera = true }
        else { mediaError = "Camera access is unavailable. You can allow it in Settings → Plenact, or choose Photo library." }
    }
    @MainActor private func importPhotos() async {
        guard !photoSelection.isEmpty else { return }
        importingPhotos = true
        defer { importingPhotos = false; photoSelection = [] }
        do {
            for item in photoSelection.prefix(max(0, 6 - photos.count)) {
                guard let data = try await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else { throw CocoaError(.fileReadCorruptFile) }
                try Task.checkCancellation()
                photos.append(QuickCapturePhoto(data: data, fileExtension: item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"))
            }
        } catch is CancellationError { return }
        catch { mediaError = "Some photos couldn't be prepared. Your draft and any photos already added are still here." }
    }

    var body: some View { /* New-card form and destination controls */

        NavigationStack {
            VStack(spacing: 0) {
                ContentCreationKindPicker(presentation: $presentation).padding(.horizontal, 20).padding(.vertical, 12)
                if presentation == .note {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            destinationPicker
                            TextField("Note title", text: $title, axis: .vertical).textInputAutocapitalization(.sentences)
                                .font(.largeTitle.weight(.bold))
                            NoteCreationDateLabel(createdAt: createdAt)
                            if captureAction == .photo { photoControls }
                            if captureAction == .voice { voiceControls }
                            if captureAction == .drawing { drawingControls }
                            if onSaveCapture != nil {
                                DisclosureGroup("Start and stop dates") { dateControls }
                            }
                            RichTextEditor(placeholder: "Start writing...", text: $description, minimumHeight: 320)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }.background(Color(.systemGroupedBackground))
                } else {
            Form {
                Section(presentation.title) {
                    TextField("Title", text: $title, axis: .vertical).textInputAutocapitalization(.sentences)
                        .lineLimit(1...6)
                    TextField("Subtitle (optional)", text: $subtitle).textInputAutocapitalization(.sentences)
                    RichTextEditor(placeholder: "Details (optional)", text: $description)
                }

                if (template != nil || captureAction == .checklist || !actions.isEmpty) && presentation == .card {
                    Section("Actions") {
                        ForEach($actions) { $action in
                            TextField("Action", text: $action.title).textInputAutocapitalization(.sentences)
                        }
                        .onDelete { actions.remove(atOffsets: $0) }
                        Button("Add action", systemImage: "plus") {
                            actions.append(KanbanChecklistItem(title: ""))
                        }
                    }
                }

                if captureAction == .photo { Section("Photos") { photoControls } }
                if captureAction == .voice { Section("Voice capture") { voiceControls } }
                if captureAction == .drawing { Section("Drawings") { drawingControls } }
                if onSaveCapture != nil {
                    Section("Dates") {
                        DisclosureGroup("Start and stop dates") { dateControls }
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
                        let originalBody = presentation == .note ? description : description.trimmingCharacters(in: .whitespacesAndNewlines)
                        let body = captureAction == .voice ? voiceSaveOption.body(existing: originalBody, transcript: voice.transcript) : originalBody
                        let actionTitles: [String]? = template != nil || captureAction == .checklist ? editedActions : nil
                        if let onSaveCapture {
                            guard voiceReady, schedule.isValid() else { return }
                            do {
                                let audio = captureAction == .voice && voiceSaveOption.savesAudio ? try voice.audioData() : nil
                                guard try QuickCaptureMediaCommit.save(photos, audio: audio, drawings: drawings, commit: { attachments in
                                    onSaveCapture(QuickCaptureSubmission(listID: selectedListID, title: trimmedTitle, body: body,
                                        subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines), presentation: presentation,
                                        actions: actionTitles, attachments: attachments, schedule: hasStartDate || hasStopDate ? schedule : nil))
                                }) else { mediaError = "This capture could not be saved. Your draft is still open; check its List and try again."; return }
                            } catch { mediaError = "Your capture couldn't be saved. Your draft is still open; please try again."; return }
                        } else {
                            onSave(selectedListID, trimmedTitle, body, subtitle.trimmingCharacters(in: .whitespacesAndNewlines), presentation, actionTitles)
                        }
                        dismiss()
                    }

                    .disabled(importingPhotos || !voiceReady || !schedule.isValid() || trimmedTitle.isEmpty || selectedListID == nil || !lists.contains(where: { $0.id == selectedListID }))
                }
            }
        }

        .task {
            if captureAction == .drawing && !offeredDrawing { offeredDrawing = true; drawingToEdit = DrawingCaptureDraft() }
            if captureAction == .photo && !offeredPhotoSources { offeredPhotoSources = true; showsPhotoSources = true }
        }
        .sheet(item: $drawingToEdit) { draft in
            DrawingCaptureEditor(initial: draft) { updated in
                if let index = drawings.firstIndex(where: { $0.id == updated.id }) { drawings[index] = updated }
                else { drawings.append(updated) }
                return true
            }
        }
        .confirmationDialog("Add a photo", isPresented: $showsPhotoSources, titleVisibility: .visible) {
            Button("Take photo") { Task { await openCamera() } }
            Button("Photo library") { showsPhotoLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showsPhotoLibrary, selection: $photoSelection, maxSelectionCount: max(1, 6 - photos.count), matching: .images)
        .task(id: photoSelection) { await importPhotos() }
        .sheet(isPresented: $showsCamera) {
            QuickCaptureCamera { image in
                if let data = image.jpegData(compressionQuality: 0.9) { photos.append(QuickCapturePhoto(data: data, fileExtension: "jpg")) }
                else { mediaError = "This photo couldn't be prepared. Please try again." }
            }.ignoresSafeArea()
        }
        .onChange(of: voice.isRecording) { wasRecording, recording in
            if wasRecording && !recording && voice.recordingURL != nil && voiceSaveOption.savesText && scenePhase == .active {
                Task { await voice.transcribe() }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { voice.stop() } }
        .onChange(of: voiceSaveOption) { _, option in if !option.savesText { voice.cancelTranscription() } }
        .onDisappear { voice.cleanup() }
        .interactiveDismissDisabled(voice.isRecording || voice.isStarting || voice.isTranscribing)
        .confirmationDialog("Replace this recording and transcript?", isPresented: $replaceRecording, titleVisibility: .visible) {
            Button("Record again", role: .destructive) { Task { await voice.start() } }
            Button("Keep recording", role: .cancel) {}
        }
        .alert("Capture not saved", isPresented: Binding(get: { mediaError != nil }, set: { if !$0 { mediaError = nil } })) {
            Button("OK", role: .cancel) { mediaError = nil }
        } message: { Text(mediaError ?? "") }
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
    let onSave: (UUID, String, String, String, Date, ItemPresentation) throws -> Void /* Checked Note creation callback */

    @Environment(\.dismiss) private var dismiss /* Composer dismissal action */
    @FocusState private var focusedField: Field? /* Input currently receiving keyboard focus */
    @State private var presentation: ItemPresentation = .note
    @State private var subtitle = ""
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
        onSave: @escaping (UUID, String, String, String, Date, ItemPresentation) throws -> Void
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

            try draft.save(in: availablePersonalLists) { destinationID, title, body, createdAt in
                try onSave(destinationID, title, body, subtitle, createdAt, presentation)
            }
            dismiss()
        } catch {

            DatabaseActivity.shared.report("Could not save the \(presentation.title): \(error.localizedDescription) The draft remains open.")
        }
    }

    private var destinationMenu: some View {
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

    }

    var body: some View { /* Note draft editor and destination picker */

        NavigationStack {
            VStack(spacing: 0) {
                ContentCreationKindPicker(presentation: $presentation).padding(.horizontal, 20).padding(.vertical, 12)
                if presentation == .card {
                    Form {
                        Section("Card") {
                            TextField("Title", text: $draft.title, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(1...6)
                            TextField("Subtitle (optional)", text: $subtitle).textInputAutocapitalization(.sentences)
                            RichTextEditor(placeholder: "Details (optional)", text: $draft.body)
                        }
                        Section("Add to") { destinationMenu }
                    }
                } else {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                destinationMenu
                TextField("Note title", text: $draft.title, axis: .vertical).textInputAutocapitalization(.sentences)
                    .font(.largeTitle.weight(.bold))
                    .focused($focusedField, equals: .title)
                    .accessibilityLabel("Note title")

                NoteCreationDateLabel(createdAt: draft.createdAt)
                    .accessibilityIdentifier("library.newNoteCreationDate")

                RichTextEditor(placeholder: "Start writing...", text: $draft.body,
                               focus: Binding(get: { focusedField == .body }, set: { focusedField = $0 ? .body : nil }), minimumHeight: 320)
                    .accessibilityLabel("Note body")

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color(.systemGroupedBackground))
                }
            }
            .onChange(of: presentation) { _, _ in focusedField = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.canSave(in: availablePersonalLists))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .title {

                        Spacer()
                        Button("Done") { focusedField = nil }
                    }
                }
            }
            .navigationTitle("New " + presentation.title)
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
    var ownerID: UUID? = nil
    var weekKey: String? = nil
    var ownerTitle: String? = nil

    ///
    /// @fcn        TodaySearchResult.id
    /// @brief      Identify a result within its containing list
    /// @details    Combines the list ID with a card ID or a list-result marker
    ///
    /// @return     (String) composite result identity
    /// @post       Result contents remain unchanged
    ///
    var id: String { "\(ownerID?.uuidString ?? "week"):\(listID):\(cardID.map(String.init) ?? "list")" } /* Composite search-result identity */
}


///
/// Limits local search to supported kinds of Board content
///
/// @section    Purpose
///     Supply stable picker choices for the Today search screen
///
enum TodaySearchScope: String, CaseIterable, Identifiable {
    case all = "All"
    case boards = "Lists"
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
                let commentText = card.comments.flatMap { [$0.author, PlanRichText.plain($0.body)] } /* Searchable discussion authors and content */
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
                        searchableText = [list.title, card.word, PlanRichText.plain(card.descriptionOverride ?? ""), card.subtitleOverride ?? ""]
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
                        detail = [card.subtitleOverride, card.descriptionOverride.map { PlanRichText.plain($0) }].compactMap { $0 }
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
struct TodaySearchView: View {

    let lists: [KanbanList] /* Current locally stored Board snapshot */
    let onOpenBoardList: (Int) -> Void /* Navigate to a result's containing list */
    let onOpenBoardCard: (Int, Int) -> Void /* Route to a Week card by list/card IDs */
    let onArchiveCard: (Int) -> Void /* Canonical Week archive */
    let onDeleteCard: (Int) -> Bool /* Confirmed canonical Week deletion result */
    let onArchiveList: (Int) -> Void /* Canonical Week list archive */
    let onDeleteList: (Int) -> Bool /* Confirmed canonical list deletion result */

    var resultProvider: ((String, TodaySearchScope, LabelLibrary) -> [TodaySearchResult])? = nil
    var onSelectResult: ((TodaySearchResult) -> Void)? = nil

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
        resultProvider?(query, scope, labelLibrary)
            ?? TodaySearchIndex.results(query: query, scope: scope, lists: lists, library: labelLibrary)
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

                    TextField(resultProvider == nil ? "Find in your Week" : "Find in Plenact", text: $query)
                        .focused($searchFieldFocused)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityLabel("Search Plenact")
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
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.top)
                Text(resultProvider == nil ? "Your Week · Cards, notes, and lists" : "Your Plenact · Today, Week, and Plans")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.top, 8).padding(.bottom, 12)

                Text("Search by").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 6)
                Picker("Search by", selection: $scope) {
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

                            if let onSelectResult { onSelectResult(result) }
                            else if let cardID = result.cardID { /* Matching card identity for direct navigation */

                                onOpenBoardCard(result.listID, cardID)
                            } else {
                                onOpenBoardList(result.listID)
                            }

                            if onSelectResult == nil { dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.cardTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text([result.ownerTitle, result.listTitle, result.detail.isEmpty ? nil : result.detail].compactMap { $0 }.joined(separator: " · "))
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
                        .modifier(SharedSearchLifecycleActions(
                            enabled: resultProvider == nil,
                            title: result.cardTitle, kind: result.cardID == nil ? "List" : "Card",
                            onArchive: {
                                if let id = result.cardID { /* Card identity targeted by the search action */

                                    onArchiveCard(id)
                                } else {
                                    onArchiveList(result.listID)
                                }
                            },
                            onDelete: {
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
            .navigationTitle(resultProvider == nil ? "Search your Week" : "Search Plenact")
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
struct LibraryRecentItem: Codable, Equatable, Identifiable {
    let collectionID: UUID
    let cardID: Int
    var id: String { "\(collectionID.uuidString).\(cardID)" }
}

enum LibraryRecentStore {
    static let key = "Plenact.LibraryRecents.v1"
    static func load(from defaults: UserDefaults = .standard) -> [LibraryRecentItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([LibraryRecentItem].self, from: data)) ?? []
    }
    static func remember(_ item: LibraryRecentItem, defaults: UserDefaults = .standard) -> [LibraryRecentItem] {
        ActivityRecentStore.remember(item, defaults: defaults)
        let items = Array(([item] + load(from: defaults).filter { $0 != item }).prefix(8))
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
        return items
    }
}

enum ActivityRecentStore {
    static let key = "Plenact.ActivityRecents.v1"
    static func load(from defaults: UserDefaults = .standard) -> [LibraryRecentItem] {
        guard let data = defaults.data(forKey: key) else { return LibraryRecentStore.load(from: defaults) }
        return (try? JSONDecoder().decode([LibraryRecentItem].self, from: data)) ?? []
    }
    static func remember(_ item: LibraryRecentItem, defaults: UserDefaults = .standard) {
        let items = Array(([item] + load(from: defaults).filter { $0 != item }).prefix(20))
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
    static func clear(defaults: UserDefaults = .standard) {
        defaults.set(Data("[]".utf8), forKey: key)
        defaults.set(Data("[]".utf8), forKey: LibraryRecentStore.key)
    }
}

enum LibraryBrowseFilter: String, CaseIterable, Identifiable {
    case all = "All", lists = "Lists", boards = "Boards", labels = "Labels", examples = "Examples", templates = "Templates", help = "Help"
    var id: String { rawValue }
    var searchPrompt: String {
        switch self {
        case .all: "Find in your Plans"
        case .lists: "Find in your Lists"
        case .boards: "Find in your Boards"
        case .labels: "Find in your Labels"
        case .templates: "Find in Templates"
        case .examples: "Find in Examples"
        case .help: "Find in Help"
        }
    }
    var symbol: String {
        switch self { case .all: "books.vertical"; case .lists: "list.bullet"; case .boards: "rectangle.split.3x1"; case .labels: "tag"; case .templates: "square.stack.3d.up"; case .examples: "sparkles"; case .help: "questionmark.circle" }
    }
    var accent: Color {
        switch self { case .all: .blue; case .lists: .teal; case .boards: .indigo; case .labels: .purple; case .templates: .orange; case .examples: .pink; case .help: .teal }
    }
    var browsesCollections: Bool { self == .all || self == .lists || self == .boards }
    var searchHint: String {
        switch self {
        case .templates: "Search saved routines and template starting points"
        case .examples: "Search example names, descriptions, and previews"
        case .help: "Search help titles and instructions"
        case .labels: "Search labels assigned to active items"
        default: "Search your personal collections, cards, and notes"
        }
    }
    var searchContext: String {
        switch self {
        case .templates: "Templates · Routines and reusable starting points"
        case .examples: "Examples · Explore before adding"
        case .help: "Help · Guides and reference"
        case .labels: "Labels · Active cards across Week and Plans"
        default: "Your Plans · Collections, cards, and notes"
        }
    }
    func includes(_ collection: PersonalCollection) -> Bool {
        collection.isActive && browsesCollections && (self == .all || (self == .lists ? collection.kind == .list : collection.kind == .board))
    }
}

enum LibrarySearchIndex {
    static func results(query: String, collections: [PersonalCollection], labels: LabelLibrary) -> [TodaySearchResult] {
        collections.filter(\.isActive).flatMap { collection in
            TodaySearchIndex.results(query: query, scope: .all, lists: collection.lists.filter { !$0.isArchived }, library: labels).map { match in
                var result = match
                result.ownerID = collection.id
                result.ownerTitle = collection.title
                return result
            }
        }
    }
}

enum LibraryImportanceSelection {
    static func contains(cardID: Int, collectionID: UUID, data: Data) -> Bool {
        let items = (try? JSONDecoder().decode([LibraryRecentItem].self, from: data)) ?? []
        return items.contains(LibraryRecentItem(collectionID: collectionID, cardID: cardID))
    }
}

/// A non-interactive status mark that follows the item's owner-qualified importance setting.
struct ImportantItemIndicator: View {
    let cardID: Int
    var ownerID: UUID? = nil
    @AppStorage("Plenact.LibraryImportant.v1") private var importantData = Data()
    @Environment(\.cardMovementSource) private var source
    @Environment(\.libraryImportance) private var importance
    private var isImportant: Bool {
        if let owner = ownerID ?? source {
            return LibraryImportanceSelection.contains(cardID: cardID, collectionID: owner, data: importantData)
        }
        return importance?.contains(cardID) == true
    }
    var body: some View {
        if isImportant {
            Image(systemName: "star.fill")
                .font(.caption.weight(.regular))
                .foregroundStyle(Color.orange.opacity(0.65))
                .accessibilityLabel("Important")
                .accessibilityIdentifier("item.important")
        }
    }
}

struct LibraryImportanceAccess {
    let contains: (Int) -> Bool
    let set: (Int, Bool) -> Void
}
private struct LibraryImportanceKey: EnvironmentKey {
    static let defaultValue: LibraryImportanceAccess? = nil
}
extension EnvironmentValues {
    var libraryImportance: LibraryImportanceAccess? {
        get { self[LibraryImportanceKey.self] }
        set { self[LibraryImportanceKey.self] = newValue }
    }
}

struct LibraryPlateItem: Identifiable {
    let collection: PersonalCollection
    let list: KanbanList
    let card: KanbanCard
    let reason: String
    let rank: Int
    let date: Date
    var id: String { "\(collection.id.uuidString).\(card.id)" }
}
enum LibraryPlateSelection {
    static func items(in collections: [PersonalCollection], important: [LibraryRecentItem], now: Date = .now, calendar: Calendar = .current) -> [LibraryPlateItem] {
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        var items: [LibraryPlateItem] = []
        for collection in collections where collection.isActive {
            for list in collection.lists where !list.isArchived {
                for card in list.cards where !card.isSectionDivider && !card.isTitleChecked {
                    let marked = important.contains(LibraryRecentItem(collectionID: collection.id, cardID: card.id))
                    var due = card.dueDate
                    // A time without a date cannot be assigned an urgency day.
                    if !card.dueDateKind.includesDate { due = nil }
                    let rank: Int
                    let reason: String
                    if let due, due < today || (card.dueDateKind.includesTime && due < now) {
                        rank = 0; reason = "Overdue · " + card.dueDateLabel
                    } else if let due, calendar.isDate(due, inSameDayAs: now) {
                        rank = 1; reason = card.dueDateKind.includesTime ? "Due at " + CardDateKind.time.label(for: due) : "Due today"
                    } else if let due, due < horizon {
                        rank = 2; reason = "Due " + card.dueDateLabel
                    } else if marked {
                        rank = 3; reason = "Marked important"
                    } else { continue }
                    items.append(LibraryPlateItem(collection: collection, list: list, card: card, reason: reason, rank: rank, date: due ?? .distantFuture))
                }
            }
        }
        return Array(items.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }.prefix(4))
    }
}

private struct LibraryItemOpenedKey: EnvironmentKey {
    static let defaultValue: (Int) -> Void = { _ in }
}
extension EnvironmentValues {
    var libraryItemOpened: (Int) -> Void {
        get { self[LibraryItemOpenedKey.self] }
        set { self[LibraryItemOpenedKey.self] = newValue }
    }
}

struct LibraryPlateTile: View {
    let item: LibraryPlateItem
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 132
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.rank == 0 ? "exclamationmark.circle.fill" : (item.rank == 3 ? "star.fill" : "clock"))
                    .foregroundStyle(item.rank == 0 ? Color.red : item.collection.libraryIdentityColor)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
            }
            Text(item.card.word).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(3)
            Spacer(minLength: 4)
        }
        .padding(12)
        .frame(width: tileWidth, alignment: .leading)
        .frame(minHeight: tileHeight, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).fill(item.collection.libraryIdentityColor.opacity(0.10)).allowsHitTesting(false) }
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(item.collection.libraryIdentityColor.opacity(0.3), lineWidth: 1).allowsHitTesting(false) }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.collection.title + ", " + item.reason)
    }
}

/// Original encouragements selected by local calendar day, repeating every sixty days.
enum TodaySloganCatalog {
    static let slogans: [String] = [
        "small steps today, bringing your plans to life",
        "a fresh page today, with room for what matters",
        "begin where you are, and grow from here",
        "one kind step forward, one brighter day ahead",
        "breathe in this morning, and begin with hope",
        "your next chapter starts with one small step",
        "make a little space for the life you imagine",
        "let today be a beginning you can believe in",
        "plant a little hope, and give it time to grow",
        "bring a brave heart to a brand new page",
        "a quieter start, a clearer path ahead",
        "choose one good thing, and begin there today",
        "your plans take shape in the steps you take",
        "leave room for wonder in the work of today",
        "let a small beginning open a new possibility",
        "build a day that feels a little more like you",
        "take a deeper breath, then take your next step",
        "give your hopes a little time on the calendar",
        "begin gently today, and let momentum follow",
        "one thoughtful choice can brighten your day",
        "make today a place where your hopes can grow",
        "let yesterday rest, and meet today with care",
        "bring your attention back to what matters now",
        "your future has room for a small step today",
        "find a little courage in the next thing you do",
        "a new morning, a little more room to begin",
        "turn a little intention into something real",
        "let your next step be a promise to yourself",
        "create a little calm, then follow your purpose",
        "give the life you love a little care today",
        "begin again today, with patience on your side",
        "one clear intention, a day of possibilities",
        "leave a little room for joy along the way",
        "your hopes deserve a place in today’s plans",
        "let a gentle reset lead to a meaningful start",
        "build from this moment, one small choice at a time",
        "bring your dreams closer with something small",
        "a little focus today, a little more possibility",
        "choose a steady pace, and make room to grow",
        "this day is yours to shape with care",
        "let the next page hold a little more hope",
        "begin with what matters, and let that guide you",
        "give a small idea the chance to become real",
        "make space for a beginning that feels like you",
        "follow a little hope into your next step",
        "you can begin anew without beginning from nothing",
        "let progress be gentle, and let it be yours",
        "a little care today can change what comes next",
        "bring your best hopes into the everyday",
        "one honest effort, one new reason to believe",
        "let today hold both purpose and breathing room",
        "grow a life you love through the things you choose",
        "a fresh start can be as small as this moment",
        "give yourself room to try a different path",
        "begin with a breath, continue with a little courage",
        "make one small move toward what feels meaningful",
        "let your plans grow with the person you are becoming",
        "there is room in this day for a hopeful beginning",
        "take the next kind step toward a life you love",
        "close today knowing you gave something good a start",
    ]

    static func slogan(on date: Date, calendar: Calendar = .current) -> String {
        // A fixed Gregorian anchor keeps rotation stable across relaunches, years, and DST.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let anchor = local.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let days = local.dateComponents([.day], from: anchor, to: local.startOfDay(for: date)).day ?? 0
        let index = ((days % slogans.count) + slogans.count) % slogans.count
        return slogans[index]
    }
}

/// A quiet, readable encouragement in Today's existing space above Quick capture.
private struct TodaySloganView: View {
    @State private var showsFullSlogan = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.everyMinute) { context in
            sloganContent(TodaySloganCatalog.slogan(on: context.date))
        }
    }

    private func sloganContent(_ slogan: String) -> some View {
        Button { showsFullSlogan = true } label: {
            GentleCollectionPreview(text: slogan, scrolls: true,
                textFont: .system(size: 27, design: .serif).italic(),
                textColor: (colorScheme == .dark
                    ? Color(red: 0.84, green: 0.76, blue: 0.65)
                    : Color(red: 0.40, green: 0.31, blue: 0.23)).opacity(0.55),
                pointsPerSecond: 35.1, startPause: 0.4, endPause: 0.55, travelsAcross: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today's slogan. " + slogan)
        .accessibilityHint("Shows the full message")
        .alert("Today's slogan", isPresented: $showsFullSlogan) {
            Button("Done", role: .cancel) { }
        } message: { Text(slogan) }
    }
}

private struct PreviewTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct PreviewViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct PreviewVisibility: ViewModifier {
    @Binding var visible: Bool
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        } else {
            content.onAppear { visible = true }.onDisappear { visible = false }
        }
    }
}

/// Keeps short previews still and reveals overflowing text without changing row size.
struct GentleCollectionPreview: View {
    let text: String
    var scrolls = false
    var textFont: Font = .caption
    var textColor: Color = .secondary
    var pointsPerSecond: Double = 14
    var startPause: Double = 2.5
    var endPause: Double = 2.5
    var travelsAcross = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var textWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var visible = false
    private struct Loop: Hashable {
        let text: String
        let distance: CGFloat
        let active: Bool
    }
    private var loop: Loop {
        Loop(text: text, distance: travelsAcross ? textWidth + viewportWidth : max(0, textWidth - viewportWidth),
             active: scrolls && !reduceMotion && !typeSize.isAccessibilitySize && visible && viewportWidth > 0)
    }
    var body: some View {
        Group {
            if scrolls && !reduceMotion && !typeSize.isAccessibilitySize {
                Text(text).lineLimit(1).hidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Text(text).fixedSize(horizontal: true, vertical: false)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: PreviewTextWidthKey.self, value: geometry.size.width)
                                }
                            }
                            .offset(x: offset).opacity(opacity)
                    }
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: PreviewViewportWidthKey.self, value: geometry.size.width)
                        }
                    }
                    .clipped()
            } else {
                Text(text).lineLimit(travelsAcross ? nil : (typeSize.isAccessibilitySize ? 2 : 1))
                    .fixedSize(horizontal: false, vertical: travelsAcross)
            }
        }
        .font(textFont).foregroundStyle(textColor)
        .accessibilityElement(children: .ignore).accessibilityLabel(text)
        .onPreferenceChange(PreviewTextWidthKey.self) { textWidth = $0 }
        .onPreferenceChange(PreviewViewportWidthKey.self) { viewportWidth = $0 }
        .modifier(PreviewVisibility(visible: $visible))
        .task(id: loop) {
            var reset = Transaction(); reset.disablesAnimations = true
            withTransaction(reset) { offset = travelsAcross && loop.active ? viewportWidth : 0; opacity = 1 }
            guard loop.active, loop.distance > 1 else { return }
            let distance = loop.distance
            let seconds = max(4, Double(distance) / max(1, pointsPerSecond))
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(startPause))
                    withAnimation(.linear(duration: seconds)) { offset = travelsAcross ? -textWidth : -distance }
                    try await Task.sleep(for: .seconds(seconds + endPause))
                    withAnimation(.easeOut(duration: 0.4)) { opacity = 0 }
                    try await Task.sleep(for: .seconds(0.4))
                    withTransaction(reset) { offset = travelsAcross ? viewportWidth : 0 }
                    withAnimation(.easeIn(duration: 0.6)) { opacity = 1 }
                    try await Task.sleep(for: .seconds(0.6))
                }
            } catch { /* Leaving the row or changing preferences cancels its loop. */ }
        }
    }
}

extension PersonalCollection {
    /// Match the default On the Table identity to its banner without changing custom colors.
    var libraryIdentityColor: Color {
        if kind == .list, title == "On the Table", color == .coral {
            return ItemAccent.coral.darkHeaderColor
        }
        return color.color
    }
}

struct LibraryCollectionRow: View {

    let title: String      /* User-owned collection or Week Board title       */
    let subtitle: String   /* Collection kind and active-list context         */
    let icon: String       /* SF Symbol representing the organizing space     */
    let color: Color       /* Collection accent, not its only identifying cue */
    let count: Int         /* Active non-divider card count                   */
    var preview: String = ""
    var scrollsPreview = false

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
                .frame(width: 4, height: 38)
                .accessibilityHidden(true)

            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
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
                    if !preview.isEmpty {
                        GentleCollectionPreview(text: preview, scrolls: scrollsPreview)
                    }
                }

                .frame(maxWidth: .infinity, alignment: .leading)
                Text(count == 1 ? "1 card" : "\(count) cards")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            .frame(maxWidth: .infinity, alignment: .leading)
        }

        .padding(.vertical, 4)
        .frame(minHeight: 48)
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
/// Keeps the chosen checkmark visible briefly before dismissing the filter picker.
private struct CollectionFilterPopover: View {
    let selection: LibraryBrowseFilter
    let onSelect: (LibraryBrowseFilter) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var pendingSelection: LibraryBrowseFilter?
    @State private var opacity = 1.0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(LibraryBrowseFilter.allCases) { filter in
                Button {
                    opacity = 1
                    onSelect(filter)
                    pendingSelection = filter
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: filter.symbol).frame(width: 22)
                        Text(filter.rawValue)
                        Spacer(minLength: 24)
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .opacity(selection == filter ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 8)
        .frame(width: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .opacity(opacity)
        .task(id: pendingSelection) {
            guard pendingSelection != nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(voiceOver ? 900 : 450))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { opacity = 0 }
                if !reduceMotion { try await Task.sleep(for: .milliseconds(160)) }
                dismiss()
            } catch { /* A newer selection or outside dismissal cancels this dismissal. */ }
        }
    }
}

struct BoardListsView: View {
    @State private var openedHelpArticle: PlenactHelpArticle?
    @Environment(\.planningCalendarAccess) private var planningAccess
    @State private var browsedLabel: KanbanLabel?
    @State private var browseLabelLibrary = LabelLibraryStore.load()
    @Environment(\.workspaceBottomBarHeight) private var bottomBarHeight

    @State private var libraryEditMode: EditMode = .inactive

    @State private var showsSharedSearch = false

    let retainedWeekLists: [KanbanList]                        /* Week references protect shared attachments */

    @Binding var collections: [PersonalCollection]             /* Shared device-local collections             */
    let registerListNewNote: ((() -> Void)?) -> Void /* Registers the directory's scoped Note action */
    let onOpenSaved: () -> Void                                /* Select the existing canonical Saved destination */
    var onLoadExampleWeek: (() -> Bool)? = nil
    var onUndoExampleWeek: (() -> Bool)? = nil
    var onLoadExampleMonth: (() -> Void)? = nil
    var onRestoreUserData: (() -> Void)? = nil
    var hasUserDataBackup = false
    var savedPersonalCardTarget: PersonalSavedCardTarget? = nil /* Saved bookmark waiting for Library navigation */
    var onClearSavedPersonalCardTarget: () -> Void = {} /* Acknowledge a handled or invalid Saved request */
    @State private var archivingCollection: PersonalCollection? /* Collection awaiting archive confirmation */
    @FocusState private var isLibrarySearchFocused: Bool
    @State private var showsRecentShelf = false
    @AppStorage("Plenact.LibraryImportant.v1") private var importantData = Data()
    @State private var recentItems = LibraryRecentStore.load()
    @AppStorage(LibraryRecentStore.key) private var libraryRecentData = Data()
    @AppStorage("Plenact.LibraryShowsCollectionPreviews") private var showsCollectionPreviews = false
    @AppStorage("Plenact.LibraryScrollsCollectionPreviews") private var scrollsCollectionPreviews = false
    @State private var showsCollectionFilter = false
    @State var browseFilter: LibraryBrowseFilter = .all /* Initial scope may be supplied by Library navigation */
    @ScaledMetric(relativeTo: .body) private var plateTileHeight: CGFloat = 110
    @State var searchText = ""                                 /* Directory search query                      */
    @State private var editingCollection: PersonalCollection?  /* Collection draft being edited               */
    @State private var openedCollection: PersonalCollection?   /* Collection board presented full-screen      */
    @State private var boardTargetListID: Int?                 /* Exact collection list requested from Saved    */
    @State private var boardTargetCardID: Int?                 /* Exact collection card requested from Saved    */
    @State private var deletingCollection: PersonalCollection? /* Collection awaiting delete confirmation     */
    @State private var newNoteDraftDestination: PersonalCollection? /* Personal List selected for the presented Note draft */
    @State private var mostRecentlyOpenedListID: UUID? /* Last opened List used as the next Note destination */
    @State private var libraryQuickTemplate: QuickCaptureTemplate?
    @State private var weekExampleAction: String?
    @State private var libraryStarterError: String?
    @State private var examplePreview: LibraryExamplePreview?


    ///
    /// @fcn        BoardListsView.filteredCollections
    /// @brief      Select active personal collections matching the directory query
    /// @details    Delegates collection matching to the model and preserves collection order
    ///
    /// @return     ([PersonalCollection]) visible active collections
    /// @post       Archived collections remain stored but are not returned
    ///
    @ViewBuilder
    private var libraryLabelRows: some View {
        let owners = WorkspaceBrowseIndex.owners(document: planningAccess?.document, library: collections)
        let usages = WorkspaceBrowseIndex.labels(in: owners, catalog: browseLabelLibrary).filter {
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.label.name.localizedStandardContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if usages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("No matching labels", systemImage: "tag") .font(.headline)
                Text("Labels assigned to active cards and notes appear here.").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 12)
        }
        ForEach(usages) { usage in
            Button { browsedLabel = usage.label } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tag").font(.title3).foregroundStyle(usage.label.color.color)
                        .frame(width: 40, height: 40)
                        .background(usage.label.color.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    Text(usage.label.name).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Text("\(usage.matches.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color(.secondarySystemGroupedBackground))
            .accessibilityLabel(usage.label.name + ", \(usage.matches.count) active items")
        }
    }

    private var filteredCollections: [PersonalCollection] { /* Active directory entries matching the search */
        let owners = Set(librarySearchResults.compactMap(\.ownerID))
        return collections.filter { browseFilter.includes($0) && ($0.matches(searchText) || owners.contains($0.id)) }
    }

    private var librarySearchResults: [TodaySearchResult] {
        LibrarySearchIndex.results(query: searchText, collections: collections.filter { browseFilter.includes($0) }, labels: LabelLibraryStore.load())
    }

    private func openLibrarySearchResult(_ result: TodaySearchResult) {
        guard let collection = collections.first(where: { $0.id == result.ownerID && $0.isActive }) else { return }
        isLibrarySearchFocused = false
        boardTargetListID = result.listID
        boardTargetCardID = result.cardID
        openedCollection = collection
    }

    private func librarySearchRow(_ result: TodaySearchResult) -> some View {
        let card = collections.first { $0.id == result.ownerID }?.lists.first { $0.id == result.listID }?.cards.first { $0.id == result.cardID }
        return Button { openLibrarySearchResult(result) } label: {
            HStack(spacing: 12) {
                Image(systemName: card?.presentation == .note ? "note.text" : "rectangle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.cardTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(result.ownerTitle == result.listTitle ? result.listTitle : (result.ownerTitle ?? "Plans") + " · " + result.listTitle)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }.padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHint("Opens this item in your Plans")
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

        return HStack(spacing: 8) {
            Button {
                if collection.kind == .list {
                    mostRecentlyOpenedListID = collection.id
                }
                openedCollection = collection
            } label: {
                row(title: collection.title, subtitle: collectionSubtitle,
                    icon: collection.icon.rawValue, color: collection.libraryIdentityColor, count: collection.cardCount, preview: collectionPreview(collection))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this personal collection")

            Menu {
                Button("Edit", systemImage: "pencil") { editingCollection = collection }
                Button("Archive", systemImage: "archivebox") { archivingCollection = collection }
                Button("Delete \(collection.kind.rawValue)", systemImage: "trash", role: .destructive) { deletingCollection = collection }
            } label: {
                WorkspaceHeaderIcon(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(collection.title) actions")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).fill(collection.libraryIdentityColor.opacity(0.12)).allowsHitTesting(false) }
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(collection.libraryIdentityColor.opacity(0.3), lineWidth: 1).allowsHitTesting(false) }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .accessibilityActions {
            Button("Edit Collection") { editingCollection = collection }
            Button("Archive Collection") { archivingCollection = collection }
            Button("Delete \(collection.kind.rawValue)") { deletingCollection = collection }
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

            DatabaseActivity.shared.report("Create a personal List before adding a Note from Plans.")

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
    private func createNote(in collectionID: UUID, title: String, body: String, subtitle: String, createdAt: Date, presentation: ItemPresentation) throws {

        guard let collectionIndex = collections.firstIndex(where: { /* Active personal List receiving the new Note */

            $0.id == collectionID && $0.kind == .list && $0.isActive
        }) else {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var updated = collections[collectionIndex] /* Destination collection receiving the new Note */

        try updated.addNote(title: title, body: body, createdAt: createdAt, presentation: presentation, subtitle: subtitle)

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
        if sourceID != destinationID, let destination = snapshot.first(where: { $0.id == destinationID }) {
            TransferConfirmationPresenter.shared.show(TransferConfirmation(title: moved.word, destination: destination.title))
        }

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
            .flatMap(\.storedFileNames))
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
            onCreateNote:              { destinationID, title, body, subtitle, createdAt, presentation in
                try createNote(in: destinationID, title: title, body: body, subtitle: subtitle, createdAt: createdAt, presentation: presentation)
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
        .environment(\.libraryImportance, LibraryImportanceAccess(contains: { cardID in
            importantItems.contains(LibraryRecentItem(collectionID: collection.id, cardID: cardID))
        }, set: { cardID, marked in
            let item = LibraryRecentItem(collectionID: collection.id, cardID: cardID)
            var updated = importantItems.filter { $0 != item }
            if marked { updated.append(item) }
            if let data = try? JSONEncoder().encode(updated) { importantData = data }
        }))
        .environment(\.libraryItemOpened, { cardID in
            recentItems = LibraryRecentStore.remember(LibraryRecentItem(collectionID: collection.id, cardID: cardID))
        })
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
    private func row(title: String, subtitle: String, icon: String, color: Color, count: Int, preview: String = "") -> some View {

        LibraryCollectionRow(title: title, subtitle: subtitle, icon: icon, color: color, count: count, preview: preview, scrollsPreview: scrollsCollectionPreviews)
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
    private var importantItems: [LibraryRecentItem] {
        (try? JSONDecoder().decode([LibraryRecentItem].self, from: importantData)) ?? []
    }
    private var plateItems: [LibraryPlateItem] {
        LibraryPlateSelection.items(in: collections, important: importantItems)
    }
    private var showsPlateShelf: Bool {
        browseFilter.browsesCollections && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && libraryEditMode != .active
    }

    private var plateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming Soon")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
                .accessibilityAddTraits(.isHeader)
            if plateItems.isEmpty {
                Text("Nothing urgent right now. Mark an item important from its menu or add a due date to bring it here.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 28)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(plateItems) { item in
                            Button {
                                boardTargetListID = item.list.id
                                boardTargetCardID = item.card.id
                                openedCollection = item.collection
                            } label: {
                                LibraryPlateTile(item: item)
                                    .frame(height: plateTileHeight)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this item directly")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 4)
                }
                .contentMargins(.all, 0, for: .scrollContent)
                .frame(height: plateTileHeight + 8)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func collectionPreview(_ collection: PersonalCollection) -> String {
        showsCollectionPreviews ? collection.contentPreview : ""
    }

    private var availableRecents: [(LibraryRecentItem, PersonalCollection, KanbanList, KanbanCard)] {
        recentItems.compactMap { item in
            guard let collection = collections.first(where: { $0.id == item.collectionID && browseFilter.includes($0) }),
                  let list = collection.lists.first(where: { !$0.isArchived && $0.cards.contains { $0.id == item.cardID && !$0.isSectionDivider } }),
                  let card = list.cards.first(where: { $0.id == item.cardID }) else { return nil }
            return (item, collection, list, card)
        }
    }

    private var recentShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(availableRecents, id: \.0.id) { item, collection, list, card in
                    Button {
                        boardTargetListID = list.id
                        boardTargetCardID = card.id
                        openedCollection = collection
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(card.word).font(.headline).foregroundStyle(.primary).lineLimit(2)
                            Text(card.subtitle.isEmpty ? PlanRichText.plain(card.descriptionOverride ?? "") : card.subtitle)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Spacer(minLength: 0)
                            Text(collection.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(width: 148, height: 132, alignment: .topLeading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(collection.libraryIdentityColor.opacity(0.4), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this item directly")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var collectionFilterMenu: some View {
        Button { showsCollectionFilter = true } label: {
            Image(systemName: browseFilter.symbol)
                .font(.system(size: 22.5, weight: .medium))
                .foregroundStyle(Color(red: 177.0 / 255, green: 143.0 / 255, blue: 112.0 / 255))
                .padding(5)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .popover(isPresented: $showsCollectionFilter, arrowEdge: .top) {
            CollectionFilterPopover(selection: browseFilter) { filter in
                browseFilter = filter
                libraryEditMode = .inactive
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel("Filter collections")
        .accessibilityValue(browseFilter.rawValue)
        .accessibilityHint("Choose All, Lists, Boards, Labels, Templates, Examples, or Help. Your search text is kept.")
        .accessibilityIdentifier("library.collectionFilter")
    }

    private var libraryHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    collectionFilterMenu
                    Text("Library").font(.largeTitle.weight(.bold))
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { showsSharedSearch = true } label: {
                    WorkspaceHeaderIcon(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search Plenact")
                .accessibilityIdentifier("library.openSearch")
                Menu {
                    Button(libraryEditMode == .active ? "Done reordering collections" : "Reorder collections", systemImage: libraryEditMode == .active ? "checkmark" : "arrow.up.arrow.down") {
                        withAnimation { libraryEditMode = libraryEditMode == .active ? .inactive : .active }
                    }
                    .disabled(browseFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Toggle("Show collection previews", isOn: $showsCollectionPreviews)
                    Toggle("Scroll long previews", isOn: $scrollsCollectionPreviews)
                        .disabled(!showsCollectionPreviews)
                } label: {
                    WorkspaceHeaderIcon(systemName: libraryEditMode == .active ? "checkmark" : "pencil")
                }
                .accessibilityLabel("Plans display and organization")
                Button(action: onOpenSaved) {
                    WorkspaceHeaderIcon(systemName: "bookmark")
                }
                .accessibilityLabel("Saved Items")
                .accessibilityHint("Opens your bookmarked content and archived collections")
                .accessibilityIdentifier("library.openSaved")
                createMenu
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(browseFilter.searchPrompt, text: $searchText)
                    .focused($isLibrarySearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel(browseFilter.searchPrompt)
                    .accessibilityHint(browseFilter.searchHint)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Clear Plans search")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            if isLibrarySearchFocused || !searchText.isEmpty {
                Text(browseFilter.searchContext)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsRecentShelf && browseFilter.browsesCollections {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recently added or viewed").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            isLibrarySearchFocused = false
                            withAnimation { showsRecentShelf = false }
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Close recent items")
                    }
                    if availableRecents.isEmpty {
                        Text("Open or add a Plans item to find it here.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        recentShelf
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: isLibrarySearchFocused) { _, focused in
            if focused { withAnimation { showsRecentShelf = true } }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background { TodayPaperBackground() }
    }

    private var createMenu: some View {
        Menu {
            Button("+ New List") {
                editingCollection = PersonalCollection(title: "", kind: .list)
            }
            Button("+ New Board") {
                editingCollection = PersonalCollection(title: "", kind: .board, icon: .project)
            }
            Divider()
            starterListsMenu
            starterBoardsMenu
            templatesMenu
            examplesMenu
        } label: {
            WorkspaceHeaderIcon(systemName: "plus.circle.fill")
        }
        .accessibilityLabel("Plans creation and examples")
    }

    private var starterListsMenu: some View {
        Menu("Starter Lists", systemImage: "list.bullet") {
            ForEach(["On the Table", "In the Queue", "Scheduled", "Shopping", "Reminders", "Up for Brew", "Misc"], id: \.self) { title in
                Button(title) {
                    editingCollection = DefaultListTutorial.makeStarter(title: title)
                }
            }
        }
    }

    private var starterBoardsMenu: some View {
        Menu("Starter Boards", systemImage: "rectangle.3.group") {
            ForEach(["General Notes", "New Project Notes", "Girlfriend Important Details"], id: \.self) { title in
                Button(title) {
                    editingCollection = PersonalCollection(title: title, kind: .board,
                        icon: title == "Girlfriend Important Details" ? .heart : .notes)
                }
            }
        }
    }

    private var examplesMenu: some View {
        Menu("Examples", systemImage: "sparkles") {
            Button("Browse all examples", systemImage: "books.vertical") { browseFilter = .examples; searchText = "" }
            listExamplesMenu
            Menu("Board examples", systemImage: "rectangle.3.group") {
                ForEach(PersonalBoardExample.allCases) { example in
                    Button(example.rawValue, systemImage: "plus") {
                        editingCollection = example.makeCollection(existingTitles: collections.map(\.title))
                    }
                }
            }
            weekExamplesMenu
            fullMonthExamplesMenu
            if hasUserDataBackup, let onRestoreUserData {
                Divider()
                Button("Restore User Data", systemImage: "arrow.uturn.backward") { onRestoreUserData() }
            }
        }
    }

    private var fullMonthExamplesMenu: some View {
        Menu("Full-month examples", systemImage: "calendar") {
            Menu("A month in motion") {
                Button("Preview month") {
                    let example = FullMonthExample.make(calendar: planningAccess?.document.calendar ?? .current)
                    examplePreview = LibraryExamplePreview(title: "A month in motion", summary: "Fictional plans for this month: fuller days through today, with a few upcoming plans. Previewing does not change your data.", lists: example.previewLists)
                }
                if let onLoadExampleMonth {
                    Button("Use example month", systemImage: "plus") { onLoadExampleMonth() }
                }
            }
        }
    }

    private var weekExamplesMenu: some View {
        Menu("Week View examples", systemImage: "calendar") {
            Button("Preview Work Week Board") {
                examplePreview = LibraryExamplePreview(title: "Work Week Board", summary: "A separate seven-list Week View example.", lists: SampleData.lists)
            }
            Button("Use Week View", systemImage: "plus") {
                editingCollection = PersonalCollection.exampleWeek(existingTitles: collections.map(\.title))
            }
            Menu("Example cards") {
                ForEach(SampleData.lists) { list in
                    Menu(list.title) {
                        ForEach(list.cards.filter { !$0.isSectionDivider }) { card in
                            Button(card.word) {
                                examplePreview = LibraryExamplePreview(title: card.word, summary: list.title,
                                    lists: [KanbanList(id: list.id, title: list.title, cards: [card])])
                            }
                        }
                    }
                }
            }
        }
    }

    private var listExamplesMenu: some View {
        Menu("List examples", systemImage: "list.bullet") {
            ForEach(PersonalListExample.allCases) { example in
                listExampleMenu(example)
            }
        }
    }

    private func listExampleMenu(_ example: PersonalListExample) -> some View {
        let draft = example.makeCollection(existingTitles: [])
        return Menu(example.rawValue) {
            Button("Preview list") {
                examplePreview = LibraryExamplePreview(title: example.rawValue, summary: example.summary, lists: draft.lists)
            }
            Menu("Example cards") {
                ForEach(draft.lists[0].cards) { card in
                    Button(card.word) {
                        examplePreview = LibraryExamplePreview(title: card.word, summary: example.summary,
                            lists: [KanbanList(id: 0, title: example.rawValue, cards: [card])])
                    }
                }
            }
            Button("Use \(example.rawValue)", systemImage: "plus") {
                editingCollection = example.makeCollection(existingTitles: collections.map(\.title))
            }
        }
    }

    @ViewBuilder
    private var libraryTemplateRows: some View {
        PlanningTemplateLibraryRows(query: searchText)
        let listTemplates = MixedListTemplate.allCases.filter {
            LibraryStarterSearch.matches(searchText, texts: [$0.rawValue, $0.summary, "List template"] + $0.items.flatMap { [$0.0, $0.1] })
        }
        if !listTemplates.isEmpty {
            Section("List templates") {
                ForEach(listTemplates) { template in
                    DisclosureGroup {
                        Text(template.summary).foregroundStyle(.secondary)
                        ForEach(template.items.indices, id: \.self) { index in
                            Label(template.items[index].0, systemImage: template.items[index].2.symbol)
                        }
                        Button("Use " + template.rawValue, systemImage: "plus") {
                            editingCollection = template.makeCollection(existingTitles: collections.map(\.title))
                        }
                    } label: { Label(template.rawValue, systemImage: "list.bullet.rectangle") }
                }
            }
        }
        let quickTemplates = QuickCaptureTemplate.allCases.filter {
            LibraryStarterSearch.matches(searchText, texts: [$0.title, $0.summary, $0.body, $0.presentation.title] + $0.actions)
        }
        if !quickTemplates.isEmpty {
            Section {
                ForEach(quickTemplates) { template in
                    DisclosureGroup {
                        Text(template.summary).foregroundStyle(.secondary)
                        if !template.body.isEmpty { Text(template.body).font(.subheadline) }
                        ForEach(Array(template.actions.enumerated()), id: \.offset) { _, action in Label(action, systemImage: "square") }
                        Button("Use " + template.title, systemImage: "plus") { libraryQuickTemplate = template }
                    } label: {
                        Label(template.title, systemImage: template.presentation == .note ? "note.text" : "rectangle")
                    }
                }
            } header: { Text("Card & Note starting points") } footer: {
                Text("Opens an editable draft with a Week list destination. Nothing is added until you tap Add.")
            }
        }
    }

    @ViewBuilder
    private var libraryExampleRows: some View {
        let listExamples = PersonalListExample.allCases.filter {
            LibraryStarterSearch.matches(searchText, texts: [$0.rawValue, $0.summary, "List example"] + $0.cards.flatMap { [$0.0, $0.1] })
        }
        let boardExamples = PersonalBoardExample.allCases.filter {
            LibraryStarterSearch.matches(searchText, texts: [$0.rawValue, $0.summary, "Board example"] + $0.listSummaries.map(\.title))
        }
        let weekMatches = LibraryStarterSearch.matches(searchText, texts: ["Example Week Work Week Board calendar seven days"] + SampleData.lists.flatMap { [$0.title] + $0.cards.map(\.word) })
        let monthMatches = LibraryStarterSearch.matches(searchText, texts: ["A month in motion Full-month example calendar fictional plans"])
        if listExamples.isEmpty && boardExamples.isEmpty && !weekMatches && !monthMatches {
            ContentUnavailableView("No matching examples", systemImage: "sparkles", description: Text("Try a different name, topic, or example type."))
        }
        if !listExamples.isEmpty {
            Section("List examples") {
                ForEach(listExamples) { example in
                    DisclosureGroup {
                        Text(example.summary).foregroundStyle(.secondary)
                        ForEach(example.cards.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(example.cards[index].0).font(.headline)
                                Text(example.cards[index].1).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Button("Preview " + example.rawValue, systemImage: "eye") {
                            let draft = example.makeCollection(existingTitles: collections.map(\.title))
                            examplePreview = LibraryExamplePreview(title: example.rawValue, summary: example.summary, lists: draft.lists)
                        }
                        Button("Use " + example.rawValue, systemImage: "plus") { editingCollection = example.makeCollection(existingTitles: collections.map(\.title)) }
                    } label: { Label(example.rawValue, systemImage: "list.bullet") }
                }
            }
        }
        if !boardExamples.isEmpty {
            Section("Board examples") {
                ForEach(boardExamples) { example in
                    DisclosureGroup {
                        Text(example.summary).foregroundStyle(.secondary)
                        ForEach(Array(example.listSummaries.enumerated()), id: \.offset) { _, list in
                            Text("\(list.title) · \(list.count) items").font(.subheadline)
                        }
                        Button("Preview " + example.rawValue, systemImage: "eye") {
                            let draft = example.makeCollection(existingTitles: collections.map(\.title))
                            examplePreview = LibraryExamplePreview(title: example.rawValue, summary: example.summary, lists: draft.lists)
                        }
                        Button("Use " + example.rawValue, systemImage: "plus") { editingCollection = example.makeCollection(existingTitles: collections.map(\.title)) }
                    } label: { Label(example.rawValue, systemImage: "rectangle.3.group") }
                }
            }
        }
        if weekMatches {
            Section {
                Button("Preview Example Week", systemImage: "eye") {
                    examplePreview = LibraryExamplePreview(title: "Example Week", summary: "Seven dated-day lists from Plenact's original Work Week example. Previewing changes nothing.", lists: SampleData.lists)
                }
                Button("Use as a new Board", systemImage: "plus") { editingCollection = PersonalCollection.exampleWeek(existingTitles: collections.map(\.title)) }
                LibraryExampleWeekTemplateButton()
                if onLoadExampleWeek != nil {
                    Button("Load into current Week", systemImage: "calendar") { weekExampleAction = "load" }
                }
                if ExampleLoadUndoStore.load() != nil, onUndoExampleWeek != nil {
                    Button("Undo Last Load", systemImage: "arrow.uturn.backward") { weekExampleAction = "undo" }
                }
            } header: { Text("Week example") } footer: {
                Text("Use as a new Board creates a draft. Loading into the current Week requires confirmation and retains the previous Week for undo.")
            }
        }
        if monthMatches {
            Section {
                Button("Preview A month in motion", systemImage: "eye") {
                    let example = FullMonthExample.make(calendar: planningAccess?.document.calendar ?? .current)
                    examplePreview = LibraryExamplePreview(title: "A month in motion", summary: "Fictional plans across this month. Previewing does not change your data.", lists: example.previewLists)
                }
                if let onLoadExampleMonth { Button("Use example month", systemImage: "calendar.badge.plus", action: onLoadExampleMonth) }
                if hasUserDataBackup, let onRestoreUserData { Button("Restore User Data", systemImage: "arrow.uturn.backward", action: onRestoreUserData) }
            } header: { Text("Full-month example") } footer: {
                Text("Using the example month asks for confirmation and backs up your workspace first. Use Restore User Data to return.")
            }
        }
    }

    private var templatesMenu: some View {
        Menu("Templates", systemImage: "square.stack.3d.up") {
            Button("Browse all templates", systemImage: "square.stack.3d.up") { browseFilter = .templates; searchText = "" }
            Divider()
            ForEach([MixedListTemplate.planDay, .startProject, .exploreIdea]) { template in
                Button(template.rawValue) {
                    editingCollection = template.makeCollection(existingTitles: collections.map(\.title))
                }
            }
        }
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
                if browseFilter == .help {
                    LibraryHelpRows(query: searchText) { openedHelpArticle = $0 }
                } else if browseFilter == .labels {
                    libraryLabelRows
                } else if browseFilter == .templates {
                    libraryTemplateRows
                } else if browseFilter == .examples {
                    libraryExampleRows
                } else {
                Section {

                    ForEach(filteredCollections) { collection in

                        collectionEntry(collection)
                    }
                    .onMove { source, destination in
                        guard browseFilter == .all, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {

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
                                    ? (browseFilter == .all ? "Your own organizing spaces" : "No " + browseFilter.rawValue.lowercased() + " yet") : "No Plans matches",
                                systemImage: "books.vertical"
                            )
                            .font(.headline)
                            Text(
                                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Keep ideas, projects, and everyday plans together in personal lists and boards."
                                    : "Nothing in your Plans matches ‘\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))’. Try another word or phrase."
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
                }
                }
                if !librarySearchResults.isEmpty {
                    Section {
                        ForEach(librarySearchResults) { result in librarySearchRow(result) }
                    } header: { Text("Cards and notes · \(librarySearchResults.count) matches") }
                }
            }

            .listRowSpacing(7)
            .listSectionSpacing(.custom(0))
            .contentMargins(.top, 12, for: .scrollContent)
            .contentMargins(.bottom, 8, for: .scrollContent)
            .onChange(of: collections) { old, updated in
                for collection in updated where collection.isActive {
                    let previousIDs = Set(old.first(where: { $0.id == collection.id })?.lists.flatMap(\.allCards).map(\.id) ?? [])
                    for card in collection.lists.filter({ !$0.isArchived }).flatMap(\.cards) where !card.isSectionDivider && !previousIDs.contains(card.id) {
                        recentItems = LibraryRecentStore.remember(LibraryRecentItem(collectionID: collection.id, cardID: card.id))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    libraryHeader
                    if showsPlateShelf {
                        plateSection
                            .background { TodayPaperBackground().clipped() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomBarHeight > 0 ? 77 : 0)
            }
            .background { TodayPaperBackground() }
            .environment(\.editMode, $libraryEditMode)
            .modifier(PlanningSharedSearchPresentation(isPresented: $showsSharedSearch))

            .sheet(item: $openedHelpArticle) { article in PlenactHelpArticleView(article: article) }
            .sheet(item: $browsedLabel) { label in
                LibraryLabelMatchesView(label: label)
            }
            .onAppear { browseLabelLibrary = LabelLibraryStore.load() }
            .onChange(of: browseFilter) { _, filter in
                libraryEditMode = .inactive
                if filter == .labels { browseLabelLibrary = LabelLibraryStore.load() }
            }
            .sheet(item: $examplePreview) { preview in
                LibraryExamplePreviewView(preview: preview)
            }

            .sheet(item: $editingCollection) { collection in
                PersonalCollectionSettingsView(
                    collection: collection,
                    isNew:      !collections.contains(where: { $0.id == collection.id }),
                    onSave:     saveCollection
                )
            }

            .sheet(item: $libraryQuickTemplate) { template in LibraryQuickTemplateComposer(template: template) }
            .confirmationDialog(weekExampleAction == "undo" ? "Restore the previous Week?" : "Load the example Week?", isPresented: Binding(get: { weekExampleAction != nil }, set: { if !$0 { weekExampleAction = nil } }), titleVisibility: .visible) {
                Button(weekExampleAction == "undo" ? "Undo Last Load" : "Load Example Week", role: .destructive) {
                    let success = weekExampleAction == "undo" ? onUndoExampleWeek?() : onLoadExampleWeek?()
                    if success != true { libraryStarterError = "The Week could not be updated. Your saved data has been retained." }
                    weekExampleAction = nil
                }
                Button("Cancel", role: .cancel) { weekExampleAction = nil }
            } message: {
                Text(weekExampleAction == "undo" ? "Replaces current active and archived Week content with the snapshot from before the example load." : "Replaces current active and archived Week content. The previous Week is retained for Undo Last Load. Personal collections stay unchanged.")
            }
            .alert("Library", isPresented: Binding(get: { libraryStarterError != nil }, set: { if !$0 { libraryStarterError = nil } })) {
                Button("OK", role: .cancel) { libraryStarterError = nil }
            } message: { Text(libraryStarterError ?? "") }
            .fullScreenCover(item: $newNoteDraftDestination) { collection in
                NewPersonalNoteComposer(
                    initialCollectionID:    collection.id,
                    availablePersonalLists: collections
                ) { destinationID, title, body, subtitle, createdAt, presentation in
                    try createNote(in: destinationID, title: title, body: body, subtitle: subtitle, createdAt: createdAt, presentation: presentation)
                }
                .databaseActivityOverlay()
            }

            .fullScreenCover(item: $openedCollection, onDismiss: registerDirectoryNewNote) { collection in
                presentedCollectionBoard(collection)
                    .environment(\.workspaceBottomBarHeight, 0)
            }

            .alert("Delete \(deletingCollection?.kind.rawValue ?? "item")?", isPresented: Binding(
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
        .onChange(of: libraryRecentData) { _, _ in recentItems = LibraryRecentStore.load() }
        .onAppear {
            recentItems = LibraryRecentStore.load()
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

        boardTargetCardID = target.cardID
        boardTargetListID = target.listID
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
                browseFilter = .examples
                searchText = ""
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
struct PersonalListExamplesView: View {

    var onLoadExampleWeek: (() -> Bool)? = nil
    var onUndoExampleWeek: (() -> Bool)? = nil
    let onSelect: (PersonalListExample) -> Void /* Delegate draft creation to the owning Library */
    var onSelectMixedTemplate: ((MixedListTemplate) -> Void)? = nil
    var onSelectBoardExample: ((PersonalBoardExample) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss /* Cancel the chooser without selecting */
    @State private var confirmsLoadWeek = false
    @State private var confirmsUndoWeek = false
    @State private var hasUndoableWeek: Bool
    @State private var operationError: String?

    init(
        onLoadExampleWeek: (() -> Bool)? = nil,
        onUndoExampleWeek: (() -> Bool)? = nil,
        hasUndoableWeek: Bool = false,
        onSelectBoardExample: ((PersonalBoardExample) -> Void)? = nil,
        onSelectMixedTemplate: ((MixedListTemplate) -> Void)? = nil,
        onSelect: @escaping (PersonalListExample) -> Void
    ) {
        self.onLoadExampleWeek = onLoadExampleWeek
        self.onUndoExampleWeek = onUndoExampleWeek
        self.onSelect = onSelect
        self.onSelectMixedTemplate = onSelectMixedTemplate
        self.onSelectBoardExample = onSelectBoardExample
        _hasUndoableWeek = State(initialValue: hasUndoableWeek)
    }


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
                    Text("Explore Lists and Boards and make them your own. Selecting an example opens a draft; only Save adds it to Plans. Your Week and existing collections stay unchanged.")
                        .foregroundStyle(.secondary)
                }

                if onLoadExampleWeek != nil {
                    Section("Example Week View") {
                        Button("Load Example Week View", systemImage: "square.and.arrow.down") {
                            confirmsLoadWeek = true
                        }
                        .accessibilityIdentifier("library.examples.loadWeek")
                        if hasUndoableWeek, onUndoExampleWeek != nil {
                            Button("Undo Last Load", systemImage: "arrow.uturn.backward") {
                                confirmsUndoWeek = true
                            }
                            .accessibilityIdentifier("library.examples.undoWeek")
                        }
                        Text("Loading replaces your current Week Board, including archived Week content. Your previous Week Board is retained on this device for Undo Last Load. Personal Lists and Boards stay unchanged. Nothing is uploaded.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let onSelectBoardExample {
                    Section("Board examples") {
                        ForEach(PersonalBoardExample.allCases) { example in
                            DisclosureGroup {
                                Text(example.summary).foregroundStyle(.secondary)
                                ForEach(Array(example.listSummaries.enumerated()), id: \.offset) { _, list in
                                    HStack {
                                        Label(list.title, systemImage: "rectangle.split.3x1")
                                        Spacer()
                                        Text("\(list.count) items").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text("Includes pictures, notes, named dividers, checklists, dates, labels, bookmarks, color overrides, and archived examples. Dates are illustrative and relative to when you create the draft.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Use \(example.rawValue)", systemImage: "plus") { onSelectBoardExample(example) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(example.rawValue, systemImage: "rectangle.3.group").font(.headline)
                                    Text("\(example.listSummaries.count) lists · \(example.listSummaries.reduce(0) { $0 + $1.count }) items")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let onSelectMixedTemplate {
                    Section("Templates") {
                        ForEach(MixedListTemplate.allCases) { template in
                            DisclosureGroup(template.rawValue) {
                                Text(template.summary).foregroundStyle(.secondary)
                                ForEach(template.items.indices, id: \.self) { index in
                                    let item = template.items[index]
                                    VStack(alignment: .leading, spacing: 6) {
                                        if item.2 == .picture {
                                            CardCoverPreview(attachment: KanbanAttachment(mediaKind: .photo, exampleImage: template.illustration))
                                        }
                                        Label(item.0, systemImage: item.2.symbol).font(.headline)
                                        Text(item.1).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }
                                Button("Use \(template.rawValue)", systemImage: "plus") {
                                    onSelectMixedTemplate(template)
                                }
                            }
                        }
                    }
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

            .navigationTitle("Examples")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .databaseActivityOverlay()
        .confirmationDialog("Replace the Week Board with the example?", isPresented: $confirmsLoadWeek, titleVisibility: .visible) {
            Button("Load Example Week View", role: .destructive) {
                if onLoadExampleWeek?() == true {
                    hasUndoableWeek = true
                    dismiss()
                } else {
                    operationError = "The example Week Board could not be loaded. Your current Week Board was not changed."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the current active and archived Week lists and cards. Your previous Week Board is kept locally for undo. Personal collections stay unchanged.")
        }
        .confirmationDialog("Restore the previous Week Board?", isPresented: $confirmsUndoWeek, titleVisibility: .visible) {
            Button("Undo Last Load", role: .destructive) {
                if onUndoExampleWeek?() == true {
                    hasUndoableWeek = false
                    dismiss()
                } else {
                    operationError = "The saved Week Board snapshot could not be restored."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the current Week Board, including edits made since loading the example, with the saved Week Board from before the last load.")
        }
        .alert("Could not update Week Board", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
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
    let onCreateNote: (UUID, String, String, String, Date, ItemPresentation) throws -> Void /* Checked creation callback for a destination List */
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
            deleteBoardTitle:          "Delete \(collection.kind.rawValue)",
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
            onToggleMovedNoteBookmark: onToggleMovedNoteBookmark,
            boardAppearance:           $collection.boardAppearance
        )
        .databaseActivityOverlay()
        .onAppear {
            if collection.kind == .list {

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
                    TextField("Name", text: $draft.title).textInputAutocapitalization(.sentences)
                    TextField("Description (optional)", text: Binding(
                        get: { draft.collectionDescription ?? "" },
                        set: { draft.collectionDescription = $0 }
                    ), axis: .vertical).textInputAutocapitalization(.sentences)
                        .lineLimit(1...3)
                    LabeledContent("Type", value: draft.kind.rawValue)
                    Picker("Icon", selection: $draft.icon) {
                        ForEach(PersonalCollectionIcon.allCases, id: \.self) { icon in
                            Label(icon.title, systemImage: icon.rawValue).tag(icon)
                        }
                    }

                    .pickerStyle(.menu)
                    if draft.kind == .list, !draft.lists.isEmpty {
                        Toggle("Show icon in title bar", isOn: Binding(
                            get: { draft.lists[0].showsIconInHeader },
                            set: { value in
                                var appearance = draft.lists[0].appearance ?? ItemAppearance()
                                appearance.showsIconInHeader = value
                                draft.lists[0].appearance = appearance
                            }
                        ))
                    }
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
                    ForEach($draft.lists) { $list in
                        Picker(list.title, selection: $list.newItemPresentation) {
                            ForEach(ItemPresentation.allCases) { presentation in
                                Text(presentation.title).tag(presentation)
                            }
                        }
                    }

                    Text("Applies only to new items. Existing items keep their display format.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

                let starts = card.startDateKind.includesDate && (card.startDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false) /* Start date marker */
                let due = card.dueDateKind.includesDate && (card.dueDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false) /* Due date marker */

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
enum ActivityFocus: String, CaseIterable, Identifiable {
    case saved = "Saved", dueSoon = "Due soon", labels = "By label"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .saved: "bookmark"; case .dueSoon: "clock"; case .labels: "tag" }
    }
}
enum ActivityFocusSelection {
    static func isDueSoon(_ card: KanbanCard, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !card.isSectionDivider, !card.isTitleChecked, card.dueDateKind.includesDate, let due = card.dueDate,
              let horizon = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) else { return false }
        return due < horizon
    }
    static func dueReason(_ card: KanbanCard, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let due = card.dueDate else { return "" }
        if due < calendar.startOfDay(for: now) || (card.dueDateKind.includesTime && due < now) {
            return "Overdue · " + card.dueDateLabel
        }
        if calendar.isDate(due, inSameDayAs: now) { return "Due today · " + card.dueDateLabel }
        return "Due · " + card.dueDateLabel
    }
}

private struct SavedCardsView: View {
    let planningDocument: PlanningCalendarDocument?
    @AppStorage(ActivityRecentStore.key) private var recentData = Data()
    @AppStorage("Plenact.ActivityShowsCovers") private var showsCovers = true
    @State private var query = ""
    @State private var showsSearch = false
    @State private var confirmsClear = false
    @State private var historicalTarget: ActivityRecentResult?
    @State private var focus: ActivityFocus = .saved
    @State private var selectedLabelID: String?
    @State private var focusLabelLibrary = LabelLibraryStore.load()
    private var focusCalendar: Calendar { planningDocument?.calendar ?? .current }

    private var availableFocusItems: [ActivityRecentResult] {
        var items: [ActivityRecentResult] = []
        for week in planningDocument?.weeks ?? [] {
            let current = week.startKey == planningDocument?.currentWeekKey
            for list in (current ? lists : week.collection.lists) where !list.isArchived {
                for card in list.cards where !card.isSectionDivider {
                    items.append(ActivityRecentResult(item: LibraryRecentItem(collectionID: week.id, cardID: card.id), card: card, list: list,
                        location: list.title + " · " + week.compactRangeTitle, week: week, isCurrent: current))
                }
            }
        }
        for collection in collections where collection.isActive {
            for list in collection.lists where !list.isArchived {
                for card in list.cards where !card.isSectionDivider {
                    items.append(ActivityRecentResult(item: LibraryRecentItem(collectionID: collection.id, cardID: card.id), card: card, list: list,
                        location: collection.title == list.title ? collection.title : collection.title + " · " + list.title, week: nil, isCurrent: false))
                }
            }
        }
        return items
    }
    private var availableFocusLabels: [KanbanLabel] {
        let assigned = Set(availableFocusItems.flatMap { $0.card.labelIDs })
        return focusLabelLibrary.labels.filter { assigned.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var selectedFocusLabel: KanbanLabel? {
        availableFocusLabels.first { $0.id == selectedLabelID }
    }
    private var focusedItems: [ActivityRecentResult] {
        let items = availableFocusItems.filter { matches($0.card.word, $0.location) }
        switch focus {
        case .saved: return []
        case .dueSoon:
            return items.filter { ActivityFocusSelection.isDueSoon($0.card, calendar: focusCalendar) }.sorted {
                if $0.card.dueDate != $1.card.dueDate { return ($0.card.dueDate ?? .distantFuture) < ($1.card.dueDate ?? .distantFuture) }
                return $0.id < $1.id
            }
        case .labels:
            guard let selectedLabelID else { return [] }
            return items.filter { $0.card.labelIDs.contains(selectedLabelID) }
        }
    }
    private var focusHeading: some View {
        Menu {
            Picker("Show items", selection: $focus) {
                ForEach(ActivityFocus.allCases) { option in
                    Label(option.rawValue, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Label(focus.rawValue, systemImage: focus.symbol).font(.title2.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }.foregroundStyle(.primary).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .accessibilityLabel("Activity view: " + focus.rawValue)
    }
    private var focusContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if focus == .labels {
                Menu {
                    ForEach(availableFocusLabels) { label in
                        Button { selectedLabelID = label.id } label: {
                            Label(label.name, systemImage: selectedLabelID == label.id ? "checkmark" : "tag")
                        }
                    }
                } label: {
                    HStack {
                        if let label = selectedFocusLabel { KanbanLabelChip(label: label) }
                        else { Text("Choose a label") }
                        Image(systemName: "chevron.down").font(.caption)
                    }.frame(minHeight: 44)
                }.disabled(availableFocusLabels.isEmpty)
                Text("Cards and notes using this label across your Week and Plans.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Unfinished items that are overdue or due within the next 7 days.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if focusedItems.isEmpty {
                Text(focus == .labels
                    ? (availableFocusLabels.isEmpty ? "Add labels to a card or note to browse them here." : "No items match this label and search.")
                    : "Nothing due soon matches this view.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(focusedItems) { result in
                Button { openRecent(result) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: result.card.presentation == .note ? "note.text" : "rectangle")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.card.word).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(result.location).font(.caption).foregroundStyle(.secondary)
                            Text(focus == .dueSoon ? ActivityFocusSelection.dueReason(result.card, calendar: focusCalendar) : "Label: " + (selectedFocusLabel?.name ?? ""))
                                .font(.caption).foregroundStyle(focus == .dueSoon ? Color.orange : Color.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityHint("Opens this item in " + result.location)
            }
        }.padding(16).modifier(TodayPanelSurface())
    }


    private struct ActivityRecentResult: Identifiable {
        let item: LibraryRecentItem
        let card: KanbanCard
        let list: KanbanList
        let location: String
        let week: DatedPlanningWeek?
        let isCurrent: Bool
        var id: String { item.id }
    }
    private func matches(_ title: String, _ location: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (title + " " + location).localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private var recents: [ActivityRecentResult] {
        let items = recentData.isEmpty ? ActivityRecentStore.load() : ((try? JSONDecoder().decode([LibraryRecentItem].self, from: recentData)) ?? [])
        return items.compactMap { item in
            if let collection = collections.first(where: { $0.id == item.collectionID && $0.isActive }),
               let list = collection.lists.first(where: { !$0.isArchived && $0.cards.contains(where: { $0.id == item.cardID && !$0.isSectionDivider }) }),
               let card = list.cards.first(where: { $0.id == item.cardID }), matches(card.word, collection.title + " " + list.title) {
                return ActivityRecentResult(item: item, card: card, list: list, location: collection.title == list.title ? collection.title : collection.title + " · " + list.title, week: nil, isCurrent: false)
            }
            guard let week = planningDocument?.weeks.first(where: { $0.id == item.collectionID }) else { return nil }
            let current = week.startKey == planningDocument?.currentWeekKey
            let source = current ? lists : week.collection.lists
            guard let list = source.first(where: { !$0.isArchived && $0.cards.contains(where: { $0.id == item.cardID && !$0.isSectionDivider }) }),
                  let card = list.cards.first(where: { $0.id == item.cardID }), matches(card.word, list.title) else { return nil }
            return ActivityRecentResult(item: item, card: card, list: list, location: list.title + " · " + week.compactRangeTitle, week: week, isCurrent: current)
        }
    }
    private func openRecent(_ result: ActivityRecentResult) {
        historicalTarget = result
    }
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent").font(.caption).foregroundStyle(.secondary)
            Text("Pick up where you left off").font(.title3.weight(.semibold))
            if recents.isEmpty {
                Text(query.isEmpty ? "Open a card or note in Today, Week, or Plans to find it here." : "No recent items match your search.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recents) { result in
                            Button { openRecent(result) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    if showsCovers, let cover = result.card.coverAttachment {
                                        CardCoverPreview(attachment: cover, height: 64).frame(height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Text(result.card.word).font(.subheadline.weight(.semibold)).lineLimit(3)
                                    Spacer(minLength: 0)
                                    Text(result.location).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .padding(12).frame(width: 156, height: showsCovers ? 210 : 144, alignment: .topLeading)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityHint("Reopen this item in " + result.location)
                        }
                    }
                }
            }
        }
    }


    let lists: [KanbanList] /* Current Board snapshot */
    let savedCardIDs: Set<Int> /* Local bookmark set */
    @Binding var collections: [PersonalCollection] /* Collections whose archived boards can be restored */
    let onOpenBoardCard: (Int, Int) -> Void /* Open the exact bookmarked item */
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
                guard savedCardIDs.contains(card.id), !card.isSectionDivider, matches(card.word, list.title) else {

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
    private var archivedCollections: [PersonalCollection] {
        collections.filter { $0.isArchived == true && matches($0.title, "") }
    }
    private var personalSavedCards: [PersonalCollectionBookmarkedCard] { /* Active personal bookmarks for Saved */
        collections.filter(\.isActive).flatMap(\.bookmarkedCards).filter { matches($0.card.word, $0.collectionTitle + " " + $0.listTitle) }
    }


    ///
    /// @fcn        SavedCardsView.body
    /// @brief      Present device-local bookmarks and archived full boards
    /// @details    Shows available bookmarked cards with list navigation and, when present,
    ///             archived board snapshots with Restore actions and nested-content counts
    ///
    /// @return     (some View) paper-backed Saved surface
    /// @post       Restore delegates to the root save-first callback; bookmarked-card selection
    ///             opens the bookmarked item directly without removing the bookmark
    ///
    var body: some View { /* Saved-card directory and navigation destinations */

        ZStack {
            TodayPaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Activity").font(.largeTitle.weight(.bold))
                            Spacer()
                            Button { showsSearch.toggle(); if !showsSearch { query = "" } } label: { Image(systemName: "magnifyingglass") }
                                .accessibilityLabel("Search Activity")
                            Menu {
                                Toggle("Show cover previews", isOn: $showsCovers)
                                Button("Clear recent history", systemImage: "trash", role: .destructive) { confirmsClear = true }
                            } label: { Image(systemName: "ellipsis.circle") }
                                .accessibilityLabel("Activity options")
                        }
                        Text("Recent work and saved favorites")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    .frame(maxWidth: .infinity, alignment: .leading)

                    if showsSearch {
                        TextField("Find in Activity", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                    }
                    recentSection
                    focusHeading
                    if focus != .saved {
                        focusContent
                    } else {
                    VStack(alignment: .leading, spacing: 10) {
                        if savedCards.isEmpty && personalSavedCards.isEmpty {

                            Label(query.isEmpty ? "No saved items yet" : "No saved items match", systemImage: "bookmark")
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
                                        if let item = availableFocusItems.first(where: { $0.isCurrent && $0.list.id == result.listID && $0.card.id == result.card.id }) {
                                            openRecent(item)
                                        }
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
                                Text("Plans")
                                    .font(.headline)
                                ForEach(personalSavedCards) { result in
                                    Button {
                                        if let item = availableFocusItems.first(where: { $0.item.collectionID == result.collectionID && $0.list.id == result.listID && $0.card.id == result.card.id }) {
                                            openRecent(item)
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "bookmark.fill")
                                                .foregroundStyle(.orange)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(result.card.word)
                                                    .foregroundStyle(.primary)
                                                Text(result.collectionTitle == result.listTitle ? result.collectionTitle : result.collectionTitle + " · " + result.listTitle)
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
                    }

                    if focus == .saved && collections.contains(where: {

                        $0.isArchived == true
                    }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Archived Collections").font(.title2.weight(.semibold))
                            ForEach(archivedCollections) { board in
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

                            Text("Restored boards appear in Plans. Restoring a Week Board creates a separate board and leaves your current Week unchanged.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        .padding(16)
                        .modifier(TodayPanelSurface())
                    }
                }

                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            .background(.clear)
        }

        .onAppear { focusLabelLibrary = LabelLibraryStore.load() }
        .onChange(of: focus) { _, value in
            if value == .labels && selectedFocusLabel == nil { selectedLabelID = availableFocusLabels.first?.id }
        }
        .onChange(of: availableFocusLabels) { _, labels in
            if !labels.contains(where: { $0.id == selectedLabelID }) { selectedLabelID = labels.first?.id }
        }
        .confirmationDialog("Clear recent history?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear recent history", role: .destructive) { ActivityRecentStore.clear() }
        } message: { Text("Removes recent shortcuts from Activity and Plans. Your cards, notes, and Saved items stay intact.") }
        .fullScreenCover(item: $historicalTarget) { result in
            if let week = result.week {
                PlanningCalendarWeekView(week: week, initialDayID: result.list.id, initialCardID: result.card.id, onLeaveForHome: { historicalTarget = nil })
            } else if let collection = collections.first(where: { $0.id == result.item.collectionID && $0.isActive }) {
                PlanningSearchLibraryView(collection: collection, initialListID: result.list.id, initialCardID: result.card.id,
                    onLeaveForHome: { historicalTarget = nil })
            }
        }

        .confirmationDialog("Delete \(deletingBoard?.title ?? "collection")?", isPresented: Binding(
            get: { deletingBoard != nil }, set: { if !$0 { deletingBoard = nil } }
        ), titleVisibility: .visible) {
            Button("Delete \(deletingBoard?.kind.rawValue ?? "item")", role: .destructive) {
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
                        Button("Delete \(collection.kind.rawValue)", systemImage: "trash", role: .destructive) { confirmsDeleteBoard = true }
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

            .confirmationDialog("Delete \(collection.kind.rawValue)?", isPresented: $confirmsDeleteBoard, titleVisibility: .visible) {
                Button("Delete \(collection.kind.rawValue)", role: .destructive) { if onDeleteBoard() { dismiss() } }
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
    let openCards: [KanbanCard] /* Incomplete items limited by the Today profile preference */
    let onToggleCard: (Int) -> Void /* Toggle local completion state */
    let onOpenCard: (KanbanCard) -> Void
    let onOpenTodayList: () -> Void /* Open the focused single-list Today view */

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    @ScaledMetric(relativeTo: .body) private var phoneRowHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var padRowHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var phoneTaskSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var padTaskSize: CGFloat = 20
    private var rowHeight: CGFloat { isPad ? padRowHeight : phoneRowHeight }
    @Environment(\.displayScale) private var displayScale
    @State private var measuredListingHeight: CGFloat?

    private var listingCapacity: CGFloat { rowHeight * 4 + 3 / displayScale }
    private var listingHeight: CGFloat {
        measuredListingHeight ?? (rowHeight * CGFloat(min(openCards.count, 4))
            + CGFloat(max(0, min(openCards.count, 4) - 1)) / displayScale)
    }

    private var focusTitle: some View {
        Text("Today's Focus")
            .font(isPad ? .title2.weight(.semibold) : .title3.weight(.semibold))
    }

    private var completionButton: some View {
        let completedCount = cards.filter(\.isTitleChecked).count
        return Button(action: onOpenTodayList) {
            Text("\(completedCount) of \(cards.count) complete")
                .font(isPad ? .subheadline : .caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(completedCount) of \(cards.count) complete")
        .accessibilityHint(completedCount < cards.count
            ? "Opens today's list at the first unfinished item"
            : "Opens today's completed list")
        .accessibilityIdentifier("today.focus.progress")
    }

    private var focusRows: some View {
        VStack(spacing: 0) {
            ForEach(openCards) { card in
                HStack(spacing: 8) {
                    Button {
                        onToggleCard(card.id)
                    } label: {
                        Image(systemName: "square")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: isPad ? 48 : 44, height: rowHeight)
                            .contentShape(Rectangle())
                    }

                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark \(card.word) complete")

                    Button { onOpenCard(card) } label: {
                        HStack {
                            ItemAppearanceMark(appearance: card.appearance)
                            Text(card.word)
                                .font(.system(size: isPad ? padTaskSize : phoneTaskSize))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }

                        .frame(maxWidth: .infinity, minHeight: rowHeight)
                        .contentShape(Rectangle())
                    }

                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(card.word)")
                }

                if card.id != openCards.last?.id {

                    Divider()
                }
            }
        }
    }


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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    focusTitle.fixedSize()
                    Spacer(minLength: 0)
                    if list != nil { completionButton.fixedSize() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    focusTitle
                    if list != nil { completionButton }
                }
            }

            if list != nil {
                let completedCount = cards.filter(\.isTitleChecked).count

                ProgressView(value: Double(completedCount), total: Double(max(cards.count, 1)))
                    .tint(.accentColor)
                    .opacity(cards.isEmpty ? 0 : 1)
                    .accessibilityHidden(cards.isEmpty)

                Group {
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
                        if openCards.count > 4 {
                            ScrollView(.vertical) {
                                focusRows
                            }
                            .frame(height: rowHeight * 4 + 3 / displayScale)
                            .accessibilityLabel("Today's Focus items")
                            .accessibilityHint("Scroll to see more unfinished items")
                        } else {
                            focusRows
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    measuredListingHeight = height
                }

                Button(action: onOpenTodayList) {
                    Label("Open today", systemImage: "arrow.right")
                        .font(.subheadline)
                        .frame(minHeight: 32)
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
        .modifier(TodayPanelSurface(backgroundOpacity: 0.5))
        .padding(.bottom, list == nil ? 0 : max(0, listingCapacity - listingHeight))
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

    var backgroundOpacity: Double = 1


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
                    .opacity(backgroundOpacity)
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

private struct LibraryExamplePreview: Identifiable {
    var id = UUID()
    let title: String
    let summary: String
    let lists: [KanbanList]
}

private struct LibraryExamplePreviewView: View {
    let preview: LibraryExamplePreview
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(preview.summary).foregroundStyle(.secondary)
                    ForEach(preview.lists) { list in
                        VStack(alignment: .leading, spacing: 12) {
                            if preview.lists.count > 1 { Text(list.title).font(.title2.bold()) }
                            ForEach(list.cards) { card in
                                if card.isSectionDivider {
                                    Divider().padding(.vertical, 6)
                                } else {
                                    KanbanCardView(card: card, height: 100, displaySettings: BoardDisplaySettings(), labelLibrary: .starter,
                                        onUpdateCard: { _ in }, onDeleteCard: {}, onArchiveCard: {}, onToggle: {})
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}


// Shared owner-qualified browsing prevents card/list IDs on different boards from colliding.
struct WorkspaceListReference: Hashable, Codable, Identifiable {
    let ownerID: UUID
    let listID: Int
    var id: String { "\(ownerID):\(listID)" }
}
struct WorkspaceListDestination: Identifiable {
    let owner: PersonalCollection
    let list: KanbanList
    var reference: WorkspaceListReference { WorkspaceListReference(ownerID: owner.id, listID: list.id) }
    var id: String { reference.id }
}
struct WorkspaceLabelUsage: Identifiable {
    let label: KanbanLabel
    let matches: [PlanningSearchResult]
    var id: String { label.id }
}
enum WorkspaceBrowseIndex {
    static func owners(document: PlanningCalendarDocument?, library: [PersonalCollection]) -> [PersonalCollection] {
        (document?.weeks.map { week in
            var owner = week.collection
            owner.title = (week.startKey == document?.currentWeekKey ? "This Week · " : "") + week.rangeTitle
            return owner
        } ?? []) + library.filter(\.isActive)
    }
    static func lists(in owners: [PersonalCollection]) -> [WorkspaceListDestination] {
        owners.filter(\.isActive).flatMap { owner in
            owner.lists.filter { !$0.isArchived }.map { WorkspaceListDestination(owner: owner, list: $0) }
        }
    }
    static func labels(in owners: [PersonalCollection], catalog: LabelLibrary) -> [WorkspaceLabelUsage] {
        var matches: [String: [PlanningSearchResult]] = [:]
        for destination in lists(in: owners) {
            for card in destination.list.cards where !card.isSectionDivider {
                let result = PlanningSearchResult(weekKey: nil, collectionID: destination.owner.id,
                    collectionTitle: destination.owner.title, listID: destination.list.id,
                    listTitle: destination.list.title, card: card)
                for labelID in Set(card.labelIDs) { matches[labelID, default: []].append(result) }
            }
        }
        return catalog.labels.compactMap { label in
            guard let cards = matches[label.id], !cards.isEmpty else { return nil }
            return WorkspaceLabelUsage(label: label, matches: cards)
        }
    }
}
enum TodayListPins {
    static let key = "Plenact.TodayListShortcuts.v1"
    /// Seed only a fresh installation; saved empty collections or shortcut selections stay empty.
    static func loadInitialCollections(from defaults: UserDefaults = .standard) -> [PersonalCollection] {
        let existing = PersonalCollectionStore.load(from: defaults)
        let savedKeys = ["Plenact.PersonalCollections.v1", "Plenact.Board.v1", PlanningCalendarStore.key, key]
        guard savedKeys.allSatisfy({ defaults.object(forKey: $0) == nil }) else { return existing }

        let initial = ["On the Table", "In the Queue", "Scheduled"].map { DefaultListTutorial.makeStarter(title: $0) }

        do {
            try PersonalCollectionStore.saveChecked(initial, to: defaults)
            let pins = initial.map { WorkspaceListReference(ownerID: $0.id, listID: $0.lists[0].id) }
            defaults.set(encode(pins), forKey: key)
            return initial
        } catch {
            return existing
        }
    }

    static func normalized(_ pins: [WorkspaceListReference]) -> [WorkspaceListReference] {
        var seen = Set<WorkspaceListReference>()
        return Array(pins.filter { seen.insert($0).inserted }.prefix(6))
    }
    static func decode(_ data: Data) -> [WorkspaceListReference] {
        normalized((try? JSONDecoder().decode([WorkspaceListReference].self, from: data)) ?? [])
    }
    static func encode(_ pins: [WorkspaceListReference]) -> Data {
        (try? JSONEncoder().encode(normalized(pins))) ?? Data()
    }
}

struct TodayShortcutEditor: View {
    @State private var pins: [WorkspaceListReference]
    let owners: [PersonalCollection]
    let onSave: ([WorkspaceListReference]) -> Void
    @Environment(\.dismiss) private var dismiss
    init(pins: [WorkspaceListReference], owners: [PersonalCollection], onSave: @escaping ([WorkspaceListReference]) -> Void) {
        _pins = State(initialValue: TodayListPins.normalized(pins))
        self.owners = owners; self.onSave = onSave
    }
    private var available: [WorkspaceListDestination] { WorkspaceBrowseIndex.lists(in: owners) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pins) { reference in
                        let destination = available.first { $0.reference == reference }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(destination?.list.title ?? "Unavailable list")
                            Text(destination?.owner.title ?? "Archived or removed; remove this shortcut to free a space")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { pins.remove(atOffsets: $0) }
                    .onMove { pins.move(fromOffsets: $0, toOffset: $1) }
                } header: { Text("Pinned · \(pins.count) of 6") }
                footer: { Text("Drag to reorder. Removing a shortcut keeps its list and cards.") }
                ForEach(owners.filter(\.isActive)) { owner in
                    Section(owner.title) {
                        ForEach(owner.lists.filter { !$0.isArchived }) { list in
                            let reference = WorkspaceListReference(ownerID: owner.id, listID: list.id)
                            Button {
                                guard pins.count < 6, !pins.contains(reference) else { return }
                                pins.append(reference)
                            } label: {
                                HStack {
                                    Label(list.title, systemImage: list.appearance?.icon?.rawValue ?? owner.icon.rawValue)
                                    Spacer()
                                    Image(systemName: pins.contains(reference) ? "checkmark" : "plus.circle")
                                }
                                .frame(minHeight: 44)
                            }
                            .disabled(pins.contains(reference) || pins.count >= 6)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("My shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onSave(pins); dismiss() } }
            }
        }
    }
}

struct LibraryLabelMatchesView: View {
    let label: KanbanLabel
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var openedCard: PlanningSearchResult?
    @State private var query = ""
    private var matches: [PlanningSearchResult] {
        let owners = WorkspaceBrowseIndex.owners(document: access?.document, library: access?.library ?? [])
        let all = WorkspaceBrowseIndex.labels(in: owners, catalog: LabelLibraryStore.load()).first { $0.id == label.id }?.matches ?? []
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { query.isEmpty || $0.card.word.localizedStandardContains(query) || $0.listTitle.localizedStandardContains(query) || $0.collectionTitle.localizedStandardContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                if matches.isEmpty { Text("No active cards or notes match this label.").foregroundStyle(.secondary) }
                ForEach(matches) { result in
                    Button { openedCard = result } label: {
                        HStack(spacing: 12) {
                            Image(systemName: result.card.presentation == .note ? "note.text" : "rectangle")
                                .foregroundStyle(label.color.color)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.card.word).font(.headline).foregroundStyle(.primary)
                                Text(result.collectionTitle + " · " + result.listTitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.buttonStyle(.plain)
                }
            }
            .navigationTitle(label.name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find in this label")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(item: $openedCard) { result in
                if let week = access?.document.weeks.first(where: { $0.id == result.collectionID }) {
                    PlanningCalendarWeekView(week: week, initialDayID: result.listID, initialCardID: result.card.id,
                        onLeaveForHome: { openedCard = nil; dismiss() })
                } else if let collection = access?.library.first(where: { $0.id == result.collectionID && $0.isActive }) {
                    PlanningSearchLibraryView(collection: collection, initialListID: result.listID, initialCardID: result.card.id,
                        onLeaveForHome: { openedCard = nil; dismiss() })
                }
            }
        }
    }
}

struct WorkspacePinnedListView: View {
    let reference: WorkspaceListReference
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let week = access?.document.weeks.first(where: { $0.id == reference.ownerID }),
           week.collection.lists.contains(where: { $0.id == reference.listID && !$0.isArchived }) {
            PinnedListDayContent(collection: week.collection, reference: reference,
                date: week.dayListIDs.first(where: { $0.value == reference.listID }).flatMap { PlanningDate.date($0.key) },
                week: week, onClose: { dismiss() })
        } else if let collection = access?.library.first(where: { $0.id == reference.ownerID && $0.isActive }),
                  collection.lists.contains(where: { $0.id == reference.listID && !$0.isArchived }) {
            PinnedListDayContent(collection: collection, reference: reference, date: nil, week: nil, onClose: { dismiss() })
        } else {
            NavigationStack {
                Text("This list is archived or no longer available.").foregroundStyle(.secondary).padding()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
    }
}
private struct PinnedListDayContent: View {
    @State var collection: PersonalCollection
    let reference: WorkspaceListReference
    let date: Date?
    let week: DatedPlanningWeek?
    let onClose: () -> Void
    @Environment(\.planningCalendarAccess) private var access
    @State private var labels = LabelLibraryStore.load()
    @State private var reverting = false
    private func save(_ collection: PersonalCollection) -> Bool {
        if var week {
            week.collection = collection
            return access?.saveWeek(week) == true
        }
        return access?.saveLibrary(collection) == true
    }
    var body: some View {
        TodayListDetailView(lists: $collection.lists.activeLists, reservedLists: collection.lists.filter(\.isArchived),
            labelLibrary: $labels, savedCardIDs: $collection.savedCardIDs, listID: reference.listID,
            currentUserName: "You", onClose: onClose,
            onOpenWeek: { if var week { week.collection = collection; access?.openWeek(week) }; onClose() },
            onPermanentDelete: { cardID in
                var updated = collection
                BoardContentDeletion.card(cardID, in: &updated.lists, savedCardIDs: &updated.savedCardIDs)
                guard save(updated) else { return false }
                collection = updated; return true
            }, boardAppearance: collection.boardAppearance, returnDestinationTitle: "Today",
            boardViewActionTitle: week == nil ? "Back to Today" : "Switch to Week View", representedDate: date)
            .environment(\.cardMovementSource, collection.id)
            .onChange(of: collection) { old, updated in
                if reverting { reverting = false; return }
                if !save(updated) { reverting = true; collection = old }
            }
            .onChange(of: access?.document) { _, document in
                if let next = document?.weeks.first(where: { $0.id == reference.ownerID })?.collection, next != collection { collection = next }
            }
            .onChange(of: access?.library) { _, library in
                if let next = library?.first(where: { $0.id == reference.ownerID }), next != collection { collection = next }
            }
            .databaseActivityOverlay()
    }
}


struct TodayShortcutGrid: View {
    let pinned: [WorkspaceListDestination]
    let onOpen: (WorkspaceListReference) -> Void
    private var usesLargeIcons: Bool { pinned.count <= 3 }

    var body: some View {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(pinned) { destination in
                    Button { onOpen(destination.reference) } label: {
                        VStack(spacing: usesLargeIcons ? 12 : 8) {
                            Image(systemName: destination.list.appearance?.icon?.rawValue ?? destination.owner.icon.rawValue)
                                .font(.system(size: usesLargeIcons ? 40 : 25, weight: .medium))
                                .foregroundStyle((destination.list.appearance?.accent?.color ?? destination.owner.libraryIdentityColor))
                                .frame(width: usesLargeIcons ? 60 : 44, height: usesLargeIcons ? 60 : 44)
                            Text(destination.list.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                .foregroundStyle(.primary).multilineTextAlignment(.center)
                            Text("\(destination.list.cards.filter { !$0.isSectionDivider }.count) cards").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: usesLargeIcons ? 150 : 130, alignment: .top)
                    }.buttonStyle(.plain)
                        .accessibilityHint("Opens " + destination.owner.title + ", " + destination.list.title)
                }

            }
    }
}


/// A direct Focus destination: dismissing the detail returns to Today, without a Day screen.
private struct TodayFocusCardDetailView: View {
    let card: KanbanCard
    @Binding var lists: [KanbanList]
    @Binding var labelLibrary: LabelLibrary
    @Binding var savedCardIDs: Set<Int>
    let currentUserName: String
    let onDelete: (Int) -> Bool

    var body: some View {
        NavigationStack {
            CardDetailView(card: card, labelLibrary: $labelLibrary,
                currentUserName: currentUserName, savedCardIDs: $savedCardIDs,
                onTitleToggle: { updated in
                    guard let owner = lists.firstIndex(where: { $0.cards.contains(where: { $0.id == card.id && $0.createdAt == card.createdAt }) }),
                          let index = lists[owner].cards.firstIndex(where: { $0.id == card.id }) else { return }
                    lists[owner].cards[index] = updated
                },
                onArchive: {
                    guard let owner = lists.firstIndex(where: { $0.cards.contains(where: { $0.id == card.id && $0.createdAt == card.createdAt }) }) else { return }
                    lists[owner].archiveCard(id: card.id)
                },
                onDelete: { onDelete(card.id) }, listedOnDate: .now)
        }
    }
}
