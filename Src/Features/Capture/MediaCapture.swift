// --------------------------------------------------------------------------------------------------
// @file       MediaCapture.swift
// @brief      Camera and voice capture lifecycle
// @details    Coordinates selected photo bytes, recording, transcription, and explicit media
//             commits with cleanup limited to failed draft files
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Coordinates voice recording and transcription
///
/// @section    Purpose
///     Publishes capture status and errors, retains recording and speech tasks, and uses generation
///     tracking to reject obsolete asynchronous work
///
@MainActor
final class QuickCaptureVoice: NSObject, ObservableObject, AVAudioRecorderDelegate
{
    @Published private(set) var isRecording    = false          /* Recording state               */
    @Published private(set) var isStarting     = false          /* Starting state                */
    @Published private(set) var isTranscribing = false          /* Transcribing state            */
    @Published var transcript                  = ""             /* Recognized speech text        */
    @Published var errorMessage: String?                        /* User-facing failure message   */
    private var generation = 0                                  /* Current navigation generation */

    @Published private(set) var recordingURL: URL?              /* Recording URL               */
    private var recorder:        AVAudioRecorder?               /* Audio recording controller  */
    private var speechTask:      SFSpeechRecognitionTask?       /* Speech task                 */
    private var timeout:         Task<Void, Never>?             /* Foreground return threshold */


    ///
    /// @fcn        QuickCaptureVoice.start
    /// @brief      Request recording access and begin voice capture
    /// @details    Sets up the recording session and local file, publishes capture status, and reports authorization
    ///             or recording setup failures
    ///
    /// @return     (Void) no return value
    ///
    func start() async
    {
        guard !isStarting, !isRecording else
        {
            return
        }

        isStarting = true

        let permissionToken = generation        /* Permission token */

        NotificationCenter.default.post(name: Notification.Name("Plenact.StopAudioPreview"), object: nil)
        defer
        {
            isStarting = false
        }

        let granted =                                           /* Requested access result */
            await AVAudioApplication.requestRecordPermission()

        guard granted else
        {
            errorMessage = "Microphone access is unavailable. You can allow it in Settings → Plenact.";

            return
        }

        guard !Task.isCancelled, permissionToken == generation else
        {
            return
        }

        cleanup()

        let url =                                                               /* Resolved file location */
            FileManager.default.temporaryDirectory.appendingPathComponent(
                "plenact-voice-" + UUID().uuidString + ".m4a")

        do
        {
            let session = AVAudioSession.sharedInstance()       /* Current operation session */

            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let recorder = try AVAudioRecorder(         /* Audio recording controller */
                url: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ])

            recorder.delegate = self

            guard recorder.record(forDuration: 60) else
            {
                throw CocoaError(.fileWriteUnknown)
            }

            self.recorder = recorder;
            recordingURL = url;
            isRecording = true
        }
        catch
        {
            try? FileManager.default.removeItem(at: url)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

            errorMessage = "Recording couldn't start. Your draft is still here; please try again."
        }
    }


    ///
    /// @fcn        QuickCaptureVoice.stop
    /// @brief      Stop the active voice recorder
    /// @details    Ends recording through the recorder so its completion delegate can update capture and
    ///             transcription state
    ///
    /// @return     (Void) no return value
    ///
    func stop()
    {
        guard isRecording else
        {
            return
        }

        recorder?.stop();

        recorder = nil;
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }


    ///
    /// @fcn        QuickCaptureVoice.audioRecorderDidFinishRecording
    /// @brief      Handle completion of a voice recording
    /// @details    Updates recording state and starts transcription only for a successfully completed recording
    ///
    /// @param[in]  recorder  Audio recorder delivering completion
    /// @param[in]  flag      Whether the system reports successful completion
    ///
    /// @return     (Void) no return value
    ///
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool)
    {
        Task
        {
            @MainActor [weak self] in
            guard let self, self.isRecording, self.recordingURL == recorder.url else
            {
                return
            }

            self.stop()
            if !flag
            {
                self.errorMessage = "Recording was interrupted. Preview the recording before saving."
            }
        }
    }


    ///
    /// @fcn        QuickCaptureVoice.transcribe
    /// @brief      Transcribe the captured audio when speech access permits
    /// @details    Creates an asynchronous speech-recognition request, publishes its result, and reports
    ///             authorization or recognition failures without discarding the recording
    ///
    /// @return     (Void) no return value
    ///
    func transcribe() async
    {
        guard let url = recordingURL, !isRecording, !isTranscribing else
        {
            return
        }

        isTranscribing = true;
        errorMessage = nil
        generation += 1

        let token  = generation                         /* Retained operation token */
        let status = await withCheckedContinuation      /* Current operation status */
        {
            continuation in
            SFSpeechRecognizer.requestAuthorization
            {
                continuation.resume(returning: $0)
            }
        }

        guard !Task.isCancelled, token == generation, recordingURL == url else
        {
            return
        }

        guard status == .authorized else
        {
            isTranscribing = false
            errorMessage =
                                    "Speech recognition is unavailable. You can enable it in Settings, keep the recording as Audio, or enter the transcript yourself."

            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else
        {
            isTranscribing = false;

            errorMessage = "Speech recognition isn't available right now. Retry later or save Audio instead.";

            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)           /* Pending lookup request */

        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        speechTask = recognizer.recognitionTask(with: request)
        {
            [weak self] result, error in

            let text   = result?.bestTranscription.formattedString      /* Text being processed      */
            let final  = result?.isFinal == true                        /* Final operation value     */
            let failed = error != nil                                   /* Rejected operation result */

            Task
            {
                @MainActor in
                guard let self, self.generation == token else
                {
                    return
                }

                if let text
                {
                    self.transcript = text
                }

                if final || failed
                {
                    self.generation += 1
                    self.isTranscribing = false;
                    self.speechTask = nil;

                    self.timeout?.cancel()
                    if failed && !final
                    {
                        self.errorMessage =
                                                                        "Transcription couldn't finish. Review any text below, retry, or save Audio instead."
                    }
                }
            }
        }

        timeout?.cancel()

        timeout = Task
        {
            [weak self] in
            do
            {
                try await Task.sleep(for: .seconds(30))
            }
            catch
            {
                return
            }

            guard let self, self.generation == token, self.isTranscribing else
            {
                return
            }

            self.cancelTranscription()

            self.errorMessage = "Transcription took too long. Retry, enter text yourself, or save Audio instead."
        }
    }


    ///
    /// @fcn        QuickCaptureVoice.cancelTranscription
    /// @brief      Cancel outstanding speech recognition work
    /// @details    Stops and clears the retained recognition task so later capture work does not reuse it
    ///
    /// @return     (Void) no return value
    ///
    func cancelTranscription()
    {
        generation += 1;

        speechTask?.cancel();

        speechTask = nil

        timeout?.cancel();

        timeout = nil;
        isTranscribing = false
    }


    ///
    /// @fcn        QuickCaptureVoice.audioData
    /// @brief      Read the current recording's encoded audio
    /// @details    Loads the captured file and propagates file access failures rather than returning invented audio
    ///             data
    ///
    /// @return     (Data) recorded file bytes ready for attachment import
    /// @throws     Explicit failures include `CocoaError(.fileReadNoSuchFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation
    ///
    func audioData() throws -> Data
    {
        guard let recordingURL, !isRecording else
        {
            throw CocoaError(.fileReadNoSuchFile)
        }

        return try Data(contentsOf: recordingURL)
    }


    ///
    /// @fcn        QuickCaptureVoice.cleanup
    /// @brief      Release voice capture work and its temporary file
    /// @details    Stops recording, cancels transcription, and removes retained temporary recording resources
    ///
    /// @return     (Void) no return value
    ///
    func cleanup()
    {
        cancelTranscription();
        stop()
        if let recordingURL
        {
            try? FileManager.default.removeItem(at: recordingURL)
        }

        recordingURL = nil;
        transcript = ""
    }
}


///
/// Retains a selected photograph before creation
///
/// @section    Purpose
///     Keeps encoded bytes and their extension with a temporary identity; image decoding does not
///     persist an attachment
///
struct QuickCapturePhoto: Identifiable
{
    let id = UUID()                     /* Record UUID             */
    let data:          Data             /* Encoded or loaded bytes */
    let fileExtension: String           /* File extension          */

    var image:         UIImage?         /* Image used by this operation */
    {
        UIImage(data: data)
    }
}


///
/// Commits quick-capture media with failure cleanup
///
/// @section    Purpose
///     Writes files only for explicit submission and removes this draft's newly created files when
///     the owner rejects the handoff
///
@MainActor
enum QuickCaptureMediaCommit
{
    ///
    /// @fcn        QuickCaptureMediaCommit.save
    /// @brief      Import capture media and commit its attachment records
    /// @details    Tracks newly created photo, audio, and drawing files; retains them only when the supplied owner
    ///             commit accepts the records and removes them on failure
    ///
    /// @param[in]  photos    Photo drafts to import before committing the owner update
    /// @param[in]  audio     Optional recorded audio bytes to import
    /// @param[in]  drawings  Editable drawing drafts to import
    /// @param[in]  commit    Owner-save callback that accepts imported attachment records and reports whether they
    ///                       were retained
    ///
    /// @return     (Bool) true if the owner accepts the imported records; false after a rejected commit and cleanup
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation
    ///
    static func save(
        _ photos: [QuickCapturePhoto],
        audio:    Data?                 = nil,
        drawings: [DrawingCaptureDraft] = [],
        commit:   ([KanbanAttachment]) -> Bool
    ) throws -> Bool
    {
        var saved: [KanbanAttachment] = []      /* Saved state under review */

        do
        {
            for photo in photos
            {
                guard photo.image != nil else
                {
                    throw CocoaError(.fileReadCorruptFile)
                }

                saved.append(
                    try CardAttachmentStore.saveMedia(photo.data, kind: .photo, fileExtension: photo.fileExtension))
            }

            for drawing in drawings
            {
                saved.append(try DrawingAttachmentStore.save(drawing))
            }

            if let audio
            {
                guard !audio.isEmpty else
                {
                    throw CocoaError(.fileReadCorruptFile)
                }

                saved.append(try CardAttachmentStore.saveMedia(audio, kind: .audio, fileExtension: "m4a"))
            }

            if commit(saved)
            {
                return true
            }

            try CardAttachmentStore.removeDeletedFiles(Set(saved.flatMap(\.storedFileNames)), keeping: [])
            return false
        }
        catch
        {
            try? CardAttachmentStore.removeDeletedFiles(Set(saved.flatMap(\.storedFileNames)), keeping: [])
            throw error
        }
    }
}


///
/// Bridges the system camera into quick capture
///
/// @section    Purpose
///     Delivers a selected image through the caller's callback and dismisses on capture or
///     cancellation
///
struct QuickCaptureCamera: UIViewControllerRepresentable
{
    let onPhoto: (UIImage) -> Void                      /* Photo callback                 */
    @Environment(\.dismiss) private var dismiss         /* Close the current presentation */


    ///
    /// @fcn        QuickCaptureCamera.makeCoordinator
    /// @brief      Create the native bridge coordinator
    /// @details    Creates the coordinator retained by SwiftUI for QuickCaptureCamera so its delegate or observation
    ///             state can span view updates
    ///
    /// @return     (Coordinator) retained native bridge coordinator
    ///
    func makeCoordinator() -> Coordinator
    {
        Coordinator(parent: self)
    }


    ///
    /// @fcn        QuickCaptureCamera.makeUIViewController
    /// @brief      Create the camera picker used by quick capture
    /// @details    Configures camera capture and assigns the coordinator as the picker delegate
    ///
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (UIImagePickerController) camera picker configured to deliver captures to its coordinator
    ///
    func makeUIViewController(context: Context) -> UIImagePickerController
    {
        let picker = UIImagePickerController()          /* Native selection control */

        picker.sourceType = .camera;
        picker.delegate = context.coordinator

        return picker
    }


    ///
    /// @fcn        QuickCaptureCamera.updateUIViewController
    /// @brief      Satisfy camera-picker updates without resetting capture
    /// @details    The picker is configured during creation and has no incremental update work in this representable
    ///
    /// @param[in]  controller  Native controller supplied to the lifecycle callback
    /// @param[in]  context     Framework-supplied update context and coordinator access
    ///
    /// @return     (Void) no return value
    ///
    func updateUIViewController(_ controller: UIImagePickerController, context: Context)
    {
    }


    ///
    /// Handles camera selection and cancellation delegates
    ///
    /// @section    Purpose
    ///     Retains the camera representable so UIKit delegate events reach its image callback and
    ///     dismissal action
    ///
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate
    {
        let parent: QuickCaptureCamera          /* Latest representable bindings */


        ///
        /// @fcn        QuickCaptureCamera.Coordinator.init
        /// @brief      Retain the camera representable for delegate callbacks
        /// @details    Keeps the current parent value so capture and cancellation callbacks can reach its selection
        ///             and dismissal actions
        ///
        /// @param[in]  parent  Representable value supplying the delegate's current bindings and callbacks
        ///
        /// @return     (Coordinator) initialized instance
        ///
        init(parent: QuickCaptureCamera)
        {
            self.parent = parent
        }


        ///
        /// @fcn        QuickCaptureCamera.Coordinator.imagePickerControllerDidCancel
        /// @brief      Dismiss a cancelled camera capture
        /// @details    Invokes the parent capture presentation's dismissal path without producing an image
        ///
        /// @param[in]  picker  Native camera controller delivering the delegate callback
        ///
        /// @return     (Void) no return value
        ///
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController)
        {
            parent.dismiss()
        }


        ///
        /// @fcn        QuickCaptureCamera.Coordinator.imagePickerController
        /// @brief      Receive the photo selected by the camera picker
        /// @details    Extracts the captured image, hands it to the parent callback when available, and finishes the
        ///             picker presentation
        ///
        /// @param[in]  picker  Native camera controller delivering the delegate callback
        /// @param[in]  info    System image-picker metadata for the selected capture
        ///
        /// @return     (Void) no return value
        ///
        func imagePickerController(
            _ picker:                           UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        )
        {
            if let image = info[.originalImage] as? UIImage
            {
                parent.onPhoto(image)
            }

            parent.dismiss()
        }
    }
}
