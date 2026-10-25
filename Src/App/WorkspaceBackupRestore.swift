// --------------------------------------------------------------------------------------------------
// @file       WorkspaceBackupRestore.swift
// @brief      Root-owned Simulator source-recovery orchestration
// @details    Model 1.0 preparation only. Uses existing journal/reload boundaries after navigation
//             teardown; the user selects and confirms the backup before any destination changes.
// --------------------------------------------------------------------------------------------------
import Foundation
import SwiftUI


/// Coordinates source recovery after the old navigation tree has disappeared.
/// @section Purpose
///     Prevent editor autosaves from racing a confirmed test restore.
extension AppRootView
{

    /// @fcn AppRootView.performNativeSourceRestore
    /// @brief Install or undo a reviewed native backup, then reload all root workspace state
    /// @return Void with recovery or completion feedback
    @MainActor
    func performNativeSourceRestore()
    {

        defer
        {
            pendingNativeRestore = nil
            undoingNativeRestore = false
            isSwitchingWorkspace = false
        }
        var committed = false
        do
        {
            #if targetEnvironment(simulator)
            KanbanBoardPersistence.waitForPendingSaves()
            let store = try FullMonthExampleStore.live()
            if undoingNativeRestore
            {
                try store.undoNativeSource()
            }
            else if let backup = pendingNativeRestore, let domain = Bundle.main.bundleIdentifier
            {
                try store.installNativeSource
                {
                    try LocalBackupRestore.install(backup,
                        root: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true), defaults: .standard, domain: domain)
                }
            }
            else
            {
                throw LocalBackupRestore.Failure.invalid
            }
            committed = true
            try reloadWorkspaceFromStorage()
            workspaceNotice = undoingNativeRestore
                ? "The workspace from before the test restore is back."
                : "Local backup restored. Compare your Week and personal Lists. This was a source recovery test; cloud synchronization is still off."
            #endif
        }
        catch
        {
            if committed || (try? FullMonthExampleStore.live().needsRecovery) == true
            {
                workspaceRecoveryError = error.localizedDescription
            }
            workspaceNotice = "The test restore could not finish. Recovery data has been retained: " + error.localizedDescription
        }
    }
}
