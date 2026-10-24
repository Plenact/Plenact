// --------------------------------------------------------------------------------------------------
// @file       BoardInteractionTests3.swift
// @brief      Board Interaction regression tests3
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
/// BoardInteraction regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMapSearchTracksQueriesSelectionAndFailureStates
    /// @brief      Keep map-search results distinct from an accepted Card location
    /// @details    Uses a deterministic provider to verify normalization, no implicit selection,
    ///             query edits, empty results, failures, and clearing without any Card persistence.
    /// @return     (Void) records query, selection, and feedback regressions
    ///
    @MainActor
    func testCardMapSearchTracksQueriesSelectionAndFailureStates() async
    {

        let place = CardLocationSearchResult(name: "Coffee Shop", address: "123 Main St", latitude: 41.88, longitude: -87.63)
        var queries: [String] = []
        let model = CardLocationSearchModel(query: "  Coffee \n")
        {

        query, _ in
            queries.append(query)
            if query == "Failure"
            {

                throw NSError(domain: "MapSearchFixture", code: 1)
            }

            return query == "Coffee" ? [place] : []
        }

        await model.search()
        XCTAssertEqual(queries, ["Coffee"])
        XCTAssertEqual(model.phase, .results)
        XCTAssertEqual(model.results, [place])
        XCTAssertNil(model.selectedResult, "Search must not choose a result without user selection")
        model.selectedID = place.id
        XCTAssertEqual(model.selectedResult?.savedLocation, "Coffee Shop, 123 Main St")
        model.query = "No matches"
        XCTAssertNil(model.selectedResult)
        XCTAssertTrue(model.results.isEmpty)
        await model.search()
        XCTAssertEqual(model.phase, .empty)
        model.query = "Failure"
        await model.search()
        XCTAssertEqual(model.phase, .failed)
        model.query = " \n "
        await model.search()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(queries.count, 3, "Blank text must not make a service request")
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMapSearchIgnoresResponsesFromAnOlderQuery
    /// @brief      Prevent a slow earlier search from replacing current matches
    /// @details    Completes injected requests in reverse order and verifies selected current
    ///             results remain intact; leaving the search invalidates the selection.
    /// @return     (Void) records stale-response and cancellation regressions
    ///
    @MainActor
    func testCardMapSearchIgnoresResponsesFromAnOlderQuery() async
    {

        let oldStarted = expectation(description: "Older request started")
        let newStarted = expectation(description: "Newer request started")
        var pending: [String: CheckedContinuation<[CardLocationSearchResult], Error>] = [:]
        let model = CardLocationSearchModel(query: "Old")
        {

        query, _ in
            try await withCheckedThrowingContinuation
            {

                pending[query] = $0
                if query == "Old"
                {

                    oldStarted.fulfill()
                }

                else
                {

                    newStarted.fulfill()
                }

            }

        }

        let oldTask = Task
        {

            await model.search()
        }

        await fulfillment(of: [oldStarted], timeout: 1)
        model.query = "New"
        let newTask = Task
        {

            await model.search()
        }

        await fulfillment(of: [newStarted], timeout: 1)
        let current = CardLocationSearchResult(name: "New place", address: "New address", latitude: 40, longitude: -80)
        pending["New"]?.resume(returning: [current])
        await newTask.value
        model.selectedID = current.id
        pending["Old"]?.resume(returning: [CardLocationSearchResult(
                    name: "Old place", address: "Old address", latitude: 41, longitude: -81)])
        await oldTask.value
        XCTAssertEqual(model.results, [current])
        XCTAssertEqual(model.selectedResult, current)
        model.cancel()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.selectedResult)
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMapSearchTaskCancellationDiscardsPendingResults
    /// @brief      Return to idle when the active search task is cancelled
    /// @details    An injected provider intentionally finishes after cancellation, proving that
    ///             its late response cannot become selectable or leave a permanent loading state.
    /// @return     (Void) records cancelled-request state regressions
    ///
    @MainActor
    func testCardMapSearchTaskCancellationDiscardsPendingResults() async
    {

        let started = expectation(description: "Search started")
        var pending: CheckedContinuation<[CardLocationSearchResult], Error>?
        let model = CardLocationSearchModel(query: "Place")
        {

        _, _ in
            try await withCheckedThrowingContinuation
            {

                pending = $0
                started.fulfill()
            }

        }

        let task = Task
        {

            await model.search()
        }

        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        pending?.resume(returning: [CardLocationSearchResult(
                    name: "Cancelled place", address: "Address", latitude: 40, longitude: -80)])
        await task.value
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.selectedResult)
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMapSearchSelectionBuildsUsefulPlaceText
    /// @brief      Retain a place and distinguishing address without duplicated display text
    /// @details    Covers named places, address-only results, duplicate names, and coordinate
    ///             fallback so the existing preferred-provider links can reopen the chosen place.
    /// @return     (Void) records location-text formatting regressions
    ///
    func testCardMapSearchSelectionBuildsUsefulPlaceText()
    {

        XCTAssertEqual(CardLocationSearchResult(name: "Library", address: "12 Main St", latitude: 1, longitude: 2)
            .savedLocation, "Library, 12 Main St")
        XCTAssertEqual(CardLocationSearchResult(name: "12 MAIN ST", address: "12 Main St", latitude: 1, longitude: 2)
            .savedLocation, "12 MAIN ST")
        XCTAssertEqual(CardLocationSearchResult(name: " ", address: "12 Main St", latitude: 1, longitude: 2)
            .savedLocation, "12 Main St")
        XCTAssertEqual(CardLocationSearchResult(name: "", address: "", latitude: 1, longitude: 2)
            .savedLocation, "1.000000, 2.000000")
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testCardMapSearchRendersResultsWithoutAcceptingOrSaving
    /// @brief      Render the searchable map with a deterministic place and explicit selection
    /// @details    Does not contact the live search service, launch another app, or accept a
    ///             result during rendering. Captures a native map picker preview for visual review.
    /// @return     (Void) records unintended selection callbacks or map-picker rendering failures
    /// @throws     Propagates missing simulator scene and preview image errors
    ///
    @MainActor
    func testCardMapSearchRendersResultsWithoutAcceptingOrSaving() async throws
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
            previous?.makeKeyAndVisible()
        }

        let place = CardLocationSearchResult(name: "Coffee on Main", address: "123 Main St, Chicago, IL",
            latitude: 41.8827, longitude: -87.6233)
        let model = CardLocationSearchModel(query: "Coffee")
        {

        _, _ in
            [place]
        }

        var selections: [String] = []
        let host = UIHostingController(rootView: NavigationStack
            {

                CardLocationSearchView(query: "Coffee", model: model)
                {

                    selections.append($0)
                }

            })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0 ..< 60
        {

            if model.results == [place]
            {

                break
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(model.results, [place])
        model.selectedID = place.id
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.selectedResult, place)
        XCTAssertTrue(selections.isEmpty, "Selecting a result must not accept it until Use this location")
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {

        _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-card-location-map-search.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("CARD_MAP_SEARCH_RENDER=" + url.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardLocationsPersistCopyAndDecodeLegacyRecords
    /// @brief      Retain optional place text across storage and destination-local copies
    /// @details    Legacy records have no location; outer whitespace is trimmed and blank values
    ///             remain absent. Relocation retains the place without inventing new content.
    /// @return     (Void) records location compatibility and retention regressions
    /// @throws     Propagates fixture encoding and decoding errors
    ///
    func testCardLocationsPersistCopyAndDecodeLegacyRecords() throws
    {

        let card = KanbanCard(id: 1201, word: "Meet for coffee", listTitle: "Today",
            location: " \n Café & Bakery, 12 Main St \n")
        XCTAssertEqual(card.location, "Café & Bakery, 12 Main St")
        let encoded = try JSONEncoder().encode(card)
        XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: encoded), card)
        XCTAssertEqual(card.replacingLocation(id: 1202, listTitle: "Tomorrow").location, card.location)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "location")
        XCTAssertNil(try JSONDecoder().decode(KanbanCard.self,
                from: JSONSerialization.data(withJSONObject: legacy)).location)
        XCTAssertNil(KanbanCard(id: 1, word: "Empty", listTitle: "Today", location: " \n ").location)
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testCardLocationHistoryAndLocksUseNormalContentRules
    /// @brief      Record saved place changes and enforce the existing Card lock
    /// @details    Adding and removing a location use ordinary List history. A locked Card cannot
    ///             accept a place edit, and an in-place date change preserves live location text.
    /// @return     (Void) records content-history, lock, and schedule-merge regressions
    ///
    func testCardLocationHistoryAndLocksUseNormalContentRules()
    {

        let original = KanbanCard(id: 1301, word: "Gym", listTitle: "Today")
        var list = KanbanList(id: 13, title: "Today", cards: [original])
        var located = original
        located.location = "123 Fitness Lane"
        list.cards[0] = located
        XCTAssertTrue(list.cards[0].editHistory?.last?.changes.contains
            {
                $0.field == "location"
            }
            == true)
        XCTAssertTrue(list.cards[0].editHistory?.last?.summary.contains("Location") == true)
        let copied = list.cards[0].replacingLocation(id: 1302, listTitle: "Tomorrow")
        XCTAssertEqual(copied.location, located.location)
        XCTAssertEqual(copied.editHistory, list.cards[0].editHistory)
        var lists = [list]
        var dateEdit = original
        dateEdit.startDate = .now
        dateEdit.startDateKind = .time
        XCTAssertTrue(TodayFocusDateUpdate.apply(dateEdit, isStart: true, to: &lists))
        XCTAssertEqual(lists[0].cards[0].location, located.location)
        var locked = lists[0].cards[0]
        locked.isEditingLocked = true
        var edited = locked
        edited.location = "Different place"
        XCTAssertFalse(locked.acceptsContentUpdate(edited))
        var removed = list.cards[0]
        removed.location = nil
        list.cards[0] = removed
        XCTAssertNil(list.cards[0].location)
        XCTAssertEqual(list.cards[0].editHistory?.count, 2)
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testPreferredMapsAppDefaultsAndPersistsWithoutAProfile
    /// @brief      Default fresh and older settings to Apple Maps and retain Google selection
    /// @details    Uses an isolated preference domain and checks Codable persistence without
    ///             creating a profile or modifying the running app's preferences.
    /// @return     (Void) records provider default and storage regressions
    /// @throws     Propagates decoding and isolated-domain creation errors
    ///
    func testPreferredMapsAppDefaultsAndPersistsWithoutAProfile() throws
    {

        XCTAssertEqual(LocalProfilePreferences().preferredMapsApp, .apple)
        XCTAssertEqual(try JSONDecoder().decode(LocalProfilePreferences.self,
                from: Data("{}".utf8)).preferredMapsApp, .apple)
        let suite = "MapsPreference." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {

            defaults.removePersistentDomain(forName: suite)
        }

        let preferences = LocalProfilePreferences(preferredMapsApp: .google)
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults).preferredMapsApp, .google)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testLocationLinksEncodePlaceTextWithoutRequestingDirections
    /// @brief      Keep every place query inside the selected provider's official search URL
    /// @details    Covers Unicode, literal plus signs, reserved punctuation, multiline addresses,
    ///             empty values, and text resembling a URL without changing the destination host.
    /// @return     (Void) records query-encoding and place-only routing regressions
    /// @throws     Propagates missing URL and component errors
    ///
    func testLocationLinksEncodePlaceTextWithoutRequestingDirections() throws
    {

        for provider in PreferredMapsApp.allCases
        {

            XCTAssertNil(provider.placeURL(for: nil))
            XCTAssertNil(provider.placeURL(for: " \n "))
            for place in ["Café + Tea & Books #2", "123 Main St\nChicago, IL", "https://example.com/?x=1&y=2"]
            {

                let url = try XCTUnwrap(provider.placeURL(for: place))
                let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
                XCTAssertEqual(components.scheme, "https")
                XCTAssertEqual(components.host, provider == .apple ? "maps.apple.com" : "www.google.com")
                let parameters = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map
                    {
                        ($0.name, $0.value ?? "")
                    })
                XCTAssertEqual(parameters[provider == .apple ? "q" : "query"], place)
                XCTAssertNil(parameters["daddr"])
                XCTAssertNil(parameters["saddr"])
                XCTAssertNil(parameters["destination"])
                XCTAssertNil(parameters["travelmode"])
                if provider == .google
                {

                    XCTAssertEqual(components.path, "/maps/search/")
                    XCTAssertEqual(parameters["api"], "1")
                }

                XCTAssertTrue(url.absoluteString.contains("%2B") || !place.contains("+"))
            }

        }

    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testLocationEditorAndRowsRenderWithoutSavingOrLaunchingMaps
    /// @brief      Render the native editor and saved-place controls without side effects
    /// @details    Exercises empty, saved, and read-only rows plus the provider settings picker.
    ///             Captures a preview for visual review and asserts rendering never invokes actions.
    /// @return     (Void) records unintended mutations or external map launches
    /// @throws     Propagates simulator scene and preview image errors
    ///
    @MainActor
    func testLocationEditorAndRowsRenderWithoutSavingOrLaunchingMaps() async throws
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
            previous?.makeKeyAndVisible()
        }

        var saves = 0
        var edits = 0
        var opens = 0
        let rows = NavigationStack
        {

            Form
            {

                Section("Details")
                {

                    CardLocationRow(location: "Café & Bakery, 12 Main St", canEdit: true)
                    {
                        edits += 1
                    }

                    CardLocationRow(location: nil, canEdit: true)
                    {
                        edits += 1
                    }

                    CardLocationRow(location: "A saved read-only location")
                }

                MapsAppSettingsSection(selection: .constant(.apple))
            }
            .navigationTitle("Card locations")
        }
        .environment(\.openURL, OpenURLAction
            {

            _ in
                opens += 1
                return .handled
            })
        let rowHost = UIHostingController(rootView: rows)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = rowHost
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(300))
        let image = UIGraphicsImageRenderer(bounds: rowHost.view.bounds).image
        {

        _ in
            rowHost.view.drawHierarchy(in: rowHost.view.bounds, afterScreenUpdates: true)
        }

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-card-location-rows.png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("CARD_LOCATION_RENDER=" + file.path)
        let editor = UIHostingController(rootView: CardLocationEditorSheet(location: "Existing place")
            {

            _ in
                saves += 1
                return true
            })
        window.rootViewController = editor
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(edits, 0)
        XCTAssertEqual(opens, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDayTimeOrderingDefaultsOnAndPersistsOptOut
    /// @brief      Enable automatic Day ordering for fresh and legacy preferences
    /// @details    Keeps an explicit opt-out through standalone preferences and Codable round trips.
    /// @return     (Void) records default and persistence regressions
    /// @throws     Propagates preference encoding and decoding errors
    ///
    func testDayTimeOrderingDefaultsOnAndPersistsOptOut() throws
    {

        XCTAssertTrue(LocalProfilePreferences().keepsDayListsInTimeOrder)
        XCTAssertTrue(try JSONDecoder().decode(LocalProfilePreferences.self,
                from: Data("{}".utf8)).keepsDayListsInTimeOrder)
        let manual = LocalProfilePreferences(keepsDayListsInTimeOrder: false)
        let decoded = try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONEncoder().encode(manual))
        XCTAssertFalse(decoded.keepsDayListsInTimeOrder)
        let suite = "DayTimeOrder." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {

            defaults.removePersistentDomain(forName: suite)
        }

        PlanPreferencesStore.save(manual, to: defaults)
        XCTAssertFalse(PlanPreferencesStore.load(from: defaults).keepsDayListsInTimeOrder)
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testDayTimeOrderingKeepsUntimedLastAndFocusInSync
    /// @brief      Sort timed Day Cards and Focus consistently after an edited time
    /// @details    Covers stable equal times, untimed and date-only contents, due-time fallback,
    ///             time-only normalization, start-time precedence, and manual opt-out.
    /// @return     (Void) records ordering and live rescheduling regressions
    ///
    func testDayTimeOrderingKeepsUntimedLastAndFocusInSync()
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1792800000)

        ///
        /// @fcn        testDayTimeOrderingKeepsUntimedLastAndFocusInSync.card
        /// @brief      Build a Card with an optional timed start on one controlled day
        /// @details    Fixture offsets produce independent identities without relying on wall-clock time.
        /// @param[in]  id   Stable fixture identity
        /// @param[in]  hour Optional start hour; nil creates an untimed Card
        /// @return     (KanbanCard) an explicit precision-aware schedule fixture
        ///
        func card(_ id: Int, hour: Int? = nil) -> KanbanCard
        {

            var card = KanbanCard(id: id, word: "Item \(id)", listTitle: "Today", checklists: [])
            card.startDate = hour.map
            {
                calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day)!
            }

            card.startDateKind = .time
            return card
        }

        var dateOnly = card(4)
        dateOnly.startDate = day
        dateOnly.startDateKind = .date
        var dueOnly = card(5)
        dueOnly.dueDate = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)
        dueOnly.dueDateKind = .dateAndTime
        var startWins = card(7, hour: 9)
        startWins.dueDate = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: day)
        startWins.dueDateKind = .time
        let input = [card(1, hour: 5), card(2), card(3, hour: 6), dateOnly, dueOnly,
            card(6, hour: 6), startWins, card(8)]
        let ordered = DayListTimeOrder.cards(input, calendar: calendar)
        XCTAssertEqual(ordered.map(\.id), [1, 3, 6, 5, 7, 2, 4, 8])
        XCTAssertEqual(DayListTimeOrder.cards(ordered, calendar: calendar), ordered)
        XCTAssertEqual(Set(ordered), Set(input), "Sorting must preserve every Card value")
        let preferences = LocalProfilePreferences(todayFocusItemCount: 0)
        XCTAssertEqual(preferences.todayFocusEntries(in: input, on: day, calendar: calendar).map(\.id), ordered.map(\.id))

        var edited = input
        edited[0].startDate = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)
        XCTAssertEqual(DayListTimeOrder.cards(edited, calendar: calendar).map(\.id), [3, 6, 1, 5, 7, 2, 4, 8])
        XCTAssertEqual(preferences.todayFocusEntries(in: edited, on: day, calendar: calendar).map(\.id),
            [3, 6, 1, 5, 7, 2, 4, 8])
        let manual = LocalProfilePreferences(keepsDayListsInTimeOrder: false)
        XCTAssertEqual(manual.todayFocusEntries(in: edited, on: day, calendar: calendar).map(\.id), edited.map(\.id))
    }



    ///
    /// @fcn        PlenactBoardDocumentTests.testDayTimeOrderingPreservesSectionsAndNonDayLists
    /// @brief      Limit canonical sorting to active date-mapped Lists and existing sections
    /// @details    Reorders no Card across a divider, creates no history entries, and leaves personal
    ///             and archived Lists untouched. Repeated normalization is idempotent.
    /// @return     (Void) records scope, section, history, and stability regressions
    ///
    func testDayTimeOrderingPreservesSectionsAndNonDayLists()
    {

        var early = KanbanCard(id: 1, word: "Early", listTitle: "Today", checklists: [])
        early.startDate = Calendar.current.date(bySettingHour: 5, minute: 0, second: 0, of: .now)
        early.startDateKind = .time
        var late = KanbanCard(id: 2, word: "Late", listTitle: "Today", checklists: [])
        late.startDate = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)
        late.startDateKind = .time
        let untimed = KanbanCard(id: 3, word: "Untimed", listTitle: "Today", checklists: [])
        let divider = KanbanCard(id: 4, word: "--- Another section", listTitle: "Today", isDivider: true)
        let input = [untimed, late, early, divider, untimed.replacingLocation(id: 5, listTitle: "Today"),
            early.replacingLocation(id: 6, listTitle: "Today")]
        let day = KanbanList(id: 10, title: "Today", cards: input)
        let personal = KanbanList(id: 11, title: "Personal", cards: input)
        var archived = KanbanList(id: 12, title: "Archived", cards: input)
        archived.isArchived = true
        let normalized = DayListTimeOrder.lists([day, personal, archived], dayListIDs: [10, 12], calendar: .current)
        XCTAssertEqual(normalized[0].cards.map(\.id), [1, 2, 3, 4, 6, 5])
        XCTAssertEqual(normalized[1], personal)
        XCTAssertEqual(normalized[2], archived)
        XCTAssertTrue(normalized[0].cards.allSatisfy
            {
                $0.editHistory == nil
            })
        XCTAssertEqual(DayListTimeOrder.lists(normalized, dayListIDs: [10, 12], calendar: .current), normalized)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusDateUpdatesMergeOnlyTheSelectedLiveValue
    /// @brief      Save Focus dates without reverting unrelated edits or bypassing locks
    /// @details    Covers start and due values, date removal, retained history, stale snapshots,
    ///             deleted items, replacement identities, and a lock applied while editing.
    /// @return     (Void) records schedule-merge and identity protection regressions
    ///
    func testFocusDateUpdatesMergeOnlyTheSelectedLiveValue()
    {
        let original = KanbanCard(
            id: 765, word: "Before editing", listTitle: "Today", createdAt: Date(timeIntervalSince1970: 100))
        var lists = [KanbanList(id: 1, title: "Today", cards: [original])]
        var edited = original
        edited.startDate = Date(timeIntervalSince1970: 10000)
        edited.startDateKind = .time
        lists[0].cards[0].word = "Changed while the date editor was open"
        lists[0].cards[0].dueDate = Date(timeIntervalSince1970: 20000)
        lists[0].cards[0].dueDateKind = .dateAndTime
        let liveDue = lists[0].cards[0].dueDate
        XCTAssertTrue(TodayFocusDateUpdate.apply(edited, isStart: true, to: &lists))
        XCTAssertEqual(lists[0].cards[0].word, "Changed while the date editor was open")
        XCTAssertEqual(lists[0].cards[0].startDate, edited.startDate)
        XCTAssertEqual(lists[0].cards[0].startDateKind, .time)
        XCTAssertEqual(lists[0].cards[0].dueDate, liveDue)
        XCTAssertEqual(lists[0].cards[0].dueDateKind, .dateAndTime)
        XCTAssertFalse(lists[0].cards[0].editHistory?.isEmpty ?? true)

        edited.dueDate = Date(timeIntervalSince1970: 30000)
        edited.dueDateKind = .dateAndTime
        XCTAssertTrue(TodayFocusDateUpdate.apply(edited, isStart: false, to: &lists))
        XCTAssertEqual(lists[0].cards[0].dueDate, edited.dueDate)
        XCTAssertEqual(lists[0].cards[0].startDate, edited.startDate)

        edited.startDate = nil
        XCTAssertTrue(TodayFocusDateUpdate.apply(edited, isStart: true, to: &lists))
        XCTAssertNil(lists[0].cards[0].startDate)
        XCTAssertEqual(lists[0].cards[0].startDateKind, .date)
        XCTAssertEqual(lists[0].cards[0].dueDate, edited.dueDate)

        lists[0].cards[0].isEditingLocked = true
        let locked = lists
        XCTAssertFalse(TodayFocusDateUpdate.apply(edited, isStart: false, to: &lists))
        XCTAssertEqual(lists, locked)

        lists[0].cards = [KanbanCard(
            id: original.id, word: "Replacement", listTitle: "Today", createdAt: Date(timeIntervalSince1970: 200))]
        let replacement = lists
        XCTAssertFalse(TodayFocusDateUpdate.apply(edited, isStart: false, to: &lists))
        XCTAssertEqual(lists, replacement)

        lists[0].cards.removeAll()
        XCTAssertFalse(TodayFocusDateUpdate.apply(edited, isStart: true, to: &lists))
        lists[0].cards = [original]
        lists[0].isArchived = true
        XCTAssertFalse(TodayFocusDateUpdate.apply(edited, isStart: true, to: &lists))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayFocusRefreshesLiveWorkspaceEdits
    /// @brief      Refresh native Focus rows without navigation or a minute ticking over
    /// @details    Keeps the same Today screen identity while changing titles, completion, dates,
    ///             bookmarks, and membership through its shared bindings. Inspects the native Focus collection,
    ///             isolating its rendered rows from unrelated slogan and subtitle animations.
    /// @return     (Void) records stale row or membership regressions
    /// @throws     Propagates missing simulator scene, collection, and image errors
    ///
    @MainActor
    func testTodayFocusRefreshesLiveWorkspaceEdits() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {

                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let originalPreferences = UserDefaults.standard.data(forKey: PlanPreferencesStore.key)
        defer
        {

            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
            UserDefaults.standard.set(originalPreferences, forKey: PlanPreferencesStore.key)
        }

        PlanPreferencesStore.save(LocalProfilePreferences(
                todayFocusItemCount: 0, todayFocusHidesCompleted: false))
        let title = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: .now) - 1]
        var lists = [KanbanList(id: 7654, title: title, cards: [
                    KanbanCard(id: 765401, word: "Original focus title", listTitle: title, checklists: [])
                ])]
        var bookmarks: Set<Int> = []

        ///
        /// @fcn        testTodayFocusRefreshesLiveWorkspaceEdits.makeToday
        /// @brief      Recreate the parent value while retaining the Today screen identity
        /// @details    Uses the same live workspace bindings on every parent update.
        /// @return     (TodayHomeView) the configured Today screen
        ///
        func makeToday() -> TodayHomeView
        {

            TodayHomeView(
                lists: Binding(get:
                    {
                        lists
                    }, set:
                    {
                        lists = $0
                    }),
                archivedLists: .constant([]),
                savedCardIDs: Binding(get:
                    {
                        bookmarks
                    }, set:
                    {
                        bookmarks = $0
                    }),
                profile: nil, onSaveProfile:
                {
                _ in
                }, onRemoveProfile:
                {

                },
                onAddCard:
                {
                _, _, _, _, _, _ in
                }, onAddCapture:
                {
                _ in
                    false
                },
                onToggleCardCompletion:
                {
                _, _ in
                }, onOpenBoardList:
                {
                _ in
                },
                onOpenBoardCard:
                {
                _, _ in
                }, onArchiveCard:
                {
                _ in
                },
                onDeleteCard:
                {
                _ in
                    false
                }, onArchiveList:
                {
                _ in
                },
                onDeleteList:
                {
                _ in
                    false
                }, quickCreateRequest: 0
            )
        }


        ///
        /// @fcn        testTodayFocusRefreshesLiveWorkspaceEdits.collection
        /// @brief      Locate the native collection backing Focus rows
        /// @details    Searches only the current hosted Today view hierarchy.
        /// @param[in]  view  Root or descendant UIKit view
        /// @return     (UICollectionView?) first native collection, if rendered
        ///
        func collection(in view: UIView) -> UICollectionView?
        {

            if let collection = view as? UICollectionView
            {

                return collection
            }

            return view.subviews.lazy.compactMap
            {
                collection(in: $0)
            } .first
        }


        let welcomeCue = TodayWelcomeCue()
        let host = UIHostingController(rootView: makeToday().environmentObject(welcomeCue))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        for _ in 0 ..< 20
        {
            if collection(in: host.view) != nil
            {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
            host.view.layoutIfNeeded()
        }

        ///
        /// @fcn        testTodayFocusRefreshesLiveWorkspaceEdits.rowsImage
        /// @brief      Capture only the current native Focus rows
        /// @details    Excludes the surrounding Today content and its timed visual effects.
        /// @return     (Data) PNG data suitable for comparing before and after an edit
        /// @throws     Propagates absent collection and image encoding errors
        ///
        func rowsImage() throws -> Data
        {

            let rows = try XCTUnwrap(collection(in: host.view))
            let image = UIGraphicsImageRenderer(bounds: rows.bounds).image
            {

            _ in
                rows.drawHierarchy(in: rows.bounds, afterScreenUpdates: true)
            }

            return try XCTUnwrap(image.pngData())
        }


        let original = try rowsImage()
        lists[0].cards[0].word = "A visibly updated title"
        host.rootView = makeToday().environmentObject(welcomeCue)
        try await Task.sleep(for: .milliseconds(200))
        let renamed = try rowsImage()
        XCTAssertNotEqual(renamed, original, "Saved title edits must redraw Focus immediately")

        lists[0].cards[0].isTitleChecked = true
        host.rootView = makeToday().environmentObject(welcomeCue)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotEqual(try rowsImage(), renamed, "Completion edits must redraw the existing row")

        let completed = try rowsImage()
        lists[0].cards[0].startDate = .now.addingTimeInterval(3600)
        lists[0].cards[0].startDateKind = .dateAndTime
        host.rootView = makeToday().environmentObject(welcomeCue)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotEqual(try rowsImage(), completed, "Saved schedule edits must update Focus metadata")

        lists[0].cards.append(KanbanCard(
                id: 765402, word: "Newly added focus card", listTitle: title, checklists: []))
        host.rootView = makeToday().environmentObject(welcomeCue)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(try XCTUnwrap(collection(in: host.view)).numberOfItems(inSection: 0), 2)

        lists[0].cards.removeFirst()
        host.rootView = makeToday().environmentObject(welcomeCue)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(try XCTUnwrap(collection(in: host.view)).numberOfItems(inSection: 0), 1)

        bookmarks = [765402]
        PlanPreferencesStore.save(LocalProfilePreferences(
                todayFocusItemCount: 0, todayFocusHidesCompleted: false, todayFocusIncludesBookmarked: true))
        host.rootView = makeToday().environmentObject(welcomeCue)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(try XCTUnwrap(collection(in: host.view)).numberOfItems(inSection: 0), 1)

        bookmarks.remove(765402)
        host.rootView = makeToday().environmentObject(welcomeCue)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(collection(in: host.view), "Removing the last matching bookmark must clear Focus rows")

        bookmarks.insert(765402)
        host.rootView = makeToday().environmentObject(welcomeCue)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(try XCTUnwrap(collection(in: host.view)).numberOfItems(inSection: 0), 1,
                               "Restoring a bookmark must immediately restore its matching Focus row")
    }





    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusMetadataMatchesSelectionAndExplainsItsSources()
    /// @brief      Keep schedules and whole-day progress out of purely personal Focus selections
    /// @details    Covers all filter combinations and verifies that the context names selected
    ///             sources without describing a filtered collection as the entire day.
    /// @return     (Void) records metadata-policy or context regressions
    ///
    func testFocusMetadataMatchesSelectionAndExplainsItsSources()
    {

        for important in [false, true]
        {
            for bookmarked in [false, true]
            {
                for upNext in [false, true]
                {
                    XCTAssertEqual(TodayFocusPresentation.showsSchedule(important: important,
                        bookmarked: bookmarked, upNext: upNext), upNext || (!important && !bookmarked))
                    let context = TodayFocusPresentation.context(important: important, bookmarked: bookmarked,
                                                                 upNext: upNext, chronological: false)
                    XCTAssertTrue(context.contains("today’s list"))
                    XCTAssertEqual(context.contains("Important"), important)
                    XCTAssertEqual(context.contains("Bookmarked"), bookmarked)
                    XCTAssertEqual(context.contains("Up Next"), upNext)
                }
            }
        }
        XCTAssertTrue(TodayFocusPresentation.context(important: false, bookmarked: false,
                                                     upNext: false, chronological: true).contains("time order"))
    }




    ///
    /// @fcn PlenactBoardDocumentTests.testStudioNativeEditorRendersReadableMaterialControls()
    /// @brief Host the native editor to verify live artwork and native controls mount together
    /// @details Uses a synthetic canvas and captures a review image without importing, saving,
    ///          or changing the user's appearance preferences.
    /// @return (Void) records presentation failures
    /// @throws Fixture setup and image export failures propagate to XCTest.
    ///
    @MainActor
    func testStudioNativeEditorRendersReadableMaterialControls() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: NavigationStack
        {
            StudioSurfaceEditor(surface: .constant(StudioSurface(material: .canvas, readability: 0.4)))
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(250))
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(host.view.bounds.width, 0)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-studio-native-preview.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("Studio review image: " + url.path)
    }


    ///
    /// @fcn PlenactBoardDocumentTests.testStudioMaterialsRoundTripWithoutChangingLegacyAppearance()
    /// @brief Preserve existing appearance defaults and explicit new material metadata
    /// @details Exercises every material kind, explicit plain overrides, Card relocation, and saved-look reuse.
    /// @return (Void) records persistence or compatibility failures
    /// @throws Fixture encoding and decoding failures propagate to XCTest.
    ///
    func testStudioMaterialsRoundTripWithoutChangingLegacyAppearance() throws
    {

        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.studioSurface)
        XCTAssertTrue(legacy.isEmpty)
        for material in StudioMaterial.allCases
        {
            let surface = StudioSurface(material: material, color: "ABCDEF", strength: 0.42,
                                        readability: 0.7, verticalPosition: 0.2, zoom: 1.4, showsInPreviews: false)
            var appearance = ItemAppearance()
            appearance.studioSurface = surface
            XCTAssertFalse(appearance.isEmpty)
            var card = KanbanCard(id: 7, word: "My note", listTitle: "Ideas", checklists: [])
            card.appearance = appearance
            let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
            XCTAssertEqual(restored.appearance?.studioSurface, surface)
            XCTAssertEqual(restored.replacingLocation(id: 22, listTitle: "Other").appearance?.studioSurface, surface)
            let look = StudioArtwork(name: "Favorite", surface: surface, header: .teal, italicSubtitle: true)
            XCTAssertEqual(try JSONDecoder().decode(StudioArtwork.self, from: JSONEncoder().encode(look)), look)
        }
    }


    ///
    /// @fcn PlenactBoardDocumentTests.testStudioCreationDefaultsRespectExplicitArtAndNotes()
    /// @brief Store new-item variety once while honoring existing per-item artwork and headers
    /// @details Uses an injected single-color palette for deterministic results and checks divider exclusion.
    /// @return (Void) records creation-default or explicit-choice regressions
    ///
    func testStudioCreationDefaultsRespectExplicitArtAndNotes()
    {

        var settings = StudioSettings()
        settings.defaultCardSurface = StudioSurface(material: .gradient)
        settings.defaultNoteSurface = StudioSurface(material: .linen)
        settings.variesNewSurfaces = true
        settings.variesNewHeaders = true
        settings.palette = ["AABBCC"]
        for presentation in [ItemPresentation.card, .note]
        {
            var card = KanbanCard(id: 1, word: "New", listTitle: "Inbox", checklists: [], presentation: presentation)
            StudioSettings.apply(to: &card, settings: settings)
            XCTAssertEqual(card.appearance?.studioSurface?.color, "AABBCC")
            XCTAssertEqual(card.appearance?.studioSurface?.material, presentation == .note ? .linen : .gradient)
            XCTAssertNotNil(card.appearance?.background)
            var explicit = ItemAppearance()
            explicit.studioSurface = StudioSurface(material: .paper, color: "123456")
            explicit.background = .rose
            card.appearance = explicit
            StudioSettings.apply(to: &card, settings: settings)
            XCTAssertEqual(card.appearance, explicit)
        }
        var divider = KanbanCard(id: 9, word: "---", listTitle: "Inbox", isDivider: true)
        StudioSettings.apply(to: &divider, settings: settings)
        XCTAssertNil(divider.appearance)
        var unchanged = KanbanCard(id: 3, word: "Existing", listTitle: "Inbox", checklists: [])
        StudioSettings.apply(to: &unchanged, settings: StudioSettings())
        XCTAssertNil(unchanged.appearance)
    }


    ///
    /// @fcn PlenactBoardDocumentTests.testStudioWorkspaceSettingsUseAnIsolatedPreferencesDomain()
    /// @brief Persist independent view wallpapers without changing unconfigured destinations
    /// @details Confirms defaults do not write preferences and settings retain explicit preview visibility.
    /// @return (Void) records workspace setting persistence failures
    /// @throws Fixture encoding and preferences setup failures propagate to XCTest.
    ///
    func testStudioWorkspaceSettingsUseAnIsolatedPreferencesDomain() throws
    {

        let suite = "Plenact.Studio.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(StudioSettings.load(from: defaults), StudioSettings())
        XCTAssertNil(defaults.data(forKey: StudioSettings.key))
        var settings = StudioSettings()
        settings.views[StudioDestination.today.rawValue] = StudioSurface(material: .canvas)
        settings.defaultNoteSurface = StudioSurface(material: .dots, showsInPreviews: false)
        defaults.set(try JSONEncoder().encode(settings), forKey: StudioSettings.key)
        XCTAssertEqual(StudioSettings.load(from: defaults), settings)
        XCTAssertNil(StudioSettings.load(from: defaults).views[StudioDestination.activity.rawValue])
    }


    ///
    /// @fcn PlenactBoardDocumentTests.testStudioImportOwnsImagesOutsideAttachmentStorage()
    /// @brief Keep reusable personal artwork independent of attachment cleanup
    /// @details Imports a synthetic image, validates safe lookup, and removes only the test's generated file.
    /// @return (Void) records image import, ownership, or lookup failures
    /// @throws Image preparation and filesystem errors propagate to XCTest.
    ///
    @MainActor
    func testStudioImportOwnsImagesOutsideAttachmentStorage() throws
    {

        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60)).image
        {
            context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        let name = try StudioArtworkStore.importImage(XCTUnwrap(image.pngData()))
        let url = try StudioArtworkStore.directory().appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNotNil(StudioArtworkStore.image(name))
        XCTAssertNil(StudioArtworkStore.image("../" + name))
        XCTAssertNil(StudioArtworkStore.image("/tmp/" + name))
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "PlenactStudioArtwork")
    }


    ///
    /// @fcn PlenactBoardDocumentTests.testStudioUnsplashRejectsCredentialRequestsToOtherHosts()
    /// @brief Prevent saved metadata from sending provider credentials to arbitrary hosts
    /// @details Uses invalid hosts and insecure URLs, all rejected before any network request.
    /// @return (Void) records missing credential-boundary enforcement
    ///
    func testStudioUnsplashRejectsCredentialRequestsToOtherHosts() async
    {

        for text in ["https://example.com/download", "http://api.unsplash.com/photos/test/download"]
        {
            do
            {
                _ = try await StudioUnsplash.request(URL(string: text)!)
                XCTFail("Unapproved credential destination was accepted")
            }
            catch { XCTAssertNotNil(error) }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSubtitleItalicsInheritAndPreserveExplicitRegularOverrides()
    /// @brief      Resolve Board, List, and Card subtitle styles without losing explicit false
    /// @details    Covers legacy defaults, the complete override chain, optional-field encoding,
    ///             and clearing List overrides when applying Board defaults.
    /// @return     (Void) records inheritance, compatibility, or persistence failures
    /// @throws     Propagates JSON fixture decoding and encoding failures to XCTest
    ///
    func testSubtitleItalicsInheritAndPreserveExplicitRegularOverrides() throws
    {

        var board = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        var list = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        var card = ItemAppearance()
        XCTAssertNil(board.subtitleItalic)
        XCTAssertNil(list.subtitleItalic)
        XCTAssertFalse(board.resolvedSubtitleItalic(card: card, list: list))
        board.subtitleItalic = true
        XCTAssertTrue(board.resolvedSubtitleItalic(card: card, list: list))
        list.subtitleItalic = false
        XCTAssertFalse(board.resolvedSubtitleItalic(card: card, list: list))
        XCTAssertFalse(list.isEmpty, "Explicit regular type must survive appearance normalization")
        card.subtitleItalic = true
        XCTAssertTrue(board.resolvedSubtitleItalic(card: card, list: list))
        list.subtitleItalic = true
        card.subtitleItalic = false
        XCTAssertFalse(board.resolvedSubtitleItalic(card: card, list: list))
        let savedCard = try JSONDecoder().decode(ItemAppearance.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(savedCard.subtitleItalic, false)
        let savedBoard = try JSONDecoder().decode(BoardAppearance.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(savedBoard.subtitleItalic, true)
        card.subtitleItalic = nil
        XCTAssertTrue(board.resolvedSubtitleItalic(card: card, list: list))
        var owner = KanbanList(id: 12, title: "Work", cards: [])
        owner.appearance = list
        XCTAssertNil(BoardAppearance.inheritingLists([owner]).first?.appearance?.subtitleItalic)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSubtitleOverridesSurviveCardAndListPersistence()
    /// @brief      Retain italic and regular choices through canonical Card and List saves
    /// @details    Exercises explicit regular Card overrides, italic List defaults, relocation,
    ///             and archive restoration without changing subtitle content.
    /// @return     (Void) records content or appearance retention failures
    /// @throws     Propagates JSON fixture encoding and decoding failures to XCTest
    ///
    func testSubtitleOverridesSurviveCardAndListPersistence() throws
    {

        var card = KanbanCard(id: 1, word: "Task", listTitle: "Work", subtitleOverride: "A softer subtitle")
        var appearance = ItemAppearance()
        appearance.subtitleItalic = false
        card.appearance = appearance
        appearance.subtitleItalic = true
        var list = KanbanList(id: 1, title: "Work", cards: [card])
        list.appearance = appearance
        let saved = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(saved.cards.first?.appearance?.subtitleItalic, false)
        XCTAssertEqual(saved.appearance?.subtitleItalic, true)
        XCTAssertEqual(saved.cards.first?.subtitleOverride, "A softer subtitle")
        XCTAssertEqual(card.replacingLocation(id: 9, listTitle: "Other").appearance?.subtitleItalic, false)
        list.archiveCard(id: 1)
        list.restoreArchivedCard(id: 1)
        XCTAssertEqual(list.cards.first?.appearance?.subtitleItalic, false)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardHistoryCoalescesTypingWithoutCombiningSeparateActions()
    /// @brief      Keep autosaved writing readable while preserving initial and final values
    /// @details    Uses deterministic timestamps to distinguish a typing burst, a later title
    ///             edit, and a separate completion action.
    /// @return     (Void) records grouping or retained-value failures
    /// @throws     Propagates fixture unwrap and JSON decoding failures to XCTest
    ///
    func testCardHistoryCoalescesTypingWithoutCombiningSeparateActions() throws
    {

        let original = KanbanCard(id: 1, word: "A", listTitle: "Work", checklists: [])
        var next = original
        next.word = "AB"
        let first = next.recordingEdits(from: original, at: Date(timeIntervalSince1970: 100))
        next.word = "ABC"
        let burst = next.recordingEdits(from: first, at: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(burst.editHistory?.count, 1)
        XCTAssertEqual(burst.editHistory?.first?.id, first.editHistory?.first?.id)
        let change = try XCTUnwrap(burst.editHistory?.first?.changes.first)
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(change.previousValue)), "A")
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(change.newValue)), "ABC")
        next.word = "Later"
        let later = next.recordingEdits(from: burst, at: Date(timeIntervalSince1970: 110))
        XCTAssertEqual(later.editHistory?.count, 2)
        next.isTitleChecked = true
        let completed = next.recordingEdits(from: later, at: Date(timeIntervalSince1970: 111))
        XCTAssertEqual(completed.editHistory?.count, 3)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardHistoryRecordsGroupedEditsAndRetainsReversibleValues()
    /// @brief      Persist a grouped save and accumulate subsequent preview and completion edits
    /// @details    Exercises the List owner boundary, no-op saves, stale reconstructed snapshots,
    ///             precise before/after values, and JSON round trips with synthetic content.
    /// @return     (Void) records history grouping, retention, or persistence failures
    /// @throws     Propagates fixture encoding and unwrapping failures to XCTest
    ///
    func testCardHistoryRecordsGroupedEditsAndRetainsReversibleValues() throws
    {

        let original = KanbanCard(id: 12, word: "Before", listTitle: "Work", checklists: [])
        var list = KanbanList(id: 7, title: "Work", cards: [original])
        XCTAssertNil(list.cards[0].editHistory, "Insertion must not invent earlier history")
        var edited = original
        edited.word = "After"
        edited.dueDate = Date(timeIntervalSince1970: 123456)
        edited.dueDateKind = .dateAndTime
        list.cards[0] = edited
        let first = try XCTUnwrap(list.cards[0].editHistory?.first)
        XCTAssertEqual(list.cards[0].editHistory?.count, 1)
        XCTAssertEqual(Set(first.changes.map(\.field)), ["word", "dueDate", "dueDateKind"])
        let title = try XCTUnwrap(first.changes.first { $0.field == "word" })
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(title.previousValue)), "Before")
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(title.newValue)), "After")
        XCTAssertNil(first.changes.first { $0.field == "dueDate" }?.previousValue)
        XCTAssertFalse(first.changes.contains { $0.field == "editHistory" })

        list.cards[0] = edited
        XCTAssertEqual(list.cards[0].editHistory, [first], "No-op and reconstructed saves retain history")
        list.cards[0].isTitleChecked = true
        XCTAssertEqual(list.cards[0].editHistory?.count, 2)
        XCTAssertEqual(list.cards[0].editHistory?.last?.changes.map(\.field), ["isTitleChecked"])
        let roundTrip = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(roundTrip, list)
        XCTAssertEqual(roundTrip.cards[0].editHistory?.count, 2, "Loading must not append edits")
        XCTAssertEqual(list.cards[0].replacingLocation(id: 99, listTitle: "Elsewhere").editHistory,
                       list.cards[0].editHistory)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardHistoryPreservesPreparedEventsAndLegacyLocks()
    /// @brief      Avoid duplicate detail-save entries and maintain locked Card update protection
    /// @details    Reconciles a pre-recorded detail edit with the canonical owner, excludes reorder
    ///             and list-context changes, and decodes legacy Cards without a history key.
    /// @return     (Void) records duplicate, compatibility, or protection failures
    /// @throws     Propagates synthetic fixture encoding and unwrap failures to XCTest
    ///
    func testCardHistoryPreservesPreparedEventsAndLegacyLocks() throws
    {

        let original = KanbanCard(id: 3, word: "Legacy", listTitle: "Work", checklists: [])
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["editHistory"])
        XCTAssertNil(try JSONDecoder().decode(KanbanCard.self, from: data).editHistory)
        var edited = original
        edited.word = "Renamed"
        let prepared = edited.recordingEdits(from: original, at: Date(timeIntervalSince1970: 100))
        var list = KanbanList(id: 8, title: "Work", cards: [original])
        list.cards[0] = prepared
        XCTAssertEqual(list.cards[0].editHistory, prepared.editHistory)
        list.cards.reverse()
        XCTAssertEqual(list.cards[0].editHistory?.count, 1)
        let relocated = prepared.replacingLocation(id: 3, listTitle: "Other")
        list.cards[0] = relocated
        XCTAssertEqual(list.cards[0].editHistory, prepared.editHistory)

        list.cards[0].isEditingLocked = true
        let locked = list.cards[0]
        var unlock = locked
        unlock.editHistory = nil
        unlock.isEditingLocked = false
        XCTAssertTrue(locked.acceptsContentUpdate(unlock), "History metadata must not block an unchanged unlock")
        unlock.word = "Unexpected stale edit"
        XCTAssertFalse(locked.acceptsContentUpdate(unlock))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testActivityBrowserScrollsWithinVisibleBounds()
    /// @brief      Keep long Saved results inside the Activity browser viewport
    /// @details    Hosts eighty synthetic bookmarks with isolated preferences, scrolls to the last
    ///             row, and verifies the viewport and independent header retain their positions.
    ///
    /// @return     (Void) records failures for unbounded content or coupled scrolling
    /// @throws     Propagates missing window, preferences, or browser fixture failures to XCTest
    ///
    @MainActor
    func testActivityBrowserScrollsWithinVisibleBounds() async throws
    {

        let suite = "Plenact.ActivityLayoutTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(Data("[]".utf8), forKey: ActivityRecentStore.key)
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let cards = (0 ..< 80).map
        {
            KanbanCard(id: $0, word: "Saved fixture \($0)", listTitle: "Fixture", checklists: [])
        }
        let list = KanbanList(id: 987, title: "Fixture", cards: cards)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
        {
            $0 as? UIWindowScene
        }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: SavedCardsView(
            planningDocument: nil,
            lists: [list],
            savedCardIDs: Set(cards.map(\.id)),
            collections: .constant([]),
            onOpenBoardCard: { _, _ in },
            onOpenPersonalCard: { _ in },
            onRestoreBoard: { _ in },
            onDeleteBoard: { _ in false },
            onArchiveCard: { _ in },
            onDeleteCard: { _ in false }
        ).defaultAppStorage(defaults))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()


        ///
        /// @fcn        scrollViews(in:)
        /// @brief      Collect UIKit scrolling viewports beneath the hosted Activity view
        /// @details    Descends all child views without depending on private SwiftUI class names.
        ///
        /// @param      view (UIView) subtree to inspect
        /// @return     ([UIScrollView]) scrolling views in traversal order
        ///
        func scrollViews(in view: UIView) -> [UIScrollView]
        {

            let own = (view as? UIScrollView).map { [$0] } ?? []
            return own + view.subviews.flatMap { scrollViews(in: $0) }
        }

        let scrolls = scrollViews(in: host.view)
        let browser = try XCTUnwrap(scrolls.max
        {
            $0.contentSize.height - $0.bounds.height < $1.contentSize.height - $1.bounds.height
        })
        let frame = browser.convert(browser.bounds, to: host.view)
        XCTAssertGreaterThan(browser.bounds.height, 100)
        XCTAssertGreaterThan(browser.contentSize.height, browser.bounds.height + 500)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.maxY, host.view.bounds.maxY + 1)
        let otherOffsets = scrolls.filter { $0 !== browser }.map(\.contentOffset)
        browser.setContentOffset(CGPoint(x: 0, y: browser.contentSize.height - browser.bounds.height), animated: false)
        host.view.layoutIfNeeded()
        XCTAssertEqual(browser.convert(browser.bounds, to: host.view), frame)
        XCTAssertEqual(scrolls.filter { $0 !== browser }.map(\.contentOffset), otherOffsets)
        XCTAssertGreaterThan(browser.contentOffset.y, 500)
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
    func testNativeCardDragSourceUsesLocalTokenAndEndsCancellationOnce() async throws
    {


        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]]) /* Declarations under inspection       */
        let declaration = try XCTUnwrap(
            declarations.first
            {  /* Declaration record under inspection */

                ($0 ["UTTypeIdentifier"] as? String) == BoardCardDragSource.contentType.identifier
            })

        XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], ["public.data"])

        var points: [CGPoint] = []  /* Sample layout coordinates */
        var ended = 0               /* Completed drag state      */
        let source = BoardCardDragSource(
            token: "synthetic-session", /* Source state before the operation */
            onBegan:
            {
                points.append($0)
            },
            onChanged:
            {
                points.append($0)
            },
            onEnded:
            {
                ended += 1
            })
        let coordinator = source.makeCoordinator()   /* Drop coordinator under test */
        let point = CGPoint(x: 150, y: 320)          /* Synthetic drop coordinate   */
        let provider = coordinator.begin(at: point)  /* Native drag-item provider   */

        XCTAssertEqual(points, [point])
        XCTAssertTrue(coordinator.isDragging)
        XCTAssertEqual(provider.suggestedName, "synthetic-session")
        XCTAssertEqual(provider.registeredTypeIdentifiers, [BoardCardDragSource.contentType.identifier])

        let data: Data = try await withCheckedThrowingContinuation
        {
        continuation in /* Serialized fixture bytes */
            provider.loadDataRepresentation(forTypeIdentifier: BoardCardDragSource.contentType.identifier)
            {

            data, error in
                if let error /* Captured operation error */
                {


                    continuation.resume(throwing: error)
                }
                else if let data /* Response bytes supplied by the data-provider callback */
                {


                    continuation.resume(returning: data)
                }
                else
                {


                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }

            }

        }


        XCTAssertEqual(
            String(data: data, encoding: .utf8), "synthetic-session",
                            "Native drag payload must not contain card content or file references")

        coordinator.finish()
        coordinator.finish()

        XCTAssertFalse(coordinator.isDragging)
        XCTAssertEqual(ended, 1, "Drop/cancellation cleanup must not run twice")
        XCTAssertTrue(
            coordinator.responds(to: NSSelectorFromString("dragInteraction:session:didEndWithOperation:")),
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
    func testNativeCardDragSourceSurvivesSourceRemovalUntilSessionEnd()
    {


        var ended = 0 /* Completed drag state              */
        let source = BoardCardDragSource(
            token: "synthetic-session", onBegan:
            {
                _ in
            }, onChanged:
            {
                _ in
            }, /* Source state before the operation */
            onEnded:
            {
                ended += 1
            })
        let coordinator = source.makeCoordinator()                  /* Drop coordinator under test */
        let container = UIView()                                    /* Target drop container       */
        let interaction = UIDragInteraction(delegate: coordinator)  /* Captured drag interaction   */

        container.addInteraction(interaction)
        coordinator.container = container
        coordinator.interaction = interaction
        _ = coordinator.begin(at: CGPoint(x: 1, y: 2))
        BoardCardDragSource.dismantleUIView(BoardCardDragSource.Probe(), coordinator: coordinator)

        XCTAssertEqual(ended, 0, "Virtualizing the source row must not end a live drag")
        XCTAssertTrue(coordinator.isDragging)
        XCTAssertTrue(container.interactions.contains
            {
                $0 === interaction
            })

        coordinator.finish()

        XCTAssertEqual(ended, 1)
        XCTAssertFalse(container.interactions.contains
            {
                $0 === interaction
            })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListDragEdgeThresholdsAndInvalidGeometry()
    /// @brief      Verify drag-edge activation at exact thresholds
    /// @details    Shared thresholds govern both list reordering and card-drag horizontal scrolling
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testListDragEdgeThresholdsAndInvalidGeometry()
    {


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
    /// @fcn        PlenactBoardDocumentTests.testToolbarBackgroundRetainsHomeIndicatorCoverageWithoutInheritedInsets
    /// @brief      Verify that a transient missing safe-area environment does not uncover the footer
    /// @details    Renders the actual toolbar surface over a conspicuous green workspace, with an explicit
    ///             home-indicator allowance and no inherited container inset. Checks pixels in the controls'
    ///             background and the lower reserved strip independently of the toolbar buttons.
    ///
    /// @return     (Void) records rendered background coverage assertions
    /// @throws     Image rendering or bitmap fixture errors propagate to XCTest
    ///
    @MainActor
    func testToolbarBackgroundRetainsHomeIndicatorCoverageWithoutInheritedInsets() throws
    {

        for layout in [BottomToolbarLayout.phoneRegular, .phoneCompact, .padRegular, .padCompact]
        {
            for reportedInset: CGFloat in [0, 21, 34]
            {

                let height = layout.height
                let inset = max(reportedInset, layout.safeAreaAllowance)
                let content = ZStack(alignment: .top)
                {

                    Color(red: 0, green: 1, blue: 0)
                    Color.clear
                    .frame(height: height)
                    .background
                    {

                        BottomToolbarBackground(topInset: layout.backgroundTopInset, bottomInset: inset)
                    }
                }
                .frame(width: 200, height: height + inset)

                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage?.cgImage)
                let data = try XCTUnwrap(image.dataProvider?.data)
                let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
                XCTAssertEqual(image.bitsPerPixel, 32)
                for y in [Int((layout.backgroundTopInset + height) / 2), Int(height + inset) - 2]
                {

                    let offset = y * image.bytesPerRow + 100 * 4
                    let uncovered = bytes[offset] < 25 && bytes[offset + 1] > 230 && bytes[offset + 2] < 25
                    XCTAssertFalse(uncovered, "Toolbar background is missing at y=\(y), bottom inset=\(inset)")
                }
                if layout.backgroundTopInset > 0
                {

                    let offset = Int(layout.backgroundTopInset / 2) * image.bytesPerRow + 100 * 4
                    let clearTopGap = bytes[offset] < 25 && bytes[offset + 1] > 230 && bytes[offset + 2] < 25
                    XCTAssertTrue(clearTopGap, "The preset overlap gap must remain transparent")
                }
            }
        }
    }

}
