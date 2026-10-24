// --------------------------------------------------------------------------------------------------
// @file       DayScheduleOverview.swift
// @brief      Read-only planned-time and Day schedule summaries
// @details    Derives task duration and completion categories without treating planned task-hours
//             as tracked elapsed time.
//
// --------------------------------------------------------------------------------------------------
import Foundation
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Determines whether a dated List receives Today's highlight
///
/// @section    Purpose
///     Uses calendar-day comparison and excludes Lists without an assigned date.
///
enum WeekDayHighlight
{


    ///
    /// @fcn        WeekDayHighlight.isToday
    /// @brief      Determine whether an assigned list date is today
    /// @details    Uses the supplied calendar's day comparison; an unassigned date never receives the highlight.
    ///
    /// @param[in]  assignedDate  Calendar date assigned to the list, or nil for an undated list
    /// @param[in]  now           Reference time used instead of an implicit clock read
    /// @param[in]  calendar      Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (Bool) true if the assigned date falls on the same local day as the reference time
    ///
    static func isToday(_ assignedDate: Date?, now: Date, calendar: Calendar) -> Bool
    {

        guard let assignedDate else
        {
            return false
        }

        return calendar.isDate(assignedDate, inSameDayAs: now)
    }

    static let gold = Color(red: 0.72, green: 0.49, blue: 0.12)
}


///
/// Presents a read-only Day schedule overview
///
/// @section    Purpose
///     Summarizes planned time above scrollable content without replacing restored Day position or
///     first-task navigation.
///
struct DayScheduleOverview: View
{


    let cards:    [KanbanCard]
    let labels:   LabelLibrary
    let day:      Date
    var calendar: Calendar = .current
    @State private var showsDetails = false
    @State private var showsPlan = false
    @AppStorage(DailyPlanStore.key) private var planData = Data()
    private var summary: DayTimeDistribution
    {

        DayTimeDistribution(cards: cards, labels: labels, day: day, calendar: calendar)
    }

    private var intention: String
    {

        ((try? DailyPlanStore.load().plans[PlanningDate.key(day, calendar: calendar)]?.intention) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var planTitle: String
    {

        calendar.isDateInToday(day) ? "Open today’s plan" : "Open day’s plan"
    }

    var body: some View
    {

        let data = summary
        VStack(alignment: .leading, spacing: 12)
        {

            Text(calendar.isDateInToday(day) ? "The day you’re shaping" : "Your day at a glance")
            .font(.headline).accessibilityAddTraits(.isHeader)
            if !intention.isEmpty
            {
                Text(intention).font(.subheadline).lineLimit(3)
            }

            Button
            {

                showsDetails = true
            }
            label:
            {

                ViewThatFits(in: .horizontal)
                {

                    HStack(spacing: 16)
                    {

                        chart(data);
                        legend(data)
                    }

                    VStack(alignment: .leading, spacing: 12)
                    {

                        chart(data);
                        legend(data)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Planned time by tag, " + DayTimeDistribution.durationLabel(data.total))
            .accessibilityHint("Opens time allocation and completion details")
            if data.total > 0
            {

                Text("Outer ring · planned time completed")
                .font(.caption).foregroundStyle(.secondary)
            }

            Text("\(data.completedCount) of \(data.taskCount) tasks complete")
            .font(.subheadline).foregroundStyle(.secondary)
            Button(planTitle, systemImage: "arrow.right", action:
                {
                    showsPlan = true
                })
            .font(.subheadline).frame(minHeight: 44)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showsPlan)
        {
            TodayPlanView(date: day, calendar: calendar)
        }
        .sheet(isPresented: $showsDetails)
        {

            NavigationStack
            {

                List
                {

                    Section("Planned task-hours by tag")
                    {

                        ForEach(data.segments)
                        {
                            segment in
                            VStack(alignment: .leading, spacing: 5)
                            {

                                Label(segment.title, systemImage: "circle.fill").foregroundStyle(segment.color.color)
                                Text(
                                                                                                "\(DayTimeDistribution.durationLabel(segment.planned)) planned · \(DayTimeDistribution.durationLabel(segment.completed)) complete"
                                )
                                .font(.subheadline)
                                ProgressView(value: segment.completed, total: max(segment.planned, 1)).tint(
                                    segment.color.color)
                            } .padding(.vertical, 4)
                        }

                        if data.segments.isEmpty
                        {

                            Text("Add start and end times to tasks to see their planned distribution.")
                        }

                    }

                    Section("What this means")
                    {

                        Text(
                                                                        "Completion is the planned duration of tasks you’ve checked off—not time tracked or elapsed."
                        )
                        Text(
                                                                        "Tasks with multiple tags divide their duration equally. Untagged tasks are Uncategorized. Notes and section headings are excluded."
                        )
                        Text(
                                                                        "\(data.untimedCount) tasks have no valid timed interval on this day. They count in task progress, not in the ring."
                        )
                        Text(
                                                                        "Intervals crossing midnight contribute only the portion on this day. Equal start and end times do not imply 24 hours."
                        )
                        if data.hasOverlaps
                        {

                            Text("Some tasks overlap. Totals are planned task-hours and may exceed the time available.")
                        }

                    }

                }
                .navigationTitle("Your planned time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar
                {
                    ToolbarItem(placement: .confirmationAction)
                    {
                        Button("Done")
                        {
                            showsDetails = false
                        }

                    }

                }

            }

        }

    }


    ///
    /// @fcn        DayScheduleOverview.chart
    /// @brief      Draw planned tag distribution and completion arcs
    /// @details    Uses segment shares of planned time for the main ring and completed planned time for the thin
    ///             outer ring; the accompanying legend supplies accessible text.
    ///
    /// @param[in]  data  Encoded input or media bytes
    ///
    /// @return     (some View) draw planned tag distribution and completion arcs
    ///
    private func chart(_ data: DayTimeDistribution) -> some View
    {

        ZStack
        {

            Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 20)
            if data.total > 0
            {

                ForEach(data.segments)
                {
                    segment in
                    let start = data.segments.prefix
                    {
                        $0.id != segment.id
                    } .reduce(0)
                    {
                        $0 + $1.planned
                    }
                    / data.total
                    let end = start + segment.planned / data.total
                    let gap = min(0.004, (end - start) / 4)
                    Circle().trim(from: start + gap, to: end - gap)
                    .stroke(segment.color.color, style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                    Circle().trim(from: start + gap, to: end - gap)
                    .stroke(segment.color.color.opacity(0.18), lineWidth: 4).padding(-16)
                    if segment.completed > 0
                    {

                        Circle().trim(from: start + gap, to: min(end - gap, start + segment.completed / data.total))
                        .stroke(segment.color.color, lineWidth: 4).padding(-16)
                    }

                }
                .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2)
            {

                Text(DayTimeDistribution.durationLabel(data.total)).font(.headline)
                Text("planned").font(.caption).foregroundStyle(.secondary)
            }

        }
        .padding(19).frame(width: 148, height: 148)
        .accessibilityHidden(true)
    }


    ///
    /// @fcn        DayScheduleOverview.legend
    /// @brief      Summarize the leading planned-time categories
    /// @details    Shows up to three tag totals, an additional-tag count, and an empty-state prompt when no timed
    ///             work is available.
    ///
    /// @param[in]  data  Encoded input or media bytes
    ///
    /// @return     (some View) summarize the leading planned-time categories
    ///
    private func legend(_ data: DayTimeDistribution) -> some View
    {

        VStack(alignment: .leading, spacing: 7)
        {

            if data.total == 0
            {

                Text("Make room for your day").font(.subheadline)
                Text("Add start and end times to see your planned balance.").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(data.segments.prefix(3))
            {
                segment in
                HStack(spacing: 5)
                {

                    Circle().fill(segment.color.color).frame(width: 7, height: 7)
                    Text(segment.title).lineLimit(1)
                    Text(DayTimeDistribution.durationLabel(segment.planned)).foregroundStyle(.secondary)
                } .font(.caption)
            }

            if data.segments.count > 3
            {

                Text("+\(data.segments.count - 3) tags").font(.caption).foregroundStyle(.secondary)
            }

            Text("Time & completion details").font(.caption).foregroundStyle(.tint)
        }
        .frame(minWidth: 120, alignment: .leading)
    }

}


///
/// Derives a read-only Day time distribution
///
/// @section    Purpose
///     Counts planned task durations and completion by category, keeping untimed Cards and Notes
///     distinct from tracked time.
///
struct DayTimeDistribution
{


    ///
    /// Represents one category in the Day's planned-time distribution
    ///
    /// @section    Purpose
    ///     Keeps category identity and color alongside planned and completed task durations for
    ///     read-only schedule summaries.
    ///
    struct Segment: Identifiable
    {


        let id:        String
        let title:     String
        let color:     KanbanLabelColor
        var planned:   TimeInterval
        var completed: TimeInterval
    }

    let segments:       [Segment]
    let taskCount:      Int
    let completedCount: Int
    let untimedCount:   Int
    let hasOverlaps:    Bool
    var total:          TimeInterval
    {
        segments.reduce(0)
        {
            $0 + $1.planned
        }

    }

    var completedTime: TimeInterval
    {
        segments.reduce(0)
        {
            $0 + $1.completed
        }

    }


    ///
    /// @fcn        DayTimeDistribution.durationLabel
    /// @brief      Format a duration as a compact hour-minute label
    /// @details    Rounds seconds to the nearest minute and omits zero hour or minute components for compact chart
    ///             totals and legend entries.
    ///
    /// @param[in]  seconds  Duration in seconds to round to a compact minute-based label
    ///
    /// @return     (String) rounded minute-based duration such as 45m, 2h, or 2h 15m
    ///
    static func durationLabel(_ seconds: TimeInterval) -> String
    {

        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60, remainder = minutes % 60
        return hours == 0 ? "\(remainder)m" : (remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m")
    }


    ///
    /// @fcn        DayTimeDistribution.init
    /// @brief      Aggregate planned and completed time by tag for one day
    /// @details    Uses timed task intervals clipped to the represented calendar day, divides multi-tag time equally,
    ///             and records overlaps as additive planned time rather than actual tracked time.
    ///
    /// @param[in]  cards     Canonical card values in their current order
    /// @param[in]  labels    Label catalog used to resolve stored label IDs
    /// @param[in]  day       Calendar day represented by the result
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (DayTimeDistribution) initialized instance
    ///
    init(cards: [KanbanCard], labels: LabelLibrary, day: Date, calendar: Calendar)
    {

        let tasks = cards.filter
        {
            $0.displayFormat == .card
        }

        taskCount = tasks.count
        completedCount = tasks.filter(\.isTitleChecked).count
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        var buckets: [String: Segment] = [:]
        var intervals: [(Date, Date)] = []
        var untimed = 0


        ///
        /// @fcn        DayTimeDistribution.init.resolve
        /// @brief      Resolve one schedule endpoint for the represented day
        /// @details    Anchors time-only values to the day and excludes date-only values from timed-duration
        ///             calculations.
        ///
        /// @param[in]  date  Represented date for the operation
        /// @param[in]  kind  Date, review, or collection kind selecting this operation's behavior
        ///
        /// @return     (Date?) timed endpoint resolved for the represented day, or nil for an unusable endpoint
        ///
        func resolve(_ date: Date, kind: CardDateKind) -> Date?
        {

            guard kind.includesTime else
            {
                return nil
            }

            if kind == .time
            {

                let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
                return calendar.date(
                    bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0,
                    second: parts.second ?? 0, of: dayStart)
            }

            return date
        }

        for card in tasks
        {

            guard let rawStart = card.startDate, let rawEnd = card.dueDate,
            let start = resolve(rawStart, kind: card.startDateKind),
            var end = resolve(rawEnd, kind: card.dueDateKind)
            else
            {
                untimed += 1;
                continue
            }

            if end < start, card.startDateKind == .time, card.dueDateKind == .time
            {

                end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
            }

            let clippedStart = max(start, dayStart), clippedEnd = min(end, dayEnd)
            guard clippedEnd > clippedStart else
            {
                untimed += 1;
                continue
            }

            intervals.append((clippedStart, clippedEnd))
            let duration = clippedEnd.timeIntervalSince(clippedStart)
            let tags = Set(card.labelIDs).sorted().compactMap
            {
                id in
                labels.labels.first
                {
                    $0.id == id
                }

            }

            let count = max(tags.count, 1)
            let parts: [(String, String, KanbanLabelColor)] =
            tags.isEmpty
            ? [("day.uncategorized", "Uncategorized", .gray)] : tags.map
            {
                ($0.id, $0.name, $0.color)
            }

            for (id, title, color) in parts
            {

                var segment = buckets[id] ?? Segment(id: id, title: title, color: color, planned: 0, completed: 0)
                segment.planned += duration / Double(count)
                if card.isTitleChecked
                {
                    segment.completed += duration / Double(count)
                }

                buckets[id] = segment
            }

        }

        untimedCount = untimed
        segments = buckets.values.sorted
        {
            $0.planned == $1.planned ? $0.id < $1.id : $0.planned > $1.planned
        }

        var latestEnd = Date.distantPast
        var overlap = false
        for (start, end) in intervals.sorted(by:
            {
                $0.0 < $1.0
            })
        {

            if start < latestEnd
            {
                overlap = true
            }

            latestEnd = max(latestEnd, end)
        }

        hasOverlaps = overlap
    }

}
