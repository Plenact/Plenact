// --------------------------------------------------------------------------------------------------
// @file       LocalDataExportView.swift
// @brief      Private local backup preparation and explicit Files export
// @details    Supports User Data Model 1.0 migration preparation; source backup format 1.
//             Preserves legacy storage without conversion, restoration, network access or fallback data.
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UniformTypeIdentifiers


/// Transfers a frozen directory into Files only after the user chooses its destination.
/// @section Purpose
///     Keep export preparation separate from saving or sharing private source content.
struct LegacyBackupDocument: FileDocument
{

    static var readableContentTypes: [UTType] { [.folder] }
    private let serialized: Data /* Immutable Sendable snapshot; reconstruct a fresh wrapper per save */


    /// @fcn LegacyBackupDocument.init
    /// @brief Wrap an already prepared source backup
    /// @param[in] files Frozen directory tree
    /// @return An export-only document
    /// @throws A serialization error if the complete snapshot cannot be retained
    init(files: FileWrapper) throws
    {

        guard let serialized = files.serializedRepresentation else
        {
            throw CocoaError(.fileWriteUnknown)
        }
        self.serialized = serialized
    }


    /// @fcn LegacyBackupDocument.init
    /// @brief Refuse importing/restoring through the export-only document path
    /// @param[in] configuration Requested read configuration
    /// @return No value; throws unsupported operation
    /// @throws Cocoa unsupported-read error
    init(configuration: ReadConfiguration) throws
    {

        throw CocoaError(.fileReadUnsupportedScheme)
    }


    /// @fcn LegacyBackupDocument.fileWrapper
    /// @brief Supply the prepared directory to the system exporter
    /// @param[in] configuration Files export configuration
    /// @return Frozen source files
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
    {

        guard let wrapper = FileWrapper(serializedRepresentation: serialized) else
        {
            throw CocoaError(.fileReadCorruptFile)
        }
        return wrapper
    }
}


/// Provides an explicit local source-backup milestone before Model 1.0 conversion.
/// @section Purpose
///     Let the owner preserve saved data, inspect preflight results and choose a Files destination.
struct LocalDataExportView: View
{

    @Environment(\.localBackupRestore) private var restoreAccess
    @State private var choosingRestore = false
    @State private var confirmsRestore = false
    @State private var reviewedRestore: ReviewedLocalBackup?
    @State private var preview: MigrationPreview? /* Explicitly partial conversion summary */
    @State private var document: LegacyBackupDocument? /* Immutable Files transfer snapshot */
    @State private var backup:    LegacyWorkspaceBackup? /* Retained only during this screen */
    @State private var preparing = false                 /* Prevent repeated capture requests */
    @State private var saving = false                    /* System Files destination chooser */
    @State private var message: String?                  /* Local status without raw values   */


    /// @fcn LocalDataExportView.body
    /// @brief Present backup scope, preparation, review and explicit saving
    /// @return The local backup workflow
    var body: some View
    {

        Form
        {
            Section
            {
                Text("Preserve your saved Plenact data and original media in a local backup folder.")
                Text("This prepares for the new data model. It does not convert your workspace or turn on cloud synchronization.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section
            {
                Button(action: prepare)
                {
                    Label(preparing ? "Preparing backup…" : "Prepare local backup", systemImage: "externaldrive")
                }
                .disabled(preparing)
                if preparing
                {
                    ProgressView()
                }
            }
            if let backup
            {
                Section("Prepared backup")
                {
                    LabeledContent("Saved stores", value: String(backup.storeCount))
                    LabeledContent("Media files", value: String(backup.mediaCount))
                    Text(backup.reviewCodes.isEmpty
                        ? "Source data preserved. Portable conversion is the next step."
                        : "Source data preserved with items needing review. The report is included in the backup.")
                    if !backup.reviewCodes.isEmpty
                    {
                        LabeledContent("Review items", value: String(backup.reviewCodes.count))
                    }
                    Button("Prepare migration preview", action: preparePreview)
                        .disabled(preparing)
                    if let preview
                    {
                        LabeledContent("Converted preview records", value: String(preview.recordCount))
                        Text("Labels and saved display choices are converted so far. The preview includes its mapping journal and a report of what remains. Your cloud account is not linked.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button(preview == nil ? "Save backup to Files…" : "Save backup and preview to Files…")
                    {
                        saving = true
                    }
                }
            }
            if let message
            {
                Section
                {
                    Text(message)
                }
            }
            #if targetEnvironment(simulator)
            Section("Simulator recovery test")
            {
                Button("Choose backup folder…")
                {
                    choosingRestore = true
                }
                .disabled(preparing || restoreAccess == nil)
                if let reviewedRestore
                {
                    LabeledContent("Saved stores", value: String(reviewedRestore.storeCount))
                    LabeledContent("Board Lists", value: String(reviewedRestore.listCount))
                    LabeledContent("Active Board Cards", value: String(reviewedRestore.cardCount))
                    LabeledContent("Media files", value: String(reviewedRestore.mediaCount))
                    Button("Restore into this Simulator…")
                    {
                        confirmsRestore = true
                    }
                    .disabled(preparing || restoreAccess == nil)
                }
                if (try? FullMonthExampleStore.live().hasNativeRestoreBackup) == true
                {
                    Button("Undo last test restore")
                    {
                        restoreAccess?.undo()
                    }
                }
                Text("This restores the original local backup, including its saved settings. The current Simulator workspace is retained for undo. It does not import Model 1.0 cloud data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            #endif
            Section
            {
                Text("The folder contains private writing and media. Choose a destination you trust. Only saved changes are included; finish editing before preparing a fresh backup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $choosingRestore, allowedContentTypes: [.folder])
        { result in
            do
            {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer
                {
                    if access
                    {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                reviewedRestore = nil
                reviewedRestore = try LocalBackupRestore.review(at: url)
                message = "Backup verified. Review the counts before confirming the Simulator restore."
            }
            catch
            {
                reviewedRestore = nil
                message = "Backup review did not finish: " + error.localizedDescription
            }
        }
        .confirmationDialog("Restore this local backup?", isPresented: $confirmsRestore, titleVisibility: .visible)
        {
            Button("Restore into this Simulator", role: .destructive)
            {
                if let reviewedRestore
                {
                    restoreAccess?.restore(reviewedRestore)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        message:
        {
            Text("Replaces this Simulator’s saved workspace and settings with the reviewed backup. A verified copy of its current data is retained for undo.")
        }
        .navigationTitle("Local backup")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(preparing)
        .fileExporter(isPresented: $saving,
            document: document,
            contentType: .folder, defaultFilename: "Plenact Backup")
        { result in
            switch result
            {
            case .success: message = "Backup saved. Your Plenact workspace is unchanged."
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError
                {
                    message = "The backup could not be saved. Please choose a destination and try again."
                }
            }
        }
    }


    /// @fcn LocalDataExportView.preparePreview
    /// @brief Convert supported fields from the existing frozen snapshot using durable local IDs
    /// @details The private journal is persisted before the preview is made available to Files.
    /// @return Void; retains the original backup if conversion cannot complete
    private func preparePreview()
    {

        guard let backup else
        {
            return
        }
        preparing = true
        message = nil
        Task { @MainActor in
            await Task.yield()
            defer { preparing = false }
            do
            {
                let support = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true).resolvingSymlinksInPath()
                let journal = support.appendingPathComponent("PlenactMigration", isDirectory: true)
                    .appendingPathComponent("source-identities-v1.json")
                let prepared = try MigrationPreview.prepare(backup: backup, journalURL: journal)
                document = try LegacyBackupDocument(files: prepared.files)
                preview = prepared
                message = "Migration preview prepared. Complete workspace conversion is still in progress."
            }
            catch MigrationIdentityJournal.Failure.unsupported
            {
                message = "The existing migration journal needs a newer app. It has been preserved."
            }
            catch MigrationBackupReader.Failure.pendingRecovery
            {
                message = "Finish recovering the pending review before converting this backup. Your backup is preserved."
            }
            catch
            {
                message = "The migration preview needs review. Your source backup and existing identity journal have been preserved."
            }
        }
    }


    /// @fcn LocalDataExportView.prepare
    /// @brief Render preparation state before freezing saved source content
    /// @details No live data is logged, uploaded or rewritten. Failed attempts discard stale exports.
    /// @return Void; publishes either a complete source backup or a bounded error
    private func prepare()
    {

        preparing = true
        backup = nil
        preview = nil
        document = nil
        message = nil
        Task { @MainActor in
            await Task.yield()
            defer { preparing = false }
            do
            {
                guard let domain = Bundle.main.bundleIdentifier else
                {
                    throw LegacyWorkspaceExport.Failure.missingDomain
                }
                let prepared = try LegacyWorkspaceExport.capture(defaults: .standard, domain: domain,
                    root: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
                document = try LegacyBackupDocument(files: prepared.files)
                backup = prepared
            }
            catch
            {
                message = (error as? LegacyWorkspaceExport.Failure)?.errorDescription
                    ?? "A complete backup could not be prepared. Your saved data is unchanged."
            }
        }
    }
}
