// -------------------------------------------------------------------------------------------------
// @file       App.swift
// @brief      Application entry point for the Plenact App kanban board
// @details    Creates the window hierarchy and installs the board as the root view
//
// @author     Justin Reina, Firmware/Systems Engineering
// @created    9/24/26
// @last rev   9/26/26
//
// -------------------------------------------------------------------------------------------------
import SwiftUI


// -------------------------------------- MARK: - Entry Point ----------------------------------- //

///
/// Application entry point for the Plenact Application
///
/// @section    Purpose
///     Create the app scene and install the board as the initial root view
///
@main
struct Plenact: App {

    ///
    /// @brief      Build the application's initial scene
    /// @details    Provides the root window and installs ContentView as the initial board surface
    ///
    /// @return     (some Scene) configured application scene
    ///
    var body: some Scene {

        WindowGroup {
            ContentView()
        }
    }
}
