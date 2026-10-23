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
import UserNotifications
import SwiftUI
import AVFoundation
import PencilKit
@testable import Plenact


///
/// Verifies the Plenact-specific Board snapshot contract
///
/// @section    Purpose
///     Protect document validation, retained local content, and presentation-only behavior
///
final class PlenactBoardDocumentTests: XCTestCase {


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
    func testUntimedBundledExamplesPopulateEveryFocusFilterCombinationLateInTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let date = try XCTUnwrap(PlanningDate.date("2026-11-01", calendar: calendar))
        let late = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 45, second: 0, of: date))
        let templates = PlanningRoutineLibrary.seeded.templates.filter { $0.id != PlanningRoutineLibrary.jmrID }
        for template in templates {
            var original = DatedPlanningWeek.make(for: date, calendar: calendar)
            original.collection.lists[0].archivedCards = [KanbanCard(id: 500, word: "Retained", listTitle: "Archive", checklists: [])]
            let before = original
            let result = try PlanningTemplateApplication.apply(template, to: original, date: date, calendar: calendar, mode: .add)
            let id = try XCTUnwrap(result.dayListIDs[PlanningDate.key(date, calendar: calendar)])
            let list = try XCTUnwrap(result.collection.lists.first { $0.id == id })
            let important = PlanningTemplateApplication.exampleImportantIDs(template, in: original)
            XCTAssertTrue(important.allSatisfy { $0 > 500 })
            for mask in 0..<8 {
                let preferences = LocalProfilePreferences(todayFocusIncludesImportant: mask & 1 != 0,
                    todayFocusIncludesBookmarked: mask & 2 != 0, todayFocusIncludesUpNext: mask & 4 != 0)
                let entries = preferences.todayFocusEntries(in: list.cards, on: late, calendar: calendar,
                    importantCardIDs: important, bookmarkedCardIDs: result.collection.savedCardIDs)
                XCTAssertFalse(entries.isEmpty, "\(template.name), filter mask \(mask) must demonstrate Focus even late in the day")
                XCTAssertTrue(entries.allSatisfy { !$0.card.isSectionDivider && !$0.card.isTitleChecked })
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
    func testLegacyBundledFocusMetadataUpgradeDoesNotRewriteStoredPlansOrCustomTemplates() throws {
        let suite = "ExampleFocusMigration." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var library = PlanningRoutineLibrary.seeded
        for index in library.templates.indices { library.templates[index].exampleFocus = nil }
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
        XCTAssertTrue(upgraded.templates.dropFirst().allSatisfy { $0.exampleFocus != nil })
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
    func testCustomTemplateDoesNotInventFocusMarksOrDates() throws {
        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-09", calendar: calendar))
        var source = DatedPlanningWeek.make(for: date, calendar: calendar)
        let id = try XCTUnwrap(source.dayListIDs[PlanningDate.key(date, calendar: calendar)])
        let index = try XCTUnwrap(source.collection.lists.firstIndex { $0.id == id })
        source.collection.lists[index].cards = [KanbanCard(id: 10, word: "My unscheduled task", listTitle: "Monday", checklists: [])]
        let custom = try PlanningRoutineTemplate.capture(name: "My day", week: source, day: date, calendar: calendar)
        XCTAssertNil(custom.exampleFocus)
        let blank = DatedPlanningWeek.make(for: date, calendar: calendar)
        let result = try PlanningTemplateApplication.apply(custom, to: blank, date: date, calendar: calendar, mode: .add)
        XCTAssertTrue(PlanningTemplateApplication.exampleImportantIDs(custom, in: blank).isEmpty)
        XCTAssertTrue(result.collection.savedCardIDs.isEmpty)
        let card = try XCTUnwrap(result.collection.lists.first { $0.id == id }?.cards.first)
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
    func testMonthExampleRetainsFocusChoicesAndProvidesMatchingTodayItems() throws {
        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-21", calendar: calendar))
        let late = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 45, second: 0, of: date))
        let example = FullMonthExample.make(now: late, calendar: calendar)
        let selected = LocalProfilePreferences(todayFocusItemCount: 6, todayFocusIncludesImportant: true, todayFocusIncludesBookmarked: true, todayFocusIncludesUpNext: true, enablesLowerCornerBack: true)
        let domain = try example.defaultsDomain(preserving: [PlanPreferencesStore.key: JSONEncoder().encode(selected)])
        let preserved = try JSONDecoder().decode(LocalProfilePreferences.self, from: XCTUnwrap(domain[PlanPreferencesStore.key] as? Data))
        XCTAssertTrue(preserved.todayFocusIncludesImportant)
        XCTAssertTrue(preserved.todayFocusIncludesBookmarked)
        XCTAssertTrue(preserved.todayFocusIncludesUpNext)
        XCTAssertEqual(preserved.todayFocusItemCount, 6)
        XCTAssertTrue(preserved.enablesLowerCornerBack)
        let legacyProfile = LocalProfile(displayName: "Synthetic", preferences: selected)
        let legacyDomain = try example.defaultsDomain(preserving: [LocalProfileStore.storageKey: JSONEncoder().encode(legacyProfile)])
        let legacyPreferences = try JSONDecoder().decode(LocalProfilePreferences.self, from: XCTUnwrap(legacyDomain[PlanPreferencesStore.key] as? Data))
        XCTAssertTrue(legacyPreferences.enablesLowerCornerBack)
        var disabled = selected
        disabled.enablesLowerCornerBack = false
        let disabledDomain = try example.defaultsDomain(preserving: [PlanPreferencesStore.key: JSONEncoder().encode(disabled)])
        let disabledPreferences = try JSONDecoder().decode(LocalProfilePreferences.self, from: XCTUnwrap(disabledDomain[PlanPreferencesStore.key] as? Data))
        XCTAssertFalse(disabledPreferences.enablesLowerCornerBack)
        let week = try XCTUnwrap(example.document.week(for: date))
        let listID = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date, calendar: calendar)])
        let cards = try XCTUnwrap(week.collection.lists.first { $0.id == listID }).cards
        let importantData = try XCTUnwrap(domain[LibraryImportanceSelection.key] as? Data)
        let important = LibraryImportanceSelection.cardIDs(collectionID: week.id, data: importantData)
        let bookmarks = Set(try XCTUnwrap(domain["Plenact.SavedCardIDs.v1"] as? [Int]))
        for mask in 1..<8 {
            let preferences = LocalProfilePreferences(todayFocusIncludesImportant: mask & 1 != 0,
                todayFocusIncludesBookmarked: mask & 2 != 0, todayFocusIncludesUpNext: mask & 4 != 0)
            XCTAssertFalse(preferences.todayFocusEntries(in: cards, on: late, calendar: calendar,
                importantCardIDs: important, bookmarkedCardIDs: bookmarks).isEmpty, "Month filter mask \(mask)")
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
    func testExampleWeekUndoRetainsCalendarAndFocusFlagsWithLegacyCompatibility() throws {
        let suite = "ExampleWeekFocusUndo." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-09", calendar: calendar))
        let week = DatedPlanningWeek.make(for: date, calendar: calendar)
        XCTAssertTrue(ExampleLoadUndoStore.save(lists: week.collection.lists, todayListID: 0, week: week,
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
    func testSectionTransferKeepsWholeBlockLinksBookmarksAndUndo() throws {


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
        func card(_ id: Int, _ title: String) -> KanbanCard { KanbanCard(id: id, word: title, listTitle: "Source", checklists: []) }
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
        watcher.checklists = [KanbanChecklist(title: "Outer", items: [KanbanChecklistItem(title: "Detail", content: .actionDetail(
            KanbanChecklistActionDetail(description: "Context", checklists: [KanbanChecklist(title: "Inner", items: [nested])])) )])]
        var hiddenDetail = KanbanChecklistItem(title: "Inactive detail")
        hiddenDetail.retainedDetail = KanbanChecklistActionDetail(description: "Hidden context", checklists: [KanbanChecklist(title: "Retained", items: [nested])])
        watcher.checklists.append(KanbanChecklist(title: "Inactive", items: [hiddenDetail]))
        source.lists = [KanbanList(id: 10, title: "Source", cards: [card(0, "Ungrouped"), heading, member, card(3, "---"), card(4, "Walk"), card(5, "--- Evening"), card(6, "Dinner")])]
        source.savedCardIDs = [2, 6]
        target.lists = [KanbanList(id: 20, title: "Target", cards: [card(2, "Existing")], archivedCards: [card(4, "Archived")])]
        observer.lists = [KanbanList(id: 30, title: "Links", cards: [], archivedCards: [watcher])]
        var owners = [source, target, observer]
        let original = owners
        let receipt = try SectionTransfer.move(heading: heading,
            source: WorkspaceListReference(ownerID: source.id, listID: 10), destination: WorkspaceListReference(ownerID: target.id, listID: 20), owners: &owners)
        XCTAssertEqual(owners[0].lists[0].cards.map(\.id), [0, 5, 6])
        XCTAssertEqual(owners[1].lists[0].cards.map(\.word), ["Existing", "--- Morning", "Breakfast", "---", "Walk"])
        let relocated = try XCTUnwrap(owners[1].lists[0].cards.first { $0.word == "Breakfast" })
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
        guard case .actionDetail(let detail) = owners[2].lists[0].archivedCards[0].checklists[0].items[0].content else { return XCTFail("Missing detail") }
        XCTAssertEqual(detail.checklists[0].items[0].content, .linkedCard(cardID: relocated.id))
        XCTAssertEqual(detail.checklists[0].items[0].linkedCollectionID, target.id)
        let retained = try XCTUnwrap(owners[2].lists[0].archivedCards[0].checklists[1].items[0].retainedDetail)
        XCTAssertEqual(retained.checklists[0].items[0].content, .linkedCard(cardID: relocated.id))
        var plan = DailyPlan(date: .now, calendar: .current)
        plan.priorities = [DailyPlanPriority(PlanningSearchResult(weekKey: nil, collectionID: source.id, collectionTitle: source.title,
            listID: 10, listTitle: "Source", card: member))]
        var plans = DailyPlanStore.Document(); plans.plans[plan.id] = plan
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
    func testSectionTransferShiftsDatesAcrossDSTAndRejectsInvalidMovesAtomically() throws {
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
        var timed = dated.replacingLocation(id: 3, listTitle: "Saturday"); timed.startDateKind = .time; timed.dueDateKind = .time
        owner.lists = [KanbanList(id: 10, title: "Saturday", cards: [heading, dated, timed]), KanbanList(id: 11, title: "Monday", cards: [])]
        var owners = [owner]
        let source = WorkspaceListReference(ownerID: owner.id, listID: 10)
        let target = WorkspaceListReference(ownerID: owner.id, listID: 11)
        let original = owners
        let receipt = try SectionTransfer.move(heading: heading, source: source, destination: target, owners: &owners,
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
        XCTAssertThrowsError(try SectionTransfer.move(heading: heading, source: source, destination: source, owners: &owners))
        XCTAssertEqual(owners, original)
        let missing = WorkspaceListReference(ownerID: UUID(), listID: 11)
        XCTAssertThrowsError(try SectionTransfer.move(heading: heading, source: source, destination: missing, owners: &owners))
        XCTAssertEqual(owners, original)
        _ = try SectionTransfer.move(heading: heading, source: source, destination: target, owners: &owners, sourceDay: fromDay, destinationDay: toDay, shiftDates: false, calendar: calendar)
        XCTAssertEqual(owners[0].lists[1].cards[1].startDate, dated.startDate)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSectionMoveJournalRestoresImportanceAndSupportsLegacyRecovery
    /// @brief      Verify that section Move Journal Restores Importance And Supports Legacy Recovery
    /// @details    Exercises `DailyReviewTransaction.perform`, `PropertyListSerialization.data`,
    ///             `DailyReviewTransaction.recover`. Checks `XCTAssertEqual(defaults.data(forKey:
    ///             LibraryImportanceSelection.key), before)`; `XCTAssertEqual(defaults.data(forKey:
    ///             "Plenact.Board.v1"), Data("board".utf8))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    @MainActor
    func testSectionMoveJournalRestoresImportanceAndSupportsLegacyRecovery() throws {
        let suite = "SectionMoveJournal." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let before = Data("before".utf8)
        defaults.set(before, forKey: LibraryImportanceSelection.key)
        defaults.set(Data("board".utf8), forKey: "Plenact.Board.v1")
        XCTAssertThrowsError(try DailyReviewTransaction.perform(in: defaults, additionalKeys: [LibraryImportanceSelection.key]) {
            defaults.set(Data("after".utf8), forKey: LibraryImportanceSelection.key)
            defaults.set(Data("changed".utf8), forKey: "Plenact.Board.v1")
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertEqual(defaults.data(forKey: LibraryImportanceSelection.key), before)
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), Data("board".utf8))
        XCTAssertNil(defaults.object(forKey: DailyReviewTransaction.key))
        // Old journals did not capture importance; recovering them must not remove it.
        let legacy = try PropertyListSerialization.data(fromPropertyList: ["version": 1, "previous": ["Plenact.Board.v1": Data("old".utf8)]], format: .binary, options: 0)
        defaults.set(legacy, forKey: DailyReviewTransaction.key)
        try DailyReviewTransaction.recover(in: defaults)
        XCTAssertEqual(defaults.data(forKey: LibraryImportanceSelection.key), before)
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), Data("old".utf8))
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
    func testSectionMoveChooserAndUndoNoticeRenderWithoutMovingAndOnlyNoticeReceivesTouches() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { TransferConfirmationPresenter.shared.dismiss(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let heading = KanbanCard(id: 1, word: "--- Morning", listTitle: "Monday", checklists: [])
        var moves = 0
        let movement = CardMovementAccess(destinations: [CardMoveDestination(collectionID: UUID(), listID: 2, title: "On the Table", group: "Plans")],
            moveSection: { _, _, _, _ in moves += 1; return true }, moveSectionToDate: { _, _, _, _ in moves += 1; return true })
        let host = UIHostingController(rootView: SectionMoveSheet(heading: heading).environment(\.cardMovementAccess, movement))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(moves, 0)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-section-move-chooser.png")
        try XCTUnwrap(image.pngData()).write(to: url); print("SECTION_MOVE_RENDER=" + url.path)
        var undoCalls = 0
        TransferConfirmationPresenter.shared.showUndo(TransferConfirmation(title: "Morning", destination: "Thursday")) { undoCalls += 1; return true }
        try await Task.sleep(for: .milliseconds(200))
        let notice = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "section.move.undo.overlay" })
        XCTAssertFalse(scene.windows.contains { !$0.isHidden && $0.windowLevel > .alert }, "Persistent Undo must not create another window")
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertNil(notice.hitTest(CGPoint(x: 10, y: 10), with: nil))
        let hits = stride(from: CGFloat(0), through: notice.bounds.height, by: 10).filter {
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
    func testDaySectionsKeepPlainDividersInsideTheirNamedSection() throws {


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
        func card(_ id: Int, _ title: String) -> KanbanCard {
            KanbanCard(id: id, word: title, listTitle: "Monday", checklists: [])
        }
        var heading = card(1, "--- Morning")
        heading.appearance = ItemAppearance(accent: .orange, sectionCollapsed: true)
        let cards = [card(0, "Ungrouped"), heading, card(2, "Breakfast"), card(3, "---"),
            card(4, "Walk"), card(5, "--- Evening"), card(6, "Dinner")]
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
        XCTAssertEqual(entries.first(where: { $0.id == 4 })?.heading, "Morning")
        XCTAssertTrue(entries.contains { $0.id == 2 }, "Collapsing Day content does not hide it from Focus")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testVisibleReorderingMapsPastCollapsedContentAndRevealsTheMovedCard
    /// @brief      Verify that visible Reordering Maps Past Collapsed Content And Reveals The Moved Card
    /// @details    Exercises `DaySections.visibleMove`, `DaySections.reordered`, `DaySections.reveal`. Checks
    ///             `XCTAssertEqual(move.id, 5)`; `XCTAssertEqual(move.index, 3)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testVisibleReorderingMapsPastCollapsedContentAndRevealsTheMovedCard() throws {


        ///
        /// @fcn        PlenactBoardDocumentTests.testVisibleReorderingMapsPastCollapsedContentAndRevealsTheMovedCard.card
        /// @brief      Prepare card for the enclosing regression test
        /// @details    Supplies the local fixture for visible Reordering Maps Past Collapsed Content And Reveals The
        ///             Moved Card.
        ///
        /// @param[in]  id     Starting numeric card ID or owner-local content identity
        /// @param[in]  title  Display title or proposed title text
        ///
        /// @return     (KanbanCard) result described by this operation's contract
        ///
        func card(_ id: Int, _ title: String) -> KanbanCard { KanbanCard(id: id, word: title, listTitle: "Day", checklists: []) }
        var heading = card(1, "--- Morning")
        heading.appearance = ItemAppearance(accent: .orange, sectionCollapsed: true)
        let cards = [card(0, "Before"), heading, card(2, "Hidden"), card(3, "--- Evening"), card(4, "Visible"), card(5, "Last")]
        let move = try XCTUnwrap(DaySections.visibleMove(cards, sourceOffsets: IndexSet(integer: 4), destinationOffset: 2))
        XCTAssertEqual(move.id, 5)
        XCTAssertEqual(move.index, 3)
        var result = DaySections.reordered(cards, itemID: move.id, to: move.index)
        DaySections.reveal(move.id, in: &result)
        XCTAssertEqual(result.map(\.id), [0, 1, 2, 5, 3, 4])
        XCTAssertEqual(DaySections.visible(result).map(\.id), result.map(\.id))
        XCTAssertEqual(Set(result.map(\.id)), Set(cards.map(\.id)))
        XCTAssertEqual(result.first { $0.id == 2 }, cards[2], "Hidden content remains intact")
        var lists = [KanbanList(id: 1, title: "Day", cards: cards)]
        XCTAssertTrue(try BoardCardMovement.move(5, to: 1, before: 3, in: &lists))
        XCTAssertEqual(lists[0].cards.map(\.id), [0, 1, 2, 5, 3, 4])
        XCTAssertEqual(lists[0].cards.first { $0.id == 1 }?.appearance?.sectionCollapsed, false)
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
    func testDaySectionMovementRetainsTheWholeBlockAndItsMetadata() throws {


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
        func card(_ id: Int, _ title: String) -> KanbanCard {
            KanbanCard(id: id, word: title, listTitle: "Monday", checklists: [])
        }
        var morning = card(1, "--- Morning")
        morning.appearance = ItemAppearance(accent: .orange, sectionCollapsed: true)
        let cards = [card(0, "Before sections"), morning, card(2, "Breakfast"), card(3, "---"),
            card(4, "Walk"), card(5, "--- Midday"), card(6, "Work"), card(7, "--- Night"), card(8, "Rest")]
        let moved = DaySections.moved(cards, sectionID: 1, offset: 1)
        XCTAssertEqual(moved.map(\.id), [0, 5, 6, 1, 2, 3, 4, 7, 8])
        XCTAssertEqual(DaySections.moved(moved, sectionID: 1, offset: -1), cards)
        XCTAssertEqual(DaySections.moved(cards, sectionID: 7, offset: -1).map(\.id), [0, 1, 2, 3, 4, 7, 8, 5, 6])
        XCTAssertEqual(DaySections.moved(cards, sectionID: 1, offset: -1), cards)
        XCTAssertEqual(DaySections.reordered(cards, itemID: 1, to: 8).map(\.id), [0, 5, 6, 7, 8, 1, 2, 3, 4])
        XCTAssertEqual(DaySections.reordered(cards, itemID: 7, to: 0).map(\.id), [0, 7, 8, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(DaySections.moved(cards, sectionID: 7, offset: 1), cards)
        XCTAssertEqual(DaySections.moved(cards, sectionID: 3, offset: 1), cards, "A plain line is not a section")
        for item in cards { XCTAssertEqual(moved.first { $0.id == item.id }, item) }
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
    func testSectionExampleUpgradePreservesExistingRoutinesAndStoredBytes() throws {
        let suite = "DaySectionExamples." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var library = PlanningRoutineLibrary.seeded
        library.templates.removeAll { template in PlanningRoutineLibrary.sectionExamples.contains { $0.id == template.id } }
        library.bundledRoutineRevision = 2
        library.templates[0].name = "My own week"
        let original = library.templates
        let bytes = try JSONEncoder().encode(library)
        defaults.set(bytes, forKey: PlanningRoutineStore.key)
        let upgraded = try PlanningRoutineStore.load(from: defaults)
        XCTAssertEqual(Array(upgraded.templates.prefix(original.count)), original)
        XCTAssertEqual(upgraded.defaultWeekID, library.defaultWeekID)
        XCTAssertEqual(upgraded.bundledRoutineRevision, 4)
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), bytes, "Loading examples does not write user data")
        try PlanningRoutineStore.validate(upgraded)
        for example in PlanningRoutineLibrary.sectionExamples {
            XCTAssertEqual(example.kind, .day)
            let cards = try XCTUnwrap(example.collection.lists.first).cards
            XCTAssertEqual(cards.filter { $0.sectionHeading != nil }.count, 3)
            XCTAssertTrue(cards.filter { $0.sectionHeading != nil }.allSatisfy { $0.appearance?.accent != nil })
            XCTAssertTrue(cards.allSatisfy { !$0.isTitleChecked })
            let day = try XCTUnwrap(PlanningDate.date("2026-11-09", calendar: example.calendar))
            let blank = DatedPlanningWeek.make(for: day, calendar: example.calendar)
            let applied = try PlanningTemplateApplication.apply(example, to: blank, date: day, calendar: example.calendar, mode: .add)
            let listID = try XCTUnwrap(applied.dayListIDs[PlanningDate.key(day, calendar: example.calendar)])
            let result = try XCTUnwrap(applied.collection.lists.first { $0.id == listID }).cards
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
    func testDaySectionRowsRenderWithLargeTextAndWithoutEditingOnAppearance() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let cards = try XCTUnwrap(PlanningRoutineLibrary.sectionExamples.first?.collection.lists.first).cards
        var writes = 0
        for scheme in [ColorScheme.light, .dark] {
            let host = UIHostingController(rootView: NavigationStack {
                List {
                    ForEach(DaySections.visible(cards)) { card in
                        if card.sectionHeading != nil {
                            DaySectionRow(card: card, cards: cards, onUpdate: { _ in writes += 1 }, onMove: { _ in writes += 1 })
                        } else {
                            Text(card.word).padding(12).modifier(DaySectionRail(cardID: card.id, cards: cards))
                        }
                    }
                }.navigationTitle("A day in chapters")
            }.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .accessibility1))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-day-sections-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("DAY_SECTION_RENDER=" + url.path)
        }
        XCTAssertEqual(writes, 0)
    }


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
    func testRandomCardColorPreferencesDefaultOffAndRoundTripWithoutProfile() throws {
        let old = try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(old.randomizesNewCardHeaders)
        XCTAssertFalse(old.randomizesNewCardBackgrounds)
        let appearance = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(appearance.cardBackground)
        XCTAssertTrue(appearance.isEmpty)
        let name = "RandomCardColorTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for headers in [false, true] {
            for backgrounds in [false, true] {
                let preferences = LocalProfilePreferences(randomizesNewCardHeaders: headers, randomizesNewCardBackgrounds: backgrounds)
                PlanPreferencesStore.save(preferences, to: defaults)
                XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
                XCTAssertNil(LocalProfileStore.load(from: defaults))
            }
        }
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
    func testRandomCardCreationColorsAreIndependentAndExcludeNotesAndDividers() throws {
        let list = KanbanList(id: 1, title: "Ideas", cards: [])
        for headers in [false, true] {
            for backgrounds in [false, true] {
                let preferences = LocalProfilePreferences(randomizesNewCardHeaders: headers, randomizesNewCardBackgrounds: backgrounds)
                let card = list.makeItem(id: 1, title: "New Card", presentationOverride: .card, creationPreferences: preferences)
                XCTAssertEqual(card.appearance?.background != nil, headers)
                XCTAssertEqual(card.appearance?.cardBackground != nil, backgrounds)
                if let header = card.appearance?.background { XCTAssertTrue(NewCardAppearanceDefaults.headerPalette.contains(header)) }
                if let background = card.appearance?.cardBackground { XCTAssertTrue(NewCardAppearanceDefaults.backgroundPalette.contains(background)) }
                var reopened = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
                XCTAssertEqual(reopened, card)
                NewCardAppearanceDefaults.apply(to: &reopened, preferences: preferences)
                XCTAssertEqual(reopened, card, "A saved color must never reroll")
                XCTAssertNil(list.makeItem(id: 2, title: "Note", presentationOverride: .note, creationPreferences: preferences).appearance)
                XCTAssertNil(list.makeItem(id: 3, title: "--- Section", creationPreferences: preferences).appearance)
            }
        }
        let enabled = LocalProfilePreferences(randomizesNewCardHeaders: true, randomizesNewCardBackgrounds: true)
        let batch = list.makeItems(startingAt: 10, titles: "First\nSecond\nThird", creationPreferences: enabled)
        XCTAssertEqual(batch.count, 3)
        XCTAssertTrue(batch.allSatisfy { $0.appearance?.background != nil && $0.appearance?.cardBackground != nil })
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
    /// @fcn        PlenactBoardDocumentTests.testRandomCardColorPreviewsRenderInLightAndDarkWithoutChangingRecords
    /// @brief      Verify that random Card Color Previews Render In Light And Dark Without Changing Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(cards, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testRandomCardColorPreviewsRenderInLightAndDarkWithoutChangingRecords() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let list = KanbanList(id: 1, title: "Color examples", cards: [])
        let cards = [
            list.makeItem(id: 1, title: "Random header only", creationPreferences: LocalProfilePreferences(randomizesNewCardHeaders: true)),
            list.makeItem(id: 2, title: "Random background only", creationPreferences: LocalProfilePreferences(randomizesNewCardBackgrounds: true)),
            list.makeItem(id: 3, title: "Both colors", creationPreferences: LocalProfilePreferences(randomizesNewCardHeaders: true, randomizesNewCardBackgrounds: true))
        ]
        let original = cards
        for scheme in [ColorScheme.light, .dark] {
            let view = VStack(spacing: 12) {
                ForEach(cards) { card in
                    KanbanCardView(card: card, height: 140, displaySettings: BoardDisplaySettings(), labelLibrary: .starter,
                        onUpdateCard: { _ in XCTFail("Rendering must not edit") }, onDeleteCard: {}, onArchiveCard: {}, onToggle: {})
                }
                BoardGalleryTile(card: cards[2])
            }.padding().background(Color(.systemGroupedBackground)).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-random-card-colors-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("RANDOM_CARD_COLORS_RENDER=" + url.path)
            XCTAssertEqual(cards, original)
        }
        let settings = UIHostingController(rootView: PlanSettingsView(lists: [list], onSaveProfile: { _ in XCTFail("Rendering must not save") }))
        window.rootViewController = settings
        try await Task.sleep(for: .milliseconds(200))
        let image = UIGraphicsImageRenderer(bounds: settings.view.bounds).image { _ in settings.view.drawHierarchy(in: settings.view.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-random-card-color-settings.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("RANDOM_CARD_COLORS_RENDER=" + url.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanPreferencesSaveWithoutCreatingProfileAndShareProfileEdits
    /// @brief      Verify that plan Preferences Save Without Creating Profile And Share Profile Edits
    /// @details    Exercises `PlanPreferencesStore.load`, `PlanPreferencesStore.save`, `LocalProfileStore.load`.
    ///             Checks `XCTAssertEqual(PlanPreferencesStore.load(from: defaults).todayFocusItemCount, 4)`;
    ///             `XCTAssertNil(LocalProfileStore.load(from: defaults))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanPreferencesSaveWithoutCreatingProfileAndShareProfileEdits() throws {
        let suite = "PlanSettingsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults).todayFocusItemCount, 4)
        var preferences = LocalProfilePreferences()
        preferences.todayFocusItemCount = 8
        preferences.showsDueDatesOnNewCards = false
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
        XCTAssertFalse(KanbanCard.defaultDueDateVisibility(from: defaults))
        preferences.todayFocusItemCount = 2
        let profile = LocalProfile(displayName: "Test", preferences: preferences)
        LocalProfileStore.save(profile, to: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
        LocalProfileStore.remove(from: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListBackgroundOpacityDefaultsClampsAndPersistsIndependently
    /// @brief      Verify that list Background Opacity Defaults Clamps And Persists Independently
    /// @details    Exercises `BoardAppearance().resolved`. Checks
    ///             `XCTAssertEqual(legacy.resolvedListBackgroundOpacity, 1)`; `XCTAssertFalse(appearance.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListBackgroundOpacityDefaultsClampsAndPersistsIndependently() throws {
        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.resolvedListBackgroundOpacity, 1)
        for value in [0.0, 0.5, 1.0] {
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
    /// @fcn        PlenactBoardDocumentTests.testNoteListDayLayoutRendersAtPhoneAndTabletWidths
    /// @brief      Verify that note List Day Layout Renders At Phone And Tablet Widths
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertGreaterThan(host.view.bounds.height, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testNoteListDayLayoutRendersAtPhoneAndTabletWidths() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        var list = KanbanList(id: 8, title: "Wednesday", cards: [
            KanbanCard(id: 1, word: "Plan the next useful step", listTitle: "Wednesday", checklists: [], descriptionOverride: "Make room for a focused morning"),
            KanbanCard(id: 2, word: "Capture a thought", listTitle: "Wednesday", checklists: [], descriptionOverride: "Writing stays in its original Note", presentation: .note),
            KanbanCard(id: 3, word: "A completed task", listTitle: "Wednesday", isTitleChecked: true, checklists: [])
        ])
        list.setSingleListViewMode(.noteList)
        for width: CGFloat in [393, 820] {
            let view = TodayListDetailView(lists: .constant([list]), reservedLists: [], labelLibrary: .constant(.starter),
                savedCardIDs: .constant([]), listID: list.id, currentUserName: "Test", onClose: {}, onOpenWeek: {},
                onPermanentDelete: { _ in false }, representedDate: Date(timeIntervalSince1970: 1791936000))
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: width, height: width < 500 ? 852 : 1180)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-note-list-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("NOTE_LIST_RENDER=" + url.path)
            XCTAssertGreaterThan(host.view.bounds.height, 0)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSingleListViewModePersistsWithoutConvertingOrReorderingContent
    /// @brief      Verify that single List View Mode Persists Without Converting Or Reordering Content
    /// @details    Exercises `list.setSingleListViewMode`, `anotherDay.setSingleListViewMode`. Checks
    ///             `XCTAssertEqual(list.singleListViewMode, .cards)`; `XCTAssertEqual(restored.singleListViewMode,
    ///             .noteList)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testSingleListViewModePersistsWithoutConvertingOrReorderingContent() throws {
        var list = KanbanList(id: 4, title: "Wednesday", cards: [
            KanbanCard(id: 1, word: "Task", listTitle: "Wednesday", isTitleChecked: true,
                checklists: [KanbanChecklist(title: "Steps", items: [KanbanChecklistItem(title: "Done", isCompleted: true)])]),
            KanbanCard(id: 2, word: "A note", listTitle: "Wednesday", checklists: [],
                descriptionOverride: "Keep this writing", presentation: .note)
        ])
        list.appearance = ItemAppearance(icon: .tasks)
        let original = list
        XCTAssertEqual(list.singleListViewMode, .cards)
        list.setSingleListViewMode(.noteList)
        let restored = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(restored.singleListViewMode, .noteList)
        XCTAssertEqual(restored.cards, original.cards)
        XCTAssertEqual(restored.archivedCards, original.archivedCards)
        XCTAssertEqual(restored.appearance?.icon, original.appearance?.icon)
        list.setSingleListViewMode(.cards)
        XCTAssertEqual(list.cards, original.cards)
        XCTAssertEqual(list.singleListViewMode, .cards)
        XCTAssertFalse(ItemAppearance(listViewMode: .noteList).isEmpty)
        XCTAssertNil(try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8)).listViewMode)
        var anotherDay = KanbanList(id: 5, title: "Thursday", cards: [])
        XCTAssertEqual(anotherDay.singleListViewMode, .cards)
        anotherDay.setSingleListViewMode(.noteList)
        XCTAssertEqual(anotherDay.singleListViewMode, .noteList)
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
    func testListIconColorsPersistAndMainListColorsRemainFixed() throws {
        var list = KanbanList(id: 1, title: "Custom", cards: [])
        list.appearance = ItemAppearance(iconColor: .blue, showsIconInHeader: true)
        let restored = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(restored.resolvedIconColor(collectionColor: .orange), .blue)
        XCTAssertEqual(restored.headerAppearance()?.iconColor, .blue)
        XCTAssertNil(restored.appearance?.background)
        XCTAssertFalse(ItemAppearance(iconColor: .blue).isEmpty)
        list.appearance?.iconColor = nil
        XCTAssertEqual(list.resolvedIconColor(collectionColor: .orange), .orange)
        XCTAssertNotEqual(KanbanList.fixedHeaderIconColor(for: "On the Table"), KanbanList.fixedIconColor(for: "On the Table"))
        for title in ["On the Table", "In the Queue", "Scheduled"] {
            var main = DefaultListTutorial.makeStarter(title: title).lists[0]
            main.appearance?.iconColor = .blue
            XCTAssertEqual(main.resolvedIconColor(collectionColor: .green), KanbanList.fixedIconColor(for: title))
            XCTAssertEqual(main.headerAppearance()?.iconColor, KanbanList.fixedHeaderIconColor(for: title))
        }
    }


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
    func testMainLibraryListsUseTheSameFocusedDestinationAsToday() {
        for title in ["On the Table", "In the Queue", "Scheduled"] {
            let collection = DefaultListTutorial.makeStarter(title: title)
            XCTAssertEqual(collection.preferredFocusedListID, collection.lists[0].id)
            XCTAssertEqual(WorkspaceListReference(ownerID: collection.id, listID: collection.preferredFocusedListID!).listID, collection.lists[0].id)
        }
        XCTAssertNil(PersonalCollection(title: "Custom", kind: .list).preferredFocusedListID)
        XCTAssertNil(PersonalCollection(title: "On the Table", kind: .board).preferredFocusedListID)
        var archived = DefaultListTutorial.makeStarter(title: "On the Table")
        archived.lists[0].isArchived = true
        XCTAssertNil(archived.preferredFocusedListID)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListHeaderIconDefaultsAndExplicitChoicesPersist
    /// @brief      Verify that list Header Icon Defaults And Explicit Choices Persist
    /// @details    Exercises `custom.headerAppearance`, `legacy.headerAppearance`, `restored.headerAppearance`.
    ///             Checks `XCTAssertFalse(custom.showsIconInHeader)`; `XCTAssertNil(custom.headerAppearance())`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListHeaderIconDefaultsAndExplicitChoicesPersist() throws {
        var custom = KanbanList(id: 7, title: "Custom list", cards: [])
        custom.appearance = ItemAppearance(icon: .tasks)
        XCTAssertFalse(custom.showsIconInHeader)
        XCTAssertNil(custom.headerAppearance())
        custom.appearance?.showsIconInHeader = true
        XCTAssertEqual(custom.headerAppearance()?.icon, .tasks)
        custom.appearance?.showsIconInHeader = false
        let roundTrip = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(custom))
        XCTAssertFalse(roundTrip.showsIconInHeader)
        let explicitOff = ItemAppearance(showsIconInHeader: false)
        XCTAssertFalse(explicitOff.isEmpty)
        for title in ["On the Table", "In the Queue", "Scheduled"] {
            var legacy = KanbanList(id: 1, title: title, cards: [])
            XCTAssertTrue(legacy.showsIconInHeader)
            XCTAssertNotNil(legacy.headerAppearance()?.icon)
            legacy.appearance = explicitOff
            let restored = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(legacy))
            XCTAssertTrue(restored.hasFixedHeaderIcon)
            XCTAssertTrue(restored.showsIconInHeader)
            XCTAssertNotNil(restored.headerAppearance())
            XCTAssertTrue(DefaultListTutorial.makeStarter(title: title).lists[0].showsIconInHeader)
        }
        custom.appearance = ItemAppearance(showsIconInHeader: true)
        XCTAssertEqual(custom.headerAppearance(collectionIcon: .upcoming)?.icon, .upcoming)
        XCTAssertEqual(custom.headerAppearance()?.icon, .notes)
        custom.appearance?.showsIconInHeader = false
        XCTAssertNil(custom.headerAppearance(collectionIcon: .upcoming))
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
    func testListCheckmarkResetRestoresExactNestedFlagsWithoutReplacingContent() throws {
        let nested = KanbanChecklist(title: "Nested", items: [KanbanChecklistItem(title: "Nested done", isCompleted: true)])
        let detail = KanbanChecklistActionDetail(description: "Keep details", checklists: [nested])
        let checklist = KanbanChecklist(title: "Steps", items: [
            KanbanChecklistItem(title: "Done", isCompleted: true, content: .actionDetail(detail)),
            KanbanChecklistItem(title: "Still open")
        ])
        var list = KanbanList(id: 1, title: "Sunday", cards: [
            KanbanCard(id: 1, word: "Done card", listTitle: "Sunday", isTitleChecked: true, checklists: [checklist]),
            KanbanCard(id: 2, word: "Open card", listTitle: "Sunday", checklists: [])
        ])
        list.archivedCards = [KanbanCard(id: 99, word: "Archived", listTitle: "Sunday", isTitleChecked: true, checklists: [])]
        let original = list
        let (snapshot, cards) = ListCheckmarkReset.reset(list)
        list.cards = cards
        XCTAssertFalse(ListCheckmarkReset.values(in: list).values.contains(true))
        XCTAssertEqual(list.archivedCards, original.archivedCards)
        XCTAssertTrue(snapshot.canRestore(list))
        XCTAssertEqual(snapshot.restoring(list), original.cards)
        list.cards[0].word = "Edited title survives restore"
        let restored = try XCTUnwrap(snapshot.restoring(list))
        XCTAssertEqual(restored[0].word, "Edited title survives restore")
        XCTAssertTrue(restored[0].isTitleChecked)
        list.cards[1].isTitleChecked = true
        XCTAssertFalse(snapshot.canRestore(list))
        XCTAssertNil(snapshot.restoring(list))
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
    func testTodayFocusPreferenceDefaultsAndPersistsWithoutChangingOlderSettings() throws {
        let legacy = Data(#"{"defaultListID":3,"usesReducedContent":true,"showsDueDatesOnNewCards":false}"#.utf8)
        let restored = try JSONDecoder().decode(LocalProfilePreferences.self, from: legacy)
        XCTAssertEqual(restored.todayFocusItemCount, 4)
        XCTAssertEqual(restored.defaultListID, 3)
        XCTAssertTrue(restored.usesReducedContent)
        XCTAssertFalse(restored.showsDueDatesOnNewCards)
        for count in 0...12 {
            var preferences = restored
            preferences.todayFocusItemCount = count
            let decoded = try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONEncoder().encode(preferences))
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
    func testFocusFiltersCombineAsUnionAndKeepAllMatchesInCanonicalOrder() throws {
        var cards = (0..<7).map { KanbanCard(id: $0, word: "Item \($0)", listTitle: "Today", checklists: []) }
        cards[2].isTitleChecked = true
        cards.insert(KanbanCard(id: 90, word: "--- Important to me", listTitle: "Today", isDivider: true, checklists: []), at: 1)
        let original = cards
        let important: Set<Int> = [1, 2, 4, 90]
        let saved: Set<Int> = [3, 4]
        var preferences = LocalProfilePreferences(todayFocusItemCount: 0, todayFocusGroupsBySection: true,
            todayFocusIncludesImportant: true)


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusFiltersCombineAsUnionAndKeepAllMatchesInCanonicalOrder.entries
        /// @brief      Prepare entries for the enclosing regression test
        /// @details    Supplies the local fixture for focus Filters Combine As Union And Keep All Matches In
        ///             Canonical Order. Uses `preferences.todayFocusEntries`.
        ///
        /// @return     ([TodayFocusEntry]) resulting values in the ordering described above
        ///
        func entries() -> [TodayFocusEntry] {
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
    func testFocusUpNextSkipsEndedSlotsAndKeepsCurrentUpcomingAndExplicitChoices() throws {
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
        func time(_ hour: Int, day: Int = 19) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        var cards = (0..<8).map { KanbanCard(id: $0, word: "Item \($0)", listTitle: "Today", checklists: []) }
        cards[0].startDate = time(4); cards[0].dueDate = time(5)
        cards[1].startDate = time(7); cards[1].dueDate = time(17)
        cards[2].startDate = time(18); cards[2].dueDate = time(19)
        cards[3].startDate = time(9, day: 1); cards[3].dueDate = time(10, day: 1)
        cards[4].startDate = time(15, day: 1); cards[4].startDateKind = .time
        cards[5].dueDate = time(0); cards[5].dueDateKind = .date
        cards[6].startDate = time(8, day: 20)
        for index in [0, 1, 2, 3, 6] { cards[index].startDateKind = .dateAndTime; cards[index].dueDateKind = .dateAndTime }
        var preferences = LocalProfilePreferences(todayFocusItemCount: 0, todayFocusIncludesUpNext: true)
        let now = time(12)
        XCTAssertEqual(preferences.todayFocusEntries(in: cards, on: now, calendar: calendar).map(\.id), [1, 2, 4, 5])
        preferences.todayFocusIncludesImportant = true
        preferences.todayFocusIncludesBookmarked = true
        XCTAssertEqual(preferences.todayFocusEntries(in: cards, on: now, calendar: calendar,
            importantCardIDs: [0], bookmarkedCardIDs: [7]).map(\.id), [0, 1, 2, 4, 5, 7])
        preferences.todayFocusIncludesImportant = false; preferences.todayFocusIncludesBookmarked = false
        XCTAssertEqual(preferences.todayFocusEntries(in: cards, on: time(20), calendar: calendar).map(\.id), [5])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testImportanceLevelsRequireSeparateGesturesAndRetainLegacyMarks
    /// @brief      Verify one-step importance, legacy migration, and owner isolation
    /// @details    Exercises every increase and decrease, clamping, unrelated edits, and legacy
    ///             presence-only decoding without losing higher-level selections.
    ///
    /// @return     (Void) records bounded-step and persistence assertions
    /// @throws     Propagates fixture encoding failures.
    ///
    func testImportanceLevelsRequireSeparateGesturesAndRetainLegacyMarks() throws {
        let owner = UUID(), other = UUID()
        var data = try JSONEncoder().encode([LibraryRecentItem(collectionID: other, cardID: 7)])
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: other, data: data), 1)
        for expected in 1...5 {
            data = LibraryImportanceSelection.adjusting(cardID: 7, collectionID: owner, direction: 99, data: data)
            XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: data), expected)
        }
        data = LibraryImportanceSelection.adjusting(cardID: 7, collectionID: owner, direction: 1, data: data)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: data), 5)
        data = LibraryImportanceSelection.setting(cardID: 7, collectionID: owner, marked: true, data: data)
        data = LibraryImportanceSelection.setting(cardID: 8, collectionID: other, marked: true, data: data)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: data), 5)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: other, data: data), 1)
        XCTAssertEqual(try JSONDecoder().decode([LibraryImportanceItem].self, from: data).first { $0.collectionID == owner }?.resolvedLevel, 5)
        for expected in (0...4).reversed() {
            data = LibraryImportanceSelection.adjusting(cardID: 7, collectionID: owner, direction: -99, data: data)
            XCTAssertEqual(LibraryImportanceSelection.level(cardID: 7, collectionID: owner, data: data), expected)
            XCTAssertEqual(LibraryImportanceSelection.contains(cardID: 7, collectionID: owner, data: data), expected > 0)
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
    func testImportanceStarStyleDefaultsTuckedAndPersistsWithoutChangingLevels() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(LocalProfilePreferences())) as? [String: Any])
        object.removeValue(forKey: "importanceStarStyle")
        XCTAssertEqual(try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONSerialization.data(withJSONObject: object)).importanceStarStyle, .tucked)
        let suite = "ImportanceStyle." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for style in ImportanceStarStyle.allCases {
            let preferences = LocalProfilePreferences(importanceStarStyle: style)
            PlanPreferencesStore.save(preferences, to: defaults)
            XCTAssertEqual(PlanPreferencesStore.load(from: defaults).importanceStarStyle, style)
            XCTAssertEqual(try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONEncoder().encode(preferences)), preferences)
        }
        let fanned = try JSONEncoder().encode(LocalProfilePreferences(importanceStarStyle: .fanned))
        let domain = try FullMonthExample.make().defaultsDomain(preserving: [PlanPreferencesStore.key: fanned])
        let retained = try XCTUnwrap(domain[PlanPreferencesStore.key] as? Data)
        XCTAssertEqual(try JSONDecoder().decode(LocalProfilePreferences.self, from: retained).importanceStarStyle, .fanned)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleUndoRetainsExactImportanceLevelsAndLegacySnapshots
    /// @brief      Verify example undo snapshots retain layered importance
    /// @details    Saves mixed levels and verifies old snapshots without levels remain readable.
    ///
    /// @return     (Void) records undo persistence assertions
    /// @throws     Propagates temporary defaults or JSON failures.
    ///
    func testExampleUndoRetainsExactImportanceLevelsAndLegacySnapshots() throws {
        let suite = "ImportanceUndo." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let levels = [1: 3, 2: 4, 3: 5]
        XCTAssertTrue(ExampleLoadUndoStore.save(lists: [], todayListID: nil, importantCardIDs: Set(levels.keys), importanceLevels: levels, to: defaults))
        XCTAssertEqual(ExampleLoadUndoStore.load(from: defaults)?.importanceLevels, levels)
        let legacy = ExampleLoadUndoSnapshot(lists: [], todayListID: nil, importantCardIDs: [1])
        XCTAssertNil(try JSONDecoder().decode(ExampleLoadUndoSnapshot.self, from: JSONEncoder().encode(legacy)).importanceLevels)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testImportanceExamplesDemonstrateBusyDaysWithoutChangingExistingOwners
    /// @brief      Verify example levels and preservation of unrelated personal importance
    /// @details    Work, Gym, and Dinner demonstrate distinct layered states; arbitrary example
    ///             titles also receive levels only through explicit example seeding.
    ///
    /// @return     (Void) records fresh-example and preservation assertions
    ///
    func testImportanceExamplesDemonstrateBusyDaysWithoutChangingExistingOwners() {
        let other = UUID()
        let original = LibraryImportanceSelection.settingLevel(cardID: 4, collectionID: other, level: 5, data: Data())
        var owner = PersonalCollection(title: "Example", kind: .list)
        owner.lists[0].cards = ["Work", "Gym", "Dinner", "Sketch an idea"].enumerated().map {
            KanbanCard(id: $0.offset, word: $0.element, listTitle: "Example")
        }
        let data = LibraryImportanceSelection.demoData(in: [owner], preserving: original, includesAllExamples: true)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 0, collectionID: owner.id, data: data), 4)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 1, collectionID: owner.id, data: data), 3)
        XCTAssertEqual(LibraryImportanceSelection.level(cardID: 2, collectionID: owner.id, data: data), 5)
        XCTAssertTrue((1...5).contains(LibraryImportanceSelection.level(cardID: 3, collectionID: owner.id, data: data)))
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
    func testFocusImportanceUsesOwnerQualifiedStateAndSeedsOnlyNamedDemoRecords() throws {
        var first = PersonalCollection(title: "Demo", kind: .list)
        first.lists[0].cards = ["Work", "Gym", "Dinner", "Call Accountant", "Wake", "Morning Starbucks Pow-wow"].enumerated().map {
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
        let accountant = examples.collections.flatMap { owner in owner.lists.flatMap(\.cards).filter { $0.word == "Call the accountant" }.map { (owner.id, $0.id) } }
        XCTAssertFalse(accountant.isEmpty)
        for (owner, card) in accountant {
            XCTAssertTrue(LibraryImportanceSelection.contains(cardID: card, collectionID: owner, data: exampleData))
        }
        let legacy = try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.todayFocusIncludesImportant)
        XCTAssertFalse(legacy.todayFocusIncludesBookmarked)
        XCTAssertFalse(legacy.todayFocusIncludesUpNext)
        let selected = LocalProfilePreferences(todayFocusIncludesImportant: true, todayFocusIncludesBookmarked: true, todayFocusIncludesUpNext: true)
        XCTAssertEqual(try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONEncoder().encode(selected)), selected)
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
    func testFocusShapePreferencesKeepLegacyDefaultsAndPersistWithoutProfile() throws {
        let legacy = try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.todayFocusOrder, .dayList)
        XCTAssertFalse(legacy.todayFocusGroupsBySection)
        XCTAssertTrue(legacy.todayFocusHidesCompleted)
        let suite = "FocusShape." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LocalProfilePreferences(todayFocusItemCount: 0,
            todayFocusOrder: .chronological, todayFocusGroupsBySection: true, todayFocusHidesCompleted: false)
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
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
    func testFocusShapePreservesSectionsStableTiesAndAllMatchesAfterSorting() throws {


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
        func item(_ id: Int, _ title: String, _ time: Double? = nil, done: Bool = false) -> KanbanCard {
            var card = KanbanCard(id: id, word: title, listTitle: "Monday", isTitleChecked: done, checklists: [])
            card.startDate = time.map { Date(timeIntervalSince1970: $0) }
            card.startDateKind = .dateAndTime
            return card
        }
        let firstHeading = KanbanCard(id: 90, word: "--- Looking forward to", listTitle: "Monday", isDivider: true, checklists: [])
        let secondHeading = KanbanCard(id: 91, word: "--- Must happen", listTitle: "Monday", isDivider: true, checklists: [])
        let repeatedHeading = KanbanCard(id: 92, word: "--- Must happen", listTitle: "Monday", isDivider: true, checklists: [])
        let cards = [item(1, "Before sections"), firstHeading, item(2, "Later", 200),
            item(3, "Earlier", 100), item(4, "Same time", 100), item(5, "Done", 50, done: true),
            secondHeading, item(6, "Undated"), item(7, "Another time", 25), repeatedHeading, item(8, "Repeated section", 1)]
        let original = cards
        var preferences = LocalProfilePreferences(todayFocusItemCount: 0,
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
    /// @fcn        PlenactBoardDocumentTests.testFocusChronologyHonorsTimeOnlyDateOnlyAndDueFallback
    /// @brief      Verify that focus Chronology Honors Time Only Date Only And Due Fallback
    /// @details    Exercises `(1...5).map`, `preferences.todayFocusEntries`, `entries.map`. Checks
    ///             `XCTAssertEqual(entries.map(\.id), [3, 2, 4, 1, 5])`; `XCTAssertEqual(entries[1].scheduleDate(on:
    ///             day, calendar: calendar), time(9, day: 19))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFocusChronologyHonorsTimeOnlyDateOnlyAndDueFallback() throws {
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
        func time(_ hour: Int, day date: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: date, hour: hour))!
        }
        var cards = (1...5).map { KanbanCard(id: $0, word: "Item \($0)", listTitle: "Monday", checklists: []) }
        cards[0].startDate = time(17, day: 1); cards[0].startDateKind = .time
        cards[1].dueDate = time(9, day: 25); cards[1].dueDateKind = .time
        cards[2].startDate = time(22, day: 19); cards[2].startDateKind = .date
        cards[3].startDate = time(12, day: 19); cards[3].startDateKind = .dateAndTime
        let preferences = LocalProfilePreferences(todayFocusItemCount: 0, todayFocusOrder: .chronological)
        let entries = preferences.todayFocusEntries(in: cards, on: day, calendar: calendar)
        XCTAssertEqual(entries.map(\.id), [3, 2, 4, 1, 5])
        XCTAssertEqual(entries[1].scheduleDate(on: day, calendar: calendar), time(9, day: 19))
        XCTAssertTrue(try XCTUnwrap(entries[1].scheduleLabel).hasPrefix("Due · "))
        XCTAssertNil(entries.last?.scheduleLabel)
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
    func testDayDistributionSplitsTagsAndCountsCompletionWithoutInventingTime() throws {
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
        func date(_ hour: Int) -> Date { calendar.date(byAdding: .hour, value: hour, to: day)! }
        let cards = [
            KanbanCard(id: 1, word: "Work", listTitle: "Tuesday", isTitleChecked: true,
                startDate: date(9), dueDate: date(11), labelIDs: ["day-work", "day-health", "day-work"],
                startDateKind: .dateAndTime, dueDateKind: .dateAndTime),
            KanbanCard(id: 2, word: "Uncategorized", listTitle: "Tuesday", startDate: date(10), dueDate: date(11),
                startDateKind: .dateAndTime, dueDateKind: .dateAndTime),
            KanbanCard(id: 3, word: "Untimed", listTitle: "Tuesday", startDate: date(0), dueDate: date(0)),
            KanbanCard(id: 4, word: "Note", listTitle: "Tuesday", presentation: .note)
        ]
        let result = DayTimeDistribution(cards: cards, labels: LabelLibrary.starter.includingDayAreas, day: day, calendar: calendar)
        XCTAssertEqual(result.total, 10800, accuracy: 0.01)
        XCTAssertEqual(result.completedTime, 7200, accuracy: 0.01)
        XCTAssertEqual(result.taskCount, 3)
        XCTAssertEqual(result.completedCount, 1)
        XCTAssertEqual(result.untimedCount, 1)
        XCTAssertTrue(result.hasOverlaps)
        XCTAssertEqual(result.segments.first { $0.id == "day-work" }?.planned, 3600)
        XCTAssertEqual(result.segments.first { $0.id == "day-health" }?.planned, 3600)
        let overnight = KanbanCard(id: 5, word: "Night", listTitle: "Tuesday", startDate: date(23), dueDate: date(1),
            startDateKind: .time, dueDateKind: .time)
        XCTAssertEqual(DayTimeDistribution(cards: [overnight], labels: .starter, day: day, calendar: calendar).total, 3600)
        let reverse = KanbanCard(id: 6, word: "Invalid", listTitle: "Tuesday", startDate: date(11), dueDate: date(9),
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
    func testDefaultWeekUsesValidDayAreaTagsWithoutRewritingCustomTags() throws {
        let labels = LabelLibrary.starter.includingDayAreas
        let template = PlanningRoutineLibrary.jmr
        XCTAssertTrue(template.collection.lists.flatMap(\.cards).allSatisfy { card in
            !card.labelIDs.isEmpty && card.labelIDs.allSatisfy { id in labels.labels.contains { $0.id == id } }
        })
        let suite = "DayDistribution." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = PlanningRoutineLibrary.seeded
        old.bundledRoutineRevision = 1
        let index = try XCTUnwrap(old.templates.firstIndex { $0.id == PlanningRoutineLibrary.jmrID })
        old.templates[index].collection.lists[0].cards[0].labelIDs = ["custom-tag"]
        old.templates[index].collection.lists[0].cards[1].labelIDs = []
        defaults.set(try JSONEncoder().encode(old), forKey: PlanningRoutineStore.key)
        let upgraded = try PlanningRoutineStore.load(from: defaults)
        XCTAssertEqual(upgraded.templates[index].collection.lists[0].cards[0].labelIDs, ["custom-tag"])
        XCTAssertFalse(upgraded.templates[index].collection.lists[0].cards[1].labelIDs.isEmpty)
        XCTAssertEqual(upgraded.bundledRoutineRevision, 4)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testToolbarRevisitMenuRendersWithoutChoosingOrChangingHistory
    /// @brief      Verify that toolbar Revisit Menu Renders Without Choosing Or Changing History
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(UserDefaults.standard.data(forKey:
    ///             ActivityRecentStore.key), history)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testToolbarRevisitMenuRendersWithoutChoosingOrChangingHistory() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let history = UserDefaults.standard.data(forKey: ActivityRecentStore.key)
        for scheme in [ColorScheme.light, .dark] {
            let host = UIHostingController(rootView: ToolbarRevisitMenu { _ in XCTFail("Rendering must not navigate") }
                .background(.regularMaterial).preferredColorScheme(scheme))
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-revisit-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: path); print("REVISIT_RENDER=" + path.path)
        }
        XCTAssertEqual(UserDefaults.standard.data(forKey: ActivityRecentStore.key), history)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDayDistributionBannerRendersWithNoPlanWrites
    /// @brief      Verify that day Distribution Banner Renders With No Plan Writes
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(UserDefaults.standard.data(forKey:
    ///             DailyPlanStore.key), before)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDayDistributionBannerRendersWithNoPlanWrites() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let before = UserDefaults.standard.data(forKey: DailyPlanStore.key)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let cards = (0..<5).map { i in
            KanbanCard(id: i, word: "Planned activity", listTitle: "Today", isTitleChecked: i % 2 == 0,
                startDate: day.addingTimeInterval(Double(i + 7) * 3600), dueDate: day.addingTimeInterval(Double(i + 8) * 3600),
                labelIDs: [LabelLibrary.dayAreaLabels[i].id], startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
        }
        for (name, items, scheme) in [("populated", cards, ColorScheme.light), ("empty", [], .light), ("dark", cards, .dark)] {
            let host = UIHostingController(rootView: ScrollView {
                DayScheduleOverview(cards: items, labels: LabelLibrary.starter.includingDayAreas, day: day).padding(16)
            }.preferredColorScheme(scheme))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-day-distribution-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: url); print("DAY_DISTRIBUTION_RENDER=" + url.path)
        }
        XCTAssertEqual(UserDefaults.standard.data(forKey: DailyPlanStore.key), before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodaySectionSnapOnlyCrossesBoundariesAndRespectsReducedMotion
    /// @brief      Verify that today Section Snap Only Crosses Boundaries And Respects Reduced Motion
    /// @details    Exercises `TodaySectionSnapBehavior.destination`. Checks `XCTAssertEqual(snap(0, 450), 800)`;
    ///             `XCTAssertEqual(snap(800, 650), 0)`.
    ///
    /// @return     (Void) no return value
    ///
    func testTodaySectionSnapOnlyCrossesBoundariesAndRespectsReducedMotion() {


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
        func snap(_ start: CGFloat, _ proposed: CGFloat, enabled: Bool = true, maximum: CGFloat = 1200) -> CGFloat? {
            TodaySectionSnapBehavior.destination(start: start, proposed: proposed, perspectiveTop: 800,
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
        XCTAssertNil(TodaySectionSnapBehavior.destination(start: 0, proposed: 500,
            perspectiveTop: 0, shortcutsBottom: 0, viewport: 600, maximum: 1200, enabled: true))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayPerspectiveRendersWithoutMutatingPlansOrLists
    /// @brief      Verify that today Perspective Renders Without Mutating Plans Or Lists
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(UserDefaults.standard.data(forKey:
    ///             DailyPlanStore.key), beforePlans)`; `XCTAssertEqual(UserDefaults.standard.data(forKey:
    ///             ReviewRhythmStore.dismissalsKey), beforeRhythm)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayPerspectiveRendersWithoutMutatingPlansOrLists() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let beforePlans = UserDefaults.standard.data(forKey: DailyPlanStore.key)
        let beforeRhythm = UserDefaults.standard.data(forKey: ReviewRhythmStore.dismissalsKey)
        let completed = [KanbanCard(id: 1, word: "Make time for family", listTitle: "Today", isTitleChecked: true, checklists: [])]
        let tomorrow = KanbanList(id: 2, title: "Tomorrow", cards: [
            KanbanCard(id: 2, word: "A thoughtful start", listTitle: "Tomorrow", checklists: []),
            KanbanCard(id: 3, word: "A long walk and a little room to think", listTitle: "Tomorrow", checklists: [])])
        for (name, done, next, scheme, width) in [
            ("populated", completed, Optional(tomorrow), ColorScheme.light, CGFloat(393)),
            ("quiet", [], nil, .light, 393),
            ("dark-tablet", completed, Optional(tomorrow), .dark, 820)
        ] {
            let view = ScrollView {
                TodayPerspectiveSection(completed: done, tomorrowList: next,
                    onReview: { _ in XCTFail("Rendering must not open review") },
                    onSettings: { XCTFail("Rendering must not open settings") },
                    onReflect: { XCTFail("Rendering must not open a plan") },
                    onPrepare: { XCTFail("Rendering must not create a plan") })
                    .padding(20)
            }.background(Color(.systemGroupedBackground)).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-perspective-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: path)
            print("PERSPECTIVE_RENDER=" + path.path)
        }
        XCTAssertEqual(UserDefaults.standard.data(forKey: DailyPlanStore.key), beforePlans)
        XCTAssertEqual(UserDefaults.standard.data(forKey: ReviewRhythmStore.dismissalsKey), beforeRhythm)
        XCTAssertTrue(completed[0].isTitleChecked)
        XCTAssertEqual(tomorrow.cards.count, 2)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusOverflowRetainsNativeScrollingToLastMatchingItem
    /// @brief      Verify that focus Overflow Retains Native Scrolling To Last Matching Item
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(entries.count, 9)`;
    ///             `XCTAssertTrue(inner.isScrollEnabled)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testFocusOverflowRetainsNativeScrollingToLastMatchingItem() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let cards = (1...9).map { KanbanCard(id: $0, word: "Focus task \($0)", listTitle: "Today", checklists: []) }
        let list = KanbanList(id: 1, title: "Today", cards: cards)
        let prefs = LocalProfilePreferences(todayFocusItemCount: 4)
        let entries = prefs.todayFocusEntries(in: cards)
        XCTAssertEqual(entries.count, 9)
        let host = UIHostingController(rootView: ScrollView {
            TodayFocusSection(list: list, cards: cards, entries: entries, groupsBySection: false, chronological: false,
                onToggleCard: { _ in XCTFail("Scrolling must not edit") }, onOpenCard: { _ in },
                onDeleteCard: { _ in XCTFail("Scrolling must not delete"); return false }, onOpenTodayList: {})
                .padding(20)
        })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        // Recurse through parent scroll views as well as ordinary containers.


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusOverflowRetainsNativeScrollingToLastMatchingItem.allScrollViews
        /// @brief      Find all scroll views in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func allScrollViews(_ view: UIView) -> [UIScrollView] {
            var result = (view as? UIScrollView).map { [$0] } ?? []
            result += view.subviews.flatMap(allScrollViews)
            return result
        }
        let inner = try XCTUnwrap(allScrollViews(host.view).first {
            $0.bounds.height > 0 && $0.bounds.height < 350 && $0.contentSize.height > $0.bounds.height + 100
        })
        XCTAssertTrue(inner.isScrollEnabled)
        let end = inner.contentSize.height - inner.bounds.height + inner.adjustedContentInset.bottom
        inner.setContentOffset(CGPoint(x: 0, y: end), animated: false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(inner.contentOffset.y, 100)
        let settledEnd = inner.contentSize.height - inner.bounds.height + inner.adjustedContentInset.bottom
        inner.setContentOffset(CGPoint(x: 0, y: settledEnd), animated: false)
        XCTAssertEqual(inner.contentOffset.y, settledEnd, accuracy: 2)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusShapeRendersDefaultGroupedAndCompletedPreviewsWithoutMutations
    /// @brief      Verify that focus Shape Renders Default Grouped And Completed Previews Without Mutations
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(list, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testFocusShapeRendersDefaultGroupedAndCompletedPreviewsWithoutMutations() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        var list = KanbanList(id: 1, title: "Monday", cards: [])
        list.cards = [KanbanCard(id: 90, word: "--- Looking forward to", listTitle: "Monday", isDivider: true, checklists: [])]
        list.cards += (1...6).map { KanbanCard(id: $0, word: "\($0 == 1 ? "Dinner with family" : "Make time for something meaningful")", listTitle: "Monday", isTitleChecked: $0 == 2, checklists: []) }
        list.cards.insert(KanbanCard(id: 91, word: "--- Must happen", listTitle: "Monday", isDivider: true, checklists: []), at: 4)
        list.cards[1].startDate = .now
        let original = list
        for (name, preference, scheme, width) in [
            ("default", LocalProfilePreferences(), ColorScheme.light, CGFloat(393)),
            ("grouped", LocalProfilePreferences(todayFocusItemCount: 0, todayFocusOrder: .chronological, todayFocusGroupsBySection: true, todayFocusHidesCompleted: false), .light, 393),
            ("dark-tablet", LocalProfilePreferences(todayFocusItemCount: 0, todayFocusGroupsBySection: true), .dark, 820),
            ("up-next", LocalProfilePreferences(todayFocusIncludesUpNext: true), .light, 393),
            ("filtered-empty", LocalProfilePreferences(todayFocusIncludesImportant: true), .light, 393)
        ] {
            let view = ScrollView {
                TodayFocusSection(list: list, cards: list.cards.filter { !$0.isSectionDivider },
                    entries: preference.todayFocusEntries(in: list.cards), groupsBySection: preference.todayFocusGroupsBySection,
                    chronological: preference.todayFocusOrder == .chronological,
                    includesImportant: preference.todayFocusIncludesImportant,
                    includesBookmarked: preference.todayFocusIncludesBookmarked,
                    includesUpNext: preference.todayFocusIncludesUpNext,
                    onToggleCard: { _ in XCTFail("Rendering must not toggle") }, onOpenCard: { _ in },
                    onDeleteCard: { _ in XCTFail("Rendering must not delete"); return false }, onOpenTodayList: {})
                    .padding(20)
            }.background(Color(.systemGroupedBackground)).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-focus-shape-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("FOCUS_SHAPE_RENDER=" + url.path)
            XCTAssertEqual(list, original)
        }
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
    func testTodayFocusRowCapacityNeverTruncatesOrderedUnfinishedMatches() throws {
        var cards = (0..<16).map { KanbanCard(id: $0, word: "Item \($0)", listTitle: "Monday", isTitleChecked: $0 == 0 || $0 == 5, checklists: []) }
        cards.insert(KanbanCard(id: 99, word: "Break", listTitle: "Monday", isDivider: true, checklists: []), at: 3)
        let original = cards
        let open = cards.filter { !$0.isSectionDivider && !$0.isTitleChecked }
        XCTAssertEqual(open.count, 14)
        XCTAssertEqual(LocalProfilePreferences().todayFocusItems(in: cards).map(\.id), open.map(\.id))
        for count in 1...12 {
            XCTAssertEqual(LocalProfilePreferences(todayFocusItemCount: count).todayFocusItems(in: cards).map(\.id), open.map(\.id))
        }
        XCTAssertEqual(LocalProfilePreferences(todayFocusItemCount: 0).todayFocusItems(in: cards), open)
        XCTAssertTrue(LocalProfilePreferences().todayFocusItems(in: []).isEmpty)
        XCTAssertEqual(cards, original)
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
    func testJmrTemplateMatchesAllRequestedTimeRangesAndDailyGymNotes() throws {
        let template = PlanningRoutineLibrary.jmr
        XCTAssertEqual(template.name, "Jmr")
        XCTAssertEqual(template.kind, .week)
        XCTAssertEqual(template.itemCount, 28)
        XCTAssertEqual(template.collection.lists.count, 7)
        XCTAssertEqual(PlanningRoutineLibrary.seeded.defaultWeekID, template.id)
        for firstWeekday in [1, 2] {
            let calendar = routineCalendar(firstWeekday: firstWeekday)
            let targetDate = try XCTUnwrap(PlanningDate.date("2026-11-01", calendar: calendar))
            let target = DatedPlanningWeek.make(for: targetDate, calendar: calendar)
            let applied = try PlanningTemplateApplication.apply(template, to: target, date: targetDate, calendar: calendar, mode: .add)
            for day in PlanningDate.days(in: applied.startKey, calendar: calendar) {
                let weekday = calendar.component(.weekday, from: day)
                let cards = try XCTUnwrap(applied.list(on: day)?.cards)
                let expected: [(String, Int, Int, Int, Int)]
                if weekday == 7 {
                    expected = [("Wake", 5, 0, 5, 30), ("Morning Starbucks Pow-wow", 6, 0, 7, 30), ("Gym", 9, 0, 11, 0), ("Car Wash", 12, 0, 12, 30)]
                } else if weekday == 1 {
                    expected = [("Wake", 4, 0, 4, 30), ("Morning Starbucks Pow-wow", 5, 0, 6, 30), ("Gym", 7, 0, 8, 30), ("Church", 9, 0, 12, 30)]
                } else {
                    expected = [("Wake", 4, 0, 4, 30), ("Morning Starbucks Pow-wow", 5, 0, 6, 30), ("Work", 7, 0, 17, 0), ("Gym", 17, 0, 18, 0)]
                }
                XCTAssertEqual(cards.count, expected.count)
                for (card, slot) in zip(cards, expected) {
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
                    if card.word == "Gym" {
                        XCTAssertTrue(card.funParagraph.contains("meditation, walking, or massage"))
                    } else { XCTAssertEqual(card.descriptionOverride, "") }
                }
            }
        }
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
    func testJmrUpgradeKeepsSavedTemplatesAndDoesNotRewriteScheduledWeeks() throws {
        let name = "Plenact.JmrUpgradeTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var legacy = PlanningRoutineLibrary.seeded
        legacy.templates.removeAll { $0.id == PlanningRoutineLibrary.jmrID }
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
        XCTAssertEqual(upgraded.bundledRoutineRevision, 4)
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), oldBytes)
        XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), weekBytes)
        var customChoice = upgraded; customChoice.defaultWeekID = nil
        try PlanningRoutineStore.save(customChoice, baseline: upgraded, to: defaults)
        XCTAssertNil(try PlanningRoutineStore.load(from: defaults).defaultWeekID)
        var deleted = customChoice; deleted.templates.removeAll { $0.id == PlanningRoutineLibrary.jmrID }
        try PlanningRoutineStore.save(deleted, baseline: customChoice, to: defaults)
        XCTAssertFalse(try PlanningRoutineStore.load(from: defaults).templates.contains { $0.id == PlanningRoutineLibrary.jmrID })
        XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), weekBytes)
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
    func testLibraryDaySectionExamplesSearchIncludesHeadingsAndMemberItems() {
        XCTAssertEqual(LibraryDaySectionExamples.matches(query: "day sections").count, 3)
        XCTAssertEqual(LibraryDaySectionExamples.matches(query: "morning").map(\.name), ["A day in chapters"])
        XCTAssertEqual(LibraryDaySectionExamples.matches(query: "tools teardown").map(\.name), ["A build session"])
        XCTAssertEqual(LibraryDaySectionExamples.matches(query: "headphones home").map(\.name), ["A workout journey"])
        XCTAssertTrue(LibraryDaySectionExamples.matches(query: "nonexistent example zzz").isEmpty)
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
    func testLibraryStarterFiltersScopeSearchAndExcludePersonalCollections() throws {
        let list = PersonalCollection(title: "Vacation private plans", kind: .list)
        let board = PersonalCollection(title: "Example private work", kind: .board)
        for filter in [LibraryBrowseFilter.templates, .examples, .labels, .help] {
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
    func testLibraryTemplateCaptureUsesLiveWeekAndReservesArchivedIDs() throws {
        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar))
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let listID = try XCTUnwrap(week.dayListIDs["2026-10-12"])
        let index = try XCTUnwrap(week.collection.lists.firstIndex { $0.id == listID })
        week.collection.lists[index].cards = [KanbanCard(id: 2, word: "Keep my work", listTitle: "Monday", isTitleChecked: true, checklists: [])]
        week.collection.lists[index].archivedCards = [KanbanCard(id: 99, word: "Keep archive", listTitle: "Monday", checklists: [])]
        let template = QuickCaptureTemplate.smallPlan
        let capture = QuickCaptureSubmission(listID: listID, title: "My custom title", body: template.body,
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
        let richBody = PlanRichText.prefix + (try JSONEncoder().encode([PlanRichText.Run(text: "Keep the formatting", bold: true)])).base64EncodedString()
        let note = QuickCaptureSubmission(listID: listID, title: "My note", body: richBody, subtitle: "", presentation: .note,
            actions: nil, attachments: [], schedule: nil)
        XCTAssertEqual(try LibraryTemplateCapture.adding(note, to: result).collection.lists[index].cards.last?.descriptionOverride, richBody)
        let missing = QuickCaptureSubmission(listID: 98765, title: "No target", body: "", subtitle: "", presentation: .card,
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
    func testLibraryTemplatesAndExamplesFiltersRenderAndSearchWithoutWriting() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let keys = [PlanningRoutineStore.key, PlanningCalendarStore.key, "Plenact.PersonalCollections.v1", "Plenact.Board.v1"]
        let before = keys.map { UserDefaults.standard.data(forKey: $0) }
        var saved = 0
        let privateCollection = PersonalCollection(title: "Private unrelated project", kind: .list)
        for width in [393.0, 744.0] {
            for (filter, query) in [(LibraryBrowseFilter.templates, ""), (.examples, ""), (.templates, "vacation"), (.examples, "month motion"), (.examples, "day sections")] {
                let host = UIHostingController(rootView: BoardListsView(retainedWeekLists: [], collections: .constant([privateCollection]),
                    registerListNewNote: { _ in }, onOpenSaved: { saved += 1 },
                    onLoadExampleWeek: { saved += 1; return true }, onLoadExampleMonth: { saved += 1 },
                    browseFilter: filter, searchText: query))
                window.frame = CGRect(x: 0, y: 0, width: width, height: 1024)
                window.rootViewController = host; window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(300))
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-library-\(filter.rawValue)-\(Int(width))-\(query.isEmpty ? "all" : query.replacingOccurrences(of: " ", with: "-")).png")
                try XCTUnwrap(image.pngData()).write(to: url)
                print("LIBRARY_FILTER_RENDER=" + url.path)
            }
        }
        XCTAssertEqual(saved, 0)
        XCTAssertEqual(keys.map { UserDefaults.standard.data(forKey: $0) }, before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningTemplateMediaRetentionAndWorkspaceBackup
    /// @brief      Verify that planning Template Media Retention And Workspace Backup
    /// @details    Exercises `PlanningRoutineStore.load`, `PlanningRoutineStore.save`,
    ///             `PlanningRoutineStore.retainedFiles`. Checks `XCTAssertEqual(try
    ///             PlanningRoutineStore.retainedFiles(from: defaults), ["routine-preview.png",
    ///             "routine-strokes.drawing"])`; `XCTAssertNil(defaults.object(forKey: PlanningRoutineStore.key))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPlanningTemplateMediaRetentionAndWorkspaceBackup() throws {
        let name = "Plenact.RoutineBackupTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        let baseline = try PlanningRoutineStore.load(from: defaults)
        var library = baseline
        var attachment = KanbanAttachment(fileName: "routine-preview.png", mediaKind: .photo)
        attachment.drawingFileName = "routine-strokes.drawing"
        library.templates[1].collection.lists[0].cards[0].attachments = [attachment]
        try PlanningRoutineStore.save(library, baseline: baseline, to: defaults)
        XCTAssertEqual(try PlanningRoutineStore.retainedFiles(from: defaults), ["routine-preview.png", "routine-strokes.drawing"])
        let bytes = try XCTUnwrap(defaults.data(forKey: PlanningRoutineStore.key))
        let documents = folder.appendingPathComponent("Documents")
        let media = documents.appendingPathComponent("CardAttachments")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let preview = Data("saved PNG preview".utf8), strokes = Data("editable native strokes".utf8)
        try preview.write(to: media.appendingPathComponent("routine-preview.png"))
        try strokes.write(to: media.appendingPathComponent("routine-strokes.drawing"))
        let store = FullMonthExampleStore(root: folder.appendingPathComponent("Backup"), documents: documents,
            support: folder.appendingPathComponent("Support"), domainName: name)
        try store.loadExample(FullMonthExample.make())
        XCTAssertNil(defaults.object(forKey: PlanningRoutineStore.key))
        try store.restoreUserData()
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), bytes)
        XCTAssertEqual(try Data(contentsOf: media.appendingPathComponent("routine-preview.png")), preview)
        XCTAssertEqual(try Data(contentsOf: media.appendingPathComponent("routine-strokes.drawing")), strokes)
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
    func testPlanningWeekReplacementPreservesUndatedAndArchivedContent() throws {
        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: calendar))
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let monday = try XCTUnwrap(week.collection.lists.firstIndex { $0.id == week.dayListIDs["2026-11-02"] })
        week.collection.lists[monday].cards = [KanbanCard(id: 100, word: "Replace this", listTitle: "Monday", checklists: [])]
        week.collection.lists[monday].archivedCards = [KanbanCard(id: 101, word: "Retain archive", listTitle: "Monday", checklists: [])]
        let undated = KanbanList(id: 50, title: "Other plans", cards: [KanbanCard(id: 102, word: "Keep undated", listTitle: "Other plans", checklists: [])])
        week.collection.lists.append(undated)
        let applied = try PlanningTemplateApplication.apply(PlanningRoutineLibrary.seeded.templates[0], to: week, date: date, calendar: calendar, mode: .replace)
        XCTAssertEqual(applied.collection.lists.first { $0.id == 50 }, undated)
        XCTAssertEqual(applied.collection.lists[monday].archivedCards, week.collection.lists[monday].archivedCards)
        XCTAssertFalse(applied.collection.lists.flatMap(\.cards).contains { $0.word == "Replace this" })
        XCTAssertEqual(applied.collection.lists.flatMap(\.cards).filter { !$0.isSectionDivider }.count, 43)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.routineCalendar
    /// @brief      Prepare routine calendar for the enclosing regression test
    /// @details    Supplies the local fixture for plenactBoardDocumentTests.
    ///
    /// @param[in]  firstWeekday  Calendar weekday index used to define the fixture week start
    ///
    /// @return     (Calendar) result described by this operation's contract
    ///
    private func routineCalendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = firstWeekday
        return calendar
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
    func testPlanningTemplatesSeedStoreConflictAndCorruptDataRetention() throws {
        let name = "Plenact.RoutineTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let baseline = try PlanningRoutineStore.load(from: defaults)
        XCTAssertNil(defaults.data(forKey: PlanningRoutineStore.key))
        XCTAssertEqual(baseline.templates.map(\.name), ["Work Week", "Vacation Day", "Jmr"])
        XCTAssertEqual(baseline.defaultWeekID, PlanningRoutineLibrary.jmrID)
        XCTAssertEqual(try PlanningRoutineStore.load(from: defaults), baseline)
        var updated = baseline; updated.templates[0].name = "My work routine"; updated.defaultWeekID = nil
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
    func testPlanningWeekTemplateCopiesResetCompletionAndRemapLinks() throws {
        let calendar = routineCalendar()
        let sourceDate = try XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar))
        var source = DatedPlanningWeek.make(for: sourceDate, calendar: calendar)
        let mondayID = try XCTUnwrap(source.dayListIDs["2026-10-12"])
        let index = try XCTUnwrap(source.collection.lists.firstIndex { $0.id == mondayID })
        let attachment = KanbanAttachment(fileName: "drawing-preview.png", mediaKind: .photo)
        var drawing = attachment; drawing.drawingFileName = "drawing-strokes.drawing"
        let linked = KanbanChecklistItem(title: "Linked", isCompleted: true, content: .linkedCard(cardID: 20))
        source.collection.lists[index].cards = [
            KanbanCard(id: 10, word: "Work", listTitle: "Monday", isTitleChecked: true,
                checklists: [KanbanChecklist(title: "Steps", items: [linked], completedItemIndices: [0])],
                comments: [KanbanComment(author: "Me", body: "Old activity")], attachments: [drawing], coverAttachmentID: drawing.id, createdAt: sourceDate),
            KanbanCard(id: 20, word: "Supporting note", listTitle: "Monday", checklists: [], presentation: .note)]
        source.collection.lists[index].archivedCards = [KanbanCard(id: 99, word: "Archive", listTitle: "Monday")]
        let template = try PlanningRoutineTemplate.capture(name: "Work", week: source, calendar: calendar)
        XCTAssertTrue(template.collection.lists[index].archivedCards.isEmpty)
        XCTAssertTrue(template.collection.lists[index].cards[0].comments.isEmpty)
        let targetDate = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: calendar))
        var target = DatedPlanningWeek.make(for: targetDate, calendar: calendar)
        let targetIndex = try XCTUnwrap(target.collection.lists.firstIndex { $0.id == target.dayListIDs["2026-11-02"] })
        target.collection.lists[targetIndex].cards = [KanbanCard(id: 100, word: "Already planned", listTitle: "Monday", checklists: [])]
        let result = try PlanningTemplateApplication.apply(template, to: target, date: targetDate, calendar: calendar, mode: .add, now: targetDate)
        let copied = result.collection.lists[targetIndex].cards
        XCTAssertEqual(copied.map(\.word), ["Already planned", "Work", "Supporting note"])
        XCTAssertFalse(copied[1].isTitleChecked)
        XCTAssertFalse(copied[1].checklists[0].items[0].isCompleted)
        XCTAssertTrue(copied[1].checklists[0].completedItemIndices.isEmpty)
        XCTAssertNotEqual(copied[1].checklists[0].id, source.collection.lists[index].cards[0].checklists[0].id)
        XCTAssertNotEqual(copied[1].checklists[0].items[0].id, linked.id)
        if case .linkedCard(let id) = copied[1].checklists[0].items[0].content { XCTAssertEqual(id, copied[2].id) }
        else { XCTFail("Internal checklist links must target the copied card") }
        XCTAssertTrue(copied[1].comments.isEmpty)
        XCTAssertEqual(copied[1].createdAt, targetDate)
        XCTAssertEqual(copied[1].funParagraph, source.collection.lists[index].cards[0].funParagraph)
        XCTAssertEqual(copied[1].subtitle, source.collection.lists[index].cards[0].subtitle)
        XCTAssertNotEqual(copied[1].attachments?.first?.id, drawing.id)
        XCTAssertEqual(copied[1].attachments?.first?.drawingFileName, drawing.drawingFileName)
        XCTAssertEqual(copied[1].coverAttachmentID, copied[1].attachments?.first?.id)
        XCTAssertEqual(copied[2].presentation, .note)
        XCTAssertEqual(source.collection.lists[index].cards[0].isTitleChecked, true)
        var edited = template; edited.collection.lists[index].cards[0].word = "New routine"
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
    func testPlanningTemplatesShiftDaysAcrossWeekStartAndDaylightSaving() throws {
        let sourceCalendar = routineCalendar(firstWeekday: 1)
        let sourceDate = try XCTUnwrap(PlanningDate.date("2026-10-25", calendar: sourceCalendar))
        var source = DatedPlanningWeek.make(for: sourceDate, calendar: sourceCalendar)
        let monday = try XCTUnwrap(PlanningDate.date("2026-10-26", calendar: sourceCalendar))
        let mondayID = try XCTUnwrap(source.dayListIDs["2026-10-26"])
        let index = try XCTUnwrap(source.collection.lists.firstIndex { $0.id == mondayID })
        let start = try XCTUnwrap(sourceCalendar.date(bySettingHour: 9, minute: 30, second: 0, of: monday))
        let due = try XCTUnwrap(sourceCalendar.date(byAdding: .day, value: 1, to: start))
        source.collection.lists[index].cards = [KanbanCard(id: 7, word: "Timed", listTitle: "Monday", startDate: start, dueDate: due, checklists: [], startDateKind: .dateAndTime, dueDateKind: .dateAndTime)]
        let template = try PlanningRoutineTemplate.capture(name: "Week", week: source, calendar: sourceCalendar)
        let destinationCalendar = routineCalendar()
        let targetDate = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: destinationCalendar))
        let target = DatedPlanningWeek.make(for: targetDate, calendar: destinationCalendar)
        let applied = try PlanningTemplateApplication.apply(template, to: target, date: targetDate, calendar: destinationCalendar, mode: .add)
        let copy = try XCTUnwrap(applied.list(on: targetDate)?.cards.first)
        XCTAssertEqual(PlanningDate.key(try XCTUnwrap(copy.startDate), calendar: destinationCalendar), "2026-11-02")
        XCTAssertEqual(destinationCalendar.component(.hour, from: try XCTUnwrap(copy.startDate)), 9)
        XCTAssertEqual(destinationCalendar.component(.minute, from: try XCTUnwrap(copy.startDate)), 30)
        let dayTemplate = try PlanningRoutineTemplate.capture(name: "Vacation", week: source, day: monday, calendar: sourceCalendar)
        let saturday = try XCTUnwrap(PlanningDate.date("2026-10-31", calendar: destinationCalendar))
        let saturdayTarget = DatedPlanningWeek.make(for: saturday, calendar: destinationCalendar)
        let day = try PlanningTemplateApplication.apply(dayTemplate, to: saturdayTarget, date: saturday, calendar: destinationCalendar, mode: .add)
        let dayCopy = try XCTUnwrap(day.list(on: saturday)?.cards.first)
        XCTAssertEqual(PlanningDate.key(try XCTUnwrap(dayCopy.startDate), calendar: destinationCalendar), "2026-10-31")
        XCTAssertEqual(PlanningDate.key(try XCTUnwrap(dayCopy.dueDate), calendar: destinationCalendar), "2026-11-01")
        XCTAssertEqual(destinationCalendar.component(.hour, from: try XCTUnwrap(dayCopy.dueDate)), 9)
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
    func testPlanningDayReplacementKeepsOtherDaysArchivesAndBookmarks() throws {
        let calendar = routineCalendar()
        let date = try XCTUnwrap(PlanningDate.date("2026-11-02", calendar: calendar))
        var target = DatedPlanningWeek.make(for: date, calendar: calendar)
        let monday = try XCTUnwrap(target.collection.lists.firstIndex { $0.id == target.dayListIDs["2026-11-02"] })
        let tuesday = try XCTUnwrap(target.collection.lists.firstIndex { $0.id == target.dayListIDs["2026-11-03"] })
        target.collection.lists[monday].cards = [KanbanCard(id: 50, word: "Old Monday", listTitle: "Monday", checklists: [])]
        target.collection.lists[monday].archivedCards = [KanbanCard(id: 60, word: "Kept archive", listTitle: "Monday", checklists: [])]
        target.collection.lists[tuesday].cards = [KanbanCard(id: 70, word: "Keep Tuesday", listTitle: "Tuesday", checklists: [])]
        target.collection.savedCardIDs = [50, 60, 70]
        let day = PlanningRoutineLibrary.seeded.templates[1]
        let result = try PlanningTemplateApplication.apply(day, to: target, date: date, calendar: calendar, mode: .replace)
        XCTAssertEqual(result.collection.lists[monday].cards.map(\.word), day.collection.lists[0].cards.map(\.word))
        XCTAssertTrue(result.collection.lists[monday].cards.allSatisfy { $0.id > 70 })
        XCTAssertEqual(result.collection.lists[tuesday], target.collection.lists[tuesday])
        XCTAssertEqual(result.collection.lists[monday].archivedCards, target.collection.lists[monday].archivedCards)
        XCTAssertEqual(result.collection.savedCardIDs, [60, 70])
        XCTAssertEqual(target.collection.lists[monday].cards[0].word, "Old Monday")
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
    func testPlanningDefaultWeekAppliesOnceAndCanBeDisabled() throws {
        let name = "Plenact.RoutineDefaultTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let calendar = routineCalendar()
        let currentDate = try XCTUnwrap(PlanningDate.date("2026-10-12", calendar: calendar))
        let nextDate = try XCTUnwrap(PlanningDate.date("2026-10-19", calendar: calendar))
        let current = DatedPlanningWeek.make(for: currentDate, calendar: calendar)
        var document = PlanningCalendarDocument(currentWeekKey: current.startKey, firstWeekday: 2, weeks: [current])
        let prepared = try PlanningRoutineStore.newWeek(for: nextDate, calendar: calendar, defaults: defaults)
        XCTAssertTrue(prepared.hasContent)
        XCTAssertTrue(prepared.collection.lists.flatMap(\.cards).allSatisfy { !$0.isTitleChecked && $0.comments.isEmpty })
        let rolled = document.rollForward(to: nextDate, currentLists: current.collection.lists, saved: [], calendar: calendar, newWeek: prepared)
        XCTAssertEqual(rolled, prepared)
        let repeated = document.rollForward(to: nextDate, currentLists: rolled.collection.lists, saved: [], calendar: calendar,
            newWeek: try PlanningRoutineStore.newWeek(for: nextDate, calendar: calendar, defaults: defaults))
        XCTAssertEqual(repeated, rolled)
        XCTAssertEqual(document.weeks.count, 2)
        let baseline = try PlanningRoutineStore.load(from: defaults)
        var disabled = baseline; disabled.defaultWeekID = nil
        try PlanningRoutineStore.save(disabled, baseline: baseline, to: defaults)
        XCTAssertFalse(try PlanningRoutineStore.newWeek(for: nextDate, calendar: calendar, defaults: defaults).hasContent)
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
    func testPlanningTemplateScreensRenderWithoutSaving() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let before = UserDefaults.standard.data(forKey: PlanningRoutineStore.key)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        var saves = 0
        for width in [393.0, 744.0] {
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1024)
            let host = UIHostingController(rootView: PlanningTemplatesView())
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-routines-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("ROUTINE_RENDER=" + url.path)
        }
        let editor = UIHostingController(rootView: PlanningTemplateEditor(template: PlanningRoutineLibrary.seeded.templates[0]) { _ in saves += 1; return true })
        window.rootViewController = editor; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(UserDefaults.standard.data(forKey: PlanningRoutineStore.key), before)
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
    func testLibraryHelpSearchIncludesInstructionsAndExcludesUserCollections() throws {
        XCTAssertEqual(LibraryBrowseFilter.allCases.map(\.rawValue), ["All", "Lists", "Boards", "Labels", "Examples", "Templates", "Help"])
        let collection = PersonalCollection(title: "Help", kind: .list)
        XCTAssertFalse(LibraryBrowseFilter.help.includes(collection))
        XCTAssertEqual(LibraryBrowseFilter.help.searchPrompt, "Find in Help")
        let articles = PlenactHelpCatalog.articles
        XCTAssertEqual(Set(articles.map(\.id)).count, articles.count)
        XCTAssertTrue(["vision", "check-in", "evening", "weekly", "periodic"].allSatisfy { id in articles.contains { $0.id == id && $0.opensPlan } })
        XCTAssertTrue(PlenactHelpCatalog.results(for: "carry objectives").contains { $0.id == "periodic" })
        XCTAssertTrue(PlenactHelpCatalog.results(for: "RESTORE DATA").contains { $0.id == "data" })
        XCTAssertTrue(PlenactHelpCatalog.results(for: "no-such-help-topic-9876").isEmpty)
        XCTAssertEqual(PlenactHelpCatalog.results(for: "  ").count, articles.count)
        XCTAssertTrue(PlenactHelpCatalog.groups.allSatisfy { group in articles.contains { $0.group == group } })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryHelpRendersGuidesWithoutChangingPlanningData
    /// @brief      Verify that library Help Renders Guides Without Changing Planning Data
    /// @details    Exercises `keys.map`, `UserDefaults.standard.data`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks `XCTAssertEqual(keys.map {
    ///             UserDefaults.standard.data(forKey: $0) }, before)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLibraryHelpRendersGuidesWithoutChangingPlanningData() async throws {
        let keys = [DailyPlanStore.key, WeeklyReviewStore.key, PeriodicReviewStore.key, PlanningCalendarStore.key, "Plenact.PersonalCollections.v1"]
        let before = keys.map { UserDefaults.standard.data(forKey: $0) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let article = try XCTUnwrap(PlenactHelpCatalog.articles.first { $0.id == "rhythm" })
        let views: [AnyView] = [AnyView(NavigationStack { List { LibraryHelpRows(query: "") } }), AnyView(PlenactHelpArticleView(article: article))]
        for (index, view) in views.enumerated() {
            let host = UIHostingController(rootView: view)
            window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-help-\(index).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("HELP_RENDER=\(url.path)")
        }
        XCTAssertEqual(keys.map { UserDefaults.standard.data(forKey: $0) }, before)
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
    func testPeriodicReviewCarriesObjectivesWithoutRewritingPriorCheckpoints() throws {
        let name = "PlenactTests.Periodic." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!


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
        func date(_ key: String) -> Date { PlanningDate.date(key, calendar: calendar)! }
        var prior = PeriodicReviewRecord(title: "First quarter", start: date("2026-01-01"), end: date("2026-03-31"), calendar: calendar)
        prior.objectives = [ReviewObjective(title: "Build a sustainable routine", progress: "Found a useful morning rhythm", nextStep: "Protect time to reflect")]
        let saved = try PeriodicReviewStore.save(prior, replacing: nil, to: defaults)
        let document = try PeriodicReviewStore.load(from: defaults)
        let inherited = try XCTUnwrap(PeriodicReviewStore.previous(before: "2026-04-01", in: document))
        var next = PeriodicReviewRecord(title: "Second quarter", start: date("2026-04-01"), end: date("2026-06-30"), calendar: calendar, previous: inherited)
        XCTAssertEqual(next.startingObjectives, saved.objectives)
        XCTAssertEqual(next.objectives[0].id, saved.objectives[0].id)
        XCTAssertEqual(next.objectives[0].progress, "")
        next.objectives[0].status = .achieved; next.step = 2; next.completedAt = .now
        let nextSaved = try PeriodicReviewStore.save(next, replacing: nil, to: defaults)
        XCTAssertEqual(try PeriodicReviewStore.load(from: defaults).records[saved.id.uuidString], saved)
        XCTAssertEqual(try PeriodicReviewStore.load(from: defaults).records[next.id.uuidString], nextSaved)
        XCTAssertThrowsError(try PeriodicReviewStore.save(next, replacing: nil, to: defaults))
        XCTAssertNil(PeriodicReviewStore.previous(before: "2026-01-01", in: document))
        var invalid = nextSaved; invalid.title = " "
        let bytes = defaults.data(forKey: PeriodicReviewStore.key)
        XCTAssertThrowsError(try PeriodicReviewStore.save(invalid, replacing: nextSaved, to: defaults))
        XCTAssertEqual(defaults.data(forKey: PeriodicReviewStore.key), bytes)
        var weeks = WeeklyReviewStore.Document()
        let overlap = WeeklyReviewRecord(date: date("2026-03-30"), calendar: calendar)
        let outside = WeeklyReviewRecord(date: date("2026-07-12"), calendar: calendar)
        weeks.records[overlap.id] = overlap; weeks.records[outside.id] = outside
        XCTAssertEqual(next.weeks(in: weeks).map(\.id), [overlap.id])
        defaults.set(Data("corrupt".utf8), forKey: PeriodicReviewStore.key)
        XCTAssertThrowsError(try PeriodicReviewStore.load(from: defaults))
        XCTAssertEqual(defaults.data(forKey: PeriodicReviewStore.key), Data("corrupt".utf8))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPeriodicReviewRendersSetupAndAllStepsWithoutWriting
    /// @brief      Verify that periodic Review Renders Setup And All Steps Without Writing
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(defaults.data(forKey:
    ///             PeriodicReviewStore.key), bytes)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPeriodicReviewRendersSetupAndAllStepsWithoutWriting() async throws {
        let name = "PlenactTests.PeriodicRender." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        var baseline: PeriodicReviewRecord?
        for step in -1...2 {
            if step >= 0 {
                var record = baseline ?? PeriodicReviewRecord(title: "A meaningful quarter", start: .now, end: .now, calendar: .current)
                record.step = step
                if record.objectives.isEmpty { record.objectives = [ReviewObjective(title: "Build a sustainable routine")] }
                baseline = try PeriodicReviewStore.save(record, replacing: baseline, to: defaults)
            }
            let bytes = defaults.data(forKey: PeriodicReviewStore.key)
            let host = UIHostingController(rootView: PeriodicReviewView(calendar: .current, defaults: defaults, initialReviewID: step < 0 ? nil : baseline?.id))
            window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-periodic-\(step).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("PERIODIC_RENDER=\(url.path)")
            XCTAssertEqual(defaults.data(forKey: PeriodicReviewStore.key), bytes)
        }
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
    func testReviewRhythmDefaultsTimingAndIndependentNotifications() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago")); calendar.firstWeekday = 2


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
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        var preferences = ReviewRhythmPreferences()
        XCTAssertTrue(preferences.dailyInvitations); XCTAssertTrue(preferences.weeklyInvitations)
        XCTAssertFalse(preferences.dailyNotifications); XCTAssertFalse(preferences.weeklyNotifications)
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
        func due(_ kind: ReviewRhythmKind, _ now: Date, completed: Bool = false, deferred: Date? = nil) -> Bool {
            ReviewRhythmStore.isDue(kind, now: now, preferences: preferences, calendar: calendar, completed: completed, deferredUntil: deferred)
        }
        XCTAssertFalse(due(.daily, date(19, 20, 29)))
        XCTAssertTrue(due(.daily, date(19, 20, 30)))
        XCTAssertFalse(due(.daily, date(19, 21), completed: true))
        XCTAssertFalse(due(.daily, date(19, 21), deferred: date(19, 22)))
        XCTAssertTrue(due(.daily, date(19, 22), deferred: date(19, 22)))
        XCTAssertFalse(due(.weekly, date(18, 17, 59)))
        XCTAssertTrue(due(.weekly, date(18, 18)))
        XCTAssertFalse(due(.weekly, date(19, 18)), "No pile of missed Sunday invitations on Monday")
        XCTAssertNotEqual(ReviewRhythmStore.periodID(.daily, date: date(19, 21), calendar: calendar),
            ReviewRhythmStore.periodID(.daily, date: date(20, 21), calendar: calendar))
        preferences.dailyInvitations = false; preferences.dailyNotifications = true
        XCTAssertFalse(due(.daily, date(19, 21)))
        XCTAssertEqual(ReviewRhythmStore.notificationRequests(preferences).count, 1)
        preferences.dailyMinutes = -2; preferences.weeklyMinutes = 9999; preferences.weeklyWeekday = 0
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
    func testReviewRhythmNotificationRequestsAreStableLocalAndContainOnlyReviewRoutes() throws {
        var preferences = ReviewRhythmPreferences()
        preferences.dailyNotifications = true; preferences.weeklyNotifications = true
        preferences.dailyMinutes = 21 * 60 + 15; preferences.weeklyMinutes = 17 * 60 + 45; preferences.weeklyWeekday = 7
        let requests = ReviewRhythmStore.notificationRequests(preferences)
        XCTAssertEqual(Set(requests.map(\.identifier)), Set(ReviewRhythmKind.allCases.map(\.notificationID)))
        let daily = try XCTUnwrap(requests.first { $0.identifier == ReviewRhythmKind.daily.notificationID })
        let weekly = try XCTUnwrap(requests.first { $0.identifier == ReviewRhythmKind.weekly.notificationID })
        let dailyTrigger = try XCTUnwrap(daily.trigger as? UNCalendarNotificationTrigger)
        let weeklyTrigger = try XCTUnwrap(weekly.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(dailyTrigger.repeats); XCTAssertTrue(weeklyTrigger.repeats)
        XCTAssertEqual(dailyTrigger.dateComponents.hour, 21); XCTAssertEqual(dailyTrigger.dateComponents.minute, 15)
        XCTAssertNil(dailyTrigger.dateComponents.weekday); XCTAssertNil(dailyTrigger.dateComponents.timeZone)
        XCTAssertEqual(weeklyTrigger.dateComponents.weekday, 7)
        XCTAssertEqual(weeklyTrigger.dateComponents.hour, 17); XCTAssertEqual(weeklyTrigger.dateComponents.minute, 45)
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
    func testReviewRhythmSaveSkipAndSnoozeAreLocalAndPreserveCorruptSettings() throws {
        let suite = "ReviewRhythmTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ReviewRhythmStore.load(from: defaults), ReviewRhythmPreferences())
        XCTAssertNil(defaults.object(forKey: ReviewRhythmStore.key))
        var settings = ReviewRhythmPreferences(); settings.dailyMinutes = 19 * 60; settings.weeklyWeekday = 6
        try ReviewRhythmStore.save(settings, to: defaults)
        XCTAssertEqual(ReviewRhythmStore.load(from: defaults), settings)
        let calendar = Calendar.current
        let now = Date()
        ReviewRhythmStore.deferInvitation(.daily, date: now, calendar: calendar, until: now.addingTimeInterval(3600), defaults: defaults)
        ReviewRhythmStore.deferInvitation(.weekly, date: now, calendar: calendar, until: .distantFuture, defaults: defaults)
        let values = try JSONDecoder().decode([String: Date].self, from: XCTUnwrap(defaults.data(forKey: ReviewRhythmStore.dismissalsKey)))
        XCTAssertEqual(values[ReviewRhythmStore.periodID(.daily, date: now, calendar: calendar)], now.addingTimeInterval(3600))
        XCTAssertEqual(values[ReviewRhythmStore.periodID(.weekly, date: now, calendar: calendar)], .distantFuture)
        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        XCTAssertNil(defaults.object(forKey: WeeklyReviewStore.key))
        defaults.set(Data("future or broken".utf8), forKey: ReviewRhythmStore.key)
        XCTAssertThrowsError(try ReviewRhythmStore.save(settings, to: defaults))
        XCTAssertEqual(defaults.data(forKey: ReviewRhythmStore.key), Data("future or broken".utf8))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testKeepTomorrowDecisionPersistsWithoutCopyingOrRetimingTheTableItem
    /// @brief      Verify that keep Tomorrow Decision Persists Without Copying Or Retiming The Table Item
    /// @details    Exercises `DatedPlanningWeek.make`, `.now.addingTimeInterval`, `TodayReviewSelection.items`.
    ///             Checks `XCTAssertEqual(restored.eveningReview?.decisions.first?.action, .keepTomorrow)`;
    ///             `XCTAssertTrue(TodayReviewSelection.pending(items, review: restored.eveningReview).isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testKeepTomorrowDecisionPersistsWithoutCopyingOrRetimingTheTableItem() throws {
        let suite = "ReviewCarryTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let week = DatedPlanningWeek.make(for: .now)
        var table = PersonalCollection(title: "On the Table", kind: .list)
        var card = KanbanCard(id: 0, word: "Go to the grocery store", listTitle: table.title, checklists: [], createdAt: .now)
        card.dueDate = .now.addingTimeInterval(-3600)
        table.lists[0].cards = [card]
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [table],
            saveWeek: { _ in XCTFail("Keep must not save/move the source"); return false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in },
            saveLibrary: { _ in XCTFail("Keep must not save/move the source"); return false })
        var plan = DailyPlan(date: .now)
        let items = TodayReviewSelection.items(plan: plan, date: .now, access: access, referenceLabelIDs: [], calendar: .current)
        let source = DailyPlanPriority(try XCTUnwrap(items.first))
        var review = DailyEveningReview()
        review.decisions = [DailyReviewDecision(source: source, result: source, action: .keepTomorrow)]
        plan.eveningReview = review
        try DailyReviewTransaction.perform(in: defaults) { _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults) }
        let restored = try XCTUnwrap(DailyPlanStore.load(from: defaults).plans[plan.id])
        XCTAssertEqual(restored.eveningReview?.decisions.first?.action, .keepTomorrow)
        XCTAssertTrue(TodayReviewSelection.pending(items, review: restored.eveningReview).isEmpty)
        XCTAssertEqual(TodayReviewSelection.pending(items, review: nil).count, 1, "Tomorrow gets a fresh decision")
        XCTAssertEqual(access.library[0], table)
        XCTAssertEqual(access.library[0].lists[0].cards[0].dueDate, card.dueDate)
        XCTAssertEqual(try JSONDecoder().decode(DailyReviewAction.self, from: JSONEncoder().encode(DailyReviewAction.table)), .table)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReviewRhythmInvitationsAndSettingsRenderWithoutWritingOrRequestingPermission
    /// @brief      Verify that review Rhythm Invitations And Settings Render Without Writing Or Requesting Permission
    /// @details    Exercises `Calendar.current.component`, `ReviewRhythmStore.save`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks `XCTAssertEqual(defaults.data(forKey:
    ///             ReviewRhythmStore.key), bytes)`; `XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testReviewRhythmInvitationsAndSettingsRenderWithoutWritingOrRequestingPermission() async throws {
        let suite = "ReviewRhythmRender." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = ReviewRhythmPreferences(); preferences.dailyMinutes = 0; preferences.weeklyMinutes = 0
        preferences.weeklyWeekday = Calendar.current.component(.weekday, from: .now)
        try ReviewRhythmStore.save(preferences, to: defaults)
        let bytes = defaults.data(forKey: ReviewRhythmStore.key)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for scheme in [ColorScheme.light, .dark] {
            let view = ScrollView {
                ReviewRhythmPanel(onOpen: { _ in XCTFail("Rendering must not open") }, onSettings: {}, defaults: defaults)
                    .padding(20)
            }.background(Color(.systemGroupedBackground)).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-review-rhythm-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: url); print("REVIEW_RHYTHM_RENDER=" + url.path)
        }
        window.rootViewController = UIHostingController(rootView: ReviewRhythmSettingsView())
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(defaults.data(forKey: ReviewRhythmStore.key), bytes)
        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        XCTAssertNil(defaults.object(forKey: WeeklyReviewStore.key))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeeklyReviewCalendarBoundariesPersistenceAndRecovery
    /// @brief      Verify that weekly Review Calendar Boundaries Persistence And Recovery
    /// @details    Exercises `DailyPlanStore.Document`, `PlanningDate.date`, `review.dailyPlans(in: days).map`.
    ///             Checks `XCTAssertEqual(review.startKey, "2026-10-12")`; `XCTAssertEqual(review.dailyPlans(in:
    ///             days).map(\.id), ["2026-10-12", "2026-10-18"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testWeeklyReviewCalendarBoundariesPersistenceAndRecovery() throws {
        let name = "PlenactTests.Weekly." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!; calendar.firstWeekday = 2
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18))!
        var review = WeeklyReviewRecord(date: date, calendar: calendar)
        XCTAssertEqual(review.startKey, "2026-10-12")
        var days = DailyPlanStore.Document()
        for key in ["2026-10-11", "2026-10-12", "2026-10-18", "2026-10-19"] {
            let day = DailyPlan(date: PlanningDate.date(key, calendar: calendar)!, calendar: calendar)
            days.plans[key] = day
        }
        XCTAssertEqual(review.dailyPlans(in: days).map(\.id), ["2026-10-12", "2026-10-18"])
        review.highlights = "Made room for important work"; review.step = 2
        let saved = try WeeklyReviewStore.save(review, replacing: nil, to: defaults)
        var other = WeeklyReviewRecord(date: calendar.date(byAdding: .day, value: 7, to: date)!, calendar: calendar)
        other.direction = "A calmer week"
        _ = try WeeklyReviewStore.save(other, replacing: nil, to: defaults)
        XCTAssertEqual(try WeeklyReviewStore.load(from: defaults).records.count, 2)
        XCTAssertEqual(try WeeklyReviewStore.load(from: defaults).records[saved.id], saved)
        XCTAssertThrowsError(try WeeklyReviewStore.save(review, replacing: nil, to: defaults))
        let before = defaults.data(forKey: WeeklyReviewStore.key)
        _ = try DailyReviewTransaction.begin(in: defaults)
        defaults.removeObject(forKey: WeeklyReviewStore.key)
        try DailyReviewTransaction.recover(in: defaults)
        XCTAssertEqual(defaults.data(forKey: WeeklyReviewStore.key), before)
        defaults.set(Data("broken".utf8), forKey: WeeklyReviewStore.key)
        XCTAssertThrowsError(try WeeklyReviewStore.load(from: defaults))
        XCTAssertEqual(defaults.data(forKey: WeeklyReviewStore.key), Data("broken".utf8))
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
    func testWeeklyReviewRendersAllStepsAndPreservesSavedRecord() async throws {
        let name = "PlenactTests.WeeklyRender." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        var baseline: WeeklyReviewRecord?
        for step in 0...2 {
            var record = baseline ?? WeeklyReviewRecord(date: .now, calendar: .current)
            record.step = step
            baseline = try WeeklyReviewStore.save(record, replacing: baseline, to: defaults)
            let bytes = defaults.data(forKey: WeeklyReviewStore.key)
            let host = UIHostingController(rootView: WeeklyReviewView(calendar: .current, defaults: defaults))
            window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-weekly-\(step).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("WEEKLY_RENDER=\(url.path)")
            XCTAssertEqual(defaults.data(forKey: WeeklyReviewStore.key), bytes)
        }
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
    func testCheckInMoodsRoundTripWithoutCarryingForwardOrChangingOlderEntries() throws {
        let name = "PlenactTests.Moods." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var plan = DailyPlan(date: .now)
        plan.recordCheckIn(changed: "Before moods existed", sources: [])
        let old = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        let bytes = try XCTUnwrap(defaults.data(forKey: DailyPlanStore.key))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("\"mood\""))
        XCTAssertNil(try DailyPlanStore.load(from: defaults).plans[plan.id]?.checkInHistory.first?.mood)
        let custom = try XCTUnwrap(CheckInMood.custom(emoji: " 🌤️ ", label: " Quietly hopeful "))
        XCTAssertEqual(custom.label, "Quietly hopeful")
        XCTAssertEqual(custom.emoji, "🌤️")
        for choice in CheckInMoodChoice.allCases where choice.mood != nil {
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
    /// @fcn        PlenactBoardDocumentTests.testCustomMoodRequiresOneEmojiAndMeaningfulShortText
    /// @brief      Verify that custom Mood Requires One Emoji And Meaningful Short Text
    /// @details    Exercises `CheckInMood.custom`. Checks `XCTAssertNotNil(CheckInMood.custom(emoji: emoji, label:
    ///             "Feeling focused"), emoji)`; `XCTAssertNil(CheckInMood.custom(emoji: emoji, label: "Focused"),
    ///             emoji)`.
    ///
    /// @return     (Void) no return value
    ///
    func testCustomMoodRequiresOneEmojiAndMeaningfulShortText() {
        for emoji in ["🌤️", "👩🏽‍💻", "🇺🇸", "❤️", "🫶🏽", "😊"] {
            XCTAssertNotNil(CheckInMood.custom(emoji: emoji, label: "Feeling focused"), emoji)
        }
        for emoji in ["", "  ", "a", "1", "😊😊", "hello"] {
            XCTAssertNil(CheckInMood.custom(emoji: emoji, label: "Focused"), emoji)
        }
        XCTAssertNil(CheckInMood.custom(emoji: "😊", label: "  "))
        XCTAssertNil(CheckInMood.custom(emoji: "😊", label: String(repeating: "a", count: 41)))
        XCTAssertNotNil(CheckInMood.custom(emoji: "😊", label: String(repeating: "a", count: 40)))
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
    func testCheckInHistoryRetainsLegacySnapshotsAndOtherDays() throws {
        let name = "PlenactTests.CheckInHistory." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
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
        var stale = second; stale.recordCheckIn(changed: "Stale", sources: [])
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
    func testCheckInSnapshotsDoNotFollowLaterCompletionOrPlanEdits() throws {
        var table = PersonalCollection(title: "On the Table", kind: .list)
        table.lists[0].cards = [KanbanCard(id: 0, word: "Make a useful start", listTitle: table.title, checklists: [])]
        let week = DatedPlanningWeek.make(for: .now)
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [table], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
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
        var card = old.card; card.isTitleChecked = true; card.word = "Renamed after finishing"
        sources[0] = PlanningSearchResult(weekKey: old.weekKey, collectionID: old.collectionID, collectionTitle: old.collectionTitle, listID: old.listID, listTitle: old.listTitle, card: card)
        plan.intention = "Now rest"
        plan.recordCheckIn(changed: "Finished", sources: sources)
        XCTAssertEqual(plan.checkInHistory[0], first)
        XCTAssertEqual(first.priorities.first?.title, "Make a useful start")
        XCTAssertEqual(plan.checkInHistory[1].completedTasks, 1)
        XCTAssertNil(plan.checkInHistory[1].focus)
        XCTAssertNil(plan.checkIn?.focus)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDailyHistoryRendersCurrentPastAndEmptyDaysWithoutWriting
    /// @brief      Verify that daily History Renders Current Past And Empty Days Without Writing
    /// @details    Exercises `plan.recordCheckIn`, `date.addingTimeInterval`, `CheckInMood.custom`. Checks
    ///             `XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), bytes)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDailyHistoryRendersCurrentPastAndEmptyDaysWithoutWriting() async throws {
        let name = "PlenactTests.DailyHistoryRender." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let calendar = Calendar.current
        let today = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let missing = calendar.date(byAdding: .day, value: -2, to: today)!
        for date in [today, yesterday] {
            var plan = DailyPlan(date: date)
            plan.intention = "Leave room for real life"
            plan.recordCheckIn(changed: "A useful start", sources: [], at: date, mood: CheckInMoodChoice.good.mood)
            plan.recordCheckIn(changed: "Adjusted my plan", sources: [], at: date.addingTimeInterval(60), mood: CheckInMood.custom(emoji: "🌤️", label: "Quietly hopeful"))
            _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        }
        let bytes = defaults.data(forKey: DailyPlanStore.key)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for (index, date) in [today, yesterday, missing].enumerated() {
            let host = UIHostingController(rootView: DailyHistoryReviewView(date: date, calendar: calendar, defaults: defaults))
            window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: 744, height: 1133); window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-daily-history-\(index).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("DAILY_HISTORY_RENDER=\(url.path)")
            XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), bytes)
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
    func testCheckInPersistsSharedPlanAndTracksLiveProgressWithoutCountingNotes() throws {
        let name = "PlenactTests.CheckIn." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var table = PersonalCollection(title: "On the Table", kind: .list)
        table.lists[0].cards = [
            KanbanCard(id: 0, word: "Next task", listTitle: table.title, checklists: []),
            KanbanCard(id: 1, word: "Finished", listTitle: table.title, isTitleChecked: true, checklists: []),
            KanbanCard(id: 2, word: "Context", listTitle: table.title, checklists: [], presentation: .note)
        ]
        let week = DatedPlanningWeek.make(for: .now)
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [table], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let sources = access.searchableItems
        var plan = DailyPlan(date: .now)
        plan.priorities = sources.map(DailyPlanPriority.init)
        plan.visionCompletedAt = .now; plan.eveningReview = DailyEveningReview()
        let initial = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        XCTAssertNil(try DailyPlanStore.load(from: defaults).plans[plan.id]?.checkIn)
        let next = try XCTUnwrap(plan.priorities.first { $0.title == "Next task" })
        plan.checkIn = DailyCheckIn(focus: next, changed: "Less time available", savedAt: .now)
        plan.constraints = "Only one hour"
        let saved = try DailyPlanStore.save(plan, replacing: initial, to: defaults)
        let restored = try XCTUnwrap(DailyPlanStore.load(from: defaults).plans[plan.id])
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(restored.visionCompletedAt, initial.visionCompletedAt)
        XCTAssertEqual(restored.eveningReview, initial.eveningReview)
        let counts = DailyCheckInProgress.counts(plan: restored, sources: sources)
        XCTAssertEqual(counts.tasks, 2); XCTAssertEqual(counts.completed, 1); XCTAssertEqual(counts.notes, 1)
        XCTAssertEqual(DailyCheckInProgress.focus(plan: restored, sources: sources), next)
        var removed = restored; removed.priorities.removeAll { $0.id == next.id }
        XCTAssertNil(DailyCheckInProgress.focus(plan: removed, sources: sources))
        XCTAssertNil(DailyCheckInProgress.focus(plan: restored, sources: []))
        var completed = sources
        let index = try XCTUnwrap(completed.firstIndex { $0.card.word == "Next task" })
        var card = completed[index].card; card.isTitleChecked = true
        let old = completed[index]
        completed[index] = PlanningSearchResult(weekKey: old.weekKey, collectionID: old.collectionID, collectionTitle: old.collectionTitle, listID: old.listID, listTitle: old.listTitle, card: card)
        XCTAssertNil(DailyCheckInProgress.focus(plan: restored, sources: completed))
        XCTAssertEqual(DailyCheckInProgress.counts(plan: restored, sources: completed).completed, 2)
        XCTAssertEqual(access.library[0], table)
        XCTAssertThrowsError(try DailyPlanStore.save(plan, replacing: initial, to: defaults))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCheckInRendersWithoutSavingOrChangingSources
    /// @brief      Verify that check In Renders Without Saving Or Changing Sources
    /// @details    Exercises `DatedPlanningWeek.make`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertEqual(saves, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCheckInRendersWithoutSavingOrChangingSources() async throws {
        let week = DatedPlanningWeek.make(for: .now)
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        var saves = 0
        let host = UIHostingController(rootView: TodayCheckInView(plan: .constant(DailyPlan(date: .now)), date: .now, onSave: { saves += 1; return true }).environment(\.planningCalendarAccess, access))
        window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-checkin.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("CHECKIN_RENDER=\(url.path)")
        XCTAssertEqual(saves, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEveningReviewTransactionRecoversInterruptedAndFailedWrites
    /// @brief      Verify that evening Review Transaction Recovers Interrupted And Failed Writes
    /// @details    Exercises `DailyReviewTransaction.perform`, `DailyReviewTransaction.begin`,
    ///             `DailyReviewTransaction.recover`. Checks `XCTAssertEqual(defaults.data(forKey: key),
    ///             Data(key.utf8))`; `XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `Forced.failure`. Errors from throwing dependencies propagate unless
    ///             handled within this operation.
    ///
    @MainActor
    func testEveningReviewTransactionRecoversInterruptedAndFailedWrites() throws {
        let name = "PlenactTests.Review." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for key in DailyReviewTransaction.keys { defaults.set(Data(key.utf8), forKey: key) }
        defaults.removeObject(forKey: DailyPlanStore.key)
        enum Forced: Error { case failure }
        XCTAssertThrowsError(try DailyReviewTransaction.perform(in: defaults) {
            for key in DailyReviewTransaction.keys { defaults.set("changed", forKey: key) }
            throw Forced.failure
        })
        for key in DailyReviewTransaction.keys where key != DailyPlanStore.key { XCTAssertEqual(defaults.data(forKey: key), Data(key.utf8)) }
        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        _ = try DailyReviewTransaction.begin(in: defaults)
        defaults.set("interrupted", forKey: DailyPlanStore.key)
        try DailyReviewTransaction.recover(in: defaults)
        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        try DailyReviewTransaction.perform(in: defaults) { defaults.set("committed", forKey: DailyPlanStore.key) }
        XCTAssertEqual(defaults.string(forKey: DailyPlanStore.key), "committed")
        XCTAssertNil(defaults.object(forKey: DailyReviewTransaction.key))
        let corrupt = Data("invalid journal".utf8)
        defaults.set(corrupt, forKey: DailyReviewTransaction.key)
        XCTAssertThrowsError(try DailyReviewTransaction.recover(in: defaults))
        XCTAssertEqual(defaults.data(forKey: DailyReviewTransaction.key), corrupt)
        XCTAssertEqual(defaults.string(forKey: DailyPlanStore.key), "committed")
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
    func testEveningReviewPersistsReflectionAndSkipsDecidedAndReferenceItems() throws {
        let name = "PlenactTests.Evening." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let week = DatedPlanningWeek.make(for: .now)
        var table = PersonalCollection(title: "On the Table", kind: .list)
        table.lists[0].cards = [
            KanbanCard(id: 0, word: "Keep", listTitle: table.title, checklists: []),
            KanbanCard(id: 1, word: "Reference", listTitle: table.title, checklists: [], labelIDs: ["reference"]),
            KanbanCard(id: 2, word: "Finished", listTitle: table.title, isTitleChecked: true, checklists: [])
        ]
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [table], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        var plan = DailyPlan(date: .now)
        let legacy = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        XCTAssertNil(try DailyPlanStore.load(from: defaults).plans[plan.id]?.eveningReview)
        let items = TodayReviewSelection.items(plan: plan, date: .now, access: access, referenceLabelIDs: ["reference"], calendar: .current)
        XCTAssertEqual(Set(items.map { $0.card.word }), ["Keep", "Finished"])
        let keep = DailyPlanPriority(try XCTUnwrap(items.first { $0.card.word == "Keep" }))
        var review = DailyEveningReview()
        review.step = 2; review.helped = "A small step"; review.tomorrow = "Begin gently"
        review.decisions = [DailyReviewDecision(source: keep, result: keep, action: .keep)]
        plan.eveningReview = review
        let saved = try DailyPlanStore.save(plan, replacing: legacy, to: defaults)
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans[plan.id]?.eveningReview, review)
        XCTAssertTrue(TodayReviewSelection.pending(items, review: review).isEmpty)
        XCTAssertEqual(access.library[0].lists[0].cards.count, 3, "Leaving in place does not delete source content")
        var invalid = saved; invalid.eveningReview?.step = 8
        _ = try DailyPlanStore.save(invalid, replacing: saved, to: defaults)
        XCTAssertThrowsError(try DailyPlanStore.load(from: defaults))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEveningReviewRendersAllStepsWithoutSaving
    /// @brief      Verify that evening Review Renders All Steps Without Saving
    /// @details    Exercises `DatedPlanningWeek.make`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertEqual(saves, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testEveningReviewRendersAllStepsWithoutSaving() async throws {
        let week = DatedPlanningWeek.make(for: .now)
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        var saves = 0
        for step in 0...2 {
            var plan = DailyPlan(date: .now)
            plan.eveningReview = DailyEveningReview(); plan.eveningReview?.step = step
            let host = UIHostingController(rootView: TodayReviewView(plan: .constant(plan), date: .now, baseline: nil, onSave: { saves += 1; return true }, onCommitted: { _ in saves += 1 }).environment(\.planningCalendarAccess, access))
            window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-review-step-\(step).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("REVIEW_RENDER=\(url.path)")
        }
        XCTAssertEqual(saves, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayVisionRendersMorningAndRealityStepsWithoutSaving
    /// @brief      Verify that today Vision Renders Morning And Reality Steps Without Saving
    /// @details    Exercises `DatedPlanningWeek.make`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertEqual(saves, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayVisionRendersMorningAndRealityStepsWithoutSaving() async throws {
        let week = DatedPlanningWeek.make(for: .now)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        let access = PlanningCalendarAccess(document: document, library: [], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        var saves = 0
        for step in [0, 2] {
            var plan = DailyPlan(date: .now); plan.visionStep = step
            plan.intention = "One useful step"
            let host = UIHostingController(rootView: TodayVisionView(plan: .constant(plan), date: .now, onSave: { saves += 1; return true }).environment(\.planningCalendarAccess, access))
            window.rootViewController = host
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-vision-step-\(step).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("VISION_RENDER=\(url.path)")
        }
        XCTAssertEqual(saves, 0, "Opening a morning review must not save or move anything")
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
    func testTodayVisionCandidatesUseRealDatesAndExcludeReferenceAndCompletedItems() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let listID = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date, calendar: calendar)])
        let index = try XCTUnwrap(week.collection.lists.firstIndex { $0.id == listID })
        week.collection.lists[index].cards = [
            KanbanCard(id: 0, word: "Day priority", listTitle: "Renamed day", checklists: []),
            KanbanCard(id: 1, word: "Reference", listTitle: "Renamed day", checklists: [], labelIDs: ["reference"]),
            KanbanCard(id: 2, word: "Already finished", listTitle: "Renamed day", isTitleChecked: true, checklists: [])
        ]
        var scheduled = PersonalCollection(title: "Scheduled", kind: .list)
        scheduled.lists[0].cards = [
            KanbanCard(id: 0, word: "Due today", listTitle: scheduled.title, dueDate: date, checklists: []),
            KanbanCard(id: 1, word: "Undated", listTitle: scheduled.title, checklists: []),
            KanbanCard(id: 2, word: "Tomorrow", listTitle: scheduled.title, dueDate: calendar.date(byAdding: .day, value: 1, to: date), checklists: []),
            KanbanCard(id: 3, word: "Spans today", listTitle: scheduled.title, startDate: calendar.date(byAdding: .day, value: -1, to: date), dueDate: calendar.date(byAdding: .day, value: 1, to: date), checklists: [])
        ]
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        let access = PlanningCalendarAccess(document: document, library: [scheduled], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let found = TodayVisionSelection.candidates(date: date, access: access, referenceLabelIDs: ["reference"], calendar: calendar)
        XCTAssertEqual(Set(found.map { $0.card.word }), ["Day priority", "Due today", "Spans today"])
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
    func testTodayVisionProgressResumesAndLegacyDailyPlansStayCompatible() throws {
        let name = "PlenactTests.Vision." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let plan = DailyPlan(date: .now)
        let saved = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: DailyPlanStore.key))) as? [String: Any])
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
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans[plan.id]?.visionCompletedAt, complete.visionCompletedAt)
        XCTAssertThrowsError(try DailyPlanStore.save(saved, replacing: legacy, to: defaults))
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
    func testMorningTransferPreservesDetailsAndReturnsOneNewDestinationIdentity() throws {
        var source = PersonalCollection(title: "Scheduled", kind: .list)
        var table = PersonalCollection(title: "On the Table", kind: .list)
        let card = KanbanCard(id: 7, word: "Scheduled work", listTitle: source.title, startDate: Date(timeIntervalSince1970: 100), dueDate: Date(timeIntervalSince1970: 200), checklists: [KanbanChecklist(title: "Steps", items: ["One", "Two"])], descriptionOverride: "Keep my details", presentation: .note, createdAt: Date(timeIntervalSince1970: 50), startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
        source.lists[0].cards = [card]
        table.lists[0].cards = [KanbanCard(id: 7, word: "Already here", listTitle: table.title)]
        let before = Set(table.lists[0].cards.map(\.id))
        var collections = [source, table]
        var week: [KanbanList] = []
        var saved = Set<Int>()
        let destination = CardMoveDestination(collectionID: table.id, listID: 0, title: table.title, group: "Plans")
        try CrossBoardCardMovement.move(card, from: source.id, to: destination, week: &week, collections: &collections, saved: &saved)
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        let moved = try XCTUnwrap(collections[1].lists[0].cards.first { !before.contains($0.id) && $0.createdAt == card.createdAt })
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
    func testAddingDailyPrioritySavesCanonicalCardOrNoteAndRejectsFailedDestinations() throws {
        let week = DatedPlanningWeek.make(for: .now)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        var owner = PersonalCollection(title: "On the Table", kind: .list)
        owner.lists[0].archivedCards = [KanbanCard(id: 90, word: "Archived", listTitle: owner.title)]
        let target = WorkspaceListReference(ownerID: owner.id, listID: owner.lists[0].id)
        let link = KanbanAttachment(url: URL(string: "https://example.com/priority"), mediaKind: .link)
        for kind in [ItemPresentation.card, .note] {
            var savedOwner: PersonalCollection?
            let access = PlanningCalendarAccess(document: document, library: [owner], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { savedOwner = $0; return true })
            let source = try XCTUnwrap(DailyPriorityCreation.create(title: "  New priority  ", body: "Useful context", presentation: kind, destination: target, access: access, attachments: [link]))
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
            XCTAssertNil(DailyPriorityCreation.create(title: " ", body: "", presentation: kind, destination: target, access: access))
        }
        let failed = PlanningCalendarAccess(document: document, library: [owner], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        XCTAssertNil(DailyPriorityCreation.create(title: "Keep draft", body: "", presentation: .card, destination: target, access: failed))
        let missing = WorkspaceListReference(ownerID: UUID(), listID: target.listID)
        XCTAssertNil(DailyPriorityCreation.create(title: "Missing", body: "", presentation: .card, destination: missing, access: failed))
        var savedWeek: DatedPlanningWeek?
        let access = PlanningCalendarAccess(document: document, library: [], saveWeek: { savedWeek = $0; return true }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let datedTarget = WorkspaceListReference(ownerID: week.id, listID: week.collection.lists[0].id)
        let dated = try XCTUnwrap(DailyPriorityCreation.create(title: "Day priority", body: "", presentation: .card, destination: datedTarget, access: access))
        XCTAssertEqual(savedWeek?.collection.lists[0].cards.first, dated.card)
        XCTAssertEqual(dated.weekKey, week.startKey)
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
    func testDailyPlanRoundTripsAndPreservesOtherDaysAndConflictingEdits() throws {
        let name = "PlenactTests.DailyPlan." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
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
        var update = saved; update.intention = "A revised intention"
        let revised = try DailyPlanStore.save(update, replacing: saved, to: defaults)
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans.count, 2)
        XCTAssertThrowsError(try DailyPlanStore.save(first, replacing: saved, to: defaults))
        XCTAssertEqual(try DailyPlanStore.load(from: defaults).plans[first.id], revised)
        for offset in [-220, -1, 0, 1, 80] {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            XCTAssertEqual(DailyPlan(date: date, calendar: calendar).id, PlanningDate.key(date, calendar: calendar))
        }
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
    func testDailyPlanPreservesUnreadableAndUnsupportedStoredData() throws {
        let name = "PlenactTests.DailyPlan." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for bytes in [Data("broken".utf8), Data(#"{"version":99,"plans":{}}"#.utf8)] {
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
    /// @fcn        PlenactBoardDocumentTests.testDailyPlanPrioritiesResolveLiveOwnerAndWithinBoardMovesWithoutCopyingCards
    /// @brief      Verify that daily Plan Priorities Resolve Live Owner And Within Board Moves Without Copying Cards
    /// @details    Exercises `reference.resolve`. Checks `XCTAssertEqual(reference.title, card.word)`;
    ///             `XCTAssertNil(reference.resolve(in: []))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDailyPlanPrioritiesResolveLiveOwnerAndWithinBoardMovesWithoutCopyingCards() throws {
        let first = UUID(), other = UUID()
        let card = KanbanCard(id: 5, word: "A useful priority", listTitle: "Before", createdAt: Date(timeIntervalSince1970: 123))
        let source = PlanningSearchResult(weekKey: nil, collectionID: first, collectionTitle: "Projects", listID: 1, listTitle: "Before", card: card)
        let reference = DailyPlanPriority(source)
        XCTAssertEqual(reference.title, card.word)
        XCTAssertNil(reference.resolve(in: []))
        let wrong = PlanningSearchResult(weekKey: nil, collectionID: other, collectionTitle: "Other", listID: 1, listTitle: "Before", card: card)
        XCTAssertNil(reference.resolve(in: [wrong]))
        var updated = card; updated.isTitleChecked = true
        let moved = PlanningSearchResult(weekKey: nil, collectionID: first, collectionTitle: "Projects", listID: 7, listTitle: "After", card: updated)
        XCTAssertEqual(reference.resolve(in: [wrong, moved])?.listID, 7)
        XCTAssertEqual(reference.resolve(in: [moved])?.card.isTitleChecked, true)
        XCTAssertFalse(card.isTitleChecked)
        let reused = KanbanCard(id: card.id, word: card.word, listTitle: card.listTitle, createdAt: Date(timeIntervalSince1970: 456))
        let replacement = PlanningSearchResult(weekKey: nil, collectionID: first, collectionTitle: "Projects", listID: 1, listTitle: "Before", card: reused)
        XCTAssertNil(reference.resolve(in: [replacement]))
        let decoded = try JSONDecoder().decode(DailyPlanPriority.self, from: JSONEncoder().encode(reference))
        XCTAssertEqual(decoded, reference)
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
    func testDailyPlanIsIncludedInExampleWorkspaceBackupAndRestore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "PlenactTests.DailyPlanBackup." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        let store = FullMonthExampleStore(root: folder.appendingPathComponent("Backup"), documents: folder.appendingPathComponent("Documents"), support: folder.appendingPathComponent("Support"), domainName: name)
        var plan = DailyPlan(date: .now); plan.intention = "My original plan"
        _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        let originalBytes = try XCTUnwrap(defaults.data(forKey: DailyPlanStore.key))
        var weekly = WeeklyReviewRecord(date: .now, calendar: .current); weekly.highlights = "Original weekly reflection"
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
    func testTodayPlanRendersSavedContextAndLivePrioritiesWithoutSourceMutations() async throws {
        let name = "PlenactTests.DailyPlanRender." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let week = DatedPlanningWeek.make(for: .now)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        var library = PersonalCollection(title: "On the Table", kind: .list)
        library.lists[0].cards = [KanbanCard(id: 42, word: "Finish one meaningful step", listTitle: library.title, isTitleChecked: true, checklists: [], descriptionOverride: "Keep a little room for the unexpected")]
        let access = PlanningCalendarAccess(document: document, library: [library], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        var plan = DailyPlan(date: .now)
        plan.priorities = access.searchableItems.map(DailyPlanPriority.init)
        plan.intention = "Small steps, with room to breathe"
        plan.constraints = "One focused hour before lunch"
        _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        let saved = defaults.data(forKey: DailyPlanStore.key)
        let originalSource = library
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TodayPlanView(defaults: defaults).environment(\.planningCalendarAccess, access))
        window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(180))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-today-plan-saved.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("DAILY_PLAN_RENDER=\(url.path)")
        XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), saved)
        XCTAssertEqual(access.library.first, originalSource)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFullMonthExampleCoversPastTodayAndSparseFuture
    /// @brief      Verify that full Month Example Covers Past Today And Sparse Future
    /// @details    Exercises `FullMonthExample.make`, `example.document.week`, `PlanningDate.key`. Checks
    ///             `XCTAssertEqual(example.document.firstWeekday, 2)`; `XCTAssertGreaterThanOrEqual(cards.count, 3)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFullMonthExampleCoversPastTodayAndSparseFuture() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let example = FullMonthExample.make(now: today, calendar: calendar)
        XCTAssertEqual(example.document.firstWeekday, 2)
        var futureCount = 0
        var ids = Set<Int>()
        for day in 1...31 {
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
            let week = try XCTUnwrap(example.document.week(for: date))
            let listID = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date, calendar: calendar)])
            let cards = try XCTUnwrap(week.collection.lists.first { $0.id == listID }).cards
            if day < 15 { XCTAssertGreaterThanOrEqual(cards.count, 3); XCTAssertTrue(cards.contains(where: \.isTitleChecked)) }
            if day == 15 { XCTAssertEqual(cards.count, 4) }
            if day > 15 { futureCount += cards.count; XCTAssertLessThanOrEqual(cards.count, 1) }
            for card in cards {
                XCTAssertTrue(ids.insert(card.id).inserted)
                if let due = card.dueDate { XCTAssertTrue(calendar.isDate(due, inSameDayAs: date)) }
            }
        }
        XCTAssertGreaterThan(futureCount, 0)
        XCTAssertLessThanOrEqual(futureCount, 5)
        XCTAssertEqual(Set(example.previewLists.map(\.id)).count, example.previewLists.count)
        for components in [(2028, 2, 29), (2026, 3, 8), (2026, 12, 31), (2027, 1, 1)] {
            let date = calendar.date(from: DateComponents(year: components.0, month: components.1, day: components.2))!
            let value = FullMonthExample.make(now: date, calendar: calendar)
            XCTAssertNotNil(value.document.week(for: date))
            XCTAssertEqual(value.document.weeks.first { $0.startKey == value.document.currentWeekKey }?.collection.lists.count, 7)
        }
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
    func testFullMonthBackupRestoresAllPreferencesAndLocalFilesAndKeepsOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "PlenactTests.Month." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        let store = FullMonthExampleStore(root: folder.appendingPathComponent("Backup"), documents: folder.appendingPathComponent("Documents"), support: folder.appendingPathComponent("Support"), domainName: name)
        try FileManager.default.createDirectory(at: store.documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.support, withIntermediateDirectories: true)
        let attachment = store.documents.appendingPathComponent("photo.bin")
        let background = store.support.appendingPathComponent("background.bin")
        try Data([1, 2, 3]).write(to: attachment)
        try Data([4, 5, 6]).write(to: background)
        let original: [String: Any] = ["Plenact.PersonalCollections.v1": Data([9]), "Plenact.CustomSetting": "original", "AnUnknownFutureKey": ["one", "two"]]
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
    /// @fcn        PlenactBoardDocumentTests.testFullMonthBackupRejectsCorruptionAndRecoversInterruptedSwitch
    /// @brief      Verify that full Month Backup Rejects Corruption And Recovers Interrupted Switch
    /// @details    Exercises `folder.appendingPathComponent`, `store.documents.appendingPathComponent`,
    ///             `Data([1]).write`. Checks `XCTAssertEqual(defaults.string(forKey: "Plenact.Protected"), "user
    ///             data")`; `XCTAssertEqual(try Data(contentsOf: file), Data([1]))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFullMonthBackupRejectsCorruptionAndRecoversInterruptedSwitch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "PlenactTests.Month." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        let store = FullMonthExampleStore(root: folder.appendingPathComponent("Backup"), documents: folder.appendingPathComponent("Documents"), support: folder.appendingPathComponent("Support"), domainName: name)
        try FileManager.default.createDirectory(at: store.documents, withIntermediateDirectories: true)
        let file = store.documents.appendingPathComponent("original.bin")
        try Data([1]).write(to: file)
        defaults.set("user data", forKey: "Plenact.Protected")
        try store.loadExample(FullMonthExample.make())
        let snapshot = store.root.appendingPathComponent("UserData")
        let transaction = store.root.appendingPathComponent("Transition")
        try FileManager.default.copyItem(at: snapshot, to: transaction)
        defaults.set("partial switch", forKey: "Plenact.Protected")
        try FileManager.default.removeItem(at: file)
        try store.recoverInterruptedSwitch()
        XCTAssertEqual(defaults.string(forKey: "Plenact.Protected"), "user data")
        XCTAssertEqual(try Data(contentsOf: file), Data([1]))
        XCTAssertTrue(store.hasUserData)
        try Data([99]).write(to: snapshot.appendingPathComponent("Documents/original.bin"))
        let previous = defaults.persistentDomain(forName: name) ?? [:]
        XCTAssertThrowsError(try store.restoreUserData())
        XCTAssertThrowsError(try store.loadExample(FullMonthExample.make()))
        XCTAssertTrue(NSDictionary(dictionary: defaults.persistentDomain(forName: name) ?? [:]).isEqual(to: previous))
        XCTAssertTrue(store.hasUserData)
        // An unavailable backup location must prevent replacement as well.
        let blocked = folder.appendingPathComponent("blocked")
        try Data([0]).write(to: blocked)
        let failed = FullMonthExampleStore(root: blocked, documents: store.documents, support: store.support, domainName: name)
        XCTAssertThrowsError(try failed.loadExample(FullMonthExample.make()))
        XCTAssertTrue(NSDictionary(dictionary: defaults.persistentDomain(forName: name) ?? [:]).isEqual(to: previous))
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
    func testLowerCornerBackPreferenceDefaultsOnAndPersistsWithoutProfile() throws {
        let legacy = try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.enablesLowerCornerBack)
        XCTAssertTrue(LocalProfilePreferences().enablesLowerCornerBack)
        let suite = "CornerBack." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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
        XCTAssertEqual(try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONEncoder().encode(preferences)), preferences)
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
    func testLowerCornerBackReservesSpaceOnlyWhenEnabledAndBackExists() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let suite = "CornerBackLayout." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var heights: [String: CGFloat] = [:]
        var activations = 0
        for (name, enabled, hasBack, toolbar) in [
            ("off", false, true, CGFloat(0)), ("on", true, true, 0),
            ("root", true, false, 0), ("toolbar", true, true, 56)
        ] {
            var preferences = LocalProfilePreferences()
            preferences.enablesLowerCornerBack = enabled
            PlanPreferencesStore.save(preferences, to: defaults)
            var measured: CGFloat?
            let host = UIHostingController(rootView: Color.blue
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured = $0 }
                .modifier(LowerCornerBackShortcut(action: hasBack ? { activations += 1 } : nil))
                .environment(\.workspaceBottomBarHeight, toolbar)
                .defaultAppStorage(defaults))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
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
    func testCornerBackResolvesLegacyProfileAndHonorsExplicitPreference() throws {
        let suite = "CornerBackLegacy." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = LocalProfilePreferences()
        preferences.enablesLowerCornerBack = true
        let profile = LocalProfile(displayName: "Synthetic", preferences: preferences)
        let profileData = try JSONEncoder().encode(profile)
        defaults.set(profileData, forKey: LocalProfileStore.storageKey)
        XCTAssertTrue(PlanPreferencesStore.load(from: defaults).enablesLowerCornerBack)
        XCTAssertTrue(PlanPreferencesStore.resolved(preferencesData: nil, profileData: profileData).enablesLowerCornerBack)
        XCTAssertTrue(PlanPreferencesStore.resolved(preferencesData: Data("invalid".utf8), profileData: profileData).enablesLowerCornerBack)
        XCTAssertNil(defaults.object(forKey: PlanPreferencesStore.key))
        preferences.enablesLowerCornerBack = false
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertFalse(PlanPreferencesStore.load(from: defaults).enablesLowerCornerBack)
        XCTAssertFalse(PlanPreferencesStore.resolved(preferencesData: defaults.data(forKey: PlanPreferencesStore.key),
                                                  profileData: profileData).enablesLowerCornerBack)
        XCTAssertEqual(defaults.data(forKey: LocalProfileStore.storageKey), profileData)
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
    func testAddItemTextColorsPersistAndRemainScopedToTheirView() throws {
        let legacy = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.addItemTextColor)
        XCTAssertNil(legacy.resolvedAddItemTextColor(list: nil, title: "Thursday"))
        for title in ["On the Table", "In the Queue", "Scheduled"] {
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
        let inherited = BoardAppearance.inheritingLists([styled])[0]
        XCTAssertNil(inherited.appearance?.addItemTextColor)
        XCTAssertEqual(inherited.cards, original.cards)
        XCTAssertEqual(styled.appearance?.addItemTextColor, .charcoal)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testInlineListCaptureRetainsFailedDraftAndCreatesDestinationItems
    /// @brief      Verify quick entry uses canonical creation for ordinary and Day Lists
    /// @details    Checks repeated capture, Card and Note defaults, whitespace rejection, archived
    ///             destinations, and retention of the original writing after a rejected save.
    ///
    /// @return     (Void) no return value
    ///
    func testInlineListCaptureRetainsFailedDraftAndCreatesDestinationItems() {
        for title in ["Projects", "Monday", "On the Table", "In the Queue", "Scheduled"] {
            for presentation in [ItemPresentation.card, .note] {
                var list = KanbanList(id: 7, title: title, cards: [], newItemPresentation: presentation)
                var draft = InlineListCaptureDraft(title: "  First thought  ")
                XCTAssertFalse(draft.submit(to: list) { _ in false })
                XCTAssertEqual(draft.title, "  First thought  ")
                for text in ["  First thought  ", "Another thought"] {
                    draft.title = text
                    let destination = list
                    XCTAssertTrue(draft.submit(to: destination) { capture in
                        guard let items = ListItemCreation.items(capture, in: destination,
                            startingAt: list.cards.count + 20) else { return false }
                        list.cards.append(contentsOf: items)
                        return true
                    })
                    XCTAssertEqual(draft.title, "")
                }
                XCTAssertEqual(list.cards.map(\.word), ["First thought", "Another thought"])
                XCTAssertTrue(list.cards.allSatisfy { $0.listTitle == title && $0.presentation == presentation })
                XCTAssertEqual(Set(list.cards.map(\.id)).count, 2)
                draft.title = " \n "
                XCTAssertFalse(draft.submit(to: list) { _ in XCTFail("Blank titles must not save"); return true })
                list.isArchived = true
                draft.title = "Keep this draft"
                XCTAssertFalse(draft.submit(to: list) { capture in
                    ListItemCreation.items(capture, in: list, startingAt: 30) != nil
                })
                XCTAssertEqual(draft.title, "Keep this draft")
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListComposerSubmissionPreservesKindScheduleActionsAndAttachments
    /// @brief      Verify that list Composer Submission Preserves Kind Schedule Actions And Attachments
    /// @details    Exercises `start.addingTimeInterval`, `ListItemCreation.items`,
    ///             `card.checklists.flatMap(\.items).map`. Checks `XCTAssertEqual(card.id, 99)`;
    ///             `XCTAssertEqual(card.presentation, presentation)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListComposerSubmissionPreservesKindScheduleActionsAndAttachments() throws {
        let list = KanbanList(id: 7, title: "Work", cards: [])
        let start = Date(timeIntervalSince1970: 1800000000)
        let schedule = QuickCaptureSchedule(start: start, stop: start.addingTimeInterval(3600), includesTime: true)
        let attachment = KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link)
        for presentation in [ItemPresentation.card, .note] {
            let capture = QuickCaptureSubmission(listID: 7, title: "A new item", body: "Keep this writing", subtitle: "Context",
                presentation: presentation, actions: ["First step"], attachments: [attachment], schedule: schedule)
            let card = try XCTUnwrap(ListItemCreation.items(capture, in: list, startingAt: 99)?.first)
            XCTAssertEqual(card.id, 99)
            XCTAssertEqual(card.presentation, presentation)
            XCTAssertEqual(card.descriptionOverride, "Keep this writing")
            XCTAssertEqual(card.subtitleOverride, "Context")
            XCTAssertEqual(card.startDate, start)
            XCTAssertEqual(card.dueDate, schedule.stop)
            XCTAssertEqual(card.startDateKind, .dateAndTime)
            XCTAssertEqual(card.attachments, [attachment])
            XCTAssertEqual(card.checklists.flatMap(\.items).map(\.title), presentation == .card ? ["First step"] : [])
        }
        let wrongOwner = QuickCaptureSubmission(listID: 8, title: "Wrong", body: "", subtitle: "", presentation: .card,
            actions: nil, attachments: [], schedule: nil)
        XCTAssertNil(ListItemCreation.items(wrongOwner, in: list, startingAt: 99))
        XCTAssertTrue(list.cards.isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalListFullComposerRetainsScheduleAndActions
    /// @brief      Verify that personal List Full Composer Retains Schedule And Actions
    /// @details    Exercises `.now.addingTimeInterval`, `collection.addNote`, `card.checklists.flatMap(\.items).map`.
    ///             Checks `XCTAssertEqual(card.checklists.flatMap(\.items).map(\.title), ["First", "Second"])`;
    ///             `XCTAssertEqual(card.startDate, schedule.start)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPersonalListFullComposerRetainsScheduleAndActions() throws {
        var collection = PersonalCollection(title: "Personal", kind: .list)
        let schedule = QuickCaptureSchedule(start: .now, stop: .now.addingTimeInterval(3600), includesTime: true)
        try collection.addNote(title: "Card", body: "Details", presentation: .card,
            actions: ["First", "Second"], schedule: schedule)
        let card = try XCTUnwrap(collection.lists[0].cards.last)
        XCTAssertEqual(card.checklists.flatMap(\.items).map(\.title), ["First", "Second"])
        XCTAssertEqual(card.startDate, schedule.start)
        XCTAssertEqual(card.dueDate, schedule.stop)
        let before = collection
        let invalid = QuickCaptureSchedule(start: .now, stop: .distantPast, includesTime: true)
        XCTAssertThrowsError(try collection.addNote(title: "Invalid", body: "", schedule: invalid))
        XCTAssertEqual(collection, before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalNoteCreationPreservesMultipleAttachmentMetadata
    /// @brief      Verify that personal Note Creation Preserves Multiple Attachment Metadata
    /// @details    Exercises `collection.addNote`. Checks `XCTAssertEqual(item.attachments, attachments)`;
    ///             `XCTAssertEqual(item.coverAttachmentID, attachments[1].id)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPersonalNoteCreationPreservesMultipleAttachmentMetadata() throws {
        var collection = PersonalCollection(title: "Attachment test", kind: .list)
        let attachments = [KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link),
                           KanbanAttachment(fileName: "test-photo.png", mediaKind: .photo),
                           KanbanAttachment(fileName: "test-video.mov", mediaKind: .video)]
        for kind in [ItemPresentation.card, .note] {
            try collection.addNote(title: "New item", body: "Keep this writing", presentation: kind, attachments: attachments)
            let item = try XCTUnwrap(collection.lists[0].cards.last)
            XCTAssertEqual(item.attachments, attachments)
            XCTAssertEqual(item.coverAttachmentID, attachments[1].id)
            XCTAssertEqual(item.presentation, kind)
        }
        let restored = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection))
        XCTAssertEqual(restored.lists[0].cards, collection.lists[0].cards)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreationAttachmentListPresentsSharedMenuInLightAndDark
    /// @brief      Verify that creation Attachment List Presents Shared Menu In Light And Dark
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertNotNil(host.presentedViewController)`;
    ///             `XCTAssertEqual(draft.entries.count, 2)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCreationAttachmentListPresentsSharedMenuInLightAndDark() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let draft = CreationAttachmentDraft()
            draft.entries = [.init(content: .link(try XCTUnwrap(URL(string: "https://example.com/plans")))),
                             .init(content: .drawing(DrawingCaptureDraft(drawing: drawingFixture())))]
            let view = NavigationStack {
                Form { Section("Attachments") { CreationAttachmentList(draft: draft) } }.navigationTitle("New item")
            }.modifier(CreationAttachmentPresentation(draft: draft))
                .preferredColorScheme(style == .dark ? .dark : .light)
            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = style
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            draft.openSources()
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertNotNil(host.presentedViewController)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-creation-attachments-\(style.rawValue).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("CREATION_ATTACHMENTS_RENDER=" + url.path)
            draft.sheet = nil
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(draft.entries.count, 2, "Closing the menu must retain the draft attachments")
            window.rootViewController = nil
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreationAttachmentDraftKeepsMultipleEntriesAndCleansRejectedFiles
    /// @brief      Verify that creation Attachment Draft Keeps Multiple Entries And Cleans Rejected Files
    /// @details    Exercises `UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image`,
    ///             `UIColor.blue.setFill`, `context.fill`. Checks `XCTAssertEqual(attachments.count, 23)`;
    ///             `XCTAssertTrue(rejectedFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    @MainActor
    func testCreationAttachmentDraftKeepsMultipleEntriesAndCleansRejectedFiles() throws {
        let draft = CreationAttachmentDraft()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let data = try XCTUnwrap(image.pngData())
        draft.entries = [.init(content: .media(data, .photo, "png")), .init(content: .media(data, .photo, "png"))]
        for index in 0..<20 { draft.entries.append(.init(content: .link(try XCTUnwrap(URL(string: "https://example.com/\(index)"))))) }
        draft.entries.append(.init(content: .drawing(DrawingCaptureDraft(drawing: drawingFixture()))))
        var rejectedFiles: [URL] = []
        XCTAssertFalse(try draft.save { attachments in
            XCTAssertEqual(attachments.count, 23)
            rejectedFiles = attachments.compactMap { CardAttachmentStore.fileURL(for: $0) }
            XCTAssertTrue(rejectedFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
            return false
        })
        XCTAssertEqual(draft.entries.count, 23)
        XCTAssertFalse(rejectedFiles.isEmpty)
        XCTAssertTrue(rejectedFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        var saved: [KanbanAttachment] = []
        XCTAssertTrue(try draft.save { saved = $0; return true })
        defer { try? CardAttachmentStore.removeDeletedFiles(Set(saved.flatMap(\.storedFileNames)), keeping: []) }
        XCTAssertEqual(saved.count, 23)
        XCTAssertEqual(saved.prefix(2).map(\.kind), [.photo, .photo])
        XCTAssertEqual(saved.dropFirst(2).prefix(20).map(\.kind), Array(repeating: .link, count: 20))
        XCTAssertTrue(saved.prefix(2).compactMap { CardAttachmentStore.fileURL(for: $0) }.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let drawing = try XCTUnwrap(saved.last)
        XCTAssertEqual(try DrawingAttachmentStore.load(drawing).drawing.strokes.count, drawingFixture().strokes.count)
        var thrownFiles: [URL] = []
        XCTAssertThrowsError(try draft.save { attachments in
            thrownFiles = attachments.compactMap { CardAttachmentStore.fileURL(for: $0) }
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertTrue(thrownFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(draft.entries.count, 23)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreatedContentRevealScrollsLongDayListsInBothLayouts
    /// @brief      Verify that created Content Reveal Scrolls Long Day Lists In Both Layouts
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `CreatedContentReveal.shared.complete`. Checks `XCTAssertLessThan(native.contentOffset.y, 100)`;
    ///             `XCTAssertGreaterThan(native.contentOffset.y, 100)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCreatedContentRevealScrollsLongDayListsInBothLayouts() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            if let target = CreatedContentReveal.shared.target { CreatedContentReveal.shared.complete(target) }
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testCreatedContentRevealScrollsLongDayListsInBothLayouts.collection
        /// @brief      Find collection in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UICollectionView. Returns the first qualifying match,
        ///             or nil when none is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UICollectionView?) matching or resolved value, or nil when unavailable
        ///
        func collection(in view: UIView) -> UICollectionView? {
            if let collection = view as? UICollectionView { return collection }
            return view.subviews.lazy.compactMap { collection(in: $0) }.first
        }
        for mode in SingleListViewMode.allCases {
            for width: CGFloat in [393, 820] {
                let owner = UUID()
                defer { UserDefaults.standard.removeObject(forKey: BoardViewportMemory.prefix + owner.uuidString + ".focused.8") }
                var list = KanbanList(id: 8, title: "Creation test", cards: [])
                list.cards = (0..<40).map { list.makeItem(id: $0, title: "Item \($0)", presentationOverride: mode == .noteList ? .note : .card) }
                list.setSingleListViewMode(mode)
                let target = try XCTUnwrap(list.cards.last)
                let view = TodayListDetailView(lists: .constant([list]), reservedLists: [], labelLibrary: .constant(.starter),
                    savedCardIDs: .constant([]), listID: list.id, currentUserName: "Test", onClose: {}, onOpenWeek: {},
                    onPermanentDelete: { _ in false })
                    .environment(\.cardMovementSource, owner)
                let host = UIHostingController(rootView: view)
                window.frame = CGRect(x: 0, y: 0, width: width, height: width < 500 ? 852 : 1180)
                window.rootViewController = host; window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(250))
                let native = try XCTUnwrap(collection(in: host.view))
                XCTAssertLessThan(native.contentOffset.y, 100)
                CreatedContentReveal.shared.request(listID: list.id, card: target)
                try await Task.sleep(for: .milliseconds(1100))
                host.view.layoutIfNeeded()
                XCTAssertGreaterThan(native.contentOffset.y, 100, "New item must be revealed in \(mode), width \(width)")
                XCTAssertLessThan(native.contentSize.height - native.contentOffset.y - native.bounds.height, 220)
                XCTAssertNil(CreatedContentReveal.shared.target)
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-created-\(mode.rawValue)-\(Int(width)).png")
                try XCTUnwrap(image.pngData()).write(to: url)
                print("CREATION_REVEAL_RENDER=" + url.path)
                window.rootViewController = nil
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekAndLibraryBoardsPrioritizeInnerListSwipesWithoutDisablingScrolling
    /// @brief      Verify that week And Library Boards Prioritize Inner List Swipes Without Disabling Scrolling
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertGreaterThan(BoardListSwipePriority.install(for:
    ///             list), 0)`; `XCTAssertTrue(list.isScrollEnabled)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testWeekAndLibraryBoardsPrioritizeInnerListSwipesWithoutDisablingScrolling() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }


        ///
        /// @fcn        PlenactBoardDocumentTests.testWeekAndLibraryBoardsPrioritizeInnerListSwipesWithoutDisablingScrolling.collections
        /// @brief      Find collections in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UICollectionView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UICollectionView]) resulting values in the ordering described above
        ///
        func collections(in view: UIView) -> [UICollectionView] {
            ((view as? UICollectionView).map { [$0] } ?? []) + view.subviews.flatMap { collections(in: $0) }
        }
        for personal in [false, true] {
            let owner = UUID()
            defer { UserDefaults.standard.removeObject(forKey: BoardViewportMemory.prefix + owner.uuidString) }
            let cards = [KanbanCard(id: 1, word: "Card", listTitle: "First", checklists: []),
                         KanbanCard(id: 2, word: "Note", listTitle: "First", checklists: [], presentation: .note)]
            let lists = [KanbanList(id: 0, title: "First", cards: cards), KanbanList(id: 1, title: "Second", cards: [])]
            let host = UIHostingController(rootView: ContentView(lists: .constant(lists), allowsAddingLists: false,
                retainedAttachmentLists: { [] }, personalCollectionID: personal ? owner : nil, viewportOwnerID: owner))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            let list = try XCTUnwrap(collections(in: host.view).first)
            XCTAssertGreaterThan(BoardListSwipePriority.install(for: list), 0)
            XCTAssertTrue(list.isScrollEnabled)
            XCTAssertTrue(list.panGestureRecognizer.isEnabled)
            var ancestor = list.superview
            var board: UIScrollView?
            while let view = ancestor {
                if let candidate = view as? UIScrollView, candidate.contentSize.width > candidate.bounds.width + 1 { board = candidate; break }
                ancestor = view.superview
            }
            XCTAssertTrue(try XCTUnwrap(board).isScrollEnabled)
            XCTAssertTrue(try XCTUnwrap(board).panGestureRecognizer.isEnabled)
            print("BOARD_LIST_NATIVE_PANS=" + (list.gestureRecognizers ?? []).map { String(describing: type(of: $0)) }.joined(separator: ","))
            window.rootViewController = nil
        }
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
    func testCreatedContentRevealFindsDestinationColumnAndGalleryTile() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            if let target = CreatedContentReveal.shared.target { CreatedContentReveal.shared.complete(target) }
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
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
        func scrolls(in view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrolls(in: $0) }
        }
        for gallery in [false, true] {
            let owner = UUID()
            let key = BoardViewportMemory.prefix + owner.uuidString
            defer { UserDefaults.standard.removeObject(forKey: key) }
            var memory = BoardViewportState(); memory.gallery = gallery
            UserDefaults.standard.set(try JSONEncoder().encode(memory), forKey: key)
            var destination = KanbanList(id: 2, title: "Destination", cards: [])
            destination.cards = (0..<40).map { destination.makeItem(id: $0, title: "Item \($0)") }
            let lists = [KanbanList(id: 0, title: "First", cards: []), KanbanList(id: 1, title: "Second", cards: []), destination]
            let host = UIHostingController(rootView: ContentView(lists: .constant(lists), retainedAttachmentLists: { [] }, viewportOwnerID: owner))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            CreatedContentReveal.shared.request(listID: destination.id, card: try XCTUnwrap(destination.cards.last))
            try await Task.sleep(for: .milliseconds(1500))
            host.view.layoutIfNeeded()
            let native = scrolls(in: host.view)
            XCTAssertTrue(native.contains { $0.contentOffset.y > 100 }, "Creation must reveal the row/tile, gallery: \(gallery)")
            if !gallery { XCTAssertTrue(native.contains { $0.contentOffset.x > 100 }, "Destination column must also be revealed") }
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
    func testCreatedContentRevealTargetsExactRecordAndRetainsNewerRequests() throws {
        let reveal = CreatedContentReveal()
        let first = KanbanList(id: 4, title: "Monday", cards: []).makeItem(id: 10, title: "New Card", createdAt: Date(timeIntervalSince1970: 100))
        let collision = KanbanList(id: 4, title: "Other Board", cards: []).makeItem(id: 10, title: "Different Card", createdAt: Date(timeIntervalSince1970: 200))
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
    /// @fcn        PlenactBoardDocumentTests.testSloganManualReadingAllowsOverscrollAndResumesWithoutJumping
    /// @brief      Verify that slogan Manual Reading Allows Overscroll And Resumes Without Jumping
    /// @details    Exercises `TodaySloganMotion.draggedPosition`, `TodaySloganMotion.position`. Checks
    ///             `XCTAssertEqual(TodaySloganMotion.draggedPosition(start: -100, translation: 500, viewport: 300,
    ///             textWidth: 700), 400)`; `XCTAssertEqual(TodaySloganMotion.draggedPosition(start: -100,
    ///             translation: -500, viewport: 300, textWidth: 700), -600)`.
    ///
    /// @return     (Void) no return value
    ///
    func testSloganManualReadingAllowsOverscrollAndResumesWithoutJumping() {
        XCTAssertEqual(TodaySloganMotion.draggedPosition(start: -100, translation: 500, viewport: 300, textWidth: 700), 400)
        XCTAssertEqual(TodaySloganMotion.draggedPosition(start: -100, translation: -500, viewport: 300, textWidth: 700), -600)
        XCTAssertEqual(TodaySloganMotion.draggedPosition(start: 0, translation: -50, viewport: 300, textWidth: 100), -50)
        XCTAssertEqual(TodaySloganMotion.draggedPosition(start: 400, translation: 5000, viewport: 300, textWidth: 700), 5400)
        XCTAssertEqual(TodaySloganMotion.draggedPosition(start: -600, translation: -5000, viewport: 300, textWidth: 700), -5600)
        XCTAssertEqual(TodaySloganMotion.position(elapsed: -1, start: -5600, viewport: 300, textWidth: 700), -5600)
        XCTAssertEqual(TodaySloganMotion.position(elapsed: 1, start: -5600, viewport: 300, textWidth: 700), 264.9, accuracy: 0.001)
        XCTAssertEqual(TodaySloganMotion.position(elapsed: 1, start: 5400, viewport: 300, textWidth: 700), 264.9, accuracy: 0.001)
        // A future resume date produces negative elapsed time throughout the reading pause.
        XCTAssertEqual(TodaySloganMotion.position(elapsed: -1, start: -150, viewport: 300, textWidth: 700), -150)
        XCTAssertEqual(TodaySloganMotion.position(elapsed: 0, start: -150, viewport: 300, textWidth: 700), -150)
        XCTAssertEqual(TodaySloganMotion.position(elapsed: 1, start: -150, viewport: 300, textWidth: 700), -185.1, accuracy: 0.001)
        // Once the text exits, the next pass enters from the right.
        XCTAssertEqual(TodaySloganMotion.position(elapsed: 1, start: -700, viewport: 300, textWidth: 700), 264.9, accuracy: 0.001)
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
    func testDailySlogansStayStableAndRotateThroughSixtyLocalDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        XCTAssertEqual(TodaySloganCatalog.slogans.count, 60)
        XCTAssertEqual(Set(TodaySloganCatalog.slogans).count, 60)
        var seen = Set<String>()
        for day in 0..<60 {
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
    func testDailySloganUsesLocalMidnightAcrossTimeZones() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-16T04:30:00Z"))
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        var london = chicago
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        XCTAssertEqual(TodaySloganCatalog.slogan(on: instant, calendar: chicago), TodaySloganCatalog.slogans[0])
        XCTAssertEqual(TodaySloganCatalog.slogan(on: instant, calendar: london), TodaySloganCatalog.slogans[1])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewComposerSharesTitleAndRichBodyAcrossCardAndNote
    /// @brief      Verify that new Composer Shares Title And Rich Body Across Card And Note
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`, `.constant`.
    ///             Checks `XCTAssertEqual(noteTitle.text, "Shared draft title")`;
    ///             `XCTAssertEqual(PlanRichText.runs(PlanRichText.encode(writing.attributedText)),
    ///             PlanRichText.runs(body))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testNewComposerSharesTitleAndRichBodyAcrossCardAndNote() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let lists = [KanbanList(id: 0, title: "Monday", cards: [])]
        let host = UIHostingController(rootView: QuickNoteComposer(lists: .constant(lists), initialListID: 0) { _, _, _, _, _, _ in
            XCTFail("Switching formats must not create content")
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(300))


        ///
        /// @fcn        PlenactBoardDocumentTests.testNewComposerSharesTitleAndRichBodyAcrossCardAndNote.descendants
        /// @brief      Find descendants in the hosted view hierarchy
        /// @details    Recursively inspects native subviews. Returns all collected matches in hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIView]) resulting values in the ordering described above
        ///
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let title = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first { String(describing: type(of: $0)).contains("VerticalTextView") })
        title.becomeFirstResponder()
        title.insertText("Shared draft title")
        let details = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first { $0.accessibilityLabel == "Details (optional)" })
        let body = PlanRichText.prefix + Data("[{\"text\":\"Keep this writing\",\"bold\":true,\"italic\":false}]".utf8).base64EncodedString()
        details.attributedText = PlanRichText.attributed(body)
        details.delegate?.textViewDidChange?(details)
        let picker = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UISegmentedControl }.first)
        picker.selectedSegmentIndex = 1
        picker.sendActions(for: .valueChanged)
        try await Task.sleep(for: .milliseconds(350))
        let noteTitle = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first { String(describing: type(of: $0)).contains("VerticalTextView") })
        XCTAssertEqual(noteTitle.text, "Shared draft title")
        let writing = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first { $0.accessibilityLabel == "Start writing..." })
        XCTAssertEqual(PlanRichText.runs(PlanRichText.encode(writing.attributedText)), PlanRichText.runs(body))
        noteTitle.becomeFirstResponder()
        noteTitle.insertText(" edited")
        writing.attributedText = PlanRichText.attributed("Edited note body")
        writing.delegate?.textViewDidChange?(writing)
        picker.selectedSegmentIndex = 0
        picker.sendActions(for: .valueChanged)
        try await Task.sleep(for: .milliseconds(350))
        let returnedTitle = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first { String(describing: type(of: $0)).contains("VerticalTextView") })
        XCTAssertEqual(returnedTitle.text, "Shared draft title edited")
        let returnedDetails = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first { $0.accessibilityLabel == "Details (optional)" })
        XCTAssertEqual(PlanRichText.encode(returnedDetails.attributedText), "Edited note body")
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
    func testCollectionBackgroundsPersistAndExcludeDatedViews() throws {
        let personalID = UUID(), weekID = UUID()
        XCTAssertTrue(CollectionBackground.isAllowed(collectionID: personalID, datedWeekIDs: [weekID], isDatedView: false))
        XCTAssertFalse(CollectionBackground.isAllowed(collectionID: nil, datedWeekIDs: [weekID], isDatedView: false))
        XCTAssertFalse(CollectionBackground.isAllowed(collectionID: weekID, datedWeekIDs: [weekID], isDatedView: false))
        XCTAssertFalse(CollectionBackground.isAllowed(collectionID: personalID, datedWeekIDs: [], isDatedView: true))
        let legacy = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.collectionBackground)
        for preset in CollectionBackgroundPreset.allCases {
            var collection = PersonalCollection(title: "Personal space", kind: .board)
            collection.boardAppearance = BoardAppearance()
            collection.boardAppearance?.collectionBackground = CollectionBackground(preset: preset,
                photoFileName: preset == .photo ? "example.jpg" : nil)
            let originalLists = collection.lists
            let decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection))
            XCTAssertEqual(decoded, collection)
            XCTAssertEqual(decoded.lists, originalLists)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundPhotoResizesStoresAndRejectsInvalidImages
    /// @brief      Verify that background Photo Resizes Stores And Rejects Invalid Images
    /// @details    Exercises `UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1800), format:
    ///             format).image`, `UIColor.systemTeal.setFill`, `context.fill`. Checks
    ///             `XCTAssertLessThanOrEqual(max(photo.size.width, photo.size.height), 2048)`;
    ///             `XCTAssertEqual(photo.size.width / photo.size.height, 3000.0 / 1800.0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testBackgroundPhotoResizesStoresAndRejectsInvalidImages() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1800), format: format).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1800))
        }
        let data = try CollectionBackgroundPhotoStore.preparedPhoto(try XCTUnwrap(original.pngData()))
        let photo = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(photo.size.width, photo.size.height), 2048)
        XCTAssertEqual(photo.size.width / photo.size.height, 3000.0 / 1800.0, accuracy: 0.01)
        let name = try CollectionBackgroundPhotoStore.save(data)
        defer { CollectionBackgroundPhotoStore.remove(name) }
        XCTAssertNotNil(CollectionBackgroundPhotoStore.image(named: name))
        XCTAssertNil(CollectionBackgroundPhotoStore.image(named: "../" + name))
        XCTAssertThrowsError(try CollectionBackgroundPhotoStore.preparedPhoto(Data("not an image".utf8)))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCollectionBackgroundPresetsRenderOffline
    /// @brief      Verify that collection Background Presets Render Offline
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`, `.flexible`.
    ///             Uses the fixture and assertions below to verify collection Background Presets Render Offline.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCollectionBackgroundPresetsRenderOffline() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(CollectionBackgroundPreset.allCases.filter { $0 != .photo }) { preset in
                CollectionBackgroundSurface(background: CollectionBackground(preset: preset))
                    .frame(height: 160)
                    .overlay(alignment: .bottomLeading) { Text(preset.title).font(.headline).foregroundStyle(.white).padding(12) }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }.padding(16).background(Color(.systemGroupedBackground)))
        host.safeAreaRegions = []
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 560)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(200))
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Personal background presets"; attachment.lifetime = .keepAlways; add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-background-presets.png")
        try image.pngData()?.write(to: url)
        print("BACKGROUND_PRESETS_PATH=\(url.path)")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardBackgroundAndWeekDefaultRenderSeparately
    /// @brief      Verify that personal Board Background And Week Default Render Separately
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`, `.constant`.
    ///             Uses the fixture and assertions below to verify personal Board Background And Week Default Render
    ///             Separately.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPersonalBoardBackgroundAndWeekDefaultRenderSeparately() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let owner = PersonalCollection(title: "Garden plans", kind: .board)
        var appearance = BoardAppearance()
        appearance.collectionBackground = CollectionBackground(preset: .sage)
        for dated in [false, true] {
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: ContentView(lists: .constant(owner.lists), boardTitle: dated ? "Plenact" : "Garden plans",
                boardSubtitle: dated ? "This Week" : "Board", onClose: { }, onListsChanged: { _ in },
                personalCollectionID: dated ? nil : owner.id, boardAppearance: .constant(appearance)))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(for: .milliseconds(250))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = dated ? "Week keeps default" : "Personal Board sage background"
            attachment.lifetime = .keepAlways; add(attachment)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(dated ? "plenact-week-default.png" : "plenact-personal-background.png")
            try image.pngData()?.write(to: url)
            print("BOARD_BACKGROUND_PATH=\(url.path)")
        }
        previous?.makeKey()
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardViewportMemoryRoundTripsAndKeepsOwnersSeparate
    /// @brief      Verify that board Viewport Memory Round Trips And Keeps Owners Separate
    /// @details    Exercises `first.record`, `first.flush`. Checks `XCTAssertEqual(reopened.state, first.state)`;
    ///             `XCTAssertEqual(other.state.scale, 1)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testBoardViewportMemoryRoundTripsAndKeepsOwnersSeparate() throws {
        let suite = "Plenact.ViewportTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = BoardViewportMemory(owner: "first", defaults: defaults)
        first.state.scale = 0.48; first.state.panoramic = true; first.state.gallery = true
        first.state.presentation = "overview"; first.state.visibleListID = 8
        first.record(430, for: "horizontal"); first.record(680, for: "list:8"); first.flush()
        let reopened = BoardViewportMemory(owner: "first", defaults: defaults)
        XCTAssertEqual(reopened.state, first.state)
        let other = BoardViewportMemory(owner: "second", defaults: defaults)
        XCTAssertEqual(other.state.scale, 1)
        XCTAssertTrue(other.state.offsets.isEmpty)
        first.record(510, for: "list:9"); first.flush()
        XCTAssertEqual(BoardViewportMemory(owner: "first", defaults: defaults).state.offsets["list:8"], 680)
        first.record(.infinity, for: "horizontal")
        XCTAssertEqual(first.state.offsets["horizontal"], 430)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testViewportProbeRestoresNativeOffsetsInBothDirections
    /// @brief      Verify that viewport Probe Restores Native Offsets In Both Directions
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(offset, 470)`;
    ///             `XCTAssertEqual(memory.state.offsets["position"], 470)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testViewportProbeRestoresNativeOffsetsInBothDirections() async throws {
        let suite = "Plenact.ScrollRestoreTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        defer { previous?.makeKey() }


        ///
        /// @fcn        PlenactBoardDocumentTests.testViewportProbeRestoresNativeOffsetsInBothDirections.nativeScroll
        /// @brief      Find native scroll in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns the first qualifying match, or
        ///             nil when none is present.
        ///
        /// @param[in]  view        Native view inspected or synchronized by the operation
        /// @param[in]  horizontal  Whether the probe observes the horizontal rather than vertical axis
        ///
        /// @return     (UIScrollView?) matching or resolved value, or nil when unavailable
        ///
        func nativeScroll(_ view: UIView, horizontal: Bool) -> UIScrollView? {
            if let scroll = view as? UIScrollView,
               horizontal ? scroll.contentSize.width > scroll.bounds.width + 1 : scroll.contentSize.height > scroll.bounds.height + 1 { return scroll }
            for child in view.subviews { if let found = nativeScroll(child, horizontal: horizontal) { return found } }
            return nil
        }
        for horizontal in [true, false] {
            let owner = horizontal ? "horizontal-board" : "vertical-list"
            for reopening in [false, true] {
                let memory = BoardViewportMemory(owner: owner, defaults: defaults)
                let host = UIHostingController(rootView: ScrollView(horizontal ? .horizontal : .vertical) {
                    Color.gray.frame(width: horizontal ? 2200 : 220, height: horizontal ? 120 : 3000)
                        .background(BoardViewportScrollProbe(memory: memory, key: "position", horizontal: horizontal))
                }.frame(width: 260, height: 230))
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = host; window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                try await Task.sleep(for: .milliseconds(250))
                host.view.layoutIfNeeded()
                let scroll = try XCTUnwrap(nativeScroll(host.view, horizontal: horizontal))
                if reopening {
                    let offset = horizontal ? scroll.contentOffset.x + scroll.adjustedContentInset.left : scroll.contentOffset.y + scroll.adjustedContentInset.top
                    XCTAssertEqual(offset, 470, accuracy: 2)
                } else {
                    scroll.setContentOffset(horizontal ? CGPoint(x: 470, y: 0) : CGPoint(x: 0, y: 470), animated: false)
                    try await Task.sleep(for: .milliseconds(50))
                    memory.flush()
                    XCTAssertEqual(memory.state.offsets["position"], 470)
                }
            }
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testZoomedBoardRestoresItsRealHorizontalViewport
    /// @brief      Verify that zoomed Board Restores Its Real Horizontal Viewport
    /// @details    Exercises `UserDefaults.standard.removeObject`, `initial.flush`, `(0..<10).map`. Checks
    ///             `XCTAssertEqual(scroll.contentOffset.x + scroll.adjustedContentInset.left, 420)`;
    ///             `XCTAssertEqual(list.contentOffset.y + list.adjustedContentInset.top, 350)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testZoomedBoardRestoresItsRealHorizontalViewport() async throws {
        let owner = UUID()
        let key = BoardViewportMemory.prefix + owner.uuidString
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let initial = BoardViewportMemory(owner: owner.uuidString)
        initial.state.scale = 0.62; initial.state.panoramic = true; initial.state.presentation = "standard"
        initial.flush()
        var lists = (0..<10).map { KanbanList(id: $0, title: "List \($0)", cards: []) }
        lists[0].cards = (0..<30).map { KanbanCard(id: $0, word: "Card \($0)", listTitle: lists[0].title) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        defer { previous?.makeKey() }


        ///
        /// @fcn        PlenactBoardDocumentTests.testZoomedBoardRestoresItsRealHorizontalViewport.scrolls
        /// @brief      Find scrolls in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrolls(_ view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrolls)
        }
        for reopening in [false, true] {
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: ContentView(lists: .constant(lists), boardTitle: "Viewport test",
                onListsChanged: { _ in }, personalCollectionID: owner))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(500))
            host.view.layoutIfNeeded()
            let scroll = try XCTUnwrap(scrolls(host.view).first { !($0 is UICollectionView) && $0.contentSize.width > $0.bounds.width + 100 })
            if reopening {
                XCTAssertEqual(scroll.contentOffset.x + scroll.adjustedContentInset.left, 420, accuracy: 3)
                scroll.setContentOffset(CGPoint(x: -scroll.adjustedContentInset.left, y: scroll.contentOffset.y), animated: false)
                try await Task.sleep(for: .milliseconds(300))
                let vertical = scrolls(host.view).compactMap { $0 as? UICollectionView }.first { $0.contentSize.height > $0.bounds.height + 100 }
                let list = try XCTUnwrap(vertical)
                XCTAssertEqual(list.contentOffset.y + list.adjustedContentInset.top, 350, accuracy: 3)
            } else {
                let vertical = scrolls(host.view).compactMap { $0 as? UICollectionView }.first { $0.contentSize.height > $0.bounds.height + 100 }
                let list = try XCTUnwrap(vertical)
                list.setContentOffset(CGPoint(x: list.contentOffset.x, y: 350 - list.adjustedContentInset.top), animated: false)
                try await Task.sleep(for: .milliseconds(450))
                XCTAssertEqual(BoardViewportMemory(owner: owner.uuidString).state.offsets["list:0"] ?? -1, 350, accuracy: 3)
                scroll.setContentOffset(CGPoint(x: 420 - scroll.adjustedContentInset.left, y: scroll.contentOffset.y), animated: false)
                try await Task.sleep(for: .milliseconds(450))
                XCTAssertEqual(BoardViewportMemory(owner: owner.uuidString).state.offsets["horizontal"] ?? -1, 420, accuracy: 3)
            }
            window.isHidden = true; window.rootViewController = nil
            try await Task.sleep(for: .milliseconds(100))
        }
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
    func testPreviewTextColorsInheritIndependentlyFromBoardListAndItem() throws {
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
        for presentation in [ItemPresentation.card, .note] {
            let card = KanbanCard(id: 123, word: "Custom colors", listTitle: "Plans", presentation: presentation, appearance: item)
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
    func testListPreviewTextColorsPersistIndependentlyAndDecodeLegacyDefaults() throws {
        let legacy = try JSONDecoder().decode(ItemAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.cardTitleColor); XCTAssertNil(legacy.cardTextColor)
        XCTAssertTrue(legacy.isEmpty)
        for color in ListPreviewTextColor.allCases {
            var appearance = ItemAppearance()
            appearance.cardTitleColor = color
            XCTAssertFalse(appearance.isEmpty)
            var list = KanbanList(id: 9, title: "Personal List", cards: [])
            list.appearance = appearance
            let decoded = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list))
            XCTAssertEqual(decoded.appearance?.cardTitleColor, color)
            XCTAssertNil(decoded.appearance?.cardTextColor)
            appearance.cardTitleColor = nil; appearance.cardTextColor = color
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
    /// @fcn        PlenactBoardDocumentTests.testCustomListPreviewColorsRenderWithoutEditingContent
    /// @brief      Verify that custom List Preview Colors Render Without Editing Content
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(originals, [card, note])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCustomListPreviewColorsRenderWithoutEditingContent() async throws {
        var card = KanbanCard(id: 92, word: "Plan the garden", listTitle: "Garden")
        card.subtitleOverride = "Choose seeds and make room to grow"
        var note = KanbanCard(id: 93, word: "Garden reflections", listTitle: "Garden", presentation: .note)
        note.descriptionOverride = "A few ideas for next season, with space for something new."
        let originals = [card, note]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: VStack(spacing: 16) {
            ForEach(originals) { item in
                KanbanCardView(card: item, height: 140, displaySettings: BoardDisplaySettings(),
                    titleColor: .teal, supportingTextColor: .plum, labelLibrary: .starter,
                    onUpdateCard: { _ in XCTFail("Colors must not edit content") },
                    onDeleteCard: { XCTFail("Colors must not delete") },
                    onArchiveCard: { XCTFail("Colors must not archive") }, onToggle: { XCTFail("Colors must not complete") })
            }
        }.padding(20).background(Color(.systemGroupedBackground)))
        host.safeAreaRegions = []
        window.frame = CGRect(x: 0, y: 0, width: 340, height: 390)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(200))
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Custom List preview text colors"; attachment.lifetime = .keepAlways; add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-list-preview-colors.png")
        try image.pngData()?.write(to: url)
        print("LIST_COLOR_PREVIEW_PATH=\(url.path)")
        XCTAssertEqual(originals, [card, note])
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
    func testFreshInstallationSeedsTutorialListsAndOrderedShortcutsOnlyOnce() throws {
        let suite = "Plenact.FreshInstallTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let seeded = TodayListPins.loadInitialCollections(from: defaults)
        XCTAssertEqual(seeded.map(\.title), ["On the Table", "In the Queue", "Scheduled"])
        XCTAssertTrue(seeded.allSatisfy { $0.kind == .list && $0.lists.count == 1 && $0.lists[0].allCards.count == 1 })
        let pins = TodayListPins.decode(try XCTUnwrap(defaults.data(forKey: TodayListPins.key)))
        XCTAssertEqual(pins, seeded.map { WorkspaceListReference(ownerID: $0.id, listID: $0.lists[0].id) })
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
    /// @fcn        PlenactBoardDocumentTests.testDefaultListPhotosAreBundledAndRespectCustomBackgrounds
    /// @brief      Verify that default List Photos Are Bundled And Respect Custom Backgrounds
    /// @details    Exercises `CollectionBackground.defaultListBackground`, `CollectionBackground.isAllowed`. Checks
    ///             `XCTAssertEqual(CollectionBackground.defaultListBackground(for: title)?.preset, preset)`;
    ///             `XCTAssertNotNil(UIImage(named: asset))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDefaultListPhotosAreBundledAndRespectCustomBackgrounds() throws {
        for (title, preset, asset) in [("On the Table", CollectionBackgroundPreset.tabletop, "DefaultListTable"), ("In the Queue", .forestPath, "DefaultListQueue"), ("Scheduled", .sunlitWall, "DefaultListScheduled")] {
            XCTAssertEqual(CollectionBackground.defaultListBackground(for: title)?.preset, preset)
            XCTAssertNotNil(UIImage(named: asset))
            for override in [CollectionBackground(preset: .plain), CollectionBackground(preset: .photo, photoFileName: "my-photo.jpg"), CollectionBackground(preset: .sage)] {
                XCTAssertEqual(CollectionBackground.defaultListBackground(for: title, overriding: override), override)
            }
            let saved = CollectionBackground(preset: preset)
            XCTAssertEqual(try JSONDecoder().decode(CollectionBackground.self, from: JSONEncoder().encode(saved)), saved)
        }
        XCTAssertNil(CollectionBackground.defaultListBackground(for: "Monday"))
        XCTAssertNil(CollectionBackground.defaultListBackground(for: "My own List"))
        XCTAssertFalse(CollectionBackground.isAllowed(collectionID: UUID(), datedWeekIDs: [], isDatedView: true))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReferenceLabelSupportsLegacyAndExistingCustomCatalogs
    /// @brief      Verify that reference Label Supports Legacy And Existing Custom Catalogs
    /// @details    Checks `XCTAssertEqual(legacy.includingReference.labels, [LabelLibrary.referenceLabel])`;
    ///             `XCTAssertEqual(library.includingReference.labels, [custom])`.
    ///
    /// @return     (Void) no return value
    ///
    func testReferenceLabelSupportsLegacyAndExistingCustomCatalogs() {
        let legacy = LabelLibrary(categories: [], labels: [])
        XCTAssertEqual(legacy.includingReference.labels, [LabelLibrary.referenceLabel])
        let custom = KanbanLabel(id: "my-reference", name: "Reference", categoryID: "custom", color: .blue)
        let library = LabelLibrary(categories: [], labels: [custom])
        XCTAssertEqual(library.includingReference.labels, [custom])
        XCTAssertEqual(library.includingReference.referenceLabelID, custom.id)
        XCTAssertEqual(LabelLibrary.starter.includingReference, LabelLibrary.starter)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedSessionGuidanceUsesEntrySnapshotAndSurvivesListEdits
    /// @brief      Verify delayed guidance is tied to the visit rather than live emptiness
    /// @details    Hosts the real guidance view, changes its List after reveal, and opens a new
    ///             nonempty visit to check that later deletion cannot trigger guidance there.
    ///
    /// @return     (Void) records visit lifecycle assertions
    /// @throws     Propagates missing scene and asynchronous wait failures.
    ///
    @MainActor
    func testHostedSessionGuidanceUsesEntrySnapshotAndSurvivesListEdits() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        var list = KanbanList(id: 4, title: "In the Queue", cards: [])
        let labels = LabelLibraryStore.load()
        var reveals = 0
        var footerStates: [Bool] = []
        let host = UIHostingController(rootView: SessionListGuidance(list: list, labels: labels, onReveal: { reveals += 1 }, onPresentationChange: { footerStates.append($0) }))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        XCTAssertEqual(reveals, 0)
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertEqual(reveals, 1)
        XCTAssertEqual(footerStates, [false, true])
        list.cards = [KanbanCard(id: 10, word: "My task", listTitle: list.title)]
        host.rootView = SessionListGuidance(list: list, labels: labels, onReveal: { reveals += 1 }, onPresentationChange: { footerStates.append($0) })
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        list.cards = []
        host.rootView = SessionListGuidance(list: list, labels: labels, onReveal: { reveals += 1 }, onPresentationChange: { footerStates.append($0) })
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(reveals, 1)
        list.cards = [KanbanCard(id: 11, word: "Already here", listTitle: list.title)]
        let nextVisit = UIHostingController(rootView: SessionListGuidance(list: list, labels: labels, onReveal: { reveals += 1 }, onPresentationChange: { footerStates.append($0) }))
        window.rootViewController = nextVisit
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        list.cards = []
        nextVisit.rootView = SessionListGuidance(list: list, labels: labels, onReveal: { reveals += 1 }, onPresentationChange: { footerStates.append($0) })
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertEqual(reveals, 1)
        nextVisit.rootView = SessionListGuidance(list: list, labels: labels, onReveal: { reveals += 1 }, toggleRequest: 1, onPresentationChange: { footerStates.append($0) })
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(reveals, 2, "The header can show guidance even for a visit that opened nonempty")
        nextVisit.rootView = SessionListGuidance(list: list, labels: labels, onReveal: { reveals += 1 }, toggleRequest: 2, onPresentationChange: { footerStates.append($0) })
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(reveals, 2, "Retraction must not trigger another reveal")
        XCTAssertEqual(footerStates.last, true, "Capture remains available while the guide retracts")
        nextVisit.rootView = SessionListGuidance(list: list, labels: labels, onReveal: { reveals += 1 }, toggleRequest: 3, onPresentationChange: { footerStates.append($0) })
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(reveals, 3, "Another header tap can reverse an in-progress retraction")
        XCTAssertEqual(Array(footerStates.suffix(3)), [true, true, true])
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
    func testSessionGuidanceMigrationPreservesCustomizedWelcomeCards() throws {
        let suite = "SessionGuidance." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for title in ["On the Table", "In the Queue", "Scheduled"] {
            let original = DefaultListTutorial.makeStarter(title: title, includesWelcomeCard: true)
            var edited = original
            edited.lists[0].cards[0].word += " personalized"
            var completed = original
            completed.lists[0].cards[0].isTitleChecked = true
            var bookmarked = original
            bookmarked.savedCardIDs.insert(0)
            for retained in [edited, completed, bookmarked] {
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
    func testStarterListTutorialsAreActionableAndOnlySeedTheThreeDefaultLists() throws {
        let titles = ["On the Table", "In the Queue", "Scheduled"]
        for title in titles {
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
        for title in ["Shopping", "Reminders", "Up for Brew", "Misc", "My custom list"] {
            XCTAssertTrue(DefaultListTutorial.makeStarter(title: title).lists[0].cards.isEmpty)
        }
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
    func testDefaultListsDoNotReplaceExistingOrLegacyInstallations() throws {
        for savedKey in ["Plenact.PersonalCollections.v1", "Plenact.Board.v1", PlanningCalendarStore.key, TodayListPins.key] {
            let suite = "Plenact.ExistingInstallTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let saved = Data("preserve saved bytes".utf8)
            defaults.set(saved, forKey: savedKey)
            XCTAssertTrue(TodayListPins.loadInitialCollections(from: defaults).isEmpty)
            XCTAssertEqual(defaults.data(forKey: savedKey), saved)
        }
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
    func testImportantIndicatorUsesCollectionAndCardIdentity() throws {
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
    /// @fcn        PlenactBoardDocumentTests.testWorkspaceLabelsCountOnlyActiveItemsAndKeepOwnerIdentity
    /// @brief      Verify that workspace Labels Count Only Active Items And Keep Owner Identity
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `card.replacingLocation`. Checks
    ///             `XCTAssertEqual(usage.matches.count, 2)`; `XCTAssertEqual(Set(usage.matches.map(\.collectionID)),
    ///             [week.id, library.id])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWorkspaceLabelsCountOnlyActiveItemsAndKeepOwnerIdentity() throws {
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
        let usage = try XCTUnwrap(WorkspaceBrowseIndex.labels(in: owners, catalog: catalog).first { $0.id == label.id })
        XCTAssertEqual(usage.matches.count, 2)
        XCTAssertEqual(Set(usage.matches.map(\.collectionID)), [week.id, library.id])
        XCTAssertEqual(Set(usage.matches.map(\.id)).count, 2, "Identical numeric IDs in different owners stay distinct")
        XCTAssertEqual(usage.matches.filter { $0.card.presentation == .note }.count, 1)
        XCTAssertFalse(WorkspaceBrowseIndex.lists(in: owners).contains { $0.list.isArchived })
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
    func testTodayShortcutPinsKeepOrderOwnerAndSixItemLimit() {
        let first = WorkspaceListReference(ownerID: UUID(), listID: 0)
        let second = WorkspaceListReference(ownerID: UUID(), listID: 0)
        let extras = (1...8).map { WorkspaceListReference(ownerID: first.ownerID, listID: $0) }
        let pins = [first, second, first] + extras
        let decoded = TodayListPins.decode(TodayListPins.encode(pins))
        XCTAssertEqual(decoded.count, 6)
        XCTAssertEqual(Array(decoded.prefix(2)), [first, second])
        XCTAssertEqual(Set(decoded).count, 6)
        XCTAssertTrue(TodayListPins.decode(Data("invalid".utf8)).isEmpty)
        XCTAssertEqual(TodayListPins.decode(TodayListPins.encode(Array(decoded.reversed()))), Array(decoded.reversed()))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayShortcutGridRendersTwoRowsWithoutOpeningOrEditing
    /// @brief      Verify that today Shortcut Grid Renders Two Rows Without Opening Or Editing
    /// @details    Exercises `(0..<6).map`, `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`.
    ///             Uses the fixture and assertions below to verify today Shortcut Grid Renders Two Rows Without
    ///             Opening Or Editing.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayShortcutGridRendersTwoRowsWithoutOpeningOrEditing() async throws {
        var owner = PersonalCollection(title: "Projects", kind: .board)
        owner.lists = (0..<6).map { KanbanList(id: $0, title: ["On the Table", "Garden", "Shopping", "Reading", "Ideas", "Home"][$0], cards: []) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TodayShortcutGrid(pinned: WorkspaceBrowseIndex.lists(in: [owner]),
            onOpen: { _ in XCTFail("Rendering must not open a list") }).padding(20).background(Color(.systemGroupedBackground)))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 440)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-shortcuts-preview.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("Shortcuts preview: " + path.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayPlanRendersWithoutChangingStoredPlans
    /// @brief      Verify that today Plan Renders Without Changing Stored Plans
    /// @details    Exercises `UserDefaults.standard.dictionaryRepresentation().filter`,
    ///             `UserDefaults.standard.dictionaryRepresentation`, `$0.key.hasPrefix`. Checks
    ///             `XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayPlanRendersWithoutChangingStoredPlans() async throws {
        let before = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("Plenact.") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TodayPlanView())
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-today-plan.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("Today plan: " + path.path)
        let after = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("Plenact.") }
        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))
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
    func testSameDayDateOnlySchedulesDoNotRepeatTheListDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        var card = KanbanCard(id: 77, word: "Same-day task", listTitle: "My renamed day", startDate: day, dueDate: day,
            showsDueDateInList: true, startDateKind: .date, dueDateKind: .date)
        let original = card
        XCTAssertTrue(card.scheduleBadges(on: day, calendar: calendar).isEmpty)
        XCTAssertEqual(card, original, "Preview formatting must retain the editable dates")
        XCTAssertEqual(card.scheduleBadges(on: tomorrow, calendar: calendar).count, 2)
        XCTAssertFalse(card.scheduleBadges(on: nil, calendar: calendar).isEmpty, "Undated Lists still need date context")
        card.dueDate = nil
        XCTAssertTrue(card.scheduleBadges(on: day, calendar: calendar).isEmpty)
        card.startDate = nil; card.dueDate = day
        XCTAssertTrue(card.scheduleBadges(on: day, calendar: calendar).isEmpty)
        card.startDate = day; card.dueDate = tomorrow
        XCTAssertEqual(card.scheduleBadges(on: day, calendar: calendar).count, 2, "Cross-day ranges retain their dates")
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
    func testSameDayScheduleUsesTimesOnlyWithoutChangingStoredDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23, minute: 24)))
        let finish = try XCTUnwrap(calendar.date(byAdding: .minute, value: 21, to: start))
        var card = KanbanCard(id: 0, word: "Task", listTitle: "Renamed day", startDate: start, dueDate: finish,
                              showsDueDateInList: true, startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
        let original = card
        let badges = card.scheduleBadges(on: start, calendar: calendar)
        XCTAssertEqual(badges.map(\.title), ["Start", "Finish"])
        XCTAssertEqual(badges.map(\.systemImage), ["clock", "checkmark.circle"])
        XCTAssertEqual(badges.map(\.value), [CardDateKind.time.label(for: start), CardDateKind.time.label(for: finish)])
        XCTAssertEqual(card, original)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(card.scheduleBadges(on: tomorrow, calendar: calendar).map(\.title), ["Start date", "Due date"])
        XCTAssertEqual(card.scheduleBadges(on: nil, calendar: calendar).map(\.value), [card.dueDateLabel], "Undated Library previews retain their existing date display")
        card.dueDate = tomorrow
        XCTAssertEqual(card.scheduleBadges(on: start, calendar: calendar).map(\.title), ["Start date", "Due date"])
        card.dueDate = finish
        card.startDateKind = .date
        XCTAssertEqual(card.scheduleBadges(on: start, calendar: calendar).map(\.title), ["Start date", "Due date"])
        card.startDate = nil
        XCTAssertEqual(card.scheduleBadges(on: start, calendar: calendar).map(\.title), ["Finish"])
        card.showsDueDateInList = false
        XCTAssertTrue(card.scheduleBadges(on: start, calendar: calendar).isEmpty)
        XCTAssertTrue(card.usesTimeOnlySchedule(on: start, calendar: calendar), "Detail context must not depend on list badge visibility")
        XCTAssertFalse(card.usesTimeOnlySchedule(on: nil, calendar: calendar))
        XCTAssertFalse(card.usesTimeOnlySchedule(on: tomorrow, calendar: calendar))
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
    func testWeekCalendarGridAlignsRowsAcrossMonthsAndWeekStarts() throws {
        for firstWeekday in [1, 2] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday
            for key in ["2026-10-14", "2026-12-31", "2027-01-01", "2028-02-29"] {
                let date = try XCTUnwrap(PlanningDate.date(key, calendar: calendar))
                let days = PlanningWeekSelector.monthDays(date, calendar: calendar)
                XCTAssertEqual(days.count, 42)
                XCTAssertEqual(calendar.component(.weekday, from: days[0]), firstWeekday)
                for row in 0..<6 {
                    let keys = Set(days[(row * 7)..<(row * 7 + 7)].map { PlanningDate.weekKey($0, calendar: calendar) })
                    XCTAssertEqual(keys.count, 1)
                }
                let month = try XCTUnwrap(calendar.dateInterval(of: .month, for: date))
                let count = try XCTUnwrap(calendar.range(of: .day, in: .month, for: date)).count
                XCTAssertEqual(days.filter { month.contains($0) && $0 < month.end }.count, count)
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
    func testCalendarContentMatchesPlannedAndScheduledItemsAcrossWeekBoundaries() throws {
        for firstWeekday in [1, 2] {
            var calendar = Calendar.current; calendar.firstWeekday = firstWeekday
            let date = try XCTUnwrap(PlanningDate.date("2026-10-17", calendar: calendar))
            let nextDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
            var week = DatedPlanningWeek.make(for: date, calendar: calendar)
            let listID = try XCTUnwrap(week.list(on: date)?.id)
            let index = try XCTUnwrap(week.collection.lists.firstIndex { $0.id == listID })
            week.collection.lists[index].cards = [KanbanCard(id: 1, word: "Planned and scheduled", listTitle: "Saturday", startDate: date, dueDate: date, checklists: [], startDateKind: .date, dueDateKind: .date)]
            var library = PersonalCollection(title: "Scheduled", kind: .list)
            library.lists[0].cards = [
                KanbanCard(id: 1, word: "Note due tomorrow", listTitle: "Scheduled", dueDate: nextDate, checklists: [], presentation: .note, dueDateKind: .date),
                KanbanCard(id: 2, word: "Time only", listTitle: "Scheduled", startDate: date, dueDate: nextDate, checklists: [], startDateKind: .time, dueDateKind: .time),
                KanbanCard(id: 3, word: "Starts today", listTitle: "Scheduled", startDate: date, checklists: [], startDateKind: .dateAndTime)
            ]
            library.lists[0].archivedCards = [KanbanCard(id: 4, word: "Archived", listTitle: "Scheduled", dueDate: date, checklists: [], dueDateKind: .date)]
            let document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: firstWeekday, weeks: [week])
            let access = PlanningCalendarAccess(document: document, library: [library], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
            let sources = access.searchableItems
            let today = PlanningCalendarContent.items(on: date, document: document, sources: sources)
            XCTAssertEqual(Set(today.map { $0.card.word }), ["Planned and scheduled", "Starts today"])
            XCTAssertEqual(today.count, 2) // A Card with both dates and day membership still counts once.
            XCTAssertEqual(PlanningCalendarContent.items(on: nextDate, document: document, sources: sources).map { $0.card.word }, ["Note due tomorrow"])
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
    func testWeekCalendarPickerRendersSelectedWeekAndDay() async throws {
        let date = try XCTUnwrap(PlanningDate.date("2026-10-14"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        var week = DatedPlanningWeek.make(for: date, calendar: calendar)
        let index = try XCTUnwrap(week.collection.lists.firstIndex { $0.id == week.list(on: date)?.id })
        week.collection.lists[index].cards = [KanbanCard(id: 1, word: "Planned work", listTitle: "Wednesday", checklists: [])]
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
        let nextIndex = try XCTUnwrap(week.collection.lists.firstIndex { $0.id == week.list(on: tomorrow)?.id })
        week.collection.lists[nextIndex].cards = [KanbanCard(id: 2, word: "Tomorrow's work", listTitle: "Thursday", checklists: [])]
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 1, weeks: [week])
        let access = PlanningCalendarAccess(document: document, library: [], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: PlanningWeekSelector(initialDate: date, document: document, selectedWeekKey: week.startKey, sources: access.searchableItems) { _, _ in })
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 480)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-week-calendar-preview.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("Week calendar preview: " + path.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDetachListCreatesStandaloneLibraryCollectionWithoutCopying
    /// @brief      Verify that detach List Creates Standalone Library Collection Without Copying
    /// @details    Exercises `.linkedCard`, `CrossBoardListMovement.detach`. Checks
    ///             `XCTAssertEqual(collections.count, 2)`; `XCTAssertTrue(collections[0].lists.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDetachListCreatesStandaloneLibraryCollectionWithoutCopying() throws {
        for title in ["Week board", "Library board"] {
            var source = PersonalCollection(title: title, kind: .board, icon: .home, color: .green)
            var card = KanbanCard(id: 8, word: "Keep this note", listTitle: "Garden", descriptionOverride: "Original writing")
            card.displayFormat = .note
            card.checklists = [KanbanChecklist(title: "Link", items: [KanbanChecklistItem(title: "Archived", content: .linkedCard(cardID: 9))])]
            let archive = KanbanCard(id: 9, word: "Archived", listTitle: "Garden")
            var list = KanbanList(id: 4, title: "Garden", cards: [card], archivedCards: [archive], newItemPresentation: .note)
            list.subtitleOverride = "Seasonal notes"
            list.appearance = ItemAppearance(accent: .green)
            source.lists = [list]
            source.savedCardIDs = [8, 9]
            var collections = [source]
            let result = try CrossBoardListMovement.detach(listID: list.id, from: source.id, collections: &collections)
            XCTAssertEqual(collections.count, 2)
            XCTAssertTrue(collections[0].lists.isEmpty)
            XCTAssertTrue(collections[0].savedCardIDs.isEmpty)
            XCTAssertEqual(result.kind, .list)
            XCTAssertEqual(result.title, list.title)
            XCTAssertEqual(result.color, source.color)
            XCTAssertEqual(result.lists.count, 1)
            XCTAssertEqual(result.savedCardIDs, [8, 9])
            XCTAssertEqual(result.lists[0].id, list.id)
            XCTAssertEqual(result.lists[0].appearance, list.appearance)
            XCTAssertEqual(result.lists[0].subtitleOverride, list.subtitleOverride)
            XCTAssertEqual(result.lists[0].newItemPresentation, .note)
            XCTAssertEqual(result.lists[0].cards[0].descriptionOverride, card.descriptionOverride)
            XCTAssertEqual(result.lists[0].archivedCards, [archive])
            XCTAssertEqual(result.lists[0].cards[0].checklists[0].items[0].linkedCollectionID, result.id)
            XCTAssertEqual(try JSONDecoder().decode([PersonalCollection].self, from: JSONEncoder().encode(collections)), collections)
        }
        var empty = [PersonalCollection]()
        XCTAssertThrowsError(try CrossBoardListMovement.detach(listID: 4, from: UUID(), collections: &empty))
        XCTAssertTrue(empty.isEmpty)
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
    func testWholeListMovePreservesContentBookmarksAndCrossBoardLinks() throws {
        var first = KanbanCard(id: 1, word: "Garden plan", listTitle: "Ideas", descriptionOverride: "Keep all writing")
        first.displayFormat = .note
        first.checklists = [KanbanChecklist(title: "Links", items: [
            KanbanChecklistItem(title: "Internal archived card", content: .linkedCard(cardID: 2)),
            KanbanChecklistItem(title: "Stays on source board", content: .linkedCard(cardID: 99))])]
        let archived = KanbanCard(id: 2, word: "Archived", listTitle: "Ideas")
        var moving = KanbanList(id: 1, title: "Ideas", cards: [first], archivedCards: [archived], newItemPresentation: .note)
        moving.appearance = ItemAppearance(accent: .green)
        moving.subtitleOverride = "Keep list description"
        var source = PersonalCollection(title: "Week", kind: .board)
        var remaining = KanbanCard(id: 99, word: "Remaining", listTitle: "Other")
        remaining.checklists = [KanbanChecklist(title: "Link", items: [KanbanChecklistItem(title: "Moved note", content: .linkedCard(cardID: 1))])]
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
        let returned = try CrossBoardListMovement.move(listID: moved.id, from: target.id, to: source.id, collections: &boards)
        XCTAssertEqual(returned.cards[0].descriptionOverride, first.descriptionOverride)
        XCTAssertEqual(returned.archivedCards.count, 1)
        XCTAssertEqual(boards[1].lists.count, 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWholeListMoveRejectsUnavailableOrSameBoardWithoutMutation
    /// @brief      Verify that whole List Move Rejects Unavailable Or Same Board Without Mutation
    /// @details    Exercises `CrossBoardListMovement.move`. Checks `XCTAssertThrowsError(try
    ///             CrossBoardListMovement.move(listID: 4, from: source.id, to: destination, collections: &boards))`;
    ///             `XCTAssertEqual(boards, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testWholeListMoveRejectsUnavailableOrSameBoardWithoutMutation() throws {
        var source = PersonalCollection(title: "Source", kind: .board)
        source.lists = [KanbanList(id: 4, title: "List", cards: [])]
        var archived = PersonalCollection(title: "Archived", kind: .board)
        archived.isArchived = true
        var boards = [source, archived]
        let original = boards
        for destination in [source.id, archived.id, UUID()] {
            XCTAssertThrowsError(try CrossBoardListMovement.move(listID: 4, from: source.id, to: destination, collections: &boards))
            XCTAssertEqual(boards, original)
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
    func testTransferToastIsVisibleWithoutTakingFocusOrInterceptingTouches() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let keyWindow = scene.windows.first(where: \.isKeyWindow)
        let presenter = TransferConfirmationPresenter.shared
        presenter.show(TransferConfirmation(title: "Sketch a garden path", destination: "Garden seasons / Ideas"))
        defer { presenter.dismiss() }
        try await Task.sleep(for: .milliseconds(300))
        let window = try XCTUnwrap(scene.windows.first { $0.windowLevel > .alert && !$0.isHidden })
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertTrue(scene.windows.first(where: \.isKeyWindow) === keyWindow)
        XCTAssertNil(window.hitTest(CGPoint(x: 100, y: window.bounds.height - 150), with: nil))
        let view = try XCTUnwrap(window.rootViewController?.view)
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-transfer-toast-preview.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("Transfer preview: " + path.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTransferConfirmationsNameDestinationAndDistinguishCopies
    /// @brief      Verify that transfer Confirmations Name Destination And Distinguish Copies
    /// @details    Checks `XCTAssertEqual(TransferConfirmation(title: "Garden path", destination: "Garden /
    ///             Ideas").message, "Moved ‘Garden path’ to Garden / Ideas.")`;
    ///             `XCTAssertEqual(TransferConfirmation(title: "My note", destination: "Journal").message, "Moved ‘My
    ///             note’ to Journal.")`.
    ///
    /// @return     (Void) no return value
    ///
    func testTransferConfirmationsNameDestinationAndDistinguishCopies() {
        XCTAssertEqual(TransferConfirmation(title: "Garden path", destination: "Garden / Ideas").message,
                       "Moved ‘Garden path’ to Garden / Ideas.")
        XCTAssertEqual(TransferConfirmation(title: "My note", destination: "Journal").message,
                       "Moved ‘My note’ to Journal.")
        XCTAssertEqual(TransferConfirmation(title: "Ideas", destination: "Home", action: .copied).message,
                       "Copied ‘Ideas’ to Home.")
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
    func testWelcomeCueLaunchAndFourHourReturnPolicy() {
        let name = "PlenactTests.WelcomePolicy." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cue = TodayWelcomeCue(defaults: defaults)
        cue.becameActive(at: start)
        XCTAssertTrue(cue.pending); XCTAssertEqual(cue.requestID, 1)
        cue.cancel()
        cue.becameActive(at: start.addingTimeInterval(1))
        XCTAssertFalse(cue.pending); XCTAssertEqual(cue.requestID, 1)
        cue.leftForeground(at: start)
        cue.leftForeground(at: start.addingTimeInterval(10)) // inactive → background records one departure
        XCTAssertEqual(defaults.double(forKey: TodayWelcomeCue.lastDepartureKey), start.timeIntervalSince1970)
        cue.becameActive(at: start.addingTimeInterval(TodayWelcomeCue.returnInterval - 1))
        XCTAssertFalse(cue.pending)
        cue.leftForeground(at: start)
        cue.becameActive(at: start.addingTimeInterval(TodayWelcomeCue.returnInterval))
        XCTAssertTrue(cue.pending); XCTAssertEqual(cue.requestID, 2)
        let freshProcess = TodayWelcomeCue(defaults: defaults)
        freshProcess.becameActive(at: start.addingTimeInterval(2))
        XCTAssertTrue(freshProcess.pending) // Every launch is intentionally testable.
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
    func testWelcomeCuePulsesInOrderAndSettlesWithoutRepeating() async {
        let cue = TodayWelcomeCue(defaults: UserDefaults(suiteName: "PlenactTests.WelcomeSequence")!)
        cue.becameActive()
        var highlights: [TodayWelcomeCue.Target] = []
        await cue.play(reduceMotion: false) { _ in
            if cue.illuminated, let target = cue.target { highlights.append(target) }
        }
        XCTAssertEqual(highlights, [.profile, .profile, .plan, .plan])
        XCTAssertNil(cue.target); XCTAssertFalse(cue.illuminated); XCTAssertFalse(cue.pending)
        await cue.play(reduceMotion: false) { _ in XCTFail("A completed greeting must not repeat") }
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
    func testWelcomeCueReduceMotionAndInteractionCancellation() async {
        let cue = TodayWelcomeCue(defaults: UserDefaults(suiteName: "PlenactTests.WelcomeCancellation")!)
        cue.becameActive()
        var highlights: [TodayWelcomeCue.Target] = []
        await cue.play(reduceMotion: true) { _ in
            if cue.illuminated, let target = cue.target { highlights.append(target) }
        }
        XCTAssertEqual(highlights, [.profile, .plan]) // One static highlight each, no repeated pulses.
        cue.leftForeground(at: .distantPast); cue.becameActive()
        highlights = []
        await cue.play(reduceMotion: false) { _ in
            if cue.illuminated, let target = cue.target { highlights.append(target); cue.cancel() }
        }
        XCTAssertEqual(highlights, [.profile])
        XCTAssertNil(cue.target); XCTAssertFalse(cue.illuminated)
        cue.leftForeground(at: .distantPast); cue.becameActive()
        await cue.play(reduceMotion: false) { _ in throw CancellationError() }
        XCTAssertNil(cue.target); XCTAssertFalse(cue.illuminated)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLaunchPacingRevealsEvenlyAndWaitsForReadiness
    /// @brief      Verify that launch Pacing Reveals Evenly And Waits For Readiness
    /// @details    Exercises `ready.paced`, `loading.paced(elapsed: 2).status`, `loading.paced`. Checks
    ///             `XCTAssertEqual(visual.stage, stage)`; `XCTAssertFalse(visual.finished)`.
    ///
    /// @return     (Void) no return value
    ///
    func testLaunchPacingRevealsEvenlyAndWaitsForReadiness() {
        let ready = PlenactLaunchProgress(stage: .welcome, finished: true)
        for (time, stage) in [(0.0, PlenactLaunchStage.restore), (0.23, .plans), (0.45, .ready), (0.67, .welcome)] {
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
    /// @fcn        PlenactBoardDocumentTests.testCreationSessionClearsLiveDraftAndRejectsDismissalCallbacks
    /// @brief      Verify that creation Session Clears Live Draft And Rejects Dismissal Callbacks
    /// @details    Exercises `ListCreationDraft.clear`, `draft.beginSession`, `draft.binding`. Checks
    ///             `XCTAssertEqual(ListCreationDraft.load(key: key).title, "New card")`; `XCTAssertEqual(draft.title,
    ///             "")`.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func testCreationSessionClearsLiveDraftAndRejectsDismissalCallbacks() {
        let key = "test.creation.reset." + UUID().uuidString
        defer { ListCreationDraft.clear(key: key) }
        let draft = ListCreationDraftModel(key: key)
        for _ in 0..<2 {
            draft.beginSession()
            draft.binding(\.title).wrappedValue = "New card"
            draft.binding(\.subtitle).wrappedValue = "Subtitle"
            draft.binding(\.description).wrappedValue = "Body"
            XCTAssertEqual(ListCreationDraft.load(key: key).title, "New card")
            draft.finishSession()
            draft.binding(\.description).wrappedValue = "Late editor callback"
            XCTAssertEqual(draft.title, "")
            XCTAssertEqual(draft.subtitle, "")
            XCTAssertEqual(draft.description, "")
            XCTAssertEqual(ListCreationDraft.load(key: key), ListCreationDraft())
            draft.beginSession()
            XCTAssertEqual(draft.title, "")
            XCTAssertEqual(draft.description, "")
        }
        draft.title = "Unsubmitted writing"
        draft.description = "Keep this draft"
        draft.beginSession()
        XCTAssertEqual(draft.title, "Unsubmitted writing")
        XCTAssertEqual(draft.description, "Keep this draft")
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
    func testLaunchProgressRevealsOnlyStartedStagesAndKeepsCompletedStagesSteady() {
        for stage in PlenactLaunchStage.allCases {
            let progress = PlenactLaunchProgress(stage: stage)
            for step in PlenactLaunchStage.allCases {
                XCTAssertEqual(progress.status(for: step), step.rawValue < stage.rawValue ? .complete : (step == stage ? .running : .waiting))
            }
        }
        let finished = PlenactLaunchProgress(stage: .welcome, finished: true)
        XCTAssertTrue(PlenactLaunchStage.allCases.allSatisfy { finished.status(for: $0) == .complete })
        XCTAssertEqual(PlenactLaunchStage.allCases.map(\.symbol), ["folder", "calendar", "slider.horizontal.3", "sun.max"])
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
    func testRichEditorDefersFocusAndIgnoresStaleRequests() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let textView = UITextView(frame: CGRect(x: 20, y: 100, width: 300, height: 150))
        window.rootViewController?.view.addSubview(textView)
        var requestedFocus = true
        var writing = "Review: Sketch a garden path"
        let parent = RichTextEditor(placeholder: "Description",
            text: Binding(get: { writing }, set: { writing = $0 }),
            focus: Binding(get: { requestedFocus }, set: { requestedFocus = $0 }))
        let coordinator = parent.makeCoordinator()
        textView.delegate = coordinator
        textView.attributedText = PlanRichText.attributed(writing)
        coordinator.scheduleFocusUpdate(textView)
        XCTAssertFalse(textView.isFirstResponder, "Focus must not change inside the SwiftUI update")
        requestedFocus = false
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(textView.isFirstResponder, "An obsolete description-focus request must not steal title focus")
        for _ in 0..<3 {
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
    /// @fcn        PlenactBoardDocumentTests.testDaySelectorResolvesDatesAcrossWeeksWithoutChangingContent
    /// @brief      Verify that day Selector Resolves Dates Across Weeks Without Changing Content
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `PlanningDate.key`. Checks
    ///             `XCTAssertEqual(selection.listID, dayID)`; `XCTAssertEqual(selection.week, week)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDaySelectorResolvesDatesAcrossWeeksWithoutChangingContent() throws {
        for firstWeekday in [1, 2] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday
            let date = try XCTUnwrap(PlanningDate.date("2026-10-13"))
            var week = DatedPlanningWeek.make(for: date, calendar: calendar)
            let dayID = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date, calendar: calendar)])
            let index = try XCTUnwrap(week.collection.lists.firstIndex { $0.id == dayID })
            week.collection.lists[index].cards = [KanbanCard(id: 333, word: "Selected day's content", listTitle: week.collection.lists[index].title)]
            let document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: firstWeekday, weeks: [week])
            let original = document
            let selection = try XCTUnwrap(PlanningDaySelection.resolve(date, document: document))
            XCTAssertEqual(selection.listID, dayID)
            XCTAssertEqual(selection.week, week)
            for offset in -9...9 {
                let target = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: date))
                let selected = try XCTUnwrap(PlanningDaySelection.resolve(target, document: document))
                XCTAssertEqual(selected.week.startKey, PlanningDate.weekKey(target, calendar: calendar))
                XCTAssertEqual(selected.week.dayListIDs[PlanningDate.key(target, calendar: calendar)], selected.listID)
                XCTAssertTrue(selected.week.collection.lists.contains { $0.id == selected.listID && !$0.isArchived })
            }
            XCTAssertEqual(document, original)
        }
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
    func testWeekSelectorPreservesStoredContentAndActiveWeek() throws {
        for firstWeekday in [1, 2] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday
            let date = try XCTUnwrap(PlanningDate.date("2026-10-13"))
            var current = DatedPlanningWeek.make(for: date, calendar: calendar)
            current.collection.lists[0].cards = [KanbanCard(id: 987, word: "Keep this writing", listTitle: current.collection.lists[0].title)]
            let document = PlanningCalendarDocument(currentWeekKey: current.startKey, firstWeekday: firstWeekday, weeks: [current])
            let original = document
            let choices = PlanningWeekSelector.choices(document: document, referenceDate: date)
            XCTAssertEqual(choices.count, 17)
            XCTAssertEqual(Set(choices.map(\.startKey)).count, choices.count)
            XCTAssertEqual(choices.first { $0.startKey == current.startKey }, current)
            XCTAssertTrue(choices.allSatisfy { PlanningDate.weekKey(PlanningDate.date($0.startKey)!, calendar: calendar) == $0.startKey })
            let future = try XCTUnwrap(calendar.date(byAdding: .month, value: 6, to: date))
            let futureChoices = PlanningWeekSelector.choices(document: document, referenceDate: future)
            XCTAssertTrue(futureChoices.contains { $0.startKey == PlanningDate.weekKey(future, calendar: calendar) })
            XCTAssertEqual(document, original)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLoadingScreenResourcesAndReducedMotionLayout
    /// @brief      Verify that loading Screen Resources And Reduced Motion Layout
    /// @details    Exercises `Bundle.main.url`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertNotNil(UIImage(named: "LaunchLogo"))`;
    ///             `XCTAssertNotNil(UIImage(named: "LaunchShadow"))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLoadingScreenResourcesAndReducedMotionLayout() async throws {
        XCTAssertNotNil(UIImage(named: "LaunchLogo"))
        XCTAssertNotNil(UIImage(named: "LaunchShadow"))
        XCTAssertNotNil(UIColor(named: "LaunchBackground"))
        XCTAssertNotNil(Bundle.main.url(forResource: "PlenactLaunch", withExtension: "storyboardc"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: PlenactLoadingView(animatesLogo: false))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(120))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let data = try XCTUnwrap(image.pngData())
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-loading-preview.png")
        try data.write(to: path)
        print("Loading preview: " + path.path)
        let launch = try XCTUnwrap(UIStoryboard(name: "PlenactLaunch", bundle: .main).instantiateInitialViewController())
        launch.loadViewIfNeeded()
        launch.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        launch.view.layoutIfNeeded()
        let staticImage = UIGraphicsImageRenderer(bounds: launch.view.bounds).image { context in
            launch.view.layer.render(in: context.cgContext)
        }
        let staticPath = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-static-launch-preview.png")
        try XCTUnwrap(staticImage.pngData()).write(to: staticPath)
        print("Static launch preview: " + staticPath.path)

        for size in [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393)] {
            let fitted = host.sizeThatFits(in: size)
            XCTAssertTrue(fitted.width.isFinite && fitted.height.isFinite)
            XCTAssertEqual(fitted.width, size.width, accuracy: 1)
            XCTAssertEqual(fitted.height, size.height, accuracy: 1)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverSearchMatchesTagsWithinTheSelectedAlbum
    /// @brief      Verify that cover Search Matches Tags Within The Selected Album
    /// @details    Exercises `ExampleCoverImage.search`, `ExampleCoverImage.search("quiet morning", in:
    ///             .rest).contains`, `ExampleCoverImage.search("WATER plants", in: .nature).contains`. Checks
    ///             `XCTAssertEqual(ExampleCoverImage.search("").count, 400)`;
    ///             `XCTAssertEqual(ExampleCoverImage.search(" ", in: .nature).count, 50)`.
    ///
    /// @return     (Void) no return value
    ///
    func testCoverSearchMatchesTagsWithinTheSelectedAlbum() {
        XCTAssertEqual(ExampleCoverImage.search("").count, 400)
        XCTAssertEqual(ExampleCoverImage.search("  ", in: .nature).count, 50)
        XCTAssertTrue(ExampleCoverImage.search("quiet morning", in: .rest).contains(.quietMorning))
        XCTAssertTrue(ExampleCoverImage.search("WATER plants", in: .nature).contains(.wateringPlants))
        XCTAssertTrue(ExampleCoverImage.search("guitar music", in: .creativity).contains(.guitarSession))
        XCTAssertTrue(ExampleCoverImage.search("computer desk", in: .work).contains(.workspace))
        XCTAssertTrue(ExampleCoverImage.search("running fitness", in: .health).contains(.runningRoute))
        XCTAssertTrue(ExampleCoverImage.search("running fitness", in: .food).isEmpty)
        XCTAssertTrue(ExampleCoverImage.search("unicorn submarines", in: .home).isEmpty)
        XCTAssertTrue(ExampleCoverImage.allCases.allSatisfy { (10...20).contains($0.tags.count) })
        let animals = ExampleCoverImage.search("animal")
        XCTAssertTrue(animals.contains(.petCare))
        XCTAssertTrue(animals.contains(.birdWatching))
        XCTAssertTrue(animals.contains(.butterfly))
        XCTAssertTrue(animals.contains(.honeyBees))
        XCTAssertFalse(animals.contains(.workspace))
        XCTAssertTrue(ExampleCoverImage.search("dogs").contains(.petCare))
        XCTAssertTrue(ExampleCoverImage.search("cat").contains(.petCare))
        XCTAssertFalse(ExampleCoverImage.search("cat").contains(.studyBooks))
        XCTAssertTrue(ExampleCoverImage.search("mood").contains(.peacefulBreath))
        XCTAssertTrue(ExampleCoverImage.search("mood").contains(.morningStretch))
        XCTAssertTrue(ExampleCoverImage.search("mood", in: .food).contains(.coffeeBreak))
        XCTAssertFalse(ExampleCoverImage.search("mood", in: .food).contains(.peacefulBreath))
        XCTAssertTrue(ExampleCoverImage.search("cats", in: .home).contains(.catCompanion))
        XCTAssertTrue(ExampleCoverImage.search("dogs", in: .home).contains(.dogWalk))
        XCTAssertTrue(ExampleCoverImage.search("wildlife", in: .nature).contains(.birdFeeder))
        XCTAssertTrue(ExampleCoverImage.search("mood", in: .rest).contains(.joyfulMoment))
        XCTAssertTrue(ExampleCoverImage.search("mental health", in: .health).contains(.mentalHealth))
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
    func testDirectCardAndNoteBackDismissesResultToItsPresenter() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for usesWeek in [false, true] {
            for isNote in [false, true] {
                var owner = PersonalCollection(title: "Return test", kind: .list)
                owner.lists[0].cards = [KanbanCard(id: 701, word: "Return item", listTitle: owner.title,
                    presentation: isNote ? .note : .card)]
                let date = try XCTUnwrap(PlanningDate.date("2026-10-15"))
                var week = DatedPlanningWeek.make(for: date)
                let listID = usesWeek ? week.collection.lists[0].id : owner.lists[0].id
                week.collection.lists[0].cards = owner.lists[0].cards
                let probe = DirectReturnTestProbe()
                let window = UIWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
                let host = UIHostingController(rootView: DirectReturnTestView(probe: probe, owner: owner,
                    week: usesWeek ? week : nil, listID: listID))
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                try await Task.sleep(for: .milliseconds(150))
                probe.presented = true
                var navigation: UINavigationController?
                for _ in 0..<40 {
                    navigation = findDetailNavigation(in: host)
                    if navigation != nil { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                let detail = try XCTUnwrap(navigation, "The requested item must open above its owning board")
                XCTAssertTrue(probe.presented)
                detail.popViewController(animated: false)
                for _ in 0..<30 {
                    if !probe.presented { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                XCTAssertFalse(probe.presented, "Back must dismiss the direct result for week=\(usesWeek), note=\(isNote)")
            }
        }
        previous?.makeKey()
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.findDetailNavigation
    /// @brief      Find a navigation controller containing a pushed detail view
    /// @details    Searches the supplied controller, its presented controller, and child controllers recursively;
    ///             returns nil when no detail navigation stack exists.
    ///
    /// @param[in]  controller  Native controller supplied to the lifecycle callback
    ///
    /// @return     (UINavigationController?) matching or resolved value, or nil when unavailable
    ///
    @MainActor
    private func findDetailNavigation(in controller: UIViewController) -> UINavigationController? {
        if let nav = controller as? UINavigationController, nav.viewControllers.count > 1 { return nav }
        if let presented = controller.presentedViewController, let found = findDetailNavigation(in: presented) { return found }
        for child in controller.children {
            if let found = findDetailNavigation(in: child) { return found }
        }
        return nil
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
    func testNoteNavigationReportsToolbarVisibilityAndRestoresOnReturn() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let probe = NoteNavigationProbe()
        let host = UIHostingController(rootView: NoteNavigationTestView(probe: probe))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(probe.noteIsVisible)
        probe.path = [KanbanCard(id: 1, word: "Note", listTitle: "Sunday", presentation: .note)]
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(probe.noteIsVisible, "A pushed Note must hide the app bar")
        probe.path = []
        for _ in 0..<20 {
            if !probe.noteIsVisible { break }
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
    func testChecklistTypeSwitchesPreserveInactiveContentAndIdentity() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/plan"))
        let detail = KanbanChecklistActionDetail(description: "My plan", checklists: [KanbanChecklist(title: "Steps", items: ["First", "Next"])], comments: [])
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
        XCTAssertEqual(try JSONDecoder().decode(KanbanChecklistItem.self, from: JSONEncoder().encode(switched)), switched)
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
    func testLegacyTypedChecklistItemsSeedRetainedPayloads() throws {
        let item = KanbanChecklistItem(title: "Linked", content: .linkedCard(cardID: 12))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        json.removeValue(forKey: "retainedCardID")
        let restored = try JSONDecoder().decode(KanbanChecklistItem.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.retainedCardID, 12)
        XCTAssertEqual(restored.content, .linkedCard(cardID: 12))
        json.removeValue(forKey: "content")
        XCTAssertEqual(try JSONDecoder().decode(KanbanChecklistItem.self, from: JSONSerialization.data(withJSONObject: json)).type, .standard)
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
    func testCompactProfileRendersSlimmerThanDetailedWithoutEditing() async throws {
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
        func row(_ compact: Bool) -> some View {
            KanbanCardView(card: card, height: compact ? 64 : 150, displaySettings: BoardDisplaySettings(),
                compactCards: compact, labelLibrary: .starter,
                onUpdateCard: { _ in XCTFail("Rendering must not edit content") },
                onDeleteCard: { XCTFail("Rendering must not delete") },
                onArchiveCard: { XCTFail("Rendering must not archive") },
                onToggle: { XCTFail("Rendering must not complete") })
        }
        let compact = UIHostingController(rootView: row(true))
        let detailed = UIHostingController(rootView: row(false))
        compact.safeAreaRegions = []; detailed.safeAreaRegions = []
        let compactSize = compact.sizeThatFits(in: CGSize(width: 300, height: 1000))
        let detailedSize = detailed.sizeThatFits(in: CGSize(width: 300, height: 1000))
        XCTAssertLessThan(compactSize.height, detailedSize.height)
        XCTAssertLessThanOrEqual(compactSize.height, 90)
        XCTAssertEqual(card, original)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let preview = UIHostingController(rootView: VStack(alignment: .leading, spacing: 16) {
            Text("Detailed").font(.headline)
            row(false)
            Text("Compact").font(.headline)
            row(true)
        }.padding(20).background(Color(.systemGroupedBackground)))
        preview.safeAreaRegions = []
        window.frame = CGRect(x: 0, y: 0, width: 340, height: 400)
        window.rootViewController = preview
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(200))
        preview.view.frame = window.bounds
        preview.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Detailed and Compact profiles"; attachment.lifetime = .keepAlways; add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-profile-preview.png")
        try image.pngData()?.write(to: url)
        print("PROFILE_PREVIEW_PATH=\(url.path)")
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
    func testCardDisplayProfilesResolveCardThenListThenBoard() throws {
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
    func testCardDisplayProfilesRoundTripWithoutChangingContent() throws {
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
        XCTAssertEqual(retained[0].appearance?.cardDetail, .compact, "Applying Board colors must keep List display profiles")
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
    func testBoardCardDetailPersistsAndDecodesLegacyAppearance() throws {
        let legacy = try JSONDecoder().decode(BoardAppearance.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.cardDetail)
        for detail in BoardCardDetail.allCases {
            var appearance = BoardAppearance()
            appearance.cardDetail = detail
            let data = try JSONEncoder().encode(appearance)
            XCTAssertEqual(try BoardAppearance.decodeWeek(data).cardDetail, detail)
            var collection = PersonalCollection(title: "Project", kind: .board)
            collection.boardAppearance = appearance
            XCTAssertEqual(try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection)).boardAppearance?.cardDetail, detail)
        }
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
    func testLibraryPlateRanksUrgencyAndExcludesCompletedArchivedAndUndatedItems() throws {
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
        func due(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: now)! }
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
        func task(_ id: Int, _ days: Int) -> KanbanCard {
            var card = KanbanCard(id: id, word: "Task \(id)", listTitle: "Projects", dueDate: due(days))
            card.isTitleChecked = false
            return card
        }
        var completed = task(5, -4); completed.isTitleChecked = true
        var timeOnly = task(6, -5); timeOnly.dueDateKind = .time
        let normal = KanbanCard(id: 7, word: "No deadline", listTitle: "Projects")
        collection.lists[0].cards = [important, task(2, 2), task(3, 0), task(4, -1), completed, timeOnly, normal, task(8, 30)]
        let marked = [LibraryRecentItem(collectionID: collection.id, cardID: 1)]
        let selected = LibraryPlateSelection.items(in: [collection], important: marked, now: now)
        XCTAssertEqual(selected.map(\.card.id), [4, 3, 2, 1])
        XCTAssertEqual(selected.map(\.rank), [0, 1, 2, 3])
        collection.lists[0].cards.append(task(9, -2))
        XCTAssertEqual(LibraryPlateSelection.items(in: [collection], important: marked, now: now).map(\.card.id), [9, 4, 3, 2])
        collection.lists[0].isArchived = true
        XCTAssertTrue(LibraryPlateSelection.items(in: [collection], important: marked, now: now).isEmpty)
        collection.lists[0].isArchived = false
        collection.isArchived = true
        XCTAssertTrue(LibraryPlateSelection.items(in: [collection], important: marked, now: now).isEmpty)
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
    func testActivityHistoryRetainsOwnersBoundsAndClearsOnlyShortcuts() throws {
        let suite = "ActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LibraryRecentItem(collectionID: UUID(), cardID: 1)
        let week = LibraryRecentItem(collectionID: UUID(), cardID: 1)
        _ = LibraryRecentStore.remember(library, defaults: defaults)
        ActivityRecentStore.remember(week, defaults: defaults)
        ActivityRecentStore.remember(library, defaults: defaults)
        XCTAssertEqual(ActivityRecentStore.load(from: defaults), [library, week])
        for id in 2...30 { ActivityRecentStore.remember(LibraryRecentItem(collectionID: week.collectionID, cardID: id), defaults: defaults) }
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
    func testLibraryRecentsPersistDeduplicateAndKeepCollectionsSeparate() throws {
        let suite = "LibraryRecentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = LibraryRecentItem(collectionID: UUID(), cardID: 1)
        let second = LibraryRecentItem(collectionID: UUID(), cardID: 1)
        _ = LibraryRecentStore.remember(first, defaults: defaults)
        _ = LibraryRecentStore.remember(second, defaults: defaults)
        XCTAssertEqual(LibraryRecentStore.remember(first, defaults: defaults), [first, second])
        XCTAssertEqual(LibraryRecentStore.load(from: defaults), [first, second])
        for id in 2...12 { _ = LibraryRecentStore.remember(LibraryRecentItem(collectionID: first.collectionID, cardID: id), defaults: defaults) }
        XCTAssertEqual(LibraryRecentStore.load(from: defaults).count, 8)
        XCTAssertEqual(LibraryRecentStore.load(from: defaults).first?.cardID, 12)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekTodayHighlightRendersInPanoramicWithoutChangingCards
    /// @brief      Verify that week Today Highlight Renders In Panoramic Without Changing Cards
    /// @details    Exercises `DatedPlanningWeek.make`, `PlanningDate.key`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks
    ///             `XCTAssertEqual(access.document.weeks[0], week)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testWeekTodayHighlightRendersInPanoramicWithoutChangingCards() async throws {
        let date = Date.now
        let week = DatedPlanningWeek.make(for: date)
        let target = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date)])
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let owner = UUID()
        let key = BoardViewportMemory.prefix + owner.uuidString
        defer { UserDefaults.standard.removeObject(forKey: key) }
        var state = BoardViewportState()
        state.scale = 0.62; state.panoramic = true; state.presentation = BoardPresentation.standard.rawValue; state.visibleListID = target
        UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: key)
        let host = UIHostingController(rootView: ContentView(lists: .constant(week.collection.lists), boardTargetListID: .constant(target), onListsChanged: { _ in }, viewportOwnerID: owner).environment(\.planningCalendarAccess, access))
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-week-today-highlight.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("TODAY_HIGHLIGHT_RENDER=\(url.path)")
        XCTAssertEqual(access.document.weeks[0], week)
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
    func testWeekTodayHighlightUsesExactDateAcrossWeeksAndTimeZones() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let today = try XCTUnwrap(PlanningDate.date("2026-10-17", calendar: calendar))
        XCTAssertTrue(WeekDayHighlight.isToday(today, now: today, calendar: calendar))
        XCTAssertFalse(WeekDayHighlight.isToday(nil, now: today, calendar: calendar))
        for key in ["2026-10-10", "2026-10-16", "2026-10-18", "2026-10-24"] {
            XCTAssertFalse(WeekDayHighlight.isToday(PlanningDate.date(key, calendar: calendar), now: today, calendar: calendar))
        }
        let beforeMidnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23, minute: 59)))
        let afterMidnight = try XCTUnwrap(calendar.date(byAdding: .minute, value: 2, to: beforeMidnight))
        XCTAssertTrue(WeekDayHighlight.isToday(today, now: beforeMidnight, calendar: calendar))
        XCTAssertFalse(WeekDayHighlight.isToday(today, now: afterMidnight, calendar: calendar))
        XCTAssertTrue(WeekDayHighlight.isToday(PlanningDate.date("2026-10-18", calendar: calendar), now: afterMidnight, calendar: calendar))
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
    func testTabletTodayPlanSummaryRendersSavedAndEmptyStatesWithoutWriting() async throws {
        let name = "PlenactTests.TodaySummary." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let date = Date.now
        let week = DatedPlanningWeek.make(for: date)
        var table = PersonalCollection(title: "On the Table", kind: .list)
        table.lists[0].cards = [
            KanbanCard(id: 0, word: "Finish a meaningful step", listTitle: table.title, isTitleChecked: true, checklists: []),
            KanbanCard(id: 1, word: "Make room for a walk", listTitle: table.title, checklists: []),
            KanbanCard(id: 2, word: "Ideas for later", listTitle: table.title, checklists: [], presentation: .note)
        ]
        let access = PlanningCalendarAccess(document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [table], saveWeek: { _ in false }, openCurrentWeek: {}, openToday: {}, openLibraryCard: { _ in }, saveLibrary: { _ in false })
        let sources = access.searchableItems
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        var opens = 0
        for saved in [false, true] {
            if saved {
                var plan = DailyPlan(date: date)
                plan.intention = "A little focus, with room to breathe"
                plan.priorities = sources.map(DailyPlanPriority.init)
                plan.checkIn = DailyCheckIn(focus: plan.priorities.first { $0.title == "Make room for a walk" }, changed: "", savedAt: .now)
                _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
            }
            let before = defaults.data(forKey: DailyPlanStore.key)
            let host = UIHostingController(rootView: TodayPlanSummaryPanel(date: date, calendar: .current, sources: sources, defaults: defaults, onOpen: { opens += 1 }).padding(24).background(Color(.systemGroupedBackground)))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-today-summary-\(saved).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("TODAY_SUMMARY_RENDER=\(url.path)")
            XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), before)
        }
        XCTAssertEqual(opens, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTabletBoardRendersProportionalLists
    /// @brief      Verify that tablet Board Renders Proportional Lists
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Uses the fixture and assertions below to verify tablet Board
    ///             Renders Proportional Lists.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTabletBoardRendersProportionalLists() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let owner = UUID()
        let fixture = ["Monday", "Tuesday", "Wednesday"].enumerated().map { index, title in
            KanbanList(id: index, title: title, cards: (0..<6).map { number in
                KanbanCard(id: index * 10 + number, word: "Take one useful step", listTitle: title, checklists: [])
            })
        }
        let host = UIHostingController(rootView: ContentView(lists: .constant(fixture), onListsChanged: { _ in }, viewportOwnerID: owner))
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-tablet-board-scale.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("TABLET_BOARD_RENDER=\(url.path)")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTabletStandardZoomPreservesProportionsAndNeighborPreviews
    /// @brief      Verify that tablet Standard Zoom Preserves Proportions And Neighbor Previews
    /// @details    Exercises `BoardPresentation.standard.columnWidth`, `BoardTabletSizing.scale`. Checks
    ///             `XCTAssertGreaterThan(scale, 1)`; `XCTAssertEqual(preview, viewport * 0.05 + 13.5)`.
    ///
    /// @return     (Void) no return value
    ///
    func testTabletStandardZoomPreservesProportionsAndNeighborPreviews() {
        for viewport: CGFloat in [744, 820, 1180] {
            let column = BoardPresentation.standard.columnWidth(viewportWidth: viewport, accessibilitySize: false)
            let scale = BoardTabletSizing.scale(viewportWidth: viewport, columnWidth: column, isTablet: true, enabled: true)
            XCTAssertGreaterThan(scale, 1)
            let preview = (viewport - column * scale) / 2 - 17 * scale
            XCTAssertEqual(preview, viewport * 0.05 + 13.5, accuracy: 0.01)
            XCTAssertEqual(column * scale / column, scale, accuracy: 0.001)
        }
        XCTAssertEqual(BoardTabletSizing.scale(viewportWidth: 852, columnWidth: 360, isTablet: false, enabled: true), 1)
        XCTAssertEqual(BoardTabletSizing.scale(viewportWidth: 820, columnWidth: 792, isTablet: true, enabled: false), 1)
        XCTAssertEqual(BoardTabletSizing.scale(viewportWidth: 320, columnWidth: 256, isTablet: true, enabled: true), 1)
        XCTAssertEqual(BoardTabletSizing.scale(viewportWidth: .infinity, columnWidth: 360, isTablet: true, enabled: true), 1)
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
    func testLegacyMondayFirstBoardUsesFollowingSundayWithoutRelabellingOldWork() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!; calendar.firstWeekday = 1
        let saturday = try XCTUnwrap(PlanningDate.date("2026-10-17", calendar: calendar))
        let oldSunday = try XCTUnwrap(PlanningDate.date("2026-10-11", calendar: calendar))
        let nextSunday = try XCTUnwrap(PlanningDate.date("2026-10-18", calendar: calendar))
        let titles = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let lists = titles.enumerated().map { KanbanList(id: $0.offset, title: $0.element, cards: []) }
        var legacy = DatedPlanningWeek.make(for: saturday, lists: lists, calendar: calendar)
        legacy.collection.lists[6].cards = [KanbanCard(id: 42, word: "October 11 work", listTitle: "Sunday", checklists: [])]
        var document = PlanningCalendarDocument(currentWeekKey: legacy.startKey, firstWeekday: 1, weeks: [legacy])
        XCTAssertTrue(try document.repairLegacyMondayFirstLayout(now: saturday))
        XCTAssertEqual(document.firstWeekday, 2)
        XCTAssertEqual(document.currentWeekKey, "2026-10-12")
        let current = try XCTUnwrap(document.week(for: saturday))
        XCTAssertEqual(current.collection.lists.map(\.title), titles)
        XCTAssertEqual(current.dayListIDs.first { $0.value == current.collection.lists[5].id }?.key, "2026-10-17")
        XCTAssertEqual(current.dayListIDs.first { $0.value == current.collection.lists[6].id }?.key, "2026-10-18")
        XCTAssertTrue(try XCTUnwrap(current.list(on: nextSunday)).cards.isEmpty)
        XCTAssertEqual(document.week(for: oldSunday)?.list(on: oldSunday)?.cards.first?.word, "October 11 work")
        XCTAssertFalse(try document.repairLegacyMondayFirstLayout(now: saturday))
        var sundayFirst = PlanningCalendarDocument(currentWeekKey: legacy.startKey, firstWeekday: 1, weeks: [DatedPlanningWeek.make(for: saturday, calendar: calendar)])
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
    func testMondayStartOnSundayKeepsConsecutiveDatesAndFollowingSundaySeparate() throws {
        let today = try XCTUnwrap(PlanningDate.date("2026-10-11"))
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        var original = DatedPlanningWeek.make(for: today, calendar: calendar)
        let sundayID = try XCTUnwrap(original.list(on: today)?.id)
        let index = try XCTUnwrap(original.collection.lists.firstIndex { $0.id == sundayID })
        original.collection.lists[index].cards = [KanbanCard(id: 42, word: "October 11 plans", listTitle: "Sunday")]
        var document = PlanningCalendarDocument(currentWeekKey: original.startKey, firstWeekday: 1, weeks: [original])
        try document.changeFirstWeekday(to: 2, now: today)
        let current = try XCTUnwrap(document.week(for: today))
        XCTAssertEqual(document.currentWeekKey, "2026-10-05")
        XCTAssertEqual(current.startKey, "2026-10-05")
        let dates = try current.collection.lists.map { list in
            try XCTUnwrap(current.dayListIDs.first { $0.value == list.id }?.key)
        }
        XCTAssertEqual(dates, ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11"])
        XCTAssertEqual(current.collection.lists.last?.cards.first?.word, "October 11 plans")
        let followingSunday = try XCTUnwrap(PlanningDate.date("2026-10-18"))
        let following = try XCTUnwrap(document.week(for: followingSunday))
        XCTAssertEqual(following.startKey, "2026-10-12")
        XCTAssertTrue(try XCTUnwrap(following.list(on: followingSunday)).cards.isEmpty)
        XCTAssertEqual(following.dayListIDs.count, 7)
        XCTAssertFalse(following.dayListIDs.keys.contains("2026-10-11"))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewCardDraftFieldsRemainEditableWhileSaving
    /// @brief      Verify that new Card Draft Fields Remain Editable While Saving
    /// @details    Exercises `ListCreationDraft.clear`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertTrue(subtitle.becomeFirstResponder())`;
    ///             `XCTAssertTrue(subtitle.isFirstResponder)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testNewCardDraftFieldsRemainEditableWhileSaving() async throws {
        let key = "plenact.testDraft.\(UUID().uuidString)"
        defer { ListCreationDraft.clear(key: key) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ListItemComposer(list: KanbanList(id: 1, title: "List", cards: []), draftKey: key) { _ in true })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(200))


        ///
        /// @fcn        PlenactBoardDocumentTests.testNewCardDraftFieldsRemainEditableWhileSaving.editors
        /// @brief      Find editors in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UITextView]) resulting values in the ordering described above
        ///
        func editors(_ view: UIView) -> [UITextView] {
            (view as? UITextView).map { [$0] } ?? view.subviews.flatMap { editors($0) }
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testNewCardDraftFieldsRemainEditableWhileSaving.fields
        /// @brief      Find fields in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextField. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UITextField]) resulting values in the ordering described above
        ///
        func fields(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
        }
        let subtitle = try XCTUnwrap(fields(host.view).first(where: { $0.placeholder == "Subtitle (optional)" }))
        XCTAssertTrue(subtitle.becomeFirstResponder())
        subtitle.text = "Subtitle"
        subtitle.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(subtitle.isFirstResponder)
        XCTAssertEqual(ListCreationDraft.load(key: key).subtitle, "Subtitle")
        let description = try XCTUnwrap(editors(host.view).first(where: { $0.accessibilityLabel == "Details (optional)" }))
        XCTAssertTrue(description.becomeFirstResponder())
        for character in ["A", "B", "C"] {
            description.insertText(character)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(description.isFirstResponder)
        }
        XCTAssertEqual(PlanRichText.plain(ListCreationDraft.load(key: key).description), "ABC")
        let restored = ListCreationDraftModel(key: key)
        XCTAssertEqual(restored.subtitle, "Subtitle")
        XCTAssertEqual(PlanRichText.plain(restored.description), "ABC")
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
    func testListCreationDraftSurvivesRecreationAndStaysInItsCollection() throws {
        let suite = "ListDraftTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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
    /// @fcn        PlenactBoardDocumentTests.testDueBadgeOmitsOnlyTheOwningListsAssignedDay
    /// @brief      Verify that due Badge Omits Only The Owning Lists Assigned Day
    /// @details    Exercises `card.dueDateBadge`. Checks `XCTAssertNil(card.dueDateBadge(on: sameDay))`;
    ///             `XCTAssertEqual(card.dueDateBadge(on: nextWeek)?.label, card.dueDateLabel)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDueBadgeOmitsOnlyTheOwningListsAssignedDay() throws {
        let calendar = Calendar.current
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 17, minute: 46)))
        let sameDay = calendar.startOfDay(for: due)
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: sameDay))
        var card = KanbanCard(id: 0, word: "Task", listTitle: "Renamed list", dueDate: due,
                             showsDueDateInList: true, dueDateKind: .date)
        XCTAssertNil(card.dueDateBadge(on: sameDay))
        XCTAssertEqual(card.dueDateBadge(on: nextWeek)?.label, card.dueDateLabel)
        XCTAssertEqual(card.dueDateBadge(on: nil)?.systemImage, "calendar", "Undated Library lists retain the full date")
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
    /// @fcn        PlenactBoardDocumentTests.testCardDateKindsPersistAndCopyWithoutInventingDates
    /// @brief      Verify that card Date Kinds Persist And Copy Without Inventing Dates
    /// @details    Exercises `decoded.startDateLabel.contains`, `decoded.listDueDateLabel?.contains`,
    ///             `decoded.dueDateLabel.contains`. Checks `XCTAssertEqual(decoded.startDateKind, kind)`;
    ///             `XCTAssertEqual(decoded.dueDateKind, kind)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCardDateKindsPersistAndCopyWithoutInventingDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 20, minute: 45)))
        for kind in CardDateKind.allCases {
            var card = KanbanCard(id: 1, word: "Scheduled", listTitle: "Monday", startDate: date, dueDate: date,
                                 showsDueDateInList: true, startDateKind: kind, dueDateKind: kind)
            let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
            XCTAssertEqual(decoded.startDateKind, kind)
            XCTAssertEqual(decoded.dueDateKind, kind)
            XCTAssertEqual(decoded.startDate, date)
            XCTAssertEqual(decoded.dueDate, date)
            if kind.includesTime {
                XCTAssertTrue(decoded.startDateLabel.contains("8:45 PM"))
                XCTAssertTrue(decoded.listDueDateLabel?.contains("8:45 PM") ?? false)
            } else { XCTAssertFalse(decoded.dueDateLabel.contains("PM")) }
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
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(KanbanCard(id: 0, word: "Legacy", listTitle: "Monday", dueDate: date))) as? [String: Any])
        legacy.removeValue(forKey: "startDateKind"); legacy.removeValue(forKey: "dueDateKind")
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.startDateKind, .date)
        XCTAssertEqual(decoded.dueDateKind, .date)
        XCTAssertFalse(decoded.dueDateLabel.contains("PM"))
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
    func testDateTimeEditorOpeningDoesNotSaveDraft() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var saves = 0
        let host = UIHostingController(rootView: CardDateEditorSheet(title: "Due date", date: nil, kind: .dateAndTime) { _, _ in saves += 1; return true })
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(saves, 0, "Opening a date draft must not create a stored date")
        XCTAssertGreaterThan(host.view.bounds.height, 0)
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
    func testDueDateVisibilityRequiresAStoredDateAndPreservesCardPreference() throws {
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
        let decodedLegacy = try JSONDecoder().decode(KanbanCard.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decodedLegacy.showsDueDateInList)
        XCTAssertEqual(decodedLegacy.listDueDateLabel, restored.dueDateLabel)
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
    func testNewCardDueDateDefaultPreferencesPersistAndLegacyDefaultsToTrue() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile.preferences)) as? [String: Any])
        legacy.removeValue(forKey: "showsDueDatesOnNewCards")
        let decoded = try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decoded.showsDueDatesOnNewCards)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardCommentComposerKeepsKeyboardFocusWhileTyping
    /// @brief      Verify that card Comment Composer Keeps Keyboard Focus While Typing
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertTrue(comment.becomeFirstResponder())`;
    ///             `XCTAssertTrue(comment.isFirstResponder, "Comment typing must not dismiss the keyboard")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCardCommentComposerKeepsKeyboardFocusWhileTyping() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var card = KanbanCard(id: 42, word: "Comment focus", listTitle: "Monday", checklists: [], comments: [], descriptionOverride: "Description")
        card.sectionLayout = CardSectionLayout(order: [.description, .activity], hidden: [.quickActions, .media, .details, .checklists])
        let host = UIHostingController(rootView: CardDetailView(card: card))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))


        ///
        /// @fcn        PlenactBoardDocumentTests.testCardCommentComposerKeepsKeyboardFocusWhileTyping.findComment
        /// @brief      Find find comment in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextView. Returns the first qualifying match, or
        ///             nil when none is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UITextView?) matching or resolved value, or nil when unavailable
        ///
        func findComment(_ view: UIView) -> UITextView? {
            if let text = view as? UITextView, text.accessibilityLabel == "Comment..." { return text }
            return view.subviews.lazy.compactMap { findComment($0) }.first
        }
        let comment = try XCTUnwrap(findComment(host.view))
        XCTAssertTrue(comment.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(100))
        for character in ["H", "e", "l", "l", "o"] {
            comment.insertText(character)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(comment.isFirstResponder, "Comment typing must not dismiss the keyboard")
            XCTAssertTrue(findComment(host.view) === comment, "The composer must retain its view identity")
        }
        XCTAssertEqual(comment.text, "Hello")
        comment.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(comment.isFirstResponder, "Explicit keyboard dismissal must still work")
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
    func testWeekStartMigrationKeepsDatesArchivesBookmarksAndUniqueIDs() throws {
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
        func fill(_ week: inout DatedPlanningWeek) {
            for index in week.collection.lists.indices {
                let list = week.collection.lists[index]
                var card = list.makeItem(id: index, title: "\(week.startKey) \(list.title)", description: "Retained body", subtitle: "Retained subtitle")
                card.sectionLayout = CardSectionLayout(order: [.activity, .description], hidden: [.details])
                week.collection.lists[index].cards = [card]
            }
        }
        fill(&first); fill(&second)
        let link = KanbanChecklistItem(title: "Sunday link", content: .linkedCard(cardID: 0))
        second.collection.lists[1].cards[0].checklists = [KanbanChecklist(title: "Linked", items: [link])]
        first.explicitlySaved = true
        first.collection.lists[2].archivedCards = [first.collection.lists[2].makeItem(id: 100, title: "Archived note", presentationOverride: .note)]
        second.collection.savedCardIDs = [0]
        second.collection.lists.append(KanbanList(id: 20, title: "Undated extras", cards: []))
        let before = [first, second].flatMap { $0.collection.lists.flatMap(\.allCards) }
        var document = PlanningCalendarDocument(currentWeekKey: second.startKey, firstWeekday: 1, weeks: [first, second])
        try document.changeFirstWeekday(to: 2, now: today)
        XCTAssertEqual(document.currentWeekKey, "2026-10-05")
        XCTAssertEqual(document.calendar.firstWeekday, 2)
        let current = try XCTUnwrap(document.week(for: today))
        XCTAssertEqual(current.list(on: today)?.cards.first?.word, "2026-10-11 Sunday")
        XCTAssertEqual(current.collection.savedCardIDs, Set(current.list(on: today)!.cards.map(\.id)))
        XCTAssertEqual(current.collection.lists.first?.title, "Monday")
        XCTAssertEqual(current.collection.lists[6].title, "Sunday")
        let after = document.weeks.flatMap { $0.collection.lists.flatMap(\.allCards) }
        XCTAssertEqual(Set(after.map(\.word)), Set(before.map(\.word)))
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(Set(after.map(\.id)).count, after.count)
        for original in before {
            let migrated = try XCTUnwrap(after.first { $0.word == original.word })
            XCTAssertEqual(migrated.descriptionOverride, original.descriptionOverride)
            XCTAssertEqual(migrated.subtitleOverride, original.subtitleOverride)
            XCTAssertEqual(migrated.sectionLayout, original.sectionLayout)
            XCTAssertEqual(migrated.presentation, original.presentation)
        }
        for originalWeek in [first, second] {
            for (dateKey, listID) in originalWeek.dayListIDs {
                let date = try XCTUnwrap(PlanningDate.date(dateKey, calendar: sunday))
                let oldList = try XCTUnwrap(originalWeek.collection.lists.first { $0.id == listID })
                let newList = try XCTUnwrap(document.week(for: date)?.list(on: date))
                XCTAssertEqual(newList.cards.map(\.word), oldList.cards.map(\.word))
                XCTAssertEqual(newList.archivedCards.map(\.word), oldList.archivedCards.map(\.word))
            }
        }
        let owner = try XCTUnwrap(document.weeks.first { $0.id == second.id })
        XCTAssertEqual(document.checklistLinkWeeks?[link.id], current.id)
        XCTAssertEqual(owner.startKey, "2026-10-12")
        XCTAssertTrue(owner.collection.lists.contains { $0.title == "Undated extras" })
        let ownerIndex = try XCTUnwrap(document.weeks.firstIndex { $0.id == owner.id })
        let extrasIndex = try XCTUnwrap(document.weeks[ownerIndex].collection.lists.firstIndex { $0.title == "Undated extras" })
        document.weeks[ownerIndex].collection.lists[extrasIndex].cards = [KanbanCard(id: 0, word: "Imported ID collision", listTitle: "Undated extras")]
        try document.changeFirstWeekday(to: 1, now: today)
        let reunited = try XCTUnwrap(document.week(for: today))
        let monday = try XCTUnwrap(reunited.collection.lists.first { $0.title == "Monday" })
        XCTAssertEqual(monday.cards.first?.checklists.first?.items.first?.content, .linkedCard(cardID: reunited.list(on: today)!.cards[0].id))
        XCTAssertEqual(document.currentWeekKey, "2026-10-11")
        XCTAssertNil(document.checklistLinkWeeks?[link.id])
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
    /// @fcn        PlenactBoardDocumentTests.testMondayWeekStartAcrossYearBoundaryAndStoredReload
    /// @brief      Verify that monday Week Start Across Year Boundary And Stored Reload
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `document.changeFirstWeekday`. Checks
    ///             `XCTAssertEqual(document.currentWeekKey, "2026-12-28")`; `XCTAssertEqual(document.week(for:
    ///             date)?.collection.lists.first?.title, "Monday")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testMondayWeekStartAcrossYearBoundaryAndStoredReload() throws {
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
        defer { defaults.removeObject(forKey: PlanningCalendarStore.key) }
        try PlanningCalendarStore.save(document, to: defaults)
        XCTAssertEqual(try PlanningCalendarStore.load(from: defaults), document)
        let next = document.rollForward(to: try XCTUnwrap(PlanningDate.date("2027-01-04", calendar: calendar)), currentLists: document.week(for: date)!.collection.lists, saved: [])
        XCTAssertEqual(next.startKey, "2027-01-04")
        XCTAssertEqual(next.collection.lists.first?.title, "Monday")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardOptionsPopoverLayoutDoesNotInvokeDestructiveActions
    /// @brief      Verify that board Options Popover Layout Does Not Invoke Destructive Actions
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Uses the fixture and assertions below to verify board Options Popover Layout
    ///             Does Not Invoke Destructive Actions.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testBoardOptionsPopoverLayoutDoesNotInvokeDestructiveActions() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for size in [DynamicTypeSize.large, .accessibility3] {
            let menu = BoardOptionsPopover(canJumpFirst: true, canJumpLast: true, hasAppearance: true,
                canArchive: true, canDelete: true, deleteTitle: "Delete Board", hasGallery: true, canResetZoom: true) { _ in
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryWeekExampleCreatesIndependentDraftWithoutReplacingWeek
    /// @brief      Verify that library Week Example Creates Independent Draft Without Replacing Week
    /// @details    Exercises `PersonalCollection.exampleWeek`. Checks `XCTAssertEqual(first.kind, .board)`;
    ///             `XCTAssertEqual(first.lists, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testMixedListTemplatesRetainFormatsAndCreateIndependentDrafts
    /// @brief      Verify that mixed List Templates Retain Formats And Create Independent Drafts
    /// @details    Exercises `template.makeCollection`, `cards.map`, `cards.allSatisfy`. Checks
    ///             `XCTAssertNotEqual(draft.id, second.id)`; `XCTAssertNotEqual(draft.title, template.rawValue)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.planningTestCalendar
    /// @brief      Create the fixed calendar used by planning regression tests
    /// @details    Uses a Gregorian calendar in America/Chicago with Sunday as the first weekday so date and
    ///             daylight-saving assertions are reproducible.
    ///
    /// @return     (Calendar) result described by this operation's contract
    ///
    private func planningTestCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        return calendar
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningRolloverPreservesPreviousWeekAndReusesFuturePlans
    /// @brief      Verify that planning Rollover Preserves Previous Week And Reuses Future Plans
    /// @details    Exercises `PlanningDate.date`, `DatedPlanningWeek.make`, `future.list`. Checks
    ///             `XCTAssertEqual(next.id, future.id)`; `XCTAssertEqual(next.collection, future.collection)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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
    func testCollectionPreviewsPreferDescriptionsAndReadOlderCollections() throws {
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
        XCTAssertEqual(try JSONDecoder().decode(PersonalCollection.self, from: data).collectionDescription, collection.collectionDescription)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "collectionDescription")
        let decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.collectionDescription)
        XCTAssertEqual(decoded.contentPreview, "Garden plans · Desk project · Weekend ideas")
        collection.collectionDescription = "  "
        collection.lists[0].isArchived = true
        XCTAssertEqual(collection.contentPreview, "")
        for example in PersonalListExample.allCases {
            XCTAssertEqual(example.makeCollection(existingTitles: []).contentPreview, example.summary)
        }
        for template in MixedListTemplate.allCases {
            XCTAssertEqual(template.makeCollection(existingTitles: []).contentPreview, template.summary)
        }
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardZoomPresetsResetAfterPinchingFromEitherMode
    /// @brief      Verify that board Zoom Presets Reset After Pinching From Either Mode
    /// @details    Exercises `BoardPanoramicZoom.preset`, `BoardPanoramicZoom.scale`. Checks
    ///             `XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: false), 1)`;
    ///             `XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: true), 0.62)`.
    ///
    /// @return     (Void) no return value
    ///
    func testBoardZoomPresetsResetAfterPinchingFromEitherMode() {
        XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: false), 1)
        XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: true), 0.62)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 1, magnification: 0.5), 0.5)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 1, magnification: 2), 1.25)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 0.5), 0.31)
        XCTAssertEqual(BoardPanoramicZoom.preset(panoramic: false), 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPanoramicPinchZoomClampsAndReversesAtBothLimits
    /// @brief      Verify that panoramic Pinch Zoom Clamps And Reverses At Both Limits
    /// @details    Exercises `BoardPanoramicZoom.scale`, `BoardPanoramicZoom.clamped`,
    ///             `BoardPresentation.standard.columnWidth`. Checks `XCTAssertEqual(BoardPanoramicZoom.initial,
    ///             0.62)`; `XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 1.5), 0.93)`.
    ///
    /// @return     (Void) no return value
    ///
    func testPanoramicPinchZoomClampsAndReversesAtBothLimits() {
        XCTAssertEqual(BoardPanoramicZoom.initial, 0.62)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 1.5), 0.93, accuracy: 0.001)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 0.1), 0.25)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.62, magnification: 10), 1.25)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.25, magnification: 2), 0.5)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 1.25, magnification: 0.5), 0.625)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.8, magnification: .nan), 0.8)
        XCTAssertEqual(BoardPanoramicZoom.scale(start: 0.8, magnification: 0), 0.8)
        XCTAssertEqual(BoardPanoramicZoom.clamped(.infinity), BoardPanoramicZoom.initial)
        for viewport: CGFloat in [320, 393, 852] {
            let width = BoardPresentation.standard.columnWidth(viewportWidth: viewport, accessibilitySize: false)
            for scale in [BoardPanoramicZoom.minimum, BoardPanoramicZoom.initial, BoardPanoramicZoom.maximum] {
                XCTAssertGreaterThan(width * scale, 0)
                XCTAssertTrue((viewport / scale).isFinite)
            }
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
    func testRichBoardExamplesRemainIndependentAndResolveTheirInternalLinks() throws {
        let now = try XCTUnwrap(PlanningDate.date("2026-10-13"))
        for example in PersonalBoardExample.allCases {
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
            XCTAssertTrue(draft.lists.contains { !$0.archivedCards.isEmpty })
            XCTAssertFalse(draft.savedCardIDs.isEmpty)
            for card in all {
                if let cover = card.coverAttachment { XCTAssertNotNil(cover.exampleImage?.url) }
                for item in card.checklists.flatMap(\.items) {
                    if case .linkedCard(let target) = item.content {
                        XCTAssertTrue(ids.contains(target))
                        XCTAssertEqual(item.linkedCollectionID, draft.id)
                    }
                }
            }
            let active = draft.lists.filter { !$0.isArchived }
            if example == .life {
                XCTAssertEqual(active.count, 12)
                XCTAssertEqual(active.prefix(3).map { $0.cards.count }, [30, 28, 26])
                XCTAssertGreaterThan(active.flatMap(\.cards).filter { $0.coverAttachment != nil }.count, 60)
            }
            XCTAssertNotEqual(draft.id, example.makeCollection(existingTitles: [], now: now).id)
        }
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
    func testActivityDueSoonIncludesOverdueAndExcludesCompletedUndatedAndLaterItems() throws {
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
    /// @fcn        PlenactBoardDocumentTests.testGalleryGroupsPreserveItemOrderAndDividerIdentity
    /// @brief      Verify that gallery Groups Preserve Item Order And Divider Identity
    /// @details    Exercises `list.makeItem`, `BoardGalleryGroup.groups`, `groups.flatMap(\.cards).map`. Checks
    ///             `XCTAssertEqual(groups.flatMap(\.cards).map(\.id), [1, 3, 4, 6])`;
    ///             `XCTAssertEqual(groups.compactMap(\.divider).map(\.id), [2, 5])`.
    ///
    /// @return     (Void) no return value
    ///
    func testGalleryGroupsPreserveItemOrderAndDividerIdentity() {
        var list = KanbanList(id: 3, title: "Plans", cards: [])
        list.cards = [list.makeItem(id: 1, title: "First"), list.makeItem(id: 2, title: "--- Ideas"),
                      list.makeItem(id: 3, title: "A note", description: "Writing", presentationOverride: .note),
                      list.makeItem(id: 4, title: "A picture"), list.makeItem(id: 5, title: "--- Later"),
                      list.makeItem(id: 6, title: "Last")]
        list.cards[3].displayFormat = .picture
        let original = list
        let groups = BoardGalleryGroup.groups(in: list)
        XCTAssertEqual(groups.flatMap(\.cards).map(\.id), [1, 3, 4, 6])
        XCTAssertEqual(groups.compactMap(\.divider).map(\.id), [2, 5])
        XCTAssertEqual(groups.compactMap { $0.divider?.sectionHeading }, ["Ideas", "Later"])
        XCTAssertEqual(groups.flatMap { ($0.divider.map { [$0] } ?? []) + $0.cards }.map(\.id), list.cards.map(\.id))
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
    func testNamedDividersPreserveIdentityAndLegacySeparators() throws {
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
    func testLibraryBrowseFiltersScopeSearchAndExcludeArchivedCollections() {
        var list = PersonalCollection(title: "Reading", kind: .list)
        var board = PersonalCollection(title: "Projects", kind: .board)
        var archived = PersonalCollection(title: "Old", kind: .list)
        archived.isArchived = true
        list.lists[0].cards = [KanbanCard(id: 1, word: "Garden reference", listTitle: "Reading")]
        board.lists[0].cards = [KanbanCard(id: 1, word: "Garden project", listTitle: "Ideas")]
        let collections = [list, board, archived]
        XCTAssertEqual(collections.filter { LibraryBrowseFilter.all.includes($0) }.map(\.id), [list.id, board.id])
        XCTAssertEqual(collections.filter { LibraryBrowseFilter.lists.includes($0) }.map(\.id), [list.id])
        XCTAssertEqual(collections.filter { LibraryBrowseFilter.boards.includes($0) }.map(\.id), [board.id])
        for (filter, expected) in [(LibraryBrowseFilter.lists, list.id), (.boards, board.id)] {
            let results = LibrarySearchIndex.results(query: "garden", collections: collections.filter { filter.includes($0) }, labels: LabelLibraryStore.load())
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.ownerID, expected)
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
    func testLibrarySearchFindsNoteContentAndKeepsCollectionIdentity() throws {
        var first = PersonalCollection(title: "Garden", kind: .list)
        var second = PersonalCollection(title: "Home", kind: .list)
        let note = KanbanCard(id: 42, word: "Ideas", listTitle: first.lists[0].title,
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
        XCTAssertTrue(results.allSatisfy { $0.weekKey == nil })
        first.lists[0].isArchived = true
        second.isArchived = true
        XCTAssertTrue(LibrarySearchIndex.results(query: "seedlings", collections: [first, second], labels: labels).isEmpty)
        XCTAssertTrue(LibrarySearchIndex.results(query: "  ", collections: [first, second], labels: labels).isEmpty)
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testCrossBoardMoveReservesArchivedIdentitiesAndPreservesFormat
    /// @brief      Verify that cross Board Move Reserves Archived Identities And Preserves Format
    /// @details    Exercises `CrossBoardCardMovement.move`, `original.replacingLocation`, `saved.contains`. Checks
    ///             `XCTAssertNotEqual(moved.id, original.id)`; `XCTAssertEqual(moved, original.replacingLocation(id:
    ///             moved.id, listTitle: "Monday"))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testCrossBoardMoveRejectsUnavailableDestinationWithoutMutation
    /// @brief      Verify that cross Board Move Rejects Unavailable Destination Without Mutation
    /// @details    Exercises `CrossBoardCardMovement.move`. Checks `XCTAssertEqual(week, before)`;
    ///             `XCTAssertEqual(saved, [card.id])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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
    func testEmojiReactionsValidateOneEmojiAndToggleOnlyTheCurrentAuthor() throws {
        for emoji in ["❤️", "👍🏽", "👨‍👩‍👧‍👦", "🇺🇸", "1️⃣", "🎉", "🫶"] {
            XCTAssertEqual(ItemEmojiReaction.validatedEmoji(" " + emoji + " "), emoji)
        }
        for invalid in ["", "hello", "a", "1", "#", "🎉🎉"] { XCTAssertNil(ItemEmojiReaction.validatedEmoji(invalid)) }
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
    func testReactionPreviewVisibilityDefaultsAndPersistsWithoutRemovingReactions() throws {
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
    func testReactionIdentityIsStableAndLegacyCardsRemainUnchangedUntilReactedTo() throws {
        let suite = "ReactionIdentity." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(LocalReactionIdentity.current(in: defaults))
        XCTAssertNil(defaults.object(forKey: LocalReactionIdentity.key))
        let author = LocalReactionIdentity.forUserAction(in: defaults)
        XCTAssertEqual(LocalReactionIdentity.forUserAction(in: defaults), author)
        XCTAssertEqual(LocalReactionIdentity.current(in: defaults), author)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
        let legacy = Data(#"{"id":1,"word":"Legacy","listTitle":"Today","checklists":[]}"#.utf8)
        var card = try JSONDecoder().decode(KanbanCard.self, from: legacy)
        XCTAssertNil(card.reactions)
        let unchangedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
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
    /// @fcn        PlenactBoardDocumentTests.testReactionsSurviveLocationChangesAndArchiveButNotFreshTemplates
    /// @brief      Verify that reactions Survive Location Changes And Archive But Not Fresh Templates
    /// @details    Exercises `card.replacingLocation`, `list.archiveCard`, `list.restoreArchivedCard`. Checks
    ///             `XCTAssertEqual(relocated.reactions, card.reactions)`; `XCTAssertEqual(relocated.createdAt,
    ///             card.createdAt)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testReactionsSurviveLocationChangesAndArchiveButNotFreshTemplates() throws {
        let reaction = ItemEmojiReaction(emoji: "💪", authorID: UUID())
        let card = KanbanCard(id: 1, word: "A meaningful step", listTitle: "Monday", checklists: [], createdAt: .now, reactions: [reaction])
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
        XCTAssertTrue(template.collection.lists.flatMap(\.cards).allSatisfy { $0.reactions == nil })
        XCTAssertEqual(week.collection.lists[0].cards[0].reactions, [reaction])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReactionPickerAndChipsRenderWithoutCreatingIdentityOrEditingRecords
    /// @brief      Verify that reaction Picker And Chips Render Without Creating Identity Or Editing Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(UserDefaults.standard.object(forKey:
    ///             LocalReactionIdentity.key) as? String, identityBefore)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testReactionPickerAndChipsRenderWithoutCreatingIdentityOrEditingRecords() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let author = UUID()
        let reactions = [ItemEmojiReaction(emoji: "❤️", authorID: author), ItemEmojiReaction(emoji: "🎉", authorID: author)]
        let identityBefore = UserDefaults.standard.object(forKey: LocalReactionIdentity.key) as? String
        for presentation in [ItemPresentation.card, .note] {
            let card = KanbanCard(id: 1, word: "Make time for something meaningful", listTitle: "Today", checklists: [],
                descriptionOverride: "A little encouragement belongs here.", presentation: presentation, reactions: reactions)
            let host = UIHostingController(rootView: NavigationStack {
                CardDetailView(card: card, onTitleToggle: { _ in XCTFail("Rendering must not edit") })
            })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-reactions-\(presentation).png")
            try XCTUnwrap(image.pngData()).write(to: url); print("REACTIONS_RENDER=" + url.path)
        }
        for scheme in [ColorScheme.light, .dark] {
            let host = UIHostingController(rootView: ItemReactionPicker(selected: ["❤️"], onChoose: { _ in XCTFail("Rendering must not choose") }).preferredColorScheme(scheme))
            window.rootViewController = host
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-reaction-picker-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: url); print("REACTIONS_RENDER=" + url.path)
        }
        XCTAssertEqual(UserDefaults.standard.object(forKey: LocalReactionIdentity.key) as? String, identityBefore)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusFilterSummaryDisappearsAfterThreeSecondsWithoutEditingItems
    /// @brief      Verify that focus Filter Summary Disappears After Three Seconds Without Editing Items
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertLessThan(try XCTUnwrap(heights.last), expanded)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testFocusFilterSummaryDisappearsAfterThreeSecondsWithoutEditingItems() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let list = KanbanList(id: 1, title: "Today", cards: [])
        var heights: [CGFloat] = []
        let host = UIHostingController(rootView: TodayFocusSection(list: list, cards: [], entries: [],
            groupsBySection: false, chronological: false, includesImportant: true, includesUpNext: true,
            filtersChangedAt: .now,
            onChangeFilters: { _, _, _ in XCTFail("Rendering must not change filters") },
            onToggleCard: { _ in XCTFail("Rendering must not edit items") }, onOpenCard: { _ in },
            onDeleteCard: { _ in XCTFail("Rendering must not delete"); return false }, onOpenTodayList: {})
            .padding(20)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights.append($0) })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(350))
        let expanded = try XCTUnwrap(heights.last)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        try XCTUnwrap(image.pngData()).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("plenact-focus-filter-summary.png"))
        try await Task.sleep(for: .seconds(3.3))
        XCTAssertLessThan(try XCTUnwrap(heights.last), expanded)
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
    func testFocusTrailingTimePrefersTimedStartAndSkipsDateOnlyValues() throws {
        let start = Date(timeIntervalSince1970: 1700000000)
        let due = start.addingTimeInterval(3600)
        var card = KanbanCard(id: 1, word: "Work", listTitle: "Today", startDate: start, dueDate: due,
                              startDateKind: .date, dueDateKind: .date)


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusTrailingTimePrefersTimedStartAndSkipsDateOnlyValues.entry
        /// @brief      Prepare entry for the enclosing regression test
        /// @details    Supplies the local fixture for focus Trailing Time Prefers Timed Start And Skips Date Only
        ///             Values.
        ///
        /// @return     (TodayFocusEntry) result described by this operation's contract
        ///
        func entry() -> TodayFocusEntry { TodayFocusEntry(card: card, sectionID: nil, heading: nil) }
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
    func testFocusFilterPaletteUsesDistinctReadableCombinationColors() throws {


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
        func luminance(_ values: [Double]) -> Double {
            zip(values, [0.2126, 0.7152, 0.0722]).reduce(0) { result, pair in
                let v = pair.0
                return result + (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)) * pair.1
            }
        }
        for dark in [false, true] {
            XCTAssertNil(TodayFocusFilterColor.rgb(upNext: false, important: false, bookmarked: false, dark: dark))
            var colors = Set<String>()
            let background = luminance(dark ? [0.12, 0.12, 0.14] : [245.0 / 255, 229.0 / 255, 212.0 / 255])
            for selection in 1...7 {
                let rgb = try XCTUnwrap(TodayFocusFilterColor.rgb(upNext: selection & 1 != 0,
                    important: selection & 2 != 0, bookmarked: selection & 4 != 0, dark: dark))
                colors.insert("\(rgb.red),\(rgb.green),\(rgb.blue)")
                let ink = luminance([rgb.red, rgb.green, rgb.blue])
                XCTAssertGreaterThanOrEqual((max(ink, background) + 0.05) / (min(ink, background) + 0.05), 4.5,
                    "Selection \(selection), dark \(dark)")
            }
            XCTAssertEqual(colors.count, 7)
        }
        let purple = try XCTUnwrap(TodayFocusFilterColor.rgb(upNext: true, important: true, bookmarked: false))
        XCTAssertEqual(purple.red, 126.0 / 255, accuracy: 0.000001)
        XCTAssertEqual(purple.green, 34.0 / 255, accuracy: 0.000001)
        XCTAssertEqual(purple.blue, 206.0 / 255, accuracy: 0.000001)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHeaderSpacingCompactsOnlyWhenIntrinsicTextWouldClip
    /// @brief      Verify that header Spacing Compacts Only When Intrinsic Text Would Clip
    /// @details    Exercises `WorkspaceHeaderSpacing.gap`. Checks
    ///             `XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 360, titleIdealWidth: 100,
    ///             controlsWidth: 176, gapCount: 4, regularSpacing: 12), 12)`;
    ///             `XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 360, titleIdealWidth: 150,
    ///             controlsWidth: 176, gapCount: 4, regularSpacing: 12), 0)`.
    ///
    /// @return     (Void) no return value
    ///
    func testHeaderSpacingCompactsOnlyWhenIntrinsicTextWouldClip() {
        XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 360, titleIdealWidth: 100,
            controlsWidth: 176, gapCount: 4, regularSpacing: 12), 12)
        XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 360, titleIdealWidth: 150,
            controlsWidth: 176, gapCount: 4, regularSpacing: 12), 0)
        XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 360, titleIdealWidth: 500,
            controlsWidth: 176, gapCount: 4, regularSpacing: 12), 0)
        XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 820, titleIdealWidth: 500,
            controlsWidth: 176, gapCount: 4, regularSpacing: 12), 12)
        XCTAssertEqual(WorkspaceHeaderSpacing.gap(availableWidth: 360, titleIdealWidth: 136,
            controlsWidth: 176, gapCount: 4, regularSpacing: 12), 12)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAdaptiveHeaderRetainsControlTargetsAndGivesLongTextTheGapSpace
    /// @brief      Verify that adaptive Header Retains Control Targets And Gives Long Text The Gap Space
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(try XCTUnwrap(frames[id]).width, 44)`;
    ///             `XCTAssertEqual(try XCTUnwrap(frames[id]).height, 44)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testAdaptiveHeaderRetainsControlTargetsAndGivesLongTextTheGapSpace() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        var results: [String: [Int: CGRect]] = [:]
        for (name, title, direction) in [
            ("short", "Day", LayoutDirection.leftToRight),
            ("long", "A long name that needs additional space before the toolbar controls", .leftToRight),
            ("rtl", "A long name that needs additional space before the toolbar controls", .rightToLeft)
        ] {


            ///
            /// @fcn        PlenactBoardDocumentTests.testAdaptiveHeaderRetainsControlTargetsAndGivesLongTextTheGapSpace.control
            /// @brief      Prepare control for the enclosing regression test
            /// @details    Supplies the local fixture for adaptive Header Retains Control Targets And Gives Long Text
            ///             The Gap Space. Uses `Color.blue.frame(width: 44, height: 44)
            ///             .onGeometryChange`, `Color.blue.frame`, `$0.frame`.
            ///
            /// @param[in]  id  Starting numeric card ID or owner-local content identity
            ///
            /// @return     (some View) regression fixture view
            ///
            func control(_ id: Int) -> some View {
                Color.blue.frame(width: 44, height: 44)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("headerFixture")) } action: { results[name, default: [:]][id] = $0 }
            }
            let view = AdaptiveWorkspaceHeaderLayout(regularSpacing: 12, layoutDirection: direction) {
                control(0)
                Text(title).lineLimit(1).frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("headerFixture")) } action: { results[name, default: [:]][1] = $0 }
                    .layoutValue(key: WorkspaceHeaderTitleKey.self, value: true)
                control(2); control(3); control(4)
            }.frame(width: 360).coordinateSpace(name: "headerFixture")
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(180))
        }
        let short = try XCTUnwrap(results["short"])
        let long = try XCTUnwrap(results["long"])
        let rtl = try XCTUnwrap(results["rtl"])
        for frames in [short, long, rtl] {
            for id in [0, 2, 3, 4] {
                XCTAssertEqual(try XCTUnwrap(frames[id]).width, 44, accuracy: 0.5)
                XCTAssertEqual(try XCTUnwrap(frames[id]).height, 44, accuracy: 0.5)
            }
        }
        XCTAssertEqual(try XCTUnwrap(short[3]).minX - XCTUnwrap(short[2]).maxX, 12, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(long[3]).minX - XCTUnwrap(long[2]).maxX, 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(long[1]).width - XCTUnwrap(short[1]).width, 48, accuracy: 0.5)
        XCTAssertGreaterThan(try XCTUnwrap(rtl[0]).midX, try XCTUnwrap(rtl[4]).midX)
        XCTAssertEqual(try XCTUnwrap(rtl[1]).width, try XCTUnwrap(long[1]).width, accuracy: 0.5)
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
    func testOverflowReadingPreferenceDefaultsOnAndPersistsWithoutProfile() throws {
        let suite = "OverflowPreferenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(try JSONDecoder().decode(LocalProfilePreferences.self, from: Data("{}".utf8)).scrollsOverflowingTitles)
        XCTAssertTrue(PlanPreferencesStore.load(from: defaults).scrollsOverflowingTitles)
        var preferences = LocalProfilePreferences()
        preferences.scrollsOverflowingTitles = false
        preferences.todayFocusIncludesImportant = true
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
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
    func testOverflowReadingPreferenceSwitchesMountedReaderWithoutChangingText() async throws {
        let suite = "OverflowReaderRender." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = LocalProfilePreferences(scrollsOverflowingTitles: false)
        PlanPreferencesStore.save(preferences, to: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }


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
        func scrolls(_ view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrolls)
        }
        let title = "A long title that can be read with a horizontal slide when this preference is enabled"
        var overflow: [Bool] = []
        let host = UIHostingController(rootView: SlideableHeaderText(text: title,
            onOverflowChange: { overflow.append($0) }).font(.headline).frame(width: 180).defaultAppStorage(defaults))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(scrolls(host.view).isEmpty)
        XCTAssertEqual(overflow.last, false)
        preferences.scrollsOverflowingTitles = true
        PlanPreferencesStore.save(preferences, to: defaults)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(scrolls(host.view).contains { $0.isScrollEnabled && $0.contentSize.width > $0.bounds.width })
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
    func testLibraryLongNamesStayCompactAndExpandForAccessibility() async throws {
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
    /// @fcn        PlenactBoardDocumentTests.testSlideableHeaderTextScrollsOnlyOverflowAndRetainsReadingPosition
    /// @brief      Verify that slideable Header Text Scrolls Only Overflow And Retains Reading Position
    /// @details    Exercises `PlanPreferencesStore.save`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertTrue(scrolling.isScrollEnabled)`;
    ///             `XCTAssertTrue(overflow.contains(true))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testSlideableHeaderTextScrollsOnlyOverflowAndRetainsReadingPosition() async throws {
        let suite = "HeaderReadingTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        PlanPreferencesStore.save(LocalProfilePreferences(scrollsOverflowingTitles: true), to: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }


        ///
        /// @fcn        PlenactBoardDocumentTests.testSlideableHeaderTextScrollsOnlyOverflowAndRetainsReadingPosition.scrolls
        /// @brief      Find scrolls in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrolls(_ view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        let long = "Make room for today because there is more to this title than fits in the header, and every word should remain readable."
        var overflow: [Bool] = []
        let host = UIHostingController(rootView: VStack(spacing: 20) {
            SlideableHeaderText(text: long, onTap: {}, onOverflowChange: { overflow.append($0) }).font(.headline)
            SlideableHeaderText(text: "Short").font(.subheadline)
        }.frame(width: 220).padding().defaultAppStorage(defaults))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        let native = scrolls(host.view)
        let scrolling = try XCTUnwrap(native.first { $0.contentSize.width > $0.bounds.width + 1 })
        XCTAssertTrue(scrolling.isScrollEnabled)
        XCTAssertTrue(overflow.contains(true))
        XCTAssertEqual(scrolling.contentOffset.x, 0, accuracy: 1, "No automatic movement")
        XCTAssertTrue(native.contains { !$0.isScrollEnabled && $0.contentSize.width <= $0.bounds.width + 1 })
        let end = max(0, scrolling.contentSize.width - scrolling.bounds.width)
        scrolling.setContentOffset(CGPoint(x: end, y: 0), animated: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(scrolling.contentOffset.x, end, accuracy: 1, "The full ending is reachable and stays where it was read")
        XCTAssertFalse(scrolling.showsHorizontalScrollIndicator)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLongListAndBoardHeadersExposeIndependentNativeReaders
    /// @brief      Verify that long List And Board Headers Expose Independent Native Readers
    /// @details    Exercises `PlanPreferencesStore.save`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertGreaterThanOrEqual(readers.count, 2)`;
    ///             `XCTAssertTrue(reader.isScrollEnabled)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLongListAndBoardHeadersExposeIndependentNativeReaders() async throws {
        let suite = "HeaderReadingTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        PlanPreferencesStore.save(LocalProfilePreferences(scrollsOverflowingTitles: true), to: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }


        ///
        /// @fcn        PlenactBoardDocumentTests.testLongListAndBoardHeadersExposeIndependentNativeReaders.scrolls
        /// @brief      Find scrolls in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrolls(_ view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrolls)
        }
        let title = "On the Table, and all the meaningful possibilities that I want to make room for today"
        let subtitle = "Ideas taking shape, plans becoming action, and the rest of this subtitle is readable too"
        var list = KanbanList(id: 8, title: title, cards: [])
        list.subtitleOverride = subtitle
        let header = BoardHeader(settings: .constant(BoardDisplaySettings()), presentation: .constant(.standard),
            activeMembers: [], memberColors: [:], onRenameMember: { _, _ in }, onDeleteMember: { _ in },
            onSetMemberColor: { _, _ in }, onOpenCalendar: {}, title: title, subtitle: subtitle,
            allowsAddingLists: false, onClose: {}, onViewArchivedLists: {}, onArchiveBoard: nil,
            onDeleteBoard: nil, deleteBoardTitle: "Delete Board", onJumpToFirstList: { XCTFail("Layout must not navigate") },
            onJumpToLastList: { XCTFail("Layout must not navigate") }, onAddList: {})
        for (name, view) in [
            ("board", AnyView(header.titleSwipeArea.padding(20).background(Color.blue))),
            ("list", AnyView(TodayListDetailView(lists: .constant([list]), reservedLists: [], labelLibrary: .constant(.starter),
                savedCardIDs: .constant([]), listID: list.id, currentUserName: "Test", onClose: {}, onOpenWeek: {}, onPermanentDelete: { _ in false })))
        ] {
            let host = UIHostingController(rootView: view.defaultAppStorage(defaults))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            // A top-edge native scroll view can extend into the container safe area;
            // its single-line content height identifies the reader, not its UIKit bounds.
            let readers = scrolls(host.view).filter { $0.contentSize.width > $0.bounds.width + 1 && $0.contentSize.height < 70 }
            XCTAssertGreaterThanOrEqual(readers.count, 2, "Title and subtitle need independent reading positions")
            for reader in readers { XCTAssertTrue(reader.isScrollEnabled) }
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-sliding-header-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: url); print("SLIDING_HEADER_RENDER=" + url.path)
        }
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
    func testLongDetailHeadersRenderWithoutEditingCardsOrNotes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for presentation in [ItemPresentation.card, .note] {
            let card = KanbanCard(id: 901, word: "Make room for today because it is so good, but not enough for me, because of all that it was for you!",
                listTitle: "On the Table, and more useful thoughts for this particular list",
                checklists: [], descriptionOverride: "A little space for a meaningful plan.",
                subtitleOverride: "On the Table, a quick guide to this List and what I treasure in the rest of this subtitle.",
                presentation: presentation)
            var emissions: [KanbanCard] = []
            let host = UIHostingController(rootView: NavigationStack {
                CardDetailView(card: card, onTitleToggle: { emissions.append($0) })
            })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(emissions.isEmpty)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-sliding-header-\(presentation).png")
            try XCTUnwrap(image.pngData()).write(to: url); print("SLIDING_HEADER_RENDER=" + url.path)
        }
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
    func testEditorBannerDoesNotInsertNativeNavigationBar() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testBannerBackgroundFillsProposedWidthWithoutLegacyAccentDecoration
    /// @brief      Verify that banner Background Fills Proposed Width Without Legacy Accent Decoration
    /// @details    Exercises `controller.sizeThatFits`, `mark.sizeThatFits`. Checks `XCTAssertEqual(size.width,
    ///             320)`; `XCTAssertLessThan(size.height, 100)`.
    ///
    /// @return     (Void) no return value
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testBannerBackgroundIsIndependentAndBackwardCompatible
    /// @brief      Verify that banner Background Is Independent And Backward Compatible
    /// @details    Exercises `JSONSerialization.jsonObject`, `card.replacingLocation`. Checks `XCTAssertEqual(legacy,
    ///             ItemAppearance(accent: .teal, icon: .heart))`; `XCTAssertNil(legacy.background)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayInitialTaskFocusSkipsCompletedAndNonTaskFormatsWithoutReordering
    /// @brief      Verify that today Initial Task Focus Skips Completed And Non Task Formats Without Reordering
    /// @details    Checks `XCTAssertEqual(list.firstUncheckedTaskID, 5)`; `XCTAssertEqual(list.cards, cards)`.
    ///
    /// @return     (Void) no return value
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testListBackgroundTintRoundTripsAndKeepsLegacyDefaults
    /// @brief      Verify that list Background Tint Round Trips And Keeps Legacy Defaults
    /// @details    Checks `XCTAssertNil(legacy.listBackground)`; `XCTAssertFalse(appearance.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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
    func testEmptySubtitleAppearanceIsOptionalAndNeverHidesWriting() throws {
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testListAppearanceChangesOnlyCanonicalMetadataAndResetsToNil
    /// @brief      Verify that list Appearance Changes Only Canonical Metadata And Resets To Nil
    /// @details    Exercises `card.replacingLocation`, `lists[0].edit`, `DatabaseActivity.shared.dismissError`.
    ///             Checks `XCTAssertTrue(setListAppearance(0, appearance: appearance, in: &lists))`;
    ///             `XCTAssertEqual(lists, expected)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testDisplayFormatsOverrideLegacyDividersWithoutChangingRetainedContent
    /// @brief      Verify that display Formats Override Legacy Dividers Without Changing Retained Content
    /// @details    Exercises `JSONSerialization.jsonObject`, `.manual`, `decoded.replacingLocation`. Checks
    ///             `XCTAssertEqual(legacy.displayFormat, .divider)`; `XCTAssertNil(legacyJSON["listDisplayFormat"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testMixedDisplayFormatsPersistMoveRenameAndArchiveWithIndependentDefaults
    /// @brief      Verify that mixed Display Formats Persist Move Rename And Archive With Independent Defaults
    /// @details    Exercises `ItemDisplayFormat.allCases.enumerated().map`, `ItemDisplayFormat.allCases.enumerated`,
    ///             `lists[0].makeItem`. Checks `XCTAssertTrue(editBoardList(1, title: "Ideas", subtitle: "",
    ///             newItemPresentation: .note, in: &lists))`; `XCTAssertEqual(lists[0].cards, cards)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedMixedDisplayFormatsAndPicturePlaceholdersDoNotMutateRecords
    /// @brief      Verify that hosted Mixed Display Formats And Picture Placeholders Do Not Mutate Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(item, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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
                let sheet = ItemAppearanceSheet(title: item.word, appearance: nil,
                    onOpenLayout: { XCTFail("Presentation must not open Layout") }, displayFormat: format,
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testStarterAndExampleWeekPictureRowsUseExplicitBundledCoversAndRetainActivities
    /// @brief      Verify that starter And Example Week Picture Rows Use Explicit Bundled Covers And Retain
    ///             Activities
    /// @details    Exercises `lists.flatMap(\.cards).filter`, `lists.flatMap`, `pictures.map`. Checks
    ///             `XCTAssertEqual(pictures.map(\.word), ["Capture a new idea", "Take a walk", "Capture notes and
    ///             ideas"])`; `XCTAssertEqual(pictures.map(\.listTitle), ["Tuesday", "Wednesday", "Sunday"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPictureRowsHaveNoFooterOrInternalPaddingAtBothBoardDensities
    /// @brief      Verify that picture Rows Have No Footer Or Internal Padding At Both Board Densities
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(size.width, width)`; `XCTAssertEqual(size.height,
    ///             (width - 8) / ratio)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleWeekGalleriesUseBundledPhotosAndPreserveCoverAndContent
    /// @brief      Verify that example Week Galleries Use Bundled Photos And Preserve Cover And Content
    /// @details    Exercises `lists.flatMap`, `cards.filter`, `galleryCards.map`. Checks
    ///             `XCTAssertEqual(galleryCards.map(\.word), [ "Review the week ahead", "Plan the weekend", "Spend
    ///             time outdoors" ])`; `XCTAssertEqual(galleryCards.map { $0.galleryPhotos.count }, [3, 3, 3])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPhotoCaptionsDecodeLegacyAttachmentsAndPreserveMetadata
    /// @brief      Verify that photo Captions Decode Legacy Attachments And Preserve Metadata
    /// @details    Exercises `JSONSerialization.jsonObject`, `card.setPhotoCaption`. Checks
    ///             `XCTAssertNil(json["caption"])`; `XCTAssertEqual(try JSONDecoder().decode(KanbanAttachment.self,
    ///             from: legacyData), photo)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPhotoGalleryReorderKeepsCoverAndNonphotoSlotsAndRejectsInvalidOrders
    /// @brief      Verify that photo Gallery Reorder Keeps Cover And Nonphoto Slots And Rejects Invalid Orders
    /// @details    Exercises `card.reorderGalleryPhotos`, `card.setCover`, `card.removeAttachment`. Checks
    ///             `XCTAssertEqual(card.galleryPhotos, [first, second, third])`; `XCTAssertEqual(card.attachments,
    ///             [third, video, cover, first, link, second])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testPhotoGalleryEditsPersistInBothStoresAndRetainArchivedCopies
    /// @brief      Verify that photo Gallery Edits Persist In Both Stores And Retain Archived Copies
    /// @details    Exercises `original.setPhotoCaption`, `original.reorderGalleryPhotos`,
    ///             `KanbanBoardPersistence.saveListsChecked`. Checks `XCTAssertEqual(restoredWeek, lists)`;
    ///             `XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [personal])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedPhotoGalleryScrollsHorizontallyWithoutEditingRecords
    /// @brief      Verify that hosted Photo Gallery Scrolls Horizontally Without Editing Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertTrue(scrollViews(in: controller.view).contains {
    ///             $0.contentSize.width > $0.bounds.width })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedPhotoGalleryScrollsHorizontallyWithoutEditingRecords.scrollViews
        /// @brief      Find scroll views in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testListEditingPreservesRetainedRecordsAndRoundTripsSubtitle
    /// @brief      Verify that list Editing Preserves Retained Records And Round Trips Subtitle
    /// @details    Exercises `list.edit`, `collection.rename`. Checks `XCTAssertThrowsError(try list.edit(title: " \n
    ///             ", subtitle: "Do not save"))`; `XCTAssertEqual(list, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedListEditorPrefillsWithoutMutatingRecords
    /// @brief      Verify that hosted List Editor Prefills Without Mutating Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertTrue(fields(in: controller.view).contains { $0.text ==
    ///             list.title })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedListEditorPrefillsWithoutMutatingRecords.fields
        /// @brief      Find fields in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextField. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UITextField]) resulting values in the ordering described above
        ///
        func fields(in view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedListEditorPrefillsWithoutMutatingRecords.textViews
        /// @brief      Find text views in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UITextView]) resulting values in the ordering described above
        ///
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




    ///
    /// @fcn        PlenactBoardDocumentTests.testNewBoardListEditorSelectsTitleAndNextFocusesSubtitle
    /// @brief      Start naming a new Board list immediately and advance to its subtitle
    /// @details    Mounts the new-list editor, checks native first-responder and full-title selection, types a
    ///             replacement name, and invokes the keyboard return delegate. Focus changes must not call Save
    ///             or mutate the supplied list, and the title's return key must be labeled Next.
    ///
    /// @return     (Void) no return value
    /// @throws     XCTest setup failures or cancelled fixture delays
    ///
    @MainActor
    func testNewBoardListEditorSelectsTitleAndNextFocusesSubtitle() async throws {
        var list = KanbanList(id: 7, title: "New List 2", cards: [])
        list.subtitleOverride = "Initial subtitle"
        let original = list
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        testNewBoardListEditorSelectsTitleAndNextFocusesSubtitle.descendants
        /// @brief      Collect the native descendants of the hosted editor
        /// @details    Includes the supplied view so callers can find both single-line fields and the multiline
        ///             subtitle editor without relying on private SwiftUI container classes.
        ///
        /// @param[in]  view  Native subtree to inspect
        ///
        /// @return     ([UIView]) root and all descendant views in traversal order
        ///
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        var saveCalls = 0
        let host = UIHostingController(rootView: ListInfoEditorSheet(list: list, focusesTitleOnAppear: true) { _, _, _ in
            saveCalls += 1
            return true
        })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        let titleField = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextField }.first { $0.text == list.title })
        XCTAssertTrue(titleField.isFirstResponder)
        XCTAssertEqual(titleField.returnKeyType, .next)
        let selection = try XCTUnwrap(titleField.selectedTextRange)
        XCTAssertEqual(titleField.text(in: selection), list.title)
        titleField.insertText("Roadmap")
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(titleField.text, "Roadmap")
        _ = titleField.delegate?.textFieldShouldReturn?(titleField)
        try await Task.sleep(for: .milliseconds(150))
        let subtitle = try XCTUnwrap(descendants(host.view).first { view in
            (view as? UITextField)?.text == list.subtitle || (view as? UITextView)?.text == list.subtitle
        })
        XCTAssertTrue(subtitle.isFirstResponder)
        XCTAssertFalse(titleField.isFirstResponder)
        XCTAssertEqual(titleField.text, "Roadmap")
        XCTAssertEqual(saveCalls, 0)
        XCTAssertEqual(list, original)
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
    func testEditingLockRoundTripsAndSurvivesCopyArchiveAndRelocation() throws {
        let suite = "EditingLock." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for presentation in ItemPresentation.allCases {
            var card = KanbanCard(id: 6, word: "Protected", listTitle: "Projects", checklists: [],
                attachments: [KanbanAttachment(exampleImage: .mountains)], descriptionOverride: "Keep this writing",
                presentation: presentation, createdAt: Date(timeIntervalSince1970: 1234))
            let legacyData = try JSONEncoder().encode(card)
            XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])["editingLocked"])
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
    func testLockedContentRejectsEditsAndAllowsOnlyAnUnchangedUnlock() throws {
        var locked = KanbanCard(id: 1, word: "Protected", listTitle: "Tasks", isTitleChecked: true,
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
    func testLockedCardAndNoteDetailsDoNotMountEditableTextInputs() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }


        ///
        /// @fcn        testLockedCardAndNoteDetailsDoNotMountEditableTextInputs.descendants
        /// @brief      Collect hosted native views for input inspection
        /// @details    Includes the root and recursively traverses child views without assuming private containers.
        ///
        /// @param[in]  view  Native subtree to inspect
        ///
        /// @return     ([UIView]) root and all descendants in traversal order
        ///
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        for presentation in ItemPresentation.allCases {
            let card = KanbanCard(id: 3, word: "Protected writing", listTitle: "Projects",
                checklists: [KanbanChecklist(title: "Read these steps", items: ["Preserved action"])],
                attachments: [KanbanAttachment(exampleImage: .mountains)], descriptionOverride: "The retained body",
                presentation: presentation, isEditingLocked: true)
            var saves = 0
            let host = UIHostingController(rootView: CardDetailView(card: card, labelLibrary: .constant(.starter),
                onTitleToggle: { _ in saves += 1 }))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertFalse(descendants(host.view).compactMap { $0 as? UITextField }.contains { $0.isEnabled })
            XCTAssertFalse(descendants(host.view).compactMap { $0 as? UITextView }.contains { $0.isEditable })
            XCTAssertEqual(saves, 0)
            window.rootViewController = nil
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
    func testQuickCreationSwitchKeepsTitleAndTemplateWriting() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let host = UIHostingController(rootView: QuickNoteComposer(lists: .constant([KanbanList(id: 4, title: "Ideas", cards: [])]),
            initialListID: 4, initialTitle: "Keep this idea", template: .smallPlan) { _, _, _, _, _, _ in
                XCTFail("Switching type must not create content")
            })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()


        ///
        /// @fcn        PlenactBoardDocumentTests.testQuickCreationSwitchKeepsTitleAndTemplateWriting.descendants
        /// @brief      Find descendants in the hosted view hierarchy
        /// @details    Recursively inspects native subviews. Returns all collected matches in hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIView]) resulting values in the ordering described above
        ///
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }


        ///
        /// @fcn        PlenactBoardDocumentTests.testQuickCreationSwitchKeepsTitleAndTemplateWriting.textValues
        /// @brief      Prepare text values for the enclosing regression test
        /// @details    Supplies the local fixture for quick Creation Switch Keeps Title And Template Writing. Uses
        ///             `descendants(host.view).compactMap`.
        ///
        /// @return     ([String]) resulting values in the ordering described above
        ///
        func textValues() -> [String] {
            descendants(host.view).compactMap { view in
                if let field = view as? UITextField { return field.text }
                if let text = view as? UITextView { return text.text }
                return nil
            }
        }
        for index in [1, 0] {
            try await Task.sleep(for: .milliseconds(180))
            host.view.layoutIfNeeded()
            let control = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UISegmentedControl }.first)
            control.selectedSegmentIndex = index
            control.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(180))
            host.view.layoutIfNeeded()
            XCTAssertTrue(textValues().contains("Keep this idea"))
            XCTAssertTrue(textValues().contains(QuickCaptureTemplate.smallPlan.body))
        }
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
    func testCaptureStartStopDatesAreOptionalValidatedAndPersistAsCalendarDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10)))
        let stop = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: start))
        for times in [false, true] {
            for pair: (Date?, Date?) in [(nil, nil), (start, nil), (nil, stop), (start, stop)] {
                let schedule = QuickCaptureSchedule(start: pair.0, stop: pair.1, includesTime: times)
                XCTAssertTrue(schedule.isValid(calendar: calendar))
                var card = KanbanCard(id: 1, word: "Scheduled capture", listTitle: "Today")
                schedule.apply(to: &card, calendar: calendar)
                let saved = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
                XCTAssertEqual(saved.startDate, pair.0.map { times ? $0 : calendar.startOfDay(for: $0) })
                XCTAssertEqual(saved.dueDate, pair.1.map { times ? $0 : calendar.startOfDay(for: $0) })
                XCTAssertEqual(saved.startDateKind, times ? .dateAndTime : .date)
                XCTAssertEqual(saved.dueDateKind, times ? .dateAndTime : .date)
            }
        }
        XCTAssertFalse(QuickCaptureSchedule(start: stop, stop: start).isValid(calendar: calendar))
        let earlierToday = start.addingTimeInterval(-60)
        XCTAssertTrue(QuickCaptureSchedule(start: start, stop: earlierToday).isValid(calendar: calendar))
        XCTAssertFalse(QuickCaptureSchedule(start: start, stop: earlierToday, includesTime: true).isValid(calendar: calendar))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testVoiceSaveOptionsKeepOnlySelectedContentAndPreserveRichWriting
    /// @brief      Verify that voice Save Options Keep Only Selected Content And Preserve Rich Writing
    /// @details    Exercises `PlanRichText.Run`, `VoiceCaptureSaveOption.audio.body`, `option.body`. Checks
    ///             `XCTAssertEqual(VoiceCaptureSaveOption.audio.body(existing: rich, transcript: transcript), rich)`;
    ///             `XCTAssertEqual(PlanRichText.plain(body), "Keep this writing\n\nMy reviewed spoken thought")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testVoiceSaveOptionsKeepOnlySelectedContentAndPreserveRichWriting() throws {
        let rich = PlanRichText.prefix + (try JSONEncoder().encode([PlanRichText.Run(text: "Keep this writing", bold: true)])).base64EncodedString()
        let transcript = "  My reviewed spoken thought  "
        XCTAssertEqual(VoiceCaptureSaveOption.audio.body(existing: rich, transcript: transcript), rich)
        for option in [VoiceCaptureSaveOption.text, .both] {
            let body = option.body(existing: rich, transcript: transcript)
            XCTAssertEqual(PlanRichText.plain(body), "Keep this writing\n\nMy reviewed spoken thought")
            XCTAssertEqual(PlanRichText.runs(body)?.first?.bold, true)
            XCTAssertEqual(option.body(existing: "", transcript: transcript), "My reviewed spoken thought")
            XCTAssertEqual(option.body(existing: rich, transcript: "   "), rich)
        }
        XCTAssertTrue(VoiceCaptureSaveOption.audio.savesAudio)
        XCTAssertFalse(VoiceCaptureSaveOption.audio.savesText)
        XCTAssertFalse(VoiceCaptureSaveOption.text.savesAudio)
        XCTAssertTrue(VoiceCaptureSaveOption.text.savesText)
        XCTAssertTrue(VoiceCaptureSaveOption.both.savesAudio && VoiceCaptureSaveOption.both.savesText)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testVoiceAudioCommitRoundTripsPlaybackFileAndCleansRejectedSave
    /// @brief      Verify that voice Audio Commit Round Trips Playback File And Cleans Rejected Save
    /// @details    Exercises `data[0].initialize`, `file.write`, `CardAttachmentStore.removeDeletedFiles`. Checks
    ///             `XCTAssertTrue(try QuickCaptureMediaCommit.save([], audio: audio) { attachments in retained =
    ///             attachments; return true })`; `XCTAssertEqual(attachment.kind, .audio)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testVoiceAudioCommitRoundTripsPlaybackFileAndCleansRejectedSave() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: source) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        if let data = buffer.floatChannelData { data[0].initialize(repeating: 0, count: 4_410) }
        do {
            let file = try AVAudioFile(forWriting: source, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
            try file.write(from: buffer)
        }
        let audio = try Data(contentsOf: source)
        var retained: [KanbanAttachment] = []
        defer { try? CardAttachmentStore.removeDeletedFiles(Set(retained.compactMap(\.fileName)), keeping: []) }
        XCTAssertTrue(try QuickCaptureMediaCommit.save([], audio: audio) { attachments in retained = attachments; return true })
        let attachment = try XCTUnwrap(retained.first)
        XCTAssertEqual(attachment.kind, .audio)
        XCTAssertNil(CardAttachmentStore.imageURL(for: attachment))
        let savedURL = try XCTUnwrap(CardAttachmentStore.fileURL(for: attachment))
        XCTAssertEqual(try Data(contentsOf: savedURL), audio)
        let player = try AVAudioPlayer(contentsOf: savedURL)
        XCTAssertGreaterThan(player.duration, 0)
        let card = KanbanCard(id: 1, word: "Voice", listTitle: "Today", attachments: retained, descriptionOverride: "Reviewed transcript")
        let saved = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(saved.attachments?.first?.kind, .audio)
        XCTAssertEqual(saved.descriptionOverride, "Reviewed transcript")
        var rejected: [URL] = []
        XCTAssertFalse(try QuickCaptureMediaCommit.save([], audio: audio) { attachments in rejected = attachments.compactMap(CardAttachmentStore.fileURL); return false })
        XCTAssertTrue(rejected.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertThrowsError(try QuickCaptureMediaCommit.save([], audio: Data()) { _ in XCTFail("Empty audio must not commit"); return true })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testQuickCapturePhotoCommitRetainsSuccessfulFilesAndCleansRejectedOrPartialImports
    /// @brief      Verify that quick Capture Photo Commit Retains Successful Files And Cleans Rejected Or Partial
    ///             Imports
    /// @details    Exercises `UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image`,
    ///             `UIColor.systemBlue.setFill`, `context.fill`. Checks `XCTAssertEqual(attachments.count, 1)`;
    ///             `XCTAssertEqual(try Data(contentsOf: url), photo.data)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testQuickCapturePhotoCommitRetainsSuccessfulFilesAndCleansRejectedOrPartialImports() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let photo = QuickCapturePhoto(data: try XCTUnwrap(image.pngData()), fileExtension: "png")
        var committed: [KanbanAttachment] = []
        defer { try? CardAttachmentStore.removeDeletedFiles(Set(committed.compactMap(\.fileName)), keeping: []) }
        XCTAssertTrue(try QuickCaptureMediaCommit.save([photo]) { attachments in
            committed = attachments
            XCTAssertEqual(attachments.count, 1)
            return true
        })
        let attachment = try XCTUnwrap(committed.first)
        let url = try XCTUnwrap(CardAttachmentStore.fileURL(for: attachment))
        XCTAssertEqual(try Data(contentsOf: url), photo.data)
        let card = KanbanCard(id: 9, word: "Captured title", listTitle: "Today", attachments: committed, coverAttachmentID: attachment.id)
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(restored.attachments, committed)
        XCTAssertEqual(restored.coverAttachmentID, attachment.id)
        var rejectedURLs: [URL] = []
        XCTAssertFalse(try QuickCaptureMediaCommit.save([photo]) { attachments in
            rejectedURLs = attachments.compactMap(CardAttachmentStore.fileURL)
            return false
        })
        XCTAssertTrue(rejectedURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        let directory = url.deletingLastPathComponent()
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        let invalid = QuickCapturePhoto(data: Data("not an image".utf8), fileExtension: "png")
        XCTAssertThrowsError(try QuickCaptureMediaCommit.save([photo, invalid]) { _ in XCTFail("Invalid imports cannot commit"); return true })
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.drawingFixture
    /// @brief      Create a small deterministic PencilKit drawing fixture
    /// @details    Builds three blue pen control points on one stroke for drawing persistence, preview, and export
    ///             tests.
    ///
    /// @return     (PKDrawing) result described by this operation's contract
    ///
    @MainActor
    private func drawingFixture() -> PKDrawing {
        let points = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 180), CGPoint(x: 200, y: 350)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDrawingCapturePersistsEditableStrokesAndRetainsBothFiles
    /// @brief      Verify that drawing Capture Persists Editable Strokes And Retains Both Files
    /// @details    Exercises `CardAttachmentStore.removeDeletedFiles`, `saved.flatMap`,
    ///             `QuickCaptureMediaCommit.save`. Checks `XCTAssertTrue(try QuickCaptureMediaCommit.save([],
    ///             drawings: [draft]) { saved = $0; return true })`; `XCTAssertEqual(attachment.kind, .photo)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDrawingCapturePersistsEditableStrokesAndRetainsBothFiles() throws {
        let draft = DrawingCaptureDraft(drawing: drawingFixture())
        var saved: [KanbanAttachment] = []
        defer { try? CardAttachmentStore.removeDeletedFiles(Set(saved.flatMap(\.storedFileNames)), keeping: []) }
        XCTAssertTrue(try QuickCaptureMediaCommit.save([], drawings: [draft]) { saved = $0; return true })
        let attachment = try XCTUnwrap(saved.first)
        XCTAssertEqual(attachment.kind, .photo)
        XCTAssertEqual(attachment.storedFileNames.count, 2)
        XCTAssertNotNil(UIImage(contentsOfFile: try XCTUnwrap(CardAttachmentStore.imageURL(for: attachment)).path))
        let card = KanbanCard(id: 4, word: "Sketch", listTitle: "Today", attachments: saved, coverAttachmentID: attachment.id)
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        let restoredAttachment = try XCTUnwrap(restored.attachments?.first)
        let editable = try DrawingAttachmentStore.load(restoredAttachment)
        XCTAssertEqual(editable.drawing.strokes.count, draft.drawing.strokes.count)
        XCTAssertEqual(editable.drawing.bounds, draft.drawing.bounds)
        XCTAssertEqual(CardAttachmentStore.fileNames(in: [KanbanList(id: 4, title: "Today", cards: [restored])]), Set(attachment.storedFileNames))
        let replacement = try DrawingAttachmentStore.save(editable, replacing: attachment)
        saved.append(replacement)
        XCTAssertEqual(replacement.id, attachment.id)
        XCTAssertEqual(replacement.addedAt, attachment.addedAt)
        XCTAssertNotEqual(replacement.fileName, attachment.fileName)
        // Editing prepares new files and never overwrites strokes referenced by a saved snapshot.
        XCTAssertNoThrow(try DrawingAttachmentStore.load(attachment))
        XCTAssertNoThrow(try DrawingAttachmentStore.load(replacement))
        let legacy = KanbanAttachment(fileName: "old-photo.jpg", mediaKind: .photo)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        object.removeValue(forKey: "drawingFileName")
        let legacyRestored = try JSONDecoder().decode(KanbanAttachment.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacyRestored.drawingFileName)
        XCTAssertEqual(legacyRestored.storedFileNames, ["old-photo.jpg"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDrawingRejectedAndPartialSavesCleanBothFiles
    /// @brief      Verify that drawing Rejected And Partial Saves Clean Both Files
    /// @details    Exercises `QuickCaptureMediaCommit.save`, `XCTUnwrap(CardAttachmentStore.fileURL(for:
    ///             attachment)).deletingLastPathComponent`, `CardAttachmentStore.fileURL`. Checks `XCTAssertFalse(try
    ///             QuickCaptureMediaCommit.save([], drawings: [draft]) { rejected = $0; return false })`;
    ///             `XCTAssertFalse(FileManager.default.fileExists(atPath:
    ///             directory.appendingPathComponent(name).path))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDrawingRejectedAndPartialSavesCleanBothFiles() throws {
        let draft = DrawingCaptureDraft(drawing: drawingFixture())
        var rejected: [KanbanAttachment] = []
        XCTAssertFalse(try QuickCaptureMediaCommit.save([], drawings: [draft]) { rejected = $0; return false })
        let attachment = try XCTUnwrap(rejected.first)
        let directory = try XCTUnwrap(CardAttachmentStore.fileURL(for: attachment)).deletingLastPathComponent()
        for name in attachment.storedFileNames { XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)) }
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertThrowsError(try QuickCaptureMediaCommit.save([], drawings: [draft, DrawingCaptureDraft()]) { _ in XCTFail("A partial drawing import must not commit"); return true })
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDrawingExportsPNGTransparencyAndJPEGWithoutChangingStrokes
    /// @brief      Verify that drawing Exports PNG Transparency And JPEG Without Changing Strokes
    /// @details    Exercises `drawing.dataRepresentation`, `DrawingImageExport.data`, `transparent.prefix`. Checks
    ///             `XCTAssertEqual(Array(transparent.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])`;
    ///             `XCTAssertEqual(Array(jpeg.prefix(2)), [255, 216])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDrawingExportsPNGTransparencyAndJPEGWithoutChangingStrokes() throws {
        let drawing = drawingFixture()
        let original = drawing.dataRepresentation()
        let transparent = try DrawingImageExport.data(drawing, format: .png, transparent: true)
        let opaque = try DrawingImageExport.data(drawing, format: .png)
        let jpeg = try DrawingImageExport.data(drawing, format: .jpeg)
        XCTAssertEqual(Array(transparent.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(Array(jpeg.prefix(2)), [255, 216])
        for data in [transparent, opaque, jpeg] {
            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertLessThanOrEqual(max(image.size.width * image.scale, image.size.height * image.scale), 4096)
            XCTAssertGreaterThan(image.size.width, 0)
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testDrawingExportsPNGTransparencyAndJPEGWithoutChangingStrokes.cornerAlpha
        /// @brief      Read the exported image corner alpha for transparency assertions
        /// @details    Decodes the image, draws its corner into a one-pixel bitmap, and returns the alpha byte;
        ///             failed image or context creation throws through XCTUnwrap.
        ///
        /// @param[in]  data  Encoded input or media bytes
        ///
        /// @return     (UInt8) result described by this operation's contract
        /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
        ///
        func cornerAlpha(_ data: Data) throws -> UInt8 {
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return bytes[3]
        }
        XCTAssertEqual(try cornerAlpha(transparent), 0)
        XCTAssertEqual(try cornerAlpha(opaque), 255)
        XCTAssertEqual(try cornerAlpha(jpeg), 255)
        XCTAssertEqual(drawing.dataRepresentation(), original)
        XCTAssertThrowsError(try DrawingImageExport.data(PKDrawing(), format: .png))
        XCTAssertEqual(TodayCaptureAction.allCases.map(\.rawValue), ["note", "checklist", "photo", "voice", "drawing"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDrawingEditorRendersOnPhoneAndTabletWithoutSaving
    /// @brief      Verify that drawing Editor Renders On Phone And Tablet Without Saving
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(canvas.drawing.strokes.count, 1)`;
    ///             `XCTAssertTrue(canvas.isFirstResponder)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDrawingEditorRendersOnPhoneAndTabletWithoutSaving() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        var saves = 0
        for size in [CGSize(width: 393, height: 852), CGSize(width: 744, height: 1133)] {
            let host = UIHostingController(rootView: DrawingCaptureEditor(initial: DrawingCaptureDraft(drawing: drawingFixture())) { _ in saves += 1; return true })
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(800))
            host.view.layoutIfNeeded()


            ///
            /// @fcn        PlenactBoardDocumentTests.testDrawingEditorRendersOnPhoneAndTabletWithoutSaving.canvases
            /// @brief      Find canvases in the hosted view hierarchy
            /// @details    Recursively inspects native subviews for PKCanvasView. Returns all collected matches in
            ///             hierarchy order.
            ///
            /// @param[in]  view  Native view inspected or synchronized by the operation
            ///
            /// @return     ([PKCanvasView]) resulting values in the ordering described above
            ///
            func canvases(_ view: UIView) -> [PKCanvasView] {
                (view as? PKCanvasView).map { [$0] } ?? view.subviews.flatMap(canvases)
            }
            let canvas = try XCTUnwrap(canvases(host.view).first)
            XCTAssertEqual(canvas.drawing.strokes.count, 1)
            XCTAssertTrue(canvas.isFirstResponder)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-drawing-\(Int(size.width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("DRAWING_RENDER=" + url.path)
        }
        XCTAssertEqual(saves, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testQuickCaptureActionsAndComposersRenderWithoutCreatingRecords
    /// @brief      Verify that quick Capture Actions And Composers Render Without Creating Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertTrue(fields(host.view).contains("Carry my thought
    ///             forward"))`; `XCTAssertTrue(fields(host.view).contains(""))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testQuickCaptureActionsAndComposersRenderWithoutCreatingRecords() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }


        ///
        /// @fcn        PlenactBoardDocumentTests.testQuickCaptureActionsAndComposersRenderWithoutCreatingRecords.fields
        /// @brief      Find fields in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextField, UITextView. Returns all collected
        ///             matches in hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([String]) resulting values in the ordering described above
        ///
        func fields(_ view: UIView) -> [String] {
            let value = (view as? UITextField)?.text ?? (view as? UITextView)?.text
            return (value.map { [$0] } ?? []) + view.subviews.flatMap(fields)
        }
        let lists = [KanbanList(id: 4, title: "Today", cards: [])]
        var saves = 0
        for action in TodayCaptureAction.allCases {
            let host = UIHostingController(rootView: QuickNoteComposer(lists: .constant(lists), initialListID: 4,
                initialTitle: "Carry my thought forward", captureAction: action, onSaveCapture: { _ in saves += 1; return true }) { _, _, _, _, _, _ in saves += 1 })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            XCTAssertTrue(fields(host.view).contains("Carry my thought forward"))
            if action == .checklist { XCTAssertTrue(fields(host.view).contains("")) }
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-capture-\(action.rawValue).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("CAPTURE_RENDER=" + url.path)
            if action == .photo || action == .drawing { host.dismiss(animated: false); try await Task.sleep(for: .milliseconds(100)) }
        }
        for width in [393.0, 744.0] {
            let host = UIHostingController(rootView: TodayCaptureActions { _ in XCTFail("Rendering must not activate a capture") }.padding().background(Color(.secondarySystemGroupedBackground)))
            window.frame = CGRect(x: 0, y: 0, width: width, height: 180)
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(100))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-capture-row-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("CAPTURE_RENDER=" + url.path)
        }
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(lists[0].cards.isEmpty)
        XCTAssertEqual(TodayCaptureAction.note.presentation, .note)
        XCTAssertEqual(TodayCaptureAction.checklist.presentation, .card)
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
    func testHostedTemplateComposerPrefillsTitleWithoutCreatingRecords() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
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
        func fields(in view: UIView) -> [UIView] {
            let editable = (view is UITextField || view is UITextView) ? [view] : []
            return editable + view.subviews.flatMap { fields(in: $0) }
        }
        let draftKey = "InlineComposerTest." + UUID().uuidString
        defer { ListCreationDraft.clear(key: draftKey) }
        for template in [QuickCaptureTemplate.smallPlan, .idea, nil] {
            ListCreationDraft(title: "Older saved title", subtitle: "Retained subtitle", description: "Retained body").save(key: draftKey)
            let controller = UIHostingController(rootView: QuickNoteComposer(
                lists: .constant([KanbanList(id: 4, title: "Thursday", cards: [])]),
                initialListID: 4, initialTitle: "Captured thought", draftKey: draftKey, template: template
            ) { _, _, _, _, _, _ in
                XCTFail("Reviewing a template must not create a record")
            })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(fields(in: controller.view).contains {
                ($0 as? UITextField)?.text == "Captured thought" || ($0 as? UITextView)?.text == "Captured thought"
            })
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

        let data = Data(#"{"id":1,"title":"Legacy","cards":[{"id":2,"word":"Retain","listTitle":"Legacy","checklists":[]}]}"#.utf8)  /* JSON fixture bytes for the compatibility check */
        let list = try JSONDecoder().decode(KanbanList.self, from: data)                                                             /* Decoded List fixture                           */

        XCTAssertEqual(list.newItemPresentation,   .card)
        XCTAssertEqual(list.cards[0].presentation, .card)

        let json  = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any])  /* Encoded JSON representation   */
        let cards = try XCTUnwrap(json["cards"] as? [[String: Any]])                                                 /* Card records under inspection */

        XCTAssertNil(json["defaultItemPresentation"])
        XCTAssertNil(cards[0]["itemPresentation"])
        XCTAssertNil(list.cards[0].descriptionOverride)
        XCTAssertNil(list.cards[0].createdAt)
        XCTAssertNil(cards[0]["createdAt"])

        let invalidCard = Data(#"{"id":2,"word":"Invalid","listTitle":"Legacy","itemPresentation":"unsupported"}"#.utf8)  /* Unsupported Card fixture                   */
        let invalidList = Data(#"{"id":1,"title":"Invalid","cards":[],"defaultItemPresentation":"unsupported"}"#.utf8)    /* Unsupported list-presentation JSON fixture */

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

        let timestamp = Date(timeIntervalSince1970: 1_791_422_000)   /* Fixed creation timestamp      */
        var list = KanbanList(id: 1, title: "Synthetic", cards: [])  /* List state under verification */
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

        let before = Date.now                                     /* Timestamp before the operation */
        let newCard = list.makeItem(id: 3, title: "Created now")  /* Newly created Card value       */
        let after = Date.now                                      /* Timestamp after the operation  */
        let actual = try XCTUnwrap(newCard.createdAt)             /* Observed creation timestamp    */

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

        var original   = SampleData.lists[0].cards[0]                                                   /* Pre-operation value for preservation checks */
        let attachment = KanbanAttachment(fileName: "synthetic-note-reference.jpg", mediaKind: .photo)  /* Attachment fixture under test               */

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


    ///
    /// @fcn        PlenactBoardDocumentTests.testKeyboardNeighborsStayWithinActiveListAndSkipDividers
    /// @brief      Verify that keyboard Neighbors Stay Within Active List And Skip Dividers
    /// @details    Exercises `CardKeyboardNeighbors.resolve`. Checks `XCTAssertNil(CardKeyboardNeighbors.resolve(a,
    ///             in: lists).previous)`; `XCTAssertEqual(CardKeyboardNeighbors.resolve(a, in: lists).next, b)`.
    ///
    /// @return     (Void) no return value
    ///
    func testKeyboardNeighborsStayWithinActiveListAndSkipDividers() {
        let a = KanbanCard(id: 1, word: "A", listTitle: "Today", checklists: [])
        let divider = KanbanCard(id: 2, word: "Section", listTitle: "Today", isDivider: true, checklists: [])
        let b = KanbanCard(id: 3, word: "B", listTitle: "Today", checklists: [], presentation: .note)
        let lists = [KanbanList(id: 1, title: "Today", cards: [a, divider, b]), KanbanList(id: 2, title: "Other", cards: [])]
        XCTAssertNil(CardKeyboardNeighbors.resolve(a, in: lists).previous)
        XCTAssertEqual(CardKeyboardNeighbors.resolve(a, in: lists).next, b)
        XCTAssertEqual(CardKeyboardNeighbors.resolve(b, in: lists).previous, a)
        XCTAssertNil(CardKeyboardNeighbors.resolve(b, in: lists).next)
        var archived = lists; archived[0].isArchived = true
        XCTAssertNil(CardKeyboardNeighbors.resolve(a, in: archived).next)
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
    func testKeyboardRichFontsPersistAndFormattingSupportsUndoRedo() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController(); window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        var stored = "Keep all these words"
        let editor = RichTextEditor(placeholder: "Body", text: Binding(get: { stored }, set: { stored = $0 }))
        let coordinator = editor.makeCoordinator()
        let text = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        controller.view.addSubview(text)
        text.attributedText = PlanRichText.attributed(stored)
        coordinator.view = text
        text.becomeFirstResponder()
        let undo = try XCTUnwrap(text.undoManager)
        undo.removeAllActions(); undo.groupsByEvent = false
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
    /// @fcn        PlenactBoardDocumentTests.testSharedKeyboardAttachesToPlainFieldsAndRendersNarrowAndWide
    /// @brief      Verify that shared Keyboard Attaches To Plain Fields And Renders Narrow And Wide
    /// @details    Exercises `PlenactKeyboard.shared.install`, `NotificationCenter.default.post`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks `XCTAssertTrue(field.inputAccessoryView
    ///             is PlenactKeyboardToolbar)`; `XCTAssertEqual(field.keyboardType, .emailAddress)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testSharedKeyboardAttachesToPlainFieldsAndRendersNarrowAndWide() throws {
        PlenactKeyboard.shared.install()
        let field = UITextField(); field.keyboardType = .emailAddress
        NotificationCenter.default.post(name: UITextField.textDidBeginEditingNotification, object: field)
        XCTAssertTrue(field.inputAccessoryView is PlenactKeyboardToolbar)
        XCTAssertEqual(field.keyboardType, .emailAddress)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController(); window.rootViewController = controller; window.makeKeyAndVisible()
        let token = UUID()
        PlenactKeyboard.shared.setContext(token, actions: KeyboardCardActions(exit: {}, previous: {}, next: {}, attachment: {}, checklist: {}))
        defer { PlenactKeyboard.shared.removeContext(token); window.isHidden = true; previous?.makeKeyAndVisible() }
        for width: CGFloat in [320, 393, 820] {
            let toolbar = PlenactKeyboardToolbar(input: field, formatting: KeyboardFormatting(toggle: { _ in }, color: { _ in }, font: { _, _ in }))
            toolbar.frame = CGRect(x: 0, y: 0, width: width, height: 44)
            controller.view.addSubview(toolbar); toolbar.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: toolbar.bounds).image { _ in toolbar.drawHierarchy(in: toolbar.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-keyboard-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("KEYBOARD_RENDER=" + url.path)
            toolbar.removeFromSuperview()
        }
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
        func editor(in view: UIView) -> UITextView? {
            if let text = view as? UITextView { return text }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
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
        func buttons(in view: UIView) -> [UIButton] {
            (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let controls = buttons(in: toolbar)
        XCTAssertEqual(controls.compactMap(\.accessibilityLabel), ["Return from Card or Note", "Previous item in this list", "Next item in this list", "Undo text edit", "Redo text edit", "Add attachment", "Add checklist", "Font and formatting", "Hide keyboard"])
        XCTAssertNotNil(controls.first(where: { $0.accessibilityLabel == "Font and formatting" })?.menu)
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
    func testChecklistEditingSelectsWholeExistingItem() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var text = "Cut or replace this item 😊"
        var focused = false
        let host = UIHostingController(rootView: ChecklistTextField(text: Binding(get: { text }, set: { text = $0 }), focus: Binding(get: { focused }, set: { focused = $0 })))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; previous?.makeKeyAndVisible() }
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
        func find(in view: UIView) -> UITextField? {
            if let field = view as? UITextField { return field }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
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
    /// @fcn        PlenactBoardDocumentTests.testListCopyAllocatesIDsAndPreservesContentAndInternalLinks
    /// @brief      Verify that list Copy Allocates I Ds And Preserves Content And Internal Links
    /// @details    Exercises `.linkedCard`, `ListCopying.copy`, `copy.allCards.map`. Checks `XCTAssertEqual(copy.id,
    ///             9)`; `XCTAssertEqual(copy.allCards.map(\.id), [21, 22])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListCopyAllocatesIDsAndPreservesContentAndInternalLinks() throws {
        var first = KanbanCard(id: 1, word: "First", listTitle: "Source", descriptionOverride: "Keep", sectionLayout: CardSectionLayout(hidden: [.details]))
        first.checklists = [KanbanChecklist(title: "Links", items: [KanbanChecklistItem(title: "Internal", content: .linkedCard(cardID: 2)), KanbanChecklistItem(title: "External", content: .linkedCard(cardID: 99))])]
        let archived = KanbanCard(id: 2, word: "Archived", listTitle: "Source")
        var source = KanbanList(id: 1, title: "Source", cards: [first], archivedCards: [archived], newItemPresentation: .note)
        source.subtitleOverride = "Subtitle"
        let destination = [KanbanList(id: 8, title: "Other", cards: [KanbanCard(id: 20, word: "Existing", listTitle: "Other")])]
        let copy = ListCopying.copy(source, into: destination, crossBoard: true)
        XCTAssertEqual(copy.id, 9)
        XCTAssertEqual(copy.allCards.map(\.id), [21, 22])
        XCTAssertEqual(copy.cards.first?.descriptionOverride, "Keep")
        XCTAssertEqual(copy.cards.first?.sectionLayout, first.sectionLayout)
        XCTAssertEqual(copy.newItemPresentation, .note)
        XCTAssertEqual(copy.subtitleOverride, "Subtitle")
        XCTAssertEqual(copy.cards[0].checklists[0].items[0].content, .linkedCard(cardID: 22))
        XCTAssertEqual(copy.cards[0].checklists[0].items[1].content, .standard)
        XCTAssertEqual(source.cards[0].checklists[0].items[0].content, .linkedCard(cardID: 2))
        XCTAssertEqual(try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(copy)), copy)
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testMultilineEntriesPreserveOrderIgnoreBlankLinesAndCreateDistinctCards
    /// @brief      Verify that multiline Entries Preserve Order Ignore Blank Lines And Create Distinct Cards
    /// @details    Exercises `MultilineEntry.titles`, `list.makeItems`, `cards.map`. Checks
    ///             `XCTAssertEqual(MultilineEntry.titles(input), ["A", "B", "C", "D", "A"])`;
    ///             `XCTAssertTrue(MultilineEntry.titles(" \n\t\r\n").isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewItemsUseBlankOrEnteredSubtitleAndPersistIt
    /// @brief      Verify that new Items Use Blank Or Entered Subtitle And Persist It
    /// @details    Exercises `list.makeItem`. Checks `XCTAssertEqual(blank.subtitleOverride, "")`;
    ///             `XCTAssertEqual(blank.subtitle, "")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testListNoteDefaultAppliesOnlyToNewNondividerItems
    /// @brief      Verify that list Note Default Applies Only To New Nondivider Items
    /// @details    Exercises `list.makeItem`, `card.checklists.map`, `legacyCard.checklists.map`. Checks
    ///             `XCTAssertEqual(card.presentation, .card)`; `XCTAssertEqual(card.word, legacyCard.word)`.
    ///
    /// @return     (Void) no return value
    ///
    func testListNoteDefaultAppliesOnlyToNewNondividerItems() {

        let existing = KanbanCard(id: 1, word: "Existing", listTitle: "Ideas")  /* Existing Card retained while applying List defaults */
        var list     = KanbanList(id: 1, title: "Ideas", cards: [existing])     /* List state under verification                       */
        let card     = list.makeItem(id: 2, title: "Action")                    /* Card value under verification                       */

        let legacyCard = KanbanCard(id: 2, word: "Action", listTitle: "Ideas") /* Legacy-format Card fixture */

        XCTAssertEqual(card.presentation,                                   .card)
        XCTAssertEqual(card.word,                                           legacyCard.word)
        XCTAssertEqual(card.descriptionOverride,                            legacyCard.descriptionOverride)
        XCTAssertEqual(card.checklists.map(\.title),                        legacyCard.checklists.map(\.title))
        XCTAssertEqual(card.checklists.flatMap(\.items).map(\.title),       legacyCard.checklists.flatMap(\.items).map(\.title))
        XCTAssertEqual(card.checklists.flatMap(\.items).map(\.isCompleted), legacyCard.checklists.flatMap(\.items).map(\.isCompleted))

        list.newItemPresentation = .note
        let note                 = list.makeItem(id: 3, title: "Thought")  /* Newly created Note value */
        let divider              = list.makeItem(id: 4, title: "---")      /* Section-divider fixture  */

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

        let suite    = "Plenact.NotePersistenceTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))        /* Isolated test preferences      */

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

        let week    = PersonalCollection.archivedWeekBoard(lists: [restored], savedCardIDs: [note.id])     /* Archived weekly-board fixture    */
        let decoded = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(week))  /* Decoded archived-week collection */

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

        var collection = PersonalCollection(title: "Synthetic ideas", kind: .list)                  /* Personal List receiving its default              */
        let existingCard = KanbanCard(id: 20, word: "Keep this Card", listTitle: collection.title)  /* Existing Card content that must remain unchanged */

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
    func testPersonalCreationHonorsSelectedKindWithoutChangingListDefault() throws {
        var collection = PersonalCollection(title: "Ideas", kind: .list)
        let createdAt = try XCTUnwrap(PlanningDate.date("2026-10-13"))
        let body = "First paragraph\n\nSecond paragraph  "
        try collection.addNote(title: "A card", body: body, createdAt: createdAt, presentation: .card, subtitle: " Useful context ")
        try collection.addNote(title: "A note", body: body, createdAt: createdAt, presentation: .note)
        XCTAssertEqual(collection.lists[0].newItemPresentation, .note)
        let cards = collection.lists[0].cards
        XCTAssertEqual(cards.map(\.presentation), [.card, .note])
        XCTAssertEqual(cards[0].subtitleOverride, "Useful context")
        XCTAssertTrue(cards.allSatisfy { $0.descriptionOverride == body && $0.createdAt == createdAt })
        XCTAssertNotEqual(cards[0].id, cards[1].id)
        XCTAssertEqual(try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection)), collection)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreatingPersonalListNoteUsesFreshIdentityAndPreservesBody
    /// @brief      Verify that creating Personal List Note Uses Fresh Identity And Preserves Body
    /// @details    Exercises `collection.lists[0].makeItem`, `collection.addNote`, `board.addNote`. Checks
    ///             `XCTAssertThrowsError(try collection.addNote(title: " \n ", body: "Uncommitted"))`;
    ///             `XCTAssertEqual(collection, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCreatingPersonalListNoteUsesFreshIdentityAndPreservesBody() throws {

        var collection = PersonalCollection(title: "Synthetic ideas", kind: .list)  /* Collection state under verification                 */
        let existing = collection.lists[0].makeItem(id: 7, title: "Existing")       /* Existing active Card retained during Note insertion */
        let archived   = collection.lists[0].makeItem(id: 12, title: "Archived")    /* Archived value for restoration checks               */

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
                subtitleOverride:    "",
                presentation:        .note,
                createdAt:           createdAt
            )
        ])

        XCTAssertEqual(collection.lists[0].archivedCards, [archived])

        var board       = PersonalCollection(title: "Not a list", kind: .board)  /* Board state under verification          */
        let boardBefore = board                                                  /* Board state before the attempted change */

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

        let link = try XCTUnwrap(URL(string: "https://example.com/synthetic"))  /* Synthetic link target   */
        let attachments = [                                                     /* Retained attachment set */
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
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)                                                   /* Previously focused window       */
        let window = UIWindow(windowScene: scene)                                                                  /* Temporary window for UI hosting */

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

            var emitted: [KanbanCard] = []                                    /* Captured callback results               */
            let controller = UIHostingController(rootView: NavigationStack {  /* Hosted controller for layout assertions */
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

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)                                                   /* Previously focused window       */
        let window = UIWindow(windowScene: scene)                                                                  /* Temporary window for UI hosting */
        defer {

            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }

        let photo = KanbanAttachment(exampleImage: .garden)                                                    /* Synthetic photo fixture       */
        var card = KanbanCard(id: 94, word: "Synthetic cover layout", listTitle: "Synthetic", checklists: [])  /* Card value under verification */
        card.appearance = ItemAppearance(icon: .project, background: .blue)
        card.attachments = [
            photo,
            KanbanAttachment(exampleImage: .camping, caption: "Our next adventure"),
            KanbanAttachment(exampleImage: .mountains)
        ]
        var covered = card /* Card with a selected cover */
        covered.coverAttachmentID = photo.id
        for fixture in [card, covered] {

            var emitted: [KanbanCard] = []                                    /* Captured callback results               */
            let controller = UIHostingController(rootView: NavigationStack {  /* Hosted controller for layout assertions */
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

        let cover = KanbanAttachment(exampleImage: .garden)                                            /* Selected cover attachment     */
        let otherPhoto = KanbanAttachment(exampleImage: .mountains)                                    /* Non-cover photo attachment    */
        let link = KanbanAttachment(url: try XCTUnwrap(URL(string: "https://example.com/synthetic")))  /* Synthetic link target         */
        let video = KanbanAttachment(fileName: "synthetic-video.mov", mediaKind: .video)               /* Video attachment fixture      */
        var card = KanbanCard(                                                                         /* Card value under verification */
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

        let initial = PersonalCollection(title: "Initial ideas", kind: .list)    /* Initial destination collection to preserve   */
        let selected = PersonalCollection(title: "Selected ideas", kind: .list)  /* Selected destination collection for the Note */
        var collections = [initial, selected]                                    /* Saved personal-collection state              */
        var draft = PersonalListNoteDraft(destinationID: initial.id)             /* Uncommitted draft under test                 */
        let originalCreationDate = draft.createdAt                               /* Timestamp retained by the operation          */

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

        let active = PersonalCollection(title: "Active ideas", kind: .list)      /* Active personal collection used as an invalid target */
        let board = PersonalCollection(title: "Projects", kind: .board)          /* Board state under verification                       */
        var archived = PersonalCollection(title: "Archived ideas", kind: .list)  /* Archived value for restoration checks                */
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

        let initial = PersonalCollection(title: "Initial ideas", kind: .list)    /* Initial destination collection to preserve   */
        let selected = PersonalCollection(title: "Selected ideas", kind: .list)  /* Selected destination collection for the Note */
        let collections = [initial, selected]                                    /* Saved personal-collection state              */
        var draft = PersonalListNoteDraft(destinationID: initial.id)             /* Uncommitted draft under test                 */
        let originalCreationDate = draft.createdAt                               /* Timestamp retained by the operation          */
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

        let attachment = KanbanAttachment(fileName: "synthetic-moved-note.jpg", mediaKind: .photo)  /* Attachment fixture under test */
        var note = KanbanCard(                                                                      /* Note value under verification */
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

        var collections = [source, destination]               /* Saved personal-collection state       */
        let moved = try PersonalCollectionNoteMovement.move(  /* Note after relocation to another List */
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

        let board = PersonalCollection(title: "Not a destination List", kind: .board)  /* Board state under verification */
        var boardMove = [source, board]                                                /* Board movement result          */
        let beforeBoardMove = boardMove                                                /* Board snapshot before movement */

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

        var source = PersonalCollection(title: "Ideas", kind: .list)                                                /* Source state before the operation */
        var note = KanbanCard(id: 14, word: "Read later", listTitle: "Ideas", checklists: [], presentation: .note)  /* Note value under verification     */
        note.descriptionOverride = "Synthetic body"
        source.lists[0].cards = [note]

        let destination = PersonalCollection(title: "Someday", kind: .list)  /* Target location for the move    */
        var collections = [source, destination]                              /* Saved personal-collection state */

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

        let first  = PersonalCollection(title: "First ideas", kind: .list)   /* First value in the comparison  */
        let recent = PersonalCollection(title: "Recent ideas", kind: .list)  /* Most recent activity entry     */
        let board  = PersonalCollection(title: "Projects", kind: .board)     /* Board state under verification */

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

        var current = [PersonalCollection(title: "First ideas", kind: .list)]                                         /* Current collections displayed by the Library */
        let scene    = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting                  */
        let previous = scene.windows.first(where: \.isKeyWindow)                                                      /* Previously focused window                    */
        let window   = UIWindow(windowScene: scene)                                                                   /* Temporary window for UI hosting              */

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

        let scene    = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)                                                      /* Previously focused window       */
        let window   = UIWindow(windowScene: scene)                                                                   /* Temporary window for UI hosting */

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
    /// @fcn        PlenactBoardDocumentTests.testOfflineLibraryContains400DistinctBundledIllustrations()
    /// @brief      Verify the complete eight-category library is shipped with the app
    /// @details    Checks actual app resources, exact canvas dimensions, distinct bytes, and total
    ///             size. Does not enable covers or write personal media files
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Missing bundle resources, image decoding, or file-read errors
    ///
    func testOfflineLibraryContains400DistinctBundledIllustrations() throws {

        let categories = CoverCategory.allCases /* Available attachment categories */

        XCTAssertEqual(categories.count, 8)

        for category in categories {

            XCTAssertEqual(category.images.count, 50, category.rawValue)
        }

        let images = categories.flatMap(\.images)  /* Synthetic image fixtures         */
        let names  = images.map(\.rawValue)        /* Bundled illustration asset names */

        XCTAssertEqual(names.count,      400)
        XCTAssertEqual(Set(names).count, 400)
        XCTAssertEqual(Set(images),      Set(ExampleCoverImage.allCases))

        var distinctImages: Set<Data> = []  /* Distinct image fixtures  */
        var totalBytes                = 0   /* Combined image-data size */

        for name in names {

            let url = try XCTUnwrap(Bundle.main.url( /* URL fixture for the request */

                forResource: name, withExtension: "png", subdirectory: "CardCoverImages"

            ), "Missing bundled illustration: \(name)")

            let bytes = try Data(contentsOf: url)                                                         /* Bundled illustration bytes   */
            let image = try XCTUnwrap(UIImage(data: bytes)?.cgImage, "Unreadable illustration: \(name)")  /* Decoded cropped-avatar image */

            XCTAssertEqual(image.width,  960, name)
            XCTAssertEqual(image.height, 480, name)
            XCTAssertTrue(distinctImages.insert(bytes).inserted, "Duplicate illustration: \(name)")

            totalBytes += bytes.count
        }

        XCTAssertEqual(distinctImages.count, 400)
        XCTAssertLessThan(totalBytes, 150_000_000, "Keep offline artwork within the 150 MB budget")

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

        let photo = KanbanAttachment(fileName: "synthetic-personal.jpg", mediaKind: .photo)  /* Synthetic photo fixture       */
        var card = KanbanCard(id: 9, word: "My plan", listTitle: "Local", checklists: [],    /* Card value under verification */
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

        let snapshot = card                                          /* Persisted snapshot under verification */
        var list = KanbanList(id: 1, title: "Local", cards: [card])  /* List state under verification         */

        list.archiveCard(id: card.id)

        let decoded = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list)) /* Decoded List round-trip value */

        XCTAssertEqual(decoded.archivedCards.first, snapshot)

        try card.setCover(nil)

        XCTAssertEqual(card.attachments, snapshot.attachments)

        try card.useLibraryCover(.garden)

        XCTAssertEqual(card.attachments?.count, ExampleCoverImage.allCases.count + 1)
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

        let legacy = Data(#"{"id":1,"word":"Synthetic","listTitle":"Local","checklists":[]}"#.utf8)  /* Legacy-format fixture */
        var card = try JSONDecoder().decode(KanbanCard.self, from: legacy)                           /* Decoded Card fixture  */

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

        let first = KanbanAttachment(fileName: "first.jpg", mediaKind: .photo)                  /* First value in the comparison  */
        let second = KanbanAttachment(fileName: "second.jpg", mediaKind: .photo)                /* Second value in the comparison */
        let video = KanbanAttachment(fileName: "video.mov", mediaKind: .video)                  /* Video attachment fixture       */
        let link = KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link)  /* Synthetic link target          */
        var card = KanbanCard(id: 1, word: "Synthetic", listTitle: "Local", checklists: [],     /* Card value under verification  */
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

        let photo = KanbanAttachment(mediaKind: .photo, exampleImage: .garden)                                     /* Synthetic photo fixture       */
        var card = KanbanCard(id: 1, word: "Synthetic", listTitle: "Local", checklists: [], attachments: [photo])  /* Card value under verification */

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

            let thumbnail = try CardAttachmentStore.coverThumbnail(for: photo)  /* Rendered attachment thumbnail */
            let image = try XCTUnwrap(thumbnail.cgImage)                        /* Synthetic image fixture       */

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

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600), format: format)  /* Synthetic image renderer                   */
        let bytes = renderer.pngData { context in                                                        /* Rendered PNG bytes for the oversized cover */
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }

        let photo = try CardAttachmentStore.saveMedia(bytes, kind: .photo, fileExtension: "png")  /* Synthetic photo fixture */
        let fileName = try XCTUnwrap(photo.fileName)                                              /* Stored avatar filename  */

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

        let suite = "Plenact.CoverLayoutTests.\(UUID().uuidString)"   /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let photo = KanbanAttachment(mediaKind: .photo, exampleImage: .garden)            /* Synthetic photo fixture       */
        let card = KanbanCard(id: 1, word: "Garden", listTitle: "Local", checklists: [],  /* Card value under verification */
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

        let standard = measure(.standard, enabled: true)  /* Standard Card baseline      */
        let overview = measure(.overview, enabled: true)  /* Overview layout measurement */

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

        let card = KanbanCard(id: 12, word: "Synthetic", listTitle: "Retained", checklists: [])    /* Card value under verification    */
        var archivedList = KanbanList(id: 3, title: "Retained", cards: [], archivedCards: [card])  /* List containing archived records */

        archivedList.isArchived = true

        var snapshot = [archivedList, KanbanList(id: 4, title: "Other", cards: [ /* Persisted snapshot under verification */
            KanbanCard(id: 13, word: "Keep", listTitle: "Other", checklists: [])
        ])]
        let independent = [archivedList]    /* Independent archived List set        */
        var bookmarks: Set<Int> = [12, 13]  /* Saved-card bookmarks before deletion */

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
        var snapshot = [first, second]          /* Persisted snapshot under verification */
        var bookmarks: Set<Int> = [10, 11, 12]  /* Saved-card bookmarks before deletion  */

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

        let candidate = try CardAttachmentStore.saveMedia(Data([1, 2, 3]), kind: .photo, fileExtension: "jpg")  /* Candidate value for validation */
        let unrelated = try CardAttachmentStore.saveMedia(Data([4, 5, 6]), kind: .photo, fileExtension: "jpg")  /* Unrelated retained value       */
        let candidateName = try XCTUnwrap(candidate.fileName)                                                   /* Candidate display name         */
        let unrelatedName = try XCTUnwrap(unrelated.fileName)                                                   /* Unrelated display name         */

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

        let suite = "Plenact.ListLifecycleTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

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

        let suite = "Plenact.DeletionCompletionTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))        /* Isolated test preferences      */

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

        let suite = "Plenact.CheckedDeletionTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

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

        let suite = "Plenact.PersonalExampleTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

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

        let originalBytes = defaults.data(forKey: "Plenact.PersonalCollections.v1")                              /* Serialized bytes used by the fixture */
        let first = PersonalListExample.shopping.makeCollection(existingTitles: [retained.title])                /* First value in the comparison        */
        let second = PersonalListExample.shopping.makeCollection(existingTitles: [retained.title, first.title])  /* Second value in the comparison       */

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

        let week = SampleData.lists                                                 /* Archived weekly-board fixture         */
        var archived = PersonalCollection(title: "Archived fixture", kind: .board)  /* Archived value for restoration checks */

        archived.isArchived = true

        let restored    = PersonalCollection(title: "Week Board (Restored)", kind: .board)                               /* Restored value under verification               */
        let personal    = PersonalCollection(title: "Personal fixture", kind: .list)                                     /* Personal List fixture filtered from demo Boards */
        let collections = [personal, restored, archived]                                                                 /* Saved personal-collection state                 */
        let scene       = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting                     */
        let previous    = scene.windows.first(where: \.isKeyWindow)                                                      /* Previously focused window                       */
        let window      = UIWindow(windowScene: scene)                                                                   /* Temporary window for UI hosting                 */

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
            XCTAssertGreaterThanOrEqual(standard.height, 48)
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


        ///
        /// @fcn        PlenactBoardDocumentTests.testStandardBoardHasEqualFifteenPointNeighborPreviews
        /// @brief      Verify that standard Board Has Equal Fifteen Point Neighbor Previews
        /// @details    Exercises `BoardPresentation.standard.columnWidth`. Checks `XCTAssertEqual(sideInset - 17,
        ///             15)`; `XCTAssertEqual(width + 2 * sideInset, viewport)`.
        ///
        /// @return     (Void) no return value
        ///
        func testStandardBoardHasEqualFifteenPointNeighborPreviews() {

            for viewport: CGFloat in [320, 360, 393, 414, 424] {
                let width = BoardPresentation.standard.columnWidth(viewportWidth: viewport, accessibilitySize: false)
                let sideInset = (viewport - width) / 2
                XCTAssertEqual(sideInset - 17, 15, accuracy: 0.001,
                               "Each side must show 15 points of its neighbor after the 17-point gap")
                XCTAssertEqual(width + 2 * sideInset, viewport, accuracy: 0.001)
            }
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

        let suite    = "Plenact.CollectionWidthTests.\(UUID().uuidString)"                                            /* Isolated preferences-suite key  */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))                                                  /* Isolated test preferences       */
        let scene    = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)                                                      /* Previously focused window       */
        let window   = UIWindow(windowScene: scene)                                                                   /* Temporary window for UI hosting */

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
                        onCreateNote:              { _, _, _ in XCTFail("Layout must not create an item") },
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

                let listWidth          = try XCTUnwrap(measured[.list])                      /* Proposed List width       */
                let boardWidth         = try XCTUnwrap(measured[.board])                     /* Proposed Board width      */
                let expectedDifference = preset == .standard ? max(0, width - 28 - 360) : 0  /* Expected width difference */

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

        let suite = "Plenact.BoardPresentationTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))       /* Isolated test preferences      */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let week = try JSONEncoder().encode(SampleData.lists)                     /* Archived weekly-board fixture  */
        var board = PersonalCollection(title: "Synthetic project", kind: .board)  /* Board state under verification */

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


        let standard = measuredHeight(.standard, size: .large, width: 360)  /* Standard Card baseline         */
        let overview = measuredHeight(.overview, size: .large, width: 240)  /* Measured Overview panel height */

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

            let width: CGFloat = preset == .standard ? 360 : 240                                /* Proposed layout width          */
            let shortProposal = controller.sizeThatFits(in: CGSize(width: width, height: 300))  /* Compact-height layout proposal */
            let tallProposal = controller.sizeThatFits(in: CGSize(width: width, height: 900))   /* Tall layout proposal           */

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

        let card = KanbanCard(id: 102, word: "Review the week ahead", listTitle: "Synthetic list")                 /* Card value under verification   */
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting     */
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)                                          /* Previously active key window    */
        let window = UIWindow(windowScene: scene)                                                                  /* Temporary window for UI hosting */

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

            let collection = try XCTUnwrap(collectionView(in: controller.view))  /* Collection state under verification */
            let row = try XCTUnwrap(collection.visibleCells.first)               /* Rendered collection row             */

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

        var lists            = SampleData.lists                                              /* Board lists under verification                           */
        let original         = lists                                                         /* Pre-operation value for preservation checks              */
        let card             = try XCTUnwrap(lists[0].cards.first { !$0.isSectionDivider })  /* Card value under verification                            */
        var targetList: Int? = lists[0].id                                                   /* List identity selected before returning to the Week root */
        var targetCard: Int? = card.id                                                       /* Card identity selected before returning to the Week root */
        var saved: Set<Int>  = [card.id]                                                     /* Persisted value under verification                       */


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

        let controller = UIHostingController(rootView: board(0))                                                        /* Hosted controller for layout assertions */
        let scene      = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting             */
        let previous   = scene.windows.first(where: \.isKeyWindow)                                                      /* Previously focused window               */
        let window     = UIWindow(windowScene: scene)                                                                   /* Temporary window for UI hosting         */

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

        let suite = "Plenact.BoardRelayoutTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        var lists = SampleData.lists /* Board lists under verification */
        lists[0].archiveCard(id: lists[0].cards[0].id)
        var archived = SampleData.lists[1] /* Archived value for restoration checks */

        archived.isArchived = true

        var archives = [archived]                                                          /* Archived-card collection               */
        var saved: Set<Int> = [lists[0].archivedCards[0].id]                               /* Persisted value under verification     */
        let focusedListID = lists[3].id                                                    /* Focused List identifier                */
        var targetList: Int? = focusedListID                                               /* List identity to focus after relayout  */
        var targetCard: Int?                                                               /* Card identity to reveal after relayout */
        var visibleListID: Int?                                                            /* Visible List identifier                */
        let revealedTarget = expectation(description: "Reveal the requested middle list")  /* Card revealed by edge navigation       */
        var didRevealTarget = false                                                        /* Whether navigation revealed its target */
        let originalLists = lists                                                          /* List snapshots before movement         */
        let originalArchives = archives                                                    /* Archive snapshots before movement      */
        let originalSaved = saved                                                          /* Saved-card identifiers before movement */
        let view = ContentView(                                                            /* Hosted view under test                 */
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

        let controller = UIHostingController(rootView: view)                                                       /* Hosted controller for layout assertions */
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting             */
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)                                          /* Previously active key window            */
        let window = UIWindow(windowScene: scene)                                                                  /* Temporary window for UI hosting         */

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

        let lists = SampleData.lists  /* Board lists under verification              */
        let original = lists          /* Pre-operation value for preservation checks */

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

        var lists = SampleData.lists      /* Board lists under verification        */
        let monday = lists.removeFirst()  /* Restored Monday List after reordering */

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

        var lists = SampleData.lists  /* Board lists under verification              */
        let original = lists          /* Pre-operation value for preservation checks */

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

        let first = KanbanCard(id: 1, word: "First", listTitle: "Synthetic", descriptionOverride: "Keep this")  /* First retained card fixture  */
        let divider = KanbanCard(id: 2, word: "", listTitle: "Synthetic", isDivider: true)                      /* Movable divider fixture      */
        let last = KanbanCard(id: 3, word: "Last", listTitle: "Synthetic", isTitleChecked: true)                /* Last retained card fixture   */
        var cards = [first, divider, last]                                                                      /* Ordered focused-list records */

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

        let cardsBeforeMove = SampleData.lists[0].cards  /* Original complete card sequence */
        var cards = cardsBeforeMove                      /* Mutable card-order copy         */

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

        let retained = KanbanCard(id: 901, word: "Archived", listTitle: "Source")  /* Archived Card retained by its source List */
        var lists = [                                                              /* Board lists under verification            */
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

        let cards = (1...4).map { KanbanCard(id: $0, word: "Card \($0)", listTitle: "A") }  /* Card records under inspection  */
        var lists = [KanbanList(id: 10, title: "A", cards: cards),                          /* Board lists under verification */
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

        let card = KanbanCard(id: 1, word: "Card", listTitle: "A")                                      /* Card value under verification  */
        let divider = KanbanCard(id: 2, word: "", listTitle: "A", isDivider: true)                      /* Section-divider fixture        */
        let archive = KanbanCard(id: 3, word: "Retained", listTitle: "A")                               /* Archived-card snapshot         */
        var lists = [KanbanList(id: 10, title: "A", cards: [card, divider], archivedCards: [archive]),  /* Board lists under verification */
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


    ///
    /// @fcn        PlenactBoardDocumentTests.testDividerMovementPreservesRecordsWithinAndBetweenLists
    /// @brief      Verify that divider Movement Preserves Records Within And Between Lists
    /// @details    Exercises `BoardCardMovement.move`. Checks `XCTAssertTrue(try BoardCardMovement.move(divider.id,
    ///             to: 10, in: &lists))`; `XCTAssertEqual(lists[0].cards, [card, divider])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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

        let suite = "Plenact.CardMovementTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        var lists = SampleData.lists                                             /* Board lists under verification */
        let card = try XCTUnwrap(lists[0].cards.first { !$0.isSectionDivider })  /* Card value under verification  */
        let destination = lists[1].id                                            /* Target location for the move   */

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


        ///
        /// @fcn        PlenactBoardDocumentTests.testDayViewNativeDragReordersCanonicalNotesAndPreservesCancelledDrags.collectionView
        /// @brief      Find collection view in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UICollectionView. Returns the first qualifying match,
        ///             or nil when none is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UICollectionView?) matching or resolved value, or nil when unavailable
        ///
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

        TransferConfirmationPresenter.shared.showUndo(TransferConfirmation(title: "Other section", destination: "Another day")) { true }
        defer { TransferConfirmationPresenter.shared.dismiss() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(scene.windows.contains { !$0.isHidden && $0.windowLevel > .alert })
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
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)  /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)                                                   /* Previously focused window       */
        let window = UIWindow(windowScene: scene)                                                                  /* Temporary window for UI hosting */

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
                canMoveEarlier:       false, canMoveLater: false, onAddCard: { _ in true },
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

            let collection = try XCTUnwrap(collectionView(in: controller.view))  /* Collection state under verification */
            let itemCount = (0..<collection.numberOfSections).reduce(0) {        /* Expected item count                 */
                $0 + collection.numberOfItems(inSection: $1)
            }

            XCTAssertEqual(itemCount, 4, "Three content rows plus Add card; no separate section creation row")

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

        let declarations = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])  /* Declarations under inspection       */
        let declaration = try XCTUnwrap(declarations.first {                                                                          /* Declaration record under inspection */
            ($0["UTTypeIdentifier"] as? String) == BoardCardDragSource.contentType.identifier
        })

        XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], ["public.data"])

        var points: [CGPoint] = []                                    /* Sample layout coordinates         */
        var ended = 0                                                 /* Completed drag state              */
        let source = BoardCardDragSource(token: "synthetic-session",  /* Source state before the operation */
                                         onBegan: { points.append($0) },
                                         onChanged: { points.append($0) },
                                         onEnded:   { ended += 1 })
        let coordinator = source.makeCoordinator()   /* Drop coordinator under test */
        let point = CGPoint(x: 150, y: 320)          /* Synthetic drop coordinate   */
        let provider = coordinator.begin(at: point)  /* Native drag-item provider   */

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

        var ended = 0                                                                                         /* Completed drag state              */
        let source = BoardCardDragSource(token: "synthetic-session", onBegan: { _ in }, onChanged: { _ in },  /* Source state before the operation */
                                         onEnded: { ended += 1 })
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

        let card = KanbanCard(id: 1, word: "Synthetic", listTitle: "Source")  /* Card value under verification  */
        var lists = [KanbanList(id: 10, title: "Source", cards: [card]),      /* Board lists under verification */
                     KanbanList(id: 20, title: "Destination", cards: [])]
        var ends = 0                                                               /* Drag completion events            */
        let source = BoardCardDragSource(token: "local-board", onBegan: { _ in },  /* Source state before the operation */
                                         onChanged: { _ in }, onEnded: { ends += 1 }).makeCoordinator()
        let item = UIDragItem(itemProvider: source.begin(at: .zero)) /* Checklist item under verification */

        item.localObject = source

        var points: [CGPoint] = []                                                               /* Sample layout coordinates */
        let drop = BoardCardDropSurface(token: "local-board", onChanged: { points.append($0) },  /* Drop operation result     */
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

        let suite = "Plenact.WeekArchiveTests.\(UUID().uuidString)"   /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

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

        let original = SampleData.lists[0]                              /* Pre-operation value for preservation checks */
        var snapshot = [original, SampleData.lists[1]]                  /* Persisted snapshot under verification       */
        let board = Binding(get: { snapshot }, set: { snapshot = $0 })  /* Board state under verification              */
        var archived = original                                         /* Archived value for restoration checks       */

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

        let sourceLists = [list, archivedList]                                                        /* Source List snapshots                           */
        let savedIDs: Set<Int> = [list.archivedCards[0].id]                                           /* Card IDs expected in the archived-week snapshot */
        var board = PersonalCollection.archivedWeekBoard(lists: sourceLists, savedCardIDs: savedIDs)  /* Board state under verification                  */
        let boardID = board.id                                                                        /* Stable Board identifier                         */

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

        let suite = "Plenact.BoardArchiveTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

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

        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let board = PersonalCollection(title: "Project", kind: .board)                                    /* Board state under verification              */
        let other = PersonalCollection(title: "Shopping", kind: .list)                                    /* Unrelated model fixture                     */
        let original = [board, other]                                                                     /* Pre-operation value for preservation checks */
        let updated = try PersonalCollectionStore.archiveBoard(id: board.id, in: original, to: defaults)  /* Updated state after mutation                */

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

        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let board = PersonalCollection(title: "Project", kind: .board) /* Board state under verification */

        try PersonalCollectionStore.saveChecked([board], to: defaults)

        var draft = board                                                                      /* Uncommitted draft under test */
        var invalidCard = KanbanCard(id: 1, word: "Unsaved", listTitle: draft.lists[0].title)  /* Unsupported Card fixture     */

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

        let suite = "Plenact.ArchiveCommitTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))   /* Isolated test preferences      */

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

        let original = PersonalCollection(title: "Project", kind: .board)                                                 /* Pre-operation value for preservation checks */
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])  /* Serialized JSON object                      */

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

        let data = Data("{\"id\":1,\"title\":\"Monday\",\"cards\":[]}".utf8)  /* JSON fixture bytes for the compatibility check */
        let list = try JSONDecoder().decode(KanbanList.self, from: data)      /* Decoded List fixture                           */

        XCTAssertTrue(list.archivedCards.isEmpty)

        let encoded = try JSONEncoder().encode(list)                                               /* Encoded model payload  */
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])  /* Serialized JSON object */

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

        let active = KanbanCard(id: 500, word: "Active", listTitle: "Monday")                                           /* Active Card before archival   */
        let divider = KanbanCard(id: 501, word: "Divider", listTitle: "Monday", isDivider: true, isTitleChecked: true)  /* Section-divider fixture       */
        var list = KanbanList(id: 1, title: "Monday", cards: [completed, divider, active])                              /* List state under verification */

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

        let archived = KanbanCard(id: 900, word: "Archived task", listTitle: "Monday", isTitleChecked: true)  /* Archived value for restoration checks */
        let list = KanbanList(                                                                                /* List state under verification         */
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

        let divider = KanbanCard(id: 800, word: "Divider", listTitle: "Monday", isDivider: true)  /* Section-divider fixture       */
        var list = KanbanList(id: 1, title: "Monday", cards: [incomplete, complete, divider])     /* List state under verification */

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

        var collection = PersonalCollection(title: "Original", kind: .list)                               /* Collection state under verification   */
        let archived = KanbanCard(id: 42, word: "Archived", listTitle: "Original", isTitleChecked: true)  /* Archived value for restoration checks */
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

            let initialCount = DatabaseActivity.shared.operations.count               /* Initial request count       */
            let url = try XCTUnwrap(URL(string: "https://\(outcome).example.test/"))  /* URL fixture for the request */
            let client = try PlenactAPIClient(baseURL: url, session: session)         /* In-process API client       */

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

        let suite = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

        defer {

            defaults.removePersistentDomain(forName: suite)
        }

        let first = [KanbanList(id: 1, title: "First", cards: [])]  /* First value in the comparison */
        let last = [KanbanList(id: 1, title: "Latest", cards: [])]  /* Most recent request           */

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

        let suite    = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))        /* Isolated test preferences      */

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

        let suite    = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))        /* Isolated test preferences      */

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

        let suite    = "Plenact.SearchTests.\(UUID().uuidString)"     /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

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

        let divider = KanbanCard(id: 1, word: "Divider", listTitle: "Monday", isDivider: true)  /* Section-divider fixture        */
        let lists = [                                                                           /* Board lists under verification */
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

        let suite    = "Plenact.ExampleLoadUndoTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))        /* Isolated test preferences      */

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

        let suite    = "Plenact.LastViewedListTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))       /* Isolated test preferences      */

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

        let lists    = Array(SampleData.lists.reversed())                                              /* Board lists under verification              */
        let original = lists                                                                           /* Pre-operation value for preservation checks */
        let names    = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]  /* Expected weekday title sequence             */

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

        let date     = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6)))  /* Date value for boundary checks        */
        let monday   = KanbanList(id: 1, title: "Monday", cards: [])                                      /* Monday List fixture for weekday focus */
        let tuesday  = KanbanList(id: 2, title: "Tuesday", cards: [])                                     /* Tuesday planning fixture              */
        var archived = tuesday                                                                            /* Archived value for restoration checks */

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
        ])                                                                       /* Previously renamed weekday list retained without modification */
        var archivedThursday = KanbanList(id: 20, title: "Thursday", cards: [])  /* Archived weekday list reserves its old ID                     */
        archivedThursday.isArchived = true
        let lists = [renamed, archivedThursday]          /* Complete Week fixture                              */
        var calendar = Calendar(identifier: .gregorian)  /* Fixed calendar for deterministic weekday selection */

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))        /* Thursday selection date              */
        let result = TodayListSelection.ensureCurrentDayList(lists: lists, date: thursday, calendar: calendar)  /* Recreated active weekday destination */

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

        var first = PersonalCollection(title: "First", kind: .list)                                      /* First independent collection */
        let firstCard = KanbanCard(id: 1, word: "First item", listTitle: "First", checklists: [])        /* Active bookmark              */
        let divider = KanbanCard(id: 2, word: "—", listTitle: "First", isDivider: true, checklists: [])  /* Non-bookmarkable separator   */
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

        let suite    = "Plenact.PersonalCollectionTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))           /* Isolated test preferences      */

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
        let encoded = try JSONEncoder().encode(document)                                  /* Versioned JSON */
        let decoded = try JSONDecoder().decode(PlenactBoardDocument.self, from: encoded)  /* Restored Board */

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
        let document = PlenactAPIClient.sampleDataDocument(for: jim)                /* Seed transformed for Jim */
        let seededAssignments = document.lists.flatMap(\.cards).flatMap(\.members)  /* All seed assignments     */

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

        let maximumBody   = Data(repeating: 0, count: PlenactAPIClient.maximumJSONBodyBytes)      /* Allowed request-body size */
        let oversizedBody = Data(repeating: 0, count: PlenactAPIClient.maximumJSONBodyBytes + 1)  /* Oversized request payload */

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
@MainActor
private final class NoteNavigationProbe: ObservableObject {
    @Published var path: [KanbanCard] = []
    var visibleNotes: Set<UUID> = []
    var noteIsVisible: Bool { !visibleNotes.isEmpty }
}
private struct NoteNavigationTestView: View {
    @ObservedObject var probe: NoteNavigationProbe
    var body: some View {
        NavigationStack(path: $probe.path) {
            Text("Week")
                .navigationDestination(for: KanbanCard.self) { card in CardDetailView(card: card) }
        }
        .environment(\.workspaceNoteVisibility, { id, visible in
            if visible { probe.visibleNotes.insert(id) } else { probe.visibleNotes.remove(id) }
        })
    }
}

@MainActor
private final class DirectReturnTestProbe: ObservableObject {
    @Published var presented = false
}

private struct DirectReturnTestView: View {
    @ObservedObject var probe: DirectReturnTestProbe
    let owner: PersonalCollection
    let week: DatedPlanningWeek?
    let listID: Int
    var body: some View {
        Text("Origin remains here")
            .fullScreenCover(isPresented: $probe.presented) {
                if let week {
                    PlanningCalendarWeekView(week: week, initialDayID: listID, initialCardID: 701,
                        onLeaveForHome: { XCTFail("Back must not invoke explicit home navigation") })
                } else {
                    PlanningSearchLibraryView(collection: owner, initialListID: listID, initialCardID: 701,
                        onLeaveForHome: { XCTFail("Back must not invoke explicit home navigation") })
                }
            }
    }
}
