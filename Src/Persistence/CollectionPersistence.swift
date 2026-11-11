// --------------------------------------------------------------------------------------------------
// @file       CollectionPersistence.swift
// @brief      Local personal collection storage and migration
// @details    Loads complete owners, validates supported content, and preserves records during
//             explicit checked updates
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Loads and saves personal collection snapshots in user defaults
///
/// @section    Purpose
///     Persist user-owned collection metadata and board content locally
///
enum PersonalCollectionStore
{
    /// Versioned storage key for saved personal collections
    private static let key = "Plenact.PersonalCollections.v1"           /* Versioned personal collection persistence key */


    ///
    /// @fcn        PersonalCollectionStore.load(from:)
    /// @brief      Load saved personal collections
    /// @details    Returns an empty collection when no value exists or decoding fails
    ///
    /// @param[in]  defaults  Defaults store to read
    ///
    /// @return     ([PersonalCollection]) decoded collections or an empty array
    ///
    /// @post       Stored values are unchanged
    ///
    static func load(from defaults: UserDefaults = .standard) -> [PersonalCollection]
    {
        guard let data = defaults.data(forKey: key) else
        {                                                       /* Stored personal collection document */
            return []
        }


        return ((try? JSONDecoder().decode([PersonalCollection].self, from: data)) ?? []).map
        {
            DefaultListTutorial.removingUntouchedWelcomeCards(from: $0)
        }
    }


    ///
    /// @fcn        PersonalCollectionStore.save(_:to:)
    /// @brief      Save personal collections when encoding succeeds
    /// @details    Encodes the complete collection snapshot and writes it to the versioned key
    ///
    /// @param[in]  collections  Collections to persist
    /// @param[in]  defaults     Defaults store to update
    ///
    /// @return     (Void) writes encoded data when encoding succeeds
    ///
    /// @post       Encoding failure leaves the stored value unchanged
    ///
    static func save(_ collections: [PersonalCollection], to defaults: UserDefaults = .standard)
    {
        guard let data = try? JSONEncoder().encode(collections)
        else
        {               /* Encoded collection snapshot ready for storage */
            return
        }


        defaults.set(data, forKey: key)
    }


    ///
    /// @fcn        PersonalCollectionStore.saveChecked(_:to:)
    /// @brief      Encode and save personal collections while reporting encoding failures
    /// @details    Propagates JSON encoding errors to the caller instead of silently skipping the
    ///             write
    ///
    /// @param[in]  collections  Collections to persist
    /// @param[in]  defaults     Defaults store to update
    ///
    /// @return     (Void) writes the encoded collection snapshot
    ///
    /// @throws     EncodingError when the collection snapshot cannot be encoded
    ///
    static func saveChecked(_ collections: [PersonalCollection], to defaults: UserDefaults = .standard) throws
    {
        defaults.set(try JSONEncoder().encode(collections), forKey: key)
    }


    ///
    /// @fcn        PersonalCollectionStore.archiveBoard(id:in:to:)
    /// @brief      Archive an active board collection and persist the result
    /// @details    Rejects missing, non-board, and already archived collection identities
    ///
    /// @param[in]  id           Identity of the board to archive
    /// @param[in]  collections  Current collection snapshot
    /// @param[in]  defaults     Defaults store to update
    ///
    /// @return     ([PersonalCollection]) updated snapshot with the board archived
    ///
    /// @throws     CocoaError when no active board has the supplied identity
    /// @throws     EncodingError when the updated snapshot cannot be encoded
    ///
    static func archiveBoard(
        id:             UUID,
        in collections: [PersonalCollection],
        to defaults:    UserDefaults = .standard
    ) throws -> [PersonalCollection]
    {
        guard
        let index = collections.firstIndex(where:
            {                                                   /* Position of the collection to archive */
                $0.id == id && $0.kind == .board && $0.isActive
            })
        else
        {
            throw CocoaError(.validationMissingMandatoryProperty)
        }


        var updated = collections       /* Directory snapshot carrying the archive state change */

        updated[index].isArchived = true

        try saveChecked(updated, to: defaults)

        return updated
    }


    ///
    /// @fcn        PersonalCollectionStore.archiveCollection(id:in:to:)
    /// @brief      Retain an active personal list or Board outside Library
    /// @details    Saves the complete updated collection snapshot before returning it
    ///
    /// @param[in]  id           Collection UUID
    /// @param[in]  collections  Current complete snapshot
    /// @param[in]  defaults     Destination preferences
    ///
    /// @return     ([PersonalCollection]) successfully saved archive state
    ///
    /// @throws     Validation or encoding errors; original state is unchanged
    ///
    static func archiveCollection(
        id:             UUID,
        in collections: [PersonalCollection],
        to defaults:    UserDefaults = .standard
    ) throws -> [PersonalCollection]
    {
        guard
        let index = collections.firstIndex(where:
            {                                                   /* Position of the active collection to archive */
                $0.id == id && $0.isActive && !$0.isPrimaryList
            })
        else
        {
            throw CocoaError(.validationMissingMandatoryProperty)
        }


        var updated = collections       /* Directory snapshot carrying the archived collection */

        updated[index].isArchived = true

        try saveChecked(updated, to: defaults)

        return updated
    }
}


/// Retains one deleted Library owner for a brief, in-process Undo window
/// @section Purpose
///     Restore only the deleted owner, preserving unrelated edits and refusing identity collisions
struct LibraryCollectionDeletion: Identifiable
{
    let collection: PersonalCollection          /* Complete deleted owner and its retained content */
    let index: Int                              /* Original directory position                     */
    let deadline: ContinuousClock.Instant       /* Monotonic Undo expiry                           */

    var id: UUID        /* Stable identity for the transient notice */
    {
        collection.id
    }


    /// @fcn LibraryCollectionDeletion.init
    /// @brief Capture an existing collection before checked deletion
    /// @param[in] id Owner to remove
    /// @param[in] collections Current directory
    /// @param[in] instant Monotonic deletion time
    /// @return Captured owner with a four-second deadline
    /// @throws CocoaError when the owner no longer exists
    init(id: UUID, in collections: [PersonalCollection], at instant: ContinuousClock.Instant = .now) throws
    {
        guard let index = collections.firstIndex(where: { $0.id == id && !$0.isPrimaryList }) else
        {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        self.collection = collections[index]
        self.index = index
        self.deadline = instant.advanced(by: .seconds(4))
    }


    /// @fcn LibraryCollectionDeletion.restoring
    /// @brief Merge the retained owner into the latest directory during its Undo window
    /// @param[in] collections Current directory, including edits since deletion
    /// @param[in] instant Monotonic Undo time
    /// @return Updated directory without overwriting an existing owner
    /// @throws CocoaError for expired Undo or an identity collision
    func restoring(in collections: [PersonalCollection], at instant: ContinuousClock.Instant = .now) throws
        -> [PersonalCollection]
    {
        guard instant < deadline, !collections.contains(where: { $0.id == id }) else
        {
            throw CocoaError(.validationMissingMandatoryProperty)
        }

        var restored = collections      /* Current directory receiving only the deleted owner */

        restored.insert(collection, at: min(index, restored.count))
        return restored
    }
}
