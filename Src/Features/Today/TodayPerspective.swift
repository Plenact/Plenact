// --------------------------------------------------------------------------------------------------
// @file       TodayPerspective.swift
// @brief      Read-only overview of the represented Day
// @details    Summarizes canonical content and offers navigation to existing planning surfaces
//             without creating new records.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Shows the current weekday list's progress and next open cards
///
/// @section    Purpose
///     Summarize the current focus and expose completion and list-navigation actions
///
/// Optional perspective below Today’s action area; all content derives from canonical lists.
struct TodayPerspectiveSection: View
{


    let completed:    [KanbanCard]
    let tomorrowList: KanbanList?
    let onReview:     (ReviewRhythmRoute) -> Void
    let onSettings:   () -> Void
    let onReflect:    () -> Void
    let onPrepare:    () -> Void

    private var tomorrowItems: [KanbanCard]
    {

        tomorrowList?.cards.filter
        {
            !$0.isSectionDivider && !$0.isTitleChecked
        }
        ?? []
    }


    var body: some View
    {

        VStack(alignment: .leading, spacing: 18)
        {

            VStack(alignment: .leading, spacing: 5)
            {

                Text("A little perspective")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                Text("Pause, notice, and make room for what’s next.")
                .font(.subheadline).foregroundStyle(.secondary)
            }


            VStack(alignment: .leading, spacing: 10)
            {

                heading("Close the loop", symbol: "arrow.triangle.2.circlepath")
                Text("Plans can change. Give unfinished things a next step when you’re ready.")
                .font(.subheadline).foregroundStyle(.secondary)
                ReviewRhythmPanel(onOpen: onReview, onSettings: onSettings)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TodayPanelSurface(backgroundOpacity: 0.6))

            if !completed.isEmpty
            {

                VStack(alignment: .leading, spacing: 10)
                {

                    heading("Worth noticing", symbol: "leaf")
                    Text(
                                                            "\(completed.count) \(completed.count == 1 ? "item is" : "items are") complete on today’s list."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(completed.prefix(2))
                    {
                        card in
                        Label(card.word, systemImage: "checkmark")
                        .font(.subheadline).lineLimit(2)
                    }

                    Button("Reflect on today", action: onReflect)
                    .font(.subheadline.weight(.medium)).foregroundStyle(.tint).frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(TodayPanelSurface(backgroundOpacity: 0.6))
            }


            VStack(alignment: .leading, spacing: 10)
            {

                heading("A glance at tomorrow", symbol: "sunrise")
                if tomorrowList == nil
                {

                    Text("A little room to think ahead. Tomorrow’s Day list isn’t set up yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                else if tomorrowItems.isEmpty
                {

                    Text("No unfinished items on tomorrow’s Day list. Leave room, or give something a place.")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                else
                {

                    Text(
                                                            "\(tomorrowItems.count) \(tomorrowItems.count == 1 ? "item has" : "items have") a place on tomorrow’s Day list."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(tomorrowItems.prefix(2))
                    {
                        card in
                        Text(card.word).font(.subheadline).lineLimit(2)
                    }

                    if tomorrowItems.count > 2
                    {

                        Text("And \(tomorrowItems.count - 2) more")
                        .font(.caption).foregroundStyle(.secondary)
                    }

                }

                Button("Consider tomorrow’s plan", action: onPrepare)
                .font(.subheadline.weight(.medium)).foregroundStyle(.tint).frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TodayPanelSurface(backgroundOpacity: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.perspective")
    }


    ///
    /// @fcn        TodayPerspectiveSection.heading
    /// @brief      Build a consistent perspective-section heading
    /// @details    Combines the authored title and symbol using the shared lower-Today section styling.
    ///
    /// @param[in]  title   Display title or proposed title text
    /// @param[in]  symbol  SF Symbol name used by the control
    ///
    /// @return     (some View) a consistent perspective-section heading
    ///
    private func heading(_ title: String, symbol: String) -> some View
    {

        Label(title, systemImage: symbol).font(.headline)
        .accessibilityAddTraits(.isHeader)
    }

}
