// --------------------------------------------------------------------------------------------------
// @file       PortableEditablePlanning.swift
// @brief      Reconstruct native planning and review documents from retained portable snapshots
// @details    Supported User Data Model versions: 1.0. Saved writing, progress, decisions and reminders
//             are decoded as data only; no review actions, notifications or persistence operations run.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Holds reconstructed native planning stores without installing or executing them.
/// @section Purpose
///     Keep complete saved history separate from current Card state and runtime workflow actions.
struct PortablePlanningDocuments
{

    let daily:    DailyPlanStore.Document
    let weekly:   WeeklyReviewStore.Document
    let periodic: PeriodicReviewStore.Document
    let rhythm:   ReviewRhythmPreferences?
}


/// Reconstructs historical snapshots independently of current content values.
/// @section Purpose
///     Preserve unavailable references and authored historical text rather than replacing them with live Cards.
extension PortableEditableContent
{

    /// @fcn PortableEditableContent.priority
    /// @brief Restore original historical title/location and canonical owner-qualified aliases
    /// @param[in] value Canonical historical priority
    /// @return Native priority Codable shape
    /// @throws Unsupported fields or undeclared identity targets
    func priority(_ value: [String: Any]) throws -> [String: Any]
    {

        var raw = try mapped(value, fields: ["source_collection_id": "ownerID", "card_id": "cardID",
            "title": "title", "source_location": "location", "source_created_at_utc": "sourceCreatedAt"])
        guard let owner = value["source_collection_id"] as? String, UUID(uuidString: owner) != nil,
              records.contains(where: { record in
                  if record["id"] as? String == owner && record["record_type"] as? String == "collection"
                  {
                      return true
                  }
                  let body = record["payload"] as? [String: Any]
                  return record["record_type"] as? String == "unavailable_reference" &&
                      body?["target_type"] as? String == "collection" && body?["target_id"] as? String == owner
              }) else
        {
            throw Failure.invalid
        }
        if let cardID = value["card_id"] as? String,
           let card = records.first(where: { $0["id"] as? String == cardID && $0["record_type"] as? String == "card" })
        {
            guard let body = card["payload"] as? [String: Any], let listID = body["list_id"] as? String,
                  let list = records.first(where: { $0["id"] as? String == listID && $0["record_type"] as? String == "list" }),
                  (list["payload"] as? [String: Any])?["collection_id"] as? String == owner,
                  body["source_created_at_utc"] as? String == value["source_created_at_utc"] as? String else
            {
                throw Failure.invalid
            }
        }
        raw["cardID"] = try alias(value["card_id"])
        raw["sourceCreatedAt"] = try timestamp(value["source_created_at_utc"])
        return raw
    }


    /// @fcn PortableEditableContent.priorities
    /// @brief Preserve snapshot order and reject duplicate logical priority targets
    /// @param[in] value Canonical priority array
    /// @return Native ordered snapshot dictionaries
    /// @throws Duplicate or invalid references
    func priorities(_ value: Any?) throws -> [[String: Any]]
    {

        var seen = Set<String>()
        return try array(value).map { item in
            guard let owner = item["source_collection_id"] as? String, let card = item["card_id"] as? String,
                  seen.insert(owner + ":" + card).inserted else
            {
                throw Failure.invalid
            }
            return try priority(item)
        }
    }


    /// @fcn PortableEditableContent.decisions
    /// @brief Decode retained review decisions without applying their actions
    /// @param[in] value Canonical decision array
    /// @return Native action-history dictionaries
    /// @throws Unsupported action, malformed dates or duplicate IDs
    func decisions(_ value: Any?) throws -> [[String: Any]]
    {

        var seen = Set<String>()
        return try array(value).map { item in
            var raw = try mapped(item, fields: ["id": "id", "source": "source", "result": "result",
                "action": "action", "recorded_at_utc": "recordedAt"])
            guard let id = item["id"] as? String, UUID(uuidString: id) != nil, seen.insert(id).inserted,
                  let source = item["source"] as? [String: Any], let result = item["result"] as? [String: Any],
                  let action = item["action"] as? [String: Any], let kind = action["kind"] as? String else
            {
                throw Failure.invalid
            }
            raw["source"] = try priority(source)
            raw["result"] = try priority(result)
            raw["recordedAt"] = try timestamp(item["recorded_at_utc"])
            if kind == "date"
            {
                guard Set(action.keys) == ["kind", "date"], let day = action["date"] as? String else
                {
                    throw Failure.invalid
                }
                _ = try civil(day)
                raw["action"] = ["date": ["_0": day]]
            }
            else
            {
                guard Set(action.keys) == ["kind"], ["keep", "keep_tomorrow", "table", "complete", "archive", "queue", "tomorrow"].contains(kind) else
                {
                    throw Failure.unsupported
                }
                raw["action"] = [kind == "keep_tomorrow" ? "keepTomorrow" : kind: [String: Any]()]
            }
            return raw
        }
    }


    /// @fcn PortableEditableContent.optionalPriority
    /// @brief Preserve explicit null without silently discarding malformed focus values
    /// @param[in] value Nullable canonical priority
    /// @return Native snapshot or null
    /// @throws Invalid non-null shape
    func optionalPriority(_ value: Any?) throws -> Any
    {

        if value is NSNull
        {
            return NSNull()
        }
        guard let value = value as? [String: Any] else
        {
            throw Failure.invalid
        }
        return try priority(value)
    }


    /// @fcn PortableEditableContent.checkIn
    /// @brief Restore an actual saved legacy check-in without generating an inferred history entry
    /// @param[in] value Nullable canonical check-in
    /// @return Native check-in or null
    /// @throws Invalid snapshot shape
    func checkIn(_ value: Any?) throws -> Any
    {

        if value is NSNull
        {
            return NSNull()
        }
        guard let value = value as? [String: Any] else
            {
                throw Failure.invalid
            }
        var raw = try mapped(value, fields: ["focus": "focus", "changed": "changed", "saved_at_utc": "savedAt"])
        raw["focus"] = try optionalPriority(value["focus"])
        raw["savedAt"] = try timestamp(value["saved_at_utc"])
        return raw
    }


    /// @fcn PortableEditableContent.checkIns
    /// @brief Retain submitted check-in order, explicit counts, moods and nullable history
    /// @param[in] value Nullable canonical history array
    /// @return Native entries or null
    /// @throws Duplicate IDs, invalid counts or unsupported fields
    func checkIns(_ value: Any?) throws -> Any
    {

        if value is NSNull
        {
            return NSNull()
        }
        var seen = Set<String>()
        return try array(value).map { item -> [String: Any] in
            var raw = try mapped(item, fields: ["id": "id", "saved_at_utc": "savedAt", "changed": "changed", "focus": "focus",
                "intention": "intention", "constraints": "constraints", "concerns": "concerns", "priorities": "priorities",
                "legacy": "legacy", "mood": "mood", "completed_tasks": "completedTasks", "total_tasks": "totalTasks",
                "notes": "notes", "unavailable": "unavailable"])
            guard let id = item["id"] as? String, !id.isEmpty, seen.insert(id).inserted else
            {
                throw Failure.invalid
            }
            raw["focus"] = try optionalPriority(item["focus"])
            raw["priorities"] = try priorities(item["priorities"])
            raw["savedAt"] = try timestamp(item["saved_at_utc"])
            if let mood = item["mood"] as? [String: Any]
            {
                _ = try mapped(mood, fields: ["emoji": "emoji", "label": "label"])
            }
            else if !(item["mood"] is NSNull)
            {
                throw Failure.invalid
            }
            for key in ["completed_tasks", "total_tasks", "notes", "unavailable"]
            {
                guard item[key] is NSNull || (item[key] as? Int).map({ (0...Int(Int32.max)).contains($0) }) == true else
                {
                    throw Failure.invalid
                }
            }
            if let completed = item["completed_tasks"] as? Int, let total = item["total_tasks"] as? Int, completed > total
            {
                throw Failure.invalid
            }
            return raw
        }
    }


    /// @fcn PortableEditableContent.evening
    /// @brief Restore saved evening workflow position, writing, achievements and recorded decisions
    /// @param[in] value Nullable canonical evening review
    /// @return Native review or null
    /// @throws Invalid progress or snapshot values
    func evening(_ value: Any?) throws -> Any
    {

        if value is NSNull
        {
            return NSNull()
        }
        guard let value = value as? [String: Any] else
            {
                throw Failure.invalid
            }
        var raw = try mapped(value, fields: ["step": "step", "completed_at_utc": "completedAt", "helped": "helped",
            "difficult": "difficult", "tomorrow": "tomorrow", "decisions": "decisions", "achievements": "achievements"])
        guard let step = value["step"] as? Int, (0...2).contains(step) else
            {
                throw Failure.invalid
            }
        raw["completedAt"] = try timestamp(value["completed_at_utc"])
        raw["decisions"] = try decisions(value["decisions"])
        raw["achievements"] = try priorities(value["achievements"])
        return raw
    }


    /// @fcn PortableEditableContent.objectives
    /// @brief Preserve independent starting/current objective snapshots and exact authored status
    /// @param[in] value Canonical objective array
    /// @return Native objective dictionaries
    /// @throws Invalid status, duplicate identity or unknown fields
    func objectives(_ value: Any?) throws -> [[String: Any]]
    {

        var seen = Set<String>()
        return try array(value).map { item in
            var raw = try mapped(item, fields: ["id": "id", "title": "title", "status": "status", "progress": "progress", "next_step": "nextStep"])
            guard let id = item["id"] as? String, UUID(uuidString: id) != nil, seen.insert(id).inserted,
                  let token = item["status"] as? String,
                  let status = ["active": "Active", "achieved": "Achieved", "paused": "Paused", "released": "Let go"][token] else
            {
                throw Failure.invalid
            }
            raw["status"] = status
            return raw
        }
    }


    /// @fcn PortableEditableContent.planningDocuments
    /// @brief Reconstruct all saved planning stores without applying review outcomes or scheduling reminders
    /// @return Native document projections and nullable reminder preferences
    /// @throws Unsupported values, duplicate logical store keys or missing historical evidence
    func planningDocuments() throws -> PortablePlanningDocuments
    {

        var daily: [String: Any] = [:]
        var weekly: [String: Any] = [:]
        var periodic: [String: Any] = [:]
        let reflections = ["step": "step", "highlights": "highlights", "learned": "learned", "direction": "direction",
            "risks": "risks", "priorities": "priorities", "updated_at_utc": "updatedAt", "completed_at_utc": "completedAt"]
        for document in records
        {
            guard let kind = document["record_type"] as? String,
                  ["daily_plan", "weekly_review", "periodic_review"].contains(kind) else
            {
                continue
            }
            guard let payload = document["payload"] as? [String: Any] else
            {
                throw Failure.invalid
            }
            if kind == "daily_plan"
            {
                var raw = try mapped(payload, fields: ["date": "id", "time_zone": "timeZoneID", "intention": "intention",
                    "constraints": "constraints", "concerns": "concerns", "priorities": "priorities", "updated_at_utc": "updatedAt",
                    "vision_completed_at_utc": "visionCompletedAt", "vision_step": "visionStep", "check_in": "checkIn",
                    "check_ins": "checkIns", "evening_review": "eveningReview"])
                guard let date = payload["date"] as? String, daily[date] == nil,
                      let zone = payload["time_zone"] as? String, TimeZone(identifier: zone) != nil else
            {
                throw Failure.invalid
            }
                _ = try civil(date)
                guard payload["vision_step"] is NSNull || (payload["vision_step"] as? Int).map({ (0...2).contains($0) }) == true else
            {
                throw Failure.invalid
            }
                raw["priorities"] = try priorities(payload["priorities"])
                raw["updatedAt"] = try timestamp(payload["updated_at_utc"])
                raw["visionCompletedAt"] = try timestamp(payload["vision_completed_at_utc"])
                raw["checkIn"] = try checkIn(payload["check_in"])
                raw["checkIns"] = try checkIns(payload["check_ins"])
                raw["eveningReview"] = try evening(payload["evening_review"])
                daily[date] = raw
            }
            else
            {
                let extra = kind == "weekly_review"
                    ? ["source_review_key": "id", "start_date": "startKey", "time_zone": "timeZoneID", "first_weekday": "firstWeekday",
                       "constraints": "constraints", "decisions": "decisions"]
                    : ["title": "title", "start_date": "startKey", "end_date": "endKey", "time_zone": "timeZoneID",
                       "starting_objectives": "startingObjectives", "objectives": "objectives"]
                var raw = try mapped(payload, fields: reflections.merging(extra) { _, latest in latest })
                guard let start = payload["start_date"] as? String, let zone = payload["time_zone"] as? String,
                      TimeZone(identifier: zone) != nil, let step = payload["step"] as? Int, (0...2).contains(step) else
            {
                throw Failure.invalid
            }
                _ = try civil(start)
                raw["priorities"] = try priorities(payload["priorities"])
                raw["updatedAt"] = try timestamp(payload["updated_at_utc"])
                raw["completedAt"] = try timestamp(payload["completed_at_utc"])
                if kind == "weekly_review"
                {
                    guard let key = payload["source_review_key"] as? String, let weekday = payload["first_weekday"] as? Int,
                          (1...7).contains(weekday), key == start + "|" + zone + "|" + String(weekday), weekly[key] == nil else
            {
                throw Failure.invalid
            }
                    raw["decisions"] = try decisions(payload["decisions"])
                    weekly[key] = raw
                }
                else
                {
                    guard let id = document["id"] as? String, let uuid = UUID(uuidString: id), let end = payload["end_date"] as? String,
                          start <= end, periodic[uuid.uuidString] == nil else
            {
                throw Failure.invalid
            }
                    _ = try civil(end)
                    raw["id"] = id
                    raw["startingObjectives"] = try objectives(payload["starting_objectives"])
                    raw["objectives"] = try objectives(payload["objectives"])
                    periodic[uuid.uuidString] = raw
                }
            }
        }
        let rhythms = records.filter { $0["record_type"] as? String == "review_rhythm" }
        guard rhythms.count <= 1 else
            {
                throw Failure.invalid
            }
        var rhythm: ReviewRhythmPreferences?
        if let document = rhythms.first
        {
            guard let payload = document["payload"] as? [String: Any], let daily = payload["daily_minutes"] as? Int,
                  let weekly = payload["weekly_minutes"] as? Int, let day = payload["weekly_weekday"] as? Int,
                  (0..<1440).contains(daily), (0..<1440).contains(weekly), (1...7).contains(day) else
            {
                throw Failure.invalid
            }
            let raw = try mapped(payload, fields: ["daily_invitations": "dailyInvitations", "weekly_invitations": "weeklyInvitations",
                "daily_minutes": "dailyMinutes", "weekly_minutes": "weeklyMinutes", "weekly_weekday": "weeklyWeekday",
                "daily_notifications": "dailyNotifications", "weekly_notifications": "weeklyNotifications"])
            rhythm = try JSONDecoder().decode(ReviewRhythmPreferences.self, from: JSONSerialization.data(withJSONObject: raw))
        }
        return PortablePlanningDocuments(
            daily: try JSONDecoder().decode(DailyPlanStore.Document.self, from: JSONSerialization.data(withJSONObject: ["version": 1, "plans": daily])),
            weekly: try JSONDecoder().decode(WeeklyReviewStore.Document.self, from: JSONSerialization.data(withJSONObject: ["version": 1, "records": weekly])),
            periodic: try JSONDecoder().decode(PeriodicReviewStore.Document.self, from: JSONSerialization.data(withJSONObject: ["version": 1, "records": periodic])),
            rhythm: rhythm)
    }
}
