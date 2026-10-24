// --------------------------------------------------------------------------------------------------
// @file       ItemMetadata.swift
// @brief      Shared item presentation and authored metadata
// @details    Defines serializable assignees, comments, scheduling intent, reactions, section
//             layout, and sharing values.
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
enum CardAssigneeKind: String, Codable, Sendable
{


    case registeredUser  /* Stable server user reference */
    case manual          /* User-entered display name    */
}


///
/// Represents one person associated with a card
///
/// @section    Purpose
///     Preserve a stable registered-user reference or a manual display name without conflating them
///
struct CardAssignee: Identifiable, Hashable, Codable, ExpressibleByStringLiteral, Sendable
{


    let id:          UUID              /* Stable assignment row ID  */
    let kind:        CardAssigneeKind  /* Registered or manual      */
    let userID:      String?           /* Stable registered user ID */
    var displayName: String            /* Name shown on the card    */


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
    init(id: UUID = UUID(), kind: CardAssigneeKind, userID: String? = nil, displayName: String)
    {


        self.id = id
        self.kind = kind
        self.userID = userID
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
    static func manual(_ displayName: String) -> CardAssignee
    {


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
    static func registered(userID: String, displayName: String) -> CardAssignee
    {


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
    init(stringLiteral value: String)
    {


        self = .manual(value)
    }

}


///
/// Defines the item's editing presentation
///
/// @section    Purpose
///     Selects Card or Note interface while preserving identity and all retained content.
///
enum ItemPresentation: String, Codable, CaseIterable, Identifiable, Sendable
{


    case card
    case note

    var id: String
    {
        rawValue
    }  /* Stable item-kind identity         */

    var title: String
    {
        self == .note ? "Note" : "Card"
    }  /* User-facing name of the item kind */

}


///
/// Defines per-item List preview rendering
///
/// @section    Purpose
///     Separates Card, Note, and picture preview choices from creation-time Card or Note
///     presentation defaults.
///
enum ItemDisplayFormat: String, Codable, CaseIterable, Identifiable, Sendable
{


    case card, note, divider, picture, title, text

    var id: String
    {
        rawValue
    }

    var title: String
    {
        rawValue.capitalized
    }

    var symbol: String
    {

        switch self
        {

        case .card:
                    "rectangle.stack"
        case .note:
                    "note.text"
        case .divider:
                    "minus"
        case .picture:
                    "photo"
        case .title:
                    "textformat.size.larger"
        case .text:
                    "text.alignleft"
        }

    }

}


///
/// Distinguishes date-only scheduling from a timed value
///
/// @section    Purpose
///     Preserves scheduling intent so calendar-day comparisons and visible date badges do not infer
///     a time the user did not choose.
///
enum CardDateKind: String, CaseIterable, Codable, Sendable, Identifiable
{


    case date, time, dateAndTime
    var id: String
    {
        rawValue
    }

    var title: String
    {

        switch self
        {

        case .date:
                    "Date only";

        case .time:
                    "Time only";

        case .dateAndTime:
                    "Date & time"
        }

    }

    var includesDate: Bool
    {
        self != .time
    }

    var includesTime: Bool
    {
        self != .date
    }


    ///
    /// @fcn        CardDateKind.normalized
    /// @brief      Normalize a date value for its stored precision
    /// @details    Date-only values use the supplied calendar's day boundary; other kinds retain their time
    ///             information.
    ///
    /// @param[in]  value     Date value whose precision or display components should be resolved
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (Date) local start-of-day for date-only precision, otherwise the original date value
    ///
    func normalized(_ value: Date, calendar: Calendar = .current) -> Date
    {

        self == .date ? calendar.startOfDay(for: value) : value
    }


    ///
    /// @fcn        CardDateKind.label
    /// @brief      Format a date value using this kind's components
    /// @details    Selects date-only, time-only, or combined formatting so the label reflects the stored precision.
    ///
    /// @param[in]  value  Date value whose precision or display components should be resolved
    ///
    /// @return     (String) label containing only the date and time components included by this kind
    ///
    func label(for value: Date) -> String
    {

        let date = DateFormatter()
        date.dateStyle = .medium
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "h:mm a"
        switch self
        {

        case .date:
            return date.string(from: value)
        case .time:
            return time.string(from: value)
        case .dateAndTime:
            return date.string(from: value) + " • " + time.string(from: value)
        }

    }

}


///
/// Retains one authored emoji reaction
///
/// @section    Purpose
///     Keeps author identity and emoji independent of labels, importance, bookmarks, and
///     completion.
///
struct ItemEmojiReaction: Identifiable, Hashable, Codable, Sendable
{


    var id = UUID()
    let emoji:    String
    let authorID: UUID
    var createdAt = Date()


    ///
    /// @fcn        ItemEmojiReaction.validatedEmoji
    /// @brief      Accept a single supported emoji reaction
    /// @details    Trims surrounding whitespace and rejects empty, multi-character, or nonemoji input by returning
    ///             nil.
    ///
    /// @param[in]  input  User-entered emoji text to trim and validate
    ///
    /// @return     (String?) accepted single emoji, or nil for unsupported input
    ///
    static func validatedEmoji(_ input: String) -> String?
    {

        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 1,
        value.unicodeScalars.contains(where:
            {

                $0.properties.isEmoji
                && ($0.value > 127 || value.unicodeScalars.contains(where:
                        {
                            $0.value == 0x20E3
                        }))
            })
        else
        {
            return nil
        }

        return value
    }


    ///
    /// @fcn        ItemEmojiReaction.toggling
    /// @brief      Toggle the current author's reaction for one emoji
    /// @details    Rejects invalid emoji; otherwise removes the matching author's existing reaction or adds a new one
    ///             while preserving other authors.
    ///
    /// @param[in]  input      User-entered emoji text to trim and validate
    /// @param[in]  authorID   Stable local author UUID for the explicit reaction action
    /// @param[in]  reactions  Existing reaction records, including other authors' selections
    ///
    /// @return     ([Self]?) updated author-qualified reactions, or nil for invalid emoji
    ///
    static func toggling(_ input: String, authorID: UUID, in reactions: [Self]) -> [Self]?
    {

        guard let emoji = validatedEmoji(input) else
        {
            return nil
        }

        if reactions.contains(where:
            {
                $0.authorID == authorID && $0.emoji == emoji
            })
        {

            return reactions.filter
            {
                !($0.authorID == authorID && $0.emoji == emoji)
            }

        }

        return reactions + [Self(emoji: emoji, authorID: authorID)]
    }

}


///
/// Resolves a stable local reaction author
///
/// @section    Purpose
///     Preserves identity across profile creation and avoids creating an identifier merely by
///     reading reactions.
///
enum LocalReactionIdentity
{


    static let key = "Plenact.LocalReactionAuthor.v1"


    ///
    /// @fcn        LocalReactionIdentity.current
    /// @brief      Read the existing local reaction author identity
    /// @details    Returns nil for missing or invalid storage without creating a new identity as a side effect of
    ///             rendering.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (UUID?) existing valid author UUID, or nil without creating one
    ///
    static func current(in defaults: UserDefaults = .standard) -> UUID?
    {

        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }


    ///
    /// @fcn        LocalReactionIdentity.forUserAction
    /// @brief      Obtain a stable author identity for an explicit reaction
    /// @details    Reuses a stored UUID or creates and persists one only when the user acts.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (UUID) existing author UUID or a newly persisted identity for this explicit user action
    ///
    static func forUserAction(in defaults: UserDefaults = .standard) -> UUID
    {

        if let existing = current(in: defaults)
        {
            return existing
        }

        let id = UUID();
        defaults.set(id.uuidString, forKey: key);
        return id
    }

}


// -------------------------------------- MARK: - Card Comment ------------------------------- //


///
/// Represents a user-authored entry in a kanban card's activity feed
///
/// @section    Purpose
///     Preserve comment identity, author, content, and creation time as card data
///
struct KanbanComment: Identifiable, Hashable, Codable, Sendable
{


    let id:        UUID    /* Unique identifier for the comment                 */
    let author:    String  /* Author of the comment                             */
    let body:      String  /* Body text of the comment                          */
    let createdAt: Date    /* Timestamp indicating when the comment was created */


    ///
    /// @fcn        KanbanComment.init(id:author:body:createdAt:)
    /// @brief      Initialize a card activity comment
    /// @details    Uses the supplied content and defaults the identity and timestamp when omitted
    ///
    ///
    /// @param[in]  id         Comment identity
    /// @param[in]  author     Display name of the comment author
    /// @param[in]  body       Comment text
    /// @param[in]  createdAt  Comment creation time
    ///
    /// @return     (KanbanComment) configured activity entry
    /// @post       The comment retains the supplied author and text
    ///
    init(id: UUID = UUID(), author: String, body: String, createdAt: Date = .now)
    {


        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }

}


///
/// Builds the text-only payload shared from a Note
///
/// @section    Purpose
///     Keep sharing limited to the Note title, written body, and explicitly attached web links
///
enum NoteTextSharing
{


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
    static func text(for note: KanbanCard) -> String
    {


        var sections = [note.word] /* Share-text sections beginning with the Note title */

        if let body = note.descriptionOverride, !body.isEmpty
        {  /* Nonempty Note body included in shared text */


            sections.append(PlanRichText.plain(body))
        }

        let links = (note.attachments ?? []).compactMap
        {

        attachment -> String? in /* Web links appended to the shared Note text */
            guard attachment.kind == .link, let url = attachment.url
            else
            {  /* Address of a shareable link attachment     */


                return nil
            }

            return url.absoluteString
        }

        if !links.isEmpty
        {


            sections.append(links.joined(separator: "\n\n"))
        }

        return sections.joined(separator: "\n\n")
    }

}


///
/// Identifies configurable sections within a Card
///
/// @section    Purpose
///     Controls presentation ordering and visibility without removing the content stored in hidden
///     sections.
///
enum CardSection: String, CaseIterable, Codable, Identifiable, Sendable
{


    case quickActions, media, description, details, checklists, activity
    var id: String
    {
        rawValue
    }

    var title: String
    {

        switch self
        {

        case .quickActions:
                    "Quick Actions"
        case .media:
                    "Photos & Attachments"
        case .description:
                    "Description"
        case .details:
                    "Details"
        case .checklists:
                    "Checklists"
        case .activity:
                    "Activity"
        }

    }

}


///
/// Retains Card section ordering and visibility
///
/// @section    Purpose
///     Normalizes repeated or omitted section identifiers for display while preserving the data in
///     hidden sections.
///
struct CardSectionLayout: Hashable, Codable, Sendable
{


    var order:    [CardSection] = CardSection.allCases
    var hidden:   Set<CardSection> = []
    var sections: [CardSection]
    {

        var seen: Set<CardSection> = []
        return (order + CardSection.allCases).filter
        {
            seen.insert($0).inserted && !hidden.contains($0)
        }

    }

}


///
/// Carries the visible content of a scheduling badge
///
/// @section    Purpose
///     Combines a title, formatted value, and system symbol and derives a concise accessibility
///     label.
///
struct CardScheduleBadge: Equatable
{


    let title:       String
    let value:       String
    let systemImage: String
    var label:       String
    {
        title.isEmpty ? value : title + " · " + value
    }

}
