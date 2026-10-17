import SwiftUI
import CryptoKit

/// Stable local date keys avoid timestamp shifts when a user changes time zone.
enum PlanningDate {
    static func listTitle(_ title: String, on date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let suffix = year == calendar.component(.year, from: now)
            ? "\(month)/\(day)" : "\(month)/\(day)/\(String(format: "%02d", year % 100))"
        return "\(title) (\(suffix))"
    }
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
    static func weekKey(_ date: Date, calendar: Calendar = .current) -> String {
        key(calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date, calendar: calendar)
    }
    static func days(in weekKey: String, calendar: Calendar = .current) -> [Date] {
        guard let start = date(weekKey, calendar: calendar) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    static func weekdayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][calendar.component(.weekday, from: date) - 1]
    }
}

struct DatedPlanningWeek: Identifiable, Hashable, Codable {
    var startKey: String
    var collection: PersonalCollection
    var dayListIDs: [String: Int]
    var explicitlySaved: Bool = false
    var id: UUID { collection.id }
    var hasContent: Bool { collection.lists.contains { !$0.allCards.isEmpty } }
    var rangeTitle: String {
        let days = PlanningDate.days(in: startKey)
        guard let first = days.first, let last = days.last else { return startKey }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
    var compactRangeTitle: String {
        let days = PlanningDate.days(in: startKey)
        guard let first = days.first, let last = days.last else { return startKey }
        let calendar = Calendar.current
        let firstYear = calendar.component(.year, from: first)
        let lastYear = calendar.component(.year, from: last)
        let firstLabel = first.formatted(.dateTime.month(.abbreviated).day())
        let lastLabel = last.formatted(.dateTime.month(.abbreviated).day())
        let yearSuffix = String(format: "%02d", lastYear % 100)
        if firstYear != lastYear {
            return "\(firstLabel) '\(String(format: "%02d", firstYear % 100))-\(lastLabel) '\(yearSuffix)"
        }
        if calendar.component(.month, from: first) == calendar.component(.month, from: last) {
            return "\(firstLabel)-\(calendar.component(.day, from: last)) '\(yearSuffix)"
        }
        return "\(firstLabel)-\(lastLabel) '\(yearSuffix)"
    }
    func list(on date: Date) -> KanbanList? {
        guard let id = dayListIDs[PlanningDate.key(date)] else { return nil }
        return collection.lists.first { $0.id == id && !$0.isArchived }
    }
    mutating func prepareDay(_ date: Date) -> Int {
        if let existing = list(on: date) { return existing.id }
        let id = (collection.lists.map(\.id).max() ?? -1) + 1
        collection.lists.append(KanbanList(id: id, title: PlanningDate.weekdayTitle(date), cards: []))
        dayListIDs[PlanningDate.key(date)] = id
        return id
    }
    static func make(for date: Date, lists: [KanbanList]? = nil, saved: Set<Int> = [],
                     calendar: Calendar = .current) -> Self {
        let start = PlanningDate.weekKey(date, calendar: calendar)
        var collection = PersonalCollection(title: "Week of \(start)", kind: .board)
        collection.lists = lists ?? []
        collection.savedCardIDs = saved
        var dayIDs: [String: Int] = [:]
        for day in PlanningDate.days(in: start, calendar: calendar) {
            let title = PlanningDate.weekdayTitle(day, calendar: calendar)
            if let list = collection.lists.first(where: { !$0.isArchived && $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                dayIDs[PlanningDate.key(day, calendar: calendar)] = list.id
            } else {
                let id = (collection.lists.map(\.id).max() ?? -1) + 1
                collection.lists.append(KanbanList(id: id, title: title, cards: []))
                dayIDs[PlanningDate.key(day, calendar: calendar)] = id
            }
        }
        return Self(startKey: start, collection: collection, dayListIDs: dayIDs)
    }
}

/// Calendar weeks remain separate from the Library collection directory.
struct PlanningCalendarDocument: Hashable, Codable {
    var version = 1
    var currentWeekKey: String
    var firstWeekday: Int = Calendar.current.firstWeekday
    var weeks: [DatedPlanningWeek]
    var checklistLinkWeeks: [UUID: UUID]? = nil
    var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = firstWeekday
        return value
    }
    func week(for date: Date, calendar: Calendar? = nil) -> DatedPlanningWeek? {
        weeks.first { $0.startKey == PlanningDate.weekKey(date, calendar: calendar ?? self.calendar) }
    }
    mutating func upsert(_ week: DatedPlanningWeek) {
        if let index = weeks.firstIndex(where: { $0.startKey == week.startKey }) { weeks[index] = week }
        else { weeks.append(week) }
        weeks.sort { $0.startKey < $1.startKey }
    }
    mutating func rollForward(to date: Date, currentLists: [KanbanList], saved: Set<Int>,
                              calendar suppliedCalendar: Calendar? = nil) -> DatedPlanningWeek {
        let calendar = suppliedCalendar ?? self.calendar
        if var previous = weeks.first(where: { $0.startKey == currentWeekKey }) {
            previous.collection.lists = currentLists
            previous.collection.savedCardIDs = saved
            upsert(previous)
        }
        let key = PlanningDate.weekKey(date, calendar: calendar)
        let next = weeks.first { $0.startKey == key } ?? DatedPlanningWeek.make(for: date, calendar: calendar)
        upsert(next)
        currentWeekKey = key
        return next
    }
}


extension PlanningCalendarDocument {
    /// Legacy Monday–Sunday boards were initially dated using the device's Sunday-start calendar.
    /// Repartition by existing date associations; never relabel the old Sunday's content.
    @discardableResult
    mutating func repairLegacyMondayFirstLayout(now: Date = .now) throws -> Bool {
        guard firstWeekday == 1,
              let current = weeks.first(where: { $0.startKey == currentWeekKey }) else { return false }
        let dated = current.collection.lists.filter { list in
            !list.isArchived && current.dayListIDs.values.contains(list.id)
        }
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        guard dated.map(\.title) == names,
              let monday = current.dayListIDs.first(where: { $0.value == dated[0].id })?.key,
              let sunday = current.dayListIDs.first(where: { $0.value == dated[6].id })?.key,
              sunday < monday else { return false }
        try changeFirstWeekday(to: 2, now: now)
        return true
    }

    /// Repartition dated lists without changing their dates or dropping archived content.
    /// Undated lists and board appearance stay with the middle of their original week.
    mutating func changeFirstWeekday(to weekday: Int, now: Date = .now) throws {
        guard weekday == 1 || weekday == 2 else { throw CocoaError(.validationMissingMandatoryProperty) }
        guard weekday != firstWeekday else { return }
        let oldCalendar = calendar
        var newCalendar = calendar
        newCalendar.firstWeekday = weekday
        let sources = weeks.sorted {
            if ($0.startKey == currentWeekKey) != ($1.startKey == currentWeekKey) { return $0.startKey == currentWeekKey }
            return $0.startKey < $1.startKey
        }
        var rebuilt: [String: DatedPlanningWeek] = [:]
        var cardIDs: [UUID: [Int: Int]] = [:]
        var usedCardIDs = Set<Int>()
        var nextCardID = (weeks.flatMap { $0.collection.lists.flatMap(\.allCards) }.map(\.id).max() ?? -1) + 1
        // Globally distinct IDs prevent a link from resolving to an unrelated card after a split.
        for source in sources {
            var mapping: [Int: Int] = [:]
            for card in source.collection.lists.flatMap(\.allCards) {
                let id: Int
                if usedCardIDs.insert(card.id).inserted { id = card.id }
                else { id = nextCardID; nextCardID += 1; usedCardIDs.insert(id) }
                mapping[card.id] = id
            }
            cardIDs[source.id] = mapping
            guard let middle = PlanningDate.days(in: source.startKey, calendar: oldCalendar).dropFirst(3).first else {
                throw CocoaError(.coderReadCorrupt)
            }
            let key = PlanningDate.weekKey(middle, calendar: newCalendar)
            var retained = source
            retained.startKey = key
            retained.collection.title = "Week of \(key)"
            retained.collection.lists = []
            retained.collection.savedCardIDs = []
            retained.dayListIDs = [:]
            rebuilt[key] = retained
        }
        for source in sources {
            let middle = PlanningDate.days(in: source.startKey, calendar: oldCalendar)[3]
            let ownerKey = PlanningDate.weekKey(middle, calendar: newCalendar)
            for list in source.collection.lists {
                let dateKey = source.dayListIDs.first { $0.value == list.id }?.key
                let date = dateKey.flatMap { PlanningDate.date($0, calendar: oldCalendar) }
                let key = date.map { PlanningDate.weekKey($0, calendar: newCalendar) } ?? ownerKey
                var target = rebuilt[key] ?? DatedPlanningWeek.make(for: date ?? middle, calendar: newCalendar)
                // A new boundary week starts empty; weekday panels are filled after migration.
                if rebuilt[key] == nil { target.collection.lists = []; target.dayListIDs = [:] }
                let occupied = Set(target.collection.lists.map(\.id))
                let listID = occupied.contains(list.id) ? (occupied.max() ?? -1) + 1 : list.id
                let mapping = cardIDs[source.id]!
                func relocated(_ card: KanbanCard) -> KanbanCard {
                    var result = card.replacingLocation(id: mapping[card.id]!, listTitle: list.title)
                    result.checklists = card.checklists.map { checklist in
                        let items = checklist.items.map { item in
                            var item = item
                            let owner = checklistLinkWeeks?[item.id] ?? item.linkedCollectionID ?? source.id
                            if let retained = item.retainedCardID, let replacement = cardIDs[owner]?[retained] {
                                item.retainedCardID = replacement
                            }
                            if case .linkedCard(let id) = item.content {
                                if let replacement = cardIDs[owner]?[id] {
                                    item.content = .linkedCard(cardID: replacement)
                                }
                            }
                            return item
                        }
                        return KanbanChecklist(id: checklist.id, title: checklist.title, items: items,
                                               completedItemIndices: checklist.completedItemIndices)
                    }
                    return result
                }
                var moved = KanbanList(id: listID, title: list.title, cards: list.cards.map(relocated),
                    archivedCards: list.archivedCards.map(relocated), newItemPresentation: list.newItemPresentation)
                moved.subtitleOverride = list.subtitleOverride
                moved.appearance = list.appearance
                moved.isArchived = list.isArchived
                target.collection.lists.append(moved)
                for card in list.allCards where source.collection.savedCardIDs.contains(card.id) {
                    target.collection.savedCardIDs.insert(mapping[card.id]!)
                }
                if let dateKey { target.dayListIDs[dateKey] = listID }
                rebuilt[key] = target
            }
        }
        let currentKey = PlanningDate.weekKey(now, calendar: newCalendar)
        if rebuilt[currentKey] == nil { rebuilt[currentKey] = DatedPlanningWeek.make(for: now, calendar: newCalendar) }
        for key in Array(rebuilt.keys) {
            var week = rebuilt[key]!
            for date in PlanningDate.days(in: key, calendar: newCalendar) where week.dayListIDs[PlanningDate.key(date)] == nil {
                _ = week.prepareDay(date)
            }
            let datesByID = Dictionary(uniqueKeysWithValues: week.dayListIDs.map { ($0.value, $0.key) })
            week.collection.lists = week.collection.lists.enumerated().sorted { lhs, rhs in
                switch (datesByID[lhs.element.id], datesByID[rhs.element.id]) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.offset < rhs.offset
                }
            }.map(\.element)
            rebuilt[key] = week
        }
        // Keep checklist links navigable when their two dated lists now belong to different weeks.
        let cardOwners = Dictionary(uniqueKeysWithValues: rebuilt.values.flatMap { week in
            week.collection.lists.flatMap(\.allCards).map { ($0.id, week.id) }
        })
        var linkWeeks: [UUID: UUID] = [:]
        for week in rebuilt.values {
            for card in week.collection.lists.flatMap(\.allCards) {
                for item in card.checklists.flatMap(\.items) {
                    if case .linkedCard(let cardID) = item.content,
                       let owner = cardOwners[cardID], owner != week.id {
                        linkWeeks[item.id] = owner
                    }
                }
            }
        }
        let sourceWeekIDs = Set(sources.map(\.id))
        for key in Array(rebuilt.keys) {
            var week = rebuilt[key]!
            func preservingOwners(_ card: KanbanCard) -> KanbanCard {
                var card = card
                card.checklists = card.checklists.map { checklist in
                    let items = checklist.items.map { original in
                        var item = original
                        if let id = item.retainedCardID,
                           item.linkedCollectionID == nil || sourceWeekIDs.contains(item.linkedCollectionID!),
                           let owner = cardOwners[id] {
                            item.linkedCollectionID = owner
                        }
                        return item
                    }
                    return KanbanChecklist(id: checklist.id, title: checklist.title, items: items, completedItemIndices: checklist.completedItemIndices)
                }
                return card
            }
            for index in week.collection.lists.indices {
                week.collection.lists[index].cards = week.collection.lists[index].cards.map(preservingOwners)
                week.collection.lists[index].archivedCards = week.collection.lists[index].archivedCards.map(preservingOwners)
            }
            rebuilt[key] = week
        }
        checklistLinkWeeks = linkWeeks.isEmpty ? nil : linkWeeks
        firstWeekday = weekday
        currentWeekKey = currentKey
        weeks = rebuilt.values.sorted { $0.startKey < $1.startKey }
    }
}

enum PlanningCalendarStore {
    static let key = "Plenact.CalendarWeeks.v1"
    static func load(from defaults: UserDefaults = .standard) throws -> PlanningCalendarDocument? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let result = try JSONDecoder().decode(PlanningCalendarDocument.self, from: data)
        guard result.version == 1, (1...7).contains(result.firstWeekday), Set(result.weeks.map(\.startKey)).count == result.weeks.count,
              Set(result.weeks.map(\.id)).count == result.weeks.count,
              result.weeks.contains(where: { $0.startKey == result.currentWeekKey }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return result
    }
    static func save(_ document: PlanningCalendarDocument, to defaults: UserDefaults = .standard) throws {
        // Retained corrupt or unsupported data must not be silently overwritten.
        _ = try load(from: defaults)
        defaults.set(try JSONEncoder().encode(document), forKey: key)
    }
}

struct PlanningSearchResult: Identifiable, Hashable {
    let weekKey: String?
    let collectionID: UUID
    let collectionTitle: String
    let listID: Int
    let listTitle: String
    let card: KanbanCard
    var id: String { "\(collectionID):\(card.id)" }
}

struct PlanningCalendarAccess {
    var document: PlanningCalendarDocument
    var library: [PersonalCollection]
    var saveWeek: (DatedPlanningWeek) -> Bool
    var openCurrentWeek: () -> Void
    var openToday: () -> Void
    var openLibraryCard: (PersonalSavedCardTarget) -> Void
    var saveLibrary: (PersonalCollection) -> Bool
    var applyWeeklyReview: ((PlanningSearchResult, DailyReviewAction, WeeklyReviewRecord, WeeklyReviewRecord?) -> WeeklyReviewRecord?)? = nil
    var applyDailyReview: ((PlanningSearchResult, DailyReviewAction, DailyPlan, DailyPlan?) -> DailyPlan?)? = nil
    var moveForDailyPlan: ((PlanningSearchResult, WorkspaceListReference) -> PlanningSearchResult?)? = nil
    var setFirstWeekday: (Int) -> Bool = { _ in false }
    var openWeek: (DatedPlanningWeek) -> Void = { _ in }
    var moveList: ((Int, UUID, UUID?) -> Bool)? = nil
    var openWeekOnDay: ((DatedPlanningWeek, Date) -> Void)? = nil
    var allRetainedLists: [KanbanList] { document.weeks.flatMap { $0.collection.lists } + library.flatMap(\.lists) }
    var searchableItems: [PlanningSearchResult] {
        document.weeks.flatMap { week in
            week.collection.lists.filter { !$0.isArchived }.flatMap { list in
                list.cards.filter { !$0.isSectionDivider }.map {
                    PlanningSearchResult(weekKey: week.startKey, collectionID: week.id, collectionTitle: week.rangeTitle,
                                         listID: list.id, listTitle: list.title, card: $0)
                }
            }
        } + library.filter(\.isActive).flatMap { collection in
            collection.lists.filter { !$0.isArchived }.flatMap { list in
                list.cards.filter { !$0.isSectionDivider }.map {
                    PlanningSearchResult(weekKey: nil, collectionID: collection.id, collectionTitle: collection.title,
                                         listID: list.id, listTitle: list.title, card: $0)
                }
            }
        }
    }
}
private struct PlanningCalendarAccessKey: EnvironmentKey {
    static let defaultValue: PlanningCalendarAccess? = nil
}
private struct PlanningDisplayedWeekKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
extension EnvironmentValues {
    var planningDisplayedWeekKey: String? {
        get { self[PlanningDisplayedWeekKey.self] }
        set { self[PlanningDisplayedWeekKey.self] = newValue }
    }
    var planningCalendarAccess: PlanningCalendarAccess? {
        get { self[PlanningCalendarAccessKey.self] }
        set { self[PlanningCalendarAccessKey.self] = newValue }
    }
}

private struct PlanningWeekRoute: Identifiable {
    var week: DatedPlanningWeek
    var dayID: Int? = nil
    var cardID: Int? = nil
    var id: UUID { week.id }
}

struct PlanningCalendarView: View {
    var onLeaveForHome: () -> Void = {}
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var todayDateFontSize: CGFloat = 17
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var route: PlanningWeekRoute?
    @State private var showsSearch = false
    init(initialDate: Date = .now, onLeaveForHome: @escaping () -> Void = {}) {
        self.onLeaveForHome = onLeaveForHome
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: initialDate)?.start ?? initialDate)
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
    }
    private var displayCalendar: Calendar { access?.document.calendar ?? .current }
    private var rows: [[Date]] {
        let calendar = displayCalendar
        guard let first = calendar.dateInterval(of: .month, for: month)?.start,
              let start = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let leading = calendar.dateComponents([.day], from: start, to: first).day ?? 0
        let rowCount = (leading + count + 6) / 7
        return (0..<rowCount).map { row in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: row * 7 + $0, to: start) }
        }
    }
    private var symbols: [String] {
        let calendar = displayCalendar
        let values = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { values[(calendar.firstWeekday - 1 + $0) % 7] }
    }
    private func week(on date: Date) -> DatedPlanningWeek {
        access?.document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: displayCalendar)
    }
    private func items(on date: Date) -> [PlanningSearchResult] {
        guard let access else { return [] }
        let plannedWeek = week(on: date)
        let plannedID = plannedWeek.list(on: date)?.id
        return access.searchableItems.filter { item in
            let planned = item.weekKey == plannedWeek.startKey && item.listID == plannedID
            let scheduled = [item.card.startDateKind.includesDate ? item.card.startDate : nil, item.card.dueDateKind.includesDate ? item.card.dueDate : nil].compactMap { $0 }.contains {
                Calendar.current.isDate($0, inSameDayAs: date)
            }
            return planned || scheduled
        }
    }
    private func open(_ result: PlanningSearchResult) {
        if let key = result.weekKey, let savedWeek = access?.document.weeks.first(where: { $0.startKey == key }) {
            route = PlanningWeekRoute(week: savedWeek, dayID: result.listID, cardID: result.card.id)
        } else {
            access?.openLibraryCard(PersonalSavedCardTarget(collectionID: result.collectionID, listID: result.listID, cardID: result.card.id))
            dismiss()
            onLeaveForHome()
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    monthGrid.dynamicTypeSize(.large) // Seven columns stay legible; full dates are announced by VoiceOver.
                    daySummary
                }
                .padding(16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { calendarHeader }
            .modifier(PlanningSharedSearchPresentation(isPresented: $showsSearch, onLeaveForHome: { dismiss(); onLeaveForHome() }))
            .fullScreenCover(item: $route) { route in
                PlanningCalendarWeekView(week: route.week, initialDayID: route.dayID, initialCardID: route.cardID,
                    onLeaveForHome: { self.route = nil; dismiss(); onLeaveForHome() })
            }
        }
    }
    private var calendarHeader: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                WorkspaceHeaderIcon(systemName: "chevron.left")
            }
            .accessibilityLabel("Close Calendar")
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar")
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Plans across time")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { showsSearch = true } label: {
                WorkspaceHeaderIcon(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search Plenact")
            Button { access?.openCurrentWeek(); dismiss(); onLeaveForHome() } label: {
                WorkspaceHeaderIcon(systemName: "rectangle.split.3x1")
            }
            .accessibilityLabel("Open This Week")
            Button { access?.openToday(); dismiss(); onLeaveForHome() } label: {
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
         .background {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.18, blue: 0.25), Color(red: 0.22, green: 0.34, blue: 0.38)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 10) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month")
            }
            HStack(spacing: 2) {
                Color.clear.frame(width: 44, height: 24)
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(rows.indices, id: \.self) { index in
                let dates = rows[index]
                let rowWeek = dates.first.map { week(on: $0) }
                let isCurrent = rowWeek?.startKey == access?.document.currentWeekKey
                HStack(spacing: 2) {
                    if let rowWeek {
                        Button { route = PlanningWeekRoute(week: rowWeek) } label: {
                            Image(systemName: rowWeek.hasContent || isCurrent ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                                .transformEffect(CGAffineTransform(a: 1, b: 0,
                                    c: rowWeek.hasContent || isCurrent ? 0 : -0.22, d: 1, tx: 0, ty: 0))
                                .foregroundStyle(isCurrent ? Color.accentColor : (rowWeek.hasContent
                                    ? Color(red: 0.45, green: 0.72, blue: 0.95)
                                    : Color.secondary.opacity(0.4)))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Open \(isCurrent ? "this week" : rowWeek.rangeTitle)\(rowWeek.hasContent ? ", saved content" : ", empty week")")
                    }
                    ForEach(dates, id: \.self) { date in
                        dayButton(date)
                    }
                }
                .background(isCurrent ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 5) {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                Text("Items planned or scheduled · highlighted row is this week")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private func dayButton(_ date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let count = items(on: date).count
        return Button { selectedDate = date } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day()))
                    .font(displayCalendar.isDateInToday(date)
                          ? .system(size: todayDateFontSize, weight: .bold).italic()
                          : .subheadline)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Circle().fill(count > 0 ? (selected ? Color.white : Color.accentColor) : .clear).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
            .opacity(Calendar.current.isDate(date, equalTo: month, toGranularity: .month) ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(count) items")
    }
    private var daySummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.headline)
                Spacer()
                Button {
                    var target = week(on: selectedDate)
                    let listID = target.prepareDay(selectedDate)
                    route = PlanningWeekRoute(week: target, dayID: listID)
                } label: { Image(systemName: "arrow.up.right.square").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("Open this day's list")
            }
            let selectedItems = items(on: selectedDate)
            if selectedItems.isEmpty {
                Text("Nothing planned yet. Open this day to add your first item.").foregroundStyle(.secondary)
            }
            ForEach(selectedItems) { result in
                Button { open(result) } label: { PlanningCalendarResultRow(result: result) }
                    .buttonStyle(.plain)
                if result.id != selectedItems.last?.id { Divider() }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private func moveMonth(_ amount: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: amount, to: month) { month = next }
    }
}

private struct PlanningCalendarResultRow: View {
    let result: PlanningSearchResult
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.card.displayFormat == .card ? (result.card.isTitleChecked ? "checkmark.square.fill" : "square") : "doc.text")
                .foregroundStyle(result.card.isTitleChecked ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
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

struct PlanningCalendarWeekView: View {
    @State var week: DatedPlanningWeek
    let initialDayID: Int?
    let initialCardID: Int?
    let onLeaveForHome: () -> Void
    var isWeekTab = false
    var initialBoardListID: Int? = nil
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var targetListID: Int?
    @State private var targetCardID: Int?
    @State private var didOpenInitialTarget = false
    @State private var showsDay = false
    @State private var dayID: Int?
    @State private var isRevertingEdit = false
    @State private var labels = LabelLibraryStore.load()
    private var isStored: Bool { access?.document.weeks.contains { $0.startKey == week.startKey } == true }
    private var isCurrent: Bool { week.startKey == access?.document.currentWeekKey }
    var body: some View {
        ContentView(
            lists: $week.collection.lists.activeLists, archivedLists: $week.collection.lists.archivedLists,
            boardTargetListID: $targetListID, boardTargetCardID: $targetCardID,
            savedCardIDs: $week.collection.savedCardIDs,
            boardTitle: isWeekTab ? "Plenact" : (isCurrent ? "This Week" : "Week"), boardSubtitle: (isWeekTab ? "Week • " : "") + week.compactRangeTitle,
            allowsAddingLists: false, onClose: isWeekTab ? nil : { dismiss() },
            onCommitDeletion: { lists, saved in
                var next = week; next.collection.lists = lists; next.collection.savedCardIDs = saved
                guard access?.saveWeek(next) == true else { throw CocoaError(.fileWriteUnknown) }
                week = next
            },
            onListsChanged: { _ in },
            retainedAttachmentLists: { access?.allRetainedLists ?? [] },
            personalCollectionID: week.id,
            boardAppearance: $week.collection.boardAppearance
        )
        .safeAreaInset(edge: .bottom) {
            if !isWeekTab {
            HStack {
                if !isStored {
                    Button("Save empty week", systemImage: "square.and.arrow.down") {
                        var next = week; next.explicitlySaved = true
                        if access?.saveWeek(next) == true { week = next }
                    }
                } else { Text(week.rangeTitle).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("This week", systemImage: "arrow.uturn.backward") {
                    access?.openCurrentWeek(); dismiss(); onLeaveForHome()
                }
            }
            .padding(12)
            .background(.regularMaterial)
            }
        }
        .environment(\.planningDirectItemReturn, initialCardID == nil ? nil : { dismiss() })
        .environment(\.planningDisplayedWeekKey, week.startKey)
        .environment(\.cardMovementSource, week.id)
        .environment(\.planningHomeExit, { dismiss(); onLeaveForHome() })
        .task {
            guard !didOpenInitialTarget else { return }
            didOpenInitialTarget = true
            if let initialBoardListID { targetListID = initialBoardListID }
            if let initialDayID {
                if let initialCardID { targetListID = initialDayID; targetCardID = initialCardID }
                else { dayID = initialDayID; showsDay = true }
            }
        }
        .onChange(of: initialBoardListID) { _, id in
            if let id { targetListID = id; targetCardID = nil }
        }
        .onChange(of: week) { old, updated in
            guard old != updated else { return }
            // Merely opening a draft never writes; an actual edit saves the week.
            if isRevertingEdit { isRevertingEdit = false; return }
            if access?.saveWeek(updated) != true { isRevertingEdit = true; week = old }
        }
        .onChange(of: access?.document) { _, document in
            if let updated = document?.weeks.first(where: { $0.startKey == week.startKey }), updated != week { week = updated }
        }
        .fullScreenCover(isPresented: $showsDay) {
            if let dayID {
                TodayListDetailView(lists: $week.collection.lists.activeLists,
                    reservedLists: week.collection.lists.filter(\.isArchived), labelLibrary: $labels,
                    savedCardIDs: $week.collection.savedCardIDs, listID: dayID, currentUserName: "You",
                    onClose: {
                        showsDay = false
                        if initialDayID != nil && initialCardID == nil { dismiss() }
                    }, onOpenWeek: { showsDay = false; targetListID = dayID },
                    onPermanentDelete: { cardID in
                        var next = week
                        BoardContentDeletion.card(cardID, in: &next.collection.lists, savedCardIDs: &next.collection.savedCardIDs)
                        guard access?.saveWeek(next) == true else { return false }
                        week = next; return true
                    }, boardAppearance: week.collection.boardAppearance,
                    returnDestinationTitle: "Calendar", boardViewActionTitle: "Switch to this week's view",
                    representedDate: week.dayListIDs.first(where: { $0.value == dayID }).flatMap { PlanningDate.date($0.key) })
                    .environment(\.cardMovementSource, week.id)
            }
        }
    }
}


private struct PlanningDirectItemReturnKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var planningDirectItemReturn: (() -> Void)? {
        get { self[PlanningDirectItemReturnKey.self] }
        set { self[PlanningDirectItemReturnKey.self] = newValue }
    }
}

private struct PlanningHomeExitKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var planningHomeExit: (() -> Void)? {
        get { self[PlanningHomeExitKey.self] }
        set { self[PlanningHomeExitKey.self] = newValue }
    }
}

/// The existing Today index supplies all filters; provenance disambiguates board-local IDs.
enum PlanningSharedSearchIndex {
    static func results(query: String, scope: TodaySearchScope, access: PlanningCalendarAccess,
                        labels: LabelLibrary) -> [TodaySearchResult] {
        let sources: [(UUID, String?, String, [KanbanList])] = access.document.weeks.map {
            ($0.id, $0.startKey, $0.startKey == access.document.currentWeekKey ? "This week · \($0.rangeTitle)" : $0.rangeTitle, $0.collection.lists)
        } + access.library.filter(\.isActive).map { ($0.id, nil, "Plans · \($0.title)", $0.lists) }
        return sources.flatMap { ownerID, weekKey, title, lists in
            TodaySearchIndex.results(query: query, scope: scope, lists: lists.filter { !$0.isArchived }, library: labels).map { match in
                var result = match
                result.ownerID = ownerID; result.weekKey = weekKey; result.ownerTitle = title
                return result
            }
        }
    }
}

/// Existing snapshot-only contexts retain their lifecycle actions; shared results open the owner first.
struct SharedSearchLifecycleActions: ViewModifier {
    let enabled: Bool
    let title: String
    let kind: String
    let onArchive: () -> Void
    let onDelete: () -> Bool
    func body(content: Content) -> some View {
        if enabled { content.modifier(ContentLifecycleActions(title: title, kind: kind, onArchive: onArchive, onDelete: onDelete)) }
        else { content }
    }
}

private struct PlanningSearchRoute: Identifiable {
    let result: TodaySearchResult
    var id: String { result.id }
}

/// Every toolbar opens this exact Today search UI, including scopes and shared recent history.
struct PlanningSharedSearchPresentation: ViewModifier {
    @Binding var isPresented: Bool
    var onLeaveForHome: () -> Void = {}
    @Environment(\.planningCalendarAccess) private var access
    @State private var route: PlanningSearchRoute?
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                TodaySearchView(lists: [], onOpenBoardList: { _ in }, onOpenBoardCard: { _, _ in },
                    onArchiveCard: { _ in }, onDeleteCard: { _ in false }, onArchiveList: { _ in }, onDeleteList: { _ in false },
                    resultProvider: { query, scope, labels in
                        guard let access else { return [] }
                        return PlanningSharedSearchIndex.results(query: query, scope: scope, access: access, labels: labels)
                    }, onSelectResult: { result in route = PlanningSearchRoute(result: result) })
                    // Keep Search alive beneath its result, preserving query, scope, and scroll.
                    .fullScreenCover(item: $route) { route in
                        if let key = route.result.weekKey, let week = access?.document.weeks.first(where: { $0.startKey == key }) {
                            PlanningCalendarWeekView(week: week,
                                initialDayID: route.result.listID, initialCardID: route.result.cardID,
                                onLeaveForHome: { self.route = nil; isPresented = false; onLeaveForHome() })
                        } else if let collection = access?.library.first(where: { $0.id == route.result.ownerID }) {
                            PlanningSearchLibraryView(collection: collection, initialListID: route.result.listID, initialCardID: route.result.cardID,
                                onLeaveForHome: { self.route = nil; isPresented = false; onLeaveForHome() })
                        }
                    }
            }
    }
}

struct PlanningSearchLibraryView: View {
    @State var collection: PersonalCollection
    let initialListID: Int
    let initialCardID: Int?
    let onLeaveForHome: () -> Void
    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var targetListID: Int?
    @State private var targetCardID: Int?
    @State private var isRevertingEdit = false
    @State private var didOpenInitialTarget = false
    var body: some View {
        ContentView(lists: $collection.lists.activeLists, archivedLists: $collection.lists.archivedLists,
            boardTargetListID: $targetListID, boardTargetCardID: $targetCardID, savedCardIDs: $collection.savedCardIDs,
            boardTitle: collection.title, boardSubtitle: "Plans", allowsAddingLists: collection.kind == .board,
            fillsAvailableListWidth: collection.kind == .list, onClose: { dismiss() },
            onCommitDeletion: { lists, saved in
                var updated = collection; updated.lists = lists; updated.savedCardIDs = saved
                guard access?.saveLibrary(updated) == true else { throw CocoaError(.fileWriteUnknown) }
                collection = updated
            }, onListsChanged: { _ in }, retainedAttachmentLists: { access?.allRetainedLists ?? [] },
            personalCollectionID: collection.id, boardAppearance: $collection.boardAppearance)
            .environment(\.planningDisplayedWeekKey, nil)
            .environment(\.planningDirectItemReturn, initialCardID == nil ? nil : { dismiss() })
            .environment(\.planningHomeExit, { dismiss(); onLeaveForHome() })
            .task {
                guard !didOpenInitialTarget else { return }
                didOpenInitialTarget = true
                targetListID = initialListID; targetCardID = initialCardID
            }
            .onChange(of: collection) { old, next in
                if isRevertingEdit { isRevertingEdit = false; return }
                if old != next, access?.saveLibrary(next) != true { isRevertingEdit = true; collection = old }
            }
            .onChange(of: access?.library) { _, library in
                if let next = library?.first(where: { $0.id == collection.id }), next != collection { collection = next }
            }
    }
}

/// Date-preserving week migration can separate two lists containing linked checklist cards.
struct PlanningChecklistLink: View {
    let itemID: UUID
    let cardID: Int
    let title: String
    var ownerID: UUID? = nil
    @Environment(\.planningCalendarAccess) private var access
    @State private var showsCard = false
    private var destination: (DatedPlanningWeek, Int)? {
        guard let owner = access?.document.checklistLinkWeeks?[itemID] ?? ownerID,
              let week = access?.document.weeks.first(where: { $0.id == owner }),
              let list = week.collection.lists.first(where: { !$0.isArchived && $0.cards.contains { $0.id == cardID } }) else { return nil }
        return (week, list.id)
    }
    var body: some View {
        Button { showsCard = true } label: {
            Image(systemName: "link").frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(destination == nil)
        .accessibilityLabel("Open linked card: \(title)")
        .fullScreenCover(isPresented: $showsCard) {
            if let (week, listID) = destination {
                PlanningCalendarWeekView(week: week, initialDayID: listID, initialCardID: cardID, onLeaveForHome: { showsCard = false })
            }
        }
    }
}


/// Direct week selection changes the browsed board without changing Today's active week.
struct PlanningWeekSelector: View {
    let document: PlanningCalendarDocument
    let onSelect: (DatedPlanningWeek, Date) -> Void
    @State private var referenceDate: Date
    @State private var selectedDate: Date
    @State private var highlightedWeekKey: String
    @State private var isSelecting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initialDate: Date, document: PlanningCalendarDocument, selectedWeekKey: String,
         onSelect: @escaping (DatedPlanningWeek, Date) -> Void) {
        self.document = document
        self.onSelect = onSelect
        _referenceDate = State(initialValue: initialDate)
        _selectedDate = State(initialValue: initialDate)
        _highlightedWeekKey = State(initialValue: selectedWeekKey)
    }

    static func choices(document: PlanningCalendarDocument, referenceDate: Date) -> [DatedPlanningWeek] {
        var choices = Dictionary(uniqueKeysWithValues: document.weeks.map { ($0.startKey, $0) })
        for offset in -8...8 {
            guard let date = document.calendar.date(byAdding: .weekOfYear, value: offset, to: referenceDate) else { continue }
            let key = PlanningDate.weekKey(date, calendar: document.calendar)
            if choices[key] == nil { choices[key] = DatedPlanningWeek.make(for: date, calendar: document.calendar) }
        }
        return choices.values.sorted { $0.startKey < $1.startKey }
    }


    static func monthDays(_ date: Date, calendar: Calendar) -> [Date] {
        guard let first = calendar.dateInterval(of: .month, for: date)?.start,
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }
    private var rows: [[Date]] {
        let days = Self.monthDays(referenceDate, calendar: document.calendar)
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }
    private var weekdaySymbols: [String] {
        let symbols = document.calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + document.calendar.firstWeekday - 1) % 7] }
    }
    private func changeMonth(_ amount: Int) {
        if let first = document.calendar.dateInterval(of: .month, for: referenceDate)?.start,
           let next = document.calendar.date(byAdding: .month, value: amount, to: first) { referenceDate = next }
    }
    private func select(_ date: Date) {
        guard !isSelecting else { return }
        isSelecting = true
        let key = PlanningDate.weekKey(date, calendar: document.calendar)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            highlightedWeekKey = key
            selectedDate = date
        }
        let week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: document.calendar)
        Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            onSelect(week, date)
            dismiss()
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text(referenceDate.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("Previous month")
                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("Next month")
                }
                .foregroundStyle(.primary)
                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol.uppercased()).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 4) {
                    ForEach(rows.indices, id: \.self) { row in
                        let dates = rows[row]
                        let highlighted = dates.first.map { PlanningDate.weekKey($0, calendar: document.calendar) == highlightedWeekKey } ?? false
                        HStack(spacing: 0) {
                            ForEach(dates, id: \.self) { date in
                                let selected = document.calendar.isDate(date, inSameDayAs: selectedDate)
                                let inMonth = document.calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
                                Button { select(date) } label: {
                                    Text(String(document.calendar.component(.day, from: date)))
                                        .font(.body.weight(selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? Color.white : (inMonth ? Color.primary : Color.secondary))
                                        .frame(width: 36, height: 36)
                                        .background(selected ? Color.blue : Color.clear, in: Circle())
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                                .accessibilityHint("Show the week containing this day")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        .background(highlighted ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text("Tap any day to show its week.").font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .disabled(isSelecting)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("Choose week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationBackground(Color(.systemBackground))
        .presentationDetents([.height(520), .large])
    }
}


struct PlanningDaySelection {
    let date: Date
    let week: DatedPlanningWeek
    let listID: Int

    static func resolve(_ date: Date, document: PlanningCalendarDocument) -> Self? {
        let date = document.calendar.startOfDay(for: date)
        let week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: document.calendar)
        guard let id = week.dayListIDs[PlanningDate.key(date, calendar: document.calendar)],
              week.collection.lists.contains(where: { $0.id == id && !$0.isArchived }) else { return nil }
        return Self(date: date, week: week, listID: id)
    }
}

struct PlanningDaySelector: View {
    @State private var date: Date
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    init(initialDate: Date, onSelect: @escaping (Date) -> Void) {
        _date = State(initialValue: initialDate)
        self.onSelect = onSelect
    }
    var body: some View {
        NavigationStack {
            DatePicker("Choose a day", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Choose day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Show day") { dismiss(); onSelect(date) }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Keeps date browsing in one Day surface and saves edits to the selected week's owner.
struct PlanningSelectedDayView: View {
    let selection: PlanningDaySelection
    let currentUserName: String
    let returnDestinationTitle: String
    let onClose: () -> Void
    let onSelectDay: (Date) -> Void
    @State private var week: DatedPlanningWeek
    @State private var labels = LabelLibraryStore.load()
    @State private var isRevertingEdit = false
    @Environment(\.planningCalendarAccess) private var access

    init(selection: PlanningDaySelection, currentUserName: String, returnDestinationTitle: String,
         onClose: @escaping () -> Void, onSelectDay: @escaping (Date) -> Void) {
        self.selection = selection
        self.currentUserName = currentUserName
        self.returnDestinationTitle = returnDestinationTitle
        self.onClose = onClose
        self.onSelectDay = onSelectDay
        _week = State(initialValue: selection.week)
    }

    var body: some View {
        TodayListDetailView(onSelectDay: onSelectDay,
            lists: $week.collection.lists.activeLists,
            reservedLists: week.collection.lists.filter(\.isArchived), labelLibrary: $labels,
            savedCardIDs: $week.collection.savedCardIDs, listID: selection.listID,
            currentUserName: currentUserName, onClose: onClose,
            onOpenWeek: { access?.openWeek(week); onClose() },
            onPermanentDelete: { cardID in
                var next = week
                BoardContentDeletion.card(cardID, in: &next.collection.lists, savedCardIDs: &next.collection.savedCardIDs)
                guard access?.saveWeek(next) == true else { return false }
                week = next
                return true
            }, boardAppearance: week.collection.boardAppearance,
            returnDestinationTitle: returnDestinationTitle,
            representedDate: selection.date)
            .environment(\.cardMovementSource, week.id)
            .environment(\.planningDisplayedWeekKey, week.startKey)
            .onChange(of: week) { old, updated in
                if isRevertingEdit { isRevertingEdit = false; return }
                if access?.saveWeek(updated) != true { isRevertingEdit = true; week = old }
            }
            .onChange(of: access?.document) { _, document in
                if let updated = document?.weeks.first(where: { $0.startKey == week.startKey }), updated != week {
                    week = updated
                }
            }
    }
}

// Full-month examples use a separate, verified offline snapshot of the entire local workspace.
struct FullMonthExampleStore: Sendable {
    let root: URL
    let documents: URL
    let support: URL
    let domainName: String
    private var defaults: UserDefaults {
        domainName == Bundle.main.bundleIdentifier ? .standard : UserDefaults(suiteName: domainName)!
    }
    private var userData: URL { root.appendingPathComponent("UserData", isDirectory: true) }
    private var transition: URL { root.appendingPathComponent("Transition", isDirectory: true) }
    private var fm: FileManager { .default }
    private struct Manifest: Codable {
        var version = 1
        var createdAt = Date()
        let hashes: [String: String]
    }
    static func live() throws -> Self {
        let fm = FileManager.default
        let library = try fm.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return Self(root: library.appendingPathComponent("PlenactDatasetBackup", isDirectory: true),
                    documents: try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
                    support: try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
                    domainName: Bundle.main.bundleIdentifier!)
    }
    var needsRecovery: Bool { fm.fileExists(atPath: transition.path) && committedOperation() == nil }
    var hasUserData: Bool {
        fm.fileExists(atPath: userData.path) && committedOperation() != "restore"
    }
    private func committedOperation() -> String? {
        try? String(contentsOf: transition.appendingPathComponent("Committed"), encoding: .utf8)
    }
    private func digest(_ url: URL) throws -> String {
        // Stream large attachments rather than loading an entire video into memory.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func hashes(in directory: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        var enumerationError: Error?
        guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                          errorHandler: { _, error in enumerationError = error; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        for case let url as URL in entries {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
            if values.isRegularFile == true {
                let key = String(url.path.dropFirst(directory.path.count + 1))
                if key != "Manifest.json" { result[key] = try digest(url) }
            }
        }
        if let enumerationError { throw enumerationError }
        return result
    }
    private func verify(_ directory: URL) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("Manifest.json")))
        guard manifest.version == 1, try hashes(in: directory) == manifest.hashes else { throw CocoaError(.fileReadCorruptFile) }
        _ = try savedDomain(in: directory)
    }
    private func savedDomain(in directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("Defaults.plist"))
        guard let domain = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return domain
    }
    private func capture(to destination: URL) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        let domain = defaults.persistentDomain(forName: domainName) ?? [:]
        let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
        try data.write(to: staging.appendingPathComponent("Defaults.plist"), options: .atomic)
        for (name, source) in [("Documents", documents), ("ApplicationSupport", support)] {
            let target = staging.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: target) }
            else { try fm.createDirectory(at: target, withIntermediateDirectories: true) }
        }
        let manifest = Manifest(hashes: try hashes(in: staging))
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("Manifest.json"), options: .atomic)
        try verify(staging)
        try fm.moveItem(at: staging, to: destination)
        var local = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try local.setResourceValues(values)
    }
    private func setDomain(_ domain: [String: Any]) throws {
        defaults.setPersistentDomain(domain, forName: domainName)
        guard defaults.synchronize(), NSDictionary(dictionary: defaults.persistentDomain(forName: domainName) ?? [:]).isEqual(to: domain) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
    private func installFiles(from snapshot: URL) throws {
        // Each immutable source survives interrupted installation and can be retried at launch.
        for (name, target) in [("Documents", documents), ("ApplicationSupport", support)] {
            let staged = root.appendingPathComponent("install-" + UUID().uuidString, isDirectory: true)
            defer { try? fm.removeItem(at: staged) }
            try fm.copyItem(at: snapshot.appendingPathComponent(name), to: staged)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: staged, to: target)
        }
    }
    private func finishCommitted() throws {
        if committedOperation() == "restore", fm.fileExists(atPath: userData.path) { try fm.removeItem(at: userData) }
        try fm.removeItem(at: transition)
    }
    /// Run before constructing any view or loading any saved model after an interrupted switch.
    func recoverInterruptedSwitch() throws {
        guard fm.fileExists(atPath: transition.path) else { return }
        if committedOperation() != nil { try finishCommitted(); return }
        try verify(transition)
        try installFiles(from: transition)
        try setDomain(savedDomain(in: transition))
        try fm.removeItem(at: transition)
    }
    func loadExample(_ example: FullMonthExample) throws {
        try recoverInterruptedSwitch()
        if !hasUserData { try capture(to: userData) }
        try verify(userData)
        let domain = try example.defaultsDomain(preserving: defaults.persistentDomain(forName: domainName) ?? [:])
        try capture(to: transition)
        do {
            try setDomain(domain)
            try Data("load".utf8).write(to: transition.appendingPathComponent("Committed"), options: .atomic)
        } catch {
            try recoverInterruptedSwitch()
            throw error
        }
        try? finishCommitted()
    }
    func restoreUserData() throws {
        try recoverInterruptedSwitch()
        guard hasUserData else { throw CocoaError(.fileNoSuchFile) }
        try verify(userData)
        try capture(to: transition)
        do {
            try installFiles(from: userData)
            try setDomain(savedDomain(in: userData))
            try Data("restore".utf8).write(to: transition.appendingPathComponent("Committed"), options: .atomic)
        } catch {
            try recoverInterruptedSwitch()
            throw error
        }
        try? finishCommitted()
    }
}

struct FullMonthExample: Sendable {
    let document: PlanningCalendarDocument
    let collections: [PersonalCollection]
    static func make(now: Date = .now, calendar: Calendar = .current) -> Self {
        let today = calendar.startOfDay(for: now)
        let month = calendar.dateInterval(of: .month, for: today)!
        let days = calendar.range(of: .day, in: .month, for: today)!
        var document = PlanningCalendarDocument(currentWeekKey: PlanningDate.weekKey(today, calendar: calendar),
                                                firstWeekday: calendar.firstWeekday, weeks: [])
        var nextID = 0
        for offset in 0..<days.count {
            let date = calendar.date(byAdding: .day, value: offset, to: month.start)!
            var week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: calendar)
            let listID = week.dayListIDs[PlanningDate.key(date, calendar: calendar)]!
            let index = week.collection.lists.firstIndex { $0.id == listID }!
            let past = date < today
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let count = past ? 3 + offset % 3 : (isToday ? 4 : (offset % 4 == 0 ? 1 : 0))
            let titles = SampleData.cardTitlesByDay[(calendar.component(.weekday, from: date) + 5) % 7]
            week.collection.lists[index].cards = (0..<count).map { item in
                let timed = item == 1 || (!past && !isToday)
                let start = calendar.date(bySettingHour: 9 + item * 2, minute: 0, second: 0, of: date)!
                let end = calendar.date(byAdding: .minute, value: 45, to: start)!
                let note = item == 3
                let card = KanbanCard(id: nextID, word: note ? "A moment from today" : titles[item % titles.count],
                    listTitle: week.collection.lists[index].title, isTitleChecked: (past && item != 2) || (isToday && item == 0),
                    startDate: timed ? start : nil, dueDate: timed ? end : date,
                    checklists: item == 0 ? [KanbanChecklist(title: "Small steps", items: ["Choose a starting point", "Take the next step", "Review the result"])] : [],
                    members: [], labelIDs: [LabelLibrary.starterLabelIDs[item % LabelLibrary.starterLabelIDs.count]],
                    attachments: [], descriptionOverride: note ? "A little progress, a useful discovery, and room to begin again tomorrow.\n\nThis is fictional example content." : "One manageable step toward a calmer, more intentional day. Example content you can edit freely.",
                    subtitleOverride: "", presentation: note ? .note : .card, createdAt: date,
                    startDateKind: timed ? .dateAndTime : .date, dueDateKind: timed ? .dateAndTime : .date)
                nextID += 1
                return card
            }
            document.upsert(week)
        }
        // Example Library content is independent of every dated week.
        let collections = [PersonalListExample.onTheTable, .inTheQueue, .scheduled].map { $0.makeCollection(existingTitles: []) }
        return Self(document: document, collections: collections)
    }
    var previewLists: [KanbanList] {
        document.weeks.enumerated().flatMap { weekIndex, week in
            week.collection.lists.enumerated().compactMap { listIndex, list in
                guard !list.cards.isEmpty else { return nil }
                let key = week.dayListIDs.first { $0.value == list.id }?.key
                let date = key.flatMap { PlanningDate.date($0, calendar: document.calendar) }
                let title = date.map { PlanningDate.listTitle(list.title, on: $0, calendar: document.calendar) } ?? list.title
                return KanbanList(id: weekIndex * 100 + listIndex, title: title, cards: list.cards)
            }
        }
    }
    func defaultsDomain(preserving original: [String: Any]) throws -> [String: Any] {
        guard let current = document.weeks.first(where: { $0.startKey == document.currentWeekKey }) else { throw CocoaError(.coderInvalidValue) }
        // Keep non-Plenact platform preferences; all app-owned data/settings remain in the backup.
        var result = original.filter { !$0.key.hasPrefix("Plenact.") }
        let encoder = JSONEncoder()
        result[PlanningCalendarStore.key] = try encoder.encode(document)
        result["Plenact.Board.v1"] = try encoder.encode(current.collection.lists)
        result["Plenact.PersonalCollections.v1"] = try encoder.encode(collections)
        result["Plenact.SavedCardIDs.v1"] = [Int]()
        result[TodayListPins.key] = TodayListPins.encode(collections.map { WorkspaceListReference(ownerID: $0.id, listID: $0.lists[0].id) })
        return result
    }
}
