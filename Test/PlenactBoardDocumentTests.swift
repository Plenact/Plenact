// -------------------------------------------------------------------------------------------------
// @file       PlenactBoardDocumentTests.swift
// @brief      Versioned Board sync document tests
// @details    Verifies snapshot validation, typed assignees, and JSON round trips
//
// -------------------------------------------------------------------------------------------------
import XCTest
@testable import Plenact


///
/// Verifies the Plenact-specific Board snapshot contract
///
/// @section    Purpose
///     Protect schema versioning and stable references before the document is sent to an API
///
final class PlenactBoardDocumentTests: XCTestCase {

    ///
    /// @fcn        PlenactBoardDocumentTests.testStarterBoardDocumentRoundTrips
    /// @brief      Encode and decode the complete starter Board document
    /// @details    Verifies weekday lists, labels, and typed card assignees remain intact
    ///
    /// @return     (Void) succeeds when the versioned document round-trips without loss
    ///
    /// @throws     JSON encoding or decoding failures
    ///
    func testStarterBoardDocumentRoundTrips() throws {

        let document = PlenactBoardDocument(   /* Synthetic shared Board fixture */
            lists:        SampleData.lists,
            labelLibrary: .starter
        )
        let encoded = try JSONEncoder().encode(document)                                   /* Versioned JSON */
        let decoded = try JSONDecoder().decode(PlenactBoardDocument.self, from: encoded)   /* Restored Board */

        XCTAssertEqual(decoded, document)
        XCTAssertNil(decoded.validationMessage)
        XCTAssertEqual(decoded.lists.map(\.title), SampleData.listTitles)
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testRegisteredAssigneeRequiresUUID
    /// @brief      Reject invalid registered-user identifiers
    /// @details    Ensures directory references use stable UUIDs instead of display names
    ///
    /// @return     (Void) succeeds when invalid registered identity is rejected
    ///
    func testRegisteredAssigneeRequiresUUID() {

        var card = SampleData.lists[0].cards[0]   /* Starter card */
        card.members = [.registered(userID: "Jim", displayName: "Jim")]

        let document = PlenactBoardDocument( /* Invalid registered-assignee fixture */
            lists: [KanbanList(id: 0, title: "Monday", cards: [card])],
            labelLibrary: .starter
        )

        XCTAssertEqual(document.validationMessage, "Registered card assignees need a valid stable user ID.")
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testManualAssigneeCannotContainUserID
    /// @brief      Keep manual names distinct from registered accounts
    /// @details    Rejects a malformed manual assignee carrying a registered user reference
    ///
    /// @return     (Void) succeeds when the invalid mixed identity is rejected
    ///
    func testManualAssigneeCannotContainUserID() {

        var card = SampleData.lists[0].cards[0]   /* Starter card */
        card.members = [CardAssignee(kind: .manual, userID: UUID().uuidString, displayName: "Jim")]

        let document = PlenactBoardDocument( /* Invalid manual-assignee fixture */
            lists: [KanbanList(id: 0, title: "Monday", cards: [card])],
            labelLibrary: .starter
        )

        XCTAssertEqual(document.validationMessage, "Manual card assignees cannot contain a registered user ID.")
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testDocumentRejectsEmptyCardTitle
    /// @brief      Reject a blank title before it reaches the shared API
    /// @details    Ensures local snapshot validation matches the server's required card-title constraint
    ///
    /// @return     (Void) succeeds when an empty card title returns a validation message
    ///
    func testDocumentRejectsEmptyCardTitle() {

        var card = SampleData.lists[0].cards[0] /* Starter card with an invalid title */
        card.word = "  "
        let document = PlenactBoardDocument( /* Invalid-title fixture */
            lists: [KanbanList(id: 0, title: "Monday", cards: [card])],
            labelLibrary: .starter
        )

        XCTAssertEqual(
            document.validationMessage,
            "Each Board card needs a unique nonnegative ID, title, and matching list title."
        )
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testSampleDataSeedMapsKnownStarterAssigneeToJim
    /// @brief      Map only the known SampleData assignee to Jim's registered identity
    /// @details    Verifies the seed keeps weekday content and labels while leaving local sample data unchanged
    ///
    /// @return     (Void) succeeds when the versioned seed remains valid and linked to Jim
    ///
    func testSampleDataSeedMapsKnownStarterAssigneeToJim() {

        let jim = PlenactRemoteUser( /* Authenticated editor identity for the seed */
            userID: "fb13a9ee-9107-47c3-bb4f-dff07fe57eba",
            username: "jim",
            displayName: "Jim",
            accountRole: "board_editor"
        )
        let document = PlenactAPIClient.sampleDataDocument(for: jim) /* Seed transformed for Jim */
        let seededAssignments = document.lists.flatMap(\.cards).flatMap(\.members) /* All seed assignments */

        XCTAssertNil(document.validationMessage)
        XCTAssertEqual(document.lists.map(\.title), SampleData.listTitles)
        XCTAssertEqual(document.labelLibrary, .starter)
        XCTAssertEqual(seededAssignments.count, SampleData.lists.flatMap(\.cards).flatMap(\.members).count)
        XCTAssertTrue(seededAssignments.allSatisfy {
            $0.kind == .registeredUser && $0.userID == jim.userID && $0.displayName == jim.displayName
        })
        XCTAssertEqual(SampleData.lists[0].cards[0].members[0].kind, .manual)
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testAPIClientRejectsPlainHTTPEndpoint
    /// @brief      Require HTTPS for shared-demo API endpoints
    /// @details    Rejects plaintext HTTP while accepting a syntactically valid HTTPS base URL
    ///
    /// @return     (Void) succeeds when endpoint transport security is enforced
    ///
    func testAPIClientRejectsPlainHTTPEndpoint() {

        let insecureURL = URL(string: "http://demo.example.test/api/")! /* Test-only plaintext endpoint */

        XCTAssertThrowsError(try PlenactAPIClient(baseURL: insecureURL)) { error in
            guard let apiError = error as? PlenactAPIError, /* Typed endpoint validation error */
                  case .invalidEndpoint = apiError else {
                XCTFail("Expected the API client to reject plain HTTP.")
                return
            }
        }

        let secureURL = URL(string: "https://demo.example.test/api/")!
        XCTAssertNoThrow(try PlenactAPIClient(baseURL: secureURL))
    }
}