// --------------------------------------------------------------------------------------------------
// @file       Models.swift
// @brief      Domain models and deterministic sample data for the Plenact board
// @details    Defines cards, lists, derived display values, weekday starter content, and optional
//             synthetic personal-list examples that create independent unsaved collection drafts
//
// @notes      Sample data is deterministic so previews and UI behavior remain reproducible
//
// @section    Opens
//     Consider separating persistence, collection, and sample-data models into focused files
//
// --------------------------------------------------------------------------------------------------
import Foundation


// -------------------------------------- MARK: - Card Model ------------------------------------ //


///
/// Identifies whether a card assignment references a registered demo account or a manual name
///
/// @section    Purpose
///     Keep directory-backed identity distinct from free-text assignees during migration and sync
///
enum CardAssigneeKind: String, Codable, Sendable {

    case registeredUser   /* Stable server user reference */
    case manual           /* User-entered display name     */
}


///
/// Represents one person associated with a card
///
/// @section    Purpose
///     Preserve a stable registered-user reference or a manual display name without conflating them
///
struct CardAssignee: Identifiable, Hashable, Codable, ExpressibleByStringLiteral, Sendable {

    let id:          UUID               /* Stable assignment row ID */
    let kind:        CardAssigneeKind   /* Registered or manual     */
    let userID:      String?            /* Stable registered user ID */
    var displayName: String             /* Name shown on the card    */


    ///
    /// @fcn        CardAssignee.init(id:kind:userID:displayName:)
    /// @brief      Initialize a typed card assignee
    /// @details    Stores registered identity separately from its user-facing display name
    ///
    /// @param[in]  id           Stable assignment identity
    /// @param[in]  kind         Registered-user or manual assignment kind
    /// @param[in]  userID       Stable account ID when kind is registeredUser
    /// @param[in]  displayName  Name shown in card and member views
    ///
    /// @return     (CardAssignee) configured card assignment
    ///
    init(id: UUID = UUID(), kind: CardAssigneeKind, userID: String? = nil, displayName: String) {

        self.id          = id
        self.kind        = kind
        self.userID      = userID
        self.displayName = displayName
    }


    ///
    /// @fcn        CardAssignee.manual(_:)
    /// @brief      Create a free-text assignment
    /// @details    Marks the value as manual so it cannot be mistaken for a directory account
    ///
    /// @param[in]  displayName  User-entered person name
    ///
    /// @return     (CardAssignee) manual assignment with a stable local identity
    ///
    static func manual(_ displayName: String) -> CardAssignee {

        CardAssignee(kind: .manual, displayName: displayName)
    }


    ///
    /// @fcn        CardAssignee.registered(userID:displayName:)
    /// @brief      Create a directory-backed assignment
    /// @details    Uses the stable server user ID as the durable account reference
    ///
    /// @param[in]  userID       Stable ID returned by the authenticated user directory
    /// @param[in]  displayName  Current directory display name cached for offline rendering
    ///
    /// @return     (CardAssignee) registered-user assignment
    ///
    static func registered(userID: String, displayName: String) -> CardAssignee {

        CardAssignee(kind: .registeredUser, userID: userID, displayName: displayName)
    }


    ///
    /// @fcn        CardAssignee.init(stringLiteral:)
    /// @brief      Preserve source compatibility for existing string-based starter members
    /// @details    Converts a string literal into an explicitly manual assignment
    ///
    /// @param[in]  value  User-entered or seeded display name
    ///
    /// @return     (CardAssignee) manual assignment with a stable identity
    ///
    init(stringLiteral value: String) {

        self = .manual(value)
    }
}


/// Selects an item's interface without changing its identity or retained content.
enum ItemPresentation: String, Codable, CaseIterable, Identifiable, Sendable {
    case card
    case note

    var id: String { rawValue } /* Stable item-kind identity */
    var title: String { self == .note ? "Note" : "Card" } /* User-facing name of the item kind */
}


///
/// Represents one card displayed on a kanban list
///
/// @section    Purpose
///     Keep one item's identity and content together across Card and Note presentations
///
/// @note   Derived values are deterministic so the board and previews remain reproducible
///
struct KanbanCard: Identifiable, Hashable, Codable, Sendable {

    let id:                   Int                 /* Stable numeric identifier for the card             */
    var word:                 String              /* Display word shown as the card's title             */
    var listTitle:            String              /* Name of the list where the card resides            */
    var isDivider:            Bool                /* Whether this item is a movable section divider     */
    var isTitleChecked:       Bool                /* Whether the card's main title checkbox is selected */
    var members:              [CardAssignee]      /* Registered and manual card assignments             */
    var labelIDs:             [String]            /* Stable IDs of labels assigned to the card          */

    var startDate:            Date?               /* Optional start date for the card                   */
    var dueDate:              Date?               /* Optional due date for the card                     */
    let createdAt:            Date?               /* Unknown for records created before timestamp support */
    var descriptionOverride:  String?             /* Optional user-edited description                   */
    var subtitleOverride:     String?             /* Optional user-edited board subtitle                */

    var checklists:           [KanbanChecklist]   /* List of checklists associated with the card        */
    var comments:             [KanbanComment]     /* Comments posted to the card's activity             */
    var attachments:          [KanbanAttachment]? /* Photo attachments stored with the card             */
    var coverAttachmentID:    UUID?              /* Explicitly chosen photo; nil disables this card's cover */

    var dismissedActivityIDs: Set<String>         /* Generated activity entries removed by the user     */
    private var itemPresentation: ItemPresentation? /* Optional persisted item kind for legacy compatibility */

    /// Missing presentation remains a Card; the default needs no new persisted key.
    var presentation: ItemPresentation { /* Effective item kind with the legacy Card fallback */
        get { itemPresentation ?? .card }
        set { itemPresentation = newValue == .card ? nil : newValue }
    }


    ///
    /// @fcn        KanbanCard.replacingLocation(id:listTitle:)
    /// @brief      Rebuild the same complete card under a destination-local identity and List title
    /// @details    Retains all supporting fields and the selected Card/Note presentation
    /// @param[in]  id        Identity allocated by the destination collection
    /// @param[in]  listTitle Name of the destination List
    /// @return     (KanbanCard) complete record with only its location identity changed
    ///
    func replacingLocation(id: Int, listTitle: String) -> KanbanCard {

        KanbanCard(
            id:                   id,
            word:                 word,
            listTitle:            listTitle,
            isDivider:            isDivider,
            isTitleChecked:       isTitleChecked,
            startDate:            startDate,
            dueDate:              dueDate,
            checklists:           checklists,
            comments:             comments,
            members:              members,
            labelIDs:             labelIDs,
            attachments:          attachments,
            coverAttachmentID:    coverAttachmentID,
            dismissedActivityIDs: dismissedActivityIDs,
            descriptionOverride:  descriptionOverride,
            subtitleOverride:     subtitleOverride,
            presentation:         presentation,
            createdAt:            createdAt
        )
    }

    ///
    /// @fcn        KanbanCard.coverAttachment
    /// @brief      Resolve the explicitly selected photo without automatic fallback
    /// @details    Missing attachments, nonphotos, and dividers do not produce a cover
    /// @return     (KanbanAttachment?) selected photo metadata
    ///
    var coverAttachment: KanbanAttachment? { /* Valid featured photo resolved from this record's attachments */
        guard !isSectionDivider, let coverAttachmentID else { /* Identity of the requested featured attachment */

            return nil
        }

        return attachments?.first { $0.id == coverAttachmentID && $0.kind == .photo }
    }

    var attachmentsExcludingCover: [KanbanAttachment] { /* Gallery records without the valid featured cover */
        let displayedCoverID = coverAttachment?.id /* Featured attachment omitted from the gallery */
        return (attachments ?? []).filter { $0.id != displayedCoverID }
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
    mutating func setCover(_ id: UUID?) throws {

        if let id { /* Requested attachment identity to validate as a cover */

            guard !isSectionDivider, attachments?.contains(where: {

                $0.id == id && $0.kind == .photo
            }) == true else {

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
    mutating func useLibraryCover(_ image: ExampleCoverImage) throws {

        guard !isSectionDivider else {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        let attachment = attachments?.first { $0.exampleImage == image && $0.kind == .photo } /* Existing photo matching the requested example cover */
            ?? KanbanAttachment(mediaKind: .photo, exampleImage: image)

        if !(attachments ?? []).contains(where: {

            $0.id == attachment.id
        }) {
            if attachments == nil {

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
    mutating func removeAttachment(_ id: UUID) {

        attachments?.removeAll { $0.id == id }
        if coverAttachmentID == id {

            coverAttachmentID = nil
        }
    }

    ///
    /// @fcn        KanbanCard.isSectionDivider
    /// @brief      Determine whether this card represents a section divider
    /// @details    Combines the explicit divider flag with recognition of the displayed marker
    ///
    /// @return     (Bool) whether the card should render and behave as a divider
    /// @post       Card state remains unchanged
    ///
    var isSectionDivider: Bool { /* Combined divider flag and recognized marker */
        isDivider || Self.isDividerTitle(word)
    }


    ///
    /// @fcn        KanbanCard.isDividerTitle(_:)
    /// @brief      Recognize a divider marker in a card title
    /// @details    Accepts supported dash characters, including iOS smart-punctuation variants
    ///
    /// @param[in]  title  Candidate card title
    ///
    /// @return     (Bool) whether the title is a recognized divider marker
    ///
    /// @post       The title and card state remain unchanged
    ///
    static func isDividerTitle(_ title: String) -> Bool {

        let trimmedTitle   = title.trimmingCharacters(in: .whitespacesAndNewlines) /* Title without surrounding spaces */
        let dashCharacters = CharacterSet(charactersIn: "-‐‑‒–—―−") /* Accepted divider dash characters */

        guard !trimmedTitle.isEmpty,
              trimmedTitle.unicodeScalars.allSatisfy({ dashCharacters.contains($0) }) else {
                
            return false
        }

        return trimmedTitle.unicodeScalars.count >= 2 || trimmedTitle.contains("–") || trimmedTitle.contains("—") || trimmedTitle.contains("―")
    }


    ///
    /// @fcn        KanbanCard.init
    /// @brief      Initialize a kanban card with its core identity and state
    /// @details    Creates a board card with a stable identifier, displayed word, list membership,
    ///             and the per-card title checkbox state used in the detail view
    ///
    /// @param[in]  id                    Stable numeric identifier for the card
    /// @param[in]  word                  Display word shown as the card's title
    /// @param[in]  listTitle             Name of the list where the card resides
    /// @param[in]  isDivider             Whether this item is a section divider
    /// @param[in]  isTitleChecked        Whether the card's main title checkbox is selected
    /// @param[in]  startDate             Optional start date for the card
    /// @param[in]  dueDate               Optional due date for the card
    /// @param[in]  checklists            Checklist groups; nil selects the seeded defaults
    /// @param[in]  comments              Activity comments associated with the card
    /// @param[in]  members               Registered and manual card assignments
    /// @param[in]  labelIDs              Stable identifiers of assigned labels
    /// @param[in]  attachments           Optional photo attachment metadata
    /// @param[in]  coverAttachmentID     Explicit cover photo identity; nil keeps the card text-only
    /// @param[in]  dismissedActivityIDs  Generated activity entries dismissed by the user
    /// @param[in]  descriptionOverride   Optional user-edited description
    /// @param[in]  subtitleOverride      Optional user-edited Board subtitle
    /// @param[in]  presentation          Card or writing-first Note interface
    /// @param[in]  createdAt             Known creation time; nil preserves unknown legacy dates
    ///
    /// @return     (KanbanCard) configured card instance
    ///
    /// @pre        Supplied values are valid for the caller's Board state
    /// @post       The card retains supplied values; nil checklists receive the default groups
    ///
    init(id: Int, word: String, listTitle: String, isDivider: Bool = false, isTitleChecked: Bool = false, startDate: Date? = nil, dueDate: Date? = nil, checklists: [KanbanChecklist]? = nil, comments: [KanbanComment] = [], members: [CardAssignee] = [], labelIDs: [String] = [], attachments: [KanbanAttachment]? = nil, coverAttachmentID: UUID? = nil, dismissedActivityIDs: Set<String> = [], descriptionOverride: String? = nil, subtitleOverride: String? = nil, presentation: ItemPresentation = .card, createdAt: Date? = nil) {

        self.id                   = id                      /* Stable numeric identifier for the card             */
        self.word                 = word                    /* Display word shown as the card's title             */
        self.listTitle            = listTitle               /* Name of the list where the card resides            */
        self.isDivider            = isDivider               /* Whether this item renders as a section divider     */
        self.isTitleChecked       = isTitleChecked          /* Whether the card's main title checkbox is selected */
        self.startDate            = startDate               /* Optional start date for the card                   */
        self.dueDate              = dueDate                 /* Optional due date for the card                     */
        self.createdAt            = createdAt
        self.comments             = comments                /* Array of comments associated with the card         */
        self.members              = members                 /* Names of users assigned to the card                */
        self.labelIDs             = labelIDs                /* Stable IDs of labels assigned to the card          */
        self.attachments          = attachments             /* Photo attachment metadata for the card             */
        self.coverAttachmentID    = coverAttachmentID
        self.dismissedActivityIDs = dismissedActivityIDs    /* Set of activity IDs that were dismissed by user    */
        self.descriptionOverride  = descriptionOverride     /* Optional user-edited description                   */
        self.subtitleOverride     = subtitleOverride        /* Optional user-edited subtitle                      */
        self.itemPresentation     = presentation == .card ? nil : presentation
        self.checklists           = checklists ?? [
            KanbanChecklist(title: "Focus",   items: ["Gather the important bits",   "Make it look intentional", "Celebrate the surprisingly good result"], completed: id % 4),
            KanbanChecklist(title: "Plan",    items: ["Choose the next useful step", "Stop building",            "Start producing"],                        completed: 1),
            KanbanChecklist(title: "Routine", items: ["Home",                        "Gym",                      "Work"])
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
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)   /* Card fields */
        let decodedMembers: [CardAssignee] /* Typed or migrated card assignments */

        if let typedMembers = try? container.decode([CardAssignee].self, forKey: .members) { /* Current typed representation */

            decodedMembers = typedMembers /* Keep registered identity references */
        } else {

            let legacyMembers = try container.decodeIfPresent([String].self, forKey: .members) ?? []   /* Legacy names */

            decodedMembers = legacyMembers.map(CardAssignee.manual) /* Migrate old names as manual entries */
        }

        self.init(
            id:                   try container.decode(Int.self, forKey: .id),
            word:                 try container.decode(String.self, forKey: .word),
            listTitle:            try container.decode(String.self, forKey: .listTitle),
            isDivider:            try container.decodeIfPresent(Bool.self, forKey: .isDivider) ?? false,
            isTitleChecked:       try container.decodeIfPresent(Bool.self, forKey: .isTitleChecked) ?? false,
            startDate:            try container.decodeIfPresent(Date.self, forKey: .startDate),
            dueDate:              try container.decodeIfPresent(Date.self, forKey: .dueDate),
            checklists:           try container.decodeIfPresent([KanbanChecklist].self, forKey: .checklists),
            comments:             try container.decodeIfPresent([KanbanComment].self, forKey: .comments) ?? [],
            members:              decodedMembers,
            labelIDs:             try container.decodeIfPresent([String].self, forKey: .labelIDs) ?? [],
            attachments:          try container.decodeIfPresent([KanbanAttachment].self, forKey: .attachments),
            coverAttachmentID:    try container.decodeIfPresent(UUID.self, forKey: .coverAttachmentID),
            dismissedActivityIDs: try container.decodeIfPresent(Set<String>.self, forKey: .dismissedActivityIDs) ?? [],
            descriptionOverride:  try container.decodeIfPresent(String.self, forKey: .descriptionOverride),
            subtitleOverride:     try container.decodeIfPresent(String.self, forKey: .subtitleOverride),
            presentation:         try container.decodeIfPresent(ItemPresentation.self, forKey: .itemPresentation) ?? .card,
            createdAt:            try container.decodeIfPresent(Date.self, forKey: .createdAt)
        )
    }


    ///
    /// Identifies persisted card fields for legacy and typed assignment decoding
    ///
    /// @section    Purpose
    ///     Preserve established Board JSON keys while upgrading only the member value shape
    ///
    private enum CodingKeys: String, CodingKey {
        case id
        case word
        case listTitle
        case isDivider
        case isTitleChecked
        case startDate
        case dueDate
        case createdAt
        case checklists
        case comments
        case members
        case labelIDs
        case attachments
        case coverAttachmentID
        case dismissedActivityIDs
        case descriptionOverride
        case subtitleOverride
        case itemPresentation
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
    var startDateLabel: String { /* Start-date badge text or default */

        guard let startDate else { /* No explicit start date */

            return "Today"
        }

        return Self.dateFormatter.string(from: startDate)
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
    var dueDateLabel: String { /* Due-date badge text or default */

        guard let dueDate else { /* No explicit due date */

            return "Tomorrow"
        }

        return Self.dateFormatter.string(from: dueDate)
    }

    /// Shared formatter used to render card date labels
    private static let dateFormatter: DateFormatter = { /* Shared date-only display formatter */

        let formatter       = DateFormatter() /* Formatter used for card date labels */

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
    var subtitle: String { /* Supporting card text or user override */
        if let subtitleOverride { /* Explicitly edited subtitle */

            return subtitleOverride
        }

        return ["A small idea with suspiciously large ambitions", "Make progress before the coffee gets cold", "A practical plan, lightly seasoned with chaos", "One more useful thing for today's board", "Future success, pending a snack break"][id % 5]
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
    var checklistItems: [String] { /* Titles from the first checklist */
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
    var completedChecklistItems: Int { /* Completion count for the first checklist */
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
    var commentCount: Int { /* Number of activity comments */
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
    var hasDueDate: Bool { /* Sample badge visibility for the card */
        id % 3 != 1
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
    var funParagraph: String { /* User description or generated sample context */

        if let descriptionOverride { /* User-authored description */

            return descriptionOverride
        }

        let templates: [(String, String) -> String] = [ /* Generated card-context templates */

            { word, title in
                "Deep within the \(title) list, a \(word) staged a one-creature protest, demanding better lighting and a snack table. Management is 'reviewing the request', which is corporate for 'ignoring it politely'."
            },
            { word, title in
                "Legend has it that this \(word) was smuggled onto the \(title) board during a coffee run and has since filed three noise complaints against the stapler."
            },
            { word, title in
                "Nobody remembers hiring the \(word), yet here it sits on the \(title) list, quietly rearranging sticky notes into passive-aggressive haiku."
            },
            { word, title in
                "According to office folklore, the \(word) on the \(title) list once won a staring contest with the printer and hasn't blinked since."
            },
            { word, title in
                "The \(word) insists it is 'just visiting' the \(title) list, despite having set up a tiny desk, a tinier chair, and a nameplate that reads 'Regional Manager'."
            },
            { word, title in
                "Reports from the \(title) list describe a \(word) attempting to unionize the paperclips, citing 'unbearable working conditions near the shredder'."
            },
            { word, title in
                "This \(word) arrived on the \(title) list via interoffice mail, addressed to 'Whoever Needs the Most Chaos Today', and promptly took over the group chat."
            },
            { word, title in
                "Witnesses on the \(title) list swear the \(word) can predict meetings that will run long, mostly because it brings its own pillow."
            },
            { word, title in
                "The \(word) has been spotted on the \(title) list rehearsing an acceptance speech for an award that does not exist, in front of an audience that also does not exist."
            },
            { word, title in
                "Somewhere between the third and fourth cup of coffee, a \(word) wandered onto the \(title) list and decided it was now in charge of snack inventory."
            }
        ]

        let template = templates[id % templates.count] /* Deterministic template for this card */

        return template(word, listTitle)
    }
}


// -------------------------------------- MARK: - List Model ------------------------------------ //


///
/// Represents one horizontally navigable kanban list
///
/// @section    Purpose
///     Group an ordered collection of cards with the list title and supporting board copy
///
struct KanbanList: Identifiable, Hashable, Codable, Sendable {

    let id:        Int              /* Unique identifier for the kanban list */
    let title:     String           /* Title of the kanban list              */
    var cards:     [KanbanCard]     /* Cards contained within the list       */
    var archivedCards: [KanbanCard] /* Cards retained in this list's archive */
    var isArchived: Bool = false    /* Whether this list is in the board archive */
    private var defaultItemPresentation: ItemPresentation? /* Optional persisted default kind for newly created records */

    /// Applies only at creation; changing this preference never converts retained items.
    var newItemPresentation: ItemPresentation { /* Effective creation kind with the legacy Card fallback */
        get { defaultItemPresentation ?? .card }
        set { defaultItemPresentation = newValue == .card ? nil : newValue }
    }


    ///
    /// @fcn        KanbanList.makeItem(id:title:description:)
    /// @brief      Create an item using this list's default interface
    /// @details    Notes start with an empty body and no seeded checklists. Dividers remain Cards.
    ///             Existing Card creation keeps its established checklist defaults
    /// @param[in]  id           Caller-allocated stable identity
    /// @param[in]  title        Validated item title
    /// @param[in]  description  Optional supplied body
    /// @param[in]  createdAt    Creation time captured once for this new item
    /// @return     (KanbanCard) new record without modifying the list
    ///
    func makeItem(id: Int, title: String, description: String? = nil, createdAt: Date = .now) -> KanbanCard {

        let isDivider = KanbanCard.isDividerTitle(title) /* Whether the title creates a section separator */
        let presentation = isDivider ? ItemPresentation.card : newItemPresentation /* Item kind selected for the new record */

        return KanbanCard(
            id: id, word: title, listTitle: self.title, isDivider: isDivider,
            checklists:          presentation == .note ? [] : nil,
            descriptionOverride: presentation == .note ? (description ?? "") : description,
            presentation:        presentation,
            createdAt:           createdAt
        )
    }

    ///
    /// @fcn        KanbanList.allCards
    /// @brief      Return active and archived cards together
    /// @details    Preserves active cards before archived cards in the combined snapshot
    ///
    /// @return     ([KanbanCard]) all cards retained by the list
    /// @post       The list's active and archived collections are unchanged
    ///
    var allCards: [KanbanCard] { cards + archivedCards } /* Active and archived records retained by this list */


    ///
    /// @fcn        KanbanList.init(id:title:cards:archivedCards:newItemPresentation:)
    /// @brief      Initialize a board list and its retained cards
    /// @details    Creates the list with active cards and an optional archived-card snapshot
    ///
    /// @param[in]  id            Stable list identity
    /// @param[in]  title         Displayed list title
    /// @param[in]  cards         Active cards in the list
    /// @param[in]  archivedCards Cards retained in this list's archive
    /// @param[in]  newItemPresentation Interface for newly created items only
    ///
    /// @return     (KanbanList) configured board list
    /// @post       The list is active; archive status defaults to false
    ///
    init(id: Int, title: String, cards: [KanbanCard], archivedCards: [KanbanCard] = [], newItemPresentation: ItemPresentation = .card) {

        self.id = id
        self.title = title
        self.cards = cards
        self.archivedCards = archivedCards
        self.defaultItemPresentation = newItemPresentation == .card ? nil : newItemPresentation
    }


    ///
    /// Identifies persisted list fields used by the custom Codable implementation
    ///
    /// @section    Purpose
    ///     Preserve backward-compatible decoding when archived fields are absent
    ///
    private enum CodingKeys: String, CodingKey {
        case id, title, cards, archivedCards, isArchived, defaultItemPresentation
    }


    ///
    /// @fcn        KanbanList.init(from:)
    /// @brief      Decode a current or older saved board list
    /// @details    Missing archive fields are initialized as empty and inactive
    ///
    /// @param[in]  decoder  Decoder containing the list snapshot
    ///
    /// @return     (KanbanList) decoded list with available archive data
    ///
    /// @throws     DecodingError when required list fields cannot be decoded
    ///
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self) /* Keyed fields read from the persisted list */

        id            = try container.decode(Int.self, forKey: .id)
        title         = try container.decode(String.self, forKey: .title)
        cards         = try container.decode([KanbanCard].self, forKey: .cards)
        archivedCards = try container.decodeIfPresent([KanbanCard].self, forKey: .archivedCards) ?? []
        isArchived    = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        defaultItemPresentation = try container.decodeIfPresent(ItemPresentation.self, forKey: .defaultItemPresentation)
        if defaultItemPresentation == .card {

            defaultItemPresentation = nil
        }
    }


    ///
    /// @fcn        KanbanList.encode(to:)
    /// @brief      Encode the list and any non-default archive state
    /// @details    Omits empty archived cards and a false archive flag from the encoded snapshot
    ///
    /// @param[in]  encoder  Encoder receiving the list snapshot
    ///
    /// @return     (Void) writes the list fields to the encoder
    ///
    /// @throws     EncodingError when list values cannot be encoded
    ///
    func encode(to encoder: Encoder) throws {

        var container = encoder.container(keyedBy: CodingKeys.self) /* Keyed fields written for the persisted list */

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(cards, forKey: .cards)
        try container.encodeIfPresent(defaultItemPresentation, forKey: .defaultItemPresentation)

        if !archivedCards.isEmpty {

            try container.encode(archivedCards, forKey: .archivedCards)
        }

        if isArchived {

            try container.encode(true, forKey: .isArchived)
        }
    }


    ///
    /// @fcn        KanbanList.archiveCompletedCards()
    /// @brief      Move checked non-divider cards into the list archive
    /// @details    Leaves section dividers and unchecked cards in the active collection
    ///
    /// @return     (Void) updates this list's active and archived card arrays
    ///
    /// @post       Every checked non-divider card is retained in archivedCards
    ///
    mutating func archiveCompletedCards() {

        archivedCards.append(contentsOf: cards.filter { !$0.isSectionDivider && $0.isTitleChecked })
        cards.removeAll { !$0.isSectionDivider && $0.isTitleChecked }
    }


    ///
    /// @fcn        KanbanList.archiveCard(id:)
    /// @brief      Archive one active card by stable identity
    /// @details    Section dividers are not eligible for card archival
    ///
    /// @param[in]  cardID  Identity of the active card to archive
    ///
    /// @return     (Void) moves the matching card when present
    ///
    /// @post       Missing IDs and divider IDs leave the list unchanged
    ///
    mutating func archiveCard(id cardID: Int) {

        guard let index = cards.firstIndex(where: { /* Position of the active card to archive */

            $0.id == cardID && !$0.isSectionDivider
        }) else {

            return
        }

        archivedCards.append(cards.remove(at: index))
    }


    ///
    /// @fcn        KanbanList.restoreArchivedCard(id:)
    /// @brief      Restore one archived card to the active list
    /// @details    Appends the matching archived card to the active collection
    ///
    /// @param[in]  cardID  Identity of the archived card to restore
    ///
    /// @return     (Void) moves the matching card when present
    ///
    /// @post       A missing ID leaves the list unchanged
    ///
    mutating func restoreArchivedCard(id cardID: Int) {

        guard let index = archivedCards.firstIndex(where: { /* Position of the archived card to restore */

            $0.id == cardID
        }) else {

            return
        }

        cards.append(archivedCards.remove(at: index))
    }


    ///
    /// @fcn        KanbanList.subtitle
    /// @brief      Provide supporting copy for the list header
    /// @details    Selects a deterministic subtitle using the list identity
    ///
    /// @return     (String) supporting text shown beneath the list title
    /// @post       No list state is modified
    ///
    var subtitle: String { /* Supporting text for the list header */
        let subtitles = ["Ideas taking shape", "Ready for a little momentum", "Currently in progress", "Nearly across the finish line", "Done, or at least confidently presented"] /* List subtitle options */

        return subtitles[id % subtitles.count]
    }
}


// -------------------------------------- MARK: - Checklist Action Detail ---------------------- //


///
/// Stores reduced card-like context owned by one checklist action
///
/// @section    Purpose
///     Let an action gain description, checklist, and comment context without becoming an
///     independent card on the Board
///
/// @note   Action Details are reached only through their owning checklist item
///
struct KanbanChecklistActionDetail: Identifiable, Hashable, Codable, Sendable {

    let id:          UUID                /* Stable Action Detail ID */
    var description: String              /* Supporting action text */
    var checklists:  [KanbanChecklist]   /* Nested standard actions */
    var comments:    [KanbanComment]     /* Action discussion       */


    ///
    /// @fcn        KanbanChecklistActionDetail.init(id:description:checklists:comments:)
    /// @brief      Initialize reduced detail content for one checklist action
    /// @details    Stores only the context required below a checklist item and does not create
    ///             Board list membership
    ///
    /// @param[in]  id           Stable Action Detail identifier
    /// @param[in]  description  Supporting action description
    /// @param[in]  checklists   Nested checklist groups owned by this detail
    /// @param[in]  comments     Comments posted within this detail
    ///
    /// @return     (KanbanChecklistActionDetail) configured reduced detail record
    ///
    init(id: UUID = UUID(), description: String = "", checklists: [KanbanChecklist] = [], comments: [KanbanComment] = []) {

        self.id          = id
        self.description = description
        self.checklists  = checklists
        self.comments    = comments
    }
}


// -------------------------------------- MARK: - Checklist Action Content --------------------- //


///
/// Identifies the behavior and owned content of one checklist action
///
/// @section    Purpose
///     Distinguish plain text, navigation to an existing card, and reduced owned detail while
///     keeping one stable checklist-item identity
///
enum KanbanChecklistActionContent: Hashable, Codable, Sendable {

    case standard                                      /* Plain text action       */
    case linkedCard(cardID: Int)                       /* Existing card reference */
    case actionDetail(KanbanChecklistActionDetail)     /* Owned reduced detail    */


    ///
    /// Identifies the persisted action-content discriminator
    ///
    /// @section    Purpose
    ///     Keep the encoded representation explicit and stable across associated-value changes
    ///
    private enum Kind: String, Codable {
        case standard       /* Plain text action kind  */
        case linkedCard     /* Existing card link kind */
        case actionDetail   /* Reduced detail kind     */
    }


    ///
    /// Identifies fields used by the explicit action-content representation
    ///
    /// @section    Purpose
    ///     Separate the content discriminator from its optional associated payload
    ///
    private enum CodingKeys: String, CodingKey {
        case kind       /* Content discriminator */
        case cardID     /* Linked card identity  */
        case detail     /* Owned Action Detail   */
    }


    ///
    /// @fcn        KanbanChecklistActionContent.init(from:)
    /// @brief      Decode one explicit checklist action-content value
    /// @details    Requires the payload associated with linked-card and Action Detail kinds
    ///
    /// @param[in]  decoder  Decoder containing action-content fields
    ///
    /// @return     (KanbanChecklistActionContent) decoded action behavior
    ///
    /// @throws     DecodingError when the discriminator or required payload is invalid
    ///
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)   /* Persisted fields */
        let kind      = try container.decode(Kind.self, forKey: .kind)    /* Action kind      */

        switch kind {

            case .standard:
                self = .standard
            case .linkedCard:
                self = .linkedCard(cardID: try container.decode(Int.self, forKey: .cardID))
            case .actionDetail:
                self = .actionDetail(try container.decode(KanbanChecklistActionDetail.self, forKey: .detail))
        }
    }


    ///
    /// @fcn        KanbanChecklistActionContent.encode(to:)
    /// @brief      Encode one explicit checklist action-content value
    /// @details    Writes the discriminator and only the payload required by the selected kind
    ///
    /// @param[in]  encoder  Encoder receiving action-content fields
    ///
    /// @return     (Void) writes the selected action behavior
    ///
    /// @throws     EncodingError when the discriminator or payload cannot be encoded
    ///
    func encode(to encoder: Encoder) throws {

        var container = encoder.container(keyedBy: CodingKeys.self)   /* Output fields */

        switch self {

            case .standard:
                try container.encode(Kind.standard, forKey: .kind)
            case .linkedCard(let cardID): /* Referenced Board card identity */
                try container.encode(Kind.linkedCard, forKey: .kind)
                try container.encode(cardID, forKey: .cardID)
            case .actionDetail(let detail): /* Owned reduced Action Detail payload */
                try container.encode(Kind.actionDetail, forKey: .kind)
                try container.encode(detail, forKey: .detail)
        }
    }
}


// -------------------------------------- MARK: - Checklist Item Model ------------------------- //


///
/// Represents one stable action within a card checklist
///
/// @section    Purpose
///     Preserve checklist-item identity, editable text, and completion independently from its
///     position so richer action types can be introduced without replacing the checklist model
///
/// @note   Revision 0 checklist strings migrate to standard items during decoding
///
struct KanbanChecklistItem: Identifiable, Hashable, Codable, ExpressibleByStringLiteral, Sendable {

    let id:        UUID                           /* Stable checklist action ID */
    var title:     String                         /* User-facing action text    */
    var isCompleted: Bool                         /* Current completion state   */
    var content:   KanbanChecklistActionContent   /* Action behavior and data  */


    ///
    /// @fcn        KanbanChecklistItem.init(id:title:isCompleted:content:)
    /// @brief      Initialize a stable standard checklist action
    /// @details    Stores identity, editable text, and completion without assigning richer content
    ///
    /// @param[in]  id           Stable identifier for the checklist item
    /// @param[in]  title        User-facing action text
    /// @param[in]  isCompleted  Whether the action begins complete
    /// @param[in]  content      Action behavior and associated content
    ///
    /// @return     (KanbanChecklistItem) configured standard action
    ///
    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, content: KanbanChecklistActionContent = .standard) {

        self.id          = id
        self.title       = title
        self.isCompleted = isCompleted
        self.content     = content
    }


    ///
    /// @fcn        KanbanChecklistItem.init(stringLiteral:)
    /// @brief      Create a standard action from a string literal
    /// @details    Keeps deterministic sample declarations and new-item call sites concise
    ///
    /// @param[in]  value  Text used as the action title
    ///
    /// @return     (KanbanChecklistItem) incomplete standard action with a new identity
    ///
    init(stringLiteral value: String) {

        self.init(title: value)
    }


    ///
    /// @fcn        KanbanChecklistItem.init(from:)
    /// @brief      Decode current action state or default earlier item records to standard text
    /// @details    Item records written before action types existed omit content and remain compatible
    ///
    /// @param[in]  decoder  Decoder containing checklist-item fields
    ///
    /// @return     (KanbanChecklistItem) decoded checklist action
    ///
    /// @throws     DecodingError when required identity, title, or completion fields are invalid
    ///
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)   /* Persisted fields */

        id          = try container.decode(UUID.self, forKey: .id)
        title       = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        content     = try container.decodeIfPresent(KanbanChecklistActionContent.self, forKey: .content) ?? .standard
    }


    ///
    /// @fcn        KanbanChecklistItem.encode(to:)
    /// @brief      Encode stable item state and its explicit action content
    /// @details    Writes content for every new snapshot, including the standard discriminator
    ///
    /// @param[in]  encoder  Encoder receiving checklist-item fields
    ///
    /// @return     (Void) writes the current checklist action
    ///
    /// @throws     EncodingError when checklist-item fields cannot be encoded
    ///
    func encode(to encoder: Encoder) throws {

        var container = encoder.container(keyedBy: CodingKeys.self)   /* Output fields */

        try container.encode(id,          forKey: .id)
        try container.encode(title,       forKey: .title)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(content,     forKey: .content)
    }


    ///
    /// Identifies persisted checklist-item fields
    ///
    /// @section    Purpose
    ///     Keep missing content backward-compatible while requiring established item state
    ///
    private enum CodingKeys: String, CodingKey {
        case id            /* Stable action identity */
        case title         /* User-facing action text */
        case isCompleted   /* Direct completion state */
        case content       /* Action behavior payload */
    }
}


// -------------------------------------- MARK: - Checklist Model ------------------------------ //


///
/// Represents a checklist shown within a kanban card
///
/// @section    Purpose
///     Provide a small value type for rendering both seeded and newly created checklist groups
///
struct KanbanChecklist: Identifiable, Hashable, Codable, Sendable {

    let id:    UUID                    /* Stable checklist ID      */
    let title: String                  /* Checklist display title */
    let items: [KanbanChecklistItem]   /* Ordered action records  */

    ///
    /// @fcn        KanbanChecklist.completedItemIndices
    /// @brief      Return completed item positions for the current checklist UI
    /// @details    Derives the legacy index surface from each stable item's direct completion state
    ///
    /// @return     (Set<Int>) zero-based positions of completed checklist items
    ///
    /// @pre        items contains the current ordered checklist actions
    /// @post       No item state is modified
    ///
    var completedItemIndices: Set<Int> {   /* Completed UI positions */
        Set(items.indices.filter { items[$0].isCompleted })
    }

    ///
    /// @fcn        KanbanChecklist.completed
    /// @brief      Count completed checklist actions
    /// @details    Reads direct item completion rather than relying on persisted positions
    ///
    /// @return     (Int) number of completed actions
    ///
    /// @pre        items contains the current checklist actions
    /// @post       No item state is modified
    ///
    var completed: Int {                   /* Completed action count */
        items.lazy.filter(\.isCompleted).count
    }


    ///
    /// @fcn        KanbanChecklist.init(id:title:items:completed:completedItemIndices:)
    /// @brief      Initialize a checklist with stable action records
    /// @details    Preserves item completion unless a count or explicit legacy index set is supplied
    ///
    /// @param[in]  id                    Stable checklist identifier
    /// @param[in]  title                 User-facing checklist title
    /// @param[in]  items                 Stable checklist action records
    /// @param[in]  completed             Optional number of leading items to mark complete
    /// @param[in]  completedItemIndices  Optional explicit completion positions
    ///
    /// @return     (KanbanChecklist) configured checklist
    ///
    init(id: UUID = UUID(), title: String, items: [KanbanChecklistItem] = [], completed: Int? = nil, completedItemIndices: Set<Int>? = nil) {

        var normalizedItems = items       /* Mutable item snapshot */

        if let completedItemIndices {   /* Explicit completion positions */

            for index in normalizedItems.indices {

                normalizedItems[index].isCompleted = completedItemIndices.contains(index)
            }

        } else if let completed {       /* Leading completion count */
            for index in normalizedItems.indices {

                normalizedItems[index].isCompleted = index < min(completed, normalizedItems.count)
            }
        }

        self.id    = id
        self.title = title
        self.items = normalizedItems
    }


    ///
    /// @fcn        KanbanChecklist.init(from:)
    /// @brief      Decode current checklist items or migrate revision 0 string items
    /// @details    Current item records decode directly; legacy strings receive deterministic IDs
    ///             derived from the checklist identity and item position
    ///
    /// @param[in]  decoder  Decoder containing current or legacy checklist data
    ///
    /// @return     (KanbanChecklist) decoded or migrated checklist
    ///
    /// @throws     DecodingError when required checklist fields or item data are invalid
    ///
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)   /* Persisted fields */
        let id        = try container.decode(UUID.self, forKey: .id)      /* Checklist ID     */
        let title     = try container.decode(String.self, forKey: .title) /* Checklist title  */

        if var currentItems = try? container.decode([KanbanChecklistItem].self, forKey: .items) { /* Current actions */

            if let legacyCompletedIndices = try container.decodeIfPresent(Set<Int>.self, forKey: .completedItemIndices) { /* Legacy completion */

                for index in currentItems.indices {

                    currentItems[index].isCompleted = legacyCompletedIndices.contains(index)
                }
            }

            self.init(id: id, title: title, items: currentItems)

            return
        }

        let legacyTitles           = try container.decode([String].self, forKey: .items) /* Legacy action text */
        let legacyCompletedIndices = try container.decodeIfPresent(Set<Int>.self, forKey: .completedItemIndices) ?? [] /* Legacy completion */
        let migratedItems          = legacyTitles.enumerated().map { index, itemTitle in /* Migrated actions */
            KanbanChecklistItem(
                id:          Self.migratedItemID(checklistID: id, itemIndex: index),
                title:       itemTitle,
                isCompleted: legacyCompletedIndices.contains(index)
            )
        }

        self.init(id: id, title: title, items: migratedItems)
    }


    ///
    /// @fcn        KanbanChecklist.encode(to:)
    /// @brief      Encode the stable checklist-item representation
    /// @details    Writes checklist identity, title, and item records without the legacy
    ///             completion-index field
    ///
    /// @param[in]  encoder  Encoder receiving the current checklist representation
    ///
    /// @return     (Void) writes the checklist into the supplied encoder
    ///
    /// @throws     EncodingError when checklist values cannot be encoded
    ///
    func encode(to encoder: Encoder) throws {

        var container = encoder.container(keyedBy: CodingKeys.self)   /* Output fields */

        try container.encode(id,    forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(items, forKey: .items)
    }


    ///
    /// Identifies persisted checklist fields across current and revision 0 snapshots
    ///
    /// @section    Purpose
    ///     Keep current item records and the legacy completion field available to custom Codable logic
    ///
    private enum CodingKeys: String, CodingKey {
        case id                     /* Checklist identity       */
        case title                  /* Checklist display title  */
        case items                  /* Current or legacy actions */
        case completedItemIndices   /* Revision 0 completion    */
    }


    ///
    /// @fcn        KanbanChecklist.migratedItemID(checklistID:itemIndex:)
    /// @brief      Produce a repeatable identity for a legacy positional item
    /// @details    Retains the first 80 bits of checklist identity and uses the legacy item
    ///             position for the final UUID component
    ///
    /// @param[in]  checklistID  Stable identity of the containing legacy checklist
    /// @param[in]  itemIndex    Zero-based position of the legacy string item
    ///
    /// @return     (UUID) repeatable migrated checklist-item identity
    ///
    /// @pre        itemIndex is nonnegative and checklistID is a valid UUID
    /// @post       No checklist or item data is modified
    ///
    private static func migratedItemID(checklistID: UUID, itemIndex: Int) -> UUID {

        let components = checklistID.uuidString.split(separator: "-")   /* UUID components */

        guard components.count == 5 else {

            return UUID()
        }

        let itemComponent = String(format: "%012llX", UInt64(itemIndex)) /* Position suffix */
        let migratedValue = "\(components[0])-\(components[1])-\(components[2])-\(components[3])-\(itemComponent)" /* Migrated UUID text */

        return UUID(uuidString: migratedValue) ?? UUID()
    }
}


// -------------------------------------- MARK: - Card Comment ------------------------------- //


///
/// Represents a user-authored entry in a kanban card's activity feed
///
/// @section    Purpose
///     Preserve comment identity, author, content, and creation time as card data
///
struct KanbanComment: Identifiable, Hashable, Codable, Sendable {
    let id:        UUID         /* Unique identifier for the comment                 */
    let author:    String       /* Author of the comment                             */
    let body:      String       /* Body text of the comment                          */
    let createdAt: Date         /* Timestamp indicating when the comment was created */


    ///
    /// @fcn        KanbanComment.init(id:author:body:createdAt:)
    /// @brief      Initialize a card activity comment
    /// @details    Uses the supplied content and defaults the identity and timestamp when omitted
    ///
    ///
    /// @param[in]  id        Comment identity
    /// @param[in]  author    Display name of the comment author
    /// @param[in]  body      Comment text
    /// @param[in]  createdAt Comment creation time
    ///
    /// @return     (KanbanComment) configured activity entry
    /// @post       The comment retains the supplied author and text
    ///
    init(id: UUID = UUID(), author: String, body: String, createdAt: Date = .now) {

        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}


///
/// An insertion boundary in one active Board list
struct BoardCardDropTarget: Equatable {
    let listID: Int /* Destination list identity for the drop */
    let beforeCardID: Int? /* Insertion anchor; nil appends after existing cards */
}


///
/// Moves complete canonical card records within one Board
///
/// @section    Purpose
///     Share validated movement between drag/drop and the existing Move to List action
///
enum BoardCardMovement {


    ///
    /// @fcn        BoardCardMovement.move(_:to:before:in:)
    /// @brief      Move the complete canonical card to a validated insertion boundary
    /// @details    Requires unambiguous active source and destination records and rejects dividers
    ///             or stale boundaries. Validates a copied list array before committing; a nil
    ///             boundary appends and only the card list title and position change.
    ///
    /// @param[in]     cardID        Board-local identity of the card being dragged or moved
    /// @param[in]     listID        Board-local identity of the destination list
    /// @param[in]     beforeCardID  Insertion-boundary card identity, or nil to append
    /// @param[in,out] lists         Canonical ordered Board lists used for movement or targeting
    ///
    /// @return     (Bool) whether the requested move changed card position or list membership
    ///
    /// @throws     CocoaError.validationMissingMandatoryProperty for invalid or ambiguous movement
    ///             records
    ///
    /// @post       Rejected and no-op movements leave lists unchanged; successful movement
    ///             preserves all other card fields
    ///
    @discardableResult
    static func move(_ cardID: Int, to listID: Int, before beforeCardID: Int? = nil,
                     in lists: inout [KanbanList]) throws -> Bool {

        let sources = lists.indices.filter { lists[$0].cards.contains { $0.id == cardID } } /* Lists containing the requested card identity */

        guard sources.count == 1, let source = sources.first, /* Unique source list position */
              lists[source].cards.filter({ $0.id == cardID }).count == 1,
              lists.filter({ $0.id == listID }).count == 1,

              let destination = lists.firstIndex(where: { $0.id == listID && !$0.isArchived }), /* Active destination list position */
              !lists[source].isArchived,
              let index = lists[source].cards.firstIndex(where: { $0.id == cardID }), /* Card position within the source list */
              !lists[source].cards[index].isSectionDivider else {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        if beforeCardID == cardID, source == destination {

            return false
        }

        var updated = lists /* Board snapshot changed only after movement validation */
        var card = updated[source].cards.remove(at: index) /* Record removed from its source for reinsertion */
        let insertion: Int /* Destination offset after removing the source record */

        if let beforeCardID { /* Destination card serving as the insertion anchor */

            guard let position = updated[destination].cards.firstIndex(where: { /* Current position of the insertion anchor */

                $0.id == beforeCardID
            }) else {

                throw CocoaError(.validationMissingMandatoryProperty)
            }

            insertion = position
        } else {

            insertion = updated[destination].cards.count
        }

        if source == destination && insertion == index {

            return false
        }

        card.listTitle = updated[destination].title
        updated[destination].cards.insert(card, at: insertion)
        lists = updated

        return true
    }


    ///
    /// @fcn        BoardCardMovement.target(for:at:viewport:lists:listFrames:cardFrames:)
    /// @brief      Resolve a card insertion boundary from visible global-coordinate geometry
    /// @details    Rejects nonfinite points, invalid viewports, and locations outside active list
    ///             panels. Uses row midpoints, excludes the dragged card, and avoids appending past
    ///             unmeasured trailing rows.
    ///
    /// @param[in]  cardID      Board-local identity of the card being dragged or moved
    /// @param[in]  point       Pointer location in the Board window coordinate space
    /// @param[in]  viewport    Visible Board bounds in the same coordinates as the pointer
    /// @param[in]  lists       Canonical ordered Board lists used for movement or targeting
    /// @param[in]  listFrames  Measured global list-panel frames keyed by list identity
    /// @param[in]  cardFrames  Measured global card-row frames keyed by card identity
    ///
    /// @return     (BoardCardDropTarget?) validated insertion target, or nil when geometry cannot
    ///             establish a destination
    ///
    static func target(for cardID: Int, at point: CGPoint, viewport: CGRect,
                       lists: [KanbanList], listFrames: [Int: CGRect],
                       cardFrames: [Int: CGRect]) -> BoardCardDropTarget? {

        guard point.x.isFinite, point.y.isFinite,
              viewport.origin.x.isFinite, viewport.origin.y.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0,
              viewport.contains(point),

              let list = lists.first(where: { !$0.isArchived && listFrames[$0.id]?.contains(point) == true }) else { /* Active list panel under the pointer */

            return nil
        }

        let cards = list.cards.filter { $0.id != cardID } /* Destination rows excluding the dragged card */
        let measured = cards.enumerated().filter { cardFrames[$0.element.id] != nil } /* Rows with geometry available for insertion targeting */

        if let next = measured.first(where: { /* First measured row below the pointer midpoint */

            point.y < (cardFrames[$0.element.id]?.midY ?? 0)
        }) {
            return BoardCardDropTarget(listID: list.id, beforeCardID: next.element.id)
        }

        if let last = measured.last, cards.indices.contains(last.offset + 1) { /* Final measured row preceding an unmeasured successor */

            return BoardCardDropTarget(listID: list.id, beforeCardID: cards[last.offset + 1].id)
        }

        guard cards.isEmpty || !measured.isEmpty else {

            return nil
        }

        return BoardCardDropTarget(listID: list.id, beforeCardID: nil)
    }
}


///
/// Provides list-ordering and drag-edge calculations for the Board
///
/// @section    Purpose
///     Keep list reorder operations independent from the view gesture implementation
///
enum BoardListReordering {


    ///
    /// @fcn        BoardListReordering.boundaryListID(_:in:)
    /// @brief      Resolve the first or last active list identity
    /// @details    Uses the current ordered list snapshot without changing list or card content
    ///
    /// @param[in]  boundary  Board edge to navigate to
    /// @param[in]  lists     Current active lists in display order
    ///
    /// @return     (Int?) boundary list identity, or nil when the Board has no active lists
    ///
    static func boundaryListID(_ boundary: BoardListBoundary, in lists: [KanbanList]) -> Int? {

        switch boundary {

            case .first:
                return lists.first?.id

            case .last:
                return lists.last?.id
        }
    }


    ///
    /// @fcn        BoardListReordering.boundary(forHorizontalSwipe:minimumDistance:)
    /// @brief      Resolve a deliberate horizontal title-area swipe to a Board edge
    /// @details    Rejects nonfinite, short, or predominantly vertical gestures. A leftward
    ///             swipe selects the last list; a rightward swipe selects the first,
    ///             matching the content movement of ordinary horizontal scrolling.
    ///
    /// @param[in]  translation      Completed drag translation in points
    /// @param[in]  minimumDistance  Minimum horizontal travel required to trigger a jump
    ///
    /// @return     (BoardListBoundary?) requested edge, or nil when the gesture is not a swipe
    ///
    static func boundary(
        forHorizontalSwipe translation: CGSize,
        minimumDistance: CGFloat = 48
    ) -> BoardListBoundary? {

        guard translation.width.isFinite, translation.height.isFinite,
              minimumDistance.isFinite, minimumDistance > 0,
              abs(translation.width) >= minimumDistance,
              abs(translation.width) > abs(translation.height) * 1.4 else {

            return nil
        }

        return translation.width < 0 ? .last : .first
    }


    ///
    /// @fcn        BoardListReordering.move(_:to:in:)
    /// @brief      Move a list to a destination index
    /// @details    Removes the identified list and inserts it at the requested position
    ///
    /// @param[in]     listID       Identity of the list to move
    /// @param[in]     destination  Destination index in the list array
    /// @param[in,out] lists        Mutable ordered list collection
    ///
    /// @return     (Bool) whether the requested move was performed
    ///
    /// @post       Invalid identities, indices, or same-position moves leave lists unchanged
    ///
    @discardableResult
    static func move(_ listID: Int, to destination: Int, in lists: inout [KanbanList]) -> Bool {

        guard let source = lists.firstIndex(where: { /* Current position of the list being reordered */

            $0.id == listID
        }),
              lists.indices.contains(destination), source != destination else { return false }

        let list = lists.remove(at: source) /* List temporarily removed for boundary insertion */

        lists.insert(list, at: destination)

        return true
    }


    /// Identifies a horizontal Board edge for direct list navigation.
    enum BoardListBoundary {
        case first
        case last
    }


    ///
    /// @fcn        BoardListReordering.edgeDirection(at:viewportWidth:)
    /// @brief      Resolve the horizontal edge direction for a drag location
    /// @details    Returns a direction only when the location falls inside an edge activation zone
    ///
    /// @param[in]  x              Horizontal drag location
    /// @param[in]  viewportWidth  Width of the visible board viewport
    ///
    /// @return     (Int) -1 for the leading edge, 1 for the trailing edge, or 0 otherwise
    ///
    /// @post       No list or drag state is modified
    ///
    static func edgeDirection(at x: CGFloat, viewportWidth: CGFloat) -> Int {

        guard x.isFinite, viewportWidth.isFinite, viewportWidth > 0 else {

            return 0
        }

        let edgeWidth = min(64, viewportWidth * 0.18) /* Edge activation zone scaled to the visible width */

        if x < edgeWidth {

            return -1
        }

        if x > viewportWidth - edgeWidth {

            return 1
        }

        return 0
    }
}


///
/// Identifies whether a saved personal collection is a single list or a board
///
/// @section    Purpose
///     Preserve collection behavior and presentation independently of its title
///
enum PersonalCollectionKind: String, CaseIterable, Codable {
    case list  = "List"
    case board = "Board"
}


///
/// Builds the text-only payload shared from a Note
///
/// @section    Purpose
///     Keep sharing limited to the Note title, written body, and explicitly attached web links
///
enum NoteTextSharing {


    ///
    /// @fcn        NoteTextSharing.text(for:)
    /// @brief      Compose the shareable text for a Note
    /// @details    Preserves the title and non-empty body, appends attached web-link URLs, and
    ///             excludes media and structured Details metadata
    ///
    /// @param[in]  note  Note whose written text and link attachments are shared
    ///
    /// @return     (String) title, optional body, and optional web links separated by blank lines
    ///
    static func text(for note: KanbanCard) -> String {

        var sections = [note.word] /* Share-text sections beginning with the Note title */

        if let body = note.descriptionOverride, !body.isEmpty { /* Nonempty Note body included in shared text */

            sections.append(body)
        }
        let links = (note.attachments ?? []).compactMap { attachment -> String? in /* Web links appended to the shared Note text */
            guard attachment.kind == .link, let url = attachment.url else { /* Address of a shareable link attachment */

                return nil
            }
            return url.absoluteString
        }
        if !links.isEmpty {

            sections.append(links.joined(separator: "\n\n"))
        }
        return sections.joined(separator: "\n\n")
    }
}


///
/// Holds the editable, unsaved state for creating a Note in a personal List
///
/// @section    Purpose
///     Preserve destination, entered text, and one creation timestamp until persistence succeeds
///
struct PersonalListNoteDraft {
    var destinationID: UUID /* Personal List selected for the unsaved Note */
    var title = "" /* Editable Note heading */
    var body = "" /* Editable Note content preserved as entered */
    let createdAt: Date = .now /* Draft creation time retained through saving */

    var normalizedTitle: String { /* Note heading without surrounding whitespace */
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        PersonalListNoteDraft.destinations(in:)
    /// @brief      Resolve active personal Lists that can receive a new Note
    /// @details    Excludes collections of Board kind, inactive collections, and Lists whose
    ///             contained records are all archived
    ///
    /// @param[in]  collections  Local personal collection snapshot to inspect
    ///
    /// @return     ([PersonalCollection]) eligible personal List destinations in source order
    ///
    static func destinations(in collections: [PersonalCollection]) -> [PersonalCollection] {

        collections.filter {
            $0.kind == .list && $0.isActive && $0.lists.contains(where: { !$0.isArchived })
        }
    }


    ///
    /// @fcn        PersonalListNoteDraft.destination(in:)
    /// @brief      Resolve the draft's currently selected destination
    /// @details    Matches the stable destination identity against the currently eligible Lists
    ///
    /// @param[in]  collections  Current local personal collection snapshot
    ///
    /// @return     (PersonalCollection?) selected active List, or nil when it is unavailable
    ///
    func destination(in collections: [PersonalCollection]) -> PersonalCollection? {

        Self.destinations(in: collections).first { $0.id == destinationID }
    }


    ///
    /// @fcn        PersonalListNoteDraft.canSave(in:)
    /// @brief      Determine whether the current Note draft meets save prerequisites
    /// @details    Requires a non-blank normalized title and a destination that remains an active
    ///             personal List
    ///
    /// @param[in]  collections  Current local personal collection snapshot
    ///
    /// @return     (Bool) true when both the title and selected destination are valid
    ///
    func canSave(in collections: [PersonalCollection]) -> Bool {

        !normalizedTitle.isEmpty && destination(in: collections) != nil
    }


    ///
    /// @fcn        PersonalListNoteDraft.save(in:onSave:)
    /// @brief      Validate the draft and pass its content to the persistence callback
    /// @details    Sends the normalized title, unchanged body, selected destination, and original
    ///             creation timestamp to the callback; does not mutate collections itself
    ///
    /// @param[in]  collections  Current local personal collection snapshot for validation
    /// @param[in]  onSave       Callback responsible for persisting the Note
    ///
    /// @return     (Void) invokes the persistence callback exactly once for a valid draft
    ///
    /// @throws     CocoaError when the title or selected destination is invalid; callback errors
    ///             propagate unchanged
    ///
    func save(
        in collections: [PersonalCollection],
        onSave: (UUID, String, String, Date) throws -> Void
    ) throws {

        guard canSave(in: collections) else {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        try onSave(destinationID, normalizedTitle, body, createdAt)
    }
}


///
/// Moves a Note between active personal collections without copying its content
///
/// @section    Purpose
///     Keep cross-collection location changes atomic and preserve collection-local identity rules
///
enum PersonalCollectionNoteMovement {


    ///
    /// @fcn        PersonalCollectionNoteMovement.move(noteID:from:to:in:)
    /// @brief      Move one active Note to an active personal List
    /// @details    Preserves all Note fields and bookmarks. Card IDs are collection-local; an ID
    ///             collision in the destination receives a fresh destination-local ID
    /// @param[in]     noteID        Active source Note ID
    /// @param[in]     sourceID      Owning collection identity
    /// @param[in]     destinationID Target active personal List identity
    /// @param[in,out] collections   Complete local collection snapshot
    /// @return     (KanbanCard) moved Note with its destination-local identity and title
    /// @throws     CocoaError when the source, Note, or destination is invalid or ambiguous
    ///
    static func move(
        noteID: Int,
        from sourceID: UUID,
        to destinationID: UUID,
        in collections: inout [PersonalCollection]
    ) throws -> KanbanCard {

        guard sourceID != destinationID,
              let sourceIndex = collections.firstIndex(where: { $0.id == sourceID && $0.isActive }), /* Active collection currently owning the Note */
              let destinationIndex = collections.firstIndex(where: { /* Active personal List receiving the Note */
                  $0.id == destinationID && $0.kind == .list && $0.isActive
              }) else {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var source = collections[sourceIndex] /* Source collection snapshot receiving the removal */
        var destination = collections[destinationIndex] /* Destination collection snapshot receiving the Note */
        let sourceMatches = source.lists.indices.flatMap { listIndex in /* Matching Note positions used to reject ambiguity */
            source.lists[listIndex].cards.indices.compactMap { cardIndex in
                !source.lists[listIndex].isArchived && source.lists[listIndex].cards[cardIndex].id == noteID
                    ? (listIndex, cardIndex)
                    : nil
            }
        }

        guard sourceMatches.count == 1,
              let (sourceListIndex, cardIndex) = sourceMatches.first, /* Unique source column and record positions */
              source.lists[sourceListIndex].cards[cardIndex].presentation == .note,
              !source.lists[sourceListIndex].cards[cardIndex].isSectionDivider,
              let destinationListIndex = destination.lists.firstIndex(where: { !$0.isArchived }) else { /* Active destination column accepting the Note */

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var moved = source.lists[sourceListIndex].cards.remove(at: cardIndex) /* Note detached from its source before relocation */
        let destinationIDs = Set(destination.lists.flatMap(\.allCards).map(\.id)) /* Active and archived identities reserved in the destination */

        var destinationCardID = moved.id /* Resulting Note identity adjusted only for a collision */

        if destinationIDs.contains(moved.id) {

            let (nextID, overflow) = (destinationIDs.max() ?? -1).addingReportingOverflow(1) /* Next unused identity and its overflow status */
            guard !overflow else {

                throw CocoaError(.validationNumberTooLarge)
            }
            destinationCardID = nextID
        }

        moved = moved.replacingLocation(id: destinationCardID, listTitle: destination.title)

        let wasSaved = source.savedCardIDs.remove(noteID) != nil /* Bookmark membership transferred with the Note */

        if wasSaved {

            destination.savedCardIDs.insert(moved.id)
        }

        destination.lists[destinationListIndex].cards.append(moved)
        collections[sourceIndex] = source
        collections[destinationIndex] = destination

        return moved
    }
}


///
/// Applies permanent removal to a complete Board snapshot
///
/// @section    Purpose
///     Keep active/archive removal and Board-local bookmark cleanup consistent
///
enum BoardContentDeletion {


    ///
    /// @fcn        BoardContentDeletion.card(_:in:savedCardIDs:)
    /// @brief      Remove a card from every active/archive partition of its owning Board
    /// @details    Only the supplied Board is inspected; equal IDs in other collections are
    ///             unaffected
    ///
    /// @param[in]     id            Board-local card identity
    /// @param[in,out] lists         Complete Board snapshot
    /// @param[in,out] savedCardIDs  Bookmarks belonging to that Board
    ///
    /// @return     (Void) removes matching records and their bookmark
    ///
    static func card(_ id: Int, in lists: inout [KanbanList], savedCardIDs: inout Set<Int>) {

        for index in lists.indices {

            lists[index].cards.removeAll { $0.id == id }
            lists[index].archivedCards.removeAll { $0.id == id }
        }

        savedCardIDs.remove(id)
    }


    ///
    /// @fcn        BoardContentDeletion.list(_:in:savedCardIDs:)
    /// @brief      Remove a list together with its active and archived cards
    /// @details    Removes bookmarks only for identities owned by the removed list
    ///
    /// @param[in]     id            Board-local list identity
    /// @param[in,out] lists         Complete Board snapshot
    /// @param[in,out] savedCardIDs  Bookmarks belonging to that Board
    ///
    /// @return     (Void) removes the list and contained bookmarks
    ///
    static func list(_ id: Int, in lists: inout [KanbanList], savedCardIDs: inout Set<Int>) {

        let removedIDs = Set(lists.filter { $0.id == id }.flatMap(\.allCards).map(\.id)) /* Card bookmarks to prune with the deleted list */

        lists.removeAll { $0.id == id }
        savedCardIDs.subtract(removedIDs)
    }
}


///
/// Defines optional synthetic examples for personal lists
///
/// @section    Purpose
///     Demonstrate organizing contexts without replacing existing content or introducing note records
///
enum PersonalListExample: String, CaseIterable, Identifiable {

    case onTheTable    = "On the Table"
    case inTheQueue    = "In the Queue"
    case scheduled     = "Scheduled"
    case shopping      = "Shopping"
    case upForBrew     = "Up for Brew"
    case miscellaneous = "Misc."

    ///
    /// @fcn        PersonalListExample.id
    /// @brief      Identify an example in the chooser
    /// @details    Uses the fixed display name; saved collections receive independent UUIDs
    /// @return     (String) example identity
    ///
    var id: String { rawValue } /* Stable personal List example identity */

    ///
    /// @fcn        PersonalListExample.coverIllustration
    /// @brief      Identify the optional original illustration for the first example card
    /// @details    Only three examples demonstrate covers; the remaining cards stay text-only
    /// @return     (ExampleCoverImage?) bundled illustration without creating attachment files
    ///
    var coverIllustration: ExampleCoverImage? { /* Offline illustration featured on the example's first card */
        switch self {

            case .onTheTable: .garden
            case .inTheQueue: .workspace
            case .upForBrew: .mountains
            default: nil
        }
    }

    ///
    /// @fcn        PersonalListExample.summary
    /// @brief      Explain the example's organizing intent
    /// @details    Describes optional use rather than assigning dates or required lifecycle states
    /// @return     (String) chooser explanation
    ///
    var summary: String { /* Brief description shown in the example picker */

        switch self {

            case .onTheTable:   "Things you would like to accomplish today."
            case .inTheQueue:    "Things to get to soon, perhaps this week."
            case .scheduled:     "Plans ahead, without automatic dates or reminders."
            case .shopping:      "Groceries, supplies, and purchases to consider."
            case .upForBrew:     "Ideas taking shape, with no commitment required."
            case .miscellaneous: "Useful reference details and thoughts to keep."
        }
    }

    ///
    /// @fcn        PersonalListExample.cards
    /// @brief      Supply synthetic card titles and supporting details
    /// @details    Fixtures contain no real personal records, user-media references, assignments, or dates
    /// @return     ([(String, String)]) ordered title/detail pairs
    ///
    var cards: [(String, String)] { /* Seeded example card headings and descriptions */

        switch self {

            case .onTheTable: [
                ("Water the garden", "Check the soil before watering the pots and garden beds."),
                ("Call Dad", "Make time for a relaxed catch-up."),
                ("Clean the kitchen", "Clear the counters, wash dishes, and wipe the stovetop."),
                ("Take a short walk", "Choose a nearby route and enjoy some time outside."),
                ("Prepare dinner", "Check what is already in the fridge before choosing a meal."),
                ("Reply to a friend", "Send the message you have been meaning to write."),
                ("Tidy the desk", "Put away loose papers and make room for the next task."),
                ("Choose tomorrow's first step", "Write down one useful starting point, without planning every hour.")
            ]
            case .inTheQueue: [
                ("Review household accounts", "Gather recent statements and note any questions."),
                ("Call the accountant", "Prepare a short list of questions before getting in touch."),
                ("Research a software release", "Read the release notes and compatibility requirements."),
                ("Update the coding project", "Choose a small change, run tests, and review the result."),
                ("Book a vehicle service", "Check the maintenance record and compare available appointments."),
                ("Sort the hallway cupboard", "Start with one shelf and set aside items to donate."),
                ("Plan meals for the week", "Choose a few flexible meals and check pantry supplies."),
                ("Return a borrowed book", "Arrange a convenient time with its owner.")
            ]
            case .scheduled: [
                ("Church this Sunday", "Confirm the service time and travel plan yourself."),
                ("Prepare to file taxes", "Check applicable deadlines and gather the documents you need."),
                ("Parents coming into town", "Confirm their travel details and discuss plans together."),
                ("Dinner with friends", "Agree on a place, time, and any food preferences."),
                ("Library workshop", "Check the organizer's current listing and registration details."),
                ("Home maintenance visit", "Confirm access arrangements with the service provider."),
                ("Birthday gathering", "Discuss the date and guest plans before making arrangements."),
                ("Community garden session", "Check the group's schedule and what to bring.")
            ]
            case .shopping: [
                ("Fresh vegetables", "Choose seasonal vegetables for the meals you plan to cook."),
                ("Fruit for the week", "Check what is already at home and buy a useful amount."),
                ("Bread and oats", "Compare pantry supplies before adding quantities."),
                ("Milk or a preferred alternative", "Choose the type and amount that suits your household."),
                ("Dish soap", "Check whether a refill is available."),
                ("Light bulbs", "Confirm the fitting and brightness before buying."),
                ("Charging cable", "Check connector compatibility and the length you need."),
                ("Garden supplies", "Measure the space and compare soil or pot options.")
            ]
            case .upForBrew: [
                ("Visit Grandma for her birthday", "Explore travel options and ask what she would enjoy."),
                ("Explore a Tanzania trip", "Research seasons, costs, and official travel guidance before deciding."),
                ("Plan time together as a couple", "Talk about activities you would both enjoy."),
                ("Try a new hobby", "Browse a few possibilities without committing to equipment yet."),
                ("Start a small herb garden", "Consider sunlight, space, and a few easy-to-use herbs."),
                ("Build a personal coding tool", "Capture the problem it could solve and a small first experiment."),
                ("Host a neighborhood meal", "Explore interest, venue options, and a manageable format."),
                ("Learn a new language", "Think about why it interests you and sample an introductory resource.")
            ]
            case .miscellaneous: [
                ("A friend's favorite band", "Synthetic reference: Derek enjoys Incubus."),
                ("Museum showtimes", "Keep the official listing link here and check it before a visit."),
                ("Conversation notes from a walk", "Example reflection: we talked about gardens and possible weekend plans."),
                ("A book recommendation", "Synthetic reference: a friend suggested exploring a local history book."),
                ("A meal worth making again", "Example: roasted vegetables with rice; add your own recipe details."),
                ("Gift ideas", "Keep possibilities here and check preferences before purchasing."),
                ("Project reference links", "Collect documentation links and explain why each is useful."),
                ("A thought to revisit", "Example: make more room for unhurried afternoons.")
            ]
        }
    }


    ///
    /// @fcn        PersonalListExample.makeCollection(existingTitles:)
    /// @brief      Build an independent example-list draft
    /// @details    Creates a fresh collection UUID, collision-safe title, and collection-local card
    ///             IDs. Explicit empty checklists and descriptions avoid the generic sample-card
    ///             defaults
    ///
    /// @param[in]  existingTitles  Current and retained collection names
    ///
    /// @return     (PersonalCollection) unsaved list draft with eight synthetic cards
    ///
    /// @post       No persistence, network operation, or existing record mutation occurs
    ///
    func makeCollection(existingTitles: [String]) -> PersonalCollection {

        let icon:  PersonalCollectionIcon /* Collection symbol selected for this example */
        let color: ProfileColor /* Collection accent selected for this example */

        switch self {

            case .onTheTable:    (icon, color) = (.tasks,    .coral)
            case .inTheQueue:    (icon, color) = (.project,  .teal)
            case .scheduled:     (icon, color) = (.upcoming, .graphite)
            case .shopping:      (icon, color) = (.shopping, .orange)
            case .upForBrew:     (icon, color) = (.home,     .green)
            case .miscellaneous: (icon, color) = (.notes,    .blue)
        }

        let title      = PersonalCollection.uniqueTitle(rawValue, existingTitles: existingTitles) /* Example name made unique within the directory */
        var collection = PersonalCollection(title: title, kind: .list, icon: icon, color: color) /* New personal List populated from the example */

        collection.lists[0].cards = cards.enumerated().map { index, content in
        
            var card = KanbanCard(                      /* Seeded record receiving example content and optional cover */
                id: index, word: content.0, listTitle: title, checklists: [],
                descriptionOverride: content.1, subtitleOverride: "Example"
            )
            if index == 0, let illustration = coverIllustration { /* Featured offline image for the first seeded card */

                let attachment = KanbanAttachment(mediaKind: .photo, exampleImage: illustration) /* Photo record referencing the bundled example image */

                card.attachments = [attachment]
                card.coverAttachmentID = attachment.id
            }

            return card
        }

        return collection
    }
}


///
/// Provides the supported symbols for saved personal collections
///
/// @section    Purpose
///     Keep collection icon choices explicit and persistable
///
enum PersonalCollectionIcon: String, CaseIterable, Codable {
    case notes = "note.text"
    case tasks = "checklist"
    case shopping = "cart"
    case reminders = "bell"
    case project = "square.stack.3d.up"
    case home = "house"
    case heart = "heart"
    case upcoming = "calendar"
}


///
/// Represents a user-owned list or multi-list board
///
/// @section    Purpose
///     Keep collection identity, presentation, board content, and bookmarks together
///
struct PersonalCollection: Identifiable, Hashable, Codable {
    let id: UUID                         /* Stable collection identity */
    var title: String                    /* User-facing collection title */
    let kind: PersonalCollectionKind     /* List or multi-column board */
    var icon: PersonalCollectionIcon     /* Symbol shown for the collection */
    var color: ProfileColor              /* Collection accent color */
    var lists: [KanbanList]              /* Lists and cards owned by the collection */
    var savedCardIDs: Set<Int>           /* Bookmarked cards retained by the collection */
    var isArchived: Bool? = nil          /* Optional archive state for older saved data */

    ///
    /// @fcn        PersonalCollection.isActive
    /// @brief      Determine whether the collection is active
    /// @details    Treats a missing archive flag in older snapshots as active
    ///
    /// @return     (Bool) whether the collection is not archived
    /// @post       Collection state is unchanged
    ///
    var isActive: Bool { isArchived != true } /* Whether the collection belongs in the active directory */


    ///
    /// @fcn        PersonalCollection.init(id:title:kind:icon:color:)
    /// @brief      Create a personal collection with its initial list structure
    /// @details    Single-list collections receive one list; boards receive Ideas, In progress,
    ///             and Done lists
    ///
    /// @param[in]  id     Stable collection identity
    /// @param[in]  title  User-facing collection title
    /// @param[in]  kind   Whether the collection is a list or board
    /// @param[in]  icon   Symbol used for the collection
    /// @param[in]  color  Accent color used for the collection
    ///
    /// @return     (PersonalCollection) initialized collection with empty lists and bookmarks
    /// @post       No collection persistence or board edits are performed
    ///
    init(
        id: UUID = UUID(), title: String, kind: PersonalCollectionKind,
        icon: PersonalCollectionIcon = .notes, color: ProfileColor = .teal
    ) {

        self.id = id
        self.title = title
        self.kind = kind
        self.icon = icon
        self.color = color

        let columns = kind == .list ? [title] : ["Ideas", "In progress", "Done"] /* Initial column headings selected by collection kind */

        lists = columns.enumerated().map { KanbanList(id: $0.offset, title: $0.element, cards: []) }
        savedCardIDs = []
    }


    ///
    /// @fcn        PersonalCollection.cardCount
    /// @brief      Count active non-divider cards owned by the collection
    /// @details    Excludes archived lists and section-divider rows
    ///
    /// @return     (Int) number of active cards across the collection
    /// @post       Collection lists and cards are unchanged
    ///
    var cardCount: Int { /* Active non-divider records counted for the directory */
        lists.filter { !$0.isArchived }.reduce(0) { $0 + $1.cards.filter { !$0.isSectionDivider }.count }
    }


    ///
    /// @fcn        PersonalCollection.rename(to:)
    /// @brief      Rename a collection and synchronize a single-list title
    /// @details    For list collections, updates the title on both active and archived cards
    ///
    /// @param[in]  name  New collection name
    ///
    /// @return     (Void) updates the collection title and, for lists, its card context
    ///
    /// @post       Board collections retain their internal list titles
    ///
    mutating func rename(to name: String) {

        title = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard kind == .list, let column = lists.first else { /* Single-list column whose name follows the collection */

            return
        }

        var cards = column.cards /* Active records receiving the renamed list context */

        for index in cards.indices {

            cards[index].listTitle = title
        }

        var archivedCards = column.archivedCards /* Archived records receiving the renamed list context */

        for index in archivedCards.indices {

            archivedCards[index].listTitle = title
        }
        lists[0] = KanbanList(id: column.id, title: title, cards: cards, archivedCards: archivedCards, newItemPresentation: column.newItemPresentation)
        lists[0].isArchived = column.isArchived
    }


    ///
    /// @fcn        PersonalCollection.addNote(title:body:)
    /// @brief      Append one writing-first item to an active personal List
    /// @details    Allocates across active and archived collection records; rejects blank titles,
    ///             non-List collections, and collections without an active destination
    /// @param[in]  title  User-entered Note title
    /// @param[in]  body   Note body preserved exactly
    /// @param[in]  createdAt  Creation time retained from the draft, or captured at creation
    /// @return     (Void) appends one Note while preserving every existing record
    /// @throws     CocoaError when the destination or title is invalid
    ///
    mutating func addNote(title: String, body: String, createdAt: Date = .now) throws {

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines) /* Nonblank Note heading used for creation */

        guard kind == .list, isActive, !trimmedTitle.isEmpty,
              let listIndex = lists.firstIndex(where: { !$0.isArchived }) else { /* Active column receiving the new Note */

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        let nextCardID = (lists.flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1 /* Next identity beyond all retained collection records */
        var destination = lists[listIndex] /* Column snapshot receiving the new Note */
        var note = destination.makeItem(id: nextCardID, title: trimmedTitle, description: body, createdAt: createdAt) /* New record carrying the draft's content and creation time */

        note.presentation = .note
        note.checklists = []
        destination.cards.append(note)
        lists[listIndex] = destination
    }


    ///
    /// @fcn        PersonalCollection.matches(_:)
    /// @brief      Search the collection title, active lists, and active cards
    /// @details    Uses localized-standard matching and ignores section dividers
    ///
    /// @param[in]  query  Search text entered by the user
    ///
    /// @return     (Bool) whether the query is empty or matches searchable collection content
    ///
    /// @post       Collection state is unchanged
    ///
    func matches(_ query: String) -> Bool {

        let term = query.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized collection-search query */

        return term.isEmpty || title.localizedStandardContains(term) || lists.filter { !$0.isArchived }.contains { list in
            list.title.localizedStandardContains(term) || list.cards.contains {
                !$0.isSectionDivider && ($0.word.localizedStandardContains(term)
                    || ($0.descriptionOverride?.localizedStandardContains(term) ?? false))
            }
        }
    }


    ///
    /// @fcn        PersonalCollection.restore(existingTitles:)
    /// @brief      Restore the collection and resolve a conflicting title
    /// @details    Adds a restored suffix for the Week Board, then selects a unique title
    ///
    /// @param[in]  existingTitles  Titles that must remain unique
    ///
    /// @return     (Void) updates the title if needed and clears archive state
    ///
    /// @post       The collection becomes active
    ///
    mutating func restore(existingTitles: [String]) {

        let base = title == "Week Board" ? "Week Board (Restored)" : title /* Restore name avoiding confusion with the live Week tab */

        title = Self.uniqueTitle(base, existingTitles: existingTitles)
        isArchived = false
    }


    ///
    /// @fcn        PersonalCollection.archivedWeekBoard(lists:savedCardIDs:)
    /// @brief      Create an archived collection from the Week Board snapshot
    /// @details    Retains supplied lists and bookmarks in a board collection marked archived
    ///
    /// @param[in]  lists         Week Board lists to retain
    /// @param[in]  savedCardIDs  Bookmarks associated with the Week Board
    ///
    /// @return     (PersonalCollection) archived Week Board collection
    ///
    static func archivedWeekBoard(lists: [KanbanList], savedCardIDs: Set<Int>) -> PersonalCollection {

        var board = PersonalCollection(title: "Week Board", kind: .board, icon: .project) /* Archived collection preserving the Week workspace */

        board.lists = lists
        board.savedCardIDs = savedCardIDs
        board.isArchived = true

        return board
    }


    ///
    /// @fcn        PersonalCollection.uniqueTitle(_:existingTitles:)
    /// @brief      Select a title not already in use
    /// @details    Compares titles without case sensitivity and appends a numbered suffix on
    ///             collision
    ///
    /// @param[in]  base            Preferred title
    /// @param[in]  existingTitles  Titles that must remain unique
    ///
    /// @return     (String) unique title based on base
    ///
    /// @post       Input title values are unchanged
    ///
    static func uniqueTitle(_ base: String, existingTitles: [String]) -> String {

        let titles = Set(existingTitles.map { $0.lowercased() }) /* Existing names compared without case distinctions */
        var candidate = base /* Proposed name retried until unique */
        var number = 2 /* Numeric suffix for resolving name collisions */

        while titles.contains(candidate.lowercased()) {

            candidate = "\(base) (\(number))"
            number += 1
        }

        return candidate
    }
}


///
/// Loads and saves personal collection snapshots in user defaults
///
/// @section    Purpose
///     Persist user-owned collection metadata and board content locally
///
enum PersonalCollectionStore {
    /// Versioned storage key for saved personal collections.
    private static let key = "Plenact.PersonalCollections.v1" /* Versioned personal collection persistence key */


    ///
    /// @fcn        PersonalCollectionStore.load(from:)
    /// @brief      Load saved personal collections
    /// @details    Returns an empty collection when no value exists or decoding fails
    ///
    /// @param[in]  defaults  Defaults store to read
    ///
    /// @return     ([PersonalCollection]) decoded collections or an empty array
    ///
    /// @post       Stored values are unchanged
    ///
    static func load(from defaults: UserDefaults = .standard) -> [PersonalCollection] {

        guard let data = defaults.data(forKey: key) else { /* Stored personal collection document */

            return []
        }

        return (try? JSONDecoder().decode([PersonalCollection].self, from: data)) ?? []
    }


    ///
    /// @fcn        PersonalCollectionStore.save(_:to:)
    /// @brief      Save personal collections when encoding succeeds
    /// @details    Encodes the complete collection snapshot and writes it to the versioned key
    ///
    /// @param[in]  collections  Collections to persist
    /// @param[in]  defaults     Defaults store to update
    ///
    /// @return     (Void) writes encoded data when encoding succeeds
    ///
    /// @post       Encoding failure leaves the stored value unchanged
    ///
    static func save(_ collections: [PersonalCollection], to defaults: UserDefaults = .standard) {

        guard let data = try? JSONEncoder().encode(collections) else { /* Encoded collection snapshot ready for storage */

            return
        }

        defaults.set(data, forKey: key)
    }


    ///
    /// @fcn        PersonalCollectionStore.saveChecked(_:to:)
    /// @brief      Encode and save personal collections while reporting encoding failures
    /// @details    Propagates JSON encoding errors to the caller instead of silently skipping the
    ///             write
    ///
    /// @param[in]  collections  Collections to persist
    /// @param[in]  defaults     Defaults store to update
    ///
    /// @return     (Void) writes the encoded collection snapshot
    ///
    /// @throws     EncodingError when the collection snapshot cannot be encoded
    ///
    static func saveChecked(_ collections: [PersonalCollection], to defaults: UserDefaults = .standard) throws {

        defaults.set(try JSONEncoder().encode(collections), forKey: key)
    }


    ///
    /// @fcn        PersonalCollectionStore.archiveBoard(id:in:to:)
    /// @brief      Archive an active board collection and persist the result
    /// @details    Rejects missing, non-board, and already archived collection identities
    ///
    /// @param[in]  id           Identity of the board to archive
    /// @param[in]  collections  Current collection snapshot
    /// @param[in]  defaults     Defaults store to update
    ///
    /// @return     ([PersonalCollection]) updated snapshot with the board archived
    ///
    /// @throws     CocoaError when no active board has the supplied identity
    /// @throws     EncodingError when the updated snapshot cannot be encoded
    ///
    static func archiveBoard(
        id: UUID,
        in collections: [PersonalCollection],
        to defaults: UserDefaults = .standard
    ) throws -> [PersonalCollection] {

        guard let index = collections.firstIndex(where: { /* Position of the collection to archive */

            $0.id == id && $0.kind == .board && $0.isActive
        }) else {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var updated = collections /* Directory snapshot carrying the archive state change */

        updated[index].isArchived = true
        try saveChecked(updated, to: defaults)

        return updated
    }


    ///
    /// @fcn        PersonalCollectionStore.archiveCollection(id:in:to:)
    /// @brief      Retain an active personal list or Board outside Library
    /// @details    Saves the complete updated collection snapshot before returning it
    ///
    /// @param[in]  id           Collection UUID
    /// @param[in]  collections  Current complete snapshot
    /// @param[in]  defaults     Destination preferences
    ///
    /// @return     ([PersonalCollection]) successfully saved archive state
    ///
    /// @throws     Validation or encoding errors; original state is unchanged
    ///
    static func archiveCollection(
        id: UUID, in collections: [PersonalCollection], to defaults: UserDefaults = .standard
    ) throws -> [PersonalCollection] {

        guard let index = collections.firstIndex(where: { /* Position of the active collection to archive */

            $0.id == id && $0.isActive
        }) else {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var updated = collections /* Directory snapshot carrying the archived collection */

        updated[index].isArchived = true
        try saveChecked(updated, to: defaults)

        return updated
    }
}


///
/// Captures the Board state and Today-list selection before loading example data
///
/// @section    Purpose
///     Preserve the prior local state for an explicit undo operation
///
struct ExampleLoadUndoSnapshot: Codable, Equatable {

    let lists: [KanbanList]   /* Board lists to restore */
    let todayListID: Int?     /* Previously selected Today list, when set */
}


///
/// Stores the undo snapshot for loading example Board data
///
/// @section    Purpose
///     Keep one locally persisted pre-example snapshot available for undo
///
enum ExampleLoadUndoStore {

    /// Versioned storage key for the saved undo snapshot.
    private static let storageKey = "Plenact.ExampleLoadUndo.v1" /* Versioned example-load recovery key */


    ///
    /// @fcn        ExampleLoadUndoStore.save(lists:todayListID:to:)
    /// @brief      Save a pre-example Board snapshot
    /// @details    Returns false when the snapshot cannot be encoded
    ///
    /// @param[in]  lists        Board lists to preserve
    /// @param[in]  todayListID  Selected Today list identity, if any
    /// @param[in]  defaults     Defaults store to update
    ///
    /// @return     (Bool) whether the encoded snapshot was saved
    ///
    /// @post       A successful save replaces the previously stored undo snapshot
    ///
    @discardableResult
    static func save(
        lists: [KanbanList],
        todayListID: Int?,
        to defaults: UserDefaults = .standard
    ) -> Bool {

        let snapshot = ExampleLoadUndoSnapshot(lists: lists, todayListID: todayListID) /* Week state and Today selection retained for undo */

        guard let data = try? JSONEncoder().encode(snapshot) else { /* Encoded recovery snapshot ready for storage */

            return false
        }

        defaults.set(data, forKey: storageKey)

        return true
    }


    ///
    /// @fcn        ExampleLoadUndoStore.load(from:)
    /// @brief      Load the saved pre-example Board snapshot
    /// @details    Returns nil when no snapshot exists or decoding fails
    ///
    /// @param[in]  defaults  Defaults store to read
    ///
    /// @return     (ExampleLoadUndoSnapshot?) decoded snapshot, or nil
    ///
    /// @post       Stored values are unchanged
    ///
    static func load(from defaults: UserDefaults = .standard) -> ExampleLoadUndoSnapshot? {

        guard let data = defaults.data(forKey: storageKey) else { /* Stored example-load recovery document */

            return nil
        }

        return try? JSONDecoder().decode(ExampleLoadUndoSnapshot.self, from: data)
    }


    ///
    /// @fcn        ExampleLoadUndoStore.clear(from:)
    /// @brief      Remove the saved pre-example Board snapshot
    /// @details    Deletes only the undo snapshot key from the selected defaults store
    ///
    /// @param[in]  defaults  Defaults store to update
    ///
    /// @return     (Void) removes the saved snapshot
    ///
    static func clear(from defaults: UserDefaults = .standard) {

        defaults.removeObject(forKey: storageKey)
    }
}


///
/// Persists and restores Board snapshots in local user defaults
///
/// @section    Purpose
///     Keep Board data available across launches without requiring a remote service
///
/// @details    Background operations report load and save failures through DatabaseActivity
///
enum KanbanBoardPersistence {

    /// Versioned storage key for the serialized Board snapshot.
    private static let storageKey = "Plenact.Board.v1" /* Versioned local Board snapshot key */

    /// Serial queue used for Board snapshot I/O.
    private static let queue = DispatchQueue(label: "Plenact.Board.persistence", qos: .userInitiated) /* Serial worker for ordered Board persistence */


    ///
    /// @fcn        KanbanBoardPersistence.saveListsChecked(_:suiteName:)
    /// @brief      Save a destructive snapshot before changing visible state
    /// @details    Encodes first, then waits behind earlier queued writes to preserve save ordering
    ///
    /// @param[in]  lists      Complete Week snapshot
    /// @param[in]  suiteName  Optional isolated preference suite
    ///
    /// @return     (Void) save a destructive snapshot before changing visible state
    ///
    /// @throws     Encoding or preference-suite errors; no write occurs on encoding failure
    ///
    static func saveListsChecked(_ lists: [KanbanList], suiteName: String? = nil) throws {

        let data = try JSONEncoder().encode(lists) /* Encoded Board snapshot for the checked save */

        try queue.sync {
            let defaults = try persistenceDefaults(suiteName: suiteName) /* Validated preferences store receiving the Board document */

            defaults.set(data, forKey: storageKey)
        }
    }


    ///
    /// @fcn        KanbanBoardPersistence.loadListsInBackground(suiteName:)
    /// @brief      Load Board lists using the persistence queue
    /// @details    Reports load failures and displays deterministic sample data without deleting
    ///             the unreadable saved snapshot
    ///
    /// @param[in]  suiteName  Optional defaults suite; nil selects standard defaults
    ///
    /// @return     ([KanbanList]) decoded lists or the starter Board on failure
    ///
    /// @post       Saved data is not modified by loading
    ///
    @MainActor
    static func loadListsInBackground(suiteName: String? = nil) async -> [KanbanList] {

        let activity = DatabaseActivity.shared /* Shared persistence progress and failure reporter */
        let operation = activity.begin("Loading Board...") /* Progress identity for the pending Board load */

        defer {

            activity.end(operation)
        }

        let result: Result<[KanbanList], Error> = await withCheckedContinuation { continuation in /* Background load outcome delivered to the caller */
            queue.async {
                continuation.resume(returning: Result {
                    let defaults = try persistenceDefaults(suiteName: suiteName) /* Validated preferences store supplying the Board document */

                    guard let data = defaults.data(forKey: storageKey) else { /* Stored Board document awaiting decoding */

                        return SampleData.lists
                    }
                    return try JSONDecoder().decode([KanbanList].self, from: data)
                })
            }
        }

        switch result {

            case .success(let lists): /* Decoded Board snapshot */
                return lists
            case .failure(let error): /* Persistence or decoding failure reported to the caller */

                activity.report("Could not load the saved Board: \(error.localizedDescription) The starter Board is displayed; saved data has not been removed.")

                return SampleData.lists
        }
    }


    ///
    /// @fcn        KanbanBoardPersistence.saveListsInBackground(_:)
    /// @brief      Request a background save of Board lists
    /// @details    Enqueues the supplied snapshot for serialized persistence
    ///
    /// @param[in]  lists  Board lists to save
    ///
    /// @return     (Void) forwards the snapshot to the save queue
    ///
    @MainActor
    static func saveListsInBackground(_ lists: [KanbanList]) {

        enqueueSave(lists)
    }


    ///
    /// @fcn        KanbanBoardPersistence.enqueueSave(_:suiteName:onSuccess:)
    /// @brief      Queue a Board snapshot for asynchronous persistence
    /// @details    Performs the write on the serial persistence queue and reports write errors
    ///
    /// @param[in]  lists      Board lists to save
    /// @param[in]  suiteName  Optional defaults suite; nil selects standard defaults
    /// @param[in]  onSuccess  Optional main-actor cleanup invoked only after a successful write
    ///
    /// @return     (Void) schedules the save operation
    ///
    @MainActor
    static func enqueueSave(
        _ lists: [KanbanList], suiteName: String? = nil,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {

        let activity = DatabaseActivity.shared /* Shared persistence progress and failure reporter */
        let operation = activity.begin("Saving Board...") /* Progress identity for the queued Board save */

        // A serial queue preserves snapshot order even when edits arrive faster than encoding.
        queue.async {
            let result = Result { /* Success or failure of the queued persistence operation */
                let defaults = try persistenceDefaults(suiteName: suiteName) /* Validated preferences store receiving the Board document */
                let data = try JSONEncoder().encode(lists) /* Encoded Board snapshot ready for storage */

                defaults.set(data, forKey: storageKey)
            }
            Task { @MainActor in
                if case .failure(let error) = result { /* Save failure surfaced through the activity reporter */

                    activity.report("Could not save the Board: \(error.localizedDescription) Your latest changes are not saved. Please try editing again.")
                } else {

                    onSuccess?()
                }

                activity.end(operation)
            }
        }

    }


    ///
    /// @fcn        KanbanBoardPersistence.persistenceDefaults(suiteName:)
    /// @brief      Resolve the defaults store for a persistence operation
    /// @details    Uses standard defaults when no suite name is supplied
    ///
    /// @param[in]  suiteName  Optional defaults suite name
    ///
    /// @return     (UserDefaults) selected defaults store
    ///
    /// @throws     CocoaError when the named defaults suite cannot be created
    ///
    private static func persistenceDefaults(suiteName: String?) throws -> UserDefaults {

        guard let suiteName else { /* Named preferences domain requested by the caller */

            return .standard
        }

        guard let defaults = UserDefaults(suiteName: suiteName) else { /* Preferences store opened for the requested domain */

            throw CocoaError(.fileReadUnknown)
        }

        return defaults
    }


    ///
    /// @fcn        KanbanBoardPersistence.loadLists()
    /// @brief      Load the saved board lists
    /// @details    Decodes the locally stored JSON snapshot and returns sample data if no valid
    ///             snapshot exists
    ///
    /// @return     ([KanbanList]) restored board lists or the deterministic starter board
    ///
    /// @pre        UserDefaults may contain data encoded by this persistence format
    /// @post       Stored data is unchanged; callers receive a usable board list value
    ///
    static func loadLists() -> [KanbanList] {

          guard let data = UserDefaults.standard.data(forKey: storageKey), /* Encoded local Board data */

              let lists = try? JSONDecoder().decode([KanbanList].self, from: data) else { /* Successfully decoded lists */
                
            return SampleData.lists
        }

        return lists
    }


    ///
    /// @fcn        KanbanBoardPersistence.saveLists(_:)
    /// @brief      Save the current board lists
    /// @details    Encodes the supplied list and card state as JSON and writes it to the versioned
    ///             user-defaults key
    ///
    /// @param[in]  lists  Board lists and their current card state
    ///
    /// @return     (Void) stores the encoded board snapshot when encoding succeeds
    ///
    /// @pre        lists contains the current in-memory board state
    /// @post       A valid encoded snapshot is stored locally; encoding failure leaves prior stored
    ///             data unchanged
    ///
    static func saveLists(_ lists: [KanbanList]) {

        guard let data = try? JSONEncoder().encode(lists) else { /* Encoded Board snapshot for legacy synchronous storage */

            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }
}


// -------------------------------------- MARK: - Sample Data ----------------------------------- //


///
/// Provides deterministic sample content used by the board and previews
///
/// @section    Purpose
///     Construct seven weekday lists with realistic planning cards and representative divider rows
///     without requiring persistence
///
enum SampleData {

    /// Titles assigned to the seven horizontally navigable Board lists.
    static let listTitles = [ /* Weekday list ordering for the starter Board */
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]

    /// Planning-oriented card titles aligned with each weekday list.
    static let cardTitlesByDay: [[String]] = [ /* Synthetic activity titles grouped by weekday */
        [
            "Review the week ahead",
            "Set three priorities",
            "Prepare for focused work",
            "Laundry session",
            "Take a movement break",
            "Evening reset"
        ],
        [
            "Review today's schedule",
            "Focus session",
            "Reply to important messages",
            "Plan groceries",
            "Capture a new idea",
            "Prepare for tomorrow"
        ],
        [
            "Midweek check-in",
            "Project work session",
            "Review daily finances",
            "Reset the home space",
            "Take a walk",
            "Review recent notes"
        ],
        [
            "Choose today's focus",
            "Deep work block",
            "Make an important call",
            "Complete errands",
            "Make time for creativity",
            "Evening review"
        ],
        [
            "Close weekly priorities",
            "Finish the current task",
            "Tidy the workspace",
            "Complete personal admin",
            "Plan the weekend",
            "Weekly reflection"
        ],
        [
            "Plan a slower morning",
            "Work on a home project",
            "Laundry and linens",
            "Spend time outdoors",
            "Connect with someone",
            "Prepare for Sunday"
        ],
        [
            "Weekly reflection",
            "Review the upcoming calendar",
            "Plan Monday priorities",
            "Prepare meals",
            "Rest and recharge",
            "Capture notes and ideas"
        ]
    ]


    ///
    /// @fcn        SampleData.actionDetail(title:description:steps:comment:)
    /// @brief      Build one deterministic reduced-detail demonstration
    /// @details    Creates standard nested actions and one respectful sample comment without
    ///             introducing recursive linked or detailed actions
    ///
    /// @param[in]  title        Nested checklist title
    /// @param[in]  description  Supporting Action Detail text
    /// @param[in]  steps        Standard nested action titles
    /// @param[in]  comment      Sample comment body
    ///
    /// @return     (KanbanChecklistActionDetail) configured demonstration detail
    ///
    private static func actionDetail(title: String, description: String, steps: [String], comment: String) -> KanbanChecklistActionDetail {

        let nestedItems = steps.map { KanbanChecklistItem(title: $0) }   /* Standard nested actions */
        let checklist   = KanbanChecklist(title: title, items: nestedItems) /* Nested checklist    */
        let sampleDate  = Date(timeIntervalSince1970: 1_790_467_200)     /* Stable sample date      */
        let comments    = [KanbanComment(author: "Plenact Demo", body: comment, createdAt: sampleDate)] /* Sample discussion */

        return KanbanChecklistActionDetail(
            description: description,
            checklists:  [checklist],
            comments:    comments
        )
    }
    

    ///
    /// @fcn        SampleData.enrichedChecklists(for:linkedCard:)
    /// @brief      Add linked-card and Action Detail demonstrations to one starter card
    /// @details    Appends one Board-card link and two reduced details to the first seeded
    ///             checklist while preserving all existing standard actions and checklist groups
    ///
    /// @param[in]  card        Starter card receiving demonstration actions
    /// @param[in]  linkedCard  Existing starter card used as the navigation target
    ///
    /// @return     ([KanbanChecklist]) enriched checklist collection
    ///
    private static func enrichedChecklists(for card: KanbanCard, linkedCard: KanbanCard) -> [KanbanChecklist] {

        guard let firstChecklist = card.checklists.first else { /* Initial checklist used to seed example actions */

            return card.checklists
        }

        let linkedAction = KanbanChecklistItem(         /* Existing card link */
            title:   "Open \(linkedCard.word) card",
            content: .linkedCard(cardID: linkedCard.id)
        )
        let planningDetail = actionDetail(              /* Planning subcard */
            title:       "Prepare",
            description: "Collect the context needed before starting the \(card.word) activity.",
            steps:       ["Choose the next clear step", "Gather anything needed"],
            comment:     "This detail stays with the checklist action."
        )
        let reviewDetail = actionDetail(                /* Review subcard */
            title:       "Review",
            description: "Capture what worked and what should happen next for \(card.word).",
            steps:       ["Note the result", "Choose a follow-up action"],
            comment:     "A short review can make the next session easier."
        )
        let detailActions = [                     /* Owned subcard actions */
            KanbanChecklistItem(
                title:   "Prepare \(card.word) details",
                content: .actionDetail(planningDetail)
            ),
            KanbanChecklistItem(
                title:   "Review \(card.word) outcome",
                content: .actionDetail(reviewDetail)
            )
        ]
        let enrichedFirstChecklist = KanbanChecklist(   /* Demonstration checklist */
            id:    firstChecklist.id,
            title: firstChecklist.title,
            items: firstChecklist.items + [linkedAction] + detailActions
        )

        return [enrichedFirstChecklist] + card.checklists.dropFirst()
    }


    /// Complete starter Board generated from weekday lists and planning cards.
    static let lists: [KanbanList] = { /* Deterministic seven-day starter Board */

        var globalIndex = 0 /* Board-wide list/card seed identity counter */

        var initializedLists = listTitles.enumerated().map { listIndex, title in /* Seed one list per weekday */

            let cards = cardTitlesByDay[listIndex].map { cardTitle -> KanbanCard in /* Seed the day's activities */

                var card = KanbanCard(                  /* Construct one synthetic starter card */
                    id:             globalIndex,
                    word:           cardTitle,
                    listTitle:      title,
                    isTitleChecked: globalIndex % 3 == 0,
                    members:        ["Justin Reina"],
                    labelIDs:       [LabelLibrary.starterLabelIDs[globalIndex % LabelLibrary.starterLabelIDs.count]]
                )

                if listIndex < 3 && cardTitle == cardTitlesByDay[listIndex].first {

                    let illustration = ExampleCoverImage.allCases[listIndex] /* Bundled cover selected for this example list */
                    let attachment = KanbanAttachment(mediaKind: .photo, exampleImage: illustration) /* Photo record referencing the bundled cover */

                    card.attachments = [attachment]
                    card.coverAttachmentID = attachment.id
                }

                globalIndex += 1

                return card
            }

            return KanbanList(id: listIndex, title: title, cards: cards)
        }

        // Positions at which divider rows should be inserted for each list
        let dividerPositionsByList = Array(repeating: [3], count: listTitles.count)   /* Daily focus divider */

        // Insert divider rows into the initialized lists at the specified positions
        for listIndex in dividerPositionsByList.indices {

            // Insert dividers for the current list
            for (dividerOffset, cardPosition) in dividerPositionsByList[listIndex].enumerated() {

                // Insert a divider card at the calculated position within the current list
                initializedLists[listIndex].cards.insert(
                    KanbanCard(
                        id:        globalIndex,
                        word:      "---",
                        listTitle: initializedLists[listIndex].title,
                        isDivider: true
                    ),
                    at: cardPosition + dividerOffset
                )

                globalIndex += 1
            }
        }

        let baseLists = initializedLists   /* Unmodified link-target snapshot */

        for listIndex in initializedLists.indices {

            let targetListIndex = (listIndex + 1) % initializedLists.count   /* Next Board list */
            let targetCards = baseLists[targetListIndex].cards.filter { !$0.isSectionDivider } /* Link targets */

            for cardIndex in initializedLists[listIndex].cards.indices {

                let sourceCard = initializedLists[listIndex].cards[cardIndex]   /* Card being enriched */

                guard !sourceCard.isSectionDivider, !targetCards.isEmpty else {

                    continue
                }

                let linkedCard = targetCards[sourceCard.id % targetCards.count] /* Stable target card */

                initializedLists[listIndex].cards[cardIndex].checklists = enrichedChecklists(
                    for:        sourceCard,
                    linkedCard: linkedCard
                )
            }
        }

        return initializedLists
    }()
}
