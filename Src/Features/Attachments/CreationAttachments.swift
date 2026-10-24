// --------------------------------------------------------------------------------------------------
// @file       CreationAttachments.swift
// @brief      In-memory attachment capture before item creation
// @details    Retains pending media, links, and drawings and limits failed-save cleanup to files
//             created by the current draft.
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
/// Owns unsaved creation attachments
///
/// @section    Purpose
///     Keeps media in memory until explicit Add or Save and removes only newly written files on a
///     failed commit, retaining the draft for retry.
///
@MainActor
final class CreationAttachmentDraft: ObservableObject
{


    ///
    /// Identifies an in-memory creation attachment
    ///
    /// @section    Purpose
    ///     Wraps media, link, or drawing content with a stable draft ID and derived labels for the
    ///     composer.
    ///
    struct Entry: Identifiable
    {


        ///
        /// Carries the supported creation attachment payloads
        ///
        /// @section    Purpose
        ///     Retains encoded media, a link URL, or an editable drawing until explicit item
        ///     creation persists them.
        ///
        enum Content
        {


            case media(Data, KanbanAttachmentKind, String)
            case link(URL)
            case drawing(DrawingCaptureDraft)
        }

        let id = UUID()
        let content: Content
        var title:   String
        {

            switch content
            {

            case .media(_, let kind, _):
                kind == .video ? "Video" : "Photo"
            case .link(let url):
                url.absoluteString
            case .drawing:
                            "Drawing"
            }

        }

        var symbol: String
        {

            switch content
            {

            case .media(_, let kind, _):
                kind == .video ? "video" : "photo"
            case .link:
                            "link"
            case .drawing:
                            "pencil.tip.crop.circle"
            }

        }

    }


    ///
    /// Identifies creation attachment sheet destinations
    ///
    /// @section    Purpose
    ///     Distinguishes source selection, link entry, and drawing editing while preserving the
    ///     selected drawing draft.
    ///
    enum Sheet: Identifiable
    {


        case sources, link, drawing(DrawingCaptureDraft)
        var id: String
        {

            switch self
            {

            case .sources:
                            "sources"
            case .link:
                            "link"
            case .drawing(let draft):
                            "drawing-" + draft.id.uuidString
            }

        }

    }

    @Published var entries:   [Entry] = []
    @Published var sheet:     Sheet?
    @Published var selection: [PhotosPickerItem] = []
    @Published var isImporting = false
    @Published var notice: String?


    ///
    /// @fcn        CreationAttachmentDraft.openSources
    /// @brief      Open attachment capture choices from the draft
    /// @details    Ends the current text-editing context as needed and presents the available attachment sources.
    ///
    /// @return     (Void) no return value
    ///
    func openSources()
    {

        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        sheet = .sources
    }


    ///
    /// @fcn        CreationAttachmentDraft.paste
    /// @brief      Add supported clipboard content to the attachment draft
    /// @details    Reads available pasteboard media and reports unsupported or failed imports without creating a
    ///             workspace card.
    ///
    /// @return     (Void) no return value
    ///
    func paste()
    {

        sheet = nil
        if let images = UIPasteboard.general.images, !images.isEmpty
        {

            for image in images
            {

                if let data = image.pngData()
                {

                    entries.append(Entry(content: .media(data, .photo, "png")))
                }
                else
                {

                    notice = "A clipboard image couldn't be prepared. Please try again."
                }

            }

        }
        else if let url = CardAttachmentStore.webURL(
            from: UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? "")
        {

            entries.append(Entry(content: .link(url)))
        }
        else
        {

            notice = "The clipboard does not contain an image or a valid web link."
        }

    }


    ///
    /// @fcn        CreationAttachmentDraft.importSelection
    /// @brief      Load selected photo items into the draft
    /// @details    Processes the current selection asynchronously and retains successfully loaded draft media for a
    ///             later checked save.
    ///
    /// @return     (Void) no return value
    ///
    func importSelection() async
    {

        guard !selection.isEmpty else
        {
            return
        }

        let selected = selection
        isImporting = true
        sheet = nil
        defer
        {
            isImporting = false;
            selection = []
        }

        for item in selected
        {

            do
            {

                guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else
                {

                    throw CocoaError(.fileReadCorruptFile)
                }

                try Task.checkCancellation()
                let video = item.supportedContentTypes.contains
                {
                    $0.conforms(to: .movie) || $0.conforms(to: .video)
                }

                guard video || UIImage(data: data) != nil else
                {
                    throw CocoaError(.fileReadCorruptFile)
                }

                entries.append(
                    Entry(
                        content: .media(
                            data, video ? .video : .photo,
                            item.supportedContentTypes.first?.preferredFilenameExtension ?? (video ? "mov" : "jpg"))))
            }
            catch is CancellationError
            {
                return
            }
            catch
            {

                notice =
                                                "Some attachments couldn't be prepared. Your draft and attachments already added are still here."
            }

        }

    }


    ///
    /// @fcn        CreationAttachmentDraft.save
    /// @brief      Import draft attachments and run the checked owner commit
    /// @details    Rejects pending photo imports, saves each media or drawing entry, and removes newly stored files
    ///             when commit returns false or throws; links require no file import.
    ///
    /// @param[in]  commit  Owner-save callback that accepts imported attachment records and reports whether they were
    ///                     retained
    ///
    /// @return     (Bool) true if the owner retains the imported attachments; false after a rejected commit and
    ///             cleanup
    /// @throws     Explicit failures include `CocoaError(.fileReadUnknown)`, `CocoaError(.fileReadCorruptFile)`.
    ///             Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func save(commit: ([KanbanAttachment]) throws -> Bool) throws -> Bool
    {

        guard !isImporting, selection.isEmpty else
        {
            throw CocoaError(.fileReadUnknown)
        }

        var stored: [KanbanAttachment] = []
        do
        {

            for entry in entries
            {

                switch entry.content
                {

                case .media(let data, let kind, let ext):
                    guard !data.isEmpty, kind != .photo || UIImage(data: data) != nil else
                    {

                        throw CocoaError(.fileReadCorruptFile)
                    }

                    stored.append(try CardAttachmentStore.saveMedia(data, kind: kind, fileExtension: ext))
                case .link(let url):
                    stored.append(KanbanAttachment(url: url, mediaKind: .link))
                case .drawing(let drawing):
                    stored.append(try DrawingAttachmentStore.save(drawing))
                }

            }

            if try commit(stored)
            {
                return true
            }

            try CardAttachmentStore.removeDeletedFiles(Set(stored.flatMap(\.storedFileNames)), keeping: [])
            return false
        }
        catch
        {

            try? CardAttachmentStore.removeDeletedFiles(Set(stored.flatMap(\.storedFileNames)), keeping: [])
            throw error
        }

    }

}


///
/// Displays pending attachments in a creation draft
///
/// @section    Purpose
///     Shows media previews and removal controls that update only the in-memory draft entries.
///
struct CreationAttachmentList: View
{


    @ObservedObject var draft: CreationAttachmentDraft
    var body:                  some View
    {

        VStack(alignment: .leading, spacing: 12)
        {

            ForEach(draft.entries)
            {
                entry in
                HStack
                {

                    if case .media(let data, .photo, _) = entry.content, let image = UIImage(data: data)
                    {

                        Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipped()
                        .accessibilityHidden(true)
                    }
                    else
                    {

                        Image(systemName: entry.symbol).frame(width: 44)
                    }

                    Text(entry.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Button(role: .destructive)
                    {

                        draft.entries.removeAll
                        {
                            $0.id == entry.id
                        }

                    }
                    label:
                    {

                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Remove attachment: " + entry.title)
                }

            }

            if draft.isImporting
            {
                ProgressView("Preparing attachments…")
            }

            Button("Add Attachment", systemImage: "paperclip", action: draft.openSources)
            .frame(minHeight: 44).disabled(draft.isImporting)
            .accessibilityIdentifier("creation.addAttachment")
        }

    }

}


///
/// Connects attachment presentation to a creation draft
///
/// @section    Purpose
///     Hosts source, link, and drawing sheets and imports selected media without creating a Card.
///
struct CreationAttachmentPresentation: ViewModifier
{


    @ObservedObject var draft: CreationAttachmentDraft


    ///
    /// @fcn        CreationAttachmentPresentation.body
    /// @brief      Present creation attachment sources, links, and drawing capture
    /// @details    Connects source and drawing sheets to the draft, imports photo selections asynchronously, and
    ///             presents attachment notices without creating a card.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) present creation attachment sources, links, and drawing capture
    ///
    func body(content: Content) -> some View
    {

        content
        .sheet(item: $draft.sheet)
        {
            sheet in
            switch sheet
            {

            case .sources:
                CardAttachmentSourceSheet(
                    photoSelection: $draft.selection,
                    onAddLink:
                    {
                        draft.sheet = .link
                    }, onPasteClipboard: draft.paste,
                    onComingSoon:
                    {
                        source in
                        draft.sheet = nil;
                        draft.notice = source + " isn't available yet."
                    },
                    onAddDrawing:
                    {
                        draft.sheet = .drawing(DrawingCaptureDraft())
                    })
            case .link:
                CardLinkAttachmentSheet
                {
                    url in
                    draft.entries.append(.init(content: .link(url)))
                }

            case .drawing(let initial):
                DrawingCaptureEditor(initial: initial)
                {
                    drawing in
                    draft.entries.append(.init(content: .drawing(drawing)))
                    return true
                }

            }

        }
        .task(id: draft.selection)
        {
            await draft.importSelection()
        }
        .alert(
                            "Attachments",
                            isPresented: Binding(get:
                                {
                                    draft.notice != nil
                                }, set:
                                {
                                    if !$0
                                    {
                                        draft.notice = nil
                                    }

                                })
        )
        {

            Button("OK", role: .cancel)
            {
                draft.notice = nil
            }

        }
        message:
        {

            Text(draft.notice ?? "")
        }

    }

}
