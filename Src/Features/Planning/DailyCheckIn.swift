// --------------------------------------------------------------------------------------------------
// @file       DailyCheckIn.swift
// @brief      Morning guidance, submitted check-ins, and retained history
// @details    Keeps live priority context separate from historical plan and progress snapshots and
//             saves deliberate submissions through checked callbacks.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Derives morning priority suggestions
///
/// @section    Purpose
///     Projects canonical dated content and existing priorities without moving items automatically.
///
enum TodayVisionSelection
{


    ///
    /// @fcn        TodayVisionSelection.candidates
    /// @brief      Select live candidates for the day's planning vision
    /// @details    Uses calendar access and reference-label exclusions to offer suitable workspace content for
    ///             explicit priority selection.
    ///
    /// @param[in]  date               Represented date for the operation
    /// @param[in]  access             Checked calendar and personal-owner access callbacks
    /// @param[in]  referenceLabelIDs  Label IDs marking reference content that should be excluded from action
    ///                                selection
    /// @param[in]  calendar           Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     ([PlanningSearchResult]) unfinished day-related candidates excluding reference-labeled material
    ///
    static func candidates(
        date: Date, access: PlanningCalendarAccess, referenceLabelIDs: Set<String>, calendar: Calendar
    ) -> [PlanningSearchResult]
    {

        let key = PlanningDate.key(date, calendar: calendar)
        let datedList = access.document.week(for: date, calendar: calendar).flatMap
        {
            week in
            week.dayListIDs[key].map
            {
                (week.id, $0)
            }

        }

        return access.searchableItems.filter
        {
            item in
            guard !item.card.isTitleChecked, Set(item.card.labelIDs).isDisjoint(with: referenceLabelIDs) else
            {

                return false
            }

            let onDay = datedList.map
            {
                $0.0 == item.collectionID && $0.1 == item.listID
            }
            ?? false
            let dated = [item.card.startDate, item.card.dueDate].compactMap
            {
                $0
            } .contains
            {

                calendar.isDate($0, inSameDayAs: date)
            }

            let spanning: Bool
            if let start = item.card.startDate, let end = item.card.dueDate
            {

                spanning =
                calendar.startOfDay(for: start) <= calendar.startOfDay(for: date)
                && calendar.startOfDay(for: end) >= calendar.startOfDay(for: date)
            }
            else
            {

                spanning = false
            }

            return onDay || dated || spanning
        }

    }

}


///
/// Guides morning intention and priority selection
///
/// @section    Purpose
///     Edits the shared Daily plan, offers live workspace candidates, and routes deliberate
///     movement and saving through checked callbacks.
///
struct TodayVisionView: View
{


    @Binding var plan: DailyPlan
    let date:          Date
    let onSave:        () -> Bool
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var showsPicker = false
    @State private var showsNew = false
    @State private var transfer: PlanningSearchResult?
    @State private var transferError = false
    @State private var planSaveFailed = false
    @State private var saving = false
    private var calendar: Calendar
    {

        var result = access?.document.calendar ?? .current
        result.timeZone = TimeZone(identifier: plan.timeZoneID) ?? .current
        return result
    }

    private var sources: [PlanningSearchResult]
    {
        access?.searchableItems ?? []
    }

    private var candidates: [PlanningSearchResult]
    {

        guard let access else
        {
            return []
        }

        let labels = LabelLibraryStore.load().labels.filter
        {

            $0.name.caseInsensitiveCompare("Reference") == .orderedSame || $0.id == LabelLibrary.referenceLabel.id
        }

        return TodayVisionSelection.candidates(
            date: date, access: access, referenceLabelIDs: Set(labels.map(\.id)), calendar: calendar)
    }

    private var table: WorkspaceListDestination?
    {

        WorkspaceBrowseIndex.lists(in: access?.library ?? []).first
        {

            $0.owner.kind == .list && $0.owner.title == "On the Table"
        }

    }


    ///
    /// @fcn        TodayVisionView.isScheduled
    /// @brief      Check whether a vision candidate belongs to the Scheduled list
    /// @details    Matches its owner UUID against active calendar access library collections whose kind is list and
    ///             title is Scheduled.
    ///
    /// @param[in]  source  Live source item with its calendar or Library location
    ///
    /// @return     (Bool) true when the source belongs to the standalone Scheduled list owner
    ///
    private func isScheduled(_ source: PlanningSearchResult) -> Bool
    {

        access?.library.contains
        {
            $0.id == source.collectionID && $0.kind == .list && $0.title == "Scheduled"
        }
        == true
    }


    ///
    /// @fcn        TodayVisionView.select
    /// @brief      Apply the user's vision candidate selection
    /// @details    Updates the working plan's priorities using the source's owner-qualified identity.
    ///
    /// @param[in]  source  Live source item with its calendar or Library location
    ///
    /// @return     (Void) no return value
    ///
    private func select(_ source: PlanningSearchResult)
    {

        let priority = DailyPlanPriority(source)
        if !plan.priorities.contains(where:
            {
                $0.id == priority.id
            })
        {
            plan.priorities.append(priority)
        }

    }


    ///
    /// @fcn        TodayVisionView.advance
    /// @brief      Save vision progress and move to its next step
    /// @details    Uses the accepted plan-save callback before advancing the guided planning flow.
    ///
    /// @return     (Void) no return value
    ///
    private func advance()
    {

        guard !saving else
        {
            return
        }
        ;
        saving = true
        let previousStep = plan.visionStep
        let previousCompletion = plan.visionCompletedAt
        plan.visionStep = step == 2 ? nil : step + 1
        if step == 2
        {
            plan.visionCompletedAt = .now
        }

        if onSave()
        {

            if step == 2
            {
                dismiss()
            }
            else
            {
                step += 1
            }

        }
        else
        {

            plan.visionStep = previousStep
            plan.visionCompletedAt = previousCompletion
            planSaveFailed = true
        }

        saving = false
    }

    var body: some View
    {

        NavigationStack
        {

            Form
            {

                Section
                {

                    VStack(alignment: .leading, spacing: 12)
                    {

                        Text(
                                                                        "\(step + 1) of 3 · "
                                                                        + ["What's already ahead?", "What matters most?", "What's realistic?"] [step]
                        ).font(.headline)
                        Text(date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(
                            .secondary)
                        ProgressView(value: Double(step + 1), total: 3).accessibilityLabel(
                                                                        "Morning plan, step \(step + 1) of 3")
                    } .padding(.vertical, 4)
                }

                if step == 0
                {

                    Section
                    {

                        Text(
                                                                        "A look at today's Day List and items with a start or due date today. Nothing moves unless you confirm it."
                        ).foregroundStyle(.secondary)
                        if candidates.isEmpty
                        {

                            Text(
                                                                                    "Nothing dated for today needs attention. You can choose any priorities in the next step."
                            )
                        }

                        ForEach(candidates)
                        {
                            source in
                            VStack(alignment: .leading, spacing: 8)
                            {

                                Text(source.card.word).font(.headline)
                                Text(source.collectionTitle + " · " + source.listTitle).font(.caption).foregroundStyle(
                                    .secondary)
                                Button(
                                    plan.priorities.contains(where:
                                        {
                                            $0.id == source.id
                                        })
                                    ? "Selected for today" : "Make a priority"
                                )
                                {
                                    select(source)
                                }
                                .disabled(plan.priorities.contains(where:
                                        {
                                            $0.id == source.id
                                        }))
                                if isScheduled(source), table != nil, access?.moveForDailyPlan != nil
                                {

                                    Button("Move to On the Table", systemImage: "arrow.right.circle")
                                    {

                                        transfer = source
                                    }

                                }

                            } .padding(.vertical, 4)
                        }

                    }
                    header:
                    {

                        Text("Ahead today")
                    }

                    if table == nil
                    {

                        Text("On the Table isn't available. You can still plan using items in their current locations.")
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }
                else if step == 1
                {

                    Section
                    {

                        if plan.priorities.isEmpty
                        {

                            Text("A small plan is enough. Choose what deserves your attention.").foregroundStyle(
                                .secondary)
                        }

                        ForEach(plan.priorities)
                        {
                            priority in
                            HStack
                            {

                                Text(priority.resolve(in: sources)?.card.word ?? priority.title)
                                Spacer()
                                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(
                                    true)
                            }

                        }
                        .onDelete
                        {
                            plan.priorities.remove(atOffsets: $0)
                        }
                        .onMove
                        {
                            plan.priorities.move(fromOffsets: $0, toOffset: $1)
                        }

                        Button("Choose priorities", systemImage: "plus.circle")
                        {
                            showsPicker = true
                        }

                        Button("Add priority", systemImage: "square.and.pencil")
                        {
                            showsNew = true
                        }

                    }
                    header:
                    {

                        Text("In the order that matters")
                    }
                    footer:
                    {

                        Text("Use Edit to reorder or remove links. The original items stay where they are.")
                    }

                }
                else
                {

                    Section("Your intention")
                    {

                        TextField("What would make today meaningful?", text: $plan.intention, axis: .vertical)
                        .textInputAutocapitalization(.sentences).lineLimit(2 ... 5)
                    }

                    Section("Make room for")
                    {

                        TextField(
                                                                        "Available time, energy, or other constraints", text: $plan.constraints, axis: .vertical
                        ).textInputAutocapitalization(.sentences).lineLimit(2 ... 5)
                    }

                    Section("Risks or concerns")
                    {

                        TextField("Anything that might get in the way?", text: $plan.concerns, axis: .vertical)
                        .textInputAutocapitalization(.sentences).lineLimit(2 ... 5)
                    }

                    Section
                    {

                        Text("These reflections are optional. Choose a plan that fits the day you have.")
                        .foregroundStyle(.secondary)
                    }

                }

                Section
                {

                    if step > 0
                    {
                        Button("Previous step")
                        {
                            step -= 1
                        }

                    }

                    Button(step == 2 ? "Save today's vision" : "Save and continue", action: advance)
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44).disabled(saving)
                    Text(
                                                            "Each step saves your plan so you can return later. Confirmed moves are saved immediately and are not undone by leaving this flow."
                    ).font(.footnote).foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Today's Vision").navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Plan", systemImage: "chevron.left")
                    {
                        dismiss()
                    } .accessibilityLabel("Back to Today’s Plan")
                }

                ToolbarItemGroup(placement: .confirmationAction)
                {

                    if step == 1
                    {
                        EditButton()
                    }

                }

            }
            .onAppear
            {
                step = min(2, max(0, plan.visionStep ?? 0))
            }
            .sheet(isPresented: $showsPicker)
            {
                DailyPriorityPicker(sources: sources, priorities: $plan.priorities)
            }
            .sheet(isPresented: $showsNew)
            {
                NewDailyPriorityView
                {
                    select($0)
                }

            }
            .confirmationDialog(
                                    "Move to On the Table?",
                                    isPresented: Binding(get:
                                        {
                                            transfer != nil
                                        }, set:
                                        {
                                            if !$0
                                            {
                                                transfer = nil
                                            }

                                        }),
                                    titleVisibility: .visible
            )
            {

                Button("Move original item")
                {

                    guard let source = transfer, let table,
                    let moved = access?.moveForDailyPlan?(source, table.reference)
                    else
                    {
                        transferError = true;
                        transfer = nil;
                        return
                    }

                    let reference = DailyPlanPriority(moved)
                    if let index = plan.priorities.firstIndex(where:
                        {
                            $0.id == source.id
                        })
                    {

                        plan.priorities[index] = reference
                    }
                    else
                    {

                        select(moved)
                    }

                    transfer = nil
                    // The move is already committed; retain the link and report any plan-save failure.
                    if !onSave()
                    {
                        planSaveFailed = true
                    }

                }

                Button("Cancel", role: .cancel)
                {
                    transfer = nil
                }

            }
            message:
            {

                Text(
                                                "Moves ‘\(transfer?.card.word ?? "")’ from Scheduled to On the Table and selects it for today. Dates, times, and details are retained. This does not create a second item."
                )
            }
            .alert("Plan not saved", isPresented: $planSaveFailed)
            {

                Button("OK", role: .cancel)
                {

                }

            }
            message:
            {

                Text(
                                                "Your draft is still open. The saved plan may have changed, or saving failed. Return to your plan to review it and retry. Any confirmed item moves remain saved."
                )
            }
            .alert("Item wasn't moved", isPresented: $transferError)
            {

                Button("OK", role: .cancel)
                {

                }

            }
            message:
            {

                Text(
                                                "The source or destination may have changed, or saving failed. Your original item has been retained. Please try again."
                )
            }

        }

    }

}


///
/// Retains the current daily check-in state
///
/// @section    Purpose
///     Stores the chosen focus, changed-context writing, and optional submission time independently
///     of historical check-in entries.
///
struct DailyCheckIn: Codable, Equatable
{


    var focus: DailyPlanPriority? = nil
    var changed = ""
    var savedAt: Date? = nil
}


///
/// Retains a submitted feeling as values
///
/// @section    Purpose
///     Preserves the original emoji and label even when presets change or the user chooses a custom
///     feeling.
///
struct CheckInMood: Codable, Equatable
{


    let emoji:   String
    let label:   String
    var display: String
    {
        emoji + " " + label
    }


    ///
    /// @fcn        CheckInMood.custom
    /// @brief      Validate a custom emoji-and-label check-in mood
    /// @details    Requires usable mood text and a valid emoji selection and returns nil when the input cannot form a
    ///             supported mood.
    ///
    /// @param[in]  emoji  Emoji text proposed for a reaction or check-in mood
    /// @param[in]  label  User-visible description accompanying the custom mood
    ///
    /// @return     (CheckInMood?) trimmed supported emoji and nonempty label of at most forty characters, or nil for
    ///             invalid input
    ///
    static func custom(emoji: String, label: String) -> CheckInMood?
    {

        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = emoji.unicodeScalars
        let isEmoji =
        scalars.contains
        {
            $0.properties.isEmojiPresentation
        }

        || (scalars.contains
            {
                $0.value == 0xFE0F
            }
            && scalars.contains
            {
                $0.properties.isEmoji
            })
        guard emoji.count == 1, isEmoji, !label.isEmpty, label.count <= 40 else
        {
            return nil
        }

        return CheckInMood(emoji: emoji, label: label)
    }

}


///
/// Defines preset and custom check-in mood choices
///
/// @section    Purpose
///     Maps named choices to retained emoji and label values while leaving none and custom choices
///     unresolved for user input.
///
enum CheckInMoodChoice: String, CaseIterable, Identifiable
{


    case none, great, good, okay, low, struggling, custom
    var id: Self
    {
        self
    }

    var mood: CheckInMood?
    {

        switch self
        {

        case .none, .custom:
            nil
        case .great:
            CheckInMood(emoji: "😊", label: "Great")
        case .good:
            CheckInMood(emoji: "🙂", label: "Good")
        case .okay:
            CheckInMood(emoji: "😐", label: "Okay")
        case .low:
            CheckInMood(emoji: "😔", label: "Low")
        case .struggling:
            CheckInMood(emoji: "😣", label: "Struggling")
        }

    }

    var title: String
    {

        switch self
        {

        case .none:
                    "Not selected"
        case .custom:
                    "Custom…"
        default:
            mood?.display ?? ""
        }

    }

}


///
/// Retains one submitted check-in moment
///
/// @section    Purpose
///     Stores its writing, focus, plan context, and available progress snapshot so subsequent plan
///     edits do not rewrite history.
///
struct DailyCheckInEntry: Codable, Equatable, Identifiable
{


    let id:             String
    let savedAt:        Date
    let changed:        String
    let focus:          DailyPlanPriority?
    let intention:      String
    let constraints:    String
    let concerns:       String
    let priorities:     [DailyPlanPriority]
    let completedTasks: Int?
    let totalTasks:     Int?
    let notes:          Int?
    let unavailable:    Int?
    let legacy:         Bool
    var mood:           CheckInMood? = nil
}


///
/// Provides compatible check-in history projections
///
/// @section    Purpose
///     Exposes retained entries and converts a legacy submitted check-in without inventing
///     unavailable plan or progress snapshots.
///
extension DailyPlan
{


    /// Legacy records have no historical plan/progress snapshot. Do not invent one.
    var checkInHistory: [DailyCheckInEntry]
    {

        if let checkIns
        {
            return checkIns
        }

        guard let saved = checkIn, let timestamp = saved.savedAt else
        {
            return []
        }

        return [
            .init(
                id: "legacy:" + id, savedAt: timestamp, changed: saved.changed,
                focus: saved.focus, intention: "", constraints: "", concerns: "", priorities: [],
                completedTasks: nil, totalTasks: nil, notes: nil, unavailable: nil, legacy: true)
        ]
    }


    ///
    /// @fcn        DailyPlan.recordCheckIn
    /// @brief      Append a snapshot of the current daily check-in
    /// @details    Captures the user's reflection, mood, priorities, and their live completion context at the
    ///             supplied timestamp.
    ///
    /// @param[in]  changed    User-authored reflection describing what changed
    /// @param[in]  sources    Live owner-qualified workspace items used to resolve retained references
    /// @param[in]  timestamp  Explicit timestamp to store or format
    /// @param[in]  mood       Optional mood captured with the check-in
    ///
    /// @return     (Void) no return value
    ///
    mutating func recordCheckIn(
        changed: String, sources: [PlanningSearchResult], at timestamp: Date = .now, mood: CheckInMood? = nil
    )
    {

        var entries = checkInHistory
        let focus = DailyCheckInProgress.focus(plan: self, sources: sources)
        let progress = DailyCheckInProgress.counts(plan: self, sources: sources)
        entries.append(
            .init(
                id: UUID().uuidString, savedAt: timestamp, changed: changed, focus: focus,
                intention: intention, constraints: constraints, concerns: concerns, priorities: priorities,
                completedTasks: progress.completed, totalTasks: progress.tasks,
                notes: progress.notes, unavailable: progress.unavailable, legacy: false, mood: mood))
        checkIns = entries
        checkIn = DailyCheckIn(focus: focus, changed: changed, savedAt: timestamp)
    }

}


///
/// Browses retained daily planning history
///
/// @section    Purpose
///     Reads saved intentions, check-ins, and reviews without writing a plan merely because history
///     is opened.
///
struct DailyHistoryReviewView: View
{


    @Environment(\.dismiss) private var dismiss
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.scenePhase) private var scenePhase
    @State private var date: Date
    @State private var document = DailyPlanStore.Document()
    @State private var loadError:       String?
    @AppStorage private var storedData: Data
    private let calendar:               Calendar
    private let defaults:               UserDefaults


    ///
    /// @fcn        DailyHistoryReviewView.init
    /// @brief      Configure history observation for a represented day
    /// @details    Retains calendar and preferences and binds stored daily-plan bytes so later saves can refresh the
    ///             displayed history.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (DailyHistoryReviewView) initialized instance
    ///
    init(date: Date, calendar: Calendar, defaults: UserDefaults = .standard)
    {

        _date = State(initialValue: date)
        self.calendar = calendar;
        self.defaults = defaults
        _storedData = AppStorage(wrappedValue: Data(), DailyPlanStore.key, store: defaults)
    }

    private var plan: DailyPlan?
    {
        document.plans[PlanningDate.key(date, calendar: calendar)]
    }

    private var isToday: Bool
    {
        calendar.isDateInToday(date)
    }


    ///
    /// @fcn        DailyHistoryReviewView.reload
    /// @brief      Reload retained planning and check-in history
    /// @details    Reads the represented day's saved plan and updates the view's history or retained-data error
    ///             state.
    ///
    /// @return     (Void) no return value
    ///
    private func reload()
    {

        do
        {
            document = try DailyPlanStore.load(from: defaults);
            loadError = nil
        }
        catch
        {

            loadError = error.localizedDescription
        }

    }


    ///
    /// @fcn        DailyHistoryReviewView.checkInTime
    /// @brief      Format a check-in timestamp in its recorded time zone
    /// @details    Uses the saved time-zone identifier with a fallback when that identifier is no longer available.
    ///
    /// @param[in]  timestamp   Explicit timestamp to store or format
    /// @param[in]  timeZoneID  Recorded time-zone identifier used to format the check-in timestamp
    ///
    /// @return     (String) localized time label using the saved time zone or the view calendar's fallback zone
    ///
    private func checkInTime(_ timestamp: Date, timeZoneID: String) -> String
    {

        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: timeZoneID) ?? calendar.timeZone
        return timestamp.formatted(style)
    }


    ///
    /// @fcn        DailyHistoryReviewView.text
    /// @brief      Build a labeled history-text section
    /// @details    Presents the recorded value using the history view's shared heading and body styling.
    ///
    /// @param[in]  title  Display title or proposed title text
    /// @param[in]  value  Stored or user-entered text to decode, inspect, or display
    ///
    /// @return     (some View) a labeled history-text section
    ///
    private func text(_ title: String, _ value: String) -> some View
    {

        Group
        {

            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {

                VStack(alignment: .leading, spacing: 4)
                {

                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value)
                }

            }

        }

    }

    var body: some View
    {

        NavigationStack
        {

            List
            {

                Section
                {

                    DatePicker("Review day", selection: $date, displayedComponents: .date)
                    Text("Saved records only. Save an open Check-in or plan before reviewing its changes here.").font(
                        .caption
                    ).foregroundStyle(.secondary)
                    Menu("Saved days")
                    {

                        ForEach(document.plans.keys.sorted(by: >), id: \.self)
                        {
                            key in
                            if let day = PlanningDate.date(key, calendar: calendar)
                            {

                                Button(day.formatted(date: .abbreviated, time: .omitted))
                                {
                                    date = day
                                }

                            }

                        }

                    } .disabled(document.plans.isEmpty)
                }

                if let loadError
                {

                    Section("Your records couldn't be opened")
                    {

                        Text(loadError)
                        Button("Try again", action: reload)
                    }

                }
                else if let plan
                {

                    Section(isToday ? "Your day so far" : "Saved daily plan")
                    {

                        text("Intention", plan.intention)
                        if isToday
                        {

                            let counts = DailyCheckInProgress.counts(plan: plan, sources: access?.searchableItems ?? [])
                            Text("\(counts.completed) of \(counts.tasks) priority tasks complete").font(.headline)
                            if counts.tasks > 0
                            {

                                ProgressView(value: Double(counts.completed), total: Double(counts.tasks))
                            }

                            Text("\(counts.notes) Notes · \(counts.unavailable) unavailable links").font(.caption)
                            .foregroundStyle(.secondary)
                            Text("Progress reflects your linked items now.").font(.caption).foregroundStyle(.secondary)
                        }

                        Text("\(plan.checkInHistory.count) saved Check-ins")
                        if isToday,
                        let focus = DailyCheckInProgress.focus(plan: plan, sources: access?.searchableItems ?? [])
                        {

                            text(
                                                                                    "Your next focus",
                                                                                    focus.resolve(in: access?.searchableItems ?? [])?.card.word ?? focus.title)
                        }

                        text("Make room for", plan.constraints)
                        text("Risks or concerns", plan.concerns)
                        ForEach(plan.priorities)
                        {
                            priority in
                            Text(priority.title)
                        }

                        if !isToday
                        {

                            Text("Saved priorities are context; completion at each Check-in is recorded below.").font(
                                .caption
                            ).foregroundStyle(.secondary)
                        }

                    }

                    Section("Check-ins · " + plan.timeZoneID)
                    {

                        if plan.checkInHistory.isEmpty
                        {

                            Text("No saved Check-ins for this day.").foregroundStyle(.secondary)
                        }

                        ForEach(plan.checkInHistory.sorted
                            {
                                $0.savedAt < $1.savedAt
                            })
                        {
                            entry in
                            VStack(alignment: .leading, spacing: 10)
                            {

                                HStack(alignment: .firstTextBaseline)
                                {

                                    Text(checkInTime(entry.savedAt, timeZoneID: plan.timeZoneID)).font(.headline)
                                    if let mood = entry.mood
                                    {
                                        Text(mood.display).font(.subheadline)
                                    }

                                } .accessibilityElement(children: .combine)
                                if entry.changed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                {

                                    Text("Checked in without a note").foregroundStyle(.secondary)
                                }
                                else
                                {

                                    Text(entry.changed)
                                }

                                if let completed = entry.completedTasks, let total = entry.totalTasks
                                {

                                    Text("\(completed) of \(total) priority tasks complete at this Check-in").font(
                                        .subheadline)
                                    Text("\(entry.notes ?? 0) Notes · \(entry.unavailable ?? 0) unavailable links")
                                    .font(.caption).foregroundStyle(.secondary)
                                }

                                if let focus = entry.focus
                                {
                                    text("Next focus", focus.title)
                                }

                                if entry.legacy
                                {

                                    Text(
                                                                                                            "Retained from the original Check-in. A plan and progress snapshot was not recorded at that time."
                                    ).font(.caption).foregroundStyle(.secondary)
                                }
                                else
                                {

                                    DisclosureGroup("Plan at this Check-in")
                                    {

                                        text("Intention", entry.intention)
                                        text("Make room for", entry.constraints)
                                        text("Risks or concerns", entry.concerns)
                                        ForEach(entry.priorities)
                                        {
                                            priority in
                                            Text(priority.title)
                                        }

                                    }

                                }

                            } .padding(.vertical, 6)
                        }

                    }

                    if let review = plan.eveningReview
                    {

                        Section("Evening review")
                        {

                            Text(review.completedAt == nil ? "In progress" : "Completed")
                            text("What helped", review.helped)
                            text("What was difficult", review.difficult)
                            text("Carry into tomorrow", review.tomorrow)
                            ForEach(review.achievements)
                            {
                                item in
                                Text(item.title)
                            }

                        }

                    }

                }
                else
                {

                    Section
                    {
                        Text("No saved plan or Check-ins for this day.").foregroundStyle(.secondary)
                    }

                }

            }
            .textSelection(.enabled)
            .navigationTitle("Daily review").navigationBarTitleDisplayMode(.inline)
            .toolbar
            {
                ToolbarItem(placement: .confirmationAction)
                {
                    Button("Done")
                    {
                        dismiss()
                    }

                }

            }
            .task
            {
                reload()
            }
            .onChange(of: storedData)
            {
                _, _ in
                reload()
            }
            .onChange(of: scenePhase)
            {
                _, phase in
                if phase == .active
                {
                    reload()
                }

            }

        }
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
    }

}


///
/// Summarizes live progress for linked daily priorities
///
/// @section    Purpose
///     Counts task completion while retaining Notes and unavailable links as separate context
///     rather than treating them as unfinished tasks.
///
enum DailyCheckInProgress
{


    ///
    /// @fcn        DailyCheckInProgress.counts
    /// @brief      Count task, note, and unresolved daily priorities
    /// @details    Counts all resolved tasks in tasks and their completed subset separately; notes and missing live
    ///             source references have their own counts.
    ///
    /// @param[in]  plan     Daily plan supplying the retained priorities and review state
    /// @param[in]  sources  Live owner-qualified workspace items used to resolve retained references
    ///
    /// @return     ((completed: Int, tasks: Int, notes: Int, unavailable: Int)) completed-task count, total task
    ///             count, note count, and unresolved-priority count
    ///
    static func counts(plan: DailyPlan, sources: [PlanningSearchResult]) -> (
        completed: Int, tasks: Int, notes: Int, unavailable: Int
    )
    {

        var result = (completed: 0, tasks: 0, notes: 0, unavailable: 0)
        for priority in plan.priorities
        {

            guard let source = priority.resolve(in: sources) else
            {
                result.unavailable += 1;
                continue
            }

            if source.card.presentation == .note
            {

                result.notes += 1
            }
            else
            {

                result.tasks += 1;
                if source.card.isTitleChecked
                {
                    result.completed += 1
                }

            }

        }

        return result
    }


    ///
    /// @fcn        DailyCheckInProgress.focus
    /// @brief      Resolve the daily plan's still-eligible check-in focus
    /// @details    Requires the recorded focus to remain among the priorities and resolve to a live note or
    ///             incomplete task; otherwise returns nil.
    ///
    /// @param[in]  plan     Daily plan supplying the retained priorities and review state
    /// @param[in]  sources  Live owner-qualified workspace items used to resolve retained references
    ///
    /// @return     (DailyPlanPriority?) still-selected live note or incomplete task priority, or nil when no eligible
    ///             focus remains
    ///
    static func focus(plan: DailyPlan, sources: [PlanningSearchResult]) -> DailyPlanPriority?
    {

        guard let focus = plan.checkIn?.focus,
        plan.priorities.contains(where:
            {
                $0 == focus
            }),
        let source = focus.resolve(in: sources),
        source.card.presentation == .note || !source.card.isTitleChecked
        else
        {
            return nil
        }

        return focus
    }

}


///
/// Presents a new check-in against the shared Daily plan
///
/// @section    Purpose
///     Resolves live priorities, records current context and progress on submission, and leaves the
///     draft available when saving fails.
///
struct TodayCheckInView: View
{


    @Binding var plan: DailyPlan
    let date:          Date
    let onSave:        () -> Bool
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var showsPicker = false
    @State private var showsNew = false
    @State private var saveFailed = false
    private var sources: [PlanningSearchResult]
    {
        access?.searchableItems ?? []
    }

    private var checkIn: DailyCheckIn
    {
        plan.checkIn ?? DailyCheckIn()
    }

    @State private var changed = ""
    @State private var moodChoice: CheckInMoodChoice = .none
    @State private var customEmoji = ""
    @State private var customFeeling = ""
    private var selectedMood: CheckInMood?
    {

        moodChoice == .custom ? CheckInMood.custom(emoji: customEmoji, label: customFeeling) : moodChoice.mood
    }

    private var hasUnsavedCheckIn: Bool
    {

        !changed.isEmpty || moodChoice != .none || !customEmoji.isEmpty || !customFeeling.isEmpty
    }

    @State private var didSave = false
    @State private var selectedFocus: DailyPlanPriority?


    ///
    /// @fcn        TodayCheckInView.init
    /// @brief      Seed check-in editing from the shared daily plan
    /// @details    Retains the plan binding, represented date, and checked save callback and restores the currently
    ///             recorded focus selection.
    ///
    /// @param[in]  plan    Daily plan supplying the retained priorities and review state
    /// @param[in]  date    Represented date for the operation
    /// @param[in]  onSave  Save callback returning true only when the owner accepts the edited value
    ///
    /// @return     (TodayCheckInView) initialized instance
    ///
    init(plan: Binding<DailyPlan>, date: Date, onSave: @escaping () -> Bool)
    {

        _plan = plan;
        self.date = date;
        self.onSave = onSave
        _selectedFocus = State(initialValue: plan.wrappedValue.checkIn?.focus)
    }

    private var focusPlan: DailyPlan
    {

        var result = plan
        var latest = checkIn;
        latest.focus = selectedFocus;
        result.checkIn = latest
        return result
    }

    @State private var confirmsLeaving = false


    ///
    /// @fcn        TodayCheckInView.selectFocus
    /// @brief      Stage the check-in focus selection
    /// @details    Assigns the optional priority to local selection state; the shared plan is updated only by the
    ///             later save action.
    ///
    /// @param[in]  priority  Owner-qualified daily priority, or nil when clearing an optional selection
    ///
    /// @return     (Void) no return value
    ///
    private func selectFocus(_ priority: DailyPlanPriority?)
    {

        selectedFocus = priority
    }


    ///
    /// @fcn        TodayCheckInView.save
    /// @brief      Save a single check-in snapshot with optional mood
    /// @details    Rejects duplicate saves and invalid custom moods, retains the previous plan before mutation, and
    ///             restores it if the checked save callback fails.
    ///
    /// @return     (Void) no return value
    ///
    private func save()
    {

        guard !didSave, moodChoice != .custom || selectedMood != nil else
        {
            return
        }

        let previous = plan
        plan.checkIns = plan.checkInHistory
        plan.checkIn = focusPlan.checkIn
        plan.recordCheckIn(changed: changed, sources: sources, mood: selectedMood)
        if onSave()
        {
            didSave = true;
            dismiss()
        }
        else
        {
            plan = previous;
            saveFailed = true
        }

    }

    var body: some View
    {

        NavigationStack
        {

            Form
            {

                Section
                {

                    Text("A moment to reset").font(.title2.bold())
                    Text(date.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                    Text("Notice where you are, adjust your plan, and choose one useful next step.").foregroundStyle(
                        .secondary)
                }

                Section("Where am I?")
                {

                    let progress = DailyCheckInProgress.counts(plan: plan, sources: sources)
                    Text("\(progress.completed) of \(progress.tasks) priority tasks complete").font(.headline)
                    if progress.tasks > 0
                    {

                        ProgressView(value: Double(progress.completed), total: Double(progress.tasks))
                    }

                    if progress.notes > 0
                    {

                        Text("\(progress.notes) linked Notes for context").foregroundStyle(.secondary)
                    }

                    if progress.unavailable > 0
                    {

                        Text("\(progress.unavailable) unavailable links · saved context retained").foregroundStyle(
                            .secondary)
                    }

                    if plan.priorities.isEmpty
                    {

                        Text("You can start a plan now, even without a morning review.").foregroundStyle(.secondary)
                    }

                }

                Section
                {

                    ForEach(plan.priorities)
                    {
                        priority in
                        let source = priority.resolve(in: sources)
                        HStack(alignment: .top, spacing: 12)
                        {

                            Image(
                                systemName: source == nil
                                ? "link.badge.plus"
                                : (source?.card.presentation == .note
                                    ? "note.text"
                                    : (source?.card.isTitleChecked == true ? "checkmark.circle.fill" : "circle"))
                            )
                            .foregroundStyle(source?.card.isTitleChecked == true ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 5)
                            {

                                Text(source?.card.word ?? priority.title).font(.headline)
                                Text(
                                    source == nil
                                    ? "Unavailable · remove this link and choose the item again if needed"
                                    : (source?.card.presentation == .note
                                        ? "Note"
                                        : (source?.card.isTitleChecked == true ? "Complete" : "Not complete"))
                                ).font(.caption).foregroundStyle(.secondary)
                                if let source, source.card.presentation == .note || !source.card.isTitleChecked
                                {

                                    let focused =
                                    DailyCheckInProgress.focus(plan: focusPlan, sources: sources)?.id == priority.id
                                    Button(focused ? "Next focus ✓" : "Focus on this next")
                                    {

                                        selectFocus(focused ? nil : priority)
                                    }
                                    .accessibilityValue(focused ? "Selected" : "Not selected")
                                }

                            }

                        } .padding(.vertical, 4)
                    }
                    .onDelete
                    {
                        plan.priorities.remove(atOffsets: $0)
                    }
                    .onMove
                    {
                        plan.priorities.move(fromOffsets: $0, toOffset: $1)
                    }

                    Button("Choose priorities", systemImage: "plus.circle")
                    {
                        showsPicker = true
                    }

                    Button("Add priority", systemImage: "square.and.pencil")
                    {
                        showsNew = true
                    }

                }
                header:
                {

                    Text("What matters next?")
                }
                footer:
                {

                    Text(
                                                            "Use Edit to reorder or set a priority aside. Removing a link keeps the original item in place. Your next focus is optional."
                    )
                }

                Section
                {

                    Picker("Mood", selection: $moodChoice)
                    {

                        ForEach(CheckInMoodChoice.allCases)
                        {
                            choice in
                            Text(choice.title).tag(choice)
                        }

                    } .pickerStyle(.menu)
                    if moodChoice == .custom
                    {

                        TextField("Emoji", text: $customEmoji)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityHint("Enter one emoji using the emoji keyboard")
                        TextField("Feeling, such as quietly hopeful", text: $customFeeling).textInputAutocapitalization(
                            .sentences
                        )
                        .onChange(of: customFeeling)
                        {
                            _, value in
                            customFeeling = String(value.prefix(40))
                        }

                        if selectedMood == nil
                        {

                            Text("Enter one emoji and a feeling of up to 40 characters.").font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        else if let selectedMood
                        {

                            Text(selectedMood.display).accessibilityLabel("Your mood: " + selectedMood.display)
                        }

                    }

                }
                header:
                {

                    Text("How are you feeling?")
                }
                footer:
                {

                    Text("Optional. Choose what fits this moment; each new Check-in starts fresh.")
                }

                Section("What changed?")
                {

                    TextField(
                                                            "New information, a small win, or a change of plan (optional)", text: $changed, axis: .vertical
                    ).textInputAutocapitalization(.sentences).lineLimit(2 ... 5)
                }

                Section("Is this still realistic?")
                {

                    TextField("Your intention", text: $plan.intention, axis: .vertical).textInputAutocapitalization(
                        .sentences
                    ).lineLimit(2 ... 5)
                    TextField("Available time, energy, or other constraints", text: $plan.constraints, axis: .vertical)
                    .textInputAutocapitalization(.sentences).lineLimit(2 ... 5)
                    TextField("Risks or concerns", text: $plan.concerns, axis: .vertical).textInputAutocapitalization(
                        .sentences
                    ).lineLimit(2 ... 5)
                }

                Section
                {

                    Button("Save check-in", action: save).disabled(moodChoice == .custom && selectedMood == nil).font(
                        .headline
                    ).frame(maxWidth: .infinity, minHeight: 44)
                    if let saved = checkIn.savedAt
                    {

                        Text("Last check-in " + saved.formatted(date: .omitted, time: .shortened)).font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Text(
                                                            "Each Save adds a timestamped entry to Daily review and updates your shared daily plan. Plan adjustments stay open when returning to Plan; an unsaved Check-in note or mood must be saved here."
                    ).font(.footnote).foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Today's Check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Plan", systemImage: "chevron.left")
                    {

                        if hasUnsavedCheckIn
                        {
                            confirmsLeaving = true
                        }
                        else
                        {
                            dismiss()
                        }

                    } .accessibilityLabel("Back to Today's Plan")
                }

                ToolbarItem(placement: .confirmationAction)
                {
                    EditButton()
                }

            }
            .sheet(isPresented: $showsPicker)
            {
                DailyPriorityPicker(sources: sources, priorities: $plan.priorities)
            }
            .sheet(isPresented: $showsNew)
            {

                NewDailyPriorityView
                {
                    source in
                    let priority = DailyPlanPriority(source)
                    if !plan.priorities.contains(where:
                        {
                            $0.id == priority.id
                        })
                    {
                        plan.priorities.append(priority)
                    }

                }

            }
            .interactiveDismissDisabled(hasUnsavedCheckIn)
            .confirmationDialog(
                                    "Leave without saving this Check-in?", isPresented: $confirmsLeaving, titleVisibility: .visible
            )
            {

                Button("Discard Check-in and return to Plan", role: .destructive)
                {
                    dismiss()
                }

                Button("Keep editing", role: .cancel)
                {

                }

            }
            .alert("Check-in not saved", isPresented: $saveFailed)
            {

                Button("OK", role: .cancel)
                {

                }

            }
            message:
            {

                Text(
                                                "Your edits are still open. The saved plan may have changed, or saving failed. Return to Plan to save or reopen it before retrying."
                )
            }

        }

    }

}


///
/// Presents the saved Daily plan summary in Today
///
/// @section    Purpose
///     Uses the same retained plan as the review workflows and delegates opening without modifying
///     history.
///
struct TodayPlanSummaryPanel: View
{


    @ScaledMetric(relativeTo: .title2) private var headingSize:    CGFloat = 26
    @ScaledMetric(relativeTo: .headline) private var subtitleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var bodySize:         CGFloat = 19
    let date:                                                      Date
    let calendar:                                                  Calendar
    let sources:                                                   [PlanningSearchResult]
    let onOpen:                                                    () -> Void
    let welcomesPlan:                                              Bool
    private let defaults:                                          UserDefaults
    @AppStorage private var storedData:                            Data
    @Environment(\.scenePhase) private var scenePhase
    @State private var plan: DailyPlan?
    @State private var readFailed = false


    ///
    /// @fcn        TodayPlanSummaryPanel.init
    /// @brief      Configure a live daily-plan summary and open action
    /// @details    Retains its represented date, source context, welcome choice, and callback and observes daily-plan
    ///             storage without writing a plan.
    ///
    /// @param[in]  date          Represented date for the operation
    /// @param[in]  calendar      Calendar supplying local-day, time-zone, and week-boundary rules
    /// @param[in]  sources       Live owner-qualified workspace items used to resolve retained references
    /// @param[in]  defaults      Preferences store used for this operation
    /// @param[in]  welcomesPlan  Whether the daily-plan summary participates in the welcome cue
    /// @param[in]  onOpen        Action invoked when the summary is opened
    ///
    /// @return     (TodayPlanSummaryPanel) initialized instance
    ///
    init(
        date: Date, calendar: Calendar, sources: [PlanningSearchResult], defaults: UserDefaults = .standard,
        welcomesPlan: Bool = false, onOpen: @escaping () -> Void
    )
    {

        self.welcomesPlan = welcomesPlan
        self.date = date;
        self.calendar = calendar;
        self.sources = sources;
        self.defaults = defaults;

        self.onOpen = onOpen
        _storedData = AppStorage(wrappedValue: Data(), DailyPlanStore.key, store: defaults)
    }


    ///
    /// @fcn        TodayPlanSummaryPanel.reload
    /// @brief      Refresh the represented day's quiet plan summary
    /// @details    Loads the retained plan for display and exposes storage failures without inventing replacement
    ///             history.
    ///
    /// @return     (Void) no return value
    ///
    private func reload()
    {

        do
        {

            plan = try DailyPlanStore.load(from: defaults).plans[PlanningDate.key(date, calendar: calendar)]
            readFailed = false
        }
        catch
        {
            plan = nil;
            readFailed = true
        }

    }

    var body: some View
    {

        VStack(alignment: .leading, spacing: 14)
        {

            HStack(spacing: 8)
            {

                Text("☀️").accessibilityHidden(true)
                Text("Today's Plan")
            }
            .font(.system(size: headingSize, weight: .semibold))
            .modifier(TodayWelcomeGlow(highlighted: welcomesPlan))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if readFailed
            {

                Text(
                                                "Your saved plan couldn't be read. Open Today's Plan to review the issue. Your records have been kept unchanged."
                ).foregroundStyle(.secondary)
            }
            else if let plan
            {

                if !plan.intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {

                    Text(plan.intention).font(.system(size: subtitleSize, weight: .semibold)).fixedSize(
                        horizontal: false, vertical: true)
                }

                if let focus = DailyCheckInProgress.focus(plan: plan, sources: sources),
                let source = focus.resolve(in: sources)
                {

                    Label("Next focus · " + source.card.word, systemImage: "scope").font(.system(size: bodySize))
                    .foregroundStyle(.blue)
                }

                if plan.priorities.isEmpty
                {

                    Text(
                                                            "What deserves your attention today? Choose a Card or Note, or add a new priority in your plan."
                    ).foregroundStyle(.secondary)
                }
                else
                {

                    Text("Your chosen priorities").font(.system(size: bodySize)).foregroundStyle(.secondary)
                    ForEach(Array(plan.priorities.prefix(3)))
                    {
                        priority in
                        let source = priority.resolve(in: sources)
                        HStack(alignment: .top, spacing: 12)
                        {

                            Image(
                                systemName: source == nil
                                ? "link.badge.plus"
                                : (source?.card.presentation == .note
                                    ? "note.text"
                                    : (source?.card.isTitleChecked == true ? "checkmark.circle.fill" : "circle"))
                            )
                            .foregroundStyle(source?.card.isTitleChecked == true ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 4)
                            {

                                Text(source?.card.word ?? priority.title).font(
                                    .system(size: bodySize, weight: .semibold))
                                Text(
                                    source == nil
                                    ? "Unavailable · saved context retained"
                                    : (source?.card.presentation == .note
                                        ? "Note"
                                        : (source?.card.isTitleChecked == true ? "Complete" : "Not complete"))
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        } .accessibilityElement(children: .combine)
                    }

                    if plan.priorities.count > 3
                    {

                        Text("\(plan.priorities.count - 3) more priorities in your plan").font(.caption)
                        .foregroundStyle(.secondary)
                    }

                }

            }
            else
            {

                Text("What would make today meaningful?").font(.system(size: subtitleSize, weight: .semibold))
                Text(
                                                "Choose a few priorities, leave room for real life, and take one useful step. Your morning vision, check-in, and evening review all connect here."
                ).foregroundStyle(.secondary)
            }

            Button(action: onOpen)
            {

                Label(plan == nil && !readFailed ? "Plan today" : "Open today's plan", systemImage: "arrow.up.right")
                .frame(minHeight: 44, alignment: .leading)
            } .buttonStyle(.plain).foregroundStyle(.blue)
            .accessibilityHint("Opens Today's Plan and the Planning Rhythm reviews")
        }
        .font(.system(size: bodySize))
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: PlanningDate.key(date, calendar: calendar))
        {
            reload()
        }
        .onChange(of: storedData)
        {
            _, _ in
            reload()
        }
        .onChange(of: scenePhase)
        {
            _, phase in
            if phase == .active
            {
                reload()
            }

        }

    }

}
