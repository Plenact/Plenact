// --------------------------------------------------------------------------------------------------
// @file       CalendarModels.swift
// @brief      Dated Week ownership and stable local calendar keys
// @details    Keeps represented dates, owner identities, List mappings, and recognized migration
//             rules separate from Library directory records.
//
// --------------------------------------------------------------------------------------------------
import CryptoKit
import SwiftUI


///
/// Provides stable local planning date conventions
///
/// @section    Purpose
///     Formats and resolves local date and Week keys using explicit calendar context rather than
///     shifted timestamp identities.
///
enum PlanningDate
{


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
    static func listTitle(_ title: String, on date: Date, now: Date = .now, calendar: Calendar = .current) -> String
    {

        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let suffix =
        year == calendar.component(.year, from: now)
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
    static func key(_ date: Date, calendar: Calendar = .current) -> String
    {

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
    static func date(_ key: String, calendar: Calendar = .current) -> Date?
    {

        let parts = key.split(separator: "-").compactMap
        {
            Int($0)
        }

        guard parts.count == 3 else
        {
            return nil
        }

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
    static func weekKey(_ date: Date, calendar: Calendar = .current) -> String
    {

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
    static func days(in weekKey: String, calendar: Calendar = .current) -> [Date]
    {

        guard let start = date(weekKey, calendar: calendar) else
        {
            return []
        }

        return (0 ..< 7).compactMap
        {
            calendar.date(byAdding: .day, value: $0, to: start)
        }

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
    static func weekdayTitle(_ date: Date, calendar: Calendar = .current) -> String
    {

        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"] [
        calendar.component(.weekday, from: date) - 1]
    }

}


///
/// Represents a calendar Week and its dated List mapping
///
/// @section    Purpose
///     Retains collection ownership, date keys, and explicit-save state so day navigation remains
///     independent of numeric List IDs.
///
struct DatedPlanningWeek: Identifiable, Hashable, Codable
{


    var startKey:        String
    var collection:      PersonalCollection
    var dayListIDs:      [String: Int]
    var explicitlySaved: Bool = false
    var id:              UUID
    {
        collection.id
    }

    var hasContent: Bool
    {
        collection.lists.contains
        {
            !$0.allCards.isEmpty
        }

    }

    var rangeTitle: String
    {

        let days = PlanningDate.days(in: startKey)
        guard let first = days.first, let last = days.last else
        {
            return startKey
        }

        return
                        "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    var compactRangeTitle: String
    {

        let days = PlanningDate.days(in: startKey)
        guard let first = days.first, let last = days.last else
        {
            return startKey
        }

        let calendar = Calendar.current
        let firstYear = calendar.component(.year, from: first)
        let lastYear = calendar.component(.year, from: last)
        let firstLabel = first.formatted(.dateTime.month(.abbreviated).day())
        let lastLabel = last.formatted(.dateTime.month(.abbreviated).day())
        let yearSuffix = String(format: "%02d", lastYear % 100)
        if firstYear != lastYear
        {

            return "\(firstLabel) '\(String(format: "%02d", firstYear % 100))-\(lastLabel) '\(yearSuffix)"
        }

        if calendar.component(.month, from: first) == calendar.component(.month, from: last)
        {

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
    func list(on date: Date) -> KanbanList?
    {

        guard let id = dayListIDs[PlanningDate.key(date)] else
        {
            return nil
        }

        return collection.lists.first
        {
            $0.id == id && !$0.isArchived
        }

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
    mutating func prepareDay(_ date: Date) -> Int
    {

        if let existing = list(on: date)
        {
            return existing.id
        }

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
    static func make(
        for date: Date, lists: [KanbanList]? = nil, saved: Set<Int> = [],
        calendar: Calendar = .current
    ) -> Self
    {

        let start = PlanningDate.weekKey(date, calendar: calendar)
        var collection = PersonalCollection(title: "Week of \(start)", kind: .board)
        collection.lists = lists ?? []
        collection.savedCardIDs = saved
        var dayIDs: [String: Int] = [:]
        for day in PlanningDate.days(in: start, calendar: calendar)
        {

            let title = PlanningDate.weekdayTitle(day, calendar: calendar)
            if let list = collection.lists.first(where:
                {

                    !$0.isArchived && $0.title.caseInsensitiveCompare(title) == .orderedSame
                })
            {

                dayIDs[PlanningDate.key(day, calendar: calendar)] = list.id
            }
            else
            {

                let id = (collection.lists.map(\.id).max() ?? -1) + 1
                collection.lists.append(KanbanList(id: id, title: title, cards: []))
                dayIDs[PlanningDate.key(day, calendar: calendar)] = id
            }

        }

        return Self(startKey: start, collection: collection, dayListIDs: dayIDs)
    }

}


///
/// Retains calendar Weeks independently of the Library directory
///
/// @section    Purpose
///     Keeps the current Week key, calendar conventions, and dated owner snapshots available for
///     validation and migration.
///
struct PlanningCalendarDocument: Hashable, Codable
{


    var version = 1
    var currentWeekKey:     String
    var firstWeekday:       Int = Calendar.current.firstWeekday
    var weeks:              [DatedPlanningWeek]
    var checklistLinkWeeks: [UUID: UUID]? = nil
    var calendar:           Calendar
    {

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
    func week(for date: Date, calendar: Calendar? = nil) -> DatedPlanningWeek?
    {

        weeks.first
        {
            $0.startKey == PlanningDate.weekKey(date, calendar: calendar ?? self.calendar)
        }

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
    mutating func upsert(_ week: DatedPlanningWeek)
    {

        if let index = weeks.firstIndex(where:
            {
                $0.startKey == week.startKey
            })
        {

            weeks[index] = week
        }
        else
        {

            weeks.append(week)
        }

        weeks.sort
        {
            $0.startKey < $1.startKey
        }

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
    mutating func rollForward(
        to date: Date, currentLists: [KanbanList], saved: Set<Int>,
        calendar suppliedCalendar: Calendar? = nil, newWeek: DatedPlanningWeek? = nil
    ) -> DatedPlanningWeek
    {

        let calendar = suppliedCalendar ?? self.calendar
        if var previous = weeks.first(where:
            {
                $0.startKey == currentWeekKey
            })
        {

            previous.collection.lists = currentLists
            previous.collection.savedCardIDs = saved
            upsert(previous)
        }

        let key = PlanningDate.weekKey(date, calendar: calendar)
        let next =
        weeks.first
        {
            $0.startKey == key
        }
        ?? newWeek ?? DatedPlanningWeek.make(for: date, calendar: calendar)
        upsert(next)
        currentWeekKey = key
        return next
    }

}


///
/// Repairs and migrates retained calendar layout conventions
///
/// @section    Purpose
///     Applies recognized legacy weekday mappings while preserving source identities and
///     date-qualified ownership.
///
extension PlanningCalendarDocument
{


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
    mutating func repairLegacyMondayFirstLayout(now: Date = .now) throws -> Bool
    {

        guard firstWeekday == 1,
        let current = weeks.first(where:
            {
                $0.startKey == currentWeekKey
            })
        else
        {
            return false
        }

        let dated = current.collection.lists.filter
        {
            list in
            !list.isArchived && current.dayListIDs.values.contains(list.id)
        }

        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        guard dated.map(\.title) == names,
        let monday = current.dayListIDs.first(where:
            {
                $0.value == dated[0].id
            })?.key,
        let sunday = current.dayListIDs.first(where:
            {
                $0.value == dated[6].id
            })?.key,
        sunday < monday
        else
        {
            return false
        }

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
    mutating func changeFirstWeekday(to weekday: Int, now: Date = .now) throws
    {

        guard weekday == 1 || weekday == 2 else
        {
            throw CocoaError(.validationMissingMandatoryProperty)
        }

        guard weekday != firstWeekday else
        {
            return
        }

        let oldCalendar = calendar
        var newCalendar = calendar
        newCalendar.firstWeekday = weekday
        let sources = weeks.sorted
        {

            if ($0.startKey == currentWeekKey) != ($1.startKey == currentWeekKey)
            {

                return $0.startKey == currentWeekKey
            }

            return $0.startKey < $1.startKey
        }

        var rebuilt: [String: DatedPlanningWeek] = [:]
        var cardIDs: [UUID: [Int: Int]] = [:]
        var usedCardIDs = Set<Int>()
        var nextCardID = (weeks.flatMap
            {
                $0.collection.lists.flatMap(\.allCards)
            } .map(\.id).max() ?? -1) + 1
        // Globally distinct IDs prevent a link from resolving to an unrelated card after a split.
        for source in sources
        {

            var mapping: [Int: Int] = [:]
            for card in source.collection.lists.flatMap(\.allCards)
            {

                let id: Int
                if usedCardIDs.insert(card.id).inserted
                {

                    id = card.id
                }
                else
                {

                    id = nextCardID;
                    nextCardID += 1;
                    usedCardIDs.insert(id)
                }

                mapping[card.id] = id
            }

            cardIDs[source.id] = mapping
            guard let middle = PlanningDate.days(in: source.startKey, calendar: oldCalendar).dropFirst(3).first else
            {

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

        for source in sources
        {

            let middle = PlanningDate.days(in: source.startKey, calendar: oldCalendar) [3]
            let ownerKey = PlanningDate.weekKey(middle, calendar: newCalendar)
            for list in source.collection.lists
            {

                let dateKey = source.dayListIDs.first
                {
                    $0.value == list.id
                }?.key
                let date = dateKey.flatMap
                {
                    PlanningDate.date($0, calendar: oldCalendar)
                }

                let key = date.map
                {
                    PlanningDate.weekKey($0, calendar: newCalendar)
                }
                ?? ownerKey
                var target = rebuilt[key] ?? DatedPlanningWeek.make(for: date ?? middle, calendar: newCalendar)
                // A new boundary week starts empty; weekday panels are filled after migration.
                if rebuilt[key] == nil
                {
                    target.collection.lists = [];
                    target.dayListIDs = [:]
                }

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
                func relocated(_ card: KanbanCard) -> KanbanCard
                {

                    var result = card.replacingLocation(id: mapping[card.id]!, listTitle: list.title)
                    result.checklists = card.checklists.map
                    {
                        checklist in
                        let items = checklist.items.map
                        {
                            item in
                            var item = item
                            let owner = checklistLinkWeeks? [item.id] ?? item.linkedCollectionID ?? source.id
                            if let retained = item.retainedCardID, let replacement = cardIDs[owner]? [retained]
                            {

                                item.retainedCardID = replacement
                            }

                            if case .linkedCard(let id) = item.content
                            {

                                if let replacement = cardIDs[owner]? [id]
                                {

                                    item.content = .linkedCard(cardID: replacement)
                                }

                            }

                            return item
                        }

                        return KanbanChecklist(
                            id: checklist.id, title: checklist.title, items: items,
                            completedItemIndices: checklist.completedItemIndices)
                    }

                    return result
                }

                var moved = KanbanList(
                    id: listID, title: list.title, cards: list.cards.map(relocated),
                    archivedCards: list.archivedCards.map(relocated), newItemPresentation: list.newItemPresentation)
                moved.subtitleOverride = list.subtitleOverride
                moved.appearance = list.appearance
                moved.isArchived = list.isArchived
                target.collection.lists.append(moved)
                for card in list.allCards where source.collection.savedCardIDs.contains(card.id)
                {

                    target.collection.savedCardIDs.insert(mapping[card.id]!)
                }

                if let dateKey
                {
                    target.dayListIDs[dateKey] = listID
                }

                rebuilt[key] = target
            }

        }

        let currentKey = PlanningDate.weekKey(now, calendar: newCalendar)
        if rebuilt[currentKey] == nil
        {
            rebuilt[currentKey] = DatedPlanningWeek.make(for: now, calendar: newCalendar)
        }

        for key in Array(rebuilt.keys)
        {

            var week = rebuilt[key]!
            for date in PlanningDate.days(in: key, calendar: newCalendar)
            where week.dayListIDs[PlanningDate.key(date)] == nil
            {

                _ = week.prepareDay(date)
            }

            let datesByID = Dictionary(uniqueKeysWithValues: week.dayListIDs.map
                {
                    ($0.value, $0.key)
                })
            week.collection.lists = week.collection.lists.enumerated().sorted
            {
                lhs, rhs in
                switch (datesByID[lhs.element.id], datesByID[rhs.element.id])
                {

                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.offset < rhs.offset
                }

            } .map(\.element)
            rebuilt[key] = week
        }

        // Keep checklist links navigable when their two dated lists now belong to different weeks.
        let cardOwners = Dictionary(
            uniqueKeysWithValues: rebuilt.values.flatMap
            {
                week in
                week.collection.lists.flatMap(\.allCards).map
                {
                    ($0.id, week.id)
                }

            })
        var linkWeeks: [UUID: UUID] = [:]
        for week in rebuilt.values
        {

            for card in week.collection.lists.flatMap(\.allCards)
            {

                for item in card.checklists.flatMap(\.items)
                {

                    if case .linkedCard(let cardID) = item.content,
                    let owner = cardOwners[cardID], owner != week.id
                    {

                        linkWeeks[item.id] = owner
                    }

                }

            }

        }

        let sourceWeekIDs = Set(sources.map(\.id))
        for key in Array(rebuilt.keys)
        {

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
            func preservingOwners(_ card: KanbanCard) -> KanbanCard
            {

                var card = card
                card.checklists = card.checklists.map
                {
                    checklist in
                    let items = checklist.items.map
                    {
                        original in
                        var item = original
                        if let id = item.retainedCardID,
                        item.linkedCollectionID == nil || sourceWeekIDs.contains(item.linkedCollectionID!),
                        let owner = cardOwners[id]
                        {

                            item.linkedCollectionID = owner
                        }

                        return item
                    }

                    return KanbanChecklist(
                        id: checklist.id, title: checklist.title, items: items,
                        completedItemIndices: checklist.completedItemIndices)
                }

                return card
            }

            for index in week.collection.lists.indices
            {

                week.collection.lists[index].cards = week.collection.lists[index].cards.map(preservingOwners)
                week.collection.lists[index].archivedCards = week.collection.lists[index].archivedCards.map(
                    preservingOwners)
            }

            rebuilt[key] = week
        }

        checklistLinkWeeks = linkWeeks.isEmpty ? nil : linkWeeks
        firstWeekday = weekday
        currentWeekKey = currentKey
        weeks = rebuilt.values.sorted
        {
            $0.startKey < $1.startKey
        }

    }

}


///
/// Identifies a live workspace Card search match
///
/// @section    Purpose
///     Carries owner, List, and optional Week provenance alongside the canonical Card so navigation
///     avoids local-ID collisions.
///
struct PlanningSearchResult: Identifiable, Hashable
{


    let weekKey:         String?
    let collectionID:    UUID
    let collectionTitle: String
    let listID:          Int
    let listTitle:       String
    let card:            KanbanCard
    var id:              String
    {
            "\(collectionID):\(card.id)"
    }

}


///
/// Defines shared calendar content membership rules
///
/// @section    Purpose
///     Keeps calendar day indicators and Week chooser summaries consistent about which retained
///     items count as content.
///
enum PlanningCalendarContent
{


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
    static func items(on date: Date, document: PlanningCalendarDocument, sources: [PlanningSearchResult])
    -> [PlanningSearchResult]
    {

        let calendar = document.calendar
        let week = document.week(for: date)
        let listID = week?.list(on: date)?.id
        return sources.filter
        {
            item in
            let planned =
            week.map
            {
                item.weekKey == $0.startKey && item.collectionID == $0.id && item.listID == listID
            }
            ?? false
            let scheduled = [
                item.card.startDateKind.includesDate ? item.card.startDate : nil,
                item.card.dueDateKind.includesDate ? item.card.dueDate : nil
            ]
            .compactMap
            {
                $0
            } .contains
            {
                calendar.isDate($0, inSameDayAs: date)
            }

            return planned || scheduled
        }

    }

}
