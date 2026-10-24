// --------------------------------------------------------------------------------------------------
// @file       TodayFocus.swift
// @brief      Derived Focus entries, filtering, and direct detail access
// @details    Combines configured selection sources and section context while preserving personal
//             importance and caller-specific return routes. Gives item taps a soft selection glow,
//             icon-based completion, and guarded in-place editing of visible schedule values.
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

    var onRemoveBookmark: (Int) -> Void =
    {
        _ in
    }

    var onUpdateDate: (KanbanCard, Bool) -> Bool =
    {
        _, _ in false
    }

    let onToggleCard:    (Int) -> Void /* Toggle local completion state */
    let onOpenCard:      (KanbanCard) -> Void
    let onDeleteCard:    (Int) -> Bool
    let onOpenTodayList: () -> Void /* Open the focused single-list Today view */

    ///
    /// @fcn        TodayFocusSection.focusDateControl
    /// @brief      Open a Focus date independently of Card navigation
    /// @details    Preserves the surrounding label styling, consumes the date tap, and leaves
    ///             locked items display-only. The section owns the editor across row reordering.
    /// @param[in]  label   Visible date or time text
    /// @param[in]  card    Item whose selected date will be edited
    /// @param[in]  isStart Whether to edit its start rather than due date
    /// @return     (some View) an accessible in-place schedule control
    ///
    private func focusDateControl(_ label: String, card: KanbanCard, isStart: Bool) -> some View
    {
        Button
        {
            editsStartDate = isStart
            editingDateCard = card
        }
        label:
        {
            Text(label)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .highPriorityGesture(TapGesture().onEnded
        {
            guard !card.isEditingLocked else
            {
                return
            }
            editsStartDate = isStart
            editingDateCard = card
        })
        .disabled(card.isEditingLocked)
        .accessibilityLabel("Edit \(isStart ? "start date" : "due date") for \(card.word)")
        .accessibilityValue(label)
        .accessibilityIdentifier("today.focus.\(isStart ? "startDate" : "dueDate").\(card.id)")
    }


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
    @State private var showsFilterChooser = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSelectionContext = true
    @State private var contextRevision = UUID()
    private var filterColor: Color
    {

        TodayFocusFilterColor.color(
            upNext: includesUpNext, important: includesImportant,
            bookmarked: includesBookmarked, dark: colorScheme == .dark)
    }

    @State private var selectedFocusCard: KanbanCard?  /* Pending item retained during visible tap feedback */
    @State private var editingDateCard: KanbanCard?
    @State private var editsStartDate = true
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

    }


    ///
    /// @fcn        TodayFocusSection.showsSchedule
    /// @brief      Keep time and whole-day progress tied to time-aware Focus selections
    /// @details    All items is represented by no active filter flags; Up Next also enables
    ///             schedule information when combined with other selection sources.
    /// @return     (Bool) whether time and whole-list progress belong in this Focus presentation
    ///
    private var showsSchedule: Bool
    {

        TodayFocusPresentation.showsSchedule(important: includesImportant, bookmarked: includesBookmarked,
                                            upNext: includesUpNext)
    }


    private var completionButton: some View
    {

        let completedCount = cards.filter(\.isTitleChecked).count
        return Button(action: onOpenTodayList)
        {

            Text("\(completedCount) of \(cards.count) complete")
            .font(isPad ? .subheadline : .caption)
            .italic()
            .foregroundStyle(.primary.opacity(0.72))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today’s list: \(completedCount) of \(cards.count) complete")
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

                            TodayFocusItemMark(card: card)
                            .frame(width: isPad ? 48 : 44, height: rowHeight)
                            .contentShape(Rectangle())
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark \(card.word) \(card.isTitleChecked ? "incomplete" : "complete")")
                        .accessibilityValue(card.isTitleChecked ? "Completed" : "Not completed")
                        .accessibilityIdentifier("today.focus.completion.\(card.id)")
                        .disabled(card.isEditingLocked)

                        Button
                        {

                            selectedFocusCard = card
                        }
                        label:
                        {

                            HStack
                            {

                                VStack(alignment: .leading, spacing: 1)
                                {

                                    Text(card.word)
                                    .font(.system(size: isPad ? padTaskSize : phoneTaskSize, weight: .medium))
                                    .foregroundStyle(card.isTitleChecked ? Color.secondary : Color.primary)
                                    .italic(card.isTitleChecked)
                                    .strikethrough(card.isTitleChecked)
                                    .lineLimit(1)

                                }

                                Spacer(minLength: 8)
                                if showsSchedule, let time = entry.previewTimeLabel
                                {

                                    focusDateControl(time, card: card, isStart: entry.previewTime?.isStart == true)
                                    .font(.caption)
                                    .foregroundStyle(.primary.opacity(0.72))
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

                                            Button
                                            {
                                                onRemoveBookmark(card.id)
                                            }
                                            label:
                                            {
                                                Image(systemName: "bookmark.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(minWidth: 28, minHeight: 40)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .highPriorityGesture(TapGesture().onEnded
                                            {
                                                onRemoveBookmark(card.id)
                                            })
                                            .accessibilityLabel("Remove bookmark from \(card.word)")
                                            .accessibilityIdentifier("today.focus.bookmark.\(card.id)")
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

                        .buttonStyle(TodayFocusSelectionStyle(isSelected: selectedFocusCard?.id == card.id))
                        .accessibilityLabel("Open \(card.word)")
                        .accessibilityValue(
                            [
                                (showsSchedule ? entry.previewTime : nil).map
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
        .task(id: selectedFocusCard?.id)
        {
            guard let selected = selectedFocusCard else
            {
                return
            }

            do
            {
                try await Task.sleep(for: .milliseconds(400))
            }
            catch
            {
                return
            }

            guard !Task.isCancelled,
                  let current = entries.first(where: { $0.card.id == selected.id })?.card
            else
            {
                selectedFocusCard = nil
                return
            }

            onOpenCard(current)
            selectedFocusCard = nil
        }
        .onDisappear
        {
            selectedFocusCard = nil
        }
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
                    if list != nil && showsSchedule
                    {
                        completionButton.fixedSize()
                    }

                }

                VStack(alignment: .leading, spacing: 4)
                {

                    focusTitle
                    if list != nil && showsSchedule
                    {
                        completionButton
                    }

                }

            }


            if list != nil
            {

                if showsSelectionContext
                {
                    Text(TodayFocusPresentation.context(important: includesImportant, bookmarked: includesBookmarked,
                                                        upNext: includesUpNext, chronological: chronological))
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.focus.context")
                        .transition(.opacity)
                }

                Divider().accessibilityHidden(true)

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

                    Label("See today’s list", systemImage: "arrow.right")
                    .font(.system(.subheadline, design: .serif).italic().weight(.medium))
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
        .sheet(item: $editingDateCard)
        {
            card in
            CardDateEditorSheet(
                title: editsStartDate ? "Start date" : "Due date",
                date: editsStartDate ? card.startDate : card.dueDate,
                kind: editsStartDate ? card.startDateKind : card.dueDateKind
            )
            {
                value, kind in
                var edited = card
                if editsStartDate
                {
                    edited.startDate = value
                    edited.startDateKind = value == nil ? .date : kind
                }
                else
                {
                    edited.dueDate = value
                    edited.dueDateKind = value == nil ? .date : kind
                }
                return onUpdateDate(edited, editsStartDate)
            }
            .presentationDetents([.large])
            .databaseActivityOverlay()
        }
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
        .onChange(of: filterLabel)
        {
            _, _ in
            contextRevision = UUID()
        }
        .onChange(of: chronological)
        {
            _, _ in
            contextRevision = UUID()
        }
        .onChange(of: showsFilterChooser)
        {
            wasOpen, isOpen in
            if wasOpen && !isOpen
            {
                contextRevision = UUID()
            }
        }
        .task(id: contextRevision)
        {
            showsSelectionContext = true
            do
            {
                try await Task.sleep(for: .seconds(3))
            }
            catch
            {
                return
            }
            guard !Task.isCancelled else
            {
                return
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6))
            {
                showsSelectionContext = false
            }
        }
        .modifier(TodayPanelSurface(backgroundOpacity: 0.82))
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
            .environment(\.studioCardSurface,
                lists.first { $0.cards.contains { $0.id == card.id } }?.appearance?.studioCardSurface
                ?? ((try? BoardAppearance.decodeWeek(subtitleBoardAppearanceData)) ?? BoardAppearance()).studioCardSurface)
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


///
/// Applies an in-place Focus schedule edit to its current workspace record
///
/// @section    Purpose
///     Resolves identity and the current editing lock at save time, then merges only the chosen
///     date into live content. Ordinary List assignment retains the existing edit-history behavior.
///
enum TodayFocusDateUpdate
{


    ///
    /// @fcn        TodayFocusDateUpdate.apply
    /// @brief      Merge a selected start or due value into the current Card
    /// @details    Rejects deleted, replaced, archived-list, and locked records. Unrelated content
    ///             and the other date remain current even when the editor began with an old snapshot.
    /// @param[in]  edited   Snapshot carrying the edited date and precision
    /// @param[in]  isStart  Whether the edited value is the start date rather than the due date
    /// @param[in,out] lists Live active workspace lists receiving the accepted edit
    /// @return     (Bool) true when the current record accepts the schedule update
    ///
    static func apply(_ edited: KanbanCard, isStart: Bool, to lists: inout [KanbanList]) -> Bool
    {

        guard let owner = lists.firstIndex(where:
            {

                !$0.isArchived && $0.cards.contains
                {

                    $0.id == edited.id && $0.createdAt == edited.createdAt
                }

            }), let index = lists[owner].cards.firstIndex(where:
            {
                $0.id == edited.id
            })
        else
        {

            return false
        }

        var current = lists[owner].cards[index]
        guard !current.isEditingLocked else
        {

            return false
        }

        if isStart
        {

            current.startDate = edited.startDate
            current.startDateKind = edited.startDate == nil ? .date : edited.startDateKind
        }

        else
        {

            current.dueDate = edited.dueDate
            current.dueDateKind = edited.dueDate == nil ? .date : edited.dueDateKind
        }

        lists[owner].cards[index] = current
        return true
    }

}


///
/// Gives Focus items a compact visual identity and completion state
///
/// @section    Purpose
///     Uses picture previews or custom icons when configured, otherwise the item's standard
///     type symbol. A small completion badge preserves that identity when checked; the row
///     supplies the completion button separately from title navigation and trailing actions.
///
private struct TodayFocusItemMark: View
{

    let card: KanbanCard
    @ScaledMetric(relativeTo: .body) private var markSize: CGFloat = 18


    ///
    /// @fcn        TodayFocusItemMark.body
    /// @brief      Render a compact picture, custom symbol, or default item-type symbol
    /// @details    Matches picture-mode List previews and honors custom icon colors. Completed
    ///             items retain their artwork with a check badge. The enclosing button owns the
    ///             accessible completion label and action.
    /// @return     (some View) a consistently sized mark subordinate to the item title
    ///
    var body: some View
    {
        Group
        {
            if card.displayFormat == .picture, let attachment = card.coverAttachment
            {
                CardCoverPreview(attachment: attachment, height: markSize)
                .frame(width: markSize, height: markSize)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            else
            {
                Image(systemName: card.appearance?.icon?.rawValue
                    ?? (card.presentation == .note ? ItemDisplayFormat.note : .card).symbol)
                .font(.system(size: markSize - 3, weight: .regular))
                .foregroundStyle(card.appearance?.iconColor?.color ?? Color.secondary)
            }
        }
        .frame(width: markSize, height: markSize)
        .overlay(alignment: .bottomTrailing)
        {
            if card.isTitleChecked
            {
                Image(systemName: "checkmark.circle.fill")
                .font(.system(size: markSize * 0.65, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .background(Circle().fill(Color(.systemBackground)))
                .offset(x: 4, y: 4)
            }
        }
        .accessibilityHidden(true)
    }
}


///
/// Gives Today Focus item selection a brief warm visual response
///
/// @section    Purpose
///     Combines native press state with a short accepted-selection highlight so feedback is
///     visible before navigation. The owner cancels pending navigation when its rows disappear.
///
private struct TodayFocusSelectionStyle: ButtonStyle
{

    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    ///
    /// @fcn        TodayFocusSelectionStyle.makeBody(configuration:)
    /// @brief      Glow behind the selected item’s text and symbol silhouettes
    /// @details    Retains the glow briefly after release until the owner opens the selected Card.
    ///             Alpha-based shadows follow the rendered glyphs, leaving row space transparent.
    ///             Reduce Motion uses an immediate gold glyph tint without an animated glow.
    ///             Decorative layers do not intercept touches or add accessibility elements.
    /// @param[in]  configuration  Native button label and current pressed state
    /// @return     (some View) original item label with transient selection feedback
    ///
    func makeBody(configuration: Configuration) -> some View
    {

        let highlighted = configuration.isPressed || isSelected
        let gold = Color(red: 0.90, green: 0.69, blue: 0.27)
        configuration.label
            .compositingGroup()
            .shadow(color: gold.opacity(highlighted && !reduceMotion ? 0.4 : 0), radius: 2)
            .shadow(color: gold.opacity(highlighted && !reduceMotion ? 0.825 : 0), radius: 6)
            .overlay
            {
                if reduceMotion
                {
                    gold.opacity(highlighted ? 0.55 : 0)
                        .mask(configuration.label)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: highlighted ? 0.08 : 0.4),
                value: highlighted
            )
    }
}
