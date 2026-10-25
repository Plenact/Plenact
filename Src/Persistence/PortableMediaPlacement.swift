// --------------------------------------------------------------------------------------------------
// @file       PortableMediaPlacement.swift
// @brief      Verified, collision-free native placement plan for portable original files
// @details    Supported User Data Model versions: 1.0 Assets and working 1.1 appearance references.
//             Stages only into a new caller-owned directory. Never replaces active app media areas.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Retains exact original bytes and native filenames independently of the active application container.
/// @section Purpose
///     Prepare and verify every original before the complete-workspace coordinator is allowed to activate it.
@MainActor
struct PortableMediaPlacement
{

    let filenames: [String: String]
    let files:     [String: Data]


    /// @fcn PortableMediaPlacement.prepare
    /// @brief Resolve all originals and native usage areas from a frozen reviewed portable snapshot
    /// @param[in] package Reviewed snapshot; never reads the source backup or live container
    /// @param[in] overrides Export-only safe source filenames; normal imports use canonical UUID filenames
    /// @return Verified filename map and exact bytes for each destination-relative path
    /// @throws Package integrity, missing original or unsupported path errors
    static func prepare(_ package: ReviewedPortablePackage, filenames overrides: [String: String] = [:]) throws -> PortableMediaPlacement
    {

        guard let snapshot = FileWrapper(serializedRepresentation: package.snapshot) else
        {
            throw PortablePackageReview.Failure.invalid
        }
        _ = try PortablePackageReview.review(files: snapshot)
        guard let assembly = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: snapshot)) as? [String: Any],
              let export = assembly["workspace_export"] as? [String: Any], let base = export["base_workspace"] as? [String: Any],
              let planning = base["planning"] as? [String: Any], let assets = planning["assets"] as? [[String: Any]],
              let manifest = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Manifest.json", in: snapshot)) as? [String: Any],
              let mappings = manifest["originals"] as? [[String: Any]] else
        {
            throw PortablePackageReview.Failure.invalid
        }
        var areas: [String: Set<String>] = [:]
        for mapping in mappings
        {
            guard let id = mapping["asset_id"] as? String, let source = mapping["source_path"] as? String,
                  let area = LegacyWorkspaceExport.mediaRoots.first(where: { source.hasPrefix($0 + "/") }) else
            {
                throw PortablePackageReview.Failure.invalid
            }
            // Also retain originals with no active content reference, in their declared owned media area.
            areas[id, default: []].insert(area)
        }

        /// @fcn PortableMediaPlacement.usage
        /// @brief Collect actual canonical file references without interpreting opaque history data
        /// @param[in] value Canonical workspace object or array
        /// @param[in] path Canonical field path used to distinguish background media areas
        /// @return Void after collecting required native areas per Asset
        func usage(_ value: Any, path: String)
        {

            if let object = value as? [String: Any]
            {
                for (key, child) in object
                {
                    if let id = child as? String
                    {
                        let area: String?
                        switch key
                        {
                        case "asset_id", "drawing_asset_id": area = "Documents/CardAttachments"
                        case "avatar_asset_id": area = "Documents/ProfileAvatars"
                        case "photo_asset_id":
                            area = path.contains("/collection_background")
                                ? "Library/Application Support/PlenactCollectionBackgrounds"
                                : "Library/Application Support/PlenactStudioArtwork"
                        default: area = nil
                        }
                        if let area
                        {
                            areas[id, default: []].insert(area)
                        }
                    }
                    usage(child, path: path + "/" + key)
                }
            }
            else if let array = value as? [Any]
            {
                for (index, child) in array.enumerated()
                {
                    usage(child, path: path + "/" + String(index))
                }
            }
        }
        usage(export, path: "")
        var filenames: [String: String] = [:]
        var output: [String: Data] = [:]
        var total = 0
        let available = Set(assets.compactMap { $0["id"] as? String })
        guard Set(areas.keys).isSubset(of: available), Set(overrides.keys).isSubset(of: available),
              overrides.values.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") }) else
        {
            throw PortablePackageReview.Failure.relationships
        }
        for asset in assets
        {
            guard let id = asset["id"] as? String, UUID(uuidString: id) != nil,
                  let payload = asset["payload"] as? [String: Any],
                  let source = mappings.first(where: { $0["asset_id"] as? String == id }),
                  let blob = source["blob"] as? String, let destinations = areas[id], !destinations.isEmpty else
            {
                throw PortablePackageReview.Failure.invalid
            }
            let bytes = try MigrationBackupReader.file(blob, in: snapshot)
            guard payload["sha256"] as? String == MigrationBackupReader.digest(bytes),
                  payload["byte_length"] as? String == String(bytes.count) else
            {
                throw PortablePackageReview.Failure.integrity
            }
            let original = payload["original_name"] as? String ?? ""
            let suffix = (original as NSString).pathExtension.lowercased()
            let safeSuffix = !suffix.isEmpty && suffix.count <= 12 && suffix.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let name = overrides[id] ?? (id.lowercased() + "." + (safeSuffix ? suffix : "bin"))
            filenames[id] = name
            for area in destinations
            {
                let path = area + "/" + name
                guard output[path] == nil, bytes.count <= LegacyWorkspaceExport.maximumBytes - total else
                {
                    throw PortablePackageReview.Failure.invalid
                }
                output[path] = bytes
                total += bytes.count
            }
        }
        return PortableMediaPlacement(filenames: filenames, files: output)
    }


    /// @fcn PortableMediaPlacement.stage
    /// @brief Write a fully verified candidate to a new isolated directory, refusing any existing destination
    /// @param[in] root Fresh staging directory; parent must exist
    /// @return Void after exact disk verification
    /// @throws Existing destination, unsafe plan, disk failure or corruption; partial candidate is removed
    func stage(at root: URL) throws
    {

        let manager = FileManager.default
        guard !manager.fileExists(atPath: root.path), files.keys.allSatisfy({ path in
            guard let area = LegacyWorkspaceExport.mediaRoots.first(where: { path.hasPrefix($0 + "/") }) else
            {
                return false
            }
            let name = String(path.dropFirst(area.count + 1))
            return !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != "." && name != ".."
        }) else
        {
            throw PortablePackageReview.Failure.invalid
        }
        var total = 0
        guard files.count <= 10000 else
        {
            throw PortablePackageReview.Failure.invalid
        }
        for bytes in files.values
        {
            guard bytes.count <= LegacyWorkspaceExport.maximumBytes - total else
            {
                throw PortablePackageReview.Failure.invalid
            }
            total += bytes.count
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var finished = false
        defer
        {
            if !finished
            {
                try? manager.removeItem(at: root)
            }
        }
        for (path, bytes) in files.sorted(by: { $0.key < $1.key })
        {
            let destination = root.appendingPathComponent(path)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: destination, options: [.atomic, .completeFileProtection])
        }
        try verify(at: root)
        finished = true
    }


    /// @fcn PortableMediaPlacement.verify
    /// @brief Verify exact candidate bytes and complete owned-area file inventory without changing files
    /// @param[in] root Candidate staging directory
    /// @return Void after exact byte and inventory checks
    /// @throws Missing, undeclared, nonregular or corrupted files
    func verify(at root: URL) throws
    {

        let manager = FileManager.default
        var actual = Set<String>()
        for area in LegacyWorkspaceExport.mediaRoots
        {
            let base = root.appendingPathComponent(area)
            if !manager.fileExists(atPath: base.path)
            {
                continue
            }
            var component = root
            for part in area.split(separator: "/")
            {
                component.appendPathComponent(String(part))
                guard try manager.attributesOfItem(atPath: component.path)[.type] as? FileAttributeType == .typeDirectory else
                {
                    throw PortablePackageReview.Failure.invalid
                }
            }
            guard let iterator = manager.enumerator(atPath: base.path) else
            {
                throw PortablePackageReview.Failure.invalid
            }
            for case let child as String in iterator
            {
                let url = base.appendingPathComponent(child)
                let kind = try manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
                if kind == .typeDirectory
                {
                    continue
                }
                guard kind == .typeRegular else
                {
                    throw PortablePackageReview.Failure.invalid
                }
                let path = area + "/" + child
                guard let expected = files[path], try Data(contentsOf: url) == expected else
                {
                    throw PortablePackageReview.Failure.integrity
                }
                actual.insert(path)
            }
        }
        guard actual == Set(files.keys) else
        {
            throw PortablePackageReview.Failure.integrity
        }
    }
}
