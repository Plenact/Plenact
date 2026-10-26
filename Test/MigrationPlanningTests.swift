// --------------------------------------------------------------------------------------------------
// @file       MigrationPlanningTests.swift
// @brief      Historical daily/check-in/review migration and safe-reference acceptance
// @details    Supported User Data Model versions: 1.0. Synthetic plans, content and temporary
//             journals only; no actual review action, notification or owner workspace is changed.
// --------------------------------------------------------------------------------------------------
import Foundation
import XCTest
import SwiftUI
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


    /// @fcn MigrationPlanningTests.portableFixture
    /// @brief Provide rich synthetic history whose initial references pass complete package review
    /// @param[in] body Assertions receiving an isolated frozen backup and journal path
    /// @return Void after synthetic cleanup
    /// @throws Fixture preparation or assertion-support failures
    private func portableFixture(_ body: (LegacyWorkspaceBackup, URL) throws -> Void) throws
    {

        try fixture(edit: { values in

            let bytes = values["Plenact.DailyPlans.v1"] as! Data
            let document = try JSONDecoder().decode(DailyPlanStore.Document.self, from: bytes)
            let priority = document.plans.values.first { !$0.priorities.isEmpty }!.priorities[0]
            var reference = try MigrationContentValues.object(priority)
            reference["sourceCreatedAt"] = floor(priority.sourceCreatedAt!.timeIntervalSinceReferenceDate)

            /// @fcn MigrationPlanningTests.bindDailyFixture
            /// @brief Make initial package references resolvable without relaxing package review gates
            /// @param[in] value Synthetic planning subtree
            /// @return Subtree with explicit live source identity and original authored writing
            func bind(_ value: Any) -> Any
            {

                if var object = value as? [String: Any]
                {

                    if object["ownerID"] != nil, object["cardID"] != nil
                    {

                        for key in ["ownerID", "cardID", "sourceCreatedAt"]
                        {

                            object[key] = reference[key]
                        }
                    }
                    return object.mapValues(bind)
                }
                return (value as? [Any]).map { $0.map(bind) } ?? value
            }
            /// @fcn MigrationPlanningTests.exactCardDate
            /// @brief Use exactly representable creation seconds in this package fixture
            /// @param[in] value Synthetic content subtree
            /// @return Content with unchanged identity and integral creation precision
            func exact(_ value: Any) -> Any
            {

                if var object = value as? [String: Any]
                {

                    if object["word"] is String, let created = object["createdAt"] as? Double
                    {

                        object["createdAt"] = floor(created)
                    }
                    return object.mapValues(exact)
                }
                return (value as? [Any]).map { $0.map(exact) } ?? value
            }
            for key in ["Plenact.Board.v1", "Plenact.CalendarWeeks.v1"]
            {

                values[key] = try JSONSerialization.data(withJSONObject: exact(JSONSerialization.jsonObject(with: values[key] as! Data)))
            }
            for key in ["Plenact.DailyPlans.v1", "Plenact.WeeklyReviews.v1", "Plenact.PeriodicReviews.v1"]
            {

                values[key] = try JSONSerialization.data(withJSONObject: bind(JSONSerialization.jsonObject(with: values[key] as! Data)))
            }
        }, body)
    }


    /// @fcn MigrationPlanningTests.testDailyTimestampComparisonPrecision
    /// @brief Normalize only declared daily timestamps while detecting millisecond and content differences
    /// @return Void after comparison-scope and boundary assertions
    /// @throws Synthetic JSON serialization or comparison errors
    func testDailyTimestampComparisonPrecision() throws
    {

        let source = Data(#"{"updatedAt":814536000.123456,"checkIns":[{"savedAt":814536000.123456,"notes":1,"changed":"Exact reflection"}]}"#.utf8)
        let same = Data(#"{"updatedAt":814536000.123,"checkIns":[{"savedAt":814536000.123,"notes":1,"changed":"Exact reflection"}]}"#.utf8)
        let later = Data(#"{"updatedAt":814536000.124,"checkIns":[{"savedAt":814536000.123,"notes":1,"changed":"Exact reflection"}]}"#.utf8)
        let changed = Data(#"{"updatedAt":814536000.123,"checkIns":[{"savedAt":814536000.123,"notes":2,"changed":"Different reflection"}]}"#.utf8)
        let key = "Plenact.DailyPlans.v1"
        let baseline = try PortableEditedExport.nativeJSON(source, store: key) as! [String: Any]
        XCTAssertTrue(NSDictionary(dictionary: baseline).isEqual(to: try PortableEditedExport.nativeJSON(same, store: key) as! [String: Any]))
        XCTAssertFalse(NSDictionary(dictionary: baseline).isEqual(to: try PortableEditedExport.nativeJSON(later, store: key) as! [String: Any]))
        XCTAssertFalse(NSDictionary(dictionary: baseline).isEqual(to: try PortableEditedExport.nativeJSON(changed, store: key) as! [String: Any]))
        XCTAssertFalse(NSDictionary(dictionary: try PortableEditedExport.nativeJSON(source) as! [String: Any])
            .isEqual(to: try PortableEditedExport.nativeJSON(same) as! [String: Any]))
    }


    /// @fcn MigrationPlanningTests.testEveningReflectionFieldsAcceptFocusAndTyping
    /// @brief Verify native reflection controls accept focus and update the review binding
    /// @details Hosts only a synthetic review on the automated Simulator, preserving the prior window.
    /// @return Void after restoring the test window and removing the synthetic editor
    /// @throws Missing scene, control or binding errors
    func testEveningReflectionFieldsAcceptFocusAndTyping() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        var plan = DailyPlan(date: Date(timeIntervalSince1970: 1793016000))
        plan.eveningReview = DailyEveningReview(step: 2)
        let host = UIHostingController(rootView: TodayReviewView(
            plan: Binding(get: { plan }, set: { plan = $0 }), date: Date(timeIntervalSince1970: 1793016000),
            baseline: plan, onSave: { true }, onCommitted: { plan = $0 }))
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))

        /// @fcn MigrationPlanningTests.reflectionDescendants
        /// @brief Inspect public native controls without private SwiftUI class assumptions
        /// @param[in] view Hosted synthetic subtree
        /// @return Native descendant views
        func descendants(_ view: UIView) -> [UIView]
        {

            [view] + view.subviews.flatMap(descendants)
        }
        let fields = descendants(host.view).compactMap { $0 as? UITextView }
        XCTAssertEqual(fields.count, 3)
        for (index, field) in fields.enumerated()
        {

            XCTAssertTrue(field.isEditable)
            XCTAssertTrue(field.isUserInteractionEnabled)
            let point = field.convert(CGPoint(x: field.bounds.midX, y: field.bounds.midY), to: window)
            let hit = window.hitTest(point, with: nil)
            XCTAssertTrue(hit === field || hit?.isDescendant(of: field) == true)
            XCTAssertTrue(field.becomeFirstResponder())
            field.insertText("Reflection \(index)")
            try await Task.sleep(for: .milliseconds(60))
        }
        XCTAssertEqual(plan.eveningReview?.helped, "Reflection 0")
        XCTAssertEqual(plan.eveningReview?.difficult, "Reflection 1")
        XCTAssertEqual(plan.eveningReview?.tomorrow, "Reflection 2")
    }


    /// @fcn MigrationPlanningTests.testNestedEveningReflectionFieldsAcceptFocusAndTyping
    /// @brief Verify native reflection controls accept focus and update the review binding
    /// @details Hosts only a synthetic review on the automated Simulator, preserving the prior window.
    /// @return Void after restoring the test window and removing the synthetic editor
    /// @throws Missing scene, control or binding errors
    func testNestedEveningReflectionFieldsAcceptFocusAndTyping() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        var plan = DailyPlan(date: Date(timeIntervalSince1970: 1793016000))
        plan.eveningReview = DailyEveningReview(step: 2)
        let domain = "Plenact.NestedReflectionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer
        {

            defaults.removePersistentDomain(forName: domain)
        }
        defaults.set(try JSONEncoder().encode(DailyPlanStore.Document(plans: [plan.id: plan])), forKey: "Plenact.DailyPlans.v1")
        let host = UIHostingController(rootView: Color.clear.sheet(isPresented: .constant(true))
        {

            TodayPlanView(date: Date(timeIntervalSince1970: 1793016000), defaults: defaults, opensEveningReview: true)
        }.environment(\.editMode, .constant(.active)))
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1500))

        /// @fcn MigrationPlanningTests.reflectionDescendants
        /// @brief Inspect public native controls without private SwiftUI class assumptions
        /// @param[in] view Hosted synthetic subtree
        /// @return Native descendant views
        func descendants(_ view: UIView) -> [UIView]
        {

            [view] + view.subviews.flatMap(descendants)
        }
        var top: UIViewController = host
        while let presented = top.presentedViewController
        {

            top = presented
        }
        let fields = descendants(top.view).compactMap { $0 as? UITextView }
        XCTAssertEqual(fields.count, 3)
        for (index, field) in fields.enumerated()
        {

            XCTAssertTrue(field.isEditable)
            XCTAssertTrue(field.isUserInteractionEnabled)
            let point = field.convert(CGPoint(x: field.bounds.midX, y: field.bounds.midY), to: window)
            let hit = window.hitTest(point, with: nil)
            XCTAssertTrue(hit === field || hit?.isDescendant(of: field) == true)
            XCTAssertTrue(field.becomeFirstResponder())
            field.insertText("Reflection \(index)")
            try await Task.sleep(for: .milliseconds(60))
        }
        XCTAssertEqual(fields.map(\.text), ["Reflection 0", "Reflection 1", "Reflection 2"])
    }


    /// @fcn MigrationPlanningTests.testWeeklyReviewEditedExport
    /// @brief Reconcile weekly reflection writing and history without executing recorded decisions
    /// @details Covers new/retained identities, real-save precision, clearing, strict validation,
    ///          unchanged other stores, frozen evidence and fresh installation/re-export.
    /// @return Void after isolated fixture cleanup
    /// @throws Fixture, conversion or installation failures
    func testWeeklyReviewEditedExport() throws
    {

        try portableFixture { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package = try MigrationTestPackage.prepare(preview)
            let candidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(package.fileWrappers?["PortableTestPackage"])))
            let root = url.deletingLastPathComponent().appendingPathComponent("WeeklyContainer")
            let stage = url.deletingLastPathComponent().appendingPathComponent("WeeklyStage")
            let domain = "Plenact.WeeklyExportTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer
            {

                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)
            let key = "Plenact.WeeklyReviews.v1"
            var document = try JSONDecoder().decode(WeeklyReviewStore.Document.self, from: XCTUnwrap(defaults.data(forKey: key)))
            let id = try XCTUnwrap(document.records.keys.first)
            var review = try XCTUnwrap(document.records[id])
            let previousDecisions = review.decisions
            review.highlights = "Edited weekly highlights"
            review.learned = "Edited weekly learning"
            review.direction = "Edited weekly direction"
            review.constraints = "Edited weekly constraints"
            review.risks = "Edited weekly risks"
            review.step = 2
            review.updatedAt = Date(timeIntervalSince1970: 1793059200.456789)
            review.completedAt = review.updatedAt
            let priority = try XCTUnwrap(review.priorities.first)
            review.decisions.append(DailyReviewDecision(source: priority, result: priority, action: .keep,
                recordedAt: review.updatedAt!))
            document.records[id] = review
            var added = WeeklyReviewRecord(date: Date(timeIntervalSince1970: 1793620800), calendar: review.calendar)
            added.highlights = "New weekly highlights"
            added.updatedAt = review.updatedAt
            XCTAssertNil(document.records[added.id])
            document.records[added.id] = added
            defaults.set(try JSONEncoder().encode(document), forKey: key)
            let source = try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let runtime = try PortableRuntimeEvidence.capture(root: root)
            let frozen = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output = try PortableEditedExport.prepare(frozen)
            let bytes = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            let rebuilt = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
            let restoredBytes = try XCTUnwrap(rebuilt.values[key] as? Data)
            XCTAssertTrue(NSDictionary(dictionary: ["v": try PortableEditedExport.nativeJSON(JSONEncoder().encode(document), store: key)])
                .isEqual(to: ["v": try PortableEditedExport.nativeJSON(restoredBytes, store: key)]))
            let originalAssembly = try JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("Assembly.json", in: XCTUnwrap(package.fileWrappers?["PortableTestPackage"]))) as! [String: Any]
            let editedAssembly = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            var beforeBase = (originalAssembly["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            var afterBase = (editedAssembly["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            var beforePlanning = beforeBase["planning"] as! [String: Any]
            var afterPlanning = afterBase["planning"] as! [String: Any]
            let retained = beforePlanning.removeValue(forKey: "weekly_reviews") as! [[String: Any]]
            let exported = afterPlanning.removeValue(forKey: "weekly_reviews") as! [[String: Any]]
            XCTAssertTrue(exported.contains { $0["id"] as? String == retained[0]["id"] as? String })
            beforeBase["planning"] = beforePlanning
            afterBase["planning"] = afterPlanning
            XCTAssertTrue(NSDictionary(dictionary: beforeBase).isEqual(to: afterBase))
            let restored = try JSONDecoder().decode(WeeklyReviewStore.Document.self, from: restoredBytes)
            XCTAssertEqual(Array(try XCTUnwrap(restored.records[id]).decisions.dropLast()), previousDecisions)
            for (store, value) in candidate.values where store != key
            {

                if let before = value as? Data, let after = rebuilt.values[store] as? Data
                {

                    XCTAssertTrue(NSDictionary(dictionary: ["v": try PortableEditedExport.nativeJSON(before, store: store)])
                        .isEqual(to: ["v": try PortableEditedExport.nativeJSON(after, store: store)]))
                }
            }
            let fresh = url.deletingLastPathComponent().appendingPathComponent("WeeklyFreshStage")
            try rebuilt.stage(at: fresh)
            try rebuilt.install(from: fresh, root: root, defaults: defaults, domain: domain)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))
            for name in ["Assembly.json", "Manifest.json"]
            {

                let attachment = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                    uniformTypeIdentifier: "public.json")
                attachment.name = "WeeklyReviewPackage-" + name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let blobs = XCTAttachment(data: Data("{}".utf8), uniformTypeIdentifier: "public.json")
            blobs.name = "WeeklyReviewPackage-Blobs.json"
            blobs.lifetime = .keepAlways
            add(blobs)
            let valid = try XCTUnwrap(defaults.data(forKey: key))
            for patch: [String: Any] in [["step": 3], ["futureField": true], ["firstWeekday": 1],
                ["startKey": "2026-02-30"], ["timeZoneID": "Invalid/Zone"]]
            {

                var raw = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
                var records = raw["records"] as! [String: Any]
                var value = records[id] as! [String: Any]
                value.merge(patch) { _, replacement in replacement }
                records[id] = value
                raw["records"] = records
                defaults.set(try JSONSerialization.data(withJSONObject: raw), forKey: key)
                XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root)))
            }
            var cleared = restored
            cleared.records[id]?.highlights = ""
            cleared.records[id]?.learned = ""
            cleared.records[id]?.direction = ""
            cleared.records[id]?.constraints = ""
            cleared.records[id]?.risks = ""
            cleared.records[id]?.priorities = []
            cleared.records[id]?.decisions = []
            cleared.records[id]?.completedAt = nil
            defaults.set(try JSONEncoder().encode(cleared), forKey: key)
            let clearOutput = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root))
            let clearCandidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(clearOutput.fileWrappers?["PortableTestPackage"])))
            XCTAssertEqual(try JSONDecoder().decode(WeeklyReviewStore.Document.self,
                from: XCTUnwrap(clearCandidate.values[key] as? Data)).records[id], cleared.records[id])
            document.records.removeValue(forKey: id)
            defaults.set(try JSONEncoder().encode(document), forKey: key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root)))
        }
    }


    /// @fcn MigrationPlanningTests.testEveningReviewEditedExport
    /// @brief Retain reflection writing, achievements and decision history without replaying actions
    /// @details Exercises creation, existing edits, submillisecond timestamps, clearing, strict nested
    ///          validation, source immutability and fresh installation with identical re-export.
    /// @return Void after synthetic state cleanup
    /// @throws Fixture, package, capture or installation errors
    func testEveningReviewEditedExport() throws
    {

        try portableFixture { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package = try MigrationTestPackage.prepare(preview)
            let candidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(package.fileWrappers?["PortableTestPackage"])))
            let root = url.deletingLastPathComponent().appendingPathComponent("EveningContainer")
            let stage = url.deletingLastPathComponent().appendingPathComponent("EveningStage")
            let domain = "Plenact.EveningExportTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer
            {

                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)
            let key = "Plenact.DailyPlans.v1"
            var document = try JSONDecoder().decode(DailyPlanStore.Document.self, from: XCTUnwrap(defaults.data(forKey: key)))
            let date = try XCTUnwrap(document.plans.keys.sorted().first)
            let other = try XCTUnwrap(document.plans.keys.sorted().last)
            var review = try XCTUnwrap(document.plans[date]?.eveningReview)
            let decisions = review.decisions
            review.helped = "Edited evening reflection"
            review.difficult = "A synthetic difficulty"
            review.tomorrow = "A synthetic next step"
            review.step = 2
            let instant = Date(timeIntervalSince1970: 1793059200.654321)
            review.completedAt = instant
            let priority = try XCTUnwrap(document.plans[date]?.priorities.first)
            review.achievements = [priority]
            review.decisions.append(DailyReviewDecision(source: priority, result: priority,
                action: .date("2026-10-28"), recordedAt: instant))
            document.plans[date]?.eveningReview = review
            document.plans[date]?.updatedAt = instant
            document.plans[other]?.eveningReview = DailyEveningReview(helped: "New evening reflection")
            document.plans[other]?.updatedAt = instant
            defaults.set(try JSONEncoder().encode(document), forKey: key)
            let source = try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let runtime = try PortableRuntimeEvidence.capture(root: root)
            let frozen = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output = try PortableEditedExport.prepare(frozen)
            let bytes = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            let rebuilt = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
            let restored = try JSONDecoder().decode(DailyPlanStore.Document.self, from: XCTUnwrap(rebuilt.values[key] as? Data))
            let original = try JSONDecoder().decode(DailyPlanStore.Document.self,
                from: XCTUnwrap(candidate.values[key] as? Data))
            var unaffected = restored
            for day in original.plans.keys
            {

                unaffected.plans[day]?.eveningReview = original.plans[day]?.eveningReview
                unaffected.plans[day]?.updatedAt = original.plans[day]?.updatedAt
            }
            XCTAssertEqual(unaffected.version, original.version)
            XCTAssertEqual(unaffected.plans, original.plans)
            let saved = try XCTUnwrap(restored.plans[date]?.eveningReview)
            XCTAssertEqual(saved.helped, review.helped)
            XCTAssertEqual(saved.difficult, review.difficult)
            XCTAssertEqual(saved.tomorrow, review.tomorrow)
            XCTAssertEqual(saved.step, 2)
            XCTAssertEqual(saved.achievements, review.achievements)
            XCTAssertEqual(Array(saved.decisions.dropLast()), decisions)
            XCTAssertEqual(saved.decisions.last?.id, review.decisions.last?.id)
            XCTAssertEqual(saved.decisions.last?.action, .date("2026-10-28"))
            XCTAssertEqual(saved.completedAt, Date(timeIntervalSince1970: 1793059200.654))
            XCTAssertEqual(saved.decisions.last?.recordedAt, saved.completedAt)
            XCTAssertEqual(restored.plans[other]?.eveningReview?.helped, "New evening reflection")
            for (store, value) in candidate.values where store != key
            {

                if let before = value as? Data, let after = rebuilt.values[store] as? Data
                {

                    XCTAssertTrue(NSDictionary(dictionary: ["v": try PortableEditedExport.nativeJSON(before, store: store)])
                        .isEqual(to: ["v": try PortableEditedExport.nativeJSON(after, store: store)]))
                }
            }
            let fresh = url.deletingLastPathComponent().appendingPathComponent("EveningFreshStage")
            try rebuilt.stage(at: fresh)
            try rebuilt.install(from: fresh, root: root, defaults: defaults, domain: domain)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))
            for name in ["Assembly.json", "Manifest.json"]
            {

                let attachment = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                    uniformTypeIdentifier: "public.json")
                attachment.name = "EveningReviewPackage-" + name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let blobs = XCTAttachment(data: Data("{}".utf8), uniformTypeIdentifier: "public.json")
            blobs.name = "EveningReviewPackage-Blobs.json"
            blobs.lifetime = .keepAlways
            add(blobs)
            let duplicate = try MigrationContentValues.object(review.decisions[0])
            for patch: [String: Any] in [["step": 3], ["futureField": true], ["decisions": [duplicate, duplicate]]]
            {

                var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as! [String: Any]
                var plans = raw["plans"] as! [String: Any]
                var plan = plans[date] as! [String: Any]
                var evening = plan["eveningReview"] as! [String: Any]
                evening.merge(patch) { _, replacement in replacement }
                plan["eveningReview"] = evening
                plans[date] = plan
                raw["plans"] = plans
                defaults.set(try JSONSerialization.data(withJSONObject: raw), forKey: key)
                XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root)))
            }
            var invalidDate = restored
            invalidDate.plans[date]?.eveningReview?.decisions.append(DailyReviewDecision(
                source: priority, result: priority, action: .date("2026-02-30"), recordedAt: instant))
            defaults.set(try JSONEncoder().encode(invalidDate), forKey: key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root)))
            for remove in [false, true]
            {

                var cleared = restored
                cleared.plans[date]?.eveningReview = remove ? nil : DailyEveningReview()
                defaults.set(try JSONEncoder().encode(cleared), forKey: key)
                let clearedOutput = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root))
                let clearCandidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                    XCTUnwrap(clearedOutput.fileWrappers?["PortableTestPackage"])))
                let clearDocument = try JSONDecoder().decode(DailyPlanStore.Document.self,
                    from: XCTUnwrap(clearCandidate.values[key] as? Data))
                XCTAssertEqual(clearDocument.plans[date]?.eveningReview, cleared.plans[date]?.eveningReview)
            }
        }
    }


    /// @fcn MigrationPlanningTests.testDailyPlanEditedExport
    /// @brief Preserve daily writing, historical references and new check-ins through verified export
    /// @details Uses isolated rich history with explicit references and new dates, plus rejected provenance,
    ///          malformed sources, frozen-source checks and fresh installation/re-export.
    /// @return Void after synthetic state cleanup
    /// @throws Fixture, conversion, installation or assertion-support failures
    func testDailyPlanEditedExport() throws
    {

        try portableFixture { backup, url in

            let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package = try MigrationTestPackage.prepare(preview)
            let reviewed = try PortablePackageReview.review(files: XCTUnwrap(package.fileWrappers?["PortableTestPackage"]))
            let candidate = try PortableWorkspaceCandidate.prepare(reviewed)
            let root = url.deletingLastPathComponent().appendingPathComponent("DailyExportContainer")
            let stage = url.deletingLastPathComponent().appendingPathComponent("DailyExportStage")
            let domain = "Plenact.DailyExportTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer
            {

                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)
            let key = "Plenact.DailyPlans.v1"
            var document = try JSONDecoder().decode(DailyPlanStore.Document.self, from: XCTUnwrap(defaults.data(forKey: key)))
            let unchanged = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root))
            let originalAssembly = try JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("Assembly.json", in: XCTUnwrap(package.fileWrappers?["PortableTestPackage"]))) as! [String: Any]
            let unchangedAssembly = try JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: unchanged)) as! [String: Any]
            let originalBase = (originalAssembly["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            let unchangedBase = (unchangedAssembly["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            XCTAssertTrue(NSDictionary(dictionary: originalBase).isEqual(to: unchangedBase))
            let date = try XCTUnwrap(document.plans.keys.sorted().first)
            var plan = try XCTUnwrap(document.plans[date])
            let retainedHistory = plan.checkInHistory
            plan.intention = "Edited synthetic intention"
            plan.constraints = "Edited synthetic constraints"
            plan.concerns = ""
            plan.updatedAt = Date(timeIntervalSince1970: 1792843200.123456)
            plan.recordCheckIn(changed: "New synthetic check-in", sources: [], at: plan.updatedAt!,
                mood: CheckInMood(emoji: "🌱", label: "Steady"))
            document.plans[date] = plan
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Chicago")!
            var added = DailyPlan(date: Date(timeIntervalSince1970: 1793016000), calendar: calendar)
            added.intention = "New synthetic daily plan"
            added.updatedAt = plan.updatedAt
            XCTAssertNil(document.plans[added.id])
            document.plans[added.id] = added
            defaults.set(try JSONEncoder().encode(document), forKey: key)
            let source = try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let runtime = try PortableRuntimeEvidence.capture(root: root)
            let frozen = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output = try PortableEditedExport.prepare(frozen)
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))
            let bytes = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)
            let repeated = try PortableEditedExport.prepare(frozen)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: repeated))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            let rebuilt = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
            let restored = try JSONDecoder().decode(DailyPlanStore.Document.self, from: XCTUnwrap(rebuilt.values[key] as? Data))
            var projected = plan
            projected.updatedAt = Date(timeIntervalSince1970: 1792843200.123)
            projected.checkIn?.savedAt = projected.updatedAt
            if var entries = projected.checkIns, let last = entries.popLast()
            {

                entries.append(DailyCheckInEntry(id: last.id, savedAt: projected.updatedAt!, changed: last.changed,
                    focus: last.focus, intention: last.intention, constraints: last.constraints, concerns: last.concerns,
                    priorities: last.priorities, completedTasks: last.completedTasks, totalTasks: last.totalTasks,
                    notes: last.notes, unavailable: last.unavailable, legacy: last.legacy, mood: last.mood))
                projected.checkIns = entries
            }
            XCTAssertEqual(restored.plans[date], projected)
            var projectedAdded = added
            projectedAdded.updatedAt = projected.updatedAt
            XCTAssertEqual(restored.plans[added.id], projectedAdded)
            XCTAssertEqual(Array(try XCTUnwrap(restored.plans[date]).checkInHistory.dropLast()), retainedHistory)
            for (store, value) in candidate.values where store != key
            {

                if let before = value as? Data, let after = rebuilt.values[store] as? Data
                {

                    XCTAssertTrue(NSDictionary(dictionary: ["v": try PortableEditedExport.nativeJSON(before, store: store)])
                        .isEqual(to: ["v": try PortableEditedExport.nativeJSON(after, store: store)]))
                }
            }
            let fresh = url.deletingLastPathComponent().appendingPathComponent("DailyExportFreshStage")
            try rebuilt.stage(at: fresh)
            try rebuilt.install(from: fresh, root: root, defaults: defaults, domain: domain)
            let reexport = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root))
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: reexport))
            for name in ["Assembly.json", "Manifest.json"]
            {

                let attachment = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                    uniformTypeIdentifier: "public.json")
                attachment.name = "DailyPlanPackage-" + name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let wrappers = try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let originals = try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let blobs = XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")
            blobs.name = "DailyPlanPackage-Blobs.json"
            blobs.lifetime = .keepAlways
            add(blobs)
            let retainedValid = try XCTUnwrap(defaults.data(forKey: key))
            var cleared = restored
            cleared.plans[date]?.intention = ""
            cleared.plans[date]?.priorities = []
            cleared.plans[date]?.checkIn = nil
            cleared.plans[date]?.checkIns = []
            defaults.set(try JSONEncoder().encode(cleared), forKey: key)
            let clearOutput = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root))
            let clearCandidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(clearOutput.fileWrappers?["PortableTestPackage"])))
            let clearDocument = try JSONDecoder().decode(DailyPlanStore.Document.self, from: XCTUnwrap(clearCandidate.values[key] as? Data))
            XCTAssertEqual(clearDocument.plans[date], cleared.plans[date])
            defaults.set(retainedValid, forKey: key)
            let valid = try XCTUnwrap(defaults.data(forKey: key))
            var raw = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
            var plans = raw["plans"] as! [String: Any]
            var changed = plans[date] as! [String: Any]
            changed["futureField"] = true
            plans[date] = changed
            raw["plans"] = plans
            defaults.set(try JSONSerialization.data(withJSONObject: raw), forKey: key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root)))
            for patch: [String: Any] in [["ownerID": UUID().uuidString], ["cardID": 999999],
                ["sourceCreatedAt": 1.0]]
            {

                var invalid = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
                var plans = invalid["plans"] as! [String: Any]
                var changed = plans[date] as! [String: Any]
                var priorities = changed["priorities"] as! [[String: Any]]
                XCTAssertFalse(priorities.isEmpty)
                priorities[0].merge(patch) { _, replacement in replacement }
                changed["priorities"] = priorities
                plans[date] = changed
                invalid["plans"] = plans
                defaults.set(try JSONSerialization.data(withJSONObject: invalid), forKey: key)
                XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root)))
            }
            for patch: [String: Any] in [["timeZoneID": "Invalid/Zone"], ["id": "2026-02-30"], ["visionStep": 3]]
            {

                var invalid = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
                var plans = invalid["plans"] as! [String: Any]
                var changed = plans[date] as! [String: Any]
                changed.merge(patch) { _, replacement in replacement }
                plans[date] = changed
                invalid["plans"] = plans
                defaults.set(try JSONSerialization.data(withJSONObject: invalid), forKey: key)
                XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root)))
            }
            document.plans.removeValue(forKey: date)
            defaults.set(try JSONEncoder().encode(document), forKey: key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root)))
        }
    }

}


/// Planning-preference export regression sharing the isolated Studio package fixture.
/// @section Purpose
///     Keep planning coverage separate without growing the combined activation/recovery test.
@MainActor
extension MigrationStudioTests
{

    /// @fcn MigrationStudioTests.testReviewRhythmEditedExport
    /// @brief Verify newly saved and retained rhythm preferences through complete isolated export
    /// @details Checks all seven choices, identity, unchanged history, source immutability, strict
    ///          rejection and fresh installation/re-export without invoking notification scheduling.
    /// @return Void after temporary synthetic stores and files are removed
    /// @throws Fixture, package, capture or installation failures
    func testReviewRhythmEditedExport() throws
    {

        for existing in [false, true]
        {

            try fixture(edit: { values in

                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "America/Chicago")!
                calendar.firstWeekday = 2
                let week = DatedPlanningWeek.make(for: Date(timeIntervalSince1970: 1792843200),
                    lists: [KanbanList(id: 1, title: "Monday", cards: [])], calendar: calendar)
                values["Plenact.Board.v1"] = try JSONEncoder().encode(week.collection.lists)
                values["Plenact.CalendarWeeks.v1"] = try JSONEncoder().encode(
                    PlanningCalendarDocument(currentWeekKey: week.startKey, firstWeekday: 2, weeks: [week]))
                var plan = DailyPlan(date: Date(timeIntervalSince1970: 1792843200), calendar: calendar)
                plan.intention = "Retain synthetic planning history"
                plan.updatedAt = Date(timeIntervalSince1970: 1792843200)
                values["Plenact.DailyPlans.v1"] = try JSONEncoder().encode(DailyPlanStore.Document(plans: [plan.id: plan]))
                if existing
                {

                    values["Plenact.ReviewRhythm.v1"] = try JSONEncoder().encode(ReviewRhythmPreferences())
                }
            }) { backup, url in

                let preview = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
                let package = try MigrationTestPackage.prepare(preview)
                let reviewed = try PortablePackageReview.review(files: XCTUnwrap(package.fileWrappers?["PortableTestPackage"]))
                let candidate = try PortableWorkspaceCandidate.prepare(reviewed)
                let root = url.deletingLastPathComponent().appendingPathComponent("RhythmContainer")
                let stage = url.deletingLastPathComponent().appendingPathComponent("RhythmStage")
                let domain = "Plenact.RhythmExportTests." + UUID().uuidString
                let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
                defer
                {

                    defaults.removePersistentDomain(forName: domain)
                }
                try candidate.stage(at: stage)
                try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)
                let key = "Plenact.ReviewRhythm.v1"
                let runtime = try PortableRuntimeEvidence.capture(root: root)
                defaults.set(try JSONEncoder().encode(ReviewRhythmPreferences()), forKey: key)
                let defaultOutput = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root))
                let defaultCandidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                    XCTUnwrap(defaultOutput.fileWrappers?["PortableTestPackage"])))
                XCTAssertEqual(try JSONDecoder().decode(ReviewRhythmPreferences.self,
                    from: XCTUnwrap(defaultCandidate.values[key] as? Data)), ReviewRhythmPreferences())
                var rhythm = ReviewRhythmPreferences()
                rhythm.dailyInvitations = false
                rhythm.weeklyInvitations = false
                rhythm.dailyMinutes = 17
                rhythm.weeklyMinutes = 1439
                rhythm.weeklyWeekday = 7
                rhythm.dailyNotifications = true
                rhythm.weeklyNotifications = true
                defaults.set(try JSONEncoder().encode(rhythm), forKey: key)
                let source = try XCTUnwrap(defaults.persistentDomain(forName: domain))
                let frozen = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
                let output = try PortableEditedExport.prepare(frozen)
                let bytes = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)
                let repeated = try PortableEditedExport.prepare(frozen)
                XCTAssertEqual(try PortableRuntimeEvidence.capture(root: root), runtime)
                XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: repeated))
                XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
                let originalAssembly = try JSONSerialization.jsonObject(with:
                    MigrationBackupReader.file("Assembly.json", in: XCTUnwrap(package.fileWrappers?["PortableTestPackage"]))) as! [String: Any]
                let editedAssembly = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
                var originalExport = originalAssembly["workspace_export"] as! [String: Any]
                var editedExport = editedAssembly["workspace_export"] as! [String: Any]
                var originalBase = originalExport["base_workspace"] as! [String: Any]
                var editedBase = editedExport["base_workspace"] as! [String: Any]
                var originalPlanning = originalBase["planning"] as! [String: Any]
                var editedPlanning = editedBase["planning"] as! [String: Any]
                let previous = originalPlanning.removeValue(forKey: "review_rhythms") as! [[String: Any]]
                let changed = editedPlanning.removeValue(forKey: "review_rhythms") as! [[String: Any]]
                XCTAssertEqual(changed.count, 1)
                if existing
                {

                    XCTAssertEqual(previous.first?["id"] as? String, changed.first?["id"] as? String)
                }
                originalBase["planning"] = originalPlanning
                editedBase["planning"] = editedPlanning
                originalExport["base_workspace"] = originalBase
                editedExport["base_workspace"] = editedBase
                originalExport.removeValue(forKey: "local_card_deletions")
                editedExport.removeValue(forKey: "local_card_deletions")
                XCTAssertTrue(NSDictionary(dictionary: originalExport).isEqual(to: editedExport))
                let rebuilt = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                    XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
                XCTAssertEqual(try JSONDecoder().decode(ReviewRhythmPreferences.self,
                    from: XCTUnwrap(rebuilt.values[key] as? Data)), rhythm)
                let freshStage = url.deletingLastPathComponent().appendingPathComponent("RhythmFreshStage")
                try rebuilt.stage(at: freshStage)
                try rebuilt.install(from: freshStage, root: root, defaults: defaults, domain: domain)
                let reexport = try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root))
                XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: reexport))
                for name in ["Assembly.json", "Manifest.json"]
                {

                    let item = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                        uniformTypeIdentifier: "public.json")
                    item.name = (existing ? "RetainedRhythmPackage-" : "NewRhythmPackage-") + name
                    item.lifetime = .keepAlways
                    add(item)
                }
                let originals = try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
                let blobs = try Dictionary(uniqueKeysWithValues: originals.map { name, file in

                    ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
                })
                let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: blobs, options: .sortedKeys),
                    uniformTypeIdentifier: "public.json")
                attachment.name = (existing ? "RetainedRhythmPackage-" : "NewRhythmPackage-") + "Blobs.json"
                attachment.lifetime = .keepAlways
                add(attachment)
                let valid = try XCTUnwrap(defaults.data(forKey: key))
                for patch: [String: Any] in [["dailyMinutes": -1], ["weeklyMinutes": 1440],
                    ["weeklyWeekday": 0], ["dailyInvitations": "false"], ["futureField": true]]
                {

                    var raw = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
                    raw.merge(patch) { _, replacement in replacement }
                    defaults.set(try JSONSerialization.data(withJSONObject: raw), forKey: key)
                    XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                        defaults: defaults, domain: domain, root: root)))
                }
                var incomplete = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
                incomplete.removeValue(forKey: "dailyNotifications")
                defaults.set(try JSONSerialization.data(withJSONObject: incomplete), forKey: key)
                XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root)))
                defaults.removeObject(forKey: key)
                XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                    defaults: defaults, domain: domain, root: root)))
            }
        }
    }


}
