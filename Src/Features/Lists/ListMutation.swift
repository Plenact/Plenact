// --------------------------------------------------------------------------------------------------
// @file       ListMutation.swift
// @brief      Validated canonical List metadata updates
// @details    Rejects ambiguous or unavailable destinations and preserves current records while
//             applying accepted display edits.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


// -------------------------------------- MARK: - Kanban Card ----------------------------------- //


///
/// @fcn        setListAppearance
/// @brief      Apply appearance to one unambiguous active list
/// @details    Rejects missing, duplicated, or archived matches with activity feedback; stores nil for an empty
///             appearance.
///
/// @param[in]      listID      Numeric list identity within its owner
/// @param[in]      appearance  Optional or explicit appearance overrides supplied by the caller
/// @param[in,out]  lists       Lists participating in the operation
///
/// @return     (Bool) true for a uniquely identified active list update; false when the target is invalid
///
@MainActor
@discardableResult
func setListAppearance(_ listID: Int, appearance: ItemAppearance?, in lists: inout [KanbanList]) -> Bool
{

    guard lists.filter(
        {
            $0.id == listID && !$0.isArchived
        }).count == 1,
    let index = lists.firstIndex(where:
        {
            $0.id == listID && !$0.isArchived
        })
    else
    {

        DatabaseActivity.shared.report("Could not change this List's appearance. Its content has been retained.")
        return false
    }

    lists[index].appearance = appearance?.isEmpty == true ? nil : appearance
    return true
}


///
/// @fcn        editBoardList
/// @brief      Validate and apply list title and subtitle edits
/// @details    Requires one active matching list, preserves an unchanged subtitle override, and reports validation
///             failures without publishing the failed edit.
///
/// @param[in]      listID               Numeric list identity within its owner
/// @param[in]      title                Display title or proposed title text
/// @param[in]      subtitle             Supporting subtitle text
/// @param[in]      newItemPresentation  Optional default presentation for new items in the edited list
/// @param[in,out]  lists                Lists participating in the operation
///
/// @return     (Bool) true after valid metadata is applied; false when validation or target resolution fails
///
/// @note       Saves metadata into the current canonical record, not the editor's older snapshot.
///
@MainActor
@discardableResult
func editBoardList(
    _ listID: Int, title: String, subtitle: String, newItemPresentation: ItemPresentation? = nil,
    in lists: inout [KanbanList]
) -> Bool
{


    do
    {

        guard lists.filter(
            {
                $0.id == listID && !$0.isArchived
            }).count == 1,
        let index = lists.firstIndex(where:
            {
                $0.id == listID && !$0.isArchived
            })
        else
        {

            throw CocoaError(.validationMissingMandatoryProperty)
        }

        let subtitleOverride = subtitle == lists[index].subtitle ? lists[index].subtitleOverride : subtitle
        try lists[index].edit(title: title, subtitle: subtitleOverride)
        if let newItemPresentation
        {
            lists[index].newItemPresentation = newItemPresentation
        }

        return true
    }
    catch
    {

        DatabaseActivity.shared.report(
                        "Could not edit this list: \(error.localizedDescription) Its content has been retained.")
        return false
    }

}
