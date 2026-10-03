// --------------------------------------------------------------------------------------------------
// @file       Models.swift
// @brief      Domain models and deterministic sample data for the Plenact board
// @details    Defines cards, lists, derived display values, and preview content generation
//
// @notes      Sample data is deterministic so previews and UI behavior remain reproducible
//
// @section    Opens
//      Rename to board organized naming
//
// --------------------------------------------------------------------------------------------------
import Foundation


// -------------------------------------- MARK: - Card Model ------------------------------------ //

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
    let word:                 String              /* Display word shown as the card's title             */
    var listTitle:            String              /* Name of the list where the card resides            */
    var isDivider:            Bool                /* Whether this item is a movable section divider     */
    var isTitleChecked:       Bool                /* Whether the card's main title checkbox is selected */

    var members:              [String]            /* User names assigned to the card                    */
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
    init(id: Int, word: String, listTitle: String, isDivider: Bool = false, isTitleChecked: Bool = false, startDate: Date? = nil, dueDate: Date? = nil, checklists: [KanbanChecklist]? = nil, comments: [KanbanComment] = [], members: [String] = [], labelIDs: [String] = [], attachments: [KanbanAttachment]? = nil, dismissedActivityIDs: Set<String> = [], descriptionOverride: String? = nil, subtitleOverride: String? = nil) {

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
        if let subtitleOverride { /* User-edited subtitle */
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

    let id:        UUID      /* Stable checklist action ID */
    var title:     String    /* User-facing action text    */
    var isCompleted: Bool    /* Current completion state   */

    ///
    /// @fcn        KanbanChecklistItem.init(id:title:isCompleted:)
    /// @brief      Initialize a stable standard checklist action
    /// @details    Stores identity, editable text, and completion without assigning richer content
    ///
    /// @param[in]  id           Stable identifier for the checklist item
    /// @param[in]  title        User-facing action text
    /// @param[in]  isCompleted  Whether the action begins complete
    ///
    /// @return     (KanbanChecklistItem) configured standard action
    ///
    init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {

        self.id          = id
        self.title       = title
        self.isCompleted = isCompleted
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
    /// @return     (KanbanComment) configured activity comment
    ///
    init(id: UUID = UUID(), author: String, body: String, createdAt: Date = .now) {
        self.id        = id
        self.author    = author
        self.body      = body
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

          guard let data = UserDefaults.standard.data(forKey: storageKey), /* Saved Board bytes */

              let lists = try? JSONDecoder().decode([KanbanList].self, from: data) else { /* Decoded Board lists */
                
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
///     Construct five lists with ten cards each and representative divider rows without requiring persistence
///
enum SampleData {

    /// Words assigned to the sample cards in repeatable order
    static let words: [String] = [ /* Repeatable titles used by the sample cards */
        "rabbit",    "toaster",    "kazoo",     "lampshade",  "spatula",
        "narwhal",   "cactus",     "bagpipe",   "waffle",     "penguin",
        "gnome",     "trombone",   "pickle",    "yeti",       "flamingo",
        "banjo",     "pretzel",    "octopus",   "unicorn",    "turnip",
        "walrus",    "accordion",  "hedgehog",  "kettle",     "tumbleweed",
        "platypus",  "harmonica",  "meatball",  "raccoon",    "umbrella",
        "otter",     "xylophone",  "dumpling",  "chinchilla", "teapot",
        "armadillo", "clarinet",   "burrito",   "mongoose",   "whisk",
        "llama",     "ukulele",    "croissant", "wombat",     "colander",
        "ferret",    "tambourine", "avocado",   "meerkat",    "spork"
    ]

    /// Titles assigned to the five horizontally navigable board lists
    static let listTitles = ["First", "Second", "Third", "Fourth", "Fifth"] /* Ordered sample-list names */


    /// Complete sample board generated from the titles and card words
    static let lists: [KanbanList] = { /* Deterministic five-list sample Board */

        var globalIndex = 0 /* Board-wide list/card seed identity counter */

        var initializedLists = listTitles.enumerated().map { listIndex, title in /* Seed one list per title */

            let cards = (0..<10).map { _ -> KanbanCard in /* Seed ten cards in the current list */

                let card = KanbanCard( /* Construct one synthetic card */
                    id:             globalIndex,
                    word:           words[globalIndex % words.count],
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
        let dividerPositionsByList: [[Int]] = [ /* Card positions receiving divider rows */
            [3, 7],
            [],
            [5],
            [],
            [4]
        ]

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

        return initializedLists
    }()
}
