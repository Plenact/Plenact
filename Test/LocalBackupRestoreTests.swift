// --------------------------------------------------------------------------------------------------
// @file       LocalBackupRestoreTests.swift
// @brief      Isolated Simulator backup review, source recovery and undo regression tests
// @details    User Data Model 1.0 preparation; legacy-source restore only. Synthetic private
//             preference suites and temporary containers never access the user's Simulator data.
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import Foundation
import XCTest


/// Verifies review-before-write and rollback-protected source recovery.
/// @section Purpose
///     Demonstrate recovery behavior without claiming complete portable migration.
@MainActor
final class LocalBackupRestoreTests: XCTestCase
{

    /// @fcn LocalBackupRestoreTests.fixture
    /// @brief Provide a synthetic source backup, isolated destination and transactional store
    /// @param[in] body Assertions with source, destination root, suite/domain and recovery store
    /// @return Void after removing only this test's owned files and suite
    /// @throws Setup or test-operation errors
    private func fixture(_ body: (URL, URL, UserDefaults, String, FullMonthExampleStore) throws -> Void) throws
    {

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let domain = "Plenact.RestoreTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer
        {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let sourceRoot = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        let week = DatedPlanningWeek.make(for: Date(timeIntervalSince1970: 1792843200), calendar: calendar)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week])
        defaults.set(try JSONEncoder().encode(document), forKey: "Plenact.CalendarWeeks.v1")
        defaults.set(try JSONEncoder().encode(week.collection.lists), forKey: "Plenact.Board.v1")
        let originals = sourceRoot.appendingPathComponent("Documents/CardAttachments")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try Data([7, 8, 9]).write(to: originals.appendingPathComponent("original.bin"))
        let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: sourceRoot)
        let preview = try MigrationPreview.prepare(backup: backup, journalURL: root.appendingPathComponent("SourceJournal/identities.json"))
        let exported = root.appendingPathComponent("backup")
        try preview.files.write(to: exported, options: .atomic, originalContentsURL: nil)
        defaults.setPersistentDomain(["destinationOnly": "retained", "Plenact.Board.v1": Data("[]".utf8)], forName: domain)
        let destination = root.appendingPathComponent("destination")
        let store = FullMonthExampleStore(root: destination.appendingPathComponent("Library/Recovery"),
            documents: destination.appendingPathComponent("Documents"),
            support: destination.appendingPathComponent("Library/Application Support"), domainName: domain)
        try body(exported, destination, defaults, domain, store)
    }


    /// @fcn LocalBackupRestoreTests.testReviewDoesNotChangeDestination
    /// @brief Review actual saved source bytes without creating a recovery journal or changing stores
    /// @return Void after source counts and destination nonmutation assertions
    /// @throws Fixture or review errors
    func testReviewDoesNotChangeDestination() throws
    {

        try fixture { source, _, defaults, domain, store in
            let before = defaults.persistentDomain(forName: domain)!
            let review = try LocalBackupRestore.review(at: source)
            XCTAssertEqual(review.storeCount, 2)
            XCTAssertEqual(review.listCount, 7)
            XCTAssertEqual(review.mediaCount, 1)
            XCTAssertNotNil(review.journal)
            XCTAssertFalse(store.hasNativeRestoreBackup)
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.persistentDomain(forName: domain)!))
        }
    }


    /// @fcn LocalBackupRestoreTests.testRestoreAndUndoPreserveExactSavedBytesAndOriginalFiles
    /// @brief Install reviewed source, retain rollback evidence, and restore the exact previous destination
    /// @return Void after import and undo comparisons
    /// @throws Fixture, filesystem or persistence errors
    func testRestoreAndUndoPreserveExactSavedBytesAndOriginalFiles() throws
    {

        try fixture { source, destination, defaults, domain, store in
            let review = try LocalBackupRestore.review(at: source)
            let original = defaults.persistentDomain(forName: domain)!
            let folder = destination.appendingPathComponent("Documents/CardAttachments")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let oldMedia = folder.appendingPathComponent("old.bin")
            try Data([1, 2, 3]).write(to: oldMedia)
            try store.installNativeSource
            {
                try LocalBackupRestore.install(review, root: destination, defaults: defaults, domain: domain)
            }
            XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), review.values["Plenact.Board.v1"] as? Data)
            XCTAssertEqual(defaults.string(forKey: "destinationOnly"), "retained")
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldMedia.path))
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("original.bin")), Data([7, 8, 9]))
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Library/Application Support/PlenactMigration/source-identities-v1.json")), review.journal)
            XCTAssertTrue(store.hasNativeRestoreBackup)
            XCTAssertFalse(store.needsRecovery)
            try store.undoNativeSource()
            XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: domain)!))
            XCTAssertEqual(try Data(contentsOf: oldMedia), Data([1, 2, 3]))
            XCTAssertFalse(store.hasNativeRestoreBackup)
        }
    }


    /// @fcn LocalBackupRestoreTests.testInstallationFailureRestoresPreviousDestination
    /// @brief Fail after partial preference/media changes and require verified transactional rollback
    /// @return Void after exact original-state verification
    /// @throws Fixture errors
    func testInstallationFailureRestoresPreviousDestination() throws
    {

        try fixture { _, destination, defaults, domain, store in
            let original = defaults.persistentDomain(forName: domain)!
            XCTAssertThrowsError(try store.installNativeSource
            {
                defaults.set("partial", forKey: "Plenact.Partial")
                try FileManager.default.createDirectory(at: destination.appendingPathComponent("Documents"), withIntermediateDirectories: true)
                try Data([9]).write(to: destination.appendingPathComponent("Documents/partial.bin"))
                throw CocoaError(.fileWriteUnknown)
            })
            XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: domain)!))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Documents/partial.bin").path))
            XCTAssertFalse(store.needsRecovery)
        }
    }


    /// @fcn LocalBackupRestoreTests.testTamperedPreferencesAreRejectedBeforeRestore
    /// @brief Do not accept altered bytes merely because a backup folder name matches
    /// @return Void after integrity failure and no rollback-state creation
    /// @throws Fixture errors
    func testTamperedPreferencesAreRejectedBeforeRestore() throws
    {

        try fixture { source, _, _, _, store in
            try Data("changed".utf8).write(to: source.appendingPathComponent("Preferences.plist"))
            XCTAssertThrowsError(try LocalBackupRestore.review(at: source))
            XCTAssertFalse(store.hasNativeRestoreBackup)
        }
    }


    /// @fcn LocalBackupRestoreTests.testUndeclaredMediaAndSymlinksAreRejected
    /// @brief Verify full original-file membership and refuse filesystem link traversal
    /// @return Void after both rejection paths
    /// @throws Fixture errors
    func testUndeclaredMediaAndSymlinksAreRejected() throws
    {

        try fixture { source, _, _, _, _ in
            let directory = source.appendingPathComponent("Documents/CardAttachments")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("extra.bin")
            try Data([7]).write(to: file)
            XCTAssertThrowsError(try LocalBackupRestore.review(at: source))
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("alias"), withDestinationURL: source.appendingPathComponent("Preferences.plist"))
            XCTAssertThrowsError(try LocalBackupRestore.review(at: source))
        }
    }


    /// @fcn LocalBackupRestoreTests.testRepeatedImportCannotReplacePreviousUndoEvidence
    /// @brief Preserve the original destination rather than overwrite its recovery copy on another import
    /// @return Void after rejecting repeat import and retaining undo
    /// @throws Fixture or persistence errors
    func testRepeatedImportCannotReplacePreviousUndoEvidence() throws
    {

        try fixture { source, destination, defaults, domain, store in
            let review = try LocalBackupRestore.review(at: source)
            try store.installNativeSource
            {
                try LocalBackupRestore.install(review, root: destination, defaults: defaults, domain: domain)
            }
            XCTAssertThrowsError(try store.installNativeSource {})
            XCTAssertTrue(store.hasNativeRestoreBackup)
            try store.undoNativeSource()
        }
    }
}
