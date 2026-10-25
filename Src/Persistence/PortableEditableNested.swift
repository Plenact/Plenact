// --------------------------------------------------------------------------------------------------
// @file       PortableEditableNested.swift
// @brief      Editable checklist, activity, attachment and opaque-history reconstruction
// @details    Supported User Data Model versions: 1.0 nested content. Rejects identity semantics the
//             current editor cannot represent, rather than stripping provenance or inventing originals.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Reconstructs the nested values used by Plenact's editable Card model.
/// @section Purpose
///     Keep authored content and inactive retained values when bridging the portable contract.
extension PortableEditableContent
{

    /// @fcn PortableEditableContent.array
    /// @brief Require a JSON object array without coercing malformed values to empty
    /// @param[in] value Required canonical array
    /// @return Exact dictionaries
    /// @throws Invalid shape
    func array(_ value: Any?) throws -> [[String: Any]]
    {

        guard let values = value as? [[String: Any]] else
        {
            throw Failure.invalid
        }
        return values
    }


    /// @fcn PortableEditableContent.comments
    /// @brief Retain text, IDs and timestamps without dropping authenticated author attribution
    /// @param[in] values Canonical comments
    /// @return Native comment shapes
    /// @throws Unrepresentable author identity or malformed values
    func comments(_ values: [[String: Any]]) throws -> [[String: Any]]
    {

        try values.map { value in
            guard value["author_account_id"] is NSNull else
            {
                throw Failure.unsupported
            }
            var raw = try mapped(value, fields: ["id": "id", "author": "author", "body": "body",
                "source_created_at_utc": "createdAt", "author_account_id": "_author"])
            raw.removeValue(forKey: "_author")
            raw["createdAt"] = try timestamp(raw["createdAt"])
            return raw
        }
    }


    /// @fcn PortableEditableContent.detail
    /// @brief Recursively reconstruct a retained Action Detail without executing it
    /// @param[in] value Canonical detail
    /// @return Native detail dictionary
    /// @throws Unsupported or malformed content
    func detail(_ value: [String: Any]) throws -> [String: Any]
    {

        var raw = try mapped(value, fields: ["id": "id", "description": "description", "checklists": "checklists", "comments": "comments"])
        raw["checklists"] = try checklists(array(value["checklists"]))
        raw["comments"] = try comments(array(value["comments"]))
        return raw
    }


    /// @fcn PortableEditableContent.checklists
    /// @brief Reconstruct active and inactive checklist content with owner-qualified linked identities
    /// @param[in] values Canonical checklist array
    /// @return Native checklist Codable shapes
    /// @throws Missing references, malformed content or unsupported actions
    func checklists(_ values: [[String: Any]]) throws -> [[String: Any]]
    {

        try values.map { list in
            var raw = try mapped(list, fields: ["id": "id", "title": "title", "items": "items"])
            raw["items"] = try array(list["items"]).map { item -> [String: Any] in
                var result = try mapped(item, fields: ["id": "id", "title": "title", "completed": "isCompleted", "content": "content",
                    "retained_detail": "retainedDetail", "retained_card_id": "retainedCardID", "retained_url": "retainedURL", "linked_collection_id": "linkedCollectionID"])
                guard let content = item["content"] as? [String: Any], let kind = content["kind"] as? String else
                {
                    throw Failure.invalid
                }
                switch kind
                {
                case "standard":
                    guard Set(content.keys) == ["kind"] else
                    {
                        throw Failure.unsupported
                    }
                    result["content"] = ["kind": "standard"]
                case "linked_card":
                    guard Set(content.keys) == ["kind", "card_id"] else
                    {
                        throw Failure.unsupported
                    }
                    result["content"] = ["kind": "linkedCard", "cardID": try alias(content["card_id"])]
                case "web_link":
                    guard Set(content.keys) == ["kind", "url"] else
                    {
                        throw Failure.unsupported
                    }
                    result["content"] = ["kind": "webLink", "url": content["url"]!]
                case "action_detail":
                    guard Set(content.keys) == ["kind", "detail"], let value = content["detail"] as? [String: Any] else
                    {
                        throw Failure.unsupported
                    }
                    result["content"] = ["kind": "actionDetail", "detail": try detail(value)]
                default:
                    throw Failure.unsupported
                }
                if let retained = item["retained_detail"] as? [String: Any]
                {
                    result["retainedDetail"] = try detail(retained)
                }
                result["retainedCardID"] = try alias(item["retained_card_id"])
                return result
            }
            return raw
        }
    }


    /// @fcn PortableEditableContent.attachments
    /// @brief Keep attachment identity and nullable metadata while resolving exact verified file aliases
    /// @param[in] value Nullable attachment array
    /// @return Native attachments or explicit null
    /// @throws Missing originals or malformed metadata
    func attachments(_ value: Any?) throws -> Any
    {

        if value is NSNull
        {
            return NSNull()
        }
        return try array(value).map { entry -> [String: Any] in
            var raw = try mapped(entry, fields: ["id": "id", "kind": "mediaKind", "asset_id": "fileName",
                "drawing_asset_id": "drawingFileName", "url": "url", "source_added_at_utc": "addedAt",
                "example_image": "exampleImage", "caption": "caption"])
            raw["fileName"] = try file(entry["asset_id"])
            raw["drawingFileName"] = try file(entry["drawing_asset_id"])
            raw["addedAt"] = try timestamp(entry["source_added_at_utc"])
            return raw
        }
    }


    /// @fcn PortableEditableContent.history
    /// @brief Restore opaque value bytes including absent-versus-empty data without interpreting or applying edits
    /// @param[in] value Nullable canonical history
    /// @return Native edit-history JSON shape or null
    /// @throws Unsupported opaque encoding or malformed source values
    func history(_ value: Any?) throws -> Any
    {

        if value is NSNull
        {
            return NSNull()
        }
        return try array(value).map { entry -> [String: Any] in
            var raw = try mapped(entry, fields: ["id": "id", "source_timestamp_utc": "timestamp", "changes": "changes"])
            raw["timestamp"] = try timestamp(entry["source_timestamp_utc"])
            raw["changes"] = try array(entry["changes"]).map { change -> [String: Any] in
                var mappedChange = try mapped(change, fields: ["field": "field", "previous_value": "previousValue", "new_value": "newValue"])
                for key in ["previousValue", "newValue"]
                {
                    if mappedChange[key] is NSNull
                    {
                        continue
                    }
                    guard let opaque = mappedChange[key] as? [String: Any],
                          Set(opaque.keys) == ["encoding", "source_format", "source_model_version", "data"],
                          opaque["encoding"] as? String == "base64", opaque["source_format"] as? String == "swift_codable_json",
                          opaque["source_model_version"] as? String == "local_legacy", let bytes = opaque["data"] as? String,
                          Data(base64Encoded: bytes) != nil else
                    {
                        throw Failure.unsupported
                    }
                    mappedChange[key] = bytes
                }
                return mappedChange
            }
            return raw
        }
    }


    /// @fcn PortableEditableContent.members
    /// @brief Reconstruct only assignee identity scopes supported by the existing editor
    /// @param[in] values Canonical assignees
    /// @return Native typed assignments
    /// @throws New or authenticated identity semantics that require a separate account adapter
    func members(_ values: [[String: Any]]) throws -> [[String: Any]]
    {

        try values.map { value in
            let kind = value["kind"] as? String
            guard (kind == "manual" && value["identity_scope"] as? String == "manual") ||
                (kind == "registered_user" && value["identity_scope"] as? String == "legacy_demo") else
            {
                throw Failure.unsupported
            }
            var raw = try mapped(value, fields: ["id": "id", "kind": "kind", "display_name": "displayName",
                "user_id": "userID", "identity_scope": "_scope"])
            raw.removeValue(forKey: "_scope")
            raw["kind"] = kind == "registered_user" ? "registeredUser" : "manual"
            return raw
        }
    }


    /// @fcn PortableEditableContent.reactions
    /// @brief Preserve source reaction authors and timestamps without inventing authenticated identity
    /// @param[in] value Nullable reaction array
    /// @return Native reactions or null
    /// @throws Authenticated attribution or malformed data unsupported by the native model
    func reactions(_ value: Any?) throws -> Any
    {

        if value is NSNull
        {
            return NSNull()
        }
        return try array(value).map { entry -> [String: Any] in
            guard entry["author_account_id"] is NSNull else
                    {
                        throw Failure.unsupported
                    }
            var raw = try mapped(entry, fields: ["id": "id", "emoji": "emoji", "source_author_id": "authorID",
                "source_created_at_utc": "createdAt", "author_account_id": "_author"])
            raw.removeValue(forKey: "_author")
            raw["createdAt"] = try timestamp(entry["source_created_at_utc"])
            return raw
        }
    }
}
