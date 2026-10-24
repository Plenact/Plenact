// --------------------------------------------------------------------------------------------------
// @file       PaperSurfaces.swift
// @brief      Shared decorative Today paper and panel surfaces
// @details    Keeps texture and readable panel backgrounds independent of content state and hit
//             testing.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Draws the shared paper texture behind Today surfaces
///
/// @section    Purpose
///     Keep the decorative background consistent and noninteractive
///
struct TodayPaperBackground: View
{


    ///
    /// @fcn        TodayPaperBackground.body
    /// @brief      Fill the available surface with the shared Today paper texture
    /// @details    Scales and clips the image to geometry, extends through safe areas,
    ///             and excludes decoration from accessibility and hit testing
    ///
    /// @return     (some View) noninteractive full-surface background
    /// @post       Rendering does not affect app or navigation state
    ///
    var body: some View
    {  /* Noninteractive paper texture behind Today surfaces */

        GeometryReader
        {
            geometry in
            Image("TodayPaper")
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }

        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

}


///
/// Gives Today sections a readable raised surface over the full-screen paper texture
///
/// @section    Purpose
///     Apply one consistent panel treatment without intercepting content interaction
///
struct TodayPanelSurface: ViewModifier
{


    var backgroundOpacity: Double = 1


    ///
    /// @fcn        TodayPanelSurface.body(content:)
    /// @brief      Give Today content a padded raised material surface
    /// @details    Adds a rounded material background, light outline, and shadow; decorative layers
    ///             do not intercept the content's interactions
    ///
    /// @param[in]  content  Section content to decorate
    ///
    /// @return     (some View) padded content with the shared panel treatment
    ///
    /// @post       Content behavior and model state remain unchanged
    ///
    func body(content: Content) -> some View
    {


        content
        .padding(16)
        .background
        {

            RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.regularMaterial)
            .opacity(backgroundOpacity)
            .allowsHitTesting(false)
        }
        .overlay
        {

            RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.white.opacity(0.68), lineWidth: 1)
            .allowsHitTesting(false)
        }

        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 5)
    }

}
