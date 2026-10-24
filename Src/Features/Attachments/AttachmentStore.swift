// --------------------------------------------------------------------------------------------------
// @file       AttachmentStore.swift
// @brief      Retained attachment metadata and local media files
// @details    Validates links and stores imported media separately from owner JSON while
//             preserving attachment identities and safe file boundaries.
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
/// Identifies supported Card attachment media
///
/// @section    Purpose
///     Distinguishes retained photos, videos, audio, and web links for storage and preview
///     selection.
///
enum KanbanAttachmentKind: String, Codable, Sendable
{


    case photo
    case video
    case audio
    case link
}


///
/// Represents one retained media attachment or web link
///
/// @section    Purpose
///     Keeps attachment identity, local filename or remote URL, media kind, creation time, example
///     artwork, and optional caption together.
///
struct KanbanAttachment: Identifiable, Hashable, Codable, Sendable
{


    let id:              UUID                   /* Stable attachment identity                                */
    let fileName:        String?                /* Device-local media filename                               */
    let url:             URL?                   /* Remote web-link destination                               */
    let mediaKind:       KanbanAttachmentKind?  /* Explicit media type when known                            */
    let addedAt:         Date                   /* Attachment creation time                                  */
    let exampleImage:    ExampleCoverImage?     /* Immutable original example illustration, never user media */
    var drawingFileName: String? = nil          /* Editable PencilKit strokes, absent in legacy photos       */
    var storedFileNames: [String]
    {
        [fileName, drawingFileName].compactMap
        {
            $0
        }

    }

    var caption: String? /* Optional photo text; absent in legacy attachment records */

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
    var kind: KanbanAttachmentKind
    {  /* Resolved kind for legacy and current records */

        mediaKind ?? (url == nil ? .photo : .link)
    }


    ///
    /// @fcn        KanbanAttachment.init(id:fileName:url:mediaKind:addedAt:)
    /// @brief      Create attachment metadata for local media or a remote link
    /// @details    Stores the supplied stable identity, location metadata, and creation date
    ///
    /// @param[in]  id            Stable attachment identity
    /// @param[in]  fileName      Local media filename, when stored on this device
    /// @param[in]  url           Remote web URL, when the attachment is a link
    /// @param[in]  mediaKind     Explicit photo, video, or link content type
    /// @param[in]  addedAt       Attachment creation time
    /// @param[in]  exampleImage  Optional bundled illustration for synthetic examples
    ///
    /// @param[in]  caption       Optional retained photo caption, absent for attachments without
    ///             authored writing
    ///
    /// @return     (KanbanAttachment) configured attachment metadata
    ///
    /// @pre        Supplied metadata describes the attachment location and content, when known
    /// @post       Stored fields match the provided values
    ///
    init(
        id: UUID = UUID(), fileName: String? = nil, url: URL? = nil, mediaKind: KanbanAttachmentKind? = nil,
        addedAt: Date = .now, exampleImage: ExampleCoverImage? = nil, caption: String? = nil
    )
    {


        self.id = id
        self.fileName = fileName
        self.url = url
        self.mediaKind = mediaKind
        self.addedAt = addedAt
        self.exampleImage = exampleImage
        self.caption = caption
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
enum CardAttachmentStore
{


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
    static func coverThumbnail(for attachment: KanbanAttachment) throws -> UIImage
    {


        guard let url = imageURL(for: attachment),                   /* Resolved attachment image URL     */
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),  /* ImageIO source for the attachment */
        let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 960,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) /* Orientation-correct bounded thumbnail */
        else
        {

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
    static func fileNames(in lists: [KanbanList]) -> Set<String>
    {


        Set(lists.flatMap(\.allCards).flatMap
            {
                $0.attachments ?? []
            } .flatMap(\.storedFileNames))
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
    static func removeDeletedFiles(_ candidates: Set<String>, keeping retained: Set<String>) throws
    {


        let retained = retained.union(try PlanningRoutineStore.retainedFiles())
        for name in candidates.subtracting(retained)
        {


            guard name == (name as NSString).lastPathComponent,
            !name.isEmpty, name != ".", name != ".."
            else
            {

                throw CocoaError(.fileWriteInvalidFileName)
            }


            let attachment = KanbanAttachment(fileName: name) /* Metadata for the stored media file */

            guard let url = fileURL(for: attachment) else
            {  /* Local destination for the attachment */


                throw CocoaError(.fileNoSuchFile)
            }


            if FileManager.default.fileExists(atPath: url.path)
            {


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
    static func saveMedia(_ mediaData: Data, kind: KanbanAttachmentKind, fileExtension: String) throws
    -> KanbanAttachment
    {


        let attachmentID = UUID() /* Stable identity for the new media file */
        let normalizedExtension = fileExtension.trimmingCharacters(
            in: CharacterSet(charactersIn: ". ")) /* Clean extension input                  */
        let safeExtension =
        normalizedExtension.isEmpty
        ? (kind == .video ? "mov" : (kind == .audio ? "m4a" : "jpg"))
        : normalizedExtension                                         /* Valid file extension      */
        let fileName = "\(attachmentID.uuidString).\(safeExtension)"  /* Unique stored filename    */
        let directoryURL = try attachmentsDirectory()                 /* App-local media directory */
        let fileURL = directoryURL.appendingPathComponent(
            fileName, isDirectory: false) /* Destination file URL                   */

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
    static func fileURL(for attachment: KanbanAttachment) -> URL?
    {


        if let exampleImage = attachment.exampleImage
        {  /* Explicit bundled cover selection */


            return exampleImage.url
        }


        guard let fileName = attachment.fileName, /* Stored local filename */

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else
        {  /* App Documents directory */


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
    static func imageURL(for attachment: KanbanAttachment) -> URL?
    {


        guard attachment.kind == .photo else
        {


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
    static func webURL(from text: String) -> URL?
    {


        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized pasted or typed URL */

        guard let components = URLComponents(string: trimmedText), /* Parsed URL components */

        let scheme = components.scheme?.lowercased(), /* Normalized URL scheme */
        ["http", "https"].contains(scheme),

        let host = components.host, /* Required URL host */
        !host.isEmpty
        else
        {


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
    static func removeUnreferencedFiles(keeping fileNames: Set<String>)
    {


        guard let templateFiles = try? PlanningRoutineStore.retainedFiles() else
        {
            return
        }

        let fileNames = fileNames.union(templateFiles)
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else
        {  /* App Documents directory */


            return
        }


        let directoryURL = documentsURL.appendingPathComponent(
            directoryName, isDirectory: true) /* Attachment folder URL */

        guard
        let files = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        else
        {  /* Files available for cleanup */


            return
        }


        for fileURL in files where !fileNames.contains(fileURL.lastPathComponent)
        {


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
    private static func attachmentsDirectory() throws -> URL
    {


        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else
        {  /* App Documents directory */


            throw CocoaError(.fileNoSuchFile)
        }


        let directoryURL = documentsURL.appendingPathComponent(
            directoryName, isDirectory: true) /* Attachment folder URL */

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return directoryURL
    }

}
