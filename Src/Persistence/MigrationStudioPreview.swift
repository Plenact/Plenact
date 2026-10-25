// --------------------------------------------------------------------------------------------------
// @file       MigrationStudioPreview.swift
// @brief      Saved Studio surfaces, artwork and global Week appearance preparation
// @details    Supported User Data Model versions: 1.0 base and working 1.1 appearance composition. Local Studio-preview format 2 maps
//             global appearance/order separately without changing the released 1.0 schemas.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Converts reusable artwork and retains account-unbound Studio/global appearance evidence.
/// @section Purpose
///     Preserve authored surfaces and original-file references without flattening inherited defaults.
@MainActor
enum MigrationStudioPreview
{

    /// Independent local appearance evidence and canonical saved artwork records.
    /// @section Purpose
    ///     Keep source-order/global-default preservation distinct from final contract integration.
    struct Result
    {

        let document:      [String: Any]
        let appearanceDocument: [String: Any]
        let appearanceRecords: [[String: Any]]
        let records:       [[String: Any]]
        let assetRecords:  [[String: Any]]
        let preparedCount: Int
        let artworkCount:  Int
        let issueCount:    Int
    }


    /// @fcn MigrationStudioPreview.surface
    /// @brief Validate and map a native surface without normalizing colors or framing
    /// @param[in] source Actual saved surface
    /// @param[in] context Candidate appearance/file identity mappings
    /// @return Complete canonical-shaped surface value
    /// @throws Invalid colors, numeric bounds, URL/file references or native metadata
    private static func surface(_ source: StudioSurface, context: MigrationContentValues) throws -> Any
    {

        for hex in [source.color, source.secondaryColor]
        {
            guard hex.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil else
            {
                throw MigrationContentValues.Failure.invalid("studio_color_format")
            }
        }
        return try context.appearance(MigrationContentValues.object(source), kind: "surface")
    }


    /// @fcn MigrationStudioPreview.prepare
    /// @brief Convert saved appearance stores independently from content and user settings
    /// @details Never invokes defaults/loaders, randomizers, image downloads or source writes.
    /// @param[in] values Frozen source preferences
    /// @param[in] records Existing canonical records proving retained reference targets
    /// @param[in] mediaDigests Verified original-media hashes
    /// @param[in,out] journal Candidate migration identities; committed only after success
    /// @return Artwork records plus local Studio/Week evidence and explicit review issues
    /// @throws Unknown source fields, invalid saved shapes, duplicate identities or surface errors
    static func prepare(values: [String: Any], records: [[String: Any]], mediaDigests: [String: String],
        journal: inout MigrationIdentityJournal) throws -> Result
    {

        let context = MigrationContentValues(journal: journal, timeZoneID: "Etc/UTC", mediaDigests: mediaDigests)
        context.known = Set(records.compactMap { $0["id"] as? String })
        for record in records where record["record_type"] as? String == "unavailable_reference"
        {
            if let target = (record["payload"] as? [String: Any])?["target_id"] as? String
            {
                context.known.insert(target)
            }
        }
        var studio: Any = NSNull()
        var week: Any = NSNull()
        var assetRecords: [[String: Any]] = []
        var output: [[String: Any]] = []
        var artworkIDs: [String] = []
        let issues: [String] = []
        var prepared = 0
        if let value = values["Plenact.Studio.Settings.v1"]
        {
            guard let data = value as? Data,
                  let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(raw.keys).isSubset(of: ["views", "defaultCardSurface", "defaultNoteSurface", "variesNewSurfaces", "variesNewHeaders", "palette"]),
                  let views = raw["views"] as? [String: Any],
                  Set(views.keys).isSubset(of: Set(StudioDestination.allCases.map(\.rawValue))) else
            {
                throw MigrationContentValues.Failure.invalid("studio_settings_fields")
            }
            for value in views.values
            {
                try MigrationContentGuard.check(value, type: "StudioSurface")
            }
            for key in ["defaultCardSurface", "defaultNoteSurface"]
            {
                if let value = raw[key], !(value is NSNull)
                {
                    try MigrationContentGuard.check(value, type: "StudioSurface")
                }
            }
            let saved = try JSONDecoder().decode(StudioSettings.self, from: data)
            guard saved.palette.allSatisfy({ $0.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil }) else
            {
                throw MigrationContentValues.Failure.invalid("studio_palette_format")
            }
            var mappedViews: [[String: Any]] = []
            for destination in saved.views.keys.sorted()
            {
                mappedViews.append(["destination": destination.lowercased(),
                    "surface": try surface(saved.views[destination]!, context: context)])
            }
            let payload: [String: Any] = ["views": mappedViews,
                "default_card_surface": try saved.defaultCardSurface.map { try surface($0, context: context) } as Any? ?? NSNull(),
                "default_note_surface": try saved.defaultNoteSurface.map { try surface($0, context: context) } as Any? ?? NSNull(),
                "varies_new_surfaces": saved.variesNewSurfaces, "varies_new_headers": saved.variesNewHeaders,
                "palette": saved.palette]
            let id = try context.id("studio_settings", owner: "workspace_metadata", legacy: "Plenact.Studio.Settings.v1")
            studio = ["id": id, "payload": payload]
            assetRecords.append(["record_type": "studio_settings_preview", "id": id, "payload": payload])
            prepared += 1
        }
        if let value = values["Plenact.Studio.Artwork.v1"]
        {
            guard let data = value as? Data,
                  let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  raw.allSatisfy({ Set($0.keys).isSubset(of: ["id", "name", "surface", "header", "italicSubtitle", "titleColor", "textColor"]) }) else
            {
                throw MigrationContentValues.Failure.invalid("studio_artwork_fields")
            }
            for entry in raw
            {
                guard let savedSurface = entry["surface"] else
                {
                    throw MigrationContentValues.Failure.invalid("studio_artwork_surface")
                }
                try MigrationContentGuard.check(savedSurface, type: "StudioSurface")
            }
            let artwork = try JSONDecoder().decode([StudioArtwork].self, from: data)
            guard Set(artwork.map(\.id)).count == artwork.count else
            {
                throw MigrationContentValues.Failure.invalid("studio_duplicate_artwork")
            }
            for item in artwork
            {
                let id = try context.id("studio_artwork", owner: "artwork_library", legacy: item.id.uuidString.lowercased())
                artworkIDs.append(id)
                output.append(context.document("studio_artwork", id: id, payload: ["name": item.name,
                    "surface": try surface(item.surface, context: context), "header": item.header?.rawValue as Any? ?? NSNull(),
                    "italic_subtitle": item.italicSubtitle as Any? ?? NSNull(),
                    "title_color": item.titleColor?.rawValue as Any? ?? NSNull(),
                    "text_color": item.textColor?.rawValue as Any? ?? NSNull()]))
            }
        }
        if let value = values["Plenact.WeekAppearance.v1"]
        {
            guard let data = value as? Data else
            {
                throw MigrationContentValues.Failure.invalid("studio_week_storage_type")
            }
            let raw = try JSONSerialization.jsonObject(with: data)
            try MigrationContentGuard.check(raw, type: "BoardAppearance")
            let saved = try JSONDecoder().decode(BoardAppearance.self, from: data)
            // Validate complete surfaces even where the generic appearance mapper preserves strings.
            for item in [saved.studioSurface, saved.studioCardSurface].compactMap({ $0 })
            {
                _ = try surface(item, context: context)
            }
            let appearance = try context.appearance(MigrationContentValues.object(saved), kind: "board_appearance")
            let id = try context.id("workspace_display_preferences", owner: "legacy_global_week_appearance", legacy: "Plenact.WeekAppearance.v1")
            week = ["id": id, "appearance": appearance]
            assetRecords.append(["record_type": "week_appearance_preview", "id": id, "payload": appearance])
            prepared += 1
        }
        let global = (week as? [String: Any])?["appearance"] as? [String: Any]
        let appearanceDocument = try MigrationAppearanceModel.prepare(globalWeek: global, artworkIDs: artworkIDs,
            artworkPresent: values["Plenact.Studio.Artwork.v1"] != nil, context: context)
        let appearanceRecords = [appearanceDocument["workspace_appearance"], appearanceDocument["artwork_library"]]
            .compactMap { $0 as? [String: Any] }
        output += context.unavailable.keys.sorted().map { context.unavailable[$0]! }
        let document: [String: Any] = ["format": "plenact.ios-studio-preview", "format_version": 2,
            "appearance_model_version": "1.1",
            "target_user_data_model_version": "1.0", "account_binding_pending": true,
            "studio_settings": studio, "global_week_appearance": week, "artwork_ids": artworkIDs,
            "artwork_store_present": values["Plenact.Studio.Artwork.v1"] != nil,
            "issues": issues, "canonical_mapping_complete": issues.isEmpty]
        journal = context.journal
        return Result(document: document, appearanceDocument: appearanceDocument, appearanceRecords: appearanceRecords, records: output, assetRecords: assetRecords,
            preparedCount: prepared, artworkCount: artworkIDs.count, issueCount: issues.count)
    }
}
