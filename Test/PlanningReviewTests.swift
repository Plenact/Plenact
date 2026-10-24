// --------------------------------------------------------------------------------------------------
// @file       PlanningReviewTests.swift
// @brief      Planning Review regression tests
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
/// PlanningReview regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testMainLibraryListsUseTheSameFocusedDestinationAsToday
    /// @brief      Verify that main Library Lists Use The Same Focused Destination As Today
    /// @details    Exercises `DefaultListTutorial.makeStarter`. Checks
    ///             `XCTAssertEqual(collection.preferredFocusedListID, collection.lists[0].id)`;
    ///             `XCTAssertEqual(WorkspaceListReference(ownerID: collection.id, listID:
    ///             collection.preferredFocusedListID!).listID, collection.lists[0].id)`.
    ///
    /// @return     (Void) no return value
    ///
    func testMainLibraryListsUseTheSameFocusedDestinationAsToday()
    {

        for title in ["On the Table", "In the Queue", "Scheduled"]
        {

            let collection = DefaultListTutorial.makeStarter(title: title)
            XCTAssertEqual(collection.preferredFocusedListID, collection.lists[0].id)
            XCTAssertEqual(
                WorkspaceListReference(ownerID: collection.id, listID: collection.preferredFocusedListID!).listID,
                collection.lists[0].id)
        }

        XCTAssertNil(PersonalCollection(title: "Custom", kind: .list).preferredFocusedListID)
        XCTAssertNil(PersonalCollection(title: "On the Table", kind: .board).preferredFocusedListID)
        var archived = DefaultListTutorial.makeStarter(title: "On the Table")
        archived.lists[0].isArchived = true
        XCTAssertNil(archived.preferredFocusedListID)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayFocusPreferenceDefaultsAndPersistsWithoutChangingOlderSettings
    /// @brief      Verify that today Focus Preference Defaults And Persists Without Changing Older Settings
    /// @details    Checks `XCTAssertEqual(restored.todayFocusItemCount, 4)`; `XCTAssertEqual(restored.defaultListID,
    ///             3)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testTodayFocusPreferenceDefaultsAndPersistsWithoutChangingOlderSettings() throws
    {

        let legacy = Data(#"{"defaultListID":3,"usesReducedContent":true,"showsDueDatesOnNewCards":false}"#.utf8)
        let restored = try JSONDecoder().decode(LocalProfilePreferences.self, from: legacy)
        XCTAssertEqual(restored.todayFocusItemCount, 4)
        XCTAssertEqual(restored.defaultListID, 3)
        XCTAssertTrue(restored.usesReducedContent)
        XCTAssertFalse(restored.showsDueDatesOnNewCards)
        for count in 0 ... 12
        {

            var preferences = restored
            preferences.todayFocusItemCount = count
            let decoded = try JSONDecoder().decode(
                LocalProfilePreferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(decoded, preferences)
        }

        XCTAssertEqual(LocalProfilePreferences(todayFocusItemCount: -1).todayFocusItemCount, 4)
        XCTAssertEqual(LocalProfilePreferences(todayFocusItemCount: 500).todayFocusItemCount, 4)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusFiltersCombineAsUnionAndKeepAllMatchesInCanonicalOrder
    /// @brief      Verify that focus Filters Combine As Union And Keep All Matches In Canonical Order
    /// @details    Exercises `(0..<7).map`, `cards.insert`, `entries().map`. Checks
    ///             `XCTAssertEqual(entries().map(\.id), [1, 4])`; `XCTAssertEqual(entries().first?.heading,
    ///             "Important to me")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusFiltersCombineAsUnionAndKeepAllMatchesInCanonicalOrder() throws
    {

        var cards = (0 ..< 7).map
        {
            KanbanCard(id: $0, word: "Item \($0)", listTitle: "Today", checklists: [])
        }

        cards[2].isTitleChecked = true
        cards.insert(
            KanbanCard(id: 90, word: "--- Important to me", listTitle: "Today", isDivider: true, checklists: []), at: 1)
        let original = cards
        let important: Set<Int> = [1, 2, 4, 90]
        let saved: Set<Int> = [3, 4]
        var preferences = LocalProfilePreferences(
            todayFocusItemCount: 0, todayFocusGroupsBySection: true,
            todayFocusIncludesImportant: true)


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusFiltersCombineAsUnionAndKeepAllMatchesInCanonicalOrder.entries
        /// @brief      Prepare entries for the enclosing regression test
        /// @details    Supplies the local fixture for focus Filters Combine As Union And Keep All Matches In
        ///             Canonical Order. Uses `preferences.todayFocusEntries`.
        ///
        /// @return     ([TodayFocusEntry]) resulting values in the ordering described above
        ///
        func entries() -> [TodayFocusEntry]
        {

            preferences.todayFocusEntries(in: cards, importantCardIDs: important, bookmarkedCardIDs: saved)
        }

        XCTAssertEqual(entries().map(\.id), [1, 4])
        XCTAssertEqual(entries().first?.heading, "Important to me")
        preferences.todayFocusIncludesBookmarked = true
        XCTAssertEqual(entries().map(\.id), [1, 3, 4])
        preferences.todayFocusItemCount = 2
        XCTAssertEqual(entries().map(\.id), [1, 3, 4])
        preferences.todayFocusItemCount = 0
        preferences.todayFocusHidesCompleted = false
        XCTAssertEqual(entries().map(\.id), [1, 2, 3, 4])
        preferences.todayFocusIncludesImportant = false
        XCTAssertEqual(entries().map(\.id), [3, 4])
        preferences.todayFocusIncludesBookmarked = false
        XCTAssertEqual(entries().count, 7)
        preferences.todayFocusIncludesImportant = true
        XCTAssertTrue(preferences.todayFocusEntries(in: cards).isEmpty)
        XCTAssertEqual(cards, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusUpNextSkipsEndedSlotsAndKeepsCurrentUpcomingAndExplicitChoices
    /// @brief      Verify that focus Up Next Skips Ended Slots And Keeps Current Upcoming And Explicit Choices
    /// @details    Exercises `(0..<8).map`, `preferences.todayFocusEntries(in: cards, on: now, calendar:
    ///             calendar).map`, `preferences.todayFocusEntries`. Checks
    ///             `XCTAssertEqual(preferences.todayFocusEntries(in: cards, on: now, calendar: calendar).map(\.id),
    ///             [1, 2, 4, 5])`; `XCTAssertEqual(preferences.todayFocusEntries(in: cards, on: time(20), calendar:
    ///             calendar).map(\.id), [5])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusUpNextSkipsEndedSlotsAndKeepsCurrentUpcomingAndExplicitChoices() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusUpNextSkipsEndedSlotsAndKeepsCurrentUpcomingAndExplicitChoices.time
        /// @brief      Prepare time for the enclosing regression test
        /// @details    Supplies the local fixture for focus Up Next Skips Ended Slots And Keeps Current Upcoming And
        ///             Explicit Choices. Uses `calendar.date`.
        ///
        /// @param[in]  hour  Hour-of-day component used by the fixture
        /// @param[in]  day   Calendar day represented by the result
        ///
        /// @return     (Date) result described by this operation's contract
        ///
        func time(_ hour: Int, day: Int = 19) -> Date
        {

            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }

        var cards = (0 ..< 8).map
        {
            KanbanCard(id: $0, word: "Item \($0)", listTitle: "Today", checklists: [])
        }

        cards[0].startDate = time(4);
        cards[0].dueDate = time(5)
        cards[1].startDate = time(7);
        cards[1].dueDate = time(17)
        cards[2].startDate = time(18);
        cards[2].dueDate = time(19)
        cards[3].startDate = time(9, day: 1);
        cards[3].dueDate = time(10, day: 1)
        cards[4].startDate = time(15, day: 1);
        cards[4].startDateKind = .time
        cards[5].dueDate = time(0);
        cards[5].dueDateKind = .date
        cards[6].startDate = time(8, day: 20)
        for index in [0, 1, 2, 3, 6]
        {

            cards[index].startDateKind = .dateAndTime;
            cards[index].dueDateKind = .dateAndTime
        }

        var preferences = LocalProfilePreferences(
            todayFocusItemCount: 0, todayFocusIncludesUpNext: true, keepsDayListsInTimeOrder: false)
        let now = time(12)
        XCTAssertEqual(preferences.todayFocusEntries(in: cards, on: now, calendar: calendar).map(\.id), [1, 2, 4, 5])
        preferences.todayFocusIncludesImportant = true
        preferences.todayFocusIncludesBookmarked = true
        XCTAssertEqual(
            preferences.todayFocusEntries(
                in: cards, on: now, calendar: calendar,
                importantCardIDs: [0], bookmarkedCardIDs: [7]
            ).map(\.id), [0, 1, 2, 4, 5, 7])
        preferences.todayFocusIncludesImportant = false;
        preferences.todayFocusIncludesBookmarked = false
        XCTAssertEqual(preferences.todayFocusEntries(in: cards, on: time(20), calendar: calendar).map(\.id), [5])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusShapePreferencesKeepLegacyDefaultsAndPersistWithoutProfile
    /// @brief      Verify that focus Shape Preferences Keep Legacy Defaults And Persist Without Profile
    /// @details    Exercises `PlanPreferencesStore.save`, `PlanPreferencesStore.load`, `LocalProfileStore.load`.
    ///             Checks `XCTAssertEqual(legacy.todayFocusOrder, .dayList)`;
    ///             `XCTAssertFalse(legacy.todayFocusGroupsBySection)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusShapePreferencesKeepLegacyDefaultsAndPersistWithoutProfile() throws
    {

        let legacy = try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.todayFocusOrder, .dayList)
        XCTAssertFalse(legacy.todayFocusGroupsBySection)
        XCTAssertTrue(legacy.todayFocusHidesCompleted)
        let suite = "FocusShape." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let preferences = LocalProfilePreferences(
            todayFocusItemCount: 0,
            todayFocusOrder: .chronological, todayFocusGroupsBySection: true, todayFocusHidesCompleted: false)
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayFocusRowCapacityNeverTruncatesOrderedUnfinishedMatches
    /// @brief      Verify that today Focus Row Capacity Never Truncates Ordered Unfinished Matches
    /// @details    Exercises `(0..<16).map`, `cards.insert`, `cards.filter`. Checks `XCTAssertEqual(open.count, 14)`;
    ///             `XCTAssertEqual(LocalProfilePreferences().todayFocusItems(in: cards).map(\.id), open.map(\.id))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testTodayFocusRowCapacityNeverTruncatesOrderedUnfinishedMatches() throws
    {

        var cards = (0 ..< 16).map
        {

            KanbanCard(
                id: $0, word: "Item \($0)", listTitle: "Monday", isTitleChecked: $0 == 0 || $0 == 5, checklists: [])
        }

        cards.insert(KanbanCard(id: 99, word: "Break", listTitle: "Monday", isDivider: true, checklists: []), at: 3)
        let original = cards
        let open = cards.filter
        {
            !$0.isSectionDivider && !$0.isTitleChecked
        }

        XCTAssertEqual(open.count, 14)
        XCTAssertEqual(LocalProfilePreferences().todayFocusItems(in: cards).map(\.id), open.map(\.id))
        for count in 1 ... 12
        {

            XCTAssertEqual(
                LocalProfilePreferences(todayFocusItemCount: count).todayFocusItems(in: cards).map(\.id), open.map(\.id)
            )
        }

        XCTAssertEqual(LocalProfilePreferences(todayFocusItemCount: 0).todayFocusItems(in: cards), open)
        XCTAssertTrue(LocalProfilePreferences().todayFocusItems(in: []).isEmpty)
        XCTAssertEqual(cards, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningDefaultWeekAppliesOnceAndCanBeDisabled
    /// @brief      Verify that planning Default Week Applies Once And Can Be Disabled
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `PlanningRoutineStore.newWeek`. Checks
    ///             `XCTAssertTrue(prepared.hasContent)`;
    ///             `XCTAssertTrue(prepared.collection.lists.flatMap(\.cards).allSatisfy { !$0.isTitleChecked &&
    ///             $0.comments.isEmpty })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningDefaultWeekAppliesOnceAndCanBeDisabled() throws
    {

        let name = "Plenact.RoutineDefaultTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let calendar = routineCalendar()
        let currentDate = try XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar))
        let nextDate = try XCTUnwrap(PlanningDate.date("2026-10-19", calendar: calendar))
        let current = DatedPlanningWeek.make(for: currentDate, calendar: calendar)
        var document = PlanningCalendarDocument(currentWeekKey: current.startKey, firstWeekday: 2, weeks: [current])
        let prepared = try PlanningRoutineStore.newWeek(for: nextDate, calendar: calendar, defaults: defaults)
        XCTAssertTrue(prepared.hasContent)
        XCTAssertTrue(
            prepared.collection.lists.flatMap(\.cards).allSatisfy
            {
                !$0.isTitleChecked && $0.comments.isEmpty
            })
        let rolled = document.rollForward(
            to: nextDate, currentLists: current.collection.lists, saved: [], calendar: calendar, newWeek: prepared)
        XCTAssertEqual(rolled, prepared)
        let repeated = document.rollForward(
            to: nextDate, currentLists: rolled.collection.lists, saved: [], calendar: calendar,
            newWeek: try PlanningRoutineStore.newWeek(for: nextDate, calendar: calendar, defaults: defaults))
        XCTAssertEqual(repeated, rolled)
        XCTAssertEqual(document.weeks.count, 2)
        let baseline = try PlanningRoutineStore.load(from: defaults)
        var disabled = baseline;
        disabled.defaultWeekID = nil
        try PlanningRoutineStore.save(disabled, baseline: baseline, to: defaults)
        XCTAssertFalse(
            try PlanningRoutineStore.newWeek(for: nextDate, calendar: calendar, defaults: defaults).hasContent)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPeriodicReviewCarriesObjectivesWithoutRewritingPriorCheckpoints
    /// @brief      Verify that periodic Review Carries Objectives Without Rewriting Prior Checkpoints
    /// @details    Exercises `PeriodicReviewStore.save`, `PeriodicReviewStore.load`, `PeriodicReviewStore.previous`.
    ///             Checks `XCTAssertEqual(next.startingObjectives, saved.objectives)`;
    ///             `XCTAssertEqual(next.objectives[0].id, saved.objectives[0].id)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPeriodicReviewCarriesObjectivesWithoutRewritingPriorCheckpoints() throws
    {

        let name = "PlenactTests.Periodic." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        var calendar = Calendar(identifier: .gregorian);
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!


        ///
        /// @fcn        PlenactBoardDocumentTests.testPeriodicReviewCarriesObjectivesWithoutRewritingPriorCheckpoints.date
        /// @brief      Prepare date for the enclosing regression test
        /// @details    Supplies the local fixture for periodic Review Carries Objectives Without Rewriting Prior
        ///             Checkpoints. Uses `PlanningDate.date`.
        ///
        /// @param[in]  key  Storage key or stable lookup key used by this operation
        ///
        /// @return     (Date) result described by this operation's contract
        ///
        func date(_ key: String) -> Date
        {
            PlanningDate.date(key, calendar: calendar)!
        }

        var prior = PeriodicReviewRecord(
            title: "First quarter", start: date("2026-01-01"), end: date("2026-03-31"), calendar: calendar)
        prior.objectives = [
            ReviewObjective(
                title: "Build a sustainable routine", progress: "Found a useful morning rhythm",
                nextStep: "Protect time to reflect")
        ]
        let saved = try PeriodicReviewStore.save(prior, replacing: nil, to: defaults)
        let document = try PeriodicReviewStore.load(from: defaults)
        let inherited = try XCTUnwrap(PeriodicReviewStore.previous(before: "2026-04-01", in: document))
        var next = PeriodicReviewRecord(
            title: "Second quarter", start: date("2026-04-01"), end: date("2026-06-30"), calendar: calendar,
            previous: inherited)
        XCTAssertEqual(next.startingObjectives, saved.objectives)
        XCTAssertEqual(next.objectives[0].id, saved.objectives[0].id)
        XCTAssertEqual(next.objectives[0].progress, "")
        next.objectives[0].status = .achieved;
        next.step = 2;
        next.completedAt = .now
        let nextSaved = try PeriodicReviewStore.save(next, replacing: nil, to: defaults)
        XCTAssertEqual(try PeriodicReviewStore.load(from: defaults).records[saved.id.uuidString], saved)
        XCTAssertEqual(try PeriodicReviewStore.load(from: defaults).records[next.id.uuidString], nextSaved)
        XCTAssertThrowsError(try PeriodicReviewStore.save(next, replacing: nil, to: defaults))
        XCTAssertNil(PeriodicReviewStore.previous(before: "2026-01-01", in: document))
        var invalid = nextSaved;
        invalid.title = " "
        let bytes = defaults.data(forKey: PeriodicReviewStore.key)
        XCTAssertThrowsError(try PeriodicReviewStore.save(invalid, replacing: nextSaved, to: defaults))
        XCTAssertEqual(defaults.data(forKey: PeriodicReviewStore.key), bytes)
        var weeks = WeeklyReviewStore.Document()
        let overlap = WeeklyReviewRecord(date: date("2026-03-30"), calendar: calendar)
        let outside = WeeklyReviewRecord(date: date("2026-07-12"), calendar: calendar)
        weeks.records[overlap.id] = overlap;
        weeks.records[outside.id] = outside
        XCTAssertEqual(next.weeks(in: weeks).map(\.id), [overlap.id])
        defaults.set(Data("corrupt".utf8), forKey: PeriodicReviewStore.key)
        XCTAssertThrowsError(try PeriodicReviewStore.load(from: defaults))
        XCTAssertEqual(defaults.data(forKey: PeriodicReviewStore.key), Data("corrupt".utf8))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReviewRhythmDefaultsTimingAndIndependentNotifications
    /// @brief      Verify that review Rhythm Defaults Timing And Independent Notifications
    /// @details    Exercises `ReviewRhythmStore.notificationRequests`, `ReviewRhythmStore.periodID`,
    ///             `preferences.normalized`. Checks `XCTAssertTrue(preferences.dailyInvitations)`;
    ///             `XCTAssertTrue(preferences.weeklyInvitations)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testReviewRhythmDefaultsTimingAndIndependentNotifications() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"));
        calendar.firstWeekday = 2


        ///
        /// @fcn        PlenactBoardDocumentTests.testReviewRhythmDefaultsTimingAndIndependentNotifications.date
        /// @brief      Prepare date for the enclosing regression test
        /// @details    Supplies the local fixture for review Rhythm Defaults Timing And Independent Notifications.
        ///             Uses `calendar.date`.
        ///
        /// @param[in]  day     Calendar day represented by the result
        /// @param[in]  hour    Hour-of-day component used by the fixture
        /// @param[in]  minute  Minute-of-hour component used by the fixture
        ///
        /// @return     (Date) result described by this operation's contract
        ///
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date
        {

            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }

        var preferences = ReviewRhythmPreferences()
        XCTAssertTrue(preferences.dailyInvitations);
        XCTAssertTrue(preferences.weeklyInvitations)
        XCTAssertFalse(preferences.dailyNotifications);
        XCTAssertFalse(preferences.weeklyNotifications)
        XCTAssertTrue(ReviewRhythmStore.notificationRequests(preferences).isEmpty)


        ///
        /// @fcn        PlenactBoardDocumentTests.testReviewRhythmDefaultsTimingAndIndependentNotifications.due
        /// @brief      Prepare due for the enclosing regression test
        /// @details    Supplies the local fixture for review Rhythm Defaults Timing And Independent Notifications.
        ///             Uses `ReviewRhythmStore.isDue`.
        ///
        /// @param[in]  kind       Date, review, or collection kind selecting this operation's behavior
        /// @param[in]  now        Reference time used instead of an implicit clock read
        /// @param[in]  completed  Whether the represented review period is already complete
        /// @param[in]  deferred   Optional deferral deadline used by the review timing fixture
        ///
        /// @return     (Bool) result of the validation, lookup, or checked operation described above
        ///
        func due(_ kind: ReviewRhythmKind, _ now: Date, completed: Bool = false, deferred: Date? = nil) -> Bool
        {

            ReviewRhythmStore.isDue(
                kind, now: now, preferences: preferences, calendar: calendar, completed: completed,
                deferredUntil: deferred)
        }

        XCTAssertFalse(due(.daily, date(19, 20, 29)))
        XCTAssertTrue(due(.daily, date(19, 20, 30)))
        XCTAssertFalse(due(.daily, date(19, 21), completed: true))
        XCTAssertFalse(due(.daily, date(19, 21), deferred: date(19, 22)))
        XCTAssertTrue(due(.daily, date(19, 22), deferred: date(19, 22)))
        XCTAssertFalse(due(.weekly, date(18, 17, 59)))
        XCTAssertTrue(due(.weekly, date(18, 18)))
        XCTAssertFalse(due(.weekly, date(19, 18)), "No pile of missed Sunday invitations on Monday")
        XCTAssertNotEqual(
            ReviewRhythmStore.periodID(.daily, date: date(19, 21), calendar: calendar),
            ReviewRhythmStore.periodID(.daily, date: date(20, 21), calendar: calendar))
        preferences.dailyInvitations = false;
        preferences.dailyNotifications = true
        XCTAssertFalse(due(.daily, date(19, 21)))
        XCTAssertEqual(ReviewRhythmStore.notificationRequests(preferences).count, 1)
        preferences.dailyMinutes = -2;
        preferences.weeklyMinutes = 9999;
        preferences.weeklyWeekday = 0
        XCTAssertEqual(preferences.normalized().dailyMinutes, 1230)
        XCTAssertEqual(preferences.normalized().weeklyMinutes, 1080)
        XCTAssertEqual(preferences.normalized().weeklyWeekday, 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReviewRhythmNotificationRequestsAreStableLocalAndContainOnlyReviewRoutes
    /// @brief      Verify that review Rhythm Notification Requests Are Stable Local And Contain Only Review Routes
    /// @details    Exercises `ReviewRhythmStore.notificationRequests`, `requests.map`,
    ///             `ReviewRhythmKind.allCases.map`. Checks `XCTAssertEqual(Set(requests.map(\.identifier)),
    ///             Set(ReviewRhythmKind.allCases.map(\.notificationID)))`; `XCTAssertTrue(dailyTrigger.repeats)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testReviewRhythmNotificationRequestsAreStableLocalAndContainOnlyReviewRoutes() throws
    {

        var preferences = ReviewRhythmPreferences()
        preferences.dailyNotifications = true;
        preferences.weeklyNotifications = true
        preferences.dailyMinutes = 21 * 60 + 15;
        preferences.weeklyMinutes = 17 * 60 + 45;
        preferences.weeklyWeekday = 7
        let requests = ReviewRhythmStore.notificationRequests(preferences)
        XCTAssertEqual(Set(requests.map(\.identifier)), Set(ReviewRhythmKind.allCases.map(\.notificationID)))
        let daily = try XCTUnwrap(requests.first
            {
                $0.identifier == ReviewRhythmKind.daily.notificationID
            })
        let weekly = try XCTUnwrap(requests.first
            {
                $0.identifier == ReviewRhythmKind.weekly.notificationID
            })
        let dailyTrigger = try XCTUnwrap(daily.trigger as? UNCalendarNotificationTrigger)
        let weeklyTrigger = try XCTUnwrap(weekly.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(dailyTrigger.repeats);
        XCTAssertTrue(weeklyTrigger.repeats)
        XCTAssertEqual(dailyTrigger.dateComponents.hour, 21);
        XCTAssertEqual(dailyTrigger.dateComponents.minute, 15)
        XCTAssertNil(dailyTrigger.dateComponents.weekday);
        XCTAssertNil(dailyTrigger.dateComponents.timeZone)
        XCTAssertEqual(weeklyTrigger.dateComponents.weekday, 7)
        XCTAssertEqual(weeklyTrigger.dateComponents.hour, 17);
        XCTAssertEqual(weeklyTrigger.dateComponents.minute, 45)
        XCTAssertEqual(daily.content.userInfo["plenactReview"] as? String, "daily")
        XCTAssertEqual(weekly.content.userInfo.count, 1)
        XCTAssertNil(daily.content.badge)
        XCTAssertNotNil(daily.content.sound)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReviewRhythmSaveSkipAndSnoozeAreLocalAndPreserveCorruptSettings
    /// @brief      Verify that review Rhythm Save Skip And Snooze Are Local And Preserve Corrupt Settings
    /// @details    Exercises `ReviewRhythmStore.load`, `ReviewRhythmStore.save`, `ReviewRhythmStore.deferInvitation`.
    ///             Checks `XCTAssertEqual(ReviewRhythmStore.load(from: defaults), ReviewRhythmPreferences())`;
    ///             `XCTAssertNil(defaults.object(forKey: ReviewRhythmStore.key))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testReviewRhythmSaveSkipAndSnoozeAreLocalAndPreserveCorruptSettings() throws
    {

        let suite = "ReviewRhythmTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        XCTAssertEqual(ReviewRhythmStore.load(from: defaults), ReviewRhythmPreferences())
        XCTAssertNil(defaults.object(forKey: ReviewRhythmStore.key))
        var settings = ReviewRhythmPreferences();
        settings.dailyMinutes = 19 * 60;
        settings.weeklyWeekday = 6
        try ReviewRhythmStore.save(settings, to: defaults)
        XCTAssertEqual(ReviewRhythmStore.load(from: defaults), settings)
        let calendar = Calendar.current
        let now = Date()
        ReviewRhythmStore.deferInvitation(
            .daily, date: now, calendar: calendar, until: now.addingTimeInterval(3600), defaults: defaults)
        ReviewRhythmStore.deferInvitation(
            .weekly, date: now, calendar: calendar, until: .distantFuture, defaults: defaults)
        let values = try JSONDecoder().decode(
            [String: Date].self, from: XCTUnwrap(defaults.data(forKey: ReviewRhythmStore.dismissalsKey)))
        XCTAssertEqual(
            values[ReviewRhythmStore.periodID(.daily, date: now, calendar: calendar)], now.addingTimeInterval(3600))
        XCTAssertEqual(values[ReviewRhythmStore.periodID(.weekly, date: now, calendar: calendar)], .distantFuture)
        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        XCTAssertNil(defaults.object(forKey: WeeklyReviewStore.key))
        defaults.set(Data("future or broken".utf8), forKey: ReviewRhythmStore.key)
        XCTAssertThrowsError(try ReviewRhythmStore.save(settings, to: defaults))
        XCTAssertEqual(defaults.data(forKey: ReviewRhythmStore.key), Data("future or broken".utf8))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCheckInMoodsRoundTripWithoutCarryingForwardOrChangingOlderEntries
    /// @brief      Verify that check In Moods Round Trip Without Carrying Forward Or Changing Older Entries
    /// @details    Exercises `plan.recordCheckIn`, `DailyPlanStore.save`, `String(decoding: bytes, as:
    ///             UTF8.self).contains`. Checks `XCTAssertFalse(String(decoding: bytes, as:
    ///             UTF8.self).contains("\"mood\""))`; `XCTAssertNil(try DailyPlanStore.load(from:
    ///             defaults).plans[plan.id]?.checkInHistory.first?.mood)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCheckInMoodsRoundTripWithoutCarryingForwardOrChangingOlderEntries() throws
    {

        let name = "PlenactTests.Moods." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        var plan = DailyPlan(date: .now)
        plan.recordCheckIn(changed: "Before moods existed", sources: [])
        let old = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        let bytes = try XCTUnwrap(defaults.data(forKey: DailyPlanStore.key))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("\"mood\""))
        XCTAssertNil(try DailyPlanStore.load(from: defaults).plans[plan.id]?.checkInHistory.first?.mood)
        let custom = try XCTUnwrap(CheckInMood.custom(emoji: " 🌤️ ", label: " Quietly hopeful "))
        XCTAssertEqual(custom.label, "Quietly hopeful")
        XCTAssertEqual(custom.emoji, "🌤️")
        for choice in CheckInMoodChoice.allCases where choice.mood != nil
        {

            plan.recordCheckIn(changed: "", sources: [], mood: choice.mood)
        }

        plan.recordCheckIn(changed: "", sources: [], mood: custom)
        plan.recordCheckIn(changed: "A fresh Check-in without mood", sources: [])
        let saved = try DailyPlanStore.save(plan, replacing: old, to: defaults)
        let restored = try XCTUnwrap(DailyPlanStore.load(from: defaults).plans[plan.id])
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(restored.checkInHistory.count, 8)
        XCTAssertEqual(restored.checkInHistory[0], old.checkInHistory[0])
        XCTAssertEqual(restored.checkInHistory[6].mood, custom)
        XCTAssertNil(restored.checkInHistory[7].mood)
        XCTAssertEqual(restored.checkInHistory[1].mood?.display, "😊 Great")
        XCTAssertNil(CheckInMoodChoice.none.mood)
        XCTAssertNil(CheckInMoodChoice.custom.mood)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCheckInHistoryRetainsLegacySnapshotsAndOtherDays
    /// @brief      Verify that check In History Retains Legacy Snapshots And Other Days
    /// @details    Exercises `Calendar.current.date`, `DailyPlanStore.save`, `String(decoding: bytes, as:
    ///             UTF8.self).contains`. Checks `XCTAssertFalse(String(decoding: bytes, as:
    ///             UTF8.self).contains("checkIns"))`; `XCTAssertEqual(restored.checkInHistory.count, 1)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCheckInHistoryRetainsLegacySnapshotsAndOtherDays() throws
    {

        let name = "PlenactTests.CheckInHistory." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let today = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        var legacy = DailyPlan(date: yesterday)
        legacy.checkIn = DailyCheckIn(changed: "Original note", savedAt: yesterday)
        let first = try DailyPlanStore.save(legacy, replacing: nil, to: defaults)
        // Real old documents omit the new optional key entirely.
        let bytes = try XCTUnwrap(defaults.data(forKey: DailyPlanStore.key))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("checkIns"))
        var restored = try XCTUnwrap(DailyPlanStore.load(from: defaults).plans[first.id])
        XCTAssertEqual(restored.checkInHistory.count, 1)
        XCTAssertEqual(restored.checkInHistory.first?.id, "legacy:" + first.id)
        XCTAssertTrue(restored.checkInHistory[0].legacy)
        XCTAssertNil(restored.checkInHistory[0].completedTasks)
        XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), bytes)
        restored.intention = "A smaller plan"
        restored.recordCheckIn(changed: "Less time", sources: [], at: yesterday.addingTimeInterval(60))
        let second = try DailyPlanStore.save(restored, replacing: first, to: defaults)
        restored.intention = "The next step"
        restored.recordCheckIn(changed: "", sources: [], at: yesterday.addingTimeInterval(120))
        let third = try DailyPlanStore.save(restored, replacing: second, to: defaults)
        XCTAssertEqual(third.checkInHistory.map(\.changed), ["Original note", "Less time", ""])
        XCTAssertEqual(third.checkInHistory.map(\.intention), ["", "A smaller plan", "The next step"])
        XCTAssertEqual(Set(third.checkInHistory.map(\.id)).count, 3)
        XCTAssertEqual(third.checkIn?.changed, "")
        var current = DailyPlan(date: today)
        current.recordCheckIn(changed: "Today", sources: [])
        _ = try DailyPlanStore.save(current, replacing: nil, to: defaults)
        let beforeConflict = defaults.data(forKey: DailyPlanStore.key)
        var stale = second;
        stale.recordCheckIn(changed: "Stale", sources: [])
        XCTAssertThrowsError(try DailyPlanStore.save(stale, replacing: second, to: defaults))
        XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), beforeConflict)
        let document = try DailyPlanStore.load(from: defaults)
        XCTAssertEqual(document.plans[first.id], third)
        XCTAssertEqual(document.plans[current.id]?.checkInHistory.count, 1)
        var duplicate = third
        duplicate.checkIns?.append(third.checkInHistory[0])
        XCTAssertThrowsError(try DailyPlanStore.save(duplicate, replacing: third, to: defaults))
        XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), beforeConflict)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCheckInSnapshotsDoNotFollowLaterCompletionOrPlanEdits
    /// @brief      Verify that check In Snapshots Do Not Follow Later Completion Or Plan Edits
    /// @details    Exercises `DatedPlanningWeek.make`, `sources.map`, `plan.recordCheckIn`. Checks
    ///             `XCTAssertEqual(first.completedTasks, 0)`; `XCTAssertEqual(first.totalTasks, 1)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCheckInSnapshotsDoNotFollowLaterCompletionOrPlanEdits() throws
    {

        var table = PersonalCollection(title: "On the Table", kind: .list)
        table.lists[0].cards = [KanbanCard(id: 0, word: "Make a useful start", listTitle: table.title, checklists: [])]
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
        var sources = access.searchableItems
        var plan = DailyPlan(date: .now)
        plan.priorities = sources.map(DailyPlanPriority.init)
        plan.checkIn = DailyCheckIn(focus: plan.priorities.first)
        plan.recordCheckIn(changed: "Starting", sources: sources)
        let first = plan.checkInHistory[0]
        XCTAssertEqual(first.completedTasks, 0)
        XCTAssertEqual(first.totalTasks, 1)
        XCTAssertEqual(first.focus, plan.priorities.first)
        let old = try XCTUnwrap(sources.first)
        var card = old.card;
        card.isTitleChecked = true;
        card.word = "Renamed after finishing"
        sources[0] = PlanningSearchResult(
            weekKey: old.weekKey, collectionID: old.collectionID, collectionTitle: old.collectionTitle,
            listID: old.listID, listTitle: old.listTitle, card: card)
        plan.intention = "Now rest"
        plan.recordCheckIn(changed: "Finished", sources: sources)
        XCTAssertEqual(plan.checkInHistory[0], first)
        XCTAssertEqual(first.priorities.first?.title, "Make a useful start")
        XCTAssertEqual(plan.checkInHistory[1].completedTasks, 1)
        XCTAssertNil(plan.checkInHistory[1].focus)
        XCTAssertNil(plan.checkIn?.focus)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEveningReviewPersistsReflectionAndSkipsDecidedAndReferenceItems
    /// @brief      Verify that evening Review Persists Reflection And Skips Decided And Reference Items
    /// @details    Exercises `DatedPlanningWeek.make`, `DailyPlanStore.save`, `DailyPlanStore.load`. Checks
    ///             `XCTAssertNil(try DailyPlanStore.load(from: defaults).plans[plan.id]?.eveningReview)`;
    ///             `XCTAssertEqual(Set(items.map { $0.card.word }), ["Keep", "Finished"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testEveningReviewPersistsReflectionAndSkipsDecidedAndReferenceItems() throws
    {

        let name = "PlenactTests.Evening." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let week = DatedPlanningWeek.make(for: .now)
        var table = PersonalCollection(title: "On the Table", kind: .list)
        table.lists[0].cards = [
            KanbanCard(id: 0, word: "Keep", listTitle: table.title, checklists: []),
            KanbanCard(id: 1, word: "Reference", listTitle: table.title, checklists: [], labelIDs: ["reference"]),
            KanbanCard(id: 2, word: "Finished", listTitle: table.title, isTitleChecked: true, checklists: [])
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
        var plan = DailyPlan(date: .now)
        let legacy = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        XCTAssertNil(try DailyPlanStore.load(from: defaults).plans[plan.id]?.eveningReview)
        let items = TodayReviewSelection.items(
            plan: plan, date: .now, access: access, referenceLabelIDs: ["reference"], calendar: .current)
        XCTAssertEqual(Set(items.map
                {
                    $0.card.word
                }), ["Keep", "Finished"])
        let keep = DailyPlanPriority(try XCTUnwrap(items.first
                {
                    $0.card.word == "Keep"
                }))
        var review = DailyEveningReview()
        review.step = 2;
        review.helped = "A small step";
        review.tomorrow = "Begin gently"
        review.decisions = [DailyReviewDecision(source: keep, result: keep, action: .keep)]
        plan.eveningReview = review
        let saved = try DailyPlanStore.save(plan, replacing: legacy, to: defaults)
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans[plan.id]?.eveningReview, review)
        XCTAssertTrue(TodayReviewSelection.pending(items, review: review).isEmpty)
        XCTAssertEqual(access.library[0].lists[0].cards.count, 3, "Leaving in place does not delete source content")
        var invalid = saved;
        invalid.eveningReview?.step = 8
        _ = try DailyPlanStore.save(invalid, replacing: saved, to: defaults)
        XCTAssertThrowsError(try DailyPlanStore.load(from: defaults))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayVisionCandidatesUseRealDatesAndExcludeReferenceAndCompletedItems
    /// @brief      Verify that today Vision Candidates Use Real Dates And Exclude Reference And Completed Items
    /// @details    Exercises `DatedPlanningWeek.make`, `PlanningDate.key`, `week.collection.lists.firstIndex`. Checks
    ///             `XCTAssertEqual(Set(found.map { $0.card.word }), ["Day priority", "Due today", "Spans today"])`;
    ///             `XCTAssertEqual(Set(found.map(\.id)).count, 3)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testTodayVisionCandidatesUseRealDatesAndExcludeReferenceAndCompletedItems() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let listID = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date, calendar: calendar)])
        let index = try XCTUnwrap(week.collection.lists.firstIndex
            {
                $0.id == listID
            })
        week.collection.lists[index].cards = [
            KanbanCard(id: 0, word: "Day priority", listTitle: "Renamed day", checklists: []),
            KanbanCard(id: 1, word: "Reference", listTitle: "Renamed day", checklists: [], labelIDs: ["reference"]),
            KanbanCard(id: 2, word: "Already finished", listTitle: "Renamed day", isTitleChecked: true, checklists: [])
        ]
        var scheduled = PersonalCollection(title: "Scheduled", kind: .list)
        scheduled.lists[0].cards = [
            KanbanCard(id: 0, word: "Due today", listTitle: scheduled.title, dueDate: date, checklists: []),
            KanbanCard(id: 1, word: "Undated", listTitle: scheduled.title, checklists: []),
            KanbanCard(
                id: 2, word: "Tomorrow", listTitle: scheduled.title,
                dueDate: calendar.date(byAdding: .day, value: 1, to: date), checklists: []),
            KanbanCard(
                id: 3, word: "Spans today", listTitle: scheduled.title,
                startDate: calendar.date(byAdding: .day, value: -1, to: date),
                dueDate: calendar.date(byAdding: .day, value: 1, to: date), checklists: [])
        ]
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        let access = PlanningCalendarAccess(
            document: document, library: [scheduled], saveWeek:
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
        let found = TodayVisionSelection.candidates(
            date: date, access: access, referenceLabelIDs: ["reference"], calendar: calendar)
        XCTAssertEqual(Set(found.map
                {
                    $0.card.word
                }), ["Day priority", "Due today", "Spans today"])
        XCTAssertEqual(Set(found.map(\.id)).count, 3)
        XCTAssertEqual(access.library[0], scheduled)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayVisionProgressResumesAndLegacyDailyPlansStayCompatible
    /// @brief      Verify that today Vision Progress Resumes And Legacy Daily Plans Stay Compatible
    /// @details    Exercises `DailyPlanStore.save`, `JSONSerialization.jsonObject`, `plans[plan.id]?.removeValue`.
    ///             Checks `XCTAssertNil(legacy.visionStep)`; `XCTAssertNil(legacy.visionCompletedAt)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayVisionProgressResumesAndLegacyDailyPlansStayCompatible() throws
    {

        let name = "PlenactTests.Vision." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let plan = DailyPlan(date: .now)
        let saved = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: DailyPlanStore.key))) as? [String: Any])
        var plans = try XCTUnwrap(json["plans"] as? [String: [String: Any]])
        plans[plan.id]?.removeValue(forKey: "visionStep")
        plans[plan.id]?.removeValue(forKey: "visionCompletedAt")
        json["plans"] = plans
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: DailyPlanStore.key)
        let legacy = try XCTUnwrap(DailyPlanStore.load(from: defaults).plans[plan.id])
        XCTAssertNil(legacy.visionStep)
        XCTAssertNil(legacy.visionCompletedAt)
        var progress = legacy
        progress.visionStep = 2
        progress.intention = "A manageable morning"
        let resumed = try DailyPlanStore.save(progress, replacing: legacy, to: defaults)
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans[plan.id]?.visionStep, 2)
        var complete = resumed
        complete.visionStep = nil
        complete.visionCompletedAt = Date(timeIntervalSince1970: 100)
        _ = try DailyPlanStore.save(complete, replacing: resumed, to: defaults)
        XCTAssertEqual(
            try DailyPlanStore.load(from: defaults).plans[plan.id]?.visionCompletedAt, complete.visionCompletedAt)
        XCTAssertThrowsError(try DailyPlanStore.save(saved, replacing: legacy, to: defaults))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDailyPlanRoundTripsAndPreservesOtherDaysAndConflictingEdits
    /// @brief      Verify that daily Plan Round Trips And Preserves Other Days And Conflicting Edits
    /// @details    Exercises `DailyPlanStore.load`, `DailyPlanStore.save`, `PlanningDate.key`. Checks
    ///             `XCTAssertEqual(first.id, "2026-10-16")`; `XCTAssertEqual(first.timeZoneID, "America/Chicago")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDailyPlanRoundTripsAndPreservesOtherDaysAndConflictingEdits() throws
    {

        let name = "PlenactTests.DailyPlan." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!
        var first = DailyPlan(date: today, calendar: calendar)
        first.intention = "Make a useful start"
        first.constraints = "One focused hour"
        first.concerns = "Leave room for a late appointment"
        XCTAssertEqual(first.id, "2026-10-16")
        XCTAssertEqual(first.timeZoneID, "America/Chicago")
        XCTAssertTrue(try DailyPlanStore.load(from: defaults).plans.isEmpty)
        let saved = try DailyPlanStore.save(first, replacing: nil, to: defaults)
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans[first.id], saved)
        let tomorrow = DailyPlan(date: calendar.date(byAdding: .day, value: 1, to: today)!, calendar: calendar)
        _ = try DailyPlanStore.save(tomorrow, replacing: nil, to: defaults)
        var update = saved;
        update.intention = "A revised intention"
        let revised = try DailyPlanStore.save(update, replacing: saved, to: defaults)
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans.count, 2)
        XCTAssertThrowsError(try DailyPlanStore.save(first, replacing: saved, to: defaults))
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans[first.id], revised)
        for offset in [-220, -1, 0, 1, 80]
        {

            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            XCTAssertEqual(DailyPlan(date: date, calendar: calendar).id, PlanningDate.key(date, calendar: calendar))
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDailyPlanPrioritiesResolveLiveOwnerAndWithinBoardMovesWithoutCopyingCards
    /// @brief      Verify that daily Plan Priorities Resolve Live Owner And Within Board Moves Without Copying Cards
    /// @details    Exercises `reference.resolve`. Checks `XCTAssertEqual(reference.title, card.word)`;
    ///             `XCTAssertNil(reference.resolve(in: []))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDailyPlanPrioritiesResolveLiveOwnerAndWithinBoardMovesWithoutCopyingCards() throws
    {

        let first = UUID(), other = UUID()
        let card = KanbanCard(
            id: 5, word: "A useful priority", listTitle: "Before", createdAt: Date(timeIntervalSince1970: 123))
        let source = PlanningSearchResult(
            weekKey: nil, collectionID: first, collectionTitle: "Projects", listID: 1, listTitle: "Before", card: card)
        let reference = DailyPlanPriority(source)
        XCTAssertEqual(reference.title, card.word)
        XCTAssertNil(reference.resolve(in: []))
        let wrong = PlanningSearchResult(
            weekKey: nil, collectionID: other, collectionTitle: "Other", listID: 1, listTitle: "Before", card: card)
        XCTAssertNil(reference.resolve(in: [wrong]))
        var updated = card;
        updated.isTitleChecked = true
        let moved = PlanningSearchResult(
            weekKey: nil, collectionID: first, collectionTitle: "Projects", listID: 7, listTitle: "After", card: updated
        )
        XCTAssertEqual(reference.resolve(in: [wrong, moved])?.listID, 7)
        XCTAssertEqual(reference.resolve(in: [moved])?.card.isTitleChecked, true)
        XCTAssertFalse(card.isTitleChecked)
        let reused = KanbanCard(
            id: card.id, word: card.word, listTitle: card.listTitle, createdAt: Date(timeIntervalSince1970: 456))
        let replacement = PlanningSearchResult(
            weekKey: nil, collectionID: first, collectionTitle: "Projects", listID: 1, listTitle: "Before", card: reused
        )
        XCTAssertNil(reference.resolve(in: [replacement]))
        let decoded = try JSONDecoder().decode(DailyPlanPriority.self, from: JSONEncoder().encode(reference))
        XCTAssertEqual(decoded, reference)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPreviewTextColorsInheritIndependentlyFromBoardListAndItem
    /// @brief      Verify that preview Text Colors Inherit Independently From Board List And Item
    /// @details    Exercises `board.resolvedTitleColor`, `board.resolvedTextColor`. Checks
    ///             `XCTAssertNil(board.cardTitleColor)`; `XCTAssertNil(board.cardTextColor)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPreviewTextColorsInheritIndependentlyFromBoardListAndItem() throws
    {

        var board = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(board.cardTitleColor)
        XCTAssertNil(board.cardTextColor)
        board.cardTitleColor = .teal
        board.cardTextColor = .plum
        var list = ItemAppearance()
        list.cardTitleColor = .blue
        var item = ItemAppearance()
        item.cardTextColor = .rose
        XCTAssertEqual(board.resolvedTitleColor(card: item, list: list), .blue)
        XCTAssertEqual(board.resolvedTextColor(card: item, list: list), .rose)
        item.cardTitleColor = .amber
        XCTAssertEqual(board.resolvedTitleColor(card: item, list: list), .amber)
        item.cardTextColor = nil
        XCTAssertEqual(board.resolvedTextColor(card: item, list: list), .plum)
        XCTAssertEqual(board.resolvedTitleColor(card: nil, list: nil), .teal)
        let restored = try JSONDecoder().decode(BoardAppearance.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(restored, board)
        for presentation in [ItemPresentation.card, .note]
        {

            let card = KanbanCard(
                id: 123, word: "Custom colors", listTitle: "Plans", presentation: presentation, appearance: item)
            let restoredCard = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
            XCTAssertEqual(restoredCard.appearance?.cardTitleColor, .amber)
            XCTAssertNil(restoredCard.appearance?.cardTextColor)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListPreviewTextColorsPersistIndependentlyAndDecodeLegacyDefaults
    /// @brief      Verify that list Preview Text Colors Persist Independently And Decode Legacy Defaults
    /// @details    Exercises `BoardAppearance.inheritingLists`. Checks `XCTAssertNil(legacy.cardTitleColor)`;
    ///             `XCTAssertNil(legacy.cardTextColor)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListPreviewTextColorsPersistIndependentlyAndDecodeLegacyDefaults() throws
    {

        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.cardTitleColor);
        XCTAssertNil(legacy.cardTextColor)
        XCTAssertTrue(legacy.isEmpty)
        for color in ListPreviewTextColor.allCases
        {

            var appearance = ItemAppearance()
            appearance.cardTitleColor = color
            XCTAssertFalse(appearance.isEmpty)
            var list = KanbanList(id: 9, title: "Personal List", cards: [])
            list.appearance = appearance
            let decoded = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
            XCTAssertEqual(decoded.appearance?.cardTitleColor, color)
            XCTAssertNil(decoded.appearance?.cardTextColor)
            appearance.cardTitleColor = nil;
            appearance.cardTextColor = color
            list.appearance = appearance
            XCTAssertFalse(appearance.isEmpty)
            let inherited = BoardAppearance.inheritingLists([list])
            XCTAssertNil(inherited[0].appearance?.cardTextColor)
            let roundTrip = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
            XCTAssertEqual(roundTrip.appearance?.cardTextColor, color)
            XCTAssertNil(roundTrip.appearance?.cardTitleColor)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTransferToastIsVisibleWithoutTakingFocusOrInterceptingTouches
    /// @brief      Verify that transfer Toast Is Visible Without Taking Focus Or Intercepting Touches
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `presenter.show`. Checks `XCTAssertFalse(window.isKeyWindow)`;
    ///             `XCTAssertTrue(scene.windows.first(where: \.isKeyWindow) === keyWindow)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTransferToastIsVisibleWithoutTakingFocusOrInterceptingTouches() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let keyWindow = scene.windows.first(where: \.isKeyWindow)
        let presenter = TransferConfirmationPresenter.shared
        presenter.show(TransferConfirmation(title: "Sketch a garden path", destination: "Garden seasons / Ideas"))
        defer
        {
            presenter.dismiss()
        }

        try await Task.sleep(for: .milliseconds(300))
        let window = try XCTUnwrap(scene.windows.first
            {
                $0.windowLevel > .alert && !$0.isHidden
            })
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertTrue(scene.windows.first(where: \.isKeyWindow) === keyWindow)
        XCTAssertNil(window.hitTest(CGPoint(x: 100, y: window.bounds.height - 150), with: nil))
        let view = try XCTUnwrap(window.rootViewController?.view)
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image
        {
            _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }

        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-transfer-toast-preview.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("Transfer preview: " + path.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRichEditorDefersFocusAndIgnoresStaleRequests
    /// @brief      Verify that rich Editor Defers Focus And Ignores Stale Requests
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertFalse(textView.isFirstResponder, "Focus must not
    ///             change inside the SwiftUI update")`; `XCTAssertFalse(textView.isFirstResponder, "An obsolete
    ///             description-focus request must not steal title focus")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testRichEditorDefersFocusAndIgnoresStaleRequests() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        let textView = UITextView(frame: CGRect(x: 20, y: 100, width: 300, height: 150))
        window.rootViewController?.view.addSubview(textView)
        var requestedFocus = true
        var writing = "Review: Sketch a garden path"
        let parent = RichTextEditor(
            placeholder: "Description",
            text: Binding(get:
                {
                    writing
                }, set:
                {
                    writing = $0
                }),
            focus: Binding(get:
                {
                    requestedFocus
                }, set:
                {
                    requestedFocus = $0
                }))
        let coordinator = parent.makeCoordinator()
        textView.delegate = coordinator
        textView.attributedText = PlanRichText.attributed(writing)
        coordinator.scheduleFocusUpdate(textView)
        XCTAssertFalse(textView.isFirstResponder, "Focus must not change inside the SwiftUI update")
        requestedFocus = false
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(textView.isFirstResponder, "An obsolete description-focus request must not steal title focus")
        for _ in 0 ..< 3
        {

            requestedFocus = true
            coordinator.scheduleFocusUpdate(textView)
            coordinator.scheduleFocusUpdate(textView)
            XCTAssertFalse(textView.isFirstResponder)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(textView.isFirstResponder)
            textView.attributedText = PlanRichText.attributed(writing + " edited")
            coordinator.textViewDidChange(textView)
            XCTAssertTrue(writing.hasSuffix(" edited"))
            requestedFocus = false
            coordinator.scheduleFocusUpdate(textView)
            XCTAssertTrue(textView.isFirstResponder)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(textView.isFirstResponder)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningMigrationPreservesExistingContentAndAssociatesSevenDates
    /// @brief      Verify that planning Migration Preserves Existing Content And Associates Seven Dates
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `week.list`. Checks
    ///             `XCTAssertEqual(week.startKey, "2026-10-04")`; `XCTAssertEqual(week.collection.lists, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningMigrationPreservesExistingContentAndAssociatesSevenDates() throws
    {

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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningDateAssociationSurvivesRenamingAndDoesNotOverwriteArchivedDay
    /// @brief      Verify that planning Date Association Survives Renaming And Does Not Overwrite Archived Day
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `week.collection.lists.firstIndex`.
    ///             Checks `XCTAssertEqual(week.list(on: date)?.title, "Family plans")`;
    ///             `XCTAssertNotEqual(replacement, id)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningDateAssociationSurvivesRenamingAndDoesNotOverwriteArchivedDay() throws
    {

        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let id = try XCTUnwrap(week.dayListIDs["2026-10-10"])
        let index = try XCTUnwrap(week.collection.lists.firstIndex
            {
                $0.id == id
            })
        try week.collection.lists[index].edit(title: "Family plans", subtitle: nil)
        XCTAssertEqual(week.list(on: date)?.title, "Family plans")
        week.collection.lists[index].isArchived = true
        let retained = week.collection.lists[index]
        let replacement = week.prepareDay(date)
        XCTAssertNotEqual(replacement, id)
        XCTAssertEqual(week.collection.lists[index], retained)
        XCTAssertEqual(week.list(on: date)?.id, replacement)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningRolloverPreservesPreviousWeekAndReusesFuturePlans
    /// @brief      Verify that planning Rollover Preserves Previous Week And Reuses Future Plans
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `future.list`. Checks
    ///             `XCTAssertEqual(next.id, future.id)`; `XCTAssertEqual(next.collection, future.collection)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningRolloverPreservesPreviousWeekAndReusesFuturePlans() throws
    {

        let calendar = planningTestCalendar()
        let today = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        let nextDate = try XCTUnwrap(PlanningDate.date("2026-10-11", calendar: calendar))
        let current = DatedPlanningWeek.make(
            for: today, lists: SampleData.lists, saved: [SampleData.lists[0].cards[0].id], calendar: calendar)
        var future = DatedPlanningWeek.make(for: nextDate, calendar: calendar)
        let dayID = try XCTUnwrap(future.list(on: nextDate)?.id)
        let index = try XCTUnwrap(future.collection.lists.firstIndex
            {
                $0.id == dayID
            })
        let card = SampleData.lists[0].cards[0].replacingLocation(id: 90, listTitle: "Sunday")
        future.collection.lists[index].cards = [card]
        future.collection.savedCardIDs = [90]
        var document = PlanningCalendarDocument(
            currentWeekKey: current.startKey, firstWeekday: 1, weeks: [current, future])
        let next = document.rollForward(
            to: nextDate, currentLists: current.collection.lists, saved: current.collection.savedCardIDs,
            calendar: calendar)
        XCTAssertEqual(next.id, future.id)
        XCTAssertEqual(next.collection, future.collection)
        XCTAssertEqual(document.weeks.count, 2)
        XCTAssertEqual(document.weeks.first
            {
                $0.startKey == current.startKey
            }, current)
        XCTAssertEqual(document.currentWeekKey, "2026-10-11")
        let repeated = document.rollForward(
            to: nextDate, currentLists: next.collection.lists, saved: next.collection.savedCardIDs, calendar: calendar)
        XCTAssertEqual(repeated.id, next.id)
        XCTAssertEqual(document.weeks.count, 2)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningEmptyBrowsingDoesNotPersistAndExplicitSaveRoundTrips
    /// @brief      Verify that planning Empty Browsing Does Not Persist And Explicit Save Round Trips
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `PlanningCalendarStore.save`. Checks
    ///             `XCTAssertNil(document.week(for: futureDate, calendar: calendar))`;
    ///             `XCTAssertFalse(preview.hasContent)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningEmptyBrowsingDoesNotPersistAndExplicitSaveRoundTrips() throws
    {

        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        let futureDate = try XCTUnwrap(PlanningDate.date("2026-12-25", calendar: calendar))
        let current = DatedPlanningWeek.make(for: date, calendar: calendar)
        var document = PlanningCalendarDocument(currentWeekKey: current.startKey, firstWeekday: 1, weeks: [current])
        let suite = "Plenact.PlanningTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningPersistenceRetainsCorruptDocumentWithoutOverwrite
    /// @brief      Verify that planning Persistence Retains Corrupt Document Without Overwrite
    /// @details    Exercises `DatedPlanningWeek.make`, `PlanningCalendarStore.save`. Checks `XCTAssertThrowsError(try
    ///             PlanningCalendarStore.save(document, to: defaults))`; `XCTAssertEqual(defaults.data(forKey:
    ///             PlanningCalendarStore.key), bytes)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningPersistenceRetainsCorruptDocumentWithoutOverwrite() throws
    {

        let suite = "Plenact.PlanningCorruption.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let bytes = Data("retained unreadable calendar".utf8)
        defaults.set(bytes, forKey: PlanningCalendarStore.key)
        let week = DatedPlanningWeek.make(for: .now)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        XCTAssertThrowsError(try PlanningCalendarStore.save(document, to: defaults))
        XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), bytes)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCollectionPreviewsPreferDescriptionsAndReadOlderCollections
    /// @brief      Verify that collection Previews Prefer Descriptions And Read Older Collections
    /// @details    Exercises `JSONSerialization.jsonObject`, `legacy.removeValue`, `JSONSerialization.data`. Checks
    ///             `XCTAssertEqual(collection.contentPreview, "Garden plans · Desk project · Weekend ideas")`;
    ///             `XCTAssertEqual(collection.contentPreview, "Personal projects and plans")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCollectionPreviewsPreferDescriptionsAndReadOlderCollections() throws
    {

        var collection = PersonalCollection(title: "Ideas", kind: .list)
        collection.lists[0].cards = [
            KanbanCard(id: 1, word: "Garden plans", listTitle: "Ideas"),
            KanbanCard(id: 2, word: "Divider", listTitle: "Ideas", isDivider: true),
            KanbanCard(id: 3, word: "Desk project", listTitle: "Ideas"),
            KanbanCard(id: 4, word: "Weekend ideas", listTitle: "Ideas"),
            KanbanCard(id: 5, word: "Later", listTitle: "Ideas")
        ]
        XCTAssertEqual(collection.contentPreview, "Garden plans · Desk project · Weekend ideas")
        collection.collectionDescription = "  Personal projects and plans  "
        XCTAssertEqual(collection.contentPreview, "Personal projects and plans")
        let data = try JSONEncoder().encode(collection)
        XCTAssertEqual(
            try JSONDecoder().decode(PersonalCollection.self, from: data).collectionDescription,
            collection.collectionDescription)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "collectionDescription")
        let decoded = try JSONDecoder().decode(
            PersonalCollection.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.collectionDescription)
        XCTAssertEqual(decoded.contentPreview, "Garden plans · Desk project · Weekend ideas")
        collection.collectionDescription = "  "
        collection.lists[0].isArchived = true
        XCTAssertEqual(collection.contentPreview, "")
        for example in PersonalListExample.allCases
        {

            XCTAssertEqual(example.makeCollection(existingTitles: []).contentPreview, example.summary)
        }

        for template in MixedListTemplate.allCases
        {

            XCTAssertEqual(template.makeCollection(existingTitles: []).contentPreview, template.summary)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningSharedSearchRetainsScopesAndOwnerQualifiedIdentities
    /// @brief      Verify that planning Shared Search Retains Scopes And Owner Qualified Identities
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `PlanningSharedSearchIndex.results`.
    ///             Checks `XCTAssertEqual(results.count, 2)`; `XCTAssertNotEqual(results[0].id, results[1].id)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningSharedSearchRetainsScopesAndOwnerQualifiedIdentities() throws
    {

        let calendar = planningTestCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-10", calendar: calendar))
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        var library = PersonalCollection(title: "Research", kind: .list)
        let card = SampleData.lists[0].cards[0]
        week.collection.lists[0].cards = [card]
        library.lists[0].cards = [card]
        let access = PlanningCalendarAccess(
            document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]),
            library: [library], saveWeek:
            {
                _ in
                true
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
                true
            })
        let results = PlanningSharedSearchIndex.results(
            query: card.word, scope: .all, access: access, labels: LabelLibraryStore.load())
        XCTAssertEqual(results.count, 2)
        XCTAssertNotEqual(results[0].id, results[1].id)
        XCTAssertEqual(Set(results.compactMap(\.ownerID)), [week.id, library.id])
        XCTAssertEqual(results.filter
            {
                $0.weekKey != nil
            } .count, 1)
        let boardResults = PlanningSharedSearchIndex.results(
            query: library.lists[0].title, scope: .boards, access: access, labels: LabelLibraryStore.load())
        XCTAssertTrue(boardResults.contains
            {
                $0.ownerID == library.id && $0.cardID == nil
            })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusSelectionContextFadesWithoutEditingItems
    /// @brief      Let selection context fade after its reading interval without editing items
    /// @details    Hosts Focus through its three-second pause and soft fade, then checks the
    ///             subtitle space is reclaimed while mutation callbacks remain uninvoked.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testFocusSelectionContextFadesWithoutEditingItems() async throws
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

        let list = KanbanList(id: 1, title: "Today", cards: [])
        var heights: [CGFloat] = []
        let host = UIHostingController(
            rootView: TodayFocusSection(
                list: list, cards: [], entries: [],
                groupsBySection: false, chronological: false, includesImportant: true, includesUpNext: true,
                filtersChangedAt: .now,
                onChangeFilters:
                {
                    _, _, _ in
                    XCTFail("Rendering must not change filters")
                },
                onToggleCard:
                {
                    _ in
                    XCTFail("Rendering must not edit items")
                }, onOpenCard:
                {
                    _ in
                },
                onDeleteCard:
                {
                    _ in
                    XCTFail("Rendering must not delete");
                    return false
                }, onOpenTodayList:
                {

                }
            )
            .padding(20)
            .onGeometryChange(for: CGFloat.self)
            {

                $0.size.height
            }
            action:
            {

                heights.append($0)
            })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host;
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(350))
        let expanded = try XCTUnwrap(heights.last)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        try XCTUnwrap(image.pngData()).write(
            to: FileManager.default.temporaryDirectory.appendingPathComponent("plenact-focus-filter-summary.png"))
        try await Task.sleep(for: .seconds(3.8))
        XCTAssertLessThan(try XCTUnwrap(heights.last), expanded)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusFilterPaletteUsesDistinctReadableCombinationColors
    /// @brief      Verify that focus Filter Palette Uses Distinct Readable Combination Colors
    /// @details    Exercises `TodayFocusFilterColor.rgb`, `colors.insert`. Checks
    ///             `XCTAssertNil(TodayFocusFilterColor.rgb(upNext: false, important: false, bookmarked: false, dark:
    ///             dark))`; `XCTAssertGreaterThanOrEqual((max(ink, background) + 0.05) / (min(ink, background) +
    ///             0.05), 4.5)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusFilterPaletteUsesDistinctReadableCombinationColors() throws
    {


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusFilterPaletteUsesDistinctReadableCombinationColors.luminance
        /// @brief      Calculate relative luminance for the filter-palette test
        /// @details    Linearizes the supplied sRGB components and combines them using the red, green, and blue
        ///             luminance weights.
        ///
        /// @param[in]  values  Values to summarize in their supplied order
        ///
        /// @return     (Double) result described by this operation's contract
        ///
        func luminance(_ values: [Double]) -> Double
        {

            zip(values, [0.2126, 0.7152, 0.0722]).reduce(0)
            {
                result, pair in
                let v = pair.0
                return result + (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)) * pair.1
            }

        }

        for dark in [false, true]
        {

            XCTAssertNil(TodayFocusFilterColor.rgb(upNext: false, important: false, bookmarked: false, dark: dark))
            var colors = Set<String>()
            let background = luminance(dark ? [0.12, 0.12, 0.14] : [245.0 / 255, 229.0 / 255, 212.0 / 255])
            for selection in 1 ... 7
            {

                let rgb = try XCTUnwrap(
                    TodayFocusFilterColor.rgb(
                        upNext: selection & 1 != 0,
                        important: selection & 2 != 0, bookmarked: selection & 4 != 0, dark: dark))
                colors.insert("\(rgb.red),\(rgb.green),\(rgb.blue)")
                let ink = luminance([rgb.red, rgb.green, rgb.blue])
                XCTAssertGreaterThanOrEqual(
                    (max(ink, background) + 0.05) / (min(ink, background) + 0.05), 4.5,
                                                    "Selection \(selection), dark \(dark)")
            }

            XCTAssertEqual(colors.count, 7)
        }

        let purple = try XCTUnwrap(TodayFocusFilterColor.rgb(upNext: true, important: true, bookmarked: false))
        XCTAssertEqual(purple.red, 126.0 / 255, accuracy: 0.000001)
        XCTAssertEqual(purple.green, 34.0 / 255, accuracy: 0.000001)
        XCTAssertEqual(purple.blue, 206.0 / 255, accuracy: 0.000001)
    }

}
