// --------------------------------------------------------------------------------------------------
// @file       WorkspaceSearchView.swift
// @brief      Common workspace search presentation
// @details    Shares filters and recent search behavior and opens resolved owner destinations
//             through existing navigation callbacks.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import CryptoKit
import PhotosUI
import Speech
import SwiftUI


/// Searches card content in the local Board and opens results in their existing lists.
///
/// Searches the local Board and presents matching destinations
///
/// @section    Purpose
///     Keep query, filter, recent-history, and result navigation state in one sheet
///
struct TodaySearchView: View
{


    let lists:           [KanbanList]        /* Current locally stored Board snapshot    */
    let onOpenBoardList: (Int) -> Void       /* Navigate to a result's containing list   */
    let onOpenBoardCard: (Int, Int) -> Void  /* Route to a Week card by list/card IDs    */
    let onArchiveCard:   (Int) -> Void       /* Canonical Week archive                   */
    let onDeleteCard:    (Int) -> Bool       /* Confirmed canonical Week deletion result */
    let onArchiveList:   (Int) -> Void       /* Canonical Week list archive              */
    let onDeleteList:    (Int) -> Bool       /* Confirmed canonical list deletion result */

    var resultProvider: ((String, TodaySearchScope, LabelLibrary) -> [TodaySearchResult])? = nil
    var onSelectResult: ((TodaySearchResult) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss                   /* Close the search sheet             */
    @FocusState private var searchFieldFocused: Bool              /* Search field focus state           */
    @State private var query = ""                                 /* User-entered search text           */
    @State private var scope: TodaySearchScope = .all             /* Selected local-search scope        */
    @State private var recentSearches = RecentSearchStore.load()  /* Device-local recent terms          */
    @State private var labelLibrary = LabelLibraryStore.load()    /* Definitions used for label matches */


    ///
    /// @fcn        TodaySearchView.results
    /// @brief      Resolve matches for the current query and selected scope
    /// @details    Delegates to the local search index using the supplied Board and label snapshots
    ///
    /// @return     ([TodaySearchResult]) current display-order matches
    /// @post       Search history and Board state are unchanged
    ///
    private var results: [TodaySearchResult]
    {  /* Matches for the current query and scope */

        resultProvider?(query, scope, labelLibrary)
        ?? TodaySearchIndex.results(query: query, scope: scope, lists: lists, library: labelLibrary)
    }


    ///
    /// @fcn        TodaySearchView.rememberSearch()
    /// @brief      Persist the current nonblank query and refresh displayed history
    /// @details    Uses the shared recent-search store's trimming, deduplication, and ten-term
    ///             limit
    ///
    /// @return     (Void) replaces recentSearches with the store result
    ///
    /// @post       Blank queries leave stored history intact
    ///
    private func rememberSearch()
    {


        recentSearches = RecentSearchStore.remember(query)
    }


    ///
    /// @fcn        TodaySearchView.recentSearchList
    /// @brief      Display reusable recent terms with a clear-history action
    /// @details    Choosing a term sets the query, refreshes its history position, and releases
    ///             field focus; Clear removes both persisted and displayed history
    ///
    /// @return     (some View) plain recent-search list
    /// @post       Interactions affect search state only, not Board content
    ///
    private var recentSearchList: some View
    {  /* Previously entered queries available for reuse */

        List
        {

            Section
            {

                ForEach(recentSearches, id: \.self)
                {
                    search in
                    Button
                    {

                        query = search
                        rememberSearch()
                        searchFieldFocused = false
                    }
                    label:
                    {

                        Label(search, systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    .buttonStyle(.plain)
                }

            }
            header:
            {

                HStack
                {

                    Text("Recent searches")
                    Spacer()
                    Button("Clear")
                    {

                        RecentSearchStore.clear()
                        recentSearches = []
                    }

                    .accessibilityLabel("Clear recent searches")
                }

            }

        }

        .listStyle(.plain)
    }


    ///
    /// @fcn        TodaySearchView.body
    /// @brief      Present local Board search, scope controls, and matching destinations
    /// @details    Switches between history, empty states, and indexed matches.
    ///             Result selection remembers the query, routes to its list/card, then dismisses
    ///
    /// @return     (some View) large-sheet search navigation surface
    /// @post       Submission, result selection, and disappearance remember nonblank queries;
    ///             search alone does not modify Board content
    ///
    var body: some View
    {  /* Board search controls and matching destinations */


        NavigationStack
        {

            VStack(spacing: 0)
            {

                HStack(spacing: 10)
                {

                    Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                    TextField(resultProvider == nil ? "Find in your Week" : "Find in Plenact", text: $query)
                    .focused($searchFieldFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Search Plenact")
                    .onSubmit
                    {

                        rememberSearch()
                        searchFieldFocused = false
                    }


                    if !query.isEmpty
                    {


                        Button
                        {

                            query = ""
                            searchFieldFocused = true
                        }
                        label:
                        {

                            Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }

                }

                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.top)
                Text(
                    resultProvider == nil
                    ? "Your Week · Cards, notes, and lists" : "Your Plenact · Today, Week, and Plans"
                )
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 12)

                Text("Search by").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.bottom, 6)
                Picker("Search by", selection: $scope)
                {

                    ForEach(TodaySearchScope.allCases)
                    {
                        scope in
                        Text(scope.rawValue).tag(scope)
                    }

                }

                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 12)

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {


                    if recentSearches.isEmpty
                    {


                        searchEmptyState(title: "No recent searches", detail: "")
                    }
                    else
                    {

                        recentSearchList
                    }

                }
                else if results.isEmpty
                {

                    searchEmptyState(title: "No results", detail: "Try another word or phrase.")
                }
                else
                {

                    List(results)
                    {
                        result in
                        Button
                        {

                            rememberSearch()

                            if let onSelectResult
                            {

                                onSelectResult(result)
                            }
                            else if let cardID = result.cardID
                            {  /* Matching card identity for direct navigation */


                                onOpenBoardCard(result.listID, cardID)
                            }
                            else
                            {

                                onOpenBoardList(result.listID)
                            }


                            if onSelectResult == nil
                            {
                                dismiss()
                            }

                        }
                        label:
                        {

                            VStack(alignment: .leading, spacing: 4)
                            {

                                Text(result.cardTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)

                                Text(
                                    [result.ownerTitle, result.listTitle, result.detail.isEmpty ? nil : result.detail]
                                    .compactMap
                                    {
                                        $0
                                    } .joined(separator: " · ")
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }

                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 5)
                        }

                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .modifier(
                            SharedSearchLifecycleActions(
                                enabled: resultProvider == nil,
                                title: result.cardTitle, kind: result.cardID == nil ? "List" : "Card",
                                onArchive:
                                {

                                    if let id = result.cardID
                                    {  /* Card identity targeted by the search action */


                                        onArchiveCard(id)
                                    }
                                    else
                                    {

                                        onArchiveList(result.listID)
                                    }

                                },
                                onDelete:
                                {

                                    if let id = result.cardID
                                    {  /* Card identity targeted by the search action */


                                        return onDeleteCard(id)
                                    }

                                    return onDeleteList(result.listID)
                                }
                            ))
                    }

                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

            }

            .background
            {
                Color(.systemBackground)
                StudioWorkspaceBackground(destination: .search)
            }
            .navigationTitle(resultProvider == nil ? "Search your Week" : "Search Plenact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Cancel")
                    {

                        dismiss()
                    }

                }

            }

        }

        .presentationDetents([.large])
        .onDisappear
        {
            rememberSearch()
        }

    }


    ///
    /// @fcn        TodaySearchView.searchEmptyState(title:detail:)
    /// @brief      Render a centered search explanation
    /// @details    Uses a search symbol, heading, and multiline supporting text for empty states
    ///
    /// @param[in]  title   Empty-state heading
    /// @param[in]  detail  Supporting explanation, which may be empty
    ///
    /// @return     (some View) noninteractive empty-state content
    ///
    /// @post       Query, focus, and history remain unchanged
    ///
    private func searchEmptyState(title: String, detail: String) -> some View
    {


        VStack(spacing: 10)
        {

            Image(systemName: "magnifyingglass")
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
            Text(title)
            .font(.headline)
            Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}


///
/// Adds lifecycle actions to shared-search contexts
///
/// @section    Purpose
///     Keeps snapshot-only actions where valid and resolves an owning workspace before exposing
///     mutable source operations.
///
struct SharedSearchLifecycleActions: ViewModifier
{


    let enabled:   Bool
    let title:     String
    let kind:      String
    let onArchive: () -> Void
    let onDelete:  () -> Bool


    ///
    /// @fcn        SharedSearchLifecycleActions.body
    /// @brief      Attach lifecycle controls when shared search permits them
    /// @details    Installs archive and delete handling only when enabled; otherwise preserves the supplied content.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) attach lifecycle controls when shared search permits them
    ///
    func body(content: Content) -> some View
    {

        if enabled
        {

            content.modifier(
                ContentLifecycleActions(title: title, kind: kind, onArchive: onArchive, onDelete: onDelete))
        }
        else
        {

            content
        }

    }

}


///
/// Presents the common workspace search interface
///
/// @section    Purpose
///     Uses the same Today search scopes and recent history from every toolbar and delegates result
///     navigation to its owner.
///
struct PlanningSharedSearchPresentation: ViewModifier
{


    @Binding var isPresented: Bool
    var onLeaveForHome:       () -> Void =
    {

    }

    @Environment(\.planningCalendarAccess) private var access
    @State private var route: PlanningSearchRoute?


    ///
    /// @fcn        PlanningSharedSearchPresentation.body
    /// @brief      Present workspace-wide search and its selected route
    /// @details    Supplies calendar-backed results and routes chosen matches through the shared destination
    ///             presentation rather than an isolated search copy.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) present workspace-wide search and its selected route
    ///
    func body(content: Content) -> some View
    {

        content
        .sheet(isPresented: $isPresented)
        {

            TodaySearchView(
                lists: [], onOpenBoardList:
                {
                    _ in
                }, onOpenBoardCard:
                {
                    _, _ in
                },
                onArchiveCard:
                {
                    _ in
                }, onDeleteCard:
                {
                    _ in
                    false
                }, onArchiveList:
                {
                    _ in
                },
                onDeleteList:
                {
                    _ in
                    false
                },
                resultProvider:
                {
                    query, scope, labels in
                    guard let access else
                    {
                        return []
                    }

                    return PlanningSharedSearchIndex.results(
                        query: query, scope: scope, access: access, labels: labels)
                }, onSelectResult:
                {
                    result in
                    route = PlanningSearchRoute(result: result)
                }
            )
            // Keep Search alive beneath its result, preserving query, scope, and scroll.
            .fullScreenCover(item: $route)
            {
                route in
                if let key = route.result.weekKey,
                let week = access?.document.weeks.first(where:
                    {
                        $0.startKey == key
                    })
                {

                    PlanningCalendarWeekView(
                        week: week,
                        initialDayID: route.result.listID, initialCardID: route.result.cardID,
                        onLeaveForHome:
                        {

                            self.route = nil;
                            isPresented = false;
                            onLeaveForHome()
                        })
                }
                else if let collection = access?.library.first(where:
                    {
                        $0.id == route.result.ownerID
                    })
                {

                    PlanningSearchLibraryView(
                        collection: collection, initialListID: route.result.listID,
                        initialCardID: route.result.cardID,
                        onLeaveForHome:
                        {

                            self.route = nil;
                            isPresented = false;
                            onLeaveForHome()
                        })
                }

            }

        }

    }

}
