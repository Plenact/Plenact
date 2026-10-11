// --------------------------------------------------------------------------------------------------
// @file       PlenactBoardDocumentTests.swift
// @brief      Board contracts, local persistence, and presentation regression tests
// @details    Covers versioned shared-demo documents, archive/restore compatibility, isolated
//             preference stores, canonical search/selection helpers, background-save failures,
//             and hosted SwiftUI sizing/re-layout. API activity uses an in-process URLProtocol
//
// @notes      Synthetic fixtures do not access the live demo database. Corruption tests verify
//             load-time byte retention, not protection against a later write to fallback content
//
// --------------------------------------------------------------------------------------------------
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

    @MainActor
    func testBoardOptionsPopoverLayoutDoesNotInvokeDestructiveActions() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for size in [DynamicTypeSize.large, .accessibility3] {
            let menu = BoardOptionsPopover(canJumpFirst: true, canJumpLast: true, hasAppearance: true,
                canArchive: true, canDelete: true, deleteTitle: "Delete Board") { _ in
                    XCTFail("Presenting options must not perform an action")
                }
            let host = UIHostingController(rootView: menu
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding().environment(\.dynamicTypeSize, size))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let snapshot = XCTAttachment(image: image)
            snapshot.name = "BoardOptions-\(size)"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }
    }

    func testLibraryWeekExampleCreatesIndependentDraftWithoutReplacingWeek() throws {
        let original = SampleData.lists
        let first = PersonalCollection.exampleWeek(existingTitles: ["Week View"])
        let second = PersonalCollection.exampleWeek(existingTitles: [])
        XCTAssertEqual(first.kind, .board)
        XCTAssertEqual(first.lists, original)
        XCTAssertEqual(first.lists.count, 7)
        XCTAssertNotEqual(first.title, "Week View")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(SampleData.lists, original)
        XCTAssertEqual(try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(first)), first)
    }

    func testMixedListTemplatesRetainFormatsAndCreateIndependentDrafts() throws {
        for template in MixedListTemplate.allCases {
            let draft = template.makeCollection(existingTitles: [template.rawValue])
            let second = template.makeCollection(existingTitles: [])
            XCTAssertNotEqual(draft.id, second.id)
            XCTAssertNotEqual(draft.title, template.rawValue)
            XCTAssertEqual(draft.lists.count, 1)
            let cards = draft.lists[0].cards
            XCTAssertEqual(Set(cards.map(\.displayFormat)), Set(ItemDisplayFormat.allCases))
            XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
            XCTAssertTrue(cards.allSatisfy { $0.listTitle == draft.title && $0.startDate == nil && $0.dueDate == nil })
            XCTAssertTrue(cards.filter { $0.displayFormat == .note }.allSatisfy { $0.presentation == .note })
            let picture = try XCTUnwrap(cards.first { $0.displayFormat == .picture })
            XCTAssertEqual(picture.coverAttachment?.exampleImage, template.illustration)
            XCTAssertTrue(CardAttachmentStore.fileNames(in: draft.lists).isEmpty)
            XCTAssertEqual(try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(draft)), draft)
        }
    }

    @MainActor
    func testPlanningHostedCalendarLayoutDoesNotPersistBrowsing() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let week = DatedPlanningWeek.make(for: .now, lists: SampleData.lists)
        let original = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        var saveCount = 0
        let access = PlanningCalendarAccess(document: original, library: [], saveWeek: { _ in saveCount += 1; return true },
            openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in saveCount += 1; return true })
        for size in [DynamicTypeSize.large, .accessibility3] {
            let controller = UIHostingController(rootView: PlanningCalendarView().environment(\.planningCalendarAccess, access)
                .environment(\.dynamicTypeSize, size))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Planning-Calendar-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(saveCount, 0, "Opening and laying out the Calendar must never save a week")
            XCTAssertEqual(access.document, original)
        }
    }

    private func planningTestCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        return calendar
    }

    func testPlanningMigrationPreservesExistingContentAndAssociatesSevenDates() throws {
        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        let original = SampleData.lists
        let saved: Set<Int> = [original[0].cards[0].id]
        let week = DatedPlanningWeek.make(for: date, lists: original, saved: saved, calendar: calendar)
        XCTAssertEqual(week.startKey, "2026-10-04")
        XCTAssertEqual(week.collection.lists, original)
        XCTAssertEqual(week.collection.savedCardIDs, saved)
        XCTAssertEqual(week.dayListIDs.count, 7)
        XCTAssertEqual(week.list(on: date)?.title, "Saturday")
        XCTAssertEqual(Set(week.dayListIDs.values).count, 7)
    }

    func testPlanningDateAssociationSurvivesRenamingAndDoesNotOverwriteArchivedDay() throws {
        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let id = try XCTUnwrap(week.dayListIDs["2026-10-10"])
        let index = try XCTUnwrap(week.collection.lists.firstIndex { $0.id == id })
        try week.collection.lists[index].edit(title: "Family plans", subtitle: nil)
        XCTAssertEqual(week.list(on: date)?.title, "Family plans")
        week.collection.lists[index].isArchived = true
        let retained = week.collection.lists[index]
        let replacement = week.prepareDay(date)
        XCTAssertNotEqual(replacement, id)
        XCTAssertEqual(week.collection.lists[index], retained)
        XCTAssertEqual(week.list(on: date)?.id, replacement)
    }

    func testPlanningRolloverPreservesPreviousWeekAndReusesFuturePlans() throws {
        let calendar = planningTestCalendar()
        let today = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        let nextDate = try XCTUnwrap(PlanningDate.date("2026-10-11", calendar: calendar))
        let current = DatedPlanningWeek.make(for: today, lists: SampleData.lists, saved: [SampleData.lists[0].cards[0].id], calendar: calendar)
        var future = DatedPlanningWeek.make(for: nextDate, calendar: calendar)
        let dayID = try XCTUnwrap(future.list(on: nextDate)?.id)
        let index = try XCTUnwrap(future.collection.lists.firstIndex { $0.id == dayID })
        let card = SampleData.lists[0].cards[0].replacingLocation(id: 90, listTitle: "Sunday")
        future.collection.lists[index].cards = [card]
        future.collection.savedCardIDs = [90]
        var document = PlanningCalendarDocument(currentWeekKey: current.startKey, firstWeekday: 1, weeks: [current, future])
        let next = document.rollForward(to: nextDate, currentLists: current.collection.lists, saved: current.collection.savedCardIDs, calendar: calendar)
        XCTAssertEqual(next.id, future.id)
        XCTAssertEqual(next.collection, future.collection)
        XCTAssertEqual(document.weeks.count, 2)
        XCTAssertEqual(document.weeks.first { $0.startKey == current.startKey }, current)
        XCTAssertEqual(document.currentWeekKey, "2026-10-11")
        let repeated = document.rollForward(to: nextDate, currentLists: next.collection.lists, saved: next.collection.savedCardIDs, calendar: calendar)
        XCTAssertEqual(repeated.id, next.id)
        XCTAssertEqual(document.weeks.count, 2)
    }

    func testPlanningEmptyBrowsingDoesNotPersistAndExplicitSaveRoundTrips() throws {
        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        let futureDate = try XCTUnwrap(PlanningDate.date("2026-12-25", calendar: calendar))
        let current = DatedPlanningWeek.make(for: date, calendar: calendar)
        var document = PlanningCalendarDocument(currentWeekKey: current.startKey, firstWeekday: 1, weeks: [current])
        let suite = "Plenact.PlanningTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try PlanningCalendarStore.save(document, to: defaults)
        let bytes = defaults.data(forKey: PlanningCalendarStore.key)
        XCTAssertNil(document.week(for: futureDate, calendar: calendar))
        var preview = DatedPlanningWeek.make(for: futureDate, calendar: calendar)
        XCTAssertFalse(preview.hasContent)
        XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), bytes)
        preview.explicitlySaved = true
        document.upsert(preview)
        try PlanningCalendarStore.save(document, to: defaults)
        XCTAssertEqual(try PlanningCalendarStore.load(from: defaults), document)
        XCTAssertEqual(document.currentWeekKey, current.startKey)
    }

    func testPlanningPersistenceRetainsCorruptDocumentWithoutOverwrite() throws {
        let suite = "Plenact.PlanningCorruption.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data("retained unreadable calendar".utf8)
        defaults.set(bytes, forKey: PlanningCalendarStore.key)
        let week = DatedPlanningWeek.make(for: .now)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        XCTAssertThrowsError(try PlanningCalendarStore.save(document, to: defaults))
        XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), bytes)
    }

    func testPlanningDateKeysAcrossDSTAndYearBoundary() throws {
        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-01", calendar: calendar))
        let days = PlanningDate.days(in: PlanningDate.weekKey(date, calendar: calendar), calendar: calendar)
        XCTAssertEqual(days.map { PlanningDate.key($0, calendar: calendar) },
                       ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"])
        let yearEnd = try XCTUnwrap(PlanningDate.date("2026-12-31", calendar: calendar))
        XCTAssertEqual(PlanningDate.weekKey(yearEnd, calendar: calendar), "2026-12-27")
        XCTAssertEqual(PlanningDate.days(in: "2026-12-27", calendar: calendar).last.map { PlanningDate.key($0, calendar: calendar) }, "2027-01-02")
    }

    func testPlanningSharedSearchRetainsScopesAndOwnerQualifiedIdentities() throws {
        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        var library = PersonalCollection(title: "Research", kind: .list)
        let card = SampleData.lists[0].cards[0]
        week.collection.lists[0].cards = [card]
        library.lists[0].cards = [card]
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]),
            library: [library], saveWeek: { _ in true }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in true })
        let results = PlanningSharedSearchIndex.results(query: card.word, scope: .all, access: access, labels: LabelLibraryStore.load())
        XCTAssertEqual(results.count, 2)
        XCTAssertNotEqual(results[0].id, results[1].id)
        XCTAssertEqual(Set(results.compactMap(\.ownerID)), [week.id, library.id])
        XCTAssertEqual(results.filter { $0.weekKey != nil }.count, 1)
        let boardResults = PlanningSharedSearchIndex.results(query: library.lists[0].title, scope: .boards, access: access, labels: LabelLibraryStore.load())
        XCTAssertTrue(boardResults.contains { $0.ownerID == library.id && $0.cardID == nil })
    }

    func testPlanningCardsMoveBetweenDatedWeekLibraryAndCurrentWeek() throws {
        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-12-25", calendar: calendar))
        var future = DatedPlanningWeek.make(for: date, calendar: calendar)
        let original = SampleData.lists[0].cards[0]
        var current = [KanbanList(id: 1, title: "Monday", cards: [original])]
        var library = PersonalCollection(title: "Research", kind: .list)
        library.lists[0].cards = []
        var owners = [future.collection, library]
        var saved: Set<Int> = [original.id]
        let destination = try XCTUnwrap(future.list(on: date))
        try CrossBoardCardMovement.move(original, from: nil,
            to: CardMoveDestination(collectionID: future.id, listID: destination.id, title: destination.title, group: "Calendar"),
            week: &current, collections: &owners, saved: &saved)
        future.collection = owners[0]
        let moved = try XCTUnwrap(future.list(on: date)?.cards.first)
        XCTAssertEqual(moved, original.replacingLocation(id: original.id, listTitle: destination.title))
        XCTAssertTrue(current[0].cards.isEmpty)
        XCTAssertTrue(future.collection.savedCardIDs.contains(moved.id))
        try CrossBoardCardMovement.move(moved, from: future.id,
            to: CardMoveDestination(collectionID: library.id, listID: library.lists[0].id, title: library.title, group: "Library"),
            week: &current, collections: &owners, saved: &saved)
        let inLibrary = try XCTUnwrap(owners[1].lists[0].cards.first)
        try CrossBoardCardMovement.move(inLibrary, from: library.id,
            to: CardMoveDestination(collectionID: nil, listID: 1, title: "Monday", group: "Week"),
            week: &current, collections: &owners, saved: &saved)
        XCTAssertEqual(current[0].cards.first, original.replacingLocation(id: original.id, listTitle: "Monday"))
        XCTAssertEqual(saved, [original.id])
        XCTAssertTrue(owners[1].lists[0].cards.isEmpty)
    }



    func testCrossBoardMoveSupportsNotesAndKeepsWithinBoardIdentity() throws {
        var note = SampleData.lists[0].cards[0]
        note.displayFormat = .note
        var library = PersonalCollection(title: "Projects", kind: .board)
        library.lists = [KanbanList(id: 20, title: "Ideas", cards: [note]),
                         KanbanList(id: 21, title: "Ready", cards: [])]
        library.savedCardIDs = [note.id]
        var collections = [library]
        var week = [KanbanList(id: 10, title: "Monday", cards: [])]
        var saved = Set<Int>()
        try CrossBoardCardMovement.move(note, from: library.id,
            to: CardMoveDestination(collectionID: library.id, listID: 21, title: "Ready", group: "Library"),
            week: &week, collections: &collections, saved: &saved)
        let moved = try XCTUnwrap(collections[0].lists[1].cards.first)
        XCTAssertEqual(moved, note.replacingLocation(id: note.id, listTitle: "Ready"))
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        XCTAssertEqual(collections[0].savedCardIDs, [note.id])
        try CrossBoardCardMovement.move(moved, from: library.id,
            to: CardMoveDestination(collectionID: nil, listID: 10, title: "Monday", group: "Week"),
            week: &week, collections: &collections, saved: &saved)
        XCTAssertEqual(week[0].cards[0].displayFormat, .note)
        XCTAssertEqual(saved, [note.id])
    }

    func testCrossBoardCardMoveRoundTripPreservesContentAndBookmark() throws {
        let original = SampleData.lists[0].cards[0]
        var week = [KanbanList(id: 10, title: "Monday", cards: [original])]
        var library = PersonalCollection(title: "Ideas", kind: .list)
        library.lists = [KanbanList(id: 20, title: "Ideas", cards: [])]
        var collections = [library]
        var saved: Set<Int> = [original.id]
        try CrossBoardCardMovement.move(original, from: nil,
            to: CardMoveDestination(collectionID: library.id, listID: 20, title: "Ideas", group: "Library"),
            week: &week, collections: &collections, saved: &saved)
        let moved = try XCTUnwrap(collections[0].lists[0].cards.first)
        XCTAssertEqual(moved, original.replacingLocation(id: original.id, listTitle: "Ideas"))
        XCTAssertTrue(week[0].cards.isEmpty)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(collections[0].savedCardIDs.contains(moved.id))
        try CrossBoardCardMovement.move(moved, from: library.id,
            to: CardMoveDestination(collectionID: nil, listID: 10, title: "Monday", group: "Week"),
            week: &week, collections: &collections, saved: &saved)
        XCTAssertEqual(week[0].cards.first, original.replacingLocation(id: original.id, listTitle: "Monday"))
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        XCTAssertTrue(collections[0].savedCardIDs.isEmpty)
        XCTAssertTrue(saved.contains(original.id))
    }

    func testCrossBoardMoveReservesArchivedIdentitiesAndPreservesFormat() throws {
        var original = SampleData.lists[0].cards[0]
        original.displayFormat = .picture
        var week = [KanbanList(id: 10, title: "Monday", cards: [])]
        week[0].archivedCards = [original]
        var library = PersonalCollection(title: "Ideas", kind: .list)
        library.lists = [KanbanList(id: 20, title: "Ideas", cards: [original])]
        library.savedCardIDs = [original.id]
        var collections = [library]
        var saved = Set<Int>()
        try CrossBoardCardMovement.move(original, from: library.id,
            to: CardMoveDestination(collectionID: nil, listID: 10, title: "Monday", group: "Week"),
            week: &week, collections: &collections, saved: &saved)
        let moved = try XCTUnwrap(week[0].cards.first)
        XCTAssertNotEqual(moved.id, original.id)
        XCTAssertEqual(moved, original.replacingLocation(id: moved.id, listTitle: "Monday"))
        XCTAssertEqual(week[0].archivedCards, [original])
        XCTAssertTrue(saved.contains(moved.id))
    }

    func testCrossBoardMoveRejectsUnavailableDestinationWithoutMutation() throws {
        let card = SampleData.lists[0].cards[0]
        var week = [KanbanList(id: 10, title: "Monday", cards: [card])]
        let before = week
        var collections = [PersonalCollection]()
        var saved: Set<Int> = [card.id]
        XCTAssertThrowsError(try CrossBoardCardMovement.move(card, from: nil,
            to: CardMoveDestination(collectionID: UUID(), listID: 20, title: "Missing", group: "Library"),
            week: &week, collections: &collections, saved: &saved))
        XCTAssertEqual(week, before)
        XCTAssertEqual(saved, [card.id])
        XCTAssertTrue(collections.isEmpty)
    }


    @MainActor
    func testEditorBannerDoesNotInsertNativeNavigationBar() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }

        func navigationController(in controller: UIViewController) -> UINavigationController? {
            if let navigation = controller as? UINavigationController {
                return navigation
            }
            return controller.children.compactMap { navigationController(in: $0) }.first
        }

        for isNote in [false, true] {
            for background in [nil, ItemAccent.orange] {
                let card = KanbanCard(
                    id: 94, word: "Synthetic banner", listTitle: "Friday",
                    presentation: isNote ? .note : .card,
                    appearance: background.map { ItemAppearance(background: $0) }
                )
                var emitted: [KanbanCard] = []
                let controller = UIHostingController(rootView: NavigationStack {
                    CardDetailView(card: card, onTitleToggle: { emitted.append($0) })
                })
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))

                let navigation = try XCTUnwrap(navigationController(in: controller))
                XCTAssertTrue(navigation.isNavigationBarHidden, "The custom editor controls must not gain an empty native bar")
                XCTAssertTrue(emitted.isEmpty, "Banner layout must not change the record")
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let snapshot = XCTAttachment(image: image)
                snapshot.name = "Editor-banner-\(isNote ? "Note" : "Card")-\(background?.rawValue ?? "none")"
                snapshot.lifetime = .keepAlways
                add(snapshot)
            }
        }
    }

    @MainActor
    func testBannerBackgroundFillsProposedWidthWithoutLegacyAccentDecoration() {
        let background = ItemAppearance(background: .green)
        for scheme in [ColorScheme.light, .dark] {
            let controller = UIHostingController(rootView:
                HStack { Text("Plan") }
                    .itemBannerBackground(background)
                    .environment(\.colorScheme, scheme)
            )
            let size = controller.sizeThatFits(in: CGSize(width: 320, height: 200))
            XCTAssertEqual(size.width, 320, accuracy: 1)
            XCTAssertLessThan(size.height, 100)
        }
        let mark = UIHostingController(rootView: ItemAppearanceMark(appearance: ItemAppearance(accent: .green)))
        let size = mark.sizeThatFits(in: CGSize(width: 320, height: 200))
        XCTAssertEqual(size.width, 0, accuracy: 1)
        XCTAssertEqual(size.height, 0, accuracy: 1)
    }

    func testBannerBackgroundIsIndependentAndBackwardCompatible() throws {
        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data(#"{"accent":"teal","icon":"heart"}"#.utf8))
        XCTAssertEqual(legacy, ItemAppearance(accent: .teal, icon: .heart))
        XCTAssertNil(legacy.background)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(json["background"])
        for color in ItemAccent.allCases {
            let backgroundOnly = ItemAppearance(background: color)
            XCTAssertFalse(backgroundOnly.isEmpty)
            let card = KanbanCard(id: 41, word: "A plan", listTitle: "Ideas", appearance: backgroundOnly)
            XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card)), card)
            XCTAssertEqual(card.replacingLocation(id: 42, listTitle: "Next").appearance, backgroundOnly)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ItemAppearance.self, from: Data(#"{"background":"invalid"}"#.utf8)))
        var combined = ItemAppearance(accent: .blue, icon: .notes, background: .rose)
        combined.background = nil
        XCTAssertEqual(combined, ItemAppearance(accent: .blue, icon: .notes))
        combined = ItemAppearance()
        XCTAssertTrue(combined.isEmpty)
    }

    func testTodayInitialTaskFocusSkipsCompletedAndNonTaskFormatsWithoutReordering() {
        let cards = [
            KanbanCard(id: 1, word: "Done", listTitle: "Plans", isTitleChecked: true),
            KanbanCard(id: 2, word: "Note", listTitle: "Plans", presentation: .note),
            KanbanCard(id: 3, word: "---", listTitle: "Plans"),
            KanbanCard(id: 4, word: "Picture", listTitle: "Plans", listDisplayFormat: .picture),
            KanbanCard(id: 5, word: "Next task", listTitle: "Plans"),
            KanbanCard(id: 6, word: "Later task", listTitle: "Plans")
        ]
        var list = KanbanList(id: 0, title: "Plans", cards: cards)
        XCTAssertEqual(list.firstUncheckedTaskID, 5)
        XCTAssertEqual(list.cards, cards)
        list.cards[4].isTitleChecked = true
        XCTAssertEqual(list.firstUncheckedTaskID, 6)
        list.cards[5].isTitleChecked = true
        XCTAssertNil(list.firstUncheckedTaskID)
        list.cards = []
        XCTAssertNil(list.firstUncheckedTaskID)
        list.cards = cards
        list.isArchived = true
        XCTAssertNil(list.firstUncheckedTaskID)
    }

    func testBoardCardBackgroundIsOptionalAndIndependentOfItemAppearance() throws {
        let legacy = try JSONDecoder().decode(BoardAppearance.self, from: Data(#"{"bannerBackground":"blue","listBackground":"green"}"#.utf8))
        XCTAssertNil(legacy.cardBackground)
        for tint in KanbanListTint.allCases {
            let theme = BoardAppearance(cardBackground: tint)
            XCTAssertEqual(try BoardAppearance.decodeWeek(JSONEncoder().encode(theme)), theme)
            let itemAppearance = ItemAppearance(icon: .home, background: .rose)
            XCTAssertEqual(theme.resolved(itemAppearance), itemAppearance)
        }
        XCTAssertThrowsError(try BoardAppearance.decodeWeek(Data(#"{"cardBackground":"invalid"}"#.utf8)))
    }

    func testBoardAppearanceInheritanceAndApplyingAllPreserveContent() throws {
        let theme = BoardAppearance(bannerBackground: .blue, listBackground: .green)
        XCTAssertEqual(theme.resolved(nil).background, .blue)
        XCTAssertEqual(theme.resolved(nil).listBackground, .green)
        let override = ItemAppearance(icon: .home, background: .rose, listBackground: .neutral)
        XCTAssertEqual(theme.resolved(override), override)
        let partial = ItemAppearance(icon: .home, background: .purple)
        XCTAssertEqual(theme.resolved(partial).listBackground, .green)
        XCTAssertEqual(theme.resolved(partial).background, .purple)
        let card = KanbanCard(id: 7, word: "Retained plan", listTitle: "Plans",
                              descriptionOverride: "Keep my writing")
        var list = KanbanList(id: 3, title: "Plans", cards: [card], archivedCards: [card.replacingLocation(id: 8, listTitle: "Plans")])
        list.appearance = override
        list.newItemPresentation = .note
        var archived = list
        archived.isArchived = true
        let inherited = BoardAppearance.inheritingLists([list, archived])
        XCTAssertEqual(inherited[0].appearance, ItemAppearance(icon: .home))
        XCTAssertEqual(inherited[1].appearance, ItemAppearance(icon: .home))
        XCTAssertTrue(inherited[1].isArchived)
        XCTAssertEqual(inherited[0].cards, list.cards)
        XCTAssertEqual(inherited[0].archivedCards, list.archivedCards)
        XCTAssertEqual(inherited[0].newItemPresentation, .note)
        XCTAssertEqual(theme.resolved(inherited[0].appearance).background, .blue)
        let fresh = KanbanList(id: 99, title: "New list", cards: [])
        XCTAssertEqual(theme.resolved(fresh.appearance).listBackground, .green)
        XCTAssertEqual(BoardAppearance.inheritingLists(inherited), inherited)
    }

    func testIndependentBoardAppearancePersistsAndAcceptsLegacyCollections() throws {
        let suite = "PlenactTests.BoardAppearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let week = BoardAppearance(bannerBackground: .blue, listBackground: .orange, cardBackground: .green)
        defaults.set(try JSONEncoder().encode(week), forKey: BoardAppearance.weekStorageKey)
        XCTAssertEqual(try BoardAppearance.decodeWeek(XCTUnwrap(defaults.data(forKey: BoardAppearance.weekStorageKey))), week)
        XCTAssertEqual(try BoardAppearance.decodeWeek(Data()), BoardAppearance())
        XCTAssertThrowsError(try BoardAppearance.decodeWeek(Data("invalid".utf8)))
        XCTAssertThrowsError(try BoardAppearance.decodeWeek(Data(#"{"bannerBackground":"invalid"}"#.utf8)))
        var first = PersonalCollection(title: "First", kind: .board)
        first.boardAppearance = BoardAppearance(bannerBackground: .purple, listBackground: .red, cardBackground: .orange)
        var second = PersonalCollection(title: "Second", kind: .board)
        second.boardAppearance = BoardAppearance(bannerBackground: .green, listBackground: .blue, cardBackground: .red)
        second.isArchived = true
        try PersonalCollectionStore.saveChecked([first, second], to: defaults)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [first, second])
        XCTAssertEqual(try BoardAppearance.decodeWeek(XCTUnwrap(defaults.data(forKey: BoardAppearance.weekStorageKey))), week)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        legacy.removeValue(forKey: "boardAppearance")
        let reopened = try JSONDecoder().decode(PersonalCollection.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(reopened.boardAppearance)
        XCTAssertEqual(reopened.lists, first.lists)
    }

    func testListBackgroundTintRoundTripsAndKeepsLegacyDefaults() throws {
        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data(#"{"background":"blue"}"#.utf8))
        XCTAssertNil(legacy.listBackground)
        for tint in KanbanListTint.allCases where tint != .neutral {
            let appearance = ItemAppearance(background: .purple, listBackground: tint)
            XCTAssertFalse(appearance.isEmpty)
            var list = KanbanList(id: 4, title: "Plans", cards: [])
            list.appearance = appearance
            list.isArchived = true
            var reopened = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
            XCTAssertEqual(reopened.appearance, appearance)
            reopened.isArchived = false
            XCTAssertEqual(reopened.appearance?.listBackground, tint)
            var resetTint = appearance
            resetTint.listBackground = nil
            XCTAssertEqual(resetTint.background, .purple)
        }
        XCTAssertFalse(ItemAppearance(listBackground: .blue).isEmpty)
        XCTAssertThrowsError(try JSONDecoder().decode(ItemAppearance.self, from: Data(#"{"listBackground":"invalid"}"#.utf8)))
    }

    func testOptionalAppearancePreservesLegacyJSONAndRejectsInvalidValues() throws {
        let card = try JSONDecoder().decode(KanbanCard.self, from: Data(#"{"id":1,"word":"Plan","listTitle":"Monday","checklists":[]}"#.utf8))
        let list = try JSONDecoder().decode(KanbanList.self, from: Data(#"{"id":0,"title":"Monday","cards":[]}"#.utf8))
        XCTAssertNil(card.appearance)
        XCTAssertNil(list.appearance)
        for data in [try JSONEncoder().encode(card), try JSONEncoder().encode(list)] {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(json["appearance"])
        }
        let empty = KanbanCard(id: 2, word: "Plan", listTitle: "Monday", appearance: ItemAppearance())
        XCTAssertNil(empty.appearance)
        XCTAssertThrowsError(try JSONDecoder().decode(KanbanCard.self, from: Data(#"{"id":1,"word":"Plan","listTitle":"Monday","appearance":{"accent":"invalid"}}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(KanbanList.self, from: Data(#"{"id":0,"title":"Monday","cards":[],"appearance":{"icon":"invalid"}}"#.utf8)))
        for accent in ItemAccent.allCases {
            let value = ItemAppearance(accent: accent, icon: nil)
            XCTAssertEqual(try JSONDecoder().decode(ItemAppearance.self, from: JSONEncoder().encode(value)), value)
        }
        for icon in PersonalCollectionIcon.allCases {
            let value = ItemAppearance(accent: nil, icon: icon)
            XCTAssertEqual(try JSONDecoder().decode(ItemAppearance.self, from: JSONEncoder().encode(value)), value)
        }
    }

    @MainActor
    func testListAppearanceChangesOnlyCanonicalMetadataAndResetsToNil() throws {
        let photo = KanbanAttachment(exampleImage: .camping, caption: "A day outdoors")
        let card = KanbanCard(id: 1, word: "Walk", listTitle: "Monday", attachments: [photo], coverAttachmentID: photo.id)
        let archivedCard = card.replacingLocation(id: 2, listTitle: "Monday")
        var lists = [KanbanList(id: 0, title: "Monday", cards: [card], archivedCards: [archivedCard])]
        let original = lists
        let appearance = ItemAppearance(accent: .teal, icon: .home, background: .blue, listBackground: .green)
        XCTAssertTrue(setListAppearance(0, appearance: appearance, in: &lists))
        var expected = original
        expected[0].appearance = appearance
        XCTAssertEqual(lists, expected)
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists)), lists)
        try lists[0].edit(title: "My plans", subtitle: "Next steps")
        XCTAssertEqual(lists[0].appearance, appearance)
        XCTAssertTrue(setListAppearance(0, appearance: ItemAppearance(), in: &lists))
        XCTAssertNil(lists[0].appearance)
        let retained = lists
        DatabaseActivity.shared.dismissError()
        defer { DatabaseActivity.shared.dismissError() }
        XCTAssertFalse(setListAppearance(99, appearance: appearance, in: &lists))
        XCTAssertEqual(lists, retained)
        var archived = retained[0]
        archived.isArchived = true
        lists = [archived]
        XCTAssertFalse(setListAppearance(0, appearance: appearance, in: &lists))
        XCTAssertEqual(lists, [archived])
        lists = [retained[0], retained[0]]
        let duplicated = lists
        XCTAssertFalse(setListAppearance(0, appearance: appearance, in: &lists))
        XCTAssertEqual(lists, duplicated)
    }

    func testAppearanceRetainsCardNoteCopiesArchivesAndBothLocalStores() async throws {
        let suite = "PlenactTests.Appearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let photo = KanbanAttachment(fileName: "appearance-example.jpg", caption: "Keep this caption")
        let appearance = ItemAppearance(accent: .purple, icon: .project, background: .rose)
        var card = KanbanCard(id: 1, word: "My plan", listTitle: "Plans", attachments: [photo],
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
        XCTAssertEqual(decoded.cards.first(where: { $0.id == card.id }), card)
        XCTAssertEqual(CardAttachmentStore.fileNames(in: [decoded]), ["appearance-example.jpg"])
    }

    func testDisplayFormatsOverrideLegacyDividersWithoutChangingRetainedContent() throws {
        let legacy = KanbanCard(id: 71, word: "---", listTitle: "Ideas", isDivider: true)
        XCTAssertEqual(legacy.displayFormat, .divider)
        let legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(legacyJSON["listDisplayFormat"])
        XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(legacy)).displayFormat, .divider)
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
        for format in ItemDisplayFormat.allCases {
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
        let explicitCard = KanbanCard(id: 76, word: "---", listTitle: "Ideas", presentation: .note, listDisplayFormat: .card)
        XCTAssertEqual(explicitCard.presentation, .card)
        XCTAssertFalse(explicitCard.isSectionDivider)
        let invalid = Data(#"{"id":1,"word":"Example","listTitle":"Ideas","listDisplayFormat":"unsupported"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(KanbanCard.self, from: invalid))
    }

    @MainActor
    func testMixedDisplayFormatsPersistMoveRenameAndArchiveWithIndependentDefaults() async throws {
        let suite = "PlenactTests.DisplayFormats.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let photo = KanbanAttachment(fileName: "mixed-display-example.jpg")
        let cards = ItemDisplayFormat.allCases.enumerated().map { index, format in
            var card = KanbanCard(id: index + 1, word: "Example \(format.title)", listTitle: "Ideas",
                                  attachments: [photo], coverAttachmentID: photo.id, descriptionOverride: "Retained body")
            card.displayFormat = format
            return card
        }
        var lists = [KanbanList(id: 1, title: "Ideas", cards: cards), KanbanList(id: 2, title: "Next", cards: [])]
        XCTAssertTrue(editBoardList(1, title: "Ideas", subtitle: "", newItemPresentation: .note, in: &lists))
        XCTAssertEqual(lists[0].cards, cards)
        XCTAssertEqual(lists[0].makeItem(id: 10, title: "New writing").displayFormat, .note)
        let picture = try XCTUnwrap(cards.first { $0.displayFormat == .picture })
        try BoardCardMovement.move(picture.id, to: 2, before: nil, in: &lists)
        XCTAssertEqual(lists[1].cards.first?.displayFormat, .picture)
        lists[1].archiveCard(id: picture.id)
        var collection = PersonalCollection(title: "Ideas", kind: .list)
        collection.lists = lists
        collection.rename(to: "Plans")
        collection.lists[0].newItemPresentation = .card
        try PersonalCollectionStore.saveChecked([collection], to: defaults)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [collection])
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults)[0].lists[0].newItemPresentation, .card)
        try KanbanBoardPersistence.saveListsChecked(collection.lists, suiteName: suite)
        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restored, collection.lists)
        var archivedList = try XCTUnwrap(restored.last)
        archivedList.restoreArchivedCard(id: picture.id)
        XCTAssertEqual(archivedList.cards.first?.displayFormat, .picture)
        XCTAssertEqual(archivedList.cards.first?.attachments, [photo])
        XCTAssertEqual(CardAttachmentStore.fileNames(in: collection.lists), ["mixed-display-example.jpg"])
    }

    @MainActor
    func testHostedMixedDisplayFormatsAndPicturePlaceholdersDoNotMutateRecords() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        for textSize in [DynamicTypeSize.large, .accessibility3] {
            for format in ItemDisplayFormat.allCases {
                var item = KanbanCard(id: 73, word: "A long example title for a mixed List", listTitle: "Ideas", descriptionOverride: "Retained writing")
                item.displayFormat = format
                let original = item
                let sheet = ItemAppearanceSheet(title: item.word, appearance: nil, displayFormat: format,
                    onSaveDisplay: { _, _ in XCTFail("Layout must not save display"); return false }
                ) { _ in XCTFail("Layout must not save decoration"); return false }
                let controller = UIHostingController(rootView: sheet.environment(\.dynamicTypeSize, textSize))
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Display-\(format.rawValue)-\(textSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let detail = UIHostingController(rootView: NavigationStack {
                    CardDetailView(card: item, onTitleToggle: { _ in XCTFail("Layout must not edit this item") })
                        .environment(\.dynamicTypeSize, textSize)
                })
                window.rootViewController = detail
                detail.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                if format == .title || format == .text {
                    let row = KanbanCardView(card: item, height: 100, displaySettings: BoardDisplaySettings(), labelLibrary: .starter,
                        onUpdateCard: { _ in XCTFail("Layout must not edit writing") }, onDeleteCard: { XCTFail("Layout must not delete") },
                        onArchiveCard: { XCTFail("Layout must not archive") }, onToggle: { XCTFail("Writing must not complete") })
                    let host = UIHostingController(rootView: row.padding().environment(\.dynamicTypeSize, textSize))
                    window.rootViewController = host
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(150))
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let snapshot = XCTAttachment(image: image)
                    snapshot.name = "WritingRow-\(format.rawValue)-\(textSize)"
                    snapshot.lifetime = .keepAlways
                    add(snapshot)
                }
                XCTAssertEqual(item, original)
            }
        }
        for cover in [nil, ExampleCoverImage.garden] {
            let photo = cover.map { KanbanAttachment(mediaKind: .photo, exampleImage: $0) }
            var picture = KanbanCard(id: 74, word: "Example picture", listTitle: "Ideas", attachments: photo.map { [$0] }, coverAttachmentID: photo?.id)
            picture.displayFormat = .picture
            let row = KanbanCardView(card: picture, height: 100, displaySettings: BoardDisplaySettings(), labelLibrary: .starter,
                onUpdateCard: { _ in XCTFail("Layout must not edit picture") }, onDeleteCard: { XCTFail("Layout must not delete") },
                onArchiveCard: { XCTFail("Layout must not archive") }, onToggle: { XCTFail("Layout must not complete") })
            let host = UIHostingController(rootView: row)
            window.rootViewController = host
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = cover == nil ? "Picture-placeholder" : "Picture-natural-aspect"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testAppearanceSheetAndDecoratedNoteLayoutDoNotModifyRecords() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        for textSize in [DynamicTypeSize.large, .accessibility3] {
            for appearance in [nil, ItemAppearance(accent: .teal, icon: nil),
                               ItemAppearance(accent: nil, icon: .heart),
                               ItemAppearance(accent: .purple, icon: .project, background: .rose),
                               ItemAppearance(background: .green)] {
                let sheet = ItemAppearanceSheet(
                    title: "A long title for my next creative project",
                    appearance: appearance,
                    onOpenCover: { XCTFail("Presentation must not open cover settings") }
                ) { _ in
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
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Appearance-\(appearance?.accent?.rawValue ?? "none")-\(appearance?.icon?.rawValue ?? "none")-\(textSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let note = KanbanCard(id: 61, word: "A long title for my next creative project", listTitle: "Ideas",
                                  presentation: .note, appearance: ItemAppearance(accent: .teal, icon: .notes, background: .blue))
            let controller = UIHostingController(rootView: NavigationStack {
                CardDetailView(card: note, onTitleToggle: { _ in XCTFail("Layout must not modify this Note") })
                    .environment(\.dynamicTypeSize, textSize)
            })
            window.rootViewController = controller
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    @MainActor
    func testLibraryExamplesLayoutDoesNotLoadOrRestoreWeekOnPresentation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        for hasUndo in [false, true] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let chooser = PersonalListExamplesView(
                    onLoadExampleWeek: { XCTFail("Opening examples must not replace Week"); return false },
                    onUndoExampleWeek: { XCTFail("Opening examples must not restore Week"); return false },
                    hasUndoableWeek: hasUndo,
                    onSelect: { _ in XCTFail("Opening examples must not create a personal List") }
                )
                let controller = UIHostingController(rootView: chooser.environment(\.dynamicTypeSize, textSize))
                let size = CGSize(width: 393, height: 852)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Library-Examples-undo-\(hasUndo)-\(textSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testStarterAndExampleWeekPictureRowsUseExplicitBundledCoversAndRetainActivities() throws {
        let lists = SampleData.lists
        let pictures = lists.flatMap(\.cards).filter { $0.displayFormat == .picture }
        XCTAssertEqual(pictures.map(\.word), ["Capture a new idea", "Take a walk", "Capture notes and ideas"])
        XCTAssertEqual(pictures.map(\.listTitle), ["Tuesday", "Wednesday", "Sunday"])
        XCTAssertEqual(pictures.compactMap { $0.coverAttachment?.exampleImage }, [.writingNotes, .forestPath, .flowerBouquet])
        XCTAssertEqual(Set(lists.flatMap(\.cards).map(\.id)).count, lists.flatMap(\.cards).count)
        for picture in pictures {
            XCTAssertFalse(picture.isSectionDivider)
            XCTAssertEqual(picture.attachments?.count, 1)
            XCTAssertTrue(picture.galleryPhotos.isEmpty)
            XCTAssertFalse(picture.checklists.isEmpty)
            XCTAssertFalse(picture.subtitle.isEmpty)
            XCTAssertNoThrow(try CardAttachmentStore.coverThumbnail(for: XCTUnwrap(picture.coverAttachment)))
            var card = picture
            card.displayFormat = .card
            XCTAssertEqual(card.attachments, picture.attachments)
            XCTAssertEqual(card.checklists, picture.checklists)
            XCTAssertEqual(card.word, picture.word)
        }
        XCTAssertTrue(CardAttachmentStore.fileNames(in: lists).isEmpty)
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists)), lists)
    }

    @MainActor
    func testPictureRowsHaveNoFooterOrInternalPaddingAtBothBoardDensities() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        let photo = KanbanAttachment(mediaKind: .photo, exampleImage: .flowerBouquet, caption: "Flowers in the garden")
        let thumbnail = try CardAttachmentStore.coverThumbnail(for: photo)
        let ratio = thumbnail.size.width / thumbnail.size.height
        for density in BoardPresentation.allCases {
            for title in ["", "A long retained title that must not add a footer to this Picture row"] {
                var card = KanbanCard(id: 81, word: title, listTitle: "Ideas", attachments: [photo], coverAttachmentID: photo.id)
                card.displayFormat = .picture
                let original = card
                let row = KanbanCardView(card: card, height: density.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                    presentation: density, labelLibrary: .starter, onUpdateCard: { _ in XCTFail("Layout must not edit") },
                    onDeleteCard: { XCTFail("Layout must not delete") }, onArchiveCard: { XCTFail("Layout must not archive") },
                    onToggle: { XCTFail("Layout must not complete") })
                    .environment(\.dynamicTypeSize, .accessibility3)
                let host = UIHostingController(rootView: row)
                host.safeAreaRegions = [] // Measure the row itself, without window safe-area insets.
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                for width: CGFloat in [320, 430] {
                    let size = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
                    XCTAssertEqual(size.width, width, accuracy: 1)
                    XCTAssertEqual(size.height, (width - 8) / ratio, accuracy: 1, "Only the image and existing outer row margins should determine Picture size")
                }
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Picture-full-row-\(density.rawValue)-\(title.isEmpty ? "blank" : "retained-title")"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertEqual(card, original)
            }
        }
    }

    func testExampleWeekGalleriesUseBundledPhotosAndPreserveCoverAndContent() throws {
        let lists = SampleData.lists
        let cards = lists.flatMap(\.cards)
        let galleryCards = cards.filter { !$0.galleryPhotos.isEmpty }
        XCTAssertEqual(galleryCards.map(\.word), [
            "Review the week ahead", "Plan the weekend", "Spend time outdoors"
        ])
        XCTAssertEqual(galleryCards.map { $0.galleryPhotos.count }, [3, 3, 3])
        XCTAssertEqual(galleryCards.map { $0.galleryPhotos.compactMap(\.exampleImage) }, [
            [.calendarPlan, .projectPlanning, .workspace],
            [.camping, .travelBag, .picnic],
            [.forestPath, .coastalWalk, .mountains]
        ])
        XCTAssertEqual(galleryCards.flatMap(\.galleryPhotos).compactMap(\.caption).count, 8)
        XCTAssertNil(galleryCards.last?.galleryPhotos.last?.caption)
        XCTAssertEqual(galleryCards.first?.coverAttachment?.exampleImage, .garden)
        XCTAssertEqual(cards.compactMap(\.coverAttachment).count, 6)
        XCTAssertTrue(CardAttachmentStore.fileNames(in: lists).isEmpty)
        let photos = cards.flatMap { $0.attachments ?? [] }
        XCTAssertEqual(Set(photos.map(\.id)).count, photos.count)
        for photo in photos {
            XCTAssertEqual(photo.kind, .photo)
            XCTAssertNil(photo.fileName)
            XCTAssertNil(photo.url)
            XCTAssertNotNil(photo.exampleImage?.url)
            XCTAssertNoThrow(try CardAttachmentStore.coverThumbnail(for: photo))
        }
        let restored = try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists))
        XCTAssertEqual(restored, lists)
        var edited = try XCTUnwrap(galleryCards.first)
        let original = edited
        try edited.reorderGalleryPhotos(edited.galleryPhotos.reversed().map(\.id))
        try edited.setPhotoCaption("My own plans", for: edited.galleryPhotos[0].id)
        edited.removeAttachment(edited.galleryPhotos[1].id)
        XCTAssertEqual(edited.coverAttachment, original.coverAttachment)
        XCTAssertEqual(edited.checklists, original.checklists)
        XCTAssertEqual(SampleData.lists, lists)
    }

    func testPhotoCaptionsDecodeLegacyAttachmentsAndPreserveMetadata() throws {
        let photo = KanbanAttachment(fileName: "gallery-legacy.jpg", mediaKind: .photo)
        let legacyData = try JSONEncoder().encode(photo)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        XCTAssertNil(json["caption"])
        XCTAssertEqual(try JSONDecoder().decode(KanbanAttachment.self, from: legacyData), photo)

        let link = KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link)
        var card = KanbanCard(id: 31, word: "Gallery", listTitle: "Local", checklists: [], attachments: [photo, link])
        try card.setPhotoCaption("  A quiet afternoon\nby the lake  ", for: photo.id)
        var expected = photo
        expected.caption = "A quiet afternoon\nby the lake"
        XCTAssertEqual(card.attachments, [expected, link])
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(restored, card)
        let original = card
        for id in [link.id, UUID()] {
            XCTAssertThrowsError(try card.setPhotoCaption("Do not save", for: id))
            XCTAssertEqual(card, original)
        }
        try card.setPhotoCaption(" \n ", for: photo.id)
        XCTAssertEqual(card.attachments, [photo, link])
    }

    func testPhotoGalleryReorderKeepsCoverAndNonphotoSlotsAndRejectsInvalidOrders() throws {
        let cover = KanbanAttachment(exampleImage: .camping, caption: "Cover caption")
        let first = KanbanAttachment(fileName: "first-gallery.jpg", caption: "First")
        let second = KanbanAttachment(exampleImage: .mountains, caption: "Second")
        let third = KanbanAttachment(exampleImage: .garden)
        let video = KanbanAttachment(fileName: "gallery.mov", mediaKind: .video)
        let link = KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link)
        var card = KanbanCard(id: 32, word: "Gallery", listTitle: "Local", checklists: [],
                              attachments: [first, video, cover, second, link, third], coverAttachmentID: cover.id)
        XCTAssertEqual(card.galleryPhotos, [first, second, third])
        try card.reorderGalleryPhotos([third.id, first.id, second.id])
        XCTAssertEqual(card.attachments, [third, video, cover, first, link, second])
        XCTAssertEqual(card.coverAttachmentID, cover.id)
        try card.reorderGalleryPhotos([first.id, second.id, third.id])
        XCTAssertEqual(card.attachments, [first, video, cover, second, link, third])
        let snapshot = card
        for ids in [[first.id], [first.id, first.id, third.id], [cover.id, second.id, third.id],
                    [UUID(), second.id, third.id], [link.id, second.id, third.id]] {
            XCTAssertThrowsError(try card.reorderGalleryPhotos(ids))
            XCTAssertEqual(card, snapshot)
        }
        try card.setCover(nil)
        XCTAssertEqual(card.galleryPhotos, [first, cover, second, third])
        card.removeAttachment(second.id)
        XCTAssertEqual(card.attachments, [first, video, cover, link, third])
        XCTAssertEqual(snapshot.attachments, [first, video, cover, second, link, third])
    }

    func testPhotoGalleryEditsPersistInBothStoresAndRetainArchivedCopies() async throws {
        let suite = "PlenactTests.Gallery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = KanbanAttachment(fileName: "retained-gallery.jpg", caption: "Original")
        let second = KanbanAttachment(exampleImage: .camping)
        var original = KanbanCard(id: 33, word: "Trip", listTitle: "Local", checklists: [], attachments: [first, second])
        let archived = original
        try original.setPhotoCaption("Edited", for: first.id)
        try original.reorderGalleryPhotos([second.id, first.id])
        let lists = [KanbanList(id: 0, title: "Local", cards: [original], archivedCards: [archived])]
        try KanbanBoardPersistence.saveListsChecked(lists, suiteName: suite)
        let restoredWeek = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restoredWeek, lists)
        var personal = PersonalCollection(title: "Gallery", kind: .board)
        personal.lists = lists
        try PersonalCollectionStore.saveChecked([personal], to: defaults)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [personal])
        var removed = original
        removed.removeAttachment(first.id)
        let retained = [KanbanList(id: 0, title: "Local", cards: [removed], archivedCards: [archived])]
        XCTAssertEqual(CardAttachmentStore.fileNames(in: retained), ["retained-gallery.jpg"])
        XCTAssertEqual(archived.attachments, [first, second])
        XCTAssertEqual(original.attachments?.first, second)
    }

    @MainActor
    func testHostedPhotoGalleryScrollsHorizontallyWithoutEditingRecords() async throws {
        let photos = [
            KanbanAttachment(exampleImage: .camping, caption: "A place to explore"),
            KanbanAttachment(exampleImage: .mountains),
            KanbanAttachment(exampleImage: .garden, caption: "A longer caption that should remain readable at accessibility text sizes"),
            KanbanAttachment(exampleImage: .workspace, caption: "Planning the next trip")
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        func scrollViews(in view: UIView) -> [UIScrollView] {
            let matches = (view as? UIScrollView).map { [$0] } ?? []
            return matches + view.subviews.flatMap { scrollViews(in: $0) }
        }
        for (width, textSize) in [(CGFloat(320), DynamicTypeSize.large), (700, .large), (393, .accessibility3)] {
            let gallery = CardPhotoGallery(
                photos: photos, photoSelection: .constant([]),
                onOpen: { _ in XCTFail("Rendering must not open a photo") },
                onCaption: { _, _ in XCTFail("Rendering must not change a caption"); return false },
                onReorder: { _ in XCTFail("Rendering must not reorder photos"); return false },
                onRemove: { _ in XCTFail("Rendering must not remove a photo") },
                onSetCover: { _ in XCTFail("Rendering must not select a cover") }
            )
            let controller = UIHostingController(rootView: gallery.environment(\.dynamicTypeSize, textSize))
            window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertTrue(scrollViews(in: controller.view).contains { $0.contentSize.width > $0.bounds.width })
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let snapshot = XCTAttachment(image: image)
            snapshot.name = "Photo-Gallery-\(Int(width))-\(textSize)"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }
    }

    func testListEditingPreservesRetainedRecordsAndRoundTripsSubtitle() throws {

        let card = KanbanCard(id: 10, word: "Synthetic", listTitle: "Thursday", descriptionOverride: "Retained body")
        let divider = KanbanCard(id: 11, word: "---", listTitle: "Thursday", isDivider: true, checklists: [])
        let archive = KanbanCard(id: 12, word: "Retained archive", listTitle: "Thursday", presentation: .note)
        var list = KanbanList(id: 4, title: "Thursday", cards: [card, divider], archivedCards: [archive], newItemPresentation: .note)
        let original = list

        XCTAssertThrowsError(try list.edit(title: " \n ", subtitle: "Do not save"))
        XCTAssertEqual(list, original)
        try list.edit(title: "  My plans  ", subtitle: "  A calm place to begin  ")
        var expectedCard = card
        var expectedDivider = divider
        var expectedArchive = archive
        expectedCard.listTitle = "My plans"
        expectedDivider.listTitle = "My plans"
        expectedArchive.listTitle = "My plans"
        XCTAssertEqual(list.cards, [expectedCard, expectedDivider])
        XCTAssertEqual(list.archivedCards, [expectedArchive])
        XCTAssertEqual(list.id, original.id)
        XCTAssertEqual(list.newItemPresentation, .note)
        XCTAssertEqual(list.subtitle, "A calm place to begin")
        XCTAssertEqual(try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list)), list)

        try list.edit(title: list.title, subtitle: "")
        XCTAssertEqual(list.subtitle, "")
        XCTAssertEqual(try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list)).subtitle, "")
        var collection = PersonalCollection(title: "Synthetic", kind: .list)
        collection.lists = [list]
        collection.rename(to: "Library plans")
        XCTAssertEqual(collection.lists[0].subtitleOverride, "")
        XCTAssertEqual(collection.lists[0].archivedCards[0].id, archive.id)
    }

    @MainActor
    func testCanonicalListEditorSaveRetainsLatestRecordsAndWeekdayRecreation() throws {

        var lists = [KanbanList(id: 4, title: "Thursday", cards: [])]
        let defaultSubtitle = lists[0].subtitle
        let note = lists[0].makeItem(id: 10, title: "Retain this", presentationOverride: .note)
        lists[0].cards.append(note)
        XCTAssertTrue(editBoardList(4, title: "My plans", subtitle: defaultSubtitle, in: &lists))
        XCTAssertNil(lists[0].subtitleOverride, "Unchanged generated text must keep the legacy optional-field shape")
        XCTAssertEqual(lists[0].cards[0].id, note.id)
        XCTAssertEqual(lists[0].cards[0].listTitle, "My plans")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
        let recreated = TodayListSelection.ensureCurrentDayList(lists: lists, date: thursday, calendar: calendar)
        XCTAssertEqual(recreated.lists.first, lists.first)
        XCTAssertEqual(recreated.dayList.title, "Thursday")
        XCTAssertTrue(recreated.dayList.cards.isEmpty)
        XCTAssertNotEqual(recreated.dayList.id, lists[0].id)

        let retained = lists
        XCTAssertFalse(editBoardList(999, title: "Missing", subtitle: "", in: &lists))
        XCTAssertFalse(editBoardList(4, title: " \n ", subtitle: "", in: &lists))
        XCTAssertEqual(lists, retained)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(lists[0])) as? [String: Any])
        XCTAssertNil(json["subtitleOverride"])
    }

    @MainActor
    func testEditedListMetadataPersistsInIndependentLocalStores() async throws {

        let suite = "PlenactTests.ListMetadata.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var week = KanbanList(id: 4, title: "Thursday", cards: [])
        try week.edit(title: "My Week plans", subtitle: "One step at a time")
        try KanbanBoardPersistence.saveListsChecked([week], suiteName: suite)
        let restoredWeek = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restoredWeek, [week])

        var collection = PersonalCollection(title: "Synthetic collection", kind: .board)
        let originalID = collection.lists[0].id
        try collection.lists[0].edit(title: "Library ideas", subtitle: "Room to explore")
        collection.savedCardIDs = []
        try PersonalCollectionStore.saveChecked([collection], to: defaults)
        let restoredCollection = try XCTUnwrap(PersonalCollectionStore.load(from: defaults).first)
        XCTAssertEqual(restoredCollection, collection)
        XCTAssertEqual(restoredCollection.lists[0].id, originalID)
        XCTAssertEqual(restoredCollection.lists[0].subtitle, "Room to explore")
        let unchangedWeek = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(unchangedWeek, [week], "Editing Library metadata must not alter the Week store")
    }

    @MainActor
    func testHostedListEditorPrefillsWithoutMutatingRecords() async throws {

        var list = KanbanList(id: 4, title: "Synthetic plans", cards: [])
        list.subtitleOverride = "A synthetic subtitle"
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        func fields(in view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
        }
        func textViews(in view: UIView) -> [UITextView] {
            (view as? UITextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
        }
        let controller = UIHostingController(rootView: ListInfoEditorSheet(list: list) { _, _ in
            XCTFail("Opening or dismissing an editor must not save")
            return false
        })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(fields(in: controller.view).contains { $0.text == list.title })
        XCTAssertTrue(textViews(in: controller.view).contains { $0.text == list.subtitle }
                      || fields(in: controller.view).contains { $0.text == list.subtitle })
    }

    func testQuickCaptureTemplatesPreserveTitleAndCreateIndependentRecords() throws {
        let list = KanbanList(id: 4, title: "Thursday", cards: [])
        for template in QuickCaptureTemplate.allCases {
            XCTAssertEqual(template.draftTitle(capturedTitle: "My own title"), "My own title")
            let first = list.makeItem(
                id: 10, title: template.draftTitle(capturedTitle: ""),
                description: template.body, presentationOverride: template.presentation,
                actions: template.actions
            )
            let second = list.makeItem(
                id: 11, title: first.word, description: template.body,
                presentationOverride: template.presentation, actions: template.actions
            )
            XCTAssertEqual(first.presentation, template.presentation)
            XCTAssertEqual(first.descriptionOverride, template.body)
            XCTAssertNil(first.startDate)
            XCTAssertNil(first.dueDate)
            XCTAssertNil(first.attachments)
            XCTAssertEqual(first.checklists.flatMap(\.items).map(\.title), template.actions)
            XCTAssertTrue(Set(first.checklists.flatMap(\.items).map(\.id))
                .isDisjoint(with: second.checklists.flatMap(\.items).map(\.id)))
            XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(first)), first)
        }
        var noteList = list
        noteList.newItemPresentation = .note
        XCTAssertEqual(noteList.makeItem(id: 12, title: "Card", presentationOverride: .card, actions: []).presentation, .card)
        XCTAssertEqual(list.makeItem(id: 13, title: "Note", presentationOverride: .note, actions: []).presentation, .note)
        XCTAssertTrue(list.cards.isEmpty)
        XCTAssertEqual(QuickCaptureTemplate.blankCard.draftTitle(capturedTitle: ""), "")
        XCTAssertEqual(QuickCaptureTemplate.blankNote.draftTitle(capturedTitle: ""), "")
    }

    @MainActor
    func testHostedTemplateComposerPrefillsTitleWithoutCreatingRecords() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        func fields(in view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
        }
        for template in [QuickCaptureTemplate.smallPlan, .idea] {
            let controller = UIHostingController(rootView: QuickNoteComposer(
                lists: .constant([KanbanList(id: 4, title: "Thursday", cards: [])]),
                initialListID: 4, initialTitle: "Captured thought", template: template
            ) { _, _, _, _, _, _ in
                XCTFail("Reviewing a template must not create a record")
            })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(fields(in: controller.view).contains { $0.text == "Captured thought" })
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyItemsRemainCardsAndRejectInvalidPresentations()
    /// @brief      Keep legacy JSON unchanged unless Note presentation is explicitly selected
    /// @details    Checks missing optional fields, default-key omission, and invalid enum values
    ///
    /// @return     (Void) records compatibility assertion failures
    /// @throws     Fixture encoding or decoding errors
    ///
    func testLegacyItemsRemainCardsAndRejectInvalidPresentations() throws {

        let data = Data(#"{"id":1,"title":"Legacy","cards":[{"id":2,"word":"Retain","listTitle":"Legacy","checklists":[]}]}"#.utf8) /* JSON fixture bytes for the compatibility check */
        let list = try JSONDecoder().decode(KanbanList.self, from: data) /* Decoded List fixture */

        XCTAssertEqual(list.newItemPresentation,   .card)
        XCTAssertEqual(list.cards[0].presentation, .card)

        let json  = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any]) /* Encoded JSON representation */
        let cards = try XCTUnwrap(json["cards"] as? [[String: Any]]) /* Card records under inspection */

        XCTAssertNil(json["defaultItemPresentation"])
        XCTAssertNil(cards[0]["itemPresentation"])
        XCTAssertNil(list.cards[0].descriptionOverride)
        XCTAssertNil(list.cards[0].createdAt)
        XCTAssertNil(cards[0]["createdAt"])

        let invalidCard = Data(#"{"id":2,"word":"Invalid","listTitle":"Legacy","itemPresentation":"unsupported"}"#.utf8) /* Unsupported Card fixture */
        let invalidList = Data(#"{"id":1,"title":"Invalid","cards":[],"defaultItemPresentation":"unsupported"}"#.utf8) /* Unsupported list-presentation JSON fixture */

        XCTAssertThrowsError(try JSONDecoder().decode(KanbanCard.self, from: invalidCard))
        XCTAssertThrowsError(try JSONDecoder().decode(KanbanList.self, from: invalidList))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreationTimestampRoundTripsAndRejectsMalformedDates()
    /// @brief      Verify Note creation timestamps survive encoding and malformed dates are rejected
    /// @details    Checks Note creation, JSON round trips, edits, and location replacement against
    ///             one fixed synthetic timestamp
    ///
    /// @return     (Void) succeeds when valid dates persist and malformed encoded dates fail
    ///
    /// @throws     Encoding or decoding failures when the timestamp fixture cannot be processed
    ///
    func testCreationTimestampRoundTripsAndRejectsMalformedDates() throws {

        let timestamp = Date(timeIntervalSince1970: 1_791_422_000) /* Fixed creation timestamp */
        var list = KanbanList(id: 1, title: "Synthetic", cards: []) /* List state under verification */
        list.newItemPresentation = .note
        let note = list.makeItem(id: 2, title: "Dated Note", createdAt: timestamp) /* Newly created Note value */

        XCTAssertEqual(note.createdAt, timestamp)

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(note)) /* Decoded Card round-trip value */

        XCTAssertEqual(decoded,           note)
        XCTAssertEqual(decoded.createdAt, timestamp)

        var card = decoded /* Card value under verification */
        card.presentation = .card
        card.word = "Edited title"
        card.descriptionOverride = "Edited body"

        XCTAssertEqual(card.createdAt, timestamp)
        card.presentation = .note

        XCTAssertEqual(card.replacingLocation(id: 8, listTitle: "Moved").createdAt, timestamp)

        let before = Date.now /* Timestamp before the operation */
        let newCard = list.makeItem(id: 3, title: "Created now") /* Newly created Card value */
        let after = Date.now /* Timestamp after the operation */
        let actual = try XCTUnwrap(newCard.createdAt) /* Observed creation timestamp */

        XCTAssertGreaterThanOrEqual(actual, before)
        XCTAssertLessThanOrEqual(actual, after)

        let invalid = Data(#"{"id":2,"word":"Invalid","listTitle":"Synthetic","createdAt":"not-a-date"}"#.utf8) /* Malformed encoded input */

        XCTAssertThrowsError(try JSONDecoder().decode(KanbanCard.self, from: invalid))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNoteCardSwitchPreservesTheCompleteRecord()
    /// @brief      Change presentation without losing identity, metadata, or media references
    /// @details    Round-trips a populated Note, then switches it back to its original Card
    ///
    /// @return     (Void) records retained-content assertion failures
    /// @throws     Synthetic fixture encoding or decoding errors
    ///
    func testNoteCardSwitchPreservesTheCompleteRecord() throws {

        var original   = SampleData.lists[0].cards[0] /* Pre-operation value for preservation checks */
        let attachment = KanbanAttachment(fileName: "synthetic-note-reference.jpg", mediaKind: .photo) /* Attachment fixture under test */

        original.descriptionOverride  = "Synthetic idea\nA second paragraph."
        original.subtitleOverride     = "Retained context"
        original.isTitleChecked       = true
        original.startDate            = Date(timeIntervalSince1970: 1200)
        original.dueDate              = Date(timeIntervalSince1970: 2400)
        original.attachments          = [attachment]
        original.coverAttachmentID    = attachment.id
        original.comments             = [KanbanComment(author: "Synthetic", body: "Retain this comment")]
        original.members              = [.manual("Synthetic")]
        original.labelIDs             = ["synthetic-label"]
        original.dismissedActivityIDs = ["addedCard"]

        var note          = original /* Note value under verification */
        note.presentation = .note

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(note)) /* Decoded Card round-trip value */

        XCTAssertEqual(decoded, note)

        var restored          = decoded /* Restored value under verification */
        restored.presentation = .card

        XCTAssertEqual(restored, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListNoteDefaultAppliesOnlyToNewNondividerItems()
    /// @brief      Apply list defaults at creation without converting retained records
    /// @details    Verifies blank Note bodies, no seeded Note checklists, and unchanged Card defaults
    ///
    /// @return     (Void) records creation/default assertion failures
    ///
    @MainActor
    func testRichTextFormattingPreservesSelectedRunsAndCardPersistence() throws {
        var stored = "Before selected after"
        let editor = RichTextEditor(placeholder: "Description", text: Binding(get: { stored }, set: { stored = $0 }))
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
        XCTAssertFalse((PlanRichText.attributed(stored).attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? true)
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

    @MainActor
    func testRichTextEditorProvidesAccessibleKeyboardToolbar() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: RichTextEditor(placeholder: "Description", text: .constant("A multiline description\nwith a second line")))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        func editor(in view: UIView) -> UITextView? {
            if let text = view as? UITextView { return text }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let text = try XCTUnwrap(editor(in: host.view))
        let toolbar = try XCTUnwrap(text.inputAccessoryView as? UIToolbar)
        XCTAssertEqual(toolbar.items?.compactMap(\.accessibilityLabel), ["Bold", "Italic", "Text color", "Hide keyboard"])
        XCTAssertEqual(text.text, "A multiline description\nwith a second line")
        XCTAssertGreaterThan(text.sizeThatFits(CGSize(width: 300, height: 1000)).height, 40)
        XCTAssertNotNil(toolbar.items?[2].menu)
    }

    @MainActor
    func testRichTextTypingStylesAndLegacyText() {
        var stored = "Legacy plain text 😊"
        let editor = RichTextEditor(placeholder: "Comment", text: Binding(get: { stored }, set: { stored = $0 }))
        let coordinator = editor.makeCoordinator()
        let view = UITextView()
        view.attributedText = PlanRichText.attributed(stored)
        view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
        view.typingAttributes = [.font: UIFont.preferredFont(forTextStyle: .body)]
        coordinator.view = view
        coordinator.toggle(.traitBold)
        coordinator.color("Purple")
        XCTAssertEqual(stored, "Legacy plain text 😊")
        XCTAssertTrue((view.typingAttributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertEqual(view.typingAttributes[NSAttributedString.Key("PlenactColor")] as? String, "Purple")
        XCTAssertEqual(PlanRichText.encode(PlanRichText.attributed(stored)), stored)
        XCTAssertEqual(PlanRichText.plain("plenact-rich-v1:invalid"), "plenact-rich-v1:invalid")
    }

    func testCardSectionLayoutPersistsWithoutRemovingHiddenContent() throws {
        var layout = CardSectionLayout()
        layout.order = [.activity, .description, .quickActions, .media, .checklists, .details]
        layout.hidden = [.description, .checklists]
        let original = KanbanCard(id: 9, word: "Custom", listTitle: "Saturday", descriptionOverride: "Keep this description", sectionLayout: layout)
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

    func testMultilineEntriesPreserveOrderIgnoreBlankLinesAndCreateDistinctCards() throws {
        let input = " A\r\nB\n\n C \rD\nA\n"
        XCTAssertEqual(MultilineEntry.titles(input), ["A", "B", "C", "D", "A"])
        XCTAssertTrue(MultilineEntry.titles(" \n\t\r\n").isEmpty)
        let list = KanbanList(id: 1, title: "Saturday", cards: [])
        let cards = list.makeItems(startingAt: 20, titles: input, description: "Shared details", subtitle: "Subtitle")
        XCTAssertEqual(cards.map(\.word), ["A", "B", "C", "D", "A"])
        XCTAssertEqual(cards.map(\.id), [20, 21, 22, 23, 24])
        XCTAssertTrue(cards.allSatisfy { $0.descriptionOverride == "Shared details" && $0.subtitle == "Subtitle" })
        let decoded = try JSONDecoder().decode([KanbanCard].self, from: JSONEncoder().encode(cards))
        XCTAssertEqual(decoded, cards)
        let items = MultilineEntry.titles(input).map { KanbanChecklistItem(title: $0) }
        XCTAssertEqual(items.map(\.title), ["A", "B", "C", "D", "A"])
        XCTAssertEqual(Set(items.map(\.id)).count, 5)
        XCTAssertTrue(items.allSatisfy { !$0.isCompleted })
    }

    func testNewItemsUseBlankOrEnteredSubtitleAndPersistIt() throws {
        let list = KanbanList(id: 1, title: "Saturday", cards: [])
        let blank = list.makeItem(id: 1, title: "New task")
        XCTAssertEqual(blank.subtitleOverride, "")
        XCTAssertEqual(blank.subtitle, "")
        let entered = list.makeItem(id: 2, title: "New task", description: "Details", subtitle: "  A useful subtitle  ")
        XCTAssertEqual(entered.subtitle, "A useful subtitle")
        XCTAssertEqual(entered.descriptionOverride, "Details")
        for card in [blank, entered] {
            let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
            XCTAssertEqual(decoded.subtitle, card.subtitle)
            XCTAssertEqual(decoded.subtitleOverride, card.subtitleOverride)
        }
    }

    func testListNoteDefaultAppliesOnlyToNewNondividerItems() {

        let existing = KanbanCard(id: 1, word: "Existing", listTitle: "Ideas") /* Existing Card retained while applying List defaults */
        var list     = KanbanList(id: 1, title: "Ideas", cards: [existing]) /* List state under verification */
        let card     = list.makeItem(id: 2, title: "Action") /* Card value under verification */

        let legacyCard = KanbanCard(id: 2, word: "Action", listTitle: "Ideas") /* Legacy-format Card fixture */

        XCTAssertEqual(card.presentation,                                   .card)
        XCTAssertEqual(card.word,                                           legacyCard.word)
        XCTAssertEqual(card.descriptionOverride,                            legacyCard.descriptionOverride)
        XCTAssertEqual(card.checklists.map(\.title),                        legacyCard.checklists.map(\.title))
        XCTAssertEqual(card.checklists.flatMap(\.items).map(\.title),       legacyCard.checklists.flatMap(\.items).map(\.title))
        XCTAssertEqual(card.checklists.flatMap(\.items).map(\.isCompleted), legacyCard.checklists.flatMap(\.items).map(\.isCompleted))

        list.newItemPresentation = .note
        let note                 = list.makeItem(id: 3, title: "Thought") /* Newly created Note value */
        let divider              = list.makeItem(id: 4, title: "---") /* Section-divider fixture */

        XCTAssertEqual(list.cards,               [existing])
        XCTAssertEqual(note.presentation,        .note)
        XCTAssertEqual(note.descriptionOverride, "")
        XCTAssertTrue(note.checklists.isEmpty)
        XCTAssertEqual(divider.presentation, .card)
        XCTAssertTrue(divider.isSectionDivider)
        XCTAssertEqual(list.makeItem(id: 5, title: "Written", description: "Keep\nspacing").descriptionOverride, "Keep\nspacing")

        list.newItemPresentation = .card

        XCTAssertEqual(note.presentation, .note, "Changing a default must not convert existing Notes")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNotePresentationSurvivesPersonalPersistenceRenameAndArchive()
    /// @brief      Retain Note choices in local active and archived content
    /// @details    Uses an isolated defaults suite and checks list defaults, bookmark IDs, and renaming
    ///
    /// @return     (Void) records persistence/retention assertion failures
    /// @throws     Defaults setup, persistence, or Codable errors
    ///
    func testNotePresentationSurvivesPersonalPersistenceRenameAndArchive() throws {

        let suite    = "Plenact.NotePersistenceTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer { defaults.removePersistentDomain(forName: suite) }


        var collection                          = PersonalCollection(title: "Synthetic ideas", kind: .list) /* Collection state under verification */
        collection.lists[0].newItemPresentation = .note
        let note                                = collection.lists[0].makeItem(id: 20, title: "Synthetic thought", description: "Retain body") /* Newly created Note value */
        collection.lists[0].cards               = [note]
        collection.savedCardIDs                 = [note.id]

        collection.lists[0].archiveCard(id: note.id)

        collection.rename(to: "Renamed ideas")

        XCTAssertEqual(collection.lists[0].newItemPresentation,           .note)
        XCTAssertEqual(collection.lists[0].archivedCards[0].presentation, .note)
        XCTAssertEqual(collection.lists[0].archivedCards[0].listTitle,    "Renamed ideas")

        try PersonalCollectionStore.saveChecked([collection], to: defaults)

        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [collection])


        var restored = collection.lists[0] /* Restored value under verification */

        restored.restoreArchivedCard(id: note.id)

        XCTAssertEqual(restored.cards[0].presentation, .note)
        XCTAssertEqual(restored.cards[0].attachments,  note.attachments)
        XCTAssertEqual(collection.savedCardIDs,        [note.id])

        let week    = PersonalCollection.archivedWeekBoard(lists: [restored], savedCardIDs: [note.id]) /* Archived weekly-board fixture */
        let decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(week)) /* Decoded archived-week collection */

        XCTAssertEqual(decoded.lists[0],            restored)
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
    func testPersonalListsDefaultNewItemsToNotesWithoutConvertingExistingRecords() {

        var collection = PersonalCollection(title: "Synthetic ideas", kind: .list) /* Personal List receiving its default */
        let existingCard = KanbanCard(id: 20, word: "Keep this Card", listTitle: collection.title) /* Existing Card content that must remain unchanged */

        XCTAssertEqual(collection.lists[0].newItemPresentation, .note)

        collection.lists[0].cards = [existingCard]
        collection.lists[0].newItemPresentation = .card
        collection.useNoteDefaultsForPersonalLists()

        XCTAssertEqual(collection.lists[0].newItemPresentation, .note)
        XCTAssertEqual(collection.lists[0].cards, [existingCard])
        XCTAssertEqual(collection.lists[0].makeItem(id: 21, title: "New thought").presentation, .note)

        var board = PersonalCollection(title: "Synthetic board", kind: .board) /* Multi-list collection preserving configurable defaults */

        board.lists[0].newItemPresentation = .card
        board.useNoteDefaultsForPersonalLists()

        XCTAssertEqual(board.lists[0].newItemPresentation, .card)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreatingPersonalListNoteUsesFreshIdentityAndPreservesBody()
    /// @brief      Create a Note in the active personal List without replacing retained content
    /// @details    Reserves archived IDs, preserves body whitespace, and rejects invalid targets
    ///             without mutating the collection
    ///
    /// @return     (Void) records new-Note and save/cancel boundary assertions
    /// @throws     Synthetic fixture setup errors
    ///
    func testCreatingPersonalListNoteUsesFreshIdentityAndPreservesBody() throws {

        var collection = PersonalCollection(title: "Synthetic ideas", kind: .list) /* Collection state under verification */
        let existing = collection.lists[0].makeItem(id: 7, title: "Existing") /* Existing active Card retained during Note insertion */
        let archived   = collection.lists[0].makeItem(id: 12, title: "Archived") /* Archived value for restoration checks */

        collection.lists[0].cards         = [existing]
        collection.lists[0].archivedCards = [archived]
        let original                      = collection /* Pre-operation value for preservation checks */

        XCTAssertThrowsError(try collection.addNote(title: " \n ", body: "Uncommitted")) { _ in

            XCTAssertEqual(collection, original, "Cancel/invalid Save must not mutate stored content")
        }

        let createdAt = Date(timeIntervalSince1970: 1_791_422_000) /* Creation timestamp under verification */
        try collection.addNote(title: "  Beach idea  ", body: "First line\n\nSecond line  ", createdAt: createdAt)

        XCTAssertEqual(collection.lists[0].cards, [
            existing,
            KanbanCard(
                id:                  13, word: "Beach idea", listTitle: collection.title,
                checklists:          [],
                descriptionOverride: "First line\n\nSecond line  ",
                presentation:        .note,
                createdAt:           createdAt
            )
        ])

        XCTAssertEqual(collection.lists[0].archivedCards, [archived])

        var board       = PersonalCollection(title: "Not a list", kind: .board) /* Board state under verification */
        let boardBefore = board /* Board state before the attempted change */

        XCTAssertThrowsError(try board.addNote(title: "No", body: ""))
        XCTAssertEqual(board, boardBefore)

        collection.isArchived  = true
        let archivedCollection = collection /* Collection state after archival */

        XCTAssertThrowsError(try collection.addNote(title: "No", body: ""))
        XCTAssertEqual(collection, archivedCollection)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAttachmentThumbnailsFitTheirSquareGridProposal()
    /// @brief      Verify attachment thumbnails honor the proposed square grid size
    /// @details    Hosts photo, web-link, video, and missing-file examples at several widths and
    ///             checks that each thumbnail returns a square layout
    ///
    /// @return     (Void) succeeds when each supported attachment fits the proposed square
    ///
    /// @throws     XCTest unwrap failure when the synthetic web-link URL is invalid
    ///
    @MainActor
    func testAttachmentThumbnailsFitTheirSquareGridProposal() throws {

        let link = try XCTUnwrap(URL(string: "https://example.com/synthetic")) /* Synthetic link target */
        let attachments = [ /* Retained attachment set */
            KanbanAttachment(exampleImage: .garden),
            KanbanAttachment(url: link),
            KanbanAttachment(fileName: "synthetic-video.mov", mediaKind: .video),
            KanbanAttachment(fileName: "synthetic-missing-photo.jpg")
        ]
        for attachment in attachments {

            let controller = UIHostingController(rootView: CardAttachmentThumbnail(attachment: attachment)) /* Hosted controller for layout assertions */
            for width: CGFloat in [92, 128, 260] {

                let size = controller.sizeThatFits(in: CGSize(width: width, height: 1000)) /* Proposed layout dimensions */

                XCTAssertEqual(size.width,  width, accuracy: 1)
                XCTAssertEqual(size.height, width, accuracy: 1)
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedNoteToolbarLayoutPreservesContent()
    /// @brief      Verify the hosted Note toolbar layout does not mutate the Note
    /// @details    Captures portrait, landscape, and accessibility-text layouts using an in-memory
    ///             Note with synthetic attachment data
    ///
    /// @return     (Void) succeeds when hosting emits no Note changes and all layouts render
    ///
    /// @throws     XCTest unwrap failure when no window scene is available
    ///
    @MainActor
    func testHostedNoteToolbarLayoutPreservesContent() async throws {

        var note = KanbanCard( /* Note value under verification */
            id: 93, word: "Synthetic toolbar Note", listTitle: "Synthetic ideas",
            descriptionOverride: "A calm writing area with attachments below.",
            presentation:        .note,
            createdAt:           Date(timeIntervalSince1970: 1_791_422_000),
            appearance:          ItemAppearance(accent: .teal, icon: .notes, background: .green)
        )
        let cover = KanbanAttachment(exampleImage: .garden)
        note.attachments = [
            cover,
            KanbanAttachment(exampleImage: .camping, caption: "Our next adventure"),
            KanbanAttachment(exampleImage: .mountains, caption: "Room to explore")
        ]
        note.coverAttachmentID = cover.id
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previous = scene.windows.first(where: \.isKeyWindow) /* Previously focused window */
        let window = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

        defer {

            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }

        let layouts: [(String, CGSize, DynamicTypeSize)] = [ /* Hosted layout configurations */
            ("portrait", CGSize(width: 393, height: 852), .large),
            ("landscape", CGSize(width: 852, height: 393), .large),
            ("large-text", CGSize(width: 393, height: 852), .accessibility3)
        ]

        for (name, size, textSize) in layouts {

            var emitted: [KanbanCard] = [] /* Captured callback results */
            let controller = UIHostingController(rootView: NavigationStack { /* Hosted controller for layout assertions */
                CardDetailView(card: note, onTitleToggle: { emitted.append($0) })
                    .environment(\.dynamicTypeSize, textSize)
            })
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))

            XCTAssertTrue(emitted.isEmpty, "Toolbar/gallery layout must not rewrite the Note")
            let image = UIGraphicsImageRenderer(size: size).image { _ in /* Synthetic two-color crop source */
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image) /* Attachment fixture under test */
            attachment.name = "Note-toolbar-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedCardCoverSetupLayoutPreservesCoveredAndUncoveredRecords()
    /// @brief      Verify cover setup presentation preserves covered and uncovered Card records
    /// @details    Hosts synthetic Cards with and without selected covers and captures each layout,
    ///             confirming presentation alone does not emit record changes
    ///
    /// @return     (Void) succeeds when both cover states render without modifying their records
    ///
    /// @throws     XCTest unwrap failure when no window scene is available
    ///
    @MainActor
    func testHostedCardCoverSetupLayoutPreservesCoveredAndUncoveredRecords() async throws {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previous = scene.windows.first(where: \.isKeyWindow) /* Previously focused window */
        let window = UIWindow(windowScene: scene) /* Temporary window for UI hosting */
        defer {

            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }

        let photo = KanbanAttachment(exampleImage: .garden) /* Synthetic photo fixture */
        var card = KanbanCard(id: 94, word: "Synthetic cover layout", listTitle: "Synthetic", checklists: []) /* Card value under verification */
        card.appearance = ItemAppearance(icon: .project, background: .blue)
        card.attachments = [
            photo,
            KanbanAttachment(exampleImage: .camping, caption: "Our next adventure"),
            KanbanAttachment(exampleImage: .mountains)
        ]
        var covered = card /* Card with a selected cover */
        covered.coverAttachmentID = photo.id
        for fixture in [card, covered] {

            var emitted: [KanbanCard] = [] /* Captured callback results */
            let controller = UIHostingController(rootView: NavigationStack { /* Hosted controller for layout assertions */
                CardDetailView(card: fixture, onTitleToggle: { emitted.append($0) })
            })
            let size = CGSize(width: 393, height: 852) /* Proposed layout dimensions */
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))

            XCTAssertTrue(emitted.isEmpty, "Relocating cover setup must not modify cover or attachments")
            let image = UIGraphicsImageRenderer(size: size).image { _ in /* Synthetic two-color crop source */
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let snapshot = XCTAttachment(image: image) /* Persisted snapshot under verification */
            snapshot.name = fixture.coverAttachmentID == nil ? "Card-without-cover-setup" : "Card-with-selected-cover"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardAttachmentGalleryExcludesOnlyTheDisplayedCover()
    /// @brief      Verify the attachment gallery omits only the currently displayed cover
    /// @details    Exercises cover selection, clearing, invalid cover references, mixed media, and
    ///             cover-only Cards while checking the underlying attachment records stay intact
    ///
    /// @return     (Void) succeeds when gallery filtering matches the valid selected cover
    ///
    /// @throws     XCTest unwrap failure when the synthetic web-link URL is invalid
    ///
    func testCardAttachmentGalleryExcludesOnlyTheDisplayedCover() throws {

        let cover = KanbanAttachment(exampleImage: .garden) /* Selected cover attachment */
        let otherPhoto = KanbanAttachment(exampleImage: .mountains) /* Non-cover photo attachment */
        let link = KanbanAttachment(url: try XCTUnwrap(URL(string: "https://example.com/synthetic"))) /* Synthetic link target */
        let video = KanbanAttachment(fileName: "synthetic-video.mov", mediaKind: .video) /* Video attachment fixture */
        var card = KanbanCard( /* Card value under verification */
            id: 95, word: "Synthetic", listTitle: "Synthetic", checklists: [],
            attachments: [cover, otherPhoto, link, video], coverAttachmentID: cover.id
        )
        let original = card /* Pre-operation value for preservation checks */

        XCTAssertEqual(card.attachmentsExcludingCover, [otherPhoto, link, video])
        XCTAssertEqual(card, original, "Filtering the gallery must not mutate attachments")

        try card.setCover(otherPhoto.id)

        XCTAssertEqual(card.attachmentsExcludingCover, [cover, link, video])
        try card.setCover(nil)

        XCTAssertEqual(card.attachmentsExcludingCover, original.attachments)

        card.coverAttachmentID = link.id

        XCTAssertEqual(card.attachmentsExcludingCover, original.attachments)
        card.coverAttachmentID = UUID()

        XCTAssertEqual(card.attachmentsExcludingCover, original.attachments)

        card.attachments = [cover]
        try card.setCover(cover.id)

        XCTAssertTrue(card.attachmentsExcludingCover.isEmpty)
        XCTAssertEqual(card.attachments, [cover])
        try card.setCover(nil)

        XCTAssertEqual(card.attachmentsExcludingCover, [cover])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNoteSharingIncludesOnlyWrittenTextAndAttachedWebLinks()
    /// @brief      Verify Note sharing includes written content and attached web links only
    /// @details    Uses synthetic Note text and mixed attachment kinds to ensure media is excluded
    ///             and the original Note record remains unchanged
    ///
    /// @return     (Void) succeeds when the share payload contains only allowed Note content
    ///
    /// @throws     XCTest unwrap failure when the synthetic web-link URL is invalid
    ///
    func testNoteSharingIncludesOnlyWrittenTextAndAttachedWebLinks() throws {

        var note = SampleData.lists[0].cards[0] /* Note value under verification */
        note.word = "Synthetic shared note"
        note.presentation = .note
        note.descriptionOverride = "First line\n\nSecond line  "
        let link = try XCTUnwrap(URL(string: "https://example.com/synthetic-note")) /* Synthetic link target */
        note.attachments = [
            KanbanAttachment(fileName: "synthetic-private-photo.jpg", mediaKind: .photo),
            KanbanAttachment(fileName: "synthetic-private-video.mov", mediaKind: .video),
            KanbanAttachment(url: link),
            KanbanAttachment(exampleImage: .garden)
        ]
        let original = note /* Pre-operation value for preservation checks */

        XCTAssertEqual(
            NoteTextSharing.text(for: note),
            "Synthetic shared note\n\nFirst line\n\nSecond line  \n\nhttps://example.com/synthetic-note"
        )
        XCTAssertEqual(note, original, "Preparing a share must not change the saved record")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNoteSharingDoesNotFillEmptyBodyWithGeneratedDescription()
    /// @brief      Verify sharing does not synthesize text for an empty Note body
    /// @details    Confirms the title is shared alone and whitespace-only body content is retained
    ///             rather than replaced with generated descriptive text
    ///
    /// @return     (Void) succeeds when the share payload reflects only explicitly written text
    ///
    func testNoteSharingDoesNotFillEmptyBodyWithGeneratedDescription() {

        var note = KanbanCard(id: 92, word: "Empty synthetic Note", listTitle: "Private list", presentation: .note) /* Note value under verification */

        XCTAssertEqual(NoteTextSharing.text(for: note), "Empty synthetic Note")
        note.descriptionOverride = ""

        XCTAssertEqual(NoteTextSharing.text(for: note), "Empty synthetic Note")
        note.descriptionOverride = " \n "

        XCTAssertEqual(NoteTextSharing.text(for: note), "Empty synthetic Note\n\n \n ")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewPersonalNoteDraftSavesOnlyToSelectedList()
    /// @brief      Verify a new Note is saved only to its selected personal List
    /// @details    Checks destination selection has no side effects before save and that the
    ///             persisted Note retains its body, type, List, and original draft timestamp
    ///
    /// @return     (Void) succeeds when exactly the selected collection receives the Note
    ///
    /// @throws     XCTest unwrap failure when the persisted synthetic Note cannot be found
    ///
    func testNewPersonalNoteDraftSavesOnlyToSelectedList() throws {

        let initial = PersonalCollection(title: "Initial ideas", kind: .list) /* Initial destination collection to preserve */
        let selected = PersonalCollection(title: "Selected ideas", kind: .list) /* Selected destination collection for the Note */
        var collections = [initial, selected] /* Saved personal-collection state */
        var draft = PersonalListNoteDraft(destinationID: initial.id) /* Uncommitted draft under test */
        let originalCreationDate = draft.createdAt /* Timestamp retained by the operation */

        draft.title = "  New idea  "
        draft.body = "First line\n\nSecond line  "
        draft.destinationID = selected.id

        XCTAssertEqual(collections, [initial, selected], "Selecting a List must not create or move content")
        XCTAssertEqual(draft.destination(in: collections), selected)

        var saves = 0 /* Save-callback invocation count */
        try draft.save(in: collections) { destinationID, title, body, createdAt in
            saves += 1

            XCTAssertEqual(createdAt, originalCreationDate)
            let index = try XCTUnwrap(collections.firstIndex { $0.id == destinationID }) /* Selected collection index */
            try collections[index].addNote(title: title, body: body, createdAt: createdAt)
        }

        XCTAssertEqual(saves,                               1)
        XCTAssertEqual(collections[0],                      initial)
        XCTAssertEqual(collections[1].lists[0].cards.count, 1)
        let note = try XCTUnwrap(collections[1].lists[0].cards.first) /* Note value under verification */

        XCTAssertEqual(note.word,                "New idea")
        XCTAssertEqual(note.descriptionOverride, draft.body)
        XCTAssertEqual(note.listTitle,           selected.title)
        XCTAssertEqual(note.presentation,        .note)
        XCTAssertEqual(note.createdAt,           originalCreationDate)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewPersonalNoteDraftRejectsUnavailableDestinationsAndBlankTitle()
    /// @brief      Verify invalid Note destinations and blank titles cannot be saved
    /// @details    Covers Board collections, archived collections, collections without active
    ///             Lists, unknown identities, and whitespace-only titles
    ///
    /// @return     (Void) succeeds when invalid drafts are rejected before persistence is called
    ///
    func testNewPersonalNoteDraftRejectsUnavailableDestinationsAndBlankTitle() {

        let active = PersonalCollection(title: "Active ideas", kind: .list) /* Active personal collection used as an invalid target */
        let board = PersonalCollection(title: "Projects", kind: .board) /* Board state under verification */
        var archived = PersonalCollection(title: "Archived ideas", kind: .list) /* Archived value for restoration checks */
        archived.isArchived = true
        var empty = PersonalCollection(title: "No active list", kind: .list) /* Empty collection fixture */
        empty.lists[0].isArchived = true
        let collections = [active, board, archived, empty] /* Saved personal-collection state */

        XCTAssertEqual(PersonalListNoteDraft.destinations(in: collections), [active])

        for id in [board.id, archived.id, empty.id, UUID()] {

            let draft = PersonalListNoteDraft(destinationID: id, title: "Idea", body: "Unsaved body") /* Uncommitted draft under test */

            XCTAssertFalse(draft.canSave(in: collections))
            XCTAssertThrowsError(try draft.save(in: collections) { _, _, _, _ in
                XCTFail("An unavailable destination must not reach persistence")
            })
        }

        let blank = PersonalListNoteDraft(destinationID: active.id, title: " \n ", body: "Unsaved body") /* Blank Note fixture */

        XCTAssertFalse(blank.canSave(in: collections))
        XCTAssertThrowsError(try blank.save(in: collections) { _, _, _, _ in
            XCTFail("A blank title must not reach persistence")
        })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewPersonalNoteDraftPreservesSelectionAndTextAfterFailedSave()
    /// @brief      Verify a failed Note save preserves the draft for retry
    /// @details    Makes the synthetic persistence callback fail, confirms the destination, title,
    ///             body, and creation timestamp remain intact, then verifies a retry can succeed
    ///
    /// @return     (Void) succeeds when failed persistence does not discard editable draft state
    ///
    /// @throws     XCTest unwrap failure when the retry callback receives unexpected values
    ///
    func testNewPersonalNoteDraftPreservesSelectionAndTextAfterFailedSave() throws {

        let initial = PersonalCollection(title: "Initial ideas", kind: .list) /* Initial destination collection to preserve */
        let selected = PersonalCollection(title: "Selected ideas", kind: .list) /* Selected destination collection for the Note */
        let collections = [initial, selected] /* Saved personal-collection state */
        var draft = PersonalListNoteDraft(destinationID: initial.id) /* Uncommitted draft under test */
        let originalCreationDate = draft.createdAt /* Timestamp retained by the operation */
        draft.title = "  Retry idea  "
        draft.body = "Retained body\n  "
        draft.destinationID = selected.id

        XCTAssertThrowsError(try draft.save(in: collections) { id, title, body, createdAt in

            XCTAssertEqual(createdAt, originalCreationDate)
            XCTAssertEqual(id,        selected.id)
            XCTAssertEqual(title,     "Retry idea")
            XCTAssertEqual(body,      draft.body)
            throw CocoaError(.fileWriteNoPermission)
        })

        XCTAssertEqual(draft.destinationID, selected.id)
        XCTAssertEqual(draft.title,         "  Retry idea  ")
        XCTAssertEqual(draft.body,          "Retained body\n  ")
        XCTAssertEqual(collections,         [initial, selected])
        XCTAssertTrue(draft.canSave(in: collections))

        var saves = 0 /* Save-callback invocation count */
        try draft.save(in: collections) { id, _, _, createdAt in

            XCTAssertEqual(id,        selected.id)
            XCTAssertEqual(createdAt, originalCreationDate)
            saves += 1
        }

        XCTAssertEqual(saves, 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalNoteMovePreservesContentAndResolvesCollectionLocalIDCollision()
    /// @brief      Move a Note across personal Lists without losing content or bookmarks
    /// @details    Reassigns only a colliding destination-local ID and leaves unrelated/archived
    ///             destination records and invalid move snapshots unchanged
    ///
    /// @return     (Void) records cross-collection move assertions
    ///
    func testPersonalNoteMovePreservesContentAndResolvesCollectionLocalIDCollision() throws {

        let attachment = KanbanAttachment(fileName: "synthetic-moved-note.jpg", mediaKind: .photo) /* Attachment fixture under test */
        var note = KanbanCard( /* Note value under verification */
            id: 4, word: "Beach idea", listTitle: "Ideas",
            checklists:          [KanbanChecklist(title: "Keep", items: ["Discuss"])],
            descriptionOverride: "First paragraph\n\nSecond paragraph",
            presentation:        .note,
            createdAt:           Date(timeIntervalSince1970: 1_791_422_000)
        )
        note.attachments = [attachment]
        note.coverAttachmentID = attachment.id
        note.labelIDs = ["keep-this-label"]
        note.comments = [KanbanComment(author: "Synthetic", body: "Keep this comment")]

        var source = PersonalCollection(title: "Ideas", kind: .list) /* Source state before the operation */
        source.lists[0].cards = [note]
        source.savedCardIDs = [note.id]

        var destination = PersonalCollection(title: "Someday", kind: .list) /* Target location for the move */
        destination.lists[0].cards = [
            KanbanCard(id: 4, word: "ID collision", listTitle: "Someday", checklists: [])
        ]
        destination.lists[0].archivedCards = [
            KanbanCard(id: 9, word: "Archived ID", listTitle: "Someday", checklists: [])
        ]
        destination.savedCardIDs = [4]

        var collections = [source, destination] /* Saved personal-collection state */
        let moved = try PersonalCollectionNoteMovement.move( /* Note after relocation to another List */
            noteID: note.id, from: source.id, to: destination.id, in: &collections
        )

        let expected = note.replacingLocation(id: 10, listTitle: destination.title) /* Expected result for comparison */

        XCTAssertEqual(moved,           expected)
        XCTAssertEqual(moved.createdAt, note.createdAt)
        XCTAssertNotNil(moved.createdAt)
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        XCTAssertFalse(collections[0].savedCardIDs.contains(note.id))
        XCTAssertEqual(collections[1].lists[0].cards, [
            destination.lists[0].cards[0], expected
        ])
        XCTAssertEqual(collections[1].lists[0].archivedCards, destination.lists[0].archivedCards)
        XCTAssertEqual(collections[1].savedCardIDs,           [4, expected.id])

        let beforeInvalidMove = collections /* Collection snapshot before invalid movement */

        XCTAssertThrowsError(try PersonalCollectionNoteMovement.move(
            noteID: expected.id, from: source.id, to: UUID(), in: &collections
        ))
        XCTAssertEqual(collections, beforeInvalidMove)

        let board = PersonalCollection(title: "Not a destination List", kind: .board) /* Board state under verification */
        var boardMove = [source, board] /* Board movement result */
        let beforeBoardMove = boardMove /* Board snapshot before movement */

        XCTAssertThrowsError(try PersonalCollectionNoteMovement.move(
            noteID: note.id, from: source.id, to: board.id, in: &boardMove
        ))
        XCTAssertEqual(boardMove, beforeBoardMove)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalNoteMovePreservesNonconflictingID()
    /// @brief      Keep the Note's local ID when its destination has no collision
    /// @details    Moves the original Note record and updates only its containing List title
    ///
    /// @return     (Void) records stable-ID and source-removal assertions
    ///
    func testPersonalNoteMovePreservesNonconflictingID() throws {

        var source = PersonalCollection(title: "Ideas", kind: .list) /* Source state before the operation */
        var note = KanbanCard(id: 14, word: "Read later", listTitle: "Ideas", checklists: [], presentation: .note) /* Note value under verification */
        note.descriptionOverride = "Synthetic body"
        source.lists[0].cards = [note]

        let destination = PersonalCollection(title: "Someday", kind: .list) /* Target location for the move */
        var collections = [source, destination] /* Saved personal-collection state */

        let moved = try PersonalCollectionNoteMovement.move( /* Note after relocation to another List */
            noteID: note.id, from: source.id, to: destination.id, in: &collections
        )

        XCTAssertEqual(moved.id,                  note.id)
        XCTAssertEqual(moved.listTitle,           destination.title)
        XCTAssertEqual(moved.descriptionOverride, note.descriptionOverride)
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        XCTAssertEqual(collections[1].lists[0].cards, [moved])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryDirectoryNoteDestinationPrefersMostRecentlyOpenedList()
    /// @brief      Resolve the Library New Note target without moving or changing collections
    /// @details    Prefer a retained recent List, fall back to the first visible active List,
    ///             and return no destination when Library has no active Lists
    ///
    /// @return     (Void) records destination selection assertion failures
    ///
    func testLibraryDirectoryNoteDestinationPrefersMostRecentlyOpenedList() {

        let first  = PersonalCollection(title: "First ideas", kind: .list) /* First value in the comparison */
        let recent = PersonalCollection(title: "Recent ideas", kind: .list) /* Most recent activity entry */
        let board  = PersonalCollection(title: "Projects", kind: .board) /* Board state under verification */

        XCTAssertEqual(

            BoardListsView.resolveNoteDestination(
                mostRecentlyOpenedListID: recent.id,
                collections:              [first, recent, board],
                visibleCollections:       [first, board]
            ),
            recent
        )

        XCTAssertEqual(

            BoardListsView.resolveNoteDestination(
                mostRecentlyOpenedListID: UUID(),
                collections:              [first, recent, board],
                visibleCollections:       [board, first]
            ),
            first
        )

        XCTAssertNil(
            BoardListsView.resolveNoteDestination(
                mostRecentlyOpenedListID: nil,
                collections:              [board],
                visibleCollections:       [board]
            )
        )
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryDirectoryNewActionPresentsNoteComposer()
    /// @brief      Verify Library's registered New action opens the writing-first composer
    /// @details    Hosts a synthetic personal List, invokes the registered directory action,
    ///             and checks that its Note destination is shown in the presented composer
    ///
    /// @return     (Void) records callback or composer presentation failures
    /// @throws     Scene, view, or presentation lookup failures
    ///
    @MainActor
    func testLibraryDirectoryNewActionPresentsNoteComposer() async throws {

        var current = [PersonalCollection(title: "First ideas", kind: .list)] /* Current collections displayed by the Library */
        let scene    = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previous = scene.windows.first(where: \.isKeyWindow) /* Previously focused window */
        let window   = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

        var newNoteAction: (() -> Void)? /* New Note action under test */


        defer {

            window.isHidden           = true
            window.rootViewController = nil

            previous?.makeKey()
        }

        let controller = UIHostingController(rootView: BoardListsView( /* Hosted controller for layout assertions */
            retainedWeekLists:   [],
            collections:         Binding(get: { current }, set: { current = $0 }),
            registerListNewNote: { newNoteAction = $0 },
            onOpenSaved:         {}
        ))

        window.frame              = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller

        window.makeKeyAndVisible()

        controller.view.layoutIfNeeded()

        try await Task.sleep(for: .milliseconds(150))

        try XCTUnwrap(newNoteAction)()

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertNotNil(
            controller.presentedViewController,
            "The Library New action must present its writing-first Note composer"
        )
        XCTAssertTrue(
            [UIModalPresentationStyle.fullScreen, .overFullScreen]
                .contains(controller.presentedViewController?.modalPresentationStyle ?? .automatic),
            "The Library-directory New action must retain the immersive full-screen composer"
        )
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedNoteBodyEditsEmitCompleteRetainedSnapshots()
    /// @brief      Exercise the actual hosted writing field and its canonical update callback
    /// @details    Edits synthetic body text through the native text-view delegate and checks
    ///             that layout is read-only and hidden checklist/completion state survives
    ///
    /// @return     (Void) records editor/persistence callback assertion failures
    /// @throws     Native editor lookup or layout delay failures
    ///
    @MainActor
    func testHostedNoteBodyEditsEmitCompleteRetainedSnapshots() async throws {

        var note = SampleData.lists[0].cards[0] /* Note value under verification */
        note.appearance = ItemAppearance(accent: .blue, icon: .heart, background: .rose)
        note.presentation        = .note
        note.descriptionOverride = "Synthetic note body"
        note.isTitleChecked     = true

        let scene    = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previous = scene.windows.first(where: \.isKeyWindow) /* Previously focused window */
        let window   = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

        defer {

            window.isHidden           = true
            window.rootViewController = nil

            previous?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedNoteBodyEditsEmitCompleteRetainedSnapshots.textViews(in:)
        /// @brief      Find native multiline editors in the hosted Note
        /// @details    Recurses through view children without changing the hierarchy
        ///
        /// @param[in]  view  Root to inspect
        ///
        /// @return     ([UITextView]) native multiline text fields
        ///
        func textViews(in view: UIView) -> [UITextView] {

            (view as? UITextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
        }


        let emptyNote = KanbanCard( /* Note with an empty body */
            id: 91, word: "Empty", listTitle: "Synthetic", checklists: [], presentation: .note,
            createdAt: Date(timeIntervalSince1970: 1_791_422_000)
        )

        for fixture in [note, emptyNote] {

            var emitted: [KanbanCard] = [] /* Captured callback results */

            let controller = UIHostingController(rootView: CardDetailView( /* Hosted controller for layout assertions */
                card: fixture, onTitleToggle: { emitted.append($0) }
            ))

            window.frame              = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller

            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()

            try await Task.sleep(for: .milliseconds(150))

            XCTAssertTrue(emitted.isEmpty, "Opening and laying out a Note must not save or rewrite it")

            let titleEditor  = try XCTUnwrap(textViews(in: controller.view).first { $0.text == fixture.word }) /* Hosted title editor */
            titleEditor.text = "Updated synthetic title"

            titleEditor.delegate?.textViewDidChange?(titleEditor)

            try await Task.sleep(for: .milliseconds(150))

            var expected  = fixture /* Expected result for comparison */
            expected.word = titleEditor.text

            XCTAssertEqual(emitted.last, expected, "Title edits must not fill an unwritten Note body with generated copy")

            let editor  = try XCTUnwrap(textViews(in: controller.view).first { $0.text == (fixture.descriptionOverride ?? "") }) /* Editor state under test */
            editor.text = "Edited synthetic body\nSecond paragraph"

            editor.delegate?.textViewDidChange?(editor)

            try await Task.sleep(for: .milliseconds(150))

            expected.descriptionOverride = editor.text

            XCTAssertEqual(emitted.last, expected)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testOfflineLibraryContains48DistinctBundledIllustrations()
    /// @brief      Verify the complete six-category library is shipped with the app
    /// @details    Checks actual app resources, exact canvas dimensions, distinct bytes, and total
    ///             size. Does not enable covers or write personal media files
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Missing bundle resources, image decoding, or file-read errors
    ///
    func testOfflineLibraryContains48DistinctBundledIllustrations() throws {

        let categories = CoverCategory.allCases /* Available attachment categories */

        XCTAssertEqual(categories.count, 6)

        for category in categories {

            XCTAssertEqual(category.images.count, 8, category.rawValue)
        }

        let images = categories.flatMap(\.images) /* Synthetic image fixtures */
        let names  = images.map(\.rawValue) /* Bundled illustration asset names */

        XCTAssertEqual(names.count,      48)
        XCTAssertEqual(Set(names).count, 48)
        XCTAssertEqual(Set(images),      Set(ExampleCoverImage.allCases))

        var distinctImages: Set<Data> = [] /* Distinct image fixtures */
        var totalBytes                = 0 /* Combined image-data size */

        for name in names {

            let url = try XCTUnwrap(Bundle.main.url( /* URL fixture for the request */

                forResource: name, withExtension: "png", subdirectory: "CardCoverImages"

            ), "Missing bundled illustration: \(name)")

            let bytes = try Data(contentsOf: url) /* Bundled illustration bytes */
            let image = try XCTUnwrap(UIImage(data: bytes)?.cgImage, "Unreadable illustration: \(name)") /* Decoded cropped-avatar image */

            XCTAssertEqual(image.width,  960, name)
            XCTAssertEqual(image.height, 480, name)
            XCTAssertTrue(distinctImages.insert(bytes).inserted, "Duplicate illustration: \(name)")

            totalBytes += bytes.count
        }

        XCTAssertEqual(distinctImages.count, 48)
        XCTAssertLessThan(totalBytes, 1_048_576, "Keep the initial offline artwork below one MiB")

        let directory    = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("CardCoverImages") /* Synthetic photo directory */

        let bundledNames = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) /* Bundled example-photo names */
            .filter { $0.pathExtension == "png" }
            .map { $0.deletingPathExtension().lastPathComponent }

        XCTAssertEqual(Set(bundledNames),                           Set(names))
        XCTAssertEqual(Array(ExampleCoverImage.allCases.prefix(3)), [.garden, .mountains, .workspace])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibrarySelectionReusesAttachmentsAndPreservesPersonalContent()
    /// @brief      Select, replace, remove, and reselect illustrations without losing personal
    ///             media
    /// @details    Covers repeated selections, archive/restore, independent copies, and Codable
    ///             identifiers
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Cover validation and encoding/decoding errors
    ///
    func testLibrarySelectionReusesAttachmentsAndPreservesPersonalContent() throws {

        let photo = KanbanAttachment(fileName: "synthetic-personal.jpg", mediaKind: .photo) /* Synthetic photo fixture */
        var card = KanbanCard(id: 9, word: "My plan", listTitle: "Local", checklists: [], /* Card value under verification */
                              attachments: [photo], coverAttachmentID: photo.id, descriptionOverride: "Keep this")

        for image in ExampleCoverImage.allCases {

            let before = card.attachments?.count ?? 0 /* Timestamp before the operation */

            try card.useLibraryCover(image)

            let selectedID = card.coverAttachmentID /* Selected attachment identifier */

            try card.useLibraryCover(image)

            XCTAssertEqual(card.attachments?.count,            before + 1)
            XCTAssertEqual(card.coverAttachmentID,             selectedID)
            XCTAssertEqual(card.coverAttachment?.exampleImage, image)
            XCTAssertEqual(card.attachments?.first,            photo)
            XCTAssertEqual(card.descriptionOverride,           "Keep this")
            XCTAssertNil(card.coverAttachment?.fileName)
        }

        let snapshot = card /* Persisted snapshot under verification */
        var list = KanbanList(id: 1, title: "Local", cards: [card]) /* List state under verification */

        list.archiveCard(id: card.id)

        let decoded = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list)) /* Decoded List round-trip value */

        XCTAssertEqual(decoded.archivedCards.first, snapshot)

        try card.setCover(nil)

        XCTAssertEqual(card.attachments, snapshot.attachments)

        try card.useLibraryCover(.garden)

        XCTAssertEqual(card.attachments?.count,                49)
        XCTAssertEqual(card.coverAttachment?.exampleImage,     .garden)
        XCTAssertEqual(snapshot.coverAttachment?.exampleImage, ExampleCoverImage.allCases.last)

        card.isDivider = true

        let rejected = card /* Card value retained after rejected selection */

        XCTAssertThrowsError(try card.useLibraryCover(.coding))
        XCTAssertEqual(card, rejected)


    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverLibraryLayoutDoesNotSelectOrWriteOnPresentation()
    /// @brief      Host the actual library at narrow, landscape, and accessibility sizes
    /// @details    Layout and presentation alone must not select images or alter preference data
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testCoverLibraryLayoutDoesNotSelectOrWriteOnPresentation() {

        for (width, height, size) in [
            (320.0, 640.0, DynamicTypeSize.large),
            (852.0, 393.0, DynamicTypeSize.large),
            (320.0, 640.0, DynamicTypeSize.accessibility5)
        ] {
            let view = CardCoverLibrary(selectedImage: .garden, onSelect: { _ in /* Hosted view under test */
                XCTFail("Presentation must not select or attach an image")
                return false
            }).environment(\.dynamicTypeSize, size)
            let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */

            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            controller.view.layoutIfNeeded()

            let fitting = controller.sizeThatFits(in: CGSize(width: width, height: height)) /* Layout proposal that fits the content */

            XCTAssertTrue(fitting.width.isFinite && fitting.height.isFinite)
            XCTAssertGreaterThan(fitting.height, 0)
            XCTAssertLessThanOrEqual(fitting.width, width)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoversAreExplicitAndBackwardCompatible()
    /// @brief      Preserve legacy cards and opt-in cover metadata through Codable
    /// @details    Attached photos never implicitly enable a cover; nil fields remain absent in
    ///             JSON
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Encoding, decoding, or cover validation errors
    ///
    func testCoversAreExplicitAndBackwardCompatible() throws {

        let legacy = Data(#"{"id":1,"word":"Synthetic","listTitle":"Local","checklists":[]}"#.utf8) /* Legacy-format fixture */
        var card = try JSONDecoder().decode(KanbanCard.self, from: legacy) /* Decoded Card fixture */

        XCTAssertNil(card.coverAttachmentID)

        let photo = KanbanAttachment(fileName: "synthetic.jpg", mediaKind: .photo) /* Synthetic photo fixture */

        card.attachments = [photo]

        XCTAssertNil(card.coverAttachment)

        let uncoveredJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]) /* Uncovered-Card JSON fixture */

        XCTAssertNil(uncoveredJSON["coverAttachmentID"])

        let attachmentJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(photo)) as? [String: Any]) /* Attachment JSON fixture */

        XCTAssertNil(attachmentJSON["exampleImage"])

        try card.setCover(photo.id)

        XCTAssertEqual(card.coverAttachment, photo)

        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card)) /* Restored value under verification */

        XCTAssertEqual(restored, card)

        try card.setCover(nil)

        XCTAssertNil(card.coverAttachment)
        XCTAssertEqual(card.attachments, [photo])

        try card.setCover(photo.id)

        XCTAssertEqual(card.coverAttachment, photo)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverSelectionAndAttachmentRemovalNeverChooseFallbackPhotos()
    /// @brief      Validate photo ownership and keep cover removal separate from media deletion
    /// @details    Rejects links/videos/missing IDs; deleting an unrelated photo preserves the
    ///             cover
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Valid cover selection errors
    ///
    func testCoverSelectionAndAttachmentRemovalNeverChooseFallbackPhotos() throws {

        let first = KanbanAttachment(fileName: "first.jpg", mediaKind: .photo) /* First value in the comparison */
        let second = KanbanAttachment(fileName: "second.jpg", mediaKind: .photo) /* Second value in the comparison */
        let video = KanbanAttachment(fileName: "video.mov", mediaKind: .video) /* Video attachment fixture */
        let link = KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link) /* Synthetic link target */
        var card = KanbanCard(id: 1, word: "Synthetic", listTitle: "Local", checklists: [], /* Card value under verification */
                              attachments: [first, second, video, link])

        try card.setCover(first.id)

        for id in [video.id, link.id, UUID()] {

            XCTAssertThrowsError(try card.setCover(id))
            XCTAssertEqual(card.coverAttachmentID, first.id)
        }

        card.removeAttachment(second.id)

        XCTAssertEqual(card.coverAttachmentID, first.id)

        card.removeAttachment(first.id)

        XCTAssertNil(card.coverAttachmentID)
        XCTAssertNil(card.coverAttachment)
        XCTAssertEqual(card.attachments, [video, link])

        card.attachments = [second]

        XCTAssertNil(card.coverAttachment)

        card.coverAttachmentID = UUID()

        XCTAssertNil(card.coverAttachment)

        card.isDivider = true

        XCTAssertThrowsError(try card.setCover(second.id))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverArchiveRestoreAndIndependentCopyRetainAttachmentIdentity()
    /// @brief      Keep cover selections across retained partitions and independent card copies
    /// @details    Removing a copy's cover does not change the original card or shared attachment
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Cover validation and Codable errors
    ///
    func testCoverArchiveRestoreAndIndependentCopyRetainAttachmentIdentity() throws {

        let photo = KanbanAttachment(mediaKind: .photo, exampleImage: .garden) /* Synthetic photo fixture */
        var card = KanbanCard(id: 1, word: "Synthetic", listTitle: "Local", checklists: [], attachments: [photo]) /* Card value under verification */

        try card.setCover(photo.id)

        var list = KanbanList(id: 1, title: "Local", cards: [card]) /* List state under verification */

        list.archiveCard(id: card.id)

        var restored = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list)) /* Restored value under verification */

        XCTAssertEqual(restored.archivedCards.first?.coverAttachment, photo)

        restored.restoreArchivedCard(id: card.id)

        XCTAssertEqual(restored.cards.first, card)

        var copy = card /* Independent Card copy */

        try copy.setCover(nil)

        XCTAssertEqual(card.coverAttachment, photo)
        XCTAssertEqual(copy.attachments,     card.attachments)
        XCTAssertTrue(CardAttachmentStore.fileNames(in: [list]).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBundledExampleCoversDecodeWithoutPersonalFilesOrNetwork()
    /// @brief      Verify resource target membership and bounded image decoding
    /// @details    Exactly three optional examples and three starter cards have original bundled
    ///             covers
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Missing resources, image decoding, or fixture errors
    ///
    func testBundledExampleCoversDecodeWithoutPersonalFilesOrNetwork() throws {

        for example in ExampleCoverImage.allCases {

            let photo = KanbanAttachment(mediaKind: .photo, exampleImage: example) /* Synthetic photo fixture */

            XCTAssertNotNil(example.url)

            let thumbnail = try CardAttachmentStore.coverThumbnail(for: photo) /* Rendered attachment thumbnail */
            let image = try XCTUnwrap(thumbnail.cgImage) /* Synthetic image fixture */

            XCTAssertLessThanOrEqual(max(image.width, image.height), 960)
            XCTAssertGreaterThan(min(image.width, image.height), 0)
            XCTAssertNil(photo.fileName)
            XCTAssertNil(photo.url)
        }

        XCTAssertThrowsError(try CardAttachmentStore.coverThumbnail(for: KanbanAttachment(fileName: "missing-\(UUID()).jpg")))
        XCTAssertEqual(SampleData.lists.flatMap(\.allCards).compactMap(\.coverAttachment).count, 6)

        let drafts = PersonalListExample.allCases.map { $0.makeCollection(existingTitles: []) } /* Uncommitted Note drafts */

        XCTAssertEqual(drafts.flatMap(\.lists).flatMap(\.allCards).compactMap(\.coverAttachment).count, 3)
        XCTAssertTrue(CardAttachmentStore.fileNames(in: drafts.flatMap(\.lists)).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLargeLocalCoverIsDownsampledAndRemovalKeepsItsMedia()
    /// @brief      Verify actual large-photo decoding and non-destructive cover disabling
    /// @details    Creates one synthetic PNG; cleans only its uniquely named fixture file
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Media creation, decoding, validation, or cleanup errors
    ///
    func testLargeLocalCoverIsDownsampledAndRemovalKeepsItsMedia() throws {

        let format = UIGraphicsImageRendererFormat() /* Image-rendering configuration */

        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600), format: format) /* Synthetic image renderer */
        let bytes = renderer.pngData { context in /* Rendered PNG bytes for the oversized cover */
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }

        let photo = try CardAttachmentStore.saveMedia(bytes, kind: .photo, fileExtension: "png") /* Synthetic photo fixture */
        let fileName = try XCTUnwrap(photo.fileName) /* Stored avatar filename */

        defer {

            try? CardAttachmentStore.removeDeletedFiles([fileName], keeping: [])
        }

        var card = KanbanCard(id: 1, word: "Synthetic", listTitle: "Local", checklists: [], attachments: [photo]) /* Card value under verification */

        try card.setCover(photo.id)

        let image = try XCTUnwrap(try CardAttachmentStore.coverThumbnail(for: photo).cgImage) /* Synthetic image fixture */

        XCTAssertEqual(image.width,  960)
        XCTAssertEqual(image.height, 640)

        try card.setCover(nil)

        XCTAssertEqual(card.attachments, [photo])
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(CardAttachmentStore.fileURL(for: photo)).path))
        XCTAssertThrowsError(try CardAttachmentStore.coverThumbnail(for: KanbanAttachment(fileName: fileName, mediaKind: .video)))


    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverRowsRemainBoundedAndCanBeDisabledWithoutContentChanges()
    /// @brief      Measure cover visibility in actual Standard/Overview card rows
    /// @details    Uses isolated display preferences and rejects mutation callbacks during layout
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference suite setup errors
    ///
    @MainActor
    func testCoverRowsRemainBoundedAndCanBeDisabledWithoutContentChanges() throws {

        let suite = "Plenact.CoverLayoutTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let photo = KanbanAttachment(mediaKind: .photo, exampleImage: .garden) /* Synthetic photo fixture */
        let card = KanbanCard(id: 1, word: "Garden", listTitle: "Local", checklists: [], /* Card value under verification */
                              attachments: [photo], coverAttachmentID: photo.id, subtitleOverride: "",
                              appearance: ItemAppearance(accent: .green, icon: .home, background: .teal))


        ///
        /// @fcn        PlenactBoardDocumentTests.testCoverRowsRemainBoundedAndCanBeDisabledWithoutContentChanges.measure(_:enabled:)
        /// @brief      Host a synthetic card at a fixed width with isolated cover visibility
        /// @details    Proposes ample height to verify intrinsic content fitting
        ///
        /// @param[in]  preset   Board density
        /// @param[in]  enabled  Cover display preference
        ///
        /// @return     (CGFloat) hosted row height
        ///
        func measure(_ preset: BoardPresentation, enabled: Bool) -> CGFloat {

            defaults.set(enabled, forKey: "Plenact.CardCovers.enabled")

            let row = KanbanCardView( /* Rendered collection row */
                card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                presentation:  preset, labelLibrary: .starter,
                onUpdateCard:  { _ in XCTFail("Layout must not change covers") },
                onDeleteCard:  { XCTFail("Layout must not delete") },
                onArchiveCard: { XCTFail("Layout must not archive") },
                onToggle:      { XCTFail("Layout must not toggle") }
            ).defaultAppStorage(defaults)
            return UIHostingController(rootView: row).sizeThatFits(in: CGSize(width: 320, height: 10_000)).height
        }

        let standard = measure(.standard, enabled: true) /* Standard Card baseline */
        let overview = measure(.overview, enabled: true) /* Overview layout measurement */

        XCTAssertGreaterThan(standard, overview)
        XCTAssertGreaterThan(standard, measure(.standard, enabled: false) + 100)
        XCTAssertGreaterThan(overview, measure(.overview, enabled: false) + 50)
        XCTAssertLessThan(standard, 350)
        XCTAssertEqual(card.coverAttachmentID, photo.id)
        XCTAssertEqual(card.attachments,       [photo])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPermanentCardDeletionIncludesArchivesAndRemovesOnlyOwningBookmarks()
    /// @brief      Remove retained card records without affecting other Board-local identities
    /// @details    Exercises an archived list and keeps an independent collection with an equal
    ///             card ID
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testPermanentCardDeletionIncludesArchivesAndRemovesOnlyOwningBookmarks() {

        let card = KanbanCard(id: 12, word: "Synthetic", listTitle: "Retained", checklists: []) /* Card value under verification */
        var archivedList = KanbanList(id: 3, title: "Retained", cards: [], archivedCards: [card]) /* List containing archived records */

        archivedList.isArchived = true

        var snapshot = [archivedList, KanbanList(id: 4, title: "Other", cards: [ /* Persisted snapshot under verification */
            KanbanCard(id: 13, word: "Keep", listTitle: "Other", checklists: [])
        ])]
        let independent = [archivedList] /* Independent archived List set */
        var bookmarks: Set<Int> = [12, 13] /* Saved-card bookmarks before deletion */

        BoardContentDeletion.card(12, in: &snapshot, savedCardIDs: &bookmarks)

        XCTAssertTrue(snapshot[0].allCards.isEmpty)
        XCTAssertEqual(snapshot[1].cards.map(\.id),  [13])
        XCTAssertEqual(bookmarks,                    [13])
        XCTAssertEqual(independent[0].archivedCards, [card])

        BoardContentDeletion.card(12, in: &snapshot, savedCardIDs: &bookmarks)

        XCTAssertEqual(bookmarks, [13])
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
    func testPermanentListDeletionRemovesNestedArchivesAndPreservesRemainingOrder() throws {

        let first = KanbanList(id: 1, title: "First", cards: [ /* First value in the comparison */
            KanbanCard(id: 10, word: "Active", listTitle: "First", checklists: [])
        ], archivedCards: [
            KanbanCard(id: 11, word: "Archived", listTitle: "First", checklists: [])
        ])
        let second = KanbanList(id: 2, title: "Keep", cards: [ /* Second value in the comparison */
            KanbanCard(id: 12, word: "Keep", listTitle: "Keep", checklists: [])
        ])
        var snapshot = [first, second] /* Persisted snapshot under verification */
        var bookmarks: Set<Int> = [10, 11, 12] /* Saved-card bookmarks before deletion */

        BoardContentDeletion.list(1, in: &snapshot, savedCardIDs: &bookmarks)

        XCTAssertEqual(snapshot,  [second])
        XCTAssertEqual(bookmarks, [12])

        BoardContentDeletion.list(2, in: &snapshot, savedCardIDs: &bookmarks)

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertTrue(bookmarks.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(snapshot)), [])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDeletionMediaCleanupPreservesRetainedCopiesAndUnrelatedFiles()
    /// @brief      Remove only explicit deletion candidates with no remaining references
    /// @details    Creates synthetic media files; protects archive/undo references and an unrelated
    ///             file
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     File creation or cleanup failures
    ///
    func testDeletionMediaCleanupPreservesRetainedCopiesAndUnrelatedFiles() throws {

        let candidate = try CardAttachmentStore.saveMedia(Data([1, 2, 3]), kind: .photo, fileExtension: "jpg") /* Candidate value for validation */
        let unrelated = try CardAttachmentStore.saveMedia(Data([4, 5, 6]), kind: .photo, fileExtension: "jpg") /* Unrelated retained value */
        let candidateName = try XCTUnwrap(candidate.fileName) /* Candidate display name */
        let unrelatedName = try XCTUnwrap(unrelated.fileName) /* Unrelated display name */

        defer {

            try? CardAttachmentStore.removeDeletedFiles([candidateName, unrelatedName], keeping: [])
        }

        var card = KanbanCard(id: 1, word: "Retained", listTitle: "Archive", checklists: []) /* Card value under verification */

        card.attachments = [candidate]

        var archived = KanbanList(id: 1, title: "Archive", cards: [], archivedCards: [card]) /* Archived value for restoration checks */

        archived.isArchived = true

        let retainedNames = CardAttachmentStore.fileNames(in: [archived]) /* Names preserved by filtering */

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
    /// @fcn        PlenactBoardDocumentTests.testPersonalListArchiveSaveFailureLeavesPriorSnapshotUntouched()
    /// @brief      Verify personal lists archive through the same save-first boundary as Boards
    /// @details    Retains nested cards/bookmarks, then forces encoding failure with an infinite
    ///             date
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite setup or checked-save failures
    ///
    func testPersonalListArchiveSaveFailureLeavesPriorSnapshotUntouched() throws {

        let suite = "Plenact.ListLifecycleTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let original = PersonalListExample.shopping.makeCollection(existingTitles: []) /* Pre-operation value for preservation checks */

        try PersonalCollectionStore.saveChecked([original], to: defaults)

        let archived = try PersonalCollectionStore.archiveCollection(id: original.id, in: [original], to: defaults) /* Archived value for restoration checks */

        XCTAssertFalse(archived[0].isActive)
        XCTAssertEqual(archived[0].lists, original.lists)

        var invalid = original /* Malformed fixture input */
        invalid.lists[0].cards[0].dueDate = Date(timeIntervalSinceReferenceDate: .infinity)

        XCTAssertThrowsError(try PersonalCollectionStore.archiveCollection(id: invalid.id, in: [invalid], to: defaults))
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), archived)


    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekSaveCompletionRunsOnlyAfterSuccessfulWrite()
    /// @brief      Gate deletion cleanup on successful ordered persistence
    /// @details    Checks valid completion and rejects completion when JSON encoding fails
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Fixture setup failures
    ///
    @MainActor
    func testWeekSaveCompletionRunsOnlyAfterSuccessfulWrite() async throws {

        let suite = "Plenact.DeletionCompletionTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }

        let success = expectation(description: "Completion follows write") /* Successful operation result */

        KanbanBoardPersistence.enqueueSave([], suiteName: suite, onSuccess: {

            XCTAssertNotNil(defaults.data(forKey: "Plenact.Board.v1"))
            success.fulfill()
        })
        await fulfillment(of: [success], timeout: 2)

        var invalid = KanbanCard(id: 1, word: "Invalid", listTitle: "List", checklists: []) /* Malformed fixture input */

        invalid.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)

        let rejected = expectation(description: "No cleanup after failed write") /* Expectation that failed writes skip completion cleanup */

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
    /// @fcn        PlenactBoardDocumentTests.testCheckedWeekDeletionWaitsForEarlierWritesAndPreservesDiskOnFailure()
    /// @brief      Verify a checked destructive save cannot be overwritten by older queued edits
    /// @details    Uses isolated preferences and rejects an unencodable remaining card without
    ///             changing disk
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite setup, encoding, or decoding errors
    ///
    @MainActor
    func testCheckedWeekDeletionWaitsForEarlierWritesAndPreservesDiskOnFailure() throws {

        let suite = "Plenact.CheckedDeletionTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let prior = [KanbanList(id: 1, title: "Earlier edit", cards: [ /* Prior persisted value */
            KanbanCard(id: 1, word: "Synthetic", listTitle: "Earlier edit", checklists: [])
        ])]
        KanbanBoardPersistence.enqueueSave(prior, suiteName: suite)
        try KanbanBoardPersistence.saveListsChecked([], suiteName: suite)

        let saved = try XCTUnwrap(defaults.data(forKey: "Plenact.Board.v1")) /* Persisted value under verification */

        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: saved), [])

        var invalid = prior /* Malformed fixture input */
        invalid[0].cards[0].dueDate = Date(timeIntervalSinceReferenceDate: .infinity)

        XCTAssertThrowsError(try KanbanBoardPersistence.saveListsChecked(invalid, suiteName: suite))
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), saved)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalListExamplesContainSafeIndependentCards()
    /// @brief      Verify the six example lists meet their content and compatibility contract
    /// @details    Checks card limits, unique local IDs, empty optional activity/media fields,
    ///             correct list ownership, and Codable round trips
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Collection encoding or decoding failures
    ///
    func testPersonalListExamplesContainSafeIndependentCards() throws {

        XCTAssertEqual(PersonalListExample.allCases.map(\.rawValue), [
            "On the Table", "In the Queue", "Scheduled", "Shopping", "Up for Brew", "Misc"
        ])

        for example in PersonalListExample.allCases {

            let collection = example.makeCollection(existingTitles: []) /* Collection state under verification */

            XCTAssertEqual(collection.kind,        .list)
            XCTAssertEqual(collection.lists.count, 1)
            XCTAssertTrue(collection.isActive)
            XCTAssertTrue(collection.savedCardIDs.isEmpty)
            XCTAssertGreaterThanOrEqual(collection.cardCount, 5)
            XCTAssertLessThanOrEqual(collection.cardCount, 20)

            let cards = collection.lists[0].cards /* Card records under inspection */

            XCTAssertEqual(Set(cards.map(\.id)).count,   cards.count)
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

                for attachment in card.attachments ?? [] {

                    XCTAssertNotNil(attachment.exampleImage)
                    XCTAssertNil(attachment.fileName)
                    XCTAssertNil(attachment.url)
                }

                if card.coverAttachmentID != nil {

                    XCTAssertNotNil(card.coverAttachment)
                }
            }

            let restored = try JSONDecoder().decode( /* Restored value under verification */
                PersonalCollection.self, from: JSONEncoder().encode(collection)
            )

            XCTAssertEqual(restored, collection)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleDraftsDoNotWriteOrReplaceExistingCollections()
    /// @brief      Preserve stored Week and personal work while generating or discarding examples
    /// @details    Uses isolated preferences, fresh draft identities, collision-safe naming, and an
    ///             explicit append/save; checks existing collections and Week bytes remain
    ///             unchanged
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Fixture setup, checked-save, or JSON encoding failures
    ///
    func testExampleDraftsDoNotWriteOrReplaceExistingCollections() throws {

        let suite = "Plenact.PersonalExampleTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let week = try JSONEncoder().encode(SampleData.lists) /* Archived weekly-board fixture */

        defaults.set(week, forKey: "Plenact.Board.v1")

        var retained = PersonalCollection(title: "Shopping", kind: .list) /* Existing collection preserved during example drafting */

        retained.isArchived = true
        retained.lists[0].cards = [KanbanCard(id: 99, word: "Existing", listTitle: "Shopping", checklists: [])]
        retained.savedCardIDs = [99]

        try PersonalCollectionStore.saveChecked([retained], to: defaults)

        let originalBytes = defaults.data(forKey: "Plenact.PersonalCollections.v1") /* Serialized bytes used by the fixture */
        let first = PersonalListExample.shopping.makeCollection(existingTitles: [retained.title]) /* First value in the comparison */
        let second = PersonalListExample.shopping.makeCollection(existingTitles: [retained.title, first.title]) /* Second value in the comparison */

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.title,                                             "Shopping (2)")
        XCTAssertEqual(second.title,                                            "Shopping (3)")
        XCTAssertEqual(defaults.data(forKey: "Plenact.PersonalCollections.v1"), originalBytes)

        var renamed = first /* Value after renaming */

        renamed.rename(to: "My shopping")

        XCTAssertTrue(renamed.lists[0].cards.allSatisfy { $0.listTitle == "My shopping" })
        XCTAssertEqual(renamed.lists[0].cards.map(\.id), first.lists[0].cards.map(\.id))

        try PersonalCollectionStore.saveChecked([retained, renamed], to: defaults)

        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [retained, renamed])
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"),    week)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryContainsOnlyPersonalCollectionsWithoutChangingWeek()
    /// @brief      Verify Library renders personal collections and one canonical Saved shortcut
    /// @details    Hosts the real Library with synthetic Week and archived content, then checks
    ///             native List item counts and unchanged snapshots, including a restored Week copy
    ///
    /// @return     (Void) records assertion failures for extra rows or changed content
    ///
    /// @throws     Scene or hosted collection-view unwrap failures and task cancellation
    ///
    @MainActor
    func testLibraryContainsOnlyPersonalCollectionsWithoutChangingWeek() async throws {

        let week = SampleData.lists /* Archived weekly-board fixture */
        var archived = PersonalCollection(title: "Archived fixture", kind: .board) /* Archived value for restoration checks */

        archived.isArchived = true

        let restored    = PersonalCollection(title: "Week Board (Restored)", kind: .board) /* Restored value under verification */
        let personal    = PersonalCollection(title: "Personal fixture", kind: .list) /* Personal List fixture filtered from demo Boards */
        let collections = [personal, restored, archived] /* Saved personal-collection state */
        let scene       = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previous    = scene.windows.first(where: \.isKeyWindow) /* Previously focused window */
        let window      = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

        defer {

            window.isHidden           = true
            window.rootViewController = nil

            previous?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testLibraryContainsOnlyPersonalCollectionsWithoutChangingWeek.collectionView(in:)
        /// @brief      Locate the native List collection in the hosted Library
        /// @details    Recursively searches subviews without changing the view hierarchy
        ///
        /// @param[in]  view  Root view to inspect
        ///
        /// @return     (UICollectionView?) first collection found, or nil when absent
        ///
        func collectionView(in view: UIView) -> UICollectionView? {

            if let collection = view as? UICollectionView /* Matched native List collection view */ {

                return collection
            }

            return view.subviews.compactMap { collectionView(in: $0) }.first
        }

        for fixtures in [[personal], collections, []] {

            var current    = fixtures /* Current collections displayed by the Library */

            let controller = UIHostingController(rootView: BoardListsView( /* Hosted controller for layout assertions */
                retainedWeekLists: week,
                collections:         Binding(get: { current }, set: { current = $0 }),
                registerListNewNote: { _ in },
                onOpenSaved:         { XCTFail("Rendering must not navigate to Saved") }
            ))

            window.frame             = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller

            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()

            try await Task.sleep(for: .milliseconds(100))

            let list = try XCTUnwrap(collectionView(in: controller.view)) /* List state under verification */

            let count = (0..<list.numberOfSections).reduce(0) { /* Number of matching values */

                $0 + list.numberOfItems(inSection: $1)
            }

            XCTAssertEqual(count, max(1, fixtures.filter(\.isActive).count),
                           "Saved navigation must not occupy a full-width Library row")
            XCTAssertEqual(current, fixtures)
            XCTAssertEqual(week,    SampleData.lists)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryRowsFitLongTitlesAndAccessibilityText()
    /// @brief      Verify Library entries fit their content across viewport and text sizes
    /// @details    Hosts synthetic collection rows at portrait/landscape widths; accessibility text
    ///             must grow vertically instead of retaining a fixed row height
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testLibraryRowsFitLongTitlesAndAccessibilityText() {

        for width: CGFloat in [280, 700] {

            let row = LibraryCollectionRow( /* Rendered collection row */
                title: "Ideas and plans for the coming season",
                subtitle: "Board · 3 lists", icon: "square.stack.3d.up", color: .blue, count: 12
            )

            let standard = UIHostingController(rootView: row.environment(\.dynamicTypeSize, .large)) /* Standard Card baseline */
                .sizeThatFits(in: CGSize(width: width, height: 10_000))

            let accessible = UIHostingController(rootView: row.environment(\.dynamicTypeSize, .accessibility5)) /* Accessibility-sized layout */
                .sizeThatFits(in: CGSize(width: width, height: 10_000))

            XCTAssertEqual(standard.width,   width, accuracy: 1)
            XCTAssertEqual(accessible.width, width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(standard.height, 68)
            XCTAssertGreaterThan(accessible.height, standard.height)
            XCTAssertLessThan(accessible.height, 1_000)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardPresentationWidthsInPortraitLandscapeAndAccessibility()
    /// @brief      Verify preset widths and invalid-geometry handling
    /// @details    Checks exact caps, landscape capacity, narrow viewports, and accessibility
    ///             sizing
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testBoardPresentationWidthsInPortraitLandscapeAndAccessibility() {

        XCTAssertEqual(BoardPresentation.standard.columnWidth(viewportWidth: 393, accessibilitySize: false), 329)
        XCTAssertEqual(BoardPresentation.overview.columnWidth(viewportWidth: 393, accessibilitySize: false), 240)
        XCTAssertEqual(BoardPresentation.standard.columnWidth(viewportWidth: 852, accessibilitySize: false), 360)
        XCTAssertEqual(BoardPresentation.overview.columnWidth(viewportWidth: 852, accessibilitySize: false), 240)
        XCTAssertLessThanOrEqual(2 * 360 + 17 + 28, 852)
        XCTAssertLessThanOrEqual(3 * 240 + 24 + 28, 852)

        for preset in BoardPresentation.allCases {

            XCTAssertEqual(preset.columnWidth(viewportWidth: 320, accessibilitySize: true),  292)
            XCTAssertEqual(preset.columnWidth(viewportWidth: 200, accessibilitySize: false), 172)

            for width: CGFloat in [0, 28, -1, .nan, .infinity] {

                XCTAssertEqual(preset.columnWidth(viewportWidth: width, accessibilitySize: false), 1)
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSingleListCollectionUsesAvailableStandardWidthWithoutChangingOverview()
    /// @brief      Verify Standard personal-list width fills the viewport without changing Board presets
    /// @details    Checks portrait, landscape, narrow, invalid, and accessibility widths against
    ///             exact usable-width values; default Week and multi-list behavior retains its cap
    ///
    /// @return     (Void) records assertion failures for incorrect column widths
    ///
    func testSingleListCollectionUsesAvailableStandardWidthWithoutChangingOverview() {

        for width: CGFloat in [320, 393, 852] {

            XCTAssertEqual(BoardPresentation.standard.columnWidth(
                viewportWidth: width, accessibilitySize: false, fillsAvailableWidth: true
            ), width - 28)

            XCTAssertEqual(BoardPresentation.standard.columnWidth(
                viewportWidth: width, accessibilitySize: false
            ), min(width - 28, 360, max(172, width - 64)))

            XCTAssertEqual(BoardPresentation.overview.columnWidth(
                viewportWidth: width, accessibilitySize: false, fillsAvailableWidth: true
            ), min(width - 28, 240))

            XCTAssertEqual(BoardPresentation.overview.columnWidth(
                viewportWidth: width, accessibilitySize: true, fillsAvailableWidth: true
            ), width - 28)
        }

        for width: CGFloat in [0, 28, -1, .nan, .infinity] {

            XCTAssertEqual(BoardPresentation.standard.columnWidth(
                viewportWidth: width, accessibilitySize: false, fillsAvailableWidth: true
            ), 1)
        }
    }

        func testStandardBoardHasEqualFifteenPointNeighborPreviews() {

            for viewport: CGFloat in [320, 360, 393, 414, 424] {
                let width = BoardPresentation.standard.columnWidth(viewportWidth: viewport, accessibilitySize: false)
                let sideInset = (viewport - width) / 2
                XCTAssertEqual(sideInset - 17, 15, accuracy: 0.001,
                               "Each side must show 15 points of its neighbor after the 17-point gap")
                XCTAssertEqual(width + 2 * sideInset, viewport, accuracy: 0.001)
            }
        }

        @MainActor
        func testHostedStandardBoardCentersRequestedListWithEqualNeighborPreviews() async throws {

            let suite = "Plenact.CenteredBoard.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defaults.set(BoardPresentation.standard.rawValue, forKey: BoardPresentation.storageKey)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previous?.makeKey()
                defaults.removePersistentDomain(forName: suite)
            }
            func collections(in view: UIView) -> [UICollectionView] {
                if let collection = view as? UICollectionView { return [collection] }
                return view.subviews.flatMap { collections(in: $0) }
            }
            let lists = (1...3).map { KanbanList(id: $0, title: "Synthetic \($0)", cards: []) }
            var targetListID: Int? = 2
            let controller = UIHostingController(rootView: ContentView(
                lists: .constant(lists),
                boardTargetListID: Binding(get: { targetListID }, set: { targetListID = $0 }),
                onListsChanged: { _ in XCTFail("Layout must not change records") }
            ).defaultAppStorage(defaults))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            // The native card collection is inset four points inside each List panel.
            let frames = collections(in: controller.view).map {
                $0.convert($0.bounds, to: window).insetBy(dx: -4, dy: 0)
            }.sorted { $0.minX < $1.minX }
            XCTAssertEqual(frames.count, 3)
            let center = try XCTUnwrap(frames.first { abs($0.midX - 196.5) < 2 })
            XCTAssertEqual(center.width, 329, accuracy: 1)
            XCTAssertEqual(center.minX, 32, accuracy: 1)
            XCTAssertEqual(393 - center.maxX, 32, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(frames.first).maxX, 15, accuracy: 1)
            XCTAssertEqual(393 - (try XCTUnwrap(frames.last).minX), 15, accuracy: 1)
            XCTAssertEqual(center.minX - (try XCTUnwrap(frames.first).maxX), 17, accuracy: 1)
            XCTAssertEqual((try XCTUnwrap(frames.last).minX) - center.maxX, 17, accuracy: 1)
            XCTAssertNil(targetListID)
        }

    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionListWidthReachesTheHostedCardContainer()
    /// @brief      Verify the real personal collection adapter widens Standard list and card containers
    /// @details    Hosts List and Board collections with isolated presentation preferences and
    ///             compares native card-container widths in portrait and landscape without mutations
    ///
    /// @return     (Void) records assertion failures for container width or content changes
    ///
    /// @throws     Fixture or hosted-view unwrap failures and task cancellation
    ///
    @MainActor
    func testPersonalCollectionListWidthReachesTheHostedCardContainer() async throws {

        let suite    = "Plenact.CollectionWidthTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */
        let scene    = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previous = scene.windows.first(where: \.isKeyWindow) /* Previously focused window */
        let window   = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

        defer {

            window.isHidden           = true
            window.rootViewController = nil

            previous?.makeKey()
            defaults.removePersistentDomain(forName: suite)
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionListWidthReachesTheHostedCardContainer.collectionView(in:)
        /// @brief      Locate the rendered list's native card collection
        /// @details    Recursively searches hosted subviews without modifying the hierarchy
        ///
        /// @param[in]  view  Root view to inspect
        ///
        /// @return     (UICollectionView?) first collection found, or nil when absent
        ///
        func collectionView(in view: UIView) -> UICollectionView? {

            if let collection = view as? UICollectionView /* Matched native List collection view */ {

                return collection
            }

            return view.subviews.compactMap { collectionView(in: $0) }.first
        }

        for width: CGFloat in [393, 852] {

            for preset in BoardPresentation.allCases {

                defaults.set(preset.rawValue, forKey: BoardPresentation.storageKey)

                var measured: [PersonalCollectionKind: CGFloat] = [:] /* Measured layout dimensions */

                for kind in [PersonalCollectionKind.list, .board] {

                    var fixture = PersonalCollection(title: "Synthetic collection", kind: kind) /* Synthetic collection fixture */

                    fixture.lists = [SampleData.lists[0]]

                    let original   = fixture /* Pre-operation value for preservation checks */

                    let controller = UIHostingController(rootView: PersonalCollectionBoardView( /* Hosted controller for layout assertions */
                        collection: Binding(get: { fixture }, set: { fixture = $0 }),
                        boardTargetListID:         .constant(nil),
                        boardTargetCardID:         .constant(nil),
                        retainedLists:             [],
                        availablePersonalLists:    [],
                        onArchive:                 { XCTFail("Layout must not archive") },
                        onDelete:                  { XCTFail("Layout must not delete") },
                        onCommitDeletion:          { _ in XCTFail("Layout must not commit deletion") },
                        onCreateNote:              { _, _, _, _ in XCTFail("Layout must not create a Note") },
                        onMoveNote:                { _, _, _ in throw CocoaError(.validationMissingMandatoryProperty) },
                        onUpdateMovedNote:         { _, _ in XCTFail("Layout must not update a moved Note"); return false },
                        onArchiveMovedNote:        { _, _ in XCTFail("Layout must not archive a moved Note"); return false },
                        onDeleteMovedNote:         { _, _ in XCTFail("Layout must not delete a moved Note"); return false },
                        onToggleMovedNoteBookmark: { _, _, _ in XCTFail("Layout must not change a moved Note bookmark"); return false },
                        registerNewNote:           { _ in }
                    ).defaultAppStorage(defaults))

                    window.frame              = CGRect(x: 0, y: 0, width: width, height: 852)
                    window.rootViewController = controller

                    window.makeKeyAndVisible()
                    controller.view.layoutIfNeeded()

                    try await Task.sleep(for: .milliseconds(100))

                    let cards = try XCTUnwrap(collectionView(in: controller.view)) /* Card records under inspection */

                    measured[kind] = cards.bounds.width

                    XCTAssertGreaterThan(cards.bounds.width, 0)
                    XCTAssertEqual(fixture, original)
                }

                let listWidth          = try XCTUnwrap(measured[.list]) /* Proposed List width */
                let boardWidth         = try XCTUnwrap(measured[.board]) /* Proposed Board width */
                let expectedDifference = preset == .standard ? max(0, width - 28 - 360) : 0 /* Expected width difference */

                XCTAssertEqual(listWidth - boardWidth, expectedDifference, accuracy: 1)
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardPresentationPreferenceIsLocalAndLeavesBoardSnapshotsUntouched()
    /// @brief      Persist presentation independently of Board snapshots
    /// @details    Reopens an isolated AppStorage preference and compares untouched Week/collection
    ///             bytes
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap or fixture encoding failures
    ///
    @MainActor
    func testBoardPresentationPreferenceIsLocalAndLeavesBoardSnapshotsUntouched() throws {

        let suite = "Plenact.BoardPresentationTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let week = try JSONEncoder().encode(SampleData.lists) /* Archived weekly-board fixture */
        var board = PersonalCollection(title: "Synthetic project", kind: .board) /* Board state under verification */

        board.lists = SampleData.lists
        board.savedCardIDs = [0]
        board.isArchived = true

        let collections = try JSONEncoder().encode([board]) /* Saved personal-collection state */

        defaults.set(week, forKey: "Plenact.Board.v1")
        defaults.set(collections, forKey: "Plenact.PersonalCollections.v1")

        let preference = AppStorage(wrappedValue: BoardPresentation.standard, BoardPresentation.storageKey, store: defaults) /* Persisted display preference */

        XCTAssertEqual(preference.wrappedValue, .standard)

        preference.wrappedValue = .overview

        XCTAssertEqual(defaults.string(forKey: BoardPresentation.storageKey), "overview")

        let reopened = AppStorage(wrappedValue: BoardPresentation.standard, BoardPresentation.storageKey, store: defaults) /* Value loaded after reopening storage */

        XCTAssertEqual(reopened.wrappedValue, .overview)

        preference.wrappedValue = .standard

        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"),               week)
        XCTAssertEqual(defaults.data(forKey: "Plenact.PersonalCollections.v1"), collections)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRenderedCardsFitContentWithoutQuarterScreenHeights()
    /// @brief      Measure compact summaries and accessibility growth
    /// @details    Hosts both presets and rejects layout callbacks that would mutate the card
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testRenderedCardsFitContentWithoutQuarterScreenHeights() {

        let card = KanbanCard(id: 100, word: "Prepare a plan", listTitle: "Synthetic list") /* Card value under verification */


        ///
        /// @fcn        PlenactBoardDocumentTests.testRenderedCardsFitContentWithoutQuarterScreenHeights.measuredHeight(_:size:width:)
        /// @brief      Measure a synthetic card at the requested preset and text size
        /// @details    Proposes ample height so the hosting controller reports content-fitting
        ///             height
        ///
        /// @param[in]  preset  Card presentation preset
        /// @param[in]  size    Dynamic Type environment value
        /// @param[in]  width   Proposed card width in points
        ///
        /// @return     (CGFloat) hosted card height in points
        ///
        func measuredHeight(_ preset: BoardPresentation, size: DynamicTypeSize, width: CGFloat) -> CGFloat {

            let view = KanbanCardView( /* Hosted view under test */
                card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                presentation:  preset, labelLibrary: .starter,
                onUpdateCard:  { _ in XCTFail("Layout must not edit a card") },
                onDeleteCard:  { XCTFail("Layout must not delete a card") },
                onArchiveCard: { XCTFail("Layout must not archive a card") },
                onToggle:      { XCTFail("Layout must not toggle a card") }
            )
            .environment(\.dynamicTypeSize, size)

            let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */

            return controller.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        }


        let standard = measuredHeight(.standard, size: .large, width: 360) /* Standard Card baseline */
        let overview = measuredHeight(.overview, size: .large, width: 240) /* Measured Overview panel height */

        XCTAssertGreaterThanOrEqual(standard, 112)
        XCTAssertLessThan(standard, 160)
        XCTAssertGreaterThanOrEqual(overview, 80)
        XCTAssertLessThan(overview, standard)
        XCTAssertGreaterThan(measuredHeight(.overview, size: .accessibility5, width: 292), overview)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardSummaryDoesNotStretchToFillListHeight()
    /// @brief      Reject vertical expansion under a taller layout proposal
    /// @details    Compares 300- and 900-point proposals for the same synthetic card in both
    ///             presets
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testCardSummaryDoesNotStretchToFillListHeight() {

        let card = KanbanCard(id: 101, word: "Review the week ahead", listTitle: "Synthetic list") /* Card value under verification */

        for preset in BoardPresentation.allCases {

            let controller = UIHostingController(rootView: KanbanCardView( /* Hosted controller for layout assertions */
                card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                presentation: preset, labelLibrary: .starter,
                onUpdateCard: { _ in XCTFail("Layout must not edit content") },
                onDeleteCard: {}, onArchiveCard: {}, onToggle: {}
            ).environment(\.dynamicTypeSize, .large))

            let width: CGFloat = preset == .standard ? 360 : 240 /* Proposed layout width */
            let shortProposal = controller.sizeThatFits(in: CGSize(width: width, height: 300)) /* Compact-height layout proposal */
            let tallProposal = controller.sizeThatFits(in: CGSize(width: width, height: 900)) /* Tall layout proposal */

            XCTAssertEqual(shortProposal.height, tallProposal.height, accuracy: 1)
            XCTAssertLessThan(tallProposal.height, preset == .standard ? 170 : 130)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNavigationLinkedCardRowsRemainCompactInAList()
    /// @brief      Verify card sizing inside native navigation-linked List rows
    /// @details    Attaches a hosting window to the current scene and restores the prior key window
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Scene/row unwrap failures or cancellation of the layout delay
    ///
    @MainActor
    func testNavigationLinkedCardRowsRemainCompactInAList() async throws {

        let card = KanbanCard(id: 102, word: "Review the week ahead", listTitle: "Synthetic list") /* Card value under verification */
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow) /* Previously active key window */
        let window = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

        defer {

            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testNavigationLinkedCardRowsRemainCompactInAList.collectionView(in:)
        /// @brief      Locate the List's backing collection view in the hosted hierarchy
        /// @details    Recursively searches subviews and returns the first match
        ///
        /// @param[in]  view  Root of the UIKit subtree to inspect
        ///
        /// @return     (UICollectionView?) first matching view, or nil
        ///
        func collectionView(in view: UIView) -> UICollectionView? {

            if let collection = view as? UICollectionView /* Matched native List collection view */ {

                return collection
            }

            return view.subviews.compactMap { collectionView(in: $0) }.first
        }

        for preset in BoardPresentation.allCases {

            let view = NavigationStack { /* Hosted view under test */
                List {
                    NavigationLink {
                        Text("Synthetic card detail")
                    } label: {
                        KanbanCardView(
                            card:         card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
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

            let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */

            window.rootViewController = controller
            window.frame = CGRect(x: 0, y: 0, width: preset == .standard ? 360 : 240, height: 700)
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))

            let collection = try XCTUnwrap(collectionView(in: controller.view)) /* Collection state under verification */
            let row = try XCTUnwrap(collection.visibleCells.first) /* Rendered collection row */

            XCTAssertLessThan(row.bounds.height, preset == .standard ? 210 : 180)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekRootRequestPopsCardDetailWithoutChangingContent()
    /// @brief      Return from a hosted Card Detail to the Week Board without changing records
    /// @details    Opens a synthetic card through canonical routing, then changes the explicit
    ///             root request and checks the real navigation controller stack and retained data
    ///
    /// @return     (Void) records assertion failures for navigation or content regressions
    ///
    /// @throws     Fixture or navigation-controller unwrap failures and task cancellation
    ///
    @MainActor
    func testWeekRootRequestPopsCardDetailWithoutChangingContent() async throws {

        var lists            = SampleData.lists /* Board lists under verification */
        let original         = lists /* Pre-operation value for preservation checks */
        let card             = try XCTUnwrap(lists[0].cards.first { !$0.isSectionDivider }) /* Card value under verification */
        var targetList: Int? = lists[0].id /* List identity selected before returning to the Week root */
        var targetCard: Int? = card.id /* Card identity selected before returning to the Week root */
        var saved: Set<Int>  = [card.id] /* Persisted value under verification */


        ///
        /// @fcn        PlenactBoardDocumentTests.testWeekRootRequestPopsCardDetailWithoutChangingContent.board(_:)
        /// @brief      Construct the same Board identity with a new root request
        /// @details    Reuses fixture bindings so hosting updates preserve navigation state
        ///
        /// @param[in]  request  Explicit Board-root request value
        ///
        /// @return     (ContentView) synthetic Board with canonical navigation bindings
        ///
        func board(_ request: Int) -> ContentView {

            ContentView(
                lists:                   Binding(get: { lists }, set: { lists = $0 }),
                boardTargetListID:       Binding(get: { targetList }, set: { targetList = $0 }),
                boardTargetCardID:       Binding(get: { targetCard }, set: { targetCard = $0 }),
                boardRootRequest:        request,
                savedCardIDs:            Binding(get: { saved }, set: { saved = $0 }),
                onListsChanged:          { _ in XCTFail("Returning to Week must not save or edit records") },
                retainedAttachmentLists: { [] }
            )
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testWeekRootRequestPopsCardDetailWithoutChangingContent.navigation(in:)
        /// @brief      Locate the hosted Board's native navigation controller
        /// @details    Recursively searches child controllers without altering their hierarchy
        ///
        /// @param[in]  controller  Root controller to inspect
        ///
        /// @return     (UINavigationController?) first navigation controller found
        ///
        func navigation(in controller: UIViewController) -> UINavigationController? {

            if let navigation = controller as? UINavigationController /* Navigation controller found in the hosted hierarchy */ {

                return navigation
            }

            return controller.children.compactMap { navigation(in: $0) }.first
        }

        let controller = UIHostingController(rootView: board(0)) /* Hosted controller for layout assertions */
        let scene      = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previous   = scene.windows.first(where: \.isKeyWindow) /* Previously focused window */
        let window     = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

        defer {

            window.isHidden           = true
            window.rootViewController = nil

            previous?.makeKey()
        }

        window.frame              = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller

        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        try await Task.sleep(for: .milliseconds(600))

        let stack = try XCTUnwrap(navigation(in: controller)) /* Navigation stack under test */

        XCTAssertEqual(stack.viewControllers.count, 2, "The fixture must actually open Card Detail")

        controller.rootView = board(1)

        try await Task.sleep(for: .milliseconds(600))

        XCTAssertEqual(stack.viewControllers.count, 1, "An explicit Week tap must pop Card Detail")
        XCTAssertEqual(lists, original)
        XCTAssertEqual(saved, [card.id])
        XCTAssertNil(targetList)
        XCTAssertNil(targetCard)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardRelayoutAndPresetChangesDoNotMutateRetainedContent()
    /// @brief      Retain the requested list and content through Board re-layout
    /// @details    Varies viewport/preset and compares active lists, archives, bookmarks, and
    ///             visible ID
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Fixture setup failures or cancellation of the layout delay
    ///
    @MainActor
    func testBoardRelayoutAndPresetChangesDoNotMutateRetainedContent() async throws {

        let suite = "Plenact.BoardRelayoutTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        var lists = SampleData.lists /* Board lists under verification */
        lists[0].archiveCard(id: lists[0].cards[0].id)
        var archived = SampleData.lists[1] /* Archived value for restoration checks */

        archived.isArchived = true

        var archives = [archived] /* Archived-card collection */
        var saved: Set<Int> = [lists[0].archivedCards[0].id] /* Persisted value under verification */
        let focusedListID = lists[3].id /* Focused List identifier */
        var targetList: Int? = focusedListID /* List identity to focus after relayout */
        var targetCard: Int? /* Card identity to reveal after relayout */
        var visibleListID: Int? /* Visible List identifier */
        let revealedTarget = expectation(description: "Reveal the requested middle list") /* Card revealed by edge navigation */
        var didRevealTarget = false /* Whether navigation revealed its target */
        let originalLists = lists /* List snapshots before movement */
        let originalArchives = archives /* Archive snapshots before movement */
        let originalSaved = saved /* Saved-card identifiers before movement */
        let view = ContentView( /* Hosted view under test */
            lists: Binding(get: { lists }, set: { lists = $0 }),
            archivedLists:           Binding(get: { archives }, set: { archives = $0 }),
            boardTargetListID:       Binding(get: { targetList }, set: { targetList = $0 }),
            boardTargetCardID:       Binding(get: { targetCard }, set: { targetCard = $0 }),
            savedCardIDs:            Binding(get: { saved }, set: { saved = $0 }),
            onListViewed:            { listID in
                visibleListID = listID
                if listID == focusedListID && !didRevealTarget {

                    didRevealTarget = true
                    revealedTarget.fulfill()
                }
            },
            boardTitle:              "Synthetic board",
            onListsChanged:          { _ in XCTFail("Presentation must not request a Board save") },
            retainedAttachmentLists: { [] }
        )
        .defaultAppStorage(defaults)

        let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow) /* Previously active key window */
        let window = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

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

                XCTAssertEqual(lists,         originalLists)
                XCTAssertEqual(archives,      originalArchives)
                XCTAssertEqual(saved,         originalSaved)
                XCTAssertEqual(visibleListID, focusedListID)
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardBoundaryNavigationTargetsFirstAndLastActiveLists()
    /// @brief      Resolve direct Board jumps using the current ordered list snapshot
    /// @details    Checks first/last identity, a single-list Board, an empty Board, and unchanged
    ///             list/card records
    ///
    /// @return     (Void) records assertion failures for incorrect edge targets or mutations
    ///
    func testBoardBoundaryNavigationTargetsFirstAndLastActiveLists() {

        let lists = SampleData.lists /* Board lists under verification */
        let original = lists /* Pre-operation value for preservation checks */

        XCTAssertEqual(BoardListReordering.boundaryListID(.first, in: lists),                  lists.first?.id)
        XCTAssertEqual(BoardListReordering.boundaryListID(.last,  in: lists),                   lists.last?.id)
        XCTAssertEqual(BoardListReordering.boundaryListID(.first, in: Array(lists.prefix(1))), lists.first?.id)
        XCTAssertEqual(BoardListReordering.boundaryListID(.last,  in: Array(lists.prefix(1))),  lists.first?.id)
        XCTAssertNil(BoardListReordering.boundaryListID(.first, in: []))
        XCTAssertNil(BoardListReordering.boundaryListID(.last,  in: []))
        XCTAssertEqual(lists, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardHeaderSwipeAreaFillsAvailableWidth()
    /// @brief      Keep short Board titles from shrinking the header swipe target
    /// @details    Measures the actual header title region at several available widths, with
    ///             and without a Library back action, and checks its minimum touch height
    ///
    /// @return     (Void) records assertion failures for a narrow swipe target
    ///
    @MainActor
    func testBoardHeaderSwipeAreaFillsAvailableWidth() {

        for hasBackAction in [false, true] {

            let header = BoardHeader( /* Rendered Board header */
                settings:           .constant(BoardDisplaySettings()),
                presentation:        .constant(.standard),
                activeMembers:       [],
                memberColors:        [:],
                onRenameMember:      { _, _ in },
                onDeleteMember:      { _ in },
                onSetMemberColor:    { _, _ in },
                onOpenCalendar:      {},
                title:               "Week",
                subtitle:            "Plan",
                allowsAddingLists:   true,
                onClose:             hasBackAction ? {} : nil,
                onViewArchivedLists: {},
                onArchiveBoard:      nil,
                onDeleteBoard:       nil,
                deleteBoardTitle:    "Delete Board",
                onJumpToFirstList:   { XCTFail("Layout must not navigate") },
                onJumpToLastList:    { XCTFail("Layout must not navigate") },
                onAddList:           {}
            )
            let controller = UIHostingController(rootView: header.titleSwipeArea) /* Hosted controller for layout assertions */

            for width in [CGFloat(180), 280, 600] {

                let size = controller.sizeThatFits(in: CGSize(width: width, height: 200)) /* Proposed layout dimensions */

                XCTAssertEqual(size.width, width, accuracy: 0.5, "Blank header space must belong to the swipe area")
                XCTAssertGreaterThanOrEqual(size.height, 44)
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardHeaderSwipeMapsDeliberateHorizontalGesturesToBoundaries()
    /// @brief      Recognize intentional horizontal header swipes without capturing vertical movement
    /// @details    Checks left/right direction, minimum travel, vertical-dominant drags, and
    ///             nonfinite gesture values
    ///
    /// @return     (Void) records assertion failures for swipe classification
    ///
    func testBoardHeaderSwipeMapsDeliberateHorizontalGesturesToBoundaries() {

        XCTAssertEqual(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: -60, height: 8)), .last)
        XCTAssertEqual(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: 60,  height: -8)), .first)
        XCTAssertNil(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: -47,              height: 0)))
        XCTAssertNil(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: 70,               height: 55)))
        XCTAssertNil(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: CGFloat.infinity, height: 0)))
        XCTAssertNil(BoardListReordering.boundary(forHorizontalSwipe: CGSize(width: 70,               height: CGFloat.nan)))
        XCTAssertNil(BoardListReordering.boundary(
            forHorizontalSwipe: CGSize(width: 100, height: 0), minimumDistance: CGFloat.infinity
        ))
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
    func testListReorderingMovesRestoredMondayToFirstWithoutChangingContent() throws {

        var lists = SampleData.lists /* Board lists under verification */
        let monday = lists.removeFirst() /* Restored Monday List after reordering */

        lists.append(monday)

        XCTAssertTrue(BoardListReordering.move(monday.id, to: 0, in: &lists))
        XCTAssertEqual(lists, SampleData.lists)
        XCTAssertTrue(BoardListReordering.move(monday.id, to: lists.count - 1, in: &lists))
        XCTAssertEqual(lists.last, monday)

        let restored = try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists)) /* Restored value under verification */

        XCTAssertEqual(restored, lists)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListReorderingRejectsMissingAndOutOfBoundsMoves()
    /// @brief      Leave list order unchanged for invalid or redundant moves
    /// @details    Exercises missing IDs, both bounds, and the current position
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testListReorderingRejectsMissingAndOutOfBoundsMoves() {

        var lists = SampleData.lists /* Board lists under verification */
        let original = lists /* Pre-operation value for preservation checks */

        XCTAssertFalse(BoardListReordering.move(999,         to: 0,           in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: -1,          in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: lists.count, in: &lists))
        XCTAssertFalse(BoardListReordering.move(lists[0].id, to: 0,           in: &lists))
        XCTAssertEqual(lists, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardReorderingMovesDividersAndPreservesCompleteRecords()
    /// @brief      Reorder Today and Board rows without altering their retained card content
    /// @details    Moves a section divider between cards and verifies complete records retain
    ///             their stable identities and values
    ///
    /// @return     (Void) records assertion failures for order or content changes
    ///
    func testCardReorderingMovesDividersAndPreservesCompleteRecords() {

        let first = KanbanCard(id: 1, word: "First", listTitle: "Synthetic", descriptionOverride: "Keep this") /* First retained card fixture */
        let divider = KanbanCard(id: 2, word: "", listTitle: "Synthetic", isDivider: true) /* Movable divider fixture */
        let last = KanbanCard(id: 3, word: "Last", listTitle: "Synthetic", isTitleChecked: true) /* Last retained card fixture */
        var cards = [first, divider, last] /* Ordered focused-list records */

        XCTAssertTrue(BoardCardReordering.move(divider.id, to: 2, in: &cards))
        XCTAssertEqual(cards, [first, last, divider])
        XCTAssertEqual(cards.map(\.id), [1, 3, 2])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardReorderingClampsDestinationsAndRejectsMissingOrNoOpMoves()
    /// @brief      Keep card reorder behavior bounded and unchanged for invalid requests
    /// @details    Verifies clamped insertion at the first position, missing identity rejection,
    ///             and unchanged-order rejection without losing any records
    ///
    /// @return     (Void) records assertion failures for invalid reorder requests
    ///
    func testCardReorderingClampsDestinationsAndRejectsMissingOrNoOpMoves() {

        let cardsBeforeMove = SampleData.lists[0].cards /* Original complete card sequence */
        var cards = cardsBeforeMove /* Mutable card-order copy */

        guard let lastCardID = cards.last?.id else { /* Stable identity moved to the first position */

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
    func testCardMovementPreservesCompleteRecordAndRetainedArchives() throws {

        var card = try XCTUnwrap(SampleData.lists[0].cards.first { !$0.isSectionDivider }) /* Card value under verification */

        card.attachments = [KanbanAttachment(fileName: "synthetic-drag.jpg", mediaKind: .photo)]
        try card.useLibraryCover(.music)
        card.comments = [KanbanComment(author: "Synthetic", body: "Keep this note")]
        card.members = [.manual("Example")]
        card.labelIDs = ["synthetic-label"]
        card.startDate = Date(timeIntervalSince1970: 1234)
        card.dueDate = Date(timeIntervalSince1970: 5678)
        card.descriptionOverride = "Retain every field"

        let retained = KanbanCard(id: 901, word: "Archived", listTitle: "Source") /* Archived Card retained by its source List */
        var lists = [ /* Board lists under verification */
            KanbanList(id: 1, title: "Source", cards: [card], archivedCards: [retained]),
            KanbanList(id: 2, title: "Destination", cards: [
                KanbanCard(id: 902, word: "First", listTitle: "Destination"),
                KanbanCard(id: 903, word: "Last", listTitle: "Destination")
            ])
        ]
        let savedIDs: Set<Int> = [card.id] /* Saved Card IDs preserved during movement */

        XCTAssertTrue(try BoardCardMovement.move(card.id, to: 2, before: 903, in: &lists))

        var expected = card /* Expected result for comparison */

        expected.listTitle = "Destination"

        XCTAssertEqual(lists[1].cards,           [lists[1].cards[0], expected, lists[1].cards[2]])
        XCTAssertEqual(lists[1].cards.map(\.id), [902, card.id, 903])
        XCTAssertTrue(lists[0].cards.isEmpty)
        XCTAssertEqual(lists[0].archivedCards,                                                         [retained])
        XCTAssertEqual(lists.flatMap(\.cards).filter { savedIDs.contains($0.id) },                     [expected])
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
    func testCardMovementSupportsEmptyListsAndSameListInsertionBoundaries() throws {

        let cards = (1...4).map { KanbanCard(id: $0, word: "Card \($0)", listTitle: "A") } /* Card records under inspection */
        var lists = [KanbanList(id: 10, title: "A", cards: cards), /* Board lists under verification */
                     KanbanList(id: 20, title: "Empty", cards: [])]

        XCTAssertTrue(try BoardCardMovement.move(1, to: 10, before: 4, in: &lists))
        XCTAssertEqual(lists[0].cards.map(\.id), [2, 3, 1, 4])
        XCTAssertTrue(try BoardCardMovement.move(4, to: 10, before: 2, in: &lists))
        XCTAssertEqual(lists[0].cards.map(\.id), [4, 2, 3, 1])
        XCTAssertFalse(try BoardCardMovement.move(2, to: 10, before: 3, in: &lists))
        XCTAssertFalse(try BoardCardMovement.move(2, to: 10, before: 2, in: &lists))
        XCTAssertTrue(try BoardCardMovement.move(2, to: 10, in: &lists))
        XCTAssertEqual(lists[0].cards.map(\.id), [4, 3, 1, 2])
        XCTAssertTrue(try BoardCardMovement.move(2, to: 20, in: &lists))
        XCTAssertEqual(lists[1].cards.map(\.id),    [2])
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
    func testCardMovementRejectsStaleArchivedAndAmbiguousSourcesAtomically() throws {

        let card = KanbanCard(id: 1, word: "Card", listTitle: "A") /* Card value under verification */
        let divider = KanbanCard(id: 2, word: "", listTitle: "A", isDivider: true) /* Section-divider fixture */
        let archive = KanbanCard(id: 3, word: "Retained", listTitle: "A") /* Archived-card snapshot */
        var lists = [KanbanList(id: 10, title: "A", cards: [card, divider], archivedCards: [archive]), /* Board lists under verification */
                     KanbanList(id: 20, title: "B", cards: [])]
        let original = lists /* Pre-operation value for preservation checks */

        for (id, destination, before) in [(999, 20, nil), (1, 999, nil), (1, 20, 999), (3, 20, nil)] as [(Int, Int, Int?)] {

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

    func testDividerMovementPreservesRecordsWithinAndBetweenLists() throws {
        let divider = KanbanCard(id: 2, word: "---", listTitle: "A", isDivider: true, checklists: [])
        let card = KanbanCard(id: 1, word: "Synthetic", listTitle: "A", checklists: [])
        var lists = [KanbanList(id: 10, title: "A", cards: [divider, card]),
                     KanbanList(id: 20, title: "B", cards: [])]
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
    /// @fcn        PlenactBoardDocumentTests.testCardDropGeometryUsesMidpointsAndRejectsOutsideViewport()
    /// @brief      Verify insertion targeting across row midpoints and viewport boundaries
    /// @details    Uses synthetic offset frames to check empty lists, gaps, nonfinite coordinates,
    ///             missing measurements, and unmeasured trailing rows without moving records.
    ///
    /// @return     (Void) records assertion failures for incorrect geometry targets
    ///
    func testCardDropGeometryUsesMidpointsAndRejectsOutsideViewport() {

        let lists = [KanbanList(id: 10, title: "A", cards: [ /* Board lists under verification */
            KanbanCard(id: 1, word: "A", listTitle: "A"),
            KanbanCard(id: 2, word: "B", listTitle: "A"),
            KanbanCard(id: 3, word: "C", listTitle: "A")
        ]), KanbanList(id: 20, title: "Empty", cards: [])]
        let listFrames = [10: CGRect(x: 100, y: 50, width: 200, height: 600), /* Rendered List frame map */
                          20: CGRect(x: 320, y: 50, width: 180, height: 160)]
        let frames = [1: CGRect(x: 100, y: 130, width: 200, height: 100), /* Measured layout frames */
                      2: CGRect(x: 100, y: 238, width: 200, height: 100),
                      3: CGRect(x: 100, y: 346, width: 200, height: 100)]
        let viewport = CGRect(x: 100, y: 50, width: 400, height: 600) /* Visible Board viewport */


        ///
        /// @fcn        PlenactBoardDocumentTests.testCardDropGeometryUsesMidpointsAndRejectsOutsideViewport.target(_:_:frames:)
        /// @brief      Resolve a synthetic drop point relative to the fixture viewport
        /// @details    Adds the viewport origin to test coordinates and forwards the selected row
        ///             frames to canonical target resolution.
        ///
        /// @param[in]  x       Horizontal test offset from the fixture viewport origin
        /// @param[in]  y       Vertical test offset from the fixture viewport origin
        /// @param[in]  frames  Synthetic card frames used for this target query
        ///
        /// @return     (BoardCardDropTarget?) resolved fixture target, or nil for a rejected point
        ///
        func target(_ x: CGFloat, _ y: CGFloat, frames: [Int: CGRect] = frames) -> BoardCardDropTarget? {

            BoardCardMovement.target(for: 99, at: CGPoint(x: x + viewport.minX, y: y + viewport.minY), viewport: viewport,
                                     lists: lists, listFrames: listFrames, cardFrames: frames)
        }

        XCTAssertEqual(target(50,  129),  BoardCardDropTarget(listID: 10, beforeCardID: 1))
        XCTAssertEqual(target(50,  130),  BoardCardDropTarget(listID: 10, beforeCardID: 2))
        XCTAssertEqual(target(50,  238),  BoardCardDropTarget(listID: 10, beforeCardID: 3))
        XCTAssertEqual(target(50,  400),  BoardCardDropTarget(listID: 10, beforeCardID: nil))
        XCTAssertEqual(target(250, 100), BoardCardDropTarget(listID: 20,  beforeCardID: nil))
        XCTAssertNil(target(210,  100))
        XCTAssertNil(target(-1,   100))
        XCTAssertNil(target(401,  100))
        XCTAssertNil(target(50,   601))
        XCTAssertNil(target(.nan, 100))
        XCTAssertNil(BoardCardMovement.target(for: 99, at: CGPoint(x: 150, y: 150),
                                             viewport: CGRect(x: 100, y: 50, width: CGFloat.infinity, height: 600),
                                             lists:    lists, listFrames: listFrames, cardFrames: frames))
        XCTAssertNil(target(50, 100, frames: [:]))
        XCTAssertEqual(target(50, 280, frames: [2: frames[2]!]), BoardCardDropTarget(listID: 10, beforeCardID: 3),
                       "A long list's viewport edge must not silently append past unmeasured rows")
        XCTAssertEqual(lists[0].cards.map(\.id), [1, 2, 3], "Hovering must not move records")


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
    func testCardMovementPersistsInWeekAndPersonalBoardWithoutChangingOtherBoards() async throws {

        let suite = "Plenact.CardMovementTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        var lists = SampleData.lists /* Board lists under verification */
        let card = try XCTUnwrap(lists[0].cards.first { !$0.isSectionDivider }) /* Card value under verification */
        let destination = lists[1].id /* Target location for the move */

        try BoardCardMovement.move(card.id, to: destination, in: &lists)
        KanbanBoardPersistence.enqueueSave(lists, suiteName: suite)

        let reloaded = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite) /* Document loaded after reopening storage */

        XCTAssertEqual(reloaded, lists)

        var personal = PersonalCollection(title: "Synthetic Board", kind: .board) /* Personal List fixture filtered from demo Boards */

        personal.lists = SampleData.lists
        personal.savedCardIDs = [card.id]

        var independent = PersonalCollection(title: "Separate Board", kind: .board) /* Separate personal Board retained by movement */

        independent.lists = personal.lists
        try BoardCardMovement.move(card.id, to: destination, in: &personal.lists)

        XCTAssertEqual(independent.lists, SampleData.lists)

        let decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(personal)) /* Decoded personal collection after persistence */

        XCTAssertEqual(decoded.lists, lists)

        try PersonalCollectionStore.saveChecked([personal, independent], to: defaults)

        let restored = PersonalCollectionStore.load(from: defaults) /* Restored value under verification */

        XCTAssertEqual(restored.map(\.lists),        [personal.lists, independent.lists])
        XCTAssertEqual(restored.first?.savedCardIDs, [card.id])


    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDayViewNativeDragReordersCanonicalNotesAndPreservesCancelledDrags()
    /// @brief      Exercise the focused Day view's actual native drag and drop callbacks
    /// @details    Checks append, divider boundaries, cancellation, and outside drops against
    ///             the canonical binding without changing record content.
    ///
    /// @return     (Void) records assertion failures for interaction installation or row layout
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    @MainActor
    func testDayViewNativeDragReordersCanonicalNotesAndPreservesCancelledDrags() async throws {
        let note = KanbanCard(id: 10, word: "Synthetic Note", listTitle: "Thursday",
                              checklists: [], descriptionOverride: "Retained body", presentation: .note)
        let divider = KanbanCard(id: 11, word: "--", listTitle: "Thursday", isDivider: true, checklists: [])
        let card = KanbanCard(id: 12, word: "Synthetic Card", listTitle: "Thursday", checklists: [])
        var lists = [KanbanList(id: 4, title: "Thursday", cards: [note, divider, card])]
        let original = lists
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        func collectionView(in view: UIView) -> UICollectionView? {
            if let collection = view as? UICollectionView { return collection }
            return view.subviews.compactMap { collectionView(in: $0) }.first
        }
        let controller = UIHostingController(rootView: TodayListDetailView(
            lists: Binding(get: { lists }, set: { lists = $0 }), reservedLists: [],
            labelLibrary: .constant(.starter), savedCardIDs: .constant([note.id]),
            listID: 4, currentUserName: "Synthetic", onClose: {}, onOpenWeek: {},
            onPermanentDelete: { _ in XCTFail("Dragging must not delete"); return false }
        ))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let collection = try XCTUnwrap(collectionView(in: controller.view))
        let noteCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let source = try XCTUnwrap(noteCell.contentView.interactions.compactMap {
            ($0 as? UIDragInteraction)?.delegate as? BoardCardDragSource.Coordinator
        }.first)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 4)
        let receiver = try XCTUnwrap(collection.dropDelegate as? BoardCardDropSurface.Coordinator)
        let item = UIDragItem(itemProvider: source.begin(at: noteCell.convert(CGPoint(x: 30, y: 30), to: window)))
        item.localObject = source
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(receiver.accepts([item]))
        XCTAssertFalse(receiver.perform([item], at: CGPoint(x: -100, y: -100)))
        source.finish()
        XCTAssertEqual(lists, original, "An outside drop must not mutate canonical records")

        let secondItem = UIDragItem(itemProvider: source.begin(at: noteCell.convert(CGPoint(x: 30, y: 30), to: window)))
        secondItem.localObject = source
        try await Task.sleep(for: .milliseconds(100))
        let addCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 3, section: 0)))
        let endPoint = addCell.convert(CGPoint(x: 30, y: addCell.bounds.midY), to: window)
        XCTAssertTrue(receiver.perform([secondItem], at: endPoint))
        source.finish()
        XCTAssertEqual(lists[0].cards, [divider, card, note])
        XCTAssertEqual(Set(lists[0].cards.map(\.id)), Set(original[0].cards.map(\.id)))

        try await Task.sleep(for: .milliseconds(150))
        let currentCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 2, section: 0)))
        let currentSource = try XCTUnwrap(currentCell.contentView.interactions.compactMap {
            ($0 as? UIDragInteraction)?.delegate as? BoardCardDragSource.Coordinator
        }.first)
        _ = currentSource.begin(at: currentCell.convert(CGPoint(x: 30, y: 30), to: window))
        currentSource.finish()
        XCTAssertEqual(lists[0].cards, [divider, card, note], "Cancelled drags retain order and content")

        let returnItem = UIDragItem(itemProvider: currentSource.begin(
            at: currentCell.convert(CGPoint(x: 30, y: 30), to: window)
        ))
        returnItem.localObject = currentSource
        try await Task.sleep(for: .milliseconds(100))
        let dividerCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let firstPoint = dividerCell.convert(CGPoint(x: 30, y: 1), to: window)
        let currentReceiver = try XCTUnwrap(collection.dropDelegate as? BoardCardDropSurface.Coordinator)
        XCTAssertTrue(currentReceiver.perform([returnItem], at: firstPoint))
        currentSource.finish()
        XCTAssertEqual(lists, original, "Dragging before a divider must restore the original complete records")

        try await Task.sleep(for: .milliseconds(150))
        let movableDividerCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
        let dividerSource = try XCTUnwrap(movableDividerCell.contentView.interactions.compactMap {
            ($0 as? UIDragInteraction)?.delegate as? BoardCardDragSource.Coordinator
        }.first)
        let dividerItem = UIDragItem(itemProvider: dividerSource.begin(
            at: movableDividerCell.convert(CGPoint(x: 30, y: 10), to: window)
        ))
        dividerItem.localObject = dividerSource
        try await Task.sleep(for: .milliseconds(100))
        let dividerReceiver = try XCTUnwrap(collection.dropDelegate as? BoardCardDropSurface.Coordinator)
        let tailCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 3, section: 0)))
        XCTAssertTrue(dividerReceiver.perform([dividerItem], at: tailCell.convert(
            CGPoint(x: 30, y: tailCell.bounds.midY), to: window
        )))
        dividerSource.finish()
        XCTAssertEqual(lists[0].cards, [note, card, divider])
    }

    ///
    /// @fcn        PlenactBoardDocumentTests.testWholeCardDragSourcesAndInsertionMarkersKeepNativeListRowIdentityAndLayout()
    /// @brief      Verify hosted card rows install native drag and one shared list receiver
    /// @details    Checks row count, enabled drag sources, receiver identity, collection
    ///             delegation, and bounds across presentation presets and accessibility text sizes.
    ///             Restores the prior key window after the synthetic layout fixture.
    ///
    /// @return     (Void) records assertion failures for interaction installation or row layout
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    @MainActor
    func testWholeCardDragSourcesAndInsertionMarkersKeepNativeListRowIdentityAndLayout() async throws {

        let list = KanbanList(id: 1, title: "Synthetic", cards: [ /* List state under verification */
            KanbanCard(id: 10, word: "A card with a longer title", listTitle: "Synthetic"),
            KanbanCard(id: 11, word: "", listTitle: "Synthetic", isDivider: true),
            KanbanCard(id: 12, word: "Another card", listTitle: "Synthetic")
        ])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) /* Active scene for UI hosting */
        let previous = scene.windows.first(where: \.isKeyWindow) /* Previously focused window */
        let window = UIWindow(windowScene: scene) /* Temporary window for UI hosting */

        defer {

            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testWholeCardDragSourcesAndInsertionMarkersKeepNativeListRowIdentityAndLayout.collectionView(in:)
        /// @brief      Find the first collection view in the hosted synthetic view tree
        /// @details    Returns the current view when it is a collection, otherwise recursively
        ///             searches its subviews in order.
        ///
        /// @param[in]  view  Root view to search for the hosted collection
        ///
        /// @return     (UICollectionView?) first collection view found, or nil when none exists
        ///
        func collectionView(in view: UIView) -> UICollectionView? {

            if let collection = view as? UICollectionView /* Matched native List collection view */ {

                return collection
            }

            return view.subviews.compactMap { collectionView(in: $0) }.first
        }

        for (preset, textSize, width) in [
            (BoardPresentation.standard, DynamicTypeSize.large, 360.0),
            (.overview, .large, 240.0),
            (.standard, .accessibility5, 320.0)
        ] {
            let view = KanbanListView( /* Hosted view under test */
                list: list, availableListHeight: 700, displaySettings: BoardDisplaySettings(),
                presentation:         preset, labelLibrary: .starter, toggleCardTitle: { _ in },
                canMoveEarlier:       false, canMoveLater: false, onAddCard: { _, _, _ in },
                onCopyList:           {}, onMoveList: { _ in }, onSortList: { _ in }, onArchiveCompleted: {},
                archivedCards:        .constant([]), onRestoreArchivedCard: { _ in },
                onDeleteArchivedCard: { _ in }, onArchiveList: {}, onDeleteList: {},
                onDeleteCard:         { _ in }, onArchiveCard: { _ in },
                onUpdateCard:         { _ in XCTFail("Layout must not update records") },
                onMoveCard:           { _, _ in XCTFail("Layout must not reorder records") },
                onListDragChanged:    { _ in }, onListDragEnded: {},
                draggedCardID:        10, dropBeforeCardID: 12, isCardDropTarget: true,
                onCardDragChanged:    { _, _ in XCTFail("Layout must not begin a drag") },
                onCardDragEnded:      { _, _, _ in }
            ).environment(\.dynamicTypeSize, textSize)
            let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */

            window.frame = CGRect(x: 0, y: 0, width: width, height: 800)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))

            let collection = try XCTUnwrap(collectionView(in: controller.view)) /* Collection state under verification */
            let itemCount = (0..<collection.numberOfSections).reduce(0) { /* Expected item count */
                $0 + collection.numberOfItems(inSection: $1)
            }

            XCTAssertEqual(itemCount, 4, "Insertion markers must not introduce extra reorderable rows")

            let dragSources = collection.visibleCells.flatMap { cell in /* Registered drag-source views */
                cell.contentView.interactions.compactMap { $0 as? UIDragInteraction }.filter {
                    $0.delegate is BoardCardDragSource.Coordinator
                }
            }

            XCTAssertFalse(dragSources.isEmpty, "Visible card bodies must have a native drag source")
            let dividerCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
            XCTAssertTrue(dividerCell.contentView.interactions.contains {
                ($0 as? UIDragInteraction)?.delegate is BoardCardDragSource.Coordinator
            }, "Divider rows must support the same native drag as Cards and Notes")
            XCTAssertTrue(dragSources.allSatisfy(\.isEnabled))
            XCTAssertEqual(collection.interactions.filter {
                ($0 as? UIDropInteraction)?.delegate is BoardCardDropSurface.Coordinator
            }.count, 1, "Visible row probes must share exactly one native list drop receiver")
            XCTAssertTrue(collection.dropDelegate is BoardCardDropSurface.Coordinator,
                          "The native List collection must forward its drop callbacks to canonical movement")
            XCTAssertGreaterThan(collection.bounds.height, 0)
            XCTAssertLessThanOrEqual(collection.bounds.width, width)
        }


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
    func testNativeCardDragSourceUsesLocalTokenAndEndsCancellationOnce() async throws {

        let declarations = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]]) /* Declarations under inspection */
        let declaration = try XCTUnwrap(declarations.first { /* Declaration record under inspection */
            ($0["UTTypeIdentifier"] as? String) == BoardCardDragSource.contentType.identifier
        })

        XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], ["public.data"])

        var points: [CGPoint] = [] /* Sample layout coordinates */
        var ended = 0 /* Completed drag state */
        let source = BoardCardDragSource(token: "synthetic-session", /* Source state before the operation */
                                         onBegan: { points.append($0) },
                                         onChanged: { points.append($0) },
                                         onEnded:   { ended += 1 })
        let coordinator = source.makeCoordinator() /* Drop coordinator under test */
        let point = CGPoint(x: 150, y: 320) /* Synthetic drop coordinate */
        let provider = coordinator.begin(at: point) /* Native drag-item provider */

        XCTAssertEqual(points, [point])
        XCTAssertTrue(coordinator.isDragging)
        XCTAssertEqual(provider.suggestedName,             "synthetic-session")
        XCTAssertEqual(provider.registeredTypeIdentifiers, [BoardCardDragSource.contentType.identifier])

        let data: Data = try await withCheckedThrowingContinuation { continuation in /* Serialized fixture bytes */
            provider.loadDataRepresentation(forTypeIdentifier: BoardCardDragSource.contentType.identifier) { data, error in
                if let error /* Captured operation error */ {

                    continuation.resume(throwing: error)
                }
                else if let data /* Response bytes supplied by the data-provider callback */ {

                    continuation.resume(returning: data)
                }
                else {

                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }

        XCTAssertEqual(String(data: data, encoding: .utf8), "synthetic-session",
                       "Native drag payload must not contain card content or file references")

        coordinator.finish()
        coordinator.finish()

        XCTAssertFalse(coordinator.isDragging)
        XCTAssertEqual(ended, 1, "Drop/cancellation cleanup must not run twice")
        XCTAssertTrue(coordinator.responds(to: NSSelectorFromString("dragInteraction:session:didEndWithOperation:")),
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
    func testNativeCardDragSourceSurvivesSourceRemovalUntilSessionEnd() {

        var ended = 0 /* Completed drag state */
        let source = BoardCardDragSource(token: "synthetic-session", onBegan: { _ in }, onChanged: { _ in }, /* Source state before the operation */
                                         onEnded: { ended += 1 })
        let coordinator = source.makeCoordinator() /* Drop coordinator under test */
        let container = UIView() /* Target drop container */
        let interaction = UIDragInteraction(delegate: coordinator) /* Captured drag interaction */

        container.addInteraction(interaction)
        coordinator.container = container
        coordinator.interaction = interaction
        _ = coordinator.begin(at: CGPoint(x: 1, y: 2))
        BoardCardDragSource.dismantleUIView(BoardCardDragSource.Probe(), coordinator: coordinator)

        XCTAssertEqual(ended, 0, "Virtualizing the source row must not end a live drag")
        XCTAssertTrue(coordinator.isDragging)
        XCTAssertTrue(container.interactions.contains { $0 === interaction })

        coordinator.finish()

        XCTAssertEqual(ended, 1)
        XCTAssertFalse(container.interactions.contains { $0 === interaction })


    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNativeCardDropCommitsOriginalRecordAndRejectsForeignOrEndedSessions()
    /// @brief      Verify native receiver commits preserve the original card record
    /// @details    Exercises a same-token active source against the real receiver callback, rejects
    ///             a foreign token and ended source, and checks unchanged card metadata plus
    ///             cleared drag state.
    ///
    /// @return     (Void) records assertion failures for accepted or rejected drop behavior
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    @MainActor
    func testNativeCardDropCommitsOriginalRecordAndRejectsForeignOrEndedSessions() throws {

        let card = KanbanCard(id: 1, word: "Synthetic", listTitle: "Source") /* Card value under verification */
        var lists = [KanbanList(id: 10, title: "Source", cards: [card]), /* Board lists under verification */
                     KanbanList(id: 20, title: "Destination", cards: [])]
        var ends = 0 /* Drag completion events */
        let source = BoardCardDragSource(token: "local-board", onBegan: { _ in }, /* Source state before the operation */
                                         onChanged: { _ in }, onEnded: { ends += 1 }).makeCoordinator()
        let item = UIDragItem(itemProvider: source.begin(at: .zero)) /* Checklist item under verification */

        item.localObject = source

        var points: [CGPoint] = [] /* Sample layout coordinates */
        let drop = BoardCardDropSurface(token: "local-board", onChanged: { points.append($0) }, /* Drop operation result */
                                        onDrop: { point in
            guard let target = BoardCardMovement.target( /* Resolved destination for the dragged Card */
                for: card.id, at: point, viewport: CGRect(x: 0, y: 100, width: 400, height: 600),
                lists:      lists, listFrames: [20: CGRect(x: 200, y: 100, width: 200, height: 600)],
                cardFrames: [:]
            ) else { return false }
            do {

                return try BoardCardMovement.move(card.id, to: target.listID, in: &lists)
            }
            catch {

                XCTFail("Drop failed: \(error)"); return false
            }
        }).makeCoordinator()
        let foreign = BoardCardDropSurface(token: "another-board", onChanged: { _ in XCTFail("Foreign hover") }, /* Foreign collection fixture */
                                           onDrop: { _ in XCTFail("Foreign drop"); return false }).makeCoordinator()

        XCTAssertFalse(foreign.accepts([item]))
        XCTAssertFalse(drop.accepts([UIDragItem(itemProvider: NSItemProvider())]))
        XCTAssertTrue(drop.accepts([item]))

        drop.surface.isEnabled = false

        XCTAssertFalse(drop.accepts([item]), "Explicit native reorder mode must disable the cross-list receiver")

        drop.surface.isEnabled = true

        XCTAssertTrue(drop.perform([item], at: CGPoint(x: 250, y: 300)))
        XCTAssertTrue(lists[0].cards.isEmpty)

        var expected = card /* Expected result for comparison */

        expected.listTitle = "Destination"

        XCTAssertEqual(lists[1].cards, [expected])
        XCTAssertEqual(points,         [CGPoint(x: 250, y: 300)])

        source.finish()

        XCTAssertEqual(ends, 1)
        XCTAssertFalse(drop.accepts([item]))
        XCTAssertFalse(drop.perform([item], at: CGPoint(x: 250, y: 300)))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListDragEdgeThresholdsAndInvalidGeometry()
    /// @brief      Verify drag-edge activation at exact thresholds
    /// @details    Shared thresholds govern both list reordering and card-drag horizontal scrolling
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testListDragEdgeThresholdsAndInvalidGeometry() {

        XCTAssertEqual(BoardListReordering.edgeDirection(at: 63,   viewportWidth: 400),       -1)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 64,   viewportWidth: 400),       0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 336,  viewportWidth: 400),      0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 337,  viewportWidth: 400),      1)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 200,  viewportWidth: 400),      0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: .nan, viewportWidth: 400),     0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 20,   viewportWidth: 0),         0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 20,   viewportWidth: .infinity), 0)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 17,   viewportWidth: 100),       -1)
        XCTAssertEqual(BoardListReordering.edgeDirection(at: 83,   viewportWidth: 100),       1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundWeekPersistenceKeepsArchivedListsAndAllowsEmptyWorkspace()
    /// @brief      Persist retained archives and an intentionally empty Week
    /// @details    Uses an isolated suite and awaits the ordered persistence queue after each save
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap failures
    ///
    @MainActor
    func testBackgroundWeekPersistenceKeepsArchivedListsAndAllowsEmptyWorkspace() async throws {

        let suite = "Plenact.WeekArchiveTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        var archived = SampleData.lists[1] /* Archived value for restoration checks */

        archived.isArchived = true

        let snapshot = [SampleData.lists[0], archived] /* Persisted snapshot under verification */

        KanbanBoardPersistence.enqueueSave(snapshot, suiteName: suite)

        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite) /* Restored value under verification */

        XCTAssertEqual(restored, snapshot)

        KanbanBoardPersistence.enqueueSave([], suiteName: suite)

        let emptyWeek = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite) /* Empty weekly-board fixture */

        XCTAssertTrue(emptyWeek.isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListArchiveBindingsPreserveCardsAndRestoreAtEnd()
    /// @brief      Preserve list records through active/archive binding projections
    /// @details    Archives, round-trips, and appends the restored list after existing active lists
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     JSON round-trip or archived-list unwrap failures
    ///
    @MainActor
    func testListArchiveBindingsPreserveCardsAndRestoreAtEnd() throws {

        let original = SampleData.lists[0] /* Pre-operation value for preservation checks */
        var snapshot = [original, SampleData.lists[1]] /* Persisted snapshot under verification */
        let board = Binding(get: { snapshot }, set: { snapshot = $0 }) /* Board state under verification */
        var archived = original /* Archived value for restoration checks */

        archived.isArchived = true
        board.archivedLists.wrappedValue.append(archived)
        board.activeLists.wrappedValue.removeAll { $0.id == original.id }

        XCTAssertEqual(board.activeLists.wrappedValue.map(\.id), [1])
        XCTAssertEqual(board.archivedLists.wrappedValue,         [archived])

        snapshot = try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(board.archivedLists.wrappedValue, [archived])

        var restored = try XCTUnwrap(board.archivedLists.wrappedValue.first) /* Restored value under verification */

        restored.isArchived = false
        board.activeLists.wrappedValue.append(restored)
        board.archivedLists.wrappedValue.removeAll { $0.id == original.id }

        XCTAssertEqual(snapshot, [SampleData.lists[1], original])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWholeWeekArchiveRestoresAsSeparateUniquelyNamedBoard()
    /// @brief      Restore a Week archive as a separate personal Board
    /// @details    Checks collision-safe naming while retaining IDs, archived lists/cards, and
    ///             bookmarks
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Collection encoding or decoding errors
    ///
    func testWholeWeekArchiveRestoresAsSeparateUniquelyNamedBoard() throws {

        var archivedList = SampleData.lists[1] /* List containing archived records */

        archivedList.isArchived = true

        var list = SampleData.lists[0] /* List state under verification */

        list.archiveCard(id: list.cards[0].id)

        let sourceLists = [list, archivedList] /* Source List snapshots */
        let savedIDs: Set<Int> = [list.archivedCards[0].id] /* Card IDs expected in the archived-week snapshot */
        var board = PersonalCollection.archivedWeekBoard(lists: sourceLists, savedCardIDs: savedIDs) /* Board state under verification */
        let boardID = board.id /* Stable Board identifier */

        XCTAssertEqual(board.isArchived, true)

        board = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(board))
        board.restore(existingTitles: ["Week Board", "Week Board (Restored)", "week board (restored) (2)"])

        XCTAssertEqual(board.title, "Week Board (Restored) (3)")
        XCTAssertTrue(board.isActive)
        XCTAssertEqual(board.id,                     boardID)
        XCTAssertEqual(board.lists,                  sourceLists)
        XCTAssertEqual(board.savedCardIDs,           savedIDs)
        XCTAssertEqual(board.lists[0].archivedCards, list.archivedCards)
        XCTAssertTrue(board.lists[1].isArchived)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testArchivedPersonalBoardPersistsAndRestoresWithoutRenamingItsLists()
    /// @brief      Persist archive state and restore a personal Board with its lists intact
    /// @details    Resolves a Board-title collision without changing contained lists or saved-card
    ///             IDs
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Checked saves, JSON conversion, or Board unwrap failures
    ///
    func testArchivedPersonalBoardPersistsAndRestoresWithoutRenamingItsLists() throws {

        let suite = "Plenact.BoardArchiveTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        var board = PersonalCollection(title: "Project", kind: .board, icon: .project) /* Board state under verification */

        board.isArchived = true
        board.lists[0].cards = [KanbanCard(id: 77, word: "Task", listTitle: board.lists[0].title)]
        board.lists[1].isArchived = true
        board.savedCardIDs = [77]
        try PersonalCollectionStore.saveChecked([board], to: defaults)

        var restored = try XCTUnwrap(PersonalCollectionStore.load(from: defaults).first) /* Restored value under verification */

        XCTAssertFalse(restored.isActive)

        restored.restore(existingTitles: ["project"])

        XCTAssertEqual(restored.title,        "Project (2)")
        XCTAssertEqual(restored.lists,        board.lists)
        XCTAssertEqual(restored.savedCardIDs, board.savedCardIDs)
        XCTAssertTrue(restored.isActive)

        try PersonalCollectionStore.saveChecked([restored], to: defaults)

        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [restored])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardArchiveSavesBeforeReturningUpdatedState()
    /// @brief      Confirm successful archive commits return the saved collection state
    /// @details    Keeps the input and unrelated collection unchanged while checking persisted
    ///             output
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap or checked-save failures
    ///
    func testPersonalBoardArchiveSavesBeforeReturningUpdatedState() throws {

        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let board = PersonalCollection(title: "Project", kind: .board) /* Board state under verification */
        let other = PersonalCollection(title: "Shopping", kind: .list) /* Unrelated model fixture */
        let original = [board, other] /* Pre-operation value for preservation checks */
        let updated = try PersonalCollectionStore.archiveBoard(id: board.id, in: original, to: defaults) /* Updated state after mutation */

        XCTAssertTrue(original[0].isActive)
        XCTAssertFalse(updated[0].isActive)
        XCTAssertEqual(updated[1],                                   other)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), updated)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardArchiveFailureKeepsMemoryAndSavedSnapshotActive()
    /// @brief      Reject an unencodable archive without publishing a new collection state
    /// @details    An infinite card date forces encoding failure; memory and the saved Board stay
    ///             active
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Fixture setup or initial checked-save failures
    ///
    func testPersonalBoardArchiveFailureKeepsMemoryAndSavedSnapshotActive() throws {

        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let board = PersonalCollection(title: "Project", kind: .board) /* Board state under verification */

        try PersonalCollectionStore.saveChecked([board], to: defaults)

        var draft = board /* Uncommitted draft under test */
        var invalidCard = KanbanCard(id: 1, word: "Unsaved", listTitle: draft.lists[0].title) /* Unsupported Card fixture */

        invalidCard.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)
        draft.lists[0].cards = [invalidCard]
        var collections = [draft] /* Saved personal-collection state */

        XCTAssertThrowsError(
            collections = try PersonalCollectionStore.archiveBoard(id: draft.id, in: collections, to: defaults)
        )
        XCTAssertEqual(collections, [draft])
        XCTAssertTrue(collections[0].isActive)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [board])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardArchiveRejectsMissingBoardWithoutChangingSavedData()
    /// @brief      Preserve saved collections when the requested Board ID is absent
    /// @details    Attempts archive with an unrelated UUID and compares the original stored
    ///             collection
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Fixture setup or initial checked-save failures
    ///
    func testPersonalBoardArchiveRejectsMissingBoardWithoutChangingSavedData() throws {

        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let board = PersonalCollection(title: "Project", kind: .board) /* Board state under verification */

        try PersonalCollectionStore.saveChecked([board], to: defaults)

        XCTAssertThrowsError(try PersonalCollectionStore.archiveBoard(id: UUID(), in: [board], to: defaults))
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [board])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyPersonalBoardDefaultsToActiveAndArchivedListsStayOutOfSearch()
    /// @brief      Preserve legacy active defaults and exclude archived lists from active
    ///             projections
    /// @details    Omits isArchived from old JSON, then verifies hidden cards/counts and demo
    ///             validation
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     JSON conversion or unwrap failures
    ///
    func testLegacyPersonalBoardDefaultsToActiveAndArchivedListsStayOutOfSearch() throws {

        let original = PersonalCollection(title: "Project", kind: .board) /* Pre-operation value for preservation checks */
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]) /* Serialized JSON object */

        object.removeValue(forKey: "isArchived")

        var decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONSerialization.data(withJSONObject: object)) /* Decoded legacy personal collection */

        XCTAssertTrue(decoded.isActive)
        decoded.lists[0].cards = [KanbanCard(id: 500, word: "Hidden activity", listTitle: decoded.lists[0].title)]
        decoded.lists[0].isArchived = true
        XCTAssertFalse(decoded.matches("Hidden activity"))
        XCTAssertEqual(decoded.cardCount, 0)

        let document = PlenactBoardDocument(lists: decoded.lists, labelLibrary: .starter) /* Board document under test */

        XCTAssertEqual(document.validationMessage, "Archived lists are stored locally and cannot be published to the shared Board.")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyListsLoadWithEmptyArchiveAndKeepExistingJSONShape()
    /// @brief      Preserve the old list JSON shape when no archive is present
    /// @details    Decodes a three-field list and checks its re-encoded key set
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     JSON conversion or unwrap failures
    ///
    func testLegacyListsLoadWithEmptyArchiveAndKeepExistingJSONShape() throws {

        let data = Data("{\"id\":1,\"title\":\"Monday\",\"cards\":[]}".utf8) /* JSON fixture bytes for the compatibility check */
        let list = try JSONDecoder().decode(KanbanList.self, from: data) /* Decoded List fixture */

        XCTAssertTrue(list.archivedCards.isEmpty)

        let encoded = try JSONEncoder().encode(list) /* Encoded model payload */
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]) /* Serialized JSON object */

        XCTAssertEqual(Set(object.keys), ["id", "title", "cards"])
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
    func testArchivingAndRestoringPreservesFullCardAndDivider() throws {

        var completed = SampleData.lists[0].cards[0] /* Completed checklist-item fixture */

        completed.isTitleChecked = true
        completed.attachments = [KanbanAttachment(fileName: "synthetic-archive.jpg", mediaKind: .photo)]

        let active = KanbanCard(id: 500, word: "Active", listTitle: "Monday") /* Active Card before archival */
        let divider = KanbanCard(id: 501, word: "Divider", listTitle: "Monday", isDivider: true, isTitleChecked: true) /* Section-divider fixture */
        var list = KanbanList(id: 1, title: "Monday", cards: [completed, divider, active]) /* List state under verification */

        list.archiveCompletedCards()

        XCTAssertEqual(list.cards,                                                        [divider, active])
        XCTAssertEqual(list.archivedCards,                                                [completed])
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
    /// @fcn        PlenactBoardDocumentTests.testArchivedCardsStayOutOfSearchAndReserveTheirIDs()
    /// @brief      Exclude archived cards from active search without reusing their identities
    /// @details    Includes retained cards in ID allocation and rejects archives in shared-demo
    ///             documents
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testArchivedCardsStayOutOfSearchAndReserveTheirIDs() {

        let archived = KanbanCard(id: 900, word: "Archived task", listTitle: "Monday", isTitleChecked: true) /* Archived value for restoration checks */
        let list = KanbanList( /* List state under verification */
            id: 1, title: "Monday",
            cards:         [KanbanCard(id: 1, word: "Active task", listTitle: "Monday")],
            archivedCards: [archived]
        )

        XCTAssertTrue(TodaySearchIndex.results(query: "Archived task", scope: .all, lists: [list], library: .starter).isEmpty)
        XCTAssertEqual(([list].flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1, 901)

        let document = PlenactBoardDocument(lists: [list], labelLibrary: .starter) /* Board document under test */

        XCTAssertEqual(document.validationMessage, "Archived cards are stored locally and cannot be published to the shared Board.")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testIndividualArchiveAcceptsIncompleteCardsAndPreservesContent()
    /// @brief      Archive individual cards independently of completion state
    /// @details    Rejects divider/duplicate archives and restores an incomplete card without
    ///             marking it done
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     List encoding or decoding errors
    ///
    func testIndividualArchiveAcceptsIncompleteCardsAndPreservesContent() throws {

        var incomplete = SampleData.lists[0].cards[0] /* Incomplete checklist-item fixture */

        incomplete.isTitleChecked = false

        XCTAssertFalse(incomplete.isTitleChecked)

        var complete = SampleData.lists[0].cards[1] /* Completed state under verification */

        complete.isTitleChecked = true

        let divider = KanbanCard(id: 800, word: "Divider", listTitle: "Monday", isDivider: true) /* Section-divider fixture */
        var list = KanbanList(id: 1, title: "Monday", cards: [incomplete, complete, divider]) /* List state under verification */

        list.archiveCard(id: incomplete.id)
        list.archiveCard(id: complete.id)
        list.archiveCard(id: incomplete.id)
        list.archiveCard(id: divider.id)

        XCTAssertEqual(list.cards,         [divider])
        XCTAssertEqual(list.archivedCards, [incomplete, complete])

        list = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        list.restoreArchivedCard(id: incomplete.id)

        XCTAssertEqual(list.cards, [divider, incomplete])
        XCTAssertFalse(list.cards[1].isTitleChecked)
        XCTAssertEqual(list.archivedCards, [complete])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalListRenamePreservesArchivedCards()
    /// @brief      Update archived cards' list-title references when renaming a personal list
    /// @details    Checks retained content and the resulting collection's JSON round trip
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Collection encoding or decoding errors
    ///
    func testPersonalListRenamePreservesArchivedCards() throws {

        var collection = PersonalCollection(title: "Original", kind: .list) /* Collection state under verification */
        let archived = KanbanCard(id: 42, word: "Archived", listTitle: "Original", isTitleChecked: true) /* Archived value for restoration checks */
        collection.lists[0].archivedCards = [archived]
        collection.rename(to: "Renamed")

        var expected = archived /* Expected result for comparison */

        expected.listTitle = "Renamed"

        XCTAssertEqual(collection.lists[0].archivedCards, [expected])

        let restored = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection)) /* Restored value under verification */

        XCTAssertEqual(restored, collection)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAPIActivityEndsAfterSuccessFailureAndCancellation()
    /// @brief      Balance activity tracking across synthetic API outcomes
    /// @details    An ephemeral intercepted session returns success, timeout, or cancellation
    ///             without networking
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Fixture unwrap/client setup failures or unexpected error types
    ///
    @MainActor
    func testAPIActivityEndsAfterSuccessFailureAndCancellation() async throws {

        let configuration = URLSessionConfiguration.ephemeral /* API client configuration */

        configuration.protocolClasses = [ActivityTestURLProtocol.self]

        let session = URLSession(configuration: configuration) /* Local API session state */

        defer {

            session.invalidateAndCancel()
        }

        for outcome in ["success", "timeout", "cancelled"] {

            let initialCount = DatabaseActivity.shared.operations.count /* Initial request count */
            let url = try XCTUnwrap(URL(string: "https://\(outcome).example.test/")) /* URL fixture for the request */
            let client = try PlenactAPIClient(baseURL: url, session: session) /* In-process API client */

            do {

                let users = try await client.directory(token: "synthetic-test-token") /* Synthetic directory users */

                XCTAssertEqual(outcome, "success")
                XCTAssertTrue(users.isEmpty)
            } catch {

                let error = try XCTUnwrap(error as? URLError) /* Captured operation error */

                XCTAssertEqual(error.code, outcome == "timeout" ? .timedOut : .cancelled)
            }

            XCTAssertEqual(DatabaseActivity.shared.operations.count, initialCount)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDatabaseActivityKeepsSpinnerUntilAllOperationsFinish()
    /// @brief      Keep activity visible until the last tracked operation ends
    /// @details    Checks message handoff and harmless repeated completion of the first operation
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testDatabaseActivityKeepsSpinnerUntilAllOperationsFinish() {

        let activity = DatabaseActivity() /* Captured activity event */
        let save = activity.begin("Saving Board...") /* Save operation under test */
        let refresh = activity.begin("Synchronizing shared database...") /* Refresh operation under test */

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
        /// @fcn        PlenactBoardDocumentTests.ActivityTestURLProtocol.canInit(with:)
        /// @brief      Accept every request in the dedicated ephemeral test session
        /// @details    The test installs this protocol only on its synthetic session configuration
        ///
        /// @param[in]  request  Request offered by URL loading
        ///
        /// @return     (Bool) true
        ///
        override class func canInit(with request: URLRequest) -> Bool {

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
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {

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
        override func startLoading() {

            Task { @MainActor in

                XCTAssertTrue(DatabaseActivity.shared.isWorking)
                XCTAssertTrue(DatabaseActivity.shared.operations.contains {
                    $0.message == "Synchronizing shared database..."
                })
                await Task.yield()

                XCTAssertTrue(DatabaseActivity.shared.isWorking)

                guard let url = request.url /* URL fixture for the request */ else {

                    XCTFail("Missing synthetic request URL")
                    client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }

                if url.host == "success.example.test" {

                    let response = HTTPURLResponse( /* Synthetic API response */
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
        /// @fcn        PlenactBoardDocumentTests.ActivityTestURLProtocol.stopLoading()
        /// @brief      Provide the required URLProtocol cancellation hook
        /// @details    This fixture performs no resource cleanup and does not cancel its spawned
        ///             task
        ///
        /// @return     (Void) provide the required URLProtocol cancellation hook
        ///
        override func stopLoading() {}
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDatabaseActivityErrorsRemainUntilDismissed()
    /// @brief      Retain a reported error after activity finishes
    /// @details    Checks that only explicit dismissal clears the error message
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testDatabaseActivityErrorsRemainUntilDismissed() {

        let activity = DatabaseActivity() /* Captured activity event */
        let operation = activity.begin("Saving Board...") /* Pending save operation */

        activity.report("Could not save the Board.")
        activity.end(operation)

        XCTAssertFalse(activity.isWorking)
        XCTAssertEqual(activity.errorMessage, "Could not save the Board.")

        activity.dismissError()

        XCTAssertNil(activity.errorMessage)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundBoardSavesPreserveLatestSnapshot()
    /// @brief      Persist the most recent queued Week snapshot
    /// @details    Enqueues two writes in an isolated suite and awaits a load before comparing
    ///             stored bytes
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference/data unwrap or JSON decoding failures
    ///
    @MainActor
    func testBackgroundBoardSavesPreserveLatestSnapshot() async throws {

        let suite = "Plenact.BackgroundBoardTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let first = [KanbanList(id: 1, title: "First", cards: [])] /* First value in the comparison */
        let last = [KanbanList(id: 1, title: "Latest", cards: [])] /* Most recent request */

        KanbanBoardPersistence.enqueueSave(first, suiteName: suite)
        KanbanBoardPersistence.enqueueSave(last, suiteName: suite)

        XCTAssertTrue(DatabaseActivity.shared.isWorking)

        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite) /* Restored value under verification */

        XCTAssertEqual(restored, last)

        let data = try XCTUnwrap(defaults.data(forKey: "Plenact.Board.v1")) /* JSON fixture bytes for the compatibility check */

        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: data), last)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundBoardSaveFailurePreservesPreviousSnapshot()
    /// @brief      Retain a valid Week snapshot when a later save cannot encode
    /// @details    Uses an infinite date to force failure and checks both retained data and error
    ///             reporting
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap failures
    ///
    @MainActor
    func testBackgroundBoardSaveFailurePreservesPreviousSnapshot() async throws {

        let suite    = "Plenact.BackgroundBoardTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }

        let original = [KanbanList(id: 1, title: "Saved", cards: [])] /* Pre-operation value for preservation checks */

        KanbanBoardPersistence.enqueueSave(original, suiteName: suite)

        _ = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)

        var invalidCard = KanbanCard(id: 1, word: "Unsaved", listTitle: "Saved") /* Unsupported Card fixture */

        invalidCard.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)

        KanbanBoardPersistence.enqueueSave(
            [KanbanList(id: 1, title: "Saved", cards: [invalidCard])], suiteName: suite
        )
        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite) /* Restored value under verification */

        XCTAssertEqual(restored, original)
        XCTAssertTrue(DatabaseActivity.shared.errorMessage?.hasPrefix("Could not save the Board:") == true)
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
    func testBackgroundBoardLoadReportsCorruptionWithoutRemovingData() async throws {

        let suite    = "Plenact.BackgroundBoardTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }

        let invalidData = Data("not JSON".utf8) /* Malformed response payload */

        defaults.set(invalidData, forKey: "Plenact.Board.v1")

        let restored = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite) /* Restored value under verification */

        XCTAssertEqual(restored, SampleData.lists)
        XCTAssertNotNil(DatabaseActivity.shared.errorMessage)
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), invalidData)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRecentSearchesAreOrderedDeduplicatedAndClearable()
    /// @brief      Verify recent-search normalization, ordering, capacity, and explicit clearing
    /// @details    Uses isolated preferences and checks case-insensitive deduplication and the
    ///             ten-entry limit
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap failures
    ///
    func testRecentSearchesAreOrderedDeduplicatedAndClearable() throws {

        let suite    = "Plenact.SearchTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        RecentSearchStore.remember("  Monday  ", in: defaults)
        RecentSearchStore.remember("Work",       in: defaults)

        XCTAssertEqual(RecentSearchStore.remember("monday", in: defaults), ["monday", "Work"])
        XCTAssertEqual(RecentSearchStore.remember("  ",     in: defaults), ["monday", "Work"])

        for index in 0..<12 {

            RecentSearchStore.remember("Search \(index)", in: defaults)
        }

        XCTAssertEqual(RecentSearchStore.load(from: defaults).count, 10)
        XCTAssertEqual(RecentSearchStore.load(from: defaults).first, "Search 11")

        RecentSearchStore.clear(in: defaults)

        XCTAssertTrue(RecentSearchStore.load(from: defaults).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSearchScopesUseOnlyTheirSelectedFields()
    /// @brief      Keep Board, label, user, and all-content searches within their intended fields
    /// @details    Uses one synthetic card to distinguish matches in title, description,
    ///             assignment, and labels
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testSearchScopesUseOnlyTheirSelectedFields() {

        let card = KanbanCard( /* Card value under verification */
            id: 1, word:         "Proposal", listTitle: "Monday",
            members:             [.manual("Jamie")], labelIDs: ["work-scheduled"],
            descriptionOverride: "Budget review"
        )
        let lists = [KanbanList(id: 0, title: "Monday", cards: [card])] /* Board lists under verification */


        ///
        /// @fcn        PlenactBoardDocumentTests.testSearchScopesUseOnlyTheirSelectedFields.matches(_:_:)
        /// @brief      Query the fixed synthetic search fixture
        /// @details    Uses the starter label library for label-name and group-name matching
        ///
        /// @param[in]  term   Search text
        /// @param[in]  scope  Fields to search
        ///
        /// @return     ([TodaySearchResult]) matching canonical references
        ///
        func matches(_ term: String, _ scope: TodaySearchScope) -> [TodaySearchResult] {

            TodaySearchIndex.results(query: term, scope: scope, lists: lists, library: .starter)
        }


        XCTAssertEqual(matches("Scheduled", .labels).map(\.cardID), [1])
        XCTAssertEqual(matches("Work",      .labels).count,         1)
        XCTAssertTrue(matches("Proposal",   .labels).isEmpty)
        XCTAssertEqual(matches("Jamie",     .users).map(\.cardID), [1])
        XCTAssertTrue(matches("Budget",     .users).isEmpty)
        XCTAssertEqual(matches("Budget",    .all).count,            1)
        XCTAssertEqual(matches("Scheduled", .all).count,            1)
        XCTAssertEqual(matches("Monday",    .boards).map(\.listID), [0])
        XCTAssertTrue(matches("Proposal", .boards).isEmpty)
        XCTAssertTrue(matches(" ",        .all).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardSearchIncludesEmptyListsAndCardSearchExcludesDividers()
    /// @brief      Keep empty lists discoverable without treating dividers as activities
    /// @details    Checks a list-only result has no card ID and divider text produces no
    ///             all-content match
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testBoardSearchIncludesEmptyListsAndCardSearchExcludesDividers() {

        let divider = KanbanCard(id: 1, word: "Divider", listTitle: "Monday", isDivider: true) /* Section-divider fixture */
        let lists = [ /* Board lists under verification */
            KanbanList(id: 0, title: "Monday",     cards: [divider]),
            KanbanList(id: 2, title: "Empty list", cards: [])
        ]
        let results = TodaySearchIndex.results(query: "Empty", scope: .boards, lists: lists, library: .starter) /* Decoded API results */

        XCTAssertEqual(results.map(\.listID), [2])
        XCTAssertNil(results.first?.cardID)
        XCTAssertTrue(TodaySearchIndex.results(query: "Divider", scope: .all, lists: lists, library: .starter).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleLoadUndoSnapshotPersistsAndClears()
    /// @brief      Round-trip the retained snapshot used by Load Example undo
    /// @details    Saves synthetic lists and today's selection in an isolated suite, then
    ///             explicitly clears them
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap failures
    ///
    func testExampleLoadUndoSnapshotPersistsAndClears() throws {

        let suite    = "Plenact.ExampleLoadUndoTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        var lists = Array(SampleData.lists.prefix(2))
        var archived = KanbanList(id: 99, title: "Previous Week", cards: lists[1].cards)
        archived.isArchived = true
        lists.append(archived)
        lists[0].archiveCard(id: lists[0].cards[0].id)
        let snapshot = ExampleLoadUndoSnapshot(lists: lists, todayListID: lists[1].id) /* Persisted snapshot under verification */

        XCTAssertTrue(ExampleLoadUndoStore.save(lists: lists, todayListID: lists[1].id, to: defaults))
        XCTAssertEqual(ExampleLoadUndoStore.load(from: defaults), snapshot)

        ExampleLoadUndoStore.clear(from: defaults)

        XCTAssertNil(ExampleLoadUndoStore.load(from: defaults))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLastViewedListResolvesSavedSelectionAndFallbacks()
    /// @brief      Resolve saved list identity against current active lists
    /// @details    Checks saved preference priority, a missing saved target, and an empty workspace
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap failures
    ///
    func testLastViewedListResolvesSavedSelectionAndFallbacks() throws {

        let suite    = "Plenact.LastViewedListTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let lists = [KanbanList(id: 4, title: "Week", cards: []), KanbanList(id: 9, title: "Shopping", cards: [])] /* Board lists under verification */

        LastViewedListStore.save(9, to: defaults)

        XCTAssertEqual(LastViewedListStore.resolve(in: lists,      fallback: 4,   from: defaults),        9)
        XCTAssertEqual(LastViewedListStore.resolve(in: [lists[0]], fallback: nil, from: defaults), 4)
        XCTAssertEqual(LastViewedListStore.resolve(in: [],         fallback: nil, from: defaults),         nil)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayFocusFollowsEveryLocalWeekdayWithoutChangingRecords()
    /// @brief      Resolve each day's canonical Week list independently of display order
    /// @details    Uses a fixed Gregorian calendar and synthetic dates, including midnight
    ///             rollover and a time-zone change, with unchanged card records
    ///
    /// @return     (Void) records assertion failures for wrong-day selection or mutations
    ///
    /// @throws     Calendar fixture construction failures
    ///
    func testTodayFocusFollowsEveryLocalWeekdayWithoutChangingRecords() throws {

        var calendar = Calendar(identifier: .gregorian) /* Fixed calendar for date assertions */

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let lists    = Array(SampleData.lists.reversed()) /* Board lists under verification */
        let original = lists /* Pre-operation value for preservation checks */
        let names    = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] /* Expected weekday title sequence */

        for (offset, name) in names.enumerated() {

            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + offset))) /* Date value for boundary checks */

            XCTAssertEqual(TodayListSelection.currentDayList(in: lists, date: date, calendar: calendar)?.title, name)
        }

        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))) /* Calendar-day boundary timestamp */

        XCTAssertEqual(TodayListSelection.currentDayList(in: lists, date: midnight.addingTimeInterval(-1), calendar: calendar)?.title, "Monday")
        XCTAssertEqual(TodayListSelection.currentDayList(in: lists, date: midnight,                        calendar: calendar)?.title,                        "Tuesday")

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -3600))

        XCTAssertEqual(TodayListSelection.currentDayList(in: lists, date: midnight, calendar: calendar)?.title, "Monday")
        XCTAssertEqual(lists,                                                                                   original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayFocusHasNoFallbackForUnavailableOrAmbiguousDay()
    /// @brief      Reject missing, renamed, archived, and duplicate current-day lists
    /// @details    Resolves a fixed Tuesday against synthetic snapshots without substituting Monday
    ///             or consulting manual selection preferences
    ///
    /// @return     (Void) records assertion failures for unintended fallback behavior
    ///
    /// @throws     Calendar fixture construction failures
    ///
    func testTodayFocusHasNoFallbackForUnavailableOrAmbiguousDay() throws {

        var calendar = Calendar(identifier: .gregorian) /* Fixed calendar for date assertions */

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let date     = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))) /* Date value for boundary checks */
        let monday   = KanbanList(id: 1, title: "Monday", cards: []) /* Monday List fixture for weekday focus */
        let tuesday  = KanbanList(id: 2, title: "Tuesday", cards: []) /* Tuesday planning fixture */
        var archived = tuesday /* Archived value for restoration checks */

        archived.isArchived = true

        XCTAssertNil(TodayListSelection.currentDayList(in: [],                                                        date: date, calendar: calendar))
        XCTAssertNil(TodayListSelection.currentDayList(in: [monday],                                                  date: date, calendar: calendar))
        XCTAssertNil(TodayListSelection.currentDayList(in: [monday, archived],                                        date: date, calendar: calendar))
        XCTAssertNil(TodayListSelection.currentDayList(in: [monday, KanbanList(id: 2, title: "Renamed", cards: [])],  date: date, calendar: calendar))
        XCTAssertNil(TodayListSelection.currentDayList(in: [tuesday, KanbanList(id: 3, title: "Tuesday", cards: [])], date: date, calendar: calendar))
        XCTAssertEqual(TodayListSelection.currentDayList(in: [monday, KanbanList(id: 2, title: " tUeSdAy ", cards: [])], date: date, calendar: calendar)?.id, 2)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testQuickCaptureCreatesMissingCurrentWeekdayList()
    /// @brief      Recreate a missing weekday list without replacing retained Week work
    /// @details    Reserves IDs across active and archived lists and returns an existing
    ///             current-weekday list unchanged when it is already available
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testQuickCaptureCreatesMissingCurrentWeekdayList() throws {

        let renamed = KanbanList(id: 7, title: "Renamed Thursday", cards: [
            KanbanCard(id: 14, word: "Keep this card", listTitle: "Renamed Thursday", checklists: [])
        ]) /* Previously renamed weekday list retained without modification */
        var archivedThursday = KanbanList(id: 20, title: "Thursday", cards: []) /* Archived weekday list reserves its old ID */
        archivedThursday.isArchived = true
        let lists = [renamed, archivedThursday] /* Complete Week fixture */
        var calendar = Calendar(identifier: .gregorian) /* Fixed calendar for deterministic weekday selection */

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8))) /* Thursday selection date */
        let result = TodayListSelection.ensureCurrentDayList(lists: lists, date: thursday, calendar: calendar) /* Recreated active weekday destination */

        XCTAssertEqual(result.dayList.id, 21)
        XCTAssertEqual(result.dayList.title, "Thursday")
        XCTAssertTrue(result.dayList.cards.isEmpty)
        XCTAssertEqual(result.lists, lists + [result.dayList])
        XCTAssertEqual(result.lists.first(where: { $0.id == renamed.id })?.cards.first?.word, "Keep this card")

        let existingResult = TodayListSelection.ensureCurrentDayList(
            lists: result.lists,
            date: thursday,
            calendar: calendar
        )

        XCTAssertEqual(existingResult.dayList.id, result.dayList.id)
        XCTAssertEqual(existingResult.lists, result.lists)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionBookmarksResolveActiveRecordsWithScopedIdentity()
    /// @brief      Resolve personal bookmarks without crossing collection-local identity boundaries
    /// @details    Excludes stale IDs, dividers, archived lists, and archived collections
    ///
    /// @return     (Void) records assertion failures for personal Saved-row resolution
    ///
    func testPersonalCollectionBookmarksResolveActiveRecordsWithScopedIdentity() {

        var first = PersonalCollection(title: "First", kind: .list) /* First independent collection */
        let firstCard = KanbanCard(id: 1, word: "First item", listTitle: "First", checklists: []) /* Active bookmark */
        let divider = KanbanCard(id: 2, word: "—", listTitle: "First", isDivider: true, checklists: []) /* Non-bookmarkable separator */
        first.lists[0].cards = [firstCard, divider]

        var archivedList = KanbanList(id: 1, title: "Archived", cards: [
            KanbanCard(id: 3, word: "Archived item", listTitle: "Archived", checklists: [])
        ])
        archivedList.isArchived = true
        first.lists.append(archivedList)
        first.savedCardIDs = [1, 2, 3, 99]

        var second = PersonalCollection(title: "Second", kind: .list) /* Another collection may reuse card ID */
        second.lists[0].cards = [KanbanCard(id: 1, word: "Second item", listTitle: "Second", checklists: [])]
        second.savedCardIDs = [1]

        let firstResult = first.bookmarkedCards
        let secondResult = second.bookmarkedCards

        XCTAssertEqual(firstResult.map(\.card.word), ["First item"])
        XCTAssertEqual(firstResult.first?.collectionID, first.id)
        XCTAssertEqual(firstResult.first?.listID, first.lists[0].id)
        XCTAssertEqual(secondResult.map(\.card.word), ["Second item"])
        XCTAssertNotEqual(firstResult.first?.id, secondResult.first?.id)

        first.isArchived = true
        XCTAssertTrue(first.bookmarkedCards.isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionPersistencePreservesOrderAndLeavesWeekUntouched()
    /// @brief      Keep personal collections ordered and independent of the Week store
    /// @details    Persists synthetic Board/list collections and compares unchanged Week bytes
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap or Week encoding failures
    ///
    func testPersonalCollectionPersistencePreservesOrderAndLeavesWeekUntouched() throws {

        let suite    = "Plenact.PersonalCollectionTests.\(UUID().uuidString)" /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) /* Isolated test preferences */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let weekSnapshot = try JSONEncoder().encode(SampleData.lists) /* Encoded weekly-board snapshot */

        defaults.set(weekSnapshot, forKey: "Plenact.Board.v1")

        var shopping            = PersonalCollection(title: "Shopping", kind: .list, icon: .shopping, color: .coral) /* Shopping-list example */
        shopping.lists[0].cards = [KanbanCard(id: 0, word: "Eggs", listTitle: "Shopping", checklists: [])]
        shopping.savedCardIDs   = [0]

        let project = PersonalCollection(title: "New Project Notes", kind: .board, icon: .project) /* Project-list example */

        PersonalCollectionStore.save([project, shopping], to: defaults)

        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [project, shopping])
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"),    weekSnapshot)
        XCTAssertEqual(shopping.lists.count,                         1)
        XCTAssertEqual(project.lists.map(\.title),                   ["Ideas", "In progress", "Done"])
        XCTAssertEqual(shopping.cardCount,                           1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionRenameAndSearchPreserveCardIdentity()
    /// @brief      Rename a personal list without replacing cards or matching dividers
    /// @details    Checks trimmed naming, synchronized list titles, active counts, and searchable
    ///             description text
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testPersonalCollectionRenameAndSearchPreserveCardIdentity() {

        var collection = PersonalCollection(title: "Shopping", kind: .list) /* Collection state under verification */

        collection.lists[0].cards = [
            KanbanCard(id: 9,  word: "Eggs",    listTitle: "Shopping", checklists: [], descriptionOverride: "Breakfast"),
            KanbanCard(id: 10, word: "Divider", listTitle: "Shopping", isDivider: true)
        ]

        collection.rename(to: "  Groceries  ")

        XCTAssertEqual(collection.title,                    "Groceries")
        XCTAssertEqual(collection.lists[0].title,           "Groceries")
        XCTAssertEqual(collection.lists[0].cards.map(\.id), [9, 10])
        XCTAssertTrue(collection.lists[0].cards.allSatisfy { $0.listTitle == "Groceries" })
        XCTAssertEqual(collection.cardCount, 1)
        XCTAssertTrue(collection.matches("eggs"))
        XCTAssertTrue(collection.matches("Breakfast"))
        XCTAssertTrue(collection.matches(" "))
        XCTAssertFalse(collection.matches("Divider"))

        var board = PersonalCollection(title: "Project", kind: .board) /* Board state under verification */

        board.rename(to: "Research")

        XCTAssertEqual(board.lists.map(\.title), ["Ideas", "In progress", "Done"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testStarterBoardDocumentRoundTrips()
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
    /// @fcn        PlenactBoardDocumentTests.testRegisteredAssigneeRequiresUUID()
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
    /// @fcn        PlenactBoardDocumentTests.testManualAssigneeCannotContainUserID()
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
    /// @fcn        PlenactBoardDocumentTests.testDocumentRejectsEmptyCardTitle()
    /// @brief      Reject a blank title before it reaches the shared API
    /// @details    Ensures local snapshot validation matches the server's required card-title
    ///             constraint
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
    /// @fcn        PlenactBoardDocumentTests.testSampleDataSeedMapsKnownStarterAssigneeToJim()
    /// @brief      Map only the known SampleData assignee to Jim's registered identity
    /// @details    Verifies the seed keeps weekday content and labels while leaving local sample
    ///             data unchanged
    ///
    /// @return     (Void) succeeds when the versioned seed remains valid and linked to Jim
    ///
    func testSampleDataSeedMapsKnownStarterAssigneeToJim() {

        let jim = PlenactRemoteUser(                                                    /* Authenticated editor identity for the seed */
            userID:      "fb13a9ee-9107-47c3-bb4f-dff07fe57eba",
            username:    "jim",
            displayName: "Jim",
            accountRole: "board_editor"
        )
        let document = PlenactAPIClient.sampleDataDocument(for: jim)                    /* Seed transformed for Jim     */
        let seededAssignments = document.lists.flatMap(\.cards).flatMap(\.members)      /* All seed assignments         */

        XCTAssertNil(document.validationMessage)
        XCTAssertEqual(document.lists.map(\.title), SampleData.listTitles)
        XCTAssertEqual(document.labelLibrary,       .starter)
        XCTAssertTrue(document.lists.flatMap(\.allCards).allSatisfy {

            $0.coverAttachmentID == nil && $0.attachments == nil && $0.listDisplayFormat == nil
        })

        XCTAssertEqual(seededAssignments.count, SampleData.lists.flatMap(\.cards).flatMap(\.members).count)
        XCTAssertTrue(seededAssignments.allSatisfy {
            $0.kind == .registeredUser && $0.userID == jim.userID && $0.displayName == jim.displayName
        })
        XCTAssertEqual(SampleData.lists[0].cards[0].members[0].kind, .manual)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSampleDataSeedRequestFitsJSONBodyLimit()
    /// @brief      Fit the complete synthetic seed request within the client's JSON body ceiling
    /// @details    Encodes the versioned document and request envelope, not just the Board payload
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Request encoding failures
    ///
    func testSampleDataSeedRequestFitsJSONBodyLimit() throws {

        let jim = PlenactRemoteUser( /* Synthetic directory-user fixture */
            userID:      "fb13a9ee-9107-47c3-bb4f-dff07fe57eba",
            username:    "jim",
            displayName: "Jim",
            accountRole: "board_editor"
        )
        let request = PlenactBoardWriteRequest( /* Outgoing API request */
            expectedRevision: 0,
            document: PlenactAPIClient.sampleDataDocument(for: jim),
            seedKind: "sample_data_v1"
        )
        let encodedRequest = try JSONEncoder().encode(request) /* Serialized request body */

        XCTAssertLessThanOrEqual(encodedRequest.count, PlenactAPIClient.maximumJSONBodyBytes)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testJSONBodySizeLimitIncludesExactBoundary()
    /// @brief      Verify the inclusive JSON request-size limit
    /// @details    Checks exactly one MiB is accepted and one byte more is rejected
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testJSONBodySizeLimitIncludesExactBoundary() {

        let maximumBody   = Data(repeating: 0, count: PlenactAPIClient.maximumJSONBodyBytes) /* Allowed request-body size */
        let oversizedBody = Data(repeating: 0, count: PlenactAPIClient.maximumJSONBodyBytes + 1) /* Oversized request payload */

        XCTAssertTrue(PlenactAPIClient.isJSONBodyWithinLimit(maximumBody))
        XCTAssertFalse(PlenactAPIClient.isJSONBodyWithinLimit(oversizedBody))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAPIClientRejectsPlainHTTPEndpoint()
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

        let secureURL = URL(string: "https://demo.example.test/api/")! /* Valid HTTPS base URL */

        XCTAssertNoThrow(try PlenactAPIClient(baseURL: secureURL))
    }
}