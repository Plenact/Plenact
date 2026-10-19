import SwiftUI

/// A priority is a link, not a second Card. The original owner prevents numeric-ID collisions.
struct DailyPlanPriority: Codable, Hashable, Identifiable {
    let ownerID: UUID
    let cardID: Int
    let title: String
    let location: String
    let sourceCreatedAt: Date?
    var id: String { "\(ownerID):\(cardID)" }
    init(_ source: PlanningSearchResult) {
        ownerID = source.collectionID
        cardID = source.card.id
        sourceCreatedAt = source.card.createdAt
        title = source.card.word
        location = source.collectionTitle == source.listTitle ? source.listTitle : source.collectionTitle + " · " + source.listTitle
    }
    func resolve(in sources: [PlanningSearchResult]) -> PlanningSearchResult? {
        sources.first { $0.collectionID == ownerID && $0.card.id == cardID && $0.card.createdAt == sourceCreatedAt }
    }
}

struct DailyPlan: Codable, Equatable, Identifiable {
    let id: String
    let timeZoneID: String
    var intention = ""
    var constraints = ""
    var concerns = ""
    var priorities: [DailyPlanPriority] = []
    var updatedAt: Date? = nil
    var checkIn: DailyCheckIn? = nil
    var checkIns: [DailyCheckInEntry]? = nil
    var eveningReview: DailyEveningReview? = nil
    var visionStep: Int? = nil
    var visionCompletedAt: Date? = nil
    init(date: Date, calendar: Calendar = .current) {
        id = PlanningDate.key(date, calendar: calendar)
        timeZoneID = calendar.timeZone.identifier
    }
}

@MainActor
enum DailyPlanStore {
    static let key = "Plenact.DailyPlans.v1"
    struct Document: Codable {
        var version = 1
        var plans: [String: DailyPlan] = [:]
    }
    enum Failure: LocalizedError {
        case unsupported, corrupt, conflict, write
        var errorDescription: String? {
            switch self {
            case .unsupported: "This saved plan format needs a newer version of Plenact. Your saved data has been kept."
            case .corrupt: "Your saved plans could not be read. They have been kept unchanged."
            case .conflict: "This plan changed while it was open. Close and reopen it before saving so the other changes are kept."
            case .write: "The plan could not be saved. Your changes are still open; please try again."
            }
        }
    }
    static func load(from defaults: UserDefaults = .standard) throws -> Document {
        guard defaults.object(forKey: key) != nil else { return Document() }
        guard let data = defaults.data(forKey: key) else { throw Failure.corrupt }
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw Failure.corrupt }
        guard document.version == 1 else { throw Failure.unsupported }
        for (key, plan) in document.plans {
            guard key == plan.id, key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                  TimeZone(identifier: plan.timeZoneID) != nil,
                  Set(plan.priorities.map(\.id)).count == plan.priorities.count,
                  Set((plan.checkIns ?? []).map(\.id)).count == (plan.checkIns ?? []).count,
                  (plan.visionStep.map({ (0...2).contains($0) }) ?? true),
                  (plan.eveningReview.map({ (0...2).contains($0.step) && Set($0.decisions.map(\.id)).count == $0.decisions.count }) ?? true) else { throw Failure.corrupt }
        }
        return document
    }
    /// Merge one day into the latest document, preserving every other day's plan.
    @discardableResult
    static func save(_ plan: DailyPlan, replacing expected: DailyPlan?, to defaults: UserDefaults = .standard) throws -> DailyPlan {
        var document = try load(from: defaults)
        guard document.plans[plan.id] == expected else { throw Failure.conflict }
        guard Set(plan.priorities.map(\.id)).count == plan.priorities.count,
              Set((plan.checkIns ?? []).map(\.id)).count == (plan.checkIns ?? []).count else { throw Failure.corrupt }
        var saved = plan
        saved.updatedAt = .now
        document.plans[saved.id] = saved
        let data = try JSONEncoder().encode(document)
        let previous = defaults.object(forKey: key)
        defaults.set(data, forKey: key)
        guard defaults.synchronize(), defaults.data(forKey: key) == data else {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
            throw Failure.write
        }
        return saved
    }
}

struct TodayPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.planningCalendarAccess) private var access
    @State private var date: Date
    private let defaults: UserDefaults
    @State private var draft: DailyPlan
    @State private var baseline: DailyPlan?
    @State private var loaded = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var showsPicker = false
    @State private var showsNewPriority = false
    @State private var showsVision = false
    @State private var showsReview = false
    @State private var showsCheckIn = false
    @State private var showsDailyReview = false
    @State private var showsWeeklyReview = false
    @State private var showsPeriodicReview = false
    @State private var confirmsDiscard = false
    @State private var openedItem: PlanningSearchResult?
    init(date: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        _date = State(initialValue: date)
        self.defaults = defaults
        _draft = State(initialValue: DailyPlan(date: date, calendar: calendar))
    }
    private var sources: [PlanningSearchResult] { access?.searchableItems ?? [] }
    private var hasChanges: Bool {
        guard loaded, loadError == nil else { return false }
        return draft != (baseline ?? DailyPlan(date: date, calendar: planCalendar))
    }
    private var planCalendar: Calendar {
        var value = Calendar.current
        value.timeZone = TimeZone(identifier: draft.timeZoneID) ?? .current
        return value
    }
    private func load() {
        do {
            let saved = try DailyPlanStore.load(from: defaults).plans[draft.id]
            baseline = saved
            draft = saved ?? draft
            loadError = nil
            loaded = true
        } catch { loadError = error.localizedDescription; loaded = true }
    }
    private func save() {
        do {
            baseline = try DailyPlanStore.save(draft, replacing: baseline, to: defaults)
            draft = baseline!
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
    private func close() {
        if hasChanges { confirmsDiscard = true } else { dismiss() }
    }
    private func saveVisionProgress() -> Bool {
        do {
            let saved = try DailyPlanStore.save(draft, replacing: baseline, to: defaults)
            baseline = saved
            draft = saved
            return true
        } catch { return false }
    }
    private func priorityRow(_ priority: DailyPlanPriority) -> some View {
        let source = priority.resolve(in: sources)
        return Button { openedItem = source } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: source == nil ? "link.badge.plus" : (source?.card.presentation == .note ? "note.text" : (source?.card.isTitleChecked == true ? "checkmark.circle.fill" : "circle")))
                    .foregroundStyle(source?.card.isTitleChecked == true ? Color.green : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(source?.card.word ?? priority.title).font(.headline).foregroundStyle(.primary)
                    if DailyCheckInProgress.focus(plan: draft, sources: sources)?.id == priority.id {
                        Label("Next focus", systemImage: "scope").font(.caption).foregroundStyle(.blue)
                    }
                    Text(source.map { $0.collectionTitle == $0.listTitle ? $0.listTitle : $0.collectionTitle + " · " + $0.listTitle } ?? priority.location)
                        .font(.caption).foregroundStyle(.secondary)
                    if let source {
                        Text(source.card.presentation == .note ? "Note" : (source.card.isTitleChecked ? "Complete" : "Not complete"))
                            .font(.caption).foregroundStyle(source.card.isTitleChecked ? .green : .secondary)
                    } else {
                        Text("Unavailable: archived, removed, or moved to another Board. Remove this link and choose the item again if needed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if source != nil { Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 6).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(source == nil)
        .accessibilityHint(source == nil ? "The saved priority remains in your plan" : "Opens the original item; Back returns to this plan")
    }
    private var planForm: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                    Text("A clear plan for today").font(.title.weight(.bold))
                    Text("Choose what matters, leave room for real life, and take one useful step.").foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
            Section {
                Button { showsVision = true } label: {
                    Label(draft.visionStep != nil ? "Resume today's vision" : (draft.visionCompletedAt == nil ? "Start today's vision" : "Revisit today's vision"), systemImage: "sunrise")
                        .font(.headline).frame(minHeight: 44)
                }.disabled(access == nil)
                Button { showsCheckIn = true } label: {
                    Label("Check in now", systemImage: "sun.max")
                        .font(.headline).frame(minHeight: 44)
                }.disabled(access == nil)
                Button { showsReview = true } label: {
                    Label(draft.eveningReview?.completedAt != nil ? "Revisit today's review" : (draft.eveningReview == nil ? "Start today's review" : "Resume today's review"), systemImage: "moon.stars")
                        .font(.headline).frame(minHeight: 44)
                }.disabled(access == nil)
            } footer: {
                Text("Plan your morning, adjust during the day, and reflect in the evening. Save within each flow to keep your progress.")
            }
            Section {
                Button { showsDailyReview = true } label: {
                    Label("Daily review", systemImage: "list.bullet.clipboard").font(.headline).frame(minHeight: 44)
                }
                Button { showsWeeklyReview = true } label: {
                    Label("Weekly review", systemImage: "calendar.badge.clock").font(.headline).frame(minHeight: 44)
                }.disabled(access == nil)
                Button { showsPeriodicReview = true } label: {
                    Label("Periodic review", systemImage: "flag.checkered").font(.headline).frame(minHeight: 44)
                }.disabled(access == nil)
            }
            Section {
                if draft.priorities.isEmpty {
                    Text("Start with a Card or Note you would like to give attention to today.").foregroundStyle(.secondary)
                }
                ForEach(draft.priorities) { priority in priorityRow(priority) }
                    .onDelete { draft.priorities.remove(atOffsets: $0) }
                    .onMove { draft.priorities.move(fromOffsets: $0, toOffset: $1) }
                Button { showsPicker = true } label: {
                    Label("Choose priorities", systemImage: "plus.circle").frame(minHeight: 44)
                }.disabled(access == nil)
                Button { showsNewPriority = true } label: {
                    Label("Add priority", systemImage: "square.and.pencil").frame(minHeight: 44)
                }.disabled(access == nil)
            } header: { Text("What matters today") }
            footer: { Text("Priorities link to existing items. Choosing, reordering, or removing a priority does not move or delete the original. Swipe to remove a link; use Edit to reorder.") }
            Section("Your intention") {
                TextField("What would make today meaningful? (optional)", text: $draft.intention, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...6)
            }
            Section("Make room for") {
                TextField("Time, energy, or other constraints (optional)", text: $draft.constraints, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...6)
            }
            Section("Risks or concerns") {
                TextField("Anything that could get in the way? (optional)", text: $draft.concerns, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...6)
            }
            Section {
                if let saved = baseline?.updatedAt {
                    Text("Last saved " + saved.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                Text(hasChanges ? "You have unsaved changes. Tap Save to keep your plan on this device." : "Your plan stays on this device. Item status updates as your work changes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    VStack(spacing: 16) {
                        Text("Your plan couldn't be opened").font(.headline)
                        Text(loadError).foregroundStyle(.secondary)
                        Button("Try again", action: load)
                    }.padding()
                } else { planForm.disabled(!loaded) }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today's Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(hasChanges ? "Cancel" : "Done", action: close) }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if loadError == nil { EditButton(); Button("Save", action: save).disabled(!loaded || (!hasChanges && baseline != nil)) }
                }
            }
            .task { if !loaded { load() } }
            .sheet(isPresented: $showsPeriodicReview) { PeriodicReviewView(calendar: access?.document.calendar ?? planCalendar) }
            .sheet(isPresented: $showsWeeklyReview) { WeeklyReviewView(calendar: access?.document.calendar ?? planCalendar) }
            .sheet(isPresented: $showsDailyReview) { DailyHistoryReviewView(date: date, calendar: planCalendar, defaults: defaults) }
            .sheet(isPresented: $showsCheckIn) { TodayCheckInView(plan: $draft, date: date, onSave: saveVisionProgress) }
            .sheet(isPresented: $showsVision) { TodayVisionView(plan: $draft, date: date, onSave: saveVisionProgress) }
            .sheet(isPresented: $showsReview) {
                TodayReviewView(plan: $draft, date: date, baseline: baseline, onSave: saveVisionProgress, onCommitted: { saved in
                    baseline = saved; draft = saved
                })
            }
            .sheet(isPresented: $showsPicker) { DailyPriorityPicker(sources: sources, priorities: $draft.priorities) }
            .sheet(isPresented: $showsNewPriority) {
                NewDailyPriorityView { source in
                    let priority = DailyPlanPriority(source)
                    if !draft.priorities.contains(where: { $0.id == priority.id }) { draft.priorities.append(priority) }
                }
            }
            .fullScreenCover(item: $openedItem) { result in
                if let week = access?.document.weeks.first(where: { $0.id == result.collectionID }) {
                    PlanningCalendarWeekView(week: week, initialDayID: result.listID, initialCardID: result.card.id, onLeaveForHome: { openedItem = nil })
                } else if let owner = access?.library.first(where: { $0.id == result.collectionID && $0.isActive }) {
                    PlanningSearchLibraryView(collection: owner, initialListID: result.listID, initialCardID: result.card.id, onLeaveForHome: { openedItem = nil })
                } else {
                    VStack(spacing: 16) {
                        ContentUnavailableView("Item unavailable", systemImage: "link.badge.plus")
                        Button("Back to plan") { openedItem = nil }.padding()
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog("Discard changes to this plan?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert("Plan not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .presentationBackground(Color(.systemGroupedBackground))
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
    }
}

struct DailyPriorityPicker: View {
    let sources: [PlanningSearchResult]
    @Binding var priorities: [DailyPlanPriority]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var matches: [PlanningSearchResult] {
        sources.filter { query.isEmpty || $0.card.word.localizedStandardContains(query) || $0.collectionTitle.localizedStandardContains(query) || $0.listTitle.localizedStandardContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose existing Cards and Notes. Their locations and contents stay unchanged.").font(.subheadline).foregroundStyle(.secondary)
                }
                if matches.isEmpty { Text("No active Cards or Notes match.").foregroundStyle(.secondary) }
                ForEach(matches) { source in
                    let priority = DailyPlanPriority(source)
                    let selected = priorities.contains { $0.id == priority.id }
                    Button {
                        if selected { priorities.removeAll { $0.id == priority.id } }
                        else { priorities.append(priority) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.card.word).font(.headline).foregroundStyle(.primary)
                                Text(priority.location).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: source.card.presentation == .note ? "note.text" : "rectangle").foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }.accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .navigationTitle("Choose priorities")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a Card, Note, List, or Board")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

@MainActor
enum DailyPriorityCreation {
    static func create(title: String, body: String, presentation: ItemPresentation,
                       destination: WorkspaceListReference, access: PlanningCalendarAccess, attachments: [KanbanAttachment] = []) -> PlanningSearchResult? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let week = access.document.weeks.first { $0.id == destination.ownerID }
        guard var owner = week?.collection ?? access.library.first(where: { $0.id == destination.ownerID && $0.isActive }),
              let index = owner.lists.firstIndex(where: { $0.id == destination.listID && !$0.isArchived }) else { return nil }
        let id = (owner.lists.flatMap(\.allCards).map(\.id).max() ?? -1) + 1
        var card = KanbanCard(id: id, word: title, listTitle: owner.lists[index].title,
            checklists: [], comments: [], members: [], labelIDs: [], attachments: attachments,
            coverAttachmentID: attachments.first(where: { $0.kind == .photo })?.id,
            descriptionOverride: body, subtitleOverride: "", presentation: presentation, createdAt: .now)
        NewCardAppearanceDefaults.apply(to: &card)
        owner.lists[index].cards.append(card)
        let saved: Bool
        if var week { week.collection = owner; saved = access.saveWeek(week) }
        else { saved = access.saveLibrary(owner) }
        guard saved else { return nil }
        return PlanningSearchResult(weekKey: week?.startKey, collectionID: owner.id,
            collectionTitle: week?.rangeTitle ?? owner.title, listID: destination.listID,
            listTitle: card.listTitle, card: card)
    }
}

private struct NewDailyPriorityView: View {
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    let onCreate: (PlanningSearchResult) -> Void
    @StateObject private var attachmentDraft = CreationAttachmentDraft()
    @State private var keyboardContextID = UUID()
    @State private var title = ""
    @State private var bodyText = ""
    @State private var presentation: ItemPresentation = .card
    @State private var destination: WorkspaceListReference?
    @State private var initialized = false
    @State private var error: String?
    @State private var confirmsDiscard = false
    private var destinations: [WorkspaceListDestination] {
        WorkspaceBrowseIndex.lists(in: WorkspaceBrowseIndex.owners(document: access?.document, library: access?.library ?? []))
    }
    private func saveDraft() {
        guard let access, let destination else { return }
        do {
            guard try attachmentDraft.save(commit: { attachments in
                guard let created = DailyPriorityCreation.create(title: title, body: bodyText, presentation: presentation,
                    destination: destination, access: access, attachments: attachments) else { return false }
                onCreate(created)
                return true
            }) else {
                error = "The item could not be saved. Your draft and attachments are still here."
                return
            }
        } catch { self.error = "Attachments couldn't be saved. Your draft is still here; please try again."; return }
        dismiss()
    }
    private func initializeDestination() {
        guard !initialized else { return }
        initialized = true
        for target in destinations where target.owner.kind == .list && target.owner.title == "On the Table" {
            destination = target.reference
            break
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Create", selection: $presentation) {
                        Text("Card").tag(ItemPresentation.card)
                        Text("Note").tag(ItemPresentation.note)
                    }.pickerStyle(.segmented)
                    TextField("Title", text: $title, axis: .vertical).textInputAutocapitalization(.sentences)
                    TextField(presentation == .note ? "Start writing…" : "Details (optional)", text: $bodyText, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(4...10)
                }
                Section("Attachments") { CreationAttachmentList(draft: attachmentDraft) }
                Section("Save in") {
                    Picker("List", selection: $destination) {
                        Text("Choose a List").tag(Optional<WorkspaceListReference>.none)
                        ForEach(destinations) { target in
                            Text(target.owner.kind == .list ? target.owner.title : target.owner.title + " · " + target.list.title)
                                .tag(Optional(target.reference))
                        }
                    }.pickerStyle(.navigationLink)
                    if destinations.isEmpty { Text("Create a List in Plans first, then return here.").foregroundStyle(.secondary) }
                }
                Section {
                    Text("Add saves the original item in this List and selects it in your plan. Tap Save on Today's Plan to keep the priority link. Canceling this composer creates nothing.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add priority")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if title.isEmpty && bodyText.isEmpty && attachmentDraft.entries.isEmpty { dismiss() } else { confirmsDiscard = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveDraft()
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destination == nil || access == nil || attachmentDraft.isImporting)
                }
            }
            .onAppear(perform: initializeDestination)
        }
        .modifier(CreationAttachmentPresentation(draft: attachmentDraft))
        .onAppear {
            PlenactKeyboard.shared.setContext(keyboardContextID, actions: KeyboardCardActions(
                exit: { confirmsDiscard = true }, attachment: attachmentDraft.openSources, showsUpperBorder: true))
        }
        .onDisappear { PlenactKeyboard.shared.removeContext(keyboardContextID) }
        .interactiveDismissDisabled(!title.isEmpty || !bodyText.isEmpty || !attachmentDraft.entries.isEmpty)
        .confirmationDialog("Discard this priority draft?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert("Priority not added", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

/// Morning suggestions are a projection of canonical dated content, never automatic moves.
enum TodayVisionSelection {
    static func candidates(date: Date, access: PlanningCalendarAccess, referenceLabelIDs: Set<String>, calendar: Calendar) -> [PlanningSearchResult] {
        let key = PlanningDate.key(date, calendar: calendar)
        let datedList = access.document.week(for: date, calendar: calendar).flatMap { week in
            week.dayListIDs[key].map { (week.id, $0) }
        }
        return access.searchableItems.filter { item in
            guard !item.card.isTitleChecked, Set(item.card.labelIDs).isDisjoint(with: referenceLabelIDs) else { return false }
            let onDay = datedList.map { $0.0 == item.collectionID && $0.1 == item.listID } ?? false
            let dated = [item.card.startDate, item.card.dueDate].compactMap { $0 }.contains { calendar.isDate($0, inSameDayAs: date) }
            let spanning: Bool
            if let start = item.card.startDate, let end = item.card.dueDate {
                spanning = calendar.startOfDay(for: start) <= calendar.startOfDay(for: date) && calendar.startOfDay(for: end) >= calendar.startOfDay(for: date)
            } else { spanning = false }
            return onDay || dated || spanning
        }
    }
}

struct TodayVisionView: View {
    @Binding var plan: DailyPlan
    let date: Date
    let onSave: () -> Bool
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var showsPicker = false
    @State private var showsNew = false
    @State private var transfer: PlanningSearchResult?
    @State private var transferError = false
    @State private var planSaveFailed = false
    @State private var saving = false
    private var calendar: Calendar {
        var result = access?.document.calendar ?? .current
        result.timeZone = TimeZone(identifier: plan.timeZoneID) ?? .current
        return result
    }
    private var sources: [PlanningSearchResult] { access?.searchableItems ?? [] }
    private var candidates: [PlanningSearchResult] {
        guard let access else { return [] }
        let labels = LabelLibraryStore.load().labels.filter { $0.name.caseInsensitiveCompare("Reference") == .orderedSame || $0.id == LabelLibrary.referenceLabel.id }
        return TodayVisionSelection.candidates(date: date, access: access, referenceLabelIDs: Set(labels.map(\.id)), calendar: calendar)
    }
    private var table: WorkspaceListDestination? {
        WorkspaceBrowseIndex.lists(in: access?.library ?? []).first { $0.owner.kind == .list && $0.owner.title == "On the Table" }
    }
    private func isScheduled(_ source: PlanningSearchResult) -> Bool {
        access?.library.contains { $0.id == source.collectionID && $0.kind == .list && $0.title == "Scheduled" } == true
    }
    private func select(_ source: PlanningSearchResult) {
        let priority = DailyPlanPriority(source)
        if !plan.priorities.contains(where: { $0.id == priority.id }) { plan.priorities.append(priority) }
    }
    private func advance() {
        guard !saving else { return }; saving = true
        let previousStep = plan.visionStep
        let previousCompletion = plan.visionCompletedAt
        plan.visionStep = step == 2 ? nil : step + 1
        if step == 2 { plan.visionCompletedAt = .now }
        if onSave() {
            if step == 2 { dismiss() } else { step += 1 }
        } else {
            plan.visionStep = previousStep
            plan.visionCompletedAt = previousCompletion
            planSaveFailed = true
        }
        saving = false
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(step + 1) of 3 · " + ["What's already ahead?", "What matters most?", "What's realistic?"][step]).font(.headline)
                        Text(date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                        ProgressView(value: Double(step + 1), total: 3).accessibilityLabel("Morning plan, step \(step + 1) of 3")
                    }.padding(.vertical, 4)
                }
                if step == 0 {
                    Section {
                        Text("A look at today's Day List and items with a start or due date today. Nothing moves unless you confirm it.").foregroundStyle(.secondary)
                        if candidates.isEmpty { Text("Nothing dated for today needs attention. You can choose any priorities in the next step.") }
                        ForEach(candidates) { source in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(source.card.word).font(.headline)
                                Text(source.collectionTitle + " · " + source.listTitle).font(.caption).foregroundStyle(.secondary)
                                Button(plan.priorities.contains(where: { $0.id == source.id }) ? "Selected for today" : "Make a priority") { select(source) }
                                    .disabled(plan.priorities.contains(where: { $0.id == source.id }))
                                if isScheduled(source), table != nil, access?.moveForDailyPlan != nil {
                                    Button("Move to On the Table", systemImage: "arrow.right.circle") { transfer = source }
                                }
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("Ahead today") }
                    if table == nil { Text("On the Table isn't available. You can still plan using items in their current locations.").font(.footnote).foregroundStyle(.secondary) }
                } else if step == 1 {
                    Section {
                        if plan.priorities.isEmpty { Text("A small plan is enough. Choose what deserves your attention.").foregroundStyle(.secondary) }
                        ForEach(plan.priorities) { priority in
                            HStack {
                                Text(priority.resolve(in: sources)?.card.word ?? priority.title)
                                Spacer()
                                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
                            }
                        }
                        .onDelete { plan.priorities.remove(atOffsets: $0) }
                        .onMove { plan.priorities.move(fromOffsets: $0, toOffset: $1) }
                        Button("Choose priorities", systemImage: "plus.circle") { showsPicker = true }
                        Button("Add priority", systemImage: "square.and.pencil") { showsNew = true }
                    } header: { Text("In the order that matters") }
                    footer: { Text("Use Edit to reorder or remove links. The original items stay where they are.") }
                } else {
                    Section("Your intention") { TextField("What would make today meaningful?", text: $plan.intention, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...5) }
                    Section("Make room for") { TextField("Available time, energy, or other constraints", text: $plan.constraints, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...5) }
                    Section("Risks or concerns") { TextField("Anything that might get in the way?", text: $plan.concerns, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...5) }
                    Section { Text("These reflections are optional. Choose a plan that fits the day you have.").foregroundStyle(.secondary) }
                }
                Section {
                    if step > 0 { Button("Previous step") { step -= 1 } }
                    Button(step == 2 ? "Save today's vision" : "Save and continue", action: advance)
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44).disabled(saving)
                    Text("Each step saves your plan so you can return later. Confirmed moves are saved immediately and are not undone by leaving this flow.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Today's Vision").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Plan", systemImage: "chevron.left") { dismiss() }.accessibilityLabel("Back to Today’s Plan") }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if step == 1 { EditButton() }
                }
            }
            .onAppear { step = min(2, max(0, plan.visionStep ?? 0)) }
            .sheet(isPresented: $showsPicker) { DailyPriorityPicker(sources: sources, priorities: $plan.priorities) }
            .sheet(isPresented: $showsNew) { NewDailyPriorityView { select($0) } }
            .confirmationDialog("Move to On the Table?", isPresented: Binding(get: { transfer != nil }, set: { if !$0 { transfer = nil } }), titleVisibility: .visible) {
                Button("Move original item") {
                    guard let source = transfer, let table,
                          let moved = access?.moveForDailyPlan?(source, table.reference) else { transferError = true; transfer = nil; return }
                    let reference = DailyPlanPriority(moved)
                    if let index = plan.priorities.firstIndex(where: { $0.id == source.id }) { plan.priorities[index] = reference }
                    else { select(moved) }
                    transfer = nil
                    // The move is already committed; retain the link and report any plan-save failure.
                    if !onSave() { planSaveFailed = true }
                }
                Button("Cancel", role: .cancel) { transfer = nil }
            } message: {
                Text("Moves ‘\(transfer?.card.word ?? "")’ from Scheduled to On the Table and selects it for today. Dates, times, and details are retained. This does not create a second item.")
            }
            .alert("Plan not saved", isPresented: $planSaveFailed) { Button("OK", role: .cancel) {} }
                message: { Text("Your draft is still open. The saved plan may have changed, or saving failed. Return to your plan to review it and retry. Any confirmed item moves remain saved.") }
            .alert("Item wasn't moved", isPresented: $transferError) { Button("OK", role: .cancel) {} }
                message: { Text("The source or destination may have changed, or saving failed. Your original item has been retained. Please try again.") }
        }
    }
}


struct DailyCheckIn: Codable, Equatable {
    var focus: DailyPlanPriority? = nil
    var changed = ""
    var savedAt: Date? = nil
}

/// Stored as values so custom feelings and future preset changes preserve the original entry.
struct CheckInMood: Codable, Equatable {
    let emoji: String
    let label: String
    var display: String { emoji + " " + label }
    static func custom(emoji: String, label: String) -> CheckInMood? {
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = emoji.unicodeScalars
        let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.contains { $0.value == 0xFE0F } && scalars.contains { $0.properties.isEmoji })
        guard emoji.count == 1, isEmoji, !label.isEmpty, label.count <= 40 else { return nil }
        return CheckInMood(emoji: emoji, label: label)
    }
}

enum CheckInMoodChoice: String, CaseIterable, Identifiable {
    case none, great, good, okay, low, struggling, custom
    var id: Self { self }
    var mood: CheckInMood? {
        switch self {
        case .none, .custom: nil
        case .great: CheckInMood(emoji: "😊", label: "Great")
        case .good: CheckInMood(emoji: "🙂", label: "Good")
        case .okay: CheckInMood(emoji: "😐", label: "Okay")
        case .low: CheckInMood(emoji: "😔", label: "Low")
        case .struggling: CheckInMood(emoji: "😣", label: "Struggling")
        }
    }
    var title: String {
        switch self {
        case .none: "Not selected"
        case .custom: "Custom…"
        default: mood?.display ?? ""
        }
    }
}

/// A submitted moment retains its own context even as the shared plan changes.
struct DailyCheckInEntry: Codable, Equatable, Identifiable {
    let id: String
    let savedAt: Date
    let changed: String
    let focus: DailyPlanPriority?
    let intention: String
    let constraints: String
    let concerns: String
    let priorities: [DailyPlanPriority]
    let completedTasks: Int?
    let totalTasks: Int?
    let notes: Int?
    let unavailable: Int?
    let legacy: Bool
    var mood: CheckInMood? = nil
}

extension DailyPlan {
    /// Legacy records have no historical plan/progress snapshot. Do not invent one.
    var checkInHistory: [DailyCheckInEntry] {
        if let checkIns { return checkIns }
        guard let saved = checkIn, let timestamp = saved.savedAt else { return [] }
        return [.init(id: "legacy:" + id, savedAt: timestamp, changed: saved.changed,
                      focus: saved.focus, intention: "", constraints: "", concerns: "", priorities: [],
                      completedTasks: nil, totalTasks: nil, notes: nil, unavailable: nil, legacy: true)]
    }
    mutating func recordCheckIn(changed: String, sources: [PlanningSearchResult], at timestamp: Date = .now, mood: CheckInMood? = nil) {
        var entries = checkInHistory
        let focus = DailyCheckInProgress.focus(plan: self, sources: sources)
        let progress = DailyCheckInProgress.counts(plan: self, sources: sources)
        entries.append(.init(id: UUID().uuidString, savedAt: timestamp, changed: changed, focus: focus,
                             intention: intention, constraints: constraints, concerns: concerns, priorities: priorities,
                             completedTasks: progress.completed, totalTasks: progress.tasks,
                             notes: progress.notes, unavailable: progress.unavailable, legacy: false, mood: mood))
        checkIns = entries
        checkIn = DailyCheckIn(focus: focus, changed: changed, savedAt: timestamp)
    }
}

/// Saved records only: opening or browsing this view never writes a plan.
struct DailyHistoryReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.scenePhase) private var scenePhase
    @State private var date: Date
    @State private var document = DailyPlanStore.Document()
    @State private var loadError: String?
    @AppStorage private var storedData: Data
    private let calendar: Calendar
    private let defaults: UserDefaults
    init(date: Date, calendar: Calendar, defaults: UserDefaults = .standard) {
        _date = State(initialValue: date)
        self.calendar = calendar; self.defaults = defaults
        _storedData = AppStorage(wrappedValue: Data(), DailyPlanStore.key, store: defaults)
    }
    private var plan: DailyPlan? { document.plans[PlanningDate.key(date, calendar: calendar)] }
    private var isToday: Bool { calendar.isDateInToday(date) }
    private func reload() {
        do { document = try DailyPlanStore.load(from: defaults); loadError = nil }
        catch { loadError = error.localizedDescription }
    }
    private func checkInTime(_ timestamp: Date, timeZoneID: String) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: timeZoneID) ?? calendar.timeZone
        return timestamp.formatted(style)
    }
    private func text(_ title: String, _ value: String) -> some View {
        Group {
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value)
                }
            }
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Review day", selection: $date, displayedComponents: .date)
                    Text("Saved records only. Save an open Check-in or plan before reviewing its changes here.").font(.caption).foregroundStyle(.secondary)
                    Menu("Saved days") {
                        ForEach(document.plans.keys.sorted(by: >), id: \.self) { key in
                            if let day = PlanningDate.date(key, calendar: calendar) {
                                Button(day.formatted(date: .abbreviated, time: .omitted)) { date = day }
                            }
                        }
                    }.disabled(document.plans.isEmpty)
                }
                if let loadError {
                    Section("Your records couldn't be opened") {
                        Text(loadError)
                        Button("Try again", action: reload)
                    }
                } else if let plan {
                    Section(isToday ? "Your day so far" : "Saved daily plan") {
                        text("Intention", plan.intention)
                        if isToday {
                            let counts = DailyCheckInProgress.counts(plan: plan, sources: access?.searchableItems ?? [])
                            Text("\(counts.completed) of \(counts.tasks) priority tasks complete").font(.headline)
                            if counts.tasks > 0 { ProgressView(value: Double(counts.completed), total: Double(counts.tasks)) }
                            Text("\(counts.notes) Notes · \(counts.unavailable) unavailable links").font(.caption).foregroundStyle(.secondary)
                            Text("Progress reflects your linked items now.").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(plan.checkInHistory.count) saved Check-ins")
                        if isToday, let focus = DailyCheckInProgress.focus(plan: plan, sources: access?.searchableItems ?? []) {
                            text("Your next focus", focus.resolve(in: access?.searchableItems ?? [])?.card.word ?? focus.title)
                        }
                        text("Make room for", plan.constraints)
                        text("Risks or concerns", plan.concerns)
                        ForEach(plan.priorities) { priority in Text(priority.title) }
                        if !isToday { Text("Saved priorities are context; completion at each Check-in is recorded below.").font(.caption).foregroundStyle(.secondary) }
                    }
                    Section("Check-ins · " + plan.timeZoneID) {
                        if plan.checkInHistory.isEmpty { Text("No saved Check-ins for this day.").foregroundStyle(.secondary) }
                        ForEach(plan.checkInHistory.sorted { $0.savedAt < $1.savedAt }) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(checkInTime(entry.savedAt, timeZoneID: plan.timeZoneID)).font(.headline)
                                    if let mood = entry.mood { Text(mood.display).font(.subheadline) }
                                }.accessibilityElement(children: .combine)
                                if entry.changed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Checked in without a note").foregroundStyle(.secondary)
                                } else { Text(entry.changed) }
                                if let completed = entry.completedTasks, let total = entry.totalTasks {
                                    Text("\(completed) of \(total) priority tasks complete at this Check-in").font(.subheadline)
                                    Text("\(entry.notes ?? 0) Notes · \(entry.unavailable ?? 0) unavailable links").font(.caption).foregroundStyle(.secondary)
                                }
                                if let focus = entry.focus { text("Next focus", focus.title) }
                                if entry.legacy {
                                    Text("Retained from the original Check-in. A plan and progress snapshot was not recorded at that time.").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    DisclosureGroup("Plan at this Check-in") {
                                        text("Intention", entry.intention)
                                        text("Make room for", entry.constraints)
                                        text("Risks or concerns", entry.concerns)
                                        ForEach(entry.priorities) { priority in Text(priority.title) }
                                    }
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                    if let review = plan.eveningReview {
                        Section("Evening review") {
                            Text(review.completedAt == nil ? "In progress" : "Completed")
                            text("What helped", review.helped)
                            text("What was difficult", review.difficult)
                            text("Carry into tomorrow", review.tomorrow)
                            ForEach(review.achievements) { item in Text(item.title) }
                        }
                    }
                } else {
                    Section { Text("No saved plan or Check-ins for this day.").foregroundStyle(.secondary) }
                }
            }
            .textSelection(.enabled)
            .navigationTitle("Daily review").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { reload() }
            .onChange(of: storedData) { _, _ in reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        }
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
    }
}

/// Live progress counts tasks only; Notes and unavailable links remain separate context.
enum DailyCheckInProgress {
    static func counts(plan: DailyPlan, sources: [PlanningSearchResult]) -> (completed: Int, tasks: Int, notes: Int, unavailable: Int) {
        var result = (completed: 0, tasks: 0, notes: 0, unavailable: 0)
        for priority in plan.priorities {
            guard let source = priority.resolve(in: sources) else { result.unavailable += 1; continue }
            if source.card.presentation == .note { result.notes += 1 }
            else { result.tasks += 1; if source.card.isTitleChecked { result.completed += 1 } }
        }
        return result
    }
    static func focus(plan: DailyPlan, sources: [PlanningSearchResult]) -> DailyPlanPriority? {
        guard let focus = plan.checkIn?.focus,
              plan.priorities.contains(where: { $0 == focus }),
              let source = focus.resolve(in: sources),
              source.card.presentation == .note || !source.card.isTitleChecked else { return nil }
        return focus
    }
}

struct TodayCheckInView: View {
    @Binding var plan: DailyPlan
    let date: Date
    let onSave: () -> Bool
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var showsPicker = false
    @State private var showsNew = false
    @State private var saveFailed = false
    private var sources: [PlanningSearchResult] { access?.searchableItems ?? [] }
    private var checkIn: DailyCheckIn { plan.checkIn ?? DailyCheckIn() }
    @State private var changed = ""
    @State private var moodChoice: CheckInMoodChoice = .none
    @State private var customEmoji = ""
    @State private var customFeeling = ""
    private var selectedMood: CheckInMood? {
        moodChoice == .custom ? CheckInMood.custom(emoji: customEmoji, label: customFeeling) : moodChoice.mood
    }
    private var hasUnsavedCheckIn: Bool {
        !changed.isEmpty || moodChoice != .none || !customEmoji.isEmpty || !customFeeling.isEmpty
    }
    @State private var didSave = false
    @State private var selectedFocus: DailyPlanPriority?
    init(plan: Binding<DailyPlan>, date: Date, onSave: @escaping () -> Bool) {
        _plan = plan; self.date = date; self.onSave = onSave
        _selectedFocus = State(initialValue: plan.wrappedValue.checkIn?.focus)
    }
    private var focusPlan: DailyPlan {
        var result = plan
        var latest = checkIn; latest.focus = selectedFocus; result.checkIn = latest
        return result
    }
    @State private var confirmsLeaving = false
    private func selectFocus(_ priority: DailyPlanPriority?) {
        selectedFocus = priority
    }
    private func save() {
        guard !didSave, moodChoice != .custom || selectedMood != nil else { return }
        let previous = plan
        plan.checkIns = plan.checkInHistory
        plan.checkIn = focusPlan.checkIn
        plan.recordCheckIn(changed: changed, sources: sources, mood: selectedMood)
        if onSave() { didSave = true; dismiss() }
        else { plan = previous; saveFailed = true }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A moment to reset").font(.title2.bold())
                    Text(date.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                    Text("Notice where you are, adjust your plan, and choose one useful next step.").foregroundStyle(.secondary)
                }
                Section("Where am I?") {
                    let progress = DailyCheckInProgress.counts(plan: plan, sources: sources)
                    Text("\(progress.completed) of \(progress.tasks) priority tasks complete").font(.headline)
                    if progress.tasks > 0 { ProgressView(value: Double(progress.completed), total: Double(progress.tasks)) }
                    if progress.notes > 0 { Text("\(progress.notes) linked Notes for context").foregroundStyle(.secondary) }
                    if progress.unavailable > 0 { Text("\(progress.unavailable) unavailable links · saved context retained").foregroundStyle(.secondary) }
                    if plan.priorities.isEmpty { Text("You can start a plan now, even without a morning review.").foregroundStyle(.secondary) }
                }
                Section {
                    ForEach(plan.priorities) { priority in
                        let source = priority.resolve(in: sources)
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: source == nil ? "link.badge.plus" : (source?.card.presentation == .note ? "note.text" : (source?.card.isTitleChecked == true ? "checkmark.circle.fill" : "circle")))
                                .foregroundStyle(source?.card.isTitleChecked == true ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(source?.card.word ?? priority.title).font(.headline)
                                Text(source == nil ? "Unavailable · remove this link and choose the item again if needed" : (source?.card.presentation == .note ? "Note" : (source?.card.isTitleChecked == true ? "Complete" : "Not complete"))).font(.caption).foregroundStyle(.secondary)
                                if let source, source.card.presentation == .note || !source.card.isTitleChecked {
                                    let focused = DailyCheckInProgress.focus(plan: focusPlan, sources: sources)?.id == priority.id
                                    Button(focused ? "Next focus ✓" : "Focus on this next") { selectFocus(focused ? nil : priority) }
                                        .accessibilityValue(focused ? "Selected" : "Not selected")
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    .onDelete { plan.priorities.remove(atOffsets: $0) }
                    .onMove { plan.priorities.move(fromOffsets: $0, toOffset: $1) }
                    Button("Choose priorities", systemImage: "plus.circle") { showsPicker = true }
                    Button("Add priority", systemImage: "square.and.pencil") { showsNew = true }
                } header: { Text("What matters next?") }
                footer: { Text("Use Edit to reorder or set a priority aside. Removing a link keeps the original item in place. Your next focus is optional.") }
                Section {
                    Picker("Mood", selection: $moodChoice) {
                        ForEach(CheckInMoodChoice.allCases) { choice in Text(choice.title).tag(choice) }
                    }.pickerStyle(.menu)
                    if moodChoice == .custom {
                        TextField("Emoji", text: $customEmoji)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityHint("Enter one emoji using the emoji keyboard")
                        TextField("Feeling, such as quietly hopeful", text: $customFeeling).textInputAutocapitalization(.sentences)
                            .onChange(of: customFeeling) { _, value in customFeeling = String(value.prefix(40)) }
                        if selectedMood == nil {
                            Text("Enter one emoji and a feeling of up to 40 characters.").font(.caption).foregroundStyle(.secondary)
                        } else if let selectedMood {
                            Text(selectedMood.display).accessibilityLabel("Your mood: " + selectedMood.display)
                        }
                    }
                } header: { Text("How are you feeling?") }
                footer: { Text("Optional. Choose what fits this moment; each new Check-in starts fresh.") }
                Section("What changed?") { TextField("New information, a small win, or a change of plan (optional)", text: $changed, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...5) }
                Section("Is this still realistic?") {
                    TextField("Your intention", text: $plan.intention, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...5)
                    TextField("Available time, energy, or other constraints", text: $plan.constraints, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...5)
                    TextField("Risks or concerns", text: $plan.concerns, axis: .vertical).textInputAutocapitalization(.sentences).lineLimit(2...5)
                }
                Section {
                    Button("Save check-in", action: save).disabled(moodChoice == .custom && selectedMood == nil).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    if let saved = checkIn.savedAt { Text("Last check-in " + saved.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    Text("Each Save adds a timestamped entry to Daily review and updates your shared daily plan. Plan adjustments stay open when returning to Plan; an unsaved Check-in note or mood must be saved here.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Today's Check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Plan", systemImage: "chevron.left") { if hasUnsavedCheckIn { confirmsLeaving = true } else { dismiss() } }.accessibilityLabel("Back to Today's Plan") }
                ToolbarItem(placement: .confirmationAction) { EditButton() }
            }
            .sheet(isPresented: $showsPicker) { DailyPriorityPicker(sources: sources, priorities: $plan.priorities) }
            .sheet(isPresented: $showsNew) { NewDailyPriorityView { source in
                let priority = DailyPlanPriority(source)
                if !plan.priorities.contains(where: { $0.id == priority.id }) { plan.priorities.append(priority) }
            } }
            .interactiveDismissDisabled(hasUnsavedCheckIn)
            .confirmationDialog("Leave without saving this Check-in?", isPresented: $confirmsLeaving, titleVisibility: .visible) {
                Button("Discard Check-in and return to Plan", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Check-in not saved", isPresented: $saveFailed) { Button("OK", role: .cancel) {} }
                message: { Text("Your edits are still open. The saved plan may have changed, or saving failed. Return to Plan to save or reopen it before retrying.") }
        }
    }
}

/// Read-only front door to the same saved daily plan used by every daily review.
struct TodayPlanSummaryPanel: View {
    @ScaledMetric(relativeTo: .title2) private var headingSize: CGFloat = 26
    @ScaledMetric(relativeTo: .headline) private var subtitleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 19
    let date: Date
    let calendar: Calendar
    let sources: [PlanningSearchResult]
    let onOpen: () -> Void
    let welcomesPlan: Bool
    private let defaults: UserDefaults
    @AppStorage private var storedData: Data
    @Environment(\.scenePhase) private var scenePhase
    @State private var plan: DailyPlan?
    @State private var readFailed = false
    init(date: Date, calendar: Calendar, sources: [PlanningSearchResult], defaults: UserDefaults = .standard, welcomesPlan: Bool = false, onOpen: @escaping () -> Void) {
        self.welcomesPlan = welcomesPlan
        self.date = date; self.calendar = calendar; self.sources = sources; self.defaults = defaults; self.onOpen = onOpen
        _storedData = AppStorage(wrappedValue: Data(), DailyPlanStore.key, store: defaults)
    }
    private func reload() {
        do {
            plan = try DailyPlanStore.load(from: defaults).plans[PlanningDate.key(date, calendar: calendar)]
            readFailed = false
        } catch { plan = nil; readFailed = true }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("☀️").accessibilityHidden(true)
                Text("Today's Plan")
            }
            .font(.system(size: headingSize, weight: .semibold))
            .modifier(TodayWelcomeGlow(highlighted: welcomesPlan))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if readFailed {
                Text("Your saved plan couldn't be read. Open Today's Plan to review the issue. Your records have been kept unchanged.").foregroundStyle(.secondary)
            } else if let plan {
                if !plan.intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(plan.intention).font(.system(size: subtitleSize, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                if let focus = DailyCheckInProgress.focus(plan: plan, sources: sources), let source = focus.resolve(in: sources) {
                    Label("Next focus · " + source.card.word, systemImage: "scope").font(.system(size: bodySize)).foregroundStyle(.blue)
                }
                if plan.priorities.isEmpty {
                    Text("What deserves your attention today? Choose a Card or Note, or add a new priority in your plan.").foregroundStyle(.secondary)
                } else {
                    Text("Your chosen priorities").font(.system(size: bodySize)).foregroundStyle(.secondary)
                    ForEach(Array(plan.priorities.prefix(3))) { priority in
                        let source = priority.resolve(in: sources)
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: source == nil ? "link.badge.plus" : (source?.card.presentation == .note ? "note.text" : (source?.card.isTitleChecked == true ? "checkmark.circle.fill" : "circle")))
                                .foregroundStyle(source?.card.isTitleChecked == true ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source?.card.word ?? priority.title).font(.system(size: bodySize, weight: .semibold))
                                Text(source == nil ? "Unavailable · saved context retained" : (source?.card.presentation == .note ? "Note" : (source?.card.isTitleChecked == true ? "Complete" : "Not complete")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.accessibilityElement(children: .combine)
                    }
                    if plan.priorities.count > 3 {
                        Text("\(plan.priorities.count - 3) more priorities in your plan").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("What would make today meaningful?").font(.system(size: subtitleSize, weight: .semibold))
                Text("Choose a few priorities, leave room for real life, and take one useful step. Your morning vision, check-in, and evening review all connect here.").foregroundStyle(.secondary)
            }
            Button(action: onOpen) {
                Label(plan == nil && !readFailed ? "Plan today" : "Open today's plan", systemImage: "arrow.up.right")
                    .frame(minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).foregroundStyle(.blue)
                .accessibilityHint("Opens Today's Plan and the Planning Rhythm reviews")
        }
        .font(.system(size: bodySize))
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: PlanningDate.key(date, calendar: calendar)) { reload() }
        .onChange(of: storedData) { _, _ in reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }
}
