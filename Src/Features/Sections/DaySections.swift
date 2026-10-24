// --------------------------------------------------------------------------------------------------
// @file       DaySections.swift
// @brief      Named section membership and ordering policy
// @details    Derives boundaries, collapsed visibility, and whole-section movement while
//             preserving original item identities.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Resolves named section membership and operations
///
/// @section    Purpose
///     Treats a named divider as owner of subsequent items until the next named divider while
///     retaining identities through collapse and reordering.
///
enum DaySections
{


    ///
    /// @fcn        DaySections.owner
    /// @brief      Find the named heading that owns a card
    /// @details    Scans canonical order until the next named heading; cards before the first heading have no section
    ///             owner.
    ///
    /// @param[in]  id     Starting numeric card ID or owner-local content identity
    /// @param[in]  cards  Canonical card values in their current order
    ///
    /// @return     (KanbanCard?) preceding named divider owning the target card, or nil for ungrouped or missing
    ///             content
    ///
    static func owner(of id: Int, in cards: [KanbanCard]) -> KanbanCard?
    {

        var heading: KanbanCard?
        for card in cards
        {

            if card.sectionHeading != nil
            {
                heading = card
            }

            if card.id == id
            {
                return heading
            }

        }

        return nil
    }


    ///
    /// @fcn        DaySections.visible
    /// @brief      Project canonical cards into the expanded section rows
    /// @details    Retains headings and ungrouped content while omitting members of collapsed sections; stored cards
    ///             remain untouched.
    ///
    /// @param[in]  cards  Canonical card values in their current order
    ///
    /// @return     ([KanbanCard]) canonical-order headings and members of expanded sections
    ///
    static func visible(_ cards: [KanbanCard]) -> [KanbanCard]
    {

        var collapsed = false
        return cards.filter
        {
            card in
            if card.sectionHeading != nil
            {

                collapsed = card.appearance?.sectionCollapsed == true
                return true
            }

            return !collapsed
        }

    }


    ///
    /// @fcn        DaySections.reveal
    /// @brief      Expand the section containing a particular card
    /// @details    Finds its named heading and clears the collapsed appearance flag without changing card order.
    ///
    /// @param[in]      id     Starting numeric card ID or owner-local content identity
    /// @param[in,out]  cards  Canonical card values in their current order
    ///
    /// @return     (Void) no return value
    ///
    static func reveal(_ id: Int, in cards: inout [KanbanCard])
    {

        guard let heading = owner(of: id, in: cards),
        let index = cards.firstIndex(where:
            {
                $0.id == heading.id
            }),
        cards[index].appearance?.sectionCollapsed == true
        else
        {
            return
        }

        cards[index].appearance?.sectionCollapsed = false
    }


    ///
    /// @fcn        DaySections.visibleMove
    /// @brief      Translate a visible native-list move into canonical indices
    /// @details    Maps visible source and destination positions back to full card order so collapsed members are not
    ///             lost or misindexed.
    ///
    /// @param[in]  cards              Canonical card values in their current order
    /// @param[in]  sourceOffsets      Indices in the visible native-list projection being moved
    /// @param[in]  destinationOffset  Insertion offset in the visible native-list projection
    ///
    /// @return     ((id: Int, index: Int)?) canonical source identity and insertion index, or nil for an invalid
    ///             visible move
    ///
    /// @note       Translate native List offsets through the visible projection, keeping hidden members in storage.
    ///
    static func visibleMove(_ cards: [KanbanCard], sourceOffsets: IndexSet, destinationOffset: Int) -> (
        id: Int, index: Int
    )?
    {

        let rows = visible(cards)
        guard let source = sourceOffsets.first, rows.indices.contains(source),
        (0 ... rows.count).contains(destinationOffset),
        let canonicalSource = cards.firstIndex(where:
            {
                $0.id == rows[source].id
            })
        else
        {
            return nil
        }

        let boundary: Int
        if destinationOffset == rows.count
        {

            boundary = cards.count
        }
        else
        {

            boundary = cards.firstIndex(where:
                {
                    $0.id == rows[destinationOffset].id
                }) ?? cards.count
        }

        return (rows[source].id, canonicalSource < boundary ? boundary - 1 : boundary)
    }


    ///
    /// @fcn        DaySections.reordered
    /// @brief      Reorder a card or named section in canonical card order
    /// @details    Moves a heading with its complete section block and delegates ordinary-card movement while
    ///             preserving the ungrouped prefix.
    ///
    /// @param[in]  cards        Canonical card values in their current order
    /// @param[in]  itemID       Canonical card or divider identity to reorder
    /// @param[in]  destination  Canonical insertion index or direction-resolved destination index
    ///
    /// @return     ([KanbanCard]) canonical cards after a valid card or whole-section move, or the unchanged input
    ///
    static func reordered(_ cards: [KanbanCard], itemID: Int, to destination: Int) -> [KanbanCard]
    {

        guard let source = cards.firstIndex(where:
            {
                $0.id == itemID
            }) else
        {
            return cards
        }

        guard cards[source].sectionHeading != nil else
        {

            var result = cards
            BoardCardReordering.move(itemID, to: destination, in: &result)
            return result
        }

        let starts = cards.indices.filter
        {
            cards[$0].sectionHeading != nil
        }

        guard let position = starts.firstIndex(of: source) else
        {
            return cards
        }

        let target = starts.lastIndex(where:
            {
                $0 <= min(max(0, destination), cards.count - 1)
            }) ?? 0
        var result = cards
        for _ in 0 ..< abs(target - position)
        {

            result = moved(result, sectionID: itemID, offset: target > position ? 1 : -1)
        }

        return result
    }


    ///
    /// @fcn        DaySections.moved
    /// @brief      Move a named section relative to neighboring sections
    /// @details    Treats the heading and all following members up to the next named heading as one block and leaves
    ///             invalid requests unchanged.
    ///
    /// @param[in]  cards      Canonical card values in their current order
    /// @param[in]  sectionID  Named divider identity whose complete section should move
    /// @param[in]  offset     Relative section or photo movement, or normalized scroll displacement
    ///
    /// @return     ([KanbanCard]) canonical cards with the requested neighboring-section move, or the unchanged input
    ///
    static func moved(_ cards: [KanbanCard], sectionID: Int, offset: Int) -> [KanbanCard]
    {

        let starts = cards.indices.filter
        {
            cards[$0].sectionHeading != nil
        }

        guard offset == -1 || offset == 1,
        let position = starts.firstIndex(where:
            {
                cards[$0].id == sectionID
            }),
        starts.indices.contains(position + offset)
        else
        {
            return cards
        }

        let start = starts[position]
        let end = position + 1 < starts.count ? starts[position + 1] : cards.count
        let target =
        offset < 0 ? starts[position - 1] : (position + 2 < starts.count ? starts[position + 2] : cards.count)
        var result = cards
        let block = Array(cards[start ..< end])
        result.removeSubrange(start ..< end)
        result.insert(contentsOf: block, at: target > start ? target - block.count : target)
        return result
    }

}
