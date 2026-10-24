// --------------------------------------------------------------------------------------------------
// @file       BookmarkStore.swift
// @brief      Device-local bookmark persistence
// @details    Retains personal saved identities independently of shared Board snapshot content.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


/// Persists device-local bookmarks without changing the shared Board document.
///
/// @section    Purpose
///     Isolate bookmark preference reads and writes from the shared Board snapshot
///
enum SavedCardPersistence
{


    private static let storageKey = "Plenact.SavedCardIDs.v1" /* Versioned local bookmark key */


    ///
    /// @fcn        SavedCardPersistence.load()
    /// @brief      Restore device-local card bookmarks
    /// @details    Reads integer IDs from the versioned standard-preferences key and removes
    ///             duplicate values through Set construction; missing or incompatible data yields
    ///             no bookmarks
    ///
    /// @return     (Set<Int>) stored card identities
    ///
    /// @post       Stored preferences and Board content are unchanged
    ///
    static func load() -> Set<Int>
    {


        Set(UserDefaults.standard.array(forKey: storageKey) as? [Int] ?? [])
    }


    ///
    /// @fcn        SavedCardPersistence.save(_:)
    /// @brief      Store the current device-local bookmark set
    /// @details    Writes IDs as a sorted integer array for deterministic preference representation
    ///
    /// @param[in]  cardIDs  Complete set of bookmarked card IDs
    ///
    /// @return     (Void) replaces the stored bookmark array
    ///
    /// @post       The shared Board document is not modified
    ///
    static func save(_ cardIDs: Set<Int>)
    {


        UserDefaults.standard.set(cardIDs.sorted(), forKey: storageKey)
    }

}
