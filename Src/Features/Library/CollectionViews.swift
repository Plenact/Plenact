// --------------------------------------------------------------------------------------------------
// @file       CollectionViews.swift
// @brief      Personal collection presentation and settings
// @details    Presents reusable directory rows and Board destinations and edits collection
//             metadata through isolated drafts.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Resolves collection identity colors for Library presentation
///
/// @section    Purpose
///     Matches the default On the Table identity to its banner while preserving explicit custom
///     colors.
///
extension PersonalCollection
{


    /// Match the default On the Table identity to its banner without changing custom colors.
    var libraryIdentityColor: Color
    {

        if kind == .list, title == "On the Table", color == .coral
        {

            return ItemAccent.coral.darkHeaderColor
        }

        return color.color
    }

}


///
/// Presents a personal collection in the Library directory
///
/// @section    Purpose
///     Combines identity, active content count, and an optional moving preview while adapting its
///     layout for text size.
///
struct LibraryCollectionRow: View
{


    let title:    String  /* User-owned collection or Week Board title       */
    let subtitle: String  /* Collection kind and active-list context         */
    let icon:     String  /* SF Symbol representing the organizing space     */
    let color:    Color   /* Collection accent, not its only identifying cue */
    let count:    Int     /* Active non-divider card count                   */
    var preview:  String = ""
    var scrollsPreview = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize /* Adapt text arrangement for accessibility sizes */

    ///
    /// @fcn        LibraryCollectionRow.body
    /// @brief      Present the space's name, kind, and labeled card count
    /// @details    Uses a tinted icon and accent strip; accessibility text sizes place the count
    ///             below the title rather than compressing it into a trailing column
    /// @return     (some View) content-fitting directory row with combined accessibility text
    /// @post       Rendering does not modify the owning Board or collection
    ///
    var body: some View
    {  /* Adaptive collection directory row with a labeled card count */


        HStack(spacing: 12)
        {


            RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4, height: 38)
            .accessibilityHidden(true)

            Image(systemName: icon)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)

            let layout =
            dynamicTypeSize.isAccessibilitySize /* Accessible arrangement of the collection name and count */
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

            layout
            {

                VStack(alignment: .leading, spacing: 5)
                {

                    Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    if !preview.isEmpty
                    {

                        GentleCollectionPreview(text: preview, scrolls: scrollsPreview)
                    }

                }

                .frame(maxWidth: .infinity, alignment: .leading)
                Text(count == 1 ? "1 card" : "\(count) cards")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            }

            .frame(maxWidth: .infinity, alignment: .leading)
        }

        .padding(.vertical, 4)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

}


///
/// Presents the Library browse-filter choices
///
/// @section    Purpose
///     Keeps the selected checkmark visible during dismissal and delegates the accepted filter
///     choice to the Library owner.
///
struct CollectionFilterPopover: View
{


    let selection: LibraryBrowseFilter
    let onSelect:  (LibraryBrowseFilter) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var pendingSelection: LibraryBrowseFilter?
    @State private var opacity = 1.0

    var body: some View
    {

        VStack(spacing: 0)
        {

            ForEach(LibraryBrowseFilter.allCases)
            {
                filter in
                Button
                {

                    opacity = 1
                    onSelect(filter)
                    pendingSelection = filter
                }
                label:
                {

                    HStack(spacing: 12)
                    {

                        Image(systemName: filter.symbol).frame(width: 22)
                        Text(filter.rawValue)
                        Spacer(minLength: 24)
                        Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .opacity(selection == filter ? 1 : 0)
                        .accessibilityHidden(true)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
            }

        }
        .padding(.vertical, 8)
        .frame(width: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .opacity(opacity)
        .task(id: pendingSelection)
        {

            guard pendingSelection != nil else
            {
                return
            }

            do
            {

                try await Task.sleep(for: .milliseconds(voiceOver ? 900 : 450))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16))
                {
                    opacity = 0
                }

                if !reduceMotion
                {
                    try await Task.sleep(for: .milliseconds(160))
                }

                dismiss()
            }
            catch
            {  /* A newer selection or outside dismissal cancels this dismissal. */

            }

        }

    }

}


///
/// Presents a personal collection through the shared Board interface
///
/// @section    Purpose
///     Reuse Board behavior while binding edits and archive actions to the collection
///
struct PersonalCollectionBoardView: View
{


    @Binding var collection:        PersonalCollection    /* Live collection shown by the shared Board view */
    @Binding var boardTargetListID: Int?                  /* Collection-local list requested from Saved     */
    @Binding var boardTargetCardID: Int?                  /* Collection-local card requested from Saved     */
    let retainedLists:              [KanbanList]          /* Other lists retaining possible attachments     */
    let availablePersonalLists:     [PersonalCollection]  /* Personal Lists offered as Note destinations    */
    let onArchive:                  () throws -> Void     /* Persist archival of this collection            */
    let onDelete:                   () throws -> Void     /* Persist permanent removal of this collection   */
    let onCommitDeletion:
    (PersonalCollection) throws -> Void /* Save nested deletion against current shared state        */
    let onCreateNote:
    (UUID, QuickCaptureSubmission, Date) throws ->
    Void /* Checked creation callback for a destination List         */
    let onMoveNote:
    (KanbanCard, UUID, UUID) throws -> KanbanCard       /* Checked movement callback returning the relocated Note   */
    let onUpdateMovedNote:  (UUID, KanbanCard) -> Bool  /* Persists edits in the Note's current collection          */
    let onArchiveMovedNote: (UUID, KanbanCard) -> Bool  /* Archives the Note in its current collection              */
    let onDeleteMovedNote:  (UUID, KanbanCard) -> Bool  /* Permanently removes the Note from its current collection */
    let onToggleMovedNoteBookmark:
    (UUID, Int, Bool) -> Bool                        /* Persists the Note's collection-local saved state     */
    let registerNewNote: ((() -> Void)?) -> Void     /* Registers or clears the presented List's Note action */
    @Environment(\.dismiss) private var dismiss      /* Close the collection board                           */
    @State private var showsNewNoteComposer = false  /* Presentation state of the List-scoped Note draft     */

    ///
    /// @fcn        PersonalCollectionBoardView.body
    /// @brief      Adapt a personal collection to the shared Board surface
    /// @details    Supplies active/archive list bindings, collection bookmarks, and retained attachment
    ///             references. Full boards allow list creation; single-list collections fill the
    ///             Standard viewport while Overview retains the shared compact column width
    ///
    /// @return     (some View) collection-backed Board with database activity feedback
    /// @post       Successful archive dismisses after onArchive returns; failure reports an error
    ///             and keeps the Board open
    ///
    var body: some View
    {  /* Collection Board wired to canonical persistence callbacks */

        ContentView(
            lists: $collection.lists.activeLists,
            archivedLists: $collection.lists.archivedLists,
            boardTargetListID: $boardTargetListID,
            boardTargetCardID: $boardTargetCardID,
            savedCardIDs: $collection.savedCardIDs,
            boardTitle: collection.title,
            boardSubtitle: "",
            allowsAddingLists: collection.kind == .board,
            fillsAvailableListWidth: collection.kind == .list,
            onClose:
            {
                dismiss()
            },
            onArchiveBoard:
            {

                do
                {


                    try onArchive()
                    dismiss()
                }
                catch
                {

                    DatabaseActivity.shared.report(
                                                            "Could not archive the board: \(error.localizedDescription) The board has not been removed.")
                }

            },
            onDeleteBoard:
            {

                do
                {


                    try onDelete()
                    dismiss()
                }
                catch
                {

                    DatabaseActivity.shared.report(
                                                            "Could not delete the collection: \(error.localizedDescription) It has been retained.")
                }

            },
            deleteBoardTitle: "Delete \(collection.kind.rawValue)",
            onCommitDeletion:
            {
                lists, bookmarks in
                var updated = collection /* Collection snapshot receiving Board removals */
                updated.lists = lists
                updated.savedCardIDs = bookmarks
                try onCommitDeletion(updated)
            },
            onListsChanged:
            {
                updatedLists in
                if collection.kind == .list, let list = updatedLists.first
                {

                    collection.title = list.title
                }

            },
            retainedAttachmentLists:
            {
                retainedLists
            },
            personalCollectionID: collection.id,
            availablePersonalLists: availablePersonalLists,
            onMoveNoteToPersonalList:
            {
                note, sourceID, destinationID in
                do
                {

                    return try onMoveNote(note, sourceID, destinationID)
                }
                catch
                {

                    DatabaseActivity.shared.report(
                                                            "Could not move the Note: \(error.localizedDescription) Its content remains in the current List."
                    )
                    return nil
                }

            },
            onUpdateMovedNote: onUpdateMovedNote,
            onArchiveMovedNote: onArchiveMovedNote,
            onDeleteMovedNote: onDeleteMovedNote,
            onToggleMovedNoteBookmark: onToggleMovedNoteBookmark,
            boardAppearance: $collection.boardAppearance
        )
        .databaseActivityOverlay()
        .onAppear
        {

            if collection.kind == .list
            {


                registerNewNote
                {
                    showsNewNoteComposer = true
                }

            }

        }
        .onDisappear
        {

            registerNewNote(nil)
        }
        .sheet(isPresented: $showsNewNoteComposer)
        {

            NewPersonalNoteComposer(
                initialCollectionID: collection.id,
                availablePersonalLists: availablePersonalLists,
                onSave: onCreateNote
            )
            .databaseActivityOverlay()
        }

    }

}


///
/// Edits a local personal collection using an isolated draft
///
/// @section    Purpose
///     Apply collection naming and appearance only after explicit Save
///
struct PersonalCollectionSettingsView: View
{


    let isNew:                Bool                          /* Whether this form creates a new collection */
    let onSave:               (PersonalCollection) -> Void  /* Submit the complete collection draft       */
    @State private var draft: PersonalCollection            /* Isolated editable collection copy          */
    @Environment(\.dismiss) private var dismiss             /* Close the settings sheet                   */


    ///
    /// @fcn        PersonalCollectionSettingsView.init(collection:isNew:onSave:)
    /// @brief      Seed an isolated personal-collection settings draft
    /// @details    Copies the supplied value into local State so Cancel does not submit partial edits
    ///
    /// @param[in]  collection  Existing collection or newly created starter draft
    /// @param[in]  isNew       Whether to display a creation heading
    /// @param[in]  onSave      Callback receiving the complete renamed draft
    /// @return     (PersonalCollectionSettingsView) initialized settings form
    /// @post       The source collection remains unchanged until onSave is invoked
    ///
    init(collection: PersonalCollection, isNew: Bool, onSave: @escaping (PersonalCollection) -> Void)
    {


        _draft = State(initialValue: collection)
        self.isNew = isNew
        self.onSave = onSave
    }


    ///
    /// @fcn        PersonalCollectionSettingsView.trimmedTitle
    /// @brief      Normalize the collection name for validation and save
    /// @details    Trims outer whitespace/newlines without mutating the draft text
    ///
    /// @return     (String) normalized collection title
    /// @post       The draft remains unchanged
    ///
    private var trimmedTitle: String
    {

        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }  /* Validated collection name without surrounding whitespace */


    ///
    /// @fcn        PersonalCollectionSettingsView.save()
    /// @brief      Submit the normalized collection draft and close settings
    /// @details    Uses the model's rename helper to keep single-list collection naming consistent,
    ///             then calls the parent submission callback before dismissal
    ///
    /// @return     (Void) updates the draft, submits it, and dismisses the form
    ///
    /// @pre        The form has verified trimmedTitle is nonempty
    /// @post       Persistence and save-error reporting remain the parent's responsibility
    ///
    private func save()
    {


        draft.rename(to: trimmedTitle)
        onSave(draft)
        dismiss()
    }


    ///
    /// @fcn        PersonalCollectionSettingsView.body
    /// @brief      Present collection name, icon, and color editing
    /// @details    Displays a fixed collection type and distinguishes create/edit headings;
    ///             whitespace-only names disable Save, while Cancel dismisses without submission
    ///
    /// @return     (some View) navigation form with draft-bound settings and toolbar actions
    /// @post       Changes remain local until Save invokes the parent callback
    ///
    var body: some View
    {  /* Collection name, kind, icon, and color form */

        NavigationStack
        {

            Form
            {

                Section
                {

                    TextField("Name", text: $draft.title).textInputAutocapitalization(.sentences)
                    TextField(
                                                            "Description (optional)",
                                                            text: Binding(
                                                                get:
                                                                {
                                                                    draft.collectionDescription ?? ""
                                                                },
                                                                set:
                                                                {
                                                                    draft.collectionDescription = $0
                                                                }
                                                            ), axis: .vertical
                    ).textInputAutocapitalization(.sentences)
                    .lineLimit(1 ... 3)
                    LabeledContent("Type", value: draft.kind.rawValue)
                    Picker("Icon", selection: $draft.icon)
                    {

                        ForEach(PersonalCollectionIcon.allCases, id: \.self)
                        {
                            icon in
                            Label(icon.title, systemImage: icon.rawValue).tag(icon)
                        }

                    }

                    .pickerStyle(.menu)
                    if draft.kind == .list, let list = draft.lists.first, !list.hasFixedHeaderIcon
                    {

                        Toggle(
                                                                        "Show icon in title bar",
                                                                        isOn: Binding(
                                                                            get:
                                                                            {
                                                                                draft.lists[0].showsIconInHeader
                                                                            },
                                                                            set:
                                                                            {
                                                                                value in
                                                                                var appearance = draft.lists[0].appearance ?? ItemAppearance()
                                                                                appearance.showsIconInHeader = value
                                                                                draft.lists[0].appearance = appearance
                                                                            }
                                                                        ))
                    }

                    Picker("Color", selection: $draft.color)
                    {

                        ForEach(
                            [
                                ("Teal", ProfileColor.teal), ("Blue", .blue), ("Green", .green),
                                ("Orange", .orange), ("Coral", .coral), ("Graphite", .graphite)
                            ], id: \.0
                        )
                        {
                            name, color in
                            HStack
                            {

                                Circle().fill(color.color).frame(width: 16, height: 16)
                                Text(name)
                            }

                            .tag(color)
                        }

                    }

                    .pickerStyle(.menu)
                }


                if draft.kind == .list, !draft.lists.isEmpty
                {

                    Section("List background")
                    {

                        ListSurfaceOpacityPicker(
                            title: draft.title,
                            tint: draft.lists[0].appearance?.listBackground ?? draft.boardAppearance?.listBackground
                            ?? .neutral,
                            opacity: Binding(
                                get:
                                {
                                    draft.lists[0].appearance?.resolvedListBackgroundOpacity ?? 1
                                },
                                set:
                                {
                                    value in
                                    var appearance = draft.lists[0].appearance ?? ItemAppearance()
                                    appearance.listBackgroundOpacity = value
                                    draft.lists[0].appearance = appearance
                                }
                            ))
                        Text(
                                                                        "Only the surface behind the List's cards fades. Save applies this choice; Cancel keeps the current background."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }


                if draft.kind == .list, !draft.lists.isEmpty
                {

                    Section("Icon color")
                    {

                        ListIconColorPicker(
                            selection: Binding(
                                get:
                                {
                                    draft.lists[0].appearance?.iconColor
                                },
                                set:
                                {
                                    value in
                                    var appearance = draft.lists[0].appearance ?? ItemAppearance()
                                    appearance.iconColor = value
                                    draft.lists[0].appearance = appearance
                                }
                            ), fixedColor: KanbanList.fixedIconColor(for: draft.lists[0].title))
                    }

                }


                if draft.kind == .list, !draft.lists.isEmpty
                {

                    Section("View as")
                    {

                        Picker(
                                                                        "List layout",
                                                                        selection: Binding(
                                                                            get:
                                                                            {
                                                                                draft.lists[0].singleListViewMode
                                                                            },
                                                                            set:
                                                                            {
                                                                                draft.lists[0].setSingleListViewMode($0)
                                                                            }
                                                                        )
                        )
                        {

                            ForEach(SingleListViewMode.allCases)
                            {
                                Text($0.title).tag($0)
                            }

                        }

                        Text("Changes only this List's presentation. Cards, Notes and their contents stay the same.")
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }


                Section("New item defaults")
                {

                    ForEach($draft.lists)
                    {
                        $list in
                        Picker(list.title, selection: $list.newItemPresentation)
                        {

                            ForEach(ItemPresentation.allCases)
                            {
                                presentation in
                                Text(presentation.title).tag(presentation)
                            }

                        }

                    }


                    Text("Applies only to new items. Existing items keep their display format.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }


                if isNew && draft.cardCount > 0
                {


                    Section("Cards included")
                    {

                        Text("These example cards will be added only when you save this new personal list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        ForEach(draft.lists.flatMap(\.cards))
                        {
                            card in
                            if let cover = card.coverAttachment
                            {  /* Featured attachment displayed above the card preview */


                                CardCoverPreview(attachment: cover, height: 96)
                            }


                            Text(card.word)
                        }

                    }

                }

            }

            .navigationTitle(isNew ? "New \(draft.kind.rawValue)" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .topBarLeading)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

                ToolbarItem(placement: .topBarTrailing)
                {

                    Button("Save", action: save).disabled(trimmedTitle.isEmpty)
                }

            }

        }

        .presentationDetents([.medium, .large])
    }

}
