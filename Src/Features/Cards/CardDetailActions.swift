// --------------------------------------------------------------------------------------------------
// @file       CardDetailActions.swift
// @brief      Owner-scoped Card editing and attachment operations
// @details    Applies explicit editor actions through complete working snapshots while respecting
//             editing locks, callbacks, and attachment retention.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


///
/// CardDetailView behavior grouped separately from stored view state
///
/// @section    Purpose
///     Keep owner-scoped operations with the existing view while retaining its state and lifecycle.
///
extension CardDetailView
{


    ///
    /// @fcn        CardDetailView.richTextFocusBinding
    /// @brief      Bridge one rich-text field into shared editor focus
    /// @details    Clears native header focus when a rich editor becomes active and clears only the matching
    ///             rich-text selection on blur.
    ///
    /// @param[in]  field  Selected editable field or field key path
    ///
    /// @return     (Binding<Bool>) binding that coordinates this rich-text field with the native header editor focus
    ///
    /// @note       UIKit focus uses ordinary state; SwiftUI FocusState only tracks native text fields.
    ///
    func richTextFocusBinding(for field: EditableField) -> Binding<Bool>
    {

        Binding(
            get:
            {
                richTextFocusedField == field
            },
            set:
            {
                isFocused in
                if isFocused
                {

                    focusedField = nil
                    richTextFocusedField = field
                }
                else if richTextFocusedField == field
                {

                    richTextFocusedField = nil
                }

            })
    }


    ///
    /// @fcn        CardDetailView.dismissEditing
    /// @brief      End header and rich-text editing together
    /// @details    Clears rich-text focus, native field focus, and the active header-field editing mode.
    ///
    /// @return     (Void) no return value
    ///
    func dismissEditing()
    {

        richTextFocusedField = nil
        focusedField = nil
        editingHeaderField = nil
    }


    ///
    /// @fcn        CardDetailView.memberIconColor(for:)
    /// @brief      Resolve the display color assigned to a member name
    /// @details    Trims surrounding whitespace and lowercases the name before dictionary lookup
    ///
    /// @param[in]  memberName  Display name whose normalized color key is queried
    ///
    /// @return     (Color) assigned member color or the system accent color
    ///
    /// @post       Member assignments and shared colors remain unchanged
    ///
    func memberIconColor(for memberName: String) -> Color
    {


        let normalizedName = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() /* Member-color lookup key */

        return memberColors[normalizedName] ?? .accentColor
    }


    ///
    /// @fcn        CardDetailView.setCover(_:)
    /// @brief      Validate and synchronize an explicit cover choice
    /// @details    Uses current attachment drafts and reports invalid selection without replacing
    ///             the cover
    ///
    /// @param[in]  id  Attached photo identity, or nil to remove the cover
    ///
    /// @return     (Void) validate and synchronize an explicit cover choice
    ///
    func setCover(_ id: UUID?)
    {


        guard !isEditingLocked else
        {
            return
        }

        var updated = card.replacingLocation(
            id: recordID, listTitle: currentListTitle) /* Edited record retaining its current location identity */

        updated.attachments = attachments

        do
        {


            try updated.setCover(id)
            coverImportID = nil
            selectedCoverPhoto = nil
            coverAttachmentID = updated.coverAttachmentID
            syncCardState()
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not set this cover: \(error.localizedDescription) Choose an attached photo.")
        }

    }


    ///
    /// @fcn        CardDetailView.useLibraryCover(_:)
    /// @brief      Publish a library selection while preserving all working card content
    /// @details    Reuses attachment identities and cancels superseded cover photo imports
    ///
    /// @param[in]  image  Explicit illustration choice
    ///
    /// @return     (Bool) whether selection succeeded; errors are shown through standard feedback
    ///
    func useLibraryCover(_ image: ExampleCoverImage) -> Bool
    {


        guard !hasDeletedCard, !hasMovedCard, !isEditingLocked else
        {


            return false
        }


        var updated = card /* Card snapshot receiving the cover change */

        updated.attachments = attachments

        do
        {


            try updated.useLibraryCover(image)
            attachments = updated.attachments ?? []
            coverAttachmentID = updated.coverAttachmentID
            coverImportID = nil
            selectedCoverPhoto = nil
            syncCardState()

            return true
        }
        catch
        {


            DatabaseActivity.shared.report("Could not select this cover: \(error.localizedDescription)")

            return false
        }

    }


    ///
    /// @fcn        CardDetailView.attachmentContent(for:)
    /// @brief      Build the tap behavior for one card attachment
    /// @details    Opens remote links directly and presents local media in the attachment viewer
    ///
    /// @param[in]  attachment  Attachment metadata shown in the card gallery
    ///
    /// @return     (some View) link or local attachment-preview button
    ///
    @ViewBuilder
    func attachmentContent(for attachment: KanbanAttachment) -> some View
    {


        if let url = attachment.url
        {  /* Remote link target */


            Link(destination: url)
            {


                CardAttachmentThumbnail(attachment: attachment)
            }

        }
        else
        {


            Button
            {

                activeSheet = .attachmentPreview(attachment)
            }
            label:
            {

                CardAttachmentThumbnail(attachment: attachment)
            }

            .buttonStyle(.plain)
        }

    }


    ///
    /// @fcn        CardDetailView.attachmentGalleryItem(_:)
    /// @brief      Add cover and removal actions to one attachment thumbnail
    /// @details    Only photos can become covers; accessibility actions mirror the contextual menu
    ///
    /// @param[in]  attachment  Current attachment metadata
    ///
    /// @return     (some View) interactive gallery item
    ///
    func attachmentGalleryItem(_ attachment: KanbanAttachment) -> some View
    {


        attachmentContent(for: attachment)
        .contextMenu
        {

            if attachment.kind == .photo
            {


                Button(coverAttachmentID == attachment.id ? "Remove Cover" : "Set as Cover")
                {

                    setCover(coverAttachmentID == attachment.id ? nil : attachment.id)
                }

            }


            Button("Remove attachment", systemImage: "trash", role: .destructive)
            {

                removeAttachment(attachment)
            }

        }

        .accessibilityLabel(attachment.url == nil ? "View attached media" : "Open attached link")
        .accessibilityActions
        {

            if attachment.kind == .photo
            {


                Button(coverAttachmentID == attachment.id ? "Remove Cover" : "Set as Cover")
                {

                    setCover(coverAttachmentID == attachment.id ? nil : attachment.id)
                }

            }


            Button("Remove attachment")
            {
                removeAttachment(attachment)
            }

        }

    }


    ///
    /// @fcn        CardDetailView.attachmentGallery(_:)
    /// @brief      Build a photo Gallery and a grid of nonphoto attachments
    /// @details    Renders each attachment using the gallery item view and leaves cover filtering
    ///             to the caller's visible-attachment selection
    ///
    /// @param[in]  visibleAttachments  Attachments to display in this gallery
    ///
    /// @return     (some View) editable photo Gallery and nonphoto attachment grid
    ///
    func attachmentGallery(_ visibleAttachments: [KanbanAttachment]) -> some View
    {

        let photos = visibleAttachments.filter
        {
            $0.kind == .photo
        }

        let otherMedia = visibleAttachments.filter
        {
            $0.kind != .photo
        }

        return VStack(alignment: .leading, spacing: 16)
        {

            if !photos.isEmpty
            {

                CardPhotoGallery(
                    photos: photos,
                    photoSelection: $selectedPhotoItems,
                    onOpen:
                    {
                        activeSheet = .attachmentPreview($0)
                    },
                    onCaption: updatePhotoCaption,
                    onReorder: reorderGalleryPhotos,
                    onRemove: removeAttachment,
                    onSetCover:
                    {
                        setCover($0)
                    }
                )
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
            }

            if !otherMedia.isEmpty
            {

                DetailSection(title: "Attachments")
                {

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8)
                    {

                        ForEach(otherMedia)
                        {
                            attachment in
                            attachmentGalleryItem(attachment)
                        }

                    }

                }

            }

        }

    }


    ///
    /// @fcn        CardDetailView.updatePhotoCaption
    /// @brief      Save a photo caption through the card's checked update
    /// @details    Edits a working card snapshot, publishes attachment state only after sync accepts it, and reports
    ///             validation or save failures.
    ///
    /// @param[in]  id       Stable draft or objective identity
    /// @param[in]  caption  Proposed photo caption text
    ///
    /// @return     (Bool) true only after the edited attachment caption is accepted by card synchronization
    ///
    func updatePhotoCaption(_ id: UUID, _ caption: String) -> Bool
    {

        var updated = workingCardSnapshot
        do
        {

            try updated.setPhotoCaption(caption, for: id)
            guard syncCardState(attachments: updated.attachments ?? []) else
            {
                return false
            }

            attachments = updated.attachments ?? []
            return true
        }
        catch
        {

            DatabaseActivity.shared.report("Could not save this photo caption: \(error.localizedDescription)")
            return false
        }

    }


    ///
    /// @fcn        CardDetailView.reorderGalleryPhotos
    /// @brief      Save a validated photo-gallery order
    /// @details    Reorders a working snapshot and updates local attachments only after checked card synchronization
    ///             succeeds.
    ///
    /// @param[in]  ids  Photo identities in their requested display order
    ///
    /// @return     (Bool) true only after validated gallery ordering is accepted by card synchronization
    ///
    func reorderGalleryPhotos(_ ids: [UUID]) -> Bool
    {

        var updated = workingCardSnapshot
        do
        {

            try updated.reorderGalleryPhotos(ids)
            guard syncCardState(attachments: updated.attachments ?? []) else
            {
                return false
            }

            attachments = updated.attachments ?? []
            return true
        }
        catch
        {

            DatabaseActivity.shared.report("Could not arrange these photos: \(error.localizedDescription)")
            return false
        }

    }


    ///
    /// @fcn        CardDetailView.selectedCoverPreview
    /// @brief      Build the selected cover's accessible preview button
    /// @details    Opens the attachment preview on tap and supplies the photo caption as the accessibility value.
    ///
    /// @param[in]  cover  Currently selected cover attachment
    ///
    /// @return     (some View) the selected cover's accessible preview button
    ///
    func selectedCoverPreview(_ cover: KanbanAttachment) -> some View
    {

        Button
        {

            activeSheet = .attachmentPreview(cover)
        }
        label:
        {

            CardCoverPreview(attachment: cover)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open selected cover")
        .accessibilityValue(cover.caption ?? "No caption")
    }


    ///
    /// @fcn        CardDetailView.importPhotos(from:coverRequestID:)
    /// @brief      Import selected photo-library items as card attachments
    /// @details    Loads each selected photo or video, stores successful transfers in the app
    ///             container, synchronizes the attachment metadata to the card, and reports partial
    ///             failures
    ///
    /// @param[in]  photoItems      PhotosPicker items selected for the current card
    /// @param[in]  coverRequestID  Explicit cover import identity; nil means ordinary attachment
    ///             import
    ///
    /// @return     (Void) updates the card with successfully imported photo and video attachments
    ///
    /// @pre        photoItems were selected from the PhotosPicker for this card
    /// @post       The selection is cleared; saved attachment records are synchronized to board
    ///             state
    /// @note       Successful imports are retained even if another selected item fails to load or
    ///             save
    ///
    @MainActor
    func importPhotos(from photoItems: [PhotosPickerItem], coverRequestID: UUID? = nil) async
    {


        guard !hasDeletedCard, !hasMovedCard, !isEditingLocked else
        {


            return
        }


        if let coverRequestID, coverImportID != coverRequestID
        {  /* Cover request checked against the latest import */


            return
        }


        var importFailed = false /* Whether any selected media failed to import */

        for photoItem in photoItems
        {  /* Selected Photos-library item */


            do
            {


                guard let mediaData = try await photoItem.loadTransferable(type: Data.self)
                else
                {  /* Transferred media bytes */


                    importFailed = true
                    continue
                }


                guard !hasDeletedCard, !hasMovedCard, !isEditingLocked else
                {


                    return
                }


                if let coverRequestID, coverImportID != coverRequestID
                {  /* Cover request checked before importing media */


                    return
                }


                let contentType = photoItem.supportedContentTypes.first /* Preferred selected-media type        */
                let isVideo = photoItem.supportedContentTypes.contains
                {  /* Whether the selection is video media */

                    $0.conforms(to: .movie) || $0.conforms(to: .video)
                }


                let mediaKind: KanbanAttachmentKind = isVideo ? .video : .photo /* Stored media category            */
                let fileExtension =
                contentType?.preferredFilenameExtension
                ?? (isVideo ? "mov" : "jpg") /* File type used for local storage */

                let attachment = try CardAttachmentStore.saveMedia(
                    mediaData, kind: mediaKind, fileExtension: fileExtension) /* Persisted media record ready to attach */

                attachments.append(attachment)

                if coverRequestID != nil && mediaKind == .photo
                {


                    coverAttachmentID = attachment.id
                }

            }
            catch
            {


                importFailed = true
            }

        }


        if let coverRequestID, coverImportID != coverRequestID
        {  /* Cover request checked before publishing saved media */


            return
        }


        if coverRequestID != nil
        {


            coverImportID = nil
            selectedCoverPhoto = nil
        }
        else
        {


            selectedPhotoItems = []
            activeSheet = nil
        }


        syncCardState(attachments: attachments)

        if importFailed
        {


            attachmentNoticeMessage = "One or more selected photos or videos could not be added. Please try again."
            showingAttachmentNotice = true
        }

    }


    ///
    /// @fcn        CardDetailView.addDrawingAttachment
    /// @brief      Import and save an editable drawing on this card
    /// @details    Rejects deleted or moved cards and restores the previous attachment state if media import or card
    ///             synchronization fails.
    ///
    /// @param[in]  draft  Editable value proposed for persistence
    ///
    /// @return     (Bool) true when the imported drawing is retained by the owner; false on rejection or failure
    ///
    /// @note       Attach both the preview and editable strokes, publishing only after the owner accepts the update.
    ///
    func addDrawingAttachment(_ draft: DrawingCaptureDraft) -> Bool
    {

        guard !hasDeletedCard, !hasMovedCard, !isEditingLocked else
        {
            return false
        }

        let previous = attachments
        do
        {

            return try QuickCaptureMediaCommit.save([], drawings: [draft])
            {
                imported in
                attachments.append(contentsOf: imported)
                guard syncCardState(attachments: attachments) else
                {

                    attachments = previous
                    return false
                }

                return true
            }

        }
        catch
        {

            attachments = previous
            return false
        }

    }


    ///
    /// @fcn        CardDetailView.addWebLink(_:)
    /// @brief      Add a validated web URL to the card's attachment list
    /// @details    Appends link metadata, closes the active sheet, and emits the complete card
    ///             snapshot
    ///
    /// @param[in]  url  Web address selected for attachment
    ///
    /// @return     (Void) updates local detail state and synchronizes the card
    ///
    /// @pre        The caller has validated the URL as an acceptable web link
    /// @post       No remote content is downloaded or local media file created by this helper
    ///
    func addWebLink(_ url: URL)
    {


        attachments.append(KanbanAttachment(url: url, mediaKind: .link))
        activeSheet = nil
        syncCardState(attachments: attachments)
    }


    ///
    /// @fcn        CardDetailView.addClipboardAttachment()
    /// @brief      Import copied images or a web address from the system clipboard
    /// @details    Prefers a clipboard URL over string content and validates with the
    ///             attachment-store helper
    ///
    /// @return     (Void) adds a valid link or presents an invalid-link notice
    ///
    /// @post       Invalid input closes the source sheet and shows a notice without adding an
    ///             attachment
    ///
    func addClipboardAttachment()
    {

        guard !hasDeletedCard, !hasMovedCard, !isEditingLocked else
        {
            return
        }

        let pasteboard = UIPasteboard.general
        activeSheet = nil

        if let images = pasteboard.images, !images.isEmpty
        {

            let previous = attachments
            var imported: [KanbanAttachment] = []
            do
            {

                for image in images
                {

                    guard let data = image.pngData() else
                    {

                        throw CocoaError(.fileReadCorruptFile)
                    }

                    imported.append(try CardAttachmentStore.saveMedia(data, kind: .photo, fileExtension: "png"))
                }

                attachments.append(contentsOf: imported)
                guard syncCardState(attachments: attachments) else
                {

                    throw CocoaError(.fileWriteUnknown)
                }

            }
            catch
            {

                attachments = previous
                try? CardAttachmentStore.removeDeletedFiles(
                    Set(imported.flatMap(\.storedFileNames)), keeping: Set(previous.flatMap(\.storedFileNames)))
                attachmentNoticeMessage = "Could not add the clipboard image. Please try again."
                showingAttachmentNotice = true
            }

            return
        }


        let clipboardText = pasteboard.url?.absoluteString ?? pasteboard.string ?? ""
        guard let url = CardAttachmentStore.webURL(from: clipboardText) else
        {

            attachmentNoticeMessage = "The clipboard does not contain an image or a valid web link."
            showingAttachmentNotice = true
            return
        }

        addWebLink(url)
    }


    ///
    /// @fcn        CardDetailView.showAttachmentSourceComingSoon(_:)
    /// @brief      Explain an attachment source that is not yet supported
    /// @details    Names the selected source in a notice and closes the source-selection sheet
    ///
    /// @param[in]  source  Display name of the unavailable attachment source
    ///
    /// @return     (Void) updates the notice and dismisses the source sheet
    ///
    /// @post       Card attachments and files remain unchanged
    ///
    func showAttachmentSourceComingSoon(_ source: String)
    {


        attachmentNoticeMessage = "\(source) attachments are coming soon."
        showingAttachmentNotice = true
        activeSheet = nil
    }


    ///
    /// @fcn        CardDetailView.removeAttachment(_:)
    /// @brief      Remove an attachment record from the current card
    /// @details    Deletes the attachment record from local detail state and synchronizes the
    ///             updated card; attachment-file pruning depends on the parent Board's update
    ///             callback
    ///
    /// @param[in]  attachment  Photo, video, or link attachment selected for removal
    ///
    /// @return     (Void) updates the card's attachment collection and persistence state
    ///
    /// @pre        attachment identifies an item in the current card's attachment collection
    /// @post       Matching attachment IDs are absent locally; this helper does not delete stored
    ///             files directly
    ///
    func removeAttachment(_ attachment: KanbanAttachment)
    {


        let removesCover =
        coverAttachmentID == attachment.id  /* Whether removing this attachment also clears the cover */
        var updated = card                  /* Card snapshot excluding the removed attachment         */

        updated.attachments = attachments
        updated.coverAttachmentID = coverAttachmentID
        updated.removeAttachment(attachment.id)
        attachments = updated.attachments ?? []
        coverAttachmentID = updated.coverAttachmentID

        if removesCover
        {


            coverImportID = nil
            selectedCoverPhoto = nil
        }


        syncCardState(attachments: attachments)
    }


    ///
    /// @fcn        CardDetailView.syncCardState(title:*/:*/:*/:*/:*/:*/:*/:*/:*/:)
    /// @brief      Push the current card state back to the parent board
    /// @details    Combines explicit overrides with working text, checklists, comments,
    ///             assignments, labels, attachments, dates, and activity dismissal state. Preserves
    ///             card identity and original list/divider metadata while emitting through
    ///             onTitleToggle
    ///
    /// @param[in]  title           Optional title override; nil uses current titleText
    /// @param[in]  subtitle        Optional subtitle override; nil resolves current/default
    ///             subtitle state
    /// @param[in]  members         Optional assignment override; nil uses local members
    /// @param[in]  labelIDs        Optional label-ID override; nil uses local selection
    /// @param[in]  attachments     Optional attachment override; nil uses local records
    /// @param[in]  titleChecked    Optional updated checked state for the card title
    /// @param[in]  startDate       Optional updated start date for the card
    /// @param[in]  dueDate         Optional updated due date for the card
    /// @param[in]  clearStartDate  Whether to remove the card's start date
    /// @param[in]  clearDueDate    Whether to remove the card's due date
    ///
    /// @param[in]  editingLocked   Optional explicit editing-lock value used for lock or unlock
    ///             snapshots
    ///
    /// @return     (Bool) false when locking, deletion, or a rejected relocated-Note update prevents submission
    ///
    /// @post       Explicit overrides do not modify local State; nil callbacks perform no parent
    ///             update. Confirmed deletion suppresses all snapshots, including dismissal and
    ///             delayed edits
    /// @note       Date removal requires the corresponding clear flag; nil dates retain working
    ///             values. The unchanged generated subtitle remains nil when no original override
    ///             existed
    ///
    @discardableResult
    func syncCardState(
        title: String? = nil,                    /* Updated card title               */
        subtitle: String? = nil,                 /* Updated card subtitle            */
        members: [CardAssignee]? = nil,          /* Updated card assignees           */
        labelIDs: [String]? = nil,               /* Updated card label IDs           */
        attachments: [KanbanAttachment]? = nil,  /* Updated card attachments         */
        titleChecked: Bool? = nil,               /* Updated card title checked state */
        startDate: Date? = nil,                  /* Updated card start date          */
        dueDate: Date? = nil,                    /* Updated card due date            */
        clearStartDate: Bool = false,            /* Whether to clear the start date  */
        clearDueDate: Bool = false,              /* Whether to clear the due date    */
        editingLocked: Bool? = nil               /* Explicit lock or unlock request  */
    ) -> Bool
    {


        guard !hasDeletedCard, !hasMovedCard, !isEditingLocked || editingLocked == false else
        {


            return false
        }


        var updatedCard = workingCardSnapshot /* Complete working record receiving submitted field changes */

        if let editingLocked
        {
            updatedCard.isEditingLocked = editingLocked
        }


        if let title
        {  /* Submitted replacement title */


            updatedCard.word = title
        }

        if let subtitle
        {  /* Submitted replacement subtitle */


            updatedCard.subtitleOverride = subtitle
        }

        if let members
        {  /* Submitted replacement assignees */


            updatedCard.members = members
        }

        if let labelIDs
        {  /* Submitted replacement label assignments */


            updatedCard.labelIDs = labelIDs
        }

        if let attachments
        {  /* Submitted replacement attachment collection */


            updatedCard.attachments = attachments
        }

        if let titleChecked
        {  /* Submitted title completion state */


            updatedCard.isTitleChecked = titleChecked
        }

        updatedCard.startDate = clearStartDate ? nil : (startDate ?? self.startDate)
        updatedCard.dueDate = clearDueDate ? nil : (dueDate ?? self.dueDate)

        if let currentPersonalCollectionID, /* Current collection used to route relocated Note edits */
        currentPersonalCollectionID != personalCollectionID
        {

            guard onUpdateMovedNote?(currentPersonalCollectionID, updatedCard) == true else
            {


                return false
            }

        }
        else
        {


            onTitleToggle?(updatedCard)
        }

        return true
    }


    ///
    /// @fcn        CardDetailView.setEditingLocked
    /// @brief      Save an explicit lock change while retaining the complete working content
    /// @details    Ends editing before saving the current draft and lock flag together. A failed checked callback
    ///             for a relocated Note leaves the prior lock state in place. Clearing media selections prevents pending imports from
    ///             modifying the locked presentation; unlocking is allowed by the normal content-update guard.
    ///
    /// @param[in]  locked  Requested content-editing lock state
    ///
    /// @return     (Void) no return value
    ///
    func setEditingLocked(_ locked: Bool)
    {

        dismissEditing()
        guard syncCardState(editingLocked: locked) else
        {
            return
        }

        if locked
        {

            var snapshot = workingCardSnapshot
            snapshot.isEditingLocked = true
            lockedSnapshot = snapshot
        }
        else
        {

            lockedSnapshot = nil
        }

        isEditingLocked = locked
        activeSheet = nil
        selectedPhotoItems = []
        selectedCoverPhoto = nil
        coverImportID = nil
    }


    ///
    /// @fcn        CardDetailView.toggleReaction
    /// @brief      Toggle the current author's reaction only while editing is unlocked
    /// @details    Validates the emoji before creating an author identity and restores the prior reactions if the
    ///             owner rejects synchronization. Locked items never create a reaction identity or submit changes.
    ///
    /// @param[in]  emoji  Proposed single emoji reaction
    ///
    /// @return     (Void) no return value
    ///
    func toggleReaction(_ emoji: String)
    {

        guard !hasDeletedCard, !hasMovedCard, !isEditingLocked, !workingCardSnapshot.isSectionDivider,
        ItemEmojiReaction.validatedEmoji(emoji) != nil
        else
        {
            return
        }

        let author = LocalReactionIdentity.forUserAction()
        guard let updated = ItemEmojiReaction.toggling(emoji, authorID: author, in: reactions ?? []) else
        {
            return
        }

        let previous = reactions
        reactions = updated.isEmpty ? nil : updated
        reactionAuthorID = author
        if !syncCardState()
        {
            reactions = previous
        }

    }


    ///
    /// @fcn        CardDetailView.deleteCard()
    /// @brief      Permanently delete the card after explicit confirmation
    /// @details    Blocks snapshot synchronization before clearing focus or invoking the caller, so
    ///             dismissal and delayed editor callbacks cannot recreate the deleted card
    ///
    /// @return     (Void) dismisses after successful deletion; failed saves retain the editor and
    ///             drafts
    ///
    /// @pre        The user confirmed permanent deletion; onDelete owns persistence and file
    ///             pruning
    /// @post       Further onTitleToggle synchronization is disabled for this detail instance.
    ///             Missing callbacks and repeated successful deletion requests have no effect
    ///
    func deleteCard()
    {


        guard let onDelete, !hasDeletedCard else
        {  /* Original-owner deletion callback available for this record */


            return
        }


        hasDeletedCard = true

        let deleted: Bool                    /* Whether the owning collection accepted permanent deletion */
        if let currentPersonalCollectionID,  /* Current owner used to route relocated Note deletion       */
        currentPersonalCollectionID != personalCollectionID
        {

            deleted = onDeleteMovedNote?(currentPersonalCollectionID, workingCardSnapshot) == true
        }
        else
        {


            deleted = onDelete()
        }


        guard deleted else
        {


            hasDeletedCard = false

            return
        }


        dismissEditing()
        dismiss()
    }


    ///
    /// @fcn        CardDetailView.toggleCardTitle()
    /// @brief      Toggle the checked state of the card's title
    /// @details    Flips the boolean value representing whether the card's main title checkbox is
    ///             selected and synchronizes this change with the parent board
    ///
    /// @return     (Void) flips local completion and emits the new snapshot
    ///
    /// @post       Other working card fields are preserved
    ///
    func toggleCardTitle()
    {


        let nextChecked = !titleChecked /* Inverted title completion state */

        titleChecked = nextChecked

        syncCardState(titleChecked: nextChecked)
    }


    ///
    /// @fcn        CardDetailView.toggleSavedCard()
    /// @brief      Toggle the card's device-local bookmark membership
    /// @details    Inserts or removes the stable card ID in the caller-supplied bookmark binding
    ///
    /// @return     (Void) updates savedCardIDs
    ///
    /// @post       Card content is unchanged; bookmark persistence belongs to the binding owner
    ///
    func toggleSavedCard()
    {


        let isSaved = isCurrentRecordSaved /* Bookmark state before toggling */

        if let currentPersonalCollectionID, /* Current owner used to route relocated Note bookmarking */
        currentPersonalCollectionID != personalCollectionID
        {

            guard onToggleMovedNoteBookmark?(currentPersonalCollectionID, recordID, !isSaved) == true else
            {


                return
            }

            movedNoteIsSaved = !isSaved
        }
        else if isSaved
        {


            savedCardIDs.remove(recordID)
            movedNoteIsSaved = nil
        }
        else
        {


            savedCardIDs.insert(recordID)
            movedNoteIsSaved = nil
        }

    }


    ///
    /// @fcn        CardDetailView.postComment()
    /// @brief      Post a comment to the current card
    /// @details    Ignores empty drafts, appends a timestamped comment, and syncs it to the board
    ///
    /// @return     (Void) appends a trimmed comment and clears a nonblank draft
    ///
    /// @post       Blank input leaves state unchanged; the optional callback receives the updated
    ///             card
    /// @note       This main-card composer currently uses the fixed Justin Reina author name,
    ///             rather than currentUserName used by generated activity and Action Detail
    ///             comments
    ///
    func postComment()
    {


        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized comment draft */

        guard !PlanRichText.plain(text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
        {


            return
        }


        comments.append(KanbanComment(author: "Justin Reina", body: text))
        commentDraft = ""

        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.deleteComment(with:)
    /// @brief      Delete a posted comment from the current card
    /// @details    Removes the comment matching its stable identifier and synchronizes the updated
    ///             card with the board
    ///
    /// @param[in]  commentID  Stable identifier of the comment to remove
    ///
    /// @return     (Void) the comment collection and parent card state are updated in place
    ///
    /// @pre        commentID identifies a comment in the current card
    /// @post       Matching comments are absent locally; persistence after reopening requires the
    ///             parent callback to store the submitted snapshot
    ///
    func deleteComment(with commentID: UUID)
    {


        comments.removeAll
        {
            $0.id == commentID
        }

        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.dismissGeneratedActivity(_:)
    /// @brief      Dismiss one generated activity entry from the current card
    /// @details    Records the entry's stable identifier as dismissed and synchronizes that state
    ///             with the board
    ///
    /// @param[in]  activity  Generated activity entry selected for removal
    ///
    /// @return     (Void) the entry is removed from the rendered Activity feed
    ///
    /// @pre        activity is a generated entry belonging to the current card
    /// @post       The entry is hidden locally; persistence after reopening depends on the parent
    ///             callback
    ///
    func dismissGeneratedActivity(_ activity: GeneratedActivity)
    {


        dismissedActivityIDs.insert(activity.id)
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.resetDate(for:)
    /// @brief      Reset the selected card date to its unset value
    /// @details    Clears only the requested date, synchronizes the card, and closes the calendar
    ///             sheet
    ///
    /// @param[in]  field  The date field to reset
    ///
    /// @return     (Void) clears local date state and submits its explicit clear flag
    ///
    /// @post       The other date is preserved and the active sheet is closed
    ///
    func resetDate(for field: DateField)
    {

        if saveDate(nil, kind: .date, for: field)
        {
            activeSheet = nil
        }

    }


    ///
    /// @fcn        CardDetailView.saveDate
    /// @brief      Save or clear one card schedule endpoint
    /// @details    Normalizes the chosen precision, explicitly signals a cleared endpoint, and restores both dates
    ///             and kinds if card synchronization rejects the change.
    ///
    /// @param[in]  value  Optional schedule value; nil explicitly clears the endpoint
    /// @param[in]  kind   Date, review, or collection kind selecting this operation's behavior
    /// @param[in]  field  Selected editable field or field key path
    ///
    /// @return     (Bool) true when date and kind save together; false after restoring the original selection
    ///
    /// @note       Commit date value and kind together; failed persistence retains the original selection.
    ///
    func saveDate(_ value: Date?, kind: CardDateKind, for field: DateField) -> Bool
    {

        let previousStart = startDate, previousDue = dueDate
        let previousStartKind = startDateKind, previousDueKind = dueDateKind
        let normalized = value.map
        {
            kind.normalized($0)
        }

        switch field
        {

        case .start:
            startDate = normalized;
            startDateKind = value == nil ? .date : kind
        case .due:
            dueDate = normalized;
            dueDateKind = value == nil ? .date : kind
        }

        guard
        syncCardState(clearStartDate: field == .start && value == nil, clearDueDate: field == .due && value == nil)
        else
        {

            startDate = previousStart;
            dueDate = previousDue
            startDateKind = previousStartKind;
            dueDateKind = previousDueKind
            return false
        }

        return true
    }


    ///
    /// @fcn        CardDetailView.moveCardMenu(@ViewBuilder:)
    /// @brief      Build the shared active-list destination menu
    /// @details    Lists supplied destinations and disables the menu when none exist. Selection
    ///             invokes the optional move callback before dismissing detail
    ///
    /// @param[in]  label  View builder providing the menu's visible control
    ///
    /// @return     (some View) destination-list menu
    ///
    /// @pre        availableLists contains appropriate destinations other than the current list
    /// @post       Construction does not move a card; selection dismisses even with no move
    ///             callback
    ///
    @ViewBuilder
    func moveCardMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View
    {

        Menu
        {

            ForEach(availableLists)
            {
                list in
                Button(list.title)
                {

                    onMoveToList?(list.id)
                    dismiss()
                }

            }

        }
        label:
        {

            label()
        }

        .disabled(availableLists.isEmpty)
    }


    ///
    /// @fcn        CardDetailView.moveNote(to:)
    /// @brief      Move the current Note to another personal List
    /// @details    Calls the supplied move operation with the latest card snapshot and updates the
    ///             editor's location and record identity only when that operation succeeds
    ///
    /// @param[in]  collectionID  Identity of the destination personal List
    ///
    /// @return     (Void) keeps the existing location when the move cannot be completed
    ///
    /// @post       Successful moves update the editor's collection identity and List title
    ///
    func moveNote(to collectionID: UUID)
    {


        guard let onMoveNoteToPersonalList,          /* Callback handling checked movement between personal Lists */
        let sourceID = currentPersonalCollectionID,  /* Collection currently owning the Note                      */
        let moved = onMoveNoteToPersonalList(workingCardSnapshot, sourceID, collectionID)
        else
        {  /* Persisted Note with its destination-local identity        */


            return
        }


        movedNoteIsSaved = movedNoteIsSaved ?? savedCardIDs.contains(recordID)
        recordID = moved.id
        currentListTitle = moved.listTitle
        self.currentPersonalCollectionID = collectionID
    }


    ///
    /// @fcn        CardDetailView.personalListDestinationButton(_:)
    /// @brief      Build a menu action for moving a Note to one personal List
    /// @details    Shows the destination name, marks the current List, and disables selection of
    ///             the already active destination
    ///
    /// @param[in]  collection  Candidate personal List destination
    ///
    /// @return     (some View) destination button with current-location state
    ///
    func personalListDestinationButton(_ collection: PersonalCollection) -> some View
    {


        Button
        {

            moveNote(to: collection.id)
        }
        label:
        {

            Label(
                collection.title,
                systemImage: currentPersonalCollectionID == collection.id ? "checkmark" : "folder"
            )
        }
        .disabled(currentPersonalCollectionID == collection.id)
    }


    ///
    /// @fcn        CardDetailView.personalListMenu(label:)
    /// @brief      Build a menu for moving a Note between available personal Lists
    /// @details    Uses the supplied label as the menu trigger, provides one action per active
    ///             destination, and disables movement when no destination or callback is available
    ///
    /// @param[in]  label  View-builder closure that renders the menu trigger
    ///
    /// @return     (some View) List destination menu
    ///
    @ViewBuilder
    func personalListMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View
    {

        Menu
        {

            ForEach(availablePersonalLists)
            {
                collection in
                personalListDestinationButton(collection)
            }

        }
        label:
        {

            label()
        }
        .disabled(availablePersonalLists.isEmpty || onMoveNoteToPersonalList == nil)
    }


    ///
    /// @fcn        CardDetailView.dateRow(for:)
    /// @brief      Build one start-date or due-date row
    /// @details    Opens date picker when tapped & enables swipe-to-remove only while date is set
    ///
    /// @param[in]  field  Date field represented by this row
    ///
    /// @return     (some View) date row with the appropriate add, edit, and removal actions
    ///
    /// @pre        field is either the card's start date or due date
    /// @post       Rendering the row does not modify the stored date
    ///
    @ViewBuilder
    func dateRow(for field: DateField) -> some View
    {


        let currentDate = field == .start ? startDate : dueDate /* Date currently stored for the selected field */
        let timeOnly = workingCardSnapshot.usesTimeOnlySchedule(on: listedOnDate)
        let iconName =
        timeOnly
        ? (field == .start ? "clock" : "checkmark.circle")
        : (field == .start ? "calendar" : "calendar.badge.clock")
        let title = timeOnly ? (field == .start ? "Start" : "Finish") : field.title
        let kind = field == .start ? startDateKind : dueDateKind
        let dateLabel = currentDate.map
        {
            (timeOnly ? CardDateKind.time : kind).label(for: $0)
        }
        ?? "Add date"
        let fieldName = field.title.lowercased() /* Accessibility label value */

        let row = HStack(alignment: .center)
        {  /* Shared date-row presentation */


            Image(systemName: iconName)
            .foregroundStyle(.secondary)

            Text(title)
            .font(.body)

            Spacer()

            Button
            {


                activeSheet = .date(field)
            }
            label:
            {

                Text(dateLabel)
            }

            .buttonStyle(.plain)
            .accessibilityLabel("\(currentDate == nil ? "Add" : "Edit") \(fieldName)")
        }


        if currentDate != nil
        {


            ActivitySwipeRow(
                onDelete:
                {
                    resetDate(for: field)
                },
                deletionAccessibilityLabel: "Remove \(fieldName)"
            )
            {

                row
            }

        }
        else
        {

            row
        }

    }


    ///
    /// @fcn        CardDetailView.addChecklist(using:)
    /// @brief      Append a new empty checklist to the selected card's detail state
    /// @details    Adds a default checklist with its first item, syncs it to the card, scrolls it
    ///             into view, and focuses the item
    ///
    /// @param[in]  scrollProxy  Proxy used to scroll the new checklist into view
    ///
    /// @return     (Void) appends and synchronizes a checklist, then schedules scrolling
    ///
    /// @post       The new checklist's first item is visible and ready for editing
    ///
    func addChecklist(using scrollProxy: ScrollViewProxy)
    {


        let checklist = KanbanChecklist(title: "Checklist", items: [""]) /* New checklist with an initial item */

        checklists.append(checklist)

        checklistToFocus = checklist.id

        syncCardState()

        DispatchQueue.main.async
        {


            withAnimation(.easeInOut)
            {

                scrollProxy.scrollTo(checklist.id, anchor: .center)
            }

        }

    }


    ///
    /// @fcn        CardDetailView.deleteChecklist(with:)
    /// @brief      Remove a checklist from the selected card's detail state
    /// @details    Filters the checklist collection by its stable identifier
    ///
    /// @param[in]  checklistID  Identifier of the checklist to remove
    ///
    /// @return     (Void) removes matching checklists and emits the current card snapshot
    ///
    /// @post       The selected checklist is no longer rendered in the Checklists section
    ///
    func deleteChecklist(with checklistID: UUID)
    {


        checklists.removeAll
        {
            $0.id == checklistID
        }


        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.renameChecklist(with:to:)
    /// @brief      Rename a checklist on the current card
    /// @details    Trims the proposed title, preserves the checklist's items and completion state,
    ///             and syncs the card
    ///
    /// @param[in]  checklistID  Stable identifier of the checklist to rename
    /// @param[in]  title        Proposed checklist title
    ///
    /// @return     (Void) updates the checklist and parent card when the title is non-empty
    ///
    /// @pre        checklistID identifies a checklist in the current card
    /// @post       The checklist displays the trimmed title; blank titles leave state unchanged
    ///
    func renameChecklist(with checklistID: UUID, to title: String)
    {


        guard
        let checklistIndex = checklists.firstIndex(where:
            {  /* Position of the checklist to rename */


                $0.id == checklistID
            })
        else
        {


            return
        }


        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized checklist title */

        guard !trimmedTitle.isEmpty else
        {


            return
        }


        let checklist = checklists[checklistIndex] /* Current checklist snapshot */

        checklists[checklistIndex] = KanbanChecklist(
            id: checklist.id,
            title: trimmedTitle,
            items: checklist.items,
            completedItemIndices: checklist.completedItemIndices
        )
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.toggleAllItems(in:)
    /// @brief      Check every item or clear all checks in one checklist
    /// @details    Clears completion for a nonempty checklist whose every item is checked;
    ///             otherwise checks every item, including blank-title actions
    ///
    /// @param[in]  checklistID  Stable identifier of the checklist to update
    ///
    /// @return     (Void) updates item completion state and synchronizes the card
    ///
    /// @pre        checklistID identifies a checklist on the current card
    /// @post       All items are checked, or all are unchecked when they were already all checked
    ///
    func toggleAllItems(in checklistID: UUID)
    {


        guard
        let checklistIndex = checklists.firstIndex(
            where:
            {  /* Checklist whose action completion states are toggled together */


                $0.id == checklistID
            })
        else
        {


            return
        }


        let checklist = checklists[checklistIndex] /* Current checklist snapshot      */
        let allItemsAreCompleted =
        !checklist.items.isEmpty
        && checklist.completedItemIndices.count == checklist.items.count /* Whether all items are complete  */
        let completedIndices =
        allItemsAreCompleted ? Set<Int>() : Set(checklist.items.indices) /* Completion indices after toggle */

        checklists[checklistIndex] = KanbanChecklist(
            id: checklist.id,
            title: checklist.title,
            items: checklist.items,
            completedItemIndices: completedIndices
        )

        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.moveChecklist(with:direction:)
    /// @brief      Move a checklist to an adjacent or absolute position
    /// @details    Removes the selected checklist and reinserts it at the requested position
    ///
    /// @param[in]  checklistID  Stable identifier of the checklist to move
    /// @param[in]  direction    Requested destination from ChecklistMoveDirection
    ///
    /// @return     (Void) updates checklist order and synchronizes the card
    ///
    /// @pre        checklistID identifies a checklist on the current card
    /// @post       The checklist occupies the requested position; boundary and single-checklist
    ///             moves leave order unchanged
    ///
    func moveChecklist(with checklistID: UUID, direction: ChecklistMoveDirection)
    {


        // Ensure the checklist exists and there is more than one checklist to move
        guard
        let sourceIndex = checklists.firstIndex(where:
            {  /* Checklist position before reordering */


                $0.id == checklistID
            }), /* Current checklist position */
        checklists.count > 1
        else
        {


            return
        }


        let destinationIndex: Int /* Position resolved from the requested direction */

        switch direction
        {


        case .top:
            destinationIndex = 0
        case .up:
            destinationIndex = max(sourceIndex - 1, 0)
        case .down:
            destinationIndex = min(sourceIndex + 1, checklists.count - 1)
        case .bottom:
            destinationIndex = checklists.count - 1
        }


        guard sourceIndex != destinationIndex else
        {


            return
        }


        let movedChecklist = checklists.remove(at: sourceIndex) /* Checklist temporarily removed for reinsertion */

        checklists.insert(movedChecklist, at: destinationIndex)

        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.addItem(to:)
    /// @brief      Append a new item to a checklist
    /// @details    Appends one action per nonblank line while preserving existing records and completion states
    ///
    /// @param[in]  checklistID  Identifier of the checklist receiving the new item
    ///
    /// @param[in]  text         Submitted checklist action writing, including supported multiline input
    ///
    /// @return     (Void) updates the matching checklist and submits the card snapshot
    ///
    /// @post       The new item appears above the checklist's Add item... control
    ///
    func addItem(to checklistID: UUID, text: String)
    {


        // Find the index of the checklist to which the new item will be added
        guard
        let checklistIndex = checklists.firstIndex(where:
            {  /* Checklist receiving the new action */


                $0.id == checklistID
            })
        else
        {  /* Target checklist position */


            return
        }


        let titles = MultilineEntry.titles(text)
        guard !titles.isEmpty else
        {
            return
        }

        let checklist = checklists[checklistIndex]
        checklists[checklistIndex] = KanbanChecklist(
            id: checklist.id, title: checklist.title,
            items: checklist.items + titles.map
            {
                KanbanChecklistItem(title: $0)
            },
            completedItemIndices: checklist.completedItemIndices
        )
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.toggleItem(in:at:)
    /// @brief      Toggle one checklist item's completion state
    /// @details    Replaces the matching value-type checklist with updated completed item indices
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being toggled
    ///
    /// @return     (Void) replaces completion state and emits the updated card snapshot
    ///
    /// @pre        The caller supplies a valid current itemIndex; only checklist existence is
    ///             guarded here
    /// @post       The selected item changes between complete and incomplete
    ///
    func toggleItem(in checklistID: UUID, at itemIndex: Int)
    {


        // Find the index of the checklist being updated
        guard
        let checklistIndex = checklists.firstIndex(where:
            {  /* Checklist containing the action to toggle */


                $0.id == checklistID
            })
        else
        {  /* Checklist being toggled */


            return
        }


        let checklist = checklists[checklistIndex]                 /* Checklist being updated               */
        var completedItemIndices = checklist.completedItemIndices  /* Mutable set of completed item indices */

        // Toggle the completion state of the specified item within the checklist
        if completedItemIndices.contains(itemIndex)
        {


            completedItemIndices.remove(itemIndex)
        }
        else
        {


            completedItemIndices.insert(itemIndex)
        }


        // Update the checklist with the new set of completed item indices
        checklists[checklistIndex] = KanbanChecklist(
            id: checklist.id,
            title: checklist.title,
            items: checklist.items,
            completedItemIndices: completedItemIndices
        )
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.updateItem(in:at:with:)
    /// @brief      Update one checklist item's text
    /// @details    Replaces the matching value-type checklist with an updated item label
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being edited
    /// @param[in]  text         New display text for the item
    ///
    /// @return     (Void) updates the item title and submits the card snapshot
    ///
    /// @post       The edited text is displayed in the checklist row
    /// @note       Missing checklists or out-of-range indices leave state unchanged; text is not
    ///             trimmed
    ///
    func updateItem(in checklistID: UUID, at itemIndex: Int, with text: String)
    {


        // Find the index of the checklist being updated
        guard
        let checklistIndex = checklists.firstIndex(where:
            {  /* Checklist containing the action to replace */


                $0.id == checklistID
            })
        else
        {  /* Checklist being edited */


            return
        }


        // Retrieve the checklist being updated
        let checklist = checklists[checklistIndex] /* Checklist being edited */

        // Ensure the item index is within the bounds of the checklist's items array
        guard checklist.items.indices.contains(itemIndex) else
        {


            return
        }


        var items = checklist.items /* Mutable checklist actions */

        items[itemIndex].title = text /* Update the text while preserving stable item identity       */

        // Update the checklist with the modified items array
        checklists[checklistIndex] = KanbanChecklist(
            id: checklist.id,
            title: checklist.title,
            items: items,
            completedItemIndices: checklist.completedItemIndices
        )
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.deleteItem(in:at:)
    /// @brief      Delete one checklist item
    /// @details    Removes the item and shifts completed item indices that follow it
    ///
    /// @param[in]  checklistID  Identifier of the checklist being updated
    /// @param[in]  itemIndex    Zero-based index of the item being deleted
    ///
    /// @return     (Void) removes the record and submits the card snapshot
    ///
    /// @post       The selected item is removed from the checklist
    /// @note       Missing checklists or out-of-range indices leave state unchanged
    ///
    func deleteItem(in checklistID: UUID, at itemIndex: Int)
    {


        // Find the index of the checklist being updated
        guard
        let checklistIndex = checklists.firstIndex(where:
            {  /* Checklist containing the action to delete */


                $0.id == checklistID
            })
        else
        {  /* Checklist being edited */


            return
        }


        // Retrieve the checklist being updated
        let checklist = checklists[checklistIndex] /* Checklist before item removal */

        // Ensure the item index is within the bounds of the checklist's items array
        guard checklist.items.indices.contains(itemIndex) else
        {


            return
        }


        var items = checklist.items /* Mutable checklist actions */

        items.remove(at: itemIndex) /* Remove the specified item from the checklist    */

        // Recalculate the set of completed item indices after the deletion
        let completedItemIndices: Set<Int> = Set( /* Completion indices adjusted for removal */

            checklist.completedItemIndices.compactMap
            {
            (index: Int) -> Int? in /* Previous completion position */

                // Skip the index if it matches the deleted item index
                guard index != itemIndex else
                {


                    return nil
                }


                return index > itemIndex ? index - 1 : index
            }
        )

        // Update the checklist with the recalculated completed item indices
        checklists[checklistIndex] = KanbanChecklist(
            id: checklist.id,
            title: checklist.title,
            items: items,
            completedItemIndices: completedItemIndices
        )
        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.updateActionDetail(checklistID:itemID:detail:)
    /// @brief      Save reduced detail content into its owning checklist action
    /// @details    Replaces only the selected item's content while preserving checklist and item
    ///             identity
    ///
    /// @param[in]  checklistID  Stable identity of the containing checklist
    /// @param[in]  itemID       Stable identity of the owning checklist action
    /// @param[in]  detail       Updated reduced detail content
    ///
    /// @return     (Void) updates checklist state and synchronizes the parent card
    ///
    /// @pre        checklistID and itemID identify an Action Detail item on the current card
    /// @post       The parent card contains the updated Action Detail when both IDs resolve
    ///
    func updateActionDetail(checklistID: UUID, itemID: UUID, detail: KanbanChecklistActionDetail)
    {


        guard
        let checklistIndex = checklists.firstIndex(
            where:
            {  /* Position of the checklist containing the requested action */


                $0.id == checklistID
            })
        else
        {


            return
        }


        let checklist = checklists[checklistIndex] /* Owning checklist */

        guard
        let itemIndex = checklist.items.firstIndex(where:
            {  /* Position of the requested checklist action */


                $0.id == itemID
            })
        else
        {


            return
        }


        var items = checklist.items /* Mutable checklist actions */

        items[itemIndex].content = .actionDetail(detail)

        checklists[checklistIndex] = KanbanChecklist(
            id: checklist.id,
            title: checklist.title,
            items: items
        )

        syncCardState()
    }


    ///
    /// @fcn        CardDetailView.checklistBlock(for:)
    /// @brief      Build a checklist block wired to card checklist actions
    /// @details    Connects row actions to checklist state handlers and supplies the one-time
    ///             first-item focus request
    ///
    /// @param[in]  checklist  Checklist data and identity used to configure the block
    ///
    /// @return     (some View) identified checklist block with edit, completion, add, delete, and
    ///             rename actions
    ///
    /// @pre        checklist belongs to the current card's checklist collection
    /// @post       Rendering the block does not mutate checklist state
    ///
    @ViewBuilder
    func checklistBlock(for checklist: KanbanChecklist) -> some View
    {


        let checklistIndex =
        checklists.firstIndex(where:
            {
                $0.id == checklist.id
            }) ?? 0 /* Current checklist position */

        ChecklistBlock(
            checklist: checklist,
            linkedCardsByID: linkedCardsByID,
            onDelete:
            {


                deleteChecklist(with: checklist.id)
            },
            onAddItem:
            {
                text in
                addItem(to: checklist.id, text: text)
            },
            onToggleItem:
            {
                itemIndex in
                toggleItem(in: checklist.id, at: itemIndex)
            },
            onUpdateItem:
            {
                itemIndex, text in
                updateItem(in: checklist.id, at: itemIndex, with: text)
            },
            onDeleteItem:
            {
                itemIndex in
                deleteItem(in: checklist.id, at: itemIndex)
            },
            onOpenActionDetail:
            {
                itemID in
                activeSheet = .actionDetail(checklist.id, itemID)
            },
            onRename:
            {
                title in
                renameChecklist(with: checklist.id, to: title)
            },
            onToggleAllItems:
            {

                toggleAllItems(in: checklist.id)
            },
            onMove:
            {
                direction in
                moveChecklist(with: checklist.id, direction: direction)
            },
            canMoveUp: checklistIndex > 0,
            canMoveDown: checklistIndex < checklists.count - 1,
            focusFirstItem: checklist.id == checklistToFocus,
            onFirstItemFocused:
            {

                checklistToFocus = nil
            },
            onChangeType:
            {
                item in
                guard let index = checklists.firstIndex(where:
                    {
                        $0.id == checklist.id
                    }),
                let position = checklists[index].items.firstIndex(where:
                    {
                        $0.id == item.id
                    })
                else
                {
                    return false
                }

                let previous = checklists
                var items = checklists[index].items
                var updated = item
                if case .linkedCard = updated.content, updated.linkedCollectionID == nil
                {

                    updated.linkedCollectionID =
                    checklistCollectionID
                    ?? checklistTypePlanningAccess?.document.weeks.first(where:
                        {

                            $0.startKey == checklistTypePlanningAccess?.document.currentWeekKey
                        })?.id
                }

                items[position] = updated
                checklists[index] = KanbanChecklist(
                    id: checklist.id, title: checklists[index].title, items: items,
                    completedItemIndices: checklists[index].completedItemIndices)
                if !syncCardState()
                {
                    checklists = previous;
                    return false
                }

                return true
            }
        )
        .id(checklist.id)
    }


    ///
    /// @fcn        CardDetailView.saveDisplayAppearance(_:format:)
    /// @brief      Save display and decoration together while retaining the complete record
    /// @details    Rejected updates restore the local draft and keep Appearance open
    /// @param[in]  updated  Proposed appearance overrides, or nil to restore inherited styling
    /// @param[in]  format   Explicit Card, Note, or picture preview format to retain with the
    ///             appearance
    ///
    /// @return     (Bool) whether the canonical update accepted the snapshot
    ///
    func saveDisplayAppearance(_ updated: ItemAppearance?, format: ItemDisplayFormat) -> Bool
    {

        let previousAppearance = appearance
        let previousFormat = displayFormat
        let previousPresentation = presentation
        let previousDescription = descriptionText
        let previousDetails = showsNoteDetails
        dismissEditing()
        appearance = updated
        displayFormat = format
        presentation = [.note, .title, .text].contains(format) ? .note : .card
        showsNoteDetails = false
        if !hasEditedDescription
        {

            descriptionText = presentation == .note ? (card.descriptionOverride ?? "") : card.funParagraph
        }

        guard syncCardState() else
        {

            appearance = previousAppearance
            displayFormat = previousFormat
            presentation = previousPresentation
            descriptionText = previousDescription
            showsNoteDetails = previousDetails
            return false
        }

        return true
    }


    ///
    /// @fcn        CardDetailView.cardCoverPanel(onDone:)
    /// @brief      Present the current item's cover controls
    /// @details    Wraps the shared cover controls in a sheet-sized navigation surface with an
    ///             explicit Done action and database error presentation.
    ///
    /// @param[in]  onDone  Action invoked by the cover panel's Done button
    ///
    /// @return     (some View) cover editing panel
    ///
    func cardCoverPanel(onDone: @escaping () -> Void) -> some View
    {

        NavigationStack
        {

            ScrollView
            {
                coverControls
            }
            .navigationTitle("Card Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .confirmationAction)
                {
                    Button("Done", action: onDone)
                }

            }

        }
        .presentationDetents([.medium, .large])
        .databaseActivityOverlay()
    }


    ///
    /// @fcn        CardDetailView.addMenu
    /// @brief      Build the card or note's contextual Add menu
    /// @details    Provides reaction, cover, checklist, date, and comment actions while excluding
    ///             presentation-specific actions for dividers.
    ///
    /// @param[in]  scrollProxy  Proxy used to reveal newly added content in the detail view
    ///
    /// @return     (some View) the card or note's contextual add menu
    ///
    func addMenu(using scrollProxy: ScrollViewProxy) -> some View
    {

        Menu
        {

            if displayFormat != .divider
            {

                Button("Add reaction", systemImage: "face.smiling")
                {

                    dismissEditing()
                    activeSheet = .reactions
                }

                Button(workingCardSnapshot.coverAttachment == nil ? "Add cover" : "Change cover", systemImage: "photo")
                {

                    dismissEditing()
                    activeSheet = .cover
                }

            }


            Button
            {

                showsNoteDetails = true
                addChecklist(using: scrollProxy)
            }
            label:
            {

                Label("Add checklist", systemImage: "checklist")
            }

            Button
            {

                activeSheet = .date(.start)
            }
            label:
            {

                Label(startDate == nil ? "Add start date" : "Edit start date", systemImage: "calendar")
            }

            Button
            {

                activeSheet = .date(.due)
            }
            label:
            {

                Label(dueDate == nil ? "Add due date" : "Edit due date", systemImage: "calendar.badge.clock")
            }

            Button
            {

                showsNoteDetails = true
                richTextFocusedField = .comment
            }
            label:
            {

                Label("Add comment", systemImage: "text.bubble")
            }

        }
        label:
        {

            Image(systemName: "plus.circle")
            .font(.title2)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Add to \(displayFormat.title.lowercased())")
        .accessibilityIdentifier("note.addMenu")
    }

}
