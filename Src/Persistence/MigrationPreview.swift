// --------------------------------------------------------------------------------------------------
// @file       MigrationPreview.swift
// @brief      First canonical label and display-setting conversion with explicit partial coverage
// @details    Supported User Data Model versions: 1.0. Local migration preparation only.
//             Journal/preview format 1 is not a server record, account credential or sync operation.
// --------------------------------------------------------------------------------------------------
import CoreFoundation
import Foundation


/// A partial conversion plus original backup, never a complete synchronized workspace.
/// @section Purpose
///     Make migration progress inspectable without disguising unsupported source domains.
struct MigrationPreview
{

    let files:           FileWrapper /* Originals plus private mapping and converted records */
    let recordCount:     Int         /* Canonical documents actually converted               */
    let remainingStores: [String]    /* Present source stores requiring later adapters        */


    /// Stable conversion errors retain the source backup and existing identity journal.
    /// @section Purpose
    ///     Prevent defaults or partial output from disguising invalid legacy content.
    enum Failure: Error
    {

        case invalidLabels, unsupportedFields, invalidPreference, invalidSnapshot
    }

    static let displayKeys: [String: String] = [
        "Plenact.BoardPresentation.v1": "board_presentation",
        "Plenact.CardCovers.enabled": "card_covers_enabled",
        "Plenact.ActivityShowsCovers": "activity_shows_covers",
        "Plenact.ActivityRecentSquareCards": "activity_recent_square_cards",
        "Plenact.LibraryShowsCollectionPreviews": "library_shows_collection_previews",
        "Plenact.LibraryScrollsCollectionPreviews": "library_scrolls_collection_previews"
    ] /* Shared intent; missing source values remain explicit null */


    /// @fcn MigrationPreview.document
    /// @brief Encode one explicit canonical envelope without server-owned provenance
    /// @param[in] type Canonical record type
    /// @param[in] source Original qualified identity
    /// @param[in] payload Complete mapped payload
    /// @param[in,out] journal Durable identity allocation candidate
    /// @return Exact portable JSON object
    /// @throws Invalid identity errors
    private static func document(type: String, source: String, payload: [String: Any],
        journal: inout MigrationIdentityJournal) throws -> [String: Any]
    {

        let target = try journal.resolve(MigrationSourceIdentity(recordType: type,
            owner: "workspace_metadata", legacyID: source, discriminator: nil))
        return ["user_data_model_version": "1.0", "payload_schema_version": 1,
            "record_type": type, "id": target.uuidString.lowercased(),
            "workspace_id": journal.previewWorkspaceID.uuidString.lowercased(), "payload": payload]
    }


    /// @fcn MigrationPreview.labels
    /// @brief Decode the actual legacy label library and explicitly map category/label identities
    /// @details Missing source means no invented library. Unknown fields and broken categories block
    ///          this conversion rather than being silently normalized by a source loader.
    /// @param[in] value Original optional property-list value
    /// @param[in,out] journal Stable source identity mappings
    /// @return Canonical categories followed by labels in their authored order
    /// @throws Wrong types, unsupported fields, duplicate IDs or missing categories
    private static func labels(_ value: Any?, journal: inout MigrationIdentityJournal) throws -> [[String: Any]]
    {

        guard let value else
        {
            return []
        }
        guard let data = value as? Data,
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == ["categories", "labels"],
              let categories = raw["categories"] as? [[String: Any]],
              let labels = raw["labels"] as? [[String: Any]],
              categories.allSatisfy({ Set($0.keys) == ["id", "name"] }),
              labels.allSatisfy({ Set($0.keys) == ["id", "name", "categoryID", "color"] }) else
        {
            throw Failure.unsupportedFields
        }
        let library = try JSONDecoder().decode(LabelLibrary.self, from: data)
        guard Set(library.categories.map(\.id)).count == library.categories.count,
              Set(library.labels.map(\.id)).count == library.labels.count else
        {
            throw Failure.invalidLabels
        }
        var categoryIDs: [String: String] = [:]
        var documents: [[String: Any]] = []
        for category in library.categories
        {
            let record = try document(type: "label_category", source: category.id,
                payload: ["name": category.name], journal: &journal)
            categoryIDs[category.id] = record["id"] as? String
            documents.append(record)
        }
        for label in library.labels
        {
            guard let category = categoryIDs[label.categoryID] else
            {
                throw Failure.invalidLabels
            }
            documents.append(try document(type: "label", source: label.id,
                payload: ["name": label.name, "category_id": category, "color": label.color.rawValue], journal: &journal))
        }
        return documents
    }


    /// @fcn MigrationPreview.displays
    /// @brief Preserve unset display preferences and reject native type coercion
    /// @param[in] values Captured persistent-domain values
    /// @param[in,out] journal Stable display-record identity
    /// @return Zero or one canonical display preference record
    /// @throws Wrong native types or unknown Board presentation tokens
    private static func displays(_ values: [String: Any], journal: inout MigrationIdentityJournal) throws -> [[String: Any]]
    {

        guard displayKeys.keys.contains(where: { values[$0] != nil }) else
        {
            return []
        }
        var payload: [String: Any] = [:]
        for (key, wire) in displayKeys
        {
            guard let value = values[key] else
            {
                payload[wire] = NSNull()
                continue
            }
            if wire == "board_presentation"
            {
                guard let token = value as? String, ["standard", "overview"].contains(token) else
                {
                    throw Failure.invalidPreference
                }
                payload[wire] = token
            }
            else
            {
                guard let boolean = value as? NSNumber, CFGetTypeID(boolean) == CFBooleanGetTypeID() else
                {
                    throw Failure.invalidPreference
                }
                payload[wire] = boolean.boolValue
            }
        }
        return [try document(type: "workspace_display_preferences", source: "display_preferences", payload: payload, journal: &journal)]
    }


    /// @fcn MigrationPreview.prepare
    /// @brief Convert the first supported metadata domains and preserve every original source file
    /// @details Persists identity mappings before returning output. No cloud account/workspace is
    ///          claimed; preview IDs remain explicitly local until a separate verified binding step.
    /// @param[in] backup Frozen source evidence
    /// @param[in] journalURL App-private migration journal or isolated test path
    /// @return Original backup with partial canonical records, journal and coverage report
    /// @throws Integrity, conversion, journal conflict or I/O failures; no source mutation occurs
    @MainActor
    static func prepare(backup: LegacyWorkspaceBackup, journalURL: URL) throws -> MigrationPreview
    {

        let values = try MigrationBackupReader.values(in: backup)
        let baseline = try MigrationIdentityStore.read(at: journalURL)
        var journal = try baseline.map(MigrationIdentityJournal.decode) ?? MigrationIdentityJournal()
        if backup.files.fileWrappers?["Migration"] != nil
        {
            let retained = try MigrationIdentityJournal.decode(
                MigrationBackupReader.file("Migration/IdentityJournal.json", in: backup.files))
            let current = Dictionary(uniqueKeysWithValues: journal.entries.map { ($0.source, $0.target) })
            guard baseline != nil, retained.sourceInstallationID == journal.sourceInstallationID,
                  retained.previewWorkspaceID == journal.previewWorkspaceID,
                  retained.entries.allSatisfy({ current[$0.source] == $0.target }) else
            {
                throw MigrationIdentityJournal.Failure.conflictingWrite
            }
        }
        var records = try labels(values["Plenact.LabelLibrary.v1"], journal: &journal)
        records.append(contentsOf: try displays(values, journal: &journal))
        let encoderOptions: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        let encodedRecords = try records.map { try JSONSerialization.data(withJSONObject: $0, options: encoderOptions) }
        let supported = Set(displayKeys.keys).union(["Plenact.LabelLibrary.v1"])
        let deviceKeys: Set<String> = ["Plenact.LibraryRecents.v1", "Plenact.ActivityRecents.v1",
            "Plenact.RecentSearches.v1", "Plenact.LocalReactionAuthor.v1", "Plenact.LastViewedList.v1",
            "Plenact.Welcome.lastDeparture.v1", "Plenact.ReviewRhythmDismissals.v1"]
        let local = values.keys.filter {
            deviceKeys.contains($0) || $0.hasPrefix("Plenact.BoardViewport.v1.") || $0.hasPrefix("plenact.creationDraft.")
        }.sorted()
        let recovery = values.keys.filter { LegacyStoreValidation.recoveryKeys.contains($0) }.sorted()
        let remaining = values.keys.filter {
            !supported.contains($0) && !local.contains($0) && !recovery.contains($0)
        }.sorted()
        let report: [String: Any] = [
            "format": "plenact.ios-migration-preview", "format_version": 1,
            "target_user_data_model_version": "1.0", "portable_conversion_complete": false,
            "cloud_account_linked": false, "workspace_identity_scope": "local_preview",
            "source_installation_id": journal.sourceInstallationID.uuidString.lowercased(),
            "preview_workspace_id": journal.previewWorkspaceID.uuidString.lowercased(),
            "source_preferences_sha256": MigrationBackupReader.digest(try MigrationBackupReader.file("Preferences.plist", in: backup.files)),
            "converted_record_count": records.count, "remaining_source_stores": remaining,
            "source_review_codes": backup.reviewCodes,
            "device_local_stores_preserved": local, "recovery_stores_preserved": recovery,
            "converted_record_types": Array(Set(records.compactMap { $0["record_type"] as? String })).sorted(),
            "blocking_requirements": ["remaining_source_adapters", "verified_account_workspace_binding",
                "full_workspace_validation", "recovery_acceptance"]
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: encoderOptions)
        guard let serialized = backup.files.serializedRepresentation,
              let output = FileWrapper(serializedRepresentation: serialized), output.isDirectory,
              output.fileWrappers?["MigrationPreview"] == nil else
        {
            throw Failure.invalidSnapshot
        }
        let recordDirectory = FileWrapper(directoryWithFileWrappers: [:])
        for (index, record) in records.enumerated()
        {
            let file = FileWrapper(regularFileWithContents: encodedRecords[index])
            file.preferredFilename = String(format: "%04d", index) + "-" + (record["record_type"] as! String) + ".json"
            recordDirectory.addFileWrapper(file)
        }
        let preview = FileWrapper(directoryWithFileWrappers: [
            "Records": recordDirectory,
            "Report.json": FileWrapper(regularFileWithContents: reportData),
            "IdentityJournal.json": FileWrapper(regularFileWithContents: try journal.encoded())
        ])
        preview.preferredFilename = "MigrationPreview"
        output.addFileWrapper(preview)
        try MigrationIdentityStore.save(journal, at: journalURL, expected: baseline)
        return MigrationPreview(files: output, recordCount: records.count, remainingStores: remaining)
    }
}
