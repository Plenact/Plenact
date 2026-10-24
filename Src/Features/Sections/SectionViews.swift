// --------------------------------------------------------------------------------------------------
// @file       SectionViews.swift
// @brief      Named divider headings and section presentation
// @details    Renders collapse controls and colored membership rails without changing canonical
//             List order.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Renders a named section heading and collapse indicator
///
/// @section    Purpose
///     Uses the divider's retained heading and accent while keeping section membership in the
///     canonical List order.
///
struct NamedSectionDivider: View
{


    let card: KanbanCard
    var body: some View
    {

        HStack(spacing: 10)
        {

            if let heading = card.sectionHeading
            {

                Text(heading).font(.subheadline.weight(.semibold))
                .foregroundStyle(card.appearance?.accent?.color ?? .secondary).fixedSize(
                    horizontal: false, vertical: true)
                if card.appearance?.sectionCollapsed == true
                {

                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }

            }

            Rectangle().fill((card.appearance?.accent?.color ?? Color.secondary).opacity(0.35)).frame(height: 1)
            .frame(maxWidth: .infinity).accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
    }

}


///
/// Presents a Day section heading with separate actions
///
/// @section    Purpose
///     Keeps collapse and section operations out of the heading's navigation tap target.
///
struct DaySectionRow: View
{


    let card:     KanbanCard
    let cards:    [KanbanCard]
    let onUpdate: (KanbanCard) -> Void
    let onMove:   (Int) -> Void
    var onOpen:   (() -> Void)? = nil
    @Environment(\.cardMovementAccess) private var movement
    @State private var showsMove = false
    @ViewBuilder private var heading: some View
    {

        if let onOpen
        {

            Button(action: onOpen)
            {
                NamedSectionDivider(card: card)
            } .buttonStyle(.plain)
        }
        else
        {

            NavigationLink(value: card)
            {
                NamedSectionDivider(card: card)
            }
            .buttonStyle(.plain)
            .modifier(HideNavigationLinkIndicator())
        }

    }

    private var headings: [KanbanCard]
    {
        cards.filter
        {
            $0.sectionHeading != nil
        }

    }

    var body: some View
    {

        HStack(spacing: 0)
        {

            heading
            if card.sectionHeading != nil
            {

                Button
                {

                    var updated = card
                    var appearance = updated.appearance ?? ItemAppearance()
                    appearance.sectionCollapsed = appearance.sectionCollapsed != true
                    updated.appearance = appearance
                    onUpdate(updated)
                }
                label:
                {

                    Image(systemName: card.appearance?.sectionCollapsed == true ? "chevron.down" : "chevron.up")
                    .frame(width: 44, height: 44)
                } .buttonStyle(.borderless)
                .accessibilityLabel(
                    card.appearance?.sectionCollapsed == true ? "Expand section" : "Collapse section")
                Menu
                {

                    if movement.moveSection != nil
                    {

                        Button("Move section to…", systemImage: "arrowshape.turn.up.right")
                        {
                            showsMove = true
                        }

                    }

                    Menu("Section color", systemImage: "paintpalette")
                    {

                        Button("Default")
                        {
                            setColor(nil)
                        }

                        ForEach(ItemAccent.allCases, id: \.self)
                        {
                            color in
                            Button
                            {

                                setColor(color)
                            }
                            label:
                            {

                                Label(color.rawValue.capitalized, systemImage: "circle.fill").foregroundStyle(
                                    color.color)
                            }

                        }

                    }

                    Button("Move section earlier", systemImage: "arrow.up")
                    {
                        onMove(-1)
                    }
                    .disabled(headings.first?.id == card.id)
                    Button("Move section later", systemImage: "arrow.down")
                    {
                        onMove(1)
                    }
                    .disabled(headings.last?.id == card.id)
                }
                label:
                {

                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Section options for " + (card.sectionHeading ?? ""))
            }

        }
        .sheet(isPresented: $showsMove)
        {
            SectionMoveSheet(heading: card)
        }

    }


    ///
    /// @fcn        DaySectionRow.setColor
    /// @brief      Update the named section's accent color
    /// @details    Preserves other appearance fields and normalizes an empty appearance to nil before invoking the
    ///             update callback.
    ///
    /// @param[in]  color  Requested section accent; nil clears the explicit accent
    ///
    /// @return     (Void) no return value
    ///
    private func setColor(_ color: ItemAccent?)
    {

        var updated = card
        var appearance = updated.appearance ?? ItemAppearance()
        appearance.accent = color
        updated.appearance = appearance.isEmpty ? nil : appearance
        onUpdate(updated)
    }

}


///
/// Adds a section-colored rail beside a member Card
///
/// @section    Purpose
///     Derives the owning heading from canonical order and excludes the decorative overlay from
///     touch and accessibility handling.
///
struct DaySectionRail: ViewModifier
{


    let cardID: Int
    let cards:  [KanbanCard]


    ///
    /// @fcn        DaySectionRail.body
    /// @brief      Show a section-colored rail beside a member card
    /// @details    Uses the owning heading's accent and keeps the decorative overlay outside hit testing and
    ///             accessibility.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) show a section-colored rail beside a member card
    ///
    func body(content: Content) -> some View
    {

        content.overlay(alignment: .leading)
        {

            if let color = DaySections.owner(of: cardID, in: cards)?.appearance?.accent
            {

                RoundedRectangle(cornerRadius: 2).fill(color.color).frame(width: 3)
                .padding(.vertical, 6).allowsHitTesting(false).accessibilityHidden(true)
            }

        }

    }

}
