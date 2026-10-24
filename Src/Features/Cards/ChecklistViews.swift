// --------------------------------------------------------------------------------------------------
// @file       ChecklistViews.swift
// @brief      Typed checklist action presentation and editing
// @details    Coordinates completion, nested details, linked destinations, text entry, and
//             action-type drafts through owner callbacks.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


// --------------------------------------- MARK: - Action Detail ------------------------------- //


///
/// Presents reduced card-like context owned by one checklist action
///
/// @section    Purpose
///     Edit an action's description, nested checklist completion, and comments without creating
///     an independent Board card or allowing recursive Action Details
///
struct ChecklistActionDetailView: View
{


    let title:           String                                 /* Owning action title */
    let currentUserName: String                                 /* Comment author name */
    let onSave:          (KanbanChecklistActionDetail) -> Void  /* Save callback       */

    @Environment(\.dismiss) private var dismiss /* Sheet dismissal     */

    @State private var detailID:        UUID               /* Stable detail ID  */
    @State private var descriptionText: String             /* Description draft */
    @State private var checklists:      [KanbanChecklist]  /* Nested actions    */
    @State private var comments:        [KanbanComment]    /* Detail comments   */
    @State private var commentDraft = ""                   /* New comment draft */


    ///
    /// @fcn        ChecklistActionDetailView.init(title:detail:currentUserName:onSave:)
    /// @brief      Initialize the reduced Action Detail editor
    /// @details    Copies persisted values into local draft state so Cancel remains non-destructive
    ///
    /// @param[in]  title            Owning checklist action title
    /// @param[in]  detail           Persisted reduced detail content
    /// @param[in]  currentUserName  Name used for newly posted comments
    /// @param[in]  onSave           Callback receiving the completed detail snapshot
    ///
    /// @return     (ChecklistActionDetailView) configured reduced detail editor
    /// @post       The source detail and parent card remain unchanged until explicit Save
    ///
    init(
        title: String,
        detail: KanbanChecklistActionDetail,
        currentUserName: String,
        onSave: @escaping (KanbanChecklistActionDetail) -> Void
    )
    {


        self.title = title
        self.currentUserName = currentUserName
        self.onSave = onSave

        _detailID = State(initialValue: detail.id)
        _descriptionText = State(initialValue: detail.description)
        _checklists = State(initialValue: detail.checklists)
        _comments = State(initialValue: detail.comments)
    }


    ///
    /// @fcn        ChecklistActionDetailView.toggleItem(checklistID:itemID:)
    /// @brief      Toggle one nested standard action
    /// @details    Updates completion by stable checklist and item identity
    ///
    /// @param[in]  checklistID  Stable nested checklist identity
    /// @param[in]  itemID       Stable nested action identity
    ///
    /// @return     (Void) updates local Action Detail draft state
    ///
    /// @post       Missing checklist/item IDs do nothing; no parent snapshot is emitted until Save
    ///
    private func toggleItem(checklistID: UUID, itemID: UUID)
    {


        guard
        let checklistIndex = checklists.firstIndex(where:
            {  /* Nested checklist containing the action to toggle */


                $0.id == checklistID
            })
        else
        {


            return
        }


        let checklist = checklists[checklistIndex] /* Nested checklist snapshot */

        guard
        let itemIndex = checklist.items.firstIndex(where:
            {  /* Nested action whose completion state is toggled */


                $0.id == itemID
            })
        else
        {


            return
        }


        var items = checklist.items /* Mutable nested actions */

        items[itemIndex].isCompleted.toggle()

        checklists[checklistIndex] = KanbanChecklist(
            id: checklist.id,
            title: checklist.title,
            items: items
        )
    }


    ///
    /// @fcn        ChecklistActionDetailView.postComment()
    /// @brief      Append the current non-empty comment draft
    /// @details    Trims surrounding whitespace and attributes the comment to the current actor
    ///
    /// @return     (Void) updates local comments and clears a valid draft
    ///
    /// @post       Blank input leaves the draft unchanged; comments remain local until Save
    ///
    private func postComment()
    {


        let trimmedDraft = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized comment */

        guard !PlanRichText.plain(trimmedDraft).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
        {


            return
        }


        comments.append(KanbanComment(author: currentUserName, body: trimmedDraft))
        commentDraft = ""
    }


    ///
    /// @fcn        ChecklistActionDetailView.body
    /// @brief      Build the reduced Action Detail form
    /// @details    Presents description, nested completion, comments, and explicit Save/Cancel actions
    ///
    /// @return     (some View) reduced detail editing sheet
    /// @post       Save emits a detail snapshot retaining its ID, then dismisses.
    ///             Cancel discards draft description, completion, and comment edits
    ///
    var body: some View
    {  /* Reduced Action Detail editor form */


        NavigationStack
        {


            Form
            {


                Section("Description")
                {

                    RichTextEditor(placeholder: "Description", text: $descriptionText)
                }


                ForEach(checklists)
                {
                    checklist in
                    Section(checklist.title)
                    {

                        ForEach(checklist.items)
                        {
                            item in
                            Button
                            {

                                toggleItem(checklistID: checklist.id, itemID: item.id)
                            }
                            label:
                            {

                                Label(
                                    item.title,
                                    systemImage: item.isCompleted ? "checkmark.square.fill" : "square"
                                )
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                            }

                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                item.isCompleted ? "Mark \(item.title) incomplete" : "Mark \(item.title) complete")
                        }

                    }

                }


                Section("Comments")
                {


                    if comments.isEmpty
                    {


                        Text("No comments yet")
                        .foregroundStyle(.secondary)
                    }


                    ForEach(comments)
                    {
                        comment in
                        VStack(alignment: .leading, spacing: 3)
                        {

                            Text(comment.author)
                            .font(.caption.weight(.semibold))
                            Text(PlanRichText.display(comment.body))
                        }

                    }


                    HStack
                    {

                        RichTextEditor(
                            placeholder: "Add comment", text: $commentDraft, minimumHeight: 24, verticalInset: 2)

                        Button(action: postComment)
                        {

                            Image(systemName: "paperplane.fill")
                        }

                        .disabled(
                            PlanRichText.plain(commentDraft).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityLabel("Post action comment")
                    }

                }

            }

            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Cancel")
                    {

                        dismiss()
                    }

                }


                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Save")
                    {

                        onSave(
                            KanbanChecklistActionDetail(
                                id: detailID,
                                description: descriptionText,
                                checklists: checklists,
                                comments: comments
                            ))
                        dismiss()
                    }

                }

            }

        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

}


// --------------------------------------- MARK: - Checklist ------------------------------------ //


///
/// Displays a checklist group and its completion count
///
/// @section    Purpose
///     Present checklist progress together with each item and its completion state
///
/// @note   Completion is supplied by the parent so this view remains presentation-focused
///
struct ChecklistBlock: View
{


    let checklist: KanbanChecklist /* The checklist data rendered by the block                                */
    let linkedCardsByID:
    [Int: KanbanCard]                   /* Linked cards keyed by stable ID                  */
    let onDelete:     () -> Void        /* The action invoked when the checklist is deleted */
    let onAddItem:    (String) -> Void  /* The action invoked when a new item is added      */
    let onToggleItem: (Int) -> Void     /* The action invoked when an item is toggled       */
    let onUpdateItem:
    (Int, String) -> Void            /* The action invoked when item text is edited */
    let onDeleteItem: (Int) -> Void  /* The action invoked when an item is deleted  */
    let onOpenActionDetail:
    (UUID) -> Void                          /* The action invoked for reduced detail                  */
    let onRename:         (String) -> Void  /* The action invoked when the checklist title is renamed */
    let onToggleAllItems: () -> Void        /* The action invoked when all items are toggled          */
    let onMove:
    (ChecklistMoveDirection) -> Void          /* The action invoked when the checklist is moved                          */
    let canMoveUp:                Bool        /* Whether the checklist can be moved up in the list                       */
    let canMoveDown:              Bool        /* Whether the checklist can be moved down in the list                     */
    let focusFirstItem:           Bool        /* Whether the first item should be focused when the checklist is rendered */
    let onFirstItemFocused:       () -> Void  /* The action invoked when the first item receives focus                   */
    var onChangeType:             ((KanbanChecklistItem) -> Bool)? = nil
    @State private var typeDraft: KanbanChecklistItem?
    @State private var requestedType = ChecklistItemType.standard

    @State private var newItemText = ""
    @State private var confirmsDeletion = false
    @State private var isRenaming = false          /* Whether the checklist title is currently being renamed          */
    @State private var titleDraft = ""             /* The draft text for the checklist title being edited             */
    @State private var hideCompletedItems = false  /* Checklist completed-item filter                                 */
    @State private var isCollapsed = false         /* Whether the checklist's items are currently collapsed from view */

    ///
    /// @fcn        ChecklistBlock.allItemsAreCompleted
    /// @brief      Determine whether every item in the checklist is complete
    /// @details    Requires a non-empty checklist and a completion entry for each item
    ///
    /// @return     (Bool) true when all checklist items are complete
    ///
    /// @pre        Checklist items and completion indices represent the current checklist state
    /// @post       No checklist state is modified
    ///
    private var allItemsAreCompleted: Bool
    {  /* Non-empty checklist completion state */


        /// Check if all items in the checklist are completed
        !checklist.items.isEmpty && checklist.completedItemIndices.count == checklist.items.count
    }


    ///
    /// @fcn        ChecklistBlock.visibleItems
    /// @brief      Return checklist items visible under the current display filter
    /// @details    Preserves each item's original index while omitting completed items when Hide Completed is enabled
    ///
    /// @return     ([(offset: Int, element: KanbanChecklistItem)]) visible item and original-index pairs
    ///
    /// @pre        Checklist data and Hide Completed state are current
    /// @post       Checklist data and completion state remain unchanged
    ///
    private var visibleItems: [(offset: Int, element: KanbanChecklistItem)]
    {  /* Filtered actions */


        /// Filter the checklist items based on the hideCompletedItems flag
        checklist.items.enumerated().filter
        {
            item in
            !hideCompletedItems || !checklist.completedItemIndices.contains(item.offset)
        }

    }


    ///
    /// @fcn        ChecklistBlock.actionRow(for:)
    /// @brief      Build the row behavior for one checklist action type
    /// @details    Keeps the main checklist body small while preserving shared completion and
    ///             deletion
    ///
    /// @param[in]  entry  Original item position and stable checklist action
    ///
    /// @return     (some View) standard editor, linked-card navigation, or Action Detail button
    ///
    /// @pre        entry.offset refers to the original checklist index, not the filtered display
    ///             index
    /// @post       Row callbacks delegate completion/deletion by original index; only standard
    ///             actions receive text editing and first-item focus requests
    ///
    @ViewBuilder
    private func actionRow(for entry: (offset: Int, element: KanbanChecklistItem)) -> some View
    {


        switch entry.element.content
        {


        case .webLink(let url):
            ChecklistItemRow(
                item: entry.element.title, isCompleted: entry.element.isCompleted,
                webURL: url, onToggle:
                {
                    onToggleItem(entry.offset)
                },
                onUpdate:
                {
                    onUpdateItem(entry.offset, $0)
                }, onDelete:
                {
                    onDeleteItem(entry.offset)
                },
                shouldFocus: false, onFocusHandled:
                {

                })
        case .standard:
            ChecklistItemRow(
                item: entry.element.title,
                isCompleted: checklist.completedItemIndices.contains(entry.offset),
                onToggle:
                {
                    onToggleItem(entry.offset)
                },
                onUpdate:
                {
                    text in
                    onUpdateItem(entry.offset, text)
                },
                onDelete:
                {
                    onDeleteItem(entry.offset)
                },
                shouldFocus: focusFirstItem && entry.offset == 0,
                onFocusHandled: onFirstItemFocused
            )

        case .linkedCard(let cardID): /* Stable target card identity */
            ChecklistItemRow(
                item: entry.element.title,
                isCompleted: checklist.completedItemIndices.contains(entry.offset),
                planningLinkID: entry.element.id,
                linkedCardID: cardID,
                linkedCollectionID: entry.element.linkedCollectionID,
                linkedCard: linkedCardsByID[cardID],
                onToggle:
                {
                    onToggleItem(entry.offset)
                },
                onUpdate:
                {
                    text in
                    onUpdateItem(entry.offset, text)
                },
                onDelete:
                {
                    onDeleteItem(entry.offset)
                },
                shouldFocus: false,
                onFocusHandled:
                {

                }
            )

        case .actionDetail:
            ChecklistItemRow(
                item: entry.element.title,
                isCompleted: checklist.completedItemIndices.contains(entry.offset),
                onOpenDetail:
                {
                    onOpenActionDetail(entry.element.id)
                },
                onToggle:
                {
                    onToggleItem(entry.offset)
                },
                onUpdate:
                {
                    text in
                    onUpdateItem(entry.offset, text)
                },
                onDelete:
                {
                    onDeleteItem(entry.offset)
                },
                shouldFocus: false,
                onFocusHandled:
                {

                }
            )
        }

    }


    ///
    /// @fcn        ChecklistBlock.chooseType(_:for:)
    /// @brief      Change a checklist action type while retaining prior content
    /// @details    Reuses retained detail, Card, or URL values where available. Requests a type
    ///             editor when a destination is missing and opens action detail only after the
    ///             owner accepts the change.
    ///
    /// @param[in]  type  Requested checklist action type
    /// @param[in]  item  Checklist item whose active type is changing; retained inactive content
    ///             may be reused
    ///
    /// @return     (Void) updates the item through its owner or presents the required draft editor
    ///
    private func chooseType(_ type: ChecklistItemType, for item: KanbanChecklistItem)
    {

        var updated = item
        switch type
        {

        case .standard:
            updated.content = .standard
        case .actionDetail:
            updated.content = .actionDetail(item.retainedDetail ?? KanbanChecklistActionDetail())
        case .linkedCard:
            if let id = item.retainedCardID, item.type != .linkedCard
            {

                updated.content = .linkedCard(cardID: id)
            }
            else
            {

                requestedType = type;
                typeDraft = item;
                return
            }

        case .webLink:
            if let url = item.retainedURL, item.type != .webLink
            {

                updated.content = .webLink(url)
            }
            else
            {

                requestedType = type;
                typeDraft = item;
                return
            }

        }

        if onChangeType?(updated) == true && type == .actionDetail
        {
            onOpenActionDetail(item.id)
        }

    }


    ///
    /// @fcn        ChecklistBlock.submitNewItems
    /// @brief      Submit nonempty checklist entry text
    /// @details    Uses the shared multiline parser to reject blank input, then invokes the add callback and clears
    ///             the editor text.
    ///
    /// @return     (Void) no return value
    ///
    private func submitNewItems()
    {

        guard !MultilineEntry.titles(newItemText).isEmpty else
        {
            return
        }

        onAddItem(newItemText)
        newItemText = ""
    }


    var body: some View
    {  /* Checklist heading, rows, and action menu */


        VStack(alignment: .leading, spacing: 0)
        {


            HStack
            {


                Text(checklist.title)
                .font(.subheadline.weight(.semibold))
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.5)
                {

                    titleDraft = checklist.title
                    isRenaming = true
                }

                .accessibilityHint("Touch and hold to rename this checklist")

                Spacer()

                Text("\(checklist.completed)/\(checklist.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

                Button
                {

                    withAnimation(.easeInOut(duration: 0.2))
                    {

                        isCollapsed.toggle()
                    }

                }
                label:
                {

                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                }

                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? "Expand checklist" : "Collapse checklist")

                Menu
                {

                    Toggle("Hide Completed", isOn: $hideCompletedItems)

                    Button
                    {

                        onToggleAllItems()
                    }
                    label:
                    {

                        Label(
                            allItemsAreCompleted ? "Uncheck All" : "Check All",
                            systemImage: allItemsAreCompleted ? "square" : "checkmark.square")
                    }

                    .disabled(checklist.items.isEmpty)

                    Divider()

                    Button("Move to the Top", systemImage: "arrow.up.to.line")
                    {

                        onMove(.top)
                    }

                    .disabled(!canMoveUp)

                    Button("Move Up", systemImage: "arrow.up")
                    {

                        onMove(.up)
                    }

                    .disabled(!canMoveUp)

                    Button("Move Down", systemImage: "arrow.down")
                    {

                        onMove(.down)
                    }

                    .disabled(!canMoveDown)

                    Button("Move to the Bottom", systemImage: "arrow.down.to.line")
                    {

                        onMove(.bottom)
                    }

                    .disabled(!canMoveDown)

                    Divider()

                    Button
                    {

                        titleDraft = checklist.title
                        isRenaming = true
                    }
                    label:
                    {

                        Label("Rename", systemImage: "pencil")
                    }


                    Button(role: .destructive)
                    {

                        confirmsDeletion = true
                    }
                    label:
                    {

                        Label("Delete", systemImage: "trash")
                    }

                }
                label:
                {

                    Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                }

                .buttonStyle(.plain)
                .accessibilityLabel("Checklist actions")
            }

            .padding(.bottom, 6)

            if !isCollapsed
            {


                ForEach(visibleItems, id: \.element.id)
                {
                    entry in
                    actionRow(for: entry)
                    .contextMenu
                    {

                        if onChangeType != nil
                        {

                            ForEach(ChecklistItemType.allCases)
                            {
                                type in
                                Button
                                {

                                    chooseType(type, for: entry.element)
                                }
                                label:
                                {

                                    Label(
                                        type.title, systemImage: type == entry.element.type ? "checkmark" : "circle"
                                    )
                                }

                            }

                        }

                    }
                    .accessibilityActions
                    {

                        if onChangeType != nil
                        {

                            Button("Change item type")
                            {

                                requestedType = entry.element.type
                                typeDraft = entry.element
                            }

                        }

                    }

                }


                HStack
                {

                    TextField("Add item...", text: $newItemText, axis: .vertical).textInputAutocapitalization(
                        .sentences
                    )
                    .lineLimit(1 ... 6)
                    .submitLabel(.done)
                    .onSubmit(submitNewItems)
                    .onChange(of: newItemText)
                    {
                        _, value in
                        if value.contains(where:
                            {
                                $0.isNewline
                            })
                        {
                            submitNewItems()
                        }

                    }

                    Button(action: submitNewItems)
                    {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(MultilineEntry.titles(newItemText).isEmpty)
                    .accessibilityLabel("Add checklist items")
                }
                .font(.subheadline)
                .padding(.vertical, 6)
            }

        }

        .padding(.vertical, 6)
        .alert("Delete checklist?", isPresented: $confirmsDeletion)
        {

            Button("Cancel", role: .cancel)
            {

            }

            Button("Delete Checklist", role: .destructive, action: onDelete)
        }
        message:
        {

            Text("Delete “\(checklist.title)” and all of its items? This cannot be undone.")
        }
        .sheet(item: $typeDraft)
        {
            item in
            ChecklistItemTypeEditor(item: item, initialType: requestedType, candidates: Array(linkedCardsByID.values))
            {

            updated in
                onChangeType?(updated) ?? false
            }

        }
        .alert("Rename Checklist", isPresented: $isRenaming)
        {

            TextField("Checklist title", text: $titleDraft).textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel)
            {

            }

            Button("Save")
            {

                onRename(titleDraft)
            }

            .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        message:
        {

            Text("Enter a name for this checklist.")
        }

    }

}


// --------------------------------------- MARK: - Checklist Item Row --------------------------- //


///
/// Displays one touch-friendly checklist item with a custom swipe-to-delete interaction
///
/// @section    Purpose
///     Provide reliable physical-device swipe behavior inside the card's custom ScrollView layout
///
struct ChecklistItemRow: View
{


    @Environment(\.planningCalendarAccess) private var planningAccess
    let planningLinkID:     UUID?
    let linkedCollectionID: UUID?
    @Environment(\.cardMovementSource) private var linkedSourceID

    let item:           String       /* The editable item text               */
    let isCompleted:    Bool         /* The current completion state         */
    let linkedCardID:   Int?         /* Stable linked card ID, when present  */
    let linkedCard:     KanbanCard?  /* Resolved linked card, when available */
    var webURL:         URL? = nil
    let onOpenDetail:   (() -> Void)?     /* Action Detail presentation callback                           */
    let onToggle:       () -> Void        /* The action invoked by the checkbox                            */
    let onUpdate:       (String) -> Void  /* The action invoked by text editing                            */
    let onDelete:       () -> Void        /* The action invoked by delete                                  */
    let shouldFocus:    Bool              /* Indicates whether the text field should receive focus         */
    let onFocusHandled: () -> Void        /* The action invoked when the text field focus has been handled */

    @State private var horizontalOffset:   CGFloat = 0  /* Current swipe translation */
    @FocusState private var isTextFocused: Bool         /* Text-editor focus state   */


    ///
    /// @fcn        ChecklistItemRow.init(item:isCompleted:linkedCardID:linkedCard:onOpenDetail:onToggle:onUpdate:onDelete:shouldFocus:onFocusHandled:)
    /// @brief      Initialize a standard, linked-card, or Action Detail checklist row
    /// @details    Optional navigation inputs determine the title control while completion and deletion
    ///             remain available for every action type
    ///
    /// @param[in]  item                Display title or editable standard-action text
    /// @param[in]  isCompleted         Current completion state
    /// @param[in]  linkedCardID        Optional stable linked-card reference
    /// @param[in]  linkedCard          Resolved linked card, or nil for an unavailable destination
    /// @param[in]  onOpenDetail        Optional reduced Action Detail presentation callback
    /// @param[in]  onToggle            Completion action
    /// @param[in]  onUpdate            Standard-action text update callback
    /// @param[in]  onDelete            Record deletion callback
    /// @param[in]  shouldFocus         Whether a standard editor requests focus on appearance
    /// @param[in]  onFocusHandled      Callback acknowledging the scheduled focus request
    ///
    /// @param[in]  planningLinkID      Optional owner-qualified destination for a dated linked Card
    /// @param[in]  linkedCollectionID  Optional explicit collection owner for a linked Card's local
    ///             ID
    /// @param[in]  webURL              Optional web-link destination for the checklist action
    ///
    /// @return     (ChecklistItemRow) configured action row
    /// @post       Initialization installs inputs without invoking any callbacks
    ///
    init(
        item: String,
        isCompleted: Bool,
        planningLinkID: UUID? = nil,
        linkedCardID: Int? = nil,
        linkedCollectionID: UUID? = nil,
        linkedCard: KanbanCard? = nil,
        onOpenDetail: (() -> Void)? = nil,
        webURL: URL? = nil,
        onToggle: @escaping () -> Void,
        onUpdate: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        shouldFocus: Bool,
        onFocusHandled: @escaping () -> Void
    )
    {


        self.item = item
        self.isCompleted = isCompleted
        self.planningLinkID = planningLinkID
        self.linkedCollectionID = linkedCollectionID
        self.linkedCardID = linkedCardID
        self.linkedCard = linkedCard
        self.onOpenDetail = onOpenDetail
        self.webURL = webURL
        self.onToggle = onToggle
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.shouldFocus = shouldFocus
        self.onFocusHandled = onFocusHandled
    }


    ///
    /// @fcn        ChecklistItemRow.body
    /// @brief      Present a typed checklist action with completion and horizontal deletion
    /// @details    Prioritizes linked-card navigation, then Action Detail, otherwise text editing.
    ///             Missing links show unavailable copy. Standard editors asynchronously handle initial focus
    ///
    /// @return     (some View) clipped row over a 72-point destructive button
    /// @post       Horizontal drags beyond 36 points reveal deletion; only the trash button invokes onDelete.
    ///             Vertical-dominant drags are ignored; text/completion changes delegate to callbacks
    /// @note       The parent must install a KanbanCard navigation destination for resolved links
    ///
    var body: some View
    {  /* Checklist action row and swipe-to-delete control */


        ZStack(alignment: .trailing)
        {


            Button(role: .destructive)
            {

                horizontalOffset = 0
                onDelete()
            }
            label:
            {


                Image(systemName: "trash")
                .foregroundStyle(.white)
                .frame(width: 72)
                .frame(maxHeight: .infinity)
                .background(.red)
            }

            .buttonStyle(.plain)
            .accessibilityLabel("Delete item")

            HStack(spacing: 10)
            {


                Button(action: onToggle)
                {


                    Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isCompleted ? .blue : .secondary)
                }

                .buttonStyle(.plain)
                .accessibilityLabel(isCompleted ? "Mark item incomplete" : "Mark item complete")

                if let webURL
                {

                    Link(destination: webURL)
                    {
                        Image(systemName: "globe").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Open website")
                }
                else if let linkedCardID
                {

                    if let planningLinkID, planningAccess?.document.checklistLinkWeeks? [planningLinkID] != nil
                    {

                        PlanningChecklistLink(itemID: planningLinkID, cardID: linkedCardID, title: item)
                    }
                    else if let owner = linkedCollectionID,
                    owner
                    != (linkedSourceID
                        ?? planningAccess?.document.weeks.first(where:
                            {

                                $0.startKey == planningAccess?.document.currentWeekKey
                            })?.id)
                    {

                        PlanningChecklistLink(
                            itemID: planningLinkID ?? UUID(), cardID: linkedCardID, title: item, ownerID: owner)
                    }
                    else if let linkedCard
                    {

                        NavigationLink(value: linkedCard)
                        {

                            Image(systemName: "link").frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open linked card: \(item)")
                    }
                    else
                    {

                        Image(systemName: "link.badge.plus")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Linked card \(linkedCardID) is unavailable")
                    }

                }
                else if let onOpenDetail
                {

                    Button(action: onOpenDetail)
                    {

                        Image(systemName: "doc.text").frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open action details: \(item)")
                }


                ChecklistTextField(
                    text: Binding(get:
                        {
                            item
                        }, set: onUpdate),
                    focus: Binding(get:
                        {
                            isTextFocused
                        }, set:
                        {
                            isTextFocused = $0
                        })
                )
                .onAppear
                {

                    guard shouldFocus else
                    {
                        return
                    }

                    DispatchQueue.main.async
                    {

                        isTextFocused = true
                        onFocusHandled()
                    }

                }


                Spacer()
            }

            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .background(.background)
            .offset(x: horizontalOffset)
            .simultaneousGesture(

                DragGesture(minimumDistance: 12)
                .onChanged
                {
                    value in
                    guard abs(value.translation.width) > abs(value.translation.height) else
                    {


                        return
                    }


                    horizontalOffset = min(0, max(-72, value.translation.width))
                }
                .onEnded
                {
                    value in
                    guard abs(value.translation.width) > abs(value.translation.height) else
                    {


                        return
                    }


                    withAnimation(.easeOut(duration: 0.2))
                    {

                        horizontalOffset = value.translation.width < -36 ? -72 : 0
                    }

                }
            )
        }

        .clipped()
    }

}


///
/// Bridges checklist action text to native editing
///
/// @section    Purpose
///     Selects existing writing on initial entry, then permits ordinary caret changes and delegates
///     focus and submission through bindings.
///
struct ChecklistTextField: UIViewRepresentable
{


    @Binding var text:  String
    @Binding var focus: Bool


    ///
    /// @fcn        ChecklistTextField.makeCoordinator
    /// @brief      Create the native bridge coordinator
    /// @details    Creates the coordinator retained by SwiftUI for ChecklistTextField so its delegate or observation
    ///             state can span view updates.
    ///
    /// @return     (Coordinator) retained native bridge coordinator
    ///
    func makeCoordinator() -> Coordinator
    {
        Coordinator(self)
    }


    ///
    /// @fcn        ChecklistTextField.makeUIView
    /// @brief      Create the native single-line checklist editor
    /// @details    Configures dynamic type, delegate callbacks, the Done return key, and horizontal layout priorities
    ///             appropriate for an editable row.
    ///
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (UITextField) native checklist text field configured for single-line editing
    ///
    func makeUIView(context: Context) -> UITextField
    {

        let field = UITextField()
        field.autocapitalizationType = .sentences
        field.placeholder = "Item"
        field.font = .preferredFont(forTextStyle: .subheadline)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .label
        field.returnKeyType = .done
        field.accessibilityLabel = "Checklist item"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }


    ///
    /// @fcn        ChecklistTextField.updateUIView
    /// @brief      Synchronize checklist text and requested focus
    /// @details    Updates changed text and makes or resigns first responder according to the parent focus value.
    ///
    /// @param[in]  field    Native checklist text field delivering the delegate callback
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (Void) no return value
    ///
    func updateUIView(_ field: UITextField, context: Context)
    {

        context.coordinator.parent = self
        if field.text != text
        {
            field.text = text
        }

        if focus && !field.isFirstResponder
        {

            field.becomeFirstResponder()
        }
        else if !focus && field.isFirstResponder
        {

            field.resignFirstResponder()
        }

    }


    ///
    /// @fcn        ChecklistTextField.sizeThatFits
    /// @brief      Measure a checklist editor at the proposed width
    /// @details    Returns nil without a width proposal and otherwise uses its intrinsic height with a
    ///             twenty-four-point minimum.
    ///
    /// @param[in]  proposal  Parent layout proposal, including an optional available width
    /// @param[in]  uiView    Native editor whose fitting size is being measured
    /// @param[in]  context   Framework-supplied update context and coordinator access
    ///
    /// @return     (CGSize?) proposed width and intrinsic height of at least twenty-four points, or nil without width
    ///
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize?
    {

        guard let width = proposal.width else
        {
            return nil
        }

        return CGSize(width: width, height: max(24, uiView.intrinsicContentSize.height))
    }


    ///
    /// Handles checklist text-field editing and submission
    ///
    /// @section    Purpose
    ///     Publishes native text and focus changes through the representable's latest bindings and
    ///     supports initial selection behavior.
    ///
    class Coordinator: NSObject, UITextFieldDelegate
    {


        var parent: ChecklistTextField


        ///
        /// @fcn        ChecklistTextField.Coordinator.init
        /// @brief      Retain the checklist representable for text-field callbacks
        /// @details    Stores the parent bindings used to publish native text and focus changes.
        ///
        /// @param[in]  parent  Representable value supplying the delegate's current bindings and callbacks
        ///
        /// @return     (Coordinator) initialized instance
        ///
        init(_ parent: ChecklistTextField)
        {
            self.parent = parent
        }


        ///
        /// @fcn        ChecklistTextField.Coordinator.changed
        /// @brief      Copy native checklist text into its SwiftUI binding
        /// @details    Normalizes a nil text-field value to an empty string on editing changes.
        ///
        /// @param[in]  field  Native checklist text field delivering the delegate callback
        ///
        /// @return     (Void) no return value
        ///
        @objc func changed(_ field: UITextField)
        {
            parent.text = field.text ?? ""
        }


        ///
        /// @fcn        ChecklistTextField.Coordinator.textFieldDidBeginEditing
        /// @brief      Select the existing checklist text when editing begins
        /// @details    Marks the parent as focused and defers full-text selection to the main queue.
        ///
        /// @param[in]  field  Native checklist text field delivering the delegate callback
        ///
        /// @return     (Void) no return value
        ///
        func textFieldDidBeginEditing(_ field: UITextField)
        {

            parent.focus = true
            DispatchQueue.main.async
            {
                [weak field] in
                guard let field, field.isFirstResponder, !(field.text ?? "").isEmpty else
                {
                    return
                }

                field.selectAll(nil)
            }

        }


        ///
        /// @fcn        ChecklistTextField.Coordinator.textFieldDidEndEditing
        /// @brief      Clear the checklist row's focus state
        /// @details    Updates the parent binding after native editing ends.
        ///
        /// @param[in]  field  Native checklist text field delivering the delegate callback
        ///
        /// @return     (Void) no return value
        ///
        func textFieldDidEndEditing(_ field: UITextField)
        {
            parent.focus = false
        }


        ///
        /// @fcn        ChecklistTextField.Coordinator.textFieldShouldReturn
        /// @brief      Finish checklist editing from the return key
        /// @details    Ends native focus through the field's return-key handling and returns the delegate's
        ///             acceptance result.
        ///
        /// @param[in]  field  Native checklist text field delivering the delegate callback
        ///
        /// @return     (Bool) true to accept the return-key request after ending editing
        ///
        func textFieldShouldReturn(_ field: UITextField) -> Bool
        {

            field.resignFirstResponder()
            return true
        }

    }

}
