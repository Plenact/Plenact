// --------------------------------------------------------------------------------------------------
// @file       CaptureTests.swift
// @brief      Capture regression tests
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
/// Capture regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testPlanPreferencesSaveWithoutCreatingProfileAndShareProfileEdits
    /// @brief      Verify that plan Preferences Save Without Creating Profile And Share Profile Edits
    /// @details    Exercises `PlanPreferencesStore.load`, `PlanPreferencesStore.save`, `LocalProfileStore.load`.
    ///             Checks `XCTAssertEqual(PlanPreferencesStore.load(from: defaults).todayFocusItemCount, 4)`;
    ///             `XCTAssertNil(LocalProfileStore.load(from: defaults))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPlanPreferencesSaveWithoutCreatingProfileAndShareProfileEdits() throws
    {

        let suite = "PlanSettingsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        XCTAssertEqual(PlanPreferencesStore.load(from: defaults).todayFocusItemCount, 4)
        var preferences = LocalProfilePreferences()
        preferences.todayFocusItemCount = 8
        preferences.showsDueDatesOnNewCards = false
        PlanPreferencesStore.save(preferences, to: defaults)
        XCTAssertNil(LocalProfileStore.load(from: defaults))
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
        XCTAssertFalse(KanbanCard.defaultDueDateVisibility(from: defaults))
        preferences.todayFocusItemCount = 2
        let profile = LocalProfile(displayName: "Test", preferences: preferences)
        LocalProfileStore.save(profile, to: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
        LocalProfileStore.remove(from: defaults)
        XCTAssertEqual(PlanPreferencesStore.load(from: defaults), preferences)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testInlineListCaptureRetainsFailedDraftAndCreatesDestinationItems
    /// @brief      Verify quick entry uses canonical creation for ordinary and Day Lists
    /// @details    Checks repeated capture, Card and Note defaults, whitespace rejection, archived
    ///             destinations, and retention of the original writing after a rejected save.
    ///
    /// @return     (Void) no return value
    ///
    func testInlineListCaptureRetainsFailedDraftAndCreatesDestinationItems()
    {

        for title in ["Projects", "Monday", "On the Table", "In the Queue", "Scheduled"]
        {

            for presentation in [ItemPresentation.card, .note]
            {

                var list = KanbanList(id: 7, title: title, cards: [], newItemPresentation: presentation)
                var draft = InlineListCaptureDraft(title: "  First thought  ")
                XCTAssertFalse(draft.submit(to: list)
                    {
                        _ in
                        false
                    })
                XCTAssertEqual(draft.title, "  First thought  ")
                for text in ["  First thought  ", "Another thought"]
                {

                    draft.title = text
                    let destination = list
                    XCTAssertTrue(
                        draft.submit(to: destination)
                        {
                            capture in
                            guard
                            let items = ListItemCreation.items(
                                capture, in: destination,
                                startingAt: list.cards.count + 20)
                            else
                            {
                                return false
                            }

                            list.cards.append(contentsOf: items)
                            return true
                        })
                    XCTAssertEqual(draft.title, "")
                }

                XCTAssertEqual(list.cards.map(\.word), ["First thought", "Another thought"])
                XCTAssertTrue(list.cards.allSatisfy
                    {
                        $0.listTitle == title && $0.presentation == presentation
                    })
                XCTAssertEqual(Set(list.cards.map(\.id)).count, 2)
                draft.title = " \n "
                XCTAssertFalse(
                    draft.submit(to: list)
                    {
                        _ in
                        XCTFail("Blank titles must not save");
                        return true
                    })
                list.isArchived = true
                draft.title = "Keep this draft"
                XCTAssertFalse(
                    draft.submit(to: list)
                    {
                        capture in
                        ListItemCreation.items(capture, in: list, startingAt: 30) != nil
                    })
                XCTAssertEqual(draft.title, "Keep this draft")
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalListFullComposerRetainsScheduleAndActions
    /// @brief      Verify that personal List Full Composer Retains Schedule And Actions
    /// @details    Exercises `.now.addingTimeInterval`, `collection.addNote`, `card.checklists.flatMap(\.items).map`.
    ///             Checks `XCTAssertEqual(card.checklists.flatMap(\.items).map(\.title), ["First", "Second"])`;
    ///             `XCTAssertEqual(card.startDate, schedule.start)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testPersonalListFullComposerRetainsScheduleAndActions() throws
    {

        var collection = PersonalCollection(title: "Personal", kind: .list)
        let schedule = QuickCaptureSchedule(start: .now, stop: .now.addingTimeInterval(3600), includesTime: true)
        try collection.addNote(
            title: "Card", body: "Details", presentation: .card,
            actions: ["First", "Second"], schedule: schedule)
        let card = try XCTUnwrap(collection.lists[0].cards.last)
        XCTAssertEqual(card.checklists.flatMap(\.items).map(\.title), ["First", "Second"])
        XCTAssertEqual(card.startDate, schedule.start)
        XCTAssertEqual(card.dueDate, schedule.stop)
        let before = collection
        let invalid = QuickCaptureSchedule(start: .now, stop: .distantPast, includesTime: true)
        XCTAssertThrowsError(try collection.addNote(title: "Invalid", body: "", schedule: invalid))
        XCTAssertEqual(collection, before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewComposerSharesTitleAndRichBodyAcrossCardAndNote
    /// @brief      Verify that new Composer Shares Title And Rich Body Across Card And Note
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`, `.constant`.
    ///             Checks `XCTAssertEqual(noteTitle.text, "Shared draft title")`;
    ///             `XCTAssertEqual(PlanRichText.runs(PlanRichText.encode(writing.attributedText)),
    ///             PlanRichText.runs(body))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testNewComposerSharesTitleAndRichBodyAcrossCardAndNote() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let lists = [KanbanList(id: 0, title: "Monday", cards: [])]
        let host = UIHostingController(
            rootView: QuickNoteComposer(lists: .constant(lists), initialListID: 0)
            {
                _, _, _, _, _, _ in
                XCTFail("Switching formats must not create content")
            })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(300))


        ///
        /// @fcn        PlenactBoardDocumentTests.testNewComposerSharesTitleAndRichBodyAcrossCardAndNote.descendants
        /// @brief      Find descendants in the hosted view hierarchy
        /// @details    Recursively inspects native subviews. Returns all collected matches in hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIView]) resulting values in the ordering described above
        ///
        func descendants(_ view: UIView) -> [UIView]
        {
            [view] + view.subviews.flatMap(descendants)
        }

        let title = try XCTUnwrap(
            descendants(host.view).compactMap
            {
                $0 as? UITextView
            } .first
            {

                String(describing: type(of: $0)).contains("VerticalTextView")
            })
        title.becomeFirstResponder()
        title.insertText("Shared draft title")
        let details = try XCTUnwrap(
            descendants(host.view).compactMap
            {
                $0 as? UITextView
            } .first
            {

                $0.accessibilityLabel == "Details (optional)"
            })
        let body =
        PlanRichText.prefix
        + Data("[{\"text\":\"Keep this writing\",\"bold\":true,\"italic\":false}]".utf8).base64EncodedString()
        details.attributedText = PlanRichText.attributed(body)
        details.delegate?.textViewDidChange?(details)
        let picker = try XCTUnwrap(descendants(host.view).compactMap
            {
                $0 as? UISegmentedControl
            } .first)
        picker.selectedSegmentIndex = 1
        picker.sendActions(for: .valueChanged)
        try await Task.sleep(for: .milliseconds(350))
        let noteTitle = try XCTUnwrap(
            descendants(host.view).compactMap
            {
                $0 as? UITextView
            } .first
            {

                String(describing: type(of: $0)).contains("VerticalTextView")
            })
        XCTAssertEqual(noteTitle.text, "Shared draft title")
        let writing = try XCTUnwrap(
            descendants(host.view).compactMap
            {
                $0 as? UITextView
            } .first
            {

                $0.accessibilityLabel == "Start writing..."
            })
        XCTAssertEqual(PlanRichText.runs(PlanRichText.encode(writing.attributedText)), PlanRichText.runs(body))
        noteTitle.becomeFirstResponder()
        noteTitle.insertText(" edited")
        writing.attributedText = PlanRichText.attributed("Edited note body")
        writing.delegate?.textViewDidChange?(writing)
        picker.selectedSegmentIndex = 0
        picker.sendActions(for: .valueChanged)
        try await Task.sleep(for: .milliseconds(350))
        let returnedTitle = try XCTUnwrap(
            descendants(host.view).compactMap
            {
                $0 as? UITextView
            } .first
            {

                String(describing: type(of: $0)).contains("VerticalTextView")
            })
        XCTAssertEqual(returnedTitle.text, "Shared draft title edited")
        let returnedDetails = try XCTUnwrap(
            descendants(host.view).compactMap
            {
                $0 as? UITextView
            } .first
            {

                $0.accessibilityLabel == "Details (optional)"
            })
        XCTAssertEqual(PlanRichText.encode(returnedDetails.attributedText), "Edited note body")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDetachListCreatesStandaloneLibraryCollectionWithoutCopying
    /// @brief      Verify that detach List Creates Standalone Library Collection Without Copying
    /// @details    Exercises `.linkedCard`, `CrossBoardListMovement.detach`. Checks
    ///             `XCTAssertEqual(collections.count, 2)`; `XCTAssertTrue(collections[0].lists.isEmpty)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testDetachListCreatesStandaloneLibraryCollectionWithoutCopying() throws
    {

        for title in ["Week board", "Library board"]
        {

            var source = PersonalCollection(title: title, kind: .board, icon: .home, color: .green)
            var card = KanbanCard(
                id: 8, word: "Keep this note", listTitle: "Garden", descriptionOverride: "Original writing")
            card.displayFormat = .note
            card.checklists = [
                KanbanChecklist(
                    title: "Link", items: [KanbanChecklistItem(title: "Archived", content: .linkedCard(cardID: 9))])
            ]
            let archive = KanbanCard(id: 9, word: "Archived", listTitle: "Garden")
            var list = KanbanList(
                id: 4, title: "Garden", cards: [card], archivedCards: [archive], newItemPresentation: .note)
            list.subtitleOverride = "Seasonal notes"
            list.appearance = ItemAppearance(accent: .green)
            source.lists = [list]
            source.savedCardIDs = [8, 9]
            var collections = [source]
            let result = try CrossBoardListMovement.detach(listID: list.id, from: source.id, collections: &collections)
            XCTAssertEqual(collections.count, 2)
            XCTAssertTrue(collections[0].lists.isEmpty)
            XCTAssertTrue(collections[0].savedCardIDs.isEmpty)
            XCTAssertEqual(result.kind, .list)
            XCTAssertEqual(result.title, list.title)
            XCTAssertEqual(result.color, source.color)
            XCTAssertEqual(result.lists.count, 1)
            XCTAssertEqual(result.savedCardIDs, [8, 9])
            XCTAssertEqual(result.lists[0].id, list.id)
            XCTAssertEqual(result.lists[0].appearance, list.appearance)
            XCTAssertEqual(result.lists[0].subtitleOverride, list.subtitleOverride)
            XCTAssertEqual(result.lists[0].newItemPresentation, .note)
            XCTAssertEqual(result.lists[0].cards[0].descriptionOverride, card.descriptionOverride)
            XCTAssertEqual(result.lists[0].archivedCards, [archive])
            XCTAssertEqual(result.lists[0].cards[0].checklists[0].items[0].linkedCollectionID, result.id)
            XCTAssertEqual(
                try JSONDecoder().decode([PersonalCollection].self, from: JSONEncoder().encode(collections)),
                collections)
        }

        var empty = [PersonalCollection]()
        XCTAssertThrowsError(try CrossBoardListMovement.detach(listID: 4, from: UUID(), collections: &empty))
        XCTAssertTrue(empty.isEmpty)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreationSessionClearsLiveDraftAndRejectsDismissalCallbacks
    /// @brief      Verify that creation Session Clears Live Draft And Rejects Dismissal Callbacks
    /// @details    Exercises `ListCreationDraft.clear`, `draft.beginSession`, `draft.binding`. Checks
    ///             `XCTAssertEqual(ListCreationDraft.load(key: key).title, "New card")`; `XCTAssertEqual(draft.title,
    ///             "")`.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func testCreationSessionClearsLiveDraftAndRejectsDismissalCallbacks()
    {

        let key = "test.creation.reset." + UUID().uuidString
        defer
        {
            ListCreationDraft.clear(key: key)
        }

        let draft = ListCreationDraftModel(key: key)
        for _ in 0 ..< 2
        {

            draft.beginSession()
            draft.binding(\.title).wrappedValue = "New card"
            draft.binding(\.subtitle).wrappedValue = "Subtitle"
            draft.binding(\.description).wrappedValue = "Body"
            XCTAssertEqual(ListCreationDraft.load(key: key).title, "New card")
            draft.finishSession()
            draft.binding(\.description).wrappedValue = "Late editor callback"
            XCTAssertEqual(draft.title, "")
            XCTAssertEqual(draft.subtitle, "")
            XCTAssertEqual(draft.description, "")
            XCTAssertEqual(ListCreationDraft.load(key: key), ListCreationDraft())
            draft.beginSession()
            XCTAssertEqual(draft.title, "")
            XCTAssertEqual(draft.description, "")
        }

        draft.title = "Unsubmitted writing"
        draft.description = "Keep this draft"
        draft.beginSession()
        XCTAssertEqual(draft.title, "Unsubmitted writing")
        XCTAssertEqual(draft.description, "Keep this draft")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewCardDraftFieldsRemainEditableWhileSaving
    /// @brief      Verify that new Card Draft Fields Remain Editable While Saving
    /// @details    Exercises `ListCreationDraft.clear`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertTrue(subtitle.becomeFirstResponder())`;
    ///             `XCTAssertTrue(subtitle.isFirstResponder)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testNewCardDraftFieldsRemainEditableWhileSaving() async throws
    {

        let key = "plenact.testDraft.\(UUID().uuidString)"
        defer
        {
            ListCreationDraft.clear(key: key)
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(
            rootView: ListItemComposer(list: KanbanList(id: 1, title: "List", cards: []), draftKey: key)
            {
                _ in
                true
            })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(200))


        ///
        /// @fcn        PlenactBoardDocumentTests.testNewCardDraftFieldsRemainEditableWhileSaving.editors
        /// @brief      Find editors in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UITextView]) resulting values in the ordering described above
        ///
        func editors(_ view: UIView) -> [UITextView]
        {

            (view as? UITextView).map
            {
                [$0]
            }
            ?? view.subviews.flatMap
            {
                editors($0)
            }

        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testNewCardDraftFieldsRemainEditableWhileSaving.fields
        /// @brief      Find fields in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextField. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UITextField]) resulting values in the ordering described above
        ///
        func fields(_ view: UIView) -> [UITextField]
        {

            (view as? UITextField).map
            {
                [$0]
            }
            ?? view.subviews.flatMap
            {
                fields($0)
            }

        }

        let subtitle = try XCTUnwrap(fields(host.view).first(where:
                {
                    $0.placeholder == "Subtitle (optional)"
                }))
        XCTAssertTrue(subtitle.becomeFirstResponder())
        subtitle.text = "Subtitle"
        subtitle.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(subtitle.isFirstResponder)
        XCTAssertEqual(ListCreationDraft.load(key: key).subtitle, "Subtitle")
        let description = try XCTUnwrap(
            editors(host.view).first(where:
                {
                    $0.accessibilityLabel == "Details (optional)"
                }))
        XCTAssertTrue(description.becomeFirstResponder())
        for character in ["A", "B", "C"]
        {

            description.insertText(character)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(description.isFirstResponder)
        }

        XCTAssertEqual(PlanRichText.plain(ListCreationDraft.load(key: key).description), "ABC")
        let restored = ListCreationDraftModel(key: key)
        XCTAssertEqual(restored.subtitle, "Subtitle")
        XCTAssertEqual(PlanRichText.plain(restored.description), "ABC")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCardCommentComposerKeepsKeyboardFocusWhileTyping
    /// @brief      Verify that card Comment Composer Keeps Keyboard Focus While Typing
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertTrue(comment.becomeFirstResponder())`;
    ///             `XCTAssertTrue(comment.isFirstResponder, "Comment typing must not dismiss the keyboard")`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCardCommentComposerKeepsKeyboardFocusWhileTyping() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var card = KanbanCard(
            id: 42, word: "Comment focus", listTitle: "Monday", checklists: [], comments: [],
            descriptionOverride: "Description")
        card.sectionLayout = CardSectionLayout(
            order: [.description, .activity], hidden: [.quickActions, .media, .details, .checklists])
        let host = UIHostingController(rootView: CardDetailView(card: card))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))


        ///
        /// @fcn        PlenactBoardDocumentTests.testCardCommentComposerKeepsKeyboardFocusWhileTyping.findComment
        /// @brief      Find find comment in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextView. Returns the first qualifying match, or
        ///             nil when none is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UITextView?) matching or resolved value, or nil when unavailable
        ///
        func findComment(_ view: UIView) -> UITextView?
        {

            if let text = view as? UITextView, text.accessibilityLabel == "Comment..."
            {
                return text
            }

            return view.subviews.lazy.compactMap
            {
                findComment($0)
            } .first
        }

        let comment = try XCTUnwrap(findComment(host.view))
        XCTAssertTrue(comment.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(100))
        for character in ["H", "e", "l", "l", "o"]
        {

            comment.insertText(character)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(comment.isFirstResponder, "Comment typing must not dismiss the keyboard")
            XCTAssertTrue(findComment(host.view) === comment, "The composer must retain its view identity")
        }

        XCTAssertEqual(comment.text, "Hello")
        comment.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(comment.isFirstResponder, "Explicit keyboard dismissal must still work")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReactionPickerAndChipsRenderWithoutCreatingIdentityOrEditingRecords
    /// @brief      Verify that reaction Picker And Chips Render Without Creating Identity Or Editing Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(UserDefaults.standard.object(forKey:
    ///             LocalReactionIdentity.key) as? String, identityBefore)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testReactionPickerAndChipsRenderWithoutCreatingIdentityOrEditingRecords() async throws
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

        let author = UUID()
        let reactions = [
            ItemEmojiReaction(emoji: "❤️", authorID: author), ItemEmojiReaction(emoji: "🎉", authorID: author)
        ]
        let identityBefore = UserDefaults.standard.object(forKey: LocalReactionIdentity.key) as? String
        for presentation in [ItemPresentation.card, .note]
        {

            let card = KanbanCard(
                id: 1, word: "Make time for something meaningful", listTitle: "Today", checklists: [],
                descriptionOverride: "A little encouragement belongs here.", presentation: presentation,
                reactions: reactions)
            let host = UIHostingController(
                rootView: NavigationStack
                {

                    CardDetailView(card: card, onTitleToggle:
                        {
                            _ in
                            XCTFail("Rendering must not edit")
                        })
                })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-reactions-\(presentation).png")
            try XCTUnwrap(image.pngData()).write(to: url);
            print("REACTIONS_RENDER=" + url.path)
        }

        for scheme in [ColorScheme.light, .dark]
        {

            let host = UIHostingController(
                rootView: ItemReactionPicker(selected: ["❤️"], onChoose:
                    {
                        _ in
                        XCTFail("Rendering must not choose")
                    })
                .preferredColorScheme(scheme))
            window.rootViewController = host
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-reaction-picker-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: url);
            print("REACTIONS_RENDER=" + url.path)
        }

        XCTAssertEqual(UserDefaults.standard.object(forKey: LocalReactionIdentity.key) as? String, identityBefore)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testInlineBoardListNamingSelectsTitleAndDoneCommitsWithoutASheet
    /// @brief      Verify the in-column naming field's keyboard, selection, and checked commit
    /// @details    Replaces the selected generated title, rejects an initial save, then commits
    ///             through the canonical editor while preserving Cards added after naming began.
    ///
    /// @return     (Void) records native input and owner-update assertions
    /// @throws     Propagates missing window, field, or text-selection fixtures.
    ///
    @MainActor
    func testInlineBoardListNamingSelectsTitleAndDoneCommitsWithoutASheet() async throws
    {

        var lists = [KanbanList(id: 7, title: "New List 2", cards: [])]
        lists[0].subtitleOverride = "Keep this context"
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            window.endEditing(true);
            window.isHidden = true;
            window.rootViewController = nil;

            previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        testInlineBoardListNamingSelectsTitleAndDoneCommitsWithoutASheet.descendants
        /// @brief      Collect native descendants of the inline editor
        /// @details    Finds the public UITextField without depending on private SwiftUI classes.
        ///
        /// @param[in]  view  Native subtree to inspect
        ///
        /// @return     ([UIView]) root and descendants
        ///
        func descendants(_ view: UIView) -> [UIView]
        {
            [view] + view.subviews.flatMap(descendants)
        }

        var allowsSave = false
        var finishCalls = 0
        let host = UIHostingController(
            rootView: InlineBoardListTitle(
                list: lists[0],
                onSave:
                {
                    title in
                    guard allowsSave else
                    {
                        return false
                    }

                    return editBoardList(7, title: title, subtitle: lists[0].subtitle, in: &lists)
                }, onFinish:
                {
                    finishCalls += 1
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        let field = try XCTUnwrap(
            descendants(host.view).compactMap
            {
                $0 as? UITextField
            } .first
            {

                $0.accessibilityIdentifier == "board.newListTitle"
            })
        XCTAssertLessThanOrEqual(
            field.bounds.height, 37, "The title must stay one line instead of expanding the List header")
        XCTAssertLessThan(
            field.convert(field.bounds, to: host.view).minY, 100, "The title stays at the top of a tall column")
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(field.returnKeyType, .done)
        XCTAssertEqual(field.text(in: try XCTUnwrap(field.selectedTextRange)), "New List 2")
        XCTAssertNil(host.presentedViewController)
        field.insertText("  Roadmap  ")
        try await Task.sleep(for: .milliseconds(60))
        _ = field.delegate?.textFieldShouldReturn?(field)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(finishCalls, 0)
        XCTAssertEqual(field.text, "  Roadmap  ")
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(lists[0].title, "New List 2")
        lists[0].cards.append(KanbanCard(id: 40, word: "Keep this task", listTitle: lists[0].title))
        allowsSave = true
        _ = field.delegate?.textFieldShouldReturn?(field)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(lists[0].title, "Roadmap")
        XCTAssertEqual(lists[0].subtitle, "Keep this context")
        XCTAssertEqual(lists[0].cards.first?.word, "Keep this task")
        XCTAssertEqual(lists[0].cards.first?.listTitle, "Roadmap")
        XCTAssertEqual(finishCalls, 1)
        XCTAssertFalse(field.isFirstResponder)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testQuickCaptureActionsAndComposersRenderWithoutCreatingRecords
    /// @brief      Verify that quick Capture Actions And Composers Render Without Creating Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertTrue(fields(host.view).contains("Carry my thought
    ///             forward"))`; `XCTAssertTrue(fields(host.view).contains(""))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testQuickCaptureActionsAndComposersRenderWithoutCreatingRecords() async throws
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


        ///
        /// @fcn        PlenactBoardDocumentTests.testQuickCaptureActionsAndComposersRenderWithoutCreatingRecords.fields
        /// @brief      Find fields in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UITextField, UITextView. Returns all collected
        ///             matches in hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([String]) resulting values in the ordering described above
        ///
        func fields(_ view: UIView) -> [String]
        {

            let value = (view as? UITextField)?.text ?? (view as? UITextView)?.text
            return (value.map
                {
                    [$0]
                }
                ?? []) + view.subviews.flatMap(fields)
        }

        let lists = [KanbanList(id: 4, title: "Today", cards: [])]
        var saves = 0
        for action in TodayCaptureAction.allCases
        {

            let host = UIHostingController(
                rootView: QuickNoteComposer(
                    lists: .constant(lists), initialListID: 4,
                    initialTitle: "Carry my thought forward", captureAction: action,
                    onSaveCapture:
                    {
                        _ in
                        saves += 1;
                        return true
                    }
                )
                {
                    _, _, _, _, _, _ in
                    saves += 1
                })
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            XCTAssertTrue(fields(host.view).contains("Carry my thought forward"))
            if action == .checklist
            {
                XCTAssertTrue(fields(host.view).contains(""))
            }

            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-capture-\(action.rawValue).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("CAPTURE_RENDER=" + url.path)
            if action == .photo || action == .drawing
            {

                host.dismiss(animated: false);
                try await Task.sleep(for: .milliseconds(100))
            }

        }

        for width in [393.0, 744.0]
        {

            let host = UIHostingController(
                rootView: TodayCaptureActions
                {
                    _ in
                    XCTFail("Rendering must not activate a capture")
                } .padding()
                .background(Color(.secondarySystemGroupedBackground)))
            window.frame = CGRect(x: 0, y: 0, width: width, height: 180)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(100))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-capture-row-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("CAPTURE_RENDER=" + url.path)
        }

        XCTAssertEqual(saves, 0)
        XCTAssertTrue(lists[0].cards.isEmpty)
        XCTAssertEqual(TodayCaptureAction.note.presentation, .note)
        XCTAssertEqual(TodayCaptureAction.checklist.presentation, .card)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreationTimestampRoundTripsAndRejectsMalformedDates()
    /// @brief      Verify Note creation timestamps survive encoding and malformed dates are rejected
    /// @details    Checks Note creation, JSON round trips, edits, and location replacement against
    ///             one fixed synthetic timestamp
    ///
    /// @return     (Void) succeeds when valid dates persist and malformed encoded dates fail
    ///
    /// @throws     Encoding or decoding failures when the timestamp fixture cannot be processed
    ///
    func testCreationTimestampRoundTripsAndRejectsMalformedDates() throws
    {


        let timestamp = Date(timeIntervalSince1970: 1_791_422_000)   /* Fixed creation timestamp      */
        var list = KanbanList(id: 1, title: "Synthetic", cards: [])  /* List state under verification */
        list.newItemPresentation = .note
        let note = list.makeItem(id: 2, title: "Dated Note", createdAt: timestamp) /* Newly created Note value */

        XCTAssertEqual(note.createdAt, timestamp)

        let decoded = try JSONDecoder().decode(
            KanbanCard.self, from: JSONEncoder().encode(note)) /* Decoded Card round-trip value */

        XCTAssertEqual(decoded, note)
        XCTAssertEqual(decoded.createdAt, timestamp)

        var card = decoded /* Card value under verification */
        card.presentation = .card
        card.word = "Edited title"
        card.descriptionOverride = "Edited body"

        XCTAssertEqual(card.createdAt, timestamp)
        card.presentation = .note

        XCTAssertEqual(card.replacingLocation(id: 8, listTitle: "Moved").createdAt, timestamp)

        let before = Date.now                                     /* Timestamp before the operation */
        let newCard = list.makeItem(id: 3, title: "Created now")  /* Newly created Card value       */
        let after = Date.now                                      /* Timestamp after the operation  */
        let actual = try XCTUnwrap(newCard.createdAt)             /* Observed creation timestamp    */

        XCTAssertGreaterThanOrEqual(actual, before)
        XCTAssertLessThanOrEqual(actual, after)

        let invalid = Data(
                        #"{"id":2,"word":"Invalid","listTitle":"Synthetic","createdAt":"not-a-date"}"#.utf8) /* Malformed encoded input */

        XCTAssertThrowsError(try JSONDecoder().decode(KanbanCard.self, from: invalid))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalCreationHonorsSelectedKindWithoutChangingListDefault()
    /// @brief      Verify explicit creation kind leaves the List default unchanged
    /// @details    Creates a Card and a Note in the same personal List, checks subtitle trimming
    ///             and body retention, and round-trips the collection while preserving its Note
    ///             creation default.
    ///
    /// @return     (Void) records explicit-presentation and persistence assertions
    /// @throws     Synthetic fixture setup errors
    ///
    func testPersonalCreationHonorsSelectedKindWithoutChangingListDefault() throws
    {

        var collection = PersonalCollection(title: "Ideas", kind: .list)
        let createdAt = try XCTUnwrap(PlanningDate.date("2026-10-13"))
        let body = "First paragraph\n\nSecond paragraph  "
        try collection.addNote(
            title: "A card", body: body, createdAt: createdAt, presentation: .card, subtitle: " Useful context ")
        try collection.addNote(title: "A note", body: body, createdAt: createdAt, presentation: .note)
        XCTAssertEqual(collection.lists[0].newItemPresentation, .note)
        let cards = collection.lists[0].cards
        XCTAssertEqual(cards.map(\.presentation), [.card, .note])
        XCTAssertEqual(cards[0].subtitleOverride, "Useful context")
        XCTAssertTrue(cards.allSatisfy
            {
                $0.descriptionOverride == body && $0.createdAt == createdAt
            })
        XCTAssertNotEqual(cards[0].id, cards[1].id)
        XCTAssertEqual(
            try JSONDecoder().decode(PersonalCollection.self, from: JSONEncoder().encode(collection)), collection)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreatingPersonalListNoteUsesFreshIdentityAndPreservesBody
    /// @brief      Verify that creating Personal List Note Uses Fresh Identity And Preserves Body
    /// @details    Exercises `collection.lists[0].makeItem`, `collection.addNote`, `board.addNote`. Checks
    ///             `XCTAssertThrowsError(try collection.addNote(title: " \n ", body: "Uncommitted"))`;
    ///             `XCTAssertEqual(collection, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testCreatingPersonalListNoteUsesFreshIdentityAndPreservesBody() throws
    {


        var collection = PersonalCollection(
            title: "Synthetic ideas", kind: .list) /* Collection state under verification                 */
        let existing = collection.lists[0].makeItem(
            id: 7, title: "Existing") /* Existing active Card retained during Note insertion */
        let archived = collection.lists[0].makeItem(
            id: 12, title: "Archived") /* Archived value for restoration checks               */

        collection.lists[0].cards = [existing]
        collection.lists[0].archivedCards = [archived]
        let original = collection /* Pre-operation value for preservation checks */

        XCTAssertThrowsError(try collection.addNote(title: " \n ", body: "Uncommitted"))
        {
            _ in

            XCTAssertEqual(collection, original, "Cancel/invalid Save must not mutate stored content")
        }


        let createdAt = Date(timeIntervalSince1970: 1_791_422_000) /* Creation timestamp under verification */
        try collection.addNote(title: "  Beach idea  ", body: "First line\n\nSecond line  ", createdAt: createdAt)

        XCTAssertEqual(
            collection.lists[0].cards,
            [
                existing,
                KanbanCard(
                    id: 13, word: "Beach idea", listTitle: collection.title,
                    checklists: [],
                    descriptionOverride: "First line\n\nSecond line  ",
                    subtitleOverride: "",
                    presentation: .note,
                    createdAt: createdAt
                )
            ])

        XCTAssertEqual(collection.lists[0].archivedCards, [archived])

        var board = PersonalCollection(title: "Not a list", kind: .board)  /* Board state under verification          */
        let boardBefore = board                                            /* Board state before the attempted change */

        XCTAssertThrowsError(try board.addNote(title: "No", body: ""))
        XCTAssertEqual(board, boardBefore)

        collection.isArchived = true
        let archivedCollection = collection /* Collection state after archival */

        XCTAssertThrowsError(try collection.addNote(title: "No", body: ""))
        XCTAssertEqual(collection, archivedCollection)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryDirectoryNewActionPresentsNoteComposer()
    /// @brief      Verify Library's registered New action opens the writing-first composer
    /// @details    Hosts a synthetic personal List, invokes the registered directory action,
    ///             and checks that its Note destination is shown in the presented composer
    ///
    /// @return     (Void) records callback or composer presentation failures
    /// @throws     Scene, view, or presentation lookup failures
    ///
    @MainActor
    func testLibraryDirectoryNewActionPresentsNoteComposer() async throws
    {


        var current = [
            PersonalCollection(title: "First ideas", kind: .list)
        ] /* Current collections displayed by the Library */
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)                                             /* Active scene for UI hosting     */
        let previous = scene.windows.first(where: \.isKeyWindow)  /* Previously focused window       */
        let window = UIWindow(windowScene: scene)                 /* Temporary window for UI hosting */

        var newNoteAction: (() -> Void)? /* New Note action under test */


        defer
        {


            window.isHidden = true
            window.rootViewController = nil

            previous?.makeKey()
        }


        let controller = UIHostingController(
            rootView: BoardListsView( /* Hosted controller for layout assertions */
                retainedWeekLists: [],
                collections: Binding(get:
                    {
                        current
                    }, set:
                    {
                        current = $0
                    }),
                registerListNewNote:
                {
                    newNoteAction = $0
                },
                onOpenSaved:
                {

                }
            ))

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller

        window.makeKeyAndVisible()

        controller.view.layoutIfNeeded()

        try await Task.sleep(for: .milliseconds(150))

        try XCTUnwrap(newNoteAction)()

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertNotNil(
            controller.presentedViewController,
                            "The Library New action must present its writing-first Note composer"
        )
        XCTAssertTrue(
            [UIModalPresentationStyle.fullScreen, .overFullScreen]
            .contains(controller.presentedViewController?.modalPresentationStyle ?? .automatic),
                            "The Library-directory New action must retain the immersive full-screen composer"
        )
    }

}
