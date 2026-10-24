// --------------------------------------------------------------------------------------------------
// @file       BoardGallery.swift
// @brief      Section-aware Board gallery presentation
// @details    Groups canonical items for visual browsing and delegates opening, updates, and
//             section movement through owner callbacks.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Groups gallery Cards beneath an optional named divider
///
/// @section    Purpose
///     Preserves the ungrouped prefix and section boundaries after collapsed-section filtering.
///
struct BoardGalleryGroup: Identifiable
{


    let id:      Int
    let divider: KanbanCard?
    var cards:   [KanbanCard]


    ///
    /// @fcn        BoardGalleryGroup.groups
    /// @brief      Partition visible gallery cards by named section
    /// @details    Begins with an ungrouped prefix and starts a new group for each named divider after collapse
    ///             filtering.
    ///
    /// @param[in]  list  List supplying the current content and metadata
    ///
    /// @return     ([BoardGalleryGroup]) ordered visible card groups, beginning with the possibly empty ungrouped
    ///             prefix
    ///
    static func groups(in list: KanbanList) -> [BoardGalleryGroup]
    {

        var groups = [BoardGalleryGroup(id: 0, divider: nil, cards: [])]
        for card in DaySections.visible(list.cards)
        {

            if card.isSectionDivider
            {

                groups.append(BoardGalleryGroup(id: groups.count, divider: card, cards: []))
            }
            else
            {

                groups[groups.count - 1].cards.append(card)
            }

        }

        return groups
    }

}


///
/// Presents Board content as section-aware gallery tiles
///
/// @section    Purpose
///     Uses canonical List data, appearance, and viewport memory while delegating opening, updates,
///     and section movement to the owner.
///
struct BoardGalleryView: View
{


    @Environment(\.boardViewportMemory) private var viewportMemory

    let lists:     [KanbanList]
    let listTitle: (KanbanList) -> String
    let onOpen:    (KanbanCard, Int) -> Void
    var onUpdate:  (KanbanCard) -> Void =
    {
        _ in
    }

    var onMoveSection: (Int, Int, Int) -> Void =
    {
        _, _, _ in
    }

    var showsListHeadings = true
    var boardAppearance = BoardAppearance()
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem]
    {

        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 156), spacing: 12, alignment: .top)]
    }

    var body: some View
    {

        ScrollView
        {

            LazyVStack(alignment: .leading, spacing: 24)
            {

                ForEach(lists)
                {
                    list in
                    VStack(alignment: .leading, spacing: 12)
                    {

                        if showsListHeadings
                        {

                            HStack
                            {

                                Text(listTitle(list)).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                                Spacer()
                                Text("\(list.cards.filter { !$0.isSectionDivider } .count) items").font(.caption)
                                .foregroundStyle(.secondary)
                            }

                        }

                        ForEach(BoardGalleryGroup.groups(in: list))
                        {
                            group in
                            if let divider = group.divider
                            {

                                DaySectionRow(
                                    card: divider, cards: list.cards, onUpdate: onUpdate,
                                    onMove:
                                    {
                                        onMoveSection(list.id, divider.id, $0)
                                    },
                                    onOpen:
                                    {
                                        onOpen(divider, list.id)
                                    }
                                )
                                .accessibilityLabel(divider.sectionHeading ?? "Section divider")
                                .id(divider.id)
                            }

                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12)
                            {

                                ForEach(group.cards)
                                {
                                    card in
                                    Button
                                    {

                                        onOpen(card, list.id)
                                    }
                                    label:
                                    {

                                        BoardGalleryTile(
                                            card: card, appearance: list.appearance, boardAppearance: boardAppearance
                                        )
                                        .modifier(DaySectionRail(cardID: card.id, cards: list.cards))
                                    }
                                    .buttonStyle(.plain).accessibilityHint("Opens this item in " + listTitle(list))
                                    .id(card.id)
                                }

                            }

                        }

                        if list.cards.isEmpty
                        {

                            Text("Room for your next idea").font(.subheadline).foregroundStyle(.secondary)
                        }

                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                }

                if lists.isEmpty
                {
                    Text("Add a list to start your gallery.").foregroundStyle(.white.opacity(0.8))
                }

            } .padding(16).padding(.bottom, 16)
            .background(BoardViewportScrollProbe(memory: viewportMemory, key: "gallery"))
            .modifier(RevealCreatedContent(lists: lists))
        }

    }

}


///
/// Renders a Card or Note in the Board gallery
///
/// @section    Purpose
///     Combines available cover imagery, plain-text excerpt, and resolved appearance without
///     modifying the source record.
///
struct BoardGalleryTile: View
{


    let card:       KanbanCard
    var appearance: ItemAppearance? = nil
    var boardAppearance = BoardAppearance()
    private var excerpt: String
    {

        PlanRichText.plain(card.descriptionOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View
    {

        VStack(alignment: .leading, spacing: 10)
        {

            if let cover = card.coverAttachment
            {

                CardCoverPreview(attachment: cover, height: card.displayFormat == .picture ? 150 : 112)
                .frame(height: card.displayFormat == .picture ? 150 : 112)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            else if card.displayFormat == .picture
            {

                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 112)
            }

            HStack(alignment: .top, spacing: 6)
            {

                Text(card.word).font(card.displayFormat == .title ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(
                    boardAppearance.resolvedTitleColor(card: card.appearance, list: appearance)?.color ?? .primary
                ).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                ImportantItemIndicator(cardID: card.id)
            }
            .itemBannerBackground(card.appearance)
            if card.presentation == .note && !excerpt.isEmpty && card.displayFormat != .picture
            {

                Text(excerpt).font(.subheadline).foregroundStyle(
                    boardAppearance.resolvedTextColor(card: card.appearance, list: appearance)?.color ?? .secondary
                ).lineLimit(3).lineSpacing(3)
            }

            ItemReactionPreview(card: card)
            HStack(spacing: 8)
            {

                Label(card.displayFormat.title, systemImage: card.displayFormat.symbol)
                if card.isTitleChecked
                {

                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Completed")
                }

                if !card.checklists.isEmpty
                {
                    Image(systemName: "checklist").accessibilityLabel("Has checklist")
                }

            } .font(.caption).foregroundStyle(.secondary)
            if card.showsDueDateInList && card.dueDate != nil
            {

                Text(card.dueDateLabel).font(.caption).foregroundStyle(.secondary)
            }

        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background
        {

            RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground))
            if let tint = card.appearance?.cardBackground ?? boardAppearance.cardBackground, tint != .neutral
            {

                RoundedRectangle(cornerRadius: 14).fill(tint.color)
            }

        }
        .overlay
        {
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.15))
        }

    }

}
