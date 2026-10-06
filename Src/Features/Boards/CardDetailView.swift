// -------------------------------------------------------------------------------------------------
// @file       CardDetailView.swift
// @brief      Detailed kanban card presentation and supporting components
// @details    Presents editable card text, completion, dates, labels, assignments, attachments,
//             checklist actions, and activity. Includes reduced Action Detail and member draft
//             editors, reusable section/row components, and custom swipe-to-delete interactions
//
// @last rev   10/05/26
//
// @notes      CardDetailView holds local working state and emits complete snapshots through the
//             optional onTitleToggle callback, which handles more than completion alone.
//             The caller owns Board persistence, movement, archival, deletion, and attachment-file pruning.
//             Confirmed deletion suppresses further snapshots before invoking onDelete and dismissing.
//             Member and Action Detail sheets use explicit Save/Cancel drafts; main card edits
//             synchronize as they occur. Generated activity is display copy, not a stored audit log
//
// @section    Opens
//     Consider extracting member/action editors and reusable checklist/activity rows into focused files
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

    /// Identifies the date field currently edited by the date picker
    ///
    /// @section    Purpose
    ///     Distinguish a card's start date from its due date
    ///
    private enum DateField: String, Identifiable, Equatable {

        case start      /* Start date field for the card */
        case due        /* Due date field for the card   */

        ///
        /// @fcn        CardDetailView.DateField.id
        /// @brief      Identify the date field being edited
        /// @details    Uses the raw enum value for stable date-sheet identity
        ///
        /// @return     (String) start or due field identity
        /// @post       Date state remains unchanged
        ///
        var id: String { rawValue } /* Stable date-field identity */

        ///
        /// @fcn        CardDetailView.DateField.title
        /// @brief      Resolve the date field's display label
        /// @details    Supplies the heading used by date rows and picker sheets
        ///
        /// @return     (String) Start date or Due date label
        /// @post       No date or presentation state changes
        ///
        var title: String { /* User-facing date-field label */
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
        case actionDetail(UUID, UUID)                /* Checklist and item IDs for reduced detail          */

        ///
        /// @fcn        CardDetailView.ActiveSheet.id
        /// @brief      Identify a card-detail modal and its associated destination
        /// @details    Combines the presentation kind with date, attachment, or checklist/item
        ///             identity where needed so distinct destinations remain distinguishable
        ///
        /// @return     (String) stable sheet-destination identity
        /// @post       No sheet is presented or dismissed by this lookup
        ///
        var id: String {                            /* Stable identity for the active sheet                */

            switch self {
                case .date(let field):                   "date-\(field.id)" /* Selected date field */
                case .members:                           "members"
                case .labels:                            "labels"
                case .attachmentSources:                 "attachment-sources"
                case .addLink:                           "add-link"
                case .attachmentPreview(let attachment): "attachment-\(attachment.id.uuidString)" /* Previewed attachment */
                case .actionDetail(let checklistID, let itemID): /* Owning checklist and action IDs */
                    "action-detail-\(checklistID.uuidString)-\(itemID.uuidString)"
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

        ///
        /// @fcn        CardDetailView.GeneratedActivity.id
        /// @brief      Identify a generated activity entry for dismissal
        /// @details    Uses the raw case value stored in the card's dismissed-activity set
        ///
        /// @return     (String) generated-entry identity
        /// @post       No activity dismissal is recorded
        ///
        var id: String { rawValue } /* Stable generated-activity identity */

        ///
        /// @fcn        CardDetailView.GeneratedActivity.text(for:actorName:)
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

        ///
        /// @fcn        CardDetailView.ActivityFilter.id
        /// @brief      Identify an activity display filter
        /// @details    Uses the enum raw value for picker identity
        ///
        /// @return     (String) stable filter identity
        /// @post       The selected filter remains unchanged
        ///
        var id: String { rawValue } /* Stable activity-filter identity */

        ///
        /// @fcn        CardDetailView.ActivityFilter.title
        /// @brief      Name the selected activity scope
        /// @details    Supplies readable labels for all entries, comments, or generated card activity
        ///
        /// @return     (String) filter display title
        /// @post       No activity records are filtered or modified by this lookup
        ///
        var title: String { /* User-facing activity-filter label */
            switch self {
            case .all:          "All Activity"
            case .comments:     "Comments"
            case .cardActivity: "Card Activity"
            }
        }
    }


    /// Identifies which editable card field currently has focus
    ///
    /// @section    Purpose
    ///     Keep text-field focus state explicit across title, subtitle, description, and comment entry
    ///
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
    @Binding var savedCardIDs: Set<Int>                       /* Local identities saved for quick access                       */
    let onTitleToggle: ((KanbanCard) -> Void)?               /* Callback invoked when the card title checkbox is toggled     */
    let onMoveToList: ((Int) -> Void)?                       /* Callback invoked to move the card to a selected list         */
    /// Optional callback that archives the latest synchronized card snapshot.
    let onArchive: (() -> Void)?
    /// Optional callback permanently deleting this card and its caller-owned content.
    let onDelete: (() -> Bool)? /* Save-first removal; false keeps the editor and drafts open */

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
    @State private var members: [CardAssignee]               /* Registered and manual card assignments                       */
    @State private var selectedLabelIDs: [String]            /* Stable IDs of labels assigned to this card                   */
    @State private var attachments: [KanbanAttachment]       /* Photo attachments currently assigned to the card             */
    @State private var coverAttachmentID: UUID? /* Explicit cover selection; nil means disabled */
    @State private var selectedCoverPhoto: PhotosPickerItem? /* One photo explicitly selected for a cover */
    @State private var coverImportID: UUID? /* Superseded requests cannot enable an old cover */
    @State private var showsCoverPicker = false /* Visual chooser for already attached photos */
    @State private var showsCoverLibrary = false /* Offline category-based illustration chooser */
    @State private var selectedPhotoItems: [PhotosPickerItem] = [] /* Photos selected from the system photo library          */
    @State private var commentDraft = ""                     /* Text currently entered in the comment composer               */
    @State private var dismissedActivityIDs: Set<String>     /* IDs of activity entries that have been dismissed by the user */
    @State private var activityFilter: ActivityFilter = .all /* The currently selected activity filter for the card          */
    @State private var showingAttachmentNotice = false       /* Whether an attachment notice is presented                    */
    @State private var attachmentNoticeMessage = ""          /* Explanation shown for failed or unavailable sources          */
    @State private var showingDeleteConfirmation = false     /* Whether permanent card deletion awaits confirmation          */
    @State private var hasDeletedCard = false                /* Prevents stale snapshots after confirmed deletion            */


    ///
    /// @fcn        CardDetailView.linkedCardsByID
    /// @brief      Index cards available as checklist-link destinations
    /// @details    Flattens other Board lists into a stable-ID lookup used by linked checklist rows
    ///
    /// @return     ([Int: KanbanCard]) available cards keyed by stable card ID
    ///
    /// @pre        Cards across availableLists have unique IDs; duplicate keys are not accepted
    /// @post       No Board or card state is modified
    ///
    private var linkedCardsByID: [Int: KanbanCard] {   /* Linked cards by ID */
        Dictionary(uniqueKeysWithValues: availableLists.flatMap(\.cards).map { ($0.id, $0) })
    }


    ///
    /// @fcn        CardDetailView.init
    /// @brief      Initialize the card detail state
    /// @details    Seeds all working fields from the supplied card, including stored checklists,
    ///             assignments, attachments, and dismissed activity IDs
    ///
    /// @param[in]  card           Complete card snapshot being edited
    /// @param[in]  labelLibrary   Shared reusable label catalog binding
    /// @param[in]  availableLists Other active lists used for movement and linked-card lookup
    /// @param[in]  memberColors   Icon colors keyed by normalized display name
    /// @param[in]  currentUserName Actor name used by generated activity and Action Detail comments
    /// @param[in]  savedCardIDs   Binding to this Board's device-local bookmarks
    /// @param[in]  onTitleToggle  Optional callback receiving every complete edited card snapshot
    /// @param[in]  onMoveToList   Optional callback receiving a destination list ID
    /// @param[in]  onArchive      Optional callback archiving the latest synchronized card
    /// @param[in]  onDelete       Optional save-first deletion callback; false retains the editor and drafts
    ///
    /// @return     (CardDetailView) configured card detail presentation
    /// @post       Initialization does not submit edits or mutate caller-owned bindings
    /// @note       Without onTitleToggle, main-card edits remain local to this detail instance
    ///
    init(
        card: KanbanCard,
        labelLibrary: Binding<LabelLibrary> = .constant(.starter),
        availableLists: [KanbanList]           = [],        /* Other lists available as move destinations                   */
        memberColors: [String: Color]          = [:],       /* Shared member icon colors                                    */
        currentUserName: String                = "Justin Reina",
        savedCardIDs: Binding<Set<Int>>        = .constant([]),
        onTitleToggle: ((KanbanCard) -> Void)? = nil,       /* Callback invoked when the card title checkbox is toggled     */
        onMoveToList: ((Int) -> Void)?         = nil,       /* Callback invoked when the card is moved                      */
        onArchive: (() -> Void)? = nil,
        onDelete: (() -> Bool)? = nil
    ) {

        self.card           = card                                              /* The kanban card being displayed in detail                            */
        self._labelLibrary  = labelLibrary                                      /* Shared catalog used by all card label assignments                    */
        self.availableLists = availableLists                                    /* Other lists available as move destinations                           */
        self.memberColors   = memberColors                                      /* Shared member icon colors                                            */
        self.currentUserName = currentUserName                                  /* Current actor name shown in card activity                            */
        self._savedCardIDs  = savedCardIDs                                      /* Local saved-card identities                                        */
        self.onTitleToggle  = onTitleToggle                                     /* Callback invoked when the card title checkbox is toggled             */
        self.onMoveToList   = onMoveToList                                      /* Callback invoked when the card is moved                              */
        self.onArchive = onArchive
        self.onDelete = onDelete

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
        _coverAttachmentID    = State(initialValue: card.coverAttachmentID)
        _dismissedActivityIDs = State(initialValue: card.dismissedActivityIDs)  /* Initialize dismissed activity IDs from the card state                */

        _checklists = State(initialValue: card.checklists)                      /* Initialize checklist state from the card's stored values             */
    }


    ///
    /// @fcn        CardDetailView.memberIconColor(for:)
    /// @brief      Resolve the display color assigned to a member name
    /// @details    Trims surrounding whitespace and lowercases the name before dictionary lookup
    ///
    /// @param[in]  memberName Display name whose normalized color key is queried
    ///
    /// @return     (Color) assigned member color or the system accent color
    /// @post       Member assignments and shared colors remain unchanged
    ///
    private func memberIconColor(for memberName: String) -> Color {

        let normalizedName = memberName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() /* Member-color lookup key */

        return memberColors[normalizedName] ?? .accentColor
    }


    ///
    /// @fcn        CardDetailView.coverControls
    /// @brief      Offer explicit photo selection, replacement, and non-destructive cover removal
    /// @details    Photo-library selection attaches one new photo; existing photos reuse their IDs.
    ///             Removing a cover preserves all attachments and never auto-selects another image
    /// @return     (some View) visible cover controls and optional preview
    ///
    private var coverControls: some View {
        DetailSection(title: "Card Cover") {
            Button("Browse Cover Library", systemImage: "photo.on.rectangle.angled") {
                showsCoverLibrary = true
            }
            .frame(minHeight: 44)
            if let cover = attachments.first(where: { $0.id == coverAttachmentID && $0.kind == .photo }) {
                CardCoverPreview(attachment: cover)
            }
            Button(coverAttachmentID == nil ? "Choose Attached Photo" : "Change Cover", systemImage: "photo") {
                showsCoverPicker = true
            }
            .disabled(!attachments.contains { $0.kind == .photo })
            .frame(minHeight: 44)

            PhotosPicker(selection: $selectedCoverPhoto, matching: .images) {
                Label("Add Photo as Cover", systemImage: "photo.badge.plus")
                    .frame(minHeight: 44)
            }

            if coverAttachmentID != nil || coverImportID != nil {
                Button("Remove Cover", systemImage: "photo.badge.minus") {
                    setCover(nil)
                }
                .frame(minHeight: 44)
                .accessibilityHint("Keeps the photo attached to this card.")
            }
            Text("Covers are optional. Removing a cover keeps its photo attached. Choose an attached photo here or use Set as Cover on a photo's menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: selectedCoverPhoto) { _, photoItem in
            guard let photoItem else { return }
            let requestID = UUID()
            coverImportID = requestID
            Task { await importPhotos(from: [photoItem], coverRequestID: requestID) }
        }
        .sheet(isPresented: $showsCoverPicker) {
            CardCoverPicker(
                photos: attachments.filter { $0.kind == .photo },
                selectedID: coverAttachmentID,
                onSelect: { setCover($0) }
            )
        }
        .sheet(isPresented: $showsCoverLibrary) {
            CardCoverLibrary(
                selectedImage: attachments.first { $0.id == coverAttachmentID }?.exampleImage,
                onSelect: useLibraryCover
            )
        }
    }

    ///
    /// @fcn        CardDetailView.setCover(_:)
    /// @brief      Validate and synchronize an explicit cover choice
    /// @details    Uses current attachment drafts and reports invalid selection without replacing the cover
    /// @param[in]  id  Attached photo identity, or nil to remove the cover
    ///
    private func setCover(_ id: UUID?) {
        var updated = card
        updated.attachments = attachments
        do {
            try updated.setCover(id)
            coverImportID = nil
            selectedCoverPhoto = nil
            coverAttachmentID = updated.coverAttachmentID
            syncCardState()
        } catch {
            DatabaseActivity.shared.report("Could not set this cover: \(error.localizedDescription) Choose an attached photo.")
        }
    }

    ///
    /// @fcn        CardDetailView.useLibraryCover(_:)
    /// @brief      Publish a library selection while preserving all working card content
    /// @details    Reuses attachment identities and cancels superseded cover photo imports
    /// @param[in]  image  Explicit illustration choice
    /// @return     (Bool) whether selection succeeded; errors are shown through standard feedback
    ///
    private func useLibraryCover(_ image: ExampleCoverImage) -> Bool {
        guard !hasDeletedCard else { return false }
        var updated = card
        updated.attachments = attachments
        do {
            try updated.useLibraryCover(image)
            attachments = updated.attachments ?? []
            coverAttachmentID = updated.coverAttachmentID
            coverImportID = nil
            selectedCoverPhoto = nil
            syncCardState()
            return true
        } catch {
            DatabaseActivity.shared.report("Could not select this cover: \(error.localizedDescription)")
            return false
        }
    }

    ///
    /// @fcn        CardDetailView.attachmentContent(for:)
    /// @brief      Build the tap behavior for one card attachment
    /// @details    Opens remote links directly and presents local media in the attachment viewer
    ///
    /// @param[in]  attachment  Attachment metadata shown in the card gallery
    ///
    /// @return     (some View) link or local attachment-preview button
    ///
    @ViewBuilder
    private func attachmentContent(for attachment: KanbanAttachment) -> some View {

        if let url = attachment.url { /* Remote link target */

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


    ///
    /// @fcn        CardDetailView.attachmentGalleryItem(_:)
    /// @brief      Add cover and removal actions to one attachment thumbnail
    /// @details    Only photos can become covers; accessibility actions mirror the contextual menu
    /// @param[in]  attachment  Current attachment metadata
    /// @return     (some View) interactive gallery item
    ///
    private func attachmentGalleryItem(_ attachment: KanbanAttachment) -> some View {
        attachmentContent(for: attachment)
            .contextMenu {
                if attachment.kind == .photo {
                    Button(coverAttachmentID == attachment.id ? "Remove Cover" : "Set as Cover") {
                        setCover(coverAttachmentID == attachment.id ? nil : attachment.id)
                    }
                }
                Button("Remove attachment", systemImage: "trash", role: .destructive) {
                    removeAttachment(attachment)
                }
            }
            .accessibilityLabel(attachment.url == nil ? "View attached media" : "Open attached link")
            .accessibilityActions {
                if attachment.kind == .photo {
                    Button(coverAttachmentID == attachment.id ? "Remove Cover" : "Set as Cover") {
                        setCover(coverAttachmentID == attachment.id ? nil : attachment.id)
                    }
                }
                Button("Remove attachment") { removeAttachment(attachment) }
            }
    }

    ///
    /// @fcn        CardDetailView.attachmentGallery
    /// @brief      Present current attachments with per-photo cover controls
    /// @details    Keeps the gallery's view-builder expression separate from the full card editor
    /// @return     (some View) adaptive attachment grid
    ///
    private var attachmentGallery: some View {
        DetailSection(title: "Attachments") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(attachments) { attachment in
                    attachmentGalleryItem(attachment)
                }
            }
        }
    }

    ///
    /// @fcn        CardDetailView.selectedLabels
    /// @brief      Resolve assigned label IDs into display definitions
    /// @details    Preserves selection order and omits identities missing from the shared catalog
    ///
    /// @return     ([KanbanLabel]) resolved label definitions
    /// @post       Missing definitions do not remove IDs from the card's selection
    ///
    private var selectedLabels: [KanbanLabel] { /* Resolved selected label definitions */
        selectedLabelIDs.compactMap { labelID in
            labelLibrary.labels.first(where: { $0.id == labelID })
        }
    }


    ///
    /// @fcn        CardDetailView.importPhotos(from:)
    /// @brief      Import selected photo-library items as card attachments
    /// @details    Loads each selected photo or video, stores successful transfers in the app container,
    ///             synchronizes the attachment metadata to the card, and reports partial failures
    ///
    /// @param[in]  photoItems  PhotosPicker items selected for the current card
    /// @param[in]  coverRequestID  Explicit cover import identity; nil means ordinary attachment import
    ///
    /// @return     (Void) updates the card with successfully imported photo and video attachments
    ///
    /// @pre        photoItems were selected from the PhotosPicker for this card
    /// @post       The selection is cleared; saved attachment records are synchronized to board state
    ///
    /// @note       Successful imports are retained even if another selected item fails to load or save
    ///
    @MainActor
    private func importPhotos(from photoItems: [PhotosPickerItem], coverRequestID: UUID? = nil) async {

        guard !hasDeletedCard else { return }
        if let coverRequestID, coverImportID != coverRequestID { return }

        var importFailed = false /* Whether any selected media failed to import */

        for photoItem in photoItems { /* Selected Photos-library item */
            
            do {
                guard let mediaData = try await photoItem.loadTransferable(type: Data.self) else { /* Transferred media bytes */
                    importFailed = true
                    continue
                }
                guard !hasDeletedCard else { return }
                if let coverRequestID, coverImportID != coverRequestID { return }

                let contentType = photoItem.supportedContentTypes.first /* Preferred selected-media type */
                let isVideo = photoItem.supportedContentTypes.contains { /* Whether the selection is video media */
                    $0.conforms(to: .movie) || $0.conforms(to: .video)
                }
                let mediaKind: KanbanAttachmentKind = isVideo ? .video : .photo /* Stored media category */
                let fileExtension = contentType?.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg") /* File type used for local storage */

                let attachment = try CardAttachmentStore.saveMedia(mediaData, kind: mediaKind, fileExtension: fileExtension)
                attachments.append(attachment)
                if coverRequestID != nil && mediaKind == .photo { coverAttachmentID = attachment.id }
            } catch {
                importFailed = true
            }
        }

        if let coverRequestID, coverImportID != coverRequestID { return }
        if coverRequestID != nil {
            coverImportID = nil
            selectedCoverPhoto = nil
        } else {
            selectedPhotoItems = []
            activeSheet = nil
        }

        syncCardState(attachments: attachments)

        if importFailed {
            attachmentNoticeMessage = "One or more selected photos or videos could not be added. Please try again."
            showingAttachmentNotice = true
        }
    }


    ///
    /// @fcn        CardDetailView.addWebLink(_:)
    /// @brief      Add a validated web URL to the card's attachment list
    /// @details    Appends link metadata, closes the active sheet, and emits the complete card snapshot
    ///
    /// @param[in]  url Web address selected for attachment
    ///
    /// @return     (Void) updates local detail state and synchronizes the card
    /// @pre        The caller has validated the URL as an acceptable web link
    /// @post       No remote content is downloaded or local media file created by this helper
    ///
    private func addWebLink(_ url: URL) {
        attachments.append(KanbanAttachment(url: url, mediaKind: .link))
        activeSheet = nil
        syncCardState(attachments: attachments)
    }


    ///
    /// @fcn        CardDetailView.addClipboardLink()
    /// @brief      Read and add a web address from the system clipboard
    /// @details    Prefers a clipboard URL over string content and validates with the attachment-store helper
    ///
    /// @return     (Void) adds a valid link or presents an invalid-link notice
    /// @post       Invalid input closes the source sheet and shows a notice without adding an attachment
    ///
    private func addClipboardLink() {
        
        let clipboardText = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? "" /* Candidate clipboard link */

        guard let url = CardAttachmentStore.webURL(from: clipboardText) else { /* Parsed clipboard URL */
            
            attachmentNoticeMessage = "The clipboard does not contain a valid web link."
            showingAttachmentNotice = true
            activeSheet             = nil
            
            return
        }

        addWebLink(url)
    }


    ///
    /// @fcn        CardDetailView.showAttachmentSourceComingSoon(_:)
    /// @brief      Explain an attachment source that is not yet supported
    /// @details    Names the selected source in a notice and closes the source-selection sheet
    ///
    /// @param[in]  source Display name of the unavailable attachment source
    ///
    /// @return     (Void) updates the notice and dismisses the source sheet
    /// @post       Card attachments and files remain unchanged
    ///
    private func showAttachmentSourceComingSoon(_ source: String) {
        
        attachmentNoticeMessage = "\(source) attachments are coming soon."
        showingAttachmentNotice = true
        activeSheet             = nil
    }


    ///
    /// @fcn        CardDetailView.removeAttachment(_:)
    /// @brief      Remove an attachment record from the current card
    /// @details    Deletes the attachment record from local detail state and synchronizes the updated card;
    ///             attachment-file pruning depends on the parent Board's update callback
    ///
    /// @param[in]  attachment  Photo, video, or link attachment selected for removal
    ///
    /// @return     (Void) updates the card's attachment collection and persistence state
    ///
    /// @pre        attachment identifies an item in the current card's attachment collection
    /// @post       Matching attachment IDs are absent locally; this helper does not delete stored files directly
    ///
    private func removeAttachment(_ attachment: KanbanAttachment) {
        let removesCover = coverAttachmentID == attachment.id
        var updated = card
        updated.attachments = attachments
        updated.coverAttachmentID = coverAttachmentID
        updated.removeAttachment(attachment.id)
        attachments = updated.attachments ?? []
        coverAttachmentID = updated.coverAttachmentID
        if removesCover {
            coverImportID = nil
            selectedCoverPhoto = nil
        }
        syncCardState(attachments: attachments)
    }


    ///
    /// @fcn        CardDetailView.syncCardState
    /// @brief      Push the current card state back to the parent board
    /// @details    Combines explicit overrides with working text, checklists, comments, assignments,
    ///             labels, attachments, dates, and activity dismissal state. Preserves card identity
    ///             and original list/divider metadata while emitting through onTitleToggle
    ///
    /// @param[in]  title          Optional title override; nil uses current titleText
    /// @param[in]  subtitle       Optional subtitle override; nil resolves current/default subtitle state
    /// @param[in]  members        Optional assignment override; nil uses local members
    /// @param[in]  labelIDs       Optional label-ID override; nil uses local selection
    /// @param[in]  attachments    Optional attachment override; nil uses local records
    /// @param[in]  titleChecked   Optional updated checked state for the card title
    /// @param[in]  startDate      Optional updated start date for the card
    /// @param[in]  dueDate        Optional updated due date for the card
    /// @param[in]  clearStartDate Whether to remove the card's start date
    /// @param[in]  clearDueDate   Whether to remove the card's due date
    ///
    /// @return     (Void) invokes the optional snapshot callback
    /// @post       Explicit overrides do not modify local State; nil callbacks perform no parent update.
    ///             Confirmed deletion suppresses all snapshots, including dismissal and delayed edits
    /// @note       Date removal requires the corresponding clear flag; nil dates retain working values.
    ///             The unchanged generated subtitle remains nil when no original override existed
    ///
    private func syncCardState(
        title:          String?             = nil,          /* Updated card title               */
        subtitle:       String?             = nil,          /* Updated card subtitle            */
        members:        [CardAssignee]?     = nil,          /* Updated card assignees           */
        labelIDs:       [String]?           = nil,          /* Updated card label IDs           */
        attachments:    [KanbanAttachment]? = nil,          /* Updated card attachments         */
        titleChecked:   Bool?               = nil,          /* Updated card title checked state */
        startDate:      Date?               = nil,          /* Updated card start date          */
        dueDate:        Date?               = nil,          /* Updated card due date            */
        clearStartDate: Bool                = false,        /* Whether to clear the start date  */
        clearDueDate:   Bool                = false         /* Whether to clear the due date    */
    ) {

        guard !hasDeletedCard else { return }

        let nextTitleChecked = titleChecked   ?? self.titleChecked /* Effective checked state */
        let nextTitle         = title         ?? titleText /* Effective card title */
        let nextSubtitle      = subtitle      ?? (card.subtitleOverride == nil && subtitleText == card.subtitle ? nil : subtitleText) /* Effective subtitle override */
        let nextMembers       = members       ?? self.members /* Effective assignees */
        let nextLabelIDs      = labelIDs      ?? selectedLabelIDs /* Effective label IDs */
        let nextAttachments   = attachments   ?? self.attachments /* Effective attachment metadata */
        let nextStartDate     = clearStartDate ? nil : (startDate ?? self.startDate) /* Effective start date */
        let nextDueDate       = clearDueDate   ? nil : (dueDate   ?? self.dueDate) /* Effective due date */

        let updatedCard = KanbanCard( /* Complete card snapshot sent to the parent */
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
            coverAttachmentID:    coverAttachmentID,
            dismissedActivityIDs: dismissedActivityIDs,
            descriptionOverride:  descriptionText,
            subtitleOverride:     nextSubtitle
        )

        onTitleToggle?(updatedCard)
    }


    ///
    /// @fcn        CardDetailView.deleteCard()
    /// @brief      Permanently delete the card after explicit confirmation
    /// @details    Blocks snapshot synchronization before clearing focus or invoking the caller,
    ///             so dismissal and delayed editor callbacks cannot recreate the deleted card
    ///
    /// @return     (Void) dismisses after successful deletion; failed saves retain the editor and drafts
    /// @pre        The user confirmed permanent deletion; onDelete owns persistence and file pruning
    /// @post       Further onTitleToggle synchronization is disabled for this detail instance.
    ///             Missing callbacks and repeated successful deletion requests have no effect
    ///
    private func deleteCard() {
        guard let onDelete, !hasDeletedCard else { return }

        hasDeletedCard = true
        guard onDelete() else {
            hasDeletedCard = false
            return
        }
        focusedField = nil
        dismiss()
    }


    ///
    /// @fcn        CardDetailView.toggleCardTitle()
    /// @brief      Toggle the checked state of the card's title
    /// @details    Flips the boolean value representing whether the card's main title checkbox is
    ///             selected and synchronizes this change with the parent board
    ///
    /// @return     (Void) flips local completion and emits the new snapshot
    /// @post       Other working card fields are preserved
    ///
    private func toggleCardTitle() {

        let nextChecked = !titleChecked /* Inverted title completion state */
        titleChecked    = nextChecked

        syncCardState(titleChecked: nextChecked)
    }


    ///
    /// @fcn        CardDetailView.toggleSavedCard()
    /// @brief      Toggle the card's device-local bookmark membership
    /// @details    Inserts or removes the stable card ID in the caller-supplied bookmark binding
    ///
    /// @return     (Void) updates savedCardIDs
    /// @post       Card content is unchanged; bookmark persistence belongs to the binding owner
    ///
    private func toggleSavedCard() {

        if savedCardIDs.contains(card.id) {
            savedCardIDs.remove(card.id)
        } else {
            savedCardIDs.insert(card.id)
        }
    }
    

    ///
    /// @fcn        CardDetailView.postComment()
    /// @brief      Post a comment to the current card
    /// @details    Ignores empty drafts, appends a timestamped comment, and syncs it to the board
    ///
    /// @return     (Void) appends a trimmed comment and clears a nonblank draft
    /// @post       Blank input leaves state unchanged; the optional callback receives the updated card
    /// @note       This main-card composer currently uses the fixed Justin Reina author name,
    ///             rather than currentUserName used by generated activity and Action Detail comments
    ///
    private func postComment() {

        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized comment draft */

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
    /// @post       Matching comments are absent locally; persistence after reopening requires the
    ///             parent callback to store the submitted snapshot
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
    /// @post       The entry is hidden locally; persistence after reopening depends on the parent callback
    ///
    private func dismissGeneratedActivity(_ activity: GeneratedActivity) {
        dismissedActivityIDs.insert(activity.id)
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.resetDate(for:)
    /// @brief      Reset the selected card date to its unset value
    /// @details    Clears only the requested date, synchronizes the card, and closes the calendar sheet
    ///
    /// @param[in]  field  The date field to reset
    /// @return     (Void) clears local date state and submits its explicit clear flag
    /// @post       The other date is preserved and the active sheet is closed
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
    /// @fcn        CardDetailView.dateBinding(for:)
    /// @brief      Create a binding for the selected card date
    /// @details    Updates the local date and parent card state, then dismisses the calendar sheet
    ///
    /// @param[in]  field  The card date field being edited
    ///
    /// @return     (Binding<Date>) binding that updates and dismisses on selection
    /// @post       Constructing the binding does not write; an unset getter returns the current time.
    ///             Setter writes local date state, submits it, and closes the active sheet
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


    ///
    /// @fcn        CardDetailView.moveCardMenu(label:)
    /// @brief      Build the shared active-list destination menu
    /// @details    Lists supplied destinations and disables the menu when none exist.
    ///             Selection invokes the optional move callback before dismissing detail
    ///
    /// @param[in]  label  View builder providing the menu's visible control
    /// @return     (some View) destination-list menu
    /// @pre        availableLists contains appropriate destinations other than the current list
    /// @post       Construction does not move a card; selection dismisses even with no move callback
    ///
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

        let currentDate = field == .start ? startDate : dueDate /* Date currently stored for the selected field */
        let iconName    = field == .start ? "calendar" : "calendar.badge.clock" /* Symbol for this date field */

        let dateLabel = currentDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Add date" /* Button label */
        let fieldName = field.title.lowercased() /* Accessibility label value */

        let row = HStack(alignment: .center) { /* Shared date-row presentation */

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
    /// @fcn        CardDetailView.addChecklist(using:)
    /// @brief      Append a new empty checklist to the selected card's detail state
    /// @details    Adds a default checklist with its first item, syncs it to the card, scrolls it
    ///             into view, and focuses the item
    ///
    /// @param[in]  scrollProxy  Proxy used to scroll the new checklist into view
    /// @return     (Void) appends and synchronizes a checklist, then schedules scrolling
    ///
    /// @post       The new checklist's first item is visible and ready for editing
    ///
    private func addChecklist(using scrollProxy: ScrollViewProxy) {

        let checklist = KanbanChecklist(title: "Checklist", items: [""]) /* New checklist with an initial item */

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
    /// @fcn        CardDetailView.deleteChecklist(with:)
    /// @brief      Remove a checklist from the selected card's detail state
    /// @details    Filters the checklist collection by its stable identifier
    ///
    /// @param[in]  checklistID  Identifier of the checklist to remove
    /// @return     (Void) removes matching checklists and emits the current card snapshot
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
        
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { return } /* Checklist position */
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized checklist title */
        
        guard !trimmedTitle.isEmpty else { return }

        let checklist = checklists[checklistIndex] /* Current checklist snapshot */

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
    /// @details    Clears completion for a nonempty checklist whose every item is checked;
    ///             otherwise checks every item, including blank-title actions
    ///
    /// @param[in]  checklistID  Stable identifier of the checklist to update
    ///
    /// @return     (Void) updates item completion state and synchronizes the card
    ///
    /// @pre        checklistID identifies a checklist on the current card
    /// @post       All items are checked, or all are unchecked when they were already all checked
    ///
    private func toggleAllItems(in checklistID: UUID) {

        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { return } /* Checklist position */

        let checklist            = checklists[checklistIndex]                                                                   /* Current checklist snapshot       */
        let allItemsAreCompleted = !checklist.items.isEmpty && checklist.completedItemIndices.count == checklist.items.count    /* Whether all items are complete    */
        let completedIndices     = allItemsAreCompleted ? Set<Int>() : Set(checklist.items.indices)                             /* Completion indices after toggle   */

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
        guard let sourceIndex = checklists.firstIndex(where: { $0.id == checklistID }), /* Current checklist position */
              checklists.count > 1 else {
            return
        }

        let destinationIndex: Int /* Position resolved from the requested direction */

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

        let movedChecklist = checklists.remove(at: sourceIndex) /* Checklist temporarily removed for reinsertion */

        checklists.insert(movedChecklist, at: destinationIndex)

        syncCardState()
    }

    
    ///
    /// @fcn        CardDetailView.addItem(to:)
    /// @brief      Append a new item to a checklist
    /// @details    Appends a standard Item N action while preserving existing typed action records
    ///
    /// @param[in]  checklistID  Identifier of the checklist receiving the new item
    /// @return     (Void) updates the matching checklist and submits the card snapshot
    ///
    /// @post       The new item appears above the checklist's Add item... control
    ///
    private func addItem(to checklistID: UUID) {

        // Find the index of the checklist to which the new item will be added
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { /* Target checklist position */
            return
        }

        let checklist = checklists[checklistIndex] /* Current checklist snapshot */
        let itemNumber = checklist.items.count + 1 /* User-facing number for the next item */

        checklists[checklistIndex] = KanbanChecklist(
            id:    checklist.id,
            title: checklist.title,
            items: checklist.items + [KanbanChecklistItem(title: "Item \(itemNumber)")]
        )
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.toggleItem(in:at:)
    /// @brief      Toggle one checklist item's completion state
    /// @details    Replaces the matching value-type checklist with updated completed item indices
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being toggled
    /// @return     (Void) replaces completion state and emits the updated card snapshot
    /// @pre        The caller supplies a valid current itemIndex; only checklist existence is guarded here
    ///
    /// @post       The selected item changes between complete and incomplete
    ///
    private func toggleItem(in checklistID: UUID, at itemIndex: Int) {

        // Find the index of the checklist being updated
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { /* Checklist being toggled */
            return
        }

        let checklist = checklists[checklistIndex]                  /* Checklist being updated */
        var completedItemIndices = checklist.completedItemIndices   /* Mutable set of completed item indices */

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
    /// @fcn        CardDetailView.updateItem(in:at:with:)
    /// @brief      Update one checklist item's text
    /// @details    Replaces the matching value-type checklist with an updated item label
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being edited
    /// @param[in]  text         New display text for the item
    /// @return     (Void) updates the item title and submits the card snapshot
    /// @note       Missing checklists or out-of-range indices leave state unchanged; text is not trimmed
    ///
    /// @post       The edited text is displayed in the checklist row
    ///
    private func updateItem(in checklistID: UUID, at itemIndex: Int, with text: String) {
        
        // Find the index of the checklist being updated
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { /* Checklist being edited */
            return
        }

        // Retrieve the checklist being updated
        let checklist = checklists[checklistIndex] /* Checklist being edited */

        // Ensure the item index is within the bounds of the checklist's items array
        guard checklist.items.indices.contains(itemIndex) else {
            return
        }

        var items = checklist.items       /* Mutable checklist actions */
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
    /// @fcn        CardDetailView.deleteItem(in:at:)
    /// @brief      Delete one checklist item
    /// @details    Removes the item and shifts completed item indices that follow it
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being deleted
    /// @return     (Void) removes the record and submits the card snapshot
    /// @note       Missing checklists or out-of-range indices leave state unchanged
    ///
    /// @post       The selected item is removed from the checklist
    ///
    private func deleteItem(in checklistID: UUID, at itemIndex: Int) {

        // Find the index of the checklist being updated
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { /* Checklist being edited */
            return
        }

        // Retrieve the checklist being updated
        let checklist = checklists[checklistIndex] /* Checklist before item removal */

        // Ensure the item index is within the bounds of the checklist's items array
        guard checklist.items.indices.contains(itemIndex) else {
            return
        }

        var items = checklist.items     /* Mutable checklist actions */
        items.remove(at: itemIndex)     /* Remove the specified item from the checklist    */

        // Recalculate the set of completed item indices after the deletion
        let completedItemIndices: Set<Int> = Set( /* Completion indices adjusted for removal */

            checklist.completedItemIndices.compactMap { (index: Int) -> Int? in /* Previous completion position */

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
    /// @fcn        CardDetailView.updateActionDetail(checklistID:itemID:detail:)
    /// @brief      Save reduced detail content into its owning checklist action
    /// @details    Replaces only the selected item's content while preserving checklist and item identity
    ///
    /// @param[in]  checklistID  Stable identity of the containing checklist
    /// @param[in]  itemID       Stable identity of the owning checklist action
    /// @param[in]  detail       Updated reduced detail content
    ///
    /// @return     (Void) updates checklist state and synchronizes the parent card
    ///
    /// @pre        checklistID and itemID identify an Action Detail item on the current card
    /// @post       The parent card contains the updated Action Detail when both IDs resolve
    ///
    private func updateActionDetail(checklistID: UUID, itemID: UUID, detail: KanbanChecklistActionDetail) {

        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { return } /* Target checklist position */

        let checklist = checklists[checklistIndex] /* Owning checklist */

        guard let itemIndex = checklist.items.firstIndex(where: { $0.id == itemID }) else { return } /* Target action position */

        var items = checklist.items /* Mutable checklist actions */
        items[itemIndex].content = .actionDetail(detail)

        checklists[checklistIndex] = KanbanChecklist(
            id:    checklist.id,
            title: checklist.title,
            items: items
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

        let checklistIndex = checklists.firstIndex(where: { $0.id == checklist.id }) ?? 0 /* Current checklist position */

        ChecklistBlock(
            checklist: checklist,
            linkedCardsByID: linkedCardsByID,
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
            onOpenActionDetail: { itemID in
                activeSheet = .actionDetail(checklist.id, itemID)
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
    /// @fcn        CardDetailView.body
    /// @brief      Build the card detail presentation
    /// @details    Composes inline text editing, completion, dates, attachments, labels, members,
    ///             typed checklist actions, activity filtering, and comments. Coordinates all editors,
    ///             media import/preview, bookmark toggling, movement, and optional card archival/deletion
    ///
    /// @return     (some View) rendered card detail screen
    /// @post       Main edits emit complete snapshots as they occur; archive emits the latest snapshot
    ///             before invoking onArchive and dismissing. Confirmed deletion invokes onDelete
    ///             and dismisses without further snapshots. Attachment failures show a notice
    /// @note       Dividers display a minimal surface without task actions. Label/catalog persistence
    ///             and Board updates belong to the caller; closing does not revert prior submitted edits
    ///
    var body: some View { /* Full card-detail presentation */

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

                    if !card.isSectionDivider {
                        coverControls
                    }

                    if !attachments.isEmpty {
                        attachmentGallery
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
                                                .foregroundStyle(memberIconColor(for: member.displayName))
                                        }
                                    }
                                    .frame(minWidth: 22, alignment: .leading)
                                }

                                Text("Members")

                                Spacer()

                                Text(members.isEmpty ? "Add members" : members.map(\.displayName).joined(separator: ", "))
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
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray5), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                if !card.isSectionDivider {

                    Button(action: toggleSavedCard) {
                        Image(systemName: savedCardIDs.contains(card.id) ? "bookmark.fill" : "bookmark")
                            .font(.title2)
                            .foregroundStyle(savedCardIDs.contains(card.id) ? .orange : .primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(savedCardIDs.contains(card.id) ? "Remove from Saved" : "Save card")

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
                        if let onArchive, !card.isSectionDivider {
                            Button {
                                syncCardState()
                                onArchive()
                                dismiss()
                            } label: {
                                Label("Archive Card", systemImage: "archivebox")
                            }
                        }
                        if onDelete != nil, !card.isSectionDivider {
                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete Card", systemImage: "trash")
                            }
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
                if card.isSectionDivider, onDelete != nil {
                    Button("Delete Divider", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .frame(minWidth: 44, minHeight: 44)
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
        .alert("Permanently delete this card?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Card", role: .destructive, action: deleteCard)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this card and its description, checklists, comments, member and label assignments, and attachments. This cannot be undone.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
                case .date(let field): /* Date field selected for editing */
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
                    .databaseActivityOverlay()

                case .members:
                    CardMembersSheet(members: members, memberColors: memberColors) { updatedMembers in
                        members = updatedMembers
                        syncCardState(members: updatedMembers)
                    }
                    .presentationDetents([.medium, .large])
                    .databaseActivityOverlay()

                case .labels:
                    CardLabelsSheet(library: labelLibrary, selectedLabelIDs: selectedLabelIDs) { updatedLibrary, updatedLabelIDs in
                        labelLibrary     = updatedLibrary
                        selectedLabelIDs = updatedLabelIDs

                        syncCardState(labelIDs: updatedLabelIDs)
                    }
                    .presentationDetents([.large])
                    .databaseActivityOverlay()

                case .attachmentSources:
                    CardAttachmentSourceSheet(
                        photoSelection: $selectedPhotoItems,
                        onAddLink: { activeSheet = .addLink },
                        onPasteClipboard: addClipboardLink,
                        onComingSoon: showAttachmentSourceComingSoon
                    )
                    .databaseActivityOverlay()

                case .addLink:
                    CardLinkAttachmentSheet(onSave: addWebLink)
                        .databaseActivityOverlay()

                case .attachmentPreview(let attachment): /* Media selected for preview */
                    CardAttachmentPreview(attachment: attachment)
                        .databaseActivityOverlay()

                case .actionDetail(let checklistID, let itemID): /* Selected checklist and action IDs */
                    if let checklist = checklists.first(where: { $0.id == checklistID }), /* Owning checklist */
                       let item = checklist.items.first(where: { $0.id == itemID }), /* Selected action */
                       case .actionDetail(let detail) = item.content { /* Reduced Action Detail payload */

                        ChecklistActionDetailView(
                            title:           item.title,
                            detail:          detail,
                            currentUserName: currentUserName
                        ) { updatedDetail in
                            updateActionDetail(
                                checklistID: checklistID,
                                itemID:      itemID,
                                detail:      updatedDetail
                            )
                        }
                        .databaseActivityOverlay()

                    } else {
                        ContentUnavailableView(
                            "Action unavailable",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("This checklist action could not be found.")
                        )
                    }
            }
        }
        }
    }
}


// --------------------------------------- MARK: - Action Detail ------------------------------- //

///
/// Presents reduced card-like context owned by one checklist action
///
/// @section    Purpose
///     Edit an action's description, nested checklist completion, and comments without creating
///     an independent Board card or allowing recursive Action Details
///
private struct ChecklistActionDetailView: View {

    let title:           String                                 /* Owning action title */
    let currentUserName: String                                 /* Comment author name */
    let onSave:          (KanbanChecklistActionDetail) -> Void  /* Save callback       */

    @Environment(\.dismiss) private var dismiss                 /* Sheet dismissal     */

    @State private var detailID:        UUID                    /* Stable detail ID     */
    @State private var descriptionText: String                  /* Description draft   */
    @State private var checklists:      [KanbanChecklist]       /* Nested actions      */
    @State private var comments:        [KanbanComment]         /* Detail comments     */
    @State private var commentDraft     = ""                    /* New comment draft   */

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
    ) {

        self.title           = title
        self.currentUserName = currentUserName
        self.onSave          = onSave

        _detailID        = State(initialValue: detail.id)
        _descriptionText = State(initialValue: detail.description)
        _checklists      = State(initialValue: detail.checklists)
        _comments        = State(initialValue: detail.comments)
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
    /// @post       Missing checklist/item IDs do nothing; no parent snapshot is emitted until Save
    ///
    private func toggleItem(checklistID: UUID, itemID: UUID) {

        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }) else { return } /* Nested checklist position */

        let checklist = checklists[checklistIndex] /* Nested checklist snapshot */

        guard let itemIndex = checklist.items.firstIndex(where: { $0.id == itemID }) else { return } /* Nested action position */

        var items = checklist.items /* Mutable nested actions */
        items[itemIndex].isCompleted.toggle()

        checklists[checklistIndex] = KanbanChecklist(
            id:    checklist.id,
            title: checklist.title,
            items: items
        )
    }

    ///
    /// @fcn        ChecklistActionDetailView.postComment
    /// @brief      Append the current non-empty comment draft
    /// @details    Trims surrounding whitespace and attributes the comment to the current actor
    ///
    /// @return     (Void) updates local comments and clears a valid draft
    /// @post       Blank input leaves the draft unchanged; comments remain local until Save
    ///
    private func postComment() {

        let trimmedDraft = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized comment */

        guard !trimmedDraft.isEmpty else { return }

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
    var body: some View { /* Reduced Action Detail editor form */

        NavigationStack {

            Form {

                Section("Description") {
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...8)
                }

                ForEach(checklists) { checklist in
                    Section(checklist.title) {
                        ForEach(checklist.items) { item in
                            Button {
                                toggleItem(checklistID: checklist.id, itemID: item.id)
                            } label: {
                                Label(
                                    item.title,
                                    systemImage: item.isCompleted ? "checkmark.square.fill" : "square"
                                )
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.isCompleted ? "Mark \(item.title) incomplete" : "Mark \(item.title) complete")
                        }
                    }
                }

                Section("Comments") {

                    if comments.isEmpty {
                        Text("No comments yet")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(comment.author)
                                .font(.caption.weight(.semibold))
                            Text(comment.body)
                        }
                    }

                    HStack {
                        TextField("Add comment", text: $commentDraft)
                            .onSubmit(postComment)

                        Button(action: postComment) {
                            Image(systemName: "paperplane.fill")
                        }
                        .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Post action comment")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(KanbanChecklistActionDetail(
                            id:          detailID,
                            description: descriptionText,
                            checklists:  checklists,
                            comments:    comments
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

    let onSave: ([CardAssignee]) -> Void            /* Save typed card assignments                                 */
    let memberColors: [String: Color]               /* Shared icon colors keyed by normalized member name          */

    @Environment(\.dismiss) private var dismiss     /* Dismiss action for the sheet                                */
    @State private var members: [CardAssignee]      /* Local typed assignments being edited                        */
    @State private var memberDraft = ""             /* Current text input for adding a new member                  */

    ///
    /// @fcn        CardMembersSheet.trimmedMemberDraft
    /// @brief      Normalize a proposed manual assignment name
    /// @details    Trims outer whitespace/newlines without editing the input field
    ///
    /// @return     (String) normalized member draft, potentially empty
    /// @post       Draft text and existing assignments remain unchanged
    ///
    private var trimmedMemberDraft: String { /* Normalized manual-assignee input */

        memberDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    ///
    /// @fcn        CardMembersSheet.canAddMember
    /// @brief      Validate whether the manual-assignment draft can be added
    /// @details    Requires a nonblank normalized draft that does not match any current display name
    ///             by localized case-insensitive comparison, regardless of assignment kind
    ///
    /// @return     (Bool) whether Add or implicit draft inclusion on Save is permitted
    /// @post       No assignment is added by validation
    ///
    private var canAddMember: Bool { /* Draft is non-empty and not already assigned */

        !trimmedMemberDraft.isEmpty && !members.contains {
            $0.displayName.localizedCaseInsensitiveCompare(trimmedMemberDraft) == .orderedSame
        }
    }

    ///
    /// @fcn        CardMembersSheet.normalizedMembers
    /// @brief      Prepare the assignment snapshot for explicit Save
    /// @details    Includes a valid pending manual draft, trims names, omits blanks, and deduplicates
    ///             manual names separately from registered-user IDs (falling back to assignment UUID)
    ///
    /// @return     ([CardAssignee]) normalized assignments preserving first-occurrence order and identity
    /// @post       Local drafts remain unchanged; a valid unsubmitted name can be included in the result
    ///
    private var normalizedMembers: [CardAssignee] { /* Deduplicated assignments prepared for saving */

        var seenAssignments: Set<String> = [] /* Identity keys already emitted */
        
        let manualDraft = canAddMember ? [CardAssignee.manual(trimmedMemberDraft)] : [] /* Optional new manual assignment */
        let membersToSave = members + manualDraft /* Existing assignments plus valid draft */

        return membersToSave.compactMap { assignee in
            let trimmedName = assignee.displayName.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized display name */
            let identityKey = assignee.kind == .registeredUser /* Stable identity namespace */
                ? "user:\(assignee.userID ?? assignee.id.uuidString)"
                : "manual:\(trimmedName.lowercased())"

            guard !trimmedName.isEmpty, seenAssignments.insert(identityKey).inserted else {
                return nil
            }

            return CardAssignee(
                id:          assignee.id,
                kind:        assignee.kind,
                userID:      assignee.userID,
                displayName: trimmedName
            )
        }
    }

    ///
    /// @fcn        CardMembersSheet.init(members:memberColors:onSave:)
    /// @brief      Seed an isolated card-assignment editing draft
    /// @details    Copies typed assignments into local State and retains display colors and submission action
    ///
    /// @param[in]  members       Initial manual/registered assignments
    /// @param[in]  memberColors  Shared icon colors keyed by lowercased display name
    /// @param[in]  onSave        Callback receiving normalized assignments
    /// @return     (CardMembersSheet) configured assignment editor
    /// @post       No assignment normalization or parent update occurs during initialization
    ///
    init(members: [CardAssignee], memberColors: [String: Color], onSave: @escaping ([CardAssignee]) -> Void) {
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

        members.append(.manual(trimmedMemberDraft))
        memberDraft = ""
    }

    ///
    /// @fcn        CardMembersSheet.body
    /// @brief      Present manual assignment editing and typed-member removal
    /// @details    Registered display names are read-only; manual names are editable.
    ///             Supports swipe removal, validated manual addition, and normalized Save/Cancel
    ///
    /// @return     (some View) member draft navigation list
    /// @post       Save submits normalizedMembers, including a valid pending draft, then dismisses.
    ///             Cancel discards local changes without invoking onSave
    ///
    var body: some View { /* Member assignment editor */

        NavigationStack {

            List {

                Section("Assigned users") {

                    if members.isEmpty {
                        Text("No users assigned")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(members.indices, id: \.self) { index in

                        HStack(spacing: 10) {

                            Image(systemName: members[index].kind == .registeredUser ? "person.crop.circle.fill" : "person.crop.circle")
                                .foregroundStyle(memberColors[members[index].displayName.lowercased()] ?? .accentColor)

                            if members[index].kind == .manual {
                                TextField("Name or email", text: Binding(
                                    get: { members[index].displayName },
                                    set: { members[index].displayName = $0 }
                                ))
                                .textInputAutocapitalization(.never)
                            } else {
                                Text(members[index].displayName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
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

    @ViewBuilder let content: () -> Content /* Content rendered beneath the section heading */

    ///
    /// @fcn        DetailSection.init(title:trailing:trailingAction:content:)
    /// @brief      Initialize a detail section
    /// @details    Stores the section title, optional trailing symbol/action, and view-builder content
    ///
    /// @param[in]  title           Display title for the section
    /// @param[in]  trailing        Optional SF Symbol name shown at the trailing edge
    /// @param[in]  trailingAction  Optional action invoked by the trailing symbol
    /// @param[in]  content         Content rendered below the section heading
    ///
    /// @return     (DetailSection) configured detail section
    /// @post       Content and trailing action are retained without being invoked
    ///
    init(title: String, trailing: String? = nil, trailingAction: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {

        self.title          = title          /* The title of the detail section                    */
        self.trailing       = trailing       /* The optional trailing symbol of the detail section */
        self.trailingAction = trailingAction /* The optional action for the trailing symbol        */
        self.content        = content        /* The content of the detail section                  */
    }


    ///
    /// @fcn        DetailSection.body
    /// @brief      Build the detail section presentation
    /// @details    Renders the heading, optional trailing symbol/action, supplied content, and divider
    ///
    /// @return     (some View) rendered detail section
    /// @post       Tapping an actionable trailing symbol invokes trailingAction;
    ///             a symbol without an action remains decorative
    ///
    var body: some View { /* Detail subsection heading and content */

        // Build the detail section container with heading, optional trailing symbol/action, content, and divider
        VStack(alignment: .leading, spacing: 10) {

            // Build the heading row with title and optional trailing symbol/action
            HStack {

                // Render the section title
                Text(title)
                    .font(.headline)
                Spacer()

                // Render the trailing symbol and optional action if provided
                if let trailing { /* Optional trailing symbol */

                    // Check if a trailing action is provided
                    if let trailingAction { /* Optional symbol action */

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
    /// @fcn        ActionTile.body
    /// @brief      Build the compact action tile
    /// @details    Renders the action label and symbol as a plain, consistently sized button
    ///
    /// @return     (some View) rendered action tile
    /// @post       Tapping delegates to action; rendering itself performs no mutation
    ///
    var body: some View { /* Compact labeled action button */

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
    /// @fcn        DetailRow.body
    /// @brief      Build one metadata row
    /// @details    Aligns the supplied icon, title, and trailing value within the detail section
    ///
    /// @return     (some View) rendered metadata row
    /// @post       The row has no mutation or navigation behavior
    ///
    var body: some View { /* Icon, title, and trailing metadata value */

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
    let linkedCardsByID: [Int: KanbanCard]  /* Linked cards keyed by stable ID                                          */
    let onDelete: ()        -> Void         /* The action invoked when the checklist is deleted                        */
    let onAddItem: ()       -> Void         /* The action invoked when a new item is added                             */
    let onToggleItem: (Int) -> Void         /* The action invoked when an item is toggled                              */
    let onUpdateItem: (Int, String) -> Void /* The action invoked when item text is edited                             */
    let onDeleteItem: (Int)  -> Void        /* The action invoked when an item is deleted                              */
    let onOpenActionDetail: (UUID) -> Void  /* The action invoked for reduced detail                                  */
    let onRename: (String)   -> Void        /* The action invoked when the checklist title is renamed                  */
    let onToggleAllItems: () -> Void        /* The action invoked when all items are toggled                           */
    let onMove: (ChecklistMoveDirection) -> Void /* The action invoked when the checklist is moved                     */
    let canMoveUp: Bool                     /* Whether the checklist can be moved up in the list                       */
    let canMoveDown: Bool                   /* Whether the checklist can be moved down in the list                     */
    let focusFirstItem: Bool                /* Whether the first item should be focused when the checklist is rendered */
    let onFirstItemFocused: () -> Void      /* The action invoked when the first item receives focus                   */

    @State private var isRenaming = false   /* Whether the checklist title is currently being renamed                  */
    @State private var titleDraft = ""      /* The draft text for the checklist title being edited                     */
    @State private var hideCompletedItems = false /* Checklist completed-item filter */
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
    private var allItemsAreCompleted: Bool { /* Non-empty checklist completion state */

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
    /// @fcn        ChecklistBlock.actionRow(for:)
    /// @brief      Build the row behavior for one checklist action type
    /// @details    Keeps the main checklist body small while preserving shared completion and deletion
    ///
    /// @param[in]  entry  Original item position and stable checklist action
    ///
    /// @return     (some View) standard editor, linked-card navigation, or Action Detail button
    /// @pre        entry.offset refers to the original checklist index, not the filtered display index
    /// @post       Row callbacks delegate completion/deletion by original index;
    ///             only standard actions receive text editing and first-item focus requests
    ///
    @ViewBuilder
    private func actionRow(for entry: (offset: Int, element: KanbanChecklistItem)) -> some View {

        switch entry.element.content {
            case .standard:
                ChecklistItemRow(
                    item: entry.element.title,
                    isCompleted: checklist.completedItemIndices.contains(entry.offset),
                    onToggle: { onToggleItem(entry.offset) },
                    onUpdate: { text in onUpdateItem(entry.offset, text) },
                    onDelete: { onDeleteItem(entry.offset) },
                    shouldFocus: focusFirstItem && entry.offset == 0,
                    onFocusHandled: onFirstItemFocused
                )

            case .linkedCard(let cardID): /* Stable target card identity */
                ChecklistItemRow(
                    item: entry.element.title,
                    isCompleted: checklist.completedItemIndices.contains(entry.offset),
                    linkedCardID: cardID,
                    linkedCard: linkedCardsByID[cardID],
                    onToggle: { onToggleItem(entry.offset) },
                    onUpdate: { _ in },
                    onDelete: { onDeleteItem(entry.offset) },
                    shouldFocus: false,
                    onFocusHandled: {}
                )

            case .actionDetail:
                ChecklistItemRow(
                    item: entry.element.title,
                    isCompleted: checklist.completedItemIndices.contains(entry.offset),
                    onOpenDetail: { onOpenActionDetail(entry.element.id) },
                    onToggle: { onToggleItem(entry.offset) },
                    onUpdate: { _ in },
                    onDelete: { onDeleteItem(entry.offset) },
                    shouldFocus: false,
                    onFocusHandled: {}
                )
        }
    }

    ///
    /// @fcn        ChecklistBlock.body
    /// @brief      Build the checklist group
    /// @details    Renders completion counts and typed rows with collapse/hide-completed controls.
    ///             Offers check-all, bounded movement, rename via menu or 0.5-second title hold,
    ///             deletion, and item creation
    ///
    /// @return     (some View) rendered checklist group
    /// @post       Content mutations delegate to parent callbacks; collapse/filter/rename presentation
    ///             remain local. Blank rename input and boundary movement controls are disabled
    ///
    var body: some View { /* Checklist heading, rows, and action menu */

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
                    actionRow(for: entry)
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
    let linkedCardID: Int?            /* Stable linked card ID, when present                           */
    let linkedCard: KanbanCard?       /* Resolved linked card, when available                          */
    let onOpenDetail: (() -> Void)?   /* Action Detail presentation callback                           */
    let onToggle: () -> Void          /* The action invoked by the checkbox                            */
    let onUpdate: (String) -> Void    /* The action invoked by text editing                            */
    let onDelete: () -> Void          /* The action invoked by delete                                  */
    let shouldFocus: Bool             /* Indicates whether the text field should receive focus         */
    let onFocusHandled: () -> Void    /* The action invoked when the text field focus has been handled */

    @State private var horizontalOffset: CGFloat = 0 /* Current swipe translation */
    @FocusState private var isTextFocused: Bool /* Text-editor focus state */

    ///
    /// @fcn        ChecklistItemRow.init(item:isCompleted:linkedCardID:linkedCard:onOpenDetail:onToggle:onUpdate:onDelete:shouldFocus:onFocusHandled:)
    /// @brief      Initialize a standard, linked-card, or Action Detail checklist row
    /// @details    Optional navigation inputs determine the title control while completion and deletion
    ///             remain available for every action type
    ///
    /// @param[in]  item           Display title or editable standard-action text
    /// @param[in]  isCompleted    Current completion state
    /// @param[in]  linkedCardID   Optional stable linked-card reference
    /// @param[in]  linkedCard     Resolved linked card, or nil for an unavailable destination
    /// @param[in]  onOpenDetail   Optional reduced Action Detail presentation callback
    /// @param[in]  onToggle       Completion action
    /// @param[in]  onUpdate       Standard-action text update callback
    /// @param[in]  onDelete       Record deletion callback
    /// @param[in]  shouldFocus    Whether a standard editor requests focus on appearance
    /// @param[in]  onFocusHandled Callback acknowledging the scheduled focus request
    ///
    /// @return     (ChecklistItemRow) configured action row
    /// @post       Initialization installs inputs without invoking any callbacks
    ///
    init(
        item: String,
        isCompleted: Bool,
        linkedCardID: Int? = nil,
        linkedCard: KanbanCard? = nil,
        onOpenDetail: (() -> Void)? = nil,
        onToggle: @escaping () -> Void,
        onUpdate: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        shouldFocus: Bool,
        onFocusHandled: @escaping () -> Void
    ) {

        self.item           = item
        self.isCompleted    = isCompleted
        self.linkedCardID   = linkedCardID
        self.linkedCard     = linkedCard
        self.onOpenDetail   = onOpenDetail
        self.onToggle       = onToggle
        self.onUpdate       = onUpdate
        self.onDelete       = onDelete
        self.shouldFocus    = shouldFocus
        self.onFocusHandled = onFocusHandled
    }


    ///
    /// @fcn        ChecklistItemRow.body
    /// @brief      Present a typed checklist action with completion and horizontal deletion
    /// @details    Prioritizes linked-card navigation, then Action Detail, otherwise text editing.
    ///             Missing links show unavailable copy. Standard editors asynchronously handle initial focus
    ///
    /// @return     (some View) clipped row over a 72-point destructive button
    /// @post       Horizontal drags beyond 36 points reveal deletion; beyond 120 points invoke onDelete.
    ///             Vertical-dominant drags are ignored; text/completion changes delegate to callbacks
    /// @note       The parent must install a KanbanCard navigation destination for resolved links
    ///
    var body: some View { /* Checklist action row and swipe-to-delete control */

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

                if let linkedCardID { /* Linked Board-card reference */

                    if let linkedCard { /* Resolved linked card */
                        NavigationLink(value: linkedCard) {
                            Label(item, systemImage: "link")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the linked card")

                    } else {
                        Label("\(item) unavailable", systemImage: "link.badge.plus")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHint("Linked card \(linkedCardID) is unavailable")
                    }

                } else if let onOpenDetail { /* Action Detail navigation callback */

                    Button(action: onOpenDetail) {
                        Label(item, systemImage: "doc.text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens action details")

                } else {

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
    let onDelete: () -> Void /* Activity deletion callback */


    ///
    /// @fcn        ActivityRow.body
    /// @brief      Build the activity event row
    /// @details    Places generated activity copy beside the actor symbol inside a shared swipe-delete row
    ///
    /// @return     (some View) rendered activity row
    /// @post       Deletion delegates to onDelete rather than removing a stored event directly
    /// @note       Today at 7:00 AM is fixed display copy, not a timestamp from persisted activity
    ///
    var body: some View { /* Generated activity text and timestamp */

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


///
/// Renders a posted card comment and its authoring time in the activity feed
///
/// @section    Purpose
///     Present comment text and author context with a consistent activity timestamp
///
struct CommentActivityRow: View {

    let comment: KanbanComment      /* The comment data rendered by the row           */
    let memberColor: Color          /* The assigned icon color for the comment author  */
    let onDelete: () -> Void        /* The action invoked when the comment is deleted */

    ///
    /// @fcn        CommentActivityRow.body
    /// @brief      Present a stored comment with author styling and creation time
    /// @details    Combines author/body text and formats the persisted timestamp using abbreviated
    ///             date and shortened time inside the shared swipe-delete container
    ///
    /// @return     (some View) deletable comment activity row
    /// @post       Rendering does not modify the comment; deletion delegates to onDelete
    ///
    var body: some View { /* Posted comment and authoring time */
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
/// Adds a trailing delete action revealed by swiping an activity row
///
/// @section    Purpose
///     Reuse one accessible swipe-to-delete presentation for card activity entries
///
struct ActivitySwipeRow<Content: View>: View {

        let onDelete: () -> Void                            /* The action invoked when the row is deleted     */
        let deletionAccessibilityLabel: String              /* Accessibility label for the swipe action       */
        @ViewBuilder let content: () -> Content             /* The content view rendered inside the swipe row */
        @State private var horizontalOffset: CGFloat = 0    /* The current horizontal offset of the swipe row */

        ///
        /// @fcn        ActivitySwipeRow.init(onDelete:deletionAccessibilityLabel:content:)
        /// @brief      Configure a reusable trailing destructive action
        /// @details    Retains the deletion callback, accessibility label, and content builder
        ///
        /// @param[in]  onDelete Delete action invoked by the exposed button or a full left swipe
        /// @param[in]  deletionAccessibilityLabel Accessible description for the delete action
        /// @param[in]  content Row content shown above the destructive background
        ///
        /// @return     (ActivitySwipeRow) configured activity row
        /// @post       Content construction and deletion are deferred until rendering/interaction
        ///
        init(
            onDelete: @escaping () -> Void,
            deletionAccessibilityLabel: String = "Delete activity",
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.onDelete = onDelete
            self.deletionAccessibilityLabel = deletionAccessibilityLabel
            self.content = content
        }

        ///
        /// @fcn        ActivitySwipeRow.body
        /// @brief      Wrap content in a custom horizontal swipe-to-delete surface
        /// @details    Clamps leftward translation to a 72-point button width and ignores vertical-dominant
        ///             gestures. Release beyond 36 points reveals the button; beyond 120 points deletes directly
        ///
        /// @return     (some View) clipped content over an accessible destructive button
        /// @post       Deletion invokes onDelete without a separate confirmation dialog;
        ///             smaller horizontal releases animate closed or open according to the threshold
        ///
        var body: some View { /* Swipe-to-delete activity container */

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
