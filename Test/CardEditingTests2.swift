// --------------------------------------------------------------------------------------------------
// @file       CardEditingTests2.swift
// @brief      Card Editing regression tests2
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
/// CardEditing regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedNoteToolbarLayoutPreservesContent()
    /// @brief      Verify the hosted Note toolbar layout does not mutate the Note
    /// @details    Captures portrait, landscape, and accessibility-text layouts using an in-memory
    ///             Note with synthetic attachment data
    ///
    /// @return     (Void) succeeds when hosting emits no Note changes and all layouts render
    ///
    /// @throws     XCTest unwrap failure when no window scene is available
    ///
    @MainActor
    func testHostedNoteToolbarLayoutPreservesContent() async throws
    {


        var note = KanbanCard( /* Note value under verification */
            id: 93, word: "Synthetic toolbar Note", listTitle: "Synthetic ideas",
            descriptionOverride: "A calm writing area with attachments below.",
            presentation: .note,
            createdAt: Date(timeIntervalSince1970: 1_791_422_000),
            appearance: ItemAppearance(accent: .teal, icon: .notes, background: .green)
        )
        let cover = KanbanAttachment(exampleImage: .garden)
        note.attachments = [
            cover,
            KanbanAttachment(exampleImage: .camping, caption: "Our next adventure"),
            KanbanAttachment(exampleImage: .mountains, caption: "Room to explore")
        ]
        note.coverAttachmentID = cover.id
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


        let layouts: [(String, CGSize, DynamicTypeSize)] = [ /* Hosted layout configurations */
            ("portrait", CGSize(width: 393, height: 852), .large),
            ("landscape", CGSize(width: 852, height: 393), .large),
            ("large-text", CGSize(width: 393, height: 852), .accessibility3)
        ]

        for (name, size, textSize) in layouts
        {


            var emitted: [KanbanCard] = [] /* Captured callback results               */
            let controller = UIHostingController(
                rootView: NavigationStack
                {  /* Hosted controller for layout assertions */

                    CardDetailView(card: note, onTitleToggle:
                        {
                            emitted.append($0)
                        })
                    .environment(\.dynamicTypeSize, textSize)
                })
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))

            XCTAssertTrue(emitted.isEmpty, "Toolbar/gallery layout must not rewrite the Note")
            let image = UIGraphicsImageRenderer(size: size).image
            {
            _ in /* Synthetic two-color crop source */
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            let attachment = XCTAttachment(image: image) /* Attachment fixture under test */
            attachment.name = "Note-toolbar-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNoteSharingIncludesOnlyWrittenTextAndAttachedWebLinks()
    /// @brief      Verify Note sharing includes written content and attached web links only
    /// @details    Uses synthetic Note text and mixed attachment kinds to ensure media is excluded
    ///             and the original Note record remains unchanged
    ///
    /// @return     (Void) succeeds when the share payload contains only allowed Note content
    ///
    /// @throws     XCTest unwrap failure when the synthetic web-link URL is invalid
    ///
    func testNoteSharingIncludesOnlyWrittenTextAndAttachedWebLinks() throws
    {


        var note = SampleData.lists[0].cards[0] /* Note value under verification */
        note.word = "Synthetic shared note"
        note.presentation = .note
        note.descriptionOverride = "First line\n\nSecond line  "
        let link = try XCTUnwrap(URL(string: "https://example.com/synthetic-note")) /* Synthetic link target */
        note.attachments = [
            KanbanAttachment(fileName: "synthetic-private-photo.jpg", mediaKind: .photo),
            KanbanAttachment(fileName: "synthetic-private-video.mov", mediaKind: .video),
            KanbanAttachment(url: link),
            KanbanAttachment(exampleImage: .garden)
        ]
        let original = note /* Pre-operation value for preservation checks */

        XCTAssertEqual(
            NoteTextSharing.text(for: note),
                            "Synthetic shared note\n\nFirst line\n\nSecond line  \n\nhttps://example.com/synthetic-note"
        )
        XCTAssertEqual(note, original, "Preparing a share must not change the saved record")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNoteSharingDoesNotFillEmptyBodyWithGeneratedDescription()
    /// @brief      Verify sharing does not synthesize text for an empty Note body
    /// @details    Confirms the title is shared alone and whitespace-only body content is retained
    ///             rather than replaced with generated descriptive text
    ///
    /// @return     (Void) succeeds when the share payload reflects only explicitly written text
    ///
    func testNoteSharingDoesNotFillEmptyBodyWithGeneratedDescription()
    {


        var note = KanbanCard(
            id: 92, word: "Empty synthetic Note", listTitle: "Private list", presentation: .note) /* Note value under verification */

        XCTAssertEqual(NoteTextSharing.text(for: note), "Empty synthetic Note")
        note.descriptionOverride = ""

        XCTAssertEqual(NoteTextSharing.text(for: note), "Empty synthetic Note")
        note.descriptionOverride = " \n "

        XCTAssertEqual(NoteTextSharing.text(for: note), "Empty synthetic Note\n\n \n ")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewPersonalNoteDraftSavesOnlyToSelectedList()
    /// @brief      Verify a new Note is saved only to its selected personal List
    /// @details    Checks destination selection has no side effects before save and that the
    ///             persisted Note retains its body, type, List, and original draft timestamp
    ///
    /// @return     (Void) succeeds when exactly the selected collection receives the Note
    ///
    /// @throws     XCTest unwrap failure when the persisted synthetic Note cannot be found
    ///
    func testNewPersonalNoteDraftSavesOnlyToSelectedList() throws
    {


        let initial = PersonalCollection(
            title: "Initial ideas", kind: .list) /* Initial destination collection to preserve   */
        let selected = PersonalCollection(
            title: "Selected ideas", kind: .list)                     /* Selected destination collection for the Note */
        var collections = [initial, selected]                         /* Saved personal-collection state              */
        var draft = PersonalListNoteDraft(destinationID: initial.id)  /* Uncommitted draft under test                 */
        let originalCreationDate = draft.createdAt                    /* Timestamp retained by the operation          */

        draft.title = "  New idea  "
        draft.body = "First line\n\nSecond line  "
        draft.destinationID = selected.id

        XCTAssertEqual(collections, [initial, selected], "Selecting a List must not create or move content")
        XCTAssertEqual(draft.destination(in: collections), selected)

        var saves = 0 /* Save-callback invocation count */
        try draft.save(in: collections)
        {
            destinationID, title, body, createdAt in
            saves += 1

            XCTAssertEqual(createdAt, originalCreationDate)
            let index = try XCTUnwrap(
                collections.firstIndex
                {
                    $0.id == destinationID
                }) /* Selected collection index */
            try collections[index].addNote(title: title, body: body, createdAt: createdAt)
        }


        XCTAssertEqual(saves, 1)
        XCTAssertEqual(collections[0], initial)
        XCTAssertEqual(collections[1].lists[0].cards.count, 1)
        let note = try XCTUnwrap(collections[1].lists[0].cards.first) /* Note value under verification */

        XCTAssertEqual(note.word, "New idea")
        XCTAssertEqual(note.descriptionOverride, draft.body)
        XCTAssertEqual(note.listTitle, selected.title)
        XCTAssertEqual(note.presentation, .note)
        XCTAssertEqual(note.createdAt, originalCreationDate)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewPersonalNoteDraftRejectsUnavailableDestinationsAndBlankTitle()
    /// @brief      Verify invalid Note destinations and blank titles cannot be saved
    /// @details    Covers Board collections, archived collections, collections without active
    ///             Lists, unknown identities, and whitespace-only titles
    ///
    /// @return     (Void) succeeds when invalid drafts are rejected before persistence is called
    ///
    func testNewPersonalNoteDraftRejectsUnavailableDestinationsAndBlankTitle()
    {


        let active = PersonalCollection(
            title: "Active ideas", kind: .list) /* Active personal collection used as an invalid target */
        let board = PersonalCollection(
            title: "Projects", kind: .board) /* Board state under verification                       */
        var archived = PersonalCollection(
            title: "Archived ideas", kind: .list) /* Archived value for restoration checks                */
        archived.isArchived = true
        var empty = PersonalCollection(title: "No active list", kind: .list) /* Empty collection fixture */
        empty.lists[0].isArchived = true
        let collections = [active, board, archived, empty] /* Saved personal-collection state */

        XCTAssertEqual(PersonalListNoteDraft.destinations(in: collections), [active])

        for id in [board.id, archived.id, empty.id, UUID()]
        {


            let draft = PersonalListNoteDraft(
                destinationID: id, title: "Idea", body: "Unsaved body") /* Uncommitted draft under test */

            XCTAssertFalse(draft.canSave(in: collections))
            XCTAssertThrowsError(
                try draft.save(in: collections)
                {
                    _, _, _, _ in
                    XCTFail("An unavailable destination must not reach persistence")
                })
        }


        let blank = PersonalListNoteDraft(
            destinationID: active.id, title: " \n ", body: "Unsaved body") /* Blank Note fixture */

        XCTAssertFalse(blank.canSave(in: collections))
        XCTAssertThrowsError(
            try blank.save(in: collections)
            {
                _, _, _, _ in
                XCTFail("A blank title must not reach persistence")
            })
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewPersonalNoteDraftPreservesSelectionAndTextAfterFailedSave()
    /// @brief      Verify a failed Note save preserves the draft for retry
    /// @details    Makes the synthetic persistence callback fail, confirms the destination, title,
    ///             body, and creation timestamp remain intact, then verifies a retry can succeed
    ///
    /// @return     (Void) succeeds when failed persistence does not discard editable draft state
    ///
    /// @throws     XCTest unwrap failure when the retry callback receives unexpected values
    ///
    func testNewPersonalNoteDraftPreservesSelectionAndTextAfterFailedSave() throws
    {


        let initial = PersonalCollection(
            title: "Initial ideas", kind: .list) /* Initial destination collection to preserve   */
        let selected = PersonalCollection(
            title: "Selected ideas", kind: .list)                     /* Selected destination collection for the Note */
        let collections = [initial, selected]                         /* Saved personal-collection state              */
        var draft = PersonalListNoteDraft(destinationID: initial.id)  /* Uncommitted draft under test                 */
        let originalCreationDate = draft.createdAt                    /* Timestamp retained by the operation          */
        draft.title = "  Retry idea  "
        draft.body = "Retained body\n  "
        draft.destinationID = selected.id

        XCTAssertThrowsError(
            try draft.save(in: collections)
            {
                id, title, body, createdAt in

                XCTAssertEqual(createdAt, originalCreationDate)
                XCTAssertEqual(id, selected.id)
                XCTAssertEqual(title, "Retry idea")
                XCTAssertEqual(body, draft.body)
                throw CocoaError(.fileWriteNoPermission)
            })

        XCTAssertEqual(draft.destinationID, selected.id)
        XCTAssertEqual(draft.title, "  Retry idea  ")
        XCTAssertEqual(draft.body, "Retained body\n  ")
        XCTAssertEqual(collections, [initial, selected])
        XCTAssertTrue(draft.canSave(in: collections))

        var saves = 0 /* Save-callback invocation count */
        try draft.save(in: collections)
        {
            id, _, _, createdAt in

            XCTAssertEqual(id, selected.id)
            XCTAssertEqual(createdAt, originalCreationDate)
            saves += 1
        }


        XCTAssertEqual(saves, 1)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalNoteMovePreservesContentAndResolvesCollectionLocalIDCollision()
    /// @brief      Move a Note across personal Lists without losing content or bookmarks
    /// @details    Reassigns only a colliding destination-local ID and leaves unrelated/archived
    ///             destination records and invalid move snapshots unchanged
    ///
    /// @return     (Void) records cross-collection move assertions
    /// @throws     Fixture setup, decoding, or checked creation errors propagate to XCTest.
    ///
    func testPersonalNoteMovePreservesContentAndResolvesCollectionLocalIDCollision() throws
    {


        let attachment = KanbanAttachment(
            fileName: "synthetic-moved-note.jpg", mediaKind: .photo)  /* Attachment fixture under test */
        var note = KanbanCard(                                        /* Note value under verification */
            id: 4, word: "Beach idea", listTitle: "Ideas",
            checklists: [KanbanChecklist(title: "Keep", items: ["Discuss"])],
            descriptionOverride: "First paragraph\n\nSecond paragraph",
            presentation: .note,
            createdAt: Date(timeIntervalSince1970: 1_791_422_000)
        )
        note.attachments = [attachment]
        note.coverAttachmentID = attachment.id
        note.labelIDs = ["keep-this-label"]
        note.comments = [KanbanComment(author: "Synthetic", body: "Keep this comment")]

        var source = PersonalCollection(title: "Ideas", kind: .list) /* Source state before the operation */
        source.lists[0].cards = [note]
        source.savedCardIDs = [note.id]

        var destination = PersonalCollection(title: "Someday", kind: .list) /* Target location for the move */
        destination.lists[0].cards = [
            KanbanCard(id: 4, word: "ID collision", listTitle: "Someday", checklists: [])
        ]
        destination.lists[0].archivedCards = [
            KanbanCard(id: 9, word: "Archived ID", listTitle: "Someday", checklists: [])
        ]
        destination.savedCardIDs = [4]

        var collections = [source, destination]               /* Saved personal-collection state       */
        let moved = try PersonalCollectionNoteMovement.move(  /* Note after relocation to another List */
            noteID: note.id, from: source.id, to: destination.id, in: &collections
        )

        let expected = note.replacingLocation(
            id: 10, listTitle: destination.title) /* Expected result for comparison */

        XCTAssertEqual(moved, expected)
        XCTAssertEqual(moved.createdAt, note.createdAt)
        XCTAssertNotNil(moved.createdAt)
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        XCTAssertFalse(collections[0].savedCardIDs.contains(note.id))
        XCTAssertEqual(
            collections[1].lists[0].cards,
            [
                destination.lists[0].cards[0], expected
            ])
        XCTAssertEqual(collections[1].lists[0].archivedCards, destination.lists[0].archivedCards)
        XCTAssertEqual(collections[1].savedCardIDs, [4, expected.id])

        let beforeInvalidMove = collections /* Collection snapshot before invalid movement */

        XCTAssertThrowsError(
            try PersonalCollectionNoteMovement.move(
                noteID: expected.id, from: source.id, to: UUID(), in: &collections
            ))
        XCTAssertEqual(collections, beforeInvalidMove)

        let board = PersonalCollection(
            title: "Not a destination List", kind: .board)  /* Board state under verification */
        var boardMove = [source, board]                     /* Board movement result          */
        let beforeBoardMove = boardMove                     /* Board snapshot before movement */

        XCTAssertThrowsError(
            try PersonalCollectionNoteMovement.move(
                noteID: note.id, from: source.id, to: board.id, in: &boardMove
            ))
        XCTAssertEqual(boardMove, beforeBoardMove)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalNoteMovePreservesNonconflictingID()
    /// @brief      Keep the Note's local ID when its destination has no collision
    /// @details    Moves the original Note record and updates only its containing List title
    ///
    /// @return     (Void) records stable-ID and source-removal assertions
    /// @throws     Fixture setup, decoding, or checked creation errors propagate to XCTest.
    ///
    func testPersonalNoteMovePreservesNonconflictingID() throws
    {


        var source = PersonalCollection(title: "Ideas", kind: .list) /* Source state before the operation */
        var note = KanbanCard(
            id: 14, word: "Read later", listTitle: "Ideas", checklists: [], presentation: .note) /* Note value under verification     */
        note.descriptionOverride = "Synthetic body"
        source.lists[0].cards = [note]

        let destination = PersonalCollection(title: "Someday", kind: .list)  /* Target location for the move    */
        var collections = [source, destination]                              /* Saved personal-collection state */

        let moved = try PersonalCollectionNoteMovement.move( /* Note after relocation to another List */
            noteID: note.id, from: source.id, to: destination.id, in: &collections
        )

        XCTAssertEqual(moved.id, note.id)
        XCTAssertEqual(moved.listTitle, destination.title)
        XCTAssertEqual(moved.descriptionOverride, note.descriptionOverride)
        XCTAssertTrue(collections[0].lists[0].cards.isEmpty)
        XCTAssertEqual(collections[1].lists[0].cards, [moved])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedNoteBodyEditsEmitCompleteRetainedSnapshots()
    /// @brief      Exercise the actual hosted writing field and its canonical update callback
    /// @details    Edits synthetic body text through the native text-view delegate and checks
    ///             that layout is read-only and hidden checklist/completion state survives
    ///
    /// @return     (Void) records editor/persistence callback assertion failures
    /// @throws     Native editor lookup or layout delay failures
    ///
    @MainActor
    func testHostedNoteBodyEditsEmitCompleteRetainedSnapshots() async throws
    {


        var note = SampleData.lists[0].cards[0] /* Note value under verification */
        note.appearance = ItemAppearance(accent: .blue, icon: .heart, background: .rose)
        note.presentation = .note
        note.descriptionOverride = "Synthetic note body"
        note.isTitleChecked = true

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
        /// @fcn        PlenactBoardDocumentTests.testHostedNoteBodyEditsEmitCompleteRetainedSnapshots.textViews(in:)
        /// @brief      Find native multiline editors in the hosted Note
        /// @details    Recurses through view children without changing the hierarchy
        ///
        /// @param[in]  view  Root to inspect
        ///
        /// @return     ([UITextView]) native multiline text fields
        ///
        func textViews(in view: UIView) -> [UITextView]
        {


            (view as? UITextView).map
            {
                [$0]
            }
            ?? view.subviews.flatMap
            {
                textViews(in: $0)
            }

        }


        let emptyNote = KanbanCard( /* Note with an empty body */
            id: 91, word: "Empty", listTitle: "Synthetic", checklists: [], presentation: .note,
            createdAt: Date(timeIntervalSince1970: 1_791_422_000)
        )

        for fixture in [note, emptyNote]
        {


            var emitted: [KanbanCard] = [] /* Captured callback results */

            let controller = UIHostingController(
                rootView: CardDetailView( /* Hosted controller for layout assertions */
                    card: fixture, onTitleToggle:
                    {
                        emitted.append($0)
                    }
                ))

            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = controller

            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()

            try await Task.sleep(for: .milliseconds(150))

            XCTAssertTrue(emitted.isEmpty, "Opening and laying out a Note must not save or rewrite it")

            let titleEditor = try XCTUnwrap(
                textViews(in: controller.view).first
                {
                    $0.text == fixture.word
                }) /* Hosted title editor */
            titleEditor.text = "Updated synthetic title"

            titleEditor.delegate?.textViewDidChange?(titleEditor)

            try await Task.sleep(for: .milliseconds(150))

            var expected = fixture /* Expected result for comparison */
            expected.word = titleEditor.text

            XCTAssertEqual(
                emitted.last, expected, "Title edits must not fill an unwritten Note body with generated copy")

            let editor = try XCTUnwrap(
                textViews(in: controller.view).first
                {
                    $0.text == (fixture.descriptionOverride ?? "")
                }) /* Editor state under test */
            editor.text = "Edited synthetic body\nSecond paragraph"

            editor.delegate?.textViewDidChange?(editor)

            try await Task.sleep(for: .milliseconds(150))

            expected.descriptionOverride = editor.text

            XCTAssertEqual(emitted.last, expected)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekRootRequestPopsCardDetailWithoutChangingContent()
    /// @brief      Return from a hosted Card Detail to the Week Board without changing records
    /// @details    Opens a synthetic card through canonical routing, then changes the explicit
    ///             root request and checks the real navigation controller stack and retained data
    ///
    /// @return     (Void) records assertion failures for navigation or content regressions
    ///
    /// @throws     Fixture or navigation-controller unwrap failures and task cancellation
    ///
    @MainActor
    func testWeekRootRequestPopsCardDetailWithoutChangingContent() async throws
    {


        var lists = SampleData.lists  /* Board lists under verification              */
        let original = lists          /* Pre-operation value for preservation checks */
        let card = try XCTUnwrap(
            lists[0].cards.first
            {
                !$0.isSectionDivider
            })                              /* Card value under verification                            */
        var targetList: Int? = lists[0].id  /* List identity selected before returning to the Week root */
        var targetCard: Int? = card.id      /* Card identity selected before returning to the Week root */
        var saved: Set<Int> = [card.id]     /* Persisted value under verification                       */


        ///
        /// @fcn        PlenactBoardDocumentTests.testWeekRootRequestPopsCardDetailWithoutChangingContent.board(_:)
        /// @brief      Construct the same Board identity with a new root request
        /// @details    Reuses fixture bindings so hosting updates preserve navigation state
        ///
        /// @param[in]  request  Explicit Board-root request value
        ///
        /// @return     (ContentView) synthetic Board with canonical navigation bindings
        ///
        func board(_ request: Int) -> ContentView
        {


            ContentView(
                lists: Binding(get:
                    {
                        lists
                    }, set:
                    {
                        lists = $0
                    }),
                boardTargetListID: Binding(get:
                    {
                        targetList
                    }, set:
                    {
                        targetList = $0
                    }),
                boardTargetCardID: Binding(get:
                    {
                        targetCard
                    }, set:
                    {
                        targetCard = $0
                    }),
                boardRootRequest: request,
                savedCardIDs: Binding(get:
                    {
                        saved
                    }, set:
                    {
                        saved = $0
                    }),
                onListsChanged:
                {
                    _ in
                    XCTFail("Returning to Week must not save or edit records")
                },
                retainedAttachmentLists:
                {
                    []
                }
            )
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testWeekRootRequestPopsCardDetailWithoutChangingContent.navigation(in:)
        /// @brief      Locate the hosted Board's native navigation controller
        /// @details    Recursively searches child controllers without altering their hierarchy
        ///
        /// @param[in]  controller  Root controller to inspect
        ///
        /// @return     (UINavigationController?) first navigation controller found
        ///
        func navigation(in controller: UIViewController) -> UINavigationController?
        {


            if let navigation = controller
            as? UINavigationController /* Navigation controller found in the hosted hierarchy */
            {


                return navigation
            }


            return controller.children.compactMap
            {
                navigation(in: $0)
            } .first
        }


        let controller = UIHostingController(rootView: board(0)) /* Hosted controller for layout assertions */
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


        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller

        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        try await Task.sleep(for: .milliseconds(600))

        let stack = try XCTUnwrap(navigation(in: controller)) /* Navigation stack under test */

        XCTAssertEqual(stack.viewControllers.count, 2, "The fixture must actually open Card Detail")

        controller.rootView = board(1)

        try await Task.sleep(for: .milliseconds(600))

        XCTAssertEqual(stack.viewControllers.count, 1, "An explicit Week tap must pop Card Detail")
        XCTAssertEqual(lists, original)
        XCTAssertEqual(saved, [card.id])
        XCTAssertNil(targetList)
        XCTAssertNil(targetCard)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDayViewNativeDragReordersCanonicalNotesAndPreservesCancelledDrags()
    /// @brief      Exercise the focused Day view's actual native drag and drop callbacks
    /// @details    Checks append, divider boundaries, cancellation, and outside drops against
    ///             the canonical binding without changing record content.
    ///
    /// @return     (Void) records assertion failures for interaction installation or row layout
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    @MainActor
    func testDayViewNativeDragReordersCanonicalNotesAndPreservesCancelledDrags() async throws
    {

        let note = KanbanCard(
            id: 10, word: "Synthetic Note", listTitle: "Thursday",
            checklists: [], descriptionOverride: "Retained body", presentation: .note)
        let divider = KanbanCard(id: 11, word: "--", listTitle: "Thursday", isDivider: true, checklists: [])
        let card = KanbanCard(id: 12, word: "Synthetic Card", listTitle: "Thursday", checklists: [])
        var lists = [KanbanList(id: 4, title: "Thursday", cards: [note, divider, card])]
        let original = lists
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
        /// @fcn        PlenactBoardDocumentTests.testDayViewNativeDragReordersCanonicalNotesAndPreservesCancelledDrags.collectionView
        /// @brief      Find collection view in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UICollectionView. Returns the first qualifying match,
        ///             or nil when none is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UICollectionView?) matching or resolved value, or nil when unavailable
        ///
        func collectionView(in view: UIView) -> UICollectionView?
        {

            if let collection = view as? UICollectionView
            {
                return collection
            }

            return view.subviews.compactMap
            {
                collectionView(in: $0)
            } .first
        }

        let controller = UIHostingController(
            rootView: TodayListDetailView(
                lists: Binding(get:
                    {
                        lists
                    }, set:
                    {
                        lists = $0
                    }), reservedLists: [],
                labelLibrary: .constant(.starter), savedCardIDs: .constant([note.id]),
                listID: 4, currentUserName: "Synthetic", onClose:
                {

                }, onOpenWeek:
                {

                },
                onPermanentDelete:
                {
                    _ in
                    XCTFail("Dragging must not delete");
                    return false
                }
            ))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        TransferConfirmationPresenter.shared.showUndo(
            TransferConfirmation(title: "Other section", destination: "Another day")
        )
        {
            true
        }

        defer
        {
            TransferConfirmationPresenter.shared.dismiss()
        }

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(scene.windows.contains
            {
                !$0.isHidden && $0.windowLevel > .alert
            })
        let collection = try XCTUnwrap(collectionView(in: controller.view))
        let noteCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let source = try XCTUnwrap(
            noteCell.contentView.interactions.compactMap
            {

                ($0 as? UIDragInteraction)?.delegate as? BoardCardDragSource.Coordinator
            } .first)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 4)
        let receiver = try XCTUnwrap(collection.dropDelegate as? BoardCardDropSurface.Coordinator)
        let item = UIDragItem(itemProvider: source.begin(at: noteCell.convert(CGPoint(x: 30, y: 30), to: window)))
        item.localObject = source
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(receiver.accepts([item]))
        XCTAssertFalse(receiver.perform([item], at: CGPoint(x: -100, y: -100)))
        source.finish()
        XCTAssertEqual(lists, original, "An outside drop must not mutate canonical records")

        let secondItem = UIDragItem(itemProvider: source.begin(at: noteCell.convert(CGPoint(x: 30, y: 30), to: window)))
        secondItem.localObject = source
        try await Task.sleep(for: .milliseconds(100))
        let addCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 3, section: 0)))
        let endPoint = addCell.convert(CGPoint(x: 30, y: addCell.bounds.midY), to: window)
        XCTAssertTrue(receiver.perform([secondItem], at: endPoint))
        source.finish()
        XCTAssertEqual(lists[0].cards, [divider, card, note])
        XCTAssertEqual(Set(lists[0].cards.map(\.id)), Set(original[0].cards.map(\.id)))

        try await Task.sleep(for: .milliseconds(150))
        let currentCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 2, section: 0)))
        let currentSource = try XCTUnwrap(
            currentCell.contentView.interactions.compactMap
            {

                ($0 as? UIDragInteraction)?.delegate as? BoardCardDragSource.Coordinator
            } .first)
        _ = currentSource.begin(at: currentCell.convert(CGPoint(x: 30, y: 30), to: window))
        currentSource.finish()
        XCTAssertEqual(lists[0].cards, [divider, card, note], "Cancelled drags retain order and content")

        let returnItem = UIDragItem(
            itemProvider: currentSource.begin(
                at: currentCell.convert(CGPoint(x: 30, y: 30), to: window)
            ))
        returnItem.localObject = currentSource
        try await Task.sleep(for: .milliseconds(100))
        let dividerCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let firstPoint = dividerCell.convert(CGPoint(x: 30, y: 1), to: window)
        let currentReceiver = try XCTUnwrap(collection.dropDelegate as? BoardCardDropSurface.Coordinator)
        XCTAssertTrue(currentReceiver.perform([returnItem], at: firstPoint))
        currentSource.finish()
        XCTAssertEqual(lists, original, "Dragging before a divider must restore the original complete records")

        try await Task.sleep(for: .milliseconds(150))
        let movableDividerCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
        let dividerSource = try XCTUnwrap(
            movableDividerCell.contentView.interactions.compactMap
            {

                ($0 as? UIDragInteraction)?.delegate as? BoardCardDragSource.Coordinator
            } .first)
        let dividerItem = UIDragItem(
            itemProvider: dividerSource.begin(
                at: movableDividerCell.convert(CGPoint(x: 30, y: 10), to: window)
            ))
        dividerItem.localObject = dividerSource
        try await Task.sleep(for: .milliseconds(100))
        let dividerReceiver = try XCTUnwrap(collection.dropDelegate as? BoardCardDropSurface.Coordinator)
        let tailCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 3, section: 0)))
        XCTAssertTrue(
            dividerReceiver.perform(
                [dividerItem],
                at: tailCell.convert(
                    CGPoint(x: 30, y: tailCell.bounds.midY), to: window
                )))
        dividerSource.finish()
        XCTAssertEqual(lists[0].cards, [note, card, divider])
    }

}
