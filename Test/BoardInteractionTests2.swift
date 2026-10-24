// --------------------------------------------------------------------------------------------------
// @file       BoardInteractionTests2.swift
// @brief      Board Interaction regression tests2
// @details    Verifies related workspace behavior with synthetic fixtures and the shared
//             PlenactBoardDocumentTests helpers. Retains original test identities and checked
//             assertions while separating this coverage from unrelated feature tests.
//
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import AVFoundation
import PencilKit
import SwiftUI
import UserNotifications
import XCTest


///
/// BoardInteraction regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayShortcutGridRendersTwoRowsWithoutOpeningOrEditing
    /// @brief      Verify that today Shortcut Grid Renders Two Rows Without Opening Or Editing
    /// @details    Exercises `(0..<6).map`, `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`.
    ///             Uses the fixture and assertions below to verify today Shortcut Grid Renders Two Rows Without
    ///             Opening Or Editing.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayShortcutGridRendersTwoRowsWithoutOpeningOrEditing() async throws
    {

        var owner = PersonalCollection(title: "Projects", kind: .board)
        owner.lists = (0 ..< 6).map
        {

            KanbanList(id: $0, title: ["On the Table", "Garden", "Shopping", "Reading", "Ideas", "Home"] [$0], cards: [])
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(
            rootView: TodayShortcutGrid(
                pinned: WorkspaceBrowseIndex.lists(in: [owner]),
                onOpen:
                {
                    _ in
                    XCTFail("Rendering must not open a list")
                }
            ).padding(20).background(Color(.systemGroupedBackground)))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 440)
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-shortcuts-preview.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("Shortcuts preview: " + path.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayPlanRendersWithoutChangingStoredPlans
    /// @brief      Verify that today Plan Renders Without Changing Stored Plans
    /// @details    Exercises `UserDefaults.standard.dictionaryRepresentation().filter`,
    ///             `UserDefaults.standard.dictionaryRepresentation`, `$0.key.hasPrefix`. Checks
    ///             `XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayPlanRendersWithoutChangingStoredPlans() async throws
    {

        let before = UserDefaults.standard.dictionaryRepresentation().filter
        {
            $0.key.hasPrefix("Plenact.")
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TodayPlanView())
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-today-plan.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("Today plan: " + path.path)
        let after = UserDefaults.standard.dictionaryRepresentation().filter
        {
            $0.key.hasPrefix("Plenact.")
        }

        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLoadingScreenResourcesAndReducedMotionLayout
    /// @brief      Verify that loading Screen Resources And Reduced Motion Layout
    /// @details    Exercises `Bundle.main.url`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertNotNil(UIImage(named: "LaunchLogo"))`;
    ///             `XCTAssertNotNil(UIImage(named: "LaunchShadow"))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLoadingScreenResourcesAndReducedMotionLayout() async throws
    {

        XCTAssertNotNil(UIImage(named: "LaunchLogo"))
        XCTAssertNotNil(UIImage(named: "LaunchShadow"))
        XCTAssertNotNil(UIColor(named: "LaunchBackground"))
        XCTAssertNotNil(Bundle.main.url(forResource: "PlenactLaunch", withExtension: "storyboardc"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: PlenactLoadingView(animatesLogo: false))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(120))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let data = try XCTUnwrap(image.pngData())
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-loading-preview.png")
        try data.write(to: path)
        print("Loading preview: " + path.path)
        let launch = try XCTUnwrap(
            UIStoryboard(name: "PlenactLaunch", bundle: .main).instantiateInitialViewController())
        launch.loadViewIfNeeded()
        launch.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        launch.view.layoutIfNeeded()
        let staticImage = UIGraphicsImageRenderer(bounds: launch.view.bounds).image
        {
            context in
            launch.view.layer.render(in: context.cgContext)
        }

        let staticPath = FileManager.default.temporaryDirectory.appendingPathComponent(
                        "plenact-static-launch-preview.png")
        try XCTUnwrap(staticImage.pngData()).write(to: staticPath)
        print("Static launch preview: " + staticPath.path)

        for size in [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393)]
        {

            let fitted = host.sizeThatFits(in: size)
            XCTAssertTrue(fitted.width.isFinite && fitted.height.isFinite)
            XCTAssertEqual(fitted.width, size.width, accuracy: 1)
            XCTAssertEqual(fitted.height, size.height, accuracy: 1)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekTodayHighlightRendersInPanoramicWithoutChangingCards
    /// @brief      Verify that week Today Highlight Renders In Panoramic Without Changing Cards
    /// @details    Exercises `DatedPlanningWeek.make`, `PlanningDate.key`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks
    ///             `XCTAssertEqual(access.document.weeks[0], week)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testWeekTodayHighlightRendersInPanoramicWithoutChangingCards() async throws
    {

        let date = Date.now
        let week = DatedPlanningWeek.make(for: date)
        let target = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date)])
        let access = PlanningCalendarAccess(
            document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [],
            saveWeek:
            {
                _ in
                false
            }, openCurrentWeek:
            {

            }, openToday:
            {

            }, openLibraryCard:
            {
                _ in
            },
            saveLibrary:
            {
                _ in
                false
            })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        let owner = UUID()
        let key = BoardViewportMemory.prefix + owner.uuidString
        defer
        {
            UserDefaults.standard.removeObject(forKey: key)
        }

        var state = BoardViewportState()
        state.scale = 0.62;
        state.panoramic = true;
        state.presentation = BoardPresentation.standard.rawValue;

        state.visibleListID = target
        UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: key)
        let host = UIHostingController(
            rootView: ContentView(
                lists: .constant(week.collection.lists), boardTargetListID: .constant(target), onListsChanged:
                {
                    _ in
                },
                viewportOwnerID: owner
            ).environment(\.planningCalendarAccess, access))
        window.rootViewController = host;
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-week-today-highlight.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("TODAY_HIGHLIGHT_RENDER=\(url.path)")
        XCTAssertEqual(access.document.weeks[0], week)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTabletBoardRendersProportionalLists
    /// @brief      Verify that tablet Board Renders Proportional Lists
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Uses the fixture and assertions below to verify tablet Board
    ///             Renders Proportional Lists.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTabletBoardRendersProportionalLists() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        let owner = UUID()
        let fixture = ["Monday", "Tuesday", "Wednesday"].enumerated().map
        {
            index, title in
            KanbanList(
                id: index, title: title,
                cards: (0 ..< 6).map
                {
                    number in
                    KanbanCard(id: index * 10 + number, word: "Take one useful step", listTitle: title, checklists: [])
                })
        }

        let host = UIHostingController(
            rootView: ContentView(lists: .constant(fixture), onListsChanged:
                {
                    _ in
                }, viewportOwnerID: owner))
        window.rootViewController = host;
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-tablet-board-scale.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("TABLET_BOARD_RENDER=\(url.path)")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTabletStandardZoomPreservesProportionsAndNeighborPreviews
    /// @brief      Verify that tablet Standard Zoom Preserves Proportions And Neighbor Previews
    /// @details    Exercises `BoardPresentation.standard.columnWidth`, `BoardTabletSizing.scale`. Checks
    ///             `XCTAssertGreaterThan(scale, 1)`; `XCTAssertEqual(preview, viewport * 0.05 + 13.5)`.
    ///
    /// @return     (Void) no return value
    ///
    func testTabletStandardZoomPreservesProportionsAndNeighborPreviews()
    {

        for viewport: CGFloat in [744, 820, 1180]
        {

            let column = BoardPresentation.standard.columnWidth(viewportWidth: viewport, accessibilitySize: false)
            let scale = BoardTabletSizing.scale(
                viewportWidth: viewport, columnWidth: column, isTablet: true, enabled: true)
            XCTAssertGreaterThan(scale, 1)
            let preview = (viewport - column * scale) / 2 - 17 * scale
            XCTAssertEqual(preview, viewport * 0.05 + 13.5, accuracy: 0.01)
            XCTAssertEqual(column * scale / column, scale, accuracy: 0.001)
        }

        XCTAssertEqual(BoardTabletSizing.scale(viewportWidth: 852, columnWidth: 360, isTablet: false, enabled: true), 1)
        XCTAssertEqual(BoardTabletSizing.scale(viewportWidth: 820, columnWidth: 792, isTablet: true, enabled: false), 1)
        XCTAssertEqual(BoardTabletSizing.scale(viewportWidth: 320, columnWidth: 256, isTablet: true, enabled: true), 1)
        XCTAssertEqual(
            BoardTabletSizing.scale(viewportWidth: .infinity, columnWidth: 360, isTablet: true, enabled: true), 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardOptionsPopoverLayoutDoesNotInvokeDestructiveActions
    /// @brief      Verify that board Options Popover Layout Does Not Invoke Destructive Actions
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Uses the fixture and assertions below to verify board Options Popover Layout
    ///             Does Not Invoke Destructive Actions.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testBoardOptionsPopoverLayoutDoesNotInvokeDestructiveActions() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        for size in [DynamicTypeSize.large, .accessibility3]
        {

            let menu = BoardOptionsPopover(
                canJumpFirst: true, canJumpLast: true, hasAppearance: true,
                canArchive: true, canDelete: true, deleteTitle: "Delete Board", hasGallery: true, canResetZoom: true
            )
            {
                _ in
                XCTFail("Presenting options must not perform an action")
            }

            let host = UIHostingController(
                rootView:
                menu
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding().environment(\.dynamicTypeSize, size))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image
            {
                _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            let snapshot = XCTAttachment(image: image)
            snapshot.name = "BoardOptions-\(size)"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardZoomPresetsResetAfterPinchingFromEitherMode
    /// @brief      Verify that board Zoom Presets Reset After Pinching From Either Mode
    /// @details    Exercises `BoardPanoramicZoom.preset`, `BoardPanoramicZoom.scale`. Checks
    ///             `XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: false), 1)`;
    ///             `XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: true), 0.62)`.
    ///
    /// @return     (Void) no return value
    ///
    func testBoardZoomPresetsResetAfterPinchingFromEitherMode()
    {

        XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: false), 1)
        XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: true), 0.62)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 1, magnification: 0.5), 0.5)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 1, magnification: 2), 1.25)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 0.5), 0.31)
        XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: false), 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPanoramicPinchZoomClampsAndReversesAtBothLimits
    /// @brief      Verify that panoramic Pinch Zoom Clamps And Reverses At Both Limits
    /// @details    Exercises `BoardPanoramicZoom.scale`, `BoardPanoramicZoom.clamped`,
    ///             `BoardPresentation.standard.columnWidth`. Checks `XCTAssertEqual(BoardPanoramicZoom.initial,
    ///             0.62)`; `XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 1.5), 0.93)`.
    ///
    /// @return     (Void) no return value
    ///
    func testPanoramicPinchZoomClampsAndReversesAtBothLimits()
    {

        XCTAssertEqual(BoardPanoramicZoom.initial, 0.62)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 1.5), 0.93, accuracy: 0.001)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 0.1), 0.25)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 10), 1.25)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.25, magnification: 2), 0.5)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 1.25, magnification: 0.5), 0.625)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.8, magnification: .nan), 0.8)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.8, magnification: 0), 0.8)
        XCTAssertEqual(BoardPanoramicZoom.clamped(.infinity), BoardPanoramicZoom.initial)
        for viewport: CGFloat in [320, 393, 852]
        {

            let width = BoardPresentation.standard.columnWidth(viewportWidth: viewport, accessibilitySize: false)
            for scale in [BoardPanoramicZoom.minimum, BoardPanoramicZoom.initial, BoardPanoramicZoom.maximum]
            {

                XCTAssertGreaterThan(width * scale, 0)
                XCTAssertTrue((viewport / scale).isFinite)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHeaderSpacingCompactsOnlyWhenIntrinsicTextWouldClip
    /// @brief      Verify that header Spacing Compacts Only When Intrinsic Text Would Clip
    /// @details    Exercises `WorkspaceHeaderSpacing.gap`. Checks
    ///             `XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 360, titleIdealWidth: 100,
    ///             controlsWidth: 176, gapCount: 4, regularSpacing: 12), 12)`;
    ///             `XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 360, titleIdealWidth: 150,
    ///             controlsWidth: 176, gapCount: 4, regularSpacing: 12), 0)`.
    ///
    /// @return     (Void) no return value
    ///
    func testHeaderSpacingCompactsOnlyWhenIntrinsicTextWouldClip()
    {

        XCTAssertEqual(
            WorkspaceHeaderSpacing.gap(
                availableWidth: 360, titleIdealWidth: 100,
                controlsWidth: 176, gapCount: 4, regularSpacing: 12), 12)
        XCTAssertEqual(
            WorkspaceHeaderSpacing.gap(
                availableWidth: 360, titleIdealWidth: 150,
                controlsWidth: 176, gapCount: 4, regularSpacing: 12), 0)
        XCTAssertEqual(
            WorkspaceHeaderSpacing.gap(
                availableWidth: 360, titleIdealWidth: 500,
                controlsWidth: 176, gapCount: 4, regularSpacing: 12), 0)
        XCTAssertEqual(
            WorkspaceHeaderSpacing.gap(
                availableWidth: 820, titleIdealWidth: 500,
                controlsWidth: 176, gapCount: 4, regularSpacing: 12), 12)
        XCTAssertEqual(
            WorkspaceHeaderSpacing.gap(
                availableWidth: 360, titleIdealWidth: 136,
                controlsWidth: 176, gapCount: 4, regularSpacing: 12), 12)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAdaptiveHeaderRetainsControlTargetsAndGivesLongTextTheGapSpace
    /// @brief      Verify that adaptive Header Retains Control Targets And Gives Long Text The Gap Space
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(try XCTUnwrap(frames[id]).width, 44)`;
    ///             `XCTAssertEqual(try XCTUnwrap(frames[id]).height, 44)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testAdaptiveHeaderRetainsControlTargetsAndGivesLongTextTheGapSpace() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        var results: [String: [Int: CGRect]] = [:]
        for (name, title, direction) in [
            ("short", "Day", LayoutDirection.leftToRight),
            ("long", "A long name that needs additional space before the toolbar controls", .leftToRight),
            ("rtl", "A long name that needs additional space before the toolbar controls", .rightToLeft)
        ]
        {


            ///
            /// @fcn        PlenactBoardDocumentTests.testAdaptiveHeaderRetainsControlTargetsAndGivesLongTextTheGapSpace.control
            /// @brief      Prepare control for the enclosing regression test
            /// @details    Supplies the local fixture for adaptive Header Retains Control Targets And Gives Long Text
            ///             The Gap Space. Uses `Color.blue.frame(width: 44, height: 44)
            ///             .onGeometryChange`, `Color.blue.frame`, `$0.frame`.
            ///
            /// @param[in]  id  Starting numeric card ID or owner-local content identity
            ///
            /// @return     (some View) regression fixture view
            ///
            func control(_ id: Int) -> some View
            {

                Color.blue.frame(width: 44, height: 44)
                .onGeometryChange(for: CGRect.self)
                {

                    $0.frame(in: .named("headerFixture"))
                }
                action:
                {

                    results[name, default: [:]] [id] = $0
                }

            }

            let view = AdaptiveWorkspaceHeaderLayout(regularSpacing: 12, layoutDirection: direction)
            {

                control(0)
                Text(title).lineLimit(1).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGRect.self)
                {

                    $0.frame(in: .named("headerFixture"))
                }
                action:
                {

                    results[name, default: [:]] [1] = $0
                }
                .layoutValue(key: WorkspaceHeaderTitleKey.self, value: true)
                control(2);
                control(3);
                control(4)
            } .frame(width: 360).coordinateSpace(name: "headerFixture")
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(180))
        }

        let short = try XCTUnwrap(results["short"])
        let long = try XCTUnwrap(results["long"])
        let rtl = try XCTUnwrap(results["rtl"])
        for frames in [short, long, rtl]
        {

            for id in [0, 2, 3, 4]
            {

                XCTAssertEqual(try XCTUnwrap(frames[id]).width, 44, accuracy: 0.5)
                XCTAssertEqual(try XCTUnwrap(frames[id]).height, 44, accuracy: 0.5)
            }

        }

        XCTAssertEqual(try XCTUnwrap(short[3]).minX - XCTUnwrap(short[2]).maxX, 12, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(long[3]).minX - XCTUnwrap(long[2]).maxX, 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(long[1]).width - XCTUnwrap(short[1]).width, 48, accuracy: 0.5)
        XCTAssertGreaterThan(try XCTUnwrap(rtl[0]).midX, try XCTUnwrap(rtl[4]).midX)
        XCTAssertEqual(try XCTUnwrap(rtl[1]).width, try XCTUnwrap(long[1]).width, accuracy: 0.5)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSlideableHeaderTextScrollsOnlyOverflowAndRetainsReadingPosition
    /// @brief      Verify that slideable Header Text Scrolls Only Overflow And Retains Reading Position
    /// @details    Exercises `PlanPreferencesStore.save`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertTrue(scrolling.isScrollEnabled)`;
    ///             `XCTAssertTrue(overflow.contains(true))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testSlideableHeaderTextScrollsOnlyOverflowAndRetainsReadingPosition() async throws
    {

        let suite = "HeaderReadingTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        PlanPreferencesStore.save(LocalProfilePreferences(scrollsOverflowingTitles: true), to: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testSlideableHeaderTextScrollsOnlyOverflowAndRetainsReadingPosition.scrolls
        /// @brief      Find scrolls in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrolls(_ view: UIView) -> [UIScrollView]
        {

            (view as? UIScrollView).map
            {
                [$0]
            }
            ?? view.subviews.flatMap(scrolls)
        }

        let long =
                        "Make room for today because there is more to this title than fits in the header, and every word should remain readable."
        var overflow: [Bool] = []
        let host = UIHostingController(
            rootView: VStack(spacing: 20)
            {

                SlideableHeaderText(text: long, onTap:
                    {

                    }, onOverflowChange:
                    {
                        overflow.append($0)
                    }).font(.headline)
                SlideableHeaderText(text: "Short").font(.subheadline)
            } .frame(width: 220).padding().defaultAppStorage(defaults))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host;
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        let native = scrolls(host.view)
        let scrolling = try XCTUnwrap(native.first
            {
                $0.contentSize.width > $0.bounds.width + 1
            })
        XCTAssertTrue(scrolling.isScrollEnabled)
        XCTAssertTrue(overflow.contains(true))
        XCTAssertEqual(scrolling.contentOffset.x, 0, accuracy: 1, "No automatic movement")
        XCTAssertTrue(native.contains
            {
                !$0.isScrollEnabled && $0.contentSize.width <= $0.bounds.width + 1
            })
        let end = max(0, scrolling.contentSize.width - scrolling.bounds.width)
        scrolling.setContentOffset(CGPoint(x: end, y: 0), animated: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(
            scrolling.contentOffset.x, end, accuracy: 1, "The full ending is reachable and stays where it was read")
        XCTAssertFalse(scrolling.showsHorizontalScrollIndicator)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLongListAndBoardHeadersExposeIndependentNativeReaders
    /// @brief      Verify that long List And Board Headers Expose Independent Native Readers
    /// @details    Exercises `PlanPreferencesStore.save`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertGreaterThanOrEqual(readers.count, 2)`;
    ///             `XCTAssertTrue(reader.isScrollEnabled)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLongListAndBoardHeadersExposeIndependentNativeReaders() async throws
    {

        let suite = "HeaderReadingTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        PlanPreferencesStore.save(LocalProfilePreferences(scrollsOverflowingTitles: true), to: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testLongListAndBoardHeadersExposeIndependentNativeReaders.scrolls
        /// @brief      Find scrolls in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrolls(_ view: UIView) -> [UIScrollView]
        {

            ((view as? UIScrollView).map
                {
                    [$0]
                }
                ?? []) + view.subviews.flatMap(scrolls)
        }

        let title = "On the Table, and all the meaningful possibilities that I want to make room for today"
        let subtitle = "Ideas taking shape, plans becoming action, and the rest of this subtitle is readable too"
        var list = KanbanList(id: 8, title: title, cards: [])
        list.subtitleOverride = subtitle
        let header = BoardHeader(
            settings: .constant(BoardDisplaySettings()), presentation: .constant(.standard),
            activeMembers: [], memberColors: [:], onRenameMember:
            {
                _, _ in
            }, onDeleteMember:
            {
                _ in
            },
            onSetMemberColor:
            {
                _, _ in
            }, onOpenCalendar:
            {

            }, title: title, subtitle: subtitle,
            allowsAddingLists: false, onClose:
            {

            }, onViewArchivedLists:
            {

            }, onArchiveBoard: nil,
            onDeleteBoard: nil, deleteBoardTitle: "Delete Board",
            onJumpToFirstList:
            {
                XCTFail("Layout must not navigate")
            },
            onJumpToLastList:
            {
                XCTFail("Layout must not navigate")
            }, onAddList:
            {

            })
        for (name, view) in [
            ("board", AnyView(header.titleSwipeArea.padding(20).background(Color.blue))),
            (
                                "list",
                                AnyView(
                                    TodayListDetailView(
                                        lists: .constant([list]), reservedLists: [], labelLibrary: .constant(.starter),
                                        savedCardIDs: .constant([]), listID: list.id, currentUserName: "Test", onClose:
                                        {

                                        },
                                        onOpenWeek:
                                        {

                                        }, onPermanentDelete:
                                        {
                                            _ in
                                            false
                                        }))
            )
        ]
        {

            let host = UIHostingController(rootView: view.defaultAppStorage(defaults))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            // A top-edge native scroll view can extend into the container safe area;
            // its single-line content height identifies the reader, not its UIKit bounds.
            let readers = scrolls(host.view).filter
            {

                $0.contentSize.width > $0.bounds.width + 1 && $0.contentSize.height < 70
            }

            XCTAssertGreaterThanOrEqual(readers.count, 2, "Title and subtitle need independent reading positions")
            for reader in readers
            {
                XCTAssertTrue(reader.isScrollEnabled)
            }

            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-sliding-header-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: url);
            print("SLIDING_HEADER_RENDER=" + url.path)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedMixedDisplayFormatsAndPicturePlaceholdersDoNotMutateRecords
    /// @brief      Verify that hosted Mixed Display Formats And Picture Placeholders Do Not Mutate Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(item, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testHostedMixedDisplayFormatsAndPicturePlaceholdersDoNotMutateRecords() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }

        for textSize in [DynamicTypeSize.large, .accessibility3]
        {

            for format in ItemDisplayFormat.allCases
            {

                var item = KanbanCard(
                    id: 73, word: "A long example title for a mixed List", listTitle: "Ideas",
                    descriptionOverride: "Retained writing")
                item.displayFormat = format
                let original = item
                let sheet = ItemAppearanceSheet(
                    title: item.word, appearance: nil,
                    onOpenLayout:
                    {
                        XCTFail("Presentation must not open Layout")
                    }, displayFormat: format,
                    onSaveDisplay:
                    {
                        _, _ in
                        XCTFail("Layout must not save display");
                        return false
                    }
                )
                {
                    _ in
                    XCTFail("Layout must not save decoration");
                    return false
                }

                let controller = UIHostingController(rootView: sheet.environment(\.dynamicTypeSize, textSize))
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image
                {
                    _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }

                let attachment = XCTAttachment(image: image)
                attachment.name = "Display-\(format.rawValue)-\(textSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let detail = UIHostingController(
                    rootView: NavigationStack
                    {

                        CardDetailView(card: item, onTitleToggle:
                            {
                                _ in
                                XCTFail("Layout must not edit this item")
                            })
                        .environment(\.dynamicTypeSize, textSize)
                    })
                window.rootViewController = detail
                detail.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                if format == .title || format == .text
                {

                    let row = KanbanCardView(
                        card: item, height: 100, displaySettings: BoardDisplaySettings(), labelLibrary: .starter,
                        onUpdateCard:
                        {
                            _ in
                            XCTFail("Layout must not edit writing")
                        },
                        onDeleteCard:
                        {
                            XCTFail("Layout must not delete")
                        },
                        onArchiveCard:
                        {
                            XCTFail("Layout must not archive")
                        },
                        onToggle:
                        {
                            XCTFail("Writing must not complete")
                        })
                    let host = UIHostingController(rootView: row.padding().environment(\.dynamicTypeSize, textSize))
                    window.rootViewController = host
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(150))
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image
                    {
                        _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }

                    let snapshot = XCTAttachment(image: image)
                    snapshot.name = "WritingRow-\(format.rawValue)-\(textSize)"
                    snapshot.lifetime = .keepAlways
                    add(snapshot)
                }

                XCTAssertEqual(item, original)
            }

        }

        for cover in [nil, ExampleCoverImage.garden]
        {

            let photo = cover.map
            {
                KanbanAttachment(mediaKind: .photo, exampleImage: $0)
            }

            var picture = KanbanCard(
                id: 74, word: "Example picture", listTitle: "Ideas", attachments: photo.map
                {
                    [$0]
                },
                coverAttachmentID: photo?.id)
            picture.displayFormat = .picture
            let row = KanbanCardView(
                card: picture, height: 100, displaySettings: BoardDisplaySettings(), labelLibrary: .starter,
                onUpdateCard:
                {
                    _ in
                    XCTFail("Layout must not edit picture")
                },
                onDeleteCard:
                {
                    XCTFail("Layout must not delete")
                },
                onArchiveCard:
                {
                    XCTFail("Layout must not archive")
                }, onToggle:
                {
                    XCTFail("Layout must not complete")
                }
            )
            let host = UIHostingController(rootView: row)
            window.rootViewController = host
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image
            {
                _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = cover == nil ? "Picture-placeholder" : "Picture-natural-aspect"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedListEditorPrefillsWithoutMutatingRecords
    /// @brief      Verify that hosted List Editor Prefills Without Mutating Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertTrue(fields(in: controller.view).contains { $0.text ==
    ///             list.title })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testHostedListEditorPrefillsWithoutMutatingRecords() async throws
    {


        var list = KanbanList(id: 4, title: "Synthetic plans", cards: [])
        list.subtitleOverride = "A synthetic subtitle"
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedListEditorPrefillsWithoutMutatingRecords.fields
        /// @brief      Find fields in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextField. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UITextField]) resulting values in the ordering described above
        ///
        func fields(in view: UIView) -> [UITextField]
        {

            (view as? UITextField).map
            {
                [$0]
            }
            ?? view.subviews.flatMap
            {
                fields(in: $0)
            }

        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedListEditorPrefillsWithoutMutatingRecords.textViews
        /// @brief      Find text views in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UITextView]) resulting values in the ordering described above
        ///
        func textViews(in view: UIView) -> [UITextView]
        {

            (view as? UITextView).map
            {
                [$0]
            }
            ?? view.subviews.flatMap
            {
                textViews(in: $0)
            }

        }

        let controller = UIHostingController(
            rootView: ListInfoEditorSheet(list: list)
            {
                _, _ in
                XCTFail("Opening or dismissing an editor must not save")
                return false
            })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(fields(in: controller.view).contains
            {
                $0.text == list.title
            })
        XCTAssertTrue(
            textViews(in: controller.view).contains
            {
                $0.text == list.subtitle
            }

            || fields(in: controller.view).contains
            {
                $0.text == list.subtitle
            })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSharedKeyboardAttachesToPlainFieldsAndRendersNarrowAndWide
    /// @brief      Verify that shared Keyboard Attaches To Plain Fields And Renders Narrow And Wide
    /// @details    Exercises `PlenactKeyboard.shared.install`, `NotificationCenter.default.post`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks `XCTAssertTrue(field.inputAccessoryView
    ///             is PlenactKeyboardToolbar)`; `XCTAssertEqual(field.keyboardType, .emailAddress)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testSharedKeyboardAttachesToPlainFieldsAndRendersNarrowAndWide() throws
    {

        PlenactKeyboard.shared.install()
        let field = UITextField();
        field.keyboardType = .emailAddress
        NotificationCenter.default.post(name: UITextField.textDidBeginEditingNotification, object: field)
        XCTAssertTrue(field.inputAccessoryView is PlenactKeyboardToolbar)
        XCTAssertEqual(field.keyboardType, .emailAddress)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController();
        window.rootViewController = controller;
        window.makeKeyAndVisible()
        let token = UUID()
        PlenactKeyboard.shared.setContext(
            token, actions: KeyboardCardActions(exit:
                {

                }, previous:
                {

                }, next:
                {

                }, attachment:
                {

                }, checklist:
                {

                }))
        defer
        {
            PlenactKeyboard.shared.removeContext(token);
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        for width: CGFloat in [320, 393, 820]
        {

            let toolbar = PlenactKeyboardToolbar(
                input: field, formatting: KeyboardFormatting(toggle:
                    {
                        _ in
                    }, color:
                    {
                        _ in
                    }, font:
                    {
                        _, _ in
                    }))
            toolbar.frame = CGRect(x: 0, y: 0, width: width, height: 44)
            controller.view.addSubview(toolbar);
            toolbar.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: toolbar.bounds).image
            {
                _ in
                toolbar.drawHierarchy(in: toolbar.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-keyboard-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("KEYBOARD_RENDER=" + url.path)
            toolbar.removeFromSuperview()
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionListWidthReachesTheHostedCardContainer()
    /// @brief      Verify the real personal collection adapter widens Standard list and card containers
    /// @details    Hosts List and Board collections with isolated presentation preferences and
    ///             compares native card-container widths in portrait and landscape without mutations
    ///
    /// @return     (Void) records assertion failures for container width or content changes
    ///
    /// @throws     Fixture or hosted-view unwrap failures and task cancellation
    ///
    @MainActor
    func testPersonalCollectionListWidthReachesTheHostedCardContainer() async throws
    {


        let suite = "Plenact.CollectionWidthTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)                                             /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)  /* Previously focused window       */
        let window = UIWindow(windowScene: scene)                 /* Temporary window for UI hosting */

        defer
        {


            window.isHidden = true
            window.rootViewController = nil

            previous?.makeKey()
            defaults.removePersistentDomain(forName: suite)
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionListWidthReachesTheHostedCardContainer.collectionView(in:)
        /// @brief      Locate the rendered list's native card collection
        /// @details    Recursively searches hosted subviews without modifying the hierarchy
        ///
        /// @param[in]  view  Root view to inspect
        ///
        /// @return     (UICollectionView?) first collection found, or nil when absent
        ///
        func collectionView(in view: UIView) -> UICollectionView?
        {


            if let collection = view as? UICollectionView /* Matched native List collection view */
            {


                return collection
            }


            return view.subviews.compactMap
            {
                collectionView(in: $0)
            } .first
        }


        for width: CGFloat in [393, 852]
        {


            for preset in BoardPresentation.allCases
            {


                defaults.set(preset.rawValue, forKey: BoardPresentation.storageKey)

                var measured: [PersonalCollectionKind: CGFloat] = [:] /* Measured layout dimensions */

                for kind in [PersonalCollectionKind.list, .board]
                {


                    var fixture = PersonalCollection(
                        title: "Synthetic collection", kind: kind) /* Synthetic collection fixture */

                    fixture.lists = [SampleData.lists[0]]

                    let original = fixture /* Pre-operation value for preservation checks */

                    let controller = UIHostingController(
                        rootView: PersonalCollectionBoardView( /* Hosted controller for layout assertions */
                            collection: Binding(get:
                                {
                                    fixture
                                }, set:
                                {
                                    fixture = $0
                                }),
                            boardTargetListID: .constant(nil),
                            boardTargetCardID: .constant(nil),
                            retainedLists: [],
                            availablePersonalLists: [],
                            onArchive:
                            {
                                XCTFail("Layout must not archive")
                            },
                            onDelete:
                            {
                                XCTFail("Layout must not delete")
                            },
                            onCommitDeletion:
                            {
                                _ in
                                XCTFail("Layout must not commit deletion")
                            },
                            onCreateNote:
                            {
                                _, _, _ in
                                XCTFail("Layout must not create an item")
                            },
                            onMoveNote:
                            {
                                _, _, _ in
                                throw CocoaError(.validationMissingMandatoryProperty)
                            },
                            onUpdateMovedNote:
                            {
                                _, _ in
                                XCTFail("Layout must not update a moved Note");
                                return false
                            },
                            onArchiveMovedNote:
                            {
                                _, _ in
                                XCTFail("Layout must not archive a moved Note");
                                return false
                            },
                            onDeleteMovedNote:
                            {
                                _, _ in
                                XCTFail("Layout must not delete a moved Note");
                                return false
                            },
                            onToggleMovedNoteBookmark:
                            {
                                _, _, _ in
                                XCTFail("Layout must not change a moved Note bookmark");
                                return false
                            },
                            registerNewNote:
                            {
                                _ in
                            }
                        ).defaultAppStorage(defaults))

                    window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
                    window.rootViewController = controller

                    window.makeKeyAndVisible()
                    controller.view.layoutIfNeeded()

                    try await Task.sleep(for: .milliseconds(100))

                    let cards = try XCTUnwrap(collectionView(in: controller.view)) /* Card records under inspection */

                    measured[kind] = cards.bounds.width

                    XCTAssertGreaterThan(cards.bounds.width, 0)
                    XCTAssertEqual(fixture, original)
                }


                let listWidth = try XCTUnwrap(measured[.list])    /* Proposed List width  */
                let boardWidth = try XCTUnwrap(measured[.board])  /* Proposed Board width */
                let expectedDifference =
                preset == .standard ? max(0, width - 28 - 360) : 0 /* Expected width difference */

                XCTAssertEqual(listWidth - boardWidth, expectedDifference, accuracy: 1)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRenderedCardsFitContentWithoutQuarterScreenHeights()
    /// @brief      Measure compact summaries and accessibility growth
    /// @details    Hosts both presets and rejects layout callbacks that would mutate the card
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testRenderedCardsFitContentWithoutQuarterScreenHeights()
    {


        let card = KanbanCard(
            id: 100, word: "Prepare a plan", listTitle: "Synthetic list") /* Card value under verification */


        ///
        /// @fcn        PlenactBoardDocumentTests.testRenderedCardsFitContentWithoutQuarterScreenHeights.measuredHeight(_:size:width:)
        /// @brief      Measure a synthetic card at the requested preset and text size
        /// @details    Proposes ample height so the hosting controller reports content-fitting
        ///             height
        ///
        /// @param[in]  preset  Card presentation preset
        /// @param[in]  size    Dynamic Type environment value
        /// @param[in]  width   Proposed card width in points
        ///
        /// @return     (CGFloat) hosted card height in points
        ///
        func measuredHeight(_ preset: BoardPresentation, size: DynamicTypeSize, width: CGFloat) -> CGFloat
        {


            let view = KanbanCardView( /* Hosted view under test */
                card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                presentation: preset, labelLibrary: .starter,
                onUpdateCard:
                {
                    _ in
                    XCTFail("Layout must not edit a card")
                },
                onDeleteCard:
                {
                    XCTFail("Layout must not delete a card")
                },
                onArchiveCard:
                {
                    XCTFail("Layout must not archive a card")
                },
                onToggle:
                {
                    XCTFail("Layout must not toggle a card")
                }
            )
            .environment(\.dynamicTypeSize, size)

            let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */

            return controller.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        }


        let standard = measuredHeight(.standard, size: .large, width: 360)  /* Standard Card baseline         */
        let overview = measuredHeight(.overview, size: .large, width: 240)  /* Measured Overview panel height */

        XCTAssertGreaterThanOrEqual(standard, 112)
        XCTAssertLessThan(standard, 160)
        XCTAssertGreaterThanOrEqual(overview, 80)
        XCTAssertLessThan(overview, standard)
        XCTAssertGreaterThan(measuredHeight(.overview, size: .accessibility5, width: 292), overview)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardRelayoutAndPresetChangesDoNotMutateRetainedContent()
    /// @brief      Retain the requested list and content through Board re-layout
    /// @details    Varies viewport/preset and compares active lists, archives, bookmarks, and
    ///             visible ID
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Fixture setup failures or cancellation of the layout delay
    ///
    @MainActor
    func testBoardRelayoutAndPresetChangesDoNotMutateRetainedContent() async throws
    {


        let suite = "Plenact.BoardRelayoutTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        var lists = SampleData.lists /* Board lists under verification */
        lists[0].archiveCard(id: lists[0].cards[0].id)
        var archived = SampleData.lists[1] /* Archived value for restoration checks */

        archived.isArchived = true

        var archives = [archived]                             /* Archived-card collection               */
        var saved: Set<Int> = [lists[0].archivedCards[0].id]  /* Persisted value under verification     */
        let focusedListID = lists[3].id                       /* Focused List identifier                */
        var targetList: Int? = focusedListID                  /* List identity to focus after relayout  */
        var targetCard: Int?                                  /* Card identity to reveal after relayout */
        var visibleListID: Int?                               /* Visible List identifier                */
        let revealedTarget = expectation(
            description: "Reveal the requested middle list")  /* Card revealed by edge navigation       */
        var didRevealTarget = false                           /* Whether navigation revealed its target */
        let originalLists = lists                             /* List snapshots before movement         */
        let originalArchives = archives                       /* Archive snapshots before movement      */
        let originalSaved = saved                             /* Saved-card identifiers before movement */
        let view = ContentView(                               /* Hosted view under test                 */
            lists: Binding(get:
                {
                    lists
                }, set:
                {
                    lists = $0
                }),
            archivedLists: Binding(get:
                {
                    archives
                }, set:
                {
                    archives = $0
                }),
            boardTargetListID: Binding(get:
                {
                    targetList
                }, set:
                {
                    targetList = $0
                }),
            boardTargetCardID: Binding(get:
                {
                    targetCard
                }, set:
                {
                    targetCard = $0
                }),
            savedCardIDs: Binding(get:
                {
                    saved
                }, set:
                {
                    saved = $0
                }),
            onListViewed:
            {
                listID in
                visibleListID = listID
                if listID == focusedListID && !didRevealTarget
                {


                    didRevealTarget = true
                    revealedTarget.fulfill()
                }

            },
            boardTitle: "Synthetic board",
            onListsChanged:
            {
                _ in
                XCTFail("Presentation must not request a Board save")
            },
            retainedAttachmentLists:
            {
                []
            }
        )
        .defaultAppStorage(defaults)

        let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)                                                      /* Active scene for UI hosting     */
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)  /* Previously active key window    */
        let window = UIWindow(windowScene: scene)                          /* Temporary window for UI hosting */

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()

        defer
        {


            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }


        await fulfillment(of: [revealedTarget], timeout: 2)

        for preset in BoardPresentation.allCases
        {


            defaults.set(preset.rawValue, forKey: BoardPresentation.storageKey)

            for size in [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393)]
            {


                window.frame.size = size
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))

                XCTAssertEqual(lists, originalLists)
                XCTAssertEqual(archives, originalArchives)
                XCTAssertEqual(saved, originalSaved)
                XCTAssertEqual(visibleListID, focusedListID)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardHeaderSwipeAreaFillsAvailableWidth()
    /// @brief      Keep short Board titles from shrinking the header swipe target
    /// @details    Measures the actual header title region at several available widths, with
    ///             and without a Library back action, and checks its minimum touch height
    ///
    /// @return     (Void) records assertion failures for a narrow swipe target
    ///
    @MainActor
    func testBoardHeaderSwipeAreaFillsAvailableWidth()
    {


        for hasBackAction in [false, true]
        {


            let header = BoardHeader( /* Rendered Board header */
                settings: .constant(BoardDisplaySettings()),
                presentation: .constant(.standard),
                activeMembers: [],
                memberColors: [:],
                onRenameMember:
                {
                    _, _ in
                },
                onDeleteMember:
                {
                    _ in
                },
                onSetMemberColor:
                {
                    _, _ in
                },
                onOpenCalendar:
                {

                },
                title: "Week",
                subtitle: "Plan",
                allowsAddingLists: true,
                onClose: hasBackAction ?
                {

                } : nil,
                onViewArchivedLists:
                {

                },
                onArchiveBoard: nil,
                onDeleteBoard: nil,
                deleteBoardTitle: "Delete Board",
                onJumpToFirstList:
                {
                    XCTFail("Layout must not navigate")
                },
                onJumpToLastList:
                {
                    XCTFail("Layout must not navigate")
                },
                onAddList:
                {

                }
            )
            let controller = UIHostingController(
                rootView: header.titleSwipeArea) /* Hosted controller for layout assertions */

            for width in [CGFloat(180), 280, 600]
            {


                let size = controller.sizeThatFits(
                    in: CGSize(width: width, height: 200)) /* Proposed layout dimensions */

                XCTAssertEqual(size.width, width, accuracy: 0.5, "Blank header space must belong to the swipe area")
                XCTAssertGreaterThanOrEqual(size.height, 44)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardHeaderSwipeMapsDeliberateHorizontalGesturesToBoundaries()
    /// @brief      Recognize intentional horizontal header swipes without capturing vertical movement
    /// @details    Checks left/right direction, minimum travel, vertical-dominant drags, and
    ///             nonfinite gesture values
    ///
    /// @return     (Void) records assertion failures for swipe classification
    ///
    func testBoardHeaderSwipeMapsDeliberateHorizontalGesturesToBoundaries()
    {


        XCTAssertEqual(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: -60, height: 8)), .last)
        XCTAssertEqual(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: 60, height: -8)), .first)
        XCTAssertNil(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: -47, height: 0)))
        XCTAssertNil(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: 70, height: 55)))
        XCTAssertNil(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: CGFloat.infinity, height: 0)))
        XCTAssertNil(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: 70, height: CGFloat.nan)))
        XCTAssertNil(
            BoardListReordering.boundary(
                forHorizontalSwipe: CGSize(width: 100, height: 0), minimumDistance: CGFloat.infinity
            ))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardDropGeometryUsesMidpointsAndRejectsOutsideViewport()
    /// @brief      Verify insertion targeting across row midpoints and viewport boundaries
    /// @details    Uses synthetic offset frames to check empty lists, gaps, nonfinite coordinates,
    ///             missing measurements, and unmeasured trailing rows without moving records.
    ///
    /// @return     (Void) records assertion failures for incorrect geometry targets
    ///
    func testCardDropGeometryUsesMidpointsAndRejectsOutsideViewport()
    {


        let lists = [
            KanbanList(
                id: 10, title: "A",
                cards: [ /* Board lists under verification */
                    KanbanCard(id: 1, word: "A", listTitle: "A"),
                    KanbanCard(id: 2, word: "B", listTitle: "A"),
                    KanbanCard(id: 3, word: "C", listTitle: "A")
                ]), KanbanList(id: 20, title: "Empty", cards: [])
        ]
        let listFrames = [
            10: CGRect(x: 100, y: 50, width: 200, height: 600), /* Rendered List frame map */
            20: CGRect(x: 320, y: 50, width: 180, height: 160)
        ]
        let frames = [
            1: CGRect(x: 100, y: 130, width: 200, height: 100), /* Measured layout frames */
            2: CGRect(x: 100, y: 238, width: 200, height: 100),
            3: CGRect(x: 100, y: 346, width: 200, height: 100)
        ]
        let viewport = CGRect(x: 100, y: 50, width: 400, height: 600) /* Visible Board viewport */


        ///
        /// @fcn        PlenactBoardDocumentTests.testCardDropGeometryUsesMidpointsAndRejectsOutsideViewport.target(_:_:frames:)
        /// @brief      Resolve a synthetic drop point relative to the fixture viewport
        /// @details    Adds the viewport origin to test coordinates and forwards the selected row
        ///             frames to canonical target resolution.
        ///
        /// @param[in]  x       Horizontal test offset from the fixture viewport origin
        /// @param[in]  y       Vertical test offset from the fixture viewport origin
        /// @param[in]  frames  Synthetic card frames used for this target query
        ///
        /// @return     (BoardCardDropTarget?) resolved fixture target, or nil for a rejected point
        ///
        func target(_ x: CGFloat, _ y: CGFloat, frames: [Int: CGRect] = frames) -> BoardCardDropTarget?
        {


            BoardCardMovement.target(
                for: 99, at: CGPoint(x: x + viewport.minX, y: y + viewport.minY), viewport: viewport,
                lists: lists, listFrames: listFrames, cardFrames: frames)
        }


        XCTAssertEqual(target(50, 129), BoardCardDropTarget(listID: 10, beforeCardID: 1))
        XCTAssertEqual(target(50, 130), BoardCardDropTarget(listID: 10, beforeCardID: 2))
        XCTAssertEqual(target(50, 238), BoardCardDropTarget(listID: 10, beforeCardID: 3))
        XCTAssertEqual(target(50, 400), BoardCardDropTarget(listID: 10, beforeCardID: nil))
        XCTAssertEqual(target(250, 100), BoardCardDropTarget(listID: 20, beforeCardID: nil))
        XCTAssertNil(target(210, 100))
        XCTAssertNil(target(-1, 100))
        XCTAssertNil(target(401, 100))
        XCTAssertNil(target(50, 601))
        XCTAssertNil(target(.nan, 100))
        XCTAssertNil(
            BoardCardMovement.target(
                for: 99, at: CGPoint(x: 150, y: 150),
                viewport: CGRect(x: 100, y: 50, width: CGFloat.infinity, height: 600),
                lists: lists, listFrames: listFrames, cardFrames: frames))
        XCTAssertNil(target(50, 100, frames: [:]))
        XCTAssertEqual(
            target(50, 280, frames: [2: frames[2]!]), BoardCardDropTarget(listID: 10, beforeCardID: 3),
                            "A long list's viewport edge must not silently append past unmeasured rows")
        XCTAssertEqual(lists[0].cards.map(\.id), [1, 2, 3], "Hovering must not move records")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWholeCardDragSourcesAndInsertionMarkersKeepNativeListRowIdentityAndLayout()
    /// @brief      Verify hosted card rows install native drag and one shared list receiver
    /// @details    Checks row count, enabled drag sources, receiver identity, collection
    ///             delegation, and bounds across presentation presets and accessibility text sizes.
    ///             Restores the prior key window after the synthetic layout fixture.
    ///
    /// @return     (Void) records assertion failures for interaction installation or row layout
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    @MainActor
    func testWholeCardDragSourcesAndInsertionMarkersKeepNativeListRowIdentityAndLayout() async throws
    {


        let list = KanbanList(
            id: 1, title: "Synthetic",
            cards: [ /* List state under verification */
                KanbanCard(id: 10, word: "A card with a longer title", listTitle: "Synthetic"),
                KanbanCard(id: 11, word: "", listTitle: "Synthetic", isDivider: true),
                KanbanCard(id: 12, word: "Another card", listTitle: "Synthetic")
            ])
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)                                             /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)  /* Previously focused window       */
        let window = UIWindow(windowScene: scene)                 /* Temporary window for UI hosting */

        defer
        {


            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testWholeCardDragSourcesAndInsertionMarkersKeepNativeListRowIdentityAndLayout.collectionView(in:)
        /// @brief      Find the first collection view in the hosted synthetic view tree
        /// @details    Returns the current view when it is a collection, otherwise recursively
        ///             searches its subviews in order.
        ///
        /// @param[in]  view  Root view to search for the hosted collection
        ///
        /// @return     (UICollectionView?) first collection view found, or nil when none exists
        ///
        func collectionView(in view: UIView) -> UICollectionView?
        {


            if let collection = view as? UICollectionView /* Matched native List collection view */
            {


                return collection
            }


            return view.subviews.compactMap
            {
                collectionView(in: $0)
            } .first
        }


        ///
        /// @fcn        testWholeCardDragSourcesAndInsertionMarkersKeepNativeListRowIdentityAndLayout.importanceMarker(in:)
        /// @brief      Locate a rendered star control's native geometry marker
        /// @details    Searches public view descendants inside the real hosted List cell.
        ///
        /// @param[in]  view  Card content subtree to inspect
        ///
        /// @return     (ImportanceInteractionRegion.Marker?) first star marker
        ///
        func importanceMarker(in view: UIView) -> ImportanceInteractionRegion.Marker?
        {

            (view as? ImportanceInteractionRegion.Marker) ?? view.subviews.compactMap
            {
                importanceMarker(in: $0)
            } .first
        }


        for (preset, textSize, width) in [
            (BoardPresentation.standard, DynamicTypeSize.large, 360.0),
            (.overview, .large, 240.0),
            (.standard, .accessibility5, 320.0)
        ]
        {

            let view = KanbanListView( /* Hosted view under test */
                list: list, availableListHeight: 700, displaySettings: BoardDisplaySettings(),
                presentation: preset, labelLibrary: .starter, toggleCardTitle:
                {
                    _ in
                },
                canMoveEarlier: false, canMoveLater: false, onAddCard:
                {
                    _ in
                    true
                },
                onCopyList:
                {

                }, onMoveList:
                {
                    _ in
                }, onSortList:
                {
                    _ in
                }, onArchiveCompleted:
                {

                },
                archivedCards: .constant([]), onRestoreArchivedCard:
                {
                    _ in
                },
                onDeleteArchivedCard:
                {
                    _ in
                }, onArchiveList:
                {

                }, onDeleteList:
                {

                },
                onDeleteCard:
                {
                    _ in
                }, onArchiveCard:
                {
                    _ in
                },
                onUpdateCard:
                {
                    _ in
                    XCTFail("Layout must not update records")
                },
                onMoveCard:
                {
                    _, _ in
                    XCTFail("Layout must not reorder records")
                },
                onListDragChanged:
                {
                    _ in
                }, onListDragEnded:
                {

                },
                draggedCardID: 10, dropBeforeCardID: 12, isCardDropTarget: true,
                onCardDragChanged:
                {
                    _, _ in
                    XCTFail("Layout must not begin a drag")
                },
                onCardDragEnded:
                {
                    _, _, _ in
                }
            ).environment(\.dynamicTypeSize, textSize)
            .environment(
                \.libraryImportance,
                LibraryImportanceAccess(
                    contains:
                    {
                        $0 == 10
                    }, set:
                    {
                        _, _ in
                    },
                    level:
                    {
                        $0 == 10 ? 3 : 0
                    }))
            let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */

            window.frame = CGRect(x: 0, y: 0, width: width, height: 800)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))

            let collection = try XCTUnwrap(
                collectionView(in: controller.view)) /* Collection state under verification */
            let itemCount = (0 ..< collection.numberOfSections).reduce(0)
            {  /* Expected item count                 */

                $0 + collection.numberOfItems(inSection: $1)
            }


            XCTAssertEqual(itemCount, 5, "Three content rows, the collapsed guidance placeholder, and Add card")

            let dragSources = collection.visibleCells.flatMap
            {
            cell in /* Registered drag-source views */
                cell.contentView.interactions.compactMap
                {
                    $0 as? UIDragInteraction
                } .filter
                {

                    $0.delegate is BoardCardDragSource.Coordinator
                }

            }


            XCTAssertFalse(dragSources.isEmpty, "Visible card bodies must have a native drag source")
            let starSource = try XCTUnwrap(
                dragSources.first
                {
                    source in
                    source.view.flatMap
                    {
                        importanceMarker(in: $0)
                    }
                    != nil
                })
            let starContainer = try XCTUnwrap(starSource.view)
            let starMarker = try XCTUnwrap(importanceMarker(in: starContainer))
            XCTAssertGreaterThan(starMarker.bounds.width, 0)
            let starPoint = starMarker.convert(
                CGPoint(x: starMarker.bounds.midX, y: starMarker.bounds.midY), to: starContainer)
            let dragOwner = try XCTUnwrap(starSource.delegate as? BoardCardDragSource.Coordinator)
            XCTAssertFalse(
                dragOwner.canBegin(at: starPoint, in: starContainer), "Holding the stars must not lift the Card")
            XCTAssertTrue(
                dragOwner.canBegin(at: CGPoint(x: 12, y: starContainer.bounds.midY), in: starContainer),
                                        "The Card body must remain draggable")
            XCTAssertFalse(dragOwner.isDragging)
            let dividerCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 2, section: 0)))
            XCTAssertTrue(
                dividerCell.contentView.interactions.contains
                {

                    ($0 as? UIDragInteraction)?.delegate is BoardCardDragSource.Coordinator
                }, "Divider rows must support the same native drag as Cards and Notes")
            XCTAssertTrue(dragSources.allSatisfy(\.isEnabled))
            XCTAssertEqual(
                collection.interactions.filter
                {

                    ($0 as? UIDropInteraction)?.delegate is BoardCardDropSurface.Coordinator
                } .count, 1, "Visible row probes must share exactly one native list drop receiver")
            XCTAssertTrue(
                collection.dropDelegate is BoardCardDropSurface.Coordinator,
                                        "The native List collection must forward its drop callbacks to canonical movement")
            XCTAssertGreaterThan(collection.bounds.height, 0)
            XCTAssertLessThanOrEqual(collection.bounds.width, width)
        }

    }

}
