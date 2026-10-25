// --------------------------------------------------------------------------------------------------
// @file       MigrationPreview.swift
// @brief      Canonical content and metadata conversion with explicit partial coverage
// @details    Supported User Data Model versions: 1.0 base and working 1.1 appearance metadata.
//             Private journal formats 1/2/3; local preview only, without authenticated ownership or sync.
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
    let contentRecordCount: Int   /* Canonical content documents emitted by this slice */
    let blockedContentReason: String? /* Explicit blocker, never silently omitted content */
    let metadataRecordCount: Int
    let selectionEntryCount: Int
    let selectionIssueCount: Int
    let verifiedAssetCount: Int
    let missingAssetCount: Int
    let assetIssueCount: Int
    let settingsSourceLabel: String
    let settingsPreparedCount: Int
    let shortcutItemCount: Int
    let settingsReviewCount: Int
    let studioPreparedCount: Int
    let artworkCount: Int
    let appearanceReviewCount: Int
    let planningRecordCount: Int
    let planningReviewCount: Int
    let appearanceModelRecordCount: Int
    let remainingStores: [String]    /* Present source stores requiring later adapters        */


    /// @fcn MigrationPreview.contentReviewMessage
    /// @brief Explain a content blocker without exposing implementation codes in the interface
    /// @return Optional action-oriented review guidance; machine details remain in the exported report
    var contentReviewMessage: String?
    {

        guard let code = blockedContentReason else
        {
            return nil
        }
        if code == "original_timezone_confirmation_required"
        {
            return "Choose the original timezone above, then prepare the preview again."
        }
        if code == "board_week_projection_conflict"
        {
            return "The saved Board and current Week differ and need review before conversion."
        }
        if code.contains("timezone") || code.contains("date_range")
        {
            return "Some saved dates use a timezone or date range this first converter does not support yet."
        }
        if code.hasPrefix("unsupported_source_fields:")
        {
            return "The backup includes fields this converter does not support yet. The originals are preserved."
        }
        return "Some content needs review before conversion. The backup and report retain the details."
    }


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
    static func prepare(backup: LegacyWorkspaceBackup, journalURL: URL, timeZoneID: String? = nil) throws -> MigrationPreview
    {

        let values = try MigrationBackupReader.values(in: backup)
        guard backup.files.fileWrappers?["PortableRuntime"] == nil else
        {
            // Never remigrate the normalized native projection as though it were original legacy data.
            throw Failure.invalidSnapshot
        }
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
        // The unsaved catalog is the explicit application fallback, never a recovered user catalog.
        let usesDefaultLabels = values["Plenact.LabelLibrary.v1"] == nil &&
            ["Plenact.CalendarWeeks.v1", "Plenact.PersonalCollections.v1", "Plenact.PlanningTemplates.v1"].contains(where: { values[$0] != nil })
        let defaultCatalog = usesDefaultLabels ? try JSONEncoder().encode(LabelLibrary.starter.includingDayAreas) : nil
        var records = try labels(values["Plenact.LabelLibrary.v1"] ?? defaultCatalog, journal: &journal)
        records.append(contentsOf: try displays(values, journal: &journal))
        var content: MigrationContentConverter.Result?
        var blockedContentReason: String?
        let contentKeys = ["Plenact.Board.v1", "Plenact.CalendarWeeks.v1", "Plenact.PersonalCollections.v1", "Plenact.PlanningTemplates.v1"]
        if contentKeys.contains(where: { values[$0] != nil })
        {
            if let timeZoneID, !timeZoneID.isEmpty
            {
                do
                {
                    let sourceReport = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as! [String: Any]
                    var digests: [String: String] = [:]
                    for entry in sourceReport["media"] as! [[String: Any]]
                    {
                        digests[entry["path"] as! String] = entry["sha256"] as? String
                    }
                    content = try MigrationContentConverter.convert(values: values, timeZoneID: timeZoneID,
                        mediaDigests: digests, existing: records, journal: journal)
                    records.append(contentsOf: content!.records)
                    journal = content!.journal
                }
                catch let error as MigrationContentValues.Failure
                {
                    switch error
                    {
                    case .invalid(let code): blockedContentReason = "content_validation:" + code
                    case .timezoneRequired: blockedContentReason = "original_timezone_confirmation_required"
                    case .projectionConflict: blockedContentReason = "board_week_projection_conflict"
                    case .duplicateIdentity: blockedContentReason = "duplicate_source_identity"
                    case .unsupportedField(let type): blockedContentReason = "unsupported_source_fields:" + type
                    }
                }
                catch
                {
                    blockedContentReason = "native_content_decode_failed"
                }
            }
            else
            {
                blockedContentReason = "original_timezone_confirmation_required"
            }
        }
        var settings: MigrationSettingsPreview.Result?
        var settingsBlocker: String?
        var settingsJournal = journal
        do
        {
            let source = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as! [String: Any]
            let digests = Dictionary(uniqueKeysWithValues: (source["media"] as! [[String: Any]]).map {
                ($0["path"] as! String, $0["sha256"] as! String)
            })
            settings = try MigrationSettingsPreview.prepare(values: values, records: records,
                mediaDigests: digests, journal: &settingsJournal)
            records.append(contentsOf: settings!.records)
            journal = settingsJournal
        }
        catch let error as MigrationContentValues.Failure
        {
            if case .invalid(let code) = error
            {
                settingsBlocker = code
            }
            else
            {
                settingsBlocker = "settings_source_requires_review"
            }
        }
        catch
        {
            settingsBlocker = "settings_source_decode_failed"
        }
        var studio: MigrationStudioPreview.Result?
        var studioBlocker: String?
        var studioJournal = journal
        do
        {
            let source = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as! [String: Any]
            let digests = Dictionary(uniqueKeysWithValues: (source["media"] as! [[String: Any]]).map {
                ($0["path"] as! String, $0["sha256"] as! String)
            })
            studio = try MigrationStudioPreview.prepare(values: values, records: records,
                mediaDigests: digests, journal: &studioJournal)
            records.append(contentsOf: studio!.records)
            journal = studioJournal
        }
        catch let error as MigrationContentValues.Failure
        {
            if case .invalid(let code) = error
            {
                studioBlocker = code
            }
            else
            {
                studioBlocker = "studio_source_requires_review"
            }
        }
        catch
        {
            studioBlocker = "studio_source_decode_failed"
        }
        var planning: MigrationPlanningPreview.Result?
        var planningBlocker: String?
        var planningJournal = journal
        do
        {
            planning = try MigrationPlanningPreview.prepare(values: values, records: records, journal: &planningJournal)
            records.append(contentsOf: planning!.records)
            journal = planningJournal
        }
        catch let error as MigrationContentValues.Failure
        {
            if case .invalid(let code) = error
            {
                planningBlocker = code
            }
            else
            {
                planningBlocker = "planning_source_requires_review"
            }
        }
        catch
        {
            planningBlocker = "planning_source_decode_failed"
        }
        let assets = try MigrationAssetPreview.prepare(backup: backup,
            records: records + (settings?.assetRecords ?? []) + (studio?.assetRecords ?? []) + (studio?.appearanceRecords ?? []), journal: &journal)
        let encoderOptions: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        let encodedRecords = try records.map { try JSONSerialization.data(withJSONObject: $0, options: encoderOptions) }
        var supported = Set(displayKeys.keys).union(["Plenact.LabelLibrary.v1"])
        if content?.boardConverted == true
        {
            supported.insert("Plenact.Board.v1")
        }
        if settings?.records.contains(where: { $0["record_type"] as? String == "today_shortcuts" }) == true
        {
            supported.insert("Plenact.TodayListShortcuts.v1")
        }
        supported.formUnion(planning?.convertedStores ?? [])
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
            "content_record_count": (content?.records.count ?? 0) - (content?.metadataRecordCount ?? 0),
            "calendar_template_record_count": content?.metadataRecordCount ?? 0,
            "verified_original_file_count": assets.verifiedCount,
            "missing_original_file_count": assets.missingCount,
            "asset_review_item_count": assets.issueCount,
            "asset_account_binding_pending": true,
            "settings_profile_prepared_count": settings?.preparedCount ?? 0,
            "shortcut_item_count": settings?.shortcutCount ?? 0,
            "settings_review_item_count": (settings?.issueCount ?? 0) + (settingsBlocker == nil ? 0 : 1),
            "settings_blocker": settingsBlocker as Any? ?? NSNull(),
            "settings_account_binding_pending": true,
            "studio_prepared_count": studio?.preparedCount ?? 0,
            "appearance_model_record_count": studio?.appearanceRecords.count ?? 0,
            "supplemental_user_data_model_versions": (studio?.appearanceRecords.isEmpty ?? true) ? [] : ["1.1"],
            "studio_artwork_count": studio?.artworkCount ?? 0,
            "appearance_review_item_count": (studio?.issueCount ?? 0) + (studioBlocker == nil ? 0 : 1),
            "studio_blocker": studioBlocker as Any? ?? NSNull(),
            "planning_review_record_count": planning?.recordCount ?? 0,
            "planning_unavailable_reference_count": planning?.unresolvedCount ?? 0,
            "planning_blocker": planningBlocker as Any? ?? NSNull(),
            "label_catalog_origin": usesDefaultLabels ? "application_default_catalog" : (values["Plenact.LabelLibrary.v1"] == nil ? "absent" : "saved_catalog"),
            "selection_preview_entry_count": content?.selections.entries.count ?? 0,
            "selection_preview_issues": content?.selections.issues ?? [],
            "selection_account_binding_pending": content != nil,
            "unresolved_label_reference_count": records.filter {
                $0["record_type"] as? String == "unavailable_reference" &&
                    ($0["payload"] as? [String: Any])?["target_type"] as? String == "label"
            }.count,
            "content_blocker": blockedContentReason as Any? ?? NSNull(),
            "confirmed_original_time_zone": timeZoneID as Any? ?? NSNull(),
            "date_rules_version": content == nil ? NSNull() : "2025b" as Any,
            "source_content_summary": content?.summary ?? [],
            "source_precision_evidence_count": content?.evidence.count ?? 0,
            "partial_source_stores": content == nil ? [] : contentKeys.filter { values[$0] != nil && $0 != "Plenact.Board.v1" },
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
        let assetFile = FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: assets.document, options: encoderOptions))
        assetFile.preferredFilename = "AssetPreview.json"
        preview.addFileWrapper(assetFile)
        if let planning
        {
            let file = FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: planning.document, options: encoderOptions))
            file.preferredFilename = "PlanningPreview.json"
            preview.addFileWrapper(file)
        }
        if let studio
        {
            let appearanceFile = FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: studio.appearanceDocument, options: encoderOptions))
            appearanceFile.preferredFilename = "AppearancePreview.json"
            preview.addFileWrapper(appearanceFile)
            let file = FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: studio.document, options: encoderOptions))
            file.preferredFilename = "StudioPreview.json"
            preview.addFileWrapper(file)
        }
        if let settings
        {
            let file = FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: settings.document, options: encoderOptions))
            file.preferredFilename = "SettingsPreview.json"
            preview.addFileWrapper(file)
        }
        if let defaultCatalog
        {
            let catalog = FileWrapper(regularFileWithContents: defaultCatalog)
            catalog.preferredFilename = "ApplicationDefaultLabels.json"
            preview.addFileWrapper(catalog)
        }
        if let content
        {
            let selections = FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: [
                "format": "plenact.ios-selection-preview", "format_version": 1,
                "target_user_data_model_version": "1.0", "account_binding_pending": true,
                "entries": content.selections.entries, "issues": content.selections.issues
            ], options: encoderOptions))
            selections.preferredFilename = "SelectionPreview.json"
            preview.addFileWrapper(selections)
            let graph = FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: content.graph, options: encoderOptions))
            graph.preferredFilename = "ContentGraph.json"
            preview.addFileWrapper(graph)
            let evidence = FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: content.evidence, options: encoderOptions))
            evidence.preferredFilename = "SourcePrecision.json"
            preview.addFileWrapper(evidence)
        }
        preview.preferredFilename = "MigrationPreview"
        output.addFileWrapper(preview)
        try MigrationIdentityStore.save(journal, at: journalURL, expected: baseline)
        let settingsLabels = ["saved_planning_preferences": "Saved planning settings",
            "saved_profile_preferences": "Saved profile settings", "application_defaults": "Application defaults"]
        let settingsOrigin = settings?.document["preferences_origin"] as? String ?? ""
        return MigrationPreview(files: output, recordCount: records.count,
            contentRecordCount: (content?.records.count ?? 0) - (content?.metadataRecordCount ?? 0), blockedContentReason: blockedContentReason, metadataRecordCount: content?.metadataRecordCount ?? 0, selectionEntryCount: content?.selections.entries.count ?? 0,
            selectionIssueCount: content?.selections.issues.count ?? 0,
            verifiedAssetCount: assets.verifiedCount, missingAssetCount: assets.missingCount,
            assetIssueCount: assets.issueCount,
            settingsSourceLabel: settingsLabels[settingsOrigin] ?? "Needs review",
            settingsPreparedCount: settings?.preparedCount ?? 0,
            shortcutItemCount: settings?.shortcutCount ?? 0,
            settingsReviewCount: (settings?.issueCount ?? 0) + (settingsBlocker == nil ? 0 : 1),
            studioPreparedCount: studio?.preparedCount ?? 0, artworkCount: studio?.artworkCount ?? 0,
            appearanceReviewCount: (studio?.issueCount ?? 0) + (studioBlocker == nil ? 0 : 1),
            planningRecordCount: planning?.recordCount ?? 0,
            planningReviewCount: (planning?.unresolvedCount ?? 0) + (planningBlocker == nil ? 0 : 1),
            appearanceModelRecordCount: studio?.appearanceRecords.count ?? 0, remainingStores: remaining)
    }
}
