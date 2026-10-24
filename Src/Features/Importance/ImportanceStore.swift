// --------------------------------------------------------------------------------------------------
// @file       ImportanceStore.swift
// @brief      Personal owner-qualified importance persistence
// @details    Resolves legacy marks, retains bounded levels, and supplies incremental owner
//             adapters without changing canonical Card content.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Retains an owner-qualified personal importance mark
///
/// @section    Purpose
///     Decodes missing legacy levels as one star and exposes a bounded level without changing the
///     original Card record.
///
struct LibraryImportanceItem: Codable
{


    let collectionID:  UUID
    let cardID:        Int
    var level:         Int? = nil
    var resolvedLevel: Int
    {
        min(5, max(0, level ?? 1))
    }

}


///
/// Persists personal importance levels independently of Card content
///
/// @section    Purpose
///     Resolves legacy marks as one star, clamps levels to zero through five, and adjusts by one
///     deliberate gesture while preserving unrelated owners.
///
enum LibraryImportanceSelection
{


    static let key = "Plenact.LibraryImportant.v1"


    ///
    /// @fcn        LibraryImportanceSelection.cardIDs
    /// @brief      Read important-card IDs for one collection owner
    /// @details    Decodes owner-qualified selections and returns an empty set for absent or malformed data.
    ///
    /// @param[in]  collectionID  UUID of the collection owning the referenced content
    /// @param[in]  data          Encoded input or media bytes
    ///
    /// @return     (Set<Int>) important numeric card IDs belonging to the requested collection
    ///
    static func cardIDs(collectionID: UUID, data: Data) -> Set<Int>
    {

        let items = (try? JSONDecoder().decode([LibraryImportanceItem].self, from: data)) ?? []
        return Set(items.filter
            {
                $0.collectionID == collectionID && $0.resolvedLevel > 0
            } .map(\.cardID))
    }


    ///
    /// @fcn        LibraryImportanceSelection.setting
    /// @brief      Encode a card's requested importance state
    /// @details    Marking retains an existing higher level or begins at one; unmarking removes the
    ///             selection. Returns the original bytes if encoding fails.
    ///
    /// @param[in]  cardID        Numeric card identity within its owner
    /// @param[in]  collectionID  UUID of the collection owning the referenced content
    /// @param[in]  marked        Requested importance state for the owner-qualified card
    /// @param[in]  data          Encoded input or media bytes
    ///
    /// @return     (Data) updated encoded selections, or the original data if encoding fails
    ///
    static func setting(cardID: Int, collectionID: UUID, marked: Bool, data: Data) -> Data
    {

        let previous = level(cardID: cardID, collectionID: collectionID, data: data)
        return settingLevel(
            cardID: cardID, collectionID: collectionID,
            level: marked ? max(1, previous) : 0, data: data)
    }


    ///
    /// @fcn        LibraryImportanceSelection.demoData
    /// @brief      Mark recognized demonstration cards as important
    /// @details    Matches the explicit demonstration-title set across supplied owners and preserves unrelated
    ///             existing selections.
    ///
    /// @param[in]  owners               Canonical collection owners participating in the operation
    /// @param[in]  data                 Encoded input or media bytes
    /// @param[in]  includesAllExamples  Include every non-divider in an explicitly chosen example
    ///
    /// @return     (Data) encoded selections including the recognized supplied demonstration cards
    ///
    /// @note       Only call for freshly created demonstration owners, never on a user's existing weeks.
    ///
    static func demoData(
        in owners: [PersonalCollection], preserving data: Data = Data(), includesAllExamples: Bool = false
    ) -> Data
    {

        let names: Set<String> = [
                        "work", "gym", "dinner", "prepare dinner", "dinner with friends",
                        "call accountant", "call the accountant"
        ]
        var result = data
        for owner in owners
        {

            for card in owner.lists.flatMap(\.cards).filter(
                {
                    !$0.isSectionDivider
                })
            where includesAllExamples
            || names.contains(card.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            {

                let title = card.word.lowercased()
                let demonstrationLevel = demonstrationLevel(for: title)
                result = settingLevel(cardID: card.id, collectionID: owner.id, level: demonstrationLevel, data: result)
            }

        }

        return result
    }


    ///
    /// @fcn        LibraryImportanceSelection.demonstrationLevel(for:)
    /// @brief      Give fresh examples a recognizable range of symbolic attention
    /// @details    Work and Gym demonstrate four and three layers; key calls and dinner show five.
    ///             Other example titles receive a deterministic one-through-five variation.
    ///
    /// @param[in]  title  Newly generated example title
    ///
    /// @return     (Int) demonstration level; never used to rank existing user content
    ///
    static func demonstrationLevel(for title: String) -> Int
    {

        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "work"
        {
            return 4
        }

        if normalized == "gym"
        {
            return 3
        }

        if normalized.contains("accountant") || normalized.contains("dinner")
        {
            return 5
        }

        return normalized.utf8.reduce(0)
        {
            ($0 + Int($1)) % 5
        }
        + 1
    }


    ///
    /// @fcn        LibraryImportanceSelection.contains
    /// @brief      Check an owner-qualified card's importance flag
    /// @details    Matches both collection UUID and card ID, treating malformed selection data as empty.
    ///
    /// @param[in]  cardID        Numeric card identity within its owner
    /// @param[in]  collectionID  UUID of the collection owning the referenced content
    /// @param[in]  data          Encoded input or media bytes
    ///
    /// @return     (Bool) true if both owner UUID and card ID match an important selection
    ///
    static func contains(cardID: Int, collectionID: UUID, data: Data) -> Bool
    {

        level(cardID: cardID, collectionID: collectionID, data: data) > 0
    }


    ///
    /// @fcn        LibraryImportanceSelection.level(cardID:collectionID:data:)
    /// @brief      Resolve bounded importance for one owner-qualified Card
    /// @details    Legacy marks mean one star. Missing and malformed selections mean no stars.
    ///
    /// @param[in]  cardID        Owner-local Card identity
    /// @param[in]  collectionID  Owning collection identity
    /// @param[in]  data          Persisted selections
    ///
    /// @return     (Int) importance from zero through five
    ///
    static func level(cardID: Int, collectionID: UUID, data: Data) -> Int
    {

        let items = (try? JSONDecoder().decode([LibraryImportanceItem].self, from: data)) ?? []
        return items.last
        {
            $0.collectionID == collectionID && $0.cardID == cardID
        }?.resolvedLevel ?? 0
    }


    ///
    /// @fcn        LibraryImportanceSelection.settingLevel(cardID:collectionID:level:data:)
    /// @brief      Persist a bounded importance snapshot for migration, examples, or transfer
    /// @details    Retains every other owner's marks. User-facing controls use adjusting instead.
    ///
    /// @param[in]  cardID        Owner-local Card identity
    /// @param[in]  collectionID  Owning collection identity
    /// @param[in]  level         Snapshot value clamped to zero through five
    /// @param[in]  data          Persisted selections
    ///
    /// @return     (Data) updated selections; zero removes the mark
    ///
    static func settingLevel(cardID: Int, collectionID: UUID, level: Int, data: Data) -> Data
    {

        var items = (try? JSONDecoder().decode([LibraryImportanceItem].self, from: data)) ?? []
        items.removeAll
        {
            $0.collectionID == collectionID && $0.cardID == cardID
        }

        let bounded = min(5, max(0, level))
        if bounded > 0
        {

            items.append(
                LibraryImportanceItem(collectionID: collectionID, cardID: cardID, level: bounded == 1 ? nil : bounded))
        }

        return (try? JSONEncoder().encode(items)) ?? data
    }


    ///
    /// @fcn        LibraryImportanceSelection.adjusting(cardID:collectionID:direction:data:)
    /// @brief      Give or remove exactly one gesture of attention
    /// @details    Only the direction matters; large input values cannot jump multiple levels.
    ///             Five is a ceiling and never wraps to zero.
    ///
    /// @param[in]  cardID        Owner-local Card identity
    /// @param[in]  collectionID  Owning collection identity
    /// @param[in]  direction     Positive increases, negative decreases, zero leaves unchanged
    /// @param[in]  data          Persisted selections
    ///
    /// @return     (Data) selections after at most one step
    ///
    static func adjusting(cardID: Int, collectionID: UUID, direction: Int, data: Data) -> Data
    {

        guard direction != 0 else
        {
            return data
        }

        return settingLevel(
            cardID: cardID, collectionID: collectionID,
            level: level(cardID: cardID, collectionID: collectionID, data: data) + (direction > 0 ? 1 : -1), data: data)
    }

}


///
/// Exposes importance operations for the current owner
///
/// @section    Purpose
///     Supplies presence, marking, level lookup, and incremental adjustment callbacks without
///     giving child views direct storage ownership.
///
struct LibraryImportanceAccess
{


    let contains: (Int) -> Bool
    let set:      (Int, Bool) -> Void
    var level:    (Int) -> Int =
    {
        _ in
        0
    }

    var adjust: (Int, Int) -> Void =
    {
        _, _ in
    }

}


///
/// Injects personal importance controls for a resolved owner
///
/// @section    Purpose
///     Shares the encoded owner-qualified marks with dated Week and Day editors without moving
///     importance into Card content.
///
struct OwnerImportanceControls: ViewModifier
{


    let ownerID: UUID?
    @AppStorage("Plenact.LibraryImportant.v1") private var data = Data()


    ///
    /// @fcn        OwnerImportanceControls.body
    /// @brief      Provide owner-qualified importance actions to descendant views
    /// @details    Installs contains and set closures for the available owner and writes selections through the
    ///             shared encoding helper.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) provide owner-qualified importance actions to descendant views
    ///
    func body(content: Content) -> some View
    {

        content.environment(
            \.libraryImportance,
            ownerID.map
            {
                owner in
                LibraryImportanceAccess(
                    contains:
                    {
                        cardID in
                        LibraryImportanceSelection.contains(cardID: cardID, collectionID: owner, data: data)
                    },
                    set:
                    {
                        cardID, marked in
                        data = LibraryImportanceSelection.setting(
                            cardID: cardID, collectionID: owner, marked: marked, data: data)
                    }, level:
                    {
                        LibraryImportanceSelection.level(cardID: $0, collectionID: owner, data: data)
                    },
                    adjust:
                    {
                        cardID, direction in
                        data = LibraryImportanceSelection.adjusting(
                            cardID: cardID, collectionID: owner, direction: direction, data: data)
                    })
            })
    }

}


///
/// Defines optional importance access in the environment
///
/// @section    Purpose
///     Defaults to no owner adapter so isolated previews and unrelated destinations do not mutate
///     an assumed workspace.
///
struct LibraryImportanceKey: EnvironmentKey
{


    static let defaultValue: LibraryImportanceAccess? = nil
}


///
/// Provides owner-scoped importance through SwiftUI's environment
///
/// @section    Purpose
///     Forwards access through LibraryImportanceKey while leaving persistence and validation with
///     the injected callbacks.
///
extension EnvironmentValues
{


    var libraryImportance: LibraryImportanceAccess?
    {

        get
        {
            self[LibraryImportanceKey.self]
        }

        set
        {
            self[LibraryImportanceKey.self] = newValue
        }

    }

}
