// --------------------------------------------------------------------------------------------------
// @file       BottomToolbar.swift
// @brief      Device-specific bottom-toolbar geometry and stable background coverage
// @details    Keeps explicit phone and tablet geometry independent of the workspace's stored
//             planning content. Draws the footer surface through an explicit bottom allowance
//             so sheet transitions cannot remove coverage by changing inherited safe-area rules.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Defines device-specific bottom-toolbar geometry
///
/// @section    Purpose
///     Keeps explicit phone and tablet presets available for independent tuning without changing
///     navigation behavior.
///
struct BottomToolbarLayout
{


    var height:             CGFloat
    var safeAreaAllowance:  CGFloat
    var rowSpacing:         CGFloat
    var horizontalPadding:  CGFloat
    var topPadding:         CGFloat
    var bottomPadding:      CGFloat
    var tabsOffset:         CGFloat
    var newOffset:          CGFloat
    var tabMinimumHeight:   CGFloat
    var tabIconSize:        CGFloat
    var newButtonSize:      CGFloat
    var newIconSize:        CGFloat
    var tabLabelSpacing:    CGFloat
    var newLabelSpacing:    CGFloat
    var backgroundTopInset: CGFloat
    var horizontalLabels:   Bool
    var labelStyle:         Font.TextStyle

    // iPhone layouts: edits here do not affect iPad.
    static let phoneRegular = Self(
        height: 74, safeAreaAllowance: 34, rowSpacing: 4, horizontalPadding: 12, topPadding: 4, bottomPadding: 4,
        tabsOffset: 25, newOffset: 14, tabMinimumHeight: 54, tabIconSize: 23, newButtonSize: 68, newIconSize: 24,
        tabLabelSpacing: 4, newLabelSpacing: 6, backgroundTopInset: 28, horizontalLabels: false, labelStyle: .caption)
    static let phoneCompact = Self(
        height: 52, safeAreaAllowance: 0, rowSpacing: 4, horizontalPadding: 12, topPadding: 4, bottomPadding: 4,
        tabsOffset: 0, newOffset: 0, tabMinimumHeight: 44, tabIconSize: 23, newButtonSize: 44, newIconSize: 24,
        tabLabelSpacing: 6, newLabelSpacing: 6, backgroundTopInset: 0, horizontalLabels: true, labelStyle: .caption)

    // iPad layouts: independently configurable, including compact-height windows.
    static let padRegular = Self(
        height: 84, safeAreaAllowance: 34, rowSpacing: 4, horizontalPadding: 12, topPadding: 4, bottomPadding: 4,
        tabsOffset: 25, newOffset: 14, tabMinimumHeight: 59, tabIconSize: 28, newButtonSize: 78, newIconSize: 29,
        tabLabelSpacing: 4, newLabelSpacing: 6, backgroundTopInset: 20, horizontalLabels: false, labelStyle: .caption)
    static let padCompact = Self(
        height: 86, safeAreaAllowance: 0, rowSpacing: 4, horizontalPadding: 12, topPadding: 4, bottomPadding: 4,
        tabsOffset: 0, newOffset: 0, tabMinimumHeight: 78, tabIconSize: 28, newButtonSize: 78, newIconSize: 29,
        tabLabelSpacing: 6, newLabelSpacing: 6, backgroundTopInset: 0, horizontalLabels: true, labelStyle: .caption)


    ///
    /// @fcn        BottomToolbarLayout.configuration
    /// @brief      Select the toolbar dimensions for device and size mode
    /// @details    Chooses among the phone and tablet compact or regular layout presets.
    ///
    /// @param[in]  isTablet  Whether the current device uses the tablet layout
    /// @param[in]  compact   Whether the compact presentation is selected
    ///
    /// @return     (BottomToolbarLayout) constructed value
    ///
    static func configuration(isTablet: Bool, compact: Bool) -> Self
    {

        if isTablet
        {
            return compact ? padCompact : padRegular
        }

        return compact ? phoneCompact : phoneRegular
    }


    ///
    /// @fcn        BottomToolbarLayout.reservedHeight
    /// @brief      Calculate toolbar space beyond the existing bottom inset
    /// @details    Adds only the remaining nonnegative safe-area allowance to the toolbar's height.
    ///
    /// @param[in]  bottomInset  Bottom safe-area inset already provided by the container
    ///
    /// @return     (CGFloat) toolbar height plus any safe-area allowance not already provided
    ///
    func reservedHeight(bottomInset: CGFloat) -> CGFloat
    {

        height + max(0, safeAreaAllowance - bottomInset)
    }

}


///
/// Draws the custom toolbar surface independently of its interactive controls
///
/// @section    Purpose
///     Keep the paper, tint, and upper border together while covering the home-indicator region.
///
struct BottomToolbarBackground: View
{

    let topInset:    CGFloat  /* Transparent overlap above the paper surface */
    let bottomInset: CGFloat  /* Explicit coverage below the control frame   */


    ///
    /// @fcn        BottomToolbarBackground.body
    /// @brief      Render the paper-backed toolbar surface
    /// @details    Extends the measured surface by the explicit bottom allowance instead of relying
    ///             on inherited safe-area expansion. Retains the preset top gap, covers missing
    ///             paper with an opaque base, and leaves control layout and hit testing unchanged.
    ///
    /// @return     (some View) decorative navigation background
    ///
    var body: some View
    {

        GeometryReader
        {
            geometry in
            let surfaceHeight = max(0, geometry.size.height - topInset) + max(0, bottomInset)  /* Paper and tint coverage including the reserved bottom strip */
            ZStack(alignment: .top)
            {

                Color(red: 0.83, green: 0.77, blue: 0.66)
                Image("TodayPaper")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: surfaceHeight)
                    .clipped()
                Color(red: 0.24, green: 0.17, blue: 0.12).opacity(0.54)
                Rectangle()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: 1)
            }
            .frame(width: geometry.size.width, height: surfaceHeight, alignment: .top)
            .offset(y: topInset)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
