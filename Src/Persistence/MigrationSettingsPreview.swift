// --------------------------------------------------------------------------------------------------
// @file       MigrationSettingsPreview.swift
// @brief      Explicit profile/preferences preparation and owner-qualified Today shortcut conversion
// @details    Supported User Data Model versions: 1.0. Local settings-preview format 1. Profile
//             and preferences remain account-unbound; no authentication identity is manufactured.
// --------------------------------------------------------------------------------------------------
import CoreFoundation
import Foundation


/// Prepares saved settings while keeping local profile identity separate from authenticated ownership.
/// @section Purpose
///     Preserve effective preference precedence and exact source provenance without hiding defaults.
@MainActor
enum MigrationSettingsPreview
{

    static let fields: [String: String] = [
        "defaultListID": "default_list_id", "usesReducedContent": "uses_reduced_content",
        "scrollsOverflowingTitles": "scrolls_overflowing_titles", "importanceStarStyle": "importance_star_style",
        "enablesLowerCornerBack": "enables_lower_corner_back", "usesLargeControls": "uses_large_controls",
        "randomizesNewCardHeaders": "randomizes_new_card_headers", "randomizesNewCardBackgrounds": "randomizes_new_card_backgrounds",
        "showsDueDatesOnNewCards": "shows_due_dates_on_new_cards", "preferredMapsApp": "preferred_maps_app",
        "keepsDayListsInTimeOrder": "keeps_day_lists_in_time_order", "todayFocusOrder": "today_focus_order",
        "todayFocusGroupsBySection": "today_focus_groups_by_section", "todayFocusIncludesUpNext": "today_focus_includes_up_next",
        "todayFocusIncludesImportant": "today_focus_includes_important", "todayFocusIncludesBookmarked": "today_focus_includes_bookmarked",
        "todayFocusHidesCompleted": "today_focus_hides_completed", "todayFocusItemCount": "today_focus_item_count",
        "showsNavigationLabels": "shows_navigation_labels"
    ]


    /// Canonical shortcuts and local account-unbound settings evidence remain separately counted.
    /// @section Purpose
    ///     Link profile avatar originals without disguising a local draft as a canonical user record.
    struct Result
    {

        let document:       [String: Any]
        let records:        [[String: Any]]
        let assetRecords:   [[String: Any]]
        let preparedCount:  Int
        let shortcutCount:  Int
        let issueCount:     Int
    }


    /// @fcn MigrationSettingsPreview.object
    /// @brief Read an actual saved object and reject keys unsupported by the reviewed adapter
    /// @param[in] value Frozen JSON Data property-list value
    /// @param[in] allowed Reviewed source field names
    /// @return Parsed exact source object
    /// @throws Wrong storage types, malformed JSON or unknown field errors
    private static func object(_ value: Any, allowed: Set<String>) throws -> [String: Any]
    {

        guard let data = value as? Data,
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys).isSubset(of: allowed) else
        {
            throw MigrationContentValues.Failure.invalid("settings_source_fields")
        }
        return raw
    }


    /// @fcn MigrationSettingsPreview.preferences
    /// @brief Decode compatible native preferences without accepting constructor range normalization
    /// @param[in] raw Original preferences and explicitly absent/null fields
    /// @return Native effective preferences after documented compatibility defaults
    /// @throws Invalid field types, source keys, enum tokens or out-of-range row counts
    private static func preferences(_ raw: [String: Any]) throws -> LocalProfilePreferences
    {

        guard Set(raw.keys).isSubset(of: Set(fields.keys)) else
        {
            throw MigrationContentValues.Failure.invalid("settings_preference_fields")
        }
        if let value = raw["todayFocusItemCount"], !(value is NSNull)
        {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.rounded() == number.doubleValue, (0...12).contains(number.intValue) else
            {
                throw MigrationContentValues.Failure.invalid("settings_focus_count")
            }
        }
        return try JSONDecoder().decode(LocalProfilePreferences.self,
            from: JSONSerialization.data(withJSONObject: raw))
    }


    /// @fcn MigrationSettingsPreview.list
    /// @brief Resolve an original numeric List only under the explicit live source owner
    /// @param[in] owner Original Collection UUID string
    /// @param[in] id Original List integer
    /// @param[in] journal Existing identity mappings
    /// @param[in] records Actual converted records proving parent/child membership
    /// @return Existing canonical Collection/List pair, or nil for unresolved evidence
    private static func list(owner: String, id: Int, journal: MigrationIdentityJournal,
        records: [[String: Any]]) -> (String, String)?
    {

        let collection = journal.entries.first {
            $0.source.recordType == "collection" && $0.source.owner == "source_collections" && $0.source.legacyID == owner
        }?.target.uuidString.lowercased()
        let list = journal.entries.first {
            $0.source.recordType == "list" && $0.source.owner == owner && $0.source.legacyID == String(id)
        }?.target.uuidString.lowercased()
        guard let collection, let list,
              records.contains(where: { record in
                  record["record_type"] as? String == "collection" && record["id"] as? String == collection &&
                      ((record["payload"] as? [String: Any])?["list_ids"] as? [String])?.contains(list) == true
              }),
              records.contains(where: { record in
                  record["record_type"] as? String == "list" && record["id"] as? String == list &&
                      (record["payload"] as? [String: Any])?["collection_id"] as? String == collection
              }) else
        {
            return nil
        }
        return (collection, list)
    }


    /// @fcn MigrationSettingsPreview.prepare
    /// @brief Convert saved shortcuts and prepare effective preferences/profile with explicit provenance
    /// @details Caller publishes this settings slice and journal atomically, or reports its blocker.
    /// @param[in] values Frozen preference values
    /// @param[in] records Existing canonical content records
    /// @param[in] mediaDigests Verified original-file digest mapping
    /// @param[in,out] journal Candidate migration identity mappings
    /// @return Local settings evidence, canonical shortcuts and avatar-file references
    /// @throws Invalid source, unsafe avatar paths or broken shortcut membership
    static func prepare(values: [String: Any], records: [[String: Any]], mediaDigests: [String: String],
        journal: inout MigrationIdentityJournal) throws -> Result
    {

        let context = MigrationContentValues(journal: journal, timeZoneID: "Etc/UTC", mediaDigests: mediaDigests)
        var profile: LocalProfile?
        var rawProfile: [String: Any] = [:]
        var profilePreferences: [String: Any] = [:]
        if let value = values["Plenact.LocalProfile.v1"]
        {
            rawProfile = try object(value, allowed: ["id", "createdAt", "displayName", "email", "context",
                "avatarColor", "avatarIcon", "avatarForegroundColor", "avatarPhotoFileName", "preferences"])
            guard let saved = rawProfile["preferences"] as? [String: Any] else
            {
                throw MigrationContentValues.Failure.invalid("settings_profile_preferences")
            }
            profilePreferences = saved
            _ = try preferences(saved)
            for key in ["avatarColor", "avatarForegroundColor"]
            {
                if let color = rawProfile[key], !(color is NSNull)
                {
                    try MigrationContentGuard.check(color, type: "ProfileColor")
                }
            }
            profile = try JSONDecoder().decode(LocalProfile.self, from: value as! Data)
        }
        let rawPreferences: [String: Any]
        let origin: String
        if let value = values["Plenact.PlanPreferences.v1"]
        {
            rawPreferences = try object(value, allowed: Set(fields.keys))
            origin = "saved_planning_preferences"
        }
        else if profile != nil
        {
            rawPreferences = profilePreferences
            origin = "saved_profile_preferences"
        }
        else
        {
            rawPreferences = [:]
            origin = "application_defaults"
        }
        let effective = try preferences(rawPreferences)
        let encoded = try MigrationContentValues.object(effective)
        var mapped: [String: Any] = [:]
        for (source, target) in fields
        {
            mapped[target] = encoded[source] ?? NSNull()
        }
        mapped["today_focus_order"] = effective.todayFocusOrder == .dayList ? "day_list" : "chronological"
        var issues: [String] = []
        var unresolvedDefault: Any = NSNull()
        mapped["default_list_id"] = NSNull()
        if let sourceList = effective.defaultListID
        {
            var owner: String?
            if let data = values["Plenact.CalendarWeeks.v1"] as? Data
            {
                let calendar = try JSONDecoder().decode(PlanningCalendarDocument.self, from: data)
                owner = calendar.weeks.first(where: { $0.startKey == calendar.currentWeekKey })?.collection.id.uuidString.lowercased()
            }
            if let owner, let target = list(owner: owner, id: sourceList, journal: context.journal, records: records)
            {
                mapped["default_list_id"] = target.1
            }
            else
            {
                issues.append("default_list_owner_requires_review")
                unresolvedDefault = sourceList
            }
        }
        let preferencesID = try context.id("user_preferences", owner: "workspace_metadata", legacy: "effective_user_preferences")
        let preferencesDraft: [String: Any] = ["id": preferencesID, "payload": ["preferences": mapped]]
        var profileDraft: Any = NSNull()
        var assetRecords: [[String: Any]] = []
        if let profile
        {
            let raw = try MigrationContentValues.object(profile)
            let id = try context.id("user_profile", owner: "local_profile", legacy: profile.id.uuidString.lowercased())
            let avatar = try context.asset(profile.avatarPhotoFileName, area: "Documents/ProfileAvatars")
            let payload: [String: Any] = ["source_profile_id": profile.id.uuidString.lowercased(),
                "source_created_at_utc": try context.utc(raw["createdAt"]!, path: id + "/profile-created"),
                "display_name": profile.displayName, "email": profile.email, "context": profile.context,
                "avatar_color": try context.appearance(raw["avatarColor"], kind: "color"),
                "avatar_icon": profile.avatarIcon.rawValue,
                "avatar_foreground_color": try context.appearance(raw["avatarForegroundColor"], kind: "color"),
                "avatar_asset_id": avatar]
            profileDraft = ["id": id, "payload": payload]
            assetRecords.append(["record_type": "user_profile_preview", "id": id, "payload": payload])
        }
        var converted: [[String: Any]] = []
        var shortcutCount = 0
        if let value = values["Plenact.TodayListShortcuts.v1"]
        {
            guard let data = value as? Data,
                  let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], raw.count <= 6,
                  raw.allSatisfy({ Set($0.keys) == ["ownerID", "listID"] }) else
            {
                throw MigrationContentValues.Failure.invalid("settings_shortcut_fields")
            }
            let pins = try JSONDecoder().decode([WorkspaceListReference].self, from: data)
            guard Set(pins).count == pins.count else
            {
                throw MigrationContentValues.Failure.invalid("settings_duplicate_shortcuts")
            }
            var items: [[String: Any]] = []
            for pin in pins
            {
                guard let target = list(owner: pin.ownerID.uuidString.lowercased(), id: pin.listID,
                    journal: context.journal, records: records) else
                {
                    throw MigrationContentValues.Failure.invalid("settings_shortcut_owner_requires_review")
                }
                items.append(["collection_id": target.0, "list_id": target.1])
            }
            let id = try context.id("today_shortcuts", owner: "workspace_metadata", legacy: "Plenact.TodayListShortcuts.v1")
            converted.append(context.document("today_shortcuts", id: id, payload: ["items": items]))
            shortcutCount = items.count
        }
        converted += context.unavailable.keys.sorted().map { context.unavailable[$0]! }
        let defaultedPreferences = fields.keys.filter { rawPreferences[$0] == nil || rawPreferences[$0] is NSNull }.sorted()
        let defaultedProfile = profile == nil ? [] : ["avatarIcon", "avatarForegroundColor"].filter {
            rawProfile[$0] == nil || rawProfile[$0] is NSNull
        }
        let document: [String: Any] = ["format": "plenact.ios-settings-preview", "format_version": 1,
            "target_user_data_model_version": "1.0", "account_binding_pending": true,
            "profile": profileDraft, "preferences": preferencesDraft, "preferences_origin": origin,
            "defaulted_preference_fields": defaultedPreferences, "defaulted_profile_fields": defaultedProfile,
            "profile_preferences_shadowed": values["Plenact.PlanPreferences.v1"] != nil && profile != nil,
            "unresolved_default_list_id": unresolvedDefault, "source_precision": context.precisionEvidence,
            "issues": issues, "ready_for_binding": issues.isEmpty]
        journal = context.journal
        return Result(document: document, records: converted, assetRecords: assetRecords,
            preparedCount: profile == nil ? 1 : 2, shortcutCount: shortcutCount, issueCount: issues.count)
    }
}
