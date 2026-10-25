// --------------------------------------------------------------------------------------------------
// @file       PortableRichCardExport.swift
// @brief      Verified new originals and personal selections for rich newly created Cards
// @details    Supported User Data Model versions: 1.0 records in working 1.1 test packages.
//             Preserves exact bytes, stable file-derived UUIDs and explicit synthetic ownership; no upload.
// --------------------------------------------------------------------------------------------------
import CryptoKit
import Foundation


/// Extends an immutable import snapshot with frozen new originals before native Card reconstruction.
/// @section Purpose
///     Keep filename translation, integrity metadata and original-byte ownership explicit during export.
@MainActor
enum PortableRichCardExport
{

    /// @fcn PortableRichCardExport.identity
    /// @brief Derive a repeatable UUIDv5 within an explicit retained namespace
    /// @param[in] namespace Existing workspace or account UUID
    /// @param[in] name Qualified immutable source token
    /// @return Stable lowercase UUID
    /// @throws Invalid namespace
    static func identity(namespace: String, name: String) throws -> String
    {

        guard var uuid = UUID(uuidString: namespace)?.uuid else
        {
            throw PortableEditedExport.Failure.inconsistent
        }
        var input = withUnsafeBytes(of: &uuid) { Data($0) }
        input.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = Array(bytes.map { String(format: "%02x", $0) }.joined())
        return String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16])
            + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])
    }


    /// @fcn PortableRichCardExport.enrich
    /// @brief Add exact newly owned files without replacing or dropping any retained original
    /// @param[in] backup Verified current native backup
    /// @param[in] snapshot Original portable members
    /// @param[in] baseline Original verified native placement and canonical identities
    /// @return Reviewed augmented members and explicit source-filename overrides used only for comparison
    /// @throws Changed original, unsafe inventory or unsupported new drawing
    static func enrich(backup: LegacyWorkspaceBackup, snapshot: FileWrapper,
        baseline: PortableWorkspaceCandidate) throws -> (files: FileWrapper, names: [String: String])
    {

        let report = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as! [String: Any]
        let inventory = report["media"] as! [[String: Any]]
        let paths = Set(inventory.map { $0["path"] as! String })
        // A removed attachment may leave no live file. Its exact original remains in the verified snapshot.
        // The caller has already rejected missing live references via the native backup review codes.
        for (path, bytes) in baseline.media.files where paths.contains(path)
        {
            guard try MigrationBackupReader.file(path, in: backup.files) == bytes else
            {
                throw PortablePackageReview.Failure.integrity
            }
        }
        var assembly = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: snapshot)) as! [String: Any]
        var export = assembly["workspace_export"] as! [String: Any]
        var base = export["base_workspace"] as! [String: Any]
        var planning = base["planning"] as! [String: Any]
        var content = planning["content"] as! [String: Any]
        var assets = planning["assets"] as! [[String: Any]]
        var external = content["external_references"] as! [[String: Any]]
        var evidence = assembly["evidence"] as! [String: Any]
        var assetEvidence = evidence["assets"] as! [String: Any]
        var entries = assetEvidence["entries"] as! [[String: Any]]
        var manifest = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Manifest.json", in: snapshot)) as! [String: Any]
        var mappings = manifest["originals"] as! [[String: Any]]
        var blobs = snapshot.fileWrappers!["Originals"]!.fileWrappers!
        var names = baseline.media.filenames
        for path in paths.subtracting(baseline.media.files.keys).sorted()
        {
            let bytes = try MigrationBackupReader.file(path, in: backup.files)
            let hash = MigrationBackupReader.digest(bytes)
            let name = (path as NSString).lastPathComponent
            // PencilKit originals require a paired derivation adapter; never label them as generic files.
            guard (name as NSString).pathExtension.lowercased() != "drawing" else
            {
                throw PortableEditedExport.Failure.unsupported
            }
            let id = try identity(namespace: baseline.workspaceID, name: "new_original:" + path + ":" + hash)
            guard !assets.contains(where: { $0["id"] as? String == id }),
                  !mappings.contains(where: { $0["source_path"] as? String == path }) else
            {
                throw PortableEditedExport.Failure.inconsistent
            }
            let detected = MigrationAssetPreview.signature(bytes)
            let entry: [String: Any] = ["asset_id": id, "source_path": path, "kind": detected.0,
                "mime_type": detected.1, "original_name": name, "content_state": "described",
                "byte_length": String(bytes.count), "sha256": hash, "source_format": NSNull(),
                "derived_from_asset_id": NSNull(), "source_created_at_utc": NSNull(), "attribution": NSNull(),
                "type_evidence": detected.0 == "binary" ? "unknown" : "signature_hint", "references": []]
            var payload = entry
            for key in ["asset_id", "source_path", "type_evidence", "references"]
            {
                payload.removeValue(forKey: key)
            }
            payload["account_id"] = MigrationTestPackage.accountID
            assets.append(["user_data_model_version": "1.0", "payload_schema_version": 1, "record_type": "asset",
                "id": id, "workspace_id": baseline.workspaceID, "payload": payload])
            external.append(["record_type": "asset", "id": id, "status": "external"])
            entries.append(entry)
            let blob = "Originals/" + hash + ".bin"
            mappings.append(["asset_id": id, "source_path": path, "blob": blob])
            blobs[hash + ".bin"] = FileWrapper(regularFileWithContents: bytes)
            names[id] = name
        }
        content["external_references"] = external
        planning["content"] = content
        planning["assets"] = assets
        base["planning"] = planning
        export["base_workspace"] = base
        assembly["workspace_export"] = export
        assetEvidence["entries"] = entries
        evidence["assets"] = assetEvidence
        assembly["evidence"] = evidence
        manifest["originals"] = mappings
        var files: [[String: Any]] = []
        for (name, file) in blobs
        {
            let bytes = file.regularFileContents!
            files.append(["path": "Originals/" + name, "byte_length": bytes.count, "sha256": MigrationBackupReader.digest(bytes)])
        }
        files.append(["path": "Assembly.json", "byte_length": 0, "sha256": ""])
        manifest["files"] = files.sorted { ($0["path"] as! String) < ($1["path"] as! String) }
        let staging = FileWrapper(directoryWithFileWrappers: ["Manifest.json": FileWrapper(regularFileWithContents:
            try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)),
            "Originals": FileWrapper(directoryWithFileWrappers: blobs)])
        return (try PortableLocalDeletions.package(snapshot: staging, assembly: assembly), names)
    }
}
