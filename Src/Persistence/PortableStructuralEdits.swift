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
    /// @param[in] card Frozen native Card
    /// @param[in] base Complete retained workspace
    /// @param[in] media Existing verified media placement
    /// @param[in] cardTargets Complete current owner-qualified Card identity map
    /// @param[in] values Frozen native stores including checklist week overrides
    /// @return Ephemeral conversion context; never saves a migration journal
    /// @throws Invalid source values or reference seeding
    private static func context(workspace: String, zone: String, owner: String, target: String,
        card: KanbanCard, base: [String: Any], media: PortableMediaPlacement,
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
        seedNested(try MigrationContentValues.object(card))
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
                // Existing List field changes remain subject to the complete inverse comparison.
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
