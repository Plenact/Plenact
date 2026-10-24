// --------------------------------------------------------------------------------------------------
// @file       AttachmentViews.swift
// @brief      Media sources, galleries, captions, ordering, and playback
// @details    Presents retained attachments and delegates accepted mutations to the current owner
//             rather than modifying snapshots implicitly.
//
// --------------------------------------------------------------------------------------------------
import AVKit
import Foundation
import ImageIO
import PencilKit
import PhotosUI
import SwiftUI
import UIKit


///
/// Identifies the attachment sources available from card detail
///
/// @section    Purpose
///     Provide stable source identities and display metadata for the attachment picker
///
enum CardAttachmentSource: String, CaseIterable, Identifiable
{


    case trello
    case confluence
    case jira
    case file
    case documentScanner
    case qrCode
    case camera
    case photoOrVideo
    case drawing
    case link
    case clipboard

    ///
    /// @fcn        CardAttachmentSource.id
    /// @brief      Expose the source token as its stable identity
    /// @details    Reuses the enum raw value for picker rows
    ///
    /// @return     (String) attachment-source identifier
    ///
    var id: String
    {
        rawValue
    }  /* Stable picker identity */


    ///
    /// @fcn        CardAttachmentSource.title
    /// @brief      Return the display title for an attachment source
    /// @details    Maps each source case to its picker-row label
    ///
    /// @return     (String) display text defined for the source
    ///
    var title: String
    {  /* User-facing attachment-source label */

        switch self
        {


        case .trello:
                    "Trello"
        case .confluence:
                    "Confluence"
        case .jira:
                    "Jira"
        case .file:
                    "File"
        case .documentScanner:
                    "Document scanner"
        case .qrCode:
                    "QR code"
        case .camera:
                    "Camera"
        case .photoOrVideo:
                    "Photo or video"
        case .drawing:
                    "Drawing"
        case .link:
                    "Link"
        case .clipboard:
                    "Clipboard"
        }

    }


    ///
    /// @fcn        CardAttachmentSource.symbolName
    /// @brief      Return the SF Symbol name for an attachment source
    /// @details    Maps each source case to the icon shown in the picker
    ///
    /// @return     (String) SF Symbol identifier for the source
    ///
    var symbolName: String
    {  /* SF Symbol for the picker row */

        switch self
        {


        case .trello:
                    "square.split.2x2"
        case .confluence:
                    "water.waves"
        case .jira:
                    "checkmark.circle"
        case .file:
                    "paperclip"
        case .documentScanner:
                    "doc.viewfinder"
        case .qrCode:
                    "qrcode.viewfinder"
        case .camera:
                    "camera"
        case .photoOrVideo:
                    "photo.on.rectangle"
        case .drawing:
                    "pencil.tip"
        case .link:
                    "link"
        case .clipboard:
                    "doc.on.clipboard"
        }

    }

}


///
/// Presents supported attachment sources and dispatches the selected action
///
/// @section    Purpose
///     Connect photo selection, link entry, clipboard import, and unavailable source notices
///
struct CardAttachmentSourceSheet: View
{


    @Binding var photoSelection: [PhotosPickerItem] /* Current Photos-picker selection */

    let onAddLink:        () -> Void           /* Callback opening manual link entry                    */
    let onPasteClipboard: () -> Void           /* Callback importing clipboard images or a link         */
    let onComingSoon:     (String) -> Void     /* Callback reporting unsupported source                 */
    var onAddDrawing:     (() -> Void)? = nil  /* Opens the editable canvas when supported by the owner */

    @Environment(\.dismiss) private var dismiss /* Sheet dismissal action */


    ///
    /// @fcn        CardAttachmentSourceSheet.select(_:)
    /// @brief      Dispatch the action associated with one attachment source
    /// @details    Invokes link or clipboard callbacks, leaves photo selection to PhotosPicker, and
    ///             reports unsupported source choices
    ///
    /// @param[in]  source  Selected attachment source
    ///
    /// @return     (Void) invokes the matching callback or system picker
    ///
    /// @pre        source is one of the available attachment sources
    /// @post       The corresponding callback is invoked where applicable
    ///
    private func select(_ source: CardAttachmentSource)
    {


        switch source
        {


        case .drawing:
            if let onAddDrawing
            {
                onAddDrawing()
            }
            else
            {
                onComingSoon(source.title)
            }

        case .link:
            onAddLink()
        case .clipboard:
            onPasteClipboard()
            dismiss()
        case .photoOrVideo:
            break
        default:
            onComingSoon(source.title)
        }

    }


    ///
    /// @fcn        CardAttachmentSourceSheet.body
    /// @brief      Build the attachment-source picker
    /// @details    Presents PhotosPicker for media and dispatches the other source actions
    ///
    /// @return     (some View) attachment-source sheet
    ///
    /// @pre        The selection binding and action callbacks are configured
    /// @post       Selecting a source dispatches its supported action
    ///
    var body: some View
    {  /* Attachment-source picker */


        NavigationStack
        {


            List
            {


                ForEach(CardAttachmentSource.allCases)
                {
                    source in

                    if source == .photoOrVideo
                    {


                        PhotosPicker(
                            selection: $photoSelection, maxSelectionCount: 12, matching: .any(of: [.images, .videos])
                        )
                        {

                            Label(source.title, systemImage: source.symbolName)
                            .foregroundStyle(.primary)
                        }

                    }
                    else
                    {


                        Button
                        {

                            select(source)
                        }
                        label:
                        {

                            Label(source.title, systemImage: source.symbolName)
                            .foregroundStyle(.primary)
                        }

                    }

                }

            }

            .navigationTitle("Add attachment from")
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

        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

}


///
/// Collects and validates a web address to attach to a card
///
/// @section    Purpose
///     Accept a valid URL and return it to the owning card-detail view
///
struct CardLinkAttachmentSheet: View
{


    let onSave: (URL) -> Void /* Callback receiving the validated URL */

    @Environment(\.dismiss) private var dismiss  /* Sheet dismissal action */
    @State private var urlDraft = ""             /* User-entered URL text  */

    ///
    /// @fcn        CardLinkAttachmentSheet.validatedURL
    /// @brief      Return the parsed URL when the current draft is valid
    /// @details    Delegates URL validation to CardAttachmentStore
    ///
    /// @return     (URL?) valid HTTP or HTTPS URL, or nil for invalid draft text
    ///
    private var validatedURL: URL?
    {  /* Parsed URL when the draft is valid */

        CardAttachmentStore.webURL(from: urlDraft)
    }


    ///
    /// @fcn        CardLinkAttachmentSheet.body
    /// @brief      Build the manual web-link form
    /// @details    Collects URL text and enables submission only when validation succeeds
    ///
    /// @return     (some View) link-entry sheet with Cancel and Add actions
    ///
    /// @pre        The save callback and dismissal environment are available
    /// @post       A valid submitted URL is passed to the save callback
    ///
    var body: some View
    {  /* Manual web-link form */


        NavigationStack
        {


            Form
            {


                Section("Link")
                {


                    TextField("https://example.com", text: $urlDraft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(saveLink)
                }

            }

            .navigationTitle("Add link")
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


                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Add")
                    {

                        saveLink()
                    }

                    .disabled(validatedURL == nil)
                }

            }

        }

        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }


    ///
    /// @fcn        CardLinkAttachmentSheet.saveLink()
    /// @brief      Submit the entered URL when it passes web-link validation
    /// @details    Calls the owner callback and dismisses the sheet for a valid draft
    ///
    /// @return     (Void) invokes the save callback and dismisses the sheet
    ///
    /// @pre        The draft has a validated URL
    /// @post       The callback receives that URL and the sheet is dismissed
    ///
    private func saveLink()
    {


        guard let validatedURL else
        {  /* Validated attachment URL */


            return
        }  /* Require a valid web address */


        onSave(validatedURL)

        dismiss()
    }

}


///
/// Presents photo attachments and their available actions
///
/// @section    Purpose
///     Delegates caption, ordering, removal, and cover selection to the owner while retaining
///     native attachment opening and photo selection.
///
struct CardPhotoGallery: View
{


    let photos:                  [KanbanAttachment]
    @Binding var photoSelection: [PhotosPickerItem]
    let onOpen:                  (KanbanAttachment) -> Void
    let onCaption:               (UUID, String) -> Bool
    let onReorder:               ([UUID]) -> Bool
    let onRemove:                (KanbanAttachment) -> Void
    let onSetCover:              (UUID) -> Void

    @ScaledMetric(relativeTo: .body) private var photoWidth = 220
    @ScaledMetric(relativeTo: .body) private var photoHeight = 180
    @State private var captionPhoto: KanbanAttachment?
    @State private var removalPhoto: KanbanAttachment?
    @State private var showsArrangement = false

    var body: some View
    {

        VStack(alignment: .leading, spacing: 12)
        {

            ViewThatFits(in: .horizontal)
            {

                HStack
                {

                    Text("Gallery").font(.headline)
                    Spacer()
                    galleryControls
                }

                VStack(alignment: .leading, spacing: 8)
                {

                    Text("Gallery").font(.headline)
                    galleryControls
                }

            }

            ScrollView(.horizontal)
            {

                LazyHStack(alignment: .top, spacing: 12)
                {

                    ForEach(Array(photos.enumerated()), id: \.element.id)
                    {
                        index, photo in
                        photoTile(photo, index: index)
                    }

                }

            }
            .accessibilityIdentifier("photoGallery.row")
        }
        .accessibilityIdentifier("photoGallery")
        .sheet(item: $captionPhoto)
        {
            photo in
            CardPhotoCaptionSheet(photo: photo)
            {
                onCaption(photo.id, $0)
            }
            .databaseActivityOverlay()
        }
        .sheet(isPresented: $showsArrangement)
        {

            CardPhotoArrangementSheet(photos: photos, onReorder: onReorder)
            .databaseActivityOverlay()
        }
        .confirmationDialog(
                        "Remove this photo?",
                        isPresented: Binding(
                            get:
                            {
                                removalPhoto != nil
                            },
                            set:
                            {
                                if !$0
                                {
                                    removalPhoto = nil
                                }

                            }
                        ), titleVisibility: .visible
        )
        {

            if let photo = removalPhoto
            {

                Button("Remove photo", role: .destructive)
                {

                    onRemove(photo)
                    removalPhoto = nil
                }

            }

            Button("Cancel", role: .cancel)
            {
                removalPhoto = nil
            }

        }
        message:
        {

            Text("Removes the photo and its caption from this item. Photos retained elsewhere are kept.")
        }

    }


    private var galleryControls: some View
    {

        HStack(spacing: 12)
        {

            Button("Arrange", systemImage: "arrow.left.arrow.right")
            {

                showsArrangement = true
            }
            .disabled(photos.count < 2)
            .accessibilityLabel("Arrange gallery photos")
            .accessibilityIdentifier("photoGallery.arrange")
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 12, matching: .images)
            {

                Label("Add photos", systemImage: "photo.badge.plus")
            }
            .accessibilityIdentifier("photoGallery.add")
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }


    ///
    /// @fcn        CardPhotoGallery.photoTile
    /// @brief      Build one photo-gallery tile and its actions
    /// @details    Uses the attachment and gallery position for the photo preview, caption, and gallery controls.
    ///             Touch and hold exposes Set as Cover through the existing owner callback; tapping opens the photo
    ///             and dragging still reorders it. The cover action is also available to accessibility users.
    ///
    /// @param[in]  photo  Photo attachment represented by the editor or gallery tile
    /// @param[in]  index  Current zero-based gallery photo index
    ///
    /// @return     (some View) one photo-gallery tile and its actions
    ///
    private func photoTile(_ photo: KanbanAttachment, index: Int) -> some View
    {

        VStack(alignment: .leading, spacing: 0)
        {

            Button
            {

                onOpen(photo)
            }
            label:
            {

                CardCoverPreview(attachment: photo, height: photoHeight, unavailableTitle: "Photo unavailable")
                .overlay(alignment: .bottomLeading)
                {

                    if let caption = photo.caption, !caption.isEmpty
                    {

                        Text(caption)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background
                        {

                            LinearGradient(
                                colors: [.black.opacity(0.7), .black.opacity(0.95)],
                                startPoint: .top, endPoint: .bottom)
                        }

                    }

                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo \(index + 1)")
            .accessibilityValue(photo.caption ?? "No caption")
            .accessibilityHint(
                                    "Opens the full photo. Touch and hold to set it as the cover, or drag it to another gallery position."
            )
            .accessibilityIdentifier("photoGallery.photo.\(photo.id)")
            .accessibilityAction(named: Text("Set as Cover"))
            {
                onSetCover(photo.id)
            }
            .contextMenu
            {

                Button("Set as Cover", systemImage: "photo")
                {
                    onSetCover(photo.id)
                }

            }
            .draggable("plenact.gallery.\(photo.id.uuidString)")
            .dropDestination(for: String.self)
            {
                items, _ in
                guard items.count == 1,
                let token = items.first,
                token.hasPrefix("plenact.gallery."),
                let id = UUID(uuidString: String(token.dropFirst("plenact.gallery.".count))),
                let source = photos.firstIndex(where:
                    {
                        $0.id == id
                    }),
                id != photo.id
                else
                {
                    return false
                }

                var ids = photos.map(\.id)
                ids.remove(at: source)
                ids.insert(id, at: index)
                return onReorder(ids)
            }

            HStack
            {

                Text("Photo \(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Menu
                {

                    Button(photo.caption == nil ? "Add caption" : "Edit caption", systemImage: "text.bubble")
                    {

                        captionPhoto = photo
                    }

                    Button("Move earlier", systemImage: "arrow.left")
                    {
                        movePhoto(index, by: -1)
                    }
                    .disabled(index == 0)
                    Button("Move later", systemImage: "arrow.right")
                    {
                        movePhoto(index, by: 1)
                    }
                    .disabled(index == photos.count - 1)
                    Button("Set as Cover", systemImage: "photo")
                    {
                        onSetCover(photo.id)
                    }

                    Button("Remove photo", systemImage: "trash", role: .destructive)
                    {
                        removalPhoto = photo
                    }

                }
                label:
                {

                    Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for photo \(index + 1)")
                .accessibilityIdentifier("photoGallery.options.\(photo.id)")
            }

        }
        .frame(width: photoWidth)
    }


    ///
    /// @fcn        CardPhotoGallery.movePhoto
    /// @brief      Request a relative gallery-photo move
    /// @details    Builds the revised photo ID ordering for the requested offset and uses the checked reorder
    ///             callback before accepting a change.
    ///
    /// @param[in]  index   Current zero-based gallery photo index
    /// @param[in]  offset  Relative section or photo movement, or normalized scroll displacement
    ///
    /// @return     (Void) no return value
    ///
    private func movePhoto(_ index: Int, by offset: Int)
    {

        var ids = photos.map(\.id)
        ids.swapAt(index, index + offset)
        _ = onReorder(ids)
    }

}


///
/// Edits one photo caption before saving
///
/// @section    Purpose
///     Seeds local writing from the attachment and dismisses only when the owner's checked callback
///     accepts it.
///
struct CardPhotoCaptionSheet: View
{


    let photo:                  KanbanAttachment
    let onSave:                 (String) -> Bool
    @State private var caption: String
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        CardPhotoCaptionSheet.init
    /// @brief      Seed photo-caption editing from its attachment
    /// @details    Retains the photo and checked save callback and uses an empty draft caption when the attachment
    ///             has none.
    ///
    /// @param[in]  photo   Photo attachment represented by the editor or gallery tile
    /// @param[in]  onSave  Save callback returning true only when the owner accepts the edited value
    ///
    /// @return     (CardPhotoCaptionSheet) initialized instance
    ///
    init(photo: KanbanAttachment, onSave: @escaping (String) -> Bool)
    {

        self.photo = photo
        self.onSave = onSave
        _caption = State(initialValue: photo.caption ?? "")
    }


    var body: some View
    {

        NavigationStack
        {

            Form
            {

                Section
                {

                    CardCoverPreview(attachment: photo, height: 180, unavailableTitle: "Photo unavailable")
                }

                Section("Caption")
                {

                    TextField("Optional caption", text: $caption, axis: .vertical).textInputAutocapitalization(
                        .sentences
                    )
                    .accessibilityIdentifier("photoGallery.captionField")
                    Text("Shown over the bottom of the photo. Clear the text to remove its caption.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Photo caption")
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

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Save")
                    {
                        if onSave(caption)
                        {
                            dismiss()
                        }

                    }
                    .accessibilityIdentifier("photoGallery.saveCaption")
                }

            }

        }

    }

}


///
/// Edits the order of retained photo attachments
///
/// @section    Purpose
///     Publishes an ordered identity list through the checked callback rather than rewriting
///     attachment records locally.
///
struct CardPhotoArrangementSheet: View
{


    let photos:    [KanbanAttachment]
    let onReorder: ([UUID]) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View
    {

        NavigationStack
        {

            List
            {

                Section
                {

                    ForEach(Array(photos.enumerated()), id: \.element.id)
                    {
                        index, photo in
                        HStack(spacing: 12)
                        {

                            CardCoverPreview(attachment: photo, height: 64, unavailableTitle: "Photo unavailable")
                            .frame(width: 80)
                            Text(photo.caption ?? "Photo \(index + 1)")
                        }

                    }
                    .onMove
                    {
                        source, destination in
                        var ids = photos.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        _ = onReorder(ids)
                    }

                }
                footer:
                {

                    Text(
                                                            "Drag the handles to arrange photos. The cover stays separate. Changes are saved as you move photos."
                    )
                }

            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Done")
                    {
                        dismiss()
                    }

                }

            }

        }

    }

}


///
/// Displays a square thumbnail for an attached card item
///
/// @section    Purpose
///     Provide a compact preview for photos, videos, and web links in card details
///
struct CardAttachmentThumbnail: View
{


    let attachment: KanbanAttachment /* Attachment represented by the thumbnail */

    ///
    /// @fcn        CardAttachmentThumbnail.body
    /// @brief      Build a square preview for an attached card item
    /// @details    Shows a link or video symbol, a cropped local photo, or a photo placeholder when
    ///             the local image cannot be loaded
    ///
    /// @return     (some View) square attachment thumbnail or missing-photo fallback
    ///
    /// @pre        attachment contains metadata for a local image file
    /// @post       Rendering does not modify the attachment or stored image data
    ///
    var body: some View
    {  /* Local image, remote link, or media fallback */


        GeometryReader
        {
            geometry in
            Group
            {


                if let url = attachment.url
                {  /* Remote link URL */


                    VStack(spacing: 6)
                    {


                        Image(systemName: "link")
                        .font(.title2)

                        Text(url.host ?? url.absoluteString)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    }

                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                }
                else if attachment.kind == .audio
                {

                    Image(systemName: "waveform")
                    .font(.title2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .accessibilityLabel("Voice recording")
                }
                else if attachment.kind == .video
                {


                    Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                }
                else if let imageURL = CardAttachmentStore.imageURL(for: attachment), /* Local photo file URL */

                let image = UIImage(contentsOfFile: imageURL.path)
                {  /* Decoded local image */


                    Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                }
                else
                {


                    Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                }

            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }

        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

}


///
/// Coordinates native playback of captured audio
///
/// @section    Purpose
///     Owns the audio player and publishes playback status and errors while allowing the
///     presentation to stop playback on lifecycle changes.
///
@MainActor
final class CaptureAudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate
{


    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?


    ///
    /// @fcn        CaptureAudioPlayback.toggle
    /// @brief      Toggle playback of the requested audio URL
    /// @details    Stops current playback or creates and starts an audio player, publishing playback state and
    ///             reporting setup failures.
    ///
    /// @param[in]  url  File URL for the requested audio resource
    ///
    /// @return     (Void) no return value
    ///
    func toggle(url: URL)
    {

        if isPlaying
        {
            stop();
            return
        }

        do
        {

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self;
            self.player = player
            isPlaying = player.play()
        }
        catch
        {
            isPlaying = false;
            errorMessage = "This recording couldn't be played. The file may be unavailable."
        }

    }

    @Published var errorMessage: String?


    ///
    /// @fcn        CaptureAudioPlayback.stop
    /// @brief      Stop and release the current audio player
    /// @details    Clears the retained player and resets the observable playing state.
    ///
    /// @return     (Void) no return value
    ///
    func stop()
    {

        guard player != nil else
        {
            isPlaying = false;
            return
        }

        player?.stop();
        player = nil;
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }


    ///
    /// @fcn        CaptureAudioPlayback.audioPlayerDidFinishPlaying
    /// @brief      Clear playback state when audio finishes
    /// @details    Handles the delegate completion by releasing the finished playback session through the shared stop
    ///             path.
    ///
    /// @param[in]  player  Audio player delivering completion
    /// @param[in]  flag    Whether the system reports successful completion
    ///
    /// @return     (Void) no return value
    ///
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool)
    {

        Task
        {
            @MainActor [weak self] in
            self?.stop()
        }

    }

}


///
/// Plays a retained audio attachment
///
/// @section    Purpose
///     Owns playback state for the supplied file URL and responds to scene changes so audio does
///     not outlive its intended presentation.
///
struct AudioAttachmentPlayer: View
{


    let url: URL
    @StateObject private var playback = CaptureAudioPlayback()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View
    {

        VStack(spacing: 16)
        {

            Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.secondary)
            Button(
                playback.isPlaying ? "Stop playback" : "Play recording",
                systemImage: playback.isPlaying ? "stop.circle" : "play.circle"
            )
            {
                playback.toggle(url: url)
            }
            .frame(minHeight: 44)
            if let error = playback.errorMessage
            {
                Text(error).foregroundStyle(.secondary)
            }

        }
        .onDisappear
        {
            playback.stop()
        }
        .onChange(of: scenePhase)
        {
            _, phase in
            if phase != .active
            {
                playback.stop()
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Plenact.StopAudioPreview")))
        {
            _ in
            playback.stop()
        }

    }

}


///
/// Previews an attachment using its retained media type
///
/// @section    Purpose
///     Selects the appropriate viewer and supports checked drawing updates when an editing callback
///     is supplied.
///
struct CardAttachmentPreview: View
{


    let attachment: KanbanAttachment /* The media attachment to preview */

    var onSaveDrawing:                   ((KanbanAttachment) -> Bool)? = nil
    @State private var editedAttachment: KanbanAttachment?
    @State private var showsDrawingEditor = false
    private var currentAttachment: KanbanAttachment
    {
        editedAttachment ?? attachment
    }

    @Environment(\.dismiss) private var dismiss /* Preview dismissal action */

    ///
    /// @fcn        CardAttachmentPreview.body
    /// @brief      Build a large preview for an attached photo
    /// @details    Plays a local video or displays a local photo scaled to fit, with a fallback
    ///             view when the referenced file is unavailable
    ///
    /// @return     (some View) navigable image preview with a Done action
    ///
    /// @pre        attachment identifies a photo previously imported for a card
    /// @post       The preview is shown without modifying the image or its metadata
    ///
    var body: some View
    {  /* Video or image preview with unavailable fallback */


        NavigationStack
        {

            Group
            {


                if attachment.kind == .audio, let url = CardAttachmentStore.fileURL(for: currentAttachment)
                {

                    AudioAttachmentPlayer(url: url).padding()
                }
                else if attachment.kind == .video,

                let videoURL = CardAttachmentStore.fileURL(for: currentAttachment)
                {  /* Local video file URL */

                    VideoPlayer(player: AVPlayer(url: videoURL))
                }
                else
                {

                    ScrollView
                    {

                        VStack(spacing: 12)
                        {

                            if let imageURL = CardAttachmentStore.imageURL(for: currentAttachment),
                            let image = UIImage(contentsOfFile: imageURL.path)
                            {

                                Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                            }
                            else
                            {

                                ContentUnavailableView("Photo unavailable", systemImage: "photo")
                            }

                            if let caption = attachment.caption, !caption.isEmpty
                            {

                                Text(caption)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            }

                        }

                    }

                }

            }

            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {


                ToolbarItem(placement: .topBarLeading)
                {

                    if currentAttachment.drawingFileName != nil
                    {

                        Button("Edit drawing", systemImage: "pencil.tip")
                        {
                            showsDrawingEditor = true
                        }

                    }

                }

                ToolbarItem(placement: .topBarTrailing)
                {


                    Button("Done")
                    {

                        dismiss()
                    }

                }

            }

        }

        .sheet(isPresented: $showsDrawingEditor)
        {

            if let draft = try? DrawingAttachmentStore.load(currentAttachment)
            {

                DrawingCaptureEditor(initial: draft)
                {
                    drawing in
                    guard let onSaveDrawing else
                    {
                        return false
                    }

                    do
                    {

                        let replacement = try DrawingAttachmentStore.save(drawing, replacing: currentAttachment)
                        guard onSaveDrawing(replacement) else
                        {

                            try? CardAttachmentStore.removeDeletedFiles(
                                Set(replacement.storedFileNames), keeping: Set(currentAttachment.storedFileNames))
                            return false
                        }

                        editedAttachment = replacement
                        return true
                    }
                    catch
                    {
                        return false
                    }

                }

            }
            else
            {

                ContentUnavailableView(
                                                "Drawing unavailable", systemImage: "pencil.tip",
                                                description: Text(
                                                                                    "The image preview is still available, but its editable strokes could not be read."))
            }

        }
        .presentationDetents([.large])
    }

}
