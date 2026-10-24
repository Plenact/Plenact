// --------------------------------------------------------------------------------------------------
// @file       LibraryView.swift
// @brief      Plans directory and personal collection workflows
// @details    Coordinates browse filters, collection drafts, templates, examples, labels, and
//             checked updates to retained Library owners.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Presents the Library and its collection editors
///
/// @section    Purpose
///     Coordinates filtered browsing, examples, templates, labels, and checked collection changes
///     while keeping draft creation separate from saved owners.
///
struct BoardListsView: View
{


    @State private var openedHelpArticle: PlenactHelpArticle?
    @Environment(\.planningCalendarAccess) private var planningAccess
    @State private var browsedLabel: KanbanLabel?
    @State private var browseLabelLibrary = LabelLibraryStore.load()
    @Environment(\.workspaceBottomBarHeight) private var bottomBarHeight

    @State private var libraryEditMode: EditMode = .inactive

    @State private var showsSharedSearch = false

    let retainedWeekLists: [KanbanList] /* Week references protect shared attachments */

    @Binding var collections: [PersonalCollection] /* Shared device-local collections             */
    var newListRequest = 0
    var toolbarCollectionRequest: Binding<PersonalCollectionKind?>? = nil
    let registerListNewNote:      ((() -> Void)?) -> Void  /* Registers the directory's scoped Note action    */
    let onOpenSaved:              () -> Void               /* Select the existing canonical Saved destination */
    var onLoadExampleWeek:        (() -> Bool)? = nil
    var onUndoExampleWeek:        (() -> Bool)? = nil
    var onLoadExampleMonth:       (() -> Void)? = nil
    var onRestoreUserData:        (() -> Void)? = nil
    var hasUserDataBackup = false
    var savedPersonalCardTarget:        PersonalSavedCardTarget? = nil /* Saved bookmark waiting for Library navigation  */
    var onClearSavedPersonalCardTarget: () -> Void =
    {

    }  /* Acknowledge a handled or invalid Saved request */

    @State private var archivingCollection:         PersonalCollection? /* Collection awaiting archive confirmation       */
    @FocusState private var isLibrarySearchFocused: Bool
    @State private var showsRecentShelf = false
    @AppStorage("Plenact.LibraryImportant.v1") private var importantData = Data()
    @State private var recentItems = LibraryRecentStore.load()
    @AppStorage(LibraryRecentStore.key) private var libraryRecentData = Data()
    @AppStorage("Plenact.LibraryShowsCollectionPreviews") private var showsCollectionPreviews = false
    @AppStorage("Plenact.LibraryScrollsCollectionPreviews") private var scrollsCollectionPreviews = false
    @State private var showsCollectionFilter = false
    @State var browseFilter:                                      LibraryBrowseFilter = .all /* Initial scope may be supplied by Library navigation */
    @ScaledMetric(relativeTo: .body) private var plateTileHeight: CGFloat = 110
    @State var searchText = "" /* Directory search query                     */
    @State private var importanceExampleDrafts: Set<UUID> = []
    @State private var editingCollection:       PersonalCollection?  /* Collection draft being edited              */
    @State private var openedCollection:        PersonalCollection?  /* Collection board presented full-screen     */
    @State private var boardTargetListID:       Int?                 /* Exact collection list requested from Saved */
    @State private var boardTargetCardID:       Int?                 /* Exact collection card requested from Saved */
    @State private var deletingCollection:      PersonalCollection?  /* Collection awaiting delete confirmation    */
    @State private var createdNoteDestination:  PersonalCollection?
    @State private var newNoteDraftDestination:
    PersonalCollection?                                 /* Personal List selected for the presented Note draft */
    @State private var mostRecentlyOpenedListID: UUID?  /* Last opened List used as the next Note destination  */
    @State private var libraryQuickTemplate:     QuickCaptureTemplate?
    @State private var weekExampleAction:        String?
    @State private var libraryStarterError:      String?
    @State private var examplePreview:           LibraryExamplePreview?
    @State private var daySectionExampleToApply: PlanningRoutineTemplate?


    ///
    /// @fcn        BoardListsView.filteredCollections
    /// @brief      Select active personal collections matching the directory query
    /// @details    Delegates collection matching to the model and preserves collection order
    ///
    /// @return     ([PersonalCollection]) visible active collections
    /// @post       Archived collections remain stored but are not returned
    ///
    @ViewBuilder
    private var libraryLabelRows: some View
    {

        let owners = WorkspaceBrowseIndex.owners(document: planningAccess?.document, library: collections)
        let usages = WorkspaceBrowseIndex.labels(in: owners, catalog: browseLabelLibrary).filter
        {

            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || $0.label.name.localizedStandardContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if usages.isEmpty
        {

            VStack(alignment: .leading, spacing: 8)
            {

                Label("No matching labels", systemImage: "tag").font(.headline)
                Text("Labels assigned to active cards and notes appear here.").font(.subheadline).foregroundStyle(
                    .secondary)
            } .padding(.vertical, 12)
        }

        ForEach(usages)
        {
            usage in
            Button
            {

                browsedLabel = usage.label
            }
            label:
            {

                HStack(spacing: 12)
                {

                    Image(systemName: "tag").font(.title3).foregroundStyle(usage.label.color.color)
                    .frame(width: 40, height: 40)
                    .background(usage.label.color.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    Text(usage.label.name).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Text("\(usage.matches.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color(.secondarySystemGroupedBackground))
            .accessibilityLabel(usage.label.name + ", \(usage.matches.count) active items")
        }

    }


    private var filteredCollections: [PersonalCollection]
    {  /* Active directory entries matching the search */

        let owners = Set(librarySearchResults.compactMap(\.ownerID))
        return collections.filter
        {
            browseFilter.includes($0) && ($0.matches(searchText) || owners.contains($0.id))
        }

    }


    private var librarySearchResults: [TodaySearchResult]
    {

        LibrarySearchIndex.results(
            query: searchText, collections: collections.filter
            {
                browseFilter.includes($0)
            },
            labels: LabelLibraryStore.load())
    }


    ///
    /// @fcn        BoardListsView.openLibrarySearchResult
    /// @brief      Open a Library match in its owning collection
    /// @details    Uses the result's owner and card identity to select the existing content rather than creating a
    ///             duplicate.
    ///
    /// @param[in]  result  Resolved search or Activity match to render or open
    ///
    /// @return     (Void) no return value
    ///
    private func openLibrarySearchResult(_ result: TodaySearchResult)
    {

        guard let collection = collections.first(where:
            {
                $0.id == result.ownerID && $0.isActive
            }) else
        {
            return
        }

        isLibrarySearchFocused = false
        boardTargetListID = result.listID
        boardTargetCardID = result.cardID
        openedCollection = collection
    }


    ///
    /// @fcn        BoardListsView.librarySearchRow
    /// @brief      Build a navigable Library search-result preview
    /// @details    Uses the result's card content and location to distinguish matching items across owners.
    ///
    /// @param[in]  result  Resolved search or Activity match to render or open
    ///
    /// @return     (some View) a navigable library search-result preview
    ///
    private func librarySearchRow(_ result: TodaySearchResult) -> some View
    {

        let card = collections.first
        {
            $0.id == result.ownerID
        }?.lists.first
        {
            $0.id == result.listID
        }?.cards.first
        {

            $0.id == result.cardID
        }

        return Button
        {

            openLibrarySearchResult(result)
        }
        label:
        {

            HStack(spacing: 12)
            {

                Image(systemName: card?.presentation == .note ? "note.text" : "rectangle")
                .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4)
                {

                    Text(result.cardTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(
                        result.ownerTitle == result.listTitle
                        ? result.listTitle : (result.ownerTitle ?? "Plans") + " · " + result.listTitle
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            } .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        } .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityHint("Opens this item in your Plans")
    }


    ///
    /// @fcn        BoardListsView.collectionEntry(_:)
    /// @brief      Build one personal-collection row and its existing lifecycle actions
    /// @details    Keeps the Library directory view builder small as navigation callbacks grow
    /// @param[in]  collection  Active directory collection
    /// @return     (some View) collection entry with edit/archive/delete affordances
    ///
    private func collectionEntry(_ collection: PersonalCollection) -> some View
    {


        let collectionSubtitle =
        collection.kind == .board /* Kind-specific directory row summary */
        ? "Board · \(collection.lists.filter { !$0.isArchived } .count) lists"
        : "List"

        return HStack(spacing: 8)
        {

            Button
            {

                if collection.kind == .list
                {

                    mostRecentlyOpenedListID = collection.id
                }

                openedCollection = collection
            }
            label:
            {

                row(
                    title: collection.title, subtitle: collectionSubtitle,
                    icon: collection.icon.rawValue,
                    color: (collection.kind == .list
                        ? collection.lists.first?.resolvedIconColor(collectionColor: collection.color)?.color : nil)
                    ?? collection.libraryIdentityColor, count: collection.cardCount,
                    preview: collectionPreview(collection))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this personal collection")

            Menu
            {

                Button("Edit", systemImage: "pencil")
                {
                    editingCollection = collection
                }

                Button("Archive", systemImage: "archivebox")
                {
                    archivingCollection = collection
                }

                Button("Delete \(collection.kind.rawValue)", systemImage: "trash", role: .destructive)
                {

                    deletingCollection = collection
                }

            }
            label:
            {

                WorkspaceHeaderIcon(systemName: "ellipsis")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(collection.title) actions")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay
        {

            RoundedRectangle(cornerRadius: 20).fill(collection.libraryIdentityColor.opacity(0.12)).allowsHitTesting(
                false)
        }
        .overlay
        {

            RoundedRectangle(cornerRadius: 20).strokeBorder(collection.libraryIdentityColor.opacity(0.3), lineWidth: 1)
            .allowsHitTesting(false)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .accessibilityActions
        {

            Button("Edit Collection")
            {
                editingCollection = collection
            }

            Button("Archive Collection")
            {
                archivingCollection = collection
            }

            Button("Delete \(collection.kind.rawValue)")
            {
                deletingCollection = collection
            }

        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false)
        {

            Button("Delete", role: .destructive)
            {
                deletingCollection = collection
            }

            Button("Archive")
            {
                archivingCollection = collection
            }

            Button("Edit")
            {
                editingCollection = collection
            }
            .tint(.blue)
        }

    }


    private var directoryNoteDestination: PersonalCollection?
    {  /* Active List resolved for directory-level Note creation */


        Self.resolveNoteDestination(
            mostRecentlyOpenedListID: mostRecentlyOpenedListID,
            collections: collections,
            visibleCollections: filteredCollections
        )
    }


    ///
    /// @fcn        BoardListsView.resolveNoteDestination(mostRecentlyOpenedListID:collections:visibleCollections:)
    /// @brief      Select the active personal List for directory-level Note creation
    /// @details    Prefer the most recently opened active List; otherwise use the first visible List
    ///
    /// @param[in]  mostRecentlyOpenedListID  Last opened personal List identity, if still active
    /// @param[in]  collections               Complete local collection snapshot
    /// @param[in]  visibleCollections        Active collections currently shown by Library search
    ///
    /// @return     (PersonalCollection?) destination List, or nil when none is available
    ///
    static func resolveNoteDestination(
        mostRecentlyOpenedListID: UUID?,
        collections: [PersonalCollection],
        visibleCollections: [PersonalCollection]
    ) -> PersonalCollection?
    {


        if let mostRecentlyOpenedListID, /* Remembered personal List identity                 */
        let recentList = collections.first(where:
            {  /* Remembered List still available for Note creation */

                $0.id == mostRecentlyOpenedListID && $0.kind == .list && $0.isActive
            })
        {

            return recentList
        }


        return visibleCollections.first(where:
            {
                $0.kind == .list && $0.isActive
            })
    }


    ///
    /// @fcn        BoardListsView.openDirectoryNewNote()
    /// @brief      Start a Library-level Note draft in the resolved destination List
    /// @details    Uses the current directory destination and reports an actionable error if no
    ///             active personal List is available
    ///
    /// @return     (Void) presents the draft for the resolved List or reports why it cannot open
    ///
    private func openDirectoryNewNote()
    {


        guard let destination = directoryNoteDestination else
        {  /* Available personal List for the new draft */


            DatabaseActivity.shared.report("Create a personal List before adding a Note from Plans.")

            return
        }


        newNoteDraftDestination = destination
    }


    ///
    /// @fcn        BoardListsView.registerDirectoryNewNote()
    /// @brief      Register the Library-level action for creating a Note
    /// @details    Routes the directory action through the shared List Note registration helper
    ///             so its presentation behavior matches other List-scoped entry points
    ///
    /// @return     (Void) registers a callback that opens a directory Note draft
    ///
    private func registerDirectoryNewNote()
    {


        registerListNewNote
        {
            openDirectoryNewNote()
        }

    }


    ///
    /// @fcn        BoardListsView.prepareImportanceExample(_:)
    /// @brief      Stage a chosen example without changing live importance
    /// @details    Remembers only the draft owner. Demonstration levels are installed after Save,
    ///             so previewing or cancelling an example cannot change existing personal marks.
    ///
    /// @param[in]  collection  Newly generated Library example or template
    ///
    /// @return     (Void) presents the collection draft
    ///
    private func prepareImportanceExample(_ collection: PersonalCollection)
    {

        importanceExampleDrafts.insert(collection.id)
        editingCollection = collection
    }


    ///
    /// @fcn        BoardListsView.saveCollection(_:)
    /// @brief      Insert or replace a personal collection by identity
    /// @details    Updates the shared binding; app-root observation owns persistence and error
    ///             reporting
    ///
    /// @param[in]  collection  Complete collection submitted by its settings form
    ///
    /// @return     (Void) replaces the matching entry or appends a new one
    ///
    /// @post       Other collections and the Week snapshot remain unchanged
    ///
    private func saveCollection(_ collection: PersonalCollection)
    {


        if let index = collections.firstIndex(where:
            {  /* Position of the collection submitted by its form */


                $0.id == collection.id
            })
        {

            collections[index] = collection
        }
        else
        {


            collections.append(collection)
            if importanceExampleDrafts.remove(collection.id) != nil
            {

                importantData = LibraryImportanceSelection.demoData(
                    in: [collection], preserving: importantData, includesAllExamples: true)
            }

        }

    }


    ///
    /// @fcn        BoardListsView.createNote(in:capture:createdAt:)
    /// @brief      Save a full capture into an active personal List
    /// @details    Resolves the current collection, forwards writing, presentation, attachments,
    ///             actions, and scheduling, and saves the complete collection snapshot before
    ///             publication. Successful creation requests the new item's reveal.
    ///
    /// @param[in]  collectionID  Active personal List identity
    /// @param[in]  capture       Complete destination-scoped creation submission with writing, media,
    ///             and scheduling
    /// @param[in]  createdAt     Creation time retained from the unsaved draft
    ///
    /// @return     (Void) saves and publishes the requested Card or Note without changing unrelated
    ///             owners
    /// @throws     CocoaError for unavailable destinations; encoding error for failed persistence
    ///
    private func createNote(in collectionID: UUID, capture: QuickCaptureSubmission, createdAt: Date) throws
    {


        guard
        let collectionIndex = collections.firstIndex(where:
            {  /* Active personal List receiving the new Note */


                $0.id == collectionID && $0.kind == .list && $0.isActive
            })
        else
        {


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        var updated = collections[collectionIndex] /* Destination collection receiving the new Note */

        try updated.addNote(
            title: capture.title, body: capture.body, createdAt: createdAt,
            presentation: capture.presentation, subtitle: capture.subtitle, attachments: capture.attachments,
            actions: capture.actions, schedule: capture.schedule,
            calendar: planningAccess?.document.calendar ?? .current)

        var snapshot = collections /* Collection snapshot saved before publishing the new Note */

        snapshot[collectionIndex] = updated
        try PersonalCollectionStore.saveChecked(snapshot)
        collections = snapshot
        if let list = updated.lists.first(where:
            {
                !$0.isArchived
            }), let card = list.cards.last
        {

            CreatedContentReveal.shared.request(listID: list.id, card: card)
            if newNoteDraftDestination != nil
            {

                createdNoteDestination = updated
            }
            else if openedCollection?.id != updated.id
            {

                openedCollection = updated
            }

        }

    }


    ///
    /// @fcn        BoardListsView.moveNote(_:from:to:)
    /// @brief      Move a Note between personal Lists and persist the resulting collection snapshot
    /// @details    Delegates identity and collision handling to the collection movement operation,
    ///             then publishes the new snapshot only after checked persistence succeeds
    ///
    /// @param[in]  noteID         Identity of the Note being moved
    /// @param[in]  sourceID       Identity of the Note's current collection
    /// @param[in]  destinationID  Identity of the target personal List
    ///
    /// @return     (KanbanCard) moved Note with its resulting destination-local identity
    ///
    /// @throws     Collection movement or persistence errors without publishing an unsaved snapshot
    ///
    private func moveNote(_ noteID: Int, from sourceID: UUID, to destinationID: UUID) throws -> KanbanCard
    {


        var snapshot = collections /* Collection snapshot carrying both sides of the Note move */
        let moved =
        try PersonalCollectionNoteMovement.move( /* Note returned with its destination-local identity        */
            noteID: noteID, from: sourceID, to: destinationID, in: &snapshot
        )
        try PersonalCollectionStore.saveChecked(snapshot)
        collections = snapshot
        if sourceID != destinationID, let destination = snapshot.first(where:
            {
                $0.id == destinationID
            })
        {

            TransferConfirmationPresenter.shared.show(
                TransferConfirmation(title: moved.word, destination: destination.title))
        }


        return moved
    }


    ///
    /// @fcn        BoardListsView.persistMovedNoteCollection(_:failureMessage:)
    /// @brief      Persist and publish a changed personal collection
    /// @details    Replaces the matching collection in a temporary snapshot and updates the shared
    ///             collection binding only after checked storage succeeds
    ///
    /// @param[in]  updated         Collection value to persist
    /// @param[in]  failureMessage  Operation-specific message prefix for reported errors
    ///
    /// @return     (Bool) true when storage and publication succeed; otherwise false
    ///
    /// @post       A failed save leaves the published collection snapshot unchanged
    ///
    private func persistMovedNoteCollection(
        _ updated: PersonalCollection,
        failureMessage: String
    ) -> Bool
    {


        guard let index = collections.firstIndex(where:
            {
                $0.id == updated.id
            })
        else
        {  /* Existing collection to replace after checked persistence */


            DatabaseActivity.shared.report("\(failureMessage) The collection is no longer available.")
            return false
        }


        var snapshot = collections /* Collection snapshot saved before publishing moved-Note changes */

        snapshot[index] = updated

        do
        {


            try PersonalCollectionStore.saveChecked(snapshot)
            collections = snapshot
            return true
        }
        catch
        {


            DatabaseActivity.shared.report("\(failureMessage) \(error.localizedDescription)")
            return false
        }

    }


    ///
    /// @fcn        BoardListsView.updateMovedNote(_:in:)
    /// @brief      Replace an existing Note in its active personal List
    /// @details    Resolves the collection and non-archived record by stable identity, then routes
    ///             the updated value through checked collection persistence
    ///
    /// @param[in]  note          Edited Note value to store
    /// @param[in]  collectionID  Identity of the Note's owning collection
    ///
    /// @return     (Bool) true when the Note update is persisted; otherwise false
    ///
    /// @post       Missing or archived records are not recreated
    ///
    private func updateMovedNote(_ note: KanbanCard, in collectionID: UUID) -> Bool
    {


        guard let index = collections.firstIndex(where:
            {
                $0.id == collectionID && $0.isActive
            })
        else
        {  /* Active collection owning the moved Note */


            DatabaseActivity.shared.report("Could not save the Note edit. Its destination List is unavailable.")
            return false
        }


        var updated = collections[index] /* Owning collection receiving the edited Note */

        guard
        let listIndex = updated.lists.firstIndex(where:
            {  /* Active column containing the moved Note */


                !$0.isArchived && $0.cards.contains(where:
                    {
                        $0.id == note.id && !$0.isSectionDivider
                    })
            }),
        let cardIndex = updated.lists[listIndex].cards.firstIndex(
            where:
            {  /* Position of the moved Note to replace */

                $0.id == note.id && !$0.isSectionDivider
            })
        else
        {


            DatabaseActivity.shared.report("Could not save the item edit. It is no longer in its destination List.")
            return false
        }


        guard updated.lists[listIndex].cards[cardIndex].acceptsContentUpdate(note) else
        {
            return false
        }

        updated.lists[listIndex].cards[cardIndex] = note
        return persistMovedNoteCollection(updated, failureMessage: "Could not save the Note edit.")
    }


    ///
    /// @fcn        BoardListsView.archiveMovedNote(_:in:)
    /// @brief      Archive an existing Note within its personal List
    /// @details    Resolves the active collection and non-archived containing List, marks the Note
    ///             archived, and persists the updated collection
    ///
    /// @param[in]  note          Note whose retained record should be archived
    /// @param[in]  collectionID  Identity of the Note's owning collection
    ///
    /// @return     (Bool) true when the archive state is persisted; otherwise false
    ///
    /// @post       The Note remains retained in the collection archive
    ///
    private func archiveMovedNote(_ note: KanbanCard, in collectionID: UUID) -> Bool
    {


        guard let index = collections.firstIndex(where:
            {
                $0.id == collectionID && $0.isActive
            })
        else
        {  /* Active collection owning the Note to archive */


            DatabaseActivity.shared.report("Could not archive the Note. Its destination List is unavailable.")
            return false
        }


        var updated = collections[index] /* Owning collection receiving the Note archive */

        guard
        let listIndex = updated.lists.firstIndex(where:
            {  /* Active column containing the Note to archive */


                !$0.isArchived && $0.cards.contains(where:
                    {
                        $0.id == note.id && !$0.isSectionDivider
                    })
            })
        else
        {


            DatabaseActivity.shared.report("Could not archive the item. It is no longer in its destination List.")
            return false
        }


        updated.lists[listIndex].archiveCard(id: note.id)
        return persistMovedNoteCollection(updated, failureMessage: "Could not archive the Note.")
    }


    ///
    /// @fcn        BoardListsView.deleteMovedNote(_:in:)
    /// @brief      Delete a Note from its personal List after checked persistence
    /// @details    Removes the matching record and bookmark, persists the collection, then removes
    ///             attachment files only when no retained Board references them
    ///
    /// @param[in]  note          Note whose record should be removed
    /// @param[in]  collectionID  Identity of the Note's owning collection
    ///
    /// @return     (Bool) true when deletion is persisted; otherwise false
    ///
    /// @post       Referenced attachment files are retained across all known local snapshots
    ///
    private func deleteMovedNote(_ note: KanbanCard, in collectionID: UUID) -> Bool
    {


        guard let index = collections.firstIndex(where:
            {
                $0.id == collectionID && $0.isActive
            })
        else
        {  /* Active collection owning the Note to delete */


            DatabaseActivity.shared.report("Could not delete the Note. Its destination List is unavailable.")
            return false
        }


        var updated = collections[index] /* Owning collection receiving the Note deletion */

        guard
        let listIndex = updated.lists.firstIndex(where:
            {  /* Active column containing the Note to delete */


                !$0.isArchived && $0.cards.contains(where:
                    {
                        $0.id == note.id && !$0.isSectionDivider
                    })
            })
        else
        {


            DatabaseActivity.shared.report("Could not delete the item. It is no longer in its destination List.")
            return false
        }


        updated.lists[listIndex].cards.removeAll
        {
            $0.id == note.id
        }

        updated.savedCardIDs.remove(note.id)
        guard persistMovedNoteCollection(updated, failureMessage: "Could not delete the Note.") else
        {


            return false
        }


        let retainedLists =
        collections.flatMap(\.lists) /* Retained lists considered before deleting Note media */
        + retainedWeekLists
        + (ExampleLoadUndoStore.load()?.lists ?? [])
        let retainedFileNames = Set(
            retainedLists.flatMap(\.allCards) /* Attachment filenames still referenced by retained records */
            .flatMap
            {
                $0.attachments ?? []
            }
            .flatMap(\.storedFileNames))
        CardAttachmentStore.removeUnreferencedFiles(keeping: retainedFileNames)

        return true
    }


    ///
    /// @fcn        BoardListsView.setMovedNoteBookmark(_:in:isSaved:)
    /// @brief      Set the saved state of a Note in its personal List
    /// @details    Confirms the Note still belongs to an active collection before changing its
    ///             bookmark, then persists the updated collection snapshot
    ///
    /// @param[in]  noteID        Identity of the Note to update
    /// @param[in]  collectionID  Identity of the Note's owning collection
    /// @param[in]  isSaved       True to bookmark the Note; false to remove its bookmark
    ///
    /// @return     (Bool) true when the bookmark update is persisted; otherwise false
    ///
    private func setMovedNoteBookmark(_ noteID: Int, in collectionID: UUID, isSaved: Bool) -> Bool
    {


        guard
        let index = collections.firstIndex(where:
            {
                $0.id == collectionID && $0.isActive
            }
        ), /* Active collection owning the Note bookmark */
        collections[index].lists.contains(where:
            {

                !$0.isArchived && $0.cards.contains(where:
                    {
                        $0.id == noteID && !$0.isSectionDivider
                    })
            })
        else
        {


            DatabaseActivity.shared.report("Could not update the item bookmark. The item is no longer available.")
            return false
        }


        var updated = collections[index] /* Owning collection receiving the bookmark change */

        if isSaved
        {


            updated.savedCardIDs.insert(noteID)
        }
        else
        {


            updated.savedCardIDs.remove(noteID)
        }


        return persistMovedNoteCollection(updated, failureMessage: "Could not update the Note bookmark.")
    }


    ///
    /// @fcn        BoardListsView.presentedCollectionBoard(_:)
    /// @brief      Wire a personal collection to its live directory records
    /// @details    Supplies retained-attachment protection, save-before-delete/note callbacks,
    ///             and the scoped bottom-toolbar Note action
    /// @param[in]  collection  Full-screen collection snapshot selected from the Library
    /// @return     (some View) collection Board wired to canonical collection persistence
    ///
    private func presentedCollectionBoard(_ collection: PersonalCollection) -> some View
    {


        let otherCollectionLists =
        collections /* Lists outside the presented collection protecting shared media */
        .filter
        {
            $0.id != collection.id
        }
        .flatMap(\.lists)
        let retainedLists =
        retainedWeekLists /* External and undo snapshots protecting referenced attachments */
        + otherCollectionLists
        + (ExampleLoadUndoStore.load()?.lists ?? [])
        let activePersonalLists = collections.filter
        {

            $0.kind == .list && $0.isActive
        }  /* Available Note destinations across the directory */


        return PersonalCollectionBoardView(
            collection: collectionBinding(for: collection),
            boardTargetListID: $boardTargetListID,
            boardTargetCardID: $boardTargetCardID,
            retainedLists: retainedLists,
            availablePersonalLists: activePersonalLists,
            onArchive:
            {

                collections = try PersonalCollectionStore.archiveCollection(id: collection.id, in: collections)
            },
            onDelete:
            {

                let updated = collections.filter
                {

                    $0.id != collection.id
                }  /* Directory snapshot excluding the deleted collection */

                try PersonalCollectionStore.saveChecked(updated)
                collections = updated
            },
            onCommitDeletion:
            {
                updated in
                guard let index = collections.firstIndex(where:
                    {
                        $0.id == updated.id
                    })
                else
                {  /* Position of the collection with confirmed removals */

                    throw CocoaError(.validationMissingMandatoryProperty)
                }

                var snapshot = collections /* Directory snapshot saved before publishing removals */
                snapshot[index] = updated
                try PersonalCollectionStore.saveChecked(snapshot)
                collections = snapshot
            },
            onCreateNote:
            {
                destinationID, capture, createdAt in
                try createNote(in: destinationID, capture: capture, createdAt: createdAt)
            },
            onMoveNote:
            {
                note, sourceID, destinationID in
                try moveNote(note.id, from: sourceID, to: destinationID)
            },
            onUpdateMovedNote:
            {
                id, note in
                updateMovedNote(note, in: id)
            },
            onArchiveMovedNote:
            {
                id, note in
                archiveMovedNote(note, in: id)
            },
            onDeleteMovedNote:
            {
                id, note in
                deleteMovedNote(note, in: id)
            },
            onToggleMovedNoteBookmark:
            {
                id, noteID, isSaved in
                setMovedNoteBookmark(noteID, in: id, isSaved: isSaved)
            },
            registerNewNote: registerListNewNote
        )
        .environment(
            \.libraryImportance,
            LibraryImportanceAccess(
                contains:
                {
                    cardID in
                    importantItems.contains(LibraryRecentItem(collectionID: collection.id, cardID: cardID))
                },
                set:
                {
                    cardID, marked in
                    importantData = LibraryImportanceSelection.setting(
                        cardID: cardID, collectionID: collection.id, marked: marked, data: importantData)
                },
                level:
                {

                    LibraryImportanceSelection.level(cardID: $0, collectionID: collection.id, data: importantData)
                },
                adjust:
                {
                    cardID, direction in
                    importantData = LibraryImportanceSelection.adjusting(
                        cardID: cardID, collectionID: collection.id, direction: direction, data: importantData)
                })
        )
        .environment(
            \.libraryItemOpened,
            {
                cardID in
                recentItems = LibraryRecentStore.remember(
                    LibraryRecentItem(collectionID: collection.id, cardID: cardID))
            })
    }


    ///
    /// @fcn        BoardListsView.collectionBinding(for:)
    /// @brief      Resolve a presented collection back to shared directory state
    /// @details    Getter finds the current entry or returns the supplied snapshot; setter replaces
    ///             an existing entry only and does not recreate removed collections
    ///
    /// @param[in]  collection  Presented snapshot providing identity and getter fallback
    ///
    /// @return     (Binding<PersonalCollection>) live getter/setter for the shared collection array
    ///
    /// @post       Constructing the binding does not modify or persist any collection
    ///
    private func collectionBinding(for collection: PersonalCollection) -> Binding<PersonalCollection>
    {


        Binding(
            get:
            {
                collections.first(where:
                    {
                        $0.id == collection.id
                    }) ?? collection
            },
            set:
            {
                updated in
                guard
                let index = collections.firstIndex(where:
                    {  /* Current position of the bound collection */


                        $0.id == updated.id
                    })
                else
                {


                    return
                }

                collections[index] = updated
            }
        )
    }


    ///
    /// @fcn        BoardListsView.row(title:subtitle:icon:color:count:)
    /// @brief      Render a consistent collection-directory row
    /// @details    Combines a collection accent, readable title/type, and an explicitly labeled
    ///             count; the caller supplies navigation or editing interaction
    ///
    /// @param[in]  title     Primary collection name
    /// @param[in]  subtitle  Supporting type or list-count text
    /// @param[in]  icon      SF Symbol name
    /// @param[in]  color     Icon tint and background accent
    /// @param[in]  count     Card count displayed at the trailing edge
    ///
    /// @param[in]  preview   Optional collection excerpt displayed beneath the directory row context
    ///
    /// @return     (some View) full-row hit-test content
    ///
    /// @post       Rendering does not change collection state
    ///
    private func row(title: String, subtitle: String, icon: String, color: Color, count: Int, preview: String = "")
    -> some View
    {


        LibraryCollectionRow(
            title: title, subtitle: subtitle, icon: icon, color: color, count: count, preview: preview,
            scrollsPreview: scrollsCollectionPreviews)
    }


    ///
    /// @fcn        BoardListsView.createMenu
    /// @brief      Offer blank and starter personal collections
    /// @details    New List, New Board, and named starters seed an editable collection draft
    ///             with the appropriate kind/icon; nothing is inserted until the form saves
    ///
    /// @return     (some View) accessible toolbar creation menu
    /// @post       Choosing an entry sets editingCollection without changing stored collections
    ///
    private var importantItems: [LibraryRecentItem]
    {

        (try? JSONDecoder().decode([LibraryRecentItem].self, from: importantData)) ?? []
    }

    private var plateItems: [LibraryPlateItem]
    {

        LibraryPlateSelection.items(in: collections, important: importantItems)
    }

    private var showsPlateShelf: Bool
    {

        browseFilter.browsesCollections && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && libraryEditMode != .active
    }


    private var plateSection: some View
    {

        VStack(alignment: .leading, spacing: 10)
        {

            Text("Coming Soon")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .accessibilityAddTraits(.isHeader)
            if plateItems.isEmpty
            {

                Text(
                                                "Nothing urgent right now. Mark an item important from its menu or add a due date to bring it here."
                )
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 28)
            }
            else
            {

                ScrollView(.horizontal, showsIndicators: false)
                {

                    HStack(alignment: .top, spacing: 10)
                    {

                        ForEach(plateItems)
                        {
                            item in
                            Button
                            {

                                boardTargetListID = item.list.id
                                boardTargetCardID = item.card.id
                                openedCollection = item.collection
                            }
                            label:
                            {

                                LibraryPlateTile(item: item)
                                .frame(height: plateTileHeight)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this item directly")
                        }

                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 4)
                }
                .contentMargins(.all, 0, for: .scrollContent)
                .frame(height: plateTileHeight + 8)
            }

        }
        .padding(.top, 10)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    ///
    /// @fcn        BoardListsView.collectionPreview
    /// @brief      Build a short text preview of a collection
    /// @details    Extracts suitable list or card content for the Library row without altering the underlying
    ///             collection.
    ///
    /// @param[in]  collection  Personal collection supplying the owner context
    ///
    /// @return     (String) brief textual content preview for the Library collection row
    ///
    private func collectionPreview(_ collection: PersonalCollection) -> String
    {

        showsCollectionPreviews ? collection.contentPreview : ""
    }


    private var availableRecents: [(LibraryRecentItem, PersonalCollection, KanbanList, KanbanCard)]
    {

        recentItems.compactMap
        {
            item in
            guard
            let collection = collections.first(where:
                {
                    $0.id == item.collectionID && browseFilter.includes($0)
                }),
            let list = collection.lists.first(where:
                {

                    !$0.isArchived && $0.cards.contains
                    {
                        $0.id == item.cardID && !$0.isSectionDivider
                    }

                }),
            let card = list.cards.first(where:
                {
                    $0.id == item.cardID
                })
            else
            {
                return nil
            }

            return (item, collection, list, card)
        }

    }


    private var recentShelf: some View
    {

        ScrollView(.horizontal, showsIndicators: false)
        {

            HStack(spacing: 12)
            {

                ForEach(availableRecents, id: \.0.id)
                {
                    item, collection, list, card in
                    Button
                    {

                        boardTargetListID = list.id
                        boardTargetCardID = card.id
                        openedCollection = collection
                    }
                    label:
                    {

                        VStack(alignment: .leading, spacing: 10)
                        {

                            Text(card.word).font(.headline).foregroundStyle(.primary).lineLimit(2)
                            Text(
                                card.subtitle.isEmpty
                                ? PlanRichText.plain(card.descriptionOverride ?? "") : card.subtitle
                            )
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Spacer(minLength: 0)
                            Text(collection.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(width: 148, height: 132, alignment: .topLeading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay
                        {

                            RoundedRectangle(cornerRadius: 16).strokeBorder(
                                collection.libraryIdentityColor.opacity(0.4), lineWidth: 1)
                        }

                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this item directly")
                }

            }
            .padding(.vertical, 4)
        }

    }


    private var collectionFilterMenu: some View
    {

        Button
        {

            showsCollectionFilter = true
        }
        label:
        {

            Image(systemName: browseFilter.symbol)
            .font(.system(size: 22.5, weight: .medium))
            .foregroundStyle(Color(red: 177.0 / 255, green: 143.0 / 255, blue: 112.0 / 255))
            .padding(5)
            .frame(width: 32, height: 44)
            .contentShape(Rectangle())
        }
        .popover(isPresented: $showsCollectionFilter, arrowEdge: .top)
        {

            CollectionFilterPopover(selection: browseFilter)
            {
                filter in
                browseFilter = filter
                libraryEditMode = .inactive
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel("Filter collections")
        .accessibilityValue(browseFilter.rawValue)
        .accessibilityHint("Choose All, Lists, Boards, Labels, Templates, Examples, or Help. Your search text is kept.")
        .accessibilityIdentifier("library.collectionFilter")
    }


    private var libraryHeader: some View
    {

        VStack(spacing: 12)
        {

            HStack(spacing: 0)
            {

                HStack(spacing: 6)
                {

                    collectionFilterMenu
                    Text("Library").font(.largeTitle.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button
                {

                    showsSharedSearch = true
                }
                label:
                {

                    WorkspaceHeaderIcon(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search Plenact")
                .accessibilityIdentifier("library.openSearch")
                Menu
                {

                    Button(
                        libraryEditMode == .active ? "Done reordering collections" : "Reorder collections",
                        systemImage: libraryEditMode == .active ? "checkmark" : "arrow.up.arrow.down"
                    )
                    {

                        withAnimation
                        {
                            libraryEditMode = libraryEditMode == .active ? .inactive : .active
                        }

                    }
                    .disabled(
                        browseFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Toggle("Show collection previews", isOn: $showsCollectionPreviews)
                    Toggle("Scroll long previews", isOn: $scrollsCollectionPreviews)
                    .disabled(!showsCollectionPreviews)
                }
                label:
                {

                    WorkspaceHeaderIcon(systemName: libraryEditMode == .active ? "checkmark" : "pencil")
                }
                .accessibilityLabel("Plans display and organization")
                Button(action: onOpenSaved)
                {

                    WorkspaceHeaderIcon(systemName: "bookmark")
                }
                .accessibilityLabel("Saved Items")
                .accessibilityHint("Opens your bookmarked content and archived collections")
                .accessibilityIdentifier("library.openSaved")
                createMenu
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            HStack(spacing: 10)
            {

                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(browseFilter.searchPrompt, text: $searchText)
                .focused($isLibrarySearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(browseFilter.searchPrompt)
                .accessibilityHint(browseFilter.searchHint)
                if !searchText.isEmpty
                {

                    Button
                    {

                        searchText = ""
                    }
                    label:
                    {

                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear Plans search")
                }

            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            if isLibrarySearchFocused || !searchText.isEmpty
            {

                Text(browseFilter.searchContext)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsRecentShelf && browseFilter.browsesCollections
            {

                VStack(alignment: .leading, spacing: 8)
                {

                    HStack
                    {

                        Text("Recently added or viewed").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button
                        {

                            isLibrarySearchFocused = false
                            withAnimation
                            {
                                showsRecentShelf = false
                            }

                        }
                        label:
                        {

                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Close recent items")
                    }

                    if availableRecents.isEmpty
                    {

                        Text("Open or add a Plans item to find it here.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    else
                    {

                        recentShelf
                    }

                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

        }
        .onChange(of: isLibrarySearchFocused)
        {
            _, focused in
            if focused
            {
                withAnimation
                {
                    showsRecentShelf = true
                }

            }

        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background
        {
            TodayPaperBackground()
        }

    }


    private var createMenu: some View
    {

        Menu
        {

            Button("+ New List")
            {

                editingCollection = PersonalCollection(title: "", kind: .list)
            }

            Button("+ New Board")
            {

                editingCollection = PersonalCollection(title: "", kind: .board, icon: .project)
            }

            Divider()
            starterListsMenu
            starterBoardsMenu
            templatesMenu
            examplesMenu
        }
        label:
        {

            WorkspaceHeaderIcon(systemName: "plus.circle.fill")
        }
        .accessibilityLabel("Plans creation and examples")
    }


    private var starterListsMenu: some View
    {

        Menu("Starter Lists", systemImage: "list.bullet")
        {

            ForEach(
                ["On the Table", "In the Queue", "Scheduled", "Shopping", "Reminders", "Up for Brew", "Misc"],
                id: \.self
            )
            {
                title in
                Button(title)
                {

                    editingCollection = DefaultListTutorial.makeStarter(title: title)
                }

            }

        }

    }


    private var starterBoardsMenu: some View
    {

        Menu("Starter Boards", systemImage: "rectangle.3.group")
        {

            ForEach(["General Notes", "New Project Notes", "Girlfriend Important Details"], id: \.self)
            {
                title in
                Button(title)
                {

                    editingCollection = PersonalCollection(
                        title: title, kind: .board,
                        icon: title == "Girlfriend Important Details" ? .heart : .notes)
                }

            }

        }

    }


    private var examplesMenu: some View
    {

        Menu("Examples", systemImage: "sparkles")
        {

            Button("Browse all examples", systemImage: "books.vertical")
            {

                browseFilter = .examples;
                searchText = ""
            }

            daySectionExamplesMenu
            listExamplesMenu
            Menu("Board examples", systemImage: "rectangle.3.group")
            {

                ForEach(PersonalBoardExample.allCases)
                {
                    example in
                    Button(example.rawValue, systemImage: "plus")
                    {

                        prepareImportanceExample(example.makeCollection(existingTitles: collections.map(\.title)))
                    }

                }

            }

            weekExamplesMenu
            fullMonthExamplesMenu
            if hasUserDataBackup, let onRestoreUserData
            {

                Divider()
                Button("Restore User Data", systemImage: "arrow.uturn.backward")
                {
                    onRestoreUserData()
                }

            }

        }

    }


    private var daySectionExamplesMenu: some View
    {

        Menu("Day section examples", systemImage: "rectangle.3.group")
        {

            ForEach(PlanningRoutineLibrary.sectionExamples)
            {
                template in
                Menu(template.name)
                {

                    Button("Preview sections", systemImage: "eye")
                    {
                        previewDaySectionExample(template)
                    }

                    Button("Use on a day…", systemImage: "calendar.badge.plus")
                    {
                        daySectionExampleToApply = template
                    }

                }

            }

        }

    }


    ///
    /// @fcn        BoardListsView.previewDaySectionExample
    /// @brief      Present a named-day-section example
    /// @details    Uses the reusable routine-template preview so users can inspect it before choosing an application
    ///             date.
    ///
    /// @param[in]  template  Authored routine or capture template to preview, apply, or edit
    ///
    /// @return     (Void) no return value
    ///
    private func previewDaySectionExample(_ template: PlanningRoutineTemplate)
    {

        examplePreview = LibraryExamplePreview(
            title: template.name,
            summary:
                                "A day organized into colored sections. Collapse, reorder, or move whole sections after applying. Previewing does not change your plans.",
            lists: template.collection.lists)
    }


    private var fullMonthExamplesMenu: some View
    {

        Menu("Full-month examples", systemImage: "calendar")
        {

            Menu("A month in motion")
            {

                Button("Preview month")
                {

                    let example = FullMonthExample.make(calendar: planningAccess?.document.calendar ?? .current)
                    examplePreview = LibraryExamplePreview(
                        title: "A month in motion",
                        summary:
                                                                    "Fictional plans for this month: fuller days through today, with a few upcoming plans. Previewing does not change your data.",
                        lists: example.previewLists)
                }

                if let onLoadExampleMonth
                {

                    Button("Use example month", systemImage: "plus")
                    {
                        onLoadExampleMonth()
                    }

                }

            }

        }

    }


    private var weekExamplesMenu: some View
    {

        Menu("Week View examples", systemImage: "calendar")
        {

            Button("Preview Work Week Board")
            {

                examplePreview = LibraryExamplePreview(
                    title: "Work Week Board", summary: "A separate seven-list Week View example.",
                    lists: SampleData.lists)
            }

            Button("Use Week View", systemImage: "plus")
            {

                prepareImportanceExample(PersonalCollection.exampleWeek(existingTitles: collections.map(\.title)))
            }

            Menu("Example cards")
            {

                ForEach(SampleData.lists)
                {
                    list in
                    Menu(list.title)
                    {

                        ForEach(list.cards.filter
                            {
                                !$0.isSectionDivider
                            })
                        {
                            card in
                            Button(card.word)
                            {

                                examplePreview = LibraryExamplePreview(
                                    title: card.word, summary: list.title,
                                    lists: [KanbanList(id: list.id, title: list.title, cards: [card])])
                            }

                        }

                    }

                }

            }

        }

    }


    private var listExamplesMenu: some View
    {

        Menu("List examples", systemImage: "list.bullet")
        {

            ForEach(PersonalListExample.allCases)
            {
                example in
                listExampleMenu(example)
            }

        }

    }


    ///
    /// @fcn        BoardListsView.listExampleMenu
    /// @brief      Build actions for a particular personal-list example
    /// @details    Routes preview and creation choices through the existing example-selection callbacks.
    ///
    /// @param[in]  example  Bundled example content or dataset to use
    ///
    /// @return     (some View) actions for a particular personal-list example
    ///
    private func listExampleMenu(_ example: PersonalListExample) -> some View
    {

        let draft = example.makeCollection(existingTitles: [])
        return Menu(example.rawValue)
        {

            Button("Preview list")
            {

                examplePreview = LibraryExamplePreview(
                    title: example.rawValue, summary: example.summary, lists: draft.lists)
            }

            Menu("Example cards")
            {

                ForEach(draft.lists[0].cards)
                {
                    card in
                    Button(card.word)
                    {

                        examplePreview = LibraryExamplePreview(
                            title: card.word, summary: example.summary,
                            lists: [KanbanList(id: 0, title: example.rawValue, cards: [card])])
                    }

                }

            }

            Button("Use \(example.rawValue)", systemImage: "plus")
            {

                prepareImportanceExample(example.makeCollection(existingTitles: collections.map(\.title)))
            }

        }

    }


    @ViewBuilder
    private var libraryTemplateRows: some View
    {

        PlanningTemplateLibraryRows(query: searchText)
        let listTemplates = MixedListTemplate.allCases.filter
        {

            LibraryStarterSearch.matches(
                searchText, texts: [$0.rawValue, $0.summary, "List template"] + $0.items.flatMap
                {
                    [$0.0, $0.1]
                })
        }

        if !listTemplates.isEmpty
        {

            Section("List templates")
            {

                ForEach(listTemplates)
                {
                    template in
                    DisclosureGroup
                    {

                        Text(template.summary).foregroundStyle(.secondary)
                        ForEach(template.items.indices, id: \.self)
                        {
                            index in
                            Label(template.items[index].0, systemImage: template.items[index].2.symbol)
                        }

                        Button("Use " + template.rawValue, systemImage: "plus")
                        {

                            prepareImportanceExample(template.makeCollection(existingTitles: collections.map(\.title)))
                        }

                    }
                    label:
                    {

                        Label(template.rawValue, systemImage: "list.bullet.rectangle")
                    }

                }

            }

        }

        let quickTemplates = QuickCaptureTemplate.allCases.filter
        {

            LibraryStarterSearch.matches(
                searchText, texts: [$0.title, $0.summary, $0.body, $0.presentation.title] + $0.actions)
        }

        if !quickTemplates.isEmpty
        {

            Section
            {

                ForEach(quickTemplates)
                {
                    template in
                    DisclosureGroup
                    {

                        Text(template.summary).foregroundStyle(.secondary)
                        if !template.body.isEmpty
                        {
                            Text(template.body).font(.subheadline)
                        }

                        ForEach(Array(template.actions.enumerated()), id: \.offset)
                        {
                            _, action in
                            Label(action, systemImage: "square")
                        }

                        Button("Use " + template.title, systemImage: "plus")
                        {
                            libraryQuickTemplate = template
                        }

                    }
                    label:
                    {

                        Label(template.title, systemImage: template.presentation == .note ? "note.text" : "rectangle")
                    }

                }

            }
            header:
            {

                Text("Card & Note starting points")
            }
            footer:
            {

                Text("Opens an editable draft with a Week list destination. Nothing is added until you tap Add.")
            }

        }

    }


    @ViewBuilder
    private var libraryExampleRows: some View
    {

        let listExamples = PersonalListExample.allCases.filter
        {

            LibraryStarterSearch.matches(
                searchText, texts: [$0.rawValue, $0.summary, "List example"] + $0.cards.flatMap
                {
                    [$0.0, $0.1]
                })
        }

        let boardExamples = PersonalBoardExample.allCases.filter
        {

            LibraryStarterSearch.matches(
                searchText, texts: [$0.rawValue, $0.summary, "Board example"] + $0.listSummaries.map(\.title))
        }

        let weekMatches = LibraryStarterSearch.matches(
            searchText,
            texts: ["Example Week Work Week Board calendar seven days"]
            + SampleData.lists.flatMap
            {
                [$0.title] + $0.cards.map(\.word)
            })
        let monthMatches = LibraryStarterSearch.matches(
            searchText, texts: ["A month in motion Full-month example calendar fictional plans"])
        let sectionExamples = LibraryDaySectionExamples.matches(query: searchText)
        if listExamples.isEmpty && boardExamples.isEmpty && sectionExamples.isEmpty && !weekMatches && !monthMatches
        {

            ContentUnavailableView(
                                    "No matching examples", systemImage: "sparkles",
                                    description: Text("Try a different name, topic, or example type."))
        }

        LibraryDaySectionExamples(
            query: searchText, onPreview: previewDaySectionExample,
            onApply:
            {
                daySectionExampleToApply = $0
            })
        if !listExamples.isEmpty
        {

            Section("List examples")
            {

                ForEach(listExamples)
                {
                    example in
                    DisclosureGroup
                    {

                        Text(example.summary).foregroundStyle(.secondary)
                        ForEach(example.cards.indices, id: \.self)
                        {
                            index in
                            VStack(alignment: .leading, spacing: 4)
                            {

                                Text(example.cards[index].0).font(.headline)
                                Text(example.cards[index].1).font(.subheadline).foregroundStyle(.secondary)
                            }

                        }

                        Button("Preview " + example.rawValue, systemImage: "eye")
                        {

                            let draft = example.makeCollection(existingTitles: collections.map(\.title))
                            examplePreview = LibraryExamplePreview(
                                title: example.rawValue, summary: example.summary, lists: draft.lists)
                        }

                        Button("Use " + example.rawValue, systemImage: "plus")
                        {

                            prepareImportanceExample(example.makeCollection(existingTitles: collections.map(\.title)))
                        }

                    }
                    label:
                    {

                        Label(example.rawValue, systemImage: "list.bullet")
                    }

                }

            }

        }

        if !boardExamples.isEmpty
        {

            Section("Board examples")
            {

                ForEach(boardExamples)
                {
                    example in
                    DisclosureGroup
                    {

                        Text(example.summary).foregroundStyle(.secondary)
                        ForEach(Array(example.listSummaries.enumerated()), id: \.offset)
                        {
                            _, list in
                            Text("\(list.title) · \(list.count) items").font(.subheadline)
                        }

                        Button("Preview " + example.rawValue, systemImage: "eye")
                        {

                            let draft = example.makeCollection(existingTitles: collections.map(\.title))
                            examplePreview = LibraryExamplePreview(
                                title: example.rawValue, summary: example.summary, lists: draft.lists)
                        }

                        Button("Use " + example.rawValue, systemImage: "plus")
                        {

                            prepareImportanceExample(example.makeCollection(existingTitles: collections.map(\.title)))
                        }

                    }
                    label:
                    {

                        Label(example.rawValue, systemImage: "rectangle.3.group")
                    }

                }

            }

        }

        if weekMatches
        {

            Section
            {

                Button("Preview Example Week", systemImage: "eye")
                {

                    examplePreview = LibraryExamplePreview(
                        title: "Example Week",
                        summary:
                                                                    "Seven dated-day lists from Plenact's original Work Week example. Previewing changes nothing.",
                        lists: SampleData.lists)
                }

                Button("Use as a new Board", systemImage: "plus")
                {

                    prepareImportanceExample(PersonalCollection.exampleWeek(existingTitles: collections.map(\.title)))
                }

                LibraryExampleWeekTemplateButton()
                if onLoadExampleWeek != nil
                {

                    Button("Load into current Week", systemImage: "calendar")
                    {
                        weekExampleAction = "load"
                    }

                }

                if ExampleLoadUndoStore.load() != nil, onUndoExampleWeek != nil
                {

                    Button("Undo Last Load", systemImage: "arrow.uturn.backward")
                    {
                        weekExampleAction = "undo"
                    }

                }

            }
            header:
            {

                Text("Week example")
            }
            footer:
            {

                Text(
                                                "Use as a new Board creates a draft. Loading into the current Week requires confirmation and retains the previous Week for undo."
                )
            }

        }

        if monthMatches
        {

            Section
            {

                Button("Preview A month in motion", systemImage: "eye")
                {

                    let example = FullMonthExample.make(calendar: planningAccess?.document.calendar ?? .current)
                    examplePreview = LibraryExamplePreview(
                        title: "A month in motion",
                        summary: "Fictional plans across this month. Previewing does not change your data.",
                        lists: example.previewLists)
                }

                if let onLoadExampleMonth
                {

                    Button("Use example month", systemImage: "calendar.badge.plus", action: onLoadExampleMonth)
                }

                if hasUserDataBackup, let onRestoreUserData
                {

                    Button("Restore User Data", systemImage: "arrow.uturn.backward", action: onRestoreUserData)
                }

            }
            header:
            {

                Text("Full-month example")
            }
            footer:
            {

                Text(
                                                "Using the example month asks for confirmation and backs up your workspace first. Use Restore User Data to return."
                )
            }

        }

    }


    private var templatesMenu: some View
    {

        Menu("Templates", systemImage: "square.stack.3d.up")
        {

            Button("Browse all templates", systemImage: "square.stack.3d.up")
            {

                browseFilter = .templates;
                searchText = ""
            }

            Divider()
            ForEach([MixedListTemplate.planDay, .startProject, .exploreIdea])
            {
                template in
                Button(template.rawValue)
                {

                    prepareImportanceExample(template.makeCollection(existingTitles: collections.map(\.title)))
                }

            }

        }

    }


    ///
    /// @fcn        BoardListsView.body
    /// @brief      Present the personal-collection directory without duplicate Week access
    /// @details    Supports search, create/edit, confirmed deletion, and unfiltered active-collection
    ///             reordering. Presented boards retain attachment references from other boards and undo state
    ///
    /// @return     (some View) searchable directory with settings and board presentations
    /// @post       Directory edits update the shared collections binding; archival uses save-first
    ///             persistence and does not alter Week. Archived collections remain outside active rows
    ///
    var body: some View
    {  /* Personal collection directory and management sheets */


        NavigationStack
        {


            List
            {

                if browseFilter == .help
                {

                    LibraryHelpRows(query: searchText)
                    {
                        openedHelpArticle = $0
                    }

                }
                else if browseFilter == .labels
                {

                    libraryLabelRows
                }
                else if browseFilter == .templates
                {

                    libraryTemplateRows
                }
                else if browseFilter == .examples
                {

                    libraryExampleRows
                }
                else
                {

                    Section
                    {


                        ForEach(filteredCollections)
                        {
                            collection in

                            collectionEntry(collection)
                        }
                        .onMove
                        {
                            source, destination in
                            guard browseFilter == .all,
                            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            else
                            {


                                return
                            }


                            var active = collections.filter(
                                \.isActive) /* Active directory entries reordered by the user */

                            active.move(fromOffsets: source, toOffset: destination)
                            collections = active + collections.filter
                            {
                                !$0.isActive
                            }

                        }


                        if filteredCollections.isEmpty
                        {


                            VStack(alignment: .leading, spacing: 12)
                            {

                                Label(
                                    searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? (browseFilter == .all
                                        ? "Your own organizing spaces"
                                        : "No " + browseFilter.rawValue.lowercased() + " yet") : "No Plans matches",
                                    systemImage: "books.vertical"
                                )
                                .font(.headline)
                                Text(
                                    searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Keep ideas, projects, and everyday plans together in personal lists and boards."
                                    : "Nothing in your Plans matches ‘\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))’. Try another word or phrase."
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                {


                                    ViewThatFits(in: .horizontal)
                                    {

                                        HStack(spacing: 12)
                                        {
                                            collectionCreationButtons
                                        }

                                        VStack(alignment: .leading, spacing: 12)
                                        {
                                            collectionCreationButtons
                                        }

                                    }

                                }

                            }

                            .padding(.vertical, 12)
                        }

                    }

                }

                if !librarySearchResults.isEmpty
                {

                    Section
                    {

                        ForEach(librarySearchResults)
                        {
                            result in
                            librarySearchRow(result)
                        }

                    }
                    header:
                    {

                        Text("Cards and notes · \(librarySearchResults.count) matches")
                    }

                }

            }

            .listRowSpacing(7)
            .listSectionSpacing(.custom(0))
            .contentMargins(.top, 12, for: .scrollContent)
            .contentMargins(.bottom, 8, for: .scrollContent)
            .onChange(of: collections)
            {
                old, updated in
                for collection in updated where collection.isActive
                {

                    let previousIDs = Set(
                        old.first(where:
                            {
                                $0.id == collection.id
                            })?.lists.flatMap(\.allCards).map(\.id) ?? [])
                    for card in collection.lists.filter(
                        {
                            !$0.isArchived
                        }).flatMap(\.cards)
                    where !card.isSectionDivider && !previousIDs.contains(card.id)
                    {

                        recentItems = LibraryRecentStore.remember(
                            LibraryRecentItem(collectionID: collection.id, cardID: card.id))
                    }

                }

            }
            .scrollContentBackground(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0)
            {

                VStack(spacing: 0)
                {

                    libraryHeader
                    if showsPlateShelf
                    {

                        plateSection
                        .background
                        {
                            TodayPaperBackground().overlay { StudioWorkspaceBackground(destination: .plans) }.clipped()
                        }

                    }

                }

            }
            .safeAreaInset(edge: .bottom, spacing: 0)
            {

                Color.clear.frame(height: bottomBarHeight > 0 ? 77 : 0)
            }
            .background
            {
                TodayPaperBackground().overlay { StudioWorkspaceBackground(destination: .plans) }
            }
            .environment(\.editMode, $libraryEditMode)
            .modifier(PlanningSharedSearchPresentation(isPresented: $showsSharedSearch))

            .sheet(item: $openedHelpArticle)
            {
                article in
                PlenactHelpArticleView(article: article)
            }
            .sheet(item: $browsedLabel)
            {
                label in
                LibraryLabelMatchesView(label: label)
            }
            .onAppear
            {
                browseLabelLibrary = LabelLibraryStore.load()
            }
            .onChange(of: browseFilter)
            {
                _, filter in
                libraryEditMode = .inactive
                if filter == .labels
                {
                    browseLabelLibrary = LabelLibraryStore.load()
                }

            }
            .sheet(item: $examplePreview)
            {
                preview in
                LibraryExamplePreviewView(preview: preview)
            }
            .sheet(item: $daySectionExampleToApply)
            {
                template in
                PlanningTemplateApplyView(template: template)
            }

            .sheet(item: $editingCollection)
            {
                collection in
                PersonalCollectionSettingsView(
                    collection: collection,
                    isNew: !collections.contains(where:
                        {
                            $0.id == collection.id
                        }),
                    onSave: saveCollection
                )
            }

            .sheet(item: $libraryQuickTemplate)
            {
                template in
                LibraryQuickTemplateComposer(template: template)
            }
            .confirmationDialog(
                weekExampleAction == "undo" ? "Restore the previous Week?" : "Load the example Week?",
                isPresented: Binding(get:
                    {
                        weekExampleAction != nil
                    }, set:
                    {
                        if !$0
                        {
                            weekExampleAction = nil
                        }

                    }),
                titleVisibility: .visible
            )
            {

                Button(weekExampleAction == "undo" ? "Undo Last Load" : "Load Example Week", role: .destructive)
                {

                    let success = weekExampleAction == "undo" ? onUndoExampleWeek?() : onLoadExampleWeek?()
                    if success != true
                    {

                        libraryStarterError = "The Week could not be updated. Your saved data has been retained."
                    }

                    weekExampleAction = nil
                }

                Button("Cancel", role: .cancel)
                {
                    weekExampleAction = nil
                }

            }
            message:
            {

                Text(
                    weekExampleAction == "undo"
                    ? "Replaces current active and archived Week content with the snapshot from before the example load."
                    : "Replaces current active and archived Week content. The previous Week is retained for Undo Last Load. Personal collections stay unchanged."
                )
            }
            .alert(
                                    "Library",
                                    isPresented: Binding(get:
                                        {
                                            libraryStarterError != nil
                                        }, set:
                                        {
                                            if !$0
                                            {
                                                libraryStarterError = nil
                                            }

                                        })
            )
            {

                Button("OK", role: .cancel)
                {
                    libraryStarterError = nil
                }

            }
            message:
            {

                Text(libraryStarterError ?? "")
            }
            .fullScreenCover(
                item: $newNoteDraftDestination,
                onDismiss:
                {

                    guard let destination = createdNoteDestination else
                    {
                        return
                    }

                    createdNoteDestination = nil
                    openedCollection = destination
                }
            )
            {
                collection in
                NewPersonalNoteComposer(
                    initialCollectionID: collection.id,
                    availablePersonalLists: collections
                )
                {
                    destinationID, capture, createdAt in
                    try createNote(in: destinationID, capture: capture, createdAt: createdAt)
                }
                .databaseActivityOverlay()
            }

            .fullScreenCover(item: $openedCollection, onDismiss: registerDirectoryNewNote)
            {
                collection in
                Group
                {

                    if let listID = collection.preferredFocusedListID, boardTargetCardID == nil
                    {

                        WorkspacePinnedListView(
                            reference: WorkspaceListReference(ownerID: collection.id, listID: listID),
                            returnDestinationTitle: "Plans")
                    }
                    else
                    {

                        presentedCollectionBoard(collection)
                    }

                }
                .environment(\.workspaceBottomBarHeight, 0)
            }

            .alert(
                                    "Delete \(deletingCollection?.kind.rawValue ?? "item")?",
                                    isPresented: Binding(
                                        get:
                                        {
                                            deletingCollection != nil
                                        },
                                        set:
                                        {
                                            if !$0
                                            {
                                                deletingCollection = nil
                                            }

                                        }
                                    )
            )
            {

                Button("Delete", role: .destructive)
                {

                    if let deletingCollection
                    {  /* Collection awaiting permanent deletion */


                        do
                        {


                            let updated = collections.filter
                            {

                                $0.id != deletingCollection.id
                            }  /* Directory snapshot excluding the confirmed deletion */


                            try PersonalCollectionStore.saveChecked(updated)
                            collections = updated
                        }
                        catch
                        {

                            DatabaseActivity.shared.report(
                                                                                    "Could not delete the collection: \(error.localizedDescription) It has been retained.")
                        }

                    }


                    deletingCollection = nil
                }


                Button("Cancel", role: .cancel)
                {
                    deletingCollection = nil
                }

            }
            message:
            {

                Text(
                                                "Permanently deletes this collection, all active and archived lists/cards, and its bookmarks. This cannot be undone. Your Week board is not affected."
                )
            }

            .confirmationDialog(
                                    "Archive \(archivingCollection?.title ?? "collection")?",
                                    isPresented: Binding(
                                        get:
                                        {
                                            archivingCollection != nil
                                        }, set:
                                        {
                                            if !$0
                                            {
                                                archivingCollection = nil
                                            }

                                        }
                                    ), titleVisibility: .visible
            )
            {

                Button("Archive")
                {

                    if let archivingCollection
                    {  /* Collection awaiting archive confirmation */


                        do
                        {


                            collections = try PersonalCollectionStore.archiveCollection(
                                id: archivingCollection.id, in: collections)
                        }
                        catch
                        {

                            DatabaseActivity.shared.report(
                                                                                    "Could not archive the collection: \(error.localizedDescription)")
                        }

                    }


                    archivingCollection = nil
                }


                Button("Cancel", role: .cancel)
                {
                    archivingCollection = nil
                }

            }
            message:
            {

                Text("Keeps all content on this device. Restore it from Saved.")
            }

        }
        .onChange(of: newListRequest)
        {
            _, _ in
            editingCollection = PersonalCollection(title: "", kind: .list)
        }
        .onChange(of: toolbarCollectionRequest?.wrappedValue, initial: true)
        {
            _, kind in
            guard let kind else
            {
                return
            }

            editingCollection = PersonalCollection(title: "", kind: kind, icon: kind == .board ? .project : .notes)
            toolbarCollectionRequest?.wrappedValue = nil
        }
        .onChange(of: libraryRecentData)
        {
            _, _ in
            recentItems = LibraryRecentStore.load()
        }
        .onAppear
        {

            recentItems = LibraryRecentStore.load()
            registerDirectoryNewNote()
            if let savedPersonalCardTarget
            {


                openSavedPersonalCard(savedPersonalCardTarget)
            }

        }
        .onChange(of: savedPersonalCardTarget)
        {
            _, target in
            guard let target else
            {


                return
            }


            openSavedPersonalCard(target)
        }

    }


    ///
    /// @fcn        BoardListsView.openSavedPersonalCard(_:)
    /// @brief      Open a bookmarked personal record in its canonical collection
    /// @details    Resolves against current active collection/list/card data and forwards the
    ///             collection-local Board targets before presenting the full-screen Board
    ///
    /// @param[in]  target  Collection/list/card identity selected from Saved
    /// @return     (Void) presents the owning collection and consumes the Saved request
    ///
    /// @post       No record is copied, moved, or unbookmarked
    ///
    private func openSavedPersonalCard(_ target: PersonalSavedCardTarget)
    {


        guard let collection = collections.first(where:
            {
                $0.id == target.collectionID && $0.isActive
            }),
        let list = collection.lists.first(where:
            {
                $0.id == target.listID && !$0.isArchived
            }),
        list.cards.contains(where:
            {
                $0.id == target.cardID && !$0.isSectionDivider
            })
        else
        {


            onClearSavedPersonalCardTarget()
            DatabaseActivity.shared.report("This saved item is no longer available in its collection.")
            return
        }


        boardTargetCardID = target.cardID
        boardTargetListID = target.listID
        mostRecentlyOpenedListID = collection.kind == .list ? collection.id : nil
        openedCollection = collection
        onClearSavedPersonalCardTarget()
    }


    ///
    /// @fcn        BoardListsView.collectionCreationButtons
    /// @brief      Offer blank-list creation alongside optional examples
    /// @details    Shared content fits horizontally or vertically without changing creation semantics
    /// @return     (some View) two independently accessible creation buttons
    /// @post       Actions present an unsaved form or chooser; collections remain unchanged
    ///
    private var collectionCreationButtons: some View
    {  /* List and Board creation shortcuts */


        Group
        {

            Button("Create a list", systemImage: "plus")
            {

                editingCollection = PersonalCollection(title: "", kind: .list)
            }


            Button("Examples", systemImage: "plus")
            {

                browseFilter = .examples
                searchText = ""
            }

        }

        .buttonStyle(.bordered)
    }

}
