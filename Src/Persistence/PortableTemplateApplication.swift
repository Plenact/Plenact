// --------------------------------------------------------------------------------------------------
// @file       PortableTemplateApplication.swift
// @brief      Reserve durable identities when a template preview is committed to an imported Week
// @details    Supported User Data Model versions: 1.0 base and working 1.1.
//             Preview generation remains read-only. Existing Cards/Lists and authored nested identities
//             remain unchanged; only newly copied native aliases and their explicit references move
// --------------------------------------------------------------------------------------------------
import Foundation


/// Translates a prepared template application at the checked save boundary
/// @section Purpose
///     Avoid collisions with other imported owners without reserving identities for cancelled previews
@MainActor
enum PortableTemplateApplication
{
    /// @fcn PortableTemplateApplication.reserve
    /// @brief Reserve new List/Card aliases while preserving the exact prepared preview content
    /// @param[in] preview Prepared additive or replacement Week
    /// @param[in] original Retained target Week, or nil for the existing new-Week creation path
    /// @param[in] importantIDs Prepared example importance markers
    /// @param[in] root App container or isolated synthetic container
    /// @return Identity-safe Week and translated importance markers
    /// @throws Invalid preview identities, partial runtime evidence or reservation failure
    static func reserve(_ preview: DatedPlanningWeek, original: DatedPlanningWeek?, importantIDs: Set<Int>,
        root: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) throws
        -> (week: DatedPlanningWeek, importantIDs: Set<Int>)
    {
        guard let original, !(try PortableRuntimeEvidence.capture(root: root)).isEmpty else
        {
            return (preview, importantIDs)
        }
        guard preview.collection.id == original.collection.id, preview.startKey == original.startKey else
        {
            throw PortableEditedExport.Failure.structureChanged
        }

        let originalLists = Set(original.collection.lists.map(\.id)) /* Original lists */
        let originalCards =                                          /* Original cards */
            Set(original.collection.lists.flatMap(\.allCards).map(\.id))
        let lists         = preview.collection.lists.map(\.id) /* Ordered List records */
        let cards         = /* Card records under consideration */
            preview.collection.lists.flatMap(\.allCards).map(\.id)

        guard Set(lists).count == lists.count, Set(cards).count == cards.count,
              importantIDs.isSubset(of: Set(cards)) else
        {
            throw PortableEditedExport.Failure.inconsistent
        }

        let newLists = lists.filter { !originalLists.contains($0) } /* New lists         */
        let newCards = cards.filter { !originalCards.contains($0) } /* New cards         */
        let count    = newLists.count + newCards.count              /* Number of entries */

        guard count > 0 else
        {
            return (preview, importantIDs)
        }

        let maximum = /* Upper supported bound */
            (lists + cards + Array(originalLists) + Array(originalCards)).max() ?? -1

        guard maximum < Int.max else
        {
            throw PortableEditedExport.Failure.unsupported
        }

        let start   = /* Range start */
            try PortableCreationIdentity.reserve(proposed: maximum + 1, count: count, root: root)
        let listMap = /* List map */
            Dictionary(uniqueKeysWithValues: newLists.enumerated().map { ($0.element, start + $0.offset) })
        let cardMap = /* Card map */
            Dictionary(uniqueKeysWithValues: newCards.enumerated().map { ($0.element, start + newLists.count + $0.offset) })

        /// @fcn PortableTemplateApplication.reserve.references
        /// @brief Translate explicit copied Card links without interpreting opaque edit-history bytes
        /// @param[in] value Newly copied Card subtree
        /// @return Translated subtree with preserved authored values
        func references(_ value: Any) -> Any
        {
            if var object = value as? [String: Any]
            {
                for field in ["cardID", "retainedCardID"]
                {
                    if let number = object[field] as? Int, let target = cardMap[number]
                    {
                        object[field] = target

                    }
                }
                for field in object.keys where field != "editHistory"
                {
                    object[field] = references(object[field]!)

                }
                return object
            }
            if let array = value as? [Any]
            {
                return array.map(references)
            }
            return value
        }

        var raw        = /* Unprocessed source value */
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(preview)) as! [String: Any]
        var collection = raw["collection"] as! [String: Any]     /* Personal collection record */
        var rawLists   = collection["lists"] as! [[String: Any]] /* Raw lists                  */

        for index in rawLists.indices
        {
            let number = rawLists[index]["id"] as! Int /* Local numeric value */

            rawLists[index]["id"] = listMap[number] ?? number

            for field in ["cards", "archivedCards"]
            {
                guard var items = rawLists[index][field] as? [[String: Any]] else
                {
                    continue
                }
                for item in items.indices
                {
                    let number = items[item]["id"] as! Int /* Local numeric value */

                    if let target = cardMap[number]
                    {
                        items[item] = references(items[item]) as! [String: Any]
                        items[item]["id"] = target

                    }
                }

                rawLists[index][field] = items

            }
        }

        collection["lists"] = rawLists

        if let saved = collection["savedCardIDs"] as? [Int]
        {
            collection["savedCardIDs"] = saved.map { cardMap[$0] ?? $0 }.sorted()

        }

        raw["collection"] = collection

        if let days = raw["dayListIDs"] as? [String: Int]
        {
            raw["dayListIDs"] = days.mapValues { listMap[$0] ?? $0 }

        }

        let week = /* Dated Week under consideration */
            try JSONDecoder().decode(DatedPlanningWeek.self, from: JSONSerialization.data(withJSONObject: raw))

        return (week, Set(importantIDs.map { cardMap[$0] ?? $0 }))
    }

    /// @fcn PortableTemplateApplication.importanceForSavedWeek
    /// @brief Remove stale unexported importance markers only for the Week being saved
    /// @details Retains active/archive targets and previously exported selection evidence, including
    ///          locally deleted canonical Cards. Other owners and the retained runtime are untouched
    /// @param[in] week New checked Week snapshot
    /// @param[in] data Current native importance bytes
    /// @param[in] root App container or isolated synthetic container
    /// @return Original bytes when unchanged, otherwise the filtered original entry objects
    /// @throws Malformed/duplicate/unknown source entries or invalid runtime evidence
    static func importanceForSavedWeek(_ week: DatedPlanningWeek, data: Data,
        root: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) throws -> Data
    {
        guard !data.isEmpty else
        {
            return data
        }

        let items = /* Items being processed */
            try JSONDecoder().decode([LibraryImportanceItem].self, from: data)

        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], raw.count == items.count else
        {
            throw PortableEditedExport.Failure.inconsistent
        }

        var seen = Set<String>() /* Identities already encountered */

        for (item, object) in zip(items, raw)
        {
            guard Set(object.keys).isSubset(of: ["collectionID", "cardID", "level"]),
                  (1...5).contains(item.level ?? 1),
                  seen.insert(item.collectionID.uuidString + ":" + String(item.cardID)).inserted else
            {
                throw PortableEditedExport.Failure.inconsistent
            }
        }

        let actual = /* Observed operation result */
            Set(week.collection.lists.flatMap(\.allCards).map(\.id))

        guard items.contains(where: { $0.collectionID == week.id && !actual.contains($0.cardID) }) else
        {
            return data
        }

        let runtime = try PortableRuntimeEvidence.capture(root: root) /* Retained import evidence */

        guard let baseline = runtime["NativeStores.plist"] else
        {
            return data
        }
        guard let stores = try PropertyListSerialization.propertyList(from: baseline, format: nil) as? [String: Any] else
        {
            throw PortableEditedExport.Failure.inconsistent
        }

        let retained = /* State retained for recovery */
            try (stores[LibraryImportanceSelection.key] as? Data).map
        {
            try JSONDecoder().decode([LibraryImportanceItem].self, from: $0)
        } ?? []
        let retainedIDs = /* Retained i ds */
            Set(retained.filter { $0.collectionID == week.id }.map(\.cardID))
        let kept        = zip(items, raw).filter /* Entries retained after filtering */
        {
            $0.0.collectionID != week.id || actual.contains($0.0.cardID) || retainedIDs.contains($0.0.cardID)
        }.map { $0.1 }

        guard kept.count != raw.count else
        {
            return data
        }
        return try JSONSerialization.data(withJSONObject: kept, options: .sortedKeys)
    }

}
