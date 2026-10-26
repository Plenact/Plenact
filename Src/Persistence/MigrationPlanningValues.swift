// --------------------------------------------------------------------------------------------------
// @file       MigrationPlanningValues.swift
// @brief      Historical planning values and exact owner/creation-qualified links
// @details    Supported User Data Model versions: 1.0. Reads original native reference-epoch dates;
//             never recomputes saved writing, progress, moods or decisions from current Cards.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Maps nested planning history while preserving nullable and independent snapshots.
/// @section Purpose
///     Resolve historical links only when original owner, numeric ID and creation provenance agree.
@MainActor
struct MigrationPlanningValues
{

    let context: MigrationContentValues
    let priorityResolver: (([String: Any]) throws -> [String: Any])?


    /// @fcn MigrationPlanningValues.init
    /// @brief Select journal references or an explicit export-only historical resolver
    /// @param[in] context Frozen conversion context
    /// @param[in] priorityResolver Optional verified portable reference resolver
    /// @return Ephemeral value mapper without persistent side effects
    init(context: MigrationContentValues, priorityResolver: (([String: Any]) throws -> [String: Any])? = nil)
    {

        self.context = context
        self.priorityResolver = priorityResolver
    }


    /// @fcn MigrationPlanningValues.timestamp
    /// @brief Convert an original native reference-epoch Date without using the device timezone
    /// @param[in] value Original 2001-reference seconds or absent/null value
    /// @param[in] path Source evidence location
    /// @return Canonical UTC millisecond timestamp or null
    /// @throws Invalid or unsupported source timestamp errors
    func timestamp(_ value: Any?, path: String) throws -> Any
    {

        guard let value, !(value is NSNull) else
        {
            return NSNull()
        }
        guard let seconds = value as? NSNumber else
        {
            throw MigrationContentValues.Failure.invalid("planning_timestamp")
        }
        return try context.utc(Date(timeIntervalSinceReferenceDate: seconds.doubleValue).timeIntervalSince1970, path: path)
    }


    /// @fcn MigrationPlanningValues.dateAndZone
    /// @brief Validate exact saved civil-date and pinned timezone context without guessing
    /// @param[in] date Original Gregorian day key
    /// @param[in] zone Original saved IANA timezone or supported UTC alias
    /// @return Void after bounded context checks
    /// @throws Invalid dates or unsupported zones
    func dateAndZone(_ date: String, zone: String) throws
    {

        _ = try MigrationCalendarTemplates.date(date)
        let zoneContext = MigrationContentValues(journal: context.journal, timeZoneID: zone, mediaDigests: [:])
        _ = try MigrationContentDates.convert(1_600_000_000, kind: "date", context: zoneContext, path: "planning-zone")
    }


    /// @fcn MigrationPlanningValues.step
    /// @brief Validate stored progress without clamping or advancing the workflow
    /// @param[in] value Original step or absent/null value
    /// @param[in] optional Whether absence is allowed
    /// @return Original zero-through-two progress or explicit null
    /// @throws Invalid progress values
    func step(_ value: Any?, optional: Bool = false) throws -> Any
    {

        if optional, value == nil || value is NSNull
        {
            return NSNull()
        }
        guard let number = value as? Int, (0...2).contains(number) else
        {
            throw MigrationContentValues.Failure.invalid("planning_step")
        }
        return number
    }


    /// @fcn MigrationPlanningValues.priority
    /// @brief Preserve a historical priority snapshot and exact source-creation discriminator
    /// @param[in] raw Original saved owner/Card/title/location/creation fields
    /// @return Canonical priority with explicit unavailable targets when originals no longer exist
    /// @throws Invalid identity or timestamp provenance
    func priority(_ raw: [String: Any]) throws -> [String: Any]
    {

        if let priorityResolver
        {

            return try priorityResolver(raw)
        }
        let owner = try MigrationContentValues.lowerUUID(raw["ownerID"])
        let collection = try context.id("collection", owner: "source_collections", legacy: owner)
        let discriminator = (raw["sourceCreatedAt"] as? NSNumber).map { String($0.doubleValue) }
        let card = try context.id("card", owner: owner, legacy: String(raw["cardID"] as! Int), discriminator: discriminator)
        return ["source_collection_id": try context.reference("collection", collection),
            "card_id": try context.reference("card", card), "title": raw["title"]!, "source_location": raw["location"]!,
            "source_created_at_utc": try timestamp(raw["sourceCreatedAt"], path: card + "/historical-creation")]
    }


    /// @fcn MigrationPlanningValues.priorities
    /// @brief Retain authored priority order while rejecting duplicate logical source references
    /// @param[in] value Saved priority array
    /// @return Ordered canonical snapshot array
    /// @throws Duplicate or malformed source identities
    func priorities(_ value: Any) throws -> [[String: Any]]
    {

        let raw = value as! [[String: Any]]
        var seen: Set<String> = []
        return try raw.map { item in
            let key = (try MigrationContentValues.lowerUUID(item["ownerID"])) + ":" + String(item["cardID"] as! Int)
            guard seen.insert(key).inserted else
            {
                throw MigrationContentValues.Failure.invalid("planning_duplicate_priority")
            }
            return try priority(item)
        }
    }


    /// @fcn MigrationPlanningValues.checkIn
    /// @brief Preserve a legacy check-in without inventing historical progress or plan context
    /// @param[in] raw Original legacy check-in
    /// @param[in] path Source evidence location
    /// @return Canonical legacy check-in value
    /// @throws Invalid referenced identity or timestamp
    func checkIn(_ raw: [String: Any], path: String) throws -> [String: Any]
    {

        ["focus": try (raw["focus"] as? [String: Any]).map(priority) as Any? ?? NSNull(),
            "changed": raw["changed"]!, "saved_at_utc": try timestamp(raw["savedAt"], path: path + "/check-in")]
    }


    /// @fcn MigrationPlanningValues.entries
    /// @brief Preserve actual submitted check-in snapshots including optional counts and mood text
    /// @param[in] raw Saved authored history array, distinct from null/absent history
    /// @param[in] path Original plan identity
    /// @return Ordered check-in history without generating a legacy projection
    /// @throws Duplicate IDs, invalid progress counts or empty mood values
    func entries(_ raw: [[String: Any]], path: String) throws -> [[String: Any]]
    {

        var seen: Set<String> = []
        return try raw.map { item in
            guard let id = item["id"] as? String, !id.isEmpty, seen.insert(id).inserted else
            {
                throw MigrationContentValues.Failure.invalid("planning_checkin_identity")
            }
            var output: [String: Any] = ["id": id,
                "saved_at_utc": try timestamp(item["savedAt"], path: path + "/check-in/" + id),
                "changed": item["changed"]!, "focus": try (item["focus"] as? [String: Any]).map(priority) as Any? ?? NSNull(),
                "intention": item["intention"]!, "constraints": item["constraints"]!, "concerns": item["concerns"]!,
                "priorities": try priorities(item["priorities"]!), "legacy": item["legacy"]!, "mood": item["mood"] ?? NSNull()]
            for (source, target) in [("completedTasks", "completed_tasks"), ("totalTasks", "total_tasks"), ("notes", "notes"), ("unavailable", "unavailable")]
            {
                if let number = item[source] as? Int
                {
                    guard (0...Int(Int32.max)).contains(number) else
                    {
                        throw MigrationContentValues.Failure.invalid("planning_checkin_counts")
                    }
                    output[target] = number
                }
                else
                {
                    output[target] = NSNull()
                }
            }
            if let complete = item["completedTasks"] as? Int, let total = item["totalTasks"] as? Int, complete > total
            {
                throw MigrationContentValues.Failure.invalid("planning_checkin_counts")
            }
            if let mood = item["mood"] as? [String: Any]
            {
                guard (mood["emoji"] as? String)?.isEmpty == false, (mood["label"] as? String)?.isEmpty == false else
                {
                    throw MigrationContentValues.Failure.invalid("planning_mood")
                }
            }
            return output
        }
    }


    /// @fcn MigrationPlanningValues.decisions
    /// @brief Map recorded decisions as history without applying their actions
    /// @param[in] value Original decision array
    /// @param[in] path Original containing review identity
    /// @return Ordered source/result/action/time snapshots
    /// @throws Duplicate identities or invalid date actions
    func decisions(_ value: Any, path: String) throws -> [[String: Any]]
    {

        var seen: Set<String> = []
        return try (value as! [[String: Any]]).map { raw in
            let id = try MigrationContentValues.lowerUUID(raw["id"])
            guard seen.insert(id).inserted else
            {
                throw MigrationContentValues.Failure.invalid("planning_decision_identity")
            }
            let source = raw["action"] as! [String: Any]
            let key = source.keys.first!
            var action: [String: Any] = ["kind": key == "keepTomorrow" ? "keep_tomorrow" : key]
            if key == "date"
            {
                let date = (source[key] as! [String: Any])["_0"] as! String
                _ = try MigrationCalendarTemplates.date(date)
                action["date"] = date
            }
            return ["id": id, "source": try priority(raw["source"] as! [String: Any]),
                "result": try priority(raw["result"] as! [String: Any]), "action": action,
                "recorded_at_utc": try timestamp(raw["recordedAt"], path: path + "/decision/" + id)]
        }
    }


    /// @fcn MigrationPlanningValues.evening
    /// @brief Preserve an evening review's text, achievements and recorded workflow position
    /// @param[in] raw Original evening review
    /// @param[in] path Source plan identity
    /// @return Canonical evening-review object
    /// @throws Invalid progress or nested decisions
    func evening(_ raw: [String: Any], path: String) throws -> [String: Any]
    {

        ["step": try step(raw["step"]), "completed_at_utc": try timestamp(raw["completedAt"], path: path + "/evening"),
            "helped": raw["helped"]!, "difficult": raw["difficult"]!, "tomorrow": raw["tomorrow"]!,
            "decisions": try decisions(raw["decisions"]!, path: path), "achievements": try priorities(raw["achievements"]!)]
    }


    /// @fcn MigrationPlanningValues.review
    /// @brief Map shared weekly/periodic reflection fields without recomputing current progress
    /// @param[in] raw Original source review
    /// @param[in] path Stable review identity
    /// @return Common canonical reflection payload
    /// @throws Invalid progress, references or timestamps
    func review(_ raw: [String: Any], path: String) throws -> [String: Any]
    {

        ["step": try step(raw["step"]), "highlights": raw["highlights"]!, "learned": raw["learned"]!,
            "direction": raw["direction"]!, "risks": raw["risks"]!, "priorities": try priorities(raw["priorities"]!),
            "updated_at_utc": try timestamp(raw["updatedAt"], path: path + "/updated"),
            "completed_at_utc": try timestamp(raw["completedAt"], path: path + "/completed")]
    }


    /// @fcn MigrationPlanningValues.objectives
    /// @brief Preserve independent starting/current objective snapshots with their shared logical UUIDs
    /// @param[in] value Original objective array
    /// @return Ordered title/status/progress/next-step snapshots
    /// @throws Duplicate IDs, empty titles or unsupported statuses
    func objectives(_ value: Any) throws -> [[String: Any]]
    {

        var seen: Set<String> = []
        return try (value as! [[String: Any]]).map { raw in
            let id = try MigrationContentValues.lowerUUID(raw["id"])
            guard seen.insert(id).inserted, let title = raw["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let status = ["Active": "active", "Achieved": "achieved", "Paused": "paused", "Let go": "released"][raw["status"] as? String ?? ""] else
            {
                throw MigrationContentValues.Failure.invalid("planning_objective")
            }
            return ["id": id, "title": title, "status": status, "progress": raw["progress"]!, "next_step": raw["nextStep"]!]
        }
    }
}
