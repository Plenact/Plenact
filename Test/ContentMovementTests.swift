// --------------------------------------------------------------------------------------------------
// @file       ContentMovementTests.swift
// @brief      Content Movement regression tests
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
/// ContentMovement regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testVisibleReorderingMapsPastCollapsedContentAndRevealsTheMovedCard
    /// @brief      Verify that visible Reordering Maps Past Collapsed Content And Reveals The Moved Card
    /// @details    Exercises `DaySections.visibleMove`, `DaySections.reordered`, `DaySections.reveal`. Checks
    ///             `XCTAssertEqual(move.id, 5)`; `XCTAssertEqual(move.index, 3)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testVisibleReorderingMapsPastCollapsedContentAndRevealsTheMovedCard() throws
    {


        ///
        /// @fcn        PlenactBoardDocumentTests.testVisibleReorderingMapsPastCollapsedContentAndRevealsTheMovedCard.card
        /// @brief      Prepare card for the enclosing regression test
        /// @details    Supplies the local fixture for visible Reordering Maps Past Collapsed Content And Reveals The
        ///             Moved Card.
        ///
        /// @param[in]  id     Starting numeric card ID or owner-local content identity
        /// @param[in]  title  Display title or proposed title text
        ///
        /// @return     (KanbanCard) result described by this operation's contract
        ///
        func card(_ id: Int, _ title: String) -> KanbanCard
        {

            KanbanCard(id: id, word: title, listTitle: "Day", checklists: [])
        }

        var heading = card(1, "--- Morning")
        heading.appearance = ItemAppearance(accent: .orange, sectionCollapsed: true)
        let cards = [
            card(0, "Before"), heading, card(2, "Hidden"), card(3, "--- Evening"), card(4, "Visible"), card(5, "Last")
        ]
        let move = try XCTUnwrap(
            DaySections.visibleMove(cards, sourceOffsets: IndexSet(integer: 4), destinationOffset: 2))
        XCTAssertEqual(move.id, 5)
        XCTAssertEqual(move.index, 3)
        var result = DaySections.reordered(cards, itemID: move.id, to: move.index)
        DaySections.reveal(move.id, in: &result)
        XCTAssertEqual(result.map(\.id), [0, 1, 2, 5, 3, 4])
        XCTAssertEqual(DaySections.visible(result).map(\.id), result.map(\.id))
        XCTAssertEqual(Set(result.map(\.id)), Set(cards.map(\.id)))
        XCTAssertEqual(result.first
            {
                $0.id == 2
            }, cards[2], "Hidden content remains intact")
        var lists = [KanbanList(id: 1, title: "Day", cards: cards)]
        XCTAssertTrue(try BoardCardMovement.move(5, to: 1, before: 3, in: &lists))
        XCTAssertEqual(lists[0].cards.map(\.id), [0, 1, 2, 5, 3, 4])
        XCTAssertEqual(lists[0].cards.first
            {
                $0.id == 1
            }?.appearance?.sectionCollapsed, false)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSingleListViewModePersistsWithoutConvertingOrReorderingContent
    /// @brief      Verify that single List View Mode Persists Without Converting Or Reordering Content
    /// @details    Exercises `list.setSingleListViewMode`, `anotherDay.setSingleListViewMode`. Checks
    ///             `XCTAssertEqual(list.singleListViewMode, .cards)`; `XCTAssertEqual(restored.singleListViewMode,
    ///             .noteList)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testSingleListViewModePersistsWithoutConvertingOrReorderingContent() throws
    {

        var list = KanbanList(
            id: 4, title: "Wednesday",
            cards: [
                KanbanCard(
                    id: 1, word: "Task", listTitle: "Wednesday", isTitleChecked: true,
                    checklists: [
                        KanbanChecklist(title: "Steps", items: [KanbanChecklistItem(title: "Done", isCompleted: true)])
                    ]),
                KanbanCard(
                    id: 2, word: "A note", listTitle: "Wednesday", checklists: [],
                    descriptionOverride: "Keep this writing", presentation: .note)
            ])
        list.appearance = ItemAppearance(icon: .tasks)
        let original = list
        XCTAssertEqual(list.singleListViewMode, .cards)
        list.setSingleListViewMode(.noteList)
        let restored = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(restored.singleListViewMode, .noteList)
        XCTAssertEqual(restored.cards, original.cards)
        XCTAssertEqual(restored.archivedCards, original.archivedCards)
        XCTAssertEqual(restored.appearance?.icon, original.appearance?.icon)
        list.setSingleListViewMode(.cards)
        XCTAssertEqual(list.cards, original.cards)
        XCTAssertEqual(list.singleListViewMode, .cards)
        XCTAssertFalse(ItemAppearance(listViewMode: .noteList).isEmpty)
        XCTAssertNil(try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8)).listViewMode)
        var anotherDay = KanbanList(id: 5, title: "Thursday", cards: [])
        XCTAssertEqual(anotherDay.singleListViewMode, .cards)
        anotherDay.setSingleListViewMode(.noteList)
        XCTAssertEqual(anotherDay.singleListViewMode, .noteList)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testKeepTomorrowDecisionPersistsWithoutCopyingOrRetimingTheTableItem
    /// @brief      Verify that keep Tomorrow Decision Persists Without Copying Or Retiming The Table Item
    /// @details    Exercises `DatedPlanningWeek.make`, `.now.addingTimeInterval`, `TodayReviewSelection.items`.
    ///             Checks `XCTAssertEqual(restored.eveningReview?.decisions.first?.action, .keepTomorrow)`;
    ///             `XCTAssertTrue(TodayReviewSelection.pending(items, review: restored.eveningReview).isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testKeepTomorrowDecisionPersistsWithoutCopyingOrRetimingTheTableItem() throws
    {

        let suite = "ReviewCarryTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let week = DatedPlanningWeek.make(for: .now)
        var table = PersonalCollection(title: "On the Table", kind: .list)
        var card = KanbanCard(
            id: 0, word: "Go to the grocery store", listTitle: table.title, checklists: [], createdAt: .now)
        card.dueDate = .now.addingTimeInterval(-3600)
        table.lists[0].cards = [card]
        let access = PlanningCalendarAccess(
            document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [table],
            saveWeek:
            {
                _ in
                XCTFail("Keep must not save/move the source");
                return false
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
                XCTFail("Keep must not save/move the source");
                return false
            })
        var plan = DailyPlan(date: .now)
        let items = TodayReviewSelection.items(
            plan: plan, date: .now, access: access, referenceLabelIDs: [], calendar: .current)
        let source = DailyPlanPriority(try XCTUnwrap(items.first))
        var review = DailyEveningReview()
        review.decisions = [DailyReviewDecision(source: source, result: source, action: .keepTomorrow)]
        plan.eveningReview = review
        try DailyReviewTransaction.perform(in: defaults)
        {

            _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        }

        let restored = try XCTUnwrap(DailyPlanStore.load(from: defaults).plans[plan.id])
        XCTAssertEqual(restored.eveningReview?.decisions.first?.action, .keepTomorrow)
        XCTAssertTrue(TodayReviewSelection.pending(items, review: restored.eveningReview).isEmpty)
        XCTAssertEqual(TodayReviewSelection.pending(items, review: nil).count, 1, "Tomorrow gets a fresh decision")
        XCTAssertEqual(access.library[0], table)
        XCTAssertEqual(access.library[0].lists[0].cards[0].dueDate, card.dueDate)
        XCTAssertEqual(
            try JSONDecoder().decode(DailyReviewAction.self, from: JSONEncoder().encode(DailyReviewAction.table)),
            .table)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWholeListMoveRejectsUnavailableOrSameBoardWithoutMutation
    /// @brief      Verify that whole List Move Rejects Unavailable Or Same Board Without Mutation
    /// @details    Exercises `CrossBoardListMovement.move`. Checks `XCTAssertThrowsError(try
    ///             CrossBoardListMovement.move(listID: 4, from: source.id, to: destination, collections: &boards))`;
    ///             `XCTAssertEqual(boards, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWholeListMoveRejectsUnavailableOrSameBoardWithoutMutation() throws
    {

        var source = PersonalCollection(title: "Source", kind: .board)
        source.lists = [KanbanList(id: 4, title: "List", cards: [])]
        var archived = PersonalCollection(title: "Archived", kind: .board)
        archived.isArchived = true
        var boards = [source, archived]
        let original = boards
        for destination in [source.id, archived.id, UUID()]
        {

            XCTAssertThrowsError(
                try CrossBoardListMovement.move(listID: 4, from: source.id, to: destination, collections: &boards))
            XCTAssertEqual(boards, original)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTransferConfirmationsNameDestinationAndDistinguishCopies
    /// @brief      Verify that transfer Confirmations Name Destination And Distinguish Copies
    /// @details    Checks `XCTAssertEqual(TransferConfirmation(title: "Garden path", destination: "Garden /
    ///             Ideas").message, "Moved ‘Garden path’ to Garden / Ideas.")`;
    ///             `XCTAssertEqual(TransferConfirmation(title: "My note", destination: "Journal").message, "Moved ‘My
    ///             note’ to Journal.")`.
    ///
    /// @return     (Void) no return value
    ///
    func testTransferConfirmationsNameDestinationAndDistinguishCopies()
    {

        XCTAssertEqual(
            TransferConfirmation(title: "Garden path", destination: "Garden / Ideas").message,
                            "Moved ‘Garden path’ to Garden / Ideas.")
        XCTAssertEqual(
            TransferConfirmation(title: "My note", destination: "Journal").message,
                            "Moved ‘My note’ to Journal.")
        XCTAssertEqual(
            TransferConfirmation(title: "Ideas", destination: "Home", action: .copied).message,
                            "Copied ‘Ideas’ to Home.")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCrossBoardMoveReservesArchivedIdentitiesAndPreservesFormat
    /// @brief      Verify that cross Board Move Reserves Archived Identities And Preserves Format
    /// @details    Exercises `CrossBoardCardMovement.move`, `original.replacingLocation`, `saved.contains`. Checks
    ///             `XCTAssertNotEqual(moved.id, original.id)`; `XCTAssertEqual(moved, original.replacingLocation(id:
    ///             moved.id, listTitle: "Monday"))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCrossBoardMoveReservesArchivedIdentitiesAndPreservesFormat() throws
    {

        var original = SampleData.lists[0].cards[0]
        original.displayFormat = .picture
        var week = [KanbanList(id: 10, title: "Monday", cards: [])]
        week[0].archivedCards = [original]
        var library = PersonalCollection(title: "Ideas", kind: .list)
        library.lists = [KanbanList(id: 20, title: "Ideas", cards: [original])]
        library.savedCardIDs = [original.id]
        var collections = [library]
        var saved = Set<Int>()
        try CrossBoardCardMovement.move(
            original, from: library.id,
            to: CardMoveDestination(collectionID: nil, listID: 10, title: "Monday", group: "Week"),
            week: &week, collections: &collections, saved: &saved)
        let moved = try XCTUnwrap(week[0].cards.first)
        XCTAssertNotEqual(moved.id, original.id)
        XCTAssertEqual(moved, original.replacingLocation(id: moved.id, listTitle: "Monday"))
        XCTAssertEqual(week[0].archivedCards, [original])
        XCTAssertTrue(saved.contains(moved.id))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCrossBoardMoveRejectsUnavailableDestinationWithoutMutation
    /// @brief      Verify that cross Board Move Rejects Unavailable Destination Without Mutation
    /// @details    Exercises `CrossBoardCardMovement.move`. Checks `XCTAssertEqual(week, before)`;
    ///             `XCTAssertEqual(saved, [card.id])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCrossBoardMoveRejectsUnavailableDestinationWithoutMutation() throws
    {

        let card = SampleData.lists[0].cards[0]
        var week = [KanbanList(id: 10, title: "Monday", cards: [card])]
        let before = week
        var collections = [PersonalCollection]()
        var saved: Set<Int> = [card.id]
        XCTAssertThrowsError(
            try CrossBoardCardMovement.move(
                card, from: nil,
                to: CardMoveDestination(collectionID: UUID(), listID: 20, title: "Missing", group: "Library"),
                week: &week, collections: &collections, saved: &saved))
        XCTAssertEqual(week, before)
        XCTAssertEqual(saved, [card.id])
        XCTAssertTrue(collections.isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testMixedDisplayFormatsPersistMoveRenameAndArchiveWithIndependentDefaults
    /// @brief      Verify that mixed Display Formats Persist Move Rename And Archive With Independent Defaults
    /// @details    Exercises `ItemDisplayFormat.allCases.enumerated().map`, `ItemDisplayFormat.allCases.enumerated`,
    ///             `lists[0].makeItem`. Checks `XCTAssertTrue(editBoardList(1, title: "Ideas", subtitle: "",
    ///             newItemPresentation: .note, in: &lists))`; `XCTAssertEqual(lists[0].cards, cards)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testMixedDisplayFormatsPersistMoveRenameAndArchiveWithIndependentDefaults() async throws
    {

        let suite = "PlenactTests.DisplayFormats.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let photo = KanbanAttachment(fileName: "mixed-display-example.jpg")
        let cards = ItemDisplayFormat.allCases.enumerated().map
        {
            index, format in
            var card = KanbanCard(
                id: index + 1, word: "Example \(format.title)", listTitle: "Ideas",
                attachments: [photo], coverAttachmentID: photo.id, descriptionOverride: "Retained body")
            card.displayFormat = format
            return card
        }

        var lists = [KanbanList(id: 1, title: "Ideas", cards: cards), KanbanList(id: 2, title: "Next", cards: [])]
        XCTAssertTrue(editBoardList(1, title: "Ideas", subtitle: "", newItemPresentation: .note, in: &lists))
        XCTAssertEqual(lists[0].cards, cards)
        XCTAssertEqual(lists[0].makeItem(id: 10, title: "New writing").displayFormat, .note)
        let picture = try XCTUnwrap(cards.first
            {
                $0.displayFormat == .picture
            })
        try BoardCardMovement.move(picture.id, to: 2, before: nil, in: &lists)
        XCTAssertEqual(lists[1].cards.first?.displayFormat, .picture)
        lists[1].archiveCard(id: picture.id)
        var collection = PersonalCollection(title: "Ideas", kind: .list)
        collection.lists = lists
        collection.rename(to: "Plans")
        collection.lists[0].newItemPresentation = .card
        try PersonalCollectionStore.saveChecked([collection], to: defaults)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [collection])
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults) [0].lists[0].newItemPresentation, .card)
        try KanbanBoardPersistence.saveListsChecked(collection.lists, suiteName: suite)
        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restored, collection.lists)
        var archivedList = try XCTUnwrap(restored.last)
        archivedList.restoreArchivedCard(id: picture.id)
        XCTAssertEqual(archivedList.cards.first?.displayFormat, .picture)
        XCTAssertEqual(archivedList.cards.first?.attachments, [photo])
        XCTAssertEqual(CardAttachmentStore.fileNames(in: collection.lists), ["mixed-display-example.jpg"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListCopyAllocatesIDsAndPreservesContentAndInternalLinks
    /// @brief      Verify that list Copy Allocates I Ds And Preserves Content And Internal Links
    /// @details    Exercises `.linkedCard`, `ListCopying.copy`, `copy.allCards.map`. Checks `XCTAssertEqual(copy.id,
    ///             9)`; `XCTAssertEqual(copy.allCards.map(\.id), [21, 22])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListCopyAllocatesIDsAndPreservesContentAndInternalLinks() throws
    {

        var first = KanbanCard(
            id: 1, word: "First", listTitle: "Source", descriptionOverride: "Keep",
            sectionLayout: CardSectionLayout(hidden: [.details]))
        first.checklists = [
            KanbanChecklist(
                title: "Links",
                items: [
                    KanbanChecklistItem(title: "Internal", content: .linkedCard(cardID: 2)),
                    KanbanChecklistItem(title: "External", content: .linkedCard(cardID: 99))
                ])
        ]
        let archived = KanbanCard(id: 2, word: "Archived", listTitle: "Source")
        var source = KanbanList(
            id: 1, title: "Source", cards: [first], archivedCards: [archived], newItemPresentation: .note)
        source.subtitleOverride = "Subtitle"
        let destination = [
            KanbanList(id: 8, title: "Other", cards: [KanbanCard(id: 20, word: "Existing", listTitle: "Other")])
        ]
        let copy = ListCopying.copy(source, into: destination, crossBoard: true)
        XCTAssertEqual(copy.id, 9)
        XCTAssertEqual(copy.allCards.map(\.id), [21, 22])
        XCTAssertEqual(copy.cards.first?.descriptionOverride, "Keep")
        XCTAssertEqual(copy.cards.first?.sectionLayout, first.sectionLayout)
        XCTAssertEqual(copy.newItemPresentation, .note)
        XCTAssertEqual(copy.subtitleOverride, "Subtitle")
        XCTAssertEqual(copy.cards[0].checklists[0].items[0].content, .linkedCard(cardID: 22))
        XCTAssertEqual(copy.cards[0].checklists[0].items[1].content, .standard)
        XCTAssertEqual(source.cards[0].checklists[0].items[0].content, .linkedCard(cardID: 2))
        XCTAssertEqual(try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(copy)), copy)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPermanentListDeletionRemovesNestedArchivesAndPreservesRemainingOrder()
    /// @brief      Remove complete list content and its bookmarks from either partition
    /// @details    Checks empty-board encoding and leaves unrelated cards/bookmarks unchanged
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     JSON encoding or decoding failures
    ///
    func testPermanentListDeletionRemovesNestedArchivesAndPreservesRemainingOrder() throws
    {


        let first = KanbanList(
            id: 1, title: "First",
            cards: [ /* First value in the comparison */
                KanbanCard(id: 10, word: "Active", listTitle: "First", checklists: [])
            ],
            archivedCards: [
                KanbanCard(id: 11, word: "Archived", listTitle: "First", checklists: [])
            ])
        let second = KanbanList(
            id: 2, title: "Keep",
            cards: [ /* Second value in the comparison */
                KanbanCard(id: 12, word: "Keep", listTitle: "Keep", checklists: [])
            ])
        var snapshot = [first, second]          /* Persisted snapshot under verification */
        var bookmarks: Set<Int> = [10, 11, 12]  /* Saved-card bookmarks before deletion  */

        BoardContentDeletion.list(1, in: &snapshot, savedCardIDs: &bookmarks)

        XCTAssertEqual(snapshot, [second])
        XCTAssertEqual(bookmarks, [12])

        BoardContentDeletion.list(2, in: &snapshot, savedCardIDs: &bookmarks)

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertTrue(bookmarks.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(snapshot)), [])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListReorderingMovesRestoredMondayToFirstWithoutChangingContent()
    /// @brief      Move an existing list without replacing its records
    /// @details    Checks moves to both ends and JSON round-trip equality of the resulting order
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Board encoding or decoding errors
    ///
    func testListReorderingMovesRestoredMondayToFirstWithoutChangingContent() throws
    {


        var lists = SampleData.lists      /* Board lists under verification        */
        let monday = lists.removeFirst()  /* Restored Monday List after reordering */

        lists.append(monday)

        XCTAssertTrue(BoardListReordering.move(monday.id, to: 0, in: &lists))
        XCTAssertEqual(lists, SampleData.lists)
        XCTAssertTrue(BoardListReordering.move(monday.id, to: lists.count - 1, in: &lists))
        XCTAssertEqual(lists.last, monday)

        let restored = try JSONDecoder().decode(
            [KanbanList].self, from: JSONEncoder().encode(lists)) /* Restored value under verification */

        XCTAssertEqual(restored, lists)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListReorderingRejectsMissingAndOutOfBoundsMoves()
    /// @brief      Leave list order unchanged for invalid or redundant moves
    /// @details    Exercises missing IDs, both bounds, and the current position
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testListReorderingRejectsMissingAndOutOfBoundsMoves()
    {


        var lists = SampleData.lists  /* Board lists under verification              */
        let original = lists          /* Pre-operation value for preservation checks */

        XCTAssertFalse(BoardListReordering.move(999, to: 0, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: -1, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: lists.count, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: 0, in: &lists))
        XCTAssertEqual(lists, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardReorderingClampsDestinationsAndRejectsMissingOrNoOpMoves()
    /// @brief      Keep card reorder behavior bounded and unchanged for invalid requests
    /// @details    Verifies clamped insertion at the first position, missing identity rejection,
    ///             and unchanged-order rejection without losing any records
    ///
    /// @return     (Void) records assertion failures for invalid reorder requests
    ///
    func testCardReorderingClampsDestinationsAndRejectsMissingOrNoOpMoves()
    {


        let cardsBeforeMove = SampleData.lists[0].cards  /* Original complete card sequence */
        var cards = cardsBeforeMove                      /* Mutable card-order copy         */

        guard let lastCardID = cards.last?.id else
        {  /* Stable identity moved to the first position */


            XCTFail("Expected a sample card for reorder coverage")
            return
        }


        XCTAssertTrue(BoardCardReordering.move(lastCardID, to: -10, in: &cards))
        XCTAssertEqual(cards.first?.id, lastCardID)

        let reorderedCards = cards /* Expected unchanged value for rejected operations */

        XCTAssertFalse(BoardCardReordering.move(999_999, to: 0, in: &cards))
        XCTAssertFalse(BoardCardReordering.move(lastCardID, to: 0, in: &cards))
        XCTAssertEqual(cards, reorderedCards)
        XCTAssertNotEqual(cards, cardsBeforeMove)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMovementPreservesCompleteRecordAndRetainedArchives()
    /// @brief      Transfer the complete card while keeping bookmarks and archived records intact
    /// @details    Checks insertion and a Codable round trip with synthetic media and dates
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    func testCardMovementPreservesCompleteRecordAndRetainedArchives() throws
    {


        var card = try XCTUnwrap(
            SampleData.lists[0].cards.first
            {
                !$0.isSectionDivider
            }) /* Card value under verification */

        card.attachments = [KanbanAttachment(fileName: "synthetic-drag.jpg", mediaKind: .photo)]
        try card.useLibraryCover(.music)
        card.comments = [KanbanComment(author: "Synthetic", body: "Keep this note")]
        card.members = [.manual("Example")]
        card.labelIDs = ["synthetic-label"]
        card.startDate = Date(timeIntervalSince1970: 1234)
        card.dueDate = Date(timeIntervalSince1970: 5678)
        card.descriptionOverride = "Retain every field"

        let retained = KanbanCard(
            id: 901, word: "Archived", listTitle: "Source")  /* Archived Card retained by its source List */
        var lists = [                                        /* Board lists under verification            */
            KanbanList(id: 1, title: "Source", cards: [card], archivedCards: [retained]),
            KanbanList(
                id: 2, title: "Destination",
                cards: [
                    KanbanCard(id: 902, word: "First", listTitle: "Destination"),
                    KanbanCard(id: 903, word: "Last", listTitle: "Destination")
                ])
        ]
        let savedIDs: Set<Int> = [card.id] /* Saved Card IDs preserved during movement */

        XCTAssertTrue(try BoardCardMovement.move(card.id, to: 2, before: 903, in: &lists))

        var expected = card /* Expected result for comparison */

        expected.listTitle = "Destination"

        XCTAssertEqual(lists[1].cards, [lists[1].cards[0], expected, lists[1].cards[2]])
        XCTAssertEqual(lists[1].cards.map(\.id), [902, card.id, 903])
        XCTAssertTrue(lists[0].cards.isEmpty)
        XCTAssertEqual(lists[0].archivedCards, [retained])
        XCTAssertEqual(lists.flatMap(\.cards).filter
            {
                savedIDs.contains($0.id)
            }, [expected])
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists)), lists)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMovementSupportsEmptyListsAndSameListInsertionBoundaries()
    /// @brief      Verify empty-list transfers and same-list insertion boundaries
    /// @details    Checks moves before another card, appends, self/current-position no-ops, and
    ///             destination list-title updates using synthetic records.
    ///
    /// @return     (Void) records assertion failures for incorrect movement or no-op results
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    func testCardMovementSupportsEmptyListsAndSameListInsertionBoundaries() throws
    {


        let cards = (1 ... 4).map
        {

            KanbanCard(id: $0, word: "Card \($0)", listTitle: "A")
        }  /* Card records under inspection  */

        var lists = [
            KanbanList(id: 10, title: "A", cards: cards), /* Board lists under verification */
            KanbanList(id: 20, title: "Empty", cards: [])
        ]

        XCTAssertTrue(try BoardCardMovement.move(1, to: 10, before: 4, in: &lists))
        XCTAssertEqual(lists[0].cards.map(\.id), [2, 3, 1, 4])
        XCTAssertTrue(try BoardCardMovement.move(4, to: 10, before: 2, in: &lists))
        XCTAssertEqual(lists[0].cards.map(\.id), [4, 2, 3, 1])
        XCTAssertFalse(try BoardCardMovement.move(2, to: 10, before: 3, in: &lists))
        XCTAssertFalse(try BoardCardMovement.move(2, to: 10, before: 2, in: &lists))
        XCTAssertTrue(try BoardCardMovement.move(2, to: 10, in: &lists))
        XCTAssertEqual(lists[0].cards.map(\.id), [4, 3, 1, 2])
        XCTAssertTrue(try BoardCardMovement.move(2, to: 20, in: &lists))
        XCTAssertEqual(lists[1].cards.map(\.id), [2])
        XCTAssertEqual(lists[1].cards[0].listTitle, "Empty")
        XCTAssertFalse(try BoardCardMovement.move(2, to: 20, in: &lists))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMovementRejectsStaleArchivedAndAmbiguousSourcesAtomically()
    /// @brief      Verify invalid card movements leave every list unchanged
    /// @details    Exercises missing identities, stale boundaries, archived content, and
    ///             duplicate source cards; compares the complete snapshot after each rejected
    ///             operation.
    ///
    /// @return     (Void) records assertion failures for invalid moves or partial mutations
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    func testCardMovementRejectsStaleArchivedAndAmbiguousSourcesAtomically() throws
    {


        let card = KanbanCard(id: 1, word: "Card", listTitle: "A")                  /* Card value under verification */
        let divider = KanbanCard(id: 2, word: "", listTitle: "A", isDivider: true)  /* Section-divider fixture       */
        let archive = KanbanCard(id: 3, word: "Retained", listTitle: "A")           /* Archived-card snapshot        */
        var lists = [
            KanbanList(
                id: 10, title: "A", cards: [card, divider], archivedCards: [archive]), /* Board lists under verification */
            KanbanList(id: 20, title: "B", cards: [])
        ]
        let original = lists /* Pre-operation value for preservation checks */

        for (id, destination, before) in [(999, 20, nil), (1, 999, nil), (1, 20, 999), (3, 20, nil)]
        as [(Int, Int, Int?)]
        {


            XCTAssertThrowsError(try BoardCardMovement.move(id, to: destination, before: before, in: &lists))
            XCTAssertEqual(lists, original)
        }

        lists[1].isArchived = true
        let archivedDestination = lists /* List receiving the archived Card */

        XCTAssertThrowsError(try BoardCardMovement.move(1, to: 20, in: &lists))
        XCTAssertEqual(lists, archivedDestination)

        lists = original
        lists[0].isArchived = true
        let archivedSource = lists /* List originally containing the Card */

        XCTAssertThrowsError(try BoardCardMovement.move(1, to: 20, in: &lists))
        XCTAssertEqual(lists, archivedSource)

        lists = original
        lists[1].cards = [card]
        let duplicate = lists /* Duplicate Card fixture */

        XCTAssertThrowsError(try BoardCardMovement.move(1, to: 20, in: &lists))
        XCTAssertEqual(lists, duplicate)

        lists = original
        lists[0].cards.append(card)
        let sameListDuplicate = lists /* Same-List duplicate fixture */

        XCTAssertThrowsError(try BoardCardMovement.move(1, to: 20, in: &lists))
        XCTAssertEqual(lists, sameListDuplicate)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMovementPersistsInWeekAndPersonalBoardWithoutChangingOtherBoards()
    /// @brief      Verify Week and personal Board movement round trips independently
    /// @details    Uses an isolated preference suite for background Week saving and personal
    ///             collection persistence; checks bookmarks and an unchanged separate Board, then
    ///             removes the fixture domain.
    ///
    /// @return     (Void) records assertion failures for changed records or persistence isolation
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    @MainActor
    func testCardMovementPersistsInWeekAndPersonalBoardWithoutChangingOtherBoards() async throws
    {


        let suite = "Plenact.CardMovementTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        var lists = SampleData.lists /* Board lists under verification */
        let card = try XCTUnwrap(lists[0].cards.first
            {
                !$0.isSectionDivider
            })                         /* Card value under verification */
        let destination = lists[1].id  /* Target location for the move  */

        try BoardCardMovement.move(card.id, to: destination, in: &lists)
        KanbanBoardPersistence.enqueueSave(lists, suiteName: suite)

        let reloaded = await KanbanBoardPersistence.loadListsInBackground(
            suiteName: suite) /* Document loaded after reopening storage */

        XCTAssertEqual(reloaded, lists)

        var personal = PersonalCollection(
            title: "Synthetic Board", kind: .board) /* Personal List fixture filtered from demo Boards */

        personal.lists = SampleData.lists
        personal.savedCardIDs = [card.id]

        var independent = PersonalCollection(
            title: "Separate Board", kind: .board) /* Separate personal Board retained by movement */

        independent.lists = personal.lists
        try BoardCardMovement.move(card.id, to: destination, in: &personal.lists)

        XCTAssertEqual(independent.lists, SampleData.lists)

        let decoded = try JSONDecoder().decode(
            PersonalCollection.self, from: JSONEncoder().encode(personal)) /* Decoded personal collection after persistence */

        XCTAssertEqual(decoded.lists, lists)

        try PersonalCollectionStore.saveChecked([personal, independent], to: defaults)

        let restored = PersonalCollectionStore.load(from: defaults) /* Restored value under verification */

        XCTAssertEqual(restored.map(\.lists), [personal.lists, independent.lists])
        XCTAssertEqual(restored.first?.savedCardIDs, [card.id])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundBoardLoadReportsCorruptionWithoutRemovingData()
    /// @brief      Report unreadable Week data while retaining its original bytes at load time
    /// @details    Confirms the current sample fallback; does not test protection against
    ///             subsequent saves
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap failures
    ///
    @MainActor
    func testBackgroundBoardLoadReportsCorruptionWithoutRemovingData() async throws
    {


        let suite = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }


        let invalidData = Data("not JSON".utf8) /* Malformed response payload */

        defaults.set(invalidData, forKey: "Plenact.Board.v1")

        let restored = await KanbanBoardPersistence.loadListsInBackground(
            suiteName: suite) /* Restored value under verification */

        XCTAssertEqual(restored, SampleData.lists)
        XCTAssertNotNil(DatabaseActivity.shared.errorMessage)
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), invalidData)
    }

}
