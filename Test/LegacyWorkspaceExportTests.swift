// --------------------------------------------------------------------------------------------------
// @file       LegacyWorkspaceExportTests.swift
// @brief      Native migration-preparation backup regression coverage
// @details    Supports User Data Model 1.0 preparation and source backup format 1 only.
//             All tests use isolated preferences and temporary synthetic media; no user data is read.
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import Foundation
import XCTest


/// Verifies exact source preservation before portable migration is implemented.
/// @section Purpose
///     Exercise corruption, absence, media safety, native decoding and immutable export boundaries.
@MainActor
final class LegacyWorkspaceExportTests: XCTestCase
{

    /// @fcn LegacyWorkspaceExportTests.fixture
    /// @brief Run an isolated capture scenario and remove only its owned temporary fixtures
    /// @param[in] body Assertions receiving a fresh preferences suite, domain and container
    /// @return Void after test cleanup
    /// @throws Fixture setup or assertion-support errors
    private func fixture(_ body: (UserDefaults, String, URL) throws -> Void) throws
    {

        let domain = "Plenact.ExportTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer
        {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        try body(defaults, domain, root)
    }


    /// @fcn LegacyWorkspaceExportTests.bytes
    /// @brief Resolve a known relative path inside an in-memory backup
    /// @param[in] path Expected backup entry
    /// @param[in] wrapper Complete directory tree
    /// @return Original regular-file bytes
    /// @throws An XCTest unwrap failure for a missing entry
    private func bytes(_ path: String, in wrapper: FileWrapper) throws -> Data
    {

        var entry = wrapper
        for part in path.split(separator: "/")
        {
            entry = try XCTUnwrap(entry.fileWrappers?[String(part)])
        }
        return try XCTUnwrap(entry.regularFileContents)
    }


    /// @fcn LegacyWorkspaceExportTests.testAbsentStoresDoNotBecomeExamples
    /// @brief Keep absent stores absent, excluding registered defaults and unrelated preferences
    /// @return Void after verifying an explicitly incomplete portable-conversion report
    /// @throws Fixture or plist errors
    func testAbsentStoresDoNotBecomeExamples() throws
    {

        try fixture { defaults, domain, root in
            defaults.register(defaults: ["Plenact.Board.v1": Data("[]".utf8)])
            defaults.set("private", forKey: "unrelated-secret")
            let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let values = try PropertyListSerialization.propertyList(from: bytes("Preferences.plist", in: backup.files), format: nil) as? [String: Any]
            XCTAssertEqual(values?.count, 0)
            XCTAssertEqual(backup.storeCount, 0)
            let report = try JSONSerialization.jsonObject(with: bytes("NativePreflight.json", in: backup.files)) as? [String: Any]
            XCTAssertEqual(report?["portable_conversion_complete"] as? Bool, false)
            XCTAssertEqual(defaults.string(forKey: "unrelated-secret"), "private")
        }
    }


    /// @fcn LegacyWorkspaceExportTests.testCorruptBytesAndRecoveryArePreserved
    /// @brief Preserve undecodable data and report recovery without executing either store
    /// @return Void after exact source-byte and review-code comparisons
    /// @throws Fixture or serialization errors
    func testCorruptBytesAndRecoveryArePreserved() throws
    {

        try fixture { defaults, domain, root in
            let corrupt = Data([0, 255, 3])
            defaults.set(corrupt, forKey: "Plenact.Board.v1")
            defaults.set(Data("pending".utf8), forKey: "Plenact.DailyReviewTransaction.v1")
            let before = defaults.persistentDomain(forName: domain)!
            let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let values = try XCTUnwrap(try PropertyListSerialization.propertyList(from: bytes("Preferences.plist", in: backup.files), format: nil) as? [String: Any])
            XCTAssertEqual(values["Plenact.Board.v1"] as? Data, corrupt)
            XCTAssertTrue(backup.reviewCodes.contains("native_decode_failed: Plenact.Board.v1"))
            XCTAssertTrue(backup.reviewCodes.contains("pending_recovery_transaction: Plenact.DailyReviewTransaction.v1"))
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.persistentDomain(forName: domain)!))
        }
    }


    /// @fcn LegacyWorkspaceExportTests.testUnknownKeysAreNotSilentlyExported
    /// @brief Surface unknown app storage without guessing that its contents are safe
    /// @return Void after checking review status and source retention
    /// @throws Fixture or capture errors
    func testUnknownKeysAreNotSilentlyExported() throws
    {

        try fixture { defaults, domain, root in
            defaults.set("sensitive", forKey: "Plenact.Future.private")
            let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            XCTAssertEqual(backup.storeCount, 0)
            XCTAssertEqual(backup.reviewCodes, ["unclassified_preference: Plenact.Future.private"])
            XCTAssertEqual(defaults.string(forKey: "Plenact.Future.private"), "sensitive")
        }
    }


    /// @fcn LegacyWorkspaceExportTests.testEveryMediaAreaPreservesOriginals
    /// @brief Include unreferenced original files in all owned areas with exact source bytes
    /// @return Void after comparing each preserved file
    /// @throws Fixture, media I/O or capture errors
    func testEveryMediaAreaPreservesOriginals() throws
    {

        try fixture { defaults, domain, root in
            for area in LegacyWorkspaceExport.mediaRoots
            {
                let folder = root.appendingPathComponent(area)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data([0, 1, 255]).write(to: folder.appendingPathComponent("original.bin"))
            }
            let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            XCTAssertEqual(backup.mediaCount, 4)
            for area in LegacyWorkspaceExport.mediaRoots
            {
                XCTAssertEqual(try bytes(area + "/original.bin", in: backup.files), Data([0, 1, 255]))
            }
        }
    }


    /// @fcn LegacyWorkspaceExportTests.testSymlinkMediaRejectsWholeCapture
    /// @brief Reject even an internal symlink rather than exporting an incomplete successful backup
    /// @return Void after checking the original linked file remains untouched
    /// @throws Fixture or filesystem errors
    func testSymlinkMediaRejectsWholeCapture() throws
    {

        try fixture { defaults, domain, root in
            let folder = root.appendingPathComponent(LegacyWorkspaceExport.mediaRoots[0])
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let original = folder.appendingPathComponent("original.bin")
            try Data([7]).write(to: original)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("alias.bin"), withDestinationURL: original)
            XCTAssertThrowsError(try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))
            XCTAssertEqual(try Data(contentsOf: original), Data([7]))
        }
    }


    /// @fcn LegacyWorkspaceExportTests.testNativeDecodersRejectFutureVersionAndWrongType
    /// @brief Distinguish valid source, unsupported documents and incorrectly stored native types
    /// @return Void after checking stable review codes
    /// @throws Native fixture encoding errors
    func testNativeDecodersRejectFutureVersionAndWrongType() throws
    {

        XCTAssertNil(LegacyStoreValidation.check(key: "Plenact.Board.v1", value: Data("[]".utf8)))
        XCTAssertEqual(LegacyStoreValidation.check(key: "Plenact.DailyPlans.v1", value: Data("{\"version\":2,\"plans\":{}}".utf8)), "unsupported_store_version")
        XCTAssertEqual(LegacyStoreValidation.check(key: "Plenact.CardCovers.enabled", value: NSNumber(value: 1)), "wrong_storage_type")
        XCTAssertNil(LegacyStoreValidation.check(key: "Plenact.CardCovers.enabled", value: true))
    }


    /// @fcn LegacyWorkspaceExportTests.testMissingAndUnsafeMediaReferencesRequireReview
    /// @brief Never represent a missing original as an empty asset or accept a path as a filename
    /// @return Void after checking reference diagnostics
    func testMissingAndUnsafeMediaReferencesRequireReview()
    {

        XCTAssertEqual(LegacyStoreValidation.mediaIssues(["fileName": "missing.bin"], store: "test", files: []), ["missing_media: test"])
        XCTAssertEqual(LegacyStoreValidation.mediaIssues(["photoFileName": "../private"], store: "test", files: []), ["unsafe_media_reference: test"])
        XCTAssertTrue(LegacyStoreValidation.mediaIssues(["fileName": "ok.bin"], store: "test", files: ["Documents/CardAttachments/ok.bin"]).isEmpty)
    }
}
