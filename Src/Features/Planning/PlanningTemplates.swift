import Foundation

/// Reusable local plans are separate snapshots, never live views of a scheduled day or week.
struct PlanningRoutineTemplate: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case day = "Day", week = "Week" }
    var id = UUID()
    var name: String
    var kind: Kind
    var anchorKey: String
    var timeZoneID: String
    var firstWeekday: Int
    var collection: PersonalCollection
    /// Calendar weekday -> source list identity; Day templates contain one source list.
    var weekdays: [Int: Int]
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        value.firstWeekday = firstWeekday
        return value
    }
    var itemCount: Int { collection.lists.flatMap(\.cards).filter { !$0.isSectionDivider }.count }
    static func capture(name: String, week: DatedPlanningWeek, day: Date? = nil, calendar: Calendar) throws -> Self {
        var collection = week.collection
        collection.savedCardIDs = []
        let sourceLists = week.collection.lists.filter { !$0.isArchived }
        var weekdays: [Int: Int] = [:]
        if let day {
            guard let id = week.dayListIDs[PlanningDate.key(day, calendar: calendar)],
                  let list = sourceLists.first(where: { $0.id == id }) else { throw CocoaError(.validationMissingMandatoryProperty) }
            collection.lists = [list]
            weekdays[calendar.component(.weekday, from: day)] = id
        } else {
            collection.lists = sourceLists
            for (key, id) in week.dayListIDs {
                if let date = PlanningDate.date(key, calendar: calendar), sourceLists.contains(where: { $0.id == id }) {
                    weekdays[calendar.component(.weekday, from: date)] = id
                }
            }
        }
        func reusableChecklist(_ source: KanbanChecklist) -> KanbanChecklist {
            let items = source.items.map { item -> KanbanChecklistItem in
                var content = item.content
                if case .actionDetail(let detail) = content {
                    content = .actionDetail(KanbanChecklistActionDetail(id: detail.id, description: detail.description,
                        checklists: detail.checklists.map(reusableChecklist)))
                }
                var result = KanbanChecklistItem(id: item.id, title: item.title, content: content)
                result.linkedCollectionID = item.linkedCollectionID
                return result
            }
            return KanbanChecklist(id: source.id, title: source.title, items: items, completedItemIndices: [])
        }
        for index in collection.lists.indices {
            collection.lists[index].archivedCards = []
            collection.lists[index].subtitleOverride = collection.lists[index].subtitle
            collection.lists[index].cards = collection.lists[index].cards.map { card in
                var copy = card; copy.comments = []; copy.dismissedActivityIDs = []; copy.isTitleChecked = false
                copy.checklists = card.checklists.map(reusableChecklist)
                copy.descriptionOverride = card.presentation == .note ? (card.descriptionOverride ?? "") : card.funParagraph
                copy.subtitleOverride = card.subtitle
                return copy
            }
        }
        return Self(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: day == nil ? .week : .day,
            anchorKey: day.map { PlanningDate.key($0, calendar: calendar) } ?? week.startKey,
            timeZoneID: calendar.timeZone.identifier, firstWeekday: calendar.firstWeekday, collection: collection, weekdays: weekdays)
    }
}

struct PlanningRoutineLibrary: Codable, Equatable {
    var version = 1
    var templates: [PlanningRoutineTemplate]
    var defaultWeekID: UUID?
    /// Optional for older v1 libraries; records the one-time addition/default selection of Jmr.
    var bundledRoutineRevision: Int? = nil
    static let jmrID = UUID(uuidString: "B28FA7CD-1928-44CA-99E0-CDA2EE840003")!
    static let jmr: PlanningRoutineTemplate = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        let anchor = PlanningDate.date("2026-10-12", calendar: calendar)!
        var week = DatedPlanningWeek.make(for: anchor, calendar: calendar)
        typealias Slot = (title: String, startHour: Int, startMinute: Int, stopHour: Int, stopMinute: Int)
        let weekdays: [Slot] = [
            ("Wake", 4, 0, 4, 30),
            ("Morning Starbucks Pow-wow", 5, 0, 6, 30),
            ("Work", 7, 0, 17, 0),
            ("Gym", 17, 0, 18, 0)]
        let saturday: [Slot] = [
            ("Wake", 5, 0, 5, 30),
            ("Morning Starbucks Pow-wow", 6, 0, 7, 30),
            ("Gym", 9, 0, 11, 0),
            ("Car Wash", 12, 0, 12, 30)]
        let sunday: [Slot] = [
            ("Wake", 4, 0, 4, 30),
            ("Morning Starbucks Pow-wow", 5, 0, 6, 30),
            ("Gym", 7, 0, 8, 30),
            ("Church", 9, 0, 12, 30)]
        var nextID = 0
        for day in PlanningDate.days(in: week.startKey, calendar: calendar) {
            let weekday = calendar.component(.weekday, from: day)
            let slots = weekday == 7 ? saturday : (weekday == 1 ? sunday : weekdays)
            let listID = week.dayListIDs[PlanningDate.key(day, calendar: calendar)]!
            let index = week.collection.lists.firstIndex { $0.id == listID }!
            week.collection.lists[index].subtitleOverride = ""
            week.collection.lists[index].cards = slots.map { slot in
                defer { nextID += 1 }
                return KanbanCard(id: nextID, word: slot.title, listTitle: week.collection.lists[index].title,
                    startDate: calendar.date(bySettingHour: slot.startHour, minute: slot.startMinute, second: 0, of: day),
                    dueDate: calendar.date(bySettingHour: slot.stopHour, minute: slot.stopMinute, second: 0, of: day),
                    checklists: [], descriptionOverride: slot.title == "Gym" ? "Choose what fits today: gym, meditation, walking, or massage." : "",
                    subtitleOverride: "", showsDueDateInList: true, startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
            }
        }
        var template = try! PlanningRoutineTemplate.capture(name: "Jmr", week: week, calendar: calendar)
        template.id = jmrID
        return template
    }()
    static let seeded: Self = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let anchor = PlanningDate.date("2026-10-12", calendar: calendar)!
        let example = DatedPlanningWeek.make(for: anchor, lists: SampleData.lists, calendar: calendar)
        var work = try! PlanningRoutineTemplate.capture(name: "Work Week", week: example, calendar: calendar)
        work.id = UUID(uuidString: "B28FA7CD-1928-44CA-99E0-CDA2EE840001")!
        var vacation = try! PlanningRoutineTemplate.capture(name: "Vacation Day", week: example, day: anchor, calendar: calendar)
        vacation.id = UUID(uuidString: "B28FA7CD-1928-44CA-99E0-CDA2EE840002")!
        var list = KanbanList(id: 0, title: "Vacation", cards: [
            KanbanCard(id: 0, word: "Enjoy a slower start", listTitle: "Vacation", checklists: []),
            KanbanCard(id: 1, word: "Explore something new", listTitle: "Vacation", checklists: []),
            KanbanCard(id: 2, word: "Make room to rest", listTitle: "Vacation", checklists: [])])
        list.subtitleOverride = "Leave room for the unexpected"
        vacation.collection.lists = [list]; vacation.weekdays = [2: 0]
        return Self(templates: [work, vacation, jmr], defaultWeekID: jmrID, bundledRoutineRevision: 1)
    }()
}

enum PlanningRoutineStore {
    static let key = "Plenact.PlanningTemplates.v1"
    static func validate(_ value: PlanningRoutineLibrary) throws {
        guard value.version == 1, (0...1).contains(value.bundledRoutineRevision ?? 0),
              Set(value.templates.map(\.id)).count == value.templates.count,
              value.defaultWeekID == nil || value.templates.contains(where: { $0.id == value.defaultWeekID && $0.kind == .week }) else { throw CocoaError(.coderReadCorrupt) }
        for template in value.templates {
            let lists = template.collection.lists
            guard !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  TimeZone(identifier: template.timeZoneID) != nil, (1...7).contains(template.firstWeekday),
                  PlanningDate.date(template.anchorKey, calendar: template.calendar) != nil,
                  Set(lists.map(\.id)).count == lists.count,
                  Set(lists.flatMap(\.allCards).map(\.id)).count == lists.flatMap(\.allCards).count,
                  !lists.isEmpty, !template.weekdays.isEmpty,
                  template.kind != .day || (lists.count == 1 && template.weekdays.count == 1),
                  lists.flatMap(\.cards).allSatisfy({ $0.id >= 0 && !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  template.weekdays.keys.allSatisfy({ (1...7).contains($0) }) else { throw CocoaError(.coderReadCorrupt) }
            guard template.weekdays.values.allSatisfy({ id in lists.contains { $0.id == id } }) else { throw CocoaError(.coderReadCorrupt) }
        }
    }
    static func load(from defaults: UserDefaults = .standard) throws -> PlanningRoutineLibrary {
        guard let data = defaults.data(forKey: key) else { return .seeded }
        var result = try JSONDecoder().decode(PlanningRoutineLibrary.self, from: data)
        try validate(result)
        if (result.bundledRoutineRevision ?? 0) == 0 {
            // Upgrade in memory only. Explicit template saves persist the marker; scheduled weeks are untouched.
            if !result.templates.contains(where: { $0.id == PlanningRoutineLibrary.jmrID }) {
                result.templates.append(PlanningRoutineLibrary.jmr)
            }
            result.defaultWeekID = PlanningRoutineLibrary.jmrID
            result.bundledRoutineRevision = 1
            try validate(result)
        }
        return result
    }
    static func save(_ value: PlanningRoutineLibrary, baseline: PlanningRoutineLibrary, to defaults: UserDefaults = .standard) throws {
        guard try load(from: defaults) == baseline else { throw CocoaError(.fileWriteFileExists) }
        try validate(value)
        let data = try JSONEncoder().encode(value)
        let previous = defaults.data(forKey: key)
        defaults.set(data, forKey: key)
        guard defaults.synchronize(), defaults.data(forKey: key) == data else {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
            throw CocoaError(.fileWriteUnknown)
        }
    }
    static func retainedFiles(from defaults: UserDefaults = .standard) throws -> Set<String> {
        Set(try load(from: defaults).templates.flatMap { $0.collection.lists }.flatMap(\.allCards)
            .flatMap { $0.attachments ?? [] }.flatMap(\.storedFileNames))
    }
    static func newWeek(for date: Date, calendar: Calendar, defaults: UserDefaults = .standard) throws -> DatedPlanningWeek {
        let library = try load(from: defaults)
        let blank = DatedPlanningWeek.make(for: date, calendar: calendar)
        guard let template = library.templates.first(where: { $0.id == library.defaultWeekID }) else { return blank }
        return try PlanningTemplateApplication.apply(template, to: blank, date: date, calendar: calendar, mode: .add)
    }
}

enum PlanningTemplateApplication {
    enum Mode: String, CaseIterable { case add = "Add to existing", replace = "Replace" }
    static func apply(_ template: PlanningRoutineTemplate, to original: DatedPlanningWeek, date: Date,
                      calendar: Calendar, mode: Mode, now: Date = .now) throws -> DatedPlanningWeek {
        try PlanningRoutineStore.validate(PlanningRoutineLibrary(templates: [template], defaultWeekID: nil))
        guard PlanningDate.weekKey(date, calendar: calendar) == original.startKey else { throw CocoaError(.validationMissingMandatoryProperty) }
        var result = original
        let targetDays = PlanningDate.days(in: original.startKey, calendar: calendar)
        let anchor = PlanningDate.date(template.anchorKey, calendar: template.calendar)!
        let sourceStart = template.calendar.startOfDay(for: anchor)
        var nextCard = (original.collection.lists.flatMap(\.allCards).map(\.id).max() ?? -1) + 1
        let cards = template.collection.lists.flatMap(\.cards)
        var mapping: [Int: Int] = [:]
        for card in cards { mapping[card.id] = nextCard; nextCard += 1 }
        func shifted(_ value: Date?, kind: CardDateKind) -> Date? {
            guard let value else { return nil }
            if kind == .time { return value }
            let offset = template.calendar.dateComponents([.day], from: sourceStart, to: template.calendar.startOfDay(for: value)).day ?? 0
            let target: Date
            if template.kind == .day {
                target = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
            } else {
                let weekday = template.calendar.component(.weekday, from: value)
                let sameWeekday = targetDays.first { calendar.component(.weekday, from: $0) == weekday }!
                target = calendar.date(byAdding: .day, value: Int(floor(Double(offset) / 7)) * 7, to: sameWeekday)!
            }
            if kind == .date { return calendar.startOfDay(for: target) }
            let components = template.calendar.dateComponents([.hour, .minute, .second], from: value)
            return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: components.second ?? 0, of: target)
        }
        func freshChecklist(_ source: KanbanChecklist) -> KanbanChecklist {
            let items = source.items.map { item -> KanbanChecklistItem in
                var content = item.content
                switch content {
                case .linkedCard(let id):
                    let local = item.linkedCollectionID == nil || item.linkedCollectionID == template.collection.id
                    content = local ? (mapping[id].map { .linkedCard(cardID: $0) } ?? .standard) : .standard
                case .actionDetail(let detail):
                    content = .actionDetail(KanbanChecklistActionDetail(description: detail.description, checklists: detail.checklists.map(freshChecklist)))
                default: break
                }
                return KanbanChecklistItem(title: item.title, content: content)
            }
            return KanbanChecklist(title: source.title, items: items, completedItemIndices: [])
        }
        func fresh(_ card: KanbanCard, title: String) -> KanbanCard {
            var cover: UUID?
            let attachments = card.attachments?.map { source -> KanbanAttachment in
                var copy = KanbanAttachment(fileName: source.fileName, url: source.url, mediaKind: source.mediaKind,
                    addedAt: now, exampleImage: source.exampleImage, caption: source.caption)
                copy.drawingFileName = source.drawingFileName
                if source.id == card.coverAttachmentID { cover = copy.id }
                return copy
            }
            return KanbanCard(id: mapping[card.id]!, word: card.word, listTitle: title, isDivider: card.isDivider,
                startDate: shifted(card.startDate, kind: card.startDateKind), dueDate: shifted(card.dueDate, kind: card.dueDateKind),
                checklists: card.checklists.map(freshChecklist), members: card.members, labelIDs: card.labelIDs,
                attachments: attachments, coverAttachmentID: cover, descriptionOverride: card.presentation == .note ? (card.descriptionOverride ?? "") : card.funParagraph,
                subtitleOverride: card.subtitle, presentation: card.presentation, createdAt: now, appearance: card.appearance,
                listDisplayFormat: card.listDisplayFormat, sectionLayout: card.sectionLayout, showsDueDateInList: card.showsDueDateInList,
                startDateKind: card.startDateKind, dueDateKind: card.dueDateKind)
        }
        if template.kind == .week && mode == .replace {
            for index in result.collection.lists.indices where result.dayListIDs.values.contains(result.collection.lists[index].id) && !result.collection.lists[index].isArchived {
                result.collection.savedCardIDs.subtract(result.collection.lists[index].cards.map(\.id))
                result.collection.lists[index].cards = []
            }
        }
        for source in template.collection.lists {
            let weekday = template.weekdays.first { $0.value == source.id }?.key
            let destinationDate = template.kind == .day ? date : targetDays.first { calendar.component(.weekday, from: $0) == weekday }
            let index: Int
            if let destinationDate {
                let key = PlanningDate.key(destinationDate, calendar: calendar)
                guard let id = result.dayListIDs[key], let found = result.collection.lists.firstIndex(where: { $0.id == id && !$0.isArchived }) else { throw CocoaError(.validationMissingMandatoryProperty) }
                index = found
            } else {
                let id = (result.collection.lists.map(\.id).max() ?? -1) + 1
                result.collection.lists.append(KanbanList(id: id, title: source.title, cards: [], newItemPresentation: source.newItemPresentation))
                index = result.collection.lists.count - 1
            }
            if mode == .replace && template.kind == .day {
                result.collection.savedCardIDs.subtract(result.collection.lists[index].cards.map(\.id))
                result.collection.lists[index].cards = []
            }
            if result.collection.lists[index].cards.isEmpty {
                result.collection.lists[index].appearance = source.appearance
                result.collection.lists[index].subtitleOverride = source.subtitleOverride
                result.collection.lists[index].newItemPresentation = source.newItemPresentation
            }
            result.collection.lists[index].cards += source.cards.map { fresh($0, title: result.collection.lists[index].title) }
        }
        if !original.hasContent { result.collection.boardAppearance = template.collection.boardAppearance }
        result.explicitlySaved = true
        return result
    }
}
