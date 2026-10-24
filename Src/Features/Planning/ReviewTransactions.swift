// --------------------------------------------------------------------------------------------------
// @file       ReviewTransactions.swift
// @brief      Recovery boundary for multi-store review mutations
// @details    Retains original preference bytes before changing source content or review progress
//             and restores interrupted operations before normal use.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Protects multi-store review decisions with recovery state
///
/// @section    Purpose
///     Records original preferences before mutation and clears the transaction only after source
///     content and review progress have both saved.
///
@MainActor
enum DailyReviewTransaction
{


    static let key = "Plenact.DailyReviewTransaction.v1"
    static let keys = [
        PlanningCalendarStore.key, "Plenact.Board.v1", "Plenact.PersonalCollections.v1", "Plenact.SavedCardIDs.v1",
        DailyPlanStore.key, WeeklyReviewStore.key
    ]


    ///
    /// @fcn        DailyReviewTransaction.begin
    /// @brief      Capture preferences before a checked review transaction
    /// @details    Snapshots the core keys and explicitly allowed additional keys into a recovery journal before
    ///             mutation begins.
    ///
    /// @param[in]  defaults        Preferences store used for this operation
    /// @param[in]  additionalKeys  Additional explicitly allowed preference keys to include in the recovery journal
    ///
    /// @return     (Data) encoded recovery journal capturing the allowed preference keys and their prior values
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    static func begin(in defaults: UserDefaults = .standard, additionalKeys: [String] = []) throws -> Data
    {

        guard defaults.object(forKey: key) == nil else
        {
            throw CocoaError(.fileWriteUnknown)
        }

        var previous: [String: Any] = [:]
        guard Set(additionalKeys).isSubset(of: ["Plenact.LibraryImportant.v1"]) else
        {

            throw CocoaError(.fileWriteUnknown)
        }

        let capturedKeys = Array(Set(keys + additionalKeys))
        for name in capturedKeys
        {
            previous[name] = defaults.object(forKey: name)
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: ["version": 1, "previous": previous, "keys": capturedKeys], format: .binary, options: 0)
        defaults.set(data, forKey: key)
        guard defaults.synchronize(), defaults.data(forKey: key) == data else
        {
            throw CocoaError(.fileWriteUnknown)
        }

        return data
    }


    ///
    /// @fcn        DailyReviewTransaction.recover
    /// @brief      Restore a retained review transaction snapshot
    /// @details    Validates journal keys and restores their captured values; legacy journals use the original key
    ///             set so uncaptured preferences are preserved.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`, `CocoaError(.fileWriteUnknown)`.
    ///             Errors from throwing dependencies propagate unless handled within this operation.
    ///
    static func recover(in defaults: UserDefaults = .standard) throws
    {

        guard defaults.object(forKey: key) != nil else
        {
            return
        }

        guard let data = defaults.data(forKey: key),
        let snapshot = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        snapshot["version"] as? Int == 1,
        let previous = snapshot["previous"] as? [String: Any]
        else
        {
            throw CocoaError(.fileReadCorruptFile)
        }

        let capturedKeys = snapshot["keys"] as? [String] ?? keys
        guard Set(keys).isSubset(of: Set(capturedKeys)),
        Set(capturedKeys).isSubset(of: Set(keys + ["Plenact.LibraryImportant.v1"])),
        Set(previous.keys).isSubset(of: Set(capturedKeys))
        else
        {
            throw CocoaError(.fileReadCorruptFile)
        }

        for name in capturedKeys
        {

            if let value = previous[name]
            {

                defaults.set(value, forKey: name)
            }
            else
            {

                defaults.removeObject(forKey: name)
            }

        }

        guard defaults.synchronize() else
        {
            throw CocoaError(.fileWriteUnknown)
        }

        defaults.removeObject(forKey: key)
        guard defaults.synchronize() else
        {
            defaults.set(data, forKey: key);
            throw CocoaError(.fileWriteUnknown)
        }

    }


    ///
    /// @fcn        DailyReviewTransaction.perform
    /// @brief      Execute a review update with recoverable preferences
    /// @details    Begins a journal, runs the throwing action, and completes the journal on success; a failure
    ///             attempts restoration before being propagated.
    ///
    /// @param[in]  defaults        Preferences store used for this operation
    /// @param[in]  additionalKeys  Additional explicitly allowed preference keys to include in the recovery journal
    /// @param[in]  action          Throwing transaction body whose result is returned after a successful commit
    ///
    /// @return     (T) value returned by the successfully completed transaction action
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    static func perform<T>(
        in defaults: UserDefaults = .standard, additionalKeys: [String] = [], _ action: () throws -> T
    ) throws -> T
    {

        let snapshot = try begin(in: defaults, additionalKeys: additionalKeys)
        do
        {

            let result = try action()
            guard defaults.synchronize() else
            {
                throw CocoaError(.fileWriteUnknown)
            }

            defaults.removeObject(forKey: key)
            guard defaults.synchronize() else
            {
                throw CocoaError(.fileWriteUnknown)
            }

            return result
        }
        catch
        {

            defaults.set(snapshot, forKey: key)
            try recover(in: defaults)
            throw error
        }

    }

}
