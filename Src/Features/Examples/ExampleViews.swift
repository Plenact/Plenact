// --------------------------------------------------------------------------------------------------
// @file       ExampleViews.swift
// @brief      Searchable example discovery and read-only previews
// @details    Shows authored starting points and routes selection through existing template or
//             collection draft flows.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Presents optional synthetic list examples with an inspectable card preview
///
/// @section    Purpose
///     Let people choose a draft without writing data or replacing their existing work
///
struct PersonalListExamplesView: View
{


    var onLoadExampleWeek:     (() -> Bool)? = nil
    var onUndoExampleWeek:     (() -> Bool)? = nil
    let onSelect:              (PersonalListExample) -> Void /* Delegate draft creation to the owning Library */
    var onSelectMixedTemplate: ((MixedListTemplate) -> Void)? = nil
    var onSelectBoardExample:  ((PersonalBoardExample) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss /* Cancel the chooser without selecting */
    @State private var confirmsLoadWeek = false
    @State private var confirmsUndoWeek = false
    @State private var hasUndoableWeek: Bool
    @State private var operationError:  String?


    ///
    /// @fcn        PersonalListExamplesView.init
    /// @brief      Configure example-selection routes and initial Undo availability
    /// @details    Retains the optional week, board, and mixed-template callbacks and seeds the displayed week-Undo
    ///             state from the caller.
    ///
    /// @param[in]  onLoadExampleWeek      Optional checked callback to load the bundled example week
    /// @param[in]  onUndoExampleWeek      Optional checked callback to restore the pre-example week
    /// @param[in]  hasUndoableWeek        Whether an example-week restoration is initially available
    /// @param[in]  onSelectBoardExample   Optional callback for selecting a board example
    /// @param[in]  onSelectMixedTemplate  Optional callback for selecting a mixed-presentation template
    /// @param[in]  onSelect               Callback invoked after the user confirms a selection
    ///
    /// @return     (PersonalListExamplesView) initialized instance
    ///
    init(
        onLoadExampleWeek: (() -> Bool)? = nil,
        onUndoExampleWeek: (() -> Bool)? = nil,
        hasUndoableWeek: Bool = false,
        onSelectBoardExample: ((PersonalBoardExample) -> Void)? = nil,
        onSelectMixedTemplate: ((MixedListTemplate) -> Void)? = nil,
        onSelect: @escaping (PersonalListExample) -> Void
    )
    {

        self.onLoadExampleWeek = onLoadExampleWeek
        self.onUndoExampleWeek = onUndoExampleWeek
        self.onSelect = onSelect
        self.onSelectMixedTemplate = onSelectMixedTemplate
        self.onSelectBoardExample = onSelectBoardExample
        _hasUndoableWeek = State(initialValue: hasUndoableWeek)
    }


    ///
    /// @fcn        PersonalListExamplesView.body
    /// @brief      Show all six organizing examples and their card titles
    /// @details    Expanding a preview is read-only; Use example opens the save-before-adding flow
    /// @return     (some View) scrollable chooser with an explicit Cancel action
    ///
    var body: some View
    {  /* Personal List example chooser with expandable card previews */

        NavigationStack
        {

            List
            {

                Section
                {

                    Text(
                                                            "Explore Lists and Boards and make them your own. Selecting an example opens a draft; only Save adds it to Plans. Your Week and existing collections stay unchanged."
                    )
                    .foregroundStyle(.secondary)
                }


                if onLoadExampleWeek != nil
                {

                    Section("Example Week View")
                    {

                        Button("Load Example Week View", systemImage: "square.and.arrow.down")
                        {

                            confirmsLoadWeek = true
                        }
                        .accessibilityIdentifier("library.examples.loadWeek")
                        if hasUndoableWeek, onUndoExampleWeek != nil
                        {

                            Button("Undo Last Load", systemImage: "arrow.uturn.backward")
                            {

                                confirmsUndoWeek = true
                            }
                            .accessibilityIdentifier("library.examples.undoWeek")
                        }

                        Text(
                                                                        "Loading replaces your current Week Board, including archived Week content. Your previous Week Board is retained on this device for Undo Last Load. Personal Lists and Boards stay unchanged. Nothing is uploaded."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                }


                if let onSelectBoardExample
                {

                    Section("Board examples")
                    {

                        ForEach(PersonalBoardExample.allCases)
                        {
                            example in
                            DisclosureGroup
                            {

                                Text(example.summary).foregroundStyle(.secondary)
                                ForEach(Array(example.listSummaries.enumerated()), id: \.offset)
                                {
                                    _, list in
                                    HStack
                                    {

                                        Label(list.title, systemImage: "rectangle.split.3x1")
                                        Spacer()
                                        Text("\(list.count) items").font(.caption).foregroundStyle(.secondary)
                                    }

                                }

                                Text(
                                                                                                "Includes pictures, notes, named dividers, checklists, dates, labels, bookmarks, color overrides, and archived examples. Dates are illustrative and relative to when you create the draft."
                                )
                                .font(.caption).foregroundStyle(.secondary)
                                Button("Use \(example.rawValue)", systemImage: "plus")
                                {
                                    onSelectBoardExample(example)
                                }

                            }
                            label:
                            {

                                VStack(alignment: .leading, spacing: 4)
                                {

                                    Label(example.rawValue, systemImage: "rectangle.3.group").font(.headline)
                                    Text(
                                                                                                            "\(example.listSummaries.count) lists · \(example.listSummaries.reduce(0) { $0 + $1.count }) items"
                                    )
                                    .font(.caption).foregroundStyle(.secondary)
                                }

                            }

                        }

                    }

                }


                if let onSelectMixedTemplate
                {

                    Section("Templates")
                    {

                        ForEach(MixedListTemplate.allCases)
                        {
                            template in
                            DisclosureGroup(template.rawValue)
                            {

                                Text(template.summary).foregroundStyle(.secondary)
                                ForEach(template.items.indices, id: \.self)
                                {
                                    index in
                                    let item = template.items[index]
                                    VStack(alignment: .leading, spacing: 6)
                                    {

                                        if item.2 == .picture
                                        {

                                            CardCoverPreview(
                                                attachment: KanbanAttachment(
                                                    mediaKind: .photo, exampleImage: template.illustration))
                                        }

                                        Label(item.0, systemImage: item.2.symbol).font(.headline)
                                        Text(item.1).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }

                                Button("Use \(template.rawValue)", systemImage: "plus")
                                {

                                    onSelectMixedTemplate(template)
                                }

                            }

                        }

                    }

                }


                ForEach(PersonalListExample.allCases)
                {
                    example in
                    Section(example.rawValue)
                    {

                        Text(example.summary)
                        DisclosureGroup("Preview \(example.cards.count) example cards")
                        {

                            ForEach(example.cards.indices, id: \.self)
                            {
                                index in
                                VStack(alignment: .leading, spacing: 4)
                                {

                                    if index == 0, let illustration = example.coverIllustration
                                    {  /* Example's featured offline cover image */


                                        CardCoverPreview(
                                            attachment: KanbanAttachment(
                                                mediaKind: .photo, exampleImage: illustration
                                            ))
                                        Text("Optional example cover")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }


                                    Text(example.cards[index].0).font(.headline)
                                    Text(example.cards[index].1)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }

                                .padding(.vertical, 4)
                            }

                        }


                        Button("Use \(example.rawValue)", systemImage: "plus")
                        {

                            onSelect(example)
                        }

                    }

                }

            }

            .navigationTitle("Examples")
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
        .databaseActivityOverlay()
        .confirmationDialog(
                        "Replace the Week Board with the example?", isPresented: $confirmsLoadWeek, titleVisibility: .visible
        )
        {

            Button("Load Example Week View", role: .destructive)
            {

                if onLoadExampleWeek?() == true
                {

                    hasUndoableWeek = true
                    dismiss()
                }
                else
                {

                    operationError =
                                                            "The example Week Board could not be loaded. Your current Week Board was not changed."
                }

            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text(
                                    "This replaces the current active and archived Week lists and cards. Your previous Week Board is kept locally for undo. Personal collections stay unchanged."
            )
        }
        .confirmationDialog(
                        "Restore the previous Week Board?", isPresented: $confirmsUndoWeek, titleVisibility: .visible
        )
        {

            Button("Undo Last Load", role: .destructive)
            {

                if onUndoExampleWeek?() == true
                {

                    hasUndoableWeek = false
                    dismiss()
                }
                else
                {

                    operationError = "The saved Week Board snapshot could not be restored."
                }

            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text(
                                    "This replaces the current Week Board, including edits made since loading the example, with the saved Week Board from before the last load."
            )
        }
        .alert(
                        "Could not update Week Board",
                        isPresented: Binding(
                            get:
                            {
                                operationError != nil
                            },
                            set:
                            {
                                if !$0
                                {
                                    operationError = nil
                                }

                            }
                        )
        )
        {

            Button("OK", role: .cancel)
            {
                operationError = nil
            }

        }
        message:
        {

            Text(operationError ?? "")
        }

    }

}


///
/// Presents searchable Day-section examples
///
/// @section    Purpose
///     Keeps discovery read-only and routes actual use through the checked Day template application
///     flow.
///
struct LibraryDaySectionExamples: View
{


    var query = ""
    let onPreview: (PlanningRoutineTemplate) -> Void
    let onApply:   (PlanningRoutineTemplate) -> Void


    ///
    /// @fcn        LibraryDaySectionExamples.matches
    /// @brief      Search the bundled named-day-section examples
    /// @details    Matches template names, headings, and member text while retaining the predefined example order.
    ///
    /// @param[in]  query  User-entered search text
    ///
    /// @return     ([PlanningRoutineTemplate]) matching bundled day-section templates in catalog order
    ///
    static func matches(query: String) -> [PlanningRoutineTemplate]
    {

        PlanningRoutineLibrary.sectionExamples.filter
        {
            template in
            LibraryStarterSearch.matches(
                query,
                texts: [template.name, "Day section examples colored sections routines dividers collapse move"]
                + template.collection.lists.flatMap
                {
                    $0.cards.map(\.word)
                })
        }

    }

    var body: some View
    {

        let examples = Self.matches(query: query)
        if !examples.isEmpty
        {

            Section
            {

                ForEach(examples)
                {
                    template in
                    DisclosureGroup
                    {

                        Text("Three colored sections, six example items. Make this rhythm your own.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(template.collection.lists.flatMap(\.cards).filter
                            {
                                $0.sectionHeading != nil
                            })
                        {

                        heading in
                            Label(heading.sectionHeading ?? "", systemImage: "circle.fill")
                            .foregroundStyle(heading.appearance?.accent?.color ?? .secondary)
                        }

                        Button("Preview sections", systemImage: "eye")
                        {
                            onPreview(template)
                        }

                        Button("Use on a day…", systemImage: "calendar.badge.plus")
                        {
                            onApply(template)
                        }

                    }
                    label:
                    {

                        VStack(alignment: .leading, spacing: 4)
                        {

                            Label(template.name, systemImage: "rectangle.3.group")
                            Text(
                                template.collection.lists.flatMap(\.cards).compactMap(\.sectionHeading).joined(
                                    separator: " → ")
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        } .padding(.vertical, 4)
                    }

                }

            }
            header:
            {

                Text("Day section examples")
            }
            footer:
            {

                Text(
                                                "Explore a daily rhythm, a build session, or a workout journey. Preview freely, then choose a day to apply. Existing plans stay unchanged until you confirm."
                )
            }

        }

    }

}


///
/// Carries an unsaved Library example preview
///
/// @section    Purpose
///     Groups a title, explanation, and sample Lists for read-only presentation without registering
///     a new collection.
///
struct LibraryExamplePreview: Identifiable
{


    var id = UUID()
    let title:   String
    let summary: String
    let lists:   [KanbanList]
}


///
/// Displays a Library example without editing its records
///
/// @section    Purpose
///     Renders sample Lists and importance styling in an isolated preview; applying an example
///     remains a separate checked action.
///
struct LibraryExamplePreviewView: View
{


    let preview: LibraryExamplePreview
    @Environment(\.dismiss) private var dismiss
    var body: some View
    {

        NavigationStack
        {

            ScrollView
            {

                VStack(alignment: .leading, spacing: 20)
                {

                    Text(preview.summary).foregroundStyle(.secondary)
                    ForEach(preview.lists)
                    {
                        list in
                        VStack(alignment: .leading, spacing: 12)
                        {

                            if preview.lists.count > 1
                            {
                                Text(list.title).font(.title2.bold())
                            }

                            ForEach(list.cards)
                            {
                                card in
                                if card.isSectionDivider
                                {

                                    NamedSectionDivider(card: card)
                                }
                                else
                                {

                                    KanbanCardView(
                                        card: card, height: 100, displaySettings: BoardDisplaySettings(),
                                        labelLibrary: .starter,
                                        onUpdateCard:
                                        {
                                            _ in
                                        }, onDeleteCard:
                                        {

                                        }, onArchiveCard:
                                        {

                                        }, onToggle:
                                        {

                                        }
                                    )
                                    .modifier(DaySectionRail(cardID: card.id, cards: list.cards))
                                    .allowsHitTesting(false)
                                }

                            }

                        }

                    }

                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {
                ToolbarItem(placement: .topBarTrailing)
                {
                    Button("Done")
                    {
                        dismiss()
                    }

                }

            }

        }
        .environment(\.cardMovementSource, nil)
        .environment(
            \.libraryImportance,
            LibraryImportanceAccess(
                contains:
                {
                    _ in
                    true
                }, set:
                {
                    _, _ in
                },
                level:
                {
                    id in
                    LibraryImportanceSelection.demonstrationLevel(
                        for: preview.lists.flatMap(\.cards).first
                        {
                            $0.id == id
                        }?.word ?? "")
                }))
    }

}
