// --------------------------------------------------------------------------------------------------
// @file       KanbanList.swift
// @brief      Canonical List records and item construction
// @details    Keeps active and archived content together and applies destination defaults only
//             when constructing new items. Retains per-Card field history at the content-update boundary
//
// --------------------------------------------------------------------------------------------------
import Foundation


// -------------------------------------- MARK: - List Model ------------------------------------ //


///
/// Represents one horizontally navigable kanban list
///
/// @section    Purpose
///     Group an ordered collection of cards with the list title and supporting board copy
///
struct KanbanList: Identifiable, Hashable, Codable, Sendable
{
    let id:                 Int           /* Unique identifier for the kanban list               */
    private(set) var title: String        /* Title updated with retained card context            */
    var subtitleOverride:   String? = nil /* nil preserves legacy generated copy; empty hides it */

    /// Records accepted content edits at the shared owner boundary, including nested value edits
    var cards: [KanbanCard] /* Card records under consideration */
    {
        didSet
        {
            let previous = Dictionary( /* Previous value for comparison */
                oldValue.map
                {
                    ($0.id, $0)
                },
                uniquingKeysWith:
                {
                    first, _ in
                    first
                }
            )

            for index in cards.indices
            {
                if let old = previous[cards[index].id]
                {
                    cards[index] = cards[index].recordingEdits(from: old)

                }
            }
        }
    }

    var archivedCards:      [KanbanCard] /* Cards retained in this list's archive     */
    var isArchived:         Bool = false /* Whether this list is in the board archive */

    var singleListViewMode: SingleListViewMode /* Single list view mode */
    {
        appearance?.listViewMode ?? .cards
    }


    ///
    /// @fcn        KanbanList.setSingleListViewMode
    /// @brief      Change a list's single-list presentation mode
    /// @details    Stores the selected mode in the list appearance, preserving the other appearance fields
    ///
    /// @param[in]  mode  Mode supplied to this operation
    ///
    /// @return     (Void) no return value
    ///
    mutating func setSingleListViewMode(_ mode: SingleListViewMode)
    {
        var value = appearance ?? ItemAppearance() /* Value being processed */

        value.listViewMode = mode
        appearance = value

    }


    ///
    /// @fcn        KanbanList.defaultHeaderIcon
    /// @brief      Choose the standard icon associated with a list title
    /// @details    Recognizes Plenact's special list names and returns nil for an ordinary title without a fixed
    ///             default
    ///
    /// @param[in]  title  Display title or proposed title text
    ///
    /// @return     (PersonalCollectionIcon?) fixed special-list icon, or nil when no recognized special-list default
    ///             exists
    ///
    static func defaultHeaderIcon(for title: String) -> PersonalCollectionIcon?
    {
        switch title
        {
        case "On the Table":
            .tasks
        case "In the Queue":
            .project
        case "Scheduled":
            .upcoming
        default:
            nil
        }

    }


    ///
    /// @fcn        KanbanList.fixedIconColor
    /// @brief      Resolve the fixed icon color for a special list
    /// @details    Maps recognized special-list titles to their established colors; ordinary titles have no fixed
    ///             color
    ///
    /// @param[in]  title  Display title or proposed title text
    ///
    /// @return     (ProfileColor?) established special-list color, or nil for an ordinary title
    ///
    static func fixedIconColor(for title: String) -> ProfileColor?
    {
        switch title
        {
        case "On the Table":
            ProfileColor(red: 0.48, green: 0.13, blue: 0.16)
        case "In the Queue":
            .teal
        case "Scheduled":
            .graphite
        default:
            nil
        }

    }


    ///
    /// @fcn        KanbanList.fixedHeaderIconColor
    /// @brief      Resolve the special list header's fixed icon color
    /// @details    Uses the title-based fixed-color rules for header presentation
    ///
    /// @param[in]  title  Display title or proposed title text
    ///
    /// @return     (ProfileColor?) fixed special-list header color, or nil when no fixed color applies
    ///
    static func fixedHeaderIconColor(for title: String) -> ProfileColor?
    {
        // A warm highlight remains legible against On the Table's burgundy banner
        title == "On the Table" ? ProfileColor(red: 1, green: 0.84, blue: 0.55) : fixedIconColor(for: title)
    }


    ///
    /// @fcn        KanbanList.resolvedIconColor
    /// @brief      Resolve the displayed list icon color
    /// @details    Combines fixed special-list styling with appearance and collection-level color choices
    ///
    /// @param[in]  collectionColor  Optional inherited collection icon color
    ///
    /// @return     (ProfileColor?) effective fixed, list, or inherited collection icon color, when available
    ///
    func resolvedIconColor(collectionColor: ProfileColor? = nil) -> ProfileColor?
    {
        Self.fixedIconColor(for: title) ?? appearance?.iconColor ?? collectionColor
    }

    var hasFixedHeaderIcon: Bool /* Fixed Header Icon availability */
    {
        Self.defaultHeaderIcon(for: title) != nil
    }

    /// The three built-in shortcut Lists always retain their header identity
    var showsIconInHeader: Bool /* Icon In Header visibility */
    {
        hasFixedHeaderIcon || appearance?.showsIconInHeader == true
    }


    ///
    /// @fcn        KanbanList.headerAppearance
    /// @brief      Build the effective icon appearance for the list header
    /// @details    Combines list overrides, collection icon defaults, and special-list styling without changing
    ///             stored appearance
    ///
    /// @param[in]  collectionIcon   Optional inherited collection icon choice
    /// @param[in]  collectionColor  Optional inherited collection icon color
    ///
    /// @return     (ItemAppearance?) resolved list-header appearance using available list and collection defaults
    ///
    func headerAppearance(collectionIcon: PersonalCollectionIcon? = nil, collectionColor: ProfileColor? = nil)
    -> ItemAppearance?
    {
        guard showsIconInHeader else
        {
            return nil
        }

        var value = appearance ?? ItemAppearance() /* Value being processed */

        value.icon = appearance?.icon ?? collectionIcon ?? Self.defaultHeaderIcon(for: title) ?? .notes
        value.iconColor = Self.fixedHeaderIconColor(for: title) ?? resolvedIconColor(collectionColor: collectionColor)

        return value
    }


    /// Today focuses the first actionable Card in saved order without moving records
    var firstUncheckedTaskID: Int? /* First unchecked task ID */
    {
        guard !isArchived else
        {
            return nil
        }

        return cards.first
        {
            $0.displayFormat == .card && !$0.isTitleChecked
        }?.id
    }


    var appearance: ItemAppearance? = nil /* Resolved appearance choices */
    private var defaultItemPresentation:  /* Default item presentation   */
    ItemPresentation? /* Optional persisted default kind for newly created records */

    /// Applies only at creation; changing this preference never converts retained items
    var newItemPresentation: ItemPresentation /* New item presentation */
    {  /* Effective creation kind with the legacy Card fallback */
        get
        {
            defaultItemPresentation ?? .card
        }

        set
        {
            defaultItemPresentation = newValue == .card ? nil : newValue

        }

    }


    ///
    /// @fcn        KanbanList.makeItem(id:title:description:)
    /// @brief      Create an item using this list's default interface
    /// @details    Notes start with an empty body and no seeded checklists. Dividers remain Cards.
    ///             Existing Card creation keeps its established checklist defaults
    /// @param[in]  id                    Caller-allocated stable identity
    /// @param[in]  title                 Validated item title
    /// @param[in]  description           Optional supplied body
    /// @param[in]  createdAt             Creation time captured once for this new item
    /// @param[in]  presentationOverride  Explicit template kind; nil preserves the List default
    /// @param[in]  actions               Template actions; nil preserves ordinary Card checklist defaults
    /// @param[in]  subtitle              Supporting preview subtitle supplied by the creation draft
    /// @param[in]  creationPreferences   Creation-only appearance and scheduling preferences applied
    ///             to new items
    ///
    /// @return     (KanbanCard) new record without modifying the list
    ///
    func makeItem(
        id: Int, title: String, description: String? = nil, subtitle: String = "", createdAt: Date = .now,
        presentationOverride: ItemPresentation? = nil, actions: [String]? = nil,
        creationPreferences: LocalProfilePreferences = PlanPreferencesStore.load(),
        origin: CardHistoryOrigin = .createdHere
    ) -> KanbanCard
    {
        let isDivider    = KanbanCard.isDividerTitle(title) /* Whether the title creates a section separator */
        let presentation = /* Current presentation style */
        isDivider
        ? ItemPresentation.card
        : (presentationOverride ?? newItemPresentation) /* Item kind selected for the new record         */
        let checklists: [KanbanChecklist]? = /* Owned checklist groups */
        presentation == .note
        ? []
        : actions.map
        {
            titles in
            titles.isEmpty
            ? [] : [KanbanChecklist(title: "Actions", items: titles.map
                    {
                        KanbanChecklistItem(title: $0)
                    })]
        }


        var card = KanbanCard( /* Card under consideration */
            id: id, word: KanbanCard.namedDividerHeading(title) ?? title, listTitle: self.title, isDivider: isDivider,
            checklists: checklists,
            descriptionOverride: presentation == .note ? (description ?? "") : description,
            subtitleOverride: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            presentation: presentation,
            createdAt: createdAt
        )

        NewCardAppearanceDefaults.apply(to: &card, preferences: creationPreferences, origin: origin)
        return card
    }


    ///
    /// @fcn        KanbanList.allCards
    /// @brief      Return active and archived cards together
    /// @details    Preserves active cards before archived cards in the combined snapshot
    ///
    /// @return     ([KanbanCard]) all cards retained by the list
    /// @post       The list's active and archived collections are unchanged
    ///
    var allCards: [KanbanCard] /* All cards */
    {
        cards + archivedCards
    }  /* Active and archived records retained by this list */


    ///
    /// @fcn        KanbanList.init(id:title:cards:archivedCards:newItemPresentation:)
    /// @brief      Initialize a board list and its retained cards
    /// @details    Creates the list with active cards and an optional archived-card snapshot
    ///
    /// @param[in]  id                   Stable list identity
    /// @param[in]  title                Displayed list title
    /// @param[in]  cards                Active cards in the list
    /// @param[in]  archivedCards        Cards retained in this list's archive
    /// @param[in]  newItemPresentation  Interface for newly created items only
    ///
    /// @return     (KanbanList) configured board list
    /// @post       The list is active; archive status defaults to false
    ///
    init(
        id: Int, title: String, cards: [KanbanCard], archivedCards: [KanbanCard] = [],
        newItemPresentation: ItemPresentation = .card
    )
    {
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
    private enum CodingKeys: String, CodingKey
    {
        case id, title, cards, archivedCards, isArchived, defaultItemPresentation, subtitleOverride, appearance
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
    init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self) /* Keyed fields read from the persisted list */

        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitleOverride = try container.decodeIfPresent(String.self, forKey: .subtitleOverride)
        appearance = try container.decodeIfPresent(ItemAppearance.self, forKey: .appearance)

        if appearance?.isEmpty == true
        {
            appearance = nil

        }

        cards = try container.decode([KanbanCard].self, forKey: .cards)
        archivedCards = try container.decodeIfPresent([KanbanCard].self, forKey: .archivedCards) ?? []
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        defaultItemPresentation = try container.decodeIfPresent(ItemPresentation.self, forKey: .defaultItemPresentation)

        if defaultItemPresentation == .card
        {
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
    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self) /* Keyed fields written for the persisted list */

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitleOverride, forKey: .subtitleOverride)
        try container.encodeIfPresent(appearance, forKey: .appearance)
        try container.encode(cards, forKey: .cards)
        try container.encodeIfPresent(defaultItemPresentation, forKey: .defaultItemPresentation)

        if !archivedCards.isEmpty
        {
            try container.encode(archivedCards, forKey: .archivedCards)
        }


        if isArchived
        {
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
    mutating func archiveCompletedCards()
    {
        archivedCards.append(contentsOf: cards.filter
            {
                !$0.isSectionDivider && $0.isTitleChecked
            })
        cards.removeAll
        {
            !$0.isSectionDivider && $0.isTitleChecked
        }

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
    mutating func archiveCard(id cardID: Int)
    {
        guard
        let index = cards.firstIndex(where:
            {  /* Position of the active card to archive */
                $0.id == cardID && !$0.isSectionDivider
            })
        else
        {
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
    mutating func restoreArchivedCard(id cardID: Int)
    {
        guard
        let index = archivedCards.firstIndex(where:
            {  /* Position of the archived card to restore */
                $0.id == cardID
            })
        else
        {
            return
        }


        cards.append(archivedCards.remove(at: index))
    }


    ///
    /// @fcn        KanbanList.subtitle
    /// @brief      Provide supporting copy for the list header
    /// @details    Uses saved supporting copy, then built-in List descriptions, then the legacy identity-based subtitle
    ///
    /// @return     (String) supporting text shown beneath the list title
    /// @post       No list state is modified
    ///
    var subtitle: String /* Supporting item text */
    {  /* Supporting text for the list header */
        if let subtitleOverride
        {
            return subtitleOverride
        }

        switch title
        {
        case "On the Table":
            return "Idea taking shape"
        case "In the Queue":
            return "Things you got started"
        case "Scheduled":
            return "Upcoming activities"
        default:
            break
        }

        let subtitles = [ /* Supporting item text values */
                        "Ideas taking shape", "Ready for a little momentum", "Currently in progress",
                        "Nearly across the finish line", "Done, or at least confidently presented"
        ] /* List subtitle options */

        return subtitles[id % subtitles.count]
    }


    ///
    /// @fcn        KanbanList.edit
    /// @brief      Validate and update editable list metadata
    /// @details    Rejects a blank proposed title before assigning the title and optional subtitle override
    ///
    /// @param[in]  proposedTitle  Proposed list title, validated before assignment
    /// @param[in]  subtitle       Supporting subtitle text
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`. Errors from throwing
    ///             dependencies propagate unless handled within this operation
    ///
    /// @note       Updates display metadata without replacing retained records or changing their identities
    ///
    mutating func edit(title proposedTitle: String, subtitle: String?) throws
    {
        let trimmedTitle = /* Trimmed title */
            proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else
        {
            throw CocoaError(.validationMissingMandatoryProperty)
        }


        title = trimmedTitle
        subtitleOverride = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        for index in cards.indices
        {
            cards[index].listTitle = title

        }

        for index in archivedCards.indices
        {
            archivedCards[index].listTitle = title

        }

    }

}


///
/// Creates List items from multiline title input
///
/// @section    Purpose
///     Allocates owner-local identities, interprets divider syntax, and applies the requested
///     content, presentation, and creation defaults
///
extension KanbanList
{
    ///
    /// @fcn        KanbanList.makeItems
    /// @brief      Create cards or notes from a multiline title submission
    /// @details    Allocates sequential IDs, interprets divider syntax, and applies supplied content, actions,
    ///             presentation, and creation preferences to the generated items
    ///
    /// @param[in]  id                   Starting numeric card ID or owner-local content identity
    /// @param[in]  titles               Multiline item-title input
    /// @param[in]  description          Optional description applied to the generated items
    /// @param[in]  subtitle             Supporting subtitle text
    /// @param[in]  presentation         Card, note, or board presentation selected by the caller
    /// @param[in]  actions              Action lines or contextual keyboard actions supplied by the caller
    /// @param[in]  creationPreferences  User defaults to apply only to newly created items
    ///
    /// @return     ([KanbanCard]) newly allocated cards, notes, or dividers corresponding to the usable title lines
    ///
    func makeItems(
        startingAt id: Int, titles: String, description: String? = nil, subtitle: String = "",
        presentation: ItemPresentation? = nil, actions: [String]? = nil,
        creationPreferences: LocalProfilePreferences = PlanPreferencesStore.load(),
        origin: CardHistoryOrigin = .createdHere
    ) -> [KanbanCard]
    {
        MultilineEntry.titles(titles).enumerated().map
        {
            offset, title in
            makeItem(
                id: id + offset, title: title, description: description, subtitle: subtitle,
                presentationOverride: presentation, actions: actions, creationPreferences: creationPreferences, origin: origin)
        }

    }

}


///
/// One persisted field change with reversible JSON values
///
/// @section    Purpose
///     Retains only changed fields; nil denotes an absent optional key rather than an encoded value
///
struct CardEditChange: Codable, Hashable, Sendable
{
    let field:         String /* Native input field */
    let previousValue: Data?  /* Previous value     */
    let newValue:      Data?  /* New value          */

}


/// Stable attribution for a locally authored Card action
struct CardHistoryAuthor: Codable, Hashable, Sendable
{
    let id: UUID        /* Stable local author identity */
    let name: String?   /* Display name at the time of the action */

    var label: String { name ?? "Local author" }

    static func local(in defaults: UserDefaults = .standard) -> Self
    {
        let name = LocalProfileStore.load(from: defaults)?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        return Self(id: LocalReactionIdentity.forUserAction(in: defaults), name: name?.isEmpty == false ? name : nil)
    }
}


enum CardHistoryOrigin: Codable, Hashable, Sendable
{
    case createdHere
    case copy(String)
    case template(String)

    var label: String
    {
        switch self
        {
        case .createdHere: "Created here"
        case .copy(let title): "Copied from “\(title)”"
        case .template(let title): "Made from “\(title)”"
        }
    }
}


struct CardHistoryContext: Codable, Hashable, Sendable
{
    let author: CardHistoryAuthor? /* Author when known */
    var origin: CardHistoryOrigin? /* Creation event when present */
    var undid: String?             /* Summary of the revision undone */
    var historyCleared: Bool?      /* Retains only last-edit attribution */
}


///
/// One saved Card update containing related field edits
///
/// @section    Purpose
///     Groups a single accepted update under a stable identity and timestamp without recursively
///     copying prior history. The opaque history payload also carries author and origin metadata
///
struct CardEditRecord: Codable, Hashable, Identifiable, Sendable
{
    let id:        UUID             /* Record UUID             */
    let timestamp: Date             /* Stored event timestamp  */
    let changes:   [CardEditChange] /* Requested content edits */


    let context: CardHistoryContext? /* Absent for historical records */

    // Keep metadata in the existing opaque history payload used by native and portable stores
    private static let contextField = "plenact.historyContext"
    private enum CodingKeys: String, CodingKey
    {
        case id, timestamp, changes
    }

    init(id: UUID, timestamp: Date, changes: [CardEditChange], context: CardHistoryContext? = nil)
    {
        self.id = id
        self.timestamp = timestamp
        self.changes = changes
        self.context = context
    }

    init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decode([CardEditChange].self, forKey: .changes)

        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        if let bytes = stored.last(where: { $0.field == Self.contextField })?.newValue,
           let decoded = try? JSONDecoder().decode(CardHistoryContext.self, from: bytes)
        {
            context = decoded
            changes = stored.filter { $0.field != Self.contextField }
        }
        else
        {
            context = nil
            changes = stored
        }
    }

    func storedChanges() throws -> [CardEditChange]
    {
        guard let context else
        {
            return changes
        }

        let encoder = JSONEncoder()

        encoder.outputFormatting = [.sortedKeys]
        return changes + [CardEditChange(field: Self.contextField, previousValue: nil,
            newValue: try encoder.encode(context))]
    }

    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(storedChanges(), forKey: .changes)
    }


    ///
    /// @fcn        CardEditRecord.summary
    /// @brief      Describe saved changes using user-facing field names
    /// @details    Groups related technical fields, such as a date and its precision, into one label
    /// @return     (String) concise list of changed areas for the history timeline
    ///
    var summary: String /* Aggregate operation results */
    {
        let names = [ /* Names used by this operation */
            "word": "Title", "subtitleOverride": "Subtitle", "descriptionOverride": "Description",
            "isTitleChecked": "Completion", "startDate": "Start date", "startDateKind": "Start date",
            "location": "Location", "dueDate": "Due date", "dueDateKind": "Due date", "checklists": "Checklists",
            "members": "Members", "labelIDs": "Labels", "attachments": "Attachments",
            "coverAttachmentID": "Cover image", "editingLocked": "Editing lock",
            "appearance": "Appearance", "reactions": "Reactions",
            "showsDueDateInList": "Date visibility", "showsReactionsInPreviews": "Reaction visibility",
            "sectionLayout": "Section layout", "itemPresentation": "Card type",
            "listDisplayFormat": "Display format", "isDivider": "Divider",
            "dismissedActivityIDs": "Activity visibility"
        ]
        var labels: [String] = [] /* Available label definitions */

        for change in changes
        {
            let label = names[change.field] ?? "Card details" /* Resolved display label */

            if !labels.contains(label)
            {
                labels.append(label)
            }
        }
        if context?.undid != nil
        {
            return "Undo · " + labels.joined(separator: ", ")
        }

        return labels.joined(separator: ", ") + " updated"
    }
}


///
/// Builds nonrecursive edit records from complete canonical Card values
///
/// @section    Purpose
///     Preserves prior history across reconstructed editor snapshots and excludes list context,
///     identity, and creation metadata from content comparisons
///
extension KanbanCard
{
    ///
    /// @fcn        KanbanCard.recordingEdits(from:at:)
    /// @brief      Append one history entry only when editable content changed
    /// @details    Compares encoded fields without history, keeps the owner's existing entries,
    ///             and recognizes an already prepared detail-editor entry to prevent duplication.
    ///             Consecutive autosaves to the same writing fields within two seconds share one
    ///             entry retaining the original value and latest text; other edits stay distinct.
    ///             New insertions and decoding do not call this comparison. Failure to encode
    ///             preserves prior history without preventing the content update
    /// @param[in]  previous  Canonical value before this accepted update
    /// @param[in]  date      Timestamp assigned to this update
    /// @return     (KanbanCard) proposed content carrying its accumulated edit history
    ///
    func recordingEdits(from previous: KanbanCard, at date: Date = .now,
        author: CardHistoryAuthor? = nil, undoing revision: CardEditRecord? = nil) -> KanbanCard
    {
        var result = self /* Accumulated output value */

        result.editHistory = previous.editHistory

        var old = previous /* Previous operation state    */
        var new = self     /* Replacement operation state */

        old.editHistory = nil
        new.editHistory = nil
        old.listTitle = new.listTitle

        if old == new
        {
            // Accept the exact clear-history snapshot while retaining history on ordinary saves
            if !previous.revisions.isEmpty, editHistory == previous.clearingRevisionHistory().editHistory
            {
                result.editHistory = editHistory
            }
            return result
        }
        guard let oldData = try? JSONEncoder().encode(old),
              let newData = try? JSONEncoder().encode(new),
              let before = try? JSONSerialization.jsonObject(with: oldData) as? [String: Any],
              let after = try? JSONSerialization.jsonObject(with: newData) as? [String: Any]
        else
        {
            return result
        }

        let excluded: Set<String>     = /* Fields omitted by this projection */
            ["id", "listTitle", "createdAt", "editHistory"]
        let keys                      = /* Keys used by this operation */
            Set(before.keys).union(after.keys).subtracting(excluded).sorted()
        var changes: [CardEditChange] = [] /* Requested content edits */

        for key in keys
        {
            let left  = before[key] as? NSObject /* First comparison operand  */
            let right = after[key] as? NSObject  /* Second comparison operand */

            if left == right
            {
                continue
            }

            let previousValue = try? before[key].map /* Previous value */
            {
                try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys])
            }
            let newValue = try? after[key].map /* New value */
            {
                try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys])
            }

            changes.append(CardEditChange(field: key, previousValue: previousValue, newValue: newValue))
        }
        guard !changes.isEmpty else
        {
            return result
        }

        let retained = previous.editHistory ?? [] /* State retained for recovery */

        if let prepared = editHistory,
           prepared.count == retained.count + 1,
           Array(prepared.dropLast()) == retained,
           prepared.last?.changes == changes
        {
            result.editHistory = prepared

        }
        else if revision == nil, let last = retained.last,
                last.context?.undid == nil, last.context?.author == (author ?? .local()),
                date.timeIntervalSince(last.timestamp) >= 0,
                date.timeIntervalSince(last.timestamp) <= 2,
                Set(changes.map(\.field)) == Set(last.changes.map(\.field)),
                Set(changes.map(\.field)).isSubset(of: ["word", "subtitleOverride", "descriptionOverride"])
        {
            // Autosaved typing is one readable update rather than an entry per keystroke
            let merged = changes.map /* Combined content after */
            {
                change in
                CardEditChange(
                    field: change.field,
                    previousValue: last.changes.first
                    {
                        $0.field == change.field
                    }?.previousValue,
                    newValue: change.newValue
                )
            }

            result.editHistory = Array(retained.dropLast()) + [
                CardEditRecord(id: last.id, timestamp: date, changes: merged, context: last.context)
            ]

        }
        else
        {
            let context = CardHistoryContext(author: author ?? .local(), undid: revision?.summary)

            result.editHistory = retained + [CardEditRecord(id: UUID(), timestamp: date,
                changes: changes, context: context)]

        }
        return result
    }
}


extension KanbanCard
{
    var creationHistory: CardEditRecord?
    {
        editHistory?.first { $0.context?.origin != nil }
    }

    var revisions: [CardEditRecord]
    {
        (editHistory ?? []).filter { $0.context?.origin == nil && $0.context?.historyCleared != true }
    }

    var lastEditHistory: CardEditRecord?
    {
        editHistory?.last { $0.context?.origin == nil }
    }

    func clearingRevisionHistory() -> KanbanCard
    {
        guard let latest = revisions.last else
        {
            return self
        }

        var cleared = self
        let summary = CardEditRecord(id: latest.id, timestamp: latest.timestamp, changes: [],
            context: CardHistoryContext(author: latest.context?.author, historyCleared: true))

        cleared.editHistory = [creationHistory, summary].compactMap { $0 }
        return cleared
    }

    mutating func recordCreation(_ origin: CardHistoryOrigin, author: CardHistoryAuthor? = nil)
    {
        guard !isSectionDivider, creationHistory == nil, let createdAt else
        {
            return
        }

        let context = CardHistoryContext(author: author ?? .local(), origin: origin)
        let event = CardEditRecord(id: UUID(), timestamp: createdAt, changes: [], context: context)

        editHistory = [event] + (editHistory ?? [])
    }
}


enum CardRevisionUndoError: Error
{
    case conflict
    case unavailable
}


extension CardEditRecord
{
    var undoableChanges: [CardEditChange]
    {
        changes.filter
        {
            ["word", "subtitleOverride", "descriptionOverride", "startDate", "startDateKind",
             "dueDate", "dueDateKind"].contains($0.field)
        }
    }

    func undo(on card: KanbanCard, replacingConflicts: Bool = false,
        author: CardHistoryAuthor? = nil, at date: Date = .now) throws -> KanbanCard
    {
        let changes = undoableChanges

        let revisions = card.revisions

        guard !card.isEditingLocked, let index = revisions.firstIndex(of: self), !changes.isEmpty else
        {
            throw CardRevisionUndoError.unavailable
        }

        if !replacingConflicts
        {
            var affected = Set(changes.map(\.field))
            for pair: Set<String> in [["startDate", "startDateKind"], ["dueDate", "dueDateKind"]]
            {
                if !affected.isDisjoint(with: pair)
                {
                    affected.formUnion(pair)
                }
            }

            if revisions.dropFirst(index + 1).contains(where: { entry in
                entry.changes.contains { affected.contains($0.field) }
            })
            {
                throw CardRevisionUndoError.conflict
            }
        }

        var restored = card
        let decoder = JSONDecoder()
        let null = Data("null".utf8)

        func restore<Value: Codable & Equatable>(_ change: CardEditChange, _ current: Value) throws -> Value
        {
            let expected = try decoder.decode(Value.self, from: change.newValue ?? null)

            guard replacingConflicts || current == expected else
            {
                throw CardRevisionUndoError.conflict
            }

            return try decoder.decode(Value.self, from: change.previousValue ?? null)
        }

        for change in changes
        {
            switch change.field
            {
            case "word":
                restored.word = try restore(change, card.word)
            case "subtitleOverride":
                restored.subtitleOverride = try restore(change, card.subtitleOverride)
            case "descriptionOverride":
                restored.descriptionOverride = try restore(change, card.descriptionOverride)
            case "startDate":
                restored.startDate = try restore(change, card.startDate)
            case "startDateKind":
                restored.startDateKind = try restore(change, card.startDateKind)
            case "dueDate":
                restored.dueDate = try restore(change, card.dueDate)
            case "dueDateKind":
                restored.dueDateKind = try restore(change, card.dueDateKind)
            default:
                break
            }
        }

        guard restored != card else
        {
            throw CardRevisionUndoError.unavailable
        }

        return restored.recordingEdits(from: card, at: date, author: author, undoing: self)
    }
}
