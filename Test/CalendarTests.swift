// --------------------------------------------------------------------------------------------------
// @file       CalendarTests.swift
// @brief      Calendar regression tests
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
/// Calendar regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusChronologyHonorsTimeOnlyDateOnlyAndDueFallback
    /// @brief      Verify that focus Chronology Honors Time Only Date Only And Due Fallback
    /// @details    Exercises `(1...5).map`, `preferences.todayFocusEntries`, `entries.map`. Checks
    ///             `XCTAssertEqual(entries.map(\.id), [3, 2, 4, 1, 5])`; `XCTAssertEqual(entries[1].scheduleDate(on:
    ///             day, calendar: calendar), time(9, day: 19))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusChronologyHonorsTimeOnlyDateOnlyAndDueFallback() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusChronologyHonorsTimeOnlyDateOnlyAndDueFallback.time
        /// @brief      Prepare time for the enclosing regression test
        /// @details    Supplies the local fixture for focus Chronology Honors Time Only Date Only And Due Fallback.
        ///             Uses `calendar.date`.
        ///
        /// @param[in]  hour  Hour-of-day component used by the fixture
        /// @param[in]  date  Represented date for the operation
        ///
        /// @return     (Date) result described by this operation's contract
        ///
        func time(_ hour: Int, day date: Int) -> Date
        {

            calendar.date(from: DateComponents(year: 2026, month: 10, day: date, hour: hour))!
        }

        var cards = (1 ... 5).map
        {
            KanbanCard(id: $0, word: "Item \($0)", listTitle: "Monday", checklists: [])
        }

        cards[0].startDate = time(17, day: 1);
        cards[0].startDateKind = .time
        cards[1].dueDate = time(9, day: 25);
        cards[1].dueDateKind = .time
        cards[2].startDate = time(22, day: 19);
        cards[2].startDateKind = .date
        cards[3].startDate = time(12, day: 19);
        cards[3].startDateKind = .dateAndTime
        let preferences = LocalProfilePreferences(todayFocusItemCount: 0, todayFocusOrder: .chronological)
        let entries = preferences.todayFocusEntries(in: cards, on: day, calendar: calendar)
        XCTAssertEqual(entries.map(\.id), [3, 2, 4, 1, 5])
        XCTAssertEqual(entries[1].scheduleDate(on: day, calendar: calendar), time(9, day: 19))
        XCTAssertTrue(try XCTUnwrap(entries[1].scheduleLabel).hasPrefix("Due · "))
        XCTAssertNil(entries.last?.scheduleLabel)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningWeekReplacementPreservesUndatedAndArchivedContent
    /// @brief      Verify that planning Week Replacement Preserves Undated And Archived Content
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `week.collection.lists.firstIndex`.
    ///             Checks `XCTAssertEqual(applied.collection.lists.first { $0.id == 50 }, undated)`;
    ///             `XCTAssertEqual(applied.collection.lists[monday].archivedCards,
    ///             week.collection.lists[monday].archivedCards)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningWeekReplacementPreservesUndatedAndArchivedContent() throws
    {

        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: calendar))
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let monday = try XCTUnwrap(week.collection.lists.firstIndex
            {
                $0.id == week.dayListIDs["2026-11-02"]
            })
        week.collection.lists[monday].cards = [
            KanbanCard(id: 100, word: "Replace this", listTitle: "Monday", checklists: [])
        ]
        week.collection.lists[monday].archivedCards = [
            KanbanCard(id: 101, word: "Retain archive", listTitle: "Monday", checklists: [])
        ]
        let undated = KanbanList(
            id: 50, title: "Other plans",
            cards: [KanbanCard(id: 102, word: "Keep undated", listTitle: "Other plans", checklists: [])])
        week.collection.lists.append(undated)
        let applied = try PlanningTemplateApplication.apply(
            PlanningRoutineLibrary.seeded.templates[0], to: week, date: date, calendar: calendar, mode: .replace)
        XCTAssertEqual(applied.collection.lists.first
            {
                $0.id == 50
            }, undated)
        XCTAssertEqual(applied.collection.lists[monday].archivedCards, week.collection.lists[monday].archivedCards)
        XCTAssertFalse(applied.collection.lists.flatMap(\.cards).contains
            {
                $0.word == "Replace this"
            })
        XCTAssertEqual(applied.collection.lists.flatMap(\.cards).filter
            {
                !$0.isSectionDivider
            } .count, 43)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDailyPlanPreservesUnreadableAndUnsupportedStoredData
    /// @brief      Verify that daily Plan Preserves Unreadable And Unsupported Stored Data
    /// @details    Exercises `DailyPlanStore.load`, `DailyPlanStore.save`. Checks `XCTAssertThrowsError(try
    ///             DailyPlanStore.load(from: defaults))`; `XCTAssertThrowsError(try
    ///             DailyPlanStore.save(DailyPlan(date: .now), replacing: nil, to: defaults))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDailyPlanPreservesUnreadableAndUnsupportedStoredData() throws
    {

        let name = "PlenactTests.DailyPlan." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        for bytes in [Data("broken".utf8), Data(#"{"version":99,"plans":{}}"#.utf8)]
        {

            defaults.set(bytes, forKey: DailyPlanStore.key)
            XCTAssertThrowsError(try DailyPlanStore.load(from: defaults))
            XCTAssertThrowsError(try DailyPlanStore.save(DailyPlan(date: .now), replacing: nil, to: defaults))
            XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), bytes)
        }

        defaults.set("unexpected preference type", forKey: DailyPlanStore.key)
        XCTAssertThrowsError(try DailyPlanStore.load(from: defaults))
        XCTAssertEqual(defaults.string(forKey: DailyPlanStore.key), "unexpected preference type")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFullMonthBackupRestoresAllPreferencesAndLocalFilesAndKeepsOriginal
    /// @brief      Verify that full Month Backup Restores All Preferences And Local Files And Keeps Original
    /// @details    Exercises `folder.appendingPathComponent`, `store.documents.appendingPathComponent`,
    ///             `store.support.appendingPathComponent`. Checks `XCTAssertTrue(store.hasUserData)`;
    ///             `XCTAssertNotNil(try PlanningCalendarStore.load(from: defaults))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFullMonthBackupRestoresAllPreferencesAndLocalFilesAndKeepsOriginal() throws
    {

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "PlenactTests.Month." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name);
            try? FileManager.default.removeItem(at: folder)
        }

        let store = FullMonthExampleStore(
            root: folder.appendingPathComponent("Backup"), documents: folder.appendingPathComponent("Documents"),
            support: folder.appendingPathComponent("Support"), domainName: name)
        try FileManager.default.createDirectory(at: store.documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.support, withIntermediateDirectories: true)
        let attachment = store.documents.appendingPathComponent("photo.bin")
        let background = store.support.appendingPathComponent("background.bin")
        try Data([1, 2, 3]).write(to: attachment)
        try Data([4, 5, 6]).write(to: background)
        let original: [String: Any] = [
                        "Plenact.PersonalCollections.v1": Data([9]), "Plenact.CustomSetting": "original",
                        "AnUnknownFutureKey": ["one", "two"]
        ]
        defaults.setPersistentDomain(original, forName: name)
        let example = FullMonthExample.make()
        try store.loadExample(example)
        XCTAssertTrue(store.hasUserData)
        XCTAssertNotNil(try PlanningCalendarStore.load(from: defaults))
        defaults.set("example edit", forKey: "Plenact.CustomSetting")
        try FileManager.default.removeItem(at: attachment)
        try Data([7]).write(to: background)
        try store.loadExample(example)
        try store.restoreUserData()
        XCTAssertFalse(store.hasUserData)
        XCTAssertTrue(NSDictionary(dictionary: defaults.persistentDomain(forName: name) ?? [:]).isEqual(to: original))
        XCTAssertEqual(try Data(contentsOf: attachment), Data([1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: background), Data([4, 5, 6]))
        // A later session creates a new backup of the newly current user workspace.
        defaults.set("new user edit", forKey: "Plenact.CustomSetting")
        try store.loadExample(example)
        try store.restoreUserData()
        XCTAssertEqual(defaults.string(forKey: "Plenact.CustomSetting"), "new user edit")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCollectionBackgroundsPersistAndExcludeDatedViews
    /// @brief      Verify that collection Backgrounds Persist And Exclude Dated Views
    /// @details    Exercises `CollectionBackground.isAllowed`. Checks
    ///             `XCTAssertTrue(CollectionBackground.isAllowed(collectionID: personalID, datedWeekIDs: [weekID],
    ///             isDatedView: false))`; `XCTAssertFalse(CollectionBackground.isAllowed(collectionID: nil,
    ///             datedWeekIDs: [weekID], isDatedView: false))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCollectionBackgroundsPersistAndExcludeDatedViews() throws
    {

        let personalID = UUID(), weekID = UUID()
        XCTAssertTrue(
            CollectionBackground.isAllowed(collectionID: personalID, datedWeekIDs: [weekID], isDatedView: false))
        XCTAssertFalse(CollectionBackground.isAllowed(collectionID: nil, datedWeekIDs: [weekID], isDatedView: false))
        XCTAssertFalse(CollectionBackground.isAllowed(collectionID: weekID, datedWeekIDs: [weekID], isDatedView: false))
        XCTAssertFalse(CollectionBackground.isAllowed(collectionID: personalID, datedWeekIDs: [], isDatedView: true))
        let legacy = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.collectionBackground)
        for preset in CollectionBackgroundPreset.allCases
        {

            var collection = PersonalCollection(title: "Personal space", kind: .board)
            collection.boardAppearance = BoardAppearance()
            collection.boardAppearance?.collectionBackground = CollectionBackground(
                preset: preset,
                photoFileName: preset == .photo ? "example.jpg" : nil)
            let originalLists = collection.lists
            let decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection))
            XCTAssertEqual(decoded, collection)
            XCTAssertEqual(decoded.lists, originalLists)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFreshInstallationSeedsTutorialListsAndOrderedShortcutsOnlyOnce
    /// @brief      Verify that fresh Installation Seeds Tutorial Lists And Ordered Shortcuts Only Once
    /// @details    Exercises `TodayListPins.loadInitialCollections`, `seeded.map`, `seeded.allSatisfy`. Checks
    ///             `XCTAssertEqual(seeded.map(\.title), ["On the Table", "In the Queue", "Scheduled"])`;
    ///             `XCTAssertTrue(seeded.allSatisfy { $0.kind == .list && $0.lists.count == 1 &&
    ///             $0.lists[0].allCards.count == 1 })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFreshInstallationSeedsTutorialListsAndOrderedShortcutsOnlyOnce() throws
    {

        let suite = "Plenact.FreshInstallTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let seeded = TodayListPins.loadInitialCollections(from: defaults)
        XCTAssertEqual(seeded.map(\.title), ["On the Table", "In the Queue", "Scheduled"])
        XCTAssertTrue(seeded.allSatisfy
            {
                $0.kind == .list && $0.lists.count == 1 && $0.lists[0].allCards.count == 1
            })
        let pins = TodayListPins.decode(try XCTUnwrap(defaults.data(forKey: TodayListPins.key)))
        XCTAssertEqual(pins, seeded.map
            {
                WorkspaceListReference(ownerID: $0.id, listID: $0.lists[0].id)
            })
        XCTAssertEqual(TodayListPins.loadInitialCollections(from: defaults), seeded)

        var cleared = seeded
        cleared[0].lists[0].cards = []
        cleared[1].lists[0].cards[0].isTitleChecked = true
        PersonalCollectionStore.save(cleared, to: defaults)
        XCTAssertEqual(TodayListPins.loadInitialCollections(from: defaults), cleared)

        PersonalCollectionStore.save([], to: defaults)
        defaults.set(TodayListPins.encode([]), forKey: TodayListPins.key)
        XCTAssertTrue(TodayListPins.loadInitialCollections(from: defaults).isEmpty)
        XCTAssertTrue(TodayListPins.decode(try XCTUnwrap(defaults.data(forKey: TodayListPins.key))).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSameDayDateOnlySchedulesDoNotRepeatTheListDate
    /// @brief      Verify that same Day Date Only Schedules Do Not Repeat The List Date
    /// @details    Exercises `card.scheduleBadges`. Checks `XCTAssertTrue(card.scheduleBadges(on: day, calendar:
    ///             calendar).isEmpty)`; `XCTAssertEqual(card, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testSameDayDateOnlySchedulesDoNotRepeatTheListDate() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        var card = KanbanCard(
            id: 77, word: "Same-day task", listTitle: "My renamed day", startDate: day, dueDate: day,
            showsDueDateInList: true, startDateKind: .date, dueDateKind: .date)
        let original = card
        XCTAssertTrue(card.scheduleBadges(on: day, calendar: calendar).isEmpty)
        XCTAssertEqual(card, original, "Preview formatting must retain the editable dates")
        XCTAssertEqual(card.scheduleBadges(on: tomorrow, calendar: calendar).count, 2)
        XCTAssertFalse(
            card.scheduleBadges(on: nil, calendar: calendar).isEmpty, "Undated Lists still need date context")
        card.dueDate = nil
        XCTAssertTrue(card.scheduleBadges(on: day, calendar: calendar).isEmpty)
        card.startDate = nil;
        card.dueDate = day
        XCTAssertTrue(card.scheduleBadges(on: day, calendar: calendar).isEmpty)
        card.startDate = day;
        card.dueDate = tomorrow
        XCTAssertEqual(card.scheduleBadges(on: day, calendar: calendar).count, 2, "Cross-day ranges retain their dates")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekCalendarGridAlignsRowsAcrossMonthsAndWeekStarts
    /// @brief      Verify that week Calendar Grid Aligns Rows Across Months And Week Starts
    /// @details    Exercises `PlanningDate.date`, `PlanningWeekSelector.monthDays`, `days[(row * 7)..<(row * 7 +
    ///             7)].map`. Checks `XCTAssertEqual(days.count, 42)`; `XCTAssertEqual(calendar.component(.weekday,
    ///             from: days[0]), firstWeekday)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWeekCalendarGridAlignsRowsAcrossMonthsAndWeekStarts() throws
    {

        for firstWeekday in [1, 2]
        {

            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday
            for key in ["2026-10-14", "2026-12-31", "2027-01-01", "2028-02-29"]
            {

                let date = try XCTUnwrap(PlanningDate.date(key, calendar: calendar))
                let days = PlanningWeekSelector.monthDays(date, calendar: calendar)
                XCTAssertEqual(days.count, 42)
                XCTAssertEqual(calendar.component(.weekday, from: days[0]), firstWeekday)
                for row in 0 ..< 6
                {

                    let keys = Set(days[(row * 7) ..< (row * 7 + 7)].map
                        {
                            PlanningDate.weekKey($0, calendar: calendar)
                        })
                    XCTAssertEqual(keys.count, 1)
                }

                let month = try XCTUnwrap(calendar.dateInterval(of: .month, for: date))
                let count = try XCTUnwrap(calendar.range(of: .day, in: .month, for: date)).count
                XCTAssertEqual(days.filter
                    {
                        month.contains($0) && $0 < month.end
                    } .count, count)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCalendarContentMatchesPlannedAndScheduledItemsAcrossWeekBoundaries
    /// @brief      Verify that calendar Content Matches Planned And Scheduled Items Across Week Boundaries
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `week.list`. Checks
    ///             `XCTAssertEqual(Set(today.map { $0.card.word }), ["Planned and scheduled", "Starts today"])`;
    ///             `XCTAssertEqual(today.count, 2)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCalendarContentMatchesPlannedAndScheduledItemsAcrossWeekBoundaries() throws
    {

        for firstWeekday in [1, 2]
        {

            var calendar = Calendar.current;
            calendar.firstWeekday = firstWeekday
            let date = try XCTUnwrap(PlanningDate.date("2026-10-17", calendar: calendar))
            let nextDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
            var week = DatedPlanningWeek.make(for: date, calendar: calendar)
            let listID = try XCTUnwrap(week.list(on: date)?.id)
            let index = try XCTUnwrap(week.collection.lists.firstIndex
                {
                    $0.id == listID
                })
            week.collection.lists[index].cards = [
                KanbanCard(
                    id: 1, word: "Planned and scheduled", listTitle: "Saturday", startDate: date, dueDate: date,
                    checklists: [], startDateKind: .date, dueDateKind: .date)
            ]
            var library = PersonalCollection(title: "Scheduled", kind: .list)
            library.lists[0].cards = [
                KanbanCard(
                    id: 1, word: "Note due tomorrow", listTitle: "Scheduled", dueDate: nextDate, checklists: [],
                    presentation: .note, dueDateKind: .date),
                KanbanCard(
                    id: 2, word: "Time only", listTitle: "Scheduled", startDate: date, dueDate: nextDate,
                    checklists: [], startDateKind: .time, dueDateKind: .time),
                KanbanCard(
                    id: 3, word: "Starts today", listTitle: "Scheduled", startDate: date, checklists: [],
                    startDateKind: .dateAndTime)
            ]
            library.lists[0].archivedCards = [
                KanbanCard(
                    id: 4, word: "Archived", listTitle: "Scheduled", dueDate: date, checklists: [], dueDateKind: .date)
            ]
            let document = PlanningCalendarDocument(
                currentWeekKey: week.startKey, firstWeekday: firstWeekday, weeks: [week])
            let access = PlanningCalendarAccess(
                document: document, library: [library], saveWeek:
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
            let sources = access.searchableItems
            let today = PlanningCalendarContent.items(on: date, document: document, sources: sources)
            XCTAssertEqual(Set(today.map
                    {
                        $0.card.word
                    }), ["Planned and scheduled", "Starts today"])
            XCTAssertEqual(today.count, 2)  // A Card with both dates and day membership still counts once.
            XCTAssertEqual(
                PlanningCalendarContent.items(on: nextDate, document: document, sources: sources).map
                {
                    $0.card.word
                },
                ["Note due tomorrow"])
            let empty = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: date))
            XCTAssertTrue(PlanningCalendarContent.items(on: empty, document: document, sources: sources).isEmpty)
            XCTAssertEqual(access.document, document)
            XCTAssertEqual(access.library, [library])
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekCalendarPickerRendersSelectedWeekAndDay
    /// @brief      Verify that week Calendar Picker Renders Selected Week And Day
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `week.collection.lists.firstIndex`. Uses
    ///             the fixture and assertions below to verify week Calendar Picker Renders Selected Week And Day.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testWeekCalendarPickerRendersSelectedWeekAndDay() async throws
    {

        let date = try XCTUnwrap(PlanningDate.date("2026-10-14"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let index = try XCTUnwrap(week.collection.lists.firstIndex
            {
                $0.id == week.list(on: date)?.id
            })
        week.collection.lists[index].cards = [
            KanbanCard(id: 1, word: "Planned work", listTitle: "Wednesday", checklists: [])
        ]
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
        let nextIndex = try XCTUnwrap(week.collection.lists.firstIndex
            {
                $0.id == week.list(on: tomorrow)?.id
            })
        week.collection.lists[nextIndex].cards = [
            KanbanCard(id: 2, word: "Tomorrow's work", listTitle: "Thursday", checklists: [])
        ]
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 1, weeks: [week])
        let access = PlanningCalendarAccess(
            document: document, library: [], saveWeek:
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
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(
            rootView: PlanningWeekSelector(
                initialDate: date, document: document, selectedWeekKey: week.startKey, sources: access.searchableItems
            )
            {
                _, _ in
            })
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 480)
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-week-calendar-preview.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("Week calendar preview: " + path.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLaunchProgressRevealsOnlyStartedStagesAndKeepsCompletedStagesSteady
    /// @brief      Verify that launch Progress Reveals Only Started Stages And Keeps Completed Stages Steady
    /// @details    Exercises `progress.status`, `PlenactLaunchStage.allCases.allSatisfy`, `finished.status`. Checks
    ///             `XCTAssertEqual(progress.status(for: step), step.rawValue < stage.rawValue ? .complete : (step ==
    ///             stage ? .running : .waiting))`; `XCTAssertTrue(PlenactLaunchStage.allCases.allSatisfy {
    ///             finished.status(for: $0) == .complete })`.
    ///
    /// @return     (Void) no return value
    ///
    func testLaunchProgressRevealsOnlyStartedStagesAndKeepsCompletedStagesSteady()
    {

        for stage in PlenactLaunchStage.allCases
        {

            let progress = PlenactLaunchProgress(stage: stage)
            for step in PlenactLaunchStage.allCases
            {

                XCTAssertEqual(
                    progress.status(for: step),
                    step.rawValue < stage.rawValue ? .complete : (step == stage ? .running : .waiting))
            }

        }

        let finished = PlenactLaunchProgress(stage: .welcome, finished: true)
        XCTAssertTrue(PlenactLaunchStage.allCases.allSatisfy
            {
                finished.status(for: $0) == .complete
            })
        XCTAssertEqual(
            PlenactLaunchStage.allCases.map(\.symbol), ["folder", "calendar", "slider.horizontal.3", "sun.max"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryPlateRanksUrgencyAndExcludesCompletedArchivedAndUndatedItems
    /// @brief      Verify that library Plate Ranks Urgency And Excludes Completed Archived And Undated Items
    /// @details    Exercises `PlanningDate.date`, `LibraryPlateSelection.items`, `selected.map`. Checks
    ///             `XCTAssertEqual(selected.map(\.card.id), [4, 3, 2, 1])`; `XCTAssertEqual(selected.map(\.rank), [0,
    ///             1, 2, 3])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLibraryPlateRanksUrgencyAndExcludesCompletedArchivedAndUndatedItems() throws
    {

        let calendar = Calendar.current
        let now = try XCTUnwrap(PlanningDate.date("2026-10-11"))


        ///
        /// @fcn        PlenactBoardDocumentTests.testLibraryPlateRanksUrgencyAndExcludesCompletedArchivedAndUndatedItems.due
        /// @brief      Prepare due for the enclosing regression test
        /// @details    Supplies the local fixture for library Plate Ranks Urgency And Excludes Completed Archived And
        ///             Undated Items. Uses `calendar.date`.
        ///
        /// @param[in]  days  Calendar-day offset used by the regression fixture
        ///
        /// @return     (Date) result described by this operation's contract
        ///
        func due(_ days: Int) -> Date
        {
            calendar.date(byAdding: .day, value: days, to: now)!
        }

        var collection = PersonalCollection(title: "Projects", kind: .list)
        var important = KanbanCard(id: 1, word: "Important", listTitle: "Projects")
        important.isTitleChecked = false


        ///
        /// @fcn        PlenactBoardDocumentTests.testLibraryPlateRanksUrgencyAndExcludesCompletedArchivedAndUndatedItems.task
        /// @brief      Prepare task for the enclosing regression test
        /// @details    Supplies the local fixture for library Plate Ranks Urgency And Excludes Completed Archived And
        ///             Undated Items.
        ///
        /// @param[in]  id    Starting numeric card ID or owner-local content identity
        /// @param[in]  days  Calendar-day offset used by the regression fixture
        ///
        /// @return     (KanbanCard) result described by this operation's contract
        ///
        func task(_ id: Int, _ days: Int) -> KanbanCard
        {

            var card = KanbanCard(id: id, word: "Task \(id)", listTitle: "Projects", dueDate: due(days))
            card.isTitleChecked = false
            return card
        }

        var completed = task(5, -4);
        completed.isTitleChecked = true
        var timeOnly = task(6, -5);
        timeOnly.dueDateKind = .time
        let normal = KanbanCard(id: 7, word: "No deadline", listTitle: "Projects")
        collection.lists[0].cards = [
            important, task(2, 2), task(3, 0), task(4, -1), completed, timeOnly, normal, task(8, 30)
        ]
        let marked = [LibraryRecentItem(collectionID: collection.id, cardID: 1)]
        let selected = LibraryPlateSelection.items(in: [collection], important: marked, now: now)
        XCTAssertEqual(selected.map(\.card.id), [4, 3, 2, 1])
        XCTAssertEqual(selected.map(\.rank), [0, 1, 2, 3])
        collection.lists[0].cards.append(task(9, -2))
        XCTAssertEqual(
            LibraryPlateSelection.items(in: [collection], important: marked, now: now).map(\.card.id), [9, 4, 3, 2])
        collection.lists[0].isArchived = true
        XCTAssertTrue(LibraryPlateSelection.items(in: [collection], important: marked, now: now).isEmpty)
        collection.lists[0].isArchived = false
        collection.isArchived = true
        XCTAssertTrue(LibraryPlateSelection.items(in: [collection], important: marked, now: now).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListCreationDraftSurvivesRecreationAndStaysInItsCollection
    /// @brief      Verify that list Creation Draft Survives Recreation And Stays In Its Collection
    /// @details    Exercises `ListCreationDraft.key`, `draft.save`, `ListCreationDraft.load`. Checks
    ///             `XCTAssertEqual(ListCreationDraft.load(key: key, defaults: defaults), draft)`;
    ///             `XCTAssertEqual(ListCreationDraft.load(key: other, defaults: defaults), ListCreationDraft())`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListCreationDraftSurvivesRecreationAndStaysInItsCollection() throws
    {

        let suite = "ListDraftTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let key = ListCreationDraft.key(collectionID: UUID(), listID: 1)
        let other = ListCreationDraft.key(collectionID: UUID(), listID: 1)
        let draft = ListCreationDraft(title: "A\nB", subtitle: "Subtitle", description: "Body")
        draft.save(key: key, defaults: defaults)
        XCTAssertEqual(ListCreationDraft.load(key: key, defaults: defaults), draft)
        XCTAssertEqual(ListCreationDraft.load(key: other, defaults: defaults), ListCreationDraft())
        ListCreationDraft.clear(key: key, defaults: defaults)
        XCTAssertEqual(ListCreationDraft.load(key: key, defaults: defaults), ListCreationDraft())
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardDateKindsPersistAndCopyWithoutInventingDates
    /// @brief      Verify that card Date Kinds Persist And Copy Without Inventing Dates
    /// @details    Exercises `decoded.startDateLabel.contains`, `decoded.listDueDateLabel?.contains`,
    ///             `decoded.dueDateLabel.contains`. Checks `XCTAssertEqual(decoded.startDateKind, kind)`;
    ///             `XCTAssertEqual(decoded.dueDateKind, kind)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCardDateKindsPersistAndCopyWithoutInventingDates() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 20, minute: 45)))
        for kind in CardDateKind.allCases
        {

            var card = KanbanCard(
                id: 1, word: "Scheduled", listTitle: "Monday", startDate: date, dueDate: date,
                showsDueDateInList: true, startDateKind: kind, dueDateKind: kind)
            let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
            XCTAssertEqual(decoded.startDateKind, kind)
            XCTAssertEqual(decoded.dueDateKind, kind)
            XCTAssertEqual(decoded.startDate, date)
            XCTAssertEqual(decoded.dueDate, date)
            if kind.includesTime
            {

                XCTAssertTrue(decoded.startDateLabel.contains("8:45 PM"))
                XCTAssertTrue(decoded.listDueDateLabel?.contains("8:45 PM") ?? false)
            }
            else
            {

                XCTAssertFalse(decoded.dueDateLabel.contains("PM"))
            }

            let relocated = decoded.replacingLocation(id: 20, listTitle: "Thursday")
            XCTAssertEqual(relocated.startDateKind, kind)
            XCTAssertEqual(relocated.dueDateKind, kind)
            let list = KanbanList(id: 0, title: "Monday", cards: [decoded])
            let copied = ListCopying.copy(list, into: [list], crossBoard: true).cards[0]
            XCTAssertEqual(copied.startDateKind, kind)
            XCTAssertEqual(copied.dueDateKind, kind)
            card.dueDate = nil
            XCTAssertNil(card.listDueDateLabel)
            card.startDate = nil
            XCTAssertEqual(card.startDateLabel, "")
        }

        XCTAssertEqual(calendar.component(.hour, from: CardDateKind.date.normalized(date, calendar: calendar)), 0)
        XCTAssertEqual(calendar.component(.minute, from: CardDateKind.date.normalized(date, calendar: calendar)), 0)
        XCTAssertEqual(CardDateKind.dateAndTime.normalized(date, calendar: calendar), date)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(KanbanCard(id: 0, word: "Legacy", listTitle: "Monday", dueDate: date)))
            as? [String: Any])
        legacy.removeValue(forKey: "startDateKind");
        legacy.removeValue(forKey: "dueDateKind")
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.startDateKind, .date)
        XCTAssertEqual(decoded.dueDateKind, .date)
        XCTAssertFalse(decoded.dueDateLabel.contains("PM"))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewCardDueDateDefaultPreferencesPersistAndLegacyDefaultsToTrue
    /// @brief      Verify that new Card Due Date Default Preferences Persist And Legacy Defaults To True
    /// @details    Exercises `KanbanCard.defaultDueDateVisibility`, `LocalProfileStore.save`,
    ///             `LocalProfileStore.load`. Checks `XCTAssertTrue(KanbanCard.defaultDueDateVisibility(from:
    ///             defaults))`; `XCTAssertTrue(profile.preferences.showsDueDatesOnNewCards)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testNewCardDueDateDefaultPreferencesPersistAndLegacyDefaultsToTrue() throws
    {

        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        XCTAssertTrue(KanbanCard.defaultDueDateVisibility(from: defaults))
        var profile = LocalProfile(displayName: "Synthetic")
        XCTAssertTrue(profile.preferences.showsDueDatesOnNewCards)
        profile.preferences.showsDueDatesOnNewCards = false
        LocalProfileStore.save(profile, to: defaults)
        XCTAssertFalse(KanbanCard.defaultDueDateVisibility(from: defaults))
        XCTAssertFalse(try XCTUnwrap(LocalProfileStore.load(from: defaults)).preferences.showsDueDatesOnNewCards)
        let explicit = KanbanCard(id: 1, word: "Override", listTitle: "Monday", showsDueDateInList: true)
        XCTAssertTrue(explicit.showsDueDateInList)
        profile.preferences.showsDueDatesOnNewCards = true
        LocalProfileStore.save(profile, to: defaults)
        XCTAssertTrue(KanbanCard.defaultDueDateVisibility(from: defaults))
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile.preferences)) as? [String: Any])
        legacy.removeValue(forKey: "showsDueDatesOnNewCards")
        let decoded = try JSONDecoder().decode(
            LocalProfilePreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decoded.showsDueDatesOnNewCards)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testMondayWeekStartAcrossYearBoundaryAndStoredReload
    /// @brief      Verify that monday Week Start Across Year Boundary And Stored Reload
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `document.changeFirstWeekday`. Checks
    ///             `XCTAssertEqual(document.currentWeekKey, "2026-12-28")`; `XCTAssertEqual(document.week(for:
    ///             date)?.collection.lists.first?.title, "Monday")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testMondayWeekStartAcrossYearBoundaryAndStoredReload() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        let date = try XCTUnwrap(PlanningDate.date("2027-01-03", calendar: calendar))
        let week = DatedPlanningWeek.make(for: date, calendar: calendar)
        var document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 1, weeks: [week])
        try document.changeFirstWeekday(to: 2, now: date)
        XCTAssertEqual(document.currentWeekKey, "2026-12-28")
        XCTAssertEqual(document.week(for: date)?.collection.lists.first?.title, "Monday")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        defer
        {
            defaults.removeObject(forKey: PlanningCalendarStore.key)
        }

        try PlanningCalendarStore.save(document, to: defaults)
        XCTAssertEqual(try PlanningCalendarStore.load(from: defaults), document)
        let next = document.rollForward(
            to: try XCTUnwrap(PlanningDate.date("2027-01-04", calendar: calendar)),
            currentLists: document.week(for: date)!.collection.lists, saved: [])
        XCTAssertEqual(next.startKey, "2027-01-04")
        XCTAssertEqual(next.collection.lists.first?.title, "Monday")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningHostedCalendarLayoutDoesNotPersistBrowsing
    /// @brief      Verify that planning Hosted Calendar Layout Does Not Persist Browsing
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(saveCount, 0)`; `XCTAssertEqual(access.document,
    ///             original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPlanningHostedCalendarLayoutDoesNotPersistBrowsing() async throws
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
            previous?.makeKey()
        }

        let week = DatedPlanningWeek.make(for: .now, lists: SampleData.lists)
        let original = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        var saveCount = 0
        let access = PlanningCalendarAccess(
            document: original, library: [],
            saveWeek:
            {
                _ in
                saveCount += 1;
                return true
            },
            openCurrentWeek:
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
                saveCount += 1;
                return true
            })
        for size in [DynamicTypeSize.large, .accessibility3]
        {

            let controller = UIHostingController(
                rootView: PlanningCalendarView().environment(\.planningCalendarAccess, access)
                .environment(\.dynamicTypeSize, size))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image
            {
                _ in
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningDateKeysAcrossDSTAndYearBoundary
    /// @brief      Verify that planning Date Keys Across DST And Year Boundary
    /// @details    Exercises `PlanningDate.date`, `PlanningDate.days`, `PlanningDate.weekKey`. Checks
    ///             `XCTAssertEqual(PlanningDate.weekKey(yearEnd, calendar: calendar), "2026-12-27")`;
    ///             `XCTAssertEqual(PlanningDate.days(in: "2026-12-27", calendar: calendar).last.map {
    ///             PlanningDate.key($0, calendar: calendar) }, "2027-01-02")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningDateKeysAcrossDSTAndYearBoundary() throws
    {

        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-01", calendar: calendar))
        let days = PlanningDate.days(in: PlanningDate.weekKey(date, calendar: calendar), calendar: calendar)
        XCTAssertEqual(
            days.map
            {
                PlanningDate.key($0, calendar: calendar)
            },
            ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"])
        let yearEnd = try XCTUnwrap(PlanningDate.date("2026-12-31", calendar: calendar))
        XCTAssertEqual(PlanningDate.weekKey(yearEnd, calendar: calendar), "2026-12-27")
        XCTAssertEqual(
            PlanningDate.days(in: "2026-12-27", calendar: calendar).last.map
            {

                PlanningDate.key($0, calendar: calendar)
            }, "2027-01-02")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningCardsMoveBetweenDatedWeekLibraryAndCurrentWeek
    /// @brief      Verify that planning Cards Move Between Dated Week Library And Current Week
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `future.list`. Checks
    ///             `XCTAssertEqual(moved, original.replacingLocation(id: original.id, listTitle:
    ///             destination.title))`; `XCTAssertTrue(current[0].cards.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningCardsMoveBetweenDatedWeekLibraryAndCurrentWeek() throws
    {

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
        try CrossBoardCardMovement.move(
            original, from: nil,
            to: CardMoveDestination(
                collectionID: future.id, listID: destination.id, title: destination.title, group: "Calendar"),
            week: &current, collections: &owners, saved: &saved)
        future.collection = owners[0]
        let moved = try XCTUnwrap(future.list(on: date)?.cards.first)
        XCTAssertEqual(moved, original.replacingLocation(id: original.id, listTitle: destination.title))
        XCTAssertTrue(current[0].cards.isEmpty)
        XCTAssertTrue(future.collection.savedCardIDs.contains(moved.id))
        try CrossBoardCardMovement.move(
            moved, from: future.id,
            to: CardMoveDestination(
                collectionID: library.id, listID: library.lists[0].id, title: library.title, group: "Library"),
            week: &current, collections: &owners, saved: &saved)
        let inLibrary = try XCTUnwrap(owners[1].lists[0].cards.first)
        try CrossBoardCardMovement.move(
            inLibrary, from: library.id,
            to: CardMoveDestination(collectionID: nil, listID: 1, title: "Monday", group: "Week"),
            week: &current, collections: &owners, saved: &saved)
        XCTAssertEqual(current[0].cards.first, original.replacingLocation(id: original.id, listTitle: "Monday"))
        XCTAssertEqual(saved, [original.id])
        XCTAssertTrue(owners[1].lists[0].cards.isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusTrailingTimePrefersTimedStartAndSkipsDateOnlyValues
    /// @brief      Verify that focus Trailing Time Prefers Timed Start And Skips Date Only Values
    /// @details    Exercises `start.addingTimeInterval`. Checks `XCTAssertNil(entry().previewTime)`;
    ///             `XCTAssertEqual(entry().previewTime?.date, due)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusTrailingTimePrefersTimedStartAndSkipsDateOnlyValues() throws
    {

        let start = Date(timeIntervalSince1970: 1700000000)
        let due = start.addingTimeInterval(3600)
        var card = KanbanCard(
            id: 1, word: "Work", listTitle: "Today", startDate: start, dueDate: due,
            startDateKind: .date, dueDateKind: .date)


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusTrailingTimePrefersTimedStartAndSkipsDateOnlyValues.entry
        /// @brief      Prepare entry for the enclosing regression test
        /// @details    Supplies the local fixture for focus Trailing Time Prefers Timed Start And Skips Date Only
        ///             Values.
        ///
        /// @return     (TodayFocusEntry) result described by this operation's contract
        ///
        func entry() -> TodayFocusEntry
        {
            TodayFocusEntry(card: card, sectionID: nil, heading: nil)
        }

        XCTAssertNil(entry().previewTime)
        card.dueDateKind = .time
        XCTAssertEqual(entry().previewTime?.date, due)
        XCTAssertEqual(entry().previewTime?.isStart, false)
        card.startDateKind = .dateAndTime
        XCTAssertEqual(entry().previewTime?.date, start)
        XCTAssertEqual(entry().previewTime?.isStart, true)
        XCTAssertFalse(try XCTUnwrap(entry().previewTimeLabel).isEmpty)
        card.startDate = nil
        XCTAssertEqual(entry().previewTime?.date, due)
        card.dueDate = nil
        XCTAssertNil(entry().previewTimeLabel)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCanonicalListEditorSaveRetainsLatestRecordsAndWeekdayRecreation
    /// @brief      Verify that canonical List Editor Save Retains Latest Records And Weekday Recreation
    /// @details    Exercises `lists[0].makeItem`, `lists[0].cards.append`, `TodayListSelection.ensureCurrentDayList`.
    ///             Checks `XCTAssertTrue(editBoardList(4, title: "My plans", subtitle: defaultSubtitle, in:
    ///             &lists))`; `XCTAssertNil(lists[0].subtitleOverride, "Unchanged generated text must keep the legacy
    ///             optional-field shape")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCanonicalListEditorSaveRetainsLatestRecordsAndWeekdayRecreation() throws
    {


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


    ///
    /// @fcn        PlenactBoardDocumentTests.testCaptureStartStopDatesAreOptionalValidatedAndPersistAsCalendarDates
    /// @brief      Verify that capture Start Stop Dates Are Optional Validated And Persist As Calendar Dates
    /// @details    Exercises `schedule.isValid`, `schedule.apply`, `pair.0.map`. Checks
    ///             `XCTAssertTrue(schedule.isValid(calendar: calendar))`; `XCTAssertEqual(saved.startDate, pair.0.map
    ///             { times ? $0 : calendar.startOfDay(for: $0) })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCaptureStartStopDatesAreOptionalValidatedAndPersistAsCalendarDates() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10)))
        let stop = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: start))
        for times in [false, true]
        {

            for pair: (Date?, Date?) in [(nil, nil), (start, nil), (nil, stop), (start, stop)]
            {

                let schedule = QuickCaptureSchedule(start: pair.0, stop: pair.1, includesTime: times)
                XCTAssertTrue(schedule.isValid(calendar: calendar))
                var card = KanbanCard(id: 1, word: "Scheduled capture", listTitle: "Today")
                schedule.apply(to: &card, calendar: calendar)
                let saved = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
                XCTAssertEqual(saved.startDate, pair.0.map
                    {
                        times ? $0 : calendar.startOfDay(for: $0)
                    })
                XCTAssertEqual(saved.dueDate, pair.1.map
                    {
                        times ? $0 : calendar.startOfDay(for: $0)
                    })
                XCTAssertEqual(saved.startDateKind, times ? .dateAndTime : .date)
                XCTAssertEqual(saved.dueDateKind, times ? .dateAndTime : .date)
            }

        }

        XCTAssertFalse(QuickCaptureSchedule(start: stop, stop: start).isValid(calendar: calendar))
        let earlierToday = start.addingTimeInterval(-60)
        XCTAssertTrue(QuickCaptureSchedule(start: start, stop: earlierToday).isValid(calendar: calendar))
        XCTAssertFalse(
            QuickCaptureSchedule(start: start, stop: earlierToday, includesTime: true).isValid(calendar: calendar))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedStandardBoardCentersRequestedListWithEqualNeighborPreviews
    /// @brief      Verify that hosted Standard Board Centers Requested List With Equal Neighbor Previews
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(frames.count, 3)`; `XCTAssertEqual(center.width,
    ///             329)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testHostedStandardBoardCentersRequestedListWithEqualNeighborPreviews() async throws
    {


        let suite = "Plenact.CenteredBoard.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(BoardPresentation.standard.rawValue, forKey: BoardPresentation.storageKey)
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
            defaults.removePersistentDomain(forName: suite)
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedStandardBoardCentersRequestedListWithEqualNeighborPreviews.collections
        /// @brief      Find collections in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UICollectionView. Returns all collected matches
        ///             in hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UICollectionView]) resulting values in the ordering described above
        ///
        func collections(in view: UIView) -> [UICollectionView]
        {

            if let collection = view as? UICollectionView
            {
                return [collection]
            }

            return view.subviews.flatMap
            {
                collections(in: $0)
            }

        }

        let lists = (1 ... 3).map
        {
            KanbanList(id: $0, title: "Synthetic \($0)", cards: [])
        }

        var targetListID: Int? = 2
        let controller = UIHostingController(
            rootView: ContentView(
                lists: .constant(lists),
                boardTargetListID: Binding(get:
                    {
                        targetListID
                    }, set:
                    {
                        targetListID = $0
                    }),
                onListsChanged:
                {
                    _ in
                    XCTFail("Layout must not change records")
                }
            ).defaultAppStorage(defaults))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        // The native card collection is inset four points inside each List panel.
        let frames = collections(in: controller.view).map
        {

            $0.convert($0.bounds, to: window).insetBy(dx: -4, dy: 0)
        } .sorted
        {
            $0.minX < $1.minX
        }

        XCTAssertEqual(frames.count, 3)
        let center = try XCTUnwrap(frames.first
            {
                abs($0.midX - 196.5) < 2
            })
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
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardArchiveSavesBeforeReturningUpdatedState()
    /// @brief      Confirm successful archive commits return the saved collection state
    /// @details    Keeps the input and unrelated collection unchanged while checking persisted
    ///             output
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap or checked-save failures
    ///
    func testPersonalBoardArchiveSavesBeforeReturningUpdatedState() throws
    {


        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let board = PersonalCollection(
            title: "Project", kind: .board) /* Board state under verification              */
        let other = PersonalCollection(
            title: "Shopping", kind: .list)  /* Unrelated model fixture                     */
        let original = [board, other]        /* Pre-operation value for preservation checks */
        let updated = try PersonalCollectionStore.archiveBoard(
            id: board.id, in: original, to: defaults) /* Updated state after mutation                */

        XCTAssertTrue(original[0].isActive)
        XCTAssertFalse(updated[0].isActive)
        XCTAssertEqual(updated[1], other)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), updated)
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
    func testTodayFocusFollowsEveryLocalWeekdayWithoutChangingRecords() throws
    {


        var calendar = Calendar(identifier: .gregorian) /* Fixed calendar for date assertions */

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let lists = Array(SampleData.lists.reversed())  /* Board lists under verification              */
        let original = lists                            /* Pre-operation value for preservation checks */
        let names = [
                        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
        ] /* Expected weekday title sequence             */

        for (offset, name) in names.enumerated()
        {


            let date = try XCTUnwrap(
                calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + offset))) /* Date value for boundary checks */

            XCTAssertEqual(TodayListSelection.currentDayList(in: lists, date: date, calendar: calendar)?.title, name)
        }


        let midnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))) /* Calendar-day boundary timestamp */

        XCTAssertEqual(
            TodayListSelection.currentDayList(in: lists, date: midnight.addingTimeInterval(-1), calendar: calendar)?
            .title, "Monday")
        XCTAssertEqual(
            TodayListSelection.currentDayList(in: lists, date: midnight, calendar: calendar)?.title, "Tuesday")

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -3600))

        XCTAssertEqual(
            TodayListSelection.currentDayList(in: lists, date: midnight, calendar: calendar)?.title, "Monday")
        XCTAssertEqual(lists, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testQuickCaptureCreatesMissingCurrentWeekdayList()
    /// @brief      Recreate a missing weekday list without replacing retained Week work
    /// @details    Reserves IDs across active and archived lists and returns an existing
    ///             current-weekday list unchanged when it is already available
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    /// @throws     Fixture setup, decoding, or checked creation errors propagate to XCTest.
    ///
    func testQuickCaptureCreatesMissingCurrentWeekdayList() throws
    {


        let renamed = KanbanList(
            id: 7, title: "Renamed Thursday",
            cards: [
                KanbanCard(id: 14, word: "Keep this card", listTitle: "Renamed Thursday", checklists: [])
            ]) /* Previously renamed weekday list retained without modification */
        var archivedThursday = KanbanList(
            id: 20, title: "Thursday", cards: []) /* Archived weekday list reserves its old ID                     */
        archivedThursday.isArchived = true
        let lists = [renamed, archivedThursday]          /* Complete Week fixture                              */
        var calendar = Calendar(identifier: .gregorian)  /* Fixed calendar for deterministic weekday selection */

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let thursday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 8))) /* Thursday selection date              */
        let result = TodayListSelection.ensureCurrentDayList(
            lists: lists, date: thursday, calendar: calendar) /* Recreated active weekday destination */

        XCTAssertEqual(result.dayList.id, 21)
        XCTAssertEqual(result.dayList.title, "Thursday")
        XCTAssertTrue(result.dayList.cards.isEmpty)
        XCTAssertEqual(result.lists, lists + [result.dayList])
        XCTAssertEqual(result.lists.first(where:
                {
                    $0.id == renamed.id
                })?.cards.first?.word, "Keep this card")

        let existingResult = TodayListSelection.ensureCurrentDayList(
            lists: result.lists,
            date: thursday,
            calendar: calendar
        )

        XCTAssertEqual(existingResult.dayList.id, result.dayList.id)
        XCTAssertEqual(existingResult.lists, result.lists)
    }

}
