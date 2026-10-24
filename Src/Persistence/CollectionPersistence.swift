// --------------------------------------------------------------------------------------------------
// @file       CollectionPersistence.swift
// @brief      Local personal collection storage and migration
// @details    Loads complete owners, validates supported content, and preserves records during
//             explicit checked updates.
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


    /// Versioned storage key for saved personal collections.
    private static let key = "Plenact.PersonalCollections.v1" /* Versioned personal collection persistence key */


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
        {  /* Stored personal collection document */


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
        {  /* Encoded collection snapshot ready for storage */


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
        id: UUID,
        in collections: [PersonalCollection],
        to defaults: UserDefaults = .standard
    ) throws -> [PersonalCollection]
    {


        guard
        let index = collections.firstIndex(where:
            {  /* Position of the collection to archive */


                $0.id == id && $0.kind == .board && $0.isActive
            })
        else
        {


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        var updated = collections /* Directory snapshot carrying the archive state change */

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
        id: UUID, in collections: [PersonalCollection], to defaults: UserDefaults = .standard
    ) throws -> [PersonalCollection]
    {


        guard
        let index = collections.firstIndex(where:
            {  /* Position of the active collection to archive */


                $0.id == id && $0.isActive
            })
        else
        {


            throw CocoaError(.validationMissingMandatoryProperty)
        }


        var updated = collections /* Directory snapshot carrying the archived collection */

        updated[index].isArchived = true
        try saveChecked(updated, to: defaults)

        return updated
    }

}
