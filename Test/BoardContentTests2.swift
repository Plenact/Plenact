// --------------------------------------------------------------------------------------------------
// @file       BoardContentTests2.swift
// @brief      Board Content regression tests2
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
/// BoardContent regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testListAppearanceChangesOnlyCanonicalMetadataAndResetsToNil
    /// @brief      Verify that list Appearance Changes Only Canonical Metadata And Resets To Nil
    /// @details    Exercises `card.replacingLocation`, `lists[0].edit`, `DatabaseActivity.shared.dismissError`.
    ///             Checks `XCTAssertTrue(setListAppearance(0, appearance: appearance, in: &lists))`;
    ///             `XCTAssertEqual(lists, expected)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testListAppearanceChangesOnlyCanonicalMetadataAndResetsToNil() throws
    {

        let photo = KanbanAttachment(exampleImage: .camping, caption: "A day outdoors")
        let card = KanbanCard(
            id: 1, word: "Walk", listTitle: "Monday", attachments: [photo], coverAttachmentID: photo.id)
        let archivedCard = card.replacingLocation(id: 2, listTitle: "Monday")
        var lists = [KanbanList(id: 0, title: "Monday", cards: [card], archivedCards: [archivedCard])]
        let original = lists
        let appearance = ItemAppearance(accent: .teal, icon: .home, background: .blue, listBackground: .green)
        XCTAssertTrue(setListAppearance(0, appearance: appearance, in: &lists))
        var expected = original
        expected[0].appearance = appearance
        XCTAssertEqual(lists, expected)
        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: JSONEncoder().encode(lists)), lists)
        try lists[0].edit(title: "My plans", subtitle: "Next steps")
        XCTAssertEqual(lists[0].appearance, appearance)
        XCTAssertTrue(setListAppearance(0, appearance: ItemAppearance(), in: &lists))
        XCTAssertNil(lists[0].appearance)
        let retained = lists
        DatabaseActivity.shared.dismissError()
        defer
        {
            DatabaseActivity.shared.dismissError()
        }

        XCTAssertFalse(setListAppearance(99, appearance: appearance, in: &lists))
        XCTAssertEqual(lists, retained)
        var archived = retained[0]
        archived.isArchived = true
        lists = [archived]
        XCTAssertFalse(setListAppearance(0, appearance: appearance, in: &lists))
        XCTAssertEqual(lists, [archived])
        lists = [retained[0], retained[0]]
        let duplicated = lists
        XCTAssertFalse(setListAppearance(0, appearance: appearance, in: &lists))
        XCTAssertEqual(lists, duplicated)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPictureRowsHaveNoFooterOrInternalPaddingAtBothBoardDensities
    /// @brief      Verify that picture Rows Have No Footer Or Internal Padding At Both Board Densities
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(size.width, width)`; `XCTAssertEqual(size.height,
    ///             (width - 8) / ratio)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPictureRowsHaveNoFooterOrInternalPaddingAtBothBoardDensities() async throws
    {

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

        let photo = KanbanAttachment(mediaKind: .photo, exampleImage: .flowerBouquet, caption: "Flowers in the garden")
        let thumbnail = try CardAttachmentStore.coverThumbnail(for: photo)
        let ratio = thumbnail.size.width / thumbnail.size.height
        for density in BoardPresentation.allCases
        {

            for title in ["", "A long retained title that must not add a footer to this Picture row"]
            {

                var card = KanbanCard(
                    id: 81, word: title, listTitle: "Ideas", attachments: [photo], coverAttachmentID: photo.id)
                card.displayFormat = .picture
                let original = card
                let row = KanbanCardView(
                    card: card, height: density.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                    presentation: density, labelLibrary: .starter,
                    onUpdateCard:
                    {
                        _ in
                        XCTFail("Layout must not edit")
                    },
                    onDeleteCard:
                    {
                        XCTFail("Layout must not delete")
                    },
                    onArchiveCard:
                    {
                        XCTFail("Layout must not archive")
                    },
                    onToggle:
                    {
                        XCTFail("Layout must not complete")
                    }
                )
                .environment(\.dynamicTypeSize, .accessibility3)
                let host = UIHostingController(rootView: row)
                host.safeAreaRegions = []  // Measure the row itself, without window safe-area insets.
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                for width: CGFloat in [320, 430]
                {

                    let size = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
                    XCTAssertEqual(size.width, width, accuracy: 1)
                    XCTAssertEqual(
                        size.height, (width - 8) / ratio, accuracy: 1,
                                                                "Only the image and existing outer row margins should determine Picture size")
                }

                let image = UIGraphicsImageRenderer(size: window.bounds.size).image
                {
                    _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }

                let attachment = XCTAttachment(image: image)
                attachment.name = "Picture-full-row-\(density.rawValue)-\(title.isEmpty ? "blank" : "retained-title")"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertEqual(card, original)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListEditingPreservesRetainedRecordsAndRoundTripsSubtitle
    /// @brief      Verify that list Editing Preserves Retained Records And Round Trips Subtitle
    /// @details    Exercises `list.edit`, `collection.rename`. Checks `XCTAssertThrowsError(try list.edit(title: " \n
    ///             ", subtitle: "Do not save"))`; `XCTAssertEqual(list, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListEditingPreservesRetainedRecordsAndRoundTripsSubtitle() throws
    {


        let card = KanbanCard(id: 10, word: "Synthetic", listTitle: "Thursday", descriptionOverride: "Retained body")
        let divider = KanbanCard(id: 11, word: "---", listTitle: "Thursday", isDivider: true, checklists: [])
        let archive = KanbanCard(id: 12, word: "Retained archive", listTitle: "Thursday", presentation: .note)
        var list = KanbanList(
            id: 4, title: "Thursday", cards: [card, divider], archivedCards: [archive], newItemPresentation: .note)
        let original = list

        XCTAssertThrowsError(try list.edit(title: " \n ", subtitle: "Do not save"))
        XCTAssertEqual(list, original)
        try list.edit(title: "  My plans  ", subtitle: "  A calm place to begin  ")
        var expectedCard = card
        var expectedDivider = divider
        var expectedArchive = archive
        expectedCard.listTitle = "My plans"
        expectedDivider.listTitle = "My plans"
        expectedArchive.listTitle = "My plans"
        XCTAssertEqual(list.cards, [expectedCard, expectedDivider])
        XCTAssertEqual(list.archivedCards, [expectedArchive])
        XCTAssertEqual(list.id, original.id)
        XCTAssertEqual(list.newItemPresentation, .note)
        XCTAssertEqual(list.subtitle, "A calm place to begin")
        XCTAssertEqual(try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list)), list)

        try list.edit(title: list.title, subtitle: "")
        XCTAssertEqual(list.subtitle, "")
        XCTAssertEqual(try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(list)).subtitle, "")
        var collection = PersonalCollection(title: "Synthetic", kind: .list)
        collection.lists = [list]
        collection.rename(to: "Library plans")
        XCTAssertEqual(collection.lists[0].subtitleOverride, "")
        XCTAssertEqual(collection.lists[0].archivedCards[0].id, archive.id)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testVoiceSaveOptionsKeepOnlySelectedContentAndPreserveRichWriting
    /// @brief      Verify that voice Save Options Keep Only Selected Content And Preserve Rich Writing
    /// @details    Exercises `PlanRichText.Run`, `VoiceCaptureSaveOption.audio.body`, `option.body`. Checks
    ///             `XCTAssertEqual(VoiceCaptureSaveOption.audio.body(existing: rich, transcript: transcript), rich)`;
    ///             `XCTAssertEqual(PlanRichText.plain(body), "Keep this writing\n\nMy reviewed spoken thought")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testVoiceSaveOptionsKeepOnlySelectedContentAndPreserveRichWriting() throws
    {

        let rich =
        PlanRichText.prefix
        + (try JSONEncoder().encode([PlanRichText.Run(text: "Keep this writing", bold: true)]))
        .base64EncodedString()
        let transcript = "  My reviewed spoken thought  "
        XCTAssertEqual(VoiceCaptureSaveOption.audio.body(existing: rich, transcript: transcript), rich)
        for option in [VoiceCaptureSaveOption.text, .both]
        {

            let body = option.body(existing: rich, transcript: transcript)
            XCTAssertEqual(PlanRichText.plain(body), "Keep this writing\n\nMy reviewed spoken thought")
            XCTAssertEqual(PlanRichText.runs(body)?.first?.bold, true)
            XCTAssertEqual(option.body(existing: "", transcript: transcript), "My reviewed spoken thought")
            XCTAssertEqual(option.body(existing: rich, transcript: "   "), rich)
        }

        XCTAssertTrue(VoiceCaptureSaveOption.audio.savesAudio)
        XCTAssertFalse(VoiceCaptureSaveOption.audio.savesText)
        XCTAssertFalse(VoiceCaptureSaveOption.text.savesAudio)
        XCTAssertTrue(VoiceCaptureSaveOption.text.savesText)
        XCTAssertTrue(VoiceCaptureSaveOption.both.savesAudio && VoiceCaptureSaveOption.both.savesText)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLegacyItemsRemainCardsAndRejectInvalidPresentations()
    /// @brief      Keep legacy JSON unchanged unless Note presentation is explicitly selected
    /// @details    Checks missing optional fields, default-key omission, and invalid enum values
    ///
    /// @return     (Void) records compatibility assertion failures
    /// @throws     Fixture encoding or decoding errors
    ///
    func testLegacyItemsRemainCardsAndRejectInvalidPresentations() throws
    {


        let data = Data(
                        #"{"id":1,"title":"Legacy","cards":[{"id":2,"word":"Retain","listTitle":"Legacy","checklists":[]}]}"#.utf8) /* JSON fixture bytes for the compatibility check */
        let list = try JSONDecoder().decode(
            KanbanList.self, from: data) /* Decoded List fixture                           */

        XCTAssertEqual(list.newItemPresentation, .card)
        XCTAssertEqual(list.cards[0].presentation, .card)

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any])  /* Encoded JSON representation   */
        let cards = try XCTUnwrap(json["cards"] as? [[String: Any]])                           /* Card records under inspection */

        XCTAssertNil(json["defaultItemPresentation"])
        XCTAssertNil(cards[0] ["itemPresentation"])
        XCTAssertNil(list.cards[0].descriptionOverride)
        XCTAssertNil(list.cards[0].createdAt)
        XCTAssertNil(cards[0] ["createdAt"])

        let invalidCard = Data(
                        #"{"id":2,"word":"Invalid","listTitle":"Legacy","itemPresentation":"unsupported"}"#.utf8) /* Unsupported Card fixture                   */
        let invalidList = Data(
                        #"{"id":1,"title":"Invalid","cards":[],"defaultItemPresentation":"unsupported"}"#.utf8) /* Unsupported list-presentation JSON fixture */

        XCTAssertThrowsError(try JSONDecoder().decode(KanbanCard.self, from: invalidCard))
        XCTAssertThrowsError(try JSONDecoder().decode(KanbanList.self, from: invalidList))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testMultilineEntriesPreserveOrderIgnoreBlankLinesAndCreateDistinctCards
    /// @brief      Verify that multiline Entries Preserve Order Ignore Blank Lines And Create Distinct Cards
    /// @details    Exercises `MultilineEntry.titles`, `list.makeItems`, `cards.map`. Checks
    ///             `XCTAssertEqual(MultilineEntry.titles(input), ["A", "B", "C", "D", "A"])`;
    ///             `XCTAssertTrue(MultilineEntry.titles(" \n\t\r\n").isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testMultilineEntriesPreserveOrderIgnoreBlankLinesAndCreateDistinctCards() throws
    {

        let input = " A\r\nB\n\n C \rD\nA\n"
        XCTAssertEqual(MultilineEntry.titles(input), ["A", "B", "C", "D", "A"])
        XCTAssertTrue(MultilineEntry.titles(" \n\t\r\n").isEmpty)
        let list = KanbanList(id: 1, title: "Saturday", cards: [])
        let cards = list.makeItems(startingAt: 20, titles: input, description: "Shared details", subtitle: "Subtitle")
        XCTAssertEqual(cards.map(\.word), ["A", "B", "C", "D", "A"])
        XCTAssertEqual(cards.map(\.id), [20, 21, 22, 23, 24])
        XCTAssertTrue(cards.allSatisfy
            {
                $0.descriptionOverride == "Shared details" && $0.subtitle == "Subtitle"
            })
        let decoded = try JSONDecoder().decode([KanbanCard].self, from: JSONEncoder().encode(cards))
        XCTAssertEqual(decoded, cards)
        let items = MultilineEntry.titles(input).map
        {
            KanbanChecklistItem(title: $0)
        }

        XCTAssertEqual(items.map(\.title), ["A", "B", "C", "D", "A"])
        XCTAssertEqual(Set(items.map(\.id)).count, 5)
        XCTAssertTrue(items.allSatisfy
            {
                !$0.isCompleted
            })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekSaveCompletionRunsOnlyAfterSuccessfulWrite()
    /// @brief      Gate deletion cleanup on successful ordered persistence
    /// @details    Checks valid completion and rejects completion when JSON encoding fails
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Fixture setup failures
    ///
    @MainActor
    func testWeekSaveCompletionRunsOnlyAfterSuccessfulWrite() async throws
    {


        let suite = "Plenact.DeletionCompletionTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))        /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }


        let success = expectation(description: "Completion follows write") /* Successful operation result */

        KanbanBoardPersistence.enqueueSave(
            [], suiteName: suite,
            onSuccess:
            {


                XCTAssertNotNil(defaults.data(forKey: "Plenact.Board.v1"))
                success.fulfill()
            })
        await fulfillment(of: [success], timeout: 2)

        var invalid = KanbanCard(
            id: 1, word: "Invalid", listTitle: "List", checklists: []) /* Malformed fixture input */

        invalid.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)

        let rejected = expectation(
            description: "No cleanup after failed write") /* Expectation that failed writes skip completion cleanup */

        rejected.isInverted = true
        KanbanBoardPersistence.enqueueSave(
            [KanbanList(id: 1, title: "List", cards: [invalid])], suiteName: suite,
            onSuccess:
            {
                rejected.fulfill()
            }
        )
        await fulfillment(of: [rejected], timeout: 0.2)

        XCTAssertNotNil(DatabaseActivity.shared.errorMessage)
        XCTAssertEqual(
            try JSONDecoder().decode([KanbanList].self, from: XCTUnwrap(defaults.data(forKey: "Plenact.Board.v1"))), [])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryContainsOnlyPersonalCollectionsWithoutChangingWeek()
    /// @brief      Verify Library renders personal collections and one canonical Saved shortcut
    /// @details    Hosts the real Library with synthetic Week and archived content, then checks
    ///             native List item counts and unchanged snapshots, including a restored Week copy
    ///
    /// @return     (Void) records assertion failures for extra rows or changed content
    ///
    /// @throws     Scene or hosted collection-view unwrap failures and task cancellation
    ///
    @MainActor
    func testLibraryContainsOnlyPersonalCollectionsWithoutChangingWeek() async throws
    {


        let week = SampleData.lists /* Archived weekly-board fixture         */
        var archived = PersonalCollection(
            title: "Archived fixture", kind: .board) /* Archived value for restoration checks */

        archived.isArchived = true

        let restored = PersonalCollection(
            title: "Week Board (Restored)", kind: .board) /* Restored value under verification               */
        let personal = PersonalCollection(
            title: "Personal fixture", kind: .list)       /* Personal List fixture filtered from demo Boards */
        let collections = [personal, restored, archived]  /* Saved personal-collection state                 */
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


        ///
        /// @fcn        PlenactBoardDocumentTests.testLibraryContainsOnlyPersonalCollectionsWithoutChangingWeek.collectionView(in:)
        /// @brief      Locate the native List collection in the hosted Library
        /// @details    Recursively searches subviews without changing the view hierarchy
        ///
        /// @param[in]  view  Root view to inspect
        ///
        /// @return     (UICollectionView?) first collection found, or nil when absent
        ///
        func collectionView(in view: UIView) -> UICollectionView?
        {


            if let collection = view as? UICollectionView /* Matched native List collection view */
            {


                return collection
            }


            return view.subviews.compactMap
            {
                collectionView(in: $0)
            } .first
        }


        for fixtures in [[personal], collections, []]
        {


            var current = fixtures /* Current collections displayed by the Library */

            let controller = UIHostingController(
                rootView: BoardListsView( /* Hosted controller for layout assertions */
                    retainedWeekLists: week,
                    collections: Binding(get:
                        {
                            current
                        }, set:
                        {
                            current = $0
                        }),
                    registerListNewNote:
                    {
                        _ in
                    },
                    onOpenSaved:
                    {
                        XCTFail("Rendering must not navigate to Saved")
                    }
                ))

            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller

            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()

            try await Task.sleep(for: .milliseconds(100))

            let list = try XCTUnwrap(collectionView(in: controller.view)) /* List state under verification */

            let count = (0 ..< list.numberOfSections).reduce(0)
            {  /* Number of matching values */


                $0 + list.numberOfItems(inSection: $1)
            }


            XCTAssertEqual(
                count, max(1, fixtures.filter(\.isActive).count),
                                        "Saved navigation must not occupy a full-width Library row")
            XCTAssertEqual(current, fixtures)
            XCTAssertEqual(week, SampleData.lists)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryRowsFitLongTitlesAndAccessibilityText()
    /// @brief      Verify Library entries fit their content across viewport and text sizes
    /// @details    Hosts synthetic collection rows at portrait/landscape widths; accessibility text
    ///             must grow vertically instead of retaining a fixed row height
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testLibraryRowsFitLongTitlesAndAccessibilityText()
    {


        for width: CGFloat in [280, 700]
        {


            let row = LibraryCollectionRow( /* Rendered collection row */
                title: "Ideas and plans for the coming season",
                subtitle: "Board · 3 lists", icon: "square.stack.3d.up", color: .blue, count: 12
            )

            let standard = UIHostingController(
                rootView: row.environment(\.dynamicTypeSize, .large)
            ) /* Standard Card baseline */
            .sizeThatFits(in: CGSize(width: width, height: 10_000))

            let accessible = UIHostingController(
                rootView: row.environment(\.dynamicTypeSize, .accessibility5)
            ) /* Accessibility-sized layout */
            .sizeThatFits(in: CGSize(width: width, height: 10_000))

            XCTAssertEqual(standard.width, width, accuracy: 1)
            XCTAssertEqual(accessible.width, width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(standard.height, 48)
            XCTAssertGreaterThan(accessible.height, standard.height)
            XCTAssertLessThan(accessible.height, 1_000)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardPresentationWidthsInPortraitLandscapeAndAccessibility()
    /// @brief      Verify preset widths and invalid-geometry handling
    /// @details    Checks exact caps, landscape capacity, narrow viewports, and accessibility
    ///             sizing
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testBoardPresentationWidthsInPortraitLandscapeAndAccessibility()
    {


        XCTAssertEqual(BoardPresentation.standard.columnWidth(viewportWidth: 393, accessibilitySize: false), 329)
        XCTAssertEqual(BoardPresentation.overview.columnWidth(viewportWidth: 393, accessibilitySize: false), 240)
        XCTAssertEqual(BoardPresentation.standard.columnWidth(viewportWidth: 852, accessibilitySize: false), 360)
        XCTAssertEqual(BoardPresentation.overview.columnWidth(viewportWidth: 852, accessibilitySize: false), 240)
        XCTAssertLessThanOrEqual(2 * 360 + 17 + 28, 852)
        XCTAssertLessThanOrEqual(3 * 240 + 24 + 28, 852)

        for preset in BoardPresentation.allCases
        {


            XCTAssertEqual(preset.columnWidth(viewportWidth: 320, accessibilitySize: true), 292)
            XCTAssertEqual(preset.columnWidth(viewportWidth: 200, accessibilitySize: false), 172)

            for width: CGFloat in [0, 28, -1, .nan, .infinity]
            {


                XCTAssertEqual(preset.columnWidth(viewportWidth: width, accessibilitySize: false), 1)
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSingleListCollectionUsesAvailableStandardWidthWithoutChangingOverview()
    /// @brief      Verify Standard personal-list width fills the viewport without changing Board presets
    /// @details    Checks portrait, landscape, narrow, invalid, and accessibility widths against
    ///             exact usable-width values; default Week and multi-list behavior retains its cap
    ///
    /// @return     (Void) records assertion failures for incorrect column widths
    ///
    func testSingleListCollectionUsesAvailableStandardWidthWithoutChangingOverview()
    {


        for width: CGFloat in [320, 393, 852]
        {


            XCTAssertEqual(
                BoardPresentation.standard.columnWidth(
                    viewportWidth: width, accessibilitySize: false, fillsAvailableWidth: true
                ), width - 28)

            XCTAssertEqual(
                BoardPresentation.standard.columnWidth(
                    viewportWidth: width, accessibilitySize: false
                ), min(width - 28, 360, max(172, width - 64)))

            XCTAssertEqual(
                BoardPresentation.overview.columnWidth(
                    viewportWidth: width, accessibilitySize: false, fillsAvailableWidth: true
                ), min(width - 28, 240))

            XCTAssertEqual(
                BoardPresentation.overview.columnWidth(
                    viewportWidth: width, accessibilitySize: true, fillsAvailableWidth: true
                ), width - 28)
        }


        for width: CGFloat in [0, 28, -1, .nan, .infinity]
        {


            XCTAssertEqual(
                BoardPresentation.standard.columnWidth(
                    viewportWidth: width, accessibilitySize: false, fillsAvailableWidth: true
                ), 1)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardPresentationPreferenceIsLocalAndLeavesBoardSnapshotsUntouched()
    /// @brief      Persist presentation independently of Board snapshots
    /// @details    Reopens an isolated AppStorage preference and compares untouched Week/collection
    ///             bytes
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap or fixture encoding failures
    ///
    @MainActor
    func testBoardPresentationPreferenceIsLocalAndLeavesBoardSnapshotsUntouched() throws
    {


        let suite = "Plenact.BoardPresentationTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))       /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let week = try JSONEncoder().encode(SampleData.lists)                     /* Archived weekly-board fixture  */
        var board = PersonalCollection(title: "Synthetic project", kind: .board)  /* Board state under verification */

        board.lists = SampleData.lists
        board.savedCardIDs = [0]
        board.isArchived = true

        let collections = try JSONEncoder().encode([board]) /* Saved personal-collection state */

        defaults.set(week, forKey: "Plenact.Board.v1")
        defaults.set(collections, forKey: "Plenact.PersonalCollections.v1")

        let preference = AppStorage(
            wrappedValue: BoardPresentation.standard, BoardPresentation.storageKey, store: defaults) /* Persisted display preference */

        XCTAssertEqual(preference.wrappedValue, .standard)

        preference.wrappedValue = .overview

        XCTAssertEqual(defaults.string(forKey: BoardPresentation.storageKey), "overview")

        let reopened = AppStorage(
            wrappedValue: BoardPresentation.standard, BoardPresentation.storageKey, store: defaults) /* Value loaded after reopening storage */

        XCTAssertEqual(reopened.wrappedValue, .overview)

        preference.wrappedValue = .standard

        XCTAssertEqual(defaults.data(forKey: "Plenact.Board.v1"), week)
        XCTAssertEqual(defaults.data(forKey: "Plenact.PersonalCollections.v1"), collections)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardSummaryDoesNotStretchToFillListHeight()
    /// @brief      Reject vertical expansion under a taller layout proposal
    /// @details    Compares 300- and 900-point proposals for the same synthetic card in both
    ///             presets
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    @MainActor
    func testCardSummaryDoesNotStretchToFillListHeight()
    {


        let card = KanbanCard(
            id: 101, word: "Review the week ahead", listTitle: "Synthetic list") /* Card value under verification */

        for preset in BoardPresentation.allCases
        {


            let controller = UIHostingController(
                rootView: KanbanCardView( /* Hosted controller for layout assertions */
                    card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                    presentation: preset, labelLibrary: .starter,
                    onUpdateCard:
                    {
                        _ in
                        XCTFail("Layout must not edit content")
                    },
                    onDeleteCard:
                    {

                    }, onArchiveCard:
                    {

                    }, onToggle:
                    {

                    }
                ).environment(\.dynamicTypeSize, .large))

            let width: CGFloat = preset == .standard ? 360 : 240 /* Proposed layout width          */
            let shortProposal = controller.sizeThatFits(
                in: CGSize(width: width, height: 300)) /* Compact-height layout proposal */
            let tallProposal = controller.sizeThatFits(
                in: CGSize(width: width, height: 900)) /* Tall layout proposal           */

            XCTAssertEqual(shortProposal.height, tallProposal.height, accuracy: 1)
            XCTAssertLessThan(tallProposal.height, preset == .standard ? 170 : 130)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNavigationLinkedCardRowsRemainCompactInAList()
    /// @brief      Verify card sizing inside native navigation-linked List rows
    /// @details    Attaches a hosting window to the current scene and restores the prior key window
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Scene/row unwrap failures or cancellation of the layout delay
    ///
    @MainActor
    func testNavigationLinkedCardRowsRemainCompactInAList() async throws
    {


        let card = KanbanCard(
            id: 102, word: "Review the week ahead", listTitle: "Synthetic list") /* Card value under verification   */
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)                                                      /* Active scene for UI hosting     */
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)  /* Previously active key window    */
        let window = UIWindow(windowScene: scene)                          /* Temporary window for UI hosting */

        defer
        {


            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testNavigationLinkedCardRowsRemainCompactInAList.collectionView(in:)
        /// @brief      Locate the List's backing collection view in the hosted hierarchy
        /// @details    Recursively searches subviews and returns the first match
        ///
        /// @param[in]  view  Root of the UIKit subtree to inspect
        ///
        /// @return     (UICollectionView?) first matching view, or nil
        ///
        func collectionView(in view: UIView) -> UICollectionView?
        {


            if let collection = view as? UICollectionView /* Matched native List collection view */
            {


                return collection
            }


            return view.subviews.compactMap
            {
                collectionView(in: $0)
            } .first
        }


        for preset in BoardPresentation.allCases
        {


            let view = NavigationStack
            {  /* Hosted view under test */

                List
                {

                    NavigationLink
                    {

                        Text("Synthetic card detail")
                    }
                    label:
                    {

                        KanbanCardView(
                            card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                            presentation: preset, labelLibrary: .starter,
                            onUpdateCard:
                            {
                                _ in
                                XCTFail("Rendering must not edit content")
                            },
                            onDeleteCard:
                            {

                            }, onArchiveCard:
                            {

                            }, onToggle:
                            {

                            }
                        )
                    }

                    .buttonStyle(.plain)
                }

                .listStyle(.plain)
            }

            .environment(\.dynamicTypeSize, .large)

            let controller = UIHostingController(rootView: view) /* Hosted controller for layout assertions */

            window.rootViewController = controller
            window.frame = CGRect(x: 0, y: 0, width: preset == .standard ? 360 : 240, height: 700)
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))

            let collection = try XCTUnwrap(
                collectionView(in: controller.view))                /* Collection state under verification */
            let row = try XCTUnwrap(collection.visibleCells.first)  /* Rendered collection row             */

            XCTAssertLessThan(row.bounds.height, preset == .standard ? 210 : 180)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardBoundaryNavigationTargetsFirstAndLastActiveLists()
    /// @brief      Resolve direct Board jumps using the current ordered list snapshot
    /// @details    Checks first/last identity, a single-list Board, an empty Board, and unchanged
    ///             list/card records
    ///
    /// @return     (Void) records assertion failures for incorrect edge targets or mutations
    ///
    func testBoardBoundaryNavigationTargetsFirstAndLastActiveLists()
    {


        let lists = SampleData.lists  /* Board lists under verification              */
        let original = lists          /* Pre-operation value for preservation checks */

        XCTAssertEqual(BoardListReordering.boundaryListID(.first, in: lists), lists.first?.id)
        XCTAssertEqual(BoardListReordering.boundaryListID(.last, in: lists), lists.last?.id)
        XCTAssertEqual(BoardListReordering.boundaryListID(.first, in: Array(lists.prefix(1))), lists.first?.id)
        XCTAssertEqual(BoardListReordering.boundaryListID(.last, in: Array(lists.prefix(1))), lists.first?.id)
        XCTAssertNil(BoardListReordering.boundaryListID(.first, in: []))
        XCTAssertNil(BoardListReordering.boundaryListID(.last, in: []))
        XCTAssertEqual(lists, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNativeCardDropCommitsOriginalRecordAndRejectsForeignOrEndedSessions()
    /// @brief      Verify native receiver commits preserve the original card record
    /// @details    Exercises a same-token active source against the real receiver callback, rejects
    ///             a foreign token and ended source, and checks unchanged card metadata plus
    ///             cleared drag state.
    ///
    /// @return     (Void) records assertion failures for accepted or rejected drop behavior
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    @MainActor
    func testNativeCardDropCommitsOriginalRecordAndRejectsForeignOrEndedSessions() throws
    {


        let card = KanbanCard(id: 1, word: "Synthetic", listTitle: "Source") /* Card value under verification  */
        var lists = [
            KanbanList(id: 10, title: "Source", cards: [card]), /* Board lists under verification */
            KanbanList(id: 20, title: "Destination", cards: [])
        ]
        var ends = 0 /* Drag completion events            */
        let source = BoardCardDragSource(
            token: "local-board", onBegan:
            {
                _ in
            }, /* Source state before the operation */
            onChanged:
            {
                _ in
            }, onEnded:
            {
                ends += 1
            }
        ).makeCoordinator()
        let item = UIDragItem(itemProvider: source.begin(at: .zero)) /* Checklist item under verification */

        item.localObject = source

        var points: [CGPoint] = [] /* Sample layout coordinates */
        let drop = BoardCardDropSurface(
            token: "local-board", onChanged:
            {
                points.append($0)
            }, /* Drop operation result     */
            onDrop:
            {
                point in
                guard
                let target = BoardCardMovement.target( /* Resolved destination for the dragged Card */
                    for: card.id, at: point, viewport: CGRect(x: 0, y: 100, width: 400, height: 600),
                    lists: lists, listFrames: [20: CGRect(x: 200, y: 100, width: 200, height: 600)],
                    cardFrames: [:]
                )
                else
                {
                    return false
                }

                do
                {


                    return try BoardCardMovement.move(card.id, to: target.listID, in: &lists)
                }
                catch
                {


                    XCTFail("Drop failed: \(error)");
                    return false
                }

            }
        ).makeCoordinator()
        let foreign = BoardCardDropSurface(
            token: "another-board", onChanged:
            {
                _ in
                XCTFail("Foreign hover")
            }, /* Foreign collection fixture */
            onDrop:
            {
                _ in
                XCTFail("Foreign drop");
                return false
            }
        ).makeCoordinator()

        XCTAssertFalse(foreign.accepts([item]))
        XCTAssertFalse(drop.accepts([UIDragItem(itemProvider: NSItemProvider())]))
        XCTAssertTrue(drop.accepts([item]))

        drop.surface.isEnabled = false

        XCTAssertFalse(drop.accepts([item]), "Explicit native reorder mode must disable the cross-list receiver")

        drop.surface.isEnabled = true

        XCTAssertTrue(drop.perform([item], at: CGPoint(x: 250, y: 300)))
        XCTAssertTrue(lists[0].cards.isEmpty)

        var expected = card /* Expected result for comparison */

        expected.listTitle = "Destination"

        XCTAssertEqual(lists[1].cards, [expected])
        XCTAssertEqual(points, [CGPoint(x: 250, y: 300)])

        source.finish()

        XCTAssertEqual(ends, 1)
        XCTAssertFalse(drop.accepts([item]))
        XCTAssertFalse(drop.perform([item], at: CGPoint(x: 250, y: 300)))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundBoardSavesPreserveLatestSnapshot()
    /// @brief      Persist the most recent queued Week snapshot
    /// @details    Enqueues two writes in an isolated suite and awaits a load before comparing
    ///             stored bytes
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference/data unwrap or JSON decoding failures
    ///
    @MainActor
    func testBackgroundBoardSavesPreserveLatestSnapshot() async throws
    {


        let suite = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let first = [KanbanList(id: 1, title: "First", cards: [])]  /* First value in the comparison */
        let last = [KanbanList(id: 1, title: "Latest", cards: [])]  /* Most recent request           */

        KanbanBoardPersistence.enqueueSave(first, suiteName: suite)
        KanbanBoardPersistence.enqueueSave(last, suiteName: suite)

        XCTAssertTrue(DatabaseActivity.shared.isWorking)

        let restored = await KanbanBoardPersistence.loadListsInBackground(
            suiteName: suite) /* Restored value under verification */

        XCTAssertEqual(restored, last)

        let data = try XCTUnwrap(
            defaults.data(forKey: "Plenact.Board.v1")) /* JSON fixture bytes for the compatibility check */

        XCTAssertEqual(try JSONDecoder().decode([KanbanList].self, from: data), last)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBackgroundBoardSaveFailurePreservesPreviousSnapshot()
    /// @brief      Retain a valid Week snapshot when a later save cannot encode
    /// @details    Uses an infinite date to force failure and checks both retained data and error
    ///             reporting
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference-suite unwrap failures
    ///
    @MainActor
    func testBackgroundBoardSaveFailurePreservesPreviousSnapshot() async throws
    {


        let suite = "Plenact.BackgroundBoardTests.\(UUID().uuidString)"  /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
            DatabaseActivity.shared.dismissError()
        }


        let original = [KanbanList(id: 1, title: "Saved", cards: [])] /* Pre-operation value for preservation checks */

        KanbanBoardPersistence.enqueueSave(original, suiteName: suite)

        _ = await KanbanBoardPersistence.loadListsInBackground(suiteName: suite)

        var invalidCard = KanbanCard(id: 1, word: "Unsaved", listTitle: "Saved") /* Unsupported Card fixture */

        invalidCard.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)

        KanbanBoardPersistence.enqueueSave(
            [KanbanList(id: 1, title: "Saved", cards: [invalidCard])], suiteName: suite
        )
        let restored = await KanbanBoardPersistence.loadListsInBackground(
            suiteName: suite) /* Restored value under verification */

        XCTAssertEqual(restored, original)
        XCTAssertTrue(DatabaseActivity.shared.errorMessage?.hasPrefix("Could not save the Board:") == true)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSearchScopesUseOnlyTheirSelectedFields()
    /// @brief      Keep Board, label, user, and all-content searches within their intended fields
    /// @details    Uses one synthetic card to distinguish matches in title, description,
    ///             assignment, and labels
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testSearchScopesUseOnlyTheirSelectedFields()
    {


        let card = KanbanCard( /* Card value under verification */
            id: 1, word: "Proposal", listTitle: "Monday",
            members: [.manual("Jamie")], labelIDs: ["work-scheduled"],
            descriptionOverride: "Budget review"
        )
        let lists = [KanbanList(id: 0, title: "Monday", cards: [card])] /* Board lists under verification */


        ///
        /// @fcn        PlenactBoardDocumentTests.testSearchScopesUseOnlyTheirSelectedFields.matches(_:_:)
        /// @brief      Query the fixed synthetic search fixture
        /// @details    Uses the starter label library for label-name and group-name matching
        ///
        /// @param[in]  term   Search text
        /// @param[in]  scope  Fields to search
        ///
        /// @return     ([TodaySearchResult]) matching canonical references
        ///
        func matches(_ term: String, _ scope: TodaySearchScope) -> [TodaySearchResult]
        {


            TodaySearchIndex.results(query: term, scope: scope, lists: lists, library: .starter)
        }


        XCTAssertEqual(matches("Scheduled", .labels).map(\.cardID), [1])
        XCTAssertEqual(matches("Work", .labels).count, 1)
        XCTAssertTrue(matches("Proposal", .labels).isEmpty)
        XCTAssertEqual(matches("Jamie", .users).map(\.cardID), [1])
        XCTAssertTrue(matches("Budget", .users).isEmpty)
        XCTAssertEqual(matches("Budget", .all).count, 1)
        XCTAssertEqual(matches("Scheduled", .all).count, 1)
        XCTAssertEqual(matches("Monday", .boards).map(\.listID), [0])
        XCTAssertTrue(matches("Proposal", .boards).isEmpty)
        XCTAssertTrue(matches(" ", .all).isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCollectionRenameAndSearchPreserveCardIdentity()
    /// @brief      Rename a personal list without replacing cards or matching dividers
    /// @details    Checks trimmed naming, synchronized list titles, active counts, and searchable
    ///             description text
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testPersonalCollectionRenameAndSearchPreserveCardIdentity()
    {


        var collection = PersonalCollection(title: "Shopping", kind: .list) /* Collection state under verification */

        collection.lists[0].cards = [
            KanbanCard(id: 9, word: "Eggs", listTitle: "Shopping", checklists: [], descriptionOverride: "Breakfast"),
            KanbanCard(id: 10, word: "Divider", listTitle: "Shopping", isDivider: true)
        ]

        collection.rename(to: "  Groceries  ")

        XCTAssertEqual(collection.title, "Groceries")
        XCTAssertEqual(collection.lists[0].title, "Groceries")
        XCTAssertEqual(collection.lists[0].cards.map(\.id), [9, 10])
        XCTAssertTrue(collection.lists[0].cards.allSatisfy
            {
                $0.listTitle == "Groceries"
            })
        XCTAssertEqual(collection.cardCount, 1)
        XCTAssertTrue(collection.matches("eggs"))
        XCTAssertTrue(collection.matches("Breakfast"))
        XCTAssertTrue(collection.matches(" "))
        XCTAssertFalse(collection.matches("Divider"))

        var board = PersonalCollection(title: "Project", kind: .board) /* Board state under verification */

        board.rename(to: "Research")

        XCTAssertEqual(board.lists.map(\.title), ["Ideas", "In progress", "Done"])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testRegisteredAssigneeRequiresUUID()
    /// @brief      Reject invalid registered-user identifiers
    /// @details    Ensures directory references use stable UUIDs instead of display names
    ///
    /// @return     (Void) succeeds when invalid registered identity is rejected
    ///
    func testRegisteredAssigneeRequiresUUID()
    {


        var card = SampleData.lists[0].cards[0] /* Starter card */

        card.members = [.registered(userID: "Jim", displayName: "Jim")]

        let document = PlenactBoardDocument( /* Invalid registered-assignee fixture */
            lists: [KanbanList(id: 0, title: "Monday", cards: [card])],
            labelLibrary: .starter
        )

        XCTAssertEqual(document.validationMessage, "Registered card assignees need a valid stable user ID.")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testManualAssigneeCannotContainUserID()
    /// @brief      Keep manual names distinct from registered accounts
    /// @details    Rejects a malformed manual assignee carrying a registered user reference
    ///
    /// @return     (Void) succeeds when the invalid mixed identity is rejected
    ///
    func testManualAssigneeCannotContainUserID()
    {


        var card = SampleData.lists[0].cards[0] /* Starter card */

        card.members = [CardAssignee(kind: .manual, userID: UUID().uuidString, displayName: "Jim")]

        let document = PlenactBoardDocument( /* Invalid manual-assignee fixture */
            lists: [KanbanList(id: 0, title: "Monday", cards: [card])],
            labelLibrary: .starter
        )

        XCTAssertEqual(document.validationMessage, "Manual card assignees cannot contain a registered user ID.")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSampleDataSeedRequestFitsJSONBodyLimit()
    /// @brief      Fit the complete synthetic seed request within the client's JSON body ceiling
    /// @details    Encodes the versioned document and request envelope, not just the Board payload
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Request encoding failures
    ///
    func testSampleDataSeedRequestFitsJSONBodyLimit() throws
    {


        let jim = PlenactRemoteUser( /* Synthetic directory-user fixture */
            userID: "fb13a9ee-9107-47c3-bb4f-dff07fe57eba",
            username: "jim",
            displayName: "Jim",
            accountRole: "board_editor"
        )
        let request = PlenactBoardWriteRequest( /* Outgoing API request */
            expectedRevision: 0,
            document: PlenactAPIClient.sampleDataDocument(for: jim),
            seedKind: "sample_data_v1"
        )
        let encodedRequest = try JSONEncoder().encode(request) /* Serialized request body */

        XCTAssertLessThanOrEqual(encodedRequest.count, PlenactAPIClient.maximumJSONBodyBytes)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testJSONBodySizeLimitIncludesExactBoundary()
    /// @brief      Verify the inclusive JSON request-size limit
    /// @details    Checks exactly one MiB is accepted and one byte more is rejected
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    func testJSONBodySizeLimitIncludesExactBoundary()
    {


        let maximumBody = Data(
            repeating: 0, count: PlenactAPIClient.maximumJSONBodyBytes) /* Allowed request-body size */
        let oversizedBody = Data(
            repeating: 0, count: PlenactAPIClient.maximumJSONBodyBytes + 1) /* Oversized request payload */

        XCTAssertTrue(PlenactAPIClient.isJSONBodyWithinLimit(maximumBody))
        XCTAssertFalse(PlenactAPIClient.isJSONBodyWithinLimit(oversizedBody))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testAPIClientRejectsPlainHTTPEndpoint()
    /// @brief      Require HTTPS for shared-demo API endpoints
    /// @details    Rejects plaintext HTTP while accepting a syntactically valid HTTPS base URL
    ///
    /// @return     (Void) succeeds when endpoint transport security is enforced
    ///
    func testAPIClientRejectsPlainHTTPEndpoint()
    {


        let insecureURL = URL(string: "http://demo.example.test/api/")! /* Test-only plaintext endpoint */

        XCTAssertThrowsError(try PlenactAPIClient(baseURL: insecureURL))
        {
            error in

            guard let apiError = error as? PlenactAPIError, /* Typed endpoint validation error */

            case .invalidEndpoint = apiError
            else
            {


                XCTFail("Expected the API client to reject plain HTTP.")

                return
            }

        }


        let secureURL = URL(string: "https://demo.example.test/api/")! /* Valid HTTPS base URL */

        XCTAssertNoThrow(try PlenactAPIClient(baseURL: secureURL))
    }

}
