// --------------------------------------------------------------------------------------------------
// @file       ListMovement.swift
// @brief      Canonical whole-List copy and transfer transforms
// @details    Reserves active and archived identities and remaps internal links before publishing
//             source and destination owners.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Copies a List into a destination owner
///
/// @section    Purpose
///     Allocates fresh local identities and remaps internal Card links while preserving retained
///     content.
///
enum ListCopying
{


    ///
    /// @fcn        ListCopying.copy
    /// @brief      Copy a list with destination-safe identities
    /// @details    Allocates new list and card IDs against the destination and updates checklist references according
    ///             to whether the copy crosses owners.
    ///
    /// @param[in]  source       Original list whose content is being copied
    /// @param[in]  destination  Existing destination lists used when allocating collision-free identities
    /// @param[in]  crossBoard   Whether the copy crosses owners and requires cross-owner reference rules
    ///
    /// @return     (KanbanList) copied list with new destination-safe list and card identities
    ///
    static func copy(_ source: KanbanList, into destination: [KanbanList], crossBoard: Bool) -> KanbanList
    {

        let listID = (destination.map(\.id).max() ?? -1) + 1
        let firstCardID = (destination.flatMap
            {
                $0.allCards.map(\.id)
            } .max() ?? -1) + 1
        let ids = Dictionary(
            uniqueKeysWithValues: source.allCards.enumerated().map
            {
                ($0.element.id, firstCardID + $0.offset)
            })
        let title = source.title + " Copy"


        ///
        /// @fcn        ListCopying.copy.copyCard
        /// @brief      Copy one card using the enclosing identity map
        /// @details    Rewrites checklist references consistently with the copied list's destination and cross-board
        ///             policy.
        ///
        /// @param[in]  card  Card or note being inspected or changed
        ///
        /// @return     (KanbanCard) copied card with rewritten checklist references
        ///
        func copyCard(_ card: KanbanCard) -> KanbanCard
        {

            var copy = card.replacingLocation(id: ids[card.id]!, listTitle: title)
            copy.checklists = card.checklists.map
            {
                checklist in
                let items = checklist.items.map
                {
                    item in
                    var item = item
                    if let id = item.retainedCardID, let copiedID = ids[id]
                    {

                        item.retainedCardID = copiedID
                        item.linkedCollectionID = nil
                    }

                    if case .linkedCard(let id) = item.content
                    {

                        if let copiedID = ids[id]
                        {

                            item.content = .linkedCard(cardID: copiedID)
                        }
                        else if crossBoard
                        {

                            item.content = .standard
                        }

                    }

                    return item
                }

                return KanbanChecklist(
                    id: checklist.id, title: checklist.title, items: items,
                    completedItemIndices: checklist.completedItemIndices)
            }

            return copy
        }

        var result = KanbanList(
            id: listID, title: title, cards: source.cards.map(copyCard),
            archivedCards: source.archivedCards.map(copyCard), newItemPresentation: source.newItemPresentation)
        result.subtitleOverride = source.subtitleOverride
        result.appearance = source.appearance
        return result
    }

}


///
/// Moves a whole List between distinct Board owners
///
/// @section    Purpose
///     Reserves active and archived identities and builds source and destination snapshots before
///     checked publication.
///
enum CrossBoardListMovement
{


    ///
    /// @fcn        CrossBoardListMovement.detach
    /// @brief      Detach one board list into a standalone collection
    /// @details    Validates its owner, preserves the moved content, and redirects affected references as the
    ///             ownership changes.
    ///
    /// @param[in]      listID       Numeric list identity within its owner
    /// @param[in]      sourceID     Identity of the source owner
    /// @param[in,out]  collections  Personal collection values available to the operation
    ///
    /// @return     (PersonalCollection) new standalone collection containing the detached list
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`. Errors from throwing
    ///             dependencies propagate unless handled within this operation.
    ///
    static func detach(
        listID: Int, from sourceID: UUID,
        collections: inout [PersonalCollection]
    ) throws -> PersonalCollection
    {

        guard let source = collections.first(where:
            {
                $0.id == sourceID && $0.isActive && $0.kind == .board
            }),
        let list = source.lists.first(where:
            {
                $0.id == listID && !$0.isArchived
            })
        else
        {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var snapshot = collections
        var destination = PersonalCollection(
            title: list.title, kind: .board,
            icon: list.newItemPresentation == .note ? .notes : .tasks, color: source.color)
        destination.lists = []
        snapshot.append(destination)
        let moved = try move(listID: listID, from: sourceID, to: destination.id, collections: &snapshot)
        let targetIndex = snapshot.count - 1
        var standalone = PersonalCollection(
            id: destination.id, title: moved.title, kind: .list,
            icon: destination.icon, color: destination.color)
        standalone.lists = [moved]
        standalone.savedCardIDs = snapshot[targetIndex].savedCardIDs
        standalone.boardAppearance = source.boardAppearance
        standalone.collectionDescription = moved.subtitleOverride
        snapshot[targetIndex] = standalone
        collections = snapshot
        return standalone
    }


    ///
    /// @fcn        CrossBoardListMovement.move
    /// @brief      Transfer an entire list between existing owners
    /// @details    Uses destination-safe IDs and rewrites affected checklist links and saved-card ownership while
    ///             retaining the list's content.
    ///
    /// @param[in]      listID         Numeric list identity within its owner
    /// @param[in]      sourceID       Identity of the source owner
    /// @param[in]      destinationID  UUID of the existing destination collection owner
    /// @param[in,out]  collections    Personal collection values available to the operation
    ///
    /// @return     (KanbanList) list at its new owner with remapped identities and links
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`,
    ///             `CocoaError(.validationNumberTooLarge)`. Errors from throwing dependencies propagate unless
    ///             handled within this operation.
    ///
    static func move(
        listID: Int, from sourceID: UUID, to destinationID: UUID,
        collections: inout [PersonalCollection]
    ) throws -> KanbanList
    {

        guard sourceID != destinationID,
        let sourceIndex = collections.firstIndex(where:
            {
                $0.id == sourceID && $0.isActive && $0.kind == .board
            }),
        let destinationIndex = collections.firstIndex(where:
            {

                $0.id == destinationID && $0.isActive && $0.kind == .board
            }),
        let listIndex = collections[sourceIndex].lists.firstIndex(where:
            {
                $0.id == listID && !$0.isArchived
            })
        else
        {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var snapshot = collections
        let source = snapshot[sourceIndex].lists[listIndex]
        let destinationLists = snapshot[destinationIndex].lists
        let targetIDs = Set(destinationLists.flatMap(\.allCards).map(\.id))
        let sourceIDs = Set(source.allCards.map(\.id))
        guard sourceIDs.count == source.allCards.count else
        {
            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var nextID = max(targetIDs.max() ?? -1, sourceIDs.max() ?? -1)
        var mapping: [Int: Int] = [:]
        for card in source.allCards
        {

            if targetIDs.contains(card.id)
            {

                let (next, overflow) = nextID.addingReportingOverflow(1)
                guard !overflow else
                {
                    throw CocoaError(.validationNumberTooLarge)
                }

                nextID = next;
                mapping[card.id] = next
            }
            else
            {

                mapping[card.id] = card.id
            }

        }

        var moved = source
        if destinationLists.contains(where:
            {
                $0.id == source.id
            })
        {

            let (next, overflow) = (destinationLists.map(\.id).max() ?? -1).addingReportingOverflow(1)
            guard !overflow else
            {
                throw CocoaError(.validationNumberTooLarge)
            }

            moved = KanbanList(
                id: next, title: source.title, cards: source.cards,
                archivedCards: source.archivedCards, newItemPresentation: source.newItemPresentation)
            moved.subtitleOverride = source.subtitleOverride
            moved.appearance = source.appearance
            moved.isArchived = source.isArchived
        }


        ///
        /// @fcn        CrossBoardListMovement.move.relocate
        /// @brief      Rewrite a moved card for its destination owner
        /// @details    Uses the enclosing list and card identity maps so internal checklist links follow the
        ///             transferred content.
        ///
        /// @param[in]  card  Card or note being inspected or changed
        ///
        /// @return     (KanbanCard) relocated card with checklist links mapped to destination identities
        ///
        func relocate(_ card: KanbanCard) -> KanbanCard
        {

            var result = card.replacingLocation(id: mapping[card.id]!, listTitle: source.title)
            result.checklists = result.checklists.map
            {
                checklist in
                let items = checklist.items.map
                {
                    item in
                    var item = item
                    // Implicit references originally belonged to the source board, including hidden links.
                    if item.retainedCardID != nil
                    ||
                    {

                        if case .linkedCard = item.content
                        {
                            return true
                        }
                        ;
                        return false
                    }()
                    {

                        item.linkedCollectionID = item.linkedCollectionID ?? sourceID
                    }

                    return item
                }

                return KanbanChecklist(
                    id: checklist.id, title: checklist.title, items: items,
                    completedItemIndices: checklist.completedItemIndices)
            }

            return result
        }

        moved.cards = source.cards.map(relocate)
        moved.archivedCards = source.archivedCards.map(relocate)
        snapshot[sourceIndex].lists.remove(at: listIndex)
        snapshot[destinationIndex].lists.append(moved)
        for id in sourceIDs where snapshot[sourceIndex].savedCardIDs.remove(id) != nil
        {

            snapshot[destinationIndex].savedCardIDs.insert(mapping[id]!)
        }

        // Redirect references from every retained board to each moved card's new owner and identity.
        for boardIndex in snapshot.indices
        {

            let owner = snapshot[boardIndex].id


            ///
            /// @fcn        CrossBoardListMovement.move.redirect
            /// @brief      Redirect links that point to the transferred list
            /// @details    Traverses card checklist content using the enclosing source and destination identity
            ///             mapping.
            ///
            /// @param[in]  card  Card or note being inspected or changed
            ///
            /// @return     (KanbanCard) card whose inbound links follow the transferred list
            ///
            func redirect(_ card: KanbanCard) -> KanbanCard
            {

                var card = card
                card.checklists = card.checklists.map
                {
                    checklist in
                    let items = checklist.items.map
                    {
                        item in
                        var item = item
                        guard (item.linkedCollectionID ?? owner) == sourceID else
                        {
                            return item
                        }

                        if let id = item.retainedCardID, let next = mapping[id]
                        {

                            item.retainedCardID = next
                            item.linkedCollectionID = destinationID
                        }

                        if case .linkedCard(let id) = item.content, let next = mapping[id]
                        {

                            item.content = .linkedCard(cardID: next)
                            item.linkedCollectionID = destinationID
                        }

                        return item
                    }

                    return KanbanChecklist(
                        id: checklist.id, title: checklist.title, items: items,
                        completedItemIndices: checklist.completedItemIndices)
                }

                return card
            }

            for index in snapshot[boardIndex].lists.indices
            {

                snapshot[boardIndex].lists[index].cards = snapshot[boardIndex].lists[index].cards.map(redirect)
                snapshot[boardIndex].lists[index].archivedCards = snapshot[boardIndex].lists[index].archivedCards.map(
                    redirect)
            }

        }

        collections = snapshot
        return snapshot[destinationIndex].lists.last!
    }

}
