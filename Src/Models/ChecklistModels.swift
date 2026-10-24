// --------------------------------------------------------------------------------------------------
// @file       ChecklistModels.swift
// @brief      Stable checklist records and typed action content
// @details    Preserves completion, nested detail, linked destinations, and legacy decoding while
//             retaining inactive action values.
//
// --------------------------------------------------------------------------------------------------
import Foundation


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
struct KanbanChecklistActionDetail: Identifiable, Hashable, Codable, Sendable
{


    let id:          UUID               /* Stable Action Detail ID */
    var description: String             /* Supporting action text  */
    var checklists:  [KanbanChecklist]  /* Nested standard actions */
    var comments:    [KanbanComment]    /* Action discussion       */


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
    init(
        id: UUID = UUID(), description: String = "", checklists: [KanbanChecklist] = [], comments: [KanbanComment] = []
    )
    {


        self.id = id
        self.description = description
        self.checklists = checklists
        self.comments = comments
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
enum KanbanChecklistActionContent: Hashable, Codable, Sendable
{


    case webLink(URL)
    case standard                                   /* Plain text action       */
    case linkedCard(cardID: Int)                    /* Existing card reference */
    case actionDetail(KanbanChecklistActionDetail)  /* Owned reduced detail    */


    ///
    /// Identifies the persisted action-content discriminator
    ///
    /// @section    Purpose
    ///     Keep the encoded representation explicit and stable across associated-value changes
    ///
    private enum Kind: String, Codable
    {


        case webLink
        case standard      /* Plain text action kind  */
        case linkedCard    /* Existing card link kind */
        case actionDetail  /* Reduced detail kind     */
    }


    ///
    /// Identifies fields used by the explicit action-content representation
    ///
    /// @section    Purpose
    ///     Separate the content discriminator from its optional associated payload
    ///
    private enum CodingKeys: String, CodingKey
    {


        case url
        case kind    /* Content discriminator */
        case cardID  /* Linked card identity  */
        case detail  /* Owned Action Detail   */
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
    init(from decoder: Decoder) throws
    {


        let container = try decoder.container(keyedBy: CodingKeys.self)  /* Persisted fields */
        let kind = try container.decode(Kind.self, forKey: .kind)        /* Action kind      */

        switch kind
        {


        case .webLink:
            self = .webLink(try container.decode(URL.self, forKey: .url))
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
    func encode(to encoder: Encoder) throws
    {


        var container = encoder.container(keyedBy: CodingKeys.self) /* Output fields */

        switch self
        {


        case .webLink(let url):
            try container.encode(Kind.webLink, forKey: .kind)
            try container.encode(url, forKey: .url)
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
/// Identifies the editable kind of a checklist action
///
/// @section    Purpose
///     Distinguishes a standard checkbox, owned detail, linked Card, and web link independently of
///     retained inactive content.
///
enum ChecklistItemType: String, CaseIterable, Identifiable
{


    case standard, linkedCard, actionDetail, webLink
    var id: String
    {
        rawValue
    }

    var title: String
    {

        switch self
        {

        case .standard:
                    "Standard";

        case .linkedCard:
                    "Linked Card";

        case .actionDetail:
                    "Action Detail";

        case .webLink:
                    "Web Link"
        }

    }

}


///
/// Represents one checklist action with stable identity
///
/// @section    Purpose
///     Retains completion, active action content, and inactive linked or detailed values so
///     changing action type does not silently discard prior content.
///
struct KanbanChecklistItem: Identifiable, Hashable, Codable, ExpressibleByStringLiteral, Sendable
{


    let id:          UUID    /* Stable checklist action ID */
    var title:       String  /* User-facing action text    */
    var isCompleted: Bool    /* Current completion state   */
    var content:     KanbanChecklistActionContent
    {

        didSet
        {
            retainActiveContent()
        }

    }

    var retainedDetail:     KanbanChecklistActionDetail? = nil
    var retainedCardID:     Int? = nil
    var retainedURL:        URL? = nil
    var linkedCollectionID: UUID? = nil


    ///
    /// @fcn        KanbanChecklistItem.retainActiveContent
    /// @brief      Retain the current checklist item's alternate presentation content
    /// @details    Copies an active linked-card ID, action detail, or URL to its retained field; a standard item
    ///             leaves retained values untouched.
    ///
    /// @return     (Void) no return value
    ///
    mutating func retainActiveContent()
    {

        switch content
        {

        case .standard:
            break
        case .linkedCard(let id):
            retainedCardID = id
        case .actionDetail(let detail):
            retainedDetail = detail
        case .webLink(let url):
            retainedURL = url
        }

    }


    var type: ChecklistItemType
    {

        switch content
        {

        case .standard:
            .standard;

        case .linkedCard:
            .linkedCard;

        case .actionDetail:
            .actionDetail;

        case .webLink:
            .webLink
        }

    }


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
    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, content: KanbanChecklistActionContent = .standard)
    {


        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.content = content
        retainActiveContent()
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
    init(stringLiteral value: String)
    {


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
    init(from decoder: Decoder) throws
    {


        let container = try decoder.container(keyedBy: CodingKeys.self) /* Persisted fields */

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        content = try container.decodeIfPresent(KanbanChecklistActionContent.self, forKey: .content) ?? .standard
        retainedDetail = try container.decodeIfPresent(KanbanChecklistActionDetail.self, forKey: .retainedDetail)
        retainedCardID = try container.decodeIfPresent(Int.self, forKey: .retainedCardID)
        retainedURL = try container.decodeIfPresent(URL.self, forKey: .retainedURL)
        linkedCollectionID = try container.decodeIfPresent(UUID.self, forKey: .linkedCollectionID)
        retainActiveContent()
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
    func encode(to encoder: Encoder) throws
    {


        var container = encoder.container(keyedBy: CodingKeys.self) /* Output fields */

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(retainedDetail, forKey: .retainedDetail)
        try container.encodeIfPresent(retainedCardID, forKey: .retainedCardID)
        try container.encodeIfPresent(retainedURL, forKey: .retainedURL)
        try container.encodeIfPresent(linkedCollectionID, forKey: .linkedCollectionID)
    }


    ///
    /// Identifies persisted checklist-item fields
    ///
    /// @section    Purpose
    ///     Keep missing content backward-compatible while requiring established item state
    ///
    private enum CodingKeys: String, CodingKey
    {


        case id           /* Stable action identity  */
        case title        /* User-facing action text */
        case isCompleted  /* Direct completion state */
        case content      /* Action behavior payload */
        case retainedDetail, retainedCardID, retainedURL, linkedCollectionID
    }

}


// -------------------------------------- MARK: - Checklist Model ------------------------------ //


///
/// Represents a checklist shown within a kanban card
///
/// @section    Purpose
///     Provide a small value type for rendering both seeded and newly created checklist groups
///
struct KanbanChecklist: Identifiable, Hashable, Codable, Sendable
{


    let id:    UUID                   /* Stable checklist ID     */
    let title: String                 /* Checklist display title */
    let items: [KanbanChecklistItem]  /* Ordered action records  */

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
    var completedItemIndices: Set<Int>
    {  /* Completed UI positions */

        Set(items.indices.filter
            {
                items[$0].isCompleted
            })
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
    var completed: Int
    {  /* Completed action count */

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
    init(
        id: UUID = UUID(), title: String, items: [KanbanChecklistItem] = [], completed: Int? = nil,
        completedItemIndices: Set<Int>? = nil
    )
    {


        var normalizedItems = items /* Mutable item snapshot */

        if let completedItemIndices
        {  /* Explicit completion positions */


            for index in normalizedItems.indices
            {


                normalizedItems[index].isCompleted = completedItemIndices.contains(index)
            }

        }
        else if let completed
        {  /* Leading completion count */

            for index in normalizedItems.indices
            {


                normalizedItems[index].isCompleted = index < min(completed, normalizedItems.count)
            }

        }


        self.id = id
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
    init(from decoder: Decoder) throws
    {


        let container = try decoder.container(keyedBy: CodingKeys.self)  /* Persisted fields */
        let id = try container.decode(UUID.self, forKey: .id)            /* Checklist ID     */
        let title = try container.decode(String.self, forKey: .title)    /* Checklist title  */

        if var currentItems = try? container.decode([KanbanChecklistItem].self, forKey: .items)
        {  /* Current actions */


            if let legacyCompletedIndices = try container.decodeIfPresent(Set<Int>.self, forKey: .completedItemIndices)
            {  /* Legacy completion */


                for index in currentItems.indices
                {


                    currentItems[index].isCompleted = legacyCompletedIndices.contains(index)
                }

            }


            self.init(id: id, title: title, items: currentItems)

            return
        }


        let legacyTitles = try container.decode([String].self, forKey: .items) /* Legacy action text */
        let legacyCompletedIndices =
        try container.decodeIfPresent(Set<Int>.self, forKey: .completedItemIndices) ?? [] /* Legacy completion  */
        let migratedItems = legacyTitles.enumerated().map
        {
        index, itemTitle in /* Migrated actions   */
            KanbanChecklistItem(
                id: Self.migratedItemID(checklistID: id, itemIndex: index),
                title: itemTitle,
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
    func encode(to encoder: Encoder) throws
    {


        var container = encoder.container(keyedBy: CodingKeys.self) /* Output fields */

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(items, forKey: .items)
    }


    ///
    /// Identifies persisted checklist fields across current and revision 0 snapshots
    ///
    /// @section    Purpose
    ///     Keep current item records and the legacy completion field available to custom Codable logic
    ///
    private enum CodingKeys: String, CodingKey
    {


        case id                    /* Checklist identity        */
        case title                 /* Checklist display title   */
        case items                 /* Current or legacy actions */
        case completedItemIndices  /* Revision 0 completion     */
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
    private static func migratedItemID(checklistID: UUID, itemIndex: Int) -> UUID
    {


        let components = checklistID.uuidString.split(separator: "-") /* UUID components */

        guard components.count == 5 else
        {


            return UUID()
        }


        let itemComponent = String(format: "%012llX", UInt64(itemIndex)) /* Position suffix    */
        let migratedValue =
                        "\(components[0])-\(components[1])-\(components[2])-\(components[3])-\(itemComponent)" /* Migrated UUID text */

        return UUID(uuidString: migratedValue) ?? UUID()
    }

}
