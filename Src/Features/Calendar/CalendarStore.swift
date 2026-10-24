// --------------------------------------------------------------------------------------------------
// @file       CalendarStore.swift
// @brief      Validated dated workspace persistence
// @details    Loads versioned calendar documents and saves complete owner snapshots through
//             explicit checked operations.
//
// --------------------------------------------------------------------------------------------------
import CryptoKit
import SwiftUI


///
/// Persists validated dated calendar documents
///
/// @section    Purpose
///     Checks document versions and owner uniqueness on load and uses checked writes for retained
///     Week snapshots.
///
enum PlanningCalendarStore
{


    static let key = "Plenact.CalendarWeeks.v1"


    ///
    /// @fcn        PlanningCalendarStore.load
    /// @brief      Read and validate the retained planning calendar
    /// @details    Returns nil for absent storage and rejects malformed encoding, unsupported versions, duplicate
    ///             week identities, or a missing current week.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (PlanningCalendarDocument?) validated document, or nil when no saved value exists
    /// @throws     Explicit failures include `CocoaError(.coderReadCorrupt)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    static func load(from defaults: UserDefaults = .standard) throws -> PlanningCalendarDocument?
    {

        guard let data = defaults.data(forKey: key) else
        {
            return nil
        }

        let result = try JSONDecoder().decode(PlanningCalendarDocument.self, from: data)
        guard result.version == 1, (1 ... 7).contains(result.firstWeekday),
        Set(result.weeks.map(\.startKey)).count == result.weeks.count,
        Set(result.weeks.map(\.id)).count == result.weeks.count,
        result.weeks.contains(where:
            {
                $0.startKey == result.currentWeekKey
            })
        else
        {

            throw CocoaError(.coderReadCorrupt)
        }

        return result
    }


    ///
    /// @fcn        PlanningCalendarStore.save
    /// @brief      Save a calendar without overwriting unreadable retained data
    /// @details    Loads the existing value first so corruption or unsupported data is surfaced before the encoded
    ///             replacement is written.
    ///
    /// @param[in]  document  Retained document containing the operation's current workspace records
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    static func save(_ document: PlanningCalendarDocument, to defaults: UserDefaults = .standard) throws
    {

        // Retained corrupt or unsupported data must not be silently overwritten.
        _ = try load(from: defaults)
        defaults.set(try JSONEncoder().encode(document), forKey: key)
    }

}
