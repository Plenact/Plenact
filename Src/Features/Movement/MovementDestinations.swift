// --------------------------------------------------------------------------------------------------
// @file       MovementDestinations.swift
// @brief      Owner-qualified Card and section destination controls
// @details    Exposes checked movement capabilities and resolves List or dated destinations
//             independently of the initiating view
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Exposes cross-owner Card and section movement operations
///
/// @section    Purpose
///     Carries available destinations and optional checked callbacks for List or dated movement
///     while leaving storage with the workspace owner
///
struct CardMovementAccess
{


    var destinations:      [CardMoveDestination]                                     = /* Available operation destinations */
        []
    var move:              ((KanbanCard, UUID?, CardMoveDestination) -> Bool)?       = /* Move callback */
        nil
    var moveToDate:        ((KanbanCard, UUID?, Date) -> Bool)?                      = /* Move to date callback */
        nil
    var moveSection:       ((KanbanCard, UUID?, CardMoveDestination, Bool) -> Bool)? = /* Move section callback */
        nil
    var moveSectionToDate: ((KanbanCard, UUID?, Date, Bool) -> Bool)?                = /* Move section to date callback */
        nil

}


///
/// Defines default movement access in the environment
///
/// @section    Purpose
///     Uses an empty adapter so detached menus have no writable destinations or implicit mutation
///     callbacks
///
struct CardMovementAccessKey: EnvironmentKey
{


    static let defaultValue = CardMovementAccess() /* Fallback environment value */

}


///
/// Defines the current movement-source owner identity
///
/// @section    Purpose
///     Defaults to nil for contexts whose ownership must be resolved by the enclosing workspace
///     route
///
struct CardMovementSourceKey: EnvironmentKey
{


    static let defaultValue: UUID? = nil /* Fallback environment value */

}


///
/// Exposes movement callbacks and source provenance
///
/// @section    Purpose
///     Keeps destination capabilities separate from the current owner's identity for Card and
///     section actions
///
extension EnvironmentValues
{


    var cardMovementAccess: CardMovementAccess /* Card movement access */
    {

        get
        {
            self[CardMovementAccessKey.self]
        }

        set
        {

            self[CardMovementAccessKey.self] = newValue

        }

    }

    var cardMovementSource: UUID? /* Card movement source */
    {

        get
        {
            self[CardMovementSourceKey.self]
        }

        set
        {

            self[CardMovementSourceKey.self] = newValue

        }

    }

}


///
/// Selects a destination for an entire named section
///
/// @section    Purpose
///     Supports List and dated destinations with optional date shifting and reports completion only
///     after the injected move succeeds
///
struct SectionMoveSheet: View
{


    let heading: KanbanCard   /* Section heading text */
    var onMoved: () -> Void = /* Moved callback       */
    {

    }

    @Environment(\.cardMovementAccess) private var movement /* Owner-qualified transfer context */
    @Environment(\.cardMovementSource) private var source /* Source value for this operation */
    @Environment(\.planningCalendarAccess) private var planning /* Planning store projection */
    @Environment(\.dismiss) private var dismiss /* Close the current presentation */
    @State private var chooseDate = false /* Choose date */
    @State private var date       = Date() /* Date used by this operation */
    @State private var destination: CardMoveDestination? /* Destination for the operation */
    @State private var shiftDates = false /* Shift dates */
    @State private var failed     = false /* Rejected operation result */

    private var destinations: [CardMoveDestination] /* Available operation destinations */
    {

        movement.destinations.filter
        {
            item in

            let current = planning?.document.weeks.first /* Current operation snapshot */
            {
                $0.startKey == planning?.document.currentWeekKey
            }?.id
            let ownerID  = item.collectionID ?? current /* Record owner identifier */
            let sourceID = source ?? current            /* Source ID               */

            guard ownerID == sourceID else
            {
                return true
            }

            let owner = /* Owning collection or Week */
            planning?.document.weeks.first
            {
                $0.id == sourceID
            }?.collection
            ?? planning?.library.first
            {
                $0.id == sourceID
            }

            return owner?.lists.first(where:
                {
                    $0.id == item.listID
                })?.cards.contains(where:
                {

                    $0.id == heading.id && $0.createdAt == heading.createdAt
                }) != true
        }

    }

    private var destinationDay: Date? /* Destination day */
    {

        guard let destination, let document = planning?.document else
        {
            return nil
        }

        let owner = destination.collectionID ?? document.weeks.first /* Owning collection or Week */
        {
            $0.startKey == document.currentWeekKey
        }?.id

        return document.weeks.first
        {
            $0.id == owner
        }?.dayListIDs.first
        {
            $0.value == destination.listID
        }
        .flatMap
        {
            PlanningDate.date($0.key, calendar: document.calendar)
        }

    }

    var body: some View /* Section Move layout */
    {

        NavigationStack
        {

            Form
            {

                Section
                {

                    Text(
                                                            "Move “" + (heading.sectionHeading ?? "Section")
                                                            + "” and everything beneath it up to the next named section.")
                }

                Section("Destination")
                {

                    Toggle("Choose another day", isOn: $chooseDate)
                    if chooseDate
                    {

                        DatePicker("Day", selection: $date, displayedComponents: .date).datePickerStyle(.graphical)
                    }
                    else
                    {

                        Picker("List", selection: $destination)
                        {

                            Text("Choose a list").tag(CardMoveDestination?.none)
                            ForEach(["Week", "Calendar", "Plans"], id: \.self)
                            {
                                group in
                                Section(group)
                                {

                                    ForEach(destinations.filter
                                        {
                                            $0.group == group
                                        })
                                    {
                                        item in
                                        Text(item.title).tag(Optional(item))
                                    }

                                }

                            }

                        }

                    }

                }

                if chooseDate || destinationDay != nil
                {

                    Section("Dates")
                    {

                        Toggle("Shift dates to destination day", isOn: $shiftDates)
                        Text(
                            shiftDates
                            ? "Dated items move by the same number of days. Time-only schedules keep their clock times. From a general list, the earliest dated item anchors the shift."
                            : "Keep all existing dates and times."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }

                Section
                {

                    Text("An Undo action remains available after moving, including when you navigate to another view.")
                    .font(.footnote).foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Move section")
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

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Move")
                    {

                        let succeeded: Bool /* Successful operation result */

                        if chooseDate
                        {

                            succeeded = movement.moveSectionToDate?(heading, source, date, shiftDates) == true

                        }
                        else if let destination
                        {

                            succeeded =
                            movement.moveSection?(heading, source, destination, shiftDates && destinationDay != nil)
                            == true

                        }
                        else
                        {

                            return
                        }

                        if succeeded
                        {
                            dismiss();
                            onMoved()
                        }
                        else
                        {

                            failed = true

                        }

                    } .disabled(!chooseDate && destination == nil)
                }

            }
            .alert("Section couldn't be moved", isPresented: $failed)
            {

                Button("OK", role: .cancel)
                {

                }

            }
            message:
            {

                Text("Your content has been retained. Check the destination and try again.")
            }

        }

    }

}


///
/// Presents owner-qualified movement destinations for a Card
///
/// @section    Purpose
///     Offers List, dated, and section routes through injected access and delegates successful
///     navigation cleanup to the caller
///
struct CardDestinationMenu: View
{


    let card:    KanbanCard   /* Card under consideration */
    var onMoved: () -> Void = /* Moved callback           */
    {

    }

    var locationTitle: String?          = nil    /* Location title          */
    @State private var showsSectionMove = false  /* Section Move visibility */
    @State private var showsDatePicker  = false  /* Date Picker visibility  */
    @State private var selectedMoveDate = Date() /* Selected move date      */

    @Environment(\.cardMovementAccess) private var access /* Scoped workspace operations     */
    @Environment(\.cardMovementSource) private var source /* Source value for this operation */

    private var destinations: [CardMoveDestination] /* Available operation destinations */
    {

        access.destinations
    }

    var body: some View /* Card Destination Menu layout */
    {

        if card.sectionHeading != nil, access.moveSection != nil
        {

            Button
            {

                showsSectionMove = true

            }
            label:
            {

                if let locationTitle
                {

                    SlideableHeaderText(text: locationTitle).font(.caption).foregroundStyle(.secondary).italic()
                }
                else
                {

                    Label("Move section to…", systemImage: "arrowshape.turn.up.right")
                }

            }
            .sheet(isPresented: $showsSectionMove)
            {
                SectionMoveSheet(heading: card, onMoved: onMoved)
            }

        }
        else if access.move != nil
        {

            Menu
            {

                ForEach(["Week", "Calendar", "Plans"], id: \.self)
                {
                    group in
                    Menu(group)
                    {

                        ForEach(destinations.filter
                            {
                                $0.group == group
                            })
                        {
                            destination in
                            Button(destination.title)
                            {

                                if access.move?(card, source, destination) == true
                                {
                                    onMoved()
                                }

                            }
                            .disabled(
                                destination.collectionID == source
                                && (destination.columnTitle ?? destination.title) == card.listTitle)
                        }

                    }
                    .disabled(!destinations.contains
                        {
                            $0.group == group
                        })
                }

                if access.moveToDate != nil
                {

                    Button("Choose a date…", systemImage: "calendar")
                    {

                        showsDatePicker = true

                    }

                }

            }
            label:
            {

                if let locationTitle
                {

                    SlideableHeaderText(text: locationTitle).font(.caption).foregroundStyle(.secondary).italic()
                }
                else
                {

                    Label("Move \(card.displayFormat.title.lowercased())", systemImage: "arrowshape.turn.up.right")
                }

            }
            .sheet(isPresented: $showsDatePicker)
            {

                NavigationStack
                {

                    Form
                    {

                        DatePicker("Move to", selection: $selectedMoveDate, displayedComponents: .date).datePickerStyle(
                            .graphical)
                    }
                    .navigationTitle("Move to a day")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar
                    {

                        ToolbarItem(placement: .cancellationAction)
                        {
                            Button("Cancel")
                            {

                                showsDatePicker = false

                            }

                        }

                        ToolbarItem(placement: .confirmationAction)
                        {

                            Button("Move")
                            {

                                if access.moveToDate?(card, source, selectedMoveDate) == true
                                {

                                    showsDatePicker = false;

                                    onMoved()
                                }

                            }

                        }

                    }

                }

            }

        }

    }

}
