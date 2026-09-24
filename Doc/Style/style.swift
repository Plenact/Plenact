import Foundation

// --------------------------------------------------------------------------------------------------
// @file       style.swift
// @brief      Swift style template with disciplined, human-readable engineering headers
// @details    This file combines modern Swift conventions with a function/header style that matches
//             the established embedded/system templates used elsewhere in the repository
//
// @author     Justin Reina, Firmware/Systems Engineering
// @created    9/24/26
// @last rev   9/24/26
//
// @notes     This template favors readability, maintainability, and debug support over compactness
//            The result is intentionally practical for human review and long-term support
//
// @section    Opens
//      none current
//
// @section    Legal Disclaimer
//      Company confidential and for template/reference use only
//
// --------------------------------------------------------------------------------------------------


// -------------------------------------- MARK: - Metadata ------------------------------------- //

///
/// Application metadata used for project ownership and traceability
///
/// This template preserves the disciplined engineering structure of the existing
/// repository while aligning with modern Swift conventions used in Apple ecosystem apps
///
/// @section    Purpose
///     Centralize project metadata in a single declaration block
///
/// @note   Keep this short and consistent across files for easy scanning and support
///
enum AppMetadata {

    static let projectName  = "ProjectName" 
    static let organization = "Company Name"
    static let author       = "Justin Reina"
    static let created      = "2026-09-24"
    static let lastRevision = "2026-09-24"
}


// -------------------------------------- MARK: - Errors ---------------------------------------- //

///
/// Centralized domain errors for app-level operations
///
/// @section    Purpose
///     Standardize error semantics for logging, UI feedback, and diagnostics
///
/// @note   Keep the error set small and explicit to preserve clarity and supportability
///
enum AppError: LocalizedError, Sendable {
    
    case missingConfiguration           /* Missing required configuration          */
    case invalidInput(String)           /* Invalid input with associated message   */
    case networkFailure(String)         /* Network failure with associated message */
    case unknown                        /* Unknown error                           */

    ///
    /// @fcn        AppError.errorDescription
    /// @brief      Exposes a human-readable message for the error case
    /// @details    Used for UI display and logging. The property remains lightweight and explicit
    ///
    /// @return     (String?) localised error description
    ///
    /// @pre        self must be a valid enum case
    /// @post       None
    ///
    /// @note   Keep output concise and actionable for support/debug workflows
    ///
    var errorDescription: String? {

        switch self {
            case .missingConfiguration:
                return "Missing required configuration."

            case .invalidInput(let message):
                return "Invalid input: \(message)"

            case .networkFailure(let message):
                return "Network request failed: \(message)"

            case .unknown:
                return "An unknown error has occurred."
        }
    }
}


// -------------------------------------- MARK: - Models ---------------------------------------- //

///
/// Simple, value-based model used throughout the app
///
/// @section    Purpose
///     Demonstrate a value-centric model with explicit and inspectable fields
///
/// @note   This is intentionally clear and support-oriented rather than over-simplified
///
struct Item: Identifiable, Codable, Sendable {

    let id:        UUID             /* Unique identifier for the item      */
    let title:     String           /* Display title                       */
    let detail:    String?          /* Optional secondary content          */
    let createdAt: Date             /* Timestamp for creation or retrieval */


    ///
    /// @fcn        Item.init
    /// @brief      Initialize a model with defaults and explicit values
    /// @details    Default values keep the data structure practical while preserving readability
    ///
    /// @param[in]  id          Unique identifier for the item
    /// @param[in]  title       Display title
    /// @param[in]  detail      Optional secondary content
    /// @param[in]  createdAt   Timestamp for creation or retrieval
    ///
    /// @return     (Item) configured instance
    ///
    init(id: UUID = UUID(), title: String, detail: String? = nil, createdAt: Date = Date()) {

        self.id        = id             /* Assign the unique identifier for the item      */
        self.title     = title          /* Assign the display title                       */
        self.detail    = detail         /* Assign the optional secondary content          */
        self.createdAt = createdAt      /* Assign the timestamp for creation or retrieval */

    }
}


// -------------------------------------- MARK: - Protocols ------------------------------------- //

///
/// Abstract boundary for data retrieval
///
/// @section    Purpose
///     Permit dependency injection and keep data access abstract from the UI layer
///
protocol ItemServiceProtocol: Sendable {

    ///
    /// @fcn        ItemServiceProtocol.fetchItems
    /// @brief      Retrieve a collection of domain items
    /// @details    Async contract keeps the UI layer decoupled from implementation details
    ///
    /// @return     ([Item]) list of retrieved items
    ///
    /// @throws     AppError or lower-level service errors when retrieval fails
    ///
    func fetchItems() async throws -> [Item]
}


// -------------------------------------- MARK: - Services -------------------------------------- //

///
/// Concrete implementation of the data-access layer
///
/// @section    Purpose
///     Provide the concrete dependency behind the abstract repository/service contract
///
final class ItemService: ItemServiceProtocol {

    ///
    /// @fcn        ItemService.fetchItems
    /// @brief      Return example data for the template
    /// @details    This sample intentionally keeps the implementation simple and easy to trace
    ///
    /// @return     ([Item]) current item collection
    ///
    /// @throws     None in the sample implementation, but future versions may throw errors
    ///
    func fetchItems() async throws -> [Item] {

        let now = Date()              /* Capture the current timestamp for item creation */ 

        return [
            Item(title: "Example Item", detail: "Sample content", createdAt: now),
            Item(title: "Second Item",  detail: "Another sample", createdAt: now.addingTimeInterval(60))
        ]
    }
}


// -------------------------------------- MARK: - View Model ----------------------------------- //

///
/// Presentation state for a screen or feature
///
/// @section    Purpose
///     Separate view state and business interaction from the UI rendering layer
///
@MainActor
final class ItemListViewModel: ObservableObject {

    @Published private(set) var items: [Item] = []          /* Current collection of items   */
    @Published private(set) var isLoading     = false       /* Loading state indicator       */

    @Published private(set) var errorMessage: String?       /* Current error message, if any */

    private let service: any ItemServiceProtocol            /* Concrete service dependency for data access */

    ///
    /// @fcn        ItemListViewModel.init
    /// @brief      Create the view model with a concrete service dependency
    /// @details    Default injection keeps the model easy to test and replace
    ///
    /// @param[in]  service     concrete service implementation
    ///
    /// @return     (ItemListViewModel) configured instance
    ///
    init(service: any ItemServiceProtocol = ItemService()) {

        self.service = service      /* Assign the injected service to the local property */
    }


    ///
    /// @fcn        ItemListViewModel.loadItems
    /// @brief      Load the latest data and update state
    /// @details    This method drives UI state transitions and captures service failures
    ///
    /// @return     (Void) state is updated in-place
    ///
    /// @pre        service must be valid and initialized
    /// @post       items and errorMessage reflect current load result
    ///
    func loadItems() async {

        isLoading    = true         /* Indicate that a loading operation is in progress */
        errorMessage = nil          /* Clear any existing error message                 */


        do {

            //Fetch attempt
            items = try await service.fetchItems()
        
        } catch let error as AppError {

            //Handle known application errors
            errorMessage = error.localizedDescription
        
        } catch {

            //Handle unexpected errors
            errorMessage = error.localizedDescription
        }

        //Update state
        isLoading = false
    }
}


// -------------------------------------- MARK: - Utility -------------------------------------- //

///
/// Example helper to format a date as a string
///
/// @section    Purpose
///     Provide a simple formatting utility for traceable example output
///
func formatDate(_ date: Date, style: DateFormatter.Style = .medium) -> String {
    
    let formatter = DateFormatter()     /* Initialize a new date formatter instance */

    
    formatter.dateStyle = style         /* Set the desired date style */
    formatter.timeStyle = .short        /* Set the desired time style */  

    return formatter.string(from: date)
}


// -------------------------------------- MARK: - Entry Point ---------------------------------- //

///
/// Example app entry used when integrated into a larger app target
///
/// In a real app, this method would be called from the application entry or a scene setup
///
/// @section    Purpose
///     Demonstrate a lightweight app entry pattern for the template
///
enum AppEntry {

    ///
    /// @fcn        AppEntry.run
    /// @brief      Launch the sample flow for the template
    /// @details    This method is intentionally small and easy to follow during debugging
    ///
    /// @return     (Void) writes example output to the console
    ///
    static func run() async {

        let viewModel = await ItemListViewModel(service: ItemService())

        // Load items from the service
        await viewModel.loadItems()

        // Retrieve the loaded items from the view model
        let items = await viewModel.items

        // Iterate over the retrieved items and print their details
        for item in items {

            print("\(item.title) - \(formatDate(item.createdAt))")
        }

        // Check for any error messages and print them if present
        if let errorMessage = await viewModel.errorMessage {

            print("Error: \(errorMessage)")
        }
    }
}


