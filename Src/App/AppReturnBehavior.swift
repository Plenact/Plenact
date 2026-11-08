// --------------------------------------------------------------------------------------------------
// @file       AppReturnBehavior.swift
// @brief      Device-local, in-process Home-screen return policy
// @details    Uses monotonic elapsed time, preserves open items/editors, and resets only the active tab.
//             No navigation state is added to shared preferences, packages or cloud data. A new process
//             uses the separate daily-opening rule; other launches start on Today. Restoring prior
//             navigation/drafts after termination is a separate feature.
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit


/// Decides whether a background return should resume or reset a tab's browsing context.
/// @section Purpose
///     Keep first activation and transient inactivity separate from a genuine Home-screen absence.
struct AppReturnSession
{

    static let timeout: Duration = .seconds(300)
    private var departure: ContinuousClock.Instant?
    private var protectedAtDeparture = false

    var hasBackgroundDeparture: Bool
    {

        departure != nil
    }

    var hasProtectedDeparture: Bool
    {

        protectedAtDeparture
    }


    /// @fcn AppReturnSession.firstListID
    /// @brief Prefer the first available dated List in the stored Week, independent of visual reordering
    /// @param[in] week Matching retained Week, if available
    /// @param[in] lists Active Lists currently displayed by the Board
    /// @return First dated List, a visible fallback, or nil for an empty Board
    static func firstListID(in week: DatedPlanningWeek?, lists: [KanbanList]) -> Int?
    {

        let active = Set(lists.map(\.id))
        let dated = week?.dayListIDs.sorted { $0.key < $1.key }.map(\.value) ?? []
        return dated.first { active.contains($0) } ?? lists.first?.id
    }


    /// @fcn AppReturnSession.leftForBackground
    /// @brief Record the first background transition without extending an existing absence
    /// @param[in] instant Monotonic departure time
    /// @param[in] protected Whether an item/editor was open
    /// @return Void; no persisted or shared data changes
    mutating func leftForBackground(at instant: ContinuousClock.Instant, protected: Bool)
    {

        departure = departure ?? instant
        protectedAtDeparture = protectedAtDeparture || protected
    }


    /// @fcn AppReturnSession.becameActive
    /// @brief Consume one background interval and resolve its return behavior
    /// @param[in] instant Monotonic arrival time, including device sleep
    /// @param[in] protected Whether an item/editor is currently open
    /// @return True only after five minutes with no protected editing context
    mutating func becameActive(at instant: ContinuousClock.Instant, protected: Bool) -> Bool
    {

        guard let departure else
        {

            return false
        }
        let shouldReset = !protected && !protectedAtDeparture && departure.duration(to: instant) >= Self.timeout
        self.departure = nil
        protectedAtDeparture = false
        return shouldReset
    }
}


/// Shares transient return protection and scoped reset requests within the current scene.
/// @section Purpose
///     Protect navigated Cards/Notes and inline writing without persisting user content or navigation.
private struct AppReturnProtectionKey: EnvironmentKey
{

    static let defaultValue: (UUID, Bool) -> Void =
    {
        _, _ in

    }
}


/// Carries a scoped, in-memory request to reset a tab's browsing position.
/// @section Purpose
///     Avoid reconstructing inactive tabs or adding navigation to the shared data model.
private struct AppReturnResetKey: EnvironmentKey
{

    static let defaultValue = 0
}


/// Optional explicit List target for a daily opening; ordinary timeout resets keep it nil.
/// @section Purpose
///     Distinguish today's List from the Week's first dated List without changing content.
private struct AppReturnTargetKey: EnvironmentKey
{

    static let defaultValue: Int? = nil
}


extension EnvironmentValues
{

    var appReturnTargetListID: Int?
    {

        get
        {

            self[AppReturnTargetKey.self]
        }
        set
        {

            self[AppReturnTargetKey.self] = newValue
        }
    }

    var appReturnProtection: (UUID, Bool) -> Void
    {

        get
        {

            self[AppReturnProtectionKey.self]
        }
        set
        {

            self[AppReturnProtectionKey.self] = newValue
        }
    }

    var appReturnResetRequest: Int
    {

        get
        {

            self[AppReturnResetKey.self]
        }
        set
        {

            self[AppReturnResetKey.self] = newValue
        }
    }
}


/// Keeps open content and active inline drafts ahead of the timeout policy.
/// @section Purpose
///     Uses a per-view token so closing one editor does not unprotect another visible editor.
private struct AppReturnProtection: ViewModifier
{

    let active: Bool
    @State private var token = UUID()
    @Environment(\.appReturnProtection) private var report

    /// @fcn AppReturnProtection.body
    /// @brief Register the visible editor's lifetime and current protection state
    /// @param[in] content Protected SwiftUI content
    /// @return Content with transient lifecycle reporting
    func body(content: Content) -> some View
    {

        content
            .onAppear
            {

                report(token, active)
            }
            .onChange(of: active)
            {
                _, value in

                report(token, value)
            }
            .onDisappear
            {

                report(token, false)
            }
    }
}


extension View
{

    /// Mark an open item or unfinished editor as protected from automatic return resets.
    func protectsAppReturn(_ active: Bool = true) -> some View
    {

        modifier(AppReturnProtection(active: active))
    }
}


/// Retains only a weak reference to the scene window for detecting presented sheets.
/// @section Purpose
///     Preserve all modal editors without coupling the timeout rule to each feature's sheet state.
@MainActor
final class AppReturnWindow
{

    weak var window: UIWindow?

    var hasPresentation: Bool
    {

        window?.rootViewController?.presentedViewController != nil
    }
}


/// Locates the owning scene window without retaining its UIKit hierarchy.
/// @section Purpose
///     Let the return policy preserve existing modal editors in the correct window.
struct AppReturnWindowProbe: UIViewRepresentable
{

    let reference: AppReturnWindow

    /// Reports its actual window after UIKit attaches the probe.
    /// @section Purpose
    ///     Keep window detection independent of global key-window selection.
    final class Marker: UIView
    {

        var reference: AppReturnWindow?

        /// @fcn AppReturnWindowProbe.Marker.didMoveToWindow
        /// @brief Refresh the weak scene-window reference after attachment
        /// @return Void; does not change presentation or navigation
        override func didMoveToWindow()
        {

            super.didMoveToWindow()
            if let window
            {

                reference?.window = window
            }
        }
    }

    /// @fcn AppReturnWindowProbe.makeUIView
    /// @brief Create a noninteractive scene-window probe
    /// @param[in] context SwiftUI representable lifecycle context
    /// @return Marker with a weak-window reference holder
    func makeUIView(context: Context) -> Marker
    {

        let view = Marker()
        view.isUserInteractionEnabled = false
        view.reference = reference
        return view
    }

    /// @fcn AppReturnWindowProbe.updateUIView
    /// @brief Refresh the attached scene reference without retaining the window
    /// @param[in] view Existing noninteractive marker
    /// @param[in] context SwiftUI representable lifecycle context
    /// @return Void; no user-data or presentation changes
    func updateUIView(_ view: Marker, context: Context)
    {

        view.reference = reference
        if let window = view.window
        {

            reference.window = window
        }
    }
}


extension AppRootView
{

    var hasProtectedAppReturnContext: Bool
    {

        !appReturnProtectionIDs.isEmpty || appReturnWindow.hasPresentation
    }


    /// @fcn AppRootView.handleAppReturn
    /// @brief Apply a timeout only after an actual background interval, before refreshing the Week
    /// @return Void; requests affect view state and existing device-local viewport memory only
    func handleAppReturn()
    {

        let fromBackground = appReturnSession.hasBackgroundDeparture
        let protected = hasProtectedAppReturnContext || appReturnSession.hasProtectedDeparture
        let reset = appReturnSession.becameActive(at: .now, protected: protected)
        guard hasLoadedBoard, !protected else
        {

            return
        }
        advancePlanningWeekIfNeeded()
        if fromBackground, openFirstDailyWeek()
        {

            return
        }
        guard reset else
        {

            return
        }
        switch selectedDestination
        {

        case .today:
            break
        case .board:
            weekReturnTargetListID = nil
            weekReturnResetRequest += 1
        case .lists:
            libraryReturnResetRequest += 1
        case .saved:
            activityRevisitDestination = nil
            activityReturnResetRequest += 1
        }
    }
}
