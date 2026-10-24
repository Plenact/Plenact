// --------------------------------------------------------------------------------------------------
// @file       TodayEncouragement.swift
// @brief      Authored daily encouragement and readable motion
// @details    Selects deterministic local-day slogans and coordinates automatic or manual reading
//             with accessibility preferences.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Supplies a repeating catalog of original encouragements
///
/// @section    Purpose
///     Selects one slogan by local calendar day on a sixty-day cycle for predictable Today
///     presentation.
///
enum TodaySloganCatalog
{


    static let slogans: [String] = [
            "small steps today, bringing your plans to life",
            "a fresh page today, with room for what matters",
            "begin where you are, and grow from here",
            "one kind step forward, one brighter day ahead",
            "breathe in this morning, and begin with hope",
            "your next chapter starts with one small step",
            "make a little space for the life you imagine",
            "let today be a beginning you can believe in",
            "plant a little hope, and give it time to grow",
            "bring a brave heart to a brand new page",
            "a quieter start, a clearer path ahead",
            "choose one good thing, and begin there today",
            "your plans take shape in the steps you take",
            "leave room for wonder in the work of today",
            "let a small beginning open a new possibility",
            "build a day that feels a little more like you",
            "take a deeper breath, then take your next step",
            "give your hopes a little time on the calendar",
            "begin gently today, and let momentum follow",
            "one thoughtful choice can brighten your day",
            "make today a place where your hopes can grow",
            "let yesterday rest, and meet today with care",
            "bring your attention back to what matters now",
            "your future has room for a small step today",
            "find a little courage in the next thing you do",
            "a new morning, a little more room to begin",
            "turn a little intention into something real",
            "let your next step be a promise to yourself",
            "create a little calm, then follow your purpose",
            "give the life you love a little care today",
            "begin again today, with patience on your side",
            "one clear intention, a day of possibilities",
            "leave a little room for joy along the way",
            "your hopes deserve a place in today’s plans",
            "let a gentle reset lead to a meaningful start",
            "build from this moment, one small choice at a time",
            "bring your dreams closer with something small",
            "a little focus today, a little more possibility",
            "choose a steady pace, and make room to grow",
            "this day is yours to shape with care",
            "let the next page hold a little more hope",
            "begin with what matters, and let that guide you",
            "give a small idea the chance to become real",
            "make space for a beginning that feels like you",
            "follow a little hope into your next step",
            "you can begin anew without beginning from nothing",
            "let progress be gentle, and let it be yours",
            "a little care today can change what comes next",
            "bring your best hopes into the everyday",
            "one honest effort, one new reason to believe",
            "let today hold both purpose and breathing room",
            "grow a life you love through the things you choose",
            "a fresh start can be as small as this moment",
            "give yourself room to try a different path",
            "begin with a breath, continue with a little courage",
            "make one small move toward what feels meaningful",
            "let your plans grow with the person you are becoming",
            "there is room in this day for a hopeful beginning",
            "take the next kind step toward a life you love",
            "close today knowing you gave something good a start"
    ]


    ///
    /// @fcn        TodaySloganCatalog.slogan
    /// @brief      Choose the stable slogan for a local calendar day
    /// @details    Uses a fixed Gregorian anchor in the requested time zone and a wrapped day offset so selection
    ///             remains stable across relaunches and daylight-saving changes.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (String) catalog slogan selected for the represented local day
    ///
    static func slogan(on date: Date, calendar: Calendar = .current) -> String
    {

        // A fixed Gregorian anchor keeps rotation stable across relaunches, years, and DST.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let anchor = local.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let days = local.dateComponents([.day], from: anchor, to: local.startOfDay(for: date)).day ?? 0
        let index = ((days % slogans.count) + slogans.count) % slogans.count
        return slogans[index]
    }

}


///
/// Presents Today's brief encouragement
///
/// @section    Purpose
///     Occupies the existing space above Quick capture and uses shared preview behavior for
///     overflowing writing.
///
struct TodaySloganView: View
{


    @State private var showsFullSlogan = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View
    {

        TimelineView(.everyMinute)
        {
            context in
            sloganContent(TodaySloganCatalog.slogan(on: context.date))
        }

    }


    ///
    /// @fcn        TodaySloganView.sloganContent
    /// @brief      Build the interactive Today slogan reader
    /// @details    Provides light or dark styling, swipe-reading accessibility guidance, and a full-text alert on
    ///             tap.
    ///
    /// @param[in]  slogan  Authored slogan text to display
    ///
    /// @return     (some View) the interactive today slogan reader
    ///
    private func sloganContent(_ slogan: String) -> some View
    {

        InteractiveSloganPreview(
            text: slogan,
            textColor: (colorScheme == .dark
                ? Color(red: 0.84, green: 0.76, blue: 0.65)
                : Color(red: 0.40, green: 0.31, blue: 0.23)).opacity(0.55),
            onTap:
            {
                showsFullSlogan = true
            }
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .accessibilityLabel("Today's slogan. " + slogan)
        .accessibilityHint("Swipe left or right to read. Tap to show the full message.")
        .alert("Today's slogan", isPresented: $showsFullSlogan)
        {

            Button("Done", role: .cancel)
            {

            }

        }
        message:
        {

            Text(slogan)
        }

    }

}


///
/// Calculates horizontal positions for slogan motion
///
/// @section    Purpose
///     Uses elapsed time and measured extents to support looping movement and smooth continuation
///     after manual dragging.
///
enum TodaySloganMotion
{


    ///
    /// @fcn        TodaySloganMotion.position
    /// @brief      Calculate the slogan's looping horizontal position
    /// @details    Moves at 35.1 points per second, wraps after the trailing edge leaves view, and restarts fully
    ///             offscreen manual positions at the right edge.
    ///
    /// @param[in]  elapsed    Elapsed time in seconds since the current animation or launch anchor
    /// @param[in]  start      Starting horizontal position or original vertical scroll offset in points
    /// @param[in]  viewport   Viewport extent in points along the relevant scroll axis
    /// @param[in]  textWidth  Measured width of the slogan text in points
    ///
    /// @return     (CGFloat) looped horizontal text origin in points
    ///
    static func position(elapsed: TimeInterval, start: CGFloat, viewport: CGFloat, textWidth: CGFloat) -> CGFloat
    {

        let distance = viewport + textWidth
        guard distance > 0 else
        {
            return 0
        }

        guard elapsed > 0 else
        {
            return start
        }

        // When released completely offscreen, restart at the invisible right edge
        // after the reading pause instead of spending minutes crossing blank space.
        let resumeStart = start > viewport || start < -textWidth ? viewport : start
        let proposed = resumeStart - elapsed * 35.1
        if proposed >= -textWidth
        {
            return proposed
        }

        return viewport - (-textWidth - proposed).truncatingRemainder(dividingBy: distance)
    }


    ///
    /// @fcn        TodaySloganMotion.draggedPosition
    /// @brief      Apply unrestricted horizontal slogan dragging
    /// @details    Adds the gesture translation to the captured start; viewport and text width do not constrain
    ///             manual reading movement.
    ///
    /// @param[in]  start        Starting horizontal position or original vertical scroll offset in points
    /// @param[in]  translation  Horizontal gesture displacement from its captured start
    /// @param[in]  viewport     Viewport extent in points along the relevant scroll axis
    /// @param[in]  textWidth    Measured width of the slogan text in points
    ///
    /// @return     (CGFloat) starting horizontal position plus gesture translation
    ///
    static func draggedPosition(start: CGFloat, translation: CGFloat, viewport: CGFloat, textWidth: CGFloat) -> CGFloat
    {

        start + translation
    }

}


///
/// Supports automatic and manual slogan reading
///
/// @section    Purpose
///     Uses elapsed-time positions so dragging begins at the visible location and automatic
///     movement resumes after the reading pause.
///
struct InteractiveSloganPreview: View
{


    let text:      String
    let textColor: Color
    let onTap:     () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var textWidth: CGFloat = 0
    @State private var visible = false
    @State private var anchorDate = Date()
    @State private var anchorOffset:  CGFloat? = nil
    @State private var dragStart:     CGFloat? = nil
    @State private var draggedOffset: CGFloat? = nil


    ///
    /// @fcn        InteractiveSloganPreview.position
    /// @brief      Resolve the slogan's manual or automatic position
    /// @details    Prefers an active drag offset and otherwise applies elapsed-time motion from the retained anchor
    ///             with the initial reading pause.
    ///
    /// @param[in]  date   Represented date for the operation
    /// @param[in]  width  Available horizontal extent in points
    ///
    /// @return     (CGFloat) active drag offset or the calculated automatic text origin
    ///
    private func position(at date: Date, width: CGFloat) -> CGFloat
    {

        if let draggedOffset
        {
            return draggedOffset
        }

        let start = anchorOffset ?? width
        let elapsed = max(0, date.timeIntervalSince(anchorDate) - (anchorOffset == nil ? 0.4 : 0))
        return TodaySloganMotion.position(elapsed: elapsed, start: start, viewport: width, textWidth: textWidth)
    }


    var body: some View
    {

        Group
        {

            if reduceMotion || typeSize.isAccessibilitySize
            {

                Button(action: onTap)
                {
                    Text(text).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            else
            {

                Text(text).lineLimit(1).hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay
                {

                    GeometryReader
                    {
                        geometry in
                        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !visible || dragStart != nil))
                        {

                        timeline in
                            Text(text).fixedSize(horizontal: true, vertical: false)
                            .background
                            {

                                GeometryReader
                                {
                                    measured in
                                    Color.clear.preference(
                                        key: PreviewTextWidthKey.self, value: measured.size.width)
                                }

                            }
                            .offset(x: position(at: timeline.date, width: geometry.size.width))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onTap)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 10)
                            .onChanged
                            {
                                value in
                                guard abs(value.translation.width) > abs(value.translation.height) else
                                {

                                    return
                                }

                                if dragStart == nil
                                {

                                    dragStart = position(at: Date(), width: geometry.size.width)
                                }

                                draggedOffset = TodaySloganMotion.draggedPosition(
                                    start: dragStart ?? 0,
                                    translation: value.translation.width, viewport: geometry.size.width,
                                    textWidth: textWidth)
                            }
                            .onEnded
                            {
                                _ in
                                guard let draggedOffset else
                                {
                                    return
                                }

                                anchorOffset = draggedOffset
                                anchorDate = Date().addingTimeInterval(1)
                                self.draggedOffset = nil
                                dragStart = nil
                            })
                    }

                }
                .clipped()
                .onPreferenceChange(PreviewTextWidthKey.self)
                {
                    textWidth = $0
                }
                .modifier(PreviewVisibility(visible: $visible))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction
                {
                    onTap()
                }

            }

        }
        .font(.system(size: 27, design: .serif).italic())
        .foregroundStyle(textColor)
        .onChange(of: text)
        {
            _, _ in
            anchorDate = Date();
            anchorOffset = nil;
            dragStart = nil;
            draggedOffset = nil
        }

    }

}
