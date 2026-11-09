// --------------------------------------------------------------------------------------------------
// @file       MigrationTestPackage.swift
// @brief      Simulator-only portable assembly with preserved originals and explicit synthetic ownership
// @details    Supported User Data Model versions: 1.0 base and working 1.1 composition. Package format 1.
//             Produces an inspectable folder; independent contract validation and portable recovery remain required
// --------------------------------------------------------------------------------------------------
import CryptoKit
import Foundation


/// Prepares an offline test package without authenticating an owner or installing converted data
/// @section Purpose
///     Expose native assembly for manual inspection while retaining the complete original backup
@MainActor
enum MigrationTestPackage
{
    static let accountID = "f0000000-0000-4000-8000-000000000001" /* Package account identifier */

    /// Reject incomplete source coverage, ambiguous values or inconsistent original files
    /// @section Purpose
    ///     Leave the existing backup export available when portable preparation cannot finish
    enum Failure: Error
    {
        case reviewRequired, invalidEvidence, unsupportedStore
    }


    /// @fcn MigrationTestPackage.json
    /// @brief Decode one required artifact from the frozen preview
    /// @param[in] name Preview artifact filename
    /// @param[in] files Preserved backup and conversion output
    /// @return Exact JSON dictionary
    /// @throws Invalid or absent evidence errors
    private static func json(_ name: String, files: FileWrapper) throws -> [String: Any]
    {
        guard let value = try JSONSerialization.jsonObject(with:
            MigrationBackupReader.file("MigrationPreview/" + name, in: files)) as? [String: Any] else
        {
            throw Failure.invalidEvidence
        }
        return value
    }


    /// @fcn MigrationTestPackage.data
    /// @brief Encode portable JSON with deterministic key order
    /// @param[in] value Complete JSON value
    /// @return Serialized finite JSON bytes
    /// @throws JSON serialization errors
    private static func data(_ value: Any) throws -> Data
    {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }


    /// @fcn MigrationTestPackage.prepare
    /// @brief Assemble a guarded native test package beside its original source backup
    /// @param[in] preview Frozen converted source with explicit original timezone
    /// @return Backup folder containing PortableTestPackage and unchanged original source files
    /// @throws Review, coverage, identity, inventory or serialization failures
    static func prepare(_ preview: MigrationPreview) throws -> FileWrapper
    {
        let files  = preview.files /* Files used by this operation    */
        let source =               /* Source value for this operation */
            LegacyWorkspaceBackup(files: files, storeCount: 0, mediaCount: 0, reviewCodes: [])

        _ = try MigrationBackupReader.values(in: source)

        let report = try json("Report.json", files: files) /* Validation findings */

        guard report["source_preferences_sha256"] as? String == MigrationBackupReader.digest(
            try MigrationBackupReader.file("Preferences.plist", in: files)) else
        {
            throw Failure.invalidEvidence
        }

        let pending = /* Operation awaiting completion */
            ["content_blocker", "settings_blocker", "studio_blocker", "planning_blocker"]
        let counts  = /* Aggregate record counts */
            ["missing_original_file_count", "asset_review_item_count", "settings_review_item_count",
            "appearance_review_item_count", "unresolved_label_reference_count", "planning_unavailable_reference_count"]

        guard pending.allSatisfy({ report[$0] is NSNull }),
              counts.allSatisfy({ (report[$0] as? Int) == 0 }),
              (report["source_review_codes"] as? [String]) == [],
              (report["selection_preview_issues"] as? [String]) == [],
              let workspace = report["preview_workspace_id"] as? String,
              let remaining = report["remaining_source_stores"] as? [String] else
        {
            throw Failure.reviewRequired
        }

        let draftStores: Set<String> = /* Draft stores */
            ["Plenact.CalendarWeeks.v1", "Plenact.PersonalCollections.v1",
            "Plenact.PlanningTemplates.v1", "Plenact.LibraryImportant.v1", "Plenact.SavedCardIDs.v1",
            "Plenact.PlanPreferences.v1", "Plenact.LocalProfile.v1", "Plenact.Studio.Settings.v1",
            "Plenact.Studio.Artwork.v1", "Plenact.WeekAppearance.v1"]

        guard Set(remaining).isSubset(of: draftStores) else
        {
            throw Failure.unsupportedStore
        }

        let settings   = /* Workspace settings snapshot */
            try json("SettingsPreview.json", files: files)
        let studio     = try json("StudioPreview.json", files: files) /* Studio operation value */
        let appearance = /* Resolved appearance choices */
            try json("AppearancePreview.json", files: files)
        let assets     = try json("AssetPreview.json", files: files) /* Verified asset records */

        guard settings["ready_for_binding"] as? Bool == true,
              studio["canonical_mapping_complete"] as? Bool == true,
              studio["format_version"] as? Int == 2,
              let entries = assets["entries"] as? [[String: Any]],
              let wrappers = files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"]?.fileWrappers else
        {
            throw Failure.reviewRequired
        }

        var records = /* Records being processed */
            try wrappers.sorted { $0.key < $1.key }.map { item -> [String: Any] in
            guard let bytes = item.value.regularFileContents,
                  let record = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  record["workspace_id"] as? String == workspace else
            {
                throw Failure.invalidEvidence
            }
            return record
        }
        let originalRecords        = records /* Original records     */
        var bound: [[String: Any]] = []      /* Bound lookup entries */

        for (kind, draft) in [("user_preferences", settings["preferences"]), ("user_profile", settings["profile"]),
            ("studio_settings", studio["studio_settings"])]
        {
            if draft is NSNull
            {
                continue
            }
            guard let draft = draft as? [String: Any], let id = draft["id"] as? String,
                  var payload = draft["payload"] as? [String: Any], payload["account_id"] == nil else
            {
                throw Failure.invalidEvidence
            }

            payload["account_id"] = accountID

            bound.append(document(kind, id: id, workspace: workspace, payload: payload))
        }

        var selection: Any = NSNull() /* Current selection state */

        if files.fileWrappers?["MigrationPreview"]?.fileWrappers?["SelectionPreview.json"] != nil
        {
            let draft = try json("SelectionPreview.json", files: files) /* Local editing draft */

            guard (draft["issues"] as? [String]) == [], let selections = draft["entries"] as? [[String: Any]] else
            {
                throw Failure.reviewRequired
            }

            selection = draft

            for entry in selections
            {
                guard let card = entry["card_id"] as? String, let bookmarked = entry["bookmarked"] as? Bool,
                      let importance = entry["importance"] as? Int, (0...5).contains(importance),
                      records.contains(where: { $0["record_type"] as? String == "card" && $0["id"] as? String == card }) else
                {
                    throw Failure.reviewRequired
                }

                // UUIDv5 uses the same synthetic account namespace and name as the independent assembler
                var namespace = UUID(uuidString: accountID)!.uuid /* Owner identity namespace */
                var name      =                                   /* Display or lookup name   */
                    withUnsafeBytes(of: &namespace) { Data($0) }

                name.append(Data(("content_selection:" + card).utf8))

                var bytes = /* Serialized or original bytes */
                    Array(Insecure.SHA1.hash(data: name).prefix(16))

                bytes[6] = (bytes[6] & 0x0f) | 0x50
                bytes[8] = (bytes[8] & 0x3f) | 0x80

                let hex = /* Encoded RGB color */
                    Array(bytes.map { String(format: "%02x", $0) }.joined())
                let id  = /* Record or view identity */
                    String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16])
                    + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])

                bound.append(document("content_selection", id: id, workspace: workspace, payload:
                    ["account_id": accountID, "card_id": card, "bookmarked": bookmarked, "importance": importance]))
            }
        }

        var blobs: [String: FileWrapper] = [:]           /* Verified original file blobs       */
        var mappings: [[String: Any]]    = []            /* Source-to-target identity mappings */
        var inventory                    = Set<String>() /* Verified source inventory          */
        var assetIDs                     = Set<String>() /* Asset i ds                         */

        for entry in entries
        {
            guard let id = entry["asset_id"] as? String, let path = entry["source_path"] as? String,
                  entry["content_state"] as? String == "described", inventory.insert(path).inserted,
                  assetIDs.insert(id).inserted else
            {
                throw Failure.reviewRequired
            }

            let bytes = /* Serialized or original bytes */
                try MigrationBackupReader.file(path, in: files)
            let hash  = MigrationBackupReader.digest(bytes) /* Content integrity digest */

            guard entry["sha256"] as? String == hash, entry["byte_length"] as? String == String(bytes.count) else
            {
                throw Failure.invalidEvidence
            }

            blobs[hash + ".bin"] = FileWrapper(regularFileWithContents: bytes)

            mappings.append(["asset_id": id, "source_path": path, "blob": "Originals/" + hash + ".bin"])

            var payload = entry /* Canonical record payload */

            for key in ["asset_id", "source_path", "type_evidence", "references"]
            {
                payload.removeValue(forKey: key)
            }

            payload["account_id"] = accountID

            bound.append(document("asset", id: id, workspace: workspace, payload: payload))
        }

        let preflightData = /* Preflight data */
            try MigrationBackupReader.file("NativePreflight.json", in: files)
        let preflight     = /* Source backup verification report */
            try JSONSerialization.jsonObject(with: preflightData) as? [String: Any]

        guard let declared = preflight?["media"] as? [[String: Any]],
              Set(declared.compactMap { $0["path"] as? String }) == inventory else
        {
            throw Failure.invalidEvidence
        }

        let replaced = records.filter { record in /* State after replacement */

            let payload = record["payload"] as? [String: Any] /* Canonical record payload */

            return record["record_type"] as? String == "unavailable_reference" && payload?["target_type"] as? String == "asset"
                && assetIDs.contains(payload?["target_id"] as? String ?? "")
        }

        records.removeAll { record in replaced.contains { $0["id"] as? String == record["id"] as? String } }

        records += bound

        records.append(document("account", id: accountID, workspace: workspace, payload:
            ["display_name": "Synthetic migration test owner", "account_kind": "personal", "created_at_utc": "2026-10-25T00:00:00.000Z"]))
        records.append(document("workspace", id: workspace, workspace: workspace, payload:
            ["owner_account_id": accountID, "display_name": "Synthetic migration test workspace", "calendar_system": "gregorian", "state": "active"]))

        let export                  = /* Prepared export evidence */
            try assemble(records, workspace: workspace, appearance: appearance)
        let evidence: [String: Any] = /* Retained verification evidence */
            ["settings": settings, "studio": studio, "selections": selection,
            "assets": assets, "appearance": appearance, "replaced_asset_placeholders": replaced]
        let assembly: [String: Any] = /* Assembled portable records */
            ["format": "plenact.synthetic-assembly-test", "format_version": 1,
            "ownership_verified": false, "cloud_upload_allowed": false, "workspace_export": export, "evidence": evidence]
        let assemblyData                   = try data(assembly) /* Assembly data  */
        var manifestFiles: [[String: Any]] =                    /* Manifest files */
            [["path": "Assembly.json", "byte_length": assemblyData.count,
            "sha256": MigrationBackupReader.digest(assemblyData)]]

        for (name, file) in blobs
        {
            let bytes = file.regularFileContents! /* Serialized or original bytes */

            manifestFiles.append(["path": "Originals/" + name, "byte_length": bytes.count, "sha256": MigrationBackupReader.digest(bytes)])
        }

        let manifest: [String: Any] = /* Package inventory and hashes */
            ["format": "plenact.synthetic-export-package", "format_version": 1,
            "user_data_model_version": "1.1", "ownership_verified": false, "cloud_upload_allowed": false,
            "originals": mappings, "files": manifestFiles.sorted { ($0["path"] as! String) < ($1["path"] as! String) }]
        let package = /* Portable package contents */
            FileWrapper(directoryWithFileWrappers: ["Manifest.json": FileWrapper(regularFileWithContents: try data(manifest)),
            "Assembly.json": FileWrapper(regularFileWithContents: assemblyData), "Originals": FileWrapper(directoryWithFileWrappers: blobs)])

        guard Set(records.compactMap { $0["id"] as? String }).count == records.count,
              originalRecords.allSatisfy({ $0["workspace_id"] as? String == workspace }),
              let serialized = files.serializedRepresentation, let output = FileWrapper(serializedRepresentation: serialized) else
        {
            throw Failure.invalidEvidence
        }

        package.preferredFilename = "PortableTestPackage"

        output.addFileWrapper(package)
        return output
    }


    /// @fcn MigrationTestPackage.document
    /// @brief Wrap an exact payload in a canonical Model 1.0 envelope
    /// @param[in] kind Record kind
    /// @param[in] id Stable test identity
    /// @param[in] workspace Preview workspace identity
    /// @param[in] payload Mapped source fields
    /// @return Canonical record dictionary
    private static func document(_ kind: String, id: String, workspace: String, payload: [String: Any]) -> [String: Any]
    {
        ["user_data_model_version": "1.0", "payload_schema_version": 1, "record_type": kind,
            "id": id, "workspace_id": workspace, "payload": payload]
    }


    /// @fcn MigrationTestPackage.assemble
    /// @brief Route all supported records exactly once into the versioned composite export
    /// @param[in] records Canonical test records
    /// @param[in] workspace Preview workspace identity
    /// @param[in] appearance Explicit Model 1.1 metadata
    /// @return Complete-shaped export awaiting independent schema and reference validation
    /// @throws Unknown kinds, duplicate singleton or missing ownership errors
    private static func assemble(_ records: [[String: Any]], workspace: String, appearance: [String: Any]) throws -> [String: Any]
    {
        let contentKinds  = /* Content kinds */
            ["collection": "collections", "list": "lists", "card": "cards"]
        let planningKinds = /* Planning kinds */
            ["calendar_index": "calendar_indexes", "calendar_week": "weeks", "daily_plan": "daily_plans",
            "weekly_review": "weekly_reviews", "periodic_review": "periodic_reviews", "planning_template": "templates",
            "template_library": "template_libraries", "review_rhythm": "review_rhythms", "asset": "assets"]
        let many = /* Many lookup entries */
            ["user_profile": "profiles", "label_category": "label_categories", "label": "labels",
            "studio_artwork": "artwork", "content_selection": "content_selections", "unavailable_reference": "unavailable_references"]
        let one = /* One lookup entries */
            ["account": "account", "workspace": "workspace", "user_preferences": "user_preferences",
            "studio_settings": "studio_settings", "today_shortcuts": "today_shortcuts", "workspace_display_preferences": "display_preferences"]
        var content: [String: Any] = /* Content being processed */
            ["user_data_model_version": "1.0", "payload_schema_version": 1, "workspace_id": workspace]
        var planning               = content /* Planning store projection */

        planning["account_id"] = accountID

        var base: [String: Any] = /* Base value before overrides */
            ["user_data_model_version": "1.0", "payload_schema_version": 1, "tombstones": []]

        for key in contentKinds.values
        {
            content[key] = [[String: Any]]()

        }
        for key in planningKinds.values
        {
            planning[key] = [[String: Any]]()

        }
        for key in many.values
        {
            base[key] = [[String: Any]]()

        }
        for key in one.values
        {
            base[key] = NSNull()

        }

        var external: [[String: Any]] = [] /* External content reference */

        for record in records
        {
            guard let kind = record["record_type"] as? String, let id = record["id"] as? String else
            {
                throw Failure.invalidEvidence
            }
            if let key = contentKinds[kind]
            {
                var list = content[key] as! [[String: Any]] /* List under consideration */

                list.append(record)

                content[key] = list

            }
            else if let key = planningKinds[kind]
            {
                var list = planning[key] as! [[String: Any]] /* List under consideration */

                list.append(record)

                planning[key] = list

            }
            else if let key = many[kind]
            {
                var list = base[key] as! [[String: Any]] /* List under consideration */

                list.append(record)

                base[key] = list

            }
            else if let key = one[kind], base[key] is NSNull
            {
                base[key] = record

            }
            else
            {
                throw Failure.invalidEvidence
            }
            if ["label", "label_category", "asset"].contains(kind)
            {
                external.append(["record_type": kind, "id": id, "status": "external"])
            }
            if kind == "unavailable_reference", let payload = record["payload"] as? [String: Any]
            {
                external.append(["record_type": payload["target_type"]!, "id": payload["target_id"]!, "status": "unavailable"])
            }
        }

        content["external_references"] = external
        planning["content"] = content
        base["planning"] = planning

        return ["user_data_model_version": "1.1", "payload_schema_version": 1, "base_workspace": base,
            "workspace_appearance": appearance["workspace_appearance"] ?? NSNull(),
            "artwork_library": appearance["artwork_library"] ?? NSNull()]
    }
}
