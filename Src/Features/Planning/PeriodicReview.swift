import SwiftUI

enum ObjectiveStatus: String, Codable, CaseIterable, Identifiable {
    case active = "Active", achieved = "Achieved", paused = "Paused", released = "Let go"
    var id: String { rawValue }
}
struct ReviewObjective: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var status: ObjectiveStatus = .active
    var progress = ""
    var nextStep = ""
}
struct PeriodicReviewRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    let startKey: String
    let endKey: String
    let timeZoneID: String
    var step = 0
    var highlights = ""
    var learned = ""
    var direction = ""
    var risks = ""
    var startingObjectives: [ReviewObjective] = []
    var objectives: [ReviewObjective] = []
    var priorities: [DailyPlanPriority] = []
    var updatedAt: Date?
    var completedAt: Date?
    init(title: String, start: Date, end: Date, calendar: Calendar, previous: PeriodicReviewRecord? = nil) {
        self.title = title
        startKey = PlanningDate.key(start, calendar: calendar)
        endKey = PlanningDate.key(end, calendar: calendar)
        timeZoneID = calendar.timeZone.identifier
        startingObjectives = previous?.objectives ?? []
        objectives = startingObjectives.map { prior in var current = prior; current.progress = ""; return current }
    }
    func weeks(in document: WeeklyReviewStore.Document) -> [WeeklyReviewRecord] {
        document.records.values.filter { record in
            let keys = record.dayKeys
            return keys.contains { $0 >= startKey && $0 <= endKey }
        }.sorted { $0.startKey < $1.startKey }
    }
}
@MainActor
enum PeriodicReviewStore {
    static let key = "Plenact.PeriodicReviews.v1"
    struct Document: Codable, Equatable { var version = 1; var records: [String: PeriodicReviewRecord] = [:] }
    static func validate(_ record: PeriodicReviewRecord) throws {
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: record.timeZoneID) else { throw DailyPlanStore.Failure.corrupt }
        calendar.timeZone = zone
        guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.startKey <= record.endKey, (0...2).contains(record.step),
              [record.startKey, record.endKey].allSatisfy({ key in
                  guard let date = PlanningDate.date(key, calendar: calendar) else { return false }
                  return PlanningDate.key(date, calendar: calendar) == key
              }), Set(record.objectives.map(\.id)).count == record.objectives.count,
              Set(record.priorities.map(\.id)).count == record.priorities.count,
              record.objectives.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw DailyPlanStore.Failure.corrupt }
    }
    static func load(from defaults: UserDefaults = .standard) throws -> Document {
        guard defaults.object(forKey: key) != nil else { return Document() }
        guard let data = defaults.data(forKey: key), let document = try? JSONDecoder().decode(Document.self, from: data) else { throw DailyPlanStore.Failure.corrupt }
        guard document.version == 1 else { throw DailyPlanStore.Failure.unsupported }
        for (id, record) in document.records { guard id == record.id.uuidString else { throw DailyPlanStore.Failure.corrupt }; try validate(record) }
        return document
    }
    static func previous(before startKey: String, in document: Document) -> PeriodicReviewRecord? {
        document.records.values.filter { $0.endKey < startKey }.max { lhs, rhs in
            if lhs.endKey != rhs.endKey { return lhs.endKey < rhs.endKey }
            return (lhs.updatedAt ?? .distantPast) < (rhs.updatedAt ?? .distantPast)
        }
    }
    static func save(_ draft: PeriodicReviewRecord, replacing baseline: PeriodicReviewRecord?, to defaults: UserDefaults = .standard) throws -> PeriodicReviewRecord {
        try validate(draft)
        var document = try load(from: defaults)
        guard document.records[draft.id.uuidString] == baseline else { throw DailyPlanStore.Failure.conflict }
        var saved = draft; saved.updatedAt = .now
        document.records[saved.id.uuidString] = saved
        let data = try JSONEncoder().encode(document)
        let previous = defaults.object(forKey: key)
        defaults.set(data, forKey: key)
        guard defaults.synchronize(), defaults.data(forKey: key) == data else {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
            throw DailyPlanStore.Failure.write
        }
        return saved
    }
}

struct PeriodicReviewView: View {
    let calendar: Calendar
    private let defaults: UserDefaults
    private let initialReviewID: UUID?
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var document = PeriodicReviewStore.Document()
    @State private var weekly = WeeklyReviewStore.Document()
    @State private var draft: PeriodicReviewRecord?
    @State private var baseline: PeriodicReviewRecord?
    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var objectiveTitle = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var confirmsDiscard = false
    @State private var showsPicker = false
    init(date: Date = .now, calendar: Calendar, defaults: UserDefaults = .standard, initialReviewID: UUID? = nil) {
        self.calendar = calendar; self.defaults = defaults; self.initialReviewID = initialReviewID
        _start = State(initialValue: calendar.dateInterval(of: .month, for: date)?.start ?? date)
        _end = State(initialValue: date)
    }
    private var dirty: Bool { draft != baseline || !objectiveTitle.isEmpty || (draft == nil && !title.isEmpty) }
    private var sources: [PlanningSearchResult] { access?.searchableItems ?? [] }
    private func load() {
        do {
            document = try PeriodicReviewStore.load(from: defaults)
            weekly = try WeeklyReviewStore.load(from: defaults)
            if !loaded, let initialReviewID, let record = document.records[initialReviewID.uuidString] { draft = record; baseline = record }
            loaded = true; loadFailed = false
        } catch { loaded = true; loadFailed = true; self.error = error.localizedDescription }
    }
    private func begin() {
        let key = PlanningDate.key(start, calendar: calendar)
        draft = PeriodicReviewRecord(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end, calendar: calendar, previous: PeriodicReviewStore.previous(before: key, in: document))
        baseline = nil
    }
    private func text(_ path: WritableKeyPath<PeriodicReviewRecord, String>) -> Binding<String> { Binding(get: { draft?[keyPath: path] ?? "" }, set: { draft?[keyPath: path] = $0 }) }
    private func addObjective() {
        let value = objectiveTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        draft?.objectives.append(ReviewObjective(title: value)); objectiveTitle = ""
    }
    private func save(advance: Bool) {
        addObjective()
        guard var value = draft else { return }
        if advance { if value.step == 2 { value.completedAt = .now } else { value.step += 1 } }
        do {
            let saved = try PeriodicReviewStore.save(value, replacing: baseline, to: defaults)
            document.records[saved.id.uuidString] = saved; draft = saved; baseline = saved
        } catch { self.error = error.localizedDescription }
    }
    private func objective(_ id: UUID) -> Binding<ReviewObjective> {
        Binding(get: { draft?.objectives.first { $0.id == id } ?? ReviewObjective(id: id) }, set: { value in
            if let index = draft?.objectives.firstIndex(where: { $0.id == id }) { draft?.objectives[index] = value }
        })
    }
    @ViewBuilder private var savedCheckpoints: some View {
                        if !document.records.isEmpty {
                            Menu("Open a saved checkpoint") {
                                ForEach(document.records.values.sorted { $0.endKey > $1.endKey }) { record in
                                    Button(record.title + " · " + record.endKey) { draft = record; baseline = record }
                                }
                            }.disabled(dirty)
                        }
    }
    var body: some View {
        NavigationStack {
            Form {
                if loadFailed { Section { Text("Saved records could not be opened. They have been kept unchanged."); Button("Try again", action: load) } }
                else {
                    Section {
                        savedCheckpoints
                        if draft != nil {
                            Button("New checkpoint") { draft = nil; baseline = nil; title = "" }.disabled(dirty)
                        }
                    }
                    if let review = draft {
                        Section {
                            Text(review.title).font(.title2.bold())
                            Text(review.startKey + " – " + review.endKey).foregroundStyle(.secondary)
                            Text("\(review.step + 1) of 3 · " + ["Look back", "Review objectives", "Look ahead"][review.step]).font(.headline)
                        }
                        if review.step == 0 {
                            Section {
                                let weeks = review.weeks(in: weekly)
                                if weeks.isEmpty { Text("No saved weekly reviews overlap this period. You can reflect and plan without them.").foregroundStyle(.secondary) }
                                ForEach(weeks) { week in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Week starting " + week.startKey).font(.headline)
                                        if !week.highlights.isEmpty { Text("Highlights: " + week.highlights) }
                                        if !week.learned.isEmpty { Text("Lessons: " + week.learned) }
                                        if !week.direction.isEmpty { Text("Direction: " + week.direction) }
                                        Text(week.completedAt == nil ? "Review in progress" : "Reviewed").font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 4)
                                }
                            } header: { Text("Saved weekly reflections") } footer: { Text("Weeks overlapping the chosen dates are included in full. These are current saved weekly reflections, not a frozen historical summary.") }
                            Section("Highlights and achievements") { TextField("What mattered during this period? (optional)", text: text(\.highlights), axis: .vertical).lineLimit(2...5) }
                            Section("What changed or became clear?") { TextField("Lessons to take forward (optional)", text: text(\.learned), axis: .vertical).lineLimit(2...5) }
                        } else if review.step == 1 {
                            Section { Text("Objectives carry forward from the latest saved checkpoint ending before this period. Changes here belong to this checkpoint; earlier reviews keep their original record.").foregroundStyle(.secondary) }
                            ForEach(review.objectives) { item in
                                Section {
                                    let value = objective(item.id)
                                    TextField("Objective", text: value.title, axis: .vertical)
                                    if let previous = review.startingObjectives.first(where: { $0.id == item.id }) {
                                        Text("Carried forward: " + previous.title + " · " + previous.status.rawValue).font(.caption).foregroundStyle(.secondary)
                                        if !previous.progress.isEmpty { Text("Previous progress: " + previous.progress).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Picker("Status", selection: value.status) { ForEach(ObjectiveStatus.allCases) { Text($0.rawValue).tag($0) } }
                                    TextField("Progress and evidence (optional)", text: value.progress, axis: .vertical).lineLimit(2...5)
                                    TextField("Next useful step (optional)", text: value.nextStep, axis: .vertical).lineLimit(2...5)
                                }
                            }
                            Section {
                                TextField("Something you want to work toward", text: $objectiveTitle, axis: .vertical)
                                Button("Add objective", systemImage: "plus.circle", action: addObjective).disabled(objectiveTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            } header: { Text("Add an objective") } footer: { Text("Pause or let go of an objective when it no longer fits. No objective is required to finish a review.") }
                        } else {
                            Section("Direction for the next period") { TextField("What deserves your attention now? (optional)", text: text(\.direction), axis: .vertical).lineLimit(2...5) }
                            Section {
                                ForEach(review.priorities) { priority in Text(priority.resolve(in: sources)?.card.word ?? priority.title) }
                                    .onDelete { draft?.priorities.remove(atOffsets: $0) }.onMove { draft?.priorities.move(fromOffsets: $0, toOffset: $1) }
                                Button("Choose priorities", systemImage: "plus.circle") { showsPicker = true }.disabled(access == nil)
                            } header: { Text("Connect to your work") } footer: { Text("These links support your direction without moving items or replacing weekly or daily plans. Use Edit to reorder or remove links.") }
                            Section("Risks and constraints ahead") { TextField("What needs preparation or room? (optional)", text: text(\.risks), axis: .vertical).lineLimit(2...5) }
                        }
                        Section {
                            if review.step > 0 { Button("Previous step") { draft?.step -= 1 } }
                            Button(review.step == 2 ? "Save periodic review" : "Save and continue") { save(advance: true) }.font(.headline)
                            Button("Save progress") { save(advance: false) }
                            if let completed = review.completedAt { Text("Reviewed " + completed.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                        }
                    } else {
                        Section("Choose a period or checkpoint") {
                            TextField("Name this checkpoint", text: $title)
                            DatePicker("From", selection: $start, displayedComponents: .date)
                            DatePicker("Through", selection: $end, displayedComponents: .date)
                            Text("Use the same date for a single-day checkpoint. The dates stay fixed after you begin.").font(.footnote).foregroundStyle(.secondary)
                            Button("Begin review", action: begin).disabled(!loaded || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || calendar.startOfDay(for: start) > calendar.startOfDay(for: end))
                        }
                    }
                }
            }
            .navigationTitle("Periodic Review").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { if dirty { confirmsDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { if draft?.step == 2 { EditButton() } }
            }
            .task { if !loaded { load() } }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Discard unsaved checkpoint edits?", isPresented: $confirmsDiscard) { Button("Discard edits", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
            .sheet(isPresented: $showsPicker) { DailyPriorityPicker(sources: sources, priorities: Binding(get: { draft?.priorities ?? [] }, set: { draft?.priorities = $0 })) }
            .alert("Review not updated", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
}
