import SwiftUI

enum DailyReviewAction: Codable, Equatable {
    case keep, complete, archive, queue, tomorrow, date(String)
    var title: String {
        switch self {
        case .keep: "Leave in place"
        case .complete: "Mark complete"
        case .archive: "Archive"
        case .queue: "Return to In the Queue"
        case .tomorrow: "Carry into tomorrow"
        case .date(let key): "Move to \(key)"
        }
    }
}
struct DailyReviewDecision: Codable, Equatable, Identifiable {
    var id = UUID()
    let source: DailyPlanPriority
    let result: DailyPlanPriority
    let action: DailyReviewAction
    var recordedAt = Date()
}
struct DailyEveningReview: Codable, Equatable {
    var step = 0
    var completedAt: Date?
    var helped = ""
    var difficult = ""
    var tomorrow = ""
    var decisions: [DailyReviewDecision] = []
    var achievements: [DailyPlanPriority] = []
}

/// Stored before mutation and cleared only after both source data and review progress are saved.
@MainActor
enum DailyReviewTransaction {
    static let key = "Plenact.DailyReviewTransaction.v1"
    static let keys = [PlanningCalendarStore.key, "Plenact.Board.v1", "Plenact.PersonalCollections.v1", "Plenact.SavedCardIDs.v1", DailyPlanStore.key, WeeklyReviewStore.key]
    static func begin(in defaults: UserDefaults = .standard) throws -> Data {
        guard defaults.object(forKey: key) == nil else { throw CocoaError(.fileWriteUnknown) }
        var previous: [String: Any] = [:]
        for name in keys { previous[name] = defaults.object(forKey: name) }
        let data = try PropertyListSerialization.data(fromPropertyList: ["version": 1, "previous": previous], format: .binary, options: 0)
        defaults.set(data, forKey: key)
        guard defaults.synchronize(), defaults.data(forKey: key) == data else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
    static func recover(in defaults: UserDefaults = .standard) throws {
        guard defaults.object(forKey: key) != nil else { return }
        guard let data = defaults.data(forKey: key),
              let snapshot = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              snapshot["version"] as? Int == 1,
              let previous = snapshot["previous"] as? [String: Any], Set(previous.keys).isSubset(of: Set(keys)) else { throw CocoaError(.fileReadCorruptFile) }
        for name in keys {
            if let value = previous[name] { defaults.set(value, forKey: name) }
            else { defaults.removeObject(forKey: name) }
        }
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        defaults.removeObject(forKey: key)
        guard defaults.synchronize() else { defaults.set(data, forKey: key); throw CocoaError(.fileWriteUnknown) }
    }
    static func perform<T>(in defaults: UserDefaults = .standard, _ action: () throws -> T) throws -> T {
        let snapshot = try begin(in: defaults)
        do {
            let result = try action()
            guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            defaults.removeObject(forKey: key)
            guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            return result
        } catch {
            defaults.set(snapshot, forKey: key)
            try recover(in: defaults)
            throw error
        }
    }
}

enum TodayReviewSelection {
    static func items(plan: DailyPlan, date: Date, access: PlanningCalendarAccess, referenceLabelIDs: Set<String>, calendar: Calendar) -> [PlanningSearchResult] {
        let day = access.document.week(for: date, calendar: calendar)
        let listID = day?.dayListIDs[PlanningDate.key(date, calendar: calendar)]
        let tables = Set(access.library.filter { $0.isActive && $0.kind == .list && $0.title == "On the Table" }.map(\.id))
        return access.searchableItems.filter { item in
            guard Set(item.card.labelIDs).isDisjoint(with: referenceLabelIDs) else { return false }
            let selected = plan.priorities.contains { $0.resolve(in: [item]) != nil }
            let inWorkingList = (item.collectionID == day?.id && item.listID == listID) || tables.contains(item.collectionID)
            return selected || (inWorkingList && item.card.presentation == .card)
        }
    }
    static func pending(_ items: [PlanningSearchResult], review: DailyEveningReview?) -> [PlanningSearchResult] {
        items.filter { item in
            guard !item.card.isTitleChecked else { return false }
            return !(review?.decisions.contains { $0.source.resolve(in: [item]) != nil || $0.result.resolve(in: [item]) != nil } ?? false)
        }
    }
}

struct TodayReviewView: View {
    @Binding var plan: DailyPlan
    let date: Date
    let baseline: DailyPlan?
    let onSave: () -> Bool
    let onCommitted: (DailyPlan) -> Void
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var pendingSource: PlanningSearchResult?
    @State private var pendingAction: DailyReviewAction?
    @State private var dateSource: PlanningSearchResult?
    @State private var selectedDate = Date()
    @State private var chosenDateDecision: (PlanningSearchResult, String)?
    @State private var operationError = false
    private var calendar: Calendar {
        var value = access?.document.calendar ?? .current
        value.timeZone = TimeZone(identifier: plan.timeZoneID) ?? .current
        return value
    }
    private var review: DailyEveningReview { plan.eveningReview ?? DailyEveningReview() }
    private var items: [PlanningSearchResult] {
        guard let access else { return [] }
        let labels = LabelLibraryStore.load().labels.filter { $0.name.caseInsensitiveCompare("Reference") == .orderedSame || $0.id == LabelLibrary.referenceLabel.id }
        return TodayReviewSelection.items(plan: plan, date: date, access: access, referenceLabelIDs: Set(labels.map(\.id)), calendar: calendar)
    }
    private var achievements: [PlanningSearchResult] { items.filter { $0.card.isTitleChecked } }
    private var queueAvailable: Bool { access?.library.contains { $0.isActive && $0.kind == .list && $0.title == "In the Queue" } == true }
    private func text(_ key: WritableKeyPath<DailyEveningReview, String>) -> Binding<String> {
        Binding(get: { review[keyPath: key] }, set: { value in var updated = review; updated[keyPath: key] = value; plan.eveningReview = updated })
    }
    private func propose(_ action: DailyReviewAction, source: PlanningSearchResult) {
        pendingSource = source; pendingAction = action
    }
    private func advance() {
        let previous = plan.eveningReview
        var updated = review
        updated.step = min(2, step + 1)
        if step == 2 {
            updated.completedAt = .now
            updated.achievements = achievements.map(DailyPlanPriority.init)
        }
        plan.eveningReview = updated
        if onSave() { if step == 2 { dismiss() } else { step += 1 } }
        else { plan.eveningReview = previous; operationError = true }
    }
    private func perform() {
        guard let source = pendingSource, let action = pendingAction,
              let saved = access?.applyDailyReview?(source, action, plan, baseline) else {
            operationError = true; pendingAction = nil; pendingSource = nil; return
        }
        onCommitted(saved)
        pendingAction = nil; pendingSource = nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(step + 1) of 3 · " + ["Notice your progress", "What belongs next?", "Close the day"][step]).font(.headline)
                        Text(date.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                        ProgressView(value: Double(step + 1), total: 3)
                    }.padding(.vertical, 4)
                }
                if step == 0 {
                    Section("What you accomplished") {
                        if achievements.isEmpty { Text("Progress isn't always a checked box. Take a moment to notice what you learned or made room for.").foregroundStyle(.secondary) }
                        ForEach(achievements) { source in Label(source.card.word, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    Section("Your priorities") {
                        if plan.priorities.isEmpty { Text("You can review today even without a morning plan.").foregroundStyle(.secondary) }
                        ForEach(plan.priorities) { priority in
                            let source = priority.resolve(in: access?.searchableItems ?? [])
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source?.card.word ?? priority.title)
                                Text(source == nil ? "Unavailable · saved context retained" : (source?.card.presentation == .note ? "Note" : (source?.card.isTitleChecked == true ? "Complete" : "Not complete")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if step == 1 {
                    Section {
                        Text("Give each item a decision, or leave it for later. Keeping work is a valid outcome; no List has to be empty.").foregroundStyle(.secondary)
                        let unfinished = TodayReviewSelection.pending(items, review: plan.eveningReview)
                        if unfinished.isEmpty { Text("Nothing else needs a decision right now.") }
                        ForEach(unfinished) { source in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(source.card.word).font(.headline)
                                Text(source.collectionTitle + " · " + source.listTitle).font(.caption).foregroundStyle(.secondary)
                                Menu("Choose what comes next") {
                                    Button("Leave in place") { propose(.keep, source: source) }
                                    Button("Carry into tomorrow") { propose(.tomorrow, source: source) }
                                    Button("Return to In the Queue") { propose(.queue, source: source) }.disabled(!queueAvailable)
                                    Button("Choose a day") { dateSource = source }
                                    if source.card.presentation == .card { Button("Mark complete") { propose(.complete, source: source) } }
                                    Button("Archive") { propose(.archive, source: source) }
                                }.disabled(access?.applyDailyReview == nil)
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("Unfinished work") }
                    if !review.decisions.isEmpty {
                        Section("Decisions saved") {
                            ForEach(review.decisions) { decision in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(decision.source.title)
                                    Text(decision.action.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Section("What helped?") { TextField("A useful step, a person, or a small win (optional)", text: text(\.helped), axis: .vertical).lineLimit(2...5) }
                    Section("What was difficult?") { TextField("Something to learn from, without judgment (optional)", text: text(\.difficult), axis: .vertical).lineLimit(2...5) }
                    Section("One thought for tomorrow") { TextField("Leave yourself a gentle starting point (optional)", text: text(\.tomorrow), axis: .vertical).lineLimit(2...5) }
                    if let completed = review.completedAt { Text("Last reviewed " + completed.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    if step > 0 { Button("Previous step") { step -= 1 } }
                    Button(step == 2 ? "Save today's review" : "Save and continue", action: advance).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    Text("Steps save your progress. Confirmed item actions are immediate and are not undone by leaving the review.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Today's Review").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Plan", systemImage: "chevron.left") { dismiss() }.accessibilityLabel("Back to Today's Plan") } }
            .onAppear { step = min(2, max(0, review.completedAt == nil ? review.step : 0)) }
            .confirmationDialog(pendingAction?.title ?? "Apply decision?", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil; pendingSource = nil } }), titleVisibility: .visible) {
                Button("Confirm", action: perform)
                Button("Cancel", role: .cancel) { pendingAction = nil; pendingSource = nil }
            } message: { Text("Applies this decision to ‘\(pendingSource?.card.word ?? "")’ and saves it in today's review. Moves preserve existing dates and details. Archive retains the item for restoration; nothing is permanently deleted.") }
            .sheet(item: $dateSource, onDismiss: {
                if let (source, key) = chosenDateDecision { chosenDateDecision = nil; propose(.date(key), source: source) }
            }) { source in
                NavigationStack {
                    Form { DatePicker("Choose a day", selection: $selectedDate, displayedComponents: .date).datePickerStyle(.graphical) }
                        .navigationTitle("Move to a day").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dateSource = nil } }
                            ToolbarItem(placement: .confirmationAction) { Button("Choose") {
                                chosenDateDecision = (source, PlanningDate.key(selectedDate, calendar: calendar))
                                dateSource = nil
                            } }
                        }
                }
            }
            .alert("Review not updated", isPresented: $operationError) { Button("OK", role: .cancel) {} }
                message: { Text("The item or saved plan may have changed, or saving failed. Your draft is still open. Return to your plan and retry. No successful review decision has been recorded for the failed action.") }
        }
    }
}

struct WeeklyReviewRecord: Codable, Equatable, Identifiable {
    let id: String
    let startKey: String
    let timeZoneID: String
    let firstWeekday: Int
    var step = 0
    var highlights = ""
    var learned = ""
    var direction = ""
    var constraints = ""
    var risks = ""
    var priorities: [DailyPlanPriority] = []
    var decisions: [DailyReviewDecision] = []
    var updatedAt: Date?
    var completedAt: Date?
    init(date: Date, calendar: Calendar) {
        startKey = PlanningDate.weekKey(date, calendar: calendar)
        timeZoneID = calendar.timeZone.identifier
        firstWeekday = calendar.firstWeekday
        id = startKey + "|" + timeZoneID + "|" + String(firstWeekday)
    }
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        value.firstWeekday = firstWeekday
        return value
    }
    var dayKeys: Set<String> { Set(PlanningDate.days(in: startKey, calendar: calendar).map { PlanningDate.key($0, calendar: calendar) }) }
    func dailyPlans(in document: DailyPlanStore.Document) -> [DailyPlan] {
        document.plans.values.filter { dayKeys.contains($0.id) }.sorted { $0.id < $1.id }
    }
}

@MainActor
enum WeeklyReviewStore {
    static let key = "Plenact.WeeklyReviews.v1"
    struct Document: Codable { var version = 1; var records: [String: WeeklyReviewRecord] = [:] }
    static func load(from defaults: UserDefaults = .standard) throws -> Document {
        guard defaults.object(forKey: key) != nil else { return Document() }
        guard let data = defaults.data(forKey: key), let document = try? JSONDecoder().decode(Document.self, from: data) else { throw DailyPlanStore.Failure.corrupt }
        guard document.version == 1 else { throw DailyPlanStore.Failure.unsupported }
        for (id, value) in document.records {
            guard id == value.id, TimeZone(identifier: value.timeZoneID) != nil, (1...7).contains(value.firstWeekday), (0...2).contains(value.step),
                  PlanningDate.date(value.startKey, calendar: value.calendar) != nil,
                  Set(value.priorities.map(\.id)).count == value.priorities.count,
                  Set(value.decisions.map(\.id)).count == value.decisions.count else { throw DailyPlanStore.Failure.corrupt }
        }
        return document
    }
    static func save(_ draft: WeeklyReviewRecord, replacing baseline: WeeklyReviewRecord?, to defaults: UserDefaults = .standard) throws -> WeeklyReviewRecord {
        var document = try load(from: defaults)
        guard document.records[draft.id] == baseline else { throw DailyPlanStore.Failure.conflict }
        var saved = draft; saved.updatedAt = .now
        document.records[saved.id] = saved
        let data = try JSONEncoder().encode(document)
        let old = defaults.object(forKey: key)
        defaults.set(data, forKey: key)
        guard defaults.synchronize(), defaults.data(forKey: key) == data else {
            if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) }
            throw DailyPlanStore.Failure.write
        }
        return saved
    }
}

struct WeeklyReviewView: View {
    let calendar: Calendar
    private let defaults: UserDefaults
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date
    @State private var draft: WeeklyReviewRecord
    @State private var baseline: WeeklyReviewRecord?
    @State private var daily = DailyPlanStore.Document()
    @State private var records: [WeeklyReviewRecord] = []
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var error: String?
    @State private var showsPicker = false
    @State private var confirmsDiscard = false
    @State private var pending: PlanningSearchResult?
    @State private var action: DailyReviewAction?
    @State private var dateSource: PlanningSearchResult?
    @State private var targetDate = Date()
    @State private var chosenDate: (PlanningSearchResult, String)?
    init(date: Date = .now, calendar: Calendar, defaults: UserDefaults = .standard) {
        self.calendar = calendar; self.defaults = defaults
        _selectedDate = State(initialValue: date)
        _draft = State(initialValue: WeeklyReviewRecord(date: date, calendar: calendar))
    }
    private var dirty: Bool { loaded && !loadFailed && draft != (baseline ?? WeeklyReviewRecord(date: selectedDate, calendar: calendar)) }
    private var sources: [PlanningSearchResult] { access?.searchableItems ?? [] }
    private var queue: [PlanningSearchResult] {
        let owners = Set(access?.library.filter { $0.isActive && $0.kind == .list && $0.title == "In the Queue" }.map(\.id) ?? [])
        let reference = Set(LabelLibraryStore.load().labels.filter { $0.name.caseInsensitiveCompare("Reference") == .orderedSame || $0.id == LabelLibrary.referenceLabel.id }.map(\.id))
        return sources.filter { item in owners.contains(item.collectionID) && item.card.presentation == .card && !item.card.isTitleChecked && Set(item.card.labelIDs).isDisjoint(with: reference) && !draft.decisions.contains(where: { $0.source.resolve(in: [item]) != nil || $0.result.resolve(in: [item]) != nil }) }
    }
    private func load(_ record: WeeklyReviewRecord) {
        do {
            let document = try WeeklyReviewStore.load(from: defaults)
            daily = try DailyPlanStore.load(from: defaults)
            records = document.records.values.sorted { $0.startKey > $1.startKey }
            baseline = document.records[record.id]; draft = baseline ?? record
            selectedDate = PlanningDate.date(draft.startKey, calendar: draft.calendar) ?? selectedDate
            loaded = true; loadFailed = false
        } catch { loaded = true; loadFailed = true; self.error = error.localizedDescription }
    }
    private func binding(_ path: WritableKeyPath<WeeklyReviewRecord, String>) -> Binding<String> { Binding(get: { draft[keyPath: path] }, set: { draft[keyPath: path] = $0 }) }
    private func save(advance: Bool) {
        let before = draft
        if advance { if draft.step == 2 { draft.completedAt = .now } else { draft.step += 1 } }
        do {
            let saved = try WeeklyReviewStore.save(draft, replacing: baseline, to: defaults)
            baseline = saved; draft = saved
            records.removeAll { $0.id == saved.id }; records.append(saved)
        } catch { draft = before; self.error = error.localizedDescription }
    }
    private func propose(_ action: DailyReviewAction, _ source: PlanningSearchResult) { pending = source; self.action = action }
    private func apply() {
        guard let pending, let action, let saved = access?.applyWeeklyReview?(pending, action, draft, baseline) else { error = "The item or review changed, or saving failed. Your draft remains open."; return }
        baseline = saved; draft = saved
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Review a week") {
                    DatePicker("Week containing", selection: Binding(get: { selectedDate }, set: { date in selectedDate = date; load(WeeklyReviewRecord(date: date, calendar: calendar)) }), displayedComponents: .date)
                        .disabled(dirty || loadFailed)
                    if !records.isEmpty {
                        Menu("Open a saved week") {
                            ForEach(records.sorted { $0.startKey > $1.startKey }) { record in
                                Button(record.startKey + (record.completedAt == nil ? " · In progress" : " · Reviewed")) { load(record) }
                            }
                        }.disabled(dirty || loadFailed)
                    }
                    Text("Week starting \(draft.startKey) · \(draft.step + 1) of 3").font(.headline)
                    Text("Save current edits before switching weeks. Reviews follow your calendar's week boundaries; saved weeks retain their original boundaries.").font(.footnote).foregroundStyle(.secondary)
                }
                if loadFailed { Section { Text("Saved records could not be opened. They have been kept unchanged."); Button("Try again") { load(draft) } } }
                else if draft.step == 0 {
                    Section("Look back") {
                        let days = draft.dailyPlans(in: daily)
                        Text("\(days.count) of 7 days have saved plans. Missing days are welcome; no catching up is required.").foregroundStyle(.secondary)
                        ForEach(days) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.id).font(.headline)
                                if !day.intention.isEmpty { Text(day.intention) }
                                if let review = day.eveningReview {
                                    ForEach(review.achievements) { Text("✓ " + $0.title) }
                                    if !review.helped.isEmpty { Text("What helped: " + review.helped) }
                                    if !review.difficult.isEmpty { Text("What was difficult: " + review.difficult) }
                                    if !review.tomorrow.isEmpty { Text("Carried forward: " + review.tomorrow) }
                                }
                                if let changed = day.checkIn?.changed, !changed.isEmpty { Text("Check-in: " + changed) }
                            }.padding(.vertical, 4)
                        }
                    }
                    Section("Your highlights") { TextField("Wins, meaningful moments, or progress (optional)", text: binding(\.highlights), axis: .vertical).lineLimit(2...5) }
                    Section("What did you learn?") { TextField("What worked, and what would you change? (optional)", text: binding(\.learned), axis: .vertical).lineLimit(2...5) }
                } else if draft.step == 1 {
                    Section("Review In the Queue") {
                        Text("Keep worthwhile work for later. The Queue does not have to be empty. These are today's live Queue items, even when reviewing a past week.").foregroundStyle(.secondary)
                        if queue.isEmpty { Text("No unfinished Queue Cards need a decision. Reference Cards and Notes are left in place.") }
                        ForEach(queue) { source in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(source.card.word).font(.headline)
                                Menu("Choose what comes next") {
                                    Button("Keep in the Queue") { propose(.keep, source) }
                                    Button("Choose a calendar day") { dateSource = source }
                                    Button("Mark complete") { propose(.complete, source) }
                                    Button("Archive") { propose(.archive, source) }
                                }.disabled(access?.applyWeeklyReview == nil)
                            }
                        }
                    }
                    Section("Decisions saved") {
                        ForEach(draft.decisions) { decision in VStack(alignment: .leading) { Text(decision.source.title); Text(decision.action.title).font(.caption).foregroundStyle(.secondary) } }
                    }
                } else {
                    Section("Next week's direction") { TextField("What deserves your attention? (optional)", text: binding(\.direction), axis: .vertical).lineLimit(2...5) }
                    Section {
                        ForEach(draft.priorities) { priority in Text(priority.resolve(in: sources)?.card.word ?? priority.title) }
                            .onDelete { draft.priorities.remove(atOffsets: $0) }.onMove { draft.priorities.move(fromOffsets: $0, toOffset: $1) }
                        Button("Choose next week's priorities", systemImage: "plus.circle") { showsPicker = true }
                    } header: { Text("Priorities for next week") } footer: { Text("These links guide next week; they do not automatically move items or replace daily plans. Use Edit to reorder or remove links.") }
                    Section("Make room for") { TextField("Time, energy, or commitments (optional)", text: binding(\.constraints), axis: .vertical).lineLimit(2...5) }
                    Section("Risks to consider") { TextField("What might get in the way? (optional)", text: binding(\.risks), axis: .vertical).lineLimit(2...5) }
                }
                if !loadFailed {
                    Section {
                        if draft.step > 0 { Button("Previous step") { draft.step -= 1 } }
                        Button(draft.step == 2 ? "Save weekly review" : "Save and continue") { save(advance: true) }.font(.headline)
                        Button("Save progress") { save(advance: false) }
                        if let completed = draft.completedAt { Text("Reviewed " + completed.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                        Text("Confirmed item actions save immediately. Other edits save with Save progress or Save and continue.").font(.footnote).foregroundStyle(.secondary)
                    }.disabled(!loaded)
                }
            }
            .navigationTitle("Weekly Review").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { if dirty { confirmsDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { if draft.step == 2 { EditButton() } }
            }
            .task { if !loaded { load(draft) } }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Discard unsaved review edits?", isPresented: $confirmsDiscard) { Button("Discard edits", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
            .confirmationDialog(action?.title ?? "Apply decision?", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil; pending = nil } }), titleVisibility: .visible) {
                Button("Confirm") { apply(); action = nil; pending = nil }
                Button("Cancel", role: .cancel) { action = nil; pending = nil }
            } message: { Text("Applies to ‘\(pending?.card.word ?? "")’ now and saves this review. Moves preserve dates and details. Archive keeps the item recoverable.") }
            .sheet(item: $dateSource, onDismiss: { if let (source, key) = chosenDate { chosenDate = nil; propose(.date(key), source) } }) { source in
                NavigationStack {
                    DatePicker("Move to a day", selection: $targetDate, displayedComponents: .date).datePickerStyle(.graphical).padding()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dateSource = nil } }
                            ToolbarItem(placement: .confirmationAction) { Button("Choose") { chosenDate = (source, PlanningDate.key(targetDate, calendar: calendar)); dateSource = nil } }
                        }
                }
            }
            .sheet(isPresented: $showsPicker) { DailyPriorityPicker(sources: sources, priorities: $draft.priorities) }
            .alert("Review not updated", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
}
