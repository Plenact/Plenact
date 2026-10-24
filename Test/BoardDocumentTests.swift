// --------------------------------------------------------------------------------------------------
// @file       BoardDocumentTests.swift
// @brief      Board Document regression tests
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
/// Verifies workspace persistence and interaction contracts
///
/// @section    Purpose
///     Protects owner-qualified models, migrations, checked mutations, calendar and review
///     workflows, gestures, navigation, and hosted presentation behavior with synthetic fixtures.
///
final class PlenactBoardDocumentTests: XCTestCase
{


    ///
    /// @fcn        PlenactBoardDocumentTests.routineCalendar
    /// @brief      Prepare routine calendar for the enclosing regression test
    /// @details    Supplies the local fixture for plenactBoardDocumentTests.
    ///
    /// @param[in]  firstWeekday  Calendar weekday index used to define the fixture week start
    ///
    /// @return     (Calendar) result described by this operation's contract
    ///
    func routineCalendar(firstWeekday: Int = 2) -> Calendar
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.findDetailNavigation
    /// @brief      Find a navigation controller containing a pushed detail view
    /// @details    Searches the supplied controller, its presented controller, and child controllers recursively;
    ///             returns nil when no detail navigation stack exists.
    ///
    /// @param[in]  controller  Native controller supplied to the lifecycle callback
    ///
    /// @return     (UINavigationController?) matching or resolved value, or nil when unavailable
    ///
    @MainActor
    func findDetailNavigation(in controller: UIViewController) -> UINavigationController?
    {

        if let nav = controller as? UINavigationController, nav.viewControllers.count > 1
        {
            return nav
        }

        if let presented = controller.presentedViewController, let found = findDetailNavigation(in: presented)
        {

            return found
        }

        for child in controller.children
        {

            if let found = findDetailNavigation(in: child)
            {
                return found
            }

        }

        return nil
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.planningTestCalendar
    /// @brief      Create the fixed calendar used by planning regression tests
    /// @details    Uses a Gregorian calendar in America/Chicago with Sunday as the first weekday so date and
    ///             daylight-saving assertions are reproducible.
    ///
    /// @return     (Calendar) result described by this operation's contract
    ///
    func planningTestCalendar() -> Calendar
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        return calendar
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.drawingFixture
    /// @brief      Create a small deterministic PencilKit drawing fixture
    /// @details    Builds three blue pen control points on one stroke for drawing persistence, preview, and export
    ///             tests.
    ///
    /// @return     (PKDrawing) result described by this operation's contract
    ///
    @MainActor
    func drawingFixture() -> PKDrawing
    {

        let points = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 180), CGPoint(x: 200, y: 350)].enumerated().map
        {

        index, point in
            PKStrokePoint(
                location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 8, height: 8), opacity: 1,
                force: 1, azimuth: 0, altitude: .pi / 2)
        }

        return PKDrawing(strokes: [
                PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))
            ])
    }


    ///
    /// Intercepts synthetic activity-test requests without accessing a remote endpoint
    ///
    /// @section    Purpose
    ///     Supply deterministic success/failure callbacks while inspecting MainActor activity state
    ///
    final class ActivityTestURLProtocol: URLProtocol
    {


        ///
        /// @fcn        PlenactBoardDocumentTests.ActivityTestURLProtocol.canInit(with:)
        /// @brief      Accept every request in the dedicated ephemeral test session
        /// @details    The test installs this protocol only on its synthetic session configuration
        ///
        /// @param[in]  request  Request offered by URL loading
        ///
        /// @return     (Bool) true
        ///
        override class func canInit(with request: URLRequest) -> Bool
        {


            true
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.ActivityTestURLProtocol.canonicalRequest(for:)
        /// @brief      Preserve the synthetic request as supplied
        /// @details    No URL or header normalization is needed for host-selected test outcomes
        ///
        /// @param[in]  request  Intercepted request
        ///
        /// @return     (URLRequest) unchanged request
        ///
        override class func canonicalRequest(for request: URLRequest) -> URLRequest
        {


            request
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.ActivityTestURLProtocol.startLoading()
        /// @brief      Deliver the response selected by the synthetic hostname
        /// @details    Checks activity before/after yielding; returns empty users or a transport
        ///             error
        ///
        /// @return     (Void) deliver the response selected by the synthetic hostname
        ///
        /// @post       Starts an asynchronous MainActor task that notifies the URLProtocol client
        ///
        override func startLoading()
        {


            Task
            {
                @MainActor in

                XCTAssertTrue(DatabaseActivity.shared.isWorking)
                XCTAssertTrue(
                    DatabaseActivity.shared.operations.contains
                    {

                        $0.message == "Synchronizing shared database..."
                    })
                await Task.yield()

                XCTAssertTrue(DatabaseActivity.shared.isWorking)

                guard let url = request.url /* URL fixture for the request */ else
                {


                    XCTFail("Missing synthetic request URL")
                    client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }


                if url.host == "success.example.test"
                {


                    let response = HTTPURLResponse( /* Synthetic API response */
                        url: url, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: Data("{\"users\":[]}".utf8))
                    client?.urlProtocolDidFinishLoading(self)
                }
                else
                {


                    client?.urlProtocol(
                        self, didFailWithError: URLError(url.host == "timeout.example.test" ? .timedOut : .cancelled)
                    )
                }

            }

        }


        ///
        /// @fcn        PlenactBoardDocumentTests.ActivityTestURLProtocol.stopLoading()
        /// @brief      Provide the required URLProtocol cancellation hook
        /// @details    This fixture performs no resource cleanup and does not cancel its spawned
        ///             task
        ///
        /// @return     (Void) provide the required URLProtocol cancellation hook
        ///
        override func stopLoading()
        {

        }

    }

}
