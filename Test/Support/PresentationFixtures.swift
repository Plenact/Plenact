// --------------------------------------------------------------------------------------------------
// @file       PresentationFixtures.swift
// @brief      Presentation Fixtures
// @details    Verifies related workspace behavior with synthetic fixtures and the shared
//             PlenactBoardDocumentTests helpers. Retains original test identities and checked
//             assertions while separating this coverage from unrelated feature tests.
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
///     visibility through push and pop transitions.
///
@MainActor
final class NoteNavigationProbe: ObservableObject
{


    @Published var path: [KanbanCard] = []
    var visibleNotes:    Set<UUID> = []
    var noteIsVisible:   Bool
    {
        !visibleNotes.isEmpty
    }

}


///
/// Hosts a Note detail navigation stack for regression testing
///
/// @section    Purpose
///     Reports editor visibility to the probe while using real CardDetailView destinations.
///
struct NoteNavigationTestView: View
{


    @ObservedObject var probe: NoteNavigationProbe
    var body:                  some View
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
        .environment(
            \.workspaceNoteVisibility,
            {
                id, visible in
                if visible
                {
                    probe.visibleNotes.insert(id)
                }
                else
                {
                    probe.visibleNotes.remove(id)
                }

            })
    }

}


///
/// Controls direct-detail presentation in hosted tests
///
/// @section    Purpose
///     Publishes the presentation flag independently of source ownership so return behavior can be
///     asserted.
///
@MainActor
final class DirectReturnTestProbe: ObservableObject
{


    @Published var presented = false
}


///
/// Hosts direct Card routes for return-navigation tests
///
/// @section    Purpose
///     Opens calendar or personal-owner detail content and checks that Back returns to the original
///     presentation rather than invoking home navigation.
///
struct DirectReturnTestView: View
{


    @ObservedObject var probe: DirectReturnTestProbe
    let owner:                 PersonalCollection
    let week:                  DatedPlanningWeek?
    let listID:                Int
    var body:                  some View
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
