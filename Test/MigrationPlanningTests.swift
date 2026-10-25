// --------------------------------------------------------------------------------------------------
// @file       MigrationPlanningTests.swift
// @brief      Historical daily/check-in/review migration and safe-reference acceptance
// @details    Supported User Data Model versions: 1.0. Synthetic plans, content and temporary
//             journals only; no actual review action, notification or owner workspace is changed.
// --------------------------------------------------------------------------------------------------
import Foundation
import XCTest
@testable import Plenact


/// Tests immutable planning snapshots, exact creation-qualified references and source-only conversion.
/// @section Purpose
///     Prove deleted/reused Card IDs cannot rewrite historical writing or resolve to unrelated content.
@MainActor
final class MigrationPlanningTests: XCTestCase
{

    /// @fcn MigrationPlanningTests.fixture
    /// @brief Capture rich planning history plus one live Card with deliberately different current text
    /// @param[in] edit Optional source mutation before capture
    /// @param[in] body Assertions receiving frozen source and an isolated journal path
    /// @return Void after removing synthetic source state
    /// @throws Fixture encoding, source capture or assertion-support errors
    private func fixture(edit: ((inout [String: Any]) throws -> Void)? = nil,
        _ body: (LegacyWorkspaceBackup, URL) throws -> Void) throws
    {

        let domain = "Plenact.PlanningMigrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer
        {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        let instant = Date(timeIntervalSinceReferenceDate: 814_536_000.123456)
        let card = KanbanCard(id: 1, word: "Current title", listTitle: "Day", checklists: [], createdAt: instant)
        let week = DatedPlanningWeek.make(for: instant, lists: [KanbanList(id: 1, title: "Day", cards: [card])], calendar: calendar)

        /// @fcn MigrationPlanningTests.priority
        /// @brief Construct original priority bytes without consulting current workspace projections
        /// @param[in] owner Original owner identity
        /// @param[in] created Original source creation discriminator
        /// @return Decoded native historical priority
        /// @throws Synthetic encoding/decoding errors
        func priority(owner: UUID, created: Date) throws -> DailyPlanPriority
        {

            let raw: [String: Any] = ["ownerID": owner.uuidString, "cardID": 1, "title": "  Original priority 🪴  ",
                "location": "Original location", "sourceCreatedAt": created.timeIntervalSinceReferenceDate]
            return try JSONDecoder().decode(DailyPlanPriority.self, from: JSONSerialization.data(withJSONObject: raw))
        }
        let original = try priority(owner: week.id, created: instant)
        let missing = try priority(owner: UUID(), created: instant)
        let reused = try priority(owner: week.id, created: instant.addingTimeInterval(-3600))
        let actions: [DailyReviewAction] = [.keep, .keepTomorrow, .table, .complete, .archive, .queue, .tomorrow,
            .date(PlanningDate.key(instant.addingTimeInterval(86400), calendar: calendar))]
        let decisions = actions.enumerated().map { index, action in
            DailyReviewDecision(source: original, result: index == 0 ? reused : missing, action: action, recordedAt: instant)
        }
        var plan = DailyPlan(date: instant, calendar: calendar)
        plan.intention = "  Historical intention 🌱  "
        plan.constraints = "Before changes"
        plan.concerns = ""
        plan.priorities = [original]
        plan.updatedAt = instant
        plan.visionStep = 2
        plan.visionCompletedAt = instant
        plan.checkIn = DailyCheckIn(focus: original, changed: "Legacy reflection", savedAt: instant)
        plan.checkIns = [DailyCheckInEntry(id: "retained-history-id", savedAt: instant, changed: "Original check-in",
            focus: missing, intention: "Earlier intention", constraints: "Earlier constraints", concerns: "Earlier concerns",
            priorities: [original], completedTasks: 0, totalTasks: 3, notes: 0, unavailable: 1, legacy: false,
            mood: CheckInMood(emoji: "🌱", label: " Unhurried "))]
        plan.eveningReview = DailyEveningReview(step: 2, completedAt: instant, helped: "What helped", difficult: "",
            tomorrow: "Next", decisions: decisions, achievements: [original])
        var legacy = DailyPlan(date: instant.addingTimeInterval(86400), calendar: calendar)
        legacy.checkIn = DailyCheckIn(focus: original, changed: "Legacy only", savedAt: instant)
        var weekly = WeeklyReviewRecord(date: instant, calendar: calendar)
        weekly.step = 1
        weekly.highlights = "Original weekly reflection"
        weekly.priorities = [original]
        weekly.decisions = decisions
        weekly.updatedAt = instant
        var periodic = PeriodicReviewRecord(title: "  Period reflection  ", start: instant,
            end: instant.addingTimeInterval(7 * 86400), calendar: calendar)
        let objective = ReviewObjective(title: "Original objective", progress: "Before", nextStep: "First")
        var current = objective
        current.status = .paused
        current.progress = "After"
        periodic.startingObjectives = [objective]
        periodic.objectives = [current]
        periodic.priorities = [original]
        periodic.updatedAt = instant
        let daily = DailyPlanStore.Document(plans: [plan.id: plan, legacy.id: legacy])
        let weeks = WeeklyReviewStore.Document(records: [weekly.id: weekly])
        let periods = PeriodicReviewStore.Document(records: [periodic.id.uuidString: periodic])
        var rhythm = ReviewRhythmPreferences()
        rhythm.dailyMinutes = 0
        rhythm.dailyNotifications = true
        var values: [String: Any] = ["Plenact.Board.v1": try JSONEncoder().encode(week.collection.lists),
            "Plenact.CalendarWeeks.v1": try JSONEncoder().encode(PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week])),
            "Plenact.DailyPlans.v1": try JSONEncoder().encode(daily), "Plenact.WeeklyReviews.v1": try JSONEncoder().encode(weeks),
            "Plenact.PeriodicReviews.v1": try JSONEncoder().encode(periods), "Plenact.ReviewRhythm.v1": try JSONEncoder().encode(rhythm)]
        try edit?(&values)
        defaults.setPersistentDomain(values, forName: domain)
        let backup = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
        try body(backup, root.appendingPathComponent("Journal/ids.json"))
    }


    /// @fcn MigrationPlanningTests.records
    /// @brief Read the actual emitted canonical record files
    /// @param[in] preview Prepared migration evidence
    /// @return Parsed records in emitted order
    /// @throws Missing or malformed output errors
    private func records(_ preview: MigrationPreview) throws -> [[String: Any]]
    {

        let files = try XCTUnwrap(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["Records"]?.fileWrappers)
        return try files.sorted { $0.key < $1.key }.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.value.regularFileContents)) as? [String: Any])
        }
    }


    /// @fcn MigrationPlanningTests.testHistoryReferencesAndStableRetry
    /// @brief Preserve historical writing/nulls, creation-qualified links, objective snapshots and reminder intent
    /// @return Void after source preservation and emitted-record checks
    /// @throws Fixture, conversion or assertion-support errors
    func testHistoryReferencesAndStableRetry() throws
    {

        try fixture { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            guard preview.planningRecordCount == 5 else
            {
                let report = try MigrationBackupReader.file("MigrationPreview/Report.json", in: preview.files)
                XCTFail("Planning output missing: " + String(decoding: report, as: UTF8.self))
                return
            }
            let output = try records(preview)
            let card = try XCTUnwrap(output.first { $0["record_type"] as? String == "card" })
            let daily = output.filter { $0["record_type"] as? String == "daily_plan" }
            let full = try XCTUnwrap(daily.first { ($0["payload"] as? [String: Any])?["check_ins"] is [Any] })
            let payload = try XCTUnwrap(full["payload"] as? [String: Any])
            let priorities = try XCTUnwrap(payload["priorities"] as? [[String: Any]])
            XCTAssertEqual(priorities.first?["card_id"] as? String, card["id"] as? String)
            XCTAssertEqual(priorities.first?["title"] as? String, "  Original priority 🪴  ")
            let history = try XCTUnwrap(payload["check_ins"] as? [[String: Any]])
            XCTAssertEqual(history.first?["intention"] as? String, "Earlier intention")
            XCTAssertEqual(history.first?["completed_tasks"] as? Int, 0)
            XCTAssertEqual((history.first?["mood"] as? [String: Any])?["label"] as? String, " Unhurried ")
            XCTAssertTrue(daily.contains { ($0["payload"] as? [String: Any])?["check_ins"] is NSNull })
            let periodic = try XCTUnwrap(output.first { $0["record_type"] as? String == "periodic_review" }?["payload"] as? [String: Any])
            let starting = try XCTUnwrap(periodic["starting_objectives"] as? [[String: Any]])
            let current = try XCTUnwrap(periodic["objectives"] as? [[String: Any]])
            XCTAssertEqual(starting.first?["id"] as? String, current.first?["id"] as? String)
            XCTAssertEqual(starting.first?["progress"] as? String, "Before")
            XCTAssertEqual(current.first?["progress"] as? String, "After")
            XCTAssertEqual(current.first?["status"] as? String, "paused")
            let decisions = try XCTUnwrap((payload["evening_review"] as? [String: Any])?["decisions"] as? [[String: Any]])
            XCTAssertEqual(decisions.count, 8)
            XCTAssertNotEqual((decisions.first?["result"] as? [String: Any])?["card_id"] as? String, card["id"] as? String)
            XCTAssertEqual(preview.planningReviewCount, 3)
            let second = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: output, options: .sortedKeys),
                try JSONSerialization.data(withJSONObject: records(second), options: .sortedKeys))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: backup.files),
                try MigrationBackupReader.file("Preferences.plist", in: preview.files))
            for name in ["PlanningPreview.json", "IdentityJournal.json", "Report.json"]
            {
                let attachment = XCTAttachment(data: try MigrationBackupReader.file("MigrationPreview/" + name, in: preview.files), uniformTypeIdentifier: "public.json")
                attachment.name = "Planning-" + name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let rawSource = try MigrationBackupReader.values(in: backup).mapValues { value -> Any in
                if let bytes = value as? Data
                {
                    return (try? JSONSerialization.jsonObject(with: bytes)) ?? NSNull()
                }
                return value
            }
            for (name, value) in [("Records", output as Any), ("SourceValues", rawSource as Any)]
            {
                let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), uniformTypeIdentifier: "public.json")
                attachment.name = "Planning-" + name + ".json"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }


    /// @fcn MigrationPlanningTests.testAbsentAndExplicitlyEmptyStoresStayDistinct
    /// @brief Preserve source presence without fabricating daily plans, reviews or reminder defaults
    /// @return Void after zero-record and converted-store evidence checks
    /// @throws Fixture or assertion-support errors
    func testAbsentAndExplicitlyEmptyStoresStayDistinct() throws
    {

        for empty in [false, true]
        {
            try fixture(edit: { values in
                for key in MigrationPlanningPreview.stores
                {
                    values.removeValue(forKey: key)
                }
                if empty
                {
                    values["Plenact.DailyPlans.v1"] = try JSONEncoder().encode(DailyPlanStore.Document())
                }
            }) { backup, url in
                let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
                XCTAssertEqual(preview.planningRecordCount, 0)
                let evidence = try XCTUnwrap(JSONSerialization.jsonObject(with: MigrationBackupReader.file("MigrationPreview/PlanningPreview.json", in: preview.files)) as? [String: Any])
                XCTAssertEqual(evidence["converted_source_stores"] as? [String], empty ? ["Plenact.DailyPlans.v1"] : [])
            }
        }
    }


    /// @fcn MigrationPlanningTests.testMalformedPlanningDoesNotReplaceHistory
    /// @brief Reject future fields/versions, invalid counts/dates/progress and unsupported review actions
    /// @return Void after visible blockers with original data and valid content preserved
    /// @throws Fixture or assertion-support errors
    func testMalformedPlanningDoesNotReplaceHistory() throws
    {

        for variant in 0..<7
        {
            try fixture(edit: { values in
                let key = variant == 6 ? "Plenact.ReviewRhythm.v1" : "Plenact.DailyPlans.v1"
                var document = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(values[key] as? Data)) as? [String: Any])
                if variant == 6
                {
                    document["dailyMinutes"] = 1440
                }
                else if variant == 0
                {
                    document["version"] = 2
                }
                else
                {
                    var plans = try XCTUnwrap(document["plans"] as? [String: Any])
                    let id = try XCTUnwrap(plans.keys.sorted().first)
                    var plan = try XCTUnwrap(plans[id] as? [String: Any])
                    if variant == 1
                    {
                        plan["unknown"] = "future"
                    }
                    else if variant == 2
                    {
                        plan["visionStep"] = 3
                    }
                    else if variant == 3
                    {
                        plan["timeZoneID"] = "Unsupported/Zone"
                    }
                    else if variant == 4
                    {
                        var entries = try XCTUnwrap(plan["checkIns"] as? [[String: Any]])
                        entries[0]["completedTasks"] = 4
                        entries[0]["totalTasks"] = 3
                        plan["checkIns"] = entries
                    }
                    else
                    {
                        var review = try XCTUnwrap(plan["eveningReview"] as? [String: Any])
                        var decisions = try XCTUnwrap(review["decisions"] as? [[String: Any]])
                        decisions[0]["action"] = ["unknown": [:]]
                        review["decisions"] = decisions
                        plan["eveningReview"] = review
                    }
                    plans[id] = plan
                    document["plans"] = plans
                }
                values[key] = try JSONSerialization.data(withJSONObject: document)
            }) { backup, url in
                let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
                XCTAssertNil(preview.blockedContentReason)
                XCTAssertEqual(preview.planningRecordCount, 0)
                XCTAssertEqual(preview.planningReviewCount, 1)
                XCTAssertNil(preview.files.fileWrappers?["MigrationPreview"]?.fileWrappers?["PlanningPreview.json"])
                XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: backup.files),
                    try MigrationBackupReader.file("Preferences.plist", in: preview.files))
            }
        }
    }

    /// @fcn MigrationPlanningTests.testExplicitEmptyHistoryDoesNotBecomeLegacyProjection
    /// @brief Preserve null-versus-empty check-in history even when a legacy check-in is present
    /// @return Void after exact empty-array and legacy-value checks
    /// @throws Fixture or assertion-support errors
    func testExplicitEmptyHistoryDoesNotBecomeLegacyProjection() throws
    {

        try fixture(edit: { values in
            var document = try JSONDecoder().decode(DailyPlanStore.Document.self,
                from: XCTUnwrap(values["Plenact.DailyPlans.v1"] as? Data))
            for key in document.plans.keys
            {
                document.plans[key]?.checkIns = []
            }
            values["Plenact.DailyPlans.v1"] = try JSONEncoder().encode(document)
        }) { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            XCTAssertEqual(preview.planningRecordCount, 5)
            let output = try records(preview)
            for record in output where record["record_type"] as? String == "daily_plan"
            {
                let payload = try XCTUnwrap(record["payload"] as? [String: Any])
                XCTAssertEqual((payload["check_ins"] as? [Any])?.count, 0)
                XCTAssertNotNil(payload["check_in"] as? [String: Any])
            }
        }
    }


    /// @fcn MigrationPlanningTests.testInvalidReviewRangesAndDuplicateHistoryFailClosed
    /// @brief Reject invalid weekly context, reversed periods and duplicated check-in/objective identities
    /// @return Void after explicit blockers without partial planning records
    /// @throws Fixture or assertion-support errors
    func testInvalidReviewRangesAndDuplicateHistoryFailClosed() throws
    {

        for variant in 0..<4
        {
            try fixture(edit: { values in
                if variant == 0
                {
                    var doc = try JSONDecoder().decode(WeeklyReviewStore.Document.self,
                        from: XCTUnwrap(values["Plenact.WeeklyReviews.v1"] as? Data))
                    let key = try XCTUnwrap(doc.records.keys.first)
                    doc.records[key]?.step = 3
                    values["Plenact.WeeklyReviews.v1"] = try JSONEncoder().encode(doc)
                }
                else if variant == 1 || variant == 3
                {
                    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(values["Plenact.PeriodicReviews.v1"] as? Data)) as? [String: Any])
                    var entries = try XCTUnwrap(raw["records"] as? [String: Any])
                    let key = try XCTUnwrap(entries.keys.first)
                    var review = try XCTUnwrap(entries[key] as? [String: Any])
                    if variant == 1
                    {
                        review["endKey"] = "1900-01-01"
                    }
                    else
                    {
                        let objectives = try XCTUnwrap(review["objectives"] as? [[String: Any]])
                        review["objectives"] = objectives + objectives
                    }
                    entries[key] = review
                    raw["records"] = entries
                    values["Plenact.PeriodicReviews.v1"] = try JSONSerialization.data(withJSONObject: raw)
                }
                else
                {
                    var doc = try JSONDecoder().decode(DailyPlanStore.Document.self,
                        from: XCTUnwrap(values["Plenact.DailyPlans.v1"] as? Data))
                    let key = try XCTUnwrap(doc.plans.keys.sorted().first)
                    let entries = try XCTUnwrap(doc.plans[key]?.checkIns)
                    doc.plans[key]?.checkIns = entries + entries
                    values["Plenact.DailyPlans.v1"] = try JSONEncoder().encode(doc)
                }
            }) { backup, url in
                let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
                XCTAssertEqual(preview.planningRecordCount, 0)
                XCTAssertEqual(preview.planningReviewCount, 1)
            }
        }
    }


    /// @fcn MigrationPlanningTests.testEditablePlanningReconstruction
    /// @brief Rebuild saved native plans/reviews while retaining unavailable links and authored historical values
    /// @return Void after history, decisions, objectives and reminder intent assertions
    /// @throws Fixture or reconstruction failures
    func testEditablePlanningReconstruction() throws
    {

        try fixture { backup, url in
            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let output = try records(preview)
            let adapter = try PortableEditableContent(records: output, assetFiles: [:])
            let native = try adapter.planningDocuments()
            XCTAssertEqual(native.daily.plans.count, 2)
            let full = try XCTUnwrap(native.daily.plans.values.first { $0.checkIns != nil })
            XCTAssertEqual(full.intention, "  Historical intention 🌱  ")
            XCTAssertEqual(full.priorities.first?.title, "  Original priority 🪴  ")
            XCTAssertEqual(full.checkIns?.first?.intention, "Earlier intention")
            XCTAssertEqual(full.checkIns?.first?.completedTasks, 0)
            XCTAssertEqual(full.checkIns?.first?.mood?.label, " Unhurried ")
            XCTAssertTrue(native.daily.plans.values.contains { $0.checkIns == nil })
            XCTAssertEqual(full.eveningReview?.decisions.count, 8)
            XCTAssertNotEqual(full.eveningReview?.decisions.first?.result.cardID, full.priorities.first?.cardID)
            XCTAssertEqual(native.weekly.records.count, 1)
            XCTAssertEqual(native.periodic.records.count, 1)
            let periodic = try XCTUnwrap(native.periodic.records.values.first)
            XCTAssertEqual(periodic.startingObjectives.first?.progress, "Before")
            XCTAssertEqual(periodic.objectives.first?.progress, "After")
            XCTAssertEqual(periodic.startingObjectives.first?.id, periodic.objectives.first?.id)
            XCTAssertEqual(native.rhythm?.dailyMinutes, 0)
            XCTAssertEqual(native.rhythm?.dailyNotifications, true)
            var malformed = output
            let index = try XCTUnwrap(malformed.firstIndex { $0["record_type"] as? String == "daily_plan" })
            var payload = try XCTUnwrap(malformed[index]["payload"] as? [String: Any])
            payload["vision_step"] = 3
            malformed[index]["payload"] = payload
            let rejected = try PortableEditableContent(records: malformed, assetFiles: [:])
            XCTAssertThrowsError(try rejected.planningDocuments())
            let attachment = XCTAttachment(data: try JSONEncoder().encode(native.daily), uniformTypeIdentifier: "public.json")
            attachment.name = "EditablePlanning-Daily.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

}
