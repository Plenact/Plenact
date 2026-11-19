// --------------------------------------------------------------------------------------------------
// @file       ContentLifecycleActions.swift
// @brief      Confirmed content archive and deletion presentation
// @details    Delegates mutations to canonical owners and retains confirmation state separately
//             from the source records
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
/// Installs the native trailing Delete action. The owner saves the deletion.
struct ListItemSwipeDelete: ViewModifier
{
    let enabled: Bool
    let onRequest: () -> Void

    /// @fcn        ListItemSwipeDelete.body(content:)
    /// @brief      Compose the decorated content and its interaction controls
    /// @details    Builds the modifier surface from its current state and forwards actions to the owner
    ///
    /// @param[in]  content  Original view receiving the modifier
    ///
    /// @return     (some View) view displaying the current content and controls
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
///     snapshot presentations after accepted removal
///
struct ContentLifecycleActions: ViewModifier
{
    let title:     String                               /* Canonical content name used for confirmation              */
    let kind:      String                               /* Card or List                                              */
    let onArchive: (() -> Void)?                        /* Optional retention action; dividers support deletion only */
    let onDelete:  ()  -> Bool                          /* Owner reports saved removal of the confirmed record       */
    @State private var confirmsDelete = false           /* Permanent removal confirmation                            */
    @Environment(\.dismiss) private var dismiss         /* Close snapshot projections after mutation                 */


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
            {                                                           /* Archive action offered by the menu's owner */
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
            {                                   /* Archive action invoked after confirmation */
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


/// Retains deleted list items and their media for newest-first Undo.
struct ListSwipeUndo
{
    private(set) var deletions: [Deletion] = []

    struct Deletion
    {
        let token = UUID()
        let card: KanbanCard
        let listID: Int
        let index: Int
        let previousID: Int?
        let nextID: Int?
        let wasBookmarked: Bool
        let media: Set<String>
        let cleanMedia: ((Set<String>) -> Void)?

        /// @fcn        ListSwipeUndo.Deletion.restoring(in:bookmarks:)
        /// @brief      Merge a deleted item into its original List without overwriting later edits
        /// @details    Checks destination availability and identity uniqueness, then uses neighboring Cards to
        ///             recover position
        ///
        /// @param[in]  lists  Current ordered Lists, including retained archive records
        /// @param[in]  saved  Current saved item identities
        ///
        /// @return     (([KanbanList], Set<Int>)?) result produced from the current inputs and state
        ///
        func restoring(in lists: [KanbanList], bookmarks saved: Set<Int>) -> ([KanbanList], Set<Int>)?
        {
            var snapshot = lists
            guard let listIndex = snapshot.firstIndex(where: { $0.id == self.listID && !$0.isArchived }),
                  !snapshot.contains(where: { $0.allCards.contains(where: { $0.id == self.card.id }) })
            else
            {
                return nil
            }

            let cards = snapshot[listIndex].cards
            let next = cards.firstIndex { $0.id == self.nextID }
            let previous = cards.firstIndex { $0.id == self.previousID }
            let index = next ?? previous.map { $0 + 1 } ?? min(self.index, cards.count)
            var card = self.card
            card.listTitle = snapshot[listIndex].title
            snapshot[listIndex].cards.insert(card, at: index)

            var bookmarks = saved
            if self.wasBookmarked
            {
                bookmarks.insert(card.id)
            }

            return (snapshot, bookmarks)
        }
    }

    /// @fcn        ListSwipeUndo.delete(_:from:bookmarks:reduceMotion:cleanMedia:save:)
    /// @brief      Save a swipe deletion and retain its item and media for Undo
    /// @details    Protects media before saving and appends an Undo snapshot only after accepted deletion
    ///
    /// @param[in]  card  Complete Card or Note record
    /// @param[in]  list  List containing the affected item
    /// @param[in]  bookmarks  Current saved item identities
    /// @param[in]  reduceMotion  Whether animations should be reduced
    /// @param[in]  cleanMedia  Cleanup callback for released attachment filenames
    /// @param[in]  save  Callback that saves deletion and reports acceptance
    ///
    /// @return     (Void) no return value
    ///
    mutating func delete(_ card: KanbanCard, from list: KanbanList, bookmarks: Set<Int>,
                         reduceMotion: Bool, cleanMedia: ((Set<String>) -> Void)?, save: (Int) -> Bool)
    {
        let cards = list.cards
        guard let index = cards.firstIndex(where: { $0.id == card.id && $0.createdAt == card.createdAt })
        else { return }

        let current = cards[index]
        let deletion = Deletion(
            card: current, listID: list.id, index: index,
            previousID: index > 0 ? cards[index - 1].id : nil,
            nextID: index + 1 < cards.count ? cards[index + 1].id : nil,
            wasBookmarked: bookmarks.contains(card.id),
            media: Set((current.attachments ?? []).flatMap(\.storedFileNames)),
            cleanMedia: cleanMedia
        )

        CardAttachmentStore.retainForUndo(deletion.media, token: deletion.token)
        // Animate the saved List mutation so UIKit can close the row gap with the swipe.
        let deleted = withAnimation(reduceMotion ? nil : .smooth(duration: 0.35))
        {
            save(card.id)
        }
        guard deleted else
        {
            CardAttachmentStore.releaseUndoMedia(token: deletion.token)
            return
        }

        withAnimation(.easeOut(duration: 0.2))
        {
            deletions.append(deletion)
        }
    }

    /// @fcn        ListSwipeUndo.undo(_:restore:)
    /// @brief      Restore the selected revision or deletion through its accepted save boundary
    /// @details    Checks the selected recovery record and retains it when restoration is rejected
    ///
    /// @param[in]  deletion  Retained item deletion to restore
    /// @param[in]  restore  Callback that saves restoration and reports acceptance
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    mutating func undo(_ deletion: Deletion, restore: (Deletion) -> Bool)
    {
        guard deletions.last?.token == deletion.token else { return }
        guard restore(deletion) else
        {
            DatabaseActivity.shared.report("Could not undo the deletion. Your current content has been retained.")
            return
        }

        withAnimation(.easeOut(duration: 0.2))
        {
            _ = deletions.popLast()
        }
        CardAttachmentStore.releaseUndoMedia(token: deletion.token)
    }

    /// @fcn        ListSwipeUndo.expire()
    /// @brief      Release expired deletion snapshots and request unused-media cleanup
    /// @details    Clears pending snapshots, releases their media protection, and invokes each cleanup callback
    ///
    /// @return     (Void) no return value
    ///
    mutating func expire()
    {
        let expired = deletions
        guard !expired.isEmpty else { return }

        withAnimation(.easeOut(duration: 0.2))
        {
            deletions.removeAll()
        }
        for deletion in expired
        {
            CardAttachmentStore.releaseUndoMedia(token: deletion.token)
            deletion.cleanMedia?(deletion.media)
        }
    }

}

struct ListSwipeUndoBanner: ViewModifier
{
    @Binding var history: ListSwipeUndo
    let accessibilityID: String
    var clearsWorkspaceToolbar = false
    let restore: (ListSwipeUndo.Deletion) -> Bool
    @Environment(\.workspaceBottomBarHeight) private var toolbarHeight
    @Environment(\.workspaceBottomBarTopInset) private var toolbarTopInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// @fcn        ListSwipeUndoBanner.body(content:)
    /// @brief      Compose the decorated content and its interaction controls
    /// @details    Builds the modifier surface from its current state and forwards actions to the owner
    ///
    /// @param[in]  content  Original view receiving the modifier
    ///
    /// @return     (some View) view displaying the current content and controls
    ///
    func body(content: Content) -> some View
    {
        content
            .overlay(alignment: .bottom)
            {
                if clearsWorkspaceToolbar, toolbarHeight > 0, !history.deletions.isEmpty
                {
                    GeometryReader
                    {
                        geometry in
                        swipeDeletionNotice
                            .padding(.bottom, max(0, toolbarHeight - geometry.safeAreaInsets.bottom) + toolbarTopInset + 12)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                else
                {
                    swipeDeletionNotice
                }
            }
            .task(id: history.deletions.last?.token)
            {
                guard let token = history.deletions.last?.token else { return }
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }

                guard !Task.isCancelled, history.deletions.last?.token == token else { return }
                history.expire()
            }
    }

    @ViewBuilder
    private var swipeDeletionNotice: some View
    {
        if let deletion = history.deletions.last
        {
            HStack(spacing: 16)
            {
                Text("\(deletion.card.presentation.title) deleted")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Button("Undo")
                {
                    history.undo(deletion, restore: restore)
                }
                .font(.headline)
                .frame(minHeight: 44)
                .accessibilityIdentifier(accessibilityID)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(alignment: .top)
            {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .id(deletion.token)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }
}
