// --------------------------------------------------------------------------------------------------
// @file       MigrationContentGuard.swift
// @brief      Source-shape audit before any native decoder can normalize or discard fields
// @details    Supported User Data Model versions: 1.0. Partial, local-only migration preview.
//             Original source bytes remain preserved; no cloud ownership or synchronization is implied.
// --------------------------------------------------------------------------------------------------
import CoreFoundation
import Foundation


/// Rejects unsupported stored fields while retaining compatible legacy omissions.
/// @section Purpose
///     Keep the native migration adapter from silently flattening future source payloads.
enum MigrationContentGuard
{

    static let fields: [String: Set<String>] = [
        "KanbanCard": ["id", "editHistory", "word", "listTitle", "isDivider", "isTitleChecked", "editingLocked", "members", "labelIDs", "startDate", "location", "dueDate", "createdAt", "descriptionOverride", "startDateKind", "dueDateKind", "showsDueDateInList", "sectionLayout", "subtitleOverride", "checklists", "showsReactionsInPreviews", "reactions", "comments", "attachments", "coverAttachmentID", "appearance", "dismissedActivityIDs", "listDisplayFormat", "itemPresentation"],
        "KanbanList": ["id", "title", "subtitleOverride", "cards", "archivedCards", "isArchived", "appearance", "defaultItemPresentation"],
        "PersonalCollection": ["id", "title", "kind", "icon", "color", "lists", "savedCardIDs", "isArchived", "boardAppearance", "collectionDescription"],
        "PlanningCalendarDocument": ["version", "currentWeekKey", "firstWeekday", "weeks", "checklistLinkWeeks"],
        "DatedPlanningWeek": ["startKey", "collection", "dayListIDs", "explicitlySaved"],
        "PlanningRoutineLibrary": ["version", "templates", "defaultWeekID", "bundledRoutineRevision"],
        "PlanningRoutineTemplate": ["id", "name", "kind", "anchorKey", "timeZoneID", "firstWeekday", "collection", "weekdays", "exampleFocus"],
        "PlanningExampleFocus": ["important", "bookmarked", "allDay"],
        "KanbanChecklist": ["id", "title", "items", "completedItemIndices"],
        "KanbanChecklistItem": ["id", "title", "isCompleted", "content", "retainedDetail", "retainedCardID", "retainedURL", "linkedCollectionID"],
        "KanbanChecklistActionDetail": ["id", "description", "checklists", "comments"],
        "CardAssignee": ["id", "kind", "userID", "displayName"],
        "KanbanComment": ["id", "author", "body", "createdAt"],
        "ItemEmojiReaction": ["id", "emoji", "authorID", "createdAt"],
        "KanbanAttachment": ["id", "fileName", "url", "mediaKind", "addedAt", "exampleImage", "drawingFileName", "caption"],
        "CardSectionLayout": ["order", "hidden"],
        "CardEditRecord": ["id", "timestamp", "changes"],
        "CardEditChange": ["field", "previousValue", "newValue"],
        "ItemAppearance": ["accent", "icon", "background", "listBackground", "cardBackground", "cardTitleColor", "cardTextColor", "addItemTextColor", "sectionCollapsed", "hideEmptySubtitle", "studioSurface", "studioCardSurface", "subtitleItalic", "cardDetail", "listViewMode", "iconColor", "showsIconInHeader", "listBackgroundOpacity"],
        "BoardAppearance": ["bannerBackground", "listBackground", "cardBackground", "cardDetail", "collectionBackground", "cardTitleColor", "cardTextColor", "addItemTextColor", "studioSurface", "studioCardSurface", "subtitleItalic"],
        "StudioSurface": ["material", "color", "secondaryColor", "strength", "readability", "verticalPosition", "zoom", "showsInPreviews", "photoFileName", "remotePhoto"],
        "StudioRemotePhoto": ["id", "imageURL", "photographer", "profileURL", "downloadURL"],
        "CollectionBackground": ["preset", "photoFileName"],
        "ProfileColor": ["red", "green", "blue"]
    ]


    /// @fcn MigrationContentGuard.richText
    /// @brief Retain supported rich text, treating malformed prefixes literally and blocking unknown runs
    /// @param[in] value Original source string
    /// @return Void without changing the string
    /// @throws Unsupported decoded run structure/attributes
    @MainActor
    static func richText(_ value: String) throws
    {

        let prefix = "plenact-rich-v1:"
        guard value.hasPrefix(prefix), let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
              let decoded = try? JSONSerialization.jsonObject(with: data) else
        {
            return
        }
        guard let runs = decoded as? [[String: Any]] else
        {
            throw MigrationContentValues.Failure.invalid("unsupported_rich_text")
        }
        for run in runs
        {
            guard Set(run.keys).isSubset(of: ["text", "bold", "italic", "color", "fontName", "fontSize"]),
                  run["text"] is String else
            {
                throw MigrationContentValues.Failure.invalid("unsupported_rich_text")
            }
            for key in ["bold", "italic"]
            {
                guard let value = run[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else
                {
                    throw MigrationContentValues.Failure.invalid("unsupported_rich_text")
                }
            }
            for key in ["color", "fontName"]
            {
                if let value = run[key], !(value is NSNull), !(value is String)
                {
                    throw MigrationContentValues.Failure.invalid("unsupported_rich_text")
                }
            }
            if let value = run["fontSize"], !(value is NSNull)
            {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue > 0, number.doubleValue <= 512 else
                {
                    throw MigrationContentValues.Failure.invalid("unsupported_rich_text")
                }
            }
        }
    }


    /// @fcn MigrationContentGuard.comparable
    /// @brief Compare source projection values while accounting only for actual set ordering
    /// @param[in] value Saved JSON value
    /// @param[in] key Source field name
    /// @return JSON value with unordered source sets sorted deterministically
    /// @throws JSON serialization errors
    static func comparable(_ value: Any, key: String = "") throws -> Any
    {

        if let object = value as? [String: Any]
        {
            return Dictionary(uniqueKeysWithValues: try object.map { ($0.key, try comparable($0.value, key: $0.key)) })
        }
        if let array = value as? [Any]
        {
            let normalized = try array.map { try comparable($0) }
            if ["dismissedActivityIDs", "hidden", "savedCardIDs", "completedItemIndices", "important", "bookmarked", "allDay"].contains(key)
            {
                return try normalized.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) }
                    .sorted { $0.lexicographicallyPrecedes($1) }.map { try JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
            }
            return normalized
        }
        return value
    }


    /// @fcn MigrationContentGuard.check
    /// @brief Recursively classify actual saved fields before native decoding
    /// @param[in] value Original source value
    /// @param[in] type Explicit source family
    /// @return Void after shape verification
    /// @throws Unknown keys, malformed containers or dropped duplicate-set evidence
    @MainActor
    static func check(_ value: Any, type: String) throws
    {

        if type == "CardAssignee", value is String
        {
            throw MigrationContentValues.Failure.invalid("legacy_manual_assignee_identity_required")
        }
        if (type == "KanbanChecklistItem" || type == "ProfileColor"), value is String
        {
            return
        }
        guard let object = value as? [String: Any] else
        {
            throw MigrationContentValues.Failure.invalid("source_" + type)
        }
        if type == "KanbanCard", !(object["checklists"] is [Any])
        {
            throw MigrationContentValues.Failure.invalid("missing_source_checklists_would_seed_examples")
        }
        if type == "KanbanChecklistItem", let content = object["content"] as? [String: Any]
        {
            for (active, retained) in [("detail", "retainedDetail"), ("cardID", "retainedCardID"), ("url", "retainedURL")]
            {
                if let original = content[active], let mirror = object[retained], !(mirror is NSNull)
                {
                    let left = try JSONSerialization.data(withJSONObject: original, options: [.fragmentsAllowed, .sortedKeys])
                    let right = try JSONSerialization.data(withJSONObject: mirror, options: [.fragmentsAllowed, .sortedKeys])
                    guard left == right else
                    {
                        throw MigrationContentValues.Failure.invalid("divergent_retained_source")
                    }
                }
            }
        }
        if type == "KanbanChecklist", let indices = object["completedItemIndices"] as? [Int], let items = object["items"] as? [Any],
           indices.contains(where: { !items.indices.contains($0) })
        {
            throw MigrationContentValues.Failure.invalid("legacy_completion_index")
        }
        if type == "ProfileColor"
        {
            for key in ["red", "green", "blue"]
            {
                guard let number = object[key] as? NSNumber, number.doubleValue.isFinite,
                      (0...1).contains(number.doubleValue) else
                {
                    throw MigrationContentValues.Failure.invalid("source_color_range")
                }
            }
        }
        for key in ["descriptionOverride", "description", "body"]
        {
            if let text = object[key] as? String
            {
                try richText(text)
            }
        }
        let accepted: Set<String>
        if type == "action_content"
        {
            accepted = ["kind", "cardID", "detail", "url"]
        }
        else
        {
            accepted = fields[type] ?? []
        }
        guard Set(object.keys).isSubset(of: accepted) else
        {
            throw MigrationContentValues.Failure.unsupportedField(type)
        }
        let children: [String: String] = ["collections": "PersonalCollection", "collection": "PersonalCollection",
            "weeks": "DatedPlanningWeek", "templates": "PlanningRoutineTemplate", "exampleFocus": "PlanningExampleFocus",
            "lists": "KanbanList", "cards": "KanbanCard", "archivedCards": "KanbanCard", "checklists": "KanbanChecklist",
            "items": "KanbanChecklistItem", "content": "action_content", "detail": "KanbanChecklistActionDetail",
            "retainedDetail": "KanbanChecklistActionDetail", "members": "CardAssignee", "comments": "KanbanComment",
            "reactions": "ItemEmojiReaction", "attachments": "KanbanAttachment", "sectionLayout": "CardSectionLayout",
            "editHistory": "CardEditRecord", "changes": "CardEditChange", "boardAppearance": "BoardAppearance",
            "collectionBackground": "CollectionBackground", "studioSurface": "StudioSurface", "studioCardSurface": "StudioSurface",
            "remotePhoto": "StudioRemotePhoto", "iconColor": "ProfileColor", "addItemTextColor": "ProfileColor"]
        for (key, child) in object where !(child is NSNull)
        {
            var childType = children[key]
            if key == "appearance"
            {
                childType = "ItemAppearance"
            }
            if key == "color", type == "PersonalCollection"
            {
                childType = "ProfileColor"
            }
            if let childType
            {
                if let array = child as? [Any]
                {
                    for item in array
                    {
                        try check(item, type: childType)
                    }
                }
                else
                {
                    try check(child, type: childType)
                }
            }
            if ["dismissedActivityIDs", "hidden", "order", "completedItemIndices", "savedCardIDs", "important", "bookmarked", "allDay"].contains(key), let array = child as? [Any]
            {
                let encoded = try array.map { try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys]) }
                guard Set(encoded).count == array.count else
                {
                    throw MigrationContentValues.Failure.invalid("duplicate_source_set")
                }
            }
        }
    }
}
