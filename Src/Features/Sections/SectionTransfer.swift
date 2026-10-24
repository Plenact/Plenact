// --------------------------------------------------------------------------------------------------
// @file       SectionTransfer.swift
// @brief      Checked whole-section transfer and guarded Undo
// @details    Builds both owner snapshots, remaps identities and links, optionally shifts dates,
//             and retains restoration receipts before publication.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Retains one guarded section-transfer Undo receipt
///
/// @section    Purpose
///     Restores affected owners only while their current snapshots still match the completed move,
///     including full importance levels where retained.
///
struct SectionTransferReceipt
{


    let before:      [PersonalCollection]
    let after:       [PersonalCollection]
    let source:      WorkspaceListReference
    let destination: WorkspaceListReference
    let mapping:     [Int: Int]
    let heading:     KanbanCard


    ///
    /// @fcn        SectionTransferReceipt.undo
    /// @brief      Restore affected owners if the transfer snapshot still matches
    /// @details    Compares current affected owners with the recorded post-transfer values, restores only those
    ///             owners, and throws on conflicts instead of overwriting later edits.
    ///
    /// @param[in]  owners  Canonical collection owners participating in the operation
    ///
    /// @return     ([PersonalCollection]) owners with only the transferred changes restored
    /// @throws     Explicit failures include `CocoaError(.fileWriteFileExists)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    func undo(in owners: [PersonalCollection]) throws -> [PersonalCollection]
    {

        guard after.allSatisfy(
            {
                expected in
                owners.first(where:
                    {
                        $0.id == expected.id
                    }) == expected
            }) else
        {

            throw CocoaError(.fileWriteFileExists)
        }

        return owners.map
        {
            owner in
            before.first(where:
                {
                    $0.id == owner.id
                }) ?? owner
        }

    }

}


///
/// Transfers a complete named section between owners
///
/// @section    Purpose
///     Validates boundaries and destinations, remaps identities and links, optionally shifts dates,
///     and creates a guarded Undo receipt before publishing owner snapshots.
///
enum SectionTransfer
{


    ///
    /// @fcn        SectionTransfer.move
    /// @brief      Transfer a complete named section between active lists
    /// @details    Validates both owners and the heading, remaps cross-owner IDs and nested links, optionally shifts
    ///             calendar dates, and publishes the working owners only after constructing a valid transfer receipt.
    ///
    /// @param[in]      heading         Named divider identifying the complete section to transfer
    /// @param[in]      source          Owner-qualified source list reference
    /// @param[in]      destination     Owner-qualified destination list reference
    /// @param[in,out]  owners          Canonical collection owners participating in the operation
    /// @param[in]      sourceDay       Original represented day, when known, for optional schedule shifting
    /// @param[in]      destinationDay  Destination represented day, when applicable
    /// @param[in]      shiftDates      Whether date-bearing schedules should shift with the moved section
    /// @param[in]      calendar        Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (SectionTransferReceipt) checked before/after snapshots and the transferred identity map
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`,
    ///             `CocoaError(.fileReadCorruptFile)`, `CocoaError(.validationNumberTooLarge)`. Errors from throwing
    ///             dependencies propagate unless handled within this operation.
    ///
    static func move(
        heading: KanbanCard, source: WorkspaceListReference, destination: WorkspaceListReference,
        owners: inout [PersonalCollection], sourceDay: Date? = nil, destinationDay: Date? = nil,
        shiftDates: Bool = false, calendar: Calendar = .current
    ) throws -> SectionTransferReceipt
    {

        guard source != destination,
        let from = owners.firstIndex(where:
            {
                $0.id == source.ownerID && $0.isActive
            }),
        let to = owners.firstIndex(where:
            {
                $0.id == destination.ownerID && $0.isActive
            }),
        let fromList = owners[from].lists.firstIndex(where:
            {
                $0.id == source.listID && !$0.isArchived
            }),
        let toList = owners[to].lists.firstIndex(where:
            {
                $0.id == destination.listID && !$0.isArchived
            }),
        let start = owners[from].lists[fromList].cards.firstIndex(where:
            {

                $0.id == heading.id && $0.createdAt == heading.createdAt
            }),
        owners[from].lists[fromList].cards[start].sectionHeading != nil
        else
        {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        let original = owners
        let sourceCards = owners[from].lists[fromList].cards
        let end =
        sourceCards.indices.dropFirst(start + 1).first
        {
            sourceCards[$0].sectionHeading != nil
        }

        ?? sourceCards.count
        let block = Array(sourceCards[start ..< end])
        let ids = Set(block.map(\.id))
        guard ids.count == block.count else
        {
            throw CocoaError(.fileReadCorruptFile)
        }

        let sameOwner = source.ownerID == destination.ownerID
        let reserved = Set(owners[to].lists.flatMap(\.allCards).map(\.id))
        var next = max(reserved.max() ?? -1, ids.max() ?? -1)
        var mapping: [Int: Int] = [:]
        for card in block
        {

            if !sameOwner && reserved.contains(card.id)
            {

                let (value, overflow) = next.addingReportingOverflow(1)
                guard !overflow else
                {
                    throw CocoaError(.validationNumberTooLarge)
                }

                next = value;
                mapping[card.id] = next
            }
            else
            {

                mapping[card.id] = card.id
            }

        }

        let dated = block.flatMap
        {
            card -> [Date] in
            [card.startDateKind == .time ? nil : card.startDate, card.dueDateKind == .time ? nil : card.dueDate]
            .compactMap
            {
                $0
            }

        }

        let anchor = sourceDay ?? dated.min()
        let delta: Int
        if shiftDates, let destinationDay, let anchor
        {

            delta =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: destinationDay)
            ).day ?? 0
        }
        else
        {

            delta = 0
        }

        // Freeze implicit links before moving their owner, including nested and retained links.


        ///
        /// @fcn        SectionTransfer.move.checklist
        /// @brief      Rewrite checklist links and retained content during a section move
        /// @details    Remaps links into the moved block, qualifies other source links when needed, and recursively
        ///             preserves inactive retained detail.
        ///
        /// @param[in]  sourceChecklist  Checklist whose active and retained links are being rewritten
        /// @param[in]  owner            Owner identity used to qualify numeric item references
        /// @param[in]  freeze           Whether implicit source-owner links must become explicitly qualified
        ///
        /// @return     (KanbanChecklist) checklist with active and retained links rewritten using the transfer maps
        ///
        func checklist(_ sourceChecklist: KanbanChecklist, owner: UUID, freeze: Bool) -> KanbanChecklist
        {

            let items = sourceChecklist.items.map
            {
                original -> KanbanChecklistItem in
                var item = original
                if case .actionDetail(var detail) = item.content
                {

                    detail.checklists = detail.checklists.map
                    {
                        checklist($0, owner: owner, freeze: freeze)
                    }

                    item.content = .actionDetail(detail)
                }
                else if var detail = item.retainedDetail
                {

                    detail.checklists = detail.checklists.map
                    {
                        checklist($0, owner: owner, freeze: freeze)
                    }

                    item.retainedDetail = detail
                }

                let linked: Bool =
                {

                    if case .linkedCard = item.content
                    {
                        return true
                    }
                    ;
                    return item.retainedCardID != nil
                }()
                if freeze && linked && item.linkedCollectionID == nil
                {
                    item.linkedCollectionID = source.ownerID
                }

                if (item.linkedCollectionID ?? owner) == source.ownerID
                {

                    if let id = item.retainedCardID, let newID = mapping[id]
                    {

                        item.retainedCardID = newID;
                        item.linkedCollectionID = destination.ownerID
                    }

                    if case .linkedCard(let id) = item.content, let newID = mapping[id]
                    {

                        item.content = .linkedCard(cardID: newID);
                        item.linkedCollectionID = destination.ownerID
                    }

                }

                return item
            }

            return KanbanChecklist(
                id: sourceChecklist.id, title: sourceChecklist.title, items: items,
                completedItemIndices: sourceChecklist.completedItemIndices)
        }

        var snapshot = owners
        let moved = block.map
        {
            card -> KanbanCard in
            var result = card.replacingLocation(id: mapping[card.id]!, listTitle: snapshot[to].lists[toList].title)
            if delta != 0
            {

                if let value = result.startDate, result.startDateKind != .time
                {

                    result.startDate = calendar.date(byAdding: .day, value: delta, to: value)
                }

                if let value = result.dueDate, result.dueDateKind != .time
                {

                    result.dueDate = calendar.date(byAdding: .day, value: delta, to: value)
                }

            }

            result.checklists = result.checklists.map
            {
                checklist($0, owner: source.ownerID, freeze: !sameOwner)
            }

            return result
        }

        snapshot[from].lists[fromList].cards.removeSubrange(start ..< end)
        snapshot[to].lists[toList].cards.append(contentsOf: moved)
        if !sameOwner
        {

            for id in ids where snapshot[from].savedCardIDs.remove(id) != nil
            {

                snapshot[to].savedCardIDs.insert(mapping[id]!)
            }

            for index in snapshot.indices
            {

                let owner = snapshot[index].id


                ///
                /// @fcn        SectionTransfer.move.redirect
                /// @brief      Redirect inbound links to the moved section's new owner
                /// @details    Applies the enclosing identity map across checklist content while avoiding a second
                ///             rewrite of cards already relocated.
                ///
                /// @param[in]  card  Card or note being inspected or changed
                ///
                /// @return     (KanbanCard) card with inbound links redirected to the transferred section's owner
                ///
                func redirect(_ card: KanbanCard) -> KanbanCard
                {

                    var result = card
                    // Moved cards were already redirected; do not apply an ID mapping twice.
                    if owner == destination.ownerID && moved.contains(where:
                        {
                            $0.id == card.id
                        })
                    {
                        return result
                    }

                    result.checklists = result.checklists.map
                    {
                        checklist($0, owner: owner, freeze: false)
                    }

                    return result
                }

                for listIndex in snapshot[index].lists.indices
                {

                    snapshot[index].lists[listIndex].cards = snapshot[index].lists[listIndex].cards.map(redirect)
                    snapshot[index].lists[listIndex].archivedCards = snapshot[index].lists[listIndex].archivedCards.map(
                        redirect)
                }

            }

        }

        let changed = Set(snapshot.indices.filter
            {
                snapshot[$0] != original[$0]
            } .map
            {
                snapshot[$0].id
            })
        let receipt = SectionTransferReceipt(
            before: original.filter
            {
                changed.contains($0.id)
            }, after: snapshot.filter
            {
                changed.contains($0.id)
            },
            source: source, destination: destination, mapping: mapping, heading: moved[0])
        owners = snapshot
        return receipt
    }

}
