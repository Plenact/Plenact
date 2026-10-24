// --------------------------------------------------------------------------------------------------
// @file       CardEditingTests.swift
// @brief      Card Editing regression tests
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
/// CardEditing regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testNoteListDayLayoutRendersAtPhoneAndTabletWidths
    /// @brief      Verify that note List Day Layout Renders At Phone And Tablet Widths
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertGreaterThan(host.view.bounds.height, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testNoteListDayLayoutRendersAtPhoneAndTabletWidths() async throws
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

        var list = KanbanList(
            id: 8, title: "Wednesday",
            cards: [
                KanbanCard(
                    id: 1, word: "Plan the next useful step", listTitle: "Wednesday", checklists: [],
                    descriptionOverride: "Make room for a focused morning"),
                KanbanCard(
                    id: 2, word: "Capture a thought", listTitle: "Wednesday", checklists: [],
                    descriptionOverride: "Writing stays in its original Note", presentation: .note),
                KanbanCard(
                    id: 3, word: "A completed task", listTitle: "Wednesday", isTitleChecked: true, checklists: [])
            ])
        list.setSingleListViewMode(.noteList)
        for width: CGFloat in [393, 820]
        {

            let view = TodayListDetailView(
                lists: .constant([list]), reservedLists: [], labelLibrary: .constant(.starter),
                savedCardIDs: .constant([]), listID: list.id, currentUserName: "Test", onClose:
                {

                }, onOpenWeek:
                {

                },
                onPermanentDelete:
                {
                    _ in
                    false
                }, representedDate: Date(timeIntervalSince1970: 1791936000))
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: width, height: width < 500 ? 852 : 1180)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-note-list-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("NOTE_LIST_RENDER=" + url.path)
            XCTAssertGreaterThan(host.view.bounds.height, 0)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCheckInPersistsSharedPlanAndTracksLiveProgressWithoutCountingNotes
    /// @brief      Verify that check In Persists Shared Plan And Tracks Live Progress Without Counting Notes
    /// @details    Exercises `DatedPlanningWeek.make`, `sources.map`, `DailyPlanStore.save`. Checks `XCTAssertNil(try
    ///             DailyPlanStore.load(from: defaults).plans[plan.id]?.checkIn)`; `XCTAssertEqual(restored, saved)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCheckInPersistsSharedPlanAndTracksLiveProgressWithoutCountingNotes() throws
    {

        let name = "PlenactTests.CheckIn." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        var table = PersonalCollection(title: "On the Table", kind: .list)
        table.lists[0].cards = [
            KanbanCard(id: 0, word: "Next task", listTitle: table.title, checklists: []),
            KanbanCard(id: 1, word: "Finished", listTitle: table.title, isTitleChecked: true, checklists: []),
            KanbanCard(id: 2, word: "Context", listTitle: table.title, checklists: [], presentation: .note)
        ]
        let week = DatedPlanningWeek.make(for: .now)
        let access = PlanningCalendarAccess(
            document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [table],
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
        let sources = access.searchableItems
        var plan = DailyPlan(date: .now)
        plan.priorities = sources.map(DailyPlanPriority.init)
        plan.visionCompletedAt = .now;
        plan.eveningReview = DailyEveningReview()
        let initial = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        XCTAssertNil(try DailyPlanStore.load(from: defaults).plans[plan.id]?.checkIn)
        let next = try XCTUnwrap(plan.priorities.first
            {
                $0.title == "Next task"
            })
        plan.checkIn = DailyCheckIn(focus: next, changed: "Less time available", savedAt: .now)
        plan.constraints = "Only one hour"
        let saved = try DailyPlanStore.save(plan, replacing: initial, to: defaults)
        let restored = try XCTUnwrap(DailyPlanStore.load(from: defaults).plans[plan.id])
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(restored.visionCompletedAt, initial.visionCompletedAt)
        XCTAssertEqual(restored.eveningReview, initial.eveningReview)
        let counts = DailyCheckInProgress.counts(plan: restored, sources: sources)
        XCTAssertEqual(counts.tasks, 2);
        XCTAssertEqual(counts.completed, 1);
        XCTAssertEqual(counts.notes, 1)
        XCTAssertEqual(DailyCheckInProgress.focus(plan: restored, sources: sources), next)
        var removed = restored;
        removed.priorities.removeAll
        {
            $0.id == next.id
        }

        XCTAssertNil(DailyCheckInProgress.focus(plan: removed, sources: sources))
        XCTAssertNil(DailyCheckInProgress.focus(plan: restored, sources: []))
        var completed = sources
        let index = try XCTUnwrap(completed.firstIndex
            {
                $0.card.word == "Next task"
            })
        var card = completed[index].card;
        card.isTitleChecked = true
        let old = completed[index]
        completed[index] = PlanningSearchResult(
            weekKey: old.weekKey, collectionID: old.collectionID, collectionTitle: old.collectionTitle,
            listID: old.listID, listTitle: old.listTitle, card: card)
        XCTAssertNil(DailyCheckInProgress.focus(plan: restored, sources: completed))
        XCTAssertEqual(DailyCheckInProgress.counts(plan: restored, sources: completed).completed, 2)
        XCTAssertEqual(access.library[0], table)
        XCTAssertThrowsError(try DailyPlanStore.save(plan, replacing: initial, to: defaults))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testMorningTransferPreservesDetailsAndReturnsOneNewDestinationIdentity
    /// @brief      Verify that morning Transfer Preserves Details And Returns One New Destination Identity
    /// @details    Exercises `table.lists[0].cards.map`, `CrossBoardCardMovement.move`,
    ///             `collections[1].lists[0].cards.first`. Checks
    ///             `XCTAssertTrue(collections[0].lists[0].cards.isEmpty)`;
    ///             `XCTAssertEqual(collections[1].lists[0].cards.count, 2)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testMorningTransferPreservesDetailsAndReturnsOneNewDestinationIdentity() throws
    {

        var source = PersonalCollection(title: "Scheduled", kind: .list)
        var table = PersonalCollection(title: "On the Table", kind: .list)
        let card = KanbanCard(
            id: 7, word: "Scheduled work", listTitle: source.title, startDate: Date(timeIntervalSince1970: 100),
            dueDate: Date(timeIntervalSince1970: 200),
            checklists: [KanbanChecklist(title: "Steps", items: ["One", "Two"])],
            descriptionOverride: "Keep my details", presentation: .note, createdAt: Date(timeIntervalSince1970: 50),
            startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
        source.lists[0].cards = [card]
        table.lists[0].cards = [KanbanCard(id: 7, word: "Already here", listTitle: table.title)]
        let before = Set(table.lists[0].cards.map(\.id))
        var collections = [source, table]
        var week: [KanbanList] = []
        var saved = Set<Int>()
        let destination = CardMoveDestination(collectionID: table.id, listID: 0, title: table.title, group: "Plans")
        try CrossBoardCardMovement.move(
            card, from: source.id, to: destination, week: &week, collections: &collections, saved: &saved)
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        let moved = try XCTUnwrap(
            collections[1].lists[0].cards.first
            {
                !before.contains($0.id) && $0.createdAt == card.createdAt
            })
        XCTAssertEqual(collections[1].lists[0].cards.count, 2)
        XCTAssertEqual(moved.descriptionOverride, card.descriptionOverride)
        XCTAssertEqual(moved.startDate, card.startDate)
        XCTAssertEqual(moved.dueDate, card.dueDate)
        XCTAssertEqual(moved.startDateKind, .dateAndTime)
        XCTAssertEqual(moved.presentation, .note)
        XCTAssertEqual(moved.checklists, card.checklists)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAddingDailyPrioritySavesCanonicalCardOrNoteAndRejectsFailedDestinations
    /// @brief      Verify that adding Daily Priority Saves Canonical Card Or Note And Rejects Failed Destinations
    /// @details    Exercises `DatedPlanningWeek.make`, `DailyPriorityCreation.create`,
    ///             `DailyPlanPriority(source).resolve`. Checks `XCTAssertEqual(source.card.id, 91)`;
    ///             `XCTAssertEqual(source.card.word, "New priority")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testAddingDailyPrioritySavesCanonicalCardOrNoteAndRejectsFailedDestinations() throws
    {

        let week = DatedPlanningWeek.make(for: .now)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        var owner = PersonalCollection(title: "On the Table", kind: .list)
        owner.lists[0].archivedCards = [KanbanCard(id: 90, word: "Archived", listTitle: owner.title)]
        let target = WorkspaceListReference(ownerID: owner.id, listID: owner.lists[0].id)
        let link = KanbanAttachment(url: URL(string: "https://example.com/priority"), mediaKind: .link)
        for kind in [ItemPresentation.card, .note]
        {

            var savedOwner: PersonalCollection?
            let access = PlanningCalendarAccess(
                document: document, library: [owner], saveWeek:
                {
                    _ in
                    false
                }, openCurrentWeek:
                {

                }, openToday:
                {

                },
                openLibraryCard:
                {
                    _ in
                },
                saveLibrary:
                {

                    savedOwner = $0;
                    return true
                })
            let source = try XCTUnwrap(
                DailyPriorityCreation.create(
                    title: "  New priority  ", body: "Useful context", presentation: kind, destination: target,
                    access: access, attachments: [link]))
            XCTAssertEqual(source.card.id, 91)
            XCTAssertEqual(source.card.word, "New priority")
            XCTAssertEqual(source.card.descriptionOverride, "Useful context")
            XCTAssertEqual(source.card.presentation, kind)
            XCTAssertEqual(source.card.attachments, [link])
            XCTAssertNotNil(source.card.createdAt)
            XCTAssertEqual(source.collectionID, owner.id)
            XCTAssertEqual(savedOwner?.lists[0].cards, [source.card])
            XCTAssertTrue(owner.lists[0].cards.isEmpty)
            XCTAssertEqual(DailyPlanPriority(source).resolve(in: [source])?.card, source.card)
            XCTAssertNil(
                DailyPriorityCreation.create(
                    title: " ", body: "", presentation: kind, destination: target, access: access))
        }

        let failed = PlanningCalendarAccess(
            document: document, library: [owner], saveWeek:
            {
                _ in
                false
            }, openCurrentWeek:
            {

            }, openToday:
            {

            },
            openLibraryCard:
            {
                _ in
            }, saveLibrary:
            {
                _ in
                false
            })
        XCTAssertNil(
            DailyPriorityCreation.create(
                title: "Keep draft", body: "", presentation: .card, destination: target, access: failed))
        let missing = WorkspaceListReference(ownerID: UUID(), listID: target.listID)
        XCTAssertNil(
            DailyPriorityCreation.create(
                title: "Missing", body: "", presentation: .card, destination: missing, access: failed))
        var savedWeek: DatedPlanningWeek?
        let access = PlanningCalendarAccess(
            document: document, library: [],
            saveWeek:
            {

                savedWeek = $0;
                return true
            }, openCurrentWeek:
            {

            }, openToday:
            {

            }, openLibraryCard:
            {
                _ in
            }, saveLibrary:
            {
                _ in
                false
            })
        let datedTarget = WorkspaceListReference(ownerID: week.id, listID: week.collection.lists[0].id)
        let dated = try XCTUnwrap(
            DailyPriorityCreation.create(
                title: "Day priority", body: "", presentation: .card, destination: datedTarget, access: access))
        XCTAssertEqual(savedWeek?.collection.lists[0].cards.first, dated.card)
        XCTAssertEqual(dated.weekKey, week.startKey)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDirectCardAndNoteBackDismissesResultToItsPresenter
    /// @brief      Verify that direct Card And Note Back Dismisses Result To Its Presenter
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `PlanningDate.date`. Checks `XCTAssertTrue(probe.presented)`; `XCTAssertFalse(probe.presented,
    ///             "Back must dismiss the direct result for week=\(usesWeek), note=\(isNote)")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDirectCardAndNoteBackDismissesResultToItsPresenter() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for usesWeek in [false, true]
        {

            for isNote in [false, true]
            {

                var owner = PersonalCollection(title: "Return test", kind: .list)
                owner.lists[0].cards = [
                    KanbanCard(
                        id: 701, word: "Return item", listTitle: owner.title,
                        presentation: isNote ? .note : .card)
                ]
                let date = try XCTUnwrap(PlanningDate.date("2026-10-15"))
                var week = DatedPlanningWeek.make(for: date)
                let listID = usesWeek ? week.collection.lists[0].id : owner.lists[0].id
                week.collection.lists[0].cards = owner.lists[0].cards
                let probe = DirectReturnTestProbe()
                let window = UIWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
                let host = UIHostingController(
                    rootView: DirectReturnTestView(
                        probe: probe, owner: owner,
                        week: usesWeek ? week : nil, listID: listID))
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer
                {
                    window.isHidden = true;
                    window.rootViewController = nil
                }

                try await Task.sleep(for: .milliseconds(150))
                probe.presented = true
                var navigation: UINavigationController?
                for _ in 0 ..< 40
                {

                    navigation = findDetailNavigation(in: host)
                    if navigation != nil
                    {
                        break
                    }

                    try await Task.sleep(for: .milliseconds(100))
                }

                let detail = try XCTUnwrap(navigation, "The requested item must open above its owning board")
                XCTAssertTrue(probe.presented)
                detail.popViewController(animated: false)
                for _ in 0 ..< 30
                {

                    if !probe.presented
                    {
                        break
                    }

                    try await Task.sleep(for: .milliseconds(100))
                }

                XCTAssertFalse(
                    probe.presented, "Back must dismiss the direct result for week=\(usesWeek), note=\(isNote)")
            }

        }

        previous?.makeKey()
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNoteNavigationReportsToolbarVisibilityAndRestoresOnReturn
    /// @brief      Verify that note Navigation Reports Toolbar Visibility And Restores On Return
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertFalse(probe.noteIsVisible)`;
    ///             `XCTAssertTrue(probe.noteIsVisible, "A pushed Note must hide the app bar")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testNoteNavigationReportsToolbarVisibilityAndRestoresOnReturn() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let probe = NoteNavigationProbe()
        let host = UIHostingController(rootView: NoteNavigationTestView(probe: probe))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(probe.noteIsVisible)
        probe.path = [KanbanCard(id: 1, word: "Note", listTitle: "Sunday", presentation: .note)]
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(probe.noteIsVisible, "A pushed Note must hide the app bar")
        probe.path = []
        for _ in 0 ..< 20
        {

            if !probe.noteIsVisible
            {
                break
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertFalse(probe.noteIsVisible, "Returning to Week must restore the app bar")
        probe.path = [KanbanCard(id: 2, word: "Card", listTitle: "Sunday")]
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(probe.noteIsVisible, "Ordinary Card navigation remains unchanged")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testChecklistTypeSwitchesPreserveInactiveContentAndIdentity
    /// @brief      Verify that checklist Type Switches Preserve Inactive Content And Identity
    /// @details    Exercises `.actionDetail`, `.linkedCard`, `.webLink`. Checks `XCTAssertEqual(restored.id, id)`;
    ///             `XCTAssertTrue(restored.isCompleted)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testChecklistTypeSwitchesPreserveInactiveContentAndIdentity() throws
    {

        let url = try XCTUnwrap(URL(string: "https://example.com/plan"))
        let detail = KanbanChecklistActionDetail(
            description: "My plan", checklists: [KanbanChecklist(title: "Steps", items: ["First", "Next"])],
            comments: [])
        var item = KanbanChecklistItem(title: "Action", isCompleted: true, content: .actionDetail(detail))
        let id = item.id
        item.content = .linkedCard(cardID: 42)
        item.linkedCollectionID = UUID()
        item.content = .webLink(url)
        item.content = .standard
        let restored = try JSONDecoder().decode(KanbanChecklistItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored.id, id)
        XCTAssertTrue(restored.isCompleted)
        XCTAssertEqual(restored.title, "Action")
        XCTAssertEqual(restored.retainedDetail, detail)
        XCTAssertEqual(restored.retainedCardID, 42)
        XCTAssertEqual(restored.retainedURL, url)
        XCTAssertEqual(restored.linkedCollectionID, item.linkedCollectionID)
        var switched = restored
        switched.content = .actionDetail(try XCTUnwrap(switched.retainedDetail))
        XCTAssertEqual(switched.type, .actionDetail)
        switched.content = .webLink(try XCTUnwrap(switched.retainedURL))
        XCTAssertEqual(
            try JSONDecoder().decode(KanbanChecklistItem.self, from: JSONEncoder().encode(switched)), switched)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyTypedChecklistItemsSeedRetainedPayloads
    /// @brief      Verify that legacy Typed Checklist Items Seed Retained Payloads
    /// @details    Exercises `.linkedCard`, `JSONSerialization.jsonObject`, `json.removeValue`. Checks
    ///             `XCTAssertEqual(restored.retainedCardID, 12)`; `XCTAssertEqual(restored.content,
    ///             .linkedCard(cardID: 12))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLegacyTypedChecklistItemsSeedRetainedPayloads() throws
    {

        let item = KanbanChecklistItem(title: "Linked", content: .linkedCard(cardID: 12))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        json.removeValue(forKey: "retainedCardID")
        let restored = try JSONDecoder().decode(
            KanbanChecklistItem.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.retainedCardID, 12)
        XCTAssertEqual(restored.content, .linkedCard(cardID: 12))
        json.removeValue(forKey: "content")
        XCTAssertEqual(
            try JSONDecoder().decode(KanbanChecklistItem.self, from: JSONSerialization.data(withJSONObject: json)).type,
            .standard)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCompactProfileRendersSlimmerThanDetailedWithoutEditing
    /// @brief      Verify that compact Profile Renders Slimmer Than Detailed Without Editing
    /// @details    Exercises `compact.sizeThatFits`, `detailed.sizeThatFits`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks `XCTAssertLessThan(compactSize.height,
    ///             detailedSize.height)`; `XCTAssertLessThanOrEqual(compactSize.height, 90)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCompactProfileRendersSlimmerThanDetailedWithoutEditing() async throws
    {

        var card = KanbanCard(id: 91, word: "Plan the next garden season", listTitle: "Garden")
        card.subtitleOverride = "Choose seeds, prepare the beds, and make room for something new"
        let original = card


        ///
        /// @fcn        PlenactBoardDocumentTests.testCompactProfileRendersSlimmerThanDetailedWithoutEditing.row
        /// @brief      Prepare row for the enclosing regression test
        /// @details    Supplies the local fixture for compact Profile Renders Slimmer Than Detailed Without Editing.
        ///
        /// @param[in]  compact  Whether the compact presentation is selected
        ///
        /// @return     (some View) regression fixture view
        ///
        func row(_ compact: Bool) -> some View
        {

            KanbanCardView(
                card: card, height: compact ? 64 : 150, displaySettings: BoardDisplaySettings(),
                compactCards: compact, labelLibrary: .starter,
                onUpdateCard:
                {
                    _ in
                    XCTFail("Rendering must not edit content")
                },
                onDeleteCard:
                {
                    XCTFail("Rendering must not delete")
                },
                onArchiveCard:
                {
                    XCTFail("Rendering must not archive")
                },
                onToggle:
                {
                    XCTFail("Rendering must not complete")
                })
        }

        let compact = UIHostingController(rootView: row(true))
        let detailed = UIHostingController(rootView: row(false))
        compact.safeAreaRegions = [];
        detailed.safeAreaRegions = []
        let compactSize = compact.sizeThatFits(in: CGSize(width: 300, height: 1000))
        let detailedSize = detailed.sizeThatFits(in: CGSize(width: 300, height: 1000))
        XCTAssertLessThan(compactSize.height, detailedSize.height)
        XCTAssertLessThanOrEqual(compactSize.height, 90)
        XCTAssertEqual(card, original)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let preview = UIHostingController(
            rootView: VStack(alignment: .leading, spacing: 16)
            {

                Text("Detailed").font(.headline)
                row(false)
                Text("Compact").font(.headline)
                row(true)
            } .padding(20).background(Color(.systemGroupedBackground)))
        preview.safeAreaRegions = []
        window.frame = CGRect(x: 0, y: 0, width: 340, height: 400)
        window.rootViewController = preview
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(200))
        preview.view.frame = window.bounds
        preview.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image
        {
            _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        let attachment = XCTAttachment(image: image)
        attachment.name = "Detailed and Compact profiles";
        attachment.lifetime = .keepAlways;
        add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-profile-preview.png")
        try image.pngData()?.write(to: url)
        print("PROFILE_PREVIEW_PATH=\(url.path)")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardCardDetailPersistsAndDecodesLegacyAppearance
    /// @brief      Verify that board Card Detail Persists And Decodes Legacy Appearance
    /// @details    Exercises `BoardAppearance.decodeWeek`. Checks `XCTAssertNil(legacy.cardDetail)`;
    ///             `XCTAssertEqual(try BoardAppearance.decodeWeek(data).cardDetail, detail)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testBoardCardDetailPersistsAndDecodesLegacyAppearance() throws
    {

        let legacy = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.cardDetail)
        for detail in BoardCardDetail.allCases
        {

            var appearance = BoardAppearance()
            appearance.cardDetail = detail
            let data = try JSONEncoder().encode(appearance)
            XCTAssertEqual(try BoardAppearance.decodeWeek(data).cardDetail, detail)
            var collection = PersonalCollection(title: "Project", kind: .board)
            collection.boardAppearance = appearance
            XCTAssertEqual(
                try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection))
                .boardAppearance?.cardDetail, detail)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibrarySearchFindsNoteContentAndKeepsCollectionIdentity
    /// @brief      Verify that library Search Finds Note Content And Keeps Collection Identity
    /// @details    Exercises `LabelLibraryStore.load`, `LibrarySearchIndex.results`, `results.compactMap`. Checks
    ///             `XCTAssertEqual(results.count, 2)`; `XCTAssertEqual(Set(results.compactMap(\.ownerID)), [first.id,
    ///             second.id])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLibrarySearchFindsNoteContentAndKeepsCollectionIdentity() throws
    {

        var first = PersonalCollection(title: "Garden", kind: .list)
        var second = PersonalCollection(title: "Home", kind: .list)
        let note = KanbanCard(
            id: 42, word: "Ideas", listTitle: first.lists[0].title,
            descriptionOverride: "Water the seedlings", presentation: .note)
        first.lists[0].cards = [note]
        second.lists[0].cards = [note]
        let labels = LabelLibraryStore.load()
        let results = LibrarySearchIndex.results(query: " seedlings ", collections: [first, second], labels: labels)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(Set(results.compactMap(\.ownerID)), [first.id, second.id])
        XCTAssertEqual(Set(results.map(\.id)).count, 2)
        XCTAssertEqual(results.first?.cardID, 42)
        XCTAssertEqual(results.first?.listID, first.lists[0].id)
        XCTAssertTrue(results.allSatisfy
            {
                $0.weekKey == nil
            })
        first.lists[0].isArchived = true
        second.isArchived = true
        XCTAssertTrue(
            LibrarySearchIndex.results(query: "seedlings", collections: [first, second], labels: labels).isEmpty)
        XCTAssertTrue(LibrarySearchIndex.results(query: "  ", collections: [first, second], labels: labels).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCrossBoardMoveSupportsNotesAndKeepsWithinBoardIdentity
    /// @brief      Verify that cross Board Move Supports Notes And Keeps Within Board Identity
    /// @details    Exercises `CrossBoardCardMovement.move`, `note.replacingLocation`. Checks `XCTAssertEqual(moved,
    ///             note.replacingLocation(id: note.id, listTitle: "Ready"))`;
    ///             `XCTAssertTrue(collections[0].lists[0].cards.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCrossBoardMoveSupportsNotesAndKeepsWithinBoardIdentity() throws
    {

        var note = SampleData.lists[0].cards[0]
        note.displayFormat = .note
        var library = PersonalCollection(title: "Projects", kind: .board)
        library.lists = [
            KanbanList(id: 20, title: "Ideas", cards: [note]),
            KanbanList(id: 21, title: "Ready", cards: [])
        ]
        library.savedCardIDs = [note.id]
        var collections = [library]
        var week = [KanbanList(id: 10, title: "Monday", cards: [])]
        var saved = Set<Int>()
        try CrossBoardCardMovement.move(
            note, from: library.id,
            to: CardMoveDestination(collectionID: library.id, listID: 21, title: "Ready", group: "Library"),
            week: &week, collections: &collections, saved: &saved)
        let moved = try XCTUnwrap(collections[0].lists[1].cards.first)
        XCTAssertEqual(moved, note.replacingLocation(id: note.id, listTitle: "Ready"))
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        XCTAssertEqual(collections[0].savedCardIDs, [note.id])
        try CrossBoardCardMovement.move(
            moved, from: library.id,
            to: CardMoveDestination(collectionID: nil, listID: 10, title: "Monday", group: "Week"),
            week: &week, collections: &collections, saved: &saved)
        XCTAssertEqual(week[0].cards[0].displayFormat, .note)
        XCTAssertEqual(saved, [note.id])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEmojiReactionsValidateOneEmojiAndToggleOnlyTheCurrentAuthor
    /// @brief      Verify that emoji Reactions Validate One Emoji And Toggle Only The Current Author
    /// @details    Exercises `ItemEmojiReaction.validatedEmoji`, `ItemEmojiReaction.toggling`. Checks
    ///             `XCTAssertEqual(ItemEmojiReaction.validatedEmoji(" " + emoji + " "), emoji)`;
    ///             `XCTAssertNil(ItemEmojiReaction.validatedEmoji(invalid))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testEmojiReactionsValidateOneEmojiAndToggleOnlyTheCurrentAuthor() throws
    {

        for emoji in ["❤️", "👍🏽", "👨‍👩‍👧‍👦", "🇺🇸", "1️⃣", "🎉", "🫶"]
        {

            XCTAssertEqual(ItemEmojiReaction.validatedEmoji(" " + emoji + " "), emoji)
        }

        for invalid in ["", "hello", "a", "1", "#", "🎉🎉"]
        {
            XCTAssertNil(ItemEmojiReaction.validatedEmoji(invalid))
        }

        let first = UUID(), second = UUID()
        let others = [ItemEmojiReaction(emoji: "❤️", authorID: second)]
        let added = try XCTUnwrap(ItemEmojiReaction.toggling("❤️", authorID: first, in: others))
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(added.first, others.first)
        let removed = try XCTUnwrap(ItemEmojiReaction.toggling("❤️", authorID: first, in: added))
        XCTAssertEqual(removed, others)
        XCTAssertNil(ItemEmojiReaction.toggling("words", authorID: first, in: added))
        XCTAssertEqual(try JSONDecoder().decode([ItemEmojiReaction].self, from: JSONEncoder().encode(added)), added)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReactionPreviewVisibilityDefaultsAndPersistsWithoutRemovingReactions
    /// @brief      Verify that reaction Preview Visibility Defaults And Persists Without Removing Reactions
    /// @details    Exercises `restored.replacingLocation`. Checks `XCTAssertNil(card.showsReactionsInPreviews)`;
    ///             `XCTAssertEqual(card.previewReactions, [reaction])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testReactionPreviewVisibilityDefaultsAndPersistsWithoutRemovingReactions() throws
    {

        let legacy = Data(#"{"id":1,"word":"Legacy","listTitle":"Today","checklists":[]}"#.utf8)
        var card = try JSONDecoder().decode(KanbanCard.self, from: legacy)
        XCTAssertNil(card.showsReactionsInPreviews)
        let reaction = ItemEmojiReaction(emoji: "🔥", authorID: UUID())
        card.reactions = [reaction]
        XCTAssertEqual(card.previewReactions, [reaction])
        card.showsReactionsInPreviews = false
        XCTAssertTrue(card.previewReactions.isEmpty)
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(restored.showsReactionsInPreviews, false)
        XCTAssertEqual(restored.reactions, [reaction])
        XCTAssertEqual(restored.replacingLocation(id: 42, listTitle: "Tomorrow").showsReactionsInPreviews, false)
        card.showsReactionsInPreviews = true
        XCTAssertEqual(card.previewReactions, [reaction])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReactionIdentityIsStableAndLegacyCardsRemainUnchangedUntilReactedTo
    /// @brief      Verify that reaction Identity Is Stable And Legacy Cards Remain Unchanged Until Reacted To
    /// @details    Exercises `LocalReactionIdentity.current`, `LocalReactionIdentity.forUserAction`,
    ///             `LocalProfileStore.load`. Checks `XCTAssertNil(LocalReactionIdentity.current(in: defaults))`;
    ///             `XCTAssertNil(defaults.object(forKey: LocalReactionIdentity.key))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testReactionIdentityIsStableAndLegacyCardsRemainUnchangedUntilReactedTo() throws
    {

        let suite = "ReactionIdentity." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        XCTAssertNil(LocalReactionIdentity.current(in: defaults))
        XCTAssertNil(defaults.object(forKey: LocalReactionIdentity.key))
        let author = LocalReactionIdentity.forUserAction(in: defaults)
        XCTAssertEqual(LocalReactionIdentity.forUserAction(in: defaults), author)
        XCTAssertEqual(LocalReactionIdentity.current(in: defaults), author)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
        let legacy = Data(#"{"id":1,"word":"Legacy","listTitle":"Today","checklists":[]}"#.utf8)
        var card = try JSONDecoder().decode(KanbanCard.self, from: legacy)
        XCTAssertNil(card.reactions)
        let unchangedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        XCTAssertNil(unchangedJSON["reactions"])
        let before = card
        card.reactions = ItemEmojiReaction.toggling("✅", authorID: author, in: [])
        XCTAssertEqual(card.isTitleChecked, before.isTitleChecked)
        XCTAssertEqual(card.labelIDs, before.labelIDs)
        XCTAssertEqual(card.word, before.word)
        XCTAssertEqual(card.checklists, before.checklists)
        XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card)), card)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLongDetailHeadersRenderWithoutEditingCardsOrNotes
    /// @brief      Verify that long Detail Headers Render Without Editing Cards Or Notes
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertTrue(emissions.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLongDetailHeadersRenderWithoutEditingCardsOrNotes() async throws
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

        for presentation in [ItemPresentation.card, .note]
        {

            let card = KanbanCard(
                id: 901,
                word:
                                            "Make room for today because it is so good, but not enough for me, because of all that it was for you!",
                listTitle: "On the Table, and more useful thoughts for this particular list",
                checklists: [], descriptionOverride: "A little space for a meaningful plan.",
                subtitleOverride:
                                            "On the Table, a quick guide to this List and what I treasure in the rest of this subtitle.",
                presentation: presentation)
            var emissions: [KanbanCard] = []
            let host = UIHostingController(
                rootView: NavigationStack
                {

                    CardDetailView(card: card, onTitleToggle:
                        {
                            emissions.append($0)
                        })
                })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(emissions.isEmpty)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-sliding-header-\(presentation).png")
            try XCTUnwrap(image.pngData()).write(to: url);
            print("SLIDING_HEADER_RENDER=" + url.path)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAppearanceRetainsCardNoteCopiesArchivesAndBothLocalStores
    /// @brief      Verify that appearance Retains Card Note Copies Archives And Both Local Stores
    /// @details    Exercises `card.replacingLocation`, `list.archiveCard`, `collection.rename`. Checks
    ///             `XCTAssertEqual(copy.appearance, appearance)`; `XCTAssertEqual(copy.attachments,
    ///             card.attachments)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testAppearanceRetainsCardNoteCopiesArchivesAndBothLocalStores() async throws
    {

        let suite = "PlenactTests.Appearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let photo = KanbanAttachment(fileName: "appearance-example.jpg", caption: "Keep this caption")
        let appearance = ItemAppearance(accent: .purple, icon: .project, background: .rose)
        var card = KanbanCard(
            id: 1, word: "My plan", listTitle: "Plans", attachments: [photo],
            coverAttachmentID: photo.id, descriptionOverride: "Keep this body", appearance: appearance)
        let copy = card.replacingLocation(id: 2, listTitle: "Plans")
        XCTAssertEqual(copy.appearance, appearance)
        XCTAssertEqual(copy.attachments, card.attachments)
        card.presentation = .note
        var list = KanbanList(id: 0, title: "Plans", cards: [card, copy])
        list.appearance = ItemAppearance(accent: .blue, icon: .upcoming, background: .green)
        list.archiveCard(id: card.id)
        var collection = PersonalCollection(title: "Plans", kind: .list)
        collection.lists = [list]
        collection.rename(to: "Next steps")
        XCTAssertEqual(collection.lists[0].appearance, list.appearance)
        XCTAssertEqual(collection.lists[0].archivedCards[0].appearance, appearance)
        try PersonalCollectionStore.saveChecked([collection], to: defaults)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [collection])
        try KanbanBoardPersistence.saveListsChecked([list], suiteName: suite)
        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restored, [list])
        var decoded = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        decoded.restoreArchivedCard(id: card.id)
        XCTAssertEqual(decoded.cards.first(where:
                {
                    $0.id == card.id
                }), card)
        XCTAssertEqual(CardAttachmentStore.fileNames(in: [decoded]), ["appearance-example.jpg"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAppearanceSheetAndDecoratedNoteLayoutDoNotModifyRecords
    /// @brief      Verify that appearance Sheet And Decorated Note Layout Do Not Modify Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Uses the fixture and assertions below to verify appearance Sheet And
    ///             Decorated Note Layout Do Not Modify Records.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testAppearanceSheetAndDecoratedNoteLayoutDoNotModifyRecords() async throws
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

            for appearance in [
                nil, ItemAppearance(accent: .teal, icon: nil),
                ItemAppearance(accent: nil, icon: .heart),
                ItemAppearance(accent: .purple, icon: .project, background: .rose),
                ItemAppearance(background: .green)
            ]
            {

                let sheet = ItemAppearanceSheet(
                    title: "A long title for my next creative project",
                    appearance: appearance,
                    onOpenCover:
                    {
                        XCTFail("Presentation must not open cover settings")
                    }
                )
                {
                    _ in
                    XCTFail("Presentation must not save appearance")
                    return false
                }

                let controller = UIHostingController(rootView: sheet.environment(\.dynamicTypeSize, textSize))
                let size = CGSize(width: 393, height: 852)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                let image = UIGraphicsImageRenderer(size: size).image
                {
                    _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }

                let attachment = XCTAttachment(image: image)
                attachment.name =
                                                "Appearance-\(appearance?.accent?.rawValue ?? "none")-\(appearance?.icon?.rawValue ?? "none")-\(textSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }

            let note = KanbanCard(
                id: 61, word: "A long title for my next creative project", listTitle: "Ideas",
                presentation: .note, appearance: ItemAppearance(accent: .teal, icon: .notes, background: .blue))
            let controller = UIHostingController(
                rootView: NavigationStack
                {

                    CardDetailView(card: note, onTitleToggle:
                        {
                            _ in
                            XCTFail("Layout must not modify this Note")
                        })
                    .environment(\.dynamicTypeSize, textSize)
                })
            window.rootViewController = controller
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEditingLockRoundTripsAndSurvivesCopyArchiveAndRelocation
    /// @brief      Persist Card and Note locks without changing legacy editable records
    /// @details    Verifies omitted legacy lock keys, explicit locking and unlocking, owner storage, list copying,
    ///             archive restoration, and destination identity changes while retaining attachments and content.
    ///
    /// @return     (Void) no return value
    /// @throws     Fixture encoding, decoding, or checked storage failures
    ///
    func testEditingLockRoundTripsAndSurvivesCopyArchiveAndRelocation() throws
    {

        let suite = "EditingLock." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        for presentation in ItemPresentation.allCases
        {

            var card = KanbanCard(
                id: 6, word: "Protected", listTitle: "Projects", checklists: [],
                attachments: [KanbanAttachment(exampleImage: .mountains)], descriptionOverride: "Keep this writing",
                presentation: presentation, createdAt: Date(timeIntervalSince1970: 1234))
            let legacyData = try JSONEncoder().encode(card)
            XCTAssertNil(
                try XCTUnwrap(JSONSerialization.jsonObject(with: legacyData) as? [String: Any]) ["editingLocked"])
            XCTAssertFalse(try JSONDecoder().decode(KanbanCard.self, from: legacyData).isEditingLocked)
            card.isEditingLocked = true
            XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card)), card)
            XCTAssertTrue(card.replacingLocation(id: 40, listTitle: "Elsewhere").isEditingLocked)
            var list = KanbanList(id: 2, title: "Projects", cards: [card])
            let copy = ListCopying.copy(list, into: [list], crossBoard: true)
            XCTAssertTrue(try XCTUnwrap(copy.cards.first).isEditingLocked)
            XCTAssertEqual(copy.cards.first?.attachments, card.attachments)
            list.archiveCard(id: card.id)
            XCTAssertTrue(try XCTUnwrap(list.archivedCards.first).isEditingLocked)
            list.restoreArchivedCard(id: card.id)
            XCTAssertEqual(list.cards, [card])
            var owner = PersonalCollection(title: "Protected owner", kind: .board)
            owner.lists = [list]
            try PersonalCollectionStore.saveChecked([owner], to: defaults)
            XCTAssertEqual(PersonalCollectionStore.load(from: defaults).first?.lists.first?.cards.first, card)
            card.isEditingLocked = false
            XCTAssertFalse(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card)).isEditingLocked)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLockedContentRejectsEditsAndAllowsOnlyAnUnchangedUnlock
    /// @brief      Protect locked content from stale editors and bulk completion clearing
    /// @details    Rejects title, completion, nested checklist, attachment, and unlock-with-edit proposals. A pure
    ///             unlock remains accepted, and clearing list checkmarks changes only unlocked cards.
    ///
    /// @return     (Void) no return value
    /// @throws     XCTest fixture unwrapping failures
    ///
    func testLockedContentRejectsEditsAndAllowsOnlyAnUnchangedUnlock() throws
    {

        var locked = KanbanCard(
            id: 1, word: "Protected", listTitle: "Tasks", isTitleChecked: true,
            checklists: [KanbanChecklist(title: "Steps", items: ["Retain this step"], completedItemIndices: [0])],
            attachments: [KanbanAttachment(exampleImage: .garden)], isEditingLocked: true)
        XCTAssertTrue(locked.acceptsContentUpdate(locked))
        var edited = locked
        edited.word = "Unexpected replacement"
        XCTAssertFalse(locked.acceptsContentUpdate(edited))
        edited.isEditingLocked = false
        XCTAssertFalse(locked.acceptsContentUpdate(edited))
        edited = locked
        edited.isTitleChecked = false
        XCTAssertFalse(locked.acceptsContentUpdate(edited))
        edited = locked
        edited.checklists = []
        XCTAssertFalse(locked.acceptsContentUpdate(edited))
        edited = locked
        edited.attachments = []
        XCTAssertFalse(locked.acceptsContentUpdate(edited))
        edited = locked
        edited.isEditingLocked = false
        XCTAssertTrue(locked.acceptsContentUpdate(edited))
        var editable = locked.replacingLocation(id: 2, listTitle: "Tasks")
        editable.isEditingLocked = false
        let list = KanbanList(id: 0, title: "Tasks", cards: [locked, editable])
        let (reset, cleared) = ListCheckmarkReset.reset(list)
        XCTAssertEqual(cleared.first, locked)
        XCTAssertFalse(try XCTUnwrap(cleared.last).isTitleChecked)
        var clearedList = list
        clearedList.cards = cleared
        XCTAssertTrue(reset.canRestore(clearedList))
        XCTAssertEqual(reset.restoring(clearedList), list.cards)
        locked.isEditingLocked = false
        XCTAssertTrue(locked.acceptsContentUpdate(edited))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLockedCardAndNoteDetailsDoNotMountEditableTextInputs
    /// @brief      Render locked Cards and Notes for reading without opening editors or saving
    /// @details    Mounts both item kinds with body text, nested checklist content, and an attached picture. The
    ///             locked presentation must not contain enabled text fields or editable text views, and rendering
    ///             must never invoke the owner update callback.
    ///
    /// @return     (Void) no return value
    /// @throws     XCTest fixture setup or cancelled layout delays
    ///
    @MainActor
    func testLockedCardAndNoteDetailsDoNotMountEditableTextInputs() async throws
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


        ///
        /// @fcn        testLockedCardAndNoteDetailsDoNotMountEditableTextInputs.descendants
        /// @brief      Collect hosted native views for input inspection
        /// @details    Includes the root and recursively traverses child views without assuming private containers.
        ///
        /// @param[in]  view  Native subtree to inspect
        ///
        /// @return     ([UIView]) root and all descendants in traversal order
        ///
        func descendants(_ view: UIView) -> [UIView]
        {
            [view] + view.subviews.flatMap(descendants)
        }

        for presentation in ItemPresentation.allCases
        {

            let card = KanbanCard(
                id: 3, word: "Protected writing", listTitle: "Projects",
                checklists: [KanbanChecklist(title: "Read these steps", items: ["Preserved action"])],
                attachments: [KanbanAttachment(exampleImage: .mountains)], descriptionOverride: "The retained body",
                presentation: presentation, isEditingLocked: true)
            var saves = 0
            let host = UIHostingController(
                rootView: CardDetailView(
                    card: card, labelLibrary: .constant(.starter),
                    onTitleToggle:
                    {
                        _ in
                        saves += 1
                    }))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertFalse(descendants(host.view).compactMap
                {
                    $0 as? UITextField
                } .contains
                {
                    $0.isEnabled
                })
            XCTAssertFalse(descendants(host.view).compactMap
                {
                    $0 as? UITextView
                } .contains
                {
                    $0.isEditable
                })
            XCTAssertEqual(saves, 0)
            window.rootViewController = nil
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNoteCardSwitchPreservesTheCompleteRecord()
    /// @brief      Change presentation without losing identity, metadata, or media references
    /// @details    Round-trips a populated Note, then switches it back to its original Card
    ///
    /// @return     (Void) records retained-content assertion failures
    /// @throws     Synthetic fixture encoding or decoding errors
    ///
    func testNoteCardSwitchPreservesTheCompleteRecord() throws
    {


        var original = SampleData.lists[0].cards[0] /* Pre-operation value for preservation checks */
        let attachment = KanbanAttachment(
            fileName: "synthetic-note-reference.jpg", mediaKind: .photo) /* Attachment fixture under test               */

        original.descriptionOverride = "Synthetic idea\nA second paragraph."
        original.subtitleOverride = "Retained context"
        original.isTitleChecked = true
        original.startDate = Date(timeIntervalSince1970: 1200)
        original.dueDate = Date(timeIntervalSince1970: 2400)
        original.attachments = [attachment]
        original.coverAttachmentID = attachment.id
        original.comments = [KanbanComment(author: "Synthetic", body: "Retain this comment")]
        original.members = [.manual("Synthetic")]
        original.labelIDs = ["synthetic-label"]
        original.dismissedActivityIDs = ["addedCard"]

        var note = original /* Note value under verification */
        note.presentation = .note

        let decoded = try JSONDecoder().decode(
            KanbanCard.self, from: JSONEncoder().encode(note)) /* Decoded Card round-trip value */

        XCTAssertEqual(decoded, note)

        var restored = decoded /* Restored value under verification */
        restored.presentation = .card

        XCTAssertEqual(restored, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRichTextFormattingPreservesSelectedRunsAndCardPersistence()
    /// @brief      Verify selected-run rich-text formatting and retained content
    /// @details    Applies bold, italic, and color changes to the selected native text range,
    ///             checks unaffected writing and selection, and round-trips formatted Card and
    ///             comment content through Codable.
    ///
    /// @return     (Void) records rich-text editing and persistence assertions
    /// @throws     Fixture setup, decoding, or checked creation errors propagate to XCTest.
    ///
    @MainActor
    func testRichTextFormattingPreservesSelectedRunsAndCardPersistence() throws
    {

        var stored = "Before selected after"
        let editor = RichTextEditor(placeholder: "Description", text: Binding(get:
                {
                    stored
                }, set:
                {
                    stored = $0
                }))
        let coordinator = editor.makeCoordinator()
        let view = UITextView()
        view.attributedText = PlanRichText.attributed(stored)
        view.selectedRange = NSRange(location: 7, length: 8)
        coordinator.view = view
        coordinator.toggle(.traitBold)
        coordinator.toggle(.traitItalic)
        coordinator.color("Blue")
        XCTAssertEqual(view.selectedRange, NSRange(location: 7, length: 8))
        XCTAssertEqual(PlanRichText.plain(stored), "Before selected after")
        let selected = PlanRichText.attributed(stored).attributes(at: 7, effectiveRange: nil)
        let font = try XCTUnwrap(selected[.font] as? UIFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitItalic))
        XCTAssertEqual(selected[NSAttributedString.Key("PlenactColor")] as? String, "Blue")
        XCTAssertFalse(
            (PlanRichText.attributed(stored).attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontDescriptor
            .symbolicTraits.contains(.traitBold) ?? true)
        var card = KanbanList(id: 1, title: "Ideas", cards: []).makeItem(id: 2, title: "Formatted", description: stored)
        card.comments = [KanbanComment(author: "Alex", body: stored)]
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(decoded.descriptionOverride, stored)
        XCTAssertEqual(decoded.comments.first?.body, stored)
        XCTAssertTrue(NoteTextSharing.text(for: decoded).contains("Before selected after"))
        XCTAssertFalse(NoteTextSharing.text(for: decoded).contains(PlanRichText.prefix))
        coordinator.toggle(.traitBold)
        coordinator.toggle(.traitItalic)
        coordinator.color("Default")
        XCTAssertEqual(stored, "Before selected after")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRichTextEditorProvidesAccessibleKeyboardToolbar
    /// @brief      Verify that rich Text Editor Provides Accessible Keyboard Toolbar
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`, `.constant`.
    ///             Checks `XCTAssertNotNil(controls.first(where: { $0.accessibilityLabel == "Font and formatting"
    ///             })?.menu)`; `XCTAssertEqual(text.text, "A multiline description\nwith a second line")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testRichTextEditorProvidesAccessibleKeyboardToolbar() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(
            rootView: RichTextEditor(
                placeholder: "Description", text: .constant("A multiline description\nwith a second line")))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            previousWindow?.makeKeyAndVisible()
        }

        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))


        ///
        /// @fcn        PlenactBoardDocumentTests.testRichTextEditorProvidesAccessibleKeyboardToolbar.editor
        /// @brief      Find editor in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextView. Returns the first qualifying match, or
        ///             nil when none is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UITextView?) matching or resolved value, or nil when unavailable
        ///
        func editor(in view: UIView) -> UITextView?
        {

            if let text = view as? UITextView
            {
                return text
            }

            return view.subviews.lazy.compactMap
            {
                editor(in: $0)
            } .first
        }

        let text = try XCTUnwrap(editor(in: host.view))
        let toolbar = try XCTUnwrap(text.inputAccessoryView as? PlenactKeyboardToolbar)


        ///
        /// @fcn        PlenactBoardDocumentTests.testRichTextEditorProvidesAccessibleKeyboardToolbar.buttons
        /// @brief      Find buttons in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIButton. Returns all collected matches in hierarchy
        ///             order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIButton]) resulting values in the ordering described above
        ///
        func buttons(in view: UIView) -> [UIButton]
        {

            (view as? UIButton).map
            {
                [$0]
            }
            ?? view.subviews.flatMap
            {
                buttons(in: $0)
            }

        }

        let controls = buttons(in: toolbar)
        XCTAssertEqual(
            controls.compactMap(\.accessibilityLabel),
            [
                                "Return from Card or Note", "Previous item in this list", "Next item in this list", "Undo text edit",
                                "Redo text edit", "Add attachment", "Add checklist", "Font and formatting", "Hide keyboard"
            ])
        XCTAssertNotNil(controls.first(where:
                {
                    $0.accessibilityLabel == "Font and formatting"
                })?.menu)
        XCTAssertEqual(text.text, "A multiline description\nwith a second line")
        XCTAssertGreaterThan(text.sizeThatFits(CGSize(width: 300, height: 1000)).height, 40)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRichTextTypingStylesAndLegacyText
    /// @brief      Verify that rich Text Typing Styles And Legacy Text
    /// @details    Exercises `editor.makeCoordinator`, `PlanRichText.attributed`, `UIFont.preferredFont`. Checks
    ///             `XCTAssertEqual(stored, "Legacy plain text 😊")`; `XCTAssertTrue((view.typingAttributes[.font] as?
    ///             UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)`.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func testRichTextTypingStylesAndLegacyText()
    {

        var stored = "Legacy plain text 😊"
        let editor = RichTextEditor(placeholder: "Comment", text: Binding(get:
                {
                    stored
                }, set:
                {
                    stored = $0
                }))
        let coordinator = editor.makeCoordinator()
        let view = UITextView()
        view.attributedText = PlanRichText.attributed(stored)
        view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
        view.typingAttributes = [.font: UIFont.preferredFont(forTextStyle: .body)]
        coordinator.view = view
        coordinator.toggle(.traitBold)
        coordinator.color("Purple")
        XCTAssertEqual(stored, "Legacy plain text 😊")
        XCTAssertTrue(
            (view.typingAttributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertEqual(view.typingAttributes[NSAttributedString.Key("PlenactColor")] as? String, "Purple")
        XCTAssertEqual(PlanRichText.encode(PlanRichText.attributed(stored)), stored)
        XCTAssertEqual(PlanRichText.plain("plenact-rich-v1:invalid"), "plenact-rich-v1:invalid")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testChecklistEditingSelectsWholeExistingItem
    /// @brief      Verify that checklist Editing Selects Whole Existing Item
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertTrue(field.becomeFirstResponder())`;
    ///             `XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testChecklistEditingSelectsWholeExistingItem() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var text = "Cut or replace this item 😊"
        var focused = false
        let host = UIHostingController(
            rootView: ChecklistTextField(
                text: Binding(get:
                    {
                        text
                    }, set:
                    {
                        text = $0
                    }),
                focus: Binding(get:
                    {
                        focused
                    }, set:
                    {
                        focused = $0
                    })))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer
        {
            window.endEditing(true);
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        host.view.layoutIfNeeded()


        ///
        /// @fcn        PlenactBoardDocumentTests.testChecklistEditingSelectsWholeExistingItem.find
        /// @brief      Find find in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextField. Returns the first qualifying match, or
        ///             nil when none is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UITextField?) matching or resolved value, or nil when unavailable
        ///
        func find(in view: UIView) -> UITextField?
        {

            if let field = view as? UITextField
            {
                return field
            }

            return view.subviews.lazy.compactMap
            {
                find(in: $0)
            } .first
        }

        let field = try XCTUnwrap(find(in: host.view))
        XCTAssertTrue(field.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(150))
        let selection = try XCTUnwrap(field.selectedTextRange)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 0)
        XCTAssertEqual(field.offset(from: selection.start, to: selection.end), (text as NSString).length)
        XCTAssertEqual(field.text, text)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNotePresentationSurvivesPersonalPersistenceRenameAndArchive()
    /// @brief      Retain Note choices in local active and archived content
    /// @details    Uses an isolated defaults suite and checks list defaults, bookmark IDs, and renaming
    ///
    /// @return     (Void) records persistence/retention assertion failures
    /// @throws     Defaults setup, persistence, or Codable errors
    ///
    func testNotePresentationSurvivesPersonalPersistenceRenameAndArchive() throws
    {


        let suite = "Plenact.NotePersistenceTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }


        var collection = PersonalCollection(
            title: "Synthetic ideas", kind: .list) /* Collection state under verification */
        collection.lists[0].newItemPresentation = .note
        let note = collection.lists[0].makeItem(
            id: 20, title: "Synthetic thought", description: "Retain body") /* Newly created Note value */
        collection.lists[0].cards = [note]
        collection.savedCardIDs = [note.id]

        collection.lists[0].archiveCard(id: note.id)

        collection.rename(to: "Renamed ideas")

        XCTAssertEqual(collection.lists[0].newItemPresentation, .note)
        XCTAssertEqual(collection.lists[0].archivedCards[0].presentation, .note)
        XCTAssertEqual(collection.lists[0].archivedCards[0].listTitle, "Renamed ideas")

        try PersonalCollectionStore.saveChecked([collection], to: defaults)

        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [collection])


        var restored = collection.lists[0] /* Restored value under verification */

        restored.restoreArchivedCard(id: note.id)

        XCTAssertEqual(restored.cards[0].presentation, .note)
        XCTAssertEqual(restored.cards[0].attachments, note.attachments)
        XCTAssertEqual(collection.savedCardIDs, [note.id])

        let week = PersonalCollection.archivedWeekBoard(
            lists: [restored], savedCardIDs: [note.id]) /* Archived weekly-board fixture    */
        let decoded = try JSONDecoder().decode(
            PersonalCollection.self, from: JSONEncoder().encode(week)) /* Decoded archived-week collection */

        XCTAssertEqual(decoded.lists[0], restored)
        XCTAssertEqual(restored.cards[0].createdAt, note.createdAt)
        XCTAssertNotNil(restored.cards[0].createdAt)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalListsDefaultNewItemsToNotesWithoutConvertingExistingRecords()
    /// @brief      Use Note defaults for personal Lists while retaining existing content
    /// @details    Covers new and legacy List defaults, preserved Card records, and unchanged
    ///             personal Board defaults
    ///
    /// @return     (Void) records assertion failures for defaults and retained content
    ///
    func testPersonalListsDefaultNewItemsToNotesWithoutConvertingExistingRecords()
    {


        var collection = PersonalCollection(
            title: "Synthetic ideas", kind: .list) /* Personal List receiving its default              */
        let existingCard = KanbanCard(
            id: 20, word: "Keep this Card", listTitle: collection.title) /* Existing Card content that must remain unchanged */

        XCTAssertEqual(collection.lists[0].newItemPresentation, .note)

        collection.lists[0].cards = [existingCard]
        collection.lists[0].newItemPresentation = .card
        collection.useNoteDefaultsForPersonalLists()

        XCTAssertEqual(collection.lists[0].newItemPresentation, .note)
        XCTAssertEqual(collection.lists[0].cards, [existingCard])
        XCTAssertEqual(collection.lists[0].makeItem(id: 21, title: "New thought").presentation, .note)

        var board = PersonalCollection(
            title: "Synthetic board", kind: .board) /* Multi-list collection preserving configurable defaults */

        board.lists[0].newItemPresentation = .card
        board.useNoteDefaultsForPersonalLists()

        XCTAssertEqual(board.lists[0].newItemPresentation, .card)
    }

}
