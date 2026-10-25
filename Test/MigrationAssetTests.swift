// --------------------------------------------------------------------------------------------------
// @file       MigrationAssetTests.swift
// @brief      Synthetic media preservation, linkage and integrity acceptance tests
// @details    Supported User Data Model versions: 1.0. Isolated preferences and temporary media only;
//             no real workspace, cloud account or Simulator source restore is modified.
// --------------------------------------------------------------------------------------------------
import XCTest
import UIKit
import PencilKit
@testable import Plenact


/// Verifies exact original-file evidence and source-derived metadata without account fabrication.
/// @section Purpose
///     Exercise media absent from the owner's current zero-media backup before hands-on testing.
@MainActor
final class MigrationAssetTests: XCTestCase
{

    /// @fcn MigrationAssetTests.fixture
    /// @brief Capture isolated photo, drawing, audio/video hints and four owned media areas
    /// @param[in] missing Whether to include a deliberately absent referenced photo
    /// @param[in] cycle Whether to deliberately create a cyclic drawing derivation
    /// @param[in] body Assertions receiving frozen source and an isolated journal path
    /// @return Void after removing only test-owned preferences and files
    /// @throws Synthetic capture or assertion-support errors
    private func fixture(missing: Bool = false, cycle: Bool = false, _ body: (LegacyWorkspaceBackup, URL) throws -> Void) throws
    {

        let domain = "Plenact.AssetTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer
        {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let png = renderer.pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let originals: [String: Data] = [
            "Documents/CardAttachments/photo.png": png,
            "Documents/CardAttachments/sketch.png": png,
            "Documents/CardAttachments/sketch.drawing": PKDrawing().dataRepresentation(),
            "Documents/CardAttachments/clip.m4a": Data([0, 0, 0, 16] + Array("ftypM4A ".utf8) + [0, 0, 0, 0]),
            "Documents/CardAttachments/movie.mov": Data([0, 0, 0, 16] + Array("ftypqt  ".utf8) + [0, 0, 0, 0]),
            "Documents/CardAttachments/empty.bin": Data(),
            "Documents/ProfileAvatars/photo.png": png,
            "Library/Application Support/PlenactStudioArtwork/photo.png": png,
            "Library/Application Support/PlenactCollectionBackgrounds/photo.png": png
        ]
        for (path, bytes) in originals
        {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: file)
        }
        var drawing = KanbanAttachment(fileName: "sketch.png", mediaKind: .photo)
        drawing.drawingFileName = "sketch.drawing"
        var attachments = [KanbanAttachment(fileName: "photo.png", mediaKind: .photo), drawing,
            KanbanAttachment(fileName: "clip.m4a", mediaKind: .audio),
            KanbanAttachment(fileName: "movie.mov", mediaKind: .video)]
        if cycle
        {
            var reverse = KanbanAttachment(fileName: "sketch.drawing", mediaKind: .photo)
            reverse.drawingFileName = "sketch.png"
            attachments.append(reverse)
        }
        if missing
        {
            attachments.append(KanbanAttachment(fileName: "absent.jpg", mediaKind: .photo))
        }
        let card = KanbanCard(id: 1, word: "Media fixture", listTitle: "Day", checklists: [],
            attachments: attachments, coverAttachmentID: drawing.id)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        let week = DatedPlanningWeek.make(for: Date(timeIntervalSince1970: 1792843200),
            lists: [KanbanList(id: 1, title: "Day", cards: [card])], calendar: calendar)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week])
        defaults.set(try JSONEncoder().encode(document), forKey: "Plenact.CalendarWeeks.v1")
        defaults.set(try JSONEncoder().encode(week.collection.lists), forKey: "Plenact.Board.v1")
        let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
        try body(backup, root.appendingPathComponent("Journal/ids.json"))
    }


    /// @fcn MigrationAssetTests.assetDocument
    /// @brief Read the actual emitted local Asset artifact
    /// @param[in] preview Prepared partial migration output
    /// @return Parsed account-unbound evidence document
    /// @throws Missing or invalid output errors
    private func assetDocument(_ preview: MigrationPreview) throws -> [String: Any]
    {

        try XCTUnwrap(JSONSerialization.jsonObject(with:
            MigrationBackupReader.file("MigrationPreview/AssetPreview.json", in: preview.files)) as? [String: Any])
    }


    /// @fcn MigrationAssetTests.testOriginalsLinksDrawingAndStableRetry
    /// @brief Verify every original, same-name isolation, drawing derivation and stable media identities
    /// @return Void after exact-byte/hash/link and account-boundary assertions
    /// @throws Fixture, conversion or assertion-support errors
    func testOriginalsLinksDrawingAndStableRetry() throws
    {

        try fixture { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            XCTAssertNil(preview.blockedContentReason)
            XCTAssertEqual(preview.verifiedAssetCount, 9)
            XCTAssertEqual(preview.missingAssetCount, 0)
            XCTAssertEqual(preview.assetIssueCount, 0)
            let document = try assetDocument(preview)
            XCTAssertEqual(document["account_binding_pending"] as? Bool, true)
            let entries = try XCTUnwrap(document["entries"] as? [[String: Any]])
            XCTAssertFalse(entries.contains { $0["account_id"] != nil })
            let byPath = Dictionary(uniqueKeysWithValues: try entries.map { (try XCTUnwrap($0["source_path"] as? String), $0) })
            for (path, entry) in byPath
            {
                let original = try MigrationBackupReader.file(path, in: backup.files)
                XCTAssertEqual(entry["sha256"] as? String, MigrationBackupReader.digest(original))
                XCTAssertEqual(entry["byte_length"] as? String, String(original.count))
                XCTAssertEqual(original, try MigrationBackupReader.file(path, in: preview.files))
            }
            let drawing = try XCTUnwrap(byPath["Documents/CardAttachments/sketch.drawing"])
            let rendered = try XCTUnwrap(byPath["Documents/CardAttachments/sketch.png"])
            XCTAssertEqual(drawing["kind"] as? String, "drawing_original")
            XCTAssertEqual(rendered["derived_from_asset_id"] as? String, drawing["asset_id"] as? String)
            XCTAssertEqual(Set(entries.filter { $0["original_name"] as? String == "photo.png" }
                .compactMap { $0["asset_id"] as? String }).count, 4)
            XCTAssertEqual(entries.filter { ($0["references"] as? [Any])?.isEmpty == true }.count, 4)
            let second = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: document, options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: assetDocument(second), options: .sortedKeys))
            var originals: [String: String] = [:]
            for path in byPath.keys
            {
                originals[path] = try MigrationBackupReader.file(path, in: backup.files).base64EncodedString()
            }
            let originalAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals, options: .sortedKeys), uniformTypeIdentifier: "public.json")
            originalAttachment.name = "Media-Originals.json"
            originalAttachment.lifetime = .keepAlways
            add(originalAttachment)
            for name in ["AssetPreview.json", "ContentGraph.json"]
            {
                let attachment = XCTAttachment(data: try MigrationBackupReader.file("MigrationPreview/" + name, in: preview.files), uniformTypeIdentifier: "public.json")
                attachment.name = "Media-" + name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let files = try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"]?.fileWrappers)
            let records = try files.sorted { $0.key < $1.key }.map { try JSONSerialization.jsonObject(with: XCTUnwrap($0.value.regularFileContents)) }
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: records, options: .sortedKeys), uniformTypeIdentifier: "public.json")
            attachment.name = "Media-Records.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }


    /// @fcn MigrationAssetTests.testMissingOriginalStaysExplicitAndDoesNotBlockOtherFiles
    /// @brief Retain absent attachment targets without fake hashes or loss of valid originals
    /// @return Void after unavailable-state and review-count assertions
    /// @throws Fixture, conversion or assertion-support errors
    func testMissingOriginalStaysExplicitAndDoesNotBlockOtherFiles() throws
    {

        try fixture(missing: true) { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            XCTAssertNil(preview.blockedContentReason)
            XCTAssertEqual(preview.verifiedAssetCount, 9)
            XCTAssertEqual(preview.missingAssetCount, 1)
            XCTAssertEqual(preview.assetIssueCount, 1)
            let entries = try XCTUnwrap(assetDocument(preview)["entries"] as? [[String: Any]])
            let missing = try XCTUnwrap(entries.first { $0["original_name"] as? String == "absent.jpg" })
            XCTAssertEqual(missing["content_state"] as? String, "unavailable")
            XCTAssertTrue(missing["sha256"] is NSNull)
            XCTAssertTrue(missing["byte_length"] is NSNull)
        }
    }


    /// @fcn MigrationAssetTests.testTamperedAndUndeclaredMediaRejectBeforeJournalWrite
    /// @brief Refuse changed bytes, undeclared files and symbolic links in frozen evidence
    /// @return Void after safe failure and unchanged journal assertions
    /// @throws Fixture or assertion-support errors
    func testTamperedAndUndeclaredMediaRejectBeforeJournalWrite() throws
    {

        for variant in 0..<3
        {
            try fixture { backup, url in
                let documents = try XCTUnwrap(backup.files.fileWrappers?["Documents"])
                let media = try XCTUnwrap(documents.fileWrappers?["CardAttachments"])
                if variant == 0
                {
                    let old = try XCTUnwrap(media.fileWrappers?["photo.png"])
                    media.removeFileWrapper(old)
                    let file = FileWrapper(regularFileWithContents: Data([1, 2, 3]))
                    file.preferredFilename = "photo.png"
                    media.addFileWrapper(file)
                }
                else
                {
                    let file = variant == 1 ? FileWrapper(regularFileWithContents: Data([9])) :
                        FileWrapper(symbolicLinkWithDestinationURL: URL(fileURLWithPath: "/private/tmp/unrelated"))
                    file.preferredFilename = "undeclared.bin"
                    media.addFileWrapper(file)
                }
                XCTAssertThrowsError(try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago"))
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    /// @fcn MigrationAssetTests.testDrawingCyclesRemainExplicitReviewItems
    /// @brief Preserve original bytes while refusing contradictory drawing dependency claims
    /// @return Void after checking removed cyclic edges and visible review issues
    /// @throws Fixture, conversion or assertion-support errors
    func testDrawingCyclesRemainExplicitReviewItems() throws
    {

        try fixture(cycle: true) { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            XCTAssertNil(preview.blockedContentReason)
            XCTAssertEqual(preview.verifiedAssetCount, 9)
            XCTAssertGreaterThanOrEqual(preview.assetIssueCount, 2)
            let document = try assetDocument(preview)
            let issues = try XCTUnwrap(document["issues"] as? [String])
            XCTAssertTrue(issues.contains { $0.hasPrefix("asset_derivation_cycle:") })
            let entries = try XCTUnwrap(document["entries"] as? [[String: Any]])
            for entry in entries where ["sketch.png", "sketch.drawing"].contains(entry["original_name"] as? String ?? "")
            {
                XCTAssertTrue(entry["derived_from_asset_id"] is NSNull)
            }
        }
    }

}
