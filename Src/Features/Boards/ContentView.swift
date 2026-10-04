// -------------------------------------------------------------------------------------------------
// @file       ContentView.swift
// @brief      Kanban board screen and reusable board views
// @details    Defines the board container, lists, cards, and navigation into card details
//
// @notes      Views remain composable and keep presentation logic close to the rendered component
//
// @section    Opens
//     Consider more board\ specific naming to file
//
// -------------------------------------------------------------------------------------------------
import SwiftUI

extension Binding where Value == [KanbanList] {
    var activeLists: Binding<[KanbanList]> {
        Binding(
            get: { wrappedValue.filter { !$0.isArchived } },
            set: { wrappedValue = $0 + wrappedValue.filter(\.isArchived) }
        )
    }

    var archivedLists: Binding<[KanbanList]> {
        Binding(
            get: { wrappedValue.filter(\.isArchived) },
            set: { archived in
                wrappedValue = wrappedValue.filter { !$0.isArchived } + archived.map { list in
                    var archivedList = list
                    archivedList.isArchived = true
                    return archivedList
                }
            }
        )
    }
}


///
/// Stores optional presentation controls for cards on the Board
///
/// @section    Purpose
///     Keep card progress, comment, and date visibility preferences together
///
struct BoardDisplaySettings {
    var showChecklistProgress = true    /* Display checklist progress on cards */
    var showCommentCounts     = true    /* Display comment counts on cards     */
    var showDueDateBadges     = true    /* Display due date badges on cards    */
}

private struct BoardListCenterPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}


// -------------------------------------- MARK: - Board View ------------------------------------ //

///
/// Displays the horizontally scrollable Plenact kanban board
///
/// @section    Purpose
///     Install the board background, header, paged list surface, and navigation path into card details
///
struct ContentView: View {

    @Binding private var lists: [KanbanList]                                                /* Shared kanban board lists                        */
    @Binding private var archivedLists: [KanbanList]
    @Binding private var boardTargetListID: Int?                                            /* Requested list to reveal after board navigation  */
    @Binding private var boardTargetCardID: Int?
    @Binding private var savedCardIDs: Set<Int>                                             /* Locally bookmarked card identities                */
    let onListViewed: (Int) -> Void
    let boardTitle: String
    let boardSubtitle: String
    let allowsAddingLists: Bool
    let onClose: (() -> Void)?
    let onArchiveBoard: (() -> Void)?
    let onListsChanged: @MainActor ([KanbanList]) -> Void
    let retainedAttachmentLists: () -> [KanbanList]
    @State private var showsCalendar = false
    @State private var showsArchivedLists = false
    @State private var navigationPath = NavigationPath()
    @State private var lastReportedVisibleListID: Int?
    @State private var draggedListID: Int?
    @State private var listCenters: [Int: CGFloat] = [:]
    @State private var listDragLocation: CGFloat?
    @State private var listDragGrabOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var labelLibrary                  = LabelLibraryStore.load()             /* Label library containing all available labels    */
    @State private var displaySettings               = BoardDisplaySettings()               /* Board display settings                           */
    @State private var memberColors: [String: Color] = [:]                                  /* Mapping of member names to their assigned colors */
    @State private var currentUserName               = "Justin Reina"                       /* Current user's name                              */


    ///
    /// @fcn        ContentView.init(lists:boardTargetListID:savedCardIDs:)
    /// @brief      Initialize the Board view with shared list state and an optional navigation target
    /// @details    The app root owns the persisted board snapshot; previews may omit the target binding
    ///
    /// @param[in]  lists                Binding to the board's shared list collection
    /// @param[in]  boardTargetListID    Optional list ID to reveal after navigation from Today
    /// @param[in]  savedCardIDs         Local card identities shown in the Saved destination
    ///
    /// @return     (ContentView) configured kanban board screen
    ///
    /// @pre        lists contains the board state to display
    /// @post       Board edits update the shared collection and requested navigation remains observable
    ///
    init(
        lists: Binding<[KanbanList]>,
        archivedLists: Binding<[KanbanList]> = .constant([]),
        boardTargetListID: Binding<Int?> = .constant(nil),
        boardTargetCardID: Binding<Int?> = .constant(nil),
        savedCardIDs: Binding<Set<Int>> = .constant([]),
        onListViewed: @escaping (Int) -> Void = { _ in },
        boardTitle: String = "Plenact",
        boardSubtitle: String = "Work Week Board",
        allowsAddingLists: Bool = true,
        onClose: (() -> Void)? = nil,
        onArchiveBoard: (() -> Void)? = nil,
        onListsChanged: @escaping @MainActor ([KanbanList]) -> Void = KanbanBoardPersistence.saveListsInBackground,
        retainedAttachmentLists: @escaping () -> [KanbanList] = {
            PersonalCollectionStore.load().flatMap(\.lists) + (ExampleLoadUndoStore.load()?.lists ?? [])
        }
    ) {
        _lists = lists
        _archivedLists = archivedLists
        _boardTargetListID = boardTargetListID
        _boardTargetCardID = boardTargetCardID
        _savedCardIDs = savedCardIDs
        self.onListViewed = onListViewed
        self.boardTitle = boardTitle
        self.boardSubtitle = boardSubtitle
        self.allowsAddingLists = allowsAddingLists
        self.onClose = onClose
        self.onArchiveBoard = onArchiveBoard
        self.onListsChanged = onListsChanged
        self.retainedAttachmentLists = retainedAttachmentLists
    }

    private func openPendingBoardTarget(using listProxy: ScrollViewProxy) {
        guard let targetListID = boardTargetListID,
              lists.contains(where: { $0.id == targetListID }) else {
            boardTargetListID = nil
            boardTargetCardID = nil
            return
        }

        listProxy.scrollTo(targetListID, anchor: .center)

        if let targetCardID = boardTargetCardID,
           let card = lists.first(where: { $0.id == targetListID })?.cards.first(where: { $0.id == targetCardID }) {
            navigationPath = NavigationPath()
            navigationPath.append(card)
        }

        boardTargetListID = nil
        boardTargetCardID = nil
    }


    ///
    /// @fcn        ContentView.activeMembers
    /// @brief      Return unique users assigned to active cards
    /// @details    Traverses cards in board order, excludes divider items, trims surrounding whitespace,
    ///             and retains the first occurrence of each member name using case-insensitive matching
    ///
    /// @return     ([String]) ordered member names currently assigned to non-divider cards
    ///
    /// @pre        lists contains the current in-memory board state
    /// @post       No board data is modified; duplicate and empty names are omitted from the result
    ///
    private var activeMembers: [String] { /* Unique names assigned to non-divider cards */

        var seenMembers: Set<String> = []       /* Track unique members to avoid duplicates */

        return lists
            .flatMap(\.cards)
            .filter { !$0.isSectionDivider }
            .flatMap(\.members)
            .compactMap { assignee in

                let trimmedMember    = assignee.displayName.trimmingCharacters(in: .whitespacesAndNewlines) /* Display name */
                let normalizedMember = trimmedMember.lowercased()                               /* Normalize the member name for case-insensitive comparison */

                guard !trimmedMember.isEmpty, seenMembers.insert(normalizedMember).inserted else {
                    return nil
                }

                return trimmedMember
            }
    }

    
    ///
    /// @fcn        ContentView.renameMember(from:to:)
    /// @brief      Rename a member across the board
    /// @details    Replaces matching card assignments and comment authors, updates the current-user name
    ///             when applicable, and migrates the member's icon color to the new normalized key
    ///
    /// @param[in]  currentName  Existing member name to replace
    /// @param[in]  proposedName Proposed new name; surrounding whitespace is trimmed
    ///
    /// @return     (Void) updates card assignments, authored comments, current-user display, and color mapping
    ///
    /// @pre        currentName identifies the member being renamed
    /// @post       Matching names are replaced; duplicate assignments within each card are removed
    ///
    /// @note       An empty proposed name is ignored; if the new name already has a color, that
    ///             color is retained
    ///
    private func renameMember(from currentName: String, to proposedName: String) {

        let updatedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines) /* Trimmed replacement name */

        guard !updatedName.isEmpty else { return }

        let currentKey = currentName.lowercased()       /* Normalized key for the current member name */
        let updatedKey = updatedName.lowercased()       /* Normalized key for the updated member name */    

        for listIndex in lists.indices {

            for cardIndex in lists[listIndex].cards.indices {

                var updatedCard            = lists[listIndex].cards[cardIndex]  /* Copy of the current card for in-place updates     */
                var seenNames: Set<String> = []                                 /* Track unique member names within the current card */

                updatedCard.members = updatedCard.members.compactMap { assignee in

                    let trimmedMember = assignee.displayName.trimmingCharacters(in: .whitespacesAndNewlines) /* Existing display name */
                    let renamedMember = assignee.kind == .manual && trimmedMember.lowercased() == currentKey /* Match only manual names */
                        ? updatedName
                        : trimmedMember /* Name retained or updated for this assignment */
                    let normalizedName = assignee.kind == .registeredUser /* Namespace stable IDs separately from names */
                        ? "user:\(assignee.userID ?? assignee.id.uuidString)"
                        : "manual:\(renamedMember.lowercased())" /* Stable deduplication key */

                    guard !renamedMember.isEmpty, seenNames.insert(normalizedName).inserted else {
                        return nil
                    }

                    return CardAssignee(
                        id:          assignee.id,
                        kind:        assignee.kind,
                        userID:      assignee.userID,
                        displayName: renamedMember
                    )
                }

                updatedCard.comments = updatedCard.comments.map { comment in

                    guard comment.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentKey else {
                        return comment
                    }

                    return KanbanComment(
                        id:        comment.id,
                        author:    updatedName,
                        body:      comment.body,
                        createdAt: comment.createdAt
                    )
                }

                lists[listIndex].cards[cardIndex] = updatedCard
            }
        }

        if currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentKey {
            currentUserName = updatedName
        }

        if currentKey != updatedKey, let existingColor = memberColors.removeValue(forKey: currentKey) { /* Preserve the old icon color */
            memberColors[updatedKey] = memberColors[updatedKey] ?? existingColor
        }
    }


    ///
    /// @fcn        ContentView.removeMember(_:)
    /// @brief      Remove a member from board assignments
    /// @details    Removes matching names from every card and clears their board icon color while
    ///             preserving historical comments
    ///
    /// @param[in]  memberName  Member name to remove; comparison ignores surrounding whitespace and case
    ///
    /// @return     (Void) updates the board and member color state
    ///
    /// @pre        memberName identifies a member currently assigned to at least one card
    /// @post       The member no longer appears in card assignments; existing comments remain unchanged
    ///
    private func removeMember(_ memberName: String) {

        let normalizedMemberName = memberName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() /* Normalized removal key */

        guard !normalizedMemberName.isEmpty else { return }

        for listIndex in lists.indices {

            for cardIndex in lists[listIndex].cards.indices {

                lists[listIndex].cards[cardIndex].members.removeAll { member in

                    member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedMemberName
                }
            }
        }

        memberColors.removeValue(forKey: normalizedMemberName)

        if currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedMemberName {

            currentUserName = "You"
        }
    }


    ///
    /// @fcn        ContentView.setMemberColor(_:color:)
    /// @brief      Store the shared icon color for a member
    /// @details    Writes the selected color under the member's lowercased name so all matching
    ///             icons resolve consistently
    ///
    /// @param[in]  memberName  Name of the member whose icon color is being changed
    /// @param[in]  color       New color selected for that member
    ///
    /// @return     (Void) updates the board-level member color mapping
    ///
    /// @pre        memberName identifies an active member
    /// @post       Views using the normalized member key receive the selected color
    ///
    private func setMemberColor(_ memberName: String, color: Color) {
        memberColors[memberName.lowercased()] = color
    }


    ///
    /// @fcn        ContentView.addList
    /// @brief      Append a new empty list to the board
    /// @details    Assigns the next available list identifier and generates a title that does not
    ///             duplicate an existing list name
    ///
    /// @return     (Void) updates the board's in-memory list collection
    ///
    /// @pre        The board list collection has been initialized
    /// @post       A uniquely identified empty list is appended to the board
    ///
    private func addList() {
        let nextListID     = ((lists + archivedLists).map(\.id).max() ?? -1) + 1 /* Board-wide next list ID */
        let existingTitles = Set(lists.map { $0.title.lowercased() }) /* Normalized current titles */
        var newTitle       = "New List" /* First candidate list name */
        var suffix         = 2 /* Duplicate-title suffix */

        while existingTitles.contains(newTitle.lowercased()) {
            newTitle = "New List \(suffix)"
            suffix  += 1
        }

        lists.append(KanbanList(id: nextListID, title: newTitle, cards: []))
    }


    ///
    /// @fcn        ContentView.safeFrameDimension(_:subtracting:)
    /// @brief      Return a finite positive frame dimension after applying an inset
    /// @details    Subtracts the requested inset and substitutes a one-point minimum when the
    ///             result is non-finite or too small
    ///
    /// @param[in]  dimension  Proposed source dimension from the parent geometry
    /// @param[in]  inset      Amount to subtract from the source dimension
    ///
    /// @return     (CGFloat) finite dimension of at least one point
    ///
    /// @pre        No input range is required; non-finite and undersized results are handled
    /// @post       The result is finite and greater than zero
    ///
    private func safeFrameDimension(_ dimension: CGFloat, subtracting inset: CGFloat) -> CGFloat {

        let availableDimension = (dimension - inset) /* Dimension remaining after the inset */
        
        guard availableDimension.isFinite else { return 1 }
        
        return max(availableDimension, 1)
    }


    ///
    /// @fcn        ContentView.addCard(to:title:description:)
    /// @brief      Add a completed card form to the end of the selected list
    /// @details    Allocates a board-wide unique card identifier and stores the supplied title and description
    ///
    /// @param[in]  listID  Stable identifier of the list receiving the card
    /// @param[in]  title   User-entered card title
    /// @param[in]  description User-entered card description
    ///
    /// @return     (Void) updates the matching list in the board state
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The new card appears as the last card in the selected list
    ///
    private func addCard(to listID: Int, title: String, description: String) {

        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* Destination list index */

        let nextCardID  = ((lists + archivedLists).flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1 /* Board-wide next card ID */
        var updatedList = lists[listIndex] /* Mutable destination-list copy */

        /// Append the new card to the list's cards array
        updatedList.cards.append(
            KanbanCard(
                id:                  nextCardID,
                word:                title,
                listTitle:           updatedList.title,
                isDivider:           KanbanCard.isDividerTitle(title),
                descriptionOverride: description
            )
        )

        lists[listIndex] = updatedList
    }


    ///
    /// @fcn        ContentView.deleteCard(in:cardID:)
    /// @brief      Remove one card from a board list
    /// @details    Finds the list by its stable identifier and removes the card matching its identifier
    ///
    /// @param[in]  listID  Stable identifier of the list containing the card
    /// @param[in]  cardID  Stable identifier of the card to delete
    ///
    /// @return     (Void) updates the selected list in the board state
    ///
    /// @pre        listID identifies a list in the board
    /// @post       The matching card no longer appears in that list
    ///
    private func deleteCard(in listID: Int, cardID: Int) {

        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* List containing the card */

        lists[listIndex].cards.removeAll { $0.id == cardID }

        pruneUnreferencedAttachments()
    }


    ///
    /// @fcn        ContentView.moveCard(in:cardID:toIndex:)
    /// @brief      Reorder one card within a board list
    /// @details    Removes the source card and inserts it at the target card's position
    ///
    /// @param[in]  listID    Stable identifier of the list to reorder
    /// @param[in]  cardID           Stable identifier of the card being moved
    /// @param[in]  destinationIndex Zero-based destination index in the list
    ///
    /// @return     (Void) updates the card order in the selected list
    ///
    /// @pre        listID identifies a list containing cardID
    /// @post       The card occupies the requested destination index within the list
    ///
    private func moveCard(in listID: Int, cardID: Int, toIndex destinationIndex: Int) {

        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* List being reordered */

        var cards = lists[listIndex].cards /* Mutable card-order copy */

        guard let sourceIndex = cards.firstIndex(where: { $0.id == cardID }), !cards.isEmpty else { return } /* Original card position */

        let safeDestinationIndex = min(max(destinationIndex, 0), cards.count - 1) /* Clamped insertion position */

        guard sourceIndex != safeDestinationIndex else { return }

        let movedCard = cards.remove(at: sourceIndex) /* Card removed before reinsertion */

        cards.insert(movedCard, at: safeDestinationIndex)

        // Update the list with the reordered cards, animating the change for a smooth user experience
        withAnimation(.easeInOut(duration: 0.2)) {
            lists[listIndex].cards = cards
        }
    }


    ///
    /// @fcn        ContentView.copyList(with:)
    /// @brief      Insert a copy of the selected list beside its source
    /// @details    Creates new list and card identifiers while copying card content and current card state
    ///
    /// @param[in]  listID  Stable identifier of the list to copy
    ///
    /// @return     (Void) inserts the copied list immediately after the source list
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The board contains a distinct copy with unique list and card identifiers
    ///
    private func copyList(with listID: Int) {

        guard let sourceIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* Source list position */

        let source       = lists[sourceIndex] /* Source list snapshot */
        let copiedTitle  = "\(source.title) Copy" /* New list display title */
        let copiedListID = ((lists + archivedLists).map(\.id).max() ?? -1) + 1 /* New list identity */
        var nextCardID   = ((lists + archivedLists).flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1 /* Next unique card identity */

        let copiedCards = source.cards.map { card /* Source card being copied */ in
        
            let copy = KanbanCard( /* New card retaining source content */
                id:                   nextCardID,
                word:                 card.word,
                listTitle:            copiedTitle,
                isDivider:            card.isSectionDivider,
                isTitleChecked:       card.isTitleChecked,
                startDate:            card.startDate,
                dueDate:              card.dueDate,
                checklists:           card.checklists,
                comments:             card.comments,
                members:              card.members,
                labelIDs:             card.labelIDs,
                attachments:          card.attachments,
                dismissedActivityIDs: card.dismissedActivityIDs,
                descriptionOverride:  card.descriptionOverride,
                subtitleOverride:     card.subtitleOverride
            )

            nextCardID += 1
            
            return copy
        }

        lists.insert(KanbanList(id: copiedListID, title: copiedTitle, cards: copiedCards), at: sourceIndex + 1)
    }


    ///
    /// @fcn        ContentView.moveList(with:by:)
    /// @brief      Move a list relative to its current board position
    /// @details    Removes the matching list and reinserts it at the index specified by the offset
    ///
    /// @param[in]  listID  Stable identifier of the list to move
    /// @param[in]  offset  Number of positions to move; negative moves earlier and positive moves later
    ///
    /// @return     (Void) reorders the board when the destination index is valid
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The list occupies its destination index, or the board is unchanged for an invalid destination
    ///
    private func moveList(with listID: Int, by offset: Int) {

        guard let sourceIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* Source list position */

        let destinationIndex = sourceIndex + offset /* Requested destination position */

        guard lists.indices.contains(destinationIndex) else { return }

        BoardListReordering.move(listID, to: destinationIndex, in: &lists)
    }

    private func updateListDrag(_ listID: Int, value: DragGesture.Value?) {
        if draggedListID == nil {
            draggedListID = listID
        }
        guard draggedListID == listID, let value else { return }
        if listDragLocation == nil {
            listDragGrabOffset = value.startLocation.x - (listCenters[listID] ?? value.startLocation.x)
        }
        listDragLocation = value.location.x

        guard let source = lists.firstIndex(where: { $0.id == listID }),
              let center = listCenters[listID] else { return }
        let direction = value.location.x > center ? 1 : -1
        let destination = source + direction
        guard lists.indices.contains(destination),
              let targetCenter = listCenters[lists[destination].id],
              direction > 0 ? value.location.x > targetCenter : value.location.x < targetCenter else { return }
        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2)) {
            _ = BoardListReordering.move(listID, to: destination, in: &lists)
        }
    }

    private func endListDrag(_ listID: Int) {
        guard draggedListID == listID else { return }
        draggedListID = nil
        listDragLocation = nil
        listDragGrabOffset = 0
    }

    private func listDragOffset(for listID: Int) -> CGFloat {
        guard draggedListID == listID, let location = listDragLocation,
              let center = listCenters[listID] else { return 0 }
        return location - center - listDragGrabOffset
    }


    ///
    /// @fcn        ContentView.sortList(with:ascending:)
    /// @brief      Sort a list's cards by their titles
    /// @details    Uses localized standard comparison to order card titles in the requested direction
    ///
    /// @param[in]  listID     Stable identifier of the list to sort
    /// @param[in]  ascending  Whether to sort from A to Z; false sorts from Z to A
    ///
    /// @return     (Void) replaces the card order in the matching board list
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       Cards in the list are ordered by title in the requested direction
    ///
    private func sortList(with listID: Int, ascending: Bool) {

        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* List being sorted */

        var updatedList = lists[listIndex] /* Mutable list copy */

        var sortedCards:    [KanbanCard] = [] /* Cards emitted in sorted order */
        var currentSection: [KanbanCard] = [] /* Cards before the next divider */

        // Iterate through each card in the list, grouping them by sections and sorting within each section
        for card in updatedList.cards { /* Preserve divider-separated sections */

            guard card.isSectionDivider else {
                currentSection.append(card)
                continue
            }

            // When encountering a section divider, sort the current section and append it to the sorted 
            // cards before adding the divider itself
            sortedCards.append(contentsOf: currentSection.sorted {
                let comparison = $0.word.localizedStandardCompare($1.word) /* Locale-aware title ordering */
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            })
            currentSection.removeAll()
            sortedCards.append(card)
        }

        sortedCards.append(contentsOf: currentSection.sorted {

            let comparison = $0.word.localizedStandardCompare($1.word) /* Locale-aware title ordering */

            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        })

        updatedList.cards = sortedCards
        
        lists[listIndex] = updatedList
    }


    ///
    /// @fcn        ContentView.archiveCompletedCards(in:)
    /// @brief      Move completed cards into the list's saved archive
    /// @details    Retains complete card records and attachments for later restoration
    ///
    /// @param[in]  listID  Stable identifier of the list to update
    ///
    /// @return     (Void) updates the matching list in the board state
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       Cards marked complete no longer appear in the active list
    ///
    private func archiveCompletedCards(in listID: Int) {

        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return } /* List being archived */

        lists[listIndex].archiveCompletedCards()
    }

    private func restoreArchivedCard(in listID: Int, cardID: Int) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[listIndex].restoreArchivedCard(id: cardID)
    }

    private func archiveCard(_ cardID: Int) {
        guard let listIndex = lists.firstIndex(where: { $0.cards.contains(where: { $0.id == cardID }) }) else { return }
        lists[listIndex].archiveCard(id: cardID)
    }

    ///
    /// @fcn        ContentView.archiveList(with:)
    /// @brief      Remove a list from the active board
    /// @details    Retains the list and all its cards for restoration through Board options
    ///
    /// @param[in]  listID  Stable identifier of the list to remove
    ///
    /// @return     (Void) updates the board's in-memory list collection
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The list and its cards no longer appear on the active board
    ///
    private func archiveList(with listID: Int) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        var archived = lists[index]
        archived.isArchived = true
        archivedLists.append(archived)
        lists.removeAll { $0.id == listID }
    }

    private func restoreArchivedList(_ listID: Int) {
        guard let index = archivedLists.firstIndex(where: { $0.id == listID }) else { return }
        var restored = archivedLists[index]
        restored.isArchived = false
        lists.append(restored)
        archivedLists.removeAll { $0.id == listID }
    }


    ///
    /// @fcn        ContentView.toggleCardTitle
    /// @brief      Toggle the selected state for one board card title checkbox
    /// @details    Finds the matching card within the selected list and flips its persisted
    ///             checked state so the root board view and detail view stay in sync
    ///
    /// @param[in]  listIndex   Zero-based index of the list containing the card
    /// @param[in]  cardID      Stable identifier of the card whose title checkbox is toggled
    ///
    /// @return     (Void) updates the local board state in place
    ///
    /// @pre        listIndex must reference a valid list in the board state
    /// @post       The selected card's checked state is inverted and the board re-renders
    ///
    private func toggleCardTitle(in listIndex: Int, cardID: Int) {

        guard lists.indices.contains(listIndex) else { return }

        var updatedList     = lists[listIndex] /* Mutable list copy */

        guard let cardIndex = updatedList.cards.firstIndex(where: { $0.id == cardID }) else { return } /* Matching card position */

        var updatedCard     = updatedList.cards[cardIndex] /* Mutable card copy */

        updatedCard.isTitleChecked.toggle()

        updatedList.cards[cardIndex] = updatedCard
        lists[listIndex]             = updatedList
    }


    ///
    /// @fcn        ContentView.updateCard
    /// @brief      Replace an existing card with the latest edited version
    /// @details    Scans the current board data for the matching card identifier and stores the
    ///             latest value so navigation changes persist across list and detail views
    ///
    /// @param[in]  updatedCard   Card instance containing the latest state to save
    ///
    /// @return     (Void) updates the board's in-memory card collection
    ///
    /// @pre        updatedCard must contain a valid id that exists within the board state
    /// @post       The matching card in the list state reflects the updated values
    ///
    private func updateCard(_ updatedCard: KanbanCard) {

        for listIndex in lists.indices {

            var updatedList = lists[listIndex] /* Mutable list being searched */

            guard let cardIndex = updatedList.cards.firstIndex(where: { $0.id == updatedCard.id }) else { /* Matching card position */
                continue
            }

            updatedList.cards[cardIndex] = updatedCard
            lists[listIndex]             = updatedList

            pruneUnreferencedAttachments()

            return
        }
    }


    ///
    /// @fcn        ContentView.pruneUnreferencedAttachments
    /// @brief      Remove stored photo files that are no longer assigned to any card
    /// @details    Collects attachment filenames referenced by the current board and asks the attachment store
    ///             to remove files outside that set
    ///
    /// @return     (Void) cleans unreferenced image files from the app's attachment directory
    ///
    /// @pre        lists reflects the current board state after a card or list mutation
    /// @post       Files referenced by cards remain available; unreferenced files are removed when possible
    ///
    /// @note       File-system cleanup failures are ignored by CardAttachmentStore
    ///
    private func pruneUnreferencedAttachments() {
        
        let referencedFileNames = Set( /* Attachment files retained by current Board cards */
            (lists + archivedLists + retainedAttachmentLists())
                .flatMap(\.allCards)
                .flatMap { $0.attachments ?? [] }
                .compactMap(\.fileName)
        )

        CardAttachmentStore.removeUnreferencedFiles(keeping: referencedFileNames)
    }


    ///
    /// @fcn        ContentView.moveCard(_:toListID:)
    /// @brief      Move an existing card into a different board list
    /// @details    Finds the card by its stable identifier, removes it from its current list,
    ///             updates its list title, and appends it to the destination list while retaining its state
    ///
    /// @param[in]  cardID             Stable identifier of the card being moved
    /// @param[in]  destinationListID  Stable identifier of the list receiving the card
    ///
    /// @return     (Void) updates the source and destination lists in the board state
    ///
    /// @pre        cardID exists in a board list and destinationListID identifies another list
    /// @post       The card is removed from its source list and appears at the end of the destination list
    ///             with its existing card data preserved
    ///
    /// @note       The operation leaves board state unchanged if the card or destination is missing,
    ///             or if the destination is the card's current list
    ///
    private func moveCard(_ cardID: Int, toListID destinationListID: Int) {

          guard let sourceListIndex = lists.firstIndex(where: { list /* Candidate source list */ in
                  list.cards.contains(where: { $0.id == cardID })
              }), /* List currently containing the card */

              let destinationListIndex = lists.firstIndex(where: { $0.id == destinationListID }), /* Requested destination list */

              sourceListIndex != destinationListIndex,

              let cardIndex = lists[sourceListIndex].cards.firstIndex(where: { $0.id == cardID }) else { /* Card position in the source list */

            return
        }

        var movedCard       = lists[sourceListIndex].cards.remove(at: cardIndex) /* Card removed before transfer */
        movedCard.listTitle = lists[destinationListIndex].title
        
        lists[destinationListIndex].cards.append(movedCard)
    }
    

    /// Builds the board scene and its horizontally scrollable list collection.
    var body: some View { /* Board scene and list collection */

        NavigationStack(path: $navigationPath) {
            
            GeometryReader { screen in

                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.18, blue: 0.25), Color(red: 0.22, green: 0.34, blue: 0.38)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {

                        BoardHeader(
                            settings:         $displaySettings,
                            activeMembers:    activeMembers,
                            memberColors:     memberColors,
                            onRenameMember:   renameMember,
                            onDeleteMember:   removeMember,
                            onSetMemberColor: setMemberColor,
                            onOpenCalendar:   { showsCalendar = true },
                            title: boardTitle,
                            subtitle: boardSubtitle,
                            allowsAddingLists: allowsAddingLists || lists.isEmpty,
                            onClose: onClose,
                            onViewArchivedLists: { showsArchivedLists = true },
                            onArchiveBoard: onArchiveBoard,
                            onAddList:        addList
                        )

                        GeometryReader { listArea in
                        ScrollViewReader { listProxy in

                            ScrollView(.horizontal, showsIndicators: false) {

                                HStack(alignment: .top, spacing: 12) {

                                    ForEach(Array(lists.enumerated()), id: \.element.id) { listIndex, list in

                                        ZStack {
                                        KanbanListView(
                                            list:               list,
                                            screenSize:         screen.size,
                                            availableListHeight: listArea.size.height,
                                            displaySettings:    displaySettings,
                                            labelLibrary:       labelLibrary,
                                            toggleCardTitle:    { cardID in toggleCardTitle(in: listIndex, cardID: cardID)
                                            },
                                            canMoveEarlier:     listIndex > 0,
                                            canMoveLater:       listIndex < lists.count - 1,
                                            onAddCard:          { title, description in addCard(to: list.id, title: title, description: description)
                                            },
                                            onCopyList:         { copyList(with: list.id) },
                                            onMoveList:         { offset in moveList(with: list.id, by: offset) },
                                            onSortList:         { ascending in sortList(with: list.id, ascending: ascending) },
                                            onArchiveCompleted: { archiveCompletedCards(in: list.id) },
                                            archivedCards: Binding(
                                                get: { lists.first(where: { $0.id == list.id })?.archivedCards ?? [] },
                                                set: { archivedCards in
                                                    guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
                                                    lists[index].archivedCards = archivedCards
                                                }
                                            ),
                                            onRestoreArchivedCard: { cardID in
                                                restoreArchivedCard(in: list.id, cardID: cardID)
                                            },
                                            onArchiveList:      { archiveList(with: list.id) },
                                            onDeleteCard:       { cardID in deleteCard(in: list.id, cardID: cardID) },
                                            onArchiveCard:      archiveCard,
                                            onUpdateCard:       updateCard,
                                            onMoveCard:         { cardID, destinationIndex in moveCard(in: list.id, cardID: cardID, toIndex: destinationIndex)
                                            },
                                            onListDragChanged: { value in updateListDrag(list.id, value: value) },
                                            onListDragEnded: { endListDrag(list.id) }
                                        )
                                        .frame(
                                            width: safeFrameDimension(screen.size.width, subtracting: 28)
                                        )
                                        .scaleEffect(draggedListID == list.id && !reducesMotion ? 1.025 : 1)
                                        .shadow(color: .black.opacity(draggedListID == list.id ? 0.4 : 0), radius: 18, y: 8)
                                        .offset(x: listDragOffset(for: list.id))
                                        }
                                        .frame(width: safeFrameDimension(screen.size.width, subtracting: 28))
                                        .background {
                                            GeometryReader { geometry in
                                                Color.clear.preference(
                                                    key: BoardListCenterPreferenceKey.self,
                                                    value: [list.id: geometry.frame(in: .named("WeekListsViewport")).midX]
                                                )
                                            }
                                        }
                                        .id(list.id)
                                        .zIndex(draggedListID == list.id ? 1 : 0)
                                    }
                                }
                                .frame(maxHeight: .infinity, alignment: .top)
                                .scrollTargetLayout()
                                .padding(.horizontal, 14)
                            }
                            .scrollTargetBehavior(.viewAligned)
                            .scrollDisabled(draggedListID != nil)
                            .coordinateSpace(name: "WeekListsViewport")
                            .onPreferenceChange(BoardListCenterPreferenceKey.self) { centers in
                                listCenters = centers
                                guard draggedListID == nil else { return }
                                guard let nearestListID = centers.min(by: {
                                    abs($0.value - listArea.size.width / 2) < abs($1.value - listArea.size.width / 2)
                                })?.key,
                                nearestListID != lastReportedVisibleListID else { return }
                                lastReportedVisibleListID = nearestListID
                                onListViewed(nearestListID)
                            }
                            .onChange(of: boardTargetListID) { _, targetListID in
                                guard targetListID != nil else { return }
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    openPendingBoardTarget(using: listProxy)
                                }
                            }
                            .onChange(of: boardTargetCardID) { _, cardID in
                                guard cardID != nil else { return }
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    openPendingBoardTarget(using: listProxy)
                                }
                            }
                            .onAppear {
                                openPendingBoardTarget(using: listProxy)
                            }
                            .task(id: draggedListID) {
                                guard let listID = draggedListID else { return }
                                do {
                                    while !Task.isCancelled {
                                        try await Task.sleep(for: .milliseconds(550))
                                        guard draggedListID == listID, let location = listDragLocation,
                                              let source = lists.firstIndex(where: { $0.id == listID }) else { continue }
                                        let direction = BoardListReordering.edgeDirection(at: location, viewportWidth: listArea.size.width)
                                        let destination = source + direction
                                        guard direction != 0, lists.indices.contains(destination) else { continue }
                                        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2)) {
                                            _ = BoardListReordering.move(listID, to: destination, in: &lists)
                                        }
                                        await Task.yield()
                                        guard !Task.isCancelled, draggedListID == listID else { return }
                                        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2)) {
                                            listProxy.scrollTo(listID, anchor: .center)
                                        }
                                    }
                                } catch is CancellationError {
                                    // Releasing the header cancels edge scrolling.
                                } catch {
                                    DatabaseActivity.shared.report("Could not move the list: \(error.localizedDescription)")
                                }
                            }
                            .onDisappear {
                                if let listID = draggedListID { endListDrag(listID) }
                            }
                        }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: KanbanCard.self) { card in
                CardDetailView(
                    card:           card,
                    labelLibrary:   $labelLibrary,
                    availableLists: lists.filter { list in
                        !list.cards.contains(where: { $0.id == card.id })
                    },
                    memberColors:    memberColors,
                    currentUserName: currentUserName,
                    savedCardIDs:    $savedCardIDs,
                    onTitleToggle:   { updatedCard in
                        updateCard(updatedCard)
                    },
                    onMoveToList:    { destinationListID in
                        moveCard(card.id, toListID: destinationListID)
                    },
                    onArchive: {
                        archiveCard(card.id)
                    }
                )
            }
            .sheet(isPresented: $showsCalendar) {
                TodayCalendarView(lists: lists) { listID in
                    showsCalendar = false
                    boardTargetCardID = nil
                    boardTargetListID = listID
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showsArchivedLists) {
                ArchivedListsView(lists: $archivedLists, onRestore: restoreArchivedList)
                    .databaseActivityOverlay()
            }
            .onChange(of: lists) { _, updatedLists in
                onListsChanged(updatedLists)
            }
            .onChange(of: labelLibrary) { _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }
        }
    }
}


// -------------------------------------- MARK: - Board Header ---------------------------------- //

///
/// Displays the board title and board-level actions
///
/// @section    Purpose
///     Establish the visual identity of the board and expose board-level controls
///
struct BoardHeader: View {

    @Binding var settings: BoardDisplaySettings      /* Board display settings                              */
    let activeMembers:     [String]                  /* Unique users assigned to active cards               */
    let memberColors:      [String: Color]           /* Icon colors keyed by normalized member name         */
    let onRenameMember:    (String, String) -> Void  /* Rename a member across all card assignments         */
    let onDeleteMember:    (String) -> Void          /* Remove a member from all card assignments           */
    let onSetMemberColor:  (String, Color) -> Void   /* Update a member's shared icon color                 */
    let onOpenCalendar: () -> Void
    let title: String
    let subtitle: String
    let allowsAddingLists: Bool
    let onClose: (() -> Void)?
    let onViewArchivedLists: () -> Void
    let onArchiveBoard: (() -> Void)?

    let onAddList: () -> Void                        /* Callback for adding a new list                      */

    @State private var showingSettings = false       /* Controls the visibility of the board settings sheet */
    @State private var confirmsArchiveBoard = false

    /// Builds the title block and board action controls.
    var body: some View { /* Board header and global actions */

        HStack {

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 44)
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Back to Lists")
            }

            VStack(alignment: .leading, spacing: 2) {

                Text(title)
                    .font(onClose == nil ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            Button(action: onOpenCalendar) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Calendar")

            if allowsAddingLists {
            Menu {
                
                Button("Add blank list", systemImage: "rectangle.stack.badge.plus", action: onAddList)
                
            } label: {
                
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Add list")
            }

            Menu {
                Button("Board Settings", systemImage: "gearshape") { showingSettings = true }
                Button("View Archived Lists", systemImage: "archivebox", action: onViewArchivedLists)
                if onArchiveBoard != nil {
                    Button("Archive Board", systemImage: "archivebox") { confirmsArchiveBoard = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Board options")
        }
        .padding(.horizontal, 18)
        .padding(.top,        12)
        .padding(.bottom,     10)
        .confirmationDialog("Archive this board?", isPresented: $confirmsArchiveBoard, titleVisibility: .visible) {
            Button("Archive Board") { onArchiveBoard?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All lists and cards will be kept on this device. Restore the board from Saved.")
        }
        .sheet(isPresented: $showingSettings) {
            
            BoardSettingsView(
                settings:         $settings,
                activeMembers:    activeMembers,
                memberColors:     memberColors,
                onRenameMember:   onRenameMember,
                onDeleteMember:   onDeleteMember,
                onSetMemberColor: onSetMemberColor
            )
        }

    }
}

private struct ArchivedListsView: View {
    @Binding var lists: [KanbanList]
    let onRestore: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(lists) { list in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.title).font(.headline)
                            Text("\(list.cards.filter { !$0.isSectionDivider }.count) cards · \(list.archivedCards.count) archived cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { onRestore(list.id) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Restore \(list.title)")
                    }
                }
            }
            .overlay {
                if lists.isEmpty {
                    ContentUnavailableView(
                        "No Archived Lists", systemImage: "archivebox",
                        description: Text("Lists archived from this board will appear here.")
                    )
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Archived Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}


/// @section    Purpose
///     Let the user control which metadata badges appear on board cards
///
/// @note   Settings are bound to ContentView and take effect immediately
///
private struct BoardSettingsView: View {

    @Binding var settings: BoardDisplaySettings             /* Bound to the board's display preferences        */

    @Environment(\.dismiss) private var dismiss             /* Dismiss action for the settings sheet           */

    let activeMembers:     [String]                         /* Active assigned users in board order            */        
    let memberColors:      [String: Color]                  /* Member icon colors keyed by normalized name     */
    let onRenameMember:    (String, String)   -> Void       /* Rename a member across all assigned cards       */
    let onDeleteMember:    (String)           -> Void       /* Remove a member from all assigned cards         */
    let onSetMemberColor:  (String, Color)    -> Void       /* Update a member's shared icon color             */

    @State private var memberNameDraft  = ""                /* Draft name for renaming a member                */
    @State private var isRenamingMember = false             /* Flag indicating if member rename in progress    */

    @State private var editingMember: String?               /* Currently edited member name                    */
    @State private var memberToDelete: String?              /* Member slated for deletion                      */
    @State private var selectedMemberColor: MemberColorTarget?  /* Target member for color selection           */


    private var trimmedMemberNameDraft: String { /* Normalized member rename input */
        memberNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    ///
    /// @fcn        BoardSettingsView.body
    /// @brief      Build the board settings form
    /// @details    Presents toggles for checklist progress, comment counts, and due-date badges
    ///
    /// @return     (some View) settings sheet content with a Done action
    ///
    /// @pre        settings is bound to the board's display preferences
    /// @post       Changes update the bound settings and are reflected by the board cards
    ///
    var body: some View { /* Board settings and member management form */

        NavigationStack {

            Form {

                Section("Card badges") {
                    Toggle("Checklist progress", isOn: $settings.showChecklistProgress)
                    Toggle("Comment counts",     isOn: $settings.showCommentCounts)
                    Toggle("Due-date badges",    isOn: $settings.showDueDateBadges)
                }

                Section("Members") {

                    if activeMembers.isEmpty {

                        Text("No active members")
                            .foregroundStyle(.secondary)

                    } else {

                        ForEach(activeMembers, id: \.self) { member in

                            HStack(spacing: 12) {

                                let memberColor = memberColors[member.lowercased()] ?? .accentColor     /* Fallback to accent color if no custom color is set */

                                Button {
                                    selectedMemberColor = MemberColorTarget(member: member, color: memberColor)

                                } label: {

                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(memberColor)
                                        .frame(width: 36, height: 36)
                                        .contentShape(Rectangle())

                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Change icon color for \(member)")

                                Text(member)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    editingMember    = member
                                    memberNameDraft  = member
                                    isRenamingMember = true

                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit \(member)")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                                Button(role: .destructive) {
                                    memberToDelete = member

                                } label: {
                                    Label("Remove", systemImage: "person.crop.circle.badge.minus")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Board Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Edit member", isPresented: $isRenamingMember) {

                TextField("Name or email", text: $memberNameDraft)
                    .textInputAutocapitalization(.never)

                Button("Cancel", role: .cancel) {}

                Button("Save") {
                    guard let editingMember else { return } /* Member currently being renamed */

                    onRenameMember(editingMember, trimmedMemberNameDraft)
                }
                .disabled(trimmedMemberNameDraft.isEmpty)
            } message: {

                Text("This updates the member name on every assigned card.")
            }
            .confirmationDialog(

                "Remove \(memberToDelete ?? "member") from the board?",

                isPresented: Binding(
                    get: { memberToDelete != nil },
                    set: { if !$0 { memberToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove member", role: .destructive) {

                    guard let memberToDelete else { return } /* Member confirmed for removal */

                    onDeleteMember(memberToDelete)

                    self.memberToDelete = nil
                }

                Button("Cancel", role: .cancel) {
                    memberToDelete = nil
                }

            } message: {
                Text("This removes the member from all card assignments. Existing comments are kept.")
            }
            .sheet(item: $selectedMemberColor) { target in

                MemberColorEditorSheet(memberName: target.member, initialColor: target.color) { color in
                    onSetMemberColor(target.member, color)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


///
/// Carries the selected member and current color while the color editor sheet is presented
///
/// @section    Purpose
///     Provide a stable identifiable sheet item containing the values needed to edit a member icon color
///
/// @details    The member's lowercased name is used as the sheet identity, and the current color seeds the editor
///
/// @note       This is transient presentation state; saving is handled by MemberColorEditorSheet
///
private struct MemberColorTarget: Identifiable {

    let member: String                          /* The name of the member whose color is being edited */    
    let color: Color                            /* The current color of the member's icon             */

    var id: String { member.lowercased() }      /* Use the lowercased member name as the unique identifier for the sheet */
}


///
/// Presents the system color picker for one member's icon
///
/// @section    Purpose
///     Let the user preview, change, save, or cancel a member's shared icon color
///
/// @details    Holds the selected color locally until Save invokes onSave; Cancel dismisses without applying changes
///
/// @note       Opacity selection is disabled so the icon remains fully visible
///
private struct MemberColorEditorSheet: View {

    let memberName: String              /* The name of the member whose color is being edited         */
    let onSave: (Color) -> Void         /* The closure to call when the user saves the selected color */

    @Environment(\.dismiss) private var dismiss /* Dismiss action for the color editor */
    @State private var selectedColor: Color /* Draft member icon color */

    /// Initialize the editor with the selected member's current color
    ///
    /// @param[in]  memberName Member whose icon color is being edited
    /// @param[in]  initialColor Current color shown when the editor opens
    /// @param[in]  onSave Callback receiving the selected color
    ///
    /// @return     (MemberColorEditorSheet) configured editor
    ///
    init(memberName: String, initialColor: Color, onSave: @escaping (Color) -> Void) {
        self.memberName = memberName
        self.onSave     = onSave
        _selectedColor  = State(initialValue: initialColor)
    }

    var body: some View { /* Member icon color editor */

        NavigationStack {

            Form {
                Section(memberName) {
                    ColorPicker("Icon color", selection: $selectedColor, supportsOpacity: false)
                }
            }
            .navigationTitle("Member icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedColor)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}


// -------------------------------------- MARK: - Kanban List ----------------------------------- //

///
/// Displays one kanban list and its cards
///
/// @section    Purpose
///     Keep a list title, list metadata, add-card action, and vertically scrollable card collection together
///
struct KanbanListView: View {

    /// Identifies the modal sheet currently presented by a kanban list
    ///
    /// @section    Purpose
    ///     Distinguish list actions from new-card entry
    ///
    private enum ActiveSheet: String, Identifiable {
        case listActions
        case newCard

        var id: String { rawValue } /* Stable sheet identity */
    }

    let list: KanbanList                        /* The kanban list data rendered by the view                      */
    let screenSize: CGSize                      /* The size of the device screen used for layout calculations     */    
    let availableListHeight: CGFloat
    let displaySettings: BoardDisplaySettings   /* The board's display settings affecting card and list rendering */
    let labelLibrary: LabelLibrary              /* Shared categorized labels available to the cards               */
    let toggleCardTitle: (Int) -> Void          /* The action invoked to toggle the title of a card               */
    let canMoveEarlier: Bool                    /* Indicates whether the list can be moved earlier in the board   */
    let canMoveLater:  Bool                     /* Indicates whether the list can be moved later in the board     */
    let onAddCard: (String, String) -> Void     /* The action invoked to add a new card to the list               */
    let onCopyList: () -> Void                  /* The action invoked to copy the list                            */
    let onMoveList: (Int) -> Void               /* The action invoked to move the list by a specified offset      */
    let onSortList: (Bool) -> Void              /* The action invoked to sort the list based on a specified order */
    let onArchiveCompleted: () -> Void          /* The action invoked to archive all completed cards in the list  */
    @Binding var archivedCards: [KanbanCard]
    let onRestoreArchivedCard: (Int) -> Void
    let onArchiveList: () -> Void               /* The action invoked to archive the entire list                  */
    let onDeleteCard: (Int) -> Void             /* The action invoked to delete a card at a specified index       */
    let onArchiveCard: (Int) -> Void
    let onUpdateCard: (KanbanCard) -> Void      /* The action invoked to save edited card information             */
    let onMoveCard: (Int, Int) -> Void          /* Move a card to a destination index in this list                */
    let onListDragChanged: (DragGesture.Value?) -> Void
    let onListDragEnded: () -> Void

    @State private var activeSheet: ActiveSheet?            /* The currently active sheet presented modally        */
    @State private var isWatching               = false     /* Indicates whether the user is watching the list     */
    @State private var listTint: KanbanListTint = .neutral  /* The tint color applied to the list header and cards */
    @State private var editMode: EditMode       = .inactive /* Indicates whether the list is in edit mode          */
    @State private var headerHeight: CGFloat = 72
    @GestureState private var isHoldingList = false

    private var listReorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("WeekListsViewport")))
            .updating($isHoldingList) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                if case .second(true, let drag) = value {
                    onListDragChanged(drag)
                }
            }
            .onEnded { _ in onListDragEnded() }
    }

    /// Maintains the original quarter-screen card sizing requirement
    private var cardHeight: CGFloat { /* Fixed card height derived from screen geometry */

        let quarterHeight = screenSize.height * 0.25 /* Original quarter-screen card target */
        
        return quarterHeight.isFinite ? max(quarterHeight, 1) : 1
    }

    private var cardCollectionContentHeight: CGFloat {
        let rowHeight = list.cards.reduce(CGFloat.zero) { height, card in
            height + (card.isSectionDivider ? 44 : max(cardHeight, 48))
        }
        return max(88, rowHeight + 64)
    }

    private var cardCollectionHeight: CGFloat {
        let availableHeight = max(1, availableListHeight - headerHeight - 24)
        return min(cardCollectionContentHeight, availableHeight)
    }

    /// Builds one list panel and its card navigation destinations
    var body: some View { /* List panel and card collection */

        VStack(spacing: 0) {

            HStack(alignment: .top) {

                VStack(alignment: .leading, spacing: 3) {

                    Text(list.title)
                        .font(.title3.weight(.bold))

                    Text(list.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(listReorderGesture)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Touch and hold to drag this list. Keep holding near either screen edge to move across the board.")
                .accessibilityAction(named: "Move earlier") {
                    if canMoveEarlier { onMoveList(-1) }
                }
                .accessibilityAction(named: "Move later") {
                    if canMoveLater { onMoveList(1) }
                }
                .onChange(of: isHoldingList) { _, holding in
                    if !holding { onListDragEnded() }
                }
                .sensoryFeedback(.selection, trigger: isHoldingList)

                Button {

                    withAnimation(.easeInOut(duration: 0.2)) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                } label: {

                    Image(systemName: editMode == .active ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(editMode == .active ? "Done reordering cards" : "Reorder cards")

                if isWatching {

                    Image(systemName: "eye.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(list.cards.filter { !$0.isSectionDivider }.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    activeSheet = .listActions
                } label: {

                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(list.title) list actions")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background {
                GeometryReader { header in
                    Color.clear
                        .onAppear { headerHeight = header.size.height }
                        .onChange(of: header.size.height) { _, height in headerHeight = height }
                }
            }

            List {

                ForEach(list.cards) { card in

                    if card.isSectionDivider {

                        NavigationLink(value: card) {

                            Rectangle()
                                .fill(Color.secondary.opacity(0.45))
                                .frame(height: 2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .modifier(HideNavigationLinkIndicator())
                        .accessibilityLabel("Open section divider")
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {

                        NavigationLink(value: card) {

                            KanbanCardView(
                                card:            card,
                                height:          cardHeight,
                                displaySettings: displaySettings,
                                labelLibrary:    labelLibrary,
                                onUpdateCard:    onUpdateCard,
                                onDeleteCard:    { onDeleteCard(card.id) },
                                onArchiveCard:   { onArchiveCard(card.id) }
                            ) {
                                toggleCardTitle(card.id)
                            }
                        }
                        .buttonStyle(.plain)
                        .modifier(HideNavigationLinkIndicator())
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDeleteCard(card.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove { sourceOffsets, destinationOffset in

                    guard let sourceIndex = sourceOffsets.first, /* Original drag source row */
                          list.cards.indices.contains(sourceIndex) else {
                        return
                    }

                    let finalIndex = sourceIndex < destinationOffset ? destinationOffset - 1 : destinationOffset /* Destination after source removal */

                    onMoveCard(list.cards[sourceIndex].id, finalIndex)
                }

                Button {
                    activeSheet = .newCard
                } label: {
                    Label("Add card", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
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
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
        .background(listTint.color)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .sheet(item: $activeSheet) { presentedSheet in
            switch presentedSheet {
            case .listActions:
                KanbanListActionsSheet(
                    list:               list,
                    canMoveEarlier:     canMoveEarlier,
                    canMoveLater:       canMoveLater,
                    isWatching:         $isWatching,
                    listTint:           $listTint,
                    onAddCard:          { activeSheet = .newCard },
                    onCopyList:         onCopyList,
                    onMoveList:         onMoveList,
                    onSortList:         onSortList,
                    onArchiveCompleted: onArchiveCompleted,
                    archivedCards: $archivedCards,
                    onRestoreArchivedCard: onRestoreArchivedCard,
                    onArchiveList:      onArchiveList
                )
                .databaseActivityOverlay()
            case .newCard:
                NewKanbanCardSheet(listTitle: list.title, onCreate: onAddCard)
                    .databaseActivityOverlay()
            }
        }
    }
}


///
/// Hides the automatic trailing indicator on navigation links when supported
///
/// @section    Purpose
///     Keep list rows fully tappable without displaying a redundant disclosure chevron
///
/// @details    Uses SwiftUI's navigation indicator visibility API on iOS 18 and later, while
///             preserving content on earlier versions
///
/// @note       Apply this modifier to navigation links whose destination is indicated by the row itself
///
private struct HideNavigationLinkIndicator: ViewModifier {

    @ViewBuilder
    ///
    /// @fcn        HideNavigationLinkIndicator.body(content:)
    /// @brief      Configure navigation indicator visibility for the modified content
    /// @details    Hides navigation link indicators on iOS 18 and later; earlier iOS versions receive
    ///             the content unchanged
    ///
    /// @param[in]  content  View content to which this modifier is applied
    ///
    /// @return     (some View) modified content with the navigation indicator hidden when supported
    ///
    /// @pre        SwiftUI invokes this function when the modifier is applied to a view
    /// @post       The original content is preserved, with supported navigation indicators hidden
    ///
    func body(content: Content) -> some View {

        if #available(iOS 18.0, *) {

            content.navigationLinkIndicatorVisibility(.hidden)
            
        } else {
            content
        }
    }
}


///
/// Presents a form for creating a card in the selected kanban list
///
/// @section    Purpose
///     Collect a card title and optional description, then return the trimmed values to the
///     owning list view
///
/// @details    The title field also accepts the divider marker, allowing the list to create a
///             movable section divider
///
/// @note       Dismissing with Cancel does not invoke the creation callback
///
private struct NewKanbanCardSheet: View {

    let listTitle: String                               /* Title of the kanban list to which the new card will be added                             */
    let onCreate: (String, String) -> Void              /* Callback invoked with the trimmed title and description when the user creates a new card */

    @Environment(\.dismiss) private var dismiss         /* Environment variable to dismiss the current view */
    @State private var title       = ""                 /* User-entered card title                          */
    @State private var description = ""                 /* User-entered card description                    */

    private var trimmedTitle: String { /* Normalized new-card title */
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View { /* New-card form and submission controls */

        NavigationStack {

            Form {

                Section("Card details") {
                    TextField("Title (or --- for divider)", text: $title)
                        .textInputAutocapitalization(.never)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .cancellationAction) {
                    
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    
                    Button("Add") {
                        onCreate(trimmedTitle, description.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


///
/// Defines the selectable background tints for kanban lists
///
/// @section    Purpose
///     Provide consistent, subtle colors that help distinguish lists without changing their card content
///
/// @details    Each case exposes a stable raw-value identity, a user-facing title, and a
///             corresponding list background color
///
/// @note       Case ordering controls the options presented by the list color picker
///
private enum KanbanListTint: String, CaseIterable, Identifiable {
    case neutral
    case blue
    case green
    case orange
    case red

    var id: String { rawValue } /* Stable tint identity */

    var title: String { /* User-facing tint label */
        switch self {
            case .neutral: "Default"
            case .blue:    "Blue"
            case .green:   "Green"
            case .orange:  "Orange"
            case .red:     "Red"
        }
    }

    var color: Color { /* Subtle list background color */
        switch self {
            case .neutral: Color(.systemGray6)
            case .blue:    Color.blue.opacity(0.12)
            case .green:   Color.green.opacity(0.12)
            case .orange:  Color.orange.opacity(0.12)
            case .red:     Color.red.opacity(0.12)
        }
    }
}


///
/// Presents actions for copying, moving, organizing, and archiving one list
///
/// @section    Purpose
///     Keep list-level operations together in a dedicated action sheet
///
private struct KanbanListActionsSheet: View {

    let list: KanbanList                   /* The Kanban list this sheet is associated with                                 */
    let canMoveEarlier: Bool               /* Indicates if the list can be moved earlier                                    */
    let canMoveLater: Bool                 /* Indicates if the list can be moved later                                      */
    @Binding var isWatching: Bool          /* Indicates if the user is watching the list                                    */
    @Binding var listTint: KanbanListTint  /* The current tint color of the list                                            */
    let onAddCard: () -> Void              /* Action to perform when adding a card                                          */
    let onCopyList: () -> Void             /* Action to perform when copying the list                                       */
    let onMoveList: (Int) -> Void          /* Action to perform when moving the list by a given offset                      */
    let onSortList: (Bool) -> Void         /* Action to perform when sorting the list; true for A to Z, false for Z to A    */
    let onArchiveCompleted: () -> Void     /* Action to perform when archiving completed cards                              */
    @Binding var archivedCards: [KanbanCard]
    let onRestoreArchivedCard: (Int) -> Void
    let onArchiveList: () -> Void          /* Action to perform when archiving the entire list                              */

    @Environment(\.dismiss) private var dismiss /* Dismiss action for list operations */
    @State private var confirmingArchive = false /* Archive confirmation presentation state */

    var body: some View { /* List operation menu */
        
        NavigationStack {

            List {

                Section {

                    Button {
                        onAddCard()
                        dismiss()
                    } label: {
                        Label("Add card", systemImage: "plus")
                    }

                    Button {
                        onCopyList()
                        dismiss()
                    } label: {
                        Label("Copy list", systemImage: "doc.on.doc")
                    }

                    Menu {
                        Button("Move earlier") {
                            onMoveList(-1)
                            dismiss()
                        }
                        .disabled(!canMoveEarlier)

                        Button("Move later") {
                            onMoveList(1)
                            dismiss()
                        }
                        .disabled(!canMoveLater)
                        
                    } label: {
                        
                        Label("Move list", systemImage: "arrow.left.arrow.right")
                            .foregroundStyle(.primary)
                    }

                    Menu {
                        Button("Title A to Z") {
                            onSortList(true)
                            dismiss()
                        }
                        Button("Title Z to A") {
                            onSortList(false)
                            dismiss()
                        }
                    } label: {
                        Label("Sort list", systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(.primary)
                    }

                    Menu {
                        ForEach(KanbanListTint.allCases) { tint in
                            Button {
                                listTint = tint
                            } label: {
                                Label(tint.title, systemImage: listTint == tint ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    } label: {
                        Label("Change list color", systemImage: "paintpalette")
                            .foregroundStyle(.primary)
                    }

                    Button {
                        isWatching.toggle()
                        
                    } label: {
                        Label(isWatching ? "Unwatch" : "Watch", systemImage: isWatching ? "eye.slash" : "eye")
                    }
                }

                Section {
                    NavigationLink {
                        ArchivedCardsView(
                            listTitle: list.title,
                            cards: $archivedCards,
                            onRestore: onRestoreArchivedCard
                        )
                    } label: {
                        Label("View Archived Cards", systemImage: "archivebox")
                    }

                    Button {
                        onArchiveCompleted()
                        dismiss()
                        
                    } label: {
                        Label("Archive completed cards", systemImage: "archivebox")
                    }

                    Button(role: .destructive) {
                        confirmingArchive = true
                        
                    } label: {
                        Label("Archive list", systemImage: "archivebox")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("List actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Archive \(list.title)?", isPresented: $confirmingArchive, titleVisibility: .visible) {

                Button("Archive list", role: .destructive) {
                    onArchiveList()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}


// -------------------------------------- MARK: - Kanban Card ----------------------------------- //

private struct ArchivedCardsView: View {
    let listTitle: String
    @Binding var cards: [KanbanCard]
    let onRestore: (Int) -> Void

    var body: some View {
        List {
            Section {
                ForEach(cards) { card in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.word).font(.headline)
                            if !card.funParagraph.isEmpty {
                                Text(card.funParagraph)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        Spacer()
                        Button("Restore") {
                            onRestore(card.id)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Restore \(card.word)")
                    }
                }
            } header: {
                Text(listTitle)
            } footer: {
                if !cards.isEmpty {
                    Text("Restored cards return to the end of this list and keep their completion status.")
                }
            }
        }
        .overlay {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No Archived Cards",
                    systemImage: "archivebox",
                    description: Text("Cards you archive from this list will appear here.")
                )
                .allowsHitTesting(false)
            }
        }
        .navigationTitle("Archived Cards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

///
/// Displays a compact summary of a kanban card
///
/// @section    Purpose
///     Present the title, supporting copy, and compact metadata used to scan cards on the board
///
struct KanbanCardView: View {

    let card: KanbanCard                            /* The kanban card being displayed                               */
    let height: CGFloat                             /* The fixed height of the card view                             */
    let displaySettings: BoardDisplaySettings       /* Settings controlling which elements of the card are displayed */
    let labelLibrary: LabelLibrary                  /* Shared label catalog used to resolve card label IDs           */
    let onUpdateCard: (KanbanCard) -> Void          /* The action invoked when card details are updated              */
    let onDeleteCard: () -> Void                    /* The action invoked when this card is deleted                  */
    let onArchiveCard: () -> Void
    let onToggle: () -> Void                        /* Callback invoked when the card's title checkbox is toggled    */

    @State private var renameDraft        = ""      /* Draft text for the rename operation                           */
    @State private var isRenaming         = false   /* Flag indicating if the rename operation is active             */
    @State private var isEditingInfo      = false   /* Flag indicating if the card info editing mode is active       */
    @State private var isConfirmingDelete = false   /* Flag indicating if the delete confirmation dialog is shown    */


    private var trimmedRenameDraft: String { /* Normalized rename input */
        renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cardLabels: [KanbanLabel] { /* Resolved labels shown on this card */
        card.labelIDs.compactMap { labelID in
            labelLibrary.labels.first(where: { $0.id == labelID })
        }
    }


    ///
    /// @fcn        KanbanCardView.cardUpdated(title:subtitle:description:)
    /// @brief      Create a card snapshot containing edited display information
    /// @details    Replaces the title, subtitle, and description while preserving the card's identity and other state
    ///
    /// @param[in]  title        Updated card title
    /// @param[in]  subtitle     Optional board subtitle override
    /// @param[in]  description  Updated detail description
    ///
    /// @return     (KanbanCard) updated card retaining its dates, checklist, comments, completion, and activity state
    ///
    /// @pre        Values come from the current card edit operation
    /// @post       The original card remains unchanged; the returned snapshot contains the requested display values
    ///
    private func cardUpdated(title: String, subtitle: String?, description: String?) -> KanbanCard {
        KanbanCard(
            id:                   card.id,
            word:                 title,
            listTitle:            card.listTitle,
            isDivider:            card.isDivider,
            isTitleChecked:       card.isTitleChecked,
            startDate:            card.startDate,
            dueDate:              card.dueDate,
            checklists:           card.checklists,
            comments:             card.comments,
            members:              card.members,
            labelIDs:             card.labelIDs,
            attachments:          card.attachments,
            dismissedActivityIDs: card.dismissedActivityIDs,
            descriptionOverride:  description,
            subtitleOverride:     subtitle
        )
    }


    ///
    /// @fcn        KanbanCardView.renameCard
    /// @brief      Submit the renamed card title
    /// @details    Trims the title draft, ignores an empty result, and sends the updated card to
    ///             the board callback
    ///
    /// @return     (Void) requests a card update when the trimmed title is not empty
    ///
    /// @pre        renameDraft contains the title entered in the Rename Card alert
    /// @post       A valid title is synchronized to board state; an empty title causes no change
    ///
    private func renameCard() {
        
        guard !trimmedRenameDraft.isEmpty else { return }

        onUpdateCard(cardUpdated(
            title:       trimmedRenameDraft,
            subtitle:    card.subtitleOverride,
            description: card.descriptionOverride
        ))
    }

    /// Builds a fixed-height card summary within its parent list
    var body: some View { /* Compact card summary and card actions */

        VStack(alignment: .leading, spacing: 9) {

            HStack(alignment: .center, spacing: 8) {

                Button {
                    onToggle()
                } label: {
                    Image(systemName: card.isTitleChecked ? "checkmark.square.fill" : "square")
                        .font(.headline)
                        .foregroundStyle(card.isTitleChecked ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.isTitleChecked ? "Uncheck card title" : "Check card title")

                Text(card.word)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                Menu {
                    Button(action: onArchiveCard) {
                        Label("Archive Card", systemImage: "archivebox")
                    }

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Card", systemImage: "trash")
                    }

                    Button {
                        renameDraft = card.word
                        isRenaming = true
                        
                    } label: {
                        Label("Rename Card", systemImage: "pencil")
                    }

                    Button {
                        isEditingInfo = true
                        
                    } label: {
                        Label("Update Card Info", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Card actions")
            }

            Text(card.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if !cardLabels.isEmpty {
                
                HStack(spacing: 5) {
                    
                    ForEach(cardLabels.prefix(3)) { label in
                        KanbanLabelChip(label: label)
                    }

                    if cardLabels.count > 3 {
                        Text("+\(cardLabels.count - 3)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 14) {

                if displaySettings.showCommentCounts {
                    Label("\(card.commentCount)", systemImage: "text.bubble")
                }

                if displaySettings.showChecklistProgress {
                    Label("\(card.completedChecklistItems)/\(card.checklistItems.count)", systemImage: "checklist")
                }

                if displaySettings.showDueDateBadges && card.hasDueDate {
                    Label("Today", systemImage: "calendar")
                }

                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(height - 8, 40), alignment: .top)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
        .padding(.horizontal, 4)
        .alert("Rename Card", isPresented: $isRenaming) {
            
            TextField("Card title", text: $renameDraft)
                .textInputAutocapitalization(.never)
            
            Button("Cancel", role: .cancel) {}
            
            Button("Rename", action: renameCard)
                .disabled(trimmedRenameDraft.isEmpty)
            
        } message: {
            
            Text("Enter a new title for this card.")
        }
        .confirmationDialog("Delete \(card.word)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            
            Button("Delete Card", role: .destructive, action: onDeleteCard)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isEditingInfo) {
            CardInfoEditorSheet(card: card) { title, subtitle, description in
                onUpdateCard(cardUpdated(title: title, subtitle: subtitle, description: description))
            }
            .databaseActivityOverlay()
        }
    }
}


/// Presents the full editor for a card's title, board subtitle, and detail description
///
/// @section    Purpose
///     Collect card display text and submit the completed values through the supplied save callback
///
/// @note   The parent card view owns persistence; cancel dismisses without invoking the callback
///
private struct CardInfoEditorSheet: View {

    let onSave: (String, String, String) -> Void /* Callback receiving the edited card text */

    @Environment(\.dismiss) private var dismiss     /* Dismiss action for the sheet         */
    @State private var title:       String          /* Draft text for the title field       */
    @State private var subtitle:    String          /* Draft text for the subtitle field    */
    @State private var description: String          /* Draft text for the description field */

    ///
    /// @fcn        CardInfoEditorSheet.trimmedTitle
    /// @brief      Return the title draft without surrounding whitespace
    /// @details    Trims leading and trailing whitespace and newline characters before validation or saving
    ///
    /// @return     (String) normalized title draft; may be empty when the input contains only whitespace
    ///
    /// @pre        title contains the current text-field value
    /// @post       The stored title draft is unchanged
    ///
    private var trimmedTitle: String { /* Normalized card title draft */
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        CardInfoEditorSheet.init(card:onSave:)
    /// @brief      Initialize the card information editor
    /// @details    Seeds the title, subtitle, and description fields from the selected card and
    ///             stores its save callback
    ///
    /// @param[in]  card    Card whose information will be edited
    /// @param[in]  onSave  Callback that applies the edited title, subtitle, and description
    ///
    /// @return     (CardInfoEditorSheet) configured card information form
    ///
    /// @pre        card contains the current values to present in the form
    /// @post       All editable fields begin with the selected card's current display values
    ///
    init(card: KanbanCard, onSave: @escaping (String, String, String) -> Void) {

        self.onSave  = onSave
        _title       = State(initialValue: card.word)
        _subtitle    = State(initialValue: card.subtitle)
        _description = State(initialValue: card.funParagraph)
    }
    

    ///
    /// @fcn        CardInfoEditorSheet.body
    /// @brief      Build the card information editing form
    /// @details    Presents title, subtitle, and description fields with Cancel and validated Save actions
    ///
    /// @return     (some View) modal form for updating card display information
    ///
    /// @pre        Editor state has been initialized from the selected card
    /// @post       Save invokes onSave with the edited values; Cancel dismisses without applying them
    ///
    var body: some View { /* Card title, subtitle, and description form */

        NavigationStack {

            Form {
                Section("Card details") {
                    
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.never)
                    
                    TextField("Subtitle", text: $subtitle)
                        .textInputAutocapitalization(.never)
                }

                Section("Description") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .navigationTitle("Update Card Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedTitle, subtitle, description)
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


/// Presents one Today list vertically, sharing its cards with the Week Board.
struct TodayListDetailView: View {

    @Binding var lists: [KanbanList] /* Shared local Board snapshot */
    let reservedLists: [KanbanList]
    @Binding var labelLibrary: LabelLibrary /* Shared reusable label library */
    @Binding var savedCardIDs: Set<Int> /* Device-local saved cards */

    let listID: Int /* Focused list identity */
    let currentUserName: String /* Current activity author */
    let onClose: () -> Void /* Return to Today */
    let onOpenWeek: () -> Void /* Open this list in the Week workspace */

    @State private var newCardTitle = "" /* Inline card-creation draft */

    private var focusedList: KanbanList? {
        lists.first { $0.id == listID }
    }

    var body: some View {

        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color(.systemGray6).ignoresSafeArea()

                    if let focusedList {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(focusedList.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                ForEach(focusedList.cards) { card in
                                    if card.isSectionDivider {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.45))
                                            .frame(height: 2)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                    } else {
                                        NavigationLink(value: card) {
                                            KanbanCardView(
                                                card: card,
                                                height: max(geometry.size.height * 0.20, 128),
                                                displaySettings: BoardDisplaySettings(),
                                                labelLibrary: labelLibrary,
                                                onUpdateCard: updateCard,
                                                onDeleteCard: { deleteCard(card.id) },
                                                onArchiveCard: { archiveCard(card.id) }
                                            ) {
                                                toggleCard(card.id)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                HStack(spacing: 10) {
                                    TextField("Add a card to \(focusedList.title)…", text: $newCardTitle)
                                        .submitLabel(.done)
                                        .onSubmit(addCard)

                                    Button(action: addCard) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                    }
                                    .disabled(newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityLabel("Add card to \(focusedList.title)")
                                }
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(16)
                        }
                        .background(.clear)
                    } else {
                        ContentUnavailableView("List unavailable", systemImage: "list.bullet")
                    }
                }
            }
            .navigationTitle(focusedList?.title ?? "Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Today", systemImage: "chevron.left", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open in Week", action: onOpenWeek)
                }
            }
            .navigationDestination(for: KanbanCard.self) { card in
                CardDetailView(
                    card: card,
                    labelLibrary: $labelLibrary,
                    availableLists: lists.filter { $0.id != listID },
                    currentUserName: currentUserName,
                    savedCardIDs: $savedCardIDs,
                    onTitleToggle: updateCard,
                    onMoveToList: { destinationListID in
                        moveCard(card.id, toListID: destinationListID)
                    },
                    onArchive: {
                        archiveCard(card.id)
                    }
                )
            }
            .onChange(of: labelLibrary) { _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }
        }
        .databaseActivityOverlay()
    }

    private func toggleCard(_ cardID: Int) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }),
              let cardIndex = lists[listIndex].cards.firstIndex(where: { $0.id == cardID }) else { return }
        lists[listIndex].cards[cardIndex].isTitleChecked.toggle()
    }

    private func archiveCard(_ cardID: Int) {
        guard let listIndex = lists.firstIndex(where: { $0.cards.contains(where: { $0.id == cardID }) }) else { return }
        lists[listIndex].archiveCard(id: cardID)
    }

    private func updateCard(_ updatedCard: KanbanCard) {
        guard let listIndex = lists.firstIndex(where: { $0.cards.contains(where: { $0.id == updatedCard.id }) }),
              let cardIndex = lists[listIndex].cards.firstIndex(where: { $0.id == updatedCard.id }) else { return }
        lists[listIndex].cards[cardIndex] = updatedCard
    }

    private func deleteCard(_ cardID: Int) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[listIndex].cards.removeAll { $0.id == cardID }
    }

    private func moveCard(_ cardID: Int, toListID destinationListID: Int) {
        guard let sourceListIndex = lists.firstIndex(where: { $0.id == listID }),
              let destinationListIndex = lists.firstIndex(where: { $0.id == destinationListID }),
              sourceListIndex != destinationListIndex,
              let cardIndex = lists[sourceListIndex].cards.firstIndex(where: { $0.id == cardID }) else { return }

        var movedCard = lists[sourceListIndex].cards.remove(at: cardIndex)
        movedCard.listTitle = lists[destinationListIndex].title
        lists[destinationListIndex].cards.append(movedCard)
    }

    private func addCard() {
        let title = newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return }

        let nextCardID = ((lists + reservedLists).flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1
        lists[listIndex].cards.append(
            KanbanCard(
                id: nextCardID,
                word: title,
                listTitle: lists[listIndex].title,
                isDivider: KanbanCard.isDividerTitle(title)
            )
        )
        newCardTitle = ""
    }
}


// -------------------------------------- MARK: - Previews -------------------------------------- //

/// Preview the complete board presentation with deterministic sample data
#Preview {
    ContentView(lists: .constant(SampleData.lists))
}
