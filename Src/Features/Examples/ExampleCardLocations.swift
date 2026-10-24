// --------------------------------------------------------------------------------------------------
// @file       ExampleCardLocations.swift
// @brief      Oshkosh locations for bundled Gym and Work Cards
// @details    Adds verified example destinations to new routines and performs a one-time, backed-up
//             fill of empty locations in existing editable Cards. Custom and archived content is retained.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Shares example destinations and a guarded one-time location update
///
/// @section    Purpose
///     Demonstrates Card locations using the requested Oshkosh places, without changing future
///     manually created Cards. A migration marker prevents removed locations from being restored.
///
enum ExampleCardLocations
{


    static let gym = "Planet Fitness, 1971 S Koeller St, Oshkosh, WI 54902"
    static let work = "Mercury Marine Plant 33, 505 Marion Road, Oshkosh, WI 54901"
    static let migrationKey = "Plenact.ExampleCardLocations.Applied.v1"
    static let backupKey = "Plenact.ExampleCardLocations.Backup.v1"
    private static let boardKey = "Plenact.Board.v1"
    private static let collectionsKey = "Plenact.PersonalCollections.v1"

    ///
    /// Retains the complete workspace values published after a successful location update
    ///
    /// @section    Purpose
    ///     Separates preparing and saving a migration from replacing the live workspace state.
    ///
    struct Snapshot
    {

        let lists:       [KanbanList]
        let calendar:    PlanningCalendarDocument
        let collections: [PersonalCollection]
    }



    ///
    /// @fcn        ExampleCardLocations.location
    /// @brief      Resolve the verified destination for an exact Gym or Work title
    /// @details    Ignores case and accidental outer whitespace without matching unrelated titles
    ///             such as Work on a home project or Gym research.
    /// @param[in]  title Existing or bundled Card title
    /// @return     (String?) requested example location, or nil for other titles
    ///
    static func location(for title: String) -> String?
    {

        switch title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        {

        case "gym":
            return gym
        case "work":
            return work
        default:
            return nil
        }

    }



    ///
    /// @fcn        ExampleCardLocations.updating
    /// @brief      Fill empty locations in matching editable Cards of active Lists
    /// @details    Preserves existing locations, Notes, dividers, locked Cards, archived Lists,
    ///             and archived Cards. Normal List assignment retains ordinary edit history.
    /// @param[in]  lists Existing active and archived Lists to inspect
    /// @return     ([KanbanList]) unchanged records plus eligible location additions
    ///
    static func updating(_ lists: [KanbanList]) -> [KanbanList]
    {

        lists.map
        {

        list in
            guard !list.isArchived else
            {

                return list
            }

            let cards = list.cards.map
            {

            card in
                guard card.presentation == .card, !card.isSectionDivider, !card.isEditingLocked,
                CardLocation.normalized(card.location) == nil,
                let location = location(for: card.word) else
                {

                    return card
                }

                var updated = card
                updated.location = location
                return updated
            }

            guard cards != list.cards else
            {

                return list
            }

            var updated = list
            updated.cards = cards
            return updated
        }

    }



    ///
    /// @fcn        ExampleCardLocations.updating
    /// @brief      Fill eligible Cards inside active personal collections
    /// @details    Whole archived collections retain their original Cards and location values.
    /// @param[in]  collections Saved personal Boards and Lists
    /// @return     ([PersonalCollection]) updated active collections with archived content retained
    ///
    static func updating(_ collections: [PersonalCollection]) -> [PersonalCollection]
    {

        collections.map
        {

        collection in
            guard collection.isActive else
            {

                return collection
            }

            var updated = collection
            updated.lists = updating(collection.lists)
            return updated
        }

    }



    ///
    /// @fcn        ExampleCardLocations.applyOnce
    /// @brief      Save a one-time fill of existing Gym and Work location fields
    /// @details    Prepares all records before writing, keeps a copy of prior persisted documents,
    ///             verifies each write, and restores the original documents on failure. The marker
    ///             is written only after success, so later manual removals remain removed.
    /// @param[in]  lists       Live current-week Lists
    /// @param[in]  calendar    Retained dated weeks and their canonical ownership
    /// @param[in]  collections Live personal collections
    /// @param[in]  defaults    Workspace preferences domain receiving the saved update
    /// @return     (Snapshot?) saved workspace, or nil when this update has already been applied
    /// @throws     Propagates routine validation, encoding, and verified-storage failures
    ///
    static func applyOnce(
        lists: [KanbanList], calendar: PlanningCalendarDocument, collections: [PersonalCollection],
        to defaults: UserDefaults = .standard
    ) throws -> Snapshot?
    {

        guard !defaults.bool(forKey: migrationKey) else
        {

            return nil
        }

        let updatedLists = updating(lists)
        let updatedCollections = updating(collections)
        var updatedCalendar = calendar
        for index in updatedCalendar.weeks.indices
        {

            let week = updatedCalendar.weeks[index]
            if week.startKey == updatedCalendar.currentWeekKey
            {

                updatedCalendar.weeks[index].collection.lists = updatedLists
            }

            else if week.collection.isActive
            {

                updatedCalendar.weeks[index].collection.lists = updating(week.collection.lists)
            }

        }

        var library = try PlanningRoutineStore.load(from: defaults)
        for index in library.templates.indices where library.templates[index].collection.isActive
        {

            library.templates[index].collection.lists = updating(library.templates[index].collection.lists)
        }

        try PlanningRoutineStore.validate(library)
        let encoder = JSONEncoder()
        let replacements = [
            boardKey: try encoder.encode(updatedLists),
            PlanningCalendarStore.key: try encoder.encode(updatedCalendar),
            collectionsKey: try encoder.encode(updatedCollections),
            PlanningRoutineStore.key: try encoder.encode(library)
        ]
        var previous: [String: Data] = [:]
        for key in replacements.keys
        {

            previous[key] = defaults.data(forKey: key)
        }

        let backup = try encoder.encode(previous)
        defaults.set(backup, forKey: backupKey)
        guard defaults.synchronize(), defaults.data(forKey: backupKey) == backup else
        {

            throw CocoaError(.fileWriteUnknown)
        }

        do
        {

            for (key, value) in replacements
            {

                defaults.set(value, forKey: key)
            }

            guard defaults.synchronize(), replacements.allSatisfy(
                {
                    defaults.data(forKey: $0.key) == $0.value
                }) else
            {

                throw CocoaError(.fileWriteUnknown)
            }

            defaults.set(true, forKey: migrationKey)
            guard defaults.synchronize(), defaults.bool(forKey: migrationKey) else
            {

                throw CocoaError(.fileWriteUnknown)
            }

        }

        catch
        {

            for key in replacements.keys
            {

                if let value = previous[key]
                {

                    defaults.set(value, forKey: key)
                }

                else
                {

                    defaults.removeObject(forKey: key)
                }

            }

            defaults.removeObject(forKey: migrationKey)
            defaults.synchronize()
            throw error
        }

        return Snapshot(lists: updatedLists, calendar: updatedCalendar, collections: updatedCollections)
    }

}

