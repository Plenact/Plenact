// --------------------------------------------------------------------------------------------------
// @file       PhotoAttachments.swift
// @brief      Media attachment models, local file storage, and picker/gallery components
// @details    Imports image selections, stores photo and video bytes in the app container, and
//             presents attached photos, videos, and web links
//
// @notes      Cards persist attachment metadata and IDs; image data remains outside the board JSON
//
// @section    Opens
//      Function Headers
//      Variable Comments
//
// --------------------------------------------------------------------------------------------------
import AVKit
import Foundation
import ImageIO
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
/// Categories for the offline illustration library
///
/// @section    Purpose
///     Organize artwork without imposing categories on people's cards
///
enum CoverCategory: String, CaseIterable, Identifiable {
    case home = "Home & Everyday"
    case nature = "Nature & Garden"
    case work = "Work & Learning"
    case food = "Food & Shopping"
    case travel = "Travel & Outdoors"
    case creativity = "Creativity & Connection"

    ///
    /// @fcn        CoverCategory.id
    /// @brief      Identify a category filter
    /// @return     (String) stable category label
    ///
    var id: String { rawValue } /* Stable category identity */

    ///
    /// @fcn        CoverCategory.images
    /// @brief      Supply eight ordered illustrations per category
    /// @details    Categories describe artwork only, not card ownership or semantics
    /// @return     ([ExampleCoverImage]) explicit curated category membership
    ///
    var images: [ExampleCoverImage] { /* Curated artwork for this category */
        switch self {

            case .home: [.readingCorner, .tidyHome, .laundryDay, .homeRepairs, .cozySofa, .cleanKitchen, .petCare, .deskLamp]
            case .nature: [.garden, .wateringPlants, .forestPath, .flowerBouquet, .sunrise, .herbPots, .rainyDay, .butterfly]
            case .work: [.workspace, .studyBooks, .writingNotes, .projectPlanning, .learning, .calendarPlan, .coding, .goalSteps]
            case .food: [.freshProduce, .cooking, .groceryBag, .coffeeBreak, .baking, .breakfast, .pantry, .market]
            case .travel: [.mountains, .camping, .coastalWalk, .cycling, .travelBag, .trainTrip, .sailboat, .picnic]
            case .creativity: [.painting, .music, .conversation, .sharedMeal, .photography, .crafting, .gift, .gameNight]
        }
    }
}


///
/// Original bundled illustrations for examples and explicit user cover choices
///
/// @section    Purpose
///     Keep example drafts side-effect-free and independent of personal media files
///
enum ExampleCoverImage: String, Codable, CaseIterable, Sendable {
    case garden, mountains, workspace
    case readingCorner = "reading-corner", tidyHome = "tidy-home", laundryDay = "laundry-day", homeRepairs = "home-repairs"
    case wateringPlants = "watering-plants", forestPath = "forest-path", flowerBouquet = "flower-bouquet", sunrise
    case studyBooks = "study-books", writingNotes = "writing-notes", projectPlanning = "project-planning", learning
    case freshProduce = "fresh-produce", cooking, groceryBag = "grocery-bag", coffeeBreak = "coffee-break"
    case camping, coastalWalk = "coastal-walk", cycling, travelBag = "travel-bag"
    case painting, music, conversation, sharedMeal = "shared-meal"
    case cozySofa = "cozy-sofa", cleanKitchen = "clean-kitchen", petCare = "pet-care", deskLamp = "desk-lamp"
    case herbPots = "herb-pots", rainyDay = "rainy-day", butterfly
    case calendarPlan = "calendar-plan", coding, goalSteps = "goal-steps"
    case baking, breakfast, pantry, market
    case trainTrip = "train-trip", sailboat, picnic
    case photography, crafting, gift, gameNight = "game-night"

    ///
    /// @fcn        ExampleCoverImage.title
    /// @brief      Provide a readable artwork label without embedded image text
    /// @return     (String) human-readable name
    ///
    var title: String { rawValue.replacingOccurrences(of: "-", with: " ").capitalized } /* Readable artwork name */

    ///
    /// @fcn        ExampleCoverImage.url
    /// @brief      Resolve the immutable bundled illustration
    /// @details    Only known resource names can be resolved; no remote downloads occur
    /// @return     (URL?) bundled PNG location
    ///
    var url: URL? { /* Bundled artwork resource URL */
        Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "CardCoverImages")
    }
}


///
/// Offline visual library with category filters and explicit cover selection
///
/// @section    Purpose
///     Browse all 48 original illustrations without downloading or analyzing card content
///
struct CardCoverLibrary: View {
    let selectedImage: ExampleCoverImage? /* Current library cover, if any */
    let onSelect: (ExampleCoverImage) -> Bool /* Owner validates and publishes an explicit choice */
    @State private var category: CoverCategory? /* nil shows All Covers */
    @Environment(\.dynamicTypeSize) private var textSize /* Use a single column for accessibility text */
    @Environment(\.dismiss) private var dismiss /* Cancel or close a successful selection */

    ///
    /// @fcn        CardCoverLibrary.body
    /// @brief      Offer category browsing, named previews, and a non-destructive Cancel path
    /// @details    No selection or attachment is created until a person taps an illustration
    /// @return     (some View) adaptive offline library
    ///
    var body: some View { /* Offline cover library interface */
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Cover category", selection: $category) {
                        Text("All Covers").tag(Optional<CoverCategory>.none)
                        ForEach(CoverCategory.allCases) { category in
                            Text(category.rawValue).tag(Optional(category))
                        }
                    }

                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    Text("Choose an illustration to use as this card's cover. Your existing photos stay attached.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns:                                        textSize.isAccessibilitySize
                              ? [GridItem(.flexible())]
                              : [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        ForEach(category?.images ?? CoverCategory.allCases.flatMap(\.images), id: \.self) { image in
                            Button {
                                if onSelect(image) {

                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CardCoverPreview(attachment: KanbanAttachment(
                                        mediaKind: .photo, exampleImage: image
                                    ), height:                   96)
                                    Label(image.title, systemImage: selectedImage == image ? "checkmark.circle.fill" : "photo")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                .padding(8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }

                            .buttonStyle(.plain)
                            .accessibilityLabel(image.title + (selectedImage == image ? ", current cover" : ""))
                            .accessibilityHint("Use this illustration as the card cover.")
                        }
                    }
                }

                .padding()
            }

            .navigationTitle("Cover Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}


///
/// Decorative, bounded preview shared by card rows and cover controls
///
/// @section    Purpose
///     Load photos away from the main actor without creating or modifying files
///
struct CardCoverPreview: View {
    let attachment: KanbanAttachment /* Explicitly selected photo */
    var height: CGFloat = 128 /* Fixed preview height, independent of source image dimensions */
    var unavailableTitle = "Cover unavailable"
    @State private var image: UIImage? /* Downsampled image for this presentation */
    @State private var unavailable = false /* Explicit missing/invalid-image feedback */

    ///
    /// @fcn        CardCoverPreview.body
    /// @brief      Render the selected cover without hiding the card's text identity
    /// @details    Task identity/cancellation prevents a previous image from replacing a changed cover
    /// @return     (some View) decorative cropped image or visible unavailable notice
    ///
    var body: some View { /* Loaded cover preview or fallback */
        GeometryReader { geometry in
            Group {
                if let image { /* Successfully decoded cover thumbnail */

                    Image(uiImage: image).resizable().scaledToFill()
                } else if unavailable {

                    Label(unavailableTitle, systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {

                    Color.secondary.opacity(0.08)
                }
            }

            .frame(width: geometry.size.width, height: height)
            .clipped()
        }

        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(!unavailable)
        .task(id: attachment) {
            image = nil
            unavailable = false

            let result = await Task.detached(priority: .utility) { /* Background thumbnail decode result */
                Result { try CardAttachmentStore.coverThumbnail(for: attachment) }
            }.value
            guard !Task.isCancelled else {

                return
            }

            switch result {

                case .success(let thumbnail): image = thumbnail /* Decoded cover thumbnail */
                case .failure: unavailable = true
            }
        }
    }
}


///
/// Visual chooser for photos already attached to a card
///
/// @section    Purpose
///     Make cover replacement recognizable without relying on numbered photo menus
///
struct CardCoverPicker: View {
    let photos: [KanbanAttachment] /* Current attached photo choices */
    let selectedID: UUID? /* Current cover, if explicitly enabled */
    let onSelect: (UUID) -> Void /* Owner validates and saves selection */
    @Environment(\.dismiss) private var dismiss /* Cancel or return after choosing */

    ///
    /// @fcn        CardCoverPicker.body
    /// @brief      Show recognizable photo choices and a clear Cancel path
    /// @details    Cancel does not mutate a card; choosing a row reuses its existing attachment
    /// @return     (some View) navigable cover-photo chooser
    ///
    var body: some View { /* Attached-photo cover choices */
        NavigationStack {
            List {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        onSelect(photo.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            CardCoverPreview(attachment: photo)
                            Label("Photo \(index + 1)", systemImage: selectedID == photo.id ? "checkmark.circle.fill" : "photo")
                        }
                    }

                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(index + 1)\(selectedID == photo.id ? ", current cover" : "")")
                    .accessibilityHint("Use this attached photo as the card cover.")
                }
            }

            .navigationTitle("Choose Card Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
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
    let exampleImage: ExampleCoverImage?    /* Immutable original example illustration, never user media */
    var caption: String?                   /* Optional photo text; absent in legacy attachment records */

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
    /// @param[in]  exampleImage  Optional bundled illustration for synthetic examples
    ///
    /// @return     (KanbanAttachment) configured attachment metadata
    ///
    /// @pre        Supplied metadata describes the attachment location and content, when known
    /// @post       Stored fields match the provided values
    ///
    init(id: UUID = UUID(), fileName: String? = nil, url: URL? = nil, mediaKind: KanbanAttachmentKind? = nil, addedAt: Date = .now, exampleImage: ExampleCoverImage? = nil, caption: String? = nil) {

        self.id        = id
        self.fileName  = fileName
        self.url       = url
        self.mediaKind = mediaKind
        self.addedAt   = addedAt
        self.exampleImage = exampleImage
        self.caption   = caption
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
    /// @fcn        CardAttachmentStore.coverThumbnail(for:)
    /// @brief      Decode a bounded, orientation-correct cover image
    /// @details    Downsamples before decoding so Board rows do not load full-size camera images
    ///
    /// @param[in]  attachment  Local or bundled photo metadata
    ///
    /// @return     (UIImage) thumbnail with at most 960 pixels on its longest edge
    ///
    /// @throws     Read/decode errors for missing or invalid media
    ///
    static func coverThumbnail(for attachment: KanbanAttachment) throws -> UIImage {

        guard let url = imageURL(for: attachment), /* Resolved attachment image URL */
              let source = CGImageSourceCreateWithURL(url as CFURL, nil), /* ImageIO source for the attachment */
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 960,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) /* Orientation-correct bounded thumbnail */ else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return UIImage(cgImage: image)
    }


    ///
    /// @fcn        CardAttachmentStore.fileNames(in:)
    /// @brief      Collect retained local media references from complete Board snapshots
    /// @details    Includes both active and archived cards regardless of the list's archive state
    ///
    /// @param[in]  lists  Complete retained lists
    ///
    /// @return     (Set<String>) referenced media filenames
    ///
    static func fileNames(in lists: [KanbanList]) -> Set<String> {

        Set(lists.flatMap(\.allCards).flatMap { $0.attachments ?? [] }.compactMap(\.fileName))
    }


    ///
    /// @fcn        CardAttachmentStore.removeDeletedFiles(_:keeping:)
    /// @brief      Remove only media belonging to successfully saved deletions
    /// @details    Never scans unrelated files; skips names still referenced by any retained
    ///             snapshot
    ///
    /// @param[in]  candidates  Previously referenced filenames affected by the saved mutation
    /// @param[in]  retained    All filenames still retained by the app
    ///
    /// @return     (Void) remove only media belonging to successfully saved deletions
    ///
    /// @throws     File removal errors; absent files are already removed
    ///
    static func removeDeletedFiles(_ candidates: Set<String>, keeping retained: Set<String>) throws {

        for name in candidates.subtracting(retained) {

            guard name == (name as NSString).lastPathComponent,
                  !name.isEmpty, name != ".", name != ".." else {
                throw CocoaError(.fileWriteInvalidFileName)
            }

            let attachment = KanbanAttachment(fileName: name) /* Metadata for the stored media file */

            guard let url = fileURL(for: attachment) else { /* Local destination for the attachment */

                throw CocoaError(.fileNoSuchFile)
            }

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
    /// @throws     File-system error if the Documents directory cannot be obtained, created, or
    ///             written
    ///
    /// @pre        mediaData contains transferable photo or video bytes
    /// @post       A new media file exists in the app's Documents/CardAttachments directory
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
    /// @return     (URL?) local media URL, or nil when its filename or Documents directory is
    ///             unavailable
    ///
    /// @pre        attachment.fileName is the filename returned when the media was saved
    /// @post       No file data or attachment metadata is modified
    ///
    static func fileURL(for attachment: KanbanAttachment) -> URL? {

        if let exampleImage = attachment.exampleImage { /* Explicit bundled cover selection */

            return exampleImage.url
        }

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
    /// @param[in]  attachment  Attachment metadata to inspect
    ///
    /// @return     (URL?) local photo URL, or nil for other media or an unresolved filename
    ///
    /// @pre        attachment contains its persisted media metadata
    /// @post       No file data or attachment metadata is modified
    ///
    static func imageURL(for attachment: KanbanAttachment) -> URL? {
        
        guard attachment.kind == .photo else {

            return nil
        }
        
        return fileURL(for: attachment)
    }


    ///
    /// @fcn        CardAttachmentStore.webURL(from:)
    /// @brief      Validate and parse a web address entered as text
    /// @details    Trims surrounding whitespace and accepts only HTTP or HTTPS URLs with a host
    ///
    /// @param[in]  text  Candidate URL text
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
    /// @fcn        CardAttachmentStore.attachmentsDirectory()
    /// @brief      Return the app's photo attachment directory
    /// @details    Resolves Documents/CardAttachments and creates the directory if it does not
    ///             already exist
    ///
    /// @return     (URL) directory used to store imported card images
    ///
    /// @throws     CocoaError when the Documents directory is unavailable or directory creation
    ///             fails
    ///
    /// @pre        The app has access to its user Documents directory
    /// @post       The returned directory exists and is ready to receive files
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
    /// @fcn        CardLinkAttachmentSheet.saveLink()
    /// @brief      Submit the entered URL when it passes web-link validation
    /// @details    Calls the owner callback and dismisses the sheet for a valid draft
    ///
    /// @return     (Void) invokes the save callback and dismisses the sheet
    ///
    /// @pre        The draft has a validated URL
    /// @post       The callback receives that URL and the sheet is dismissed
    ///
    private func saveLink() {

        guard let validatedURL else { /* Validated attachment URL */

            return
        } /* Require a valid web address */

        onSave(validatedURL)

        dismiss()
    }
}


extension ItemAccent {
    var color: Color {
        switch self {
            case .teal: .teal
            case .blue: .blue
            case .purple: .purple
            case .rose: .pink
            case .orange: .orange
            case .green: .green
        }
    }

    var darkHeaderColor: Color {
        switch self {
            case .teal: Color(red: 0.08, green: 0.28, blue: 0.28)
            case .blue: Color(red: 0.08, green: 0.20, blue: 0.36)
            case .purple: Color(red: 0.24, green: 0.12, blue: 0.32)
            case .rose: Color(red: 0.34, green: 0.12, blue: 0.22)
            case .orange: Color(red: 0.34, green: 0.20, blue: 0.08)
            case .green: Color(red: 0.12, green: 0.28, blue: 0.14)
        }
    }

    func bannerColor(increasedContrast: Bool) -> Color {
        Color(uiColor: UIColor { traits in
            let tint = UIColor(self.color).resolvedColor(with: traits)
            let base = UIColor.systemBackground.resolvedColor(with: traits)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            var baseRed: CGFloat = 0
            var baseGreen: CGFloat = 0
            var baseBlue: CGFloat = 0
            tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &alpha)
            let amount: CGFloat = increasedContrast ? 0.10 : 0.16
            return UIColor(
                red: baseRed * (1 - amount) + red * amount,
                green: baseGreen * (1 - amount) + green * amount,
                blue: baseBlue * (1 - amount) + blue * amount,
                alpha: 1
            )
        })
    }
}

struct ItemAppearanceMark: View {
    let appearance: ItemAppearance?

    var body: some View {
        if let icon = appearance?.icon {
            Image(systemName: icon.rawValue)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

private struct ItemBannerBackground: ViewModifier {
    let appearance: ItemAppearance?
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if let background = appearance?.background {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background.bannerColor(increasedContrast: contrast == .increased))
        } else {
            content
        }
    }
}

extension View {
    func itemBannerBackground(_ appearance: ItemAppearance?) -> some View {
        modifier(ItemBannerBackground(appearance: appearance))
    }
}

/// Shows the complete selected image at its natural aspect ratio, using the existing thumbnail loader.
struct ItemPicturePreview: View {
    let attachment: KanbanAttachment?
    var title: String? = nil

    private var accessibleDescription: String {
        let text = [title, attachment?.caption]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return text.isEmpty ? "Picture" : text
    }
    @State private var image: UIImage?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
            } else {
                Label(attachment == nil ? "Choose picture" : (unavailable ? "Picture unavailable" : "Loading picture…"), systemImage: "photo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color.secondary.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleDescription)
        .accessibilityValue(attachment == nil ? "Choose picture" : (unavailable ? "Picture unavailable" : ""))
        .accessibilityAddTraits(.isImage)
        .task(id: attachment) {
            image = nil
            unavailable = false
            guard let attachment else { return }
            let result = await Task.detached(priority: .utility) {
                Result { try CardAttachmentStore.coverThumbnail(for: attachment) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let thumbnail): image = thumbnail
            case .failure: unavailable = true
            }
        }
    }
}

/// Shared row menu; changes only the canonical record's display metadata.
struct ItemDisplayFormatMenu: View {
    let card: KanbanCard
    let onUpdate: (KanbanCard) -> Void

    var body: some View {
        Menu {
            ForEach(ItemDisplayFormat.allCases) { format in
                Button {
                    var updated = card
                    updated.displayFormat = format
                    onUpdate(updated)
                } label: {
                    Label(format.title, systemImage: card.displayFormat == format ? "checkmark" : format.symbol)
                }
            }
        } label: {
            Label("Display as", systemImage: "rectangle.on.rectangle")
        }
    }
}

struct ItemAppearanceSheet: View {
    let title: String
    let onSave: (ItemAppearance?) -> Bool
    let onOpenCover: (() -> Void)?
    let onSaveDisplay: ((ItemAppearance?, ItemDisplayFormat) -> Bool)?
    @State private var draftDisplay: ItemDisplayFormat?
    @State private var draft: ItemAppearance
    @Environment(\.dismiss) private var dismiss

    init(title: String, appearance: ItemAppearance?, onOpenCover: (() -> Void)? = nil, displayFormat: ItemDisplayFormat? = nil, onSaveDisplay: ((ItemAppearance?, ItemDisplayFormat) -> Bool)? = nil, onSave: @escaping (ItemAppearance?) -> Bool) {
        self.title = title
        self.onSave = onSave
        self.onOpenCover = onOpenCover
        self.onSaveDisplay = onSaveDisplay
        _draftDisplay = State(initialValue: displayFormat)
        _draft = State(initialValue: appearance ?? ItemAppearance())
    }

    var body: some View {
        NavigationStack {
            Form {
                if draftDisplay != nil {
                    Section("Display as") {
                        Picker("Format", selection: Binding(
                            get: { draftDisplay ?? .card }, set: { draftDisplay = $0 }
                        )) {
                            ForEach(ItemDisplayFormat.allCases) { format in
                                Label(format.title, systemImage: format.symbol).tag(format)
                            }
                        }
                        .accessibilityIdentifier("appearance.displayFormat")
                        Text("Changes how this item is displayed. Its writing, actions, dates, and photos are retained.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if draftDisplay == .picture {
                            Text("Picture uses the selected Card Cover. Save this format, then choose a picture in Card Cover if needed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Preview") {
                    HStack {
                        ItemAppearanceMark(appearance: draft)
                        Text(title).font(.headline)
                    }
                }
                Section("Leading icon") {
                    Picker("Icon", selection: $draft.icon) {
                        Text("None").tag(Optional<PersonalCollectionIcon>.none)
                        ForEach(PersonalCollectionIcon.allCases, id: \.self) { icon in
                            Label(icon.title, systemImage: icon.rawValue).tag(Optional(icon))
                        }
                    }
                    .accessibilityIdentifier("appearance.icon")
                }
                Section("Banner background") {
                    Picker("Background color", selection: $draft.background) {
                        Text("None").tag(Optional<ItemAccent>.none)
                        ForEach(ItemAccent.allCases, id: \.self) { color in
                            Text(color.rawValue.capitalized).tag(Optional(color))
                        }
                    }
                    .accessibilityIdentifier("appearance.background")
                    Text("A soft color across the full header and upper bar, independent of the icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let onOpenCover {
                    Section("Card Cover") {
                        Button("Card Cover", systemImage: "photo", action: onOpenCover)
                            .accessibilityIdentifier("appearance.cover")
                        Text("Choose or remove a cover. Cover changes apply immediately and are separate from saving or canceling the icon and background draft.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Reset appearance") { draft = ItemAppearance() }
                        .accessibilityIdentifier("appearance.reset")
                    Text("Icon and background are optional and independent. Titles, covers, photos, and other content stay unchanged. Save applies your choices; Cancel discards them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let appearance = draft.isEmpty ? nil : draft
                        let saved: Bool
                        if let draftDisplay, let onSaveDisplay {
                            saved = onSaveDisplay(appearance, draftDisplay)
                        } else {
                            saved = onSave(appearance)
                        }
                        if saved { dismiss() }
                    }
                    .accessibilityIdentifier("appearance.save")
                }
            }
        }
        .databaseActivityOverlay()
    }
}

struct CardPhotoGallery: View {
    let photos: [KanbanAttachment]
    @Binding var photoSelection: [PhotosPickerItem]
    let onOpen: (KanbanAttachment) -> Void
    let onCaption: (UUID, String) -> Bool
    let onReorder: ([UUID]) -> Bool
    let onRemove: (KanbanAttachment) -> Void
    let onSetCover: (UUID) -> Void

    @ScaledMetric(relativeTo: .body) private var photoWidth = 220
    @ScaledMetric(relativeTo: .body) private var photoHeight = 180
    @State private var captionPhoto: KanbanAttachment?
    @State private var removalPhoto: KanbanAttachment?
    @State private var showsArrangement = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Gallery").font(.headline)
                    Spacer()
                    galleryControls
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gallery").font(.headline)
                    galleryControls
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        photoTile(photo, index: index)
                    }
                }
            }
            .accessibilityIdentifier("photoGallery.row")
        }
        .accessibilityIdentifier("photoGallery")
        .sheet(item: $captionPhoto) { photo in
            CardPhotoCaptionSheet(photo: photo) { onCaption(photo.id, $0) }
                .databaseActivityOverlay()
        }
        .sheet(isPresented: $showsArrangement) {
            CardPhotoArrangementSheet(photos: photos, onReorder: onReorder)
                .databaseActivityOverlay()
        }
        .confirmationDialog("Remove this photo?", isPresented: Binding(
            get: { removalPhoto != nil },
            set: { if !$0 { removalPhoto = nil } }
        ), titleVisibility: .visible) {
            if let photo = removalPhoto {
                Button("Remove photo", role: .destructive) {
                    onRemove(photo)
                    removalPhoto = nil
                }
            }
            Button("Cancel", role: .cancel) { removalPhoto = nil }
        } message: {
            Text("Removes the photo and its caption from this item. Photos retained elsewhere are kept.")
        }
    }

    private var galleryControls: some View {
        HStack(spacing: 12) {
            Button("Arrange", systemImage: "arrow.left.arrow.right") {
                showsArrangement = true
            }
            .disabled(photos.count < 2)
            .accessibilityLabel("Arrange gallery photos")
            .accessibilityIdentifier("photoGallery.arrange")
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 12, matching: .images) {
                Label("Add photos", systemImage: "photo.badge.plus")
            }
            .accessibilityIdentifier("photoGallery.add")
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }

    private func photoTile(_ photo: KanbanAttachment, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { onOpen(photo) } label: {
                CardCoverPreview(attachment: photo, height: photoHeight, unavailableTitle: "Photo unavailable")
                    .overlay(alignment: .bottomLeading) {
                        if let caption = photo.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.95)],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo \(index + 1)")
            .accessibilityValue(photo.caption ?? "No caption")
            .accessibilityHint("Opens the full photo. Touch and hold to drag it to another gallery position.")
            .accessibilityIdentifier("photoGallery.photo.\(photo.id)")
            .draggable("plenact.gallery.\(photo.id.uuidString)")
            .dropDestination(for: String.self) { items, _ in
                guard items.count == 1,
                      let token = items.first,
                      token.hasPrefix("plenact.gallery."),
                      let id = UUID(uuidString: String(token.dropFirst("plenact.gallery.".count))),
                      let source = photos.firstIndex(where: { $0.id == id }),
                      id != photo.id else { return false }
                var ids = photos.map(\.id)
                ids.remove(at: source)
                ids.insert(id, at: index)
                return onReorder(ids)
            }
            HStack {
                Text("Photo \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(photo.caption == nil ? "Add caption" : "Edit caption", systemImage: "text.bubble") {
                        captionPhoto = photo
                    }
                    Button("Move earlier", systemImage: "arrow.left") { movePhoto(index, by: -1) }
                        .disabled(index == 0)
                    Button("Move later", systemImage: "arrow.right") { movePhoto(index, by: 1) }
                        .disabled(index == photos.count - 1)
                    Button("Set as Cover", systemImage: "photo") { onSetCover(photo.id) }
                    Button("Remove photo", systemImage: "trash", role: .destructive) { removalPhoto = photo }
                } label: {
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

    private func movePhoto(_ index: Int, by offset: Int) {
        var ids = photos.map(\.id)
        ids.swapAt(index, index + offset)
        _ = onReorder(ids)
    }
}

struct CardPhotoCaptionSheet: View {
    let photo: KanbanAttachment
    let onSave: (String) -> Bool
    @State private var caption: String
    @Environment(\.dismiss) private var dismiss

    init(photo: KanbanAttachment, onSave: @escaping (String) -> Bool) {
        self.photo = photo
        self.onSave = onSave
        _caption = State(initialValue: photo.caption ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardCoverPreview(attachment: photo, height: 180, unavailableTitle: "Photo unavailable")
                }
                Section("Caption") {
                    TextField("Optional caption", text: $caption, axis: .vertical)
                        .accessibilityIdentifier("photoGallery.captionField")
                    Text("Shown over the bottom of the photo. Clear the text to remove its caption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Photo caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if onSave(caption) { dismiss() } }
                        .accessibilityIdentifier("photoGallery.saveCaption")
                }
            }
        }
    }
}

struct CardPhotoArrangementSheet: View {
    let photos: [KanbanAttachment]
    let onReorder: ([UUID]) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        HStack(spacing: 12) {
                            CardCoverPreview(attachment: photo, height: 64, unavailableTitle: "Photo unavailable")
                                .frame(width: 80)
                            Text(photo.caption ?? "Photo \(index + 1)")
                        }
                    }
                    .onMove { source, destination in
                        var ids = photos.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        _ = onReorder(ids)
                    }
                } footer: {
                    Text("Drag the handles to arrange photos. The cover stays separate. Changes are saved as you move photos.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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

        GeometryReader { geometry in
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
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
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
                    
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if let imageURL = CardAttachmentStore.imageURL(for: attachment),
                               let image = UIImage(contentsOfFile: imageURL.path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                ContentUnavailableView("Photo unavailable", systemImage: "photo")
                            }
                            if let caption = attachment.caption, !caption.isEmpty {
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
