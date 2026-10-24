// --------------------------------------------------------------------------------------------------
// @file       ListGuidance.swift
// @brief      Temporary read-only built-in List guidance
// @details    Presents measured session-only guide content, header toggling, and coordinated
//             capture-row placement outside retained Card records. Header retraction slides and
//             collapses the guide together using the same timing as its entrance.
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
///     coordinates capture-row placement for the session.
///
struct SessionListGuidance: View
{


    let list:     KanbanList
    let labels:   LabelLibrary
    var onReveal: () -> Void =
    {

    }

    var toggleRequest:        Int = 0
    var onPresentationChange: (Bool) -> Void =
    {
        _ in
    }

    @State private var reportedInitialPresentation = false
    @State private var automaticRevealAttempted = false
    @State private var handledToggleRequest = 0
    @State private var entryWasEmpty: Bool
    @State private var isVisible = false
    @State private var hasPreparedLayout = false
    @State private var guideHeight: CGFloat = 220
    @State private var showsReadingView = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    ///
    /// @fcn        SessionListGuidance.init(list:labels:onReveal:)
    /// @brief      Capture eligibility at the start of this List visit
    /// @details    State retains the entry snapshot across content edits and child presentations.
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
        list: KanbanList, labels: LabelLibrary, onReveal: @escaping () -> Void =
        {

        }, toggleRequest: Int = 0,
        onPresentationChange: @escaping (Bool) -> Void =
        {
            _ in
        }
    )
    {

        self.list = list
        self.labels = labels
        self.onReveal = onReveal
        self.toggleRequest = toggleRequest
        self.onPresentationChange = onPresentationChange
        _entryWasEmpty = State(initialValue: list.cards.isEmpty && DefaultListTutorial.guidance(for: list.title) != nil)
    }


    var body: some View
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
                // Capture remains available and follows the shrinking row back toward the header.
                withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 1.9))
                {
                    isVisible = false
                    hasPreparedLayout = false
                }

                return
            }

            guard !Task.isCancelled else
            {
                return
            }

            if toggleRequest > 0
            {

                // Expand the reserved space with the card so capture follows the same curve.
                withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 1.9))
                {
                    hasPreparedLayout = true
                    isVisible = true
                    onReveal()
                    onPresentationChange(true)
                }

                return
            }

            // Initial entry prepares the row while capture is hidden before revealing both.
            var layoutTransaction = Transaction(animation: nil)
            layoutTransaction.disablesAnimations = true
            withTransaction(layoutTransaction)
            {

                hasPreparedLayout = true
                onReveal()
            }

            do
            {
                try await Task.sleep(for: .milliseconds(50))
            }
            catch
            {
                return
            }

            guard !Task.isCancelled else
            {
                return
            }

            isVisible = true
            onPresentationChange(true)
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
                        }, showsUnlockHint: false)
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
