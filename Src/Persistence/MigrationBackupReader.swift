// --------------------------------------------------------------------------------------------------
// @file       MigrationBackupReader.swift
// @brief      Verify frozen source bytes before conversion reads any stored values
// @details    Supported User Data Model versions: 1.0 base and working 1.1 appearance metadata.
//             Private journal formats 1/2/3; local preview only, without authenticated ownership or sync.
// --------------------------------------------------------------------------------------------------
import CryptoKit
import Foundation


/// Validates the native source backup's declared files and hashes before conversion.
/// @section Purpose
///     Keep migration attached to preserved evidence rather than live or modified app storage.
@MainActor
enum MigrationBackupReader
{

    /// Source-integrity errors block conversion without altering originals.
    /// @section Purpose
    ///     Separate invalid snapshot evidence from a legitimate absent source store.
    enum Failure: Error
    {

        case invalidBackup, integrityMismatch, pendingRecovery
    }


    /// @fcn MigrationBackupReader.digest
    /// @brief Hash the original saved bytes using the same native backup convention
    /// @param[in] data Exact source bytes
    /// @return Lowercase SHA-256
    static func digest(_ data: Data) -> String
    {

        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }


    /// @fcn MigrationBackupReader.file
    /// @brief Resolve an explicitly relative regular-file entry without following symlinks
    /// @param[in] path Expected backup path
    /// @param[in] root In-memory source directory
    /// @return Exact regular-file bytes
    /// @throws Invalid paths or missing/nonregular entries
    static func file(_ path: String, in root: FileWrapper) throws -> Data
    {

        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !path.contains("\\") else
        {
            throw Failure.invalidBackup
        }
        var wrapper = root
        for part in parts
        {
            guard wrapper.isDirectory, let child = wrapper.fileWrappers?[String(part)], !child.isSymbolicLink else
            {
                throw Failure.invalidBackup
            }
            wrapper = child
        }
        guard wrapper.isRegularFile, let data = wrapper.regularFileContents else
        {
            throw Failure.invalidBackup
        }
        return data
    }


    /// @fcn MigrationBackupReader.values
    /// @brief Verify native evidence and return only the captured persistent-domain values
    /// @details This is integrity checking, not an authenticated publisher signature or source restore.
    /// @param[in] backup Native preserved source snapshot
    /// @return Exact captured property-list values
    /// @throws Integrity, unsupported evidence or unresolved recovery errors
    static func values(in backup: LegacyWorkspaceBackup) throws -> [String: Any]
    {

        let reportData = try file("NativePreflight.json", in: backup.files)
        guard let report = try JSONSerialization.jsonObject(with: reportData) as? [String: Any],
              report["format"] as? String == "plenact.ios-frozen-backup",
              [1, 2].contains(report["format_version"] as? Int ?? 0),
              report["portable_conversion_complete"] as? Bool == false,
              let issues = report["review_codes"] as? [String],
              let media = report["media"] as? [[String: Any]] else
        {
            throw Failure.invalidBackup
        }
        guard !issues.contains(where: { $0.hasPrefix("pending_recovery_transaction:") }) else
        {
            throw Failure.pendingRecovery
        }
        let portableRuntime = try PortableRuntimeEvidence.backupFiles(report: report, files: backup.files)
        let preferences = try file("Preferences.plist", in: backup.files)
        guard digest(preferences) == report["preferences_sha256"] as? String,
              let values = try PropertyListSerialization.propertyList(from: preferences, format: nil) as? [String: Any],
              values.count == report["store_count"] as? Int,
              media.count == report["media_count"] as? Int else
        {
            throw Failure.integrityMismatch
        }
        if let expected = report["migration_journal_sha256"] as? String
        {
            guard digest(try file("Migration/IdentityJournal.json", in: backup.files)) == expected else
            {
                throw Failure.integrityMismatch
            }
        }
        else if backup.files.fileWrappers?["Migration"] != nil
        {
            throw Failure.invalidBackup
        }
        var seen: Set<String> = []
        for entry in media
        {
            guard let path = entry["path"] as? String, seen.insert(path).inserted,
                  LegacyWorkspaceExport.mediaRoots.contains(where: { path.hasPrefix($0 + "/") }) else
            {
                throw Failure.invalidBackup
            }
            let bytes = try file(path, in: backup.files)
            guard digest(bytes) == entry["sha256"] as? String, bytes.count == entry["byte_length"] as? Int else
            {
                throw Failure.integrityMismatch
            }
        }
        var actual: Set<String> = []
        var total = preferences.count + portableRuntime.values.reduce(0, { $0 + $1.count })
        guard total <= LegacyWorkspaceExport.maximumBytes else
        {
            throw Failure.invalidBackup
        }

        /// @fcn MigrationBackupReader.walkMedia
        /// @brief Reject undeclared or nonregular media entries beneath every owned original-file area
        /// @param[in] wrapper Frozen media subtree
        /// @param[in] path Exact source-relative location
        /// @return Void after collecting bounded regular-file identities
        /// @throws Unsafe, oversized or undeclared source evidence
        func walkMedia(_ wrapper: FileWrapper, path: String) throws
        {

            guard !wrapper.isSymbolicLink else
            {
                throw Failure.invalidBackup
            }
            if wrapper.isDirectory
            {
                for (name, child) in wrapper.fileWrappers ?? [:]
                {
                    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else
                    {
                        throw Failure.invalidBackup
                    }
                    try walkMedia(child, path: path + "/" + name)
                }
            }
            else
            {
                guard wrapper.isRegularFile, let bytes = wrapper.regularFileContents,
                      bytes.count <= LegacyWorkspaceExport.maximumBytes - total else
                {
                    throw Failure.invalidBackup
                }
                total += bytes.count
                actual.insert(path)
            }
        }
        for area in LegacyWorkspaceExport.mediaRoots
        {
            var wrapper: FileWrapper? = backup.files
            for part in area.split(separator: "/")
            {
                guard wrapper?.isSymbolicLink != true, wrapper == nil || wrapper?.isDirectory == true else
                {
                    throw Failure.invalidBackup
                }
                wrapper = wrapper?.fileWrappers?[String(part)]
            }
            if let wrapper
            {
                guard wrapper.isDirectory else
                {
                    throw Failure.invalidBackup
                }
                try walkMedia(wrapper, path: area)
            }
        }
        guard actual == seen else
        {
            throw Failure.integrityMismatch
        }
        return values
    }
}
