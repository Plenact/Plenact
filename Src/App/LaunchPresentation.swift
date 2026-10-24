// --------------------------------------------------------------------------------------------------
// @file       LaunchPresentation.swift
// @brief      Launch progress, loading artwork, and welcome cues
// @details    Presents restoration progress and occasional welcome decoration with the user's
//             motion and lifecycle preferences.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Identifies stages in the launch presentation
///
/// @section    Purpose
///     Provides ordered restoration, planning, readiness, and welcome symbols and labels without
///     owning workspace restoration state.
///
enum PlenactLaunchStage: Int, CaseIterable
{


    case restore, plans, ready, welcome
    var symbol: String
    {

        switch self
        {

        case .restore:
                    "folder";

        case .plans:
                    "calendar";

        case .ready:
                    "slider.horizontal.3";

        case .welcome:
                    "sun.max"
        }

    }

    var label: String
    {

        switch self
        {

        case .restore:
                    "Restoring your workspace"
        case .plans:
                    "Preparing your plans"
        case .ready:
                    "Readying the app"
        case .welcome:
                    "Welcoming you in"
        }

    }

}


///
/// Represents progress through the launch presentation
///
/// @section    Purpose
///     Separates the current launch stage from completion so visible pacing can finish
///     independently of restoration work.
///
struct PlenactLaunchProgress: Equatable
{


    ///
    /// Classifies a launch indicator's progress
    ///
    /// @section    Purpose
    ///     Distinguishes stages that have not started, are running, or have completed for
    ///     consistent indicator rendering.
    ///
    enum Status
    {

        case waiting, running, complete
    }

    var stage: PlenactLaunchStage = .restore
    var finished = false


    ///
    /// @fcn        PlenactLaunchProgress.paced
    /// @brief      Pace visible launch stages from elapsed time
    /// @details    Limits the displayed stage to the supported range and withholds finished state until the minimum
    ///             presentation interval has elapsed.
    ///
    /// @param[in]  elapsed  Elapsed time in seconds since the current animation or launch anchor
    ///
    /// @return     (PlenactLaunchProgress) constructed value
    ///
    func paced(elapsed: TimeInterval) -> Self
    {

        let index = min(3, max(0, Int(max(0, elapsed) / 0.22)))
        return Self(
            stage: PlenactLaunchStage(rawValue: index) ?? .restore,
            finished: finished && elapsed >= 0.84)
    }


    ///
    /// @fcn        PlenactLaunchProgress.status
    /// @brief      Classify a launch stage as waiting, running, or complete
    /// @details    Treats earlier stages and a finished launch as complete while identifying the current unfinished
    ///             stage as running.
    ///
    /// @param[in]  step  Launch or review stage whose status should be evaluated
    ///
    /// @return     (Status) waiting, running, or complete for the requested launch stage
    ///
    func status(for step: PlenactLaunchStage) -> Status
    {

        if finished || step.rawValue < stage.rawValue
        {
            return .complete
        }

        return step == stage ? .running : .waiting
    }

}


///
/// Renders the launch-stage indicator row
///
/// @section    Purpose
///     Maps progress to stage symbols and animation while respecting the user's Reduce Motion
///     preference.
///
struct PlenactLaunchIndicators: View
{


    let progress: PlenactLaunchProgress
    var animates = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View
    {

        HStack(spacing: 44)
        {

            ForEach(PlenactLaunchStage.allCases, id: \.rawValue)
            {
                step in
                let status = progress.status(for: step)
                Image(systemName: step.symbol)
                .font(.system(size: 25.3, weight: .light))
                .frame(width: 30.8, height: 35.2)
                .foregroundStyle(.white)
                .phaseAnimator(status == .running && animates && !reduceMotion ? [false, true] : [false])
                {

                icon, bright in
                    icon.opacity(status == .waiting ? 0 : (status == .complete ? 0.85 : (bright ? 0.9 : 0.4)))
                }
                animation:
                {
                    _ in
                    .easeInOut(duration: 1.4)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: status)
            }

        }
        .accessibilityHidden(true)
    }

}


///
/// Paces launch indicators against elapsed time
///
/// @section    Purpose
///     Retains a local animation anchor and supplies paced progress through a timeline without
///     changing workspace data.
///
struct PlenactLaunchSequence: View
{


    let progress: PlenactLaunchProgress
    var animates: Bool
    @State private var startedAt = Date()
    var body: some View
    {

        TimelineView(.animation(minimumInterval: 1.0 / 30.0))
        {
            context in
            PlenactLaunchIndicators(
                progress: animates ? progress.paced(elapsed: context.date.timeIntervalSince(startedAt)) : progress,
                animates: animates)
        }

    }

}


///
/// Presents the launch artwork and progress overlay
///
/// @section    Purpose
///     Combines logo, shadow, and stage indicators while adapting decorative movement to
///     accessibility preferences.
///
struct PlenactLoadingView: View
{


    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animatesLogo = true
    var fadesShadow = false
    var progress = PlenactLaunchProgress()

    var body: some View
    {

        GeometryReader
        {
            geometry in
            ZStack
            {

                ZStack
                {

                    Image("LaunchShadow")
                    .resizable().scaledToFit()
                    .frame(width: 240, height: 240)
                    .opacity(fadesShadow ? 0 : 0.8)
                    .animation(.easeOut(duration: 1), value: fadesShadow)
                    .offset(x: 14, y: 14)
                    Image("LaunchLogo")
                    .resizable().scaledToFit()
                    .frame(width: 136, height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .phaseAnimator(reduceMotion || !animatesLogo ? [false] : [false, true])
                {
                    logo, expanded in
                    logo.scaleEffect(expanded ? 1.035 : 1)
                    .opacity(expanded ? 1 : 0.94)
                }
                animation:
                {
                    _ in
                    .easeInOut(duration: 1.8)
                }
                .accessibilityHidden(true)
                VStack(spacing: 8)
                {

                    Text("Plenact").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                    Text("Planning your life into action").font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
                }
                .offset(y: 124)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .offset(y: -geometry.size.height * 0.125)
            .overlay(alignment: .bottom)
            {

                PlenactLaunchSequence(progress: progress, animates: animatesLogo)
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


///
/// Coordinates occasional welcome cues
///
/// @section    Purpose
///     Tracks launch and meaningful foreground absence, then targets the appropriate planning or
///     profile entry point.
///
@MainActor
final class TodayWelcomeCue: ObservableObject
{


    ///
    /// Identifies the destination of a welcome cue
    ///
    /// @section    Purpose
    ///     Distinguishes the profile and planning settings targets used by the welcome
    ///     presentation.
    ///
    enum Target: Equatable
    {

        case profile, plan
    }

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


    ///
    /// @fcn        TodayWelcomeCue.init
    /// @brief      Create welcome-cue state using the supplied preferences store
    /// @details    Retains the store used to record foreground departures; constructing the cue does not start its
    ///             animation.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (TodayWelcomeCue) initialized instance
    ///
    init(defaults: UserDefaults = .standard)
    {
        self.defaults = defaults
    }


    ///
    /// @fcn        TodayWelcomeCue.becameActive
    /// @brief      Queue a welcome cue for an eligible foreground return
    /// @details    Greets on first activation or after the configured departure interval and resets departure
    ///             tracking.
    ///
    /// @param[in]  now  Reference time used instead of an implicit clock read
    ///
    /// @return     (Void) no return value
    ///
    func becameActive(at now: Date = .now)
    {

        let shouldGreet = !hasActivated || departure.map
        {
            now.timeIntervalSince($0) >= Self.returnInterval
        }
        == true
        hasActivated = true
        departure = nil
        if shouldGreet
        {
            pending = true;
            requestID += 1
        }

    }


    ///
    /// @fcn        TodayWelcomeCue.leftForeground
    /// @brief      Remember departure and stop the current welcome cue
    /// @details    Records the first departure timestamp in preferences and cancels any pending or illuminated cue.
    ///
    /// @param[in]  now  Reference time used instead of an implicit clock read
    ///
    /// @return     (Void) no return value
    ///
    func leftForeground(at now: Date = .now)
    {

        if departure == nil
        {

            departure = now
            defaults.set(now.timeIntervalSince1970, forKey: Self.lastDepartureKey)
        }

        cancel()
    }


    ///
    /// @fcn        TodayWelcomeCue.cancel
    /// @brief      Invalidate pending welcome animation work
    /// @details    Advances the generation token and clears the target and illumination without animation.
    ///
    /// @return     (Void) no return value
    ///
    func cancel()
    {

        generation += 1
        pending = false
        var transaction = Transaction();
        transaction.disablesAnimations = true
        withTransaction(transaction)
        {

            illuminated = false;
            target = nil
        }

    }


    ///
    /// @fcn        TodayWelcomeCue.highlights
    /// @brief      Check whether a particular welcome target is illuminated
    /// @details    Requires both a matching target and the current illumination flag.
    ///
    /// @param[in]  candidate  Welcome target whose current illumination should be checked
    ///
    /// @return     (Bool) true only when the requested target is the illuminated target
    ///
    func highlights(_ candidate: Target) -> Bool
    {
        target == candidate && illuminated
    }


    ///
    /// @fcn        TodayWelcomeCue.play
    /// @brief      Play the pending profile and plan welcome cues
    /// @details    Uses a generation token and cancellation checks around the injected asynchronous pauses, respects
    ///             Reduce Motion, and clears its own target on completion.
    ///
    /// @param[in]  reduceMotion    Whether accessibility preferences require reduced motion
    /// @param[in]  planPulseSpeed  Multiplier for the daily-plan welcome pulse speed
    /// @param[in]  pause           Injected asynchronous delay used to pace the welcome sequence and honor
    ///                             cancellation
    ///
    /// @return     (Void) no return value
    ///
    func play(
        reduceMotion: Bool, planPulseSpeed: Double = 1,
        pause: (Duration) async throws -> Void =
        {
            try await Task.sleep(for: $0)
        }
    ) async
    {

        guard pending else
        {
            return
        }

        pending = false
        let token = generation


        ///
        /// @fcn        TodayWelcomeCue.play.current
        /// @brief      Check that this welcome sequence is still current
        /// @details    Compares the captured generation with live state and rejects a cancelled task.
        ///
        /// @return     (Bool) true while this sequence's generation is current and its task is not cancelled
        ///
        func current() -> Bool
        {
            token == generation && !Task.isCancelled
        }


        ///
        /// @fcn        TodayWelcomeCue.play.light
        /// @brief      Set illumination using the requested motion policy
        /// @details    Updates directly with Reduce Motion or animates using the plan-specific pulse-speed
        ///             adjustment.
        ///
        /// @param[in]  value  New illumination state
        ///
        /// @return     (Void) no return value
        ///
        func light(_ value: Bool)
        {

            if reduceMotion
            {

                illuminated = value
            }
            else
            {

                withAnimation(.easeInOut(duration: 0.5 / (target == .plan ? planPulseSpeed : 1)))
                {

                    illuminated = value
                }

            }

        }

        defer
        {
            if token == generation
            {
                illuminated = false;
                target = nil
            }

        }

        do
        {

            try await pause(.milliseconds(650))
            for cue in [Target.profile, .plan]
            {

                guard current() else
                {
                    return
                }

                target = cue
                if reduceMotion
                {

                    light(true)
                    try await pause(.milliseconds(1000))
                    guard current() else
                    {
                        return
                    }

                    light(false)
                }
                else
                {

                    for _ in 0 ..< 2
                    {

                        guard current() else
                        {
                            return
                        }

                        light(true)
                        try await pause(.seconds(0.6 / (cue == .plan ? planPulseSpeed : 1)))
                        guard current() else
                        {
                            return
                        }

                        light(false)
                        try await pause(.seconds(0.6 / (cue == .plan ? planPulseSpeed : 1)))
                    }

                }

                guard current() else
                {
                    return
                }

                target = nil
                if cue == .profile
                {
                    try await pause(.milliseconds(500))
                }

            }

        }
        catch
        {  /* View disappearance/backgrounding cancels the finite sequence. */

        }

    }

}


///
/// Renders the decorative welcome glow
///
/// @section    Purpose
///     Highlights the requested control without changing layout, intercepting touches, or creating
///     accessibility elements.
///
struct TodayWelcomeGlow: ViewModifier
{


    let highlighted: Bool
    var circular = false
    private let softGold = Color(red: 0.94, green: 0.79, blue: 0.44)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    ///
    /// @fcn        TodayWelcomeGlow.body
    /// @brief      Apply the quiet welcome highlight to a view
    /// @details    Adds a decorative gold background and shadow and uses scale motion only when accessibility
    ///             preferences allow it.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) the quiet welcome highlight to a view
    ///
    func body(content: Content) -> some View
    {

        content
        .background
        {

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
