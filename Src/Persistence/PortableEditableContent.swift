// --------------------------------------------------------------------------------------------------
// @file       PortableEditableContent.swift
// @brief      Portable-to-native editable List and Card reconstruction without source-backup fallback
// @details    Supported User Data Model versions: 1.0 content; working 1.1 package input. Retains UUID
//             identity aliases separately from numeric editor IDs. Does not install application data.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Converts portable content into the real editor models while retaining canonical identity evidence.
/// @section Purpose
///     Build the normal-workspace import bridge without silently loading legacy source preferences.
@MainActor
struct PortableEditableContent
{

    let records:       [[String: Any]]
    let numericIDs:    [String: Int]
    let assetFiles:    [String: String]
    let deletedCardIDs: Set<String>


    /// Adapter failures reject unsupported or ambiguous values rather than defaulting authored content.
    /// @section Purpose
    ///     Keep incomplete reconstruction from being installed as an editable workspace.
    enum Failure: LocalizedError
    {

        case invalid, unsupported, dateContextRequired

        /// @fcn Failure.errorDescription
        /// @brief Explain a blocked editable reconstruction without exposing private values
        /// @return Actionable local import guidance
        var errorDescription: String?
        {

            switch self
            {
            case .invalid:
                return "Some portable record identities or values are inconsistent."
            case .unsupported:
                return "This package includes a feature the current editable importer cannot safely preserve."
            case .dateContextRequired:
                return "The original date/time context cannot be safely applied. For this test, the Simulator timezone must match the package’s original timezone."
            }
        }
    }


    /// @fcn PortableEditableContent.init
    /// @brief Allocate deterministic editor aliases independently of record titles and array order
    /// @param[in] records Canonical content and unavailable-reference records
    /// @param[in] assetFiles Verified Asset UUID to safe destination filename mapping
    /// @param[in] retainedAliases Previously retained UUID aliases; deleted identities remain reserved
    /// @param[in] deletedCardIDs Validated working 1.1 pending local deletions; retained records are still checked
    /// @return An immutable reconstruction context
    /// @throws Duplicate identities or unsafe filenames
    init(records: [[String: Any]], assetFiles: [String: String], retainedAliases: [String: Int] = [:], deletedCardIDs: Set<String> = []) throws
    {

        let ids = records.compactMap { $0["id"] as? String }
        guard ids.count == records.count, Set(ids).count == ids.count,
              ids.allSatisfy({ UUID(uuidString: $0) != nil }),
              Set(records.compactMap { $0["workspace_id"] as? String }).count == 1,
              records.allSatisfy({ $0["workspace_id"] is String && $0["user_data_model_version"] as? String == "1.0" }),
              assetFiles.values.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") && $0 != "." && $0 != ".." }) else
        {
            throw Failure.invalid
        }
        var targets = Set(records.filter { ["card", "list"].contains($0["record_type"] as? String ?? "") }.compactMap { $0["id"] as? String })
        for record in records where record["record_type"] as? String == "unavailable_reference"
        {
            if let payload = record["payload"] as? [String: Any], payload["target_type"] as? String == "card",
               let target = payload["target_id"] as? String
            {
                targets.insert(target)
            }
        }
        self.deletedCardIDs = deletedCardIDs
        self.records = records
        self.assetFiles = assetFiles
        guard Set(retainedAliases.values).count == retainedAliases.count,
              retainedAliases.values.allSatisfy({ $0 > 0 && $0 < Int.max }),
              retainedAliases.keys.allSatisfy({ UUID(uuidString: $0) != nil }) else
        {
            throw Failure.invalid
        }
        var aliases = retainedAliases
        var next = (aliases.values.max() ?? 0) + 1
        for id in targets.sorted() where aliases[id] == nil
        {
            guard next < Int.max else
            {
                throw Failure.invalid
            }
            aliases[id] = next
            next += 1
        }
        self.numericIDs = aliases
    }


    /// @fcn PortableEditableContent.mapped
    /// @brief Rename an explicitly supported value shape while preserving nulls and rejecting unknown fields
    /// @param[in] value Canonical dictionary
    /// @param[in] fields Canonical-to-native field map
    /// @return Native Codable shape
    /// @throws Unknown canonical fields
    func mapped(_ value: [String: Any], fields: [String: String]) throws -> [String: Any]
    {

        guard Set(value.keys) == Set(fields.keys) else
        {
            throw Failure.unsupported
        }
        return Dictionary(uniqueKeysWithValues: value.map { (fields[$0.key]!, $0.value) })
    }


    /// @fcn PortableEditableContent.timestamp
    /// @brief Convert a canonical UTC instant into Swift Codable reference-epoch seconds
    /// @param[in] value Nullable fixed UTC timestamp
    /// @return Reference-epoch seconds or null
    /// @throws Malformed timestamps
    func timestamp(_ value: Any?) throws -> Any
    {

        guard let value, !(value is NSNull) else
        {
            return NSNull()
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let text = value as? String, let date = formatter.date(from: text) else
        {
            throw Failure.invalid
        }
        return date.timeIntervalSinceReferenceDate
    }


    /// @fcn PortableEditableContent.date
    /// @brief Reconstruct timed instants exactly and civil dates only with explicit destination context
    /// @param[in] value Canonical tagged date
    /// @param[in] timeZoneID Explicit owner timezone
    /// @param[in] civilDate Explicit owner day required for time-only values
    /// @return Codable reference-epoch seconds or null
    /// @throws Missing context, invalid dates or ambiguous repeated wall-clock time
    func date(_ value: Any?, timeZoneID: String, civilDate: String?) throws -> Any
    {

        guard let value, !(value is NSNull) else
        {
            return NSNull()
        }
        guard let object = value as? [String: Any], let kind = object["kind"] as? String else
        {
            throw Failure.invalid
        }
        if kind == "date_and_time"
        {
            guard Set(object.keys) == ["kind", "local_date_time", "time_zone", "tzdb_version", "utc_instant", "utc_offset", "occurrence"],
                  object["utc_instant"] is String else
            {
                throw Failure.invalid
            }
            return try timestamp(object["utc_instant"])
        }
        guard let zone = TimeZone(identifier: timeZoneID) else
        {
            throw Failure.dateContextRequired
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.isLenient = false
        let text: String
        if kind == "date", Set(object.keys) == ["kind", "date"], let day = object["date"] as? String
        {
            formatter.dateFormat = "yyyy-MM-dd"
            text = day
        }
        else if kind == "time", Set(object.keys) == ["kind", "time"], let day = civilDate, let time = object["time"] as? String
        {
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            text = day + " " + time
        }
        else
        {
            throw Failure.dateContextRequired
        }
        guard let result = formatter.date(from: text), formatter.string(from: result) == text else
        {
            throw Failure.dateContextRequired
        }
        if kind == "time", [-3600.0, 3600.0].contains(where: { formatter.string(from: result.addingTimeInterval($0)) == text })
        {
            throw Failure.dateContextRequired
        }
        return result.timeIntervalSinceReferenceDate
    }


    /// @fcn PortableEditableContent.file
    /// @brief Resolve a verified Asset into a native filename without inventing missing originals
    /// @param[in] value Nullable Asset UUID
    /// @return Verified destination filename or null
    /// @throws Missing Asset mapping
    func file(_ value: Any?) throws -> Any
    {

        guard let value, !(value is NSNull) else
        {
            return NSNull()
        }
        guard let id = value as? String, let name = assetFiles[id] else
        {
            throw Failure.invalid
        }
        return name
    }


    /// @fcn PortableEditableContent.alias
    /// @brief Resolve a stable UUID to the retained editor identity map
    /// @param[in] value Nullable canonical Card/List UUID
    /// @return Numeric editor alias or null
    /// @throws Undeclared reference
    func alias(_ value: Any?) throws -> Any
    {

        guard let value, !(value is NSNull) else
        {
            return NSNull()
        }
        guard let id = value as? String, let number = numericIDs[id] else
        {
            throw Failure.invalid
        }
        return number
    }


    /// @fcn PortableEditableContent.appearance
    /// @brief Reconstruct authored appearance fields without flattening inherited values
    /// @param[in] value Nullable canonical appearance
    /// @param[in] kind Explicit appearance value kind
    /// @return Native Codable appearance value or null
    /// @throws Unsupported provider or missing Asset mapping
    func appearance(_ value: Any?, kind: String) throws -> Any
    {

        guard let value, !(value is NSNull) else
        {
            return NSNull()
        }
        guard var source = value as? [String: Any], let fields = MigrationContentValues.appearanceFields[kind] else
        {
            throw Failure.invalid
        }
        if kind == "remote_photo"
        {
            guard source.removeValue(forKey: "provider") as? String == "unsplash" else
            {
                throw Failure.unsupported
            }
        }
        var output = try mapped(source, fields: Dictionary(uniqueKeysWithValues: fields.map { ($0.value, $0.key) }))
        for (key, nestedKind) in ["collectionBackground": "collection_background", "studioSurface": "surface",
            "studioCardSurface": "surface", "addItemTextColor": "color", "iconColor": "color", "remotePhoto": "remote_photo"]
        {
            if let nested = output[key]
            {
                output[key] = try appearance(nested, kind: nestedKind)
            }
        }
        if output["photoFileName"] != nil
        {
            output["photoFileName"] = try file(output["photoFileName"])
        }
        if output["preset"] as? String == "forest_path"
        {
            output["preset"] = "forestPath"
        }
        if output["preset"] as? String == "sunlit_wall"
        {
            output["preset"] = "sunlitWall"
        }
        if output["listViewMode"] as? String == "note_list"
        {
            output["listViewMode"] = "noteList"
        }
        for key in ["red", "green", "blue", "strength", "readability", "verticalPosition", "listBackgroundOpacity"]
        {
            if let number = output[key] as? NSNumber,
               !number.doubleValue.isFinite || !(0...1).contains(number.doubleValue)
            {
                throw Failure.invalid
            }
        }
        if let zoom = output["zoom"] as? NSNumber, !(1...2).contains(zoom.doubleValue)
        {
            throw Failure.invalid
        }
        return output
    }


    /// @fcn PortableEditableContent.card
    /// @brief Reconstruct an actual editable Card including all supported nested content
    /// @param[in] record Canonical Card
    /// @param[in] listTitle Actual owning List title
    /// @param[in] timeZoneID Explicit owner timezone
    /// @param[in] civilDate Explicit owner day for time-only scheduling
    /// @return Native editable Card; no persistence or defaults/example loaders are invoked
    /// @throws Unsupported fields, unresolved references or native decoding failures
    func card(_ record: [String: Any], listTitle: String, timeZoneID: String, civilDate: String?) throws -> KanbanCard
    {

        guard record["record_type"] as? String == "card", let payload = record["payload"] as? [String: Any] else
        {
            throw Failure.invalid
        }
        let fields = ["list_id": "_list", "archived": "_archived", "title": "word", "is_divider": "isDivider",
            "completed": "isTitleChecked", "editing_locked": "editingLocked", "presentation": "itemPresentation",
            "display_format": "listDisplayFormat", "description_override": "descriptionOverride", "subtitle_override": "subtitleOverride",
            "location": "location", "start_kind": "startDateKind", "due_kind": "dueDateKind", "start": "startDate", "due": "dueDate",
            "shows_due_date_in_list": "showsDueDateInList", "source_created_at_utc": "createdAt", "checklists": "checklists",
            "members": "members", "label_ids": "labelIDs", "comments": "comments", "reactions": "reactions",
            "shows_reactions_in_previews": "showsReactionsInPreviews", "attachments": "attachments", "cover_attachment_id": "coverAttachmentID",
            "dismissed_activity_ids": "dismissedActivityIDs", "appearance": "appearance", "section_layout": "sectionLayout", "edit_history": "editHistory"]
        guard Set(payload.keys) == Set(fields.keys) else
        {
            throw Failure.unsupported
        }
        var raw = try mapped(payload, fields: fields)
        raw.removeValue(forKey: "_list")
        raw.removeValue(forKey: "_archived")
        raw["id"] = try alias(record["id"])
        raw["listTitle"] = listTitle
        for field in ["startDate", "dueDate"]
        {
            raw[field] = try date(raw[field], timeZoneID: timeZoneID, civilDate: civilDate)
        }
        for field in ["startDateKind", "dueDateKind"] where raw[field] as? String == "date_and_time"
        {
            raw[field] = "dateAndTime"
        }
        raw["createdAt"] = try timestamp(raw["createdAt"])
        raw["appearance"] = try appearance(raw["appearance"], kind: "item_appearance")
        raw["checklists"] = try checklists(array(payload["checklists"]))
        raw["comments"] = try comments(array(payload["comments"]))
        raw["attachments"] = try attachments(payload["attachments"])
        raw["editHistory"] = try history(payload["edit_history"])
        raw["members"] = try members(array(payload["members"]))
        raw["reactions"] = try reactions(payload["reactions"])
        if var layout = payload["section_layout"] as? [String: Any]
        {
            for key in ["order", "hidden"]
            {
                guard let values = layout[key] as? [String] else
                {
                    throw Failure.invalid
                }
                layout[key] = values.map { $0 == "quick_actions" ? "quickActions" : $0 }
            }
            raw["sectionLayout"] = layout
        }
        return try JSONDecoder().decode(KanbanCard.self, from: JSONSerialization.data(withJSONObject: raw))
    }


    /// @fcn PortableEditableContent.list
    /// @brief Reconstruct ordered active and archived Cards into the actual editable List model
    /// @param[in] record Canonical List
    /// @param[in] timeZoneID Explicit owning timezone
    /// @param[in] civilDate Explicit owning day when needed
    /// @return Native editable List
    /// @throws Membership, decoding or nested mapping failures
    func list(_ record: [String: Any], timeZoneID: String, civilDate: String?) throws -> KanbanList
    {

        guard record["record_type"] as? String == "list", let value = record["payload"] as? [String: Any],
              let title = value["title"] as? String else
        {
            throw Failure.invalid
        }
        var raw = try mapped(value, fields: ["collection_id": "_collection", "title": "title", "subtitle_override": "subtitleOverride",
            "archived": "isArchived", "default_item_presentation": "defaultItemPresentation", "appearance": "appearance",
            "card_ids": "cards", "archived_card_ids": "archivedCards"])
        raw.removeValue(forKey: "_collection")
        raw["id"] = try alias(record["id"])
        raw["appearance"] = try appearance(raw["appearance"], kind: "item_appearance")
        var used = Set<String>()
        for (field, archived) in [("cards", false), ("archivedCards", true)]
        {
            guard let ids = raw[field] as? [String] else
                {
                    throw Failure.invalid
                }
            raw[field] = try ids.compactMap { id -> Any? in
                guard used.insert(id).inserted, let target = records.first(where: { $0["id"] as? String == id }),
                      let payload = target["payload"] as? [String: Any], payload["list_id"] as? String == record["id"] as? String,
                      payload["archived"] as? Bool == archived else
                {
                    throw Failure.invalid
                }
                let native = try card(target, listTitle: title, timeZoneID: timeZoneID, civilDate: civilDate)
                if deletedCardIDs.contains(id)
                {
                    return nil
                }
                return try JSONSerialization.jsonObject(with: JSONEncoder().encode(native))
            }
        }
        return try JSONDecoder().decode(KanbanList.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    /// @fcn PortableEditableContent.collection
    /// @brief Reconstruct collection ownership, exact List order and bookmarked Card membership
    /// @param[in] record Canonical collection
    /// @param[in] selections Canonical account-bound selections for the workspace
    /// @param[in] accountID Expected owning account
    /// @param[in] timeZoneID Explicit owning timezone
    /// @param[in] listDates Explicit civil date per mapped day List
    /// @return Actual editable personal collection without persistence
    /// @throws Ownership, membership, date-context or decoding errors
    func collection(_ record: [String: Any], selections: [[String: Any]], accountID: String,
        timeZoneID: String, listDates: [String: String]) throws -> PersonalCollection
    {

        guard record["record_type"] as? String == "collection", let id = record["id"] as? String,
              let payload = record["payload"] as? [String: Any], let listIDs = payload["list_ids"] as? [String],
              Set(listIDs).count == listIDs.count, payload["preferred_focused_list_id"] is NSNull else
        {
            throw Failure.invalid
        }
        var raw = try mapped(payload, fields: ["title": "title", "kind": "kind", "icon": "icon", "color": "color",
            "description": "collectionDescription", "archived": "isArchived", "board_appearance": "boardAppearance",
            "preferred_focused_list_id": "preferredFocusedListID", "list_ids": "lists"])
        raw["id"] = id
        guard let kind = payload["kind"] as? String, ["list", "board"].contains(kind) else
        {
            throw Failure.invalid
        }
        raw["kind"] = kind == "list" ? "List" : "Board"
        raw["color"] = try appearance(payload["color"], kind: "color")
        raw["boardAppearance"] = try appearance(payload["board_appearance"], kind: "board_appearance")
        if let focused = payload["preferred_focused_list_id"] as? String, !listIDs.contains(focused)
        {
            throw Failure.invalid
        }
        // The current model derives focused List state; it cannot persist an authored override.
        raw.removeValue(forKey: "preferredFocusedListID")
        var ownedCards = Set<String>()
        raw["lists"] = try listIDs.map { target -> Any in
            guard let record = records.first(where: { $0["id"] as? String == target }),
                  let body = record["payload"] as? [String: Any], body["collection_id"] as? String == id,
                  let active = body["card_ids"] as? [String], let archived = body["archived_card_ids"] as? [String] else
            {
                throw Failure.invalid
            }
            for card in active + archived
            {
                guard ownedCards.insert(card).inserted else
                {
                    throw Failure.invalid
                }
            }
            let value = try list(record, timeZoneID: timeZoneID, civilDate: listDates[target])
            return try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        }
        var bookmarks: [Int] = []
        var seenSelections = Set<String>()
        for selection in selections
        {
            guard selection["record_type"] as? String == "content_selection", let body = selection["payload"] as? [String: Any],
                  body["account_id"] as? String == accountID, let target = body["card_id"] as? String,
                  seenSelections.insert(target).inserted, let saved = body["bookmarked"] as? Bool else
            {
                throw Failure.invalid
            }
            if ownedCards.contains(target), !deletedCardIDs.contains(target), saved
            {
                guard let number = numericIDs[target] else
                {
                    throw Failure.invalid
                }
                bookmarks.append(number)
            }
        }
        raw["savedCardIDs"] = bookmarks.sorted()
        return try JSONDecoder().decode(PersonalCollection.self, from: JSONSerialization.data(withJSONObject: raw))
    }

}
