// --------------------------------------------------------------------------------------------------
// @file       MigrationContentTests.swift
// @brief      Synthetic canonical content conversion, ownership and date regression coverage
// @details    Supported User Data Model versions: 1.0; private journal formats 1/2.
//             No personal backup is read or imported. Native JSON output is attached for independent checks.
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import Foundation
import XCTest
import SwiftUI


/// Exercises real native content models and frozen backups without fallback/example loaders.
/// @section Purpose
///     Prove explicit content mapping, repeatable IDs, rejection boundaries and source preservation.
@MainActor
final class MigrationContentTests: XCTestCase
{

    /// @fcn MigrationContentTests.fixture
    /// @brief Build a frozen synthetic Week and run assertions in an isolated preferences/container scope
    /// @param[in] edit Optional raw source transformation for malformed/legacy cases
    /// @param[in] body Assertions receiving the backup and private journal location
    /// @return Void after private test cleanup
    /// @throws Source setup/capture/assertion-support errors
    private func fixture(edit: ((inout [String: Any]) throws -> Void)? = nil,
        _ body: (LegacyWorkspaceBackup, URL) throws -> Void) throws
    {

        let domain   = "Plenact.ContentMigrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root     = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer
        {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }

        let instant = Date(timeIntervalSince1970: 1792843200.123456)
        let detail  = KanbanChecklistActionDetail(description: "Exact nested writing", checklists: [
            KanbanChecklist(title: "Nested", items: [KanbanChecklistItem(title: "Nested action", isCompleted: true)])])
        var dormant = KanbanChecklistItem(title: "Inactive retained detail")

        dormant.retainedDetail = KanbanChecklistActionDetail(description: "Keep this even while inactive")
        dormant.retainedCardID = 999
        dormant.retainedURL = URL(string: "https://example.com/retained")

        let items = [KanbanChecklistItem(title: "Done", isCompleted: true),
            KanbanChecklistItem(title: "Link", content: .linkedCard(cardID: 2)),
            KanbanChecklistItem(title: "Detail", content: .actionDetail(detail)),
            KanbanChecklistItem(title: "Web", content: .webLink(URL(string: "https://example.com/action")!)), dormant]
        var attachment = KanbanAttachment(fileName: "original.bin", mediaKind: .photo, addedAt: instant, caption: "")

        attachment.drawingFileName = "drawing.bin"

        var appearance = ItemAppearance()

        appearance.subtitleItalic = false
        appearance.listBackgroundOpacity = 0.4

        let history = CardEditRecord(id: UUID(), timestamp: instant,
            changes: [CardEditChange(field: "word", previousValue: Data([0, 255, 7]), newValue: Data())])
        let card = KanbanCard(id: 1, word: "  Exact Card 🪴  ", listTitle: "Monday", isTitleChecked: true,
            startDate: instant, dueDate: instant.addingTimeInterval(3600),
            checklists: [KanbanChecklist(title: "Actions", items: items)],
            comments: [KanbanComment(author: "Legacy author", body: "Retain discussion", createdAt: instant)],
            members: [CardAssignee(kind: .manual, displayName: "Manual name"),
                CardAssignee(kind: .registeredUser, userID: UUID().uuidString, displayName: "Legacy directory")],
            labelIDs: ["saved-label", "unresolved-label"], attachments: [attachment], coverAttachmentID: attachment.id,
            dismissedActivityIDs: ["event-B", "event-A"], descriptionOverride: "", subtitleOverride: "",
            createdAt: instant, appearance: appearance, sectionLayout: CardSectionLayout(order: [.details, .checklists], hidden: [.media]),
            startDateKind: .dateAndTime, dueDateKind: .dateAndTime,
            reactions: [ItemEmojiReaction(emoji: "🌱", authorID: UUID())], showsReactionsInPreviews: false,
            isEditingLocked: true, editHistory: [history], location: "Oshkosh")
        let second   = KanbanCard(id: 2, word: "Linked Note", listTitle: "Monday", checklists: [], presentation: .note)
        let archived = KanbanCard(id: 3, word: "Archived", listTitle: "Monday", checklists: [])
        var list     = KanbanList(id: 1, title: "Monday", cards: [card, second])

        list.archivedCards = [archived]

        var calendar = Calendar(identifier: .gregorian)

        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2

        let week     = DatedPlanningWeek.make(for: instant, lists: [list], calendar: calendar)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week])
        var personal = PersonalCollection(title: "Personal", kind: .board)

        personal.lists = [list]

        let library               = PlanningRoutineLibrary.seeded
        var values: [String: Any] = ["Plenact.Board.v1": try JSONEncoder().encode(week.collection.lists),
            "Plenact.CalendarWeeks.v1": try JSONEncoder().encode(document),
            "Plenact.PersonalCollections.v1": try JSONEncoder().encode([personal]),
            "Plenact.PlanningTemplates.v1": try JSONEncoder().encode(library),
            "Plenact.LabelLibrary.v1": try JSONSerialization.data(withJSONObject: [
                "categories": [["id": "category", "name": "Saved"]],
                "labels": [["id": "saved-label", "name": "Real label", "categoryID": "category", "color": "green"]]])]

        try edit?(&values)
        defaults.setPersistentDomain(values, forName: domain)

        let media = root.appendingPathComponent("Documents/CardAttachments")

        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data([0, 255]).write(to: media.appendingPathComponent("original.bin"))
        try Data([7, 9]).write(to: media.appendingPathComponent("drawing.bin"))

        let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)

        try body(backup, root.appendingPathComponent("Journal/ids.json"))
    }


    /// @fcn MigrationContentTests.documents
    /// @brief Decode the actual emitted record files for assertions/independent attachments
    /// @param[in] preview Prepared output
    /// @return Complete canonical record array
    /// @throws Missing or invalid JSON files
    private func documents(_ preview: MigrationPreview) throws -> [[String: Any]]
    {

        let root = try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"])

        return try (root.fileWrappers ?? [:]).sorted { $0.key < $1.key }.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.value.regularFileContents)) as? [String: Any])
        }
    }


    /// @fcn MigrationContentTests.testCompleteContentSlicePreservesOriginalsAndRetries
    /// @brief Convert complex live/template content, preserve source bytes and attach actual native output
    /// @return Void after exact writing, archive, ownership, media/history and retry comparisons
    /// @throws Fixture/conversion/assertion-support errors
    func testCompleteContentSlicePreservesOriginalsAndRetries() throws
    {

        try fixture { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            guard preview.blockedContentReason == nil else
            {
                XCTFail("Content blocked: " + preview.blockedContentReason!)
                return
            }
            XCTAssertGreaterThan(preview.contentRecordCount, 0)

            let records = try documents(preview)
            let cards   = records.filter { $0["record_type"] as? String == "card" }
            let exact   = cards.filter { ($0["payload"] as? [String: Any])?["title"] as? String == "  Exact Card 🪴  " }

            guard exact.count == 2 else
            {
                XCTFail("Expected two independently owned source Cards; got " + String(exact.count))
                return
            }
            XCTAssertNotEqual(exact[0]["id"] as? String, exact[1]["id"] as? String)

            let payload = try XCTUnwrap(exact[0]["payload"] as? [String: Any])

            XCTAssertEqual(payload["completed"] as? Bool, true)
            XCTAssertEqual(payload["editing_locked"] as? Bool, true)
            XCTAssertEqual(payload["description_override"] as? String, "")
            XCTAssertEqual((payload["start"] as? [String: Any])?["tzdb_version"] as? String, "2025b")
            XCTAssertEqual((payload["start"] as? [String: Any])?["utc_offset"] as? String, "-05:00")

            let history     = try XCTUnwrap(payload["edit_history"] as? [[String: Any]])
            let changes     = try XCTUnwrap(XCTUnwrap(history.first)["changes"] as? [[String: Any]])
            let firstChange = try XCTUnwrap(changes.first)

            XCTAssertEqual((firstChange["previous_value"] as? [String: Any])?["data"] as? String, Data([0, 255, 7]).base64EncodedString())
            XCTAssertEqual((firstChange["new_value"] as? [String: Any])?["data"] as? String, "")
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: preview.files),
                try MigrationBackupReader.file("Preferences.plist", in: backup.files))

            let again = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertEqual(try JSONSerialization.data(withJSONObject: records, options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: documents(again), options: .sortedKeys))
            XCTAssertFalse(preview.remainingStores.contains("Plenact.Board.v1"))
            XCTAssertTrue(preview.remainingStores.contains("Plenact.CalendarWeeks.v1"))

            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys, .prettyPrinted]), uniformTypeIdentifier: "public.json")

            attachment.name = "native-content-records.json"
            attachment.lifetime = .keepAlways

            add(attachment)

            let graph = XCTAttachment(data: try MigrationBackupReader.file("MigrationPreview/ContentGraph.json", in: preview.files), uniformTypeIdentifier: "public.json")

            graph.name = "native-content-graph.json"
            graph.lifetime = .keepAlways

            add(graph)
        }
    }


    /// @fcn MigrationContentTests.testTimezoneConfirmationIsRequiredForContent
    /// @brief Preserve metadata preview while explicitly blocking unconfirmed content dates
    /// @return Void after blocker and retained-source assertions
    /// @throws Fixture errors
    func testTimezoneConfirmationIsRequiredForContent() throws
    {

        try fixture { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url)

            XCTAssertEqual(preview.blockedContentReason, "original_timezone_confirmation_required")
            XCTAssertEqual(preview.contentRecordCount, 0)
        }
    }


    /// @fcn MigrationContentTests.testProjectionDivergenceBlocksContentAtomically
    /// @brief Do not choose one conflicting Board/Week snapshot or allocate partial content identities
    /// @return Void after explicit block
    /// @throws Fixture errors
    func testProjectionDivergenceBlocksContentAtomically() throws
    {

        try fixture(edit: { values in

            values["Plenact.Board.v1"] = Data("[]".utf8)

        }) { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertEqual(preview.blockedContentReason, "board_week_projection_conflict")
            XCTAssertEqual(preview.contentRecordCount, 0)

            let journal = try MigrationIdentityJournal.decode(XCTUnwrap(MigrationIdentityStore.read(at: url)))

            XCTAssertFalse(journal.entries.contains { $0.source.recordType == "card" })
        }
    }


    /// @fcn MigrationContentTests.testFutureStoredCardFieldCannotDisappearDuringDecoding
    /// @brief Reject unknown source fields before the compatible decoder can discard them
    /// @return Void after explicit unsupported-field report
    /// @throws Fixture errors
    func testFutureStoredCardFieldCannotDisappearDuringDecoding() throws
    {

        try fixture(edit: { values in

            var board = try JSONSerialization.jsonObject(with: values["Plenact.Board.v1"] as! Data) as! [[String: Any]]
            var cards = board[0]["cards"] as! [[String: Any]]

            cards[0]["future-content"] = "must survive"
            board[0]["cards"] = cards
            values["Plenact.Board.v1"] = try JSONSerialization.data(withJSONObject: board)

        }) { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertEqual(preview.blockedContentReason, "unsupported_source_fields:KanbanCard")
        }
    }


    /// @fcn MigrationContentTests.testMissingChecklistCannotSeedDefaultExampleContent
    /// @brief Block the native initializer's example-producing omission path
    /// @return Void after explicit source-missing diagnostic
    /// @throws Guard errors are expected
    func testMissingChecklistCannotSeedDefaultExampleContent() throws
    {

        XCTAssertThrowsError(try MigrationContentGuard.check(["id": 1, "word": "Legacy", "listTitle": "Monday"], type: "KanbanCard"))
        XCTAssertThrowsError(try MigrationContentGuard.check("Legacy name", type: "CardAssignee"))
    }


    /// @fcn MigrationContentTests.testPinnedDatesResolveFoldOccurrencesAndSpringTransition
    /// @brief Use pinned rules rather than whichever timezone data the device currently has installed
    /// @return Void after first/second-fold, gap boundary, date-only and time-only assertions
    /// @throws Date conversion errors
    func testPinnedDatesResolveFoldOccurrencesAndSpringTransition() throws
    {

        let context                 = MigrationContentValues(journal: MigrationIdentityJournal(), timeZoneID: "America/Chicago", mediaDigests: [:])
        let formatter               = ISO8601DateFormatter()
        var values: [[String: Any]] = []

        for (instant, occurrence) in [("2026-11-01T06:30:00Z", "first"), ("2026-11-01T07:30:00Z", "second"), ("2026-03-08T08:15:00Z", "unique")]
        {

            let value = try MigrationContentDates.convert(NSNumber(value: formatter.date(from: instant)!.timeIntervalSince1970), kind: "date_and_time", context: context, path: instant) as! [String: Any]

            XCTAssertEqual(value["occurrence"] as? String, occurrence)
            values.append(value)
        }

        let sample = NSNumber(value: formatter.date(from: "2026-10-24T05:30:00Z")!.timeIntervalSince1970)

        XCTAssertEqual((try MigrationContentDates.convert(sample, kind: "date", context: context, path: "date") as? [String: Any])?["date"] as? String, "2026-10-24")
        XCTAssertEqual((try MigrationContentDates.convert(sample, kind: "time", context: context, path: "time") as? [String: Any])?["time"] as? String, "00:30:00.000")

        context.timeZoneID = "unsupported/zone"

        XCTAssertThrowsError(try MigrationContentDates.convert(sample, kind: "date_and_time", context: context, path: "unsupported"))

        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted]), uniformTypeIdentifier: "public.json")

        attachment.name = "native-content-date-cases.json"
        attachment.lifetime = .keepAlways

        add(attachment)
    }


    /// @fcn MigrationContentTests.testJournalV1MappingsSurviveNestedIdentityUpgrade
    /// @brief Retain existing UUIDs while introducing the private v2 nested-kind registry
    /// @return Void after upgrade/reopen checks
    /// @throws Journal errors
    func testJournalV1MappingsSurviveNestedIdentityUpgrade() throws
    {

        var original = MigrationIdentityJournal()
        let source   = MigrationSourceIdentity(recordType: "label", owner: "workspace_metadata", legacyID: "same", discriminator: nil)
        let target   = try original.resolve(source)
        var object   = try JSONSerialization.jsonObject(with: original.encoded()) as! [String: Any]

        object["formatVersion"] = 1

        var upgraded = try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: object))

        _ = try upgraded.resolve(MigrationSourceIdentity(recordType: "nested_checklist", owner: "card", legacyID: UUID().uuidString, discriminator: nil))

        XCTAssertEqual(upgraded.formatVersion, 2)
        XCTAssertEqual(try upgraded.resolve(source), target)
        XCTAssertEqual(try MigrationIdentityJournal.decode(upgraded.encoded()).sourceInstallationID, original.sourceInstallationID)
    }

    /// @fcn MigrationContentTests.testEmptySourceReactionsAndAppearanceRemainDistinctFromNull
    /// @brief Preserve original optional values that compatible native constructors normalize away
    /// @return Void after exact empty/null distinctions are observed in canonical output
    /// @throws Fixture/conversion errors
    func testEmptySourceReactionsAndAppearanceRemainDistinctFromNull() throws
    {

        try fixture(edit: { values in

            var board = try JSONSerialization.jsonObject(with: values["Plenact.Board.v1"] as! Data) as! [[String: Any]]
            var cards = board[0]["cards"] as! [[String: Any]]

            cards[0]["reactions"] = [Any]()
            cards[0]["appearance"] = [String: Any]()
            board[0]["cards"] = cards
            values["Plenact.Board.v1"] = try JSONSerialization.data(withJSONObject: board)

            var calendar   = try JSONSerialization.jsonObject(with: values["Plenact.CalendarWeeks.v1"] as! Data) as! [String: Any]
            var weeks      = calendar["weeks"] as! [[String: Any]]
            var collection = weeks[0]["collection"] as! [String: Any]

            collection["lists"] = board
            weeks[0]["collection"] = collection
            calendar["weeks"] = weeks
            values["Plenact.CalendarWeeks.v1"] = try JSONSerialization.data(withJSONObject: calendar)

        }) { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertNil(preview.blockedContentReason)

            let record = try XCTUnwrap(documents(preview).first {
                ($0["payload"] as? [String: Any])?["title"] as? String == "  Exact Card 🪴  "
            })
            let payload = try XCTUnwrap(record["payload"] as? [String: Any])

            XCTAssertEqual((payload["reactions"] as? [Any])?.count, 0)
            XCTAssertNotNil(payload["appearance"] as? [String: Any])
        }
    }


    /// @fcn MigrationContentTests.testRichTextIsRetainedOrBlockedWithoutFlattening
    /// @brief Accept known rich runs, retain malformed prefixes literally, and reject future attributes
    /// @return Void after compatibility boundary assertions
    /// @throws Fixture encoding errors
    func testRichTextIsRetainedOrBlockedWithoutFlattening() throws
    {

        let runs: [[String: Any]] = [["text": "Exact rich writing", "bold": true, "italic": false, "fontSize": 17]]
        let valid                 = "plenact-rich-v1:" + (try JSONSerialization.data(withJSONObject: runs)).base64EncodedString()

        XCTAssertNoThrow(try MigrationContentGuard.richText(valid))
        XCTAssertNoThrow(try MigrationContentGuard.richText("plenact-rich-v1:not-base64"))

        var future = runs

        future[0]["unsupported-decoration"] = true

        let unsupported = "plenact-rich-v1:" + (try JSONSerialization.data(withJSONObject: future)).base64EncodedString()

        XCTAssertThrowsError(try MigrationContentGuard.richText(unsupported))
        XCTAssertThrowsError(try MigrationContentGuard.check([
            "red": -0.1, "green": 0.5, "blue": 0.4], type: "ProfileColor"))
    }


    /// @fcn MigrationContentTests.testDuplicateSourceCardCannotBeSilentlyMerged
    /// @brief Keep the entire content slice blocked when a current owner has ambiguous Card identity
    /// @return Void after explicit source identity failure
    /// @throws Fixture errors
    func testDuplicateSourceCardCannotBeSilentlyMerged() throws
    {

        try fixture(edit: { values in

            var personal = try JSONSerialization.jsonObject(with: values["Plenact.PersonalCollections.v1"] as! Data) as! [[String: Any]]
            var lists    = personal[0]["lists"] as! [[String: Any]]
            let cards    = lists[0]["cards"] as! [[String: Any]]

            lists[0]["cards"] = cards + [cards[0]]
            personal[0]["lists"] = lists
            values["Plenact.PersonalCollections.v1"] = try JSONSerialization.data(withJSONObject: personal)

        }) { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertEqual(preview.blockedContentReason, "content_validation:duplicate_card_identity")
            XCTAssertEqual(preview.contentRecordCount, 0)
        }
    }


    /// @fcn MigrationContentTests.testDefaultLabelEvidenceResolvesOnlyKnownLabels
    /// @brief Resolve absent-catalog built-ins without manufacturing unknown user definitions
    /// @return Void after checking provenance, stable IDs and untouched original bytes
    /// @throws Fixture, conversion or assertion-support errors
    func testDefaultLabelEvidenceResolvesOnlyKnownLabels() throws
    {

        try fixture(edit: { values in
            values.removeValue(forKey: "Plenact.LabelLibrary.v1")

            var calendar = try JSONDecoder().decode(PlanningCalendarDocument.self,
                from: XCTUnwrap(values["Plenact.CalendarWeeks.v1"] as? Data))
            let index = try XCTUnwrap(calendar.weeks.firstIndex { $0.startKey == calendar.currentWeekKey })

            calendar.weeks[index].collection.savedCardIDs = [1]
            values["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(calendar)
            values["Plenact.SavedCardIDs.v1"] = [1]
            values["Plenact.LibraryImportant.v1"] = try JSONEncoder().encode([
                LibraryImportanceItem(collectionID: calendar.weeks[index].collection.id, cardID: 1, level: 3)])

        }) { backup, url in

            let first = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertNil(first.blockedContentReason)

            let records = try documents(first)

            XCTAssertEqual(first.selectionEntryCount, 1)
            XCTAssertEqual(first.selectionIssueCount, 0)

            let selectionData = try MigrationBackupReader.file("MigrationPreview/SelectionPreview.json", in: first.files)
            let selection     = try XCTUnwrap(JSONSerialization.jsonObject(with: selectionData) as? [String: Any])
            let entries       = try XCTUnwrap(selection["entries"] as? [[String: Any]])

            XCTAssertEqual(try XCTUnwrap(entries.first)["importance"] as? Int, 3)
            XCTAssertEqual(try XCTUnwrap(entries.first)["bookmarked"] as? Bool, true)

            let recordAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: records, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            recordAttachment.name = "LabelsAndSelectionsRecords.json"
            recordAttachment.lifetime = .keepAlways

            add(recordAttachment)

            let selectionAttachment = XCTAttachment(data: selectionData, uniformTypeIdentifier: "public.json")

            selectionAttachment.name = "SelectionPreview.json"
            selectionAttachment.lifetime = .keepAlways

            add(selectionAttachment)

            let catalog = try MigrationBackupReader.file("MigrationPreview/ApplicationDefaultLabels.json", in: first.files)
            let labels  = try JSONDecoder().decode(LabelLibrary.self, from: catalog)

            XCTAssertTrue(labels.labels.contains { $0.id == "day-health" })
            XCTAssertTrue(records.contains { $0["record_type"] as? String == "label" })

            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: MigrationBackupReader.file("MigrationPreview/Report.json", in: first.files)) as? [String: Any])

            XCTAssertEqual(report["label_catalog_origin"] as? String, "application_default_catalog")
            XCTAssertTrue(records.contains { ($0["payload"] as? [String: Any])?["target_type"] as? String == "label" })

            let second = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertEqual(try JSONSerialization.data(withJSONObject: records, options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: documents(second), options: .sortedKeys))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: backup.files),
                try MigrationBackupReader.file("Preferences.plist", in: first.files))
        }
    }


    /// @fcn MigrationContentTests.testSelectionsRetainOwnerScopeAndImportance
    /// @brief Merge bookmark and importance only for an exact original owner/Card pair
    /// @return Void after checking legacy one-star defaults, orphan evidence and projection conflicts
    /// @throws Native synthetic encoding errors
    func testSelectionsRetainOwnerScopeAndImportance() throws
    {

        var owner = PersonalCollection(title: "Owner", kind: .board)

        owner.lists = [KanbanList(id: 1, title: "List", cards: [KanbanCard(id: 1, word: "Card", listTitle: "List", checklists: [])])]
        owner.savedCardIDs = [1, 9]

        let other      = PersonalCollection(title: "Other", kind: .board)
        let scope      = owner.id.uuidString.lowercased()
        let target     = UUID().uuidString.lowercased()
        let importance = [LibraryImportanceItem(collectionID: owner.id, cardID: 1),
            LibraryImportanceItem(collectionID: other.id, cardID: 1, level: 5)]
        let values: [String: Any] = ["Plenact.LibraryImportant.v1": try JSONEncoder().encode(importance),
            "Plenact.SavedCardIDs.v1": [1, 9]]
        let result = MigrationSelectionPreview.prepare(values: values, owners: [(scope, owner)], currentScope: scope,
            targets: [scope + ":1": target])
        let resolved = try XCTUnwrap(result.entries.first { $0["card_id"] as? String == target })

        XCTAssertEqual(resolved["bookmarked"] as? Bool, true)
        XCTAssertEqual(resolved["importance"] as? Int, 1)
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertEqual(result.issues.count, 2)
        XCTAssertFalse(result.entries.contains { $0["account_id"] != nil })

        let conflict = MigrationSelectionPreview.prepare(values: ["Plenact.SavedCardIDs.v1": [1]],
            owners: [(scope, owner)], currentScope: scope, targets: [scope + ":1": target])

        XCTAssertTrue(conflict.issues.contains("board_bookmark_projection_requires_review"))
    }


    /// @fcn MigrationContentTests.testInvalidAndAmbiguousImportanceNeverBecomesZero
    /// @brief Preserve uncertainty when source levels or copied owner identities need review
    /// @return Void after confirming no clamping, cross-owner application or fabricated account
    /// @throws Native synthetic encoding and assertion-support errors
    func testInvalidAndAmbiguousImportanceNeverBecomesZero() throws
    {

        var owner = PersonalCollection(title: "Owner", kind: .board)

        owner.savedCardIDs = [1]

        let scope   = owner.id.uuidString.lowercased()
        let target  = UUID().uuidString.lowercased()
        let invalid = try JSONEncoder().encode([LibraryImportanceItem(collectionID: owner.id, cardID: 1, level: 6)])
        let result  = MigrationSelectionPreview.prepare(values: ["Plenact.LibraryImportant.v1": invalid],
            owners: [(scope, owner)], currentScope: scope, targets: [scope + ":1": target])

        XCTAssertTrue(result.issues.contains("importance_source_requires_review"))
        XCTAssertTrue(try XCTUnwrap(result.entries.first)["importance"] is NSNull)

        let valid     = try JSONEncoder().encode([LibraryImportanceItem(collectionID: owner.id, cardID: 1, level: 4)])
        let ambiguous = MigrationSelectionPreview.prepare(values: ["Plenact.LibraryImportant.v1": valid],
            owners: [("template:A", owner), ("template:B", owner)], currentScope: nil,
            targets: ["template:A:1": target, "template:B:1": UUID().uuidString.lowercased()])

        XCTAssertEqual(ambiguous.entries.count, 3)
        XCTAssertEqual(ambiguous.entries.filter { $0["importance"] is NSNull }.count, 2)
    }


    /// @fcn MigrationContentTests.testCalendarAndTemplateMetadataPreservesMappings
    /// @brief Preserve current Week context, ordered templates and independent copied owners
    /// @return Void after exact metadata, timezone, default and retry checks
    /// @throws Fixture, conversion or assertion-support errors
    func testCalendarAndTemplateMetadataPreservesMappings() throws
    {

        try fixture { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertNil(preview.blockedContentReason)
            XCTAssertEqual(preview.metadataRecordCount, 9)

            let records     = try documents(preview)
            let week        = try XCTUnwrap(records.first { $0["record_type"] as? String == "calendar_week" })
            let weekPayload = try XCTUnwrap(week["payload"] as? [String: Any])

            XCTAssertEqual(weekPayload["time_zone"] as? String, "America/Chicago")
            XCTAssertEqual(weekPayload["time_zone_source"] as? String, "user_confirmed")
            XCTAssertEqual((weekPayload["day_lists"] as? [Any])?.count, 7)

            let library = try XCTUnwrap(records.first { $0["record_type"] as? String == "template_library" })
            let payload = try XCTUnwrap(library["payload"] as? [String: Any])
            let ids     = try XCTUnwrap(payload["template_ids"] as? [String])

            XCTAssertEqual(ids.count, 6)

            let templates = records.filter { $0["record_type"] as? String == "planning_template" }

            XCTAssertEqual(Set(templates.compactMap { ($0["payload"] as? [String: Any])?["collection_id"] as? String }).count, 6)

            let selected = try XCTUnwrap(templates.first { $0["id"] as? String == payload["default_week_id"] as? String })

            XCTAssertEqual((selected["payload"] as? [String: Any])?["name"] as? String, "Jmr")

            let second = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertEqual(try JSONSerialization.data(withJSONObject: records, options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: documents(second), options: .sortedKeys))
        }
    }


    /// @fcn MigrationContentTests.testInvalidCalendarMappingsBlockWithoutPartialMetadata
    /// @brief Reject normalized dates, repeated/outside day mappings and ambiguous global checklist links
    /// @return Void after confirming explicit blockers and preserved original preferences
    /// @throws Fixture, conversion or assertion-support errors
    func testInvalidCalendarMappingsBlockWithoutPartialMetadata() throws
    {

        for variant in 0..<5
        {
            try fixture(edit: { values in

                var document = try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(values["Plenact.CalendarWeeks.v1"] as? Data))
                let index = try XCTUnwrap(document.weeks.firstIndex { $0.startKey == document.currentWeekKey })
                let keys  = document.weeks[index].dayListIDs.keys.sorted()
                let first = try XCTUnwrap(keys.first)
                let list  = try XCTUnwrap(document.weeks[index].dayListIDs[first])

                if variant == 0
                {

                    document.weeks[index].dayListIDs["2026-02-30"] = list

                }
                else if variant == 1
                {

                    document.weeks[index].dayListIDs["2026-12-31"] = list

                }
                else if variant == 2
                {

                    document.weeks[index].dayListIDs[first] = -999

                }
                else if variant == 3
                {

                    let second = try XCTUnwrap(keys.dropFirst().first)

                    document.weeks[index].dayListIDs[second] = list

                }
                else
                {

                    document.checklistLinkWeeks = [UUID(): document.weeks[index].id]

                }

                values["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(document)

            }) { backup, url in

                let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

                XCTAssertNotNil(preview.blockedContentReason)
                XCTAssertEqual(preview.metadataRecordCount, 0)
                XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: backup.files),
                    try MigrationBackupReader.file("Preferences.plist", in: preview.files))
            }
        }
        XCTAssertThrowsError(try MigrationCalendarTemplates.date("2026-02-30"))
        XCTAssertThrowsError(try MigrationCalendarTemplates.date("2026-2-03"))
        XCTAssertNoThrow(try MigrationCalendarTemplates.date("2000-02-29"))
    }


    /// @fcn MigrationContentTests.testInvalidTemplateMetadataBlocksWithoutInventedDefaults
    /// @brief Reject invalid default kinds, weekday mappings, focus references and source revisions
    /// @return Void after confirming no metadata documents are partially emitted
    /// @throws Fixture or conversion errors
    func testInvalidTemplateMetadataBlocksWithoutInventedDefaults() throws
    {

        for variant in 0..<6
        {
            try fixture(edit: { values in

                var library = try JSONDecoder().decode(PlanningRoutineLibrary.self,
                    from: XCTUnwrap(values["Plenact.PlanningTemplates.v1"] as? Data))
                let index = try XCTUnwrap(library.templates.firstIndex { $0.kind == .day })

                if variant == 0
                {

                    library.defaultWeekID = library.templates[index].id

                }
                else if variant == 1
                {

                    library.templates[index].weekdays = [8: 1]

                }
                else if variant == 2
                {

                    library.templates[index].weekdays = [2: -999]

                }
                else if variant == 3
                {

                    library.templates[index].exampleFocus = PlanningExampleFocus(important: [-999])

                }
                else if variant == 4
                {

                    library.bundledRoutineRevision = -1

                }
                else
                {

                    library.templates[index].anchorKey = "2026-02-30"

                }

                values["Plenact.PlanningTemplates.v1"] = try JSONEncoder().encode(library)

            }) { backup, url in

                let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

                XCTAssertNotNil(preview.blockedContentReason)
                XCTAssertEqual(preview.metadataRecordCount, 0)
            }
        }
    }


    /// @fcn MigrationContentTests.testCrossWeekChecklistOverrideTargetsItsActualWeek
    /// @brief Respect the saved calendar override even when a matching numeric Card exists locally
    /// @return Void after checking both the nested link and calendar-index provenance
    /// @throws Fixture, conversion or assertion-support errors
    func testCrossWeekChecklistOverrideTargetsItsActualWeek() throws
    {

        try fixture(edit: { values in

            var source = try JSONDecoder().decode(PlanningCalendarDocument.self,
                from: XCTUnwrap(values["Plenact.CalendarWeeks.v1"] as? Data))
            let week = try XCTUnwrap(source.weeks.first)
            let card = try XCTUnwrap(week.collection.lists.flatMap(\.cards).first { $0.id == 1 })
            let item = try XCTUnwrap(card.checklists.flatMap(\.items).first {
                if case .linkedCard = $0.content
                {
                    return true
                }
                return false
            })
            var calendar = Calendar(identifier: .gregorian)

            calendar.timeZone = TimeZone(identifier: "America/Chicago")!
            calendar.firstWeekday = source.firstWeekday

            let target = KanbanCard(id: 2, word: "Other Week target", listTitle: "Other", checklists: [])
            let next   = DatedPlanningWeek.make(for: Date(timeIntervalSince1970: 1793448000),
                lists: [KanbanList(id: 77, title: "Other", cards: [target])], calendar: calendar)

            source.weeks.append(next)

            source.checklistLinkWeeks = [item.id: next.id]
            values["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(source)

        }) { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            guard preview.blockedContentReason == nil else
            {
                XCTFail("Cross-Week metadata blocked: " + (preview.blockedContentReason ?? ""))
                return
            }

            let records = try documents(preview)
            let target  = try XCTUnwrap(records.first { ($0["payload"] as? [String: Any])?["title"] as? String == "Other Week target" })
            let index   = try XCTUnwrap(records.first { $0["record_type"] as? String == "calendar_index" })
            let links   = try XCTUnwrap((index["payload"] as? [String: Any])?["checklist_link_weeks"] as? [[String: Any]])
            let itemID  = try XCTUnwrap(links.first?["checklist_item_id"] as? String)
            var matched = false

            for record in records where record["record_type"] as? String == "card"
            {

                let payload = try XCTUnwrap(record["payload"] as? [String: Any])

                for checklist in payload["checklists"] as? [[String: Any]] ?? []
                {
                    for item in checklist["items"] as? [[String: Any]] ?? [] where item["id"] as? String == itemID
                    {
                        XCTAssertEqual((item["content"] as? [String: Any])?["card_id"] as? String, target["id"] as? String)

                        matched = true

                    }
                }
            }
            XCTAssertTrue(matched)

            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: records, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            attachment.name = "CrossWeekMetadataRecords.json"
            attachment.lifetime = .keepAlways

            add(attachment)
        }
    }


    /// @fcn MigrationContentTests.testPortableContentReconstructsEditableModels
    /// @brief Reconstruct actual editor models directly from exported portable content with retained identities
    /// @return Void after nested content, dates, opaque history and stable alias assertions
    /// @throws Fixture, conversion or adapter errors
    func testPortableContentReconstructsEditableModels() throws
    {

        try fixture { backup, url in

            let preview       = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let records       = try documents(preview)
            let assetDocument = try XCTUnwrap(JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("MigrationPreview/AssetPreview.json", in: preview.files)) as? [String: Any])
            let entries = try XCTUnwrap(assetDocument["entries"] as? [[String: Any]])
            let files   = Dictionary(uniqueKeysWithValues: try entries.map { entry in
                (try XCTUnwrap(entry["asset_id"] as? String), try XCTUnwrap(entry["original_name"] as? String))
            })
            let adapter  = try PortableEditableContent(records: records, assetFiles: files)
            let reversed = try PortableEditableContent(records: Array(records.reversed()), assetFiles: files)

            XCTAssertEqual(adapter.numericIDs, reversed.numericIDs)

            var extra = try XCTUnwrap(records.first { $0["record_type"] as? String == "card" })

            extra["id"] = "00000000-0000-4000-8000-000000000001"

            let extended = try PortableEditableContent(records: records + [extra], assetFiles: files, retainedAliases: adapter.numericIDs)

            for (id, number) in adapter.numericIDs
            {
                XCTAssertEqual(extended.numericIDs[id], number)
            }

            let exactCard    = try XCTUnwrap(records.first { ($0["payload"] as? [String: Any])?["title"] as? String == "  Exact Card 🪴  " })
            let owningListID = try XCTUnwrap((exactCard["payload"] as? [String: Any])?["list_id"] as? String)
            let owningList   = try XCTUnwrap(records.first { $0["id"] as? String == owningListID })
            let ownerID      = try XCTUnwrap((owningList["payload"] as? [String: Any])?["collection_id"] as? String)
            let owner        = try XCTUnwrap(records.first { $0["id"] as? String == ownerID })
            let accountID    = "f0000000-0000-4000-8000-000000000001"
            let nativeOwner  = try adapter.collection(owner, selections: [], accountID: accountID,
                timeZoneID: "America/Chicago", listDates: [:])

            XCTAssertEqual(nativeOwner.id.uuidString.lowercased(), owner["id"] as? String)
            XCTAssertEqual(nativeOwner.lists.first?.cards.first?.word, "  Exact Card 🪴  ")

            let savedCard = try XCTUnwrap((owner["payload"] as? [String: Any])?["list_ids"] as? [String]).first

            XCTAssertEqual(nativeOwner.lists.first?.id, savedCard.flatMap { adapter.numericIDs[$0] })

            let lists    = records.filter { $0["record_type"] as? String == "list" }
            let list     = try XCTUnwrap(lists.first { ($0["payload"] as? [String: Any])?["title"] as? String == "Monday" })
            let imported = try adapter.list(list, timeZoneID: "America/Chicago", civilDate: "2026-10-19")

            XCTAssertEqual(imported.cards.map(\.word), ["  Exact Card 🪴  ", "Linked Note"])
            XCTAssertEqual(imported.archivedCards.map(\.word), ["Archived"])

            let card = try XCTUnwrap(imported.cards.first)

            XCTAssertEqual(card.location, "Oshkosh")
            XCTAssertTrue(card.isTitleChecked)
            XCTAssertTrue(card.isEditingLocked)
            XCTAssertEqual(card.descriptionOverride, "")
            XCTAssertEqual(card.subtitleOverride, "")
            XCTAssertEqual(card.startDateKind, .dateAndTime)
            XCTAssertEqual(try XCTUnwrap(card.startDate).timeIntervalSince1970, 1792843200.123, accuracy: 0.00001)
            XCTAssertEqual(card.appearance?.subtitleItalic, false)
            XCTAssertEqual(card.appearance?.listBackgroundOpacity, 0.4)
            XCTAssertEqual(card.members.count, 2)
            XCTAssertEqual(card.comments.first?.body, "Retain discussion")
            XCTAssertEqual(card.reactions?.first?.emoji, "🌱")
            XCTAssertEqual(card.showsReactionsInPreviews, false)
            XCTAssertEqual(card.checklists.first?.items.count, 5)
            XCTAssertEqual(card.checklists.first?.items.last?.retainedDetail?.description, "Keep this even while inactive")
            XCTAssertEqual(card.checklists.first?.items.last?.retainedURL?.absoluteString, "https://example.com/retained")
            XCTAssertEqual(card.attachments?.first?.fileName, "original.bin")
            XCTAssertEqual(card.attachments?.first?.drawingFileName, "drawing.bin")
            XCTAssertEqual(card.coverAttachmentID, card.attachments?.first?.id)
            XCTAssertEqual(card.editHistory?.first?.changes.first?.previousValue, Data([0, 255, 7]))
            XCTAssertEqual(card.editHistory?.first?.changes.first?.newValue, Data())
            XCTAssertEqual(card.dismissedActivityIDs, ["event-A", "event-B"])

            let duplicateTitles = records.filter { ($0["payload"] as? [String: Any])?["title"] as? String == "  Exact Card 🪴  " }
            let ids             = duplicateTitles.compactMap { ($0["id"] as? String).flatMap { adapter.numericIDs[$0] } }

            XCTAssertEqual(ids.count, 2)
            XCTAssertEqual(Set(ids).count, 2)

            let selected                 = try XCTUnwrap(exactCard["id"] as? String)
            let selection: [String: Any] = ["user_data_model_version": "1.0", "payload_schema_version": 1,
                "record_type": "content_selection", "id": UUID().uuidString.lowercased(), "workspace_id": exactCard["workspace_id"]!,
                "payload": ["account_id": accountID, "card_id": selected, "bookmarked": true, "importance": 4]]
            let importance = try adapter.importance([selection], accountID: accountID)

            XCTAssertEqual(importance.first?.level, 4)
            XCTAssertEqual(importance.first?.cardID, adapter.numericIDs[selected])
            XCTAssertEqual(importance.first?.collectionID.uuidString.lowercased(), ownerID)

            let bookmarkedOwner = try adapter.collection(owner, selections: [selection], accountID: accountID,
                timeZoneID: "America/Chicago", listDates: [:])

            XCTAssertTrue(bookmarkedOwner.savedCardIDs.contains(try XCTUnwrap(adapter.numericIDs[selected])))

            let labels = try adapter.labelLibrary()

            XCTAssertEqual(Set(labels.labels.map(\.id)), Set(records.filter { $0["record_type"] as? String == "label" }.compactMap { $0["id"] as? String }))

            let evidence: [String: Any] = ["lists": try JSONSerialization.jsonObject(with: JSONEncoder().encode([imported])),
                "numeric_ids": adapter.numericIDs]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            attachment.name = "EditableContent-ImportedModels.json"
            attachment.lifetime = .keepAlways

            add(attachment)
        }
    }


    /// @fcn MigrationContentTests.testPortableContentRejectsUnknownFieldsAndMissingFiles
    /// @brief Keep unsupported content from silently entering the native editor
    /// @return Void after fail-closed assertions
    /// @throws Fixture or preview errors
    func testPortableContentRejectsUnknownFieldsAndMissingFiles() throws
    {

        try fixture { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let records = try documents(preview)
            let adapter = try PortableEditableContent(records: records, assetFiles: [:])
            var card    = try XCTUnwrap(records.first { ($0["payload"] as? [String: Any])?["title"] as? String == "  Exact Card 🪴  " })

            XCTAssertThrowsError(try adapter.card(card, listTitle: "Monday", timeZoneID: "America/Chicago", civilDate: nil))

            var payload = try XCTUnwrap(card["payload"] as? [String: Any])

            payload["future_authored_value"] = "must not be lost"
            card["payload"] = payload

            XCTAssertThrowsError(try adapter.card(card, listTitle: "Monday", timeZoneID: "America/Chicago", civilDate: nil))
            XCTAssertThrowsError(try adapter.date(["kind": "time", "time": "01:30:00.000"], timeZoneID: "America/Chicago", civilDate: nil))
            XCTAssertThrowsError(try adapter.date(["kind": "time", "time": "01:30:00.000"], timeZoneID: "America/Chicago", civilDate: "2026-11-01"))
            XCTAssertThrowsError(try adapter.date(["kind": "time", "time": "02:30:00.000"], timeZoneID: "America/Chicago", civilDate: "2026-03-08"))
        }
    }


    /// @fcn MigrationContentTests.testPortableCalendarAndTemplateReconstruction
    /// @brief Rebuild calendar and routine metadata without reading original stores inside the adapter
    /// @return Void after authored ordering, day ownership, defaults and reconstruction assertions
    /// @throws Fixture or adapter failures
    func testPortableCalendarAndTemplateReconstruction() throws
    {

        try fixture { backup, url in

            let preview       = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let records       = try documents(preview)
            let assetDocument = try XCTUnwrap(JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("MigrationPreview/AssetPreview.json", in: preview.files)) as? [String: Any])
            let entries = try XCTUnwrap(assetDocument["entries"] as? [[String: Any]])
            let files   = Dictionary(uniqueKeysWithValues: try entries.map { entry in
                (try XCTUnwrap(entry["asset_id"] as? String), try XCTUnwrap(entry["original_name"] as? String))
            })
            let adapter      = try PortableEditableContent(records: records, assetFiles: files)
            let account      = "f0000000-0000-4000-8000-000000000001"
            let calendar     = try XCTUnwrap(adapter.calendarDocument(selections: [], accountID: account))
            let sourceValues = try MigrationBackupReader.values(in: backup)
            let original     = try JSONDecoder().decode(PlanningCalendarDocument.self,
                from: XCTUnwrap(sourceValues["Plenact.CalendarWeeks.v1"] as? Data))

            XCTAssertEqual(calendar.currentWeekKey, original.currentWeekKey)
            XCTAssertEqual(calendar.firstWeekday, original.firstWeekday)
            XCTAssertEqual(calendar.weeks.map(\.startKey), original.weeks.map(\.startKey))
            XCTAssertEqual(calendar.weeks.map { $0.collection.lists.map(\.title) }, original.weeks.map { $0.collection.lists.map(\.title) })
            XCTAssertEqual(calendar.weeks.first?.dayListIDs.keys.sorted(), original.weeks.first?.dayListIDs.keys.sorted())

            let library       = try XCTUnwrap(adapter.templateLibrary(accountID: account))
            let sourceLibrary = try JSONDecoder().decode(PlanningRoutineLibrary.self,
                from: XCTUnwrap(sourceValues["Plenact.PlanningTemplates.v1"] as? Data))

            XCTAssertEqual(library.templates.map(\.name), sourceLibrary.templates.map(\.name))
            XCTAssertEqual(library.templates.map(\.timeZoneID), sourceLibrary.templates.map(\.timeZoneID))
            XCTAssertEqual(library.templates.map(\.anchorKey), sourceLibrary.templates.map(\.anchorKey))
            XCTAssertEqual(library.templates.map(\.kind), sourceLibrary.templates.map(\.kind))
            XCTAssertEqual(library.bundledRoutineRevision, sourceLibrary.bundledRoutineRevision)

            let originalDefault = sourceLibrary.templates.first { $0.id == sourceLibrary.defaultWeekID }?.name

            XCTAssertEqual(library.templates.first { $0.id == library.defaultWeekID }?.name, originalDefault)

            var broken  = records
            let index   = try XCTUnwrap(broken.firstIndex { $0["record_type"] as? String == "calendar_index" })
            var payload = try XCTUnwrap(broken[index]["payload"] as? [String: Any])

            payload["current_week_start_date"] = "2099-01-01"
            broken[index]["payload"] = payload

            let invalid = try PortableEditableContent(records: broken, assetFiles: files)

            XCTAssertThrowsError(try invalid.calendarDocument(selections: [], accountID: account))
        }
    }

}


/// Verifies retained template metadata using the isolated complete portable-package fixture.
/// @section Purpose
///     Separate library metadata coverage from content conversion and the combined recovery test.
@MainActor
extension MigrationStudioTests
{

    /// @fcn MigrationStudioTests.testTemplateEditorPresentationSurvivesLibraryReload
    /// @brief Keep the editor presented while its multi-section library loads inside a List
    /// @return Void after restoring the test window and isolated defaults
    /// @throws Scene, presentation or synthetic-storage failures
    func testTemplateEditorPresentationSurvivesLibraryReload() async throws
    {

        let domain   = "Plenact.TemplatePresentationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let library  = PlanningRoutineLibrary.seeded
        let bytes    = try JSONEncoder().encode(library)

        defaults.set(bytes, forKey: PlanningRoutineStore.key)

        let scene    = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window   = UIWindow(windowScene: scene)

        defer
        {

            window.endEditing(true)

            window.isHidden = true
            window.rootViewController = nil

            previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: domain)
        }

        let template = try XCTUnwrap(library.templates.first)
        let host     = UIHostingController(rootView: NavigationStack
        {

            List
            {

                PlanningTemplateLibraryRows(defaults: defaults, editing: template)
            }
        })

        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host

        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(1500))

        let editor = try XCTUnwrap(host.presentedViewController)

        XCTAssertFalse(editor.isBeingDismissed)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(host.presentedViewController === editor)
        /// @fcn MigrationStudioTests.templateEditorDescendants
        /// @brief Find native input controls in the presented synthetic editor
        /// @param[in] view Hosted editor subtree
        /// @return Native descendants
        func descendants(_ view: UIView) -> [UIView]
        {

            [view] + view.subviews.flatMap(descendants)
        }

        let name = try XCTUnwrap(descendants(editor.view).compactMap { $0 as? UITextField }
            .first { $0.text == template.name })

        XCTAssertTrue(name.becomeFirstResponder())
        name.selectAll(nil)
        name.insertText("Unsaved template rename")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(name.text, "Unsaved template rename")
        XCTAssertTrue(host.presentedViewController === editor)
        editor.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(host.presentedViewController)
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), bytes)
    }


    /// @fcn MigrationStudioTests.testTemplateDeletionConfirmationIsPresented
    /// @brief Present the destructive confirmation while its library has offscreen trailing rows
    /// @return Void after restoring the synthetic window and isolated defaults
    /// @throws Scene, dialog or synthetic-storage failures
    func testTemplateDeletionConfirmationIsPresented() async throws
    {

        let domain   = "Plenact.TemplateDeleteDialogTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let library  = PlanningRoutineLibrary.seeded
        let bytes    = try JSONEncoder().encode(library)

        defaults.set(bytes, forKey: PlanningRoutineStore.key)

        let template = try XCTUnwrap(library.templates.first)
        let scene    = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window   = UIWindow(windowScene: scene)

        defer
        {

            window.isHidden = true
            window.rootViewController = nil

            previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: domain)
        }

        let host = UIHostingController(rootView: NavigationStack
        {

            List
            {

                PlanningTemplateLibraryRows(defaults: defaults, deleting: template)
            }
        })

        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host

        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(1500))

        let dialog = try XCTUnwrap(host.presentedViewController as? UIAlertController)

        XCTAssertEqual(dialog.title, "Delete this template?")
        XCTAssertEqual(dialog.actions.filter { $0.style == .destructive }.map(\.title), ["Delete " + template.name])
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), bytes)
        dialog.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), bytes)
    }


    /// @fcn MigrationStudioTests.retainedTemplateFixture
    /// @brief Capture a complete library and live Week with deliberately overlapping native IDs
    /// @param[in] edit Optional synthetic source setup after the complete library is captured
    /// @param[in] body Isolated backup assertions
    /// @return Void after synthetic cleanup
    /// @throws Fixture or assertion errors
    func retainedTemplateFixture(edit: ((inout [String: Any]) throws -> Void)? = nil,
        _ body: (LegacyWorkspaceBackup, URL) throws -> Void) throws
    {

        try fixture(edit: { values in

            var calendar = Calendar(identifier: .gregorian)

            calendar.timeZone = TimeZone(identifier: "America/Chicago")!
            calendar.firstWeekday = 2

            let instant = Date(timeIntervalSince1970: 1793016000)
            let week    = DatedPlanningWeek.make(for: instant,
                lists: [KanbanList(id: 1, title: "Monday", cards: [KanbanCard(id: 1, word: "Retained template task", listTitle: "Monday", checklists: [KanbanChecklist(title: "Copied steps", items: ["One", "Two"], completed: 1)])])],
                calendar: calendar)
            let first  = try PlanningRoutineTemplate.capture(name: "First week", week: week, calendar: calendar)
            let second = try PlanningRoutineTemplate.capture(name: "Second week", week: week, calendar: calendar)
            let day    = try PlanningRoutineTemplate.capture(name: "One day", week: week, day: instant, calendar: calendar)

            values["Plenact.Board.v1"] = try JSONEncoder().encode(week.collection.lists)
            values["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(
                PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week]))
            values["Plenact.PlanningTemplates.v1"] = try JSONEncoder().encode(
                PlanningRoutineLibrary(templates: [first, second, day], defaultWeekID: first.id, bundledRoutineRevision: 5))

            try edit?(&values)
        }, body)
    }


    /// @fcn MigrationStudioTests.testNewTemplateEditedExport
    /// @brief Preserve captured and duplicated templates with independent content identities
    /// @details Uses real capture with overlapping live/template aliases, copied nested content,
    ///          example focus, default selection, source immutability and fresh import/re-export.
    /// @return Void after isolated cleanup
    /// @throws Capture, conversion, installation or assertion-support failures
    func testNewTemplateEditedExport() throws
    {

        try retainedTemplateFixture { backup, url in

            let preview   = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package   = try MigrationTestPackage.prepare(preview)
            let candidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(package.fileWrappers?["PortableTestPackage"])))
            let root     = url.deletingLastPathComponent().appendingPathComponent("NewTemplateContainer")
            let stage    = url.deletingLastPathComponent().appendingPathComponent("NewTemplateStage")
            let domain   = "Plenact.NewTemplateExportTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {

                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)

            let key      = "Plenact.PlanningTemplates.v1"
            var library  = try JSONDecoder().decode(PlanningRoutineLibrary.self, from: XCTUnwrap(defaults.data(forKey: key)))
            let original = library
            let calendar = try JSONDecoder().decode(PlanningCalendarDocument.self,
                from: XCTUnwrap(defaults.data(forKey: "Plenact.CalendarWeeks.v1")))
            let week     = try XCTUnwrap(calendar.weeks.first)
            var captured = try PlanningRoutineTemplate.capture(name: "Captured Week", week: week, calendar: calendar.calendar)
            let listMap  = Dictionary(uniqueKeysWithValues: captured.collection.lists.enumerated().map { ($0.element.id, $0.offset + 1) })

            for index in captured.collection.lists.indices
            {

                var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(captured.collection.lists[index])) as! [String: Any]

                raw["id"] = index + 1

                var cards = raw["cards"] as! [[String: Any]]

                for index in cards.indices
                {

                    cards[index]["id"] = index + 1

                }

                raw["cards"] = cards
                captured.collection.lists[index] = try JSONDecoder().decode(KanbanList.self,
                    from: JSONSerialization.data(withJSONObject: raw))

            }

            captured.weekdays = captured.weekdays.mapValues { listMap[$0]! }

            captured.collection.lists[0].cards.append(KanbanCard(id: 2, word: "Template link target", listTitle: "Monday", checklists: []))

            var linked = KanbanChecklistItem(title: "Copied target", content: .linkedCard(cardID: 2))

            linked.linkedCollectionID = captured.collection.id

            captured.collection.lists[0].cards[0].checklists.append(KanbanChecklist(title: "Copied reference", items: [linked]))

            let photo     = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 42])
            let photoPath = root.appendingPathComponent("Documents/CardAttachments/template-photo.png")

            try FileManager.default.createDirectory(at: photoPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try photo.write(to: photoPath)

            let attachment = KanbanAttachment(fileName: "template-photo.png", mediaKind: .photo,
                addedAt: Date(timeIntervalSince1970: 1793000000.654321), caption: "Template photo caption")

            captured.collection.lists[0].cards[0].attachments = [attachment]
            captured.collection.lists[0].cards[0].coverAttachmentID = attachment.id

            let sourceCard = try XCTUnwrap(captured.collection.lists.first?.cards.first)

            captured.exampleFocus = PlanningExampleFocus(important: [sourceCard.id], bookmarked: [sourceCard.id], allDay: [sourceCard.id])

            var duplicate = library.templates[0]

            duplicate.id = UUID()
            duplicate.name = "Duplicated template"

            let day = try PlanningRoutineTemplate.capture(name: "Captured Day", week: week,
                day: PlanningDate.date(week.startKey, calendar: calendar.calendar)!, calendar: calendar.calendar)

            library.templates.append(contentsOf: [captured, duplicate, day])

            library.defaultWeekID = captured.id

            defaults.set(try JSONEncoder().encode(library), forKey: key)
            XCTAssertEqual(captured.collection.id, week.collection.id)
            XCTAssertEqual(duplicate.collection.id, original.templates[0].collection.id)

            let source  = try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let runtime = try PortableRuntimeEvidence.capture(root: root)
            let frozen  = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output  = try PortableEditedExport.prepare(frozen)
            let bytes   = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)

            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))

            let rebuilt = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])), retainedAliases: candidate.numericIDs)
            let restored = try JSONDecoder().decode(PlanningRoutineLibrary.self, from: XCTUnwrap(rebuilt.values[key] as? Data))

            XCTAssertEqual(restored.templates.count, original.templates.count + 3)
            XCTAssertEqual(restored.defaultWeekID, captured.id)

            let restoredCapture   = try XCTUnwrap(restored.templates.first { $0.id == captured.id })
            let restoredDuplicate = try XCTUnwrap(restored.templates.first { $0.id == duplicate.id })

            XCTAssertNotEqual(restoredCapture.collection.id, week.collection.id)
            XCTAssertNotEqual(restoredDuplicate.collection.id, duplicate.collection.id)

            let card       = try XCTUnwrap(restoredCapture.collection.lists.first?.cards.first)
            let target     = try XCTUnwrap(restoredCapture.collection.lists[0].cards.first { $0.word == "Template link target" })
            let copiedLink = try XCTUnwrap(card.checklists.last?.items.first)

            XCTAssertEqual(copiedLink.linkedCollectionID, restoredCapture.collection.id)
            XCTAssertEqual(copiedLink.content, .linkedCard(cardID: target.id))
            XCTAssertEqual(card.word, sourceCard.word)
            XCTAssertEqual(card.attachments?.first?.caption, "Template photo caption")
            XCTAssertEqual(card.coverAttachmentID, card.attachments?.first?.id)
            XCTAssertTrue(rebuilt.media.files.values.contains(photo))
            XCTAssertEqual(card.checklists.first?.title, "Copied steps")
            XCTAssertEqual(card.checklists.first?.items.map(\.title), ["One", "Two"])
            XCTAssertNotEqual(card.checklists.first?.id, sourceCard.checklists.first?.id)
            XCTAssertEqual(restoredCapture.exampleFocus?.bookmarked, [card.id])
            for template in original.templates
            {

                XCTAssertEqual(restored.templates.first { $0.id == template.id }, template)
            }
            for (store, value) in candidate.values where store != key
            {

                if let before = value as? Data, let after = rebuilt.values[store] as? Data
                {

                    XCTAssertTrue(NSDictionary(dictionary: ["v": try PortableEditedExport.nativeJSON(before, store: store)])
                        .isEqual(to: ["v": try PortableEditedExport.nativeJSON(after, store: store)]))
                }
            }

            var unknown      = try JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as! [String: Any]
            var rawTemplates = unknown["templates"] as! [[String: Any]]

            rawTemplates[original.templates.count]["futureField"] = true
            unknown["templates"] = rawTemplates

            defaults.set(try JSONSerialization.data(withJSONObject: unknown), forKey: key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root)))

            let fresh          = url.deletingLastPathComponent().appendingPathComponent("NewTemplateFreshStage")
            let freshCandidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))

            try freshCandidate.stage(at: fresh)
            try freshCandidate.install(from: fresh, root: root, defaults: defaults, domain: domain)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))
            for name in ["Assembly.json", "Manifest.json"]
            {

                let attachment = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output), uniformTypeIdentifier: "public.json")

                attachment.name = "NewTemplatePackage-" + name
                attachment.lifetime = .keepAlways

                add(attachment)
            }

            let wrappers  = try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let originals = try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let blobs = XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")

            blobs.name = "NewTemplatePackage-Blobs.json"
            blobs.lifetime = .keepAlways

            add(blobs)

            var removed = try JSONDecoder().decode(PlanningRoutineLibrary.self, from: XCTUnwrap(defaults.data(forKey: key)))

            removed.templates.removeAll { $0.id == captured.id }

            removed.defaultWeekID = original.defaultWeekID

            defaults.set(try JSONEncoder().encode(removed), forKey: key)

            let deletion = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root))
            let deletedCandidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(deletion.fileWrappers?["PortableTestPackage"])))

            XCTAssertEqual(try JSONDecoder().decode(PlanningRoutineLibrary.self,
                from: XCTUnwrap(deletedCandidate.values[key] as? Data)).templates.count, restored.templates.count - 1)
            XCTAssertTrue(deletedCandidate.media.files.values.contains(photo))
        }
    }


    /// @fcn MigrationStudioTests.testTemplateDeletionEditedExport
    /// @brief Delete default and complete libraries without changing live Weeks or recovery evidence
    /// @return Void after isolated cleanup
    /// @throws Fixture, export or reconstruction errors
    func testTemplateDeletionEditedExport() throws
    {

        try retainedTemplateFixture { backup, url in

            let preview   = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package   = try MigrationTestPackage.prepare(preview)
            let candidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(package.fileWrappers?["PortableTestPackage"])))
            let root     = url.deletingLastPathComponent().appendingPathComponent("DeletedTemplateContainer")
            let stage    = url.deletingLastPathComponent().appendingPathComponent("DeletedTemplateStage")
            let domain   = "Plenact.DeletedTemplateTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {

                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)

            let key      = "Plenact.PlanningTemplates.v1"
            let original = try JSONDecoder().decode(PlanningRoutineLibrary.self, from: XCTUnwrap(defaults.data(forKey: key)))
            let calendar = defaults.data(forKey: "Plenact.CalendarWeeks.v1")
            let assembly = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json",
                in: XCTUnwrap(package.fileWrappers?["PortableTestPackage"]))) as! [String: Any]
            var deleting = original

            deleting.templates.removeFirst()

            deleting.defaultWeekID = nil

            var comparison = candidate.values

            comparison[key] = try JSONEncoder().encode(deleting)

            let removedOwner = original.templates[0].collection
            let removedCard  = removedOwner.lists.flatMap { $0.cards }.first!
            let cardID       = try XCTUnwrap(candidate.numericIDs.first { $0.value == removedCard.id }?.key)
            var dangling     = assembly
            var export       = dangling["workspace_export"] as! [String: Any]
            var base         = export["base_workspace"] as! [String: Any]

            base["synthetic_reference_guard"] = ["record_type": "card", "id": cardID]
            export["base_workspace"] = base
            dangling["workspace_export"] = export

            XCTAssertThrowsError(try PortableStructuralEdits.removeTemplates(assembly: dangling,
                current: comparison, aliases: candidate.numericIDs, baseline: candidate))

            export = assembly["workspace_export"] as! [String: Any]
            export["local_card_deletions"] = [cardID]
            dangling = assembly
            dangling["workspace_export"] = export

            XCTAssertThrowsError(try PortableStructuralEdits.removeTemplates(assembly: dangling,
                current: comparison, aliases: candidate.numericIDs, baseline: candidate))

            var transferred = try JSONDecoder().decode(PlanningCalendarDocument.self, from: XCTUnwrap(calendar))

            transferred.weeks[0].collection.lists[0].cards.append(removedCard)

            comparison["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(transferred)

            XCTAssertThrowsError(try PortableStructuralEdits.removeTemplates(assembly: assembly,
                current: comparison, aliases: candidate.numericIDs, baseline: candidate))
            for count in [1, original.templates.count]
            {

                var library = original

                library.templates.removeFirst(count)

                library.defaultWeekID = nil

                defaults.set(try JSONEncoder().encode(library), forKey: key)

                let source  = try XCTUnwrap(defaults.persistentDomain(forName: domain))
                let runtime = try PortableRuntimeEvidence.capture(root: root)
                let frozen  = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
                let output  = try PortableEditedExport.prepare(frozen)
                let bytes   = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)

                XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
                XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
                XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
                XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                    try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))

                let rebuilt = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                    XCTUnwrap(output.fileWrappers?["PortableTestPackage"])), retainedAliases: candidate.numericIDs)

                XCTAssertEqual(try JSONDecoder().decode(PlanningRoutineLibrary.self,
                    from: XCTUnwrap(rebuilt.values[key] as? Data)), library)
                XCTAssertEqual(try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(rebuilt.values["Plenact.CalendarWeeks.v1"] as? Data)),
                    try JSONDecoder().decode(PlanningCalendarDocument.self, from: XCTUnwrap(calendar)))
                XCTAssertEqual(rebuilt.media.files, candidate.media.files)
                if count == original.templates.count
                {

                    for name in ["Assembly.json", "Manifest.json"]
                    {

                        let attachment = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                            uniformTypeIdentifier: "public.json")

                        attachment.name = "DeletedTemplatePackage-" + name
                        attachment.lifetime = .keepAlways

                        add(attachment)
                    }

                    let wrappers  = try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
                    let originals = try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                        ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
                    })
                    let blobs = XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")

                    blobs.name = "DeletedTemplatePackage-Blobs.json"
                    blobs.lifetime = .keepAlways

                    add(blobs)

                    let fresh = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                        XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
                    let freshStage = url.deletingLastPathComponent().appendingPathComponent("DeletedTemplateFresh")

                    try fresh.stage(at: freshStage)
                    try fresh.install(from: freshStage, root: root, defaults: defaults, domain: domain)
                    XCTAssertTrue(try PlanningRoutineStore.load(from: defaults).templates.isEmpty)
                    XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                        PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))
                }
            }
        }
    }


    /// @fcn MigrationStudioTests.testRetainedTemplateContentEditedExport
    /// @brief Edit retained template content independently of its source Week and sibling copies
    /// @return Void after isolated defaults and temporary container cleanup
    /// @throws Fixture, export, media or reconstruction errors
    func testRetainedTemplateContentEditedExport() throws
    {

        try retainedTemplateFixture { backup, url in

            let preview       = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package       = try MigrationTestPackage.prepare(preview)
            let originalFiles = try XCTUnwrap(package.fileWrappers?["PortableTestPackage"])
            let candidate     = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: originalFiles))
            let root          = url.deletingLastPathComponent().appendingPathComponent("RetainedTemplateContentContainer")
            let stage         = url.deletingLastPathComponent().appendingPathComponent("RetainedTemplateContentStage")
            let domain        = "Plenact.RetainedTemplateContentTests." + UUID().uuidString
            let defaults      = try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {

                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)

            let key        = PlanningRoutineStore.key
            let previous   = try PlanningRoutineStore.load(from: defaults)
            var library    = previous
            let templateID = library.templates[0].id
            let ownerID    = library.templates[0].collection.id.uuidString.lowercased()
            let number     = library.templates[0].collection.lists[0].cards[0].id
            let cardID     = try XCTUnwrap(candidate.numericIDs.first { $0.value == number }?.key)

            library.templates[0].collection.lists[0].cards[0].word = "Edited retained template task"
            library.templates[0].collection.lists[0].cards[0].descriptionOverride = "Edited template details"

            try PlanningRoutineStore.save(library, baseline: previous, to: defaults)

            let source  = try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let runtime = try PortableRuntimeEvidence.capture(root: root)
            let frozen  = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output  = try PortableEditedExport.prepare(frozen)
            let bytes   = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)

            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))

            var expected = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: originalFiles)) as! [String: Any]
            let actual   = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            var export   = expected["workspace_export"] as! [String: Any]
            var base     = export["base_workspace"] as! [String: Any]
            var planning = base["planning"] as! [String: Any]
            var content  = planning["content"] as! [String: Any]
            var cards    = content["cards"] as! [[String: Any]]
            let index    = try XCTUnwrap(cards.firstIndex { $0["id"] as? String == cardID })
            var payload  = cards[index]["payload"] as! [String: Any]

            payload["title"] = "Edited retained template task"
            payload["description_override"] = "Edited template details"

            let actualBase     = (actual["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            let actualPlanning = actualBase["planning"] as! [String: Any]
            let actualContent  = actualPlanning["content"] as! [String: Any]
            let editedCard     = try XCTUnwrap((actualContent["cards"] as! [[String: Any]]).first { $0["id"] as? String == cardID })
            let editedPayload  = editedCard["payload"] as! [String: Any]

            XCTAssertFalse((editedPayload["edit_history"] as? [Any] ?? []).isEmpty)

            payload["edit_history"] = editedPayload["edit_history"]
            cards[index]["payload"] = payload
            content["cards"] = cards
            planning["content"] = content
            base["planning"] = planning
            export["base_workspace"] = base
            expected["workspace_export"] = export

            XCTAssertEqual((actual["workspace_export"] as! [String: Any])["local_card_deletions"] as? [String], [])

            export["local_card_deletions"] = [String]()
            expected["workspace_export"] = export

            XCTAssertTrue(NSDictionary(dictionary: expected).isEqual(to: actual))

            let rebuilt = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])), retainedAliases: candidate.numericIDs)
            let restored        = try JSONDecoder().decode(PlanningRoutineLibrary.self, from: XCTUnwrap(rebuilt.values[key] as? Data))
            let originalHistory = library.templates[0].collection.lists[0].cards[0].editHistory ?? []
            let restoredHistory = restored.templates[0].collection.lists[0].cards[0].editHistory ?? []

            XCTAssertEqual(originalHistory.count, restoredHistory.count)
            for (old, new) in zip(originalHistory, restoredHistory)
            {

                XCTAssertEqual(old.id, new.id)
                XCTAssertEqual(old.changes, new.changes)
                XCTAssertEqual(old.timestamp.timeIntervalSince1970, new.timestamp.timeIntervalSince1970, accuracy: 0.00101)
            }
            func withoutEditedHistory(_ value: Any) -> Any
            {

                if var object = value as? [String: Any]
                {

                    if object["id"] as? Int == number, object["word"] != nil
                    {

                        object.removeValue(forKey: "editHistory")
                    }
                    return object.mapValues(withoutEditedHistory)
                }
                if let array = value as? [Any]
                {

                    return array.map(withoutEditedHistory)
                }
                return value
            }
            XCTAssertTrue(NSDictionary(dictionary: ["v": withoutEditedHistory(try PortableEditedExport.nativeJSON(JSONEncoder().encode(restored), store: key))])
                .isEqual(to: ["v": withoutEditedHistory(try PortableEditedExport.nativeJSON(JSONEncoder().encode(library), store: key))]))
            XCTAssertEqual(restored.templates[0].id, templateID)
            XCTAssertEqual(restored.templates[0].collection.id.uuidString.lowercased(), ownerID)
            XCTAssertEqual(rebuilt.media.files, candidate.media.files)

            let fresh = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
            let freshStage = url.deletingLastPathComponent().appendingPathComponent("RetainedTemplateContentFresh")

            try fresh.stage(at: freshStage)
            try fresh.install(from: freshStage, root: root, defaults: defaults, domain: domain)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))
            for name in ["Assembly.json", "Manifest.json"]
            {

                let attachment = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                    uniformTypeIdentifier: "public.json")

                attachment.name = "RetainedTemplateContentPackage-" + name
                attachment.lifetime = .keepAlways

                add(attachment)
            }

            let wrappers  = try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let originals = try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let blobs = XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")

            blobs.name = "RetainedTemplateContentPackage-Blobs.json"
            blobs.lifetime = .keepAlways

            add(blobs)
        }
    }


    /// @fcn MigrationStudioTests.testTemplateMetadataEditedExport
    /// @brief Preserve retained template names, order/default selection and content identity
    /// @return Void after synthetic container/defaults cleanup
    /// @throws Fixture, package or installation failures
    func testTemplateMetadataEditedExport() throws
    {

        try retainedTemplateFixture { backup, url in

            let preview   = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package   = try MigrationTestPackage.prepare(preview)
            let candidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(package.fileWrappers?["PortableTestPackage"])))
            let root     = url.deletingLastPathComponent().appendingPathComponent("TemplateContainer")
            let stage    = url.deletingLastPathComponent().appendingPathComponent("TemplateStage")
            let domain   = "Plenact.TemplateExportTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {

                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)

            let key      = "Plenact.PlanningTemplates.v1"
            var library  = try JSONDecoder().decode(PlanningRoutineLibrary.self, from: XCTUnwrap(defaults.data(forKey: key)))
            let original = library

            library.templates[0].name = "Renamed retained week"
            library.defaultWeekID = library.templates[1].id

            library.templates.reverse()
            defaults.set(try JSONEncoder().encode(library), forKey: key)

            let source  = try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let runtime = try PortableRuntimeEvidence.capture(root: root)
            let frozen  = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output  = try PortableEditedExport.prepare(frozen)
            let bytes   = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)

            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))

            let originalAssembly = try JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("Assembly.json", in: XCTUnwrap(package.fileWrappers?["PortableTestPackage"]))) as! [String: Any]
            let editedAssembly = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            var beforeBase     = (originalAssembly["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            var afterBase      = (editedAssembly["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            var beforePlanning = beforeBase["planning"] as! [String: Any]
            var afterPlanning  = afterBase["planning"] as! [String: Any]

            for group in ["templates", "template_libraries"]
            {

                let old = beforePlanning.removeValue(forKey: group) as! [[String: Any]]
                let new = afterPlanning.removeValue(forKey: group) as! [[String: Any]]

                XCTAssertEqual(Set(old.map { $0["id"] as! String }), Set(new.map { $0["id"] as! String }))
            }

            beforeBase["planning"] = beforePlanning
            afterBase["planning"] = afterPlanning

            XCTAssertTrue(NSDictionary(dictionary: beforeBase).isEqual(to: afterBase))

            let rebuilt = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))

            XCTAssertEqual(try JSONDecoder().decode(PlanningRoutineLibrary.self,
                from: XCTUnwrap(rebuilt.values[key] as? Data)), library)
            XCTAssertEqual(Set(library.templates.map(\.id)), Set(original.templates.map(\.id)))
            for template in library.templates
            {

                XCTAssertEqual(template.collection, original.templates.first { $0.id == template.id }?.collection)
            }
            for (store, value) in candidate.values where store != key
            {

                if let before = value as? Data, let after = rebuilt.values[store] as? Data
                {

                    XCTAssertTrue(NSDictionary(dictionary: ["v": try PortableEditedExport.nativeJSON(before, store: store)])
                        .isEqual(to: ["v": try PortableEditedExport.nativeJSON(after, store: store)]))
                }
            }

            let fresh = url.deletingLastPathComponent().appendingPathComponent("TemplateFreshStage")

            try rebuilt.stage(at: fresh)
            try rebuilt.install(from: fresh, root: root, defaults: defaults, domain: domain)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))
            for name in ["Assembly.json", "Manifest.json"]
            {

                let attachment = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                    uniformTypeIdentifier: "public.json")

                attachment.name = "TemplateMetadataPackage-" + name
                attachment.lifetime = .keepAlways

                add(attachment)
            }

            let wrappers  = try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let originals = try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let blobs = XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")

            blobs.name = "TemplateMetadataPackage-Blobs.json"
            blobs.lifetime = .keepAlways

            add(blobs)

            var cleared = library

            cleared.defaultWeekID = nil

            defaults.set(try JSONEncoder().encode(cleared), forKey: key)

            let clearOutput = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root))
            let clearCandidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(clearOutput.fileWrappers?["PortableTestPackage"])))

            XCTAssertEqual(try JSONDecoder().decode(PlanningRoutineLibrary.self,
                from: XCTUnwrap(clearCandidate.values[key] as? Data)), cleared)

            var raw       = try JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as! [String: Any]
            var templates = raw["templates"] as! [[String: Any]]

            templates[0]["futureField"] = true
            raw["templates"] = templates

            defaults.set(try JSONSerialization.data(withJSONObject: raw), forKey: key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root)))
            for variant in 0..<5
            {

                var invalid = library

                switch variant
                {

                case 0:
                    invalid.templates.append(invalid.templates[0])
                case 1:

                    invalid.templates[0].anchorKey = "2026-10-27"

                case 2:

                    invalid.defaultWeekID = invalid.templates.first { $0.kind == .day }!.id

                case 3:

                    invalid.bundledRoutineRevision = 99

                default:

                    invalid.templates[0].timeZoneID = "Etc/UTC"

                }
                defaults.set(try JSONEncoder().encode(invalid), forKey: key)
                XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root)))
            }
        }
    }
}
