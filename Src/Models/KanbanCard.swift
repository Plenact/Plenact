// --------------------------------------------------------------------------------------------------
// @file       KanbanCard.swift
// @brief      Canonical Card, Note, and divider records
// @details    Retains content, scheduling, checklists, media, reactions, locks, and compatibility
//             fields and optional edit history independently of any one presentation.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Represents a retained Card, Note, or section divider
///
/// @section    Purpose
///     Preserves identity, writing, checklists, scheduling, attachments, appearance, and
///     compatibility fields; optional editing lock protects content without changing its
///     presentation kind.
///
struct KanbanCard: Identifiable, Hashable, Codable, Sendable
{


    let id:                    Int          /* Stable numeric identifier for the card             */
    var editHistory: [CardEditRecord]? = nil  /* Saved content changes; absent on legacy records */
    var word:                  String       /* Display word shown as the card's title             */
    var listTitle:             String       /* Name of the list where the card resides            */
    var isDivider:             Bool         /* Whether this item is a movable section divider     */
    var isTitleChecked:        Bool         /* Whether the card's main title checkbox is selected */
    private var editingLocked: Bool? = nil  /* Missing means editable for older saved records     */

    var isEditingLocked: Bool
    {

        get
        {
            editingLocked == true
        }

        set
        {
            editingLocked = newValue ? true : nil
        }

    }

    var members:  [CardAssignee]  /* Registered and manual card assignments    */
    var labelIDs: [String]        /* Stable IDs of labels assigned to the card */

    var startDate:           Date?    /* Optional start date for the card                     */
    var dueDate:             Date?    /* Optional due date for the card                       */
    let createdAt:           Date?    /* Unknown for records created before timestamp support */
    var descriptionOverride: String?  /* Optional user-edited description                     */
    var startDateKind:       CardDateKind
    var dueDateKind:         CardDateKind
    var showsDueDateInList:  Bool
    var sectionLayout:       CardSectionLayout?
    var subtitleOverride:    String? /* Optional user-edited board subtitle                */

    var checklists:               [KanbanChecklist] /* List of checklists associated with the card        */
    var showsReactionsInPreviews: Bool? = nil
    var previewReactions:         [ItemEmojiReaction]
    {

        showsReactionsInPreviews != false && !isSectionDivider ? reactions ?? [] : []
    }

    var reactions:         [ItemEmojiReaction]? = nil
    var comments:          [KanbanComment]      /* Comments posted to the card's activity                  */
    var attachments:       [KanbanAttachment]?  /* Photo attachments stored with the card                  */
    var coverAttachmentID: UUID?                /* Explicitly chosen photo; nil disables this card's cover */
    var appearance:        ItemAppearance? = nil

    var dismissedActivityIDs:     Set<String>               /* Generated activity entries removed by the user        */
    var listDisplayFormat:        ItemDisplayFormat? = nil  /* Explicit override; nil preserves legacy rendering     */
    private var itemPresentation: ItemPresentation?         /* Optional persisted item kind for legacy compatibility */


    ///
    /// @fcn        KanbanCard.acceptsContentUpdate
    /// @brief      Reject content changes to a locked item while allowing an explicit unlock
    /// @details    Editable items accept normal owner updates. A locked item accepts an unchanged snapshot or a
    ///             snapshot differing only by its cleared lock flag, preventing stale editors from modifying content
    ///             as part of unlocking. Structural movement uses replacingLocation and retains the lock.
    ///
    /// @param[in]  updated  Proposed complete card value for this owner
    ///
    /// @return     (Bool) whether the proposed edit respects the current lock
    ///
    func acceptsContentUpdate(_ updated: KanbanCard) -> Bool
    {

        guard isEditingLocked else
        {
            return true
        }

        var unlocked = self
        unlocked.isEditingLocked = false
        var candidate = updated
        candidate.editHistory = editHistory
        return candidate == self || candidate == unlocked
    }


    /// Missing presentation remains a Card; the default needs no new persisted key.
    var presentation: ItemPresentation
    {  /* Effective item kind with the legacy Card fallback */

        get
        {
            itemPresentation ?? .card
        }

        set
        {

            itemPresentation = newValue == .card ? nil : newValue
            if listDisplayFormat == .card || listDisplayFormat == .note
            {

                listDisplayFormat = newValue == .note ? .note : .card
            }

        }

    }


    /// Explicit choices override historical dash titles without modifying retained content.
    var displayFormat: ItemDisplayFormat
    {

        get
        {

            listDisplayFormat
            ?? ((isDivider || Self.isDividerTitle(word)) ? .divider : (presentation == .note ? .note : .card))
        }

        set
        {

            if newValue == .card || newValue == .note || newValue == .title || newValue == .text
            {

                presentation = newValue == .card ? .card : .note
            }

            listDisplayFormat = newValue
        }

    }


    ///
    /// @fcn        KanbanCard.replacingLocation(id:listTitle:)
    /// @brief      Rebuild the same complete card under a destination-local identity and List title
    /// @details    Retains all supporting fields and the selected Card/Note presentation
    /// @param[in]  id         Identity allocated by the destination collection
    /// @param[in]  listTitle  Name of the destination List
    /// @return     (KanbanCard) complete record with only its location identity changed
    ///
    func replacingLocation(id: Int, listTitle: String) -> KanbanCard
    {


        KanbanCard(
            id: id,
            word: word,
            listTitle: listTitle,
            isDivider: isDivider,
            isTitleChecked: isTitleChecked,
            startDate: startDate,
            dueDate: dueDate,
            checklists: checklists,
            comments: comments,
            members: members,
            labelIDs: labelIDs,
            attachments: attachments,
            coverAttachmentID: coverAttachmentID,
            dismissedActivityIDs: dismissedActivityIDs,
            descriptionOverride: descriptionOverride,
            subtitleOverride: subtitleOverride,
            presentation: presentation,
            createdAt: createdAt,
            appearance: appearance,
            listDisplayFormat: listDisplayFormat,
            sectionLayout: sectionLayout,
            showsDueDateInList: showsDueDateInList,
            startDateKind: startDateKind,
            dueDateKind: dueDateKind,
            reactions: reactions,
            showsReactionsInPreviews: showsReactionsInPreviews,
            isEditingLocked: isEditingLocked,
            editHistory: editHistory
        )
    }


    ///
    /// @fcn        KanbanCard.coverAttachment
    /// @brief      Resolve the explicitly selected photo without automatic fallback
    /// @details    Missing attachments, nonphotos, and dividers do not produce a cover
    /// @return     (KanbanAttachment?) selected photo metadata
    ///
    var coverAttachment: KanbanAttachment?
    {  /* Valid featured photo resolved from this record's attachments */

        guard !isSectionDivider, let coverAttachmentID
        else
        {  /* Identity of the requested featured attachment                */


            return nil
        }


        return attachments?.first
        {
            $0.id == coverAttachmentID && $0.kind == .photo
        }

    }


    var attachmentsExcludingCover: [KanbanAttachment]
    {  /* Gallery records without the valid featured cover */

        let displayedCoverID = coverAttachment?.id /* Featured attachment omitted from the gallery     */
        return (attachments ?? []).filter
        {
            $0.id != displayedCoverID
        }

    }


    var galleryPhotos: [KanbanAttachment]
    {

        attachmentsExcludingCover.filter
        {
            $0.kind == .photo
        }

    }


    ///
    /// @fcn        KanbanCard.setPhotoCaption
    /// @brief      Update a particular photo attachment's caption
    /// @details    Validates the photo identity and normalizes caption input before changing the attachment array;
    ///             invalid targets throw.
    ///
    /// @param[in]  caption  Proposed photo caption text
    /// @param[in]  id       Stable draft or objective identity
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`. Errors from throwing
    ///             dependencies propagate unless handled within this operation.
    ///
    mutating func setPhotoCaption(_ caption: String, for id: UUID) throws
    {

        guard var current = attachments,
        let index = current.firstIndex(where:
            {
                $0.id == id && $0.kind == .photo
            })
        else
        {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        current[index].caption = text.isEmpty ? nil : text
        attachments = current
    }


    ///
    /// @fcn        KanbanCard.reorderGalleryPhotos
    /// @brief      Apply a validated photo-gallery order
    /// @details    Requires the supplied photo IDs to match the gallery contents and preserves nonphoto attachments.
    ///
    /// @param[in]  orderedIDs  Photo identities in the requested complete gallery order
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`. Errors from throwing
    ///             dependencies propagate unless handled within this operation.
    ///
    mutating func reorderGalleryPhotos(_ orderedIDs: [UUID]) throws
    {

        let photos = galleryPhotos
        guard orderedIDs.count == photos.count,
        Set(orderedIDs).count == orderedIDs.count,
        Set(orderedIDs) == Set(photos.map(\.id)),
        var current = attachments
        else
        {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        let byID = Dictionary(uniqueKeysWithValues: photos.map
            {
                ($0.id, $0)
            })
        let slots = current.indices.filter
        {
            current[$0].kind == .photo && current[$0].id != coverAttachment?.id
        }

        for (slot, id) in zip(slots, orderedIDs)
        {

            guard let photo = byID[id] else
            {

                throw CocoaError(.validationMissingMandatoryProperty)
            }

            current[slot] = photo
        }

        attachments = current
    }


    ///
    /// @fcn        KanbanCard.setCover(_:)
    /// @brief      Select an attached photo or disable the cover without removing media
    /// @details    Rejects nonphoto/missing identities and preserves the prior selection on error
    ///
    /// @param[in]  id  Attached photo identity, or nil to remove the cover
    ///
    /// @return     (Void) select an attached photo or disable the cover without removing media
    ///
    /// @throws     Validation error for an unavailable photo or divider
    ///
    mutating func setCover(_ id: UUID?) throws
    {


        if let id
        {  /* Requested attachment identity to validate as a cover */


            guard !isSectionDivider,
            attachments?.contains(where:
                {


                    $0.id == id && $0.kind == .photo
                }) == true
            else
            {


                throw CocoaError(.validationMissingMandatoryProperty)
            }

        }


        coverAttachmentID = id
    }


    ///
    /// @fcn        KanbanCard.useLibraryCover(_:)
    /// @brief      Attach and select a bundled illustration without replacing personal photos
    /// @details    Reuses an existing matching attachment; repeat selection does not create
    ///             duplicates
    ///
    /// @param[in]  image  Explicit user-selected library illustration
    ///
    /// @return     (Void) attach and select a bundled illustration without replacing personal
    ///             photos
    ///
    /// @throws     Validation error for a divider; original card remains unchanged
    ///
    mutating func useLibraryCover(_ image: ExampleCoverImage) throws
    {


        guard !isSectionDivider else
        {


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        let attachment =
        attachments?.first
        {

            $0.exampleImage == image && $0.kind == .photo
        }  /* Existing photo matching the requested example cover */

        ?? KanbanAttachment(mediaKind: .photo, exampleImage: image)

        if !(attachments ?? []).contains(where:
            {


                $0.id == attachment.id
            })
        {

            if attachments == nil
            {


                attachments = []
            }

            attachments?.append(attachment)
        }


        try setCover(attachment.id)
    }


    ///
    /// @fcn        KanbanCard.removeAttachment(_:)
    /// @brief      Remove attachment metadata and clear only its selected cover
    /// @details    Does not delete files or automatically select another attached photo
    ///
    /// @param[in]  id  Attachment identity belonging to this card
    ///
    /// @return     (Void) remove attachment metadata and clear only its selected cover
    ///
    mutating func removeAttachment(_ id: UUID)
    {


        attachments?.removeAll
        {
            $0.id == id
        }

        if coverAttachmentID == id
        {


            coverAttachmentID = nil
        }

    }


    ///
    /// @fcn        KanbanCard.isSectionDivider
    /// @brief      Determine whether this card represents a section divider
    /// @details    Explicit display format overrides the legacy divider flag and dash title
    ///
    /// @return     (Bool) whether the card should render and behave as a divider
    /// @post       Card state remains unchanged
    ///
    var isSectionDivider: Bool
    {  /* Effective separator display, including legacy records */

        displayFormat == .divider
    }


    ///
    /// @fcn        KanbanCard.namedDividerHeading(_:)
    /// @brief      Extract a heading from supported named-divider syntax
    /// @details    Trims input, requires at least three supported dash characters followed by
    ///             whitespace, and returns the remaining nonempty heading without changing the
    ///             title.
    ///
    /// @param[in]  title  Candidate card title
    ///
    /// @return     (String?) trimmed section heading, or nil when named-divider syntax does not
    ///             match
    ///
    static func namedDividerHeading(_ title: String) -> String?
    {

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = trimmed.firstIndex(where:
            {
                $0.isWhitespace
            }) else
        {
            return nil
        }

        let marker = trimmed[..<space]
        let dashes = CharacterSet(charactersIn: "-‐‑‒–—―−")
        guard marker.count >= 3, marker.unicodeScalars.allSatisfy(
            {
                dashes.contains($0)
            }) else
        {
            return nil
        }

        let heading = trimmed[space...].trimmingCharacters(in: .whitespacesAndNewlines)
        return heading.isEmpty ? nil : heading
    }


    var sectionHeading: String?
    {

        guard isSectionDivider else
        {
            return nil
        }

        if let heading = Self.namedDividerHeading(word)
        {
            return heading
        }

        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Self.isDividerTitle(trimmed) ? nil : trimmed
    }


    ///
    /// @fcn        KanbanCard.isDividerTitle
    /// @brief      Recognize the divider entry syntax
    /// @details    Trims the input before checking the dash-based syntax used to create plain and named dividers.
    ///
    /// @param[in]  title  Display title or proposed title text
    ///
    /// @return     (Bool) true for named-divider syntax or a supported plain dash separator
    ///
    static func isDividerTitle(_ title: String) -> Bool
    {

        if namedDividerHeading(title) != nil
        {
            return true
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)  /* Title without surrounding spaces */
        let dashCharacters = CharacterSet(charactersIn: "-‐‑‒–—―−")               /* Accepted divider dash characters */

        guard !trimmedTitle.isEmpty,
        trimmedTitle.unicodeScalars.allSatisfy(
            {
                dashCharacters.contains($0)
            })
        else
        {


            return false
        }


        return trimmedTitle.unicodeScalars.count >= 2 || trimmedTitle.contains("–") || trimmedTitle.contains("—")
        || trimmedTitle.contains("―")
    }


    ///
    /// @fcn        KanbanCard.init
    /// @brief      Initialize a kanban card with its core identity and state
    /// @details    Creates a board card with a stable identifier, displayed word, list membership,
    ///             and the per-card title checkbox state used in the detail view
    ///
    /// @param[in]  id                        Stable numeric identifier for the card
    /// @param[in]  word                      Display word shown as the card's title
    /// @param[in]  listTitle                 Name of the list where the card resides
    /// @param[in]  isDivider                 Whether this item is a section divider
    /// @param[in]  isTitleChecked            Whether the card's main title checkbox is selected
    /// @param[in]  startDate                 Optional start date for the card
    /// @param[in]  dueDate                   Optional due date for the card
    /// @param[in]  checklists                Checklist groups; nil selects the seeded defaults
    /// @param[in]  comments                  Activity comments associated with the card
    /// @param[in]  members                   Registered and manual card assignments
    /// @param[in]  labelIDs                  Stable identifiers of assigned labels
    /// @param[in]  attachments               Optional photo attachment metadata
    /// @param[in]  coverAttachmentID         Explicit cover photo identity; nil keeps the card text-only
    /// @param[in]  dismissedActivityIDs      Generated activity entries dismissed by the user
    /// @param[in]  descriptionOverride       Optional user-edited description
    /// @param[in]  subtitleOverride          Optional user-edited Board subtitle
    /// @param[in]  presentation              Card or writing-first Note interface
    /// @param[in]  createdAt                 Known creation time; nil preserves unknown legacy dates
    /// @param[in]  isEditingLocked           Whether content editing is protected until explicitly unlocked
    ///
    /// @param[in]  appearance                Optional item-specific appearance overrides
    /// @param[in]  listDisplayFormat         Optional explicit List preview format, leaving nil to inherit
    ///             the item presentation
    /// @param[in]  sectionLayout             Optional retained ordering and visibility of detail sections
    /// @param[in]  showsDueDateInList        Optional per-item due-date preview override
    /// @param[in]  startDateKind             Optional date-only or date-and-time interpretation of the start
    ///             value
    /// @param[in]  dueDateKind               Optional date-only or date-and-time interpretation of the due value
    /// @param[in]  reactions                 Retained authored emoji reactions for the item
    /// @param[in]  showsReactionsInPreviews  Optional override controlling reaction summaries in
    ///             List previews
    ///
    /// @return     (KanbanCard) configured card instance
    ///
    /// @pre        Supplied values are valid for the caller's Board state
    /// @post       The card retains supplied values; nil checklists receive the default groups
    ///
    init(
        id: Int, word: String, listTitle: String, isDivider: Bool = false, isTitleChecked: Bool = false,
        startDate: Date? = nil, dueDate: Date? = nil, checklists: [KanbanChecklist]? = nil,
        comments: [KanbanComment] = [], members: [CardAssignee] = [], labelIDs: [String] = [],
        attachments: [KanbanAttachment]? = nil, coverAttachmentID: UUID? = nil, dismissedActivityIDs: Set<String> = [],
        descriptionOverride: String? = nil, subtitleOverride: String? = nil, presentation: ItemPresentation = .card,
        createdAt: Date? = nil, appearance: ItemAppearance? = nil, listDisplayFormat: ItemDisplayFormat? = nil,
        sectionLayout: CardSectionLayout? = nil, showsDueDateInList: Bool? = nil, startDateKind: CardDateKind = .date,
        dueDateKind: CardDateKind = .date, reactions: [ItemEmojiReaction]? = nil, showsReactionsInPreviews: Bool? = nil,
        isEditingLocked: Bool = false, editHistory: [CardEditRecord]? = nil
    )
    {


        self.editHistory = editHistory
        self.editingLocked = isEditingLocked ? true : nil
        self.showsReactionsInPreviews = showsReactionsInPreviews
        self.reactions = reactions?.isEmpty == true ? nil : reactions
        self.id = id                          /* Stable numeric identifier for the card             */
        self.word = word                      /* Display word shown as the card's title             */
        self.listTitle = listTitle            /* Name of the list where the card resides            */
        self.isDivider = isDivider            /* Whether this item renders as a section divider     */
        self.isTitleChecked = isTitleChecked  /* Whether the card's main title checkbox is selected */
        self.startDate = startDate            /* Optional start date for the card                   */
        self.startDateKind = startDateKind
        self.dueDateKind = dueDateKind
        self.showsDueDateInList = showsDueDateInList ?? Self.defaultDueDateVisibility()
        self.dueDate = dueDate /* Optional due date for the card                     */
        self.createdAt = createdAt
        self.comments = comments        /* Array of comments associated with the card */
        self.members = members          /* Names of users assigned to the card        */
        self.labelIDs = labelIDs        /* Stable IDs of labels assigned to the card  */
        self.attachments = attachments  /* Photo attachment metadata for the card     */
        self.coverAttachmentID = coverAttachmentID
        self.dismissedActivityIDs = dismissedActivityIDs  /* Set of activity IDs that were dismissed by user */
        self.descriptionOverride = descriptionOverride    /* Optional user-edited description                */
        self.subtitleOverride = subtitleOverride          /* Optional user-edited subtitle                   */
        let retainedPresentation =
        [.note, .title, .text].contains(listDisplayFormat)
        ? ItemPresentation.note : (listDisplayFormat == .card ? .card : presentation)
        self.itemPresentation = retainedPresentation == .card ? nil : retainedPresentation
        self.appearance = appearance?.isEmpty == true ? nil : appearance
        self.sectionLayout = sectionLayout
        self.listDisplayFormat = listDisplayFormat
        self.checklists =
        checklists ?? [
            KanbanChecklist(
                title: "Focus",
                items: [
                                            "Gather the important bits", "Make it look intentional",
                                            "Celebrate the surprisingly good result"
                ], completed: id % 4),
            KanbanChecklist(
                title: "Plan", items: ["Choose the next useful step", "Stop building", "Start producing"],
                completed: 1),
            KanbanChecklist(title: "Routine", items: ["Home", "Gym", "Work"])
        ]
    }


    ///
    /// @fcn        KanbanCard.init(from:)
    /// @brief      Decode current typed assignments or migrate legacy member strings
    /// @details    Existing `[String]` members become manual assignees; typed directory references
    ///             retain their stable user IDs
    ///
    /// @param[in]  decoder  Decoder containing a current or previously saved Board card
    ///
    /// @return     (KanbanCard) decoded card with preserved member assignments
    ///
    /// @throws     DecodingError when required card identity or content is invalid
    ///
    init(from decoder: Decoder) throws
    {


        let container = try decoder.container(keyedBy: CodingKeys.self)  /* Card fields                        */
        let decodedMembers: [CardAssignee]                               /* Typed or migrated card assignments */

        if let typedMembers = try? container.decode([CardAssignee].self, forKey: .members)
        {  /* Current typed representation */


            decodedMembers = typedMembers /* Keep registered identity references */
        }
        else
        {


            let legacyMembers = try container.decodeIfPresent([String].self, forKey: .members) ?? [] /* Legacy names */

            decodedMembers = legacyMembers.map(CardAssignee.manual) /* Migrate old names as manual entries */
        }


        self.init(
            id: try container.decode(Int.self, forKey: .id),
            word: try container.decode(String.self, forKey: .word),
            listTitle: try container.decode(String.self, forKey: .listTitle),
            isDivider: try container.decodeIfPresent(Bool.self, forKey: .isDivider) ?? false,
            isTitleChecked: try container.decodeIfPresent(Bool.self, forKey: .isTitleChecked) ?? false,
            startDate: try container.decodeIfPresent(Date.self, forKey: .startDate),
            dueDate: try container.decodeIfPresent(Date.self, forKey: .dueDate),
            checklists: try container.decodeIfPresent([KanbanChecklist].self, forKey: .checklists),
            comments: try container.decodeIfPresent([KanbanComment].self, forKey: .comments) ?? [],
            members: decodedMembers,
            labelIDs: try container.decodeIfPresent([String].self, forKey: .labelIDs) ?? [],
            attachments: try container.decodeIfPresent([KanbanAttachment].self, forKey: .attachments),
            coverAttachmentID: try container.decodeIfPresent(UUID.self, forKey: .coverAttachmentID),
            dismissedActivityIDs: try container.decodeIfPresent(Set<String>.self, forKey: .dismissedActivityIDs) ?? [],
            descriptionOverride: try container.decodeIfPresent(String.self, forKey: .descriptionOverride),
            subtitleOverride: try container.decodeIfPresent(String.self, forKey: .subtitleOverride),
            presentation: try container.decodeIfPresent(ItemPresentation.self, forKey: .itemPresentation) ?? .card,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt),
            appearance: try container.decodeIfPresent(ItemAppearance.self, forKey: .appearance),
            listDisplayFormat: try container.decodeIfPresent(ItemDisplayFormat.self, forKey: .listDisplayFormat),
            sectionLayout: try container.decodeIfPresent(CardSectionLayout.self, forKey: .sectionLayout),
            showsDueDateInList: try container.decodeIfPresent(Bool.self, forKey: .showsDueDateInList) ?? true,
            startDateKind: try container.decodeIfPresent(CardDateKind.self, forKey: .startDateKind) ?? .date,
            dueDateKind: try container.decodeIfPresent(CardDateKind.self, forKey: .dueDateKind) ?? .date,
            reactions: try container.decodeIfPresent([ItemEmojiReaction].self, forKey: .reactions),
            showsReactionsInPreviews: try container.decodeIfPresent(Bool.self, forKey: .showsReactionsInPreviews),
            isEditingLocked: try container.decodeIfPresent(Bool.self, forKey: .editingLocked) ?? false
        )
        editHistory = try container.decodeIfPresent([CardEditRecord].self, forKey: .editHistory)
    }


    ///
    /// Identifies persisted card fields for legacy and typed assignment decoding
    ///
    /// @section    Purpose
    ///     Preserve established Board JSON keys while upgrading only the member value shape
    ///
    private enum CodingKeys: String, CodingKey
    {


        case id
        case editHistory
        case word
        case listTitle
        case isDivider
        case isTitleChecked
        case startDate
        case dueDate
        case showsDueDateInList
        case startDateKind
        case dueDateKind
        case createdAt
        case checklists
        case reactions
        case showsReactionsInPreviews
        case editingLocked
        case comments
        case members
        case labelIDs
        case attachments
        case coverAttachmentID
        case dismissedActivityIDs
        case descriptionOverride
        case subtitleOverride
        case itemPresentation
        case listDisplayFormat
        case appearance
        case sectionLayout
    }


    /// Human-readable label for the card's start date
    ///
    /// @fcn        KanbanCard.startDateLabel
    /// @brief      Provide the start-date badge text
    /// @details    Formats the optional start date for compact Board display
    ///
    /// @return     (String) formatted date, or "Today" when no start date is set
    /// @post       Card dates are unchanged
    ///
    var startDateLabel: String
    {  /* Start-date badge text or default */


        guard let startDate else
        {  /* No explicit start date */


            return ""
        }


        return startDateKind.label(for: startDate)
    }


    /// Human-readable label for the card's due date
    ///
    /// @fcn        KanbanCard.dueDateLabel
    /// @brief      Provide the due-date badge text
    /// @details    Formats the optional due date for compact Board display
    ///
    /// @return     (String) formatted date, or "Tomorrow" when no due date is set
    /// @post       Card dates are unchanged
    ///
    var dueDateLabel: String
    {  /* Due-date badge text or default */


        guard let dueDate else
        {  /* No explicit due date */


            return ""
        }


        return dueDateKind.label(for: dueDate)
    }


    /// Shared formatter used to render card date labels
    private static let dateFormatter: DateFormatter =
    {  /* Shared date-only display formatter */


        let formatter = DateFormatter() /* Formatter used for card date labels */

        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return formatter
    }()


    /// Short supporting copy shown beneath the card title
    ///
    /// @fcn        KanbanCard.subtitle
    /// @brief      Resolve the card's supporting Board text
    /// @details    Uses the edited subtitle when present and otherwise derives sample text
    ///
    /// @return     (String) supporting text shown beneath the card title
    /// @post       Card state is unchanged
    ///
    var subtitle: String
    {  /* Supporting card text or user override */

        if let subtitleOverride
        {  /* Explicitly edited subtitle            */


            return subtitleOverride
        }


        return [
                        "A small idea with suspiciously large ambitions", "Make progress before the coffee gets cold",
                        "A practical plan, lightly seasoned with chaos", "One more useful thing for today's board",
                        "Future success, pending a snack break"
        ] [id % 5]
    }


    /// Checklist labels used by the card detail presentation
    ///
    /// @fcn        KanbanCard.checklistItems
    /// @brief      Return action titles from the first checklist
    /// @details    Provides the compact card-summary checklist surface
    ///
    /// @return     ([String]) action titles, or an empty array when no checklist exists
    /// @post       Checklist state is unchanged
    ///
    var checklistItems: [String]
    {  /* Titles from the first checklist */

        checklists.first?.items.map(\.title) ?? []
    }


    /// Number of checklist items shown as complete for this sample card
    ///
    /// @fcn        KanbanCard.completedChecklistItems
    /// @brief      Count completed actions in the first checklist
    /// @details    Derives the compact card progress count from its checklist records
    ///
    /// @return     (Int) completed action count, or zero when no checklist exists
    /// @post       Checklist state is unchanged
    ///
    var completedChecklistItems: Int
    {  /* Completion count for the first checklist */

        checklists.first?.completed ?? 0
    }


    /// Number of sample comments shown on the board card
    ///
    /// @fcn        KanbanCard.commentCount
    /// @brief      Count the card's comments
    /// @details    Reports the number of user-authored comment records
    ///
    /// @return     (Int) number of comments associated with the card
    /// @post       Comment state is unchanged
    ///
    var commentCount: Int
    {  /* Number of activity comments */

        comments.count
    }


    /// Indicates whether the sample card displays a due-date badge
    ///
    /// @fcn        KanbanCard.hasDueDate
    /// @brief      Determine whether the card has a due date
    /// @details    Exposes due-date presence for Board badge presentation
    ///
    /// @return     (Bool) whether a due date is set
    /// @post       Card state is unchanged
    ///
    var hasDueDate: Bool
    {
        dueDate != nil
    }


    /// The badge is derived only from a stored due date and this card's saved display preference.
    var listDueDateLabel: String?
    {
        showsDueDateInList && hasDueDate ? dueDateLabel : nil
    }


    ///
    /// @fcn        KanbanCard.dueDateBadge
    /// @brief      Build the due-date badge for this card's context
    /// @details    Uses the represented list date and calendar to decide whether a due badge is meaningful; returns
    ///             nil when it should be omitted.
    ///
    /// @param[in]  listDate  Calendar date represented by the owning list, when available
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     ((label: String, systemImage: String)?) due label and symbol, or nil when the list context already
    ///             supplies the date
    ///
    /// @note       Omit a date already supplied by the owning list, while retaining any explicit time.
    ///
    func dueDateBadge(on listDate: Date?, calendar: Calendar = .current) -> (label: String, systemImage: String)?
    {

        guard showsDueDateInList, let dueDate else
        {
            return nil
        }

        let matchesListDay =
        dueDateKind.includesDate && listDate.map
        {
            calendar.isDate(dueDate, inSameDayAs: $0)
        }
        == true
        if matchesListDay || dueDateKind == .time
        {

            guard dueDateKind.includesTime else
            {
                return nil
            }

            return (CardDateKind.time.label(for: dueDate), "clock")
        }

        return (dueDateLabel, "calendar")
    }


    ///
    /// @fcn        KanbanCard.usesTimeOnlySchedule
    /// @brief      Determine whether schedule badges can omit the date
    /// @details    Compares stored schedule precision and the represented list day before choosing time-only
    ///             presentation.
    ///
    /// @param[in]  listDate  Calendar date represented by the owning list, when available
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (Bool) true when schedule labels can omit a redundant calendar date in this list context
    ///
    func usesTimeOnlySchedule(on listDate: Date?, calendar: Calendar = .current) -> Bool
    {

        guard let listDate else
        {
            return false
        }

        let dates = [(startDate, startDateKind), (dueDate, dueDateKind)].compactMap
        {
            date, kind in
            date.map
            {
                ($0, kind)
            }

        }

        return !dates.isEmpty
        && dates.allSatisfy
        {

            $0.1 == .dateAndTime && calendar.isDate($0.0, inSameDayAs: listDate)
        }

    }


    ///
    /// @fcn        KanbanCard.scheduleBadges
    /// @brief      Build the applicable start and due schedule badges
    /// @details    Uses date precision and list context to retain useful schedule information without redundant date
    ///             text.
    ///
    /// @param[in]  listDate  Calendar date represented by the owning list, when available
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     ([CardScheduleBadge]) applicable start and due badges for the represented list date
    ///
    /// @note       Presentation-only schedule labels for a card in a dated Day or Week list.
    ///
    func scheduleBadges(on listDate: Date?, calendar: Calendar = .current) -> [CardScheduleBadge]
    {

        guard showsDueDateInList else
        {
            return []
        }

        guard listDate != nil else
        {

            guard let badge = dueDateBadge(on: nil, calendar: calendar) else
            {
                return []
            }

            return [CardScheduleBadge(title: "", value: badge.label, systemImage: badge.systemImage)]
        }

        var entries: [(title: String, date: Date, kind: CardDateKind)] = []
        if let startDate
        {
            entries.append(("Start", startDate, startDateKind))
        }

        if let dueDate
        {
            entries.append(("Finish", dueDate, dueDateKind))
        }

        // A date-only schedule adds no information when every date is already the list's day.
        if let listDate, !entries.isEmpty,
        entries.allSatisfy(
            {

                $0.kind == .date && calendar.isDate($0.date, inSameDayAs: listDate)
            })
        {

            return []
        }

        let sameDayTimes = usesTimeOnlySchedule(on: listDate, calendar: calendar)
        if sameDayTimes
        {

            return entries.map
            {

                CardScheduleBadge(
                    title: $0.title, value: CardDateKind.time.label(for: $0.date),
                    systemImage: $0.title == "Start" ? "clock" : "checkmark.circle")
            }

        }

        if entries.count == 2
        {

            return entries.map
            {

                CardScheduleBadge(
                    title: $0.title == "Start" ? "Start date" : "Due date",
                    value: $0.kind.label(for: $0.date), systemImage: $0.kind == .time ? "clock" : "calendar")
            }

        }

        if dueDate == nil, let startDate
        {

            return [
                CardScheduleBadge(
                    title: "Start date", value: startDateKind.label(for: startDate),
                    systemImage: startDateKind == .time ? "clock" : "calendar")
            ]
        }

        guard let badge = dueDateBadge(on: listDate, calendar: calendar) else
        {
            return []
        }

        return [CardScheduleBadge(title: "", value: badge.label, systemImage: badge.systemImage)]
    }


    ///
    /// @fcn        KanbanCard.defaultDueDateVisibility
    /// @brief      Read the default due-date badge preference
    /// @details    Loads the stored display preferences and uses their due-date visibility setting for new
    ///             presentation decisions.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Bool) configured default visibility of due-date badges
    ///
    static func defaultDueDateVisibility(from defaults: UserDefaults = .standard) -> Bool
    {

        PlanPreferencesStore.load(from: defaults).showsDueDatesOnNewCards
    }


    /// Humorous context paragraph shown in the card detail view
    ///
    /// @fcn        KanbanCard.funParagraph
    /// @brief      Resolve the card's descriptive text
    /// @details    Prefers the user's description override to generated sample context
    ///
    /// @return     (String) description shown for the card
    /// @post       Card state is unchanged
    ///
    var funParagraph: String
    {  /* User description or generated sample context */


        if let descriptionOverride
        {  /* User-authored description */


            return descriptionOverride
        }


        let templates: [(String, String) -> String] = [ /* Generated card-context templates */
            {
                word, title in
                                        "Deep within the \(title) list, a \(word) staged a one-creature protest, demanding better lighting and a snack table. Management is 'reviewing the request', which is corporate for 'ignoring it politely'."
            },
            {
                word, title in
                                        "Legend has it that this \(word) was smuggled onto the \(title) board during a coffee run and has since filed three noise complaints against the stapler."
            },
            {
                word, title in
                                        "Nobody remembers hiring the \(word), yet here it sits on the \(title) list, quietly rearranging sticky notes into passive-aggressive haiku."
            },
            {
                word, title in
                                        "According to office folklore, the \(word) on the \(title) list once won a staring contest with the printer and hasn't blinked since."
            },
            {
                word, title in
                                        "The \(word) insists it is 'just visiting' the \(title) list, despite having set up a tiny desk, a tinier chair, and a nameplate that reads 'Regional Manager'."
            },
            {
                word, title in
                                        "Reports from the \(title) list describe a \(word) attempting to unionize the paperclips, citing 'unbearable working conditions near the shredder'."
            },
            {
                word, title in
                                        "This \(word) arrived on the \(title) list via interoffice mail, addressed to 'Whoever Needs the Most Chaos Today', and promptly took over the group chat."
            },
            {
                word, title in
                                        "Witnesses on the \(title) list swear the \(word) can predict meetings that will run long, mostly because it brings its own pillow."
            },
            {
                word, title in
                                        "The \(word) has been spotted on the \(title) list rehearsing an acceptance speech for an award that does not exist, in front of an audience that also does not exist."
            },
            {
                word, title in
                                        "Somewhere between the third and fourth cup of coffee, a \(word) wandered onto the \(title) list and decided it was now in charge of snack inventory."
            }
        ]

        let template = templates[id % templates.count] /* Deterministic template for this card */

        return template(word, listTitle)
    }

}
