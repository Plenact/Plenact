// --------------------------------------------------------------------------------------------------
// @file       LocalDataExportView.swift
// @brief      Private local backup preparation and explicit Files export
// @details    Supports User Data Model 1.0 base and working 1.1; native backup formats 1/2.
//             Preserves originals beside explicit partial conversion and Simulator-only source recovery.
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
    @Environment(\.portableWorkspaceImport) private var editableImportAccess
    @State private var originalTimeZoneID = "" /* Explicit original context; never default to this device’s clock */
    @State private var packageDocument: LegacyBackupDocument?
    @State private var savingPackage = false
    @State private var choosingPortablePackage = false
    @State private var portableReview: ReviewedPortablePackage?
    @State private var installedPortable: ReviewedPortablePackage?
    @State private var canUndoPortable = false
    @State private var confirmsPortableInstall = false
    @State private var confirmsEditableImport = false
    @State private var confirmsEditableUndo = false
    @State private var editedDocument: LegacyBackupDocument?
    @State private var savingEdited = false
    @State private var editedExportError: String?
    @State private var showsEditedExportError = false
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
                    Picker("Original date/time zone", selection: $originalTimeZoneID)
                    {
                        Text("Choose timezone…").tag("")
                        Text("Central — America/Chicago").tag("America/Chicago")
                        Text("UTC").tag("Etc/UTC")
                    }
                    Text("Confirm where the saved dates/times were entered. This first converter supports Central and UTC, 1900–2100.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Prepare migration preview", action: preparePreview)
                        .disabled(preparing || backup.files.fileWrappers?["PortableRuntime"] != nil)
                    if backup.files.fileWrappers?["PortableRuntime"] != nil
                    {
                        Text("This backup preserves all current edits and portable import evidence. Use Export supported Card edits in the Editable Simulator workspace section for a portable test package.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let preview
                    {
                        LabeledContent("Converted preview records", value: String(preview.recordCount))
                        LabeledContent("Converted content records", value: String(preview.contentRecordCount))
                        LabeledContent("Calendar and template records", value: String(preview.metadataRecordCount))
                        LabeledContent("Plans and reviews converted", value: String(preview.planningRecordCount))
                        if preview.planningReviewCount > 0
                        {
                            LabeledContent("Planning review items", value: String(preview.planningReviewCount))
                            Text("Some saved planning data or historical references need review. The original writing and source data are preserved.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Studio and Week looks prepared", value: String(preview.studioPreparedCount))
                        LabeledContent("Model 1.1 appearance records", value: String(preview.appearanceModelRecordCount))
                        LabeledContent("Saved artwork converted", value: String(preview.artworkCount))
                        if preview.appearanceReviewCount > 0
                        {
                            LabeledContent("Appearance review items", value: String(preview.appearanceReviewCount))
                            Text("Some appearance details need review or a final data-model mapping. The originals and details remain in the exported preview.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Settings source", value: preview.settingsSourceLabel)
                        LabeledContent("Settings and profile prepared", value: String(preview.settingsPreparedCount))
                        LabeledContent("Today shortcuts converted", value: String(preview.shortcutItemCount))
                        if preview.settingsReviewCount > 0
                        {
                            LabeledContent("Settings review items", value: String(preview.settingsReviewCount))
                            Text("Some saved settings or shortcut references need review. The originals and details are preserved in the report.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Verified original files", value: String(preview.verifiedAssetCount))
                        LabeledContent("Missing original files", value: String(preview.missingAssetCount))
                        if preview.assetIssueCount > 0
                        {
                            LabeledContent("File review items", value: String(preview.assetIssueCount))
                        }
                        Text("Original files are linked and checked in this backup. Asset ownership and cloud transfer are still pending.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        LabeledContent("Personal selections prepared", value: String(preview.selectionEntryCount))
                        if preview.selectionIssueCount > 0
                        {
                            LabeledContent("Selection review items", value: String(preview.selectionIssueCount))
                        }
                        Text("Bookmarks and importance are prepared separately. Linking them to your verified account is still pending.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let guidance = preview.contentReviewMessage
                        {
                            Text(guidance)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("The preview includes converted records, stable identities and a report of remaining work. Complete workspace conversion and cloud account linking are still pending.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    #if targetEnvironment(simulator)
                    if preview != nil
                    {
                        Button("Prepare portable test package", action: prepareTestPackage)
                            .disabled(preparing)
                        Text("Uses a synthetic test owner. Your original backup stays included. Independent export review is required before portable import; cloud synchronization stays off.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if packageDocument != nil
                        {
                            Button("Save portable test package to Files…")
                            {
                                savingPackage = true
                            }
                            .disabled(preparing)
                        }
                    }
                    #endif
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
            Section("Portable package review")
            {
                Button("Choose portable test package…")
                {
                    choosingPortablePackage = true
                }
                .disabled(preparing)
                if let portableReview
                {
                    LabeledContent("Portable records reviewed", value: String(portableReview.recordCount))
                    LabeledContent("Cards", value: String(portableReview.cardCount))
                    LabeledContent("Lists", value: String(portableReview.listCount))
                    LabeledContent("Verified original files", value: String(portableReview.mediaCount))
                    Button("Install isolated portable test copy…")
                    {
                        confirmsPortableInstall = true
                    }
                    .disabled(preparing)
                }
                Text("Reviews portable records and original files without using the source backup. Installation requires the separate confirmation below and creates only an isolated test copy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Isolated portable test workspace")
            {
                if let installedPortable
                {
                    LabeledContent("Installed Cards", value: String(installedPortable.cardCount))
                    LabeledContent("Installed original files", value: String(installedPortable.mediaCount))
                    NavigationLink("Inspect installed test workspace")
                    {
                        PortableWorkspaceInspector(package: installedPortable)
                    }
                }
                else
                {
                    Text("No portable test copy is currently installed.")
                }
                if canUndoPortable
                {
                    Button("Undo last portable test installation")
                    {
                        do
                        {
                            let store = try PortableTestWorkspace.live()
                            installedPortable = try store.undo()
                            canUndoPortable = try store.canUndo()
                            message = "Previous isolated test state restored. Your main workspace is unchanged."
                        }
                        catch
                        {
                            message = "The previous portable test state could not be verified. Nothing was changed."
                        }
                    }
                }
                Text("This test copy is separate from your main workspace. It retains the complete portable snapshot and original files; inspection is read-only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Editable Simulator workspace")
            {
                if portableReview != nil
                {
                    Button("Import into editable Simulator workspace…")
                    {
                        confirmsEditableImport = true
                    }
                    .disabled(preparing || editableImportAccess == nil || (try? FullMonthExampleStore.live().hasPortableImportBackup) == true)
                }
                else
                {
                    Text("Choose a portable test package above to prepare an editable import.")
                }
                if (try? FullMonthExampleStore.live().hasPortableImportBackup) == true
                {
                    Button("Export supported Card edits to Files…")
                    {
                        prepareEditedExport()
                    }
                    .disabled(preparing)
                    Button("Undo editable workspace import…")
                    {
                        confirmsEditableUndo = true
                    }
                    .disabled(preparing || editableImportAccess == nil)
                }
                Text("Replaces this Simulator’s main workspace after retaining its full previous state for undo. Uses the package’s test owner; cloud synchronization stays off. Edited export supports new Cards and Lists created in Board views, same-Board moves and reordering, plus existing Card content, checklists, comments, photos, completion, scheduling, deletion and history. Other changes stop export; local backups preserve all changes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
        .fileImporter(isPresented: $choosingPortablePackage, allowedContentTypes: [.folder])
        { result in
            portableReview = nil
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
                portableReview = try PortablePackageReview.review(at: url)
                message = "Portable package integrity and core references reviewed. No data was imported."
            }
            catch
            {
                if (error as NSError).code != NSUserCancelledError
                {
                    message = (error as? PortablePackageReview.Failure)?.errorDescription
                        ?? "The portable package could not be reviewed. No data was imported."
                }
            }
        }
        .onAppear
        {
            do
            {
                let store = try PortableTestWorkspace.live()
                installedPortable = try store.active()
                canUndoPortable = try store.canUndo()
            }
            catch
            {
                message = "The retained portable test copy needs review. Your main workspace is unchanged."
            }
        }
        .confirmationDialog("Install an isolated portable test copy?", isPresented: $confirmsPortableInstall, titleVisibility: .visible)
        {
            Button("Install isolated test copy")
            {
                do
                {
                    guard let portableReview else
                    {
                        return
                    }
                    let store = try PortableTestWorkspace.live()
                    installedPortable = try store.install(portableReview)
                    canUndoPortable = try store.canUndo()
                    message = "Portable test copy installed and read back from disk. Your main workspace is unchanged."
                }
                catch
                {
                    message = "The isolated test copy could not be installed. The previous test state and main workspace are preserved."
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        message:
        {
            Text("Retains the previous isolated test state for undo. Your main workspace, settings and original backup are not replaced. This does not enable cloud synchronization.")
        }
        .confirmationDialog("Replace this Simulator workspace?", isPresented: $confirmsEditableImport, titleVisibility: .visible)
        {
            Button("Back up and import editable workspace", role: .destructive)
            {
                if let portableReview
                {
                    editableImportAccess?.install(portableReview)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        message:
        {
            Text("Your full current workspace will be retained for undo. The portable records will open in the normal editing views. Keep the original package. Portable export supports Card text, completion, scheduling, deletion and history; other changes currently require a local backup.")
        }
        .confirmationDialog("Restore the workspace from before portable import?", isPresented: $confirmsEditableUndo, titleVisibility: .visible)
        {
            Button("Undo editable workspace import", role: .destructive)
            {
                editableImportAccess?.undo()
            }
            Button("Cancel", role: .cancel) {}
        }
        message:
        {
            Text("Restores the full retained pre-import workspace. The imported workspace and its changes are also retained in local recovery history before the previous workspace is restored.")
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
        .onChange(of: originalTimeZoneID)
        {
            preview = nil
            packageDocument = nil
            if let backup
            {
                document = try? LegacyBackupDocument(files: backup.files)
            }
        }
        .fileExporter(isPresented: $savingPackage, document: packageDocument,
            contentType: .folder, defaultFilename: "Plenact Portable Test")
        { result in
            switch result
            {
            case .success:
                message = "Portable test package saved with its original backup. Independent review and portable recovery testing are still required."
            case .failure:
                message = "The test package was not saved. You can choose a destination and try again."
            }
        }
        .fileExporter(isPresented: $savingEdited, document: editedDocument,
            contentType: .folder, defaultFilename: "Plenact Edited Portable Test")
        { result in
            switch result
            {
            case .success:
                message = "Edited portable test package saved with its exact native backup. Your workspace and Undo are unchanged."
            case .failure:
                message = "The edited package was not saved. You can try again."
            }
            editedDocument = nil
        }
        .alert("Edited export could not be prepared", isPresented: $showsEditedExportError)
        {
            Button("OK", role: .cancel) {}
        }
        message:
        {
            Text(editedExportError ?? "Your workspace is unchanged. Please try again.")
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


    /// @fcn LocalDataExportView.prepareEditedExport
    /// @brief Freeze saved native changes and prepare an identity-preserving portable test export
    /// @return Void after presenting Files or an actionable unsupported-edit message
    private func prepareEditedExport()
    {

        preparing = true
        editedDocument = nil
        message = nil
        Task { @MainActor in
            defer
            {
                preparing = false
            }
            do
            {
                KanbanBoardPersistence.waitForPendingSaves()
                guard let domain = Bundle.main.bundleIdentifier else
                {
                    throw LegacyWorkspaceExport.Failure.missingDomain
                }
                let backup = try LegacyWorkspaceExport.capture(defaults: .standard, domain: domain,
                    root: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
                editedDocument = try LegacyBackupDocument(files: PortableEditedExport.prepare(backup))
                savingEdited = true
            }
            catch
            {
                editedExportError = error.localizedDescription
                message = editedExportError
                showsEditedExportError = true
            }
        }
    }


    /// @fcn LocalDataExportView.prepareTestPackage
    /// @brief Assemble an explicitly synthetic package from the current frozen migration preview
    /// @details Saves no workspace changes; source coverage and review gates must pass first.
    /// @return Void after publishing a Files-export document or a bounded review message
    private func prepareTestPackage()
    {

        guard let preview else
        {
            return
        }
        packageDocument = nil
        preparing = true
        message = nil
        Task { @MainActor in
            await Task.yield()
            defer
            {
                preparing = false
            }
            do
            {
                let files = try MigrationTestPackage.prepare(preview)
                packageDocument = try LegacyBackupDocument(files: files)
                message = "Portable test package prepared. Save it to Files for independent review. No data was installed or uploaded."
            }
            catch
            {
                message = "The portable test package needs review. Save the backup and preview so the remaining items can be checked. Your original data is unchanged."
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
        packageDocument = nil
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
                let prepared = try MigrationPreview.prepare(backup: backup, journalURL: journal,
                    timeZoneID: originalTimeZoneID.isEmpty ? nil : originalTimeZoneID)
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
        packageDocument = nil
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
