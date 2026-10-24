// --------------------------------------------------------------------------------------------------
// @file       ActivityView.swift
// @brief      Recent, bookmarked, and focused Activity presentation
// @details    Resolves retained references against live owners and opens direct item destinations
//             that return to their calling Activity surface.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Identifies a saved Card in a personal collection
///
/// @section    Purpose
///     Carries the owner UUID and local List and Card identities needed to open the correct
///     retained source.
///
struct PersonalSavedCardTarget: Equatable
{


    let collectionID: UUID  /* Owning personal collection         */
    let listID:       Int   /* Containing collection-local list   */
    let cardID:       Int   /* Collection-local bookmarked record */
}


///
/// Identifies a bookmarked Card within the Week snapshot
///
/// @section    Purpose
///     Retains the containing list ID and title so selecting a Saved row can resolve its original
///     content.
///
struct SavedCardResult: Identifiable
{


    let card:      KanbanCard  /* Saved card data           */
    let listID:    Int         /* List opened when selected */
    let listTitle: String      /* Containing list title     */

    ///
    /// @fcn        SavedCardResult.id
    /// @brief      Identify a bookmarked-card row
    /// @details    Reuses the card's stable identity in the Week snapshot
    ///
    /// @return     (Int) card identity
    /// @pre        Card IDs are unique within the displayed Week Board
    /// @post       Bookmark membership and card content remain unchanged
    ///
    var id: Int
    {
        card.id
    }  /* Saved card's stable Board-local identity */

}


///
/// Defines the active Activity content selection
///
/// @section    Purpose
///     Distinguishes the available Saved and focus categories while keeping the underlying Cards in
///     their original owners.
///
enum ActivityFocus: String, CaseIterable, Identifiable
{


    case saved = "Saved", dueSoon = "Due soon", labels = "By label"
    var id: String
    {
        rawValue
    }

    var symbol: String
    {

        switch self
        {

        case .saved:
                    "bookmark";

        case .dueSoon:
                    "clock";

        case .labels:
                    "tag"
        }

    }

}


///
/// Selects Activity content by its focus rules
///
/// @section    Purpose
///     Evaluates due-soon and other derived views without changing completion, importance, or
///     stored Card data.
///
enum ActivityFocusSelection
{


    ///
    /// @fcn        ActivityFocusSelection.isDueSoon
    /// @brief      Find unfinished date-bearing work due before the upcoming horizon
    /// @details    Excludes dividers and completed cards, requires a date-bearing due value, and includes overdue
    ///             work before the seven-calendar-day boundary.
    ///
    /// @param[in]  card      Card or note being inspected or changed
    /// @param[in]  now       Reference time used instead of an implicit clock read
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (Bool) true for eligible unfinished work due before the seven-day boundary, including overdue work
    ///
    static func isDueSoon(_ card: KanbanCard, now: Date = .now, calendar: Calendar = .current) -> Bool
    {

        guard !card.isSectionDivider, !card.isTitleChecked, card.dueDateKind.includesDate, let due = card.dueDate,
        let horizon = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))
        else
        {
            return false
        }

        return due < horizon
    }


    ///
    /// @fcn        ActivityFocusSelection.dueReason
    /// @brief      Describe a card's due status for Activity
    /// @details    Compares its due date with the reference time and local day to produce the contextual reason text.
    ///
    /// @param[in]  card      Card or note being inspected or changed
    /// @param[in]  now       Reference time used instead of an implicit clock read
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (String) overdue, due-today, or due text; an empty string when no due date exists
    ///
    static func dueReason(_ card: KanbanCard, now: Date = .now, calendar: Calendar = .current) -> String
    {

        guard let due = card.dueDate else
        {
            return ""
        }

        if due < calendar.startOfDay(for: now) || (card.dueDateKind.includesTime && due < now)
        {

            return "Overdue · " + card.dueDateLabel
        }

        if calendar.isDate(due, inSameDayAs: now)
        {
            return "Due today · " + card.dueDateLabel
        }

        return "Due · " + card.dueDateLabel
    }

}


///
/// Defines the toolbar's revisit destinations
///
/// @section    Purpose
///     Supplies labels, symbols, and explanations for recent, bookmarked, and archived content.
///
enum ToolbarRevisitDestination: String, CaseIterable, Identifiable
{


    case recent, bookmarked, archived
    var id: String
    {
        rawValue
    }

    var title: String
    {

        switch self
        {

        case .recent:
                    "Recently viewed";

        case .bookmarked:
                    "Bookmarked";

        case .archived:
                    "Archived content"
        }

    }

    var symbol: String
    {

        switch self
        {

        case .recent:
                    "clock.arrow.circlepath";

        case .bookmarked:
                    "bookmark";

        case .archived:
                    "archivebox"
        }

    }

    var detail: String
    {

        switch self
        {

        case .recent:
                    "Pick up where you left off."
        case .bookmarked:
                    "Return to something you kept."
        case .archived:
                    "Find collections you put away."
        }

    }

}


///
/// Presents the toolbar's revisit choices
///
/// @section    Purpose
///     Delegates destination selection to the caller so the existing Activity navigation remains
///     authoritative.
///
struct ToolbarRevisitMenu: View
{


    let onChoose: (ToolbarRevisitDestination) -> Void
    var body:     some View
    {

        VStack(alignment: .leading, spacing: 4)
        {

            Text("Revisit").font(.headline).accessibilityAddTraits(.isHeader).padding(.bottom, 8)
            ForEach(ToolbarRevisitDestination.allCases)
            {
                choice in
                Button
                {

                    onChoose(choice)
                }
                label:
                {

                    HStack(spacing: 12)
                    {

                        Image(systemName: choice.symbol).frame(width: 24).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3)
                        {

                            Text(choice.title).font(.subheadline)
                            Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toolbar.revisit." + choice.rawValue)
            }

        }
        .padding(16).frame(idealWidth: 290)
    }

}


///
/// Presents recent, bookmarked, and archived Activity content
///
/// @section    Purpose
///     Resolves retained references against live calendar and Library owners and presents direct
///     item routes that return to Activity.
///
struct SavedCardsView: View
{


    let planningDocument:   PlanningCalendarDocument?
    var revisitDestination: Binding<ToolbarRevisitDestination?> = .constant(nil)
    private var revisit:    ToolbarRevisitDestination?
    {
        revisitDestination.wrappedValue
    }

    @AppStorage(ActivityRecentStore.key) private var recentData = Data()
    @AppStorage("Plenact.ActivityShowsCovers") private var showsCovers = true
    @AppStorage("Plenact.ActivityRecentSquareCards") private var usesSquareRecentCards = false
    @Environment(\.accessibilityReduceMotion) private var reduceRecentMotion
    @State private var query = ""
    @State private var showsSearch = false
    @State private var confirmsClear = false
    @State private var historicalTarget: ActivityRecentResult?
    @State private var focus:            ActivityFocus = .saved
    @State private var selectedLabelID:  String?
    @State private var activityHeaderHeight: CGFloat = 0
    @State private var focusLabelLibrary = LabelLibraryStore.load()
    private var focusCalendar: Calendar
    {
        planningDocument?.calendar ?? .current
    }


    private var availableFocusItems: [ActivityRecentResult]
    {

        var items: [ActivityRecentResult] = []
        for week in planningDocument?.weeks ?? []
        {

            let current = week.startKey == planningDocument?.currentWeekKey
            for list in (current ? lists : week.collection.lists) where !list.isArchived
            {

                for card in list.cards where !card.isSectionDivider
                {

                    items.append(
                        ActivityRecentResult(
                            item: LibraryRecentItem(collectionID: week.id, cardID: card.id), card: card, list: list,
                            location: list.title + " · " + week.compactRangeTitle, week: week, isCurrent: current))
                }

            }

        }

        for collection in collections where collection.isActive
        {

            for list in collection.lists where !list.isArchived
            {

                for card in list.cards where !card.isSectionDivider
                {

                    items.append(
                        ActivityRecentResult(
                            item: LibraryRecentItem(collectionID: collection.id, cardID: card.id), card: card,
                            list: list,
                            location: collection.title == list.title
                            ? collection.title : collection.title + " · " + list.title, week: nil, isCurrent: false)
                    )
                }

            }

        }

        return items
    }

    private var availableFocusLabels: [KanbanLabel]
    {

        let assigned = Set(availableFocusItems.flatMap
            {
                $0.card.labelIDs
            })
        return focusLabelLibrary.labels.filter
        {
            assigned.contains($0.id)
        }
        .sorted
        {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

    }

    private var selectedFocusLabel: KanbanLabel?
    {

        availableFocusLabels.first
        {
            $0.id == selectedLabelID
        }

    }

    private var focusedItems: [ActivityRecentResult]
    {

        let items = availableFocusItems.filter
        {
            matches($0.card.word, $0.location)
        }

        switch focus
        {

        case .saved:
            return []
        case .dueSoon:
            return items.filter
            {
                ActivityFocusSelection.isDueSoon($0.card, calendar: focusCalendar)
            } .sorted
            {

                if $0.card.dueDate != $1.card.dueDate
                {

                    return ($0.card.dueDate ?? .distantFuture) < ($1.card.dueDate ?? .distantFuture)
                }

                return $0.id < $1.id
            }

        case .labels:
            guard let selectedLabelID else
            {
                return []
            }

            return items.filter
            {
                $0.card.labelIDs.contains(selectedLabelID)
            }

        }

    }

    private var focusHeading: some View
    {

        Menu
        {

            Picker("Show items", selection: $focus)
            {

                ForEach(ActivityFocus.allCases)
                {
                    option in
                    Label(option.rawValue, systemImage: option.symbol).tag(option)
                }

            }

        }
        label:
        {

            HStack(spacing: 8)
            {

                Label(focus.rawValue, systemImage: focus.symbol).font(.title2.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            } .foregroundStyle(.primary).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .accessibilityLabel("Activity view: " + focus.rawValue)
    }

    private var focusContent: some View
    {

        VStack(alignment: .leading, spacing: 12)
        {

            if focus == .labels
            {

                Menu
                {

                    ForEach(availableFocusLabels)
                    {
                        label in
                        Button
                        {

                            selectedLabelID = label.id
                        }
                        label:
                        {

                            Label(label.name, systemImage: selectedLabelID == label.id ? "checkmark" : "tag")
                        }

                    }

                }
                label:
                {

                    HStack
                    {

                        if let label = selectedFocusLabel
                        {

                            KanbanLabelChip(label: label)
                        }
                        else
                        {

                            Text("Choose a label")
                        }

                        Image(systemName: "chevron.down").font(.caption)
                    } .frame(minHeight: 44)
                } .disabled(availableFocusLabels.isEmpty)
                Text("Cards and notes using this label across your Week and Plans.")
                .font(.caption).foregroundStyle(.secondary)
            }
            else
            {

                Text("Unfinished items that are overdue or due within the next 7 days.")
                .font(.caption).foregroundStyle(.secondary)
            }

            if focusedItems.isEmpty
            {

                Text(
                    focus == .labels
                    ? (availableFocusLabels.isEmpty
                        ? "Add labels to a card or note to browse them here."
                        : "No items match this label and search.")
                    : "Nothing due soon matches this view."
                )
                .font(.subheadline).foregroundStyle(.secondary)
            }

            ForEach(focusedItems)
            {
                result in
                Button
                {

                    openRecent(result)
                }
                label:
                {

                    HStack(alignment: .top, spacing: 12)
                    {

                        Image(systemName: result.card.presentation == .note ? "note.text" : "rectangle")
                        .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4)
                        {

                            Text(result.card.word).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(result.location).font(.caption).foregroundStyle(.secondary)
                            Text(
                                focus == .dueSoon
                                ? ActivityFocusSelection.dueReason(result.card, calendar: focusCalendar)
                                : "Label: " + (selectedFocusLabel?.name ?? "")
                            )
                            .font(.caption).foregroundStyle(focus == .dueSoon ? Color.orange : Color.secondary)
                        }

                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    } .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                } .buttonStyle(.plain).accessibilityHint("Opens this item in " + result.location)
            }

        } .padding(16)
    }


    ///
    /// Resolves a retained Activity reference to live content
    ///
    /// @section    Purpose
    ///     Pairs the recent-item identity with its Card, List, location, and optional dated Week
    ///     for direct navigation.
    ///
    private struct ActivityRecentResult: Identifiable
    {


        let item:      LibraryRecentItem
        let card:      KanbanCard
        let list:      KanbanList
        let location:  String
        let week:      DatedPlanningWeek?
        let isCurrent: Bool
        var id:        String
        {
            item.id
        }

    }


    ///
    /// @fcn        SavedCardsView.matches
    /// @brief      Match saved content against the current search text
    /// @details    Searches the supplied title and location so users can find items by either content or owner
    ///             context.
    ///
    /// @param[in]  title     Display title or proposed title text
    /// @param[in]  location  Human-readable owner and list location used for matching
    ///
    /// @return     (Bool) true when the current search matches the supplied title or location
    ///
    private func matches(_ title: String, _ location: String) -> Bool
    {

        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || (title + " " + location).localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var recents: [ActivityRecentResult]
    {

        let items =
        recentData.isEmpty
        ? ActivityRecentStore.load()
        : ((try? JSONDecoder().decode([LibraryRecentItem].self, from: recentData)) ?? [])
        return items.compactMap
        {
            item in
            if let collection = collections.first(where:
                {
                    $0.id == item.collectionID && $0.isActive
                }),
            let list = collection.lists.first(where:
                {

                    !$0.isArchived && $0.cards.contains(where:
                        {
                            $0.id == item.cardID && !$0.isSectionDivider
                        })
                }),
            let card = list.cards.first(where:
                {
                    $0.id == item.cardID
                }),
            matches(card.word, collection.title + " " + list.title)
            {

                return ActivityRecentResult(
                    item: item, card: card, list: list,
                    location: collection.title == list.title ? collection.title : collection.title + " · " + list.title,
                    week: nil, isCurrent: false)
            }

            guard let week = planningDocument?.weeks.first(where:
                {
                    $0.id == item.collectionID
                }) else
            {
                return nil
            }

            let current = week.startKey == planningDocument?.currentWeekKey
            let source = current ? lists : week.collection.lists
            guard
            let list = source.first(where:
                {

                    !$0.isArchived && $0.cards.contains(where:
                        {
                            $0.id == item.cardID && !$0.isSectionDivider
                        })
                }),
            let card = list.cards.first(where:
                {
                    $0.id == item.cardID
                }), matches(card.word, list.title)
            else
            {
                return nil
            }

            return ActivityRecentResult(
                item: item, card: card, list: list, location: list.title + " · " + week.compactRangeTitle, week: week,
                isCurrent: current)
        }

    }


    ///
    /// @fcn        SavedCardsView.openRecent
    /// @brief      Navigate to an owner-qualified recent Activity item
    /// @details    Resolves the retained item against available workspace content and opens its current destination.
    ///
    /// @param[in]  result  Resolved search or Activity match to render or open
    ///
    /// @return     (Void) no return value
    ///
    private func openRecent(_ result: ActivityRecentResult)
    {

        historicalTarget = result
    }

    private var recentSection: some View
    {

        VStack(alignment: .leading, spacing: 10)
        {

            if revisit == nil
            {

                Button
                {

                    withAnimation(reduceRecentMotion ? nil : .easeInOut(duration: 0.2))
                    {

                        usesSquareRecentCards.toggle()
                    }
                }
                label:
                {

                    Text("Recent").font(.headline)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Recent card size")
                .accessibilityValue(usesSquareRecentCards ? "Square" : "Full size")
                .accessibilityHint(usesSquareRecentCards ? "Show full-size recent cards" : "Show square recent cards")
                .accessibilityIdentifier("activity.recent.toggleSize")
            }

            if recents.isEmpty
            {

                Text(
                    query.isEmpty
                    ? "Recently opened Cards and Notes will appear here." : "No recent items match your search."
                )
                .font(.subheadline).foregroundStyle(.secondary)
            }
            else
            {

                ScrollView(.horizontal, showsIndicators: false)
                {

                    HStack(spacing: 10)
                    {

                        ForEach(recents)
                        {
                            result in
                            Button
                            {

                                openRecent(result)
                            }
                            label:
                            {

                                VStack(alignment: .leading, spacing: usesSquareRecentCards ? 6 : 8)
                                {

                                    if showsCovers, let cover = result.card.coverAttachment
                                    {

                                        CardCoverPreview(attachment: cover, height: usesSquareRecentCards ? 40 : 64)
                                            .frame(height: usesSquareRecentCards ? 40 : 64).clipShape(
                                            RoundedRectangle(cornerRadius: 8))
                                    }

                                    Text(result.card.word).font(.subheadline.weight(.semibold)).lineLimit(usesSquareRecentCards ? 2 : 3)
                                    Spacer(minLength: 0)
                                    Text(result.location).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .padding(12)
                                .frame(
                                    width: usesSquareRecentCards && !showsCovers ? 144 : 156,
                                    height: usesSquareRecentCards ? (showsCovers ? 156 : 144) : (showsCovers ? 210 : 144),
                                    alignment: .topLeading
                                )
                                .clipped()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            } .buttonStyle(.plain).accessibilityHint("Reopen this item in " + result.location)
                        }

                    }

                }
                .frame(height: usesSquareRecentCards ? (showsCovers ? 156 : 144) : (showsCovers ? 210 : 144))

            }

        }

    }


    let lists:                [KanbanList]          /* Current Board snapshot                            */
    let savedCardIDs:         Set<Int>              /* Local bookmark set                                */
    @Binding var collections: [PersonalCollection]  /* Collections whose archived boards can be restored */
    let onOpenBoardCard:      (Int, Int) -> Void    /* Open the exact bookmarked item                    */
    let onOpenPersonalCard:
    (PersonalSavedCardTarget) -> Void                        /* Navigate to a bookmarked personal record             */
    let onRestoreBoard:                 (UUID) -> Void       /* Restore a saved board by identity                    */
    let onDeleteBoard:                  (UUID) -> Bool       /* Save permanent collection removal and report success */
    let onArchiveCard:                  (Int) -> Void        /* Archive a Week bookmark's canonical card             */
    let onDeleteCard:                   (Int) -> Bool        /* Report confirmed Week bookmark-card removal          */
    @State private var deletingBoard:   PersonalCollection?  /* Saved collection awaiting removal                    */
    @State private var deletingCard:    KanbanCard?          /* Week bookmark awaiting removal                       */
    @State private var inspectingBoard: PersonalCollection?  /* Archived collection being browsed                    */

    ///
    /// @fcn        SavedCardsView.savedCards
    /// @brief      Resolve bookmarks against available active cards
    /// @details    Traverses supplied lists in order, includes bookmarked non-divider cards,
    ///             and retains containing-list provenance; stale bookmark IDs produce no rows
    ///
    /// @return     ([SavedCardResult]) currently available bookmarked cards
    /// @pre        The caller supplies active Week lists
    /// @post       Stale bookmark IDs are not removed from the stored set
    ///
    private var savedCards: [SavedCardResult]
    {  /* Bookmarked cards paired with their containing lists */

        lists.flatMap
        {
            list in
            list.cards.compactMap
            {
                card in
                guard savedCardIDs.contains(card.id), !card.isSectionDivider, matches(card.word, list.title) else
                {


                    return nil
                }


                return SavedCardResult(card: card, listID: list.id, listTitle: list.title)
            }

        }

    }


    ///
    /// @fcn        SavedCardsView.personalSavedCards
    /// @brief      Resolve active personal bookmarks without merging their local ID spaces
    /// @details    PersonalCollection supplies collection/list provenance and filters archived or
    ///             divider content before these results are rendered
    ///
    /// @return     ([PersonalCollectionBookmarkedCard]) available personal bookmark rows
    ///
    private var archivedCollections: [PersonalCollection]
    {

        collections.filter
        {
            $0.isArchived == true && matches($0.title, "")
        }

    }

    private var personalSavedCards: [PersonalCollectionBookmarkedCard]
    {  /* Active personal bookmarks for Saved */

        collections.filter(\.isActive).flatMap(\.bookmarkedCards).filter
        {

            matches($0.card.word, $0.collectionTitle + " " + $0.listTitle)
        }

    }




    ///
    /// @fcn        SavedCardsView.activityHeader
    /// @brief      Present Activity controls and the independent horizontal Recent carousel
    /// @details    Measures its natural height so short windows and accessibility text can retain
    ///             a bounded header viewport while the browser keeps usable scrolling space.
    ///
    /// @return     (some View) Activity heading, optional search, revisit controls, and Recent cards
    ///
    private var activityHeader: some View
    {

        VStack(alignment: .leading, spacing: 16)
        {

            VStack(alignment: .leading, spacing: 4)
            {

                HStack
                {

                    Text("Activity").font(.largeTitle.weight(.bold))
                    Spacer()
                    Button
                    {

                        showsSearch.toggle();
                        if !showsSearch
                        {
                            query = ""
                        }

                    }
                    label:
                    {

                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search Activity")
                    Menu
                    {

                        Toggle("Show cover previews", isOn: $showsCovers)
                        Button("Clear recent history", systemImage: "trash", role: .destructive)
                        {

                            confirmsClear = true
                        }

                    }
                    label:
                    {

                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Activity options")
                }

                if let revisit
                {

                    Text(revisit.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

            }

            .frame(maxWidth: .infinity, alignment: .leading)

            if showsSearch
            {

                TextField("Find in Activity", text: $query)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
            }

            if revisit != nil
            {

                HStack
                {

                    Text(revisit?.title ?? "").font(.title2.weight(.semibold))
                    Spacer()
                    Button("All Activity")
                    {
                        revisitDestination.wrappedValue = nil
                    }
                    .font(.subheadline).frame(minHeight: 44)
                }

            }

            if revisit == nil || revisit == .recent
            {
                recentSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    ///
    /// @fcn        SavedCardsView.activityBrowserContents
    /// @brief      Present the selected Activity browser rows and archived collection actions
    /// @details    Keeps existing owner-qualified opening and lifecycle callbacks inside a common
    ///             bounded scroll viewport for Saved, Due soon, By label, and archive destinations.
    ///
    /// @return     (some View) selected browser content without its own outer scrolling surface
    ///
    private var activityBrowserContents: some View
    {

        VStack(alignment: .leading, spacing: 16)
        {

            if revisit == nil && focus != .saved
            {

                focusContent
            }
            else if revisit == nil || revisit == .bookmarked
            {

                VStack(alignment: .leading, spacing: 10)
                {

                    if savedCards.isEmpty && personalSavedCards.isEmpty
                    {


                        Label(
                            query.isEmpty ? "No saved items yet" : "No saved items match",
                            systemImage: "bookmark"
                        )
                        .font(.headline)
                        Text("Open a card and tap the bookmark to keep it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    else
                    {

                        if !savedCards.isEmpty
                        {

                            Text("Week")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            ForEach(savedCards)
                            {
                                result in
                                Button
                                {

                                    if let item = availableFocusItems.first(where:
                                        {

                                            $0.isCurrent && $0.list.id == result.listID
                                            && $0.card.id == result.card.id
                                        })
                                    {

                                        openRecent(item)
                                    }

                                }
                                label:
                                {

                                    HStack(spacing: 12)
                                    {

                                        Image(systemName: "bookmark.fill")
                                        .foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 3)
                                        {

                                            Text(result.card.word)
                                            .foregroundStyle(.primary)
                                            Text(result.listTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }


                                        Spacer()
                                        Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                    }

                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }

                                .buttonStyle(.plain)
                                .accessibilityHint("Opens this saved item.")
                                .accessibilityActions
                                {

                                    Button("Archive Card")
                                    {
                                        onArchiveCard(result.card.id)
                                    }

                                    Button("Delete Card")
                                    {
                                        deletingCard = result.card
                                    }

                                }

                            }

                        }


                        if !personalSavedCards.isEmpty
                        {

                            Text("Plans")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            ForEach(personalSavedCards)
                            {
                                result in
                                Button
                                {

                                    if let item = availableFocusItems.first(where:
                                        {

                                            $0.item.collectionID == result.collectionID
                                            && $0.list.id == result.listID && $0.card.id == result.card.id
                                        })
                                    {

                                        openRecent(item)
                                    }

                                }
                                label:
                                {

                                    HStack(spacing: 12)
                                    {

                                        Image(systemName: "bookmark.fill")
                                        .foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 3)
                                        {

                                            Text(result.card.word)
                                            .foregroundStyle(.primary)
                                            Text(
                                                result.collectionTitle == result.listTitle
                                                ? result.collectionTitle
                                                : result.collectionTitle + " · " + result.listTitle
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        }


                                        Spacer()
                                        Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                    }

                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }

                                .buttonStyle(.plain)
                                .accessibilityHint(
                                    "Opens this item in \(result.collectionTitle), \(result.listTitle).")
                            }

                        }

                    }

                }

                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            }


            if (revisit == .archived || (revisit == nil && focus == .saved))
            && collections.contains(where:
                {


                    $0.isArchived == true
                })
            {

                VStack(alignment: .leading, spacing: 12)
                {

                    Text("Archived Collections").font(.title2.weight(.semibold))
                    ForEach(archivedCollections)
                    {
                        board in
                        HStack
                        {

                            Image(systemName: "archivebox").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4)
                            {

                                Button(board.title)
                                {
                                    inspectingBoard = board
                                }
                                .font(.headline)
                                Text(
                                    "\(board.lists.count) lists · \(board.lists.flatMap(\.allCards).filter { !$0.isSectionDivider } .count) cards"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }


                            Spacer()
                            Button("Restore")
                            {
                                onRestoreBoard(board.id)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Restore \(board.title)")
                            Button("Delete", systemImage: "trash", role: .destructive)
                            {
                                deletingBoard = board
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Delete \(board.title)")
                        }

                    }


                    Text(
                        "Restored boards appear in Plans. Restoring a Week Board creates a separate board and leaves your current Week unchanged."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                .padding(16)

            }

            if revisit == .archived && archivedCollections.isEmpty
            {

                ContentUnavailableView(
                    "No archived collections", systemImage: "archivebox",
                    description: Text(
                        query.isEmpty
                        ? "Collections you archive will be available here."
                        : "No archived collections match this search."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    ///
    /// @fcn        SavedCardsView.body
    /// @brief      Present Recent items above a bounded, independently scrollable Activity browser
    /// @details    Keeps the browser selector outside its scroll viewport and allocates the remaining
    ///             view height to its rows. The header scrolls only when a short window or large
    ///             text cannot fit naturally above the browser. Existing item routes remain intact.
    ///
    /// @return     (some View) paper-backed Saved surface
    /// @post       Restore delegates to the root save-first callback; bookmarked-card selection
    ///             opens the bookmarked item directly without removing the bookmark
    ///
    var body: some View
    {  /* Saved-card directory and navigation destinations */


        ZStack
        {

            TodayPaperBackground()

            GeometryReader
            {
                geometry in
                let hasBrowser = revisit != .recent
                let browserAllowance: CGFloat = hasBrowser ? 128 : 0
                let selectorAllowance: CGFloat = revisit == nil ? 60 : 0
                // Keep the browser above the toolbar when the tab extends beneath its safe-area inset.
                let bottomClearance = geometry.safeAreaInsets.bottom + 5
                let headerLimit = max(0, geometry.size.height - bottomClearance - 40 - browserAllowance - selectorAllowance - 16)
                VStack(alignment: .leading, spacing: 16)
                {

                    ScrollView(.vertical)
                    {

                        activityHeader
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self)
                            {
                                $0.size.height
                            }
                            action:
                            {
                                activityHeaderHeight = $0
                            }
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(activityHeaderHeight > 0 ? activityHeaderHeight : headerLimit, headerLimit))

                    if revisit == nil
                    {

                        focusHeading
                    }

                    if hasBrowser
                    {

                        ScrollView(.vertical)
                        {

                            activityBrowserContents
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .modifier(TodayPanelSurface())
                        .accessibilityIdentifier("activity.browser.contents")
                        .id(focus)
                    }
                    else
                    {

                        Spacer(minLength: 0)
                    }
                }
                .padding(20)
                .padding(.bottom, bottomClearance)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .id(revisit)
        }

        .onAppear
        {
            focusLabelLibrary = LabelLibraryStore.load()
        }
        .onChange(of: revisit, initial: true)
        {
            _, choice in
            if choice != nil
            {
                query = "";
                showsSearch = false;
                focus = .saved
            }

        }
        .onChange(of: focus)
        {
            _, value in
            if value == .labels && selectedFocusLabel == nil
            {
                selectedLabelID = availableFocusLabels.first?.id
            }

        }
        .onChange(of: availableFocusLabels)
        {
            _, labels in
            if !labels.contains(where:
                {
                    $0.id == selectedLabelID
                })
            {
                selectedLabelID = labels.first?.id
            }

        }
        .confirmationDialog("Clear recent history?", isPresented: $confirmsClear, titleVisibility: .visible)
        {

            Button("Clear recent history", role: .destructive)
            {
                ActivityRecentStore.clear()
            }

        }
        message:
        {

            Text("Removes recent shortcuts from Activity and Plans. Your cards, notes, and Saved items stay intact.")
        }
        .fullScreenCover(item: $historicalTarget)
        {
            result in
            if let week = result.week
            {

                PlanningCalendarWeekView(
                    week: week, initialDayID: result.list.id, initialCardID: result.card.id,
                    onLeaveForHome:
                    {
                        historicalTarget = nil
                    })
            }
            else if let collection = collections.first(where:
                {
                    $0.id == result.item.collectionID && $0.isActive
                })
            {

                PlanningSearchLibraryView(
                    collection: collection, initialListID: result.list.id, initialCardID: result.card.id,
                    onLeaveForHome:
                    {
                        historicalTarget = nil
                    })
            }

        }

        .confirmationDialog(
                        "Delete \(deletingBoard?.title ?? "collection")?",
                        isPresented: Binding(
                            get:
                            {
                                deletingBoard != nil
                            }, set:
                            {
                                if !$0
                                {
                                    deletingBoard = nil
                                }

                            }
                        ), titleVisibility: .visible
        )
        {

            Button("Delete \(deletingBoard?.kind.rawValue ?? "item")", role: .destructive)
            {

                if let deletingBoard
                {  /* Archived collection awaiting permanent deletion */


                    _ = onDeleteBoard(deletingBoard.id)
                }


                deletingBoard = nil
            }


            Button("Cancel", role: .cancel)
            {
                deletingBoard = nil
            }

        }
        message:
        {

            Text(
                                    "Permanently deletes this retained collection, active and archived lists/cards, and bookmarks. This cannot be undone."
            )
        }

        .confirmationDialog(
                        "Delete \(deletingCard?.word ?? "card")?",
                        isPresented: Binding(
                            get:
                            {
                                deletingCard != nil
                            }, set:
                            {
                                if !$0
                                {
                                    deletingCard = nil
                                }

                            }
                        ), titleVisibility: .visible
        )
        {

            Button("Delete Card", role: .destructive)
            {

                if let deletingCard
                {  /* Saved Week card awaiting permanent deletion */


                    _ = onDeleteCard(deletingCard.id)
                }


                deletingCard = nil
            }


            Button("Cancel", role: .cancel)
            {
                deletingCard = nil
            }

        }
        message:
        {

            Text("Permanently deletes the card and its bookmark from Week. This cannot be undone.")
        }

        .sheet(item: $inspectingBoard)
        {
            board in
            ArchivedCollectionContentsView(
                collection: Binding(
                    get:
                    {
                        collections.first
                        {
                            $0.id == board.id
                        }
                        ?? board
                    },
                    set:
                    {
                        updated in
                        guard
                        let index = collections.firstIndex(
                            where:
                            {  /* Position of the archived collection to mutate */


                                $0.id == updated.id
                            })
                        else
                        {

                            return
                        }

                        do
                        {


                            var snapshot = collections /* Directory snapshot saved before publishing archive changes */
                            snapshot[index] = updated
                            try PersonalCollectionStore.saveChecked(snapshot)
                            collections = snapshot
                        }
                        catch
                        {

                            DatabaseActivity.shared.report(
                                                                                    "Could not delete archived content: \(error.localizedDescription) It has been retained."
                            )
                        }

                    }
                ),
                onDeleteBoard:
                {
                    onDeleteBoard(board.id)
                },
                onRestoreBoard:
                {
                    onRestoreBoard(board.id)
                }
            )
            .databaseActivityOverlay()
        }

    }

}
