// --------------------------------------------------------------------------------------------------
// @file       LocalBackupRestore.swift
// @brief      Reviewed Simulator-only recovery of a preserved native source backup
// @details    User Data Model 1.0 preparation; source-backup format 1. Restores legacy source bytes,
//             not portable Model 1.0/cloud data. UI execution requires explicit user confirmation.
// --------------------------------------------------------------------------------------------------
import Foundation
import SwiftUI


/// Retains a verified source snapshot and counts for explicit restore review.
/// @section Purpose
///     Separate selecting/validating files from any destination mutation.
struct ReviewedLocalBackup
{

    let files:      FileWrapper    /* Private immutable snapshot, independent of file-provider changes */
    let values:     [String: Any]  /* Exact source persistent-domain values                            */
    let storeCount: Int            /* Reviewed saved source stores                                    */
    let listCount:  Int            /* Lists in the active Board                                       */
    let cardCount:  Int            /* Active Cards in the active Board                                */
    let mediaCount: Int            /* Verified original files                                         */
    let journal:    Data?          /* Verified retained migration identity evidence                    */
}


/// Performs bounded read/review and a protected local recovery test in a Simulator.
/// @section Purpose
///     Exercise source-backup recovery independently from incomplete portable conversion.
@MainActor
enum LocalBackupRestore
{

    /// User-visible validation failures never authorize source repair or partial installation.
    /// @section Purpose
    ///     Refuse incomplete, inconsistent or unsafe source evidence.
    enum Failure: LocalizedError
    {

        case invalid, unsafe, tooLarge, projectionMismatch, reviewRequired

        /// @fcn Failure.errorDescription
        /// @brief Explain the failed review without exposing private source values
        /// @return Actionable local-only feedback
        var errorDescription: String?
        {

            switch self
            {
            case .invalid: return "This folder is not a supported, complete native source backup."
            case .unsafe: return "The backup contains an unsafe or unsupported file entry."
            case .tooLarge: return "This backup exceeds the current 256 MB review limit."
            case .projectionMismatch: return "The saved Board and current Week need reconciliation before restore."
            case .reviewRequired: return "The backup reports saved data needing review. Restore has not started."
            }
        }
    }


    /// @fcn LocalBackupRestore.readTree
    /// @brief Read a source folder with explicit size, depth and file-kind limits
    /// @param[in] url User-selected source entry
    /// @param[in,out] remaining Remaining byte allowance
    /// @param[in] depth Current directory depth
    /// @return Captured regular file or directory wrapper
    /// @throws Unreadable, unsafe or oversized source entries
    private static func readTree(_ url: URL, remaining: inout Int, depth: Int = 0) throws -> FileWrapper
    {

        guard depth <= 32 else
        {
            throw Failure.unsafe
        }
        let manager = FileManager.default
        let attributes = try manager.attributesOfItem(atPath: url.path)
        let kind = attributes[.type] as? FileAttributeType
        if kind == .typeDirectory
        {
            var children: [String: FileWrapper] = [:]
            for child in try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            {
                children[child.lastPathComponent] = try readTree(child, remaining: &remaining, depth: depth + 1)
            }
            return FileWrapper(directoryWithFileWrappers: children)
        }
        guard kind == .typeRegular else
        {
            throw Failure.unsafe
        }
        guard let length = attributes[.size] as? NSNumber, length.int64Value >= 0,
              length.int64Value <= Int64(remaining) else
        {
            throw Failure.tooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= remaining else
        {
            throw Failure.tooLarge
        }
        remaining -= data.count
        return FileWrapper(regularFileWithContents: data)
    }


    /// @fcn LocalBackupRestore.mediaPaths
    /// @brief Enumerate preserved original files so undeclared media cannot slip through restore
    /// @param[in] wrapper Source directory or regular file
    /// @param[in] prefix Relative source path
    /// @return Every regular-file path under the selected subtree
    /// @throws Unsafe wrapper kinds
    private static func mediaPaths(_ wrapper: FileWrapper, prefix: String) throws -> Set<String>
    {

        if wrapper.isRegularFile
        {
            return [prefix]
        }
        guard wrapper.isDirectory else
        {
            throw Failure.unsafe
        }
        var result: Set<String> = []
        for (name, child) in wrapper.fileWrappers ?? [:]
        {
            result.formUnion(try mediaPaths(child, prefix: prefix + "/" + name))
        }
        return result
    }


    /// @fcn LocalBackupRestore.review
    /// @brief Freeze and verify a selected native backup without changing the app's saved data
    /// @details All declared originals are hash-checked. A consistent active calendar Week is required
    ///          for the current root reload path; source defaults/examples are never loaded.
    /// @param[in] url Folder containing Preferences.plist and NativePreflight.json
    /// @return Fully reviewed source snapshot and human-readable counts
    /// @throws Integrity, native decoding or reconciliation errors
    static func review(at url: URL) throws -> ReviewedLocalBackup
    {

        var remaining = LegacyWorkspaceExport.maximumBytes
        let files = try readTree(url, remaining: &remaining)
        guard files.isDirectory,
              let report = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: files)) as? [String: Any],
              let stores = report["store_count"] as? Int, let media = report["media_count"] as? Int,
              let issues = report["review_codes"] as? [String], issues.isEmpty else
        {
            throw Failure.reviewRequired
        }
        let backup = LegacyWorkspaceBackup(files: files, storeCount: stores, mediaCount: media, reviewCodes: issues)
        let values = try MigrationBackupReader.values(in: backup)
        var actualMedia: Set<String> = []
        for area in LegacyWorkspaceExport.mediaRoots
        {
            var entry: FileWrapper? = files
            for part in area.split(separator: "/")
            {
                entry = entry?.fileWrappers?[String(part)]
            }
            if let entry
            {
                actualMedia.formUnion(try mediaPaths(entry, prefix: area))
            }
        }
        guard let declared = report["media"] as? [[String: Any]],
              Set(declared.compactMap { $0["path"] as? String }) == actualMedia else
        {
            throw Failure.invalid
        }
        for (key, value) in values
        {
            if let data = value as? Data, let json = try? JSONSerialization.jsonObject(with: data),
               !LegacyStoreValidation.mediaIssues(json, store: key, files: actualMedia).isEmpty
            {
                throw Failure.reviewRequired
            }
        }
        guard values.keys.allSatisfy(LegacyStoreValidation.includes),
              values.allSatisfy({ LegacyStoreValidation.check(key: $0.key, value: $0.value) == nil }),
              let boardData = values["Plenact.Board.v1"] as? Data,
              let calendarData = values["Plenact.CalendarWeeks.v1"] as? Data else
        {
            throw Failure.invalid
        }
        let board = try JSONDecoder().decode([KanbanList].self, from: boardData)
        let calendar = try JSONDecoder().decode(PlanningCalendarDocument.self, from: calendarData)
        let current = calendar.weeks.filter { $0.startKey == calendar.currentWeekKey }
        guard calendar.version == 1, (1...7).contains(calendar.firstWeekday),
              Set(calendar.weeks.map(\.startKey)).count == calendar.weeks.count,
              Set(calendar.weeks.map(\.id)).count == calendar.weeks.count,
              current.count == 1, current[0].collection.lists == board else
        {
            throw Failure.projectionMismatch
        }
        var journal: Data?
        if files.fileWrappers?["Migration"] != nil
        {
            journal = try MigrationBackupReader.file("Migration/IdentityJournal.json", in: files)
            _ = try MigrationIdentityJournal.decode(journal!)
        }
        if files.fileWrappers?["MigrationPreview"] != nil
        {
            let data = try MigrationBackupReader.file("MigrationPreview/IdentityJournal.json", in: files)
            let candidate = try MigrationIdentityJournal.decode(data)
            guard let preview = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("MigrationPreview/Report.json", in: files)) as? [String: Any],
                  preview["source_preferences_sha256"] as? String == MigrationBackupReader.digest(try boardPreferences(files)),
                  preview["source_installation_id"] as? String == candidate.sourceInstallationID.uuidString.lowercased(),
                  preview["preview_workspace_id"] as? String == candidate.previewWorkspaceID.uuidString.lowercased(),
                  preview["cloud_account_linked"] as? Bool == false else
            {
                throw Failure.invalid
            }
            if let journal
            {
                let original = try MigrationIdentityJournal.decode(journal)
                let mapped = Dictionary(uniqueKeysWithValues: candidate.entries.map { ($0.source, $0.target) })
                guard original.sourceInstallationID == candidate.sourceInstallationID,
                      original.previewWorkspaceID == candidate.previewWorkspaceID,
                      original.entries.allSatisfy({ mapped[$0.source] == $0.target }) else
                {
                    throw Failure.invalid
                }
            }
            journal = data
        }
        return ReviewedLocalBackup(files: files, values: values, storeCount: stores, listCount: board.count,
            cardCount: board.reduce(0) { $0 + $1.cards.count }, mediaCount: media, journal: journal)
    }


    /// @fcn LocalBackupRestore.boardPreferences
    /// @brief Return already hash-checked source-domain bytes
    /// @param[in] files Reviewed source tree
    /// @return Exact preferences file bytes
    /// @throws Missing source evidence
    private static func boardPreferences(_ files: FileWrapper) throws -> Data
    {

        try MigrationBackupReader.file("Preferences.plist", in: files)
    }


    /// @fcn LocalBackupRestore.install
    /// @brief Install reviewed legacy stores/media inside the caller's rollback-protected transaction
    /// @details Simulator only. Replace reviewed app-owned stores/areas and retain unrelated platform
    ///          values. The caller must first remove the navigation tree and flush queued saves.
    /// @param[in] backup Reviewed immutable source snapshot
    /// @param[in] root Destination app container or isolated fixture container
    /// @param[in] defaults Destination preferences
    /// @param[in] domain Destination persistent-domain name
    /// @return Void after exact preference verification
    /// @throws Unsupported environment, filesystem or persistence failure
    static func install(_ backup: ReviewedLocalBackup, root: URL, defaults: UserDefaults, domain: String) throws
    {

        #if targetEnvironment(simulator)
        let manager = FileManager.default
        for area in LegacyWorkspaceExport.mediaRoots
        {
            let target = root.appendingPathComponent(area)
            if manager.fileExists(atPath: target.path)
            {
                try manager.removeItem(at: target)
            }
            var source: FileWrapper? = backup.files
            for part in area.split(separator: "/")
            {
                source = source?.fileWrappers?[String(part)]
            }
            if let source
            {
                guard source.isDirectory else
                {
                    throw Failure.unsafe
                }
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try source.write(to: target, options: .atomic, originalContentsURL: nil)
            }
        }
        let migration = root.appendingPathComponent("Library/Application Support/PlenactMigration")
        if manager.fileExists(atPath: migration.path)
        {
            try manager.removeItem(at: migration)
        }
        if let journal = backup.journal
        {
            try manager.createDirectory(at: migration, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try journal.write(to: migration.appendingPathComponent("source-identities-v1.json"), options: [.atomic, .completeFileProtection])
        }
        guard let sourceReport = try JSONSerialization.jsonObject(
            with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as? [String: Any],
              let installedMedia = sourceReport["media"] as? [[String: Any]] else
        {
            throw Failure.invalid
        }
        for entry in installedMedia
        {
            guard let path = entry["path"] as? String else
            {
                throw Failure.invalid
            }
            let installed = try Data(contentsOf: root.appendingPathComponent(path))
            guard MigrationBackupReader.digest(installed) == entry["sha256"] as? String else
            {
                throw Failure.invalid
            }
        }
        if let journal = backup.journal
        {
            guard try Data(contentsOf: migration.appendingPathComponent("source-identities-v1.json")) == journal else
            {
                throw Failure.invalid
            }
        }
        var destination = (defaults.persistentDomain(forName: domain) ?? [:]).filter { !LegacyStoreValidation.includes($0.key) }
        destination.merge(backup.values) { _, imported in imported }
        defaults.setPersistentDomain(destination, forName: domain)
        guard defaults.synchronize(), NSDictionary(dictionary: destination).isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]) else
        {
            throw CocoaError(.fileWriteUnknown)
        }
        #else
        throw Failure.invalid
        #endif
    }
}


/// Routes confirmed test recovery through the root's navigation teardown/reload boundary.
/// @section Purpose
///     Prevent a Settings sheet from installing data while old editors can still autosave.
struct LocalBackupRestoreAccess
{

    let restore: (ReviewedLocalBackup) -> Void /* Confirmed restore request */
    let undo:    () -> Void                   /* Explicit recovery of the pre-import workspace */
}


/// Keeps recovery routing absent unless explicitly installed by the app root.
/// @section Purpose
///     Make standalone previews inert rather than mutating storage.
private struct LocalBackupRestoreKey: EnvironmentKey
{

    static let defaultValue: LocalBackupRestoreAccess? = nil
}


extension EnvironmentValues
{

    /// @fcn EnvironmentValues.localBackupRestore
    /// @brief Expose the root-owned explicit restore boundary
    /// @return Optional installed restore callbacks
    var localBackupRestore: LocalBackupRestoreAccess?
    {

        get { self[LocalBackupRestoreKey.self] }
        set { self[LocalBackupRestoreKey.self] = newValue }
    }
}
