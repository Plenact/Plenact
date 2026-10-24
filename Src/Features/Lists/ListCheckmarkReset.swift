// --------------------------------------------------------------------------------------------------
// @file       ListCheckmarkReset.swift
// @brief      Temporary completion-only restoration snapshots
// @details    Clears and restores captured checklist state without replacing current writing or
//             unrelated metadata.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Retains temporary Undo state for List checkmarks
///
/// @section    Purpose
///     Restores only captured completion values and never replaces current writing or unrelated
///     Card content.
///
struct ListCheckmarkReset: Equatable
{


    let previous: [String: Bool]
    let cleared:  [String: Bool]


    ///
    /// @fcn        ListCheckmarkReset.values
    /// @brief      Capture completion state throughout a list
    /// @details    Uses stable nested identity paths so card and checklist checkmarks can be compared and restored
    ///             separately from other metadata.
    ///
    /// @param[in]  list  List supplying the current content and metadata
    ///
    /// @return     ([String: Bool]) completion values keyed by stable card and nested checklist identity paths
    ///
    static func values(in list: KanbanList) -> [String: Bool]
    {

        var values: [String: Bool] = [:]
        _ = transform(list.cards)
        {
            key, value in
            values[key] = value;
            return value
        }

        return values
    }


    ///
    /// @fcn        ListCheckmarkReset.reset
    /// @brief      Create a cleared copy and restoration snapshot
    /// @details    Records original and cleared completion values and returns transformed cards without mutating the
    ///             supplied list.
    ///
    /// @param[in]  list  List supplying the current content and metadata
    ///
    /// @return     ((ListCheckmarkReset, [KanbanCard])) restoration snapshot paired with copies of the cleared cards
    ///
    static func reset(_ list: KanbanList) -> (ListCheckmarkReset, [KanbanCard])
    {

        let previous = values(in: list)
        let cards = transform(list.cards)
        {
            _, _ in
            false
        }

        var cleared = list;
        cleared.cards = cards
        return (Self(previous: previous, cleared: values(in: cleared)), cards)
    }


    ///
    /// @fcn        ListCheckmarkReset.canRestore
    /// @brief      Check whether the captured checkmarks can still be restored
    /// @details    Requires the current list's completion values to match the cleared snapshot, preventing an Undo
    ///             from overwriting later checkmark edits.
    ///
    /// @param[in]  list  List supplying the current content and metadata
    ///
    /// @return     (Bool) true only when current checkmarks still match the captured cleared state
    ///
    func canRestore(_ list: KanbanList) -> Bool
    {
        Self.values(in: list) == cleared
    }


    ///
    /// @fcn        ListCheckmarkReset.restoring
    /// @brief      Restore captured checkmarks when the snapshot is still valid
    /// @details    Returns nil after a conflicting completion change; otherwise restores only completion fields while
    ///             keeping current card content.
    ///
    /// @param[in]  list  List supplying the current content and metadata
    ///
    /// @return     ([KanbanCard]?) restored completion values, or nil if later checkmark edits conflict
    ///
    func restoring(_ list: KanbanList) -> [KanbanCard]?
    {

        guard canRestore(list) else
        {
            return nil
        }

        return Self.transform(list.cards)
        {
            key, value in
            previous[key] ?? value
        }

    }


    ///
    /// @fcn        ListCheckmarkReset.transform
    /// @brief      Transform completion values recursively by identity path
    /// @details    Copies the supplied hierarchy and invokes the change closure for each card or nested checklist
    ///             path.
    ///
    /// @param[in]  cards   Canonical card values in their current order
    /// @param[in]  change  Transform receiving the stable identity path and current completion value
    ///
    /// @return     ([KanbanCard]) hierarchy copies with completion fields transformed by stable identity path
    ///
    private static func transform(_ cards: [KanbanCard], change: (String, Bool) -> Bool) -> [KanbanCard]
    {

        cards.map
        {
            original in
            guard !original.isSectionDivider, !original.isEditingLocked else
            {
                return original
            }

            var card = original
            let key = "card/\(card.id)/\(card.createdAt?.timeIntervalSince1970 ?? 0)"
            card.isTitleChecked = change(key, card.isTitleChecked)
            card.checklists = transform(card.checklists, path: key, change: change)
            return card
        }

    }


    ///
    /// @fcn        ListCheckmarkReset.transform
    /// @brief      Transform completion values recursively by identity path
    /// @details    Copies the supplied hierarchy and invokes the change closure for each card or nested checklist
    ///             path.
    ///
    /// @param[in]  lists   Lists participating in the operation
    /// @param[in]  path    Stable hierarchy path or writable field key path used by the operation
    /// @param[in]  change  Transform receiving the stable identity path and current completion value
    ///
    /// @return     ([KanbanChecklist]) hierarchy copies with completion fields transformed by stable identity path
    ///
    private static func transform(_ lists: [KanbanChecklist], path: String, change: (String, Bool) -> Bool)
    -> [KanbanChecklist]
    {

        lists.map
        {
            checklist in
            KanbanChecklist(
                id: checklist.id, title: checklist.title,
                items: checklist.items.map
                {
                    original in
                    var item = original
                    let key = path + "/\(checklist.id)/\(item.id)"
                    item.isCompleted = change(key, item.isCompleted)
                    if case .actionDetail(var detail) = item.content
                    {

                        detail.checklists = transform(detail.checklists, path: key, change: change)
                        item.content = .actionDetail(detail)
                    }
                    else if var detail = item.retainedDetail
                    {

                        detail.checklists = transform(detail.checklists, path: key + "/retained", change: change)
                        item.retainedDetail = detail
                    }

                    return item
                })
        }

    }

}
