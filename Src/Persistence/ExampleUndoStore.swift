// --------------------------------------------------------------------------------------------------
// @file       ExampleUndoStore.swift
// @brief      Pre-example workspace restoration snapshots
// @details    Keeps complete content and related personal selection state available for explicit
//             recovery after demonstration loading.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Captures the Board state and Today-list selection before loading example data
///
/// @section    Purpose
///     Preserve the prior local state for an explicit undo operation
///
struct ExampleLoadUndoSnapshot: Codable, Equatable
{


    let lists:            [KanbanList]  /* Board lists to restore                   */
    let todayListID:      Int?          /* Previously selected Today list, when set */
    var week:             DatedPlanningWeek? = nil
    var savedCardIDs:     Set<Int>? = nil
    var importantCardIDs: Set<Int>? = nil
    var importanceLevels: [Int: Int]? = nil
}


///
/// Stores the undo snapshot for loading example Board data
///
/// @section    Purpose
///     Keep one locally persisted pre-example snapshot available for undo
///
enum ExampleLoadUndoStore
{


    /// Versioned storage key for the saved undo snapshot.
    private static let storageKey = "Plenact.ExampleLoadUndo.v1" /* Versioned example-load recovery key */


    ///
    /// @fcn        ExampleLoadUndoStore.save(lists:todayListID:to:)
    /// @brief      Save a pre-example Board snapshot
    /// @details    Returns false when the snapshot cannot be encoded
    ///
    /// @param[in]  lists             Board lists to preserve
    /// @param[in]  todayListID       Selected Today list identity, if any
    /// @param[in]  defaults          Defaults store to update
    ///
    /// @param[in]  week              Optional complete dated Week retained for example-load restoration
    /// @param[in]  savedCardIDs      Optional personal bookmark snapshot retained for Undo
    /// @param[in]  importantCardIDs  Optional legacy importance-presence snapshot retained for Undo
    /// @param[in]  importanceLevels  Optional exact zero-through-five importance levels retained
    ///             for Undo
    ///
    /// @return     (Bool) whether the encoded snapshot was saved
    ///
    /// @post       A successful save replaces the previously stored undo snapshot
    ///
    @discardableResult
    static func save(
        lists: [KanbanList],
        todayListID: Int?,
        week: DatedPlanningWeek? = nil,
        savedCardIDs: Set<Int>? = nil,
        importantCardIDs: Set<Int>? = nil,
        importanceLevels: [Int: Int]? = nil,
        to defaults: UserDefaults = .standard
    ) -> Bool
    {


        let snapshot = ExampleLoadUndoSnapshot(
            lists: lists, todayListID: todayListID,
            week: week, savedCardIDs: savedCardIDs, importantCardIDs: importantCardIDs,
            importanceLevels: importanceLevels) /* Week state and Today selection retained for undo */

        guard let data = try? JSONEncoder().encode(snapshot) else
        {  /* Encoded recovery snapshot ready for storage */


            return false
        }


        defaults.set(data, forKey: storageKey)

        return true
    }


    ///
    /// @fcn        ExampleLoadUndoStore.load(from:)
    /// @brief      Load the saved pre-example Board snapshot
    /// @details    Returns nil when no snapshot exists or decoding fails
    ///
    /// @param[in]  defaults  Defaults store to read
    ///
    /// @return     (ExampleLoadUndoSnapshot?) decoded snapshot, or nil
    ///
    /// @post       Stored values are unchanged
    ///
    static func load(from defaults: UserDefaults = .standard) -> ExampleLoadUndoSnapshot?
    {


        guard let data = defaults.data(forKey: storageKey) else
        {  /* Stored example-load recovery document */


            return nil
        }


        return try? JSONDecoder().decode(ExampleLoadUndoSnapshot.self, from: data)
    }


    ///
    /// @fcn        ExampleLoadUndoStore.clear(from:)
    /// @brief      Remove the saved pre-example Board snapshot
    /// @details    Deletes only the undo snapshot key from the selected defaults store
    ///
    /// @param[in]  defaults  Defaults store to update
    ///
    /// @return     (Void) removes the saved snapshot
    ///
    static func clear(from defaults: UserDefaults = .standard)
    {


        defaults.removeObject(forKey: storageKey)
    }

}
