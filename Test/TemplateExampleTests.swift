// --------------------------------------------------------------------------------------------------
// @file       TemplateExampleTests.swift
// @brief      Template Example regression tests
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
/// TemplateExample regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testUntimedBundledExamplesPopulateEveryFocusFilterCombinationLateInTheDay
    /// @brief      Verify that untimed Bundled Examples Populate Every Focus Filter Combination Late In The Day
    /// @details    Exercises `PlanningDate.date`, `PlanningRoutineLibrary.seeded.templates.filter`,
    ///             `DatedPlanningWeek.make`. Checks `XCTAssertTrue(important.allSatisfy { $0 > 500 })`;
    ///             `XCTAssertFalse(entries.isEmpty, "\(template.name), filter mask \(mask) must demonstrate Focus
    ///             even late in the day")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testUntimedBundledExamplesPopulateEveryFocusFilterCombinationLateInTheDay() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let date = try XCTUnwrap(PlanningDate.date("2026-11-01", calendar: calendar))
        let late = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 45, second: 0, of: date))
        let templates = PlanningRoutineLibrary.seeded.templates.filter
        {
            $0.id != PlanningRoutineLibrary.jmrID
        }

        for template in templates
        {

            var original = DatedPlanningWeek.make(for: date, calendar: calendar)
            original.collection.lists[0].archivedCards = [
                KanbanCard(id: 500, word: "Retained", listTitle: "Archive", checklists: [])
            ]
            let before = original
            let result = try PlanningTemplateApplication.apply(
                template, to: original, date: date, calendar: calendar, mode: .add)
            let id = try XCTUnwrap(result.dayListIDs[PlanningDate.key(date, calendar: calendar)])
            let list = try XCTUnwrap(result.collection.lists.first
                {
                    $0.id == id
                })
            let important = PlanningTemplateApplication.exampleImportantIDs(template, in: original)
            XCTAssertTrue(important.allSatisfy
                {
                    $0 > 500
                })
            for mask in 0 ..< 8
            {

                let preferences = LocalProfilePreferences(
                    todayFocusIncludesImportant: mask & 1 != 0,
                    todayFocusIncludesBookmarked: mask & 2 != 0, todayFocusIncludesUpNext: mask & 4 != 0)
                let entries = preferences.todayFocusEntries(
                    in: list.cards, on: late, calendar: calendar,
                    importantCardIDs: important, bookmarkedCardIDs: result.collection.savedCardIDs)
                XCTAssertFalse(
                    entries.isEmpty, "\(template.name), filter mask \(mask) must demonstrate Focus even late in the day"
                )
                XCTAssertTrue(entries.allSatisfy
                    {
                        !$0.card.isSectionDivider && !$0.card.isTitleChecked
                    })
            }

            XCTAssertEqual(original, before)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyBundledFocusMetadataUpgradeDoesNotRewriteStoredPlansOrCustomTemplates
    /// @brief      Verify that legacy Bundled Focus Metadata Upgrade Does Not Rewrite Stored Plans Or Custom
    ///             Templates
    /// @details    Exercises `PlanningRoutineStore.load`, `upgraded.templates.dropFirst().allSatisfy`,
    ///             `upgraded.templates.dropFirst`. Checks `XCTAssertEqual(upgraded.bundledRoutineRevision, 4)`;
    ///             `XCTAssertEqual(upgraded.templates[0], custom)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLegacyBundledFocusMetadataUpgradeDoesNotRewriteStoredPlansOrCustomTemplates() throws
    {

        let suite = "ExampleFocusMigration." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        var library = PlanningRoutineLibrary.seeded
        for index in library.templates.indices
        {
            library.templates[index].exampleFocus = nil
        }

        library.bundledRoutineRevision = 3
        library.templates[0].name = "My custom edited week"
        let custom = library.templates[0]
        let originalBytes = try JSONEncoder().encode(library)
        defaults.set(originalBytes, forKey: PlanningRoutineStore.key)
        let weekBytes = Data("unchanged calendar".utf8)
        defaults.set(weekBytes, forKey: PlanningCalendarStore.key)
        let upgraded = try PlanningRoutineStore.load(from: defaults)
        XCTAssertEqual(upgraded.bundledRoutineRevision, 4)
        XCTAssertEqual(upgraded.templates[0], custom)
        XCTAssertNil(upgraded.templates[0].exampleFocus)
        XCTAssertTrue(upgraded.templates.dropFirst().allSatisfy
            {
                $0.exampleFocus != nil
            })
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), originalBytes)
        XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), weekBytes)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCustomTemplateDoesNotInventFocusMarksOrDates
    /// @brief      Verify that custom Template Does Not Invent Focus Marks Or Dates
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `PlanningDate.key`. Checks
    ///             `XCTAssertNil(custom.exampleFocus)`;
    ///             `XCTAssertTrue(PlanningTemplateApplication.exampleImportantIDs(custom, in: blank).isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCustomTemplateDoesNotInventFocusMarksOrDates() throws
    {

        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-09", calendar: calendar))
        var source = DatedPlanningWeek.make(for: date, calendar: calendar)
        let id = try XCTUnwrap(source.dayListIDs[PlanningDate.key(date, calendar: calendar)])
        let index = try XCTUnwrap(source.collection.lists.firstIndex
            {
                $0.id == id
            })
        source.collection.lists[index].cards = [
            KanbanCard(id: 10, word: "My unscheduled task", listTitle: "Monday", checklists: [])
        ]
        let custom = try PlanningRoutineTemplate.capture(name: "My day", week: source, day: date, calendar: calendar)
        XCTAssertNil(custom.exampleFocus)
        let blank = DatedPlanningWeek.make(for: date, calendar: calendar)
        let result = try PlanningTemplateApplication.apply(
            custom, to: blank, date: date, calendar: calendar, mode: .add)
        XCTAssertTrue(PlanningTemplateApplication.exampleImportantIDs(custom, in: blank).isEmpty)
        XCTAssertTrue(result.collection.savedCardIDs.isEmpty)
        let card = try XCTUnwrap(result.collection.lists.first
            {
                $0.id == id
            }?.cards.first)
        XCTAssertNil(card.startDate)
        XCTAssertNil(card.dueDate)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testMonthExampleRetainsFocusChoicesAndProvidesMatchingTodayItems
    /// @brief      Verify that month Example Retains Focus Choices And Provides Matching Today Items
    /// @details    Verifies that the example retains Focus choices and supplies matching dated content. Also
    ///             preserves the corner-Back choice from standalone or legacy profile preferences and honors an
    ///             explicit opt-out so changing datasets does not silently change navigation behavior.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testMonthExampleRetainsFocusChoicesAndProvidesMatchingTodayItems() throws
    {

        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-21", calendar: calendar))
        let late = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 45, second: 0, of: date))
        let example = FullMonthExample.make(now: late, calendar: calendar)
        let selected = LocalProfilePreferences(
            todayFocusItemCount: 6, todayFocusIncludesImportant: true, todayFocusIncludesBookmarked: true,
            todayFocusIncludesUpNext: true, enablesLowerCornerBack: true)
        let domain = try example.defaultsDomain(preserving: [PlanPreferencesStore.key: JSONEncoder().encode(selected)])
        let preserved = try JSONDecoder().decode(
            LocalProfilePreferences.self, from: XCTUnwrap(domain[PlanPreferencesStore.key] as? Data))
        XCTAssertTrue(preserved.todayFocusIncludesImportant)
        XCTAssertTrue(preserved.todayFocusIncludesBookmarked)
        XCTAssertTrue(preserved.todayFocusIncludesUpNext)
        XCTAssertEqual(preserved.todayFocusItemCount, 6)
        XCTAssertTrue(preserved.enablesLowerCornerBack)
        let legacyProfile = LocalProfile(displayName: "Synthetic", preferences: selected)
        let legacyDomain = try example.defaultsDomain(preserving: [
                LocalProfileStore.storageKey: JSONEncoder().encode(legacyProfile)
            ])
        let legacyPreferences = try JSONDecoder().decode(
            LocalProfilePreferences.self, from: XCTUnwrap(legacyDomain[PlanPreferencesStore.key] as? Data))
        XCTAssertTrue(legacyPreferences.enablesLowerCornerBack)
        var disabled = selected
        disabled.enablesLowerCornerBack = false
        let disabledDomain = try example.defaultsDomain(preserving: [
                PlanPreferencesStore.key: JSONEncoder().encode(disabled)
            ])
        let disabledPreferences = try JSONDecoder().decode(
            LocalProfilePreferences.self, from: XCTUnwrap(disabledDomain[PlanPreferencesStore.key] as? Data))
        XCTAssertFalse(disabledPreferences.enablesLowerCornerBack)
        let week = try XCTUnwrap(example.document.week(for: date))
        let listID = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date, calendar: calendar)])
        let cards = try XCTUnwrap(week.collection.lists.first
            {
                $0.id == listID
            }).cards
        let importantData = try XCTUnwrap(domain[LibraryImportanceSelection.key] as? Data)
        let important = LibraryImportanceSelection.cardIDs(collectionID: week.id, data: importantData)
        let bookmarks = Set(try XCTUnwrap(domain["Plenact.SavedCardIDs.v1"] as? [Int]))
        for mask in 1 ..< 8
        {

            let preferences = LocalProfilePreferences(
                todayFocusIncludesImportant: mask & 1 != 0,
                todayFocusIncludesBookmarked: mask & 2 != 0, todayFocusIncludesUpNext: mask & 4 != 0)
            XCTAssertFalse(
                preferences.todayFocusEntries(
                    in: cards, on: late, calendar: calendar,
                    importantCardIDs: important, bookmarkedCardIDs: bookmarks
                ).isEmpty, "Month filter mask \(mask)")
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleWeekUndoRetainsCalendarAndFocusFlagsWithLegacyCompatibility
    /// @brief      Verify that example Week Undo Retains Calendar And Focus Flags With Legacy Compatibility
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `ExampleLoadUndoStore.save`. Checks
    ///             `XCTAssertEqual(snapshot.week, week)`; `XCTAssertEqual(snapshot.savedCardIDs, [3])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testExampleWeekUndoRetainsCalendarAndFocusFlagsWithLegacyCompatibility() throws
    {

        let suite = "ExampleWeekFocusUndo." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-09", calendar: calendar))
        let week = DatedPlanningWeek.make(for: date, calendar: calendar)
        XCTAssertTrue(
            ExampleLoadUndoStore.save(
                lists: week.collection.lists, todayListID: 0, week: week,
                savedCardIDs: [3], importantCardIDs: [5], to: defaults))
        let snapshot = try XCTUnwrap(ExampleLoadUndoStore.load(from: defaults))
        XCTAssertEqual(snapshot.week, week)
        XCTAssertEqual(snapshot.savedCardIDs, [3])
        XCTAssertEqual(snapshot.importantCardIDs, [5])
        XCTAssertTrue(ExampleLoadUndoStore.save(lists: week.collection.lists, todayListID: 0, to: defaults))
        let legacy = try XCTUnwrap(ExampleLoadUndoStore.load(from: defaults))
        XCTAssertNil(legacy.week)
        XCTAssertNil(legacy.importantCardIDs)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testJmrTemplateMatchesAllRequestedTimeRangesAndDailyGymNotes
    /// @brief      Verify that jmr Template Matches All Requested Time Ranges And Daily Gym Notes
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `PlanningTemplateApplication.apply`.
    ///             Checks `XCTAssertEqual(template.name, "Jmr")`; `XCTAssertEqual(template.kind, .week)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testJmrTemplateMatchesAllRequestedTimeRangesAndDailyGymNotes() throws
    {

        let template = PlanningRoutineLibrary.jmr
        XCTAssertEqual(template.name, "Jmr")
        XCTAssertEqual(template.kind, .week)
        XCTAssertEqual(template.itemCount, 28)
        XCTAssertEqual(template.collection.lists.count, 7)
        XCTAssertEqual(PlanningRoutineLibrary.seeded.defaultWeekID, template.id)
        for firstWeekday in [1, 2]
        {

            let calendar = routineCalendar(firstWeekday: firstWeekday)
            let targetDate = try XCTUnwrap(PlanningDate.date("2026-11-01", calendar: calendar))
            let target = DatedPlanningWeek.make(for: targetDate, calendar: calendar)
            let applied = try PlanningTemplateApplication.apply(
                template, to: target, date: targetDate, calendar: calendar, mode: .add)
            for day in PlanningDate.days(in: applied.startKey, calendar: calendar)
            {

                let weekday = calendar.component(.weekday, from: day)
                let cards = try XCTUnwrap(applied.list(on: day)?.cards)
                let expected: [(String, Int, Int, Int, Int)]
                if weekday == 7
                {

                    expected = [
                        ("Wake", 5, 0, 5, 30), ("Morning Starbucks Pow-wow", 6, 0, 7, 30), ("Gym", 9, 0, 11, 0),
                        ("Car Wash", 12, 0, 12, 30)
                    ]
                }
                else if weekday == 1
                {

                    expected = [
                        ("Wake", 4, 0, 4, 30), ("Morning Starbucks Pow-wow", 5, 0, 6, 30), ("Gym", 7, 0, 8, 30),
                        ("Church", 9, 0, 12, 30)
                    ]
                }
                else
                {

                    expected = [
                        ("Wake", 4, 0, 4, 30), ("Morning Starbucks Pow-wow", 5, 0, 6, 30), ("Work", 7, 0, 17, 0),
                        ("Gym", 17, 0, 18, 0)
                    ]
                }

                XCTAssertEqual(cards.count, expected.count)
                for (card, slot) in zip(cards, expected)
                {

                    XCTAssertEqual(card.word, slot.0)
                    let start = try XCTUnwrap(card.startDate), stop = try XCTUnwrap(card.dueDate)
                    XCTAssertTrue(calendar.isDate(start, inSameDayAs: day))
                    XCTAssertTrue(calendar.isDate(stop, inSameDayAs: day))
                    XCTAssertEqual(calendar.component(.hour, from: start), slot.1)
                    XCTAssertEqual(calendar.component(.minute, from: start), slot.2)
                    XCTAssertEqual(calendar.component(.hour, from: stop), slot.3)
                    XCTAssertEqual(calendar.component(.minute, from: stop), slot.4)
                    XCTAssertLessThan(start, stop)
                    XCTAssertEqual(card.startDateKind, .dateAndTime)
                    XCTAssertEqual(card.dueDateKind, .dateAndTime)
                    XCTAssertTrue(card.showsDueDateInList)
                    XCTAssertTrue(card.usesTimeOnlySchedule(on: day, calendar: calendar))
                    XCTAssertFalse(card.isTitleChecked)
                    XCTAssertTrue(card.checklists.isEmpty)
                    if card.word == "Gym"
                    {

                        XCTAssertTrue(card.funParagraph.contains("meditation, walking, or massage"))
                    }
                    else
                    {

                        XCTAssertEqual(card.descriptionOverride, "")
                    }

                }

            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryStarterFiltersScopeSearchAndExcludePersonalCollections
    /// @brief      Verify that library Starter Filters Scope Search And Exclude Personal Collections
    /// @details    Exercises `filter.includes`, `LibraryBrowseFilter.all.includes`,
    ///             `LibraryBrowseFilter.boards.includes`. Checks `XCTAssertFalse(filter.browsesCollections)`;
    ///             `XCTAssertFalse(filter.includes(list))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLibraryStarterFiltersScopeSearchAndExcludePersonalCollections() throws
    {

        let list = PersonalCollection(title: "Vacation private plans", kind: .list)
        let board = PersonalCollection(title: "Example private work", kind: .board)
        for filter in [LibraryBrowseFilter.templates, .examples, .labels, .help]
        {

            XCTAssertFalse(filter.browsesCollections)
            XCTAssertFalse(filter.includes(list))
            XCTAssertFalse(filter.includes(board))
        }

        XCTAssertTrue(LibraryBrowseFilter.all.includes(list))
        XCTAssertTrue(LibraryBrowseFilter.boards.includes(board))
        XCTAssertEqual(LibraryBrowseFilter.templates.searchPrompt, "Find in Templates")
        XCTAssertEqual(LibraryBrowseFilter.examples.searchPrompt, "Find in Examples")
        XCTAssertTrue(LibraryStarterSearch.matches("VACATION day", texts: ["Vacation Day", "Day template"]))
        XCTAssertFalse(LibraryStarterSearch.matches("vacation nonexistent", texts: ["Vacation Day"]))
        XCTAssertTrue(LibraryStarterSearch.matches("", texts: []))
        XCTAssertTrue(LibraryStarterSearch.matches("month motion", texts: ["A month in motion", "Full-month example"]))
        XCTAssertFalse(LibraryStarterSearch.matches("private plans", texts: ["A month in motion"]))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryTemplateCaptureUsesLiveWeekAndReservesArchivedIDs
    /// @brief      Verify that library Template Capture Uses Live Week And Reserves Archived I Ds
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `week.collection.lists.firstIndex`.
    ///             Checks `XCTAssertEqual(result.id, week.id)`;
    ///             `XCTAssertEqual(result.collection.lists[index].cards.count, 2)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLibraryTemplateCaptureUsesLiveWeekAndReservesArchivedIDs() throws
    {

        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar))
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let listID = try XCTUnwrap(week.dayListIDs["2026-10-12"])
        let index = try XCTUnwrap(week.collection.lists.firstIndex
            {
                $0.id == listID
            })
        week.collection.lists[index].cards = [
            KanbanCard(id: 2, word: "Keep my work", listTitle: "Monday", isTitleChecked: true, checklists: [])
        ]
        week.collection.lists[index].archivedCards = [
            KanbanCard(id: 99, word: "Keep archive", listTitle: "Monday", checklists: [])
        ]
        let template = QuickCaptureTemplate.smallPlan
        let capture = QuickCaptureSubmission(
            listID: listID, title: "My custom title", body: template.body,
            subtitle: "", presentation: template.presentation, actions: template.actions, attachments: [],
            schedule: QuickCaptureSchedule(start: date, stop: nil))
        let result = try LibraryTemplateCapture.adding(capture, to: week)
        XCTAssertEqual(result.id, week.id)
        XCTAssertEqual(result.collection.lists[index].cards.count, 2)
        XCTAssertEqual(result.collection.lists[index].cards[0], week.collection.lists[index].cards[0])
        XCTAssertEqual(result.collection.lists[index].archivedCards, week.collection.lists[index].archivedCards)
        let added = try XCTUnwrap(result.collection.lists[index].cards.last)
        XCTAssertEqual(added.id, 100)
        XCTAssertEqual(added.word, "My custom title")
        XCTAssertEqual(added.descriptionOverride, template.body)
        XCTAssertEqual(added.checklists.flatMap(\.items).map(\.title), template.actions)
        XCTAssertFalse(added.isTitleChecked)
        let richBody =
        PlanRichText.prefix
        + (try JSONEncoder().encode([PlanRichText.Run(text: "Keep the formatting", bold: true)]))
        .base64EncodedString()
        let note = QuickCaptureSubmission(
            listID: listID, title: "My note", body: richBody, subtitle: "", presentation: .note,
            actions: nil, attachments: [], schedule: nil)
        XCTAssertEqual(
            try LibraryTemplateCapture.adding(note, to: result).collection.lists[index].cards.last?.descriptionOverride,
            richBody)
        let missing = QuickCaptureSubmission(
            listID: 98765, title: "No target", body: "", subtitle: "", presentation: .card,
            actions: nil, attachments: [], schedule: nil)
        XCTAssertThrowsError(try LibraryTemplateCapture.adding(missing, to: week))
        XCTAssertEqual(week.collection.lists[index].cards.count, 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryTemplatesAndExamplesFiltersRenderAndSearchWithoutWriting
    /// @brief      Verify that library Templates And Examples Filters Render And Search Without Writing
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(saved, 0)`; `XCTAssertEqual(keys.map {
    ///             UserDefaults.standard.data(forKey: $0) }, before)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLibraryTemplatesAndExamplesFiltersRenderAndSearchWithoutWriting() async throws
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

        let keys = [
            PlanningRoutineStore.key, PlanningCalendarStore.key, "Plenact.PersonalCollections.v1", "Plenact.Board.v1"
        ]
        let before = keys.map
        {
            UserDefaults.standard.data(forKey: $0)
        }

        var saved = 0
        let privateCollection = PersonalCollection(title: "Private unrelated project", kind: .list)
        for width in [393.0, 744.0]
        {

            for (filter, query) in [
                (LibraryBrowseFilter.templates, ""), (.examples, ""), (.templates, "vacation"),
                (.examples, "month motion"), (.examples, "day sections")
            ]
            {

                let host = UIHostingController(
                    rootView: BoardListsView(
                        retainedWeekLists: [], collections: .constant([privateCollection]),
                        registerListNewNote:
                        {
                            _ in
                        }, onOpenSaved:
                        {
                            saved += 1
                        },
                        onLoadExampleWeek:
                        {

                            saved += 1;
                            return true
                        }, onLoadExampleMonth:
                        {
                            saved += 1
                        },
                        browseFilter: filter, searchText: query))
                window.frame = CGRect(x: 0, y: 0, width: width, height: 1024)
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
                                                "plenact-library-\(filter.rawValue)-\(Int(width))-\(query.isEmpty ? "all" : query.replacingOccurrences(of: " ", with: "-")).png"
                )
                try XCTUnwrap(image.pngData()).write(to: url)
                print("LIBRARY_FILTER_RENDER=" + url.path)
            }

        }

        XCTAssertEqual(saved, 0)
        XCTAssertEqual(keys.map
            {
                UserDefaults.standard.data(forKey: $0)
            }, before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningTemplatesSeedStoreConflictAndCorruptDataRetention
    /// @brief      Verify that planning Templates Seed Store Conflict And Corrupt Data Retention
    /// @details    Exercises `PlanningRoutineStore.load`, `baseline.templates.map`, `PlanningRoutineStore.save`.
    ///             Checks `XCTAssertNil(defaults.data(forKey: PlanningRoutineStore.key))`;
    ///             `XCTAssertEqual(baseline.templates.map(\.name), ["Work Week", "Vacation Day", "Jmr"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningTemplatesSeedStoreConflictAndCorruptDataRetention() throws
    {

        let name = "Plenact.RoutineTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let baseline = try PlanningRoutineStore.load(from: defaults)
        XCTAssertNil(defaults.data(forKey: PlanningRoutineStore.key))
        XCTAssertEqual(baseline.templates.map(\.name), ["Work Week", "Vacation Day", "Jmr"])
        XCTAssertEqual(baseline.defaultWeekID, PlanningRoutineLibrary.jmrID)
        XCTAssertEqual(try PlanningRoutineStore.load(from: defaults), baseline)
        var updated = baseline;
        updated.templates[0].name = "My work routine";
        updated.defaultWeekID = nil
        try PlanningRoutineStore.save(updated, baseline: baseline, to: defaults)
        XCTAssertEqual(try PlanningRoutineStore.load(from: defaults), updated)
        XCTAssertThrowsError(try PlanningRoutineStore.save(baseline, baseline: baseline, to: defaults))
        let retained = Data("retained damaged template bytes".utf8)
        defaults.set(retained, forKey: PlanningRoutineStore.key)
        XCTAssertThrowsError(try PlanningRoutineStore.load(from: defaults))
        XCTAssertThrowsError(try PlanningRoutineStore.save(updated, baseline: baseline, to: defaults))
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), retained)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningWeekTemplateCopiesResetCompletionAndRemapLinks
    /// @brief      Verify that planning Week Template Copies Reset Completion And Remap Links
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `source.collection.lists.firstIndex`.
    ///             Checks `XCTAssertTrue(template.collection.lists[index].archivedCards.isEmpty)`;
    ///             `XCTAssertTrue(template.collection.lists[index].cards[0].comments.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningWeekTemplateCopiesResetCompletionAndRemapLinks() throws
    {

        let calendar = routineCalendar()
        let sourceDate = try XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar))
        var source = DatedPlanningWeek.make(for: sourceDate, calendar: calendar)
        let mondayID = try XCTUnwrap(source.dayListIDs["2026-10-12"])
        let index = try XCTUnwrap(source.collection.lists.firstIndex
            {
                $0.id == mondayID
            })
        let attachment = KanbanAttachment(fileName: "drawing-preview.png", mediaKind: .photo)
        var drawing = attachment;
        drawing.drawingFileName = "drawing-strokes.drawing"
        let linked = KanbanChecklistItem(title: "Linked", isCompleted: true, content: .linkedCard(cardID: 20))
        source.collection.lists[index].cards = [
            KanbanCard(
                id: 10, word: "Work", listTitle: "Monday", isTitleChecked: true,
                checklists: [KanbanChecklist(title: "Steps", items: [linked], completedItemIndices: [0])],
                comments: [KanbanComment(author: "Me", body: "Old activity")], attachments: [drawing],
                coverAttachmentID: drawing.id, createdAt: sourceDate),
            KanbanCard(id: 20, word: "Supporting note", listTitle: "Monday", checklists: [], presentation: .note)
        ]
        source.collection.lists[index].archivedCards = [KanbanCard(id: 99, word: "Archive", listTitle: "Monday")]
        let template = try PlanningRoutineTemplate.capture(name: "Work", week: source, calendar: calendar)
        XCTAssertTrue(template.collection.lists[index].archivedCards.isEmpty)
        XCTAssertTrue(template.collection.lists[index].cards[0].comments.isEmpty)
        let targetDate = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: calendar))
        var target = DatedPlanningWeek.make(for: targetDate, calendar: calendar)
        let targetIndex = try XCTUnwrap(target.collection.lists.firstIndex
            {
                $0.id == target.dayListIDs["2026-11-02"]
            })
        target.collection.lists[targetIndex].cards = [
            KanbanCard(id: 100, word: "Already planned", listTitle: "Monday", checklists: [])
        ]
        let result = try PlanningTemplateApplication.apply(
            template, to: target, date: targetDate, calendar: calendar, mode: .add, now: targetDate)
        let copied = result.collection.lists[targetIndex].cards
        XCTAssertEqual(copied.map(\.word), ["Already planned", "Work", "Supporting note"])
        XCTAssertFalse(copied[1].isTitleChecked)
        XCTAssertFalse(copied[1].checklists[0].items[0].isCompleted)
        XCTAssertTrue(copied[1].checklists[0].completedItemIndices.isEmpty)
        XCTAssertNotEqual(copied[1].checklists[0].id, source.collection.lists[index].cards[0].checklists[0].id)
        XCTAssertNotEqual(copied[1].checklists[0].items[0].id, linked.id)
        if case .linkedCard(let id) = copied[1].checklists[0].items[0].content
        {

            XCTAssertEqual(id, copied[2].id)
        }
        else
        {

            XCTFail("Internal checklist links must target the copied card")
        }

        XCTAssertTrue(copied[1].comments.isEmpty)
        XCTAssertEqual(copied[1].createdAt, targetDate)
        XCTAssertEqual(copied[1].funParagraph, source.collection.lists[index].cards[0].funParagraph)
        XCTAssertEqual(copied[1].subtitle, source.collection.lists[index].cards[0].subtitle)
        XCTAssertNotEqual(copied[1].attachments?.first?.id, drawing.id)
        XCTAssertEqual(copied[1].attachments?.first?.drawingFileName, drawing.drawingFileName)
        XCTAssertEqual(copied[1].coverAttachmentID, copied[1].attachments?.first?.id)
        XCTAssertEqual(copied[2].presentation, .note)
        XCTAssertEqual(source.collection.lists[index].cards[0].isTitleChecked, true)
        var edited = template;
        edited.collection.lists[index].cards[0].word = "New routine"
        XCTAssertEqual(copied[1].word, "Work")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningTemplatesShiftDaysAcrossWeekStartAndDaylightSaving
    /// @brief      Verify that planning Templates Shift Days Across Week Start And Daylight Saving
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `source.collection.lists.firstIndex`.
    ///             Checks `XCTAssertEqual(PlanningDate.key(try XCTUnwrap(copy.startDate), calendar:
    ///             destinationCalendar), "2026-11-02")`; `XCTAssertEqual(destinationCalendar.component(.hour, from:
    ///             try XCTUnwrap(copy.startDate)), 9)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanningTemplatesShiftDaysAcrossWeekStartAndDaylightSaving() throws
    {

        let sourceCalendar = routineCalendar(firstWeekday: 1)
        let sourceDate = try XCTUnwrap(PlanningDate.date("2026-10-25", calendar: sourceCalendar))
        var source = DatedPlanningWeek.make(for: sourceDate, calendar: sourceCalendar)
        let monday = try XCTUnwrap(PlanningDate.date("2026-10-26", calendar: sourceCalendar))
        let mondayID = try XCTUnwrap(source.dayListIDs["2026-10-26"])
        let index = try XCTUnwrap(source.collection.lists.firstIndex
            {
                $0.id == mondayID
            })
        let start = try XCTUnwrap(sourceCalendar.date(bySettingHour: 9, minute: 30, second: 0, of: monday))
        let due = try XCTUnwrap(sourceCalendar.date(byAdding: .day, value: 1, to: start))
        source.collection.lists[index].cards = [
            KanbanCard(
                id: 7, word: "Timed", listTitle: "Monday", startDate: start, dueDate: due, checklists: [],
                startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
        ]
        let template = try PlanningRoutineTemplate.capture(name: "Week", week: source, calendar: sourceCalendar)
        let destinationCalendar = routineCalendar()
        let targetDate = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: destinationCalendar))
        let target = DatedPlanningWeek.make(for: targetDate, calendar: destinationCalendar)
        let applied = try PlanningTemplateApplication.apply(
            template, to: target, date: targetDate, calendar: destinationCalendar, mode: .add)
        let copy = try XCTUnwrap(applied.list(on: targetDate)?.cards.first)
        XCTAssertEqual(PlanningDate.key(try XCTUnwrap(copy.startDate), calendar: destinationCalendar), "2026-11-02")
        XCTAssertEqual(destinationCalendar.component(.hour, from: try XCTUnwrap(copy.startDate)), 9)
        XCTAssertEqual(destinationCalendar.component(.minute, from: try XCTUnwrap(copy.startDate)), 30)
        let dayTemplate = try PlanningRoutineTemplate.capture(
            name: "Vacation", week: source, day: monday, calendar: sourceCalendar)
        let saturday = try XCTUnwrap(PlanningDate.date("2026-10-31", calendar: destinationCalendar))
        let saturdayTarget = DatedPlanningWeek.make(for: saturday, calendar: destinationCalendar)
        let day = try PlanningTemplateApplication.apply(
            dayTemplate, to: saturdayTarget, date: saturday, calendar: destinationCalendar, mode: .add)
        let dayCopy = try XCTUnwrap(day.list(on: saturday)?.cards.first)
        XCTAssertEqual(PlanningDate.key(try XCTUnwrap(dayCopy.startDate), calendar: destinationCalendar), "2026-10-31")
        XCTAssertEqual(PlanningDate.key(try XCTUnwrap(dayCopy.dueDate), calendar: destinationCalendar), "2026-11-01")
        XCTAssertEqual(destinationCalendar.component(.hour, from: try XCTUnwrap(dayCopy.dueDate)), 9)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningTemplateScreensRenderWithoutSaving
    /// @brief      Verify that planning Template Screens Render Without Saving
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `UserDefaults.standard.data`. Checks `XCTAssertEqual(saves, 0)`;
    ///             `XCTAssertEqual(UserDefaults.standard.data(forKey: PlanningRoutineStore.key), before)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPlanningTemplateScreensRenderWithoutSaving() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let before = UserDefaults.standard.data(forKey: PlanningRoutineStore.key)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        var saves = 0
        for width in [393.0, 744.0]
        {

            window.frame = CGRect(x: 0, y: 0, width: width, height: 1024)
            let host = UIHostingController(rootView: PlanningTemplatesView())
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-routines-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("ROUTINE_RENDER=" + url.path)
        }

        let editor = UIHostingController(
            rootView: PlanningTemplateEditor(template: PlanningRoutineLibrary.seeded.templates[0])
            {
                _ in
                saves += 1;
                return true
            })
        window.rootViewController = editor;
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(UserDefaults.standard.data(forKey: PlanningRoutineStore.key), before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDailyPlanIsIncludedInExampleWorkspaceBackupAndRestore
    /// @brief      Verify that daily Plan Is Included In Example Workspace Backup And Restore
    /// @details    Exercises `folder.appendingPathComponent`, `DailyPlanStore.save`, `WeeklyReviewStore.save`. Checks
    ///             `XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))`; `XCTAssertNil(defaults.object(forKey:
    ///             WeeklyReviewStore.key))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDailyPlanIsIncludedInExampleWorkspaceBackupAndRestore() throws
    {

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "PlenactTests.DailyPlanBackup." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name);
            try? FileManager.default.removeItem(at: folder)
        }

        let store = FullMonthExampleStore(
            root: folder.appendingPathComponent("Backup"), documents: folder.appendingPathComponent("Documents"),
            support: folder.appendingPathComponent("Support"), domainName: name)
        var plan = DailyPlan(date: .now);
        plan.intention = "My original plan"
        _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        let originalBytes = try XCTUnwrap(defaults.data(forKey: DailyPlanStore.key))
        var weekly = WeeklyReviewRecord(date: .now, calendar: .current);

        weekly.highlights = "Original weekly reflection"
        _ = try WeeklyReviewStore.save(weekly, replacing: nil, to: defaults)
        let weeklyBytes = defaults.data(forKey: WeeklyReviewStore.key)
        let periodic = PeriodicReviewRecord(title: "Original checkpoint", start: .now, end: .now, calendar: .current)
        _ = try PeriodicReviewStore.save(periodic, replacing: nil, to: defaults)
        let periodicBytes = defaults.data(forKey: PeriodicReviewStore.key)
        try store.loadExample(FullMonthExample.make())
        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        XCTAssertNil(defaults.object(forKey: WeeklyReviewStore.key))
        XCTAssertNil(defaults.object(forKey: PeriodicReviewStore.key))
        plan.intention = "Example workspace plan"
        _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        try store.restoreUserData()
        XCTAssertEqual(defaults.data(forKey: PeriodicReviewStore.key), periodicBytes)
        XCTAssertEqual(defaults.data(forKey: WeeklyReviewStore.key), weeklyBytes)
        XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), originalBytes)
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans[plan.id]?.intention, "My original plan")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testStarterListTutorialsAreActionableAndOnlySeedTheThreeDefaultLists
    /// @brief      Verify that starter List Tutorials Are Actionable And Only Seed The Three Default Lists
    /// @details    Exercises `DefaultListTutorial.makeStarter`, `LabelLibraryStore.load`,
    ///             `card.descriptionOverride?.contains`. Checks
    ///             `XCTAssertEqual(starter.boardAppearance?.bannerBackground, expected)`;
    ///             `XCTAssertNil(list.appearance?.background)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testStarterListTutorialsAreActionableAndOnlySeedTheThreeDefaultLists() throws
    {

        let titles = ["On the Table", "In the Queue", "Scheduled"]
        for title in titles
        {

            let starter = DefaultListTutorial.makeStarter(title: title)
            let list = try XCTUnwrap(starter.lists.first)
            let card = try XCTUnwrap(DefaultListTutorial.guidance(for: title))
            let expected: ItemAccent = title == "On the Table" ? .coral : (title == "In the Queue" ? .teal : .graphite)
            XCTAssertEqual(starter.boardAppearance?.bannerBackground, expected)
            XCTAssertNil(list.appearance?.background)
            XCTAssertTrue(list.cards.isEmpty)
            XCTAssertEqual(card.presentation, .note)
            XCTAssertTrue(card.isEditingLocked)
            XCTAssertFalse(card.isTitleChecked)
            XCTAssertNil(card.startDate)
            XCTAssertNil(card.dueDate)
            XCTAssertTrue(card.members.isEmpty)
            XCTAssertEqual(card.labelIDs, [LabelLibraryStore.load().referenceLabelID])
            XCTAssertEqual(card.subtitleOverride, "'\(title)', A quick guide to this List")
            XCTAssertEqual(card.checklists.first?.title, "Try it")
            XCTAssertEqual(card.checklists.first?.items.count, 3)
            XCTAssertFalse(card.descriptionOverride?.contains("yours to edit") == true)
            let restored = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(starter))
            XCTAssertEqual(restored, starter)
        }

        for title in ["Shopping", "Reminders", "Up for Brew", "Misc", "My custom list"]
        {

            XCTAssertTrue(DefaultListTutorial.makeStarter(title: title).lists[0].cards.isEmpty)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryWeekExampleCreatesIndependentDraftWithoutReplacingWeek
    /// @brief      Verify that library Week Example Creates Independent Draft Without Replacing Week
    /// @details    Exercises `PersonalCollection.exampleWeek`. Checks `XCTAssertEqual(first.kind, .board)`;
    ///             `XCTAssertEqual(first.lists, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLibraryWeekExampleCreatesIndependentDraftWithoutReplacingWeek() throws
    {

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


    ///
    /// @fcn        PlenactBoardDocumentTests.testMixedListTemplatesRetainFormatsAndCreateIndependentDrafts
    /// @brief      Verify that mixed List Templates Retain Formats And Create Independent Drafts
    /// @details    Exercises `template.makeCollection`, `cards.map`, `cards.allSatisfy`. Checks
    ///             `XCTAssertNotEqual(draft.id, second.id)`; `XCTAssertNotEqual(draft.title, template.rawValue)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testMixedListTemplatesRetainFormatsAndCreateIndependentDrafts() throws
    {

        for template in MixedListTemplate.allCases
        {

            let draft = template.makeCollection(existingTitles: [template.rawValue])
            let second = template.makeCollection(existingTitles: [])
            XCTAssertNotEqual(draft.id, second.id)
            XCTAssertNotEqual(draft.title, template.rawValue)
            XCTAssertEqual(draft.lists.count, 1)
            let cards = draft.lists[0].cards
            XCTAssertEqual(Set(cards.map(\.displayFormat)), Set(ItemDisplayFormat.allCases))
            XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
            XCTAssertTrue(cards.allSatisfy
                {
                    $0.listTitle == draft.title && $0.startDate == nil && $0.dueDate == nil
                })
            XCTAssertTrue(cards.filter
                {
                    $0.displayFormat == .note
                } .allSatisfy
                {
                    $0.presentation == .note
                })
            let picture = try XCTUnwrap(cards.first
                {
                    $0.displayFormat == .picture
                })
            XCTAssertEqual(picture.coverAttachment?.exampleImage, template.illustration)
            XCTAssertTrue(CardAttachmentStore.fileNames(in: draft.lists).isEmpty)
            XCTAssertEqual(try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(draft)), draft)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRichBoardExamplesRemainIndependentAndResolveTheirInternalLinks
    /// @brief      Verify that rich Board Examples Remain Independent And Resolve Their Internal Links
    /// @details    Exercises `PlanningDate.date`, `example.makeCollection`, `draft.lists.flatMap`. Checks
    ///             `XCTAssertEqual(draft.kind, .board)`; `XCTAssertNotEqual(draft.title, example.rawValue)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testRichBoardExamplesRemainIndependentAndResolveTheirInternalLinks() throws
    {

        let now = try XCTUnwrap(PlanningDate.date("2026-10-13"))
        for example in PersonalBoardExample.allCases
        {

            let draft = example.makeCollection(existingTitles: [example.rawValue], now: now)
            XCTAssertEqual(draft.kind, .board)
            XCTAssertNotEqual(draft.title, example.rawValue)
            XCTAssertNotNil(draft.boardAppearance)
            XCTAssertFalse(draft.collectionDescription?.isEmpty ?? true)
            let all = draft.lists.flatMap(\.allCards)
            let ids = Set(all.map(\.id))
            XCTAssertEqual(ids.count, all.count)
            XCTAssertEqual(try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(draft)), draft)
            XCTAssertEqual(Set(all.map(\.displayFormat)), Set(ItemDisplayFormat.allCases))
            XCTAssertTrue(draft.lists.contains(where: \.isArchived))
            XCTAssertTrue(draft.lists.contains
                {
                    !$0.archivedCards.isEmpty
                })
            XCTAssertFalse(draft.savedCardIDs.isEmpty)
            for card in all
            {

                if let cover = card.coverAttachment
                {
                    XCTAssertNotNil(cover.exampleImage?.url)
                }

                for item in card.checklists.flatMap(\.items)
                {

                    if case .linkedCard(let target) = item.content
                    {

                        XCTAssertTrue(ids.contains(target))
                        XCTAssertEqual(item.linkedCollectionID, draft.id)
                    }

                }

            }

            let active = draft.lists.filter
            {
                !$0.isArchived
            }

            if example == .life
            {

                XCTAssertEqual(active.count, 12)
                XCTAssertEqual(active.prefix(3).map
                    {
                        $0.cards.count
                    }, [30, 28, 26])
                XCTAssertGreaterThan(active.flatMap(\.cards).filter
                    {
                        $0.coverAttachment != nil
                    } .count, 60)
            }

            XCTAssertNotEqual(draft.id, example.makeCollection(existingTitles: [], now: now).id)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReactionsSurviveLocationChangesAndArchiveButNotFreshTemplates
    /// @brief      Verify that reactions Survive Location Changes And Archive But Not Fresh Templates
    /// @details    Exercises `card.replacingLocation`, `list.archiveCard`, `list.restoreArchivedCard`. Checks
    ///             `XCTAssertEqual(relocated.reactions, card.reactions)`; `XCTAssertEqual(relocated.createdAt,
    ///             card.createdAt)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testReactionsSurviveLocationChangesAndArchiveButNotFreshTemplates() throws
    {

        let reaction = ItemEmojiReaction(emoji: "💪", authorID: UUID())
        let card = KanbanCard(
            id: 1, word: "A meaningful step", listTitle: "Monday", checklists: [], createdAt: .now,
            reactions: [reaction])
        let relocated = card.replacingLocation(id: 99, listTitle: "In the Queue")
        XCTAssertEqual(relocated.reactions, card.reactions)
        XCTAssertEqual(relocated.createdAt, card.createdAt)
        var list = KanbanList(id: 0, title: "Monday", cards: [card])
        list.archiveCard(id: card.id)
        XCTAssertEqual(list.archivedCards.first?.reactions, [reaction])
        list.restoreArchivedCard(id: card.id)
        XCTAssertEqual(list.cards.first?.reactions, [reaction])
        var week = DatedPlanningWeek.make(for: .now)
        week.collection.lists[0].cards = [card]
        let template = try PlanningRoutineTemplate.capture(name: "Fresh work", week: week, calendar: .current)
        XCTAssertTrue(template.collection.lists.flatMap(\.cards).allSatisfy
            {
                $0.reactions == nil
            })
        XCTAssertEqual(week.collection.lists[0].cards[0].reactions, [reaction])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryExamplesLayoutDoesNotLoadOrRestoreWeekOnPresentation
    /// @brief      Verify that library Examples Layout Does Not Load Or Restore Week On Presentation
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Uses the fixture and assertions below to verify library Examples Layout Does
    ///             Not Load Or Restore Week On Presentation.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLibraryExamplesLayoutDoesNotLoadOrRestoreWeekOnPresentation() async throws
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

        for hasUndo in [false, true]
        {

            for textSize in [DynamicTypeSize.large, .accessibility3]
            {

                let chooser = PersonalListExamplesView(
                    onLoadExampleWeek:
                    {

                        XCTFail("Opening examples must not replace Week");
                        return false
                    },
                    onUndoExampleWeek:
                    {

                        XCTFail("Opening examples must not restore Week");
                        return false
                    },
                    hasUndoableWeek: hasUndo,
                    onSelect:
                    {
                        _ in
                        XCTFail("Opening examples must not create a personal List")
                    }
                )
                let controller = UIHostingController(rootView: chooser.environment(\.dynamicTypeSize, textSize))
                let size = CGSize(width: 393, height: 852)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                let image = UIGraphicsImageRenderer(size: size).image
                {
                    _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }

                let attachment = XCTAttachment(image: image)
                attachment.name = "Library-Examples-undo-\(hasUndo)-\(textSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testQuickCaptureTemplatesPreserveTitleAndCreateIndependentRecords
    /// @brief      Verify that quick Capture Templates Preserve Title And Create Independent Records
    /// @details    Exercises `template.draftTitle`, `list.makeItem`, `first.checklists.flatMap(\.items).map`. Checks
    ///             `XCTAssertEqual(template.draftTitle(capturedTitle: "My own title"), "My own title")`;
    ///             `XCTAssertEqual(first.presentation, template.presentation)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testQuickCaptureTemplatesPreserveTitleAndCreateIndependentRecords() throws
    {

        let list = KanbanList(id: 4, title: "Thursday", cards: [])
        for template in QuickCaptureTemplate.allCases
        {

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
            XCTAssertTrue(
                Set(first.checklists.flatMap(\.items).map(\.id))
                .isDisjoint(with: second.checklists.flatMap(\.items).map(\.id)))
            XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(first)), first)
        }

        var noteList = list
        noteList.newItemPresentation = .note
        XCTAssertEqual(
            noteList.makeItem(id: 12, title: "Card", presentationOverride: .card, actions: []).presentation, .card)
        XCTAssertEqual(
            list.makeItem(id: 13, title: "Note", presentationOverride: .note, actions: []).presentation, .note)
        XCTAssertTrue(list.cards.isEmpty)
        XCTAssertEqual(QuickCaptureTemplate.blankCard.draftTitle(capturedTitle: ""), "")
        XCTAssertEqual(QuickCaptureTemplate.blankNote.draftTitle(capturedTitle: ""), "")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testQuickCreationSwitchKeepsTitleAndTemplateWriting
    /// @brief      Verify that quick Creation Switch Keeps Title And Template Writing
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertTrue(textValues().contains("Keep this idea"))`;
    ///             `XCTAssertTrue(textValues().contains(QuickCaptureTemplate.smallPlan.body))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testQuickCreationSwitchKeepsTitleAndTemplateWriting() async throws
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

        let host = UIHostingController(
            rootView: QuickNoteComposer(
                lists: .constant([KanbanList(id: 4, title: "Ideas", cards: [])]),
                initialListID: 4, initialTitle: "Keep this idea", template: .smallPlan
            )
            {
                _, _, _, _, _, _ in
                XCTFail("Switching type must not create content")
            })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host;
        window.makeKeyAndVisible()


        ///
        /// @fcn        PlenactBoardDocumentTests.testQuickCreationSwitchKeepsTitleAndTemplateWriting.descendants
        /// @brief      Find descendants in the hosted view hierarchy
        /// @details    Recursively inspects native subviews. Returns all collected matches in hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIView]) resulting values in the ordering described above
        ///
        func descendants(_ view: UIView) -> [UIView]
        {
            [view] + view.subviews.flatMap
            {
                descendants($0)
            }

        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testQuickCreationSwitchKeepsTitleAndTemplateWriting.textValues
        /// @brief      Prepare text values for the enclosing regression test
        /// @details    Supplies the local fixture for quick Creation Switch Keeps Title And Template Writing. Uses
        ///             `descendants(host.view).compactMap`.
        ///
        /// @return     ([String]) resulting values in the ordering described above
        ///
        func textValues() -> [String]
        {

            descendants(host.view).compactMap
            {
                view in
                if let field = view as? UITextField
                {
                    return field.text
                }

                if let text = view as? UITextView
                {
                    return text.text
                }

                return nil
            }

        }

        for index in [1, 0]
        {

            try await Task.sleep(for: .milliseconds(180))
            host.view.layoutIfNeeded()
            let control = try XCTUnwrap(descendants(host.view).compactMap
                {
                    $0 as? UISegmentedControl
                } .first)
            control.selectedSegmentIndex = index
            control.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(180))
            host.view.layoutIfNeeded()
            XCTAssertTrue(textValues().contains("Keep this idea"))
            XCTAssertTrue(textValues().contains(QuickCaptureTemplate.smallPlan.body))
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedTemplateComposerPrefillsTitleWithoutCreatingRecords
    /// @brief      Verify that hosted Template Composer Prefills Title Without Creating Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Uses the fixture and assertions below to verify hosted Template Composer
    ///             Prefills Title Without Creating Records.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testHostedTemplateComposerPrefillsTitleWithoutCreatingRecords() async throws
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


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedTemplateComposerPrefillsTitleWithoutCreatingRecords.fields
        /// @brief      Find fields in the hosted view hierarchy
        /// @details    Recursively inspects native subviews. Returns all collected matches in hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIView]) resulting values in the ordering described above
        ///
        func fields(in view: UIView) -> [UIView]
        {

            let editable = (view is UITextField || view is UITextView) ? [view] : []
            return editable + view.subviews.flatMap
            {
                fields(in: $0)
            }

        }

        let draftKey = "InlineComposerTest." + UUID().uuidString
        defer
        {
            ListCreationDraft.clear(key: draftKey)
        }

        for template in [QuickCaptureTemplate.smallPlan, .idea, nil]
        {

            ListCreationDraft(title: "Older saved title", subtitle: "Retained subtitle", description: "Retained body")
            .save(key: draftKey)
            let controller = UIHostingController(
                rootView: QuickNoteComposer(
                    lists: .constant([KanbanList(id: 4, title: "Thursday", cards: [])]),
                    initialListID: 4, initialTitle: "Captured thought", draftKey: draftKey, template: template
                )
                {
                    _, _, _, _, _, _ in
                    XCTFail("Reviewing a template must not create a record")
                })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(
                fields(in: controller.view).contains
                {

                    ($0 as? UITextField)?.text == "Captured thought" || ($0 as? UITextView)?.text == "Captured thought"
                })
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testOfflineLibraryContains400DistinctBundledIllustrations()
    /// @brief      Verify the complete eight-category library is shipped with the app
    /// @details    Checks actual app resources, exact canvas dimensions, distinct bytes, and total
    ///             size. Does not enable covers or write personal media files
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Missing bundle resources, image decoding, or file-read errors
    ///
    func testOfflineLibraryContains400DistinctBundledIllustrations() throws
    {


        let categories = CoverCategory.allCases /* Available attachment categories */

        XCTAssertEqual(categories.count, 8)

        for category in categories
        {


            XCTAssertEqual(category.images.count, 50, category.rawValue)
        }


        let images = categories.flatMap(\.images)  /* Synthetic image fixtures         */
        let names = images.map(\.rawValue)         /* Bundled illustration asset names */

        XCTAssertEqual(names.count, 400)
        XCTAssertEqual(Set(names).count, 400)
        XCTAssertEqual(Set(images), Set(ExampleCoverImage.allCases))

        var distinctImages: Set<Data> = []  /* Distinct image fixtures  */
        var totalBytes = 0                  /* Combined image-data size */

        for name in names
        {


            let url = try XCTUnwrap(
                Bundle.main.url( /* URL fixture for the request */

                    forResource: name, withExtension: "png", subdirectory: "CardCoverImages"

                ), "Missing bundled illustration: \(name)")

            let bytes = try Data(contentsOf: url) /* Bundled illustration bytes   */
            let image = try XCTUnwrap(
                UIImage(data: bytes)?.cgImage, "Unreadable illustration: \(name)") /* Decoded cropped-avatar image */

            XCTAssertEqual(image.width, 960, name)
            XCTAssertEqual(image.height, 480, name)
            XCTAssertTrue(distinctImages.insert(bytes).inserted, "Duplicate illustration: \(name)")

            totalBytes += bytes.count
        }


        XCTAssertEqual(distinctImages.count, 400)
        XCTAssertLessThan(totalBytes, 150_000_000, "Keep offline artwork within the 150 MB budget")

        let directory = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent(
                        "CardCoverImages") /* Synthetic photo directory */

        let bundledNames = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) /* Bundled example-photo names */
        .filter
        {
            $0.pathExtension == "png"
        }
        .map
        {
            $0.deletingPathExtension().lastPathComponent
        }


        XCTAssertEqual(Set(bundledNames), Set(names))
        XCTAssertEqual(Array(ExampleCoverImage.allCases.prefix(3)), [.garden, .mountains, .workspace])
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
    func testPersonalListExamplesContainSafeIndependentCards() throws
    {


        XCTAssertEqual(
            PersonalListExample.allCases.map(\.rawValue),
            [
                                "On the Table", "In the Queue", "Scheduled", "Shopping", "Up for Brew", "Misc"
            ])

        for example in PersonalListExample.allCases
        {


            let collection = example.makeCollection(existingTitles: []) /* Collection state under verification */

            XCTAssertEqual(collection.kind, .list)
            XCTAssertEqual(collection.lists.count, 1)
            XCTAssertTrue(collection.isActive)
            XCTAssertTrue(collection.savedCardIDs.isEmpty)
            XCTAssertGreaterThanOrEqual(collection.cardCount, 5)
            XCTAssertLessThanOrEqual(collection.cardCount, 20)

            let cards = collection.lists[0].cards /* Card records under inspection */

            XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
            XCTAssertEqual(Set(cards.map(\.word)).count, cards.count)

            for card in cards
            {


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

                for attachment in card.attachments ?? []
                {


                    XCTAssertNotNil(attachment.exampleImage)
                    XCTAssertNil(attachment.fileName)
                    XCTAssertNil(attachment.url)
                }


                if card.coverAttachmentID != nil
                {


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
    func testExampleDraftsDoNotWriteOrReplaceExistingCollections() throws
    {


        let suite = "Plenact.PersonalExampleTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let week = try JSONEncoder().encode(SampleData.lists) /* Archived weekly-board fixture */

        defaults.set(week, forKey: "Plenact.Board.v1")

        var retained = PersonalCollection(
            title: "Shopping", kind: .list) /* Existing collection preserved during example drafting */

        retained.isArchived = true
        retained.lists[0].cards = [KanbanCard(id: 99, word: "Existing", listTitle: "Shopping", checklists: [])]
        retained.savedCardIDs = [99]

        try PersonalCollectionStore.saveChecked([retained], to: defaults)

        let originalBytes = defaults.data(
            forKey: "Plenact.PersonalCollections.v1") /* Serialized bytes used by the fixture */
        let first = PersonalListExample.shopping.makeCollection(existingTitles: [retained.title]
        ) /* First value in the comparison        */
        let second = PersonalListExample.shopping.makeCollection(existingTitles: [retained.title, first.title]
        ) /* Second value in the comparison       */

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.title, "Shopping (2)")
        XCTAssertEqual(second.title, "Shopping (3)")
        XCTAssertEqual(defaults.data(forKey: "Plenact.PersonalCollections.v1"), originalBytes)

        var renamed = first /* Value after renaming */

        renamed.rename(to: "My shopping")

        XCTAssertTrue(renamed.lists[0].cards.allSatisfy
            {
                $0.listTitle == "My shopping"
            })
        XCTAssertEqual(renamed.lists[0].cards.map(\.id), first.lists[0].cards.map(\.id))

        try PersonalCollectionStore.saveChecked([retained, renamed], to: defaults)

        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [retained, renamed])
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), week)
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
    func testExampleLoadUndoSnapshotPersistsAndClears() throws
    {


        let suite = "Plenact.ExampleLoadUndoTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        var lists = Array(SampleData.lists.prefix(2))
        var archived = KanbanList(id: 99, title: "Previous Week", cards: lists[1].cards)
        archived.isArchived = true
        lists.append(archived)
        lists[0].archiveCard(id: lists[0].cards[0].id)
        let snapshot = ExampleLoadUndoSnapshot(
            lists: lists, todayListID: lists[1].id) /* Persisted snapshot under verification */

        XCTAssertTrue(ExampleLoadUndoStore.save(lists: lists, todayListID: lists[1].id, to: defaults))
        XCTAssertEqual(ExampleLoadUndoStore.load(from: defaults), snapshot)

        ExampleLoadUndoStore.clear(from: defaults)

        XCTAssertNil(ExampleLoadUndoStore.load(from: defaults))
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
    func testStarterBoardDocumentRoundTrips() throws
    {


        let document = PlenactBoardDocument( /* Synthetic shared Board fixture */
            lists: SampleData.lists,
            labelLibrary: .starter
        )
        let encoded = try JSONEncoder().encode(document)                                  /* Versioned JSON */
        let decoded = try JSONDecoder().decode(PlenactBoardDocument.self, from: encoded)  /* Restored Board */

        XCTAssertEqual(decoded, document)
        XCTAssertNil(decoded.validationMessage)
        XCTAssertEqual(decoded.lists.map(\.title), SampleData.listTitles)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSampleDataSeedMapsKnownStarterAssigneeToJim()
    /// @brief      Map only the known SampleData assignee to Jim's registered identity
    /// @details    Verifies the seed keeps weekday content and labels while leaving local sample
    ///             data unchanged
    ///
    /// @return     (Void) succeeds when the versioned seed remains valid and linked to Jim
    ///
    func testSampleDataSeedMapsKnownStarterAssigneeToJim()
    {


        let jim = PlenactRemoteUser( /* Authenticated editor identity for the seed */
            userID: "fb13a9ee-9107-47c3-bb4f-dff07fe57eba",
            username: "jim",
            displayName: "Jim",
            accountRole: "board_editor"
        )
        let document = PlenactAPIClient.sampleDataDocument(for: jim)                /* Seed transformed for Jim */
        let seededAssignments = document.lists.flatMap(\.cards).flatMap(\.members)  /* All seed assignments     */

        XCTAssertNil(document.validationMessage)
        XCTAssertEqual(document.lists.map(\.title), SampleData.listTitles)
        XCTAssertEqual(document.labelLibrary, .starter)
        XCTAssertTrue(
            document.lists.flatMap(\.allCards).allSatisfy
            {


                $0.coverAttachmentID == nil && $0.attachments == nil && $0.listDisplayFormat == nil
            })

        XCTAssertEqual(seededAssignments.count, SampleData.lists.flatMap(\.cards).flatMap(\.members).count)
        XCTAssertTrue(
            seededAssignments.allSatisfy
            {

                $0.kind == .registeredUser && $0.userID == jim.userID && $0.displayName == jim.displayName
            })
        XCTAssertEqual(SampleData.lists[0].cards[0].members[0].kind, .manual)
    }

}
