// --------------------------------------------------------------------------------------------------
// @file       TodayFocus.swift
// @brief      Derived Focus entries, filtering, and direct detail access
// @details    Combines configured selection sources and section context while preserving personal
//             importance and caller-specific return routes.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Resolves colors for combined Today Focus filters
///
/// @section    Purpose
///     Keeps deliberately chosen combination hues distinct instead of blending selections into an
///     ambiguous average.
///
struct TodayFocusFilterColor
{


    ///
    /// @fcn        TodayFocusFilterColor.rgb
    /// @brief      Choose the distinct RGB color for a Focus-filter combination
    /// @details    Uses the selected-filter bit combination and light or dark palette; returns nil for the unfiltered
    ///             All state.
    ///
    /// @param[in]  upNext      Whether the Up Next filter is selected
    /// @param[in]  important   Importance selections or the Important filter state
    /// @param[in]  bookmarked  Whether the Bookmarked filter is selected
    /// @param[in]  dark        Whether to use the dark-appearance palette
    ///
    /// @return     ((red: Double, green: Double, blue: Double)?) selected combination color, or nil for All
    ///
    static func rgb(upNext: Bool, important: Bool, bookmarked: Bool, dark: Bool = false) -> (
        red: Double, green: Double, blue: Double
    )?
    {

        let selection = (upNext ? 1 : 0) | (important ? 2 : 0) | (bookmarked ? 4 : 0)
        // A blue, B red, C green; AB purple, AC teal, BC orange, ABC neutral.
        let light: [Int: Int] = [
            1: 0x1D4ED8, 2: 0xB42336, 4: 0x276524,
            3: 0x7E22CE, 5: 0x00666B, 6: 0x9A4100, 7: 0x535766
        ]
        let night: [Int: Int] = [
            1: 0x93B8FF, 2: 0xFF9BA8, 4: 0xA3DA83,
            3: 0xD3A6FF, 5: 0x70D8D4, 6: 0xFFBB78, 7: 0xC9CBD4
        ]
        guard let hex = (dark ? night : light) [selection] else
        {
            return nil
        }

        return (
            Double((hex >> 16) & 255) / 255,
            Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255
        )
    }


    ///
    /// @fcn        TodayFocusFilterColor.color
    /// @brief      Resolve the Focus combination color for display
    /// @details    Converts the shared RGB selection into a SwiftUI color and uses the unfiltered fallback when no
    ///             specific filter is active.
    ///
    /// @param[in]  upNext      Whether the Up Next filter is selected
    /// @param[in]  important   Importance selections or the Important filter state
    /// @param[in]  bookmarked  Whether the Bookmarked filter is selected
    /// @param[in]  dark        Whether to use the dark-appearance palette
    ///
    /// @return     (Color) palette color for the selected filters, or the All-state fallback
    ///
    static func color(upNext: Bool = false, important: Bool = false, bookmarked: Bool = false, dark: Bool) -> Color
    {

        guard let rgb = rgb(upNext: upNext, important: important, bookmarked: bookmarked, dark: dark) else
        {

            return dark ? .white : .black
        }

        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

}


///
/// Presents Today's filtered focus items
///
/// @section    Purpose
///     Renders derived entries with optional section grouping, importance controls, and direct
///     detail navigation without duplicating the Day's records.
///
struct TodayFocusSection: View
{


    let list:              KanbanList?   /* Canonical Week list matching the current local weekday */
    let cards:             [KanbanCard]  /* Non-divider cards on that list                         */
    let entries:           [TodayFocusEntry]
    let groupsBySection:   Bool
    var visibleItemCount:  Int = 4
    let chronological:     Bool
    private var openCards: [KanbanCard]
    {
        entries.map(\.card)
    }

    var includesImportant = false
    var includesBookmarked = false
    var includesUpNext = false
    var filtersChangedAt:  Date? = nil
    var bookmarkedCardIDs: Set<Int> = []
    var importantCardIDs:  Set<Int> = []
    var onChangeFilters:   (Bool, Bool, Bool) -> Void =
    {
        _, _, _ in
    }

    let onToggleCard:    (Int) -> Void /* Toggle local completion state */
    let onOpenCard:      (KanbanCard) -> Void
    let onDeleteCard:    (Int) -> Bool
    let onOpenTodayList: () -> Void /* Open the focused single-list Today view */

    private var isPad: Bool
    {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    @ScaledMetric(relativeTo: .body) private var phoneRowHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var padRowHeight:   CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var phoneTaskSize:  CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var padTaskSize:    CGFloat = 20
    private var rowHeight:                                       CGFloat
    {
        isPad ? padRowHeight : phoneRowHeight
    }

    @Environment(\.displayScale) private var displayScale
    @State private var measuredListingHeight: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsFilterChooser = false
    @State private var showsFilterSummary = false
    @State private var filterChooserDismissedAt: Date?
    private var filterSummaryRequestedAt:        Date?
    {

        guard includesUpNext || includesImportant || includesBookmarked else
        {
            return nil
        }

        return [filtersChangedAt, filterChooserDismissedAt].compactMap
        {
            $0
        } .max()
    }

    private var filterColor: Color
    {

        TodayFocusFilterColor.color(
            upNext: includesUpNext, important: includesImportant,
            bookmarked: includesBookmarked, dark: colorScheme == .dark)
    }

    @State private var deletingCard: KanbanCard?

    @ScaledMetric(relativeTo: .caption) private var headingHeight: CGFloat = 28


    ///
    /// @fcn        TodayFocusSection.beginsGroup
    /// @brief      Check whether an entry begins a visible Focus section
    /// @details    Requires section grouping and a known entry; the first entry or a change from the preceding
    ///             section ID begins a group.
    ///
    /// @param[in]  entry  Focus entry carrying its card and section context
    ///
    /// @return     (Bool) true for the first visible entry or a changed section when grouping is enabled
    ///
    private func beginsGroup(_ entry: TodayFocusEntry) -> Bool
    {

        guard groupsBySection, let index = entries.firstIndex(where:
            {
                $0.id == entry.id
            }) else
        {
            return false
        }

        return index == 0 || entries[index - 1].sectionID != entry.sectionID
    }


    private var rowCapacity: Int
    {

        visibleItemCount == 0 ? max(entries.count, 1) : ((1 ... 12).contains(visibleItemCount) ? visibleItemCount : 4)
    }

    private var visibleHeadingCount: Int
    {
        entries.prefix(rowCapacity).filter
        {
            beginsGroup($0)
        } .count
    }

    private var rowsHeight: CGFloat
    {

        rowHeight * CGFloat(min(entries.count, rowCapacity)) + headingHeight * CGFloat(visibleHeadingCount)
    }

    private var listingCapacity: CGFloat
    {

        rowHeight * CGFloat(rowCapacity) + headingHeight * CGFloat(visibleHeadingCount) + 3 / displayScale
    }

    private var listingHeight: CGFloat
    {

        measuredListingHeight ?? rowsHeight
    }


    private var filterLabel: String?
    {

        let selected = [
            (includesUpNext, "Up Next"), (includesImportant, "Important"), (includesBookmarked, "Bookmarked")
        ]
        .filter
        {
            $0.0
        } .map
        {
            $0.1
        }

        return selected.isEmpty ? nil : selected.joined(separator: " or ")
    }


    private var focusTitle: some View
    {

        Button
        {

            showsFilterChooser = true
        }
        label:
        {

            VStack(alignment: .leading, spacing: 2)
            {

                Text("Today's Focus")
                .font(isPad ? .title2.weight(.semibold) : .title3.weight(.semibold))
                if showsFilterSummary
                {

                    Text(filterLabel ?? "All items").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                }

            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -10)
        .accessibilityLabel("Today's Focus")
        .accessibilityValue(filterLabel ?? "All items")
        .accessibilityHint("Choose Up Next, important, or bookmarked items to show")
        .accessibilityIdentifier("today.focus.filters")
        .popover(isPresented: $showsFilterChooser)
        {

            VStack(alignment: .leading, spacing: 4)
            {

                HStack(spacing: 0)
                {

                    Button
                    {

                        onChangeFilters(false, false, false)
                    }
                    label:
                    {

                        Text("All items")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityValue(filterLabel == nil ? "Selected" : "")
                    if filterLabel == nil
                    {

                        Button
                        {

                            showsFilterChooser = false
                        }
                        label:
                        {

                            Image(systemName: "checkmark")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Close Focus filters")
                        .accessibilityIdentifier("today.focus.filters.close")
                    }

                }
                .buttonStyle(.plain)
                .foregroundStyle(TodayFocusFilterColor.color(dark: colorScheme == .dark))
                Divider()
                Toggle(
                    isOn: Binding(
                        get:
                        {
                            includesUpNext
                        }, set:
                        {
                            onChangeFilters(includesImportant, includesBookmarked, $0)
                        })
                )
                {

                    Text("Up Next").foregroundStyle(
                        TodayFocusFilterColor.color(upNext: true, dark: colorScheme == .dark))
                }

                Toggle(
                    isOn: Binding(
                        get:
                        {
                            includesImportant
                        }, set:
                        {
                            onChangeFilters($0, includesBookmarked, includesUpNext)
                        })
                )
                {

                    Text("Important").foregroundStyle(
                        TodayFocusFilterColor.color(important: true, dark: colorScheme == .dark))
                }

                Toggle(
                    isOn: Binding(
                        get:
                        {
                            includesBookmarked
                        }, set:
                        {
                            onChangeFilters(includesImportant, $0, includesUpNext)
                        })
                )
                {

                    Text("Bookmarked").foregroundStyle(
                        TodayFocusFilterColor.color(bookmarked: true, dark: colorScheme == .dark))
                }

                Text("Show items matching any selection").font(.caption).foregroundStyle(filterColor).padding(.top, 8)
            }
            .toggleStyle(.switch)
            .buttonStyle(.plain)
            .padding(16)
            .frame(idealWidth: 290)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showsFilterChooser)
        {
            wasOpen, isOpen in
            if wasOpen && !isOpen
            {

                if filterLabel != nil
                {

                    filterChooserDismissedAt = .now
                }
                else
                {

                    // An unused filter needs no confirmation after merely inspecting the chooser.
                    filterChooserDismissedAt = nil
                    showsFilterSummary = false
                }

            }

        }
        .task(id: filterSummaryRequestedAt)
        {

            guard let changedAt = filterSummaryRequestedAt else
            {
                showsFilterSummary = false;
                return
            }

            let remaining = 3 - Date.now.timeIntervalSince(changedAt)
            guard remaining > 0 else
            {
                showsFilterSummary = false;
                return
            }

            showsFilterSummary = true
            do
            {
                try await Task.sleep(for: .seconds(remaining))
            }
            catch
            {
                return
            }

            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25))
            {
                showsFilterSummary = false
            }

        }

    }


    private var completionButton: some View
    {

        let completedCount = cards.filter(\.isTitleChecked).count
        return Button(action: onOpenTodayList)
        {

            Text("\(completedCount) of \(cards.count) complete")
            .font(isPad ? .subheadline : .caption)
            .italic()
            .foregroundStyle(filterColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(completedCount) of \(cards.count) complete")
        .accessibilityHint(
            completedCount < cards.count
            ? "Opens today's list at the first unfinished item"
            : "Opens today's completed list"
        )
        .accessibilityIdentifier("today.focus.progress")
    }


    private var focusRows: some View
    {

        List
        {

            ForEach(entries)
            {
                entry in
                let card = entry.card
                VStack(alignment: .leading, spacing: 0)
                {

                    if beginsGroup(entry)
                    {

                        Text(entry.heading ?? (entry.sectionID == nil ? "Before first section" : "Untitled section"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: headingHeight, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    }

                    HStack(spacing: 8)
                    {

                        Button
                        {

                            onToggleCard(card.id)
                        }
                        label:
                        {

                            Image(systemName: card.isTitleChecked ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: isPad ? 48 : 44, height: rowHeight)
                            .contentShape(Rectangle())
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark \(card.word) \(card.isTitleChecked ? "incomplete" : "complete")")
                        .disabled(card.isEditingLocked)

                        Button
                        {

                            onOpenCard(card)
                        }
                        label:
                        {

                            HStack
                            {

                                ItemAppearanceMark(appearance: card.appearance)
                                VStack(alignment: .leading, spacing: 1)
                                {

                                    Text(card.word)
                                    .font(.system(size: isPad ? padTaskSize : phoneTaskSize))
                                    .foregroundStyle(.primary)
                                    .strikethrough(card.isTitleChecked)
                                    .lineLimit(1)
                                    if chronological, let label = entry.scheduleLabel
                                    {

                                        Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }

                                }

                                Spacer(minLength: 8)
                                if let time = entry.previewTimeLabel
                                {

                                    Text(time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                                else
                                {

                                    let hasBookmark = bookmarkedCardIDs.contains(card.id)
                                    HStack(spacing: 3)
                                    {

                                        if hasBookmark
                                        {

                                            Image(systemName: "bookmark.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("Bookmarked")
                                        }

                                        ImportantItemIndicator(cardID: card.id)
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                }

                                Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            }

                            .frame(maxWidth: .infinity, minHeight: rowHeight)
                            .contentShape(Rectangle())
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(card.word)")
                        .accessibilityValue(
                            [
                                entry.previewTime.map
                                {

                                    ($0.isStart ? "Start time " : "Due time ")
                                    + $0.date.formatted(date: .omitted, time: .shortened)
                                },
                                importantCardIDs.contains(card.id) ? "Important" : nil,
                                bookmarkedCardIDs.contains(card.id) ? "Bookmarked" : nil
                            ].compactMap
                            {
                                $0
                            } .joined(separator: ", "))
                    }

                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false)
                {

                    Button
                    {

                        deletingCard = card
                    }
                    label:
                    {

                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                    .accessibilityIdentifier("today.focus.swipeDelete")
                }

            }

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, rowHeight)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: rowsHeight)
    }


    ///
    /// @fcn        TodayFocusSection.body
    /// @brief      Summarize the current weekday list and preview unfinished cards
    /// @details    Displays title-completion progress, distinct empty/all-complete states,
    ///             quick completion controls, and an action to open today's list
    ///
    /// @return     (some View) raised Today focus panel
    /// @pre        cards and openCards describe the supplied list and exclude section dividers
    /// @post       Completion and navigation are delegated to supplied callbacks
    ///
    var body: some View
    {  /* Weekday-list progress and unfinished-card shortcuts */

        VStack(alignment: .leading, spacing: 10)
        {

            ViewThatFits(in: .horizontal)
            {

                HStack(alignment: .firstTextBaseline, spacing: 12)
                {

                    focusTitle.fixedSize()
                    Spacer(minLength: 0)
                    if list != nil
                    {
                        completionButton.fixedSize()
                    }

                }

                VStack(alignment: .leading, spacing: 4)
                {

                    focusTitle
                    if list != nil
                    {
                        completionButton
                    }

                }

            }


            if list != nil
            {

                let completedCount = cards.filter(\.isTitleChecked).count

                ProgressView(value: Double(completedCount), total: Double(max(cards.count, 1)))
                .tint(.accentColor)
                .opacity(cards.isEmpty ? 0 : 1)
                .accessibilityHidden(cards.isEmpty)

                Group
                {

                    if cards.isEmpty
                    {


                        Text("This list is ready for its first card.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    else if openCards.isEmpty
                    {

                        Label(
                            cards.allSatisfy(\.isTitleChecked)
                            ? "Everything on this list is complete"
                            : "No unfinished items match your Focus filters",
                            systemImage: cards.allSatisfy(\.isTitleChecked)
                            ? "checkmark.circle.fill" : "line.3.horizontal.decrease.circle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 40, alignment: .leading)
                        if !cards.allSatisfy(\.isTitleChecked)
                        {

                            Button("Show all items")
                            {
                                onChangeFilters(false, false, false)
                            }
                            .font(.subheadline).frame(minHeight: 44)
                        }

                    }
                    else
                    {

                        focusRows
                        .accessibilityLabel("Today's Focus items")
                    }

                }
                .onGeometryChange(for: CGFloat.self)
                {
                    geometry in
                    geometry.size.height
                }
                action:
                {
                    height in
                    measuredListingHeight = height
                }


                Button(action: onOpenTodayList)
                {

                    Label("Open today", systemImage: "arrow.right")
                    .font(.subheadline)
                    .frame(minHeight: 32)
                }

                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            else
            {

                Text("No list for today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

        }

        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            deletingCard?.presentation == .note ? "Delete Note?" : "Delete Card?",
            isPresented: Binding(
                get:
                {
                    deletingCard != nil
                },
                set:
                {
                    if !$0
                    {
                        deletingCard = nil
                    }

                }
            ),
            presenting: deletingCard
        )
        {
            card in
            Button("Delete", role: .destructive)
            {

                guard
                list?.cards.contains(where:
                    {

                        $0.id == card.id && $0.createdAt == card.createdAt
                    }) == true
                else
                {
                    return
                }

                _ = onDeleteCard(card.id)
                deletingCard = nil
            }

            Button("Cancel", role: .cancel)
            {
                deletingCard = nil
            }

        }
        message:
        {
            card in
            Text("Permanently delete “\(card.word)”? This cannot be undone.")
        }
        .modifier(TodayPanelSurface(backgroundOpacity: 0.5))
        .padding(.bottom, list == nil ? 0 : max(0, listingCapacity - listingHeight))
    }

}


///
/// Hosts a direct Today Focus Card destination
///
/// @section    Purpose
///     Dismisses back to Today and forwards edits to the owning workspace rather than inserting an
///     intermediate Day route.
///
struct TodayFocusCardDetailView: View
{

    @AppStorage(BoardAppearance.weekStorageKey) private var subtitleBoardAppearanceData = Data()


    @State private var keyboardCard: KanbanCard?
    let card:                        KanbanCard
    @Binding var lists:              [KanbanList]
    @Binding var labelLibrary:       LabelLibrary
    @Binding var savedCardIDs:       Set<Int>
    let currentUserName:             String
    let onDelete:                    (Int) -> Bool


    ///
    /// @fcn        TodayFocusCardDetailView.keyboardNavigation
    /// @brief      Build keyboard navigation among current Focus entries
    /// @details    Resolves previous and next candidates from the live Focus context before changing the detail
    ///             selection.
    ///
    /// @param[in]  card  Card or note being inspected or changed
    ///
    /// @return     (CardKeyboardNavigation) available previous and next actions scoped to the current Focus entries
    ///
    private func keyboardNavigation(for card: KanbanCard) -> CardKeyboardNavigation
    {

        let neighbors = CardKeyboardNeighbors.resolve(card, in: lists)
        return CardKeyboardNavigation(
            previous: neighbors.previous == nil
            ? nil :
            {
                keyboardCard = CardKeyboardNeighbors.resolve(card, in: lists).previous
            },
            next: neighbors.next == nil ? nil :
            {
                keyboardCard = CardKeyboardNeighbors.resolve(card, in: lists).next
            })
    }

    var body: some View
    {

        let card = keyboardCard ?? self.card
        NavigationStack
        {

            CardDetailView(
                card: card, labelLibrary: $labelLibrary,
                currentUserName: currentUserName, savedCardIDs: $savedCardIDs,
                onTitleToggle:
                {
                    updated in
                    guard
                    let owner = lists.firstIndex(where:
                        {

                            $0.cards.contains(where:
                                {
                                    $0.id == card.id && $0.createdAt == card.createdAt
                                })
                        }),
                    let index = lists[owner].cards.firstIndex(where:
                        {
                            $0.id == card.id
                        })
                    else
                    {
                        return
                    }

                    guard lists[owner].cards[index].acceptsContentUpdate(updated) else
                    {
                        return
                    }

                    lists[owner].cards[index] = updated
                },
                onArchive:
                {

                    guard
                    let owner = lists.firstIndex(where:
                        {

                            $0.cards.contains(where:
                                {
                                    $0.id == card.id && $0.createdAt == card.createdAt
                                })
                        })
                    else
                    {
                        return
                    }

                    lists[owner].archiveCard(id: card.id)
                },
                onDelete:
                {
                    onDelete(card.id)
                }, listedOnDate: .now
            )
            .id(card.id)
            .environment(\.cardKeyboardNavigation, keyboardNavigation(for: card))
            .environment(\.inheritedSubtitleItalic,
                ((try? BoardAppearance.decodeWeek(subtitleBoardAppearanceData)) ?? BoardAppearance())
                    .resolvedSubtitleItalic(list: lists.first
                    {
                        $0.cards.contains
                        {
                            $0.id == card.id
                        }
                    }?.appearance))
        }

    }

}
