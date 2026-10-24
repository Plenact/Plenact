// --------------------------------------------------------------------------------------------------
// @file       DrawingEditor.swift
// @brief      Editable PencilKit capture and drawing export
// @details    Keeps a stable native canvas and stroke data alongside bounded previews, explicit
//             saves, and user-selected sharing.
//
// --------------------------------------------------------------------------------------------------
import AVKit
import Foundation
import ImageIO
import PencilKit
import PhotosUI
import SwiftUI
import UIKit


// MARK: - Editable drawing capture


///
/// Retains editable drawing strokes and a cached preview
///
/// @section    Purpose
///     Uses a stable draft identity and bounded raster preview so composer updates do not
///     repeatedly render PencilKit content.
///
struct DrawingCaptureDraft: Identifiable
{


    let id:      UUID
    let drawing: PKDrawing
    let preview: UIImage


    ///
    /// @fcn        DrawingCaptureDraft.init
    /// @brief      Create an editable drawing draft with a cached preview
    /// @details    Retains its identity and PencilKit strokes and renders a bounded 960-point preview so composer
    ///             typing does not repeatedly rasterize the drawing.
    ///
    /// @param[in]  id       Stable draft or objective identity
    /// @param[in]  drawing  PencilKit strokes used as the editable drawing source
    ///
    /// @return     (DrawingCaptureDraft) initialized instance
    ///
    init(id: UUID = UUID(), drawing: PKDrawing = PKDrawing())
    {

        self.id = id
        self.drawing = drawing
        // Cache a bounded preview so typing in the composer never rerenders every drawing.
        preview = DrawingImageExport.image(drawing, transparent: false, maximumDimension: 960)
    }

}


///
/// Defines supported raster drawing export formats
///
/// @section    Purpose
///     Distinguishes PNG from JPEG so encoding and transparency behavior can follow the user's
///     export choice.
///
enum DrawingImageFormat: String, CaseIterable
{


    case png, jpeg
}


///
/// Renders PencilKit content for preview and export
///
/// @section    Purpose
///     Bounds output dimensions and controls transparency independently of the editable stroke
///     data.
///
enum DrawingImageExport
{


    ///
    /// @fcn        DrawingImageExport.image
    /// @brief      Render a drawing into a bounded raster image
    /// @details    Uses drawing bounds and the requested maximum dimension, applying a transparent or opaque export
    ///             surface as requested.
    ///
    /// @param[in]  drawing           PencilKit strokes used as the editable drawing source
    /// @param[in]  transparent       Whether the exported PNG or drawing image should preserve transparency
    /// @param[in]  maximumDimension  Maximum raster dimension used to bound drawing previews
    ///
    /// @return     (UIImage) bounded raster preview of the drawing with the requested background treatment
    ///
    /// @note       Crop to the marks with a small margin; cap raster size without changing editable strokes.
    ///
    static func image(_ drawing: PKDrawing, transparent: Bool, maximumDimension: CGFloat = 4096) -> UIImage
    {

        let bounds = drawing.bounds
        let rect =
        bounds.isNull || bounds.isEmpty
        ? CGRect(x: 0, y: 0, width: 600, height: 800) : bounds.insetBy(dx: -24, dy: -24)
        let scale = min(2, maximumDimension / max(rect.width, rect.height))
        let ink = drawing.image(from: rect, scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = !transparent
        return UIGraphicsImageRenderer(size: rect.size, format: format).image
        {
            context in
            if !transparent
            {
                UIColor.white.setFill();
                context.fill(CGRect(origin: .zero, size: rect.size))
            }

            ink.draw(in: CGRect(origin: .zero, size: rect.size))
        }

    }


    ///
    /// @fcn        DrawingImageExport.data
    /// @brief      Encode nonempty drawing strokes as PNG or JPEG
    /// @details    Rejects an empty drawing, permits transparency only for PNG, uses 0.95 JPEG quality, and throws if
    ///             image encoding fails.
    ///
    /// @param[in]  drawing      PencilKit strokes used as the editable drawing source
    /// @param[in]  format       Selected drawing export format
    /// @param[in]  transparent  Whether the exported PNG or drawing image should preserve transparency
    ///
    /// @return     (Data) PNG or JPEG image bytes for the nonempty drawing
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`, `CocoaError(.fileWriteUnknown)`.
    ///             Errors from throwing dependencies propagate unless handled within this operation.
    ///
    static func data(_ drawing: PKDrawing, format: DrawingImageFormat, transparent: Bool = false) throws -> Data
    {

        guard !drawing.strokes.isEmpty else
        {
            throw CocoaError(.fileReadCorruptFile)
        }

        let image = image(drawing, transparent: format == .png && transparent)
        guard let data = format == .png ? image.pngData() : image.jpegData(compressionQuality: 0.95) else
        {

            throw CocoaError(.fileWriteUnknown)
        }

        return data
    }

}


///
/// Persists drawing attachments and their editable source
///
/// @section    Purpose
///     Writes strokes and preview files together while retaining an existing attachment identity
///     when updating a drawing.
///
enum DrawingAttachmentStore
{


    ///
    /// @fcn        DrawingAttachmentStore.save
    /// @brief      Save both editable strokes and a drawing preview
    /// @details    Creates the files needed by the attachment and preserves the appropriate previous attachment
    ///             identity when updating an existing drawing.
    ///
    /// @param[in]  draft     Editable value proposed for persistence
    /// @param[in]  previous  Previous saved drawing attachment or preceding review, when available
    ///
    /// @return     (KanbanAttachment) photo attachment linking the new preview and editable stroke files
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`, `CocoaError(.fileWriteUnknown)`.
    ///             Errors from throwing dependencies propagate unless handled within this operation.
    ///
    /// @note       New files are written before publishing metadata. Previous files remain safe until normal pruning.
    ///
    static func save(_ draft: DrawingCaptureDraft, replacing previous: KanbanAttachment? = nil) throws
    -> KanbanAttachment
    {

        guard !draft.drawing.strokes.isEmpty else
        {
            throw CocoaError(.fileReadCorruptFile)
        }

        let png = try DrawingImageExport.data(draft.drawing, format: .png)
        let preview = try CardAttachmentStore.saveMedia(png, kind: .photo, fileExtension: "png")
        guard let previewURL = CardAttachmentStore.fileURL(for: preview) else
        {
            throw CocoaError(.fileWriteUnknown)
        }

        let strokesURL = previewURL.deletingPathExtension().appendingPathExtension("drawing")
        do
        {

            try draft.drawing.dataRepresentation().write(to: strokesURL, options: .atomic)
        }
        catch
        {

            try? FileManager.default.removeItem(at: previewURL)
            throw error
        }

        var attachment = KanbanAttachment(
            id: previous?.id ?? preview.id, fileName: preview.fileName,
            mediaKind: .photo, addedAt: previous?.addedAt ?? preview.addedAt, caption: previous?.caption)
        attachment.drawingFileName = strokesURL.lastPathComponent
        return attachment
    }


    ///
    /// @fcn        DrawingAttachmentStore.load
    /// @brief      Restore editable strokes from a drawing attachment
    /// @details    Reads the attachment's retained drawing data and throws when the editable source cannot be loaded.
    ///
    /// @param[in]  attachment  Attachment whose retained drawing source should be loaded
    ///
    /// @return     (DrawingCaptureDraft) editable drawing draft reconstructed from the stored stroke file
    /// @throws     Explicit failures include `CocoaError(.fileReadNoSuchFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    static func load(_ attachment: KanbanAttachment) throws -> DrawingCaptureDraft
    {

        guard let name = attachment.drawingFileName, name == URL(fileURLWithPath: name).lastPathComponent,
        let previewURL = CardAttachmentStore.fileURL(for: attachment)
        else
        {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let data = try Data(contentsOf: previewURL.deletingLastPathComponent().appendingPathComponent(name))
        return DrawingCaptureDraft(id: attachment.id, drawing: try PKDrawing(data: data))
    }

}


///
/// Owns a stable PencilKit canvas and observable editing state
///
/// @section    Purpose
///     Publishes mark and Undo availability through canvas delegate events while preserving the
///     native canvas across SwiftUI updates.
///
@MainActor
final class DrawingCanvasState: NSObject, ObservableObject, PKCanvasViewDelegate
{


    let canvas = DrawingCanvasView()
    @Published var hasMarks: Bool
    @Published var canUndo = false
    @Published var canRedo = false


    ///
    /// @fcn        DrawingCanvasState.init
    /// @brief      Configure a retained PencilKit canvas for editing
    /// @details    Loads the initial strokes, installs the delegate and black pen, enables any input, and sets the
    ///             canvas size and maximum zoom.
    ///
    /// @param[in]  drawing  PencilKit strokes used as the editable drawing source
    ///
    /// @return     (DrawingCanvasState) initialized instance
    ///
    init(drawing: PKDrawing)
    {

        hasMarks = !drawing.strokes.isEmpty
        super.init()
        canvas.drawing = drawing
        canvas.delegate = self
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.contentSize = CGSize(width: 1200, height: 1600)
        canvas.maximumZoomScale = 3
    }


    ///
    /// @fcn        DrawingCanvasState.canvasViewDrawingDidChange
    /// @brief      Publish a canvas stroke change to editor state
    /// @details    Updates the observable drawing and undo availability from the PencilKit delegate callback.
    ///
    /// @param[in]  canvasView  Canvas view supplied to this operation
    ///
    /// @return     (Void) no return value
    ///
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView)
    {

        hasMarks = !canvasView.drawing.strokes.isEmpty
        // PencilKit registers undo after its drawing-change delegate callback.
        DispatchQueue.main.async
        {
            [weak self] in
            self?.refreshUndo()
        }

    }


    ///
    /// @fcn        DrawingCanvasState.refreshUndo
    /// @brief      Refresh the canvas's undo and redo availability
    /// @details    Reads both capabilities from the canvas undo manager for the editor controls.
    ///
    /// @return     (Void) no return value
    ///
    func refreshUndo()
    {

        canUndo = canvas.undoManager?.canUndo ?? false;
        canRedo = canvas.undoManager?.canRedo ?? false
    }


    ///
    /// @fcn        DrawingCanvasState.undo
    /// @brief      Undo the canvas's most recent drawing edit
    /// @details    Delegates to its undo manager and refreshes the published control availability.
    ///
    /// @return     (Void) no return value
    ///
    func undo()
    {
        canvas.undoManager?.undo();
        refreshUndo()
    }


    ///
    /// @fcn        DrawingCanvasState.redo
    /// @brief      Redo the canvas's next available drawing edit
    /// @details    Uses the canvas undo manager and refreshes availability after the operation.
    ///
    /// @return     (Void) no return value
    ///
    func redo()
    {
        canvas.undoManager?.redo();
        refreshUndo()
    }


    ///
    /// @fcn        DrawingCanvasState.clear
    /// @brief      Clear canvas strokes with a registered inverse edit
    /// @details    Captures the previous drawing in the canvas undo manager before assigning an empty drawing and
    ///             refreshing Undo availability.
    ///
    /// @return     (Void) no return value
    ///
    func clear()
    {

        let previous = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: self)
        {
            target in
            target.restore(previous)
        }

        canvas.drawing = PKDrawing()
        refreshUndo()
    }


    ///
    /// @fcn        DrawingCanvasState.restore
    /// @brief      Restore canvas strokes with a registered inverse edit
    /// @details    Captures the previous drawing for Undo, replaces the native canvas drawing, and refreshes Undo and
    ///             Redo availability.
    ///
    /// @param[in]  drawing  PencilKit strokes used as the editable drawing source
    ///
    /// @return     (Void) no return value
    ///
    private func restore(_ drawing: PKDrawing)
    {

        let previous = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: self)
        {
            target in
            target.restore(previous)
        }

        canvas.drawing = drawing
        refreshUndo()
    }

}


///
/// Keeps the PencilKit tool picker attached to its canvas
///
/// @section    Purpose
///     Responds to window and size changes so drawing tools and canvas presentation follow the
///     native view lifecycle.
///
@MainActor
final class DrawingCanvasView: PKCanvasView
{


    private let picker = PKToolPicker()
    private var lastSize = CGSize.zero


    ///
    /// @fcn        DrawingCanvasView.didMoveToWindow
    /// @brief      Reconnect the PencilKit tool picker after attachment
    /// @details    Calls the superclass lifecycle method and updates tool presentation for the current window.
    ///
    /// @return     (Void) no return value
    ///
    override func didMoveToWindow()
    {

        super.didMoveToWindow()
        if window != nil
        {

            picker.addObserver(self)
            DispatchQueue.main.async
            {
                [weak self] in
                self?.showTools()
            }

        }
        else
        {

            picker.setVisible(false, forFirstResponder: self)
            picker.removeObserver(self)
        }

    }


    ///
    /// @fcn        DrawingCanvasView.showTools
    /// @brief      Present the tool picker for the attached drawing canvas
    /// @details    Associates the picker with the canvas and requests the appropriate first-responder tool
    ///             interaction.
    ///
    /// @return     (Void) no return value
    ///
    func showTools()
    {

        guard window != nil else
        {
            return
        }

        becomeFirstResponder()
        picker.setVisible(true, forFirstResponder: self)
    }


    ///
    /// @fcn        DrawingCanvasView.layoutSubviews
    /// @brief      Refresh drawing-tool placement after layout
    /// @details    Runs the superclass layout before updating the canvas's tool-picker presentation.
    ///
    /// @return     (Void) no return value
    ///
    override func layoutSubviews()
    {

        super.layoutSubviews()
        guard bounds.size != lastSize, bounds.width > 0, bounds.height > 0 else
        {
            return
        }

        lastSize = bounds.size
        let fit = min(bounds.width / 1200, bounds.height / 1600)
        minimumZoomScale = fit
        zoomScale = fit
    }

}


///
/// Bridges the retained drawing canvas into SwiftUI
///
/// @section    Purpose
///     Reuses DrawingCanvasState's native view so strokes and Undo history survive declarative view
///     updates.
///
struct DrawingCanvas: UIViewRepresentable
{


    let state: DrawingCanvasState


    ///
    /// @fcn        DrawingCanvas.makeUIView
    /// @brief      Create the editor's native PencilKit canvas
    /// @details    Returns the canvas held by the shared drawing state so its strokes and Undo manager remain stable
    ///             across SwiftUI updates.
    ///
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (DrawingCanvasView) the existing PencilKit canvas retained by the drawing state object
    ///
    func makeUIView(context: Context) -> DrawingCanvasView
    {
        state.canvas
    }


    ///
    /// @fcn        DrawingCanvas.updateUIView
    /// @brief      Retain the existing canvas during SwiftUI updates
    /// @details    No incremental update is needed because DrawingCanvasState owns and directly updates the same
    ///             native canvas instance.
    ///
    /// @param[in]  view     Native view inspected or synchronized by the operation
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (Void) no return value
    ///
    func updateUIView(_ view: DrawingCanvasView, context: Context)
    {

    }

}


///
/// Identifies a prepared drawing export file
///
/// @section    Purpose
///     Keeps the temporary URL associated with a particular share presentation.
///
struct DrawingExportFile: Identifiable
{


    let id = UUID()
    let url: URL
}


///
/// Presents the system share sheet for a drawing export
///
/// @section    Purpose
///     Passes the prepared file URL to UIActivityViewController so the user chooses its
///     destination.
///
struct DrawingShareSheet: UIViewControllerRepresentable
{


    let url: URL


    ///
    /// @fcn        DrawingShareSheet.makeUIViewController
    /// @brief      Create the system sheet for a drawing export
    /// @details    Passes the exported file URL to UIActivityViewController for the user's chosen share or save
    ///             action.
    ///
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (UIActivityViewController) system activity controller containing the exported drawing file
    ///
    func makeUIViewController(context: Context) -> UIActivityViewController
    {

        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }


    ///
    /// @fcn        DrawingShareSheet.updateUIViewController
    /// @brief      Retain the current drawing share controller during updates
    /// @details    No incremental controller update is needed because the share payload is supplied at creation.
    ///
    /// @param[in]  controller  Native controller supplied to the lifecycle callback
    /// @param[in]  context     Framework-supplied update context and coordinator access
    ///
    /// @return     (Void) no return value
    ///
    func updateUIViewController(_ controller: UIActivityViewController, context: Context)
    {

    }

}


///
/// Edits a drawing with explicit Save and discard handling
///
/// @section    Purpose
///     Owns canvas state, export presentation, and errors; checked saves preserve an editable draft
///     when the caller rejects the result.
///
struct DrawingCaptureEditor: View
{


    let initial:                    DrawingCaptureDraft
    let onSave:                     (DrawingCaptureDraft) -> Bool
    @StateObject private var state: DrawingCanvasState
    @State private var showsClear = false
    @State private var showsDiscard = false
    @State private var errorMessage:    String?
    @State private var exportFile:      DrawingExportFile?
    @State private var exportDirectory: URL?
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        DrawingCaptureEditor.init
    /// @brief      Initialize a drawing editor without saving its draft
    /// @details    Retains the initial draft and checked save callback and creates a state object containing its
    ///             editable PencilKit canvas.
    ///
    /// @param[in]  initial  Initial editable drawing draft
    /// @param[in]  onSave   Save callback returning true only when the owner accepts the edited value
    ///
    /// @return     (DrawingCaptureEditor) initialized instance
    ///
    init(initial: DrawingCaptureDraft, onSave: @escaping (DrawingCaptureDraft) -> Bool)
    {

        self.initial = initial;
        self.onSave = onSave
        _state = StateObject(wrappedValue: DrawingCanvasState(drawing: initial.drawing))
    }

    private var changed: Bool
    {
        state.canvas.drawing.dataRepresentation() != initial.drawing.dataRepresentation()
    }


    ///
    /// @fcn        DrawingCaptureEditor.export
    /// @brief      Create a temporary drawing export for sharing
    /// @details    Encodes the selected format and transparency, retains the export URL for presentation, and reports
    ///             failures without replacing the draft drawing.
    ///
    /// @param[in]  format       Selected drawing export format
    /// @param[in]  transparent  Whether the exported PNG or drawing image should preserve transparency
    ///
    /// @return     (Void) no return value
    ///
    private func export(_ format: DrawingImageFormat, transparent: Bool = false)
    {

        do
        {

            let data = try DrawingImageExport.data(state.canvas.drawing, format: format, transparent: transparent)
            cleanExport()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "Plenact-Drawing-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            exportDirectory = directory
            let url = directory.appendingPathComponent("Drawing." + (format == .png ? "png" : "jpg"))
            try data.write(to: url, options: .atomic)
            exportFile = DrawingExportFile(url: url)
        }
        catch
        {

            cleanExport();

            errorMessage = "The image couldn't be exported. Your drawing is still here; please try again."
        }

    }


    ///
    /// @fcn        DrawingCaptureEditor.cleanExport
    /// @brief      Remove the editor's temporary export file
    /// @details    Releases the current export URL after removing its file so later sharing begins with a fresh
    ///             export.
    ///
    /// @return     (Void) no return value
    ///
    private func cleanExport()
    {

        if let exportDirectory
        {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        exportDirectory = nil
    }

    var body: some View
    {

        NavigationStack
        {

            DrawingCanvas(state: state)
            .accessibilityLabel("Drawing canvas")
            .navigationTitle("Drawing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Cancel")
                    {
                        if changed
                        {
                            showsDiscard = true
                        }
                        else
                        {
                            dismiss()
                        }

                    }

                }

                ToolbarItemGroup(placement: .primaryAction)
                {

                    Menu
                    {

                        Button("Drawing tools", systemImage: "pencil.tip.crop.circle")
                        {
                            state.canvas.showTools()
                        }

                        Button("Undo", systemImage: "arrow.uturn.backward")
                        {
                            state.undo()
                        } .disabled(
                            !state.canUndo)
                        Button("Redo", systemImage: "arrow.uturn.forward")
                        {
                            state.redo()
                        } .disabled(!state.canRedo)
                        Button("Clear drawing", systemImage: "trash", role: .destructive)
                        {
                            showsClear = true
                        }
                        .disabled(!state.hasMarks)
                    }
                    label:
                    {

                        Image(systemName: "ellipsis.circle")
                    } .accessibilityLabel("Drawing actions")
                    Menu
                    {

                        Button("PNG · White background")
                        {
                            export(.png)
                        }

                        Button("PNG · Transparent background")
                        {
                            export(.png, transparent: true)
                        }

                        Button("JPEG · White background")
                        {
                            export(.jpeg)
                        }

                    }
                    label:
                    {

                        Image(systemName: "square.and.arrow.up")
                    } .accessibilityLabel("Export drawing").disabled(!state.hasMarks)
                    Button("Done")
                    {

                        let draft = DrawingCaptureDraft(id: initial.id, drawing: state.canvas.drawing)
                        if onSave(draft)
                        {

                            dismiss()
                        }
                        else
                        {

                            errorMessage =
                                                                                            "The drawing couldn't be saved. Your changes are still here; please try again."
                        }

                    } .disabled(!state.hasMarks)
                }

            }

        }
        .interactiveDismissDisabled(changed)
        .confirmationDialog("Clear this drawing?", isPresented: $showsClear, titleVisibility: .visible)
        {

            Button("Clear drawing", role: .destructive)
            {
                state.clear()
            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        .confirmationDialog("Discard drawing changes?", isPresented: $showsDiscard, titleVisibility: .visible)
        {

            Button("Discard changes", role: .destructive)
            {
                dismiss()
            }

            Button("Keep drawing", role: .cancel)
            {

            }

        }
        .alert("Drawing", isPresented: Binding(get:
                {
                    errorMessage != nil
                }, set:
                {
                    if !$0
                    {
                        errorMessage = nil
                    }

                }))
        {

            Button("OK", role: .cancel)
            {
                errorMessage = nil
            }

        }
        message:
        {

            Text(errorMessage ?? "")
        }
        .sheet(item: $exportFile, onDismiss: cleanExport)
        {
            file in
            DrawingShareSheet(url: file.url)
        }
        .task
        {

            // Wait for the sheet's navigation controller to finish attaching its canvas.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else
            {
                return
            }

            state.canvas.showTools()
        }
        .onDisappear
        {
            if exportFile == nil
            {
                cleanExport()
            }

        }
        .presentationDetents([.large])
    }

}
