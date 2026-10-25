// --------------------------------------------------------------------------------------------------
// @file       PortableWorkspaceCandidate.swift
// @brief      Complete native-store candidate assembled from portable records and verified originals
// @details    Supported User Data Model versions: 1.0 base and working 1.1 appearance. Candidate format 1.
//             Retains canonical evidence and numeric aliases; stages privately without activating app stores.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Holds one coordinated native projection and its canonical source of truth for guarded installation.
/// @section Purpose
///     Keep store reconstruction, media verification and provenance retention in one candidate boundary.
@MainActor
struct PortableWorkspaceCandidate
{

    let values:       [String: Any]
    let media:        PortableMediaPlacement
    let snapshot:     Data
    let numericIDs:   [String: Int]
    let workspaceID:  String
    let timeZoneID:   String


    /// @fcn PortableWorkspaceCandidate.prepare
    /// @brief Reconstruct every supported native store from one reviewed portable package
    /// @param[in] package Frozen reviewed package; source backup members are never consulted
    /// @param[in] retainedAliases Existing identity map when rebuilding a candidate
    /// @param[in] mediaFilenames Export comparison only; normal import retains collision-safe canonical filenames
    /// @return Coordinated candidate without mutating active preferences or files
    /// @throws Unsupported ownership, schema shape, runtime context or model reconstruction
    static func prepare(_ package: ReviewedPortablePackage, retainedAliases: [String: Int] = [:], mediaFilenames: [String: String] = [:]) throws -> PortableWorkspaceCandidate
    {

        guard let files = FileWrapper(serializedRepresentation: package.snapshot) else
        {
            throw PortableEditableContent.Failure.invalid
        }
        _ = try PortablePackageReview.review(files: files)
        let assemblyBytes = try MigrationBackupReader.file("Assembly.json", in: files)
        guard let assembly = try JSONSerialization.jsonObject(with: assemblyBytes) as? [String: Any],
              let export = assembly["workspace_export"] as? [String: Any],
              Set(export.keys).subtracting(["local_card_deletions"]) == ["user_data_model_version", "payload_schema_version", "base_workspace", "workspace_appearance", "artwork_library"],
              let base = export["base_workspace"] as? [String: Any], let planning = base["planning"] as? [String: Any],
              let content = planning["content"] as? [String: Any], let workspace = planning["workspace_id"] as? String,
              let account = base["account"] as? [String: Any], let accountID = account["id"] as? String,
              let tombstones = base["tombstones"] as? [Any], tombstones.isEmpty else
        {
            throw PortableEditableContent.Failure.unsupported
        }
        let baseMany = ["profiles": "user_profile", "label_categories": "label_category", "labels": "label",
            "artwork": "studio_artwork", "content_selections": "content_selection", "unavailable_references": "unavailable_reference"]
        let planningMany = ["calendar_indexes": "calendar_index", "weeks": "calendar_week", "daily_plans": "daily_plan",
            "weekly_reviews": "weekly_review", "periodic_reviews": "periodic_review", "templates": "planning_template",
            "template_libraries": "template_library", "review_rhythms": "review_rhythm", "assets": "asset"]
        let contentMany = ["collections": "collection", "lists": "list", "cards": "card"]
        let singletons = ["account": "account", "workspace": "workspace", "user_preferences": "user_preferences",
            "studio_settings": "studio_settings", "today_shortcuts": "today_shortcuts", "display_preferences": "workspace_display_preferences"]
        guard Set(base.keys) == Set(baseMany.keys).union(singletons.keys).union(["user_data_model_version", "payload_schema_version", "planning", "tombstones"]),
              Set(planning.keys) == Set(planningMany.keys).union(["user_data_model_version", "payload_schema_version", "workspace_id", "account_id", "content"]),
              Set(content.keys) == Set(contentMany.keys).union(["user_data_model_version", "payload_schema_version", "workspace_id", "external_references"]) else
        {
            throw PortableEditableContent.Failure.unsupported
        }
        var records: [[String: Any]] = []
        for (object, groups) in [(base, baseMany), (planning, planningMany), (content, contentMany)]
        {
            for (key, kind) in groups
            {
                guard let items = object[key] as? [[String: Any]], items.allSatisfy({ $0["record_type"] as? String == kind }) else
                {
                    throw PortableEditableContent.Failure.invalid
                }
                records += items
            }
        }
        for (key, kind) in singletons
        {
            if let record = base[key] as? [String: Any]
            {
                guard record["record_type"] as? String == kind else
                {
                    throw PortableEditableContent.Failure.invalid
                }
                records.append(record)
            }
            else if !(base[key] is NSNull)
            {
                throw PortableEditableContent.Failure.invalid
            }
        }
        let media = try PortableMediaPlacement.prepare(package, filenames: mediaFilenames)
        let adapter = try PortableEditableContent(records: records, assetFiles: media.filenames, retainedAliases: retainedAliases,
            deletedCardIDs: PortableLocalDeletions.ids(in: export))
        let selections = try adapter.array(base["content_selections"])
        guard let calendar = try adapter.calendarDocument(selections: selections, accountID: accountID),
              let current = calendar.weeks.first(where: { $0.startKey == calendar.currentWeekKey }) else
        {
            // The existing root requires a saved calendar; never generate example Weeks on import.
            throw PortableEditableContent.Failure.unsupported
        }
        let weekRecords = try adapter.array(planning["weeks"])
        let zones = Set(weekRecords.compactMap { ($0["payload"] as? [String: Any])?["time_zone"] as? String })
        guard zones.count == 1, let zone = zones.first else
        {
            // Retain canonical per-Week zones; the legacy active root currently has one runtime calendar.
            throw PortableEditableContent.Failure.unsupported
        }
        let templateRecords = try adapter.array(planning["templates"])
        let calendarOwners = Set(weekRecords.compactMap { ($0["payload"] as? [String: Any])?["collection_id"] as? String })
        let templateOwners = templateRecords.compactMap { ($0["payload"] as? [String: Any])?["collection_id"] as? String }
        guard Set(templateOwners).count == templateOwners.count, calendarOwners.isDisjoint(with: templateOwners) else
        {
            throw PortableEditableContent.Failure.unsupported
        }
        let personal = try records.filter { record in
            guard record["record_type"] as? String == "collection", let id = record["id"] as? String else
            {
                return false
            }
            return !calendarOwners.contains(id) && !templateOwners.contains(id)
        }.map { try adapter.collection($0, selections: selections, accountID: accountID, timeZoneID: zone, listDates: [:]) }
        let templates = try adapter.templateLibrary(accountID: accountID)
        let preferences = try adapter.preferences(base["user_preferences"] as? [String: Any], accountID: accountID)
        let profiles = try adapter.array(base["profiles"])
        guard profiles.count <= 1 else
        {
            throw PortableEditableContent.Failure.invalid
        }
        let profile = try adapter.profile(profiles.first, preferences: preferences, accountID: accountID)
        let plans = try adapter.planningDocuments()
        var values: [String: Any] = [:]

        /// @fcn PortableWorkspaceCandidate.put
        /// @brief Encode a fully reconstructed native store without invoking its loader or save side effects
        /// @param[in] key Existing native persistent-store key
        /// @param[in] value Reconstructed Codable value
        /// @return Void after adding encoded bytes to the candidate only
        func put<T: Encodable>(_ key: String, _ value: T) throws
        {

            values[key] = try JSONEncoder().encode(value)
        }
        try put("Plenact.CalendarWeeks.v1", calendar)
        try put("Plenact.Board.v1", current.collection.lists)
        try put("Plenact.PersonalCollections.v1", personal)
        try put("Plenact.LabelLibrary.v1", adapter.labelLibrary())
        try put("Plenact.LibraryImportant.v1", adapter.importance(selections, accountID: accountID))
        values["Plenact.SavedCardIDs.v1"] = current.collection.savedCardIDs.sorted()
        try put("Plenact.DailyPlans.v1", plans.daily)
        try put("Plenact.WeeklyReviews.v1", plans.weekly)
        try put("Plenact.PeriodicReviews.v1", plans.periodic)
        if let rhythm = plans.rhythm
        {
            try put("Plenact.ReviewRhythm.v1", rhythm)
        }
        if let templates
        {
            try put("Plenact.PlanningTemplates.v1", templates)
        }
        if let preferences
        {
            try put("Plenact.PlanPreferences.v1", preferences)
        }
        if let profile
        {
            try put("Plenact.LocalProfile.v1", profile)
        }
        if let shortcuts = try adapter.shortcuts(base["today_shortcuts"] as? [String: Any])
        {
            try put("Plenact.TodayListShortcuts.v1", shortcuts)
        }
        if let studio = try adapter.studioSettings(base["studio_settings"] as? [String: Any], accountID: accountID)
        {
            try put("Plenact.Studio.Settings.v1", studio)
        }
        if let artwork = try adapter.artwork(export["artwork_library"] as? [String: Any])
        {
            try put("Plenact.Studio.Artwork.v1", artwork)
        }
        if let appearance = try adapter.weekAppearance(export["workspace_appearance"] as? [String: Any])
        {
            try put("Plenact.WeekAppearance.v1", appearance)
        }
        if let display = base["display_preferences"] as? [String: Any]
        {
            guard let body = display["payload"] as? [String: Any] else
            {
                throw PortableEditableContent.Failure.invalid
            }
            let projected = try adapter.mapped(body, fields: Dictionary(uniqueKeysWithValues: MigrationPreview.displayKeys.map { ($0.value, $0.key) }))
            for (key, value) in projected where !(value is NSNull)
            {
                values[key] = value
            }
        }
        for (key, value) in values
        {
            guard LegacyStoreValidation.check(key: key, value: value) == nil else
            {
                throw PortableEditableContent.Failure.invalid
            }
            if let bytes = value as? Data
            {
                let object = try JSONSerialization.jsonObject(with: bytes)
                guard LegacyStoreValidation.mediaIssues(object, store: key, files: Set(media.files.keys)).isEmpty else
                {
                    throw PortableEditableContent.Failure.invalid
                }
            }
        }
        return PortableWorkspaceCandidate(values: values, media: media, snapshot: package.snapshot,
            numericIDs: adapter.numericIDs, workspaceID: workspace, timeZoneID: zone)
    }


    /// @fcn PortableWorkspaceCandidate.stage
    /// @brief Stage all native stores, originals and immutable canonical evidence in one fresh candidate directory
    /// @param[in] root New private candidate directory; no active application path is replaced
    /// @return Void after exact stored-byte verification
    /// @throws Existing destination, serialization, file-placement or readback failure
    func stage(at root: URL) throws
    {

        try media.stage(at: root)
        var completed = false
        defer
        {
            if !completed
            {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let stores = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        let aliases: [String: Any] = ["format_version": 1, "workspace_id": workspaceID, "time_zone": timeZoneID, "numeric_ids": numericIDs]
        let aliasesData = try JSONSerialization.data(withJSONObject: aliases, options: .sortedKeys)
        let retained = root.appendingPathComponent("Library/Application Support/PlenactPortableRuntime", isDirectory: true)
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (name, data) in [("NativeStores.plist", stores), ("CanonicalPackage.bin", snapshot), ("IdentityAliases.json", aliasesData)]
        {
            let target = retained.appendingPathComponent(name)
            try data.write(to: target, options: [.atomic, .completeFileProtection])
            guard try Data(contentsOf: target) == data else
            {
                throw PortablePackageReview.Failure.integrity
            }
        }
        try media.verify(at: root)
        completed = true
    }
}


/// Installs a candidate only within the caller's root-owned backup/rollback transaction.
/// @section Purpose
///     Keep view teardown, backup retention and activation authorization outside pure reconstruction.
extension PortableWorkspaceCandidate
{

    /// @fcn PortableWorkspaceCandidate.install
    /// @brief Replace reviewed managed stores/media from a verified staging directory in the Simulator
    /// @param[in] staging Fully staged candidate
    /// @param[in] root Destination app or isolated test container
    /// @param[in] defaults Explicit destination defaults
    /// @param[in] domain Explicit persistent-domain name
    /// @return Void after exact preference/media/evidence verification
    /// @throws Unsupported environment/context, invalid staging or persistence errors; caller must roll back
    func install(from staging: URL, root: URL, defaults: UserDefaults, domain: String) throws
    {

        #if targetEnvironment(simulator)
        try media.verify(at: staging)
        let evidence = try PortableRuntimeEvidence.capture(root: staging)
        guard evidence["CanonicalPackage.bin"] == snapshot,
              let stores = evidence["NativeStores.plist"],
              let staged = try PropertyListSerialization.propertyList(from: stores, format: nil) as? [String: Any],
              NSDictionary(dictionary: values).isEqual(to: staged) else
        {
            throw PortablePackageReview.Failure.integrity
        }
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        guard !original.keys.contains(where: { ($0.hasPrefix("Plenact.") || $0.hasPrefix("plenact.")) && !LegacyStoreValidation.includes($0) }) else
        {
            throw PortableEditableContent.Failure.unsupported
        }
        let manager = FileManager.default
        for area in LegacyWorkspaceExport.mediaRoots + [PortableRuntimeEvidence.area]
        {
            let destination = root.appendingPathComponent(area)
            if manager.fileExists(atPath: destination.path)
            {
                try manager.removeItem(at: destination)
            }
            let source = staging.appendingPathComponent(area)
            if manager.fileExists(atPath: source.path)
            {
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: destination)
            }
        }
        let migration = root.appendingPathComponent("Library/Application Support/PlenactMigration")
        if manager.fileExists(atPath: migration.path)
        {
            try manager.removeItem(at: migration)
        }
        var destination = original.filter { !LegacyStoreValidation.includes($0.key) }
        destination.merge(values) { _, imported in imported }
        defaults.setPersistentDomain(destination, forName: domain)
        guard defaults.synchronize(), NSDictionary(dictionary: destination).isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]) else
        {
            throw PortablePackageReview.Failure.integrity
        }
        try media.verify(at: root)
        guard try PortableRuntimeEvidence.capture(root: root) == evidence else
        {
            throw PortablePackageReview.Failure.integrity
        }
        #else
        throw PortableEditableContent.Failure.unsupported
        #endif
    }
}
