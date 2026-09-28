// -------------------------------------------------------------------------------------------------
// @file       CardDetailView.swift
// @brief      Detailed kanban card presentation and supporting components
// @details    Defines the card detail screen, sections, actions, metadata rows, and activity feed
//
// @notes      Supporting views are intentionally small and reusable within the detail screen
//
// @section    Opens
//     Modularize into separate files
//
// -------------------------------------------------------------------------------------------------
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers


/// Identifies a checklist's requested position within its card.
///
/// @section    Purpose
///     Represent adjacent and absolute checklist move operations
///
/// @note   Boundary actions are disabled in ChecklistBlock when no movement is possible
///
enum ChecklistMoveDirection {
    case top
    case up
    case down
    case bottom
}


// -------------------------------------- MARK: - Card Detail View ------------------------------ //

///
/// Presents the complete detail view for a selected kanban card
///
/// @section    Purpose
///     Render the selected card's title, context, metadata, checklists, activity, and navigation action
///
/// @note   The detail surface is intentionally scrollable so every card section remains accessible on iPhone
///
struct CardDetailView: View {

    // ----------------------------------- MARK: - Date Field Enum ------------------------------ //

    private enum DateField: String, Identifiable, Equatable {

        case start      /* Start date field for the card */
        case due        /* Due date field for the card   */

        var id: String { rawValue }

        var title: String {
            switch self {
                case .start: return "Start date"
                case .due:   return "Due date"
            }
        }
    }

    ///
    /// Identifies the modal sheet currently presented by the card detail view
    ///
    /// @section    Purpose
    ///     Distinguish date-picker presentation from the card-member management sheet
    ///
    /// @details    Each case supplies a stable identity so SwiftUI can update or replace the
    ///             active sheet reliably
    ///
    /// @note       The date case carries the specific start or due date field to edit
    ///
    private enum ActiveSheet: Identifiable {

        case date(DateField)                        /* Date picker sheet for editing a specific date field */
        case members                                /* Card member management sheet                        */
        case labels                                 /* Card label library and assignment picker            */
        case attachmentSources                      /* Attachment source chooser                           */
        case addLink                                /* Manual web-link entry sheet                         */
        case attachmentPreview(KanbanAttachment)    /* Preview of an attached photo                        */

        var id: String {                            /* Stable identity for the active sheet                */

            switch self {
                case .date(let field):                   "date-\(field.id)"
                case .members:                           "members"
                case .labels:                            "labels"
                case .attachmentSources:                 "attachment-sources"
                case .addLink:                           "add-link"
                case .attachmentPreview(let attachment): "attachment-\(attachment.id.uuidString)"
            }
        }
    }

    /// Stable identifiers and display copy for the card's generated activity entries
    ///
    /// @section    Purpose
    ///     Keep generated activity text identifiable so a user's deletion remains associated with
    ///     the card
    ///
    private enum GeneratedActivity: String, CaseIterable, Identifiable {
        case addedCard          /* Card was added to the board           */
        case createdCard        /* Card was created on the board         */
        case initialComment     /* Initial comment was added to the card */

        var id: String { rawValue }

        ///
        /// @fcn        GeneratedActivity.text(for:actorName:)
        /// @brief      Generate the display text for an activity entry
        /// @details    Resolves this activity type into user-visible copy using the selected
        ///             card's title and list
        ///
        /// @param[in]  card       Card whose activity feed is being rendered
        /// @param[in]  actorName  Current user name shown as the activity actor
        ///
        /// @return     (String) display text for this generated activity entry
        ///
        /// @pre        card contains the identity and list details used by the activity message
        /// @post       No card or activity state is modified
        ///
        func text(for card: KanbanCard, actorName: String) -> String {
            
            switch self {
                case .addedCard:
                    return "\(actorName) added \(card.word) to this card"
                case .createdCard:
                    return "\(actorName) created this card in \(card.listTitle)"
                case .initialComment:
                    return "\(actorName): \"This is going to be surprisingly useful.\""
            }
        }
    }

    /// Selection modes available for the card's Activity feed
    ///
    /// @section    Purpose
    ///     Control whether the feed displays all entries, comments, or generated card activity
    ///
    /// @note   This filter is presentation state and is not persisted with the card
    ///
    private enum ActivityFilter: String, CaseIterable, Identifiable {
        case all                /* All activity entries for the card       */
        case comments           /* User-added comments for the card        */  
        case cardActivity       /* Generated activity entries for the card */

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:          "All Activity"
            case .comments:     "Comments"
            case .cardActivity: "Card Activity"
            }
        }
    }

    // Selection modes for editable fields within the card detail view
    private enum EditableField: Hashable {
        case title              /* The title field is being edited       */
        case subtitle           /* The subtitle field is being edited    */
        case description        /* The description field is being edited */
        case comment            /* The comment field is being edited     */
    }

    let card: KanbanCard                                     /* The kanban card being displayed in detail                    */
    @Binding var labelLibrary: LabelLibrary                  /* Shared label catalog available to every card                 */
    let availableLists: [KanbanList]                         /* Other lists that can receive this card                       */
    let memberColors: [String: Color]                        /* Shared icon colors keyed by normalized member name           */
    let currentUserName: String                              /* Current actor name shown in card activity                    */
    let onTitleToggle: ((KanbanCard) -> Void)?               /* Callback invoked when the card title checkbox is toggled     */
    let onMoveToList: ((Int) -> Void)?                       /* Callback invoked to move the card to a selected list         */

    @Environment(\.dismiss) private var dismiss              /* Dismiss action for the card detail view                      */
    @FocusState private var focusedField: EditableField?     /* current focused editable field within the card detail view   */

    @State private var checklists: [KanbanChecklist]         /* The checklist groups associated with the selected card       */
    @State private var checklistToFocus: UUID?               /* Newly added checklist whose first item should be focused     */
    @State private var titleChecked: Bool                    /* Whether the card title itself is checked                     */
    @State private var titleText: String                     /* Editable card title displayed in the detail header           */
    @State private var subtitleText: String                  /* Editable card subtitle displayed in the detail header        */
    @State private var startDate: Date?                      /* Optional start date for the selected card                    */
    @State private var dueDate: Date?                        /* Optional due date for the selected card                      */
    @State private var descriptionText: String               /* Editable description shown on this card                      */
    @State private var activeSheet: ActiveSheet?             /* The date picker or member editor currently presented         */
    @State private var comments: [KanbanComment]             /* Comments saved to this card's activity                       */
    @State private var members: [String]                     /* Users assigned to the selected card                          */
    @State private var selectedLabelIDs: [String]            /* Stable IDs of labels assigned to this card                   */
    @State private var attachments: [KanbanAttachment]       /* Photo attachments currently assigned to the card             */
    @State private var selectedPhotoItems: [PhotosPickerItem] = [] /* Photos selected from the system photo library          */
    @State private var commentDraft = ""                     /* Text currently entered in the comment composer               */
    @State private var dismissedActivityIDs: Set<String>     /* IDs of activity entries that have been dismissed by the user */
    @State private var activityFilter: ActivityFilter = .all /* The currently selected activity filter for the card          */
    @State private var showingAttachmentNotice = false       /* Whether an attachment notice is presented                    */
    @State private var attachmentNoticeMessage = ""          /* Explanation shown for failed or unavailable sources          */

    ///
    /// @brief      Initialize the card detail state
    /// @details    Seeds the card with the Focus, Plan, and Routine checklist groups shown in the detail view
    ///
    /// @param[in]  card        The kanban card being displayed in detail
    ///
    /// @return     (CardDetailView) configured card detail presentation
    ///
    init(
        card: KanbanCard,
        labelLibrary: Binding<LabelLibrary> = .constant(.starter),
        availableLists: [KanbanList]           = [],        /* Other lists available as move destinations                   */
        memberColors: [String: Color]          = [:],       /* Shared member icon colors                                    */
        currentUserName: String                = "Justin Reina",
        onTitleToggle: ((KanbanCard) -> Void)? = nil,       /* Callback invoked when the card title checkbox is toggled     */
        onMoveToList: ((Int) -> Void)?         = nil        /* Callback invoked when the card is moved                      */
    ) {

        self.card           = card                                              /* The kanban card being displayed in detail                            */
        self._labelLibrary  = labelLibrary                                      /* Shared catalog used by all card label assignments                    */
        self.availableLists = availableLists                                    /* Other lists available as move destinations                           */
        self.memberColors   = memberColors                                      /* Shared member icon colors                                            */
        self.currentUserName = currentUserName                                  /* Current actor name shown in card activity                            */
        self.onTitleToggle  = onTitleToggle                                     /* Callback invoked when the card title checkbox is toggled             */
        self.onMoveToList   = onMoveToList                                      /* Callback invoked when the card is moved                              */

        _titleChecked         = State(initialValue: card.isTitleChecked)        /* Initialize the title checked state based on the card's current value */
        _titleText            = State(initialValue: card.word)                  /* Initialize the editable title from the card                          */
        _subtitleText         = State(initialValue: card.subtitle)              /* Initialize the editable subtitle from the card                       */
        _startDate            = State(initialValue: card.startDate)             /* Initialize the start date from the card state                        */
        _dueDate              = State(initialValue: card.dueDate)               /* Initialize the due date from the card state                          */
        _descriptionText      = State(initialValue: card.funParagraph)          /* Initialize the editable description from the card                    */
        _comments             = State(initialValue: card.comments)              /* Initialize comments from the selected card                           */
        _members              = State(initialValue: card.members)               /* Initialize assigned members from the selected card                   */
        _selectedLabelIDs     = State(initialValue: card.labelIDs)              /* Initialize selected labels from the card                             */
        _attachments          = State(initialValue: card.attachments ?? [])     /* Initialize photo attachments from the card                           */
        _dismissedActivityIDs = State(initialValue: card.dismissedActivityIDs)  /* Initialize dismissed activity IDs from the card state                */

        _checklists = State(initialValue: card.checklists)                      /* Initialize checklist state from the card's stored values             */
    }

    // MARK: - Member Icon Color Helper
    private func memberIconColor(for memberName: String) -> Color {

        let normalizedName = memberName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return memberColors[normalizedName] ?? .accentColor
    }

    private var selectedLabels: [KanbanLabel] {
        selectedLabelIDs.compactMap { labelID in
            labelLibrary.labels.first(where: { $0.id == labelID })
        }
    }


    @MainActor
    ///
    /// @fcn        CardDetailView.importPhotos(from:)
    /// @brief      Import selected photo-library items as card attachments
    /// @details    Loads each selected photo or video, stores successful transfers in the app container,
    ///             synchronizes the attachment metadata to the card, and reports partial failures
    ///
    /// @param[in]  photoItems  PhotosPicker items selected for the current card
    ///
    /// @return     (Void) updates the card with successfully imported photo and video attachments
    ///
    /// @pre        photoItems were selected from the PhotosPicker for this card
    /// @post       The selection is cleared; saved attachment records are synchronized to board state
    ///
    /// @note       Successful imports are retained even if another selected item fails to load or save
    ///
    private func importPhotos(from photoItems: [PhotosPickerItem]) async {

        var importFailed = false

        for photoItem in photoItems {
            
            do {
                guard let mediaData = try await photoItem.loadTransferable(type: Data.self) else {
                    importFailed = true
                    continue
                }

                let contentType = photoItem.supportedContentTypes.first
                let isVideo = photoItem.supportedContentTypes.contains {
                    $0.conforms(to: .movie) || $0.conforms(to: .video)
                }
                let mediaKind: KanbanAttachmentKind = isVideo ? .video : .photo
                let fileExtension = contentType?.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg")

                attachments.append(try CardAttachmentStore.saveMedia(mediaData, kind: mediaKind, fileExtension: fileExtension))
            } catch {
                importFailed = true
            }
        }

        selectedPhotoItems = []
        activeSheet        = nil

        syncCardState(attachments: attachments)

        if importFailed {
            attachmentNoticeMessage = "One or more selected photos or videos could not be added. Please try again."
            showingAttachmentNotice = true
        }
    }

    private func addWebLink(_ url: URL) {
        attachments.append(KanbanAttachment(url: url, mediaKind: .link))
        activeSheet = nil
        syncCardState(attachments: attachments)
    }

    private func addClipboardLink() {
        
        let clipboardText = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""

        guard let url = CardAttachmentStore.webURL(from: clipboardText) else {
            
            attachmentNoticeMessage = "The clipboard does not contain a valid web link."
            showingAttachmentNotice = true
            activeSheet             = nil
            
            return
        }

        addWebLink(url)
    }

    private func showAttachmentSourceComingSoon(_ source: String) {
        
        attachmentNoticeMessage = "\(source) attachments are coming soon."
        showingAttachmentNotice = true
        activeSheet             = nil
    }

    ///
    /// @fcn        CardDetailView.removeAttachment(_:)
    /// @brief      Remove one photo from the current card
    /// @details    Deletes the attachment record from local detail state and synchronizes the updated card;
    ///             the board owner removes the stored image file if no card references it
    ///
    /// @param[in]  attachment  Photo attachment selected for removal
    ///
    /// @return     (Void) updates the card's attachment collection and persistence state
    ///
    /// @pre        attachment identifies an item in the current card's attachment collection
    /// @post       The selected photo is no longer assigned to this card
    ///
    private func removeAttachment(_ attachment: KanbanAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        syncCardState(attachments: attachments)
    }


    ///
    /// @brief      Push the current card state back to the parent board
    /// @details    Builds the latest card snapshot from the title checkbox and date values,
    ///             then emits it to the callback so the list view remains synchronized
    ///
    /// @param[in]  titleChecked   Optional updated checked state for the card title
    /// @param[in]  startDate      Optional updated start date for the card
    /// @param[in]  dueDate        Optional updated due date for the card
    /// @param[in]  clearStartDate Whether to remove the card's start date
    /// @param[in]  clearDueDate   Whether to remove the card's due date
    ///
    /// @post       The parent view receives the current card state for persistence
    ///
    private func syncCardState(
        title:          String?             = nil,
        subtitle:       String?             = nil,
        members:        [String]?           = nil,
        labelIDs:       [String]?           = nil,
        attachments:    [KanbanAttachment]? = nil,
        titleChecked:   Bool?               = nil,
        startDate:      Date?               = nil,
        dueDate:        Date?               = nil,
        clearStartDate: Bool                = false,
        clearDueDate:   Bool                = false
    ) {

        let nextTitleChecked = titleChecked   ?? self.titleChecked
        let nextTitle         = title         ?? titleText
        let nextSubtitle      = subtitle      ?? (card.subtitleOverride == nil && subtitleText == card.subtitle ? nil : subtitleText)
        let nextMembers       = members       ?? self.members
        let nextLabelIDs      = labelIDs      ?? selectedLabelIDs
        let nextAttachments   = attachments   ?? self.attachments
        let nextStartDate     = clearStartDate ? nil : (startDate ?? self.startDate)
        let nextDueDate       = clearDueDate   ? nil : (dueDate   ?? self.dueDate)

        let updatedCard = KanbanCard(
            id:                   card.id,
            word:                 nextTitle,
            listTitle:            card.listTitle,
            isDivider:            card.isDivider,
            isTitleChecked:       nextTitleChecked,
            startDate:            nextStartDate,
            dueDate:              nextDueDate,
            checklists:           checklists,
            comments:             comments,
            members:              nextMembers,
            labelIDs:             nextLabelIDs,
            attachments:          nextAttachments,
            dismissedActivityIDs: dismissedActivityIDs,
            descriptionOverride:  descriptionText,
            subtitleOverride:     nextSubtitle
        )

        onTitleToggle?(updatedCard)
    }


    ///
    /// @brief      Toggle the checked state of the card's title
    /// @details    Flips the boolean value representing whether the card's main title checkbox is
    ///             selected and synchronizes this change with the parent board
    ///
    private func toggleCardTitle() {

        let nextChecked = !titleChecked
        titleChecked    = nextChecked

        syncCardState(titleChecked: nextChecked)
    }
    

    ///
    /// @brief      Post a comment to the current card
    /// @details    Ignores empty drafts, appends a timestamped comment, and syncs it to the board
    ///
    private func postComment() {

        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return }

        comments.append(KanbanComment(author: "Justin Reina", body: text))
        commentDraft = ""

        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.deleteComment(with:)
    /// @brief      Delete a posted comment from the current card
    /// @details    Removes the comment matching its stable identifier and synchronizes the updated
    ///             card with the board
    ///
    /// @param[in]  commentID  Stable identifier of the comment to remove
    ///
    /// @return     (Void) the comment collection and parent card state are updated in place
    ///
    /// @pre        commentID identifies a comment in the current card
    /// @post       Comment is absent from Activity feed & remains deleted after reopening card
    ///
    private func deleteComment(with commentID: UUID) {
        comments.removeAll { $0.id == commentID }
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.dismissGeneratedActivity(_:)
    /// @brief      Dismiss one generated activity entry from the current card
    /// @details    Records the entry's stable identifier as dismissed and synchronizes that state
    ///              with the board
    ///
    /// @param[in]  activity  Generated activity entry selected for removal
    ///
    /// @return     (Void) the entry is removed from the rendered Activity feed
    ///
    /// @pre        activity is a generated entry belonging to the current card
    /// @post       The entry stays dismissed when the card is reopened
    ///
    private func dismissGeneratedActivity(_ activity: GeneratedActivity) {
        dismissedActivityIDs.insert(activity.id)
        syncCardState()
    }


    ///
    /// @brief      Reset the selected card date to its unset value
    /// @details    Clears only the requested date, synchronizes the card, and closes the calendar sheet
    ///
    /// @param[in]  field  The date field to reset
    ///
    private func resetDate(for field: DateField) {

        switch field {
            case .start:
                startDate = nil
                syncCardState(clearStartDate: true)
            case .due:
                dueDate = nil
                syncCardState(clearDueDate: true)
        }

        activeSheet = nil
    }


    ///
    /// @brief      Create a binding for the selected card date
    /// @details    Updates the local date and parent card state, then dismisses the calendar sheet
    ///
    /// @param[in]  field  The card date field being edited
    ///
    /// @return     (Binding<Date>) binding that updates and dismisses on selection
    ///
    private func dateBinding(for field: DateField) -> Binding<Date> {

        Binding(
            get: {

                switch field {

                    case .start: 
                        return startDate ?? Date()

                    case .due:   
                        return dueDate ?? Date()
                }
            },
            set: { newValue in

                switch field {

                    case .start:
                        startDate = newValue
                        syncCardState(startDate: newValue)
                        
                    case .due:
                        dueDate = newValue
                        syncCardState(dueDate: newValue)
                }
                
                activeSheet = nil
            }
        )
    }


    /// Builds the shared destination-list menu used by the card actions and list label.
    @ViewBuilder
    private func moveCardMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            ForEach(availableLists) { list in
                Button(list.title) {
                    onMoveToList?(list.id)
                    dismiss()
                }
            }
        } label: {
            label()
        }
        .disabled(availableLists.isEmpty)
    }


    ///
    /// @fcn        CardDetailView.dateRow(for:)
    /// @brief      Build one start-date or due-date row
    /// @details    Opens date picker when tapped & enables swipe-to-remove only while date is set
    ///
    /// @param[in]  field  Date field represented by this row
    ///
    /// @return     (some View) date row with the appropriate add, edit, and removal actions
    ///
    /// @pre        field is either the card's start date or due date
    /// @post       Rendering the row does not modify the stored date
    ///
    @ViewBuilder
    private func dateRow(for field: DateField) -> some View {

        let currentDate = field == .start ? startDate : dueDate
        let iconName    = field == .start ? "calendar" : "calendar.badge.clock"

        let dateLabel = currentDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Add date"
        let fieldName = field.title.lowercased()

        let row = HStack(alignment: .center) {

            Image(systemName: iconName)
                .foregroundStyle(.secondary)

            Text(field.title)
                .font(.body)

            Spacer()

            Button {
                activeSheet = .date(field)
            } label: {
                Text(dateLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(currentDate == nil ? "Add" : "Edit") \(fieldName)")
        }

        if currentDate != nil {
            
            ActivitySwipeRow(
                onDelete: { resetDate(for: field) },
                deletionAccessibilityLabel: "Remove \(fieldName)"
            ) {
                row
            }
        } else {
            row
        }
    }


    ///
    /// @brief      Append a new empty checklist to the selected card's detail state
    /// @details    Adds a default checklist with its first item, syncs it to the card, scrolls it
    ///             into view, and focuses the item
    ///
    /// @param[in]  scrollProxy  Proxy used to scroll the new checklist into view
    ///
    /// @post       The new checklist's first item is visible and ready for editing
    ///
    private func addChecklist(using scrollProxy: ScrollViewProxy) {

        let checklist = KanbanChecklist(title: "Checklist", items: [""])

        checklists.append(checklist)
        
        checklistToFocus = checklist.id

        syncCardState()

        DispatchQueue.main.async {
            withAnimation(.easeInOut) {
                scrollProxy.scrollTo(checklist.id, anchor: .center)
            }
        }
    }


    ///
    /// @brief      Remove a checklist from the selected card's detail state
    /// @details    Filters the checklist collection by its stable identifier
    ///
    /// @param[in]  checklistID  Identifier of the checklist to remove
    ///
    /// @post       The selected checklist is no longer rendered in the Checklists section
    ///
    private func deleteChecklist(with checklistID: UUID) {

        checklists.removeAll { $0.id == checklistID }

        syncCardState()
    }

    ///
    /// @fcn        CardDetailView.renameChecklist(with:to:)
    /// @brief      Rename a checklist on the current card
    /// @details    Trims the proposed title, preserves the checklist's items and completion state,
    ///             and syncs the card
    ///
    /// @param[in]  checklistID  Stable identifier of the checklist to rename
    /// @param[in]  title        Proposed checklist title
    ///
    /// @return     (Void) updates the checklist and parent card when the title is non-empty
    ///
    /// @pre        checklistID identifies a checklist in the current card
    /// @post       The checklist displays the trimmed title; blank titles leave state unchanged
    ///
    private func renameChecklist(with checklistID: UUID, to title: String) {
        
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { return }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedTitle.isEmpty else { return }

        let checklist = checklists[checklistIndex]

        checklists[checklistIndex] = KanbanChecklist(
            id:                   checklist.id,
            title:                trimmedTitle,
            items:                checklist.items,
            completedItemIndices: checklist.completedItemIndices
        )
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.toggleAllItems(in:)
    /// @brief      Check every item or clear all checks in one checklist
    /// @details    Clears completion when all non-empty items are already checked; otherwise
    ///             checks every item
    ///
    /// @param[in]  checklistID  Stable identifier of the checklist to update
    ///
    /// @return     (Void) updates item completion state and synchronizes the card
    ///
    /// @pre        checklistID identifies a checklist on the current card
    /// @post       All items are checked, or all are unchecked when they were already all checked
    ///
    private func toggleAllItems(in checklistID: UUID) {

        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { return }

        let checklist            = checklists[checklistIndex]                                                                   /* current checklist               */
        let allItemsAreCompleted = !checklist.items.isEmpty && checklist.completedItemIndices.count == checklist.items.count    /* all non-empty items are checked */
        let completedIndices     = allItemsAreCompleted ? Set<Int>() : Set(checklist.items.indices)                             /* new completion state            */

        checklists[checklistIndex] = KanbanChecklist(
            id:                   checklist.id,
            title:                checklist.title,
            items:                checklist.items,
            completedItemIndices: completedIndices
        )

        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.moveChecklist(with:direction:)
    /// @brief      Move a checklist to an adjacent or absolute position
    /// @details    Removes the selected checklist and reinserts it at the requested position
    ///
    /// @param[in]  checklistID  Stable identifier of the checklist to move
    /// @param[in]  direction    Requested destination from ChecklistMoveDirection
    ///
    /// @return     (Void) updates checklist order and synchronizes the card
    ///
    /// @pre        checklistID identifies a checklist on the current card
    /// @post       The checklist occupies the requested position; boundary and single-checklist
    ///             moves leave order unchanged
    ///
    private func moveChecklist(with checklistID: UUID, direction: ChecklistMoveDirection) {

        // Ensure the checklist exists and there is more than one checklist to move
        guard let sourceIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              checklists.count > 1 else {
            return
        }

        let destinationIndex: Int

        switch direction {
            case .top:
                destinationIndex = 0
            case .up:
                destinationIndex = max(sourceIndex - 1, 0)
            case .down:
                destinationIndex = min(sourceIndex + 1, checklists.count - 1)
            case .bottom:
                destinationIndex = checklists.count - 1
        }

        guard sourceIndex != destinationIndex else { return }

        let movedChecklist = checklists.remove(at: sourceIndex)

        checklists.insert(movedChecklist, at: destinationIndex)

        syncCardState()
    }

    
    ///
    /// @brief      Append a new item to a checklist
    /// @details    Replaces matching value-type checklist with copy containing one addtnl item
    ///
    /// @param[in]  checklistID  Identifier of the checklist receiving the new item
    ///
    /// @post       The new item appears above the checklist's Add item... control
    ///
    private func addItem(to checklistID: UUID) {

        // Find the index of the checklist to which the new item will be added
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else {
            return
        }

        let checklist = checklists[checklistIndex]
        let itemNumber = checklist.items.count + 1

        checklists[checklistIndex] = KanbanChecklist(
            id:    checklist.id,
            title: checklist.title,
            items: checklist.items + [KanbanChecklistItem(title: "Item \(itemNumber)")]
        )
        syncCardState()
    }


    ///
    /// @brief      Toggle one checklist item's completion state
    /// @details    Replaces the matching value-type checklist with updated completed item indices
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being toggled
    ///
    /// @post       The selected item changes between complete and incomplete
    ///
    private func toggleItem(in checklistID: UUID, at itemIndex: Int) {

        // Find the index of the checklist being updated
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else {
            return
        }

        let checklist = checklists[checklistIndex]                  /* Retrieve the checklist being updated       */
        var completedItemIndices = checklist.completedItemIndices   /* Copy current set of completed item indices */

        // Toggle the completion state of the specified item within the checklist
        if completedItemIndices.contains(itemIndex) {
            completedItemIndices.remove(itemIndex)
        } else {
            completedItemIndices.insert(itemIndex)
        }

        // Update the checklist with the new set of completed item indices
        checklists[checklistIndex] = KanbanChecklist(
            id:                    checklist.id,
            title:                 checklist.title,
            items:                 checklist.items,
            completedItemIndices:  completedItemIndices
        )
        syncCardState()
    }


    ///
    /// @brief      Update one checklist item's text
    /// @details    Replaces the matching value-type checklist with an updated item label
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being edited
    /// @param[in]  text         New display text for the item
    ///
    /// @post       The edited text is displayed in the checklist row
    ///
    private func updateItem(in checklistID: UUID, at itemIndex: Int, with text: String) {
        
        // Find the index of the checklist being updated
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else {
            return
        }

        // Retrieve the checklist being updated
        let checklist = checklists[checklistIndex]

        // Ensure the item index is within the bounds of the checklist's items array
        guard checklist.items.indices.contains(itemIndex) else {
            return
        }

        var items = checklist.items       /* Copy the current list of items for modification            */
        items[itemIndex].title = text     /* Update the text while preserving stable item identity       */

        // Update the checklist with the modified items array
        checklists[checklistIndex] = KanbanChecklist(
            id:                    checklist.id,
            title:                 checklist.title,
            items:                 items,
            completedItemIndices:  checklist.completedItemIndices
        )
        syncCardState()
    }


    ///
    /// @brief      Delete one checklist item
    /// @details    Removes the item and shifts completed item indices that follow it
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being deleted
    ///
    /// @post       The selected item is removed from the checklist
    ///
    private func deleteItem(in checklistID: UUID, at itemIndex: Int) {

        // Find the index of the checklist being updated
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else {
            return
        }

        // Retrieve the checklist being updated
        let checklist = checklists[checklistIndex]

        // Ensure the item index is within the bounds of the checklist's items array
        guard checklist.items.indices.contains(itemIndex) else {
            return
        }

        var items = checklist.items     /* Copy the current list of items for modification */
        items.remove(at: itemIndex)     /* Remove the specified item from the checklist    */

        // Recalculate the set of completed item indices after the deletion
        let completedItemIndices: Set<Int> = Set(

            checklist.completedItemIndices.compactMap { (index: Int) -> Int? in

                // Skip the index if it matches the deleted item index
                guard index != itemIndex else {
                    return nil
                }

                return index > itemIndex ? index - 1 : index
            }
        )

        // Update the checklist with the recalculated completed item indices
        checklists[checklistIndex] = KanbanChecklist(
            id:                    checklist.id,
            title:                 checklist.title,
            items:                 items,
            completedItemIndices:  completedItemIndices
        )
        syncCardState()
    }

    ///
    /// @fcn        CardDetailView.checklistBlock(for:)
    /// @brief      Build a checklist block wired to card checklist actions
    /// @details    Connects row actions to checklist state handlers and supplies the one-time first-item focus request
    ///
    /// @param[in]  checklist  Checklist data and identity used to configure the block
    ///
    /// @return     (some View) identified checklist block with edit, completion, add, delete, and rename actions
    ///
    /// @pre        checklist belongs to the current card's checklist collection
    /// @post       Rendering the block does not mutate checklist state
    ///
    @ViewBuilder
    private func checklistBlock(for checklist: KanbanChecklist) -> some View {

        let checklistIndex = checklists.firstIndex(where: { $0.id == checklist.id }) ?? 0

        ChecklistBlock(
            checklist: checklist,
            onDelete: {
                deleteChecklist(with: checklist.id)
            },
            onAddItem: {
                addItem(to: checklist.id)
            },
            onToggleItem: { itemIndex in
                toggleItem(in: checklist.id, at: itemIndex)
            },
            onUpdateItem: { itemIndex, text in
                updateItem(in: checklist.id, at: itemIndex, with: text)
            },
            onDeleteItem: { itemIndex in
                deleteItem(in: checklist.id, at: itemIndex)
            },
            onRename: { title in
                renameChecklist(with: checklist.id, to: title)
            },
            onToggleAllItems: {
                toggleAllItems(in: checklist.id)
            },
            onMove: { direction in
                moveChecklist(with: checklist.id, direction: direction)
            },
            canMoveUp:      checklistIndex > 0,
            canMoveDown:    checklistIndex < checklists.count - 1,
            focusFirstItem: checklist.id == checklistToFocus,
            onFirstItemFocused: {
                checklistToFocus = nil
            }
        )
        .id(checklist.id)
    }


    ///
    /// @brief      Build the card detail presentation
    /// @details    Composes the card sections and places a compact close action in the top safe area
    ///
    /// @return     (some View) rendered card detail screen
    ///
    var body: some View {

        ScrollViewReader { scrollProxy in
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if card.isSectionDivider {

                VStack(alignment: .leading) {

                    Text("---")
                        .font(.title2.weight(.bold))

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)

            } else {

                ScrollView {

                VStack(alignment: .leading, spacing: 0) {

                    HStack(alignment: .center, spacing: 12) {

                        Button(action: toggleCardTitle) {
                            
                            Image(systemName: titleChecked ? "checkmark.square.fill" : "square")
                                .font(.title2)
                                .foregroundStyle(titleChecked ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(titleChecked ? "Uncheck card title" : "Check card title")

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                TextField("Card title", text: $titleText)
                                    .font(.title2.weight(.bold))
                                    .textInputAutocapitalization(.never)
                                    .focused($focusedField, equals: .title)
                                    .submitLabel(.done)
                                    .onSubmit { focusedField = nil }
                                    .onChange(of: titleText) { _, newValue in
                                        syncCardState(title: newValue)
                                    }

                                moveCardMenu {
                                    Text(card.listTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Move card from \(card.listTitle)")
                                }

                            TextField("Card subtitle", text: $subtitleText)
                                .font(.subheadline)
                                .textInputAutocapitalization(.never)
                                .foregroundColor(focusedField == .subtitle ? Color.secondary : Color.clear)
                                .focused($focusedField, equals: .subtitle)
                                .submitLabel(.done)
                                .overlay(alignment: .leading) {
                                    if focusedField != .subtitle {
                                        Text(subtitleText)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .allowsHitTesting(false)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .onSubmit { focusedField = nil }
                                .onChange(of: subtitleText) { _, newValue in
                                    syncCardState(subtitle: newValue)
                                }
                        }

                        Spacer()

                    }
                    .padding(16)

                    //****************************************************************************//
                    // SECTION: Quick Actions                                                     //
                    //                                                                            //
                    //          Presents the primary actions available for the selected card      //
                    //****************************************************************************//
                    DetailSection(title: "Quick Actions") {

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {

                            ActionTile(title: "Add Checklist",  icon: "checklist", color: .green, action: { addChecklist(using: scrollProxy) })
                            ActionTile(title: "Add Attachment", icon: "paperclip", color: .cyan,  action: { activeSheet = .attachmentSources }
                            )
                            ActionTile(title: "Members",        icon: "person.2",  color: .purple, action: { activeSheet = .members })
                        }
                    }

                    if !attachments.isEmpty {
                        
                        DetailSection(title: "Attachments") {
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                                
                                ForEach(attachments) { attachment in
                                    
                                    Group {
                                        
                                        if let url = attachment.url {
                                            
                                            Link(destination: url) {
                                                CardAttachmentThumbnail(attachment: attachment)
                                            }
                                        } else {
                                            Button {
                                                activeSheet = .attachmentPreview(attachment)
                                            } label: {
                                                CardAttachmentThumbnail(attachment: attachment)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            removeAttachment(attachment)
                                        } label: {
                                            Label("Remove attachment", systemImage: "trash")
                                        }
                                    }
                                    .accessibilityLabel(attachment.url == nil ? "View attached media" : "Open attached link")
                                }
                            }
                        }
                    }

                    //****************************************************************************//
                    // SECTION: Description                                                       //
                    //                                                                            //
                    //          Presents humorous context assoc with selected card. Text expands  //
                    //          vertically so the complete description remains readable           //
                    //****************************************************************************//
                    DetailSection(title: "Description") {

                        TextField("Description", text: $descriptionText, axis: .vertical)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3...12)
                            .focused($focusedField, equals: .description)
                            .onTapGesture {
                                focusedField = .description
                            }
                            .onChange(of: descriptionText) {
                                syncCardState()
                            }
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    if focusedField == .description {
                                        Spacer()
                                        Button {
                                            focusedField = nil
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 16, weight: .semibold))
                                                .frame(width: 30, height: 30)
                                        }
                                        .foregroundStyle(.blue)
                                    }
                                }
                            }
                    }

                    //****************************************************************************//
                    // SECTION: Details                                                           //
                    //                                                                            //
                    //          Presents selected card's dates, labels & meta in aligned rows     //
                    //****************************************************************************//
                    DetailSection(title: "Details") {

                        if startDate != nil {
                            dateRow(for: .start)
                            Divider()
                        }

                        if dueDate != nil {
                            dateRow(for: .due)
                            Divider()
                        }

                        Button {
                            activeSheet = .labels
                        } label: {

                            HStack(spacing: 10) {

                                Image(systemName: "tag")
                                    .frame(width: 22)
                                    .foregroundStyle(.secondary)

                                Text("Labels")

                                Spacer()

                                if selectedLabels.isEmpty {

                                    Text("Add labels")
                                        .foregroundStyle(.secondary)

                                } else {

                                    ForEach(selectedLabels) { label in

                                        KanbanLabelChip(label: label)
                                    }
                                }
                            }
                            .font(.subheadline)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit card labels")

                        Divider()

                        Button {
                            activeSheet = .members

                        } label: {

                            HStack(spacing: 12) {

                                if members.isEmpty {

                                    Image(systemName: "person")
                                        .frame(width: 22)
                                        .foregroundStyle(.secondary)

                                } else {

                                    HStack(spacing: -5) {

                                        ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                                        
                                            Image(systemName: "person.crop.circle.fill")
                                                .foregroundStyle(memberIconColor(for: member))
                                        }
                                    }
                                    .frame(minWidth: 22, alignment: .leading)
                                }

                                Text("Members")

                                Spacer()

                                Text(members.isEmpty ? "Add members" : members.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit assigned members")
                    }

                    //****************************************************************************//
                    // SECTION: Checklists                                                        //
                    //                                                                            //
                    //          Presents card's checklist groups & completion state. Checklist    //
                    //          creation & deletion update the local collection rendered here     //
                    //****************************************************************************//
                    DetailSection(title: "Checklists", trailing: "plus", trailingAction: { addChecklist(using: scrollProxy) }) {

                        ForEach(checklists) { checklist in
                            checklistBlock(for: checklist)
                        }
                    }

                    //****************************************************************************//
                    // SECTION: Activity                                                          //
                    //                                                                            //
                    //          Presents the recent events associated with the selected card      //
                    //****************************************************************************//
                    VStack(alignment: .leading, spacing: 10) {

                        HStack {

                            Text("Activity")
                                .font(.headline)

                            Spacer()

                            Menu {
                                Picker("Show", selection: $activityFilter) {
                                    ForEach(ActivityFilter.allCases) { filter in
                                        Text(filter.title).tag(filter)
                                    }
                                }
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Activity options")
                        }

                        if activityFilter != .cardActivity {
                            ForEach(comments) { comment in
                                CommentActivityRow(
                                    comment: comment,
                                    memberColor: memberIconColor(for: comment.author)
                                ) {
                                    deleteComment(with: comment.id)
                                }
                            }
                        }

                        if activityFilter != .comments {
                            ForEach(GeneratedActivity.allCases.filter { !dismissedActivityIDs.contains($0.id) }) { activity in
                                ActivityRow(
                                    text: activity.text(for: card, actorName: currentUserName),
                                    actorColor: memberIconColor(for: currentUserName)
                                ) {
                                    dismissGeneratedActivity(activity)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(.background)
                    .overlay(alignment: .bottom) { Divider() }

                    HStack(alignment: .bottom, spacing: 10) {

                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(memberIconColor(for: currentUserName))

                        TextField("Comment...", text: $commentDraft, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focusedField, equals: .comment)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Button(action: postComment) {
                            Image(systemName: "paperplane.fill")
                                .font(.body.weight(.semibold))
                        }
                        .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Post comment")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .padding(.bottom, 12)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {

            HStack(spacing: 12) {

                Button {
                    dismiss()

                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray5), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close card")

                Spacer()

                if !card.isSectionDivider {

                    Menu {
                        Button {
                            addChecklist(using: scrollProxy)
                        } label: {
                            Label("Add checklist", systemImage: "checklist")
                        }
                        Button {
                            activeSheet = .date(.start)
                        } label: {
                            Label(startDate == nil ? "Add start date" : "Edit start date", systemImage: "calendar")
                        }
                        Button {
                            activeSheet = .date(.due)
                        } label: {
                            Label(dueDate == nil ? "Add due date" : "Edit due date", systemImage: "calendar.badge.clock")
                        }
                        Button {
                            focusedField = .comment
                        } label: {
                            Label("Add comment", systemImage: "text.bubble")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Add to card")

                    Menu {
                        Button(action: toggleCardTitle) {
                            Label(
                                titleChecked ? "Mark incomplete" : "Mark complete",
                                systemImage: titleChecked ? "square" : "checkmark.square"
                            )
                        }
                        Button {
                            focusedField = .description
                        } label: {
                            Label("Edit description", systemImage: "text.alignleft")
                        }
                        moveCardMenu {
                            Label("Move card", systemImage: "arrowshape.turn.up.right")
                        }
                        Button {
                            activityFilter = .all
                        } label: {
                            Label("Show all activity", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Card actions")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onChange(of: selectedPhotoItems) { _, photoItems in
            guard !photoItems.isEmpty else { return }
            Task {
                await importPhotos(from: photoItems)
            }
        }
        .alert("Attachment notice", isPresented: $showingAttachmentNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentNoticeMessage)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
                case .date(let field):
                    NavigationStack {
                        DatePicker(
                            field.title,
                            selection: dateBinding(for: field),
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding()
                        .navigationTitle(field.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Reset") {
                                    resetDate(for: field)
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    activeSheet = nil
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])

                case .members:
                    CardMembersSheet(members: members, memberColors: memberColors) { updatedMembers in
                        members = updatedMembers
                        syncCardState(members: updatedMembers)
                    }
                    .presentationDetents([.medium, .large])

                case .labels:
                    CardLabelsSheet(library: labelLibrary, selectedLabelIDs: selectedLabelIDs) { updatedLibrary, updatedLabelIDs in
                        labelLibrary     = updatedLibrary
                        selectedLabelIDs = updatedLabelIDs

                        syncCardState(labelIDs: updatedLabelIDs)
                    }
                    .presentationDetents([.large])

                case .attachmentSources:
                    CardAttachmentSourceSheet(
                        photoSelection: $selectedPhotoItems,
                        onAddLink: { activeSheet = .addLink },
                        onPasteClipboard: addClipboardLink,
                        onComingSoon: showAttachmentSourceComingSoon
                    )

                case .addLink:
                    CardLinkAttachmentSheet(onSave: addWebLink)

                case .attachmentPreview(let attachment):
                    CardAttachmentPreview(attachment: attachment)
            }
        }
        }
    }
}


///
/// Presents the names assigned to a card and lets the user maintain that list
///
/// @section    Purpose
///     Provide one interface for viewing, editing, adding, and removing users assigned to a card
///
/// @details    Keeps draft edits local until Save, trims names, removes case-insensitive duplicates,
///             and supports swipe-to-remove
///
/// @note       Member entries are stored as names or email strings; no separate user directory is required
///
private struct CardMembersSheet: View {

    let onSave: ([String]) -> Void                  /* Callback to be invoked when the list of members is saved    */
    let memberColors: [String: Color]               /* Shared icon colors keyed by normalized member name          */

    @Environment(\.dismiss) private var dismiss     /* Dismiss action for the sheet                                */
    @State private var members: [String]            /* Local copy of the members list for editing within the sheet */
    @State private var memberDraft = ""             /* Current text input for adding a new member                  */

    // Returns the member draft with leading and trailing whitespace removed
    private var trimmedMemberDraft: String {

        memberDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Determines whether the current member draft can be added to the list of members
    private var canAddMember: Bool {

        !trimmedMemberDraft.isEmpty && !members.contains {
            
            $0.localizedCaseInsensitiveCompare(trimmedMemberDraft) == .orderedSame
        }
    }

    // Returns a list of members with duplicates removed and whitespace trimmed
    private var normalizedMembers: [String] {

        var seenNames: Set<String> = []
        
        let membersToSave = canAddMember ? members + [trimmedMemberDraft] : members

        return membersToSave.compactMap { member in
            let trimmedMember  = member.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = trimmedMember.lowercased()

            guard !trimmedMember.isEmpty, seenNames.insert(normalizedName).inserted else {
                return nil
            }

            return trimmedMember
        }
    }

    /// Initializes the card members sheet with a list of members and a save callback
    /// - Parameters:
    ///   - members: The initial list of members assigned to the card
    ///   - onSave: A closure to be called when the list of members is saved
    init(members: [String], memberColors: [String: Color], onSave: @escaping ([String]) -> Void) {
        self.onSave = onSave
        self.memberColors = memberColors
        _members = State(initialValue: members)
    }

    ///
    /// @fcn        CardMembersSheet.addMember
    /// @brief      Add the current member draft to the assigned-user list
    /// @details    Appends trimmed draft & clears input when non-empty & not already assigned
    ///
    /// @return     (Void) updates the sheet's member draft and local assignment list
    ///
    /// @pre        memberDraft contains the current text entered in the Add user field
    /// @post       A valid unique name is appended and memberDraft is cleared; invalid or duplicate
    ///             drafts are unchanged
    ///
    /// @note       Duplicate detection is case-insensitive
    ///
    private func addMember() {
        
        guard canAddMember else { return }

        members.append(trimmedMemberDraft)
        memberDraft = ""
    }

    var body: some View {

        NavigationStack {

            List {

                Section("Assigned users") {

                    if members.isEmpty {
                        Text("No users assigned")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(members.indices, id: \.self) { index in

                        HStack(spacing: 10) {

                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(memberColors[members[index].lowercased()] ?? .accentColor)

                            TextField("Name or email", text: $members[index])
                                .textInputAutocapitalization(.never)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {

                            Button(role: .destructive) {
                                members.remove(at: index)

                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }

                Section("Add user") {

                    HStack {

                        TextField("Name or email", text: $memberDraft)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addMember)

                        Button(action: addMember) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(!canAddMember)
                        .accessibilityLabel("Add member")
                    }
                }
            }
            .navigationTitle("Card members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {

                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    
                    Button("Save") {
                        onSave(normalizedMembers)
                        dismiss()
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}


// --------------------------------------- MARK: - Detail Section ------------------------------- //

///
/// Groups a detail subsection with an optional trailing symbol
///
/// @section    Purpose
///     Provide a consistent heading, content area, spacing, and divider for card detail sections
///
/// @note   The generic content keeps this component reusable for text, controls, metadata, and activity
///
struct DetailSection<Content: View>: View {

    let title:          String          /* The title of the detail section                    */
    var trailing:       String?         /* The optional trailing symbol of the detail section */
    var trailingAction: (() -> Void)?   /* The optional action for the trailing symbol        */

    @ViewBuilder let content: () -> Content

    ///
    /// @brief      Initialize a detail section
    /// @details    Stores the section title, optional trailing symbol/action, and view-builder content
    ///
    /// @param[in]  title           Display title for the section
    /// @param[in]  trailing        Optional SF Symbol name shown at the trailing edge
    /// @param[in]  trailingAction  Optional action invoked by the trailing symbol
    /// @param[in]  content         Content rendered below the section heading
    ///
    /// @return     (DetailSection) configured detail section
    ///
    init(title: String, trailing: String? = nil, trailingAction: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {

        self.title          = title          /* The title of the detail section                    */
        self.trailing       = trailing       /* The optional trailing symbol of the detail section */
        self.trailingAction = trailingAction /* The optional action for the trailing symbol        */
        self.content        = content        /* The content of the detail section                  */
    }


    ///
    /// @brief      Build the detail section presentation
    /// @details    Renders the heading, optional trailing symbol/action, supplied content, and divider
    ///
    /// @return     (some View) rendered detail section
    ///
    var body: some View {

        // Build the detail section container with heading, optional trailing symbol/action, content, and divider
        VStack(alignment: .leading, spacing: 10) {

            // Build the heading row with title and optional trailing symbol/action
            HStack {

                // Render the section title
                Text(title)
                    .font(.headline)
                Spacer()

                // Render the trailing symbol and optional action if provided
                if let trailing {

                    // Check if a trailing action is provided
                    if let trailingAction {

                        Button(action: trailingAction) {
                            Image(systemName: trailing)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(title.lowercased())")
                    } else {

                        // Render the trailing symbol without an action
                        Image(systemName: trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content()
        }
        .padding(16)
        .background(.background)
        .overlay(alignment: .bottom) { Divider() }
    }
}


// --------------------------------------- MARK: - Action Tile ---------------------------------- //

///
/// Displays a labeled action tile in a card detail section
///
/// @section    Purpose
///     Present a labeled action with a symbol and accent color in the quick-actions grid
///
struct ActionTile: View {

    let title: String       /* The title of the action tile                  */
    let icon:  String       /* The icon representing the action tile         */
    let color: Color        /* The color of the action tile                  */
    let action: () -> Void  /* The action to perform when the tile is tapped */

    ///
    /// @brief      Build the compact action tile
    /// @details    Renders the action label and symbol as a plain, consistently sized button
    ///
    /// @return     (some View) rendered action tile
    ///
    var body: some View {

        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .tint(color)
        }
        .buttonStyle(.plain)
    }
}


// --------------------------------------- MARK: - Detail Row ----------------------------------- //

///
/// Displays one icon, label, and value row in the card metadata
///
/// @section    Purpose
///     Keep related card metadata visually aligned and easy to scan
///
struct DetailRow: View {

    let icon:  String   /* The icon representing the detail row     */
    let title: String   /* The title or label of the detail row     */
    let value: String   /* The value associated with the detail row */

    ///
    /// @brief      Build one metadata row
    /// @details    Aligns the supplied icon, title, and trailing value within the detail section
    ///
    /// @return     (some View) rendered metadata row
    ///
    var body: some View {

        HStack(spacing: 12) {

            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            Text(title)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.vertical, 5)
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
struct ChecklistBlock: View {

    let checklist: KanbanChecklist          /* The checklist data rendered by the block                                */
    let onDelete: ()        -> Void         /* The action invoked when the checklist is deleted                        */
    let onAddItem: ()       -> Void         /* The action invoked when a new item is added                             */
    let onToggleItem: (Int) -> Void         /* The action invoked when an item is toggled                              */
    let onUpdateItem: (Int, String) -> Void /* The action invoked when item text is edited                             */
    let onDeleteItem: (Int)  -> Void        /* The action invoked when an item is deleted                              */
    let onRename: (String)   -> Void        /* The action invoked when the checklist title is renamed                  */
    let onToggleAllItems: () -> Void        /* The action invoked when all items are toggled                           */
    let onMove: (ChecklistMoveDirection) -> Void /* The action invoked when the checklist is moved                     */
    let canMoveUp: Bool                     /* Whether the checklist can be moved up in the list                       */
    let canMoveDown: Bool                   /* Whether the checklist can be moved down in the list                     */
    let focusFirstItem: Bool                /* Whether the first item should be focused when the checklist is rendered */
    let onFirstItemFocused: () -> Void      /* The action invoked when the first item receives focus                   */

    @State private var isRenaming = false   /* Whether the checklist title is currently being renamed                  */
    @State private var titleDraft = ""      /* The draft text for the checklist title being edited                     */
    @State private var hideCompletedItems = false
    @State private var isCollapsed = false  /* Whether the checklist's items are currently collapsed from view         */

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
    private var allItemsAreCompleted: Bool {

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
    private var visibleItems: [(offset: Int, element: KanbanChecklistItem)] {  /* Filtered actions */

        /// Filter the checklist items based on the hideCompletedItems flag
        checklist.items.enumerated().filter { item in
            !hideCompletedItems || !checklist.completedItemIndices.contains(item.offset)
        }
    }

    ///
    /// @brief      Build the checklist group
    /// @details    Renders the group title, completed-item count, and checklist rows
    ///
    /// @return     (some View) rendered checklist group
    ///
    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            HStack {

                Text(checklist.title)
                    .font(.subheadline.weight(.semibold))
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.5) {
                        titleDraft = checklist.title
                        isRenaming = true
                    }
                    .accessibilityHint("Touch and hold to rename this checklist")

                Spacer()

                Text("\(checklist.completed)/\(checklist.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? "Expand checklist" : "Collapse checklist")

                Menu {
                    Toggle("Hide Completed", isOn: $hideCompletedItems)

                    Button {
                        onToggleAllItems()
                    } label: {
                        Label(allItemsAreCompleted ? "Uncheck All" : "Check All", systemImage: allItemsAreCompleted ? "square" : "checkmark.square")
                    }
                    .disabled(checklist.items.isEmpty)

                    Divider()

                    Button("Move to the Top", systemImage: "arrow.up.to.line") {
                        onMove(.top)
                    }
                    .disabled(!canMoveUp)

                    Button("Move Up", systemImage: "arrow.up") {
                        onMove(.up)
                    }
                    .disabled(!canMoveUp)

                    Button("Move Down", systemImage: "arrow.down") {
                        onMove(.down)
                    }
                    .disabled(!canMoveDown)

                    Button("Move to the Bottom", systemImage: "arrow.down.to.line") {
                        onMove(.bottom)
                    }
                    .disabled(!canMoveDown)

                    Divider()

                    Button {
                        titleDraft = checklist.title
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Checklist actions")
            }
            .padding(.bottom, 6)

            if !isCollapsed {

                ForEach(visibleItems, id: \.offset) { entry in

                    ChecklistItemRow(
                        item: entry.element.title,
                        isCompleted: checklist.completedItemIndices.contains(entry.offset),

                        onToggle: {
                            onToggleItem(entry.offset)
                        },

                        onUpdate: { text in
                            onUpdateItem(entry.offset, text)
                        },

                        onDelete: {
                            onDeleteItem(entry.offset)
                        },
                        shouldFocus: focusFirstItem && entry.offset == 0,
                        onFocusHandled: onFirstItemFocused
                    )
                }

                Button(action: onAddItem) {

                    Text("Add item...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .alert("Rename Checklist", isPresented: $isRenaming) {
            TextField("Checklist title", text: $titleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                onRename(titleDraft)
            }
            .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
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
struct ChecklistItemRow: View {

    let item: String                  /* The editable item text                                        */
    let isCompleted: Bool             /* The current completion state                                  */
    let onToggle: () -> Void          /* The action invoked by the checkbox                            */
    let onUpdate: (String) -> Void    /* The action invoked by text editing                            */
    let onDelete: () -> Void          /* The action invoked by delete                                  */
    let shouldFocus: Bool             /* Indicates whether the text field should receive focus         */
    let onFocusHandled: () -> Void    /* The action invoked when the text field focus has been handled */

    @State private var horizontalOffset: CGFloat = 0
    @FocusState private var isTextFocused: Bool


    var body: some View {

        ZStack(alignment: .trailing) {

            Button(role: .destructive, action: onDelete) {

                Image(systemName: "trash")
                    .foregroundStyle(.white)
                    .frame(width: 72)
                    .frame(maxHeight: .infinity)
                    .background(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete item")

            HStack(spacing: 10) {

                Button(action: onToggle) {

                    Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isCompleted ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCompleted ? "Mark item incomplete" : "Mark item complete")

                TextField("Item", text: Binding(
                    get: { item },
                    set: onUpdate
                ))
                .font(.subheadline)
                .focused($isTextFocused)
                .onAppear {
                    guard shouldFocus else { return }
                    DispatchQueue.main.async {
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
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }

                        horizontalOffset = min(0, max(-72, value.translation.width))
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }

                        withAnimation(.easeOut(duration: 0.2)) {
                            if value.translation.width < -120 {
                                onDelete()
                            } else {
                                horizontalOffset = value.translation.width < -36 ? -72 : 0
                            }
                        }
                    }
            )
        }
        .clipped()
    }
}


// --------------------------------------- MARK: - Activity ------------------------------------- //

///
/// Displays one activity event associated with the card
///
/// @section    Purpose
///     Render a compact activity entry with actor styling, event text, and timestamp
///
struct ActivityRow: View {

    let text: String       /* The main text content of the activity row */
    let actorColor: Color  /* The icon color for the activity actor      */
    let onDelete: () -> Void


    ///
    /// @brief      Build the activity event row
    /// @details    Places the activity text and timestamp beside the actor symbol
    ///
    /// @return     (some View) rendered activity row
    ///
    var body: some View {

        ActivitySwipeRow(onDelete: onDelete) {

            HStack(alignment: .top, spacing: 10) {

                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(actorColor)

                VStack(alignment: .leading, spacing: 3) {

                    Text(text)
                        .font(.subheadline)

                    Text("Today at 7:00 AM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}


/// Renders a posted card comment and its authoring time in the activity feed
struct CommentActivityRow: View {

    let comment: KanbanComment      /* The comment data rendered by the row           */
    let memberColor: Color          /* The assigned icon color for the comment author  */
    let onDelete: () -> Void        /* The action invoked when the comment is deleted */

    var body: some View {
        ActivitySwipeRow(onDelete: onDelete) {

            HStack(alignment: .top, spacing: 10) {

                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(memberColor)

                VStack(alignment: .leading, spacing: 3) {

                    (Text(comment.author).fontWeight(.semibold) + Text(" ") + Text(comment.body))
                        .font(.subheadline)

                    Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}


// -------------------------------------- MARK: - Previews -------------------------------------- //

///
/// Preview the card detail presentation with representative sample data
///
/// @section    Purpose
///     Provide a fast Xcode canvas preview for the complete detail flow
///
    struct ActivitySwipeRow<Content: View>: View {

        let onDelete: () -> Void                            /* The action invoked when the row is deleted     */
        let deletionAccessibilityLabel: String              /* Accessibility label for the swipe action       */
        @ViewBuilder let content: () -> Content             /* The content view rendered inside the swipe row */
        @State private var horizontalOffset: CGFloat = 0    /* The current horizontal offset of the swipe row */

        init(
            onDelete: @escaping () -> Void,
            deletionAccessibilityLabel: String = "Delete activity",
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.onDelete = onDelete
            self.deletionAccessibilityLabel = deletionAccessibilityLabel
            self.content = content
        }

        var body: some View {

            ZStack(alignment: .trailing) {

                Button(role: .destructive, action: onDelete) {

                    Image(systemName: "trash")
                        .foregroundStyle(.white)
                        .frame(width: 72)
                        .frame(maxHeight: .infinity)
                        .background(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(deletionAccessibilityLabel)

                content()
                    .padding(.vertical, 7)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background)
                    .offset(x: horizontalOffset)
                    .simultaneousGesture(

                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else {
                                    return
                                }
                                horizontalOffset = min(0, max(-72, value.translation.width))
                            }

                            .onEnded { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else {
                                    return
                                }
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if value.translation.width < -120 {
                                        onDelete()
                                    } else {
                                        horizontalOffset = value.translation.width < -36 ? -72 : 0
                                    }
                                }
                            }
                    )
            }
            .clipped()
        }
    }

    
// -------------------------------------- MARK: - Card Detail Preview --------------------------- //

    ///
    /// @fcn        CardDetailView.Preview
    /// @brief      Render a representative card detail screen in the Xcode canvas
    /// @details    Wraps the first deterministic sample card in a NavigationStack so navigation-dependent
    ///             presentation, including the detail navigation bar and sheets, has its required context
    ///
    /// @return     (some View) navigable card detail preview
    ///
    /// @pre        SampleData contains at least one list with one card
    /// @post       Preview rendering does not mutate the production board state
    ///
    #Preview {
    NavigationStack {
        CardDetailView(card: SampleData.lists[0].cards[0])
    }
}

