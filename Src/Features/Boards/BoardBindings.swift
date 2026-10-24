// --------------------------------------------------------------------------------------------------
// @file       BoardBindings.swift
// @brief      Active and archived Board binding projections
// @details    Lets child views edit one partition while retaining the complete owner's other
//             partition.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Adds active and archived projections to a complete Board-list binding
///
/// @section    Purpose
///     Let child views update one partition without discarding the other
///
extension Binding where Value == [KanbanList]
{


    ///
    /// @fcn        Binding.activeLists
    /// @brief      Expose the active partition of a complete Board list binding
    /// @details    Getter filters archived lists; setter replaces the active portion while retaining
    ///             current archived entries after it. Supplied active entries are not normalized
    ///
    /// @return     (Binding<[KanbanList]>) projected active-list binding
    /// @pre        Setter values represent active lists with isArchived false
    /// @post       Constructing the projection does not mutate the underlying snapshot
    ///
    var activeLists: Binding<[KanbanList]>
    {  /* Mutable active partition of the Board document */

        Binding(
            get:
            {
                wrappedValue.filter
                {
                    !$0.isArchived
                }

            },
            set:
            {
                wrappedValue = $0 + wrappedValue.filter(\.isArchived)
            }
        )
    }


    ///
    /// @fcn        Binding.archivedLists
    /// @brief      Expose the archived partition of a complete Board list binding
    /// @details    Getter filters archived entries; setter retains active entries first and
    ///             replaces the archive portion, forcing every supplied entry's archive flag true
    ///
    /// @return     (Binding<[KanbanList]>) projected archived-list binding
    /// @post       Setter writes preserve the active portion; constructing the projection does not write
    ///
    var archivedLists: Binding<[KanbanList]>
    {  /* Mutable archived partition of the Board document */

        Binding(
            get:
            {
                wrappedValue.filter(\.isArchived)
            },
            set:
            {
                archived in
                wrappedValue =
                wrappedValue.filter
                {
                    !$0.isArchived
                }

                + archived.map
                {
                    list in
                    var archivedList = list /* Incoming list normalized to archived state */
                    archivedList.isArchived = true
                    return archivedList
                }

            }
        )
    }

}
