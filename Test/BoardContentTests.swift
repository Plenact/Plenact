// --------------------------------------------------------------------------------------------------
// @file       BoardContentTests.swift
// @brief      Board Content regression tests
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
/// BoardContent regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testRandomCardColorPreferencesDefaultOffAndRoundTripWithoutProfile
    /// @brief      Verify that random Card Color Preferences Default Off And Round Trip Without Profile
    /// @details    Exercises `PlanPreferencesStore.save`, `PlanPreferencesStore.load`, `LocalProfileStore.load`.
    ///             Checks `XCTAssertFalse(old.randomizesNewCardHeaders)`;
    ///             `XCTAssertFalse(old.randomizesNewCardBackgrounds)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testRandomCardColorPreferencesDefaultOffAndRoundTripWithoutProfile() throws
    {

        let old = try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(old.randomizesNewCardHeaders)
        XCTAssertFalse(old.randomizesNewCardBackgrounds)
        let appearance = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(appearance.cardBackground)
        XCTAssertTrue(appearance.isEmpty)
        let name = "RandomCardColorTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        for headers in [false, true]
        {

            for backgrounds in [false, true]
            {

                let preferences = LocalProfilePreferences(
                    randomizesNewCardHeaders: headers, randomizesNewCardBackgrounds: backgrounds)
                PlanPreferencesStore.save(preferences, to: defaults)
                XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
                XCTAssertNil(LocalProfileStore.load(from: defaults))
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDayDistributionSplitsTagsAndCountsCompletionWithoutInventingTime
    /// @brief      Verify that day Distribution Splits Tags And Counts Completion Without Inventing Time
    /// @details    Exercises `PlanningDate.date`, `result.segments.first`. Checks `XCTAssertEqual(result.total,
    ///             10800)`; `XCTAssertEqual(result.completedTime, 7200)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDayDistributionSplitsTagsAndCountsCompletionWithoutInventingTime() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: try XCTUnwrap(PlanningDate.date("2026-10-20", calendar: calendar)))


        ///
        /// @fcn        PlenactBoardDocumentTests.testDayDistributionSplitsTagsAndCountsCompletionWithoutInventingTime.date
        /// @brief      Prepare date for the enclosing regression test
        /// @details    Supplies the local fixture for day Distribution Splits Tags And Counts Completion Without
        ///             Inventing Time. Uses `calendar.date`.
        ///
        /// @param[in]  hour  Hour-of-day component used by the fixture
        ///
        /// @return     (Date) result described by this operation's contract
        ///
        func date(_ hour: Int) -> Date
        {
            calendar.date(byAdding: .hour, value: hour, to: day)!
        }

        let cards = [
            KanbanCard(
                id: 1, word: "Work", listTitle: "Tuesday", isTitleChecked: true,
                startDate: date(9), dueDate: date(11), labelIDs: ["day-work", "day-health", "day-work"],
                startDateKind: .dateAndTime, dueDateKind: .dateAndTime),
            KanbanCard(
                id: 2, word: "Uncategorized", listTitle: "Tuesday", startDate: date(10), dueDate: date(11),
                startDateKind: .dateAndTime, dueDateKind: .dateAndTime),
            KanbanCard(id: 3, word: "Untimed", listTitle: "Tuesday", startDate: date(0), dueDate: date(0)),
            KanbanCard(id: 4, word: "Note", listTitle: "Tuesday", presentation: .note)
        ]
        let result = DayTimeDistribution(
            cards: cards, labels: LabelLibrary.starter.includingDayAreas, day: day, calendar: calendar)
        XCTAssertEqual(result.total, 10800, accuracy: 0.01)
        XCTAssertEqual(result.completedTime, 7200, accuracy: 0.01)
        XCTAssertEqual(result.taskCount, 3)
        XCTAssertEqual(result.completedCount, 1)
        XCTAssertEqual(result.untimedCount, 1)
        XCTAssertTrue(result.hasOverlaps)
        XCTAssertEqual(result.segments.first
            {
                $0.id == "day-work"
            }?.planned, 3600)
        XCTAssertEqual(result.segments.first
            {
                $0.id == "day-health"
            }?.planned, 3600)
        let overnight = KanbanCard(
            id: 5, word: "Night", listTitle: "Tuesday", startDate: date(23), dueDate: date(1),
            startDateKind: .time, dueDateKind: .time)
        XCTAssertEqual(
            DayTimeDistribution(cards: [overnight], labels: .starter, day: day, calendar: calendar).total, 3600)
        let reverse = KanbanCard(
            id: 6, word: "Invalid", listTitle: "Tuesday", startDate: date(11), dueDate: date(9),
            startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
        XCTAssertEqual(DayTimeDistribution(cards: [reverse], labels: .starter, day: day, calendar: calendar).total, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDefaultWeekUsesValidDayAreaTagsWithoutRewritingCustomTags
    /// @brief      Verify that default Week Uses Valid Day Area Tags Without Rewriting Custom Tags
    /// @details    Exercises `template.collection.lists.flatMap(\.cards).allSatisfy`,
    ///             `template.collection.lists.flatMap`, `card.labelIDs.allSatisfy`. Checks
    ///             `XCTAssertEqual(upgraded.templates[index].collection.lists[0].cards[0].labelIDs, ["custom-tag"])`;
    ///             `XCTAssertFalse(upgraded.templates[index].collection.lists[0].cards[1].labelIDs.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDefaultWeekUsesValidDayAreaTagsWithoutRewritingCustomTags() throws
    {

        let labels = LabelLibrary.starter.includingDayAreas
        let template = PlanningRoutineLibrary.jmr
        XCTAssertTrue(
            template.collection.lists.flatMap(\.cards).allSatisfy
            {
                card in
                !card.labelIDs.isEmpty && card.labelIDs.allSatisfy
                {
                    id in
                    labels.labels.contains
                    {
                        $0.id == id
                    }

                }

            })
        let suite = "DayDistribution." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        var old = PlanningRoutineLibrary.seeded
        old.bundledRoutineRevision = 1
        let index = try XCTUnwrap(old.templates.firstIndex
            {
                $0.id == PlanningRoutineLibrary.jmrID
            })
        old.templates[index].collection.lists[0].cards[0].labelIDs = ["custom-tag"]
        old.templates[index].collection.lists[0].cards[1].labelIDs = []
        defaults.set(try JSONEncoder().encode(old), forKey: PlanningRoutineStore.key)
        let upgraded = try PlanningRoutineStore.load(from: defaults)
        XCTAssertEqual(upgraded.templates[index].collection.lists[0].cards[0].labelIDs, ["custom-tag"])
        XCTAssertFalse(upgraded.templates[index].collection.lists[0].cards[1].labelIDs.isEmpty)
        XCTAssertEqual(upgraded.bundledRoutineRevision, 5)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryHelpSearchIncludesInstructionsAndExcludesUserCollections
    /// @brief      Verify that library Help Search Includes Instructions And Excludes User Collections
    /// @details    Exercises `LibraryBrowseFilter.allCases.map`, `LibraryBrowseFilter.help.includes`, `articles.map`.
    ///             Checks `XCTAssertEqual(LibraryBrowseFilter.allCases.map(\.rawValue), ["All", "Lists", "Boards",
    ///             "Labels", "Examples", "Templates", "Help"])`;
    ///             `XCTAssertFalse(LibraryBrowseFilter.help.includes(collection))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLibraryHelpSearchIncludesInstructionsAndExcludesUserCollections() throws
    {

        XCTAssertEqual(
            LibraryBrowseFilter.allCases.map(\.rawValue),
            ["All", "Lists", "Boards", "Labels", "Examples", "Templates", "Help"])
        let collection = PersonalCollection(title: "Help", kind: .list)
        XCTAssertFalse(LibraryBrowseFilter.help.includes(collection))
        XCTAssertEqual(LibraryBrowseFilter.help.searchPrompt, "Find in Help")
        let articles = PlenactHelpCatalog.articles
        XCTAssertEqual(Set(articles.map(\.id)).count, articles.count)
        XCTAssertTrue(
            ["vision", "check-in", "evening", "weekly", "periodic"].allSatisfy
            {
                id in
                articles.contains
                {
                    $0.id == id && $0.opensPlan
                }

            })
        XCTAssertTrue(PlenactHelpCatalog.results(for: "carry objectives").contains
            {
                $0.id == "periodic"
            })
        XCTAssertTrue(PlenactHelpCatalog.results(for: "RESTORE DATA").contains
            {
                $0.id == "data"
            })
        XCTAssertTrue(PlenactHelpCatalog.results(for: "no-such-help-topic-9876").isEmpty)
        XCTAssertEqual(PlenactHelpCatalog.results(for: "  ").count, articles.count)
        XCTAssertTrue(PlenactHelpCatalog.groups.allSatisfy
            {
                group in
                articles.contains
                {
                    $0.group == group
                }

            })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCustomMoodRequiresOneEmojiAndMeaningfulShortText
    /// @brief      Verify that custom Mood Requires One Emoji And Meaningful Short Text
    /// @details    Exercises `CheckInMood.custom`. Checks `XCTAssertNotNil(CheckInMood.custom(emoji: emoji, label:
    ///             "Feeling focused"), emoji)`; `XCTAssertNil(CheckInMood.custom(emoji: emoji, label: "Focused"),
    ///             emoji)`.
    ///
    /// @return     (Void) no return value
    ///
    func testCustomMoodRequiresOneEmojiAndMeaningfulShortText()
    {

        for emoji in ["🌤️", "👩🏽‍💻", "🇺🇸", "❤️", "🫶🏽", "😊"]
        {

            XCTAssertNotNil(CheckInMood.custom(emoji: emoji, label: "Feeling focused"), emoji)
        }

        for emoji in ["", "  ", "a", "1", "😊😊", "hello"]
        {

            XCTAssertNil(CheckInMood.custom(emoji: emoji, label: "Focused"), emoji)
        }

        XCTAssertNil(CheckInMood.custom(emoji: "😊", label: "  "))
        XCTAssertNil(CheckInMood.custom(emoji: "😊", label: String(repeating: "a", count: 41)))
        XCTAssertNotNil(CheckInMood.custom(emoji: "😊", label: String(repeating: "a", count: 40)))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLowerCornerBackReservesSpaceOnlyWhenEnabledAndBackExists
    /// @brief      Verify that lower Corner Back Reserves Space Only When Enabled And Back Exists
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(try XCTUnwrap(heights["off"]) -
    ///             XCTUnwrap(heights["on"]), 44)`; `XCTAssertEqual(heights["root"], heights["off"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLowerCornerBackReservesSpaceOnlyWhenEnabledAndBackExists() async throws
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

        let suite = "CornerBackLayout." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        var heights: [String: CGFloat] = [:]
        var activations = 0
        for (name, enabled, hasBack, toolbar) in [
            ("off", false, true, CGFloat(0)), ("on", true, true, 0),
            ("root", true, false, 0), ("toolbar", true, true, 56)
        ]
        {

            var preferences = LocalProfilePreferences()
            preferences.enablesLowerCornerBack = enabled
            PlanPreferencesStore.save(preferences, to: defaults)
            var measured: CGFloat?
            let host = UIHostingController(
                rootView: Color.blue
                .onGeometryChange(for: CGFloat.self)
                {

                    $0.size.height
                }
                action:
                {

                    measured = $0
                }
                .modifier(LowerCornerBackShortcut(action: hasBack ?
                        {
                            activations += 1
                        } : nil))
                .environment(\.workspaceBottomBarHeight, toolbar)
                .defaultAppStorage(defaults))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(150))
            heights[name] = measured
            window.rootViewController = nil
        }

        XCTAssertEqual(try XCTUnwrap(heights["off"]) - XCTUnwrap(heights["on"]), 44, accuracy: 1)
        XCTAssertEqual(heights["root"], heights["off"])
        XCTAssertEqual(try XCTUnwrap(heights["on"]) - XCTUnwrap(heights["toolbar"]), 56, accuracy: 1)
        XCTAssertEqual(activations, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCornerBackResolvesLegacyProfileAndHonorsExplicitPreference
    /// @brief      Keep legacy profile settings and standalone shortcut settings consistent
    /// @details    Exercises an installation with profile-only preferences, an unreadable standalone record, and
    ///             an explicit standalone opt-out. Resolving preferences must not migrate or modify either record.
    ///
    /// @return     (Void) no return value
    /// @throws     XCTest fixture creation or JSON encoding errors
    ///
    func testCornerBackResolvesLegacyProfileAndHonorsExplicitPreference() throws
    {

        let suite = "CornerBackLegacy." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        var preferences = LocalProfilePreferences()
        preferences.enablesLowerCornerBack = true
        let profile = LocalProfile(displayName: "Synthetic", preferences: preferences)
        let profileData = try JSONEncoder().encode(profile)
        defaults.set(profileData, forKey: LocalProfileStore.storageKey)
        XCTAssertTrue(PlanPreferencesStore.load(from: defaults).enablesLowerCornerBack)
        XCTAssertTrue(
            PlanPreferencesStore.resolved(preferencesData: nil, profileData: profileData).enablesLowerCornerBack)
        XCTAssertTrue(
            PlanPreferencesStore.resolved(preferencesData: Data("invalid".utf8), profileData: profileData)
            .enablesLowerCornerBack)
        XCTAssertNil(defaults.object(forKey: PlanPreferencesStore.key))
        preferences.enablesLowerCornerBack = false
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertFalse(PlanPreferencesStore.load(from: defaults).enablesLowerCornerBack)
        XCTAssertFalse(
            PlanPreferencesStore.resolved(
                preferencesData: defaults.data(forKey: PlanPreferencesStore.key),
                profileData: profileData
            ).enablesLowerCornerBack)
        XCTAssertEqual(defaults.data(forKey: LocalProfileStore.storageKey), profileData)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreatedContentRevealFindsDestinationColumnAndGalleryTile
    /// @brief      Verify that created Content Reveal Finds Destination Column And Gallery Tile
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `CreatedContentReveal.shared.complete`. Checks `XCTAssertTrue(native.contains { $0.contentOffset.y
    ///             > 100 }, "Creation must reveal the row/tile, gallery: \(gallery)")`;
    ///             `XCTAssertTrue(native.contains { $0.contentOffset.x > 100 }, "Destination column must also be
    ///             revealed")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCreatedContentRevealFindsDestinationColumnAndGalleryTile() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            if let target = CreatedContentReveal.shared.target
            {
                CreatedContentReveal.shared.complete(target)
            }

            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testCreatedContentRevealFindsDestinationColumnAndGalleryTile.scrolls
        /// @brief      Find scrolls in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrolls(in view: UIView) -> [UIScrollView]
        {

            ((view as? UIScrollView).map
                {
                    [$0]
                }
                ?? []) + view.subviews.flatMap
            {
                scrolls(in: $0)
            }

        }

        for gallery in [false, true]
        {

            let owner = UUID()
            let key = BoardViewportMemory.prefix + owner.uuidString
            defer
            {
                UserDefaults.standard.removeObject(forKey: key)
            }

            var memory = BoardViewportState();
            memory.gallery = gallery
            UserDefaults.standard.set(try JSONEncoder().encode(memory), forKey: key)
            var destination = KanbanList(id: 2, title: "Destination", cards: [])
            destination.cards = (0 ..< 40).map
            {
                destination.makeItem(id: $0, title: "Item \($0)")
            }

            let lists = [
                KanbanList(id: 0, title: "First", cards: []), KanbanList(id: 1, title: "Second", cards: []), destination
            ]
            let host = UIHostingController(
                rootView: ContentView(lists: .constant(lists), retainedAttachmentLists:
                    {
                        []
                    }, viewportOwnerID: owner))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            CreatedContentReveal.shared.request(listID: destination.id, card: try XCTUnwrap(destination.cards.last))
            try await Task.sleep(for: .milliseconds(1500))
            host.view.layoutIfNeeded()
            let native = scrolls(in: host.view)
            XCTAssertTrue(
                native.contains
                {
                    $0.contentOffset.y > 100
                }, "Creation must reveal the row/tile, gallery: \(gallery)")
            if !gallery
            {

                XCTAssertTrue(native.contains
                    {
                        $0.contentOffset.x > 100
                    }, "Destination column must also be revealed")
            }

            XCTAssertNil(CreatedContentReveal.shared.target)
            window.rootViewController = nil
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreatedContentRevealTargetsExactRecordAndRetainsNewerRequests
    /// @brief      Verify that created Content Reveal Targets Exact Record And Retains Newer Requests
    /// @details    Exercises `KanbanList(id: 4, title: "Monday", cards: []).makeItem`, `KanbanList(id: 4, title:
    ///             "Other Board", cards: []).makeItem`, `reveal.request`. Checks
    ///             `XCTAssertTrue(original.matches(KanbanList(id: 4, title: "Monday", cards: [first])))`;
    ///             `XCTAssertFalse(original.matches(KanbanList(id: 4, title: "Other Board", cards: [collision])))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCreatedContentRevealTargetsExactRecordAndRetainsNewerRequests() throws
    {

        let reveal = CreatedContentReveal()
        let first = KanbanList(id: 4, title: "Monday", cards: []).makeItem(
            id: 10, title: "New Card", createdAt: Date(timeIntervalSince1970: 100))
        let collision = KanbanList(id: 4, title: "Other Board", cards: []).makeItem(
            id: 10, title: "Different Card", createdAt: Date(timeIntervalSince1970: 200))
        reveal.request(listID: 4, card: first)
        let original = try XCTUnwrap(reveal.target)
        XCTAssertTrue(original.matches(KanbanList(id: 4, title: "Monday", cards: [first])))
        XCTAssertFalse(original.matches(KanbanList(id: 4, title: "Other Board", cards: [collision])))
        XCTAssertFalse(original.matches(KanbanList(id: 5, title: "Another List", cards: [first])))
        XCTAssertFalse(original.matches(KanbanList(id: 4, title: "Monday", cards: [])))
        var note = collision
        note.presentation = .note
        reveal.request(listID: 4, card: note)
        let next = try XCTUnwrap(reveal.target)
        reveal.complete(original)
        XCTAssertEqual(reveal.target, next)
        XCTAssertTrue(next.matches(KanbanList(id: 4, title: "Other Board", cards: [note])))
        reveal.complete(next)
        XCTAssertNil(reveal.target)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDailySlogansStayStableAndRotateThroughSixtyLocalDays
    /// @brief      Verify that daily Slogans Stay Stable And Rotate Through Sixty Local Days
    /// @details    Exercises `TodaySloganCatalog.slogan`, `seen.insert`. Checks
    ///             `XCTAssertEqual(TodaySloganCatalog.slogans.count, 60)`;
    ///             `XCTAssertEqual(Set(TodaySloganCatalog.slogans).count, 60)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDailySlogansStayStableAndRotateThroughSixtyLocalDays() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        XCTAssertEqual(TodaySloganCatalog.slogans.count, 60)
        XCTAssertEqual(Set(TodaySloganCatalog.slogans).count, 60)
        var seen = Set<String>()
        for day in 0 ..< 60
        {

            let morning = try XCTUnwrap(calendar.date(byAdding: .day, value: day, to: anchor))
            let evening = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 59, second: 59, of: morning))
            let slogan = TodaySloganCatalog.slogan(on: morning, calendar: calendar)
            XCTAssertEqual(slogan, TodaySloganCatalog.slogan(on: evening, calendar: calendar))
            seen.insert(slogan)
        }

        XCTAssertEqual(seen.count, 60)
        let repeatDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 60, to: anchor))
        XCTAssertEqual(TodaySloganCatalog.slogan(on: repeatDay, calendar: calendar), TodaySloganCatalog.slogans[0])
        let previous = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: anchor))
        XCTAssertEqual(TodaySloganCatalog.slogan(on: previous, calendar: calendar), TodaySloganCatalog.slogans[59])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDailySloganUsesLocalMidnightAcrossTimeZones
    /// @brief      Verify that daily Slogan Uses Local Midnight Across Time Zones
    /// @details    Exercises `ISO8601DateFormatter().date`, `TodaySloganCatalog.slogan`. Checks
    ///             `XCTAssertEqual(TodaySloganCatalog.slogan(on: instant, calendar: chicago),
    ///             TodaySloganCatalog.slogans[0])`; `XCTAssertEqual(TodaySloganCatalog.slogan(on: instant, calendar:
    ///             london), TodaySloganCatalog.slogans[1])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDailySloganUsesLocalMidnightAcrossTimeZones() throws
    {

        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-16T04:30:00Z"))
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        var london = chicago
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        XCTAssertEqual(TodaySloganCatalog.slogan(on: instant, calendar: chicago), TodaySloganCatalog.slogans[0])
        XCTAssertEqual(TodaySloganCatalog.slogan(on: instant, calendar: london), TodaySloganCatalog.slogans[1])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReferenceLabelSupportsLegacyAndExistingCustomCatalogs
    /// @brief      Verify that reference Label Supports Legacy And Existing Custom Catalogs
    /// @details    Checks `XCTAssertEqual(legacy.includingReference.labels, [LabelLibrary.referenceLabel])`;
    ///             `XCTAssertEqual(library.includingReference.labels, [custom])`.
    ///
    /// @return     (Void) no return value
    ///
    func testReferenceLabelSupportsLegacyAndExistingCustomCatalogs()
    {

        let legacy = LabelLibrary(categories: [], labels: [])
        XCTAssertEqual(legacy.includingReference.labels, [LabelLibrary.referenceLabel])
        let custom = KanbanLabel(id: "my-reference", name: "Reference", categoryID: "custom", color: .blue)
        let library = LabelLibrary(categories: [], labels: [custom])
        XCTAssertEqual(library.includingReference.labels, [custom])
        XCTAssertEqual(library.includingReference.referenceLabelID, custom.id)
        XCTAssertEqual(LabelLibrary.starter.includingReference, LabelLibrary.starter)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSessionGuidanceMigrationPreservesCustomizedWelcomeCards
    /// @brief      Verify legacy welcome conversion never removes user-edited content
    /// @details    Loads pristine, edited, completed, and bookmarked fixtures through the real store.
    ///             New starters and transient guides remain outside stored item counts.
    ///
    /// @return     (Void) records migration and content-preservation assertions
    /// @throws     Propagates temporary defaults and persistence failures.
    ///
    func testSessionGuidanceMigrationPreservesCustomizedWelcomeCards() throws
    {

        let suite = "SessionGuidance." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        for title in ["On the Table", "In the Queue", "Scheduled"]
        {

            let original = DefaultListTutorial.makeStarter(title: title, includesWelcomeCard: true)
            var edited = original
            edited.lists[0].cards[0].word += " personalized"
            var completed = original
            completed.lists[0].cards[0].isTitleChecked = true
            var bookmarked = original
            bookmarked.savedCardIDs.insert(0)
            for retained in [edited, completed, bookmarked]
            {

                XCTAssertEqual(DefaultListTutorial.removingUntouchedWelcomeCards(from: retained), retained)
            }

            try PersonalCollectionStore.saveChecked([original], to: defaults)
            let loaded = try XCTUnwrap(PersonalCollectionStore.load(from: defaults).first)
            XCTAssertTrue(loaded.lists[0].cards.isEmpty)
            XCTAssertEqual(loaded.id, original.id)
            XCTAssertEqual(loaded.boardAppearance, original.boardAppearance)
            XCTAssertTrue(DefaultListTutorial.makeStarter(title: title).lists[0].cards.isEmpty)
        }

        XCTAssertNil(DefaultListTutorial.guidance(for: "A custom List"))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDefaultListsDoNotReplaceExistingOrLegacyInstallations
    /// @brief      Verify that default Lists Do Not Replace Existing Or Legacy Installations
    /// @details    Exercises `TodayListPins.loadInitialCollections`. Checks
    ///             `XCTAssertTrue(TodayListPins.loadInitialCollections(from: defaults).isEmpty)`;
    ///             `XCTAssertEqual(defaults.data(forKey: savedKey), saved)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDefaultListsDoNotReplaceExistingOrLegacyInstallations() throws
    {

        for savedKey in [
                        "Plenact.PersonalCollections.v1", "Plenact.Board.v1", PlanningCalendarStore.key, TodayListPins.key
        ]
        {

            let suite = "Plenact.ExistingInstallTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer
            {
                defaults.removePersistentDomain(forName: suite)
            }

            let saved = Data("preserve saved bytes".utf8)
            defaults.set(saved, forKey: savedKey)
            XCTAssertTrue(TodayListPins.loadInitialCollections(from: defaults).isEmpty)
            XCTAssertEqual(defaults.data(forKey: savedKey), saved)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWorkspaceLabelsCountOnlyActiveItemsAndKeepOwnerIdentity
    /// @brief      Verify that workspace Labels Count Only Active Items And Keep Owner Identity
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `card.replacingLocation`. Checks
    ///             `XCTAssertEqual(usage.matches.count, 2)`; `XCTAssertEqual(Set(usage.matches.map(\.collectionID)),
    ///             [week.id, library.id])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWorkspaceLabelsCountOnlyActiveItemsAndKeepOwnerIdentity() throws
    {

        let catalog = LabelLibrary.starter
        let label = try XCTUnwrap(catalog.labels.first)
        let date = try XCTUnwrap(PlanningDate.date("2026-10-15"))
        var week = DatedPlanningWeek.make(for: date)
        var card = KanbanCard(id: 5, word: "Week card", listTitle: week.collection.lists[0].title)
        card.labelIDs = [label.id, label.id]
        week.collection.lists[0].cards = [card]
        week.collection.lists[0].archivedCards = [card.replacingLocation(id: 88, listTitle: "Archive")]
        var library = PersonalCollection(title: "Notes", kind: .list)
        var note = card.replacingLocation(id: 5, listTitle: library.title)
        note.presentation = .note
        library.lists[0].cards = [note]
        var archived = PersonalCollection(title: "Old", kind: .board)
        archived.isArchived = true
        archived.lists[0].cards = [card]
        var hidden = KanbanList(id: 100, title: "Archived list", cards: [card])
        hidden.isArchived = true
        library.lists.append(hidden)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        let owners = WorkspaceBrowseIndex.owners(document: document, library: [library, archived])
        let usage = try XCTUnwrap(WorkspaceBrowseIndex.labels(in: owners, catalog: catalog).first
            {
                $0.id == label.id
            })
        XCTAssertEqual(usage.matches.count, 2)
        XCTAssertEqual(Set(usage.matches.map(\.collectionID)), [week.id, library.id])
        XCTAssertEqual(Set(usage.matches.map(\.id)).count, 2, "Identical numeric IDs in different owners stay distinct")
        XCTAssertEqual(usage.matches.filter
            {
                $0.card.presentation == .note
            } .count, 1)
        XCTAssertFalse(WorkspaceBrowseIndex.lists(in: owners).contains
            {
                $0.list.isArchived
            })
        XCTAssertFalse(LibraryBrowseFilter.labels.includes(library))
        XCTAssertEqual(LibraryBrowseFilter.labels.searchPrompt, "Find in your Labels")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayShortcutPinsKeepOrderOwnerAndSixItemLimit
    /// @brief      Verify that today Shortcut Pins Keep Order Owner And Six Item Limit
    /// @details    Exercises `(1...8).map`, `TodayListPins.decode`, `TodayListPins.encode`. Checks
    ///             `XCTAssertEqual(decoded.count, 6)`; `XCTAssertEqual(Array(decoded.prefix(2)), [first, second])`.
    ///
    /// @return     (Void) no return value
    ///
    func testTodayShortcutPinsKeepOrderOwnerAndSixItemLimit()
    {

        let first = WorkspaceListReference(ownerID: UUID(), listID: 0)
        let second = WorkspaceListReference(ownerID: UUID(), listID: 0)
        let extras = (1 ... 8).map
        {
            WorkspaceListReference(ownerID: first.ownerID, listID: $0)
        }

        let pins = [first, second, first] + extras
        let decoded = TodayListPins.decode(TodayListPins.encode(pins))
        XCTAssertEqual(decoded.count, 6)
        XCTAssertEqual(Array(decoded.prefix(2)), [first, second])
        XCTAssertEqual(Set(decoded).count, 6)
        XCTAssertTrue(TodayListPins.decode(Data("invalid".utf8)).isEmpty)
        XCTAssertEqual(TodayListPins.decode(TodayListPins.encode(Array(decoded.reversed()))), Array(decoded.reversed()))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWelcomeCueLaunchAndFourHourReturnPolicy
    /// @brief      Verify that welcome Cue Launch And Four Hour Return Policy
    /// @details    Exercises `cue.becameActive`, `cue.cancel`, `start.addingTimeInterval`. Checks
    ///             `XCTAssertTrue(cue.pending)`; `XCTAssertEqual(cue.requestID, 1)`.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func testWelcomeCueLaunchAndFourHourReturnPolicy()
    {

        let name = "PlenactTests.WelcomePolicy." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cue = TodayWelcomeCue(defaults: defaults)
        cue.becameActive(at: start)
        XCTAssertTrue(cue.pending);
        XCTAssertEqual(cue.requestID, 1)
        cue.cancel()
        cue.becameActive(at: start.addingTimeInterval(1))
        XCTAssertFalse(cue.pending);
        XCTAssertEqual(cue.requestID, 1)
        cue.leftForeground(at: start)
        cue.leftForeground(at: start.addingTimeInterval(10))  // inactive → background records one departure
        XCTAssertEqual(defaults.double(forKey: TodayWelcomeCue.lastDepartureKey), start.timeIntervalSince1970)
        cue.becameActive(at: start.addingTimeInterval(TodayWelcomeCue.returnInterval - 1))
        XCTAssertFalse(cue.pending)
        cue.leftForeground(at: start)
        cue.becameActive(at: start.addingTimeInterval(TodayWelcomeCue.returnInterval))
        XCTAssertTrue(cue.pending);
        XCTAssertEqual(cue.requestID, 2)
        let freshProcess = TodayWelcomeCue(defaults: defaults)
        freshProcess.becameActive(at: start.addingTimeInterval(2))
        XCTAssertTrue(freshProcess.pending)  // Every launch is intentionally testable.
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWelcomeCuePulsesInOrderAndSettlesWithoutRepeating
    /// @brief      Verify that welcome Cue Pulses In Order And Settles Without Repeating
    /// @details    Exercises `cue.becameActive`, `cue.play`, `highlights.append`. Checks `XCTAssertEqual(highlights,
    ///             [.profile, .profile, .plan, .plan])`; `XCTAssertNil(cue.target)`.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func testWelcomeCuePulsesInOrderAndSettlesWithoutRepeating() async
    {

        let cue = TodayWelcomeCue(defaults: UserDefaults(suiteName: "PlenactTests.WelcomeSequence")!)
        cue.becameActive()
        var highlights: [TodayWelcomeCue.Target] = []
        await cue.play(reduceMotion: false)
        {
            _ in
            if cue.illuminated, let target = cue.target
            {
                highlights.append(target)
            }

        }

        XCTAssertEqual(highlights, [.profile, .profile, .plan, .plan])
        XCTAssertNil(cue.target);
        XCTAssertFalse(cue.illuminated);
        XCTAssertFalse(cue.pending)
        await cue.play(reduceMotion: false)
        {
            _ in
            XCTFail("A completed greeting must not repeat")
        }

        cue.becameActive()
        XCTAssertFalse(cue.pending)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWelcomeCueReduceMotionAndInteractionCancellation
    /// @brief      Verify that welcome Cue Reduce Motion And Interaction Cancellation
    /// @details    Exercises `cue.becameActive`, `cue.play`, `highlights.append`. Checks `XCTAssertEqual(highlights,
    ///             [.profile, .plan])`; `XCTAssertEqual(highlights, [.profile])`.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func testWelcomeCueReduceMotionAndInteractionCancellation() async
    {

        let cue = TodayWelcomeCue(defaults: UserDefaults(suiteName: "PlenactTests.WelcomeCancellation")!)
        cue.becameActive()
        var highlights: [TodayWelcomeCue.Target] = []
        await cue.play(reduceMotion: true)
        {
            _ in
            if cue.illuminated, let target = cue.target
            {
                highlights.append(target)
            }

        }

        XCTAssertEqual(highlights, [.profile, .plan])  // One static highlight each, no repeated pulses.
        cue.leftForeground(at: .distantPast);
        cue.becameActive()
        highlights = []
        await cue.play(reduceMotion: false)
        {
            _ in
            if cue.illuminated, let target = cue.target
            {
                highlights.append(target);
                cue.cancel()
            }

        }

        XCTAssertEqual(highlights, [.profile])
        XCTAssertNil(cue.target);
        XCTAssertFalse(cue.illuminated)
        cue.leftForeground(at: .distantPast);
        cue.becameActive()
        await cue.play(reduceMotion: false)
        {
            _ in
            throw CancellationError()
        }

        XCTAssertNil(cue.target);
        XCTAssertFalse(cue.illuminated)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLaunchPacingRevealsEvenlyAndWaitsForReadiness
    /// @brief      Verify that launch Pacing Reveals Evenly And Waits For Readiness
    /// @details    Exercises `ready.paced`, `loading.paced(elapsed: 2).status`, `loading.paced`. Checks
    ///             `XCTAssertEqual(visual.stage, stage)`; `XCTAssertFalse(visual.finished)`.
    ///
    /// @return     (Void) no return value
    ///
    func testLaunchPacingRevealsEvenlyAndWaitsForReadiness()
    {

        let ready = PlenactLaunchProgress(stage: .welcome, finished: true)
        for (time, stage) in [(0.0, PlenactLaunchStage.restore), (0.23, .plans), (0.45, .ready), (0.67, .welcome)]
        {

            let visual = ready.paced(elapsed: time)
            XCTAssertEqual(visual.stage, stage)
            XCTAssertFalse(visual.finished)
        }

        XCTAssertTrue(ready.paced(elapsed: 0.9).finished)
        let loading = PlenactLaunchProgress(stage: .plans)
        XCTAssertEqual(loading.paced(elapsed: 2).status(for: .welcome), .running)
        XCTAssertFalse(loading.paced(elapsed: 2).finished)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDaySelectorResolvesDatesAcrossWeeksWithoutChangingContent
    /// @brief      Verify that day Selector Resolves Dates Across Weeks Without Changing Content
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `PlanningDate.key`. Checks
    ///             `XCTAssertEqual(selection.listID, dayID)`; `XCTAssertEqual(selection.week, week)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDaySelectorResolvesDatesAcrossWeeksWithoutChangingContent() throws
    {

        for firstWeekday in [1, 2]
        {

            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday
            let date = try XCTUnwrap(PlanningDate.date("2026-10-13"))
            var week = DatedPlanningWeek.make(for: date, calendar: calendar)
            let dayID = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date, calendar: calendar)])
            let index = try XCTUnwrap(week.collection.lists.firstIndex
                {
                    $0.id == dayID
                })
            week.collection.lists[index].cards = [
                KanbanCard(id: 333, word: "Selected day's content", listTitle: week.collection.lists[index].title)
            ]
            let document = PlanningCalendarDocument(
                currentWeekKey: week.startKey, firstWeekday: firstWeekday, weeks: [week])
            let original = document
            let selection = try XCTUnwrap(PlanningDaySelection.resolve(date, document: document))
            XCTAssertEqual(selection.listID, dayID)
            XCTAssertEqual(selection.week, week)
            for offset in -9 ... 9
            {

                let target = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: date))
                let selected = try XCTUnwrap(PlanningDaySelection.resolve(target, document: document))
                XCTAssertEqual(selected.week.startKey, PlanningDate.weekKey(target, calendar: calendar))
                XCTAssertEqual(selected.week.dayListIDs[PlanningDate.key(target, calendar: calendar)], selected.listID)
                XCTAssertTrue(selected.week.collection.lists.contains
                    {
                        $0.id == selected.listID && !$0.isArchived
                    })
            }

            XCTAssertEqual(document, original)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardDisplayProfilesResolveCardThenListThenBoard
    /// @brief      Verify that card Display Profiles Resolve Card Then List Then Board
    /// @details    Exercises `board.resolvedCardDetail`. Checks `XCTAssertEqual(board.resolvedCardDetail(card: nil,
    ///             list: nil), .detailed)`; `XCTAssertEqual(board.resolvedCardDetail(card: nil, list: nil, fallback:
    ///             .compact), .compact)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCardDisplayProfilesResolveCardThenListThenBoard() throws
    {

        var board = BoardAppearance()
        XCTAssertEqual(board.resolvedCardDetail(card: nil, list: nil), .detailed)
        XCTAssertEqual(board.resolvedCardDetail(card: nil, list: nil, fallback: .compact), .compact)
        board.cardDetail = .compact
        var list = ItemAppearance()
        var card = ItemAppearance()
        XCTAssertEqual(board.resolvedCardDetail(card: card, list: list), .compact)
        list.cardDetail = .detailed
        XCTAssertEqual(board.resolvedCardDetail(card: card, list: list), .detailed)
        card.cardDetail = .compact
        XCTAssertEqual(board.resolvedCardDetail(card: card, list: list), .compact)
        card.cardDetail = nil
        XCTAssertEqual(board.resolvedCardDetail(card: card, list: list), .detailed)
        list.cardDetail = nil
        XCTAssertEqual(board.resolvedCardDetail(card: card, list: list), .compact)
        board.cardDetail = nil
        XCTAssertEqual(board.resolvedCardDetail(card: card, list: list), .detailed)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardDisplayProfilesRoundTripWithoutChangingContent
    /// @brief      Verify that card Display Profiles Round Trip Without Changing Content
    /// @details    Exercises `BoardAppearance.inheritingLists`. Checks `XCTAssertEqual(decoded, collection)`;
    ///             `XCTAssertEqual(decoded.lists[0].cards[0].descriptionOverride, "Keep my writing")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCardDisplayProfilesRoundTripWithoutChangingContent() throws
    {

        var collection = PersonalCollection(title: "Profiles", kind: .board)
        var card = KanbanCard(id: 65, word: "Keep my title", listTitle: collection.lists[0].title)
        card.descriptionOverride = "Keep my writing"
        card.appearance = ItemAppearance()
        card.appearance?.cardDetail = .detailed
        collection.lists[0].appearance = ItemAppearance()
        collection.lists[0].appearance?.cardDetail = .compact
        collection.lists[0].cards = [card]
        collection.boardAppearance = BoardAppearance()
        collection.boardAppearance?.cardDetail = .detailed
        let decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection))
        XCTAssertEqual(decoded, collection)
        XCTAssertEqual(decoded.lists[0].cards[0].descriptionOverride, "Keep my writing")
        XCTAssertFalse(try XCTUnwrap(decoded.lists[0].cards[0].appearance).isEmpty)
        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.cardDetail)
        XCTAssertTrue(legacy.isEmpty)
        var profileOnly = ItemAppearance()
        profileOnly.cardDetail = .compact
        XCTAssertFalse(profileOnly.isEmpty)
        let retained = BoardAppearance.inheritingLists(decoded.lists)
        XCTAssertEqual(
            retained[0].appearance?.cardDetail, .compact, "Applying Board colors must keep List display profiles")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekTodayHighlightUsesExactDateAcrossWeeksAndTimeZones
    /// @brief      Verify that week Today Highlight Uses Exact Date Across Weeks And Time Zones
    /// @details    Exercises `PlanningDate.date`, `WeekDayHighlight.isToday`. Checks
    ///             `XCTAssertTrue(WeekDayHighlight.isToday(today, now: today, calendar: calendar))`;
    ///             `XCTAssertFalse(WeekDayHighlight.isToday(nil, now: today, calendar: calendar))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWeekTodayHighlightUsesExactDateAcrossWeeksAndTimeZones() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let today = try XCTUnwrap(PlanningDate.date("2026-10-17", calendar: calendar))
        XCTAssertTrue(WeekDayHighlight.isToday(today, now: today, calendar: calendar))
        XCTAssertFalse(WeekDayHighlight.isToday(nil, now: today, calendar: calendar))
        for key in ["2026-10-10", "2026-10-16", "2026-10-18", "2026-10-24"]
        {

            XCTAssertFalse(
                WeekDayHighlight.isToday(PlanningDate.date(key, calendar: calendar), now: today, calendar: calendar))
        }

        let beforeMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23, minute: 59)))
        let afterMidnight = try XCTUnwrap(calendar.date(byAdding: .minute, value: 2, to: beforeMidnight))
        XCTAssertTrue(WeekDayHighlight.isToday(today, now: beforeMidnight, calendar: calendar))
        XCTAssertFalse(WeekDayHighlight.isToday(today, now: afterMidnight, calendar: calendar))
        XCTAssertTrue(
            WeekDayHighlight.isToday(
                PlanningDate.date("2026-10-18", calendar: calendar), now: afterMidnight, calendar: calendar))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyMondayFirstBoardUsesFollowingSundayWithoutRelabellingOldWork
    /// @brief      Verify that legacy Monday First Board Uses Following Sunday Without Relabelling Old Work
    /// @details    Exercises `PlanningDate.date`, `titles.enumerated().map`, `titles.enumerated`. Checks
    ///             `XCTAssertTrue(try document.repairLegacyMondayFirstLayout(now: saturday))`;
    ///             `XCTAssertEqual(document.firstWeekday, 2)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testLegacyMondayFirstBoardUsesFollowingSundayWithoutRelabellingOldWork() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!;
        calendar.firstWeekday = 1
        let saturday = try XCTUnwrap(PlanningDate.date("2026-10-17", calendar: calendar))
        let oldSunday = try XCTUnwrap(PlanningDate.date("2026-10-11", calendar: calendar))
        let nextSunday = try XCTUnwrap(PlanningDate.date("2026-10-18", calendar: calendar))
        let titles = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let lists = titles.enumerated().map
        {
            KanbanList(id: $0.offset, title: $0.element, cards: [])
        }

        var legacy = DatedPlanningWeek.make(for: saturday, lists: lists, calendar: calendar)
        legacy.collection.lists[6].cards = [
            KanbanCard(id: 42, word: "October 11 work", listTitle: "Sunday", checklists: [])
        ]
        var document = PlanningCalendarDocument(currentWeekKey: legacy.startKey, firstWeekday: 1, weeks: [legacy])
        XCTAssertTrue(try document.repairLegacyMondayFirstLayout(now: saturday))
        XCTAssertEqual(document.firstWeekday, 2)
        XCTAssertEqual(document.currentWeekKey, "2026-10-12")
        let current = try XCTUnwrap(document.week(for: saturday))
        XCTAssertEqual(current.collection.lists.map(\.title), titles)
        XCTAssertEqual(current.dayListIDs.first
            {
                $0.value == current.collection.lists[5].id
            }?.key, "2026-10-17")
        XCTAssertEqual(current.dayListIDs.first
            {
                $0.value == current.collection.lists[6].id
            }?.key, "2026-10-18")
        XCTAssertTrue(try XCTUnwrap(current.list(on: nextSunday)).cards.isEmpty)
        XCTAssertEqual(document.week(for: oldSunday)?.list(on: oldSunday)?.cards.first?.word, "October 11 work")
        XCTAssertFalse(try document.repairLegacyMondayFirstLayout(now: saturday))
        var sundayFirst = PlanningCalendarDocument(
            currentWeekKey: legacy.startKey, firstWeekday: 1,
            weeks: [DatedPlanningWeek.make(for: saturday, calendar: calendar)])
        let before = sundayFirst
        XCTAssertFalse(try sundayFirst.repairLegacyMondayFirstLayout(now: saturday))
        XCTAssertEqual(sundayFirst, before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testMondayStartOnSundayKeepsConsecutiveDatesAndFollowingSundaySeparate
    /// @brief      Verify that monday Start On Sunday Keeps Consecutive Dates And Following Sunday Separate
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `original.list`. Checks
    ///             `XCTAssertEqual(document.currentWeekKey, "2026-10-05")`; `XCTAssertEqual(current.startKey,
    ///             "2026-10-05")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testMondayStartOnSundayKeepsConsecutiveDatesAndFollowingSundaySeparate() throws
    {

        let today = try XCTUnwrap(PlanningDate.date("2026-10-11"))
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        var original = DatedPlanningWeek.make(for: today, calendar: calendar)
        let sundayID = try XCTUnwrap(original.list(on: today)?.id)
        let index = try XCTUnwrap(original.collection.lists.firstIndex
            {
                $0.id == sundayID
            })
        original.collection.lists[index].cards = [KanbanCard(id: 42, word: "October 11 plans", listTitle: "Sunday")]
        var document = PlanningCalendarDocument(currentWeekKey: original.startKey, firstWeekday: 1, weeks: [original])
        try document.changeFirstWeekday(to: 2, now: today)
        let current = try XCTUnwrap(document.week(for: today))
        XCTAssertEqual(document.currentWeekKey, "2026-10-05")
        XCTAssertEqual(current.startKey, "2026-10-05")
        let dates = try current.collection.lists.map
        {
            list in
            try XCTUnwrap(current.dayListIDs.first
                {
                    $0.value == list.id
                }?.key)
        }

        XCTAssertEqual(
            dates, ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11"])
        XCTAssertEqual(current.collection.lists.last?.cards.first?.word, "October 11 plans")
        let followingSunday = try XCTUnwrap(PlanningDate.date("2026-10-18"))
        let following = try XCTUnwrap(document.week(for: followingSunday))
        XCTAssertEqual(following.startKey, "2026-10-12")
        XCTAssertTrue(try XCTUnwrap(following.list(on: followingSunday)).cards.isEmpty)
        XCTAssertEqual(following.dayListIDs.count, 7)
        XCTAssertFalse(following.dayListIDs.keys.contains("2026-10-11"))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDueBadgeOmitsOnlyTheOwningListsAssignedDay
    /// @brief      Verify that due Badge Omits Only The Owning Lists Assigned Day
    /// @details    Exercises `card.dueDateBadge`. Checks `XCTAssertNil(card.dueDateBadge(on: sameDay))`;
    ///             `XCTAssertEqual(card.dueDateBadge(on: nextWeek)?.label, card.dueDateLabel)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDueBadgeOmitsOnlyTheOwningListsAssignedDay() throws
    {

        let calendar = Calendar.current
        let due = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 17, minute: 46)))
        let sameDay = calendar.startOfDay(for: due)
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: sameDay))
        var card = KanbanCard(
            id: 0, word: "Task", listTitle: "Renamed list", dueDate: due,
            showsDueDateInList: true, dueDateKind: .date)
        XCTAssertNil(card.dueDateBadge(on: sameDay))
        XCTAssertEqual(card.dueDateBadge(on: nextWeek)?.label, card.dueDateLabel)
        XCTAssertEqual(
            card.dueDateBadge(on: nil)?.systemImage, "calendar", "Undated Library lists retain the full date")
        card.dueDateKind = .dateAndTime
        XCTAssertEqual(card.dueDateBadge(on: sameDay)?.label, "5:46 PM")
        XCTAssertEqual(card.dueDateBadge(on: sameDay)?.systemImage, "clock")
        XCTAssertEqual(card.dueDateBadge(on: nextWeek)?.label, card.dueDateLabel)
        XCTAssertEqual(card.dueDateBadge(on: nextWeek)?.systemImage, "calendar")
        XCTAssertEqual(card.dueDateKind, .dateAndTime, "Compact rendering must retain the saved type")
        XCTAssertEqual(card.dueDate, due)
        card.dueDateKind = .time
        XCTAssertEqual(card.dueDateBadge(on: nil)?.label, "5:46 PM")
        XCTAssertEqual(card.dueDateBadge(on: nextWeek)?.systemImage, "clock")
        card.showsDueDateInList = false
        XCTAssertNil(card.dueDateBadge(on: sameDay))
        card.showsDueDateInList = true
        card.dueDate = nil
        XCTAssertNil(card.dueDateBadge(on: nil))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testOverflowReadingPreferenceSwitchesMountedReaderWithoutChangingText
    /// @brief      Verify that overflow Reading Preference Switches Mounted Reader Without Changing Text
    /// @details    Exercises `PlanPreferencesStore.save`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertTrue(scrolls(host.view).isEmpty)`;
    ///             `XCTAssertEqual(overflow.last, false)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testOverflowReadingPreferenceSwitchesMountedReaderWithoutChangingText() async throws
    {

        let suite = "OverflowReaderRender." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        var preferences = LocalProfilePreferences(scrollsOverflowingTitles: false)
        PlanPreferencesStore.save(preferences, to: defaults)
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
        /// @fcn        PlenactBoardDocumentTests.testOverflowReadingPreferenceSwitchesMountedReaderWithoutChangingText.scrolls
        /// @brief      Find scrolls in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrolls(_ view: UIView) -> [UIScrollView]
        {

            ((view as? UIScrollView).map
                {
                    [$0]
                }
                ?? []) + view.subviews.flatMap(scrolls)
        }

        let title = "A long title that can be read with a horizontal slide when this preference is enabled"
        var overflow: [Bool] = []
        let host = UIHostingController(
            rootView: SlideableHeaderText(
                text: title,
                onOverflowChange:
                {
                    overflow.append($0)
                }
            ).font(.headline).frame(width: 180).defaultAppStorage(defaults))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host;
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(scrolls(host.view).isEmpty)
        XCTAssertEqual(overflow.last, false)
        preferences.scrollsOverflowingTitles = true
        PlanPreferencesStore.save(preferences, to: defaults)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(scrolls(host.view).contains
            {
                $0.isScrollEnabled && $0.contentSize.width > $0.bounds.width
            })
        XCTAssertEqual(overflow.last, true)
        preferences.scrollsOverflowingTitles = false
        PlanPreferencesStore.save(preferences, to: defaults)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(scrolls(host.view).isEmpty)
        XCTAssertEqual(overflow.last, false)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryLongNamesStayCompactAndExpandForAccessibility
    /// @brief      Verify that library Long Names Stay Compact And Expand For Accessibility
    /// @details    Exercises `row.environment`, `standard.sizeThatFits`, `accessible.sizeThatFits`. Checks
    ///             `XCTAssertLessThan(standardSize.height, 100)`; `XCTAssertGreaterThan(accessibleSize.height,
    ///             standardSize.height)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLibraryLongNamesStayCompactAndExpandForAccessibility() async throws
    {

        let title = Array(repeating: "On the Table", count: 8).joined(separator: ", ")
        let row = LibraryCollectionRow(title: title, subtitle: "List", icon: "list.bullet", color: .red, count: 7)
        let standard = UIHostingController(rootView: row.environment(\.dynamicTypeSize, .large))
        let accessible = UIHostingController(rootView: row.environment(\.dynamicTypeSize, .accessibility3))
        let standardSize = standard.sizeThatFits(in: CGSize(width: 300, height: 1000))
        let accessibleSize = accessible.sizeThatFits(in: CGSize(width: 300, height: 3000))
        XCTAssertLessThan(standardSize.height, 100, "Two-line names must not dominate the directory")
        XCTAssertGreaterThan(accessibleSize.height, standardSize.height, "Accessibility names retain expanded reading")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEditorBannerDoesNotInsertNativeNavigationBar
    /// @brief      Verify that editor Banner Does Not Insert Native Navigation Bar
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertTrue(navigation.isNavigationBarHidden, "The custom editor
    ///             controls must not gain an empty native bar")`; `XCTAssertTrue(emitted.isEmpty, "Banner layout must
    ///             not change the record")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testEditorBannerDoesNotInsertNativeNavigationBar() async throws
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
        /// @fcn        PlenactBoardDocumentTests.testEditorBannerDoesNotInsertNativeNavigationBar.navigationController
        /// @brief      Prepare navigation controller for the enclosing regression test
        /// @details    Supplies the local fixture for editor Banner Does Not Insert Native Navigation Bar. Uses
        ///             `controller.children.compactMap`.
        ///
        /// @param[in]  controller  Native controller supplied to the lifecycle callback
        ///
        /// @return     (UINavigationController?) matching or resolved value, or nil when unavailable
        ///
        func navigationController(in controller: UIViewController) -> UINavigationController?
        {

            if let navigation = controller as? UINavigationController
            {

                return navigation
            }

            return controller.children.compactMap
            {
                navigationController(in: $0)
            } .first
        }


        for isNote in [false, true]
        {

            for background in [nil, ItemAccent.orange]
            {

                let card = KanbanCard(
                    id: 94, word: "Synthetic banner", listTitle: "Friday",
                    presentation: isNote ? .note : .card,
                    appearance: background.map
                    {
                        ItemAppearance(background: $0)
                    }
                )
                var emitted: [KanbanCard] = []
                let controller = UIHostingController(
                    rootView: NavigationStack
                    {

                        CardDetailView(card: card, onTitleToggle:
                            {
                                emitted.append($0)
                            })
                    })
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))

                let navigation = try XCTUnwrap(navigationController(in: controller))
                XCTAssertTrue(
                    navigation.isNavigationBarHidden, "The custom editor controls must not gain an empty native bar")
                XCTAssertTrue(emitted.isEmpty, "Banner layout must not change the record")
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image
                {
                    _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }

                let snapshot = XCTAttachment(image: image)
                snapshot.name = "Editor-banner-\(isNote ? "Note" : "Card")-\(background?.rawValue ?? "none")"
                snapshot.lifetime = .keepAlways
                add(snapshot)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBannerBackgroundFillsProposedWidthWithoutLegacyAccentDecoration
    /// @brief      Verify that banner Background Fills Proposed Width Without Legacy Accent Decoration
    /// @details    Exercises `controller.sizeThatFits`, `mark.sizeThatFits`. Checks `XCTAssertEqual(size.width,
    ///             320)`; `XCTAssertLessThan(size.height, 100)`.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func testBannerBackgroundFillsProposedWidthWithoutLegacyAccentDecoration()
    {

        let background = ItemAppearance(background: .green)
        for scheme in [ColorScheme.light, .dark]
        {

            let controller = UIHostingController(
                rootView:
                HStack
                {
                    Text("Plan")
                }
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testBannerBackgroundIsIndependentAndBackwardCompatible
    /// @brief      Verify that banner Background Is Independent And Backward Compatible
    /// @details    Exercises `JSONSerialization.jsonObject`, `card.replacingLocation`. Checks `XCTAssertEqual(legacy,
    ///             ItemAppearance(accent: .teal, icon: .heart))`; `XCTAssertNil(legacy.background)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testBannerBackgroundIsIndependentAndBackwardCompatible() throws
    {

        let legacy = try JSONDecoder().decode(
            ItemAppearance.self, from: Data(#"{"accent":"teal","icon":"heart"}"#.utf8))
        XCTAssertEqual(legacy, ItemAppearance(accent: .teal, icon: .heart))
        XCTAssertNil(legacy.background)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(json["background"])
        for color in ItemAccent.allCases
        {

            let backgroundOnly = ItemAppearance(background: color)
            XCTAssertFalse(backgroundOnly.isEmpty)
            let card = KanbanCard(id: 41, word: "A plan", listTitle: "Ideas", appearance: backgroundOnly)
            XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card)), card)
            XCTAssertEqual(card.replacingLocation(id: 42, listTitle: "Next").appearance, backgroundOnly)
        }

        XCTAssertThrowsError(
            try JSONDecoder().decode(ItemAppearance.self, from: Data(#"{"background":"invalid"}"#.utf8)))
        var combined = ItemAppearance(accent: .blue, icon: .notes, background: .rose)
        combined.background = nil
        XCTAssertEqual(combined, ItemAppearance(accent: .blue, icon: .notes))
        combined = ItemAppearance()
        XCTAssertTrue(combined.isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardCardBackgroundIsOptionalAndIndependentOfItemAppearance
    /// @brief      Verify that board Card Background Is Optional And Independent Of Item Appearance
    /// @details    Exercises `BoardAppearance.decodeWeek`, `theme.resolved`. Checks
    ///             `XCTAssertNil(legacy.cardBackground)`; `XCTAssertEqual(try
    ///             BoardAppearance.decodeWeek(JSONEncoder().encode(theme)), theme)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testBoardCardBackgroundIsOptionalAndIndependentOfItemAppearance() throws
    {

        let legacy = try JSONDecoder().decode(
            BoardAppearance.self, from: Data(#"{"bannerBackground":"blue","listBackground":"green"}"#.utf8))
        XCTAssertNil(legacy.cardBackground)
        for tint in KanbanListTint.allCases
        {

            let theme = BoardAppearance(cardBackground: tint)
            XCTAssertEqual(try BoardAppearance.decodeWeek(JSONEncoder().encode(theme)), theme)
            let itemAppearance = ItemAppearance(icon: .home, background: .rose)
            XCTAssertEqual(theme.resolved(itemAppearance), itemAppearance)
        }

        XCTAssertThrowsError(try BoardAppearance.decodeWeek(Data(#"{"cardBackground":"invalid"}"#.utf8)))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardAppearanceInheritanceAndApplyingAllPreserveContent
    /// @brief      Verify that board Appearance Inheritance And Applying All Preserve Content
    /// @details    Exercises `theme.resolved`, `card.replacingLocation`, `BoardAppearance.inheritingLists`. Checks
    ///             `XCTAssertEqual(theme.resolved(nil).background, .blue)`;
    ///             `XCTAssertEqual(theme.resolved(nil).listBackground, .green)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testBoardAppearanceInheritanceAndApplyingAllPreserveContent() throws
    {

        let theme = BoardAppearance(bannerBackground: .blue, listBackground: .green)
        XCTAssertEqual(theme.resolved(nil).background, .blue)
        XCTAssertEqual(theme.resolved(nil).listBackground, .green)
        let override = ItemAppearance(icon: .home, background: .rose, listBackground: .neutral)
        XCTAssertEqual(theme.resolved(override), override)
        let partial = ItemAppearance(icon: .home, background: .purple)
        XCTAssertEqual(theme.resolved(partial).listBackground, .green)
        XCTAssertEqual(theme.resolved(partial).background, .purple)
        let card = KanbanCard(
            id: 7, word: "Retained plan", listTitle: "Plans",
            descriptionOverride: "Keep my writing")
        var list = KanbanList(
            id: 3, title: "Plans", cards: [card], archivedCards: [card.replacingLocation(id: 8, listTitle: "Plans")])
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testListBackgroundTintRoundTripsAndKeepsLegacyDefaults
    /// @brief      Verify that list Background Tint Round Trips And Keeps Legacy Defaults
    /// @details    Checks `XCTAssertNil(legacy.listBackground)`; `XCTAssertFalse(appearance.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListBackgroundTintRoundTripsAndKeepsLegacyDefaults() throws
    {

        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data(#"{"background":"blue"}"#.utf8))
        XCTAssertNil(legacy.listBackground)
        for tint in KanbanListTint.allCases where tint != .neutral
        {

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
        XCTAssertThrowsError(
            try JSONDecoder().decode(ItemAppearance.self, from: Data(#"{"listBackground":"invalid"}"#.utf8)))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEmptySubtitleAppearanceIsOptionalAndNeverHidesWriting
    /// @brief      Verify that empty Subtitle Appearance Is Optional And Never Hides Writing
    /// @details    Exercises `legacy.hidesSubtitle`, `appearance.hidesSubtitle`,
    ///             `restored.appearance?.hidesSubtitle`. Checks `XCTAssertNil(legacy.hideEmptySubtitle)`;
    ///             `XCTAssertFalse(legacy.hidesSubtitle(""))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testEmptySubtitleAppearanceIsOptionalAndNeverHidesWriting() throws
    {

        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.hideEmptySubtitle)
        XCTAssertFalse(legacy.hidesSubtitle(""))
        var appearance = ItemAppearance()
        appearance.hideEmptySubtitle = true
        XCTAssertFalse(appearance.isEmpty)
        XCTAssertTrue(appearance.hidesSubtitle(" \n "))
        XCTAssertFalse(appearance.hidesSubtitle("A useful subtitle"))
        var card = KanbanCard(id: 42, word: "Plan", listTitle: "Today", subtitleOverride: "", appearance: appearance)
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(restored.appearance, appearance)
        XCTAssertTrue(restored.appearance?.hidesSubtitle(restored.subtitle) == true)
        card.subtitleOverride = "A useful subtitle"
        XCTAssertFalse(card.appearance?.hidesSubtitle(card.subtitle) == true)
        appearance.hideEmptySubtitle = nil
        XCTAssertTrue(appearance.isEmpty)
        XCTAssertFalse(appearance.hidesSubtitle(""))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testOptionalAppearancePreservesLegacyJSONAndRejectsInvalidValues
    /// @brief      Verify that optional Appearance Preserves Legacy JSON And Rejects Invalid Values
    /// @details    Exercises `JSONSerialization.jsonObject`. Checks `XCTAssertNil(card.appearance)`;
    ///             `XCTAssertNil(list.appearance)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testOptionalAppearancePreservesLegacyJSONAndRejectsInvalidValues() throws
    {

        let card = try JSONDecoder().decode(
            KanbanCard.self, from: Data(#"{"id":1,"word":"Plan","listTitle":"Monday","checklists":[]}"#.utf8))
        let list = try JSONDecoder().decode(KanbanList.self, from: Data(#"{"id":0,"title":"Monday","cards":[]}"#.utf8))
        XCTAssertNil(card.appearance)
        XCTAssertNil(list.appearance)
        for data in [try JSONEncoder().encode(card), try JSONEncoder().encode(list)]
        {

            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(json["appearance"])
        }

        let empty = KanbanCard(id: 2, word: "Plan", listTitle: "Monday", appearance: ItemAppearance())
        XCTAssertNil(empty.appearance)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                KanbanCard.self,
                from: Data(#"{"id":1,"word":"Plan","listTitle":"Monday","appearance":{"accent":"invalid"}}"#.utf8)))
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                KanbanList.self,
                from: Data(#"{"id":0,"title":"Monday","cards":[],"appearance":{"icon":"invalid"}}"#.utf8)))
        for accent in ItemAccent.allCases
        {

            let value = ItemAppearance(accent: accent, icon: nil)
            XCTAssertEqual(try JSONDecoder().decode(ItemAppearance.self, from: JSONEncoder().encode(value)), value)
        }

        for icon in PersonalCollectionIcon.allCases
        {

            let value = ItemAppearance(accent: nil, icon: icon)
            XCTAssertEqual(try JSONDecoder().decode(ItemAppearance.self, from: JSONEncoder().encode(value)), value)
        }

    }

}
