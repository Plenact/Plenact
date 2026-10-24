// --------------------------------------------------------------------------------------------------
// @file       CaptureModels.swift
// @brief      Full capture submissions and creation policy values
// @details    Keeps destination, writing, presentation, scheduling, template choices, and
//             multiline parsing together before explicit item creation.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import Foundation
import PhotosUI
import Speech
import SwiftUI


///
/// Presents local quick-capture starting points
///
/// @section    Purpose
///     Returns a selected template to the capture flow without creating or replacing stored
///     content.
///
struct QuickCaptureTemplatesView: View
{


    let onSelect: (QuickCaptureTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ItemPresentation?

    var body: some View
    {

        NavigationStack
        {

            ScrollView
            {

                VStack(alignment: .leading, spacing: 16)
                {

                    Text("Choose a starting point. Make it your own.")
                    .foregroundStyle(.secondary)
                    Picker("Template type", selection: $filter)
                    {

                        Text("All").tag(nil as ItemPresentation?)
                        Text("Cards").tag(Optional(ItemPresentation.card))
                        Text("Notes").tag(Optional(ItemPresentation.note))
                    }
                    .pickerStyle(.segmented)

                    ForEach(
                        QuickCaptureTemplate.allCases.filter
                        {

                            $0 != .blankCard && $0 != .blankNote && (filter == nil || $0.presentation == filter)
                        }
                    )
                    {
                        template in
                        templateButton(template)
                    }


                    Text("Or start with a blank page")
                    .font(.headline)
                    ForEach(
                        [QuickCaptureTemplate.blankCard, .blankNote].filter
                        {

                            filter == nil || $0.presentation == filter
                        }
                    )
                    {
                        template in
                        templateButton(template)
                    }

                    Text("Templates stay on this device. Nothing is added until you review the draft and tap Add.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background
            {
                TodayPaperBackground()
            }
            .navigationTitle("Start from a template")
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
    }


    ///
    /// @fcn        QuickCaptureTemplatesView.templateButton
    /// @brief      Build a quick-capture template selection button
    /// @details    Uses the template's presentation and invokes the selection action for that particular template.
    ///
    /// @param[in]  template  Authored routine or capture template to preview, apply, or edit
    ///
    /// @return     (some View) a quick-capture template selection button
    ///
    private func templateButton(_ template: QuickCaptureTemplate) -> some View
    {

        Button
        {

            onSelect(template)
        }
        label:
        {

            VStack(alignment: .leading, spacing: 8)
            {

                Label(template.title, systemImage: template.presentation == .note ? "note.text" : "rectangle")
                .font(.headline)
                Text(template.presentation.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Text(template.summary)
                .font(.subheadline)
                if !template.body.isEmpty
                {

                    Text(([template.body] + template.actions).joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(16)
            .modifier(TodayPanelSurface())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens an editable draft. Does not add an item yet.")
    }

}


///
/// Selects Card or Note creation presentation
///
/// @section    Purpose
///     Binds the requested item kind in a segmented control without creating records or changing
///     destination defaults.
///
struct ContentCreationKindPicker: View
{


    @Binding var presentation: ItemPresentation
    var body:                  some View
    {

        Picker("Create as", selection: $presentation)
        {

            Label("Card", systemImage: "rectangle").tag(ItemPresentation.card)
            Label("Note", systemImage: "note.text").tag(ItemPresentation.note)
        } .pickerStyle(.segmented).accessibilityLabel("Create as Card or Note")
    }

}


///
/// Defines the quick-capture entry modes
///
/// @section    Purpose
///     Supplies each mode's label, symbol, and initial Card or Note presentation without creating a
///     record.
///
enum TodayCaptureAction: String, CaseIterable, Identifiable
{


    case note, checklist, photo, voice, drawing
    var id: Self
    {
        self
    }

    var title: String
    {

        switch self
        {

        case .note:
                    "Note";

        case .checklist:
                    "Checklist";

        case .photo:
                    "Photo";

        case .voice:
                    "Voice";

        case .drawing:
                    "Drawing"
        }

    }

    var symbol: String
    {

        switch self
        {

        case .note:
                    "square.and.pencil";

        case .checklist:
                    "checklist";

        case .photo:
                    "camera";

        case .voice:
                    "mic";

        case .drawing:
                    "pencil.tip.crop.circle.badge.plus"
        }

    }

    var presentation: ItemPresentation
    {
        self == .note ? .note : .card
    }

}


///
/// Presents the quick-capture mode buttons
///
/// @section    Purpose
///     Delegates selection to the caller so capture presentation and storage remain under the
///     owning view's control.
///
struct TodayCaptureActions: View
{


    let onSelect: (TodayCaptureAction) -> Void
    var body:     some View
    {

        HStack(spacing: 8)
        {

            ForEach(TodayCaptureAction.allCases)
            {
                action in
                Button
                {

                    onSelect(action)
                }
                label:
                {

                    Image(systemName: action.symbol)
                    .font(.system(size: 19))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Capture " + action.title.lowercased())
            }

        }

    }

}


///
/// Carries optional scheduling values for a capture draft
///
/// @section    Purpose
///     Validates start and stop values with the supplied calendar before a new item is committed.
///
struct QuickCaptureSchedule: Equatable
{


    var start: Date?
    var stop:  Date?
    var includesTime = false


    ///
    /// @fcn        QuickCaptureSchedule.isValid
    /// @brief      Validate the optional capture schedule
    /// @details    Checks the schedule endpoints using their date kinds and the supplied calendar before new items
    ///             are created.
    ///
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (Bool) true when the schedule satisfies its endpoint and calendar rules; false otherwise
    ///
    func isValid(calendar: Calendar = .current) -> Bool
    {

        guard let start, let stop else
        {
            return true
        }

        return includesTime ? stop >= start : calendar.startOfDay(for: stop) >= calendar.startOfDay(for: start)
    }


    ///
    /// @fcn        QuickCaptureSchedule.apply
    /// @brief      Copy the capture schedule onto a newly created card
    /// @details    Normalizes the start and due values according to their date kinds and supplied calendar.
    ///
    /// @param[in,out]  card      Card or note being inspected or changed
    /// @param[in]      calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (Void) no return value
    ///
    func apply(to card: inout KanbanCard, calendar: Calendar = .current)
    {

        let kind: CardDateKind = includesTime ? .dateAndTime : .date
        card.startDate = start.map
        {
            kind.normalized($0, calendar: calendar)
        }

        card.dueDate = stop.map
        {
            kind.normalized($0, calendar: calendar)
        }

        card.startDateKind = kind;
        card.dueDateKind = kind
    }

}


///
/// Carries a complete new-item submission
///
/// @section    Purpose
///     Keeps destination, writing, presentation, checklist actions, attachments, and optional
///     scheduling together for a checked owner-level save.
///
struct QuickCaptureSubmission
{


    let listID:       Int
    let title:        String
    let body:         String
    let subtitle:     String
    let presentation: ItemPresentation
    let actions:      [String]?
    let attachments:  [KanbanAttachment]
    let schedule:     QuickCaptureSchedule?
}


///
/// Selects which parts of voice capture to retain
///
/// @section    Purpose
///     Controls whether the saved item contains recorded audio, transcribed writing, or both.
///
enum VoiceCaptureSaveOption: String, CaseIterable, Identifiable
{


    case audio = "Audio", text = "Text", both = "Both"
    var id: Self
    {
        self
    }

    var savesAudio: Bool
    {
        self != .text
    }

    var savesText: Bool
    {
        self != .audio
    }


    ///
    /// @fcn        VoiceCaptureSaveOption.body
    /// @brief      Combine existing writing with a voice transcript
    /// @details    Uses the selected save option to keep, replace, or combine content without changing the underlying
    ///             recording.
    ///
    /// @param[in]  existing    Existing body text that may be retained or combined
    /// @param[in]  transcript  Recognized voice transcript proposed for the capture body
    ///
    /// @return     (String) body text selected or combined according to this save option
    ///
    func body(existing: String, transcript: String) -> String
    {

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard savesText, !text.isEmpty else
        {
            return existing
        }

        let result = NSMutableAttributedString(attributedString: PlanRichText.attributed(existing))
        result.append(NSAttributedString(string: (result.length == 0 ? "" : "\n\n") + text))
        return PlanRichText.encode(result)
    }

}


///
/// Provides authored quick-capture starting points
///
/// @section    Purpose
///     Supplies local draft content without creating records until the user explicitly submits the
///     composer.
///
enum QuickCaptureTemplate: String, CaseIterable, Identifiable
{


    case usefulStep, smallPlan, errands, idea, reference, reflection
    case blankCard, blankNote

    var id: String
    {
        rawValue
    }


    var presentation: ItemPresentation
    {

        switch self
        {

        case .idea, .reference, .reflection, .blankNote:
            .note
        default:
            .card
        }

    }


    var title: String
    {

        switch self
        {

        case .usefulStep:
                    "One useful step"
        case .smallPlan:
                    "A small plan"
        case .errands:
                    "Out and about"
        case .idea:
                    "An idea to explore"
        case .reference:
                    "Something to remember"
        case .reflection:
                    "Looking back"
        case .blankCard:
                    "Blank Card"
        case .blankNote:
                    "Blank Note"
        }

    }


    var summary: String
    {

        switch self
        {

        case .usefulStep:
                    "Name an activity and choose a manageable next step."
        case .smallPlan:
                    "Describe a goal, prepare, and take the next steps."
        case .errands:
                    "Keep a few errands together in an editable checklist."
        case .idea:
                    "Explore a thought without committing to a plan."
        case .reference:
                    "Keep useful information, context, and links."
        case .reflection:
                    "Notice what happened and what you want to take forward."
        case .blankCard, .blankNote:
                    "Start with space for your own words."
        }

    }


    var body: String
    {

        switch self
        {

        case .usefulStep:
                    "What matters about this activity?"
        case .smallPlan:
                    "The goal\n\nWhat would a useful result look like?"
        case .errands:
                    "Places to visit and anything to bring"
        case .idea:
                    "The idea\n\nWhy it interests me\n\nSomething to try"
        case .reference:
                    "Useful information\n\nContext\n\nLinks"
        case .reflection:
                    "What happened\n\nWhat I noticed\n\nWhat comes next"
        case .blankCard, .blankNote:
                    ""
        }

    }


    var actions: [String]
    {

        switch self
        {

        case .usefulStep:
            ["Choose one next step"]
        case .smallPlan:
            ["Prepare what I need", "Take the first step"]
        case .errands:
            ["An errand to do", "Something to bring"]
        default:
            []
        }

    }


    ///
    /// @fcn        QuickCaptureTemplate.draftTitle
    /// @brief      Choose a captured title or the template default
    /// @details    Preserves a nonblank captured title exactly; blank Card and Note templates remain untitled while
    ///             other templates use their authored title.
    ///
    /// @param[in]  capturedTitle  Existing title text to preserve when it is not blank
    ///
    /// @return     (String) unchanged nonblank captured title, authored template title, or blank for empty generic
    ///             templates
    ///
    func draftTitle(capturedTitle: String) -> String
    {

        if !capturedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {

            return capturedTitle
        }

        return self == .blankCard || self == .blankNote ? "" : title
    }

}


///
/// Normalizes multiline item-title submissions
///
/// @section    Purpose
///     Preserves nonempty line order and duplicates while omitting whitespace-only entries.
///
enum MultilineEntry
{


    ///
    /// @fcn        MultilineEntry.titles
    /// @brief      Split a multiline entry into usable item titles
    /// @details    Trims each line and discards empty lines while preserving the order of the remaining entries.
    ///
    /// @param[in]  text  Attributed or plain text to restore or display
    ///
    /// @return     ([String]) trimmed nonempty input lines in their original order
    ///
    static func titles(_ text: String) -> [String]
    {

        text.components(separatedBy: .newlines)
        .map
        {
            $0.trimmingCharacters(in: .whitespaces)
        }
        .filter
        {
            !$0.isEmpty
        }

    }

}
