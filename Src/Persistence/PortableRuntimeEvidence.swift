// --------------------------------------------------------------------------------------------------
// @file       PortableRuntimeEvidence.swift
// @brief      Preserve portable canonical baselines and aliases in native backup format 2
// @details    Supported User Data Model versions: 1.0 base and working 1.1. Backups retain current
//             native edits alongside the canonical import baseline; fresh portable reconciliation is separate.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Retains the three runtime evidence files so native backups cannot silently drop portable provenance.
/// @section Purpose
///     Keep native recovery usable while the editable canonical export path is being completed.
@MainActor
enum PortableRuntimeEvidence
{

    static let area = "Library/Application Support/PlenactPortableRuntime"
    static let names: Set<String> = ["CanonicalPackage.bin", "IdentityAliases.json", "NativeStores.plist"]


    /// @fcn PortableRuntimeEvidence.capture
    /// @brief Read an exact bounded runtime evidence inventory or preserve genuine absence
    /// @param[in] root App container or isolated synthetic container
    /// @return Evidence bytes keyed by filename
    /// @throws Unsafe, incomplete, oversized or invalid evidence
    static func capture(root: URL) throws -> [String: Data]
    {

        let directory = root.appendingPathComponent(area)
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path)
        {
            return [:]
        }
        var remaining = LegacyWorkspaceExport.maximumBytes
        let files = try LocalBackupRestore.readTree(directory, remaining: &remaining)
        guard files.isDirectory, Set(files.fileWrappers?.keys.map { $0 } ?? []) == names else
        {
            throw PortablePackageReview.Failure.invalid
        }
        let bytes = try Dictionary(uniqueKeysWithValues: names.map { name in
            (name, try MigrationBackupReader.file(name, in: files))
        })
        try validate(bytes)
        return bytes
    }


    /// @fcn PortableRuntimeEvidence.validate
    /// @brief Check canonical package, identity aliases and baseline native stores as one supported evidence set
    /// @param[in] bytes Exact retained evidence files
    /// @return Void after closed-shape, package and store checks
    /// @throws Inconsistent or unsupported evidence
    private static func validate(_ bytes: [String: Data]) throws
    {

        guard let snapshot = bytes["CanonicalPackage.bin"].flatMap(FileWrapper.init(serializedRepresentation:)),
              let aliases = try JSONSerialization.jsonObject(with: bytes["IdentityAliases.json"]!) as? [String: Any],
              Set(aliases.keys) == ["format_version", "workspace_id", "time_zone", "numeric_ids"],
              aliases["format_version"] as? Int == 1,
              let ids = aliases["numeric_ids"] as? [String: Int], Set(ids.values).count == ids.count,
              ids.keys.allSatisfy({ UUID(uuidString: $0) != nil }), ids.values.allSatisfy({ $0 > 0 }),
              (try PropertyListSerialization.propertyList(from: bytes["NativeStores.plist"]!, format: nil)) is [String: Any] else
        {
            throw PortablePackageReview.Failure.invalid
        }
        _ = try PortablePackageReview.review(files: snapshot)
    }


    /// @fcn PortableRuntimeEvidence.backupFiles
    /// @brief Verify optional version-two backup evidence before it can be restored
    /// @param[in] report Native preflight report
    /// @param[in] files Frozen native source backup
    /// @return Exact evidence bytes, empty only for a supported version-one backup
    /// @throws Unsupported version, unsafe inventory or checksum mismatch
    static func backupFiles(report: [String: Any], files: FileWrapper) throws -> [String: Data]
    {

        if report["format_version"] as? Int == 1
        {
            guard files.fileWrappers?["PortableRuntime"] == nil, report["portable_runtime_files"] == nil else
            {
                throw PortablePackageReview.Failure.invalid
            }
            return [:]
        }
        guard report["format_version"] as? Int == 2, let entries = report["portable_runtime_files"] as? [[String: Any]],
              entries.count == names.count, let directory = files.fileWrappers?["PortableRuntime"], directory.isDirectory,
              Set(directory.fileWrappers?.keys.map { $0 } ?? []) == names else
        {
            throw PortablePackageReview.Failure.invalid
        }
        var output: [String: Data] = [:]
        for entry in entries
        {
            guard Set(entry.keys) == ["name", "sha256", "byte_length"], let name = entry["name"] as? String,
                  names.contains(name), output[name] == nil else
            {
                throw PortablePackageReview.Failure.invalid
            }
            let bytes = try MigrationBackupReader.file(name, in: directory)
            guard entry["sha256"] as? String == MigrationBackupReader.digest(bytes), entry["byte_length"] as? Int == bytes.count else
            {
                throw PortablePackageReview.Failure.integrity
            }
            output[name] = bytes
        }
        try validate(output)
        return output
    }
}
