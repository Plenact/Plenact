// --------------------------------------------------------------------------------------------------
// @file       CardMovement.swift
// @brief      Canonical Card movement, ordering, and deletion transforms
// @details    Preserves complete records and related personal marks while allocating
//             destination-safe identities and validating boundaries.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Identifies a Card insertion boundary in an active List
///
/// @section    Purpose
///     Carries the target List and insertion context used to move content without replacing native
///     row identity.
///
struct BoardCardDropTarget: Equatable
{


    let listID:       Int   /* Destination list identity for the drop             */
    let beforeCardID: Int?  /* Insertion anchor; nil appends after existing cards */
}


///
/// Moves complete canonical card records within one Board
///
/// @section    Purpose
///     Share validated movement between drag/drop and the existing Move to List action
///
enum BoardCardMovement
{


    ///
    /// @fcn        BoardCardMovement.move(_:to:before:in:)
    /// @brief      Move the complete canonical card to a validated insertion boundary
    /// @details    Requires unambiguous active source and destination records and rejects
    ///             stale boundaries. Validates a copied list array before committing; a nil
    ///             boundary appends and only the card list title and position change.
    ///
    /// @param[in]     cardID        Board-local identity of the card being dragged or moved
    /// @param[in]     listID        Board-local identity of the destination list
    /// @param[in]     beforeCardID  Insertion-boundary card identity, or nil to append
    /// @param[in,out] lists         Canonical ordered Board lists used for movement or targeting
    ///
    /// @return     (Bool) whether the requested move changed card position or list membership
    ///
    /// @throws     CocoaError.validationMissingMandatoryProperty for invalid or ambiguous movement
    ///             records
    ///
    /// @post       Rejected and no-op movements leave lists unchanged; successful movement
    ///             preserves all other card fields
    ///
    @discardableResult
    static func move(
        _ cardID: Int, to listID: Int, before beforeCardID: Int? = nil,
        in lists: inout [KanbanList]
    ) throws -> Bool
    {


        let sources = lists.indices.filter
        {

            lists[$0].cards.contains
            {
                $0.id == cardID
            }

        }  /* Lists containing the requested card identity */


        guard sources.count == 1, let source = sources.first, /* Unique source list position */
        lists[source].cards.filter(
            {
                $0.id == cardID
            }).count == 1,
        lists.filter(
            {
                $0.id == listID
            }).count == 1,

        let destination = lists.firstIndex(where:
            {
                $0.id == listID && !$0.isArchived
            }
        ), /* Active destination list position */
        !lists[source].isArchived,
        let index = lists[source].cards.firstIndex(where:
            {
                $0.id == cardID
            })
        else
        {  /* Card position within the source list */


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        if beforeCardID == cardID, source == destination
        {


            return false
        }


        var updated = lists                                 /* Board snapshot changed only after movement validation */
        var card = updated[source].cards.remove(at: index)  /* Record removed from its source for reinsertion        */
        let insertion: Int                                  /* Destination offset after removing the source record   */

        if let beforeCardID
        {  /* Destination card serving as the insertion anchor */


            guard
            let position = updated[destination].cards.firstIndex(
                where:
                {  /* Current position of the insertion anchor */


                    $0.id == beforeCardID
                })
            else
            {


                throw CocoaError(.validationMissingMandatoryProperty)
            }


            insertion = position
        }
        else
        {


            insertion = updated[destination].cards.count
        }


        if source == destination && insertion == index
        {


            return false
        }


        card.listTitle = updated[destination].title
        updated[destination].cards.insert(card, at: insertion)
        DaySections.reveal(cardID, in: &updated[destination].cards)
        lists = updated

        return true
    }


    ///
    /// @fcn        BoardCardMovement.target(for:at:viewport:lists:listFrames:cardFrames:)
    /// @brief      Resolve a card insertion boundary from visible global-coordinate geometry
    /// @details    Rejects nonfinite points, invalid viewports, and locations outside active list
    ///             panels. Uses row midpoints, excludes the dragged card, and avoids appending past
    ///             unmeasured trailing rows.
    ///
    /// @param[in]  cardID      Board-local identity of the card being dragged or moved
    /// @param[in]  point       Pointer location in the Board window coordinate space
    /// @param[in]  viewport    Visible Board bounds in the same coordinates as the pointer
    /// @param[in]  lists       Canonical ordered Board lists used for movement or targeting
    /// @param[in]  listFrames  Measured global list-panel frames keyed by list identity
    /// @param[in]  cardFrames  Measured global card-row frames keyed by card identity
    ///
    /// @return     (BoardCardDropTarget?) validated insertion target, or nil when geometry cannot
    ///             establish a destination
    ///
    static func target(
        for cardID: Int, at point: CGPoint, viewport: CGRect,
        lists: [KanbanList], listFrames: [Int: CGRect],
        cardFrames: [Int: CGRect]
    ) -> BoardCardDropTarget?
    {


        guard point.x.isFinite, point.y.isFinite,
        viewport.origin.x.isFinite, viewport.origin.y.isFinite,
        viewport.width.isFinite, viewport.height.isFinite,
        viewport.width > 0, viewport.height > 0,
        viewport.contains(point),

        let list = lists.first(where:
            {
                !$0.isArchived && listFrames[$0.id]?.contains(point) == true
            })
        else
        {  /* Active list panel under the pointer */


            return nil
        }


        let cards = list.cards.filter
        {
            $0.id != cardID
        }  /* Destination rows excluding the dragged card          */

        let measured = cards.enumerated().filter
        {

            cardFrames[$0.element.id] != nil
        }  /* Rows with geometry available for insertion targeting */


        if let next = measured.first(where:
            {  /* First measured row below the pointer midpoint */


                point.y < (cardFrames[$0.element.id]?.midY ?? 0)
            })
        {

            return BoardCardDropTarget(listID: list.id, beforeCardID: next.element.id)
        }


        if let last = measured.last, cards.indices.contains(last.offset + 1)
        {  /* Final measured row preceding an unmeasured successor */


            return BoardCardDropTarget(listID: list.id, beforeCardID: cards[last.offset + 1].id)
        }


        guard cards.isEmpty || !measured.isEmpty else
        {


            return nil
        }


        return BoardCardDropTarget(listID: list.id, beforeCardID: nil)
    }

}


///
/// Reorders complete card records within one list
///
/// @section    Purpose
///     Share bounded in-list ordering behavior between Board and Today surfaces
///
enum BoardCardReordering
{


    ///
    /// @fcn        BoardCardReordering.move(_:to:in:)
    /// @brief      Move a card to a valid position without changing its content
    /// @details    Clamps the destination to the existing card range and moves the complete
    ///             record, allowing section dividers to participate like other rows
    ///
    /// @param[in]     cardID            Stable identity of the card being moved
    /// @param[in]     destinationIndex  Requested insertion position before movement
    /// @param[in,out] cards             Ordered records in the owning list
    ///
    /// @return     (Bool) whether the card order changed
    ///
    /// @post       Missing IDs and same-position moves leave cards unchanged
    ///
    @discardableResult
    static func move(_ cardID: Int, to destinationIndex: Int, in cards: inout [KanbanCard]) -> Bool
    {


        guard
        let sourceIndex = cards.firstIndex(where:
            {  /* Current position of the card being moved */


                $0.id == cardID
            }), !cards.isEmpty
        else
        {


            return false
        }


        let safeDestinationIndex = min(
            max(destinationIndex, 0), cards.count - 1) /* Valid insertion position within the existing records */

        guard sourceIndex != safeDestinationIndex else
        {


            return false
        }


        let movedCard = cards.remove(at: sourceIndex) /* Complete record temporarily removed for reinsertion */

        cards.insert(movedCard, at: safeDestinationIndex)

        return true
    }

}


///
/// Provides list-ordering and drag-edge calculations for the Board
///
/// @section    Purpose
///     Keep list reorder operations independent from the view gesture implementation
///
enum BoardListReordering
{


    ///
    /// @fcn        BoardListReordering.boundaryListID(_:in:)
    /// @brief      Resolve the first or last active list identity
    /// @details    Uses the current ordered list snapshot without changing list or card content
    ///
    /// @param[in]  boundary  Board edge to navigate to
    /// @param[in]  lists     Current active lists in display order
    ///
    /// @return     (Int?) boundary list identity, or nil when the Board has no active lists
    ///
    static func boundaryListID(_ boundary: BoardListBoundary, in lists: [KanbanList]) -> Int?
    {


        switch boundary
        {


        case .first:
            return lists.first?.id

        case .last:
            return lists.last?.id
        }

    }


    ///
    /// @fcn        BoardListReordering.boundary(forHorizontalSwipe:minimumDistance:)
    /// @brief      Resolve a deliberate horizontal title-area swipe to a Board edge
    /// @details    Rejects nonfinite, short, or predominantly vertical gestures. A leftward
    ///             swipe selects the last list; a rightward swipe selects the first,
    ///             matching the content movement of ordinary horizontal scrolling.
    ///
    /// @param[in]  translation      Completed drag translation in points
    /// @param[in]  minimumDistance  Minimum horizontal travel required to trigger a jump
    ///
    /// @return     (BoardListBoundary?) requested edge, or nil when the gesture is not a swipe
    ///
    static func boundary(
        forHorizontalSwipe translation: CGSize,
        minimumDistance: CGFloat = 48
    ) -> BoardListBoundary?
    {


        guard translation.width.isFinite, translation.height.isFinite,
        minimumDistance.isFinite, minimumDistance > 0,
        abs(translation.width) >= minimumDistance,
        abs(translation.width) > abs(translation.height) * 1.4
        else
        {


            return nil
        }


        return translation.width < 0 ? .last : .first
    }


    ///
    /// @fcn        BoardListReordering.move(_:to:in:)
    /// @brief      Move a list to a destination index
    /// @details    Removes the identified list and inserts it at the requested position
    ///
    /// @param[in]     listID       Identity of the list to move
    /// @param[in]     destination  Destination index in the list array
    /// @param[in,out] lists        Mutable ordered list collection
    ///
    /// @return     (Bool) whether the requested move was performed
    ///
    /// @post       Invalid identities, indices, or same-position moves leave lists unchanged
    ///
    @discardableResult
    static func move(_ listID: Int, to destination: Int, in lists: inout [KanbanList]) -> Bool
    {


        guard
        let source = lists.firstIndex(where:
            {  /* Current position of the list being reordered */


                $0.id == listID
            }),
        lists.indices.contains(destination), source != destination
        else
        {
            return false
        }


        let list = lists.remove(at: source) /* List temporarily removed for boundary insertion */

        lists.insert(list, at: destination)

        return true
    }


    ///
    /// Identifies a horizontal Board boundary
    ///
    /// @section    Purpose
    ///     Represents the leading or trailing edge for direct List navigation and drag-related
    ///     paging.
    ///
    enum BoardListBoundary
    {


        case first
        case last
    }


    ///
    /// @fcn        BoardListReordering.edgeDirection(at:viewportWidth:)
    /// @brief      Resolve the horizontal edge direction for a drag location
    /// @details    Returns a direction only when the location falls inside an edge activation zone
    ///
    /// @param[in]  x              Horizontal drag location
    /// @param[in]  viewportWidth  Width of the visible board viewport
    ///
    /// @return     (Int) -1 for the leading edge, 1 for the trailing edge, or 0 otherwise
    ///
    /// @post       No list or drag state is modified
    ///
    static func edgeDirection(at x: CGFloat, viewportWidth: CGFloat) -> Int
    {


        guard x.isFinite, viewportWidth.isFinite, viewportWidth > 0 else
        {


            return 0
        }


        let edgeWidth = min(64, viewportWidth * 0.18) /* Edge activation zone scaled to the visible width */

        if x < edgeWidth
        {


            return -1
        }


        if x > viewportWidth - edgeWidth
        {


            return 1
        }


        return 0
    }

}


///
/// Moves a Note between active personal collections without copying its content
///
/// @section    Purpose
///     Keep cross-collection location changes atomic and preserve collection-local identity rules
///
enum PersonalCollectionNoteMovement
{


    ///
    /// @fcn        PersonalCollectionNoteMovement.move(noteID:from:to:in:)
    /// @brief      Move one active Note to an active personal List
    /// @details    Preserves all Note fields and bookmarks. Card IDs are collection-local; an ID
    ///             collision in the destination receives a fresh destination-local ID
    /// @param[in]     noteID         Active source Note ID
    /// @param[in]     sourceID       Owning collection identity
    /// @param[in]     destinationID  Target active personal List identity
    /// @param[in,out] collections    Complete local collection snapshot
    /// @return     (KanbanCard) moved Note with its destination-local identity and title
    /// @throws     CocoaError when the source, Note, or destination is invalid or ambiguous
    ///
    static func move(
        noteID: Int,
        from sourceID: UUID,
        to destinationID: UUID,
        in collections: inout [PersonalCollection]
    ) throws -> KanbanCard
    {


        guard sourceID != destinationID,
        let sourceIndex = collections.firstIndex(where:
            {
                $0.id == sourceID && $0.isActive
            }
        ), /* Active collection currently owning the Note */
        let destinationIndex = collections.firstIndex(where:
            {  /* Active personal List receiving the Note     */

                $0.id == destinationID && $0.kind == .list && $0.isActive
            })
        else
        {


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        var source = collections[sourceIndex]            /* Source collection snapshot receiving the removal   */
        var destination = collections[destinationIndex]  /* Destination collection snapshot receiving the Note */
        let sourceMatches = source.lists.indices.flatMap
        {

        listIndex in /* Matching Note positions used to reject ambiguity   */
            source.lists[listIndex].cards.indices.compactMap
            {
                cardIndex in
                !source.lists[listIndex].isArchived && source.lists[listIndex].cards[cardIndex].id == noteID
                ? (listIndex, cardIndex)
                : nil
            }

        }


        guard sourceMatches.count == 1,
        let (sourceListIndex, cardIndex) = sourceMatches.first, /* Unique source column and record positions */
        source.lists[sourceListIndex].cards[cardIndex].presentation == .note,
        !source.lists[sourceListIndex].cards[cardIndex].isSectionDivider,
        let destinationListIndex = destination.lists.firstIndex(where:
            {
                !$0.isArchived
            })
        else
        {  /* Active destination column accepting the Note */


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        var moved = source.lists[sourceListIndex].cards.remove(
            at: cardIndex) /* Note detached from its source before relocation            */
        let destinationIDs = Set(
            destination.lists.flatMap(\.allCards).map(\.id)) /* Active and archived identities reserved in the destination */

        var destinationCardID = moved.id /* Resulting Note identity adjusted only for a collision */

        if destinationIDs.contains(moved.id)
        {


            let (nextID, overflow) = (destinationIDs.max() ?? -1).addingReportingOverflow(
                1) /* Next unused identity and its overflow status */
            guard !overflow else
            {


                throw CocoaError(.validationNumberTooLarge)
            }

            destinationCardID = nextID
        }


        moved = moved.replacingLocation(id: destinationCardID, listTitle: destination.title)

        let wasSaved = source.savedCardIDs.remove(noteID) != nil /* Bookmark membership transferred with the Note */

        if wasSaved
        {


            destination.savedCardIDs.insert(moved.id)
        }


        destination.lists[destinationListIndex].cards.append(moved)
        collections[sourceIndex] = source
        collections[destinationIndex] = destination

        return moved
    }

}


///
/// Applies permanent removal to a complete Board snapshot
///
/// @section    Purpose
///     Keep active/archive removal and Board-local bookmark cleanup consistent
///
enum BoardContentDeletion
{


    ///
    /// @fcn        BoardContentDeletion.card(_:in:savedCardIDs:)
    /// @brief      Remove a card from every active/archive partition of its owning Board
    /// @details    Only the supplied Board is inspected; equal IDs in other collections are
    ///             unaffected
    ///
    /// @param[in]     id            Board-local card identity
    /// @param[in,out] lists         Complete Board snapshot
    /// @param[in,out] savedCardIDs  Bookmarks belonging to that Board
    ///
    /// @return     (Void) removes matching records and their bookmark
    ///
    static func card(_ id: Int, in lists: inout [KanbanList], savedCardIDs: inout Set<Int>)
    {


        for index in lists.indices
        {


            lists[index].cards.removeAll
            {
                $0.id == id
            }

            lists[index].archivedCards.removeAll
            {
                $0.id == id
            }

        }


        savedCardIDs.remove(id)
    }


    ///
    /// @fcn        BoardContentDeletion.list(_:in:savedCardIDs:)
    /// @brief      Remove a list together with its active and archived cards
    /// @details    Removes bookmarks only for identities owned by the removed list
    ///
    /// @param[in]     id            Board-local list identity
    /// @param[in,out] lists         Complete Board snapshot
    /// @param[in,out] savedCardIDs  Bookmarks belonging to that Board
    ///
    /// @return     (Void) removes the list and contained bookmarks
    ///
    static func list(_ id: Int, in lists: inout [KanbanList], savedCardIDs: inout Set<Int>)
    {


        let removedIDs = Set(
            lists.filter
            {
                $0.id == id
            } .flatMap(\.allCards).map(\.id)) /* Card bookmarks to prune with the deleted list */

        lists.removeAll
        {
            $0.id == id
        }

        savedCardIDs.subtract(removedIDs)
    }

}


///
/// Identifies an owner-qualified Card movement destination
///
/// @section    Purpose
///     Pairs the destination List with its Board owner; legacy nil ownership denotes the active
///     Week context.
///
struct CardMoveDestination: Identifiable, Hashable
{


    let collectionID: UUID?
    let listID:       Int
    let title:        String
    let group:        String
    var columnTitle:  String? = nil
    var id:           String
    {
            "\(collectionID?.uuidString ?? "week"):\(listID)"
    }

}


///
/// Builds both sides of a cross-Board Card transfer
///
/// @section    Purpose
///     Preserves hidden fields, allocates destination-safe identity, and relocates bookmarks before
///     publishing changed owners.
///
enum CrossBoardCardMovement
{


    ///
    /// @fcn        CrossBoardCardMovement.move
    /// @brief      Move a card between current-week and personal-owner lists
    /// @details    Validates unique source and active destination, allocates a collision-free destination card ID
    ///             when crossing owners, and transfers the moved card's bookmark with its content.
    ///
    /// @param[in]      card         Card or note being inspected or changed
    /// @param[in]      sourceID     Identity of the source owner
    /// @param[in]      destination  Chosen calendar or personal-list destination
    /// @param[in,out]  week         Current planning-week lists, updated in place after a valid movement
    /// @param[in,out]  collections  Personal collection values available to the operation
    /// @param[in,out]  saved        Owner-local saved-card identities, updated when bookmarked content moves
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`,
    ///             `CocoaError(.validationNumberTooLarge)`. Errors from throwing dependencies propagate unless
    ///             handled within this operation.
    ///
    static func move(
        _ card: KanbanCard, from sourceID: UUID?, to destination: CardMoveDestination,
        week: inout [KanbanList], collections: inout [PersonalCollection],
        saved: inout Set<Int>
    ) throws
    {

        var sourceLists: [KanbanList]
        var sourceSaved: Set<Int>
        if let sourceID
        {

            guard let source = collections.first(where:
                {
                    $0.id == sourceID && $0.isActive
                }) else
            {

                throw CocoaError(.validationMissingMandatoryProperty)
            }

            sourceLists = source.lists;
            sourceSaved = source.savedCardIDs
        }
        else
        {

            sourceLists = week;
            sourceSaved = saved
        }

        let matches = sourceLists.indices.filter
        {

            !sourceLists[$0].isArchived && sourceLists[$0].cards.contains
            {
                $0.id == card.id
            }

        }

        guard matches.count == 1, let sourceIndex = matches.first,
        !(sourceID == destination.collectionID && sourceLists[sourceIndex].id == destination.listID)
        else
        {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var targetLists: [KanbanList]
        var targetSaved: Set<Int>
        let sameBoard = sourceID == destination.collectionID
        if sameBoard
        {

            targetLists = sourceLists;
            targetSaved = sourceSaved
        }
        else if let targetID = destination.collectionID
        {

            guard let target = collections.first(where:
                {
                    $0.id == targetID && $0.isActive
                }) else
            {

                throw CocoaError(.validationMissingMandatoryProperty)
            }

            targetLists = target.lists;
            targetSaved = target.savedCardIDs
        }
        else
        {

            targetLists = week;
            targetSaved = saved
        }

        guard let targetIndex = targetLists.firstIndex(where:
            {
                $0.id == destination.listID && !$0.isArchived
            }) else
        {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var newID = card.id
        let reserved = Set(targetLists.flatMap(\.allCards).map(\.id))
        if !sameBoard && reserved.contains(newID)
        {

            let (next, overflow) = (reserved.max() ?? -1).addingReportingOverflow(1)
            guard !overflow else
            {
                throw CocoaError(.validationNumberTooLarge)
            }

            newID = next
        }

        sourceLists[sourceIndex].cards.removeAll
        {
            $0.id == card.id
        }

        if sameBoard
        {
            targetLists = sourceLists
        }

        targetLists[targetIndex].cards.append(
            card.replacingLocation(id: newID, listTitle: targetLists[targetIndex].title))
        if !sameBoard, sourceSaved.remove(card.id) != nil
        {
            targetSaved.insert(newID)
        }

        if sameBoard
        {
            sourceLists = targetLists;
            sourceSaved = targetSaved
        }

        if let sourceID, let index = collections.firstIndex(where:
            {
                $0.id == sourceID
            })
        {

            collections[index].lists = sourceLists;
            collections[index].savedCardIDs = sourceSaved
        }
        else
        {

            week = sourceLists;
            saved = sourceSaved
        }

        if !sameBoard
        {

            if let targetID = destination.collectionID, let index = collections.firstIndex(where:
                {
                    $0.id == targetID
                })
            {

                collections[index].lists = targetLists;
                collections[index].savedCardIDs = targetSaved
            }
            else
            {

                week = targetLists;
                saved = targetSaved
            }

        }

    }

}
