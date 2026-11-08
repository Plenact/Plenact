// --------------------------------------------------------------------------------------------------
// @file       AppReturnTests.swift
// @brief      Monotonic background-return policy, editor protection and native viewport resets
// @details    Uses synthetic clocks, isolated defaults and an automated-Simulator window only
// --------------------------------------------------------------------------------------------------
import SwiftUI
import XCTest
@testable import Plenact


/// Verifies that timeout navigation never replaces open work or changes shared records
/// @section Purpose
///     Exercise five-minute boundaries without real waiting and scroll resets against native views
@MainActor
final class AppReturnTests: XCTestCase
{


    /// Manual completion follows visual order, not weekday mappings or today's date
    func testManualWeekOpeningUsesLeftmostActiveList()
    {

        let date = Date(timeIntervalSince1970: 1_793_016_000) /* Date used by this operation */
        var week =                                            /* Synthetic week fixture      */
            DatedPlanningWeek.make(for: date, calendar: .current)
        var archived = /* Archived records or state */
            KanbanList(id: 9000, title: "Archived", cards: [])

        archived.isArchived = true
        week.collection.lists.insert(KanbanList(id: 9001, title: "Undated first", cards: []), at: 0)
        week.collection.lists.insert(archived, at: 0)

        let opening = /* Prepared explicit Week navigation */
            ManualWeekOpening(week: week, replaced: true)

        XCTAssertEqual(opening.firstListID, 9001)
        XCTAssertEqual(opening.title, "Week replaced")
        XCTAssertNotEqual(opening.firstListID, week.dayListIDs.sorted { $0.key < $1.key }.first?.value)
        week.collection.lists = []
        XCTAssertNil(ManualWeekOpening(week: week, replaced: false).firstListID)
    }


    /// Ordinary additive edits and day templates must not trigger Week completion navigation
    func testManualWeekCompletionScope()
    {

        let week = /* Synthetic week fixture */
            DatedPlanningWeek.make(for: .now, calendar: .current)

        XCTAssertEqual(ManualWeekOpening.completion(week: week, kind: .week,
            mode: .add, hadBaseline: false)?.title, "Week created")
        XCTAssertEqual(ManualWeekOpening.completion(week: week, kind: .week,
            mode: .replace, hadBaseline: true)?.title, "Week replaced")
        XCTAssertNil(ManualWeekOpening.completion(week: week, kind: .week,
            mode: .add, hadBaseline: true))
        XCTAssertNil(ManualWeekOpening.completion(week: week, kind: .day,
            mode: .replace, hadBaseline: true))
        XCTAssertNil(ManualWeekOpening.completion(week: week, kind: .day,
            mode: .add, hadBaseline: false))
    }


    /// A destination not yet mounted reads the new top position without resetting another owner
    func testManualWeekOpeningResetsOnlyItsViewport() throws
    {

        let domain = /* Lookup or storage namespace */
            "Plenact.Tests.ManualWeek." + UUID().uuidString
        let defaults = /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))
        let week = /* Synthetic week fixture */
            DatedPlanningWeek.make(for: .now, calendar: .current)
        let opening = /* Prepared explicit Week navigation */
            ManualWeekOpening(week: week, replaced: true)
        let memory = /* Owner-scoped viewport state */
            BoardViewportMemory(owner: week.id.uuidString, defaults: defaults)
        let other = /* Independent comparison value */
            BoardViewportMemory(owner: "other", defaults: defaults)

        defer { defaults.removePersistentDomain(forName: domain) }

        memory.record(450, for: "horizontal")
        memory.record(780, for: "list")
        memory.state.gallery = true
        memory.state.scale = 0.65

        memory.flush()
        other.record(333, for: "horizontal")
        other.flush()
        opening.resetViewport(in: defaults)

        let reopened = /* Instance reloaded from storage */
            BoardViewportMemory(owner: week.id.uuidString, defaults: defaults)
        let retained = /* State retained for recovery */
            BoardViewportMemory(owner: "other", defaults: defaults)

        XCTAssertEqual(reopened.state.visibleListID, opening.firstListID)
        XCTAssertTrue(reopened.state.offsets.values.allSatisfy { $0 == 0 })
        XCTAssertFalse(reopened.state.gallery)
        XCTAssertEqual(reopened.state.scale, 0.65)
        XCTAssertEqual(retained.state.offsets["horizontal"], 333)
    }


    /// Measure root navigation value sizes without mounting or importing a workspace
    func testRootNavigationValueSize()
    {

        let bodyBytes       = MemoryLayout<AppRootView.Body>.size /* Root view value size       */
        let navigationBytes =                                     /* Navigation view value size */
            MemoryLayout.size(ofValue: AppRootView().navigationContent)

        print("ROOT_BODY_BYTES", bodyBytes)
        print("ROOT_NAVIGATION_BYTES", navigationBytes)
        // Previously 19,944 and 18,187 bytes, repeatedly copied through the root builders
        XCTAssertLessThan(bodyBytes, 8_192)
        XCTAssertLessThan(navigationBytes, 8_192)
    }


    /// Verify visible-time boundaries, permanent cancellation and stale timer rejection
    func testDailyOverviewDeadlineAndCancellation()
    {

        let now      = ContinuousClock.now /* Current reference instant   */
        var overview = DailyWeekOverview() /* Overview comparison fixture */

        overview.arm()

        let first = overview.id! /* First comparison value */

        XCTAssertFalse(overview.consume(first, at: now.advanced(by: .seconds(30))))
        XCTAssertEqual(overview.begin(at: now), first)
        XCTAssertNil(overview.begin(at: now.advanced(by: .seconds(1))))
        XCTAssertFalse(overview.consume(first, at: now.advanced(by: .milliseconds(1249))))
        XCTAssertTrue(overview.consume(first, at: now.advanced(by: .milliseconds(1250))))
        XCTAssertFalse(overview.consume(first, at: now.advanced(by: .seconds(4))))
        overview.arm()
        overview.cancel()
        XCTAssertNil(overview.begin(at: now))
        overview.arm()

        let second = overview.begin(at: now)! /* Second comparison value */

        XCTAssertFalse(overview.consume(first, at: now.advanced(by: .seconds(4))))
        overview.cancel()
        XCTAssertFalse(overview.consume(second, at: now.advanced(by: .seconds(4))))
    }


    /// Observe typing only in the owning scene, then detach without affecting controls
    func testDailyOverviewObservesOnlyItsOwnWindow()
    {

        let window     = /* Synthetic scene window */
            UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let controller = DailyOverviewProbe.Controller() /* Native view controller */

        window.rootViewController = controller
        window.isHidden = false

        defer
        {

            controller.disconnect()

            window.isHidden = true
            window.rootViewController = nil

        }

        let field = /* Native input field */
            UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))

        controller.view.addSubview(field)

        var interactions = 0 /* Interactions comparison fixture */

        controller.configure(armed: true)
        {

            interactions += 1

        }
        XCTAssertTrue(controller.observer.view === window)
        XCTAssertFalse(controller.observer.cancelsTouchesInView)
        XCTAssertFalse(controller.observer.delaysTouchesBegan)
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: UITextField())
        XCTAssertEqual(interactions, 0)
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)
        XCTAssertEqual(interactions, 1)
        controller.configure(armed: false, interaction: {})
        XCTAssertNil(controller.observer.view)
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)
        XCTAssertEqual(interactions, 1)
    }


    /// Reduce Motion switches directly and cancellation removes transient visuals
    func testDailyOverviewFadeRespectsReduceMotion()
    {

        let fade     = DailyOverviewFade() /* Fade comparison fixture */
        var selected = false               /* Current selection       */

        fade.transition(in: nil, reduceMotion: true)
        {

            selected = true

        }
        XCTAssertTrue(selected)
        XCTAssertNil(fade.overlay)
        fade.cancel()
        XCTAssertNil(fade.overlay)
    }


    /// @fcn AppReturnTests.testFreshActivationAndShortReturnPreserveContext
    /// @brief A new process and a short Home-screen interval issue no browsing reset
    /// @throws None
    func testFreshActivationAndShortReturnPreserveContext()
    {

        let now     = ContinuousClock.now /* Current reference instant */
        var session = AppReturnSession()  /* Current operation session */

        XCTAssertFalse(session.becameActive(at: now, protected: false))
        session.leftForBackground(at: now, protected: false)
        XCTAssertFalse(session.becameActive(at: now.advanced(by: .seconds(299)), protected: false))
        XCTAssertFalse(session.becameActive(at: now.advanced(by: .seconds(900)), protected: false))
    }


    /// @fcn AppReturnTests.testTimeoutIsConsumedOnceAndDuplicateDepartureDoesNotExtendIt
    /// @brief The five-minute boundary resets exactly once; repeated lifecycle events keep the first timestamp
    /// @throws None
    func testTimeoutIsConsumedOnceAndDuplicateDepartureDoesNotExtendIt()
    {

        let now     = ContinuousClock.now /* Current reference instant */
        var session = AppReturnSession()  /* Current operation session */

        session.leftForBackground(at: now, protected: false)
        session.leftForBackground(at: now.advanced(by: .seconds(240)), protected: false)
        XCTAssertTrue(session.becameActive(at: now.advanced(by: .seconds(300)), protected: false))
        XCTAssertFalse(session.becameActive(at: now.advanced(by: .seconds(360)), protected: false))
        session.leftForBackground(at: now.advanced(by: .seconds(400)), protected: false)
        XCTAssertTrue(session.becameActive(at: now.advanced(by: .seconds(1500)), protected: false))
    }


    /// @fcn AppReturnTests.testOpenWorkOverridesTimeoutAtEitherLifecycleBoundary
    /// @brief An open item/editor before or after suspension prevents reset, including long absences
    /// @throws None
    func testOpenWorkOverridesTimeoutAtEitherLifecycleBoundary()
    {

        let now = ContinuousClock.now /* Current reference instant */

        for (departure, arrival) in [(true, false), (false, true), (true, true)]
        {

            var session = AppReturnSession() /* Current operation session */

            session.leftForBackground(at: now, protected: departure)
            XCTAssertFalse(session.becameActive(at: now.advanced(by: .seconds(86400)), protected: arrival))
            session.leftForBackground(at: now.advanced(by: .seconds(86401)), protected: false)
            XCTAssertTrue(session.becameActive(at: now.advanced(by: .seconds(86701)), protected: false))
        }
    }


    /// @fcn AppReturnTests.testWeekResetUsesStoredFirstDayBeforeUndatedOrReorderedLists
    /// @brief Respect Monday/Sunday boundaries and available dated Lists without changing content
    /// @throws Missing fixture date or day mapping
    func testWeekResetUsesStoredFirstDayBeforeUndatedOrReorderedLists() throws
    {

        let date = Date(timeIntervalSince1970: 1793620800) /* Date used by this operation */

        for firstWeekday in [1, 2]
        {

            var calendar = Calendar(identifier: .gregorian) /* Date calculation calendar */

            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
            calendar.firstWeekday = firstWeekday

            let week    = /* Synthetic week fixture */
                DatedPlanningWeek.make(for: date, calendar: calendar)
            let first   = try XCTUnwrap(week.dayListIDs[week.startKey]) /* First comparison value */
            let undated =                                               /* Undated List example   */
                KanbanList(id: 900, title: "Undated", cards: [])
            let visible = /* Current visibility state */
                [undated] + week.collection.lists.reversed()

            XCTAssertEqual(AppReturnSession.firstListID(in: week, lists: visible), first)

            let remaining = visible.filter { $0.id != first } /* Entries still to process */

            XCTAssertNotEqual(AppReturnSession.firstListID(in: week, lists: remaining), undated.id)
            XCTAssertEqual(AppReturnSession.firstListID(in: nil, lists: [undated]), undated.id)
            XCTAssertNil(AppReturnSession.firstListID(in: week, lists: []))
        }
    }


    /// @fcn AppReturnTests.testDailyOpeningIsOncePerLocalDayAcrossNewStoreInstances
    /// @brief First eligible opening claims the day; later launches on that day retain normal startup behavior
    /// @throws Isolated preference or date fixture failure
    func testDailyOpeningIsOncePerLocalDayAcrossNewStoreInstances() throws
    {

        let domain   = /* Lookup or storage namespace */
            "Plenact.DailyOpeningTests." + UUID().uuidString
        let defaults = /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))

        defer { defaults.removePersistentDomain(forName: domain) }

        var calendar = Calendar(identifier: .gregorian) /* Date calculation calendar */

        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))

        let date   = /* Date used by this operation */
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-07T18:00:00Z"))
        let source = Data([0, 255, 1]) /* Source value for this operation */

        defaults.set(source, forKey: "syntheticUserData")
        XCTAssertTrue(AppDailyOpening.claim(at: date, calendar: calendar, protected: false, targetAvailable: true, defaults: defaults))

        let reopened = /* Instance reloaded from storage */
            try XCTUnwrap(UserDefaults(suiteName: domain))

        XCTAssertFalse(AppDailyOpening.claim(at: date.addingTimeInterval(3600), calendar: calendar,
            protected: false, targetAvailable: true, defaults: reopened))
        XCTAssertEqual(reopened.string(forKey: AppDailyOpening.key), "2026-11-07")
        XCTAssertEqual(reopened.data(forKey: "syntheticUserData"), source)
        XCTAssertNotEqual(AppDailyOpening.domain, Bundle.main.bundleIdentifier)
    }


    /// @fcn AppReturnTests.testDailyOpeningChangesAtLocalMidnightNotUTCMidnight
    /// @brief Use the phone's local calendar day and permit exactly one opening after midnight
    /// @throws Isolated preference or date fixture failure
    func testDailyOpeningChangesAtLocalMidnightNotUTCMidnight() throws
    {

        let domain   = /* Lookup or storage namespace */
            "Plenact.DailyBoundaryTests." + UUID().uuidString
        let defaults = /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))

        defer { defaults.removePersistentDomain(forName: domain) }

        var calendar = Calendar(identifier: .gregorian) /* Date calculation calendar */

        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))

        let formatter = ISO8601DateFormatter() /* Date or value formatter    */
        let before    =                        /* State before the operation */
            try XCTUnwrap(formatter.date(from: "2026-11-08T05:59:59Z"))
        let after     = before.addingTimeInterval(1) /* State after the operation */

        XCTAssertTrue(AppDailyOpening.claim(at: before, calendar: calendar, protected: false, targetAvailable: true, defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: AppDailyOpening.key), "2026-11-07")
        XCTAssertTrue(AppDailyOpening.claim(at: after, calendar: calendar, protected: false, targetAvailable: true, defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: AppDailyOpening.key), "2026-11-08")
        XCTAssertFalse(AppDailyOpening.claim(at: after.addingTimeInterval(300), calendar: calendar,
            protected: false, targetAvailable: true, defaults: defaults))
    }


    /// @fcn AppReturnTests.testProtectedOrUnavailableMorningIsDeferredWithoutClaimingTheDay
    /// @brief Open work and missing target Lists prevent daily navigation without consuming its later opportunity
    /// @throws Isolated preference failure
    func testProtectedOrUnavailableMorningIsDeferredWithoutClaimingTheDay() throws
    {

        let domain   = /* Lookup or storage namespace */
            "Plenact.DeferredDailyTests." + UUID().uuidString
        let defaults = /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))

        defer { defaults.removePersistentDomain(forName: domain) }

        let date = Date(timeIntervalSince1970: 1794074400) /* Date used by this operation */

        for (protected, available) in [(true, true), (false, false), (true, false)]
        {

            XCTAssertFalse(AppDailyOpening.claim(at: date, calendar: .current,
                protected: protected, targetAvailable: available, defaults: defaults))
            XCTAssertNil(defaults.object(forKey: AppDailyOpening.key))
        }
        XCTAssertTrue(AppDailyOpening.claim(at: date, calendar: .current,
            protected: false, targetAvailable: true, defaults: defaults))
    }


    /// @fcn AppReturnTests.testRepeatedDSTHourDoesNotCreateAnotherDailyOpening
    /// @brief Repeated local clock times during fall-back remain one calendar day
    /// @throws Isolated preference or date fixture failure
    func testRepeatedDSTHourDoesNotCreateAnotherDailyOpening() throws
    {

        let domain   = /* Lookup or storage namespace */
            "Plenact.DailyDSTTests." + UUID().uuidString
        let defaults = /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))

        defer { defaults.removePersistentDomain(forName: domain) }

        var calendar = Calendar(identifier: .gregorian) /* Date calculation calendar */

        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))

        let formatter = ISO8601DateFormatter() /* Date or value formatter */
        let first     =                        /* First comparison value  */
            try XCTUnwrap(formatter.date(from: "2026-11-01T06:30:00Z"))
        let repeated  = /* Result of the repeated operation */
            try XCTUnwrap(formatter.date(from: "2026-11-01T07:30:00Z"))

        XCTAssertTrue(AppDailyOpening.claim(at: first, calendar: calendar, protected: false, targetAvailable: true, defaults: defaults))
        XCTAssertFalse(AppDailyOpening.claim(at: repeated, calendar: calendar,
            protected: false, targetAvailable: true, defaults: defaults))
    }


    /// @fcn AppReturnTests.testViewportResetPreservesOtherOwnersAndPresentation
    /// @brief Reset offsets without touching zoom, presentation, another Board or shared user data
    /// @throws Isolated preference setup failure
    func testViewportResetPreservesOtherOwnersAndPresentation() throws
    {

        let domain   = /* Lookup or storage namespace */
            "Plenact.ReturnViewportTests." + UUID().uuidString
        let defaults = /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))

        defer { defaults.removePersistentDomain(forName: domain) }

        let bytes = Data([0, 1, 255]) /* Serialized or original bytes */

        defaults.set(bytes, forKey: "syntheticUserRecord")

        let memory = /* Owner-scoped viewport state */
            BoardViewportMemory(owner: "week", defaults: defaults)

        memory.state.scale = 0.7
        memory.state.panoramic = true
        memory.state.presentation = "standard"
        memory.state.visibleListID = 17
        memory.state.offsets = ["horizontal": 470, "list:17": 920]

        memory.flush()

        let other = /* Independent comparison value */
            BoardViewportMemory(owner: "personal", defaults: defaults)

        other.record(810, for: "horizontal")
        other.flush()

        let retained = defaults.data(forKey: other.key) /* State retained for recovery */

        memory.resetScrollOffsets()

        let restored = /* Recovered state under review */
            BoardViewportMemory(owner: "week", defaults: defaults)

        XCTAssertEqual(restored.state.offsets, ["horizontal": 0, "list:17": 0])
        XCTAssertEqual(restored.state.scale, 0.7)
        XCTAssertTrue(restored.state.panoramic)
        XCTAssertEqual(restored.state.presentation, "standard")
        XCTAssertEqual(restored.state.visibleListID, 17)
        XCTAssertEqual(defaults.data(forKey: other.key), retained)
        XCTAssertEqual(defaults.data(forKey: "syntheticUserRecord"), bytes)
    }


    /// @fcn AppReturnTests.testResetRepositionsMountedNativeScrollViews
    /// @brief A reset updates real mounted scrollers, not only their retained offset dictionaries
    /// @throws Scene, scroll-discovery or isolated-storage failure
    func testResetRepositionsMountedNativeScrollViews() async throws
    {

        let domain   = /* Lookup or storage namespace */
            "Plenact.ReturnScrollTests." + UUID().uuidString
        let defaults = /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))
        let scene    = /* Owning window scene */
            try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow) /* Prior key window */

        defer
        {

            defaults.removePersistentDomain(forName: domain)
            previous?.makeKeyAndVisible()
        }
        for horizontal in [false, true]
        {

            let memory = /* Owner-scoped viewport state */
                BoardViewportMemory(owner: horizontal ? "horizontal" : "vertical", defaults: defaults)

            memory.record(470, for: "position")
            memory.flush()
            func screen(_ request: Int) -> some View
            {

                ScrollView(horizontal ? .horizontal : .vertical)
                {

                    Color.gray.frame(width: horizontal ? 2200 : 220, height: horizontal ? 120 : 3000)
                        .background(BoardViewportScrollProbe(memory: memory, key: "position", horizontal: horizontal))
                }
                .frame(width: 260, height: 230)
                .environment(\.appReturnResetRequest, request)
            }

            let host   = UIHostingController(rootView: screen(0)) /* Synthetic SwiftUI host */
            let window = UIWindow(windowScene: scene)             /* Synthetic scene window */

            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host

            window.makeKeyAndVisible()
            defer
            {

                window.isHidden = true
                window.rootViewController = nil

            }
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutIfNeeded()
            func find(_ view: UIView) -> UIScrollView?
            {

                if let scroll = view as? UIScrollView,
                   horizontal ? scroll.contentSize.width > scroll.bounds.width + 1 : scroll.contentSize.height > scroll.bounds.height + 1
                {

                    return scroll
                }
                return view.subviews.lazy.compactMap(find).first
            }

            let scroll = try XCTUnwrap(find(host.view)) /* Native scroll view */

            func offset() -> CGFloat
            {

                horizontal ? scroll.contentOffset.x + scroll.adjustedContentInset.left
                    : scroll.contentOffset.y + scroll.adjustedContentInset.top
            }
            XCTAssertEqual(offset(), 470, accuracy: 2)
            memory.resetScrollOffsets()

            host.rootView = screen(1)

            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(offset(), 0, accuracy: 2)
            scroll.setContentOffset(horizontal ? CGPoint(x: 530, y: 0) : CGPoint(x: 0, y: 530), animated: false)
            memory.flush()
            XCTAssertEqual(memory.state.offsets["position"] ?? -1, 530, accuracy: 2)
        }
    }


    /// @fcn AppReturnTests.testWeekReturnResetsTheActualBoardToFirstListTop
    /// @brief Reset a mounted zoomed Week after scrolling both axes, without changing its Cards
    /// @throws Scene, native scroll discovery or fixture failure
    func testWeekReturnResetsTheActualBoardToFirstListTop() async throws
    {

        let domain   = /* Lookup or storage namespace */
            "Plenact.ReturnBoardTests." + UUID().uuidString
        let defaults = /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))
        let owner    = UUID() /* Owning collection or Week   */
        let memory   =        /* Owner-scoped viewport state */
            BoardViewportMemory(owner: owner.uuidString, defaults: defaults)

        memory.state.scale = 0.62
        memory.state.panoramic = true
        memory.state.presentation = "standard"

        memory.flush()

        let lists = (0..<5).map /* Ordered List records */
        {
            index in

            KanbanList(id: index, title: "Day " + String(index), cards: (0..<30).map
            {

                KanbanCard(id: index * 100 + $0, word: "Synthetic Card " + String($0), listTitle: "Day " + String(index))
            })
        }
        let scene    = /* Owning window scene */
            try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow) /* Prior key window       */
        let window   = UIWindow(windowScene: scene)              /* Synthetic scene window */

        defer
        {

            window.isHidden = true
            window.rootViewController = nil

            defaults.removePersistentDomain(forName: domain)
            previous?.makeKeyAndVisible()
        }
        func screen(_ request: Int, target: Int? = nil) -> some View
        {

            ContentView(lists: .constant(lists), boardTitle: "Return test", onListsChanged: { _ in },
                personalCollectionID: owner, viewportDefaults: defaults)
                .environment(\.appReturnResetRequest, request)
                .environment(\.appReturnTargetListID, target)
        }
        func scrolls(_ view: UIView) -> [UIScrollView]
        {

            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrolls)
        }

        let host = UIHostingController(rootView: screen(0)) /* Synthetic SwiftUI host */

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host

        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(600))
        host.view.layoutIfNeeded()

        let horizontal = try XCTUnwrap(scrolls(host.view).first /* Horizontal scrolling axis */
        {

            !($0 is UICollectionView) && $0.contentSize.width > $0.bounds.width + 100
        })
        let vertical = try XCTUnwrap(scrolls(host.view).first /* Vertical comparison fixture */
        {

            $0 is UICollectionView && $0.contentSize.height > $0.bounds.height + 100
        })

        vertical.setContentOffset(CGPoint(x: vertical.contentOffset.x, y: 350 - vertical.adjustedContentInset.top), animated: false)
        try await Task.sleep(for: .milliseconds(400))
        horizontal.setContentOffset(CGPoint(x: 420 - horizontal.adjustedContentInset.left, y: horizontal.contentOffset.y), animated: false)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertGreaterThan(horizontal.contentOffset.x + horizontal.adjustedContentInset.left, 300)

        host.rootView = screen(1)

        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(horizontal.contentOffset.x + horizontal.adjustedContentInset.left, 0, accuracy: 4)
        XCTAssertEqual(vertical.contentOffset.y + vertical.adjustedContentInset.top, 0, accuracy: 4)

        host.rootView = screen(2, target: 2)

        try await Task.sleep(for: .milliseconds(600))
        XCTAssertGreaterThan(horizontal.contentOffset.x + horizontal.adjustedContentInset.left, 100)
        XCTAssertEqual(BoardViewportMemory(owner: owner.uuidString, defaults: defaults).state.visibleListID, 2)
        for list in scrolls(host.view) where list is UICollectionView && list.contentSize.height > list.bounds.height + 100
        {

            XCTAssertEqual(list.contentOffset.y + list.adjustedContentInset.top, 0, accuracy: 4)
        }
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), nil)
    }


    /// @fcn AppReturnTests.testSceneWindowProbeRecognizesPresentedEditors
    /// @brief The return guard sees modal editors and releases its weak window after teardown
    /// @throws Scene or presentation failure
    func testSceneWindowProbeRecognizesPresentedEditors() async throws
    {

        let scene     = /* Owning window scene */
            try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous  = scene.windows.first(where: \.isKeyWindow) /* Prior key window           */
        let reference = AppReturnWindow()                         /* Qualified record reference */
        let host      =                                           /* Synthetic SwiftUI host     */
            UIHostingController(rootView: Color.clear.background(AppReturnWindowProbe(reference: reference)))
        let window    = UIWindow(windowScene: scene) /* Synthetic scene window */

        window.rootViewController = host

        window.makeKeyAndVisible()
        defer
        {

            window.isHidden = true
            window.rootViewController = nil

            previous?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(reference.window === window)
        XCTAssertFalse(reference.hasPresentation)
        await withCheckedContinuation
        {
            continuation in

            host.present(UIViewController(), animated: false)
            {

                continuation.resume()
            }
        }
        XCTAssertTrue(reference.hasPresentation)
        await withCheckedContinuation
        {
            continuation in

            host.dismiss(animated: false)
            {

                continuation.resume()
            }
        }
        XCTAssertFalse(reference.hasPresentation)
    }
}


extension AppReturnTests
{

    /// @fcn AppReturnTests.testLongAbsenceOverridesDailyWeekOnlyBeyondEightHours
    /// @brief Verify the strict threshold, persisted departure, and once-only daily override
    /// @return Void; isolated preferences are removed after the test
    func testLongAbsenceOverridesDailyWeekOnlyBeyondEightHours() throws
    {

        let domain = "Plenact.LongAbsenceTests." + UUID().uuidString /* Isolated preference domain */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain)) /* Test-only preferences */
        let start = Date(timeIntervalSince1970: 1_794_000_000) /* Synthetic departure */

        defer
        {

            defaults.removePersistentDomain(forName: domain)
        }
        for elapsed in [28799.0, 28800.0, 28801.0, 43200.0]
        {

            AppDailyOpening.recordDeparture(at: start, defaults: defaults)
            AppDailyOpening.recordDeparture(at: start.addingTimeInterval(100), defaults: defaults)

            let reopened = try XCTUnwrap(UserDefaults(suiteName: domain)) /* Fresh store instance */
            let arrival = start.addingTimeInterval(elapsed) /* Synthetic return */

            XCTAssertEqual(AppDailyOpening.consumeLongAbsence(at: arrival,
                protected: false, defaults: reopened), elapsed > 28800)
            XCTAssertNil(reopened.object(forKey: AppDailyOpening.departureKey))
            if elapsed > 28800
            {

                XCTAssertFalse(AppDailyOpening.claim(at: arrival, calendar: .current,
                    protected: false, targetAvailable: true, defaults: reopened))
            }
            XCTAssertFalse(AppDailyOpening.consumeLongAbsence(at: arrival,
                protected: false, defaults: reopened))
        }
    }


    /// @fcn AppReturnTests.testLongAbsencePreservesOpenWorkAndHandlesMissingOrFutureDates
    /// @brief Reject navigation for protected work and absent or future departure evidence
    /// @return Void; no workspace preferences are used
    func testLongAbsencePreservesOpenWorkAndHandlesMissingOrFutureDates() throws
    {

        let domain = "Plenact.LongAbsenceTests." + UUID().uuidString /* Isolated preference domain */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain)) /* Test-only preferences */
        let now = Date() /* Synthetic arrival anchor */

        defer
        {

            defaults.removePersistentDomain(forName: domain)
        }
        XCTAssertFalse(AppDailyOpening.consumeLongAbsence(at: now, protected: false, defaults: defaults))
        AppDailyOpening.recordDeparture(at: now.addingTimeInterval(-43200), defaults: defaults)
        XCTAssertFalse(AppDailyOpening.consumeLongAbsence(at: now, protected: true, defaults: defaults))
        XCTAssertNil(defaults.object(forKey: AppDailyOpening.key))
        XCTAssertNil(defaults.object(forKey: AppDailyOpening.departureKey))
        AppDailyOpening.recordDeparture(at: now.addingTimeInterval(60), defaults: defaults)
        XCTAssertFalse(AppDailyOpening.consumeLongAbsence(at: now, protected: false, defaults: defaults))
    }
}
