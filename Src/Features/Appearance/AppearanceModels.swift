// --------------------------------------------------------------------------------------------------
// @file       AppearanceModels.swift
// @brief      Persisted appearance choices and inheritance policy
// @details    Defines Board, List, and item overrides separately from content identity, including
//             creation-only defaults and capture text colors.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Defines persisted item accent choices
///
/// @section    Purpose
///     Keeps a compact, Codable palette identity that presentation extensions resolve into standard
///     and header colors.
///
enum ItemAccent: String, CaseIterable, Codable, Sendable
{


    case teal, blue, purple, rose, orange, green, coral, graphite
}


///
/// Defines persisted muted List surface tints
///
/// @section    Purpose
///     Provides stable cases, identities, and user-facing labels, including the inherited default
///     tint.
///
enum KanbanListTint: String, CaseIterable, Identifiable, Codable, Sendable
{


    case neutral, blue, green, orange, red
    var id: String
    {
        rawValue
    }

    var title: String
    {
        self == .neutral ? "Default" : rawValue.capitalized
    }

}


///
/// Defines Board-wide Card detail defaults
///
/// @section    Purpose
///     Keeps compact or detailed Board presentation separate from explicit List-level overrides.
///
enum BoardCardDetail: String, Codable, CaseIterable, Identifiable, Sendable
{


    case compact, detailed
    var id: String
    {
        rawValue
    }

    var title: String
    {
        rawValue.capitalized
    }

}


///
/// Defines built-in collection background choices
///
/// @section    Purpose
///     Identifies procedural, bundled photographic, custom-photo, and plain backgrounds
///     independently of rendering code.
///
enum CollectionBackgroundPreset: String, Codable, CaseIterable, Identifiable, Sendable
{


    case linen, sage, ocean, plum, sandstone, midnight, photo, tabletop, forestPath, sunlitWall, plain
    var id: String
    {
        rawValue
    }

    var title: String
    {

        switch self
        {

        case .linen:
                    "Warm linen"
        case .sage:
                    "Garden sage"
        case .ocean:
                    "Ocean blue"
        case .plum:
                    "Evening plum"
        case .sandstone:
                    "Sandstone"
        case .midnight:
                    "Midnight"
        case .photo:
                    "Your photo"
        case .tabletop:
                    "Ready for today"
        case .forestPath:
                    "The path ahead"
        case .sunlitWall:
                    "Light through the day"
        case .plain:
                    "Plain"
        }

    }

}


///
/// Retains a collection background selection
///
/// @section    Purpose
///     Pairs a preset with an optional photo filename and resolves built-in List defaults without
///     copying attachment data.
///
struct CollectionBackground: Hashable, Codable, Sendable
{


    var preset:        CollectionBackgroundPreset
    var photoFileName: String? = nil


    ///
    /// @fcn        CollectionBackground.defaultListBackground
    /// @brief      Resolve the built-in background for a special list
    /// @details    Uses an explicit override when supplied and otherwise chooses the tutorial background associated
    ///             with the list title.
    ///
    /// @param[in]  title       Display title or proposed title text
    /// @param[in]  overriding  Explicit background override to prefer over the built-in choice
    ///
    /// @return     (CollectionBackground?) explicit or recognized built-in background, or nil for an ordinary list
    ///
    static func defaultListBackground(for title: String, overriding: CollectionBackground? = nil)
    -> CollectionBackground?
    {

        if let overriding
        {
            return overriding
        }

        switch title
        {

        case "On the Table":
            return CollectionBackground(preset: .tabletop)
        case "In the Queue":
            return CollectionBackground(preset: .forestPath)
        case "Scheduled":
            return CollectionBackground(preset: .sunlitWall)
        default:
            return nil
        }

    }


    ///
    /// @fcn        CollectionBackground.isAllowed
    /// @brief      Check whether collection-level imagery is available
    /// @details    Separates ordinary personal collections from dated-week and dated-view contexts before permitting
    ///             a collection background.
    ///
    /// @param[in]  collectionID  UUID of the collection owning the referenced content
    /// @param[in]  datedWeekIDs  Known calendar-week owner identities
    /// @param[in]  isDatedView   Whether the current interface represents a calendar day or week
    ///
    /// @return     (Bool) true for a known personal owner outside dated-week and dated-view contexts
    ///
    static func isAllowed(collectionID: UUID?, datedWeekIDs: Set<UUID>, isDatedView: Bool) -> Bool
    {

        guard let collectionID, !isDatedView else
        {
            return false
        }

        return !datedWeekIDs.contains(collectionID)
    }

}


///
/// Retains Board-wide appearance defaults
///
/// @section    Purpose
///     Stores optional banner, List, Card, background, and text-color overrides; individual Lists
///     and items can retain more specific choices.
///
struct BoardAppearance: Hashable, Codable, Sendable
{


    static let weekStorageKey = "Plenact.WeekAppearance.v1"
    var bannerBackground:     ItemAccent? = nil
    var listBackground:       KanbanListTint? = nil
    var cardBackground:       KanbanListTint? = nil
    var cardDetail:           BoardCardDetail? = nil
    var collectionBackground: CollectionBackground? = nil
    var cardTitleColor:       ListPreviewTextColor? = nil
    var cardTextColor:        ListPreviewTextColor? = nil
    var addItemTextColor:     ProfileColor? = nil
    var subtitleItalic:      Bool? = nil  /* Board default; missing preserves regular subtitles */


    ///
    /// @fcn        BoardAppearance.resolvedSubtitleItalic(card:list:)
    /// @brief      Resolve subtitle styling from the most specific owner override
    /// @details    Explicit false restores regular type even when an ancestor uses italics.
    ///             Missing values inherit Card, List, then Board defaults, ending at regular.
    /// @param[in]  card  Optional Card or Note appearance
    /// @param[in]  list  Optional List appearance
    /// @return     (Bool) whether the subtitle should use italic type
    ///
    func resolvedSubtitleItalic(card: ItemAppearance? = nil, list: ItemAppearance? = nil) -> Bool
    {

        card?.subtitleItalic ?? list?.subtitleItalic ?? subtitleItalic ?? false
    }


    ///
    /// @fcn        BoardAppearance.resolvedAddItemTextColor(list:title:)
    /// @brief      Resolve the inline Add Card field color for one List
    /// @details    Prefers the List override, then Board override. Existing built-in photo Lists
    ///             default to white without rewriting their stored appearance.
    ///
    /// @param[in]  list   Optional List appearance
    /// @param[in]  title  Destination List title used for built-in defaults
    ///
    /// @return     (ProfileColor?) selected color, or nil for the system primary text color
    ///
    func resolvedAddItemTextColor(list: ItemAppearance?, title: String) -> ProfileColor?
    {

        list?.addItemTextColor ?? addItemTextColor
        ?? (["On the Table", "In the Queue", "Scheduled"].contains(title) ? .white : nil)
    }


    ///
    /// @fcn        BoardAppearance.resolvedTitleColor
    /// @brief      Resolve the card preview title color through inheritance
    /// @details    Prefers a card override, then a list override, then the board's configured title color.
    ///
    /// @param[in]  card  Optional card-level appearance overrides
    /// @param[in]  list  Optional list-level appearance overrides
    ///
    /// @return     (ListPreviewTextColor?) most-specific preview title color override, or nil to retain default
    ///             rendering
    ///
    func resolvedTitleColor(card: ItemAppearance?, list: ItemAppearance?) -> ListPreviewTextColor?
    {

        card?.cardTitleColor ?? list?.cardTitleColor ?? cardTitleColor
    }


    ///
    /// @fcn        BoardAppearance.resolvedTextColor
    /// @brief      Resolve supporting preview text color through inheritance
    /// @details    Prefers the most specific card or list override before falling back to the board setting.
    ///
    /// @param[in]  card  Optional card-level appearance overrides
    /// @param[in]  list  Optional list-level appearance overrides
    ///
    /// @return     (ListPreviewTextColor?) most-specific supporting text color override, or nil to retain default
    ///             rendering
    ///
    func resolvedTextColor(card: ItemAppearance?, list: ItemAppearance?) -> ListPreviewTextColor?
    {

        card?.cardTextColor ?? list?.cardTextColor ?? cardTextColor
    }


    ///
    /// @fcn        BoardAppearance.resolvedCardDetail
    /// @brief      Resolve compact or detailed preview presentation
    /// @details    Combines card and list overrides with the board setting and the supplied fallback detail mode.
    ///
    /// @param[in]  card      Optional card-level appearance overrides
    /// @param[in]  list      Optional list-level appearance overrides
    /// @param[in]  fallback  Presentation to use when no explicit override applies
    ///
    /// @return     (BoardCardDetail) card, list, or board detail override, falling back to the caller's existing
    ///             layout
    ///
    /// @note       Explicit item choices override List, then Board; nil preserves the caller's existing layout.
    ///
    func resolvedCardDetail(card: ItemAppearance?, list: ItemAppearance?, fallback: BoardCardDetail = .detailed)
    -> BoardCardDetail
    {

        card?.cardDetail ?? list?.cardDetail ?? cardDetail ?? fallback
    }


    ///
    /// @fcn        BoardAppearance.resolved
    /// @brief      Fill missing item backgrounds from board appearance
    /// @details    Returns an appearance copy with missing banner and list backgrounds inherited from the board;
    ///             explicit values and other item fields are preserved.
    ///
    /// @param[in]  appearance  Optional or explicit appearance overrides supplied by the caller
    ///
    /// @return     (ItemAppearance) appearance with missing banner and list backgrounds filled from board settings
    ///
    func resolved(_ appearance: ItemAppearance?) -> ItemAppearance
    {

        var result = appearance ?? ItemAppearance()
        result.background = result.background ?? bannerBackground
        result.listBackground = result.listBackground ?? listBackground
        return result
    }


    ///
    /// @fcn        BoardAppearance.inheritingLists
    /// @brief      Return lists whose surface and text styling inherits from the board
    /// @details    Clears list banner, list background, and preview text-color overrides while preserving card-level
    ///             overrides, list content, and other appearance fields. Clears subtitle style overrides as well.
    ///
    /// @param[in]  lists  Lists participating in the operation
    ///
    /// @return     ([KanbanList]) lists with surface and preview text-color overrides cleared, preserving their order
    ///             and content
    ///
    static func inheritingLists(_ lists: [KanbanList]) -> [KanbanList]
    {

        lists.map
        {
            list in
            var updated = list
            if var appearance = updated.appearance
            {

                appearance.background = nil
                appearance.listBackground = nil
                appearance.cardTitleColor = nil
                appearance.cardTextColor = nil
                appearance.addItemTextColor = nil
                appearance.subtitleItalic = nil
                updated.appearance = appearance.isEmpty ? nil : appearance
            }

            return updated
        }

    }


    ///
    /// @fcn        BoardAppearance.decodeWeek
    /// @brief      Decode the stored current-week board appearance
    /// @details    Uses the default appearance for empty data and propagates decoding errors for malformed nonempty
    ///             storage.
    ///
    /// @param[in]  data  Encoded input or media bytes
    ///
    /// @return     (BoardAppearance) decoded board appearance, or default appearance for empty data
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    static func decodeWeek(_ data: Data) throws -> BoardAppearance
    {

        data.isEmpty ? BoardAppearance() : try JSONDecoder().decode(BoardAppearance.self, from: data)
    }

}


///
/// Defines adaptive preview text color choices
///
/// @section    Purpose
///     Persists named palette values whose light and dark rendering is resolved by presentation
///     extensions.
///
enum ListPreviewTextColor: String, Codable, CaseIterable, Identifiable, Sendable
{


    case graphite, blue, teal, green, plum, rose, amber
    var id: String
    {
        rawValue
    }

    var title: String
    {
        rawValue.capitalized
    }

}


///
/// Selects a focused List's presentation mode
///
/// @section    Purpose
///     Switches between Card previews and the denser Note List layout without converting the
///     underlying records.
///
enum SingleListViewMode: String, CaseIterable, Codable, Sendable, Identifiable
{


    case cards, noteList
    var id: String
    {
        rawValue
    }

    var title: String
    {
        self == .cards ? "Cards" : "Note List"
    }

}


///
/// Retains per-item and per-List appearance overrides
///
/// @section    Purpose
///     Keeps colors, icon, collapse state, layout, and display preferences optional so absent
///     values continue to inherit defaults.
///
struct ItemAppearance: Hashable, Codable, Sendable
{


    var accent:                        ItemAccent?
    var icon:                          PersonalCollectionIcon?
    var background:                    ItemAccent? = nil
    var listBackground:                KanbanListTint? = nil
    var cardBackground:                KanbanListTint? = nil
    var cardTitleColor:                ListPreviewTextColor? = nil
    var cardTextColor:                 ListPreviewTextColor? = nil
    var addItemTextColor:              ProfileColor? = nil
    var sectionCollapsed:              Bool? = nil
    var hideEmptySubtitle:             Bool? = nil
    var subtitleItalic:               Bool? = nil  /* nil inherits; false explicitly requests regular type */
    var cardDetail:                    BoardCardDetail? = nil
    var listViewMode:                  SingleListViewMode? = nil
    var iconColor:                     ProfileColor? = nil
    var showsIconInHeader:             Bool? = nil
    var listBackgroundOpacity:         Double? = nil
    var resolvedListBackgroundOpacity: Double
    {

        guard let value = listBackgroundOpacity, value.isFinite else
        {
            return 1
        }

        return min(1, max(0, value))
    }


    ///
    /// @fcn        ItemAppearance.hidesSubtitle
    /// @brief      Decide whether an empty subtitle should be suppressed
    /// @details    Returns true only when hideEmptySubtitle is explicitly enabled and the supplied text is blank
    ///             after trimming whitespace.
    ///
    /// @param[in]  text  Attributed or plain text to restore or display
    ///
    /// @return     (Bool) true only for a blank subtitle with hideEmptySubtitle explicitly enabled
    ///
    func hidesSubtitle(_ text: String) -> Bool
    {

        hideEmptySubtitle == true && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }


    var isEmpty: Bool
    {

        sectionCollapsed != true && cardBackground == nil && listViewMode == nil && iconColor == nil
        && listBackgroundOpacity == nil && showsIconInHeader == nil && accent == nil && icon == nil
        && background == nil && listBackground == nil && hideEmptySubtitle != true && cardDetail == nil
        && cardTitleColor == nil && cardTextColor == nil && addItemTextColor == nil && subtitleItalic == nil
    }

}


///
/// Applies creation-only random Card color preferences
///
/// @section    Purpose
///     Chooses persisted editable appearance fields for new Cards while leaving existing records,
///     Notes, and dividers unchanged.
///
enum NewCardAppearanceDefaults
{


    static let headerPalette:     [ItemAccent] = [.teal, .blue, .purple, .rose, .orange, .green, .coral]
    static let backgroundPalette: [KanbanListTint] = [.blue, .green, .orange, .red]


    ///
    /// @fcn        NewCardAppearanceDefaults.apply
    /// @brief      Apply configured creation appearance to a new card
    /// @details    Mutates only the new card using the user's creation preferences rather than rewriting existing
    ///             cards.
    ///
    /// @param[in,out]  card         Card or note being inspected or changed
    /// @param[in]      preferences  User display and creation preferences
    ///
    /// @return     (Void) no return value
    ///
    static func apply(to card: inout KanbanCard, preferences: LocalProfilePreferences = PlanPreferencesStore.load())
    {

        guard card.presentation == .card, !card.isSectionDivider,
        preferences.randomizesNewCardHeaders || preferences.randomizesNewCardBackgrounds
        else
        {
            return
        }

        var appearance = card.appearance ?? ItemAppearance()
        if preferences.randomizesNewCardHeaders && appearance.background == nil
        {

            appearance.background = headerPalette.randomElement()
        }

        if preferences.randomizesNewCardBackgrounds && appearance.cardBackground == nil
        {

            appearance.cardBackground = backgroundPalette.randomElement()
        }

        card.appearance = appearance.isEmpty ? nil : appearance
    }

}
