// --------------------------------------------------------------------------------------------------
// @file       PreviewText.swift
// @brief      Measured overflowing preview text presentation
// @details    Reveals long writing within stable row dimensions and suspends unnecessary animation
//             for visibility or accessibility.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Collects the intrinsic preview-text width
///
/// @section    Purpose
///     Accepts the latest child measurement so overflowing content can be distinguished from text
///     that already fits.
///
struct PreviewTextWidthKey: PreferenceKey
{


    static let defaultValue: CGFloat = 0


    ///
    /// @fcn        PreviewTextWidthKey.reduce
    /// @brief      Accept the latest measured preview text width
    /// @details    Replaces the accumulated preference with the next measurement from the view hierarchy.
    ///
    /// @param[in,out]  value      Accumulated preference value replaced by the next child measurement
    /// @param[in]      nextValue  Closure supplying the next child preference value
    ///
    /// @return     (Void) no return value
    ///
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat)
    {
        value = nextValue()
    }

}


///
/// Collects the available preview viewport width
///
/// @section    Purpose
///     Propagates the latest visible width used to bound and schedule preview movement.
///
struct PreviewViewportWidthKey: PreferenceKey
{


    static let defaultValue: CGFloat = 0


    ///
    /// @fcn        PreviewViewportWidthKey.reduce
    /// @brief      Accept the latest measured preview viewport width
    /// @details    Uses the next child preference as the current available reading width.
    ///
    /// @param[in,out]  value      Accumulated preference value replaced by the next child measurement
    /// @param[in]      nextValue  Closure supplying the next child preference value
    ///
    /// @return     (Void) no return value
    ///
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat)
    {
        value = nextValue()
    }

}


///
/// Reports whether a moving preview is visible
///
/// @section    Purpose
///     Uses supported scroll visibility or appearance callbacks so offscreen previews can stop
///     unnecessary movement.
///
struct PreviewVisibility: ViewModifier
{


    @Binding var visible: Bool


    ///
    /// @fcn        PreviewVisibility.body
    /// @brief      Track whether an animated preview is visible
    /// @details    Uses scroll visibility where supported and falls back to appearance callbacks on older supported
    ///             systems.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) track whether an animated preview is visible
    ///
    func body(content: Content) -> some View
    {

        if #available(iOS 18.0, *)
        {

            content.onScrollVisibilityChange(threshold: 0.1)
            {
                visible = $0
            }

        }
        else
        {

            content.onAppear
            {
                visible = true
            } .onDisappear
            {
                visible = false
            }

        }

    }

}


///
/// Reveals overflowing collection preview writing
///
/// @section    Purpose
///     Measures text and viewport extents, keeps fitting text still, and suspends movement when
///     accessibility or visibility requires it.
///
struct GentleCollectionPreview: View
{


    let text: String
    var scrolls = false
    var textFont:        Font = .caption
    var textColor:       Color = .secondary
    var pointsPerSecond: Double = 14
    var startPause:      Double = 2.5
    var endPause:        Double = 2.5
    var travelsAcross = false


    ///
    /// Identifies a particular preview movement configuration
    ///
    /// @section    Purpose
    ///     Combines text, travel distance, and activity state so changes restart the appropriate
    ///     animation task.
    ///
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var textWidth:     CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var offset:        CGFloat = 0
    @State private var opacity:       Double = 1
    @State private var visible = false
    private struct Loop: Hashable
    {


        let text:     String
        let distance: CGFloat
        let active:   Bool
    }

    private var loop: Loop
    {

        Loop(
            text: text, distance: travelsAcross ? textWidth + viewportWidth : max(0, textWidth - viewportWidth),
            active: scrolls && !reduceMotion && !typeSize.isAccessibilitySize && visible && viewportWidth > 0)
    }

    var body: some View
    {

        Group
        {

            if scrolls && !reduceMotion && !typeSize.isAccessibilitySize
            {

                Text(text).lineLimit(1).hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading)
                {

                    Text(text).fixedSize(horizontal: true, vertical: false)
                    .background
                    {

                        GeometryReader
                        {
                            geometry in
                            Color.clear.preference(key: PreviewTextWidthKey.self, value: geometry.size.width)
                        }

                    }
                    .offset(x: offset).opacity(opacity)
                }
                .background
                {

                    GeometryReader
                    {
                        geometry in
                        Color.clear.preference(key: PreviewViewportWidthKey.self, value: geometry.size.width)
                    }

                }
                .clipped()
            }
            else
            {

                Text(text).lineLimit(travelsAcross ? nil : (typeSize.isAccessibilitySize ? 2 : 1))
                .fixedSize(horizontal: false, vertical: travelsAcross)
            }

        }
        .font(textFont).foregroundStyle(textColor)
        .accessibilityElement(children: .ignore).accessibilityLabel(text)
        .onPreferenceChange(PreviewTextWidthKey.self)
        {
            textWidth = $0
        }
        .onPreferenceChange(PreviewViewportWidthKey.self)
        {
            viewportWidth = $0
        }
        .modifier(PreviewVisibility(visible: $visible))
        .task(id: loop)
        {

            var reset = Transaction();
            reset.disablesAnimations = true
            withTransaction(reset)
            {

                offset = travelsAcross && loop.active ? viewportWidth : 0;
                opacity = 1
            }

            guard loop.active, loop.distance > 1 else
            {
                return
            }

            let distance = loop.distance
            let seconds = max(4, Double(distance) / max(1, pointsPerSecond))
            do
            {

                while !Task.isCancelled
                {

                    try await Task.sleep(for: .seconds(startPause))
                    withAnimation(.linear(duration: seconds))
                    {
                        offset = travelsAcross ? -textWidth : -distance
                    }

                    try await Task.sleep(for: .seconds(seconds + endPause))
                    withAnimation(.easeOut(duration: 0.4))
                    {
                        opacity = 0
                    }

                    try await Task.sleep(for: .seconds(0.4))
                    withTransaction(reset)
                    {
                        offset = travelsAcross ? viewportWidth : 0
                    }

                    withAnimation(.easeIn(duration: 0.6))
                    {
                        opacity = 1
                    }

                    try await Task.sleep(for: .seconds(0.6))
                }

            }
            catch
            {  /* Leaving the row or changing preferences cancels its loop. */

            }

        }

    }

}
