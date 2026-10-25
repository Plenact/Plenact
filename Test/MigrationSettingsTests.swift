// --------------------------------------------------------------------------------------------------
// @file       MigrationSettingsTests.swift
// @brief      Isolated settings/profile and Today shortcut migration verification
// @details    Supported User Data Model versions: 1.0. Synthetic preferences, avatar bytes and
//             temporary journals only; no real account or owner workspace is imported or modified.
// --------------------------------------------------------------------------------------------------
import Foundation
import XCTest
@testable import Plenact


/// Verifies native settings precedence, owner-qualified references and explicit default provenance.
/// @section Purpose
///     Keep account-unbound personal metadata reviewable without normalizing away saved values.
@MainActor
final class MigrationSettingsTests: XCTestCase
{

    /// @fcn MigrationSettingsTests.fixture
    /// @brief Freeze independent current-Week and personal owners sharing a numeric List ID
    /// @param[in] edit Optional source mutation before source capture
    /// @param[in] body Assertions receiving preserved source and a private journal path
    /// @return Void after deleting only synthetic preferences and files
    /// @throws Fixture setup, encoding or assertion-support errors
    private func fixture(edit: ((inout [String: Any]) throws -> Void)? = nil,
        _ body: (LegacyWorkspaceBackup, URL) throws -> Void) throws
    {

        let domain = "Plenact.SettingsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer
        {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        let week = DatedPlanningWeek.make(for: Date(timeIntervalSince1970: 1792843200),
            lists: [KanbanList(id: 1, title: "Live", cards: [])], calendar: calendar)
        var personal = PersonalCollection(title: "Personal", kind: .board)
        personal.lists = [KanbanList(id: 1, title: "Also one", cards: [])]
        var saved = LocalProfilePreferences(defaultListID: 1, usesReducedContent: false, showsNavigationLabels: false,
            todayFocusItemCount: 0, importanceStarStyle: .fanned, preferredMapsApp: .google)
        saved.randomizesNewCardBackgrounds = true
        let profile = LocalProfile(createdAt: Date(timeIntervalSince1970: 1792843200.123456),
            displayName: "  Local Writer 🪴  ", email: "MixedCase@Example.test", context: "",
            avatarColor: .teal, avatarForegroundColor: ProfileColor(red: 0.1, green: 0.2, blue: 0.3),
            avatarPhotoFileName: "avatar.png", preferences: LocalProfilePreferences(usesReducedContent: true))
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week])
        var values: [String: Any] = [
            "Plenact.Board.v1": try JSONEncoder().encode(week.collection.lists),
            "Plenact.CalendarWeeks.v1": try JSONEncoder().encode(document),
            "Plenact.PersonalCollections.v1": try JSONEncoder().encode([personal]),
            "Plenact.LocalProfile.v1": try JSONEncoder().encode(profile),
            "Plenact.PlanPreferences.v1": try JSONEncoder().encode(saved),
            "Plenact.TodayListShortcuts.v1": try JSONEncoder().encode([
                WorkspaceListReference(ownerID: personal.id, listID: 1),
                WorkspaceListReference(ownerID: week.collection.id, listID: 1)])]
        try edit?(&values)
        defaults.setPersistentDomain(values, forName: domain)
        let avatar = root.appendingPathComponent("Documents/ProfileAvatars/avatar.png")
        try FileManager.default.createDirectory(at: avatar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([137, 80, 78, 71, 13, 10, 26, 10, 0]).write(to: avatar)
        let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
        try body(backup, root.appendingPathComponent("Journal/ids.json"))
    }


    /// @fcn MigrationSettingsTests.document
    /// @brief Read an actual local settings artifact emitted by the migration preview
    /// @param[in] preview Prepared partial conversion
    /// @return Parsed settings-preview object
    /// @throws Missing or invalid JSON errors
    private func document(_ preview: MigrationPreview) throws -> [String: Any]
    {

        try XCTUnwrap(JSONSerialization.jsonObject(with:
            MigrationBackupReader.file("MigrationPreview/SettingsPreview.json", in: preview.files)) as? [String: Any])
    }


    /// @fcn MigrationSettingsTests.testSavedPrecedenceOwnerMappingsAvatarAndRetry
    /// @brief Preserve false/zero/strings, account separation, stable IDs and original owner mappings
    /// @return Void after source preservation and emitted-output assertions
    /// @throws Fixture or assertion-support errors
    func testSavedPrecedenceOwnerMappingsAvatarAndRetry() throws
    {

        try fixture { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            XCTAssertEqual(preview.settingsPreparedCount, 2)
            XCTAssertEqual(preview.shortcutItemCount, 2)
            XCTAssertEqual(preview.settingsReviewCount, 0)
            XCTAssertEqual(preview.verifiedAssetCount, 1)
            let result = try document(preview)
            XCTAssertEqual(result["preferences_origin"] as? String, "saved_planning_preferences")
            XCTAssertEqual(result["profile_preferences_shadowed"] as? Bool, true)
            let preferences = try XCTUnwrap((result["preferences"] as? [String: Any])?["payload"] as? [String: Any])
            let fields = try XCTUnwrap(preferences["preferences"] as? [String: Any])
            XCTAssertEqual(fields["today_focus_item_count"] as? Int, 0)
            XCTAssertEqual(fields["uses_reduced_content"] as? Bool, false)
            XCTAssertEqual(fields["shows_navigation_labels"] as? Bool, false)
            XCTAssertEqual(fields["preferred_maps_app"] as? String, "google")
            XCTAssertEqual(fields["importance_star_style"] as? String, "fanned")
            XCTAssertNotNil(fields["default_list_id"] as? String)
            XCTAssertNil(preferences["account_id"])
            let profile = try XCTUnwrap((result["profile"] as? [String: Any])?["payload"] as? [String: Any])
            XCTAssertEqual(profile["display_name"] as? String, "  Local Writer 🪴  ")
            XCTAssertEqual(profile["email"] as? String, "MixedCase@Example.test")
            XCTAssertNotNil(profile["avatar_asset_id"] as? String)
            XCTAssertNil(profile["account_id"])
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: preview.files),
                try MigrationBackupReader.file("Preferences.plist", in: backup.files))
            let second = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: result, options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: document(second), options: .sortedKeys))
            for name in ["SettingsPreview.json", "AssetPreview.json", "IdentityJournal.json", "Report.json"]
            {
                let attachment = XCTAttachment(data: try MigrationBackupReader.file("MigrationPreview/" + name, in: preview.files), uniformTypeIdentifier: "public.json")
                attachment.name = "Settings-" + name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let preflight = try XCTUnwrap(JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as? [String: Any])
            let media = try XCTUnwrap(preflight["media"] as? [[String: Any]])
            var originals: [String: String] = [:]
            for entry in media
            {
                let path = try XCTUnwrap(entry["path"] as? String)
                originals[path] = try MigrationBackupReader.file(path, in: backup.files).base64EncodedString()
            }
            let originalsAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals, options: .sortedKeys), uniformTypeIdentifier: "public.json")
            originalsAttachment.name = "Settings-Originals.json"
            originalsAttachment.lifetime = .keepAlways
            add(originalsAttachment)
            let source = try MigrationBackupReader.values(in: backup)
            let sourceValues = source.mapValues { value -> Any in
                if let data = value as? Data
                {
                    return (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
                }
                return value
            }
            let sourceAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: sourceValues, options: .sortedKeys), uniformTypeIdentifier: "public.json")
            sourceAttachment.name = "Settings-SourceValues.json"
            sourceAttachment.lifetime = .keepAlways
            add(sourceAttachment)
            let records = try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"]?.fileWrappers)
            let output = try records.sorted { $0.key < $1.key }.map { try JSONSerialization.jsonObject(with: XCTUnwrap($0.value.regularFileContents)) }
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), uniformTypeIdentifier: "public.json")
            attachment.name = "Settings-Records.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }


    /// @fcn MigrationSettingsTests.testProfileFallbackAndAbsentProfileAreExplicit
    /// @brief Distinguish saved embedded preferences from unsaved current application defaults
    /// @return Void after origin, profile absence and documented default assertions
    /// @throws Fixture or assertion-support errors
    func testProfileFallbackAndAbsentProfileAreExplicit() throws
    {

        for removeProfile in [false, true]
        {
            try fixture(edit: { values in
                values.removeValue(forKey: "Plenact.PlanPreferences.v1")
                if removeProfile
                {
                    values.removeValue(forKey: "Plenact.LocalProfile.v1")
                }
            }) { backup, url in
                let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
                let result = try document(preview)
                XCTAssertEqual(result["preferences_origin"] as? String,
                    removeProfile ? "application_defaults" : "saved_profile_preferences")
                XCTAssertEqual(result["profile"] is NSNull, removeProfile)
                if removeProfile
                {
                    XCTAssertEqual((result["defaulted_preference_fields"] as? [String])?.count, 19)
                }
            }
        }
    }


    /// @fcn MigrationSettingsTests.testOlderPartialPreferencesExposeCompatibilityDefaults
    /// @brief Preserve explicit false and null while identifying fields supplied by the native decoder
    /// @return Void after field-provenance assertions
    /// @throws Fixture or assertion-support errors
    func testOlderPartialPreferencesExposeCompatibilityDefaults() throws
    {

        try fixture(edit: { values in
            values["Plenact.PlanPreferences.v1"] = try JSONSerialization.data(withJSONObject: [
                "usesReducedContent": false, "todayFocusItemCount": 0, "preferredMapsApp": NSNull()])
        }) { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let result = try document(preview)
            let defaults = try XCTUnwrap(result["defaulted_preference_fields"] as? [String])
            XCTAssertTrue(defaults.contains("preferredMapsApp"))
            XCTAssertFalse(defaults.contains("usesReducedContent"))
            XCTAssertFalse(defaults.contains("todayFocusItemCount"))
        }
    }


    /// @fcn MigrationSettingsTests.testUnresolvedDefaultListIsNotSilentlyUnset
    /// @brief Retain the original numeric default with a review blocker instead of guessing an owner
    /// @return Void after pending-binding and source-evidence checks
    /// @throws Fixture or assertion-support errors
    func testUnresolvedDefaultListIsNotSilentlyUnset() throws
    {

        try fixture(edit: { values in
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(values["Plenact.PlanPreferences.v1"] as? Data)) as? [String: Any])
            raw["defaultListID"] = -999
            values["Plenact.PlanPreferences.v1"] = try JSONSerialization.data(withJSONObject: raw)
        }) { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let result = try document(preview)
            XCTAssertEqual(preview.settingsReviewCount, 1)
            XCTAssertEqual(result["unresolved_default_list_id"] as? Int, -999)
            XCTAssertEqual(result["ready_for_binding"] as? Bool, false)
        }
    }


    /// @fcn MigrationSettingsTests.testMalformedPreferencesProfileAndPinsFailClosed
    /// @brief Refuse unknown fields, invalid ranges/colors/paths and normalized-away shortcut evidence
    /// @return Void after visible settings blockers with preserved source and canonical content
    /// @throws Fixture or assertion-support errors
    func testMalformedPreferencesProfileAndPinsFailClosed() throws
    {

        for variant in 0..<7
        {
            try fixture(edit: { values in
                if variant < 3
                {
                    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(values["Plenact.PlanPreferences.v1"] as? Data)) as? [String: Any])
                    raw[variant == 0 ? "unknown" : "todayFocusItemCount"] = variant == 1 ? 13 : (variant == 2 ? true : "future") as Any
                    values["Plenact.PlanPreferences.v1"] = try JSONSerialization.data(withJSONObject: raw)
                }
                else if variant < 5
                {
                    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(values["Plenact.LocalProfile.v1"] as? Data)) as? [String: Any])
                    if variant == 3
                    {
                        raw["avatarColor"] = ["red": 2, "green": 0, "blue": 0]
                    }
                    else
                    {
                        raw["avatarPhotoFileName"] = "../outside.png"
                    }
                    values["Plenact.LocalProfile.v1"] = try JSONSerialization.data(withJSONObject: raw)
                }
                else
                {
                    var pins = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(values["Plenact.TodayListShortcuts.v1"] as? Data)) as? [[String: Any]])
                    if variant == 5
                    {
                        pins.append(try XCTUnwrap(pins.first))
                    }
                    else
                    {
                        pins[0]["listID"] = -999
                    }
                    values["Plenact.TodayListShortcuts.v1"] = try JSONSerialization.data(withJSONObject: pins)
                }
            }) { backup, url in
                let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
                XCTAssertNil(preview.blockedContentReason)
                XCTAssertEqual(preview.settingsPreparedCount, 0)
                XCTAssertEqual(preview.settingsReviewCount, 1)
                XCTAssertEqual(preview.shortcutItemCount, 0)
                XCTAssertNil(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["SettingsPreview.json"])
                XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: backup.files),
                    try MigrationBackupReader.file("Preferences.plist", in: preview.files))
            }
        }
    }

    /// @fcn MigrationSettingsTests.testPortableSettingsReconstructNativePreferencesProfileAndShortcuts
    /// @brief Verify canonical settings project into real models without defaults or owner substitution
    /// @return Void after exact effective settings and account/file reference checks
    /// @throws Fixture, reconstruction or assertion-support errors
    func testPortableSettingsReconstructNativePreferencesProfileAndShortcuts() throws
    {

        try fixture { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let settings = try document(preview)
            let wrappers = try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"]?.fileWrappers)
            let records = try wrappers.sorted { $0.key < $1.key }.map { item in
                try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(item.value.regularFileContents)) as? [String: Any])
            }
            let assetData = try MigrationBackupReader.file("MigrationPreview/AssetPreview.json", in: preview.files)
            let assetPreview = try XCTUnwrap(JSONSerialization.jsonObject(with: assetData) as? [String: Any])
            let entries = try XCTUnwrap(assetPreview["entries"] as? [[String: Any]])
            let files = Dictionary(uniqueKeysWithValues: try entries.map { entry in
                (try XCTUnwrap(entry["asset_id"] as? String), try XCTUnwrap(entry["original_name"] as? String))
            })
            let adapter = try PortableEditableContent(records: records, assetFiles: files)
            let workspace = try XCTUnwrap(records.first?["workspace_id"] as? String)
            let account = "f0000000-0000-4000-8000-000000000001"
            var canonical: [String: [String: Any]] = [:]
            for (field, kind) in [("preferences", "user_preferences"), ("profile", "user_profile")]
            {
                let draft = try XCTUnwrap(settings[field] as? [String: Any])
                var payload = try XCTUnwrap(draft["payload"] as? [String: Any])
                payload["account_id"] = account
                canonical[field] = ["user_data_model_version": "1.0", "payload_schema_version": 1,
                    "record_type": kind, "id": draft["id"]!, "workspace_id": workspace, "payload": payload]
            }
            let preferences = try XCTUnwrap(adapter.preferences(canonical["preferences"], accountID: account))
            XCTAssertEqual(preferences.todayFocusItemCount, 0)
            XCTAssertFalse(preferences.usesReducedContent)
            XCTAssertFalse(preferences.showsNavigationLabels)
            XCTAssertEqual(preferences.preferredMapsApp, .google)
            XCTAssertEqual(preferences.importanceStarStyle, .fanned)
            let mapped = try XCTUnwrap((settings["preferences"] as? [String: Any])?["payload"] as? [String: Any])
            let fields = try XCTUnwrap(mapped["preferences"] as? [String: Any])
            let target = try XCTUnwrap(fields["default_list_id"] as? String)
            XCTAssertEqual(preferences.defaultListID, adapter.numericIDs[target])
            let profile = try XCTUnwrap(adapter.profile(canonical["profile"], preferences: preferences, accountID: account))
            XCTAssertEqual(profile.displayName, "  Local Writer 🪴  ")
            XCTAssertEqual(profile.email, "MixedCase@Example.test")
            XCTAssertEqual(profile.avatarPhotoFileName, "avatar.png")
            XCTAssertEqual(profile.preferences, preferences)
            XCTAssertEqual(profile.id.uuidString.lowercased(), canonical["profile"]?["id"] as? String)
            let shortcuts = try XCTUnwrap(adapter.shortcuts(records.first { $0["record_type"] as? String == "today_shortcuts" }))
            XCTAssertEqual(shortcuts.count, 2)
            XCTAssertNotEqual(shortcuts[0].ownerID, shortcuts[1].ownerID)
            XCTAssertNotEqual(shortcuts[0].listID, shortcuts[1].listID)
            XCTAssertThrowsError(try adapter.preferences(canonical["preferences"], accountID: UUID().uuidString.lowercased()))
            XCTAssertThrowsError(try adapter.profile(canonical["profile"], preferences: nil, accountID: account))
        }
    }

}
