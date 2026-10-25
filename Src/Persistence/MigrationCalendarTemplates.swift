// --------------------------------------------------------------------------------------------------
// @file       MigrationCalendarTemplates.swift
// @brief      Owner-qualified calendar and reusable-template metadata conversion
// @details    Supported User Data Model versions: 1.0. Local migration preview only. Preserves
//             explicit source mappings and ordering without generating Weeks, routines or accounts.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Converts calendar indexes, dated Weeks and template libraries after owned content is mapped.
/// @section Purpose
///     Preserve the scheduling structure around content without inferring mappings from titles.
@MainActor
enum MigrationCalendarTemplates
{

    /// @fcn MigrationCalendarTemplates.date
    /// @brief Validate an exact Gregorian source day without device timezone normalization
    /// @param[in] key Original yyyy-MM-dd source key
    /// @return Gregorian UTC-noon value used only for civil-date arithmetic
    /// @throws Malformed, normalized or unsupported source date errors
    static func date(_ key: String) throws -> Date
    {

        guard key.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else
        {
            throw MigrationContentValues.Failure.invalid("calendar_date_key")
        }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1900...2100).contains(parts[0]) else
        {
            throw MigrationContentValues.Failure.invalid("calendar_date_range")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let result = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              calendar.component(.year, from: result) == parts[0],
              calendar.component(.month, from: result) == parts[1],
              calendar.component(.day, from: result) == parts[2] else
        {
            throw MigrationContentValues.Failure.invalid("calendar_date_key")
        }
        return result
    }


    /// @fcn MigrationCalendarTemplates.listTarget
    /// @brief Resolve an explicit source List mapping within its actual converted owner
    /// @param[in] id Original numeric List identity
    /// @param[in] collection Original owner content
    /// @param[in] scope Stable original owner namespace
    /// @param[in] context Existing conversion mappings
    /// @param[in] active Whether archived Lists must be rejected for a live day mapping
    /// @return Existing canonical List UUID
    /// @throws Missing or archived mapping errors
    private static func listTarget(_ id: Int, collection: PersonalCollection, scope: String,
        context: MigrationContentValues, active: Bool) throws -> String
    {

        guard let list = collection.lists.first(where: { $0.id == id }), !active || !list.isArchived else
        {
            throw MigrationContentValues.Failure.invalid("calendar_template_list_mapping")
        }
        return try context.id("list", owner: scope, legacy: String(id))
    }


    /// @fcn MigrationCalendarTemplates.convert
    /// @brief Convert actual saved calendar/template metadata using established content identities
    /// @details No loaders, timezone fallback, default-template selection or account allocation runs.
    /// @param[in] values Frozen source preferences already guarded by the content census
    /// @param[in] context Candidate content mappings; caller discards the entire slice on failure
    /// @param[in] originalTimeZoneID User-confirmed original live-calendar zone
    /// @return Canonical calendar_week, calendar_index, planning_template and template_library records
    /// @throws Invalid civil dates, mappings, source provenance or ambiguous checklist ownership
    static func convert(values: [String: Any], context: MigrationContentValues, originalTimeZoneID: String) throws -> [[String: Any]]
    {

        var records: [[String: Any]] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        if let data = values["Plenact.CalendarWeeks.v1"] as? Data
        {
            let source = try JSONDecoder().decode(PlanningCalendarDocument.self, from: data)
            let zoneContext = MigrationContentValues(journal: context.journal, timeZoneID: originalTimeZoneID, mediaDigests: [:])
            _ = try MigrationContentDates.convert(1_600_000_000, kind: "date", context: zoneContext, path: "calendar-zone")
            let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            if let links = raw["checklistLinkWeeks"] as? [String]
            {
                let keys = stride(from: 0, to: links.count, by: 2).map { links[$0].lowercased() }
                guard links.count % 2 == 0, Set(keys).count == keys.count else
                {
                    throw MigrationContentValues.Failure.invalid("calendar_duplicate_checklist_mapping")
                }
            }
            var weekTargets: [UUID: String] = [:]
            for week in source.weeks
            {
                let scope = week.collection.id.uuidString.lowercased()
                guard let collection = context.collectionTargets[scope] else
                {
                    throw MigrationContentValues.Failure.invalid("calendar_collection_mapping")
                }
                let start = try date(week.startKey)
                guard calendar.component(.weekday, from: start) == source.firstWeekday,
                      Set(week.dayListIDs.values).count == week.dayListIDs.count else
                {
                    throw MigrationContentValues.Failure.invalid("calendar_week_mapping")
                }
                var days: [[String: Any]] = []
                for key in week.dayListIDs.keys.sorted()
                {
                    let day = try date(key)
                    let distance = calendar.dateComponents([.day], from: start, to: day).day ?? -1
                    guard (0..<7).contains(distance), let sourceList = week.dayListIDs[key] else
                    {
                        throw MigrationContentValues.Failure.invalid("calendar_day_outside_week")
                    }
                    days.append(["date": key, "list_id": try listTarget(sourceList, collection: week.collection,
                        scope: scope, context: context, active: true)])
                }
                let id = try context.id("calendar_week", owner: "calendar_weeks", legacy: scope)
                weekTargets[week.id] = id
                records.append(context.document("calendar_week", id: id, payload: [
                    "start_date": week.startKey, "collection_id": collection, "first_weekday": source.firstWeekday,
                    "time_zone": originalTimeZoneID, "time_zone_source": "user_confirmed",
                    "day_lists": days, "explicitly_saved": week.explicitlySaved]))
            }
            var links: [[String: Any]] = []
            let liveCards = Set(context.cardTargets.filter { key, _ in
                context.calendarOwnerScopes.contains(key.components(separatedBy: ":").first ?? "")
            }.values)
            for item in (source.checklistLinkWeeks ?? [:]).keys.sorted(by: { $0.uuidString < $1.uuidString })
            {
                guard let owner = source.checklistLinkWeeks?[item], let week = weekTargets[owner] else
                {
                    throw MigrationContentValues.Failure.invalid("calendar_checklist_week_target")
                }
                let matches = context.journal.entries.filter {
                    $0.source.recordType == "nested_checklist_item" && liveCards.contains($0.source.owner) &&
                        $0.source.legacyID == item.uuidString.lowercased() &&
                        context.usedNested.contains($0.source.owner + ":checklist_item:" + $0.source.legacyID)
                }
                guard matches.count == 1, let target = matches.first?.target else
                {
                    throw MigrationContentValues.Failure.invalid("calendar_checklist_item_ambiguous")
                }
                links.append(["checklist_item_id": target.uuidString.lowercased(), "week_id": week])
            }
            let index = try context.id("calendar_index", owner: "workspace_metadata", legacy: "Plenact.CalendarWeeks.v1")
            records.append(context.document("calendar_index", id: index, payload: [
                "source_store_version": source.version, "first_weekday": source.firstWeekday,
                "current_week_start_date": source.currentWeekKey,
                "week_ids": source.weeks.map { weekTargets[$0.id]! }, "checklist_link_weeks": links]))
        }
        if let data = values["Plenact.PlanningTemplates.v1"] as? Data
        {
            let library = try JSONDecoder().decode(PlanningRoutineLibrary.self, from: data)
            guard Set(library.templates.map(\.id)).count == library.templates.count,
                  library.bundledRoutineRevision.map({ (0...Int(Int32.max)).contains($0) }) ?? true else
            {
                throw MigrationContentValues.Failure.invalid("template_library_identity_or_revision")
            }
            var ids: [UUID: String] = [:]
            for template in library.templates
            {
                _ = try date(template.anchorKey)
                guard (1...7).contains(template.firstWeekday), !template.weekdays.isEmpty,
                      template.weekdays.keys.allSatisfy({ (1...7).contains($0) }),
                      Set(template.weekdays.values).count == template.weekdays.count,
                      template.kind != .day || template.weekdays.count == 1 else
                {
                    throw MigrationContentValues.Failure.invalid("template_weekday_mapping")
                }
                let scope = "template:" + template.id.uuidString.lowercased() + ":" + template.collection.id.uuidString.lowercased()
                guard let collection = context.collectionTargets[scope] else
                {
                    throw MigrationContentValues.Failure.invalid("template_collection_mapping")
                }
                // Validate the stored zone even for a routine containing no timed Cards.
                let zoneContext = MigrationContentValues(journal: context.journal, timeZoneID: template.timeZoneID, mediaDigests: [:])
                _ = try MigrationContentDates.convert(1_600_000_000, kind: "date", context: zoneContext, path: "template-zone")
                let id = try context.id("planning_template", owner: "planning_templates", legacy: template.id.uuidString.lowercased())
                ids[template.id] = id
                var weekdays: [[String: Any]] = []
                for weekday in template.weekdays.keys.sorted()
                {
                    weekdays.append(["weekday": weekday, "list_id": try listTarget(template.weekdays[weekday]!,
                        collection: template.collection, scope: scope, context: context, active: false)])
                }
                var focus: Any = NSNull()
                if let source = template.exampleFocus
                {
                    var mapped: [String: Any] = [:]
                    for (key, originals) in [("important", source.important), ("bookmarked", source.bookmarked), ("all_day", source.allDay)]
                    {
                        var targets: [String] = []
                        for original in originals.sorted()
                        {
                            guard let target = context.cardTargets[scope + ":" + String(original)] else
                            {
                                throw MigrationContentValues.Failure.invalid("template_focus_mapping")
                            }
                            targets.append(target)
                        }
                        mapped[key] = targets
                    }
                    focus = mapped
                }
                records.append(context.document("planning_template", id: id, payload: [
                    "name": template.name, "kind": template.kind == .day ? "day" : "week",
                    "anchor_date": template.anchorKey, "time_zone": template.timeZoneID,
                    "first_weekday": template.firstWeekday, "collection_id": collection,
                    "weekdays": weekdays, "example_focus": focus]))
            }
            var selected: Any = NSNull()
            if let source = library.defaultWeekID
            {
                guard let id = ids[source], library.templates.first(where: { $0.id == source })?.kind == .week else
                {
                    throw MigrationContentValues.Failure.invalid("template_default_mapping")
                }
                selected = id
            }
            let id = try context.id("template_library", owner: "workspace_metadata", legacy: "Plenact.PlanningTemplates.v1")
            records.append(context.document("template_library", id: id, payload: [
                "source_store_version": library.version, "template_ids": library.templates.map { ids[$0.id]! },
                "default_week_id": selected, "bundled_routine_revision": library.bundledRoutineRevision as Any? ?? NSNull()]))
        }
        return records
    }
}
