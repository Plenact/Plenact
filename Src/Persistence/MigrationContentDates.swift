// --------------------------------------------------------------------------------------------------
// @file       MigrationContentDates.swift
// @brief      Pinned, explicit timezone conversion without relying on installed OS rules
// @details    Supported User Data Model versions: 1.0. Partial, local-only migration preview.
//             Original source bytes remain preserved; no cloud ownership or synchronization is implied.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Uses a pinned IANA 2025b transition projection for the first supported migration zones.
/// @section Purpose
///     Preserve source instant/date intent and fold occurrence with independent cross-language checks.
@MainActor
enum MigrationContentDates
{

    /// Pinned transition data, not a claim about the device's installed timezone package.
    /// @section Purpose
    ///     Bound current migration support explicitly to Chicago/UTC during 1900–2100.
    private struct Rules: Decodable
    {

        let tzdb_version: String
        let start_epoch: Int
        let end_epoch: Int
        let zones: [String: [[Int]]]
    }


    /// @fcn MigrationContentDates.convert
    /// @brief Convert native Date/display-kind together using confirmed original timezone context
    /// @param[in] value Optional original epoch seconds
    /// @param[in] kind Original date-kind token
    /// @param[in] context Conversion context retaining precision evidence
    /// @param[in] path Original field evidence path
    /// @return Tagged Model 1.0 date object or explicit null
    /// @throws Unsupported context/range or invalid time values
    static func convert(_ value: Any?, kind: String, context: MigrationContentValues, path: String) throws -> Any
    {

        guard let value, !(value is NSNull) else
        {
            return NSNull()
        }
        guard let epoch = (value as? NSNumber)?.doubleValue, epoch.isFinite,
              let url = Bundle.main.url(forResource: "MigrationTimeZoneRules", withExtension: "json") else
        {
            throw MigrationContentValues.Failure.invalid("date_context")
        }
        let rules = try JSONDecoder().decode(Rules.self, from: Data(contentsOf: url))
        guard rules.tzdb_version == "2025b", let transitions = rules.zones[["GMT", "UTC", "Etc/GMT"].contains(context.timeZoneID) ? "Etc/UTC" : context.timeZoneID],
              epoch >= Double(rules.start_epoch), epoch < Double(rules.end_epoch),
              let index = transitions.lastIndex(where: { Double($0[0]) <= epoch }) else
        {
            throw MigrationContentValues.Failure.invalid("unsupported_timezone_or_date_range")
        }
        let offset = transitions[index][1]
        guard offset % 60 == 0 else
        {
            throw MigrationContentValues.Failure.invalid("subminute_timezone_offset")
        }
        let wireEpoch = floor(epoch * 1000) / 1000
        let local = Date(timeIntervalSince1970: wireEpoch + Double(offset))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if kind == "date"
        {
            formatter.dateFormat = "yyyy-MM-dd"
            return ["kind": "date", "date": formatter.string(from: local)]
        }
        if kind == "time"
        {
            formatter.dateFormat = "HH:mm:ss.SSS"
            return ["kind": "time", "time": formatter.string(from: local)]
        }
        guard kind == "date_and_time" else
        {
            throw MigrationContentValues.Failure.invalid("date_kind")
        }
        var occurrence = "unique"
        for i in 1..<transitions.count
        {
            let delta = transitions[i - 1][1] - transitions[i][1]
            let instant = Double(transitions[i][0])
            if delta > 0, wireEpoch >= instant - Double(delta), wireEpoch < instant + Double(delta)
            {
                occurrence = wireEpoch < instant ? "first" : "second"
                break
            }
        }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return ["kind": kind, "local_date_time": formatter.string(from: local),
            "time_zone": context.timeZoneID, "tzdb_version": rules.tzdb_version,
            "utc_instant": try context.utc(value, path: path),
            "utc_offset": String(format: "%@%02d:%02d", sign, minutes / 60, minutes % 60), "occurrence": occurrence]
    }
}
