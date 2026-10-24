// --------------------------------------------------------------------------------------------------
// @file       CardDateBrowser.swift
// @brief      Card start-date and due-date calendar browsing
// @details    Projects canonical scheduled content into local days and opens its existing List or
//             Card destination.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Associates a matched card with the list that contains it
///
/// @section    Purpose
///     Preserve routing context for label results
///
struct CalendarCardResult: Identifiable
{


    let cardID:    Int     /* Stable card identity                  */
    let title:     String  /* Card title shown on the selected date */
    let listID:    Int     /* Board list opened when selected       */
    let listTitle: String  /* Containing Board list                 */
    let dateLabel: String  /* Start/due marker for this date        */

    ///
    /// @fcn        CalendarCardResult.id
    /// @brief      Identify a dated-card result
    /// @details    Reuses the underlying card ID within the supplied Board snapshot
    ///
    /// @return     (Int) card identity
    /// @pre        Card IDs are unique within the displayed Board
    /// @post       Card dates and result content remain unchanged
    ///
    var id: Int
    {
        cardID
    }  /* Stable card identity for the destination */

}


///
/// Browses card start and due dates using the user's local calendar
///
/// @section    Purpose
///     Show dated cards by month and route selections to their exact Board records
///
struct TodayCalendarView: View
{


    let lists:           [KanbanList]        /* Current Board snapshot                             */
    let onArchiveCard:   (Int) -> Void       /* Canonical archive callback                         */
    let onDeleteCard:    (Int) -> Bool       /* Confirmed deletion result                          */
    let onOpenBoardCard: (Int, Int) -> Void  /* Navigate using containing list and card identities */

    @State private var displayedMonth =
    Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now       /* Visible month      */
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)  /* Selected local day */

    private let weekdayColumns = Array(
        repeating: GridItem(.flexible(), spacing: 2), count: 7) /* Seven localized calendar columns */

    ///
    /// @fcn        TodayCalendarView.weekdaySymbols
    /// @brief      Order localized weekday headings for the user's calendar
    /// @details    Rotates very-short standalone symbols so the configured first weekday leads
    ///
    /// @return     ([String]) weekday headings in calendar-column order
    /// @post       Calendar preferences are unchanged
    ///
    private var weekdaySymbols: [String]
    {  /* Locale weekday headings ordered by the calendar */

        let calendar = Calendar.current                           /* User's local calendar */
        let symbols = calendar.veryShortStandaloneWeekdaySymbols  /* Locale weekday labels */

        return (0 ..< symbols.count).map
        {
            symbols[(calendar.firstWeekday - 1 + $0) % symbols.count]
        }

    }


    ///
    /// @fcn        TodayCalendarView.monthDays
    /// @brief      Build complete calendar-grid rows for the displayed month
    /// @details    Uses the current calendar's month boundaries and first weekday,
    ///             adding nil placeholders before and after dates to complete seven-column rows
    ///
    /// @return     ([Date?]) grid cells, or an empty array when month metadata cannot be resolved
    /// @post       Displayed month and selection remain unchanged
    ///
    private var monthDays: [Date?]
    {  /* Month grid dates with leading alignment placeholders */

        let calendar = Calendar.current /* User's local calendar                                */

        guard
        let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?
        .start, /* First date in the displayed month         */
        let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth)
        else
        {  /* Valid day numbers for the displayed month */


            return []
        }


        let leadingDays =
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7)
        % 7 /* Empty cells before day one                   */
        var days: [Date?] = Array(
            repeating: nil, count: leadingDays) /* Grid cells assembled after weekday alignment */

        days += dayRange.compactMap
        {
            calendar.date(byAdding: .day, value: $0 - 1, to: monthStart)
        }

        days += Array(repeating: nil, count: (7 - days.count % 7) % 7)

        return days
    }


    ///
    /// @fcn        TodayCalendarView.selectedDayCards
    /// @brief      Resolve cards starting or due on the selected local day
    /// @details    Delegates date comparison and result construction to cards(on:)
    ///
    /// @return     ([CalendarCardResult]) selected-day results in list/card order
    /// @post       Dates and selection remain unchanged
    ///
    private var selectedDayCards: [CalendarCardResult]
    {  /* Cards scheduled for the chosen calendar date */

        cards(on: selectedDate)
    }


    ///
    /// @fcn        TodayCalendarView.body
    /// @brief      Present monthly card-date browsing and selected-day results
    /// @details    Combines month navigation, localized weekday columns, selectable date cells,
    ///             and starting/due cards; result rows route to their containing Board lists
    ///
    /// @return     (some View) paper-backed calendar surface
    /// @post       Date/month controls update local display state; navigation does not edit card dates
    ///
    var body: some View
    {  /* Calendar grid and selected-day card results */


        ZStack
        {

            TodayPaperBackground()

            ScrollView
            {

                VStack(alignment: .leading, spacing: 16)
                {

                    VStack(alignment: .leading, spacing: 4)
                    {

                        Text("Calendar")
                        .font(.largeTitle.weight(.bold))
                        Text("Dates from your existing cards")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14)
                    {

                        HStack
                        {

                            Button
                            {

                                moveMonth(by: -1)
                            }
                            label:
                            {

                                Image(systemName: "chevron.left")
                                .frame(width: 40, height: 40)
                            }

                            .accessibilityLabel("Previous month")

                            Spacer()
                            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                            .font(.headline)
                            Spacer()

                            Button
                            {

                                moveMonth(by: 1)
                            }
                            label:
                            {

                                Image(systemName: "chevron.right")
                                .frame(width: 40, height: 40)
                            }

                            .accessibilityLabel("Next month")
                        }

                        .buttonStyle(.plain)

                        LazyVGrid(columns: weekdayColumns, spacing: 4)
                        {

                            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset)
                            {
                                _, symbol in
                                Text(symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 24)
                            }


                            ForEach(monthDays.indices, id: \.self)
                            {
                                index in
                                if let date = monthDays[index]
                                {  /* Actual date represented by this grid cell */


                                    calendarDayButton(date)
                                }
                                else
                                {

                                    Color.clear.frame(height: 40)
                                }

                            }

                        }

                    }

                    .padding(14)
                    .modifier(TodayPanelSurface())

                    VStack(alignment: .leading, spacing: 10)
                    {

                        Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(.title3.weight(.semibold))

                        if selectedDayCards.isEmpty
                        {


                            Text("No cards with a start or due date on this day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        else
                        {

                            ForEach(selectedDayCards)
                            {
                                result in
                                Button
                                {

                                    onOpenBoardCard(result.listID, result.cardID)
                                }
                                label:
                                {

                                    HStack(alignment: .top, spacing: 12)
                                    {

                                        Image(systemName: "calendar")
                                        .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 3)
                                        {

                                            Text(result.title)
                                            .foregroundStyle(.primary)
                                            Text("\(result.listTitle) · \(result.dateLabel)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }


                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                    }

                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }

                                .buttonStyle(.plain)
                                .modifier(
                                    ContentLifecycleActions(
                                        title: result.title, kind: "Card",
                                        onArchive:
                                        {
                                            onArchiveCard(result.cardID)
                                        },
                                        onDelete:
                                        {
                                            onDeleteCard(result.cardID)
                                        }
                                    ))
                            }

                        }

                    }

                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .modifier(TodayPanelSurface())
                }

                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            .background(.clear)
        }

    }


    ///
    /// @fcn        TodayCalendarView.calendarDayButton(_:)
    /// @brief      Render an accessible calendar date cell
    /// @details    Distinguishes today and the selected day, marks dates containing cards, and
    ///             announces the full date with its dated-card count
    ///
    /// @param[in]  date  Calendar-grid date to represent
    ///
    /// @return     (some View) day-selection button
    ///
    /// @post       Tapping selects the date's local start of day without changing card dates
    ///
    private func calendarDayButton(_ date: Date) -> some View
    {


        let calendar = Calendar.current                                    /* User's local calendar   */
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)  /* Selected day state      */
        let isToday = calendar.isDateInToday(date)                         /* Current day state       */
        let cardCount = cards(on: date).count                              /* Dated cards on this day */

        return Button
        {


            selectedDate = calendar.startOfDay(for: date)
        }
        label:
        {

            VStack(spacing: 3)
            {

                Text(date.formatted(.dateTime.day()))
                .font(.subheadline.weight(isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Circle()
                .fill(cardCount > 0 ? Color.accentColor : .clear)
                .frame(width: 4, height: 4)
            }

            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected ? Color.accentColor.opacity(0.12) : .clear, in: Circle())
            .overlay
            {

                if isToday
                {


                    Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                }

            }

        }

        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(cardCount) dated cards")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }


    ///
    /// @fcn        TodayCalendarView.cards(on:)
    /// @brief      Find active cards starting or due on a local calendar day
    /// @details    Excludes dividers, compares dates with the user's current calendar, and emits
    ///             one result per matching card, including a combined start/due marker
    ///
    /// @param[in]  date  Day whose starting and due cards are requested
    ///
    /// @return     ([CalendarCardResult]) dated-card results in supplied list/card order
    ///
    /// @pre        The caller supplies the intended list partition with Board-unique card IDs
    /// @post       No date, completion, or archived-card data is modified
    ///
    private func cards(on date: Date) -> [CalendarCardResult]
    {


        let calendar = Calendar.current /* User's local calendar */

        return lists.flatMap
        {
            list in
            list.cards.compactMap
            {
                card in
                guard !card.isSectionDivider else
                {


                    return nil
                }


                let starts =
                card.startDateKind.includesDate
                && (card.startDate.map
                    {
                        calendar.isDate($0, inSameDayAs: date)
                    }
                    ?? false) /* Start date marker */
                let due =
                card.dueDateKind.includesDate
                && (card.dueDate.map
                    {
                        calendar.isDate($0, inSameDayAs: date)
                    }
                    ?? false) /* Due date marker   */

                guard starts || due else
                {


                    return nil
                }


                let dateLabel =
                starts && due ? "Starts & due" : (due ? "Due" : "Starts") /* Display-only date meaning */

                return CalendarCardResult(
                    cardID: card.id, title: card.word, listID: list.id, listTitle: list.title, dateLabel: dateLabel)
            }

        }

    }


    ///
    /// @fcn        TodayCalendarView.moveMonth(by:)
    /// @brief      Shift the displayed calendar month and reset day selection
    /// @details    Adds the signed month offset using the current calendar; if date arithmetic
    ///             fails, leaves both displayedMonth and selectedDate unchanged
    ///
    /// @param[in]  amount  Signed number of months to move
    ///
    /// @return     (Void) selects the local start of day for the shifted month date
    ///
    /// @post       Card dates and Board contents remain unchanged
    ///
    private func moveMonth(by amount: Int)
    {


        guard let nextMonth = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth)
        else
        {  /* Month reached by the navigation offset */


            return
        }


        displayedMonth = nextMonth
        selectedDate = Calendar.current.startOfDay(for: nextMonth)
    }

}
