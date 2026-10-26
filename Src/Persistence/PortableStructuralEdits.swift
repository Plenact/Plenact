// --------------------------------------------------------------------------------------------------
// @file       PortableStructuralEdits.swift
// @brief      Reserved identities and owner-aware structural reconciliation for editable portable workspaces
// @details    Supported User Data Model versions: 1.0 retained records and working 1.1 local deletions.
//             New native identities are reserved before Board creation; no server identity is manufactured.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Reserves private aliases independently of whether a creation or subsequent Files export succeeds.
/// @section Purpose
///     Prevent number reuse and identity changes after cancellation, restart or repeated export.
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

        let evidence = try PortableRuntimeEvidence.capture(root: root)
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
        let maximum = aliases.values.max() ?? 0
        guard maximum < Int.max - count else
        {
            throw PortableEditedExport.Failure.unsupported
        }
        let start = max(proposed, maximum + 1)
        guard start > 0, start < Int.max - count else
        {
            throw PortableEditedExport.Failure.unsupported
        }
        for number in start..<(start + count)
        {
            aliases[UUID().uuidString.lowercased()] = number
        }
        object["numeric_ids"] = aliases
        let bytes = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let target = root.appendingPathComponent(PortableRuntimeEvidence.area + "/IdentityAliases.json")
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


/// Reconciles current native ownership/order against retained canonical records without matching titles.
/// @section Purpose
///     Keep existing identities and unknown authored canonical values while adding explicitly reserved records.
@MainActor
enum PortableStructuralEdits
{

    static let cardFields: [String: String] = [
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

        var result: [String: PersonalCollection] = [:]
        var owners: [PersonalCollection] = []
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
            let id = owner.id.uuidString.lowercased()
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

        var journal = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MigrationIdentityJournal())) as! [String: Any]
        journal["previewWorkspaceID"] = workspace
        var entries: [[String: Any]] = []

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

            var source: [String: Any] = ["recordType": kind, "owner": owner, "legacyID": legacy]
            source["discriminator"] = discriminator
            entries.append(["source": source, "target": id])
        }
        for label in base["labels"] as? [[String: Any]] ?? []
        {
            let id = label["id"] as! String
            seed("label", owner: "workspace_metadata", legacy: id, id: id)
        }
        let planning = base["planning"] as! [String: Any]
        for asset in planning["assets"] as? [[String: Any]] ?? []
        {
            let id = asset["id"] as! String
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
        var nestedSources = Set<String>()

        /// @fcn PortableStructuralEdits.seedNested
        /// @brief Preserve actual newly authored nested UUIDs in their supported identity families
        /// @param[in] value New Card subtree, excluding opaque encoded history values
        /// @return Void after seeding deterministic native nested identities
        func seedNested(_ value: Any)
        {

            if let object = value as? [String: Any]
            {
                var kind: String?
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
        let decoded = try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
        let context = MigrationContentValues(journal: decoded, timeZoneID: zone,
            mediaDigests: media.files.mapValues { MigrationBackupReader.digest($0) })
        context.known = Set((base["labels"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        context.known.formUnion((planning["assets"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        context.cardTargets = cardTargets
        context.known.formUnion(cardTargets.values)
        let content = planning["content"] as! [String: Any]
        let owners = (content["collections"] as! [[String: Any]]).map { $0["id"] as! String }
        context.originalCollectionIDs = Dictionary(uniqueKeysWithValues: owners.map { ($0, $0) })
        context.collectionTargets = context.originalCollectionIDs
        context.ownerScopesByCollection = Dictionary(uniqueKeysWithValues: owners.map { ($0, [$0]) })
        context.known.formUnion(owners)
        context.calendarOwnerScopes = Set((planning["weeks"] as! [[String: Any]]).compactMap {
            ($0["payload"] as? [String: Any])?["collection_id"] as? String
        })
        if let bytes = values["Plenact.CalendarWeeks.v1"] as? Data
        {
            let calendar = try JSONDecoder().decode(PlanningCalendarDocument.self, from: bytes)
            context.checklistWeekOverrides = Dictionary(uniqueKeysWithValues: (calendar.checklistLinkWeeks ?? [:]).map {
                ($0.key.uuidString.lowercased(), $0.value.uuidString.lowercased())
            })
        }
        return context
    }


    /// @fcn PortableStructuralEdits.rollovers
    /// @brief Convert newly retained dated Weeks with owner-qualified identities before structural comparison
    /// @details Operates on the frozen export candidate only; live stores and runtime evidence are unchanged.
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
        var calendar = try JSONDecoder().decode(PlanningCalendarDocument.self, from: bytes)
        let oldCalendar = try JSONDecoder().decode(PlanningCalendarDocument.self, from: oldBytes)
        let oldOwners = Set(oldCalendar.weeks.map { $0.collection.id })
        let incoming = calendar.weeks.filter { !oldOwners.contains($0.collection.id) }
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
            // A numeric default without explicit owner provenance is ambiguous across newly added Weeks.
            throw PortableEditedExport.Failure.unsupported
        }
        var assembly = assembly
        var export = assembly["workspace_export"] as! [String: Any]
        var base = export["base_workspace"] as! [String: Any]
        var planning = base["planning"] as! [String: Any]
        var content = planning["content"] as! [String: Any]
        guard let indexes = planning["calendar_indexes"] as? [[String: Any]], indexes.count == 1 else
        {
            throw PortableEditedExport.Failure.inconsistent
        }
        let oldIndex = indexes[0]
        var aliases = aliases
        var comparison = current
        var cardMaps: [String: [Int: Int]] = [:]
        for week in incoming
        {
            let owner = week.collection.id.uuidString.lowercased()
            let context = try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                owner: owner, target: owner, card: nil, base: base, media: baseline.media,
                cardTargets: [:], values: [:])
            var isolated = PlanningCalendarDocument(currentWeekKey: week.startKey,
                firstWeekday: calendar.firstWeekday, weeks: [week])
            isolated.checklistLinkWeeks = [:]
            let source: [String: Any] = ["Plenact.CalendarWeeks.v1": try JSONEncoder().encode(isolated),
                "Plenact.Board.v1": try JSONEncoder().encode(week.collection.lists)]
            let known = (base["labels"] as! [[String: Any]]) + (planning["assets"] as! [[String: Any]])
            let first = try MigrationContentConverter.convert(values: source, timeZoneID: baseline.timeZoneID,
                mediaDigests: context.mediaDigests, existing: known, journal: context.journal)
            var journal = try JSONSerialization.jsonObject(with: first.journal.encoded()) as! [String: Any]
            var entries = journal["entries"] as! [[String: Any]]
            let seeded = Set(context.journal.entries.map { $0.target.uuidString.lowercased() })
            for index in entries.indices
            {
                if seeded.contains((entries[index]["target"] as! String).lowercased())
                {
                    continue
                }
                let key = entries[index]["source"] as! [String: Any]
                if key["recordType"] as? String == "collection"
                {
                    entries[index]["target"] = owner
                }
                else
                {
                    let encoded = try JSONSerialization.data(withJSONObject: key, options: [.sortedKeys, .withoutEscapingSlashes])
                    entries[index]["target"] = try PortableRichCardExport.identity(namespace: baseline.workspaceID,
                        name: "rollover:" + String(decoding: encoded, as: UTF8.self))
                }
            }
            let targetChanges = Dictionary(uniqueKeysWithValues: zip(first.journal.entries, entries).map {
                ($0.0.target.uuidString.lowercased(), ($0.1["target"] as! String).lowercased())
            })
            for index in entries.indices
            {
                var key = entries[index]["source"] as! [String: Any]
                if (key["recordType"] as? String)?.hasPrefix("nested_") == true,
                   let owner = key["owner"] as? String, let target = targetChanges[owner.lowercased()]
                {
                    key["owner"] = target
                    entries[index]["source"] = key
                    let encoded = try JSONSerialization.data(withJSONObject: key, options: [.sortedKeys, .withoutEscapingSlashes])
                    entries[index]["target"] = try PortableRichCardExport.identity(namespace: baseline.workspaceID,
                        name: "rollover:" + String(decoding: encoded, as: UTF8.self))
                }
            }
            journal["entries"] = entries
            let stable = try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
            let converted = try MigrationContentConverter.convert(values: source, timeZoneID: baseline.timeZoneID,
                mediaDigests: context.mediaDigests, existing: known, journal: stable)
            guard !converted.records.contains(where: { $0["record_type"] as? String == "unavailable_reference" }) else
            {
                throw PortableEditedExport.Failure.unsupported
            }
            var listMap: [Int: Int] = [:]
            var cardMap: [Int: Int] = [:]
            for entry in stable.entries where ["list", "card"].contains(entry.source.recordType)
            {
                guard let number = Int(entry.source.legacyID), entry.source.owner == owner else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }
                let id = entry.target.uuidString.lowercased()
                let maximum = aliases.values.max() ?? 0
                guard maximum < Int.max - 1 else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }
                let next = maximum + 1
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
            // Only editor aliases are normalized; all authored native values remain in the comparison.
            var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(week)) as! [String: Any]
            var collection = raw["collection"] as! [String: Any]
            var lists = collection["lists"] as! [[String: Any]]
            for index in lists.indices
            {
                lists[index]["id"] = listMap[lists[index]["id"] as! Int]!
                for field in ["cards", "archivedCards"]
                {
                    var cards = lists[index][field] as? [[String: Any]] ?? []
                    for card in cards.indices
                    {
                        cards[card]["id"] = cardMap[cards[card]["id"] as! Int]!
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
            let normalized = try JSONDecoder().decode(DatedPlanningWeek.self, from: JSONSerialization.data(withJSONObject: raw))
            calendar.weeks[calendar.weeks.firstIndex(where: { $0.collection.id == week.collection.id })!] = normalized
            for (field, kind) in [("collections", "collection"), ("lists", "list"), ("cards", "card")]
            {
                content[field] = (content[field] as! [[String: Any]]) + converted.records.filter { $0["record_type"] as? String == kind }
            }
            planning["weeks"] = (planning["weeks"] as! [[String: Any]]) + converted.records.filter { $0["record_type"] as? String == "calendar_week" }
        }
        var index = oldIndex
        var payload = index["payload"] as! [String: Any]
        let weeks = planning["weeks"] as! [[String: Any]]
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
        let rawCalendar = try JSONDecoder().decode(PlanningCalendarDocument.self, from: bytes)
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
            var items = try JSONSerialization.jsonObject(with: bytes) as! [[String: Any]]
            for i in items.indices
            {
                let owner = (items[i]["collectionID"] as! String).lowercased()
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

        let context = try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
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
            let profile = try JSONDecoder().decode(LocalProfile.self, from: bytes)
            let raw = try MigrationContentValues.object(profile)
            let source = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            guard Set(source.keys).isSubset(of: ["id", "createdAt", "displayName", "email", "context",
                "avatarColor", "avatarIcon", "avatarForegroundColor", "avatarPhotoFileName", "preferences"]) else
            {
                throw PortableEditedExport.Failure.unsupported
            }
            var profiles = base["profiles"] as! [[String: Any]]
            guard profiles.count <= 1 else
            {
                throw PortableEditedExport.Failure.unsupported
            }
            let id = profile.id.uuidString.lowercased()
            var document: [String: Any]
            var payload: [String: Any]
            var previousRaw: [String: Any] = [:]
            if let old = profiles.first
            {
                guard old["id"] as? String == id,
                      let oldBytes = baseline.values["Plenact.LocalProfile.v1"] as? Data else
                {
                    throw PortableEditedExport.Failure.inconsistent
                }
                let previous = try JSONDecoder().decode(LocalProfile.self, from: oldBytes)
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
            let profileFields = ["displayName": "display_name", "email": "email", "context": "context",
                "avatarIcon": "avatar_icon", "avatarColor": "avatar_color",
                "avatarForegroundColor": "avatar_foreground_color", "avatarPhotoFileName": "avatar_asset_id"]
            for (native, canonical) in profileFields
            {
                let before = previousRaw[native] ?? NSNull()
                let after = raw[native] ?? NSNull()
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
        let keys = ["Plenact.Studio.Settings.v1", "Plenact.Studio.Artwork.v1", "Plenact.WeekAppearance.v1"]
        let changed = Set(try keys.filter { key in
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
        var journal = try JSONSerialization.jsonObject(with: context.journal.encoded()) as! [String: Any]
        var entries = journal["entries"] as! [[String: Any]]
        let studioID = (base["studio_settings"] as? [String: Any])?["id"] as? String
        let appearanceID = (export["workspace_appearance"] as? [String: Any])?["id"] as? String
        let libraryID = (export["artwork_library"] as? [String: Any])?["id"] as? String
        for (kind, owner, legacy, retained) in [
            ("studio_settings", "workspace_metadata", keys[0], studioID),
            ("workspace_appearance", "workspace_metadata", keys[2], appearanceID),
            ("artwork_library", "workspace_metadata", keys[1], libraryID)]
        {
            let id = try retained ?? PortableRichCardExport.identity(namespace: baseline.workspaceID, name: kind)
            entries.append(["source": ["recordType": kind, "owner": owner, "legacyID": legacy], "target": id])
        }
        if let bytes = current[keys[1]] as? Data
        {
            for item in try JSONDecoder().decode([StudioArtwork].self, from: bytes)
            {
                let id = item.id.uuidString.lowercased()
                entries.append(["source": ["recordType": "studio_artwork", "owner": "artwork_library", "legacyID": id], "target": id])
            }
        }
        journal["formatVersion"] = 3
        journal["entries"] = entries
        var seeded = try MigrationIdentityJournal.decode(JSONSerialization.data(withJSONObject: journal))
        let records = (base["artwork"] as! [[String: Any]]) + ((base["planning"] as! [String: Any])["assets"] as! [[String: Any]])
        let values = current.filter { keys.contains($0.key) }
        let result = try MigrationStudioPreview.prepare(values: values, records: records,
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

        var assembly = assembly
        var export = assembly["workspace_export"] as! [String: Any]
        var base = export["base_workspace"] as! [String: Any]
        var planning = base["planning"] as! [String: Any]
        var content = planning["content"] as! [String: Any]
        var collections = content["collections"] as! [[String: Any]]
        var lists = content["lists"] as! [[String: Any]]
        var cards = content["cards"] as! [[String: Any]]
        let native = try self.collections(current)
        let previousNative = try self.collections(baseline.values)
        guard Set(native.keys) == Set(collections.compactMap { $0["id"] as? String }) else
        {
            throw PortableEditedExport.Failure.structureChanged
        }
        let reverse = Dictionary(uniqueKeysWithValues: aliases.map { ($0.value, $0.key) })
        let existingLists = Dictionary(uniqueKeysWithValues: lists.map { ($0["id"] as! String, $0) })
        let existingCards = Dictionary(uniqueKeysWithValues: cards.map { ($0["id"] as! String, $0) })
        var seenLists = Set<String>()
        var seenCards = Set<String>()
        var targets: [String: String] = [:]
        for record in cards
        {
            let id = record["id"] as! String
            let body = record["payload"] as! [String: Any]
            let list = existingLists[body["list_id"] as! String]!
            let owner = (list["payload"] as! [String: Any])["collection_id"] as! String
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
        let deleted = try PortableLocalDeletions.ids(in: export)
        guard deleted.isDisjoint(with: seenCards) else
        {
            throw PortableEditedExport.Failure.inconsistent
        }
        for collectionIndex in collections.indices
        {
            let owner = collections[collectionIndex]["id"] as! String
            let snapshot = native[owner]!
            var ownerPayload = collections[collectionIndex]["payload"] as! [String: Any]
            guard let previousOwner = previousNative[owner], previousOwner.kind == snapshot.kind else
            {
                throw PortableEditedExport.Failure.structureChanged
            }
            let beforeOwner = try MigrationContentValues.object(previousOwner)
            let afterOwner = try MigrationContentValues.object(snapshot)
            let ownerContext = try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                owner: owner, target: owner, card: nil, base: base, media: baseline.media,
                cardTargets: targets, values: current)
            let ownerFields = ["title": "title", "icon": "icon", "color": "color",
                "collectionDescription": "description", "isArchived": "archived", "boardAppearance": "board_appearance"]
            for (nativeKey, canonicalKey) in ownerFields
            {
                let old = beforeOwner[nativeKey] ?? NSNull()
                let new = afterOwner[nativeKey] ?? NSNull()
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
                let id = reverse[list.id]!
                var payload: [String: Any]
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
                    let raw = try MigrationContentValues.object(list)
                    let context = MigrationContentValues(journal: MigrationIdentityJournal(), timeZoneID: baseline.timeZoneID, mediaDigests: [:])
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
                    let before = try MigrationContentValues.object(original)
                    let after = try MigrationContentValues.object(list)
                    let fields = ["title": "title", "subtitleOverride": "subtitle_override",
                        "isArchived": "archived", "defaultItemPresentation": "default_item_presentation",
                        "appearance": "appearance"]
                    let context = try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                        owner: owner, target: id, card: nil, base: base, media: baseline.media,
                        cardTargets: targets, values: current)
                    for (nativeKey, canonicalKey) in fields
                    {
                        let old = before[nativeKey] ?? NSNull()
                        let new = after[nativeKey] ?? NSNull()
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
                // Preserve deleted last-import membership so 1.0 references remain valid under the 1.1 overlay.
                if let old = existingLists[id]?["payload"] as? [String: Any]
                {
                    for key in ["card_ids", "archived_card_ids"]
                    {
                        payload[key] = (payload[key] as! [String]) + (old[key] as! [String]).filter { !seenCards.contains($0) }
                    }
                }
                let document: [String: Any] = ["user_data_model_version": "1.0", "payload_schema_version": 1,
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
                        let target = reverse[card.id]!
                        if let index = cards.firstIndex(where: { $0["id"] as? String == target })
                        {
                            var body = cards[index]["payload"] as! [String: Any]
                            let previousList = body["list_id"] as! String
                            guard (existingLists[previousList]?["payload"] as? [String: Any])?["collection_id"] as? String == owner else
                            {
                                throw PortableEditedExport.Failure.structureChanged
                            }
                            guard let original = previousNative[owner]?.lists.flatMap(\.allCards).first(where: { $0.id == card.id }) else
                            {
                                throw PortableEditedExport.Failure.inconsistent
                            }
                            let before = try PortableEditedExport.nativeJSON(JSONEncoder().encode(original)) as! [String: Any]
                            let after = try PortableEditedExport.nativeJSON(JSONEncoder().encode(card)) as! [String: Any]
                            var changed = Set(before.keys).union(after.keys).filter {
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
                                let context = try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                                    owner: owner, target: target, card: card, base: base, media: baseline.media,
                                    cardTargets: targets, values: current)
                                var source = card
                                source.editHistory = nil
                                let converted = try MigrationContentConverter.convertCard(source, archived: archived,
                                    list: id, owner: owner, context: context)
                                guard context.unavailable.isEmpty, let projected = converted["payload"] as? [String: Any] else
                                {
                                    throw PortableEditedExport.Failure.unsupported
                                }
                                let mapping = Self.cardFields
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
                                      let value = (record["payload"] as? [String: Any])?["source_created_at_utc"] as? String
                                      let formatter = ISO8601DateFormatter()
                                      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                      return value.flatMap(formatter.date(from:)).map { abs($0.timeIntervalSince(created)) < 0.001 } == true
                                  }) else
                            {
                                throw PortableEditedExport.Failure.structureChanged
                            }
                            let context = try self.context(workspace: baseline.workspaceID, zone: baseline.timeZoneID,
                                owner: owner, target: target, card: card, base: base, media: baseline.media, cardTargets: targets, values: current)
                            var source = card
                            source.editHistory = nil
                            var converted = try MigrationContentConverter.convertCard(source, archived: archived, list: id, owner: owner, context: context)
                            guard context.unavailable.isEmpty else
                            {
                                throw PortableEditedExport.Failure.unsupported
                            }
                            converted["workspace_id"] = baseline.workspaceID
                            var body = converted["payload"] as! [String: Any]
                            body["edit_history"] = try PortableEditedExport.historyValue(card.editHistory)
                            converted["payload"] = body
                            cards.append(converted)
                        }
                    }
                }
            }
        }
        var selections = base["content_selections"] as! [[String: Any]]
        var levels: [String: Int] = [:]
        if let bytes = current["Plenact.LibraryImportant.v1"] as? Data
        {
            for item in try JSONDecoder().decode([LibraryImportanceItem].self, from: bytes)
            {
                let key = item.collectionID.uuidString.lowercased() + ":" + String(item.cardID)
                guard levels[key] == nil, item.level == nil || (1...5).contains(item.level!) else
                {
                    throw PortableEditedExport.Failure.unsupported
                }
                levels[key] = item.resolvedLevel
            }
        }
        for (owner, collection) in native
        {
            let actual = Set(collection.lists.flatMap(\.allCards).map(\.id))
            guard collection.savedCardIDs.isSubset(of: actual) else
            {
                throw PortableEditedExport.Failure.inconsistent
            }
            for number in actual.sorted()
            {
                let target = reverse[number]!
                let bookmarked = collection.savedCardIDs.contains(number)
                let importance = levels[owner + ":" + String(number)] ?? 0
                let index = selections.firstIndex { ($0["payload"] as? [String: Any])?["card_id"] as? String == target }
                if index != nil || bookmarked || importance > 0
                {
                    let id = try index.map { selections[$0]["id"] as! String } ?? PortableRichCardExport.identity(
                        namespace: MigrationTestPackage.accountID, name: "content_selection:" + target)
                    let record: [String: Any] = ["user_data_model_version": "1.0", "payload_schema_version": 1,
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
            let preferences = try JSONDecoder().decode(LocalProfilePreferences.self, from: bytes)
            let raw = try MigrationContentValues.object(preferences)
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
        base["planning"] = planning
        export["base_workspace"] = base
        export["local_card_deletions"] = deleted.union(Set(existingCards.keys).subtracting(seenCards)).sorted()
        assembly["workspace_export"] = export
        return assembly
    }
}
