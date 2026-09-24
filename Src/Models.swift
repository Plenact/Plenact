// --------------------------------------------------------------------------------------------------
// @file       Models.swift
// @brief      Domain models and deterministic sample data for the Plenact board
// @details    Defines cards, lists, derived display values, and preview content generation
//
// @notes      Sample data is deterministic so previews and UI behavior remain reproducible
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

    let id:             Int                 /* Stable numeric identifier for the card             */
    let word:           String              /* Display word shown as the card's title             */
    var listTitle:      String              /* Name of the list where the card resides            */
    var isDivider:      Bool                /* Whether this item is a movable section divider     */
    var isTitleChecked: Bool                /* Whether the card's main title checkbox is selected */
    var startDate:      Date?               /* Optional start date for the card                   */
    var dueDate:        Date?               /* Optional due date for the card                     */
    var checklists:     [KanbanChecklist]   /* List of checklists associated with the card        */
    var comments:       [KanbanComment]     /* Comments posted to the card's activity             */
    var members:        [String]            /* User names assigned to the card                    */
    var labelIDs:       [String]            /* Stable IDs of labels assigned to the card          */
    var attachments:    [KanbanAttachment]? /* Photo attachments stored with the card            */
    var dismissedActivityIDs: Set<String>   /* Generated activity entries removed by the user     */
    var descriptionOverride: String?        /* Optional user-edited description                   */
    var subtitleOverride: String?           /* Optional user-edited board subtitle                */

    /// Indicates whether this item should render and behave as a section divider
    var isSectionDivider: Bool {
        isDivider || Self.isDividerTitle(word)
    }

    /// Recognizes the ASCII marker and dash characters substituted by iOS smart punctuation
    static func isDividerTitle(_ title: String) -> Bool {

        let trimmedTitle   = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let dashCharacters = CharacterSet(charactersIn: "-‐‑‒–—―−")

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
    var startDateLabel: String {

        guard let startDate else {
            return "Today"
        }

        return Self.dateFormatter.string(from: startDate)
    }

    /// Human-readable label for the card's due date
    var dueDateLabel: String {

        guard let dueDate else {
            return "Tomorrow"
        }

        return Self.dateFormatter.string(from: dueDate)
    }

    /// Shared formatter used to render card date labels
    private static let dateFormatter: DateFormatter = {

        let formatter       = DateFormatter()

        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return formatter
    }()

    /// Short supporting copy shown beneath the card title
    var subtitle: String {
        if let subtitleOverride {
            return subtitleOverride
        }

        return ["A small idea with suspiciously large ambitions", "Make progress before the coffee gets cold", "A practical plan, lightly seasoned with chaos", "One more useful thing for today's board", "Future success, pending a snack break"][id % 5]
    }

    /// Checklist labels used by the card detail presentation
    var checklistItems: [String] {
        checklists.first?.items ?? []
    }

    /// Number of checklist items shown as complete for this sample card
    var completedChecklistItems: Int {
        checklists.first?.completed ?? 0
    }

    /// Number of sample comments shown on the board card
    var commentCount: Int {
        comments.count
    }

    /// Indicates whether the sample card displays a due-date badge
    var hasDueDate: Bool {
        id % 3 != 1
    }

    /// Humorous context paragraph shown in the card detail view
    var funParagraph: String {

        if let descriptionOverride {
            return descriptionOverride
        }

        let templates: [(String, String) -> String] = [

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

        let template = templates[id % templates.count]

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
    var subtitle: String {
        let subtitles = ["Ideas taking shape", "Ready for a little momentum", "Currently in progress", "Nearly across the finish line", "Done, or at least confidently presented"]

        return subtitles[id % subtitles.count]
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

    let id:                    UUID       /* Unique identifier for the checklist       */
    let title:                 String     /* Title of the checklist                    */
    let items:                 [String]   /* Items contained within the checklist      */
    let completedItemIndices:  Set<Int>   /* Zero-based indices of completed items     */

    // Number of completed items within the checklist
    var completed: Int {
        completedItemIndices.count
    }


    /// Creates a checklist with optional initial completion state.
    init(id: UUID = UUID(), title: String, items: [String] = [], completed: Int = 0, completedItemIndices: Set<Int>? = nil) {

        self.id                   = id
        self.title                = title
        self.items                = items
        self.completedItemIndices = completedItemIndices ?? Set(0..<min(completed, items.count))
    }
}


// -------------------------------------- MARK: - Card Comment ------------------------------- //

/// A comment posted to a kanban card's activity feed
struct KanbanComment: Identifiable, Hashable, Codable {
    let id:        UUID         /* Unique identifier for the comment                 */
    let author:    String       /* Author of the comment                             */
    let body:      String       /* Body text of the comment                          */
    let createdAt: Date         /* Timestamp indicating when the comment was created */

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
enum KanbanBoardPersistence {

    private static let storageKey = "Plenact.Board.v1"

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

        guard let data = UserDefaults.standard.data(forKey: storageKey),

              let lists = try? JSONDecoder().decode([KanbanList].self, from: data) else {
                
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

        guard let data = try? JSONEncoder().encode(lists) else { return }

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
    static let words: [String] = [
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
    static let listTitles = ["First", "Second", "Third", "Fourth", "Fifth"]


    /// Complete sample board generated from the titles and card words
    static let lists: [KanbanList] = {

        var globalIndex = 0

        var initializedLists = listTitles.enumerated().map { listIndex, title in

            let cards = (0..<10).map { _ -> KanbanCard in

                let card = KanbanCard(
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
        let dividerPositionsByList: [[Int]] = [
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
