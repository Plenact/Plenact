// --------------------------------------------------------------------------------------------------
// @file       CalendarNavigation.swift
// @brief      Dated owner access and caller-specific return routes
// @details    Supplies checked owner callbacks, resolves targeted Lists or Cards, and preserves
//             direct-detail return context.
//
// --------------------------------------------------------------------------------------------------
import CryptoKit
import SwiftUI


///
/// Exposes calendar and Library operations to descendants
///
/// @section    Purpose
///     Supplies current owner snapshots and checked save, navigation, review, and movement
///     callbacks from the workspace root.
///
struct PlanningCalendarAccess
{


    var document:        PlanningCalendarDocument
    var library:         [PersonalCollection]
    var saveWeek:        (DatedPlanningWeek) -> Bool
    var openCurrentWeek: () -> Void
    var openToday:       () -> Void
    var openLibraryCard: (PersonalSavedCardTarget) -> Void
    var saveLibrary:     (PersonalCollection) -> Bool
    var applyWeeklyReview:
    ((PlanningSearchResult, DailyReviewAction, WeeklyReviewRecord, WeeklyReviewRecord?) -> WeeklyReviewRecord?)? =
    nil
    var applyDailyReview: ((PlanningSearchResult, DailyReviewAction, DailyPlan, DailyPlan?) -> DailyPlan?)? = nil
    var moveForDailyPlan: ((PlanningSearchResult, WorkspaceListReference) -> PlanningSearchResult?)? = nil
    var setFirstWeekday:  (Int) -> Bool =
    {
        _ in
        false
    }

    var openWeek: (DatedPlanningWeek) -> Void =
    {
        _ in
    }

    var moveList:         ((Int, UUID, UUID?) -> Bool)? = nil
    var openWeekOnDay:    ((DatedPlanningWeek, Date) -> Void)? = nil
    var saveExampleWeek:  ((DatedPlanningWeek, Set<Int>) -> Bool)? = nil
    var allRetainedLists: [KanbanList]
    {
        document.weeks.flatMap
        {
            $0.collection.lists
        }
        + library.flatMap(\.lists)
    }

    var searchableItems: [PlanningSearchResult]
    {

        document.weeks.flatMap
        {
            week in
            week.collection.lists.filter
            {
                !$0.isArchived
            } .flatMap
            {
                list in
                list.cards.filter
                {
                    !$0.isSectionDivider
                } .map
                {

                    PlanningSearchResult(
                        weekKey: week.startKey, collectionID: week.id, collectionTitle: week.rangeTitle,
                        listID: list.id, listTitle: list.title, card: $0)
                }

            }

        }

        + library.filter(\.isActive).flatMap
        {
            collection in
            collection.lists.filter
            {
                !$0.isArchived
            } .flatMap
            {
                list in
                list.cards.filter
                {
                    !$0.isSectionDivider
                } .map
                {

                    PlanningSearchResult(
                        weekKey: nil, collectionID: collection.id, collectionTitle: collection.title,
                        listID: list.id, listTitle: list.title, card: $0)
                }

            }

        }

    }

}


///
/// Defines optional workspace access in the environment
///
/// @section    Purpose
///     Uses nil by default so detached views cannot assume a writable calendar owner.
///
struct PlanningCalendarAccessKey: EnvironmentKey
{


    static let defaultValue: PlanningCalendarAccess? = nil
}


///
/// Defines the currently displayed Week environment value
///
/// @section    Purpose
///     Defaults to no Week key so consumers distinguish general workspace contexts from a dated
///     Board.
///
struct PlanningDisplayedWeekKey: EnvironmentKey
{


    static let defaultValue: String? = nil
}


///
/// Provides shared calendar access and displayed Week context
///
/// @section    Purpose
///     Stores injected owner callbacks separately from the currently browsed Week key.
///
extension EnvironmentValues
{


    var planningDisplayedWeekKey: String?
    {

        get
        {
            self[PlanningDisplayedWeekKey.self]
        }

        set
        {
            self[PlanningDisplayedWeekKey.self] = newValue
        }

    }

    var planningCalendarAccess: PlanningCalendarAccess?
    {

        get
        {
            self[PlanningCalendarAccessKey.self]
        }

        set
        {
            self[PlanningCalendarAccessKey.self] = newValue
        }

    }

}


///
/// Carries a selected Week and optional item destination
///
/// @section    Purpose
///     Keeps Week, Day, and Card targeting together for one identifiable presentation route.
///
struct PlanningWeekRoute: Identifiable
{


    var week:   DatedPlanningWeek
    var dayID:  Int? = nil
    var cardID: Int? = nil
    var id:     UUID
    {
        week.id
    }

}


///
/// Hosts a dated Week with checked owner-level saving
///
/// @section    Purpose
///     Supports optional Day and Card targeting while coordinating shared navigation and the
///     caller's home exit.
///
struct PlanningCalendarWeekView: View
{


    @State var week:    DatedPlanningWeek
    let initialDayID:   Int?
    let initialCardID:  Int?
    let onLeaveForHome: () -> Void
    var isWeekTab = false
    var initialBoardListID: Int? = nil
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var targetListID: Int?
    @State private var targetCardID: Int?
    @State private var didOpenInitialTarget = false
    @State private var showsDay = false
    @State private var dayID: Int?
    @State private var isRevertingEdit = false
    @State private var labels = LabelLibraryStore.load()
    private var isStored: Bool
    {
        access?.document.weeks.contains
        {
            $0.startKey == week.startKey
        }
        == true
    }

    private var isCurrent: Bool
    {
        week.startKey == access?.document.currentWeekKey
    }

    var body: some View
    {

        ContentView(
            lists: $week.collection.lists.activeLists, archivedLists: $week.collection.lists.archivedLists,
            boardTargetListID: $targetListID, boardTargetCardID: $targetCardID,
            savedCardIDs: $week.collection.savedCardIDs,
            boardTitle: isWeekTab ? "Plenact" : (isCurrent ? "This Week" : "Week"),
            boardSubtitle: (isWeekTab ? "Week • " : "") + week.compactRangeTitle,
            allowsAddingLists: false, onClose: isWeekTab ? nil :
            {
                dismiss()
            },
            onCommitDeletion:
            {
                lists, saved in
                var next = week;
                next.collection.lists = lists;
                next.collection.savedCardIDs = saved
                guard access?.saveWeek(next) == true else
                {
                    throw CocoaError(.fileWriteUnknown)
                }

                week = next
            },
            onListsChanged:
            {
                _ in
            },
            retainedAttachmentLists:
            {
                access?.allRetainedLists ?? []
            },
            personalCollectionID: week.id,
            boardAppearance: $week.collection.boardAppearance
        )
        .safeAreaInset(edge: .bottom)
        {

            if !isWeekTab
            {

                HStack
                {

                    if !isStored
                    {

                        Button("Save empty week", systemImage: "square.and.arrow.down")
                        {

                            var next = week;
                            next.explicitlySaved = true
                            if access?.saveWeek(next) == true
                            {
                                week = next
                            }

                        }

                    }
                    else
                    {

                        Text(week.rangeTitle).font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()
                    Button("This week", systemImage: "arrow.uturn.backward")
                    {

                        access?.openCurrentWeek();
                        dismiss();
                        onLeaveForHome()
                    }

                }
                .padding(12)
                .background(.regularMaterial)
            }

        }
        .environment(\.planningDirectItemReturn, initialCardID == nil ? nil :
            {
                dismiss()
            })
        .environment(\.planningDisplayedWeekKey, week.startKey)
        .environment(\.cardMovementSource, week.id)
        .modifier(OwnerImportanceControls(ownerID: week.id))
        .environment(
            \.planningHomeExit,
            {

                dismiss();
                onLeaveForHome()
            }
        )
        .task
        {

            guard !didOpenInitialTarget else
            {
                return
            }

            didOpenInitialTarget = true
            if !isStored, let access
            {

                do
                {

                    let date = PlanningDate.date(week.startKey, calendar: access.document.calendar)!
                    let prepared = try PlanningRoutineStore.newWeek(for: date, calendar: access.document.calendar)
                    guard access.saveWeek(prepared) else
                    {
                        dismiss();
                        return
                    }

                    isRevertingEdit = true
                    week = prepared
                }
                catch
                {

                    DatabaseActivity.shared.report(
                                                            "Could not create this week from its template. Your saved plans were retained.")
                    dismiss();
                    return
                }

            }

            if let initialBoardListID
            {
                targetListID = initialBoardListID
            }

            if let initialDayID
            {

                if let initialCardID
                {

                    targetListID = initialDayID;
                    targetCardID = initialCardID
                }
                else
                {

                    dayID = initialDayID;
                    showsDay = true
                }

            }

        }
        .onChange(of: initialBoardListID)
        {
            _, id in
            if let id
            {
                targetListID = id;
                targetCardID = nil
            }

        }
        .onChange(of: week)
        {
            old, updated in
            guard old != updated else
            {
                return
            }

            // Merely opening a draft never writes; an actual edit saves the week.
            if isRevertingEdit
            {
                isRevertingEdit = false;
                return
            }

            if access?.saveWeek(updated) != true
            {
                isRevertingEdit = true;
                week = old
            }

        }
        .onChange(of: access?.document)
        {
            _, document in
            if let updated = document?.weeks.first(where:
                {
                    $0.startKey == week.startKey
                }), updated != week
            {

                week = updated
            }

        }
        .fullScreenCover(isPresented: $showsDay)
        {

            if let dayID
            {

                TodayListDetailView(
                    lists: $week.collection.lists.activeLists,
                    reservedLists: week.collection.lists.filter(\.isArchived), labelLibrary: $labels,
                    savedCardIDs: $week.collection.savedCardIDs, listID: dayID, currentUserName: "You",
                    onClose:
                    {

                        showsDay = false
                        if initialDayID != nil && initialCardID == nil
                        {
                            dismiss()
                        }

                    },
                    onOpenWeek:
                    {

                        showsDay = false;
                        targetListID = dayID
                    },
                    onPermanentDelete:
                    {
                        cardID in
                        var next = week
                        BoardContentDeletion.card(
                            cardID, in: &next.collection.lists, savedCardIDs: &next.collection.savedCardIDs)
                        guard access?.saveWeek(next) == true else
                        {
                            return false
                        }

                        week = next;
                        return true
                    }, boardAppearance: week.collection.boardAppearance,
                    returnDestinationTitle: "Calendar", boardViewActionTitle: "Switch to this week's view",
                    representedDate: week.dayListIDs.first(where:
                        {
                            $0.value == dayID
                        }).flatMap
                    {

                        PlanningDate.date($0.key)
                    }
                )
                .environment(\.cardMovementSource, week.id)
                .modifier(OwnerImportanceControls(ownerID: week.id))
            }

        }

    }

}


///
/// Defines an optional direct-item return action
///
/// @section    Purpose
///     Allows a detail opened from Activity or another direct destination to return to its caller
///     instead of opening the source List.
///
struct PlanningDirectItemReturnKey: EnvironmentKey
{


    static let defaultValue: (() -> Void)? = nil
}


///
/// Exposes direct-detail return navigation through the environment
///
/// @section    Purpose
///     Keeps the caller's return action available to nested Card presentation without changing
///     source ownership.
///
extension EnvironmentValues
{


    var planningDirectItemReturn: (() -> Void)?
    {

        get
        {
            self[PlanningDirectItemReturnKey.self]
        }

        set
        {
            self[PlanningDirectItemReturnKey.self] = newValue
        }

    }

}


///
/// Defines an optional return-to-home navigation action
///
/// @section    Purpose
///     Uses an absent default so nested calendar screens leave their outer navigation unchanged
///     unless an owner supplies an exit.
///
struct PlanningHomeExitKey: EnvironmentKey
{


    static let defaultValue: (() -> Void)? = nil
}


///
/// Exposes the workspace home-exit callback
///
/// @section    Purpose
///     Allows nested destinations to request the caller's established home route without owning tab
///     state.
///
extension EnvironmentValues
{


    var planningHomeExit: (() -> Void)?
    {

        get
        {
            self[PlanningHomeExitKey.self]
        }

        set
        {
            self[PlanningHomeExitKey.self] = newValue
        }

    }

}


///
/// Identifies one shared-search navigation request
///
/// @section    Purpose
///     Retains the selected result and its composite identity for destination presentation.
///
struct PlanningSearchRoute: Identifiable
{


    let result: TodaySearchResult
    var id:     String
    {
        result.id
    }

}


///
/// Opens a shared-search result in its personal collection
///
/// @section    Purpose
///     Targets the resolved List and Card and sends checked edits back through injected workspace
///     access, reverting rejected changes.
///
struct PlanningSearchLibraryView: View
{


    @State var collection: PersonalCollection
    let initialListID:     Int
    let initialCardID:     Int?
    let onLeaveForHome:    () -> Void
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var targetListID: Int?
    @State private var targetCardID: Int?
    @State private var isRevertingEdit = false
    @State private var didOpenInitialTarget = false
    var body: some View
    {

        ContentView(
            lists: $collection.lists.activeLists, archivedLists: $collection.lists.archivedLists,
            boardTargetListID: $targetListID, boardTargetCardID: $targetCardID, savedCardIDs: $collection.savedCardIDs,
            boardTitle: collection.title, boardSubtitle: "Plans", allowsAddingLists: collection.kind == .board,
            fillsAvailableListWidth: collection.kind == .list, onClose:
            {
                dismiss()
            },
            onCommitDeletion:
            {
                lists, saved in
                var updated = collection;
                updated.lists = lists;
                updated.savedCardIDs = saved
                guard access?.saveLibrary(updated) == true else
                {
                    throw CocoaError(.fileWriteUnknown)
                }

                collection = updated
            }, onListsChanged:
            {
                _ in
            }, retainedAttachmentLists:
            {
                access?.allRetainedLists ?? []
            },
            personalCollectionID: collection.id, boardAppearance: $collection.boardAppearance
        )
        .environment(\.planningDisplayedWeekKey, nil)
        .environment(\.planningDirectItemReturn, initialCardID == nil ? nil :
            {
                dismiss()
            })
        .environment(
            \.planningHomeExit,
            {

                dismiss();
                onLeaveForHome()
            }
        )
        .task
        {

            guard !didOpenInitialTarget else
            {
                return
            }

            didOpenInitialTarget = true
            targetListID = initialListID;
            targetCardID = initialCardID
        }
        .onChange(of: collection)
        {
            old, next in
            if isRevertingEdit
            {
                isRevertingEdit = false;
                return
            }

            if old != next, access?.saveLibrary(next) != true
            {
                isRevertingEdit = true;
                collection = old
            }

        }
        .onChange(of: access?.library)
        {
            _, library in
            if let next = library?.first(where:
                {
                    $0.id == collection.id
                }), next != collection
            {
                collection = next
            }

        }

    }

}


///
/// Resolves checklist Card links across dated Week ownership
///
/// @section    Purpose
///     Preserves date-qualified references when calendar migration separates Lists that previously
///     shared an owner.
///
struct PlanningChecklistLink: View
{


    let itemID:  UUID
    let cardID:  Int
    let title:   String
    var ownerID: UUID? = nil
    @Environment(\.planningCalendarAccess) private var access
    @State private var showsCard = false
    private var destination: (DatedPlanningWeek, Int)?
    {

        guard let owner = access?.document.checklistLinkWeeks? [itemID] ?? ownerID,
        let week = access?.document.weeks.first(where:
            {
                $0.id == owner
            }),
        let list = week.collection.lists.first(where:
            {
                !$0.isArchived && $0.cards.contains
                {
                    $0.id == cardID
                }

            })
        else
        {
            return nil
        }

        return (week, list.id)
    }

    var body: some View
    {

        Button
        {

            showsCard = true
        }
        label:
        {

            Image(systemName: "link").frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(destination == nil)
        .accessibilityLabel("Open linked card: \(title)")
        .fullScreenCover(isPresented: $showsCard)
        {

            if let (week, listID) = destination
            {

                PlanningCalendarWeekView(
                    week: week, initialDayID: listID, initialCardID: cardID, onLeaveForHome:
                    {
                        showsCard = false
                    })
            }

        }

    }

}


///
/// Resolves a date to an active Day List
///
/// @section    Purpose
///     Combines the normalized date, owning Week, and List ID so retained and unsaved Weeks follow
///     the same navigation rules.
///
struct PlanningDaySelection
{


    let date:   Date
    let week:   DatedPlanningWeek
    let listID: Int


    ///
    /// @fcn        PlanningDaySelection.resolve
    /// @brief      Resolve an active day-list navigation target
    /// @details    Normalizes the day and uses a retained or unsaved week; returns nil if the day mapping does not
    ///             identify an active list.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  document  Retained document containing the operation's current workspace records
    ///
    /// @return     (Self?) normalized date, containing week, and active day-list ID, or nil if mapping fails
    ///
    static func resolve(_ date: Date, document: PlanningCalendarDocument) -> Self?
    {

        let date = document.calendar.startOfDay(for: date)
        let week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: document.calendar)
        guard let id = week.dayListIDs[PlanningDate.key(date, calendar: document.calendar)],
        week.collection.lists.contains(where:
            {
                $0.id == id && !$0.isArchived
            })
        else
        {
            return nil
        }

        return Self(date: date, week: week, listID: id)
    }

}


///
/// Hosts a selected date in one focused Day surface
///
/// @section    Purpose
///     Resolves the correct dated owner and sends checked edits back to that Week while preserving
///     date navigation.
///
struct PlanningSelectedDayView: View
{


    let selection:              PlanningDaySelection
    let currentUserName:        String
    let returnDestinationTitle: String
    let onClose:                () -> Void
    let onSelectDay:            (Date) -> Void
    @State private var week:    DatedPlanningWeek
    @State private var labels = LabelLibraryStore.load()
    @State private var isRevertingEdit = false
    @Environment(\.planningCalendarAccess) private var access


    ///
    /// @fcn        PlanningSelectedDayView.init
    /// @brief      Initialize navigation and editing for a selected calendar day
    /// @details    Retains the resolved selection and return callbacks and seeds the working week from the selection
    ///             snapshot.
    ///
    /// @param[in]  selection               Text selection or resolved navigation selection to retain
    /// @param[in]  currentUserName         Display name used in the selected-day interface
    /// @param[in]  returnDestinationTitle  Accessible title describing the destination reached by Back
    /// @param[in]  onClose                 Action used to leave the selected-day presentation
    /// @param[in]  onSelectDay             Callback for changing the represented calendar day
    ///
    /// @return     (PlanningSelectedDayView) initialized instance
    ///
    init(
        selection: PlanningDaySelection, currentUserName: String, returnDestinationTitle: String,
        onClose: @escaping () -> Void, onSelectDay: @escaping (Date) -> Void
    )
    {

        self.selection = selection
        self.currentUserName = currentUserName
        self.returnDestinationTitle = returnDestinationTitle
        self.onClose = onClose
        self.onSelectDay = onSelectDay
        _week = State(initialValue: selection.week)
    }


    var body: some View
    {

        TodayListDetailView(
            onSelectDay: onSelectDay,
            lists: $week.collection.lists.activeLists,
            reservedLists: week.collection.lists.filter(\.isArchived), labelLibrary: $labels,
            savedCardIDs: $week.collection.savedCardIDs, listID: selection.listID,
            currentUserName: currentUserName, onClose: onClose,
            onOpenWeek:
            {

                access?.openWeek(week);
                onClose()
            },
            onPermanentDelete:
            {
                cardID in
                var next = week
                BoardContentDeletion.card(
                    cardID, in: &next.collection.lists, savedCardIDs: &next.collection.savedCardIDs)
                guard access?.saveWeek(next) == true else
                {
                    return false
                }

                week = next
                return true
            }, boardAppearance: week.collection.boardAppearance,
            returnDestinationTitle: returnDestinationTitle,
            representedDate: selection.date
        )
        .environment(\.cardMovementSource, week.id)
        .modifier(OwnerImportanceControls(ownerID: week.id))
        .environment(\.planningDisplayedWeekKey, week.startKey)
        .task
        {

            guard let access, access.document.week(for: selection.date) == nil else
            {
                return
            }

            do
            {

                let prepared = try PlanningRoutineStore.newWeek(for: selection.date, calendar: access.document.calendar)
                guard access.saveWeek(prepared) else
                {
                    onClose();
                    return
                }

                isRevertingEdit = true
                week = prepared
            }
            catch
            {

                DatabaseActivity.shared.report(
                                                "Could not create this day from its week template. Your saved plans were retained.")
                onClose()
            }

        }
        .onChange(of: week)
        {
            old, updated in
            if isRevertingEdit
            {
                isRevertingEdit = false;
                return
            }

            if access?.saveWeek(updated) != true
            {
                isRevertingEdit = true;
                week = old
            }

        }
        .onChange(of: access?.document)
        {
            _, document in
            if let updated = document?.weeks.first(where:
                {
                    $0.startKey == week.startKey
                }), updated != week
            {

                week = updated
            }

        }

    }

}
