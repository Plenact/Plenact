// --------------------------------------------------------------------------------------------------
// @file       FullMonthExamples.swift
// @brief      Verified workspace backup, restoration and Simulator portable import recovery
// @details    Supported User Data Model versions: 1.0 base and working 1.1; native backup formats 1/2.
//             Builds dated sample content and maintains verified user-data backups around explicit
//             example loading and restoration.
//
// --------------------------------------------------------------------------------------------------
import CryptoKit
import SwiftUI


// Full-month examples use a separate, verified offline snapshot of the entire local workspace.


///
/// Manages reversible full-month example workspace transitions
///
/// @section    Purpose
///     Keeps user-data backups, transition files, and preference domains separate so loading
///     examples can preserve a recoverable workspace.
///
struct FullMonthExampleStore: Sendable
{


    let root:             URL
    let documents:        URL
    let support:          URL
    let domainName:       String
    private var defaults: UserDefaults
    {

        domainName == Bundle.main.bundleIdentifier ? .standard : UserDefaults(suiteName: domainName)!
    }

    private var userData: URL
    {
        root.appendingPathComponent("UserData", isDirectory: true)
    }

    private var transition: URL
    {
        root.appendingPathComponent("Transition", isDirectory: true)
    }

    private var fm: FileManager
    {
        .default
    }


    ///
    /// Describes a versioned example-workspace backup
    ///
    /// @section    Purpose
    ///     Records creation time and file hashes used to verify retained backup content before
    ///     restoration.
    ///
    private struct Manifest: Codable
    {


        var version = 1
        var createdAt = Date()
        let hashes: [String: String]
    }


    ///
    /// @fcn        FullMonthExampleStore.live
    /// @brief      Locate the application's live example backup directories
    /// @details    Resolves the Library, Documents, and Application Support locations and uses the application's
    ///             preferences domain for backup and restoration.
    ///
    /// @return     (FullMonthExampleStore) constructed value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    static func live() throws -> Self
    {

        let fm = FileManager.default
        let library = try fm.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return Self(
            root: library.appendingPathComponent("PlenactDatasetBackup", isDirectory: true),
            documents: try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
            support: try fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
            domainName: Bundle.main.bundleIdentifier!)
    }

    var needsRecovery: Bool
    {
        fm.fileExists(atPath: transition.path) && committedOperation() == nil
    }

    var hasUserData: Bool
    {

        fm.fileExists(atPath: userData.path) && committedOperation() != "restore"
    }


    ///
    /// @fcn        FullMonthExampleStore.committedOperation
    /// @brief      Read the completed dataset-switch marker
    /// @details    Returns the marker text when readable and nil when no readable commit marker exists.
    ///
    /// @return     (String?) readable committed-operation marker, or nil if unavailable
    ///
    private func committedOperation() -> String?
    {

        try? String(contentsOf: transition.appendingPathComponent("Committed"), encoding: .utf8)
    }


    ///
    /// @fcn        FullMonthExampleStore.digest
    /// @brief      Hash a backup file without loading it entirely into memory
    /// @details    Streams the file in one-megabyte chunks through SHA-256 and closes the handle even if reading
    ///             fails.
    ///
    /// @param[in]  url  File URL for the requested audio resource
    ///
    /// @return     (String) lowercase hexadecimal SHA-256 digest of the file's bytes
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    private func digest(_ url: URL) throws -> String
    {

        // Stream large attachments rather than loading an entire video into memory.
        let handle = try FileHandle(forReadingFrom: url)
        defer
        {
            try? handle.close()
        }

        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty
        {
            hash.update(data: data)
        }

        return hash.finalize().map
        {
            String(format: "%02x", $0)
        } .joined()
    }


    ///
    /// @fcn        FullMonthExampleStore.hashes
    /// @brief      Build a relative-path checksum inventory of a backup
    /// @details    Enumerates regular files, rejects symbolic links, and propagates enumeration and file-reading
    ///             failures.
    ///
    /// @param[in]  directory  Backup directory to enumerate, decode, or verify
    ///
    /// @return     ([String: String]) relative file paths mapped to their SHA-256 checksums
    /// @throws     Explicit failures include `CocoaError(.fileReadUnknown)`,
    ///             `CocoaError(.fileReadUnsupportedScheme)`, `enumerationError`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    private func hashes(in directory: URL) throws -> [String: String]
    {

        var result: [String: String] = [:]
        var enumerationError: Error?
        guard
        let entries = fm.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            errorHandler:
            {
                _, error in
                enumerationError = error;
                return false
            })
        else
        {

            throw CocoaError(.fileReadUnknown)
        }

        for case let url as URL in entries
        {

            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else
            {
                throw CocoaError(.fileReadUnsupportedScheme)
            }

            if values.isRegularFile == true
            {

                let key = String(url.path.dropFirst(directory.path.count + 1))
                if key != "Manifest.json"
                {
                    result[key] = try digest(url)
                }

            }

        }

        if let enumerationError
        {
            throw enumerationError
        }

        return result
    }


    ///
    /// @fcn        FullMonthExampleStore.verify
    /// @brief      Validate a backup before installation or recovery
    /// @details    Requires the supported manifest version, matching file checksums, and a readable saved preferences
    ///             dictionary.
    ///
    /// @param[in]  directory  Backup directory to enumerate, decode, or verify
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    private func verify(_ directory: URL) throws
    {

        let manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("Manifest.json")))
        guard manifest.version == 1, try hashes(in: directory) == manifest.hashes else
        {

            throw CocoaError(.fileReadCorruptFile)
        }

        _ = try savedDomain(in: directory)
    }


    ///
    /// @fcn        FullMonthExampleStore.savedDomain
    /// @brief      Decode the backed-up application preferences domain
    /// @details    Reads Defaults.plist and requires a string-keyed property-list dictionary; other contents are
    ///             treated as corrupt.
    ///
    /// @param[in]  directory  Backup directory to enumerate, decode, or verify
    ///
    /// @return     ([String: Any]) decoded string-keyed application preferences dictionary
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    private func savedDomain(in directory: URL) throws -> [String: Any]
    {

        let data = try Data(contentsOf: directory.appendingPathComponent("Defaults.plist"))
        guard let domain = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else
        {

            throw CocoaError(.fileReadCorruptFile)
        }

        return domain
    }


    ///
    /// @fcn        FullMonthExampleStore.capture
    /// @brief      Capture a verified snapshot of files and preferences
    /// @details    Builds the snapshot in a temporary staging directory, synchronizes preferences, and retains
    ///             cleanup for failures before publishing the backup.
    ///
    /// @param[in]  destination  Backup destination directory for the verified snapshot
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    private func capture(to destination: URL) throws
    {

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer
        {
            try? fm.removeItem(at: staging)
        }

        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        guard defaults.synchronize() else
        {
            throw CocoaError(.fileWriteUnknown)
        }

        let domain = defaults.persistentDomain(forName: domainName) ?? [:]
        let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
        try data.write(to: staging.appendingPathComponent("Defaults.plist"), options: .atomic)
        for (name, source) in [("Documents", documents), ("ApplicationSupport", support)]
        {

            let target = staging.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: source.path)
            {

                try fm.copyItem(at: source, to: target)
            }
            else
            {

                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            }

        }

        let manifest = Manifest(hashes: try hashes(in: staging))
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("Manifest.json"), options: .atomic)
        try verify(staging)
        try fm.moveItem(at: staging, to: destination)
        var local = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try local.setResourceValues(values)
    }


    ///
    /// @fcn        FullMonthExampleStore.setDomain
    /// @brief      Replace and verify the application preferences domain
    /// @details    Synchronizes after writing and compares the stored dictionary with the requested value; a failed
    ///             write or mismatch throws.
    ///
    /// @param[in]  domain  Complete application preferences dictionary to install and verify
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    private func setDomain(_ domain: [String: Any]) throws
    {

        defaults.setPersistentDomain(domain, forName: domainName)
        guard defaults.synchronize(),
        NSDictionary(dictionary: defaults.persistentDomain(forName: domainName) ?? [:]).isEqual(to: domain)
        else
        {

            throw CocoaError(.fileWriteUnknown)
        }

    }


    ///
    /// @fcn        FullMonthExampleStore.installFiles
    /// @brief      Install backed-up Documents and Application Support trees
    /// @details    Copies each immutable snapshot tree through staging before replacing its live directory, allowing
    ///             interrupted installation to be retried from the snapshot.
    ///
    /// @param[in]  snapshot  Snapshot values or directory used for the operation
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    private func installFiles(from snapshot: URL) throws
    {

        // Each immutable source survives interrupted installation and can be retried at launch.
        for (name, target) in [("Documents", documents), ("ApplicationSupport", support)]
        {

            let staged = root.appendingPathComponent("install-" + UUID().uuidString, isDirectory: true)
            defer
            {
                try? fm.removeItem(at: staged)
            }

            try fm.copyItem(at: snapshot.appendingPathComponent(name), to: staged)
            if fm.fileExists(atPath: target.path)
            {
                try fm.removeItem(at: target)
            }

            try fm.moveItem(at: staged, to: target)
        }

    }


    ///
    /// @fcn        FullMonthExampleStore.finishCommitted
    /// @brief      Clean up a successfully committed dataset transition
    /// @details    Removes the retained user backup after a completed restore and deletes the transition directory.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    private func finishCommitted() throws
    {

        if committedOperation() == "restore", fm.fileExists(atPath: userData.path)
        {
            try fm.removeItem(at: userData)
        }

        if committedOperation() == "native_restore_undo"
        {
            let previous = root.appendingPathComponent("BeforeNativeRestore")
            if fm.fileExists(atPath: previous.path)
            {
                try fm.removeItem(at: previous)
            }
        }
        if committedOperation() == "portable_import_undo"
        {
            let previous = root.appendingPathComponent("BeforePortableImport")
            if fm.fileExists(atPath: previous.path)
            {
                try fm.removeItem(at: previous)
            }
        }
        try fm.removeItem(at: transition)
    }


    ///
    /// @fcn        FullMonthExampleStore.recoverInterruptedSwitch
    /// @brief      Recover or finish an interrupted dataset transition
    /// @details    Finishes committed cleanup or verifies and reinstalls the transition snapshot and preferences
    ///             before removing its journal directory.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    /// @note       Run before constructing any view or loading any saved model after an interrupted switch.
    ///
    func recoverInterruptedSwitch() throws
    {

        guard fm.fileExists(atPath: transition.path) else
        {
            return
        }

        if committedOperation() != nil
        {
            try finishCommitted();
            return
        }

        try verify(transition)
        try installFiles(from: transition)
        try setDomain(savedDomain(in: transition))
        try fm.removeItem(at: transition)
    }


    ///
    /// @fcn        FullMonthExampleStore.loadExample
    /// @brief      Load the full-month example while retaining user data
    /// @details    Recovers interrupted work first, captures the original user backup only when absent, verifies it,
    ///             and journals the preferences switch before marking it committed.
    ///
    /// @param[in]  example  Bundled example content or dataset to use
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func loadExample(_ example: FullMonthExample) throws
    {

        try recoverInterruptedSwitch()
        if !hasUserData
        {
            try capture(to: userData)
        }

        try verify(userData)
        let domain = try example.defaultsDomain(preserving: defaults.persistentDomain(forName: domainName) ?? [:])
        try capture(to: transition)
        do
        {

            try setDomain(domain)
            try Data("load".utf8).write(to: transition.appendingPathComponent("Committed"), options: .atomic)
        }
        catch
        {

            try recoverInterruptedSwitch()
            throw error
        }

        try? finishCommitted()
    }


    /// @fcn FullMonthExampleStore.hasPortableImportBackup
    /// @brief Identify retained recovery data from a confirmed editable portable import
    /// @return Whether the pre-import workspace can be restored
    var hasPortableImportBackup: Bool
    {

        fm.fileExists(atPath: root.appendingPathComponent("BeforePortableImport").path)
    }


    /// @fcn FullMonthExampleStore.installPortableWorkspace
    /// @brief Preserve current data and execute a confirmed portable activation inside the recovery journal
    /// @param[in] install Native installation and root reload checks
    /// @return Void after commit, retaining the prior full workspace for undo
    /// @throws Capture, install, reload or recovery failures
    func installPortableWorkspace(_ install: () throws -> Void) throws
    {

        try recoverInterruptedSwitch()
        guard !hasPortableImportBackup else
        {
            throw CocoaError(.fileWriteFileExists)
        }
        let previous = root.appendingPathComponent("BeforePortableImport")
        try capture(to: previous)
        do
        {
            try capture(to: transition)
            try install()
            try Data("portable_import".utf8).write(to: transition.appendingPathComponent("Committed"), options: .atomic)
        }
        catch
        {
            let failure = error
            try recoverInterruptedSwitch()
            try? fm.removeItem(at: previous)
            throw failure
        }
        try? finishCommitted()
    }


    /// @fcn FullMonthExampleStore.undoPortableWorkspace
    /// @brief Restore the full retained pre-import workspace through the existing recovery journal
    /// @return Void after verified restore and committed cleanup
    /// @throws Missing backup, verification, persistence or recovery errors
    func undoPortableWorkspace() throws
    {

        try recoverInterruptedSwitch()
        let previous = root.appendingPathComponent("BeforePortableImport")
        guard fm.fileExists(atPath: previous.path) else
        {
            throw CocoaError(.fileNoSuchFile)
        }
        try verify(previous)
        let history = root.appendingPathComponent("PortableImportHistory", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try capture(to: history)
        try capture(to: transition)
        do
        {
            try installFiles(from: previous)
            try setDomain(savedDomain(in: previous))
            try Data("portable_import_undo".utf8).write(to: transition.appendingPathComponent("Committed"), options: .atomic)
        }
        catch
        {
            try recoverInterruptedSwitch()
            throw error
        }
        try finishCommitted()
    }


    ///
    /// @fcn FullMonthExampleStore.hasNativeRestoreBackup
    /// @brief Identify retained pre-import recovery evidence
    /// @return True when a prior Simulator restore has an undo snapshot
    var hasNativeRestoreBackup: Bool
    {

        fm.fileExists(atPath: root.appendingPathComponent("BeforeNativeRestore").path)
    }


    /// @fcn FullMonthExampleStore.installNativeSource
    /// @brief Retain the destination and journal a user-confirmed source recovery test
    /// @param[in] install Reviewed source installation, executed inside the recoverable boundary
    /// @return Void after commit; the pre-import workspace remains available for undo
    /// @throws Capture, installation or recovery errors
    func installNativeSource(_ install: () throws -> Void) throws
    {

        try recoverInterruptedSwitch()
        guard !hasNativeRestoreBackup else
        {
            throw CocoaError(.fileWriteFileExists)
        }
        try capture(to: root.appendingPathComponent("BeforeNativeRestore"))
        try capture(to: transition)
        do
        {
            try install()
            try Data("native_restore".utf8).write(to: transition.appendingPathComponent("Committed"), options: .atomic)
        }
        catch
        {
            try recoverInterruptedSwitch()
            throw error
        }
        try? finishCommitted()
    }


    /// @fcn FullMonthExampleStore.undoNativeSource
    /// @brief Restore the verified pre-import destination rather than guessing inverse mutations
    /// @return Void after recovery and retained-backup cleanup
    /// @throws Verification, persistence or rollback errors
    func undoNativeSource() throws
    {

        try recoverInterruptedSwitch()
        let previous = root.appendingPathComponent("BeforeNativeRestore")
        try verify(previous)
        try capture(to: transition)
        do
        {
            try installFiles(from: previous)
            try setDomain(savedDomain(in: previous))
            try Data("native_restore_undo".utf8).write(to: transition.appendingPathComponent("Committed"), options: .atomic)
        }
        catch
        {
            try recoverInterruptedSwitch()
            throw error
        }
        try finishCommitted()
    }


    ///
    /// @fcn        FullMonthExampleStore.restoreUserData
    /// @brief      Restore the verified original user dataset
    /// @details    Requires a retained backup, journals the current state, reinstalls files and preferences, and
    ///             attempts transition recovery if installation fails.
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileNoSuchFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    func restoreUserData() throws
    {

        try recoverInterruptedSwitch()
        guard hasUserData else
        {
            throw CocoaError(.fileNoSuchFile)
        }

        try verify(userData)
        try capture(to: transition)
        do
        {

            try installFiles(from: userData)
            try setDomain(savedDomain(in: userData))
            try Data("restore".utf8).write(to: transition.appendingPathComponent("Committed"), options: .atomic)
        }
        catch
        {

            try recoverInterruptedSwitch()
            throw error
        }

        try? finishCommitted()
    }

}


///
/// Builds a synthetic month of planning examples
///
/// @section    Purpose
///     Keeps dated calendar Weeks and personal collections together as a generated snapshot rather
///     than mutating the live workspace.
///
struct FullMonthExample: Sendable
{


    let document:    PlanningCalendarDocument
    let collections: [PersonalCollection]


    ///
    /// @fcn        FullMonthExample.make
    /// @brief      Create a full month of calendar-backed demonstration content
    /// @details    Builds dated weeks and examples around the reference month using the supplied calendar, with
    ///             deterministic relationships among their lists and cards.
    ///
    /// @param[in]  now       Reference time used instead of an implicit clock read
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (FullMonthExample) constructed value
    ///
    static func make(now: Date = .now, calendar: Calendar = .current) -> Self
    {

        let today = calendar.startOfDay(for: now)
        let month = calendar.dateInterval(of: .month, for: today)!
        let days = calendar.range(of: .day, in: .month, for: today)!
        var document = PlanningCalendarDocument(
            currentWeekKey: PlanningDate.weekKey(today, calendar: calendar),
            firstWeekday: calendar.firstWeekday, weeks: [])
        var nextID = 0
        for offset in 0 ..< days.count
        {

            let date = calendar.date(byAdding: .day, value: offset, to: month.start)!
            var week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: calendar)
            let listID = week.dayListIDs[PlanningDate.key(date, calendar: calendar)]!
            let index = week.collection.lists.firstIndex
            {
                $0.id == listID
            }!
            let past = date < today
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let count = past ? 3 + offset % 3 : (isToday ? 4 : (offset % 4 == 0 ? 1 : 0))
            let titles = SampleData.cardTitlesByDay[(calendar.component(.weekday, from: date) + 5) % 7]
            week.collection.lists[index].cards = (0 ..< count).map
            {
                item in
                let timed = item == 1 || (!past && !isToday)
                let start = calendar.date(bySettingHour: 9 + item * 2, minute: 0, second: 0, of: date)!
                let end = calendar.date(byAdding: .minute, value: 45, to: start)!
                let note = item == 3
                let card = KanbanCard(
                    id: nextID, word: note ? "A moment from today" : titles[item % titles.count],
                    listTitle: week.collection.lists[index].title,
                    isTitleChecked: (past && item != 2) || (isToday && item == 0),
                    startDate: timed ? start : nil, dueDate: timed ? end : date,
                    checklists: item == 0
                    ? [
                        KanbanChecklist(
                            title: "Small steps",
                            items: ["Choose a starting point", "Take the next step", "Review the result"])
                    ] : [],
                    members: [], labelIDs: [LabelLibrary.starterLabelIDs[item % LabelLibrary.starterLabelIDs.count]],
                    attachments: [],
                    descriptionOverride: note
                    ? "A little progress, a useful discovery, and room to begin again tomorrow.\n\nThis is fictional example content."
                    : "One manageable step toward a calmer, more intentional day. Example content you can edit freely.",
                    subtitleOverride: "", presentation: note ? .note : .card, createdAt: date,
                    startDateKind: timed ? .dateAndTime : .date, dueDateKind: timed ? .dateAndTime : .date)
                nextID += 1
                return card
            }

            if let bookmark = week.collection.lists[index].cards.first(where:
                {

                    !$0.isTitleChecked && $0.dueDateKind == .date && !$0.isSectionDivider
                })
            {

                week.collection.savedCardIDs.insert(bookmark.id)
            }

            document.upsert(week)
        }

        // Example Library content is independent of every dated week.
        let collections = [PersonalListExample.onTheTable, .inTheQueue, .scheduled].map
        {

            $0.makeCollection(existingTitles: [])
        }

        return Self(document: document, collections: collections)
    }

    var previewLists: [KanbanList]
    {

        document.weeks.enumerated().flatMap
        {
            weekIndex, week in
            week.collection.lists.enumerated().compactMap
            {
                listIndex, list in
                guard !list.cards.isEmpty else
                {
                    return nil
                }

                let key = week.dayListIDs.first
                {
                    $0.value == list.id
                }?.key
                let date = key.flatMap
                {
                    PlanningDate.date($0, calendar: document.calendar)
                }

                let title =
                date.map
                {
                    PlanningDate.listTitle(list.title, on: $0, calendar: document.calendar)
                }
                ?? list.title
                return KanbanList(id: weekIndex * 100 + listIndex, title: title, cards: list.cards)
            }

        }

    }


    ///
    /// @fcn        FullMonthExample.defaultsDomain
    /// @brief      Build the example dataset's preferences dictionary
    /// @details    Encodes the generated calendar, collections, bookmarks, and importance data while retaining
    ///             platform preferences, Focus choices, and the user's optional lower-corner Back setting.
    ///
    /// @param[in]  original  Original preferences domain retained for comparison or transformation
    ///
    /// @return     ([String: Any]) preferences domain containing the generated example and supported preserved
    ///             choices
    /// @throws     Explicit failures include `CocoaError(.coderInvalidValue)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    func defaultsDomain(preserving original: [String: Any]) throws -> [String: Any]
    {

        guard let current = document.weeks.first(where:
            {
                $0.startKey == document.currentWeekKey
            }) else
        {

            throw CocoaError(.coderInvalidValue)
        }

        // Keep non-Plenact platform preferences; all app-owned data/settings remain in the backup.
        var result = original.filter
        {
            !$0.key.hasPrefix("Plenact.")
        }

        let encoder = JSONEncoder()
        result[PlanningCalendarStore.key] = try encoder.encode(document)
        result["Plenact.Board.v1"] = try encoder.encode(current.collection.lists)
        result["Plenact.PersonalCollections.v1"] = try encoder.encode(collections)
        result["Plenact.SavedCardIDs.v1"] = Array(current.collection.savedCardIDs).sorted()
        var importance = LibraryImportanceSelection.demoData(in: document.weeks.map(\.collection) + collections)
        for week in document.weeks
        {

            for list in week.collection.lists
            {

                if let card = list.cards.first(where:
                    {
                        !$0.isTitleChecked && $0.displayFormat == .card
                    })
                {

                    importance = LibraryImportanceSelection.setting(
                        cardID: card.id, collectionID: week.id, marked: true, data: importance)
                }

            }

        }

        result[LibraryImportanceSelection.key] = importance
        let savedPreferences =
        (original[PlanPreferencesStore.key] as? Data).flatMap
        {

            try? JSONDecoder().decode(LocalProfilePreferences.self, from: $0)
        }

        ?? (original[LocalProfileStore.storageKey] as? Data).flatMap
        {

            try? JSONDecoder().decode(LocalProfile.self, from: $0)
        }?.preferences
        if let existing = savedPreferences
        {

            var preferences = LocalProfilePreferences()
            preferences.enablesLowerCornerBack = existing.enablesLowerCornerBack
            preferences.importanceStarStyle = existing.importanceStarStyle
            preferences.todayFocusIncludesImportant = existing.todayFocusIncludesImportant
            preferences.todayFocusIncludesBookmarked = existing.todayFocusIncludesBookmarked
            preferences.todayFocusIncludesUpNext = existing.todayFocusIncludesUpNext
            preferences.todayFocusHidesCompleted = existing.todayFocusHidesCompleted
            preferences.todayFocusGroupsBySection = existing.todayFocusGroupsBySection
            preferences.todayFocusOrder = existing.todayFocusOrder
            preferences.keepsDayListsInTimeOrder = existing.keepsDayListsInTimeOrder
            preferences.preferredMapsApp = existing.preferredMapsApp
            preferences.todayFocusItemCount = existing.todayFocusItemCount
            result[PlanPreferencesStore.key] = try encoder.encode(preferences)
        }

        result[TodayListPins.key] = TodayListPins.encode(
            collections.map
            {
                WorkspaceListReference(ownerID: $0.id, listID: $0.lists[0].id)
            })
        return result
    }

}
