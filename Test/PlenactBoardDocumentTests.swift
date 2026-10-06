// -------------------------------------------------------------------------------------------------
// @file       PlenactBoardDocumentTests.swift
// @brief      Board contracts, local persistence, and presentation regression tests
// @details    Covers versioned shared-demo documents, archive/restore compatibility, isolated
//             preference stores, canonical search/selection helpers, background-save failures,
//             and hosted SwiftUI sizing/re-layout. API activity uses an in-process URLProtocol
//
// @notes      Synthetic fixtures do not access the live demo database. Corruption tests verify
//             load-time byte retention, not protection against a later write to fallback content
//
// -------------------------------------------------------------------------------------------------
import XCTest
import SwiftUI
@testable import Plenact


///
/// Verifies the Plenact-specific Board snapshot contract
///
/// @section    Purpose
///     Protect document validation, retained local content, and presentation-only behavior
///
final class PlenactBoardDocumentTests: XCTestCase {

    ///
    /// @fcn        PlenactBoardDocumentTests.testPermanentCardDeletionIncludesArchivesAndRemovesOnlyOwningBookmarks
    /// @brief      Remove retained card records without affecting other Board-local identities
    /// @details    Exercises an archived list and keeps an independent collection with an equal card ID
    ///
    func testPermanentCardDeletionIncludesArchivesAndRemovesOnlyOwningBookmarks() {
        let card = KanbanCard(id: 12, word: "Synthetic", listTitle: "Retained", checklists: [])
        var archivedList = KanbanList(id: 3, title: "Retained", cards: [], archivedCards: [card])
        archivedList.isArchived = true
        var snapshot = [archivedList, KanbanList(id: 4, title: "Other", cards: [
            KanbanCard(id: 13, word: "Keep", listTitle: "Other", checklists: [])
        ])]
        let independent = [archivedList]
        var bookmarks: Set<Int> = [12, 13]
        BoardContentDeletion.card(12, in: &snapshot, savedCardIDs: &bookmarks)
        XCTAssertTrue(snapshot[0].allCards.isEmpty)
        XCTAssertEqual(snapshot[1].cards.map(\.id), [13])
        XCTAssertEqual(bookmarks, [13])
        XCTAssertEqual(independent[0].archivedCards, [card])
        BoardContentDeletion.card(12, in: &snapshot, savedCardIDs: &bookmarks)
        XCTAssertEqual(bookmarks, [13])
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testPermanentListDeletionRemovesNestedArchivesAndPreservesRemainingOrder
    /// @brief      Remove complete list content and its bookmarks from either partition
    /// @details    Checks empty-board encoding and leaves unrelated cards/bookmarks unchanged
    /// @throws     JSON encoding or decoding failures
    ///
    func testPermanentListDeletionRemovesNestedArchivesAndPreservesRemainingOrder() throws {
        let first = KanbanList(id: 1, title: "First", cards: [
            KanbanCard(id: 10, word: "Active", listTitle: "First", checklists: [])
        ], archivedCards: [
            KanbanCard(id: 11, word: "Archived", listTitle: "First", checklists: [])
        ])
        let second = KanbanList(id: 2, title: "Keep", cards: [
            KanbanCard(id: 12, word: "Keep", listTitle: "Keep", checklists: [])
        ])
        var snapshot = [first, second]
        var bookmarks: Set<Int> = [10, 11, 12]
        BoardContentDeletion.list(1, in: &snapshot, savedCardIDs: &bookmarks)
        XCTAssertEqual(snapshot, [second])
        XCTAssertEqual(bookmarks, [12])
        BoardContentDeletion.list(2, in: &snapshot, savedCardIDs: &bookmarks)
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertTrue(bookmarks.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(snapshot)), [])
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testDeletionMediaCleanupPreservesRetainedCopiesAndUnrelatedFiles
    /// @brief      Remove only explicit deletion candidates with no remaining references
    /// @details    Creates synthetic media files; protects archive/undo references and an unrelated file
    /// @throws     File creation or cleanup failures
    ///
    func testDeletionMediaCleanupPreservesRetainedCopiesAndUnrelatedFiles() throws {
        let candidate = try CardAttachmentStore.saveMedia(Data([1, 2, 3]), kind: .photo, fileExtension: "jpg")
        let unrelated = try CardAttachmentStore.saveMedia(Data([4, 5, 6]), kind: .photo, fileExtension: "jpg")
        let candidateName = try XCTUnwrap(candidate.fileName)
        let unrelatedName = try XCTUnwrap(unrelated.fileName)
        defer {
            try? CardAttachmentStore.removeDeletedFiles([candidateName, unrelatedName], keeping: [])
        }
        var card = KanbanCard(id: 1, word: "Retained", listTitle: "Archive", checklists: [])
        card.attachments = [candidate]
        var archived = KanbanList(id: 1, title: "Archive", cards: [], archivedCards: [card])
        archived.isArchived = true
        let retainedNames = CardAttachmentStore.fileNames(in: [archived])
        try CardAttachmentStore.removeDeletedFiles([candidateName], keeping: retainedNames)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(CardAttachmentStore.fileURL(for: candidate)).path))
        try CardAttachmentStore.removeDeletedFiles([candidateName], keeping: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(CardAttachmentStore.fileURL(for: candidate)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(CardAttachmentStore.fileURL(for: unrelated)).path))
        for invalidName in ["", ".", "..", "../outside.jpg"] {
            XCTAssertThrowsError(try CardAttachmentStore.removeDeletedFiles([invalidName], keeping: []))
        }
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalListArchiveSaveFailureLeavesPriorSnapshotUntouched
    /// @brief      Verify personal lists archive through the same save-first boundary as Boards
    /// @details    Retains nested cards/bookmarks, then forces encoding failure with an infinite date
    /// @throws     Preference-suite setup or checked-save failures
    ///
    func testPersonalListArchiveSaveFailureLeavesPriorSnapshotUntouched() throws {
        let suite = "Plenact.ListLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = PersonalListExample.shopping.makeCollection(existingTitles: [])
        try PersonalCollectionStore.saveChecked([original], to: defaults)
        let archived = try PersonalCollectionStore.archiveCollection(id: original.id, in: [original], to: defaults)
        XCTAssertFalse(archived[0].isActive)
        XCTAssertEqual(archived[0].lists, original.lists)
        var invalid = original
        invalid.lists[0].cards[0].dueDate = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertThrowsError(try PersonalCollectionStore.archiveCollection(id: invalid.id, in: [invalid], to: defaults))
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), archived)
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekSaveCompletionRunsOnlyAfterSuccessfulWrite
    /// @brief      Gate deletion cleanup on successful ordered persistence
    /// @details    Checks valid completion and rejects completion when JSON encoding fails
    /// @throws     Fixture setup failures
    ///
    @MainActor
    func testWeekSaveCompletionRunsOnlyAfterSuccessfulWrite() async throws {
        let suite = "Plenact.DeletionCompletionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }
        let success = expectation(description: "Completion follows write")
        KanbanBoardPersistence.enqueueSave([], suiteName: suite, onSuccess: {
            XCTAssertNotNil(defaults.data(forKey: "Plenact.Board.v1"))
            success.fulfill()
        })
        await fulfillment(of: [success], timeout: 2)
        var invalid = KanbanCard(id: 1, word: "Invalid", listTitle: "List", checklists: [])
        invalid.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let rejected = expectation(description: "No cleanup after failed write")
        rejected.isInverted = true
        KanbanBoardPersistence.enqueueSave(
            [KanbanList(id: 1, title: "List", cards: [invalid])], suiteName: suite,
            onSuccess: { rejected.fulfill() }
        )
        await fulfillment(of: [rejected], timeout: 0.2)
        XCTAssertNotNil(DatabaseActivity.shared.errorMessage)
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: XCTUnwrap(defaults.data(forKey: "Plenact.Board.v1"))), [])
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testCheckedWeekDeletionWaitsForEarlierWritesAndPreservesDiskOnFailure
    /// @brief      Verify a checked destructive save cannot be overwritten by older queued edits
    /// @details    Uses isolated preferences and rejects an unencodable remaining card without changing disk
    /// @throws     Preference-suite setup, encoding, or decoding errors
    ///
    @MainActor
    func testCheckedWeekDeletionWaitsForEarlierWritesAndPreservesDiskOnFailure() throws {
        let suite = "Plenact.CheckedDeletionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prior = [KanbanList(id: 1, title: "Earlier edit", cards: [
            KanbanCard(id: 1, word: "Synthetic", listTitle: "Earlier edit", checklists: [])
        ])]
        KanbanBoardPersistence.enqueueSave(prior, suiteName: suite)
        try KanbanBoardPersistence.saveListsChecked([], suiteName: suite)
        let saved = try XCTUnwrap(defaults.data(forKey: "Plenact.Board.v1"))
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: saved), [])

        var invalid = prior
        invalid[0].cards[0].dueDate = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertThrowsError(try KanbanBoardPersistence.saveListsChecked(invalid, suiteName: suite))
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), saved)
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalListExamplesContainSafeIndependentCards
    /// @brief      Verify the six example lists meet their content and compatibility contract
    /// @details    Checks card limits, unique local IDs, empty optional activity/media fields,
    ///             correct list ownership, and Codable round trips
    /// @throws     Collection encoding or decoding failures
    ///
    func testPersonalListExamplesContainSafeIndependentCards() throws {

        XCTAssertEqual(PersonalListExample.allCases.map(\.rawValue), [
            "On the Table", "In the Queue", "Scheduled", "Shopping", "Up for Brew", "Misc."
        ])

        for example in PersonalListExample.allCases {

            let collection = example.makeCollection(existingTitles: [])

            XCTAssertEqual(collection.kind, .list)
            XCTAssertEqual(collection.lists.count, 1)
            XCTAssertTrue(collection.isActive)
            XCTAssertTrue(collection.savedCardIDs.isEmpty)
            XCTAssertGreaterThanOrEqual(collection.cardCount, 5)
            XCTAssertLessThanOrEqual(collection.cardCount, 20)

            let cards = collection.lists[0].cards

            XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
            XCTAssertEqual(Set(cards.map(\.word)).count, cards.count)

            for card in cards {
                XCTAssertEqual(card.listTitle, collection.title)
                XCTAssertFalse(card.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(card.descriptionOverride?.isEmpty ?? true)
                XCTAssertEqual(card.subtitleOverride, "Example")
                XCTAssertFalse(card.isTitleChecked)
                XCTAssertFalse(card.isSectionDivider)
                XCTAssertNil(card.startDate)
                XCTAssertNil(card.dueDate)
                XCTAssertTrue(card.checklists.isEmpty)
                XCTAssertTrue(card.comments.isEmpty)
                XCTAssertTrue(card.members.isEmpty)
                XCTAssertTrue(card.labelIDs.isEmpty)
                XCTAssertTrue(card.attachments?.isEmpty ?? true)
            }
            let restored = try JSONDecoder().decode(
                PersonalCollection.self, from: JSONEncoder().encode(collection)
            )
            XCTAssertEqual(restored, collection)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleDraftsDoNotWriteOrReplaceExistingCollections
    /// @brief      Preserve stored Week and personal work while generating or discarding examples
    /// @details    Uses isolated preferences, fresh draft identities, collision-safe naming, and an
    ///             explicit append/save; checks existing collections and Week bytes remain unchanged
    /// @throws     Fixture setup, checked-save, or JSON encoding failures
    ///
    func testExampleDraftsDoNotWriteOrReplaceExistingCollections() throws {

        let suite = "Plenact.PersonalExampleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))

        defer { defaults.removePersistentDomain(forName: suite) }

        let week = try JSONEncoder().encode(SampleData.lists)

        defaults.set(week, forKey: "Plenact.Board.v1")

        var retained = PersonalCollection(title: "Shopping", kind: .list)

        retained.isArchived = true
        retained.lists[0].cards = [KanbanCard(id: 99, word: "Existing", listTitle: "Shopping", checklists: [])]
        retained.savedCardIDs = [99]

        try PersonalCollectionStore.saveChecked([retained], to: defaults)
        
        let originalBytes = defaults.data(forKey: "Plenact.PersonalCollections.v1")
        let first = PersonalListExample.shopping.makeCollection(existingTitles: [retained.title])
        let second = PersonalListExample.shopping.makeCollection(existingTitles: [retained.title, first.title])
        
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.title, "Shopping (2)")
        XCTAssertEqual(second.title, "Shopping (3)")
        XCTAssertEqual(defaults.data(forKey: "Plenact.PersonalCollections.v1"), originalBytes)
        
        var renamed = first
        
        renamed.rename(to: "My shopping")
        
        XCTAssertTrue(renamed.lists[0].cards.allSatisfy { $0.listTitle == "My shopping" })
        XCTAssertEqual(renamed.lists[0].cards.map(\.id), first.lists[0].cards.map(\.id))
        
        try PersonalCollectionStore.saveChecked([retained, renamed], to: defaults)
        
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [retained, renamed])
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), week)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryRowsFitLongTitlesAndAccessibilityText
    /// @brief      Verify Library entries fit their content across viewport and text sizes
    /// @details    Hosts synthetic collection rows at portrait/landscape widths; accessibility
    ///             text must grow vertically instead of retaining a fixed row height
    ///
    @MainActor
    func testLibraryRowsFitLongTitlesAndAccessibilityText() {

        for width: CGFloat in [280, 700] {

            let row = LibraryCollectionRow(
                title: "Ideas and plans for the coming season",
                subtitle: "Board · 3 lists", icon: "square.stack.3d.up", color: .blue, count: 12
            )

            let standard = UIHostingController(rootView: row.environment(\.dynamicTypeSize, .large))
                .sizeThatFits(in: CGSize(width: width, height: 10_000))

            let accessible = UIHostingController(rootView: row.environment(\.dynamicTypeSize, .accessibility5))
                .sizeThatFits(in: CGSize(width: width, height: 10_000))

            XCTAssertEqual(standard.width, width, accuracy: 1)
            XCTAssertEqual(accessible.width, width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(standard.height, 68)
            XCTAssertGreaterThan(accessible.height, standard.height)
            XCTAssertLessThan(accessible.height, 1_000)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardPresentationWidthsInPortraitLandscapeAndAccessibility
    /// @brief      Verify preset widths and invalid-geometry handling
    /// @details    Checks exact caps, landscape capacity, narrow viewports, and accessibility sizing
    ///
    func testBoardPresentationWidthsInPortraitLandscapeAndAccessibility() {
        XCTAssertEqual(BoardPresentation.standard.columnWidth(viewportWidth: 393, accessibilitySize: false), 360)
        XCTAssertEqual(BoardPresentation.overview.columnWidth(viewportWidth: 393, accessibilitySize: false), 240)
        XCTAssertEqual(BoardPresentation.standard.columnWidth(viewportWidth: 852, accessibilitySize: false), 360)
        XCTAssertEqual(BoardPresentation.overview.columnWidth(viewportWidth: 852, accessibilitySize: false), 240)
        XCTAssertLessThanOrEqual(2 * 360 + 12 + 28, 852)
        XCTAssertLessThanOrEqual(3 * 240 + 24 + 28, 852)
        for preset in BoardPresentation.allCases {
            XCTAssertEqual(preset.columnWidth(viewportWidth: 320, accessibilitySize: true), 292)
            XCTAssertEqual(preset.columnWidth(viewportWidth: 200, accessibilitySize: false), 172)
            for width: CGFloat in [0, 28, -1, .nan, .infinity] {
                XCTAssertEqual(preset.columnWidth(viewportWidth: width, accessibilitySize: false), 1)
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardPresentationPreferenceIsLocalAndLeavesBoardSnapshotsUntouched
    /// @brief      Persist presentation independently of Board snapshots
    /// @details    Reopens an isolated AppStorage preference and compares untouched Week/collection bytes
    /// @throws     Preference-suite unwrap or fixture encoding failures
    ///
    @MainActor
    func testBoardPresentationPreferenceIsLocalAndLeavesBoardSnapshotsUntouched() throws {
        let suite = "Plenact.BoardPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        
        defer { defaults.removePersistentDomain(forName: suite) }
        
        let week = try JSONEncoder().encode(SampleData.lists)
        var board = PersonalCollection(title: "Synthetic project", kind: .board)
        board.lists = SampleData.lists
        board.savedCardIDs = [0]
        board.isArchived = true
        
        let collections = try JSONEncoder().encode([board])
        defaults.set(week, forKey: "Plenact.Board.v1")
        defaults.set(collections, forKey: "Plenact.PersonalCollections.v1")
        
        let preference = AppStorage(wrappedValue: BoardPresentation.standard, BoardPresentation.storageKey, store: defaults)
        XCTAssertEqual(preference.wrappedValue, .standard)
        preference.wrappedValue = .overview
        XCTAssertEqual(defaults.string(forKey: BoardPresentation.storageKey), "overview")
        
        let reopened = AppStorage(wrappedValue: BoardPresentation.standard, BoardPresentation.storageKey, store: defaults)
        XCTAssertEqual(reopened.wrappedValue, .overview)
        preference.wrappedValue = .standard
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), week)
        XCTAssertEqual(defaults.data(forKey: "Plenact.PersonalCollections.v1"), collections)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRenderedCardsFitContentWithoutQuarterScreenHeights
    /// @brief      Measure compact summaries and accessibility growth
    /// @details    Hosts both presets and rejects layout callbacks that would mutate the card
    ///
    @MainActor
    func testRenderedCardsFitContentWithoutQuarterScreenHeights() {

        let card = KanbanCard(id: 100, word: "Prepare a plan", listTitle: "Synthetic list")

        ///
        /// @fcn        measuredHeight(_:size:width:)
        /// @brief      Measure a synthetic card at the requested preset and text size
        /// @details    Proposes ample height so the hosting controller reports content-fitting height
        /// @param[in]  preset  Card presentation preset
        /// @param[in]  size    Dynamic Type environment value
        /// @param[in]  width   Proposed card width in points
        /// @return     (CGFloat) hosted card height in points
        ///
        func measuredHeight(_ preset: BoardPresentation, size: DynamicTypeSize, width: CGFloat) -> CGFloat {
            let view = KanbanCardView(
                card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                presentation: preset, labelLibrary: .starter,
                onUpdateCard: { _ in XCTFail("Layout must not edit a card") },
                onDeleteCard: { XCTFail("Layout must not delete a card") },
                onArchiveCard: { XCTFail("Layout must not archive a card") },
                onToggle: { XCTFail("Layout must not toggle a card") }
            )
            .environment(\.dynamicTypeSize, size)
            let controller = UIHostingController(rootView: view)
            return controller.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        }


        let standard = measuredHeight(.standard, size: .large, width: 360)
        let overview = measuredHeight(.overview, size: .large, width: 240)
        XCTAssertGreaterThanOrEqual(standard, 112)
        XCTAssertLessThan(standard, 160)
        XCTAssertGreaterThanOrEqual(overview, 80)
        XCTAssertLessThan(overview, standard)
        XCTAssertGreaterThan(measuredHeight(.overview, size: .accessibility5, width: 292), overview)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardSummaryDoesNotStretchToFillListHeight
    /// @brief      Reject vertical expansion under a taller layout proposal
    /// @details    Compares 300- and 900-point proposals for the same synthetic card in both presets
    ///
    @MainActor
    func testCardSummaryDoesNotStretchToFillListHeight() {

        let card = KanbanCard(id: 101, word: "Review the week ahead", listTitle: "Synthetic list")
        for preset in BoardPresentation.allCases {
            
            let controller = UIHostingController(rootView: KanbanCardView(
                card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                presentation: preset, labelLibrary: .starter,
                onUpdateCard: { _ in XCTFail("Layout must not edit content") },
                onDeleteCard: {}, onArchiveCard: {}, onToggle: {}
            ).environment(\.dynamicTypeSize, .large))
            
            let width: CGFloat = preset == .standard ? 360 : 240
            let shortProposal = controller.sizeThatFits(in: CGSize(width: width, height: 300))
            let tallProposal = controller.sizeThatFits(in: CGSize(width: width, height: 900))
            
            XCTAssertEqual(shortProposal.height, tallProposal.height, accuracy: 1)
            XCTAssertLessThan(tallProposal.height, preset == .standard ? 170 : 130)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNavigationLinkedCardRowsRemainCompactInAList
    /// @brief      Verify card sizing inside native navigation-linked List rows
    /// @details    Attaches a hosting window to the current scene and restores the prior key window
    /// @throws     Scene/row unwrap failures or cancellation of the layout delay
    ///
    @MainActor
    func testNavigationLinkedCardRowsRemainCompactInAList() async throws {
        let card = KanbanCard(id: 102, word: "Review the week ahead", listTitle: "Synthetic list")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }


        ///
        /// @fcn        collectionView(in:)
        /// @brief      Locate the List's backing collection view in the hosted hierarchy
        /// @details    Recursively searches subviews and returns the first match
        /// @param[in]  view  Root of the UIKit subtree to inspect
        /// @return     (UICollectionView?) first matching view, or nil
        ///
        func collectionView(in view: UIView) -> UICollectionView? {
            if let collection = view as? UICollectionView { return collection }
            return view.subviews.compactMap { collectionView(in: $0) }.first
        }
        for preset in BoardPresentation.allCases {
            let view = NavigationStack {
                List {
                    NavigationLink {
                        Text("Synthetic card detail")
                    } label: {
                        KanbanCardView(
                            card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                            presentation: preset, labelLibrary: .starter,
                            onUpdateCard: { _ in XCTFail("Rendering must not edit content") },
                            onDeleteCard: {}, onArchiveCard: {}, onToggle: {}
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .environment(\.dynamicTypeSize, .large)
            let controller = UIHostingController(rootView: view)
            window.rootViewController = controller
            window.frame = CGRect(x: 0, y: 0, width: preset == .standard ? 360 : 240, height: 700)
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let collection = try XCTUnwrap(collectionView(in: controller.view))
            let row = try XCTUnwrap(collection.visibleCells.first)
            XCTAssertLessThan(row.bounds.height, preset == .standard ? 210 : 180)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardRelayoutAndPresetChangesDoNotMutateRetainedContent
    /// @brief      Retain the requested list and content through Board re-layout
    /// @details    Varies viewport/preset and compares active lists, archives, bookmarks, and visible ID
    /// @throws     Fixture setup failures or cancellation of the layout delay
    ///
    @MainActor
    func testBoardRelayoutAndPresetChangesDoNotMutateRetainedContent() async throws {
        let suite = "Plenact.BoardRelayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var lists = SampleData.lists
        lists[0].archiveCard(id: lists[0].cards[0].id)
        var archived = SampleData.lists[1]
        archived.isArchived = true
        var archives = [archived]
        var saved: Set<Int> = [lists[0].archivedCards[0].id]
        let focusedListID = lists[3].id
        var targetList: Int? = focusedListID
        var targetCard: Int?
        var visibleListID: Int?
        let revealedTarget = expectation(description: "Reveal the requested middle list")
        var didRevealTarget = false
        let originalLists = lists
        let originalArchives = archives
        let originalSaved = saved
        let view = ContentView(
            lists: Binding(get: { lists }, set: { lists = $0 }),
            archivedLists: Binding(get: { archives }, set: { archives = $0 }),
            boardTargetListID: Binding(get: { targetList }, set: { targetList = $0 }),
            boardTargetCardID: Binding(get: { targetCard }, set: { targetCard = $0 }),
            savedCardIDs: Binding(get: { saved }, set: { saved = $0 }),
            onListViewed: { listID in
                visibleListID = listID
                if listID == focusedListID && !didRevealTarget {
                    didRevealTarget = true
                    revealedTarget.fulfill()
                }
            },
            boardTitle: "Synthetic board",
            onListsChanged: { _ in XCTFail("Presentation must not request a Board save") },
            retainedAttachmentLists: { [] }
        )
        .defaultAppStorage(defaults)
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await fulfillment(of: [revealedTarget], timeout: 2)
        for preset in BoardPresentation.allCases {
            defaults.set(preset.rawValue, forKey: BoardPresentation.storageKey)
            for size in [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393)] {
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
    /// @fcn        PlenactBoardDocumentTests.testListReorderingMovesRestoredMondayToFirstWithoutChangingContent
    /// @brief      Move an existing list without replacing its records
    /// @details    Checks moves to both ends and JSON round-trip equality of the resulting order
    /// @throws     Board encoding or decoding errors
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testListReorderingRejectsMissingAndOutOfBoundsMoves
    /// @brief      Leave list order unchanged for invalid or redundant moves
    /// @details    Exercises missing IDs, both bounds, and the current position
    ///
    func testListReorderingRejectsMissingAndOutOfBoundsMoves() {
        var lists = SampleData.lists
        let original = lists
        XCTAssertFalse(BoardListReordering.move(999, to: 0, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: -1, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: lists.count, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: 0, in: &lists))
        XCTAssertEqual(lists, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListDragEdgeThresholdsAndInvalidGeometry
    /// @brief      Verify list-drag edge activation at exact thresholds
    /// @details    Checks left/right bands, narrow viewports, and nonfinite geometry
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundWeekPersistenceKeepsArchivedListsAndAllowsEmptyWorkspace
    /// @brief      Persist retained archives and an intentionally empty Week
    /// @details    Uses an isolated suite and awaits the ordered persistence queue after each save
    /// @throws     Preference-suite unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testListArchiveBindingsPreserveCardsAndRestoreAtEnd
    /// @brief      Preserve list records through active/archive binding projections
    /// @details    Archives, round-trips, and appends the restored list after existing active lists
    /// @throws     JSON round-trip or archived-list unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testWholeWeekArchiveRestoresAsSeparateUniquelyNamedBoard
    /// @brief      Restore a Week archive as a separate personal Board
    /// @details    Checks collision-safe naming while retaining IDs, archived lists/cards, and bookmarks
    /// @throws     Collection encoding or decoding errors
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testArchivedPersonalBoardPersistsAndRestoresWithoutRenamingItsLists
    /// @brief      Persist archive state and restore a personal Board with its lists intact
    /// @details    Resolves a Board-title collision without changing contained lists or saved-card IDs
    /// @throws     Checked saves, JSON conversion, or Board unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardArchiveSavesBeforeReturningUpdatedState
    /// @brief      Confirm successful archive commits return the saved collection state
    /// @details    Keeps the input and unrelated collection unchanged while checking persisted output
    /// @throws     Preference-suite unwrap or checked-save failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardArchiveFailureKeepsMemoryAndSavedSnapshotActive
    /// @brief      Reject an unencodable archive without publishing a new collection state
    /// @details    An infinite card date forces encoding failure; memory and the saved Board stay active
    /// @throws     Fixture setup or initial checked-save failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardArchiveRejectsMissingBoardWithoutChangingSavedData
    /// @brief      Preserve saved collections when the requested Board ID is absent
    /// @details    Attempts archive with an unrelated UUID and compares the original stored collection
    /// @throws     Fixture setup or initial checked-save failures
    ///
    func testPersonalBoardArchiveRejectsMissingBoardWithoutChangingSavedData() throws {
        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = PersonalCollection(title: "Project", kind: .board)
        try PersonalCollectionStore.saveChecked([board], to: defaults)
        XCTAssertThrowsError(try PersonalCollectionStore.archiveBoard(id: UUID(), in: [board], to: defaults))
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [board])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyPersonalBoardDefaultsToActiveAndArchivedListsStayOutOfSearch
    /// @brief      Preserve legacy active defaults and exclude archived lists from active projections
    /// @details    Omits isArchived from old JSON, then verifies hidden cards/counts and demo validation
    /// @throws     JSON conversion or unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyListsLoadWithEmptyArchiveAndKeepExistingJSONShape
    /// @brief      Preserve the old list JSON shape when no archive is present
    /// @details    Decodes a three-field list and checks its re-encoded key set
    /// @throws     JSON conversion or unwrap failures
    ///
    func testLegacyListsLoadWithEmptyArchiveAndKeepExistingJSONShape() throws {
        let data = Data("{\"id\":1,\"title\":\"Monday\",\"cards\":[]}".utf8)
        let list = try JSONDecoder().decode(KanbanList.self, from: data)
        XCTAssertTrue(list.archivedCards.isEmpty)
        let encoded = try JSONEncoder().encode(list)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "title", "cards"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testArchivingAndRestoringPreservesFullCardAndDivider
    /// @brief      Retain completed-card content and attachment references through archive/restore
    /// @details    Checks idempotence, divider exclusion, Codable round trip, and restoration at the end
    /// @throws     List encoding or decoding errors
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testArchivedCardsStayOutOfSearchAndReserveTheirIDs
    /// @brief      Exclude archived cards from active search without reusing their identities
    /// @details    Includes retained cards in ID allocation and rejects archives in shared-demo documents
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testIndividualArchiveAcceptsIncompleteCardsAndPreservesContent
    /// @brief      Archive individual cards independently of completion state
    /// @details    Rejects divider/duplicate archives and restores an incomplete card without marking it done
    /// @throws     List encoding or decoding errors
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalListRenamePreservesArchivedCards
    /// @brief      Update archived cards' list-title references when renaming a personal list
    /// @details    Checks retained content and the resulting collection's JSON round trip
    /// @throws     Collection encoding or decoding errors
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testAPIActivityEndsAfterSuccessFailureAndCancellation
    /// @brief      Balance activity tracking across synthetic API outcomes
    /// @details    An ephemeral intercepted session returns success, timeout, or cancellation without networking
    /// @throws     Fixture unwrap/client setup failures or unexpected error types
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testDatabaseActivityKeepsSpinnerUntilAllOperationsFinish
    /// @brief      Keep activity visible until the last tracked operation ends
    /// @details    Checks message handoff and harmless repeated completion of the first operation
    ///
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


    ///
    /// Intercepts synthetic activity-test requests without accessing a remote endpoint
    ///
    /// @section    Purpose
    ///     Supply deterministic success/failure callbacks while inspecting MainActor activity state
    ///
    private final class ActivityTestURLProtocol: URLProtocol {

        ///
        /// @fcn        ActivityTestURLProtocol.canInit(with:)
        /// @brief      Accept every request in the dedicated ephemeral test session
        /// @details    The test installs this protocol only on its synthetic session configuration
        /// @param[in]  request  Request offered by URL loading
        /// @return     (Bool) true
        ///
        override class func canInit(with request: URLRequest) -> Bool { true }

        ///
        /// @fcn        ActivityTestURLProtocol.canonicalRequest(for:)
        /// @brief      Preserve the synthetic request as supplied
        /// @details    No URL or header normalization is needed for host-selected test outcomes
        /// @param[in]  request  Intercepted request
        /// @return     (URLRequest) unchanged request
        ///
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        ///
        /// @fcn        ActivityTestURLProtocol.startLoading
        /// @brief      Deliver the response selected by the synthetic hostname
        /// @details    Checks activity before/after yielding; returns empty users or a transport error
        /// @post       Starts an asynchronous MainActor task that notifies the URLProtocol client
        ///
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

        ///
        /// @fcn        ActivityTestURLProtocol.stopLoading
        /// @brief      Provide the required URLProtocol cancellation hook
        /// @details    This fixture performs no resource cleanup and does not cancel its spawned task
        ///
        override func stopLoading() {}
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDatabaseActivityErrorsRemainUntilDismissed
    /// @brief      Retain a reported error after activity finishes
    /// @details    Checks that only explicit dismissal clears the error message
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundBoardSavesPreserveLatestSnapshot
    /// @brief      Persist the most recent queued Week snapshot
    /// @details    Enqueues two writes in an isolated suite and awaits a load before comparing stored bytes
    /// @throws     Preference/data unwrap or JSON decoding failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundBoardSaveFailurePreservesPreviousSnapshot
    /// @brief      Retain a valid Week snapshot when a later save cannot encode
    /// @details    Uses an infinite date to force failure and checks both retained data and error reporting
    /// @throws     Preference-suite unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundBoardLoadReportsCorruptionWithoutRemovingData
    /// @brief      Report unreadable Week data while retaining its original bytes at load time
    /// @details    Confirms the current sample fallback; does not test protection against subsequent saves
    /// @throws     Preference-suite unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testRecentSearchesAreOrderedDeduplicatedAndClearable
    /// @brief      Verify recent-search normalization, ordering, capacity, and explicit clearing
    /// @details    Uses isolated preferences and checks case-insensitive deduplication and the ten-entry limit
    /// @throws     Preference-suite unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testSearchScopesUseOnlyTheirSelectedFields
    /// @brief      Keep Board, label, user, and all-content searches within their intended fields
    /// @details    Uses one synthetic card to distinguish matches in title, description, assignment, and labels
    ///
    func testSearchScopesUseOnlyTheirSelectedFields() {

        let card = KanbanCard(
            id: 1, word: "Proposal", listTitle: "Monday",
            members: [.manual("Jamie")], labelIDs: ["work-scheduled"],
            descriptionOverride: "Budget review"
        )
        let lists = [KanbanList(id: 0, title: "Monday", cards: [card])]

        ///
        /// @fcn        matches(_:_:)
        /// @brief      Query the fixed synthetic search fixture
        /// @details    Uses the starter label library for label-name and group-name matching
        /// @param[in]  term   Search text
        /// @param[in]  scope  Fields to search
        /// @return     ([TodaySearchResult]) matching canonical references
        ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardSearchIncludesEmptyListsAndCardSearchExcludesDividers
    /// @brief      Keep empty lists discoverable without treating dividers as activities
    /// @details    Checks a list-only result has no card ID and divider text produces no all-content match
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleLoadUndoSnapshotPersistsAndClears
    /// @brief      Round-trip the retained snapshot used by Load Example undo
    /// @details    Saves synthetic lists and today's selection in an isolated suite, then explicitly clears them
    /// @throws     Preference-suite unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testLastViewedListResolvesSavedSelectionAndFallbacks
    /// @brief      Resolve saved list identity against current active lists
    /// @details    Checks saved preference priority, a missing saved target, and an empty workspace
    /// @throws     Preference-suite unwrap failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayDefaultsToMondayAfterSavedAndProfileChoices
    /// @brief      Verify initial Today selection priority
    /// @details    Checks valid saved/profile choices before the named-Monday fallback
    ///
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
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionPersistencePreservesOrderAndLeavesWeekUntouched
    /// @brief      Keep personal collections ordered and independent of the Week store
    /// @details    Persists synthetic Board/list collections and compares unchanged Week bytes
    /// @throws     Preference-suite unwrap or Week encoding failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionRenameAndSearchPreserveCardIdentity
    /// @brief      Rename a personal list without replacing cards or matching dividers
    /// @details    Checks trimmed naming, synchronized list titles, active counts, and searchable description text
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testSampleDataSeedRequestFitsJSONBodyLimit
    /// @brief      Fit the complete synthetic seed request within the client's JSON body ceiling
    /// @details    Encodes the versioned document and request envelope, not just the Board payload
    /// @throws     Request encoding failures
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testJSONBodySizeLimitIncludesExactBoundary
    /// @brief      Verify the inclusive JSON request-size limit
    /// @details    Checks exactly one MiB is accepted and one byte more is rejected
    ///
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