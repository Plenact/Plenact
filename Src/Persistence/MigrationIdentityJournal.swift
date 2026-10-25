// --------------------------------------------------------------------------------------------------
// @file       MigrationIdentityJournal.swift
// @brief      Durable source-qualified identities for repeatable local migration
// @details    Supported User Data Model versions: 1.0 base and 1.1 appearance metadata. Private
//             journal formats 1/2/3; targetModelVersion retains its legacy meaning of base Model 1.0.
//             The journal is neither a server record, an account credential nor a sync operation.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Identifies legacy content without confusing another owner's matching numeric identifier.
/// @section Purpose
///     Preserve source provenance independently from titles, list positions and account display names.
struct MigrationSourceIdentity: Codable, Hashable
{

    let recordType:    String  /* Canonical target record type                       */
    let owner:         String  /* Stable source-owner namespace, never display text   */
    let legacyID:      String  /* Original identifier represented without coercion   */
    let discriminator: String? /* Source creation discriminator where actually known */
}


/// Associates one qualified source identity with a stable portable UUID.
/// @section Purpose
///     Retain the same mapping across retries, restarts and explicit export copies.
struct MigrationIdentityEntry: Codable, Equatable
{

    let source: MigrationSourceIdentity /* Exact source provenance */
    let target: UUID                    /* Stable portable identity */
}


/// Persistent local migration journal, explicitly unlinked to a verified cloud owner.
/// @section Purpose
///     Allocate stable identities before conversion without pretending a local profile is an account.
struct MigrationIdentityJournal: Codable
{

    private(set) var formatVersion:        Int                      /* Local journal format, independent of Model 1.0 */
    let targetModelVersion:   String                   /* Explicit portable definition target             */
    let sourceInstallationID: UUID                     /* Durable source-installation namespace            */
    let previewWorkspaceID:   UUID                     /* Local preview only; not server-owned workspace  */
    private(set) var entries: [MigrationIdentityEntry] /* Retained mappings; removed source entries remain */
    private var targets: [MigrationSourceIdentity: UUID] = [:] /* Rebuilt local lookup; never serialized */


    /// Exact on-disk journal fields; the lookup cache is derived only.
    /// @section Purpose
    ///     Keep durable provenance independent of transient migration performance state.
    private enum CodingKeys: String, CodingKey
    {

        case formatVersion, targetModelVersion, sourceInstallationID, previewWorkspaceID, entries
    }


    /// Stable migration failures never authorize replacing a corrupt or incompatible journal.
    /// @section Purpose
    ///     Fail closed when retry identities cannot be trusted.
    enum Failure: Error
    {

        case unsupported, corrupt, invalidSource, conflictingWrite, unsafePath
    }


    /// @fcn MigrationIdentityJournal.init
    /// @brief Create an unpersisted source namespace for a genuinely new migration
    /// @return An empty journal with fresh local-only UUIDs
    init()
    {

        formatVersion = 2
        targetModelVersion = "1.0"
        sourceInstallationID = UUID()
        previewWorkspaceID = UUID()
        entries = []
    }


    /// @fcn MigrationIdentityJournal.resolve
    /// @brief Reuse an exact qualified identity or allocate it once
    /// @details Owner/creation changes remain distinct. Callers retain a stable owner through moves.
    /// @param[in] source Original qualified identity
    /// @return Stable target UUID
    /// @throws Invalid or unsupported identity kinds
    mutating func resolve(_ source: MigrationSourceIdentity) throws -> UUID
    {

        try Self.validate(source)
        if source.recordType.hasPrefix("nested_")
        {
            formatVersion = max(formatVersion, 2)
        }
        if ["workspace_appearance", "artwork_library"].contains(source.recordType)
        {
            formatVersion = max(formatVersion, 3)
        }
        if targets.count != entries.count
        {
            guard Set(entries.map(\.source)).count == entries.count else
            {
                throw Failure.corrupt
            }
            targets = Dictionary(uniqueKeysWithValues: entries.map { ($0.source, $0.target) })
        }
        if let existing = targets[source]
        {
            return existing
        }
        let target = UUID()
        entries.append(MigrationIdentityEntry(source: source, target: target))
        targets[source] = target
        return target
    }


    /// @fcn MigrationIdentityJournal.validate
    /// @brief Check a qualified identity without allocating or searching mappings
    /// @param[in] source Original provenance key
    /// @return Void for a supported bounded identity
    /// @throws Invalid source errors
    private static func validate(_ source: MigrationSourceIdentity) throws
    {

        let types: Set<String> = ["account", "workspace", "collection", "list", "card", "label",
            "label_category", "calendar_week", "calendar_index", "daily_plan", "weekly_review",
            "periodic_review", "planning_template", "template_library", "review_rhythm", "asset",
            "content_selection", "user_profile", "user_preferences", "studio_settings", "studio_artwork",
            "today_shortcuts", "workspace_display_preferences", "unavailable_reference", "workspace_appearance", "artwork_library",
            "nested_checklist", "nested_checklist_item", "nested_action_detail", "nested_comment",
            "nested_reaction", "nested_attachment", "nested_history", "nested_assignee"]
        guard types.contains(source.recordType), !source.owner.isEmpty,
              source.owner.utf8.count <= 4096, source.legacyID.utf8.count <= 4096,
              (source.discriminator?.utf8.count ?? 0) <= 4096 else
        {
            throw Failure.invalidSource
        }
    }


    /// @fcn MigrationIdentityJournal.encoded
    /// @brief Preserve the entire journal in a deterministic JSON representation
    /// @return UTF-8 journal bytes with stable key order
    /// @throws Encoding failures
    func encoded() throws -> Data
    {

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }


    /// @fcn MigrationIdentityJournal.decode
    /// @brief Validate retained journal structure, version and one-to-one mapping before use
    /// @details Unknown fields/versions and colliding mappings are not silently dropped or reset.
    /// @param[in] data Original journal bytes
    /// @return Validated journal
    /// @throws Corrupt or unsupported journal errors
    static func decode(_ data: Data) throws -> MigrationIdentityJournal
    {

        guard data.count <= 32 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["formatVersion", "targetModelVersion", "sourceInstallationID", "previewWorkspaceID", "entries"] else
        {
            throw Failure.corrupt
        }
        guard [1, 2, 3].contains(object["formatVersion"] as? Int ?? 0), object["targetModelVersion"] as? String == "1.0" else
        {
            throw Failure.unsupported
        }
        guard let rawEntries = object["entries"] as? [[String: Any]], rawEntries.count <= 100_000 else
        {
            throw Failure.corrupt
        }
        for entry in rawEntries
        {
            guard Set(entry.keys) == ["source", "target"], let source = entry["source"] as? [String: Any],
                  Set(source.keys).isSubset(of: ["recordType", "owner", "legacyID", "discriminator"]),
                  ["recordType", "owner", "legacyID"].allSatisfy({ source[$0] is String }) else
            {
                throw Failure.corrupt
            }
        }
        let journal = try JSONDecoder().decode(MigrationIdentityJournal.self, from: data)
        guard Set(journal.entries.map(\.source)).count == journal.entries.count,
              Set(journal.entries.map(\.target)).count == journal.entries.count,
              !journal.entries.contains(where: { $0.target == journal.sourceInstallationID || $0.target == journal.previewWorkspaceID }),
              journal.sourceInstallationID != journal.previewWorkspaceID else
        {
            throw Failure.corrupt
        }
        let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
        for identifier in [journal.sourceInstallationID, journal.previewWorkspaceID] + journal.entries.map(\.target)
        {
            guard identifier.uuidString.lowercased().range(of: uuidPattern, options: .regularExpression) != nil else
            {
                throw Failure.corrupt
            }
        }
        for entry in journal.entries
        {
            guard journal.formatVersion >= 2 || !entry.source.recordType.hasPrefix("nested_") else
            {
                throw Failure.unsupported
            }
            guard journal.formatVersion >= 3 || !["workspace_appearance", "artwork_library"].contains(entry.source.recordType) else
            {
                throw Failure.unsupported
            }
            try validate(entry.source)
        }
        return journal
    }
}


/// Coordinates a private journal with exact-baseline compare before atomic replacement.
/// @section Purpose
///     Avoid resetting identities after corruption or overwriting another migration's newer mapping.
@MainActor
enum MigrationIdentityStore
{

    /// @fcn MigrationIdentityStore.read
    /// @brief Read a private journal without supplying defaults for an existing corrupt file
    /// @param[in] url Journal location under the app's migration-support directory
    /// @return Exact original bytes, or nil only when genuinely absent
    /// @throws Unsafe path or filesystem errors
    static func read(at url: URL) throws -> Data?
    {

        var current = url
        while current.path != "/"
        {
            if FileManager.default.fileExists(atPath: current.path)
            {
                let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else
                {
                    throw MigrationIdentityJournal.Failure.unsafePath
                }
            }
            else if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil
            {
                throw MigrationIdentityJournal.Failure.unsafePath
            }
            current.deleteLastPathComponent()
        }
        guard FileManager.default.fileExists(atPath: url.path) else
        {
            return nil
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 32 * 1024 * 1024 else
        {
            throw MigrationIdentityJournal.Failure.corrupt
        }
        return try Data(contentsOf: url)
    }


    /// @fcn MigrationIdentityStore.save
    /// @brief Persist mappings before exposing an export, retaining their expected baseline
    /// @details This main-actor API is the app's only journal writer. Atomic replacement protects
    ///          interrupted writes; baseline comparison rejects stale writers within that boundary.
    /// @param[in] journal Fully prepared mapping journal
    /// @param[in] url Private destination
    /// @param[in] expected Original bytes or nil for first creation
    /// @return Void once the complete new journal is persisted
    /// @throws Conflict, structural validation or filesystem errors
    static func save(_ journal: MigrationIdentityJournal, at url: URL, expected: Data?) throws
    {

        guard try read(at: url) == expected else
        {
            throw MigrationIdentityJournal.Failure.conflictingWrite
        }
        let data = try journal.encoded()
        _ = try MigrationIdentityJournal.decode(data)
        if let expected
        {
            let original = try MigrationIdentityJournal.decode(expected)
            let retained = Dictionary(uniqueKeysWithValues: journal.entries.map { ($0.source, $0.target) })
            guard original.formatVersion <= journal.formatVersion,
                  original.sourceInstallationID == journal.sourceInstallationID,
                  original.previewWorkspaceID == journal.previewWorkspaceID,
                  original.entries.allSatisfy({ retained[$0.source] == $0.target }) else
            {
                throw MigrationIdentityJournal.Failure.conflictingWrite
            }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
