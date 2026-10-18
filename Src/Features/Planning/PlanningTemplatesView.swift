import SwiftUI

struct PlanningTemplatesView: View {
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var library: PlanningRoutineLibrary?
    @State private var sourceDate = Date.now
    @State private var editing: PlanningRoutineTemplate?
    @State private var applying: PlanningRoutineTemplate?
    @State private var deleting: PlanningRoutineTemplate?
    @State private var message: String?
    private func reload() {
        do { library = try PlanningRoutineStore.load() }
        catch { library = nil; message = "Templates couldn't be read. Your saved data has been retained. Please retry." }
    }
    @discardableResult private func update(_ change: (inout PlanningRoutineLibrary) -> Void) -> Bool {
        guard let baseline = library else { return false }
        var next = baseline; change(&next)
        do { try PlanningRoutineStore.save(next, baseline: baseline); library = next; return true }
        catch { message = "Templates couldn't be saved, or changed elsewhere. Close this draft and retry after reloading."; return false }
    }
    private func capture(_ kind: PlanningRoutineTemplate.Kind) {
        guard let access, let week = access.document.week(for: sourceDate) else {
            message = "There is no saved plan for that date yet. Open and plan its week first."; return
        }
        do {
            editing = try PlanningRoutineTemplate.capture(name: kind == .day ? "My Day" : "My Week", week: week,
                day: kind == .day ? sourceDate : nil, calendar: access.document.calendar)
        } catch { message = "That day has no active list to save as a template." }
    }
    var body: some View {
        NavigationStack {
            List {
                if let library {
                    Section {
                        Picker("New weeks use", selection: Binding(get: { self.library?.defaultWeekID }, set: { value in _ = update { $0.defaultWeekID = value } })) {
                            Text("Empty week").tag(nil as UUID?)
                            ForEach(library.templates.filter { $0.kind == .week }) { template in
                                Text(template.name).tag(Optional(template.id))
                            }
                        }
                    } header: { Text("Default Week") } footer: {
                        Text("Applied once when a new week is created. Existing weeks keep their plans. Editing a template affects future applications only.")
                    }
                    Section("Your templates") {
                        ForEach(library.templates) { template in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(template.name, systemImage: template.kind == .week ? "calendar" : "sun.max")
                                        .font(.headline)
                                    Spacer()
                                    if template.id == library.defaultWeekID { Text("Default").font(.caption).foregroundStyle(.secondary) }
                                    Menu {
                                        Button("Edit template", systemImage: "pencil") { editing = template }
                                        Button("Duplicate", systemImage: "plus.square.on.square") {
                                            var copy = template; copy.id = UUID(); copy.name += " Copy"; editing = copy
                                        }
                                        Button("Delete template", systemImage: "trash", role: .destructive) { deleting = template }
                                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                    .accessibilityLabel(template.name + " actions")
                                }
                                Text("\(template.kind.rawValue) · \(template.itemCount) items").font(.caption).foregroundStyle(.secondary)
                                Button("Preview & apply", systemImage: "calendar.badge.plus") { applying = template }
                                    .frame(minHeight: 44)
                            }.padding(.vertical, 4)
                        }
                    }
                    Section {
                        DatePicker("Source day / week", selection: $sourceDate, displayedComponents: .date)
                        Button("Save day as template", systemImage: "sun.max") { capture(.day) }
                        Button("Save week as template", systemImage: "calendar") { capture(.week) }
                    } header: { Text("Save your layout") } footer: {
                        Text("Includes active lists, Cards, Notes, checklists and media. New copies start unchecked, with dates shifted to their destination. Archives and activity history are excluded.")
                    }
                    Section("Examples") {
                        Button("Preview Example Week", systemImage: "sparkles") {
                            var example = PlanningRoutineLibrary.seeded.templates[0]
                            example.id = UUID(); example.name = "Example Week"; editing = example
                        }
                        Text("Work Week starts from Plenact's example layout. Customize it here or save your own planned week.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView("Templates unavailable", systemImage: "square.stack.3d.up")
                    Button("Retry", action: reload)
                }
            }
            .navigationTitle("Day & Week Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Reload", systemImage: "arrow.clockwise", action: reload) }
            }
            .task { reload() }
            .sheet(item: $editing) { template in
                PlanningTemplateEditor(template: template) { updated in
                    update { library in
                        if let index = library.templates.firstIndex(where: { $0.id == updated.id }) { library.templates[index] = updated }
                        else { library.templates.append(updated) }
                    }
                }
            }
            .sheet(item: $applying) { template in PlanningTemplateApplyView(template: template) }
            .confirmationDialog("Delete this template?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let deleting {
                    Button("Delete " + deleting.name, role: .destructive) {
                        _ = update { library in
                            library.templates.removeAll { $0.id == deleting.id }
                            if library.defaultWeekID == deleting.id { library.defaultWeekID = nil }
                        }
                        self.deleting = nil
                    }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("Applied days and weeks remain. Deleting the default switches new weeks to Empty week.") }
            .alert("Templates", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
        .presentationDetents([.large])
    }
}

struct PlanningTemplateEditor: View {
    @State var template: PlanningRoutineTemplate
    let onSave: (PlanningRoutineTemplate) -> Bool
    private let original: PlanningRoutineTemplate
    init(template: PlanningRoutineTemplate, onSave: @escaping (PlanningRoutineTemplate) -> Bool) {
        _template = State(initialValue: template)
        self.original = template
        self.onSave = onSave
    }
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Name", text: $template.name)
                    LabeledContent("Kind", value: template.kind.rawValue)
                    Text("These are reusable items. Completion and activity history reset when applied.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(template.collection.lists.indices, id: \.self) { index in
                    PlanningTemplateListEditor(list: $template.collection.lists[index], allLists: template.collection.lists,
                        anchor: PlanningDate.date(template.anchorKey, calendar: template.calendar) ?? .now)
                }
            }
            .navigationTitle("Edit template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        template.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSave(template) { dismiss() } else { failed = true }
                    }.disabled(template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Template not saved", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Your draft is still open. Check the template name and retry, or close it and reload Templates if another window made changes.") }
        }
        .interactiveDismissDisabled(template != original)
        .presentationDetents([.large])
    }
}

private struct PlanningTemplateListEditor: View {
    @Binding var list: KanbanList
    let allLists: [KanbanList]
    let anchor: Date
    var body: some View {
        Section(list.title) {
            ForEach($list.cards) { $card in
                NavigationLink {
                    PlanningTemplateCardEditor(card: $card, anchor: anchor)
                } label: {
                    Label(card.word, systemImage: card.isSectionDivider ? "minus" : (card.presentation == .note ? "note.text" : "square"))
                }
            }
            .onDelete { list.cards.remove(atOffsets: $0) }
            .onMove { list.cards.move(fromOffsets: $0, toOffset: $1) }
            Menu("Add item", systemImage: "plus") {
                Button("Card") { add(.card) }
                Button("Note") { add(.note) }
            }
        }
    }
    private func add(_ presentation: ItemPresentation) {
        let next = ((allLists.flatMap(\.allCards) + list.cards).map(\.id).max() ?? -1) + 1
        list.cards.append(KanbanCard(id: next, word: presentation == .note ? "New note" : "New card", listTitle: list.title,
            checklists: [], descriptionOverride: "", subtitleOverride: "", presentation: presentation))
    }
}

private struct PlanningTemplateCardEditor: View {
    @Binding var card: KanbanCard
    let anchor: Date
    var body: some View {
        Form {
            Section("Item") {
                TextField("Title", text: $card.word, axis: .vertical)
                ContentCreationKindPicker(presentation: $card.presentation)
                RichTextEditor(placeholder: "Details", text: Binding(get: { card.descriptionOverride ?? "" }, set: { card.descriptionOverride = $0 }))
            }
            Section("Relative dates") {
                Toggle("Start", isOn: Binding(get: { card.startDate != nil }, set: { card.startDate = $0 ? anchor : nil }))
                if card.startDate != nil {
                    Picker("Start format", selection: $card.startDateKind) {
                        ForEach(CardDateKind.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Source start", selection: Binding(get: { card.startDate ?? anchor }, set: { card.startDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                }
                Toggle("Due", isOn: Binding(get: { card.dueDate != nil }, set: { card.dueDate = $0 ? anchor : nil }))
                if card.dueDate != nil {
                    Picker("Due format", selection: $card.dueDateKind) {
                        ForEach(CardDateKind.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Source due", selection: Binding(get: { card.dueDate ?? anchor }, set: { card.dueDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                }
                Text("These dates are relative to the template's source day or week. They shift when applied.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach($card.checklists) { $checklist in
                PlanningTemplateChecklistEditor(checklist: $checklist)
            }
            Section {
                Button("Add checklist", systemImage: "checklist") { card.checklists.append(KanbanChecklist(title: "Checklist", items: [])) }
            }
        }.navigationTitle("Template item").navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlanningTemplateChecklistEditor: View {
    @Binding var checklist: KanbanChecklist
    private var items: Binding<[KanbanChecklistItem]> {
        Binding(get: { checklist.items }, set: { values in
            checklist = KanbanChecklist(id: checklist.id, title: checklist.title, items: values, completedItemIndices: [])
        })
    }
    var body: some View {
        Section {
            TextField("Checklist name", text: Binding(get: { checklist.title }, set: { title in
                checklist = KanbanChecklist(id: checklist.id, title: title, items: checklist.items, completedItemIndices: [])
            }))
            ForEach(items) { $item in TextField("Action", text: $item.title) }
                .onDelete { offsets in
                    var values = items.wrappedValue; values.remove(atOffsets: offsets); items.wrappedValue = values
                }
            Button("Add action", systemImage: "plus") {
                items.wrappedValue = items.wrappedValue + [KanbanChecklistItem(title: "")]
            }
        }
    }
}

struct PlanningTemplateApplyView: View {
    let template: PlanningRoutineTemplate
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var mode: PlanningTemplateApplication.Mode = .add
    @State private var baseline: DatedPlanningWeek?
    @State private var preview: DatedPlanningWeek?
    @State private var message: String?
    @State private var confirmsReplace = false
    private func prepare() {
        guard let access else { preview = nil; return }
        baseline = access.document.week(for: date)
        let target = baseline ?? DatedPlanningWeek.make(for: date, calendar: access.document.calendar)
        do { preview = try PlanningTemplateApplication.apply(template, to: target, date: date, calendar: access.document.calendar, mode: mode) }
        catch { preview = nil; message = "This template couldn't be prepared. Your plans have not changed." }
    }
    private func apply() {
        guard let access, let preview else { return }
        let persisted: PlanningCalendarDocument?
        do { persisted = try PlanningCalendarStore.load() }
        catch { message = "Your saved calendar couldn't be read. Please retry after reopening the app."; return }
        guard access.document.week(for: date) == baseline, persisted?.week(for: date) == baseline else {
            message = "This week changed while you were previewing it. Refresh the preview before applying."; return
        }
        if access.saveWeek(preview) { dismiss() }
        else { message = "The template couldn't be applied. Your preview is still open; refresh and retry." }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(template.name).font(.headline)
                    DatePicker(template.kind == .week ? "Destination week" : "Destination day", selection: $date, displayedComponents: .date)
                    Picker("Apply as", selection: $mode) {
                        ForEach(PlanningTemplateApplication.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Button("Refresh preview", systemImage: "arrow.clockwise", action: prepare)
                } footer: {
                    Text(mode == .add ? "Adds independent, unchecked copies. Existing items are kept." : "Replaces active items in the selected day or dated week lists. Archives and undated lists are retained.")
                }
                if let preview, let access {
                    ForEach(preview.collection.lists.filter { list in
                        template.kind == .week || preview.dayListIDs[PlanningDate.key(date, calendar: access.document.calendar)] == list.id
                    }) { list in
                        Section(list.title) {
                            if list.cards.isEmpty { Text("No items").foregroundStyle(.secondary) }
                            ForEach(list.cards) { card in
                                Label(card.word, systemImage: card.isSectionDivider ? "minus" : (card.presentation == .note ? "note.text" : "square"))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Preview template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { if mode == .replace && baseline?.hasContent == true { confirmsReplace = true } else { apply() } }
                        .disabled(preview == nil)
                }
            }
            .task { prepare() }
            .onChange(of: date) { _, _ in prepare() }
            .onChange(of: mode) { _, _ in prepare() }
            .confirmationDialog("Replace the selected plan?", isPresented: $confirmsReplace, titleVisibility: .visible) {
                Button("Replace with " + template.name, role: .destructive, action: apply)
                Button("Cancel", role: .cancel) {}
            } message: { Text("Active items in this target will be replaced by the preview. Other days, archives and undated lists are kept.") }
            .alert("Apply template", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }.presentationDetents([.large])
    }
}
