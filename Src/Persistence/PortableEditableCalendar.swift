// --------------------------------------------------------------------------------------------------
// @file       PortableEditableCalendar.swift
// @brief      Reconstruct editable calendar Weeks and template libraries from portable ownership records
// @details    Supported User Data Model versions: 1.0 calendar/template records. Preserves authored
//             ordering and explicit day ownership; no title-based matching, loaders or persistence.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Extends the editable bridge with explicit calendar and routine ownership.
/// @section Purpose
///     Rebuild day mappings without treating renamed Lists as a source of calendar identity.
extension PortableEditableContent
{

    /// @fcn PortableEditableContent.record
    /// @brief Require an existing canonical record of the expected kind
    /// @param[in] id Canonical UUID
    /// @param[in] kind Expected record type
    /// @return Complete retained record
    /// @throws Missing or mismatched target
    func record(_ id: String, kind: String) throws -> [String: Any]
    {

        guard let value = records.first(where: { $0["id"] as? String == id }), value["record_type"] as? String == kind else
        {
            throw Failure.invalid
        }
        return value
    }


    /// @fcn PortableEditableContent.civil
    /// @brief Decode an exact Gregorian civil date independently of device calendar and timezone
    /// @param[in] text YYYY-MM-DD value
    /// @return UTC date used only for civil-date arithmetic
    /// @throws Invalid date
    func civil(_ text: String) throws -> Date
    {

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else
        {
            throw Failure.invalid
        }
        return date
    }


    /// @fcn PortableEditableContent.calendarDocument
    /// @brief Reconstruct ordered Weeks, day ownership and checklist cross-Week overrides
    /// @param[in] selections Account-bound personal selections
    /// @param[in] accountID Expected selection owner
    /// @return Native calendar document, or nil when no calendar index exists
    /// @throws Missing metadata, conflicting ownership or invalid date/reference values
    func calendarDocument(selections: [[String: Any]], accountID: String) throws -> PlanningCalendarDocument?
    {

        let indexes = records.filter { $0["record_type"] as? String == "calendar_index" }
        guard indexes.count <= 1 else
            {
                throw Failure.invalid
            }
        guard let index = indexes.first, let body = index["payload"] as? [String: Any] else
        {
            guard !records.contains(where: { $0["record_type"] as? String == "calendar_week" }) else
            {
                throw Failure.invalid
            }
            return nil
        }
        _ = try mapped(body, fields: ["source_store_version": "version", "first_weekday": "firstWeekday",
            "current_week_start_date": "currentWeekKey", "week_ids": "weeks", "checklist_link_weeks": "checklistLinkWeeks"])
        guard body["source_store_version"] as? Int == 1, let firstWeekday = body["first_weekday"] as? Int,
              (1...7).contains(firstWeekday), let current = body["current_week_start_date"] as? String,
              let weekIDs = body["week_ids"] as? [String], Set(weekIDs).count == weekIDs.count,
              Set(weekIDs) == Set(records.filter { $0["record_type"] as? String == "calendar_week" }.compactMap { $0["id"] as? String }) else
        {
            throw Failure.invalid
        }
        var weeks: [DatedPlanningWeek] = []
        var metadataOwners: [String: UUID] = [:]
        var usedCollections = Set<String>()
        var usedDays = Set<String>()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for id in weekIDs
        {
            let week = try record(id, kind: "calendar_week")
            guard let value = week["payload"] as? [String: Any] else
            {
                throw Failure.invalid
            }
            _ = try mapped(value, fields: ["start_date": "start", "collection_id": "collection", "first_weekday": "weekday",
                "time_zone": "zone", "time_zone_source": "source", "day_lists": "days", "explicitly_saved": "saved"])
            guard let start = value["start_date"] as? String, let owner = value["collection_id"] as? String,
                  usedCollections.insert(owner).inserted, usedDays.insert(start).inserted,
                  value["first_weekday"] as? Int == firstWeekday,
                  let zone = value["time_zone"] as? String, TimeZone(identifier: zone) != nil,
                  let saved = value["explicitly_saved"] as? Bool else
            {
                throw Failure.invalid
            }
            let first = try civil(start)
            guard calendar.component(.weekday, from: first) == firstWeekday else
            {
                throw Failure.invalid
            }
            var dates: [String: String] = [:]
            var days: [String: Int] = [:]
            for mapping in try array(value["day_lists"])
            {
                guard Set(mapping.keys) == ["date", "list_id"], let day = mapping["date"] as? String,
                      let target = mapping["list_id"] as? String, dates[target] == nil, days[day] == nil,
                      let number = numericIDs[target] else
                {
                    throw Failure.invalid
                }
                let distance = calendar.dateComponents([.day], from: first, to: try civil(day)).day ?? -1
                guard (0..<7).contains(distance) else
            {
                throw Failure.invalid
            }
                dates[target] = day
                days[day] = number
            }
            let collection = try collection(record(owner, kind: "collection"), selections: selections,
                accountID: accountID, timeZoneID: zone, listDates: dates)
            guard Set(days.values).isSubset(of: Set(collection.lists.filter { !$0.isArchived }.map(\.id))) else
            {
                throw Failure.invalid
            }
            weeks.append(DatedPlanningWeek(startKey: start, collection: collection, dayListIDs: days, explicitlySaved: saved))
            metadataOwners[id] = collection.id
        }
        guard weeks.contains(where: { $0.startKey == current }) else
            {
                throw Failure.invalid
            }
        var links: [UUID: UUID] = [:]
        for mapping in try array(body["checklist_link_weeks"])
        {
            guard Set(mapping.keys) == ["checklist_item_id", "week_id"], let item = mapping["checklist_item_id"] as? String,
                  let itemID = UUID(uuidString: item), let weekID = mapping["week_id"] as? String,
                  let owner = metadataOwners[weekID], links[itemID] == nil else
            {
                throw Failure.invalid
            }
            // Canonical nested UUIDs are retained directly in the reconstructed checklists.
            let matches = weeks.flatMap { $0.collection.lists }.flatMap { $0.cards + $0.archivedCards }
                .reduce(0) { $0 + checklistOccurrences(itemID, in: $1.checklists) }
            guard matches == 1 else
            {
                throw Failure.invalid
            }
            links[itemID] = owner
        }
        var output = PlanningCalendarDocument(currentWeekKey: current, firstWeekday: firstWeekday, weeks: weeks)
        output.checklistLinkWeeks = links
        return output
    }


    /// @fcn PortableEditableContent.checklistOccurrences
    /// @brief Count a cross-Week checklist item including retained nested Action Details
    /// @param[in] id Canonical nested item identity
    /// @param[in] lists Reconstructed checklist hierarchy
    /// @return Number of distinct occurrences
    private func checklistOccurrences(_ id: UUID, in lists: [KanbanChecklist]) -> Int
    {

        var count = 0
        for list in lists
        {
            for item in list.items
            {
                if item.id == id
                {
                    count += 1
                }
                if case .actionDetail(let detail) = item.content
                {
                    count += checklistOccurrences(id, in: detail.checklists)
                }
                else if let detail = item.retainedDetail
                {
                    count += checklistOccurrences(id, in: detail.checklists)
                }
            }
        }
        return count
    }


    /// @fcn PortableEditableContent.templateLibrary
    /// @brief Reconstruct authored routine order, default selection and example focus independently of live Weeks
    /// @param[in] accountID Expected owner context; template bookmarks are separate example intent
    /// @return Native routine library, or nil when no source library exists
    /// @throws Invalid order, ownership, default routine or focus references
    func templateLibrary(accountID: String) throws -> PlanningRoutineLibrary?
    {

        let libraries = records.filter { $0["record_type"] as? String == "template_library" }
        guard libraries.count <= 1 else
            {
                throw Failure.invalid
            }
        guard let library = libraries.first, let value = library["payload"] as? [String: Any] else
        {
            guard !records.contains(where: { $0["record_type"] as? String == "planning_template" }) else
            {
                throw Failure.invalid
            }
            return nil
        }
        _ = try mapped(value, fields: ["source_store_version": "version", "template_ids": "templates",
            "default_week_id": "defaultWeekID", "bundled_routine_revision": "bundledRoutineRevision"])
        guard value["source_store_version"] as? Int == 1, let ids = value["template_ids"] as? [String],
              Set(ids).count == ids.count,
              Set(ids) == Set(records.filter { $0["record_type"] as? String == "planning_template" }.compactMap { $0["id"] as? String }) else
        {
            throw Failure.invalid
        }
        var templates: [PlanningRoutineTemplate] = []
        for id in ids
        {
            let document = try record(id, kind: "planning_template")
            guard let payload = document["payload"] as? [String: Any] else
            {
                throw Failure.invalid
            }
            var raw = try mapped(payload, fields: ["name": "name", "kind": "kind", "anchor_date": "anchorKey",
                "time_zone": "timeZoneID", "first_weekday": "firstWeekday", "collection_id": "collection",
                "weekdays": "weekdays", "example_focus": "exampleFocus"])
            guard let anchor = payload["anchor_date"] as? String, let zone = payload["time_zone"] as? String,
                  TimeZone(identifier: zone) != nil, let weekday = payload["first_weekday"] as? Int, (1...7).contains(weekday),
                  let owner = payload["collection_id"] as? String,
                  let kind = payload["kind"] as? String, ["day", "week"].contains(kind) else
            {
                throw Failure.invalid
            }
            let first = try civil(anchor)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            var weekdays: [String: Int] = [:]
            var dates: [String: String] = [:]
            var usedLists = Set<String>()
            for mapping in try array(payload["weekdays"])
            {
                guard Set(mapping.keys) == ["weekday", "list_id"], let day = mapping["weekday"] as? Int,
                      (1...7).contains(day), let listID = mapping["list_id"] as? String, weekdays[String(day)] == nil,
                      usedLists.insert(listID).inserted, let number = numericIDs[listID] else
            {
                throw Failure.invalid
            }
                weekdays[String(day)] = number
                let offset = (day - calendar.component(.weekday, from: first) + 7) % 7
                let date = calendar.date(byAdding: .day, value: offset, to: first)!
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.calendar = calendar
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = calendar.timeZone
                dates[listID] = formatter.string(from: date)
            }
            guard !weekdays.isEmpty, kind != "day" || weekdays.count == 1 else
            {
                throw Failure.invalid
            }
            let nativeOwner = try collection(record(owner, kind: "collection"), selections: [],
                accountID: accountID, timeZoneID: zone, listDates: dates)
            guard Set(weekdays.values).isSubset(of: Set(nativeOwner.lists.map(\.id))) else
            {
                throw Failure.invalid
            }
            raw["id"] = id
            raw["kind"] = kind == "day" ? "Day" : "Week"
            raw["weekdays"] = weekdays
            raw["collection"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(nativeOwner))
            if let focus = payload["example_focus"] as? [String: Any]
            {
                let owned = Set(nativeOwner.lists.flatMap { $0.cards + $0.archivedCards }.map(\.id))
                var mappedFocus = try mapped(focus, fields: ["important": "important", "bookmarked": "bookmarked", "all_day": "allDay"])
                for key in mappedFocus.keys
                {
                    guard let targets = mappedFocus[key] as? [String], Set(targets).count == targets.count else
            {
                throw Failure.invalid
            }
                    let numbers = try targets.map { target -> Int in
                        guard let number = numericIDs[target], owned.contains(number) else
            {
                throw Failure.invalid
            }
                        return number
                    }
                    mappedFocus[key] = numbers
                }
                raw["exampleFocus"] = mappedFocus
            }
            templates.append(try JSONDecoder().decode(PlanningRoutineTemplate.self, from: JSONSerialization.data(withJSONObject: raw)))
        }
        if let defaultID = value["default_week_id"] as? String
        {
            guard templates.contains(where: { $0.id.uuidString.lowercased() == defaultID && $0.kind == .week }) else
            {
                throw Failure.invalid
            }
        }
        let raw: [String: Any] = ["version": 1,
            "templates": try JSONSerialization.jsonObject(with: JSONEncoder().encode(templates)),
            "defaultWeekID": value["default_week_id"] ?? NSNull(), "bundledRoutineRevision": value["bundled_routine_revision"] ?? NSNull()]
        return try JSONDecoder().decode(PlanningRoutineLibrary.self, from: JSONSerialization.data(withJSONObject: raw))
    }
}
