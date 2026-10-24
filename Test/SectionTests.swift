// --------------------------------------------------------------------------------------------------
// @file       SectionTests.swift
// @brief      Section regression tests
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
/// Section regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testSectionTransferKeepsWholeBlockLinksBookmarksAndUndo
    /// @brief      Verify that section Transfer Keeps Whole Block Links Bookmarks And Undo
    /// @details    Exercises `.linkedCard`, `.actionDetail`, `watcher.checklists.append`. Checks
    ///             `XCTAssertEqual(owners[0].lists[0].cards.map(\.id), [0, 5, 6])`;
    ///             `XCTAssertEqual(owners[1].lists[0].cards.map(\.word), ["Existing", "--- Morning", "Breakfast",
    ///             "---", "Walk"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testSectionTransferKeepsWholeBlockLinksBookmarksAndUndo() throws
    {


        ///
        /// @fcn        PlenactBoardDocumentTests.testSectionTransferKeepsWholeBlockLinksBookmarksAndUndo.card
        /// @brief      Prepare card for the enclosing regression test
        /// @details    Supplies the local fixture for section Transfer Keeps Whole Block Links Bookmarks And Undo.
        ///
        /// @param[in]  id     Starting numeric card ID or owner-local content identity
        /// @param[in]  title  Display title or proposed title text
        ///
        /// @return     (KanbanCard) result described by this operation's contract
        ///
        func card(_ id: Int, _ title: String) -> KanbanCard
        {

            KanbanCard(id: id, word: title, listTitle: "Source", checklists: [])
        }

        var source = PersonalCollection(title: "Source", kind: .board, icon: .project, color: .blue)
        var target = PersonalCollection(title: "Target", kind: .list, icon: .notes, color: .teal)
        var observer = PersonalCollection(title: "Links", kind: .board, icon: .project, color: .blue)
        var heading = card(1, "--- Morning")
        heading.appearance = ItemAppearance(accent: .orange, sectionCollapsed: true)
        var member = card(2, "Breakfast")
        member.attachments = [KanbanAttachment(url: URL(string: "https://example.com/breakfast"), mediaKind: .link)]
        member.isTitleChecked = true
        var internalLink = KanbanChecklistItem(title: "Inside", content: .linkedCard(cardID: 2))
        internalLink.retainedCardID = 2
        let externalLink = KanbanChecklistItem(title: "Outside", content: .linkedCard(cardID: 6))
        member.checklists = [KanbanChecklist(title: "Links", items: [internalLink, externalLink])]
        var watcher = card(8, "Watch")
        var nested = KanbanChecklistItem(title: "Nested", content: .linkedCard(cardID: 2))
        nested.linkedCollectionID = source.id
        watcher.checklists = [
            KanbanChecklist(
                title: "Outer",
                items: [
                    KanbanChecklistItem(
                        title: "Detail",
                        content: .actionDetail(
                            KanbanChecklistActionDetail(
                                description: "Context", checklists: [KanbanChecklist(title: "Inner", items: [nested])]))
                    )
                ])
        ]
        var hiddenDetail = KanbanChecklistItem(title: "Inactive detail")
        hiddenDetail.retainedDetail = KanbanChecklistActionDetail(
            description: "Hidden context", checklists: [KanbanChecklist(title: "Retained", items: [nested])])
        watcher.checklists.append(KanbanChecklist(title: "Inactive", items: [hiddenDetail]))
        source.lists = [
            KanbanList(
                id: 10, title: "Source",
                cards: [
                    card(0, "Ungrouped"), heading, member, card(3, "---"), card(4, "Walk"), card(5, "--- Evening"),
                    card(6, "Dinner")
                ])
        ]
        source.savedCardIDs = [2, 6]
        target.lists = [
            KanbanList(id: 20, title: "Target", cards: [card(2, "Existing")], archivedCards: [card(4, "Archived")])
        ]
        observer.lists = [KanbanList(id: 30, title: "Links", cards: [], archivedCards: [watcher])]
        var owners = [source, target, observer]
        let original = owners
        let receipt = try SectionTransfer.move(
            heading: heading,
            source: WorkspaceListReference(ownerID: source.id, listID: 10),
            destination: WorkspaceListReference(ownerID: target.id, listID: 20), owners: &owners)
        XCTAssertEqual(owners[0].lists[0].cards.map(\.id), [0, 5, 6])
        XCTAssertEqual(owners[1].lists[0].cards.map(\.word), ["Existing", "--- Morning", "Breakfast", "---", "Walk"])
        let relocated = try XCTUnwrap(owners[1].lists[0].cards.first
            {
                $0.word == "Breakfast"
            })
        XCTAssertNotEqual(relocated.id, 2)
        XCTAssertEqual(relocated.attachments, member.attachments)
        XCTAssertEqual(relocated.createdAt, member.createdAt)
        XCTAssertTrue(relocated.isTitleChecked)
        XCTAssertEqual(owners[1].lists[0].cards[1].appearance, heading.appearance)
        XCTAssertEqual(owners[0].savedCardIDs, [6])
        XCTAssertTrue(owners[1].savedCardIDs.contains(relocated.id))
        XCTAssertEqual(relocated.checklists[0].items[0].content, .linkedCard(cardID: relocated.id))
        XCTAssertEqual(relocated.checklists[0].items[0].linkedCollectionID, target.id)
        XCTAssertEqual(relocated.checklists[0].items[1].linkedCollectionID, source.id)
        guard case .actionDetail(let detail) = owners[2].lists[0].archivedCards[0].checklists[0].items[0].content else
        {

            return XCTFail("Missing detail")
        }

        XCTAssertEqual(detail.checklists[0].items[0].content, .linkedCard(cardID: relocated.id))
        XCTAssertEqual(detail.checklists[0].items[0].linkedCollectionID, target.id)
        let retained = try XCTUnwrap(owners[2].lists[0].archivedCards[0].checklists[1].items[0].retainedDetail)
        XCTAssertEqual(retained.checklists[0].items[0].content, .linkedCard(cardID: relocated.id))
        var plan = DailyPlan(date: .now, calendar: .current)
        plan.priorities = [
            DailyPlanPriority(
                PlanningSearchResult(
                    weekKey: nil, collectionID: source.id, collectionTitle: source.title,
                    listID: 10, listTitle: "Source", card: member))
        ]
        var plans = DailyPlanStore.Document();
        plans.plans[plan.id] = plan
        let updatedPlans = DailyPlanStore.relocatingSection(receipt, in: plans)
        XCTAssertEqual(updatedPlans.plans[plan.id]?.priorities.first?.ownerID, target.id)
        XCTAssertEqual(updatedPlans.plans[plan.id]?.priorities.first?.cardID, relocated.id)
        XCTAssertEqual(updatedPlans.plans[plan.id]?.priorities.first?.sourceCreatedAt, member.createdAt)
        XCTAssertEqual(try receipt.undo(in: owners), original)
        var edited = owners
        edited[1].lists[0].cards[0].word = "Edited after moving"
        XCTAssertThrowsError(try receipt.undo(in: edited))
        XCTAssertEqual(edited[1].lists[0].cards[0].word, "Edited after moving")
        var unrelated = PersonalCollection(title: "Unrelated", kind: .board, icon: .project, color: .blue)
        unrelated.lists = []
        XCTAssertEqual(try receipt.undo(in: owners + [unrelated]), original + [unrelated])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSectionTransferShiftsDatesAcrossDSTAndRejectsInvalidMovesAtomically
    /// @brief      Verify that section Transfer Shifts Dates Across DST And Rejects Invalid Moves Atomically
    /// @details    Exercises `PlanningDate.date`, `dated.replacingLocation`, `SectionTransfer.move`. Checks
    ///             `XCTAssertTrue(owners[0].lists[0].cards.isEmpty)`; `XCTAssertEqual(result.map(\.id), [1, 2, 3])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testSectionTransferShiftsDatesAcrossDSTAndRejectsInvalidMovesAtomically() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let fromDay = try XCTUnwrap(PlanningDate.date("2026-10-31", calendar: calendar))
        let toDay = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: calendar))
        var owner = PersonalCollection(title: "Week", kind: .board, icon: .project, color: .blue)
        let heading = KanbanCard(id: 1, word: "--- Build", listTitle: "Saturday", checklists: [])
        var dated = KanbanCard(id: 2, word: "Work", listTitle: "Saturday", checklists: [])
        dated.startDate = calendar.date(bySettingHour: 9, minute: 15, second: 0, of: fromDay)
        dated.startDateKind = .dateAndTime
        dated.dueDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: fromDay))
        dated.dueDateKind = .date
        var timed = dated.replacingLocation(id: 3, listTitle: "Saturday");
        timed.startDateKind = .time;

        timed.dueDateKind = .time
        owner.lists = [
            KanbanList(id: 10, title: "Saturday", cards: [heading, dated, timed]),
            KanbanList(id: 11, title: "Monday", cards: [])
        ]
        var owners = [owner]
        let source = WorkspaceListReference(ownerID: owner.id, listID: 10)
        let target = WorkspaceListReference(ownerID: owner.id, listID: 11)
        let original = owners
        let receipt = try SectionTransfer.move(
            heading: heading, source: source, destination: target, owners: &owners,
            sourceDay: fromDay, destinationDay: toDay, shiftDates: true, calendar: calendar)
        XCTAssertTrue(owners[0].lists[0].cards.isEmpty)
        let result = owners[0].lists[1].cards
        XCTAssertEqual(result.map(\.id), [1, 2, 3])
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(result[1].startDate)), 9)
        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(result[1].startDate)), 15)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(result[1].startDate), inSameDayAs: toDay))
        XCTAssertEqual(PlanningDate.key(try XCTUnwrap(result[1].dueDate), calendar: calendar), "2026-11-03")
        XCTAssertEqual(result[2].startDate, timed.startDate)
        XCTAssertEqual(result[2].dueDate, timed.dueDate)
        XCTAssertEqual(try receipt.undo(in: owners), original)
        owners = original
        XCTAssertThrowsError(
            try SectionTransfer.move(heading: heading, source: source, destination: source, owners: &owners))
        XCTAssertEqual(owners, original)
        let missing = WorkspaceListReference(ownerID: UUID(), listID: 11)
        XCTAssertThrowsError(
            try SectionTransfer.move(heading: heading, source: source, destination: missing, owners: &owners))
        XCTAssertEqual(owners, original)
        _ = try SectionTransfer.move(
            heading: heading, source: source, destination: target, owners: &owners, sourceDay: fromDay,
            destinationDay: toDay, shiftDates: false, calendar: calendar)
        XCTAssertEqual(owners[0].lists[1].cards[1].startDate, dated.startDate)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSectionMoveChooserAndUndoNoticeRenderWithoutMovingAndOnlyNoticeReceivesTouches
    /// @brief      Verify that section Move Chooser And Undo Notice Render Without Moving And Only Notice Receives
    ///             Touches
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `TransferConfirmationPresenter.shared.dismiss`. Checks `XCTAssertEqual(moves, 0)`;
    ///             `XCTAssertFalse(scene.windows.contains { !$0.isHidden && $0.windowLevel > .alert }, "Persistent
    ///             Undo must not create another window")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testSectionMoveChooserAndUndoNoticeRenderWithoutMovingAndOnlyNoticeReceivesTouches() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            TransferConfirmationPresenter.shared.dismiss();
            window.isHidden = true;
            window.rootViewController = nil;

            previous?.makeKeyAndVisible()
        }

        let heading = KanbanCard(id: 1, word: "--- Morning", listTitle: "Monday", checklists: [])
        var moves = 0
        let movement = CardMovementAccess(
            destinations: [CardMoveDestination(collectionID: UUID(), listID: 2, title: "On the Table", group: "Plans")],
            moveSection:
            {
                _, _, _, _ in
                moves += 1;
                return true
            },
            moveSectionToDate:
            {
                _, _, _, _ in
                moves += 1;
                return true
            })
        let host = UIHostingController(
            rootView: SectionMoveSheet(heading: heading).environment(\.cardMovementAccess, movement))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host;
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(moves, 0)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-section-move-chooser.png")
        try XCTUnwrap(image.pngData()).write(to: url);
        print("SECTION_MOVE_RENDER=" + url.path)
        var undoCalls = 0
        TransferConfirmationPresenter.shared.showUndo(TransferConfirmation(title: "Morning", destination: "Thursday"))
        {

            undoCalls += 1;
            return true
        }

        try await Task.sleep(for: .milliseconds(200))
        let notice = try XCTUnwrap(window.subviews.first
            {
                $0.accessibilityIdentifier == "section.move.undo.overlay"
            })
        XCTAssertFalse(
            scene.windows.contains
            {
                !$0.isHidden && $0.windowLevel > .alert
            },
                            "Persistent Undo must not create another window")
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertNil(notice.hitTest(CGPoint(x: 10, y: 10), with: nil))
        let hits = stride(from: CGFloat(0), through: notice.bounds.height, by: 10).filter
        {

            notice.hitTest(CGPoint(x: notice.bounds.midX, y: $0), with: nil) != nil
        }

        XCTAssertFalse(hits.isEmpty, "Undo must receive taps")
        XCTAssertLessThan(hits.count, Int(notice.bounds.height / 20), "Touches outside the notice pass through")
        XCTAssertEqual(undoCalls, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDaySectionsKeepPlainDividersInsideTheirNamedSection
    /// @brief      Verify that day Sections Keep Plain Dividers Inside Their Named Section
    /// @details    Exercises `DaySections.visible(cards).map`, `DaySections.visible`, `DaySections.owner`. Checks
    ///             `XCTAssertEqual(DaySections.visible(cards).map(\.id), [0, 1, 5, 6])`;
    ///             `XCTAssertEqual(DaySections.owner(of: 4, in: cards)?.id, 1)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDaySectionsKeepPlainDividersInsideTheirNamedSection() throws
    {


        ///
        /// @fcn        PlenactBoardDocumentTests.testDaySectionsKeepPlainDividersInsideTheirNamedSection.card
        /// @brief      Prepare card for the enclosing regression test
        /// @details    Supplies the local fixture for day Sections Keep Plain Dividers Inside Their Named Section.
        ///
        /// @param[in]  id     Starting numeric card ID or owner-local content identity
        /// @param[in]  title  Display title or proposed title text
        ///
        /// @return     (KanbanCard) result described by this operation's contract
        ///
        func card(_ id: Int, _ title: String) -> KanbanCard
        {

            KanbanCard(id: id, word: title, listTitle: "Monday", checklists: [])
        }

        var heading = card(1, "--- Morning")
        heading.appearance = ItemAppearance(accent: .orange, sectionCollapsed: true)
        let cards = [
            card(0, "Ungrouped"), heading, card(2, "Breakfast"), card(3, "---"),
            card(4, "Walk"), card(5, "--- Evening"), card(6, "Dinner")
        ]
        XCTAssertEqual(DaySections.visible(cards).map(\.id), [0, 1, 5, 6])
        XCTAssertEqual(DaySections.owner(of: 4, in: cards)?.id, 1)
        XCTAssertNil(DaySections.owner(of: 0, in: cards))
        let decoded = try JSONDecoder().decode([KanbanCard].self, from: JSONEncoder().encode(cards))
        XCTAssertEqual(decoded, cards)
        XCTAssertTrue(decoded[1].appearance?.sectionCollapsed == true)
        var expanded = cards
        DaySections.reveal(4, in: &expanded)
        XCTAssertEqual(DaySections.visible(expanded).map(\.id), cards.map(\.id))
        XCTAssertEqual(expanded[1].appearance?.accent, .orange)
        XCTAssertEqual(cards[1].appearance?.sectionCollapsed, true)
        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.sectionCollapsed)
        XCTAssertTrue(legacy.isEmpty)
        XCTAssertFalse(ItemAppearance(sectionCollapsed: true).isEmpty)
        var preferences = LocalProfilePreferences(todayFocusGroupsBySection: true)
        preferences.todayFocusHidesCompleted = false
        let entries = preferences.todayFocusEntries(in: cards)
        XCTAssertEqual(entries.first(where:
                {
                    $0.id == 4
                })?.heading, "Morning")
        XCTAssertTrue(entries.contains
            {
                $0.id == 2
            }, "Collapsing Day content does not hide it from Focus")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDaySectionMovementRetainsTheWholeBlockAndItsMetadata
    /// @brief      Verify that day Section Movement Retains The Whole Block And Its Metadata
    /// @details    Exercises `DaySections.moved`, `moved.map`, `DaySections.moved(cards, sectionID: 7, offset:
    ///             -1).map`. Checks `XCTAssertEqual(moved.map(\.id), [0, 5, 6, 1, 2, 3, 4, 7, 8])`;
    ///             `XCTAssertEqual(DaySections.moved(moved, sectionID: 1, offset: -1), cards)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDaySectionMovementRetainsTheWholeBlockAndItsMetadata() throws
    {


        ///
        /// @fcn        PlenactBoardDocumentTests.testDaySectionMovementRetainsTheWholeBlockAndItsMetadata.card
        /// @brief      Prepare card for the enclosing regression test
        /// @details    Supplies the local fixture for day Section Movement Retains The Whole Block And Its Metadata.
        ///
        /// @param[in]  id     Starting numeric card ID or owner-local content identity
        /// @param[in]  title  Display title or proposed title text
        ///
        /// @return     (KanbanCard) result described by this operation's contract
        ///
        func card(_ id: Int, _ title: String) -> KanbanCard
        {

            KanbanCard(id: id, word: title, listTitle: "Monday", checklists: [])
        }

        var morning = card(1, "--- Morning")
        morning.appearance = ItemAppearance(accent: .orange, sectionCollapsed: true)
        let cards = [
            card(0, "Before sections"), morning, card(2, "Breakfast"), card(3, "---"),
            card(4, "Walk"), card(5, "--- Midday"), card(6, "Work"), card(7, "--- Night"), card(8, "Rest")
        ]
        let moved = DaySections.moved(cards, sectionID: 1, offset: 1)
        XCTAssertEqual(moved.map(\.id), [0, 5, 6, 1, 2, 3, 4, 7, 8])
        XCTAssertEqual(DaySections.moved(moved, sectionID: 1, offset: -1), cards)
        XCTAssertEqual(DaySections.moved(cards, sectionID: 7, offset: -1).map(\.id), [0, 1, 2, 3, 4, 7, 8, 5, 6])
        XCTAssertEqual(DaySections.moved(cards, sectionID: 1, offset: -1), cards)
        XCTAssertEqual(DaySections.reordered(cards, itemID: 1, to: 8).map(\.id), [0, 5, 6, 7, 8, 1, 2, 3, 4])
        XCTAssertEqual(DaySections.reordered(cards, itemID: 7, to: 0).map(\.id), [0, 7, 8, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(DaySections.moved(cards, sectionID: 7, offset: 1), cards)
        XCTAssertEqual(DaySections.moved(cards, sectionID: 3, offset: 1), cards, "A plain line is not a section")
        for item in cards
        {
            XCTAssertEqual(moved.first
                {
                    $0.id == item.id
                }, item)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSectionExampleUpgradePreservesExistingRoutinesAndStoredBytes
    /// @brief      Verify that section Example Upgrade Preserves Existing Routines And Stored Bytes
    /// @details    Exercises `library.templates.removeAll`, `PlanningRoutineLibrary.sectionExamples.contains`,
    ///             `PlanningRoutineStore.load`. Checks
    ///             `XCTAssertEqual(Array(upgraded.templates.prefix(original.count)), original)`;
    ///             `XCTAssertEqual(upgraded.defaultWeekID, library.defaultWeekID)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testSectionExampleUpgradePreservesExistingRoutinesAndStoredBytes() throws
    {

        let suite = "DaySectionExamples." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        var library = PlanningRoutineLibrary.seeded
        library.templates.removeAll
        {
            template in
            PlanningRoutineLibrary.sectionExamples.contains
            {
                $0.id == template.id
            }

        }

        library.bundledRoutineRevision = 2
        library.templates[0].name = "My own week"
        let original = library.templates
        let bytes = try JSONEncoder().encode(library)
        defaults.set(bytes, forKey: PlanningRoutineStore.key)
        let upgraded = try PlanningRoutineStore.load(from: defaults)
        XCTAssertEqual(Array(upgraded.templates.prefix(original.count)), original)
        XCTAssertEqual(upgraded.defaultWeekID, library.defaultWeekID)
        XCTAssertEqual(upgraded.bundledRoutineRevision, 4)
        XCTAssertEqual(
            defaults.data(forKey: PlanningRoutineStore.key), bytes, "Loading examples does not write user data")
        try PlanningRoutineStore.validate(upgraded)
        for example in PlanningRoutineLibrary.sectionExamples
        {

            XCTAssertEqual(example.kind, .day)
            let cards = try XCTUnwrap(example.collection.lists.first).cards
            XCTAssertEqual(cards.filter
                {
                    $0.sectionHeading != nil
                } .count, 3)
            XCTAssertTrue(cards.filter
                {
                    $0.sectionHeading != nil
                } .allSatisfy
                {
                    $0.appearance?.accent != nil
                })
            XCTAssertTrue(cards.allSatisfy
                {
                    !$0.isTitleChecked
                })
            let day = try XCTUnwrap(PlanningDate.date("2026-11-09", calendar: example.calendar))
            let blank = DatedPlanningWeek.make(for: day, calendar: example.calendar)
            let applied = try PlanningTemplateApplication.apply(
                example, to: blank, date: day, calendar: example.calendar, mode: .add)
            let listID = try XCTUnwrap(applied.dayListIDs[PlanningDate.key(day, calendar: example.calendar)])
            let result = try XCTUnwrap(applied.collection.lists.first
                {
                    $0.id == listID
                }).cards
            XCTAssertEqual(result.map(\.word), cards.map(\.word))
            XCTAssertEqual(result.map(\.appearance), cards.map(\.appearance))
            XCTAssertEqual(Set(result.map(\.id)).count, result.count)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDaySectionRowsRenderWithLargeTextAndWithoutEditingOnAppearance
    /// @brief      Verify that day Section Rows Render With Large Text And Without Editing On Appearance
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(writes, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDaySectionRowsRenderWithLargeTextAndWithoutEditingOnAppearance() async throws
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

        let cards = try XCTUnwrap(PlanningRoutineLibrary.sectionExamples.first?.collection.lists.first).cards
        var writes = 0
        for scheme in [ColorScheme.light, .dark]
        {

            let host = UIHostingController(
                rootView: NavigationStack
                {

                    List
                    {

                        ForEach(DaySections.visible(cards))
                        {
                            card in
                            if card.sectionHeading != nil
                            {

                                DaySectionRow(
                                    card: card, cards: cards, onUpdate:
                                    {
                                        _ in
                                        writes += 1
                                    },
                                    onMove:
                                    {
                                        _ in
                                        writes += 1
                                    })
                            }
                            else
                            {

                                Text(card.word).padding(12).modifier(DaySectionRail(cardID: card.id, cards: cards))
                            }

                        }

                    } .navigationTitle("A day in chapters")
                } .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .accessibility1))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-day-sections-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("DAY_SECTION_RENDER=" + url.path)
        }

        XCTAssertEqual(writes, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRandomCardCreationColorsAreIndependentAndExcludeNotesAndDividers
    /// @brief      Verify that random Card Creation Colors Are Independent And Exclude Notes And Dividers
    /// @details    Exercises `list.makeItem`, `NewCardAppearanceDefaults.headerPalette.contains`,
    ///             `NewCardAppearanceDefaults.backgroundPalette.contains`. Checks
    ///             `XCTAssertEqual(card.appearance?.background != nil, headers)`;
    ///             `XCTAssertEqual(card.appearance?.cardBackground != nil, backgrounds)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testRandomCardCreationColorsAreIndependentAndExcludeNotesAndDividers() throws
    {

        let list = KanbanList(id: 1, title: "Ideas", cards: [])
        for headers in [false, true]
        {

            for backgrounds in [false, true]
            {

                let preferences = LocalProfilePreferences(
                    randomizesNewCardHeaders: headers, randomizesNewCardBackgrounds: backgrounds)
                let card = list.makeItem(
                    id: 1, title: "New Card", presentationOverride: .card, creationPreferences: preferences)
                XCTAssertEqual(card.appearance?.background != nil, headers)
                XCTAssertEqual(card.appearance?.cardBackground != nil, backgrounds)
                if let header = card.appearance?.background
                {

                    XCTAssertTrue(NewCardAppearanceDefaults.headerPalette.contains(header))
                }

                if let background = card.appearance?.cardBackground
                {

                    XCTAssertTrue(NewCardAppearanceDefaults.backgroundPalette.contains(background))
                }

                var reopened = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
                XCTAssertEqual(reopened, card)
                NewCardAppearanceDefaults.apply(to: &reopened, preferences: preferences)
                XCTAssertEqual(reopened, card, "A saved color must never reroll")
                XCTAssertNil(
                    list.makeItem(id: 2, title: "Note", presentationOverride: .note, creationPreferences: preferences)
                    .appearance)
                XCTAssertNil(list.makeItem(id: 3, title: "--- Section", creationPreferences: preferences).appearance)
            }

        }

        let enabled = LocalProfilePreferences(randomizesNewCardHeaders: true, randomizesNewCardBackgrounds: true)
        let batch = list.makeItems(startingAt: 10, titles: "First\nSecond\nThird", creationPreferences: enabled)
        XCTAssertEqual(batch.count, 3)
        XCTAssertTrue(batch.allSatisfy
            {
                $0.appearance?.background != nil && $0.appearance?.cardBackground != nil
            })
        var owner = PersonalCollection(title: "Personal Notes", kind: .list)
        try owner.addNote(title: "Choose Card", body: "Writing", presentation: .card, creationPreferences: enabled)
        try owner.addNote(title: "Choose Note", body: "Writing", presentation: .note, creationPreferences: enabled)
        XCTAssertNotNil(owner.lists[0].cards[0].appearance?.cardBackground)
        XCTAssertNil(owner.lists[0].cards[1].appearance)
        var custom = batch[0]
        custom.appearance = ItemAppearance(icon: .notes, background: .purple, cardBackground: .green)
        let original = custom
        NewCardAppearanceDefaults.apply(to: &custom, preferences: enabled)
        XCTAssertEqual(custom, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusShapePreservesSectionsStableTiesAndAllMatchesAfterSorting
    /// @brief      Verify that focus Shape Preserves Sections Stable Ties And All Matches After Sorting
    /// @details    Exercises `preferences.todayFocusEntries`, `entries.map`, `preferences.todayFocusItems(in:
    ///             cards).map`. Checks `XCTAssertEqual(entries.map(\.id), [1, 3, 4, 2, 7, 6, 8])`;
    ///             `XCTAssertEqual(entries[1].heading, "Looking forward to")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusShapePreservesSectionsStableTiesAndAllMatchesAfterSorting() throws
    {


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusShapePreservesSectionsStableTiesAndAllMatchesAfterSorting.item
        /// @brief      Prepare item for the enclosing regression test
        /// @details    Supplies the local fixture for focus Shape Preserves Sections Stable Ties And All Matches
        ///             After Sorting. Uses `time.map`.
        ///
        /// @param[in]  id     Starting numeric card ID or owner-local content identity
        /// @param[in]  title  Display title or proposed title text
        /// @param[in]  time   Time fixture value supplied to the enclosing test
        /// @param[in]  done   Completion state assigned by the fixture
        ///
        /// @return     (KanbanCard) result described by this operation's contract
        ///
        func item(_ id: Int, _ title: String, _ time: Double? = nil, done: Bool = false) -> KanbanCard
        {

            var card = KanbanCard(id: id, word: title, listTitle: "Monday", isTitleChecked: done, checklists: [])
            card.startDate = time.map
            {
                Date(timeIntervalSince1970: $0)
            }

            card.startDateKind = .dateAndTime
            return card
        }

        let firstHeading = KanbanCard(
            id: 90, word: "--- Looking forward to", listTitle: "Monday", isDivider: true, checklists: [])
        let secondHeading = KanbanCard(
            id: 91, word: "--- Must happen", listTitle: "Monday", isDivider: true, checklists: [])
        let repeatedHeading = KanbanCard(
            id: 92, word: "--- Must happen", listTitle: "Monday", isDivider: true, checklists: [])
        let cards = [
            item(1, "Before sections"), firstHeading, item(2, "Later", 200),
            item(3, "Earlier", 100), item(4, "Same time", 100), item(5, "Done", 50, done: true),
            secondHeading, item(6, "Undated"), item(7, "Another time", 25), repeatedHeading,
            item(8, "Repeated section", 1)
        ]
        let original = cards
        var preferences = LocalProfilePreferences(
            todayFocusItemCount: 0,
            todayFocusOrder: .chronological, todayFocusGroupsBySection: true)
        var entries = preferences.todayFocusEntries(in: cards)
        XCTAssertEqual(entries.map(\.id), [1, 3, 4, 2, 7, 6, 8])
        XCTAssertEqual(entries[1].heading, "Looking forward to")
        XCTAssertEqual(entries[4].sectionID, 91)
        XCTAssertEqual(entries.last?.sectionID, 92)
        preferences.todayFocusItemCount = 3
        XCTAssertEqual(preferences.todayFocusItems(in: cards).map(\.id), [1, 3, 4, 2, 7, 6, 8])
        preferences.todayFocusItemCount = 0
        preferences.todayFocusGroupsBySection = false
        XCTAssertEqual(preferences.todayFocusItems(in: cards).map(\.id), [8, 7, 3, 4, 2, 1, 6])
        preferences.todayFocusHidesCompleted = false
        entries = preferences.todayFocusEntries(in: cards)
        XCTAssertEqual(entries.map(\.id), [8, 7, 5, 3, 4, 2, 1, 6])
        XCTAssertTrue(entries[2].card.isTitleChecked)
        preferences.todayFocusOrder = .dayList
        XCTAssertEqual(preferences.todayFocusItems(in: cards).map(\.id), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(cards, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodaySectionSnapOnlyCrossesBoundariesAndRespectsReducedMotion
    /// @brief      Verify that today Section Snap Only Crosses Boundaries And Respects Reduced Motion
    /// @details    Exercises `TodaySectionSnapBehavior.destination`. Checks `XCTAssertEqual(snap(0, 450), 800)`;
    ///             `XCTAssertEqual(snap(800, 650), 0)`.
    ///
    /// @return     (Void) no return value
    ///
    func testTodaySectionSnapOnlyCrossesBoundariesAndRespectsReducedMotion()
    {


        ///
        /// @fcn        PlenactBoardDocumentTests.testTodaySectionSnapOnlyCrossesBoundariesAndRespectsReducedMotion.snap
        /// @brief      Prepare snap for the enclosing regression test
        /// @details    Supplies the local fixture for today Section Snap Only Crosses Boundaries And Respects Reduced
        ///             Motion. Uses `TodaySectionSnapBehavior.destination`.
        ///
        /// @param[in]  start     Starting horizontal position or original vertical scroll offset in points
        /// @param[in]  proposed  Proposed vertical scroll offset at the end of the gesture
        /// @param[in]  enabled   Whether this optional behavior is enabled
        /// @param[in]  maximum   Largest vertical content offset allowed by the scroll bounds
        ///
        /// @return     (CGFloat?) matching or resolved value, or nil when unavailable
        ///
        func snap(_ start: CGFloat, _ proposed: CGFloat, enabled: Bool = true, maximum: CGFloat = 1200) -> CGFloat?
        {

            TodaySectionSnapBehavior.destination(
                start: start, proposed: proposed, perspectiveTop: 800,
                shortcutsBottom: 700, viewport: 600, maximum: maximum, enabled: enabled)
        }

        XCTAssertEqual(snap(0, 450), 800)
        XCTAssertEqual(snap(800, 650), 0)
        XCTAssertNil(snap(0, 200))
        XCTAssertNil(snap(800, 950))
        XCTAssertNil(snap(1000, 850))
        XCTAssertNil(snap(700, 690))
        XCTAssertNil(snap(0, 450, enabled: false))
        XCTAssertEqual(snap(0, 450, maximum: 600), 600)
        XCTAssertNil(
            TodaySectionSnapBehavior.destination(
                start: 0, proposed: 500,
                perspectiveTop: 0, shortcutsBottom: 0, viewport: 600, maximum: 1200, enabled: true))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryDaySectionExamplesSearchIncludesHeadingsAndMemberItems
    /// @brief      Verify that library Day Section Examples Search Includes Headings And Member Items
    /// @details    Exercises `LibraryDaySectionExamples.matches`, `LibraryDaySectionExamples.matches(query:
    ///             "morning").map`, `LibraryDaySectionExamples.matches(query: "tools teardown").map`. Checks
    ///             `XCTAssertEqual(LibraryDaySectionExamples.matches(query: "day sections").count, 3)`;
    ///             `XCTAssertEqual(LibraryDaySectionExamples.matches(query: "morning").map(\.name), ["A day in
    ///             chapters"])`.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func testLibraryDaySectionExamplesSearchIncludesHeadingsAndMemberItems()
    {

        XCTAssertEqual(LibraryDaySectionExamples.matches(query: "day sections").count, 3)
        XCTAssertEqual(LibraryDaySectionExamples.matches(query: "morning").map(\.name), ["A day in chapters"])
        XCTAssertEqual(LibraryDaySectionExamples.matches(query: "tools teardown").map(\.name), ["A build session"])
        XCTAssertEqual(LibraryDaySectionExamples.matches(query: "headphones home").map(\.name), ["A workout journey"])
        XCTAssertTrue(LibraryDaySectionExamples.matches(query: "nonexistent example zzz").isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testGalleryGroupsPreserveItemOrderAndDividerIdentity
    /// @brief      Verify that gallery Groups Preserve Item Order And Divider Identity
    /// @details    Exercises `list.makeItem`, `BoardGalleryGroup.groups`, `groups.flatMap(\.cards).map`. Checks
    ///             `XCTAssertEqual(groups.flatMap(\.cards).map(\.id), [1, 3, 4, 6])`;
    ///             `XCTAssertEqual(groups.compactMap(\.divider).map(\.id), [2, 5])`.
    ///
    /// @return     (Void) no return value
    ///
    func testGalleryGroupsPreserveItemOrderAndDividerIdentity()
    {

        var list = KanbanList(id: 3, title: "Plans", cards: [])
        list.cards = [
            list.makeItem(id: 1, title: "First"), list.makeItem(id: 2, title: "--- Ideas"),
            list.makeItem(id: 3, title: "A note", description: "Writing", presentationOverride: .note),
            list.makeItem(id: 4, title: "A picture"), list.makeItem(id: 5, title: "--- Later"),
            list.makeItem(id: 6, title: "Last")
        ]
        list.cards[3].displayFormat = .picture
        let original = list
        let groups = BoardGalleryGroup.groups(in: list)
        XCTAssertEqual(groups.flatMap(\.cards).map(\.id), [1, 3, 4, 6])
        XCTAssertEqual(groups.compactMap(\.divider).map(\.id), [2, 5])
        XCTAssertEqual(groups.compactMap
            {
                $0.divider?.sectionHeading
            }, ["Ideas", "Later"])
        XCTAssertEqual(groups.flatMap
            {
                ($0.divider.map
                    {
                        [$0]
                    }
                    ?? []) + $0.cards
            } .map(\.id), list.cards.map(\.id))
        XCTAssertEqual(list, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNamedDividersPreserveIdentityAndLegacySeparators
    /// @brief      Verify that named Dividers Preserve Identity And Legacy Separators
    /// @details    Exercises `list.makeItem`. Checks `XCTAssertTrue(named.isSectionDivider)`;
    ///             `XCTAssertEqual(named.word, "Ideas")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testNamedDividersPreserveIdentityAndLegacySeparators() throws
    {

        let list = KanbanList(id: 3, title: "Plans", cards: [])
        var named = list.makeItem(id: 42, title: "--- Ideas")
        XCTAssertTrue(named.isSectionDivider)
        XCTAssertEqual(named.word, "Ideas")
        XCTAssertEqual(named.sectionHeading, "Ideas")
        named.word = "This week"
        XCTAssertTrue(named.isSectionDivider)
        XCTAssertEqual(named.sectionHeading, "This week")
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(named))
        XCTAssertEqual(restored.id, 42)
        XCTAssertTrue(restored.isSectionDivider)
        XCTAssertEqual(restored.sectionHeading, "This week")
        named.word = ""
        XCTAssertTrue(named.isSectionDivider)
        XCTAssertNil(named.sectionHeading)
        XCTAssertNil(list.makeItem(id: 43, title: "---").sectionHeading)
        XCTAssertTrue(list.makeItem(id: 44, title: "——— Later").isSectionDivider)
        XCTAssertFalse(list.makeItem(id: 45, title: "- A regular item").isSectionDivider)
        var converted = list.makeItem(id: 46, title: "Later")
        converted.displayFormat = .divider
        XCTAssertEqual(converted.sectionHeading, "Later")
        converted.displayFormat = .card
        XCTAssertFalse(converted.isSectionDivider)
        XCTAssertNil(converted.sectionHeading)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDisplayFormatsOverrideLegacyDividersWithoutChangingRetainedContent
    /// @brief      Verify that display Formats Override Legacy Dividers Without Changing Retained Content
    /// @details    Exercises `JSONSerialization.jsonObject`, `.manual`, `decoded.replacingLocation`. Checks
    ///             `XCTAssertEqual(legacy.displayFormat, .divider)`; `XCTAssertNil(legacyJSON["listDisplayFormat"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDisplayFormatsOverrideLegacyDividersWithoutChangingRetainedContent() throws
    {

        let legacy = KanbanCard(id: 71, word: "---", listTitle: "Ideas", isDivider: true)
        XCTAssertEqual(legacy.displayFormat, .divider)
        let legacyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(legacyJSON["listDisplayFormat"])
        XCTAssertEqual(
            try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(legacy)).displayFormat, .divider)
        let photo = KanbanAttachment(fileName: "display-example.jpg", caption: "Retained caption")
        var original = legacy
        original.attachments = [photo]
        original.coverAttachmentID = photo.id
        original.descriptionOverride = "Retained writing"
        original.comments = [KanbanComment(author: "Example", body: "Retained comment")]
        original.members = [.manual("Example")]
        original.labelIDs = ["example"]
        original.isTitleChecked = true
        original.startDate = Date(timeIntervalSince1970: 1200)
        original.dueDate = Date(timeIntervalSince1970: 2400)
        original.appearance = ItemAppearance(icon: .heart, background: .rose)
        for format in ItemDisplayFormat.allCases
        {

            var changed = original
            changed.displayFormat = format
            let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(changed))
            XCTAssertEqual(decoded, changed)
            XCTAssertEqual(decoded.displayFormat, format)
            XCTAssertEqual(decoded.isSectionDivider, format == .divider)
            XCTAssertEqual(decoded.coverAttachment?.id, format == .divider ? nil : photo.id)
            var restored = decoded
            restored.listDisplayFormat = original.listDisplayFormat
            restored.presentation = original.presentation
            XCTAssertEqual(restored, original, "Changing display must retain every content field")
            let relocated = decoded.replacingLocation(id: 72, listTitle: "Next")
            XCTAssertEqual(relocated.displayFormat, format)
            XCTAssertEqual(relocated.attachments, original.attachments)
            XCTAssertEqual(relocated.checklists, original.checklists)
        }

        let explicitNote = KanbanCard(id: 75, word: "---", listTitle: "Ideas", listDisplayFormat: .note)
        XCTAssertEqual(explicitNote.presentation, .note)
        XCTAssertFalse(explicitNote.isSectionDivider)
        let explicitCard = KanbanCard(
            id: 76, word: "---", listTitle: "Ideas", presentation: .note, listDisplayFormat: .card)
        XCTAssertEqual(explicitCard.presentation, .card)
        XCTAssertFalse(explicitCard.isSectionDivider)
        let invalid = Data(#"{"id":1,"word":"Example","listTitle":"Ideas","listDisplayFormat":"unsupported"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(KanbanCard.self, from: invalid))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testKeyboardNeighborsStayWithinActiveListAndSkipDividers
    /// @brief      Verify that keyboard Neighbors Stay Within Active List And Skip Dividers
    /// @details    Exercises `CardKeyboardNeighbors.resolve`. Checks `XCTAssertNil(CardKeyboardNeighbors.resolve(a,
    ///             in: lists).previous)`; `XCTAssertEqual(CardKeyboardNeighbors.resolve(a, in: lists).next, b)`.
    ///
    /// @return     (Void) no return value
    ///
    func testKeyboardNeighborsStayWithinActiveListAndSkipDividers()
    {

        let a = KanbanCard(id: 1, word: "A", listTitle: "Today", checklists: [])
        let divider = KanbanCard(id: 2, word: "Section", listTitle: "Today", isDivider: true, checklists: [])
        let b = KanbanCard(id: 3, word: "B", listTitle: "Today", checklists: [], presentation: .note)
        let lists = [
            KanbanList(id: 1, title: "Today", cards: [a, divider, b]), KanbanList(id: 2, title: "Other", cards: [])
        ]
        XCTAssertNil(CardKeyboardNeighbors.resolve(a, in: lists).previous)
        XCTAssertEqual(CardKeyboardNeighbors.resolve(a, in: lists).next, b)
        XCTAssertEqual(CardKeyboardNeighbors.resolve(b, in: lists).previous, a)
        XCTAssertNil(CardKeyboardNeighbors.resolve(b, in: lists).next)
        var archived = lists;
        archived[0].isArchived = true
        XCTAssertNil(CardKeyboardNeighbors.resolve(a, in: archived).next)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardSectionLayoutPersistsWithoutRemovingHiddenContent
    /// @brief      Verify that card Section Layout Persists Without Removing Hidden Content
    /// @details    Exercises `JSONSerialization.jsonObject`, `legacy.removeValue`, `JSONSerialization.data`. Checks
    ///             `XCTAssertEqual(decoded.sectionLayout, layout)`; `XCTAssertEqual(decoded.sectionLayout?.sections,
    ///             [.activity, .quickActions, .media, .details])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCardSectionLayoutPersistsWithoutRemovingHiddenContent() throws
    {

        var layout = CardSectionLayout()
        layout.order = [.activity, .description, .quickActions, .media, .checklists, .details]
        layout.hidden = [.description, .checklists]
        let original = KanbanCard(
            id: 9, word: "Custom", listTitle: "Saturday", descriptionOverride: "Keep this description",
            sectionLayout: layout)
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.sectionLayout, layout)
        XCTAssertEqual(decoded.sectionLayout?.sections, [.activity, .quickActions, .media, .details])
        XCTAssertEqual(decoded.descriptionOverride, "Keep this description")
        XCTAssertEqual(decoded.checklists, original.checklists)
        var restored = decoded
        restored.sectionLayout = nil
        XCTAssertEqual((restored.sectionLayout ?? CardSectionLayout()).sections, CardSection.allCases)
        XCTAssertEqual(restored.checklists, original.checklists)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "sectionLayout")
        let oldCard = try JSONDecoder().decode(KanbanCard.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(oldCard.sectionLayout)
        let repaired = CardSectionLayout(order: [.activity, .activity], hidden: [.details])
        XCTAssertEqual(repaired.sections, [.activity, .quickActions, .media, .description, .checklists])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListNoteDefaultAppliesOnlyToNewNondividerItems
    /// @brief      Verify that list Note Default Applies Only To New Nondivider Items
    /// @details    Exercises `list.makeItem`, `card.checklists.map`, `legacyCard.checklists.map`. Checks
    ///             `XCTAssertEqual(card.presentation, .card)`; `XCTAssertEqual(card.word, legacyCard.word)`.
    ///
    /// @return     (Void) no return value
    ///
    func testListNoteDefaultAppliesOnlyToNewNondividerItems()
    {


        let existing = KanbanCard(
            id: 1, word: "Existing", listTitle: "Ideas") /* Existing Card retained while applying List defaults */
        var list = KanbanList(
            id: 1, title: "Ideas", cards: [existing])     /* List state under verification */
        let card = list.makeItem(id: 2, title: "Action")  /* Card value under verification */

        let legacyCard = KanbanCard(id: 2, word: "Action", listTitle: "Ideas") /* Legacy-format Card fixture */

        XCTAssertEqual(card.presentation, .card)
        XCTAssertEqual(card.word, legacyCard.word)
        XCTAssertEqual(card.descriptionOverride, legacyCard.descriptionOverride)
        XCTAssertEqual(card.checklists.map(\.title), legacyCard.checklists.map(\.title))
        XCTAssertEqual(
            card.checklists.flatMap(\.items).map(\.title), legacyCard.checklists.flatMap(\.items).map(\.title))
        XCTAssertEqual(
            card.checklists.flatMap(\.items).map(\.isCompleted),
            legacyCard.checklists.flatMap(\.items).map(\.isCompleted))

        list.newItemPresentation = .note
        let note = list.makeItem(id: 3, title: "Thought")  /* Newly created Note value */
        let divider = list.makeItem(id: 4, title: "---")   /* Section-divider fixture  */

        XCTAssertEqual(list.cards, [existing])
        XCTAssertEqual(note.presentation, .note)
        XCTAssertEqual(note.descriptionOverride, "")
        XCTAssertTrue(note.checklists.isEmpty)
        XCTAssertEqual(divider.presentation, .card)
        XCTAssertTrue(divider.isSectionDivider)
        XCTAssertEqual(
            list.makeItem(id: 5, title: "Written", description: "Keep\nspacing").descriptionOverride, "Keep\nspacing")

        list.newItemPresentation = .card

        XCTAssertEqual(note.presentation, .note, "Changing a default must not convert existing Notes")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardReorderingMovesDividersAndPreservesCompleteRecords()
    /// @brief      Reorder Today and Board rows without altering their retained card content
    /// @details    Moves a section divider between cards and verifies complete records retain
    ///             their stable identities and values
    ///
    /// @return     (Void) records assertion failures for order or content changes
    ///
    func testCardReorderingMovesDividersAndPreservesCompleteRecords()
    {


        let first = KanbanCard(
            id: 1, word: "First", listTitle: "Synthetic", descriptionOverride: "Keep this") /* First retained card fixture  */
        let divider = KanbanCard(
            id: 2, word: "", listTitle: "Synthetic", isDivider: true) /* Movable divider fixture      */
        let last = KanbanCard(
            id: 3, word: "Last", listTitle: "Synthetic", isTitleChecked: true)  /* Last retained card fixture   */
        var cards = [first, divider, last]                                      /* Ordered focused-list records */

        XCTAssertTrue(BoardCardReordering.move(divider.id, to: 2, in: &cards))
        XCTAssertEqual(cards, [first, last, divider])
        XCTAssertEqual(cards.map(\.id), [1, 3, 2])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDividerMovementPreservesRecordsWithinAndBetweenLists
    /// @brief      Verify that divider Movement Preserves Records Within And Between Lists
    /// @details    Exercises `BoardCardMovement.move`. Checks `XCTAssertTrue(try BoardCardMovement.move(divider.id,
    ///             to: 10, in: &lists))`; `XCTAssertEqual(lists[0].cards, [card, divider])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDividerMovementPreservesRecordsWithinAndBetweenLists() throws
    {

        let divider = KanbanCard(id: 2, word: "---", listTitle: "A", isDivider: true, checklists: [])
        let card = KanbanCard(id: 1, word: "Synthetic", listTitle: "A", checklists: [])
        var lists = [
            KanbanList(id: 10, title: "A", cards: [divider, card]),
            KanbanList(id: 20, title: "B", cards: [])
        ]
        XCTAssertTrue(try BoardCardMovement.move(divider.id, to: 10, in: &lists))
        XCTAssertEqual(lists[0].cards, [card, divider])
        XCTAssertFalse(try BoardCardMovement.move(divider.id, to: 10, in: &lists))
        let beforeInvalidMove = lists
        XCTAssertThrowsError(try BoardCardMovement.move(divider.id, to: 20, before: 999, in: &lists))
        XCTAssertEqual(lists, beforeInvalidMove)
        XCTAssertTrue(try BoardCardMovement.move(divider.id, to: 20, in: &lists))
        var relocated = divider
        relocated.listTitle = "B"
        XCTAssertEqual(lists[0].cards, [card])
        XCTAssertEqual(lists[1].cards, [relocated])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testArchivingAndRestoringPreservesFullCardAndDivider()
    /// @brief      Retain completed-card content and attachment references through archive/restore
    /// @details    Checks idempotence, divider exclusion, Codable round trip, and restoration at
    ///             the end
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     List encoding or decoding errors
    ///
    func testArchivingAndRestoringPreservesFullCardAndDivider() throws
    {


        var completed = SampleData.lists[0].cards[0] /* Completed checklist-item fixture */

        completed.isTitleChecked = true
        completed.attachments = [KanbanAttachment(fileName: "synthetic-archive.jpg", mediaKind: .photo)]

        let active = KanbanCard(id: 500, word: "Active", listTitle: "Monday") /* Active Card before archival   */
        let divider = KanbanCard(
            id: 501, word: "Divider", listTitle: "Monday", isDivider: true, isTitleChecked: true) /* Section-divider fixture       */
        var list = KanbanList(
            id: 1, title: "Monday", cards: [completed, divider, active]) /* List state under verification */

        list.archiveCompletedCards()

        XCTAssertEqual(list.cards, [divider, active])
        XCTAssertEqual(list.archivedCards, [completed])
        XCTAssertEqual(Set(list.allCards.compactMap
                {
                    $0.attachments?.first?.fileName
                }), ["synthetic-archive.jpg"])

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
    /// @fcn        PlenactBoardDocumentTests.testBoardSearchIncludesEmptyListsAndCardSearchExcludesDividers()
    /// @brief      Keep empty lists discoverable without treating dividers as activities
    /// @details    Checks a list-only result has no card ID and divider text produces no
    ///             all-content match
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testBoardSearchIncludesEmptyListsAndCardSearchExcludesDividers()
    {


        let divider = KanbanCard(
            id: 1, word: "Divider", listTitle: "Monday", isDivider: true)  /* Section-divider fixture        */
        let lists = [                                                      /* Board lists under verification */
            KanbanList(id: 0, title: "Monday", cards: [divider]),
            KanbanList(id: 2, title: "Empty list", cards: [])
        ]
        let results = TodaySearchIndex.results(
            query: "Empty", scope: .boards, lists: lists, library: .starter) /* Decoded API results */

        XCTAssertEqual(results.map(\.listID), [2])
        XCTAssertNil(results.first?.cardID)
        XCTAssertTrue(TodaySearchIndex.results(query: "Divider", scope: .all, lists: lists, library: .starter).isEmpty)
    }

}
