// --------------------------------------------------------------------------------------------------
// @file       MigrationPreviewTests.swift
// @brief      Repeatable source identities and first canonical migration adapters
// @details    Supported User Data Model versions: 1.0; local journal/preview format 1.
//             Uses isolated source preferences and temporary media/journals only; never real accounts.
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import Foundation
import XCTest


/// Exercises retry identity, integrity failure and explicit partial conversion boundaries.
/// @section Purpose
///     Demonstrate source preservation and portable metadata before full-workspace migration.
@MainActor
final class MigrationPreviewTests: XCTestCase
{

    /// @fcn MigrationPreviewTests.fixture
    /// @brief Capture synthetic source values inside a disposable test container
    /// @param[in] values Explicit saved preferences
    /// @param[in] body Assertions receiving the frozen backup and private journal path
    /// @return Void after cleanup
    /// @throws Setup, source capture or assertion support errors
    private func fixture(_ values: [String: Any] = [:],
        _ body: (LegacyWorkspaceBackup, URL) throws -> Void) throws
    {

        let domain = "Plenact.MigrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults.setPersistentDomain(values, forName: domain)
        defer
        {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
        try body(backup, root.appendingPathComponent("Library/Application Support/PlenactMigration/source-identities-v1.json"))
    }


    /// @fcn MigrationPreviewTests.library
    /// @brief Build exact legacy label JSON without source examples or loaders
    /// @param[in] category Referenced category, optionally missing for a rejection case
    /// @return Synthetic label-library bytes
    /// @throws JSON encoding errors
    private func library(category: String = "same") throws -> Data
    {

        try JSONSerialization.data(withJSONObject: [
            "categories": [["id": "same", "name": "  Personal 🪴  "]],
            "labels": [["id": "same", "name": "Quiet attention", "categoryID": category, "color": "green"]]
        ])
    }


    /// @fcn MigrationPreviewTests.records
    /// @brief Decode the preview's canonical record files for independent assertions
    /// @param[in] preview Completed partial migration
    /// @return Ordered JSON document objects
    /// @throws Missing output or invalid JSON
    private func records(_ preview: MigrationPreview) throws -> [[String: Any]]
    {

        let folder = try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"])
        return try (folder.fileWrappers ?? [:]).sorted { $0.key < $1.key }.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.value.regularFileContents)) as? [String: Any])
        }
    }


    /// @fcn MigrationPreviewTests.testIdentitySurvivesRestartAndPreservesOwnerDiscriminators
    /// @brief Retry mappings without merging owners, kinds or distinct source creations
    /// @return Void after source-key comparisons
    /// @throws Journal resolution/encoding errors
    func testIdentitySurvivesRestartAndPreservesOwnerDiscriminators() throws
    {

        var journal = MigrationIdentityJournal()
        let source = MigrationSourceIdentity(recordType: "card", owner: "collection-A", legacyID: "7", discriminator: nil)
        let identity = try journal.resolve(source)
        var reopened = try MigrationIdentityJournal.decode(journal.encoded())
        XCTAssertEqual(try reopened.resolve(source), identity)
        XCTAssertEqual(reopened.sourceInstallationID, journal.sourceInstallationID)
        for other in [
            MigrationSourceIdentity(recordType: "card", owner: "collection-B", legacyID: "7", discriminator: nil),
            MigrationSourceIdentity(recordType: "list", owner: "collection-A", legacyID: "7", discriminator: nil),
            MigrationSourceIdentity(recordType: "card", owner: "collection-A", legacyID: "7", discriminator: "source-created-2")
        ]
        {
            XCTAssertNotEqual(try reopened.resolve(other), identity)
        }
    }


    /// @fcn MigrationPreviewTests.testCorruptFutureUnknownAndCollidingJournalsAreRejected
    /// @brief Fail closed rather than silently resetting or dropping mapping evidence
    /// @return Void after structural rejection cases
    /// @throws Fixture encoding errors
    func testCorruptFutureUnknownAndCollidingJournalsAreRejected() throws
    {

        XCTAssertThrowsError(try MigrationIdentityJournal.decode(Data("not-json".utf8)))
        var journal = MigrationIdentityJournal()
        _ = try journal.resolve(MigrationSourceIdentity(recordType: "label", owner: "labels", legacyID: "one", discriminator: nil))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: journal.encoded()) as? [String: Any])
        object["formatVersion"] = 2
        XCTAssertThrowsError(try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: object)))
        object["formatVersion"] = 1
        object["future"] = true
        XCTAssertThrowsError(try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "future")
        let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        object["entries"] = entries + entries
        XCTAssertThrowsError(try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: object)))
        object["entries"] = entries
        object["previewWorkspaceID"] = "00000000-0000-0000-0000-000000000000"
        XCTAssertThrowsError(try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: object)))
    }


    /// @fcn MigrationPreviewTests.testStaleJournalWriterCannotOverwriteDurableMappings
    /// @brief Compare the exact baseline before atomic replacement
    /// @return Void after durable bytes remain unchanged
    /// @throws Fixture or journal I/O errors
    func testStaleJournalWriterCannotOverwriteDurableMappings() throws
    {

        try fixture { _, url in
            let journal = MigrationIdentityJournal()
            try MigrationIdentityStore.save(journal, at: url, expected: nil)
            let original = try XCTUnwrap(MigrationIdentityStore.read(at: url))
            XCTAssertThrowsError(try MigrationIdentityStore.save(MigrationIdentityJournal(), at: url, expected: nil))
            XCTAssertEqual(try MigrationIdentityStore.read(at: url), original)
        }
    }


    /// @fcn MigrationPreviewTests.testConvertedRecordsAreStableAndRetainExactWriting
    /// @brief Convert labels/display values twice, independently preserving source bytes and UUID links
    /// @return Void after attaching actual Swift output for external schema validation
    /// @throws Fixture, conversion or output-decoding errors
    func testConvertedRecordsAreStableAndRetainExactWriting() throws
    {

        let source = try library()
        try fixture(["Plenact.LabelLibrary.v1": source, "Plenact.ActivityShowsCovers": false,
            "Plenact.BoardPresentation.v1": "overview", "Plenact.Board.v1": Data("[]".utf8)]) { backup, url in
            let first = try MigrationPreview.prepare(backup: backup, journalURL: url)
            let second = try MigrationPreview.prepare(backup: backup, journalURL: url)
            XCTAssertEqual(first.recordCount, 3)
            let documents = try records(first)
            let repeated = try records(second)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: documents, options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: repeated, options: .sortedKeys))
            let category = try XCTUnwrap(documents[0]["payload"] as? [String: Any])
            let label = try XCTUnwrap(documents[1]["payload"] as? [String: Any])
            XCTAssertEqual(category["name"] as? String, "  Personal 🪴  ")
            XCTAssertEqual(label["category_id"] as? String, documents[0]["id"] as? String)
            XCTAssertNotEqual(documents[0]["id"] as? String, documents[1]["id"] as? String)
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: first.files),
                try MigrationBackupReader.file("Preferences.plist", in: backup.files))
            let copy = try MigrationBackupReader.file("MigrationPreview/IdentityJournal.json", in: first.files)
            XCTAssertEqual(copy, try MigrationIdentityStore.read(at: url))
            XCTAssertEqual(first.remainingStores, ["Plenact.Board.v1"])
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: documents, options: [.prettyPrinted, .sortedKeys]),
                uniformTypeIdentifier: "public.json")
            attachment.name = "native-migration-records.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }


    /// @fcn MigrationPreviewTests.testUnsetFalseAndTrueDisplayChoicesRemainDistinct
    /// @brief Never coerce missing preferences into the current platform's defaults
    /// @return Void after complete-value payload checks
    /// @throws Fixture or conversion errors
    func testUnsetFalseAndTrueDisplayChoicesRemainDistinct() throws
    {

        try fixture(["Plenact.CardCovers.enabled": false, "Plenact.ActivityShowsCovers": true]) { backup, url in
            let payload = try XCTUnwrap(records(MigrationPreview.prepare(backup: backup, journalURL: url)).first?["payload"] as? [String: Any])
            XCTAssertEqual(payload["card_covers_enabled"] as? Bool, false)
            XCTAssertEqual(payload["activity_shows_covers"] as? Bool, true)
            XCTAssertTrue(payload["board_presentation"] is NSNull)
            XCTAssertTrue(payload["activity_recent_square_cards"] is NSNull)
        }
    }


    /// @fcn MigrationPreviewTests.testAbsentStoresNeverManufacturePortableExamples
    /// @brief Leave an empty source empty even though the app has bundled defaults
    /// @return Void after confirming explicit partial/unlinked status
    /// @throws Fixture or conversion errors
    func testAbsentStoresNeverManufacturePortableExamples() throws
    {

        try fixture { backup, url in
            let result = try MigrationPreview.prepare(backup: backup, journalURL: url)
            XCTAssertEqual(result.recordCount, 0)
            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: MigrationBackupReader.file("MigrationPreview/Report.json", in: result.files)) as? [String: Any])
            XCTAssertEqual(report["portable_conversion_complete"] as? Bool, false)
            XCTAssertEqual(report["cloud_account_linked"] as? Bool, false)
            XCTAssertEqual(report["workspace_identity_scope"] as? String, "local_preview")
        }
    }


    /// @fcn MigrationPreviewTests.testMissingLabelCategoryRejectsWithoutCreatingJournal
    /// @brief Do not fabricate a category to make a broken source library appear valid
    /// @return Void after verifying no output identity file is persisted
    /// @throws Fixture errors
    func testMissingLabelCategoryRejectsWithoutCreatingJournal() throws
    {

        try fixture(["Plenact.LabelLibrary.v1": library(category: "missing")]) { backup, url in
            XCTAssertThrowsError(try MigrationPreview.prepare(backup: backup, journalURL: url))
            XCTAssertNil(try MigrationIdentityStore.read(at: url))
        }
    }


    /// @fcn MigrationPreviewTests.testDuplicateLabelsAndUnknownSourceFieldsAreRejected
    /// @brief Reject lossy decoder normalization and ambiguous duplicate source identities
    /// @return Void after explicit failures
    /// @throws Fixture encoding errors
    func testDuplicateLabelsAndUnknownSourceFieldsAreRejected() throws
    {

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: library()) as? [String: Any])
        let labels = try XCTUnwrap(object["labels"] as? [[String: Any]])
        object["labels"] = labels + labels
        try fixture(["Plenact.LabelLibrary.v1": JSONSerialization.data(withJSONObject: object)]) { backup, url in
            XCTAssertThrowsError(try MigrationPreview.prepare(backup: backup, journalURL: url))
            XCTAssertNil(try MigrationIdentityStore.read(at: url))
        }
        object["labels"] = labels
        object["new-field"] = "must not be discarded"
        try fixture(["Plenact.LabelLibrary.v1": JSONSerialization.data(withJSONObject: object)]) { backup, url in
            XCTAssertThrowsError(try MigrationPreview.prepare(backup: backup, journalURL: url))
        }
    }


    /// @fcn MigrationPreviewTests.testWrongNativePreferenceTypesAreNotCoerced
    /// @brief Distinguish Boolean storage from integer 0/1 and reject future display tokens
    /// @return Void after explicit rejection
    /// @throws Fixture errors
    func testWrongNativePreferenceTypesAreNotCoerced() throws
    {

        for values: [String: Any] in [["Plenact.CardCovers.enabled": 1], ["Plenact.BoardPresentation.v1": "future"]]
        {
            try fixture(values) { backup, url in
                XCTAssertThrowsError(try MigrationPreview.prepare(backup: backup, journalURL: url))
                XCTAssertNil(try MigrationIdentityStore.read(at: url))
            }
        }
    }


    /// @fcn MigrationPreviewTests.testChangedSourceEvidenceBlocksBeforeJournalWrite
    /// @brief Hash-check source bytes rather than converting an unverified modified wrapper
    /// @return Void after integrity rejection
    /// @throws Fixture errors
    func testChangedSourceEvidenceBlocksBeforeJournalWrite() throws
    {

        try fixture { backup, url in
            let original = try XCTUnwrap(backup.files.fileWrappers?["Preferences.plist"])
            backup.files.removeFileWrapper(original)
            let changed = FileWrapper(regularFileWithContents: try PropertyListSerialization.data(fromPropertyList: ["changed": true], format: .binary, options: 0))
            changed.preferredFilename = "Preferences.plist"
            backup.files.addFileWrapper(changed)
            XCTAssertThrowsError(try MigrationPreview.prepare(backup: backup, journalURL: url))
            XCTAssertNil(try MigrationIdentityStore.read(at: url))
        }
    }


    /// @fcn MigrationPreviewTests.testPendingReviewRecoveryBlocksConversion
    /// @brief Preserve pending recovery rather than executing or ignoring its transactional boundary
    /// @return Void after blocked conversion
    /// @throws Fixture errors
    func testPendingReviewRecoveryBlocksConversion() throws
    {

        try fixture(["Plenact.DailyReviewTransaction.v1": Data("pending".utf8)]) { backup, url in
            XCTAssertThrowsError(try MigrationPreview.prepare(backup: backup, journalURL: url))
            XCTAssertNil(try MigrationIdentityStore.read(at: url))
        }
    }


    /// @fcn MigrationPreviewTests.testDeviceAndRecoveryStateAreNotListedAsSyncWork
    /// @brief Preserve local state while keeping the partial conversion's remaining work explicit
    /// @return Void after lifecycle classification assertions
    /// @throws Fixture or report errors
    func testDeviceAndRecoveryStateAreNotListedAsSyncWork() throws
    {

        try fixture(["Plenact.ActivityRecents.v1": Data("[]".utf8), "Plenact.ExampleLoadUndo.v1": Data("old-source".utf8),
            "Plenact.SavedCardIDs.v1": [7]]) { backup, url in
            let result = try MigrationPreview.prepare(backup: backup, journalURL: url)
            XCTAssertEqual(result.remainingStores, ["Plenact.SavedCardIDs.v1"])
            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: MigrationBackupReader.file("MigrationPreview/Report.json", in: result.files)) as? [String: Any])
            XCTAssertEqual(report["device_local_stores_preserved"] as? [String], ["Plenact.ActivityRecents.v1"])
            XCTAssertEqual(report["recovery_stores_preserved"] as? [String], ["Plenact.ExampleLoadUndo.v1"])
        }
    }


    /// @fcn MigrationPreviewTests.testCorruptExistingJournalIsNeverReset
    /// @brief Retain original corrupt evidence when conversion cannot trust retry identity
    /// @return Void after exact file-byte comparison
    /// @throws Fixture or filesystem errors
    func testCorruptExistingJournalIsNeverReset() throws
    {

        try fixture(["Plenact.LabelLibrary.v1": library()]) { backup, url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = Data("corrupt-journal".utf8)
            try original.write(to: url)
            XCTAssertThrowsError(try MigrationPreview.prepare(backup: backup, journalURL: url))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    /// @fcn MigrationPreviewTests.testExistingNamespaceCannotBeReplacedEvenWithCurrentBaseline
    /// @brief Keep source-installation and portable identities immutable across valid writes
    /// @return Void after rejecting a fresh namespace and preserving exact journal bytes
    /// @throws Fixture or journal errors
    func testExistingNamespaceCannotBeReplacedEvenWithCurrentBaseline() throws
    {

        try fixture { _, url in
            let original = MigrationIdentityJournal()
            try MigrationIdentityStore.save(original, at: url, expected: nil)
            let baseline = try XCTUnwrap(MigrationIdentityStore.read(at: url))
            XCTAssertThrowsError(try MigrationIdentityStore.save(MigrationIdentityJournal(), at: url, expected: baseline))
            XCTAssertEqual(try MigrationIdentityStore.read(at: url), baseline)
        }
    }


    /// @fcn MigrationPreviewTests.testSubsequentBackupPreservesJournalAndPreviewResumesItsNamespace
    /// @brief Capture durable migration state alongside source bytes before another conversion attempt
    /// @return Void after round-trip source identity and original journal-byte checks
    /// @throws Fixture, source-capture or conversion errors
    func testSubsequentBackupPreservesJournalAndPreviewResumesItsNamespace() throws
    {

        try fixture(["Plenact.LabelLibrary.v1": library()]) { backup, url in
            let first = try MigrationPreview.prepare(backup: backup, journalURL: url)
            let baseline = try XCTUnwrap(MigrationIdentityStore.read(at: url))
            let domain = "Plenact.MigrationResumeTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defaults.setPersistentDomain(try MigrationBackupReader.values(in: backup), forName: domain)
            defer
            {
                defaults.removePersistentDomain(forName: domain)
            }
            var root = url
            for _ in 0..<4
            {
                root.deleteLastPathComponent()
            }
            let resumedBackup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            XCTAssertEqual(try MigrationBackupReader.file("Migration/IdentityJournal.json", in: resumedBackup.files), baseline)
            let resumed = try MigrationPreview.prepare(backup: resumedBackup, journalURL: url)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: records(first), options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: records(resumed), options: .sortedKeys))
        }
    }

}
