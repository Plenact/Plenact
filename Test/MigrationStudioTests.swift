// --------------------------------------------------------------------------------------------------
// @file       MigrationStudioTests.swift
// @brief      Studio surface, reusable artwork and global Week-default preservation tests
// @details    Supported User Data Model versions: 1.0 base and working 1.1. Synthetic stores/files only; no source
//             workspace, image downloads, authenticated account or synchronization is modified
// --------------------------------------------------------------------------------------------------
import Foundation
import XCTest
@testable import Plenact


/// Verifies exact appearance metadata, shared original files and explicit canonical mapping gaps
/// @section Purpose
///     Preserve authored personalization without turning global defaults into per-Week overrides
@MainActor
final class MigrationStudioTests: XCTestCase
{
    /// @fcn MigrationStudioTests.fixture
    /// @brief Capture synthetic materials and originals for Studio and planning-export regressions
    /// @param[in] edit Optional raw source mutation before capture
    /// @param[in] body Assertions receiving frozen source and an isolated journal path
    /// @return Void after removing only synthetic files and preferences
    /// @throws Fixture, capture or assertion-support errors
    func fixture(edit: ((inout [String: Any]) throws -> Void)? = nil,
        _ body: (LegacyWorkspaceBackup, URL) throws -> Void) throws
    {
        let domain   = "Plenact.StudioTests." + UUID().uuidString       /* Lookup or storage namespace */
        let defaults =                                                  /* Preference store under test */
            try XCTUnwrap(UserDefaults(suiteName: domain))
        let root     =                                                  /* Synthetic workspace root    */
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer
        {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }

        let photo =                                                                                     /* Photo selection or source   */
            StudioSurface(material: .photo, color: "A1B2C3", strength: 0.2, readability: 0,
                verticalPosition: 0.25, zoom: 1.5, showsInPreviews: false, photoFileName: "wall.png")
        let remote =                                                                                    /* Remote comparison fixture   */
            StudioRemotePhoto(id: "source-photo", imageURL: URL(string: "https://images.example.test/photo")!,
                photographer: "Exact credit", profileURL: URL(string: "https://example.test/photographer")!,
                downloadURL: URL(string: "https://example.test/source")!)
        let settings =                                                                                  /* Workspace settings snapshot */
            StudioSettings(views: ["Today": photo, "Week": StudioSurface(material: .gradient),
            "Activity": StudioSurface(material: .linen), "Calendar": StudioSurface(material: .canvas),
            "Plans": StudioSurface(material: .dots), "Search": StudioSurface(material: .plain),
            "Settings": StudioSurface(material: .grid)], defaultCardSurface: photo,
                defaultNoteSurface: StudioSurface(material: .unsplash, remotePhoto: remote),
                variesNewSurfaces: false, variesNewHeaders: true, palette: ["A1B2C3", "A1B2C3", "FFFFFF"])
        let artwork =                                                                                   /* Reusable artwork definition */
            [StudioArtwork(name: "  Saved photo 🪴  ", surface: photo, header: .rose, italicSubtitle: false,
                titleColor: .blue, textColor: .graphite), StudioArtwork(name: "Color", surface: StudioSurface(material: .color))]
        let week = BoardAppearance(bannerBackground: .teal,                                             /* Synthetic week fixture      */
            collectionBackground: CollectionBackground(preset: .photo, photoFileName: "board.png"),
            studioCardSurface: StudioSurface(material: .paper), subtitleItalic: false)
        var values: [String: Any] =                                                                     /* Values being processed      */
            ["Plenact.Studio.Settings.v1": try JSONEncoder().encode(settings),
            "Plenact.Studio.Artwork.v1": try JSONEncoder().encode(artwork),
            "Plenact.WeekAppearance.v1": try JSONEncoder().encode(week)]

        try edit?(&values)
        defaults.setPersistentDomain(values, forName: domain)
        for path in ["Library/Application Support/PlenactStudioArtwork/wall.png",
            "Library/Application Support/PlenactCollectionBackgrounds/board.png"]
        {
            let url = root.appendingPathComponent(path)         /* Resolved file location */

            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([137, 80, 78, 71, 13, 10, 26, 10, 0]).write(to: url)
        }

        let backup =                                                                            /* Recoverable native snapshot */
            try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)

        try body(backup, root.appendingPathComponent("Journal/ids.json"))
    }


    /// @fcn MigrationStudioTests.document
    /// @brief Read actual emitted local Studio evidence
    /// @param[in] preview Prepared source conversion
    /// @return Parsed Studio-preview document
    /// @throws Missing or malformed output errors
    private func document(_ preview: MigrationPreview) throws -> [String: Any]
    {
        try XCTUnwrap(JSONSerialization.jsonObject(with:
            MigrationBackupReader.file("MigrationPreview/StudioPreview.json", in: preview.files)) as? [String: Any])
    }


    /// @fcn MigrationStudioTests.testExactSurfacesArtworkSharedFilesAndRetry
    /// @brief Retain material/framing/credit/style metadata, authored palette order and stable identities
    /// @return Void after exact output, original-file and retry assertions
    /// @throws Fixture, conversion or assertion-support errors
    func testExactSurfacesArtworkSharedFilesAndRetry() throws
    {
        try fixture { backup, url in

            let preview =       /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertEqual(preview.studioPreparedCount, 2)
            XCTAssertEqual(preview.artworkCount, 2)
            XCTAssertEqual(preview.appearanceReviewCount, 0)
            XCTAssertEqual(preview.appearanceModelRecordCount, 2)
            XCTAssertEqual(preview.verifiedAssetCount, 2)
            XCTAssertEqual(preview.assetIssueCount, 0)

            let doc     = try document(preview)         /* Decoded store document   */
            let payload =                               /* Canonical record payload */
                try XCTUnwrap((doc["studio_settings"] as? [String: Any])?["payload"] as? [String: Any])

            XCTAssertNil(payload["account_id"])
            XCTAssertEqual(payload["palette"] as? [String], ["A1B2C3", "A1B2C3", "FFFFFF"])
            XCTAssertEqual(payload["varies_new_surfaces"] as? Bool, false)

            let views =                                                 /* Rendered or configured views */
                try XCTUnwrap(payload["views"] as? [[String: Any]])

            XCTAssertEqual(views.count, 7)

            let surface =       /* Artwork surface definition */
                try XCTUnwrap(views.first { $0["destination"] as? String == "today" }?["surface"] as? [String: Any])

            XCTAssertEqual(surface["shows_in_previews"] as? Bool, false)
            XCTAssertEqual(surface["zoom"] as? Double, 1.5)
            XCTAssertEqual(surface["readability"] as? Double, 0)

            let note =                                                                  /* Note content record */
                try XCTUnwrap(payload["default_note_surface"] as? [String: Any])

            XCTAssertEqual((note["remote_photo"] as? [String: Any])?["photographer"] as? String, "Exact credit")

            let second =        /* Second comparison value */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertEqual(try JSONSerialization.data(withJSONObject: doc, options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: document(second), options: .sortedKeys))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: backup.files),
                try MigrationBackupReader.file("Preferences.plist", in: preview.files))
            for name in ["StudioPreview.json", "AppearancePreview.json", "AssetPreview.json", "IdentityJournal.json"]
            {
                let attachment =        /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("MigrationPreview/" + name, in: preview.files), uniformTypeIdentifier: "public.json")

                attachment.name = "Studio-" + name
                attachment.lifetime = .keepAlways

                add(attachment)
            }

            let source =                                                                        /* Source value for this operation */
                try MigrationBackupReader.values(in: backup).mapValues { value -> Any in
                if let bytes = value as? Data
                {
                    return (try? JSONSerialization.jsonObject(with: bytes)) ?? NSNull()
                }
                return value
            }
            let records                     =           /* Records being processed */
                try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"]?.fileWrappers)
            let output                      =           /* Decoded JSON object     */
                try records.sorted { $0.key < $1.key }.map { try JSONSerialization.jsonObject(with: XCTUnwrap($0.value.regularFileContents)) }
            var originals: [String: String] = [:]       /* Retained original files */

            for path in ["Library/Application Support/PlenactStudioArtwork/wall.png",
                "Library/Application Support/PlenactCollectionBackgrounds/board.png"]
            {
                originals[path] = try MigrationBackupReader.file(path, in: backup.files).base64EncodedString()
            }
            for (name, value) in [("SourceValues", source as Any), ("Records", output as Any), ("Originals", originals as Any)]
            {
                let attachment =        /* Synthetic test evidence */
                    XCTAttachment(data: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), uniformTypeIdentifier: "public.json")

                attachment.name = "Studio-" + name + ".json"
                attachment.lifetime = .keepAlways

                add(attachment)
            }
        }
    }


    /// @fcn MigrationStudioTests.testGlobalWeekAppearanceDoesNotBecomePerCollectionOverride
    /// @brief Preserve the global default in its own 1.1 record rather than rewriting Week content
    /// @return Void after versioned mapping, explicit false and full appearance assertions
    /// @throws Fixture or assertion-support errors
    func testGlobalWeekAppearanceDoesNotBecomePerCollectionOverride() throws
    {
        try fixture { backup, url in

            let preview =                                               /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let doc     = try document(preview)                         /* Decoded store document      */
            let issues  = try XCTUnwrap(doc["issues"] as? [String])     /* Validation findings         */

            XCTAssertTrue(issues.isEmpty)
            XCTAssertEqual(doc["canonical_mapping_complete"] as? Bool, true)
            XCTAssertEqual(doc["appearance_model_version"] as? String, "1.1")

            let appearance =    /* Resolved appearance choices */
                try XCTUnwrap(JSONSerialization.jsonObject(with: MigrationBackupReader.file("MigrationPreview/AppearancePreview.json", in: preview.files)) as? [String: Any])

            XCTAssertEqual((appearance["workspace_appearance"] as? [String: Any])?["record_type"] as? String, "workspace_appearance")
            XCTAssertEqual((appearance["artwork_library"] as? [String: Any])?["record_type"] as? String, "artwork_library")

            let week =          /* Synthetic week fixture */
                try XCTUnwrap((doc["global_week_appearance"] as? [String: Any])?["appearance"] as? [String: Any])

            XCTAssertEqual(week["subtitle_italic"] as? Bool, false)
            XCTAssertEqual(week["banner_background"] as? String, "teal")
        }
    }


    /// @fcn MigrationStudioTests.testAbsentStoresNeverInventSavedLooks
    /// @brief Leave absent Studio/global stores absent while retaining independent original files
    /// @return Void after zero-conversion and nullable evidence assertions
    /// @throws Fixture or assertion-support errors
    func testAbsentStoresNeverInventSavedLooks() throws
    {
        try fixture(edit: {
            $0 = [:]
        }) { backup, url in

            let preview =                                                       /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url)

            XCTAssertEqual(preview.studioPreparedCount, 0)
            XCTAssertEqual(preview.artworkCount, 0)

            let doc = try document(preview)     /* Decoded store document */

            XCTAssertTrue(doc["studio_settings"] is NSNull)
            XCTAssertTrue(doc["global_week_appearance"] is NSNull)
            XCTAssertEqual(doc["artwork_store_present"] as? Bool, false)
        }
    }


    /// @fcn MigrationStudioTests.testInvalidStudioEvidenceBlocksOnlyItsOwnSlice
    /// @brief Refuse unknown fields/destinations, malformed colors, invalid framing and duplicate artwork
    /// @return Void after safe review without a partially emitted appearance slice
    /// @throws Fixture or assertion-support errors
    func testInvalidStudioEvidenceBlocksOnlyItsOwnSlice() throws
    {
        for variant in 0..<6
        {
            try fixture(edit: { values in
                if variant == 5
                {
                    var artwork =       /* Reusable artwork definition */
                        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(values["Plenact.Studio.Artwork.v1"] as? Data)) as? [[String: Any]])

                    artwork[1]["id"] = artwork[0]["id"]
                    values["Plenact.Studio.Artwork.v1"] = try JSONSerialization.data(withJSONObject: artwork)

                    return
                }

                var settings =                                          /* Workspace settings snapshot  */
                    try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(values["Plenact.Studio.Settings.v1"] as? Data)) as? [String: Any])
                var views    =                                          /* Rendered or configured views */
                    try XCTUnwrap(settings["views"] as? [String: Any])
                var surface  =                                          /* Artwork surface definition   */
                    try XCTUnwrap(views["Today"] as? [String: Any])

                if variant == 0
                {
                    surface["unknown"] = "future"
                }
                else if variant == 1
                {
                    surface["color"] = "a1b2c3"
                }
                else if variant == 2
                {
                    surface["zoom"] = 2.5
                }
                else if variant == 3
                {
                    surface["photoFileName"] = "../outside.png"
                }
                else
                {
                    views["Unknown destination"] = surface
                }

                views["Today"] = surface
                settings["views"] = views
                values["Plenact.Studio.Settings.v1"] = try JSONSerialization.data(withJSONObject: settings)
            }) { backup, url in

                let preview =           /* Converted migration preview */
                    try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

                XCTAssertEqual(preview.studioPreparedCount, 0)
                XCTAssertEqual(preview.artworkCount, 0)
                XCTAssertEqual(preview.appearanceReviewCount, 1)
                XCTAssertNil(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["StudioPreview.json"])
                XCTAssertEqual(preview.verifiedAssetCount, 2)
            }
        }
    }

    /// @fcn MigrationStudioTests.testAppearanceLibraryRetainsExactSourceOrderAndIndependentIds
    /// @brief Compare the new ordered record with original artwork IDs and retained base mappings
    /// @return Void after exact source-sequence and version-namespace checks
    /// @throws Fixture, conversion or assertion-support errors
    func testAppearanceLibraryRetainsExactSourceOrderAndIndependentIds() throws
    {
        try fixture { backup, url in

            let preview =                                                                               /* Converted migration preview     */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let source  =                                                                               /* Source value for this operation */
                try MigrationBackupReader.values(in: backup)
            let artwork =                                                                               /* Reusable artwork definition     */
                try JSONDecoder().decode([StudioArtwork].self,
                    from: XCTUnwrap(source["Plenact.Studio.Artwork.v1"] as? Data))
            let journal    =                                                                            /* Migration identity journal      */
                try MigrationIdentityJournal.decode(MigrationBackupReader.file("MigrationPreview/IdentityJournal.json", in: preview.files))
            let appearance =                                                                            /* Resolved appearance choices     */
                try XCTUnwrap(JSONSerialization.jsonObject(with: MigrationBackupReader.file("MigrationPreview/AppearancePreview.json", in: preview.files)) as? [String: Any])
            let library    =                                                                            /* Retained library contents       */
                try XCTUnwrap(appearance["artwork_library"] as? [String: Any])
            let ordered    =                                                                            /* Values in display order         */
                try XCTUnwrap((library["payload"] as? [String: Any])?["artwork_ids"] as? [String])
            let expected   = try artwork.map { item in                                                  /* Expected operation result       */
                try XCTUnwrap(journal.entries.first {
                    $0.source.recordType == "studio_artwork" && $0.source.owner == "artwork_library" &&
                        $0.source.legacyID == item.id.uuidString.lowercased()
                }?.target.uuidString.lowercased())
            }

            XCTAssertEqual(ordered, expected)
            XCTAssertEqual(library["user_data_model_version"] as? String, "1.1")
            XCTAssertEqual(journal.formatVersion, 3)

            let records =       /* Records being processed */
                try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"]?.fileWrappers)

            for file in records.values
            {
                let record =    /* Decoded JSON object */
                    try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(file.regularFileContents)) as? [String: Any])

                XCTAssertEqual(record["user_data_model_version"] as? String, "1.0")
            }
        }
    }


    /// @fcn MigrationStudioTests.testJournalUpgradePreservesMappingsAndNeverDowngradesAfterNestedAllocation
    /// @brief Upgrade existing source identities to format 3 without resetting or relabeling them
    /// @return Void after exact identity, retry and incompatible-reader assertions
    /// @throws Journal encode/decode or assertion-support errors
    func testJournalUpgradePreservesMappingsAndNeverDowngradesAfterNestedAllocation() throws
    {
        var original   = MigrationIdentityJournal()                     /* Baseline before changes         */
        let source     =                                                /* Source value for this operation */
            MigrationSourceIdentity(recordType: "card", owner: "original-owner", legacyID: "1", discriminator: nil)
        let card       = try original.resolve(source)                   /* Synthetic card fixture          */
        var upgraded   =                                                /* Value in the current format     */
            try MigrationIdentityJournal.decode(original.encoded())
        let appearance =                                                /* Resolved appearance choices     */
            MigrationSourceIdentity(recordType: "workspace_appearance", owner: "workspace_metadata", legacyID: "Plenact.WeekAppearance.v1", discriminator: nil)
        let target     = try upgraded.resolve(appearance)               /* Target under consideration      */

        _ = try upgraded.resolve(MigrationSourceIdentity(recordType: "nested_comment", owner: card.uuidString.lowercased(), legacyID: UUID().uuidString.lowercased(), discriminator: nil))

        XCTAssertEqual(upgraded.formatVersion, 3)
        XCTAssertEqual(try upgraded.resolve(source), card)
        XCTAssertEqual(try upgraded.resolve(appearance), target)
        XCTAssertEqual(upgraded.previewWorkspaceID, original.previewWorkspaceID)
        XCTAssertEqual(upgraded.sourceInstallationID, original.sourceInstallationID)
        XCTAssertEqual(try MigrationIdentityJournal.decode(upgraded.encoded()).formatVersion, 3)

        var unsupported =                                                                               /* Rejected edit fixture */
            try XCTUnwrap(JSONSerialization.jsonObject(with: upgraded.encoded()) as? [String: Any])

        unsupported["formatVersion"] = 2

        XCTAssertThrowsError(try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: unsupported)))
    }


    /// @fcn MigrationStudioTests.testExplicitEmptyLibraryIsDistinctFromMissingModel11Record
    /// @brief Retain saved empty ordering while allocating no appearance record for absent sources
    /// @return Void after presence, empty-array and versioned-record count checks
    /// @throws Fixture, conversion or assertion-support errors
    func testExplicitEmptyLibraryIsDistinctFromMissingModel11Record() throws
    {
        for present in [false, true]
        {
            try fixture(edit: { values in

                values = [:]

                if present
                {
                    values["Plenact.Studio.Artwork.v1"] = Data("[]".utf8)
                }
            }) { backup, url in

                let preview    =                                                        /* Converted migration preview */
                    try MigrationPreview.prepare(backup: backup, journalURL: url)
                let appearance =                                                        /* Resolved appearance choices */
                    try XCTUnwrap(JSONSerialization.jsonObject(with: MigrationBackupReader.file("MigrationPreview/AppearancePreview.json", in: preview.files)) as? [String: Any])

                XCTAssertEqual(preview.appearanceModelRecordCount, present ? 1 : 0)
                XCTAssertTrue(appearance["workspace_appearance"] is NSNull)
                XCTAssertEqual(appearance["artwork_library"] is NSNull, !present)
                if present
                {
                    let library =                                                       /* Retained library contents */
                        try XCTUnwrap(appearance["artwork_library"] as? [String: Any])

                    XCTAssertEqual(((library["payload"] as? [String: Any])?["artwork_ids"] as? [String])?.count, 0)
                }
            }
        }
    }


    /// @fcn MigrationStudioTests.testCombinedPortableTestPackage
    /// @brief Assemble one native source with calendar content, selections, profile, planning and artwork
    /// @return Void after preserved-source, stable-retry and export-evidence assertions
    /// @throws Fixture, mapping, package or serialization errors
    func testCombinedPortableTestPackage() throws
    {
        try fixture(edit: { values in

            let instant  = Date(timeIntervalSince1970: 1792843200)      /* Reference timestamp       */
            var calendar = Calendar(identifier: .gregorian)             /* Date calculation calendar */

            calendar.timeZone = TimeZone(identifier: "America/Chicago")!
            calendar.firstWeekday = 2

            let card =                                                                          /* Synthetic card fixture */
                KanbanCard(id: 1, word: "  Package Card 🪴  ", listTitle: "Day", checklists: [], createdAt: instant)
            var week = DatedPlanningWeek.make(for: instant,                                     /* Synthetic week fixture */
                lists: [KanbanList(id: 1, title: "Day", cards: [card])], calendar: calendar)

            week.collection.savedCardIDs = [1]
            values["Plenact.Board.v1"] = try JSONEncoder().encode(week.collection.lists)
            values["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(
                PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week]))
            values["Plenact.LibraryImportant.v1"] = try JSONEncoder().encode([
                LibraryImportanceItem(collectionID: week.collection.id, cardID: 1, level: 4)])

            let profile =                                                                               /* Synthetic profile fixture */
                LocalProfile(createdAt: instant, displayName: "Synthetic package writer", email: "",
                    context: "", avatarColor: .teal, avatarForegroundColor: .white,
                    preferences: LocalProfilePreferences())

            values["Plenact.LocalProfile.v1"] = try JSONEncoder().encode(profile)
            values["Plenact.PlanPreferences.v1"] = try JSONEncoder().encode(LocalProfilePreferences())

            var plan = DailyPlan(date: instant, calendar: calendar)     /* Daily planning record */

            plan.intention = "Exact package intention"
            plan.updatedAt = instant
            values["Plenact.DailyPlans.v1"] = try JSONEncoder().encode(DailyPlanStore.Document(plans: [plan.id: plan]))
        }) { backup, url in

            let preview =                                               /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let output  = try MigrationTestPackage.prepare(preview)     /* Operation output            */

            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: backup.files),
                try MigrationBackupReader.file("Preferences.plist", in: output))

            let second   = try MigrationTestPackage.prepare(preview)            /* Second comparison value   */
            let package  =                                                      /* Portable package contents */
                try XCTUnwrap(output.fileWrappers?["PortableTestPackage"])
            let reviewed =                                                      /* Verified operation input  */
                try PortablePackageReview.review(files: package)

            XCTAssertEqual(reviewed.cardCount, 1)
            XCTAssertEqual(reviewed.mediaCount, 2)

            let candidate =                                             /* Candidate under validation */
                try PortableWorkspaceCandidate.prepare(reviewed)

            XCTAssertEqual(candidate.media.filenames.count, 2)

            let currentBoard = try JSONDecoder().decode([KanbanList].self,      /* Current board */
                from: XCTUnwrap(candidate.values["Plenact.Board.v1"] as? Data))

            XCTAssertEqual(currentBoard.flatMap(\.cards).map(\.word), ["  Package Card 🪴  "])

            let saved =                                                                 /* Saved state under review */
                try XCTUnwrap(candidate.values["Plenact.SavedCardIDs.v1"] as? [Int])

            XCTAssertEqual(saved, currentBoard.flatMap(\.cards).map(\.id))

            let importance =                                            /* Owner-qualified importance state */
                try JSONDecoder().decode([LibraryImportanceItem].self,
                    from: XCTUnwrap(candidate.values["Plenact.LibraryImportant.v1"] as? Data))

            XCTAssertEqual(importance.first?.level, 4)

            let plans =                                                 /* Saved daily planning records */
                try JSONDecoder().decode(DailyPlanStore.Document.self,
                    from: XCTUnwrap(candidate.values["Plenact.DailyPlans.v1"] as? Data))

            XCTAssertEqual(plans.plans.values.first?.intention, "Exact package intention")

            let candidateURL =                                                                  /* Candidate URL */
                url.deletingLastPathComponent().appendingPathComponent("CompleteCandidate")

            try candidate.stage(at: candidateURL)
            try candidate.media.verify(at: candidateURL)

            let retained =      /* State retained for recovery */
                candidateURL.appendingPathComponent("Library/Application Support/PlenactPortableRuntime")

            XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("CanonicalPackage.bin")), reviewed.snapshot)

            let persisted =                                             /* Previously saved state */
                try PropertyListSerialization.propertyList(from:
                Data(contentsOf: retained.appendingPathComponent("NativeStores.plist")), format: nil)

            XCTAssertTrue(NSDictionary(dictionary: candidate.values).isEqual(to: try XCTUnwrap(persisted as? [String: Any])))
            XCTAssertThrowsError(try candidate.stage(at: candidateURL))

            let store =         /* Persistence boundary */
                PortableTestWorkspace(root: url.deletingLastPathComponent().appendingPathComponent("PortableInstallation"))

            XCTAssertNil(try store.active())
            XCTAssertEqual(try store.install(reviewed).cardCount, 1)

            let reopened =                              /* Instance reloaded from storage */
                PortableTestWorkspace(root: store.root)

            XCTAssertEqual(try reopened.active()?.mediaCount, 2)
            XCTAssertTrue(try reopened.canUndo())
            XCTAssertNil(try reopened.undo())
            XCTAssertEqual(try reopened.undo()?.cardCount, 1)

            let stateBeforeFailure =                                                    /* State before failure */
                try Data(contentsOf: store.root.appendingPathComponent("state.json"))

            XCTAssertThrowsError(try store.install(reviewed, beforeCommit: {
                throw CocoaError(.fileWriteUnknown)
            }))
            XCTAssertEqual(try Data(contentsOf: store.root.appendingPathComponent("state.json")), stateBeforeFailure)
            XCTAssertEqual(try store.active()?.cardCount, 1)
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: backup.files),
                try MigrationBackupReader.file("Preferences.plist", in: output))
            guard let frozen = package.serializedRepresentation,
                  let corrupt = FileWrapper(serializedRepresentation: frozen),
                  let originalAssembly = corrupt.fileWrappers?["Assembly.json"] else
            {
                XCTFail("Missing test package assembly")
                return
            }
            corrupt.removeFileWrapper(originalAssembly)

            let replacement =                                           /* Replacement content or state */
                FileWrapper(regularFileWithContents: Data("{}".utf8))

            replacement.preferredFilename = "Assembly.json"

            corrupt.addFileWrapper(replacement)
            XCTAssertThrowsError(try PortablePackageReview.review(files: corrupt))

            let future      =                                                                   /* Future-dated comparison value */
                try XCTUnwrap(FileWrapper(serializedRepresentation: frozen))
            var rawManifest = try XCTUnwrap(JSONSerialization.jsonObject(with:                  /* Raw manifest                  */
                MigrationBackupReader.file("Manifest.json", in: future)) as? [String: Any])

            rawManifest["format_version"] = 99

            future.removeFileWrapper(try XCTUnwrap(future.fileWrappers?["Manifest.json"]))

            let changedManifest =       /* Changed manifest */
                FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: rawManifest))

            changedManifest.preferredFilename = "Manifest.json"

            future.addFileWrapper(changedManifest)
            XCTAssertThrowsError(try PortablePackageReview.review(files: future))
            for name in ["Assembly.json", "Manifest.json"]
            {
                let bytes =                                                                     /* Serialized or original bytes */
                    try MigrationBackupReader.file("PortableTestPackage/" + name, in: output)

                XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/" + name, in: second))

                let attachment =                                                        /* Synthetic test evidence */
                    XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")

                attachment.name = "NativePackage-" + name
                attachment.lifetime = .keepAlways

                add(attachment)
            }

            let manifest =                                                      /* Package inventory and hashes  */
                try XCTUnwrap(JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("PortableTestPackage/Manifest.json", in: output)) as? [String: Any])
            let mapping                 =                                       /* Source-to-target identity map */
                try XCTUnwrap(manifest["originals"] as? [[String: Any]])
            var blobs: [String: String] = [:]                                   /* Verified original file blobs  */

            for entry in mapping
            {
                let blob  =                                                                     /* Verified original file bytes  */
                    try XCTUnwrap(entry["blob"] as? String)
                let path  =                                                                     /* Filesystem or navigation path */
                    try XCTUnwrap(entry["source_path"] as? String)
                let bytes =                                                                     /* Serialized or original bytes  */
                    try MigrationBackupReader.file("PortableTestPackage/" + blob, in: output)

                XCTAssertEqual(bytes, try MigrationBackupReader.file(path, in: backup.files))

                blobs[blob] = bytes.base64EncodedString()
            }

            let attachment =    /* Synthetic test evidence */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: blobs, options: .sortedKeys),
                    uniformTypeIdentifier: "public.json")

            attachment.name = "NativePackage-Blobs.json"
            attachment.lifetime = .keepAlways

            add(attachment)
        }
    }


    /// @fcn MigrationStudioTests.testPortablePackageRejectsSourceReview
    /// @brief Block unclassified saved data instead of claiming complete source coverage
    /// @return Void after fail-closed preparation
    /// @throws Fixture or preview errors
    func testPortablePackageRejectsSourceReview() throws
    {
        try fixture(edit: { values in

            values["Plenact.FutureUserData.v1"] = "must not disappear"
        }) { backup, url in

            let preview =       /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")

            XCTAssertThrowsError(try MigrationTestPackage.prepare(preview))
        }
    }


    /// @fcn MigrationStudioTests.testPortableUndoRejectsCorruptPreviousGeneration
    /// @brief Verify rollback failure leaves the active portable test copy selected
    /// @return Void after corruption rejection and unchanged activation assertions
    /// @throws Fixture, installation or filesystem errors
    func testPortableUndoRejectsCorruptPreviousGeneration() throws
    {
        try fixture { backup, url in

            let preview  =                                              /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let output   = try MigrationTestPackage.prepare(preview)    /* Operation output            */
            let reviewed =                                              /* Verified operation input    */
                try PortablePackageReview.review(files: XCTUnwrap(output.fileWrappers?["PortableTestPackage"]))
            let store    =                                              /* Persistence boundary        */
                PortableTestWorkspace(root: url.deletingLastPathComponent().appendingPathComponent("PortableUndo"))

            _ = try store.install(reviewed)
            _ = try store.install(reviewed)

            let stateURL = store.root.appendingPathComponent("state.json")                      /* State URL                  */
            let before   = try Data(contentsOf: stateURL)                                       /* State before the operation */
            let state    =                                                                      /* Current operation state    */
                try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
            let old      = try XCTUnwrap(state["undo"] as? String)                              /* Previous operation state   */

            try Data("corrupt".utf8).write(to: store.root.appendingPathComponent(old).appendingPathComponent("snapshot.bin"))
            XCTAssertThrowsError(try store.undo())
            XCTAssertEqual(try Data(contentsOf: stateURL), before)
            XCTAssertEqual(try store.active()?.mediaCount, 2)
        }
    }


    /// @fcn MigrationStudioTests.testEditableStudioReconstruction
    /// @brief Project canonical Studio settings, ordered artwork and global Week defaults into native models
    /// @return Void after exact look, palette, surface and ownership assertions
    /// @throws Fixture or reconstruction errors
    func testEditableStudioReconstruction() throws
    {
        try fixture { backup, url in

            let preview  =                                                      /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let output   = try MigrationTestPackage.prepare(preview)            /* Operation output            */
            let assembly =                                                      /* Assembled portable records  */
                try XCTUnwrap(JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)) as? [String: Any])
            let export   =                                                      /* Prepared export evidence    */
                try XCTUnwrap(assembly["workspace_export"] as? [String: Any])
            let base     =                                                      /* Base value before overrides */
                try XCTUnwrap(export["base_workspace"] as? [String: Any])
            let wrappers =                                                      /* Package file wrappers       */
                try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"]?.fileWrappers)
            let records  =                                                      /* Records being processed     */
                try wrappers.sorted { $0.key < $1.key }.map { item in
                try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(item.value.regularFileContents)) as? [String: Any])
            }
            let assetPreview = try XCTUnwrap(JSONSerialization.jsonObject(with:         /* Asset preview                */
                MigrationBackupReader.file("MigrationPreview/AssetPreview.json", in: preview.files)) as? [String: Any])
            let entries =                                                               /* Entries being processed      */
                try XCTUnwrap(assetPreview["entries"] as? [[String: Any]])
            let files   =                                                               /* Files used by this operation */
                Dictionary(uniqueKeysWithValues: try entries.map {
                (try XCTUnwrap($0["asset_id"] as? String), try XCTUnwrap($0["original_name"] as? String))
            })
            let adapter          =                                                              /* Store conversion adapter        */
                try PortableEditableContent(records: records, assetFiles: files)
            let settings         =                                                              /* Workspace settings snapshot     */
                try XCTUnwrap(adapter.studioSettings(base["studio_settings"] as? [String: Any], accountID: MigrationTestPackage.accountID))
            let looks            =                                                              /* Looks comparison fixture        */
                try XCTUnwrap(adapter.artwork(export["artwork_library"] as? [String: Any]))
            let week             =                                                              /* Synthetic week fixture          */
                try XCTUnwrap(adapter.weekAppearance(export["workspace_appearance"] as? [String: Any]))
            let source           =                                                              /* Source value for this operation */
                try MigrationBackupReader.values(in: backup)
            let expectedSettings =                                                              /* Expected settings               */
                try JSONDecoder().decode(StudioSettings.self,
                    from: XCTUnwrap(source["Plenact.Studio.Settings.v1"] as? Data))
            let expectedLooks = try JSONDecoder().decode([StudioArtwork].self,                  /* Expected looks                  */
                from: XCTUnwrap(source["Plenact.Studio.Artwork.v1"] as? Data))
            let expectedWeek = try JSONDecoder().decode(BoardAppearance.self,                   /* Expected week                   */
                from: XCTUnwrap(source["Plenact.WeekAppearance.v1"] as? Data))

            XCTAssertEqual(settings, expectedSettings)
            XCTAssertEqual(looks.map(\.name), expectedLooks.map(\.name))
            XCTAssertEqual(looks.map(\.surface), expectedLooks.map(\.surface))
            XCTAssertEqual(looks.map(\.italicSubtitle), expectedLooks.map(\.italicSubtitle))
            XCTAssertEqual(week, expectedWeek)
        }
    }


    /// @fcn MigrationStudioTests.testVerifiedNativeMediaStaging
    /// @brief Stage exact portable originals with collision-free names and reject corruption or overwrite
    /// @return Void after staged-byte, inventory and original-source preservation checks
    /// @throws Fixture, package, media-plan or filesystem failures
    func testVerifiedNativeMediaStaging() throws
    {
        try fixture { backup, url in

            let preview  =                                                      /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let output   = try MigrationTestPackage.prepare(preview)            /* Operation output            */
            let reviewed =                                                      /* Verified operation input    */
                try PortablePackageReview.review(files: XCTUnwrap(output.fileWrappers?["PortableTestPackage"]))
            let plan     = try PortableMediaPlacement.prepare(reviewed)         /* Daily planning record       */

            XCTAssertEqual(plan.filenames.count, 2)
            XCTAssertEqual(Set(plan.filenames.values).count, 2)
            XCTAssertEqual(plan.files.count, 2)

            let destination =                                                                   /* Destination for the operation */
                url.deletingLastPathComponent().appendingPathComponent("MediaCandidate")

            try plan.stage(at: destination)
            try plan.verify(at: destination)
            for (path, expected) in plan.files
            {
                XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(path)), expected)
            }
            XCTAssertThrowsError(try plan.stage(at: destination))

            let path =                                          /* Filesystem or navigation path */
                try XCTUnwrap(plan.files.keys.sorted().first)

            try Data("corrupt".utf8).write(to: destination.appendingPathComponent(path))
            XCTAssertThrowsError(try plan.verify(at: destination))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: output),
                try MigrationBackupReader.file("Preferences.plist", in: backup.files))
        }
    }


    /// @fcn MigrationStudioTests.testProtectedEditableWorkspaceActivationAndRecovery
    /// @brief Prove coordinated installation, format-two backup, full undo and failed-activation rollback
    /// @return Void after exact preference, file and canonical evidence assertions in isolated containers
    /// @throws Fixture, staging, backup or transaction failures
    func testProtectedEditableWorkspaceActivationAndRecovery() throws
    {
        try fixture(edit: { values in

            var calendar = Calendar(identifier: .gregorian)     /* Date calculation calendar */

            calendar.timeZone = TimeZone(identifier: "America/Chicago")!
            calendar.firstWeekday = 2

            let card =                                                                  /* Synthetic card fixture */
                KanbanCard(id: 1, word: "Imported editable Card", listTitle: "Monday", checklists: [],
                    createdAt: Date(timeIntervalSince1970: 1792843200))
            var week =                                                                  /* Synthetic week fixture */
                DatedPlanningWeek.make(for: Date(timeIntervalSince1970: 1792843200),
                    lists: [KanbanList(id: 1, title: "Monday", cards: [card])], calendar: calendar)

            week.collection.savedCardIDs = [1]
            values["Plenact.SavedCardIDs.v1"] = [1]
            values["Plenact.LibraryImportant.v1"] = try JSONEncoder().encode([
                LibraryImportanceItem(collectionID: week.collection.id, cardID: 1, level: 4)])
            values["Plenact.Board.v1"] = try JSONEncoder().encode(week.collection.lists)
            values["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(
                PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week]))
        }) { backup, url in

            let manager   = FileManager.default                         /* Filesystem or media manager */
            let preview   =                                             /* Converted migration preview */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package   =                                             /* Portable package contents   */
                try MigrationTestPackage.prepare(preview)
            let reviewed  =                                             /* Verified operation input    */
                try PortablePackageReview.review(files: XCTUnwrap(package.fileWrappers?["PortableTestPackage"]))
            let candidate =                                             /* Candidate under validation  */
                try PortableWorkspaceCandidate.prepare(reviewed)
            let base      = url.deletingLastPathComponent()             /* Base value before overrides */
            let stage     =                                             /* Isolated staging workspace  */
                base.appendingPathComponent("ProtectedStage")

            try candidate.stage(at: stage)

            let container =                                                     /* Decoded field container        */
                base.appendingPathComponent("ProtectedContainer")
            let documents =                                                     /* Store document snapshots       */
                container.appendingPathComponent("Documents")
            let support   =                                                     /* Supported operation capability */
                container.appendingPathComponent("Library/Application Support")

            try manager.createDirectory(at: documents, withIntermediateDirectories: true)
            try manager.createDirectory(at: support, withIntermediateDirectories: true)

            let sentinel =                                              /* Sentinel comparison fixture */
                documents.appendingPathComponent("retain-original.txt")

            try Data("Retained original document".utf8).write(to: sentinel)

            let domain   =                                              /* Lookup or storage namespace */
                "Plenact.ProtectedPortable." + UUID().uuidString
            let defaults =                                              /* Preference store under test */
                try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {
                defaults.removePersistentDomain(forName: domain)
            }

            var original =                                              /* Baseline before changes   */
                try MigrationBackupReader.values(in: backup)
            var calendar =                                              /* Date calculation calendar */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(original["Plenact.CalendarWeeks.v1"] as? Data))

            calendar.weeks[0].collection.lists[0].cards[0].word = "Before editable import"
            original["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(calendar)
            original["Plenact.Board.v1"] = try JSONEncoder().encode(calendar.weeks[0].collection.lists)
            original["PlatformSentinel"] = "unchanged"

            defaults.setPersistentDomain(original, forName: domain)

            let transaction =                                                                   /* Transaction comparison fixture */
                FullMonthExampleStore(root: base.appendingPathComponent("ProtectedRecovery"),
                    documents: documents, support: support, domainName: domain)

            try transaction.installPortableWorkspace
            {
                try candidate.install(from: stage, root: container, defaults: defaults, domain: domain)
            }
            XCTAssertTrue(transaction.hasPortableImportBackup)

            let installed =                                     /* Installed workspace state */
                try JSONDecoder().decode([KanbanList].self,
                    from: XCTUnwrap(defaults.data(forKey: "Plenact.Board.v1")))

            XCTAssertEqual(installed.first?.cards.first?.word, "Imported editable Card")
            XCTAssertEqual(defaults.string(forKey: "PlatformSentinel"), "unchanged")
            XCTAssertEqual(try PortableRuntimeEvidence.capture(root: container)["CanonicalPackage.bin"], reviewed.snapshot)

            // Export edits from the real native projection, preserving stable IDs, original files and source bytes
            var editedCalendar =                                        /* Edited calendar */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(defaults.data(forKey: "Plenact.CalendarWeeks.v1")))

            editedCalendar.weeks[0].collection.lists[0].cards[0].startDate = Date(timeIntervalSince1970: 1792933200)
            editedCalendar.weeks[0].collection.lists[0].cards[0].startDateKind = .dateAndTime

            let historyID = UUID()      /* History ID */

            editedCalendar.weeks[0].collection.lists[0].cards[0].descriptionOverride = "An edited description"
            editedCalendar.weeks[0].collection.lists[0].cards[0].word = "Edited portable Card"
            editedCalendar.weeks[0].collection.lists[0].cards[0].editHistory = [CardEditRecord(id: historyID,
                timestamp: Date(timeIntervalSince1970: 1792843200.123456),
                changes: [CardEditChange(field: "descriptionOverride", previousValue: nil, newValue: Data("\"An edited description\"".utf8))])]

            defaults.set(try JSONEncoder().encode(editedCalendar), forKey: "Plenact.CalendarWeeks.v1")
            defaults.set(try JSONEncoder().encode(editedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            let editedBackup  =                                                         /* Edited backup                    */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)
            let editedOutput  = try PortableEditedExport.prepare(editedBackup)          /* Edited output                    */
            let editedPackage =                                                         /* Edited package                   */
                try PortablePackageReview.review(files: XCTUnwrap(editedOutput.fileWrappers?["PortableTestPackage"]))
            let reconstructed =                                                         /* Reconstructed comparison fixture */
                try PortableWorkspaceCandidate.prepare(editedPackage, retainedAliases: candidate.numericIDs)
            let editedLists   = try JSONDecoder().decode([KanbanList].self,             /* Edited lists                     */
                from: XCTUnwrap(reconstructed.values["Plenact.Board.v1"] as? Data))

            XCTAssertEqual(editedLists.first?.cards.first?.startDate, editedCalendar.weeks[0].collection.lists[0].cards[0].startDate)
            XCTAssertEqual(editedLists.first?.cards.first?.startDateKind, .dateAndTime)
            XCTAssertEqual(reconstructed.numericIDs, candidate.numericIDs)
            XCTAssertEqual(editedLists.first?.cards.first?.word, "Edited portable Card")
            XCTAssertEqual(editedLists.first?.cards.first?.descriptionOverride, "An edited description")

            let expectedHistory =                                                       /* Expected history */
                editedCalendar.weeks[0].collection.lists[0].cards[0].editHistory

            XCTAssertEqual(editedLists.first?.cards.first?.editHistory?.map(\.id), expectedHistory?.map(\.id))
            XCTAssertEqual(editedLists.first?.cards.first?.editHistory?.map(\.changes), expectedHistory?.map(\.changes))
            for (actual, expected) in zip(editedLists.first?.cards.first?.editHistory ?? [], expectedHistory ?? [])
            {
                XCTAssertEqual(actual.timestamp.timeIntervalSince1970, expected.timestamp.timeIntervalSince1970, accuracy: 0.001)
            }

            let editedAssembly =                                                                /* Assembly after edits    */
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: editedOutput)
            let attachment     =                                                                /* Synthetic test evidence */
                XCTAttachment(data: editedAssembly, uniformTypeIdentifier: "public.json")

            attachment.name = "EditedPackage-Assembly.json"
            attachment.lifetime = .keepAlways

            add(attachment)

            let manifestAttachment =    /* Manifest attachment */
                XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/Manifest.json", in: editedOutput),
                    uniformTypeIdentifier: "public.json")

            manifestAttachment.name = "EditedPackage-Manifest.json"
            manifestAttachment.lifetime = .keepAlways

            add(manifestAttachment)

            let originals =                                                             /* Retained original files      */
                try XCTUnwrap(editedOutput.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let blobs     =                                                             /* Verified original file blobs */
                try Dictionary(uniqueKeysWithValues: originals.map { name, file in
                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let blobsAttachment =       /* Blobs attachment */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: blobs, options: .sortedKeys),
                    uniformTypeIdentifier: "public.json")

            blobsAttachment.name = "EditedPackage-Blobs.json"
            blobsAttachment.lifetime = .keepAlways

            add(blobsAttachment)
            XCTAssertEqual(reconstructed.media.files, candidate.media.files)
            XCTAssertEqual(try PortableRuntimeEvidence.capture(root: container)["CanonicalPackage.bin"], reviewed.snapshot)
            XCTAssertNotNil(editedOutput.fileWrappers?["EditedNativeBackup"])
            // A stale duplicated Board copy must fail rather than overwrite the edited calendar Card
            defaults.set(candidate.values["Plenact.Board.v1"], forKey: "Plenact.Board.v1")

            let staleBackup =           /* Stale backup */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)

            XCTAssertThrowsError(try PortableEditedExport.prepare(staleBackup))
            defaults.set(try JSONEncoder().encode(editedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            // Explicit removal and completion are distinct from retaining the old text
            var cleared = editedCalendar        /* Value after clearing choices */

            cleared.weeks[0].collection.lists[0].cards[0].descriptionOverride = nil
            cleared.weeks[0].collection.lists[0].cards[0].isTitleChecked = true

            defaults.set(try JSONEncoder().encode(cleared), forKey: "Plenact.CalendarWeeks.v1")
            defaults.set(try JSONEncoder().encode(cleared.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            let clearedBackup    =                                                      /* Cleared backup    */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)
            let clearedOutput    =                                                      /* Cleared output    */
                try PortableEditedExport.prepare(clearedBackup)
            let clearedPackage   =                                                      /* Cleared package   */
                try PortablePackageReview.review(files: XCTUnwrap(clearedOutput.fileWrappers?["PortableTestPackage"]))
            let clearedCandidate =                                                      /* Cleared candidate */
                try PortableWorkspaceCandidate.prepare(clearedPackage, retainedAliases: candidate.numericIDs)
            let clearedLists     = try JSONDecoder().decode([KanbanList].self,          /* Cleared lists     */
                from: XCTUnwrap(clearedCandidate.values["Plenact.Board.v1"] as? Data))

            XCTAssertNil(clearedLists.first?.cards.first?.descriptionOverride)
            XCTAssertEqual(clearedLists.first?.cards.first?.isTitleChecked, true)
            defaults.set(try JSONEncoder().encode(editedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            // A deleted Card stays retained canonically but is absent from both editable partitions
            var deletedCalendar = editedCalendar                                                /* Deleted calendar */
            let deletedNumber   =                                                               /* Deleted number   */
                try XCTUnwrap(deletedCalendar.weeks[0].collection.lists[0].cards.first?.id)

            deletedCalendar.weeks[0].collection.lists[0].cards = []

            deletedCalendar.weeks[0].collection.savedCardIDs.remove(deletedNumber)
            defaults.set(try JSONEncoder().encode(deletedCalendar), forKey: "Plenact.CalendarWeeks.v1")
            defaults.set(try JSONEncoder().encode(deletedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")
            defaults.set([], forKey: "Plenact.SavedCardIDs.v1")

            let deletedBackup =                                                         /* Deleted backup */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)
            let deletedOutput = try PortableEditedExport.prepare(deletedBackup)         /* Deleted output */
            let deletedReview =                                                         /* Deleted review */
                try PortablePackageReview.review(files: XCTUnwrap(deletedOutput.fileWrappers?["PortableTestPackage"]))

            XCTAssertEqual(deletedReview.cardCount, 0)

            let deletedCandidate =                                                      /* Deleted candidate */
                try PortableWorkspaceCandidate.prepare(deletedReview, retainedAliases: candidate.numericIDs)
            let deletedLists     = try JSONDecoder().decode([KanbanList].self,          /* Deleted lists     */
                from: XCTUnwrap(deletedCandidate.values["Plenact.Board.v1"] as? Data))

            XCTAssertTrue(deletedLists.allSatisfy { $0.cards.isEmpty && $0.archivedCards.isEmpty })
            XCTAssertEqual(deletedCandidate.numericIDs, candidate.numericIDs)
            XCTAssertEqual(deletedCandidate.media.files, candidate.media.files)
            XCTAssertEqual(deletedCandidate.values["Plenact.SavedCardIDs.v1"] as? [Int], [])

            let retainedImportance =                                    /* Retained importance */
                try JSONDecoder().decode([LibraryImportanceItem].self,
                    from: XCTUnwrap(deletedCandidate.values["Plenact.LibraryImportant.v1"] as? Data))

            XCTAssertEqual(retainedImportance.first?.resolvedLevel, 4)

            let deletedAssembly =                                                       /* Deleted assembly */
                try XCTUnwrap(JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: deletedOutput)) as? [String: Any])
            let deletedExport =                                                         /* Deleted export   */
                try XCTUnwrap(deletedAssembly["workspace_export"] as? [String: Any])

            XCTAssertEqual(try PortableLocalDeletions.ids(in: deletedExport).count, 1)

            let deletionStage = base.appendingPathComponent("DeletionReimport")         /* Deletion stage */

            try deletedCandidate.stage(at: deletionStage)

            // Reconstructing/importing a deletion must not resurrect it on the next export
            let deletionDomain   =                                      /* Deletion domain   */
                "Plenact.DeletedReimport." + UUID().uuidString
            let deletionDefaults =                                      /* Deletion defaults */
                try XCTUnwrap(UserDefaults(suiteName: deletionDomain))

            defer { deletionDefaults.removePersistentDomain(forName: deletionDomain) }

            let deletionContainer =                                     /* Deletion container */
                base.appendingPathComponent("DeletionContainer")

            try deletedCandidate.install(from: deletionStage, root: deletionContainer,
                defaults: deletionDefaults, domain: deletionDomain)

            let repeatedDeletionBackup =                                        /* Repeated deletion backup */
                try LegacyWorkspaceExport.capture(defaults: deletionDefaults, domain: deletionDomain, root: deletionContainer)
            let repeatedDeletion       =                                        /* Repeated deletion        */
                try PortableEditedExport.prepare(repeatedDeletionBackup)

            XCTAssertEqual(try PortablePackageReview.review(files: XCTUnwrap(repeatedDeletion.fileWrappers?["PortableTestPackage"])).cardCount, 0)
            for name in ["Assembly.json", "Manifest.json"]
            {
                let deletionAttachment =        /* Deletion attachment */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: deletedOutput), uniformTypeIdentifier: "public.json")

                deletionAttachment.name = "DeletedPackage-" + name
                deletionAttachment.lifetime = .keepAlways

                add(deletionAttachment)
            }

            let deletionBlobs =         /* Deletion blobs */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: blobs, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            deletionBlobs.name = "DeletedPackage-Blobs.json"
            deletionBlobs.lifetime = .keepAlways

            add(deletionBlobs)
            defaults.set(candidate.values["Plenact.SavedCardIDs.v1"], forKey: "Plenact.SavedCardIDs.v1")
            defaults.set(try JSONEncoder().encode(editedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            // Reserve new identities durably, then create, move and reorder within one existing owner
            let firstReserved =                                                                 /* First reserved */
                try PortableCreationIdentity.reserve(proposed: 1, count: 2, root: container)
            let reservedAgain =                                                                 /* Reserved again */
                try PortableCreationIdentity.reserve(proposed: 1, root: container)

            XCTAssertGreaterThan(reservedAgain, firstReserved + 1)

            var structuralCalendar = editedCalendar                                             /* Structural calendar */
            let originalList       =                                                            /* Original list       */
                structuralCalendar.weeks[0].collection.lists[0]
            let moved              =                                                            /* Item after transfer */
                try XCTUnwrap(originalList.cards.first).replacingLocation(id: deletedNumber, listTitle: "New structural List")
            var created            =                                                            /* Newly created value */
                originalList.makeItem(id: firstReserved + 1, title: "New structural Card",
                    createdAt: Date(timeIntervalSince1970: 1793000000.123456), creationPreferences: LocalProfilePreferences())
                .replacingLocation(id: firstReserved + 1, listTitle: "New structural List")

            XCTAssertFalse(created.checklists.isEmpty)

            let photoBytes =                                                                    /* Photo bytes */
                try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII="))
            let photoPath  =                                                                    /* Photo path  */
                container.appendingPathComponent("Documents/CardAttachments/rich-photo.png")

            try manager.createDirectory(at: photoPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try photoBytes.write(to: photoPath)

            let attachmentID = UUID()           /* Attachment ID */

            created.attachments = [KanbanAttachment(id: attachmentID, fileName: "rich-photo.png", mediaKind: .photo,
                addedAt: Date(timeIntervalSince1970: 1793000000.654321), caption: "Exact photo caption")]
            created.coverAttachmentID = attachmentID
            created.comments = [KanbanComment(author: "Synthetic author", body: "Exact rich comment",
                createdAt: Date(timeIntervalSince1970: 1793000000.987654))]

            created.checklists.append(KanbanChecklist(title: "Additional checklist", items: ["One", "Two", "Three"], completed: 2))

            created.isTitleChecked = true
            created.descriptionOverride = "Rich Card description"
            created.editHistory = [CardEditRecord(id: UUID(), timestamp: Date(timeIntervalSince1970: 1793000001.456789),
                changes: [CardEditChange(field: "descriptionOverride", previousValue: nil,
                    newValue: Data("\"Rich Card description\"".utf8))])]

            let oldImportance =                                         /* Old importance */
                try JSONDecoder().decode([LibraryImportanceItem].self,
                    from: XCTUnwrap(candidate.values["Plenact.LibraryImportant.v1"] as? Data))

            defaults.set(try JSONEncoder().encode(oldImportance + [LibraryImportanceItem(
                collectionID: structuralCalendar.weeks[0].collection.id, cardID: created.id, level: nil)]),
                forKey: "Plenact.LibraryImportant.v1")
            structuralCalendar.weeks[0].collection.savedCardIDs.insert(created.id)
            defaults.set(structuralCalendar.weeks[0].collection.savedCardIDs.sorted(), forKey: "Plenact.SavedCardIDs.v1")

            var emptyOriginal = originalList    /* Empty original */

            emptyOriginal.cards = []

            let addedList =                                                                             /* Added list */
                KanbanList(id: firstReserved, title: "New structural List", cards: [created, moved])

            structuralCalendar.weeks[0].collection.lists = [addedList] + Array(editedCalendar.weeks[0].collection.lists.dropFirst()) + [emptyOriginal]

            defaults.set(try JSONEncoder().encode(structuralCalendar), forKey: "Plenact.CalendarWeeks.v1")
            defaults.set(try JSONEncoder().encode(structuralCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            let structuralBackup       =                                        /* Structural backup        */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)
            let structuralOutput       =                                        /* Structural output        */
                try PortableEditedExport.prepare(structuralBackup)
            let protectedPath          =                                        /* Protected path           */
                try XCTUnwrap(candidate.media.files.keys.sorted().first)
            let originalProtectedBytes =                                        /* Original protected bytes */
                try XCTUnwrap(candidate.media.files[protectedPath])

            try Data("changed original".utf8).write(to: container.appendingPathComponent(protectedPath))

            let modifiedOriginalBackup =        /* Modified original backup */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)

            XCTAssertThrowsError(try PortableEditedExport.prepare(modifiedOriginalBackup))
            try originalProtectedBytes.write(to: container.appendingPathComponent(protectedPath))

            let repeatedStructuralOutput =                              /* Repeated structural output */
                try PortableEditedExport.prepare(structuralBackup)

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: structuralOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: repeatedStructuralOutput))

            let structuralReview =      /* Structural review */
                try PortablePackageReview.review(files: XCTUnwrap(structuralOutput.fileWrappers?["PortableTestPackage"]))

            XCTAssertEqual(structuralReview.cardCount, 2)

            let runtime             =                                           /* Retained import evidence */
                try PortableRuntimeEvidence.capture(root: container)
            let reservedAliases     =                                           /* Reserved aliases         */
                try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(runtime["IdentityAliases.json"])) as? [String: Any])
            let expandedAliases     =                                           /* Expanded aliases         */
                try XCTUnwrap(reservedAliases["numeric_ids"] as? [String: Int])
            let structuralCandidate =                                           /* Structural candidate     */
                try PortableWorkspaceCandidate.prepare(structuralReview, retainedAliases: expandedAliases)
            let anyAsset            =                                           /* Any asset                */
                try XCTUnwrap(structuralCandidate.media.filenames.keys.first)

            XCTAssertThrowsError(try PortableWorkspaceCandidate.prepare(structuralReview, retainedAliases: expandedAliases,
                mediaFilenames: [anyAsset: "../unsafe.png"]))

            let structuralLists = try JSONDecoder().decode([KanbanList].self,                   /* Structural lists */
                from: XCTUnwrap(structuralCandidate.values["Plenact.Board.v1"] as? Data))

            XCTAssertEqual(structuralLists.map(\.id), [firstReserved] + editedCalendar.weeks[0].collection.lists.dropFirst().map(\.id) + [originalList.id])
            XCTAssertEqual(structuralLists.first?.cards.map(\.id), [firstReserved + 1, deletedNumber])
            XCTAssertEqual(structuralLists.first?.cards.last?.word, moved.word)
            XCTAssertEqual(structuralCandidate.numericIDs, expandedAliases)

            let restoredRich = try XCTUnwrap(structuralLists.first?.cards.first)        /* Restored rich */

            XCTAssertEqual(restoredRich.comments.first?.id, created.comments.first?.id)
            XCTAssertEqual(restoredRich.comments.first?.body, "Exact rich comment")
            XCTAssertEqual(restoredRich.attachments?.first?.id, attachmentID)
            XCTAssertEqual(restoredRich.attachments?.first?.caption, "Exact photo caption")
            XCTAssertEqual(restoredRich.coverAttachmentID, attachmentID)
            XCTAssertEqual(restoredRich.checklists, created.checklists)
            XCTAssertEqual(restoredRich.editHistory?.map(\.id), created.editHistory?.map(\.id))
            XCTAssertEqual(restoredRich.editHistory?.map(\.changes), created.editHistory?.map(\.changes))
            XCTAssertTrue(restoredRich.isTitleChecked)
            XCTAssertTrue((structuralCandidate.values["Plenact.SavedCardIDs.v1"] as? [Int] ?? []).contains(created.id))

            let restoredFile =                                                  /* Restored file */
                try XCTUnwrap(restoredRich.attachments?.first?.fileName)

            XCTAssertEqual(structuralCandidate.media.files["Documents/CardAttachments/" + restoredFile], photoBytes)

            let structuralStage =                               /* Structural stage */
                base.appendingPathComponent("StructuralStage")

            try structuralCandidate.stage(at: structuralStage)

            let structuralContainer =                                           /* Structural container */
                base.appendingPathComponent("StructuralReimport")
            let structuralDomain    =                                           /* Structural domain    */
                "Plenact.StructuralReimport." + UUID().uuidString
            let structuralDefaults  =                                           /* Structural defaults  */
                try XCTUnwrap(UserDefaults(suiteName: structuralDomain))

            defer
            {
                structuralDefaults.removePersistentDomain(forName: structuralDomain)
            }
            try structuralCandidate.install(from: structuralStage, root: structuralContainer,
                defaults: structuralDefaults, domain: structuralDomain)

            let reimportedBackup     =                                  /* Reimported backup     */
                try LegacyWorkspaceExport.capture(defaults: structuralDefaults, domain: structuralDomain, root: structuralContainer)
            let reexportedStructural =                                  /* Reexported structural */
                try PortableEditedExport.prepare(reimportedBackup)

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: structuralOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: reexportedStructural))

            // Edit the rich Card after import: preserve its existing identity and untouched canonical fields
            var importedCalendar =                                                                      /* Imported calendar */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(structuralDefaults.data(forKey: "Plenact.CalendarWeeks.v1")))
            let originalImported =                                                                      /* Original imported */
                importedCalendar.weeks[0].collection.lists[0].cards[0]
            var editedImported   = originalImported                                                     /* Edited imported   */
            let firstComment     = try XCTUnwrap(editedImported.comments.first)                         /* First comment     */

            editedImported.comments[0] = KanbanComment(id: firstComment.id, author: firstComment.author,
                body: "Updated existing comment", createdAt: firstComment.createdAt)

            editedImported.comments.append(KanbanComment(author: "Another synthetic author", body: "Added after import",
                createdAt: Date(timeIntervalSince1970: 1793001000.123456)))

            let originalChecklist = editedImported.checklists[0]        /* Original checklist */
            var changedItems      = originalChecklist.items             /* Changed items      */

            changedItems[0].isCompleted.toggle()

            editedImported.checklists[0] = KanbanChecklist(id: originalChecklist.id, title: originalChecklist.title, items: changedItems)

            editedImported.checklists.append(KanbanChecklist(title: "Imported linked checklist", items: [
                KanbanChecklistItem(title: "Existing target", content: .linkedCard(cardID: deletedNumber))]))

            editedImported.attachments?[0].caption = "Updated imported caption"

            let secondAttachment =                                                      /* Second attachment */
                KanbanAttachment(fileName: "second-photo.png", mediaKind: .photo,
                    addedAt: Date(timeIntervalSince1970: 1793001000.654321), caption: "Second original")

            editedImported.attachments?.append(secondAttachment)

            editedImported.coverAttachmentID = secondAttachment.id

            let secondPath =    /* Second path */
                structuralContainer.appendingPathComponent("Documents/CardAttachments/second-photo.png")

            try photoBytes.write(to: secondPath)

            editedImported.members = [.manual("Synthetic member")]

            let reactionAuthor = UUID()         /* Reaction author */

            editedImported.reactions = [ItemEmojiReaction(emoji: "👍", authorID: reactionAuthor,
                createdAt: Date(timeIntervalSince1970: 1793001000.987654))]

            structuralDefaults.set(reactionAuthor.uuidString, forKey: "Plenact.LocalReactionAuthor.v1")

            var editedAppearance =                              /* Edited appearance */
                editedImported.appearance ?? ItemAppearance()

            editedAppearance.subtitleItalic = true
            editedAppearance.listBackgroundOpacity = 0.42
            editedImported.appearance = editedAppearance
            importedCalendar.weeks[0].collection.lists[0].cards[0] = editedImported

            structuralDefaults.set(try JSONEncoder().encode(importedCalendar), forKey: "Plenact.CalendarWeeks.v1")
            structuralDefaults.set(try JSONEncoder().encode(importedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            let existingBackup =                                        /* Existing backup */
                try LegacyWorkspaceExport.capture(defaults: structuralDefaults, domain: structuralDomain, root: structuralContainer)
            let existingOutput =                                        /* Existing output */
                try PortableEditedExport.prepare(existingBackup)
            let existingAgain  =                                        /* Existing again  */
                try PortableEditedExport.prepare(existingBackup)

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: existingOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: existingAgain))

            let existingReview    =                                                     /* Existing review    */
                try PortablePackageReview.review(files: XCTUnwrap(existingOutput.fileWrappers?["PortableTestPackage"]))
            let existingCandidate =                                                     /* Existing candidate */
                try PortableWorkspaceCandidate.prepare(existingReview, retainedAliases: expandedAliases)
            let existingLists     = try JSONDecoder().decode([KanbanList].self,         /* Existing lists     */
                from: XCTUnwrap(existingCandidate.values["Plenact.Board.v1"] as? Data))
            let afterExisting = try XCTUnwrap(existingLists.first?.cards.first)         /* After existing     */

            XCTAssertEqual(afterExisting.id, originalImported.id)
            XCTAssertEqual(afterExisting.comments.first?.id, originalImported.comments.first?.id)
            XCTAssertEqual(afterExisting.comments.map(\.body), ["Updated existing comment", "Added after import"])
            XCTAssertEqual(afterExisting.checklists, importedCalendar.weeks[0].collection.lists[0].cards[0].checklists)
            XCTAssertEqual(afterExisting.attachments?.first?.id, originalImported.attachments?.first?.id)
            XCTAssertEqual(afterExisting.attachments?.first?.caption, "Updated imported caption")
            XCTAssertEqual(afterExisting.attachments?.count, 2)
            XCTAssertEqual(afterExisting.coverAttachmentID, secondAttachment.id)
            XCTAssertEqual(afterExisting.members, editedImported.members)
            XCTAssertEqual(afterExisting.reactions?.map(\.id), editedImported.reactions?.map(\.id))
            XCTAssertEqual(afterExisting.reactions?.first?.authorID, reactionAuthor)
            XCTAssertEqual(afterExisting.appearance, editedAppearance)
            XCTAssertEqual(afterExisting.editHistory?.map(\.id), importedCalendar.weeks[0].collection.lists[0].cards[0].editHistory?.map(\.id))

            let sourceAssembly =                                        /* Source assembly  */
                try XCTUnwrap(JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: structuralOutput)) as? [String: Any])
            let revisedAssembly =                                       /* Revised assembly */
                try XCTUnwrap(JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: existingOutput)) as? [String: Any])
            let sourceExport  =                                         /* Source export    */
                sourceAssembly["workspace_export"] as! [String: Any]
            let revisedExport =                                         /* Revised export   */
                revisedAssembly["workspace_export"] as! [String: Any]
            let sourceCards   =                                         /* Source cards     */
                ((sourceExport["base_workspace"] as! [String: Any])["planning"] as! [String: Any])["content"] as! [String: Any]
            let revisedCards  =                                         /* Revised cards    */
                ((revisedExport["base_workspace"] as! [String: Any])["planning"] as! [String: Any])["content"] as! [String: Any]

            XCTAssertEqual((sourceCards["cards"] as! [[String: Any]]).map { $0["id"] as! String },
                (revisedCards["cards"] as! [[String: Any]]).map { $0["id"] as! String })

            let beforeRecords             =                     /* Before records */
                sourceCards["cards"] as! [[String: Any]]
            let afterRecords              =                     /* After records  */
                revisedCards["cards"] as! [[String: Any]]
            let richID                    =                     /* Rich ID        */
                try XCTUnwrap(expandedAliases.first(where: { $0.value == originalImported.id })?.key)
            let oldPayload                =                     /* Old payload    */
                try XCTUnwrap(beforeRecords.first(where: { $0["id"] as? String == richID })?["payload"] as? [String: Any])
            let newPayload                =                     /* New payload    */
                try XCTUnwrap(afterRecords.first(where: { $0["id"] as? String == richID })?["payload"] as? [String: Any])
            let editedFields: Set<String> =                     /* Edited fields  */
                ["comments", "checklists", "attachments", "cover_attachment_id", "members", "reactions", "appearance", "edit_history"]

            for key in Set(oldPayload.keys).subtracting(editedFields)
            {
                XCTAssertTrue(NSDictionary(dictionary: ["value": oldPayload[key]!]).isEqual(to: ["value": newPayload[key]!]))
            }

            let existingStage =                                         /* Existing stage */
                base.appendingPathComponent("ExistingCardStage")

            try existingCandidate.stage(at: existingStage)

            let existingContainer =                                     /* Existing container */
                base.appendingPathComponent("ExistingCardReimport")
            let existingDomain    =                                     /* Existing domain    */
                "Plenact.ExistingCardReimport." + UUID().uuidString
            let existingDefaults  =                                     /* Existing defaults  */
                try XCTUnwrap(UserDefaults(suiteName: existingDomain))

            defer
            {
                existingDefaults.removePersistentDomain(forName: existingDomain)
            }
            try existingCandidate.install(from: existingStage, root: existingContainer, defaults: existingDefaults, domain: existingDomain)

            let existingReimportBackup =                                        /* Existing reimport backup */
                try LegacyWorkspaceExport.capture(defaults: existingDefaults, domain: existingDomain, root: existingContainer)
            let existingReexport       =                                        /* Existing reexport        */
                try PortableEditedExport.prepare(existingReimportBackup)

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: existingOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: existingReexport))
            for name in ["Assembly.json", "Manifest.json"]
            {
                let item =      /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: existingOutput), uniformTypeIdentifier: "public.json")

                item.name = "ExistingCardPackage-" + name
                item.lifetime = .keepAlways

                add(item)
            }

            let existingOriginals =                                                             /* Existing originals */
                try XCTUnwrap(existingOutput.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let existingBlobs     =                                                             /* Existing blobs     */
                try Dictionary(uniqueKeysWithValues: existingOriginals.map { name, file in
                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let existingBlobAttachment =        /* Existing blob attachment */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: existingBlobs, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            existingBlobAttachment.name = "ExistingCardPackage-Blobs.json"
            existingBlobAttachment.lifetime = .keepAlways

            add(existingBlobAttachment)

            // Existing List metadata must retain identities and survive a fresh native projection
            var listCalendar = importedCalendar         /* List calendar */

            listCalendar.weeks[0].collection.title = "Renamed portable Collection"
            listCalendar.weeks[0].collection.collectionDescription = "Updated collection description"
            listCalendar.weeks[0].collection.boardAppearance = BoardAppearance(bannerBackground: .teal, subtitleItalic: true)

            try listCalendar.weeks[0].collection.lists[0].edit(title: "Renamed portable List", subtitle: "  Authored subtitle  ")

            listCalendar.weeks[0].collection.lists[0].newItemPresentation = .note
            listCalendar.weeks[0].collection.lists[0].appearance = ItemAppearance(accent: .rose,
                studioSurface: StudioSurface(material: .gradient), subtitleItalic: true)

            structuralDefaults.set(try JSONEncoder().encode(listCalendar), forKey: "Plenact.CalendarWeeks.v1")
            structuralDefaults.set(try JSONEncoder().encode(listCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            let listBackup            =                                                                 /* List backup             */
                try LegacyWorkspaceExport.capture(defaults: structuralDefaults, domain: structuralDomain, root: structuralContainer)
            let listOutput            =                                                                 /* List output             */
                try PortableEditedExport.prepare(listBackup)
            let listReview            =                                                                 /* List review             */
                try PortablePackageReview.review(files: XCTUnwrap(listOutput.fileWrappers?["PortableTestPackage"]))
            let listCandidate         =                                                                 /* List candidate          */
                try PortableWorkspaceCandidate.prepare(listReview, retainedAliases: expandedAliases)
            let restoredOwnerCalendar =                                                                 /* Restored owner calendar */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(listCandidate.values["Plenact.CalendarWeeks.v1"] as? Data))

            XCTAssertEqual(restoredOwnerCalendar.weeks[0].collection.title, listCalendar.weeks[0].collection.title)
            XCTAssertEqual(restoredOwnerCalendar.weeks[0].collection.collectionDescription, "Updated collection description")
            XCTAssertEqual(restoredOwnerCalendar.weeks[0].collection.boardAppearance, listCalendar.weeks[0].collection.boardAppearance)

            let listBoard = try JSONDecoder().decode([KanbanList].self,                 /* List board */
                from: XCTUnwrap(listCandidate.values["Plenact.Board.v1"] as? Data))

            XCTAssertEqual(listBoard[0].id, listCalendar.weeks[0].collection.lists[0].id)
            XCTAssertEqual(listBoard[0].title, "Renamed portable List")
            XCTAssertEqual(listBoard[0].subtitleOverride, listCalendar.weeks[0].collection.lists[0].subtitleOverride)
            XCTAssertEqual(listBoard[0].newItemPresentation, .note)
            XCTAssertEqual(listBoard[0].appearance, listCalendar.weeks[0].collection.lists[0].appearance)
            XCTAssertEqual(listBoard[0].cards.map(\.id), listCalendar.weeks[0].collection.lists[0].cards.map(\.id))
            for name in ["Assembly.json", "Manifest.json"]
            {
                let item =      /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: listOutput), uniformTypeIdentifier: "public.json")

                item.name = "ExistingListPackage-" + name
                item.lifetime = .keepAlways

                add(item)
            }

            let listBlobAttachment =    /* List blob attachment */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: existingBlobs, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            listBlobAttachment.name = "ExistingListPackage-Blobs.json"
            listBlobAttachment.lifetime = .keepAlways

            add(listBlobAttachment)

            let listStage = base.appendingPathComponent("ExistingListStage")    /* List stage */

            try listCandidate.stage(at: listStage)
            try listCandidate.install(from: listStage, root: existingContainer, defaults: existingDefaults, domain: existingDomain)

            let listReexport =                                                  /* List reexport */
                try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: existingDefaults, domain: existingDomain, root: existingContainer))

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: listOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: listReexport))

            var changedPreferences =                                    /* Changed preferences */
                try JSONDecoder().decode(LocalProfilePreferences.self,
                    from: XCTUnwrap(existingDefaults.data(forKey: "Plenact.PlanPreferences.v1")))

            changedPreferences.usesReducedContent.toggle()

            changedPreferences.todayFocusItemCount = 7

            existingDefaults.set(try JSONEncoder().encode(changedPreferences), forKey: "Plenact.PlanPreferences.v1")
            if let profileBytes = existingDefaults.data(forKey: "Plenact.LocalProfile.v1")
            {
                var profile =                                                           /* Synthetic profile fixture */
                    try JSONDecoder().decode(LocalProfile.self, from: profileBytes)

                profile.preferences = changedPreferences

                existingDefaults.set(try JSONEncoder().encode(profile), forKey: "Plenact.LocalProfile.v1")
            }

            let preferencesOutput =                                                                     /* Preferences output    */
                try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: existingDefaults, domain: existingDomain, root: existingContainer))
            let preferencesCandidate =                                                                  /* Preferences candidate */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(preferencesOutput.fileWrappers?["PortableTestPackage"])), retainedAliases: expandedAliases)

            XCTAssertEqual(try JSONDecoder().decode(LocalProfilePreferences.self,
                from: XCTUnwrap(preferencesCandidate.values["Plenact.PlanPreferences.v1"] as? Data)), changedPreferences)

            let preferencesStage =                              /* Preferences stage */
                base.appendingPathComponent("PreferencesStage")

            try preferencesCandidate.stage(at: preferencesStage)
            try preferencesCandidate.install(from: preferencesStage, root: existingContainer,
                defaults: existingDefaults, domain: existingDomain)

            let preferencesReexport =                                           /* Preferences reexport */
                try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: existingDefaults, domain: existingDomain, root: existingContainer))

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: preferencesOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: preferencesReexport))
            for name in ["Assembly.json", "Manifest.json"]
            {
                let item =      /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: preferencesOutput), uniformTypeIdentifier: "public.json")

                item.name = "PreferencesPackage-" + name
                item.lifetime = .keepAlways

                add(item)
            }

            let preferencesBlobs =      /* Preferences blobs */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: existingBlobs, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            preferencesBlobs.name = "PreferencesPackage-Blobs.json"
            preferencesBlobs.lifetime = .keepAlways

            add(preferencesBlobs)
            for path in ["Documents/ProfileAvatars/synthetic-avatar.png",
                "Library/Application Support/PlenactStudioArtwork/synthetic-wall.png"]
            {
                let target =                                            /* Target under consideration */
                    existingContainer.appendingPathComponent(path)

                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try photoBytes.write(to: target)
            }

            let profileForExport =                                                      /* Profile for export */
                LocalProfile(createdAt: Date(timeIntervalSince1970: 1793600000),
                    displayName: "Synthetic profile", email: "profile@example.test", context: "Personal workspace",
                    avatarPhotoFileName: "synthetic-avatar.png", preferences: changedPreferences)

            existingDefaults.set(try JSONEncoder().encode(profileForExport), forKey: "Plenact.LocalProfile.v1")

            var studioForExport =                               /* Studio for export */
                try JSONDecoder().decode(StudioSettings.self,
                    from: XCTUnwrap(existingDefaults.data(forKey: "Plenact.Studio.Settings.v1")))

            studioForExport.variesNewHeaders.toggle()

            studioForExport.views["Today"] = StudioSurface(material: .photo, color: "A1B2C3", strength: 0.4,
                photoFileName: "synthetic-wall.png")

            existingDefaults.set(try JSONEncoder().encode(studioForExport), forKey: "Plenact.Studio.Settings.v1")

            var artForExport = try JSONDecoder().decode([StudioArtwork].self,                   /* Art for export */
                from: XCTUnwrap(existingDefaults.data(forKey: "Plenact.Studio.Artwork.v1")))

            artForExport.append(StudioArtwork(name: "New synthetic look", surface: StudioSurface(material: .linen)))
            artForExport.reverse()
            existingDefaults.set(try JSONEncoder().encode(artForExport), forKey: "Plenact.Studio.Artwork.v1")

            let weekForExport =                                                 /* Week for export */
                BoardAppearance(bannerBackground: .teal, subtitleItalic: true)

            existingDefaults.set(try JSONEncoder().encode(weekForExport), forKey: "Plenact.WeekAppearance.v1")

            let personalBackup    =                                                             /* Personal backup    */
                try LegacyWorkspaceExport.capture(defaults: existingDefaults, domain: existingDomain, root: existingContainer)
            let personalOutput    =                                                             /* Personal output    */
                try PortableEditedExport.prepare(personalBackup)
            let personalCandidate =                                                             /* Personal candidate */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(personalOutput.fileWrappers?["PortableTestPackage"])))
            let restoredProfile = try JSONDecoder().decode(LocalProfile.self,                   /* Restored profile   */
                from: XCTUnwrap(personalCandidate.values["Plenact.LocalProfile.v1"] as? Data))

            XCTAssertEqual(restoredProfile.id, profileForExport.id)
            XCTAssertEqual(restoredProfile.displayName, profileForExport.displayName)

            let restoredStudio = try JSONDecoder().decode(StudioSettings.self,                          /* Restored studio */
                from: XCTUnwrap(personalCandidate.values["Plenact.Studio.Settings.v1"] as? Data))

            studioForExport.views["Today"]?.photoFileName = restoredStudio.views["Today"]?.photoFileName

            XCTAssertEqual(restoredStudio, studioForExport)
            XCTAssertEqual(personalCandidate.media.files["Documents/ProfileAvatars/" + (restoredProfile.avatarPhotoFileName ?? "missing")], photoBytes)
            XCTAssertEqual(personalCandidate.media.files["Library/Application Support/PlenactStudioArtwork/" + (restoredStudio.views["Today"]?.photoFileName ?? "missing")], photoBytes)
            XCTAssertEqual(try JSONDecoder().decode([StudioArtwork].self,
                from: XCTUnwrap(personalCandidate.values["Plenact.Studio.Artwork.v1"] as? Data)), artForExport)
            XCTAssertEqual(try JSONDecoder().decode(BoardAppearance.self,
                from: XCTUnwrap(personalCandidate.values["Plenact.WeekAppearance.v1"] as? Data)), weekForExport)

            let personalStage =                                         /* Personal stage */
                base.appendingPathComponent("PersonalizationStage")

            try personalCandidate.stage(at: personalStage)
            try personalCandidate.install(from: personalStage, root: existingContainer,
                defaults: existingDefaults, domain: existingDomain)

            let personalReexport =                                              /* Personal reexport */
                try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: existingDefaults, domain: existingDomain, root: existingContainer))

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: personalOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: personalReexport))
            for name in ["Assembly.json", "Manifest.json"]
            {
                let item =      /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: personalOutput), uniformTypeIdentifier: "public.json")

                item.name = "PersonalizationPackage-" + name
                item.lifetime = .keepAlways

                add(item)
            }

            let personalOriginals  =                                                            /* Personal originals   */
                try XCTUnwrap(personalOutput.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let personalBlobValues =                                                            /* Personal blob values */
                try Dictionary(uniqueKeysWithValues: personalOriginals.map { name, file in
                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let personalBlobs =         /* Personal blobs */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: personalBlobValues, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            personalBlobs.name = "PersonalizationPackage-Blobs.json"
            personalBlobs.lifetime = .keepAlways

            add(personalBlobs)

            var revisedProfile = restoredProfile        /* Revised profile */

            revisedProfile.displayName = "Revised synthetic profile"
            revisedProfile.context = ""
            revisedProfile.avatarPhotoFileName = nil

            existingDefaults.set(try JSONEncoder().encode(revisedProfile), forKey: "Plenact.LocalProfile.v1")

            var clearedStudio = studioForExport         /* Cleared studio */

            clearedStudio.views.removeValue(forKey: "Today")
            existingDefaults.set(try JSONEncoder().encode(clearedStudio), forKey: "Plenact.Studio.Settings.v1")
            existingDefaults.set(try JSONEncoder().encode([StudioArtwork]()), forKey: "Plenact.Studio.Artwork.v1")

            let clearPersonalOutput =                                                                   /* Clear personal output    */
                try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: existingDefaults, domain: existingDomain, root: existingContainer))
            let clearPersonalCandidate =                                                                /* Clear personal candidate */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(clearPersonalOutput.fileWrappers?["PortableTestPackage"])))
            let clearProfile = try JSONDecoder().decode(LocalProfile.self,                              /* Clear profile            */
                from: XCTUnwrap(clearPersonalCandidate.values["Plenact.LocalProfile.v1"] as? Data))

            XCTAssertEqual(clearProfile.id, restoredProfile.id)
            XCTAssertEqual(clearProfile.displayName, revisedProfile.displayName)
            XCTAssertNil(clearProfile.avatarPhotoFileName)
            XCTAssertEqual(try JSONDecoder().decode([StudioArtwork].self,
                from: XCTUnwrap(clearPersonalCandidate.values["Plenact.Studio.Artwork.v1"] as? Data)).count, 0)
            XCTAssertNil(try JSONDecoder().decode(StudioSettings.self,
                from: XCTUnwrap(clearPersonalCandidate.values["Plenact.Studio.Settings.v1"] as? Data)).views["Today"])
            try personalCandidate.install(from: personalStage, root: existingContainer,
                defaults: existingDefaults, domain: existingDomain)

            var rolloverCalendar =                                                              /* Rollover calendar */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(existingDefaults.data(forKey: "Plenact.CalendarWeeks.v1")))
            let rolloverDate =                                                                  /* Rollover date     */
                try XCTUnwrap(PlanningDate.date(rolloverCalendar.currentWeekKey, calendar: rolloverCalendar.calendar))
                .addingTimeInterval(7 * 86400)
            var newWeek      =                                                                  /* New week          */
                DatedPlanningWeek.make(for: rolloverDate, calendar: rolloverCalendar.calendar)
            let reusedNumber =                                                                  /* Reused number     */
                try XCTUnwrap(rolloverCalendar.weeks[0].collection.lists[0].cards.first).id
            let rolloverCard =                                                                  /* Rollover card     */
                newWeek.collection.lists[0].makeItem(id: reusedNumber, title: "Rollover Card",
                    createdAt: Date(timeIntervalSince1970: 1793600000), creationPreferences: LocalProfilePreferences())

            newWeek.collection.lists[0].cards = [rolloverCard]

            for index in 1..<7
            {
                let card =                                                              /* Synthetic card fixture */
                    newWeek.collection.lists[index].makeItem(id: reusedNumber + index,
                        title: "Rollover bookmark " + String(index), createdAt: Date(timeIntervalSince1970: 1793600000),
                        creationPreferences: LocalProfilePreferences())

                newWeek.collection.lists[index].cards = [card]
            }

            newWeek.collection.savedCardIDs = Set(newWeek.collection.lists.flatMap(\.cards).map(\.id))

            rolloverCalendar.weeks.append(newWeek)

            rolloverCalendar.currentWeekKey = newWeek.startKey

            existingDefaults.set(try JSONEncoder().encode(rolloverCalendar), forKey: "Plenact.CalendarWeeks.v1")
            existingDefaults.set(try JSONEncoder().encode(newWeek.collection.lists), forKey: "Plenact.Board.v1")
            existingDefaults.set(Array(newWeek.collection.savedCardIDs), forKey: "Plenact.SavedCardIDs.v1")

            let rolloverBackup =                                        /* Rollover backup */
                try LegacyWorkspaceExport.capture(defaults: existingDefaults, domain: existingDomain, root: existingContainer)
            let rolloverOutput =                                        /* Rollover output */
                try PortableEditedExport.prepare(rolloverBackup)
            let rolloverAgain  =                                        /* Rollover again  */
                try PortableEditedExport.prepare(rolloverBackup)

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: rolloverOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: rolloverAgain))
            XCTAssertEqual(try JSONDecoder().decode(PlanningCalendarDocument.self, from: XCTUnwrap(existingDefaults.data(forKey: "Plenact.CalendarWeeks.v1"))), rolloverCalendar)
            for name in ["Assembly.json", "Manifest.json"]
            {
                let item =      /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: rolloverOutput), uniformTypeIdentifier: "public.json")

                item.name = "RolloverPackage-" + name
                item.lifetime = .keepAlways

                add(item)
            }

            let rolloverBlobs =         /* Rollover blobs */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: personalBlobValues, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            rolloverBlobs.name = "RolloverPackage-Blobs.json"
            rolloverBlobs.lifetime = .keepAlways

            add(rolloverBlobs)

            let rolloverCandidate =                                                             /* Rollover candidate  */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(rolloverOutput.fileWrappers?["PortableTestPackage"])))
            let roundTripCalendar =                                                             /* Round trip calendar */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(rolloverCandidate.values["Plenact.CalendarWeeks.v1"] as? Data))

            XCTAssertEqual(roundTripCalendar.weeks.count, rolloverCalendar.weeks.count)
            XCTAssertEqual(roundTripCalendar.currentWeekKey, newWeek.startKey)
            XCTAssertEqual(roundTripCalendar.weeks.last?.collection.lists[0].cards.first?.word, "Rollover Card")
            XCTAssertEqual(roundTripCalendar.weeks.last?.collection.savedCardIDs.count, 7)
            XCTAssertEqual((rolloverCandidate.values["Plenact.SavedCardIDs.v1"] as? [Int])?.count, 7)

            let rolloverStage = base.appendingPathComponent("RolloverStage")    /* Rollover stage */

            try rolloverCandidate.stage(at: rolloverStage)
            try rolloverCandidate.install(from: rolloverStage, root: existingContainer, defaults: existingDefaults, domain: existingDomain)

            let rolloverReexport =                                              /* Rollover reexport */
                try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: existingDefaults, domain: existingDomain, root: existingContainer))

            XCTAssertEqual(try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: rolloverOutput),
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: rolloverReexport))

            listCalendar.weeks[0].collection.lists[0].subtitleOverride = nil
            listCalendar.weeks[0].collection.lists[0].appearance = nil
            listCalendar.weeks[0].collection.lists[0].newItemPresentation = .card

            structuralDefaults.set(try JSONEncoder().encode(listCalendar), forKey: "Plenact.CalendarWeeks.v1")
            structuralDefaults.set(try JSONEncoder().encode(listCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            let clearedListOutput =                                                             /* Cleared list output    */
                try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: structuralDefaults, domain: structuralDomain, root: structuralContainer))
            let clearedListCandidate =                                                          /* Cleared list candidate */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(clearedListOutput.fileWrappers?["PortableTestPackage"])), retainedAliases: expandedAliases)
            let clearedMetadataLists =                                                          /* Cleared metadata lists */
                try JSONDecoder().decode([KanbanList].self,
                    from: XCTUnwrap(clearedListCandidate.values["Plenact.Board.v1"] as? Data))

            XCTAssertNil(clearedMetadataLists[0].subtitleOverride)
            XCTAssertNil(clearedMetadataLists[0].appearance)
            XCTAssertEqual(clearedMetadataLists[0].newItemPresentation, .card)
            structuralDefaults.set(try JSONEncoder().encode(importedCalendar), forKey: "Plenact.CalendarWeeks.v1")
            structuralDefaults.set(try JSONEncoder().encode(importedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            // Removing a live attachment must not lose its verified imported original or restore its row
            let removedName  =                                                  /* Removed name  */
                try XCTUnwrap(originalImported.attachments?.first?.fileName)
            var removedPhoto =                                                  /* Removed photo */
                importedCalendar.weeks[0].collection.lists[0].cards[0]

            removedPhoto.attachments?.removeFirst()

            importedCalendar.weeks[0].collection.lists[0].cards[0] = removedPhoto

            structuralDefaults.set(try JSONEncoder().encode(importedCalendar), forKey: "Plenact.CalendarWeeks.v1")
            structuralDefaults.set(try JSONEncoder().encode(importedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            let removedPath =           /* Removed path */
                structuralContainer.appendingPathComponent("Documents/CardAttachments/" + removedName)

            try manager.removeItem(at: removedPath)

            let removedBackup    =                                                      /* Removed backup    */
                try LegacyWorkspaceExport.capture(defaults: structuralDefaults, domain: structuralDomain, root: structuralContainer)
            let removedOutput    =                                                      /* Removed output    */
                try PortableEditedExport.prepare(removedBackup)
            let removedReview    =                                                      /* Removed review    */
                try PortablePackageReview.review(files: XCTUnwrap(removedOutput.fileWrappers?["PortableTestPackage"]))
            let removedCandidate =                                                      /* Removed candidate */
                try PortableWorkspaceCandidate.prepare(removedReview, retainedAliases: expandedAliases)
            let removedLists     = try JSONDecoder().decode([KanbanList].self,          /* Removed lists     */
                from: XCTUnwrap(removedCandidate.values["Plenact.Board.v1"] as? Data))

            XCTAssertEqual(removedLists.first?.cards.first?.attachments?.map(\.id), [secondAttachment.id])
            XCTAssertEqual(removedCandidate.media.files["Documents/CardAttachments/" + removedName], photoBytes)
            XCTAssertFalse(manager.fileExists(atPath: removedPath.path))

            var clearedNested =                                         /* Cleared nested */
                importedCalendar.weeks[0].collection.lists[0].cards[0]

            clearedNested.comments = []
            clearedNested.checklists = []
            clearedNested.members = []
            clearedNested.reactions = nil
            clearedNested.attachments = nil
            clearedNested.coverAttachmentID = nil
            importedCalendar.weeks[0].collection.lists[0].cards[0] = clearedNested

            structuralDefaults.set(try JSONEncoder().encode(importedCalendar), forKey: "Plenact.CalendarWeeks.v1")
            structuralDefaults.set(try JSONEncoder().encode(importedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")

            let clearBackup    =                                                                /* Clear backup    */
                try LegacyWorkspaceExport.capture(defaults: structuralDefaults, domain: structuralDomain, root: structuralContainer)
            let clearOutput    = try PortableEditedExport.prepare(clearBackup)                  /* Clear output    */
            let clearCandidate =                                                                /* Clear candidate */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(clearOutput.fileWrappers?["PortableTestPackage"])), retainedAliases: expandedAliases)
            let clearLists = try JSONDecoder().decode([KanbanList].self,                        /* Clear lists     */
                from: XCTUnwrap(clearCandidate.values["Plenact.Board.v1"] as? Data))
            let clearCard = try XCTUnwrap(clearLists.first?.cards.first)                        /* Clear card      */

            XCTAssertTrue(clearCard.comments.isEmpty && clearCard.checklists.isEmpty && clearCard.members.isEmpty)
            XCTAssertNil(clearCard.reactions)
            XCTAssertNil(clearCard.attachments)
            XCTAssertNil(clearCard.coverAttachmentID)
            XCTAssertEqual(clearCandidate.media.files["Documents/CardAttachments/" + removedName], photoBytes)
            XCTAssertEqual(try PortableCreationIdentity.reserve(proposed: 7, root: base.appendingPathComponent("Nonportable")), 7)
            for name in ["Assembly.json", "Manifest.json"]
            {
                let item =      /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: structuralOutput), uniformTypeIdentifier: "public.json")

                item.name = "StructuralPackage-" + name
                item.lifetime = .keepAlways

                add(item)
            }

            let structuralOriginals =                                                           /* Structural originals */
                try XCTUnwrap(structuralOutput.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let richBlobs           =                                                           /* Rich blobs           */
                try Dictionary(uniqueKeysWithValues: structuralOriginals.map { name, file in
                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let structuralBlobs =       /* Structural blobs */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: richBlobs, options: .sortedKeys), uniformTypeIdentifier: "public.json")

            structuralBlobs.name = "StructuralPackage-Blobs.json"
            structuralBlobs.lifetime = .keepAlways

            add(structuralBlobs)
            defaults.set(try JSONEncoder().encode(editedCalendar.weeks[0].collection.lists), forKey: "Plenact.Board.v1")
            defaults.set(candidate.values["Plenact.SavedCardIDs.v1"], forKey: "Plenact.SavedCardIDs.v1")
            defaults.set(candidate.values["Plenact.LibraryImportant.v1"], forKey: "Plenact.LibraryImportant.v1")

            // New structure must never be silently omitted by this bounded export implementation
            var unsupported = editedCalendar    /* Rejected edit fixture */

            unsupported.weeks[0].collection.lists[0].cards.append(KanbanCard(id: 99999, word: "New Card", listTitle: "Monday", checklists: []))
            defaults.set(try JSONEncoder().encode(unsupported), forKey: "Plenact.CalendarWeeks.v1")

            let unsupportedBackup =     /* Unsupported backup */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)

            XCTAssertThrowsError(try PortableEditedExport.prepare(unsupportedBackup)) { error in
                guard case PortableEditedExport.Failure.structureChanged = error else
                {
                    return XCTFail("Structural changes must explain the unsupported operation")
                }
            }
            defaults.set(candidate.values["Plenact.CalendarWeeks.v1"], forKey: "Plenact.CalendarWeeks.v1")
            defaults.set(candidate.values["Plenact.Board.v1"], forKey: "Plenact.Board.v1")
            defaults.set(true, forKey: "Plenact.ExampleCardLocations.Applied.v1")
            defaults.set(Data("retained recovery evidence".utf8), forKey: "Plenact.ExampleCardLocations.Backup.v1")

            let unchangedBackup =       /* Unchanged backup */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)

            _ = try PortableEditedExport.prepare(unchangedBackup)

            let sourceBackup =                                          /* Source backup       */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: container)
            let report       =                                          /* Validation findings */
                try XCTUnwrap(JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("NativePreflight.json", in: sourceBackup.files)) as? [String: Any])

            XCTAssertEqual(report["format_version"] as? Int, 2)

            _ = try MigrationBackupReader.values(in: sourceBackup)

            XCTAssertThrowsError(try MigrationPreview.prepare(backup: sourceBackup,
                journalURL: base.appendingPathComponent("NoRemigration/ids.json"), timeZoneID: "America/Chicago"))

            let exported =                                              /* Prepared portable export */
                base.appendingPathComponent("ImportedNativeBackup")

            try sourceBackup.files.write(to: exported, options: .atomic, originalContentsURL: nil)

            let reviewedBackup = try LocalBackupRestore.review(at: exported)    /* Reviewed backup */

            XCTAssertEqual(reviewedBackup.cardCount, 1)
            try transaction.undoPortableWorkspace()
            XCTAssertFalse(transaction.hasPortableImportBackup)

            let history =                                                               /* Retained edit history */
                base.appendingPathComponent("ProtectedRecovery/PortableImportHistory")

            XCTAssertEqual(try manager.contentsOfDirectory(at: history, includingPropertiesForKeys: nil).count, 1)
            XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]))
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("Retained original document".utf8))
            XCTAssertTrue(try PortableRuntimeEvidence.capture(root: container).isEmpty)
            try transaction.installNativeSource
            {
                try LocalBackupRestore.install(reviewedBackup, root: container, defaults: defaults, domain: domain)
            }
            XCTAssertEqual(try PortableRuntimeEvidence.capture(root: container)["CanonicalPackage.bin"], reviewed.snapshot)
            try transaction.undoNativeSource()
            XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]))
            XCTAssertTrue(try PortableRuntimeEvidence.capture(root: container).isEmpty)
            XCTAssertThrowsError(try transaction.installPortableWorkspace {
                try candidate.install(from: stage, root: container, defaults: defaults, domain: domain)
                throw CocoaError(.fileWriteUnknown)
            })
            XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]))
            XCTAssertFalse(transaction.hasPortableImportBackup)
            XCTAssertFalse(transaction.needsRecovery)
            XCTAssertTrue(try PortableRuntimeEvidence.capture(root: container).isEmpty)
        }
    }


    /// @fcn MigrationStudioTests.testEditedExportIgnoresOnlyNativeSetOrdering
    /// @brief Verify independently encoded sets compare equally while authored order and duplicates remain meaningful
    /// @return Void after normalization regression checks
    func testEditedExportIgnoresOnlyNativeSetOrdering() throws
    {
        let first     =                                                                 /* First comparison value        */
            Data(#"{"savedCardIDs":[3,1,2],"exampleFocus":{"important":[8,4],"bookmarked":[3,2]},"cards":[1,2]}"#.utf8)
        let reordered =                                                                 /* Items in the requested order  */
            Data(#"{"savedCardIDs":[2,3,1],"exampleFocus":{"important":[4,8],"bookmarked":[2,3]},"cards":[1,2]}"#.utf8)
        let moved     =                                                                 /* Item after transfer           */
            Data(#"{"savedCardIDs":[2,3,1],"exampleFocus":{"important":[4,8],"bookmarked":[2,3]},"cards":[2,1]}"#.utf8)
        let duplicate =                                                                 /* Repeated identity fixture     */
            Data(#"{"savedCardIDs":[2,3,1,1],"exampleFocus":{"important":[4,8],"bookmarked":[2,3]},"cards":[1,2]}"#.utf8)
        let baseline  =                                                                 /* Original state for comparison */
            try XCTUnwrap(PortableEditedExport.nativeJSON(first) as? [String: Any])

        XCTAssertTrue(NSDictionary(dictionary: baseline).isEqual(to: try XCTUnwrap(PortableEditedExport.nativeJSON(reordered) as? [String: Any])))
        XCTAssertFalse(NSDictionary(dictionary: baseline).isEqual(to: try XCTUnwrap(PortableEditedExport.nativeJSON(moved) as? [String: Any])))
        XCTAssertFalse(NSDictionary(dictionary: baseline).isEqual(to: try XCTUnwrap(PortableEditedExport.nativeJSON(duplicate) as? [String: Any])))
    }


    /// @fcn MigrationStudioTests.testEditedScheduleUsesPinnedTimeZoneAndPrecision
    /// @brief Cover date/time precision, explicit clearing and both repeated-hour occurrences
    /// @return Void after tagged scheduling assertions
    func testEditedScheduleUsesPinnedTimeZoneAndPrecision() throws
    {
        let instant =                                                                   /* Reference timestamp      */
            Date(timeIntervalSince1970: 1792933200).timeIntervalSinceReferenceDate
        let timed   =                                                                   /* Timed comparison fixture */
            try XCTUnwrap(PortableEditedExport.schedule(instant, kind: "dateAndTime", zone: "America/Chicago") as? [String: Any])

        XCTAssertEqual(timed["time_zone"] as? String, "America/Chicago")
        XCTAssertEqual(timed["tzdb_version"] as? String, "2025b")
        XCTAssertEqual(timed["kind"] as? String, "date_and_time")
        XCTAssertTrue(try PortableEditedExport.schedule(NSNull(), kind: "date", zone: "America/Chicago") is NSNull)

        let date =      /* Date used by this operation */
            try XCTUnwrap(PortableEditedExport.schedule(instant, kind: "date", zone: "America/Chicago") as? [String: Any])

        XCTAssertEqual(Set(date.keys), ["kind", "date"])

        let time =      /* Local schedule time */
            try XCTUnwrap(PortableEditedExport.schedule(instant, kind: "time", zone: "America/Chicago") as? [String: Any])

        XCTAssertEqual(Set(time.keys), ["kind", "time"])

        let formatter = ISO8601DateFormatter()          /* Date or value formatter */

        for (text, occurrence) in [("2026-11-01T06:30:00Z", "first"), ("2026-11-01T07:30:00Z", "second")]
        {
            let value    =                                                                      /* Value being processed            */
                try XCTUnwrap(formatter.date(from: text)).timeIntervalSinceReferenceDate
            let repeated =                                                                      /* Result of the repeated operation */
                try XCTUnwrap(PortableEditedExport.schedule(value, kind: "dateAndTime", zone: "America/Chicago") as? [String: Any])

            XCTAssertEqual(repeated["occurrence"] as? String, occurrence)
        }
        XCTAssertThrowsError(try PortableEditedExport.schedule(instant, kind: "unknown", zone: "America/Chicago"))
        XCTAssertThrowsError(try PortableEditedExport.schedule(instant, kind: "dateAndTime", zone: "Europe/Paris"))
    }
}
