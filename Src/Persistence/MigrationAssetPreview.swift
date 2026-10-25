// --------------------------------------------------------------------------------------------------
// @file       MigrationAssetPreview.swift
// @brief      Verified original-file links and account-unbound Asset preparation
// @details    Supported User Data Model versions: 1.0. Local preview format 1 only. Original bytes
//             stay in the backup; no account, upload endpoint or authenticated ownership is invented.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Prepares file identities, exact integrity evidence and source-derived drawing relationships.
/// @section Purpose
///     Make attachment recovery reviewable before account-bound canonical Asset publication exists.
@MainActor
enum MigrationAssetPreview
{

    /// Local file evidence with separate verified, unavailable and review counts.
    /// @section Purpose
    ///     Keep file preservation distinct from complete portable conversion or upload success.
    struct Result
    {

        let document:     [String: Any]
        let verifiedCount: Int
        let missingCount:  Int
        let issueCount:    Int
    }


    /// @fcn MigrationAssetPreview.signature
    /// @brief Describe recognized file signatures conservatively without decoding or rewriting bytes
    /// @param[in] bytes Exact preserved file data
    /// @return Kind and MIME where a supported signature is recognized; binary otherwise
    static func signature(_ bytes: Data) -> (String, String)
    {

        let prefix = Array(bytes.prefix(16))
        if prefix.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        {
            return ("image", "image/png")
        }
        if prefix.starts(with: [255, 216, 255])
        {
            return ("image", "image/jpeg")
        }
        if bytes.starts(with: Data("GIF87a".utf8)) || bytes.starts(with: Data("GIF89a".utf8))
        {
            return ("image", "image/gif")
        }
        if prefix.count >= 12, String(bytes: prefix[4..<8], encoding: .ascii) == "ftyp"
        {
            let brand = String(bytes: prefix[8..<12], encoding: .ascii)
            if ["M4A ", "M4B "].contains(brand)
            {
                return ("audio", "audio/mp4")
            }
            if ["heic", "heix", "hevc", "hevx", "mif1"].contains(brand)
            {
                return ("image", "image/heic")
            }
            if brand == "qt  "
            {
                return ("video", "video/quicktime")
            }
            if ["isom", "iso2", "mp41", "mp42", "avc1"].contains(brand)
            {
                return ("video", "video/mp4")
            }
        }
        if prefix.count >= 12, String(bytes: prefix[0..<4], encoding: .ascii) == "RIFF",
           String(bytes: prefix[8..<12], encoding: .ascii) == "WAVE"
        {
            return ("audio", "audio/wav")
        }
        return ("binary", "application/octet-stream")
    }


    /// @fcn MigrationAssetPreview.prepare
    /// @brief Recheck frozen media and link every converted Asset target or preserved original file
    /// @details Missing references retain unavailable evidence; malformed integrity evidence fails closed.
    ///          Local source paths never enter canonical Asset records. Type detection is a signature
    ///          hint, not decoder/playback verification; drawing roles come from native source metadata.
    /// @param[in] backup Verified frozen source backup
    /// @param[in] records Actual converted content and metadata records
    /// @param[in,out] journal Durable original-media identity mappings
    /// @return Local AssetPreview document and UI counts
    /// @throws Invalid evidence, unsafe paths, integrity mismatches or missing identity provenance
    static func prepare(backup: LegacyWorkspaceBackup, records: [[String: Any]],
        journal: inout MigrationIdentityJournal) throws -> Result
    {

        _ = try MigrationBackupReader.values(in: backup)
        let report = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as! [String: Any]
        let media = report["media"] as! [[String: Any]]
        var paths: [String: String] = [:]
        var available: [String: [String: Any]] = [:]
        var usages: [String: [[String: Any]]] = [:]
        var roles: [String: Set<String>] = [:]
        var parents: [String: Set<String>] = [:]
        var issues: Set<String> = []
        for entry in media
        {
            let path = entry["path"] as! String
            let digest = entry["sha256"] as! String
            let id = try journal.resolve(MigrationSourceIdentity(recordType: "asset", owner: "owned_media",
                legacyID: path, discriminator: digest)).uuidString.lowercased()
            paths[id] = path
            available[id] = entry
        }
        let unavailableTargets = records.compactMap { record -> String? in
            guard record["record_type"] as? String == "unavailable_reference",
                  let payload = record["payload"] as? [String: Any], payload["target_type"] as? String == "asset" else
            {
                return nil
            }
            return payload["target_id"] as? String
        }
        for target in unavailableTargets where paths[target] == nil
        {
            guard let source = journal.entries.first(where: { $0.target.uuidString.lowercased() == target })?.source,
                  source.recordType == "asset", source.owner == "owned_media",
                  LegacyWorkspaceExport.mediaRoots.contains(where: { source.legacyID.hasPrefix($0 + "/") }) else
            {
                throw MigrationBackupReader.Failure.invalidBackup
            }
            paths[target] = source.legacyID
        }

        /// @fcn MigrationAssetPreview.walk
        /// @brief Record exact content field paths and roles without interpreting arbitrary writing
        /// @param[in] value Converted structured value
        /// @param[in] record Owning canonical record identity
        /// @param[in] path JSON field path within that record
        /// @return Void; accumulates local source linkage evidence only
        func walk(_ value: Any, record: String, path: String)
        {

            if let object = value as? [String: Any]
            {
                if let image = object["asset_id"] as? String, let drawing = object["drawing_asset_id"] as? String
                {
                    parents[image, default: []].insert(drawing)
                }
                for key in object.keys.sorted()
                {
                    let child = object[key]!
                    let next = path + "/" + key
                    if ["asset_id", "drawing_asset_id", "photo_asset_id", "avatar_asset_id"].contains(key), let asset = child as? String
                    {
                        let role = key == "drawing_asset_id" ? "drawing_original" :
                            (key == "photo_asset_id" ? "appearance_photo" :
                                (key == "avatar_asset_id" ? "profile_avatar" : "attachment_original"))
                        usages[asset, default: []].append(["record_id": record, "field_path": next, "role": role])
                        if role == "drawing_original"
                        {
                            roles[asset, default: []].insert("drawing_original")
                        }
                        else if ["appearance_photo", "profile_avatar"].contains(role)
                        {
                            roles[asset, default: []].insert("image")
                        }
                        else
                        {
                            let kind = object["kind"] as? String
                            roles[asset, default: []].insert(kind == "photo" ? "image" :
                                (["audio", "video"].contains(kind ?? "") ? kind! : "binary"))
                        }
                    }
                    walk(child, record: record, path: next)
                }
            }
            else if let array = value as? [Any]
            {
                for (index, child) in array.enumerated()
                {
                    walk(child, record: record, path: path + "/" + String(index))
                }
            }
        }
        for record in records where record["record_type"] as? String != "unavailable_reference"
        {
            walk(record["payload"]!, record: record["id"] as! String, path: "/payload")
        }
        guard Set(usages.keys).isSubset(of: Set(paths.keys)) else
        {
            throw MigrationBackupReader.Failure.invalidBackup
        }
        var derivations: [String: String] = [:]
        for (child, candidates) in parents
        {
            if candidates.count == 1, let parent = candidates.first, parent != child, paths[parent] != nil
            {
                derivations[child] = parent
            }
            else
            {
                issues.insert("asset_derivation_requires_review:" + child)
            }
        }
        let proposed = derivations
        for child in proposed.keys
        {
            var visited: Set<String> = []
            var current: String? = child
            while let node = current
            {
                if !visited.insert(node).inserted
                {
                    derivations.removeValue(forKey: child)
                    issues.insert("asset_derivation_cycle:" + child)
                    break
                }
                current = proposed[node]
            }
        }
        var entries: [[String: Any]] = []
        for id in paths.keys.sorted()
        {
            let path = paths[id]!
            let filename = String(path.split(separator: "/").last ?? "")
            let stored = available[id]
            let sourceRoles = roles[id] ?? []
            let bytes = try stored.map { _ in try MigrationBackupReader.file(path, in: backup.files) }
            let detected = bytes.map(signature) ?? ("binary", "application/octet-stream")
            let drawing = sourceRoles == ["drawing_original"]
            if sourceRoles.count > 1 || (!drawing && detected.0 != "binary" && !sourceRoles.isEmpty && !sourceRoles.contains(detected.0))
            {
                issues.insert("asset_type_requires_review:" + id)
            }
            if stored == nil
            {
                issues.insert("asset_original_unavailable:" + id)
            }
            let kind = drawing ? "drawing_original" : detected.0
            entries.append(["asset_id": id, "source_path": path, "kind": kind, "mime_type": detected.1,
                "original_name": filename, "content_state": stored == nil ? "unavailable" : "described",
                "byte_length": bytes.map { String($0.count) } as Any? ?? NSNull(),
                "sha256": bytes.map(MigrationBackupReader.digest) as Any? ?? NSNull(),
                "source_format": drawing ? "pencilkit" as Any : NSNull(),
                "derived_from_asset_id": derivations[id] as Any? ?? NSNull(),
                "source_created_at_utc": NSNull(), "attribution": NSNull(),
                "type_evidence": drawing ? "source_role" : (detected.0 == "binary" ? "unknown" : "signature_hint"),
                "references": usages[id] ?? []])
        }
        let document: [String: Any] = ["format": "plenact.ios-asset-preview", "format_version": 1,
            "target_user_data_model_version": "1.0", "account_binding_pending": true,
            "entries": entries, "issues": issues.sorted()]
        return Result(document: document, verifiedCount: available.count,
            missingCount: paths.count - available.count, issueCount: issues.count)
    }
}
