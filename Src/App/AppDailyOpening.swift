// --------------------------------------------------------------------------------------------------
// @file       AppDailyOpening.swift
// @brief      First daily opening to today's Week List, using a separate device-local preference domain
// @details    Local calendar-day boundaries start at midnight. A daily opening takes priority over the
//             five-minute browsing reset, but an eight-hour absence opens Today instead
//             Open work stays protected; no workspace/export keys are added
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass


/// Records the handled local day and background departure in device-local preferences
/// @section Purpose
///     Persist the once-per-day decision across launches without sharing navigation as user data
enum AppDailyOpening
{
    static let domain = "com.plenact.app.device-navigation"     /* Lookup or storage namespace */
    static let key    = "lastDailyWeekOpening"                  /* Lookup or persistence key   */


    static let departureKey = "lastBackgroundDeparture"         /* Device-local absence start */
    static let longAbsence: TimeInterval = 8 * 60 * 60          /* Direct-to-Today threshold  */


    /// @fcn AppDailyOpening.recordDeparture
    /// @brief Retain the first background timestamp across process termination
    /// @param[in] date Background transition time
    /// @param[in] defaults Device-local preference store
    /// @return Void; repeated background notifications retain the original departure
    static func recordDeparture(at date: Date, defaults: UserDefaults)
    {
        guard defaults.object(forKey: departureKey) == nil else
        {
            return
        }
        defaults.set(date, forKey: departureKey)
    }


    /// @fcn AppDailyOpening.consumeLongAbsence
    /// @brief Open Today after more than eight hours away, unless open work is protected
    /// @param[in] date Foreground arrival time
    /// @param[in] protected Whether navigation must preserve open work
    /// @param[in] defaults Device-local preference store
    /// @return True once for an eligible long absence; consumes the daily Week opening too
    static func consumeLongAbsence(at date: Date, protected: Bool, defaults: UserDefaults) -> Bool
    {
        let departure = defaults.object(forKey: departureKey) as? Date          /* Prior background time */

        defaults.removeObject(forKey: departureKey)
        guard !protected, let departure, date.timeIntervalSince(departure) > longAbsence else
        {
            return false
        }
        defaults.set(PlanningDate.key(date, calendar: .current), forKey: key)
        return true
    }


    /// @fcn AppDailyOpening.claim
    /// @brief Consume a new local day only when navigation is eligible and a target is available
    /// @param[in] date Current instant
    /// @param[in] calendar Device-local calendar supplying the time zone
    /// @param[in] protected Whether open work prevents navigation
    /// @param[in] targetAvailable Whether today's retained List can be opened safely
    /// @param[in] defaults Dedicated device-local preference domain or isolated test domain
    /// @return True once for the local day, without touching a workspace preference domain
    static func claim(
        at date:         Date,
        calendar:        Calendar,
        protected:       Bool,
        targetAvailable: Bool,
        defaults:        UserDefaults) -> Bool
    {
        guard !protected, targetAvailable else
        {
            return false
        }

        let day = PlanningDate.key(date, calendar: calendar)    /* Day under consideration */

        guard defaults.string(forKey: key) != day else
        {
            return false
        }
        defaults.set(day, forKey: key)
        return true
    }
}


extension AppRootView
{
    /// @fcn AppRootView.openTodayAfterLongAbsence
    /// @brief Give long absences priority over daily Week navigation while retaining open work
    /// @param[in] date Foreground arrival time
    /// @return True when Today was selected
    @discardableResult
    func openTodayAfterLongAbsence(at date: Date = .now) -> Bool
    {
        guard let defaults = UserDefaults(suiteName: AppDailyOpening.domain),
              AppDailyOpening.consumeLongAbsence(at: date,
                  protected: hasProtectedAppReturnContext || appReturnSession.hasProtectedDeparture,
                  defaults: defaults) else
        {
            return false
        }
        dailyOverview.cancel()
        dailyOverviewFade.cancel()
        selectedDestination = .today
        return true
    }


    /// @fcn AppRootView.openFirstDailyWeek
    /// @brief Select the current Week and today's List at its top on the first eligible opening of the day
    /// @param[in] date Current local instant, injected when needed by callers
    /// @return True after claiming the daily opening and issuing its navigation request
    /// @note Missing/archived targets or active editors defer the rule to a later foreground opening
    @discardableResult
    func openFirstDailyWeek(at date: Date = .now) -> Bool
    {
        if openTodayAfterLongAbsence(at: date)
        {
            return true
        }
        guard !hasProtectedAppReturnContext, let document = calendarDocument,
              document.currentWeekKey == PlanningDate.weekKey(date, calendar: document.calendar),
              let week = document.week(for: date),
              let target = week.dayListIDs[PlanningDate.key(date, calendar: document.calendar)],
              lists.contains(where: { $0.id == target && !$0.isArchived }),
              let defaults = UserDefaults(suiteName: AppDailyOpening.domain),
              AppDailyOpening.claim(at: date, calendar: .current, protected: false,
                  targetAvailable: true, defaults: defaults) else
        {
            return false
        }

        // A not-yet-mounted Week must read the same top position as an already mounted Week
        let memory =                                            /* Owner-scoped viewport state */
            BoardViewportMemory(owner: week.id.uuidString)

        memory.resetScrollOffsets()

        memory.state.visibleListID = target

        memory.flush()

        displayedPlanningWeek = nil
        displayedPlanningListID = nil
        boardTargetCardID = nil
        boardTargetListID = target
        weekReturnTargetListID = target
        weekReturnResetRequest += 1

        dailyOverview.arm()

        selectedDestination = .board

        return true
    }
}


/// One-shot monotonic deadline for an untouched daily or quick-add Week overview
/// @section Purpose
///     Cancellation consumes this opening; stale tasks cannot affect another opening
struct DailyWeekOverview
{
    static let delay: Duration = .milliseconds(1250)    /* Time before starting the transition */

    private(set) var returnDelay = Self.delay                   /* Delay for this transient Week preview */
    private(set) var waitsForCreatedContent = false             /* Wait until the new Card is revealed   */
    private(set) var id: UUID?                                  /* Record UUID                           */
    private(set) var deadline: ContinuousClock.Instant?         /* Monotonic transition deadline         */


    /// Arm an eligible daily opening or a successfully created inline Card
    mutating func arm(delay: Duration = Self.delay, waitsForCreatedContent: Bool = false)
    {
        returnDelay = delay
        self.waitsForCreatedContent = waitsForCreatedContent
        id = UUID()
        deadline = nil
    }


    /// Begin once the destination is visible and its scroll target has been consumed
    mutating func begin(at instant: ContinuousClock.Instant, contentRevealed: Bool = true) -> UUID?
    {
        guard !waitsForCreatedContent || contentRevealed, deadline == nil, let id else
        {
            return nil
        }

        deadline = instant.advanced(by: returnDelay)

        return id
    }


    /// Consume a matching deadline once, rejecting early or stale callbacks
    mutating func consume(_ request: UUID, at instant: ContinuousClock.Instant) -> Bool
    {
        guard id == request, let deadline, instant >= deadline else
        {
            return false
        }
        cancel()
        return true
    }


    /// Cancel permanently for this opening, including before its timer starts
    mutating func cancel()
    {
        id = nil
        deadline = nil
    }
}


extension AppRootView
{
    /// Start the transient overview only after Week appears and its target has settled
    func beginDailyOverview()
    {
        guard dailyWeekVisible, scenePhase == .active, selectedDestination == .board,
              boardTargetListID == nil, !hasProtectedAppReturnContext,
              let request = dailyOverview.begin(at: .now,
                  contentRevealed: CreatedContentReveal.shared.target == nil) else
        {
            return
        }
        let delay = dailyOverview.returnDelay           /* Capture the delay for this request */

        Task { @MainActor in

            try? await Task.sleep(for: delay)
            guard scenePhase == .active, selectedDestination == .board,
                  !hasProtectedAppReturnContext,
                  dailyOverview.consume(request, at: .now) else
            {
                return
            }
            dailyOverviewFade.transition(in: appReturnWindow.window,
                reduceMotion: UIAccessibility.isReduceMotionEnabled)
            {
                selectedDestination = .today
            }
        }
    }
}


/// Fades a transient in-memory snapshot while preserving both tab hierarchies
/// @section Purpose
///     No screen image is written to disk; backgrounding immediately removes the overlay
@MainActor
final class DailyOverviewFade
{
    private(set) weak var overlay: UIView?      /* Temporary display overlay */


    /// Switch tabs beneath a noninteractive snapshot, respecting Reduce Motion
    func transition(in window: UIWindow?, reduceMotion: Bool, selectToday: () -> Void)
    {
        cancel()
        guard !reduceMotion, let window, let snapshot = window.snapshotView(afterScreenUpdates: false) else
        {
            selectToday()
            return
        }

        snapshot.frame = window.bounds
        snapshot.isUserInteractionEnabled = false

        window.addSubview(snapshot)

        overlay = snapshot

        selectToday()
        DispatchQueue.main.async
        {
            [weak self, weak snapshot] in
            guard let self, let snapshot, self.overlay === snapshot else
            {
                return
            }
            UIView.animate(withDuration: 0.4375, delay: 0, options: [.allowUserInteraction])
            {
                snapshot.alpha = 0
            } completion:
            {
                _ in
                snapshot.removeFromSuperview()
            }
        }
    }


    /// Remove any unfinished visual transition on loss of foreground visibility
    func cancel()
    {
        overlay?.layer.removeAllAnimations()
        overlay?.removeFromSuperview()

        overlay = nil
    }
}


/// Reports actual Week appearance and passively observes interaction in its scene
/// @section Purpose
///     Touches fail immediately without delaying or preventing normal controls and scrolling
struct DailyOverviewProbe: UIViewControllerRepresentable
{
    let armed: Bool                     /* Pending one-shot transition */
    let onVisible: (Bool) -> Void       /* Visible callback            */
    let onInteraction: () -> Void       /* Interaction callback        */


    final class TouchObserver: UIGestureRecognizer
    {
        var interaction: (() -> Void)?          /* Interaction callback */


        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent)
        {
            interaction?()

            state = .failed
        }


        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool
        {
            false
        }


        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool
        {
            false
        }
    }


    final class Controller: UIViewController
    {
        var visible: ((Bool) -> Void)?                                  /* Current visibility state         */
        var armed                             = false                   /* Pending one-shot transition      */
        let observer                          = TouchObserver()         /* Native interaction observer      */
        var notifications: [NSObjectProtocol] = []                      /* Installed notification observers */
        weak var observedWindow: UIWindow?                              /* Observed window                  */


        override func viewDidAppear(_ animated: Bool)
        {
            super.viewDidAppear(animated)
            configure(armed: armed, interaction: observer.interaction ?? {})
            visible?(true)
        }


        override func viewWillDisappear(_ animated: Bool)
        {
            super.viewWillDisappear(animated)
            visible?(false)
        }


        /// Attach only during a pending overview; observe typing in this window as well as touches
        func configure(armed: Bool, interaction: @escaping () -> Void)
        {
            self.armed = armed
            observer.interaction = interaction

            guard armed else
            {
                disconnect()
                return
            }
            guard observedWindow == nil, let window = view.window else
            {
                return
            }

            observedWindow = window
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false

            window.addGestureRecognizer(observer)
            for name in [UITextField.textDidBeginEditingNotification, UITextField.textDidChangeNotification,
                         UITextView.textDidBeginEditingNotification, UITextView.textDidChangeNotification]
            {
                notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                    queue: .main)
                {
                    [weak self] notification in
                    MainActor.assumeIsolated
                    {
                        guard let self, let view = notification.object as? UIView,
                              view.window === self.observedWindow else
                        {
                            return
                        }
                        self.observer.interaction?()
                    }
                })
            }
        }


        /// Remove scene observers when the opening is consumed or its view is dismantled
        func disconnect()
        {
            observedWindow?.removeGestureRecognizer(observer)

            observedWindow = nil

            notifications.forEach(NotificationCenter.default.removeObserver)
            notifications.removeAll()
        }
    }


    func makeUIViewController(context: Context) -> Controller
    {
        let controller = Controller()           /* Native view controller */

        controller.view.isUserInteractionEnabled = false

        return controller
    }


    func updateUIViewController(_ controller: Controller, context: Context)
    {
        controller.visible = onVisible

        controller.configure(armed: armed, interaction: onInteraction)
    }


    static func dismantleUIViewController(_ controller: Controller, coordinator: ())
    {
        controller.disconnect()
    }
}
