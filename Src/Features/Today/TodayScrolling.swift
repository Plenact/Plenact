// --------------------------------------------------------------------------------------------------
// @file       TodayScrolling.swift
// @brief      Today header fading and deliberate section settling
// @details    Observes native scrolling and applies boundary-aware targets without publishing
//             unnecessary content mutations.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Carries the latest vertical offset reported by Today content
///
/// @section    Purpose
///     Bridge child scroll geometry to the header's fade observer
///
struct TodayScrollOffsetPreferenceKey: PreferenceKey
{


    ///
    /// @section    Purpose
    ///     Carry the latest vertical scroll offset from Today content to its observer
    ///
    /// Latest vertical offset reported by Today scroll content.
    static var defaultValue: CGFloat = 0 /* Unmeasured bottom navigation height */


    ///
    /// @fcn        TodayScrollOffsetPreferenceKey.reduce(value:nextValue:)
    /// @brief      Accept the latest reported Today content offset
    /// @details    Replaces the accumulated preference rather than adding nested offsets
    ///
    /// @param[in,out] value      Accumulated vertical offset
    /// @param[in]     nextValue  Provider for the next child preference
    ///
    /// @return     (Void) updates value with the next offset
    ///
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat)
    {


        value = nextValue()
    }

}


///
/// Snaps deliberate scrolling between Today content regions
///
/// @section    Purpose
///     Changes the native settling target only when a directional swipe crosses a configured
///     section boundary; otherwise preserves normal scrolling.
///
struct TodaySectionSnapBehavior: ScrollTargetBehavior
{


    var perspectiveTop:  CGFloat
    var shortcutsBottom: CGFloat
    var enabled:         Bool


    ///
    /// @fcn        TodaySectionSnapBehavior.destination
    /// @brief      Choose an optional Today-section scroll destination
    /// @details    Requires a meaningful directional swipe across the perspective or shortcut boundary; returns nil
    ///             when snapping is disabled or the gesture does not cross a boundary.
    ///
    /// @param[in]  start            Starting horizontal position or original vertical scroll offset in points
    /// @param[in]  proposed         Proposed vertical scroll offset at the end of the gesture
    /// @param[in]  perspectiveTop   Vertical content offset where the lower perspective section starts
    /// @param[in]  shortcutsBottom  Vertical content offset below the Today shortcut subtitles
    /// @param[in]  viewport         Viewport extent in points along the relevant scroll axis
    /// @param[in]  maximum          Largest vertical content offset allowed by the scroll bounds
    /// @param[in]  enabled          Whether this optional behavior is enabled
    ///
    /// @return     (CGFloat?) snapped vertical offset, or nil to preserve native scrolling
    ///
    static func destination(
        start: CGFloat, proposed: CGFloat, perspectiveTop: CGFloat,
        shortcutsBottom: CGFloat, viewport: CGFloat, maximum: CGFloat,
        enabled: Bool
    ) -> CGFloat?
    {

        guard enabled, perspectiveTop > shortcutsBottom, shortcutsBottom > 0, viewport > 0,
        abs(proposed - start) >= 24
        else
        {
            return nil
        }

        let revealBoundary = max(24, perspectiveTop - viewport * 0.7)
        if proposed > start, start < perspectiveTop - 24,
        start <= revealBoundary, proposed >= revealBoundary
        {

            return min(maximum, perspectiveTop)
        }

        if proposed < start, start >= shortcutsBottom, proposed <= shortcutsBottom
        {

            return 0
        }

        return nil
    }


    ///
    /// @fcn        TodaySectionSnapBehavior.updateTarget
    /// @brief      Apply the Today-section snap to a native scroll target
    /// @details    Uses the original and proposed offsets with content bounds, replacing only the target's vertical
    ///             origin when a snap is warranted.
    ///
    /// @param[in,out]  target   Proposed native scroll target, updated in place when the snapping rules apply
    /// @param[in]      context  Framework-supplied update context and coordinator access
    ///
    /// @return     (Void) no return value
    ///
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext)
    {

        guard
        let y = Self.destination(
            start: context.originalTarget.rect.minY,
            proposed: target.rect.minY, perspectiveTop: perspectiveTop, shortcutsBottom: shortcutsBottom,
            viewport: context.containerSize.height,
            maximum: max(0, context.contentSize.height - context.containerSize.height), enabled: enabled)
        else
        {
            return
        }

        target.rect.origin.y = y
    }

}


///
/// Tracks Today scrolling for header fading
///
/// @section    Purpose
///     Keeps the fade binding synchronized with native scroll geometry, with a coordinate-space
///     fallback on older systems.
///
struct TodayScrollFadeTracking: ViewModifier
{


    @Binding var isScrolled: Bool /* Header fade visibility state */


    ///
    /// @fcn        TodayScrollFadeTracking.body(content:)
    /// @brief      Track whether Today content has moved beneath its header
    /// @details    Uses inset-adjusted native scroll geometry on iOS 18 and later; earlier systems
    ///             use the named coordinate-space offset preference
    ///
    /// @param[in]  content  Scroll content receiving tracking behavior
    ///
    /// @return     (some View) content with scroll-observation modifiers
    ///
    /// @post       Scroll callbacks set isScrolled beyond the two-point threshold
    ///
    func body(content: Content) -> some View
    {


        if #available(iOS 18.0, *)
        {


            content.onScrollGeometryChange(for: Bool.self)
            {
                geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 2
            }
            action:
            {
                _, contentIsScrolled in
                isScrolled = contentIsScrolled
            }

        }
        else
        {

            content
            .coordinateSpace(name: "TodayScroll")
            .onPreferenceChange(TodayScrollOffsetPreferenceKey.self)
            {
                verticalOffset in
                isScrolled = verticalOffset < -2
            }

        }

    }

}
