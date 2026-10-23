import SwiftUI
import CryptoKit

/// Stable local date keys avoid timestamp shifts when a user changes time zone.
enum PlanningDate {


    ///
    /// @fcn        PlanningDate.listTitle
    /// @brief      Build a dated list title for nonheader contexts
    /// @details    Appends month and day, adding a two-digit year when the represented year differs from the
    ///             reference year.
    ///
    /// @param[in]  title     Display title or proposed title text
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  now       Reference time used instead of an implicit clock read
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (String) title suffixed with month/day and, for another year, a two-digit year
    ///
    static func listTitle(_ title: String, on date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let suffix = year == calendar.component(.year, from: now)
            ? "\(month)/\(day)" : "\(month)/\(day)/\(String(format: "%02d", year % 100))"
        return "\(title) (\(suffix))"
    }


    ///
    /// @fcn        PlanningDate.key
    /// @brief      Create a stable local calendar-day storage key
    /// @details    Uses Gregorian year, month, and day in the supplied calendar's time zone, independent of its
    ///             week-start setting.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (String) zero-padded Gregorian yyyy-MM-dd key in the supplied time zone
    ///
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }


    ///
    /// @fcn        PlanningDate.date
    /// @brief      Resolve a stored day key to a local date
    /// @details    Parses three numeric components and constructs local noon in a Gregorian calendar with the
    ///             supplied time zone; returns nil if construction fails.
    ///
    /// @param[in]  key       Storage key or stable lookup key used by this operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (Date?) decoded local-noon date, or nil if parsing or date construction fails
    ///
    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }


    ///
    /// @fcn        PlanningDate.weekKey
    /// @brief      Find the storage key for the containing week's start
    /// @details    Uses the supplied calendar's week interval, falling back to the given date if that interval is
    ///             unavailable.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (String) local day key identifying the start of the containing calendar week
    ///
    static func weekKey(_ date: Date, calendar: Calendar = .current) -> String {
        key(calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date, calendar: calendar)
    }


    ///
    /// @fcn        PlanningDate.days
    /// @brief      Resolve the seven local dates belonging to a week key
    /// @details    Adds calendar days from the decoded start so daylight-saving transitions do not assume fixed
    ///             twenty-four-hour intervals; invalid keys produce an empty array.
    ///
    /// @param[in]  weekKey   Local calendar-week start key
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     ([Date]) up to seven calendar-day dates, or an empty array if the key cannot be resolved
    ///
    static func days(in weekKey: String, calendar: Calendar = .current) -> [Date] {
        guard let start = date(weekKey, calendar: calendar) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }


    ///
    /// @fcn        PlanningDate.weekdayTitle
    /// @brief      Return the English weekday name for a date
    /// @details    Indexes the Sunday-first name table using the supplied calendar's weekday component.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (String) English weekday name corresponding to the calendar weekday component
    ///
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


    ///
    /// @fcn        DatedPlanningWeek.list
    /// @brief      Find the active list mapped to a calendar day
    /// @details    Resolves the day key through dayListIDs and returns nil when the mapping or active list is
    ///             missing.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (KanbanList?) active list mapped to the requested day, or nil if missing
    ///
    func list(on date: Date) -> KanbanList? {
        guard let id = dayListIDs[PlanningDate.key(date)] else { return nil }
        return collection.lists.first { $0.id == id && !$0.isArchived }
    }


    ///
    /// @fcn        DatedPlanningWeek.prepareDay
    /// @brief      Ensure the week contains an active list for a day
    /// @details    Reuses an existing mapped list or allocates and appends a new weekday list, then records its day
    ///             mapping.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (Int) ID of the existing or newly appended active weekday list
    ///
    mutating func prepareDay(_ date: Date) -> Int {
        if let existing = list(on: date) { return existing.id }
        let id = (collection.lists.map(\.id).max() ?? -1) + 1
        collection.lists.append(KanbanList(id: id, title: PlanningDate.weekdayTitle(date), cards: []))
        dayListIDs[PlanningDate.key(date)] = id
        return id
    }


    ///
    /// @fcn        DatedPlanningWeek.make
    /// @brief      Construct a dated week around existing or empty lists
    /// @details    Maps weekday titles onto calendar days, creates missing day lists, and retains the supplied
    ///             saved-card IDs in the new collection.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  lists     Lists participating in the operation
    /// @param[in]  saved     Owner-local saved-card identities, updated when bookmarked content moves
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (DatedPlanningWeek) constructed value
    ///
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


    ///
    /// @fcn        PlanningCalendarDocument.week
    /// @brief      Find the retained week containing a date
    /// @details    Matches a week-start key using the supplied calendar override or the document's calendar and
    ///             returns nil if absent.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (DatedPlanningWeek?) retained matching week, or nil if the calendar has no such week
    ///
    func week(for date: Date, calendar: Calendar? = nil) -> DatedPlanningWeek? {
        weeks.first { $0.startKey == PlanningDate.weekKey(date, calendar: calendar ?? self.calendar) }
    }


    ///
    /// @fcn        PlanningCalendarDocument.upsert
    /// @brief      Insert or replace a dated week by its start key
    /// @details    Replaces an existing matching week or appends it, then sorts all weeks chronologically by key.
    ///
    /// @param[in]  week  Dated planning week being inspected or saved
    ///
    /// @return     (Void) no return value
    ///
    mutating func upsert(_ week: DatedPlanningWeek) {
        if let index = weeks.firstIndex(where: { $0.startKey == week.startKey }) { weeks[index] = week }
        else { weeks.append(week) }
        weeks.sort { $0.startKey < $1.startKey }
    }


    ///
    /// @fcn        PlanningCalendarDocument.rollForward
    /// @brief      Retain the outgoing week and select the requested week
    /// @details    Captures current lists and bookmarks before choosing an existing, supplied, or empty destination
    ///             week and updating currentWeekKey.
    ///
    /// @param[in]  date              Represented date for the operation
    /// @param[in]  currentLists      Current live-week lists retained before selecting another week
    /// @param[in]  saved             Owner-local saved-card identities, updated when bookmarked content moves
    /// @param[in]  suppliedCalendar  Optional override for the document's calendar
    /// @param[in]  newWeek           Optional prepared destination week to use when none is retained
    ///
    /// @return     (DatedPlanningWeek) selected incoming week after the outgoing week has been retained
    ///
    mutating func rollForward(to date: Date, currentLists: [KanbanList], saved: Set<Int>,
                              calendar suppliedCalendar: Calendar? = nil, newWeek: DatedPlanningWeek? = nil) -> DatedPlanningWeek {
        let calendar = suppliedCalendar ?? self.calendar
        if var previous = weeks.first(where: { $0.startKey == currentWeekKey }) {
            previous.collection.lists = currentLists
            previous.collection.savedCardIDs = saved
            upsert(previous)
        }
        let key = PlanningDate.weekKey(date, calendar: calendar)
        let next = weeks.first { $0.startKey == key } ?? newWeek ?? DatedPlanningWeek.make(for: date, calendar: calendar)
        upsert(next)
        currentWeekKey = key
        return next
    }
}


extension PlanningCalendarDocument {


    ///
    /// @fcn        PlanningCalendarDocument.repairLegacyMondayFirstLayout
    /// @brief      Repair a recognized legacy weekday mapping
    /// @details    Checks the specific Monday-first legacy arrangement before invoking the calendar migration;
    ///             unrelated layouts return false without alteration.
    ///
    /// @param[in]  now  Reference time used instead of an implicit clock read
    ///
    /// @return     (Bool) true when the recognized legacy layout was repaired; false when no repair applies
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    /// @note       Legacy Monday–Sunday boards were initially dated using the device's Sunday-start calendar.
    ///             Repartition by existing date associations; never relabel the old Sunday's content.
    ///
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


    ///
    /// @fcn        PlanningCalendarDocument.changeFirstWeekday
    /// @brief      Regroup retained planning days under a new week start
    /// @details    Accepts Sunday or Monday, rebuilds dated ownership while preserving content and bookmarks, and
    ///             rewrites IDs and links where ownership changes.
    ///
    /// @param[in]  weekday  Requested supported planning week-start value
    /// @param[in]  now      Reference time used instead of an implicit clock read
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`,
    ///             `CocoaError(.coderReadCorrupt)`. Errors from throwing dependencies propagate unless handled within
    ///             this operation.
    ///
    /// @note       Repartition dated lists without changing their dates or dropping archived content. Undated lists
    ///             and board appearance stay with the middle of their original week.
    ///
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


                ///
                /// @fcn        PlanningCalendarDocument.changeFirstWeekday.relocated
                /// @brief      Relocate a card during weekday regrouping
                /// @details    Replaces its ID and list title using the enclosing migration maps and updates
                ///             checklist references to retained and linked cards.
                ///
                /// @param[in]  card  Card or note being inspected or changed
                ///
                /// @return     (KanbanCard) card with destination-safe identity, list title, and migrated checklist
                ///             references
                ///
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


            ///
            /// @fcn        PlanningCalendarDocument.changeFirstWeekday.preservingOwners
            /// @brief      Qualify retained checklist references after regrouping
            /// @details    Resolves implicit or former-week ownership through the migration's card-owner map so
            ///             references still identify their retained cards.
            ///
            /// @param[in]  card  Card or note being inspected or changed
            ///
            /// @return     (KanbanCard) card with retained checklist references qualified to their migrated owners
            ///
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


    ///
    /// @fcn        PlanningCalendarStore.load
    /// @brief      Read and validate the retained planning calendar
    /// @details    Returns nil for absent storage and rejects malformed encoding, unsupported versions, duplicate
    ///             week identities, or a missing current week.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (PlanningCalendarDocument?) validated document, or nil when no saved value exists
    /// @throws     Explicit failures include `CocoaError(.coderReadCorrupt)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        PlanningCalendarStore.save
    /// @brief      Save a calendar without overwriting unreadable retained data
    /// @details    Loads the existing value first so corruption or unsupported data is surfaced before the encoded
    ///             replacement is written.
    ///
    /// @param[in]  document  Retained document containing the operation's current workspace records
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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
    var saveExampleWeek: ((DatedPlanningWeek, Set<Int>) -> Bool)? = nil
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

/// Shared membership rules keep Calendar and Choose week indicators in agreement.
enum PlanningCalendarContent {


    ///
    /// @fcn        PlanningCalendarContent.items
    /// @brief      Select content represented on a calendar day
    /// @details    Includes cards in that day's mapped list and cards with a date-bearing start or due value on that
    ///             day; time-only values do not create calendar matches.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  document  Retained document containing the operation's current workspace records
    /// @param[in]  sources   Live owner-qualified workspace items used to resolve retained references
    ///
    /// @return     ([PlanningSearchResult]) workspace items planned in the day's list or explicitly scheduled on that
    ///             date
    ///
    static func items(on date: Date, document: PlanningCalendarDocument, sources: [PlanningSearchResult]) -> [PlanningSearchResult] {
        let calendar = document.calendar
        let week = document.week(for: date)
        let listID = week?.list(on: date)?.id
        return sources.filter { item in
            let planned = week.map { item.weekKey == $0.startKey && item.collectionID == $0.id && item.listID == listID } ?? false
            let scheduled = [item.card.startDateKind.includesDate ? item.card.startDate : nil,
                             item.card.dueDateKind.includesDate ? item.card.dueDate : nil]
                .compactMap { $0 }.contains { calendar.isDate($0, inSameDayAs: date) }
            return planned || scheduled
        }
    }
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


    ///
    /// @fcn        PlanningCalendarView.init
    /// @brief      Initialize calendar navigation around a requested date
    /// @details    Seeds the displayed month and selected local day using Calendar.current and retains the callback
    ///             used when leaving for home.
    ///
    /// @param[in]  initialDate     Date initially selected when the view opens
    /// @param[in]  onLeaveForHome  Callback used after navigation leaves the calendar for home
    ///
    /// @return     (PlanningCalendarView) initialized instance
    ///
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


    ///
    /// @fcn        PlanningCalendarView.week
    /// @brief      Resolve a retained week or an unsaved empty preview
    /// @details    Uses the shared calendar document when available and otherwise constructs a week with the display
    ///             calendar without saving it.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (DatedPlanningWeek) retained week or a newly constructed unsaved empty week
    ///
    private func week(on date: Date) -> DatedPlanningWeek {
        access?.document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: displayCalendar)
    }


    ///
    /// @fcn        PlanningCalendarView.items
    /// @brief      Look up searchable content for a calendar date
    /// @details    Uses the shared calendar-content selector and returns an empty result when calendar access is
    ///             unavailable.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     ([PlanningSearchResult]) searchable items represented on the requested day, or an empty array
    ///             without access
    ///
    private func items(on date: Date) -> [PlanningSearchResult] {
        guard let access else { return [] }
        return PlanningCalendarContent.items(on: date, document: access.document, sources: access.searchableItems)
    }


    ///
    /// @fcn        PlanningCalendarView.open
    /// @brief      Navigate to the selected calendar search result
    /// @details    Routes retained-week content within the calendar; library content opens through its owner callback
    ///             before leaving the calendar presentation.
    ///
    /// @param[in]  result  Resolved search or Activity match to render or open
    ///
    /// @return     (Void) no return value
    ///
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
            .modifier(LowerCornerBackShortcut(action: { dismiss() }))
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


    ///
    /// @fcn        PlanningCalendarView.dayButton
    /// @brief      Build a selectable calendar day cell
    /// @details    Shows the day number, today styling, selection state, and an item-presence dot based on the day's
    ///             searchable content.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (some View) a selectable calendar day cell
    ///
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


    ///
    /// @fcn        PlanningCalendarView.moveMonth
    /// @brief      Advance the displayed calendar month
    /// @details    Adds the requested month offset and leaves the current month unchanged if calendar arithmetic
    ///             fails.
    ///
    /// @param[in]  amount  Signed calendar-month offset
    ///
    /// @return     (Void) no return value
    ///
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
        .modifier(OwnerImportanceControls(ownerID: week.id))
        .environment(\.planningHomeExit, { dismiss(); onLeaveForHome() })
        .task {
            guard !didOpenInitialTarget else { return }
            didOpenInitialTarget = true
            if !isStored, let access {
                do {
                    let date = PlanningDate.date(week.startKey, calendar: access.document.calendar)!
                    let prepared = try PlanningRoutineStore.newWeek(for: date, calendar: access.document.calendar)
                    guard access.saveWeek(prepared) else { dismiss(); return }
                    isRevertingEdit = true
                    week = prepared
                } catch {
                    DatabaseActivity.shared.report("Could not create this week from its template. Your saved plans were retained.")
                    dismiss(); return
                }
            }
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
                    .modifier(OwnerImportanceControls(ownerID: week.id))
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


    ///
    /// @fcn        PlanningSharedSearchIndex.results
    /// @brief      Search retained weeks and active personal collections
    /// @details    Runs the shared search over active lists and annotates each match with its owner, week key, and
    ///             location title for later navigation.
    ///
    /// @param[in]  query   User-entered search text
    /// @param[in]  scope   Search scope restricting the kind of shared results
    /// @param[in]  access  Checked calendar and personal-owner access callbacks
    /// @param[in]  labels  Label catalog used to resolve stored label IDs
    ///
    /// @return     ([TodaySearchResult]) calendar and Library matches annotated with owner and week navigation
    ///             metadata
    ///
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


    ///
    /// @fcn        SharedSearchLifecycleActions.body
    /// @brief      Attach lifecycle controls when shared search permits them
    /// @details    Installs archive and delete handling only when enabled; otherwise preserves the supplied content.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) attach lifecycle controls when shared search permits them
    ///
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


    ///
    /// @fcn        PlanningSharedSearchPresentation.body
    /// @brief      Present workspace-wide search and its selected route
    /// @details    Supplies calendar-backed results and routes chosen matches through the shared destination
    ///             presentation rather than an isolated search copy.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) present workspace-wide search and its selected route
    ///
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
    let sources: [PlanningSearchResult]
    let onSelect: (DatedPlanningWeek, Date) -> Void
    @State private var referenceDate: Date
    @State private var selectedDate: Date
    @State private var highlightedWeekKey: String
    @State private var isSelecting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    ///
    /// @fcn        PlanningWeekSelector.init
    /// @brief      Seed the week chooser's selected date and highlight
    /// @details    Retains the calendar document, searchable sources, and selection callback while initializing its
    ///             local date and week-key state.
    ///
    /// @param[in]  initialDate      Date initially selected when the view opens
    /// @param[in]  document         Retained document containing the operation's current workspace records
    /// @param[in]  selectedWeekKey  Week-start key initially highlighted in the chooser
    /// @param[in]  sources          Live owner-qualified workspace items used to resolve retained references
    /// @param[in]  onSelect         Callback invoked after the user confirms a selection
    ///
    /// @return     (PlanningWeekSelector) initialized instance
    ///
    init(initialDate: Date, document: PlanningCalendarDocument, selectedWeekKey: String, sources: [PlanningSearchResult] = [],
         onSelect: @escaping (DatedPlanningWeek, Date) -> Void) {
        self.document = document
        self.onSelect = onSelect
        self.sources = sources
        _referenceDate = State(initialValue: initialDate)
        _selectedDate = State(initialValue: initialDate)
        _highlightedWeekKey = State(initialValue: selectedWeekKey)
    }


    ///
    /// @fcn        PlanningWeekSelector.choices
    /// @brief      Build retained and nearby unsaved week choices
    /// @details    Adds missing weeks within eight weeks of the reference date to a key-indexed copy and returns
    ///             chronological choices without persisting them.
    ///
    /// @param[in]  document       Retained document containing the operation's current workspace records
    /// @param[in]  referenceDate  Date around which available calendar choices are constructed
    ///
    /// @return     ([DatedPlanningWeek]) chronological retained and nearby unsaved week choices
    ///
    static func choices(document: PlanningCalendarDocument, referenceDate: Date) -> [DatedPlanningWeek] {
        var choices = Dictionary(uniqueKeysWithValues: document.weeks.map { ($0.startKey, $0) })
        for offset in -8...8 {
            guard let date = document.calendar.date(byAdding: .weekOfYear, value: offset, to: referenceDate) else { continue }
            let key = PlanningDate.weekKey(date, calendar: document.calendar)
            if choices[key] == nil { choices[key] = DatedPlanningWeek.make(for: date, calendar: document.calendar) }
        }
        return choices.values.sorted { $0.startKey < $1.startKey }
    }


    ///
    /// @fcn        PlanningWeekSelector.monthDays
    /// @brief      Create a six-week calendar selection grid
    /// @details    Begins at the calendar week containing the month's first day and returns up to forty-two dates;
    ///             unavailable boundaries yield an empty grid.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     ([Date]) six-week grid dates starting at the week containing the month's first day
    ///
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


    ///
    /// @fcn        PlanningWeekSelector.changeMonth
    /// @brief      Move the selector's reference month
    /// @details    Calculates from the first day of the displayed month to avoid drift from differing month lengths.
    ///
    /// @param[in]  amount  Signed calendar-month offset
    ///
    /// @return     (Void) no return value
    ///
    private func changeMonth(_ amount: Int) {
        if let first = document.calendar.dateInterval(of: .month, for: referenceDate)?.start,
           let next = document.calendar.date(byAdding: .month, value: amount, to: first) { referenceDate = next }
    }


    ///
    /// @fcn        PlanningWeekSelector.select
    /// @brief      Confirm one calendar date and its containing week
    /// @details    Prevents duplicate selection, briefly updates the highlighted choice with Reduce Motion support,
    ///             then invokes the callback and dismisses.
    ///
    /// @param[in]  date  Represented date for the operation
    ///
    /// @return     (Void) no return value
    ///
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
            ScrollView {
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
                                    let count = PlanningCalendarContent.items(on: date, document: document, sources: sources).count
                                    Button { select(date) } label: {
                                        VStack(spacing: 2) {
                                            Text(String(document.calendar.component(.day, from: date)))
                                                .font(.body.weight(selected ? .semibold : .regular))
                                                .foregroundStyle(selected ? Color.white : (inMonth ? Color.primary : Color.secondary))
                                            Circle()
                                                .fill(count > 0 ? (selected ? Color.white : Color.blue) : Color.clear)
                                                .frame(width: 5, height: 5)
                                                .accessibilityHidden(true)
                                        }
                                        .frame(width: 36, height: 44)
                                        .background(selected ? Color.blue : Color.clear, in: Circle())
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())), \(count) items")
                                    .accessibilityHint("Show the week containing this day")
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                            .background(highlighted ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color.blue).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text("Items planned or scheduled").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Tap any day to show its week.").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
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


    ///
    /// @fcn        PlanningDaySelection.resolve
    /// @brief      Resolve an active day-list navigation target
    /// @details    Normalizes the day and uses a retained or unsaved week; returns nil if the day mapping does not
    ///             identify an active list.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  document  Retained document containing the operation's current workspace records
    ///
    /// @return     (Self?) normalized date, containing week, and active day-list ID, or nil if mapping fails
    ///
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


    ///
    /// @fcn        PlanningDaySelector.init
    /// @brief      Seed a day chooser with its initial date
    /// @details    Retains the date-selection callback and stores the initial date as editable local state.
    ///
    /// @param[in]  initialDate  Date initially selected when the view opens
    /// @param[in]  onSelect     Callback invoked after the user confirms a selection
    ///
    /// @return     (PlanningDaySelector) initialized instance
    ///
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


    ///
    /// @fcn        PlanningSelectedDayView.init
    /// @brief      Initialize navigation and editing for a selected calendar day
    /// @details    Retains the resolved selection and return callbacks and seeds the working week from the selection
    ///             snapshot.
    ///
    /// @param[in]  selection               Text selection or resolved navigation selection to retain
    /// @param[in]  currentUserName         Display name used in the selected-day interface
    /// @param[in]  returnDestinationTitle  Accessible title describing the destination reached by Back
    /// @param[in]  onClose                 Action used to leave the selected-day presentation
    /// @param[in]  onSelectDay             Callback for changing the represented calendar day
    ///
    /// @return     (PlanningSelectedDayView) initialized instance
    ///
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
            .modifier(OwnerImportanceControls(ownerID: week.id))
            .environment(\.planningDisplayedWeekKey, week.startKey)
            .task {
                guard let access, access.document.week(for: selection.date) == nil else { return }
                do {
                    let prepared = try PlanningRoutineStore.newWeek(for: selection.date, calendar: access.document.calendar)
                    guard access.saveWeek(prepared) else { onClose(); return }
                    isRevertingEdit = true
                    week = prepared
                } catch {
                    DatabaseActivity.shared.report("Could not create this day from its week template. Your saved plans were retained.")
                    onClose()
                }
            }
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


    ///
    /// @fcn        FullMonthExampleStore.live
    /// @brief      Locate the application's live example backup directories
    /// @details    Resolves the Library, Documents, and Application Support locations and uses the application's
    ///             preferences domain for backup and restoration.
    ///
    /// @return     (FullMonthExampleStore) constructed value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        FullMonthExampleStore.committedOperation
    /// @brief      Read the completed dataset-switch marker
    /// @details    Returns the marker text when readable and nil when no readable commit marker exists.
    ///
    /// @return     (String?) readable committed-operation marker, or nil if unavailable
    ///
    private func committedOperation() -> String? {
        try? String(contentsOf: transition.appendingPathComponent("Committed"), encoding: .utf8)
    }


    ///
    /// @fcn        FullMonthExampleStore.digest
    /// @brief      Hash a backup file without loading it entirely into memory
    /// @details    Streams the file in one-megabyte chunks through SHA-256 and closes the handle even if reading
    ///             fails.
    ///
    /// @param[in]  url  File URL for the requested audio resource
    ///
    /// @return     (String) lowercase hexadecimal SHA-256 digest of the file's bytes
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    private func digest(_ url: URL) throws -> String {
        // Stream large attachments rather than loading an entire video into memory.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }


    ///
    /// @fcn        FullMonthExampleStore.hashes
    /// @brief      Build a relative-path checksum inventory of a backup
    /// @details    Enumerates regular files, rejects symbolic links, and propagates enumeration and file-reading
    ///             failures.
    ///
    /// @param[in]  directory  Backup directory to enumerate, decode, or verify
    ///
    /// @return     ([String: String]) relative file paths mapped to their SHA-256 checksums
    /// @throws     Explicit failures include `CocoaError(.fileReadUnknown)`,
    ///             `CocoaError(.fileReadUnsupportedScheme)`, `enumerationError`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        FullMonthExampleStore.verify
    /// @brief      Validate a backup before installation or recovery
    /// @details    Requires the supported manifest version, matching file checksums, and a readable saved preferences
    ///             dictionary.
    ///
    /// @param[in]  directory  Backup directory to enumerate, decode, or verify
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    private func verify(_ directory: URL) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("Manifest.json")))
        guard manifest.version == 1, try hashes(in: directory) == manifest.hashes else { throw CocoaError(.fileReadCorruptFile) }
        _ = try savedDomain(in: directory)
    }


    ///
    /// @fcn        FullMonthExampleStore.savedDomain
    /// @brief      Decode the backed-up application preferences domain
    /// @details    Reads Defaults.plist and requires a string-keyed property-list dictionary; other contents are
    ///             treated as corrupt.
    ///
    /// @param[in]  directory  Backup directory to enumerate, decode, or verify
    ///
    /// @return     ([String: Any]) decoded string-keyed application preferences dictionary
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    private func savedDomain(in directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("Defaults.plist"))
        guard let domain = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return domain
    }


    ///
    /// @fcn        FullMonthExampleStore.capture
    /// @brief      Capture a verified snapshot of files and preferences
    /// @details    Builds the snapshot in a temporary staging directory, synchronizes preferences, and retains
    ///             cleanup for failures before publishing the backup.
    ///
    /// @param[in]  destination  Backup destination directory for the verified snapshot
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        FullMonthExampleStore.setDomain
    /// @brief      Replace and verify the application preferences domain
    /// @details    Synchronizes after writing and compares the stored dictionary with the requested value; a failed
    ///             write or mismatch throws.
    ///
    /// @param[in]  domain  Complete application preferences dictionary to install and verify
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileWriteUnknown)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    private func setDomain(_ domain: [String: Any]) throws {
        defaults.setPersistentDomain(domain, forName: domainName)
        guard defaults.synchronize(), NSDictionary(dictionary: defaults.persistentDomain(forName: domainName) ?? [:]).isEqual(to: domain) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }


    ///
    /// @fcn        FullMonthExampleStore.installFiles
    /// @brief      Install backed-up Documents and Application Support trees
    /// @details    Copies each immutable snapshot tree through staging before replacing its live directory, allowing
    ///             interrupted installation to be retried from the snapshot.
    ///
    /// @param[in]  snapshot  Snapshot values or directory used for the operation
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        FullMonthExampleStore.finishCommitted
    /// @brief      Clean up a successfully committed dataset transition
    /// @details    Removes the retained user backup after a completed restore and deletes the transition directory.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    private func finishCommitted() throws {
        if committedOperation() == "restore", fm.fileExists(atPath: userData.path) { try fm.removeItem(at: userData) }
        try fm.removeItem(at: transition)
    }


    ///
    /// @fcn        FullMonthExampleStore.recoverInterruptedSwitch
    /// @brief      Recover or finish an interrupted dataset transition
    /// @details    Finishes committed cleanup or verifies and reinstalls the transition snapshot and preferences
    ///             before removing its journal directory.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    /// @note       Run before constructing any view or loading any saved model after an interrupted switch.
    ///
    func recoverInterruptedSwitch() throws {
        guard fm.fileExists(atPath: transition.path) else { return }
        if committedOperation() != nil { try finishCommitted(); return }
        try verify(transition)
        try installFiles(from: transition)
        try setDomain(savedDomain(in: transition))
        try fm.removeItem(at: transition)
    }


    ///
    /// @fcn        FullMonthExampleStore.loadExample
    /// @brief      Load the full-month example while retaining user data
    /// @details    Recovers interrupted work first, captures the original user backup only when absent, verifies it,
    ///             and journals the preferences switch before marking it committed.
    ///
    /// @param[in]  example  Bundled example content or dataset to use
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        FullMonthExampleStore.restoreUserData
    /// @brief      Restore the verified original user dataset
    /// @details    Requires a retained backup, journals the current state, reinstalls files and preferences, and
    ///             attempts transition recovery if installation fails.
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileNoSuchFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
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


    ///
    /// @fcn        FullMonthExample.make
    /// @brief      Create a full month of calendar-backed demonstration content
    /// @details    Builds dated weeks and examples around the reference month using the supplied calendar, with
    ///             deterministic relationships among their lists and cards.
    ///
    /// @param[in]  now       Reference time used instead of an implicit clock read
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (FullMonthExample) constructed value
    ///
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
            if let bookmark = week.collection.lists[index].cards.first(where: { !$0.isTitleChecked && $0.dueDateKind == .date && !$0.isSectionDivider }) {
                week.collection.savedCardIDs.insert(bookmark.id)
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


    ///
    /// @fcn        FullMonthExample.defaultsDomain
    /// @brief      Build the example dataset's preferences dictionary
    /// @details    Encodes the generated calendar, collections, bookmarks, and importance data while retaining
    ///             platform preferences, Focus choices, and the user's optional lower-corner Back setting.
    ///
    /// @param[in]  original  Original preferences domain retained for comparison or transformation
    ///
    /// @return     ([String: Any]) preferences domain containing the generated example and supported preserved
    ///             choices
    /// @throws     Explicit failures include `CocoaError(.coderInvalidValue)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    func defaultsDomain(preserving original: [String: Any]) throws -> [String: Any] {
        guard let current = document.weeks.first(where: { $0.startKey == document.currentWeekKey }) else { throw CocoaError(.coderInvalidValue) }
        // Keep non-Plenact platform preferences; all app-owned data/settings remain in the backup.
        var result = original.filter { !$0.key.hasPrefix("Plenact.") }
        let encoder = JSONEncoder()
        result[PlanningCalendarStore.key] = try encoder.encode(document)
        result["Plenact.Board.v1"] = try encoder.encode(current.collection.lists)
        result["Plenact.PersonalCollections.v1"] = try encoder.encode(collections)
        result["Plenact.SavedCardIDs.v1"] = Array(current.collection.savedCardIDs).sorted()
        var importance = LibraryImportanceSelection.demoData(in: document.weeks.map(\.collection) + collections)
        for week in document.weeks {
            for list in week.collection.lists {
                if let card = list.cards.first(where: { !$0.isTitleChecked && $0.displayFormat == .card }) {
                    importance = LibraryImportanceSelection.setting(cardID: card.id, collectionID: week.id, marked: true, data: importance)
                }
            }
        }
        result[LibraryImportanceSelection.key] = importance
        let savedPreferences = (original[PlanPreferencesStore.key] as? Data).flatMap {
            try? JSONDecoder().decode(LocalProfilePreferences.self, from: $0)
        } ?? (original[LocalProfileStore.storageKey] as? Data).flatMap {
            try? JSONDecoder().decode(LocalProfile.self, from: $0)
        }?.preferences
        if let existing = savedPreferences {
            var preferences = LocalProfilePreferences()
            preferences.enablesLowerCornerBack = existing.enablesLowerCornerBack
            preferences.importanceStarStyle = existing.importanceStarStyle
            preferences.todayFocusIncludesImportant = existing.todayFocusIncludesImportant
            preferences.todayFocusIncludesBookmarked = existing.todayFocusIncludesBookmarked
            preferences.todayFocusIncludesUpNext = existing.todayFocusIncludesUpNext
            preferences.todayFocusHidesCompleted = existing.todayFocusHidesCompleted
            preferences.todayFocusGroupsBySection = existing.todayFocusGroupsBySection
            preferences.todayFocusOrder = existing.todayFocusOrder
            preferences.todayFocusItemCount = existing.todayFocusItemCount
            result[PlanPreferencesStore.key] = try encoder.encode(preferences)
        }
        result[TodayListPins.key] = TodayListPins.encode(collections.map { WorkspaceListReference(ownerID: $0.id, listID: $0.lists[0].id) })
        return result
    }
}
