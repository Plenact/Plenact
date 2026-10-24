// --------------------------------------------------------------------------------------------------
// @file       NewItemComposer.swift
// @brief      Full-featured Card and Note creation drafts
// @details    Retains unsaved writing and attachments and submits complete content through checked
//             destination callbacks.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Edits a full Card or Note creation draft
///
/// @section    Purpose
///     Combines writing, templates, scheduling, and media with checked submission callbacks;
///     retained drafts survive cancellation and failed saves.
///
struct QuickNoteComposer: View
{


    @State private var keyboardContextID = UUID()
    @StateObject private var attachmentDraft = CreationAttachmentDraft()
    @Binding var lists: [KanbanList] /* Current destination lists */
    let onSave:         (Int, String, String, String, ItemPresentation?, [String]?) -> Void
    let template:       QuickCaptureTemplate?
    let captureAction:  TodayCaptureAction?
    let draftKey:       String?
    @State private var acceptsDraftEdits = true
    let onSaveCapture:                ((QuickCaptureSubmission) -> Bool)?
    @State private var drawings:      [DrawingCaptureDraft] = []
    @State private var drawingToEdit: DrawingCaptureDraft?
    @State private var offeredDrawing = false
    @State private var photos:         [QuickCapturePhoto] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsPhotoSources = false
    @State private var showsPhotoLibrary = false
    @State private var showsCamera = false
    @State private var offeredPhotoSources = false
    @State private var importingPhotos = false
    @State private var mediaError: String?
    @StateObject private var voice = QuickCaptureVoice()
    @State private var voiceSaveOption: VoiceCaptureSaveOption = .both
    @State private var replaceRecording = false
    @State private var hasStartDate = false
    @State private var hasStopDate = false
    @State private var startDate = Date.now
    @State private var stopDate = Date.now
    @State private var includesDateTime = false
    @Environment(\.scenePhase) private var scenePhase
    private var schedule: QuickCaptureSchedule
    {

        QuickCaptureSchedule(
            start: hasStartDate ? startDate : nil, stop: hasStopDate ? stopDate : nil, includesTime: includesDateTime)
    }

    private var voiceReady: Bool
    {

        guard captureAction == .voice else
        {
            return true
        }

        return !voice.isStarting && !voice.isRecording && !voice.isTranscribing
        && (!voiceSaveOption.savesAudio || voice.recordingURL != nil)
        && (!voiceSaveOption.savesText || !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }


    @Environment(\.dismiss) private var dismiss /* Close the full-size editor */

    @State private var presentation: ItemPresentation
    @State private var createdAt = Date.now
    @State private var subtitle = ""
    @State private var title = ""            /* New card title                   */
    @State private var description = ""      /* Optional card detail             */
    @State private var selectedListID: Int?  /* Destination selected in the form */
    @State private var actions:        [KanbanChecklistItem]


    ///
    /// @fcn        QuickNoteComposer.init(lists:initialListID:initialTitle:template:onSave:)
    /// @brief      Configure the card composer with destinations and a submission callback
    /// @details    Seeds the optional destination without mutating lists; the form validates
    ///             that the selected identity still exists before permitting Add
    ///
    /// @param[in]  lists                Binding to available destination lists
    /// @param[in]  initialListID        Optional initially selected destination identity
    /// @param[in]  initialTitle         Existing inline title transferred into the composer
    /// @param[in]  template             Optional local starting point with explicit Card/Note presentation
    /// @param[in]  onSave               Callback receiving destination, text, and optional template presentation/actions
    /// @param[in]  draftKey             Optional preference key for retaining unsaved composer writing
    /// @param[in]  captureAction        Optional capture mode used to configure initial creation controls
    /// @param[in]  initialPresentation  Optional explicit Card or Note presentation before applying
    ///             destination defaults
    /// @param[in]  onSaveCapture        Optional checked full-submission callback; rejected saves keep
    ///             the draft available
    ///
    /// @return     (QuickNoteComposer) initialized unsaved composer
    ///
    init(
        lists: Binding<[KanbanList]>,
        initialListID: Int?,
        initialTitle: String = "",
        draftKey: String? = nil,
        template: QuickCaptureTemplate? = nil,
        captureAction: TodayCaptureAction? = nil,
        initialPresentation: ItemPresentation? = nil,
        onSaveCapture: ((QuickCaptureSubmission) -> Bool)? = nil,
        onSave: @escaping (Int, String, String, String, ItemPresentation?, [String]?) -> Void
    )
    {


        _lists = lists
        self.draftKey = draftKey
        let savedDraft = draftKey.map
        {
            ListCreationDraft.load(key: $0)
        }

        _subtitle = State(initialValue: savedDraft?.subtitle ?? "")
        _presentation = State(
            initialValue: captureAction?.presentation ?? template?.presentation ?? initialPresentation ?? lists
            .wrappedValue.first(where:
                {
                    $0.id == initialListID
                })?.newItemPresentation ?? .card)
        // Explicit inline writing takes priority over a previously retained composer title.
        let suppliedTitle = initialTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : initialTitle
        _title = State(
            initialValue: template?.draftTitle(capturedTitle: initialTitle) ?? suppliedTitle ?? savedDraft?.title
            ?? initialTitle)
        _description = State(initialValue: template?.body ?? savedDraft?.description ?? "")
        _actions = State(
            initialValue: captureAction == .checklist
            ? [KanbanChecklistItem(title: "")] : (template?.actions ?? []).map
            {
                KanbanChecklistItem(title: $0)
            })
        _selectedListID = State(initialValue: initialListID)
        self.template = template
        self.captureAction = captureAction
        self.onSaveCapture = onSaveCapture
        self.onSave = onSave
    }


    ///
    /// @fcn        QuickNoteComposer.trimmedTitle
    /// @brief      Normalize the card title for validation and submission
    /// @details    Removes leading and trailing whitespace/newlines without altering internal text
    ///
    /// @return     (String) normalized title
    /// @post       The editable title draft remains unchanged
    ///
    private var trimmedTitle: String
    {  /* Card title without surrounding whitespace */

        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        QuickNoteComposer.body
    /// @brief      Present card text entry and destination selection
    /// @details    Disables Add until a nonempty trimmed title and an existing list resolve;
    ///             Add trims the title/Card description but preserves Note body whitespace
    ///             before submitting to the callback and dismissing the composer
    ///
    /// @return     (some View) large-sheet navigation form with Cancel and Add actions
    /// @post       Cancel discards the draft; creating/persisting a submitted card belongs to onSave
    ///
    private var destinationPicker: some View
    {

        Picker("List", selection: $selectedListID)
        {

            Text("Choose a list").tag(nil as Int?)
            ForEach(lists)
            {
                list in
                Text(list.title).tag(Optional(list.id))
            }

        } .pickerStyle(.menu)
    }


    private var drawingControls: some View
    {

        VStack(alignment: .leading, spacing: 12)
        {

            ForEach(drawings)
            {
                drawing in
                HStack
                {

                    Button
                    {

                        drawingToEdit = drawing
                    }
                    label:
                    {

                        Image(uiImage: drawing.preview).resizable().scaledToFit().frame(maxHeight: 150)
                    } .buttonStyle(.plain).accessibilityLabel("Edit drawing")
                    Button("Remove drawing", systemImage: "trash", role: .destructive)
                    {

                        drawings.removeAll
                        {
                            $0.id == drawing.id
                        }

                    }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }

            }

            Button("Add drawing", systemImage: "pencil.tip")
            {
                drawingToEdit = DrawingCaptureDraft()
            }
            .frame(minHeight: 44).disabled(drawings.count >= 6)
            Text("Drawings stay editable. Tap a preview to edit or export it. They are attached when you tap Add.")
            .font(.caption).foregroundStyle(.secondary)
        }

    }

    private var dateControls: some View
    {

        VStack(alignment: .leading, spacing: 12)
        {

            Toggle("Start date", isOn: $hasStartDate)
            if hasStartDate
            {

                DatePicker(
                                                "Start", selection: $startDate,
                                                displayedComponents: includesDateTime ? [.date, .hourAndMinute] : [.date])
            }

            Toggle("Stop date", isOn: $hasStopDate)
            if hasStopDate
            {

                DatePicker(
                                                "Stop", selection: $stopDate,
                                                displayedComponents: includesDateTime ? [.date, .hourAndMinute] : [.date])
            }

            Toggle("Include times", isOn: $includesDateTime)
            Text("Both dates are optional. Stop sets the item's due date, so it appears in Calendar.")
            .font(.caption).foregroundStyle(.secondary)
            if !schedule.isValid()
            {
                Text("Stop must be on or after Start.").foregroundStyle(.red)
            }

        }

    }

    private var voiceControls: some View
    {

        VStack(alignment: .leading, spacing: 12)
        {

            Picker("Save as", selection: $voiceSaveOption)
            {

                ForEach(VoiceCaptureSaveOption.allCases)
                {
                    option in
                    Text(option.rawValue).tag(option)
                }

            } .pickerStyle(.segmented)
            if voice.isRecording
            {

                Label("Recording · up to 60 seconds", systemImage: "record.circle").foregroundStyle(.red)
                Button("Stop recording", systemImage: "stop.circle")
                {
                    voice.stop()
                } .frame(minHeight: 44)
            }
            else
            {

                Button(voice.recordingURL == nil ? "Record a thought" : "Record again", systemImage: "mic")
                {

                    if voice.recordingURL != nil
                    {
                        replaceRecording = true
                    }
                    else
                    {
                        Task
                        {
                            await voice.start()
                        }

                    }

                } .frame(minHeight: 44).disabled(voice.isStarting || voice.isTranscribing)
                if voice.isStarting
                {
                    ProgressView("Preparing microphone…")
                }

                if let url = voice.recordingURL
                {
                    AudioAttachmentPlayer(url: url)
                }

            }

            if voiceSaveOption.savesText
            {

                if voice.isTranscribing
                {

                    ProgressView("Transcribing…")
                    Button("Cancel transcription")
                    {
                        voice.cancelTranscription()
                    }

                }
                else if voice.recordingURL != nil
                {

                    Button(
                        voice.transcript.isEmpty ? "Transcribe recording" : "Transcribe again",
                        systemImage: "text.bubble"
                    )
                    {
                        Task
                        {
                            await voice.transcribe()
                        }

                    }
                    .disabled(voice.isRecording)
                }

                TextField("Transcript · review or edit before saving", text: $voice.transcript, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .lineLimit(3 ... 10).disabled(voice.isRecording || voice.isTranscribing)
            }

            if let error = voice.errorMessage
            {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }

            Text(
                                    "Audio keeps the recording; Text adds your reviewed transcript to the item's writing; Both keeps each. Transcription uses Apple’s speech recognition and may need an internet connection. Nothing is added to your List until you tap Add."
            )
            .font(.caption).foregroundStyle(.secondary)
        }

    }


    private var photoControls: some View
    {

        VStack(alignment: .leading, spacing: 12)
        {

            if importingPhotos
            {
                ProgressView("Preparing photos…")
            }

            ForEach(photos)
            {
                photo in
                HStack
                {

                    if let image = photo.image
                    {

                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 140)
                        .accessibilityLabel("Photo to attach")
                    }

                    Button("Remove photo", systemImage: "trash", role: .destructive)
                    {

                        photos.removeAll
                        {
                            $0.id == photo.id
                        }

                    }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }

            }

            Button("Add photo", systemImage: "camera")
            {
                showsPhotoSources = true
            }
            .frame(minHeight: 44).disabled(importingPhotos)
            Text("Photos are attached when you tap Add. Cancelling leaves your original Quick capture title in place.")
            .font(.caption).foregroundStyle(.secondary)
        }

    }


    ///
    /// @fcn        QuickNoteComposer.openCamera
    /// @brief      Open camera capture when the device supports it
    /// @details    Checks capture availability and authorization before presenting, retaining user-facing feedback
    ///             when the camera cannot be used.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor private func openCamera() async
    {

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else
        {

            mediaError = "A camera isn't available on this device. Choose Photo library instead."
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined
        {
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        }

        if allowed
        {

            showsCamera = true
        }
        else
        {

            mediaError =
                                    "Camera access is unavailable. You can allow it in Settings → Plenact, or choose Photo library."
        }

    }


    ///
    /// @fcn        QuickNoteComposer.importPhotos
    /// @brief      Import selected photo data into the capture draft
    /// @details    Loads the current selections asynchronously and updates the in-memory photo draft without creating
    ///             owner records yet.
    ///
    /// @return     (Void) no return value
    ///
    @MainActor private func importPhotos() async
    {

        guard !photoSelection.isEmpty else
        {
            return
        }

        importingPhotos = true
        defer
        {
            importingPhotos = false;
            photoSelection = []
        }

        do
        {

            for item in photoSelection
            {

                guard let data = try await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else
                {

                    throw CocoaError(.fileReadCorruptFile)
                }

                try Task.checkCancellation()
                photos.append(
                    QuickCapturePhoto(
                        data: data, fileExtension: item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    ))
            }

        }
        catch is CancellationError
        {
            return
        }
        catch
        {

            mediaError = "Some photos couldn't be prepared. Your draft and any photos already added are still here."
        }

    }


    ///
    /// @fcn        QuickNoteComposer.finishDraft
    /// @brief      Clear a finished draft and reject late editor updates
    /// @details    Disables draft edits before clearing retained draft content so keyboard dismissal cannot recreate
    ///             it.
    ///
    /// @return     (Void) no return value
    ///
    private func finishDraft()
    {

        acceptsDraftEdits = false
        if let draftKey
        {
            ListCreationDraft.clear(key: draftKey)
        }

    }


    ///
    /// @fcn        QuickNoteComposer.registerKeyboardDraft
    /// @brief      Register creation actions for the active keyboard context
    /// @details    Provides the current composer actions to the shared keyboard context without committing a new
    ///             item.
    ///
    /// @return     (Void) no return value
    ///
    private func registerKeyboardDraft()
    {

        PlenactKeyboard.shared.setContext(
            keyboardContextID,
            actions: KeyboardCardActions(
                exit:
                {

                    finishDraft();
                    dismiss()
                },
                attachment: attachmentDraft.openSources,
                checklist: presentation == .card
                ?
                {

                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    actions.append(KanbanChecklistItem(title: ""))
                } : nil,
                showsUpperBorder: true
            ))
    }


    var body: some View
    {  /* New-card form and destination controls */


        NavigationStack
        {

            VStack(spacing: 0)
            {

                ContentCreationKindPicker(presentation: $presentation).padding(.horizontal, 20).padding(.vertical, 12)
                if presentation == .note
                {

                    ScrollView
                    {

                        VStack(alignment: .leading, spacing: 18)
                        {

                            destinationPicker
                            TextField("Note title", text: $title, axis: .vertical).textInputAutocapitalization(
                                .sentences
                            )
                            .font(.largeTitle.weight(.bold))
                            NoteCreationDateLabel(createdAt: createdAt)
                            CreationAttachmentList(draft: attachmentDraft)
                            if captureAction == .photo || !photos.isEmpty
                            {
                                photoControls
                            }

                            if captureAction == .voice
                            {
                                voiceControls
                            }

                            if captureAction == .drawing || !drawings.isEmpty
                            {
                                drawingControls
                            }

                            if onSaveCapture != nil
                            {

                                DisclosureGroup("Start and stop dates")
                                {
                                    dateControls
                                }

                            }

                            RichTextEditor(placeholder: "Start writing...", text: $description, minimumHeight: 320)
                        } .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    } .background(Color(.systemGroupedBackground))
                }
                else
                {

                    Form
                    {

                        Section(presentation.title)
                        {

                            TextField("Title", text: $title, axis: .vertical).textInputAutocapitalization(.sentences)
                            .lineLimit(1 ... 6)
                            TextField("Subtitle (optional)", text: $subtitle).textInputAutocapitalization(.sentences)
                            RichTextEditor(placeholder: "Details (optional)", text: $description)
                        }


                        if (template != nil || captureAction == .checklist || !actions.isEmpty) && presentation == .card
                        {

                            Section("Actions")
                            {

                                ForEach($actions)
                                {
                                    $action in
                                    TextField("Action", text: $action.title).textInputAutocapitalization(.sentences)
                                }
                                .onDelete
                                {
                                    actions.remove(atOffsets: $0)
                                }

                                Button("Add action", systemImage: "plus")
                                {

                                    actions.append(KanbanChecklistItem(title: ""))
                                }

                            }

                        }


                        Section("Attachments")
                        {
                            CreationAttachmentList(draft: attachmentDraft)
                        }

                        if captureAction == .photo || !photos.isEmpty
                        {
                            Section("Photos")
                            {
                                photoControls
                            }

                        }

                        if captureAction == .voice
                        {
                            Section("Voice capture")
                            {
                                voiceControls
                            }

                        }

                        if captureAction == .drawing || !drawings.isEmpty
                        {
                            Section("Drawings")
                            {
                                drawingControls
                            }

                        }

                        if onSaveCapture != nil
                        {

                            Section("Dates")
                            {

                                DisclosureGroup("Start and stop dates")
                                {
                                    dateControls
                                }

                            }

                        }


                        Section("Add to")
                        {

                            if lists.isEmpty
                            {


                                Text("Create a list in Week before adding a card.")
                                .foregroundStyle(.secondary)
                            }
                            else
                            {

                                Picker("List", selection: $selectedListID)
                                {

                                    Text("Choose a list").tag(nil as Int?)
                                    ForEach(lists)
                                    {
                                        list in
                                        Text(list.title).tag(Optional(list.id))
                                    }

                                }

                                .pickerStyle(.menu)
                            }

                        }

                    }

                }

            }

            .navigationTitle("New \(presentation.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {


                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Cancel")
                    {

                        finishDraft()
                        dismiss()
                    }

                }


                ToolbarItem(placement: .confirmationAction)
                {


                    Button("Add")
                    {

                        guard let selectedListID, /* Chosen Week destination identity */
                        lists.contains(where:
                            {
                                $0.id == selectedListID
                            })
                        else
                        {
                            return
                        }

                        let editedActions = actions.map
                        {
                            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        .filter
                        {
                            !$0.isEmpty
                        }

                        let originalBody =
                        presentation == .note
                        ? description : description.trimmingCharacters(in: .whitespacesAndNewlines)
                        let body =
                        captureAction == .voice
                        ? voiceSaveOption.body(existing: originalBody, transcript: voice.transcript) : originalBody
                        let actionTitles: [String]? =
                        template != nil || captureAction == .checklist || !editedActions.isEmpty
                        ? editedActions : nil
                        if let onSaveCapture
                        {

                            guard voiceReady, schedule.isValid() else
                            {
                                return
                            }

                            do
                            {

                                let audio =
                                captureAction == .voice && voiceSaveOption.savesAudio ? try voice.audioData() : nil
                                guard
                                try attachmentDraft.save(commit:
                                    {
                                        additional in
                                        try QuickCaptureMediaCommit.save(
                                            photos, audio: audio, drawings: drawings,
                                            commit:
                                            {
                                                attachments in
                                                onSaveCapture(
                                                    QuickCaptureSubmission(
                                                        listID: selectedListID, title: trimmedTitle, body: body,
                                                        subtitle: subtitle.trimmingCharacters(
                                                            in: .whitespacesAndNewlines), presentation: presentation,
                                                        actions: actionTitles, attachments: attachments + additional,
                                                        schedule: hasStartDate || hasStopDate ? schedule : nil))
                                            })
                                    })
                                else
                                {

                                    mediaError =
                                                                                                            "This capture could not be saved. Your draft is still open; check its List and try again.";

                                    return
                                }

                            }
                            catch
                            {

                                mediaError =
                                                                                                "Your capture couldn't be saved. Your draft is still open; please try again.";

                                return
                            }

                        }
                        else
                        {

                            guard attachmentDraft.entries.isEmpty else
                            {

                                mediaError = "This destination couldn't save attachments. Your draft is still open.";

                                return
                            }

                            onSave(
                                selectedListID, trimmedTitle, body,
                                subtitle.trimmingCharacters(in: .whitespacesAndNewlines), presentation, actionTitles)
                        }

                        finishDraft()
                        dismiss()
                    }

                    .disabled(
                        importingPhotos || attachmentDraft.isImporting || !voiceReady || !schedule.isValid()
                        || trimmedTitle.isEmpty || selectedListID == nil
                        || !lists.contains(where:
                            {
                                $0.id == selectedListID
                            }))
                }

            }

        }

        .modifier(CreationAttachmentPresentation(draft: attachmentDraft))
        .onAppear
        {
            registerKeyboardDraft()
        }
        .onChange(of: [title, subtitle, description])
        {
            _, _ in
            guard acceptsDraftEdits, let draftKey else
            {
                return
            }

            ListCreationDraft(title: title, subtitle: subtitle, description: description).save(key: draftKey)
        }
        .onChange(of: presentation)
        {
            _, _ in
            registerKeyboardDraft()
        }
        .onDisappear
        {
            PlenactKeyboard.shared.removeContext(keyboardContextID)
        }
        .task
        {

            if captureAction == .drawing && !offeredDrawing
            {

                offeredDrawing = true;
                drawingToEdit = DrawingCaptureDraft()
            }

            if captureAction == .photo && !offeredPhotoSources
            {
                offeredPhotoSources = true;
                showsPhotoSources = true
            }

        }
        .sheet(item: $drawingToEdit)
        {
            draft in
            DrawingCaptureEditor(initial: draft)
            {
                updated in
                if let index = drawings.firstIndex(where:
                    {
                        $0.id == updated.id
                    })
                {

                    drawings[index] = updated
                }
                else
                {

                    drawings.append(updated)
                }

                return true
            }

        }
        .confirmationDialog("Add an attachment", isPresented: $showsPhotoSources, titleVisibility: .visible)
        {

            Button("Take photo")
            {
                Task
                {
                    await openCamera()
                }

            }

            Button("Photo library")
            {
                showsPhotoLibrary = true
            }

            if onSaveCapture != nil
            {
                Button("Drawing")
                {
                    drawingToEdit = DrawingCaptureDraft()
                }

            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        .photosPicker(
            isPresented: $showsPhotoLibrary, selection: $photoSelection, maxSelectionCount: 12, matching: .images
        )
        .task(id: photoSelection)
        {
            await importPhotos()
        }
        .sheet(isPresented: $showsCamera)
        {

            QuickCaptureCamera
            {
                image in
                if let data = image.jpegData(compressionQuality: 0.9)
                {

                    photos.append(QuickCapturePhoto(data: data, fileExtension: "jpg"))
                }
                else
                {

                    mediaError = "This photo couldn't be prepared. Please try again."
                }

            } .ignoresSafeArea()
        }
        .onChange(of: voice.isRecording)
        {
            wasRecording, recording in
            if wasRecording && !recording && voice.recordingURL != nil && voiceSaveOption.savesText
            && scenePhase == .active
            {

                Task
                {
                    await voice.transcribe()
                }

            }

        }
        .onChange(of: scenePhase)
        {
            _, phase in
            if phase != .active
            {
                voice.stop()
            }

        }
        .onChange(of: voiceSaveOption)
        {
            _, option in
            if !option.savesText
            {
                voice.cancelTranscription()
            }

        }
        .onDisappear
        {
            voice.cleanup()
        }
        .interactiveDismissDisabled(voice.isRecording || voice.isStarting || voice.isTranscribing)
        .confirmationDialog(
                        "Replace this recording and transcript?", isPresented: $replaceRecording, titleVisibility: .visible
        )
        {

            Button("Record again", role: .destructive)
            {
                Task
                {
                    await voice.start()
                }

            }

            Button("Keep recording", role: .cancel)
            {

            }

        }
        .alert(
                        "Capture not saved", isPresented: Binding(get:
                            {
                                mediaError != nil
                            }, set:
                            {
                                if !$0
                                {
                                    mediaError = nil
                                }

                            })
        )
        {

            Button("OK", role: .cancel)
            {
                mediaError = nil
            }

        }
        message:
        {

            Text(mediaError ?? "")
        }
        .presentationDetents([.large])
    }

}


///
/// Creates a Note draft with a selectable personal List destination
///
/// @section    Purpose
///     Offer a roomy, writing-first draft that is committed only after explicit Save
///
struct NewPersonalNoteComposer: View
{


    let availablePersonalLists:        [PersonalCollection]
    let onSave:                        (UUID, QuickCaptureSubmission, Date) throws -> Void
    @State private var destinationIDs: [UUID]
    @State private var createdAt = Date.now
    private let initialCollectionID: UUID


    ///
    /// @fcn        NewPersonalNoteComposer.init
    /// @brief      Freeze available personal-list destinations for creation
    /// @details    Retains the checked save callback and captures stable destination UUIDs so numeric selection
    ///             values cannot drift as collections change.
    ///
    /// @param[in]  initialCollectionID     Initially selected personal-list owner UUID
    /// @param[in]  availablePersonalLists  Snapshot of personal-list owners available when creation starts
    /// @param[in]  onSave                  Owner-save callback that throws if the full capture cannot be retained
    ///
    /// @return     (NewPersonalNoteComposer) initialized instance
    ///
    init(
        initialCollectionID: UUID, availablePersonalLists: [PersonalCollection],
        onSave: @escaping (UUID, QuickCaptureSubmission, Date) throws -> Void
    )
    {

        self.initialCollectionID = initialCollectionID
        self.availablePersonalLists = availablePersonalLists
        self.onSave = onSave
        _destinationIDs = State(initialValue: PersonalListNoteDraft.destinations(in: availablePersonalLists).map(\.id))
    }

    private var destinations: [KanbanList]
    {

        destinationIDs.enumerated().compactMap
        {
            index, id in
            guard let owner = availablePersonalLists.first(where:
                {
                    $0.id == id && $0.kind == .list && $0.isActive
                })
            else
            {
                return nil
            }

            return KanbanList(id: index, title: owner.title, cards: [])
        }

    }


    ///
    /// @fcn        NewPersonalNoteComposer.save
    /// @brief      Save a full capture to its selected personal-list owner
    /// @details    Resolves the captured destination identity, calls the throwing owner-save callback, and returns
    ///             false with feedback when creation is rejected.
    ///
    /// @param[in]  capture  Full capture submission including presentation, text, schedule, and attachments
    ///
    /// @return     (Bool) true after the selected owner's save succeeds; false when selection or saving fails
    ///
    private func save(_ capture: QuickCaptureSubmission) -> Bool
    {

        guard destinationIDs.indices.contains(capture.listID) else
        {
            return false
        }

        let ownerID = destinationIDs[capture.listID]
        guard availablePersonalLists.contains(where:
            {
                $0.id == ownerID && $0.kind == .list && $0.isActive
            }) else
        {

            return false
        }

        do
        {
            try onSave(ownerID, capture, createdAt);
            return true
        }
        catch
        {

            DatabaseActivity.shared.report(
                                    "Could not save this item. Your draft remains open: \(error.localizedDescription)")
            return false
        }

    }

    var body: some View
    {

        QuickNoteComposer(
            lists: .constant(destinations), initialListID: destinationIDs.firstIndex(of: initialCollectionID),
            initialPresentation: .note, onSaveCapture: save
        )
        {
            id, title, body, subtitle, presentation, actions in
            _ = save(
                QuickCaptureSubmission(
                    listID: id, title: title, body: body, subtitle: subtitle,
                    presentation: presentation ?? .note, actions: actions, attachments: [], schedule: nil))
        }

    }

}
