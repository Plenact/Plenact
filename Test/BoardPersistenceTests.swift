// --------------------------------------------------------------------------------------------------
// @file       BoardPersistenceTests.swift
// @brief      Board Persistence regression tests
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
/// BoardPersistence regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testListBackgroundOpacityDefaultsClampsAndPersistsIndependently
    /// @brief      Verify that list Background Opacity Defaults Clamps And Persists Independently
    /// @details    Exercises `BoardAppearance().resolved`. Checks
    ///             `XCTAssertEqual(legacy.resolvedListBackgroundOpacity, 1)`; `XCTAssertFalse(appearance.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListBackgroundOpacityDefaultsClampsAndPersistsIndependently() throws
    {

        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.resolvedListBackgroundOpacity, 1)
        for value in [0.0, 0.5, 1.0]
        {

            let appearance = ItemAppearance(listBackgroundOpacity: value)
            XCTAssertFalse(appearance.isEmpty)
            let restored = try JSONDecoder().decode(ItemAppearance.self, from: JSONEncoder().encode(appearance))
            XCTAssertEqual(restored.resolvedListBackgroundOpacity, value)
            XCTAssertEqual(BoardAppearance().resolved(restored).resolvedListBackgroundOpacity, value)
            XCTAssertNil(restored.background)
            XCTAssertNil(restored.cardTitleColor)
        }

        XCTAssertEqual(ItemAppearance(listBackgroundOpacity: -1).resolvedListBackgroundOpacity, 0)
        XCTAssertEqual(ItemAppearance(listBackgroundOpacity: 2).resolvedListBackgroundOpacity, 1)
        XCTAssertEqual(ItemAppearance(listBackgroundOpacity: .nan).resolvedListBackgroundOpacity, 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListIconColorsPersistAndMainListColorsRemainFixed
    /// @brief      Verify that list Icon Colors Persist And Main List Colors Remain Fixed
    /// @details    Exercises `restored.resolvedIconColor`, `restored.headerAppearance`, `list.resolvedIconColor`.
    ///             Checks `XCTAssertEqual(restored.resolvedIconColor(collectionColor: .orange), .blue)`;
    ///             `XCTAssertEqual(restored.headerAppearance()?.iconColor, .blue)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListIconColorsPersistAndMainListColorsRemainFixed() throws
    {

        var list = KanbanList(id: 1, title: "Custom", cards: [])
        list.appearance = ItemAppearance(iconColor: .blue, showsIconInHeader: true)
        let restored = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(restored.resolvedIconColor(collectionColor: .orange), .blue)
        XCTAssertEqual(restored.headerAppearance()?.iconColor, .blue)
        XCTAssertNil(restored.appearance?.background)
        XCTAssertFalse(ItemAppearance(iconColor: .blue).isEmpty)
        list.appearance?.iconColor = nil
        XCTAssertEqual(list.resolvedIconColor(collectionColor: .orange), .orange)
        XCTAssertNotEqual(
            KanbanList.fixedHeaderIconColor(for: "On the Table"), KanbanList.fixedIconColor(for: "On the Table"))
        for title in ["On the Table", "In the Queue", "Scheduled"]
        {

            var main = DefaultListTutorial.makeStarter(title: title).lists[0]
            main.appearance?.iconColor = .blue
            XCTAssertEqual(main.resolvedIconColor(collectionColor: .green), KanbanList.fixedIconColor(for: title))
            XCTAssertEqual(main.headerAppearance()?.iconColor, KanbanList.fixedHeaderIconColor(for: title))
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListCheckmarkResetRestoresExactNestedFlagsWithoutReplacingContent
    /// @brief      Verify that list Checkmark Reset Restores Exact Nested Flags Without Replacing Content
    /// @details    Exercises `.actionDetail`, `ListCheckmarkReset.reset`, `ListCheckmarkReset.values(in:
    ///             list).values.contains`. Checks `XCTAssertFalse(ListCheckmarkReset.values(in:
    ///             list).values.contains(true))`; `XCTAssertEqual(list.archivedCards, original.archivedCards)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListCheckmarkResetRestoresExactNestedFlagsWithoutReplacingContent() throws
    {

        let nested = KanbanChecklist(
            title: "Nested", items: [KanbanChecklistItem(title: "Nested done", isCompleted: true)])
        let detail = KanbanChecklistActionDetail(description: "Keep details", checklists: [nested])
        let checklist = KanbanChecklist(
            title: "Steps",
            items: [
                KanbanChecklistItem(title: "Done", isCompleted: true, content: .actionDetail(detail)),
                KanbanChecklistItem(title: "Still open")
            ])
        var list = KanbanList(
            id: 1, title: "Sunday",
            cards: [
                KanbanCard(
                    id: 1, word: "Done card", listTitle: "Sunday", isTitleChecked: true, checklists: [checklist]),
                KanbanCard(id: 2, word: "Open card", listTitle: "Sunday", checklists: [])
            ])
        list.archivedCards = [
            KanbanCard(id: 99, word: "Archived", listTitle: "Sunday", isTitleChecked: true, checklists: [])
        ]
        let original = list
        let (snapshot, cards) = ListCheckmarkReset.reset(list)
        list.cards = cards
        XCTAssertFalse(ListCheckmarkReset.values(in: list).values.contains(true))
        XCTAssertEqual(list.archivedCards, original.archivedCards)
        XCTAssertTrue(snapshot.canRestore(list))
        var expectedRestored = original.cards
        for index in expectedRestored.indices
        {
            expectedRestored[index].editHistory = list.cards[index].editHistory
        }
        XCTAssertEqual(snapshot.restoring(list), expectedRestored)
        XCTAssertEqual(list.cards[0].editHistory?.count, 1)
        XCTAssertNil(list.cards[1].editHistory)
        list.cards[0].word = "Edited title survives restore"
        let restored = try XCTUnwrap(snapshot.restoring(list))
        XCTAssertEqual(restored[0].word, "Edited title survives restore")
        XCTAssertTrue(restored[0].isTitleChecked)
        list.cards[1].isTitleChecked = true
        XCTAssertFalse(snapshot.canRestore(list))
        XCTAssertNil(snapshot.restoring(list))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLowerCornerBackPreferenceDefaultsOnAndPersistsWithoutProfile
    /// @brief      Enable corner Back by default while retaining an explicit user opt-out
    /// @details    New preferences and older records without the field enable the shortcut. Explicitly saved false
    ///             values still round-trip and remain disabled; reading defaults never creates a profile or record.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLowerCornerBackPreferenceDefaultsOnAndPersistsWithoutProfile() throws
    {

        let legacy = try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.enablesLowerCornerBack)
        XCTAssertTrue(LocalProfilePreferences().enablesLowerCornerBack)
        let suite = "CornerBack." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        XCTAssertTrue(PlanPreferencesStore.load(from: defaults).enablesLowerCornerBack)
        XCTAssertNil(defaults.object(forKey: PlanPreferencesStore.key))
        var preferences = legacy
        preferences.enablesLowerCornerBack = true
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertTrue(PlanPreferencesStore.load(from: defaults).enablesLowerCornerBack)
        preferences.enablesLowerCornerBack = false
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertFalse(PlanPreferencesStore.load(from: defaults).enablesLowerCornerBack)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
        XCTAssertEqual(
            try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONEncoder().encode(preferences)), preferences
        )
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAddItemTextColorsPersistAndRemainScopedToTheirView
    /// @brief      Verify capture colors, legacy defaults, and independent List overrides
    /// @details    Checks Codable compatibility, Board inheritance, built-in readability defaults,
    ///             and preservation of unrelated Card text colors and List content.
    ///
    /// @return     (Void) records color and persistence assertions
    /// @throws     Propagates encoding or decoding failures.
    ///
    func testAddItemTextColorsPersistAndRemainScopedToTheirView() throws
    {

        let legacy = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.addItemTextColor)
        XCTAssertNil(legacy.resolvedAddItemTextColor(list: nil, title: "Thursday"))
        for title in ["On the Table", "In the Queue", "Scheduled"]
        {

            XCTAssertEqual(legacy.resolvedAddItemTextColor(list: nil, title: title), .white)
            XCTAssertEqual(DefaultListTutorial.makeStarter(title: title).boardAppearance?.addItemTextColor, .white)
        }

        var board = BoardAppearance()
        board.addItemTextColor = .white
        board.cardTextColor = .blue
        var list = ItemAppearance()
        list.addItemTextColor = .charcoal
        XCTAssertFalse(list.isEmpty)
        XCTAssertEqual(board.resolvedAddItemTextColor(list: list, title: "Projects"), .charcoal)
        XCTAssertEqual(board.resolvedAddItemTextColor(list: nil, title: "Projects"), .white)
        XCTAssertEqual(board.cardTextColor, .blue)
        XCTAssertNil(list.cardTextColor)
        XCTAssertEqual(try JSONDecoder().decode(BoardAppearance.self, from: JSONEncoder().encode(board)), board)
        XCTAssertEqual(try JSONDecoder().decode(ItemAppearance.self, from: JSONEncoder().encode(list)), list)
        let original = KanbanList(id: 8, title: "Ideas", cards: [])
        var styled = original
        styled.appearance = list
        let inherited = BoardAppearance.inheritingLists([styled]) [0]
        XCTAssertNil(inherited.appearance?.addItemTextColor)
        XCTAssertEqual(inherited.cards, original.cards)
        XCTAssertEqual(styled.appearance?.addItemTextColor, .charcoal)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSameDayScheduleUsesTimesOnlyWithoutChangingStoredDates
    /// @brief      Verify that same Day Schedule Uses Times Only Without Changing Stored Dates
    /// @details    Exercises `card.scheduleBadges`, `badges.map`, `CardDateKind.time.label`. Checks
    ///             `XCTAssertEqual(badges.map(\.title), ["Start", "Finish"])`;
    ///             `XCTAssertEqual(badges.map(\.systemImage), ["clock", "checkmark.circle"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testSameDayScheduleUsesTimesOnlyWithoutChangingStoredDates() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23, minute: 24)))
        let finish = try XCTUnwrap(calendar.date(byAdding: .minute, value: 21, to: start))
        var card = KanbanCard(
            id: 0, word: "Task", listTitle: "Renamed day", startDate: start, dueDate: finish,
            showsDueDateInList: true, startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
        let original = card
        let badges = card.scheduleBadges(on: start, calendar: calendar)
        XCTAssertEqual(badges.map(\.title), ["Start", "Finish"])
        XCTAssertEqual(badges.map(\.systemImage), ["clock", "checkmark.circle"])
        XCTAssertEqual(badges.map(\.value), [CardDateKind.time.label(for: start), CardDateKind.time.label(for: finish)])
        XCTAssertEqual(card, original)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(card.scheduleBadges(on: tomorrow, calendar: calendar).map(\.title), ["Start date", "Due date"])
        XCTAssertEqual(
            card.scheduleBadges(on: nil, calendar: calendar).map(\.value), [card.dueDateLabel],
                            "Undated Library previews retain their existing date display")
        card.dueDate = tomorrow
        XCTAssertEqual(card.scheduleBadges(on: start, calendar: calendar).map(\.title), ["Start date", "Due date"])
        card.dueDate = finish
        card.startDateKind = .date
        XCTAssertEqual(card.scheduleBadges(on: start, calendar: calendar).map(\.title), ["Start date", "Due date"])
        card.startDate = nil
        XCTAssertEqual(card.scheduleBadges(on: start, calendar: calendar).map(\.title), ["Finish"])
        card.showsDueDateInList = false
        XCTAssertTrue(card.scheduleBadges(on: start, calendar: calendar).isEmpty)
        XCTAssertTrue(
            card.usesTimeOnlySchedule(on: start, calendar: calendar),
                            "Detail context must not depend on list badge visibility")
        XCTAssertFalse(card.usesTimeOnlySchedule(on: nil, calendar: calendar))
        XCTAssertFalse(card.usesTimeOnlySchedule(on: tomorrow, calendar: calendar))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekSelectorPreservesStoredContentAndActiveWeek
    /// @brief      Verify that week Selector Preserves Stored Content And Active Week
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `PlanningWeekSelector.choices`. Checks
    ///             `XCTAssertEqual(choices.count, 17)`; `XCTAssertEqual(Set(choices.map(\.startKey)).count,
    ///             choices.count)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWeekSelectorPreservesStoredContentAndActiveWeek() throws
    {

        for firstWeekday in [1, 2]
        {

            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday
            let date = try XCTUnwrap(PlanningDate.date("2026-10-13"))
            var current = DatedPlanningWeek.make(for: date, calendar: calendar)
            current.collection.lists[0].cards = [
                KanbanCard(id: 987, word: "Keep this writing", listTitle: current.collection.lists[0].title)
            ]
            let document = PlanningCalendarDocument(
                currentWeekKey: current.startKey, firstWeekday: firstWeekday, weeks: [current])
            let original = document
            let choices = PlanningWeekSelector.choices(document: document, referenceDate: date)
            XCTAssertEqual(choices.count, 17)
            XCTAssertEqual(Set(choices.map(\.startKey)).count, choices.count)
            XCTAssertEqual(choices.first
                {
                    $0.startKey == current.startKey
                }, current)
            XCTAssertTrue(
                choices.allSatisfy
                {

                    PlanningDate.weekKey(PlanningDate.date($0.startKey)!, calendar: calendar) == $0.startKey
                })
            let future = try XCTUnwrap(calendar.date(byAdding: .month, value: 6, to: date))
            let futureChoices = PlanningWeekSelector.choices(document: document, referenceDate: future)
            XCTAssertTrue(futureChoices.contains
                {
                    $0.startKey == PlanningDate.weekKey(future, calendar: calendar)
                })
            XCTAssertEqual(document, original)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDueDateVisibilityRequiresAStoredDateAndPreservesCardPreference
    /// @brief      Verify that due Date Visibility Requires A Stored Date And Preserves Card Preference
    /// @details    Exercises `restored.replacingLocation`, `ListCopying.copy`, `JSONSerialization.jsonObject`. Checks
    ///             `XCTAssertTrue(card.hasDueDate, "Date presence must not depend on the sample card ID")`;
    ///             `XCTAssertEqual(card.listDueDateLabel, card.dueDateLabel)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDueDateVisibilityRequiresAStoredDateAndPreservesCardPreference() throws
    {

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var card = KanbanCard(id: 1, word: "Due date", listTitle: "Monday", dueDate: date, showsDueDateInList: true)
        XCTAssertTrue(card.hasDueDate, "Date presence must not depend on the sample card ID")
        XCTAssertEqual(card.listDueDateLabel, card.dueDateLabel)
        XCTAssertNotEqual(card.listDueDateLabel, "Today")
        card.showsDueDateInList = false
        XCTAssertNil(card.listDueDateLabel)
        XCTAssertEqual(card.dueDate, date, "Hiding the badge must retain the due date")
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertFalse(restored.showsDueDateInList)
        XCTAssertEqual(restored.dueDate, date)
        XCTAssertFalse(restored.replacingLocation(id: 50, listTitle: "Friday").showsDueDateInList)
        let source = KanbanList(id: 0, title: "Monday", cards: [restored])
        XCTAssertFalse(ListCopying.copy(source, into: [source], crossBoard: true).cards[0].showsDueDateInList)
        card.dueDate = nil
        card.showsDueDateInList = true
        XCTAssertFalse(card.hasDueDate)
        XCTAssertNil(card.listDueDateLabel)
        XCTAssertEqual(card.dueDateLabel, "")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        legacy.removeValue(forKey: "showsDueDateInList")
        let decodedLegacy = try JSONDecoder().decode(
            KanbanCard.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decodedLegacy.showsDueDateInList)
        XCTAssertEqual(decodedLegacy.listDueDateLabel, restored.dueDateLabel)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryBrowseFiltersScopeSearchAndExcludeArchivedCollections
    /// @brief      Verify that library Browse Filters Scope Search And Exclude Archived Collections
    /// @details    Exercises `collections.filter`, `LibraryBrowseFilter.all.includes`,
    ///             `LibraryBrowseFilter.lists.includes`. Checks `XCTAssertEqual(collections.filter {
    ///             LibraryBrowseFilter.all.includes($0) }.map(\.id), [list.id, board.id])`;
    ///             `XCTAssertEqual(collections.filter { LibraryBrowseFilter.lists.includes($0) }.map(\.id),
    ///             [list.id])`.
    ///
    /// @return     (Void) no return value
    ///
    func testLibraryBrowseFiltersScopeSearchAndExcludeArchivedCollections()
    {

        var list = PersonalCollection(title: "Reading", kind: .list)
        var board = PersonalCollection(title: "Projects", kind: .board)
        var archived = PersonalCollection(title: "Old", kind: .list)
        archived.isArchived = true
        list.lists[0].cards = [KanbanCard(id: 1, word: "Garden reference", listTitle: "Reading")]
        board.lists[0].cards = [KanbanCard(id: 1, word: "Garden project", listTitle: "Ideas")]
        let collections = [list, board, archived]
        XCTAssertEqual(collections.filter
            {
                LibraryBrowseFilter.all.includes($0)
            } .map(\.id), [list.id, board.id])
        XCTAssertEqual(collections.filter
            {
                LibraryBrowseFilter.lists.includes($0)
            } .map(\.id), [list.id])
        XCTAssertEqual(collections.filter
            {
                LibraryBrowseFilter.boards.includes($0)
            } .map(\.id), [board.id])
        for (filter, expected) in [(LibraryBrowseFilter.lists, list.id), (.boards, board.id)]
        {

            let results = LibrarySearchIndex.results(
                query: "garden", collections: collections.filter
                {
                    filter.includes($0)
                },
                labels: LabelLibraryStore.load())
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.ownerID, expected)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testOverflowReadingPreferenceDefaultsOnAndPersistsWithoutProfile
    /// @brief      Verify that overflow Reading Preference Defaults On And Persists Without Profile
    /// @details    Exercises `PlanPreferencesStore.load`, `PlanPreferencesStore.save`, `LocalProfileStore.load`.
    ///             Checks `XCTAssertTrue(try JSONDecoder().decode(LocalProfilePreferences.self, from:
    ///             Data("{}".utf8)).scrollsOverflowingTitles)`; `XCTAssertTrue(PlanPreferencesStore.load(from:
    ///             defaults).scrollsOverflowingTitles)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testOverflowReadingPreferenceDefaultsOnAndPersistsWithoutProfile() throws
    {

        let suite = "OverflowPreferenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        XCTAssertTrue(
            try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8)).scrollsOverflowingTitles)
        XCTAssertTrue(PlanPreferencesStore.load(from: defaults).scrollsOverflowingTitles)
        var preferences = LocalProfilePreferences()
        preferences.scrollsOverflowingTitles = false
        preferences.todayFocusIncludesImportant = true
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testIndependentBoardAppearancePersistsAndAcceptsLegacyCollections
    /// @brief      Verify that independent Board Appearance Persists And Accepts Legacy Collections
    /// @details    Exercises `BoardAppearance.decodeWeek`, `PersonalCollectionStore.saveChecked`,
    ///             `PersonalCollectionStore.load`. Checks `XCTAssertEqual(try
    ///             BoardAppearance.decodeWeek(XCTUnwrap(defaults.data(forKey: BoardAppearance.weekStorageKey))),
    ///             week)`; `XCTAssertEqual(try BoardAppearance.decodeWeek(Data()), BoardAppearance())`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testIndependentBoardAppearancePersistsAndAcceptsLegacyCollections() throws
    {

        let suite = "PlenactTests.BoardAppearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let week = BoardAppearance(bannerBackground: .blue, listBackground: .orange, cardBackground: .green)
        defaults.set(try JSONEncoder().encode(week), forKey: BoardAppearance.weekStorageKey)
        XCTAssertEqual(
            try BoardAppearance.decodeWeek(XCTUnwrap(defaults.data(forKey: BoardAppearance.weekStorageKey))), week)
        XCTAssertEqual(try BoardAppearance.decodeWeek(Data()), BoardAppearance())
        XCTAssertThrowsError(try BoardAppearance.decodeWeek(Data("invalid".utf8)))
        XCTAssertThrowsError(try BoardAppearance.decodeWeek(Data(#"{"bannerBackground":"invalid"}"#.utf8)))
        var first = PersonalCollection(title: "First", kind: .board)
        first.boardAppearance = BoardAppearance(
            bannerBackground: .purple, listBackground: .red, cardBackground: .orange)
        var second = PersonalCollection(title: "Second", kind: .board)
        second.boardAppearance = BoardAppearance(bannerBackground: .green, listBackground: .blue, cardBackground: .red)
        second.isArchived = true
        try PersonalCollectionStore.saveChecked([first, second], to: defaults)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [first, second])
        XCTAssertEqual(
            try BoardAppearance.decodeWeek(XCTUnwrap(defaults.data(forKey: BoardAppearance.weekStorageKey))), week)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        legacy.removeValue(forKey: "boardAppearance")
        let reopened = try JSONDecoder().decode(
            PersonalCollection.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(reopened.boardAppearance)
        XCTAssertEqual(reopened.lists, first.lists)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEditedListMetadataPersistsInIndependentLocalStores
    /// @brief      Verify that edited List Metadata Persists In Independent Local Stores
    /// @details    Exercises `week.edit`, `KanbanBoardPersistence.saveListsChecked`,
    ///             `KanbanBoardPersistence.loadListsInBackground`. Checks `XCTAssertEqual(restoredWeek, [week])`;
    ///             `XCTAssertEqual(restoredCollection, collection)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testEditedListMetadataPersistsInIndependentLocalStores() async throws
    {


        let suite = "PlenactTests.ListMetadata.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

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


    ///
    /// @fcn        PlenactBoardDocumentTests.testKeyboardRichFontsPersistAndFormattingSupportsUndoRedo
    /// @brief      Verify that keyboard Rich Fonts Persist And Formatting Supports Undo Redo
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual((attributes[.font] as? UIFont)?.pointSize,
    ///             24)`; `XCTAssertEqual(attributes[NSAttributedString.Key("PlenactFontName")] as? String,
    ///             "Georgia")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testKeyboardRichFontsPersistAndFormattingSupportsUndoRedo() throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController();
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        var stored = "Keep all these words"
        let editor = RichTextEditor(placeholder: "Body", text: Binding(get:
                {
                    stored
                }, set:
                {
                    stored = $0
                }))
        let coordinator = editor.makeCoordinator()
        let text = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        controller.view.addSubview(text)
        text.attributedText = PlanRichText.attributed(stored)
        coordinator.view = text
        text.becomeFirstResponder()
        let undo = try XCTUnwrap(text.undoManager)
        undo.removeAllActions();
        undo.groupsByEvent = false
        text.selectedRange = NSRange(location: 0, length: text.textStorage.length)
        undo.beginUndoGrouping()
        coordinator.font(name: "Georgia", size: 24)
        coordinator.toggle(.traitBold)
        coordinator.color("Blue")
        undo.endUndoGrouping()
        let formatted = stored
        let attributes = PlanRichText.attributed(stored).attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual((attributes[.font] as? UIFont)?.pointSize, 24)
        XCTAssertEqual(attributes[NSAttributedString.Key("PlenactFontName")] as? String, "Georgia")
        XCTAssertEqual(PlanRichText.plain(stored), "Keep all these words")
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(stored, "Keep all these words")
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(PlanRichText.runs(stored), PlanRichText.runs(formatted))
        let legacy = Data(#"[{"text":"Old writing","bold":true,"italic":false}]"#.utf8)
        XCTAssertEqual(PlanRichText.plain(PlanRichText.prefix + legacy.base64EncodedString()), "Old writing")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewItemsUseBlankOrEnteredSubtitleAndPersistIt
    /// @brief      Verify that new Items Use Blank Or Entered Subtitle And Persist It
    /// @details    Exercises `list.makeItem`. Checks `XCTAssertEqual(blank.subtitleOverride, "")`;
    ///             `XCTAssertEqual(blank.subtitle, "")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testNewItemsUseBlankOrEnteredSubtitleAndPersistIt() throws
    {

        let list = KanbanList(id: 1, title: "Saturday", cards: [])
        let blank = list.makeItem(id: 1, title: "New task")
        XCTAssertEqual(blank.subtitleOverride, "")
        XCTAssertEqual(blank.subtitle, "")
        let entered = list.makeItem(id: 2, title: "New task", description: "Details", subtitle: "  A useful subtitle  ")
        XCTAssertEqual(entered.subtitle, "A useful subtitle")
        XCTAssertEqual(entered.descriptionOverride, "Details")
        for card in [blank, entered]
        {

            let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
            XCTAssertEqual(decoded.subtitle, card.subtitle)
            XCTAssertEqual(decoded.subtitleOverride, card.subtitleOverride)
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
    func testPersonalListArchiveSaveFailureLeavesPriorSnapshotUntouched() throws
    {


        let suite = "Plenact.ListLifecycleTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let original = PersonalListExample.shopping.makeCollection(existingTitles: []
        ) /* Pre-operation value for preservation checks */

        try PersonalCollectionStore.saveChecked([original], to: defaults)

        let archived = try PersonalCollectionStore.archiveCollection(
            id: original.id, in: [original], to: defaults) /* Archived value for restoration checks */

        XCTAssertFalse(archived[0].isActive)
        XCTAssertEqual(archived[0].lists, original.lists)

        var invalid = original /* Malformed fixture input */
        invalid.lists[0].cards[0].dueDate = Date(timeIntervalSinceReferenceDate: .infinity)

        XCTAssertThrowsError(try PersonalCollectionStore.archiveCollection(id: invalid.id, in: [invalid], to: defaults))
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), archived)
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
    func testCheckedWeekDeletionWaitsForEarlierWritesAndPreservesDiskOnFailure() throws
    {


        let suite = "Plenact.CheckedDeletionTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let prior = [
            KanbanList(
                id: 1, title: "Earlier edit",
                cards: [ /* Prior persisted value */
                    KanbanCard(id: 1, word: "Synthetic", listTitle: "Earlier edit", checklists: [])
                ])
        ]
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
    /// @fcn        PlenactBoardDocumentTests.testBackgroundWeekPersistenceKeepsArchivedListsAndAllowsEmptyWorkspace()
    /// @brief      Persist retained archives and an intentionally empty Week
    /// @details    Uses an isolated suite and awaits the ordered persistence queue after each save
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap failures
    ///
    @MainActor
    func testBackgroundWeekPersistenceKeepsArchivedListsAndAllowsEmptyWorkspace() async throws
    {


        let suite = "Plenact.WeekArchiveTests.\(UUID().uuidString)"   /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        var archived = SampleData.lists[1] /* Archived value for restoration checks */

        archived.isArchived = true

        let snapshot = [SampleData.lists[0], archived] /* Persisted snapshot under verification */

        KanbanBoardPersistence.enqueueSave(snapshot, suiteName: suite)

        let restored = await KanbanBoardPersistence.loadListsInBackground(
            suiteName: suite) /* Restored value under verification */

        XCTAssertEqual(restored, snapshot)

        KanbanBoardPersistence.enqueueSave([], suiteName: suite)

        let emptyWeek = await KanbanBoardPersistence.loadListsInBackground(
            suiteName: suite) /* Empty weekly-board fixture */

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
    func testListArchiveBindingsPreserveCardsAndRestoreAtEnd() throws
    {


        let original = SampleData.lists[0]              /* Pre-operation value for preservation checks */
        var snapshot = [original, SampleData.lists[1]]  /* Persisted snapshot under verification       */
        let board = Binding(
            get:
            {
                snapshot
            }, set:
            {
                snapshot = $0
            })                   /* Board state under verification        */
        var archived = original  /* Archived value for restoration checks */

        archived.isArchived = true
        board.archivedLists.wrappedValue.append(archived)
        board.activeLists.wrappedValue.removeAll
        {
            $0.id == original.id
        }


        XCTAssertEqual(board.activeLists.wrappedValue.map(\.id), [1])
        XCTAssertEqual(board.archivedLists.wrappedValue, [archived])

        snapshot = try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(board.archivedLists.wrappedValue, [archived])

        var restored = try XCTUnwrap(board.archivedLists.wrappedValue.first) /* Restored value under verification */

        restored.isArchived = false
        board.activeLists.wrappedValue.append(restored)
        board.archivedLists.wrappedValue.removeAll
        {
            $0.id == original.id
        }


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
    func testWholeWeekArchiveRestoresAsSeparateUniquelyNamedBoard() throws
    {


        var archivedList = SampleData.lists[1] /* List containing archived records */

        archivedList.isArchived = true

        var list = SampleData.lists[0] /* List state under verification */

        list.archiveCard(id: list.cards[0].id)

        let sourceLists = [list, archivedList]               /* Source List snapshots                           */
        let savedIDs: Set<Int> = [list.archivedCards[0].id]  /* Card IDs expected in the archived-week snapshot */
        var board = PersonalCollection.archivedWeekBoard(
            lists: sourceLists, savedCardIDs: savedIDs)  /* Board state under verification */
        let boardID = board.id                           /* Stable Board identifier        */

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
    /// @fcn        PlenactBoardDocumentTests.testArchivedPersonalBoardPersistsAndRestoresWithoutRenamingItsLists()
    /// @brief      Persist archive state and restore a personal Board with its lists intact
    /// @details    Resolves a Board-title collision without changing contained lists or saved-card
    ///             IDs
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Checked saves, JSON conversion, or Board unwrap failures
    ///
    func testArchivedPersonalBoardPersistsAndRestoresWithoutRenamingItsLists() throws
    {


        let suite = "Plenact.BoardArchiveTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        var board = PersonalCollection(
            title: "Project", kind: .board, icon: .project) /* Board state under verification */

        board.isArchived = true
        board.lists[0].cards = [KanbanCard(id: 77, word: "Task", listTitle: board.lists[0].title)]
        board.lists[1].isArchived = true
        board.savedCardIDs = [77]
        try PersonalCollectionStore.saveChecked([board], to: defaults)

        var restored = try XCTUnwrap(
            PersonalCollectionStore.load(from: defaults).first) /* Restored value under verification */

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
    func testLegacyPersonalBoardDefaultsToActiveAndArchivedListsStayOutOfSearch() throws
    {


        let original = PersonalCollection(
            title: "Project", kind: .board) /* Pre-operation value for preservation checks */
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]) /* Serialized JSON object                      */

        object.removeValue(forKey: "isArchived")

        var decoded = try JSONDecoder().decode(
            PersonalCollection.self, from: JSONSerialization.data(withJSONObject: object)) /* Decoded legacy personal collection */

        XCTAssertTrue(decoded.isActive)
        decoded.lists[0].cards = [KanbanCard(id: 500, word: "Hidden activity", listTitle: decoded.lists[0].title)]
        decoded.lists[0].isArchived = true
        XCTAssertFalse(decoded.matches("Hidden activity"))
        XCTAssertEqual(decoded.cardCount, 0)

        let document = PlenactBoardDocument(
            lists: decoded.lists, labelLibrary: .starter) /* Board document under test */

        XCTAssertEqual(
            document.validationMessage, "Archived lists are stored locally and cannot be published to the shared Board."
        )
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
    func testLegacyListsLoadWithEmptyArchiveAndKeepExistingJSONShape() throws
    {


        let data = Data(
                        "{\"id\":1,\"title\":\"Monday\",\"cards\":[]}".utf8) /* JSON fixture bytes for the compatibility check */
        let list = try JSONDecoder().decode(
            KanbanList.self, from: data) /* Decoded List fixture                           */

        XCTAssertTrue(list.archivedCards.isEmpty)

        let encoded = try JSONEncoder().encode(list) /* Encoded model payload  */
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]) /* Serialized JSON object */

        XCTAssertEqual(Set(object.keys), ["id", "title", "cards"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testArchivedCardsStayOutOfSearchAndReserveTheirIDs()
    /// @brief      Exclude archived cards from active search without reusing their identities
    /// @details    Includes retained cards in ID allocation and rejects archives in shared-demo
    ///             documents
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testArchivedCardsStayOutOfSearchAndReserveTheirIDs()
    {


        let archived = KanbanCard(
            id: 900, word: "Archived task", listTitle: "Monday", isTitleChecked: true)  /* Archived value for restoration checks */
        let list = KanbanList(                                                          /* List state under verification         */
            id: 1, title: "Monday",
            cards: [KanbanCard(id: 1, word: "Active task", listTitle: "Monday")],
            archivedCards: [archived]
        )

        XCTAssertTrue(
            TodaySearchIndex.results(query: "Archived task", scope: .all, lists: [list], library: .starter).isEmpty)
        XCTAssertEqual(([list].flatMap
                {
                    $0.allCards.map(\.id)
                } .max() ?? -1) + 1, 901)

        let document = PlenactBoardDocument(lists: [list], labelLibrary: .starter) /* Board document under test */

        XCTAssertEqual(
            document.validationMessage, "Archived cards are stored locally and cannot be published to the shared Board."
        )
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
    func testIndividualArchiveAcceptsIncompleteCardsAndPreservesContent() throws
    {


        var incomplete = SampleData.lists[0].cards[0] /* Incomplete checklist-item fixture */

        incomplete.isTitleChecked = false

        XCTAssertFalse(incomplete.isTitleChecked)

        var complete = SampleData.lists[0].cards[1] /* Completed state under verification */

        complete.isTitleChecked = true

        let divider = KanbanCard(
            id: 800, word: "Divider", listTitle: "Monday", isDivider: true) /* Section-divider fixture       */
        var list = KanbanList(
            id: 1, title: "Monday", cards: [incomplete, complete, divider]) /* List state under verification */

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
    /// @fcn        PlenactBoardDocumentTests.testPersonalListRenamePreservesArchivedCards()
    /// @brief      Update archived cards' list-title references when renaming a personal list
    /// @details    Checks retained content and the resulting collection's JSON round trip
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Collection encoding or decoding errors
    ///
    func testPersonalListRenamePreservesArchivedCards() throws
    {


        var collection = PersonalCollection(title: "Original", kind: .list) /* Collection state under verification   */
        let archived = KanbanCard(
            id: 42, word: "Archived", listTitle: "Original", isTitleChecked: true) /* Archived value for restoration checks */
        collection.lists[0].archivedCards = [archived]
        collection.rename(to: "Renamed")

        var expected = archived /* Expected result for comparison */

        expected.listTitle = "Renamed"

        XCTAssertEqual(collection.lists[0].archivedCards, [expected])

        let restored = try JSONDecoder().decode(
            PersonalCollection.self, from: JSONEncoder().encode(collection)) /* Restored value under verification */

        XCTAssertEqual(restored, collection)
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
    func testPersonalCollectionPersistencePreservesOrderAndLeavesWeekUntouched() throws
    {


        let suite = "Plenact.PersonalCollectionTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))        /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let weekSnapshot = try JSONEncoder().encode(SampleData.lists) /* Encoded weekly-board snapshot */

        defaults.set(weekSnapshot, forKey: "Plenact.Board.v1")

        var shopping = PersonalCollection(
            title: "Shopping", kind: .list, icon: .shopping, color: .coral) /* Shopping-list example */
        shopping.lists[0].cards = [KanbanCard(id: 0, word: "Eggs", listTitle: "Shopping", checklists: [])]
        shopping.savedCardIDs = [0]

        let project = PersonalCollection(
            title: "New Project Notes", kind: .board, icon: .project) /* Project-list example */

        PersonalCollectionStore.save([project, shopping], to: defaults)

        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [project, shopping])
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), weekSnapshot)
        XCTAssertEqual(shopping.lists.count, 1)
        XCTAssertEqual(project.lists.map(\.title), ["Ideas", "In progress", "Done"])
        XCTAssertEqual(shopping.cardCount, 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDocumentRejectsEmptyCardTitle()
    /// @brief      Reject a blank title before it reaches the shared API
    /// @details    Ensures local snapshot validation matches the server's required card-title
    ///             constraint
    ///
    /// @return     (Void) succeeds when an empty card title returns a validation message
    ///
    func testDocumentRejectsEmptyCardTitle()
    {


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

}
