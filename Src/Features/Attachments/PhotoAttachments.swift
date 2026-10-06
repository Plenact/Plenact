// -------------------------------------------------------------------------------------------------
// @file       PhotoAttachments.swift
// @brief      Media attachment models, local file storage, and picker/gallery components
// @details    Imports image selections, stores photo and video bytes in the app container, and
//             presents attached photos, videos, and web links
//
// @notes      Cards persist attachment metadata and IDs; image data remains outside the board JSON
//
// @section     Opens
//      Function Headers
//      Variable Comments
//
// -------------------------------------------------------------------------------------------------
import AVKit
import Foundation
import PhotosUI
import SwiftUI
import UIKit


///
/// Identifies the supported content types for card attachments
///
/// @section    Purpose
///     Distinguish local photo/video media from remotely accessible links
///
enum KanbanAttachmentKind: String, Codable, Sendable {
    case photo
    case video
    case link
}


///
/// Identifies one photo, video, or web link attached to a card
///
/// @section    Purpose
///     Persist stable attachment identity and lightweight file or URL metadata without embedding
///     image bytes in the board
///
struct KanbanAttachment: Identifiable, Hashable, Codable, Sendable {

    let id:        UUID                     /* Stable attachment identity     */
    let fileName:  String?                  /* Device-local media filename    */
    let url:       URL?                     /* Remote web-link destination    */
    let mediaKind: KanbanAttachmentKind?    /* Explicit media type when known */
    let addedAt:   Date                     /* Attachment creation time       */

    ///
    /// @fcn        KanbanAttachment.kind
    /// @brief      Resolve the attachment's content kind
    /// @details    Uses explicit metadata when available and infers legacy photo or link records
    ///             from whether a URL is present
    ///
    /// @return     (KanbanAttachmentKind) resolved photo, video, or link kind
    ///
    /// @pre        The attachment contains its persisted metadata
    /// @post       No attachment fields are modified
    ///
    var kind: KanbanAttachmentKind { /* Resolved kind for legacy and current records */
        mediaKind ?? (url == nil ? .photo : .link)
    }

    ///
    /// @fcn        KanbanAttachment.init(id:fileName:url:mediaKind:addedAt:)
    /// @brief      Create attachment metadata for local media or a remote link
    /// @details    Stores the supplied stable identity, location metadata, and creation date
    ///
    /// @param[in]  id        Stable attachment identity
    /// @param[in]  fileName  Local media filename, when stored on this device
    /// @param[in]  url       Remote web URL, when the attachment is a link
    /// @param[in]  mediaKind Explicit photo, video, or link content type
    /// @param[in]  addedAt   Attachment creation time
    ///
    /// @return     (KanbanAttachment) configured attachment metadata
    ///
    /// @pre        Supplied metadata describes the attachment location and content, when known
    /// @post       Stored fields match the provided values
    ///
    init(id: UUID = UUID(), fileName: String? = nil, url: URL? = nil, mediaKind: KanbanAttachmentKind? = nil, addedAt: Date = .now) {
        self.id        = id
        self.fileName  = fileName
        self.url       = url
        self.mediaKind = mediaKind
        self.addedAt   = addedAt
    }
}


///
/// Stores imported card media in the app's private Documents directory and validates web links
///
/// @section    Purpose
///     Keep image data out of UserDefaults while allowing board JSON to retain lightweight photo
///     and link records
///
/// @note       Files no longer referenced by any card can be removed with
///             removeUnreferencedFiles(keeping:)
///
enum CardAttachmentStore {

    ///
    /// @fcn        CardAttachmentStore.fileNames(in:)
    /// @brief      Collect retained local media references from complete Board snapshots
    /// @details    Includes both active and archived cards regardless of the list's archive state
    /// @param[in]  lists  Complete retained lists
    /// @return     (Set<String>) referenced media filenames
    ///
    static func fileNames(in lists: [KanbanList]) -> Set<String> {
        Set(lists.flatMap(\.allCards).flatMap { $0.attachments ?? [] }.compactMap(\.fileName))
    }

    ///
    /// @fcn        CardAttachmentStore.removeDeletedFiles(_:keeping:)
    /// @brief      Remove only media belonging to successfully saved deletions
    /// @details    Never scans unrelated files; skips names still referenced by any retained snapshot
    /// @param[in]  candidates  Previously referenced filenames affected by the saved mutation
    /// @param[in]  retained  All filenames still retained by the app
    /// @throws     File removal errors; absent files are already removed
    ///
    static func removeDeletedFiles(_ candidates: Set<String>, keeping retained: Set<String>) throws {
        for name in candidates.subtracting(retained) {
            guard name == (name as NSString).lastPathComponent,
                  !name.isEmpty, name != ".", name != ".." else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let attachment = KanbanAttachment(fileName: name)
            guard let url = fileURL(for: attachment) else { throw CocoaError(.fileNoSuchFile) }
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static let directoryName = "CardAttachments" /* Local media folder name */

    ///
    /// @fcn        CardAttachmentStore.saveMedia(_:kind:fileExtension:)
    /// @brief      Save selected photo or video data to the app's private attachment directory
    /// @details    Writes the media atomically under a unique filename and returns metadata
    ///             referencing that file
    ///
    /// @param[in]  mediaData      Encoded photo or video data transferred from system photo picker
    /// @param[in]  kind           Media kind represented by the saved data
    /// @param[in]  fileExtension  Preferred file extension supplied by the Photos library
    ///
    /// @return     (KanbanAttachment) metadata for the newly stored media file
    ///
    /// @pre        mediaData contains transferable photo or video bytes
    /// @post       A new media file exists in the app's Documents/CardAttachments directory
    ///
    /// @throws     File-system error if the Documents directory cannot be obtained, created,
    ///             or written
    ///
    static func saveMedia(_ mediaData: Data, kind: KanbanAttachmentKind, fileExtension: String) throws -> KanbanAttachment {

        let attachmentID        = UUID() /* Stable identity for the new media file */
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) /* Clean extension input */
        let safeExtension       = normalizedExtension.isEmpty ? (kind == .video ? "mov" : "jpg") : normalizedExtension /* Valid file extension */
        let fileName            = "\(attachmentID.uuidString).\(safeExtension)" /* Unique stored filename */
        let directoryURL        = try attachmentsDirectory() /* App-local media directory */
        let fileURL             = directoryURL.appendingPathComponent(fileName, isDirectory: false) /* Destination file URL */

        try mediaData.write(to: fileURL, options: .atomic)

        return KanbanAttachment(id: attachmentID, fileName: fileName, mediaKind: kind)
    }

    
    ///
    /// @fcn        CardAttachmentStore.fileURL(for:)
    /// @brief      Resolve an attachment record to its local media URL
    /// @details    Combines the app's Documents directory, attachment subdirectory, and stored
    ///             filename
    ///
    /// @param[in]  attachment  Metadata identifying the stored media file
    ///
    /// @return     (URL?) local media URL, or nil when its filename or Documents directory is unavailable
    ///
    /// @pre        attachment.fileName is the filename returned when the media was saved
    /// @post       No file data or attachment metadata is modified
    ///
    static func fileURL(for attachment: KanbanAttachment) -> URL? {

        guard let fileName = attachment.fileName, /* Stored local filename */
              
              let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { /* App Documents directory */
            
            return nil
        }

        return documentsURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }


    ///
    /// @fcn        CardAttachmentStore.imageURL(for:)
    /// @brief      Resolve a local URL only when an attachment represents a photo
    /// @details    Delegates filename resolution to the attachment store after checking the kind
    ///
    /// @param[in]  attachment Attachment metadata to inspect
    ///
    /// @return     (URL?) local photo URL, or nil for other media or an unresolved filename
    ///
    /// @pre        attachment contains its persisted media metadata
    /// @post       No file data or attachment metadata is modified
    ///
    static func imageURL(for attachment: KanbanAttachment) -> URL? {
        
        guard attachment.kind == .photo else { return nil }
        
        return fileURL(for: attachment)
    }


    ///
    /// @fcn        CardAttachmentStore.webURL(from:)
    /// @brief      Validate and parse a web address entered as text
    /// @details    Trims surrounding whitespace and accepts only HTTP or HTTPS URLs with a host
    ///
    /// @param[in]  text Candidate URL text
    ///
    /// @return     (URL?) HTTP or HTTPS URL with a host, or nil when invalid
    ///
    /// @pre        text contains a candidate URL
    /// @post       The input text is unchanged
    ///
    static func webURL(from text: String) -> URL? {
        
          let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized pasted or typed URL */

          guard let components = URLComponents(string: trimmedText), /* Parsed URL components */
              
              let scheme = components.scheme?.lowercased(), /* Normalized URL scheme */
              ["http", "https"].contains(scheme),
              
              let host = components.host, /* Required URL host */
              !host.isEmpty else {
            
            return nil
        }

        return components.url
    }

    
    ///
    /// @fcn        CardAttachmentStore.removeUnreferencedFiles(keeping:)
    /// @brief      Remove stored image files no longer referenced by any card
    /// @details    Scans the attachment directory and deletes filenames absent from the supplied
    ///             reference set
    ///
    /// @param[in]  fileNames  Filenames still referenced by the current board cards
    ///
    /// @return     (Void) removes unreferenced files when the attachment directory can be read
    ///
    /// @pre        fileNames represents the current persisted card attachment references
    /// @post       Referenced files remain; unreferenced files are removed when possible
    ///
    static func removeUnreferencedFiles(keeping fileNames: Set<String>) {

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { /* App Documents directory */
            return
        }

        let directoryURL = documentsURL.appendingPathComponent(directoryName, isDirectory: true) /* Attachment folder URL */

        guard let files = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { /* Files available for cleanup */
            return
        }

        for fileURL in files where !fileNames.contains(fileURL.lastPathComponent) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    

    ///
    /// @fcn        CardAttachmentStore.attachmentsDirectory
    /// @brief      Return the app's photo attachment directory
    /// @details    Resolves Documents/CardAttachments and creates the directory if it does not already exist
    ///
    /// @return     (URL) directory used to store imported card images
    ///
    /// @pre        The app has access to its user Documents directory
    /// @post       The returned directory exists and is ready to receive files
    ///
    /// @throws     CocoaError when the Documents directory is unavailable or directory creation fails
    ///
    private static func attachmentsDirectory() throws -> URL {

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { /* App Documents directory */
            throw CocoaError(.fileNoSuchFile)
        }

        let directoryURL = documentsURL.appendingPathComponent(directoryName, isDirectory: true) /* Attachment folder URL */

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return directoryURL
    }
}


///
/// Identifies the attachment sources available from card detail
///
/// @section    Purpose
///     Provide stable source identities and display metadata for the attachment picker
///
enum CardAttachmentSource: String, CaseIterable, Identifiable {

    case trello
    case confluence
    case jira
    case file
    case documentScanner
    case qrCode
    case camera
    case photoOrVideo
    case link
    case clipboard

    ///
    /// @fcn        CardAttachmentSource.id
    /// @brief      Expose the source token as its stable identity
    /// @details    Reuses the enum raw value for picker rows
    ///
    /// @return     (String) attachment-source identifier
    ///
    var id: String { rawValue } /* Stable picker identity */

    ///
    /// @fcn        CardAttachmentSource.title
    /// @brief      Return the display title for an attachment source
    /// @details    Maps each source case to its picker-row label
    ///
    /// @return     (String) display text defined for the source
    ///
    var title: String { /* User-facing attachment-source label */
        switch self {
            case .trello:         "Trello"
            case .confluence:     "Confluence"
            case .jira:           "Jira"
            case .file:           "File"
            case .documentScanner:"Document scanner"
            case .qrCode:         "QR code"
            case .camera:         "Camera"
            case .photoOrVideo:   "Photo or video"
            case .link:           "Link"
            case .clipboard:      "Clipboard"
        }
    }

    ///
    /// @fcn        CardAttachmentSource.symbolName
    /// @brief      Return the SF Symbol name for an attachment source
    /// @details    Maps each source case to the icon shown in the picker
    ///
    /// @return     (String) SF Symbol identifier for the source
    ///
    var symbolName: String { /* SF Symbol for the picker row */
        switch self {
            case .trello:         "square.split.2x2"
            case .confluence:     "water.waves"
            case .jira:           "checkmark.circle"
            case .file:           "paperclip"
            case .documentScanner:"doc.viewfinder"
            case .qrCode:         "qrcode.viewfinder"
            case .camera:         "camera"
            case .photoOrVideo:   "photo.on.rectangle"
            case .link:           "link"
            case .clipboard:      "doc.on.clipboard"
        }
    }
}


///
/// Presents supported attachment sources and dispatches the selected action
///
/// @section    Purpose
///     Connect photo selection, link entry, clipboard import, and unavailable source notices
///
struct CardAttachmentSourceSheet: View {

    @Binding var photoSelection: [PhotosPickerItem] /* Current Photos-picker selection */
    
    let onAddLink: ()          -> Void /* Callback opening manual link entry */
    let onPasteClipboard: ()   -> Void /* Callback importing clipboard link */
    let onComingSoon: (String) -> Void /* Callback reporting unsupported source */

    @Environment(\.dismiss) private var dismiss /* Sheet dismissal action */

    
    ///
    /// @fcn        CardAttachmentSourceSheet.select(_:)
    /// @brief      Dispatch the action associated with one attachment source
    /// @details    Invokes link or clipboard callbacks, leaves photo selection to PhotosPicker,
    ///             and reports unsupported source choices
    ///
    /// @param[in]  source Selected attachment source
    ///
    /// @return     (Void) invokes the matching callback or system picker
    ///
    /// @pre        source is one of the available attachment sources
    /// @post       The corresponding callback is invoked where applicable
    ///
    private func select(_ source: CardAttachmentSource) {
        switch source {
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
    var body: some View { /* Attachment-source picker */
        
        NavigationStack {
            
            List {

                ForEach(CardAttachmentSource.allCases) { source in

                    if source == .photoOrVideo {
                        PhotosPicker(selection: $photoSelection, maxSelectionCount: 12, matching: .any(of: [.images, .videos])) {
                            Label(source.title, systemImage: source.symbolName)
                                .foregroundStyle(.primary)
                        }

                    } else {
                        Button {
                            select(source)
                        } label: {
                            Label(source.title, systemImage: source.symbolName)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Add attachment from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
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
struct CardLinkAttachmentSheet: View {

    let onSave: (URL) -> Void /* Callback receiving the validated URL */

    @Environment(\.dismiss) private var dismiss /* Sheet dismissal action */
    @State private var urlDraft = "" /* User-entered URL text */

    ///
    /// @fcn        CardLinkAttachmentSheet.validatedURL
    /// @brief      Return the parsed URL when the current draft is valid
    /// @details    Delegates URL validation to CardAttachmentStore
    ///
    /// @return     (URL?) valid HTTP or HTTPS URL, or nil for invalid draft text
    ///
    private var validatedURL: URL? { /* Parsed URL when the draft is valid */
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
    var body: some View {               /* Manual web-link form */

        NavigationStack {

            Form {

                Section("Link") {

                    TextField("https://example.com", text: $urlDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveLink)
                }
            }
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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
    /// @fcn        CardLinkAttachmentSheet.saveLink
    /// @brief      Submit the entered URL when it passes web-link validation
    /// @details    Calls the owner callback and dismisses the sheet for a valid draft
    ///
    /// @return     (Void) invokes the save callback and dismisses the sheet
    ///
    /// @pre        The draft has a validated URL
    /// @post       The callback receives that URL and the sheet is dismissed
    ///
    private func saveLink() {

        guard let validatedURL else { return } /* Require a valid web address */

        onSave(validatedURL)

        dismiss()
    }
}


///
/// Displays a square thumbnail for an attached card item
///
/// @section    Purpose
///     Provide a compact preview for photos, videos, and web links in card details
///
struct CardAttachmentThumbnail: View {

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
    var body: some View { /* Local image, remote link, or media fallback */

        Group {

            if let url = attachment.url { /* Remote link URL */
                
                VStack(spacing: 6) {
                    
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
                
            } else if attachment.kind == .video {
                
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                
            } else if let imageURL = CardAttachmentStore.imageURL(for: attachment), /* Local photo file URL */
                      
               let image = UIImage(contentsOfFile: imageURL.path) { /* Decoded local image */
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}


///
/// Displays an attached photo or video at a larger size
///
/// @section    Purpose
///     Allow users to inspect local media after opening its card-detail thumbnail
///
struct CardAttachmentPreview: View {

    let attachment: KanbanAttachment        /* The media attachment to preview */

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
    var body: some View { /* Video or image preview with unavailable fallback */

        NavigationStack {
            Group {

                if attachment.kind == .video,
                   
                   let videoURL = CardAttachmentStore.fileURL(for: attachment) { /* Local video file URL */
                    VideoPlayer(player: AVPlayer(url: videoURL))
                    
                } else if let imageURL = CardAttachmentStore.imageURL(for: attachment), /* Local photo file URL */
                          
                   let image = UIImage(contentsOfFile: imageURL.path) { /* Decoded local image */
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                    
                } else {
                    ContentUnavailableView("Photo unavailable", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .topBarTrailing) {
                    
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
