// --------------------------------------------------------------------------------------------------
// @file       LibraryBrowse.swift
// @brief      Derived Library filters and owner-qualified browsing
// @details    Builds upcoming previews and label matches without duplicating canonical Card
//             records or taking persistence ownership.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Defines the Library's browse categories
///
/// @section    Purpose
///     Provides labels and search prompts for user collections, labels, examples, templates, and
///     help.
///
enum LibraryBrowseFilter: String, CaseIterable, Identifiable
{


    case all = "All", lists = "Lists", boards = "Boards", labels = "Labels", examples = "Examples", templates =
            "Templates", help = "Help"
    var id: String
    {
        rawValue
    }

    var searchPrompt: String
    {

        switch self
        {

        case .all:
                    "Find in your Plans"
        case .lists:
                    "Find in your Lists"
        case .boards:
                    "Find in your Boards"
        case .labels:
                    "Find in your Labels"
        case .templates:
                    "Find in Templates"
        case .examples:
                    "Find in Examples"
        case .help:
                    "Find in Help"
        }

    }

    var symbol: String
    {

        switch self
        {

        case .all:
                    "books.vertical";

        case .lists:
                    "list.bullet";

        case .boards:
                    "rectangle.split.3x1";

        case .labels:
                    "tag";

        case .templates:
                    "square.stack.3d.up";

        case .examples:
                    "sparkles";

        case .help:
                    "questionmark.circle"
        }

    }

    var accent: Color
    {

        switch self
        {

        case .all:
            .blue;

        case .lists:
            .teal;

        case .boards:
            .indigo;

        case .labels:
            .purple;

        case .templates:
            .orange;

        case .examples:
            .pink;

        case .help:
            .teal
        }

    }

    var browsesCollections: Bool
    {
        self == .all || self == .lists || self == .boards
    }

    var searchHint: String
    {

        switch self
        {

        case .templates:
                    "Search saved routines and template starting points"
        case .examples:
                    "Search example names, descriptions, and previews"
        case .help:
                    "Search help titles and instructions"
        case .labels:
                    "Search labels assigned to active items"
        default:
                    "Search your personal collections, cards, and notes"
        }

    }

    var searchContext: String
    {

        switch self
        {

        case .templates:
                    "Templates · Routines and reusable starting points"
        case .examples:
                    "Examples · Explore before adding"
        case .help:
                    "Help · Guides and reference"
        case .labels:
                    "Labels · Active cards across Week and Plans"
        default:
                    "Your Plans · Collections, cards, and notes"
        }

    }


    ///
    /// @fcn        LibraryBrowseFilter.includes
    /// @brief      Check whether an active collection belongs in this Library filter
    /// @details    Requires a collection-browsing filter and matches list or board kind unless the All filter is
    ///             selected.
    ///
    /// @param[in]  collection  Personal collection supplying the owner context
    ///
    /// @return     (Bool) true for an active collection of a kind included by this browsing filter
    ///
    func includes(_ collection: PersonalCollection) -> Bool
    {

        collection.isActive && browsesCollections
        && (self == .all || (self == .lists ? collection.kind == .list : collection.kind == .board))
    }

}


///
/// Represents a ranked upcoming Library item
///
/// @section    Purpose
///     Pairs its canonical owner, list, and Card with the reason, rank, and reference date used by
///     the preview.
///
struct LibraryPlateItem: Identifiable
{


    let collection: PersonalCollection
    let list:       KanbanList
    let card:       KanbanCard
    let reason:     String
    let rank:       Int
    let date:       Date
    var id:         String
    {
            "\(collection.id.uuidString).\(card.id)"
    }

}


///
/// Builds the upcoming Library preview selection
///
/// @section    Purpose
///     Ranks unfinished, non-divider content by date-bearing urgency and importance while retaining
///     owner-qualified identities.
///
enum LibraryPlateSelection
{


    ///
    /// @fcn        LibraryPlateSelection.items
    /// @brief      Rank unfinished Library content for the upcoming-items preview
    /// @details    Considers date-bearing urgency and explicit importance across active owners and lists while
    ///             excluding completed cards and section dividers.
    ///
    /// @param[in]  collections  Personal collection values available to the operation
    /// @param[in]  important    Importance selections or the Important filter state
    /// @param[in]  now          Reference time used instead of an implicit clock read
    /// @param[in]  calendar     Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     ([LibraryPlateItem]) ranked upcoming or important unfinished Library items
    ///
    static func items(
        in collections: [PersonalCollection], important: [LibraryRecentItem], now: Date = .now,
        calendar: Calendar = .current
    ) -> [LibraryPlateItem]
    {

        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        var items: [LibraryPlateItem] = []
        for collection in collections where collection.isActive
        {

            for list in collection.lists where !list.isArchived
            {

                for card in list.cards where !card.isSectionDivider && !card.isTitleChecked
                {

                    let marked = important.contains(LibraryRecentItem(collectionID: collection.id, cardID: card.id))
                    var due = card.dueDate
                    // A time without a date cannot be assigned an urgency day.
                    if !card.dueDateKind.includesDate
                    {
                        due = nil
                    }

                    let rank: Int
                    let reason: String
                    if let due, due < today || (card.dueDateKind.includesTime && due < now)
                    {

                        rank = 0;
                        reason = "Overdue · " + card.dueDateLabel
                    }
                    else if let due, calendar.isDate(due, inSameDayAs: now)
                    {

                        rank = 1;

                        reason =
                        card.dueDateKind.includesTime ? "Due at " + CardDateKind.time.label(for: due) : "Due today"
                    }
                    else if let due, due < horizon
                    {

                        rank = 2;
                        reason = "Due " + card.dueDateLabel
                    }
                    else if marked
                    {

                        rank = 3;
                        reason = "Marked important"
                    }
                    else
                    {

                        continue
                    }

                    items.append(
                        LibraryPlateItem(
                            collection: collection, list: list, card: card, reason: reason, rank: rank,
                            date: due ?? .distantFuture))
                }

            }

        }

        return Array(
            items.sorted
            {

                if $0.rank != $1.rank
                {
                    return $0.rank < $1.rank
                }

                if $0.date != $1.date
                {
                    return $0.date < $1.date
                }

                return $0.id < $1.id
            } .prefix(4))
    }

}


///
/// Defines the environment callback for opening a Library item
///
/// @section    Purpose
///     Uses an inert default so views outside a Library route do not create visit-history side
///     effects.
///
struct LibraryItemOpenedKey: EnvironmentKey
{


    static let defaultValue: (Int) -> Void =
    {
        _ in
    }

}


///
/// Exposes the current Library item-open callback
///
/// @section    Purpose
///     Lets descendants report a viewed Card to the owner without coupling them to its
///     recent-history storage.
///
extension EnvironmentValues
{


    var libraryItemOpened: (Int) -> Void
    {

        get
        {
            self[LibraryItemOpenedKey.self]
        }

        set
        {
            self[LibraryItemOpenedKey.self] = newValue
        }

    }

}


///
/// Renders one upcoming Library preview tile
///
/// @section    Purpose
///     Displays the item's reason and owner styling in a Dynamic Type-scaled tile without changing
///     the source record.
///
struct LibraryPlateTile: View
{


    let item:                                                LibraryPlateItem
    @ScaledMetric(relativeTo: .body) private var tileWidth:  CGFloat = 132
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 110

    var body: some View
    {

        VStack(alignment: .leading, spacing: 8)
        {

            HStack
            {

                Image(
                    systemName: item.rank == 0
                    ? "exclamationmark.circle.fill" : (item.rank == 3 ? "star.fill" : "clock")
                )
                .foregroundStyle(item.rank == 0 ? Color.red : item.collection.libraryIdentityColor)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
            }

            Text(item.card.word).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(3)
            Spacer(minLength: 4)
        }
        .padding(12)
        .frame(width: tileWidth, alignment: .leading)
        .frame(minHeight: tileHeight, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay
        {

            RoundedRectangle(cornerRadius: 14).fill(item.collection.libraryIdentityColor.opacity(0.10))
            .allowsHitTesting(false)
        }
        .overlay
        {

            RoundedRectangle(cornerRadius: 14).strokeBorder(
                item.collection.libraryIdentityColor.opacity(0.3), lineWidth: 1
            ).allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.collection.title + ", " + item.reason)
    }

}


///
/// Browses workspace Cards carrying a selected label
///
/// @section    Purpose
///     Resolves live owner-qualified matches, filters their displayed context, and opens the chosen
///     source item.
///
struct LibraryLabelMatchesView: View
{


    let label: KanbanLabel
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var openedCard: PlanningSearchResult?
    @State private var query = ""
    private var matches: [PlanningSearchResult]
    {

        let owners = WorkspaceBrowseIndex.owners(document: access?.document, library: access?.library ?? [])
        let all =
        WorkspaceBrowseIndex.labels(in: owners, catalog: LabelLibraryStore.load()).first
        {
            $0.id == label.id
        }?
        .matches ?? []
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter
        {

            query.isEmpty || $0.card.word.localizedStandardContains(query)
            || $0.listTitle.localizedStandardContains(query) || $0.collectionTitle.localizedStandardContains(query)
        }

    }

    var body: some View
    {

        NavigationStack
        {

            List
            {

                if matches.isEmpty
                {
                    Text("No active cards or notes match this label.").foregroundStyle(.secondary)
                }

                ForEach(matches)
                {
                    result in
                    Button
                    {

                        openedCard = result
                    }
                    label:
                    {

                        HStack(spacing: 12)
                        {

                            Image(systemName: result.card.presentation == .note ? "note.text" : "rectangle")
                            .foregroundStyle(label.color.color)
                            VStack(alignment: .leading, spacing: 4)
                            {

                                Text(result.card.word).font(.headline).foregroundStyle(.primary)
                                Text(result.collectionTitle + " · " + result.listTitle).font(.caption).foregroundStyle(
                                    .secondary)
                            }

                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        } .padding(.vertical, 6)
                    } .buttonStyle(.plain)
                }

            }
            .navigationTitle(label.name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find in this label")
            .toolbar
            {
                ToolbarItem(placement: .confirmationAction)
                {
                    Button("Done")
                    {
                        dismiss()
                    }

                }

            }
            .fullScreenCover(item: $openedCard)
            {
                result in
                if let week = access?.document.weeks.first(where:
                    {
                        $0.id == result.collectionID
                    })
                {

                    PlanningCalendarWeekView(
                        week: week, initialDayID: result.listID, initialCardID: result.card.id,
                        onLeaveForHome:
                        {

                            openedCard = nil;
                            dismiss()
                        })
                }
                else if let collection = access?.library.first(where:
                    {
                        $0.id == result.collectionID && $0.isActive
                    })
                {

                    PlanningSearchLibraryView(
                        collection: collection, initialListID: result.listID, initialCardID: result.card.id,
                        onLeaveForHome:
                        {

                            openedCard = nil;
                            dismiss()
                        })
                }

            }

        }

    }

}
