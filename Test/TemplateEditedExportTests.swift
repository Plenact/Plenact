// --------------------------------------------------------------------------------------------------
// @file       TemplateEditedExportTests.swift
// @brief      Isolated retained-template item creation/deletion, durable identity and recovery coverage
// @details    Uses synthetic stores and temporary containers. Personal workspaces are never read.
//             Supported User Data Model versions: 1.0 records within working 1.1 packages
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import Foundation
import XCTest


/// Exercises the production template item allocator and complete portable export/import boundary
/// @section Purpose
///     Keep new template content separate from existing owners, cancelled drafts and native aliases
@MainActor
extension MigrationStudioTests
{
    /// @fcn MigrationStudioTests.testRetainedTemplateItemCreationEditedExport
    /// @brief Add Card/Note draft items without changing retained content or the live Week
    /// @return Void after isolated defaults/container cleanup
    /// @throws Fixture, identity, export or reconstruction failures
    func testRetainedTemplateItemCreationEditedExport() throws
    {
        try retainedTemplateFixture { backup, url in

            let preview       =                                                                 /* Prepared template preview   */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package       =                                                                 /* Portable package contents   */
                try MigrationTestPackage.prepare(preview)
            let originalFiles =                                                                 /* Original files              */
                try XCTUnwrap(package.fileWrappers?["PortableTestPackage"])
            let candidate     =                                                                 /* Candidate under validation  */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: originalFiles))
            let root          =                                                                 /* Synthetic workspace root    */
                url.deletingLastPathComponent().appendingPathComponent("TemplateItemContainer")
            let stage         =                                                                 /* Isolated staging workspace  */
                url.deletingLastPathComponent().appendingPathComponent("TemplateItemStage")
            let domain        =                                                                 /* Lookup or storage namespace */
                "Plenact.TemplateItemTests." + UUID().uuidString
            let defaults      =                                                                 /* Preference store under test */
                try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {
                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)

            let previous       =                                                /* Previous value for comparison */
                try PlanningRoutineStore.load(from: defaults)
            let key            = PlanningRoutineStore.key                       /* Lookup or persistence key     */
            let originalSource = defaults.data(forKey: key)                     /* Original source               */
            let originalList   = previous.templates[0].collection.lists[0]      /* Original list                 */
            let allLists       = previous.templates[0].collection.lists         /* All lists                     */
            let instant        =                                                /* Reference timestamp           */
                Date(timeIntervalSince1970: 1793102400.123)
            var cancelled      = originalList                                   /* Cancelled comparison fixture  */

            try PlanningTemplateItemCreation.append(.card, to: &cancelled, allLists: allLists, root: root, createdAt: instant)

            let cancelledID = try XCTUnwrap(cancelled.cards.last?.id)           /* Cancelled ID */

            XCTAssertEqual(defaults.data(forKey: key), originalSource)

            var library = previous              /* Retained library contents */
            var list    = originalList          /* Synthetic list fixture    */

            try PlanningTemplateItemCreation.append(.card, to: &list, allLists: allLists, root: root, createdAt: instant)

            list.cards[list.cards.count - 1].word = "New retained template Card"

            let cardID = try XCTUnwrap(list.cards.last?.id)     /* Owner-local Card identifier */

            try PlanningTemplateItemCreation.append(.note, to: &list, allLists: allLists, root: root,
                createdAt: instant.addingTimeInterval(1))

            list.cards[list.cards.count - 1].word = "New retained template Note"

            let noteID = try XCTUnwrap(list.cards.last?.id)     /* Note ID */

            XCTAssertGreaterThan(cardID, cancelledID)
            XCTAssertGreaterThan(noteID, cardID)
            XCTAssertTrue(Set(candidate.numericIDs.values).isDisjoint(with: [cancelledID, cardID, noteID]))

            library.templates[0].collection.lists[0] = list

            try PlanningRoutineStore.save(library, baseline: previous, to: defaults)

            let source          =                                                                       /* Source value for this operation */
                try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let runtime         =                                                                       /* Retained import evidence        */
                try PortableRuntimeEvidence.capture(root: root)
            let aliasObject     =                                                                       /* Alias object                    */
                try JSONSerialization.jsonObject(with: XCTUnwrap(runtime["IdentityAliases.json"])) as! [String: Any]
            let aliases         =                                                                       /* Local-to-portable identities    */
                aliasObject["numeric_ids"] as! [String: Int]
            let cardTarget      =                                                                       /* Card target                     */
                try XCTUnwrap(aliases.first { $0.value == cardID }?.key)
            let noteTarget      =                                                                       /* Note target                     */
                try XCTUnwrap(aliases.first { $0.value == noteID }?.key)
            let cancelledTarget =                                                                       /* Cancelled target                */
                try XCTUnwrap(aliases.first { $0.value == cancelledID }?.key)
            let listTarget      =                                                                       /* List target                     */
                try XCTUnwrap(aliases.first { $0.value == list.id }?.key)
            let frozen          =                                                                       /* Immutable source snapshot       */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output          = try PortableEditedExport.prepare(frozen)                              /* Operation output                */
            let bytes           =                                                                       /* Serialized or original bytes    */
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)

            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))

            var expected      =                                                                         /* Expected operation result   */
                try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: originalFiles)) as! [String: Any]
            let actual        =                                                                         /* Observed operation result   */
                try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            var export        =                                                                         /* Prepared export evidence    */
                expected["workspace_export"] as! [String: Any]
            var base          =                                                                         /* Base value before overrides */
                export["base_workspace"] as! [String: Any]
            var planning      = base["planning"] as! [String: Any]                                      /* Planning store projection   */
            var content       = planning["content"] as! [String: Any]                                   /* Content being processed     */
            let actualBase    =                                                                         /* Actual base                 */
                (actual["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            let actualContent =                                                                         /* Actual content              */
                (actualBase["planning"] as! [String: Any])["content"] as! [String: Any]
            let additions     =                                                                         /* Filtered additions entries  */
                (actualContent["cards"] as! [[String: Any]]).filter { [cardTarget, noteTarget].contains($0["id"] as! String) }

            XCTAssertEqual(additions.count, 2)
            XCTAssertFalse((actualContent["cards"] as! [[String: Any]]).contains { $0["id"] as? String == cancelledTarget })
            for record in additions
            {
                let body = record["payload"] as! [String: Any]          /* Note or description text */

                XCTAssertEqual(body["list_id"] as? String, listTarget)
                XCTAssertEqual(body["title"] as? String, record["id"] as? String == cardTarget
                    ? "New retained template Card" : "New retained template Note")
                XCTAssertNotNil(body["source_created_at_utc"] as? String)
            }

            content["cards"] = (content["cards"] as! [[String: Any]]) + additions

            var lists   = content["lists"] as! [[String: Any]]                          /* Ordered List records     */
            let index   =                                                               /* Element position         */
                try XCTUnwrap(lists.firstIndex { $0["id"] as? String == listTarget })
            var payload = lists[index]["payload"] as! [String: Any]                     /* Canonical record payload */

            payload["card_ids"] = (payload["card_ids"] as! [String]) + [cardTarget, noteTarget]
            lists[index]["payload"] = payload
            content["lists"] = lists
            planning["content"] = content
            base["planning"] = planning
            export["base_workspace"] = base
            export["local_card_deletions"] = [String]()
            expected["workspace_export"] = export

            XCTAssertTrue(NSDictionary(dictionary: expected).isEqual(to: actual))

            let rebuilt =                                                                               /* Reconstructed output value   */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])), retainedAliases: aliases)
            let restored      =                                                                         /* Recovered state under review */
                try JSONDecoder().decode(PlanningRoutineLibrary.self, from: XCTUnwrap(rebuilt.values[key] as? Data))
            let restoredItems = restored.templates[0].collection.lists[0].cards                         /* Restored items               */

            XCTAssertEqual(restoredItems.suffix(2).map(\.word), ["New retained template Card", "New retained template Note"])
            XCTAssertEqual(restoredItems.suffix(2).map(\.presentation), [.card, .note])
            XCTAssertEqual(rebuilt.media.files, candidate.media.files)

            let fresh =                                                                         /* New isolated instance          */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
            let freshStage =                                                                    /* New isolated staging workspace */
                url.deletingLastPathComponent().appendingPathComponent("TemplateItemFresh")

            try fresh.stage(at: freshStage)
            try fresh.install(from: freshStage, root: root, defaults: defaults, domain: domain)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))

            let aliasURL     =                                                                          /* Alias URL     */
                root.appendingPathComponent(PortableRuntimeEvidence.area + "/IdentityAliases.json")
            let validAliases = try Data(contentsOf: aliasURL)                                           /* Valid aliases */

            try Data("{}".utf8).write(to: aliasURL)

            var failedDraft = originalList      /* Failed draft */

            XCTAssertThrowsError(try PlanningTemplateItemCreation.append(.card, to: &failedDraft,
                allLists: allLists, root: root, createdAt: instant))
            XCTAssertEqual(failedDraft, originalList)
            try validAliases.write(to: aliasURL)
            for name in ["Assembly.json", "Manifest.json"]
            {
                let attachment =        /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                        uniformTypeIdentifier: "public.json")

                attachment.name = "TemplateItemCreationPackage-" + name
                attachment.lifetime = .keepAlways

                add(attachment)
            }

            let wrappers  =                                                             /* Package file wrappers   */
                try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let originals =                                                             /* Retained original files */
                try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let blobs =         /* Verified original file blobs */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")

            blobs.name = "TemplateItemCreationPackage-Blobs.json"
            blobs.lifetime = .keepAlways

            add(blobs)
        }
    }

    /// @fcn MigrationStudioTests.testRetainedTemplateItemDeletionEditedExport
    /// @brief Preserve a deleted template Card in the local overlay while keeping live content unchanged
    /// @details Also rejects deletion when retained example-focus metadata still requires the target
    /// @return Void after isolated defaults and temporary-container cleanup
    /// @throws Fixture, reconstruction, export or evidence failures
    func testRetainedTemplateItemDeletionEditedExport() throws
    {
        try retainedTemplateFixture { backup, url in

            let preview        =                                                                /* Prepared template preview  */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package        =                                                                /* Portable package contents  */
                try MigrationTestPackage.prepare(preview)
            let originalFiles  =                                                                /* Original files             */
                try XCTUnwrap(package.fileWrappers?["PortableTestPackage"])
            let initial        =                                                                /* Initial operation state    */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: originalFiles))
            let initialLibrary =                                                                /* Initial library            */
                try JSONDecoder().decode(PlanningRoutineLibrary.self,
                    from: XCTUnwrap(initial.values[PlanningRoutineStore.key] as? Data))
            let targetNumber =                                                                  /* Target number              */
                initialLibrary.templates[0].collection.lists[0].cards[0].id
            let target       =                                                                  /* Target under consideration */
                try XCTUnwrap(initial.numericIDs.first { $0.value == targetNumber }?.key)
            let assembly     =                                                                  /* Assembled portable records */
                try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: originalFiles)) as! [String: Any]

            for focused in [false, true]
            {
                var baselineAssembly = assembly         /* Baseline assembly */

                if focused
                {
                    var export    =                                             /* Prepared export evidence    */
                        baselineAssembly["workspace_export"] as! [String: Any]
                    var base      =                                             /* Base value before overrides */
                        export["base_workspace"] as! [String: Any]
                    var planning  =                                             /* Planning store projection   */
                        base["planning"] as! [String: Any]
                    var templates =                                             /* Reusable planning templates */
                        planning["templates"] as! [[String: Any]]
                    let index     =                                             /* Element position            */
                        try XCTUnwrap(templates.firstIndex { $0["id"] as? String == initialLibrary.templates[0].id.uuidString.lowercased() })
                    var payload   =                                             /* Canonical record payload    */
                        templates[index]["payload"] as! [String: Any]

                    payload["example_focus"] = ["important": [String](), "bookmarked": [target], "all_day": [String]()]
                    templates[index]["payload"] = payload
                    planning["templates"] = templates
                    base["planning"] = planning
                    export["base_workspace"] = base
                    baselineAssembly["workspace_export"] = export
                }

                let baselineFiles =                                             /* Baseline files                     */
                    try PortableLocalDeletions.package(snapshot: originalFiles, assembly: baselineAssembly)
                let candidate     =                                             /* Candidate under validation         */
                    try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: baselineFiles),
                        retainedAliases: initial.numericIDs)
                let suffix   =                                                  /* Trailing display or path component */
                    focused ? "Focused" : "Plain"
                let root     =                                                  /* Synthetic workspace root           */
                    url.deletingLastPathComponent().appendingPathComponent("TemplateItemDeletion" + suffix)
                let stage    =                                                  /* Isolated staging workspace         */
                    url.deletingLastPathComponent().appendingPathComponent("TemplateItemDeletionStage" + suffix)
                let domain   =                                                  /* Lookup or storage namespace        */
                    "Plenact.TemplateItemDeletionTests." + UUID().uuidString
                let defaults =                                                  /* Preference store under test        */
                    try XCTUnwrap(UserDefaults(suiteName: domain))

                defer
                {
                    defaults.removePersistentDomain(forName: domain)
                }
                try candidate.stage(at: stage)
                try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)

                let previous =                                          /* Previous value for comparison */
                    try PlanningRoutineStore.load(from: defaults)
                var library  = previous                                 /* Retained library contents     */

                XCTAssertEqual(library.templates[0].collection.lists[0].cards.count, 1)
                library.templates[0].collection.lists[0].cards.removeAll()
                try PlanningRoutineStore.save(library, baseline: previous, to: defaults)

                let source  =                                                   /* Source value for this operation */
                    try XCTUnwrap(defaults.persistentDomain(forName: domain))
                let runtime =                                                   /* Retained import evidence        */
                    try PortableRuntimeEvidence.capture(root: root)
                let frozen  =                                                   /* Immutable source snapshot       */
                    try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)

                if focused
                {
                    XCTAssertThrowsError(try PortableEditedExport.prepare(frozen))
                    XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
                    XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
                    continue
                }

                let output = try PortableEditedExport.prepare(frozen)                                   /* Operation output             */
                let bytes  =                                                                            /* Serialized or original bytes */
                    try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)

                XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
                XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
                XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
                XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                    try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))

                var expected = baselineAssembly                         /* Expected operation result */
                var export   =                                          /* Prepared export evidence  */
                    expected["workspace_export"] as! [String: Any]

                export["local_card_deletions"] = [target]
                expected["workspace_export"] = export

                let actual =                                                            /* Observed operation result */
                    try JSONSerialization.jsonObject(with: bytes) as! [String: Any]

                XCTAssertTrue(NSDictionary(dictionary: expected).isEqual(to: actual))

                let rebuilt =                                                                   /* Reconstructed output value   */
                    try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                    XCTUnwrap(output.fileWrappers?["PortableTestPackage"])), retainedAliases: initial.numericIDs)
                let restored =                                                                  /* Recovered state under review */
                    try JSONDecoder().decode(PlanningRoutineLibrary.self,
                        from: XCTUnwrap(rebuilt.values[PlanningRoutineStore.key] as? Data))

                XCTAssertEqual(restored, library)
                XCTAssertTrue(restored.templates[0].collection.lists[0].cards.isEmpty)
                XCTAssertEqual(rebuilt.media.files, candidate.media.files)

                let fresh =                                                                     /* New isolated instance          */
                    try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                    XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
                let freshStage =                                                                /* New isolated staging workspace */
                    url.deletingLastPathComponent().appendingPathComponent("TemplateItemDeletionFresh")

                try fresh.stage(at: freshStage)
                try fresh.install(from: freshStage, root: root, defaults: defaults, domain: domain)
                XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                    PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))
                for name in ["Assembly.json", "Manifest.json"]
                {
                    let attachment =    /* Synthetic test evidence */
                        XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output),
                            uniformTypeIdentifier: "public.json")

                    attachment.name = "TemplateItemDeletionPackage-" + name
                    attachment.lifetime = .keepAlways

                    add(attachment)
                }

                let wrappers  =                                                         /* Package file wrappers   */
                    try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
                let originals =                                                         /* Retained original files */
                    try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                    ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
                })
                let blobs =     /* Verified original file blobs */
                    XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")

                blobs.name = "TemplateItemDeletionPackage-Blobs.json"
                blobs.lifetime = .keepAlways

                add(blobs)
            }
        }
    }


    /// @fcn MigrationStudioTests.testTemplateApplicationEditedExport
    /// @brief Commit two additive previews with copied links/bookmarks and independent portable identities
    /// @return Void after isolated defaults and synthetic container cleanup
    /// @throws Fixture, preview, reservation, persistence or export errors
    func testTemplateApplicationEditedExport() throws
    {
        try templateApplicationFixture(mode: .add)
    }


    /// @fcn MigrationStudioTests.testTemplateReplacementEditedExport
    /// @brief Replace active dated items while preserving archives, undated work and retained deletion evidence
    /// @return Void after isolated fixture cleanup
    /// @throws Application, reservation, persistence or export failures
    func testTemplateReplacementEditedExport() throws
    {
        try templateApplicationFixture(mode: .replace)
    }


    /// @fcn MigrationStudioTests.testRolloverReplacementReconcilesUnretainedImportance
    /// @brief Replace a newly generated Week before its first export and retain valid owner selections
    /// @return Void after isolated fixture cleanup
    /// @throws Synthetic installation, checked save or portable reconciliation errors
    func testRolloverReplacementReconcilesUnretainedImportance() throws
    {
        try retainedTemplateFixture { backup, url in

            let preview   =                                                                             /* Prepared template preview   */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package   =                                                                             /* Portable package contents   */
                try MigrationTestPackage.prepare(preview)
            let candidate =                                                                             /* Candidate under validation  */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(package.fileWrappers?["PortableTestPackage"])))
            let root     =                                                                              /* Synthetic workspace root    */
                url.deletingLastPathComponent().appendingPathComponent("RolloverReplacementContainer")
            let stage    =                                                                              /* Isolated staging workspace  */
                url.deletingLastPathComponent().appendingPathComponent("RolloverReplacementStage")
            let domain   =                                                                              /* Lookup or storage namespace */
                "Plenact.RolloverReplacementTests." + UUID().uuidString
            let defaults =                                                                              /* Preference store under test */
                try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {
                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)

            var document   =                                                                    /* Working calendar document    */
                try XCTUnwrap(PlanningCalendarStore.load(from: defaults))
            let retained   = document.weeks[0]                                                  /* State retained for recovery  */
            let date       =                                                                    /* Date used by this operation  */
                Date(timeIntervalSince1970: 1793620800)
            let generated  =                                                                    /* Generated comparison fixture */
                try PlanningRoutineStore.newWeek(for: date, calendar: document.calendar, defaults: defaults)
            let removedID  =                                                                    /* Removed ID                   */
                try XCTUnwrap(generated.collection.lists.flatMap(\.cards).first?.id)
            var template   =                                                                    /* Synthetic template fixture   */
                try PlanningRoutineStore.load(from: defaults).templates[0]
            let templateID = template.collection.lists[0].cards[0].id                           /* Template ID                  */
            let targetID   =                                                                    /* Target ID                    */
                (template.collection.lists.flatMap(\.allCards).map(\.id).max() ?? 0) + 1

            template.collection.lists[0].cards.append(KanbanCard(id: targetID,
                word: "Rollover linked target", listTitle: "Monday", presentation: .note))

            let linked =        /* Value linked to another owner */
                KanbanChecklistItem(title: "Follow copied target", content: .linkedCard(cardID: targetID))

            template.collection.lists[0].cards[0].checklists.append(KanbanChecklist(title: "Copied references", items: [linked]))

            template.exampleFocus = PlanningExampleFocus(important: [templateID], bookmarked: [templateID], allDay: [])

            let applied =                                                                       /* Result after applying changes */
                try PlanningTemplateApplication.apply(template, to: generated, date: date,
                    calendar: document.calendar, mode: .replace)
            let committed =                                                                     /* Saved operation result        */
                try PortableTemplateApplication.reserve(applied, original: generated,
                    importantIDs: PlanningTemplateApplication.exampleImportantIDs(template, in: generated), root: root)
            let week = committed.week                                                           /* Synthetic week fixture        */

            XCTAssertFalse(week.collection.lists.flatMap(\.allCards).contains { $0.id == removedID })
            document.upsert(week)

            document.currentWeekKey = week.startKey

            try PlanningCalendarStore.save(document, to: defaults)
            defaults.set(try JSONEncoder().encode(week.collection.lists), forKey: "Plenact.Board.v1")
            defaults.set(week.collection.savedCardIDs.sorted(), forKey: "Plenact.SavedCardIDs.v1")

            let oldID      = retained.collection.lists[0].cards[0].id                           /* Old ID                           */
            var importance = try JSONEncoder().encode([                                         /* Owner-qualified importance state */
                LibraryImportanceItem(collectionID: retained.id, cardID: oldID, level: 4),
                LibraryImportanceItem(collectionID: week.id, cardID: removedID, level: 3)])

            for id in committed.importantIDs
            {
                importance = LibraryImportanceSelection.settingLevel(cardID: id, collectionID: week.id, level: 1, data: importance)
            }
            defaults.set(importance, forKey: LibraryImportanceSelection.key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root)))

            let runtime   =                                                                             /* Retained import evidence     */
                try PortableRuntimeEvidence.capture(root: root)
            var malformed =                                                                             /* Malformed comparison fixture */
                try XCTUnwrap(JSONSerialization.jsonObject(with: importance) as? [[String: Any]])

            malformed[0]["unknownSelectionField"] = true

            XCTAssertThrowsError(try PortableTemplateApplication.importanceForSavedWeek(week,
                data: JSONSerialization.data(withJSONObject: malformed), root: root))

            malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: importance) as? [[String: Any]])

            malformed.append(malformed[0])
            XCTAssertThrowsError(try PortableTemplateApplication.importanceForSavedWeek(week,
                data: JSONSerialization.data(withJSONObject: malformed), root: root))

            let cleaned    =                                                            /* Normalized input value   */
                try PortableTemplateApplication.importanceForSavedWeek(week, data: importance, root: root)
            let selections =                                                            /* Retained selection state */
                try JSONDecoder().decode([LibraryImportanceItem].self, from: cleaned)

            XCTAssertEqual(selections.count, 2)
            XCTAssertTrue(selections.contains { $0.collectionID == retained.id && $0.cardID == oldID && $0.level == 4 })
            XCTAssertFalse(selections.contains { $0.collectionID == week.id && $0.cardID == removedID })
            XCTAssertEqual(cleaned, try PortableTemplateApplication.importanceForSavedWeek(week, data: cleaned, root: root))
            defaults.set(cleaned, forKey: LibraryImportanceSelection.key)

            let source   =                                                                              /* Source value for this operation  */
                try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let frozen   =                                                                              /* Immutable source snapshot        */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output   = try PortableEditedExport.prepare(frozen)                                     /* Operation output                 */
            let bytes    =                                                                              /* Serialized or original bytes     */
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)
            let repeated =                                                                              /* Result of the repeated operation */
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen))

            for (name, data) in [("RolloverLinksFirst", bytes), ("RolloverLinksRepeated", repeated)]
            {
                let attachment =                                                        /* Synthetic test evidence */
                    XCTAttachment(data: data, uniformTypeIdentifier: "public.json")

                attachment.name = name
                attachment.lifetime = .keepAlways

                add(attachment)
            }
            XCTAssertEqual(bytes, repeated)
            for _ in 0..<8
            {
                let retry =     /* Retry comparison fixture */
                    try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen))

                if bytes != retry
                {
                    let attachment =                                                            /* Synthetic test evidence */
                        XCTAttachment(data: retry, uniformTypeIdentifier: "public.json")

                    attachment.name = "RolloverLinksDivergent"
                    attachment.lifetime = .keepAlways

                    add(attachment)
                }
                XCTAssertEqual(bytes, retry)
            }
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))

            let fresh =                                                                         /* New isolated instance        */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
            let restored =                                                                      /* Recovered state under review */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(fresh.values[PlanningCalendarStore.key] as? Data))

            XCTAssertEqual(restored.weeks.count, 2)
            XCTAssertEqual(restored.weeks.first { $0.startKey == week.startKey }?.collection.lists.flatMap(\.cards).count, 2)

            let restoredWeek   =                                                                /* Restored week   */
                try XCTUnwrap(restored.weeks.first { $0.startKey == week.startKey })
            let restoredCards  = restoredWeek.collection.lists.flatMap(\.cards)                 /* Restored cards  */
            let restoredSource =                                                                /* Restored source */
                try XCTUnwrap(restoredCards.first { $0.word == "Retained template task" })
            let restoredTarget =                                                                /* Restored target */
                try XCTUnwrap(restoredCards.first { $0.word == "Rollover linked target" })

            XCTAssertEqual(restoredSource.checklists.last?.items.first?.content, .linkedCard(cardID: restoredTarget.id))
            XCTAssertEqual(restoredSource.checklists.last?.items.first?.retainedCardID, restoredTarget.id)

            let freshStage =                                                                            /* New isolated staging workspace */
                url.deletingLastPathComponent().appendingPathComponent("RolloverReplacementFresh")

            try fresh.stage(at: freshStage)
            try fresh.install(from: freshStage, root: root, defaults: defaults, domain: domain)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))
        }
    }


    /// @fcn MigrationStudioTests.testDayTemplateApplicationEditedExport
    /// @brief Add a Day template twice while retaining all other dated Lists and their selections
    /// @return Void after isolated fixture cleanup
    /// @throws Synthetic application, export or recovery errors
    func testDayTemplateApplicationEditedExport() throws
    {
        try templateApplicationFixture(mode: .add, day: true)
    }


    /// @fcn MigrationStudioTests.testDayTemplateReplacementEditedExport
    /// @brief Replace Tuesday only, preserving Monday, archives, undated work and retained deletion evidence
    /// @return Void after isolated fixture cleanup
    /// @throws Synthetic application, export or recovery errors
    func testDayTemplateReplacementEditedExport() throws
    {
        try templateApplicationFixture(mode: .replace, day: true)
    }


    /// @fcn MigrationStudioTests.templateApplicationFixture
    /// @brief Exercise production application/commit and complete export recovery for one explicit mode
    /// @param[in] mode Additive or replacement operation under test
    /// @param[in] day Select a Tuesday Day-template boundary instead of the full Week
    /// @return Void after isolated cleanup
    /// @throws Synthetic setup, application or verification failures
    private func templateApplicationFixture(mode: PlanningTemplateApplication.Mode, day: Bool = false) throws
    {
        try retainedTemplateFixture(edit: { values in

            guard mode == .replace || day else
            {
                return
            }

            var document =                                                              /* Working calendar document */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(values[PlanningCalendarStore.key] as? Data))
            var week     = document.weeks[0]                                            /* Synthetic week fixture    */
            let activeID = week.collection.lists[0].cards[0].id                         /* Active ID                 */

            week.collection.lists[0].archivedCards = [KanbanCard(id: 2, word: "Retained archived task", listTitle: "Monday", checklists: [])]

            let listID =                                                /* Owner-local List identifier */
                (week.collection.lists.map(\.id).max() ?? 0) + 1

            week.collection.lists.append(KanbanList(id: listID, title: "Retained undated work",
                cards: [KanbanCard(id: 3, word: "Retained undated task", listTitle: "Retained undated work", checklists: [])]))

            week.collection.lists[1].cards = [KanbanCard(id: 4, word: "Retained Tuesday task",
                listTitle: week.collection.lists[1].title, checklists: [])]

            if day
            {
                week.collection.lists[1].archivedCards = [KanbanCard(id: 5, word: "Retained Tuesday archive",
                    listTitle: week.collection.lists[1].title, checklists: [])]
            }

            week.collection.savedCardIDs = [activeID, 3, 4]
            document.weeks[0] = week
            values[PlanningCalendarStore.key] = try JSONEncoder().encode(document)
            values["Plenact.Board.v1"] = try JSONEncoder().encode(week.collection.lists)
            values["Plenact.SavedCardIDs.v1"] = week.collection.savedCardIDs.sorted()
        }) { backup, url in

            let preview       =                                                                         /* Prepared template preview   */
                try MigrationPreview.prepare(backup: backup, journalURL: url, timeZoneID: "America/Chicago")
            let package       =                                                                         /* Portable package contents   */
                try MigrationTestPackage.prepare(preview)
            var originalFiles =                                                                         /* Original files              */
                try XCTUnwrap(package.fileWrappers?["PortableTestPackage"])
            var candidate     =                                                                         /* Candidate under validation  */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: originalFiles))
            let root          =                                                                         /* Synthetic workspace root    */
                url.deletingLastPathComponent().appendingPathComponent("TemplateApplicationContainer")
            let stage         =                                                                         /* Isolated staging workspace  */
                url.deletingLastPathComponent().appendingPathComponent("TemplateApplicationStage")
            let domain        =                                                                         /* Lookup or storage namespace */
                "Plenact.TemplateApplicationTests." + UUID().uuidString
            let defaults      =                                                                         /* Preference store under test */
                try XCTUnwrap(UserDefaults(suiteName: domain))

            defer
            {
                defaults.removePersistentDomain(forName: domain)
            }
            try candidate.stage(at: stage)
            try candidate.install(from: stage, root: root, defaults: defaults, domain: domain)
            if mode == .replace || day
            {
                // Establish importance after owner-qualified import, without ambiguous legacy capture owners
                let imported =                                                  /* Imported isolated content  */
                    try XCTUnwrap(PlanningCalendarStore.load(from: defaults))
                let week     = imported.weeks[0]                                /* Synthetic week fixture     */
                let active   = week.collection.lists[0].cards[0].id             /* Active operation state     */
                let undated  =                                                  /* Undated comparison fixture */
                    try XCTUnwrap(week.collection.lists.first { $0.title == "Retained undated work" }?.cards.first?.id)

                defaults.set(try JSONEncoder().encode([
                    LibraryImportanceItem(collectionID: week.id, cardID: active, level: 2),
                    LibraryImportanceItem(collectionID: week.id, cardID: week.collection.lists[1].cards[0].id, level: 3),
                    LibraryImportanceItem(collectionID: week.id, cardID: undated, level: 4)]), forKey: LibraryImportanceSelection.key)

                let seeded =    /* Built-in initial content */
                    try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))

                originalFiles = try XCTUnwrap(seeded.fileWrappers?["PortableTestPackage"])
                candidate = try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files: originalFiles),
                    retainedAliases: candidate.numericIDs)

                let seededStage =                                                                       /* Seeded stage */
                    url.deletingLastPathComponent().appendingPathComponent("ReplacementSeededStage")

                try candidate.stage(at: seededStage)
                try candidate.install(from: seededStage, root: root, defaults: defaults, domain: domain)
            }

            let library  =                                                                              /* Retained library contents  */
                try PlanningRoutineStore.load(from: defaults)
            var template =                                                                              /* Synthetic template fixture */
                try XCTUnwrap(library.templates.first { day ? $0.kind == .day : $0.kind == .week })
            let sourceID = template.collection.lists[0].cards[0].id                                     /* Source ID                  */
            let linkID   =                                                                              /* Link ID                    */
                (template.collection.lists.flatMap(\.allCards).map(\.id).max() ?? 0) + 1

            // Keep this isolated export fixture independent of device-local Note photo defaults
            template.collection.lists[0].cards.append(KanbanCard(id: linkID, word: "Applied link target",
                listTitle: "Monday", presentation: .note, appearance: ItemAppearance(studioSurface: StudioSurface(material: .plain))))

            var linkedItem =                                                                            /* Linked item */
                KanbanChecklistItem(title: "Local target", content: .linkedCard(cardID: linkID))

            linkedItem.linkedCollectionID = template.collection.id

            template.collection.lists[0].cards[0].checklists.append(KanbanChecklist(title: "Copied link", items: [linkedItem]))

            template.exampleFocus = PlanningExampleFocus(important: [sourceID, linkID], bookmarked: [sourceID], allDay: [])

            var document          =                                             /* Working calendar document  */
                try XCTUnwrap(PlanningCalendarStore.load(from: defaults))
            let instant           =                                             /* Reference timestamp        */
                Date(timeIntervalSince1970: 1793016000 + (day ? 86400 : 0))
            let original          =                                             /* Baseline before changes    */
                try XCTUnwrap(document.week(for: instant))
            var current           = original                                    /* Current operation snapshot */
            var expectedImportant = Set<Int>()                                  /* Expected important         */

            for iteration in 0..<(mode == .add ? 2 : 1)
            {
                let beforePreview =                                                                     /* Before preview                */
                    try PortableRuntimeEvidence.capture(root: root)
                let applied       =                                                                     /* Result after applying changes */
                    try PlanningTemplateApplication.apply(template, to: current, date: instant,
                        calendar: document.calendar, mode: mode,
                        now: Date(timeIntervalSince1970: 1793102400.123 + Double(iteration) * 3600))
                let important =                                                                         /* Importance selection state    */
                    PlanningTemplateApplication.exampleImportantIDs(template, in: current)

                XCTAssertEqual(beforePreview, try PortableRuntimeEvidence.capture(root: root))

                let committed =                                                 /* Saved operation result */
                    try PortableTemplateApplication.reserve(applied, original: current, importantIDs: important, root: root)
                let oldIDs    =                                                 /* Old i ds               */
                    Set(current.collection.lists.flatMap(\.allCards).map(\.id))
                let newItems  =                                                 /* New items              */
                    committed.week.collection.lists.flatMap(\.allCards).filter { !oldIDs.contains($0.id) }

                XCTAssertEqual(newItems.count, 2)
                XCTAssertTrue(Set(candidate.numericIDs.values).isDisjoint(with: Set(newItems.map(\.id))))

                let linked =                                                                    /* Value linked to another owner */
                    try XCTUnwrap(newItems.first { $0.word == "Retained template task" })
                let target =                                                                    /* Target under consideration    */
                    try XCTUnwrap(newItems.first { $0.word == "Applied link target" })

                XCTAssertEqual(linked.checklists.last?.items.first?.content, .linkedCard(cardID: target.id))

                let preparedCard =      /* Prepared card */
                    try XCTUnwrap(applied.collection.lists.flatMap(\.cards).last { $0.word == "Retained template task" })

                XCTAssertEqual(linked.checklists.first?.id, preparedCard.checklists.first?.id)
                XCTAssertEqual(linked.createdAt, preparedCard.createdAt)
                XCTAssertEqual(linked.creationHistory?.context?.origin, .template(template.name))
                XCTAssertNotEqual(linked.checklists.first?.id, template.collection.lists[0].cards[0].checklists.first?.id)
                XCTAssertEqual(committed.importantIDs, Set(newItems.map(\.id)))
                XCTAssertTrue(committed.week.collection.savedCardIDs.contains(linked.id))
                XCTAssertFalse(linked.isTitleChecked)
                XCTAssertTrue(linked.comments.isEmpty)
                expectedImportant.formUnion(committed.importantIDs)

                current = committed.week

                document.upsert(current)
                try PlanningCalendarStore.save(document, to: defaults)
                defaults.set(try JSONEncoder().encode(current.collection.lists), forKey: "Plenact.Board.v1")
                defaults.set(current.collection.savedCardIDs.sorted(), forKey: "Plenact.SavedCardIDs.v1")

                var importance =                                                        /* Owner-qualified importance state */
                    try PortableTemplateApplication.importanceForSavedWeek(current,
                        data: defaults.data(forKey: LibraryImportanceSelection.key) ?? Data(), root: root)

                for id in committed.importantIDs.sorted(by: >)
                {
                    importance = LibraryImportanceSelection.settingLevel(cardID: id, collectionID: current.id, level: 1, data: importance)
                }
                defaults.set(importance, forKey: LibraryImportanceSelection.key)
            }

            let source  =                                                                               /* Source value for this operation */
                try XCTUnwrap(defaults.persistentDomain(forName: domain))
            let runtime =                                                                               /* Retained import evidence        */
                try PortableRuntimeEvidence.capture(root: root)
            let frozen  =                                                                               /* Immutable source snapshot       */
                try LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root)
            let output  = try PortableEditedExport.prepare(frozen)                                      /* Operation output                */
            let bytes   =                                                                               /* Serialized or original bytes    */
                try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: output)

            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in: PortableEditedExport.prepare(frozen)))
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: try XCTUnwrap(defaults.persistentDomain(forName: domain))))
            XCTAssertEqual(runtime, try PortableRuntimeEvidence.capture(root: root))
            XCTAssertEqual(try MigrationBackupReader.file("Preferences.plist", in: frozen.files),
                try MigrationBackupReader.file("EditedNativeBackup/Preferences.plist", in: output))

            let old         =                                                                           /* Previous operation state   */
                try JSONSerialization.jsonObject(with: MigrationBackupReader.file("Assembly.json", in: originalFiles)) as! [String: Any]
            let actual      =                                                                           /* Observed operation result  */
                try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let before      =                                                                           /* State before the operation */
                (old["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            let after       =                                                                           /* State after the operation  */
                (actual["workspace_export"] as! [String: Any])["base_workspace"] as! [String: Any]
            let oldPlanning = before["planning"] as! [String: Any]                                      /* Old planning               */
            let newPlanning = after["planning"] as! [String: Any]                                       /* New planning               */

            for key in before.keys where key != "planning" && key != "content_selections"
            {
                XCTAssertTrue(NSDictionary(dictionary: ["v": before[key]!]).isEqual(to: ["v": after[key]!]))
            }
            for key in oldPlanning.keys where key != "content" && key != "weeks"
            {
                XCTAssertTrue(NSDictionary(dictionary: ["v": oldPlanning[key]!]).isEqual(to: ["v": newPlanning[key]!]))
            }

            let newWeeks = newPlanning["weeks"] as! [[String: Any]]     /* New weeks */

            for var oldWeek in oldPlanning["weeks"] as! [[String: Any]]
            {
                var payload = oldWeek["payload"] as! [String: Any]      /* Canonical record payload */

                if payload["collection_id"] as? String == current.id.uuidString.lowercased()
                {
                    payload["explicitly_saved"] = true
                }

                oldWeek["payload"] = payload

                XCTAssertTrue(NSDictionary(dictionary: oldWeek).isEqual(to:
                    try XCTUnwrap(newWeeks.first { $0["id"] as? String == oldWeek["id"] as? String })))
            }
            XCTAssertTrue(NSDictionary(dictionary: ["v": oldPlanning["templates"]!]).isEqual(to: ["v": newPlanning["templates"]!]))
            XCTAssertTrue(NSDictionary(dictionary: ["v": oldPlanning["template_libraries"]!]).isEqual(to: ["v": newPlanning["template_libraries"]!]))

            let oldCards =                                                              /* Old cards */
                (oldPlanning["content"] as! [String: Any])["cards"] as! [[String: Any]]
            let newCards =                                                              /* New cards */
                (newPlanning["content"] as! [String: Any])["cards"] as! [[String: Any]]

            XCTAssertEqual(newCards.count, oldCards.count + (mode == .add ? 4 : 2))
            for card in oldCards
            {
                XCTAssertTrue(NSDictionary(dictionary: card).isEqual(to: try XCTUnwrap(newCards.first { $0["id"] as? String == card["id"] as? String })))
            }

            let aliases =                                                                               /* Local-to-portable identities */
                (try JSONSerialization.jsonObject(with: XCTUnwrap(runtime["IdentityAliases.json"])) as! [String: Any])["numeric_ids"] as! [String: Int]
            let rebuilt =                                                                               /* Reconstructed output value   */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])), retainedAliases: aliases)
            let rebuiltDocument =                                                                       /* Rebuilt document             */
                try JSONDecoder().decode(PlanningCalendarDocument.self,
                    from: XCTUnwrap(rebuilt.values[PlanningCalendarStore.key] as? Data))
            let rebuiltWeek = try XCTUnwrap(rebuiltDocument.week(for: instant))                         /* Rebuilt week                 */

            XCTAssertEqual(rebuiltWeek.collection.lists.flatMap(\.cards).map(\.word), current.collection.lists.flatMap(\.cards).map(\.word))
            let restoredOrigin = rebuiltWeek.collection.lists.flatMap(\.cards)
                .first { $0.word == "Applied link target" }?.creationHistory?.context?.origin

            XCTAssertEqual(restoredOrigin, .template(template.name))
            XCTAssertEqual(rebuiltWeek.collection.savedCardIDs, current.collection.savedCardIDs)
            if mode == .replace
            {
                let dated =                                                                             /* Calendar-backed owner        */
                    day ? Set([try XCTUnwrap(original.dayListIDs[PlanningDate.key(instant, calendar: document.calendar)])])
                    : Set(original.dayListIDs.values)
                let removed =                                                                           /* Entries selected for removal */
                    Set(original.collection.lists.filter { dated.contains($0.id) && !$0.isArchived }
                    .flatMap(\.cards).map(\.id))
                let aliasesByNumber =                                                                   /* Aliases by number            */
                    Dictionary(uniqueKeysWithValues: aliases.map { ($0.value, $0.key) })
                let expectedDeleted =                                                                   /* Expected deleted             */
                    Set(removed.map { aliasesByNumber[$0]! })
                let actualDeleted   =                                                                   /* Actual deleted               */
                    Set((actual["workspace_export"] as! [String: Any])["local_card_deletions"] as? [String] ?? [])

                XCTAssertEqual(actualDeleted, expectedDeleted)
                XCTAssertTrue(Set(rebuiltWeek.collection.lists.flatMap(\.cards).map(\.id)).isDisjoint(with: removed))
                for list in original.collection.lists
                {
                    let restoredList =                                                          /* Restored list */
                        try XCTUnwrap(rebuiltWeek.collection.lists.first { $0.id == list.id })

                    XCTAssertEqual(restoredList.archivedCards, list.archivedCards)
                    if !dated.contains(list.id) || list.isArchived
                    {
                        XCTAssertEqual(restoredList, list)
                    }
                }
            }
            if day
            {
                let targetListID =      /* Target list ID */
                    try XCTUnwrap(original.dayListIDs[PlanningDate.key(instant, calendar: document.calendar)])

                for list in original.collection.lists where list.id != targetListID
                {
                    XCTAssertEqual(try XCTUnwrap(rebuiltWeek.collection.lists.first { $0.id == list.id }), list)

                    let ids = Set(list.allCards.map(\.id))      /* Record identifiers */

                    XCTAssertEqual(rebuiltWeek.collection.savedCardIDs.intersection(ids), original.collection.savedCardIDs.intersection(ids))
                }

                let destination =                                                               /* Destination for the operation */
                    try XCTUnwrap(rebuiltWeek.collection.lists.first { $0.id == targetListID })

                XCTAssertEqual(destination.archivedCards, original.collection.lists.first { $0.id == targetListID }?.archivedCards)
                XCTAssertEqual(destination.cards.filter { $0.word == "Applied link target" }.count, mode == .add ? 2 : 1)
            }

            let rebuiltImportance =                                     /* Rebuilt importance */
                try JSONDecoder().decode([LibraryImportanceItem].self,
                    from: XCTUnwrap(rebuilt.values[LibraryImportanceSelection.key] as? Data))

            XCTAssertTrue(expectedImportant.isSubset(of: Set(rebuiltImportance.filter { $0.collectionID == current.id }.map(\.cardID))))
            if day
            {
                let untouchedID = original.collection.lists[0].cards[0].id      /* Untouched ID */

                XCTAssertEqual(rebuiltImportance.first { $0.collectionID == original.id && $0.cardID == untouchedID }?.level, 2)
            }
            XCTAssertEqual(rebuilt.media.files, candidate.media.files)

            let fresh =                                                                                 /* New isolated instance          */
                try PortableWorkspaceCandidate.prepare(PortablePackageReview.review(files:
                XCTUnwrap(output.fileWrappers?["PortableTestPackage"])))
            let freshStage =                                                                            /* New isolated staging workspace */
                url.deletingLastPathComponent().appendingPathComponent("TemplateApplicationFresh")

            try fresh.stage(at: freshStage)
            try fresh.install(from: freshStage, root: root, defaults: defaults, domain: domain)
            XCTAssertEqual(bytes, try MigrationBackupReader.file("PortableTestPackage/Assembly.json", in:
                PortableEditedExport.prepare(LegacyWorkspaceExport.capture(defaults: defaults, domain: domain, root: root))))

            let savedCalendar =                                                                 /* Saved calendar             */
                try XCTUnwrap(defaults.data(forKey: PlanningCalendarStore.key))
            var unsaved       =                                                                 /* Unsaved comparison fixture */
                try JSONDecoder().decode(PlanningCalendarDocument.self, from: savedCalendar)

            unsaved.weeks[0].explicitlySaved = false

            defaults.set(try JSONEncoder().encode(unsaved), forKey: PlanningCalendarStore.key)
            XCTAssertThrowsError(try PortableEditedExport.prepare(LegacyWorkspaceExport.capture(
                defaults: defaults, domain: domain, root: root)))
            defaults.set(savedCalendar, forKey: PlanningCalendarStore.key)

            let runtimeURL   =                                                                          /* Runtime URL   */
                root.appendingPathComponent(PortableRuntimeEvidence.area + "/IdentityAliases.json")
            let validAliases = try Data(contentsOf: runtimeURL)                                         /* Valid aliases */

            try Data("{}".utf8).write(to: runtimeURL)

            let retryPreview =                                                                  /* Retry preview */
                try PlanningTemplateApplication.apply(template, to: current, date: instant,
                    calendar: document.calendar, mode: .add)

            XCTAssertThrowsError(try PortableTemplateApplication.reserve(retryPreview, original: current,
                importantIDs: [], root: root))
            XCTAssertEqual(defaults.data(forKey: PlanningCalendarStore.key), savedCalendar)
            try validAliases.write(to: runtimeURL)

            let prefix =        /* Leading lookup or display text */
                day ? (mode == .add ? "DayTemplateApplicationPackage-" : "DayTemplateReplacementPackage-")
                : (mode == .add ? "TemplateApplicationPackage-" : "TemplateReplacementPackage-")

            for name in ["Assembly.json", "Manifest.json"]
            {
                let attachment =        /* Synthetic test evidence */
                    XCTAttachment(data: try MigrationBackupReader.file("PortableTestPackage/" + name, in: output), uniformTypeIdentifier: "public.json")

                attachment.name = prefix + name
                attachment.lifetime = .keepAlways

                add(attachment)
            }

            let wrappers  =                                                             /* Package file wrappers   */
                try XCTUnwrap(output.fileWrappers?["PortableTestPackage"]?.fileWrappers?["Originals"]?.fileWrappers)
            let originals =                                                             /* Retained original files */
                try Dictionary(uniqueKeysWithValues: wrappers.map { name, file in

                ("Originals/" + name, try XCTUnwrap(file.regularFileContents).base64EncodedString())
            })
            let blobs =         /* Verified original file blobs */
                XCTAttachment(data: try JSONSerialization.data(withJSONObject: originals), uniformTypeIdentifier: "public.json")

            blobs.name = prefix + "Blobs.json"
            blobs.lifetime = .keepAlways

            add(blobs)
        }
    }


    /// @fcn MigrationStudioTests.testImportanceComparisonKeepsIdentityAndUnknownValues
    /// @brief Ignore selection array order without discarding duplicates, levels or unknown fields
    /// @return Void after pure synthetic JSON comparisons
    /// @throws JSON encoding or normalization failures
    func testImportanceComparisonKeepsIdentityAndUnknownValues() throws
    {
        let key                   = LibraryImportanceSelection.key      /* Lookup or persistence key   */
        let owner                 =                                     /* Owning collection or Week   */
            "f0000000-0000-4000-8000-000000000001"
        let first: [String: Any]  =                                     /* First comparison value      */
            ["collectionID": owner, "cardID": 4]
        let second: [String: Any] =                                     /* Second comparison value     */
            ["collectionID": owner, "cardID": 9, "level": 3]
        let original              =                                     /* Baseline before changes     */
            try JSONSerialization.data(withJSONObject: [first, second])
        let reversed              =                                     /* Reversed comparison fixture */
            try JSONSerialization.data(withJSONObject: [second, first])
        let normalized            =                                     /* Comparison-normalized value */
            try PortableEditedExport.nativeJSON(original, store: key)

        XCTAssertTrue(NSDictionary(dictionary: ["v": normalized]).isEqual(to:
            ["v": try PortableEditedExport.nativeJSON(reversed, store: key)]))

        var unknown = first     /* Unrecognized input fixture */

        unknown["futureField"] = true

        for values in [[first, second, first], [unknown, second], [first, first]]
        {
            let changed =       /* Value with requested edits */
                try PortableEditedExport.nativeJSON(JSONSerialization.data(withJSONObject: values), store: key)

            XCTAssertFalse(NSDictionary(dictionary: ["v": normalized]).isEqual(to: ["v": changed]))
        }
    }
}
