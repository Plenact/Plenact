// --------------------------------------------------------------------------------------------------
// @file       MigrationContentAppearance.swift
// @brief      Explicit complete-value appearance mapping with inherited nulls preserved
// @details    Supported User Data Model versions: 1.0. Partial, local-only migration preview.
//             Original source bytes remain preserved; no cloud ownership or synchronization is implied.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Maps portable appearance while keeping unsupported original files as explicit pending targets.
/// @section Purpose
///     Preserve authored overrides rather than exporting a flattened resolved style.
extension MigrationContentValues
{

    static let appearanceFields: [String: [String: String]] = [
        "item_appearance": ["accent": "accent", "icon": "icon", "background": "background", "listBackground": "list_background", "cardBackground": "card_background", "cardTitleColor": "card_title_color", "cardTextColor": "card_text_color", "addItemTextColor": "add_item_text_color", "sectionCollapsed": "section_collapsed", "hideEmptySubtitle": "hide_empty_subtitle", "studioSurface": "studio_surface", "studioCardSurface": "studio_card_surface", "subtitleItalic": "subtitle_italic", "cardDetail": "card_detail", "listViewMode": "list_view_mode", "iconColor": "icon_color", "showsIconInHeader": "shows_icon_in_header", "listBackgroundOpacity": "list_background_opacity"],
        "board_appearance": ["bannerBackground": "banner_background", "listBackground": "list_background", "cardBackground": "card_background", "cardDetail": "card_detail", "collectionBackground": "collection_background", "cardTitleColor": "card_title_color", "cardTextColor": "card_text_color", "addItemTextColor": "add_item_text_color", "studioSurface": "studio_surface", "studioCardSurface": "studio_card_surface", "subtitleItalic": "subtitle_italic"],
        "surface": ["material": "material", "color": "color", "secondaryColor": "secondary_color", "strength": "strength", "readability": "readability", "verticalPosition": "vertical_position", "zoom": "zoom", "showsInPreviews": "shows_in_previews", "photoFileName": "photo_asset_id", "remotePhoto": "remote_photo"],
        "color": ["red": "red", "green": "green", "blue": "blue", "legacyToken": "legacy_token"],
        "collection_background": ["preset": "preset", "photoFileName": "photo_asset_id"],
        "remote_photo": ["id": "id", "imageURL": "image_url", "photographer": "photographer", "profileURL": "profile_url", "downloadURL": "download_url"]
    ]


    /// @fcn MigrationContentValues.appearance
    /// @brief Map every supported saved appearance field and reject out-of-range values
    /// @param[in] value Optional natively decoded object
    /// @param[in] kind Explicit portable value kind
    /// @return Complete portable object or explicit null
    /// @throws Unsupported tokens, unsafe files or invalid bounds
    func appearance(_ value: Any?, kind: String) throws -> Any
    {

        guard let value, !(value is NSNull) else
        {
            return NSNull()
        }
        if kind == "color", let token = value as? String
        {
            let data = try JSONSerialization.data(withJSONObject: token, options: .fragmentsAllowed)
            let color = try JSONDecoder().decode(ProfileColor.self, from: data)
            return ["red": color.red, "green": color.green, "blue": color.blue, "legacy_token": token]
        }
        guard let source = value as? [String: Any], let mapping = Self.appearanceFields[kind] else
        {
            throw Failure.invalid("appearance")
        }
        var output: [String: Any] = [:]
        for (key, wire) in mapping
        {
            var item: Any = source[key] ?? NSNull()
            switch key
            {
            case "collectionBackground": item = try appearance(source[key], kind: "collection_background")
            case "studioSurface", "studioCardSurface": item = try appearance(source[key], kind: "surface")
            case "addItemTextColor", "iconColor": item = try appearance(source[key], kind: "color")
            case "remotePhoto": item = try appearance(source[key], kind: "remote_photo")
            case "imageURL", "profileURL", "downloadURL": item = try source[key].map(Self.webURL) as Any? ?? NSNull()
            case "photoFileName": item = try asset(source[key], area: kind == "collection_background"
                ? "Library/Application Support/PlenactCollectionBackgrounds" : "Library/Application Support/PlenactStudioArtwork")
            case "preset":
                if let token = item as? String
                {
                    item = ["forestPath": "forest_path", "sunlitWall": "sunlit_wall"][token] ?? token
                }
            case "listViewMode":
                if item as? String == "noteList"
                {
                    item = "note_list"
                }
            default: break
            }
            if ["red", "green", "blue", "strength", "readability", "verticalPosition", "listBackgroundOpacity"].contains(key), let number = item as? NSNumber,
               !number.doubleValue.isFinite || !(0...1).contains(number.doubleValue)
            {
                throw Failure.invalid("appearance_range")
            }
            if key == "zoom", let number = item as? NSNumber, !(1...2).contains(number.doubleValue)
            {
                throw Failure.invalid("appearance_zoom")
            }
            output[wire] = item
        }
        if kind == "remote_photo"
        {
            output["provider"] = "unsplash"
        }
        return output
    }
}
