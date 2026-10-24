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
