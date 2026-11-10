// --------------------------------------------------------------------------------------------------
// @file       PortableStructuralEdits.swift
// @brief      Reserved identities and owner-aware structural reconciliation for editable portable workspaces
// @details    Supported User Data Model versions: 1.0 retained records and working 1.1 local deletions.
//             New native identities are reserved before Board creation; no server identity is manufactured
// --------------------------------------------------------------------------------------------------
import Foundation


/// Reserves private aliases independently of whether a creation or subsequent Files export succeeds
/// @section Purpose
///     Prevent number reuse and identity changes after cancellation, restart or repeated export
@MainActor
enum PortableCreationIdentity
{
    /// @fcn PortableCreationIdentity.reserve
    /// @brief Reserve collision-free numeric aliases and UUIDs only when portable runtime evidence exists
    /// @param[in] proposed Existing native allocator's proposed first number
    /// @param[in] count Number of sequential item identities required
    /// @param[in] root App container or isolated synthetic container
    /// @return First reserved native number, or unchanged proposed number for a nonportable workspace
    /// @throws Invalid evidence, exhausted identity space or failed atomic reservation
    static func reserve(proposed: Int, count: Int = 1,
        root: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) throws -> Int
    {
        let evidence =                                          /* Retained verification evidence */
            try PortableRuntimeEvidence.capture(root: root)

        guard !evidence.isEmpty else
        {
            return proposed
        }
        guard count > 0, count < 10000,
              var object = try JSONSerialization.jsonObject(with: evidence["IdentityAliases.json"]!) as? [String: Any],
              var aliases = object["numeric_ids"] as? [String: Int] else
        {
            throw PortableEditedExport.Failure.inconsistent
        }

        let maximum = aliases.values.max() ?? 0         /* Upper supported bound */

        guard maximum < Int.max - count else
        {
            throw PortableEditedExport.Failure.unsupported
        }

        let start = max(proposed, maximum + 1)          /* Range start */

        guard start > 0, start < Int.max - count else
        {
            throw PortableEditedExport.Failure.unsupported
        }
        for number in start..<(start + count)
        {
            aliases[UUID().uuidString.lowercased()] = number
        }

        object["numeric_ids"] = aliases

        let bytes  =                                                                            /* Encoded record bytes       */
            try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let target =                                                                            /* Target under consideration */
            root.appendingPathComponent(PortableRuntimeEvidence.area + "/IdentityAliases.json")

        guard try Data(contentsOf: target) == evidence["IdentityAliases.json"] else
        {
            throw PortableEditedExport.Failure.inconsistent
        }
        try bytes.write(to: target, options: [.atomic, .completeFileProtection])
        guard try Data(contentsOf: target) == bytes else
        {
            throw PortableEditedExport.Failure.inconsistent
        }
        return start
    }
}


/// Reconciles current native ownership/order against retained canonical records without matching titles
/// @section Purpose
///     Keep existing identities and unknown authored canonical values while adding explicitly reserved records
@MainActor
enum PortableStructuralEdits
{
    static let cardFields: [String: String] = [         /* Card fields */
        "word": "title", "isDivider": "is_divider", "isTitleChecked": "completed", "editingLocked": "editing_locked",
        "members": "members", "labelIDs": "label_ids", "startDate": "start", "dueDate": "due", "location": "location",
        "descriptionOverride": "description_override", "startDateKind": "start_kind", "dueDateKind": "due_kind",
        "showsDueDateInList": "shows_due_date_in_list", "sectionLayout": "section_layout", "subtitleOverride": "subtitle_override",
        "checklists": "checklists", "showsReactionsInPreviews": "shows_reactions_in_previews", "reactions": "reactions",
        "comments": "comments", "attachments": "attachments", "coverAttachmentID": "cover_attachment_id",
        "appearance": "appearance", "dismissedActivityIDs": "dismissed_activity_ids", "listDisplayFormat": "display_format",
        "itemPresentation": "presentation", "editHistory": "edit_history"
    ]


    /// @fcn PortableStructuralEdits.collections
    /// @brief Gather canonical owner UUIDs from native calendar, personal and template stores
    /// @param[in] values Frozen native stores
    /// @return Unique owner-qualified collection snapshots
    /// @throws Duplicate owner projections or malformed stores
    private static func collections(_ values: [String: Any]) throws -> [String: PersonalCollection]
    {
        var result: [String: PersonalCollection] = [:]          /* Accumulated output value */
        var owners: [PersonalCollection]         = []           /* Qualified record owners  */

        if let bytes = values["Plenact.CalendarWeeks.v1"] as? Data
        {
            owners += try JSONDecoder().decode(PlanningCalendarDocument.self, from: bytes).weeks.map(\.collection)
        }
        if let bytes = values["Plenact.PersonalCollections.v1"] as? Data
        {
            owners += try JSONDecoder().decode([PersonalCollection].self, from: bytes)
        }
        if let bytes = values["Plenact.PlanningTemplates.v1"] as? Data
        {
            owners += try JSONDecoder().decode(PlanningRoutineLibrary.self, from: bytes).templates.map(\.collection)
        }
        for owner in owners
        {
            let id = owner.id.uuidString.lowercased()           /* Record or view identity */

            guard result[id] == nil else
            {
                throw PortableEditedExport.Failure.inconsistent
            }

            result[id] = owner
        }
        return result
    }


    /// @fcn PortableStructuralEdits.context
    /// @brief Seed explicit identities and references for native Card conversion
    /// @param[in] workspace Retained canonical workspace UUID
    /// @param[in] zone Retained timezone
    /// @param[in] owner Current canonical owner
    /// @param[in] target Retained or newly reserved Card UUID
    /// @param[in] card Frozen native Card, or nil when converting List metadata
    /// @param[in] base Complete retained workspace
    /// @param[in] media Existing verified media placement
    /// @param[in] cardTargets Complete current owner-qualified Card identity map
    /// @param[in] values Frozen native stores including checklist week overrides
    /// @return Ephemeral conversion context; never saves a migration journal
    /// @throws Invalid source values or reference seeding
    private static func context(workspace: String, zone: String, owner: String, target: String,
        card: KanbanCard?, base: [String: Any], media: PortableMediaPlacement,
        cardTargets: [String: String], values: [String: Any]) throws -> MigrationContentValues
    {
        var journal =           /* Migration identity journal */
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(MigrationIdentityJournal())) as! [String: Any]

        journal["previewWorkspaceID"] = workspace

        var entries: [[String: Any]] = []       /* Entries being processed */

        /// @fcn PortableStructuralEdits.seed
        /// @brief Preserve a known source identity instead of allocating a replacement
        /// @param[in] kind Migration identity family
        /// @param[in] owner Explicit source scope
        /// @param[in] legacy Original token
        /// @param[in] id Existing canonical target
        /// @param[in] discriminator Optional file digest
        /// @return Void after appending one ephemeral mapping
        func seed(_ kind: String, owner: String, legacy: String, id: String, discriminator: String? = nil)
        {
            var source: [String: Any] =                                         /* Source value for this operation */
                ["recordType": kind, "owner": owner, "legacyID": legacy]

            source["discriminator"] = discriminator

            entries.append(["source": source, "target": id])
        }
        for label in base["labels"] as? [[String: Any]] ?? []
        {
            let id = label["id"] as! String     /* Record or view identity */

            seed("label", owner: "workspace_metadata", legacy: id, id: id)
        }

        let planning = base["planning"] as! [String: Any]       /* Planning store projection */

        for asset in planning["assets"] as? [[String: Any]] ?? []
        {
            let id = asset["id"] as! String     /* Record or view identity */

            guard let filename = media.filenames[id] else
            {
                throw PortableEditedExport.Failure.inconsistent
            }
            if let path = media.files.keys.sorted().first(where: { $0.hasSuffix("/" + filename) }), let bytes = media.files[path]
            {
                seed("asset", owner: "owned_media", legacy: path, id: id,
                    discriminator: MigrationBackupReader.digest(bytes))
            }
        }

        var nestedSources = Set<String>()       /* Nested sources */

        /// @fcn PortableStructuralEdits.seedNested
        /// @brief Preserve actual newly authored nested UUIDs in their supported identity families
        /// @param[in] value New Card subtree, excluding opaque encoded history values
        /// @return Void after seeding deterministic native nested identities
        func seedNested(_ value: Any)
        {
            if let object = value as? [String: Any]
            {
                var kind: String?       /* Content kind discriminator */

                if object["items"] is [Any]
                {
                    kind = "checklist"
                }
                else if object["isCompleted"] != nil
                {
                    kind = "checklist_item"
                }
                else if object["description"] != nil && object["checklists"] != nil
                {
                    kind = "action_detail"
                }
                else if object["author"] != nil && object["body"] != nil
                {
                    kind = "comment"
                }
                else if object["emoji"] != nil
                {
                    kind = "reaction"
                }
                else if object["displayName"] != nil
                {
                    kind = "assignee"
                }
                else if object["addedAt"] != nil
                {
                    kind = "attachment"
                }
                if let kind, let raw = object["id"] as? String, let id = UUID(uuidString: raw)?.uuidString.lowercased(),
                   nestedSources.insert(kind + ":" + id).inserted
                {
                    seed("nested_" + kind, owner: target, legacy: id, id: id)
                }
                for child in object.values
                {
                    seedNested(child)
                }
            }
            else if let values = value as? [Any]
            {
                for child in values
                {
                    seedNested(child)
                }
            }
        }
        if let card
        {
            seedNested(try MigrationContentValues.object(card))
        }

        journal["entries"] = entries

        let decoded =                                                                                   /* Decoded input value */
            try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
        let context =                                                                                   /* Operation context   */
            MigrationContentValues(journal: decoded, timeZoneID: zone,
                mediaDigests: media.files.mapValues { MigrationBackupReader.digest($0) })

        context.known = Set((base["labels"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })

        context.known.formUnion((planning["assets"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })

        context.cardTargets = cardTargets

        context.known.formUnion(cardTargets.values)

        let content = planning["content"] as! [String: Any]                             /* Content being processed */
        let owners  =                                                                   /* Qualified record owners */
            (content["collections"] as! [[String: Any]]).map { $0["id"] as! String }

        context.originalCollectionIDs = Dictionary(uniqueKeysWithValues: owners.map { ($0, $0) })
        context.collectionTargets = context.originalCollectionIDs
        context.ownerScopesByCollection = Dictionary(uniqueKeysWithValues: owners.map { ($0, [$0]) })

        context.known.formUnion(owners)

        context.calendarOwnerScopes = Set((planning["weeks"] as! [[String: Any]]).compactMap {
            ($0["payload"] as? [String: Any])?["collection_id"] as? String
        })

        if let bytes = values["Plenact.CalendarWeeks.v1"] as? Data
        {
            let calendar =                                                              /* Date calculation calendar */
                try JSONDecoder().decode(PlanningCalendarDocument.self, from: bytes)

            context.checklistWeekOverrides = Dictionary(uniqueKeysWithValues: (calendar.checklistLinkWeeks ?? [:]).map {
                ($0.key.uuidString.lowercased(), $0.value.uuidString.lowercased())
            })
        }
        return context
    }


    /// @fcn PortableStructuralEdits.rollovers
    /// @brief Convert newly retained dated Weeks with owner-qualified identities before structural comparison
    /// @details Operates on the frozen export candidate only; live stores and runtime evidence are unchanged
    /// @param[in] assembly Retained canonical assembly
    /// @param[in] current Frozen native stores
    /// @param[in] aliases Retained global editor aliases
    /// @param[in] baseline Original reconstructed workspace
    /// @return Expanded assembly, normalized comparison stores and stable aliases
    /// @throws Invalid dates, ambiguous references, unsupported metadata or conflicting retained identities
    static func rollovers(assembly: [String: Any], current: [String: Any], aliases: [String: Int],
        baseline: PortableWorkspaceCandidate) throws -> (assembly: [String: Any], current: [String: Any], aliases: [String: Int])
    {
        guard let bytes = current["Plenact.CalendarWeeks.v1"] as? Data,
              let oldBytes = baseline.values["Plenact.CalendarWeeks.v1"] as? Data else
        {
            return (assembly, current, aliases)
        }

        var calendar    =                                                               /* Date calculation calendar */
            try JSONDecoder().decode(PlanningCalendarDocument.self, from: bytes)
        let oldCalendar =                                                               /* Old calendar              */
            try JSONDecoder().decode(PlanningCalendarDocument.self, from: oldBytes)
        let oldOwners   = Set(oldCalendar.weeks.map { $0.collection.id })               /* Old owners                */
        let incoming    =                                                               /* Newly received content    */
            calendar.weeks.filter { !oldOwners.contains($0.collection.id) }

        guard !incoming.isEmpty else
        {
            return (assembly, current, aliases)
        }
        guard Set(oldCalendar.weeks.map(\.startKey)).isSubset(of: Set(calendar.weeks.map(\.startKey))),
              calendar.firstWeekday == oldCalendar.firstWeekday,
              incoming.allSatisfy({ !oldCalendar.weeks.map(\.startKey).contains($0.startKey) }),
              (calendar.checklistLinkWeeks ?? [:]) == (oldCalendar.checklistLinkWeeks ?? [:]) else
        {
            throw PortableEditedExport.Failure.structureChanged
        }
        if let preferences = current["Plenact.PlanPreferences.v1"] as? Data,
           try JSONDecoder().decode(LocalProfilePreferences.self, from: preferences).defaultListID != nil
        {
            // A numeric default without explicit owner provenance is ambiguous across newly added Weeks
            throw PortableEditedExport.Failure.unsupported
        }

        var assembly = assembly                                                 /* Assembled portable records  */
        var export   = assembly["workspace_export"] as! [String: Any]           /* Prepared export evidence    */
        var base     = export["base_workspace"] as! [String: Any]               /* Base value before overrides */
        var planning = base["planning"] as! [String: Any]                       /* Planning store projection   */
        var content  = planning["content"] as! [String: Any]                    /* Content being processed     */

        guard let indexes = planning["calendar_indexes"] as? [[String: Any]], indexes.count == 1 else
        {
            throw PortableEditedExport.Failure.inconsistent
        }

        let oldIndex                       = indexes[0]         /* Old index                    */
        var aliases                        = aliases            /* Local-to-portable identities */
        var comparison                     = current            /* Independent comparison value */
        var cardMaps: [String: [Int: Int]] = [:]                /* Card maps                    */
        var listMaps: [String: [Int: Int]] = [:]                /* List maps                    */

        for week in incoming
        {
            let owner   =                                                                       /* Normalized owner identifier */
                week.collection.id.uuidString.lowercased()
            let context =                                                                       /* Operation context           */
                try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                    owner: owner, target: owner, card: nil, base: base, media: baseline.media,
                    cardTargets: [:], values: [:])
            var isolated =                                                                      /* Independent test workspace  */
                PlanningCalendarDocument(currentWeekKey: week.startKey,
                    firstWeekday: calendar.firstWeekday, weeks: [week])

            isolated.checklistLinkWeeks = [:]

            let source: [String: Any] =                                                                 /* Source value for this operation  */
                ["Plenact.CalendarWeeks.v1": try JSONEncoder().encode(isolated),
                "Plenact.Board.v1": try JSONEncoder().encode(week.collection.lists)]
            let known =                                                                                 /* Previously recognized identities */
                (base["labels"] as! [[String: Any]]) + (planning["assets"] as! [[String: Any]])
            let first =                                                                                 /* First comparison value           */
                try MigrationContentConverter.convert(values: source, timeZoneID: baseline.timeZoneID,
                    mediaDigests: context.mediaDigests, existing: known, journal: context.journal)
            var journal =                                                                               /* Migration identity journal       */
                try JSONSerialization.jsonObject(with: first.journal.encoded()) as! [String: Any]
            var entries = journal["entries"] as! [[String: Any]]                                        /* Entries being processed          */
            let seeded  =                                                                               /* Built-in initial content         */
                Set(context.journal.entries.map { $0.target.uuidString.lowercased() })

            for index in entries.indices
            {
                if seeded.contains((entries[index]["target"] as! String).lowercased())
                {
                    continue
                }

                let key = entries[index]["source"] as! [String: Any]    /* Lookup or persistence key */

                if key["recordType"] as? String == "collection"
                {
                    entries[index]["target"] = owner
                }
                else
                {
                    let encoded =       /* Serialized representation */
                        try JSONSerialization.data(withJSONObject: key, options: [.sortedKeys, .withoutEscapingSlashes])

                    entries[index]["target"] = try PortableRichCardExport.identity(namespace: baseline.workspaceID,
                        name: "rollover:" + String(decoding: encoded, as: UTF8.self))
                }
            }

            let targetChanges =                                                                 /* Target changes */
                Dictionary(uniqueKeysWithValues: zip(first.journal.entries, entries).map {
                ($0.0.target.uuidString.lowercased(), ($0.1["target"] as! String).lowercased())
            })

            for index in entries.indices
            {
                var key = entries[index]["source"] as! [String: Any]    /* Lookup or persistence key */

                if (key["recordType"] as? String)?.hasPrefix("nested_") == true,
                   let owner = key["owner"] as? String, let target = targetChanges[owner.lowercased()]
                {
                    key["owner"] = target
                    entries[index]["source"] = key

                    let encoded =       /* Serialized representation */
                        try JSONSerialization.data(withJSONObject: key, options: [.sortedKeys, .withoutEscapingSlashes])

                    entries[index]["target"] = try PortableRichCardExport.identity(namespace: baseline.workspaceID,
                        name: "rollover:" + String(decoding: encoded, as: UTF8.self))
                }
            }

            journal["entries"] = entries

            let stable    =                                                                             /* Identity retained across edits */
                try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
            let converted =                                                                             /* Converted portable value       */
                try MigrationContentConverter.convert(values: source, timeZoneID: baseline.timeZoneID,
                    mediaDigests: context.mediaDigests, existing: known, journal: stable)

            guard !converted.records.contains(where: { $0["record_type"] as? String == "unavailable_reference" }) else
            {
                throw PortableEditedExport.Failure.unsupported
            }

            var listMap: [Int: Int] = [:]       /* List map */
            var cardMap: [Int: Int] = [:]       /* Card map */

            for entry in stable.entries where ["list", "card"].contains(entry.source.recordType)
            {
                guard let number = Int(entry.source.legacyID), entry.source.owner == owner else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }

                let id      = entry.target.uuidString.lowercased()      /* Record or view identity */
                let maximum = aliases.values.max() ?? 0                 /* Upper supported bound   */

                guard maximum < Int.max - 1 else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }

                let next = maximum + 1          /* Candidate next state */

                aliases[id] = aliases[id] ?? next

                if entry.source.recordType == "list"
                {
                    listMap[number] = aliases[id]!
                }
                else
                {
                    cardMap[number] = aliases[id]!
                }
            }

            cardMaps[owner] = cardMap
            listMaps[owner] = listMap

            // Only editor aliases are normalized; all authored native values remain in the comparison.
            // Nested links use the same owner-qualified Card aliases as the copied Cards themselves
            /// @fcn PortableStructuralEdits.rollovers.references
            /// @brief Translate verified same-Week links in the frozen comparison without touching history bytes
            /// @param[in] value Newly converted native Card subtree
            /// @return Equivalent subtree with canonical reconstruction aliases
            /// @throws A reference missing from the explicitly converted owner mapping
            func references(_ value: Any) throws -> Any
            {
                if var object = value as? [String: Any]
                {
                    for field in ["cardID", "retainedCardID"]
                    {
                        if let number = object[field] as? Int
                        {
                            guard let target = cardMap[number] else
                            {
                                throw PortableEditedExport.Failure.inconsistent
                            }

                            object[field] = target
                        }
                    }
                    for field in object.keys where field != "editHistory"
                    {
                        object[field] = try references(object[field]!)
                    }
                    return object
                }
                if let array = value as? [Any]
                {
                    return try array.map(references)
                }
                return value
            }

            var raw        =                                                                            /* Unprocessed source value   */
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(week)) as! [String: Any]
            var collection = raw["collection"] as! [String: Any]                                        /* Personal collection record */
            var lists      = collection["lists"] as! [[String: Any]]                                    /* Ordered List records       */

            for index in lists.indices
            {
                lists[index]["id"] = listMap[lists[index]["id"] as! Int]!

                for field in ["cards", "archivedCards"]
                {
                    var cards =                                         /* Card records under consideration */
                        lists[index][field] as? [[String: Any]] ?? []

                    for card in cards.indices
                    {
                        cards[card]["id"] = cardMap[cards[card]["id"] as! Int]!
                        cards[card] = try references(cards[card]) as! [String: Any]
                    }

                    lists[index][field] = cards
                }
            }

            collection["lists"] = lists
            collection["isArchived"] = week.collection.isArchived == true
            collection["color"] = ["red": week.collection.color.red,
                "green": week.collection.color.green, "blue": week.collection.color.blue]
            collection["savedCardIDs"] = try week.collection.savedCardIDs.map { id -> Int in
                guard let target = cardMap[id] else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }
                return target
            }
            raw["collection"] = collection
            raw["dayListIDs"] = week.dayListIDs.mapValues { listMap[$0]! }

            let normalized =    /* Comparison-normalized value */
                try JSONDecoder().decode(DatedPlanningWeek.self, from: JSONSerialization.data(withJSONObject: raw))

            calendar.weeks[calendar.weeks.firstIndex(where: { $0.collection.id == week.collection.id })!] = normalized

            for (field, kind) in [("collections", "collection"), ("lists", "list"), ("cards", "card")]
            {
                content[field] = (content[field] as! [[String: Any]]) + converted.records.filter { $0["record_type"] as? String == kind }
            }

            planning["weeks"] = (planning["weeks"] as! [[String: Any]]) + converted.records.filter { $0["record_type"] as? String == "calendar_week" }
        }
        if let data = comparison[TodayListPins.key] as? Data
        {
            guard var pins = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], pins.count <= 6,
                  pins.allSatisfy({ Set($0.keys) == ["ownerID", "listID"] }) else
            {
                throw PortableEditedExport.Failure.unsupported
            }

            let references =                                                            /* Qualified record references */
                try JSONDecoder().decode([WorkspaceListReference].self, from: data)

            guard Set(references).count == references.count else
            {
                throw PortableEditedExport.Failure.unsupported
            }
            for index in references.indices
            {
                let pin = references[index]     /* Pinned shortcut reference */

                if let mapping = listMaps[pin.ownerID.uuidString.lowercased()]
                {
                    guard let target = mapping[pin.listID] else
                    {
                        throw PortableEditedExport.Failure.inconsistent
                    }

                    pins[index]["listID"] = target
                }
            }

            comparison[TodayListPins.key] = try JSONSerialization.data(withJSONObject: pins, options: .sortedKeys)
        }

        var index   = oldIndex                                  /* Element position         */
        var payload = index["payload"] as! [String: Any]        /* Canonical record payload */
        let weeks   = planning["weeks"] as! [[String: Any]]     /* Retained dated Weeks     */

        payload["current_week_start_date"] = calendar.currentWeekKey
        payload["week_ids"] = try calendar.weeks.map { source -> String in
            guard let record = weeks.first(where: { ($0["payload"] as? [String: Any])?["collection_id"] as? String == source.collection.id.uuidString.lowercased() }) else
            {
                throw PortableEditedExport.Failure.inconsistent
            }
            return record["id"] as! String
        }
        index["payload"] = payload
        planning["calendar_indexes"] = [index]
        planning["content"] = content
        base["planning"] = planning
        export["base_workspace"] = base
        assembly["workspace_export"] = export
        comparison["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(calendar)

        guard let active = calendar.weeks.first(where: { $0.startKey == calendar.currentWeekKey }) else
        {
            throw PortableEditedExport.Failure.inconsistent
        }

        let rawCalendar =                                                               /* Raw calendar */
            try JSONDecoder().decode(PlanningCalendarDocument.self, from: bytes)

        guard let rawActive = rawCalendar.weeks.first(where: { $0.startKey == calendar.currentWeekKey }),
              let board = current["Plenact.Board.v1"] as? Data,
              try JSONDecoder().decode([KanbanList].self, from: board) == rawActive.collection.lists else
        {
            throw PortableEditedExport.Failure.inconsistent
        }
        guard Set(current["Plenact.SavedCardIDs.v1"] as? [Int] ?? []) == rawActive.collection.savedCardIDs else
        {
            throw PortableEditedExport.Failure.inconsistent
        }

        comparison["Plenact.Board.v1"] = try JSONEncoder().encode(active.collection.lists)
        comparison["Plenact.SavedCardIDs.v1"] = active.collection.savedCardIDs.sorted()

        if let bytes = current["Plenact.LibraryImportant.v1"] as? Data
        {
            var items =                                                                 /* Items being processed */
                try JSONSerialization.jsonObject(with: bytes) as! [[String: Any]]

            for i in items.indices
            {
                let owner =                                             /* Owning collection or Week */
                    (items[i]["collectionID"] as! String).lowercased()

                if let mapping = cardMaps[owner], let id = items[i]["cardID"] as? Int
                {
                    guard let target = mapping[id] else
                    {
                        throw PortableEditedExport.Failure.inconsistent
                    }

                    items[i]["cardID"] = target
                }
            }

            comparison["Plenact.LibraryImportant.v1"] = try JSONSerialization.data(withJSONObject: items)
        }
        return (assembly, comparison, aliases)
    }


    /// @fcn PortableStructuralEdits.removeTemplates
    /// @brief Remove exclusively owned template content from a complete local snapshot
    /// @details Retains original files and exact native recovery evidence. Surviving references,
    ///          transferred aliases and pending Card deletion intent stop export rather than guessing
    /// @param[in] assembly Verified retained assembly
    /// @param[in] current Frozen source stores
    /// @param[in] aliases Retained numeric identities
    /// @param[in] baseline Reconstructed imported workspace
    /// @return Pruned assembly; live source and runtime evidence remain unchanged
    /// @throws Unsupported ownership, references or malformed library identity
    static func removeTemplates(assembly: [String: Any], current: [String: Any], aliases: [String: Int],
        baseline: PortableWorkspaceCandidate) throws -> [String: Any]
    {
        let key = "Plenact.PlanningTemplates.v1"        /* Lookup or persistence key */

        guard let bytes = current[key] as? Data, let old = baseline.values[key] as? Data else
        {
            return assembly
        }

        let library  =                                                          /* Retained library contents     */
            try JSONDecoder().decode(PlanningRoutineLibrary.self, from: bytes)
        let previous =                                                          /* Previous value for comparison */
            try JSONDecoder().decode(PlanningRoutineLibrary.self, from: old)
        let retained = Set(previous.templates.map(\.id))                        /* State retained for recovery   */
        let live     = Set(library.templates.map(\.id))                         /* Current workspace state       */

        guard live.count == library.templates.count else
        {
            throw PortableEditedExport.Failure.structureChanged
        }

        let removed = retained.subtracting(live)        /* Entries selected for removal */

        guard !removed.isEmpty else
        {
            return assembly
        }

        var assembly   = assembly                                               /* Assembled portable records  */
        var export     =                                                        /* Prepared export evidence    */
            assembly["workspace_export"] as! [String: Any]
        var base       =                                                        /* Base value before overrides */
            export["base_workspace"] as! [String: Any]
        var planning   = base["planning"] as! [String: Any]                     /* Planning store projection   */
        var content    = planning["content"] as! [String: Any]                  /* Content being processed     */
        let removedIDs = Set(removed.map { $0.uuidString.lowercased() })        /* Removed i ds                */
        let owners     =                                                        /* Qualified record owners     */
            Set(previous.templates.filter { removed.contains($0.id) }.map { $0.collection.id.uuidString.lowercased() })
        var deleted    = removedIDs.union(owners)                               /* Content after deletion      */

        for record in content["lists"] as! [[String: Any]]
        {
            if owners.contains((record["payload"] as! [String: Any])["collection_id"] as! String)
            {
                deleted.insert(record["id"] as! String)
            }
        }
        for record in content["cards"] as! [[String: Any]]
        {
            if deleted.contains((record["payload"] as! [String: Any])["list_id"] as! String)
            {
                deleted.insert(record["id"] as! String)
            }
        }
        func collectNestedIDs(_ value: Any)
        {
            if let object = value as? [String: Any]
            {
                if let id = object["id"] as? String, UUID(uuidString: id) != nil
                {
                    deleted.insert(id.lowercased())
                }
                for child in object.values
                {
                    collectNestedIDs(child)
                }
            }
            else if let array = value as? [Any]
            {
                for child in array
                {
                    collectNestedIDs(child)
                }
            }
        }
        for record in content["cards"] as! [[String: Any]] where deleted.contains(record["id"] as! String)
        {
            collectNestedIDs(record["payload"]!)
        }
        guard Set(export["local_card_deletions"] as? [String] ?? []).isDisjoint(with: deleted) else
        {
            throw PortableEditedExport.Failure.unsupported
        }

        // New captures can borrow source numbers. Only retained surviving owners are transfer evidence
        var surviving       = current           /* Entries retained after edits */
        var retainedLibrary = library           /* Retained library             */

        retainedLibrary.templates.removeAll { !retained.contains($0.id) }

        surviving[key] = try JSONEncoder().encode(retainedLibrary)

        let removedNumbers = Set(deleted.compactMap { aliases[$0] })    /* Removed numbers */

        for owner in try collections(surviving).values
        {
            guard !owners.contains(owner.id.uuidString.lowercased()),
                  owner.lists.allSatisfy({ list in

                      !removedNumbers.contains(list.id) &&
                          (list.cards + list.archivedCards).allSatisfy { !removedNumbers.contains($0.id) }
                  }) else
            {
                throw PortableEditedExport.Failure.structureChanged
            }
        }
        for field in ["collections", "lists", "cards"]
        {
            content[field] = (content[field] as! [[String: Any]]).filter { !deleted.contains($0["id"] as! String) }
        }

        planning["content"] = content
        planning["templates"] = (planning["templates"] as! [[String: Any]]).filter { !removedIDs.contains($0["id"] as! String) }

        var libraries =                                         /* Libraries operation value */
            planning["template_libraries"] as! [[String: Any]]

        guard libraries.count == 1 else
        {
            throw PortableEditedExport.Failure.unsupported
        }

        var payload = libraries[0]["payload"] as! [String: Any]         /* Canonical record payload */

        payload["template_ids"] = (payload["template_ids"] as! [String]).filter { !removedIDs.contains($0) }

        if let id = payload["default_week_id"] as? String, removedIDs.contains(id)
        {
            payload["default_week_id"] = NSNull()
        }

        libraries[0]["payload"] = payload
        planning["template_libraries"] = libraries
        base["planning"] = planning
        base["content_selections"] = (base["content_selections"] as! [[String: Any]]).filter
        {
            !deleted.contains(($0["payload"] as! [String: Any])["card_id"] as! String)
        }

        func referencesDeleted(_ value: Any, field: String = "") -> Bool
        {
            if let object = value as? [String: Any]
            {
                if object["record_type"] != nil, let id = object["id"] as? String, deleted.contains(id.lowercased())
                {
                    return true
                }
                return object.contains { referencesDeleted($0.value, field: $0.key) }
            }
            if let array = value as? [Any]
            {
                return array.contains { referencesDeleted($0, field: field) }
            }
            return (field.hasSuffix("_id") || field.hasSuffix("_ids")) &&
                (value as? String).map { deleted.contains($0.lowercased()) } == true
        }
        guard !referencesDeleted(base) else
        {
            throw PortableEditedExport.Failure.unsupported
        }

        export["base_workspace"] = base
        assembly["workspace_export"] = export

        return assembly
    }


    /// @fcn PortableStructuralEdits.newTemplates
    /// @brief Convert newly authored templates with independent owner-qualified portable identities
    /// @details Normalizes only frozen comparison identities; live stores, originals and runtime stay
    ///          unchanged. Retained removals are reconciled first; unknown/external references fail closed
    /// @param[in] assembly Verified content baseline
    /// @param[in] current Frozen source stores
    /// @param[in] aliases Retained numeric aliases
    /// @param[in] baseline Reconstructed imported workspace
    /// @return Expanded assembly, comparison stores and aliases
    /// @throws Invalid identities, unresolved references, malformed content or unsupported lifecycle
    static func newTemplates(assembly: [String: Any], current: [String: Any], aliases: [String: Int],
        baseline: PortableWorkspaceCandidate) throws -> (assembly: [String: Any], current: [String: Any], aliases: [String: Int])
    {
        let key = "Plenact.PlanningTemplates.v1"        /* Lookup or persistence key */

        guard let bytes = current[key] as? Data, let oldBytes = baseline.values[key] as? Data else
        {
            return (assembly, current, aliases)
        }

        let library  =                                                                  /* Retained library contents     */
            try JSONDecoder().decode(PlanningRoutineLibrary.self, from: bytes)
        let previous =                                                                  /* Previous value for comparison */
            try JSONDecoder().decode(PlanningRoutineLibrary.self, from: oldBytes)
        let retained = Set(previous.templates.map(\.id))                                /* State retained for recovery   */

        guard Set(library.templates.map(\.id)).count == library.templates.count,
              retained.isSubset(of: Set(library.templates.map(\.id))) else
        {
            throw PortableEditedExport.Failure.structureChanged
        }

        let incoming =                                                  /* Newly received content */
            library.templates.filter { !retained.contains($0.id) }

        guard !incoming.isEmpty else
        {
            return (assembly, current, aliases)
        }

        var assembly  = assembly                                        /* Assembled portable records  */
        var export    =                                                 /* Prepared export evidence    */
            assembly["workspace_export"] as! [String: Any]
        var base      = export["base_workspace"] as! [String: Any]      /* Base value before overrides */
        var planning  = base["planning"] as! [String: Any]              /* Planning store projection   */
        var content   = planning["content"] as! [String: Any]           /* Content being processed     */
        var libraries =                                                 /* Libraries operation value   */
            planning["template_libraries"] as! [[String: Any]]

        guard libraries.count == 1 else
        {
            throw PortableEditedExport.Failure.unsupported
        }

        var rawLibrary   =                                                      /* Raw library                  */
            try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        var rawTemplates = rawLibrary["templates"] as! [[String: Any]]          /* Raw templates                */
        var aliases      = aliases                                              /* Local-to-portable identities */
        var comparison   = current                                              /* Independent comparison value */

        for template in incoming
        {
            let id          = template.id.uuidString.lowercased()                                       /* Record or view identity          */
            let sourceOwner = template.collection.id.uuidString.lowercased()                            /* Source owner                     */
            let scope       = "template:" + id + ":" + sourceOwner                                      /* Owner or search scope            */
            let owner       =                                                                           /* Owning collection or Week        */
                try PortableRichCardExport.identity(namespace: baseline.workspaceID, name: "template_owner:" + id)
            let context     =                                                                           /* Operation context                */
                try self.context(workspace: baseline.workspaceID, zone: template.timeZoneID,
                    owner: owner, target: owner, card: nil, base: base, media: baseline.media, cardTargets: [:], values: current)
            let index                 =                                                                 /* Element position                 */
                rawTemplates.firstIndex { ($0["id"] as? String)?.lowercased() == id }!
            let source: [String: Any] =                                                                 /* Source value for this operation  */
                [key: try JSONSerialization.data(withJSONObject:
                ["version": 1, "templates": [rawTemplates[index]]])]
            let known =                                                                                 /* Previously recognized identities */
                (base["labels"] as! [[String: Any]]) + (planning["assets"] as! [[String: Any]])
            let first =                                                                                 /* First comparison value           */
                try MigrationContentConverter.convert(values: source, timeZoneID: template.timeZoneID,
                    mediaDigests: context.mediaDigests, existing: known, journal: context.journal)
            var journal =                                                                               /* Migration identity journal       */
                try JSONSerialization.jsonObject(with: first.journal.encoded()) as! [String: Any]
            var entries = journal["entries"] as! [[String: Any]]                                        /* Entries being processed          */
            let seeded  =                                                                               /* Built-in initial content         */
                Set(context.journal.entries.map { $0.target.uuidString.lowercased() })

            for index in entries.indices
            {
                if seeded.contains((entries[index]["target"] as! String).lowercased())
                {
                    continue
                }

                let source =                                    /* Source value for this operation */
                    entries[index]["source"] as! [String: Any]

                switch source["recordType"] as! String
                {
                case "collection":

                    entries[index]["target"] = owner

                case "planning_template":

                    entries[index]["target"] = id

                case "template_library":

                    entries[index]["target"] = libraries[0]["id"]!

                default:

                    let token =         /* Retained operation token */
                        try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys, .withoutEscapingSlashes])

                    entries[index]["target"] = try PortableRichCardExport.identity(namespace: baseline.workspaceID,
                        name: "template_creation:" + String(decoding: token, as: UTF8.self))
                }
            }

            let changedTargets =                                                                /* Changed targets */
                Dictionary(uniqueKeysWithValues: zip(first.journal.entries, entries).map {
                ($0.0.target.uuidString.lowercased(), ($0.1["target"] as! String).lowercased())
            })

            for index in entries.indices
            {
                var source =                                    /* Source value for this operation */
                    entries[index]["source"] as! [String: Any]

                if (source["recordType"] as? String)?.hasPrefix("nested_") == true,
                   let old = source["owner"] as? String, let target = changedTargets[old.lowercased()]
                {
                    source["owner"] = target
                    entries[index]["source"] = source

                    let token =         /* Retained operation token */
                        try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys, .withoutEscapingSlashes])

                    entries[index]["target"] = try PortableRichCardExport.identity(namespace: baseline.workspaceID,
                        name: "template_creation:" + String(decoding: token, as: UTF8.self))
                }
            }

            journal["entries"] = entries

            let stable    =                                                                             /* Identity retained across edits */
                try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
            let converted =                                                                             /* Converted portable value       */
                try MigrationContentConverter.convert(values: source, timeZoneID: template.timeZoneID,
                    mediaDigests: context.mediaDigests, existing: known, journal: stable)

            guard !converted.records.contains(where: { $0["record_type"] as? String == "unavailable_reference" }) else
            {
                throw PortableEditedExport.Failure.unsupported
            }

            var lists: [Int: Int]          = [:]        /* Ordered List records             */
            var cards: [Int: Int]          = [:]        /* Card records under consideration */
            var cardTargets: [Int: String] = [:]        /* Card targets                     */

            for entry in stable.entries where ["list", "card"].contains(entry.source.recordType)
            {
                guard entry.source.owner == scope, let number = Int(entry.source.legacyID),
                      (aliases.values.max() ?? 0) < Int.max - 1 else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }

                let target = entry.target.uuidString.lowercased()       /* Target under consideration */

                aliases[target] = aliases[target] ?? (aliases.values.max() ?? 0) + 1

                if entry.source.recordType == "list"
                {
                    lists[number] = aliases[target]!
                }
                else
                {
                    cards[number] = aliases[target]!
                    cardTargets[number] = target
                }
            }

            /// @fcn PortableStructuralEdits.normalizeTemplateCard
            /// @brief Translate declared nested identities and same-owner links in frozen Card values
            /// @param[in] value Raw Card subtree
            /// @param[in] target Explicit owning canonical Card
            /// @return Identity-normalized comparison subtree; opaque history remains unchanged
            func normalize(_ value: Any, target: String) throws -> Any
            {
                if var object = value as? [String: Any]
                {
                    if let raw = object["id"] as? String
                    {
                        let matches =                                                                   /* Matching source entries */
                            stable.entries.filter { $0.source.recordType.hasPrefix("nested_") &&
                            $0.source.owner == target && $0.source.legacyID == raw.lowercased() }

                        guard matches.count <= 1 else
                        {
                            throw PortableEditedExport.Failure.unsupported
                        }
                        if let mapped = matches.first
                        {
                            object["id"] = mapped.target.uuidString
                        }
                    }
                    if let cover = object["coverAttachmentID"] as? String
                    {
                        guard let attachment = stable.entries.first(where: { $0.source.recordType == "nested_attachment" &&
                            $0.source.owner == target && $0.source.legacyID == cover.lowercased() }) else
                        {
                            throw PortableEditedExport.Failure.unsupported
                        }

                        object["coverAttachmentID"] = attachment.target.uuidString
                    }
                    if let linked = object["linkedCollectionID"] as? String
                    {
                        guard linked.lowercased() == sourceOwner else
                        {
                            throw PortableEditedExport.Failure.unsupported
                        }

                        object["linkedCollectionID"] = UUID(uuidString: owner)!.uuidString
                    }
                    for field in ["cardID", "retainedCardID"]
                    {
                        if let linked = object[field] as? Int
                        {
                            guard let mapped = cards[linked] else
                            {
                                throw PortableEditedExport.Failure.unsupported
                            }

                            object[field] = mapped
                        }
                    }
                    for field in object.keys where field != "editHistory"
                    {
                        object[field] = try normalize(object[field]!, target: target)
                    }
                    return object
                }
                if let array = value as? [Any]
                {
                    return try array.map { try normalize($0, target: target) }
                }
                return value
            }

            var raw        = rawTemplates[index]                        /* Unprocessed source value   */
            var collection = raw["collection"] as! [String: Any]        /* Personal collection record */
            var rawLists   = collection["lists"] as! [[String: Any]]    /* Raw lists                  */

            for index in rawLists.indices
            {
                rawLists[index]["id"] = lists[rawLists[index]["id"] as! Int]!

                for field in ["cards", "archivedCards"]
                {
                    var values =                                                /* Values being processed */
                        rawLists[index][field] as? [[String: Any]] ?? []

                    for index in values.indices
                    {
                        let number = values[index]["id"] as! Int        /* Local numeric value */

                        values[index] = try normalize(values[index], target: cardTargets[number]!) as! [String: Any]
                        values[index]["id"] = cards[number]!
                    }
                    if rawLists[index][field] != nil || !values.isEmpty
                    {
                        rawLists[index][field] = values
                    }
                }
            }

            collection["id"] = UUID(uuidString: owner)!.uuidString
            collection["lists"] = rawLists
            collection["isArchived"] = template.collection.isArchived == true
            collection["color"] = ["red": template.collection.color.red,
                "green": template.collection.color.green, "blue": template.collection.color.blue]
            collection["savedCardIDs"] = try template.collection.savedCardIDs.map { number -> Int in

                guard let value = cards[number] else
                {
                    throw PortableEditedExport.Failure.unsupported
                }
                return value
            }.sorted()
            raw["collection"] = collection

            let weekdays = raw["weekdays"] as! [String: Int]    /* Ordered weekday values */

            raw["weekdays"] = weekdays.mapValues { lists[$0]! }

            if var focus = raw["exampleFocus"] as? [String: Any]
            {
                for field in ["important", "bookmarked", "allDay"]
                {
                    focus[field] = try (focus[field] as! [Int]).map { number -> Int in

                        guard let value = cards[number] else
                        {
                            throw PortableEditedExport.Failure.unsupported
                        }
                        return value
                    }.sorted()
                }

                raw["exampleFocus"] = focus
            }

            rawTemplates[index] = raw

            for (field, kind) in [("collections", "collection"), ("lists", "list"), ("cards", "card")]
            {
                content[field] = (content[field] as! [[String: Any]]) + converted.records.filter { $0["record_type"] as? String == kind }
            }

            planning["templates"] = (planning["templates"] as! [[String: Any]]) + converted.records.filter { $0["record_type"] as? String == "planning_template" }
        }

        var payload = libraries[0]["payload"] as! [String: Any]         /* Canonical record payload */

        payload["template_ids"] = library.templates.map { $0.id.uuidString.lowercased() }
        payload["default_week_id"] = library.defaultWeekID?.uuidString.lowercased() as Any? ?? NSNull()
        libraries[0]["payload"] = payload
        planning["template_libraries"] = libraries
        planning["content"] = content
        base["planning"] = planning
        export["base_workspace"] = base
        assembly["workspace_export"] = export
        rawLibrary["templates"] = rawTemplates
        comparison[key] = try JSONSerialization.data(withJSONObject: rawLibrary)

        return (assembly, comparison, aliases)
    }


    /// @fcn PortableStructuralEdits.personalization
    /// @brief Reconcile authored profile and Studio values using retained identities and verified media
    /// @param[in,out] base Retained base-model records
    /// @param[in,out] export Working composition including appearance/library metadata
    /// @param[in] current Frozen native stores
    /// @param[in] baseline Reconstructed import baseline
    /// @return Void; mutations affect only the export candidate
    /// @throws Unknown fields, missing originals, identity changes or incompatible metadata
    private static func personalization(base: inout [String: Any], export: inout [String: Any],
        current: [String: Any], baseline: PortableWorkspaceCandidate) throws
    {
        let context =                                                                           /* Operation context */
            try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                owner: baseline.workspaceID, target: baseline.workspaceID, card: nil, base: base,
                media: baseline.media, cardTargets: [:], values: current)

        guard Set(baseline.media.filenames.values).count == baseline.media.filenames.count else
        {
            throw PortableEditedExport.Failure.unsupported
        }
        for (id, name) in baseline.media.filenames
        {
            for area in ["Documents/ProfileAvatars", "Library/Application Support/PlenactStudioArtwork",
                "Library/Application Support/PlenactCollectionBackgrounds"]
            {
                context.assetTargets[area + "/" + name] = id
            }
        }
        if let bytes = current["Plenact.LocalProfile.v1"] as? Data
        {
            let profile =                                                       /* Local profile record            */
                try JSONDecoder().decode(LocalProfile.self, from: bytes)
            let raw     = try MigrationContentValues.object(profile)            /* Unprocessed source value        */
            let source  =                                                       /* Source value for this operation */
                try JSONSerialization.jsonObject(with: bytes) as! [String: Any]

            guard Set(source.keys).isSubset(of: ["id", "createdAt", "displayName", "email", "context",
                "avatarColor", "avatarIcon", "avatarForegroundColor", "avatarPhotoFileName", "preferences"]) else
            {
                throw PortableEditedExport.Failure.unsupported
            }

            var profiles = base["profiles"] as! [[String: Any]]         /* Retained local profile records */

            guard profiles.count <= 1 else
            {
                throw PortableEditedExport.Failure.unsupported
            }

            let id = profile.id.uuidString.lowercased()         /* Record or view identity  */
            var document: [String: Any]                         /* Source document snapshot */
            var payload: [String: Any]                          /* Canonical record payload */
            var previousRaw: [String: Any] = [:]                /* Previous raw             */

            if let old = profiles.first
            {
                guard old["id"] as? String == id,
                      let oldBytes = baseline.values["Plenact.LocalProfile.v1"] as? Data else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }

                let previous =                                                  /* Previous value for comparison */
                    try JSONDecoder().decode(LocalProfile.self, from: oldBytes)

                guard previous.createdAt == profile.createdAt else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }

                previousRaw = try MigrationContentValues.object(previous)
                document = old
                payload = old["payload"] as! [String: Any]
            }
            else
            {
                document = context.document("user_profile", id: id, payload: [:])
                payload = ["account_id": MigrationTestPackage.accountID, "source_profile_id": id,
                    "source_created_at_utc": try context.utc(raw["createdAt"]!, path: id + "/profile-created")]
            }

            let profileFields =                                                         /* Profile fields */
                ["displayName": "display_name", "email": "email", "context": "context",
                "avatarIcon": "avatar_icon", "avatarColor": "avatar_color",
                "avatarForegroundColor": "avatar_foreground_color", "avatarPhotoFileName": "avatar_asset_id"]

            for (native, canonical) in profileFields
            {
                let before = previousRaw[native] ?? NSNull()    /* State before the operation */
                let after  = raw[native] ?? NSNull()            /* State after the operation  */

                if !profiles.isEmpty && NSDictionary(dictionary: ["value": before]).isEqual(to: ["value": after])
                {
                    continue
                }
                switch native
                {
                case "avatarColor", "avatarForegroundColor":

                    payload[canonical] = try context.appearance(raw[native], kind: "color")

                case "avatarPhotoFileName":

                    payload[canonical] = try context.asset(profile.avatarPhotoFileName, area: "Documents/ProfileAvatars")

                default:

                    payload[canonical] = after
                }
            }

            document["payload"] = payload
            profiles = [document]
            base["profiles"] = profiles
        }

        let keys    =                                                                                   /* Keys used by this operation */
            ["Plenact.Studio.Settings.v1", "Plenact.Studio.Artwork.v1", "Plenact.WeekAppearance.v1"]
        let changed = Set(try keys.filter { key in                                                      /* Value with requested edits  */
            guard let value = current[key] as? Data else
            {
                return false
            }
            guard let old = baseline.values[key] as? Data else
            {
                return true
            }
            return try !NSDictionary(dictionary: ["value": PortableEditedExport.nativeJSON(value)])
                .isEqual(to: ["value": PortableEditedExport.nativeJSON(old)])
        })

        guard !changed.isEmpty else
        {
            guard context.unavailable.isEmpty else
            {
                throw PortableEditedExport.Failure.unsupported
            }
            return
        }

        var journal      =                                                                      /* Migration identity journal */
            try JSONSerialization.jsonObject(with: context.journal.encoded()) as! [String: Any]
        var entries      = journal["entries"] as! [[String: Any]]                               /* Entries being processed    */
        let studioID     =                                                                      /* Studio ID                  */
            (base["studio_settings"] as? [String: Any])?["id"] as? String
        let appearanceID =                                                                      /* Appearance ID              */
            (export["workspace_appearance"] as? [String: Any])?["id"] as? String
        let libraryID    =                                                                      /* Library ID                 */
            (export["artwork_library"] as? [String: Any])?["id"] as? String

        for (kind, owner, legacy, retained) in [
            ("studio_settings", "workspace_metadata", keys[0], studioID),
            ("workspace_appearance", "workspace_metadata", keys[2], appearanceID),
            ("artwork_library", "workspace_metadata", keys[1], libraryID)]
        {
            let id =    /* Record or view identity */
                try retained ?? PortableRichCardExport.identity(namespace: baseline.workspaceID, name: kind)

            entries.append(["source": ["recordType": kind, "owner": owner, "legacyID": legacy], "target": id])
        }
        if let bytes = current[keys[1]] as? Data
        {
            for item in try JSONDecoder().decode([StudioArtwork].self, from: bytes)
            {
                let id = item.id.uuidString.lowercased()        /* Record or view identity */

                entries.append(["source": ["recordType": "studio_artwork", "owner": "artwork_library", "legacyID": id], "target": id])
            }
        }

        journal["formatVersion"] = 3
        journal["entries"] = entries

        var seeded  =                                                                                   /* Built-in initial content */
            try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
        let records =                                                                                   /* Records being processed  */
            (base["artwork"] as! [[String: Any]]) + ((base["planning"] as! [String: Any])["assets"] as! [[String: Any]])
        let values  = current.filter { keys.contains($0.key) }                                          /* Values being processed   */
        let result  =                                                                                   /* Result being assembled   */
            try MigrationStudioPreview.prepare(values: values, records: records,
                mediaDigests: context.mediaDigests, journal: &seeded, assetTargets: context.assetTargets)

        guard result.issueCount == 0,
              !result.records.contains(where: { $0["record_type"] as? String == "unavailable_reference" }),
              context.unavailable.isEmpty else
        {
            throw PortableEditedExport.Failure.unsupported
        }
        if changed.contains(keys[0]), let draft = result.document["studio_settings"] as? [String: Any],
           var payload = draft["payload"] as? [String: Any]
        {
            payload["account_id"] = MigrationTestPackage.accountID
            base["studio_settings"] = context.document("studio_settings", id: draft["id"] as! String, payload: payload)
        }
        if changed.contains(keys[1])
        {
            base["artwork"] = result.records.filter { $0["record_type"] as? String == "studio_artwork" }
            export["artwork_library"] = result.appearanceDocument["artwork_library"]
        }
        if changed.contains(keys[2])
        {
            export["workspace_appearance"] = result.appearanceDocument["workspace_appearance"]
        }
    }


    /// @fcn PortableStructuralEdits.apply
    /// @brief Reconcile List/Card creation and same-owner movement/order into the retained assembly
    /// @param[in] assembly Original canonical assembly
    /// @param[in] current Frozen native stores
    /// @param[in] aliases Durable reserved numeric aliases
    /// @param[in] baseline Reconstructed original native values and verified media
    /// @return Canonical assembly with structural edits, leaving existing Card content for field reconciliation
    /// @throws Unreserved/colliding identities, missing owners, List deletion or unsupported new content
    static func apply(assembly: [String: Any], current: [String: Any], aliases: [String: Int],
        baseline: PortableWorkspaceCandidate) throws -> [String: Any]
    {
        var assembly       = assembly                                   /* Assembled portable records       */
        var export         =                                            /* Prepared export evidence         */
            assembly["workspace_export"] as! [String: Any]
        var base           =                                            /* Base value before overrides      */
            export["base_workspace"] as! [String: Any]
        var planning       = base["planning"] as! [String: Any]         /* Planning store projection        */
        var content        = planning["content"] as! [String: Any]      /* Content being processed          */
        var collections    =                                            /* Retained personal collections    */
            content["collections"] as! [[String: Any]]
        var lists          = content["lists"] as! [[String: Any]]       /* Ordered List records             */
        var cards          =                                            /* Card records under consideration */
            content["cards"] as! [[String: Any]]
        let native         = try self.collections(current)              /* Native workspace representation  */
        let previousNative = try self.collections(baseline.values)      /* Previous native                  */

        guard Set(native.keys) == Set(collections.compactMap { $0["id"] as? String }) else
        {
            throw PortableEditedExport.Failure.structureChanged
        }

        let reverse                   =                                                 /* Inverse identity lookup    */
            Dictionary(uniqueKeysWithValues: aliases.map { ($0.value, $0.key) })
        let existingLists             =                                                 /* Existing lists             */
            Dictionary(uniqueKeysWithValues: lists.map { ($0["id"] as! String, $0) })
        let existingCards             =                                                 /* Existing cards             */
            Dictionary(uniqueKeysWithValues: cards.map { ($0["id"] as! String, $0) })
        var seenLists                 = Set<String>()                                   /* Seen lists                 */
        var seenCards                 = Set<String>()                                   /* Seen cards                 */
        var targets: [String: String] = [:]                                             /* Resolved operation targets */

        for record in cards
        {
            let id    = record["id"] as! String                                 /* Record or view identity   */
            let body  = record["payload"] as! [String: Any]                     /* Note or description text  */
            let list  = existingLists[body["list_id"] as! String]!              /* List under consideration  */
            let owner =                                                         /* Owning collection or Week */
                (list["payload"] as! [String: Any])["collection_id"] as! String

            if let number = aliases[id]
            {
                targets[owner + ":" + String(number)] = id
            }
        }
        for (owner, collection) in native
        {
            for list in collection.lists
            {
                guard let id = reverse[list.id], existingCards[id] == nil, seenLists.insert(id).inserted else
                {
                    throw PortableEditedExport.Failure.structureChanged
                }
                for card in list.allCards
                {
                    guard let id = reverse[card.id], existingLists[id] == nil, seenCards.insert(id).inserted else
                    {
                        throw PortableEditedExport.Failure.structureChanged
                    }

                    targets[owner + ":" + String(card.id)] = id
                }
            }
        }
        guard Set(existingLists.keys).isSubset(of: seenLists) else
        {
            throw PortableEditedExport.Failure.structureChanged
        }

        let deleted = try PortableLocalDeletions.ids(in: export)        /* Content after deletion */

        guard deleted.isDisjoint(with: seenCards) else
        {
            throw PortableEditedExport.Failure.inconsistent
        }
        for collectionIndex in collections.indices
        {
            let owner        =                                                  /* Owning collection or Week */
                collections[collectionIndex]["id"] as! String
            let snapshot     = native[owner]!                                   /* Working state snapshot    */
            var ownerPayload =                                                  /* Owner payload             */
                collections[collectionIndex]["payload"] as! [String: Any]

            guard let previousOwner = previousNative[owner], previousOwner.kind == snapshot.kind else
            {
                throw PortableEditedExport.Failure.structureChanged
            }

            let beforeOwner  = try MigrationContentValues.object(previousOwner)                 /* Before owner  */
            let afterOwner   = try MigrationContentValues.object(snapshot)                      /* After owner   */
            let ownerContext =                                                                  /* Owner context */
                try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                    owner: owner, target: owner, card: nil, base: base, media: baseline.media,
                    cardTargets: targets, values: current)
            let ownerFields =                                                                   /* Owner fields  */
                ["title": "title", "icon": "icon", "color": "color",
                "collectionDescription": "description", "isArchived": "archived", "boardAppearance": "board_appearance"]

            for (nativeKey, canonicalKey) in ownerFields
            {
                let old = beforeOwner[nativeKey] ?? NSNull()    /* Previous operation state    */
                let new = afterOwner[nativeKey] ?? NSNull()     /* Replacement operation state */

                if !NSDictionary(dictionary: ["value": old]).isEqual(to: ["value": new])
                {
                    switch nativeKey
                    {
                    case "color":

                        ownerPayload[canonicalKey] = try ownerContext.appearance(afterOwner[nativeKey], kind: "color")

                    case "boardAppearance":

                        ownerPayload[canonicalKey] = try ownerContext.appearance(afterOwner[nativeKey], kind: "board_appearance")

                    case "isArchived":

                        ownerPayload[canonicalKey] = snapshot.isArchived == true

                    default:

                        ownerPayload[canonicalKey] = new
                    }
                }
            }
            guard ownerContext.unavailable.isEmpty else
            {
                throw PortableEditedExport.Failure.unsupported
            }

            ownerPayload["list_ids"] = snapshot.lists.map { reverse[$0.id]! }
            collections[collectionIndex]["payload"] = ownerPayload

            for list in snapshot.lists
            {
                let id = reverse[list.id]!      /* Record or view identity  */
                var payload: [String: Any]      /* Canonical record payload */

                if let existing = existingLists[id]
                {
                    payload = existing["payload"] as! [String: Any]

                    guard payload["collection_id"] as? String == owner else
                    {
                        throw PortableEditedExport.Failure.structureChanged
                    }
                }
                else
                {
                    let raw     =                               /* Unprocessed source value */
                        try MigrationContentValues.object(list)
                    let context =                               /* Operation context        */
                        MigrationContentValues(journal: MigrationIdentityJournal(), timeZoneID: baseline.timeZoneID, mediaDigests: [:])

                    payload = ["collection_id": owner, "title": list.title,
                        "subtitle_override": raw["subtitleOverride"] ?? NSNull(), "archived": list.isArchived,
                        "default_item_presentation": raw["defaultItemPresentation"] ?? NSNull(),
                        "appearance": try context.appearance(raw["appearance"], kind: "item_appearance")]

                    guard context.unavailable.isEmpty else
                    {
                        throw PortableEditedExport.Failure.unsupported
                    }
                }
                if existingLists[id] != nil
                {
                    guard let original = previousNative[owner]?.lists.first(where: { $0.id == list.id }) else
                    {
                        throw PortableEditedExport.Failure.inconsistent
                    }

                    let before =                                                                        /* State before the operation */
                        try MigrationContentValues.object(original)
                    let after  =                                                                        /* State after the operation  */
                        try MigrationContentValues.object(list)
                    let fields =                                                                        /* Record fields under review */
                        ["title": "title", "subtitleOverride": "subtitle_override",
                        "isArchived": "archived", "defaultItemPresentation": "default_item_presentation",
                        "appearance": "appearance"]
                    let context =                                                                       /* Operation context          */
                        try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                            owner: owner, target: id, card: nil, base: base, media: baseline.media,
                            cardTargets: targets, values: current)

                    for (nativeKey, canonicalKey) in fields
                    {
                        let old = before[nativeKey] ?? NSNull()         /* Previous operation state    */
                        let new = after[nativeKey] ?? NSNull()          /* Replacement operation state */

                        if !NSDictionary(dictionary: ["value": old]).isEqual(to: ["value": new])
                        {
                            if nativeKey == "appearance"
                            {
                                payload[canonicalKey] = try context.appearance(after[nativeKey], kind: "item_appearance")
                            }
                            else
                            {
                                payload[canonicalKey] = new
                            }
                        }
                    }
                    guard context.unavailable.isEmpty else
                    {
                        throw PortableEditedExport.Failure.unsupported
                    }
                }

                payload["card_ids"] = list.cards.map { reverse[$0.id]! }
                payload["archived_card_ids"] = list.archivedCards.map { reverse[$0.id]! }

                // Preserve deleted last-import membership so 1.0 references remain valid under the 1.1 overlay
                if let old = existingLists[id]?["payload"] as? [String: Any]
                {
                    for key in ["card_ids", "archived_card_ids"]
                    {
                        payload[key] = (payload[key] as! [String]) + (old[key] as! [String]).filter { !seenCards.contains($0) }
                    }
                }

                let document: [String: Any] =                                           /* Source document snapshot */
                    ["user_data_model_version": "1.0", "payload_schema_version": 1,
                    "record_type": "list", "id": id, "workspace_id": baseline.workspaceID, "payload": payload]

                if let index = lists.firstIndex(where: { $0["id"] as? String == id })
                {
                    lists[index] = document
                }
                else
                {
                    lists.append(document)
                }
                for (archived, items) in [(false, list.cards), (true, list.archivedCards)]
                {
                    for card in items
                    {
                        let target = reverse[card.id]!          /* Target under consideration */

                        if let index = cards.firstIndex(where: { $0["id"] as? String == target })
                        {
                            var body         =                                  /* Note or description text */
                                cards[index]["payload"] as! [String: Any]
                            let previousList = body["list_id"] as! String       /* Previous list            */

                            guard (existingLists[previousList]?["payload"] as? [String: Any])?["collection_id"] as? String == owner else
                            {
                                throw PortableEditedExport.Failure.structureChanged
                            }
                            guard let original = previousNative[owner]?.lists.flatMap(\.allCards).first(where: { $0.id == card.id }) else
                            {
                                throw PortableEditedExport.Failure.inconsistent
                            }

                            let before  =                                       /* State before the operation */
                                try PortableEditedExport.nativeJSON(JSONEncoder().encode(original)) as! [String: Any]
                            let after   =                                       /* State after the operation  */
                                try PortableEditedExport.nativeJSON(JSONEncoder().encode(card)) as! [String: Any]
                            var changed =                                       /* Value with requested edits */
                                Set(before.keys).union(after.keys).filter {
                                !NSDictionary(dictionary: ["value": before[$0] ?? NSNull()]).isEqual(to: ["value": after[$0] ?? NSNull()])
                            }

                            changed.subtract(["id", "listTitle"])
                            guard !changed.contains("createdAt") else
                            {
                                throw PortableEditedExport.Failure.inconsistent
                            }
                            for prefix in ["start", "due"] where changed.contains(prefix + "Date") || changed.contains(prefix + "DateKind")
                            {
                                changed.formUnion([prefix + "Date", prefix + "DateKind"])
                            }
                            if !changed.isEmpty
                            {
                                let context =                                   /* Operation context               */
                                    try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                                        owner: owner, target: target, card: card, base: base, media: baseline.media,
                                        cardTargets: targets, values: current)
                                var source = card                               /* Source value for this operation */

                                source.editHistory = nil

                                let converted =         /* Converted portable value */
                                    try MigrationContentConverter.convertCard(source, archived: archived,
                                        list: id, owner: owner, context: context)

                                guard context.unavailable.isEmpty, let projected = converted["payload"] as? [String: Any] else
                                {
                                    throw PortableEditedExport.Failure.unsupported
                                }

                                let mapping = Self.cardFields           /* Source-to-target identity map */

                                for key in changed
                                {
                                    guard let field = mapping[key] else
                                    {
                                        throw PortableEditedExport.Failure.unsupported
                                    }

                                    body[field] = key == "editHistory" ? try PortableEditedExport.historyValue(card.editHistory) : projected[field]
                                }
                            }

                            body["list_id"] = id
                            body["archived"] = archived
                            cards[index]["payload"] = body
                        }
                        else
                        {
                            guard let created = card.createdAt,
                                  !existingCards.values.contains(where: { record in

                                      let value     =                   /* Value being processed   */
                                          (record["payload"] as? [String: Any])?["source_created_at_utc"] as? String
                                      let formatter =                   /* Date or value formatter */
                                          ISO8601DateFormatter()

                                      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                                      return value.flatMap(formatter.date(from:)).map { abs($0.timeIntervalSince(created)) < 0.001 } == true
                                  }) else
                            {
                                throw PortableEditedExport.Failure.structureChanged
                            }

                            let context =               /* Operation context               */
                                try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                                    owner: owner, target: target, card: card, base: base, media: baseline.media, cardTargets: targets, values: current)
                            var source = card           /* Source value for this operation */

                            source.editHistory = nil

                            var converted =     /* Converted portable value */
                                try MigrationContentConverter.convertCard(source, archived: archived, list: id, owner: owner, context: context)

                            guard context.unavailable.isEmpty else
                            {
                                throw PortableEditedExport.Failure.unsupported
                            }

                            converted["workspace_id"] = baseline.workspaceID

                            var body =                                  /* Note or description text */
                                converted["payload"] as! [String: Any]

                            body["edit_history"] = try PortableEditedExport.historyValue(card.editHistory)
                            converted["payload"] = body

                            cards.append(converted)
                        }
                    }
                }
            }
        }

        var selections            =                             /* Retained selection state          */
            base["content_selections"] as! [[String: Any]]
        var levels: [String: Int] = [:]                         /* Owner-qualified importance levels */

        if let bytes = current["Plenact.LibraryImportant.v1"] as? Data
        {
            for item in try JSONDecoder().decode([LibraryImportanceItem].self, from: bytes)
            {
                let key =                                                                       /* Lookup or persistence key */
                    item.collectionID.uuidString.lowercased() + ":" + String(item.cardID)

                guard levels[key] == nil, item.level == nil || (1...5).contains(item.level!) else
                {
                    throw PortableEditedExport.Failure.unsupported
                }

                levels[key] = item.resolvedLevel
            }
        }
        // Preserve retained selection order and append new owners in deterministic identity order
        for owner in native.keys.sorted()
        {
            let collection = native[owner]!                             /* Personal collection record */
            let actual     =                                            /* Observed operation result  */
                Set(collection.lists.flatMap(\.allCards).map(\.id))

            guard collection.savedCardIDs.isSubset(of: actual) else
            {
                throw PortableEditedExport.Failure.inconsistent
            }
            for number in actual.sorted()
            {
                let target     = reverse[number]!               /* Target under consideration       */
                let bookmarked =                                /* Saved Card selection state       */
                    collection.savedCardIDs.contains(number)
                let importance =                                /* Owner-qualified importance state */
                    levels[owner + ":" + String(number)] ?? 0
                let index      =                                /* Element position                 */
                    selections.firstIndex { ($0["payload"] as? [String: Any])?["card_id"] as? String == target }

                if index != nil || bookmarked || importance > 0
                {
                    let id =                                                            /* Record or view identity */
                        try index.map { selections[$0]["id"] as! String } ?? PortableRichCardExport.identity(
                            namespace: MigrationTestPackage.accountID, name: "content_selection:" + target)
                    let record: [String: Any] =                                         /* Record being processed  */
                        ["user_data_model_version": "1.0", "payload_schema_version": 1,
                        "record_type": "content_selection", "id": id, "workspace_id": baseline.workspaceID,
                        "payload": ["account_id": MigrationTestPackage.accountID, "card_id": target,
                            "bookmarked": bookmarked, "importance": importance]]

                    if let index
                    {
                        selections[index] = record
                    }
                    else
                    {
                        selections.append(record)
                    }
                }
            }
        }
        if let bytes = current["Plenact.PlanPreferences.v1"] as? Data,
           let oldBytes = baseline.values["Plenact.PlanPreferences.v1"] as? Data,
           try !NSDictionary(dictionary: MigrationContentValues.object(JSONDecoder().decode(LocalProfilePreferences.self, from: bytes)))
            .isEqual(to: MigrationContentValues.object(JSONDecoder().decode(LocalProfilePreferences.self, from: oldBytes)))
        {
            let preferences =                                                           /* Planning and display choices */
                try JSONDecoder().decode(LocalProfilePreferences.self, from: bytes)
            let raw         =                                                           /* Unprocessed source value     */
                try MigrationContentValues.object(preferences)

            guard var record = base["user_preferences"] as? [String: Any],
                  var payload = record["payload"] as? [String: Any],
                  var fields = payload["preferences"] as? [String: Any] else
            {
                throw PortableEditedExport.Failure.unsupported
            }
            for (source, destination) in MigrationSettingsPreview.fields
            {
                fields[destination] = raw[source] ?? NSNull()
            }

            fields["today_focus_order"] = preferences.todayFocusOrder == .dayList ? "day_list" : "chronological"

            if let number = preferences.defaultListID
            {
                guard let target = reverse[number], lists.contains(where: { $0["id"] as? String == target }) else
                {
                    throw PortableEditedExport.Failure.unsupported
                }

                fields["default_list_id"] = target
            }

            payload["preferences"] = fields
            record["payload"] = payload
            base["user_preferences"] = record
        }
        try personalization(base: &base, export: &export, current: current, baseline: baseline)

        base["content_selections"] = selections
        content["collections"] = collections
        content["lists"] = lists
        content["cards"] = cards
        planning["content"] = content

        if let currentBytes = current[PlanningCalendarStore.key] as? Data,
           let previousBytes = baseline.values[PlanningCalendarStore.key] as? Data
        {
            let calendar =                                                                      /* Date calculation calendar     */
                try JSONDecoder().decode(PlanningCalendarDocument.self, from: currentBytes)
            let previous =                                                                      /* Previous value for comparison */
                try JSONDecoder().decode(PlanningCalendarDocument.self, from: previousBytes)
            var weeks    = planning["weeks"] as! [[String: Any]]                                /* Retained dated Weeks          */

            for index in weeks.indices
            {
                var payload =                                           /* Canonical record payload  */
                    weeks[index]["payload"] as! [String: Any]
                let owner   = payload["collection_id"] as! String       /* Owning collection or Week */

                guard let old = previous.weeks.first(where: { $0.collection.id.uuidString.lowercased() == owner }),
                      let edited = calendar.weeks.first(where: { $0.collection.id.uuidString.lowercased() == owner }) else
                {
                    throw PortableEditedExport.Failure.structureChanged
                }
                if old.explicitlySaved != edited.explicitlySaved
                {
                    // Saving an existing generated Week records intent; removing that intent is unsupported
                    guard !old.explicitlySaved, edited.explicitlySaved, old.id == edited.id,
                          old.startKey == edited.startKey, payload["explicitly_saved"] as? Bool == false else
                    {
                        throw PortableEditedExport.Failure.unsupported
                    }

                    payload["explicitly_saved"] = true
                    weeks[index]["payload"] = payload
                }
            }

            planning["weeks"] = weeks
        }

        base["planning"] = planning
        export["base_workspace"] = base
        export["local_card_deletions"] = deleted.union(Set(existingCards.keys).subtracting(seenCards)).sorted()
        assembly["workspace_export"] = export

        return assembly
    }
}
