// --------------------------------------------------------------------------------------------------
// @file       NavigationShortcuts.swift
// @brief      Shared Back behavior and navigation presentation helpers
// @details    Exposes the configured lower-corner return action and focused navigation styling
//             without owning workspace content.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Hides the automatic trailing indicator on navigation links when supported
///
/// @section    Purpose
///     Keep list rows fully tappable without displaying a redundant disclosure chevron
///
/// @details    Uses SwiftUI's navigation indicator visibility API on iOS 18 and later, while
///             preserving content on earlier versions
///
/// @note       Apply this modifier to navigation links whose destination is indicated by the row itself
///
struct HideNavigationLinkIndicator: ViewModifier
{


    ///
    /// @fcn        HideNavigationLinkIndicator.body(content:)
    /// @brief      Configure navigation indicator visibility for the modified content
    /// @details    Hides navigation link indicators on iOS 18 and later; earlier iOS versions
    ///             receive the content unchanged
    ///
    /// @param[in]  content  View content to which this modifier is applied
    ///
    /// @return     (some View) modified content with the navigation indicator hidden when supported
    ///
    /// @pre        SwiftUI invokes this function when the modifier is applied to a view
    /// @post       The original content is preserved, with supported navigation indicators hidden
    ///
    @ViewBuilder
    func body(content: Content) -> some View
    {


        if #available(iOS 18.0, *)
        {


            content.navigationLinkIndicatorVisibility(.hidden)
        }
        else
        {


            content
        }

    }

}


///
/// Adds the configurable lower-left Back shortcut
///
/// @section    Purpose
///     Uses the same return action as the visible Back control, defaults to enabled, and reserves
///     space around existing content and toolbars.
///
struct LowerCornerBackShortcut: ViewModifier
{


    let action: (() -> Void)?
    @AppStorage(PlanPreferencesStore.key) private var preferencesData = Data()
    @AppStorage(LocalProfileStore.storageKey) private var profileData = Data()
    @Environment(\.workspaceBottomBarHeight) private var toolbarHeight
    @State private var keyboardVisible = false
    private var enabled: Bool
    {

        PlanPreferencesStore.resolved(preferencesData: preferencesData, profileData: profileData).enablesLowerCornerBack
    }


    ///
    /// @fcn        LowerCornerBackShortcut.body
    /// @brief      Install the optional lower-left Back touch region
    /// @details    Shows an eighty-eight-point-wide target only when enabled, a Back action exists, and the keyboard
    ///             is hidden; includes the home-indicator inset on full-screen destinations.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) install the optional lower-left back touch region
    ///
    func body(content: Content) -> some View
    {

        content
        .safeAreaInset(edge: .bottom, spacing: 0)
        {

            if enabled, !keyboardVisible, let action
            {

                GeometryReader
                {
                    geometry in
                    // Full-screen destinations have no toolbar below the target:
                    // include their home-indicator safe area in the touch region.
                    let bottomExtension = toolbarHeight > 0 ? 0 : geometry.safeAreaInsets.bottom
                    HStack(spacing: 0)
                    {

                        Color.clear
                        .frame(width: 88, height: 44 + bottomExtension)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: action)
                        .accessibilityElement()
                        .accessibilityLabel("Back")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction
                        {
                            action()
                        }
                        .accessibilityIdentifier("navigation.lowerCornerBack")
                        Spacer(minLength: 0)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .frame(height: 44)
                .padding(.bottom, max(0, toolbarHeight))
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
        {
            _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
        {
            _ in
            keyboardVisible = false
        }

    }

}
