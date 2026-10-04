// -------------------------------------------------------------------------------------------------
// @file       PlenactBoardDocumentTests.swift
// @brief      Versioned Board sync document tests
// @details    Verifies snapshot validation, typed assignees, and JSON round trips
//
// -------------------------------------------------------------------------------------------------
import XCTest
import SwiftUI
@testable import Plenact


///
/// Verifies the Plenact-specific Board snapshot contract
///
/// @section    Purpose
///     Protect schema versioning and stable references before the document is sent to an API
///
final class PlenactBoardDocumentTests: XCTestCase {

    func testListReorderingMovesRestoredMondayToFirstWithoutChangingContent() throws {
        var lists = SampleData.lists
        let monday = lists.removeFirst()
        lists.append(monday)
        XCTAssertTrue(BoardListReordering.move(monday.id, to: 0, in: &lists))
        XCTAssertEqual(lists, SampleData.lists)
        XCTAssertTrue(BoardListReordering.move(monday.id, to: lists.count - 1, in: &lists))
        XCTAssertEqual(lists.last, monday)
        let restored = try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists))
        XCTAssertEqual(restored, lists)
    }

    func testListReorderingRejectsMissingAndOutOfBoundsMoves() {
        var lists = SampleData.lists
        let original = lists
        XCTAssertFalse(BoardListReordering.move(999, to: 0, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: -1, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: lists.count, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: 0, in: &lists))
        XCTAssertEqual(lists, original)
    }

    func testListDragEdgeThresholdsAndInvalidGeometry() {
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

    @MainActor
    func testBackgroundWeekPersistenceKeepsArchivedListsAndAllowsEmptyWorkspace() async throws {
        let suite = "Plenact.WeekArchiveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var archived = SampleData.lists[1]
        archived.isArchived = true
        let snapshot = [SampleData.lists[0], archived]
        KanbanBoardPersistence.enqueueSave(snapshot, suiteName: suite)
        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restored, snapshot)
        KanbanBoardPersistence.enqueueSave([], suiteName: suite)
        let emptyWeek = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertTrue(emptyWeek.isEmpty)
    }

    @MainActor
    func testListArchiveBindingsPreserveCardsAndRestoreAtEnd() throws {
        let original = SampleData.lists[0]
        var snapshot = [original, SampleData.lists[1]]
        let board = Binding(get: { snapshot }, set: { snapshot = $0 })
        var archived = original
        archived.isArchived = true
        board.archivedLists.wrappedValue.append(archived)
        board.activeLists.wrappedValue.removeAll { $0.id == original.id }

        XCTAssertEqual(board.activeLists.wrappedValue.map(\.id), [1])
        XCTAssertEqual(board.archivedLists.wrappedValue, [archived])
        snapshot = try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(board.archivedLists.wrappedValue, [archived])
        var restored = try XCTUnwrap(board.archivedLists.wrappedValue.first)
        restored.isArchived = false
        board.activeLists.wrappedValue.append(restored)
        board.archivedLists.wrappedValue.removeAll { $0.id == original.id }
        XCTAssertEqual(snapshot, [SampleData.lists[1], original])
    }

    func testWholeWeekArchiveRestoresAsSeparateUniquelyNamedBoard() throws {
        var archivedList = SampleData.lists[1]
        archivedList.isArchived = true
        var list = SampleData.lists[0]
        list.archiveCard(id: list.cards[0].id)
        let sourceLists = [list, archivedList]
        let savedIDs: Set<Int> = [list.archivedCards[0].id]
        var board = PersonalCollection.archivedWeekBoard(lists: sourceLists, savedCardIDs: savedIDs)
        let boardID = board.id
        XCTAssertEqual(board.isArchived, true)
        board = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(board))
        board.restore(existingTitles: ["Week Board", "Week Board (Restored)", "week board (restored) (2)"])
        XCTAssertEqual(board.title, "Week Board (Restored) (3)")
        XCTAssertTrue(board.isActive)
        XCTAssertEqual(board.id, boardID)
        XCTAssertEqual(board.lists, sourceLists)
        XCTAssertEqual(board.savedCardIDs, savedIDs)
        XCTAssertEqual(board.lists[0].archivedCards, list.archivedCards)
        XCTAssertTrue(board.lists[1].isArchived)
    }

    func testArchivedPersonalBoardPersistsAndRestoresWithoutRenamingItsLists() throws {
        let suite = "Plenact.BoardArchiveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var board = PersonalCollection(title: "Project", kind: .board, icon: .project)
        board.isArchived = true
        board.lists[0].cards = [KanbanCard(id: 77, word: "Task", listTitle: board.lists[0].title)]
        board.lists[1].isArchived = true
        board.savedCardIDs = [77]
        try PersonalCollectionStore.saveChecked([board], to: defaults)
        var restored = try XCTUnwrap(PersonalCollectionStore.load(from: defaults).first)
        XCTAssertFalse(restored.isActive)
        restored.restore(existingTitles: ["project"])
        XCTAssertEqual(restored.title, "Project (2)")
        XCTAssertEqual(restored.lists, board.lists)
        XCTAssertEqual(restored.savedCardIDs, board.savedCardIDs)
        XCTAssertTrue(restored.isActive)
        try PersonalCollectionStore.saveChecked([restored], to: defaults)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [restored])
    }

    func testPersonalBoardArchiveSavesBeforeReturningUpdatedState() throws {
        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = PersonalCollection(title: "Project", kind: .board)
        let other = PersonalCollection(title: "Shopping", kind: .list)
        let original = [board, other]
        let updated = try PersonalCollectionStore.archiveBoard(id: board.id, in: original, to: defaults)
        XCTAssertTrue(original[0].isActive)
        XCTAssertFalse(updated[0].isActive)
        XCTAssertEqual(updated[1], other)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), updated)
    }

    func testPersonalBoardArchiveFailureKeepsMemoryAndSavedSnapshotActive() throws {
        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = PersonalCollection(title: "Project", kind: .board)
        try PersonalCollectionStore.saveChecked([board], to: defaults)
        var draft = board
        var invalidCard = KanbanCard(id: 1, word: "Unsaved", listTitle: draft.lists[0].title)
        invalidCard.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)
        draft.lists[0].cards = [invalidCard]
        var collections = [draft]

        XCTAssertThrowsError(
            collections = try PersonalCollectionStore.archiveBoard(id: draft.id, in: collections, to: defaults)
        )
        XCTAssertEqual(collections, [draft])
        XCTAssertTrue(collections[0].isActive)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [board])
    }

    func testPersonalBoardArchiveRejectsMissingBoardWithoutChangingSavedData() throws {
        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = PersonalCollection(title: "Project", kind: .board)
        try PersonalCollectionStore.saveChecked([board], to: defaults)
        XCTAssertThrowsError(try PersonalCollectionStore.archiveBoard(id: UUID(), in: [board], to: defaults))
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [board])
    }

    func testLegacyPersonalBoardDefaultsToActiveAndArchivedListsStayOutOfSearch() throws {
        let original = PersonalCollection(title: "Project", kind: .board)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "isArchived")
        var decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.isActive)
        decoded.lists[0].cards = [KanbanCard(id: 500, word: "Hidden activity", listTitle: decoded.lists[0].title)]
        decoded.lists[0].isArchived = true
        XCTAssertFalse(decoded.matches("Hidden activity"))
        XCTAssertEqual(decoded.cardCount, 0)
        let document = PlenactBoardDocument(lists: decoded.lists, labelLibrary: .starter)
        XCTAssertEqual(document.validationMessage, "Archived lists are stored locally and cannot be published to the shared Board.")
    }

    func testLegacyListsLoadWithEmptyArchiveAndKeepExistingJSONShape() throws {
        let data = Data("{\"id\":1,\"title\":\"Monday\",\"cards\":[]}".utf8)
        let list = try JSONDecoder().decode(KanbanList.self, from: data)
        XCTAssertTrue(list.archivedCards.isEmpty)
        let encoded = try JSONEncoder().encode(list)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "title", "cards"])
    }

    func testArchivingAndRestoringPreservesFullCardAndDivider() throws {
        var completed = SampleData.lists[0].cards[0]
        completed.isTitleChecked = true
        completed.attachments = [KanbanAttachment(fileName: "synthetic-archive.jpg", mediaKind: .photo)]
        let active = KanbanCard(id: 500, word: "Active", listTitle: "Monday")
        let divider = KanbanCard(id: 501, word: "Divider", listTitle: "Monday", isDivider: true, isTitleChecked: true)
        var list = KanbanList(id: 1, title: "Monday", cards: [completed, divider, active])

        list.archiveCompletedCards()
        XCTAssertEqual(list.cards, [divider, active])
        XCTAssertEqual(list.archivedCards, [completed])
        XCTAssertEqual(Set(list.allCards.compactMap { $0.attachments?.first?.fileName }), ["synthetic-archive.jpg"])
        list.archiveCompletedCards()
        XCTAssertEqual(list.archivedCards, [completed])

        list = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(list.archivedCards, [completed])
        list.restoreArchivedCard(id: completed.id)
        XCTAssertEqual(list.cards, [divider, active, completed])
        XCTAssertTrue(list.archivedCards.isEmpty)
        list.restoreArchivedCard(id: completed.id)
        XCTAssertEqual(list.cards, [divider, active, completed])
    }

    func testArchivedCardsStayOutOfSearchAndReserveTheirIDs() {
        let archived = KanbanCard(id: 900, word: "Archived task", listTitle: "Monday", isTitleChecked: true)
        let list = KanbanList(
            id: 1, title: "Monday",
            cards: [KanbanCard(id: 1, word: "Active task", listTitle: "Monday")],
            archivedCards: [archived]
        )
        XCTAssertTrue(TodaySearchIndex.results(query: "Archived task", scope: .all, lists: [list], library: .starter).isEmpty)
        XCTAssertEqual(([list].flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1, 901)
        let document = PlenactBoardDocument(lists: [list], labelLibrary: .starter)
        XCTAssertEqual(document.validationMessage, "Archived cards are stored locally and cannot be published to the shared Board.")
    }

    func testIndividualArchiveAcceptsIncompleteCardsAndPreservesContent() throws {
        var incomplete = SampleData.lists[0].cards[0]
        incomplete.isTitleChecked = false
        XCTAssertFalse(incomplete.isTitleChecked)
        var complete = SampleData.lists[0].cards[1]
        complete.isTitleChecked = true
        let divider = KanbanCard(id: 800, word: "Divider", listTitle: "Monday", isDivider: true)
        var list = KanbanList(id: 1, title: "Monday", cards: [incomplete, complete, divider])

        list.archiveCard(id: incomplete.id)
        list.archiveCard(id: complete.id)
        list.archiveCard(id: incomplete.id)
        list.archiveCard(id: divider.id)
        XCTAssertEqual(list.cards, [divider])
        XCTAssertEqual(list.archivedCards, [incomplete, complete])
        list = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        list.restoreArchivedCard(id: incomplete.id)
        XCTAssertEqual(list.cards, [divider, incomplete])
        XCTAssertFalse(list.cards[1].isTitleChecked)
        XCTAssertEqual(list.archivedCards, [complete])
    }

    func testPersonalListRenamePreservesArchivedCards() throws {
        var collection = PersonalCollection(title: "Original", kind: .list)
        let archived = KanbanCard(id: 42, word: "Archived", listTitle: "Original", isTitleChecked: true)
        collection.lists[0].archivedCards = [archived]
        collection.rename(to: "Renamed")
        var expected = archived
        expected.listTitle = "Renamed"
        XCTAssertEqual(collection.lists[0].archivedCards, [expected])
        let restored = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection))
        XCTAssertEqual(restored, collection)
    }

    @MainActor
    func testAPIActivityEndsAfterSuccessFailureAndCancellation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivityTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        for outcome in ["success", "timeout", "cancelled"] {
            let initialCount = DatabaseActivity.shared.operations.count
            let url = try XCTUnwrap(URL(string: "https://\(outcome).example.test/"))
            let client = try PlenactAPIClient(baseURL: url, session: session)
            do {
                let users = try await client.directory(token: "synthetic-test-token")
                XCTAssertEqual(outcome, "success")
                XCTAssertTrue(users.isEmpty)
            } catch {
                let error = try XCTUnwrap(error as? URLError)
                XCTAssertEqual(error.code, outcome == "timeout" ? .timedOut : .cancelled)
            }
            XCTAssertEqual(DatabaseActivity.shared.operations.count, initialCount)
        }
    }

    @MainActor
    func testDatabaseActivityKeepsSpinnerUntilAllOperationsFinish() {
        let activity = DatabaseActivity()
        let save = activity.begin("Saving Board...")
        let refresh = activity.begin("Synchronizing shared database...")
        XCTAssertTrue(activity.isWorking)
        XCTAssertEqual(activity.message, "Saving Board...")

        activity.end(save)
        XCTAssertTrue(activity.isWorking)
        XCTAssertEqual(activity.message, "Synchronizing shared database...")
        activity.end(save)
        XCTAssertTrue(activity.isWorking)

        activity.end(refresh)
        XCTAssertFalse(activity.isWorking)
        XCTAssertNil(activity.message)
    }

    private final class ActivityTestURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Task { @MainActor in
                XCTAssertTrue(DatabaseActivity.shared.isWorking)
                XCTAssertTrue(DatabaseActivity.shared.operations.contains {
                    $0.message == "Synchronizing shared database..."
                })
                await Task.yield()
                XCTAssertTrue(DatabaseActivity.shared.isWorking)
                guard let url = request.url else {
                    XCTFail("Missing synthetic request URL")
                    client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }
                if url.host == "success.example.test" {
                    let response = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: Data("{\"users\":[]}".utf8))
                    client?.urlProtocolDidFinishLoading(self)
                } else {
                    client?.urlProtocol(
                        self, didFailWithError: URLError(url.host == "timeout.example.test" ? .timedOut : .cancelled)
                    )
                }
            }
        }

        override func stopLoading() {}
    }

    @MainActor
    func testDatabaseActivityErrorsRemainUntilDismissed() {
        let activity = DatabaseActivity()
        let operation = activity.begin("Saving Board...")
        activity.report("Could not save the Board.")
        activity.end(operation)
        XCTAssertFalse(activity.isWorking)
        XCTAssertEqual(activity.errorMessage, "Could not save the Board.")
        activity.dismissError()
        XCTAssertNil(activity.errorMessage)
    }

    @MainActor
    func testBackgroundBoardSavesPreserveLatestSnapshot() async throws {
        let suite = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = [KanbanList(id: 1, title: "First", cards: [])]
        let last = [KanbanList(id: 1, title: "Latest", cards: [])]

        KanbanBoardPersistence.enqueueSave(first, suiteName: suite)
        KanbanBoardPersistence.enqueueSave(last, suiteName: suite)
        XCTAssertTrue(DatabaseActivity.shared.isWorking)
        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restored, last)
        let data = try XCTUnwrap(defaults.data(forKey: "Plenact.Board.v1"))
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: data), last)
    }

    @MainActor
    func testBackgroundBoardSaveFailurePreservesPreviousSnapshot() async throws {
        let suite = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }
        let original = [KanbanList(id: 1, title: "Saved", cards: [])]
        KanbanBoardPersistence.enqueueSave(original, suiteName: suite)
        _ = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)

        var invalidCard = KanbanCard(id: 1, word: "Unsaved", listTitle: "Saved")
        invalidCard.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)
        KanbanBoardPersistence.enqueueSave(
            [KanbanList(id: 1, title: "Saved", cards: [invalidCard])], suiteName: suite
        )
        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restored, original)
        XCTAssertTrue(DatabaseActivity.shared.errorMessage?.hasPrefix("Could not save the Board:") == true)
    }

    @MainActor
    func testBackgroundBoardLoadReportsCorruptionWithoutRemovingData() async throws {
        let suite = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }
        let invalidData = Data("not JSON".utf8)
        defaults.set(invalidData, forKey: "Plenact.Board.v1")
        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restored, SampleData.lists)
        XCTAssertNotNil(DatabaseActivity.shared.errorMessage)
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), invalidData)
    }

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

    func testPersonalCollectionPersistencePreservesOrderAndLeavesWeekUntouched() throws {
        let suite = "Plenact.PersonalCollectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let weekSnapshot = try JSONEncoder().encode(SampleData.lists)
        defaults.set(weekSnapshot, forKey: "Plenact.Board.v1")

        var shopping = PersonalCollection(title: "Shopping", kind: .list, icon: .shopping, color: .coral)
        shopping.lists[0].cards = [KanbanCard(id: 0, word: "Eggs", listTitle: "Shopping", checklists: [])]
        shopping.savedCardIDs = [0]
        let project = PersonalCollection(title: "New Project Notes", kind: .board, icon: .project)
        PersonalCollectionStore.save([project, shopping], to: defaults)

        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [project, shopping])
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), weekSnapshot)
        XCTAssertEqual(shopping.lists.count, 1)
        XCTAssertEqual(project.lists.map(\.title), ["Ideas", "In progress", "Done"])
        XCTAssertEqual(shopping.cardCount, 1)
    }

    func testPersonalCollectionRenameAndSearchPreserveCardIdentity() {
        var collection = PersonalCollection(title: "Shopping", kind: .list)
        collection.lists[0].cards = [
            KanbanCard(id: 9, word: "Eggs", listTitle: "Shopping", checklists: [], descriptionOverride: "Breakfast"),
            KanbanCard(id: 10, word: "Divider", listTitle: "Shopping", isDivider: true)
        ]
        collection.rename(to: "  Groceries  ")

        XCTAssertEqual(collection.title, "Groceries")
        XCTAssertEqual(collection.lists[0].title, "Groceries")
        XCTAssertEqual(collection.lists[0].cards.map(\.id), [9, 10])
        XCTAssertTrue(collection.lists[0].cards.allSatisfy { $0.listTitle == "Groceries" })
        XCTAssertEqual(collection.cardCount, 1)
        XCTAssertTrue(collection.matches("eggs"))
        XCTAssertTrue(collection.matches("Breakfast"))
        XCTAssertTrue(collection.matches(" "))
        XCTAssertFalse(collection.matches("Divider"))

        var board = PersonalCollection(title: "Project", kind: .board)
        board.rename(to: "Research")
        XCTAssertEqual(board.lists.map(\.title), ["Ideas", "In progress", "Done"])
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