// --------------------------------------------------------------------------------------------------
// @file       CardDetailView.swift
// @brief      Card and Note detail composition and retained editor state
// @details    Owns the working presentation and synchronization context; focused extensions
//             provide mutation and section rendering behavior.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


/// Identifies a checklist's requested position within its card.
///
/// @section    Purpose
///     Represent adjacent and absolute checklist move operations
///
/// @note   Boundary actions are disabled in ChecklistBlock when no movement is possible
///
enum ChecklistMoveDirection
{


    case top
    case up
    case down
    case bottom
}


// -------------------------------------- MARK: - Card Detail View ------------------------------ //


///
/// Defines checklist link candidates in the environment
///
/// @section    Purpose
///     Defaults to an empty set of Cards until the owning workspace injects eligible canonical link
///     destinations.
///
struct ChecklistCandidatesKey: EnvironmentKey
{

    static let defaultValue: [KanbanCard] = []
}


///
/// Supplies checklist link candidates to Card editors
///
/// @section    Purpose
///     Injects the currently eligible canonical Cards without coupling checklist controls to a
///     particular owner store.
///
extension EnvironmentValues
{


    var checklistLinkCandidates: [KanbanCard]
    {

        get
        {
            self[ChecklistCandidatesKey.self]
        }

        set
        {
            self[ChecklistCandidatesKey.self] = newValue
        }

    }

}


///
/// Presents and edits the complete Card or Note record
///
/// @section    Purpose
///     Coordinates writing, checklists, dates, attachments, appearance, reactions, and importance
///     through owner callbacks; locked content uses a read-only presentation.
///
struct CardDetailView: View
{

    @Environment(\.inheritedSubtitleItalic) private var inheritedSubtitleItalic


    @Environment(\.cardKeyboardNavigation) var keyboardNavigation
    @State var keyboardContextID = UUID()
    @Environment(\.workspaceNoteVisibility) var workspaceNoteVisibility
    @State var noteVisibilityID = UUID()
    @Environment(\.planningCalendarAccess) var checklistTypePlanningAccess
    @Environment(\.checklistLinkCandidates) var checklistLinkCandidates
    @Environment(\.cardMovementSource) var checklistCollectionID
    @Environment(\.libraryItemOpened) var libraryItemOpened
    @Environment(\.libraryImportance) var libraryImportance
    @State var isActivityCollapsed = false
    @State var startDateKind:      CardDateKind
    @State var dueDateKind:        CardDateKind
    @State var showsDueDateInList: Bool
    @State var sectionLayout:      CardSectionLayout
    @State var showsLayoutEditor = false
    @Environment(\.workspaceBottomBarHeight) var workspaceBottomBarHeight

    // ----------------------------------- MARK: - Date Field Enum ------------------------------ //


    /// Identifies the date field currently edited by the date picker
    ///
    /// @section    Purpose
    ///     Distinguish a card's start date from its due date
    ///
    enum DateField: String, Identifiable, Equatable
    {


        case start  /* Start date field for the card */
        case due    /* Due date field for the card   */

        ///
        /// @fcn        CardDetailView.DateField.id
        /// @brief      Identify the date field being edited
        /// @details    Uses the raw enum value for stable date-sheet identity
        ///
        /// @return     (String) start or due field identity
        /// @post       Date state remains unchanged
        ///
        var id: String
        {
            rawValue
        }  /* Stable date-field identity */


        ///
        /// @fcn        CardDetailView.DateField.title
        /// @brief      Resolve the date field's display label
        /// @details    Supplies the heading used by date rows and picker sheets
        ///
        /// @return     (String) Start date or Due date label
        /// @post       No date or presentation state changes
        ///
        var title: String
        {  /* User-facing date-field label */

            switch self
            {


            case .start:
                return "Start date"
            case .due:
                return "Due date"
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
    enum ActiveSheet: Identifiable
    {


        case date(DateField) /* Date picker sheet for editing a specific date field */
        case editHistory
        case reactions
        case members            /* Card member management sheet             */
        case labels             /* Card label library and assignment picker */
        case attachmentSources  /* Attachment source chooser                */
        case noteAttachments
        case appearance
        case cover
        case addDrawing(DrawingCaptureDraft)      /* New drawing attached only after Done      */
        case addLink                              /* Manual web-link entry sheet               */
        case attachmentPreview(KanbanAttachment)  /* Preview of an attached photo              */
        case actionDetail(UUID, UUID)             /* Checklist and item IDs for reduced detail */

        ///
        /// @fcn        CardDetailView.ActiveSheet.id
        /// @brief      Identify a card-detail modal and its associated destination
        /// @details    Combines the presentation kind with date, attachment, or checklist/item
        ///             identity where needed so distinct destinations remain distinguishable
        ///
        /// @return     (String) stable sheet-destination identity
        /// @post       No sheet is presented or dismissed by this lookup
        ///
        var id: String
        {  /* Stable identity for the active sheet                */


            switch self
            {


            case .date(let field):
                            "date-\(field.id)" /* Selected date field */
            case .editHistory:
                            "editHistory"
            case .reactions:
                            "reactions"
            case .members:
                            "members"
            case .labels:
                            "labels"
            case .attachmentSources:
                            "attachment-sources"
            case .noteAttachments:
                            "note-attachments"
            case .cover:
                            "cover"
            case .appearance:
                            "appearance"
            case .addLink:
                            "add-link"
            case .addDrawing(let draft):
                            "add-drawing-\(draft.id.uuidString)"
            case .attachmentPreview(let attachment):
                                    "attachment-\(attachment.id.uuidString)"  /* Previewed attachment            */
            case .actionDetail(let checklistID, let itemID):                  /* Owning checklist and action IDs */
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
    enum GeneratedActivity: String, CaseIterable, Identifiable
    {


        case addedCard       /* Card was added to the board           */
        case createdCard     /* Card was created on the board         */
        case initialComment  /* Initial comment was added to the card */

        ///
        /// @fcn        CardDetailView.GeneratedActivity.id
        /// @brief      Identify a generated activity entry for dismissal
        /// @details    Uses the raw case value stored in the card's dismissed-activity set
        ///
        /// @return     (String) generated-entry identity
        /// @post       No activity dismissal is recorded
        ///
        var id: String
        {
            rawValue
        }  /* Stable generated-activity identity */


        ///
        /// @fcn        CardDetailView.GeneratedActivity.text(for:actorName:)
        /// @brief      Generate the display text for an activity entry
        /// @details    Resolves this activity type into user-visible copy using the selected card's
        ///             title and list
        ///
        /// @param[in]  card       Card whose activity feed is being rendered
        /// @param[in]  actorName  Current user name shown as the activity actor
        ///
        /// @return     (String) display text for this generated activity entry
        ///
        /// @pre        card contains the identity and list details used by the activity message
        /// @post       No card or activity state is modified
        ///
        func text(for card: KanbanCard, actorName: String) -> String
        {


            switch self
            {


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
    enum ActivityFilter: String, CaseIterable, Identifiable
    {


        case all           /* All activity entries for the card       */
        case comments      /* User-added comments for the card        */
        case cardActivity  /* Generated activity entries for the card */

        ///
        /// @fcn        CardDetailView.ActivityFilter.id
        /// @brief      Identify an activity display filter
        /// @details    Uses the enum raw value for picker identity
        ///
        /// @return     (String) stable filter identity
        /// @post       The selected filter remains unchanged
        ///
        var id: String
        {
            rawValue
        }  /* Stable activity-filter identity */


        ///
        /// @fcn        CardDetailView.ActivityFilter.title
        /// @brief      Name the selected activity scope
        /// @details    Supplies readable labels for all entries, comments, or generated card activity
        ///
        /// @return     (String) filter display title
        /// @post       No activity records are filtered or modified by this lookup
        ///
        var title: String
        {  /* User-facing activity-filter label */

            switch self
            {


            case .all:
                            "All Activity"
            case .comments:
                            "Comments"
            case .cardActivity:
                            "Card Activity"
            }

        }

    }


    /// Identifies which editable card field currently has focus
    ///
    /// @section    Purpose
    ///     Keep text-field focus state explicit across title, subtitle, description, and comment entry
    ///
    enum EditableField: Hashable
    {


        case title        /* The title field is being edited       */
        case subtitle     /* The subtitle field is being edited    */
        case description  /* The description field is being edited */
        case comment      /* The comment field is being edited     */
    }


    @State var lastSavedHistoryCard: KanbanCard  /* Accepted local snapshot for history and save grouping */
    let card:                  KanbanCard /* The kanban card being displayed in detail                    */
    let listedOnDate:          Date?
    @Binding var labelLibrary: LabelLibrary             /* Shared label catalog available to every card             */
    let availableLists:        [KanbanList]             /* Other lists that can receive this card                   */
    let memberColors:          [String: Color]          /* Shared icon colors keyed by normalized member name       */
    let currentUserName:       String                   /* Current actor name shown in card activity                */
    @Binding var savedCardIDs: Set<Int>                 /* Local identities saved for quick access                  */
    let onTitleToggle:         ((KanbanCard) -> Void)?  /* Callback invoked when the card title checkbox is toggled */
    let onMoveToList:          ((Int) -> Void)?         /* Callback invoked to move the card to a selected list     */
    let personalCollectionID:  UUID?                    /* Original personal collection owning this detail session  */
    @Environment(\.cardMovementAccess) var cardMovementAccess
    let availablePersonalLists: [PersonalCollection] /* Personal Lists offered as Note movement destinations     */
    let onMoveNoteToPersonalList:
    ((KanbanCard, UUID, UUID) -> KanbanCard?)?            /* Moves the Note and returns its destination-local record */
    let onUpdateMovedNote: ((UUID, KanbanCard) -> Bool)?  /* Persists edits after the Note changes collections       */
    let onArchiveMovedNote:
    ((UUID, KanbanCard) -> Bool)?                         /* Archives the Note in its current collection              */
    let onDeleteMovedNote: ((UUID, KanbanCard) -> Bool)?  /* Permanently removes the Note from its current collection */
    let onToggleMovedNoteBookmark:
    ((UUID, Int, Bool) -> Bool)? /* Persists the relocated Note's saved state                */
    /// Optional callback that archives the latest synchronized card snapshot.
    let onArchive: (() -> Void)? /* Archives the record through its original owner */
    /// Optional callback permanently deleting this card and its caller-owned content.
    let onDelete: (() -> Bool)? /* Save-first removal; false keeps the editor and drafts open */

    @Environment(\.dismiss) var dismiss /* Dismiss action for the card detail view                      */
    @State var richTextFocusedField: EditableField?  // UIKit editors retain focus independently of SwiftUI text fields.
    @State var editingHeaderField:   EditableField?
    @FocusState var focusedField:    EditableField? /* current focused editable field within the card detail view   */

    @State var checklists:               [KanbanChecklist]  /* The checklist groups associated with the selected card   */
    @State var checklistToFocus:         UUID?              /* Newly added checklist whose first item should be focused */
    @State var titleChecked:             Bool               /* Whether the card title itself is checked                 */
    @State var showsReactionsInPreviews: Bool?
    @State var reactions:                [ItemEmojiReaction]?
    @State var reactionAuthorID = LocalReactionIdentity.current()
    @State var titleText:  String /* Editable card title displayed in the detail header           */
    @State var appearance: ItemAppearance?
    @State var showsAppearanceCover = false
    @State var subtitleText:       String              /* Editable card subtitle displayed in the detail header */
    @State var startDate:          Date?               /* Optional start date for the selected card             */
    @State var dueDate:            Date?               /* Optional due date for the selected card               */
    @State var descriptionText:    String              /* Editable description shown on this card               */
    @State var activeSheet:        ActiveSheet?        /* The date picker or member editor currently presented  */
    @State var comments:           [KanbanComment]     /* Comments saved to this card's activity                */
    @State var members:            [CardAssignee]      /* Registered and manual card assignments                */
    @State var selectedLabelIDs:   [String]            /* Stable IDs of labels assigned to this card            */
    @State var attachments:        [KanbanAttachment]  /* Photo attachments currently assigned to the card      */
    @State var isEditingLocked:    Bool
    @State var lockedSnapshot:     KanbanCard?
    @State var coverAttachmentID:  UUID?              /* Explicit cover selection; nil means disabled   */
    @State var selectedCoverPhoto: PhotosPickerItem?  /* One photo explicitly selected for a cover      */
    @State var coverImportID:      UUID?              /* Superseded requests cannot enable an old cover */
    @State var showsCoverPicker = false               /* Visual chooser for already attached photos     */
    @State var showsCoverLibrary = false              /* Offline category-based illustration chooser    */
    @State var selectedPhotoItems: [PhotosPickerItem] =
    []                                                      /* Photos selected from the system photo library                */
    @State var commentDraft = ""                            /* Text currently entered in the comment composer               */
    @State var dismissedActivityIDs: Set<String>            /* IDs of activity entries that have been dismissed by the user */
    @State var activityFilter:       ActivityFilter = .all  /* The currently selected activity filter for the card          */
    @State var showingAttachmentNotice = false              /* Whether an attachment notice is presented                    */
    @State var attachmentNoticeMessage = ""                 /* Explanation shown for failed or unavailable sources          */
    @State var showingDeleteConfirmation = false            /* Whether permanent card deletion awaits confirmation          */
    @State var hasMovedCard = false                         /* Stops editor callbacks from writing back to the old owner    */
    @State var hasDeletedCard = false                       /* Prevents stale snapshots after confirmed deletion            */
    @State var displayFormat: ItemDisplayFormat
    @State var presentation:  ItemPresentation      /* Current Card or Note rendering mode                      */
    @State var showsNoteDetails = false             /* Visibility of supplementary Note fields                  */
    @State var hasEditedDescription = false         /* Whether the body draft should replace the stored value   */
    @State var recordID:                    Int     /* Current identity after any collection-local reassignment */
    @State var currentListTitle:            String  /* Owning list name updated after Note movement             */
    @State var currentPersonalCollectionID: UUID?   /* Current personal collection after Note movement          */
    @State var movedNoteIsSaved:            Bool?   /* Saved-state override for a relocated Note                */


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
    var linkedCardsByID: [Int: KanbanCard]
    {

        Dictionary(
            (availableLists.flatMap(\.cards) + checklistLinkCandidates).map
            {
                ($0.id, $0)
            },
            uniquingKeysWith:
            {
                _, latest in
                latest
            })
    }


    ///
    /// @fcn        CardDetailView.init
    /// @brief      Initialize the card detail state
    /// @details    Seeds all working fields from the supplied card, including stored checklists,
    ///             assignments, attachments, and dismissed activity IDs
    ///
    /// @param[in]  card                       Complete card snapshot being edited
    /// @param[in]  labelLibrary               Shared reusable label catalog binding
    /// @param[in]  availableLists             Other active lists used for movement and linked-card lookup
    /// @param[in]  memberColors               Icon colors keyed by normalized display name
    /// @param[in]  currentUserName            Actor name used by generated activity and Action Detail comments
    /// @param[in]  savedCardIDs               Binding to this Board's device-local bookmarks
    /// @param[in]  onTitleToggle              Optional callback receiving every complete edited card snapshot
    /// @param[in]  onMoveToList               Optional callback receiving a destination list ID
    /// @param[in]  personalCollectionID       Current local collection for cross-collection Note moves
    /// @param[in]  availablePersonalLists     Active personal Lists offered as Note destinations
    /// @param[in]  onMoveNoteToPersonalList   Save-first Note movement callback
    /// @param[in]  onArchive                  Optional callback archiving the latest synchronized card
    /// @param[in]  onDelete                   Optional save-first deletion callback; false retains the editor and drafts
    ///
    /// @param[in]  onUpdateMovedNote          Optional checked callback saving further edits after a Note
    ///             moves to another owner
    /// @param[in]  onArchiveMovedNote         Optional owner callback archiving a Note after it moves
    /// @param[in]  onDeleteMovedNote          Optional checked callback deleting a Note after it moves
    /// @param[in]  onToggleMovedNoteBookmark  Optional callback changing a moved Note's personal
    ///             bookmark
    /// @param[in]  listedOnDate               Optional represented Day date supplying context for the detail
    ///             presentation
    ///
    /// @return     (CardDetailView) configured card detail presentation
    /// @post       Initialization does not submit edits or mutate caller-owned bindings
    /// @note       Without onTitleToggle, main-card edits remain local to this detail instance
    ///
    init(
        card: KanbanCard,
        labelLibrary: Binding<LabelLibrary> = .constant(.starter),
        availableLists: [KanbanList] = [],    /* Other lists available as move destinations */
        memberColors: [String: Color] = [:],  /* Shared member icon colors                  */
        currentUserName: String = "Justin Reina",
        savedCardIDs: Binding<Set<Int>> = .constant([]),
        onTitleToggle: ((KanbanCard) -> Void)? = nil,  /* Callback invoked when the card title checkbox is toggled */
        onMoveToList: ((Int) -> Void)? = nil,          /* Callback invoked when the card is moved                  */
        personalCollectionID: UUID? = nil,
        availablePersonalLists: [PersonalCollection] = [],
        onMoveNoteToPersonalList: ((KanbanCard, UUID, UUID) -> KanbanCard?)? = nil,
        onUpdateMovedNote: ((UUID, KanbanCard) -> Bool)? = nil,
        onArchiveMovedNote: ((UUID, KanbanCard) -> Bool)? = nil,
        onDeleteMovedNote: ((UUID, KanbanCard) -> Bool)? = nil,
        onToggleMovedNoteBookmark: ((UUID, Int, Bool) -> Bool)? = nil,
        onArchive: (() -> Void)? = nil,
        onDelete: (() -> Bool)? = nil,
        listedOnDate: Date? = nil
    )
    {


        self.card = card /* The kanban card being displayed in detail                            */
        self.listedOnDate = listedOnDate
        self._labelLibrary = labelLibrary       /* Shared catalog used by all card label assignments        */
        self.availableLists = availableLists    /* Other lists available as move destinations               */
        self.memberColors = memberColors        /* Shared member icon colors                                */
        self.currentUserName = currentUserName  /* Current actor name shown in card activity                */
        self._savedCardIDs = savedCardIDs       /* Local saved-card identities                              */
        self.onTitleToggle = onTitleToggle      /* Callback invoked when the card title checkbox is toggled */
        self.onMoveToList = onMoveToList        /* Callback invoked when the card is moved                  */
        self.personalCollectionID = personalCollectionID
        self.availablePersonalLists = availablePersonalLists
        self.onMoveNoteToPersonalList = onMoveNoteToPersonalList
        self.onUpdateMovedNote = onUpdateMovedNote
        self.onArchiveMovedNote = onArchiveMovedNote
        self.onDeleteMovedNote = onDeleteMovedNote
        self.onToggleMovedNoteBookmark = onToggleMovedNoteBookmark
        self.onArchive = onArchive
        self.onDelete = onDelete

        _titleChecked = State(
            initialValue: card.isTitleChecked) /* Initialize the title checked state based on the card's current value */
        _lastSavedHistoryCard = State(initialValue: card)
        _showsReactionsInPreviews = State(initialValue: card.showsReactionsInPreviews)
        _reactions = State(initialValue: card.reactions)
        _titleText = State(
            initialValue: card.isSectionDivider ? (card.sectionHeading ?? "") : card.word) /* Initialize the editable title from the card                          */
        _appearance = State(initialValue: card.appearance)
        _subtitleText = State(initialValue: card.subtitle)  /* Initialize the editable subtitle from the card */
        _startDate = State(initialValue: card.startDate)    /* Initialize the start date from the card state  */
        _dueDate = State(initialValue: card.dueDate)        /* Initialize the due date from the card state    */
        _sectionLayout = State(initialValue: card.sectionLayout ?? CardSectionLayout())
        _showsDueDateInList = State(initialValue: card.showsDueDateInList)
        _startDateKind = State(initialValue: card.startDateKind)
        _dueDateKind = State(initialValue: card.dueDateKind)
        _descriptionText = State(
            initialValue: card.presentation == .note ? (card.descriptionOverride ?? "") : card.funParagraph)
        _presentation = State(initialValue: [.note, .title, .text].contains(card.displayFormat) ? .note : .card)
        _displayFormat = State(initialValue: card.displayFormat)
        _recordID = State(initialValue: card.id)
        _currentListTitle = State(initialValue: card.listTitle)
        _currentPersonalCollectionID = State(initialValue: personalCollectionID)
        _comments = State(initialValue: card.comments)          /* Initialize comments from the selected card         */
        _members = State(initialValue: card.members)            /* Initialize assigned members from the selected card */
        _selectedLabelIDs = State(initialValue: card.labelIDs)  /* Initialize selected labels from the card           */
        _attachments = State(
            initialValue: card.attachments ?? []) /* Initialize photo attachments from the card         */
        _lockedSnapshot = State(initialValue: card.isEditingLocked ? card : nil)
        _isEditingLocked = State(initialValue: card.isEditingLocked)
        _coverAttachmentID = State(initialValue: card.coverAttachmentID)
        _dismissedActivityIDs = State(
            initialValue: card.dismissedActivityIDs) /* Initialize dismissed activity IDs from the card state                */

        _checklists = State(
            initialValue: card.checklists) /* Initialize checklist state from the card's stored values             */
    }


    ///
    /// @fcn        CardDetailView.coverControls
    /// @brief      Offer explicit photo selection, replacement, and non-destructive cover removal
    /// @details    Photo-library selection attaches one new photo; existing photos reuse their IDs.
    ///             Removing a cover preserves all attachments and never auto-selects another image
    /// @return     (some View) cover settings shown only on explicit request
    ///
    var coverControls: some View
    {  /* Featured-media selection and removal controls */

        DetailSection(title: "Card Cover")
        {

            Button("Browse Cover Library", systemImage: "photo.on.rectangle.angled")
            {

                showsCoverLibrary = true
            }

            .frame(minHeight: 44)

            if let cover = attachments.first(where:
                {  /* Attachment currently selected as the cover */


                    $0.id == coverAttachmentID && $0.kind == .photo
                })
            {

                CardCoverPreview(attachment: cover)
            }


            Button(coverAttachmentID == nil ? "Choose Attached Photo" : "Change Cover", systemImage: "photo")
            {

                showsCoverPicker = true
            }

            .disabled(!attachments.contains
                {
                    $0.kind == .photo
                })
            .frame(minHeight: 44)

            PhotosPicker(selection: $selectedCoverPhoto, matching: .images)
            {

                Label("Add Photo as Cover", systemImage: "photo.badge.plus")
                .frame(minHeight: 44)
            }


            if coverAttachmentID != nil || coverImportID != nil
            {


                Button("Remove Cover", systemImage: "photo.badge.minus")
                {

                    setCover(nil)
                }

                .frame(minHeight: 44)
                .accessibilityHint("Keeps the photo attached to this card.")
            }


            Text(
                                    "Covers are optional. Removing a cover keeps its photo attached. Choose an attached photo here or use Set as Cover on a photo's menu."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        .sheet(isPresented: $showsCoverPicker)
        {

            CardCoverPicker(
                photos: attachments.filter
                {
                    $0.kind == .photo
                },
                selectedID: coverAttachmentID,
                onSelect:
                {
                    setCover($0)
                }
            )
        }

        .sheet(isPresented: $showsCoverLibrary)
        {

            CardCoverLibrary(
                selectedImage: attachments.first
                {
                    $0.id == coverAttachmentID
                }?.exampleImage,
                onSelect: useLibraryCover
            )
        }

    }


    ///
    /// @fcn        CardDetailView.attachmentGallery
    /// @brief      Present gallery photos separately from the cover and other attachments
    /// @details    Keeps the gallery's view-builder expression separate from the full card editor
    /// @return     (some View) horizontal photo gallery and remaining media
    ///
    var attachmentGallery: some View
    {  /* Attached media displayed with editing actions */

        attachmentGallery(workingCardSnapshot.attachmentsExcludingCover)
    }


    ///
    /// @fcn        CardDetailView.selectedLabels
    /// @brief      Resolve assigned label IDs into display definitions
    /// @details    Preserves selection order and omits identities missing from the shared catalog
    ///
    /// @return     ([KanbanLabel]) resolved label definitions
    /// @post       Missing definitions do not remove IDs from the card's selection
    ///
    var selectedLabels: [KanbanLabel]
    {  /* Resolved selected label definitions */

        selectedLabelIDs.compactMap
        {
            labelID in
            labelLibrary.labels.first(where:
                {
                    $0.id == labelID
                })
        }

    }


    var reactionStrip: some View
    {

        ItemReactionStrip(
            reactions: reactions ?? [], authorID: reactionAuthorID,
            onToggle: toggleReaction,
            onAdd:
            {

                dismissEditing();
                activeSheet = .reactions
            })
    }


    ///
    /// @fcn        CardDetailView.workingCardSnapshot
    /// @brief      Overlay working fields on the original record without losing hidden content
    /// @details    Keeps nil body/attachment values until edited and preserves future model fields
    /// @return     (KanbanCard) complete current record without submitting or saving it
    ///
    var workingCardSnapshot: KanbanCard
    {  /* Original record overlaid with all current editor fields */


        if isEditingLocked, let lockedSnapshot
        {
            return lockedSnapshot
        }

        var updated = card /* Complete record assembled from working editor state */

        updated.isEditingLocked = isEditingLocked
        updated.showsReactionsInPreviews = showsReactionsInPreviews
        updated.reactions = reactions
        updated.word = titleText
        updated.appearance = appearance
        updated.subtitleOverride = card.subtitleOverride == nil && subtitleText == card.subtitle ? nil : subtitleText
        updated.isTitleChecked = titleChecked
        updated.startDate = startDate
        updated.dueDate = dueDate
        updated.showsDueDateInList = showsDueDateInList
        updated.startDateKind = startDateKind
        updated.dueDateKind = dueDateKind
        updated.members = members
        updated.labelIDs = selectedLabelIDs
        updated.attachments = attachments.isEmpty && card.attachments == nil ? nil : attachments
        updated.coverAttachmentID = coverAttachmentID
        updated.sectionLayout = sectionLayout == CardSectionLayout() ? nil : sectionLayout
        updated.checklists = checklists
        updated.comments = comments
        updated.dismissedActivityIDs = dismissedActivityIDs
        updated.descriptionOverride = hasEditedDescription ? descriptionText : card.descriptionOverride
        if displayFormat == .card || displayFormat == .note
        {

            updated.presentation = presentation
        }

        if displayFormat == .divider || displayFormat != card.displayFormat || card.listDisplayFormat != nil
        {

            updated.displayFormat = displayFormat
        }

        return updated
    }


    var noteLocationLabel: some View
    {  /* Current personal List displayed in the Note header */


        SlideableHeaderText(text: currentListTitle)
        .font(.caption)
        .foregroundStyle(.secondary)
        .italic()
    }


    var isCurrentRecordSaved: Bool
    {  /* Bookmark state resolved for the record's current owner */


        movedNoteIsSaved ?? savedCardIDs.contains(recordID)
    }


    @ViewBuilder
    var locationControl: some View
    {  /* List-location picker adapted to Card or Note movement */


        if cardMovementAccess.move != nil
        {

            CardDestinationMenu(
                card: workingCardSnapshot,
                onMoved:
                {

                    hasMovedCard = true;
                    dismiss()
                }, locationTitle: currentListTitle)
        }
        else if presentation == .note, onMoveNoteToPersonalList != nil
        {


            personalListMenu
            {
                noteLocationLabel
            }
            .accessibilityLabel("Move Note from \(currentListTitle)")
        }
        else
        {

            moveCardMenu
            {
                noteLocationLabel
            }
            .accessibilityLabel("Move \(displayFormat.title.lowercased()) from \(currentListTitle)")
        }

    }


    ///
    /// @fcn        CardDetailView.descriptionEditingBinding
    /// @brief      Distinguish user-written text from generated Card display copy
    /// @details    Interface changes do not mark the body as edited
    /// @return     (Binding<String>) body editor binding
    ///
    var descriptionEditingBinding: Binding<String>
    {  /* Body draft binding that records explicit edits */

        Binding(
            get:
            {
                descriptionText
            },
            set:
            {

                hasEditedDescription = true
                descriptionText = $0
            }
        )
    }


    ///
    /// @fcn        CardDetailView.noteEditor
    /// @brief      Present a roomy writing-first interface for the same Card record
    /// @details    Keeps title/body editing immediate and exposes retained metadata through Details
    /// @return     (some View) accessible Note editor without a task-completion checkbox
    ///
    var noteEditor: some View
    {  /* Inline Note title and body editor */


        VStack(alignment: .leading, spacing: 18)
        {


            VStack(alignment: .leading, spacing: 18)
            {

                locationControl
                .accessibilityIdentifier("note.locationPicker")

                HStack(alignment: .firstTextBaseline, spacing: 8)
                {

                    ItemAppearanceMark(appearance: appearance)
                    TextField("Note title", text: $titleText, axis: .vertical).textInputAutocapitalization(.sentences)
                    .font(.largeTitle.weight(.bold))
                    .focused($focusedField, equals: .title)
                    .accessibilityLabel("Note title")
                    .onChange(of: titleText)
                    {
                        _, newValue in
                        syncCardState(title: newValue)
                    }

                }


                if let createdAt = card.createdAt
                {  /* Original Note creation timestamp displayed below its body */

                    NoteCreationDateLabel(createdAt: createdAt)
                    .accessibilityIdentifier("note.creationDate")
                }

            }
            .padding(.horizontal, appearance?.background == nil ? 0 : 20)
            .padding(.vertical, appearance?.background == nil ? 0 : 12)
            .itemBannerBackground(appearance)
            .padding(.horizontal, appearance?.background == nil ? 0 : -20)

            if reactions?.isEmpty == false
            {

                reactionStrip
            }


            RichTextEditor(
                placeholder: "Start writing...", text: descriptionEditingBinding,
                focus: richTextFocusBinding(for: .description), minimumHeight: 280
            )
            .accessibilityLabel("Note body")
            .onChange(of: descriptionText)
            {
                syncCardState()
            }


            if let cover = workingCardSnapshot.coverAttachment
            {

                selectedCoverPreview(cover)
                .accessibilityIdentifier("note.selectedCoverPreview")
            }

            if !workingCardSnapshot.attachmentsExcludingCover.isEmpty
            {


                attachmentGallery
            }

        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("plenact.noteEditor")
        .accessibilityIdentifier("plenact.noteEditor")
    }


    var noteAttachmentsSheet: some View
    {  /* Note attachment browser and import controls */

        NavigationStack
        {

            ScrollView
            {

                VStack(alignment: .leading, spacing: 16)
                {

                    if attachments.isEmpty
                    {

                        ContentUnavailableView("No attachments", systemImage: "paperclip")
                    }
                    else
                    {

                        if let cover = workingCardSnapshot.coverAttachment
                        {

                            selectedCoverPreview(cover)
                        }

                        attachmentGallery
                    }


                    Button("Add attachment", systemImage: "plus")
                    {

                        activeSheet = .attachmentSources
                    }
                    .frame(minHeight: 44)
                }
                .padding(16)
            }
            .navigationTitle("Note attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Done")
                    {
                        activeSheet = nil
                    }

                }

            }

        }
        .presentationDetents([.medium, .large])
    }


    var body: some View
    {  /* Full card-detail presentation */


        ScrollViewReader
        {
            scrollProxy in
            ZStack
            {

                Color(.systemGroupedBackground)
                .ignoresSafeArea()

                if isEditingLocked
                {

                    ReadOnlyCardContent(
                        card: workingCardSnapshot, labels: labelLibrary,
                        onOpenAttachment:
                        {
                            activeSheet = .attachmentPreview($0)
                        })
                }
                else if displayFormat == .divider
                {


                    VStack(alignment: .leading)
                    {


                        TextField("Section heading (optional)", text: $titleText, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .font(.title2.weight(.bold))
                        .focused($focusedField, equals: .title)
                        .submitLabel(.done)
                        .onSubmit
                        {
                            dismissEditing()
                        }
                        .onChange(of: titleText)
                        {
                            _, newValue in
                            syncCardState(title: newValue)
                        }

                        Text(
                                                                        "A named section includes everything beneath it until the next named section. Leave the heading blank for a simple line."
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                        if !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        {

                            Toggle(
                                                                                    "Collapse section",
                                                                                    isOn: Binding(
                                                                                        get:
                                                                                        {
                                                                                            appearance?.sectionCollapsed == true
                                                                                        },
                                                                                        set:
                                                                                        {
                                                                                            value in
                                                                                            var updated = appearance ?? ItemAppearance()
                                                                                            updated.sectionCollapsed = value
                                                                                            appearance = updated
                                                                                            syncCardState()
                                                                                        }))
                            Picker(
                                                                                    "Section color",
                                                                                    selection: Binding<ItemAccent?>(
                                                                                        get:
                                                                                        {
                                                                                            appearance?.accent
                                                                                        },
                                                                                        set:
                                                                                        {
                                                                                            value in
                                                                                            var updated = appearance ?? ItemAppearance()
                                                                                            updated.accent = value
                                                                                            appearance = updated.isEmpty ? nil : updated
                                                                                            syncCardState()
                                                                                        })
                            )
                            {

                                Text("Default").tag(ItemAccent?.none)
                                ForEach(ItemAccent.allCases, id: \.self)
                                {
                                    color in
                                    Text(color.rawValue.capitalized).tag(Optional(color))
                                }

                            }

                        }

                        Spacer(minLength: 0)
                    }

                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                }
                else
                {


                    ScrollView
                    {


                        VStack(alignment: .leading, spacing: 0)
                        {


                            if displayFormat == .picture
                            {

                                Button
                                {

                                    dismissEditing()
                                    activeSheet = .appearance
                                    showsAppearanceCover = true
                                }
                                label:
                                {

                                    ItemPicturePreview(attachment: workingCardSnapshot.coverAttachment)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    workingCardSnapshot.coverAttachment == nil ? "Choose picture" : "Change picture"
                                )
                                .disabled(onTitleToggle == nil)
                                .padding(16)
                            }

                            if presentation == .note
                            {


                                noteEditor
                            }


                            if presentation == .card || showsNoteDetails
                            {


                                Color.clear
                                .frame(height: 0)
                                .id("note.detailsStart")

                                if presentation == .card
                                {


                                    HStack(alignment: .center, spacing: 12)
                                    {


                                        Button(action: toggleCardTitle)
                                        {


                                            Image(systemName: titleChecked ? "checkmark.square.fill" : "square")
                                            .font(.title2)
                                            .foregroundStyle(titleChecked ? .blue : .secondary)
                                        }

                                        .buttonStyle(.plain)
                                        .accessibilityLabel(titleChecked ? "Uncheck card title" : "Check card title")

                                        VStack(alignment: .leading, spacing: 5)
                                        {

                                            HStack(alignment: .firstTextBaseline, spacing: 8)
                                            {

                                                ItemAppearanceMark(appearance: appearance)
                                                Group
                                                {

                                                    if editingHeaderField == .title
                                                    {

                                                        TextField("Card title", text: $titleText)
                                                        .textInputAutocapitalization(.sentences)
                                                        .focused($focusedField, equals: .title)
                                                        .task
                                                        {
                                                            focusedField = .title
                                                        }
                                                        .submitLabel(.done)
                                                        .onSubmit
                                                        {
                                                            dismissEditing()
                                                        }
                                                        .onChange(of: titleText)
                                                        {
                                                            _, value in
                                                            syncCardState(title: value)
                                                        }

                                                    }
                                                    else
                                                    {

                                                        SlideableHeaderText(
                                                            text: titleText.isEmpty ? "Card title" : titleText,
                                                            onTap:
                                                            {
                                                                editingHeaderField = .title
                                                            }
                                                        )
                                                        .accessibilityLabel("Card title, " + titleText)
                                                        .accessibilityIdentifier("card.readableTitle")
                                                    }

                                                }
                                                .font(.title2.weight(.bold))
                                                .layoutPriority(1)
                                            }


                                            if appearance?.hidesSubtitle(subtitleText) != true
                                            || editingHeaderField == .subtitle
                                            {

                                                Group
                                                {

                                                    if editingHeaderField == .subtitle || subtitleText.isEmpty
                                                    {

                                                        TextField("Card subtitle", text: $subtitleText)
                                                        .textInputAutocapitalization(.sentences)
                                                        .focused($focusedField, equals: .subtitle)
                                                        .task
                                                        {

                                                            if editingHeaderField == .subtitle
                                                            {

                                                                focusedField = .subtitle
                                                            }

                                                        }
                                                        .submitLabel(.done)
                                                        .onSubmit
                                                        {
                                                            dismissEditing()
                                                        }
                                                        .onChange(of: subtitleText)
                                                        {
                                                            _, value in
                                                            syncCardState(subtitle: value)
                                                        }

                                                    }
                                                    else
                                                    {

                                                        SlideableHeaderText(
                                                            text: subtitleText,
                                                            onTap:
                                                            {
                                                                editingHeaderField = .subtitle
                                                            }
                                                        )
                                                        .accessibilityLabel("Card subtitle, " + subtitleText)
                                                        .accessibilityIdentifier("card.readableSubtitle")
                                                    }

                                                }
                                                .font((appearance?.subtitleItalic ?? inheritedSubtitleItalic)
                                                      ? .subheadline.italic() : .subheadline)
                                                .foregroundStyle(.secondary)
                                            }

                                        }


                                        Spacer()
                                    }

                                    .padding(16)
                                    .itemBannerBackground(appearance)
                                }


                                //****************************************************************************//
                                // SECTION: Quick Actions                                                     //
                                //                                                                            //
                                //          Presents the primary actions available for the selected card      //
                                //****************************************************************************//
                                if presentation == .card && reactions?.isEmpty == false
                                {

                                    reactionStrip.padding(.horizontal, 16).padding(.vertical, 8)
                                }

                                ForEach(sectionLayout.sections)
                                {
                                    section in
                                    cardSection(section, using: scrollProxy)
                                }

                            }

                        }

                    }

                    .padding(.bottom, 12)
                    // Add scrollable clearance without shortening the visible card-detail viewport.
                    .contentMargins(.bottom, workspaceBottomBarHeight, for: .scrollContent)
                }

            }

            .safeAreaInset(edge: .top, spacing: 0)
            {


                HStack(spacing: 12)
                {


                    if presentation != .note || displayFormat == .divider
                    {

                        Button
                        {

                            dismiss()
                        }
                        label:
                        {

                            Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray5), in: Circle())
                            .contentShape(Circle())
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                    }


                    Spacer()

                    ImportantItemIndicator(
                        cardID: recordID, ownerID: currentPersonalCollectionID ?? checklistCollectionID)

                    if presentation == .card, displayFormat != .divider
                    {

                        locationControl
                        .frame(maxWidth: 180, minHeight: 44)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("card.locationPicker")
                        .disabled(isEditingLocked)
                    }


                    Group
                    {


                        if displayFormat != .divider
                        {

                            Button(action: toggleSavedCard)
                            {

                                Image(systemName: isCurrentRecordSaved ? "bookmark.fill" : "bookmark")
                                .font(.title2)
                                .foregroundStyle(isCurrentRecordSaved ? .orange : .primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                            }

                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                isCurrentRecordSaved ? "Remove from Saved" : "Save \(displayFormat.title.lowercased())")

                            if presentation == .card
                            {

                                addMenu(using: scrollProxy)
                                .foregroundStyle(.primary)
                                .disabled(isEditingLocked)
                            }

                        }

                        Menu
                        {

                            Button("Edit history", systemImage: "clock.arrow.circlepath")
                            {
                                activeSheet = .editHistory
                            }
                            .accessibilityIdentifier("card.editHistory")

                            if displayFormat != .divider
                            {

                                Button(
                                    isEditingLocked ? "Unlock editing" : "Lock editing",
                                    systemImage: isEditingLocked ? "lock.open" : "lock"
                                )
                                {

                                    setEditingLocked(!isEditingLocked)
                                }
                                .disabled(onTitleToggle == nil && onUpdateMovedNote == nil)
                                .accessibilityIdentifier("card.editingLockAction")
                            }

                            if !isEditingLocked
                            {

                                if displayFormat != .divider
                                {

                                    Button("Add reaction", systemImage: "face.smiling")
                                    {

                                        dismissEditing();
                                        activeSheet = .reactions
                                    }

                                    if let libraryImportance
                                    {

                                        Button(
                                            libraryImportance.contains(card.id)
                                            ? "Increase importance" : "Mark important", systemImage: "star.fill"
                                        )
                                        {

                                            libraryImportance.adjust(card.id, 1)
                                        }
                                        .disabled(libraryImportance.level(card.id) >= 5)
                                        if libraryImportance.contains(card.id)
                                        {

                                            Button("Decrease importance", systemImage: "star")
                                            {

                                                libraryImportance.adjust(card.id, -1)
                                            }

                                        }

                                    }

                                    Toggle(
                                                                                                            "Show reactions in previews",
                                                                                                            isOn: Binding(
                                                                                                                get:
                                                                                                                {
                                                                                                                    showsReactionsInPreviews != false
                                                                                                                },
                                                                                                                set:
                                                                                                                {
                                                                                                                    visible in
                                                                                                                    let previous = showsReactionsInPreviews
                                                                                                                    showsReactionsInPreviews = visible
                                                                                                                    if !syncCardState()
                                                                                                                    {
                                                                                                                        showsReactionsInPreviews = previous
                                                                                                                    }

                                                                                                                }))
                                    Toggle(
                                                                                                            "Show due date in lists",
                                                                                                            isOn: Binding(
                                                                                                                get:
                                                                                                                {
                                                                                                                    showsDueDateInList
                                                                                                                },
                                                                                                                set:
                                                                                                                {
                                                                                                                    visible in
                                                                                                                    let previous = showsDueDateInList
                                                                                                                    showsDueDateInList = visible
                                                                                                                    if !syncCardState()
                                                                                                                    {
                                                                                                                        showsDueDateInList = previous
                                                                                                                    }

                                                                                                                }))
                                }

                                if displayFormat == .card, appearance?.hidesSubtitle(subtitleText) == true
                                {

                                    Button("Add subtitle", systemImage: "text.badge.plus")
                                    {

                                        editingHeaderField = .subtitle
                                    }

                                }

                                Button("Appearance", systemImage: "paintpalette")
                                {

                                    dismissEditing()
                                    activeSheet = .appearance
                                }
                                .disabled(onTitleToggle == nil)

                                if displayFormat != .divider
                                {

                                    Button
                                    {

                                        richTextFocusedField = .description
                                    }
                                    label:
                                    {

                                        Label("Edit description", systemImage: "text.alignleft")
                                    }

                                    if cardMovementAccess.move != nil
                                    {

                                        CardDestinationMenu(
                                            card: workingCardSnapshot,
                                            onMoved:
                                            {

                                                hasMovedCard = true;
                                                dismiss()
                                            })
                                    }
                                    else
                                    {

                                        moveCardMenu
                                        {

                                            Label(
                                                                                                                                    "Move \(displayFormat.title.lowercased())",
                                                                                                                                    systemImage: "arrowshape.turn.up.right")
                                        }

                                    }

                                    Button
                                    {

                                        showsNoteDetails = true
                                        activityFilter = .all
                                    }
                                    label:
                                    {

                                        Label("Show all activity", systemImage: "clock.arrow.circlepath")
                                    }

                                }


                                if let onArchive, displayFormat != .divider
                                {  /* Available archive callback for an actionable record */


                                    Button
                                    {

                                        syncCardState()
                                        if let
                                        currentPersonalCollectionID, /* Current owner used to route relocated Note archiving */
                                        currentPersonalCollectionID != personalCollectionID
                                        {

                                            if onArchiveMovedNote?(currentPersonalCollectionID, workingCardSnapshot)
                                            == true
                                            {


                                                dismiss()
                                            }

                                        }
                                        else
                                        {

                                            onArchive()
                                            dismiss()
                                        }

                                    }
                                    label:
                                    {

                                        Label("Archive \(displayFormat.title)", systemImage: "archivebox")
                                    }

                                }


                                if onDelete != nil
                                {


                                    Button(role: .destructive)
                                    {

                                        showingDeleteConfirmation = true
                                    }
                                    label:
                                    {

                                        Label("Delete \(displayFormat.title)", systemImage: "trash")
                                    }

                                }

                            }

                        }
                        label:
                        {

                            Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }

                        .accessibilityLabel("\(displayFormat.title) actions")
                    }

                }

                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .itemBannerBackground(appearance)
                .background(Color(.systemGroupedBackground))
            }

            .modifier(
                LowerCornerBackShortcut(
                    action: (presentation != .note || displayFormat == .divider) ?
                    {
                        dismiss()
                    } : nil)
            )
            .safeAreaInset(edge: .bottom, spacing: 0)
            {

                if presentation == .note && displayFormat != .divider
                {

                    noteToolbar(using: scrollProxy)
                }

            }
            // Keep the Note's navigation toolbar at the screen bottom, beneath the keyboard.
            // The focused editor supplies its own accessory controls above the keyboard.
            .ignoresSafeArea(.keyboard, edges: presentation == .note && displayFormat != .divider ? .bottom : [])
            .onAppear
            {

                guard !card.isSectionDivider else
                {
                    return
                }

                libraryItemOpened(card.id)
                let owner =
                checklistCollectionID
                ?? checklistTypePlanningAccess?.document.weeks.first(where:
                    {

                        $0.startKey == checklistTypePlanningAccess?.document.currentWeekKey
                    })?.id
                if let owner
                {
                    ActivityRecentStore.remember(LibraryRecentItem(collectionID: owner, cardID: card.id))
                }

            }
            .onAppear
            {

                PlenactKeyboard.shared.setContext(
                    keyboardContextID,
                    actions: KeyboardCardActions(
                        exit:
                        {

                            dismissEditing();
                            syncCardState();
                            dismiss()
                        },
                        previous: keyboardNavigation.previous.map
                        {
                            action in
                            {

                                dismissEditing();
                                syncCardState();
                                action()
                            }

                        },
                        next: keyboardNavigation.next.map
                        {
                            action in
                            {

                                dismissEditing();
                                syncCardState();
                                action()
                            }

                        },
                        attachment:
                        {

                            guard !isEditingLocked else
                            {
                                return
                            }
                            ;
                            dismissEditing();
                            activeSheet = .attachmentSources
                        },
                        checklist:
                        {

                            guard !isEditingLocked else
                            {
                                return
                            }
                            ;
                            dismissEditing();
                            showsNoteDetails = true;

                            addChecklist(using: scrollProxy)
                        },
                        showsUpperBorder: true
                    ))
            }
            .onDisappear
            {
                PlenactKeyboard.shared.removeContext(keyboardContextID)
            }
            .onAppear
            {
                workspaceNoteVisibility(noteVisibilityID, presentation == .note && displayFormat != .divider)
            }
            .onDisappear
            {
                workspaceNoteVisibility(noteVisibilityID, false)
            }
            .onChange(of: displayFormat)
            {
                _, _ in
                workspaceNoteVisibility(noteVisibilityID, presentation == .note && displayFormat != .divider)
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .onChange(of: focusedField)
            {
                _, field in
                if field != nil
                {
                    richTextFocusedField = nil
                }

                if let editingHeaderField, field != editingHeaderField
                {
                    self.editingHeaderField = nil
                }

            }
            .onChange(of: selectedCoverPhoto)
            {
                _, photoItem in
                guard let photoItem else
                {
                    return
                }  /* Newly selected library media awaiting cover import */


                let requestID = UUID() /* Identity used to reject superseded cover imports */
                coverImportID = requestID
                Task
                {
                    await importPhotos(from: [photoItem], coverRequestID: requestID)
                }

            }
            .onChange(of: selectedPhotoItems)
            {
                _, photoItems in
                guard !photoItems.isEmpty else
                {


                    return
                }

                Task
                {

                    await importPhotos(from: photoItems)
                }

            }

            .alert("Attachment notice", isPresented: $showingAttachmentNotice)
            {

                Button("OK", role: .cancel)
                {

                }

            }
            message:
            {

                Text(attachmentNoticeMessage)
            }

            .alert(
                                    "Permanently delete this \(displayFormat.title.lowercased())?", isPresented: $showingDeleteConfirmation
            )
            {

                Button("Delete \(displayFormat.title)", role: .destructive, action: deleteCard)
                Button("Cancel", role: .cancel)
                {

                }

            }
            message:
            {

                Text(
                                                "This permanently deletes this \(displayFormat.title.lowercased()) and its description, checklists, comments, member and label assignments, and attachments. This cannot be undone."
                )
            }

            .sheet(item: $activeSheet)
            {
                sheet in
                switch sheet
                {


                case .editHistory:
                    CardEditHistorySheet(records: lastSavedHistoryCard.editHistory ?? [])

                case .date(let field): /* Date field selected for editing */
                    CardDateEditorSheet(
                        title: field.title,
                        date: field == .start ? startDate : dueDate,
                        kind: field == .start ? startDateKind : dueDateKind
                    )
                    {
                        value, kind in
                        saveDate(value, kind: kind, for: field)
                    }
                    .presentationDetents([.large])
                    .databaseActivityOverlay()

                case .reactions:
                    ItemReactionPicker(
                        selected: Set((reactions ?? []).filter
                            {
                                $0.authorID == reactionAuthorID
                            } .map(\.emoji)),
                        onChoose: toggleReaction)
                case .members:
                    CardMembersSheet(members: members, memberColors: memberColors)
                    {
                        updatedMembers in
                        members = updatedMembers
                        syncCardState(members: updatedMembers)
                    }

                    .presentationDetents([.medium, .large])
                    .databaseActivityOverlay()

                case .labels:
                    CardLabelsSheet(library: labelLibrary, selectedLabelIDs: selectedLabelIDs)
                    {

                    updatedLibrary, updatedLabelIDs in
                        labelLibrary = updatedLibrary
                        selectedLabelIDs = updatedLabelIDs

                        syncCardState(labelIDs: updatedLabelIDs)
                    }

                    .presentationDetents([.large])
                    .databaseActivityOverlay()

                case .attachmentSources:
                    CardAttachmentSourceSheet(
                        photoSelection: $selectedPhotoItems,
                        onAddLink:
                        {
                            activeSheet = .addLink
                        },
                        onPasteClipboard: addClipboardAttachment,
                        onComingSoon: showAttachmentSourceComingSoon,
                        onAddDrawing:
                        {
                            activeSheet = .addDrawing(DrawingCaptureDraft())
                        }
                    )
                    .databaseActivityOverlay()

                case .noteAttachments:
                    noteAttachmentsSheet
                    .databaseActivityOverlay()

                case .appearance:
                    ItemAppearanceSheet(
                        title: titleText,
                        appearance: appearance,
                        onOpenCover: displayFormat == .divider ? nil :
                        {
                            showsAppearanceCover = true
                        },
                        onOpenLayout:
                        {
                            showsLayoutEditor = true
                        },
                        displayFormat: displayFormat,
                        onSaveDisplay: saveDisplayAppearance
                    )
                    {
                        updated in
                        saveDisplayAppearance(updated, format: displayFormat)
                    }
                    .sheet(isPresented: $showsAppearanceCover)
                    {

                        cardCoverPanel
                        {
                            showsAppearanceCover = false
                        }

                    }
                    .sheet(isPresented: $showsLayoutEditor)
                    {

                        CardLayoutEditor(layout: sectionLayout)
                        {
                            updated in
                            let previous = sectionLayout
                            sectionLayout = updated
                            if syncCardState()
                            {
                                return true
                            }

                            sectionLayout = previous
                            return false
                        }

                    }


                case .cover:
                    cardCoverPanel
                    {
                        activeSheet = nil
                    }


                case .addDrawing(let draft):
                    DrawingCaptureEditor(initial: draft, onSave: addDrawingAttachment)
                    .databaseActivityOverlay()

                case .addLink:
                    CardLinkAttachmentSheet(onSave: addWebLink)
                    .databaseActivityOverlay()

                case .attachmentPreview(let attachment): /* Media selected for preview */
                    CardAttachmentPreview(
                        attachment: attachment,
                        onSaveDrawing:
                        {
                            replacement in
                            guard let index = attachments.firstIndex(where:
                                {
                                    $0.id == replacement.id
                                }) else
                            {

                                return false
                            }

                            let previous = attachments
                            attachments[index] = replacement
                            guard syncCardState(attachments: attachments) else
                            {
                                attachments = previous;
                                return false
                            }

                            return true
                        }
                    )
                    .databaseActivityOverlay()

                case .actionDetail(let checklistID, let itemID): /* Selected checklist and action IDs        */
                    if let checklist = checklists.first(where:
                        {  /* Checklist containing the selected action */


                            $0.id == checklistID
                        }), /* Owning checklist              */
                    let item = checklist.items.first(where:
                        {
                            $0.id == itemID
                        }
                    ), /* Selected action               */
                    case .actionDetail(let detail) = item.content
                    {  /* Reduced Action Detail payload */


                        ChecklistActionDetailView(
                            title: item.title,
                            detail: detail,
                            currentUserName: currentUserName
                        )
                        {
                            updatedDetail in
                            updateActionDetail(
                                checklistID: checklistID,
                                itemID: itemID,
                                detail: updatedDetail
                            )
                        }

                        .databaseActivityOverlay()
                    }
                    else
                    {

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
