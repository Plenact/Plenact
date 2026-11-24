// --------------------------------------------------------------------------------------------------
// @file       RecentHistory.swift
// @brief      Owner-qualified viewed-item and search history
// @details    Retains lightweight references and recent terms rather than copying canonical Cards
//             into separate history content
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
    private static let key = "Plenact.RecentSearches.v1"        /* Versioned local search-history key */


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
        let term     = query.trimmingCharacters(in: .whitespacesAndNewlines)    /* Normalized query to remember            */
        var searches = load(from: defaults)                                     /* Recent queries updated in recency order */

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
///     can resolve canonical live content
///
struct LibraryRecentItem: Codable, Equatable, Identifiable
{
    let collectionID: UUID      /* Collection ID               */
    let cardID:       Int       /* Owner-local Card identifier */

    var id:           String    /* Record or view identity */
    {
            "\(collectionID.uuidString).\(cardID)"
    }
}


///
/// Stores owner-qualified Library visit history
///
/// @section    Purpose
///     Decodes and saves recent-item references through the supplied preferences store without
///     copying the underlying Cards
///
enum LibraryRecentStore
{
    static let key = "Plenact.LibraryRecents.v1"        /* Persistence lookup key */


    ///
    /// @fcn        LibraryRecentStore.load
    /// @brief      Read the Library's recent item history
    /// @details    Decodes retained owner-qualified items and returns an empty array when storage is absent or
    ///             unreadable
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
    ///             and persists when encoding succeeds
    ///
    /// @param[in]  item      Item supplied to this operation
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     ([LibraryRecentItem]) updated deduplicated Library recents, limited to eight entries
    ///
    static func remember(_ item: LibraryRecentItem, defaults: UserDefaults = .standard) -> [LibraryRecentItem]
    {
        ActivityRecentStore.remember(item, defaults: defaults)

        let items = Array(([item] + load(from: defaults).filter         /* Items being processed */
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
///     own encoded recent references
///
enum ActivityRecentStore
{
    static let key = "Plenact.ActivityRecents.v1"       /* Persistence lookup key */


    ///
    /// @fcn        ActivityRecentStore.load
    /// @brief      Read Activity history with a legacy Library fallback
    /// @details    Uses Library recents only when Activity storage is absent; malformed Activity data produces an
    ///             empty array
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
    ///             entries
    ///
    /// @param[in]  item      Item supplied to this operation
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Void) no return value
    ///
    static func remember(_ item: LibraryRecentItem, defaults: UserDefaults = .standard)
    {
        let items = Array(([item] + load(from: defaults).filter         /* Items being processed */
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
    /// @details    Writes empty encoded arrays to both keys so the legacy fallback cannot repopulate cleared history
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


/// Device-local, owner-qualified activity and recoverable deletions for dated lists.
enum DayListHistoryStore
{
    static let key = "Plenact.DayListHistory.v1"
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    struct Entry: Codable, Identifiable
    {
        var id = UUID()
        let ownerID: UUID
        let dayKey: String
        let listID: Int
        let cardID: Int
        let createdAt: Date?
        let title: String
        let itemKind: String
        let action: String
        let timestamp: Date
        var deletedCard: KanbanCard?
        var restoredAt: Date?
        var index = 0
        var previousID: Int?
        var nextID: Int?
        var wasBookmarked = false

        func restoring(in lists: [KanbanList], bookmarks: Set<Int>) -> ([KanbanList], Set<Int>)?
        {
            guard let card = deletedCard, restoredAt == nil,
                  let destination = lists.firstIndex(where: { $0.id == listID && !$0.isArchived }),
                  !lists.contains(where: { $0.allCards.contains(where: { $0.id == card.id }) })
            else { return nil }
            var snapshot = lists
            let cards = snapshot[destination].cards
            let position = cards.firstIndex(where: { $0.id == nextID })
                ?? cards.firstIndex(where: { $0.id == previousID }).map { $0 + 1 }
                ?? min(index, cards.count)
            var restored = card
            restored.listTitle = snapshot[destination].title
            snapshot[destination].cards.insert(restored, at: position)
            var saved = bookmarks
            if wasBookmarked { saved.insert(card.id) }
            return (snapshot, saved)
        }
    }

    static func load(from defaults: UserDefaults = .standard, now: Date = .now) throws -> [Entry]
    {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([Entry].self, from: data)
            .filter { now.timeIntervalSince($0.timestamp) < retention }
            .sorted { $0.timestamp == $1.timestamp ? $0.id.uuidString > $1.id.uuidString : $0.timestamp > $1.timestamp }
    }

    static func retainedFiles(from defaults: UserDefaults = .standard, now: Date = .now) throws -> Set<String>
    {
        Set(try load(from: defaults, now: now).filter { $0.restoredAt == nil }
            .flatMap { ($0.deletedCard?.attachments ?? []).flatMap(\.storedFileNames) })
    }

    /// Encode activity before either preferences value is written; no events for initial imports.
    static func recording(from old: PlanningCalendarDocument?, to new: PlanningCalendarDocument,
                          defaults: UserDefaults = .standard, now: Date = .now) throws -> Data
    {
        var entries = try load(from: defaults, now: now)
        let allPreviousCards = old?.weeks.flatMap { $0.collection.lists.flatMap(\.allCards) } ?? []
        let allCurrentCards = new.weeks.flatMap { $0.collection.lists.flatMap(\.allCards) }
        for week in new.weeks
        {
            guard let before = old?.weeks.first(where: { $0.id == week.id }) else { continue }
            for (dayKey, listID) in week.dayListIDs.sorted(by: { $0.key < $1.key })
            {
                guard let previous = before.collection.lists.first(where: { $0.id == listID }),
                      let current = week.collection.lists.first(where: { $0.id == listID })
                else { continue }
                func matches(_ lhs: KanbanCard, _ rhs: KanbanCard) -> Bool
                {
                    lhs.id == rhs.id && lhs.createdAt == rhs.createdAt
                }
                func event(_ card: KanbanCard, action: String) -> Entry
                {
                    Entry(ownerID: week.id, dayKey: dayKey, listID: listID, cardID: card.id,
                          createdAt: card.createdAt, title: card.word,
                          itemKind: card.presentation == .note ? "Note" : "Card", action: action,
                          timestamp: now)
                }
                if previous.title != current.title || previous.subtitle != current.subtitle
                    || previous.appearance != current.appearance
                {
                    entries.append(Entry(ownerID: week.id, dayKey: dayKey, listID: listID, cardID: -1,
                                         createdAt: nil, title: current.title, itemKind: "List",
                                         action: "Updated", timestamp: now))
                }
                for (index, card) in previous.cards.enumerated() where !card.isSectionDivider
                {
                    if let updated = current.cards.first(where: { matches($0, card) })
                    {
                        if card != updated
                        {
                            let action = card.isTitleChecked != updated.isTitleChecked
                                ? (updated.isTitleChecked ? "Completed" : "Marked incomplete") : "Updated"
                            entries.append(event(updated, action: action))
                        }
                        else
                        {
                            let oldOrder = previous.cards.filter { candidate in
                                current.cards.contains(where: { matches($0, candidate) })
                            }.map(\.id)
                            let newOrder = current.cards.filter { candidate in
                                previous.cards.contains(where: { matches($0, candidate) })
                            }.map(\.id)
                            if oldOrder.firstIndex(of: card.id) != newOrder.firstIndex(of: card.id)
                            { entries.append(event(card, action: "Reordered")) }
                        }
                    }
                    else if allCurrentCards.contains(where: { matches($0, card) })
                    {
                        entries.append(event(card, action: current.archivedCards.contains(where: { matches($0, card) })
                                             ? "Archived" : "Moved out"))
                    }
                    else
                    {
                        var deletion = event(card, action: "Deleted")
                        deletion.deletedCard = card
                        deletion.index = index
                        deletion.previousID = index > 0 ? previous.cards[index - 1].id : nil
                        deletion.nextID = index + 1 < previous.cards.count ? previous.cards[index + 1].id : nil
                        let isCurrentOwner = old?.weeks.first(where: { $0.startKey == old?.currentWeekKey })?.id == week.id
                        let liveBookmarks = isCurrentOwner
                            ? defaults.array(forKey: "Plenact.SavedCardIDs.v1") as? [Int] : nil
                        deletion.wasBookmarked = liveBookmarks.map { $0.contains(card.id) }
                            ?? before.collection.savedCardIDs.contains(card.id)
                        entries.append(deletion)
                    }
                }
                for card in current.cards where !card.isSectionDivider
                    && !previous.cards.contains(where: { matches($0, card) })
                {
                    let recovered = entries.indices.filter {
                        entries[$0].ownerID == week.id && entries[$0].listID == listID
                        && entries[$0].cardID == card.id && entries[$0].createdAt == card.createdAt
                        && entries[$0].deletedCard != nil && entries[$0].restoredAt == nil
                    }
                    for index in recovered { entries[index].restoredAt = now }
                    let action = !recovered.isEmpty ? "Restored"
                        : (allPreviousCards.contains(where: { matches($0, card) }) ? "Moved in" : "Added")
                    entries.append(event(card, action: action))
                }
            }
        }
        return try JSONEncoder().encode(entries)
    }
}

struct DayListHistorySheet: View
{
    let ownerID: UUID
    let dayKey: String
    let title: String
    let onRestore: (DayListHistoryStore.Entry) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DayListHistoryStore.Entry] = []
    @State private var errorMessage: String?

    var body: some View
    {
        NavigationStack
        {
            List
            {
                Section
                {
                    Text("Changes are saved on this device for 30 days. Deleted Cards and Notes can be restored during that time. Recording begins with this update.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if entries.isEmpty
                {
                    ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Saved changes to this day's list will appear here."))
                }
                ForEach(entries)
                {
                    entry in
                    VStack(alignment: .leading, spacing: 6)
                    {
                        Text("\(entry.action) · \(entry.itemKind)").font(.caption).foregroundStyle(.secondary)
                        Text(entry.title.isEmpty ? "Untitled" : entry.title).font(.headline)
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        if entry.deletedCard != nil
                        {
                            if entry.restoredAt != nil
                            {
                                Label("Restored", systemImage: "checkmark").font(.caption)
                            }
                            else
                            {
                                Button("Undo deletion", systemImage: "arrow.uturn.backward")
                                {
                                    guard onRestore(entry) else
                                    {
                                        errorMessage = "Could not restore this item. Its list may be unavailable, the item may already exist, its media may be missing, or saving may have failed."
                                        return
                                    }
                                    reload()
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("day.history.restore.\(entry.id)")
                                Text("Recoverable until \(entry.timestamp.addingTimeInterval(DayListHistoryStore.retention).formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("\(title) History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { reload() }
            .alert("History", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }))
            { Button("OK") { errorMessage = nil } }
            message: { Text(errorMessage ?? "") }
        }
    }

    private func reload()
    {
        do
        {
            entries = try DayListHistoryStore.load().filter { $0.ownerID == ownerID && $0.dayKey == dayKey }
        }
        catch { errorMessage = "Saved history could not be read. It has been retained." }
    }
}
