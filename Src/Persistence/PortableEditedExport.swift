// --------------------------------------------------------------------------------------------------
// @file       PortableEditedExport.swift
// @brief      Reconcile supported editable Card changes with their retained canonical identities
// @details    Supported User Data Model versions: 1.0 base and working 1.1. Simulator test packages only.
//             Refuses unsupported edits and changed originals; never changes the active workspace or baseline.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Produces a new reviewed package while preserving unmapped canonical values and original bytes.
/// @section Purpose
///     Establish a reversible edit/export/import path without treating native numeric IDs as global identities.
@MainActor
enum PortableEditedExport
{

    static let fields = ["word": "title", "descriptionOverride": "description_override",
        "subtitleOverride": "subtitle_override", "isTitleChecked": "completed", "editingLocked": "editing_locked",
        "showsDueDateInList": "shows_due_date_in_list", "showsReactionsInPreviews": "shows_reactions_in_previews"]

    static let scheduleFields: Set<String> = ["startDate", "dueDate", "startDateKind", "dueDateKind"]

    /// Explains unsupported changes without exposing private content.
    /// @section Purpose
    ///     Prevent an apparently successful package from omitting an unconverted edit.
    enum Failure: LocalizedError
    {

        case unsupported, inconsistent, structureChanged

        /// @fcn Failure.errorDescription
        /// @brief Describe the limited editable export boundary
        /// @return Actionable guidance with no source values
        var errorDescription: String?
        {

            switch self
            {
            case .unsupported:
                return "This export supports Board-created Cards and Lists, same-Board movement and reordering, plus Card text, completion, scheduling, deletion and history. Another saved change needs an export adapter. Your local backup can preserve all changes."
            case .structureChanged:
                return "These structural changes cannot yet be exported safely. Creation in Board views, movement within the same Board and reordering are supported; cross-Board transfers and List deletion still need support. Your title, time and other saved changes remain intact; a local backup preserves the complete workspace."
            case .inconsistent:
                return "The retained import evidence or saved Card copies disagree. No package was prepared. Your workspace is unchanged."
            }
        }
    }


    /// @fcn PortableEditedExport.nativeJSON
    /// @brief Normalize explicitly unordered native Set encodings while preserving authored array order
    /// @param[in] bytes Native Codable store bytes
    /// @param[in] store Optional store family for explicit legacy importance-level comparison
    /// @return Comparable decoded store
    /// @throws Malformed JSON
    static func nativeJSON(_ bytes: Data, store: String? = nil) throws -> Any
    {

        var value = try JSONSerialization.jsonObject(with: bytes)
        if store == "Plenact.LibraryImportant.v1", let entries = value as? [[String: Any]]
        {
            value = entries.map { entry in
                var entry = entry
                if entry["level"] == nil
                {
                    entry["level"] = 1
                }
                return entry
            }
        }
        return normalized(value)
    }


    /// @fcn PortableEditedExport.normalized
    /// @brief Sort only known native Set fields and UUID dictionary pairs without discarding duplicates
    /// @param[in] value Native JSON subtree
    /// @return Normalized subtree; user-authored arrays remain ordered
    private static func normalized(_ value: Any) -> Any
    {

        if let object = value as? [String: Any]
        {
            return object.mapValues { normalized($0) }.reduce(into: [String: Any]()) { result, entry in
                let sets: Set<String> = ["savedCardIDs", "dismissedActivityIDs", "important", "bookmarked", "allDay"]
                if sets.contains(entry.key), let values = entry.value as? [Any],
                   values.allSatisfy({ $0 is String || $0 is NSNumber })
                {
                    result[entry.key] = values.sorted { String(describing: $0) < String(describing: $1) }
                }
                else if ["createdAt", "addedAt"].contains(entry.key),
                        let number = entry.value as? NSNumber
                {
                    result[entry.key] = floor((number.doubleValue + Date.timeIntervalBetween1970AndReferenceDate) * 1000)
                }
                else if entry.key == "checklistLinkWeeks", let pairs = entry.value as? [String], pairs.count % 2 == 0
                {
                    let grouped = stride(from: 0, to: pairs.count, by: 2).map { [pairs[$0], pairs[$0 + 1]] }
                    result[entry.key] = grouped.sorted { $0[0] < $1[0] }.flatMap { $0 }
                }
                else
                {
                    result[entry.key] = entry.value
                }
            }
        }
        if let values = value as? [Any]
        {
            return values.map { normalized($0) }
        }
        return value
    }


    /// @fcn PortableEditedExport.equal
    /// @brief Compare decoded JSON or property-list values independently of dictionary ordering
    /// @param[in] left First value
    /// @param[in] right Second value
    /// @return Structural value equality
    private static func equal(_ left: Any, _ right: Any) -> Bool
    {

        NSDictionary(dictionary: ["value": left]).isEqual(to: ["value": right])
    }


    /// @fcn PortableEditedExport.reconcile
    /// @brief Walk matching native stores and collect only explicitly supported Card field changes
    /// @param[in] old Imported native baseline
    /// @param[in] current Frozen current native value
    /// @param[in,out] edits Consistent Card changes keyed by retained numeric alias
    /// @return Void after every changed value is accounted for
    /// @throws Structural edits, unsupported values or divergent duplicate Card copies
    private static func reconcile(_ old: Any, _ current: Any, edits: inout [Int: [String: Any]]) throws
    {

        if equal(old, current)
        {
            return
        }
        if let before = old as? [String: Any], let after = current as? [String: Any]
        {
            if let id = before["id"] as? Int, before["word"] is String, after["id"] as? Int == id
            {
                let allowed = Set(fields.keys).union(scheduleFields).union(["editHistory"])
                let keys = Set(before.keys).union(after.keys)
                guard keys.subtracting(allowed).allSatisfy({ equal(before[$0] ?? NSNull(), after[$0] ?? NSNull()) }) else
                {
                    throw Failure.unsupported
                }
                let sameFields = Set(fields.keys).union(scheduleFields).allSatisfy { equal(before[$0] ?? NSNull(), after[$0] ?? NSNull()) }
                let sameHistory = try equal(history(before["editHistory"] ?? NSNull()), history(after["editHistory"] ?? NSNull()))
                if sameFields && sameHistory
                {
                    return
                }
                var patch = Dictionary(uniqueKeysWithValues: allowed.map { ($0, after[$0] ?? NSNull()) })
                // The native model omits its false lock flag; canonical records require an explicit Boolean.
                patch["editingLocked"] = after["editingLocked"] ?? false
                if let existing = edits[id], !equal(existing, patch)
                {
                    throw Failure.inconsistent
                }
                edits[id] = patch
                return
            }
            guard Set(before.keys) == Set(after.keys) else
            {
                throw Failure.unsupported
            }
            for key in before.keys
            {
                try reconcile(before[key]!, after[key]!, edits: &edits)
            }
            return
        }
        if let before = old as? [Any], let after = current as? [Any], before.count == after.count
        {
            for index in before.indices
            {
                try reconcile(before[index], after[index], edits: &edits)
            }
            return
        }
        if old is [Any] || current is [Any]
        {
            throw Failure.structureChanged
        }
        throw Failure.unsupported
    }


    /// @fcn PortableEditedExport.history
    /// @brief Preserve stable native history UUIDs, UTC timestamps and opaque value bytes
    /// @param[in] value Optional native Codable history
    /// @return Canonical history without executing or interpreting any change
    /// @throws Invalid history, timestamp or encoded value
    private static func history(_ value: Any) throws -> Any
    {

        if value is NSNull
        {
            return NSNull()
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        let entries = try JSONDecoder().decode([CardEditRecord].self, from: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        guard Set(entries.map(\.id)).count == entries.count else
        {
            throw Failure.inconsistent
        }
        return try entries.map { entry -> [String: Any] in
            guard entry.timestamp.timeIntervalSince1970.isFinite else
            {
                throw Failure.unsupported
            }
            let changes = entry.changes.map { change -> [String: Any] in
                var output: [String: Any] = ["field": change.field]
                for (key, bytes) in [("previous_value", change.previousValue), ("new_value", change.newValue)]
                {
                    if let bytes
                    {
                        output[key] = ["encoding": "base64", "source_format": "swift_codable_json",
                            "source_model_version": "local_legacy", "data": bytes.base64EncodedString()]
                    }
                    else
                    {
                        output[key] = NSNull()
                    }
                }
                return output
            }
            return ["id": entry.id.uuidString.lowercased(), "source_timestamp_utc": formatter.string(from: Date(timeIntervalSince1970: floor(entry.timestamp.timeIntervalSince1970 * 1000) / 1000)), "changes": changes]
        }
    }


    /// @fcn PortableEditedExport.schedule
    /// @brief Convert an edited native date and precision using the retained explicit timezone and pinned rules
    /// @param[in] value Nullable Codable reference-epoch date
    /// @param[in] kind Native display precision
    /// @param[in] zone Explicit owning timezone
    /// @return Canonical tagged schedule value without allocating any identity
    /// @throws Unsupported precision, date range or timezone
    static func schedule(_ value: Any, kind: String, zone: String) throws -> Any
    {

        let kinds = ["date": "date", "time": "time", "dateAndTime": "date_and_time"]
        guard let canonicalKind = kinds[kind] else
        {
            throw Failure.unsupported
        }
        if value is NSNull
        {
            return NSNull()
        }
        guard let number = value as? NSNumber, number.doubleValue.isFinite else
        {
            throw Failure.unsupported
        }
        let context = MigrationContentValues(journal: MigrationIdentityJournal(), timeZoneID: zone, mediaDigests: [:])
        return try MigrationContentDates.convert(number.doubleValue + Date.timeIntervalBetween1970AndReferenceDate,
            kind: canonicalKind, context: context, path: "edited_schedule")
    }


    /// @fcn PortableEditedExport.historyValue
    /// @brief Preserve new Card history UUIDs and opaque values using the existing canonical history adapter
    /// @param[in] entries Optional native history
    /// @return Canonical history or explicit null
    static func historyValue(_ entries: [CardEditRecord]?) throws -> Any
    {

        guard let entries else
        {
            return NSNull()
        }
        return try history(JSONSerialization.jsonObject(with: JSONEncoder().encode(entries)))
    }


    /// @fcn PortableEditedExport.prepare
    /// @brief Export a frozen native backup using its immutable canonical import baseline
    /// @param[in] backup Current backup including runtime evidence and exact current originals
    /// @return New independently reviewable portable package; source backup and active stores are untouched
    /// @throws Unsupported edits, inconsistent provenance, missing originals or failed native round trip
    static func prepare(_ backup: LegacyWorkspaceBackup) throws -> FileWrapper
    {

        let current = try MigrationBackupReader.values(in: backup)
        let report = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as! [String: Any]
        guard (report["review_codes"] as? [String]) == [] else
        {
            throw Failure.unsupported
        }
        let livePaths = Set((report["media"] as! [[String: Any]]).map { $0["path"] as! String })
        for (key, value) in current where LegacyStoreValidation.jsonKeys.contains(key)
        {
            if let bytes = value as? Data
            {
                let object = try JSONSerialization.jsonObject(with: bytes)
                guard LegacyStoreValidation.mediaIssues(object, store: key, files: livePaths).isEmpty else
                {
                    throw Failure.unsupported
                }
            }
        }
        let evidence = try PortableRuntimeEvidence.backupFiles(report: report, files: backup.files)
        guard let snapshot = evidence["CanonicalPackage.bin"].flatMap(FileWrapper.init(serializedRepresentation:)),
              let aliasBytes = evidence["IdentityAliases.json"],
              let aliasObject = try JSONSerialization.jsonObject(with: aliasBytes) as? [String: Any],
              let aliases = aliasObject["numeric_ids"] as? [String: Int] else
        {
            throw Failure.inconsistent
        }
        let reviewed = try PortablePackageReview.review(files: snapshot)
        var baseline = try PortableWorkspaceCandidate.prepare(reviewed, retainedAliases: aliases)
        guard let retained = evidence["NativeStores.plist"],
              let baselineValues = try PropertyListSerialization.propertyList(from: retained, format: nil) as? [String: Any],
              Set(baseline.values.keys) == Set(baselineValues.keys), baseline.numericIDs == aliases else
        {
            throw Failure.inconsistent
        }
        for (key, value) in baseline.values
        {
            if let before = value as? Data, let retained = baselineValues[key] as? Data
            {
                guard equal(try nativeJSON(before, store: key), try nativeJSON(retained, store: key)) else
                {
                    throw Failure.inconsistent
                }
            }
            else if !equal(value, baselineValues[key] ?? NSNull())
            {
                throw Failure.inconsistent
            }
        }
        // Device navigation and recovery values have no portable meaning. Every user-data key must match.
        let retainedRecoveryKeys: Set<String> = ["Plenact.ExampleCardLocations.Applied.v1", "Plenact.ExampleCardLocations.Backup.v1"]
        let deviceKeys = Set(current.keys.filter { retainedRecoveryKeys.contains($0) || $0.hasPrefix("Plenact.BoardViewport.") ||
            ["Plenact.ActivityRecents.v1", "Plenact.LibraryRecents.v1", "Plenact.RecentSearches.v1", "Plenact.LocalReactionAuthor.v1", "Plenact.LastViewedList.v1", "Plenact.Welcome.lastDeparture.v1"].contains($0) })
        guard Set(current.keys).subtracting(deviceKeys) == Set(baseline.values.keys) else
        {
            throw Failure.unsupported
        }
        let enriched = try PortableRichCardExport.enrich(backup: backup, snapshot: snapshot, baseline: baseline)
        let mediaNames = enriched.names
        let exportSnapshot = enriched.files
        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: exportSnapshot),
            retainedAliases: aliases, mediaFilenames: mediaNames)
        let originalAssembly = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: exportSnapshot)) as! [String: Any]
        let effectiveAssembly = try PortableStructuralEdits.apply(assembly: originalAssembly,
            current: current, aliases: aliases, baseline: baseline)
        let structuralPackage = try PortableLocalDeletions.package(snapshot: exportSnapshot, assembly: effectiveAssembly)
        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: structuralPackage), retainedAliases: aliases, mediaFilenames: mediaNames)
        var edits: [Int: [String: Any]] = [:]
        for (key, original) in baseline.values
        {
            let live = current[key]!
            if let before = original as? Data, let after = live as? Data
            {
                try reconcile(nativeJSON(before, store: key), nativeJSON(after, store: key), edits: &edits)
            }
            else if !equal(original, live)
            {
                throw Failure.unsupported
            }
        }
        let declared = report["media"] as! [[String: Any]]
        let capturedPaths = Set(declared.map { $0["path"] as! String })
        guard capturedPaths.isSubset(of: Set(baseline.media.files.keys)) else
        {
            throw Failure.unsupported
        }
        for path in capturedPaths
        {
            guard try MigrationBackupReader.file(path, in: backup.files) == baseline.media.files[path] else
            {
                throw PortablePackageReview.Failure.integrity
            }
        }
        var assembly = effectiveAssembly
        var export = assembly["workspace_export"] as! [String: Any]
        var base = export["base_workspace"] as! [String: Any]
        var planning = base["planning"] as! [String: Any]
        var content = planning["content"] as! [String: Any]
        var cards = content["cards"] as! [[String: Any]]
        var consumed = Set<Int>()
        for index in cards.indices
        {
            guard let id = cards[index]["id"] as? String, let number = aliases[id], let patch = edits[number] else
            {
                continue
            }
            var payload = cards[index]["payload"] as! [String: Any]
            for (native, canonical) in fields
            {
                payload[canonical] = patch[native]!
            }
            for (native, canonical) in [("startDate", "start"), ("dueDate", "due")]
            {
                guard let kind = patch[native + "Kind"] as? String else
                {
                    throw Failure.unsupported
                }
                let old = payload[canonical] as? [String: Any]
                let zone = old?["time_zone"] as? String ?? baseline.timeZoneID
                payload[canonical] = try schedule(patch[native] ?? NSNull(), kind: kind, zone: zone)
                payload[canonical + "_kind"] = kind == "dateAndTime" ? "date_and_time" : kind
            }
            payload["edit_history"] = try history(patch["editHistory"]!)
            cards[index]["payload"] = payload
            consumed.insert(number)
        }
        guard consumed == Set(edits.keys) else
        {
            throw Failure.inconsistent
        }
        content["cards"] = cards
        planning["content"] = content
        base["planning"] = planning
        export["base_workspace"] = base
        assembly["workspace_export"] = export
        let bytes = try JSONSerialization.data(withJSONObject: assembly, options: [.sortedKeys, .withoutEscapingSlashes])
        var manifest = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Manifest.json", in: exportSnapshot)) as! [String: Any]
        var files = manifest["files"] as! [[String: Any]]
        guard let index = files.firstIndex(where: { $0["path"] as? String == "Assembly.json" }) else
        {
            throw Failure.inconsistent
        }
        files[index] = ["path": "Assembly.json", "byte_length": bytes.count, "sha256": MigrationBackupReader.digest(bytes)]
        manifest["files"] = files
        let output = FileWrapper(directoryWithFileWrappers: ["Assembly.json": FileWrapper(regularFileWithContents: bytes),
            "Manifest.json": FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)),
            "Originals": exportSnapshot.fileWrappers!["Originals"]!])
        let result = try PortablePackageReview.review(files: output)
        let rebuilt = try PortableWorkspaceCandidate.prepare(result, retainedAliases: aliases, mediaFilenames: mediaNames)
        guard rebuilt.numericIDs == aliases else
        {
            throw Failure.inconsistent
        }
        // A second complete projection detects missed fields, stale duplicate Cards and lossy conversion.
        for (key, value) in rebuilt.values
        {
            if let bytes = value as? Data, let live = current[key] as? Data
            {
                var unexpected: [Int: [String: Any]] = [:]
                try reconcile(nativeJSON(bytes, store: key), nativeJSON(live, store: key), edits: &unexpected)
                guard unexpected.isEmpty else
                {
                    throw Failure.inconsistent
                }
            }
            else if !equal(value, current[key] ?? NSNull())
            {
                throw Failure.inconsistent
            }
        }
        guard let sourceBytes = backup.files.serializedRepresentation,
              let sourceCopy = FileWrapper(serializedRepresentation: sourceBytes) else
        {
            throw Failure.inconsistent
        }
        let folder = FileWrapper(directoryWithFileWrappers: ["PortableTestPackage": output, "EditedNativeBackup": sourceCopy])
        guard let frozen = folder.serializedRepresentation, frozen.count <= LegacyWorkspaceExport.maximumBytes else
        {
            throw LegacyWorkspaceExport.Failure.tooLarge
        }
        folder.preferredFilename = "Plenact Edited Portable Test"
        return folder
    }
}


/// Retains offline deletion intent without manufacturing server revision or acknowledgement metadata.
/// @section Purpose
///     Model 1.1 keeps pre-deletion records and aliases while applying an explicit local presentation overlay.
@MainActor
enum PortableLocalDeletions
{

    /// @fcn PortableLocalDeletions.ids
    /// @brief Validate optional local deletion targets against retained canonical Cards
    /// @param[in] export Working Model 1.1 composite
    /// @return Unique deleted Card UUIDs
    /// @throws Invalid shape, duplicate identity or missing retained Card
    static func ids(in export: [String: Any]) throws -> Set<String>
    {

        guard let raw = export["local_card_deletions"] else
        {
            return []
        }
        guard let ids = raw as? [String], Set(ids).count == ids.count,
              let base = export["base_workspace"] as? [String: Any], let planning = base["planning"] as? [String: Any],
              let content = planning["content"] as? [String: Any], let cards = content["cards"] as? [[String: Any]],
              Set(ids).isSubset(of: Set(cards.compactMap { $0["id"] as? String })) else
        {
            throw PortablePackageReview.Failure.relationships
        }
        return Set(ids)
    }


    /// @fcn PortableLocalDeletions.package
    /// @brief Freeze a revised canonical assembly and rehash its manifest without replacing original blobs
    /// @param[in] snapshot Retained portable members
    /// @param[in] assembly Revised synthetic assembly
    /// @return Reviewed portable members
    /// @throws Serialization, checksum or reference failure
    static func package(snapshot: FileWrapper, assembly: [String: Any]) throws -> FileWrapper
    {

        let bytes = try JSONSerialization.data(withJSONObject: assembly, options: [.sortedKeys, .withoutEscapingSlashes])
        var manifest = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Manifest.json", in: snapshot)) as! [String: Any]
        var files = manifest["files"] as! [[String: Any]]
        guard let index = files.firstIndex(where: { $0["path"] as? String == "Assembly.json" }) else
        {
            throw PortablePackageReview.Failure.integrity
        }
        files[index] = ["path": "Assembly.json", "byte_length": bytes.count, "sha256": MigrationBackupReader.digest(bytes)]
        manifest["files"] = files
        let result = FileWrapper(directoryWithFileWrappers: ["Assembly.json": FileWrapper(regularFileWithContents: bytes),
            "Manifest.json": FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)),
            "Originals": snapshot.fileWrappers!["Originals"]!])
        _ = try PortablePackageReview.review(files: result)
        return result
    }


    /// @fcn PortableLocalDeletions.nativeCards
    /// @brief Collect native Card identities without interpreting opaque history or other record IDs
    /// @param[in] value Native store subtree
    /// @return Retained Card numeric aliases
    static func nativeCards(_ value: Any) -> Set<Int>
    {

        if let object = value as? [String: Any]
        {
            if object["word"] is String, let id = object["id"] as? Int
            {
                return [id]
            }
            return object.values.reduce(into: Set<Int>()) { $0.formUnion(nativeCards($1)) }
        }
        if let values = value as? [Any]
        {
            return values.reduce(into: Set<Int>()) { $0.formUnion(nativeCards($1)) }
        }
        return []
    }
}
