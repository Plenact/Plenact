// --------------------------------------------------------------------------------------------------
// @file       PortableEditedExport.swift
// @brief      Reconcile supported editable Card changes with their retained canonical identities
// @details    Supported User Data Model versions: 1.0 base and working 1.1. Simulator test packages only.
//             Refuses unsupported edits and changed originals; never changes the active workspace or baseline
// --------------------------------------------------------------------------------------------------
import Foundation


/// Produces a new reviewed package while preserving unmapped canonical values and original bytes
/// @section Purpose
///     Establish a reversible edit/export/import path without treating native numeric IDs as global identities
@MainActor
enum PortableEditedExport
{
    static let fields =                                                         /* Record fields under review */
        ["word": "title", "descriptionOverride": "description_override",
        "subtitleOverride": "subtitle_override", "isTitleChecked": "completed", "editingLocked": "editing_locked",
        "showsDueDateInList": "shows_due_date_in_list", "showsReactionsInPreviews": "shows_reactions_in_previews"]

    static let scheduleFields: Set<String> =                            /* Scheduling field names */
        ["startDate", "dueDate", "startDateKind", "dueDateKind"]

    /// Selects one explicitly reviewed planning-store family
    /// @section Purpose
    ///     Share reference and preservation rules without accepting unrelated source stores
    private enum PlanningFamily: String
    {
        case daily = "daily_plan"
        case weekly = "weekly_review"
        case periodic = "periodic_review"
    }


    /// Explains unsupported changes without exposing private content
    /// @section Purpose
    ///     Prevent an apparently successful package from omitting an unconverted edit
    enum Failure: LocalizedError
    {
        case unsupported, inconsistent, structureChanged

        /// @fcn Failure.errorDescription
        /// @brief Describe the limited editable export boundary
        /// @return Actionable guidance with no source values
        var errorDescription: String?           /* Readable failure explanation */
        {
            switch self
            {
            case .unsupported:
                return "This export supports Board-created Cards and Lists, same-Board movement and reordering, automatic Week rollover, profile and Studio personalization, saved app and review-rhythm preferences, daily-plan writing, check-ins and evening, weekly and periodic-review history, new template Cards and Notes, additive template application to retained Weeks, captured/duplicated templates, retained names and library order/defaults, existing List and Collection metadata and appearance, plus supported Card content, completion, scheduling, deletion and history. Another saved change needs an export adapter. Your local backup can preserve all changes."
            case .structureChanged:
                return "These structural changes cannot yet be exported safely. Creation in Board views, movement within the same Board and reordering are supported; cross-Board transfers and List deletion still need support. Your title, time and other saved changes remain intact; a local backup preserves the complete workspace."
            case .inconsistent:
                return "The retained import evidence or saved Card copies disagree. No package was prepared. Your workspace is unchanged."
            }
        }
    }


    /// @fcn PortableEditedExport.nativeJSON
    /// @brief Normalize reviewed Set/importance encodings and planning timestamp precision for comparison
    /// @param[in] bytes Native Codable store bytes
    /// @param[in] store Optional store family for explicit legacy importance-level comparison
    /// @return Comparable decoded store
    /// @throws Malformed JSON
    static func nativeJSON(_ bytes: Data, store: String? = nil) throws -> Any
    {
        var value = try JSONSerialization.jsonObject(with: bytes)       /* Decoded JSON object */

        if store == "Plenact.LibraryImportant.v1", let entries = value as? [[String: Any]]
        {
            value = entries.map { entry in

                var entry = entry       /* Entry being processed */

                if entry["level"] == nil
                {
                    entry["level"] = 1
                }
                return entry
            }.sorted { left, right in

                let leftOwner  =                                                /* First reference owner  */
                    (left["collectionID"] as? String ?? "").lowercased()
                let rightOwner =                                                /* Second reference owner */
                    (right["collectionID"] as? String ?? "").lowercased()

                if leftOwner != rightOwner
                {
                    return leftOwner < rightOwner
                }
                return (left["cardID"] as? Int ?? Int.min) < (right["cardID"] as? Int ?? Int.min)
            }
        }
        if store == "Plenact.LocalProfile.v1", var profile = value as? [String: Any]
        {
            for key in ["avatarColor", "avatarForegroundColor"]
            {
                if let raw = profile[key]
                {
                    let bytes =                                                                         /* Encoded record bytes */
                        try JSONSerialization.data(withJSONObject: raw, options: .fragmentsAllowed)
                    let color =                                                                         /* Resolved color value */
                        try JSONDecoder().decode(ProfileColor.self, from: bytes)

                    profile[key] = ["red": color.red, "green": color.green, "blue": color.blue]
                }
            }

            value = profile
        }
        if ["Plenact.DailyPlans.v1", "Plenact.WeeklyReviews.v1", "Plenact.PeriodicReviews.v1"].contains(store ?? "")
        {
            value = planningTimestampComparison(value)
        }
        return normalized(value)
    }


    /// @fcn PortableEditedExport.planningTimestampComparison
    /// @brief Compare declared planning timestamps at the canonical millisecond precision
    /// @details Only frozen comparison values change. Exact source seconds remain in the native
    ///          backup; authored strings, array order, nulls and unrelated numeric values are retained
    /// @param[in] value Validated planning-store subtree
    /// @return Comparable subtree with integer epoch milliseconds for known timestamp fields
    private static func planningTimestampComparison(_ value: Any) -> Any
    {
        if let object = value as? [String: Any]
        {
            let fields: Set<String> =                                           /* Record fields under review */
                ["updatedAt", "savedAt", "visionCompletedAt", "completedAt",
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

                let sets: Set<String> =                                                                 /* Normalized sets for comparison */
                    ["savedCardIDs", "dismissedActivityIDs", "important", "bookmarked", "allDay"]

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
                    let grouped =                                                                       /* Values grouped by identity */
                        stride(from: 0, to: pairs.count, by: 2).map { [pairs[$0], pairs[$0 + 1]] }

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
                let allowed =                                                           /* Permitted input values      */
                    Set(fields.keys).union(scheduleFields).union(["editHistory"])
                let keys    = Set(before.keys).union(after.keys)                        /* Keys used by this operation */

                guard keys.subtracting(allowed).allSatisfy({ equal(before[$0] ?? NSNull(), after[$0] ?? NSNull()) }) else
                {
                    throw Failure.unsupported
                }

                let sameFields  =       /* Same fields  */
                    Set(fields.keys).union(scheduleFields).allSatisfy { equal(before[$0] ?? NSNull(), after[$0] ?? NSNull()) }
                let sameHistory =       /* Same history */
                    try equal(history(before["editHistory"] ?? NSNull()), history(after["editHistory"] ?? NSNull()))

                if sameFields && sameHistory
                {
                    return
                }

                var patch =                                                                             /* Edits to apply */
                    Dictionary(uniqueKeysWithValues: allowed.map { ($0, after[$0] ?? NSNull()) })

                // The native model omits its false lock flag; canonical records require an explicit Boolean
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

        let data      = try JSONSerialization.data(withJSONObject: value)       /* Encoded record bytes    */
        let entries   =                                                         /* Entries being processed */
            try JSONDecoder().decode([CardEditRecord].self, from: data)
        let formatter = DateFormatter()                                         /* Date or value formatter */

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

            let changes =                                                       /* Requested content edits */
                try entry.storedChanges().map { change -> [String: Any] in

                var output: [String: Any] = ["field": change.field]     /* Operation output */

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
        let kinds =                                                             /* Supported record kinds */
            ["date": "date", "time": "time", "dateAndTime": "date_and_time"]

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

        let context =           /* Operation context */
            MigrationContentValues(journal: MigrationIdentityJournal(), timeZoneID: zone, mediaDigests: [:])

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
    ///          store receives a deterministic workspace-qualified identity; malformed fields fail closed
    /// @param[in] assembly Reconciled content and personalization package
    /// @param[in] current Frozen native source values
    /// @param[in] baseline Retained imported projection
    /// @return Assembly with validated authored review-rhythm preferences
    /// @throws Missing retained store, unknown fields, invalid types, ranges or singleton shape
    private static func reviewRhythm(assembly: [String: Any], current: [String: Any],
        baseline: PortableWorkspaceCandidate) throws -> [String: Any]
    {
        let key = "Plenact.ReviewRhythm.v1"     /* Explicitly supported planning preference store */

        guard let bytes = current[key] as? Data else
        {
            guard current[key] == nil, baseline.values[key] == nil else
            {
                throw Failure.unsupported
            }
            return assembly
        }

        let fields =                                                                                    /* Record fields under review */
            ["dailyInvitations": "daily_invitations", "weeklyInvitations": "weekly_invitations",
            "dailyMinutes": "daily_minutes", "weeklyMinutes": "weekly_minutes", "weeklyWeekday": "weekly_weekday",
            "dailyNotifications": "daily_notifications", "weeklyNotifications": "weekly_notifications"]
        let raw =                                                                                       /* Unprocessed source value   */
            try JSONSerialization.jsonObject(with: bytes) as? [String: Any]

        guard let raw, Set(raw.keys) == Set(fields.keys) else
        {
            throw Failure.unsupported
        }

        let rhythm =                                                            /* Review invitation preferences */
            try JSONDecoder().decode(ReviewRhythmPreferences.self, from: bytes)

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

        var result   = assembly                                         /* Accumulated output value    */
        var export   = result["workspace_export"] as! [String: Any]     /* Prepared export evidence    */
        var base     = export["base_workspace"] as! [String: Any]       /* Base value before overrides */
        var planning = base["planning"] as! [String: Any]               /* Planning store projection   */
        let retained =                                                  /* State retained for recovery */
            planning["review_rhythms"] as! [[String: Any]]

        guard retained.count <= 1, (baseline.values[key] != nil) == !retained.isEmpty else
        {
            throw Failure.inconsistent
        }

        let id =                                                                                /* Record or view identity  */
            try retained.first?["id"] as? String ?? PortableRichCardExport.identity(
                namespace: baseline.workspaceID, name: "review_rhythm:" + key)
        var record =                                                                            /* Record being processed   */
            retained.first ?? ["user_data_model_version": "1.0", "payload_schema_version": 1,
            "record_type": "review_rhythm", "id": id, "workspace_id": baseline.workspaceID]
        var payload =                                                                           /* Canonical record payload */
            retained.first?["payload"] as? [String: Any] ?? [:]

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
    /// @brief Reconcile daily, weekly or periodic records with explicit historical reference provenance
    /// @details Retains explicit planning identities and unchanged payload fields. Unknown references, removed records
    ///          and changed date/time-zone identities fail closed. Review history is data, never replayed
    /// @param[in] assembly Reconciled content, personalization and rhythm assembly
    /// @param[in] current Frozen native values
    /// @param[in] baseline Imported native projection
    /// @param[in] aliases Retained and explicitly reserved numeric identities
    /// @param[in] family Explicit daily, weekly or periodic store family
    /// @return Assembly containing verified planning snapshots
    /// @throws Invalid source, identity changes, ambiguous references or unsupported removals
    private static func planningEdits(assembly: [String: Any], current: [String: Any],
        baseline: PortableWorkspaceCandidate, aliases: [String: Int], family: PlanningFamily = .daily) throws -> [String: Any]
    {
        let weekly        = family == .weekly                                           /* Weekly review state        */
        let periodic      = family == .periodic                                         /* Periodic review state      */
        let key           =                                                             /* Lookup or persistence key  */
            periodic ? "Plenact.PeriodicReviews.v1" : (weekly ? "Plenact.WeeklyReviews.v1" : "Plenact.DailyPlans.v1")
        let group         =                                                             /* Related operation entries  */
            periodic ? "periodic_reviews" : (weekly ? "weekly_reviews" : "daily_plans")
        let container     = family == .daily ? "plans" : "records"                      /* Decoded field container    */
        let identityField = weekly ? "source_review_key" : "date"                       /* Identity field             */
        let kind          = family.rawValue                                             /* Content kind discriminator */

        guard let bytes = current[key] as? Data else
        {
            guard current[key] == nil, baseline.values[key] == nil else
            {
                throw Failure.unsupported
            }
            return assembly
        }

        var result   = assembly                                         /* Accumulated output value    */
        var export   = result["workspace_export"] as! [String: Any]     /* Prepared export evidence    */
        var base     = export["base_workspace"] as! [String: Any]       /* Base value before overrides */
        var planning = base["planning"] as! [String: Any]               /* Planning store projection   */
        let retained = planning[group] as! [[String: Any]]              /* State retained for recovery */

        if periodic
        {
            _ = try JSONDecoder().decode(PeriodicReviewStore.Document.self, from: bytes)
        }
        else if weekly
        {
            _ = try JSONDecoder().decode(WeeklyReviewStore.Document.self, from: bytes)
        }
        else
        {
            _ = try JSONDecoder().decode(DailyPlanStore.Document.self, from: bytes)
        }

        let rawDocument =                                                       /* Raw document */
            try JSONSerialization.jsonObject(with: bytes) as! [String: Any]

        guard let sourceRecords = rawDocument[container] as? [String: [String: Any]] else
        {
            throw Failure.unsupported
        }

        var journal =           /* Migration identity journal */
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(MigrationIdentityJournal())) as! [String: Any]

        journal["previewWorkspaceID"] = baseline.workspaceID

        var entries: [[String: Any]] = []       /* Entries being processed */

        for (date, plan) in sourceRecords.sorted(by: { $0.key < $1.key })
        {
            let zone = plan["timeZoneID"] as! String                    /* Date conversion time zone */
            let old  = retained.first {                                 /* Previous operation state  */
                periodic ? ($0["id"] as? String == date.lowercased()) :
                    (($0["payload"] as? [String: Any])?[identityField] as? String == date)
            }

            if let old, (old["payload"] as? [String: Any])?["time_zone"] as? String != zone
            {
                throw Failure.unsupported
            }
            if periodic, let old
            {
                let payload = old["payload"] as! [String: Any]          /* Canonical record payload */

                guard payload["start_date"] as? String == plan["startKey"] as? String,
                      payload["end_date"] as? String == plan["endKey"] as? String else
                {
                    throw Failure.unsupported
                }
            }

            let name =                                                                                  /* Display or lookup name          */
                weekly ? kind + ":" + date : kind + ":" + date + ":" + zone
            let id   =                                                                                  /* Record UUID                     */
                try old?["id"] as? String ?? (periodic ? MigrationContentValues.lowerUUID(plan["id"]) :
                PortableRichCardExport.identity(namespace: baseline.workspaceID, name: name))
            var source: [String: Any] =                                                                 /* Source value for this operation */
                ["recordType": kind, "owner": key, "legacyID": periodic ? date.lowercased() : date]

            if family == .daily
            {
                source["discriminator"] = zone
            }
            entries.append(["source": source, "target": id])
        }
        guard retained.allSatisfy({
            let token =                 /* Retained operation token */
                periodic ? ($0["id"] as! String).uppercased() : ($0["payload"] as! [String: Any])[identityField] as! String

            return sourceRecords[token] != nil
        }) else
        {
            throw Failure.unsupported
        }

        journal["entries"] = entries

        var seeded                   =                                                                  /* Built-in initial content */
            try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
        var records: [[String: Any]] = []                                                               /* Records being processed  */

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

        let adapter =                                                                                   /* Store conversion adapter */
            try PortableEditableContent(records: records, assetFiles: baseline.media.filenames,
                retainedAliases: aliases, deletedCardIDs: PortableLocalDeletions.ids(in: export))
        var historical: [[String: Any]] = []                                                            /* Retained earlier state   */

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

        let content = planning["content"] as! [String: Any]     /* Content being processed */
        let lists   = content["lists"] as! [[String: Any]]      /* Ordered List records    */

        for card in content["cards"] as! [[String: Any]]
        {
            let payload = card["payload"] as! [String: Any]                             /* Canonical record payload  */
            let list    =                                                               /* List under consideration  */
                lists.first { $0["id"] as? String == payload["list_id"] as? String }!
            let owner   =                                                               /* Owning collection or Week */
                (list["payload"] as! [String: Any])["collection_id"] as! String

            historical.append(["source_collection_id": owner, "card_id": card["id"]!,
                "source_created_at_utc": payload["source_created_at_utc"]!, "title": "", "source_location": ""])
        }

        let converted =         /* Converted portable value */
            try MigrationPlanningPreview.prepare(values: [key: bytes], records: records, journal: &seeded,
                priorityResolver: { raw in

                    var targets: [String: [String: Any]] = [:]          /* Resolved operation targets */

                    for snapshot in historical
                    {
                        let native =                            /* Native workspace representation */
                            try adapter.priority(snapshot)
                        let fields = ["cardID"]                 /* Record fields under review      */

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

        let sourceDocument   =                                                                          /* Source document         */
            try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        let sources          =                                                                          /* Source records or files */
            sourceDocument[container] as! [String: Any]
        let previousBytes    = baseline.values[key] as? Data                                            /* Previous bytes          */
        let previousDocument =                                                                          /* Previous document       */
            try previousBytes.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
        let previousSources  =                                                                          /* Previous sources        */
            previousDocument?[container] as? [String: Any] ?? [:]
        var sourceFields     =                                                                          /* Source fields           */
            ["date": "id", "time_zone": "timeZoneID", "intention": "intention",
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
        if periodic
        {
            sourceFields = ["title": "title", "start_date": "startKey", "end_date": "endKey", "time_zone": "timeZoneID",
                "step": "step", "highlights": "highlights", "learned": "learned", "direction": "direction", "risks": "risks",
                "priorities": "priorities", "updated_at_utc": "updatedAt", "completed_at_utc": "completedAt",
                "starting_objectives": "startingObjectives", "objectives": "objectives"]
        }

        var updated = retained          /* Edited value to publish */

        for record in converted.records
        {
            if let index = updated.firstIndex(where: { $0["id"] as? String == record["id"] as? String })
            {
                var old     = updated[index]                            /* Previous operation state    */
                var payload = old["payload"] as! [String: Any]          /* Canonical record payload    */
                let fresh   = record["payload"] as! [String: Any]       /* New isolated instance       */
                let date    =                                           /* Date used by this operation */
                    periodic ? (record["id"] as! String).uppercased() : fresh[identityField] as! String
                let before  =                                           /* State before the operation  */
                    previousSources[date] as? [String: Any] ?? [:]
                let after   = sources[date] as! [String: Any]           /* State after the operation   */

                for (field, value) in fresh
                {
                    let source = sourceFields[field]!           /* Source value for this operation */

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


    /// @fcn PortableEditedExport.templateMetadata
    /// @brief Reconcile retained template names, library order and default Week selection
    /// @details Content reconciliation retains owner identities. Creation/removal and changes to
    ///          template date policy, kind, weekday mappings or example-focus metadata remain blocked
    /// @param[in] assembly Content-reconciled assembly
    /// @param[in] current Frozen native stores
    /// @param[in] baseline Imported native projection
    /// @return Assembly with retained template/library identities and supported metadata edits
    /// @throws Changed identity/context, unsupported library lifecycle or invalid default selection
    private static func templateMetadata(assembly: [String: Any], current: [String: Any],
        baseline: PortableWorkspaceCandidate) throws -> [String: Any]
    {
        let key = "Plenact.PlanningTemplates.v1"        /* Lookup or persistence key */

        guard let bytes = current[key] as? Data, let oldBytes = baseline.values[key] as? Data else
        {
            guard current[key] == nil, baseline.values[key] == nil else
            {
                throw Failure.unsupported
            }
            return assembly
        }

        let library  =                                                                  /* Retained library contents     */
            try JSONDecoder().decode(PlanningRoutineLibrary.self, from: bytes)
        let previous =                                                                  /* Previous value for comparison */
            try JSONDecoder().decode(PlanningRoutineLibrary.self, from: oldBytes)

        guard library.version == previous.version, library.version == 1,
              library.bundledRoutineRevision == previous.bundledRoutineRevision,
              Set(library.templates.map(\.id)).count == library.templates.count,
              Set(library.templates.map(\.id)) == Set(previous.templates.map(\.id)) else
        {
            throw Failure.structureChanged
        }

        var result    = assembly                                        /* Accumulated output value    */
        var export    = result["workspace_export"] as! [String: Any]    /* Prepared export evidence    */
        var base      = export["base_workspace"] as! [String: Any]      /* Base value before overrides */
        var planning  = base["planning"] as! [String: Any]              /* Planning store projection   */
        var templates = planning["templates"] as! [[String: Any]]       /* Reusable planning templates */
        var libraries =                                                 /* Libraries operation value   */
            planning["template_libraries"] as! [[String: Any]]

        guard libraries.count == 1,
              Set(templates.compactMap { $0["id"] as? String }) == Set(library.templates.map { $0.id.uuidString.lowercased() }) else
        {
            throw Failure.inconsistent
        }
        for template in library.templates
        {
            let old =                                                   /* Previous operation state */
                previous.templates.first { $0.id == template.id }!

            guard old.collection.id == template.collection.id, old.kind == template.kind,
                  old.anchorKey == template.anchorKey, old.timeZoneID == template.timeZoneID,
                  old.firstWeekday == template.firstWeekday, old.weekdays == template.weekdays,
                  old.exampleFocus == template.exampleFocus else
            {
                throw Failure.unsupported
            }

            let index =                                                                                 /* Element position */
                templates.firstIndex { $0["id"] as? String == template.id.uuidString.lowercased() }!

            if template.name != old.name
            {
                var payload =                                           /* Canonical record payload */
                    templates[index]["payload"] as! [String: Any]

                payload["name"] = template.name
                templates[index]["payload"] = payload
            }
        }
        if let selected = library.defaultWeekID
        {
            guard library.templates.first(where: { $0.id == selected })?.kind == .week else
            {
                throw Failure.unsupported
            }
        }

        var payload = libraries[0]["payload"] as! [String: Any]         /* Canonical record payload */

        payload["template_ids"] = library.templates.map { $0.id.uuidString.lowercased() }
        payload["default_week_id"] = library.defaultWeekID?.uuidString.lowercased() as Any? ?? NSNull()
        libraries[0]["payload"] = payload
        planning["templates"] = templates
        planning["template_libraries"] = libraries
        base["planning"] = planning
        export["base_workspace"] = base
        result["workspace_export"] = export

        return result
    }


    /// @fcn PortableEditedExport.shortcuts
    /// @brief Preserve authored Today shortcut selection and order against explicit owner/List identities
    /// @details Keeps retained singleton identity and unchanged canonical bytes; an explicitly saved new
    ///          store gets a deterministic workspace identity. Missing, malformed or ambiguous targets reject
    /// @param[in] assembly Current reconciled content graph
    /// @param[in] current Frozen native values, including rollover comparison aliases
    /// @param[in] baseline Retained imported settings projection
    /// @param[in] aliases Verified canonical-to-native identity mappings
    /// @return Assembly with the checked shortcut singleton or unchanged absence
    /// @throws Unknown fields, duplicates, excess items, missing stores or invalid owner membership
    private static func shortcuts(assembly: [String: Any], current: [String: Any],
        baseline: PortableWorkspaceCandidate, aliases: [String: Int]) throws -> [String: Any]
    {
        let key = TodayListPins.key     /* Lookup or persistence key */

        guard let bytes = current[key] as? Data else
        {
            guard current[key] == nil, baseline.values[key] == nil else
            {
                throw Failure.unsupported
            }
            return assembly
        }
        guard let raw = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]], raw.count <= 6,
              raw.allSatisfy({ Set($0.keys) == ["ownerID", "listID"] }) else
        {
            throw Failure.unsupported
        }

        let pins =                                                                      /* Ordered pinned shortcuts */
            try JSONDecoder().decode([WorkspaceListReference].self, from: bytes)

        guard Set(pins).count == pins.count else
        {
            throw Failure.unsupported
        }
        if let old = baseline.values[key] as? Data, equal(try nativeJSON(old), try nativeJSON(bytes))
        {
            return assembly
        }

        var result      = assembly                                              /* Accumulated output value      */
        var export      =                                                       /* Prepared export evidence      */
            result["workspace_export"] as! [String: Any]
        var base        =                                                       /* Base value before overrides   */
            export["base_workspace"] as! [String: Any]
        let content     =                                                       /* Content being processed       */
            (base["planning"] as! [String: Any])["content"] as! [String: Any]
        let lists       = content["lists"] as! [[String: Any]]                  /* Ordered List records          */
        let collections =                                                       /* Retained personal collections */
            content["collections"] as! [[String: Any]]
        let items       = try pins.map { pin -> [String: Any] in                /* Items being processed         */

            let owner   = pin.ownerID.uuidString.lowercased()           /* Normalized owner identifier */
            let targets = lists.filter                                  /* Resolved operation targets  */
            {
                aliases[$0["id"] as! String] == pin.listID &&
                    ($0["payload"] as! [String: Any])["collection_id"] as? String == owner
            }

            guard targets.count == 1, let target = targets.first?["id"] as? String,
                  let collection = collections.first(where: { $0["id"] as? String == owner }),
                  ((collection["payload"] as! [String: Any])["list_ids"] as? [String])?.contains(target) == true else
            {
                throw Failure.unsupported
            }
            return ["collection_id": owner, "list_id": target]
        }
        let retained = base["today_shortcuts"] as? [String: Any]        /* State retained for recovery */

        guard (baseline.values[key] != nil) == (retained != nil) else
        {
            throw Failure.inconsistent
        }

        let id =                                                                                /* Record or view identity  */
            try retained?["id"] as? String ?? PortableRichCardExport.identity(
                namespace: baseline.workspaceID, name: "today_shortcuts:" + key)
        var record =                                                                            /* Record being processed   */
            retained ?? ["user_data_model_version": "1.0", "payload_schema_version": 1,
            "record_type": "today_shortcuts", "id": id, "workspace_id": baseline.workspaceID]
        var payload = retained?["payload"] as? [String: Any] ?? [:]                             /* Canonical record payload */

        payload["items"] = items
        record["payload"] = payload
        base["today_shortcuts"] = record
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
        var current = try MigrationBackupReader.values(in: backup)      /* Current operation snapshot */
        let report  =                                                   /* Validation findings        */
            try JSONSerialization.jsonObject(with: MigrationBackupReader.file("NativePreflight.json", in: backup.files)) as! [String: Any]

        guard (report["review_codes"] as? [String]) == [] else
        {
            throw Failure.unsupported
        }

        let livePaths =                                                                 /* Live paths */
            Set((report["media"] as! [[String: Any]]).map { $0["path"] as! String })

        for (key, value) in current where LegacyStoreValidation.jsonKeys.contains(key)
        {
            if let bytes = value as? Data
            {
                let object = try JSONSerialization.jsonObject(with: bytes)      /* Decoded JSON object */

                guard LegacyStoreValidation.mediaIssues(object, store: key, files: livePaths).isEmpty else
                {
                    throw Failure.unsupported
                }
            }
        }

        let evidence =                                                                          /* Retained verification evidence */
            try PortableRuntimeEvidence.backupFiles(report: report, files: backup.files)

        guard let snapshot = evidence["CanonicalPackage.bin"].flatMap(FileWrapper.init(serializedRepresentation:)),
              let aliasBytes = evidence["IdentityAliases.json"],
              let aliasObject = try JSONSerialization.jsonObject(with: aliasBytes) as? [String: Any],
              var aliases = aliasObject["numeric_ids"] as? [String: Int] else
        {
            throw Failure.inconsistent
        }

        let reviewed =                                                                  /* Verified operation input      */
            try PortablePackageReview.review(files: snapshot)
        var baseline =                                                                  /* Original state for comparison */
            try PortableWorkspaceCandidate.prepare(reviewed, retainedAliases: aliases)

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

        // Device navigation and recovery values have no portable meaning. Every user-data key must match
        let retainedRecoveryKeys: Set<String> =                                                         /* Retained recovery keys */
            ["Plenact.ExampleCardLocations.Applied.v1", "Plenact.ExampleCardLocations.Backup.v1"]
        let deviceKeys                        =                                                         /* Device keys            */
            Set(current.keys.filter { retainedRecoveryKeys.contains($0) || $0.hasPrefix("Plenact.BoardViewport.") ||
            ["Plenact.ActivityRecents.v1", "Plenact.LibraryRecents.v1", "Plenact.RecentSearches.v1", "Plenact.LocalReactionAuthor.v1", "Plenact.LastViewedList.v1", "Plenact.Welcome.lastDeparture.v1"].contains($0) })
        let newSupportedKeys: Set<String> =                                                             /* New supported keys     */
            [TodayListPins.key, "Plenact.PeriodicReviews.v1", "Plenact.WeeklyReviews.v1", "Plenact.DailyPlans.v1", "Plenact.ReviewRhythm.v1", "Plenact.LocalProfile.v1", "Plenact.Studio.Settings.v1",
            "Plenact.Studio.Artwork.v1", "Plenact.WeekAppearance.v1"]

        guard Set(current.keys).subtracting(deviceKeys).subtracting(newSupportedKeys)
                == Set(baseline.values.keys).subtracting(newSupportedKeys),
              Set(baseline.values.keys).isSubset(of: Set(current.keys)) else
        {
            throw Failure.unsupported
        }

        let enriched       =                    /* Record with verified originals */
            try PortableRichCardExport.enrich(backup: backup, snapshot: snapshot, baseline: baseline)
        let mediaNames     = enriched.names     /* Media names                    */
        let exportSnapshot = enriched.files     /* Export snapshot                */

        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: exportSnapshot),
            retainedAliases: aliases, mediaFilenames: mediaNames)

        let originalAssembly =                                                                  /* Assembly before edits         */
            try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: exportSnapshot)) as! [String: Any]
        let rollover         =                                                                  /* New dated Week reconciliation */
            try PortableStructuralEdits.rollovers(assembly: originalAssembly, current: current,
                aliases: aliases, baseline: baseline)

        current = rollover.current
        aliases = rollover.aliases

        let rolloverPackage =           /* Rollover package */
            try PortableLocalDeletions.package(snapshot: exportSnapshot, assembly: rollover.assembly)

        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: rolloverPackage),
            retainedAliases: aliases, mediaFilenames: mediaNames)

        let deletionAssembly =                                                                          /* Deletion assembly */
            try PortableStructuralEdits.removeTemplates(assembly: rollover.assembly,
                current: current, aliases: aliases, baseline: baseline)
        let deletionPackage =                                                                           /* Deletion package  */
            try PortableLocalDeletions.package(snapshot: exportSnapshot, assembly: deletionAssembly)

        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: deletionPackage),
            retainedAliases: aliases, mediaFilenames: mediaNames)

        let creation =                                                                  /* New-record identity mapping */
            try PortableStructuralEdits.newTemplates(assembly: deletionAssembly,
                current: current, aliases: aliases, baseline: baseline)

        current = creation.current
        aliases = creation.aliases

        let creationPackage =           /* Creation package */
            try PortableLocalDeletions.package(snapshot: exportSnapshot, assembly: creation.assembly)

        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: creationPackage),
            retainedAliases: aliases, mediaFilenames: mediaNames)

        let contentAssembly =                                                                           /* Content assembly   */
            try PortableStructuralEdits.apply(assembly: creation.assembly,
                current: current, aliases: aliases, baseline: baseline)
        let shortcutAssembly  =                                                                         /* Shortcut assembly  */
            try shortcuts(assembly: contentAssembly, current: current, baseline: baseline, aliases: aliases)
        let templateAssembly  =                                                                         /* Template assembly  */
            try templateMetadata(assembly: shortcutAssembly, current: current, baseline: baseline)
        let rhythmAssembly    =                                                                         /* Rhythm assembly    */
            try reviewRhythm(assembly: templateAssembly, current: current, baseline: baseline)
        let dailyAssembly     =                                                                         /* Daily assembly     */
            try planningEdits(assembly: rhythmAssembly, current: current, baseline: baseline, aliases: aliases)
        let weeklyAssembly    =                                                                         /* Weekly assembly    */
            try planningEdits(assembly: dailyAssembly, current: current, baseline: baseline, aliases: aliases, family: .weekly)
        let effectiveAssembly =                                                                         /* Effective assembly */
            try planningEdits(assembly: weeklyAssembly, current: current, baseline: baseline, aliases: aliases, family: .periodic)
        let structuralPackage =                                                                         /* Structural package */
            try PortableLocalDeletions.package(snapshot: exportSnapshot, assembly: effectiveAssembly)

        baseline = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: structuralPackage), retainedAliases: aliases, mediaFilenames: mediaNames)

        var edits: [Int: [String: Any]] = [:]           /* Requested workspace changes */

        for (key, original) in baseline.values
        {
            let live = current[key]!    /* Current workspace state */

            if let before = original as? Data, let after = live as? Data
            {
                try reconcile(nativeJSON(before, store: key), nativeJSON(after, store: key), edits: &edits)
            }
            else if !equal(original, live)
            {
                throw Failure.unsupported
            }
        }

        let declared      = report["media"] as! [[String: Any]]                 /* Declared package metadata */
        let capturedPaths = Set(declared.map { $0["path"] as! String })         /* Captured paths            */

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

        var assembly = effectiveAssembly                                        /* Assembled portable records       */
        var export   = assembly["workspace_export"] as! [String: Any]           /* Prepared export evidence         */
        var base     = export["base_workspace"] as! [String: Any]               /* Base value before overrides      */
        var planning = base["planning"] as! [String: Any]                       /* Planning store projection        */
        var content  = planning["content"] as! [String: Any]                    /* Content being processed          */
        var cards    = content["cards"] as! [[String: Any]]                     /* Card records under consideration */
        var consumed = Set<Int>()                                               /* References already processed     */

        for index in cards.indices
        {
            guard let id = cards[index]["id"] as? String, let number = aliases[id], let patch = edits[number] else
            {
                continue
            }

            var payload = cards[index]["payload"] as! [String: Any]     /* Canonical record payload */

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

                let old  = payload[canonical] as? [String: Any]         /* Previous operation state  */
                let zone =                                              /* Date conversion time zone */
                    old?["time_zone"] as? String ?? baseline.timeZoneID

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

        let bytes    =                                          /* Encoded record bytes         */
            try JSONSerialization.data(withJSONObject: assembly, options: [.sortedKeys, .withoutEscapingSlashes])
        var manifest =                                          /* Package inventory and hashes */
            try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Manifest.json", in: exportSnapshot)) as! [String: Any]
        var files    = manifest["files"] as! [[String: Any]]    /* Files used by this operation */

        guard let index = files.firstIndex(where: { $0["path"] as? String == "Assembly.json" }) else
        {
            throw Failure.inconsistent
        }

        files[index] = ["path": "Assembly.json", "byte_length": bytes.count, "sha256": MigrationBackupReader.digest(bytes)]
        manifest["files"] = files

        let output =                                                    /* Operation output           */
            FileWrapper(directoryWithFileWrappers: ["Assembly.json": FileWrapper(regularFileWithContents: bytes),
            "Manifest.json": FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)),
            "Originals": exportSnapshot.fileWrappers!["Originals"]!])
        let result  =                                                   /* Verified portable package  */
            try PortablePackageReview.review(files: output)
        let rebuilt =                                                   /* Reconstructed output value */
            try PortableWorkspaceCandidate.prepare(result, retainedAliases: aliases, mediaFilenames: mediaNames)

        guard rebuilt.numericIDs == aliases else
        {
            throw Failure.inconsistent
        }
        // A second complete projection detects missed fields, stale duplicate Cards and lossy conversion
        for (key, value) in rebuilt.values
        {
            if let bytes = value as? Data, let live = current[key] as? Data
            {
                var unexpected: [Int: [String: Any]] = [:]      /* Unrecognized input values */

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

        let folder =    /* Working folder location */
            FileWrapper(directoryWithFileWrappers: ["PortableTestPackage": output, "EditedNativeBackup": sourceCopy])

        guard let frozen = folder.serializedRepresentation, frozen.count <= LegacyWorkspaceExport.maximumBytes else
        {
            throw LegacyWorkspaceExport.Failure.tooLarge
        }

        folder.preferredFilename = "Plenact Edited Portable Test"

        return folder
    }
}


/// Retains offline deletion intent without manufacturing server revision or acknowledgement metadata
/// @section Purpose
///     Model 1.1 keeps pre-deletion records and aliases while applying an explicit local presentation overlay
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
        let bytes    =                                          /* Encoded record bytes         */
            try JSONSerialization.data(withJSONObject: assembly, options: [.sortedKeys, .withoutEscapingSlashes])
        var manifest =                                          /* Package inventory and hashes */
            try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Manifest.json", in: snapshot)) as! [String: Any]
        var files    = manifest["files"] as! [[String: Any]]    /* Files used by this operation */

        guard let index = files.firstIndex(where: { $0["path"] as? String == "Assembly.json" }) else
        {
            throw PortablePackageReview.Failure.integrity
        }

        files[index] = ["path": "Assembly.json", "byte_length": bytes.count, "sha256": MigrationBackupReader.digest(bytes)]
        manifest["files"] = files

        let result =    /* Assembled package wrapper */
            FileWrapper(directoryWithFileWrappers: ["Assembly.json": FileWrapper(regularFileWithContents: bytes),
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
