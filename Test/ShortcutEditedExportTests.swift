// --------------------------------------------------------------------------------------------------
// @file       ShortcutEditedExportTests.swift
// @brief      Owner-qualified Today shortcut edits, rollover and portable recovery
// @details    Uses isolated synthetic preferences/media only. No personal archives or live stores
// --------------------------------------------------------------------------------------------------
import Foundation
import XCTest
@testable import Plenact


/// Exercises the shortcut adapter through complete frozen export and fresh installation
/// @section Purpose
///     Preserve authored order without guessing owners or silently normalizing invalid references
@MainActor
extension MigrationStudioTests
{


    /// @fcn MigrationStudioTests.testTodayShortcutEditedExport
    /// @brief Create, reorder, replace and clear shortcuts, then pin a newly generated Week
    /// @return Void after isolated source/container cleanup
    /// @throws Fixture, export, identity, reconstruction or recovery errors
    func testTodayShortcutEditedExport() throws
    {

        try retainedTemplateFixture(edit:
        {
            values in

            var collection = PersonalCollection(title: "Synthetic shortcut owner", kind: .board)

            collection.lists = [KanbanList(id: 1, title: "Synthetic personal target", cards: [])]
            values["Plenact.PersonalCollections.v1"] = try JSONEncoder().encode([collection])

        })
        {
            backup, url in

            let preview   = try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package   = try MigrationTestPackage.prepare(preview)
            var candidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(package.fileWrappers?["PortableTestPackage"])))
            let root     = url.deletingLastPathComponent().appendingPathComponent("ShortcutContainer")
            let stage    = url.deletingLastPathComponent().appendingPathComponent("ShortcutStage")
            let domain   = "Plenact.ShortcutExportTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {

                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)
            XCTAssertNil(defaults.object(forKey: TodayListPins.key))

            var previous = try JSONSerialization.jsonObject(with:
                MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: package)) as! [String: Any]
            var singletonID: String?
            var output: FileWrapper?

            for phase in 0..<6
            {

                var calendar = try XCTUnwrap(PlanningCalendarStore.load(from: defaults))
                let personal = try JSONDecoder().decode([PersonalCollection].self,
                    from: XCTUnwrap(defaults.data(forKey: "Plenact.PersonalCollections.v1")))[0]
                let retainedWeek = calendar.weeks[0]
                let weekPins     = retainedWeek.collection.lists.map { WorkspaceListReference(ownerID: retainedWeek.id, listID: $0.id) }
                let personalPin  = WorkspaceListReference(ownerID: personal.id, listID: personal.lists[0].id)
                let pins: [WorkspaceListReference]

                switch phase
                {

                case 0:

                    pins = []

                case 1:

                    pins = [weekPins[0], personalPin]

                case 2:

                    pins = [personalPin, weekPins[0]]

                case 3:

                    pins = Array(weekPins.prefix(6))

                case 4:

                    pins = []

                default:

                    let date    = Date(timeIntervalSince1970: 1793620800)
                    let newWeek = try PlanningRoutineStore.newWeek(for: date, calendar: calendar.calendar, defaults: defaults)

                    calendar.upsert(newWeek)

                    calendar.currentWeekKey = newWeek.startKey

                    try PlanningCalendarStore.save(calendar, to: defaults)
                    defaults.set(try JSONEncoder().encode(newWeek.collection.lists), forKey: "Plenact.Board.v1")
                    defaults.set(newWeek.collection.savedCardIDs.sorted(), forKey: "Plenact.SavedCardIDs.v1")

                    pins = [WorkspaceListReference(ownerID: newWeek.id, listID: newWeek.collection.lists[0].id),
                        personalPin, weekPins[0]]

                }
                defaults.set(TodayListPins.encode(pins), forKey: TodayListPins.key)

                let source   = try XCTUnwrap(defaults.persistentDomain(forName: domain))
                let runtime  = try PortableRuntimeEvidence.capture(root: root)
                let frozen   = try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
                let exported = try PortableEditedExport.prepare(frozen)
                let bytes    = try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: exported)

                XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
                XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
                XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
                XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                    try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: exported))

                let actual   = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
                let export   = actual["workspace_export"] as! [String: Any]
                var base     = export["base_workspace"] as! [String: Any]
                let shortcut = try XCTUnwrap(base["today_shortcuts"] as? [String: Any])
                let id       = try XCTUnwrap(shortcut["id"] as? String)

                if let singletonID
                {

                    XCTAssertEqual(id, singletonID)
                }
                else
                {

                    XCTAssertEqual(id, try PortableRichCardExport.identity(namespace: candidate.workspaceID,
                        name: "today_shortcuts:" + TodayListPins.key))

                    singletonID = id

                }

                let items = (shortcut["payload"] as! [String: Any])["items"] as! [[String: Any]]

                XCTAssertEqual(items.map { $0["collection_id"] as! String }, pins.map { $0.ownerID.uuidString.lowercased() })
                if phase < 5
                {

                    let priorExport = previous["workspace_export"] as! [String: Any]
                    var priorBase   = priorExport["base_workspace"] as! [String: Any]

                    base["today_shortcuts"] = NSNull()
                    priorBase["today_shortcuts"] = NSNull()

                    let changedGroups = Set(base.keys).union(priorBase.keys).filter
                    {

                        !NSDictionary(dictionary: ["value": base[$0] ?? NSNull()])
                            .isEqual(to: ["value": priorBase[$0] ?? NSNull()])
                    }

                    XCTAssertTrue(changedGroups.isEmpty, "Unexpected changed groups: " + changedGroups.sorted().joined(separator: ", "))

                    let retained = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                        XCTUnwrap(exported.fileWrappers?["PortableTestPackage"])), retainedAliases: candidate.numericIDs)

                    XCTAssertEqual(try JSONDecoder().decode([WorkspaceListReference].self,
                        from: XCTUnwrap(retained.values[TodayListPins.key] as? Data)), pins)
                }

                let fresh = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                    XCTUnwrap(exported.fileWrappers?["PortableTestPackage"])))

                XCTAssertEqual(fresh.media.files, candidate.media.files)

                let freshStage = url.deletingLastPathComponent().appendingPathComponent("ShortcutStage-" + String(phase))

                try fresh.stage(at: freshStage)
                try fresh.install(from: freshStage, root: root, defaults: defaults, domain: domain)
                XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                    PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))

                candidate = fresh
                previous = actual
                output = exported

            }

            let saved   = try XCTUnwrap(defaults.data(forKey: TodayListPins.key))
            let pins    = try JSONDecoder().decode([WorkspaceListReference].self, from: saved)
            let raw     = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [[String: Any]])
            var unknown = raw[0]

            unknown["futureField"] = true

            var wrongOwner = raw[0]

            wrongOwner["ownerID"] = UUID().uuidString

            var wrongList = raw[0]

            wrongList["listID"] = Int.max

            var fractional = raw[0]

            fractional["listID"] = 0.5

            var mismatchedOwner = raw[0]

            mismatchedOwner["ownerID"] = pins[1].ownerID.uuidString

            for invalid in [[raw[0], raw[0]], [unknown], [wrongOwner], [wrongList], [fractional],
                [mismatchedOwner], Array(repeating: raw[0], count: 7)]
            {

                defaults.set(try JSONSerialization.data(withJSONObject: invalid), forKey: TodayListPins.key)

                let before  = try XCTUnwrap(defaults.persistentDomain(forName: domain))
                let runtime = try PortableRuntimeEvidence.capture(root: root)

                XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)))
                XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
                XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            }
            defaults.removeObject(forKey: TodayListPins.key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)))
            defaults.set(saved, forKey: TodayListPins.key)
            for name in ["Assembly.json", "Manifest.json"]
            {

                let attachment = XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name,
                    in: XCTUnwrap(output)), uniformTypeIdentifier: "public.json")

                attachment.name = "ShortcutsPackage-" + name
                attachment.lifetime = .keepAlways

                add(attachment)
            }

            let wrappers  = try XCTUnwrap(output?.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let originals = try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let blobs = XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")

            blobs.name = "ShortcutsPackage-Blobs.json"
            blobs.lifetime = .keepAlways

            add(blobs)
        }
    }
}
