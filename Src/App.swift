// --------------------------------------------------------------------------------------------------
// @file       App.swift
// @brief      Application entry point and scene recovery
// @details    Installs the shared app scene and starts the workspace through the existing
//             restoration boundary.
//
// @author     Justin Reina, Firmware/Systems Engineering
// @created    9/24/26
// @last rev   10/23/26
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


// -------------------------------------- MARK: - Entry Point ----------------------------------- //


///
/// Application entry point for the Plenact Application
///
/// @section    Purpose
///     Create the app scene and install the primary navigation shell
///
@main
struct Plenact: App
{


    @State private var recoveryError: String?


    ///
    /// @fcn        Plenact.init
    /// @brief      Install notification handling and recover interrupted storage work
    /// @details    Attempts review-journal and dataset-switch recovery at launch, retaining an error for the recovery
    ///             interface if either operation fails.
    ///
    /// @return     (Plenact) initialized instance
    ///
    init()
    {

        ReviewRhythmNotifications.shared.install()
        do
        {

            try DailyReviewTransaction.recover()
            try FullMonthExampleStore.live().recoverInterruptedSwitch()
            _recoveryError = State(initialValue: nil)
        }
        catch
        {

            _recoveryError = State(initialValue: error.localizedDescription)
        }

    }


    ///
    /// @fcn        Plenact.body
    /// @brief      Build the application's initial scene
    /// @details    Provides the root window and installs AppRootView as the Today-first surface
    ///
    /// @return     (some Scene) configured application scene
    ///
    /// @post       Each window installs its own AppRootView navigation shell
    ///
    var body: some Scene
    {  /* Root window scene */


        WindowGroup
        {

            if let recoveryError
            {

                VStack(spacing: 20)
                {

                    Text("Your saved data needs recovery").font(.headline)
                    Text(recoveryError).foregroundStyle(.secondary)
                    Button("Retry recovery")
                    {

                        do
                        {

                            try DailyReviewTransaction.recover();

                            try FullMonthExampleStore.live().recoverInterruptedSwitch();
                            self.recoveryError = nil
                        }
                        catch
                        {
                            self.recoveryError = error.localizedDescription
                        }

                    }

                } .padding()
            }
            else
            {

                AppRootView()
            }

        }

    }

}


///
/// Provides display names for the personal-collection icon choices
///
/// @section    Purpose
///     Keep picker labels alongside the collection icon type
///
extension PersonalCollectionIcon
{


    ///
    /// @fcn        PersonalCollectionIcon.title
    /// @brief      Translate a collection icon into its display name
    /// @details    Maps each icon case to a readable name for the settings picker
    ///
    /// @return     (String) icon display title
    /// @post       No collection state is changed
    ///
    var title: String
    {  /* User-facing name of the collection icon */

        switch self
        {


        case .notes:
                    "Notes"
        case .tasks:
                    "Tasks"
        case .shopping:
                    "Shopping"
        case .reminders:
                    "Reminders"
        case .project:
                    "Project"
        case .home:
                    "Home"
        case .heart:
                    "Heart"
        case .upcoming:
                    "Upcoming"
        }

    }

}
