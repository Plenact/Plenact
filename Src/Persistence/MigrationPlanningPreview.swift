// --------------------------------------------------------------------------------------------------
// @file       MigrationPlanningPreview.swift
// @brief      Daily plans, historical check-ins, reviews and reminder-intent conversion
// @details    Supported User Data Model versions: 1.0. Local migration preview only. Historical
//             snapshots remain authored values; review decisions and OS notifications are never run.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Converts actual saved planning history without replacing it with current workspace values.
/// @section Purpose
///     Retain reflection writing, progress snapshots and owner/creation-qualified references.
@MainActor
enum MigrationPlanningPreview
{

    static let stores = ["Plenact.DailyPlans.v1", "Plenact.WeeklyReviews.v1", "Plenact.PeriodicReviews.v1", "Plenact.ReviewRhythm.v1"]
    static let fields: [String: Set<String>] = [
        "daily": ["id", "timeZoneID", "intention", "constraints", "concerns", "priorities", "updatedAt", "checkIn", "checkIns", "eveningReview", "visionStep", "visionCompletedAt"],
        "weekly": ["id", "startKey", "timeZoneID", "firstWeekday", "step", "highlights", "learned", "direction", "constraints", "risks", "priorities", "decisions", "updatedAt", "completedAt"],
        "periodic": ["id", "title", "startKey", "endKey", "timeZoneID", "step", "highlights", "learned", "direction", "risks", "startingObjectives", "objectives", "priorities", "updatedAt", "completedAt"],
        "priority": ["ownerID", "cardID", "title", "location", "sourceCreatedAt"],
        "checkIn": ["focus", "changed", "savedAt"],
        "checkIns": ["id", "savedAt", "changed", "focus", "intention", "constraints", "concerns", "priorities", "completedTasks", "totalTasks", "notes", "unavailable", "legacy", "mood"],
        "mood": ["emoji", "label"],
        "eveningReview": ["step", "completedAt", "helped", "difficult", "tomorrow", "decisions", "achievements"],
        "decision": ["id", "source", "result", "action", "recordedAt"],
        "objective": ["id", "title", "status", "progress", "nextStep"],
        "rhythm": ["dailyInvitations", "weeklyInvitations", "dailyMinutes", "weeklyMinutes", "weeklyWeekday", "dailyNotifications", "weeklyNotifications"]]


    /// Canonical history records and explicit local source/precision evidence.
    /// @section Purpose
    ///     Count converted source domains independently from complete workspace acceptance.
    struct Result
    {

        let records:        [[String: Any]]
        let document:       [String: Any]
        let convertedStores: [String]
        let recordCount:    Int
        let unresolvedCount: Int
    }


    /// @fcn MigrationPlanningPreview.check
    /// @brief Reject unknown raw fields recursively before native decoders can discard them
    /// @param[in] value Saved object or authored array
    /// @param[in] type Reviewed source family
    /// @return Void for a supported raw shape
    /// @throws Malformed or unsupported field errors
    private static func check(_ value: Any, type: String) throws
    {

        if let array = value as? [Any]
        {
            for item in array
            {
                try check(item, type: type)
            }
            return
        }
        guard let raw = value as? [String: Any], let allowed = fields[type], Set(raw.keys).isSubset(of: allowed) else
        {
            throw MigrationContentValues.Failure.invalid("planning_source_fields:" + type)
        }
        let children = ["priorities": "priority", "focus": "priority", "source": "priority", "result": "priority",
            "checkIn": "checkIn", "checkIns": "checkIns", "eveningReview": "eveningReview", "mood": "mood",
            "decisions": "decision", "achievements": "priority", "startingObjectives": "objective", "objectives": "objective"]
        for (key, child) in raw where !(child is NSNull)
        {
            if let family = children[key]
            {
                try check(child, type: family)
            }
        }
        if let action = raw["action"]
        {
            guard let object = action as? [String: Any], object.count == 1, let kind = object.keys.first,
                  ["keep", "keepTomorrow", "table", "complete", "archive", "queue", "tomorrow", "date"].contains(kind),
                  let argument = object[kind] as? [String: Any],
                  Set(argument.keys) == (kind == "date" ? ["_0"] : []) else
            {
                throw MigrationContentValues.Failure.invalid("planning_action_fields")
            }
        }
    }


    /// @fcn MigrationPlanningPreview.load
    /// @brief Verify a versioned native document while retaining original reference-epoch timestamp bits
    /// @param[in] value Frozen source Data
    /// @param[in] type Actual native Codable document type
    /// @param[in] family Reviewed record family
    /// @param[in] container Source dictionary name or nil for rhythm preferences
    /// @return Exact source object with native Date reference-epoch values, without persistence loaders
    /// @throws Invalid version, fields or native source decoding errors
    private static func load<T: Codable>(_ value: Any, as type: T.Type, family: String, container: String?) throws -> [String: Any]
    {

        guard let data = value as? Data, let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            throw MigrationContentValues.Failure.invalid("planning_source_storage")
        }
        if let container
        {
            guard Set(raw.keys) == ["version", container], raw["version"] as? Int == 1,
                  let entries = raw[container] as? [String: Any] else
            {
                throw MigrationContentValues.Failure.invalid("planning_source_version_or_container")
            }
            for entry in entries.values
            {
                try check(entry, type: family)
            }
        }
        else
        {
            try check(raw, type: family)
        }
        _ = try JSONDecoder().decode(type, from: data)
        return raw
    }


    /// @fcn MigrationPlanningPreview.prepare
    /// @brief Convert only saved planning domains with stable identities and explicit historical references
    /// @param[in] values Frozen property-list stores
    /// @param[in] records Existing canonical content and unavailable evidence
    /// @param[in,out] journal Candidate source identity mapping, published atomically by the caller
    /// @param[in] priorityResolver Optional verified export-only historical reference resolver
    /// @return Canonical planning records and local precision/store-presence report
    /// @throws Invalid histories, source keys, civil dates, ranges or reference provenance
    static func prepare(values: [String: Any], records: [[String: Any]], journal: inout MigrationIdentityJournal,
        priorityResolver: (([String: Any]) throws -> [String: Any])? = nil) throws -> Result
    {

        let context = MigrationContentValues(journal: journal, timeZoneID: "Etc/UTC", mediaDigests: [:])
        context.known = Set(records.compactMap { $0["id"] as? String })
        for record in records where record["record_type"] as? String == "unavailable_reference"
        {
            if let target = (record["payload"] as? [String: Any])?["target_id"] as? String
            {
                context.known.insert(target)
            }
        }
        let mapper = MigrationPlanningValues(context: context, priorityResolver: priorityResolver)
        var output: [[String: Any]] = []
        var converted: [String] = []
        if let value = values[stores[0]]
        {
            let document = try load(value, as: DailyPlanStore.Document.self, family: "daily", container: "plans")
            let plans = document["plans"] as! [String: Any]
            for key in plans.keys.sorted()
            {
                let source = plans[key] as! [String: Any]
                guard source["id"] as? String == key else
                {
                    throw MigrationContentValues.Failure.invalid("planning_daily_key")
                }
                try mapper.dateAndZone(key, zone: source["timeZoneID"] as! String)
                let id = try context.id("daily_plan", owner: stores[0], legacy: key, discriminator: source["timeZoneID"] as? String)
                var payload: [String: Any] = ["date": key, "time_zone": source["timeZoneID"]!,
                    "intention": source["intention"]!, "constraints": source["constraints"]!, "concerns": source["concerns"]!,
                    "priorities": try mapper.priorities(source["priorities"]!),
                    "updated_at_utc": try mapper.timestamp(source["updatedAt"], path: id + "/updated"),
                    "vision_completed_at_utc": try mapper.timestamp(source["visionCompletedAt"], path: id + "/vision"),
                    "vision_step": try mapper.step(source["visionStep"], optional: true)]
                payload["check_in"] = try (source["checkIn"] as? [String: Any]).map { try mapper.checkIn($0, path: id) } as Any? ?? NSNull()
                payload["check_ins"] = try (source["checkIns"] as? [[String: Any]]).map { try mapper.entries($0, path: id) } as Any? ?? NSNull()
                payload["evening_review"] = try (source["eveningReview"] as? [String: Any]).map { try mapper.evening($0, path: id) } as Any? ?? NSNull()
                output.append(context.document("daily_plan", id: id, payload: payload))
            }
            converted.append(stores[0])
        }
        if let value = values[stores[1]]
        {
            let document = try load(value, as: WeeklyReviewStore.Document.self, family: "weekly", container: "records")
            let entries = document["records"] as! [String: Any]
            for key in entries.keys.sorted()
            {
                let source = entries[key] as! [String: Any]
                let date = source["startKey"] as! String
                let zone = source["timeZoneID"] as! String
                let weekday = source["firstWeekday"] as! Int
                try mapper.dateAndZone(date, zone: zone)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                guard source["id"] as? String == key, key == date + "|" + zone + "|" + String(weekday),
                      (1...7).contains(weekday), calendar.component(.weekday, from: try MigrationCalendarTemplates.date(date)) == weekday else
                {
                    throw MigrationContentValues.Failure.invalid("planning_weekly_key_or_start")
                }
                let id = try context.id("weekly_review", owner: stores[1], legacy: key)
                var payload = try mapper.review(source, path: id)
                payload["source_review_key"] = key
                payload["start_date"] = date
                payload["time_zone"] = zone
                payload["first_weekday"] = weekday
                payload["constraints"] = source["constraints"]!
                payload["decisions"] = try mapper.decisions(source["decisions"]!, path: id)
                output.append(context.document("weekly_review", id: id, payload: payload))
            }
            converted.append(stores[1])
        }
        if let value = values[stores[2]]
        {
            let document = try load(value, as: PeriodicReviewStore.Document.self, family: "periodic", container: "records")
            let entries = document["records"] as! [String: Any]
            for key in entries.keys.sorted()
            {
                let source = entries[key] as! [String: Any]
                let original = try MigrationContentValues.lowerUUID(source["id"])
                guard let uuid = UUID(uuidString: key), uuid.uuidString == key, original == key.lowercased(),
                      let title = source["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let start = source["startKey"] as? String, let end = source["endKey"] as? String, start <= end else
                {
                    throw MigrationContentValues.Failure.invalid("planning_periodic_key_or_range")
                }
                try mapper.dateAndZone(start, zone: source["timeZoneID"] as! String)
                _ = try MigrationCalendarTemplates.date(end)
                let id = try context.id("periodic_review", owner: stores[2], legacy: original)
                var payload = try mapper.review(source, path: id)
                payload["title"] = title
                payload["start_date"] = start
                payload["end_date"] = end
                payload["time_zone"] = source["timeZoneID"]!
                payload["starting_objectives"] = try mapper.objectives(source["startingObjectives"]!)
                payload["objectives"] = try mapper.objectives(source["objectives"]!)
                output.append(context.document("periodic_review", id: id, payload: payload))
            }
            converted.append(stores[2])
        }
        if let value = values[stores[3]]
        {
            let source = try load(value, as: ReviewRhythmPreferences.self, family: "rhythm", container: nil)
            guard let daily = source["dailyMinutes"] as? Int, let weekly = source["weeklyMinutes"] as? Int,
                  let weekday = source["weeklyWeekday"] as? Int,
                  (0..<1440).contains(daily), (0..<1440).contains(weekly), (1...7).contains(weekday) else
            {
                throw MigrationContentValues.Failure.invalid("planning_rhythm_range")
            }
            let id = try context.id("review_rhythm", owner: "workspace_metadata", legacy: stores[3])
            output.append(context.document("review_rhythm", id: id, payload: [
                "daily_invitations": source["dailyInvitations"]!, "weekly_invitations": source["weeklyInvitations"]!,
                "daily_minutes": daily, "weekly_minutes": weekly, "weekly_weekday": weekday,
                "daily_notifications": source["dailyNotifications"]!, "weekly_notifications": source["weeklyNotifications"]!]))
            converted.append(stores[3])
        }
        let count = output.count
        output += context.unavailable.keys.sorted().map { context.unavailable[$0]! }
        let document: [String: Any] = ["format": "plenact.ios-planning-preview", "format_version": 1,
            "target_user_data_model_version": "1.0", "converted_source_stores": converted,
            "source_store_versions": Dictionary(uniqueKeysWithValues: converted.filter { $0 != stores[3] }.map { ($0, 1) }),
            "planning_record_count": count, "unavailable_reference_count": context.unavailable.count,
            "source_precision": context.precisionEvidence, "review_actions_executed": false,
            "notifications_scheduled": false]
        journal = context.journal
        return Result(records: output, document: document, convertedStores: converted,
            recordCount: count, unresolvedCount: context.unavailable.count)
    }
}
