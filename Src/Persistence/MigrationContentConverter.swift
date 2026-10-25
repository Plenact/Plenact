// --------------------------------------------------------------------------------------------------
// @file       MigrationContentConverter.swift
// @brief      Owner-aware Board/List/Card conversion with projection reconciliation
// @details    Supported User Data Model versions: 1.0. Partial, local-only migration preview.
//             Original source bytes remain preserved; no cloud ownership or synchronization is implied.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Converts complete owned content while retaining unresolved dependencies separately.
/// @section Purpose
///     Produce inspectable canonical content without claiming the remaining workspace adapters exist.
@MainActor
enum MigrationContentConverter
{

    /// Original owner context, distinct from a translated title or current List position.
    /// @section Purpose
    ///     Keep copied template content and retained live Weeks independent.
    private struct Owner
    {

        let collection: PersonalCollection
        let origin:     String
        let timeZoneID: String
        let namespace: String
    }


    /// Complete result of this atomic conversion slice.
    /// @section Purpose
    ///     Report records, unresolved references and source precision independently.
    struct Result
    {

        let records:  [[String: Any]]
        let evidence: [[String: Any]]
        let summary:  [[String: Any]]
        let journal:  MigrationIdentityJournal
        let graph:    [String: Any]
        let boardConverted: Bool
        let selections: MigrationSelectionPreview.Result
        let metadataRecordCount: Int
    }


    /// @fcn MigrationContentConverter.source
    /// @brief Guard actual stored fields, then use compatible native decoders directly
    /// @param[in] value Present source bytes
    /// @param[in] type Native source type
    /// @param[in] shape Audited source object family
    /// @param[in] array Whether the source is an array of that family
    /// @return Decoded source without invoking loaders or examples
    /// @throws Unsupported source fields, versions or decoding errors
    private static func source<T: Decodable>(_ value: Any, as type: T.Type, shape: String, array: Bool = false) throws -> T
    {

        guard let data = value as? Data else
        {
            throw MigrationContentValues.Failure.invalid("source_storage_type")
        }
        let raw = try JSONSerialization.jsonObject(with: data)
        if array
        {
            guard let entries = raw as? [Any] else
            {
                throw MigrationContentValues.Failure.invalid("source_array")
            }
            for entry in entries
            {
                try MigrationContentGuard.check(entry, type: shape)
            }
        }
        else
        {
            try MigrationContentGuard.check(raw, type: shape)
            if let version = (raw as? [String: Any])?["version"] as? Int, version != 1
            {
                throw MigrationContentValues.Failure.invalid("source_store_version")
            }
        }
        return try JSONDecoder().decode(type, from: data)
    }


    /// @fcn MigrationContentConverter.convert
    /// @brief Reconcile source ownership before allocating records, then convert all fields explicitly
    /// @param[in] values Verified frozen preference values
    /// @param[in] timeZoneID Explicit original timezone confirmation
    /// @param[in] mediaDigests Verified original media identities
    /// @param[in] existing Already converted metadata IDs
    /// @param[in] journal Uncommitted journal candidate
    /// @return Complete content slice and evidence
    /// @throws Ambiguous projections, source fields, IDs, links or dates
    static func convert(values: [String: Any], timeZoneID: String, mediaDigests: [String: String],
        existing: [[String: Any]], journal: MigrationIdentityJournal) throws -> Result
    {

        let context = MigrationContentValues(journal: journal, timeZoneID: timeZoneID, mediaDigests: mediaDigests)
        context.known = Set(existing.compactMap { $0["id"] as? String })
        var owners: [Owner] = []
        var boardConverted = false
        var currentScope: String?
        if let raw = values["Plenact.CalendarWeeks.v1"]
        {
            let document = try source(raw, as: PlanningCalendarDocument.self, shape: "PlanningCalendarDocument")
            guard document.version == 1, (1...7).contains(document.firstWeekday),
                  Set(document.weeks.map(\.startKey)).count == document.weeks.count,
                  Set(document.weeks.map(\.id)).count == document.weeks.count else
            {
                throw MigrationContentValues.Failure.invalid("calendar_identity")
            }
            let current = document.weeks.filter { $0.startKey == document.currentWeekKey }
            guard current.count == 1 else
            {
                throw MigrationContentValues.Failure.projectionConflict
            }
            currentScope = current[0].collection.id.uuidString.lowercased()
            if let rawBoard = values["Plenact.Board.v1"]
            {
                let board = try source(rawBoard, as: [KanbanList].self, shape: "KanbanList", array: true)
                guard current[0].collection.lists == board else
                {
                    throw MigrationContentValues.Failure.projectionConflict
                }
                let originalCalendar = try JSONSerialization.jsonObject(with: raw as! Data) as! [String: Any]
                let originalWeek = (originalCalendar["weeks"] as! [[String: Any]]).first { $0["startKey"] as? String == document.currentWeekKey }!
                let originalLists = (originalWeek["collection"] as! [String: Any])["lists"]!
                let originalBoard = try JSONSerialization.jsonObject(with: rawBoard as! Data)
                let left = try JSONSerialization.data(withJSONObject: MigrationContentGuard.comparable(originalLists), options: .sortedKeys)
                let right = try JSONSerialization.data(withJSONObject: MigrationContentGuard.comparable(originalBoard), options: .sortedKeys)
                guard left == right else
                {
                    throw MigrationContentValues.Failure.projectionConflict
                }
                boardConverted = true
            }
            context.calendarOwnerScopes = Set(document.weeks.map { $0.collection.id.uuidString.lowercased() })
            context.checklistWeekOverrides = Dictionary(uniqueKeysWithValues: (document.checklistLinkWeeks ?? [:]).map {
                ($0.key.uuidString.lowercased(), $0.value.uuidString.lowercased())
            })
            owners += document.weeks.map { Owner(collection: $0.collection, origin: "calendar_week", timeZoneID: timeZoneID, namespace: $0.collection.id.uuidString.lowercased()) }
        }
        else if values["Plenact.Board.v1"] != nil
        {
            throw MigrationContentValues.Failure.invalid("standalone_board_owner_context_required")
        }
        if let raw = values["Plenact.PersonalCollections.v1"]
        {
            let collections = try source(raw, as: [PersonalCollection].self, shape: "PersonalCollection", array: true)
            owners += collections.map { Owner(collection: $0, origin: "personal_collection", timeZoneID: timeZoneID, namespace: $0.id.uuidString.lowercased()) }
        }
        if let raw = values["Plenact.PlanningTemplates.v1"]
        {
            let library = try source(raw, as: PlanningRoutineLibrary.self, shape: "PlanningRoutineLibrary")
            owners += library.templates.map { Owner(collection: $0.collection, origin: "planning_template", timeZoneID: $0.timeZoneID,
                namespace: "template:" + $0.id.uuidString.lowercased() + ":" + $0.collection.id.uuidString.lowercased()) }
        }
        // Original optional values remain available even when compatible native constructors normalize them.
        /// Retain original optional values using immutable source owner/Card keys.
        /// @fcn MigrationContentConverter.remember
        /// @param[in] collection Original stored Collection object
        /// @return Void; records raw evidence without writing source data
        func remember(_ collection: [String: Any], namespace: String? = nil)
        {
            guard let owner = collection["id"] as? String else
            {
                return
            }
            for list in collection["lists"] as? [[String: Any]] ?? []
            {
                for card in (list["cards"] as? [[String: Any]] ?? []) + (list["archivedCards"] as? [[String: Any]] ?? [])
                {
                    if let id = card["id"] as? Int
                    {
                        context.originalCards[(namespace ?? owner.lowercased()) + ":" + String(id)] = card
                    }
                }
            }
        }
        for key in ["Plenact.CalendarWeeks.v1", "Plenact.PersonalCollections.v1", "Plenact.PlanningTemplates.v1"]
        {
            guard let bytes = values[key] as? Data else
            {
                continue
            }
            let raw = try JSONSerialization.jsonObject(with: bytes)
            if let array = raw as? [[String: Any]]
            {
                for collection in array
                {
                    remember(collection)
                }
            }
            else if let object = raw as? [String: Any]
            {
                for entry in (object["weeks"] ?? object["templates"]) as? [[String: Any]] ?? []
                {
                    if let collection = entry["collection"] as? [String: Any]
                    {
                        let namespace: String?
                        if key == "Plenact.PlanningTemplates.v1", let template = entry["id"] as? String, let source = collection["id"] as? String
                        {
                            namespace = "template:" + template.lowercased() + ":" + source.lowercased()
                        }
                        else
                        {
                            namespace = nil
                        }
                        remember(collection, namespace: namespace)
                    }
                }
            }
        }
        guard Set(owners.map(\.namespace)).count == owners.count else
        {
            throw MigrationContentValues.Failure.invalid("duplicate_owner_identity")
        }
        for owner in owners
        {
            let origin = owner.namespace
            let target = try context.id("collection", owner: "source_collections", legacy: origin)
            context.collectionTargets[origin] = target
            let sourceCollection = owner.collection.id.uuidString.lowercased()
            context.originalCollectionIDs[origin] = sourceCollection
            context.ownerScopesByCollection[sourceCollection, default: []].append(origin)
            context.known.insert(target)
            guard Set(owner.collection.lists.map(\.id)).count == owner.collection.lists.count else
            {
                throw MigrationContentValues.Failure.invalid("duplicate_list_identity")
            }
            var cardIDs: Set<Int> = []
            for list in owner.collection.lists
            {
                context.known.insert(try context.id("list", owner: origin, legacy: String(list.id)))
                for card in list.cards + list.archivedCards
                {
                    guard cardIDs.insert(card.id).inserted else
                    {
                        throw MigrationContentValues.Failure.invalid("duplicate_card_identity")
                    }
                    let target = try context.id("card", owner: origin, legacy: String(card.id),
                        discriminator: card.createdAt.map { String($0.timeIntervalSinceReferenceDate) })
                    context.cardTargets[origin + ":" + String(card.id)] = target
                    context.known.insert(target)
                }
            }
        }
        var records: [[String: Any]] = []
        var summary: [[String: Any]] = []
        for owner in owners
        {
            context.timeZoneID = owner.timeZoneID
            let origin = owner.namespace
            let collectionID = context.collectionTargets[origin]!
            let raw = try MigrationContentValues.object(owner.collection)
            var listIDs: [String] = []
            for list in owner.collection.lists
            {
                let listID = try context.id("list", owner: origin, legacy: String(list.id))
                listIDs.append(listID)
                let rawList = try MigrationContentValues.object(list)
                for card in list.cards
                {
                    records.append(try convertCard(card, archived: false, list: listID, owner: origin, context: context))
                }
                for card in list.archivedCards
                {
                    records.append(try convertCard(card, archived: true, list: listID, owner: origin, context: context))
                }
                records.append(context.document("list", id: listID, payload: ["collection_id": collectionID,
                    "title": list.title, "subtitle_override": rawList["subtitleOverride"] ?? NSNull(), "archived": list.isArchived,
                    "default_item_presentation": rawList["defaultItemPresentation"] ?? NSNull(),
                    "appearance": try context.appearance(rawList["appearance"], kind: "item_appearance"),
                    "card_ids": list.cards.map { context.cardTargets[origin + ":" + String($0.id)]! },
                    "archived_card_ids": list.archivedCards.map { context.cardTargets[origin + ":" + String($0.id)]! }]))
            }
            records.append(context.document("collection", id: collectionID, payload: [
                "title": owner.collection.title, "kind": owner.collection.kind == .list ? "list" : "board",
                "icon": owner.collection.icon.rawValue, "color": try context.appearance(raw["color"], kind: "color"),
                "description": raw["collectionDescription"] ?? NSNull(), "archived": owner.collection.isArchived == true,
                "board_appearance": try context.appearance(raw["boardAppearance"], kind: "board_appearance"),
                "preferred_focused_list_id": NSNull(), "list_ids": listIDs]))
            summary.append(["source_collection_id": owner.collection.id.uuidString.lowercased(), "source_owner_scope": origin, "collection_id": collectionID, "origin": owner.origin,
                "list_count": owner.collection.lists.count, "active_card_count": owner.collection.lists.reduce(0) { $0 + $1.cards.count },
                "archived_card_count": owner.collection.lists.reduce(0) { $0 + $1.archivedCards.count },
                "time_zone": owner.timeZoneID, "pending_collection_bookmark_count": owner.collection.savedCardIDs.count])
        }
        let metadata = try MigrationCalendarTemplates.convert(values: values, context: context, originalTimeZoneID: timeZoneID)
        records.append(contentsOf: metadata)
        let selections = MigrationSelectionPreview.prepare(values: values,
            owners: owners.map { ($0.namespace, $0.collection) }, currentScope: currentScope, targets: context.cardTargets)
        let unavailable = context.unavailable.keys.sorted().map { context.unavailable[$0]! }
        let graph: [String: Any] = ["user_data_model_version": "1.0", "payload_schema_version": 1,
            "workspace_id": context.journal.previewWorkspaceID.uuidString.lowercased(),
            "collections": records.filter { $0["record_type"] as? String == "collection" },
            "lists": records.filter { $0["record_type"] as? String == "list" },
            "cards": records.filter { $0["record_type"] as? String == "card" },
            "external_references": existing.filter { ["label", "label_category"].contains($0["record_type"] as? String ?? "") }.map {
                ["record_type": $0["record_type"]!, "id": $0["id"]!, "status": "external"]
            } + unavailable.map { record -> [String: Any] in
                let payload = record["payload"] as! [String: Any]
                return ["record_type": payload["target_type"]!, "id": payload["target_id"]!, "status": "unavailable"]
            }]
        return Result(records: records + unavailable, evidence: context.precisionEvidence, summary: summary,
            journal: context.journal, graph: graph, boardConverted: boardConverted, selections: selections, metadataRecordCount: metadata.count)
    }


    /// @fcn MigrationContentConverter.convertCard
    /// @brief Explicitly map every stored Card field, retaining hidden content and history
    /// @param[in] card Native source Card/Note/divider
    /// @param[in] archived Original active/archive membership
    /// @param[in] list Canonical parent List
    /// @param[in] owner Original Collection scope
    /// @param[in] context Candidate identity/evidence context
    /// @return Complete canonical Card record
    /// @throws Nested identity, source URL, appearance or date errors
    static func convertCard(_ card: KanbanCard, archived: Bool, list: String, owner: String,
        context: MigrationContentValues) throws -> [String: Any]
    {

        var raw = try MigrationContentValues.object(card)
        if let source = context.originalCards[owner + ":" + String(card.id)]
        {
            if let empty = source["reactions"] as? [Any], empty.isEmpty
            {
                raw["reactions"] = [Any]()
            }
            if let appearance = source["appearance"] as? [String: Any], appearance.isEmpty
            {
                raw["appearance"] = appearance
            }
            if let kind = source["itemPresentation"] as? String
            {
                raw["itemPresentation"] = kind
            }
        }
        let target = context.cardTargets[owner + ":" + String(card.id)]!
        let attachments = try context.attachments(raw["attachments"] as? [[String: Any]], scope: target)
        var cover: Any = NSNull()
        if let original = card.coverAttachmentID
        {
            guard let mapped = context.attachmentTargets[target + ":" + original.uuidString.lowercased()] else
            {
                throw MigrationContentValues.Failure.invalid("missing_cover_attachment")
            }
            cover = mapped
        }
        let members = try (raw["members"] as! [[String: Any]]).map { member -> [String: Any] in
            let registered = member["kind"] as? String == "registeredUser"
            return ["id": try context.nested("assignee", member["id"], scope: target),
                "kind": registered ? "registered_user" : "manual", "display_name": member["displayName"]!,
                "user_id": try registered ? MigrationContentValues.lowerUUID(member["userID"]) as Any : NSNull(),
                "identity_scope": registered ? "legacy_demo" : "manual"]
        }
        let reactions: Any = try (raw["reactions"] as? [[String: Any]]).map { values in
            try values.map { value -> [String: Any] in
                ["id": try context.nested("reaction", value["id"], scope: target), "emoji": value["emoji"]!,
                    "source_author_id": try MigrationContentValues.lowerUUID(value["authorID"]),
                    "source_created_at_utc": try context.utc(value["createdAt"]!, path: target + "/reaction"), "author_account_id": NSNull()]
            }
        } as Any? ?? NSNull()
        let labels = try card.labelIDs.map { source -> String in
            let id = try context.id("label", owner: "workspace_metadata", legacy: source)
            return try context.reference("label", id)
        }
        guard Set(labels).count == labels.count else
        {
            throw MigrationContentValues.Failure.invalid("duplicate_label_reference")
        }
        let layout: Any = (raw["sectionLayout"] as? [String: Any]).map { source in
            ["order": (source["order"] as! [String]).map { $0 == "quickActions" ? "quick_actions" : $0 },
                "hidden": (source["hidden"] as! [String]).map { $0 == "quickActions" ? "quick_actions" : $0 }.sorted()]
        } as Any? ?? NSNull()
        let startKind = card.startDateKind == .dateAndTime ? "date_and_time" : card.startDateKind.rawValue
        let dueKind = card.dueDateKind == .dateAndTime ? "date_and_time" : card.dueDateKind.rawValue
        let payload: [String: Any] = ["list_id": list, "archived": archived, "title": card.word,
            "is_divider": card.isDivider, "completed": card.isTitleChecked, "editing_locked": card.isEditingLocked,
            "presentation": raw["itemPresentation"] ?? card.presentation.rawValue, "display_format": raw["listDisplayFormat"] ?? NSNull(),
            "description_override": raw["descriptionOverride"] ?? NSNull(), "subtitle_override": raw["subtitleOverride"] ?? NSNull(),
            "location": raw["location"] ?? NSNull(), "start_kind": startKind, "due_kind": dueKind,
            "start": try MigrationContentDates.convert(raw["startDate"], kind: startKind, context: context, path: target + "/start"),
            "due": try MigrationContentDates.convert(raw["dueDate"], kind: dueKind, context: context, path: target + "/due"),
            "shows_due_date_in_list": card.showsDueDateInList,
            "source_created_at_utc": try raw["createdAt"].map { try context.utc($0, path: target + "/created") } as Any? ?? NSNull(),
            "checklists": try context.checklists(raw["checklists"] as! [[String: Any]], owner: owner, scope: target),
            "members": members, "label_ids": labels, "comments": try context.comments(raw["comments"] as! [[String: Any]], scope: target),
            "reactions": reactions, "shows_reactions_in_previews": raw["showsReactionsInPreviews"] ?? NSNull(),
            "attachments": attachments, "cover_attachment_id": cover, "dismissed_activity_ids": card.dismissedActivityIDs.sorted(),
            "appearance": try context.appearance(raw["appearance"], kind: "item_appearance"), "section_layout": layout,
            "edit_history": try context.history(raw["editHistory"] as? [[String: Any]], scope: target)]
        return context.document("card", id: target, payload: payload)
    }
}


/// Prepares personal selections without assigning an unverified cloud account.
/// @section Purpose
///     Retain owner-qualified bookmarks and importance as local evidence until account binding.
@MainActor
enum MigrationSelectionPreview
{

    /// Reviewable entries remain distinct from canonical content_selection records.
    /// @section Purpose
    ///     Expose unresolved or conflicting selections without discarding their original stores.
    struct Result
    {

        let entries: [[String: Any]]
        let issues:  [String]
    }


    /// @fcn MigrationSelectionPreview.prepare
    /// @brief Reconcile saved selections against exact original owners and converted Card targets
    /// @details Does not infer an account ID, clamp importance, or spread a numeric bookmark across owners.
    /// @param[in] values Frozen original preferences
    /// @param[in] owners Distinct original owner namespaces and Collections
    /// @param[in] currentScope Calendar owner of the unqualified Board bookmark projection
    /// @param[in] targets Existing owner-qualified canonical Card mappings
    /// @return Local-only entries and explicit review issues; originals are never changed
    static func prepare(values: [String: Any], owners: [(String, PersonalCollection)],
        currentScope: String?, targets: [String: String]) -> Result
    {

        var issues: [String] = []
        var entries: [[String: Any]] = []
        var levels: [String: Int] = [:]
        var unresolved: [[String: Any]] = []
        var importanceInvalid = false
        var uncertain: Set<String> = []
        if let value = values["Plenact.LibraryImportant.v1"]
        {
            do
            {
                guard let data = value as? Data,
                      let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                      raw.allSatisfy({ Set($0.keys).isSubset(of: ["collectionID", "cardID", "level"]) }) else
                {
                    throw MigrationContentValues.Failure.invalid("importance_shape")
                }
                let source = try JSONDecoder().decode([LibraryImportanceItem].self, from: data)
                var seen: Set<String> = []
                for item in source
                {
                    let owner = item.collectionID.uuidString.lowercased()
                    let key = owner + ":" + String(item.cardID)
                    guard seen.insert(key).inserted, (0...5).contains(item.level ?? 1) else
                    {
                        throw MigrationContentValues.Failure.invalid("importance_duplicate_or_range")
                    }
                    let scopes = owners.filter { $0.1.id == item.collectionID }.map(\.0)
                    if scopes.count == 1, let scope = scopes.first,
                       targets[scope + ":" + String(item.cardID)] != nil
                    {
                        levels[scope + ":" + String(item.cardID)] = item.level ?? 1
                    }
                    else
                    {
                        for scope in scopes
                        {
                            uncertain.insert(scope + ":" + String(item.cardID))
                        }
                        issues.append("importance_target_unresolved:" + key)
                        unresolved.append(["source_collection_id": owner, "source_card_id": item.cardID,
                            "source_owner_scope": NSNull(), "card_id": NSNull(),
                            "bookmarked": NSNull(), "importance": item.level ?? 1])
                    }
                }
            }
            catch
            {
                levels = [:]
                unresolved = []
                importanceInvalid = true
                issues.append("importance_source_requires_review")
            }
        }
        if let value = values["Plenact.SavedCardIDs.v1"]
        {
            if let ids = value as? [Int], Set(ids).count == ids.count,
               let scope = currentScope, let owner = owners.first(where: { $0.0 == scope }),
               Set(ids) == owner.1.savedCardIDs
            {
                // This is the current Week's projection, already represented by its owner below.
            }
            else
            {
                issues.append("board_bookmark_projection_requires_review")
            }
        }
        for (scope, owner) in owners.sorted(by: { $0.0 < $1.0 })
        {
            var cardIDs = owner.savedCardIDs
            for list in owner.lists
            {
                for card in list.cards + list.archivedCards
                {
                    if levels[scope + ":" + String(card.id)] != nil
                    {
                        cardIDs.insert(card.id)
                    }
                }
            }
            for card in cardIDs.sorted()
            {
                let key = scope + ":" + String(card)
                let target = targets[key]
                if target == nil
                {
                    issues.append("bookmark_target_unresolved:" + key)
                }
                entries.append(["source_collection_id": owner.id.uuidString.lowercased(),
                    "source_owner_scope": scope, "source_card_id": card,
                    "card_id": target as Any? ?? NSNull(), "bookmarked": owner.savedCardIDs.contains(card),
                    "importance": importanceInvalid || uncertain.contains(key) ? NSNull() : (levels[key] ?? 0) as Any])
            }
        }
        return Result(entries: entries + unresolved, issues: issues.sorted())
    }
}
