// --------------------------------------------------------------------------------------------------
// @file       CalendarViews.swift
// @brief      Calendar browsing and Week or Day selection
// @details    Derives visible date content and delegates canonical destination opening without
//             changing the active Week merely by browsing.
//
// --------------------------------------------------------------------------------------------------
import CryptoKit
import SwiftUI


///
/// Browses planning dates and their stored content
///
/// @section    Purpose
///     Coordinates month selection, shared search, and Week routes through injected workspace
///     access.
///
struct PlanningCalendarView: View
{


    var onLeaveForHome: () -> Void =
    {

    }

    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var todayDateFontSize: CGFloat = 17
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var route: PlanningWeekRoute?
    @State private var showsSearch = false


    ///
    /// @fcn        PlanningCalendarView.init
    /// @brief      Initialize calendar navigation around a requested date
    /// @details    Seeds the displayed month and selected local day using Calendar.current and retains the callback
    ///             used when leaving for home.
    ///
    /// @param[in]  initialDate     Date initially selected when the view opens
    /// @param[in]  onLeaveForHome  Callback used after navigation leaves the calendar for home
    ///
    /// @return     (PlanningCalendarView) initialized instance
    ///
    init(initialDate: Date = .now, onLeaveForHome: @escaping () -> Void =
        {

        })
    {

        self.onLeaveForHome = onLeaveForHome
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: initialDate)?.start ?? initialDate)
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
    }

    private var displayCalendar: Calendar
    {
        access?.document.calendar ?? .current
    }

    private var rows: [[Date]]
    {

        let calendar = displayCalendar
        guard let first = calendar.dateInterval(of: .month, for: month)?.start,
        let start = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
        let count = calendar.range(of: .day, in: .month, for: month)?.count
        else
        {
            return []
        }

        let leading = calendar.dateComponents([.day], from: start, to: first).day ?? 0
        let rowCount = (leading + count + 6) / 7
        return (0 ..< rowCount).map
        {
            row in
            (0 ..< 7).compactMap
            {
                calendar.date(byAdding: .day, value: row * 7 + $0, to: start)
            }

        }

    }

    private var symbols: [String]
    {

        let calendar = displayCalendar
        let values = calendar.veryShortStandaloneWeekdaySymbols
        return (0 ..< 7).map
        {
            values[(calendar.firstWeekday - 1 + $0) % 7]
        }

    }


    ///
    /// @fcn        PlanningCalendarView.week
    /// @brief      Resolve a retained week or an unsaved empty preview
    /// @details    Uses the shared calendar document when available and otherwise constructs a week with the display
    ///             calendar without saving it.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (DatedPlanningWeek) retained week or a newly constructed unsaved empty week
    ///
    private func week(on date: Date) -> DatedPlanningWeek
    {

        access?.document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: displayCalendar)
    }


    ///
    /// @fcn        PlanningCalendarView.items
    /// @brief      Look up searchable content for a calendar date
    /// @details    Uses the shared calendar-content selector and returns an empty result when calendar access is
    ///             unavailable.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     ([PlanningSearchResult]) searchable items represented on the requested day, or an empty array
    ///             without access
    ///
    private func items(on date: Date) -> [PlanningSearchResult]
    {

        guard let access else
        {
            return []
        }

        return PlanningCalendarContent.items(on: date, document: access.document, sources: access.searchableItems)
    }


    ///
    /// @fcn        PlanningCalendarView.open
    /// @brief      Navigate to the selected calendar search result
    /// @details    Routes retained-week content within the calendar; library content opens through its owner callback
    ///             before leaving the calendar presentation.
    ///
    /// @param[in]  result  Resolved search or Activity match to render or open
    ///
    /// @return     (Void) no return value
    ///
    private func open(_ result: PlanningSearchResult)
    {

        if let key = result.weekKey, let savedWeek = access?.document.weeks.first(where:
            {
                $0.startKey == key
            })
        {

            route = PlanningWeekRoute(week: savedWeek, dayID: result.listID, cardID: result.card.id)
        }
        else
        {

            access?.openLibraryCard(
                PersonalSavedCardTarget(
                    collectionID: result.collectionID, listID: result.listID, cardID: result.card.id))
            dismiss()
            onLeaveForHome()
        }

    }

    var body: some View
    {

        NavigationStack
        {

            ScrollView
            {

                VStack(alignment: .leading, spacing: 20)
                {

                    monthGrid.dynamicTypeSize(.large)  // Seven columns stay legible; full dates are announced by VoiceOver.
                    daySummary
                }
                .padding(16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background
            {
                Color(.systemGroupedBackground)
                StudioWorkspaceBackground(destination: .calendar)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0)
            {
                calendarHeader
            }
            .modifier(LowerCornerBackShortcut(action:
                    {
                        dismiss()
                    }))
            .modifier(
                PlanningSharedSearchPresentation(
                    isPresented: $showsSearch,
                    onLeaveForHome:
                    {

                        dismiss();
                        onLeaveForHome()
                    })
            )
            .fullScreenCover(item: $route)
            {
                route in
                PlanningCalendarWeekView(
                    week: route.week, initialDayID: route.dayID, initialCardID: route.cardID,
                    onLeaveForHome:
                    {

                        self.route = nil;
                        dismiss();
                        onLeaveForHome()
                    })
            }

        }

    }

    private var calendarHeader: some View
    {

        HStack(spacing: 0)
        {

            Button
            {

                dismiss()
            }
            label:
            {

                WorkspaceHeaderIcon(systemName: "chevron.left")
            }
            .accessibilityLabel("Close Calendar")
            VStack(alignment: .leading, spacing: 4)
            {

                Text("Calendar")
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Text("Plans across time")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button
            {

                showsSearch = true
            }
            label:
            {

                WorkspaceHeaderIcon(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search Plenact")
            Button
            {

                access?.openCurrentWeek();
                dismiss();
                onLeaveForHome()
            }
            label:
            {

                WorkspaceHeaderIcon(systemName: "rectangle.split.3x1")
            }
            .accessibilityLabel("Open This Week")
            Button
            {

                access?.openToday();
                dismiss();
                onLeaveForHome()
            }
            label:
            {

                WorkspaceHeaderIcon(systemName: "sun.max")
            }
            .accessibilityLabel("Open Today")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .background
        {

            LinearGradient(
                colors: [Color(red: 0.10, green: 0.18, blue: 0.25), Color(red: 0.22, green: 0.34, blue: 0.38)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
        }

    }


    private var monthGrid: some View
    {

        VStack(spacing: 10)
        {

            HStack
            {

                Button
                {

                    moveMonth(-1)
                }
                label:
                {

                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button
                {

                    moveMonth(1)
                }
                label:
                {

                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next month")
            }

            HStack(spacing: 2)
            {

                Color.clear.frame(width: 44, height: 24)
                ForEach(Array(symbols.enumerated()), id: \.offset)
                {
                    _, symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }

            }

            ForEach(rows.indices, id: \.self)
            {
                index in
                let dates = rows[index]
                let rowWeek = dates.first.map
                {
                    week(on: $0)
                }

                let isCurrent = rowWeek?.startKey == access?.document.currentWeekKey
                HStack(spacing: 2)
                {

                    if let rowWeek
                    {

                        Button
                        {

                            route = PlanningWeekRoute(week: rowWeek)
                        }
                        label:
                        {

                            Image(
                                systemName: rowWeek.hasContent || isCurrent
                                ? "rectangle.split.3x1.fill" : "rectangle.split.3x1"
                            )
                            .transformEffect(
                                CGAffineTransform(
                                    a: 1, b: 0,
                                    c: rowWeek.hasContent || isCurrent ? 0 : -0.22, d: 1, tx: 0, ty: 0)
                            )
                            .foregroundStyle(
                                isCurrent
                                ? Color.accentColor
                                : (rowWeek.hasContent
                                    ? Color(red: 0.45, green: 0.72, blue: 0.95)
                                    : Color.secondary.opacity(0.4))
                            )
                            .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(
                                                                        "Open \(isCurrent ? "this week" : rowWeek.rangeTitle)\(rowWeek.hasContent ? ", saved content" : ", empty week")"
                        )
                    }

                    ForEach(dates, id: \.self)
                    {
                        date in
                        dayButton(date)
                    }

                }
                .background(
                    isCurrent ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 5)
            {

                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                Text("Items planned or scheduled · highlighted row is this week")
                .font(.caption2).foregroundStyle(.secondary)
            }

        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }


    ///
    /// @fcn        PlanningCalendarView.dayButton
    /// @brief      Build a selectable calendar day cell
    /// @details    Shows the day number, today styling, selection state, and an item-presence dot based on the day's
    ///             searchable content.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (some View) a selectable calendar day cell
    ///
    private func dayButton(_ date: Date) -> some View
    {

        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let count = items(on: date).count
        return Button
        {

            selectedDate = date
        }
        label:
        {

            VStack(spacing: 4)
            {

                Text(date.formatted(.dateTime.day()))
                .font(
                    displayCalendar.isDateInToday(date)
                    ? .system(size: todayDateFontSize, weight: .bold).italic()
                    : .subheadline
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
                Circle().fill(count > 0 ? (selected ? Color.white : Color.accentColor) : .clear).frame(
                    width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
            .opacity(Calendar.current.isDate(date, equalTo: month, toGranularity: .month) ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(count) items")
    }

    private var daySummary: some View
    {

        VStack(alignment: .leading, spacing: 14)
        {

            HStack
            {

                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.headline)
                Spacer()
                Button
                {

                    var target = week(on: selectedDate)
                    let listID = target.prepareDay(selectedDate)
                    route = PlanningWeekRoute(week: target, dayID: listID)
                }
                label:
                {

                    Image(systemName: "arrow.up.right.square").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Open this day's list")
            }

            let selectedItems = items(on: selectedDate)
            if selectedItems.isEmpty
            {

                Text("Nothing planned yet. Open this day to add your first item.").foregroundStyle(.secondary)
            }

            ForEach(selectedItems)
            {
                result in
                Button
                {

                    open(result)
                }
                label:
                {

                    PlanningCalendarResultRow(result: result)
                }
                .buttonStyle(.plain)
                if result.id != selectedItems.last?.id
                {
                    Divider()
                }

            }

        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }


    ///
    /// @fcn        PlanningCalendarView.moveMonth
    /// @brief      Advance the displayed calendar month
    /// @details    Adds the requested month offset and leaves the current month unchanged if calendar arithmetic
    ///             fails.
    ///
    /// @param[in]  amount  Signed calendar-month offset
    ///
    /// @return     (Void) no return value
    ///
    private func moveMonth(_ amount: Int)
    {

        if let next = Calendar.current.date(byAdding: .month, value: amount, to: month)
        {
            month = next
        }

    }

}


///
/// Renders a workspace search match with its source context
///
/// @section    Purpose
///     Shows Card or Note identity, completion state, and owner/List labels without mutating the
///     source item.
///
struct PlanningCalendarResultRow: View
{


    let result: PlanningSearchResult
    var body:   some View
    {

        HStack(alignment: .top, spacing: 12)
        {

            Image(
                systemName: result.card.displayFormat == .card
                ? (result.card.isTitleChecked ? "checkmark.square.fill" : "square") : "doc.text"
            )
            .foregroundStyle(result.card.isTitleChecked ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4)
            {

                Text(result.card.word).foregroundStyle(.primary)
                Text("\(result.collectionTitle) · \(result.listTitle)").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

}


///
/// Selects the Week currently being browsed
///
/// @section    Purpose
///     Changes the displayed Board without silently replacing Today's active calendar Week.
///
struct PlanningWeekSelector: View
{


    let document:                          PlanningCalendarDocument
    let sources:                           [PlanningSearchResult]
    let onSelect:                          (DatedPlanningWeek, Date) -> Void
    @State private var referenceDate:      Date
    @State private var selectedDate:       Date
    @State private var highlightedWeekKey: String
    @State private var isSelecting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    ///
    /// @fcn        PlanningWeekSelector.init
    /// @brief      Seed the week chooser's selected date and highlight
    /// @details    Retains the calendar document, searchable sources, and selection callback while initializing its
    ///             local date and week-key state.
    ///
    /// @param[in]  initialDate      Date initially selected when the view opens
    /// @param[in]  document         Retained document containing the operation's current workspace records
    /// @param[in]  selectedWeekKey  Week-start key initially highlighted in the chooser
    /// @param[in]  sources          Live owner-qualified workspace items used to resolve retained references
    /// @param[in]  onSelect         Callback invoked after the user confirms a selection
    ///
    /// @return     (PlanningWeekSelector) initialized instance
    ///
    init(
        initialDate: Date, document: PlanningCalendarDocument, selectedWeekKey: String,
        sources: [PlanningSearchResult] = [],
        onSelect: @escaping (DatedPlanningWeek, Date) -> Void
    )
    {

        self.document = document
        self.onSelect = onSelect
        self.sources = sources
        _referenceDate = State(initialValue: initialDate)
        _selectedDate = State(initialValue: initialDate)
        _highlightedWeekKey = State(initialValue: selectedWeekKey)
    }


    ///
    /// @fcn        PlanningWeekSelector.choices
    /// @brief      Build retained and nearby unsaved week choices
    /// @details    Adds missing weeks within eight weeks of the reference date to a key-indexed copy and returns
    ///             chronological choices without persisting them.
    ///
    /// @param[in]  document       Retained document containing the operation's current workspace records
    /// @param[in]  referenceDate  Date around which available calendar choices are constructed
    ///
    /// @return     ([DatedPlanningWeek]) chronological retained and nearby unsaved week choices
    ///
    static func choices(document: PlanningCalendarDocument, referenceDate: Date) -> [DatedPlanningWeek]
    {

        var choices = Dictionary(uniqueKeysWithValues: document.weeks.map
            {
                ($0.startKey, $0)
            })
        for offset in -8 ... 8
        {

            guard let date = document.calendar.date(byAdding: .weekOfYear, value: offset, to: referenceDate) else
            {

                continue
            }

            let key = PlanningDate.weekKey(date, calendar: document.calendar)
            if choices[key] == nil
            {
                choices[key] = DatedPlanningWeek.make(for: date, calendar: document.calendar)
            }

        }

        return choices.values.sorted
        {
            $0.startKey < $1.startKey
        }

    }


    ///
    /// @fcn        PlanningWeekSelector.monthDays
    /// @brief      Create a six-week calendar selection grid
    /// @details    Begins at the calendar week containing the month's first day and returns up to forty-two dates;
    ///             unavailable boundaries yield an empty grid.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     ([Date]) six-week grid dates starting at the week containing the month's first day
    ///
    static func monthDays(_ date: Date, calendar: Calendar) -> [Date]
    {

        guard let first = calendar.dateInterval(of: .month, for: date)?.start,
        let gridStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start
        else
        {
            return []
        }

        return (0 ..< 42).compactMap
        {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }

    }

    private var rows: [[Date]]
    {

        let days = Self.monthDays(referenceDate, calendar: document.calendar)
        return stride(from: 0, to: days.count, by: 7).map
        {
            Array(days[$0 ..< min($0 + 7, days.count)])
        }

    }

    private var weekdaySymbols: [String]
    {

        let symbols = document.calendar.veryShortStandaloneWeekdaySymbols
        return (0 ..< 7).map
        {
            symbols[($0 + document.calendar.firstWeekday - 1) % 7]
        }

    }


    ///
    /// @fcn        PlanningWeekSelector.changeMonth
    /// @brief      Move the selector's reference month
    /// @details    Calculates from the first day of the displayed month to avoid drift from differing month lengths.
    ///
    /// @param[in]  amount  Signed calendar-month offset
    ///
    /// @return     (Void) no return value
    ///
    private func changeMonth(_ amount: Int)
    {

        if let first = document.calendar.dateInterval(of: .month, for: referenceDate)?.start,
        let next = document.calendar.date(byAdding: .month, value: amount, to: first)
        {

            referenceDate = next
        }

    }


    ///
    /// @fcn        PlanningWeekSelector.select
    /// @brief      Confirm one calendar date and its containing week
    /// @details    Prevents duplicate selection, briefly updates the highlighted choice with Reduce Motion support,
    ///             then invokes the callback and dismisses.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (Void) no return value
    ///
    private func select(_ date: Date)
    {

        guard !isSelecting else
        {
            return
        }

        isSelecting = true
        let key = PlanningDate.weekKey(date, calendar: document.calendar)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12))
        {

            highlightedWeekKey = key
            selectedDate = date
        }

        let week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: document.calendar)
        Task
        {
            @MainActor in
            do
            {
                try await Task.sleep(for: .milliseconds(140))
            }
            catch
            {
                return
            }

            onSelect(week, date)
            dismiss()
        }

    }

    var body: some View
    {

        NavigationStack
        {

            ScrollView
            {

                VStack(spacing: 12)
                {

                    HStack
                    {

                        Text(referenceDate.formatted(.dateTime.month(.wide).year())).font(.headline)
                        Spacer()
                        Button
                        {

                            changeMonth(-1)
                        }
                        label:
                        {

                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Previous month")
                        Button
                        {

                            changeMonth(1)
                        }
                        label:
                        {

                            Image(systemName: "chevron.right").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Next month")
                    }
                    .foregroundStyle(.primary)
                    HStack(spacing: 0)
                    {

                        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset)
                        {
                            _, symbol in
                            Text(symbol.uppercased()).font(.caption2).foregroundStyle(.secondary).frame(
                                maxWidth: .infinity)
                        }

                    }

                    VStack(spacing: 4)
                    {

                        ForEach(rows.indices, id: \.self)
                        {
                            row in
                            let dates = rows[row]
                            let highlighted =
                            dates.first.map
                            {

                                PlanningDate.weekKey($0, calendar: document.calendar) == highlightedWeekKey
                            }
                            ?? false
                            HStack(spacing: 0)
                            {

                                ForEach(dates, id: \.self)
                                {
                                    date in
                                    let selected = document.calendar.isDate(date, inSameDayAs: selectedDate)
                                    let inMonth = document.calendar.isDate(
                                        date, equalTo: referenceDate, toGranularity: .month)
                                    let count = PlanningCalendarContent.items(
                                        on: date, document: document, sources: sources
                                    ).count
                                    Button
                                    {

                                        select(date)
                                    }
                                    label:
                                    {

                                        VStack(spacing: 2)
                                        {

                                            Text(String(document.calendar.component(.day, from: date)))
                                            .font(.body.weight(selected ? .semibold : .regular))
                                            .foregroundStyle(
                                                selected ? Color.white : (inMonth ? Color.primary : Color.secondary)
                                            )
                                            Circle()
                                            .fill(count > 0 ? (selected ? Color.white : Color.blue) : Color.clear)
                                            .frame(width: 5, height: 5)
                                            .accessibilityHidden(true)
                                        }
                                        .frame(width: 36, height: 44)
                                        .background(selected ? Color.blue : Color.clear, in: Circle())
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                                                                                            "\(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())), \(count) items"
                                    )
                                    .accessibilityHint("Show the week containing this day")
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }

                            }
                            .background(
                                highlighted ? Color.blue.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                        }

                    }

                    HStack(spacing: 5)
                    {

                        Circle().fill(Color.blue).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text("Items planned or scheduled").font(.caption).foregroundStyle(.secondary)
                    }

                    Text("Tap any day to show its week.").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .disabled(isSelecting)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("Choose week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {
                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

            }

        }
        .presentationBackground(Color(.systemBackground))
        .presentationDetents([.height(520), .large])
    }

}


///
/// Presents a draft date selection for Day navigation
///
/// @section    Purpose
///     Retains the initial choice locally and reports the selected date through the caller's
///     callback.
///
struct PlanningDaySelector: View
{


    @State private var date: Date
    let onSelect:            (Date) -> Void
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        PlanningDaySelector.init
    /// @brief      Seed a day chooser with its initial date
    /// @details    Retains the date-selection callback and stores the initial date as editable local state.
    ///
    /// @param[in]  initialDate  Date initially selected when the view opens
    /// @param[in]  onSelect     Callback invoked after the user confirms a selection
    ///
    /// @return     (PlanningDaySelector) initialized instance
    ///
    init(initialDate: Date, onSelect: @escaping (Date) -> Void)
    {

        _date = State(initialValue: initialDate)
        self.onSelect = onSelect
    }

    var body: some View
    {

        NavigationStack
        {

            DatePicker("Choose a day", selection: $date, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Choose day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Show day")
                    {

                        dismiss();
                        onSelect(date)
                    }

                }

            }

        }
        .presentationDetents([.medium, .large])
    }

}
