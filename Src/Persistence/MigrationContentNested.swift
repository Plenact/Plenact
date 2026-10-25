// --------------------------------------------------------------------------------------------------
// @file       MigrationContentNested.swift
// @brief      Lossless checklist, activity, attachment, history and appearance conversion
// @details    Supported User Data Model versions: 1.0. Partial, local-only migration preview.
//             Original source bytes remain preserved; no cloud ownership or synchronization is implied.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Explicitly maps nested native values; unknown source fields are rejected before native decoding.
/// @section Purpose
///     Preserve inactive retained content, attribution and media/history evidence.
extension MigrationContentValues
{

    /// @fcn MigrationContentValues.nested
    /// @brief Map an owned nested UUID into the original Card scope
    /// @param[in] kind Nested identity kind
    /// @param[in] value Original UUID
    /// @param[in] scope Stable canonical Card scope
    /// @return Stable owned nested UUID
    /// @throws Invalid/duplicate nested identity errors
    func nested(_ kind: String, _ value: Any?, scope: String) throws -> String
    {

        let source = try Self.lowerUUID(value)
        let key = scope + ":" + kind + ":" + source
        guard usedNested.insert(key).inserted else
        {
            throw Failure.invalid("duplicate_nested_" + kind)
        }
        return try id("nested_" + kind, owner: scope, legacy: source)
    }


    /// @fcn MigrationContentValues.comments
    /// @brief Preserve authored text and source attribution without inventing an authenticated author
    /// @param[in] values Source comment objects
    /// @param[in] scope Owning Card scope
    /// @return Canonical comment values
    /// @throws Invalid nested IDs or timestamps
    func comments(_ values: [[String: Any]], scope: String) throws -> [[String: Any]]
    {

        try values.map { value in
            ["id": try nested("comment", value["id"], scope: scope),
                "author": value["author"]!, "body": value["body"]!,
                "source_created_at_utc": try utc(value["createdAt"]!, path: scope + "/comment/" + (value["id"] as! String)),
                "author_account_id": NSNull()]
        }
    }


    /// @fcn MigrationContentValues.detail
    /// @brief Convert an owned Action Detail recursively
    /// @param[in] value Source detail
    /// @param[in] owner Original Collection identity
    /// @param[in] scope Owning Card scope
    /// @return Complete canonical detail
    /// @throws Nested conversion errors
    func detail(_ value: [String: Any], owner: String, scope: String) throws -> [String: Any]
    {

        ["id": try nested("action_detail", value["id"], scope: scope), "description": value["description"]!,
            "checklists": try checklists(value["checklists"] as! [[String: Any]], owner: owner, scope: scope),
            "comments": try comments(value["comments"] as! [[String: Any]], scope: scope)]
    }


    /// @fcn MigrationContentValues.checklists
    /// @brief Convert actions and independently retained inactive content without flattening recursion
    /// @param[in] values Source checklist array
    /// @param[in] owner Original Collection identity
    /// @param[in] scope Owning Card scope
    /// @return Complete canonical checklist array
    /// @throws Invalid links, divergent retained mirrors or duplicate identities
    func checklists(_ values: [[String: Any]], owner: String, scope: String) throws -> [[String: Any]]
    {

        try values.map { list in
            let identifier = try nested("checklist", list["id"], scope: scope)
            let items = try (list["items"] as! [[String: Any]]).map { item -> [String: Any] in
                let identifier = try nested("checklist_item", item["id"], scope: scope)
                var linkedOwner = owner
                var linkedCollection: Any = NSNull()
                let originalItem = try Self.lowerUUID(item["id"])
                let calendarOverride = calendarOwnerScopes.contains(owner) ? checklistWeekOverrides[originalItem] : nil
                if let original = calendarOverride ?? (item["linkedCollectionID"] as? String)?.lowercased()
                {
                    if originalCollectionIDs[owner] == original
                    {
                        linkedOwner = owner
                    }
                    else if let candidates = ownerScopesByCollection[original], candidates.count == 1
                    {
                        linkedOwner = candidates[0]
                    }
                    else
                    {
                        linkedOwner = "unresolved_from:" + owner + ":" + original
                    }
                    let target = try collectionTargets[linkedOwner] ?? id("collection", owner: "source_collections", legacy: linkedOwner)
                    linkedCollection = try reference("collection", target)
                }
                let source = item["content"] as! [String: Any]
                let kind = source["kind"] as! String
                var content: [String: Any]
                switch kind
                {
                case "standard": content = ["kind": "standard"]
                case "linkedCard": content = ["kind": "linked_card", "card_id": try cardReference(source["cardID"] as! Int, owner: linkedOwner)]
                case "webLink": content = ["kind": "web_link", "url": try Self.webURL(source["url"]!)]
                case "actionDetail": content = ["kind": "action_detail", "detail": try detail(source["detail"] as! [String: Any], owner: owner, scope: scope)]
                default: throw Failure.invalid("action_kind")
                }
                var retained: Any = NSNull()
                if let saved = item["retainedDetail"] as? [String: Any]
                {
                    if kind == "actionDetail"
                    {
                        guard NSDictionary(dictionary: saved).isEqual(to: source["detail"] as! [String: Any]) else
                        {
                            throw Failure.invalid("divergent_retained_detail")
                        }
                        retained = content["detail"]!
                    }
                    else
                    {
                        retained = try detail(saved, owner: owner, scope: scope)
                    }
                }
                return ["id": identifier, "title": item["title"]!, "completed": item["isCompleted"]!,
                    "content": content, "retained_detail": retained,
                    "retained_card_id": try (item["retainedCardID"] as? Int).map { try cardReference($0, owner: linkedOwner) } as Any? ?? NSNull(),
                    "retained_url": try item["retainedURL"].map(Self.webURL) as Any? ?? NSNull(),
                    "linked_collection_id": linkedCollection]
            }
            return ["id": identifier, "title": list["title"]!, "items": items]
        }
    }


    /// @fcn MigrationContentValues.webURL
    /// @brief Retain supported HTTP(S) URLs without rewriting the original token
    /// @param[in] value Native URL string
    /// @return Original URL text
    /// @throws Unsupported or malformed URL values
    static func webURL(_ value: Any) throws -> String
    {

        guard let text = value as? String, let url = URLComponents(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
              text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else
        {
            throw Failure.invalid("unsupported_url")
        }
        return text
    }


    /// @fcn MigrationContentValues.attachments
    /// @brief Preserve media metadata and original/preview references independently
    /// @param[in] values Optional original attachment array
    /// @param[in] scope Owning Card scope
    /// @return Canonical attachment array or explicit null
    /// @throws Unsafe media/URL values
    func attachments(_ values: [[String: Any]]?, scope: String) throws -> Any
    {

        guard let values else
        {
            return NSNull()
        }
        return try values.map { value -> [String: Any] in
            let target = try nested("attachment", value["id"], scope: scope)
            attachmentTargets[scope + ":" + (try Self.lowerUUID(value["id"]))] = target
            return ["id": target, "kind": value["mediaKind"] ?? (value["url"] == nil ? "photo" : "link"),
                "asset_id": try asset(value["fileName"], area: "Documents/CardAttachments"),
                "drawing_asset_id": try asset(value["drawingFileName"], area: "Documents/CardAttachments"),
                "url": try value["url"].map(Self.webURL) as Any? ?? NSNull(),
                "source_added_at_utc": try utc(value["addedAt"]!, path: scope + "/attachment/" + target),
                "example_image": value["exampleImage"] ?? NSNull(), "caption": value["caption"] ?? NSNull()]
        }
    }


    /// @fcn MigrationContentValues.history
    /// @brief Preserve opaque history value bytes rather than interpreting them as current content
    /// @param[in] values Optional source history
    /// @param[in] scope Owning Card scope
    /// @return Canonical history or explicit null
    /// @throws Invalid identities/timestamps
    func history(_ values: [[String: Any]]?, scope: String) throws -> Any
    {

        guard let values else
        {
            return NSNull()
        }
        return try values.map { value -> [String: Any] in
            let changes = (value["changes"] as! [[String: Any]]).map { change -> [String: Any] in
                var result: [String: Any] = ["field": change["field"]!]
                for (source, target) in [("previousValue", "previous_value"), ("newValue", "new_value")]
                {
                    if let data = change[source]
                    {
                        result[target] = ["encoding": "base64", "source_format": "swift_codable_json", "source_model_version": "local_legacy", "data": data]
                    }
                    else
                    {
                        result[target] = NSNull()
                    }
                }
                return result
            }
            return ["id": try nested("history", value["id"], scope: scope),
                "source_timestamp_utc": try utc(value["timestamp"]!, path: scope + "/history"), "changes": changes]
        }
    }
}
