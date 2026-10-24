// --------------------------------------------------------------------------------------------------
// @file       ListDetailView.swift
// @brief      Focused Day and personal List presentation
// @details    Renders one canonical List, resolves its dated or personal owner, and saves accepted
//             content through injected workspace access.
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


    @State private var keyboardDetailPath: [KanbanCard] = []
    @State private var checkmarkReset:     ListCheckmarkReset?
    @State private var confirmsCheckmarkReset = false
    @Environment(\.cardMovementSource) private var dayMovementSource
    @Environment(\.planningCalendarAccess) private var planningCalendarAccess
    @Environment(\.planningHomeExit) private var planningHomeExit
    @State private var focusedViewportMemory: BoardViewportMemory?
    @State private var showsDaySearch = false
    @State private var guidanceToggleRequest = 0
    @State private var guidanceFooterVisible: Bool?
    @State private var showsDaySelector = false
    @State private var selectedDay: PlanningDaySelection?
    var onSelectDay:                ((Date) -> Void)? = nil


    @Binding var lists: [KanbanList] /* Shared local Board snapshot */
    /// Archived lists and cards retained to reserve identities during creation.
    let reservedLists:         [KanbanList]  /* Retained lists whose card identities remain unavailable for reuse */
    @Binding var labelLibrary: LabelLibrary  /* Shared reusable label library                                     */
    @Binding var savedCardIDs: Set<Int>      /* Device-local saved cards                                          */

    let listID:            Int            /* Focused list identity                    */
    let currentUserName:   String         /* Current activity author                  */
    let onClose:           () -> Void     /* Return to Today                          */
    let onOpenWeek:        () -> Void     /* Open this list in the Week workspace     */
    let onPermanentDelete: (Int) -> Bool  /* Parent's save-first Week deletion result */

    @Environment(\.layoutDirection) private var headerLayoutDirection
    @AppStorage(BoardAppearance.weekStorageKey) private var weekAppearanceData = Data()
    var boardAppearance:        BoardAppearance? = nil
    var returnDestinationTitle: String = "Today"
    var boardViewActionTitle:   String = "Switch to Week View"
    var focusesFirstUncheckedTask = false
    var representedDate: Date? = nil
    @State private var didApplyInitialTaskFocus = false


    private var effectiveBoardAppearance: BoardAppearance
    {

        if let boardAppearance
        {
            return boardAppearance
        }

        if let dayMovementSource
        {

            let owner =
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

    @State private var isEditingList = false
    @State private var isEditingAppearance = false
    @State private var showsNewCard = false
    @State private var inlineCaptureDraft = InlineListCaptureDraft()
    @State private var deletingCard: KanbanCard?
    @State private var editMode:     EditMode = .inactive /* Whether Today rows expose native reorder controls */
    @State private var cardDragToken = UUID().uuidString
    @State private var draggedCardID:    Int?
    @State private var cardDragLocation: CGPoint?
    @State private var cardFrames:       [Int: CGRect] = [:]
    @State private var cardViewport:     CGRect = .zero
    @Environment(\.scenePhase) private var scenePhase

    private var cardDropTarget: BoardCardDropTarget?
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


    private var cardDropSurface: some View
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
    ///             interaction and accessibility.
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
    /// @details    Resets both drag fields so subsequent gestures begin without a stale source or pointer position.
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
    ///             card identity.
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

                    }
                )
            }

        }

    }


    ///
    /// @fcn        TodayListDetailView.finishCardDrag
    /// @brief      Resolve and apply the final card-drop location
    /// @details    Always clears drag state, rejects missing sources or targets, and reports movement errors instead
    ///             of claiming success.
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
        let target = BoardCardMovement.target(
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
    private var focusedList: KanbanList?
    {  /* Current list resolved for the focused Board surface */

        lists.first
        {
            $0.id == listID
        }

    }


    ///
    /// @fcn        TodayListDetailView.usesCompactCards
    /// @brief      Resolve whether a card uses a compact preview
    /// @details    Combines board, list, and card appearance through the shared detail-resolution rules.
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
    ///             the standard minimum.
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
    ///             archive, and delete callbacks.
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
                })
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


    private var personalListBackground: CollectionBackground?
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


    private var headerColor: Color
    {

        let chosen = effectiveBoardAppearance.resolved(focusedList?.appearance).background
        let fallback = representedDate == nil ? DefaultListTutorial.defaultBanner(for: focusedList?.title ?? "") : nil
        return (chosen ?? fallback)?.darkHeaderColor
        ?? Color(red: 109.0 / 255, green: 139.0 / 255, blue: 152.0 / 255)  // Muted blue (#6D8B98)
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
    var body: some View
    {

        Group
        {

            if let selectedDay
            {

                PlanningSelectedDayView(
                    selection: selectedDay, currentUserName: currentUserName,
                    returnDestinationTitle: returnDestinationTitle, onClose: onClose,
                    onSelectDay: selectDay
                )
                .id(selectedDay.date)
            }
            else
            {

                dayContent
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
    ///             leaves state unchanged if unavailable.
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
    ///             using a stale ordering.
    ///
    /// @param[in]  card  Card or note being inspected or changed
    ///
    /// @return     (CardKeyboardNavigation) previous and next actions that resolve current neighboring cards when
    ///             invoked
    ///
    private func keyboardNavigation(for card: KanbanCard) -> CardKeyboardNavigation
    {

        let neighbors = CardKeyboardNeighbors.resolve(card, in: lists)
        return CardKeyboardNavigation(
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


    private var dayContent: some View
    {  /* Focused-list Board surface and card-detail navigation */


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

                        // Match the Day banner below the gold edge through the home-indicator area.
                        headerColor
                        .ignoresSafeArea(edges: .bottom)
                    }
                    .shadow(color: Color(red: 0.72, green: 0.56, blue: 0.30).opacity(0.4), radius: 5, y: 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }


                if let focusedList
                {  /* Selected list available for rendering */


                    ScrollViewReader
                    {
                        scrollProxy in
                        List
                        {

                            if let day = representedDate
                            {

                                DayScheduleOverview(
                                    cards: focusedList.cards, labels: labelLibrary, day: day,
                                    calendar: planningCalendarAccess?.document.calendar ?? .current
                                )
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .id("day.scheduleOverview")
                            }


                            SessionListGuidance(
                                list: focusedList, labels: labelLibrary, toggleRequest: guidanceToggleRequest,
                                onPresentationChange:
                                {
                                    guidanceFooterVisible = $0
                                }
                            )
                            .environment(\.defaultMinListRowHeight, 0)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

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
                                    .modifier(
                                        ListItemSwipeDelete(
                                            enabled: editMode != .active,
                                            onRequest:
                                            {
                                                deletingCard = card
                                            }))
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
                                }
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
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 16, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        .listStyle(.plain)
                        .environment(\.editMode, $editMode)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.top, 14, for: .scrollContent)
                        .background(
                            focusedList.singleListViewMode == .noteList
                            ? Color(.systemBackground).opacity(
                                focusedList.appearance?.resolvedListBackgroundOpacity ?? 1) : .clear
                        )
                        // Explicit task focus takes priority over restoring an old viewport.
                        .background(
                            BoardViewportScrollProbe(
                                memory: focusesFirstUncheckedTask ? nil : focusedViewportMemory, key: "vertical")
                        )
                        .modifier(RevealCreatedContent(lists: [focusedList], existingProxy: scrollProxy))
                        .onAppear
                        {

                            if focusedViewportMemory == nil
                            {

                                let currentWeekID = planningCalendarAccess?.document.weeks.first
                                {

                                    $0.startKey == planningCalendarAccess?.document.currentWeekKey
                                }?.id
                                let owner = (dayMovementSource ?? currentWeekID)?.uuidString ?? "week.current"
                                let location = representedDate.map
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

                            guard focusesFirstUncheckedTask, !didApplyInitialTaskFocus,
                            cardViewport.height > 0, cardViewport.width > 0,
                            let target = focusedList.firstUncheckedTaskID
                            else
                            {
                                return
                            }

                            // List registers its row IDs after its first layout pass.
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
                checkmarkReset = nil;
                deletingCard = nil
            }
            .onDisappear
            {

                checkmarkReset = nil;
                deletingCard = nil
            }
            .confirmationDialog(
                                    "Delete \(deletingCard?.word ?? "item")?",
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

                Button("Delete \(deletingCard?.presentation.title ?? "item")", role: .destructive)
                {

                    if let target = deletingCard,
                    focusedList?.cards.contains(where:
                        {
                            $0.id == target.id && $0.createdAt == target.createdAt
                        })
                    == true
                    {

                        deleteCard(target.id)
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

                Text("Permanently deletes this item, its details, and its bookmark. This cannot be undone.")
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
                                SlideableHeaderText(
                                    text: focusedList?.title ?? representedDate.map
                                    {
                                        PlanningDate.weekdayTitle($0)
                                    }

                                    ?? "Today"
                                )
                                .font(.title2.weight(.bold))

                                .foregroundStyle(.white)
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
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.75))
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
                                .font(.subheadline)
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

                            if let planningCalendarAccess,
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

            .onChange(of: labelLibrary)
            {
                _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }

        }

        .modifier(LowerCornerBackShortcut(action: onClose))
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
            {  /* Position of the focused list containing the requested card */


                $0.id == listID
            }),
        let cardIndex = lists[listIndex].cards.firstIndex(where:
            {
                $0.id == cardID
            })
        else
        {
            return
        }  /* Position of the requested card within the focused list */

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
            {  /* Position of the focused list to reorder */


                $0.id == listID
            })
        else
        {


            return
        }


        var cards = lists[listIndex].cards /* Mutable focused-list card order */

        let reordered = DaySections.reordered(cards, itemID: cardID, to: destinationIndex)
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
            {  /* Position of the focused list receiving the requested change */


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
            {  /* Position of the focused list owning the edited card */


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
        }  /* Existing position of the submitted card snapshot */

        guard lists[listIndex].cards[cardIndex].acceptsContentUpdate(updatedCard) else
        {
            return
        }

        lists[listIndex].cards[cardIndex] = updatedCard
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
            {  /* Source list position for explicit card movement */


                $0.id == listID
            }),
        let destinationListIndex = lists.firstIndex(where:
            {
                $0.id == destinationListID
            }
        ), /* Destination list position for explicit card movement */
        sourceListIndex != destinationListIndex,
        let cardIndex = lists[sourceListIndex].cards.firstIndex(where:
            {
                $0.id == cardID
            })
        else
        {
            return
        }  /* Source card position before removal */


        var movedCard = lists[sourceListIndex].cards.remove(
            at: cardIndex) /* Record relocated with its destination list name */

        movedCard.listTitle = lists[destinationListIndex].title
        lists[destinationListIndex].cards.append(movedCard)
    }


    ///
    /// @fcn        TodayListDetailView.addCard(_:)
    /// @brief      Save a full capture into the focused Day or personal List
    /// @details    Validates the destination, allocates identities across retained Lists, and
    ///             constructs complete items through the shared factory. Saves the resolved
    ///             calendar or personal owner before updating local bindings and requesting a
    ///             reveal; rejected saves leave the draft available.
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

        let nextCardID = ((lists + reservedLists).flatMap
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

        var updated = lists[listIndex]
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

                let key =
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
