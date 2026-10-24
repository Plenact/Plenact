// --------------------------------------------------------------------------------------------------
// @file       ListActions.swift
// @brief      List options and owner-qualified destination selection
// @details    Presents copy, move, appearance, and reset actions while leaving content allocation
//             and persistence with checked owner operations.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Defines the selectable background tints for kanban lists
///
/// @section    Purpose
///     Provide consistent, subtle colors that help distinguish lists without changing their card content
///
/// @details    Each case exposes a stable raw-value identity, a user-facing title, and a
///             corresponding list background color
///
/// @note       Case ordering controls the options presented by the list color picker
///


///
/// Presents actions for copying, moving, organizing, and archiving one list
///
/// @section    Purpose
///     Keep list-level operations together in a dedicated action sheet
///
struct KanbanListActionsSheet: View
{


    @State private var confirmsCheckmarkReset = false
    @Binding var checkmarkReset: ListCheckmarkReset?
    let onUpdateCard:            (KanbanCard) -> Void
    let list:                    KanbanList  /* The Kanban list this sheet is associated with */
    let canMoveEarlier:          Bool        /* Indicates if the list can be moved earlier    */
    let canMoveLater:            Bool        /* Indicates if the list can be moved later      */
    @Binding var isWatching:     Bool        /* Indicates if the user is watching the list    */
    let onAddCard:               () -> Void  /* Action to perform when adding a card          */
    let onCopyList:              () -> Void  /* Action to perform when copying the list       */
    var onMoveToBoard:           (() -> Void)? = nil
    let onMoveList:              (Int) -> Void   /* Action to perform when moving the list by a given offset                   */
    let onSortList:              (Bool) -> Void  /* Action to perform when sorting the list; true for A to Z, false for Z to A */
    @Binding var cardEditMode:
    EditMode                            /* Manual card ordering in the owning List          */
    let onArchiveCompleted: () -> Void  /* Action to perform when archiving completed cards */
    /// Archived cards available to restore to the active list.
    @Binding var archivedCards: [KanbanCard] /* Shared retained records in this list's archive */
    /// Restores an archived card by stable card identity.
    let onRestoreArchivedCard:     (Int) -> Void  /* Restores a retained record by identity           */
    let onDeleteArchivedCard:      (Int) -> Void  /* Permanently remove a confirmed archived card     */
    let onArchiveList:             () -> Void     /* Action to perform when archiving the entire list */
    let onDeleteList:              () -> Void     /* Permanently remove this list after confirmation  */
    var onEditList:                ((String, String, ItemPresentation) -> Bool)? = nil
    var onAppearance:              ((ItemAppearance?) -> Bool)? = nil
    var inheritedAddItemTextColor: Color = .primary
    var onOpenDayView:             (() -> Void)? = nil
    @State private var isEditingAppearance = false
    @State private var isEditingList = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheetHeight: PresentationDetent = .height(624)
    @Environment(\.dismiss) private var dismiss    /* Dismiss action for list operations             */
    @State private var showsArchivedCards = false  /* Archive browser opened from the compact footer */
    @State private var confirmingArchive = false   /* Archive confirmation presentation state        */
    @State private var confirmingDelete = false    /* Permanent list deletion confirmation           */


    ///
    /// @fcn        KanbanListActionsSheet.body
    /// @brief      Present creation, organization, appearance, and archive actions for one list
    /// @details    Offers copy, bounded earlier/later movement, section-aware sorting, tint/watch
    ///             controls, archived-card browsing, completed-card archival, and confirmed list archival
    ///
    /// @return     (some View) list-actions navigation sheet
    /// @post       Mutation callbacks belong to the parent. Add card delegates sheet handoff without
    ///             calling dismiss here; copy/move/sort/archive actions dismiss after invoking callbacks
    /// @note       Appearance is persisted on Save; Watch remains a temporary view preference
    ///
    var body: some View
    {  /* List operation menu */


        NavigationStack
        {


            List
            {


                Section("List")
                {

                    if let onOpenDayView
                    {

                        Button("Switch to Day View", systemImage: "rectangle.portrait", action: onOpenDayView)
                    }


                    Button
                    {

                        onAddCard()
                    }
                    label:
                    {

                        Label("Add \(list.newItemPresentation.title.lowercased())", systemImage: "plus")
                    }


                    if onEditList != nil
                    {

                        Button("Edit list", systemImage: "pencil")
                        {

                            isEditingList = true
                        }

                    }


                    if onAppearance != nil
                    {

                        Button("Appearance", systemImage: "paintpalette")
                        {
                            isEditingAppearance = true
                        }

                    }

                    Button
                    {

                        isWatching.toggle()
                    }
                    label:
                    {

                        Label(isWatching ? "Unwatch" : "Watch", systemImage: isWatching ? "eye.slash" : "eye")
                    }

                }


                Section("Organize")
                {

                    ListCheckmarkResetControl(
                        list: list, session: $checkmarkReset, confirmsClear: $confirmsCheckmarkReset,
                        onUpdateCard: onUpdateCard)
                    Button
                    {

                        withAnimation(.easeInOut(duration: 0.2))
                        {

                            cardEditMode = cardEditMode == .active ? .inactive : .active
                        }

                        dismiss()
                    }
                    label:
                    {

                        Label(
                            cardEditMode == .active ? "Done reordering cards" : "Reorder cards",
                            systemImage: cardEditMode == .active ? "checkmark.circle" : "arrow.up.arrow.down")
                    }


                    Menu
                    {

                        Button("Title A to Z")
                        {

                            onSortList(true)
                            dismiss()
                        }


                        Button("Title Z to A")
                        {

                            onSortList(false)
                            dismiss()
                        }

                    }
                    label:
                    {

                        Label("Sort Alphabetically", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.primary)
                    }


                    Button
                    {

                        onCopyList()
                        dismiss()
                    }
                    label:
                    {

                        Label("Copy list", systemImage: "doc.on.doc")
                    }

                    if let onMoveToBoard
                    {

                        Button
                        {

                            onMoveToBoard()
                            dismiss()
                        }
                        label:
                        {

                            Label("Move list to another board", systemImage: "arrow.right.square")
                        }

                    }


                    Menu
                    {

                        Button("Move earlier")
                        {

                            onMoveList(-1)
                            dismiss()
                        }

                        .disabled(!canMoveEarlier)

                        Button("Move later")
                        {

                            onMoveList(1)
                            dismiss()
                        }

                        .disabled(!canMoveLater)
                    }
                    label:
                    {


                        Label("Move list", systemImage: "arrow.left.arrow.right")
                        .foregroundStyle(.primary)
                    }

                }


                Section
                {

                    HStack(alignment: .top, spacing: 8)
                    {

                        Button
                        {

                            showsArchivedCards = true
                        }
                        label:
                        {

                            footerActionLabel("Archived", symbol: "archivebox")
                        }
                        .accessibilityLabel("View Archived Cards")
                        .help("View Archived Cards")

                        Button
                        {

                            onArchiveCompleted()
                            dismiss()
                        }
                        label:
                        {

                            footerActionLabel("Completed", symbol: "checkmark.circle")
                        }
                        .accessibilityLabel("Archive completed cards")
                        .help("Archive completed cards")

                        Button
                        {

                            confirmingArchive = true
                        }
                        label:
                        {

                            footerActionLabel("Archive list", symbol: "archivebox.fill")
                        }
                        .accessibilityLabel("Archive list")
                        .help("Archive list")

                        Button(role: .destructive)
                        {

                            confirmingDelete = true
                        }
                        label:
                        {

                            footerActionLabel("Delete", symbol: "trash")
                            .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Delete List")
                        .help("Delete List")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }

            }

            .listStyle(.insetGrouped)
            .listSectionSpacing(12)
            .contentMargins(.top, 12, for: .scrollContent)
            .navigationTitle("List actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .topBarLeading)
                {

                    Button("Close", systemImage: "xmark")
                    {

                        dismiss()
                    }

                }

            }

            .navigationDestination(isPresented: $showsArchivedCards)
            {

                ArchivedCardsView(
                    listTitle: list.title,
                    cards: $archivedCards,
                    onRestore: onRestoreArchivedCard,
                    onDelete: onDeleteArchivedCard
                )
            }
            .modifier(
                ListCheckmarkResetConfirmation(
                    list: list, session: $checkmarkReset,
                    confirmsClear: $confirmsCheckmarkReset, onUpdateCard: onUpdateCard)
            )
            .confirmationDialog("Archive \(list.title)?", isPresented: $confirmingArchive, titleVisibility: .visible)
            {

                Button("Archive list", role: .destructive)
                {

                    onArchiveList()
                    dismiss()
                }

            }
            .confirmationDialog("Delete \(list.title)?", isPresented: $confirmingDelete, titleVisibility: .visible)
            {

                Button("Delete List", role: .destructive)
                {

                    onDeleteList()
                    dismiss()
                }

                Button("Cancel", role: .cancel)
                {

                }

            }
            message:
            {

                Text(
                                                "Permanently deletes this list, all active and archived cards, and their bookmarks. This cannot be undone."
                )
            }

        }

        .presentationDetents([.height(624), .large], selection: $sheetHeight)
        .onAppear
        {
            sheetHeight = dynamicTypeSize.isAccessibilitySize ? .large : .height(624)
        }
        .onChange(of: dynamicTypeSize)
        {
            _, size in
            if size.isAccessibilitySize
            {
                sheetHeight = .large
            }

        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .sheet(isPresented: $isEditingList)
        {

            if let onEditList
            {

                ListInfoEditorSheet(list: list, onSave: onEditList)
                .databaseActivityOverlay()
            }

        }
        .sheet(isPresented: $isEditingAppearance)
        {

            if let onAppearance
            {

                ItemAppearanceSheet(
                    title: list.title, appearance: list.appearance, showsListBackground: true,
                    inheritedAddItemTextColor: inheritedAddItemTextColor, onSave: onAppearance)
            }

        }

    }


    ///
    /// @fcn        KanbanListActionsSheet.footerActionLabel
    /// @brief      Build a consistent list-action footer label
    /// @details    Stacks the icon and wrapping caption in a shared minimum-height touch region.
    ///
    /// @param[in]  title   Display title or proposed title text
    /// @param[in]  symbol  SF Symbol name used by the control
    ///
    /// @return     (some View) a consistent list-action footer label
    ///
    private func footerActionLabel(_ title: String, symbol: String) -> some View
    {

        VStack(spacing: 8)
        {

            Image(systemName: symbol)
            .font(.title3)
            .accessibilityHidden(true)
            Text(title)
            .font(.caption2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .top)
        .contentShape(Rectangle())
    }

}


///
/// Chooses an owner for copying a List
///
/// @section    Purpose
///     Keeps the source snapshot and current owner context together and routes copies through
///     checked workspace access.
///
struct CopyListDestinationSheet: View
{


    let source:    KanbanList
    let access:    PlanningCalendarAccess?
    let currentID: UUID?
    let copyHere:  () -> Bool
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        CopyListDestinationSheet.destinationWeeks
    /// @brief      List active calendar-week copy destinations
    /// @details    Excludes the current source week and archived collections while retaining the calendar's week
    ///             ordering.
    ///
    /// @param[in]  access  Checked calendar and personal-owner access callbacks
    ///
    /// @return     ([DatedPlanningWeek]) active calendar weeks excluding the source owner
    ///
    private func destinationWeeks(_ access: PlanningCalendarAccess) -> [DatedPlanningWeek]
    {

        let sourceID: UUID? = currentID ?? access.document.week(for: .now)?.id
        return access.document.weeks.filter
        {
            $0.collection.isActive && $0.id != sourceID
        }

    }


    ///
    /// @fcn        CopyListDestinationSheet.copy
    /// @brief      Copy the source list into a calendar week
    /// @details    Creates a cross-board copy and dismisses with confirmation only after the checked week save
    ///             succeeds.
    ///
    /// @param[in]  week    Dated planning week being inspected or saved
    /// @param[in]  access  Checked calendar and personal-owner access callbacks
    ///
    /// @return     (Void) no return value
    ///
    private func copy(to week: DatedPlanningWeek, using access: PlanningCalendarAccess)
    {

        var updated = week
        let copy = ListCopying.copy(source, into: updated.collection.lists, crossBoard: true)
        updated.collection.lists.append(copy)
        if access.saveWeek(updated)
        {

            dismiss()
            TransferConfirmationPresenter.shared.show(
                TransferConfirmation(title: source.title, destination: week.rangeTitle, action: .copied))
        }

    }

    var body: some View
    {

        NavigationStack
        {

            List
            {

                Section
                {

                    Button("This board")
                    {
                        if copyHere()
                        {
                            dismiss()
                        }

                    }

                }

                if let access
                {

                    Section("Week boards")
                    {

                        ForEach(destinationWeeks(access))
                        {
                            week in
                            Button(week.startKey == access.document.currentWeekKey ? "This Week" : week.rangeTitle)
                            {

                                copy(to: week, using: access)
                            }

                        }

                    }

                    Section("Plans boards")
                    {

                        ForEach(access.library.filter
                            {
                                $0.isActive && $0.kind == .board && $0.id != currentID
                            })
                        {

                        board in
                            Button(board.title)
                            {

                                var updated = board
                                updated.lists.append(ListCopying.copy(source, into: updated.lists, crossBoard: true))
                                if access.saveLibrary(updated)
                                {

                                    dismiss()
                                    TransferConfirmationPresenter.shared.show(
                                        TransferConfirmation(
                                            title: source.title, destination: board.title, action: .copied))
                                }

                            }

                        }

                    }

                    Section
                    {

                        Text(
                                                                        "Copies cards, archived cards, and list settings. Links to cards outside this list become plain checklist text on another board."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }

            }
            .navigationTitle("Copy List To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {
                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

            }

        }

    }

}


///
/// Chooses a different owner for moving a List
///
/// @section    Purpose
///     Resolves the source owner and delegates cross-Board transfer through the injected workspace
///     callbacks.
///
struct MoveListDestinationSheet: View
{


    let source:    KanbanList
    let access:    PlanningCalendarAccess?
    let currentID: UUID?
    @Environment(\.dismiss) private var dismiss
    private var sourceID: UUID?
    {

        currentID ?? access?.document.weeks.first
        {
            $0.startKey == access?.document.currentWeekKey
        }?.id
    }


    ///
    /// @fcn        MoveListDestinationSheet.move
    /// @brief      Move the source list to the selected owner
    /// @details    Requires the source owner and a successful movement callback before dismissing the destination
    ///             sheet.
    ///
    /// @param[in]  id  Stable identity used by this operation
    ///
    /// @return     (Void) no return value
    ///
    private func move(to id: UUID?)
    {

        guard let sourceID, access?.moveList?(source.id, sourceID, id) == true else
        {
            return
        }

        dismiss()
    }

    var body: some View
    {

        NavigationStack
        {

            List
            {

                if let access
                {

                    Section
                    {

                        Button
                        {

                            move(to: nil)
                        }
                        label:
                        {

                            Label("Standalone List in Plans", systemImage: "list.bullet.rectangle")
                        }

                    }

                    Section("Week boards")
                    {

                        ForEach(access.document.weeks.filter
                            {
                                $0.id != sourceID && $0.collection.isActive
                            })
                        {
                            week in
                            Button(
                                week.startKey == access.document.currentWeekKey
                                ? "This Week · " + week.rangeTitle : week.rangeTitle
                            )
                            {
                                move(to: week.id)
                            }

                        }

                    }

                    Section("Plans boards")
                    {

                        ForEach(access.library.filter
                            {
                                $0.id != sourceID && $0.isActive && $0.kind == .board
                            })
                        {

                        board in
                            Button(board.title)
                            {
                                move(to: board.id)
                            }

                        }

                    }

                    Section
                    {

                        Text(
                                                                        "Moves the list and all its contents. A dated list leaves an empty day in its original week."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }

            }
            .navigationTitle("Move List To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {
                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

            }

        }

    }

}


///
/// Presents the List checkmark reset menu action
///
/// @section    Purpose
///     Requests confirmation from the owning List, which retains the temporary checkmark
///     restoration session.
///
struct ListCheckmarkResetControl: View
{


    let list:                   KanbanList
    @Binding var session:       ListCheckmarkReset?
    @Binding var confirmsClear: Bool
    let onUpdateCard:           (KanbanCard) -> Void

    var body: some View
    {

        Button(
            session?.canRestore(list) == true ? "Restore previous checkmarks" : "Clear all checkmarks…",
            systemImage: session?.canRestore(list) == true ? "arrow.uturn.backward" : "checkmark.circle"
        )
        {

            if let session, let cards = session.restoring(list)
            {

                self.session = nil
                apply(cards)
            }
            else
            {

                confirmsClear = true
            }

        }
        .disabled(session?.canRestore(list) != true && !ListCheckmarkReset.values(in: list).values.contains(true))
    }


    ///
    /// @fcn        ListCheckmarkResetControl.apply
    /// @brief      Publish only cards changed by a checkmark operation
    /// @details    Compares each candidate against the current list and invokes the update callback only for
    ///             differing records.
    ///
    /// @param[in]  cards  Canonical card values in their current order
    ///
    /// @return     (Void) no return value
    ///
    private func apply(_ cards: [KanbanCard])
    {

        for card in cards where list.cards.first(where:
            {
                $0.id == card.id
            }) != card
        {
            onUpdateCard(card)
        }

    }

}


///
/// Confirms List checkmark clearing and retains its Undo snapshot
///
/// @section    Purpose
///     Captures restoration state before publishing Card updates without replacing unrelated
///     content fields.
///
struct ListCheckmarkResetConfirmation: ViewModifier
{


    let list:                   KanbanList?
    @Binding var session:       ListCheckmarkReset?
    @Binding var confirmsClear: Bool
    let onUpdateCard:           (KanbanCard) -> Void


    ///
    /// @fcn        ListCheckmarkResetConfirmation.body
    /// @brief      Confirm clearing a list's nested checkmarks
    /// @details    Captures a restoration session before publishing changed cards and explains when that restoration
    ///             remains available.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) confirm clearing a list's nested checkmarks
    ///
    func body(content: Content) -> some View
    {

        content.confirmationDialog(
                        "Clear all checkmarks in \(list?.title ?? "this list")?", isPresented: $confirmsClear,
                        titleVisibility: .visible
        )
        {

            Button("Clear all checkmarks", role: .destructive)
            {

                guard let list else
                {
                    return
                }

                let (snapshot, cards) = ListCheckmarkReset.reset(list)
                session = snapshot
                for card in cards where list.cards.first(where:
                    {
                        $0.id == card.id
                    }) != card
                {
                    onUpdateCard(card)
                }

            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text(
                                    "This unchecks cards and nested checklist items. You can restore these checkmarks until you change a checkmark or leave this list."
            )
        }

    }

}
