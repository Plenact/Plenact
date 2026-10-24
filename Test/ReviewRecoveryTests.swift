// --------------------------------------------------------------------------------------------------
// @file       ReviewRecoveryTests.swift
// @brief      Review Recovery regression tests
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
/// ReviewRecovery regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


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
    func testSectionMoveJournalRestoresImportanceAndSupportsLegacyRecovery() throws
    {

        let suite = "SectionMoveJournal." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let before = Data("before".utf8)
        defaults.set(before, forKey: LibraryImportanceSelection.key)
        defaults.set(Data("board".utf8), forKey: "Plenact.Board.v1")
        XCTAssertThrowsError(
            try DailyReviewTransaction.perform(in: defaults, additionalKeys: [LibraryImportanceSelection.key])
            {

                defaults.set(Data("after".utf8), forKey: LibraryImportanceSelection.key)
                defaults.set(Data("changed".utf8), forKey: "Plenact.Board.v1")
                throw CocoaError(.fileWriteUnknown)
            })
        XCTAssertEqual(defaults.data(forKey: LibraryImportanceSelection.key), before)
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), Data("board".utf8))
        XCTAssertNil(defaults.object(forKey: DailyReviewTransaction.key))
        // Old journals did not capture importance; recovering them must not remove it.
        let legacy = try PropertyListSerialization.data(
            fromPropertyList: ["version": 1, "previous": ["Plenact.Board.v1": Data("old".utf8)]], format: .binary,
            options: 0)
        defaults.set(legacy, forKey: DailyReviewTransaction.key)
        try DailyReviewTransaction.recover(in: defaults)
        XCTAssertEqual(defaults.data(forKey: LibraryImportanceSelection.key), before)
        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), Data("old".utf8))
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
    func testWeeklyReviewCalendarBoundariesPersistenceAndRecovery() throws
    {

        let name = "PlenactTests.Weekly." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!;
        calendar.firstWeekday = 2
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18))!
        var review = WeeklyReviewRecord(date: date, calendar: calendar)
        XCTAssertEqual(review.startKey, "2026-10-12")
        var days = DailyPlanStore.Document()
        for key in ["2026-10-11", "2026-10-12", "2026-10-18", "2026-10-19"]
        {

            let day = DailyPlan(date: PlanningDate.date(key, calendar: calendar)!, calendar: calendar)
            days.plans[key] = day
        }

        XCTAssertEqual(review.dailyPlans(in: days).map(\.id), ["2026-10-12", "2026-10-18"])
        review.highlights = "Made room for important work";
        review.step = 2
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
    func testEveningReviewTransactionRecoversInterruptedAndFailedWrites() throws
    {

        let name = "PlenactTests.Review." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        for key in DailyReviewTransaction.keys
        {
            defaults.set(Data(key.utf8), forKey: key)
        }

        defaults.removeObject(forKey: DailyPlanStore.key)


        ///
        /// Injects a deterministic review-transaction failure in a test
        ///
        /// @section    Purpose
        ///     Forces rollback after preferences have changed so the test can verify restoration of
        ///     all retained keys.
        ///
        enum Forced: Error
        {

            case failure
        }

        XCTAssertThrowsError(
            try DailyReviewTransaction.perform(in: defaults)
            {

                for key in DailyReviewTransaction.keys
                {
                    defaults.set("changed", forKey: key)
                }

                throw Forced.failure
            })
        for key in DailyReviewTransaction.keys where key != DailyPlanStore.key
        {

            XCTAssertEqual(defaults.data(forKey: key), Data(key.utf8))
        }

        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        _ = try DailyReviewTransaction.begin(in: defaults)
        defaults.set("interrupted", forKey: DailyPlanStore.key)
        try DailyReviewTransaction.recover(in: defaults)
        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        try DailyReviewTransaction.perform(in: defaults)
        {
            defaults.set("committed", forKey: DailyPlanStore.key)
        }

        XCTAssertEqual(defaults.string(forKey: DailyPlanStore.key), "committed")
        XCTAssertNil(defaults.object(forKey: DailyReviewTransaction.key))
        let corrupt = Data("invalid journal".utf8)
        defaults.set(corrupt, forKey: DailyReviewTransaction.key)
        XCTAssertThrowsError(try DailyReviewTransaction.recover(in: defaults))
        XCTAssertEqual(defaults.data(forKey: DailyReviewTransaction.key), corrupt)
        XCTAssertEqual(defaults.string(forKey: DailyPlanStore.key), "committed")
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
    func testFullMonthBackupRejectsCorruptionAndRecoversInterruptedSwitch() throws
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
        let failed = FullMonthExampleStore(
            root: blocked, documents: store.documents, support: store.support, domainName: name)
        XCTAssertThrowsError(try failed.loadExample(FullMonthExample.make()))
        XCTAssertTrue(NSDictionary(dictionary: defaults.persistentDomain(forName: name) ?? [:]).isEqual(to: previous))
    }

}
