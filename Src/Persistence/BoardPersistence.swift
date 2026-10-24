// --------------------------------------------------------------------------------------------------
// @file       BoardPersistence.swift
// @brief      Checked local Board snapshot storage
// @details    Loads compatible retained content and coordinates save boundaries without embedding
//             presentation preferences in the Board document.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Persists and restores Board snapshots in local user defaults
///
/// @section    Purpose
///     Keep Board data available across launches without requiring a remote service
///
/// @details    Background operations report load and save failures through DatabaseActivity
///
enum KanbanBoardPersistence
{


    /// Versioned storage key for the serialized Board snapshot.
    private static let storageKey = "Plenact.Board.v1" /* Versioned local Board snapshot key */

    /// Serial queue used for Board snapshot I/O.
    private static let queue = DispatchQueue(
        label: "Plenact.Board.persistence", qos: .userInitiated) /* Serial worker for ordered Board persistence */


    ///
    /// @fcn        KanbanBoardPersistence.saveListsChecked(_:suiteName:)
    /// @brief      Save a destructive snapshot before changing visible state
    /// @details    Encodes first, then waits behind earlier queued writes to preserve save ordering
    ///
    /// @param[in]  lists      Complete Week snapshot
    /// @param[in]  suiteName  Optional isolated preference suite
    ///
    /// @return     (Void) save a destructive snapshot before changing visible state
    ///
    /// @throws     Encoding or preference-suite errors; no write occurs on encoding failure
    ///
    static func saveListsChecked(_ lists: [KanbanList], suiteName: String? = nil) throws
    {


        let data = try JSONEncoder().encode(lists) /* Encoded Board snapshot for the checked save */

        try queue.sync
        {

            let defaults = try persistenceDefaults(
                suiteName: suiteName) /* Validated preferences store receiving the Board document */

            defaults.set(data, forKey: storageKey)
        }

    }


    ///
    /// @fcn        KanbanBoardPersistence.loadListsInBackground(suiteName:)
    /// @brief      Load Board lists using the persistence queue
    /// @details    Reports load failures and displays deterministic sample data without deleting
    ///             the unreadable saved snapshot
    ///
    /// @param[in]  suiteName  Optional defaults suite; nil selects standard defaults
    ///
    /// @return     ([KanbanList]) decoded lists or the starter Board on failure
    ///
    /// @post       Saved data is not modified by loading
    ///
    @MainActor
    static func loadListsInBackground(suiteName: String? = nil) async -> [KanbanList]
    {


        let activity = DatabaseActivity.shared              /* Shared persistence progress and failure reporter */
        let operation = activity.begin("Loading Board...")  /* Progress identity for the pending Board load     */

        defer
        {


            activity.end(operation)
        }


        let result: Result<[KanbanList], Error> = await withCheckedContinuation
        {

        continuation in /* Background load outcome delivered to the caller */
            queue.async
            {

                continuation.resume(
                    returning: Result
                    {

                        let defaults = try persistenceDefaults(
                            suiteName: suiteName) /* Validated preferences store supplying the Board document */

                        guard let data = defaults.data(forKey: storageKey)
                        else
                        {  /* Stored Board document awaiting decoding */


                            return SampleData.lists
                        }

                        return try JSONDecoder().decode([KanbanList].self, from: data)
                    })
            }

        }


        switch result
        {


        case .success(let lists): /* Decoded Board snapshot */
            return lists
        case .failure(let error): /* Persistence or decoding failure reported to the caller */

            activity.report(
                                "Could not load the saved Board: \(error.localizedDescription) The starter Board is displayed; saved data has not been removed."
            )

            return SampleData.lists
        }

    }


    ///
    /// @fcn        KanbanBoardPersistence.saveListsInBackground(_:)
    /// @brief      Request a background save of Board lists
    /// @details    Enqueues the supplied snapshot for serialized persistence
    ///
    /// @param[in]  lists  Board lists to save
    ///
    /// @return     (Void) forwards the snapshot to the save queue
    ///
    @MainActor
    static func saveListsInBackground(_ lists: [KanbanList])
    {


        enqueueSave(lists)
    }


    ///
    /// @fcn        KanbanBoardPersistence.enqueueSave(_:suiteName:onSuccess:)
    /// @brief      Queue a Board snapshot for asynchronous persistence
    /// @details    Performs the write on the serial persistence queue and reports write errors
    ///
    /// @param[in]  lists      Board lists to save
    /// @param[in]  suiteName  Optional defaults suite; nil selects standard defaults
    /// @param[in]  onSuccess  Optional main-actor cleanup invoked only after a successful write
    ///
    /// @return     (Void) schedules the save operation
    ///
    @MainActor
    static func enqueueSave(
        _ lists: [KanbanList], suiteName: String? = nil,
        onSuccess: (@MainActor () -> Void)? = nil
    )
    {


        let activity = DatabaseActivity.shared             /* Shared persistence progress and failure reporter */
        let operation = activity.begin("Saving Board...")  /* Progress identity for the queued Board save      */

        // A serial queue preserves snapshot order even when edits arrive faster than encoding.
        queue.async
        {

            let result = Result
            {  /* Success or failure of the queued persistence operation   */

                let defaults = try persistenceDefaults(
                    suiteName: suiteName) /* Validated preferences store receiving the Board document */
                let data = try JSONEncoder().encode(
                    lists) /* Encoded Board snapshot ready for storage                 */

                defaults.set(data, forKey: storageKey)
            }

            Task
            {
                @MainActor in
                if case .failure(let error) = result
                {  /* Save failure surfaced through the activity reporter */


                    activity.report(
                                                            "Could not save the Board: \(error.localizedDescription) Your latest changes are not saved. Please try editing again."
                    )
                }
                else
                {


                    onSuccess?()
                }


                activity.end(operation)
            }

        }

    }


    ///
    /// @fcn        KanbanBoardPersistence.persistenceDefaults(suiteName:)
    /// @brief      Resolve the defaults store for a persistence operation
    /// @details    Uses standard defaults when no suite name is supplied
    ///
    /// @param[in]  suiteName  Optional defaults suite name
    ///
    /// @return     (UserDefaults) selected defaults store
    ///
    /// @throws     CocoaError when the named defaults suite cannot be created
    ///
    private static func persistenceDefaults(suiteName: String?) throws -> UserDefaults
    {


        guard let suiteName else
        {  /* Named preferences domain requested by the caller */


            return .standard
        }


        guard let defaults = UserDefaults(suiteName: suiteName)
        else
        {  /* Preferences store opened for the requested domain */


            throw CocoaError(.fileReadUnknown)
        }


        return defaults
    }


    ///
    /// @fcn        KanbanBoardPersistence.loadLists()
    /// @brief      Load the saved board lists
    /// @details    Decodes the locally stored JSON snapshot and returns sample data if no valid
    ///             snapshot exists
    ///
    /// @return     ([KanbanList]) restored board lists or the deterministic starter board
    ///
    /// @pre        UserDefaults may contain data encoded by this persistence format
    /// @post       Stored data is unchanged; callers receive a usable board list value
    ///
    static func loadLists() -> [KanbanList]
    {


        guard let data = UserDefaults.standard.data(forKey: storageKey), /* Encoded local Board data */

        let lists = try? JSONDecoder().decode([KanbanList].self, from: data)
        else
        {  /* Successfully decoded lists */


            return SampleData.lists
        }


        return lists
    }


    ///
    /// @fcn        KanbanBoardPersistence.saveLists(_:)
    /// @brief      Save the current board lists
    /// @details    Encodes the supplied list and card state as JSON and writes it to the versioned
    ///             user-defaults key
    ///
    /// @param[in]  lists  Board lists and their current card state
    ///
    /// @return     (Void) stores the encoded board snapshot when encoding succeeds
    ///
    /// @pre        lists contains the current in-memory board state
    /// @post       A valid encoded snapshot is stored locally; encoding failure leaves prior stored
    ///             data unchanged
    ///
    static func saveLists(_ lists: [KanbanList])
    {


        guard let data = try? JSONEncoder().encode(lists)
        else
        {  /* Encoded Board snapshot for legacy synchronous storage */


            return
        }


        UserDefaults.standard.set(data, forKey: storageKey)
    }

}
