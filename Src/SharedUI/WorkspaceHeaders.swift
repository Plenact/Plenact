// --------------------------------------------------------------------------------------------------
// @file       WorkspaceHeaders.swift
// @brief      Adaptive workspace headings and manual overflow reading
// @details    Keeps title measurement, control spacing, and visible reading cues consistent while
//             retaining native touch regions.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Renders consistent workspace header icons
///
/// @section    Purpose
///     Shares glyph dimensions and touch areas across primary header controls without owning their
///     navigation actions.
///
struct WorkspaceHeaderIcon: View
{


    let systemName: String
    var body:       some View
    {

        Image(systemName: systemName)
        .font(.system(size: 20, weight: .medium))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

}


///
/// Adds accessibility navigation to a Day header
///
/// @section    Purpose
///     Applies button semantics only when an action exists, preserving a passive heading otherwise.
///
struct DayHeaderAccessibility: ViewModifier
{


    let label:  String
    let action: (() -> Void)?


    ///
    /// @fcn        DayHeaderAccessibility.body
    /// @brief      Expose an actionable day header to accessibility
    /// @details    Adds a button label and action when navigation exists; otherwise returns the content without
    ///             additional traits.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) expose an actionable day header to accessibility
    ///
    @ViewBuilder func body(content: Content) -> some View
    {

        if let action
        {

            content.accessibilityLabel(label).accessibilityAddTraits(.isButton).accessibilityAction
            {
                action()
            }

        }
        else
        {

            content
        }

    }

}


///
/// Provides manual horizontal reading for long headers
///
/// @section    Purpose
///     Uses native scrolling and overflow cues on either edge while preserving touch cancellation,
///     momentum, and the original title value.
///
struct SlideableHeaderText: View
{


    let text:             String
    var onTap:            (() -> Void)? = nil
    var onOverflowChange: (Bool) -> Void =
    {
        _ in
    }

    @AppStorage(PlanPreferencesStore.key) private var preferencesData = Data()
    private var allowsScrolling: Bool
    {

        (try? JSONDecoder().decode(LocalProfilePreferences.self, from: preferencesData))?.scrollsOverflowingTitles
        ?? true
    }

    @Environment(\.layoutDirection) private var readingDirection
    @Namespace private var readingSpace
    @State private var textFrame:     CGRect = .zero
    @State private var ellipsisWidth: CGFloat = 18
    @State private var textWidth:     CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    private var overflows:            Bool
    {
        textWidth > viewportWidth + 1
    }


    private var showsLeadingCue: Bool
    {

        guard overflows else
        {
            return false
        }

        return readingDirection == .rightToLeft ? textFrame.maxX > viewportWidth + 1 : textFrame.minX < -1
    }


    private var showsTrailingCue: Bool
    {

        guard overflows else
        {
            return false
        }

        return readingDirection == .rightToLeft ? textFrame.minX < -1 : textFrame.maxX > viewportWidth + 1
    }


    private var scrollingSurface: some View
    {

        Text(text.isEmpty ? " " : text)
        .lineLimit(1)
        .hidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay
        {

            GeometryReader
            {
                geometry in
                ScrollView(.horizontal)
                {

                    Text(text.isEmpty ? " " : text)
                    .fixedSize(horizontal: true, vertical: false)
                    .onGeometryChange(for: CGRect.self)
                    {

                        $0.frame(in: .named(readingSpace))
                    }
                    action:
                    {

                        textFrame = $0
                        textWidth = $0.width
                    }

                }
                .id(text)
                .coordinateSpace(name: readingSpace)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollDisabled(!overflows)
                .onGeometryChange(for: CGFloat.self)
                {

                    $0.size.width
                }
                action:
                {

                    viewportWidth = $0
                }
                .mask
                {

                    HStack(spacing: 0)
                    {

                        if showsLeadingCue
                        {

                            Color.clear.frame(width: ellipsisWidth)
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: readingDirection == .rightToLeft ? .trailing : .leading,
                                endPoint: readingDirection == .rightToLeft ? .leading : .trailing
                            )
                            .frame(width: 10)
                        }

                        Rectangle()
                        if showsTrailingCue
                        {

                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: readingDirection == .rightToLeft ? .trailing : .leading,
                                endPoint: readingDirection == .rightToLeft ? .leading : .trailing
                            )
                            .frame(width: 10)
                            Color.clear.frame(width: ellipsisWidth)
                        }

                    }

                }
                .overlay(alignment: .leading)
                {

                    Text("…")
                    .fixedSize()
                    .opacity(showsLeadingCue ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay(alignment: .trailing)
                {

                    Text("…")
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self)
                    {

                        $0.size.width
                    }
                    action:
                    {

                        ellipsisWidth = $0
                    }
                    .opacity(showsTrailingCue ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

            }

        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onChange(of: overflows, initial: true)
        {
            _, value in
            onOverflowChange(allowsScrolling && value)
        }

    }


    @ViewBuilder private var readingSurface: some View
    {

        if allowsScrolling
        {

            scrollingSurface
        }
        else
        {

            Text(text.isEmpty ? " " : text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(text)
        }

    }


    var body: some View
    {

        Group
        {

            if let onTap
            {

                readingSurface
                .onTapGesture(perform: onTap)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(
                    allowsScrolling && overflows
                    ? "Slide horizontally to read. Tap to open or edit." : "Tap to open or edit."
                )
                .accessibilityAction
                {
                    onTap()
                }

            }
            else
            {

                readingSurface
                .accessibilityHint(allowsScrolling && overflows ? "Slide horizontally to read the full text." : "")
            }

        }
        .onChange(of: allowsScrolling, initial: true)
        {
            _, value in
            onOverflowChange(value && overflows)
        }

    }

}


///
/// Marks a title subview for workspace header layout
///
/// @section    Purpose
///     Uses an explicit layout value so adaptive spacing can distinguish intrinsic title width from
///     neighboring controls.
///
struct WorkspaceHeaderTitleKey: LayoutValueKey
{


    static let defaultValue = false
}


///
/// Resolves stable spacing for workspace headers
///
/// @section    Purpose
///     Bases compact-gap decisions on intrinsic text width rather than a previously clipped
///     measurement.
///
enum WorkspaceHeaderSpacing
{


    ///
    /// @fcn        WorkspaceHeaderSpacing.gap
    /// @brief      Choose compact spacing only when header text would clip
    /// @details    Subtracts control widths and regular gaps, then returns zero if the ideal title exceeds the
    ///             remaining space by more than one point.
    ///
    /// @param[in]  availableWidth   Total width available to the header in points
    /// @param[in]  titleIdealWidth  Intrinsic width required by the title and subtitle
    /// @param[in]  controlsWidth    Combined intrinsic width of the header controls
    /// @param[in]  gapCount         Number of spaces between adjacent header children
    /// @param[in]  regularSpacing   Normal intercontrol spacing in points
    ///
    /// @return     (CGFloat) regular spacing when text fits, otherwise zero
    ///
    static func gap(
        availableWidth: CGFloat, titleIdealWidth: CGFloat, controlsWidth: CGFloat,
        gapCount: Int, regularSpacing: CGFloat
    ) -> CGFloat
    {

        let titleSpace = max(0, availableWidth - controlsWidth - CGFloat(max(0, gapCount)) * regularSpacing)
        return titleIdealWidth > titleSpace + 1 ? 0 : regularSpacing
    }

}


///
/// Lays out headers with adaptive gaps
///
/// @section    Purpose
///     Tightens spacing only between controls and preserves native control dimensions and their
///     interactive regions.
///
struct AdaptiveWorkspaceHeaderLayout: Layout
{


    var regularSpacing:  CGFloat
    var layoutDirection: LayoutDirection = .leftToRight


    ///
    /// @fcn        AdaptiveWorkspaceHeaderLayout.arrangement
    /// @brief      Measure a header with adaptive control spacing
    /// @details    Reserves intrinsic control sizes, detects the marked title child, and gives that child the
    ///             remaining width after the chosen gaps.
    ///
    /// @param[in]  width     Available horizontal extent in points
    /// @param[in]  subviews  Layout children to measure or position
    ///
    /// @return     ((sizes: [CGSize], gap: CGFloat, width: CGFloat)) child sizes, selected gap, and total width used
    ///             by measurement and placement
    ///
    private func arrangement(width: CGFloat?, subviews: Subviews) -> (sizes: [CGSize], gap: CGFloat, width: CGFloat)
    {

        let ideal = subviews.map
        {
            $0.sizeThatFits(.unspecified)
        }

        guard let title = subviews.indices.first(where:
            {
                subviews[$0] [WorkspaceHeaderTitleKey.self]
            }) else
        {

            let total = ideal.reduce(0)
            {
                $0 + $1.width
            }
            + CGFloat(max(0, subviews.count - 1)) * regularSpacing
            return (ideal, regularSpacing, width ?? total)
        }

        let controlsWidth = ideal.enumerated().filter
        {
            $0.offset != title
        } .reduce(0)
        {
            $0 + $1.element.width
        }

        let gapCount = max(0, subviews.count - 1)
        let available = width ?? (controlsWidth + ideal[title].width + CGFloat(gapCount) * regularSpacing)
        let gap = WorkspaceHeaderSpacing.gap(
            availableWidth: available, titleIdealWidth: ideal[title].width,
            controlsWidth: controlsWidth, gapCount: gapCount, regularSpacing: regularSpacing)
        let titleWidth = max(0, available - controlsWidth - CGFloat(gapCount) * gap)
        var sizes = ideal
        let titleSize = subviews[title].sizeThatFits(ProposedViewSize(width: titleWidth, height: nil))
        sizes[title] = CGSize(width: titleWidth, height: titleSize.height)
        return (sizes, gap, available)
    }


    ///
    /// @fcn        AdaptiveWorkspaceHeaderLayout.sizeThatFits
    /// @brief      Measure the adaptive header's required size
    /// @details    Uses the proposed width and the tallest arranged child without modifying the layout cache.
    ///
    /// @param[in]      proposal  Parent layout proposal, including an optional available width
    /// @param[in]      subviews  Layout children to measure or position
    /// @param[in,out]  cache     Framework layout cache; this implementation does not retain measurements in it
    ///
    /// @return     (CGSize) arranged header width and maximum child height
    ///
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize
    {

        let layout = arrangement(width: proposal.width, subviews: subviews)
        return CGSize(width: layout.width, height: layout.sizes.map(\.height).max() ?? 0)
    }


    ///
    /// @fcn        AdaptiveWorkspaceHeaderLayout.placeSubviews
    /// @brief      Position header children in the current reading direction
    /// @details    Uses the shared measurement result and reverses horizontal placement for right-to-left layouts
    ///             while centering children vertically.
    ///
    /// @param[in]      bounds    Assigned layout rectangle in which children should be placed
    /// @param[in]      proposal  Parent layout proposal, including an optional available width
    /// @param[in]      subviews  Layout children to measure or position
    /// @param[in,out]  cache     Framework layout cache; this implementation does not retain measurements in it
    ///
    /// @return     (Void) no return value
    ///
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
    {

        let layout = arrangement(width: bounds.width, subviews: subviews)
        var offset: CGFloat = 0
        for index in subviews.indices
        {

            let size = layout.sizes[index]
            let x =
            layoutDirection == .rightToLeft
            ? bounds.maxX - offset - size.width / 2
            : bounds.minX + offset + size.width / 2
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .center,
                proposal: ProposedViewSize(width: size.width, height: size.height))
            offset += size.width + layout.gap
        }

    }

}
