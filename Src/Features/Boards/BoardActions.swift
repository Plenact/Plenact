// --------------------------------------------------------------------------------------------------
// @file       BoardActions.swift
// @brief      Board, focused List, and reusable workspace presentation
// @details    Composes standard, panoramic, and gallery Boards alongside focused Day and personal
//             Lists. Coordinates native Card dragging and swipe routing, inline List naming and
//             item capture, temporary List guidance, section movement, appearance, archives, and
//             configurable corner Back navigation.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// ContentView behavior grouped separately from stored view state
///
/// @section    Purpose
///     Keep owner-scoped operations with the existing view while retaining its state and lifecycle.
///
extension ContentView
{


    ///
    /// @fcn        ContentView.saveBoardAppearance
    /// @brief      Save board styling and optionally restore list inheritance
    /// @details    Uses the supplied appearance binding or the checked current-week encoding path; reports failures
    ///             and returns false when the change cannot be saved.
    ///
    /// @param[in]  appearance  Optional or explicit appearance overrides supplied by the caller
    /// @param[in]  applyToAll  Whether list surface and text overrides should inherit the board settings
    ///
    /// @return     (Bool) true after the appearance change is accepted; false if storage is invalid or saving fails
    ///
    func saveBoardAppearance(_ appearance: BoardAppearance, applyToAll: Bool) -> Bool
    {

        do
        {

            if let appearanceBinding
            {

                appearanceBinding.wrappedValue = appearance
            }
            else
            {

                guard personalCollectionID == nil else
                {
                    return false
                }

                _ = try BoardAppearance.decodeWeek(weekAppearanceData)
                weekAppearanceData = try JSONEncoder().encode(appearance)
            }

            if applyToAll
            {

                lists = BoardAppearance.inheritingLists(lists)
                archivedLists = BoardAppearance.inheritingLists(archivedLists)
            }

            return true
        }
        catch
        {

            DatabaseActivity.shared.report(
                                    "Could not save Board Appearance: \(error.localizedDescription). Existing settings have been retained.")
            return false
        }

    }


    ///
    /// @fcn        ContentView.refreshActiveDragGeometry
    /// @brief      Invalidate geometry while a card or list drag is active
    /// @details    Advances the revision only when a drag exists, avoiding unnecessary geometry refreshes at rest.
    ///
    /// @return     (Void) no return value
    ///
    func refreshActiveDragGeometry()
    {

        if draggedListID != nil || draggedCardID != nil
        {
            dragGeometryRevision &+= 1
        }

    }


    ///
    /// @fcn        ContentView.persistViewport
    /// @brief      Save the board's current presentation and zoom state
    /// @details    Copies zoom, panorama, gallery, presentation, and visible-list values into owner-scoped memory
    ///             before flushing.
    ///
    /// @return     (Void) no return value
    ///
    func persistViewport()
    {

        viewportMemory.state.scale = Double(boardScale)
        viewportMemory.state.panoramic = isPanoramic
        viewportMemory.state.gallery = isGallery
        viewportMemory.state.presentation = presentation.rawValue
        viewportMemory.state.visibleListID = visibleListID
        viewportMemory.flush()
    }


    ///
    /// @fcn        ContentView.resetBoardZoom
    /// @brief      Reset zoom to the current mode's baseline
    /// @details    Ignores requests during dragging and disables the transition animation when Reduce Motion is
    ///             enabled.
    ///
    /// @return     (Void) no return value
    ///
    func resetBoardZoom()
    {

        guard draggedListID == nil, draggedCardID == nil else
        {
            return
        }

        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2))
        {

            boardScale = BoardPanoramicZoom.preset(panoramic: isPanoramic)
        }

    }


    ///
    /// @fcn        ContentView.adjustBoardZoom
    /// @brief      Adjust zoom through accessibility controls
    /// @details    Applies a bounded fifteen percent step outside gallery mode and ignores requests during an active
    ///             drag.
    ///
    /// @param[in]  direction  Accessibility adjustment direction selecting a zoom increment or decrement
    ///
    /// @return     (Void) no return value
    ///
    func adjustBoardZoom(_ direction: AccessibilityAdjustmentDirection)
    {

        guard !isGallery, draggedListID == nil, draggedCardID == nil else
        {
            return
        }

        switch direction
        {

        case .increment:
            boardScale = BoardPanoramicZoom.clamped(boardScale * 1.15)
        case .decrement:
            boardScale = BoardPanoramicZoom.clamped(boardScale / 1.15)
        @unknown default:
            break
        }

    }


    ///
    /// @fcn        ContentView.toggleBoardZoom
    /// @brief      Toggle between panoramic and standard board modes
    /// @details    Resets zoom to the new mode's preset and respects Reduce Motion; active drags prevent mode
    ///             changes.
    ///
    /// @return     (Void) no return value
    ///
    func toggleBoardZoom()
    {

        guard draggedListID == nil, draggedCardID == nil else
        {
            return
        }

        withAnimation(reducesMotion ? nil : .smooth(duration: 0.25))
        {

            isPanoramic.toggle()
            boardScale = BoardPanoramicZoom.preset(panoramic: isPanoramic)
        }

    }


    ///
    /// @fcn        ContentView.openPendingBoardTarget(using:)
    /// @brief      Consume a pending list/card navigation request
    /// @details    Scrolls an existing active list into view and, for an existing target card,
    ///             replaces the detail path with that card. Missing lists invalidate both targets
    ///
    /// @param[in]  listProxy  Proxy for the horizontal list viewport
    ///
    /// @return     (Void) updates scroll position and optional card navigation
    ///
    /// @post       Both pending targets are cleared; a missing card leaves the existing path
    ///             unchanged
    ///
    func openPendingBoardTarget(using listProxy: ScrollViewProxy)
    {


        guard let targetListID = boardTargetListID, /* Requested list identity to reveal */
        lists.contains(where:
            {
                $0.id == targetListID
            })
        else
        {


            boardTargetListID = nil
            boardTargetCardID = nil

            return
        }


        viewportMemory.horizontalRestoreAllowed = false
        visibleListID = targetListID
        listProxy.scrollTo(targetListID, anchor: presentation == .standard ? .center : .leading)

        if let targetCardID = boardTargetCardID, /* Requested card identity to open                  */
        let card = lists.first(where:
            {
                $0.id == targetListID
            })?.cards.first(where:
            {
                $0.id == targetCardID
            })
        {  /* Requested record resolved in its containing list */

            navigationPath = NavigationPath()
            navigationPath.append(card)
            openedDirectItem = directItemReturn != nil
        }


        boardTargetListID = nil
        boardTargetCardID = nil
    }


    ///
    /// @fcn        ContentView.requestBoundaryJump(_:)
    /// @brief      Request an animated jump to one end of the active Board
    /// @details    Stores the requested edge and increments a revision so repeated taps to the
    ///             same edge trigger a fresh scroll request
    ///
    /// @param[in]  boundary  First or last active list to reveal
    ///
    /// @return     (Void) schedules a Board viewport scroll without changing list order
    ///
    func requestBoundaryJump(_ boundary: BoardListReordering.BoardListBoundary)
    {


        boardBoundaryJumpTarget = boundary
        boardBoundaryJumpRequest += 1
    }


    ///
    /// @fcn        ContentView.renameMember(from:to:)
    /// @brief      Rename a member across the board
    /// @details    Renames matching manual assignments and comment authors on active cards, trims
    ///             assignment names, and deduplicates manual names or registered-user identities.
    ///             Updates the current author and migrates its icon color when applicable
    ///
    /// @param[in]  currentName   Existing member name to replace
    /// @param[in]  proposedName  Proposed new name; surrounding whitespace is trimmed
    ///
    /// @return     (Void) updates card assignments, authored comments, current-user display, and
    ///             color mapping
    ///
    /// @pre        currentName identifies the member being renamed
    /// @post       Registered-user identities/display names are not renamed, beyond whitespace
    ///             trimming; archived content is untouched. Blank proposals leave all state
    ///             unchanged
    /// @note       An empty proposed name is ignored; if the new name already has a color, that
    ///             color is retained
    ///
    func renameMember(from currentName: String, to proposedName: String)
    {


        let updatedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines) /* Trimmed replacement name */

        guard !updatedName.isEmpty else
        {


            return
        }


        let currentKey = currentName.lowercased()  /* Normalized key for the current member name */
        let updatedKey = updatedName.lowercased()  /* Normalized key for the updated member name */

        for listIndex in lists.indices
        {


            for cardIndex in lists[listIndex].cards.indices
            {


                var updatedCard = lists[listIndex].cards[
                cardIndex]                       /* Copy of the current card for in-place updates     */
                var seenNames: Set<String> = []  /* Track unique member names within the current card */

                updatedCard.members = updatedCard.members.compactMap
                {
                    assignee in

                    let trimmedMember = assignee.displayName.trimmingCharacters(
                        in: .whitespacesAndNewlines) /* Existing display name   */
                    let renamedMember =
                    assignee.kind == .manual
                    && trimmedMember.lowercased() == currentKey /* Match only manual names */
                    ? updatedName
                    : trimmedMember /* Name retained or updated for this assignment */
                    let normalizedName =
                    assignee.kind == .registeredUser /* Namespace stable IDs separately from names   */
                    ? "user:\(assignee.userID ?? assignee.id.uuidString)"
                    : "manual:\(renamedMember.lowercased())" /* Stable deduplication key */

                    guard !renamedMember.isEmpty, seenNames.insert(normalizedName).inserted else
                    {


                        return nil
                    }


                    return CardAssignee(
                        id: assignee.id,
                        kind: assignee.kind,
                        userID: assignee.userID,
                        displayName: renamedMember
                    )
                }


                updatedCard.comments = updatedCard.comments.map
                {
                    comment in

                    guard comment.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentKey
                    else
                    {


                        return comment
                    }


                    return KanbanComment(
                        id: comment.id,
                        author: updatedName,
                        body: comment.body,
                        createdAt: comment.createdAt
                    )
                }


                lists[listIndex].cards[cardIndex] = updatedCard
            }

        }


        if currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentKey
        {


            currentUserName = updatedName
        }


        if currentKey != updatedKey, let existingColor = memberColors.removeValue(forKey: currentKey)
        {  /* Preserve the old icon color */


            memberColors[updatedKey] = memberColors[updatedKey] ?? existingColor
        }

    }


    ///
    /// @fcn        ContentView.removeMember(_:)
    /// @brief      Remove a member from board assignments
    /// @details    Removes matching names from active cards and clears their board icon color while
    ///             preserving historical comments
    ///
    /// @param[in]  memberName  Member name to remove; comparison ignores surrounding whitespace and
    ///             case
    ///
    /// @return     (Void) updates the board and member color state
    ///
    /// @pre        memberName identifies a member currently assigned to at least one card
    /// @post       Matching active-card assignments are removed; comments and archives remain
    ///             unchanged. Removing the current author name resets its display value to You
    ///
    func removeMember(_ memberName: String)
    {


        let normalizedMemberName = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() /* Normalized removal key */

        guard !normalizedMemberName.isEmpty else
        {


            return
        }


        for listIndex in lists.indices
        {


            for cardIndex in lists[listIndex].cards.indices
            {


                lists[listIndex].cards[cardIndex].members.removeAll
                {
                    member in

                    member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == normalizedMemberName
                }

            }

        }


        memberColors.removeValue(forKey: normalizedMemberName)

        if currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedMemberName
        {


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
    func setMemberColor(_ memberName: String, color: Color)
    {


        memberColors[memberName.lowercased()] = color
    }


    ///
    /// @fcn        ContentView.dayDate(for:)
    /// @brief      Resolve the calendar date assigned to a Board List
    /// @details    Finds the current or explicitly owned calendar Week, resolves its List-to-day
    ///             mapping, and returns nil when the workspace or mapping is unavailable.
    ///
    /// @param[in]  listID  Owner-local List identity used to resolve its represented calendar date
    ///
    /// @return     (Date?) represented local day, or nil for an unresolved or undated List
    ///
    func dayDate(for listID: Int) -> Date?
    {

        guard let document = planningCalendarAccess?.document,
        let week = document.weeks.first(where:
            {

                personalCollectionID == nil
                ? $0.startKey == document.currentWeekKey : $0.id == personalCollectionID
            }),
        let key = week.dayListIDs.first(where:
            {
                $0.value == listID
            })?.key
        else
        {
            return nil
        }

        return PlanningDate.date(key)
    }


    ///
    /// @fcn        ContentView.addList
    /// @brief      Append a uniquely named empty list to the board
    /// @details    Allocates an ID beyond active and archived lists, avoids case-insensitive title collisions, and
    ///             makes the new list the visible target. Focuses its inline column title and selects the generated
    ///             name so typing replaces it without presenting a separate editor.
    ///
    /// @return     (Void) no return value
    ///
    func addList()
    {


        let nextListID: Int
        do
        {
            nextListID = try PortableCreationIdentity.reserve(proposed: ((lists + archivedLists).map(\.id).max() ?? -1) + 1)
        }
        catch
        {
            DatabaseActivity.shared.report("The new List identity could not be reserved. Please try again.")
            return
        }
        let existingTitles = Set(lists.map
            {
                $0.title.lowercased()
            })                     /* Normalized current titles */
        var newTitle = "New List"  /* First candidate list name */
        var suffix = 2             /* Duplicate-title suffix    */

        while existingTitles.contains(newTitle.lowercased())
        {


            newTitle = "New List \(suffix)"
            suffix += 1
        }


        let newList = KanbanList(id: nextListID, title: newTitle, cards: [])
        lists.append(newList)
        visibleListID = nextListID
        boardTargetListID = nextListID
        namingNewListID = nextListID
    }


    ///
    /// @fcn        ContentView.addCard(_:)
    /// @brief      Save and publish a complete Board-scoped capture
    /// @details    Allocates identities across active and archived content, constructs all
    ///             submitted items, and persists the complete snapshot before updating bindings.
    ///             Failed validation or saving leaves the draft available; success requests a
    ///             reveal of the first created item.
    ///
    /// @param[in]  capture  Complete destination-scoped creation submission with writing, media,
    ///             and scheduling
    ///
    /// @return     (Bool) true when new content was saved and published
    ///
    func addCard(_ capture: QuickCaptureSubmission) -> Bool
    {

        guard let listIndex = lists.firstIndex(where:
            {
                $0.id == capture.listID
            }) else
        {
            return false
        }

        let proposedCardID = ((lists + archivedLists).flatMap
            {
                $0.allCards.map(\.id)
            } .max() ?? -1) + 1
        let nextCardID: Int
        do
        {
            nextCardID = try PortableCreationIdentity.reserve(proposed: proposedCardID,
                count: max(1, MultilineEntry.titles(capture.title).count))
        }
        catch
        {
            DatabaseActivity.shared.report("The new Card identities could not be reserved. Your draft is unchanged.")
            return false
        }
        guard
        let created = ListItemCreation.items(
            capture, in: lists[listIndex], startingAt: nextCardID,
            calendar: planningCalendarAccess?.document.calendar ?? .current)
        else
        {
            return false
        }

        var snapshot = lists
        snapshot[listIndex].cards.append(contentsOf: created)
        if let first = created.first
        {
            DaySections.reveal(first.id, in: &snapshot[listIndex].cards)
        }

        do
        {

            if let onCommitDeletion
            {

                try onCommitDeletion(snapshot + archivedLists, savedCardIDs)
            }
            else
            {

                try KanbanBoardPersistence.saveListsChecked(snapshot + archivedLists)
            }

        }
        catch
        {

            DatabaseActivity.shared.report("Could not save the new item. Your draft is still open.")
            return false
        }

        lists = snapshot
        if let card = created.first
        {
            CreatedContentReveal.shared.request(listID: capture.listID, card: card)
        }

        return true
    }


    ///
    /// @fcn        ContentView.deleteCard(_:)
    /// @brief      Remove one confirmed card from this Board
    /// @details    Includes active/archive partitions and delegates save-first removal to the
    ///             owner; media cleanup occurs only after persistence succeeds
    ///
    /// @param[in]  cardID  Stable identifier of the card to delete
    ///
    /// @return     (Bool) whether the card and bookmark were successfully removed
    ///
    /// @post       Failed saves leave the canonical records unchanged
    ///
    @discardableResult
    func deleteCard(_ cardID: Int) -> Bool
    {


        var snapshot = lists + archivedLists  /* Complete Board snapshot for checked removal  */
        var bookmarks = savedCardIDs          /* Saved identities pruned with removed records */

        BoardContentDeletion.card(cardID, in: &snapshot, savedCardIDs: &bookmarks)

        return commitDeletion(snapshot, bookmarks: bookmarks)
    }


    ///
    /// @fcn        ContentView.deleteList(_:)
    /// @brief      Permanently remove a confirmed list and its retained cards
    /// @details    Updates both partitions and removes only this Board's contained bookmarks
    ///
    /// @param[in]  id  List identity in this Board
    ///
    /// @return     (Void) updates caller-owned state without pruning unsaved media references
    ///
    func deleteList(_ id: Int)
    {


        var snapshot = lists + archivedLists  /* Complete Board snapshot for checked removal  */
        var bookmarks = savedCardIDs          /* Saved identities pruned with removed records */

        BoardContentDeletion.list(id, in: &snapshot, savedCardIDs: &bookmarks)
        commitDeletion(snapshot, bookmarks: bookmarks)
    }


    ///
    /// @fcn        ContentView.commitDeletion(_:bookmarks:)
    /// @brief      Delegate permanent removal to the owner's save-first boundary
    /// @details    Production callers persist the complete snapshot before publishing state
    ///
    /// @param[in]  snapshot   Proposed remaining lists including archives
    /// @param[in]  bookmarks  Remaining Board-local bookmarks
    ///
    /// @return     (Bool) successful persistence/publication, or false after a reported error
    ///
    @discardableResult
    func commitDeletion(_ snapshot: [KanbanList], bookmarks: Set<Int>) -> Bool
    {


        do
        {


            if let onCommitDeletion
            {  /* Caller-supplied save-first deletion boundary */


                try onCommitDeletion(snapshot, bookmarks)
            }
            else
            {


                lists = snapshot.filter
                {
                    !$0.isArchived
                }

                archivedLists = snapshot.filter(\.isArchived)
                savedCardIDs = bookmarks
            }


            return true
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not delete content: \(error.localizedDescription) It has been retained.")

            return false
        }

    }


    ///
    /// @fcn        ContentView.moveSection(in:sectionID:offset:)
    /// @brief      Reorder an entire named section within its List
    /// @details    Finds the source List and delegates boundary-aware movement to DaySections,
    ///             retaining each member's identity and content. An unavailable List leaves state
    ///             unchanged.
    ///
    /// @param[in]  listID     Owner-local List identity used to resolve its represented calendar date
    /// @param[in]  sectionID  Named divider identity of the complete section to reorder
    /// @param[in]  offset     Signed section displacement supplied to the section-aware ordering
    ///             helper
    ///
    /// @return     (Void) publishes the resulting section order in the bound List
    ///
    func moveSection(in listID: Int, sectionID: Int, offset: Int)
    {

        guard let index = lists.firstIndex(where:
            {
                $0.id == listID
            }) else
        {
            return
        }

        lists[index].cards = DaySections.moved(lists[index].cards, sectionID: sectionID, offset: offset)
    }


    ///
    /// @fcn        ContentView.moveCard
    /// @brief      Reorder a card or an entire named section
    /// @details    Uses the canonical section-aware ordering helper, reveals the moved card's section, and animates
    ///             only a changed order.
    ///
    /// @param[in]  listID            Numeric list identity within its owner
    /// @param[in]  cardID            Numeric card identity within its owner
    /// @param[in]  destinationIndex  Canonical insertion index in the destination list
    ///
    /// @return     (Void) no return value
    ///
    func moveCard(in listID: Int, cardID: Int, toIndex destinationIndex: Int)
    {


        guard
        let listIndex = lists.firstIndex(where:
            {  /* Position of the list containing the reordered card */


                $0.id == listID
            })
        else
        {


            return
        }


        var cards = lists[listIndex].cards /* Mutable card-order copy */

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
    /// @fcn        ContentView.copyList(with:)
    /// @brief      Insert a copy of the selected list beside its source
    /// @details    Reserves new IDs across active/archive content and copies active cards with
    ///             their full state and shared attachment references. Archived cards and list
    ///             metadata are not copied; the new list uses model defaults and a Copy title
    ///             suffix
    ///
    /// @param[in]  listID  Stable identifier of the list to copy
    ///
    /// @return     (Void) inserts the copied list immediately after the source list
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The board contains a distinct copy with unique list and card identifiers
    ///
    func copyList(with listID: Int)
    {


        guard
        let sourceIndex = lists.firstIndex(where:
            {  /* List position before the requested reorder */


                $0.id == listID
            })
        else
        {


            return
        }


        let copiedList = ListCopying.copy(lists[sourceIndex], into: lists + archivedLists, crossBoard: false)
        lists.insert(copiedList, at: sourceIndex + 1)
    }


    ///
    /// @fcn        ContentView.moveList(with:by:)
    /// @brief      Move a list relative to its current board position
    /// @details    Removes the matching list and reinserts it at the index specified by the offset
    ///
    /// @param[in]  listID  Stable identifier of the list to move
    /// @param[in]  offset  Number of positions to move; negative moves earlier and positive moves
    ///             later
    ///
    /// @return     (Void) reorders the board when the destination index is valid
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The list occupies its destination index, or the board is unchanged for an
    ///             invalid destination
    ///
    func moveList(with listID: Int, by offset: Int)
    {


        guard
        let sourceIndex = lists.firstIndex(where:
            {  /* List position at the start of a drag reorder */


                $0.id == listID
            })
        else
        {


            return
        }


        let destinationIndex = sourceIndex + offset /* Requested destination position */

        guard lists.indices.contains(destinationIndex) else
        {


            return
        }


        BoardListReordering.move(listID, to: destinationIndex, in: &lists)
    }


    ///
    /// @fcn        ContentView.updateListDrag(_:value:)
    /// @brief      Track a held list and reorder it when the pointer crosses a neighbor
    /// @details    Claims the first list, captures its grab offset on the first drag value, and
    ///             moves at most one neighboring position per update using viewport centers
    ///
    /// @param[in]  listID  List whose title-area gesture is reporting
    /// @param[in]  value   Optional drag geometry; nil can claim the hold without moving
    ///
    /// @return     (Void) updates drag state and potentially active-list order
    ///
    /// @post       Reports for another held list are ignored; reorder animation honors Reduce
    ///             Motion
    ///
    func updateListDrag(_ listID: Int, value: DragGesture.Value?)
    {


        guard draggedCardID == nil, !boardPinch.active else
        {

            return
        }


        if draggedListID == nil
        {


            listDragInitialCenter = dragGeometry.centers[listID]
            withAnimation(reducesMotion ? nil : .smooth(duration: 0.25))
            {

                draggedListID = listID
            }

        }


        guard draggedListID == listID, let value else
        {  /* Current gesture sample for the active list drag */


            return
        }


        if listDragLocation == nil
        {


            listDragGrabOffset =
            (value.startLocation.x - (listDragInitialCenter ?? value.startLocation.x))
            * (listDragScale / boardZoomScale)
        }


        listDragLocation = value.location.x
        listDragTilt = reducesMotion ? 0 : max(-3, min(3, Double(value.translation.width / 40)))

        guard
        let source = lists.firstIndex(where:
            {  /* Current position of the dragged list */


                $0.id == listID
            }),
        let center = dragGeometry.centers[listID]
        else
        {
            return
        }  /* Measured center of the dragged list                 */

        let direction = value.location.x > center ? 1 : -1  /* Neighbor direction selected by the pointer position */
        let destination = source + direction                /* Adjacent list position considered for swapping      */

        guard lists.indices.contains(destination),
        let targetCenter = dragGeometry.centers[
        lists[destination].id], /* Neighbor center used as the reorder threshold */
        direction > 0 ? value.location.x > targetCenter : value.location.x < targetCenter
        else
        {
            return
        }

        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2))
        {

            _ = BoardListReordering.move(listID, to: destination, in: &lists)
        }

    }


    ///
    /// @fcn        ContentView.endListDrag(_:)
    /// @brief      Release drag state for the currently held list
    /// @details    Clears the held identity, pointer location, and grab offset only for the
    ///             matching list
    ///
    /// @param[in]  listID  Identity ending its hold/drag interaction
    ///
    /// @return     (Void) resets transient drag tracking
    ///
    /// @post       List order stays as last updated; clearing the identity cancels edge-scrolling
    ///             work
    ///
    func endListDrag(_ listID: Int)
    {


        guard draggedListID == listID else
        {


            return
        }


        withAnimation(reducesMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85))
        {

            draggedListID = nil
            listDragLocation = nil
            listDragGrabOffset = 0
            listDragInitialCenter = nil
            listDragTilt = 0
        }

    }


    ///
    /// @fcn        ContentView.listDragOffset(for:)
    /// @brief      Calculate the visual translation of the held list
    /// @details    Subtracts the current layout center and captured grab offset from pointer
    ///             position
    ///
    /// @param[in]  listID  List whose horizontal translation is requested
    ///
    /// @return     (CGFloat) translation in points, or zero without matching drag/geometry state
    ///
    /// @post       Layout and drag state remain unchanged
    ///
    func listDragOffset(for listID: Int) -> CGFloat
    {


        guard draggedListID == listID,
        let location = listDragLocation, /* Pointer position driving the dragged list's offset */
        let center = dragGeometry.centers[listID]
        else
        {
            return 0
        }  /* Measured resting center of the dragged list        */

        return location - center - listDragGrabOffset
    }


    ///
    /// @fcn        ContentView.sortList(with:ascending:)
    /// @brief      Sort a list's cards by their titles
    /// @details    Uses localized standard title comparison within divider-separated sections;
    ///             divider positions and section membership are preserved
    ///
    /// @param[in]  listID     Stable identifier of the list to sort
    /// @param[in]  ascending  Whether to sort from A to Z; false sorts from Z to A
    ///
    /// @return     (Void) replaces the card order in the matching board list
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       Each non-divider section is sorted in the requested direction; archive content
    ///             is unchanged
    ///
    func sortList(with listID: Int, ascending: Bool)
    {


        guard
        let listIndex = lists.firstIndex(where:
            {  /* Position of the list whose cards are being sorted */


                $0.id == listID
            })
        else
        {


            return
        }


        var updatedList = lists[listIndex] /* Mutable list copy */

        var sortedCards: [KanbanCard] = []     /* Cards emitted in sorted order */
        var currentSection: [KanbanCard] = []  /* Cards before the next divider */

        // Iterate through each card in the list, grouping them by sections and sorting within each section
        for card in updatedList.cards
        {  /* Preserve divider-separated sections */


            guard card.isSectionDivider else
            {


                currentSection.append(card)
                continue
            }


            // When encountering a section divider, sort the current section and append it to the sorted
            // cards before adding the divider itself
            sortedCards.append(
                contentsOf: currentSection.sorted
                {

                    let comparison = $0.word.localizedStandardCompare($1.word) /* Locale-aware title ordering */

                    return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                })
            currentSection.removeAll()
            sortedCards.append(card)
        }


        sortedCards.append(
            contentsOf: currentSection.sorted
            {


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
    /// @post       Completed non-divider cards leave the active list; section dividers stay in
    ///             place
    ///
    func archiveCompletedCards(in listID: Int)
    {


        guard
        let listIndex = lists.firstIndex(where:
            {  /* List containing completed cards to archive */


                $0.id == listID
            })
        else
        {


            return
        }


        lists[listIndex].archiveCompletedCards()
    }


    ///
    /// @fcn        ContentView.restoreArchivedCard(in:cardID:)
    /// @brief      Return a saved card to the end of its active list
    /// @details    Delegates to the model archive helper, preserving identity, completion, and
    ///             content
    ///
    /// @param[in]  listID  Active list containing the card archive
    /// @param[in]  cardID  Archived card identity to restore
    ///
    /// @return     (Void) transfers the archived record into active cards when found
    ///
    /// @post       Missing identities do nothing; no attachment files are pruned
    ///
    func restoreArchivedCard(in listID: Int, cardID: Int)
    {


        guard
        let listIndex = lists.firstIndex(where:
            {  /* Position of the list receiving the requested edit */


                $0.id == listID
            })
        else
        {


            return
        }

        lists[listIndex].restoreArchivedCard(id: cardID)
    }


    ///
    /// @fcn        ContentView.archiveCard(_:)
    /// @brief      Move one active task card into its containing list's archive
    /// @details    Finds the first containing active list and delegates record retention to the
    ///             model helper
    ///
    /// @param[in]  cardID  Board-unique active card identity
    ///
    /// @return     (Void) archives a matching non-divider card
    ///
    /// @post       Missing IDs and divider cards do nothing; card state and attachment references
    ///             survive
    ///
    func archiveCard(_ cardID: Int)
    {


        guard
        let listIndex = lists.firstIndex(where:
            {  /* Position of the list receiving the requested edit */


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
    func archiveList(with listID: Int)
    {


        guard
        let index = lists.firstIndex(where:
            {  /* Position of the active list to archive */


                $0.id == listID
            })
        else
        {


            return
        }


        var archived = lists[index] /* List snapshot marked archived before partition transfer */

        archived.isArchived = true
        archivedLists.append(archived)
        lists.removeAll
        {
            $0.id == listID
        }

    }


    ///
    /// @fcn        ContentView.restoreArchivedList(_:)
    /// @brief      Append an archived list to the active Board
    /// @details    Clears the list archive flag, appends its complete record, and removes its
    ///             archived entry
    ///
    /// @param[in]  listID  Archived list identity to restore
    ///
    /// @return     (Void) transfers a matching list between partitions
    ///
    /// @pre        Active/archive bindings are writable partitions of the same Board
    /// @post       Nested card archives and all identities survive; an absent ID leaves state
    ///             unchanged
    ///
    func restoreArchivedList(_ listID: Int)
    {


        guard
        let index = archivedLists.firstIndex(where:
            {  /* Position of the archived list to restore */


                $0.id == listID
            })
        else
        {


            return
        }


        var restored = archivedLists[index] /* List snapshot marked active before partition transfer */

        restored.isArchived = false
        lists.append(restored)
        archivedLists.removeAll
        {
            $0.id == listID
        }

    }


    ///
    /// @fcn        ContentView.toggleCardTitle(in:cardID:)
    /// @brief      Toggle the selected state for one board card title checkbox
    /// @details    Finds the matching card within the selected list and flips its persisted checked
    ///             state so the root board view and detail view stay in sync
    ///
    /// @param[in]  listIndex  Zero-based index of the list containing the card
    /// @param[in]  cardID     Stable identifier of the card whose title checkbox is toggled
    ///
    /// @return     (Void) updates the local board state in place
    ///
    /// @pre        listIndex must reference a valid list in the board state
    /// @post       The selected card's checked state is inverted and the board re-renders
    ///
    func toggleCardTitle(in listIndex: Int, cardID: Int)
    {


        guard lists.indices.contains(listIndex) else
        {


            return
        }


        var updatedList = lists[listIndex] /* Mutable list copy */

        guard
        let cardIndex = updatedList.cards.firstIndex(
            where:
            {  /* Position of the card receiving the requested edit */


                $0.id == cardID
            })
        else
        {


            return
        }


        guard !updatedList.cards[cardIndex].isEditingLocked else
        {
            return
        }

        var updatedCard = updatedList.cards[cardIndex] /* Mutable card copy */

        updatedCard.isTitleChecked.toggle()

        updatedList.cards[cardIndex] = updatedCard
        lists[listIndex] = updatedList
    }


    ///
    /// @fcn        ContentView.keyboardNavigation(for:)
    /// @brief      Build keyboard navigation actions for adjacent Cards
    /// @details    Resolves eligible neighbors in display order and re-resolves them when invoked
    ///             so navigation follows current content. Missing neighbors leave the corresponding
    ///             action unavailable.
    ///
    /// @param[in]  card  Canonical item whose resolved preview or navigation context is requested
    ///
    /// @return     (CardKeyboardNavigation) optional previous and next navigation actions
    ///
    func keyboardNavigation(for card: KanbanCard) -> CardKeyboardNavigation
    {

        let neighbors = CardKeyboardNeighbors.resolve(card, in: lists)
        return CardKeyboardNavigation(
            previous: neighbors.previous == nil
            ? nil
            :
            {

                guard let target = CardKeyboardNeighbors.resolve(card, in: lists).previous else
                {
                    return
                }

                var path = NavigationPath();
                path.append(target);
                navigationPath = path
            },
            next: neighbors.next == nil
            ? nil
            :
            {

                guard let target = CardKeyboardNeighbors.resolve(card, in: lists).next else
                {
                    return
                }

                var path = NavigationPath();
                path.append(target);
                navigationPath = path
            })
    }


    ///
    /// @fcn        ContentView.updateCard
    /// @brief      Replace the matching active card with its edited value
    /// @details    Searches lists by card identity, updates the first match, and prunes attachments after
    ///             replacement.
    ///
    /// @param[in]  updatedCard  Edited card value to publish at its existing identity
    ///
    /// @return     (Void) no return value
    ///
    func updateCard(_ updatedCard: KanbanCard)
    {


        for listIndex in lists.indices
        {


            var updatedList = lists[listIndex] /* Mutable list being searched */

            guard
            let cardIndex = updatedList.cards.firstIndex(
                where:
                {  /* Position of the card receiving the requested edit */


                    $0.id == updatedCard.id
                })
            else
            {  /* Matching card position */


                continue
            }


            guard updatedList.cards[cardIndex].acceptsContentUpdate(updatedCard) else
            {
                return
            }

            updatedList.cards[cardIndex] = updatedCard
            lists[listIndex] = updatedList

            pruneUnreferencedAttachments()

            return
        }

    }


    ///
    /// @fcn        ContentView.pruneUnreferencedAttachments()
    /// @brief      Remove stored photo files that are no longer assigned to any card
    /// @details    Collects filenames from active/archived lists and cards plus the caller's
    ///             retained snapshots, then asks the attachment store to remove files outside that
    ///             combined set
    ///
    /// @return     (Void) cleans unreferenced image files from the app's attachment directory
    ///
    /// @pre        lists reflects the current board state after a card or list mutation
    /// @post       Files referenced by cards remain available; unreferenced files are removed when
    ///             possible
    /// @note       File-system cleanup failures are ignored by CardAttachmentStore
    ///
    func pruneUnreferencedAttachments()
    {


        do
        {
            _ = try PlanningCalendarStore.load()
        }
        catch
        {

            DatabaseActivity.shared.report("Unused media was retained because calendar data could not be read.");
            return
        }

        let referencedFileNames = Set( /* Attachment files retained by current Board cards */
            (lists + archivedLists + retainedAttachmentLists() + (planningCalendarAccess?.allRetainedLists ?? []))
            .flatMap(\.allCards)
            .flatMap
            {
                $0.attachments ?? []
            }
            .flatMap(\.storedFileNames)
        )

        CardAttachmentStore.removeUnreferencedFiles(keeping: referencedFileNames)
    }


    ///
    /// @fcn        ContentView.moveCard(_:toListID:)
    /// @brief      Move an existing card into a different board list
    /// @details    Finds the card by its stable identifier, removes it from its current list,
    ///             updates its list title, and appends it to the destination list while retaining
    ///             its state
    ///
    /// @param[in]  cardID             Stable identifier of the card being moved
    /// @param[in]  destinationListID  Stable identifier of the list receiving the card
    ///
    /// @return     (Void) updates the source and destination lists in the board state
    ///
    /// @pre        cardID exists in a board list and destinationListID identifies another list
    /// @post       The card is removed from its source list and appears at the end of the
    ///             destination list with its existing card data preserved
    /// @note       The operation leaves board state unchanged if the card or destination is
    ///             missing, or if the destination is the card's current list
    ///
    func moveCard(_ cardID: Int, toListID destinationListID: Int)
    {


        guard
        !lists.contains(where:
            {


                $0.id == destinationListID && $0.cards.contains(where:
                    {
                        $0.id == cardID
                    })
            })
        else
        {


            return
        }


        do
        {


            try BoardCardMovement.move(cardID, to: destinationListID, in: &lists)
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not move this card: \(error.localizedDescription) Its content has been retained.")
        }

    }


    ///
    /// @fcn        ContentView.updateCardDrag(_:location:)
    /// @brief      Update the pointer location for the currently claimed card session
    /// @details    Ignores callbacks whose card identity does not match the active drag; hovering
    ///             does not modify Board records.
    ///
    /// @param[in]  cardID    Board-local identity of the card being dragged or moved
    /// @param[in]  location  Current or final pointer position in global Board geometry
    ///
    /// @return     (Void) updates only matching drag-location state
    ///
    func updateCardDrag(_ cardID: Int, location: CGPoint)
    {


        guard draggedCardID == cardID else
        {


            return
        }


        cardDragLocation = location
    }


    ///
    /// @fcn        ContentView.beginCardDrag(_:location:)
    /// @brief      Claim an idle Board for a native card drag
    /// @details    Records the card identity and starting location only when neither a list drag
    ///             nor another card drag is active.
    ///
    /// @param[in]  cardID    Board-local identity of the card being dragged or moved
    /// @param[in]  location  Current or final pointer position in global Board geometry
    ///
    /// @return     (Void) starts drag presentation without moving card records
    ///
    func beginCardDrag(_ cardID: Int, location: CGPoint)
    {


        guard draggedListID == nil, draggedCardID == nil, !boardPinch.active else
        {

            return
        }


        draggedCardID = cardID
        cardDragLocation = location
    }


    ///
    /// @fcn        ContentView.endCardDrag(_:commit:location:)
    /// @brief      Finish a matching card session and optionally commit its final drop
    /// @details    Validates the release point against measured Board geometry and moves the
    ///             canonical card. Clears matching session state on exit; movement errors retain
    ///             content and reach the database-activity banner.
    ///
    /// @param[in]  cardID    Board-local identity of the card being dragged or moved
    /// @param[in]  commit    Whether to attempt movement after validating the destination
    /// @param[in]  location  Current or final pointer position in global Board geometry
    ///
    /// @return     (Bool) whether canonical card movement changed the Board
    ///
    /// @post       Matching drag state is cleared even when validation fails or movement reports an
    ///             error
    ///
    @discardableResult
    func endCardDrag(_ cardID: Int, commit: Bool, location: CGPoint? = nil) -> Bool
    {


        guard draggedCardID == cardID else
        {


            return false
        }


        if let location
        {  /* Final pointer sample supplied by the native drag session */


            cardDragLocation = location
        }


        defer
        {


            draggedCardID = nil
            cardDragLocation = nil
        }


        guard commit,
        let target = location.map(
            {  /* Validated destination for the committed card drop */


                BoardCardMovement.target(
                    for: cardID, at: $0, viewport: dragGeometry.viewport,
                    lists: lists, listFrames: dragGeometry.lists, cardFrames: dragGeometry.cards)
            }) ?? cardDropTarget
        else
        {
            return false
        }

        do
        {


            return try BoardCardMovement.move(cardID, to: target.listID, before: target.beforeCardID, in: &lists)
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not move this card: \(error.localizedDescription) Its content has been retained.")

            return false
        }

    }

}
