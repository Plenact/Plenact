// --------------------------------------------------------------------------------------------------
// @file       ContentLifecycleActions.swift
// @brief      Confirmed content archive and deletion presentation
// @details    Delegates mutations to canonical owners and retains confirmation state separately
//             from the source records.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Provides consistent archive/delete context actions for canonical projection rows
///
/// @section    Purpose
///     Keep Search, labels, Calendar, and list pickers from owning duplicate content
///
/// Reveal Delete without UIKit's optimistic destructive-row removal. The owning
/// screen confirms the action and performs its existing checked deletion.
struct ListItemSwipeDelete: ViewModifier
{


    let enabled:   Bool
    let onRequest: () -> Void


    ///
    /// @fcn        ListItemSwipeDelete.body
    /// @brief      Install an explicit trailing swipe-delete action
    /// @details    Exposes Delete only when enabled and disables full-swipe deletion so the user must choose the
    ///             action.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) install an explicit trailing swipe-delete action
    ///
    func body(content: Content) -> some View
    {

        content.swipeActions(edge: .trailing, allowsFullSwipe: false)
        {

            if enabled
            {

                Button(action: onRequest)
                {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
                .accessibilityIdentifier("list.item.swipeDelete")
            }

        }

    }

}


///
/// Adds confirmed archive and delete actions to content
///
/// @section    Purpose
///     Delegates mutations to the owner, retains destructive confirmation state, and dismisses
///     snapshot presentations after accepted removal.
///
struct ContentLifecycleActions: ViewModifier
{


    let title:     String                        /* Canonical content name used for confirmation              */
    let kind:      String                        /* Card or List                                              */
    let onArchive: (() -> Void)?                 /* Optional retention action; dividers support deletion only */
    let onDelete:  () -> Bool                    /* Owner reports saved removal of the confirmed record       */
    @State private var confirmsDelete = false    /* Permanent removal confirmation                            */
    @Environment(\.dismiss) private var dismiss  /* Close snapshot projections after mutation                 */


    ///
    /// @fcn        ContentLifecycleActions.body(content:)
    /// @brief      Add accessible lifecycle actions and permanent deletion confirmation
    /// @details    Delegates mutations to the canonical owner and closes the snapshot projection
    ///
    /// @param[in]  content  Projection row to decorate
    ///
    /// @return     (some View) contextual archive/delete actions
    ///
    func body(content: Content) -> some View
    {


        content
        .contextMenu
        {

            if let onArchive
            {  /* Archive action offered by the menu's owner */


                Button("Archive \(kind)", systemImage: "archivebox")
                {

                    onArchive();
                    dismiss()
                }

            }


            Button("Delete \(kind)", systemImage: "trash", role: .destructive)
            {
                confirmsDelete = true
            }

        }
        .accessibilityActions
        {

            if let onArchive
            {  /* Archive action invoked after confirmation */


                Button("Archive \(kind)")
                {

                    onArchive();
                    dismiss()
                }

            }


            Button("Delete \(kind)")
            {
                confirmsDelete = true
            }

        }

        .confirmationDialog("Delete \(title)?", isPresented: $confirmsDelete, titleVisibility: .visible)
        {

            Button("Delete \(kind)", role: .destructive)
            {
                if onDelete()
                {
                    dismiss()
                }

            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text(
                                        "Permanently deletes this \(kind.lowercased()) and its contents and bookmarks. This cannot be undone. Other retained copies are unchanged."
            )
        }

    }

}
