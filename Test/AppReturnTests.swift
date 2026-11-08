// --------------------------------------------------------------------------------------------------
// @file       AppReturnTests.swift
// @brief      Monotonic background-return policy, editor protection and native viewport resets
// @details    Uses synthetic clocks, isolated defaults and an automated-Simulator window only.
// --------------------------------------------------------------------------------------------------
import SwiftUI
import XCTest
@testable import Plenact


/// Verifies that timeout navigation never replaces open work or changes shared records.
/// @section Purpose
///     Exercise five-minute boundaries without real waiting and scroll resets against native views.
@MainActor
final class AppReturnTests: XCTestCase
{


    /// @fcn AppReturnTests.testFreshActivationAndShortReturnPreserveContext
    /// @brief A new process and a short Home-screen interval issue no browsing reset
    /// @throws None
    func testFreshActivationAndShortReturnPreserveContext()
    {

        let now = ContinuousClock.now
        var session = AppReturnSession()
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

        let now = ContinuousClock.now
        var session = AppReturnSession()
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

        let now = ContinuousClock.now
        for (departure, arrival) in [(true, false), (false, true), (true, true)]
        {

            var session = AppReturnSession()
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

        let date = Date(timeIntervalSince1970: 1793620800)
        for firstWeekday in [1, 2]
        {

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
            calendar.firstWeekday = firstWeekday
            let week = DatedPlanningWeek.make(for: date, calendar: calendar)
            let first = try XCTUnwrap(week.dayListIDs[week.startKey])
            let undated = KanbanList(id: 900, title: "Undated", cards: [])
            let visible = [undated] + week.collection.lists.reversed()
            XCTAssertEqual(AppReturnSession.firstListID(in: week, lists: visible), first)
            let remaining = visible.filter { $0.id != first }
            XCTAssertNotEqual(AppReturnSession.firstListID(in: week, lists: remaining), undated.id)
            XCTAssertEqual(AppReturnSession.firstListID(in: nil, lists: [undated]), undated.id)
            XCTAssertNil(AppReturnSession.firstListID(in: week, lists: []))
        }
    }


    /// @fcn AppReturnTests.testViewportResetPreservesOtherOwnersAndPresentation
    /// @brief Reset offsets without touching zoom, presentation, another Board or shared user data
    /// @throws Isolated preference setup failure
    func testViewportResetPreservesOtherOwnersAndPresentation() throws
    {

        let domain = "Plenact.ReturnViewportTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let bytes = Data([0, 1, 255])
        defaults.set(bytes, forKey: "syntheticUserRecord")
        let memory = BoardViewportMemory(owner: "week", defaults: defaults)
        memory.state.scale = 0.7
        memory.state.panoramic = true
        memory.state.presentation = "standard"
        memory.state.visibleListID = 17
        memory.state.offsets = ["horizontal": 470, "list:17": 920]
        memory.flush()
        let other = BoardViewportMemory(owner: "personal", defaults: defaults)
        other.record(810, for: "horizontal")
        other.flush()
        let retained = defaults.data(forKey: other.key)
        memory.resetScrollOffsets()
        let restored = BoardViewportMemory(owner: "week", defaults: defaults)
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

        let domain = "Plenact.ReturnScrollTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        defer
        {

            defaults.removePersistentDomain(forName: domain)
            previous?.makeKeyAndVisible()
        }
        for horizontal in [false, true]
        {

            let memory = BoardViewportMemory(owner: horizontal ? "horizontal" : "vertical", defaults: defaults)
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
            let host = UIHostingController(rootView: screen(0))
            let window = UIWindow(windowScene: scene)
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
            let scroll = try XCTUnwrap(find(host.view))
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

        let domain = "Plenact.ReturnBoardTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let owner = UUID()
        let memory = BoardViewportMemory(owner: owner.uuidString, defaults: defaults)
        memory.state.scale = 0.62
        memory.state.panoramic = true
        memory.state.presentation = "standard"
        memory.flush()
        let lists = (0..<5).map
        {
            index in

            KanbanList(id: index, title: "Day " + String(index), cards: (0..<30).map
            {

                KanbanCard(id: index * 100 + $0, word: "Synthetic Card " + String($0), listTitle: "Day " + String(index))
            })
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            window.isHidden = true
            window.rootViewController = nil
            defaults.removePersistentDomain(forName: domain)
            previous?.makeKeyAndVisible()
        }
        func screen(_ request: Int) -> some View
        {

            ContentView(lists: .constant(lists), boardTitle: "Return test", onListsChanged: { _ in },
                personalCollectionID: owner, viewportDefaults: defaults)
                .environment(\.appReturnResetRequest, request)
        }
        func scrolls(_ view: UIView) -> [UIScrollView]
        {

            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrolls)
        }
        let host = UIHostingController(rootView: screen(0))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(600))
        host.view.layoutIfNeeded()
        let horizontal = try XCTUnwrap(scrolls(host.view).first
        {

            !($0 is UICollectionView) && $0.contentSize.width > $0.bounds.width + 100
        })
        let vertical = try XCTUnwrap(scrolls(host.view).first
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
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), nil)
    }


    /// @fcn AppReturnTests.testSceneWindowProbeRecognizesPresentedEditors
    /// @brief The return guard sees modal editors and releases its weak window after teardown
    /// @throws Scene or presentation failure
    func testSceneWindowProbeRecognizesPresentedEditors() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let reference = AppReturnWindow()
        let host = UIHostingController(rootView: Color.clear.background(AppReturnWindowProbe(reference: reference)))
        let window = UIWindow(windowScene: scene)
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
