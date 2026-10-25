// --------------------------------------------------------------------------------------------------
// @file       PortableEditableSettings.swift
// @brief      Account-qualified preferences, profile, label, shortcut and importance editor projections
// @details    Supported User Data Model versions: 1.0. Pure reconstruction only; canonical ownership
//             and provenance remain separate from local UI identities and are never authenticated here.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Reconstructs personal metadata only after portable workspace ownership has been established by a caller.
/// @section Purpose
///     Keep settings and personal selections attached to the same identities as imported content.
extension PortableEditableContent
{

    /// @fcn PortableEditableContent.preferences
    /// @brief Restore effective settings using explicit field mappings and the retained List alias map
    /// @param[in] document Canonical user-preferences record, or nil for absent preferences
    /// @param[in] accountID Expected owning account
    /// @return Native preferences or nil; no app defaults are manufactured
    /// @throws Ownership, unknown field, range or unresolved List failures
    func preferences(_ document: [String: Any]?, accountID: String) throws -> LocalProfilePreferences?
    {

        guard let document else
        {
            return nil
        }
        let payload = try owned(document, kind: "user_preferences", accountID: accountID)
        guard Set(payload.keys) == ["account_id", "preferences"], let values = payload["preferences"] as? [String: Any] else
        {
            throw Failure.invalid
        }
        var raw = try mapped(values, fields: Dictionary(uniqueKeysWithValues: MigrationSettingsPreview.fields.map { ($0.value, $0.key) }))
        if let target = values["default_list_id"] as? String
        {
            _ = try record(target, kind: "list")
        }
        raw["defaultListID"] = try alias(values["default_list_id"])
        guard let count = values["today_focus_item_count"] as? Int, (0...12).contains(count),
              let order = values["today_focus_order"] as? String, ["day_list", "chronological"].contains(order) else
        {
            throw Failure.invalid
        }
        raw["todayFocusOrder"] = order == "day_list" ? "dayList" : "chronological"
        return try JSONDecoder().decode(LocalProfilePreferences.self, from: JSONSerialization.data(withJSONObject: raw))
    }


    /// @fcn PortableEditableContent.owned
    /// @brief Require an account-bound record in this reconstruction workspace
    /// @param[in] document Canonical record
    /// @param[in] kind Expected type
    /// @param[in] accountID Expected owning account; not proof of authentication
    /// @return Account-qualified payload
    /// @throws Wrong ownership, workspace or record type
    func owned(_ document: [String: Any], kind: String, accountID: String) throws -> [String: Any]
    {

        guard document["record_type"] as? String == kind,
              document["workspace_id"] as? String == records.first?["workspace_id"] as? String,
              let payload = document["payload"] as? [String: Any], payload["account_id"] as? String == accountID else
        {
            throw Failure.invalid
        }
        return payload
    }


    /// @fcn PortableEditableContent.profile
    /// @brief Reconstruct the local profile without using its name/email/source ID as cloud ownership
    /// @param[in] document Canonical profile record or nil
    /// @param[in] preferences Explicit reconstructed preferences embedded by the native model
    /// @param[in] accountID Expected owner
    /// @return Native profile projection or nil
    /// @throws Missing preferences, timestamp, original avatar or unsupported fields
    func profile(_ document: [String: Any]?, preferences: LocalProfilePreferences?, accountID: String) throws -> LocalProfile?
    {

        guard let document else
        {
            return nil
        }
        guard let preferences, let id = document["id"] as? String else
        {
            throw Failure.unsupported
        }
        let payload = try owned(document, kind: "user_profile", accountID: accountID)
        var raw = try mapped(payload, fields: ["account_id": "_account", "source_profile_id": "_source",
            "source_created_at_utc": "createdAt", "display_name": "displayName", "email": "email", "context": "context",
            "avatar_color": "avatarColor", "avatar_icon": "avatarIcon", "avatar_foreground_color": "avatarForegroundColor",
            "avatar_asset_id": "avatarPhotoFileName"])
        raw.removeValue(forKey: "_account")
        raw.removeValue(forKey: "_source")
        raw["id"] = id
        raw["createdAt"] = try timestamp(payload["source_created_at_utc"])
        raw["avatarColor"] = try appearance(payload["avatar_color"], kind: "color")
        raw["avatarForegroundColor"] = try appearance(payload["avatar_foreground_color"], kind: "color")
        raw["avatarPhotoFileName"] = try file(payload["avatar_asset_id"])
        raw["preferences"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences))
        return try JSONDecoder().decode(LocalProfile.self, from: JSONSerialization.data(withJSONObject: raw))
    }


    /// @fcn PortableEditableContent.labelLibrary
    /// @brief Rebuild label definitions with canonical IDs matching reconstructed Card references
    /// @return Native library in canonical input order
    /// @throws Invalid category membership or unsupported fields
    func labelLibrary() throws -> LabelLibrary
    {

        let categories = records.filter { $0["record_type"] as? String == "label_category" }
        let labels = records.filter { $0["record_type"] as? String == "label" }
        let known = Set(categories.compactMap { $0["id"] as? String })
        let nativeCategories = try categories.map { record -> [String: Any] in
            guard let body = record["payload"] as? [String: Any] else
            {
                throw Failure.invalid
            }
            var raw = try mapped(body, fields: ["name": "name"])
            raw["id"] = record["id"]
            return raw
        }
        let nativeLabels = try labels.map { record -> [String: Any] in
            guard let body = record["payload"] as? [String: Any], let category = body["category_id"] as? String,
                  known.contains(category) else
            {
                throw Failure.invalid
            }
            var raw = try mapped(body, fields: ["name": "name", "category_id": "categoryID", "color": "color"])
            raw["id"] = record["id"]
            return raw
        }
        return try JSONDecoder().decode(LabelLibrary.self,
            from: JSONSerialization.data(withJSONObject: ["categories": nativeCategories, "labels": nativeLabels]))
    }


    /// @fcn PortableEditableContent.shortcuts
    /// @brief Resolve authored shortcut order using explicit owner/List references
    /// @param[in] document Optional canonical shortcuts
    /// @return Native shortcut references, or nil when the canonical record is absent
    /// @throws Unresolved, duplicate or incorrectly owned List targets
    func shortcuts(_ document: [String: Any]?) throws -> [WorkspaceListReference]?
    {

        guard let document else
        {
            return nil
        }
        guard document["record_type"] as? String == "today_shortcuts", let body = document["payload"] as? [String: Any],
              Set(body.keys) == ["items"] else
            {
                throw Failure.invalid
            }
        var seen = Set<String>()
        return try array(body["items"]).map { item in
            guard Set(item.keys) == ["collection_id", "list_id"], let owner = item["collection_id"] as? String,
                  let ownerID = UUID(uuidString: owner), let listID = item["list_id"] as? String,
                  seen.insert(owner + ":" + listID).inserted, let number = numericIDs[listID] else
            {
                throw Failure.invalid
            }
            let collection = try record(owner, kind: "collection")
            let list = try record(listID, kind: "list")
            guard (list["payload"] as? [String: Any])?["collection_id"] as? String == owner,
                  ((collection["payload"] as? [String: Any])?["list_ids"] as? [String])?.contains(listID) == true else
            {
                throw Failure.invalid
            }
            return WorkspaceListReference(ownerID: ownerID, listID: number)
        }
    }


    /// @fcn PortableEditableContent.importance
    /// @brief Reconstruct positive importance entries while canonical selections retain explicit zero intent
    /// @param[in] selections Canonical selections; bookmark membership is reconstructed with collections
    /// @param[in] accountID Expected owner
    /// @return Native importance-store entries for positive levels
    /// @throws Unknown ownership, duplicate targets or invalid levels
    func importance(_ selections: [[String: Any]], accountID: String) throws -> [LibraryImportanceItem]
    {

        var seen = Set<String>()
        var output: [LibraryImportanceItem] = []
        for selection in selections
        {
            let value = try owned(selection, kind: "content_selection", accountID: accountID)
            guard Set(value.keys) == ["account_id", "card_id", "bookmarked", "importance"],
                  let cardID = value["card_id"] as? String, seen.insert(cardID).inserted,
                  let level = value["importance"] as? Int, (0...5).contains(level), value["bookmarked"] is Bool,
                  let numericID = numericIDs[cardID] else
            {
                throw Failure.invalid
            }
            let card = try record(cardID, kind: "card")
            guard let listID = (card["payload"] as? [String: Any])?["list_id"] as? String else
            {
                throw Failure.invalid
            }
            let list = try record(listID, kind: "list")
            guard let owner = (list["payload"] as? [String: Any])?["collection_id"] as? String,
                  let ownerID = UUID(uuidString: owner) else
            {
                throw Failure.invalid
            }
            _ = try record(owner, kind: "collection")
            if level > 0
            {
                output.append(LibraryImportanceItem(collectionID: ownerID, cardID: numericID, level: level))
            }
        }
        return output
    }
}


/// Reconstructs Studio preferences and authored artwork order without rewriting per-collection defaults.
/// @section Purpose
///     Preserve the additive appearance model while projecting supported values into current editor types.
extension PortableEditableContent
{

    /// @fcn PortableEditableContent.studioSettings
    /// @brief Rebuild exact saved surfaces, palette order and variety flags
    /// @param[in] document Account-qualified Studio settings or nil
    /// @param[in] accountID Expected owning account
    /// @return Native Studio settings, or nil
    /// @throws Unsupported destinations, file mappings or ownership
    func studioSettings(_ document: [String: Any]?, accountID: String) throws -> StudioSettings?
    {

        guard let document else
        {
            return nil
        }
        let payload = try owned(document, kind: "studio_settings", accountID: accountID)
        var raw = try mapped(payload, fields: ["account_id": "_account", "views": "views", "default_card_surface": "defaultCardSurface",
            "default_note_surface": "defaultNoteSurface", "varies_new_surfaces": "variesNewSurfaces", "varies_new_headers": "variesNewHeaders", "palette": "palette"])
        raw.removeValue(forKey: "_account")
        var views: [String: Any] = [:]
        let destinations = ["today": "Today", "week": "Week", "plans": "Plans", "activity": "Activity",
            "calendar": "Calendar", "search": "Search", "settings": "Settings"]
        for view in try array(payload["views"])
        {
            guard Set(view.keys) == ["destination", "surface"], let key = view["destination"] as? String,
                  let name = destinations[key], views[name] == nil else
            {
                throw Failure.invalid
            }
            views[name] = try appearance(view["surface"], kind: "surface")
        }
        raw["views"] = views
        raw["defaultCardSurface"] = try appearance(payload["default_card_surface"], kind: "surface")
        raw["defaultNoteSurface"] = try appearance(payload["default_note_surface"], kind: "surface")
        return try JSONDecoder().decode(StudioSettings.self, from: JSONSerialization.data(withJSONObject: raw))
    }


    /// @fcn PortableEditableContent.artwork
    /// @brief Rebuild reusable looks in their explicit Model 1.1 authored order
    /// @param[in] library Optional canonical artwork-library metadata
    /// @return Ordered native saved looks, or nil when the source library was absent
    /// @throws Missing library, incorrect membership or unsupported look values
    func artwork(_ library: [String: Any]?) throws -> [StudioArtwork]?
    {

        let all = records.filter { $0["record_type"] as? String == "studio_artwork" }
        guard let library else
        {
            guard all.isEmpty else
            {
                throw Failure.invalid
            }
            return nil
        }
        guard library["record_type"] as? String == "artwork_library", library["user_data_model_version"] as? String == "1.1",
              library["workspace_id"] as? String == records.first?["workspace_id"] as? String,
              let body = library["payload"] as? [String: Any], Set(body.keys) == ["artwork_ids"],
              let ids = body["artwork_ids"] as? [String], Set(ids).count == ids.count,
              Set(ids) == Set(all.compactMap { $0["id"] as? String }) else
        {
            throw Failure.invalid
        }
        return try ids.map { id in
            let document = try record(id, kind: "studio_artwork")
            guard let payload = document["payload"] as? [String: Any] else
            {
                throw Failure.invalid
            }
            var raw = try mapped(payload, fields: ["name": "name", "surface": "surface", "header": "header",
                "italic_subtitle": "italicSubtitle", "title_color": "titleColor", "text_color": "textColor"])
            raw["id"] = id
            raw["surface"] = try appearance(payload["surface"], kind: "surface")
            return try JSONDecoder().decode(StudioArtwork.self, from: JSONSerialization.data(withJSONObject: raw))
        }
    }


    /// @fcn PortableEditableContent.weekAppearance
    /// @brief Retain the global Week default independently of every Collection override
    /// @param[in] document Optional Model 1.1 workspace appearance
    /// @return Native global defaults, or nil when not saved
    /// @throws Version, workspace, payload or appearance failures
    func weekAppearance(_ document: [String: Any]?) throws -> BoardAppearance?
    {

        guard let document else
        {
            return nil
        }
        guard document["record_type"] as? String == "workspace_appearance", document["user_data_model_version"] as? String == "1.1",
              document["workspace_id"] as? String == records.first?["workspace_id"] as? String,
              let payload = document["payload"] as? [String: Any], Set(payload.keys) == ["week_board_defaults"] else
        {
            throw Failure.invalid
        }
        let raw = try appearance(payload["week_board_defaults"], kind: "board_appearance")
        return try JSONDecoder().decode(BoardAppearance.self, from: JSONSerialization.data(withJSONObject: raw))
    }
}
