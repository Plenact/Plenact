// --------------------------------------------------------------------------------------------------
// @file       PresentationFixtures.swift
// @brief      Presentation Fixtures
// @details    Verifies related workspace behavior with synthetic fixtures and the shared
//             PlenactBoardDocumentTests helpers. Retains original test identities and checked
//             assertions while separating this coverage from unrelated feature tests
//
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import AVFoundation
import PencilKit
import SwiftUI
import UserNotifications
import XCTest


///
/// Observes Note navigation during hosted presentation tests
///
/// @section    Purpose
///     Retains the navigation path and visible editor identities so tests can assert toolbar
///     visibility through push and pop transitions
///
@MainActor
final class NoteNavigationProbe: ObservableObject
{
    @Published var path: [KanbanCard] = []      /* Filesystem or navigation path */
    var itemToolbars = WorkspaceItemToolbars()

}


///
/// Hosts a Note detail navigation stack for regression testing
///
/// @section    Purpose
///     Reports editor visibility to the probe while using real CardDetailView destinations
///
struct NoteNavigationTestView: View
{
    @ObservedObject var probe: NoteNavigationProbe      /* Probe comparison fixture */

    var body:                  some View        /* Note Navigation Test layout */
    {
        NavigationStack(path: $probe.path)
        {
            Text("Week")
            .navigationDestination(for: KanbanCard.self)
            {
                card in
                CardDetailView(card: card)
            }
        }
        .environment(\.workspaceItemToolbarVisibility)
        {
            toolbar, presentation in
            probe.itemToolbars.update(toolbar, presentation: presentation)
        }
    }
}


///
/// Controls direct-detail presentation in hosted tests
///
/// @section    Purpose
///     Publishes the presentation flag independently of source ownership so return behavior can be
///     asserted
///
@MainActor
final class DirectReturnTestProbe: ObservableObject
{
    @Published var presented = false    /* Presented state flag */
}


///
/// Hosts direct Card routes for return-navigation tests
///
/// @section    Purpose
///     Opens calendar or personal-owner detail content and checks that Back returns to the original
///     presentation rather than invoking home navigation
///
struct DirectReturnTestView: View
{
    @ObservedObject var probe: DirectReturnTestProbe    /* Probe comparison fixture    */
    let owner:                 PersonalCollection       /* Owning collection or Week   */
    let week:                  DatedPlanningWeek?       /* Synthetic week fixture      */
    let listID:                Int                      /* Owner-local List identifier */

    var body:                  some View        /* Direct Return Test layout */
    {
        Text("Origin remains here")
        .fullScreenCover(isPresented: $probe.presented)
        {
            if let week
            {
                PlanningCalendarWeekView(
                    week: week, initialDayID: listID, initialCardID: 701,
                    onLeaveForHome:
                    {
                        XCTFail("Back must not invoke explicit home navigation")
                    })
            }
            else
            {
                PlanningSearchLibraryView(
                    collection: owner, initialListID: listID, initialCardID: 701,
                    onLeaveForHome:
                    {
                        XCTFail("Back must not invoke explicit home navigation")
                    })
            }
        }
    }
}
