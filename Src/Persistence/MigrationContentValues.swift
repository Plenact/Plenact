// --------------------------------------------------------------------------------------------------
// @file       MigrationContentValues.swift
// @brief      Explicit nested value conversion, references and source-precision evidence
// @details    Supported User Data Model versions: 1.0. Partial, local-only migration preview.
//             Original source bytes remain preserved; no cloud ownership or synchronization is implied.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Carries resolved source ownership and preserves unresolved links explicitly.
/// @section Purpose
///     Keep nested conversion from guessing identity, missing media or historical authorship.
@MainActor
final class MigrationContentValues
{

    var journal: MigrationIdentityJournal                  /* Candidate identities; saved only after the slice succeeds */
    var known: Set<String> = []                            /* Canonical record IDs supplied by converted source records */
    var unavailable: [String: [String: Any]] = [:]          /* Typed explicit unavailable-reference documents            */
    var precisionEvidence: [[String: Any]] = []            /* Original epoch values not exactly representable in ms     */
    var usedNested: Set<String> = []
    var attachmentTargets: [String: String] = [:]
    var originalCards: [String: [String: Any]] = [:]
    var cardTargets: [String: String] = [:]                /* Original owner + numeric Card identity                    */
    var assetTargets: [String: String] = [:] /* Export-only verified source-path aliases; normal migration uses its journal */
    var originalCollectionIDs: [String: String] = [:]
    var ownerScopesByCollection: [String: [String]] = [:]
    var collectionTargets: [String: String] = [:]          /* Original Collection UUID -> canonical UUID                 */
    var calendarOwnerScopes: Set<String> = []
    var checklistWeekOverrides: [String: String] = [:]
    var timeZoneID: String                                 /* Explicit caller-confirmed original timezone                */
    let mediaDigests: [String: String]                     /* Exact preserved-file identities                           */


    /// Structured conversion failures remain visible in the partial preview report.
    /// @section Purpose
    ///     Refuse incompatible source instead of dropping fields or manufacturing values.
    enum Failure: Error
    {

        case invalid(String), timezoneRequired, projectionConflict, duplicateIdentity, unsupportedField(String)
    }


    /// @fcn MigrationContentValues.init
    /// @brief Initialize a conversion candidate with explicit source context
    /// @param[in] journal Original durable identity mappings
    /// @param[in] timeZoneID Confirmed original timezone
    /// @param[in] mediaDigests Preserved media path/digest pairs
    /// @return New uncommitted conversion context
    init(journal: MigrationIdentityJournal, timeZoneID: String, mediaDigests: [String: String])
    {

        self.journal = journal
        self.timeZoneID = timeZoneID
        self.mediaDigests = mediaDigests
    }


    /// @fcn MigrationContentValues.object
    /// @brief Encode a compatible native source value for explicit keyed mapping
    /// @param[in] value Actual natively decoded source
    /// @return JSON object with epoch seconds for Date fields
    /// @throws Native encoding/JSON errors
    static func object<T: Encodable>(_ value: T) throws -> [String: Any]
    {

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let object = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any] else
        {
            throw Failure.invalid("native_object")
        }
        return object
    }


    /// @fcn MigrationContentValues.id
    /// @brief Resolve an original owner-qualified identity without title/index matching
    /// @param[in] type Canonical type
    /// @param[in] owner Stable original source owner
    /// @param[in] legacy Original identifier
    /// @param[in] discriminator Optional original creation discriminator
    /// @return Lowercase stable portable UUID
    /// @throws Identity journal validation errors
    func id(_ type: String, owner: String, legacy: String, discriminator: String? = nil) throws -> String
    {

        try journal.resolve(MigrationSourceIdentity(recordType: type, owner: owner,
            legacyID: legacy, discriminator: discriminator)).uuidString.lowercased()
    }


    /// @fcn MigrationContentValues.document
    /// @brief Produce a complete portable envelope without editable server metadata
    /// @param[in] type Canonical type
    /// @param[in] id Stable canonical identity
    /// @param[in] payload Explicit mapped values
    /// @return Canonical record object
    func document(_ type: String, id: String, payload: [String: Any]) -> [String: Any]
    {

        ["user_data_model_version": "1.0", "payload_schema_version": 1, "record_type": type,
            "id": id, "workspace_id": journal.previewWorkspaceID.uuidString.lowercased(), "payload": payload]
    }


    /// @fcn MigrationContentValues.reference
    /// @brief Preserve a typed target while recording missing/pending source resolution
    /// @param[in] type Referenced canonical type
    /// @param[in] target Referenced stable UUID
    /// @return Target UUID
    /// @throws Identity resolution errors
    func reference(_ type: String, _ target: String) throws -> String
    {

        if !known.contains(target), unavailable[target] == nil
        {
            let record = try id("unavailable_reference", owner: "unavailable", legacy: type + ":" + target)
            unavailable[target] = document("unavailable_reference", id: record,
                payload: ["target_type": type, "target_id": target, "reason": "legacy_unresolved", "display_text": NSNull()])
        }
        return target
    }


    /// @fcn MigrationContentValues.cardReference
    /// @brief Resolve a numeric Card link only in its original owner scope
    /// @param[in] value Original numeric identifier
    /// @param[in] owner Original Collection namespace
    /// @return Known or explicitly unavailable target UUID
    /// @throws Identity errors
    func cardReference(_ value: Int, owner: String) throws -> String
    {

        if let target = cardTargets[owner + ":" + String(value)]
        {
            return target
        }
        return try reference("card", id("card", owner: owner, legacy: String(value)))
    }


    /// @fcn MigrationContentValues.asset
    /// @brief Retain a file-qualified asset reference pending the owned-Asset adapter/account binding
    /// @param[in] filename Optional original basename
    /// @param[in] area Explicit original media root
    /// @return Mapped target UUID or explicit null
    /// @throws Unsafe filenames or identity errors
    func asset(_ filename: Any?, area: String) throws -> Any
    {

        guard let filename, !(filename is NSNull) else
        {
            return NSNull()
        }
        guard let name = filename as? String, !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\") else
        {
            throw Failure.invalid("media_filename")
        }
        let path = area + "/" + name
        if let target = assetTargets[path]
        {
            return try reference("asset", target)
        }
        let target = try id("asset", owner: "owned_media", legacy: path, discriminator: mediaDigests[path])
        return try reference("asset", target)
    }


    /// @fcn MigrationContentValues.utc
    /// @brief Render a millisecond UTC timestamp while retaining original finer precision separately
    /// @param[in] value Original numeric epoch seconds
    /// @param[in] path Qualified source evidence path
    /// @return Fixed-width UTC timestamp
    /// @throws Invalid source timestamp
    func utc(_ value: Any, path: String) throws -> String
    {

        guard let number = value as? NSNumber, number.doubleValue.isFinite else
        {
            throw Failure.invalid("timestamp")
        }
        let epoch = number.doubleValue
        guard epoch >= -62_135_596_800, epoch < 253_402_300_800 else
        {
            throw Failure.invalid("timestamp_range")
        }
        let milliseconds = floor(epoch * 1000)
        if abs(epoch - milliseconds / 1000) > 0.000_000_1
        {
            precisionEvidence.append(["path": path, "source_epoch_seconds": epoch,
                "wire_epoch_milliseconds": milliseconds, "source_format": "native_date_seconds_since_1970"])
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }


    /// @fcn MigrationContentValues.lowerUUID
    /// @brief Normalize actual source UUID spelling without inventing nested identities
    /// @param[in] value Original UUID token
    /// @return Lowercase UUID
    /// @throws Invalid source identity
    static func lowerUUID(_ value: Any?) throws -> String
    {

        guard let text = value as? String, let id = UUID(uuidString: text) else
        {
            throw Failure.invalid("nested_uuid")
        }
        return id.uuidString.lowercased()
    }
}
