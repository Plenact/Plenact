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
                return "This export supports Board-created Cards and Lists, same-Board movement and reordering, automatic Week rollover, profile and Studio personalization, saved app and review-rhythm preferences, daily-plan writing, check-ins and evening/weekly-review history, existing List and Collection metadata and appearance, plus supported Card content, completion, scheduling, deletion and history. Another saved change needs an export adapter. Your local backup can preserve all changes."
            case .structureChanged:
                return "These structural changes cannot yet be exported safely. Creation in Board views, movement within the same Board and reordering are supported; cross-Board transfers and List deletion still need support. Your title, time and other saved changes remain intact; a local backup preserves the complete workspace."
            case .inconsistent:
                return "The retained import evidence or saved Card copies disagree. No package was prepared. Your workspace is unchanged."
            }
        }
    }


    /// @fcn PortableEditedExport.nativeJSON
    /// @brief Normalize reviewed Set encodings and daily/weekly timestamp precision for comparison
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
        if store == "Plenact.LocalProfile.v1", var profile = value as? [String: Any]
        {
            for key in ["avatarColor", "avatarForegroundColor"]
            {
                if let raw = profile[key]
                {
                    let bytes = try JSONSerialization.data(withJSONObject: raw, options: .fragmentsAllowed)
                    let color = try JSONDecoder().decode(ProfileColor.self, from: bytes)
                    profile[key] = ["red": color.red, "green": color.green, "blue": color.blue]
                }
            }
            value = profile
        }
        if store == "Plenact.DailyPlans.v1" || store == "Plenact.WeeklyReviews.v1"
        {

            value = planningTimestampComparison(value)
        }
        return normalized(value)
    }


    /// @fcn PortableEditedExport.planningTimestampComparison
    /// @brief Compare declared daily/weekly timestamps at the canonical millisecond precision
    /// @details Only frozen comparison values change. Exact source seconds remain in the native
    ///          backup; authored strings, array order, nulls and unrelated numeric values are retained.
    /// @param[in] value Validated daily-plan or weekly-review subtree
    /// @return Comparable subtree with integer epoch milliseconds for known timestamp fields
    private static func planningTimestampComparison(_ value: Any) -> Any
    {

        if let object = value as? [String: Any]
        {

            let fields: Set<String> = ["updatedAt", "savedAt", "visionCompletedAt", "completedAt",
                "recordedAt", "sourceCreatedAt"]
            return object.mapValues(planningTimestampComparison).reduce(into: [String: Any]()) { result, entry in

                if fields.contains(entry.key), let number = entry.value as? NSNumber
                {

                    result[entry.key] = floor((number.doubleValue + Date.timeIntervalBetween1970AndReferenceDate) * 1000)
                }
                else
                {

                    result[entry.key] = entry.value
                }
            }
        }
        if let array = value as? [Any]
        {

            return array.map(planningTimestampComparison)
        }
        return value
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


    /// @fcn PortableEditedExport.reviewRhythm
    /// @brief Reconcile saved review invitation and notification intent without scheduling actions
    /// @details Preserves retained singleton identity and unchanged canonical values. A newly saved
    ///          store receives a deterministic workspace-qualified identity; malformed fields fail closed.
    /// @param[in] assembly Reconciled content and personalization package
    /// @param[in] current Frozen native source values
    /// @param[in] baseline Retained imported projection
    /// @return Assembly with validated authored review-rhythm preferences
    /// @throws Missing retained store, unknown fields, invalid types, ranges or singleton shape
    private static func reviewRhythm(assembly: [String: Any], current: [String: Any],
        baseline: PortableWorkspaceCandidate) throws -> [String: Any]
    {

        let key = "Plenact.ReviewRhythm.v1"  /* Explicitly supported planning preference store */
        guard let bytes = current[key] as? Data else
        {

            guard current[key] == nil, baseline.values[key] == nil else
            {

                throw Failure.unsupported
            }
            return assembly
        }
        let fields = ["dailyInvitations": "daily_invitations", "weeklyInvitations": "weekly_invitations",
            "dailyMinutes": "daily_minutes", "weeklyMinutes": "weekly_minutes", "weeklyWeekday": "weekly_weekday",
            "dailyNotifications": "daily_notifications", "weeklyNotifications": "weekly_notifications"]
        let raw = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        guard let raw, Set(raw.keys) == Set(fields.keys) else
        {

            throw Failure.unsupported
        }
        let rhythm = try JSONDecoder().decode(ReviewRhythmPreferences.self, from: bytes)
        guard (0..<1440).contains(rhythm.dailyMinutes), (0..<1440).contains(rhythm.weeklyMinutes),
              (1...7).contains(rhythm.weeklyWeekday) else
        {

            throw Failure.unsupported
        }
        if let old = baseline.values[key] as? Data,
           equal(try nativeJSON(old, store: key), try nativeJSON(bytes, store: key))
        {

            return assembly
        }
        var result = assembly
        var export = result["workspace_export"] as! [String: Any]
        var base = export["base_workspace"] as! [String: Any]
        var planning = base["planning"] as! [String: Any]
        let retained = planning["review_rhythms"] as! [[String: Any]]
        guard retained.count <= 1, (baseline.values[key] != nil) == !retained.isEmpty else
        {

            throw Failure.inconsistent
        }
        let id = try retained.first?["id"] as? String ?? PortableRichCardExport.identity(
            namespace: baseline.workspaceID, name: "review_rhythm:" + key)
        var record = retained.first ?? ["user_data_model_version": "1.0", "payload_schema_version": 1,
            "record_type": "review_rhythm", "id": id, "workspace_id": baseline.workspaceID]
        var payload = retained.first?["payload"] as? [String: Any] ?? [:]
        for (source, target) in fields
        {

            payload[target] = raw[source]!
        }
        record["payload"] = payload
        planning["review_rhythms"] = [record]
        base["planning"] = planning
        export["base_workspace"] = base
        result["workspace_export"] = export
        return result
    }


    /// @fcn PortableEditedExport.planningEdits
    /// @brief Reconcile daily plans or weekly reviews with explicit historical reference provenance
    /// @details Retains daily/weekly identities and unchanged payload fields. Unknown references, removed records
    ///          and changed date/time-zone identities fail closed. Review history is data, never replayed.
    /// @param[in] assembly Reconciled content, personalization and rhythm assembly
    /// @param[in] current Frozen native values
    /// @param[in] baseline Imported native projection
    /// @param[in] aliases Retained and explicitly reserved numeric identities
    /// @param[in] weekly Select weekly-review records instead of daily plans
    /// @return Assembly containing verified daily or weekly snapshots
    /// @throws Invalid source, identity changes, ambiguous references or unsupported removals
    private static func planningEdits(assembly: [String: Any], current: [String: Any],
        baseline: PortableWorkspaceCandidate, aliases: [String: Int], weekly: Bool = false) throws -> [String: Any]
    {

        let key = weekly ? "Plenact.WeeklyReviews.v1" : "Plenact.DailyPlans.v1"
        let group = weekly ? "weekly_reviews" : "daily_plans"
        let container = weekly ? "records" : "plans"
        let identityField = weekly ? "source_review_key" : "date"
        let kind = weekly ? "weekly_review" : "daily_plan"
        guard let bytes = current[key] as? Data else
        {

            guard current[key] == nil, baseline.values[key] == nil else
            {

                throw Failure.unsupported
            }
            return assembly
        }
        var result = assembly
        var export = result["workspace_export"] as! [String: Any]
        var base = export["base_workspace"] as! [String: Any]
        var planning = base["planning"] as! [String: Any]
        let retained = planning[group] as! [[String: Any]]
        if weekly
        {

            _ = try JSONDecoder().decode(WeeklyReviewStore.Document.self, from: bytes)
        }
        else
        {

            _ = try JSONDecoder().decode(DailyPlanStore.Document.self, from: bytes)
        }
        let rawDocument = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        guard let sourceRecords = rawDocument[container] as? [String: [String: Any]] else
        {

            throw Failure.unsupported
        }
        var journal = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MigrationIdentityJournal())) as! [String: Any]
        journal["previewWorkspaceID"] = baseline.workspaceID
        var entries: [[String: Any]] = []
        for (date, plan) in sourceRecords.sorted(by: { $0.key < $1.key })
        {

            let zone = plan["timeZoneID"] as! String
            let old = retained.first { ($0["payload"] as? [String: Any])?[identityField] as? String == date }
            if let old, (old["payload"] as? [String: Any])?["time_zone"] as? String != zone
            {

                throw Failure.unsupported
            }
            let name = weekly ? kind + ":" + date : kind + ":" + date + ":" + zone
            let id = try old?["id"] as? String ?? PortableRichCardExport.identity(namespace: baseline.workspaceID, name: name)
            var source: [String: Any] = ["recordType": kind, "owner": key, "legacyID": date]
            if !weekly
            {

                source["discriminator"] = zone
            }
            entries.append(["source": source, "target": id])
        }
        guard retained.allSatisfy({ sourceRecords[($0["payload"] as! [String: Any])[identityField] as! String] != nil }) else
        {

            throw Failure.unsupported
        }
        journal["entries"] = entries
        var seeded = try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
        var records: [[String: Any]] = []

        /// @fcn PortableEditedExport.collectDailyRecords
        /// @brief Collect canonical records without interpreting opaque strings or source files
        /// @param[in] value Canonical subtree
        /// @return Void after collecting uniquely stored records
        func collect(_ value: Any)
        {

            if let object = value as? [String: Any]
            {

                if object["record_type"] is String, object["payload"] != nil,
                   object["user_data_model_version"] as? String == "1.0"
                {

                    records.append(object)
                }
                else
                {

                    for child in object.values
                    {

                        collect(child)
                    }
                }
            }
            else if let array = value as? [Any]
            {

                for child in array
                {

                    collect(child)
                }
            }
        }
        collect(export)
        let adapter = try PortableEditableContent(records: records, assetFiles: baseline.media.filenames,
            retainedAliases: aliases, deletedCardIDs: PortableLocalDeletions.ids(in: export))
        var historical: [[String: Any]] = []

        /// @fcn PortableEditedExport.collectDailyPriorities
        /// @brief Retain declared historical targets even when their live Cards have been deleted
        /// @param[in] value Canonical historical subtree
        /// @return Void after gathering authored reference snapshots
        func priorities(_ value: Any)
        {

            if let object = value as? [String: Any]
            {

                if object["source_collection_id"] is String, object["card_id"] is String,
                   object["source_created_at_utc"] != nil
                {

                    historical.append(object)
                }
                for child in object.values
                {

                    priorities(child)
                }
            }
            else if let array = value as? [Any]
            {

                for child in array
                {

                    priorities(child)
                }
            }
        }
        priorities(planning)
        let content = planning["content"] as! [String: Any]
        let lists = content["lists"] as! [[String: Any]]
        for card in content["cards"] as! [[String: Any]]
        {

            let payload = card["payload"] as! [String: Any]
            let list = lists.first { $0["id"] as? String == payload["list_id"] as? String }!
            let owner = (list["payload"] as! [String: Any])["collection_id"] as! String
            historical.append(["source_collection_id": owner, "card_id": card["id"]!,
                "source_created_at_utc": payload["source_created_at_utc"]!, "title": "", "source_location": ""])
        }
        let converted = try MigrationPlanningPreview.prepare(values: [key: bytes], records: records, journal: &seeded,
            priorityResolver: { raw in

                var targets: [String: [String: Any]] = [:]
                for snapshot in historical
                {

                    let native = try adapter.priority(snapshot)
                    let fields = ["cardID"]
                    if (native["ownerID"] as? String)?.lowercased() == (raw["ownerID"] as? String)?.lowercased(),
                       fields.allSatisfy({ equal(native[$0] ?? NSNull(), raw[$0] ?? NSNull()) }),
                       equal(planningTimestampComparison(["sourceCreatedAt": native["sourceCreatedAt"] ?? NSNull()]),
                           planningTimestampComparison(["sourceCreatedAt": raw["sourceCreatedAt"] ?? NSNull()]))
                    {

                        targets[snapshot["card_id"] as! String] = snapshot
                    }
                }
                guard targets.count == 1, var target = targets.values.first else
                {

                    throw Failure.unsupported
                }
                target["title"] = raw["title"]!
                target["source_location"] = raw["location"]!
                return target
            })
        guard converted.unresolvedCount == 0, seeded.entries.count == entries.count else
        {

            throw Failure.unsupported
        }
        let sourceDocument = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        let sources = sourceDocument[container] as! [String: Any]
        let previousBytes = baseline.values[key] as? Data
        let previousDocument = try previousBytes.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
        let previousSources = previousDocument?[container] as? [String: Any] ?? [:]
        var sourceFields = ["date": "id", "time_zone": "timeZoneID", "intention": "intention",
            "constraints": "constraints", "concerns": "concerns", "priorities": "priorities", "updated_at_utc": "updatedAt",
            "vision_completed_at_utc": "visionCompletedAt", "vision_step": "visionStep", "check_in": "checkIn",
            "check_ins": "checkIns", "evening_review": "eveningReview"]
        if weekly
        {

            sourceFields = ["source_review_key": "id", "start_date": "startKey", "time_zone": "timeZoneID",
                "first_weekday": "firstWeekday", "step": "step", "highlights": "highlights", "learned": "learned",
                "direction": "direction", "constraints": "constraints", "risks": "risks", "priorities": "priorities",
                "decisions": "decisions", "updated_at_utc": "updatedAt", "completed_at_utc": "completedAt"]
        }
        var updated = retained
        for record in converted.records
        {

            if let index = updated.firstIndex(where: { $0["id"] as? String == record["id"] as? String })
            {

                var old = updated[index]
                var payload = old["payload"] as! [String: Any]
                let fresh = record["payload"] as! [String: Any]
                let date = fresh[identityField] as! String
                let before = previousSources[date] as? [String: Any] ?? [:]
                let after = sources[date] as! [String: Any]
                for (field, value) in fresh
                {

                    let source = sourceFields[field]!
                    if !equal(normalized(before[source] ?? NSNull()), normalized(after[source] ?? NSNull()))
                    {

                        payload[field] = value
                    }
                }
                old["payload"] = payload
                updated[index] = old
            }
            else
            {

                updated.append(record)
            }
        }
        planning[group] = updated
        base["planning"] = planning
        export["base_workspace"] = base
        result["workspace_export"] = export
        return result
    }


    /// @fcn PortableEditedExport.prepare
    /// @brief Export a frozen native backup using its immutable canonical import baseline
    /// @param[in] backup Current backup including runtime evidence and exact current originals
    /// @return New independently reviewable portable package; source backup and active stores are untouched
    /// @throws Unsupported edits, inconsistent provenance, missing originals or failed native round trip
    static func prepare(_ backup: LegacyWorkspaceBackup) throws -> FileWrapper
    {

        var current = try MigrationBackupReader.values(in: backup)
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
              var aliases = aliasObject["numeric_ids"] as? [String: Int] else
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
        let newSupportedKeys: Set<String> = ["Plenact.WeeklyReviews.v1", "Plenact.DailyPlans.v1", "Plenact.ReviewRhythm.v1", "Plenact.LocalProfile.v1", "Plenact.Studio.Settings.v1",
            "Plenact.Studio.Artwork.v1", "Plenact.WeekAppearance.v1"]
        guard Set(current.keys).subtracting(deviceKeys).subtracting(newSupportedKeys)
                == Set(baseline.values.keys).subtracting(newSupportedKeys),
              Set(baseline.values.keys).isSubset(of: Set(current.keys)) else
        {
            throw Failure.unsupported
        }
        let enriched = try PortableRichCardExport.enrich(backup: backup, snapshot: snapshot, baseline: baseline)
        let mediaNames = enriched.names
        let exportSnapshot = enriched.files
        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: exportSnapshot),
            retainedAliases: aliases, mediaFilenames: mediaNames)
        let originalAssembly = try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: exportSnapshot)) as! [String: Any]
        let rollover = try PortableStructuralEdits.rollovers(assembly: originalAssembly, current: current,
            aliases: aliases, baseline: baseline)
        current = rollover.current
        aliases = rollover.aliases
        let rolloverPackage = try PortableLocalDeletions.package(snapshot: exportSnapshot, assembly: rollover.assembly)
        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: rolloverPackage),
            retainedAliases: aliases, mediaFilenames: mediaNames)
        let contentAssembly = try PortableStructuralEdits.apply(assembly: rollover.assembly,
            current: current, aliases: aliases, baseline: baseline)
        let rhythmAssembly = try reviewRhythm(assembly: contentAssembly, current: current, baseline: baseline)
        let dailyAssembly = try planningEdits(assembly: rhythmAssembly, current: current, baseline: baseline, aliases: aliases)
        let effectiveAssembly = try planningEdits(assembly: dailyAssembly, current: current, baseline: baseline, aliases: aliases, weekly: true)
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
