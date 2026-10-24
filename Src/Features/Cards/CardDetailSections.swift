// --------------------------------------------------------------------------------------------------
// @file       CardDetailSections.swift
// @brief      Reusable Card detail sections and controls
// @details    Keeps shared metadata rows, action tiles, date labels, and collapse controls
//             consistent between reading and editing surfaces.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


///
/// Displays a Note's creation date and time in a width-adaptive layout
///
/// @section    Purpose
///     Keep creation metadata visible beneath the Note title without truncating date or time
///
struct NoteCreationDateLabel: View
{


    let createdAt: Date /* Original Note creation time shown in the metadata row */

    var body: some View
    {  /* Formatted Note creation metadata */

        ViewThatFits(in: .horizontal)
        {

            Text(createdAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
            .fixedSize()
            VStack(alignment: .leading, spacing: 4)
            {

                Text(createdAt, format: .dateTime.month(.abbreviated).day().year())
                Text(createdAt, format: .dateTime.hour().minute())
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Created")
        .accessibilityValue(createdAt.formatted(date: .complete, time: .shortened))
    }

}


///
/// Applies the Note toolbar's minimum hit area and pressed-state feedback
///
/// @section    Purpose
///     Keep toolbar controls comfortably tappable and visibly responsive
///
struct NoteToolbarButtonStyle: ButtonStyle
{


    ///
    /// @fcn        NoteToolbarButtonStyle.makeBody(configuration:)
    /// @brief      Apply accessible sizing and pressed-state styling to a toolbar button
    /// @details    Preserves the label's shape as its content target and reduces opacity while
    ///             the button is pressed
    ///
    /// @param[in]  configuration  Current button label and interaction state
    ///
    /// @return     (some View) button label with minimum touch dimensions and feedback
    ///
    func makeBody(configuration: Configuration) -> some View
    {

        configuration.label
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .foregroundStyle(Color.accentColor)
        .opacity(configuration.isPressed ? 0.5 : 1)
    }

}


// --------------------------------------- MARK: - Detail Section ------------------------------- //


///
/// Groups a detail subsection with an optional trailing symbol
///
/// @section    Purpose
///     Provide a consistent heading, content area, spacing, and divider for card detail sections
///
/// @note   The generic content keeps this component reusable for text, controls, metadata, and activity
///
struct DetailSection<Content: View>: View
{


    @State private var isCollapsed = false
    let collapsible:    Bool
    let title:          String         /* The title of the detail section                    */
    var trailing:       String?        /* The optional trailing symbol of the detail section */
    var trailingAction: (() -> Void)?  /* The optional action for the trailing symbol        */

    @ViewBuilder let content: () -> Content /* Content rendered beneath the section heading */


    ///
    /// @fcn        DetailSection.init(title:trailing:trailingAction:content:)
    /// @brief      Initialize a detail section
    /// @details    Stores the section title, optional trailing symbol/action, and view-builder content
    ///
    /// @param[in]  title           Display title for the section
    /// @param[in]  trailing        Optional SF Symbol name shown at the trailing edge
    /// @param[in]  trailingAction  Optional action invoked by the trailing symbol
    /// @param[in]  content         Content rendered below the section heading
    ///
    /// @param[in]  collapsible     Whether the section heading exposes its local collapse control
    ///
    /// @return     (DetailSection) configured detail section
    /// @post       Content and trailing action are retained without being invoked
    ///
    init(
        title: String, collapsible: Bool = false, trailing: String? = nil, trailingAction: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    )
    {


        self.collapsible = collapsible
        self.title = title                    /* The title of the detail section                    */
        self.trailing = trailing              /* The optional trailing symbol of the detail section */
        self.trailingAction = trailingAction  /* The optional action for the trailing symbol        */
        self.content = content                /* The content of the detail section                  */
    }


    ///
    /// @fcn        DetailSection.body
    /// @brief      Build the detail section presentation
    /// @details    Renders the heading, optional trailing symbol/action, supplied content, and divider
    ///
    /// @return     (some View) rendered detail section
    /// @post       Tapping an actionable trailing symbol invokes trailingAction;
    ///             a symbol without an action remains decorative
    ///
    var body: some View
    {  /* Detail subsection heading and content */


        // Build the detail section container with heading, optional trailing symbol/action, content, and divider
        VStack(alignment: .leading, spacing: isCollapsed ? 0 : 10)
        {


            // Build the heading row with title and optional trailing symbol/action
            HStack
            {


                // Render the section title
                Text(title)
                .font(.headline)
                Spacer()

                // Render the trailing symbol and optional action if provided
                if let trailing
                {  /* Optional trailing symbol */


                    // Check if a trailing action is provided
                    if let trailingAction
                    {  /* Optional symbol action */


                        Button(action: trailingAction)
                        {

                            Image(systemName: trailing)
                            .foregroundStyle(.secondary)
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(title.lowercased())")
                    }
                    else
                    {


                        // Render the trailing symbol without an action
                        Image(systemName: trailing)
                        .foregroundStyle(.secondary)
                    }

                }

                if collapsible
                {

                    SectionCollapseButton(title: title, isCollapsed: $isCollapsed)
                }

            }


            VStack(alignment: .leading, spacing: 10)
            {
                content()
            }
            .frame(height: isCollapsed ? 0 : nil, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .opacity(isCollapsed ? 0 : 1)
            .allowsHitTesting(!isCollapsed)
            .accessibilityHidden(isCollapsed)
        }

        .padding(16)
        .background(.background)
        .overlay(alignment: .bottom)
        {
            Divider()
        }

    }

}


// --------------------------------------- MARK: - Action Tile ---------------------------------- //


///
/// Displays a labeled action tile in a card detail section
///
/// @section    Purpose
///     Present a labeled action with a symbol and accent color in the quick-actions grid
///
struct ActionTile: View
{


    let title:  String      /* The title of the action tile                  */
    let icon:   String      /* The icon representing the action tile         */
    let color:  Color       /* The color of the action tile                  */
    let action: () -> Void  /* The action to perform when the tile is tapped */

    ///
    /// @fcn        ActionTile.body
    /// @brief      Build the compact action tile
    /// @details    Renders the action label and symbol as a plain, consistently sized button
    ///
    /// @return     (some View) rendered action tile
    /// @post       Tapping delegates to action; rendering itself performs no mutation
    ///
    var body: some View
    {  /* Compact labeled action button */


        Button(action: action)
        {

            Label(title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .tint(color)
        }

        .buttonStyle(.plain)
    }

}


// --------------------------------------- MARK: - Detail Row ----------------------------------- //


///
/// Displays one icon, label, and value row in the card metadata
///
/// @section    Purpose
///     Keep related card metadata visually aligned and easy to scan
///
struct DetailRow: View
{


    let icon:  String  /* The icon representing the detail row     */
    let title: String  /* The title or label of the detail row     */
    let value: String  /* The value associated with the detail row */

    ///
    /// @fcn        DetailRow.body
    /// @brief      Build one metadata row
    /// @details    Aligns the supplied icon, title, and trailing value within the detail section
    ///
    /// @return     (some View) rendered metadata row
    /// @post       The row has no mutation or navigation behavior
    ///
    var body: some View
    {  /* Icon, title, and trailing metadata value */


        HStack(spacing: 12)
        {


            Image(systemName: icon)
            .frame(width: 22)
            .foregroundStyle(.secondary)

            Text(title)

            Spacer()

            Text(value)
            .foregroundStyle(.secondary)
        }

        .font(.subheadline)
        .padding(.vertical, 5)
    }

}


///
/// Presents a shared expandable-section control
///
/// @section    Purpose
///     Matches checklist chevron behavior while leaving the retained collapse state with the owning
///     editor.
///
struct SectionCollapseButton: View
{


    let title:                String
    @Binding var isCollapsed: Bool
    var body:                 some View
    {

        Button
        {

            isCollapsed.toggle()
        }
        label:
        {

            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand \(title)" : "Collapse \(title)")
    }

}
