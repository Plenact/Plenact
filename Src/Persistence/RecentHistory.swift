// --------------------------------------------------------------------------------------------------
// @file       RecentHistory.swift
// @brief      Owner-qualified viewed-item and search history
// @details    Retains lightweight references and recent terms rather than copying canonical Cards
//             into separate history content.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Stores the device-local history of recent search terms
///
/// @section    Purpose
///     Centralize bounded, deduplicated search-history preference access
///
enum RecentSearchStore
{


    private static let key = "Plenact.RecentSearches.v1" /* Versioned local search-history key */


    ///
    /// @fcn        RecentSearchStore.load(from:)
    /// @brief      Read device-local recent search terms
    /// @details    Returns the stored string array without normalization, or an empty array when
    ///             the preferences key is absent or incompatible
    ///
    /// @param[in]  defaults  Preferences store containing recent searches
    ///
    /// @return     ([String]) stored terms in most-recent-first order
    ///
    /// @post       No preferences are modified
    ///
    static func load(from defaults: UserDefaults = .standard) -> [String]
    {


        defaults.stringArray(forKey: key) ?? []
    }


    ///
    /// @fcn        RecentSearchStore.remember(_:in:)
    /// @brief      Move a nonempty search term to the front of local history
    /// @details    Trims surrounding whitespace, removes case-insensitive duplicates, and persists
    ///             at most ten terms; blank input returns existing history unchanged
    ///
    /// @param[in]  query     User-entered search term
    /// @param[in]  defaults  Preferences store receiving updated history
    ///
    /// @return     ([String]) resulting most-recent-first history
    ///
    /// @post       Only nonempty normalized input writes the history key
    ///
    @discardableResult
    static func remember(_ query: String, in defaults: UserDefaults = .standard) -> [String]
    {


        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)  /* Normalized query to remember            */
        var searches = load(from: defaults)                               /* Recent queries updated in recency order */

        guard !term.isEmpty else
        {


            return searches
        }

        searches.removeAll
        {
            $0.caseInsensitiveCompare(term) == .orderedSame
        }

        searches.insert(term, at: 0)
        searches = Array(searches.prefix(10))
        defaults.set(searches, forKey: key)

        return searches
    }


    ///
    /// @fcn        RecentSearchStore.clear(in:)
    /// @brief      Remove device-local search history
    /// @details    Deletes only the versioned recent-searches preference key
    ///
    /// @param[in]  defaults  Preferences store to clear
    ///
    /// @return     (Void) removes the history key
    ///
    /// @post       Board content, bookmarks, and other preferences are untouched
    ///
    static func clear(in defaults: UserDefaults = .standard)
    {


        defaults.removeObject(forKey: key)
    }

}


///
/// Retains an owner-qualified recently viewed item reference
///
/// @section    Purpose
///     Stores collection and local Card identity in visit order so Library and Activity history
///     can resolve canonical live content.
///
struct LibraryRecentItem: Codable, Equatable, Identifiable
{


    let collectionID: UUID
    let cardID:       Int
    var id:           String
    {
            "\(collectionID.uuidString).\(cardID)"
    }

}


///
/// Stores owner-qualified Library visit history
///
/// @section    Purpose
///     Decodes and saves recent-item references through the supplied preferences store without
///     copying the underlying Cards.
///
enum LibraryRecentStore
{


    static let key = "Plenact.LibraryRecents.v1"


    ///
    /// @fcn        LibraryRecentStore.load
    /// @brief      Read the Library's recent item history
    /// @details    Decodes retained owner-qualified items and returns an empty array when storage is absent or
    ///             unreadable.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     ([LibraryRecentItem]) decoded Library recents, or an empty array for absent or unreadable storage
    ///
    static func load(from defaults: UserDefaults = .standard) -> [LibraryRecentItem]
    {

        guard let data = defaults.data(forKey: key) else
        {
            return []
        }

        return (try? JSONDecoder().decode([LibraryRecentItem].self, from: data)) ?? []
    }


    ///
    /// @fcn        LibraryRecentStore.remember
    /// @brief      Move an item to the front of Library recents
    /// @details    Also records Activity history, deduplicates the selected item, limits Library history to eight,
    ///             and persists when encoding succeeds.
    ///
    /// @param[in]  item      Item supplied to this operation
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     ([LibraryRecentItem]) updated deduplicated Library recents, limited to eight entries
    ///
    static func remember(_ item: LibraryRecentItem, defaults: UserDefaults = .standard) -> [LibraryRecentItem]
    {

        ActivityRecentStore.remember(item, defaults: defaults)
        let items = Array(([item] + load(from: defaults).filter
                {
                    $0 != item
                }).prefix(8))
        if let data = try? JSONEncoder().encode(items)
        {
            defaults.set(data, forKey: key)
        }

        return items
    }

}


///
/// Stores Activity's recent-item history
///
/// @section    Purpose
///     Falls back to legacy Library history only when Activity storage is absent and maintains its
///     own encoded recent references.
///
enum ActivityRecentStore
{


    static let key = "Plenact.ActivityRecents.v1"


    ///
    /// @fcn        ActivityRecentStore.load
    /// @brief      Read Activity history with a legacy Library fallback
    /// @details    Uses Library recents only when Activity storage is absent; malformed Activity data produces an
    ///             empty array.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     ([LibraryRecentItem]) decoded Activity recents, legacy Library fallback, or an empty array for
    ///             invalid Activity data
    ///
    static func load(from defaults: UserDefaults = .standard) -> [LibraryRecentItem]
    {

        guard let data = defaults.data(forKey: key) else
        {
            return LibraryRecentStore.load(from: defaults)
        }

        return (try? JSONDecoder().decode([LibraryRecentItem].self, from: data)) ?? []
    }


    ///
    /// @fcn        ActivityRecentStore.remember
    /// @brief      Record a recently opened item for Activity
    /// @details    Moves the owner-qualified identity to the front, removes duplicates, and retains at most twenty
    ///             entries.
    ///
    /// @param[in]  item      Item supplied to this operation
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Void) no return value
    ///
    static func remember(_ item: LibraryRecentItem, defaults: UserDefaults = .standard)
    {

        let items = Array(([item] + load(from: defaults).filter
                {
                    $0 != item
                }).prefix(20))
        if let data = try? JSONEncoder().encode(items)
        {
            defaults.set(data, forKey: key)
        }

    }


    ///
    /// @fcn        ActivityRecentStore.clear
    /// @brief      Explicitly clear both Activity and Library recent history
    /// @details    Writes empty encoded arrays to both keys so the legacy fallback cannot repopulate cleared history.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Void) no return value
    ///
    static func clear(defaults: UserDefaults = .standard)
    {

        defaults.set(Data("[]".utf8), forKey: key)
        defaults.set(Data("[]".utf8), forKey: LibraryRecentStore.key)
    }

}
