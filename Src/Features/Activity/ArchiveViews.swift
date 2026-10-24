// --------------------------------------------------------------------------------------------------
// @file       ArchiveViews.swift
// @brief      Read-only inspection of retained archives
// @details    Makes archived collections, Lists, and Cards inspectable without silently restoring
//             or editing their contents.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Browses all retained content inside an archived personal collection
///
/// @section    Purpose
///     Provide confirmed list/card deletion without restoring or duplicating the Board
///
struct ArchivedCollectionContentsView: View
{


    @Binding var collection: PersonalCollection     /* Canonical retained collection           */
    let onDeleteBoard:       () -> Bool             /* Parent reports saved collection removal */
    let onRestoreBoard:      () -> Void             /* Parent saves restoration                */
    @Environment(\.dismiss) private var dismiss     /* Return to Saved                         */
    @State private var deletingList: KanbanList?    /* Nested list awaiting removal            */
    @State private var deletingCard: KanbanCard?    /* Retained card awaiting removal          */
    @State private var confirmsDeleteBoard = false  /* Entire collection removal confirmation  */


    ///
    /// @fcn        ArchivedCollectionContentsView.deleteCard(_:)
    /// @brief      Save complete retained-card and bookmark removal through the canonical binding
    /// @details    The owner reports save errors; failed saves leave its binding unchanged
    ///
    /// @param[in]  id  Card identity within this collection
    ///
    /// @return     (Bool) whether the canonical card was removed
    ///
    @discardableResult
    private func deleteCard(_ id: Int) -> Bool
    {


        var updated = collection /* Archived Board snapshot receiving the requested change */

        BoardContentDeletion.card(id, in: &updated.lists, savedCardIDs: &updated.savedCardIDs)
        collection = updated

        return !collection.lists.contains
        {
            $0.allCards.contains
            {
                $0.id == id
            }

        }

    }


    ///
    /// @fcn        ArchivedCollectionContentsView.body
    /// @brief      Inspect archived collection lists and their active/archive cards
    /// @details    Deletion updates the owning collection's complete snapshot and local bookmarks
    /// @return     (some View) retained-content browser with restore and deletion controls
    ///
    var body: some View
    {  /* Archived Board lists and retained card management */

        NavigationStack
        {

            List
            {

                ForEach(collection.lists)
                {
                    list in
                    Section(list.title + (list.isArchived ? " (archived)" : ""))
                    {

                        ForEach(list.allCards)
                        {
                            card in
                            NavigationLink(card.word)
                            {

                                ArchivedCardInspectionView(card: card)
                                {

                                    deleteCard(card.id)
                                }

                            }
                            .contextMenu
                            {

                                Button("Delete Card", systemImage: "trash", role: .destructive)
                                {
                                    deletingCard = card
                                }

                            }

                            .accessibilityAction(named: "Delete Card")
                            {
                                deletingCard = card
                            }

                        }


                        Button("Delete List", systemImage: "trash", role: .destructive)
                        {
                            deletingList = list
                        }

                    }

                }

            }

            .navigationTitle(collection.title)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Close")
                    {
                        dismiss()
                    }

                }

                ToolbarItem(placement: .primaryAction)
                {

                    Menu("Collection actions", systemImage: "ellipsis.circle")
                    {

                        Button("Restore")
                        {

                            onRestoreBoard();
                            dismiss()
                        }

                        Button("Delete \(collection.kind.rawValue)", systemImage: "trash", role: .destructive)
                        {

                            confirmsDeleteBoard = true
                        }

                    }

                }

            }

            .confirmationDialog(
                                    "Delete \(deletingList?.title ?? "list")?",
                                    isPresented: Binding(
                                        get:
                                        {
                                            deletingList != nil
                                        }, set:
                                        {
                                            if !$0
                                            {
                                                deletingList = nil
                                            }

                                        }
                                    ), titleVisibility: .visible
            )
            {

                Button("Delete List", role: .destructive)
                {

                    if let deletingList
                    {  /* Archived list awaiting permanent deletion */


                        var updated = collection /* Archived Board snapshot excluding the removed list */

                        BoardContentDeletion.list(
                            deletingList.id, in: &updated.lists, savedCardIDs: &updated.savedCardIDs)
                        collection = updated
                    }


                    deletingList = nil
                }


                Button("Cancel", role: .cancel)
                {
                    deletingList = nil
                }

            }
            message:
            {

                Text("Permanently deletes this list, all retained cards, and bookmarks. This cannot be undone.")
            }

            .confirmationDialog(
                                    "Delete \(collection.kind.rawValue)?", isPresented: $confirmsDeleteBoard, titleVisibility: .visible
            )
            {

                Button("Delete \(collection.kind.rawValue)", role: .destructive)
                {
                    if onDeleteBoard()
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

                Text("Permanently deletes all content in this retained collection. This cannot be undone.")
            }

            .confirmationDialog(
                                    "Delete \(deletingCard?.word ?? "card")?",
                                    isPresented: Binding(
                                        get:
                                        {
                                            deletingCard != nil
                                        }, set:
                                        {
                                            if !$0
                                            {
                                                deletingCard = nil
                                            }

                                        }
                                    ), titleVisibility: .visible
            )
            {

                Button("Delete Card", role: .destructive)
                {

                    if let deletingCard
                    {  /* Archived card awaiting permanent deletion */


                        deleteCard(deletingCard.id)
                    }


                    deletingCard = nil
                }


                Button("Cancel", role: .cancel)
                {
                    deletingCard = nil
                }

            }
            message:
            {

                Text("Permanently deletes this card, its details, and its bookmark. This cannot be undone.")
            }

        }

    }

}


///
/// Presents the archived lists belonging to one board
///
/// @section    Purpose
///     Let the user restore a list without deleting its retained cards
///
struct ArchivedListsView: View
{


    /// Archived lists available for restoration.
    @Binding var lists: [KanbanList] /* Shared archived-list partition */
    /// Requests restoration of a list by identity.
    let onRestore:                   (Int) -> Void       /* Restores an archived list by identity        */
    let onDelete:                    (Int) -> Void       /* Permanently remove a confirmed archived list */
    let onDeleteCard:                (Int, Int) -> Void  /* Remove a card within the archived list       */
    @State private var deletingList: KanbanList?         /* List awaiting permanent deletion             */
    /// Dismiss action for the archive browser.
    @Environment(\.dismiss) private var dismiss /* Archived-list browser dismissal action */


    ///
    /// @fcn        ArchivedListsView.body
    /// @brief      Browse lists archived from the current Board
    /// @details    Shows each list's active non-divider count and archived-card count,
    ///             with Restore controls and an empty-state explanation
    ///
    /// @return     (some View) archived-list navigation sheet with Close action
    /// @post       Restore delegates the list identity to onRestore; Close dismisses without changes
    ///
    var body: some View
    {  /* Archived-list browser with restore and deletion actions */

        NavigationStack
        {

            List
            {

                ForEach(lists)
                {
                    list in
                    HStack
                    {

                        VStack(alignment: .leading, spacing: 4)
                        {

                            NavigationLink(list.title)
                            {

                                ArchivedListContentsView(
                                    lists: $lists, listID: list.id,
                                    onDeleteCard:
                                    {
                                        onDeleteCard(list.id, $0)
                                    },
                                    onDeleteList:
                                    {
                                        onDelete(list.id)
                                    }
                                )
                            }

                            .font(.headline)
                            Text(
                                                                                    "\(list.cards.filter { !$0.isSectionDivider } .count) cards · \(list.archivedCards.count) archived cards"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }


                        Spacer()
                        Button("Restore")
                        {
                            onRestore(list.id)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Restore \(list.title)")
                        Button("Delete", systemImage: "trash", role: .destructive)
                        {
                            deletingList = list
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Delete \(list.title)")
                    }

                }

            }
            .overlay
            {

                if lists.isEmpty
                {


                    ContentUnavailableView(
                                                            "No Archived Lists", systemImage: "archivebox",
                                                            description: Text("Lists archived from this board will appear here.")
                    )
                    .allowsHitTesting(false)
                }

            }

            .navigationTitle("Archived Lists")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                                    "Delete \(deletingList?.title ?? "list")?",
                                    isPresented: Binding(
                                        get:
                                        {
                                            deletingList != nil
                                        }, set:
                                        {
                                            if !$0
                                            {
                                                deletingList = nil
                                            }

                                        }
                                    ), titleVisibility: .visible
            )
            {

                Button("Delete List", role: .destructive)
                {

                    if let deletingList
                    {  /* Archived list awaiting permanent deletion */


                        onDelete(deletingList.id)
                    }


                    deletingList = nil
                }


                Button("Cancel", role: .cancel)
                {
                    deletingList = nil
                }

            }
            message:
            {

                Text(
                                                "This permanently deletes the list, all its active and archived cards, and their bookmarks. This cannot be undone."
                )
            }
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Close")
                    {
                        dismiss()
                    }

                }

            }

        }

    }

}


///
/// Makes the contents of an archived list inspectable without restoring it
///
/// @section    Purpose
///     Offer confirmed card deletion for both retained card partitions
///
struct ArchivedListContentsView: View
{


    @Binding var lists:              [KanbanList]   /* Canonical retained lists         */
    let listID:                      Int            /* Archived list identity           */
    let onDeleteCard:                (Int) -> Void  /* Owner removes confirmed cards    */
    let onDeleteList:                () -> Void     /* Owner removes the confirmed list */
    @State private var deletingCard: KanbanCard?    /* Card awaiting permanent removal  */
    @State private var confirmsDeleteList = false   /* Complete retained list deletion  */
    @Environment(\.dismiss) private var dismiss     /* Close a deleted list             */

    ///
    /// @fcn        ArchivedListContentsView.list
    /// @brief      Resolve the current archived list by identity
    /// @details    Failed saves keep the original rows visible rather than hiding snapshot records
    /// @return     (KanbanList?) current retained list
    ///
    private var list: KanbanList?
    {

        lists.first
        {
            $0.id == listID
        }

    }  /* Current archived list resolved by its stable identity */


    ///
    /// @fcn        ArchivedListContentsView.body
    /// @brief      Browse all retained cards and offer permanent removal
    /// @details    Leaves the list archived and does not create editable copies of its cards
    /// @return     (some View) retained-content list with confirmation
    ///
    var body: some View
    {  /* Retained cards within the selected archived list */

        List(list?.allCards ?? [])
        {
            card in
            VStack(alignment: .leading, spacing: 8)
            {

                NavigationLink(card.word)
                {

                    ArchivedCardInspectionView(card: card)
                    {

                        onDeleteCard(card.id)

                        return !(list?.allCards.contains
                            {
                                $0.id == card.id
                            }
                            ?? false)
                    }

                }

                .font(.headline)
                Text(PlanRichText.display(card.funParagraph)).foregroundStyle(.secondary)
                Button("Delete Card", systemImage: "trash", role: .destructive)
                {
                    deletingCard = card
                }

            }

        }

        .navigationTitle(list?.title ?? "List unavailable")
        .toolbar
        {

            ToolbarItem(placement: .primaryAction)
            {

                Button("Delete List", systemImage: "trash", role: .destructive)
                {
                    confirmsDeleteList = true
                }

            }

        }

        .confirmationDialog("Delete this list?", isPresented: $confirmsDeleteList, titleVisibility: .visible)
        {

            Button("Delete List", role: .destructive)
            {

                onDeleteList()

                if list == nil
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

            Text("Permanently deletes this list, all retained cards, and bookmarks. This cannot be undone.")
        }

        .confirmationDialog(
                        "Delete \(deletingCard?.word ?? "card")?",
                        isPresented: Binding(
                            get:
                            {
                                deletingCard != nil
                            }, set:
                            {
                                if !$0
                                {
                                    deletingCard = nil
                                }

                            }
                        ), titleVisibility: .visible
        )
        {

            Button("Delete Card", role: .destructive)
            {

                if let deletingCard
                {  /* Retained card awaiting permanent deletion */


                    onDeleteCard(deletingCard.id)
                }


                deletingCard = nil
            }


            Button("Cancel", role: .cancel)
            {
                deletingCard = nil
            }

        }
        message:
        {

            Text("Permanently deletes this card, its details, and its bookmark. This cannot be undone.")
        }

    }

}


///
/// Displays retained card content without synchronizing an editable snapshot
///
/// @section    Purpose
///     Allow inspection and confirmed permanent deletion before restoration
///
struct ArchivedCardInspectionView: View
{


    let card:     KanbanCard                     /* Retained card snapshot                      */
    let onDelete: () -> Bool                     /* Owner reports successful save-first removal */
    @State private var confirmsDelete = false    /* Permanent deletion confirmation             */
    @Environment(\.dismiss) private var dismiss  /* Return after deletion                       */

    ///
    /// @fcn        ArchivedCardInspectionView.body
    /// @brief      Inspect retained description, checklist actions, comments, and media references
    /// @details    This read-only view never writes stale card state on disappearance
    /// @return     (some View) archived card detail with a confirmed Delete Card action
    ///
    var body: some View
    {  /* Archived card preview with optional featured media */

        List
        {

            if let cover = card.coverAttachment
            {  /* Valid featured attachment shown in the archive preview */


                Section("Card Cover")
                {
                    CardCoverPreview(attachment: cover)
                }

            }


            Section("Description")
            {
                Text(PlanRichText.display(card.funParagraph))
            }

            ForEach(card.checklists)
            {
                checklist in
                Section(checklist.title)
                {

                    ForEach(checklist.items)
                    {
                        item in
                        Label(item.title, systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    }

                }

            }


            Section("Attachments")
            {

                ForEach(card.attachments ?? [])
                {
                    attachment in
                    if let url = attachment.url
                    {  /* Remote address used to display the archived cover */


                        Link("Open link", destination: url)
                    }
                    else if let url = CardAttachmentStore.fileURL(for: attachment)
                    {  /* Local media file used to display the archived cover */

                        ShareLink(item: url)
                        {

                            Label(attachment.fileName ?? "Attachment", systemImage: "paperclip")
                        }

                    }

                }

            }


            Section("Comments")
            {

                ForEach(card.comments)
                {
                    comment in
                    VStack(alignment: .leading)
                    {

                        Text(comment.author).font(.headline)
                        Text(PlanRichText.display(comment.body))
                    }

                }

            }


            Button("Delete Card", systemImage: "trash", role: .destructive)
            {
                confirmsDelete = true
            }

        }

        .navigationTitle(card.word)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(card.word)?", isPresented: $confirmsDelete, titleVisibility: .visible)
        {

            Button("Delete Card", role: .destructive)
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
                                    "Permanently deletes this card, its details, and its bookmark. This cannot be undone. Other retained copies are unchanged."
            )
        }

    }

}


///
/// Presents cards retained in a list's archive
///
/// @section    Purpose
///     Let the user restore archived cards while preserving their stored card state
///
struct ArchivedCardsView: View
{


    /// Title of the list whose archived cards are being browsed.
    let listTitle: String /* Owning list name displayed in the archive browser */
    /// Archived card snapshot supplied by the owning list.
    @Binding var cards: [KanbanCard] /* Shared archived-card collection displayed by the browser */
    /// Requests restoration of an archived card by identity.
    let onRestore:                   (Int) -> Void  /* Returns an archived card to its active list */
    let onDelete:                    (Int) -> Void  /* Owner removes confirmed archived cards      */
    @State private var deletingCard: KanbanCard?    /* Archived card awaiting deletion             */


    ///
    /// @fcn        ArchivedCardsView.body
    /// @brief      Browse saved card records for one list
    /// @details    Displays titles and up to three lines of supporting copy, with Restore controls,
    ///             an empty-state explanation, and a reminder that completion state is preserved
    ///
    /// @return     (some View) archived-card navigation list
    /// @post       Restore invokes onRestore with the card identity; record movement belongs to the parent
    ///
    var body: some View
    {  /* Archived-card browser with restore and deletion controls */

        List
        {

            Section
            {

                ForEach(cards)
                {
                    card in
                    HStack(alignment: .top, spacing: 12)
                    {

                        VStack(alignment: .leading, spacing: 4)
                        {

                            NavigationLink(card.word)
                            {

                                ArchivedCardInspectionView(card: card)
                                {

                                    onDelete(card.id)

                                    return !cards.contains
                                    {
                                        $0.id == card.id
                                    }

                                }

                            }

                            .font(.headline)

                            if !card.funParagraph.isEmpty
                            {


                                Text(PlanRichText.display(card.funParagraph))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            }

                        }


                        Spacer()
                        Button("Restore")
                        {

                            onRestore(card.id)
                        }

                        .buttonStyle(.bordered)
                        .accessibilityLabel("Restore \(card.word)")
                        Button("Delete", systemImage: "trash", role: .destructive)
                        {
                            deletingCard = card
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Delete \(card.word)")
                    }

                }

            }
            header:
            {

                Text(listTitle)
            }
            footer:
            {

                if !cards.isEmpty
                {


                    Text("Restored cards return to the end of this list and keep their completion status.")
                }

            }

        }
        .overlay
        {

            if cards.isEmpty
            {


                ContentUnavailableView(
                                                "No Archived Cards",
                                                systemImage: "archivebox",
                                                description: Text("Cards you archive from this list will appear here.")
                )
                .allowsHitTesting(false)
            }

        }

        .navigationTitle("Archived Cards")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
                        "Delete \(deletingCard?.word ?? "card")?",
                        isPresented: Binding(
                            get:
                            {
                                deletingCard != nil
                            }, set:
                            {
                                if !$0
                                {
                                    deletingCard = nil
                                }

                            }
                        ), titleVisibility: .visible
        )
        {

            Button("Delete Card", role: .destructive)
            {

                if let deletingCard
                {  /* Archived record awaiting permanent deletion */


                    onDelete(deletingCard.id)
                }


                deletingCard = nil
            }


            Button("Cancel", role: .cancel)
            {
                deletingCard = nil
            }

        }
        message:
        {

            Text("Permanently deletes this card, its details, and its bookmark. This cannot be undone.")
        }

    }

}
