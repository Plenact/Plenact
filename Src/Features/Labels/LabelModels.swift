// -------------------------------------------------------------------------------------------------
// @file       LabelModels.swift
// @brief      Shared label catalog models, persistence, palette, and chip presentation
// @details    Defines reusable categorized labels, stable card assignments, local catalog storage,
//             and the compact chip used in card views
//
// @notes      Card assignments store label IDs; the shared catalog owns label names, categories, and colors
//
// -------------------------------------------------------------------------------------------------
import Foundation
import SwiftUI


// -------------------------------------- MARK: - Label Color ---------------------------------- //

///
/// Defines the fixed palette of colors available to reusable kanban labels
///
/// @section    Purpose
///     Provide stable, serializable color choices for label definitions
///
/// @note       Raw values are persisted; color values are resolved into SwiftUI colors for
///             presentation
///
enum KanbanLabelColor: String, CaseIterable, Codable, Identifiable {
    case mint
    case yellow
    case orange
    case coral
    case pink
    case purple
    case blue
    case green
    case red
    case gray

    ///
    /// @fcn        KanbanLabelColor.id
    /// @brief      Expose the palette token as its stable identity
    /// @details    Uses the enum raw value so the same color remains identifiable after decoding
    ///
    /// @return     (String) serialized raw-value identifier
    ///
    var id: String { rawValue } /* Stable persisted color token */

    ///
    /// @fcn        KanbanLabelColor.title
    /// @brief      Return a display title for the palette color
    /// @details    Capitalizes the raw-value token for use in color selection controls
    ///
    /// @return     (String) user-facing color name
    ///
    var title: String { /* Display name for the color picker */
        rawValue.capitalized
    }

    ///
    /// @fcn        KanbanLabelColor.color
    /// @brief      Resolve the palette token to a SwiftUI color
    /// @details    Maps each persisted palette case to its fixed display color
    ///
    /// @return     (Color) presentation color associated with this palette case
    ///
    var color: Color { /* SwiftUI color resolved from the persisted token */
        switch self {
            case .mint:   Color(red: 0.17, green: 0.72, blue: 0.55)
            case .yellow: Color(red: 0.91, green: 0.79, blue: 0.13)
            case .orange: Color(red: 0.96, green: 0.55, blue: 0.10)
            case .coral:  Color(red: 0.91, green: 0.37, blue: 0.32)
            case .pink:   Color(red: 0.88, green: 0.38, blue: 0.66)
            case .purple: Color(red: 0.57, green: 0.32, blue: 0.76)
            case .blue:   Color(red: 0.20, green: 0.48, blue: 0.88)
            case .green:  Color(red: 0.20, green: 0.60, blue: 0.37)
            case .red:    Color(red: 0.78, green: 0.22, blue: 0.21)
            case .gray:   Color(red: 0.43, green: 0.46, blue: 0.50)
        }
    }
}


// -------------------------------------- MARK: - Label Category ------------------------------- //

///
/// Represents a named group in the reusable label library
///
/// @section    Purpose
///     Organize labels into browseable categories such as Work, Home, or Finance
///
/// @note       Labels refer to categories using the stable category ID
///
struct KanbanLabelCategory: Identifiable, Hashable, Codable {
    let id: String /* Stable category identity */
    var name: String /* User-facing category name */
}


// -------------------------------------- MARK: - Label Model ---------------------------------- //

///
/// Represents one reusable label in the shared catalog
///
/// @section    Purpose
///     Keep a label's stable identity, display name, category, and palette color in one definition
///
/// @note       Cards store the label ID rather than copying these presentation values
///
struct KanbanLabel: Identifiable, Hashable, Codable {
    let id: String /* Stable label identity */
    var name: String /* User-facing label name */
    var categoryID: String /* Stable owning-category identity */
    var color: KanbanLabelColor /* Persisted palette selection */
}


// -------------------------------------- MARK: - Label Library -------------------------------- //

///
/// Owns the reusable label definitions and their categories
///
/// @section    Purpose
///     Supply a shared catalog that cards can reference by stable label ID
///
/// @details    The starter catalog seeds common categories and labels when no saved catalog is
///             available
///
struct LabelLibrary: Hashable, Codable {

    var categories: [KanbanLabelCategory] /* Reusable label categories */
    var labels: [KanbanLabel] /* Reusable label definitions */

    /// Stable IDs used to assign representative starter labels to sample cards
    static let starterLabelIDs = [ /* Label IDs used by deterministic SampleData */
        "work-scheduled", "work-deliverable", "work-onsite",
        "home-dinner", "home-relatives", "home-church",
        "finance-budget", "finance-bills",
        "health-fitness", "health-wellness",
        "leisure-hobby", "leisure-travel",
        "casual-social"
    ]

    /// Initial categories and reusable labels available on a fresh installation
    static let starter = LabelLibrary( /* Initial categorized label catalog */
        categories: [
            KanbanLabelCategory(id: "work", name: "Work"),
            KanbanLabelCategory(id: "home", name: "Home"),
            KanbanLabelCategory(id: "finance", name: "Finance"),
            KanbanLabelCategory(id: "health", name: "Health & Fitness"),
            KanbanLabelCategory(id: "leisure", name: "Leisure"),
            KanbanLabelCategory(id: "casual", name: "Casual")
        ],
        labels: [
            KanbanLabel(id: "work-scheduled", name: "Scheduled", categoryID: "work", color: .blue),
            KanbanLabel(id: "work-deliverable", name: "Deliverable", categoryID: "work", color: .orange),
            KanbanLabel(id: "work-onsite", name: "Onsite", categoryID: "work", color: .purple),
            KanbanLabel(id: "home-dinner", name: "Dinner", categoryID: "home", color: .coral),
            KanbanLabel(id: "home-relatives", name: "Relatives", categoryID: "home", color: .pink),
            KanbanLabel(id: "home-church", name: "Church", categoryID: "home", color: .green),
            KanbanLabel(id: "finance-budget", name: "Budget", categoryID: "finance", color: .mint),
            KanbanLabel(id: "finance-bills", name: "Bills", categoryID: "finance", color: .red),
            KanbanLabel(id: "health-fitness", name: "Fitness", categoryID: "health", color: .green),
            KanbanLabel(id: "health-wellness", name: "Wellness", categoryID: "health", color: .mint),
            KanbanLabel(id: "leisure-hobby", name: "Hobby", categoryID: "leisure", color: .purple),
            KanbanLabel(id: "leisure-travel", name: "Travel", categoryID: "leisure", color: .blue),
            KanbanLabel(id: "casual-social", name: "Social", categoryID: "casual", color: .yellow)
        ]
    )
}


// -------------------------------------- MARK: - Label Persistence ---------------------------- //

///
/// Loads and saves the shared label library on the current installation
///
/// @section    Purpose
///     Preserve reusable category and label definitions between app launches
///
/// @note       This local store does not synchronize the catalog across devices or users
///
enum LabelLibraryStore {

    private static let storageKey = "Plenact.LabelLibrary.v1" /* Versioned local catalog key */

    ///
    /// @fcn        LabelLibraryStore.load
    /// @brief      Load the saved label catalog
    /// @details    Decodes the local JSON snapshot and returns the starter catalog when no valid
    ///             saved catalog exists
    ///
    /// @return     (LabelLibrary) restored catalog or starter catalog
    ///
    /// @pre        UserDefaults may contain data encoded by this library format
    /// @post       Stored data is unchanged; callers receive a usable label library
    ///
    static func load() -> LabelLibrary {
          guard let data = UserDefaults.standard.data(forKey: storageKey), /* Saved JSON catalog */
              let library = try? JSONDecoder().decode(LabelLibrary.self, from: data) else { /* Decoded catalog */
            return .starter
        }

        return library
    }

    ///
    /// @fcn        LabelLibraryStore.save(_:)
    /// @brief      Save the current label catalog
    /// @details    Encodes the catalog as JSON and stores it under the versioned local key
    ///
    /// @param[in]  library  Categories and labels to persist
    ///
    /// @return     (Void) saves the encoded catalog when encoding succeeds
    ///
    /// @pre        library contains the current in-memory label definitions
    /// @post       A valid encoded snapshot is stored locally; encoding failure leaves prior data
    ///             unchanged
    ///
    static func save(_ library: LabelLibrary) {
        guard let data = try? JSONEncoder().encode(library) else { return } /* Encoded catalog snapshot */
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}


// -------------------------------------- MARK: - Label Chip ----------------------------------- //

///
/// Displays one compact colored label chip
///
/// @section    Purpose
///     Present a label name with its palette color in card summaries and details
///
struct KanbanLabelChip: View {

    let label: KanbanLabel /* Label displayed by the chip */

    ///
    /// @fcn        KanbanLabelChip.body
    /// @brief      Build the label chip presentation
    /// @details    Styles the label name with its color and a lightly tinted background
    ///
    /// @return     (some View) compact visual representation of the supplied label
    ///
    var body: some View { /* Colored reusable-label chip */
        Text(label.name)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(label.color.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(label.color.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
