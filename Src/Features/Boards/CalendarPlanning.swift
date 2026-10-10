import SwiftUI

/// Stable local date keys avoid timestamp shifts when a user changes time zone.
enum PlanningDate {
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
extension EnvironmentValues {
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
            let scheduled = [item.card.startDate, item.card.dueDate].compactMap { $0 }.contains {
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
                    HStack {
                        Button("This week", systemImage: "rectangle.split.3x1") {
                            access?.openCurrentWeek(); dismiss(); onLeaveForHome()
                        }
                        Spacer()
                    }
                    .buttonStyle(.bordered)
                    monthGrid.dynamicTypeSize(.large) // Seven columns stay legible; full dates are announced by VoiceOver.
                    daySummary
                }
                .padding(16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() }.dynamicTypeSize(.large) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { access?.openToday(); dismiss(); onLeaveForHome() } label: { Image(systemName: "sun.max").font(.system(size: 20)) }
                        .accessibilityLabel("Open Today")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSearch = true } label: { Image(systemName: "magnifyingglass").font(.system(size: 20)) }
                        .accessibilityLabel("Search calendar and Library")
                }
            }
            .modifier(PlanningSharedSearchPresentation(isPresented: $showsSearch, onLeaveForHome: { dismiss(); onLeaveForHome() }))
            .fullScreenCover(item: $route) { route in
                PlanningCalendarWeekView(week: route.week, initialDayID: route.dayID, initialCardID: route.cardID,
                    onLeaveForHome: { self.route = nil; dismiss(); onLeaveForHome() })
            }
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
                            Image(systemName: rowWeek.hasContent ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                                .foregroundStyle(rowWeek.hasContent || isCurrent ? Color.accentColor : Color.secondary.opacity(0.4))
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
                    .font(.subheadline.weight(Calendar.current.isDateInToday(date) ? .bold : .regular))
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

private struct PlanningCalendarWeekView: View {
    @State var week: DatedPlanningWeek
    let initialDayID: Int?
    let initialCardID: Int?
    let onLeaveForHome: () -> Void
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
            boardTitle: isCurrent ? "This week" : "Week", boardSubtitle: week.rangeTitle,
            allowsAddingLists: false, onClose: { dismiss() },
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
        .environment(\.cardMovementSource, week.id)
        .environment(\.planningHomeExit, { dismiss(); onLeaveForHome() })
        .task {
            guard !didOpenInitialTarget else { return }
            didOpenInitialTarget = true
            if let initialDayID {
                if let initialCardID { targetListID = initialDayID; targetCardID = initialCardID }
                else { dayID = initialDayID; showsDay = true }
            }
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
        } + access.library.filter(\.isActive).map { ($0.id, nil, "Library · \($0.title)", $0.lists) }
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
    @State private var pending: TodaySearchResult?
    @State private var route: PlanningSearchRoute?
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: {
                if let pending { self.pending = nil; route = PlanningSearchRoute(result: pending) }
            }) {
                TodaySearchView(lists: [], onOpenBoardList: { _ in }, onOpenBoardCard: { _, _ in },
                    onArchiveCard: { _ in }, onDeleteCard: { _ in false }, onArchiveList: { _ in }, onDeleteList: { _ in false },
                    resultProvider: { query, scope, labels in
                        guard let access else { return [] }
                        return PlanningSharedSearchIndex.results(query: query, scope: scope, access: access, labels: labels)
                    }, onSelectResult: { result in pending = result; isPresented = false })
            }
            .fullScreenCover(item: $route) { route in
                if let key = route.result.weekKey, let week = access?.document.weeks.first(where: { $0.startKey == key }) {
                    PlanningCalendarWeekView(week: week,
                        initialDayID: route.result.listID, initialCardID: route.result.cardID,
                        onLeaveForHome: { self.route = nil; onLeaveForHome() })
                } else if let collection = access?.library.first(where: { $0.id == route.result.ownerID }) {
                    PlanningSearchLibraryView(collection: collection, initialListID: route.result.listID, initialCardID: route.result.cardID,
                        onLeaveForHome: { self.route = nil; onLeaveForHome() })
                }
            }
    }
}

private struct PlanningSearchLibraryView: View {
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
            boardTitle: collection.title, boardSubtitle: "Library", allowsAddingLists: collection.kind == .board,
            fillsAvailableListWidth: collection.kind == .list, onClose: { dismiss() },
            onCommitDeletion: { lists, saved in
                var updated = collection; updated.lists = lists; updated.savedCardIDs = saved
                guard access?.saveLibrary(updated) == true else { throw CocoaError(.fileWriteUnknown) }
                collection = updated
            }, onListsChanged: { _ in }, retainedAttachmentLists: { access?.allRetainedLists ?? [] },
            personalCollectionID: collection.id, boardAppearance: $collection.boardAppearance)
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
