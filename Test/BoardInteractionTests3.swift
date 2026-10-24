// --------------------------------------------------------------------------------------------------
// @file       BoardInteractionTests3.swift
// @brief      Board Interaction regression tests3
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
    /// @fcn        PlenactBoardDocumentTests.testSubtitleItalicsInheritAndPreserveExplicitRegularOverrides()
    /// @brief      Resolve Board, List, and Card subtitle styles without losing explicit false
    /// @details    Covers legacy defaults, the complete override chain, optional-field encoding,
    ///             and clearing List overrides when applying Board defaults.
    /// @return     (Void) records inheritance, compatibility, or persistence failures
    /// @throws     Propagates JSON fixture decoding and encoding failures to XCTest
    ///
    func testSubtitleItalicsInheritAndPreserveExplicitRegularOverrides() throws
    {

        var board = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        var list = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        var card = ItemAppearance()
        XCTAssertNil(board.subtitleItalic)
        XCTAssertNil(list.subtitleItalic)
        XCTAssertFalse(board.resolvedSubtitleItalic(card: card, list: list))
        board.subtitleItalic = true
        XCTAssertTrue(board.resolvedSubtitleItalic(card: card, list: list))
        list.subtitleItalic = false
        XCTAssertFalse(board.resolvedSubtitleItalic(card: card, list: list))
        XCTAssertFalse(list.isEmpty, "Explicit regular type must survive appearance normalization")
        card.subtitleItalic = true
        XCTAssertTrue(board.resolvedSubtitleItalic(card: card, list: list))
        list.subtitleItalic = true
        card.subtitleItalic = false
        XCTAssertFalse(board.resolvedSubtitleItalic(card: card, list: list))
        let savedCard = try JSONDecoder().decode(ItemAppearance.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(savedCard.subtitleItalic, false)
        let savedBoard = try JSONDecoder().decode(BoardAppearance.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(savedBoard.subtitleItalic, true)
        card.subtitleItalic = nil
        XCTAssertTrue(board.resolvedSubtitleItalic(card: card, list: list))
        var owner = KanbanList(id: 12, title: "Work", cards: [])
        owner.appearance = list
        XCTAssertNil(BoardAppearance.inheritingLists([owner]).first?.appearance?.subtitleItalic)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSubtitleOverridesSurviveCardAndListPersistence()
    /// @brief      Retain italic and regular choices through canonical Card and List saves
    /// @details    Exercises explicit regular Card overrides, italic List defaults, relocation,
    ///             and archive restoration without changing subtitle content.
    /// @return     (Void) records content or appearance retention failures
    /// @throws     Propagates JSON fixture encoding and decoding failures to XCTest
    ///
    func testSubtitleOverridesSurviveCardAndListPersistence() throws
    {

        var card = KanbanCard(id: 1, word: "Task", listTitle: "Work", subtitleOverride: "A softer subtitle")
        var appearance = ItemAppearance()
        appearance.subtitleItalic = false
        card.appearance = appearance
        appearance.subtitleItalic = true
        var list = KanbanList(id: 1, title: "Work", cards: [card])
        list.appearance = appearance
        let saved = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(saved.cards.first?.appearance?.subtitleItalic, false)
        XCTAssertEqual(saved.appearance?.subtitleItalic, true)
        XCTAssertEqual(saved.cards.first?.subtitleOverride, "A softer subtitle")
        XCTAssertEqual(card.replacingLocation(id: 9, listTitle: "Other").appearance?.subtitleItalic, false)
        list.archiveCard(id: 1)
        list.restoreArchivedCard(id: 1)
        XCTAssertEqual(list.cards.first?.appearance?.subtitleItalic, false)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardHistoryCoalescesTypingWithoutCombiningSeparateActions()
    /// @brief      Keep autosaved writing readable while preserving initial and final values
    /// @details    Uses deterministic timestamps to distinguish a typing burst, a later title
    ///             edit, and a separate completion action.
    /// @return     (Void) records grouping or retained-value failures
    /// @throws     Propagates fixture unwrap and JSON decoding failures to XCTest
    ///
    func testCardHistoryCoalescesTypingWithoutCombiningSeparateActions() throws
    {

        let original = KanbanCard(id: 1, word: "A", listTitle: "Work", checklists: [])
        var next = original
        next.word = "AB"
        let first = next.recordingEdits(from: original, at: Date(timeIntervalSince1970: 100))
        next.word = "ABC"
        let burst = next.recordingEdits(from: first, at: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(burst.editHistory?.count, 1)
        XCTAssertEqual(burst.editHistory?.first?.id, first.editHistory?.first?.id)
        let change = try XCTUnwrap(burst.editHistory?.first?.changes.first)
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(change.previousValue)), "A")
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(change.newValue)), "ABC")
        next.word = "Later"
        let later = next.recordingEdits(from: burst, at: Date(timeIntervalSince1970: 110))
        XCTAssertEqual(later.editHistory?.count, 2)
        next.isTitleChecked = true
        let completed = next.recordingEdits(from: later, at: Date(timeIntervalSince1970: 111))
        XCTAssertEqual(completed.editHistory?.count, 3)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardHistoryRecordsGroupedEditsAndRetainsReversibleValues()
    /// @brief      Persist a grouped save and accumulate subsequent preview and completion edits
    /// @details    Exercises the List owner boundary, no-op saves, stale reconstructed snapshots,
    ///             precise before/after values, and JSON round trips with synthetic content.
    /// @return     (Void) records history grouping, retention, or persistence failures
    /// @throws     Propagates fixture encoding and unwrapping failures to XCTest
    ///
    func testCardHistoryRecordsGroupedEditsAndRetainsReversibleValues() throws
    {

        let original = KanbanCard(id: 12, word: "Before", listTitle: "Work", checklists: [])
        var list = KanbanList(id: 7, title: "Work", cards: [original])
        XCTAssertNil(list.cards[0].editHistory, "Insertion must not invent earlier history")
        var edited = original
        edited.word = "After"
        edited.dueDate = Date(timeIntervalSince1970: 123456)
        edited.dueDateKind = .dateAndTime
        list.cards[0] = edited
        let first = try XCTUnwrap(list.cards[0].editHistory?.first)
        XCTAssertEqual(list.cards[0].editHistory?.count, 1)
        XCTAssertEqual(Set(first.changes.map(\.field)), ["word", "dueDate", "dueDateKind"])
        let title = try XCTUnwrap(first.changes.first { $0.field == "word" })
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(title.previousValue)), "Before")
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(title.newValue)), "After")
        XCTAssertNil(first.changes.first { $0.field == "dueDate" }?.previousValue)
        XCTAssertFalse(first.changes.contains { $0.field == "editHistory" })

        list.cards[0] = edited
        XCTAssertEqual(list.cards[0].editHistory, [first], "No-op and reconstructed saves retain history")
        list.cards[0].isTitleChecked = true
        XCTAssertEqual(list.cards[0].editHistory?.count, 2)
        XCTAssertEqual(list.cards[0].editHistory?.last?.changes.map(\.field), ["isTitleChecked"])
        let roundTrip = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(roundTrip, list)
        XCTAssertEqual(roundTrip.cards[0].editHistory?.count, 2, "Loading must not append edits")
        XCTAssertEqual(list.cards[0].replacingLocation(id: 99, listTitle: "Elsewhere").editHistory,
                       list.cards[0].editHistory)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardHistoryPreservesPreparedEventsAndLegacyLocks()
    /// @brief      Avoid duplicate detail-save entries and maintain locked Card update protection
    /// @details    Reconciles a pre-recorded detail edit with the canonical owner, excludes reorder
    ///             and list-context changes, and decodes legacy Cards without a history key.
    /// @return     (Void) records duplicate, compatibility, or protection failures
    /// @throws     Propagates synthetic fixture encoding and unwrap failures to XCTest
    ///
    func testCardHistoryPreservesPreparedEventsAndLegacyLocks() throws
    {

        let original = KanbanCard(id: 3, word: "Legacy", listTitle: "Work", checklists: [])
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["editHistory"])
        XCTAssertNil(try JSONDecoder().decode(KanbanCard.self, from: data).editHistory)
        var edited = original
        edited.word = "Renamed"
        let prepared = edited.recordingEdits(from: original, at: Date(timeIntervalSince1970: 100))
        var list = KanbanList(id: 8, title: "Work", cards: [original])
        list.cards[0] = prepared
        XCTAssertEqual(list.cards[0].editHistory, prepared.editHistory)
        list.cards.reverse()
        XCTAssertEqual(list.cards[0].editHistory?.count, 1)
        let relocated = prepared.replacingLocation(id: 3, listTitle: "Other")
        list.cards[0] = relocated
        XCTAssertEqual(list.cards[0].editHistory, prepared.editHistory)

        list.cards[0].isEditingLocked = true
        let locked = list.cards[0]
        var unlock = locked
        unlock.editHistory = nil
        unlock.isEditingLocked = false
        XCTAssertTrue(locked.acceptsContentUpdate(unlock), "History metadata must not block an unchanged unlock")
        unlock.word = "Unexpected stale edit"
        XCTAssertFalse(locked.acceptsContentUpdate(unlock))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testActivityBrowserScrollsWithinVisibleBounds()
    /// @brief      Keep long Saved results inside the Activity browser viewport
    /// @details    Hosts eighty synthetic bookmarks with isolated preferences, scrolls to the last
    ///             row, and verifies the viewport and independent header retain their positions.
    ///
    /// @return     (Void) records failures for unbounded content or coupled scrolling
    /// @throws     Propagates missing window, preferences, or browser fixture failures to XCTest
    ///
    @MainActor
    func testActivityBrowserScrollsWithinVisibleBounds() async throws
    {

        let suite = "Plenact.ActivityLayoutTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(Data("[]".utf8), forKey: ActivityRecentStore.key)
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let cards = (0 ..< 80).map
        {
            KanbanCard(id: $0, word: "Saved fixture \($0)", listTitle: "Fixture", checklists: [])
        }
        let list = KanbanList(id: 987, title: "Fixture", cards: cards)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
        {
            $0 as? UIWindowScene
        }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: SavedCardsView(
            planningDocument: nil,
            lists: [list],
            savedCardIDs: Set(cards.map(\.id)),
            collections: .constant([]),
            onOpenBoardCard: { _, _ in },
            onOpenPersonalCard: { _ in },
            onRestoreBoard: { _ in },
            onDeleteBoard: { _ in false },
            onArchiveCard: { _ in },
            onDeleteCard: { _ in false }
        ).defaultAppStorage(defaults))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()


        ///
        /// @fcn        scrollViews(in:)
        /// @brief      Collect UIKit scrolling viewports beneath the hosted Activity view
        /// @details    Descends all child views without depending on private SwiftUI class names.
        ///
        /// @param      view (UIView) subtree to inspect
        /// @return     ([UIScrollView]) scrolling views in traversal order
        ///
        func scrollViews(in view: UIView) -> [UIScrollView]
        {

            let own = (view as? UIScrollView).map { [$0] } ?? []
            return own + view.subviews.flatMap { scrollViews(in: $0) }
        }

        let scrolls = scrollViews(in: host.view)
        let browser = try XCTUnwrap(scrolls.max
        {
            $0.contentSize.height - $0.bounds.height < $1.contentSize.height - $1.bounds.height
        })
        let frame = browser.convert(browser.bounds, to: host.view)
        XCTAssertGreaterThan(browser.bounds.height, 100)
        XCTAssertGreaterThan(browser.contentSize.height, browser.bounds.height + 500)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.maxY, host.view.bounds.maxY + 1)
        let otherOffsets = scrolls.filter { $0 !== browser }.map(\.contentOffset)
        browser.setContentOffset(CGPoint(x: 0, y: browser.contentSize.height - browser.bounds.height), animated: false)
        host.view.layoutIfNeeded()
        XCTAssertEqual(browser.convert(browser.bounds, to: host.view), frame)
        XCTAssertEqual(scrolls.filter { $0 !== browser }.map(\.contentOffset), otherOffsets)
        XCTAssertGreaterThan(browser.contentOffset.y, 500)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNativeCardDragSourceUsesLocalTokenAndEndsCancellationOnce()
    /// @brief      Verify built-app type registration, local token payload, and one-time cleanup
    /// @details    Reads the bundled exported type declaration, loads the synthetic token
    ///             representation, and checks active-state transitions plus UIKit recognition of
    ///             the session-end selector.
    ///
    /// @return     (Void) records assertion failures for registration, payload, or lifecycle
    ///             regressions
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    @MainActor
    func testNativeCardDragSourceUsesLocalTokenAndEndsCancellationOnce() async throws
    {


        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]]) /* Declarations under inspection       */
        let declaration = try XCTUnwrap(
            declarations.first
            {  /* Declaration record under inspection */

                ($0 ["UTTypeIdentifier"] as? String) == BoardCardDragSource.contentType.identifier
            })

        XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], ["public.data"])

        var points: [CGPoint] = []  /* Sample layout coordinates */
        var ended = 0               /* Completed drag state      */
        let source = BoardCardDragSource(
            token: "synthetic-session", /* Source state before the operation */
            onBegan:
            {
                points.append($0)
            },
            onChanged:
            {
                points.append($0)
            },
            onEnded:
            {
                ended += 1
            })
        let coordinator = source.makeCoordinator()   /* Drop coordinator under test */
        let point = CGPoint(x: 150, y: 320)          /* Synthetic drop coordinate   */
        let provider = coordinator.begin(at: point)  /* Native drag-item provider   */

        XCTAssertEqual(points, [point])
        XCTAssertTrue(coordinator.isDragging)
        XCTAssertEqual(provider.suggestedName, "synthetic-session")
        XCTAssertEqual(provider.registeredTypeIdentifiers, [BoardCardDragSource.contentType.identifier])

        let data: Data = try await withCheckedThrowingContinuation
        {
        continuation in /* Serialized fixture bytes */
            provider.loadDataRepresentation(forTypeIdentifier: BoardCardDragSource.contentType.identifier)
            {

            data, error in
                if let error /* Captured operation error */
                {


                    continuation.resume(throwing: error)
                }
                else if let data /* Response bytes supplied by the data-provider callback */
                {


                    continuation.resume(returning: data)
                }
                else
                {


                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }

            }

        }


        XCTAssertEqual(
            String(data: data, encoding: .utf8), "synthetic-session",
                            "Native drag payload must not contain card content or file references")

        coordinator.finish()
        coordinator.finish()

        XCTAssertFalse(coordinator.isDragging)
        XCTAssertEqual(ended, 1, "Drop/cancellation cleanup must not run twice")
        XCTAssertTrue(
            coordinator.responds(to: NSSelectorFromString("dragInteraction:session:didEndWithOperation:")),
                            "UIKit must recognize the real optional session-end callback")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNativeCardDragSourceSurvivesSourceRemovalUntilSessionEnd()
    /// @brief      Verify source virtualization does not end a live native session
    /// @details    Dismantles a synthetic active source probe, checks that cancellation is
    ///             deferred, and confirms explicit finish ends the session exactly once.
    ///
    /// @return     (Void) records assertion failures for premature or repeated session completion
    ///
    @MainActor
    func testNativeCardDragSourceSurvivesSourceRemovalUntilSessionEnd()
    {


        var ended = 0 /* Completed drag state              */
        let source = BoardCardDragSource(
            token: "synthetic-session", onBegan:
            {
                _ in
            }, onChanged:
            {
                _ in
            }, /* Source state before the operation */
            onEnded:
            {
                ended += 1
            })
        let coordinator = source.makeCoordinator()                  /* Drop coordinator under test */
        let container = UIView()                                    /* Target drop container       */
        let interaction = UIDragInteraction(delegate: coordinator)  /* Captured drag interaction   */

        container.addInteraction(interaction)
        coordinator.container = container
        coordinator.interaction = interaction
        _ = coordinator.begin(at: CGPoint(x: 1, y: 2))
        BoardCardDragSource.dismantleUIView(BoardCardDragSource.Probe(), coordinator: coordinator)

        XCTAssertEqual(ended, 0, "Virtualizing the source row must not end a live drag")
        XCTAssertTrue(coordinator.isDragging)
        XCTAssertTrue(container.interactions.contains
            {
                $0 === interaction
            })

        coordinator.finish()

        XCTAssertEqual(ended, 1)
        XCTAssertFalse(container.interactions.contains
            {
                $0 === interaction
            })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListDragEdgeThresholdsAndInvalidGeometry()
    /// @brief      Verify drag-edge activation at exact thresholds
    /// @details    Shared thresholds govern both list reordering and card-drag horizontal scrolling
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testListDragEdgeThresholdsAndInvalidGeometry()
    {


        XCTAssertEqual(BoardListReordering.edgeDirection(at: 63, viewportWidth: 400), -1)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 64, viewportWidth: 400), 0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 336, viewportWidth: 400), 0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 337, viewportWidth: 400), 1)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 200, viewportWidth: 400), 0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: .nan, viewportWidth: 400), 0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 20, viewportWidth: 0), 0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 20, viewportWidth: .infinity), 0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 17, viewportWidth: 100), -1)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 83, viewportWidth: 100), 1)
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testToolbarBackgroundRetainsHomeIndicatorCoverageWithoutInheritedInsets
    /// @brief      Verify that a transient missing safe-area environment does not uncover the footer
    /// @details    Renders the actual toolbar surface over a conspicuous green workspace, with an explicit
    ///             home-indicator allowance and no inherited container inset. Checks pixels in the controls'
    ///             background and the lower reserved strip independently of the toolbar buttons.
    ///
    /// @return     (Void) records rendered background coverage assertions
    /// @throws     Image rendering or bitmap fixture errors propagate to XCTest
    ///
    @MainActor
    func testToolbarBackgroundRetainsHomeIndicatorCoverageWithoutInheritedInsets() throws
    {

        for layout in [BottomToolbarLayout.phoneRegular, .phoneCompact, .padRegular, .padCompact]
        {
            for reportedInset: CGFloat in [0, 21, 34]
            {

                let height = layout.height
                let inset = max(reportedInset, layout.safeAreaAllowance)
                let content = ZStack(alignment: .top)
                {

                    Color(red: 0, green: 1, blue: 0)
                    Color.clear
                    .frame(height: height)
                    .background
                    {

                        BottomToolbarBackground(topInset: layout.backgroundTopInset, bottomInset: inset)
                    }
                }
                .frame(width: 200, height: height + inset)

                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage?.cgImage)
                let data = try XCTUnwrap(image.dataProvider?.data)
                let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
                XCTAssertEqual(image.bitsPerPixel, 32)
                for y in [Int((layout.backgroundTopInset + height) / 2), Int(height + inset) - 2]
                {

                    let offset = y * image.bytesPerRow + 100 * 4
                    let uncovered = bytes[offset] < 25 && bytes[offset + 1] > 230 && bytes[offset + 2] < 25
                    XCTAssertFalse(uncovered, "Toolbar background is missing at y=\(y), bottom inset=\(inset)")
                }
                if layout.backgroundTopInset > 0
                {

                    let offset = Int(layout.backgroundTopInset / 2) * image.bytesPerRow + 100 * 4
                    let clearTopGap = bytes[offset] < 25 && bytes[offset + 1] > 230 && bytes[offset + 2] < 25
                    XCTAssertTrue(clearTopGap, "The preset overlap gap must remain transparent")
                }
            }
        }
    }

}
