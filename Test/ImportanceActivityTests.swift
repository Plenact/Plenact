// --------------------------------------------------------------------------------------------------
// @file       ImportanceActivityTests.swift
// @brief      Importance Activity regression tests
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
/// ImportanceActivity regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testImportanceLevelsRequireSeparateGesturesAndRetainLegacyMarks
    /// @brief      Verify one-step importance, legacy migration, and owner isolation
    /// @details    Exercises every increase and decrease, clamping, unrelated edits, and legacy
    ///             presence-only decoding without losing higher-level selections.
    ///
    /// @return     (Void) records bounded-step and persistence assertions
    /// @throws     Propagates fixture encoding failures.
    ///
    func testImportanceLevelsRequireSeparateGesturesAndRetainLegacyMarks() throws
    {

        let owner = UUID(), other = UUID()
        var data = try JSONEncoder().encode([LibraryRecentItem(collectionID: other, cardID: 7)])
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: other, data: data), 1)
        for expected in 1 ... 5
        {

            data = LibraryImportanceSelection.adjusting(cardID: 7, collectionID: owner, direction: 99, data: data)
            XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: data), expected)
        }

        data = LibraryImportanceSelection.adjusting(cardID: 7, collectionID: owner, direction: 1, data: data)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: data), 5)
        data = LibraryImportanceSelection.setting(cardID: 7, collectionID: owner, marked: true, data: data)
        data = LibraryImportanceSelection.setting(cardID: 8, collectionID: other, marked: true, data: data)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: data), 5)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: other, data: data), 1)
        XCTAssertEqual(
            try JSONDecoder().decode([LibraryImportanceItem].self, from: data).first
            {
                $0.collectionID == owner
            }?
            .resolvedLevel, 5)
        for expected in (0 ... 4).reversed()
        {

            data = LibraryImportanceSelection.adjusting(cardID: 7, collectionID: owner, direction: -99, data: data)
            XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: data), expected)
            XCTAssertEqual(
                LibraryImportanceSelection.contains(cardID: 7, collectionID: owner, data: data), expected > 0)
        }

        XCTAssertTrue(LibraryImportanceSelection.cardIDs(collectionID: owner, data: data).isEmpty)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: Data("invalid".utf8)), 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testImportanceStarStyleDefaultsTuckedAndPersistsWithoutChangingLevels
    /// @brief      Verify the display preference is independent of importance
    /// @details    Legacy preferences default to Tucked; both choices round-trip with all other fields.
    ///
    /// @return     (Void) records default and Codable assertions
    /// @throws     Propagates fixture serialization failures.
    ///
    func testImportanceStarStyleDefaultsTuckedAndPersistsWithoutChangingLevels() throws
    {

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(LocalProfilePreferences())) as? [String: Any])
        object.removeValue(forKey: "importanceStarStyle")
        XCTAssertEqual(
            try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONSerialization.data(withJSONObject: object))
            .importanceStarStyle, .tucked)
        let suite = "ImportanceStyle." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        for style in ImportanceStarStyle.allCases
        {

            let preferences = LocalProfilePreferences(importanceStarStyle: style)
            PlanPreferencesStore.save(preferences, to: defaults)
            XCTAssertEqual(PlanPreferencesStore.load(from: defaults).importanceStarStyle, style)
            XCTAssertEqual(
                try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONEncoder().encode(preferences)),
                preferences)
        }

        let fanned = try JSONEncoder().encode(LocalProfilePreferences(importanceStarStyle: .fanned))
        let domain = try FullMonthExample.make().defaultsDomain(preserving: [PlanPreferencesStore.key: fanned])
        let retained = try XCTUnwrap(domain[PlanPreferencesStore.key] as? Data)
        XCTAssertEqual(
            try JSONDecoder().decode(LocalProfilePreferences.self, from: retained).importanceStarStyle, .fanned)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleUndoRetainsExactImportanceLevelsAndLegacySnapshots
    /// @brief      Verify example undo snapshots retain layered importance
    /// @details    Saves mixed levels and verifies old snapshots without levels remain readable.
    ///
    /// @return     (Void) records undo persistence assertions
    /// @throws     Propagates temporary defaults or JSON failures.
    ///
    func testExampleUndoRetainsExactImportanceLevelsAndLegacySnapshots() throws
    {

        let suite = "ImportanceUndo." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let levels = [1: 3, 2: 4, 3: 5]
        XCTAssertTrue(
            ExampleLoadUndoStore.save(
                lists: [], todayListID: nil, importantCardIDs: Set(levels.keys), importanceLevels: levels, to: defaults)
        )
        XCTAssertEqual(ExampleLoadUndoStore.load(from: defaults)?.importanceLevels, levels)
        let legacy = ExampleLoadUndoSnapshot(lists: [], todayListID: nil, importantCardIDs: [1])
        XCTAssertNil(
            try JSONDecoder().decode(ExampleLoadUndoSnapshot.self, from: JSONEncoder().encode(legacy)).importanceLevels)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testImportanceExamplesDemonstrateBusyDaysWithoutChangingExistingOwners
    /// @brief      Verify example levels and preservation of unrelated personal importance
    /// @details    Work, Gym, and Dinner demonstrate distinct layered states; arbitrary example
    ///             titles also receive levels only through explicit example seeding.
    ///
    /// @return     (Void) records fresh-example and preservation assertions
    ///
    func testImportanceExamplesDemonstrateBusyDaysWithoutChangingExistingOwners()
    {

        let other = UUID()
        let original = LibraryImportanceSelection.settingLevel(cardID: 4, collectionID: other, level: 5, data: Data())
        var owner = PersonalCollection(title: "Example", kind: .list)
        owner.lists[0].cards = ["Work", "Gym", "Dinner", "Sketch an idea"].enumerated().map
        {

            KanbanCard(id: $0.offset, word: $0.element, listTitle: "Example")
        }

        let data = LibraryImportanceSelection.demoData(in: [owner], preserving: original, includesAllExamples: true)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 0, collectionID: owner.id, data: data), 4)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 1, collectionID: owner.id, data: data), 3)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 2, collectionID: owner.id, data: data), 5)
        XCTAssertTrue((1 ... 5).contains(LibraryImportanceSelection.level(cardID: 3, collectionID: owner.id, data: data)))
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 4, collectionID: other, data: data), 5)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusImportanceUsesOwnerQualifiedStateAndSeedsOnlyNamedDemoRecords
    /// @brief      Verify that focus Importance Uses Owner Qualified State And Seeds Only Named Demo Records
    /// @details    Exercises `LibraryImportanceSelection.setting`, `LibraryImportanceSelection.demoData`,
    ///             `LibraryImportanceSelection.cardIDs`. Checks
    ///             `XCTAssertEqual(LibraryImportanceSelection.cardIDs(collectionID: first.id, data: data), [0, 1, 2,
    ///             3])`; `XCTAssertEqual(LibraryImportanceSelection.cardIDs(collectionID: second.id, data: data),
    ///             [0])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusImportanceUsesOwnerQualifiedStateAndSeedsOnlyNamedDemoRecords() throws
    {

        var first = PersonalCollection(title: "Demo", kind: .list)
        first.lists[0].cards = ["Work", "Gym", "Dinner", "Call Accountant", "Wake", "Morning Starbucks Pow-wow"]
        .enumerated().map
        {

            KanbanCard(id: $0.offset, word: $0.element, listTitle: "Today", checklists: [])
        }

        var second = PersonalCollection(title: "Other owner", kind: .list)
        second.lists[0].cards = [KanbanCard(id: 0, word: "Different item", listTitle: "Today", checklists: [])]
        let original = first
        var data = LibraryImportanceSelection.setting(cardID: 0, collectionID: second.id, marked: true, data: Data())
        data = LibraryImportanceSelection.demoData(in: [first], preserving: data)
        XCTAssertEqual(LibraryImportanceSelection.cardIDs(collectionID: first.id, data: data), [0, 1, 2, 3])
        XCTAssertEqual(LibraryImportanceSelection.cardIDs(collectionID: second.id, data: data), [0])
        data = LibraryImportanceSelection.setting(cardID: 0, collectionID: first.id, marked: false, data: data)
        XCTAssertFalse(LibraryImportanceSelection.contains(cardID: 0, collectionID: first.id, data: data))
        XCTAssertTrue(LibraryImportanceSelection.contains(cardID: 0, collectionID: second.id, data: data))
        XCTAssertEqual(first, original)
        let examples = FullMonthExample.make()
        let domain = try examples.defaultsDomain(preserving: [:])
        let exampleData = try XCTUnwrap(domain[LibraryImportanceSelection.key] as? Data)
        let accountant = examples.collections.flatMap
        {
            owner in
            owner.lists.flatMap(\.cards).filter
            {
                $0.word == "Call the accountant"
            } .map
            {
                (owner.id, $0.id)
            }

        }

        XCTAssertFalse(accountant.isEmpty)
        for (owner, card) in accountant
        {

            XCTAssertTrue(LibraryImportanceSelection.contains(cardID: card, collectionID: owner, data: exampleData))
        }

        let legacy = try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.todayFocusIncludesImportant)
        XCTAssertFalse(legacy.todayFocusIncludesBookmarked)
        XCTAssertFalse(legacy.todayFocusIncludesUpNext)
        let selected = LocalProfilePreferences(
            todayFocusIncludesImportant: true, todayFocusIncludesBookmarked: true, todayFocusIncludesUpNext: true)
        XCTAssertEqual(
            try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONEncoder().encode(selected)), selected)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testJmrUpgradeKeepsSavedTemplatesAndDoesNotRewriteScheduledWeeks
    /// @brief      Verify that jmr Upgrade Keeps Saved Templates And Does Not Rewrite Scheduled Weeks
    /// @details    Exercises `legacy.templates.removeAll`, `PlanningDate.date`, `DatedPlanningWeek.make`. Checks
    ///             `XCTAssertEqual(upgraded.templates.count, 6)`; `XCTAssertEqual(upgraded.templates[0],
    ///             legacy.templates[0])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testJmrUpgradeKeepsSavedTemplatesAndDoesNotRewriteScheduledWeeks() throws
    {

        let name = "Plenact.JmrUpgradeTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        var legacy = PlanningRoutineLibrary.seeded
        legacy.templates.removeAll
        {
            $0.id == PlanningRoutineLibrary.jmrID
        }

        legacy.defaultWeekID = legacy.templates[0].id
        legacy.templates[0].name = "My edited Work Week"
        legacy.bundledRoutineRevision = nil
        let oldBytes = try JSONEncoder().encode(legacy)
        defaults.set(oldBytes, forKey: PlanningRoutineStore.key)
        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar))
        let existing = DatedPlanningWeek.make(for: date, lists: SampleData.lists, calendar: calendar)
        let document = PlanningCalendarDocument(currentWeekKey: existing.startKey, firstWeekday: 2, weeks: [existing])
        try PlanningCalendarStore.save(document, to: defaults)
        let weekBytes = defaults.data(forKey: PlanningCalendarStore.key)
        let upgraded = try PlanningRoutineStore.load(from: defaults)
        XCTAssertEqual(upgraded.templates.count, 6)
        XCTAssertEqual(upgraded.templates[0], legacy.templates[0])
        XCTAssertEqual(upgraded.templates[1], legacy.templates[1])
        XCTAssertEqual(upgraded.defaultWeekID, PlanningRoutineLibrary.jmrID)
        XCTAssertEqual(upgraded.bundledRoutineRevision, 5)
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), oldBytes)
        XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), weekBytes)
        var customChoice = upgraded;
        customChoice.defaultWeekID = nil
        try PlanningRoutineStore.save(customChoice, baseline: upgraded, to: defaults)
        XCTAssertNil(try PlanningRoutineStore.load(from: defaults).defaultWeekID)
        var deleted = customChoice;
        deleted.templates.removeAll
        {
            $0.id == PlanningRoutineLibrary.jmrID
        }

        try PlanningRoutineStore.save(deleted, baseline: customChoice, to: defaults)
        XCTAssertFalse(
            try PlanningRoutineStore.load(from: defaults).templates.contains
            {
                $0.id == PlanningRoutineLibrary.jmrID
            })
        XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), weekBytes)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningDayReplacementKeepsOtherDaysArchivesAndBookmarks
    /// @brief      Verify that planning Day Replacement Keeps Other Days Archives And Bookmarks
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `target.collection.lists.firstIndex`.
    ///             Checks `XCTAssertEqual(result.collection.lists[monday].cards.map(\.word),
    ///             day.collection.lists[0].cards.map(\.word))`;
    ///             `XCTAssertTrue(result.collection.lists[monday].cards.allSatisfy { $0.id > 70 })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningDayReplacementKeepsOtherDaysArchivesAndBookmarks() throws
    {

        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: calendar))
        var target = DatedPlanningWeek.make(for: date, calendar: calendar)
        let monday = try XCTUnwrap(target.collection.lists.firstIndex
            {
                $0.id == target.dayListIDs["2026-11-02"]
            })
        let tuesday = try XCTUnwrap(target.collection.lists.firstIndex
            {
                $0.id == target.dayListIDs["2026-11-03"]
            })
        target.collection.lists[monday].cards = [
            KanbanCard(id: 50, word: "Old Monday", listTitle: "Monday", checklists: [])
        ]
        target.collection.lists[monday].archivedCards = [
            KanbanCard(id: 60, word: "Kept archive", listTitle: "Monday", checklists: [])
        ]
        target.collection.lists[tuesday].cards = [
            KanbanCard(id: 70, word: "Keep Tuesday", listTitle: "Tuesday", checklists: [])
        ]
        target.collection.savedCardIDs = [50, 60, 70]
        let day = PlanningRoutineLibrary.seeded.templates[1]
        let result = try PlanningTemplateApplication.apply(
            day, to: target, date: date, calendar: calendar, mode: .replace)
        XCTAssertEqual(result.collection.lists[monday].cards.map(\.word), day.collection.lists[0].cards.map(\.word))
        XCTAssertTrue(result.collection.lists[monday].cards.allSatisfy
            {
                $0.id > 70
            })
        XCTAssertEqual(result.collection.lists[tuesday], target.collection.lists[tuesday])
        XCTAssertEqual(result.collection.lists[monday].archivedCards, target.collection.lists[monday].archivedCards)
        XCTAssertEqual(result.collection.savedCardIDs, [60, 70])
        XCTAssertEqual(target.collection.lists[monday].cards[0].word, "Old Monday")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeeklyReviewRendersAllStepsAndPreservesSavedRecord
    /// @brief      Verify that weekly Review Renders All Steps And Preserves Saved Record
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(defaults.data(forKey:
    ///             WeeklyReviewStore.key), bytes)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testWeeklyReviewRendersAllStepsAndPreservesSavedRecord() async throws
    {

        let name = "PlenactTests.WeeklyRender." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        var baseline: WeeklyReviewRecord?
        for step in 0 ... 2
        {

            var record = baseline ?? WeeklyReviewRecord(date: .now, calendar: .current)
            record.step = step
            baseline = try WeeklyReviewStore.save(record, replacing: baseline, to: defaults)
            let bytes = defaults.data(forKey: WeeklyReviewStore.key)
            let host = UIHostingController(rootView: WeeklyReviewView(calendar: .current, defaults: defaults))
            window.rootViewController = host;
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852);

            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-weekly-\(step).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("WEEKLY_RENDER=\(url.path)")
            XCTAssertEqual(defaults.data(forKey: WeeklyReviewStore.key), bytes)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayPlanRendersSavedContextAndLivePrioritiesWithoutSourceMutations
    /// @brief      Verify that today Plan Renders Saved Context And Live Priorities Without Source Mutations
    /// @details    Exercises `DatedPlanningWeek.make`, `access.searchableItems.map`, `DailyPlanStore.save`. Checks
    ///             `XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), saved)`;
    ///             `XCTAssertEqual(access.library.first, originalSource)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayPlanRendersSavedContextAndLivePrioritiesWithoutSourceMutations() async throws
    {

        let name = "PlenactTests.DailyPlanRender." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let week = DatedPlanningWeek.make(for: .now)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        var library = PersonalCollection(title: "On the Table", kind: .list)
        library.lists[0].cards = [
            KanbanCard(
                id: 42, word: "Finish one meaningful step", listTitle: library.title, isTitleChecked: true,
                checklists: [], descriptionOverride: "Keep a little room for the unexpected")
        ]
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
        var plan = DailyPlan(date: .now)
        plan.priorities = access.searchableItems.map(DailyPlanPriority.init)
        plan.intention = "Small steps, with room to breathe"
        plan.constraints = "One focused hour before lunch"
        _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        let saved = defaults.data(forKey: DailyPlanStore.key)
        let originalSource = library
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(
            rootView: TodayPlanView(defaults: defaults).environment(\.planningCalendarAccess, access))
        window.rootViewController = host;
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        try await Task.sleep(for: .milliseconds(180))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-today-plan-saved.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("DAILY_PLAN_RENDER=\(url.path)")
        XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), saved)
        XCTAssertEqual(access.library.first, originalSource)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testImportantIndicatorUsesCollectionAndCardIdentity
    /// @brief      Verify that important Indicator Uses Collection And Card Identity
    /// @details    Exercises `LibraryImportanceSelection.contains`. Checks
    ///             `XCTAssertTrue(LibraryImportanceSelection.contains(cardID: 7, collectionID: owner, data: data))`;
    ///             `XCTAssertFalse(LibraryImportanceSelection.contains(cardID: 7, collectionID: other, data: data))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testImportantIndicatorUsesCollectionAndCardIdentity() throws
    {

        let owner = UUID()
        let other = UUID()
        let data = try JSONEncoder().encode([LibraryRecentItem(collectionID: owner, cardID: 7)])
        XCTAssertTrue(LibraryImportanceSelection.contains(cardID: 7, collectionID: owner, data: data))
        XCTAssertFalse(LibraryImportanceSelection.contains(cardID: 7, collectionID: other, data: data))
        XCTAssertFalse(LibraryImportanceSelection.contains(cardID: 8, collectionID: owner, data: data))
        XCTAssertFalse(LibraryImportanceSelection.contains(cardID: 7, collectionID: owner, data: Data()))
        let cleared = try JSONEncoder().encode([LibraryRecentItem]())
        XCTAssertFalse(LibraryImportanceSelection.contains(cardID: 7, collectionID: owner, data: cleared))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWholeListMovePreservesContentBookmarksAndCrossBoardLinks
    /// @brief      Verify that whole List Move Preserves Content Bookmarks And Cross Board Links
    /// @details    Exercises `.linkedCard`, `CrossBoardListMovement.move`, `boards[0].lists.map`. Checks
    ///             `XCTAssertEqual(boards[0].lists.map(\.id), [9])`; `XCTAssertEqual(boards[1].lists.count, 2)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWholeListMovePreservesContentBookmarksAndCrossBoardLinks() throws
    {

        var first = KanbanCard(id: 1, word: "Garden plan", listTitle: "Ideas", descriptionOverride: "Keep all writing")
        first.displayFormat = .note
        first.checklists = [
            KanbanChecklist(
                title: "Links",
                items: [
                    KanbanChecklistItem(title: "Internal archived card", content: .linkedCard(cardID: 2)),
                    KanbanChecklistItem(title: "Stays on source board", content: .linkedCard(cardID: 99))
                ])
        ]
        let archived = KanbanCard(id: 2, word: "Archived", listTitle: "Ideas")
        var moving = KanbanList(
            id: 1, title: "Ideas", cards: [first], archivedCards: [archived], newItemPresentation: .note)
        moving.appearance = ItemAppearance(accent: .green)
        moving.subtitleOverride = "Keep list description"
        var source = PersonalCollection(title: "Week", kind: .board)
        var remaining = KanbanCard(id: 99, word: "Remaining", listTitle: "Other")
        remaining.checklists = [
            KanbanChecklist(
                title: "Link", items: [KanbanChecklistItem(title: "Moved note", content: .linkedCard(cardID: 1))])
        ]
        source.lists = [moving, KanbanList(id: 9, title: "Other", cards: [remaining])]
        source.savedCardIDs = [1, 2, 99]
        var target = PersonalCollection(title: "Library", kind: .board)
        target.lists = [KanbanList(id: 1, title: "Existing", cards: [first], archivedCards: [archived])]
        target.savedCardIDs = [1]
        var boards = [source, target]
        let moved = try CrossBoardListMovement.move(listID: 1, from: source.id, to: target.id, collections: &boards)
        XCTAssertEqual(boards[0].lists.map(\.id), [9])
        XCTAssertEqual(boards[1].lists.count, 2)
        XCTAssertEqual(moved.title, moving.title)
        XCTAssertNotEqual(moved.id, moving.id)
        XCTAssertEqual(moved.appearance, moving.appearance)
        XCTAssertEqual(moved.subtitleOverride, moving.subtitleOverride)
        XCTAssertEqual(moved.newItemPresentation, .note)
        let note = try XCTUnwrap(moved.cards.first)
        let retained = try XCTUnwrap(moved.archivedCards.first)
        XCTAssertEqual(note.descriptionOverride, first.descriptionOverride)
        XCTAssertEqual(note.displayFormat, .note)
        XCTAssertNotEqual(note.id, 1)
        XCTAssertNotEqual(retained.id, 2)
        XCTAssertEqual(note.checklists[0].items[0].content, .linkedCard(cardID: retained.id))
        XCTAssertEqual(note.checklists[0].items[0].linkedCollectionID, target.id)
        XCTAssertEqual(note.checklists[0].items[1].content, .linkedCard(cardID: 99))
        XCTAssertEqual(note.checklists[0].items[1].linkedCollectionID, source.id)
        XCTAssertEqual(boards[0].lists[0].cards[0].checklists[0].items[0].content, .linkedCard(cardID: note.id))
        XCTAssertEqual(boards[0].lists[0].cards[0].checklists[0].items[0].linkedCollectionID, target.id)
        XCTAssertEqual(boards[0].savedCardIDs, [99])
        XCTAssertEqual(boards[1].savedCardIDs, [1, note.id, retained.id])
        let roundTrip = try JSONDecoder().decode([PersonalCollection].self, from: JSONEncoder().encode(boards))
        XCTAssertEqual(roundTrip, boards)
        let returned = try CrossBoardListMovement.move(
            listID: moved.id, from: target.id, to: source.id, collections: &boards)
        XCTAssertEqual(returned.cards[0].descriptionOverride, first.descriptionOverride)
        XCTAssertEqual(returned.archivedCards.count, 1)
        XCTAssertEqual(boards[1].lists.count, 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testActivityHistoryRetainsOwnersBoundsAndClearsOnlyShortcuts
    /// @brief      Verify that activity History Retains Owners Bounds And Clears Only Shortcuts
    /// @details    Exercises `LibraryRecentStore.remember`, `ActivityRecentStore.remember`,
    ///             `ActivityRecentStore.load`. Checks `XCTAssertEqual(ActivityRecentStore.load(from: defaults),
    ///             [library, week])`; `XCTAssertEqual(ActivityRecentStore.load(from: defaults).count, 20)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testActivityHistoryRetainsOwnersBoundsAndClearsOnlyShortcuts() throws
    {

        let suite = "ActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let library = LibraryRecentItem(collectionID: UUID(), cardID: 1)
        let week = LibraryRecentItem(collectionID: UUID(), cardID: 1)
        _ = LibraryRecentStore.remember(library, defaults: defaults)
        ActivityRecentStore.remember(week, defaults: defaults)
        ActivityRecentStore.remember(library, defaults: defaults)
        XCTAssertEqual(ActivityRecentStore.load(from: defaults), [library, week])
        for id in 2 ... 30
        {

            ActivityRecentStore.remember(
                LibraryRecentItem(collectionID: week.collectionID, cardID: id), defaults: defaults)
        }

        XCTAssertEqual(ActivityRecentStore.load(from: defaults).count, 20)
        XCTAssertEqual(ActivityRecentStore.load(from: defaults).first?.cardID, 30)
        defaults.set("saved payload", forKey: "SavedFixture")
        ActivityRecentStore.clear(defaults: defaults)
        XCTAssertTrue(ActivityRecentStore.load(from: defaults).isEmpty)
        XCTAssertTrue(LibraryRecentStore.load(from: defaults).isEmpty)
        XCTAssertEqual(defaults.string(forKey: "SavedFixture"), "saved payload")
        _ = LibraryRecentStore.remember(library, defaults: defaults)
        XCTAssertEqual(ActivityRecentStore.load(from: defaults), [library])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryRecentsPersistDeduplicateAndKeepCollectionsSeparate
    /// @brief      Verify that library Recents Persist Deduplicate And Keep Collections Separate
    /// @details    Exercises `LibraryRecentStore.remember`, `LibraryRecentStore.load`. Checks
    ///             `XCTAssertEqual(LibraryRecentStore.remember(first, defaults: defaults), [first, second])`;
    ///             `XCTAssertEqual(LibraryRecentStore.load(from: defaults), [first, second])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLibraryRecentsPersistDeduplicateAndKeepCollectionsSeparate() throws
    {

        let suite = "LibraryRecentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let first = LibraryRecentItem(collectionID: UUID(), cardID: 1)
        let second = LibraryRecentItem(collectionID: UUID(), cardID: 1)
        _ = LibraryRecentStore.remember(first, defaults: defaults)
        _ = LibraryRecentStore.remember(second, defaults: defaults)
        XCTAssertEqual(LibraryRecentStore.remember(first, defaults: defaults), [first, second])
        XCTAssertEqual(LibraryRecentStore.load(from: defaults), [first, second])
        for id in 2 ... 12
        {

            _ = LibraryRecentStore.remember(
                LibraryRecentItem(collectionID: first.collectionID, cardID: id), defaults: defaults)
        }

        XCTAssertEqual(LibraryRecentStore.load(from: defaults).count, 8)
        XCTAssertEqual(LibraryRecentStore.load(from: defaults).first?.cardID, 12)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTabletTodayPlanSummaryRendersSavedAndEmptyStatesWithoutWriting
    /// @brief      Verify that tablet Today Plan Summary Renders Saved And Empty States Without Writing
    /// @details    Exercises `DatedPlanningWeek.make`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), before)`;
    ///             `XCTAssertEqual(opens, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTabletTodayPlanSummaryRendersSavedAndEmptyStatesWithoutWriting() async throws
    {

        let name = "PlenactTests.TodaySummary." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let date = Date.now
        let week = DatedPlanningWeek.make(for: date)
        var table = PersonalCollection(title: "On the Table", kind: .list)
        table.lists[0].cards = [
            KanbanCard(
                id: 0, word: "Finish a meaningful step", listTitle: table.title, isTitleChecked: true, checklists: []),
            KanbanCard(id: 1, word: "Make room for a walk", listTitle: table.title, checklists: []),
            KanbanCard(id: 2, word: "Ideas for later", listTitle: table.title, checklists: [], presentation: .note)
        ]
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
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        var opens = 0
        for saved in [false, true]
        {

            if saved
            {

                var plan = DailyPlan(date: date)
                plan.intention = "A little focus, with room to breathe"
                plan.priorities = sources.map(DailyPlanPriority.init)
                plan.checkIn = DailyCheckIn(
                    focus: plan.priorities.first
                    {
                        $0.title == "Make room for a walk"
                    }, changed: "", savedAt: .now)
                _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
            }

            let before = defaults.data(forKey: DailyPlanStore.key)
            let host = UIHostingController(
                rootView: TodayPlanSummaryPanel(
                    date: date, calendar: .current, sources: sources, defaults: defaults, onOpen:
                    {
                        opens += 1
                    }
                ).padding(24).background(Color(.systemGroupedBackground)))
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-today-summary-\(saved).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("TODAY_SUMMARY_RENDER=\(url.path)")
            XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), before)
        }

        XCTAssertEqual(opens, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDateTimeEditorOpeningDoesNotSaveDraft
    /// @brief      Verify that date Time Editor Opening Does Not Save Draft
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(saves, 0)`;
    ///             `XCTAssertGreaterThan(host.view.bounds.height, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDateTimeEditorOpeningDoesNotSaveDraft() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var saves = 0
        let host = UIHostingController(
            rootView: CardDateEditorSheet(title: "Due date", date: nil, kind: .dateAndTime)
            {
                _, _ in
                saves += 1;
                return true
            })
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(saves, 0, "Opening a date draft must not create a stored date")
        XCTAssertGreaterThan(host.view.bounds.height, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekStartMigrationKeepsDatesArchivesBookmarksAndUniqueIDs
    /// @brief      Verify that week Start Migration Keeps Dates Archives Bookmarks And Unique I Ds
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `.linkedCard`. Checks
    ///             `XCTAssertEqual(document.currentWeekKey, "2026-10-05")`;
    ///             `XCTAssertEqual(document.calendar.firstWeekday, 2)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWeekStartMigrationKeepsDatesArchivesBookmarksAndUniqueIDs() throws
    {

        var sunday = Calendar(identifier: .gregorian)
        sunday.timeZone = TimeZone(secondsFromGMT: 0)!
        sunday.firstWeekday = 1
        let today = try XCTUnwrap(PlanningDate.date("2026-10-11", calendar: sunday))
        let earlier = try XCTUnwrap(PlanningDate.date("2026-10-04", calendar: sunday))
        var first = DatedPlanningWeek.make(for: earlier, calendar: sunday)
        var second = DatedPlanningWeek.make(for: today, calendar: sunday)


        ///
        /// @fcn        PlenactBoardDocumentTests.testWeekStartMigrationKeepsDatesArchivesBookmarksAndUniqueIDs.fill
        /// @brief      Prepare fill for the enclosing regression test
        /// @details    Supplies the local fixture for week Start Migration Keeps Dates Archives Bookmarks And Unique
        ///             I Ds. Uses `list.makeItem`.
        ///
        /// @param[in,out]  week  Dated planning week being inspected or saved
        ///
        /// @return     (Void) no return value
        ///
        func fill(_ week: inout DatedPlanningWeek)
        {

            for index in week.collection.lists.indices
            {

                let list = week.collection.lists[index]
                var card = list.makeItem(
                    id: index, title: "\(week.startKey) \(list.title)", description: "Retained body",
                    subtitle: "Retained subtitle")
                card.sectionLayout = CardSectionLayout(order: [.activity, .description], hidden: [.details])
                week.collection.lists[index].cards = [card]
            }

        }

        fill(&first);
        fill(&second)
        let link = KanbanChecklistItem(title: "Sunday link", content: .linkedCard(cardID: 0))
        second.collection.lists[1].cards[0].checklists = [KanbanChecklist(title: "Linked", items: [link])]
        first.explicitlySaved = true
        first.collection.lists[2].archivedCards = [
            first.collection.lists[2].makeItem(id: 100, title: "Archived note", presentationOverride: .note)
        ]
        second.collection.savedCardIDs = [0]
        second.collection.lists.append(KanbanList(id: 20, title: "Undated extras", cards: []))
        let before = [first, second].flatMap
        {
            $0.collection.lists.flatMap(\.allCards)
        }

        var document = PlanningCalendarDocument(
            currentWeekKey: second.startKey, firstWeekday: 1, weeks: [first, second])
        try document.changeFirstWeekday(to: 2, now: today)
        XCTAssertEqual(document.currentWeekKey, "2026-10-05")
        XCTAssertEqual(document.calendar.firstWeekday, 2)
        let current = try XCTUnwrap(document.week(for: today))
        XCTAssertEqual(current.list(on: today)?.cards.first?.word, "2026-10-11 Sunday")
        XCTAssertEqual(current.collection.savedCardIDs, Set(current.list(on: today)!.cards.map(\.id)))
        XCTAssertEqual(current.collection.lists.first?.title, "Monday")
        XCTAssertEqual(current.collection.lists[6].title, "Sunday")
        let after = document.weeks.flatMap
        {
            $0.collection.lists.flatMap(\.allCards)
        }

        XCTAssertEqual(Set(after.map(\.word)), Set(before.map(\.word)))
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(Set(after.map(\.id)).count, after.count)
        for original in before
        {

            let migrated = try XCTUnwrap(after.first
                {
                    $0.word == original.word
                })
            XCTAssertEqual(migrated.descriptionOverride, original.descriptionOverride)
            XCTAssertEqual(migrated.subtitleOverride, original.subtitleOverride)
            XCTAssertEqual(migrated.sectionLayout, original.sectionLayout)
            XCTAssertEqual(migrated.presentation, original.presentation)
        }

        for originalWeek in [first, second]
        {

            for (dateKey, listID) in originalWeek.dayListIDs
            {

                let date = try XCTUnwrap(PlanningDate.date(dateKey, calendar: sunday))
                let oldList = try XCTUnwrap(originalWeek.collection.lists.first
                    {
                        $0.id == listID
                    })
                let newList = try XCTUnwrap(document.week(for: date)?.list(on: date))
                XCTAssertEqual(newList.cards.map(\.word), oldList.cards.map(\.word))
                XCTAssertEqual(newList.archivedCards.map(\.word), oldList.archivedCards.map(\.word))
            }

        }

        let owner = try XCTUnwrap(document.weeks.first
            {
                $0.id == second.id
            })
        XCTAssertEqual(document.checklistLinkWeeks? [link.id], current.id)
        XCTAssertEqual(owner.startKey, "2026-10-12")
        XCTAssertTrue(owner.collection.lists.contains
            {
                $0.title == "Undated extras"
            })
        let ownerIndex = try XCTUnwrap(document.weeks.firstIndex
            {
                $0.id == owner.id
            })
        let extrasIndex = try XCTUnwrap(
            document.weeks[ownerIndex].collection.lists.firstIndex
            {
                $0.title == "Undated extras"
            })
        document.weeks[ownerIndex].collection.lists[extrasIndex].cards = [
            KanbanCard(id: 0, word: "Imported ID collision", listTitle: "Undated extras")
        ]
        try document.changeFirstWeekday(to: 1, now: today)
        let reunited = try XCTUnwrap(document.week(for: today))
        let monday = try XCTUnwrap(reunited.collection.lists.first
            {
                $0.title == "Monday"
            })
        XCTAssertEqual(
            monday.cards.first?.checklists.first?.items.first?.content,
            .linkedCard(cardID: reunited.list(on: today)!.cards[0].id))
        XCTAssertEqual(document.currentWeekKey, "2026-10-11")
        XCTAssertNil(document.checklistLinkWeeks? [link.id])
        XCTAssertEqual(document.week(for: today)?.list(on: today)?.cards.first?.word, "2026-10-11 Sunday")
        let encoded = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(PlanningCalendarDocument.self, from: encoded), document)
        let unchanged = document
        try document.changeFirstWeekday(to: 1, now: today)
        XCTAssertEqual(document, unchanged)
        XCTAssertThrowsError(try document.changeFirstWeekday(to: 4, now: today))
        XCTAssertEqual(document, unchanged)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testActivityDueSoonIncludesOverdueAndExcludesCompletedUndatedAndLaterItems
    /// @brief      Verify that activity Due Soon Includes Overdue And Excludes Completed Undated And Later Items
    /// @details    Exercises `XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar)).addingTimeInterval`,
    ///             `PlanningDate.date`, `ActivityFocusSelection.isDueSoon`. Checks
    ///             `XCTAssertTrue(ActivityFocusSelection.isDueSoon(card, now: now, calendar: calendar))`;
    ///             `XCTAssertTrue(ActivityFocusSelection.dueReason(card, now: now, calendar:
    ///             calendar).hasPrefix("Overdue"))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testActivityDueSoonIncludesOverdueAndExcludesCompletedUndatedAndLaterItems() throws
    {

        let calendar = planningTestCalendar()
        let now = try XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar)).addingTimeInterval(12 * 3600)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        var card = KanbanCard(id: 1, word: "Garden", listTitle: "Plans", dueDate: yesterday)
        XCTAssertTrue(ActivityFocusSelection.isDueSoon(card, now: now, calendar: calendar))
        XCTAssertTrue(ActivityFocusSelection.dueReason(card, now: now, calendar: calendar).hasPrefix("Overdue"))
        card.dueDate = now
        XCTAssertTrue(ActivityFocusSelection.dueReason(card, now: now, calendar: calendar).hasPrefix("Due today"))
        card.dueDate = calendar.date(byAdding: .day, value: 6, to: now)
        XCTAssertTrue(ActivityFocusSelection.isDueSoon(card, now: now, calendar: calendar))
        card.dueDate = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))
        XCTAssertFalse(ActivityFocusSelection.isDueSoon(card, now: now, calendar: calendar))
        card.dueDate = yesterday
        card.isTitleChecked = true
        XCTAssertFalse(ActivityFocusSelection.isDueSoon(card, now: now, calendar: calendar))
        card.isTitleChecked = false
        card.dueDateKind = .time
        XCTAssertFalse(ActivityFocusSelection.isDueSoon(card, now: now, calendar: calendar))
        card.dueDateKind = .date
        card.displayFormat = .divider
        XCTAssertFalse(ActivityFocusSelection.isDueSoon(card, now: now, calendar: calendar))
        card.displayFormat = .card
        card.dueDate = nil
        XCTAssertFalse(ActivityFocusSelection.isDueSoon(card, now: now, calendar: calendar))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCrossBoardCardMoveRoundTripPreservesContentAndBookmark
    /// @brief      Verify that cross Board Card Move Round Trip Preserves Content And Bookmark
    /// @details    Exercises `CrossBoardCardMovement.move`, `original.replacingLocation`,
    ///             `collections[0].savedCardIDs.contains`. Checks `XCTAssertEqual(moved,
    ///             original.replacingLocation(id: original.id, listTitle: "Ideas"))`;
    ///             `XCTAssertTrue(week[0].cards.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCrossBoardCardMoveRoundTripPreservesContentAndBookmark() throws
    {

        let original = SampleData.lists[0].cards[0]
        var week = [KanbanList(id: 10, title: "Monday", cards: [original])]
        var library = PersonalCollection(title: "Ideas", kind: .list)
        library.lists = [KanbanList(id: 20, title: "Ideas", cards: [])]
        var collections = [library]
        var saved: Set<Int> = [original.id]
        try CrossBoardCardMovement.move(
            original, from: nil,
            to: CardMoveDestination(collectionID: library.id, listID: 20, title: "Ideas", group: "Library"),
            week: &week, collections: &collections, saved: &saved)
        let moved = try XCTUnwrap(collections[0].lists[0].cards.first)
        XCTAssertEqual(moved, original.replacingLocation(id: original.id, listTitle: "Ideas"))
        XCTAssertTrue(week[0].cards.isEmpty)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(collections[0].savedCardIDs.contains(moved.id))
        try CrossBoardCardMovement.move(
            moved, from: library.id,
            to: CardMoveDestination(collectionID: nil, listID: 10, title: "Monday", group: "Week"),
            week: &week, collections: &collections, saved: &saved)
        XCTAssertEqual(week[0].cards.first, original.replacingLocation(id: original.id, listTitle: "Monday"))
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        XCTAssertTrue(collections[0].savedCardIDs.isEmpty)
        XCTAssertTrue(saved.contains(original.id))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryDirectoryNoteDestinationPrefersMostRecentlyOpenedList()
    /// @brief      Resolve the Library New Note target without moving or changing collections
    /// @details    Prefer a retained recent List, fall back to the first visible active List,
    ///             and return no destination when Library has no active Lists
    ///
    /// @return     (Void) records destination selection assertion failures
    ///
    func testLibraryDirectoryNoteDestinationPrefersMostRecentlyOpenedList()
    {


        let first = PersonalCollection(title: "First ideas", kind: .list)    /* First value in the comparison  */
        let recent = PersonalCollection(title: "Recent ideas", kind: .list)  /* Most recent activity entry     */
        let board = PersonalCollection(title: "Projects", kind: .board)      /* Board state under verification */

        XCTAssertEqual(

            BoardListsView.resolveNoteDestination(
                mostRecentlyOpenedListID: recent.id,
                collections: [first, recent, board],
                visibleCollections: [first, board]
            ),
            recent
        )

        XCTAssertEqual(

            BoardListsView.resolveNoteDestination(
                mostRecentlyOpenedListID: UUID(),
                collections: [first, recent, board],
                visibleCollections: [board, first]
            ),
            first
        )

        XCTAssertNil(
            BoardListsView.resolveNoteDestination(
                mostRecentlyOpenedListID: nil,
                collections: [board],
                visibleCollections: [board]
            )
        )
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPermanentCardDeletionIncludesArchivesAndRemovesOnlyOwningBookmarks()
    /// @brief      Remove retained card records without affecting other Board-local identities
    /// @details    Exercises an archived list and keeps an independent collection with an equal
    ///             card ID
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testPermanentCardDeletionIncludesArchivesAndRemovesOnlyOwningBookmarks()
    {


        let card = KanbanCard(
            id: 12, word: "Synthetic", listTitle: "Retained", checklists: []) /* Card value under verification    */
        var archivedList = KanbanList(
            id: 3, title: "Retained", cards: [], archivedCards: [card]) /* List containing archived records */

        archivedList.isArchived = true

        var snapshot = [
            archivedList,
            KanbanList(
                id: 4, title: "Other",
                cards: [ /* Persisted snapshot under verification */
                    KanbanCard(id: 13, word: "Keep", listTitle: "Other", checklists: [])
                ])
        ]
        let independent = [archivedList]    /* Independent archived List set        */
        var bookmarks: Set<Int> = [12, 13]  /* Saved-card bookmarks before deletion */

        BoardContentDeletion.card(12, in: &snapshot, savedCardIDs: &bookmarks)

        XCTAssertTrue(snapshot[0].allCards.isEmpty)
        XCTAssertEqual(snapshot[1].cards.map(\.id), [13])
        XCTAssertEqual(bookmarks, [13])
        XCTAssertEqual(independent[0].archivedCards, [card])

        BoardContentDeletion.card(12, in: &snapshot, savedCardIDs: &bookmarks)

        XCTAssertEqual(bookmarks, [13])
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
    func testPersonalBoardArchiveFailureKeepsMemoryAndSavedSnapshotActive() throws
    {


        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let board = PersonalCollection(title: "Project", kind: .board) /* Board state under verification */

        try PersonalCollectionStore.saveChecked([board], to: defaults)

        var draft = board /* Uncommitted draft under test */
        var invalidCard = KanbanCard(
            id: 1, word: "Unsaved", listTitle: draft.lists[0].title) /* Unsupported Card fixture     */

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
    func testPersonalBoardArchiveRejectsMissingBoardWithoutChangingSavedData() throws
    {


        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let board = PersonalCollection(title: "Project", kind: .board) /* Board state under verification */

        try PersonalCollectionStore.saveChecked([board], to: defaults)

        XCTAssertThrowsError(try PersonalCollectionStore.archiveBoard(id: UUID(), in: [board], to: defaults))
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [board])
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
    func testAPIActivityEndsAfterSuccessFailureAndCancellation() async throws
    {


        let configuration = URLSessionConfiguration.ephemeral /* API client configuration */

        configuration.protocolClasses = [ActivityTestURLProtocol.self]

        let session = URLSession(configuration: configuration) /* Local API session state */

        defer
        {


            session.invalidateAndCancel()
        }


        for outcome in ["success", "timeout", "cancelled"]
        {


            let initialCount = DatabaseActivity.shared.operations.count               /* Initial request count       */
            let url = try XCTUnwrap(URL(string: "https://\(outcome).example.test/"))  /* URL fixture for the request */
            let client = try PlenactAPIClient(baseURL: url, session: session)         /* In-process API client       */

            do
            {


                let users = try await client.directory(token: "synthetic-test-token") /* Synthetic directory users */

                XCTAssertEqual(outcome, "success")
                XCTAssertTrue(users.isEmpty)
            }
            catch
            {


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
    func testDatabaseActivityKeepsSpinnerUntilAllOperationsFinish()
    {


        let activity = DatabaseActivity()                                 /* Captured activity event      */
        let save = activity.begin("Saving Board...")                      /* Save operation under test    */
        let refresh = activity.begin("Synchronizing shared database...")  /* Refresh operation under test */

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
    /// @fcn        PlenactBoardDocumentTests.testDatabaseActivityErrorsRemainUntilDismissed()
    /// @brief      Retain a reported error after activity finishes
    /// @details    Checks that only explicit dismissal clears the error message
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testDatabaseActivityErrorsRemainUntilDismissed()
    {


        let activity = DatabaseActivity()                  /* Captured activity event */
        let operation = activity.begin("Saving Board...")  /* Pending save operation  */

        activity.report("Could not save the Board.")
        activity.end(operation)

        XCTAssertFalse(activity.isWorking)
        XCTAssertEqual(activity.errorMessage, "Could not save the Board.")

        activity.dismissError()

        XCTAssertNil(activity.errorMessage)
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
    func testRecentSearchesAreOrderedDeduplicatedAndClearable() throws
    {


        let suite = "Plenact.SearchTests.\(UUID().uuidString)"        /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        RecentSearchStore.remember("  Monday  ", in: defaults)
        RecentSearchStore.remember("Work", in: defaults)

        XCTAssertEqual(RecentSearchStore.remember("monday", in: defaults), ["monday", "Work"])
        XCTAssertEqual(RecentSearchStore.remember("  ", in: defaults), ["monday", "Work"])

        for index in 0 ..< 12
        {


            RecentSearchStore.remember("Search \(index)", in: defaults)
        }


        XCTAssertEqual(RecentSearchStore.load(from: defaults).count, 10)
        XCTAssertEqual(RecentSearchStore.load(from: defaults).first, "Search 11")

        RecentSearchStore.clear(in: defaults)

        XCTAssertTrue(RecentSearchStore.load(from: defaults).isEmpty)
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
    func testLastViewedListResolvesSavedSelectionAndFallbacks() throws
    {


        let suite = "Plenact.LastViewedListTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))    /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let lists = [
            KanbanList(id: 4, title: "Week", cards: []), KanbanList(id: 9, title: "Shopping", cards: [])
        ] /* Board lists under verification */

        LastViewedListStore.save(9, to: defaults)

        XCTAssertEqual(LastViewedListStore.resolve(in: lists, fallback: 4, from: defaults), 9)
        XCTAssertEqual(LastViewedListStore.resolve(in: [lists[0]], fallback: nil, from: defaults), 4)
        XCTAssertEqual(LastViewedListStore.resolve(in: [], fallback: nil, from: defaults), nil)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionBookmarksResolveActiveRecordsWithScopedIdentity()
    /// @brief      Resolve personal bookmarks without crossing collection-local identity boundaries
    /// @details    Excludes stale IDs, dividers, archived lists, and archived collections
    ///
    /// @return     (Void) records assertion failures for personal Saved-row resolution
    ///
    func testPersonalCollectionBookmarksResolveActiveRecordsWithScopedIdentity()
    {


        var first = PersonalCollection(title: "First", kind: .list) /* First independent collection */
        let firstCard = KanbanCard(
            id: 1, word: "First item", listTitle: "First", checklists: []) /* Active bookmark              */
        let divider = KanbanCard(
            id: 2, word: "—", listTitle: "First", isDivider: true, checklists: []) /* Non-bookmarkable separator   */
        first.lists[0].cards = [firstCard, divider]

        var archivedList = KanbanList(
            id: 1, title: "Archived",
            cards: [
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

}
