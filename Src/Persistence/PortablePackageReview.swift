// --------------------------------------------------------------------------------------------------
// @file       PortablePackageReview.swift
// @brief      Read-only Simulator review of portable package records and exact original files
// @details    Supported User Data Model versions: 1.0 base and working 1.1; test package format 1.
//             Reads only portable members, never restores Preferences.plist or changes a workspace.
// --------------------------------------------------------------------------------------------------
import CoreFoundation
import Foundation


/// Human-readable counts from a frozen portable test package, without import authorization.
/// @section Purpose
///     Distinguish verified portable-file review from source recovery and workspace installation.
struct ReviewedPortablePackage
{

    let recordCount: Int
    let cardCount:   Int
    let listCount:   Int
    let mediaCount:  Int
    let snapshot:    Data /* Frozen portable members; no native source backup */
}


/// Checks integrity and core workspace relationships without executing any saved action.
/// @section Purpose
///     Establish a read-only review boundary before a future portable importer is allowed to write.
@MainActor
enum PortablePackageReview
{

    /// Review failures retain both the selected package and the current application workspace.
    /// @section Purpose
    ///     Reject unsupported versions, inconsistent metadata and corrupted original bytes.
    enum Failure: LocalizedError
    {

        case invalid, integrity, relationships

        /// @fcn Failure.errorDescription
        /// @brief Explain review failure without private source values
        /// @return Bounded review guidance
        var errorDescription: String?
        {

            switch self
            {
            case .invalid:
                return "Choose the saved portable test folder, or its PortableTestPackage subfolder. Its format must be supported."
            case .integrity:
                return "The package files do not match their integrity information. No data was imported."
            case .relationships:
                return "Some portable record identities or references need review. No data was imported."
            }
        }
    }


    /// @fcn PortablePackageReview.integer
    /// @brief Require a JSON integer without accepting a Boolean as its numeric equivalent
    /// @param[in] value Parsed JSON value
    /// @param[in] expected Required integer
    /// @return Whether the value has the expected numeric type and value
    private static func integer(_ value: Any?, equals expected: Int) -> Bool
    {

        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else
        {
            return false
        }
        return number.doubleValue == Double(expected)
    }


    /// @fcn PortablePackageReview.isFalse
    /// @brief Require an explicit JSON false rather than a numeric zero
    /// @param[in] value Parsed JSON value
    /// @return Whether the value is exactly false
    private static func isFalse(_ value: Any?) -> Bool
    {

        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else
        {
            return false
        }
        return !number.boolValue
    }


    /// @fcn PortablePackageReview.object
    /// @brief Decode an exact portable JSON object from a frozen directory
    /// @param[in] path Relative regular-file path
    /// @param[in] files Frozen directory
    /// @return Parsed dictionary
    /// @throws Missing, unsafe or malformed JSON errors
    private static func object(_ path: String, files: FileWrapper) throws -> [String: Any]
    {

        guard let value = try JSONSerialization.jsonObject(with: MigrationBackupReader.file(path, in: files)) as? [String: Any] else
        {
            throw Failure.invalid
        }
        return value
    }


    /// @fcn PortablePackageReview.review
    /// @brief Read only portable members from a user-selected folder without using its native source backup
    /// @param[in] url Saved export root or PortableTestPackage directory
    /// @return Integrity and core-reference review counts; not an import receipt or full schema certificate
    /// @throws Bounded read, unsupported format, corruption or reference errors
    static func review(at url: URL) throws -> ReviewedPortablePackage
    {

        let nested = url.appendingPathComponent("PortableTestPackage", isDirectory: true)
        let selected = FileManager.default.fileExists(atPath: nested.path) ? nested : url
        var remaining = LegacyWorkspaceExport.maximumBytes
        let files = try LocalBackupRestore.readTree(selected, remaining: &remaining)
        return try review(files: files)
    }


    /// @fcn PortablePackageReview.review
    /// @brief Verify a frozen package inventory and original bytes before displaying review counts
    /// @param[in] files PortableTestPackage members only
    /// @return Read-only counts
    /// @throws Unsupported or inconsistent package evidence
    static func review(files: FileWrapper) throws -> ReviewedPortablePackage
    {

        guard files.isDirectory, Set(files.fileWrappers?.keys.map { $0 } ?? []) == ["Manifest.json", "Assembly.json", "Originals"],
              let originals = files.fileWrappers?["Originals"], originals.isDirectory else
        {
            throw Failure.invalid
        }
        let manifest = try object("Manifest.json", files: files)
        guard Set(manifest.keys) == ["format", "format_version", "user_data_model_version", "ownership_verified",
                "cloud_upload_allowed", "originals", "files"],
              manifest["format"] as? String == "plenact.synthetic-export-package",
              integer(manifest["format_version"], equals: 1), manifest["user_data_model_version"] as? String == "1.1",
              isFalse(manifest["ownership_verified"]), isFalse(manifest["cloud_upload_allowed"]),
              let inventory = manifest["files"] as? [[String: Any]],
              let mappings = manifest["originals"] as? [[String: Any]], inventory.count <= 10000 else
        {
            throw Failure.invalid
        }
        var actual = Set(["Assembly.json"])
        for (name, file) in originals.fileWrappers ?? [:]
        {
            guard file.isRegularFile, !file.isSymbolicLink, name.count == 68, name.hasSuffix(".bin"),
                  name.dropLast(4).allSatisfy({ "0123456789abcdef".contains($0) }) else
            {
                throw Failure.invalid
            }
            actual.insert("Originals/" + name)
        }
        var declared = Set<String>()
        for entry in inventory
        {
            guard Set(entry.keys) == ["path", "byte_length", "sha256"], let path = entry["path"] as? String,
                  actual.contains(path), declared.insert(path).inserted else
            {
                throw Failure.integrity
            }
            let bytes = try MigrationBackupReader.file(path, in: files)
            guard integer(entry["byte_length"], equals: bytes.count),
                  entry["sha256"] as? String == MigrationBackupReader.digest(bytes) else
            {
                throw Failure.integrity
            }
        }
        guard declared == actual else
        {
            throw Failure.integrity
        }
        let assembly = try object("Assembly.json", files: files)
        guard assembly["format"] as? String == "plenact.synthetic-assembly-test",
              integer(assembly["format_version"], equals: 1), isFalse(assembly["ownership_verified"]),
              isFalse(assembly["cloud_upload_allowed"]),
              let export = assembly["workspace_export"] as? [String: Any],
              export["user_data_model_version"] as? String == "1.1",
              let base = export["base_workspace"] as? [String: Any], base["user_data_model_version"] as? String == "1.0",
              let planning = base["planning"] as? [String: Any], let content = planning["content"] as? [String: Any],
              let workspace = planning["workspace_id"] as? String,
              let account = base["account"] as? [String: Any], account["id"] as? String == MigrationTestPackage.accountID,
              planning["account_id"] as? String == MigrationTestPackage.accountID,
              let workspaceRecord = base["workspace"] as? [String: Any], workspaceRecord["id"] as? String == workspace,
              (workspaceRecord["payload"] as? [String: Any])?["owner_account_id"] as? String == MigrationTestPackage.accountID,
              content["workspace_id"] as? String == workspace else
        {
            throw Failure.relationships
        }
        let contentGroups = ["collections": "collection", "lists": "list", "cards": "card"]
        let planningGroups = ["calendar_indexes": "calendar_index", "weeks": "calendar_week", "daily_plans": "daily_plan",
            "weekly_reviews": "weekly_review", "periodic_reviews": "periodic_review", "templates": "planning_template",
            "template_libraries": "template_library", "review_rhythms": "review_rhythm", "assets": "asset"]
        let baseGroups = ["profiles": "user_profile", "label_categories": "label_category", "labels": "label",
            "artwork": "studio_artwork", "content_selections": "content_selection", "unavailable_references": "unavailable_reference"]
        var records: [[String: Any]] = []
        for (object, groups) in [(content, contentGroups), (planning, planningGroups), (base, baseGroups)]
        {
            for (key, kind) in groups
            {
                guard let group = object[key] as? [[String: Any]], group.allSatisfy({ $0["record_type"] as? String == kind }) else
                {
                    throw Failure.relationships
                }
                records += group
            }
        }
        for key in ["account", "workspace", "user_preferences", "studio_settings", "today_shortcuts", "display_preferences"]
        {
            if let record = base[key] as? [String: Any]
            {
                records.append(record)
            }
            else if !(base[key] is NSNull)
            {
                throw Failure.relationships
            }
        }
        for key in ["workspace_appearance", "artwork_library"]
        {
            if let record = export[key] as? [String: Any]
            {
                guard record["user_data_model_version"] as? String == "1.1", record["record_type"] as? String == key else
                {
                    throw Failure.relationships
                }
                records.append(record)
            }
            else if !(export[key] is NSNull)
            {
                throw Failure.relationships
            }
        }
        var identities = Set<String>()
        for record in records
        {
            guard let id = record["id"] as? String, UUID(uuidString: id) != nil,
                  identities.insert(id).inserted, record["workspace_id"] as? String == workspace,
                  let payload = record["payload"] as? [String: Any],
                  integer(record["payload_schema_version"], equals: 1),
                  (["workspace_appearance", "artwork_library"].contains(record["record_type"] as? String ?? "")
                    ? record["user_data_model_version"] as? String == "1.1"
                    : record["user_data_model_version"] as? String == "1.0"),
                  payload["account_id"] == nil || payload["account_id"] as? String == MigrationTestPackage.accountID else
            {
                throw Failure.relationships
            }
        }
        let assets = planning["assets"] as! [[String: Any]]
        var seenAssets = Set<String>()
        var seenPaths = Set<String>()
        var usedBlobs = Set<String>()
        for mapping in mappings
        {
            guard Set(mapping.keys) == ["asset_id", "source_path", "blob"],
                  let id = mapping["asset_id"] as? String, let path = mapping["source_path"] as? String,
                  let blob = mapping["blob"] as? String, actual.contains(blob), blob.hasPrefix("Originals/"),
                  seenAssets.insert(id).inserted, seenPaths.insert(path).inserted,
                  LegacyWorkspaceExport.mediaRoots.contains(where: { path.hasPrefix($0 + "/") }),
                  !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  !path.contains("\\"), let asset = assets.first(where: { $0["id"] as? String == id }),
                  let payload = asset["payload"] as? [String: Any], payload["content_state"] as? String == "described" else
            {
                throw Failure.relationships
            }
            let bytes = try MigrationBackupReader.file(blob, in: files)
            let hash = MigrationBackupReader.digest(bytes)
            guard blob == "Originals/" + hash + ".bin", payload["sha256"] as? String == hash,
                  payload["byte_length"] as? String == String(bytes.count) else
            {
                throw Failure.integrity
            }
            usedBlobs.insert(blob)
        }
        guard seenAssets == Set(assets.compactMap { $0["id"] as? String }), usedBlobs == actual.subtracting(["Assembly.json"]) else
        {
            throw Failure.integrity
        }
        let deleted = try PortableLocalDeletions.ids(in: export)
        try references(records: records)
        guard let snapshot = files.serializedRepresentation else
        {
            throw Failure.invalid
        }
        return ReviewedPortablePackage(recordCount: records.count, cardCount: (content["cards"] as! [Any]).count - deleted.count,
            listCount: (content["lists"] as! [Any]).count, mediaCount: seenAssets.count, snapshot: snapshot)
    }


    /// @fcn PortablePackageReview.references
    /// @brief Check parent membership, selections and exact reusable-artwork membership
    /// @param[in] records Unique workspace records
    /// @return Void when core record relationships agree
    /// @throws Invalid core references
    private static func references(records: [[String: Any]]) throws
    {

        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0["id"] as! String, $0) })
        if records.contains(where: { $0["record_type"] as? String == "studio_artwork" }) &&
            !records.contains(where: { $0["record_type"] as? String == "artwork_library" })
        {
            throw Failure.relationships
        }
        for record in records
        {
            let kind = record["record_type"] as? String
            let payload = record["payload"] as! [String: Any]
            for (field, expected) in [("list_ids", "list"), ("card_ids", "card")]
            {
                if let targets = payload[field] as? [String]
                {
                    guard Set(targets).count == targets.count,
                          targets.allSatisfy({ byID[$0]?["record_type"] as? String == expected }) else
                    {
                        throw Failure.relationships
                    }
                }
            }
            if kind == "content_selection"
            {
                guard let card = payload["card_id"] as? String, byID[card]?["record_type"] as? String == "card" else
                {
                    throw Failure.relationships
                }
            }
            if kind == "artwork_library"
            {
                let expected = Set(records.filter { $0["record_type"] as? String == "studio_artwork" }.compactMap { $0["id"] as? String })
                guard let ids = payload["artwork_ids"] as? [String], Set(ids) == expected, Set(ids).count == ids.count else
                {
                    throw Failure.relationships
                }
            }
        }
    }
}
