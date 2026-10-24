// --------------------------------------------------------------------------------------------------
// @file       BoardListColumn.swift
// @brief      One Board List column and its canonical Card rows
// @details    Composes List headings, previews, creation controls, and row actions while retaining
//             native List identity and owner callbacks.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


// -------------------------------------- MARK: - Kanban List ----------------------------------- //


///
/// Displays one kanban list and its cards
///
/// @section    Purpose
///     Keep a list title, list metadata, add-card action, and vertically scrollable card collection together
///
struct KanbanListView: View
{


    @State private var checkmarkReset: ListCheckmarkReset?
    @State private var confirmsCheckmarkReset = false
    @Environment(\.boardViewportMemory) private var viewportMemory

    @Environment(\.cardMovementSource) private var draftCollectionID


    /// Identifies the modal sheet currently presented by a kanban list
    ///
    /// @section    Purpose
    ///     Distinguish list actions from new-card entry
    ///
    private enum ActiveSheet: String, Identifiable
    {


        case listActions
        case newCard

        ///
        /// @fcn        KanbanListView.ActiveSheet.id
        /// @brief      Identify the list's active modal presentation
        /// @details    Uses the enum raw value to distinguish actions from new-card entry
        ///
        /// @return     (String) stable sheet identity
        /// @post       Presentation state remains unchanged
        ///
        var id: String
        {
            rawValue
        }  /* Stable sheet identity */

    }


    let list: KanbanList /* The kanban list data rendered by the view                      */
    /// Maximum vertical space available to the list's card collection.
    let availableListHeight: CGFloat               /* Vertical viewport space available to this list panel           */
    let displaySettings:     BoardDisplaySettings  /* The board's display settings affecting card and list rendering */
    /// Layout preset that controls the list's card dimensions.
    let presentation:       BoardPresentation                 /* Board layout controlling list density and dimensions         */
    let labelLibrary:       LabelLibrary                      /* Shared categorized labels available to the cards             */
    let toggleCardTitle:    (Int) -> Void                     /* The action invoked to toggle the title of a card             */
    let canMoveEarlier:     Bool                              /* Indicates whether the list can be moved earlier in the board */
    let canMoveLater:       Bool                              /* Indicates whether the list can be moved later in the board   */
    let onAddCard:          (QuickCaptureSubmission) -> Bool  /* The action invoked to add a new card to the list             */
    let onCopyList:         () -> Void                        /* The action invoked to copy the list                          */
    var onMoveToBoard:      (() -> Void)? = nil
    let onMoveList:         (Int) -> Void   /* The action invoked to move the list by a specified offset      */
    let onSortList:         (Bool) -> Void  /* The action invoked to sort the list based on a specified order */
    let onArchiveCompleted: () -> Void      /* The action invoked to archive all completed cards in the list  */
    /// Archived cards retained by this list.
    @Binding var archivedCards: [KanbanCard] /* Retained records belonging to this list's archive */
    /// Requests restoration of an archived card by identity.
    let onRestoreArchivedCard: (Int) -> Void  /* Restores a retained card to the active list              */
    let onDeleteArchivedCard:  (Int) -> Void  /* Confirmed removal of a retained card                     */
    let onArchiveList:         () -> Void     /* The action invoked to archive the entire list            */
    let onDeleteList:          () -> Void     /* Confirmed removal of this list and its retained content  */
    let onDeleteCard:          (Int) -> Void  /* The action invoked to delete a card at a specified index */
    /// Requests archival of an active card by identity.
    let onArchiveCard: (Int) -> Void         /* Archives an active card by identity                */
    let onUpdateCard:  (KanbanCard) -> Void  /* The action invoked to save edited card information */
    let onMoveCard:    (Int, Int) -> Void    /* Move a card to a destination index in this list    */
    /// Reports list-reorder drag updates to the owning board.
    let onListDragChanged: (DragGesture.Value?) -> Void /* Reports list-reorder gesture samples to the Board */
    /// Reports completion or cancellation of a list-reorder drag.
    let onListDragEnded:  () -> Void  /* Ends the parent Board's list-reorder session            */
    var draggedCardID:    Int? = nil  /* Active native-drag record identity                      */
    var dropBeforeCardID: Int? = nil  /* Card identity marking the current insertion boundary    */
    var isCardDropTarget = false      /* Whether this list contains the current insertion target */
    var onMoveSection: (Int, Int) -> Void =
    {
        _, _ in
    }

    var onCardDragBegan: (Int, CGPoint) -> Void =
    {
        _, _ in
    }  /* Reports a card identity and initial global pointer           */

    var onCardDragChanged: (Int, CGPoint) -> Void =
    {
        _, _ in
    }  /* Reports a card identity and updated global pointer           */

    var onCardDragEnded: (Int, Bool, CGPoint?) -> Void =
    {
        _, _, _ in
    }  /* Ends a card drag with commit intent and final pointer        */

    var cardDragToken = "" /* Board-session token shared by drag sources and drop surfaces */
    var onCardDrop: (CGPoint) -> Bool =
    {
        _ in
        false
    }  /* Commits a native drop at its global pointer position         */

    var cardMoveDestinations: [KanbanList] = [] /* Lists offered by the explicit card movement menu             */
    var onMoveCardToList:     (Int, Int) -> Void =
    {
        _, _ in
    }  /* Moves a selected card to the requested list identity         */

    @State private var inlineCaptureDraft = InlineListCaptureDraft()
    @State private var guidanceVisible = false
    @State private var guidanceFooterVisible: Bool?
    var onEditList:                           ((String, String, ItemPresentation) -> Bool)? = nil
    var isNamingNewList = false
    var onFinishNaming: () -> Void =
    {

    }

    var onOpenDayView: (() -> Void)? = nil
    @State private var opensDayAfterDismissal = false
    var boardAppearance: BoardAppearance = BoardAppearance()
    var onAppearance:    ((ItemAppearance?) -> Bool)? = nil
    var isCurrentDay = false
    var assignedDate: Date? = nil
    var datedTitle:   String? = nil
    var hidesPanelHeader = false
    var listActionsRequest = 0
    var onConsumeListActions: () -> Void =
    {

    }


    private var styledListTitle: AttributedString
    {

        var title = AttributedString(list.title)
        title.font = .title3.weight(.bold)
        if let datedTitle
        {

            var date = AttributedString(String(datedTitle.dropFirst(list.title.count)))
            date.font = .title3.weight(.regular).italic()
            date.foregroundColor = .secondary
            title.append(date)
        }

        return title
    }


    @State private var activeSheet: ActiveSheet? /* The currently active sheet presented modally        */
    /// Opens card creation after the active list-actions sheet has dismissed.
    @State private var opensNewCardAfterDismissal = false  /* Deferred creation request after another sheet closes */
    @State private var isWatching = false                  /* Indicates whether the user is watching the list      */
    private var effectiveAppearance: ItemAppearance
    {
        boardAppearance.resolved(list.appearance)
    }

    private var usesNoteList: Bool
    {
        hidesPanelHeader && list.singleListViewMode == .noteList
    }

    private var listTint: KanbanListTint
    {
        effectiveAppearance.listBackground ?? .neutral
    }

    @State private var editMode:     EditMode = .inactive  /* Indicates whether the list is in edit mode */
    @State private var deletingCard: KanbanCard?           /* Swipe deletion awaiting confirmation       */
    /// Measured height of the list header used to size its card collection.
    @State private var headerHeight: CGFloat = 72 /* Measured list-header height with an initial estimate */
    /// Measured card heights keyed by stable card identity.
    @State private var measuredCardHeights: [Int: CGFloat] = [:] /* Actual card-row heights keyed by identity */
    /// Dynamic Type scaling factor applied to card content.
    @ScaledMetric(relativeTo: .body) private var cardScale =
    1.0 /* Text-size scale applied to minimum card dimensions */
    /// Transient state indicating a list title is being held for reordering.
    @GestureState private var isHoldingList = false /* Long-press state enabling the list-reorder gesture */


    ///
    /// @fcn        KanbanListView.listReorderGesture
    /// @brief      Sequence a title-area hold into horizontal Board-list dragging
    /// @details    Requires a 0.45-second hold within twelve points, then reports zero-threshold
    ///             drag geometry in the WeekListsViewport coordinate space
    ///
    /// @return     (some Gesture) hold/drag sequence with transient holding-state updates
    /// @post       Successful holds report optional drag values; ending calls onListDragEnded
    ///
    private var canOpenDatedDay: Bool
    {
        assignedDate != nil && onOpenDayView != nil
    }

    private var dayOpeningLabel: String
    {

        assignedDate.map
        {

            (isCurrentDay ? "Today. Open " : "Open ") + $0.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        }
        ?? list.title
    }

    @ViewBuilder private var listSubtitle: some View
    {

        if canOpenDatedDay
        {

            Button
            {

                onOpenDayView?()
            }
            label:
            {

                Text(list.subtitle)
                .font(boardAppearance.resolvedSubtitleItalic(list: list.appearance) ? .caption.italic() : .caption)
                .foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dayOpeningLabel)
            .accessibilityHint("Opens this day's Day view. Back returns to this Week.")
        }
        else
        {

            Text(list.subtitle)
                .font(boardAppearance.resolvedSubtitleItalic(list: list.appearance) ? .caption.italic() : .caption)
                .foregroundStyle(.secondary).lineLimit(1)
        }

    }


    private var listReorderGesture: some Gesture
    {  /* Long-press then drag sequence for reordering this list */

        LongPressGesture(minimumDuration: 0.45, maximumDistance: 12)
        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("WeekListsViewport")))
        .updating($isHoldingList)
        {
            value, state, _ in
            if case .second(true, _) = value
            {


                state = true
            }

        }
        .onChanged
        {
            value in
            if case .second(true, let drag) = value
            {  /* Drag sample following a successful list long press */


                onListDragChanged(drag)
            }

        }
        .onEnded
        {
            _ in
            onListDragEnded()
        }

    }


    ///
    /// @fcn        KanbanListView.usesCompactCards(_:)
    /// @brief      Resolve whether an item uses compact Board detail
    /// @details    Applies the Board appearance resolver to the Card and List overrides without
    ///             changing their retained settings.
    ///
    /// @param[in]  card  Canonical item whose resolved preview or navigation context is requested
    ///
    /// @return     (Bool) true when the effective Card detail choice is compact
    ///
    private func usesCompactCards(_ card: KanbanCard) -> Bool
    {

        boardAppearance.resolvedCardDetail(card: card.appearance, list: list.appearance) == .compact
    }


    ///
    /// @fcn        KanbanListView.cardHeight
    /// @brief      Calculate a scaled card preview height
    /// @details    Uses the compact height or the selected presentation's minimum height before applying the card
    ///             scale.
    ///
    /// @param[in]  card  Card or note being inspected or changed
    ///
    /// @return     (CGFloat) compact or presentation-minimum height multiplied by the current card scale
    ///
    private func cardHeight(for card: KanbanCard) -> CGFloat
    {

        (usesCompactCards(card) ? 64 : presentation.minimumCardHeight) * cardScale
    }


    ///
    /// @fcn        KanbanListView.cardCollectionContentHeight
    /// @brief      Estimate the vertical space required by this list's rows
    /// @details    Uses measured card heights when available, scaled minimums for unmeasured rows,
    ///             44 points for dividers, and an allowance for the Add card row and spacing
    ///
    /// @return     (CGFloat) estimated collection height in points
    /// @post       No card order or layout state is modified
    ///
    private var cardCollectionContentHeight: CGFloat
    {  /* Total card content height including row spacing */

        let rowHeight = DaySections.visible(list.cards).reduce(CGFloat.zero)
        {

        height, card in /* Accumulated measured or estimated card heights  */
            height
            + (card.isSectionDivider
                ? 44
                : (usesNoteList
                    ? (measuredCardHeights[card.id] ?? 72)
                    : max(measuredCardHeights[card.id] ?? 0, cardHeight(for: card))) + (usesNoteList ? 0 : 8))
        }


        return max(88, rowHeight + 64 + (guidanceVisible ? 220 : 0))
    }


    ///
    /// @fcn        KanbanListView.cardCollectionHeight
    /// @brief      Fit the card collection within remaining panel space
    /// @details    Subtracts the measured header and 24-point bottom allowance from available height,
    ///             clamps remaining space to at least one point, and caps it by estimated content height
    ///
    /// @return     (CGFloat) visible card-collection height
    /// @post       Header measurement and card content remain unchanged
    ///
    private var cardCollectionHeight: CGFloat
    {  /* Card collection height capped by the remaining list viewport */

        let availableHeight = max(
            1, availableListHeight - (hidesPanelHeader ? 0 : headerHeight) - 24) /* Vertical space remaining after header and panel padding      */

        return min(cardCollectionContentHeight, availableHeight)
    }


    ///
    /// @fcn        KanbanListView.cardInsertionMarker(before:)
    /// @brief      Render the insertion boundary for the current card-drop target
    /// @details    Shows an accent line only when this list and boundary match the active
    ///             destination. The marker is noninteractive and hidden from accessibility.
    ///
    /// @param[in]  cardID  Board-local identity of the card being dragged or moved
    ///
    /// @return     (some View) insertion line or empty view for an inactive boundary
    ///
    @ViewBuilder
    private func cardInsertionMarker(before cardID: Int?) -> some View
    {


        if isCardDropTarget && dropBeforeCardID == cardID
        {


            Rectangle().fill(Color.accentColor).frame(height: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

    }


    private var cardDropSurface: some View
    {  /* Native drop receiver covering the list's card collection */

        BoardCardDropSurface(
            token: cardDragToken,
            isEnabled: editMode != .active,
            onChanged:
            {
                point in
                if let cardID = draggedCardID
                {  /* Active record identity paired with drop pointer updates */


                    onCardDragChanged(cardID, point)
                }

            },
            onDrop: onCardDrop)
    }


    ///
    /// @fcn        KanbanListView.body
    /// @brief      Compose a list panel with card rows, ordering, and action sheets
    /// @details    Measures the title header, supports hold-to-drag and accessible list movement,
    ///             and wires card completion/edit/archive/delete plus native row reordering.
    ///             List Actions Add card dismisses that sheet before presenting the creation form
    ///
    /// @return     (some View) tinted, height-limited list panel with modal actions
    /// @pre        The parent installs KanbanCard destinations and supplies consistent list callbacks
    /// @post       Content edits delegate to the parent; tint/watch and edit mode remain local.
    ///             Ending the hold resets drag through the parent callback
    ///
    var body: some View
    {  /* List panel and card collection */


        VStack(spacing: 0)
        {


            if !hidesPanelHeader
            {

                VStack(alignment: .leading, spacing: 0)
                {

                    HStack(alignment: .firstTextBaseline, spacing: 8)
                    {

                        ItemAppearanceMark(appearance: list.headerAppearance())
                        if isNamingNewList
                        {

                            InlineBoardListTitle(
                                list: list,
                                onSave:
                                {
                                    title in
                                    onEditList?(title, list.subtitle, list.newItemPresentation) == true
                                }, onFinish: onFinishNaming
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        }
                        else
                        {

                            Text(styledListTitle)
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        }

                        if isCurrentDay
                        {

                            Text("Today")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1).fixedSize()
                            .foregroundStyle(Color(red: 0.39, green: 0.25, blue: 0.05))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(WeekDayHighlight.gold.opacity(0.25), in: Capsule())
                            .accessibilityHidden(true)
                        }

                        Text("\(list.cards.filter { !$0.isSectionDivider } .count)")
                        .fixedSize()
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .gesture(listReorderGesture, including: isNamingNewList ? .none : .all)
                    .simultaneousGesture(
                        TapGesture().onEnded
                        {

                            if !isNamingNewList && canOpenDatedDay && !isHoldingList
                            {
                                onOpenDayView?()
                            }

                        }
                    )
                    .accessibilityElement(children: isNamingNewList ? .contain : .combine)
                    .modifier(
                        DayHeaderAccessibility(label: dayOpeningLabel, action: canOpenDatedDay ? onOpenDayView : nil)
                    )
                    .accessibilityHint(
                        canOpenDatedDay
                        ? "Opens this day. Touch and hold to drag this list instead."
                        : "Touch and hold to drag this list. Keep holding near either screen edge to move across the board."
                    )
                    .accessibilityAction(named: "Move earlier")
                    {

                        if canMoveEarlier
                        {


                            onMoveList(-1)
                        }

                    }

                    .accessibilityAction(named: "Move later")
                    {

                        if canMoveLater
                        {


                            onMoveList(1)
                        }

                    }

                    .onChange(of: isHoldingList)
                    {
                        _, holding in
                        if !holding
                        {


                            onListDragEnded()
                        }

                    }

                    .sensoryFeedback(.selection, trigger: isHoldingList)
                    HStack(spacing: 0)
                    {

                        VStack(alignment: .leading, spacing: 3)
                        {


                            if presentation == .standard
                            {


                                listSubtitle
                            }

                        }

                        .frame(maxWidth: .infinity, alignment: .leading)

                        if isWatching
                        {


                            Image(systemName: "eye.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }


                        Button
                        {

                            activeSheet = .listActions
                        }
                        label:
                        {


                            Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel("\(list.title) list actions")
                    }

                }

                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .background(isCurrentDay ? WeekDayHighlight.gold.opacity(0.16) : Color.clear)
                .itemBannerBackground(effectiveAppearance)
                .background
                {

                    GeometryReader
                    {
                        header in
                        Color.clear
                        .onAppear
                        {
                            headerHeight = header.size.height
                        }
                        .onChange(of: header.size.height)
                        {
                            _, height in
                            headerHeight = height
                        }

                    }

                }

            }


            List
            {

                SessionListGuidance(
                    list: list, labels: labelLibrary,
                    onReveal:
                    {
                        guidanceVisible = true
                    },
                    onPresentationChange:
                    {
                        guidanceFooterVisible = $0
                    }
                )
                .environment(\.defaultMinListRowHeight, 0)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ForEach(DaySections.visible(list.cards))
                {
                    card in

                    if card.isSectionDivider
                    {


                        DaySectionRow(
                            card: card, cards: list.cards, onUpdate: onUpdateCard,
                            onMove:
                            {
                                onMoveSection(card.id, $0)
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
                        .background
                        {

                            if editMode != .active && card.sectionHeading == nil
                            {

                                BoardCardDragSource(
                                    token: cardDragToken,
                                    onBegan:
                                    {
                                        onCardDragBegan(card.id, $0)
                                    },
                                    onChanged:
                                    {
                                        onCardDragChanged(card.id, $0)
                                    },
                                    onEnded:
                                    {
                                        onCardDragEnded(card.id, false, nil)
                                    })
                            }

                        }
                        .opacity(draggedCardID == card.id ? 0.45 : 1)
                        .overlay(alignment: .top)
                        {
                            cardInsertionMarker(before: card.id)
                        }
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
                        .contextMenu
                        {

                            ItemDisplayFormatMenu(card: card, onUpdate: onUpdateCard)
                            CardDestinationMenu(card: card)
                            Button("Delete Divider", systemImage: "trash", role: .destructive)
                            {
                                deletingCard = card
                            }

                        }

                        .accessibilityAction(named: "Delete Divider")
                        {
                            deletingCard = card
                        }
                        .listRowInsets(
                            usesNoteList
                            ? EdgeInsets()
                            : EdgeInsets(
                                top: boardAppearance.cardDetail == .compact ? 2 : 4, leading: 4,
                                bottom: boardAppearance.cardDetail == .compact ? 2 : 4, trailing: 4)
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    else
                    {


                        NavigationLink(value: card)
                        {


                            Group
                            {

                                if usesNoteList
                                {

                                    SingleListNoteRow(
                                        card: card, onToggle:
                                        {
                                            toggleCardTitle(card.id)
                                        },
                                        onArchive:
                                        {
                                            onArchiveCard(card.id)
                                        }, onDelete:
                                        {
                                            onDeleteCard(card.id)
                                        }, onUpdateCard: onUpdateCard)
                                }
                                else
                                {

                                    KanbanCardView(
                                        card: card,
                                        height: cardHeight(for: card),
                                        displaySettings: displaySettings,
                                        cardBackground: boardAppearance.cardBackground,
                                        compactCards: usesCompactCards(card),
                                        titleColor: boardAppearance.resolvedTitleColor(
                                            card: card.appearance, list: list.appearance),
                                        supportingTextColor: boardAppearance.resolvedTextColor(
                                            card: card.appearance, list: list.appearance),
                                        listedOnDate: assignedDate,
                                        presentation: presentation,
                                        labelLibrary: labelLibrary,
                                        onUpdateCard: onUpdateCard,
                                        onDeleteCard:
                                        {
                                            onDeleteCard(card.id)
                                        },
                                        onArchiveCard:
                                        {
                                            onArchiveCard(card.id)
                                        }
                                    )
                                    {

                                        toggleCardTitle(card.id)
                                    }

                                }

                            }
                            .background
                            {

                                GeometryReader
                                {
                                    geometry in
                                    Color.clear.preference(
                                        key: BoardCardHeightPreferenceKey.self,
                                        value: [card.id: geometry.size.height]
                                    )
                                }

                            }

                        }

                        .buttonStyle(.plain)
                        .modifier(HideNavigationLinkIndicator())
                        .id(card.id)
                        .modifier(DaySectionRail(cardID: card.id, cards: list.cards))
                        .background
                        {

                            if editMode != .active
                            {


                                BoardCardDragSource(
                                    token: cardDragToken,
                                    onBegan:
                                    {
                                        onCardDragBegan(card.id, $0)
                                    },
                                    onChanged:
                                    {
                                        onCardDragChanged(card.id, $0)
                                    },
                                    onEnded:
                                    {
                                        onCardDragEnded(card.id, false, nil)
                                    })
                            }

                        }
                        .accessibilityActions
                        {

                            ForEach(cardMoveDestinations)
                            {
                                list in
                                Button("Move to \(list.title)")
                                {
                                    onMoveCardToList(card.id, list.id)
                                }

                            }

                        }

                        .opacity(draggedCardID == card.id ? 0.45 : 1)
                        .overlay(alignment: .top)
                        {
                            cardInsertionMarker(before: card.id)
                        }
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
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .background
                        {

                            if !hidesPanelHeader
                            {
                                BoardCardSwipeZone(enabled: editMode != .active)
                            }

                        }
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
                        list.cards, sourceOffsets: sourceOffsets, destinationOffset: destinationOffset)
                    else
                    {
                        return
                    }

                    onMoveCard(move.id, move.index)
                }
                .moveDisabled(editMode != .active)


                InlineListCapture(
                    list: list, draft: $inlineCaptureDraft,
                    textColor: boardAppearance.resolvedAddItemTextColor(list: list.appearance, title: list.title)?.color
                    ?? .primary,
                    isPresented: guidanceFooterVisible
                    ?? (!list.cards.isEmpty || DefaultListTutorial.guidance(for: list.title) == nil),
                    onCreate: onAddCard,
                    onOpenComposer:
                    {
                        activeSheet = .newCard
                    }
                )
                .background
                {
                    cardDropSurface
                }
                .overlay(alignment: .top)
                {
                    cardInsertionMarker(before: nil)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .contentMargins(.bottom, cardCollectionContentHeight > cardCollectionHeight ? 80 : 0, for: .scrollContent)
            .background(.clear)
            .frame(height: cardCollectionHeight)
            .background(BoardViewportScrollProbe(memory: viewportMemory, key: "list:\(list.id)"))
            .modifier(RevealCreatedContent(lists: [list]))
            .onPreferenceChange(BoardCardHeightPreferenceKey.self)
            {
                heights in
                var updated = measuredCardHeights
                updated.merge(heights, uniquingKeysWith:
                    {
                        _, latest in
                        latest
                    })
                if updated != measuredCardHeights
                {
                    measuredCardHeights = updated
                }

            }

            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }

        .background
        {
            (usesNoteList ? Color(.systemBackground) : listTint.color).opacity(
                effectiveAppearance.resolvedListBackgroundOpacity)
            if let surface = list.appearance?.studioSurface
            {
                StudioSurfaceView(surface: surface)
            }
        }
        .overlay
        {

            RoundedRectangle(cornerRadius: 18)
            .stroke(isCardDropTarget ? Color.accentColor : .clear, lineWidth: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        .overlay
        {

            if isCurrentDay && !hidesPanelHeader
            {

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isCardDropTarget ? Color.accentColor : WeekDayHighlight.gold, lineWidth: 4)
                .allowsHitTesting(false).accessibilityHidden(true)
            }

        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(usesNoteList ? 0 : 0.18), radius: 10, y: 5)
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

            Button("Delete \(deletingCard?.presentation.title ?? "item")", role: .destructive)
            {

                if let target = deletingCard,
                list.cards.contains(where:
                    {
                        $0.id == target.id && $0.createdAt == target.createdAt
                    })
                {

                    onDeleteCard(target.id)
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

        .onChange(of: listActionsRequest, initial: true)
        {
            _, request in
            guard request > 0 else
            {
                return
            }

            activeSheet = .listActions
            onConsumeListActions()
        }
        .onChange(of: ListCheckmarkReset.values(in: list))
        {
            _, _ in
            if checkmarkReset?.canRestore(list) == false
            {
                checkmarkReset = nil
            }

        }
        .environment(\.studioCardSurface, list.appearance?.studioCardSurface ?? boardAppearance.studioCardSurface)
        .environment(\.inheritedSubtitleItalic, boardAppearance.resolvedSubtitleItalic(list: list.appearance))
        .onDisappear
        {
            checkmarkReset = nil
        }
        .sheet(
            item: $activeSheet,
            onDismiss:
            {

                if opensDayAfterDismissal
                {

                    opensDayAfterDismissal = false
                    onOpenDayView?()
                    return
                }

                guard opensNewCardAfterDismissal else
                {


                    return
                }

                opensNewCardAfterDismissal = false
                activeSheet = .newCard
            }
        )
        {
            presentedSheet in
            switch presentedSheet
            {

            case .listActions:
                KanbanListActionsSheet(
                    checkmarkReset: $checkmarkReset,
                    onUpdateCard: onUpdateCard,
                    list: list,
                    canMoveEarlier: canMoveEarlier,
                    canMoveLater: canMoveLater,
                    isWatching: $isWatching,
                    onAddCard:
                    {

                        opensNewCardAfterDismissal = true
                        activeSheet = nil
                    },
                    onCopyList: onCopyList,
                    onMoveToBoard: onMoveToBoard,
                    onMoveList: onMoveList,
                    onSortList: onSortList,
                    cardEditMode: $editMode,
                    onArchiveCompleted: onArchiveCompleted,
                    archivedCards: $archivedCards,
                    onRestoreArchivedCard: onRestoreArchivedCard,
                    onDeleteArchivedCard: onDeleteArchivedCard,
                    onArchiveList: onArchiveList,
                    onDeleteList: onDeleteList,
                    onEditList: onEditList,
                    onAppearance: onAppearance,
                    inheritedAddItemTextColor: boardAppearance.resolvedAddItemTextColor(list: nil, title: list.title)?
                    .color ?? .primary,
                    onOpenDayView: onOpenDayView == nil
                    ? nil
                    :
                    {

                        opensDayAfterDismissal = true
                        activeSheet = nil
                    }
                )
                .databaseActivityOverlay()
            case .newCard:
                ListItemComposer(
                    list: list, draftKey: ListCreationDraft.key(collectionID: draftCollectionID, listID: list.id),
                    initialTitle: inlineCaptureDraft.title,
                    onCreate:
                    {
                        capture in
                        guard onAddCard(capture) else
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

    }

}
