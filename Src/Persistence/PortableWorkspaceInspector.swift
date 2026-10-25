// --------------------------------------------------------------------------------------------------
// @file       PortableWorkspaceInspector.swift
// @brief      Read-only inspection of the installed portable test workspace
// @details    Supported User Data Model versions: 1.0 base and working 1.1. Displays portable records
//             directly; does not load legacy preferences or offer editing in the main application.
// --------------------------------------------------------------------------------------------------
import SwiftUI


/// Lets the owner compare installed Lists, Cards and saved metadata without modifying either workspace.
/// @section Purpose
///     Make portable test installation visible independently of the original native backup.
struct PortableWorkspaceInspector: View
{

    let package: ReviewedPortablePackage


    /// @fcn PortableWorkspaceInspector.base
    /// @brief Decode the already verified installed snapshot for read-only presentation
    /// @return Canonical base workspace, or an empty value if presentation decoding unexpectedly fails
    private var base: [String: Any]
    {

        guard let files = FileWrapper(serializedRepresentation: package.snapshot),
              let bytes = try? MigrationBackupReader.file("Assembly.json", in: files),
              let assembly = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let export = assembly["workspace_export"] as? [String: Any],
              var base = export["base_workspace"] as? [String: Any] else
        {
            return [:]
        }
        let deleted = Set(export["local_card_deletions"] as? [String] ?? [])
        if var planning = base["planning"] as? [String: Any], var content = planning["content"] as? [String: Any]
        {
            content["cards"] = (content["cards"] as? [[String: Any]] ?? []).filter { !deleted.contains($0["id"] as? String ?? "") }
            content["lists"] = (content["lists"] as? [[String: Any]] ?? []).map { record in
                var record = record
                if var payload = record["payload"] as? [String: Any]
                {
                    for key in ["card_ids", "archived_card_ids"]
                    {
                        payload[key] = (payload[key] as? [String] ?? []).filter { !deleted.contains($0) }
                    }
                    record["payload"] = payload
                }
                return record
            }
            planning["content"] = content
            base["planning"] = planning
        }
        return base
    }


    /// @fcn PortableWorkspaceInspector.body
    /// @brief Present retained content directly from the isolated installed snapshot
    /// @return Read-only List and Card navigation with summary metadata
    var body: some View
    {

        let base = base
        let planning = base["planning"] as? [String: Any] ?? [:]
        let content = planning["content"] as? [String: Any] ?? [:]
        let lists = content["lists"] as? [[String: Any]] ?? []
        let cards = content["cards"] as? [[String: Any]] ?? []
        let selections = base["content_selections"] as? [[String: Any]] ?? []
        let artwork = base["artwork"] as? [[String: Any]] ?? []
        let plans = planning["daily_plans"] as? [[String: Any]] ?? []
        Form
        {
            Section
            {
                Text("Installed portable test copy. Your main workspace is unchanged.")
                LabeledContent("Cards", value: String(package.cardCount))
                LabeledContent("Lists", value: String(package.listCount))
                LabeledContent("Verified original files", value: String(package.mediaCount))
            }
            Section("Lists")
            {
                ForEach(lists.indices, id: \.self)
                { index in
                    let list = lists[index]
                    let payload = list["payload"] as? [String: Any] ?? [:]
                    let ids = payload["card_ids"] as? [String] ?? []
                    let byID = Dictionary(uniqueKeysWithValues: cards.compactMap { card -> (String, [String: Any])? in
                        guard let id = card["id"] as? String else
                        {
                            return nil
                        }
                        return (id, card)
                    })
                    NavigationLink(payload["title"] as? String ?? "List")
                    {
                        List
                        {
                            ForEach(ids, id: \.self)
                            { id in
                                if let card = byID[id], let detail = card["payload"] as? [String: Any]
                                {
                                    NavigationLink(detail["title"] as? String ?? "Card")
                                    {
                                        Form
                                        {
                                            LabeledContent("Completed", value: detail["completed"] as? Bool == true ? "Yes" : "No")
                                            if let selected = selections.first(where: {
                                                ($0["payload"] as? [String: Any])?["card_id"] as? String == id
                                            }), let saved = selected["payload"] as? [String: Any]
                                            {
                                                LabeledContent("Bookmarked", value: saved["bookmarked"] as? Bool == true ? "Yes" : "No")
                                                LabeledContent("Importance", value: String(saved["importance"] as? Int ?? 0))
                                            }
                                            ForEach(["subtitle_override", "description_override", "location"], id: \.self)
                                            { key in
                                                if let text = detail[key] as? String, !text.isEmpty
                                                {
                                                    Text(text)
                                                }
                                            }
                                            LabeledContent("Checklists", value: String((detail["checklists"] as? [Any])?.count ?? 0))
                                            LabeledContent("Attachments", value: String((detail["attachments"] as? [Any])?.count ?? 0))
                                            LabeledContent("History entries", value: String((detail["edit_history"] as? [Any])?.count ?? 0))
                                        }
                                        .navigationTitle(detail["title"] as? String ?? "Card")
                                    }
                                }
                            }
                        }
                        .navigationTitle(payload["title"] as? String ?? "List")
                    }
                }
            }
            Section("Saved artwork")
            {
                ForEach(artwork.indices, id: \.self)
                { index in
                    Text((artwork[index]["payload"] as? [String: Any])?["name"] as? String ?? "Artwork")
                }
            }
            Section("Daily plans")
            {
                ForEach(plans.indices, id: \.self)
                { index in
                    if let intention = (plans[index]["payload"] as? [String: Any])?["intention"] as? String
                    {
                        Text(intention)
                    }
                }
            }
            Section("Saved metadata")
            {
                LabeledContent("Personal selections", value: String((base["content_selections"] as? [Any])?.count ?? 0))
                LabeledContent("Saved artwork", value: String((base["artwork"] as? [Any])?.count ?? 0))
                LabeledContent("Daily plans", value: String((planning["daily_plans"] as? [Any])?.count ?? 0))
                LabeledContent("Preferences retained", value: base["user_preferences"] is [String: Any] ? "Yes" : "No")
            }
        }
        .navigationTitle("Portable test workspace")
    }
}
