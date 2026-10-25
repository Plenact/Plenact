// --------------------------------------------------------------------------------------------------
// @file       PortableWorkspaceActivation.swift
// @brief      User-confirmed Simulator activation of a reconstructed editable portable workspace
// @details    Supported User Data Model versions: 1.0 base and working 1.1. Retains complete pre-import
//             recovery and canonical evidence. Cloud sync stays off; edited export has an explicit limited scope.
// --------------------------------------------------------------------------------------------------
import SwiftUI


/// Routes explicit import/undo requests through root navigation teardown.
/// @section Purpose
///     Prevent old editors from saving into the reconstructed workspace during activation.
struct PortableWorkspaceImportAccess
{

    let install: (ReviewedPortablePackage) -> Void
    let undo:    () -> Void
}


/// Optional root-owned import routing; absence disables activation controls.
/// @section Purpose
///     Keep views from installing native stores directly.
private struct PortableWorkspaceImportKey: EnvironmentKey
{

    static let defaultValue: PortableWorkspaceImportAccess? = nil
}


extension EnvironmentValues
{

    /// @fcn EnvironmentValues.portableWorkspaceImport
    /// @brief Access the root's explicit Simulator import boundary
    /// @return Optional import and undo actions
    var portableWorkspaceImport: PortableWorkspaceImportAccess?
    {

        get
        {
            self[PortableWorkspaceImportKey.self]
        }
        set
        {
            self[PortableWorkspaceImportKey.self] = newValue
        }
    }
}


extension AppRootView
{

    /// @fcn AppRootView.performPortableWorkspaceImport
    /// @brief Activate or undo portable data after old navigation/editor state has been removed
    /// @return Void after reload or protected recovery, without enabling synchronization
    @MainActor
    func performPortableWorkspaceImport()
    {

        defer
        {
            pendingPortableImport = nil
            undoingPortableImport = false
            isSwitchingWorkspace = false
        }
        do
        {
            #if targetEnvironment(simulator)
            KanbanBoardPersistence.waitForPendingSaves()
            let store = try FullMonthExampleStore.live()
            if undoingPortableImport
            {
                try store.undoPortableWorkspace()
                try reloadWorkspaceFromStorage()
                workspaceNotice = "Your workspace from before the editable portable import is restored."
            }
            else if let package = pendingPortableImport, let domain = Bundle.main.bundleIdentifier
            {
                let candidate = try PortableWorkspaceCandidate.prepare(package)
                let aliases = ["GMT": "Etc/UTC", "UTC": "Etc/UTC", "Etc/GMT": "Etc/UTC"]
                let deviceZone = aliases[TimeZone.current.identifier] ?? TimeZone.current.identifier
                let originalZone = aliases[candidate.timeZoneID] ?? candidate.timeZoneID
                guard originalZone == deviceZone else
                {
                    throw PortableEditableContent.Failure.dateContextRequired
                }
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                defer
                {
                    try? FileManager.default.removeItem(at: staging)
                }
                try candidate.stage(at: staging)
                try store.installPortableWorkspace
                {
                    try candidate.install(from: staging, root: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
                        defaults: .standard, domain: domain)
                    try reloadWorkspaceFromStorage()
                }
                workspaceNotice = "Portable data loaded into your editable Simulator workspace. The previous workspace is retained for undo. Cloud synchronization is off."
            }
            else
            {
                throw PortableEditableContent.Failure.invalid
            }
            #endif
        }
        catch
        {
            if (try? FullMonthExampleStore.live().needsRecovery) == true
            {
                workspaceRecoveryError = error.localizedDescription
            }
            else
            {
                try? reloadWorkspaceFromStorage()
            }
            workspaceNotice = "The editable portable switch did not finish. The original package is unchanged, and recovery files are retained when needed. " + error.localizedDescription
        }
    }
}
