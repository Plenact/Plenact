// --------------------------------------------------------------------------------------------------
// @file       StudioModels.swift
// @brief      Reusable personalization surfaces, saved looks, and workspace defaults
// @details    Stores additive appearance metadata without changing Card content or attachment ownership.
//             Imported artwork lives independently; online photography retains its provider attribution.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Describes a reusable surface material.
/// @section Purpose
///     Provides the same selection vocabulary for Cards, Notes, Lists, Boards, and workspace views.
enum StudioMaterial: String, Codable, CaseIterable, Identifiable, Sendable
{


    case plain, color, gradient, paper, linen, dots, grid, canvas, photo, unsplash
    var id: String
    {
        rawValue
    }

    var title: String
    {
        rawValue.capitalized
    }

}



/// Retains approved online image URLs and visible photographer attribution.
/// @section Purpose
///     Keeps external photographs separate from offline user imports and preserves required credits.
struct StudioRemotePhoto: Codable, Hashable, Sendable
{


    let id:           String
    let imageURL:     URL
    let photographer: String
    let profileURL:   URL
    let downloadURL:  URL
}



/// Stores one portable surface description, with optional references to locally owned artwork.
/// @section Purpose
///     Allows each use of an artwork to retain independent strength, readability, and framing.
struct StudioSurface: Codable, Hashable, Sendable
{


    var material:         StudioMaterial = .paper
    var color:            String = "EDE3CA"
    var secondaryColor:   String = "C4DADB"
    var strength:         Double = 0.65
    var readability:      Double = 0.55
    var verticalPosition: Double = 0.5
    var zoom:             Double = 1
    var showsInPreviews:  Bool = true
    var photoFileName:    String? = nil
    var remotePhoto:      StudioRemotePhoto? = nil
}



/// Names a reusable look including optional header and subtitle styling.
/// @section Purpose
///     Stores references rather than duplicated image bytes, so removing an individual use leaves art intact.
struct StudioArtwork: Codable, Identifiable, Hashable, Sendable
{


    var id = UUID()
    var name:           String
    var surface:        StudioSurface
    var header:         ItemAccent? = nil
    var italicSubtitle: Bool? = nil
    var titleColor:     ListPreviewTextColor? = nil
    var textColor:      ListPreviewTextColor? = nil
}



/// Enumerates workspace wallpaper destinations.
/// @section Purpose
///     Keeps per-view defaults distinct from Board and List overrides.
enum StudioDestination: String, Codable, CaseIterable, Identifiable
{


    case today = "Today", week = "Week", plans = "Plans", activity = "Activity"
    case calendar = "Calendar", search = "Search", settings = "Settings"
    var id: String
    {
        rawValue
    }

}



/// Retains device-local workspace choices without changing existing content by default.
/// @section Purpose
///     Provides new-item defaults and per-view wallpapers while leaving unset destinations unchanged.
struct StudioSettings: Codable, Equatable
{


    static let key = "Plenact.Studio.Settings.v1"
    static let libraryKey = "Plenact.Studio.Artwork.v1"
    var views:              [String: StudioSurface] = [:]
    var defaultCardSurface: StudioSurface? = nil
    var defaultNoteSurface: StudioSurface? = nil
    var variesNewSurfaces = false
    var variesNewHeaders = false
    var palette: [String] = ["EDE3CA", "DDE8D8", "DCE7EE", "E9DDEB", "F0DDD3"]


    /// @fcn StudioSettings.load(from:)
    /// @brief Load workspace personalization without writing defaults
    /// @details Returns the established appearance when no valid settings have been saved.
    /// @param[in] defaults Preferences domain to inspect
    /// @return (StudioSettings) retained choices or an unchanged default configuration
    static func load(from defaults: UserDefaults = .standard) -> StudioSettings
    {


        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else
        {

            return Self()
        }

        return value
    }



    /// @fcn StudioSettings.apply(to:settings:)
    /// @brief Apply creation defaults once without repainting existing records
    /// @details Honors explicit item surfaces and stores random palette choices in the newly created item.
    /// @param[in,out] card New item receiving appearance defaults
    /// @param[in] settings Optional injected configuration for deterministic callers
    /// @return (Void) updates only an eligible new Card or Note
    static func apply(to card: inout KanbanCard, settings: StudioSettings = .load())
    {


        guard !card.isSectionDivider else
        {
            return
        }

        var surface = card.appearance?.studioSurface ?? (card.presentation == .note ? settings.defaultNoteSurface : settings.defaultCardSurface)
        if settings.variesNewSurfaces, card.appearance?.studioSurface == nil, let color = settings.palette.randomElement()
        {

            if surface == nil
            {
                surface = StudioSurface(material: .color)
            }

            surface?.color = color
        }

        var appearance = card.appearance ?? ItemAppearance()
        if settings.variesNewHeaders, appearance.background == nil
        {

            appearance.background = ItemAccent.allCases.randomElement()
        }

        if let surface
        {
            appearance.studioSurface = surface
        }

        card.appearance = appearance.isEmpty ? nil : appearance
    }

}

