// --------------------------------------------------------------------------------------------------
// @file       PersonalCollection.swift
// @brief      User-owned personal Lists and Boards
// @details    Retains collection identity, complete List snapshots, personal references, and
//             explicit local draft operations.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Identifies whether a saved personal collection is a single list or a board
///
/// @section    Purpose
///     Preserve collection behavior and presentation independently of its title
///
enum PersonalCollectionKind: String, CaseIterable, Codable
{


    case list = "List"
    case board = "Board"
}


///
/// Holds the editable, unsaved state for creating a Note in a personal List
///
/// @section    Purpose
///     Preserve destination, entered text, and one creation timestamp until persistence succeeds
///
struct PersonalListNoteDraft
{


    var destinationID: UUID     /* Personal List selected for the unsaved Note */
    var title = ""              /* Editable Note heading                       */
    var body = ""               /* Editable Note content preserved as entered  */
    let createdAt: Date = .now  /* Draft creation time retained through saving */

    var normalizedTitle: String
    {  /* Note heading without surrounding whitespace */

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
    static func destinations(in collections: [PersonalCollection]) -> [PersonalCollection]
    {


        collections.filter
        {

            $0.kind == .list && $0.isActive && $0.lists.contains(where:
                {
                    !$0.isArchived
                })
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
    func destination(in collections: [PersonalCollection]) -> PersonalCollection?
    {


        Self.destinations(in: collections).first
        {
            $0.id == destinationID
        }

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
    func canSave(in collections: [PersonalCollection]) -> Bool
    {


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
    ) throws
    {


        guard canSave(in: collections) else
        {


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        try onSave(destinationID, normalizedTitle, body, createdAt)
    }

}


///
/// Provides the supported symbols for saved personal collections
///
/// @section    Purpose
///     Keep collection icon choices explicit and persistable
///
enum PersonalCollectionIcon: String, CaseIterable, Codable, Sendable
{


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
struct PersonalCollection: Identifiable, Hashable, Codable
{


    let id:                    UUID                    /* Stable collection identity                  */
    var title:                 String                  /* User-facing collection title                */
    let kind:                  PersonalCollectionKind  /* List or multi-column board                  */
    var icon:                  PersonalCollectionIcon  /* Symbol shown for the collection             */
    var color:                 ProfileColor            /* Collection accent color                     */
    var lists:                 [KanbanList]            /* Lists and cards owned by the collection     */
    var savedCardIDs:          Set<Int>                /* Bookmarked cards retained by the collection */
    var isArchived:            Bool? = nil             /* Optional archive state for older saved data */
    var boardAppearance:       BoardAppearance? = nil  /* Independent persisted List color defaults   */
    var collectionDescription: String? = nil

    /// The three shortcut Lists share their focused layout across Today and Plans.
    var preferredFocusedListID: Int?
    {

        let active = lists.filter
        {
            !$0.isArchived
        }

        guard kind == .list, active.count == 1, active[0].hasFixedHeaderIcon else
        {
            return nil
        }

        return active[0].id
    }


    var contentPreview: String
    {

        let description = collectionDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty
        {
            return description
        }

        let titles = lists.filter
        {
            !$0.isArchived
        } .flatMap(\.cards)
        .filter
        {
            !$0.isSectionDivider
        } .map(\.word)
        .map
        {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } .filter
        {
            !$0.isEmpty
        }

        return titles.prefix(3).joined(separator: " · ")
    }


    ///
    /// @fcn        PersonalCollection.isActive
    /// @brief      Determine whether the collection is active
    /// @details    Treats a missing archive flag in older snapshots as active
    ///
    /// @return     (Bool) whether the collection is not archived
    /// @post       Collection state is unchanged
    ///
    var isActive: Bool
    {
        isArchived != true
    }  /* Whether the collection belongs in the active directory */


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
    )
    {


        self.id = id
        self.title = title
        self.kind = kind
        self.icon = icon
        self.color = color

        let columns =
        kind == .list
        ? [title] : ["Ideas", "In progress", "Done"] /* Initial column headings selected by collection kind */

        lists = columns.enumerated().map
        {

            KanbanList(
                id: $0.offset,
                title: $0.element,
                cards: [],
                newItemPresentation: kind == .list ? .note : .card
            )
        }

        savedCardIDs = []
    }


    ///
    /// @fcn        PersonalCollection.useNoteDefaultsForPersonalLists()
    /// @brief      Make new items in a personal List use the Note interface
    /// @details    Applies only to personal List collections and changes creation defaults
    ///             without converting or replacing active or archived records
    ///
    /// @return     (Void) updates each contained list's new-item presentation
    ///
    /// @post       Boards and all retained card content remain unchanged
    ///
    mutating func useNoteDefaultsForPersonalLists()
    {


        guard kind == .list else
        {


            return
        }


        for index in lists.indices
        {


            lists[index].newItemPresentation = .note
        }

    }


    ///
    /// @fcn        PersonalCollection.cardCount
    /// @brief      Count active non-divider cards owned by the collection
    /// @details    Excludes archived lists and section-divider rows
    ///
    /// @return     (Int) number of active cards across the collection
    /// @post       Collection lists and cards are unchanged
    ///
    var cardCount: Int
    {  /* Active non-divider records counted for the directory */

        lists.filter
        {
            !$0.isArchived
        } .reduce(0)
        {
            $0 + $1.cards.filter
            {
                !$0.isSectionDivider
            } .count
        }

    }


    ///
    /// @fcn        PersonalCollection.bookmarkedCards
    /// @brief      Resolve this active collection's bookmarks to active non-divider records
    /// @details    Preserves collection/list/card order and excludes stale IDs and archived lists
    ///
    /// @return     ([PersonalCollectionBookmarkedCard]) bookmark rows with collection/list context
    ///
    /// @post       Collection content and bookmark membership remain unchanged
    ///
    var bookmarkedCards: [PersonalCollectionBookmarkedCard]
    {  /* Current bookmarked personal items with navigation context */


        guard isActive else
        {


            return []
        }


        return lists.filter
        {
            !$0.isArchived
        } .flatMap
        {
            list in
            list.cards.compactMap
            {
                card in
                guard savedCardIDs.contains(card.id), !card.isSectionDivider else
                {


                    return nil
                }


                return PersonalCollectionBookmarkedCard(
                    collectionID: id,
                    collectionTitle: title,
                    listID: list.id,
                    listTitle: list.title,
                    card: card
                )
            }

        }

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
    mutating func rename(to name: String)
    {


        title = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard kind == .list, let column = lists.first else
        {  /* Single-list column whose name follows the collection */


            return
        }


        var cards = column.cards /* Active records receiving the renamed list context */

        for index in cards.indices
        {


            cards[index].listTitle = title
        }


        var archivedCards = column.archivedCards /* Archived records receiving the renamed list context */

        for index in archivedCards.indices
        {


            archivedCards[index].listTitle = title
        }

        lists[0] = KanbanList(
            id: column.id, title: title, cards: cards, archivedCards: archivedCards,
            newItemPresentation: column.newItemPresentation)
        lists[0].isArchived = column.isArchived
        lists[0].subtitleOverride = column.subtitleOverride
        lists[0].appearance = column.appearance
    }


    ///
    /// @fcn        PersonalCollection.addNote(title:body:createdAt:presentation:subtitle:attachments:creationPreferences:actions:schedule:calendar:)
    /// @brief      Append a fully configured Card or Note to a personal List
    /// @details    Rejects unavailable destinations, blank titles, and invalid schedules. Allocates
    ///             beyond retained identities, applies the selected presentation and creation
    ///             defaults, retains media, and reveals the containing section without changing the
    ///             List's creation default.
    ///
    /// @param[in]  title                User-entered Note title
    /// @param[in]  body                 Note body preserved exactly
    /// @param[in]  createdAt            Creation time retained from the draft, or captured at creation
    /// @param[in]  presentation         Card or Note presentation requested for the new item
    /// @param[in]  subtitle             Supporting preview subtitle supplied by the creation draft
    /// @param[in]  attachments          Retained media attachment records committed for the new item
    /// @param[in]  creationPreferences  Creation-only appearance and scheduling preferences applied
    ///             to new items
    /// @param[in]  actions              Optional checklist action titles supplied by the capture mode
    /// @param[in]  schedule             Optional validated start and stop values applied during creation
    /// @param[in]  calendar             Calendar supplying local-day and scheduling interpretation rules
    ///
    /// @return     (Void) appends the requested item to the active destination List
    /// @throws     CocoaError when the destination or title is invalid
    ///
    mutating func addNote(
        title: String, body: String, createdAt: Date = .now, presentation: ItemPresentation = .note,
        subtitle: String = "", attachments: [KanbanAttachment] = [],
        creationPreferences: LocalProfilePreferences = PlanPreferencesStore.load(),
        actions: [String]? = nil, schedule: QuickCaptureSchedule? = nil, calendar: Calendar = .current
    ) throws
    {


        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines) /* Nonblank Note heading used for creation */

        guard kind == .list, isActive, !trimmedTitle.isEmpty, schedule?.isValid(calendar: calendar) != false,
        let listIndex = lists.firstIndex(where:
            {
                !$0.isArchived
            })
        else
        {  /* Active column receiving the new Note */


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        let nextCardID =
        (lists.flatMap
            {
                $0.allCards.map(\.id)
            } .max() ?? -1)
        + 1                                 /* Next identity beyond all retained collection records */
        var destination = lists[listIndex]  /* Column snapshot receiving the new Note               */
        var note = destination.makeItem(
            id: nextCardID, title: trimmedTitle, description: body, createdAt: createdAt,
            presentationOverride: presentation, actions: actions, creationPreferences: creationPreferences) /* New record carrying the draft's content and creation time */

        note.presentation = presentation
        note.subtitleOverride = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if presentation == .note || actions == nil
        {
            note.checklists = []
        }

        schedule?.apply(to: &note, calendar: calendar)
        if !attachments.isEmpty
        {

            note.attachments = attachments
            note.coverAttachmentID = attachments.first(where:
                {
                    $0.kind == .photo
                })?.id
        }

        destination.cards.append(note)
        DaySections.reveal(note.id, in: &destination.cards)
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
    func matches(_ query: String) -> Bool
    {


        let term = query.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized collection-search query */

        return term.isEmpty || title.localizedStandardContains(term)
        || lists.filter
        {
            !$0.isArchived
        } .contains
        {
            list in
            list.title.localizedStandardContains(term)
            || list.cards.contains
            {

                !$0.isSectionDivider
                && ($0.word.localizedStandardContains(term)
                    || PlanRichText.plain($0.descriptionOverride ?? "").localizedStandardContains(term))
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
    mutating func restore(existingTitles: [String])
    {


        let base =
        title == "Week Board"
        ? "Week Board (Restored)" : title /* Restore name avoiding confusion with the live Week tab */

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
    static func archivedWeekBoard(lists: [KanbanList], savedCardIDs: Set<Int>) -> PersonalCollection
    {


        var board = PersonalCollection(
            title: "Week Board", kind: .board, icon: .project) /* Archived collection preserving the Week workspace */

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
    static func uniqueTitle(_ base: String, existingTitles: [String]) -> String
    {


        let titles = Set(
            existingTitles.map
            {
                $0.lowercased()
            })                /* Existing names compared without case distinctions */
        var candidate = base  /* Proposed name retried until unique                */
        var number = 2        /* Numeric suffix for resolving name collisions      */

        while titles.contains(candidate.lowercased())
        {


            candidate = "\(base) (\(number))"
            number += 1
        }


        return candidate
    }

}


///
/// Identifies a bookmarked record in a personal collection
///
/// @section    Purpose
///     Keep collection-local record IDs distinct in the combined Saved destination
///
struct PersonalCollectionBookmarkedCard: Identifiable, Hashable
{


    let collectionID:    UUID        /* Owning personal collection identity       */
    let collectionTitle: String      /* Collection name shown in Saved            */
    let listID:          Int         /* Containing collection-local list identity */
    let listTitle:       String      /* Containing list name shown in Saved       */
    let card:            KanbanCard  /* Complete bookmarked record                */

    ///
    /// @fcn        PersonalCollectionBookmarkedCard.id
    /// @brief      Build a stable Saved-row identity across collections
    /// @details    Combines the collection UUID with its local card ID to avoid collisions
    ///
    /// @return     (String) composite row identity
    ///
    var id: String
    {
            "\(collectionID.uuidString):\(card.id)"
    }  /* Collection-scoped row identity */

}
