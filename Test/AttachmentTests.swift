// --------------------------------------------------------------------------------------------------
// @file       AttachmentTests.swift
// @brief      Attachment regression tests
// @details    Verifies related workspace behavior with synthetic fixtures and the shared
//             PlenactBoardDocumentTests helpers. Retains original test identities and checked
//             assertions while separating this coverage from unrelated feature tests.
//
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import AVFoundation
import PencilKit
import SwiftUI
import UserNotifications
import XCTest


///
/// Attachment regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanningTemplateMediaRetentionAndWorkspaceBackup
    /// @brief      Verify that planning Template Media Retention And Workspace Backup
    /// @details    Exercises `PlanningRoutineStore.load`, `PlanningRoutineStore.save`,
    ///             `PlanningRoutineStore.retainedFiles`. Checks `XCTAssertEqual(try
    ///             PlanningRoutineStore.retainedFiles(from: defaults), ["routine-preview.png",
    ///             "routine-strokes.drawing"])`; `XCTAssertNil(defaults.object(forKey: PlanningRoutineStore.key))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPlanningTemplateMediaRetentionAndWorkspaceBackup() throws
    {

        let name = "Plenact.RoutineBackupTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer
        {
            defaults.removePersistentDomain(forName: name);
            try? FileManager.default.removeItem(at: folder)
        }

        let baseline = try PlanningRoutineStore.load(from: defaults)
        var library = baseline
        var attachment = KanbanAttachment(fileName: "routine-preview.png", mediaKind: .photo)
        attachment.drawingFileName = "routine-strokes.drawing"
        library.templates[1].collection.lists[0].cards[0].attachments = [attachment]
        try PlanningRoutineStore.save(library, baseline: baseline, to: defaults)
        XCTAssertEqual(
            try PlanningRoutineStore.retainedFiles(from: defaults), ["routine-preview.png", "routine-strokes.drawing"])
        let bytes = try XCTUnwrap(defaults.data(forKey: PlanningRoutineStore.key))
        let documents = folder.appendingPathComponent("Documents")
        let media = documents.appendingPathComponent("CardAttachments")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let preview = Data("saved PNG preview".utf8), strokes = Data("editable native strokes".utf8)
        try preview.write(to: media.appendingPathComponent("routine-preview.png"))
        try strokes.write(to: media.appendingPathComponent("routine-strokes.drawing"))
        let store = FullMonthExampleStore(
            root: folder.appendingPathComponent("Backup"), documents: documents,
            support: folder.appendingPathComponent("Support"), domainName: name)
        try store.loadExample(FullMonthExample.make())
        XCTAssertNil(defaults.object(forKey: PlanningRoutineStore.key))
        try store.restoreUserData()
        XCTAssertEqual(defaults.data(forKey: PlanningRoutineStore.key), bytes)
        XCTAssertEqual(try Data(contentsOf: media.appendingPathComponent("routine-preview.png")), preview)
        XCTAssertEqual(try Data(contentsOf: media.appendingPathComponent("routine-strokes.drawing")), strokes)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFullMonthExampleCoversPastTodayAndSparseFuture
    /// @brief      Verify that full Month Example Covers Past Today And Sparse Future
    /// @details    Exercises `FullMonthExample.make`, `example.document.week`, `PlanningDate.key`. Checks
    ///             `XCTAssertEqual(example.document.firstWeekday, 2)`; `XCTAssertGreaterThanOrEqual(cards.count, 3)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testFullMonthExampleCoversPastTodayAndSparseFuture() throws
    {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let example = FullMonthExample.make(now: today, calendar: calendar)
        XCTAssertEqual(example.document.firstWeekday, 2)
        var futureCount = 0
        var ids = Set<Int>()
        for day in 1 ... 31
        {

            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
            let week = try XCTUnwrap(example.document.week(for: date))
            let listID = try XCTUnwrap(week.dayListIDs[PlanningDate.key(date, calendar: calendar)])
            let cards = try XCTUnwrap(week.collection.lists.first
                {
                    $0.id == listID
                }).cards
            if day < 15
            {

                XCTAssertGreaterThanOrEqual(cards.count, 3);
                XCTAssertTrue(cards.contains(where: \.isTitleChecked))
            }

            if day == 15
            {
                XCTAssertEqual(cards.count, 4)
            }

            if day > 15
            {
                futureCount += cards.count;
                XCTAssertLessThanOrEqual(cards.count, 1)
            }

            for card in cards
            {

                XCTAssertTrue(ids.insert(card.id).inserted)
                if let due = card.dueDate
                {
                    XCTAssertTrue(calendar.isDate(due, inSameDayAs: date))
                }

            }

        }

        XCTAssertGreaterThan(futureCount, 0)
        XCTAssertLessThanOrEqual(futureCount, 5)
        XCTAssertEqual(Set(example.previewLists.map(\.id)).count, example.previewLists.count)
        for components in [(2028, 2, 29), (2026, 3, 8), (2026, 12, 31), (2027, 1, 1)]
        {

            let date = calendar.date(from: DateComponents(year: components.0, month: components.1, day: components.2))!
            let value = FullMonthExample.make(now: date, calendar: calendar)
            XCTAssertNotNil(value.document.week(for: date))
            XCTAssertEqual(
                value.document.weeks.first
                {
                    $0.startKey == value.document.currentWeekKey
                }?.collection.lists.count, 7)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListComposerSubmissionPreservesKindScheduleActionsAndAttachments
    /// @brief      Verify that list Composer Submission Preserves Kind Schedule Actions And Attachments
    /// @details    Exercises `start.addingTimeInterval`, `ListItemCreation.items`,
    ///             `card.checklists.flatMap(\.items).map`. Checks `XCTAssertEqual(card.id, 99)`;
    ///             `XCTAssertEqual(card.presentation, presentation)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListComposerSubmissionPreservesKindScheduleActionsAndAttachments() throws
    {

        let list = KanbanList(id: 7, title: "Work", cards: [])
        let start = Date(timeIntervalSince1970: 1800000000)
        let schedule = QuickCaptureSchedule(start: start, stop: start.addingTimeInterval(3600), includesTime: true)
        let attachment = KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link)
        for presentation in [ItemPresentation.card, .note]
        {

            let capture = QuickCaptureSubmission(
                listID: 7, title: "A new item", body: "Keep this writing", subtitle: "Context",
                presentation: presentation, actions: ["First step"], attachments: [attachment], schedule: schedule)
            let card = try XCTUnwrap(ListItemCreation.items(capture, in: list, startingAt: 99)?.first)
            XCTAssertEqual(card.id, 99)
            XCTAssertEqual(card.presentation, presentation)
            XCTAssertEqual(card.descriptionOverride, "Keep this writing")
            XCTAssertEqual(card.subtitleOverride, "Context")
            XCTAssertEqual(card.startDate, start)
            XCTAssertEqual(card.dueDate, schedule.stop)
            XCTAssertEqual(card.startDateKind, .dateAndTime)
            XCTAssertEqual(card.attachments, [attachment])
            XCTAssertEqual(card.checklists.flatMap(\.items).map(\.title), presentation == .card ? ["First step"] : [])
        }

        let wrongOwner = QuickCaptureSubmission(
            listID: 8, title: "Wrong", body: "", subtitle: "", presentation: .card,
            actions: nil, attachments: [], schedule: nil)
        XCTAssertNil(ListItemCreation.items(wrongOwner, in: list, startingAt: 99))
        XCTAssertTrue(list.cards.isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalNoteCreationPreservesMultipleAttachmentMetadata
    /// @brief      Verify that personal Note Creation Preserves Multiple Attachment Metadata
    /// @details    Exercises `collection.addNote`. Checks `XCTAssertEqual(item.attachments, attachments)`;
    ///             `XCTAssertEqual(item.coverAttachmentID, attachments[1].id)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPersonalNoteCreationPreservesMultipleAttachmentMetadata() throws
    {

        var collection = PersonalCollection(title: "Attachment test", kind: .list)
        let attachments = [
            KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link),
            KanbanAttachment(fileName: "test-photo.png", mediaKind: .photo),
            KanbanAttachment(fileName: "test-video.mov", mediaKind: .video)
        ]
        for kind in [ItemPresentation.card, .note]
        {

            try collection.addNote(
                title: "New item", body: "Keep this writing", presentation: kind, attachments: attachments)
            let item = try XCTUnwrap(collection.lists[0].cards.last)
            XCTAssertEqual(item.attachments, attachments)
            XCTAssertEqual(item.coverAttachmentID, attachments[1].id)
            XCTAssertEqual(item.presentation, kind)
        }

        let restored = try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection))
        XCTAssertEqual(restored.lists[0].cards, collection.lists[0].cards)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreationAttachmentListPresentsSharedMenuInLightAndDark
    /// @brief      Verify that creation Attachment List Presents Shared Menu In Light And Dark
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertNotNil(host.presentedViewController)`;
    ///             `XCTAssertEqual(draft.entries.count, 2)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCreationAttachmentListPresentsSharedMenuInLightAndDark() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        for style in [UIUserInterfaceStyle.light, .dark]
        {

            let draft = CreationAttachmentDraft()
            draft.entries = [
                .init(content: .link(try XCTUnwrap(URL(string: "https://example.com/plans")))),
                .init(content: .drawing(DrawingCaptureDraft(drawing: drawingFixture())))
            ]
            let view = NavigationStack
            {

                Form
                {
                    Section("Attachments")
                    {
                        CreationAttachmentList(draft: draft)
                    }

                } .navigationTitle("New item")
            } .modifier(CreationAttachmentPresentation(draft: draft))
            .preferredColorScheme(style == .dark ? .dark : .light)
            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = style
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            draft.openSources()
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertNotNil(host.presentedViewController)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image
            {
                _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-creation-attachments-\(style.rawValue).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("CREATION_ATTACHMENTS_RENDER=" + url.path)
            draft.sheet = nil
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(draft.entries.count, 2, "Closing the menu must retain the draft attachments")
            window.rootViewController = nil
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreationAttachmentDraftKeepsMultipleEntriesAndCleansRejectedFiles
    /// @brief      Verify that creation Attachment Draft Keeps Multiple Entries And Cleans Rejected Files
    /// @details    Exercises `UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image`,
    ///             `UIColor.blue.setFill`, `context.fill`. Checks `XCTAssertEqual(attachments.count, 23)`;
    ///             `XCTAssertTrue(rejectedFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    @MainActor
    func testCreationAttachmentDraftKeepsMultipleEntriesAndCleansRejectedFiles() throws
    {

        let draft = CreationAttachmentDraft()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image
        {
            context in
            UIColor.blue.setFill();
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        let data = try XCTUnwrap(image.pngData())
        draft.entries = [.init(content: .media(data, .photo, "png")), .init(content: .media(data, .photo, "png"))]
        for index in 0 ..< 20
        {

            draft.entries.append(.init(content: .link(try XCTUnwrap(URL(string: "https://example.com/\(index)")))))
        }

        draft.entries.append(.init(content: .drawing(DrawingCaptureDraft(drawing: drawingFixture()))))
        var rejectedFiles: [URL] = []
        XCTAssertFalse(
            try draft.save
            {
                attachments in
                XCTAssertEqual(attachments.count, 23)
                rejectedFiles = attachments.compactMap
                {
                    CardAttachmentStore.fileURL(for: $0)
                }

                XCTAssertTrue(rejectedFiles.allSatisfy
                    {
                        FileManager.default.fileExists(atPath: $0.path)
                    })
                return false
            })
        XCTAssertEqual(draft.entries.count, 23)
        XCTAssertFalse(rejectedFiles.isEmpty)
        XCTAssertTrue(rejectedFiles.allSatisfy
            {
                !FileManager.default.fileExists(atPath: $0.path)
            })
        var saved: [KanbanAttachment] = []
        XCTAssertTrue(
            try draft.save
            {

                saved = $0;
                return true
            })
        defer
        {
            try? CardAttachmentStore.removeDeletedFiles(Set(saved.flatMap(\.storedFileNames)), keeping: [])
        }

        XCTAssertEqual(saved.count, 23)
        XCTAssertEqual(saved.prefix(2).map(\.kind), [.photo, .photo])
        XCTAssertEqual(saved.dropFirst(2).prefix(20).map(\.kind), Array(repeating: .link, count: 20))
        XCTAssertTrue(
            saved.prefix(2).compactMap
            {
                CardAttachmentStore.fileURL(for: $0)
            } .allSatisfy
            {

                FileManager.default.fileExists(atPath: $0.path)
            })
        let drawing = try XCTUnwrap(saved.last)
        XCTAssertEqual(try DrawingAttachmentStore.load(drawing).drawing.strokes.count, drawingFixture().strokes.count)
        var thrownFiles: [URL] = []
        XCTAssertThrowsError(
            try draft.save
            {
                attachments in
                thrownFiles = attachments.compactMap
                {
                    CardAttachmentStore.fileURL(for: $0)
                }

                throw CocoaError(.fileWriteUnknown)
            })
        XCTAssertTrue(thrownFiles.allSatisfy
            {
                !FileManager.default.fileExists(atPath: $0.path)
            })
        XCTAssertEqual(draft.entries.count, 23)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundPhotoResizesStoresAndRejectsInvalidImages
    /// @brief      Verify that background Photo Resizes Stores And Rejects Invalid Images
    /// @details    Exercises `UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1800), format:
    ///             format).image`, `UIColor.systemTeal.setFill`, `context.fill`. Checks
    ///             `XCTAssertLessThanOrEqual(max(photo.size.width, photo.size.height), 2048)`;
    ///             `XCTAssertEqual(photo.size.width / photo.size.height, 3000.0 / 1800.0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testBackgroundPhotoResizesStoresAndRejectsInvalidImages() throws
    {

        let format = UIGraphicsImageRendererFormat();
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1800), format: format).image
        {

        context in
            UIColor.systemTeal.setFill();
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1800))
        }

        let data = try CollectionBackgroundPhotoStore.preparedPhoto(try XCTUnwrap(original.pngData()))
        let photo = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(photo.size.width, photo.size.height), 2048)
        XCTAssertEqual(photo.size.width / photo.size.height, 3000.0 / 1800.0, accuracy: 0.01)
        let name = try CollectionBackgroundPhotoStore.save(data)
        defer
        {
            CollectionBackgroundPhotoStore.remove(name)
        }

        XCTAssertNotNil(CollectionBackgroundPhotoStore.image(named: name))
        XCTAssertNil(CollectionBackgroundPhotoStore.image(named: "../" + name))
        XCTAssertThrowsError(try CollectionBackgroundPhotoStore.preparedPhoto(Data("not an image".utf8)))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDefaultListPhotosAreBundledAndRespectCustomBackgrounds
    /// @brief      Verify that default List Photos Are Bundled And Respect Custom Backgrounds
    /// @details    Exercises `CollectionBackground.defaultListBackground`, `CollectionBackground.isAllowed`. Checks
    ///             `XCTAssertEqual(CollectionBackground.defaultListBackground(for: title)?.preset, preset)`;
    ///             `XCTAssertNotNil(UIImage(named: asset))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDefaultListPhotosAreBundledAndRespectCustomBackgrounds() throws
    {

        for (title, preset, asset) in [
            ("On the Table", CollectionBackgroundPreset.tabletop, "DefaultListTable"),
            ("In the Queue", .forestPath, "DefaultListQueue"), ("Scheduled", .sunlitWall, "DefaultListScheduled")
        ]
        {

            XCTAssertEqual(CollectionBackground.defaultListBackground(for: title)?.preset, preset)
            XCTAssertNotNil(UIImage(named: asset))
            for override in [
                CollectionBackground(preset: .plain),
                CollectionBackground(preset: .photo, photoFileName: "my-photo.jpg"), CollectionBackground(preset: .sage)
            ]
            {

                XCTAssertEqual(CollectionBackground.defaultListBackground(for: title, overriding: override), override)
            }

            let saved = CollectionBackground(preset: preset)
            XCTAssertEqual(
                try JSONDecoder().decode(CollectionBackground.self, from: JSONEncoder().encode(saved)), saved)
        }

        XCTAssertNil(CollectionBackground.defaultListBackground(for: "Monday"))
        XCTAssertNil(CollectionBackground.defaultListBackground(for: "My own List"))
        XCTAssertFalse(CollectionBackground.isAllowed(collectionID: UUID(), datedWeekIDs: [], isDatedView: true))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverSearchMatchesTagsWithinTheSelectedAlbum
    /// @brief      Verify that cover Search Matches Tags Within The Selected Album
    /// @details    Exercises `ExampleCoverImage.search`, `ExampleCoverImage.search("quiet morning", in:
    ///             .rest).contains`, `ExampleCoverImage.search("WATER plants", in: .nature).contains`. Checks
    ///             `XCTAssertEqual(ExampleCoverImage.search("").count, 400)`;
    ///             `XCTAssertEqual(ExampleCoverImage.search(" ", in: .nature).count, 50)`.
    ///
    /// @return     (Void) no return value
    ///
    func testCoverSearchMatchesTagsWithinTheSelectedAlbum()
    {

        XCTAssertEqual(ExampleCoverImage.search("").count, 400)
        XCTAssertEqual(ExampleCoverImage.search("  ", in: .nature).count, 50)
        XCTAssertTrue(ExampleCoverImage.search("quiet morning", in: .rest).contains(.quietMorning))
        XCTAssertTrue(ExampleCoverImage.search("WATER plants", in: .nature).contains(.wateringPlants))
        XCTAssertTrue(ExampleCoverImage.search("guitar music", in: .creativity).contains(.guitarSession))
        XCTAssertTrue(ExampleCoverImage.search("computer desk", in: .work).contains(.workspace))
        XCTAssertTrue(ExampleCoverImage.search("running fitness", in: .health).contains(.runningRoute))
        XCTAssertTrue(ExampleCoverImage.search("running fitness", in: .food).isEmpty)
        XCTAssertTrue(ExampleCoverImage.search("unicorn submarines", in: .home).isEmpty)
        XCTAssertTrue(ExampleCoverImage.allCases.allSatisfy
            {
                (10 ... 20).contains($0.tags.count)
            })
        let animals = ExampleCoverImage.search("animal")
        XCTAssertTrue(animals.contains(.petCare))
        XCTAssertTrue(animals.contains(.birdWatching))
        XCTAssertTrue(animals.contains(.butterfly))
        XCTAssertTrue(animals.contains(.honeyBees))
        XCTAssertFalse(animals.contains(.workspace))
        XCTAssertTrue(ExampleCoverImage.search("dogs").contains(.petCare))
        XCTAssertTrue(ExampleCoverImage.search("cat").contains(.petCare))
        XCTAssertFalse(ExampleCoverImage.search("cat").contains(.studyBooks))
        XCTAssertTrue(ExampleCoverImage.search("mood").contains(.peacefulBreath))
        XCTAssertTrue(ExampleCoverImage.search("mood").contains(.morningStretch))
        XCTAssertTrue(ExampleCoverImage.search("mood", in: .food).contains(.coffeeBreak))
        XCTAssertFalse(ExampleCoverImage.search("mood", in: .food).contains(.peacefulBreath))
        XCTAssertTrue(ExampleCoverImage.search("cats", in: .home).contains(.catCompanion))
        XCTAssertTrue(ExampleCoverImage.search("dogs", in: .home).contains(.dogWalk))
        XCTAssertTrue(ExampleCoverImage.search("wildlife", in: .nature).contains(.birdFeeder))
        XCTAssertTrue(ExampleCoverImage.search("mood", in: .rest).contains(.joyfulMoment))
        XCTAssertTrue(ExampleCoverImage.search("mental health", in: .health).contains(.mentalHealth))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testStarterAndExampleWeekPictureRowsUseExplicitBundledCoversAndRetainActivities
    /// @brief      Verify that starter And Example Week Picture Rows Use Explicit Bundled Covers And Retain
    ///             Activities
    /// @details    Exercises `lists.flatMap(\.cards).filter`, `lists.flatMap`, `pictures.map`. Checks
    ///             `XCTAssertEqual(pictures.map(\.word), ["Capture a new idea", "Take a walk", "Capture notes and
    ///             ideas"])`; `XCTAssertEqual(pictures.map(\.listTitle), ["Tuesday", "Wednesday", "Sunday"])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testStarterAndExampleWeekPictureRowsUseExplicitBundledCoversAndRetainActivities() throws
    {

        let lists = SampleData.lists
        let pictures = lists.flatMap(\.cards).filter
        {
            $0.displayFormat == .picture
        }

        XCTAssertEqual(pictures.map(\.word), ["Capture a new idea", "Take a walk", "Capture notes and ideas"])
        XCTAssertEqual(pictures.map(\.listTitle), ["Tuesday", "Wednesday", "Sunday"])
        XCTAssertEqual(
            pictures.compactMap
            {
                $0.coverAttachment?.exampleImage
            }, [.writingNotes, .forestPath, .flowerBouquet])
        XCTAssertEqual(Set(lists.flatMap(\.cards).map(\.id)).count, lists.flatMap(\.cards).count)
        for picture in pictures
        {

            XCTAssertFalse(picture.isSectionDivider)
            XCTAssertEqual(picture.attachments?.count, 1)
            XCTAssertTrue(picture.galleryPhotos.isEmpty)
            XCTAssertFalse(picture.checklists.isEmpty)
            XCTAssertFalse(picture.subtitle.isEmpty)
            XCTAssertNoThrow(try CardAttachmentStore.coverThumbnail(for: XCTUnwrap(picture.coverAttachment)))
            var card = picture
            card.displayFormat = .card
            XCTAssertEqual(card.attachments, picture.attachments)
            XCTAssertEqual(card.checklists, picture.checklists)
            XCTAssertEqual(card.word, picture.word)
        }

        XCTAssertTrue(CardAttachmentStore.fileNames(in: lists).isEmpty)
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists)), lists)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testExampleWeekGalleriesUseBundledPhotosAndPreserveCoverAndContent
    /// @brief      Verify that example Week Galleries Use Bundled Photos And Preserve Cover And Content
    /// @details    Exercises `lists.flatMap`, `cards.filter`, `galleryCards.map`. Checks
    ///             `XCTAssertEqual(galleryCards.map(\.word), [ "Review the week ahead", "Plan the weekend", "Spend
    ///             time outdoors" ])`; `XCTAssertEqual(galleryCards.map { $0.galleryPhotos.count }, [3, 3, 3])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testExampleWeekGalleriesUseBundledPhotosAndPreserveCoverAndContent() throws
    {

        let lists = SampleData.lists
        let cards = lists.flatMap(\.cards)
        let galleryCards = cards.filter
        {
            !$0.galleryPhotos.isEmpty
        }

        XCTAssertEqual(
            galleryCards.map(\.word),
            [
                                "Review the week ahead", "Plan the weekend", "Spend time outdoors"
            ])
        XCTAssertEqual(galleryCards.map
            {
                $0.galleryPhotos.count
            }, [3, 3, 3])
        XCTAssertEqual(
            galleryCards.map
            {
                $0.galleryPhotos.compactMap(\.exampleImage)
            },
            [
                [.calendarPlan, .projectPlanning, .workspace],
                [.camping, .travelBag, .picnic],
                [.forestPath, .coastalWalk, .mountains]
            ])
        XCTAssertEqual(galleryCards.flatMap(\.galleryPhotos).compactMap(\.caption).count, 8)
        XCTAssertNil(galleryCards.last?.galleryPhotos.last?.caption)
        XCTAssertEqual(galleryCards.first?.coverAttachment?.exampleImage, .garden)
        XCTAssertEqual(cards.compactMap(\.coverAttachment).count, 6)
        XCTAssertTrue(CardAttachmentStore.fileNames(in: lists).isEmpty)
        let photos = cards.flatMap
        {
            $0.attachments ?? []
        }

        XCTAssertEqual(Set(photos.map(\.id)).count, photos.count)
        for photo in photos
        {

            XCTAssertEqual(photo.kind, .photo)
            XCTAssertNil(photo.fileName)
            XCTAssertNil(photo.url)
            XCTAssertNotNil(photo.exampleImage?.url)
            XCTAssertNoThrow(try CardAttachmentStore.coverThumbnail(for: photo))
        }

        let restored = try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists))
        XCTAssertEqual(restored, lists)
        var edited = try XCTUnwrap(galleryCards.first)
        let original = edited
        try edited.reorderGalleryPhotos(edited.galleryPhotos.reversed().map(\.id))
        try edited.setPhotoCaption("My own plans", for: edited.galleryPhotos[0].id)
        edited.removeAttachment(edited.galleryPhotos[1].id)
        XCTAssertEqual(edited.coverAttachment, original.coverAttachment)
        XCTAssertEqual(edited.checklists, original.checklists)
        XCTAssertEqual(SampleData.lists, lists)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPhotoCaptionsDecodeLegacyAttachmentsAndPreserveMetadata
    /// @brief      Verify that photo Captions Decode Legacy Attachments And Preserve Metadata
    /// @details    Exercises `JSONSerialization.jsonObject`, `card.setPhotoCaption`. Checks
    ///             `XCTAssertNil(json["caption"])`; `XCTAssertEqual(try JSONDecoder().decode(KanbanAttachment.self,
    ///             from: legacyData), photo)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPhotoCaptionsDecodeLegacyAttachmentsAndPreserveMetadata() throws
    {

        let photo = KanbanAttachment(fileName: "gallery-legacy.jpg", mediaKind: .photo)
        let legacyData = try JSONEncoder().encode(photo)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        XCTAssertNil(json["caption"])
        XCTAssertEqual(try JSONDecoder().decode(KanbanAttachment.self, from: legacyData), photo)

        let link = KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link)
        var card = KanbanCard(id: 31, word: "Gallery", listTitle: "Local", checklists: [], attachments: [photo, link])
        try card.setPhotoCaption("  A quiet afternoon\nby the lake  ", for: photo.id)
        var expected = photo
        expected.caption = "A quiet afternoon\nby the lake"
        XCTAssertEqual(card.attachments, [expected, link])
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(restored, card)
        let original = card
        for id in [link.id, UUID()]
        {

            XCTAssertThrowsError(try card.setPhotoCaption("Do not save", for: id))
            XCTAssertEqual(card, original)
        }

        try card.setPhotoCaption(" \n ", for: photo.id)
        XCTAssertEqual(card.attachments, [photo, link])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPhotoGalleryReorderKeepsCoverAndNonphotoSlotsAndRejectsInvalidOrders
    /// @brief      Verify that photo Gallery Reorder Keeps Cover And Nonphoto Slots And Rejects Invalid Orders
    /// @details    Exercises `card.reorderGalleryPhotos`, `card.setCover`, `card.removeAttachment`. Checks
    ///             `XCTAssertEqual(card.galleryPhotos, [first, second, third])`; `XCTAssertEqual(card.attachments,
    ///             [third, video, cover, first, link, second])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPhotoGalleryReorderKeepsCoverAndNonphotoSlotsAndRejectsInvalidOrders() throws
    {

        let cover = KanbanAttachment(exampleImage: .camping, caption: "Cover caption")
        let first = KanbanAttachment(fileName: "first-gallery.jpg", caption: "First")
        let second = KanbanAttachment(exampleImage: .mountains, caption: "Second")
        let third = KanbanAttachment(exampleImage: .garden)
        let video = KanbanAttachment(fileName: "gallery.mov", mediaKind: .video)
        let link = KanbanAttachment(url: URL(string: "https://example.com"), mediaKind: .link)
        var card = KanbanCard(
            id: 32, word: "Gallery", listTitle: "Local", checklists: [],
            attachments: [first, video, cover, second, link, third], coverAttachmentID: cover.id)
        XCTAssertEqual(card.galleryPhotos, [first, second, third])
        try card.reorderGalleryPhotos([third.id, first.id, second.id])
        XCTAssertEqual(card.attachments, [third, video, cover, first, link, second])
        XCTAssertEqual(card.coverAttachmentID, cover.id)
        try card.reorderGalleryPhotos([first.id, second.id, third.id])
        XCTAssertEqual(card.attachments, [first, video, cover, second, link, third])
        let snapshot = card
        for ids in [
            [first.id], [first.id, first.id, third.id], [cover.id, second.id, third.id],
            [UUID(), second.id, third.id], [link.id, second.id, third.id]
        ]
        {

            XCTAssertThrowsError(try card.reorderGalleryPhotos(ids))
            XCTAssertEqual(card, snapshot)
        }

        try card.setCover(nil)
        XCTAssertEqual(card.galleryPhotos, [first, cover, second, third])
        card.removeAttachment(second.id)
        XCTAssertEqual(card.attachments, [first, video, cover, link, third])
        XCTAssertEqual(snapshot.attachments, [first, video, cover, second, link, third])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPhotoGalleryEditsPersistInBothStoresAndRetainArchivedCopies
    /// @brief      Verify that photo Gallery Edits Persist In Both Stores And Retain Archived Copies
    /// @details    Exercises `original.setPhotoCaption`, `original.reorderGalleryPhotos`,
    ///             `KanbanBoardPersistence.saveListsChecked`. Checks `XCTAssertEqual(restoredWeek, lists)`;
    ///             `XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [personal])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPhotoGalleryEditsPersistInBothStoresAndRetainArchivedCopies() async throws
    {

        let suite = "PlenactTests.Gallery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let first = KanbanAttachment(fileName: "retained-gallery.jpg", caption: "Original")
        let second = KanbanAttachment(exampleImage: .camping)
        var original = KanbanCard(
            id: 33, word: "Trip", listTitle: "Local", checklists: [], attachments: [first, second])
        let archived = original
        try original.setPhotoCaption("Edited", for: first.id)
        try original.reorderGalleryPhotos([second.id, first.id])
        let lists = [KanbanList(id: 0, title: "Local", cards: [original], archivedCards: [archived])]
        try KanbanBoardPersistence.saveListsChecked(lists, suiteName: suite)
        let restoredWeek = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)
        XCTAssertEqual(restoredWeek, lists)
        var personal = PersonalCollection(title: "Gallery", kind: .board)
        personal.lists = lists
        try PersonalCollectionStore.saveChecked([personal], to: defaults)
        XCTAssertEqual(PersonalCollectionStore.load(from: defaults), [personal])
        var removed = original
        removed.removeAttachment(first.id)
        let retained = [KanbanList(id: 0, title: "Local", cards: [removed], archivedCards: [archived])]
        XCTAssertEqual(CardAttachmentStore.fileNames(in: retained), ["retained-gallery.jpg"])
        XCTAssertEqual(archived.attachments, [first, second])
        XCTAssertEqual(original.attachments?.first, second)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedPhotoGalleryScrollsHorizontallyWithoutEditingRecords
    /// @brief      Verify that hosted Photo Gallery Scrolls Horizontally Without Editing Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertTrue(scrollViews(in: controller.view).contains {
    ///             $0.contentSize.width > $0.bounds.width })`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testHostedPhotoGalleryScrollsHorizontallyWithoutEditingRecords() async throws
    {

        let photos = [
            KanbanAttachment(exampleImage: .camping, caption: "A place to explore"),
            KanbanAttachment(exampleImage: .mountains),
            KanbanAttachment(
                exampleImage: .garden,
                caption: "A longer caption that should remain readable at accessibility text sizes"),
            KanbanAttachment(exampleImage: .workspace, caption: "Planning the next trip")
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testHostedPhotoGalleryScrollsHorizontallyWithoutEditingRecords.scrollViews
        /// @brief      Find scroll views in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrollViews(in view: UIView) -> [UIScrollView]
        {

            let matches = (view as? UIScrollView).map
            {
                [$0]
            }
            ?? []
            return matches + view.subviews.flatMap
            {
                scrollViews(in: $0)
            }

        }

        for (width, textSize) in [(CGFloat(320), DynamicTypeSize.large), (700, .large), (393, .accessibility3)]
        {

            let gallery = CardPhotoGallery(
                photos: photos, photoSelection: .constant([]),
                onOpen:
                {
                    _ in
                    XCTFail("Rendering must not open a photo")
                },
                onCaption:
                {
                    _, _ in
                    XCTFail("Rendering must not change a caption");
                    return false
                },
                onReorder:
                {
                    _ in
                    XCTFail("Rendering must not reorder photos");
                    return false
                },
                onRemove:
                {
                    _ in
                    XCTFail("Rendering must not remove a photo")
                },
                onSetCover:
                {
                    _ in
                    XCTFail("Rendering must not select a cover")
                }
            )
            let controller = UIHostingController(rootView: gallery.environment(\.dynamicTypeSize, textSize))
            window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertTrue(scrollViews(in: controller.view).contains
                {
                    $0.contentSize.width > $0.bounds.width
                })
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image
            {
                _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            let snapshot = XCTAttachment(image: image)
            snapshot.name = "Photo-Gallery-\(Int(width))-\(textSize)"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testVoiceAudioCommitRoundTripsPlaybackFileAndCleansRejectedSave
    /// @brief      Verify that voice Audio Commit Round Trips Playback File And Cleans Rejected Save
    /// @details    Exercises `data[0].initialize`, `file.write`, `CardAttachmentStore.removeDeletedFiles`. Checks
    ///             `XCTAssertTrue(try QuickCaptureMediaCommit.save([], audio: audio) { attachments in retained =
    ///             attachments; return true })`; `XCTAssertEqual(attachment.kind, .audio)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testVoiceAudioCommitRoundTripsPlaybackFileAndCleansRejectedSave() throws
    {

        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer
        {
            try? FileManager.default.removeItem(at: source)
        }

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        if let data = buffer.floatChannelData
        {
            data[0].initialize(repeating: 0, count: 4_410)
        }

        do
        {

            let file = try AVAudioFile(
                forWriting: source,
                settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
            try file.write(from: buffer)
        }

        let audio = try Data(contentsOf: source)
        var retained: [KanbanAttachment] = []
        defer
        {
            try? CardAttachmentStore.removeDeletedFiles(Set(retained.compactMap(\.fileName)), keeping: [])
        }

        XCTAssertTrue(
            try QuickCaptureMediaCommit.save([], audio: audio)
            {
                attachments in
                retained = attachments;
                return true
            })
        let attachment = try XCTUnwrap(retained.first)
        XCTAssertEqual(attachment.kind, .audio)
        XCTAssertNil(CardAttachmentStore.imageURL(for: attachment))
        let savedURL = try XCTUnwrap(CardAttachmentStore.fileURL(for: attachment))
        XCTAssertEqual(try Data(contentsOf: savedURL), audio)
        let player = try AVAudioPlayer(contentsOf: savedURL)
        XCTAssertGreaterThan(player.duration, 0)
        let card = KanbanCard(
            id: 1, word: "Voice", listTitle: "Today", attachments: retained, descriptionOverride: "Reviewed transcript")
        let saved = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(saved.attachments?.first?.kind, .audio)
        XCTAssertEqual(saved.descriptionOverride, "Reviewed transcript")
        var rejected: [URL] = []
        XCTAssertFalse(
            try QuickCaptureMediaCommit.save([], audio: audio)
            {
                attachments in
                rejected = attachments.compactMap(CardAttachmentStore.fileURL);
                return false
            })
        XCTAssertTrue(rejected.allSatisfy
            {
                !FileManager.default.fileExists(atPath: $0.path)
            })
        XCTAssertThrowsError(
            try QuickCaptureMediaCommit.save([], audio: Data())
            {
                _ in
                XCTFail("Empty audio must not commit");
                return true
            })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testQuickCapturePhotoCommitRetainsSuccessfulFilesAndCleansRejectedOrPartialImports
    /// @brief      Verify that quick Capture Photo Commit Retains Successful Files And Cleans Rejected Or Partial
    ///             Imports
    /// @details    Exercises `UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image`,
    ///             `UIColor.systemBlue.setFill`, `context.fill`. Checks `XCTAssertEqual(attachments.count, 1)`;
    ///             `XCTAssertEqual(try Data(contentsOf: url), photo.data)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testQuickCapturePhotoCommitRetainsSuccessfulFilesAndCleansRejectedOrPartialImports() throws
    {

        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image
        {
            context in
            UIColor.systemBlue.setFill();
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        let photo = QuickCapturePhoto(data: try XCTUnwrap(image.pngData()), fileExtension: "png")
        var committed: [KanbanAttachment] = []
        defer
        {
            try? CardAttachmentStore.removeDeletedFiles(Set(committed.compactMap(\.fileName)), keeping: [])
        }

        XCTAssertTrue(
            try QuickCaptureMediaCommit.save([photo])
            {
                attachments in
                committed = attachments
                XCTAssertEqual(attachments.count, 1)
                return true
            })
        let attachment = try XCTUnwrap(committed.first)
        let url = try XCTUnwrap(CardAttachmentStore.fileURL(for: attachment))
        XCTAssertEqual(try Data(contentsOf: url), photo.data)
        let card = KanbanCard(
            id: 9, word: "Captured title", listTitle: "Today", attachments: committed, coverAttachmentID: attachment.id)
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(restored.attachments, committed)
        XCTAssertEqual(restored.coverAttachmentID, attachment.id)
        var rejectedURLs: [URL] = []
        XCTAssertFalse(
            try QuickCaptureMediaCommit.save([photo])
            {
                attachments in
                rejectedURLs = attachments.compactMap(CardAttachmentStore.fileURL)
                return false
            })
        XCTAssertTrue(rejectedURLs.allSatisfy
            {
                !FileManager.default.fileExists(atPath: $0.path)
            })
        let directory = url.deletingLastPathComponent()
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        let invalid = QuickCapturePhoto(data: Data("not an image".utf8), fileExtension: "png")
        XCTAssertThrowsError(
            try QuickCaptureMediaCommit.save([photo, invalid])
            {
                _ in
                XCTFail("Invalid imports cannot commit");
                return true
            })
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDrawingCapturePersistsEditableStrokesAndRetainsBothFiles
    /// @brief      Verify that drawing Capture Persists Editable Strokes And Retains Both Files
    /// @details    Exercises `CardAttachmentStore.removeDeletedFiles`, `saved.flatMap`,
    ///             `QuickCaptureMediaCommit.save`. Checks `XCTAssertTrue(try QuickCaptureMediaCommit.save([],
    ///             drawings: [draft]) { saved = $0; return true })`; `XCTAssertEqual(attachment.kind, .photo)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDrawingCapturePersistsEditableStrokesAndRetainsBothFiles() throws
    {

        let draft = DrawingCaptureDraft(drawing: drawingFixture())
        var saved: [KanbanAttachment] = []
        defer
        {
            try? CardAttachmentStore.removeDeletedFiles(Set(saved.flatMap(\.storedFileNames)), keeping: [])
        }

        XCTAssertTrue(
            try QuickCaptureMediaCommit.save([], drawings: [draft])
            {

                saved = $0;
                return true
            })
        let attachment = try XCTUnwrap(saved.first)
        XCTAssertEqual(attachment.kind, .photo)
        XCTAssertEqual(attachment.storedFileNames.count, 2)
        XCTAssertNotNil(UIImage(contentsOfFile: try XCTUnwrap(CardAttachmentStore.imageURL(for: attachment)).path))
        let card = KanbanCard(
            id: 4, word: "Sketch", listTitle: "Today", attachments: saved, coverAttachmentID: attachment.id)
        let restored = try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card))
        let restoredAttachment = try XCTUnwrap(restored.attachments?.first)
        let editable = try DrawingAttachmentStore.load(restoredAttachment)
        XCTAssertEqual(editable.drawing.strokes.count, draft.drawing.strokes.count)
        XCTAssertEqual(editable.drawing.bounds, draft.drawing.bounds)
        XCTAssertEqual(
            CardAttachmentStore.fileNames(in: [KanbanList(id: 4, title: "Today", cards: [restored])]),
            Set(attachment.storedFileNames))
        let replacement = try DrawingAttachmentStore.save(editable, replacing: attachment)
        saved.append(replacement)
        XCTAssertEqual(replacement.id, attachment.id)
        XCTAssertEqual(replacement.addedAt, attachment.addedAt)
        XCTAssertNotEqual(replacement.fileName, attachment.fileName)
        // Editing prepares new files and never overwrites strokes referenced by a saved snapshot.
        XCTAssertNoThrow(try DrawingAttachmentStore.load(attachment))
        XCTAssertNoThrow(try DrawingAttachmentStore.load(replacement))
        let legacy = KanbanAttachment(fileName: "old-photo.jpg", mediaKind: .photo)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        object.removeValue(forKey: "drawingFileName")
        let legacyRestored = try JSONDecoder().decode(
            KanbanAttachment.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacyRestored.drawingFileName)
        XCTAssertEqual(legacyRestored.storedFileNames, ["old-photo.jpg"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDrawingRejectedAndPartialSavesCleanBothFiles
    /// @brief      Verify that drawing Rejected And Partial Saves Clean Both Files
    /// @details    Exercises `QuickCaptureMediaCommit.save`, `XCTUnwrap(CardAttachmentStore.fileURL(for:
    ///             attachment)).deletingLastPathComponent`, `CardAttachmentStore.fileURL`. Checks `XCTAssertFalse(try
    ///             QuickCaptureMediaCommit.save([], drawings: [draft]) { rejected = $0; return false })`;
    ///             `XCTAssertFalse(FileManager.default.fileExists(atPath:
    ///             directory.appendingPathComponent(name).path))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDrawingRejectedAndPartialSavesCleanBothFiles() throws
    {

        let draft = DrawingCaptureDraft(drawing: drawingFixture())
        var rejected: [KanbanAttachment] = []
        XCTAssertFalse(
            try QuickCaptureMediaCommit.save([], drawings: [draft])
            {

                rejected = $0;
                return false
            })
        let attachment = try XCTUnwrap(rejected.first)
        let directory = try XCTUnwrap(CardAttachmentStore.fileURL(for: attachment)).deletingLastPathComponent()
        for name in attachment.storedFileNames
        {

            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
        }

        let before = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertThrowsError(
            try QuickCaptureMediaCommit.save([], drawings: [draft, DrawingCaptureDraft()])
            {
                _ in
                XCTFail("A partial drawing import must not commit");
                return true
            })
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDrawingExportsPNGTransparencyAndJPEGWithoutChangingStrokes
    /// @brief      Verify that drawing Exports PNG Transparency And JPEG Without Changing Strokes
    /// @details    Exercises `drawing.dataRepresentation`, `DrawingImageExport.data`, `transparent.prefix`. Checks
    ///             `XCTAssertEqual(Array(transparent.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])`;
    ///             `XCTAssertEqual(Array(jpeg.prefix(2)), [255, 216])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDrawingExportsPNGTransparencyAndJPEGWithoutChangingStrokes() throws
    {

        let drawing = drawingFixture()
        let original = drawing.dataRepresentation()
        let transparent = try DrawingImageExport.data(drawing, format: .png, transparent: true)
        let opaque = try DrawingImageExport.data(drawing, format: .png)
        let jpeg = try DrawingImageExport.data(drawing, format: .jpeg)
        XCTAssertEqual(Array(transparent.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(Array(jpeg.prefix(2)), [255, 216])
        for data in [transparent, opaque, jpeg]
        {

            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertLessThanOrEqual(max(image.size.width * image.scale, image.size.height * image.scale), 4096)
            XCTAssertGreaterThan(image.size.width, 0)
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testDrawingExportsPNGTransparencyAndJPEGWithoutChangingStrokes.cornerAlpha
        /// @brief      Read the exported image corner alpha for transparency assertions
        /// @details    Decodes the image, draws its corner into a one-pixel bitmap, and returns the alpha byte;
        ///             failed image or context creation throws through XCTUnwrap.
        ///
        /// @param[in]  data  Encoded input or media bytes
        ///
        /// @return     (UInt8) result described by this operation's contract
        /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
        ///
        func cornerAlpha(_ data: Data) throws -> UInt8
        {

            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(
                CGContext(
                    data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return bytes[3]
        }

        XCTAssertEqual(try cornerAlpha(transparent), 0)
        XCTAssertEqual(try cornerAlpha(opaque), 255)
        XCTAssertEqual(try cornerAlpha(jpeg), 255)
        XCTAssertEqual(drawing.dataRepresentation(), original)
        XCTAssertThrowsError(try DrawingImageExport.data(PKDrawing(), format: .png))
        XCTAssertEqual(TodayCaptureAction.allCases.map(\.rawValue), ["note", "checklist", "photo", "voice", "drawing"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDrawingEditorRendersOnPhoneAndTabletWithoutSaving
    /// @brief      Verify that drawing Editor Renders On Phone And Tablet Without Saving
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(canvas.drawing.strokes.count, 1)`;
    ///             `XCTAssertTrue(canvas.isFirstResponder)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDrawingEditorRendersOnPhoneAndTabletWithoutSaving() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        var saves = 0
        for size in [CGSize(width: 393, height: 852), CGSize(width: 744, height: 1133)]
        {

            let host = UIHostingController(
                rootView: DrawingCaptureEditor(initial: DrawingCaptureDraft(drawing: drawingFixture()))
                {
                    _ in
                    saves += 1;
                    return true
                })
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(800))
            host.view.layoutIfNeeded()


            ///
            /// @fcn        PlenactBoardDocumentTests.testDrawingEditorRendersOnPhoneAndTabletWithoutSaving.canvases
            /// @brief      Find canvases in the hosted view hierarchy
            /// @details    Recursively inspects native subviews for PKCanvasView. Returns all collected matches in
            ///             hierarchy order.
            ///
            /// @param[in]  view  Native view inspected or synchronized by the operation
            ///
            /// @return     ([PKCanvasView]) resulting values in the ordering described above
            ///
            func canvases(_ view: UIView) -> [PKCanvasView]
            {

                (view as? PKCanvasView).map
                {
                    [$0]
                }
                ?? view.subviews.flatMap(canvases)
            }

            let canvas = try XCTUnwrap(canvases(host.view).first)
            XCTAssertEqual(canvas.drawing.strokes.count, 1)
            XCTAssertTrue(canvas.isFirstResponder)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-drawing-\(Int(size.width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("DRAWING_RENDER=" + url.path)
        }

        XCTAssertEqual(saves, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAttachmentThumbnailsFitTheirSquareGridProposal()
    /// @brief      Verify attachment thumbnails honor the proposed square grid size
    /// @details    Hosts photo, web-link, video, and missing-file examples at several widths and
    ///             checks that each thumbnail returns a square layout
    ///
    /// @return     (Void) succeeds when each supported attachment fits the proposed square
    ///
    /// @throws     XCTest unwrap failure when the synthetic web-link URL is invalid
    ///
    @MainActor
    func testAttachmentThumbnailsFitTheirSquareGridProposal() throws
    {


        let link = try XCTUnwrap(URL(string: "https://example.com/synthetic"))  /* Synthetic link target   */
        let attachments = [                                                     /* Retained attachment set */
            KanbanAttachment(exampleImage: .garden),
            KanbanAttachment(url: link),
            KanbanAttachment(fileName: "synthetic-video.mov", mediaKind: .video),
            KanbanAttachment(fileName: "synthetic-missing-photo.jpg")
        ]
        for attachment in attachments
        {


            let controller = UIHostingController(
                rootView: CardAttachmentThumbnail(attachment: attachment)) /* Hosted controller for layout assertions */
            for width: CGFloat in [92, 128, 260]
            {


                let size = controller.sizeThatFits(
                    in: CGSize(width: width, height: 1000)) /* Proposed layout dimensions */

                XCTAssertEqual(size.width, width, accuracy: 1)
                XCTAssertEqual(size.height, width, accuracy: 1)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedCardCoverSetupLayoutPreservesCoveredAndUncoveredRecords()
    /// @brief      Verify cover setup presentation preserves covered and uncovered Card records
    /// @details    Hosts synthetic Cards with and without selected covers and captures each layout,
    ///             confirming presentation alone does not emit record changes
    ///
    /// @return     (Void) succeeds when both cover states render without modifying their records
    ///
    /// @throws     XCTest unwrap failure when no window scene is available
    ///
    @MainActor
    func testHostedCardCoverSetupLayoutPreservesCoveredAndUncoveredRecords() async throws
    {


        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)                                             /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)  /* Previously focused window       */
        let window = UIWindow(windowScene: scene)                 /* Temporary window for UI hosting */
        defer
        {


            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }


        let photo = KanbanAttachment(exampleImage: .garden) /* Synthetic photo fixture       */
        var card = KanbanCard(
            id: 94, word: "Synthetic cover layout", listTitle: "Synthetic", checklists: []) /* Card value under verification */
        card.appearance = ItemAppearance(icon: .project, background: .blue)
        card.attachments = [
            photo,
            KanbanAttachment(exampleImage: .camping, caption: "Our next adventure"),
            KanbanAttachment(exampleImage: .mountains)
        ]
        var covered = card /* Card with a selected cover */
        covered.coverAttachmentID = photo.id
        for fixture in [card, covered]
        {


            var emitted: [KanbanCard] = [] /* Captured callback results               */
            let controller = UIHostingController(
                rootView: NavigationStack
                {  /* Hosted controller for layout assertions */

                    CardDetailView(card: fixture, onTitleToggle:
                        {
                            emitted.append($0)
                        })
                })
            let size = CGSize(width: 393, height: 852) /* Proposed layout dimensions */
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))

            XCTAssertTrue(emitted.isEmpty, "Relocating cover setup must not modify cover or attachments")
            let image = UIGraphicsImageRenderer(size: size).image
            {
            _ in /* Synthetic two-color crop source */
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            let snapshot = XCTAttachment(image: image) /* Persisted snapshot under verification */
            snapshot.name = fixture.coverAttachmentID == nil ? "Card-without-cover-setup" : "Card-with-selected-cover"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardAttachmentGalleryExcludesOnlyTheDisplayedCover()
    /// @brief      Verify the attachment gallery omits only the currently displayed cover
    /// @details    Exercises cover selection, clearing, invalid cover references, mixed media, and
    ///             cover-only Cards while checking the underlying attachment records stay intact
    ///
    /// @return     (Void) succeeds when gallery filtering matches the valid selected cover
    ///
    /// @throws     XCTest unwrap failure when the synthetic web-link URL is invalid
    ///
    func testCardAttachmentGalleryExcludesOnlyTheDisplayedCover() throws
    {


        let cover = KanbanAttachment(exampleImage: .garden)          /* Selected cover attachment  */
        let otherPhoto = KanbanAttachment(exampleImage: .mountains)  /* Non-cover photo attachment */
        let link = KanbanAttachment(
            url: try XCTUnwrap(URL(string: "https://example.com/synthetic"))) /* Synthetic link target         */
        let video = KanbanAttachment(
            fileName: "synthetic-video.mov", mediaKind: .video)  /* Video attachment fixture      */
        var card = KanbanCard(                                   /* Card value under verification */
            id: 95, word: "Synthetic", listTitle: "Synthetic", checklists: [],
            attachments: [cover, otherPhoto, link, video], coverAttachmentID: cover.id
        )
        let original = card /* Pre-operation value for preservation checks */

        XCTAssertEqual(card.attachmentsExcludingCover, [otherPhoto, link, video])
        XCTAssertEqual(card, original, "Filtering the gallery must not mutate attachments")

        try card.setCover(otherPhoto.id)

        XCTAssertEqual(card.attachmentsExcludingCover, [cover, link, video])
        try card.setCover(nil)

        XCTAssertEqual(card.attachmentsExcludingCover, original.attachments)

        card.coverAttachmentID = link.id

        XCTAssertEqual(card.attachmentsExcludingCover, original.attachments)
        card.coverAttachmentID = UUID()

        XCTAssertEqual(card.attachmentsExcludingCover, original.attachments)

        card.attachments = [cover]
        try card.setCover(cover.id)

        XCTAssertTrue(card.attachmentsExcludingCover.isEmpty)
        XCTAssertEqual(card.attachments, [cover])
        try card.setCover(nil)

        XCTAssertEqual(card.attachmentsExcludingCover, [cover])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibrarySelectionReusesAttachmentsAndPreservesPersonalContent()
    /// @brief      Select, replace, remove, and reselect illustrations without losing personal
    ///             media
    /// @details    Covers repeated selections, archive/restore, independent copies, and Codable
    ///             identifiers
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Cover validation and encoding/decoding errors
    ///
    func testLibrarySelectionReusesAttachmentsAndPreservesPersonalContent() throws
    {


        let photo = KanbanAttachment(
            fileName: "synthetic-personal.jpg", mediaKind: .photo) /* Synthetic photo fixture       */
        var card = KanbanCard(
            id: 9, word: "My plan", listTitle: "Local", checklists: [], /* Card value under verification */
            attachments: [photo], coverAttachmentID: photo.id, descriptionOverride: "Keep this")

        for image in ExampleCoverImage.allCases
        {


            let before = card.attachments?.count ?? 0 /* Timestamp before the operation */

            try card.useLibraryCover(image)

            let selectedID = card.coverAttachmentID /* Selected attachment identifier */

            try card.useLibraryCover(image)

            XCTAssertEqual(card.attachments?.count, before + 1)
            XCTAssertEqual(card.coverAttachmentID, selectedID)
            XCTAssertEqual(card.coverAttachment?.exampleImage, image)
            XCTAssertEqual(card.attachments?.first, photo)
            XCTAssertEqual(card.descriptionOverride, "Keep this")
            XCTAssertNil(card.coverAttachment?.fileName)
        }


        let snapshot = card                                          /* Persisted snapshot under verification */
        var list = KanbanList(id: 1, title: "Local", cards: [card])  /* List state under verification         */

        list.archiveCard(id: card.id)

        let decoded = try JSONDecoder().decode(
            KanbanList.self, from: JSONEncoder().encode(list)) /* Decoded List round-trip value */

        XCTAssertEqual(decoded.archivedCards.first, snapshot)

        try card.setCover(nil)

        XCTAssertEqual(card.attachments, snapshot.attachments)

        try card.useLibraryCover(.garden)

        XCTAssertEqual(card.attachments?.count, ExampleCoverImage.allCases.count + 1)
        XCTAssertEqual(card.coverAttachment?.exampleImage, .garden)
        XCTAssertEqual(snapshot.coverAttachment?.exampleImage, ExampleCoverImage.allCases.last)

        card.isDivider = true

        let rejected = card /* Card value retained after rejected selection */

        XCTAssertThrowsError(try card.useLibraryCover(.coding))
        XCTAssertEqual(card, rejected)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverLibraryLayoutDoesNotSelectOrWriteOnPresentation()
    /// @brief      Host the actual library at narrow, landscape, and accessibility sizes
    /// @details    Layout and presentation alone must not select images or alter preference data
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testCoverLibraryLayoutDoesNotSelectOrWriteOnPresentation()
    {


        for (width, height, size) in [
            (320.0, 640.0, DynamicTypeSize.large),
            (852.0, 393.0, DynamicTypeSize.large),
            (320.0, 640.0, DynamicTypeSize.accessibility5)
        ]
        {

            let view = CardCoverLibrary(
                selectedImage: .garden,
                onSelect:
                {
                _ in /* Hosted view under test */
                    XCTFail("Presentation must not select or attach an image")
                    return false
                }
            ).environment(\.dynamicTypeSize, size)
            let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */

            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            controller.view.layoutIfNeeded()

            let fitting = controller.sizeThatFits(
                in: CGSize(width: width, height: height)) /* Layout proposal that fits the content */

            XCTAssertTrue(fitting.width.isFinite && fitting.height.isFinite)
            XCTAssertGreaterThan(fitting.height, 0)
            XCTAssertLessThanOrEqual(fitting.width, width)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoversAreExplicitAndBackwardCompatible()
    /// @brief      Preserve legacy cards and opt-in cover metadata through Codable
    /// @details    Attached photos never implicitly enable a cover; nil fields remain absent in
    ///             JSON
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Encoding, decoding, or cover validation errors
    ///
    func testCoversAreExplicitAndBackwardCompatible() throws
    {


        let legacy = Data(
                        #"{"id":1,"word":"Synthetic","listTitle":"Local","checklists":[]}"#.utf8)  /* Legacy-format fixture */
        var card = try JSONDecoder().decode(KanbanCard.self, from: legacy)                         /* Decoded Card fixture  */

        XCTAssertNil(card.coverAttachmentID)

        let photo = KanbanAttachment(fileName: "synthetic.jpg", mediaKind: .photo) /* Synthetic photo fixture */

        card.attachments = [photo]

        XCTAssertNil(card.coverAttachment)

        let uncoveredJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]) /* Uncovered-Card JSON fixture */

        XCTAssertNil(uncoveredJSON["coverAttachmentID"])

        let attachmentJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(photo)) as? [String: Any]) /* Attachment JSON fixture */

        XCTAssertNil(attachmentJSON["exampleImage"])

        try card.setCover(photo.id)

        XCTAssertEqual(card.coverAttachment, photo)

        let restored = try JSONDecoder().decode(
            KanbanCard.self, from: JSONEncoder().encode(card)) /* Restored value under verification */

        XCTAssertEqual(restored, card)

        try card.setCover(nil)

        XCTAssertNil(card.coverAttachment)
        XCTAssertEqual(card.attachments, [photo])

        try card.setCover(photo.id)

        XCTAssertEqual(card.coverAttachment, photo)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverSelectionAndAttachmentRemovalNeverChooseFallbackPhotos()
    /// @brief      Validate photo ownership and keep cover removal separate from media deletion
    /// @details    Rejects links/videos/missing IDs; deleting an unrelated photo preserves the
    ///             cover
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Valid cover selection errors
    ///
    func testCoverSelectionAndAttachmentRemovalNeverChooseFallbackPhotos() throws
    {


        let first = KanbanAttachment(fileName: "first.jpg", mediaKind: .photo)    /* First value in the comparison  */
        let second = KanbanAttachment(fileName: "second.jpg", mediaKind: .photo)  /* Second value in the comparison */
        let video = KanbanAttachment(fileName: "video.mov", mediaKind: .video)    /* Video attachment fixture       */
        let link = KanbanAttachment(
            url: URL(string: "https://example.com"), mediaKind: .link) /* Synthetic link target          */
        var card = KanbanCard(
            id: 1, word: "Synthetic", listTitle: "Local", checklists: [], /* Card value under verification  */
            attachments: [first, second, video, link])

        try card.setCover(first.id)

        for id in [video.id, link.id, UUID()]
        {


            XCTAssertThrowsError(try card.setCover(id))
            XCTAssertEqual(card.coverAttachmentID, first.id)
        }


        card.removeAttachment(second.id)

        XCTAssertEqual(card.coverAttachmentID, first.id)

        card.removeAttachment(first.id)

        XCTAssertNil(card.coverAttachmentID)
        XCTAssertNil(card.coverAttachment)
        XCTAssertEqual(card.attachments, [video, link])

        card.attachments = [second]

        XCTAssertNil(card.coverAttachment)

        card.coverAttachmentID = UUID()

        XCTAssertNil(card.coverAttachment)

        card.isDivider = true

        XCTAssertThrowsError(try card.setCover(second.id))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverArchiveRestoreAndIndependentCopyRetainAttachmentIdentity()
    /// @brief      Keep cover selections across retained partitions and independent card copies
    /// @details    Removing a copy's cover does not change the original card or shared attachment
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Cover validation and Codable errors
    ///
    func testCoverArchiveRestoreAndIndependentCopyRetainAttachmentIdentity() throws
    {


        let photo = KanbanAttachment(mediaKind: .photo, exampleImage: .garden) /* Synthetic photo fixture       */
        var card = KanbanCard(
            id: 1, word: "Synthetic", listTitle: "Local", checklists: [], attachments: [photo]) /* Card value under verification */

        try card.setCover(photo.id)

        var list = KanbanList(id: 1, title: "Local", cards: [card]) /* List state under verification */

        list.archiveCard(id: card.id)

        var restored = try JSONDecoder().decode(
            KanbanList.self, from: JSONEncoder().encode(list)) /* Restored value under verification */

        XCTAssertEqual(restored.archivedCards.first?.coverAttachment, photo)

        restored.restoreArchivedCard(id: card.id)

        XCTAssertEqual(restored.cards.first, card)

        var copy = card /* Independent Card copy */

        try copy.setCover(nil)

        XCTAssertEqual(card.coverAttachment, photo)
        XCTAssertEqual(copy.attachments, card.attachments)
        XCTAssertTrue(CardAttachmentStore.fileNames(in: [list]).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBundledExampleCoversDecodeWithoutPersonalFilesOrNetwork()
    /// @brief      Verify resource target membership and bounded image decoding
    /// @details    Exactly three optional examples and three starter cards have original bundled
    ///             covers
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Missing resources, image decoding, or fixture errors
    ///
    func testBundledExampleCoversDecodeWithoutPersonalFilesOrNetwork() throws
    {


        for example in ExampleCoverImage.allCases
        {


            let photo = KanbanAttachment(mediaKind: .photo, exampleImage: example) /* Synthetic photo fixture */

            XCTAssertNotNil(example.url)

            let thumbnail = try CardAttachmentStore.coverThumbnail(for: photo)  /* Rendered attachment thumbnail */
            let image = try XCTUnwrap(thumbnail.cgImage)                        /* Synthetic image fixture       */

            XCTAssertLessThanOrEqual(max(image.width, image.height), 960)
            XCTAssertGreaterThan(min(image.width, image.height), 0)
            XCTAssertNil(photo.fileName)
            XCTAssertNil(photo.url)
        }


        XCTAssertThrowsError(
            try CardAttachmentStore.coverThumbnail(for: KanbanAttachment(fileName: "missing-\(UUID()).jpg")))
        XCTAssertEqual(SampleData.lists.flatMap(\.allCards).compactMap(\.coverAttachment).count, 6)

        let drafts = PersonalListExample.allCases.map
        {

            $0.makeCollection(existingTitles: [])
        }  /* Uncommitted Note drafts */


        XCTAssertEqual(drafts.flatMap(\.lists).flatMap(\.allCards).compactMap(\.coverAttachment).count, 3)
        XCTAssertTrue(CardAttachmentStore.fileNames(in: drafts.flatMap(\.lists)).isEmpty)
    }

}
