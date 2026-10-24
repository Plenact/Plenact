// --------------------------------------------------------------------------------------------------
// @file       InlineListCapture.swift
// @brief      Inline List creation and full-composer handoff
// @details    Supports keyboard quick creation and plus-button expansion with prefilled writing
//             while retaining rejected or cancelled drafts.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Retains the editable fields of a List-scoped creation draft
///
/// @section    Purpose
///     Stores unsaved title, description, and supporting creation values separately from committed
///     List content.
///
struct ListCreationDraft: Codable, Equatable
{


    var title = ""
    var subtitle = ""
    var description = ""


    ///
    /// @fcn        ListCreationDraft.key
    /// @brief      Build the storage key for a destination's creation draft
    /// @details    Includes the collection UUID or current-week sentinel and the numeric list ID to keep drafts
    ///             separate.
    ///
    /// @param[in]  collectionID  UUID of the collection owning the referenced content
    /// @param[in]  listID        Numeric list identity within its owner
    ///
    /// @return     (String) owner-and-list-qualified creation-draft preferences key
    ///
    static func key(collectionID: UUID?, listID: Int) -> String
    {

                "plenact.creationDraft.\(collectionID?.uuidString ?? "currentWeek").\(listID)"
    }


    ///
    /// @fcn        ListCreationDraft.load
    /// @brief      Restore a destination-specific creation draft
    /// @details    Returns an empty draft when the key has no data or its encoded value cannot be decoded.
    ///
    /// @param[in]  key       Storage key or stable lookup key used by this operation
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (ListCreationDraft) constructed value
    ///
    static func load(key: String, defaults: UserDefaults = .standard) -> Self
    {

        guard let data = defaults.data(forKey: key), let draft = try? JSONDecoder().decode(Self.self, from: data) else
        {

            return Self()
        }

        return draft
    }


    ///
    /// @fcn        ListCreationDraft.save
    /// @brief      Persist the current creation draft
    /// @details    Writes encoded draft data under the supplied key only when encoding succeeds.
    ///
    /// @param[in]  key       Storage key or stable lookup key used by this operation
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Void) no return value
    ///
    func save(key: String, defaults: UserDefaults = .standard)
    {

        if let data = try? JSONEncoder().encode(self)
        {
            defaults.set(data, forKey: key)
        }

    }


    ///
    /// @fcn        ListCreationDraft.clear
    /// @brief      Remove a completed or cancelled creation draft
    /// @details    Deletes only the specified draft key from the supplied preferences store.
    ///
    /// @param[in]  key       Storage key or stable lookup key used by this operation
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Void) no return value
    ///
    static func clear(key: String, defaults: UserDefaults = .standard)
    {
        defaults.removeObject(forKey: key)
    }

}


///
/// Retains the live List creation composer model
///
/// @section    Purpose
///     Keeps editable content stable across sheet reconstruction and persists draft changes
///     independently of final item creation.
///
final class ListCreationDraftModel: ObservableObject
{


    private let key: String
    private var acceptsEdits = true
    @Published var title: String
    {
        didSet
        {
            save()
        }

    }

    @Published var subtitle: String
    {
        didSet
        {
            save()
        }

    }

    @Published var description: String
    {
        didSet
        {
            save()
        }

    }


    ///
    /// @fcn        ListCreationDraftModel.init
    /// @brief      Load editable creation fields for a destination key
    /// @details    Retains the key and initializes title, subtitle, and description from the saved draft.
    ///
    /// @param[in]  key  Storage key or stable lookup key used by this operation
    ///
    /// @return     (ListCreationDraftModel) initialized instance
    ///
    init(key: String)
    {

        self.key = key
        let saved = ListCreationDraft.load(key: key)
        title = saved.title
        subtitle = saved.subtitle
        description = saved.description
    }


    ///
    /// @fcn        ListCreationDraftModel.beginSession
    /// @brief      Reload draft fields before accepting editor changes
    /// @details    Temporarily suspends edits during restoration so field assignments do not persist intermediate
    ///             values.
    ///
    /// @return     (Void) no return value
    ///
    func beginSession()
    {

        acceptsEdits = false
        let saved = ListCreationDraft.load(key: key)
        title = saved.title
        subtitle = saved.subtitle
        description = saved.description
        acceptsEdits = true
    }


    ///
    /// @fcn        ListCreationDraftModel.finishSession
    /// @brief      Clear a finished draft and reject delayed editor callbacks
    /// @details    Stops accepting edits before clearing fields and storage, preventing keyboard dismissal from
    ///             recreating the draft.
    ///
    /// @return     (Void) no return value
    ///
    func finishSession()
    {

        // Dismissal can deliver a final text-editor callback after Add or Cancel.
        acceptsEdits = false
        title = ""
        subtitle = ""
        description = ""
        ListCreationDraft.clear(key: key)
    }


    ///
    /// @fcn        ListCreationDraftModel.binding
    /// @brief      Bind a creation field while the session accepts edits
    /// @details    Reads through the supplied reference key path and ignores writes after the session has finished.
    ///
    /// @param[in]  field  Selected editable field or field key path
    ///
    /// @return     (Binding<String>) field binding that ignores writes after the creation session has finished
    ///
    func binding(_ field: ReferenceWritableKeyPath<ListCreationDraftModel, String>) -> Binding<String>
    {

        Binding(
            get:
            {
                self[keyPath: field]
            },
            set:
            {
                value in
                guard self.acceptsEdits else
                {
                    return
                }

                self[keyPath: field] = value
            })
    }


    ///
    /// @fcn        ListCreationDraftModel.save
    /// @brief      Persist editable draft fields during an active session
    /// @details    Returns without writing once edits are disabled, preserving the completed-session cleanup.
    ///
    /// @return     (Void) no return value
    ///
    private func save()
    {

        guard acceptsEdits else
        {
            return
        }

        ListCreationDraft(title: title, subtitle: subtitle, description: description).save(key: key)
    }

}


///
/// Provides quick inline creation and full-composer access
///
/// @section    Purpose
///     Keyboard submission creates the typed title in place; the adjacent plus opens the full
///     composer with that writing prefilled.
///
struct InlineListCapture: View
{


    let list:           KanbanList
    @Binding var draft: InlineListCaptureDraft
    var textColor:      Color = .primary
    var isPresented = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onCreate:                      (QuickCaptureSubmission) -> Bool
    let onOpenComposer:                () -> Void
    @FocusState private var isFocused: Bool

    var body: some View
    {

        HStack(spacing: 8)
        {

            TextField(
                                    "Add a \(list.newItemPresentation.title.lowercased()) to \(list.title)…", text: $draft.title,
                                    prompt: Text("Add a \(list.newItemPresentation.title.lowercased()) to \(list.title)…").foregroundStyle(
                                        textColor)
            )
            .foregroundStyle(textColor)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit
            {
                createInline()
            }
            .accessibilityIdentifier("list.inlineCapture.title")
            Button
            {

                isFocused = false
                onOpenComposer()
            }
            label:
            {

                Image(systemName: "plus.circle.fill")
                .foregroundStyle(textColor)
                .font(.title2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(list.newItemPresentation.title.lowercased()) to \(list.title)")
            .accessibilityHint("Opens the full editor with your entered title.")
            .accessibilityIdentifier("list.inlineCapture.add")
        }
        .frame(minHeight: 44)
        .offset(y: reduceMotion || isPresented ? 0 : -120)
        .opacity(isPresented ? 1 : 0)
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 1.9), value: isPresented)
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
        .onChange(of: isPresented)
        {
            _, visible in
            if !visible
            {
                isFocused = false
            }

        }
        .onChange(of: list.id)
        {
            _, _ in
            draft = InlineListCaptureDraft()
            isFocused = false
        }

    }


    ///
    /// @fcn        InlineListCapture.createInline()
    /// @brief      Save a title directly into the current List
    /// @details    Retains focus for successive captures and retains writing if saving fails.
    ///
    /// @return     (Void) requests creation without opening a detail view
    ///
    private func createInline()
    {

        let previousRevealID = CreatedContentReveal.shared.target?.id
        guard draft.submit(to: list, onCreate: onCreate) else
        {
            return
        }

        // Keep successive captures at the footer rather than centering the new Card above it.
        if let request = CreatedContentReveal.shared.target,
        request.id != previousRevealID, request.listID == list.id
        {

            CreatedContentReveal.shared.complete(request)
        }

        isFocused = true
    }

}


///
/// Retains pending inline item writing
///
/// @section    Purpose
///     Clears the draft only after the canonical List creation callback accepts the new item,
///     leaving failed submissions editable.
///
struct InlineListCaptureDraft
{


    var title = ""


    ///
    /// @fcn        InlineListCaptureDraft.submit(to:onCreate:)
    /// @brief      Submit a nonblank title through the existing List creation path
    /// @details    Uses the destination's Card or Note default and clears only after a successful
    ///             save. Empty submissions never invoke creation or open another view.
    ///
    /// @param[in]  list      Destination List and its default item presentation
    /// @param[in]  onCreate  Checked canonical creation callback
    ///
    /// @return     (Bool) true when the item was saved and the draft cleared
    ///
    mutating func submit(to list: KanbanList, onCreate: (QuickCaptureSubmission) -> Bool) -> Bool
    {

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else
        {
            return false
        }

        let capture = QuickCaptureSubmission(
            listID: list.id, title: trimmed, body: "",
            subtitle: "", presentation: list.newItemPresentation, actions: nil, attachments: [], schedule: nil)
        guard onCreate(capture) else
        {
            return false
        }

        title = ""
        return true
    }

}


///
/// Opens full-featured creation scoped to a List
///
/// @section    Purpose
///     Reuses the central New composer with destination context and an optional initial title
///     rather than an outdated separate editor.
///
struct ListItemComposer: View
{


    let list:         KanbanList
    let draftKey:     String
    var initialTitle: String = ""
    let onCreate:     (QuickCaptureSubmission) -> Bool
    var body:         some View
    {

        QuickNoteComposer(
            lists: .constant([list]), initialListID: list.id, initialTitle: initialTitle,
            draftKey: draftKey, initialPresentation: list.newItemPresentation,
            onSaveCapture: onCreate
        )
        {
            id, title, body, subtitle, presentation, actions in
            _ = onCreate(
                QuickCaptureSubmission(
                    listID: id, title: title, body: body,
                    subtitle: subtitle, presentation: presentation ?? list.newItemPresentation,
                    actions: actions, attachments: [], schedule: nil))
        }

    }

}


///
/// Creates a complete item draft in its intended owner
///
/// @section    Purpose
///     Uses destination-local allocation and full capture content without mutating an unrelated
///     Board or calendar Week.
///
enum ListItemCreation
{


    ///
    /// @fcn        ListItemCreation.items
    /// @brief      Build full-featured cards or notes from a capture submission
    /// @details    Validates the active destination, title, and schedule; applies scheduling to each created item and
    ///             attaches imported media and its photo cover to the first item.
    ///
    /// @param[in]  capture   Full capture submission including presentation, text, schedule, and attachments
    /// @param[in]  list      List supplying the current content and metadata
    /// @param[in]  id        Starting numeric card ID or owner-local content identity
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     ([KanbanCard]?) generated items, or nil when input or destination validation fails
    ///
    static func items(
        _ capture: QuickCaptureSubmission, in list: KanbanList, startingAt id: Int,
        calendar: Calendar = .current
    ) -> [KanbanCard]?
    {

        guard capture.listID == list.id, !list.isArchived,
        !capture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        capture.schedule?.isValid(calendar: calendar) != false
        else
        {
            return nil
        }

        var cards = list.makeItems(
            startingAt: id, titles: capture.title,
            description: capture.body, subtitle: capture.subtitle,
            presentation: capture.presentation, actions: capture.actions)
        guard !cards.isEmpty else
        {
            return nil
        }

        for index in cards.indices
        {
            capture.schedule?.apply(to: &cards[index], calendar: calendar)
        }

        cards[0].attachments = capture.attachments.isEmpty ? nil : capture.attachments
        cards[0].coverAttachmentID = capture.attachments.first
        {
            $0.kind == .photo
        }?.id
        return cards
    }

}
