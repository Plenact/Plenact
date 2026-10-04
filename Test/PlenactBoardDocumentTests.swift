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

    func testRecentSearchesAreOrderedDeduplicatedAndClearable() throws {
        let suite = "Plenact.SearchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        RecentSearchStore.remember("  Monday  ", in: defaults)
        RecentSearchStore.remember("Work", in: defaults)
        XCTAssertEqual(RecentSearchStore.remember("monday", in: defaults), ["monday", "Work"])
        XCTAssertEqual(RecentSearchStore.remember("  ", in: defaults), ["monday", "Work"])
        for index in 0..<12 {
            RecentSearchStore.remember("Search \(index)", in: defaults)
        }
        XCTAssertEqual(RecentSearchStore.load(from: defaults).count, 10)
        XCTAssertEqual(RecentSearchStore.load(from: defaults).first, "Search 11")
        RecentSearchStore.clear(in: defaults)
        XCTAssertTrue(RecentSearchStore.load(from: defaults).isEmpty)
    }

    func testSearchScopesUseOnlyTheirSelectedFields() {
        let card = KanbanCard(
            id: 1, word: "Proposal", listTitle: "Monday",
            members: [.manual("Jamie")], labelIDs: ["work-scheduled"],
            descriptionOverride: "Budget review"
        )
        let lists = [KanbanList(id: 0, title: "Monday", cards: [card])]
        func matches(_ term: String, _ scope: TodaySearchScope) -> [TodaySearchResult] {
            TodaySearchIndex.results(query: term, scope: scope, lists: lists, library: .starter)
        }

        XCTAssertEqual(matches("Scheduled", .labels).map(\.cardID), [1])
        XCTAssertEqual(matches("Work", .labels).count, 1)
        XCTAssertTrue(matches("Proposal", .labels).isEmpty)
        XCTAssertEqual(matches("Jamie", .users).map(\.cardID), [1])
        XCTAssertTrue(matches("Budget", .users).isEmpty)
        XCTAssertEqual(matches("Budget", .all).count, 1)
        XCTAssertEqual(matches("Scheduled", .all).count, 1)
        XCTAssertEqual(matches("Monday", .boards).map(\.listID), [0])
        XCTAssertTrue(matches("Proposal", .boards).isEmpty)
        XCTAssertTrue(matches(" ", .all).isEmpty)
    }

    func testBoardSearchIncludesEmptyListsAndCardSearchExcludesDividers() {
        let divider = KanbanCard(id: 1, word: "Divider", listTitle: "Monday", isDivider: true)
        let lists = [
            KanbanList(id: 0, title: "Monday", cards: [divider]),
            KanbanList(id: 2, title: "Empty list", cards: [])
        ]
        let results = TodaySearchIndex.results(query: "Empty", scope: .boards, lists: lists, library: .starter)
        XCTAssertEqual(results.map(\.listID), [2])
        XCTAssertNil(results.first?.cardID)
        XCTAssertTrue(TodaySearchIndex.results(query: "Divider", scope: .all, lists: lists, library: .starter).isEmpty)
    }

    func testExampleLoadUndoSnapshotPersistsAndClears() throws {
        let suite = "Plenact.ExampleLoadUndoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let lists = Array(SampleData.lists.prefix(2))
        let snapshot = ExampleLoadUndoSnapshot(lists: lists, todayListID: lists[1].id)

        XCTAssertTrue(ExampleLoadUndoStore.save(lists: lists, todayListID: lists[1].id, to: defaults))
        XCTAssertEqual(ExampleLoadUndoStore.load(from: defaults), snapshot)

        ExampleLoadUndoStore.clear(from: defaults)
        XCTAssertNil(ExampleLoadUndoStore.load(from: defaults))
    }

    func testLastViewedListResolvesSavedSelectionAndFallbacks() throws {
        let suite = "Plenact.LastViewedListTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let lists = [KanbanList(id: 4, title: "Week", cards: []), KanbanList(id: 9, title: "Shopping", cards: [])]
        LastViewedListStore.save(9, to: defaults)
        XCTAssertEqual(LastViewedListStore.resolve(in: lists, fallback: 4, from: defaults), 9)
        XCTAssertEqual(LastViewedListStore.resolve(in: [lists[0]], fallback: nil, from: defaults), 4)
        XCTAssertEqual(LastViewedListStore.resolve(in: [], fallback: nil, from: defaults), nil)
    }

    func testTodayDefaultsToMondayAfterSavedAndProfileChoices() {
        let lists = [
            KanbanList(id: 3, title: "Tuesday", cards: []),
            KanbanList(id: 7, title: "Monday", cards: [])
        ]

        XCTAssertEqual(TodayListSelection.initialListID(savedListID: nil, profileDefaultListID: nil, lists: lists), 7)
        XCTAssertEqual(TodayListSelection.initialListID(savedListID: nil, profileDefaultListID: 3, lists: lists), 3)
        XCTAssertEqual(TodayListSelection.initialListID(savedListID: 7, profileDefaultListID: 3, lists: lists), 7)
        XCTAssertEqual(TodayListSelection.initialListID(savedListID: 99, profileDefaultListID: nil, lists: lists), 7)
    }

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

    /// Verify the complete encoded seed request fits the confirmed v1 JSON body ceiling
    func testSampleDataSeedRequestFitsJSONBodyLimit() throws {

        let jim = PlenactRemoteUser(
            userID: "fb13a9ee-9107-47c3-bb4f-dff07fe57eba",
            username: "jim",
            displayName: "Jim",
            accountRole: "board_editor"
        )
        let request = PlenactBoardWriteRequest(
            expectedRevision: 0,
            document: PlenactAPIClient.sampleDataDocument(for: jim),
            seedKind: "sample_data_v1"
        )
        let encodedRequest = try JSONEncoder().encode(request)

        XCTAssertLessThanOrEqual(encodedRequest.count, PlenactAPIClient.maximumJSONBodyBytes)
    }

    /// Verify the client accepts exactly 1 MiB and rejects a body one byte over
    func testJSONBodySizeLimitIncludesExactBoundary() {

        let maximumBody = Data(repeating: 0, count: PlenactAPIClient.maximumJSONBodyBytes)
        let oversizedBody = Data(repeating: 0, count: PlenactAPIClient.maximumJSONBodyBytes + 1)

        XCTAssertTrue(PlenactAPIClient.isJSONBodyWithinLimit(maximumBody))
        XCTAssertFalse(PlenactAPIClient.isJSONBodyWithinLimit(oversizedBody))
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