// --------------------------------------------------------------------------------------------------
// @file       LegacyWorkspaceExport.swift
// @brief      Read-only iOS snapshot with exact preference and original-media preservation
// @details    Supports User Data Model 1.0 migration preparation; source backup format 1.
//             Preserves legacy storage without conversion, restoration, network access or fallback data.
// --------------------------------------------------------------------------------------------------
import CryptoKit
import Foundation


/// Private source backup and human-review metadata, distinct from portable Model 1.0 data.
/// @section Purpose
///     Preserve current source bytes before any future conversion or cloud write.
struct LegacyWorkspaceBackup
{

    let files:       FileWrapper /* Frozen directory ready for the Files exporter */
    let storeCount:  Int         /* Number of captured present preference values  */
    let mediaCount:  Int         /* Number of original media files                */
    let reviewCodes: [String]    /* Bounded issue descriptions without raw values */
}


/// Captures only reviewed local stores and owned media while the main actor prevents UI edits.
/// @section Purpose
///     Establish a recoverable native snapshot boundary without mutating saved content.
@MainActor
enum LegacyWorkspaceExport
{

    static let mediaRoots = [
        "Documents/CardAttachments", "Documents/ProfileAvatars",
        "Library/Application Support/PlenactStudioArtwork",
        "Library/Application Support/PlenactCollectionBackgrounds"
    ] /* Every currently owned original-media area */

    static let maximumBytes = 256 * 1024 * 1024 /* Explicit in-memory export ceiling; never truncate */


    /// Explicit capture failures leave source stores and files untouched.
    /// @section Purpose
    ///     Explain why a consistent, bounded source backup could not be prepared.
    enum Failure: LocalizedError
    {

        case unsafeFile, changedSource, tooLarge, missingDomain

        /// @fcn Failure.errorDescription
        /// @brief Present an actionable local backup error
        /// @return A description containing no source values or private paths
        var errorDescription: String?
        {

            switch self
            {
            case .unsafeFile: return "A media file could not be safely included. Your saved data is unchanged."
            case .changedSource: return "Saved data changed during backup. Please try again after imports finish."
            case .tooLarge: return "This backup exceeds the current 256 MB export limit. Nothing was removed or truncated."
            case .missingDomain: return "The app’s saved preference domain could not be identified."
            }
        }
    }


    /// @fcn LegacyWorkspaceExport.digest
    /// @brief Hash exact bytes rather than decoded media or reconstructed values
    /// @param[in] data Original file bytes
    /// @return Lowercase SHA-256 hexadecimal digest
    private static func digest(_ data: Data) -> String
    {

        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }


    /// @fcn LegacyWorkspaceExport.inventory
    /// @brief Enumerate only regular files beneath reviewed media roots
    /// @details Rejects symlinks in every path component and nonregular media entries.
    /// @param[in] root App container or isolated test container
    /// @return Relative file paths and exact original bytes
    /// @throws Unsafe paths, unreadable files or the explicit size ceiling
    private static func inventory(root: URL) throws -> [String: Data]
    {

        let manager = FileManager.default /* File access stays within the supplied source container */
        var result: [String: Data] = [:]   /* Complete media inventory, including unreferenced originals */
        var size = 0                      /* Running memory bound */
        for area in mediaRoots
        {
            var directory = root
            for component in area.split(separator: "/")
            {
                directory.appendPathComponent(String(component))
                if manager.fileExists(atPath: directory.path)
                {
                    let attributes = try manager.attributesOfItem(atPath: directory.path)
                    guard attributes[.type] as? FileAttributeType == .typeDirectory else
                    {
                        throw Failure.unsafeFile
                    }
                }
                else if (try? manager.destinationOfSymbolicLink(atPath: directory.path)) != nil
                {
                    throw Failure.unsafeFile
                }
            }
            guard manager.fileExists(atPath: directory.path) else
            {
                continue
            }
            let entries = try regularFiles(in: directory)
            for file in entries
            {
                let attributes = try manager.attributesOfItem(atPath: file.path)
                if attributes[.type] as? FileAttributeType == .typeDirectory
                {
                    continue
                }
                guard attributes[.type] as? FileAttributeType == .typeRegular else
                {
                    throw Failure.unsafeFile
                }
                let length = (attributes[.size] as? NSNumber)?.intValue ?? maximumBytes + 1
                guard length <= maximumBytes - size else
                {
                    throw Failure.tooLarge
                }
                let bytes = try Data(contentsOf: file)
                size += bytes.count
                guard size <= maximumBytes else
                {
                    throw Failure.tooLarge
                }
                let relative = String(file.path.dropFirst(root.path.count + 1))
                result[relative] = bytes
            }
        }
        return result
    }


    /// @fcn LegacyWorkspaceExport.regularFiles
    /// @brief Walk owned media with throwing enumeration rather than swallowing directory errors
    /// @param[in] directory Reviewed non-symlink directory
    /// @return Complete regular-file URLs
    /// @throws Unreadable directories, symlinks and special files
    private static func regularFiles(in directory: URL) throws -> [URL]
    {

        var files: [URL] = []
        for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        {
            let attributes = try FileManager.default.attributesOfItem(atPath: child.path)
            switch attributes[.type] as? FileAttributeType
            {
            case .typeDirectory:
                files.append(contentsOf: try regularFiles(in: child))
            case .typeRegular:
                files.append(child)
            default:
                throw Failure.unsafeFile
            }
        }
        return files
    }


    /// @fcn LegacyWorkspaceExport.insert
    /// @brief Insert a reviewed relative path into the export's in-memory directory tree
    /// @param[in] data Exact output bytes
    /// @param[in] path Fixed or enumerated safe relative path
    /// @param[in] directory Destination directory wrapper
    /// @return Void; adds the leaf without writing the source container
    private static func insert(_ data: Data, path: String, directory: FileWrapper)
    {

        let parts = path.split(separator: "/").map(String.init)
        var parent = directory
        for part in parts.dropLast()
        {
            if let existing = parent.fileWrappers?[part]
            {
                parent = existing
            }
            else
            {
                let child = FileWrapper(directoryWithFileWrappers: [:])
                child.preferredFilename = part
                parent.addFileWrapper(child)
                parent = child
            }
        }
        let file = FileWrapper(regularFileWithContents: data)
        file.preferredFilename = parts.last
        parent.addFileWrapper(file)
    }


    /// @fcn LegacyWorkspaceExport.capture
    /// @brief Freeze saved stores and media after pending Board writes finish
    /// @details Main-actor execution prevents UI writes during capture. Double-reading preferences
    ///          and media detects overlapping background imports; a mismatch aborts the whole export.
    ///          Missing stores stay absent and corrupt bytes remain available for recovery.
    /// @param[in] defaults App preferences or an isolated test suite
    /// @param[in] domain Explicit persistent-domain name; registered defaults are excluded
    /// @param[in] root App container or isolated test media container
    /// @return Preserved source backup plus decoder/recovery review results
    /// @throws Source changes, unsafe media, invalid plist or bounded-memory failures
    static func capture(defaults: UserDefaults, domain: String, root: URL) throws -> LegacyWorkspaceBackup
    {

        KanbanBoardPersistence.waitForPendingSaves()
        let migrationURL = root.resolvingSymlinksInPath()
            .appendingPathComponent("Library/Application Support/PlenactMigration/source-identities-v1.json")
        let migrationJournal = try MigrationIdentityStore.read(at: migrationURL)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        let values = original.filter { LegacyStoreValidation.includes($0.key) }
        let preferences = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        guard preferences.count + (migrationJournal?.count ?? 0) <= maximumBytes else
        {
            throw Failure.tooLarge
        }
        var issues: [String] = []
        for key in original.keys.sorted()
        {
            if !LegacyStoreValidation.includes(key)
            {
                if key.hasPrefix("Plenact.") || key.hasPrefix("plenact.")
                {
                    issues.append("unclassified_preference: " + key)
                }
                continue
            }
            if let issue = LegacyStoreValidation.check(key: key, value: original[key]!)
            {
                issues.append(issue + ": " + key)
            }
        }
        let media = try inventory(root: root)
        for (key, value) in values
        {
            guard let data = value as? Data,
                  let json = try? JSONSerialization.jsonObject(with: data) else
            {
                continue
            }
            issues.append(contentsOf: LegacyStoreValidation.mediaIssues(json, store: key, files: Set(media.keys)))
        }
        issues = Array(Set(issues)).sorted()
        guard media.values.reduce(preferences.count + (migrationJournal?.count ?? 0), { $0 + $1.count }) <= maximumBytes else
        {
            throw Failure.tooLarge
        }
        guard NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]),
              media == (try inventory(root: root)),
              migrationJournal == (try MigrationIdentityStore.read(at: migrationURL)) else
        {
            throw Failure.changedSource
        }
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        insert(preferences, path: "Preferences.plist", directory: wrapper)
        if let migrationJournal
        {
            insert(migrationJournal, path: "Migration/IdentityJournal.json", directory: wrapper)
        }
        for (path, bytes) in media
        {
            insert(bytes, path: path, directory: wrapper)
        }
        let manifest: [String: Any] = [
            "format": "plenact.ios-frozen-backup", "format_version": 1,
            "target_user_data_model_version": "1.0", "portable_conversion_complete": false,
            "created_at_utc": ISO8601DateFormatter().string(from: Date()),
            "status": issues.isEmpty ? "source_preserved" : "needs_review",
            "store_count": values.count, "media_count": media.count, "review_codes": issues,
            "preferences_sha256": digest(preferences),
            "migration_journal_sha256": migrationJournal.map { digest($0) } as Any? ?? NSNull(),
            "media": media.keys.sorted().map { ["path": $0, "byte_length": media[$0]!.count,
                "sha256": digest(media[$0]!)] as [String: Any] }
        ]
        insert(try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
            path: "NativePreflight.json", directory: wrapper)
        return LegacyWorkspaceBackup(files: wrapper, storeCount: values.count,
            mediaCount: media.count, reviewCodes: issues)
    }
}
