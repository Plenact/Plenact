// --------------------------------------------------------------------------------------------------
// @file       WorkspaceNavigation.swift
// @brief      Workspace destination identities and direct List navigation
// @details    Resolves canonical owners and coordinates primary destinations while preserving
//             caller-specific return routes.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Identifies a primary destination in the application tab bar
///
/// @section    Purpose
///     Keep tab selection explicit and type-safe
///
/// @note   Add cases only when the corresponding application view is implemented
///
enum AppDestination: Hashable
{


    case today  /* Today's planning entry point             */
    case board  /* Complete kanban workspace                */
    case lists  /* Library of Week and personal collections */
    case saved  /* Device-local saved cards                 */
}


///
/// Identifies the operation shown by the Today list picker
///
/// @section    Purpose
///     Distinguish choosing today's plan from browsing directly to a board list
///
/// @note   Both picker modes operate on existing board lists
///
enum TodayListPickerMode: String, Identifiable
{


    case chooseToday  /* Set the selected list as today's plan */
    case browseAll    /* Open a selected list on the Board     */

    ///
    /// @fcn        TodayListPickerMode.id
    /// @brief      Return the stable identity for picker presentation
    /// @details    Uses the enum raw value so SwiftUI can identify the active sheet
    ///
    /// @return     (String) picker-mode raw value
    /// @post       No presentation or stored state is changed
    ///
    var id: String
    {
        rawValue
    }  /* Stable tab-selection identity */


    ///
    /// @fcn        TodayListPickerMode.title
    /// @brief      Return the user-facing title for the picker mode
    /// @details    Keeps the sheet heading aligned with the action being performed
    ///
    /// @return     (String) heading for choosing today's list or browsing Board lists
    /// @post       No selection is changed
    ///
    var title: String
    {  /* User-facing list-picker title */

        switch self
        {


        case .chooseToday:
                    "Choose today's list"
        case .browseAll:
                    "Board lists"
        }

    }

}


///
/// Resolves a valid default destination for the Today screen
///
/// @section    Purpose
///     Keep initial list-choice precedence independent from view construction
///
enum TodayListSelection
{


    ///
    /// @fcn        TodayListSelection.currentDayList(in:date:calendar:)
    /// @brief      Resolve the active Week list for the supplied local day
    /// @details    Matches canonical weekday titles without consulting manual Today preferences.
    ///             Missing, archived, renamed, or ambiguous weekday lists produce no focus.
    ///
    /// @param[in]  lists     Canonical Week list records
    /// @param[in]  date      Date whose local weekday is resolved
    /// @param[in]  calendar  Calendar and time zone used to determine the weekday
    ///
    /// @return     (KanbanList?) unique active weekday list, or nil when unavailable
    ///
    static func currentDayList(in lists: [KanbanList], date: Date, calendar: Calendar = .current) -> KanbanList?
    {


        let title = weekdayTitle(for: date, calendar: calendar) /* List title matching the requested day */

        let matches = lists.filter
        {  /* Active lists matching the weekday */


            !$0.isArchived
            && $0.title.trimmingCharacters(in: .whitespacesAndNewlines)

            .caseInsensitiveCompare(title) == .orderedSame
        }


        return matches.count == 1 ? matches.first : nil
    }


    ///
    /// @fcn        TodayListSelection.ensureCurrentDayList(in:date:calendar:)
    /// @brief      Find today's active Week list or append a new blank weekday list
    /// @details    Preserves every supplied active and archived list, reserving a fresh ID across
    ///             both partitions when the real-world weekday has no active matching title
    ///
    /// @param[in]  lists     Active and archived Week lists
    /// @param[in]  date      Date whose local weekday is required
    /// @param[in]  calendar  Calendar and time zone used to determine the weekday
    ///
    /// @return     Updated complete list snapshot and the active weekday list
    ///
    /// @post       Existing list and card records remain unchanged
    ///
    static func ensureCurrentDayList(
        lists: [KanbanList],
        date: Date = .now,
        calendar: Calendar = .current
    ) -> (lists: [KanbanList], dayList: KanbanList)
    {


        let title = weekdayTitle(for: date, calendar: calendar) /* Required weekday list title */

        if let existing = lists.first(where:
            {

                !$0.isArchived
                && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(title)
                == .orderedSame
            })
        {


            return (lists, existing)
        }


        let nextID = (lists.map(\.id).max() ?? -1) + 1 /* Fresh ID reserved across active and archived lists */
        let dayList = KanbanList(
            id: nextID, title: title, cards: []) /* New empty list for the actual weekday              */

        return (lists + [dayList], dayList)
    }


    ///
    /// @fcn        TodayListSelection.weekdayTitle(for:calendar:)
    /// @brief      Resolve the canonical weekday title for a local calendar date
    /// @details    Uses Calendar's weekday component so local time zone and midnight determine the day
    /// @param[in]  date      Date whose weekday title is needed
    /// @param[in]  calendar  Calendar and time zone used to determine the weekday
    /// @return     (String) canonical weekday list title
    ///
    private static func weekdayTitle(for date: Date, calendar: Calendar) -> String
    {


        let weekdays = [
                        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ] /* Calendar-indexed weekday names */
        return weekdays[calendar.component(.weekday, from: date) - 1]
    }

}


///
/// Persists the most recently viewed Week list identity
///
/// @section    Purpose
///     Reuse a valid destination for subsequent card creation
///
enum LastViewedListStore
{


    private static let key = "Plenact.LastViewedList.v1" /* Versioned last-viewed-list preference key */


    ///
    /// @fcn        LastViewedListStore.load(from:)
    /// @brief      Read the most recently viewed Week list identity
    /// @details    Uses an injectable preferences store to support isolated persistence tests
    ///
    /// @param[in]  defaults  Preferences containing the last-viewed key
    ///
    /// @return     (Int?) stored integer ID, or nil for a missing or incompatible value
    ///
    /// @post       No preferences are changed or list existence validated
    ///
    static func load(from defaults: UserDefaults = .standard) -> Int?
    {


        defaults.object(forKey: key) as? Int
    }


    ///
    /// @fcn        LastViewedListStore.save(_:to:)
    /// @brief      Remember the most recently viewed Week list
    /// @details    Stores the supplied identity without changing the list or validating its
    ///             existence
    ///
    /// @param[in]  listID    List identity to remember
    /// @param[in]  defaults  Preferences receiving the last-viewed key
    ///
    /// @return     (Void) replaces the stored list ID
    ///
    static func save(_ listID: Int, to defaults: UserDefaults = .standard)
    {


        defaults.set(listID, forKey: key)
    }


    ///
    /// @fcn        LastViewedListStore.resolve(in:fallback:from:)
    /// @brief      Choose an existing list for a new-card destination
    /// @details    Uses the stored last-viewed list when present in the supplied collection,
    ///             otherwise a valid fallback, then the first list
    ///
    /// @param[in]  lists     Available destination lists
    /// @param[in]  fallback  Optional preferred ID when the saved ID is unavailable
    /// @param[in]  defaults  Preferences supplying the last-viewed ID
    ///
    /// @return     (Int?) existing destination ID, or nil for an empty collection
    ///
    /// @post       Preferences and list order are unchanged
    ///
    static func resolve(in lists: [KanbanList], fallback: Int? = nil, from defaults: UserDefaults = .standard) -> Int?
    {


        if let lastViewed = load(from: defaults),
        lists.contains(where:
            {  /* Remembered new-card destination */


                $0.id == lastViewed
            })
        {

            return lastViewed
        }


        if let fallback,
        lists.contains(where:
            {  /* Alternate new-card destination */


                $0.id == fallback
            })
        {

            return fallback
        }


        return lists.first?.id
    }

}


// Shared owner-qualified browsing prevents card/list IDs on different boards from colliding.


///
/// Identifies a workspace List by owner and local ID
///
/// @section    Purpose
///     Persists a composite reference so equal list IDs in different Boards or calendar Weeks
///     remain distinct.
///
struct WorkspaceListReference: Hashable, Codable, Identifiable
{


    let ownerID: UUID
    let listID:  Int
    var id:      String
    {
            "\(ownerID):\(listID)"
    }

}


///
/// Resolves a workspace List reference to its owner
///
/// @section    Purpose
///     Carries the live collection and List used by shortcut and destination pickers.
///
struct WorkspaceListDestination: Identifiable
{


    let owner:     PersonalCollection
    let list:      KanbanList
    var reference: WorkspaceListReference
    {
        WorkspaceListReference(ownerID: owner.id, listID: list.id)
    }

    var id: String
    {
        reference.id
    }

}


///
/// Groups workspace matches for one label
///
/// @section    Purpose
///     Retains the label catalog entry alongside owner-qualified Card matches for Library browsing.
///
struct WorkspaceLabelUsage: Identifiable
{


    let label:   KanbanLabel
    let matches: [PlanningSearchResult]
    var id:      String
    {
        label.id
    }

}


///
/// Builds common workspace browsing projections
///
/// @section    Purpose
///     Combines calendar and personal owners and derives available Lists and label usage without
///     writing content.
///
enum WorkspaceBrowseIndex
{


    ///
    /// @fcn        WorkspaceBrowseIndex.owners
    /// @brief      Combine active calendar and Library owners for browsing
    /// @details    Builds the common owner projection used by list and label pickers without persisting changes.
    ///
    /// @param[in]  document  Retained document containing the operation's current workspace records
    /// @param[in]  library   Personal owners to combine with calendar-backed weeks
    ///
    /// @return     ([PersonalCollection]) active browsable calendar and personal collection owners
    ///
    static func owners(document: PlanningCalendarDocument?, library: [PersonalCollection]) -> [PersonalCollection]
    {

        (document?.weeks.map
            {
                week in
                var owner = week.collection
                owner.title = (week.startKey == document?.currentWeekKey ? "This Week · " : "") + week.rangeTitle
                return owner
            }
            ?? []) + library.filter(\.isActive)
    }


    ///
    /// @fcn        WorkspaceBrowseIndex.lists
    /// @brief      Build owner-qualified list destinations
    /// @details    Projects browsable owner lists into references that retain both collection and list identity.
    ///
    /// @param[in]  owners  Canonical collection owners participating in the operation
    ///
    /// @return     ([WorkspaceListDestination]) owner-qualified active list destinations
    ///
    static func lists(in owners: [PersonalCollection]) -> [WorkspaceListDestination]
    {

        owners.filter(\.isActive).flatMap
        {
            owner in
            owner.lists.filter
            {
                !$0.isArchived
            } .map
            {
                WorkspaceListDestination(owner: owner, list: $0)
            }

        }

    }


    ///
    /// @fcn        WorkspaceBrowseIndex.labels
    /// @brief      Collect label usage across browsable workspace content
    /// @details    Resolves card label IDs through the supplied catalog and retains owner context for each usage
    ///             destination.
    ///
    /// @param[in]  owners   Canonical collection owners participating in the operation
    /// @param[in]  catalog  Catalog used to resolve the referenced display metadata
    ///
    /// @return     ([WorkspaceLabelUsage]) resolved label-usage groups and their workspace destinations
    ///
    static func labels(in owners: [PersonalCollection], catalog: LabelLibrary) -> [WorkspaceLabelUsage]
    {

        var matches: [String: [PlanningSearchResult]] = [:]
        for destination in lists(in: owners)
        {

            for card in destination.list.cards where !card.isSectionDivider
            {

                let result = PlanningSearchResult(
                    weekKey: nil, collectionID: destination.owner.id,
                    collectionTitle: destination.owner.title, listID: destination.list.id,
                    listTitle: destination.list.title, card: card)
                for labelID in Set(card.labelIDs)
                {
                    matches[labelID, default: []].append(result)
                }

            }

        }

        return catalog.labels.compactMap
        {
            label in
            guard let cards = matches[label.id], !cards.isEmpty else
            {
                return nil
            }

            return WorkspaceLabelUsage(label: label, matches: cards)
        }

    }

}


///
/// Resolves and opens a pinned workspace List
///
/// @section    Purpose
///     Chooses the dated Week or personal owner associated with the reference and preserves the
///     caller's return destination.
///
struct WorkspacePinnedListView: View
{


    let reference: WorkspaceListReference
    var returnDestinationTitle = "Today"
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    var body: some View
    {

        if let week = access?.document.weeks.first(where:
            {
                $0.id == reference.ownerID
            }),
        week.collection.lists.contains(where:
            {
                $0.id == reference.listID && !$0.isArchived
            })
        {

            PinnedListDayContent(
                collection: week.collection, reference: reference,
                date: week.dayListIDs.first(where:
                    {
                        $0.value == reference.listID
                    }).flatMap
                {

                    PlanningDate.date($0.key)
                },
                week: week, onClose:
                {
                    dismiss()
                }, returnDestinationTitle: returnDestinationTitle)
        }
        else if let collection = access?.library.first(where:
            {
                $0.id == reference.ownerID && $0.isActive
            }),
        collection.lists.contains(where:
            {
                $0.id == reference.listID && !$0.isArchived
            })
        {

            PinnedListDayContent(
                collection: collection, reference: reference, date: nil, week: nil, onClose:
                {
                    dismiss()
                },
                returnDestinationTitle: returnDestinationTitle)
        }
        else
        {

            NavigationStack
            {

                Text("This list is archived or no longer available.").foregroundStyle(.secondary).padding()
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

            }

        }

    }

}


///
/// Hosts editable content for a resolved pinned List
///
/// @section    Purpose
///     Retains the owner snapshot and routes checked changes through calendar access, including
///     rollback when a save fails.
///
struct PinnedListDayContent: View
{


    @State var collection: PersonalCollection
    let reference:         WorkspaceListReference
    let date:              Date?
    let week:              DatedPlanningWeek?
    let onClose:           () -> Void
    var returnDestinationTitle = "Today"
    @Environment(\.planningCalendarAccess) private var access
    @State private var labels = LabelLibraryStore.load()
    @State private var reverting = false


    ///
    /// @fcn        PinnedListDayContent.save
    /// @brief      Save edits to a pinned list through its canonical owner
    /// @details    Uses calendar-week or personal-collection access as appropriate and returns false when the owner
    ///             cannot be saved.
    ///
    /// @param[in]  collection  Personal collection supplying the owner context
    ///
    /// @return     (Bool) true after the canonical owner accepts the edited collection; false otherwise
    ///
    private func save(_ collection: PersonalCollection) -> Bool
    {

        if var week
        {

            week.collection = collection
            return access?.saveWeek(week) == true
        }

        return access?.saveLibrary(collection) == true
    }

    var body: some View
    {

        TodayListDetailView(
            lists: $collection.lists.activeLists, reservedLists: collection.lists.filter(\.isArchived),
            labelLibrary: $labels, savedCardIDs: $collection.savedCardIDs, listID: reference.listID,
            currentUserName: "You", onClose: onClose,
            onOpenWeek:
            {

                if var week
                {
                    week.collection = collection;
                    access?.openWeek(week)
                }
                ;
                onClose()
            },
            onPermanentDelete:
            {
                cardID in
                var updated = collection
                BoardContentDeletion.card(cardID, in: &updated.lists, savedCardIDs: &updated.savedCardIDs)
                guard save(updated) else
                {
                    return false
                }

                collection = updated;
                return true
            }, boardAppearance: collection.boardAppearance, returnDestinationTitle: returnDestinationTitle,
            boardViewActionTitle: week == nil ? "Back to \(returnDestinationTitle)" : "Switch to Week View",
            representedDate: date
        )
        .environment(\.cardMovementSource, collection.id)
        .modifier(OwnerImportanceControls(ownerID: collection.id))
        .onChange(of: collection)
        {
            old, updated in
            if reverting
            {
                reverting = false;
                return
            }

            if !save(updated)
            {
                reverting = true;
                collection = old
            }

        }
        .onChange(of: access?.document)
        {
            _, document in
            if let next = document?.weeks.first(where:
                {
                    $0.id == reference.ownerID
                })?.collection, next != collection
            {

                collection = next
            }

        }
        .onChange(of: access?.library)
        {
            _, library in
            if let next = library?.first(where:
                {
                    $0.id == reference.ownerID
                }), next != collection
            {

                collection = next
            }

        }
        .databaseActivityOverlay()
    }

}
