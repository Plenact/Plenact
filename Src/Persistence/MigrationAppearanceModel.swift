// --------------------------------------------------------------------------------------------------
// @file       MigrationAppearanceModel.swift
// @brief      Additive Model 1.1 global Week defaults and authored artwork ordering
// @details    Supported User Data Model versions: 1.0 base and 1.1 appearance composition. Local
//             preview only; no verified workspace binding, sync API or release publication is implied.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Gives global appearance and ordered artwork dedicated records instead of overloading Collections.
/// @section Purpose
///     Close source representation gaps while preserving the immutable Model 1.0 record namespace.
@MainActor
enum MigrationAppearanceModel
{

    /// @fcn MigrationAppearanceModel.prepare
    /// @brief Build separately versioned records only for actually present source stores
    /// @param[in] globalWeek Original mapped global Week appearance or nil when absent
    /// @param[in] artworkIDs Canonical base-model artwork IDs in exact authored library order
    /// @param[in] artworkPresent Whether the source library exists, including an explicitly empty one
    /// @param[in] context Candidate journal and local workspace namespace
    /// @return Local evidence containing nullable Model 1.1 records and their explicit base version
    /// @throws Invalid source identities or incompatible journal errors
    static func prepare(globalWeek: [String: Any]?, artworkIDs: [String], artworkPresent: Bool,
        context: MigrationContentValues) throws -> [String: Any]
    {

        let workspace = context.journal.previewWorkspaceID.uuidString.lowercased()
        var appearance: Any = NSNull()
        var library: Any = NSNull()
        if let globalWeek
        {
            let id = try context.id("workspace_appearance", owner: "workspace_metadata", legacy: "Plenact.WeekAppearance.v1")
            appearance = ["user_data_model_version": "1.1", "payload_schema_version": 1,
                "record_type": "workspace_appearance", "id": id, "workspace_id": workspace,
                "payload": ["week_board_defaults": globalWeek]] as [String: Any]
        }
        if artworkPresent
        {
            let id = try context.id("artwork_library", owner: "workspace_metadata", legacy: "Plenact.Studio.Artwork.v1")
            library = ["user_data_model_version": "1.1", "payload_schema_version": 1,
                "record_type": "artwork_library", "id": id, "workspace_id": workspace,
                "payload": ["artwork_ids": artworkIDs]] as [String: Any]
        }
        return ["format": "plenact.ios-appearance-preview", "format_version": 1,
            "target_user_data_model_version": "1.1", "base_user_data_model_version": "1.0",
            "workspace_id": workspace, "workspace_identity_scope": "local_preview",
            "workspace_appearance": appearance, "artwork_library": library]
    }
}
