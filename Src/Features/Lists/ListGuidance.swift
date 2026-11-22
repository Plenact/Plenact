// --------------------------------------------------------------------------------------------------
// @file       ListGuidance.swift
// @brief      Temporary read-only built-in List guidance
// @details    Presents measured session-only guide content, header toggling, and coordinated
//             capture-row placement outside retained Card records. Header retraction slides and
//             collapses the guide together using the same timing as its entrance
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Presents temporary guidance during a built-in List visit
///
/// @section    Purpose
///     Measures and slides a read-only guide outside persisted Cards, supports header toggling, and
///     coordinates capture-row placement for the session
///
struct SessionListGuidance: View
{
    let list:     KanbanList            /* List under consideration    */
    let labels:   LabelLibrary          /* Available label definitions */
    var onReveal: () -> Void =          /* Reveal callback             */
    {
    }

    var toggleRequest:        Int            = 0        /* Toggle request               */
    var onPresentationChange: (Bool) -> Void =          /* Presentation change callback */
    {
        _ in
    }

    var onVisibilityChange: (Bool) -> Void = { _ in }     /* Actual guide visibility, including retraction */

    @State private var reportedInitialPresentation = false                      /* Reported initial presentation */
    @State private var automaticRevealAttempted    = false                      /* Automatic reveal attempted    */
    @State private var handledToggleRequest        = 0                          /* Handled toggle request        */
    @State private var entryWasEmpty: Bool                                      /* Entry was empty               */
    @State private var isVisible            = false                             /* Visible state                 */
    @State private var hasPreparedLayout    = false                             /* Prepared Layout availability  */
    @State private var guideHeight: CGFloat = 220                               /* Guide height                  */
    @State private var showsReadingView     = false                             /* Reading View visibility       */
    @Environment(\.accessibilityReduceMotion) private var reduceMotion          /* Reduced-motion preference     */


    ///
    /// @fcn        SessionListGuidance.init(list:labels:onReveal:)
    /// @brief      Capture eligibility at the start of this List visit
    /// @details    State retains the entry snapshot across content edits and child presentations
    ///
    /// @param[in]  list                  List opened by the user
    /// @param[in]  labels                Shared labels used by the reading view
    /// @param[in]  onReveal              Layout notification when guidance becomes visible
    /// @param[in]  toggleRequest         Header tap sequence; changes toggle guidance independently of entry emptiness
    ///
    /// @param[in]  onPresentationChange  Reveals capture with the initial guide; capture stays available on retraction
    ///
    /// @return     (SessionListGuidance) transient visit-scoped guidance
    ///
    init(
        list:                 KanbanList,
        labels:               LabelLibrary,
        onReveal:             @escaping () -> Void =
        {
        },
        toggleRequest:        Int = 0,
        onPresentationChange: @escaping (Bool) -> Void =
        {
            _ in
        },
        onVisibilityChange: @escaping (Bool) -> Void = { _ in }
    )
    {
        self.list = list
        self.labels = labels
        self.onReveal = onReveal
        self.toggleRequest = toggleRequest
        self.onPresentationChange = onPresentationChange
        self.onVisibilityChange = onVisibilityChange
        _entryWasEmpty = State(initialValue: list.cards.isEmpty && DefaultListTutorial.guidance(for: list.title) != nil)
    }


    var body: some View         /* Session List Guidance layout */
    {
        VStack(spacing: 0)
        {
            if let guide = DefaultListTutorial.guidance(for: list.title)
            {
                Button
                {
                    showsReadingView = true
                }
                label:
                {
                    VStack(alignment: .leading, spacing: 10)
                    {
                        Label("About this List", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                        Text(guide.word).font(.headline).foregroundStyle(.primary)
                        Text(guide.descriptionOverride ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(
                            3)
                        Label("Read guide", systemImage: "arrow.up.right").font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("list.sessionGuidance")
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self)
                {
                    geometry in
                    geometry.size.height
                }
                action:
                {
                    height in
                    if height > 0
                    {
                        guideHeight = height
                    }
                }
                .offset(y: reduceMotion ? 0 : (isVisible ? 0 : -guideHeight))
                .opacity(isVisible ? 1 : 0)
                .animation(.easeInOut(duration: reduceMotion ? 0.2 : 1.9), value: isVisible)
                .allowsHitTesting(isVisible)
                .accessibilityHidden(!isVisible)
            }
        }
        .frame(height: hasPreparedLayout ? guideHeight : 0, alignment: .top)
        .clipped()
        .onAppear
        {
            guard !reportedInitialPresentation else
            {
                return
            }

            reportedInitialPresentation = true

            onPresentationChange(!entryWasEmpty)
            onVisibilityChange(isVisible)
        }
        .task(id: toggleRequest)
        {
            guard DefaultListTutorial.guidance(for: list.title) != nil else
            {
                return
            }

            if toggleRequest > 0
            {
                guard handledToggleRequest != toggleRequest else
                {
                    return
                }

                handledToggleRequest = toggleRequest
            }

            if toggleRequest == 0
            {
                guard entryWasEmpty, !automaticRevealAttempted else
                {
                    return
                }

                automaticRevealAttempted = true

                do
                {
                    try await Task.sleep(for: .milliseconds(300))
                }
                catch
                {
                    return
                }
            }
            else if isVisible
            {
                // Retract the card and its reserved row together, using the entrance curve.
                // Capture remains available and follows the shrinking row back toward the header
                withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 1.9))
                {
                    isVisible = false
                    onVisibilityChange(false)
                    hasPreparedLayout = false
                }

                return
            }

            guard !Task.isCancelled else
            {
                return
            }

            // Initial entry and header toggles expand the row and slide its content in one
            // transaction, so the list/capture below follows the same entrance curve.
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 1.9))
            {
                hasPreparedLayout = true
                isVisible = true
                onVisibilityChange(true)
                onReveal()
                onPresentationChange(true)
            }
        }
        .sheet(isPresented: $showsReadingView)
        {
            if let guide = DefaultListTutorial.guidance(for: list.title)
            {
                NavigationStack
                {
                    ReadOnlyCardContent(card: guide, labels: labels, onOpenAttachment:
                        {
                            _ in
                        }, showsUnlockHint: false, showsReadOnlyBadge: false)
                    .navigationTitle("About this List")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar
                    {
                        ToolbarItem(placement: .confirmationAction)
                        {
                            Button("Done")
                            {
                                showsReadingView = false
                            }
                        }
                    }
                }
            }
        }
    }
}


/// Blends the toolbar fade into a tapered glow as the built-in guide appears.
/// Animating the masks themselves keeps both edges soft throughout the card's slide.
struct SessionListGuidanceFade: View, Animatable
{
    var tint: Color
    var progress: CGFloat

    var animatableData: CGFloat
    {
        get { progress }
        set { progress = newValue }
    }

    var body: some View
    {
        let reveal = min(max(progress, 0), 1)

        Rectangle()
            .fill(Color(.systemGray3).opacity(0.65))
            .overlay(tint.opacity(0.20))
            .mask
            {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(1 - Double(reveal)), location: 0),
                        .init(color: .black, location: 0.28 * reveal),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .mask
            {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(1 - Double(reveal)), location: 0),
                        .init(color: .black, location: 0.16),
                        .init(color: .black, location: 0.84),
                        .init(color: .black.opacity(1 - Double(reveal)), location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing)
            }
            .frame(height: 12 + 8 * reveal)
            .padding(.horizontal, 12 * reveal)
            .opacity(1 - 0.45 * Double(reveal))
            .offset(y: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
