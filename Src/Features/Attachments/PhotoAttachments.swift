// -------------------------------------------------------------------------------------------------
// @file       PhotoAttachments.swift
// @brief      Photo attachment model, local file storage, and picker/gallery components
// @details    Imports image selections, stores photo bytes in the app container, and presents
//             attached photos
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


/// Identifies the content type of a card attachment.
enum KanbanAttachmentKind: String, Codable {
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
struct KanbanAttachment: Identifiable, Hashable, Codable {

    let id:        UUID
    let fileName:  String?
    let url:       URL?
    let mediaKind: KanbanAttachmentKind?
    let addedAt:   Date

    var kind: KanbanAttachmentKind {
        mediaKind ?? (url == nil ? .photo : .link)
    }

    init(id: UUID = UUID(), fileName: String? = nil, url: URL? = nil, mediaKind: KanbanAttachmentKind? = nil, addedAt: Date = .now) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.mediaKind = mediaKind
        self.addedAt = addedAt
    }
}


///
/// Stores imported card photos in the app's private Documents directory and validates web links
///
/// @section    Purpose
///     Keep image data out of UserDefaults while allowing board JSON to retain lightweight photo
///     and link records
///
/// @note       Files no longer referenced by any card can be removed with
///             removeUnreferencedFiles(keeping:)
///
enum CardAttachmentStore {

    private static let directoryName = "CardAttachments"

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

        let attachmentID        = UUID()
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let safeExtension       = normalizedExtension.isEmpty ? (kind == .video ? "mov" : "jpg") : normalizedExtension
        let fileName            = "\(attachmentID.uuidString).\(safeExtension)"
        let directoryURL        = try attachmentsDirectory()
        let fileURL             = directoryURL.appendingPathComponent(fileName, isDirectory: false)

        try mediaData.write(to: fileURL, options: .atomic)

        return KanbanAttachment(id: attachmentID, fileName: fileName, mediaKind: kind)
    }

    
    ///
    /// @fcn        CardAttachmentStore.imageURL(for:)
    /// @brief      Resolve an attachment record to its local image URL
    /// @details    Combines the app's Documents directory, attachment subdirectory, and stored
    ///             filename
    ///
    /// @param[in]  attachment  Metadata identifying the stored photo file
    ///
    /// @return     (URL?) local image URL, or nil when the Documents directory is unavailable
    ///
    /// @pre        attachment.fileName is the filename returned when the image was saved
    /// @post       No file data or attachment metadata is modified
    ///
    static func fileURL(for attachment: KanbanAttachment) -> URL? {

        guard let fileName = attachment.fileName,
              
              let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            
            return nil
        }

        return documentsURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    
    static func imageURL(for attachment: KanbanAttachment) -> URL? {
        
        guard attachment.kind == .photo else { return nil }
        
        return fileURL(for: attachment)
    }

    
    static func webURL(from text: String) -> URL? {
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let components = URLComponents(string: trimmedText),
              
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              
              let host = components.host,
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

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let directoryURL = documentsURL.appendingPathComponent(directoryName, isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
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

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directoryURL = documentsURL.appendingPathComponent(directoryName, isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return directoryURL
    }
}


/// Sources available when adding an attachment to a card.
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

    var id: String { rawValue }

    var title: String {
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

    var symbolName: String {
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


/// Presents attachment sources and dispatches supported source actions.
struct CardAttachmentSourceSheet: View {

    @Binding var photoSelection: [PhotosPickerItem]
    
    let onAddLink: ()          -> Void
    let onPasteClipboard: ()   -> Void
    let onComingSoon: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    
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

    var body: some View {
        
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


/// Collects and validates a web address to attach to a card.
struct CardLinkAttachmentSheet: View {

    let onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlDraft = ""

    private var validatedURL: URL? {
        CardAttachmentStore.webURL(from: urlDraft)
    }

    var body: some View {
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

    private func saveLink() {
        guard let validatedURL else { return }
        onSave(validatedURL)
        dismiss()
    }
}


///
/// Displays a square thumbnail for an attached photo
///
/// @section    Purpose
///     Provide a compact preview for the attachment gallery in card details
///
struct CardAttachmentThumbnail: View {

    let attachment: KanbanAttachment

    ///
    /// @fcn        CardAttachmentThumbnail.body
    /// @brief      Build a square preview for an attached photo
    /// @details    Loads the local image file and displays a cropped thumbnail, or a photo placeholder if unavailable
    ///
    /// @return     (some View) square attachment thumbnail or missing-photo fallback
    ///
    /// @pre        attachment contains metadata for a local image file
    /// @post       Rendering does not modify the attachment or stored image data
    ///
    var body: some View {

        Group {

            if let url = attachment.url {
                
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
                
            } else if let imageURL = CardAttachmentStore.imageURL(for: attachment),
                      
               let image = UIImage(contentsOfFile: imageURL.path) {
                
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
/// Displays an attached photo at a larger size
///
/// @section    Purpose
///     Allow users to inspect a photo after opening its card-detail thumbnail
///
struct CardAttachmentPreview: View {

    let attachment: KanbanAttachment        /* The photo attachment to be previewed */

    @Environment(\.dismiss) private var dismiss

    ///
    /// @fcn        CardAttachmentPreview.body
    /// @brief      Build a large preview for an attached photo
    /// @details    Displays the local image scaled to fit, with a fallback view if the file is unavailable
    ///
    /// @return     (some View) navigable image preview with a Done action
    ///
    /// @pre        attachment identifies a photo previously imported for a card
    /// @post       The preview is shown without modifying the image or its metadata
    ///
    var body: some View {

        NavigationStack {
            Group {

                if attachment.kind == .video,
                   
                   let videoURL = CardAttachmentStore.fileURL(for: attachment) {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                    
                } else if let imageURL = CardAttachmentStore.imageURL(for: attachment),
                          
                   let image = UIImage(contentsOfFile: imageURL.path) {
                    
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
