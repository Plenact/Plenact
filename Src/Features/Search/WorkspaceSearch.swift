// --------------------------------------------------------------------------------------------------
// @file       WorkspaceSearch.swift
// @brief      Shared matching, scopes, and owner provenance
// @details    Searches canonical workspace records and carries enough owner context to
//             disambiguate local numeric identifiers.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import CryptoKit
import PhotosUI
import Speech
import SwiftUI


///
/// Identifies a search match and its navigation provenance
///
/// @section    Purpose
///     Carries the matching list or card alongside optional collection and week ownership so local
///     numeric identities remain unambiguous.
///
struct TodaySearchResult: Identifiable
{


    let listID:     Int     /* Board list opened when this result is selected */
    let cardID:     Int?    /* Stable card identity, or nil for a list result */
    let cardTitle:  String  /* Matching card title                            */
    let listTitle:  String  /* Containing list title                          */
    let detail:     String  /* Supporting detail shown under the title        */
    var ownerID:    UUID? = nil
    var weekKey:    String? = nil
    var ownerTitle: String? = nil


    ///
    /// @fcn        TodaySearchResult.id
    /// @brief      Identify a result within its containing list
    /// @details    Combines the list ID with a card ID or a list-result marker
    ///
    /// @return     (String) composite result identity
    /// @post       Result contents remain unchanged
    ///
    var id: String
    {

                "\(ownerID?.uuidString ?? "week"):\(listID):\(cardID.map(String.init) ?? "list")"
    }  /* Composite search-result identity */

}


///
/// Limits local search to supported kinds of Board content
///
/// @section    Purpose
///     Supply stable picker choices for the Today search screen
///
enum TodaySearchScope: String, CaseIterable, Identifiable
{


    case all = "All"
    case boards = "Lists"
    case labels = "Labels"
    case users = "Users"

    ///
    /// @fcn        TodaySearchScope.id
    /// @brief      Identify a selectable local-search scope
    /// @details    Uses the display raw value for segmented-picker identity
    ///
    /// @return     (String) scope raw value
    /// @post       The selected scope is unchanged
    ///
    var id: String
    {
        rawValue
    }  /* Stable search-scope identity */

}


///
/// Searches a supplied local Board snapshot and returns matching destinations
///
/// @section    Purpose
///     Keep query matching independent from search presentation and persistence
///
enum TodaySearchIndex
{


    ///
    /// @fcn        TodaySearchIndex.results(query:scope:lists:library:)
    /// @brief      Search a supplied local Board snapshot without modifying it
    /// @details    Trims the query and uses localized-standard substring matching. Boards scope
    ///             matches list titles/subtitles; other scopes match non-divider cards by
    ///             label/category, member names, or combined card/checklist/comment content
    ///
    /// @param[in]  query    Search text; blank input yields no results
    /// @param[in]  scope    Fields and result kind to search
    /// @param[in]  lists    Snapshot to traverse in list/card order
    /// @param[in]  library  Definitions resolving assigned label and category names
    ///
    /// @return     ([TodaySearchResult]) matching list or card results with navigation provenance
    ///
    /// @post       No archive filtering, storage writes, ranking, or network requests are performed
    /// @note       Callers supply the intended list partition; archivedCards are not searched
    ///
    static func results(query: String, scope: TodaySearchScope, lists: [KanbanList], library: LabelLibrary)
    -> [TodaySearchResult]
    {


        let term = query.trimmingCharacters(
            in: .whitespacesAndNewlines) /* Nonblank text matched against the chosen scope */

        guard !term.isEmpty else
        {


            return []
        }


        if scope == .boards
        {


            return lists.compactMap
            {
                list in
                guard list.title.localizedStandardContains(term) || list.subtitle.localizedStandardContains(term) else
                {


                    return nil
                }


                return TodaySearchResult(
                    listID: list.id, cardID: nil, cardTitle: list.title, listTitle: list.title,
                    detail: "\(list.cards.filter { !$0.isSectionDivider } .count) cards"
                )
            }

        }


        return lists.flatMap
        {
            list in
            list.cards.compactMap
            {
                card -> TodaySearchResult? in
                guard !card.isSectionDivider else
                {


                    return nil
                }


                let checklistText = card.checklists.flatMap
                {

                    [$0.title] + $0.items.map(\.title)
                }  /* Searchable checklist and action titles      */

                let commentText = card.comments.flatMap
                {

                    [$0.author, PlanRichText.plain($0.body)]
                }  /* Searchable discussion authors and content   */

                let users = card.members.map(\.displayName) /* Searchable assignee names                   */
                let labels = library.labels.filter
                {

                    card.labelIDs.contains($0.id)
                }  /* Definitions of labels assigned to this card */

                let labelText = labels.flatMap
                {
                label in /* Searchable label and category names         */
                    [label.name] + library.categories.filter
                    {
                        $0.id == label.categoryID
                    } .map(\.name)
                }


                let searchableText: [String] /* Card fields selected by the search scope */

                switch scope
                {


                case .labels:
                    searchableText = labelText
                case .users:
                    searchableText = users
                case .all:
                    searchableText =
                    [
                        list.title, card.word, PlanRichText.plain(card.descriptionOverride ?? ""),
                        card.subtitleOverride ?? ""
                    ]
                    + checklistText + commentText + users + labelText
                case .boards:
                    searchableText = []
                }


                guard
                searchableText.contains(where:
                    {


                        $0.localizedStandardContains(term)
                    })
                else
                {


                    return nil
                }


                let detail: String /* Supporting text displayed beneath a matching card */

                switch scope
                {


                case .labels:
                    detail = labels.map(\.name).joined(separator: ", ")
                case .users:
                    detail = users.joined(separator: ", ")
                default:
                    detail =
                    [card.subtitleOverride, card.descriptionOverride.map
                        {
                            PlanRichText.plain($0)
                        }].compactMap
                    {

                        $0
                    }
                    .first(where:
                        {
                            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        })
                    ?? checklistText.first ?? ""
                }


                return TodaySearchResult(
                    listID: list.id, cardID: card.id, cardTitle: card.word, listTitle: list.title, detail: detail
                )
            }

        }

    }

}


///
/// Searches active personal collections
///
/// @section    Purpose
///     Uses shared text matching and annotates matches with collection provenance so navigation
///     resolves the correct owner.
///
enum LibrarySearchIndex
{


    ///
    /// @fcn        LibrarySearchIndex.results
    /// @brief      Search active lists across personal collections
    /// @details    Annotates shared search matches with their collection UUID and title so equal numeric card IDs
    ///             remain owner-qualified.
    ///
    /// @param[in]  query        User-entered search text
    /// @param[in]  collections  Personal collection values available to the operation
    /// @param[in]  labels       Label catalog used to resolve stored label IDs
    ///
    /// @return     ([TodaySearchResult]) owner-qualified personal-collection matches in the shared search order
    ///
    static func results(query: String, collections: [PersonalCollection], labels: LabelLibrary) -> [TodaySearchResult]
    {

        collections.filter(\.isActive).flatMap
        {
            collection in
            TodaySearchIndex.results(
                query: query, scope: .all, lists: collection.lists.filter
                {
                    !$0.isArchived
                }, library: labels
            ).map
            {
                match in
                var result = match
                result.ownerID = collection.id
                result.ownerTitle = collection.title
                return result
            }

        }

    }

}


///
/// Builds owner-qualified shared workspace search results
///
/// @section    Purpose
///     Reuses Today matching and filters while carrying provenance that disambiguates Board-local
///     numeric identities.
///
enum PlanningSharedSearchIndex
{


    ///
    /// @fcn        PlanningSharedSearchIndex.results
    /// @brief      Search retained weeks and active personal collections
    /// @details    Runs the shared search over active lists and annotates each match with its owner, week key, and
    ///             location title for later navigation.
    ///
    /// @param[in]  query   User-entered search text
    /// @param[in]  scope   Search scope restricting the kind of shared results
    /// @param[in]  access  Checked calendar and personal-owner access callbacks
    /// @param[in]  labels  Label catalog used to resolve stored label IDs
    ///
    /// @return     ([TodaySearchResult]) calendar and Library matches annotated with owner and week navigation
    ///             metadata
    ///
    static func results(
        query: String, scope: TodaySearchScope, access: PlanningCalendarAccess,
        labels: LabelLibrary
    ) -> [TodaySearchResult]
    {

        let sources: [(UUID, String?, String, [KanbanList])] =
        access.document.weeks.map
        {

            (
                $0.id, $0.startKey,
                $0.startKey == access.document.currentWeekKey ? "This week · \($0.rangeTitle)" : $0.rangeTitle,
                $0.collection.lists
            )
        }
        + access.library.filter(\.isActive).map
        {
            ($0.id, nil, "Plans · \($0.title)", $0.lists)
        }

        return sources.flatMap
        {
            ownerID, weekKey, title, lists in
            TodaySearchIndex.results(
                query: query, scope: scope, lists: lists.filter
                {
                    !$0.isArchived
                }, library: labels
            ).map
            {
                match in
                var result = match
                result.ownerID = ownerID;
                result.weekKey = weekKey;
                result.ownerTitle = title
                return result
            }

        }

    }

}
