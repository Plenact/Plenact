// --------------------------------------------------------------------------------------------------
// @file       Models.swift
// @brief      Domain models and deterministic sample data for the Plenact board
// @details    Defines cards, lists, derived display values, and weekday starter content
//
// @notes      Sample data is deterministic so previews and UI behavior remain reproducible
//
// @section    Opens
//     Consider more board\ specific naming to file
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
enum CardAssigneeKind: String, Codable {

    case registeredUser   /* Stable server user reference */
    case manual           /* User-entered display name     */
}


///
/// Represents one person associated with a card
///
/// @section    Purpose
///     Preserve a stable registered-user reference or a manual display name without conflating them
///
struct CardAssignee: Identifiable, Hashable, Codable, ExpressibleByStringLiteral {

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

///
/// Represents one card displayed on a kanban list
///
/// @section    Purpose
///     Keep the card's identity, displayed word, list membership, and derived detail content together
///
/// @note   Derived values are deterministic so the board and previews remain reproducible
///
struct KanbanCard: Identifiable, Hashable, Codable {

    let id:                   Int                 /* Stable numeric identifier for the card             */
    var word:                 String              /* Display word shown as the card's title             */
    var listTitle:            String              /* Name of the list where the card resides            */
    var isDivider:            Bool                /* Whether this item is a movable section divider     */
    var isTitleChecked:       Bool                /* Whether the card's main title checkbox is selected */
    var members:              [CardAssignee]      /* Registered and manual card assignments             */
    var labelIDs:             [String]            /* Stable IDs of labels assigned to the card          */

    var startDate:            Date?               /* Optional start date for the card                   */
    var dueDate:              Date?               /* Optional due date for the card                     */
    var descriptionOverride:  String?             /* Optional user-edited description                   */
    var subtitleOverride:     String?             /* Optional user-edited board subtitle                */

    var checklists:           [KanbanChecklist]   /* List of checklists associated with the card        */
    var comments:             [KanbanComment]     /* Comments posted to the card's activity             */
    var attachments:          [KanbanAttachment]? /* Photo attachments stored with the card             */

    var dismissedActivityIDs: Set<String>         /* Generated activity entries removed by the user     */

    /// Indicates whether this item should render and behave as a section divider
    var isSectionDivider: Bool { /* Combined divider flag and recognized marker */
        isDivider || Self.isDividerTitle(word)
    }

    /// Recognizes the ASCII marker and dash characters substituted by iOS smart punctuation
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
    /// @param[in]  descriptionOverride   Optional user-edited description
    ///
    /// @return     (KanbanCard) configured card instance
    ///
    /// @pre        All values should be valid for the board's deterministic sample data
    /// @post       The card contains the provided identity, title text, and checked state
    ///
    init(id: Int, word: String, listTitle: String, isDivider: Bool = false, isTitleChecked: Bool = false, startDate: Date? = nil, dueDate: Date? = nil, checklists: [KanbanChecklist]? = nil, comments: [KanbanComment] = [], members: [CardAssignee] = [], labelIDs: [String] = [], attachments: [KanbanAttachment]? = nil, dismissedActivityIDs: Set<String> = [], descriptionOverride: String? = nil, subtitleOverride: String? = nil) {

        self.id                   = id                      /* Stable numeric identifier for the card             */
        self.word                 = word                    /* Display word shown as the card's title             */
        self.listTitle            = listTitle               /* Name of the list where the card resides            */
        self.isDivider            = isDivider               /* Whether this item renders as a section divider     */
        self.isTitleChecked       = isTitleChecked          /* Whether the card's main title checkbox is selected */
        self.startDate            = startDate               /* Optional start date for the card                   */
        self.dueDate              = dueDate                 /* Optional due date for the card                     */
        self.comments             = comments                /* Array of comments associated with the card         */
        self.members              = members                 /* Names of users assigned to the card                */
        self.labelIDs             = labelIDs                /* Stable IDs of labels assigned to the card          */
        self.attachments          = attachments             /* Photo attachment metadata for the card             */
        self.dismissedActivityIDs = dismissedActivityIDs    /* Set of activity IDs that were dismissed by user    */
        self.descriptionOverride  = descriptionOverride     /* Optional user-edited description                   */
        self.subtitleOverride     = subtitleOverride        /* Optional user-edited subtitle                      */
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
            dismissedActivityIDs: try container.decodeIfPresent(Set<String>.self, forKey: .dismissedActivityIDs) ?? [],
            descriptionOverride:  try container.decodeIfPresent(String.self, forKey: .descriptionOverride),
            subtitleOverride:     try container.decodeIfPresent(String.self, forKey: .subtitleOverride)
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
        case checklists
        case comments
        case members
        case labelIDs
        case attachments
        case dismissedActivityIDs
        case descriptionOverride
        case subtitleOverride
    }

    /// Human-readable label for the card's start date
    var startDateLabel: String { /* Start-date badge text or default */

        guard let startDate else { /* No explicit start date */
            return "Today"
        }

        return Self.dateFormatter.string(from: startDate)
    }

    /// Human-readable label for the card's due date
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
    var subtitle: String { /* Supporting card text or user override */
        if let subtitleOverride { /* Explicitly edited subtitle */
            return subtitleOverride
        }

        return ["A small idea with suspiciously large ambitions", "Make progress before the coffee gets cold", "A practical plan, lightly seasoned with chaos", "One more useful thing for today's board", "Future success, pending a snack break"][id % 5]
    }

    /// Checklist labels used by the card detail presentation
    var checklistItems: [String] { /* Titles from the first checklist */
        checklists.first?.items.map(\.title) ?? []
    }

    /// Number of checklist items shown as complete for this sample card
    var completedChecklistItems: Int { /* Completion count for the first checklist */
        checklists.first?.completed ?? 0
    }

    /// Number of sample comments shown on the board card
    var commentCount: Int { /* Number of activity comments */
        comments.count
    }

    /// Indicates whether the sample card displays a due-date badge
    var hasDueDate: Bool { /* Sample badge visibility for the card */
        id % 3 != 1
    }

    /// Humorous context paragraph shown in the card detail view
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
struct KanbanList: Identifiable, Hashable, Codable {

    let id:        Int              /* Unique identifier for the kanban list */
    let title:     String           /* Title of the kanban list              */
    var cards:     [KanbanCard]     /* Cards contained within the list       */


    /// Supporting copy shown beneath the list title.
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
struct KanbanChecklistActionDetail: Identifiable, Hashable, Codable {

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
enum KanbanChecklistActionContent: Hashable, Codable {

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
struct KanbanChecklistItem: Identifiable, Hashable, Codable, ExpressibleByStringLiteral {

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
struct KanbanChecklist: Identifiable, Hashable, Codable {

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
    /// @details    Writes checklist identity, title, and item records without the legacy completion-index field
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
    /// @details    Retains the first 80 bits of checklist identity and uses the legacy item position
    ///             for the final UUID component
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

        guard components.count == 5 else { return UUID() }

        let itemComponent = String(format: "%012llX", UInt64(itemIndex)) /* Position suffix */
        let migratedValue = "\(components[0])-\(components[1])-\(components[2])-\(components[3])-\(itemComponent)" /* Migrated UUID text */

        return UUID(uuidString: migratedValue) ?? UUID()
    }
}


// -------------------------------------- MARK: - Card Comment ------------------------------- //

/// A comment posted to a kanban card's activity feed
struct KanbanComment: Identifiable, Hashable, Codable {
    let id:        UUID         /* Unique identifier for the comment                 */
    let author:    String       /* Author of the comment                             */
    let body:      String       /* Body text of the comment                          */
    let createdAt: Date         /* Timestamp indicating when the comment was created */

    /// Create a card comment with a stable identity and timestamp
    ///
    /// @param[in]  id        Comment identity
    /// @param[in]  author    Display name of the comment author
    /// @param[in]  body      Comment text
    /// @param[in]  createdAt Comment creation time
    ///
    init(id: UUID = UUID(), author: String, body: String, createdAt: Date = .now) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}


///
/// Persists the active board as a Codable snapshot in local user defaults
///
/// @section    Purpose
///     Restore card and list state across app launches without requiring a remote service
///
/// @details    Decodes the saved board when available and falls back to deterministic sample data on first launch or invalid data
///
/// @note       The storage key is versioned so future persistence format changes can be migrated deliberately
///
struct ExampleLoadUndoSnapshot: Codable, Equatable {

    let lists: [KanbanList]
    let todayListID: Int?
}


enum ExampleLoadUndoStore {

    private static let storageKey = "Plenact.ExampleLoadUndo.v1"

    @discardableResult
    static func save(
        lists: [KanbanList],
        todayListID: Int?,
        to defaults: UserDefaults = .standard
    ) -> Bool {
        let snapshot = ExampleLoadUndoSnapshot(lists: lists, todayListID: todayListID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: storageKey)
        return true
    }

    static func load(from defaults: UserDefaults = .standard) -> ExampleLoadUndoSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ExampleLoadUndoSnapshot.self, from: data)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}


enum KanbanBoardPersistence {

    private static let storageKey = "Plenact.Board.v1" /* Versioned local Board snapshot key */

    ///
    /// @fcn        KanbanBoardPersistence.loadLists
    /// @brief      Load the saved board lists
    /// @details    Decodes the locally stored JSON snapshot and returns sample data if no valid snapshot exists
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
    /// @details    Encodes the supplied list and card state as JSON and writes it to the versioned user-defaults key
    ///
    /// @param[in]  lists  Board lists and their current card state
    ///
    /// @return     (Void) stores the encoded board snapshot when encoding succeeds
    ///
    /// @pre        lists contains the current in-memory board state
    /// @post       A valid encoded snapshot is stored locally; encoding failure leaves prior stored data unchanged
    ///
    static func saveLists(_ lists: [KanbanList]) {

        guard let data = try? JSONEncoder().encode(lists) else { return } /* Encoded Board snapshot */

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
    /// @details    Appends one Board-card link and two reduced details to the first seeded checklist
    ///             while preserving all existing standard actions and checklist groups
    ///
    /// @param[in]  card        Starter card receiving demonstration actions
    /// @param[in]  linkedCard  Existing starter card used as the navigation target
    ///
    /// @return     ([KanbanChecklist]) enriched checklist collection
    ///
    private static func enrichedChecklists(for card: KanbanCard, linkedCard: KanbanCard) -> [KanbanChecklist] {

        guard let firstChecklist = card.checklists.first else { return card.checklists } /* Checklist receiving sample actions */

        let linkedAction = KanbanChecklistItem(   /* Existing card link */
            title:   "Open \(linkedCard.word) card",
            content: .linkedCard(cardID: linkedCard.id)
        )
        let planningDetail = actionDetail(        /* Planning subcard */
            title:       "Prepare",
            description: "Collect the context needed before starting the \(card.word) activity.",
            steps:       ["Choose the next clear step", "Gather anything needed"],
            comment:     "This detail stays with the checklist action."
        )
        let reviewDetail = actionDetail(          /* Review subcard */
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

                let card = KanbanCard( /* Construct one synthetic starter card */
                    id:             globalIndex,
                    word:           cardTitle,
                    listTitle:      title,
                    isTitleChecked: globalIndex % 3 == 0,
                    members:        ["Justin Reina"],
                    labelIDs:       [LabelLibrary.starterLabelIDs[globalIndex % LabelLibrary.starterLabelIDs.count]]
                )

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

                guard !sourceCard.isSectionDivider, !targetCards.isEmpty else { continue }

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

