// --------------------------------------------------------------------------------------------------
// @file       ListDetailView.swift
// @brief      Focused Day and personal List presentation
// @details    Renders one canonical List, resolves its dated or personal owner, and saves accepted
//             content through injected workspace access
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Presents one Today list vertically while sharing its cards with the Week Board
///
/// @section    Purpose
///     Provide focused-list capture and card actions against the shared Board snapshot
///
struct TodayListDetailView: View
{
    @Environment(\.accessibilityReduceMotion) private var reduceSummaryMotion
    @State private var daySummaryScrollID = 0
    @State private var canDismissPartiallyVisibleSummary = false
    @State private var daySummaryHeight: CGFloat = 0
    @State private var isDaySummaryDismissalPending: Bool?
    private var shouldDismissDaySummary: Bool
    {
        isDaySummaryDismissalPending ?? autoDismissesDaySummary
    }
    @State private var isDayVisible = false
    var autoDismissesDaySummary = false

    @State private var keyboardDetailPath: [KanbanCard] = []            /* Keyboard detail path     */
    @State private var confirmsCheckmarkReset           = false         /* Confirms checkmark reset */

    @State private var checkmarkReset:     ListCheckmarkReset?                          /* Checkmark reset          */
    @Environment(\.cardMovementSource) private var dayMovementSource                    /* Day movement source      */
    @Environment(\.planningCalendarAccess) private var planningCalendarAccess           /* Planning calendar access */
    @Environment(\.planningHomeExit) private var planningHomeExit                       /* Planning home exit       */
    @State private var showsDaySearch                 = false                           /* Day Search visibility    */
    @State private var guidanceToggleRequest          = 0                               /* Guidance toggle request  */
    @State private var showsDaySelector               = false                           /* Day Selector visibility  */
    @State private var showsWeekSelector = false
    var onSelectDay:                ((Date) -> Void)? = nil                             /* Select day callback      */

    var onOpenSelectedWeek: ((PlanningDaySelection) -> Void)? = nil     /* Switch to the selected date’s Week */

    @State private var focusedViewportMemory: BoardViewportMemory?      /* Focused viewport memory */
    @State private var guidanceFooterVisible: Bool?                     /* Guidance footer visible */
    @State private var selectedDay: PlanningDaySelection?               /* Selected day            */


    @Binding var lists: [KanbanList]    /* Shared local Board snapshot */
    /// Archived lists and cards retained to reserve identities during creation
    let reservedLists:         [KanbanList]     /* Retained lists whose card identities remain unavailable for reuse */
    @Binding var labelLibrary: LabelLibrary     /* Shared reusable label library                                     */
    @Binding var savedCardIDs: Set<Int>         /* Device-local saved cards                                          */

    let listID:            Int                  /* Focused list identity                    */
    let currentUserName:   String               /* Current activity author                  */
    let onClose:           ()    -> Void        /* Return to Today                          */
    let onOpenWeek:        ()    -> Void        /* Open this list in the Week workspace     */
    let onPermanentDelete: (Int) -> Bool        /* Parent's save-first Week deletion result */

    var onRestoreDeletedCard: (([KanbanList], Set<Int>) -> Bool)? = nil

    @Environment(\.layoutDirection) private var headerLayoutDirection                   /* Header layout direction             */
    @AppStorage(BoardAppearance.weekStorageKey) private var weekAppearanceData =        /* Week appearance data                */
        Data()
    var boardAppearance:        BoardAppearance?                               =        /* Board appearance                    */
        nil
    var returnDestinationTitle: String                                         =        /* Return destination title            */
        "Today"
    var boardViewActionTitle:   String                                         =        /* Board view action title             */
        "Switch to Week View"
    var focusesFirstUncheckedTask                                              =        /* Focuses first unchecked task        */
        false
    var representedDate: Date?                                                 =        /* Represented date                    */
        nil
    @State private var didApplyInitialTaskFocus                                =        /* Apply Initial Task Focus completion */
        false


    private var effectiveBoardAppearance: BoardAppearance       /* Resolved Board appearance */
    {
        if let boardAppearance
        {
            return boardAppearance
        }

        if let dayMovementSource
        {
            let owner =                                         /* Owning collection or Week */
            planningCalendarAccess?.document.weeks.first
            {
                $0.id == dayMovementSource
            }?.collection
            ?? planningCalendarAccess?.library.first
            {
                $0.id == dayMovementSource
            }

            return owner?.boardAppearance ?? BoardAppearance()
        }

        return (try? BoardAppearance.decodeWeek(weekAppearanceData)) ?? BoardAppearance()
    }

    @State private var isEditingList                   = false                          /* Editing List state                                */
    @State private var isEditingAppearance             = false                          /* Editing Appearance state                          */
    @State private var showsNewCard                    = false                          /* New Card visibility                               */
    @State private var inlineCaptureDraft              = InlineListCaptureDraft()       /* Inline capture draft                              */
    @State private var editMode:     EditMode          = .inactive                      /* Whether Today rows expose native reorder controls */
    @State private var cardDragToken                   = UUID().uuidString              /* Card drag token                                   */
    @State private var cardFrames:       [Int: CGRect] = [:]                            /* Card frames                                       */
    @State private var cardViewport:     CGRect        = .zero                          /* Card viewport                                     */

    @State private var swipeDeletion: SwipeDeletion?
    @GestureState private var swipeOffset: (id: Int, x: CGFloat)?
    @State private var slidingOutCardID: Int?

    private struct SwipeDeletion
    {
        let token = UUID()
        let card: KanbanCard
        let listID: Int
        let index: Int
        let previousID: Int?
        let nextID: Int?
        let wasBookmarked: Bool
        let media: Set<String>
        let cleanMedia: ((Set<String>) -> Void)?
    }
    @State private var draggedCardID:    Int?                   /* Dragged card ID    */
    @State private var cardDragLocation: CGPoint?               /* Card drag location */
    @Environment(\.scenePhase) private var scenePhase           /* Scene phase        */

    private var cardDropTarget: BoardCardDropTarget?    /* Card drop target */
    {
        guard let cardID = draggedCardID, let point = cardDragLocation, let focusedList else
        {
            return nil
        }

        return BoardCardMovement.target(
            for: cardID, at: point, viewport: cardViewport,
            lists: [focusedList], listFrames: [listID: cardViewport], cardFrames: cardFrames
        )
    }


    private var cardDropSurface: some View      /* Card drop surface */
    {
        BoardCardDropSurface(
            token: cardDragToken, isEnabled: editMode != .active,
            onChanged:
            {
                cardDragLocation = $0
            },
            onDrop:
            {
                point in
                finishCardDrag(at: point)
            }
        )
    }


    ///
    /// @fcn        TodayListDetailView.insertionMarker
    /// @brief      Render the current drag insertion position
    /// @details    Shows a decorative accent line only for the matching before-card target and excludes it from
    ///             interaction and accessibility
    ///
    /// @param[in]  cardID  Numeric card identity within its owner
    ///
    /// @return     (some View) the current drag insertion position
    ///
    private func insertionMarker(before cardID: Int?) -> some View
    {
        Group
        {
            if let target = cardDropTarget, target.beforeCardID == cardID
            {
                RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(height: 4)
                .padding(.horizontal, 8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }


    ///
    /// @fcn        TodayListDetailView.clearCardDrag
    /// @brief      Clear the active card drag identity and location
    /// @details    Resets both drag fields so subsequent gestures begin without a stale source or pointer position
    ///
    /// @return     (Void) no return value
    ///
    private func clearCardDrag()
    {
        draggedCardID = nil
        cardDragLocation = nil
    }


    ///
    /// @fcn        TodayListDetailView.cardDragSource
    /// @brief      Attach normal press-and-hold dragging to a card
    /// @details    Installs the drag source outside Edit mode and scopes begin, move, and end callbacks to the active
    ///             card identity
    ///
    /// @param[in]  cardID  Numeric card identity within its owner
    ///
    /// @return     (some View) attach normal press-and-hold dragging to a card
    ///
    private func cardDragSource(for cardID: Int) -> some View
    {
        Group
        {
            if editMode != .active
            {
                BoardCardDragSource(
                    token: cardDragToken,
                    onBegan:
                    {
                        point in
                        guard draggedCardID == nil else
                        {
                            return
                        }

                        draggedCardID = cardID
                        cardDragLocation = point
                    },
                    onChanged:
                    {
                        point in
                        if draggedCardID == cardID
                        {
                            cardDragLocation = point
                        }
                    },
                    onEnded:
                    {
                        if draggedCardID == cardID
                        {
                            clearCardDrag()
                        }
                    },
                    onDirectDrop: finishCardDrag
                )
            }
        }
    }


    ///
    /// @fcn        TodayListDetailView.finishCardDrag
    /// @brief      Resolve and apply the final card-drop location
    /// @details    Always clears drag state, rejects missing sources or targets, and reports movement errors instead
    ///             of claiming success
    ///
    /// @param[in]  point  Touch or drop location in the operation's coordinate space
    ///
    /// @return     (Bool) true when the resolved card drop changes the canonical list order; false otherwise
    ///
    private func finishCardDrag(at point: CGPoint) -> Bool
    {
        defer
        {
            clearCardDrag()
        }

        guard let cardID = draggedCardID, let focusedList else
        {
            return false
        }

        guard
        let target = cardDropTarget ?? BoardCardMovement.target(
            for: cardID, at: point, viewport: cardViewport,
            lists: [focusedList], listFrames: [listID: cardViewport], cardFrames: cardFrames
        )
        else
        {
            return false
        }

        do
        {
            return try BoardCardMovement.move(cardID, to: listID, before: target.beforeCardID, in: &lists)
        }
        catch
        {
            DatabaseActivity.shared.report(
                "Could not move this card: \(error.localizedDescription) Its content has been retained.")
            return false
        }
    }


    ///
    /// @fcn        TodayListDetailView.focusedList
    /// @brief      Resolve the focused Today list in the shared active snapshot
    /// @details    Finds the first list matching listID without selecting a fallback
    ///
    /// @return     (KanbanList?) current list value, or nil after removal/archive
    /// @post       Selection and shared Board data remain unchanged
    ///
    private var focusedList: KanbanList?        /* Focused list                                        */
    {                                           /* Current list resolved for the focused Board surface */
        lists.first
        {
            $0.id == listID
        }
    }


    ///
    /// @fcn        TodayListDetailView.usesCompactCards
    /// @brief      Resolve whether a card uses a compact preview
    /// @details    Combines board, list, and card appearance through the shared detail-resolution rules
    ///
    /// @param[in]  card  Card or note being inspected or changed
    ///
    /// @return     (Bool) true when effective card, list, and board appearance resolves to compact detail
    ///
    private func usesCompactCards(_ card: KanbanCard) -> Bool
    {
        effectiveBoardAppearance.resolvedCardDetail(card: card.appearance, list: focusedList?.appearance) == .compact
    }


    ///
    /// @fcn        TodayListDetailView.cardPreviewHeight
    /// @brief      Choose the compact or standard preview height
    /// @details    Returns the compact row height when inherited appearance selects compact detail; otherwise uses
    ///             the standard minimum
    ///
    /// @param[in]  card  Card or note being inspected or changed
    ///
    /// @return     (CGFloat) sixty-four points for a compact card or the standard minimum height otherwise
    ///
    private func cardPreviewHeight(_ card: KanbanCard) -> CGFloat
    {
        usesCompactCards(card) ? 64 : BoardPresentation.standard.minimumCardHeight
    }


    ///
    /// @fcn        TodayListDetailView.cardPreview
    /// @brief      Build a preview appropriate to the list's display mode
    /// @details    Uses a note row for note-list mode or a styled card preview with the existing edit, completion,
    ///             archive, and delete callbacks
    ///
    /// @param[in]  card  Card or note being inspected or changed
    ///
    /// @return     (some View) a preview appropriate to the list's display mode
    ///
    @ViewBuilder
    private func cardPreview(_ card: KanbanCard) -> some View
    {
        if focusedList?.singleListViewMode == .noteList
        {
            SingleListNoteRow(
                card: card, onToggle:
                {
                    toggleCard(card.id)
                },
                onArchive:
                {
                    archiveCard(card.id)
                }, onDelete:
                {
                    _ = deleteCard(card.id)
                }, onUpdateCard: updateCard)
        }
        else
        {
            KanbanCardView(
                card: card,
                height: cardPreviewHeight(card),
                displaySettings: BoardDisplaySettings(),
                cardBackground: effectiveBoardAppearance.cardBackground,
                compactCards: usesCompactCards(card),
                titleColor: effectiveBoardAppearance.resolvedTitleColor(
                    card: card.appearance, list: focusedList?.appearance),
                supportingTextColor: effectiveBoardAppearance.resolvedTextColor(
                    card: card.appearance, list: focusedList?.appearance),
                listedOnDate: representedDate,
                labelLibrary: labelLibrary,
                onUpdateCard: updateCard,
                onDeleteCard:
                {
                    deleteCard(card.id)
                },
                onArchiveCard:
                {
                    archiveCard(card.id)
                }
            )
            {
                toggleCard(card.id)
            }
        }
    }


    private var personalListBackground: CollectionBackground?           /* Personal list background */
    {
        guard representedDate == nil,
        CollectionBackground.isAllowed(
            collectionID: dayMovementSource,
            datedWeekIDs: Set(planningCalendarAccess?.document.weeks.map(\.id) ?? []), isDatedView: false)
        else
        {
            return nil
        }

        return CollectionBackground.defaultListBackground(
            for: focusedList?.title ?? "", overriding: effectiveBoardAppearance.collectionBackground)
    }


    private var headerColor: Color      /* Header color */
    {
        let chosen   =                                                                  /* Explicit user selection            */
            effectiveBoardAppearance.resolved(focusedList?.appearance).background
        let fallback =                                                                  /* Value used when no override exists */
            representedDate == nil ? DefaultListTutorial.defaultBanner(for: focusedList?.title ?? "") : nil

        return (chosen ?? fallback)?.darkHeaderColor
        ?? Color(red: 109.0 / 255, green: 139.0 / 255, blue: 152.0 / 255)       // Muted blue (#6D8B98)
    }




    ///
    /// @fcn        TodayListDetailView.sessionGuidance(for:)
    /// @brief      Build the visit-scoped information card
    /// @details    Shares guidance state and header toggles across empty and populated list layouts
    ///
    /// @param[in]  focusedList  Current list supplying content and appearance
    /// @return     (some View) session-scoped list content
    ///
    private func sessionGuidance(for focusedList: KanbanList) -> some View
    {
        SessionListGuidance(
            list: focusedList, labels: labelLibrary, toggleRequest: guidanceToggleRequest,
            onPresentationChange:
            {
                guidanceFooterVisible = $0
            }
        )
    }


    ///
    /// @fcn        TodayListDetailView.inlineCapture(for:)
    /// @brief      Build the list capture controls
    /// @details    Reveals capture with the guide on an empty List and keeps it available on retraction
    ///
    /// @param[in]  focusedList  Current list supplying content and appearance
    /// @return     (some View) session-scoped list content
    ///
    private func inlineCapture(for focusedList: KanbanList) -> some View
    {
        InlineListCapture(
            list: focusedList, draft: $inlineCaptureDraft,
            textColor: effectiveBoardAppearance.resolvedAddItemTextColor(
                list: focusedList.appearance, title: focusedList.title)?.color ?? .primary,
            isPresented: guidanceFooterVisible
            ?? (!focusedList.cards.isEmpty
                || DefaultListTutorial.guidance(for: focusedList.title) == nil),
            onCreate: addCard,
            onOpenComposer:
            {
                showsNewCard = true
            },
            keepsFocusAfterSubmit: representedDate == nil
        )

        .padding(12)
        .background
        {
            cardDropSurface
        }
        .overlay(alignment: .top)
        {
            insertionMarker(before: nil)
        }
    }


    ///
    /// @fcn        TodayListDetailView.body
    /// @brief      Present today's selected list vertically with shared Week card actions
    /// @details    Reuses compact card rows and detail navigation, displays dividers without
    ///             detail links, and offers inline card capture. Missing lists show an unavailable state
    ///
    /// @return     (some View) focused-list navigation stack with activity feedback
    /// @pre        lists is the writable active Week partition; reservedLists retains archived ID reservations
    /// @post       Card edits mutate the shared binding for caller-owned persistence; label changes
    ///             save locally. Toolbar actions delegate Today/Week routing to supplied callbacks
    ///
    var body: some View         /* Today List Detail layout */
    {
        Group
        {
            if let selectedDay
            {
                PlanningSelectedDayView(
                    selection: selectedDay, currentUserName: currentUserName,
                    returnDestinationTitle: returnDestinationTitle, onClose: onClose,
                    onSelectDay: selectDay, onOpenSelectedWeek: onOpenSelectedWeek
                )
                .id(selectedDay.date)
            }
            else
            {
                dayContent
            }
        }
        .sheet(isPresented: $showsWeekSelector)
        {
            if let date = representedDate, let access = planningCalendarAccess
            {
                PlanningWeekSelector(
                    initialDate: date,
                    document: access.document,
                    selectedWeekKey: PlanningDate.weekKey(date, calendar: access.document.calendar),
                    sources: access.searchableItems,
                    opensDay: true
                )
                {
                    _, date in

                    showsWeekSelector = false
                    selectDay(date)
                }
            }
        }
        .sheet(isPresented: $showsDaySelector)
        {
            PlanningDaySelector(initialDate: representedDate ?? .now)
            {
                date in

                showsDaySelector = false

                selectDay(date)
            }
            .environment(\.calendar, planningCalendarAccess?.document.calendar ?? .current)
        }
    }


    ///
    /// @fcn        TodayListDetailView.selectDay
    /// @brief      Open the requested day through the available navigation path
    /// @details    Prefers the injected day-selection callback; otherwise resolves a calendar-backed selection and
    ///             leaves state unchanged if unavailable
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (Void) no return value
    ///
    private func selectDay(_ date: Date)
    {
        if let onSelectDay
        {
            onSelectDay(date);
            return
        }

        guard let access = planningCalendarAccess,
        let selection = PlanningDaySelection.resolve(date, document: access.document)
        else
        {
            return
        }

        selectedDay = selection
    }


    ///
    /// @fcn        TodayListDetailView.keyboardNavigation
    /// @brief      Build previous and next card navigation actions
    /// @details    Enables actions only for existing neighbors and resolves each neighbor again when invoked to avoid
    ///             using a stale ordering
    ///
    /// @param[in]  card  Card or note being inspected or changed
    ///
    /// @return     (CardKeyboardNavigation) previous and next actions that resolve current neighboring cards when
    ///             invoked
    ///
    private func keyboardNavigation(for card: KanbanCard) -> CardKeyboardNavigation
    {
        let neighbors = CardKeyboardNeighbors.resolve(card, in: lists)          /* Adjacent items or Lists */

        return CardKeyboardNavigation(
            back:
            {
                if !keyboardDetailPath.isEmpty
                {
                    keyboardDetailPath.removeLast()
                }
            },
            previous: neighbors.previous == nil
            ? nil
            :
            {
                if let target = CardKeyboardNeighbors.resolve(card, in: lists).previous
                {
                    keyboardDetailPath = [target]
                }
            },
            next: neighbors.next == nil
            ? nil
            :
            {
                if let target = CardKeyboardNeighbors.resolve(card, in: lists).next
                {
                    keyboardDetailPath = [target]
                }
            })
    }


    private func dismissDaySummary(allowingPartialVisibility: Bool = false)
    {
        isDaySummaryDismissalPending = false
        canDismissPartiallyVisibleSummary = allowingPartialVisibility
        daySummaryScrollID += 1
    }


    private var dayContent: some View                   /* Day content                                           */
    {                                                   /* Focused-list Board surface and card-detail navigation */
        NavigationStack(path: $keyboardDetailPath)
        {
            ZStack
            {
                if let personalListBackground
                {
                    CollectionBackgroundSurface(background: personalListBackground).ignoresSafeArea()
                }
                else
                {
                    Color(.systemGray6).ignoresSafeArea()
                }
                if let surface = focusedList?.appearance?.studioSurface ?? effectiveBoardAppearance.studioSurface
                {
                    StudioSurfaceView(surface: surface).ignoresSafeArea()
                }


                VStack(spacing: 0)
                {
                    Color.clear.frame(height: 129)

                    Spacer(minLength: 0)
                }

                .ignoresSafeArea()
                .overlay(alignment: .bottom)
                {
                    Rectangle()
                    .fill(Color(red: 0.82, green: 0.68, blue: 0.40))
                    .frame(height: 4)
                    .background
                    {
                        // Match the Day banner below the gold edge through the home-indicator area
                        headerColor
                        .ignoresSafeArea(edges: .bottom)
                    }
                    .shadow(color: Color(red: 0.72, green: 0.56, blue: 0.30).opacity(0.4), radius: 5, y: 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }


                if let focusedList
                {                       /* Selected list available for rendering */
                    ScrollViewReader
                    {
                        scrollProxy in
                        let cards = List        /* Scrollable rows beneath the guidance */
                        {
                            if let day = representedDate
                            {
                                DayScheduleOverview(
                                    cards: focusedList.cards, labels: labelLibrary, day: day,
                                    calendar: planningCalendarAccess?.document.calendar ?? .current,
                                    onDismissSummary: { dismissDaySummary(allowingPartialVisibility: true) }
                                )
                                .padding(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                                .onGeometryChange(for: CGFloat.self)
                                {
                                    $0.size.height
                                }
                                action:
                                {
                                    daySummaryHeight = $0
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .id("day.scheduleOverview")
                            }


                            ForEach(DaySections.visible(focusedList.cards))
                            {
                                card in

                                if card.isSectionDivider
                                {
                                    DaySectionRow(
                                        card: card, cards: focusedList.cards, onUpdate: updateCard,
                                        onMove:
                                        {
                                            offset in
                                            guard let index = lists.firstIndex(where:
                                                {
                                                    $0.id == listID
                                                }) else
                                            {
                                                return
                                            }

                                            lists[index].cards = DaySections.moved(
                                                lists[index].cards, sectionID: card.id, offset: offset)
                                        }
                                    )
                                    .buttonStyle(.plain)
                                    .modifier(HideNavigationLinkIndicator())
                                    .id(card.id)
                                    .accessibilityLabel(
                                        card.sectionHeading.map
                                        {
                                                                                    "Edit section heading: " + $0
                                        }

                                        ?? "Edit section divider"
                                    )
                                    .contextMenu
                                    {
                                        ItemDisplayFormatMenu(card: card, onUpdate: updateCard)
                                    }
                                    .modifier(
                                        ContentLifecycleActions(
                                            title: "Divider", kind: "Card", onArchive: nil,
                                            onDelete:
                                            {
                                                deleteCard(card.id)
                                            }
                                        )
                                    )
                                    .contentShape(Rectangle())
                                    .background
                                    {
                                        if card.sectionHeading == nil
                                        {
                                            cardDragSource(for: card.id)
                                        }
                                    }
                                    .opacity(draggedCardID == card.id ? 0.45 : 1)
                                    .listRowInsets(
                                        focusedList.singleListViewMode == .noteList
                                        ? EdgeInsets() : EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .background
                                    {
                                        GeometryReader
                                        {
                                            geometry in
                                            Color.clear.preference(
                                                key: BoardCardFramePreferenceKey.self,
                                                value: [card.id: geometry.frame(in: .global)])
                                        }
                                    }
                                    .background
                                    {
                                        cardDropSurface
                                    }
                                    .overlay(alignment: .top)
                                    {
                                        insertionMarker(before: card.id)
                                    }
                                }
                                else
                                {
                                    NavigationLink(value: card)
                                    {
                                        cardPreview(card)
                                        .modifier(DaySectionRail(cardID: card.id, cards: focusedList.cards))
                                    }

                                    .buttonStyle(.plain)
                                    .modifier(HideNavigationLinkIndicator())
                                    .id(card.id)
                                    .background
                                    {
                                        cardDragSource(for: card.id)
                                    }
                                    .opacity(draggedCardID == card.id ? 0.45 : 1)
                                    .background
                                    {
                                        GeometryReader
                                        {
                                            geometry in
                                            Color.clear.preference(
                                                key: BoardCardFramePreferenceKey.self,
                                                value: [card.id: geometry.frame(in: .global)])
                                        }
                                    }
                                    .background
                                    {
                                        cardDropSurface
                                    }
                                    .overlay(alignment: .top)
                                    {
                                        insertionMarker(before: card.id)
                                    }
                                    .listRowInsets(
                                        focusedList.singleListViewMode == .noteList
                                        ? EdgeInsets() : EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .offset(x: slidingOutCardID == card.id
                                        ? -max(cardViewport.width, cardFrames[card.id]?.width ?? 0) - 24
                                        : (swipeOffset?.id == card.id ? swipeOffset?.x ?? 0 : 0))
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 24, coordinateSpace: .global)
                                            .updating($swipeOffset)
                                            {
                                                drag, offset, _ in
                                                if !reduceSummaryMotion, canSwipeDelete(drag)
                                                {
                                                    offset = (card.id, drag.translation.width)
                                                }
                                            }
                                            .onEnded
                                            {
                                                drag in
                                                guard canSwipeDelete(drag), drag.translation.width <= -80 else { return }
                                                slideOutCard(card)
                                            },
                                        including: editMode == .active ? .none : .all
                                    )
                                    .accessibilityAction(named: "Delete")
                                    {
                                        guard editMode != .active else { return }
                                        swipeDelete(card)
                                    }
                                }
                            }

                            .onMove
                            {
                                sourceOffsets, destinationOffset in
                                guard editMode == .active,
                                let move = DaySections.visibleMove(
                                    focusedList.cards, sourceOffsets: sourceOffsets,
                                    destinationOffset: destinationOffset)
                                else
                                {
                                    return
                                }

                                moveCard(move.id, toIndex: move.index)
                            }
                            .moveDisabled(editMode != .active)


                            inlineCapture(for: focusedList)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 16, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        .listStyle(.plain)
                        .environment(\.defaultMinListRowHeight, 0)
                        .environment(\.editMode, $editMode)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.top, 14, for: .scrollContent)
                        .background(
                            focusedList.singleListViewMode == .noteList
                            && focusedList.appearance?.studioSurface == nil && effectiveBoardAppearance.studioSurface == nil
                            ? Color(.systemBackground).opacity(
                                focusedList.appearance?.resolvedListBackgroundOpacity ?? 1) : .clear
                        )
                        // Explicit task focus takes priority over restoring an old viewport
                        .background(
                            BoardViewportScrollProbe(
                                memory: focusesFirstUncheckedTask ? nil : focusedViewportMemory, key: "vertical",
                                initialScroll: daySummaryScrollID > 0
                                ? .init(id: daySummaryScrollID, distance: daySummaryHeight,
                                        duration: reduceSummaryMotion ? 0 : 1,
                                        requiresTop: !canDismissPartiallyVisibleSummary)
                                : nil,
                                returnToTopDistance: daySummaryHeight,
                                onReturnToTop: representedDate != nil ?
                                {
                                    isDaySummaryDismissalPending = $0
                                } : nil
                            )
                        )
                        .modifier(RevealCreatedContent(lists: [focusedList], existingProxy: scrollProxy))
                        .onAppear
                        {
                            if focusedViewportMemory == nil
                            {
                                let currentWeekID =                                     /* Current week ID */
                                    planningCalendarAccess?.document.weeks.first
                                {
                                    $0.startKey == planningCalendarAccess?.document.currentWeekKey
                                }?.id
                                let owner    =                          /* Normalized owner identifier */
                                    (dayMovementSource ?? currentWeekID)?.uuidString ?? "week.current"
                                let location = representedDate.map      /* Resolved place metadata     */
                                {
                                    PlanningDate.key($0)
                                }
                                ?? String(listID)

                                focusedViewportMemory = BoardViewportMemory(owner: owner + ".focused." + location)
                            }
                        }
                        .onDisappear
                        {
                            focusedViewportMemory?.flush()
                        }

                        .background
                        {
                            GeometryReader
                            {
                                geometry in
                                Color.clear.preference(
                                    key: BoardListFramePreferenceKey.self,
                                    value: [listID: geometry.frame(in: .global)])
                            }
                        }
                        .onPreferenceChange(BoardListFramePreferenceKey.self)
                        {
                            frames in

                            cardViewport = frames[listID] ?? .zero
                        }
                        .onPreferenceChange(BoardCardFramePreferenceKey.self)
                        {
                            frames in

                            cardFrames = frames
                        }
                        .onDisappear
                        {
                            clearCardDrag()
                        }
                        .onChange(of: scenePhase)
                        {
                            _, phase in
                            if phase != .active
                            {
                                clearCardDrag()
                            }
                        }
                        .onChange(of: editMode)
                        {
                            _, _ in
                            clearCardDrag()
                        }
                        .overlay(alignment: .top)
                        {
                            Rectangle()
                            .fill(Color(.systemGray3).opacity(0.65))
                            .overlay(headerColor.opacity(0.20))
                            .mask
                            {
                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .top, endPoint: .bottom)
                            }
                            .frame(height: 12)
                            .offset(y: 4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }

                        .task(id: cardViewport.size)
                        {
                            guard focusesFirstUncheckedTask, !autoDismissesDaySummary, !didApplyInitialTaskFocus,
                            cardViewport.height > 0, cardViewport.width > 0,
                            let target = focusedList.firstUncheckedTaskID
                            else
                            {
                                return
                            }

                            // List registers its row IDs after its first layout pass
                            do
                            {
                                try await Task.sleep(for: .milliseconds(150))
                            }
                            catch
                            {
                                return
                            }

                            guard !Task.isCancelled else
                            {
                                return
                            }

                            scrollProxy.scrollTo(target, anchor: .top)

                            didApplyInitialTaskFocus = true
                        }

                        VStack(spacing: 0)
                        {
                            sessionGuidance(for: focusedList)
                                .padding(.horizontal, 8)

                            cards
                        }
                    }
                }
                else
                {
                    ContentUnavailableView("List unavailable", systemImage: "list.bullet")
                }
            }

            .onChange(of: focusedList.map
                {
                    ListCheckmarkReset.values(in: $0)
                })
            {
                _, _ in
                if let focusedList, checkmarkReset?.canRestore(focusedList) == false
                {
                    checkmarkReset = nil
                }
            }
            .onChange(of: listID)
            {
                _, _ in

                checkmarkReset = nil
                slidingOutCardID = nil
                finishSwipeDeletion()
            }
            .onDisappear
            {
                slidingOutCardID = nil
                checkmarkReset = nil
                finishSwipeDeletion()
            }
            .overlay(alignment: .bottom)
            {
                swipeDeletionNotice
            }
            .task(id: swipeDeletion?.token)
            {
                guard let token = swipeDeletion?.token else { return }
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }

                guard !Task.isCancelled, swipeDeletion?.token == token else { return }
                finishSwipeDeletion()
            }
            .modifier(
                ListCheckmarkResetConfirmation(
                    list: focusedList, session: $checkmarkReset,
                    confirmsClear: $confirmsCheckmarkReset, onUpdateCard: updateCard)
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0)
            {
                VStack(spacing: 0)
                {
                    AdaptiveWorkspaceHeaderLayout(regularSpacing: 12, layoutDirection: headerLayoutDirection)
                    {
                        Button(action: onClose)
                        {
                            Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to \(returnDestinationTitle)")
                        VStack(alignment: .leading, spacing: 2)
                        {
                            HStack(spacing: 8)
                            {
                                ItemAppearanceMark(
                                    appearance: focusedList?.headerAppearance(
                                        collectionIcon: planningCalendarAccess?.library.first(where:
                                            {
                                                $0.id == dayMovementSource
                                            })?.icon,
                                        collectionColor: planningCalendarAccess?.library.first(where:
                                            {
                                                $0.id == dayMovementSource
                                            })?.color))
                                let title = SlideableHeaderText(
                                    text: focusedList?.title ?? representedDate.map
                                    {
                                        PlanningDate.weekdayTitle($0)
                                    }
                                    ?? "Today"
                                )
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)

                                if representedDate != nil, planningCalendarAccess != nil
                                {
                                    Button
                                    {
                                        showsWeekSelector = true
                                    }
                                    label:
                                    {
                                        title.contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Choose the day displayed in this view")
                                    .accessibilityIdentifier("day.weekSelector")
                                }
                                else
                                {
                                    title
                                }
                            }


                            if let representedDate
                            {
                                Button
                                {
                                    showsDaySelector = true
                                }
                                label:
                                {
                                    Text(representedDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .font(effectiveBoardAppearance.resolvedSubtitleItalic(list: focusedList?.appearance)
                                          ? .subheadline.italic() : .subheadline)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(planningCalendarAccess == nil && onSelectDay == nil)
                                .accessibilityHint("Choose the day displayed in this view")
                                .accessibilityIdentifier("day.dateSelector")
                            }
                            else if let subtitle = focusedList?.subtitle, !subtitle.isEmpty
                            {
                                SlideableHeaderText(text: subtitle)
                                .font(effectiveBoardAppearance.resolvedSubtitleItalic(list: focusedList?.appearance)
                                      ? .subheadline.italic() : .subheadline)
                                .foregroundStyle(.white.opacity(0.75))
                            }
                        }

                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .contain)
                        .contentShape(Rectangle())
                        .onTapGesture
                        {
                            guard representedDate == nil,
                            DefaultListTutorial.guidance(for: focusedList?.title ?? "") != nil
                            else
                            {
                                return
                            }

                            guidanceToggleRequest += 1
                        }
                        .accessibilityAction(named: "Show or hide List guide")
                        {
                            guard representedDate == nil,
                            DefaultListTutorial.guidance(for: focusedList?.title ?? "") != nil
                            else
                            {
                                return
                            }

                            guidanceToggleRequest += 1
                        }
                        .layoutValue(key: WorkspaceHeaderTitleKey.self, value: true)
                        Button
                        {
                            showsDaySearch = true
                        }
                        label:
                        {
                            WorkspaceHeaderIcon(systemName: "magnifyingglass").foregroundStyle(.white)
                        }
                        .accessibilityLabel("Search Plenact")
                        Button
                        {
                            if onOpenSelectedWeek == nil, onSelectDay == nil, let planningCalendarAccess,
                            (dayMovementSource != nil
                                && dayMovementSource != planningCalendarAccess.document.week(for: .now)?.id)
                            || (representedDate.map
                                {
                                    PlanningDate.weekKey($0, calendar: planningCalendarAccess.document.calendar)
                                    != planningCalendarAccess.document.currentWeekKey
                                }
                                ?? false)
                            {
                                planningCalendarAccess.openCurrentWeek();
                                onClose();
                                planningHomeExit?()
                            }
                            else
                            {
                                onOpenWeek()
                            }
                        }
                        label:
                        {
                            WorkspaceHeaderIcon(systemName: "rectangle.split.3x1").foregroundStyle(.white)
                        }
                        .accessibilityLabel("Open this week")
                        Menu
                        {
                            Picker(
                                "View as",
                                selection: Binding(
                                    get:
                                    {
                                        focusedList?.singleListViewMode ?? .cards
                                    },
                                    set:
                                    {
                                        mode in
                                        guard let index = lists.firstIndex(where:
                                            {
                                                $0.id == listID
                                            }) else
                                        {
                                            return
                                        }

                                        lists[index].setSingleListViewMode(mode)
                                    }
                                )
                            )
                            {
                                ForEach(SingleListViewMode.allCases)
                                {
                                    Text($0.title).tag($0)
                                }
                            }

                            if let focusedList
                            {
                                ListCheckmarkResetControl(
                                    list: focusedList, session: $checkmarkReset, confirmsClear: $confirmsCheckmarkReset,
                                    onUpdateCard: updateCard)
                            }

                            Button("Appearance", systemImage: "paintpalette")
                            {
                                isEditingAppearance = true
                            }

                            Button("Edit list", systemImage: "pencil")
                            {
                                isEditingList = true
                            }

                            Button(
                                editMode == .active ? "Done reordering cards" : "Reorder cards",
                                systemImage: editMode == .active
                                ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle"
                            )
                            {
                                withAnimation(.easeInOut(duration: 0.2))
                                {
                                    editMode = editMode == .active ? .inactive : .active
                                }
                            }


                            Button(boardViewActionTitle, systemImage: "rectangle.split.3x1", action: onOpenWeek)
                        }
                        label:
                        {
                            WorkspaceHeaderIcon(systemName: "ellipsis.circle.fill").foregroundStyle(.white)
                        }

                        .accessibilityLabel("Day options")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)

                    Color.clear.frame(height: 12)
                }
                .background
                {
                    Rectangle()
                    .fill(headerColor.opacity(0.85))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .top)
                }
                .overlay(alignment: .bottom)
                {
                    Rectangle()
                    .fill(Color(red: 0.82, green: 0.68, blue: 0.40))
                    .frame(height: 4)
                    .offset(y: 4)
                    .shadow(color: Color(red: 0.72, green: 0.56, blue: 0.30).opacity(0.4), radius: 5, y: 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }

            .modifier(LowerCornerBackShortcut(action: onClose))
            .background
            {
                if representedDate != nil
                {
                    DailyOverviewProbe(
                        armed: shouldDismissDaySummary,
                        onVisible: { isDayVisible = $0 },
                        onInteraction: { isDaySummaryDismissalPending = false }
                    )
                }
            }
            .task(id: isDayVisible && shouldDismissDaySummary && scenePhase == .active)
            {
                guard isDayVisible, shouldDismissDaySummary,
                      scenePhase == .active, representedDate != nil else { return }

                do
                {
                    try await Task.sleep(for: .seconds(2))
                }
                catch
                {
                    return
                }

                guard !Task.isCancelled, shouldDismissDaySummary else { return }
                dismissDaySummary()
            }
            .navigationDestination(for: KanbanCard.self)
            {
                card in
                CardDetailView(
                    card: card,
                    labelLibrary: $labelLibrary,
                    availableLists: lists.filter
                    {
                        $0.id != listID
                    },
                    currentUserName: currentUserName,
                    savedCardIDs: $savedCardIDs,
                    onTitleToggle: updateCard,
                    onMoveToList:
                    {
                        destinationListID in
                        moveCard(card.id, toListID: destinationListID)
                    },
                    onArchive:
                    {
                        archiveCard(card.id)
                    },
                    onDelete:
                    {
                        deleteCard(card.id)
                    },
                    listedOnDate: representedDate
                )
                .id(card.id)
                .environment(\.cardKeyboardNavigation, keyboardNavigation(for: card))
            }

            .environment(\.studioCardSurface,
                focusedList?.appearance?.studioCardSurface ?? effectiveBoardAppearance.studioCardSurface)
            .environment(\.inheritedSubtitleItalic,
                effectiveBoardAppearance.resolvedSubtitleItalic(list: focusedList?.appearance))
            .onChange(of: labelLibrary)
            {
                _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }
        }

        .modifier(
            PlanningSharedSearchPresentation(
                isPresented: $showsDaySearch,
                onLeaveForHome:
                {
                    onClose();
                    planningHomeExit?()
                })
        )
        .environment(\.checklistLinkCandidates, lists.filter
            {
                !$0.isArchived
            } .flatMap(\.cards))
        .sheet(isPresented: $showsNewCard)
        {
            if let focusedList = lists.first(where:
                {
                    $0.id == listID
                })
            {
                ListItemComposer(
                    list: focusedList, draftKey: ListCreationDraft.key(collectionID: dayMovementSource, listID: listID),
                    initialTitle: inlineCaptureDraft.title,
                    onCreate:
                    {
                        capture in
                        guard addCard(capture) else
                        {
                            return false
                        }

                        inlineCaptureDraft.title = ""

                        return true
                    }
                )
                .databaseActivityOverlay()
            }
        }
        .sheet(isPresented: $isEditingList)
        {
            if let focusedList
            {
                ListInfoEditorSheet(list: focusedList)
                {
                    title, subtitle, defaultPresentation in
                    editBoardList(
                        listID, title: title, subtitle: subtitle, newItemPresentation: defaultPresentation, in: &lists)
                }
                .databaseActivityOverlay()
            }
        }
        .sheet(isPresented: $isEditingAppearance)
        {
            if let focusedList
            {
                ItemAppearanceSheet(
                    title: focusedList.title, appearance: focusedList.appearance, showsListBackground: true,
                    inheritedAddItemTextColor: effectiveBoardAppearance.resolvedAddItemTextColor(
                        list: nil, title: focusedList.title)?.color ?? .primary
                )
                {
                    appearance in
                    setListAppearance(listID, appearance: appearance, in: &lists)
                }
            }
        }
        .databaseActivityOverlay()
    }


    ///
    /// @fcn        TodayListDetailView.toggleCard(_:)
    /// @brief      Toggle one focused-list card's title completion
    /// @details    Resolves the focused list and active card by ID before flipping its completion
    ///             flag
    ///
    /// @param[in]  cardID  Card identity within the focused list
    ///
    /// @return     (Void) updates shared completion state
    ///
    /// @post       Missing list/card identities leave state unchanged; caller observation owns
    ///             persistence
    ///
    private func toggleCard(_ cardID: Int)
    {
        guard
        let listIndex = lists.firstIndex(where:
            {                                   /* Position of the focused list containing the requested card */
                $0.id == listID
            }),
        let cardIndex = lists[listIndex].cards.firstIndex(where:
            {
                $0.id == cardID
            })
        else
        {
            return
        }               /* Position of the requested card within the focused list */

        guard !lists[listIndex].cards[cardIndex].isEditingLocked else
        {
            return
        }

        lists[listIndex].cards[cardIndex].isTitleChecked.toggle()
    }


    ///
    /// @fcn        TodayListDetailView.moveCard(_:toIndex:)
    /// @brief      Reorder one focused-list record without changing its content
    /// @details    Uses the shared bounded card-order operation on the canonical Week binding
    ///
    /// @param[in]  cardID            Stable identity of the record being moved
    /// @param[in]  destinationIndex  Requested zero-based destination position
    ///
    /// @return     (Void) updates only the focused list's card order
    ///
    /// @post       Missing lists, IDs, or no-op destinations leave shared state unchanged
    ///
    private func moveCard(_ cardID: Int, toIndex destinationIndex: Int)
    {
        guard
        let listIndex = lists.firstIndex(where:
            {                                   /* Position of the focused list to reorder */
                $0.id == listID
            })
        else
        {
            return
        }


        var cards = lists[listIndex].cards      /* Mutable focused-list card order */

        let reordered =                                                         /* Items in the requested order */
            DaySections.reordered(cards, itemID: cardID, to: destinationIndex)

        guard reordered != cards else
        {
            return
        }

        cards = reordered

        DaySections.reveal(cardID, in: &cards)

        withAnimation(.easeInOut(duration: 0.2))
        {
            lists[listIndex].cards = cards
        }
    }


    ///
    /// @fcn        TodayListDetailView.archiveCard(_:)
    /// @brief      Archive a task card in the shared Week snapshot
    /// @details    Finds the first active list containing the identity and delegates to the model
    ///             helper; it is not restricted to the focused list after a card moves
    ///
    /// @param[in]  cardID  Board-unique active card identity
    ///
    /// @return     (Void) transfers a matching non-divider card to its list's archive
    ///
    /// @post       Missing IDs/dividers do nothing; full content and attachments are retained
    ///
    private func archiveCard(_ cardID: Int)
    {
        guard
        let listIndex = lists.firstIndex(where:
            {                                   /* Position of the focused list receiving the requested change */
                $0.cards.contains(where:
                    {
                        $0.id == cardID
                    })
            })
        else
        {
            return
        }

        lists[listIndex].archiveCard(id: cardID)
    }


    ///
    /// @fcn        TodayListDetailView.updateCard(_:)
    /// @brief      Replace a shared active card with its edited snapshot
    /// @details    Searches all supplied active lists by identity so edits can resolve after list
    ///             movement
    ///
    /// @param[in]  updatedCard  Complete edited card value with an existing Board identity
    ///
    /// @return     (Void) replaces the first matching active record
    ///
    /// @post       Unknown IDs do nothing; this helper does not prune attachment files
    ///
    private func updateCard(_ updatedCard: KanbanCard)
    {
        guard
        let listIndex = lists.firstIndex(where:
            {                                   /* Position of the focused list owning the edited card */
                $0.cards.contains(where:
                    {
                        $0.id == updatedCard.id
                    })
            }),
        let cardIndex = lists[listIndex].cards.firstIndex(where:
            {
                $0.id == updatedCard.id
            })
        else
        {
            return
        }               /* Existing position of the submitted card snapshot */

        guard lists[listIndex].cards[cardIndex].acceptsContentUpdate(updatedCard) else
        {
            return
        }

        lists[listIndex].cards[cardIndex] = updatedCard
    }


    @ViewBuilder
    private var swipeDeletionNotice: some View
    {
        if let deletion = swipeDeletion
        {
            HStack(spacing: 16)
            {
                Text("\(deletion.card.presentation.title) deleted")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Button("Undo")
                {
                    undoSwipeDeletion(deletion)
                }
                .font(.headline)
                .frame(minHeight: 44)
                .accessibilityIdentifier("day.item.delete.undo")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(alignment: .top)
            {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .transition(reduceSummaryMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func canSwipeDelete(_ drag: DragGesture.Value) -> Bool
    {
        editMode != .active && draggedCardID == nil && slidingOutCardID == nil
            && -drag.translation.width > abs(drag.translation.height) * 2
    }

    private func slideOutCard(_ card: KanbanCard)
    {
        guard !reduceSummaryMotion else
        {
            swipeDelete(card)
            return
        }

        withAnimation(.easeOut(duration: 0.25), completionCriteria: .logicallyComplete)
        {
            slidingOutCardID = card.id
        }
        completion:
        {
            guard slidingOutCardID == card.id else { return }
            swipeDelete(card)
            withAnimation(.easeOut(duration: 0.2))
            {
                slidingOutCardID = nil
            }
        }
    }

    private func swipeDelete(_ card: KanbanCard)
    {
        guard let cards = focusedList?.cards,
              let index = cards.firstIndex(where: { $0.id == card.id && $0.createdAt == card.createdAt })
        else { return }

        let current = cards[index]
        let deletion = SwipeDeletion(
            card: current, listID: listID, index: index,
            previousID: index > 0 ? cards[index - 1].id : nil,
            nextID: index + 1 < cards.count ? cards[index + 1].id : nil,
            wasBookmarked: savedCardIDs.contains(card.id),
            media: Set((current.attachments ?? []).flatMap(\.storedFileNames)),
            cleanMedia: planningCalendarAccess?.cleanDeletedMedia
        )

        CardAttachmentStore.retainForUndo(deletion.media, token: deletion.token)
        // Animate the saved List mutation so UIKit can close the row gap with the swipe.
        let deleted = withAnimation(reduceSummaryMotion ? nil : .smooth(duration: 0.35))
        {
            deleteCard(card.id)
        }
        guard deleted else
        {
            CardAttachmentStore.releaseUndoMedia(token: deletion.token)
            return
        }

        finishSwipeDeletion()
        withAnimation(.easeOut(duration: 0.2))
        {
            swipeDeletion = deletion
        }
    }

    private func undoSwipeDeletion(_ deletion: SwipeDeletion)
    {
        guard swipeDeletion?.token == deletion.token else { return }

        var snapshot = lists + reservedLists
        guard let listIndex = snapshot.firstIndex(where: { $0.id == deletion.listID && !$0.isArchived }),
              !snapshot.contains(where: { $0.allCards.contains(where: { $0.id == deletion.card.id }) })
        else
        {
            DatabaseActivity.shared.report("Could not undo the deletion because the list or item changed.")
            return
        }

        let cards = snapshot[listIndex].cards
        let next = cards.firstIndex { $0.id == deletion.nextID }
        let previous = cards.firstIndex { $0.id == deletion.previousID }
        let index = next ?? previous.map { $0 + 1 } ?? min(deletion.index, cards.count)
        var card = deletion.card
        card.listTitle = snapshot[listIndex].title
        snapshot[listIndex].cards.insert(card, at: index)

        var bookmarks = savedCardIDs
        if deletion.wasBookmarked
        {
            bookmarks.insert(card.id)
        }

        if let onRestoreDeletedCard
        {
            guard onRestoreDeletedCard(snapshot, bookmarks) else
            {
                DatabaseActivity.shared.report("Could not undo the deletion. Your current content has been retained.")
                return
            }
        }
        else
        {
            lists = snapshot.filter { !$0.isArchived }
            savedCardIDs = bookmarks
        }

        finishSwipeDeletion(restored: true)
    }

    private func finishSwipeDeletion(restored: Bool = false)
    {
        guard let deletion = swipeDeletion else { return }
        withAnimation(.easeOut(duration: 0.2))
        {
            swipeDeletion = nil
        }
        CardAttachmentStore.releaseUndoMedia(token: deletion.token)
        if !restored
        {
            deletion.cleanMedia?(deletion.media)
        }
    }


    ///
    /// @fcn        TodayListDetailView.deleteCard(_:)
    /// @brief      Remove a card from the focused list
    /// @details    Delegates complete active/archive record and bookmark removal to the Week owner
    ///
    /// @param[in]  cardID  Identity to remove from the focused list
    ///
    /// @return     (Bool) successful checked save and canonical removal
    ///
    /// @post       Failed persistence leaves content, bookmarks, and detail drafts retained
    ///
    @discardableResult
    private func deleteCard(_ cardID: Int) -> Bool
    {
        onPermanentDelete(cardID)
    }


    ///
    /// @fcn        TodayListDetailView.moveCard(_:toListID:)
    /// @brief      Move a focused-list card to another active Week list
    /// @details    Removes the source record, updates its containing-list title, and appends it to
    ///             the destination while preserving all remaining card state
    ///
    /// @param[in]  cardID             Card identity in the focused source list
    /// @param[in]  destinationListID  Different active list identity receiving the card
    ///
    /// @return     (Void) updates source and destination in the shared binding
    ///
    /// @post       Missing identities or a same-list destination leave state unchanged
    ///
    private func moveCard(_ cardID: Int, toListID destinationListID: Int)
    {
        guard
        let sourceListIndex = lists.firstIndex(where:
            {                                           /* Source list position for explicit card movement */
                $0.id == listID
            }),
        let destinationListIndex = lists.firstIndex(where:
            {
                $0.id == destinationListID
            }
        ),                                              /* Destination list position for explicit card movement */
        sourceListIndex != destinationListIndex,
        let cardIndex = lists[sourceListIndex].cards.firstIndex(where:
            {
                $0.id == cardID
            })
        else
        {
            return
        }               /* Source card position before removal */


        var movedCard = lists[sourceListIndex].cards.remove(    /* Moved card */
            at: cardIndex)                                      /* Record relocated with its destination list name */

        movedCard.listTitle = lists[destinationListIndex].title

        lists[destinationListIndex].cards.append(movedCard)
    }


    ///
    /// @fcn        TodayListDetailView.addCard(_:)
    /// @brief      Save a full capture into the focused Day or personal List
    /// @details    Validates the destination, allocates identities across retained Lists, and
    ///             constructs complete items through the shared factory. Saves the resolved
    ///             calendar or personal owner before updating local bindings and requesting a
    ///             reveal; rejected saves leave the draft available
    ///
    /// @param[in]  capture  Complete destination-scoped creation submission with writing, media,
    ///             and scheduling
    ///
    /// @return     (Bool) true when the owning workspace accepted and saved the new content
    ///
    ///
    private func addCard(_ capture: QuickCaptureSubmission) -> Bool
    {
        guard capture.listID == listID, let listIndex = lists.firstIndex(where:
            {
                $0.id == listID
            }),
        let access = planningCalendarAccess
        else
        {
            return false
        }

        let nextCardID = ((lists + reservedLists).flatMap       /* Next card ID */
            {
                $0.allCards.map(\.id)
            } .max() ?? -1) + 1

        guard
        let created = ListItemCreation.items(
            capture, in: lists[listIndex], startingAt: nextCardID,
            calendar: access.document.calendar)
        else
        {
            return false
        }

        var updated = lists[listIndex]          /* Edited value to publish */

        updated.cards.append(contentsOf: created)
        if let first = created.first
        {
            DaySections.reveal(first.id, in: &updated.cards)
        }

        if var week = access.document.weeks.first(where:
            {
                week in
                if let dayMovementSource
                {
                    return week.id == dayMovementSource
                }

                let key =               /* Lookup or persistence key */
                representedDate.flatMap
                {
                    access.document.week(for: $0)?.startKey
                }
                ?? access.document.currentWeekKey

                return week.startKey == key
            }), let index = week.collection.lists.firstIndex(where:
            {
                $0.id == listID
            })
        {
            week.collection.lists[index] = updated

            guard access.saveWeek(week) else
            {
                return false
            }
        }
        else if var owner = access.library.first(where:
            {
                $0.id == dayMovementSource
            }),
        let index = owner.lists.firstIndex(where:
            {
                $0.id == listID
            })
        {
            owner.lists[index] = updated

            guard access.saveLibrary(owner) else
            {
                return false
            }
        }
        else
        {
            return false
        }

        lists[listIndex] = updated

        if let card = created.first
        {
            CreatedContentReveal.shared.request(listID: listID, card: card)
        }

        return true
    }
}
