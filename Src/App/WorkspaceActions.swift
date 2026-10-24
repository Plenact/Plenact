// --------------------------------------------------------------------------------------------------
// @file       WorkspaceActions.swift
// @brief      Calendar ownership and checked workspace operations
// @details    Coordinates Week changes, owner-qualified transfers, review decisions, and checked
//             persistence without copying state into a second owner.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// AppRootView behavior grouped separately from stored view state
///
/// @section    Purpose
///     Keep owner-scoped operations with the existing view while retaining its state and lifecycle.
///
extension AppRootView
{


    ///
    /// @fcn        AppRootView.setPlanningFirstWeekday
    /// @brief      Save a supported planning week-start change
    /// @details    Uses calendar migration and checked persistence before publishing the regrouped workspace; returns
    ///             false with feedback when the change fails.
    ///
    /// @param[in]  weekday  Requested supported planning week-start value
    ///
    /// @return     (Bool) true when the week-start change is accepted; false when checked migration or saving fails
    ///
    func setPlanningFirstWeekday(_ weekday: Int) -> Bool
    {

        guard let previous = calendarDocument else
        {
            return false
        }

        guard previous.firstWeekday != weekday else
        {
            return true
        }

        var updated = previous
        if var current = updated.weeks.first(where:
            {
                $0.startKey == updated.currentWeekKey
            })
        {

            current.collection.lists = lists
            current.collection.savedCardIDs = savedCardIDs
            updated.upsert(current)
        }

        do
        {

            try updated.changeFirstWeekday(to: weekday)
            let current = updated.weeks.first
            {
                $0.startKey == updated.currentWeekKey
            }!
            try PlanningCalendarStore.save(updated)
            do
            {
                try KanbanBoardPersistence.saveListsChecked(current.collection.lists)
            }
            catch
            {

                try PlanningCalendarStore.save(previous);
                throw error
            }

            calendarDocument = updated
            lists = current.collection.lists
            savedCardIDs = current.collection.savedCardIDs
            SavedCardPersistence.save(savedCardIDs)
            boardTargetListID = nil;
            boardTargetCardID = nil
            weekRootRequest += 1
            return true
        }
        catch
        {

            DatabaseActivity.shared.report(
                                    "Could not change the start of the week: \(error.localizedDescription) Your plans have been retained.")
            return false
        }

    }


    ///
    /// @fcn        AppRootView.applyExampleCardLocations
    /// @brief      Publish the one-time requested Gym and Work destination additions
    /// @details    Runs only after the calendar loads. Existing custom and protected locations
    ///             remain intact; failed preparation or storage leaves live state unchanged.
    /// @return     (Void) publishes the saved update or reports its persistence error
    ///
    func applyExampleCardLocations()
    {

        guard hasLoadedBoard, let document = calendarDocument else
        {

            return
        }

        do
        {

            guard let updated = try ExampleCardLocations.applyOnce(
                lists: lists, calendar: document, collections: collections) else
            {

                return
            }

            calendarDocument = updated.calendar
            lists = updated.lists
            collections = updated.collections
        }

        catch
        {

            DatabaseActivity.shared.report("Could not add example Card locations: \(error.localizedDescription)")
        }

    }


    ///
    /// @fcn        AppRootView.applyDayListOrderingPreference
    /// @brief      Apply the enabled Day time-order policy to existing calendar weeks
    /// @details    Called after loading and when preferences change. Sorts only active date-mapped
    ///             Lists, saves before publishing the new snapshots, and leaves personal Lists intact.
    /// @return     (Void) publishes persisted chronological Day contents or reports a save failure
    ///
    func applyDayListOrderingPreference()
    {
        guard hasLoadedBoard, PlanPreferencesStore.load().keepsDayListsInTimeOrder,
              var document = calendarDocument else
        {
            return
        }
        var currentLists = lists
        for index in document.weeks.indices
        {
            let week = document.weeks[index]
            let source = week.startKey == document.currentWeekKey ? lists : week.collection.lists
            let ordered = DayListTimeOrder.lists(
                source, dayListIDs: Set(week.dayListIDs.values), calendar: document.calendar)
            document.weeks[index].collection.lists = ordered
            if week.startKey == document.currentWeekKey
            {
                currentLists = ordered
            }
        }
        guard document != calendarDocument || currentLists != lists else
        {
            return
        }
        do
        {
            try PlanningCalendarStore.save(document)
            try KanbanBoardPersistence.saveListsChecked(currentLists)
            calendarDocument = document
            lists = currentLists
            if let displayed = displayedPlanningWeek
            {
                displayedPlanningWeek = document.weeks.first
                {
                    $0.id == displayed.id
                }
            }
        }
        catch
        {
            DatabaseActivity.shared.report(error.localizedDescription)
        }
    }


    ///
    /// @fcn        AppRootView.persistCurrentPlanningWeek
    /// @brief      Persist the current week's live lists and bookmarks
    /// @details    Updates the retained calendar from the current workspace and reports save failures through
    ///             database activity.
    ///
    /// @return     (Void) no return value
    ///
    func persistCurrentPlanningWeek()
    {

        guard hasLoadedBoard, var document = calendarDocument,
        var current = document.weeks.first(where:
            {
                $0.startKey == document.currentWeekKey
            })
        else
        {
            return
        }

        current.collection.lists = lists
        current.collection.savedCardIDs = savedCardIDs
        // If a weekday was archived/deleted, its replacement receives the date association.
        for date in PlanningDate.days(in: current.startKey) where current.list(on: date) == nil
        {

            if let replacement = TodayListSelection.currentDayList(in: lists, date: date)
            {

                current.dayListIDs[PlanningDate.key(date)] = replacement.id
            }

        }

        if PlanPreferencesStore.load().keepsDayListsInTimeOrder
        {
            let ordered = DayListTimeOrder.lists(
                lists, dayListIDs: Set(current.dayListIDs.values), calendar: document.calendar)
            if ordered != lists
            {
                lists = ordered
            }
        }
        current.collection.lists = lists

        document.upsert(current)
        guard document != calendarDocument else
        {
            return
        }

        do
        {
            try PlanningCalendarStore.save(document);
            calendarDocument = document
        }
        catch
        {

            DatabaseActivity.shared.report("Could not save calendar weeks: \(error.localizedDescription)")
        }

    }


    ///
    /// @fcn        AppRootView.advancePlanningWeekIfNeeded
    /// @brief      Advance the live workspace when the calendar week changes
    /// @details    Retains the outgoing week and uses existing or default-template content for the incoming week
    ///             before publishing its lists and markers.
    ///
    /// @return     (Void) no return value
    ///
    func advancePlanningWeekIfNeeded()
    {

        guard !isSwitchingWorkspace, hasLoadedBoard, var document = calendarDocument,
        document.currentWeekKey != PlanningDate.weekKey(.now, calendar: document.calendar)
        else
        {
            return
        }

        do
        {

            let newWeek =
            document.week(for: .now) == nil
            ? try PlanningRoutineStore.newWeek(for: .now, calendar: document.calendar) : nil
            let next = document.rollForward(to: .now, currentLists: lists, saved: savedCardIDs, newWeek: newWeek)
            let importantIDs =
            newWeek == nil
            ? Set<Int>() : try PlanningRoutineStore.newWeekImportantIDs(for: .now, calendar: document.calendar)
            var importance = UserDefaults.standard.data(forKey: LibraryImportanceSelection.key) ?? Data()
            if !importantIDs.isEmpty && !importance.isEmpty
            {

                _ = try JSONDecoder().decode([LibraryRecentItem].self, from: importance)
            }

            for id in importantIDs
            {

                importance = LibraryImportanceSelection.settingLevel(
                    cardID: id, collectionID: next.id,
                    level: LibraryImportanceSelection.demonstrationLevel(
                        for: next.collection.lists.flatMap(\.cards).first
                        {
                            $0.id == id
                        }?.word ?? ""), data: importance
                )
            }

            try DailyReviewTransaction.perform(additionalKeys: [LibraryImportanceSelection.key])
            {

                try PlanningCalendarStore.save(document)
                try KanbanBoardPersistence.saveListsChecked(next.collection.lists)
                SavedCardPersistence.save(next.collection.savedCardIDs)
                if !importantIDs.isEmpty
                {

                    UserDefaults.standard.set(importance, forKey: LibraryImportanceSelection.key)
                }

            }

            calendarDocument = document
            lists = next.collection.lists;
            savedCardIDs = next.collection.savedCardIDs
            boardTargetListID = nil;
            boardTargetCardID = nil
            weekRootRequest += 1
        }
        catch
        {
            DatabaseActivity.shared.report("Could not advance this week: \(error.localizedDescription)")
        }

    }


    ///
    /// @fcn        AppRootView.preparePlanningWeek
    /// @brief      Resolve a retained week or save a default-template week
    /// @details    Returns an existing matching week immediately; otherwise generates the configured routine and its
    ///             importance IDs and returns the new week only after checked saving succeeds.
    ///
    /// @param[in]  requested  Requested week snapshot to resolve or prepare
    ///
    /// @return     (DatedPlanningWeek?) retained or successfully prepared week, or nil if calendar access or
    ///             preparation fails
    ///
    func preparePlanningWeek(_ requested: DatedPlanningWeek) -> DatedPlanningWeek?
    {

        guard let document = calendarDocument else
        {
            return nil
        }

        if let existing = document.weeks.first(where:
            {
                $0.startKey == requested.startKey
            })
        {
            return existing
        }

        do
        {

            guard let date = PlanningDate.date(requested.startKey, calendar: document.calendar) else
            {
                return nil
            }

            let prepared = try PlanningRoutineStore.newWeek(for: date, calendar: document.calendar)
            let importantIDs = try PlanningRoutineStore.newWeekImportantIDs(for: date, calendar: document.calendar)
            return savePlanningWeek(prepared, exampleImportantIDs: importantIDs) ? prepared : nil
        }
        catch
        {

            DatabaseActivity.shared.report(
                                    "Could not prepare this week from its template. Your saved plans were retained.")
            return nil
        }

    }


    ///
    /// @fcn        AppRootView.savePlanningWeek
    /// @brief      Save a dated week and any explicit example importance
    /// @details    Uses a recoverable preferences transaction to update calendar-backed state and publishes the
    ///             current owner only after saving succeeds; the simple overload supplies no example markers.
    ///
    /// @param[in]  week  Dated planning week being inspected or saved
    ///
    /// @return     (Bool) true after the week and related marker changes save successfully; false on rejection
    ///
    func savePlanningWeek(_ week: DatedPlanningWeek) -> Bool
    {

        savePlanningWeek(week, exampleImportantIDs: [])
    }


    ///
    /// @fcn        AppRootView.savePlanningWeek
    /// @brief      Save a dated week and any explicit example importance
    /// @details    Uses a recoverable preferences transaction to update calendar-backed state and publishes the
    ///             current owner only after saving succeeds; the simple overload supplies no example markers.
    ///
    /// @param[in]  week                      Dated planning week being inspected or saved
    /// @param[in]  exampleImportantIDs       Destination card IDs explicitly marked important by an applied example
    /// @param[in]  replaceImportant          Whether the owner's existing importance selections should be replaced
    ///
    /// @param[in]  restoredImportanceLevels  Optional exact Card-to-level snapshot restored with
    ///             the Week, including levels above one
    ///
    /// @return     (Bool) true after the week and related marker changes save successfully; false on rejection
    ///
    func savePlanningWeek(
        _ week: DatedPlanningWeek, exampleImportantIDs: Set<Int>, replaceImportant: Bool = false,
        restoredImportanceLevels: [Int: Int]? = nil
    ) -> Bool
    {

        guard var document = calendarDocument else
        {
            return false
        }

        var week = week
        if PlanPreferencesStore.load().keepsDayListsInTimeOrder
        {
            week.collection.lists = DayListTimeOrder.lists(
                week.collection.lists, dayListIDs: Set(week.dayListIDs.values), calendar: document.calendar)
        }

        if let existing = document.weeks.first(where:
            {
                $0.startKey == week.startKey
            }), existing.id != week.id
        {

            return false
        }

        document.upsert(week)
        if document == calendarDocument && exampleImportantIDs.isEmpty && !replaceImportant
        {
            return true
        }

        do
        {

            let oldData = UserDefaults.standard.data(forKey: LibraryImportanceSelection.key) ?? Data()
            if (!exampleImportantIDs.isEmpty || replaceImportant) && !oldData.isEmpty
            {

                _ = try JSONDecoder().decode([LibraryRecentItem].self, from: oldData)
            }

            var importance = oldData
            if replaceImportant
            {

                for id in LibraryImportanceSelection.cardIDs(collectionID: week.id, data: importance)
                {

                    importance = LibraryImportanceSelection.setting(
                        cardID: id, collectionID: week.id, marked: false, data: importance)
                }

            }

            for id in exampleImportantIDs
            {

                importance = LibraryImportanceSelection.settingLevel(
                    cardID: id, collectionID: week.id,
                    level: restoredImportanceLevels? [id]
                    ?? LibraryImportanceSelection.demonstrationLevel(
                        for: week.collection.lists.flatMap(\.cards).first
                        {
                            $0.id == id
                        }?.word ?? ""),
                    data: importance)
            }

            try DailyReviewTransaction.perform(additionalKeys: [LibraryImportanceSelection.key])
            {

                try PlanningCalendarStore.save(document)
                if week.startKey == document.currentWeekKey
                {

                    try KanbanBoardPersistence.saveListsChecked(week.collection.lists)
                    SavedCardPersistence.save(week.collection.savedCardIDs)
                }

                if importance != oldData
                {

                    UserDefaults.standard.set(importance, forKey: LibraryImportanceSelection.key)
                }

            }

            calendarDocument = document
            if week.startKey == document.currentWeekKey
            {

                lists = week.collection.lists;
                savedCardIDs = week.collection.savedCardIDs
            }

            return true
        }
        catch
        {

            DatabaseActivity.shared.report(
                                    "Could not save this week: \(error.localizedDescription) Your content has been retained.")
            return false
        }

    }


    ///
    /// @fcn        AppRootView.sectionOwners
    /// @brief      Build the canonical owner set used for section movement
    /// @details    Combines personal collections and retained calendar weeks, substituting the current live week
    ///             values where needed.
    ///
    /// @param[in]  document  Retained document containing the operation's current workspace records
    ///
    /// @return     ([PersonalCollection]) personal and calendar owners with the live current-week values substituted
    ///
    func sectionOwners(in document: PlanningCalendarDocument) -> [PersonalCollection]
    {

        var document = document
        if let index = document.weeks.firstIndex(where:
            {
                $0.startKey == document.currentWeekKey
            })
        {

            document.weeks[index].collection.lists = lists
            document.weeks[index].collection.savedCardIDs = savedCardIDs
        }

        return collections + document.weeks.map(\.collection)
    }


    ///
    /// @fcn        AppRootView.saveSectionOwners
    /// @brief      Persist owners and metadata affected by a section transfer
    /// @details    Rebuilds calendar and personal-owner storage from the supplied working owners and writes the
    ///             related importance and daily-plan values through checked storage.
    ///
    /// @param[in]  owners      Canonical collection owners participating in the operation
    /// @param[in]  original    Original planning calendar document retained for comparison or transformation
    /// @param[in]  importance  Optional encoded owner-qualified importance selections to save
    /// @param[in]  dailyPlans  Optional encoded daily-plan document accompanying the workspace change
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    func saveSectionOwners(
        _ owners: [PersonalCollection], document original: PlanningCalendarDocument, importance: Data?,
        dailyPlans: Data?
    ) throws
    {

        var document = original
        for index in document.weeks.indices
        {

            if let owner = owners.first(where:
                {
                    $0.id == document.weeks[index].id
                })
            {

                document.weeks[index].collection = owner
            }

        }

        let libraryIDs = Set(collections.map(\.id))
        let library = owners.filter
        {
            libraryIDs.contains($0.id)
        }

        guard let current = document.weeks.first(where:
            {
                $0.startKey == document.currentWeekKey
            }) else
        {

            throw CocoaError(.fileReadCorruptFile)
        }

        _ = try PlanningCalendarStore.load()
        if let data = UserDefaults.standard.data(forKey: "Plenact.PersonalCollections.v1")
        {

            _ = try JSONDecoder().decode([PersonalCollection].self, from: data)
        }

        if let data = UserDefaults.standard.data(forKey: "Plenact.Board.v1")
        {

            _ = try JSONDecoder().decode([KanbanList].self, from: data)
        }

        try DailyReviewTransaction.perform(additionalKeys: [LibraryImportanceSelection.key])
        {

            try PlanningCalendarStore.save(document)
            try KanbanBoardPersistence.saveListsChecked(current.collection.lists)
            try PersonalCollectionStore.saveChecked(library)
            SavedCardPersistence.save(current.collection.savedCardIDs)
            if let importance
            {

                UserDefaults.standard.set(importance, forKey: LibraryImportanceSelection.key)
            }
            else
            {

                UserDefaults.standard.removeObject(forKey: LibraryImportanceSelection.key)
            }

            if let dailyPlans
            {

                UserDefaults.standard.set(dailyPlans, forKey: DailyPlanStore.key)
            }
            else
            {

                UserDefaults.standard.removeObject(forKey: DailyPlanStore.key)
            }

        }

        calendarDocument = document
        lists = current.collection.lists;
        savedCardIDs = current.collection.savedCardIDs;
        collections = library
    }


    ///
    /// @fcn        AppRootView.movePlanningSection
    /// @brief      Move a whole section with checked persistence and Undo
    /// @details    Resolves calendar and library destinations, optionally shifts dates, remaps importance and daily
    ///             priorities, and retains a guarded receipt for restoration only after the transfer saves.
    ///
    /// @param[in]  heading           Named divider identifying the complete section to transfer
    /// @param[in]  source            Optional source owner UUID; nil selects the current planning week
    /// @param[in]  destination       Chosen calendar or personal-list destination
    /// @param[in]  shiftDates        Whether date-bearing schedules should shift with the moved section
    /// @param[in]  documentOverride  Optional prepared calendar document used instead of the retained document
    ///
    /// @return     (Bool) true after a valid section transfer is saved; false if validation or persistence fails
    ///
    func movePlanningSection(
        _ heading: KanbanCard, source: UUID?, destination: CardMoveDestination,
        shiftDates: Bool, documentOverride: PlanningCalendarDocument? = nil
    ) -> Bool
    {

        do
        {

            guard let document = documentOverride ?? calendarDocument,
            let currentID = document.weeks.first(where:
                {
                    $0.startKey == document.currentWeekKey
                })?.id
            else
            {
                return false
            }

            let sourceID = source ?? currentID
            let destinationID = destination.collectionID ?? currentID
            var owners = sectionOwners(in: document)
            guard
            let sourceList = owners.first(where:
                {
                    $0.id == sourceID
                })?.lists.first(where:
                {

                    !$0.isArchived && $0.cards.contains
                    {
                        $0.id == heading.id && $0.createdAt == heading.createdAt
                    }

                })
            else
            {
                return false
            }


            ///
            /// @fcn        AppRootView.movePlanningSection.day
            /// @brief      Resolve the calendar day associated with an owner list
            /// @details    Searches the enclosing calendar document's day mappings and returns nil for lists without
            ///             a dated mapping.
            ///
            /// @param[in]  owner  Owner identity used to qualify numeric item references
            /// @param[in]  list   List supplying the current content and metadata
            ///
            /// @return     (Date?) local-noon date for the mapped list, or nil for an undated or missing list
            ///
            func day(owner: UUID, list: Int) -> Date?
            {

                document.weeks.first(where:
                    {
                        $0.id == owner
                    })?.dayListIDs.first(where:
                    {
                        $0.value == list
                    })
                .flatMap
                {
                    PlanningDate.date($0.key, calendar: document.calendar)
                }

            }

            let receipt = try SectionTransfer.move(
                heading: heading,
                source: WorkspaceListReference(ownerID: sourceID, listID: sourceList.id),
                destination: WorkspaceListReference(ownerID: destinationID, listID: destination.listID),
                owners: &owners,
                sourceDay: day(owner: sourceID, list: sourceList.id),
                destinationDay: day(owner: destinationID, list: destination.listID),
                shiftDates: shiftDates, calendar: document.calendar)
            let beforeImportance = UserDefaults.standard.data(forKey: LibraryImportanceSelection.key)
            if let beforeImportance, !beforeImportance.isEmpty
            {

                _ = try JSONDecoder().decode([LibraryRecentItem].self, from: beforeImportance)
            }

            var afterImportance = beforeImportance
            if sourceID != destinationID
            {

                var data = beforeImportance ?? Data()
                for (id, mapped) in receipt.mapping
                {

                    let importanceLevel = LibraryImportanceSelection.level(
                        cardID: id, collectionID: sourceID, data: beforeImportance ?? Data())
                    data = LibraryImportanceSelection.setting(
                        cardID: id, collectionID: sourceID, marked: false, data: data)
                    data = LibraryImportanceSelection.settingLevel(
                        cardID: mapped, collectionID: destinationID, level: importanceLevel, data: data)
                }

                afterImportance = data
            }

            let beforePlans = UserDefaults.standard.data(forKey: DailyPlanStore.key)
            let plans = try DailyPlanStore.load()
            let relocatedPlans = DailyPlanStore.relocatingSection(receipt, in: plans)
            let plansChanged = plans.plans != relocatedPlans.plans
            let afterPlans = plansChanged ? try JSONEncoder().encode(relocatedPlans) : beforePlans
            try saveSectionOwners(owners, document: document, importance: afterImportance, dailyPlans: afterPlans)
            CreatedContentReveal.shared.request(listID: destination.listID, card: receipt.heading)
            TransferConfirmationPresenter.shared.showUndo(
                TransferConfirmation(title: receipt.heading.sectionHeading ?? "Section", destination: destination.title)
            )
            {

                do
                {

                    guard let current = calendarDocument,
                    UserDefaults.standard.data(forKey: LibraryImportanceSelection.key) == afterImportance,
                    UserDefaults.standard.data(forKey: DailyPlanStore.key) == afterPlans
                    else
                    {
                        throw CocoaError(.fileWriteFileExists)
                    }

                    let restored = try receipt.undo(in: sectionOwners(in: current))
                    try saveSectionOwners(
                        restored, document: current, importance: beforeImportance, dailyPlans: beforePlans)
                    if let original = receipt.before.first(where:
                        {
                            $0.id == sourceID
                        })?.lists.first(where:
                        {

                            $0.id == sourceList.id
                        })?.cards.first(where:
                        {
                            $0.id == heading.id
                        })
                    {

                        CreatedContentReveal.shared.request(listID: sourceList.id, card: original)
                    }

                    return true
                }
                catch
                {

                    DatabaseActivity.shared.report(
                                                            "Could not undo the section move. Content may have changed since it moved; your current edits have been retained."
                    )
                    return false
                }

            }

            return true
        }
        catch
        {

            DatabaseActivity.shared.report("Could not move this section. Your content has been retained.")
            return false
        }

    }


    ///
    /// @fcn        AppRootView.movePlanningList
    /// @brief      Move a list between planning and personal owners
    /// @details    Resolves the destination, updates cross-owner references and markers, and publishes only after the
    ///             checked storage operation succeeds.
    ///
    /// @param[in]  listID         Numeric list identity within its owner
    /// @param[in]  sourceID       Identity of the source owner
    /// @param[in]  destinationID  Identity of the destination owner; nil uses the supported current-week route
    ///
    /// @return     (Bool) true after the list transfer is accepted and saved; false otherwise
    ///
    func movePlanningList(_ listID: Int, sourceID: UUID, destinationID: UUID?) -> Bool
    {

        do
        {

            guard var document = calendarDocument else
            {
                return false
            }

            if let current = document.weeks.firstIndex(where:
                {
                    $0.startKey == document.currentWeekKey
                })
            {

                document.weeks[current].collection.lists = lists
                document.weeks[current].collection.savedCardIDs = savedCardIDs
            }

            let datedSource = document.weeks.first
            {
                $0.id == sourceID
            }

            let emptiedDates = datedSource?.dayListIDs.filter
            {
                $0.value == listID
            } .map(\.key) ?? []
            var combined = collections + document.weeks.map(\.collection)
            let moved: KanbanList
            let newStandalone: PersonalCollection?
            if let destinationID
            {

                moved = try CrossBoardListMovement.move(
                    listID: listID, from: sourceID, to: destinationID, collections: &combined)
                newStandalone = nil
            }
            else
            {

                let standalone = try CrossBoardListMovement.detach(
                    listID: listID, from: sourceID, collections: &combined)
                moved = standalone.lists[0]
                newStandalone = standalone
            }

            for index in document.weeks.indices
            {

                if let updated = combined.first(where:
                    {
                        $0.id == document.weeks[index].id
                    })
                {

                    document.weeks[index].collection = updated
                }

                if document.weeks[index].id == sourceID
                {

                    for key in emptiedDates
                    {

                        if let date = PlanningDate.date(key, calendar: document.calendar)
                        {

                            _ = document.weeks[index].prepareDay(date)
                        }

                    }

                }

            }

            let updatedLibrary = combined.filter
            {
                candidate in
                candidate.id == newStandalone?.id || collections.contains
                {
                    $0.id == candidate.id
                }

            }

            guard let current = document.weeks.first(where:
                {
                    $0.startKey == document.currentWeekKey
                }) else
            {

                return false
            }

            // Validate all payloads and retained stores before any writes or publication.
            _ = try JSONEncoder().encode(document)
            _ = try JSONEncoder().encode(updatedLibrary)
            _ = try JSONEncoder().encode(current.collection.lists)
            _ = try PlanningCalendarStore.load()
            if let data = UserDefaults.standard.data(forKey: "Plenact.Board.v1")
            {

                _ = try JSONDecoder().decode([KanbanList].self, from: data)
            }

            if let data = UserDefaults.standard.data(forKey: "Plenact.PersonalCollections.v1")
            {

                _ = try JSONDecoder().decode([PersonalCollection].self, from: data)
            }

            let defaults = UserDefaults.standard
            let keys = [
                PlanningCalendarStore.key, "Plenact.Board.v1", "Plenact.PersonalCollections.v1",
                                        "Plenact.SavedCardIDs.v1"
            ]
            let previous = keys.map
            {
                defaults.object(forKey: $0)
            }

            do
            {

                try PlanningCalendarStore.save(document)
                try PersonalCollectionStore.saveChecked(updatedLibrary)
                try KanbanBoardPersistence.saveListsChecked(current.collection.lists)
                SavedCardPersistence.save(current.collection.savedCardIDs)
            }
            catch
            {

                for (key, value) in zip(keys, previous)
                {

                    if let value
                    {
                        defaults.set(value, forKey: key)
                    }
                    else
                    {
                        defaults.removeObject(forKey: key)
                    }

                }

                throw error
            }

            calendarDocument = document
            collections = updatedLibrary
            lists = current.collection.lists
            savedCardIDs = current.collection.savedCardIDs
            let destination =
            newStandalone != nil
            ? "Plans as a standalone List"
            : (document.weeks.first(where:
                    {
                        $0.id == destinationID
                    })?.rangeTitle
                ?? updatedLibrary.first(where:
                    {
                        $0.id == destinationID
                    })?.title ?? "another board")
            TransferConfirmationPresenter.shared.show(
                TransferConfirmation(title: moved.title, destination: destination))
            return true
        }
        catch
        {

            DatabaseActivity.shared.report(
                                    "Could not move this list: \(error.localizedDescription) Its content has been retained.")
            return false
        }

    }


    ///
    /// @fcn        AppRootView.mutateReviewItem
    /// @brief      Apply an explicit review decision to its current source
    /// @details    Uses the live item and review anchor to perform the requested completion or movement and returns
    ///             its resulting workspace identity.
    ///
    /// @param[in]  live    Currently resolved workspace source item
    /// @param[in]  action  Explicit review, toolbar, or contextual action selected by the caller
    /// @param[in]  anchor  Calendar-day key anchoring the review decision
    ///
    /// @return     (PlanningSearchResult) source identity and content resulting from the explicit review action
    /// @throws     Explicit failures include `CocoaError(.validationMissingMandatoryProperty)`,
    ///             `CocoaError(.fileWriteUnknown)`, `CocoaError(.fileNoSuchFile)`,
    ///             `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies propagate unless handled
    ///             within this operation.
    ///
    func mutateReviewItem(_ live: PlanningSearchResult, action: DailyReviewAction, anchor: String) throws
    -> PlanningSearchResult
    {

        var result = live
        switch action
        {

        case .keep:
            break
        case .keepTomorrow:
            guard !live.card.isTitleChecked,
            collections.contains(where:
                {

                    $0.id == live.collectionID && $0.isActive && $0.kind == .list && $0.title == "On the Table"
                })
            else
            {
                throw CocoaError(.validationMissingMandatoryProperty)
            }

            // The review decision is the persisted change; the original item stays intact.
            break
        case .table:
            guard !live.card.isTitleChecked,
            let table = collections.first(where:
                {
                    $0.isActive && $0.kind == .list && $0.title == "On the Table"
                }),
            let list = table.lists.first(where:
                {
                    !$0.isArchived
                }),
            let moved = movePriorityForVision(
                live, destination: WorkspaceListReference(ownerID: table.id, listID: list.id))
            else
            {
                throw CocoaError(.fileWriteUnknown)
            }

            result = moved
        case .queue:
            guard
            let queue = collections.first(where:
                {
                    $0.isActive && $0.kind == .list && $0.title == "In the Queue"
                }),
            let list = queue.lists.first(where:
                {
                    !$0.isArchived
                })
            else
            {
                throw CocoaError(.fileNoSuchFile)
            }

            if queue.id != live.collectionID || list.id != live.listID
            {

                guard
                let moved = movePriorityForVision(
                    live, destination: WorkspaceListReference(ownerID: queue.id, listID: list.id))
                else
                {
                    throw CocoaError(.fileWriteUnknown)
                }

                result = moved
            }

        case .tomorrow, .date:
            guard var document = calendarDocument else
            {
                throw CocoaError(.fileReadCorruptFile)
            }

            let targetDate: Date
            if case .date(let key) = action
            {

                guard let date = PlanningDate.date(key, calendar: document.calendar) else
                {

                    throw CocoaError(.coderInvalidValue)
                }

                targetDate = date
            }
            else
            {

                guard let date = PlanningDate.date(anchor, calendar: document.calendar),
                let next = document.calendar.date(byAdding: .day, value: 1, to: date)
                else
                {
                    throw CocoaError(.coderInvalidValue)
                }

                targetDate = next
            }

            var week =
            document.week(for: targetDate) ?? DatedPlanningWeek.make(for: targetDate, calendar: document.calendar)
            let targetID = week.prepareDay(targetDate)
            if week.id != live.collectionID || targetID != live.listID
            {

                let before = Set(week.collection.lists.first
                    {
                        $0.id == targetID
                    }!.cards.map(\.id))
                document.upsert(week)
                let target = CardMoveDestination(
                    collectionID: week.id, listID: targetID, title: week.rangeTitle, group: "Calendar")
                guard
                movePlanningCard(
                    live.card, source: live.collectionID, destination: target, documentOverride: document),
                let updated = calendarDocument?.weeks.first(where:
                    {
                        $0.id == week.id
                    }),
                let list = updated.collection.lists.first(where:
                    {
                        $0.id == targetID
                    }),
                let moved = list.cards.first(where:
                    {

                        !before.contains($0.id) && $0.createdAt == live.card.createdAt
                    })
                else
                {
                    throw CocoaError(.fileWriteUnknown)
                }

                result = PlanningSearchResult(
                    weekKey: updated.startKey, collectionID: updated.id, collectionTitle: updated.rangeTitle,
                    listID: list.id, listTitle: list.title, card: moved)
            }

        case .complete, .archive:
            let dated = calendarDocument?.weeks.first
            {
                $0.id == live.collectionID
            }

            guard
            var owner = dated?.collection
            ?? collections.first(where:
                {
                    $0.id == live.collectionID && $0.isActive
                }),
            let index = owner.lists.firstIndex(where:
                {
                    $0.id == live.listID && !$0.isArchived
                }),
            let cardIndex = owner.lists[index].cards.firstIndex(where:
                {
                    $0.id == live.card.id
                })
            else
            {
                throw CocoaError(.fileNoSuchFile)
            }

            if action == .archive
            {

                owner.lists[index].archiveCard(id: live.card.id)
            }
            else
            {

                guard live.card.presentation == .card else
                {
                    throw CocoaError(.coderInvalidValue)
                }

                guard !live.card.isEditingLocked else
                {
                    throw CocoaError(.validationMissingMandatoryProperty)
                }

                owner.lists[index].cards[cardIndex].isTitleChecked = true
                result = PlanningSearchResult(
                    weekKey: live.weekKey, collectionID: owner.id, collectionTitle: live.collectionTitle,
                    listID: live.listID, listTitle: live.listTitle, card: owner.lists[index].cards[cardIndex])
            }

            if var week = dated, var document = calendarDocument
            {

                week.collection = owner;
                document.upsert(week)
                try PlanningCalendarStore.save(document)
                if week.startKey == document.currentWeekKey
                {
                    try KanbanBoardPersistence.saveListsChecked(owner.lists)
                }

                calendarDocument = document
                if week.startKey == document.currentWeekKey
                {
                    lists = owner.lists
                }

            }
            else
            {

                guard let index = collections.firstIndex(where:
                    {
                        $0.id == owner.id
                    }) else
                {

                    throw CocoaError(.fileNoSuchFile)
                }

                var updated = collections;
                updated[index] = owner
                try PersonalCollectionStore.saveChecked(updated)
                collections = updated
            }

        }

        return result
    }


    ///
    /// @fcn        AppRootView.applyWeeklyReview
    /// @brief      Commit a weekly review decision with its review record
    /// @details    Uses the expected review baseline and recoverable workspace transaction so the item action and
    ///             saved decision remain consistent; failures return nil with feedback.
    ///
    /// @param[in]  source    Live source item with its calendar or Library location
    /// @param[in]  action    Explicit review, toolbar, or contextual action selected by the caller
    /// @param[in]  draft     Editable value proposed for persistence
    /// @param[in]  baseline  Expected retained value used to detect a conflicting edit
    ///
    /// @return     (WeeklyReviewRecord?) saved weekly review record, or nil when the decision cannot be committed
    ///
    func applyWeeklyReview(
        _ source: PlanningSearchResult, action: DailyReviewAction, draft: WeeklyReviewRecord,
        baseline: WeeklyReviewRecord?
    ) -> WeeklyReviewRecord?
    {

        let oldDocument = calendarDocument, oldLists = lists, oldCollections = collections, oldSaved = savedCardIDs
        do
        {

            guard
            let live = planningCalendarAccess?.searchableItems.first(where:
                {

                    $0.collectionID == source.collectionID && $0.card.id == source.card.id
                    && $0.card.createdAt == source.card.createdAt
                }),
            collections.contains(where:
                {

                    $0.id == live.collectionID && $0.isActive && $0.kind == .list && $0.title == "In the Queue"
                }),
            try WeeklyReviewStore.load().records[draft.id] == baseline,
            !draft.decisions.contains(where:
                {
                    $0.source.resolve(in: [live]) != nil
                })
            else
            {
                throw DailyPlanStore.Failure.conflict
            }

            return try DailyReviewTransaction.perform
            {

                let result = try mutateReviewItem(live, action: action, anchor: draft.startKey)
                var updated = draft
                updated.decisions.append(
                    DailyReviewDecision(
                        source: DailyPlanPriority(live), result: DailyPlanPriority(result), action: action))
                if let index = updated.priorities.firstIndex(where:
                    {
                        $0.resolve(in: [live]) != nil
                    })
                {

                    updated.priorities[index] = DailyPlanPriority(result)
                }

                return try WeeklyReviewStore.save(updated, replacing: baseline)
            }

        }
        catch
        {

            calendarDocument = oldDocument;
            lists = oldLists;
            collections = oldCollections;
            savedCardIDs = oldSaved
            if UserDefaults.standard.object(forKey: DailyReviewTransaction.key) != nil
            {

                workspaceRecoveryError = error.localizedDescription
            }

            return nil
        }

    }


    ///
    /// @fcn        AppRootView.applyDailyReview
    /// @brief      Commit an evening review decision with its daily plan
    /// @details    Checks the expected daily-plan baseline and saves the workspace action and review state together;
    ///             failures return nil instead of advancing the review.
    ///
    /// @param[in]  source    Live source item with its calendar or Library location
    /// @param[in]  action    Explicit review, toolbar, or contextual action selected by the caller
    /// @param[in]  draft     Editable value proposed for persistence
    /// @param[in]  baseline  Expected retained value used to detect a conflicting edit
    ///
    /// @return     (DailyPlan?) saved daily plan, or nil when the review decision cannot be committed
    ///
    func applyDailyReview(
        _ source: PlanningSearchResult, action: DailyReviewAction, draft: DailyPlan, baseline: DailyPlan?
    ) -> DailyPlan?
    {

        let previousDocument = calendarDocument
        let previousLists = lists
        let previousCollections = collections
        let previousSaved = savedCardIDs
        do
        {

            guard
            let live = planningCalendarAccess?.searchableItems.first(where:
                {

                    $0.collectionID == source.collectionID && $0.card.id == source.card.id
                    && $0.card.createdAt == source.card.createdAt
                }), try DailyPlanStore.load().plans[draft.id] == baseline
            else
            {
                throw DailyPlanStore.Failure.conflict
            }

            return try DailyReviewTransaction.perform
            {

                let result = try mutateReviewItem(live, action: action, anchor: draft.id)
                var updatedPlan = draft
                let original = DailyPlanPriority(live)
                let destination = DailyPlanPriority(result)
                if let index = updatedPlan.priorities.firstIndex(where:
                    {
                        $0.resolve(in: [live]) != nil
                    })
                {

                    updatedPlan.priorities[index] = destination
                }

                var review = updatedPlan.eveningReview ?? DailyEveningReview()
                guard !review.decisions.contains(where:
                    {
                        $0.source == original
                    }) else
                {

                    throw DailyPlanStore.Failure.conflict
                }

                review.decisions.append(DailyReviewDecision(source: original, result: destination, action: action))
                updatedPlan.eveningReview = review
                return try DailyPlanStore.save(updatedPlan, replacing: baseline)
            }

        }
        catch
        {

            calendarDocument = previousDocument;
            lists = previousLists;
            collections = previousCollections;

            savedCardIDs = previousSaved
            if UserDefaults.standard.object(forKey: DailyReviewTransaction.key) != nil
            {

                workspaceRecoveryError = error.localizedDescription
            }

            return nil
        }

    }


    ///
    /// @fcn        AppRootView.movePriorityForVision
    /// @brief      Move a planning priority to its chosen workspace list
    /// @details    Resolves the live source and returns the moved result only after the checked workspace operation
    ///             succeeds.
    ///
    /// @param[in]  source       Live source item with its calendar or Library location
    /// @param[in]  destination  Owner-qualified destination list reference
    ///
    /// @return     (PlanningSearchResult?) moved live item at its new personal-list location, or nil if movement
    ///             fails
    ///
    func movePriorityForVision(_ source: PlanningSearchResult, destination: WorkspaceListReference)
    -> PlanningSearchResult?
    {

        guard
        let live = planningCalendarAccess?.searchableItems.first(where:
            {

                $0.collectionID == source.collectionID && $0.card.id == source.card.id
                && $0.card.createdAt == source.card.createdAt
            }), let owner = collections.first(where:
            {
                $0.id == destination.ownerID && $0.isActive
            }),
        let target = owner.lists.first(where:
            {
                $0.id == destination.listID && !$0.isArchived
            })
        else
        {
            return nil
        }

        let before = Set(target.cards.map(\.id))
        let route = CardMoveDestination(
            collectionID: owner.id, listID: target.id, title: owner.title, group: "Plans", columnTitle: target.title)
        guard movePlanningCard(live.card, source: live.collectionID, destination: route),
        let updatedOwner = collections.first(where:
            {
                $0.id == owner.id
            }),
        let updatedList = updatedOwner.lists.first(where:
            {
                $0.id == target.id
            }),
        let moved = updatedList.cards.first(where:
            {

                !before.contains($0.id) && $0.createdAt == live.card.createdAt
            })
        else
        {
            return nil
        }

        return PlanningSearchResult(
            weekKey: nil, collectionID: owner.id, collectionTitle: updatedOwner.title,
            listID: updatedList.id, listTitle: updatedList.title, card: moved)
    }


    ///
    /// @fcn        AppRootView.movePlanningCard
    /// @brief      Transfer one card between calendar or library lists
    /// @details    Works from the canonical document, preserves content through cross-owner movement, and publishes
    ///             changes only after checked persistence succeeds.
    ///
    /// @param[in]  card              Card or note being inspected or changed
    /// @param[in]  source            Optional source owner UUID; nil selects the current planning week
    /// @param[in]  destination       Chosen calendar or personal-list destination
    /// @param[in]  documentOverride  Optional prepared calendar document used instead of the retained document
    ///
    /// @return     (Bool) true after the card transfer saves successfully; false on invalid input or save failure
    ///
    func movePlanningCard(
        _ card: KanbanCard, source: UUID?, destination: CardMoveDestination,
        documentOverride: PlanningCalendarDocument? = nil
    ) -> Bool
    {

        do
        {

            var document = documentOverride ?? calendarDocument
            let currentID = document?.weeks.first
            {
                $0.startKey == document?.currentWeekKey
            }?.id
            let normalizedSource = source == currentID ? nil : source
            let normalizedDestination = CardMoveDestination(
                collectionID: destination.collectionID == currentID ? nil : destination.collectionID,
                listID: destination.listID, title: destination.title, group: destination.group)
            var updatedWeek = lists
            var updatedSaved = savedCardIDs
            let dated = (document?.weeks ?? []).filter
            {
                $0.id != currentID
            }

            var combined = collections + dated.map(\.collection)
            try CrossBoardCardMovement.move(
                card, from: normalizedSource, to: normalizedDestination,
                week: &updatedWeek, collections: &combined, saved: &updatedSaved)
            let libraryIDs = Set(collections.map(\.id))
            let updatedLibrary = combined.filter
            {
                libraryIDs.contains($0.id)
            }

            if var next = document
            {

                for var week in next.weeks
                {

                    if week.id == currentID
                    {

                        week.collection.lists = updatedWeek;
                        week.collection.savedCardIDs = updatedSaved
                    }
                    else if let collection = combined.first(where:
                        {
                            $0.id == week.id
                        })
                    {

                        week.collection = collection
                    }

                    next.upsert(week)
                }

                document = next
            }

            _ = try JSONEncoder().encode(updatedWeek)
            _ = try JSONEncoder().encode(updatedLibrary)
            if let document
            {
                _ = try JSONEncoder().encode(document);
                _ = try PlanningCalendarStore.load()
            }

            if let data = UserDefaults.standard.data(forKey: "Plenact.Board.v1")
            {

                _ = try JSONDecoder().decode([KanbanList].self, from: data)
            }

            if let data = UserDefaults.standard.data(forKey: "Plenact.PersonalCollections.v1")
            {

                _ = try JSONDecoder().decode([PersonalCollection].self, from: data)
            }

            let defaults = UserDefaults.standard
            let keys = [
                PlanningCalendarStore.key, "Plenact.Board.v1", "Plenact.PersonalCollections.v1",
                                        "Plenact.SavedCardIDs.v1"
            ]
            let previous = keys.map
            {
                defaults.object(forKey: $0)
            }

            do
            {

                if let document
                {
                    try PlanningCalendarStore.save(document)
                }

                try KanbanBoardPersistence.saveListsChecked(updatedWeek)
                try PersonalCollectionStore.saveChecked(updatedLibrary)
                SavedCardPersistence.save(updatedSaved)
            }
            catch
            {

                for (key, value) in zip(keys, previous)
                {

                    if let value
                    {
                        defaults.set(value, forKey: key)
                    }
                    else
                    {
                        defaults.removeObject(forKey: key)
                    }

                }

                throw error
            }

            calendarDocument = document
            lists = updatedWeek;
            collections = updatedLibrary;
            savedCardIDs = updatedSaved
            if normalizedSource != normalizedDestination.collectionID
            {

                TransferConfirmationPresenter.shared.show(
                    TransferConfirmation(title: card.word, destination: destination.title))
            }

            return true
        }
        catch
        {

            DatabaseActivity.shared.report(
                                    "Could not move this item: \(error.localizedDescription) Its content has been retained.")
            return false
        }

    }


    ///
    /// @fcn        AppRootView.switchMonthExample
    /// @brief      Request a protected example-dataset switch
    /// @details    Coordinates the requested load or restore with the application's dataset-switch presentation and
    ///             recovery state.
    ///
    /// @param[in]  restoring  Whether to restore original user data rather than load an example
    ///
    /// @return     (Void) no return value
    ///
    func switchMonthExample(restoring: Bool)
    {

        guard !isSwitchingWorkspace else
        {
            return
        }

        isRestoringWorkspace = restoring
        isSwitchingWorkspace = true
    }


    ///
    /// @fcn        AppRootView.performMonthExampleSwitch
    /// @brief      Perform the example load or original-data restore
    /// @details    Uses the verified backup store, reloads workspace state after success, and retains recovery
    ///             feedback when switching fails.
    ///
    /// @param[in]  restoring  Whether to restore original user data rather than load an example
    ///
    /// @return     (Void) no return value
    ///
    @MainActor
    func performMonthExampleSwitch(restoring: Bool) async
    {

        // Runs only after the navigation tree has disappeared and flushed its saved state.
        do
        {

            guard var savedDocument = calendarDocument,
            let currentIndex = savedDocument.weeks.firstIndex(where:
                {
                    $0.startKey == savedDocument.currentWeekKey
                }
            )
            else
            {
                throw CocoaError(.fileReadCorruptFile)
            }

            savedDocument.weeks[currentIndex].collection.lists = lists
            savedDocument.weeks[currentIndex].collection.savedCardIDs = savedCardIDs
            try PlanningCalendarStore.save(savedDocument)
            calendarDocument = savedDocument
            try KanbanBoardPersistence.saveListsChecked(lists)
            try PersonalCollectionStore.saveChecked(collections)
            SavedCardPersistence.save(savedCardIDs)
            let store = try FullMonthExampleStore.live()
            let example = FullMonthExample.make(calendar: calendarDocument?.calendar ?? .current)
            try await Task.detached(priority: .userInitiated)
            {

                if restoring
                {
                    try store.restoreUserData()
                }
                else
                {
                    try store.loadExample(example)
                }

            } .value
            try reloadWorkspaceFromStorage()
            workspaceNotice =
            restoring
            ? "Your saved Plenact data and local files have been restored. Changes made while exploring the example month have been replaced."
            : "Your original Plenact data is saved offline on this device. Explore the example month, then return to Library + → Examples → Restore User Data to bring it back. Loading another example month will keep that original backup."
        }
        catch
        {

            if (try? FullMonthExampleStore.live().needsRecovery) == true
            {

                workspaceRecoveryError = error.localizedDescription
            }

            workspaceNotice =
                                    "The data switch could not finish: \(error.localizedDescription) Your saved data and any existing offline backup have been retained. Please retry."
        }

        isSwitchingWorkspace = false
    }


    ///
    /// @fcn        AppRootView.reloadWorkspaceFromStorage
    /// @brief      Reload live workspace state after a dataset change
    /// @details    Reads the retained planning, library, and related preference values so the interface reflects the
    ///             installed dataset.
    ///
    /// @return     (Void) no return value
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    func reloadWorkspaceFromStorage() throws
    {

        let document = try PlanningCalendarStore.load()
        guard let current = document?.weeks.first(where:
            {
                $0.startKey == document?.currentWeekKey
            }) else
        {

            throw CocoaError(.fileReadCorruptFile)
        }

        calendarDocument = document
        lists = current.collection.lists
        savedCardIDs = SavedCardPersistence.load()
        collections = PersonalCollectionStore.load()
        profile = LocalProfileStore.load()
        displayedPlanningWeek = nil
        displayedPlanningListID = nil
        boardTargetListID = nil
        boardTargetCardID = nil
        savedPersonalCardTarget = nil
        activePersonalListNewNote = nil
        visibleNoteIDs = []
        selectedDestination = .lists
        workspaceGeneration = UUID()
    }


    ///
    /// @fcn        AppRootView.recoverWorkspace
    /// @brief      Retry recovery of interrupted workspace storage operations
    /// @details    Runs the checked recovery paths and refreshes live state when recovery succeeds, retaining
    ///             actionable error feedback otherwise.
    ///
    /// @return     (Void) no return value
    ///
    func recoverWorkspace()
    {

        isSwitchingWorkspace = true
        Task
        {
            @MainActor in
            do
            {

                try DailyReviewTransaction.recover()
                let store = try FullMonthExampleStore.live()
                try await Task.detached(priority: .userInitiated)
                {
                    try store.recoverInterruptedSwitch()
                } .value
                try reloadWorkspaceFromStorage()
                workspaceRecoveryError = nil
            }
            catch
            {
                workspaceRecoveryError = error.localizedDescription
            }

            isSwitchingWorkspace = false
        }

    }


    ///
    /// @fcn        AppRootView.loadExampleWeek
    /// @brief      Apply the bundled example to the current calendar week
    /// @details    Retains a full Undo snapshot and applies the example through the dated-template path so schedules,
    ///             bookmarks, and importance align with Today.
    ///
    /// @return     (Bool) true when the example is applied and saved; false when loading is rejected
    ///
    func loadExampleWeek() -> Bool
    {

        guard let document = calendarDocument,
        var current = document.weeks.first(where:
            {
                $0.startKey == document.currentWeekKey
            }),
        let date = PlanningDate.date(current.startKey, calendar: document.calendar)
        else
        {
            return false
        }

        current.collection.lists = lists;
        current.collection.savedCardIDs = savedCardIDs
        let importance = LibraryImportanceSelection.cardIDs(
            collectionID: current.id,
            data: UserDefaults.standard.data(forKey: LibraryImportanceSelection.key) ?? Data())
        let todayListID = TodayListSelection.currentDayList(in: lists.filter
            {
                !$0.isArchived
            }, date: .now)?.id
        let importanceData = UserDefaults.standard.data(forKey: LibraryImportanceSelection.key) ?? Data()
        let levels = Dictionary(
            uniqueKeysWithValues: importance.map
            {
                id in
                (id, LibraryImportanceSelection.level(cardID: id, collectionID: current.id, data: importanceData))
            })
        guard
        ExampleLoadUndoStore.save(
            lists: lists, todayListID: todayListID, week: current,
            savedCardIDs: savedCardIDs, importantCardIDs: importance, importanceLevels: levels)
        else
        {

            DatabaseActivity.shared.report("Could not save the previous Week Board, so the example was not loaded.")
            return false
        }

        do
        {

            let template = PlanningRoutineLibrary.seeded.templates[0]
            let importantIDs = PlanningTemplateApplication.exampleImportantIDs(template, in: current)
            let example = try PlanningTemplateApplication.apply(
                template, to: current, date: date, calendar: document.calendar, mode: .replace)
            return savePlanningWeek(example, exampleImportantIDs: importantIDs, replaceImportant: true)
        }
        catch
        {

            DatabaseActivity.shared.report("Could not load the example Week Board: \(error.localizedDescription)")
            return false
        }

    }


    ///
    /// @fcn        AppRootView.undoExampleWeek
    /// @brief      Restore the workspace snapshot preceding the example load
    /// @details    Restores the retained week and its owner-qualified markers through checked persistence, consuming
    ///             the snapshot only after success.
    ///
    /// @return     (Bool) true when the pre-example state is restored; false when no valid restoration succeeds
    ///
    func undoExampleWeek() -> Bool
    {

        guard let snapshot = ExampleLoadUndoStore.load(),
        let current = calendarDocument?.weeks.first(where:
            {
                $0.startKey == calendarDocument?.currentWeekKey
            })
        else
        {

            DatabaseActivity.shared.report("The saved Week Board snapshot could not be restored.")
            return false
        }

        var restored = snapshot.week ?? current
        guard restored.id == current.id else
        {

            DatabaseActivity.shared.report("Return to the original week before restoring this example load.")
            return false
        }

        restored.collection.lists = snapshot.lists
        restored.collection.savedCardIDs = snapshot.savedCardIDs ?? savedCardIDs
        let levels =
        snapshot.importanceLevels
        ?? Dictionary(uniqueKeysWithValues: (snapshot.importantCardIDs ?? []).map
            {
                ($0, 1)
            })
        if savePlanningWeek(
            restored, exampleImportantIDs: snapshot.importantCardIDs ?? [],
            replaceImportant: snapshot.importantCardIDs != nil, restoredImportanceLevels: levels)
        {

            ExampleLoadUndoStore.clear()
            return true
        }

        return false
    }


    ///
    /// @fcn        AppRootView.openToolbarItem(_:)
    /// @brief      Open the requested Card or Note creation flow
    /// @details    Uses an open personal List's Note action when available; otherwise seeds the
    ///             shared composer with the selected presentation and Today's destination when
    ///             appropriate.
    ///
    /// @param[in]  presentation  Card or Note presentation requested for the new item
    ///
    /// @return     (Void) updates creation presentation state without creating a record
    ///
    func openToolbarItem(_ presentation: ItemPresentation)
    {

        if selectedDestination == .lists, presentation == .note, let action = activePersonalListNewNote
        {

            action()
            return
        }

        centerNewListID =
        selectedDestination == .today
        ? TodayListSelection.currentDayList(in: lists.filter
            {
                !$0.isArchived
            }, date: .now)?.id : nil
        centerNewPresentation = presentation
        showsCenterNewCardSheet = true
    }


    ///
    /// @fcn        AppRootView.openToolbarCollection
    /// @brief      Open personal list or board creation from the toolbar
    /// @details    Switches to Plans and sets its pending collection-kind request so the owning view can present the
    ///             corresponding creation flow.
    ///
    /// @param[in]  kind  Date, review, or collection kind selecting this operation's behavior
    ///
    /// @return     (Void) no return value
    ///
    func openToolbarCollection(_ kind: PersonalCollectionKind)
    {

        selectedDestination = .lists
        toolbarCollectionRequest = kind
    }


    ///
    /// @fcn        AppRootView.selectToolbarDestination
    /// @brief      Select a lower-toolbar destination and prepare its context
    /// @details    Clears stale Revisit selection for Activity; Week selection ensures today's list, clears its card
    ///             target, and increments the request that returns navigation to the week root.
    ///
    /// @param[in]  destination  Lower-toolbar destination to select
    ///
    /// @return     (Void) no return value
    ///
    func selectToolbarDestination(_ destination: AppDestination)
    {

        if destination == .saved
        {
            activityRevisitDestination = nil
        }

        if destination == .board
        {

            let result = TodayListSelection.ensureCurrentDayList(lists: lists)
            if result.lists != lists
            {
                lists = result.lists
            }

            boardTargetCardID = nil
            boardTargetListID = result.dayList.id
            weekRootRequest += 1
        }

        selectedDestination = destination
    }


    ///
    /// @fcn        AppRootView.tabButton
    /// @brief      Build a toolbar destination with its tap and hold actions
    /// @details    Uses the destination's icon and title while exposing its contextual long-press shortcut alongside
    ///             normal selection.
    ///
    /// @param[in]  destination  Lower-toolbar destination to select
    /// @param[in]  title        Display title or proposed title text
    /// @param[in]  systemImage  SF Symbol name used by the toolbar destination
    ///
    /// @return     (some View) a toolbar destination with its tap and hold actions
    ///
    func tabButton(_ destination: AppDestination, title: String, systemImage: String) -> some View
    {


        let geometry = bottomToolbarLayout
        let isSelected = selectedDestination == destination /* Current tab selection */

        return Button
        {

            selectToolbarDestination(destination)
        }
        label:
        {


            let layout =
            geometry.horizontalLabels /* Adaptive quick-creation action layout */
            ? AnyLayout(HStackLayout(spacing: geometry.tabLabelSpacing))
            : AnyLayout(VStackLayout(spacing: geometry.tabLabelSpacing))
            layout
            {


                Image(systemName: systemImage)
                .font(.system(size: geometry.tabIconSize, weight: .semibold))

                if PlanPreferencesStore.load().showsNavigationLabels
                {


                    Text(title)
                    .font(.system(geometry.labelStyle))
                }

            }

            .frame(maxWidth: .infinity, minHeight: geometry.tabMinimumHeight)
            .contentShape(Rectangle())
        }

        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.82))
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.55, maximumDistance: 24)
            .exclusively(before: TapGesture())
            .onEnded
            {
                result in
                switch result
                {

                case .first:
                    if destination == .today
                    {
                        showsToolbarTodayPlan = true
                    }

                    if destination == .board
                    {
                        showsToolbarCalendar = true
                    }

                    if destination == .lists
                    {
                        showsToolbarSearch = true
                    }

                    if destination == .saved
                    {
                        showsToolbarRevisit = true
                    }

                case .second:
                    selectToolbarDestination(destination)
                }

            }
        )
        .popover(
            isPresented: Binding(
                get:
                {
                    destination == .saved && showsToolbarRevisit
                },
                set:
                {

                    if destination == .saved
                    {
                        showsToolbarRevisit = $0
                    }

                }), arrowEdge: .bottom
        )
        {

            ToolbarRevisitMenu
            {
                choice in
                showsToolbarRevisit = false
                activityRevisitDestination = choice
                selectedDestination = .saved
            }
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityActions
        {

            if destination == .today
            {

                Button("Open Today’s Plan")
                {
                    showsToolbarTodayPlan = true
                }

            }

            if destination == .board
            {

                Button("Open Calendar")
                {
                    showsToolbarCalendar = true
                }

            }

            if destination == .lists
            {

                Button("Open Search")
                {
                    showsToolbarSearch = true
                }

            }

            if destination == .saved
            {

                Button("Open Revisit")
                {
                    showsToolbarRevisit = true
                }

            }

        }
        .accessibilityHint(
            destination == .today
            ? "Touch and hold to open Today’s Plan"
            : (destination == .board
                ? "Touch and hold to open Calendar"
                : (destination == .lists ? "Touch and hold to open Search" : "Touch and hold to open Revisit"))
        )
        .accessibilityIdentifier("toolbar.\(title.lowercased())")
        .accessibilityLabel(title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }


    ///
    /// @fcn        AppRootView.openBoardList(_:)
    /// @brief      Route to a specific list in Week
    /// @details    Remembers an existing list, clears any pending card target, and selects Week;
    ///             ContentView consumes and validates the pending list request
    ///
    /// @param[in]  listID  Requested Week list identity
    ///
    /// @return     (Void) updates navigation targets and selected destination
    ///
    /// @post       Board content remains unchanged
    ///
    func openBoardList(_ listID: Int)
    {

        displayedPlanningWeek = nil

        rememberLastViewedList(listID)
        boardTargetCardID = nil
        boardTargetListID = listID
        selectedDestination = .board
    }


    ///
    /// @fcn        AppRootView.registerPersonalListNewNote(_:)
    /// @brief      Register the New action supplied by an open personal List
    /// @details    The Library directory and personal Boards register nil and retain Week creation
    /// @param[in]  action  Optional List-scoped New Note presentation action
    /// @return     (Void) updates the current toolbar route only
    ///
    func registerPersonalListNewNote(_ action: (() -> Void)?)
    {


        activePersonalListNewNote = action
    }


    ///
    /// @fcn        AppRootView.openSavedDestination()
    /// @brief      Select the Activity destination
    /// @details    Changes the primary navigation selection to the existing Saved-backed Activity
    ///             surface without constructing a second copy of its history or bookmarks.
    ///
    /// @return     (Void) updates the selected application destination
    ///
    func openSavedDestination()
    {


        selectedDestination = .saved
    }


    ///
    /// @fcn        AppRootView.archiveWeekBoard()
    /// @brief      Preserve the complete Week Board as an archived personal board
    /// @details    Saves the recovery collection before clearing Week lists and bookmarks,
    ///             including archived lists/cards; errors are presented through DatabaseActivity
    ///
    /// @return     (Void) archives Week and navigates to Saved after saving the recovery collection
    ///
    /// @post       Success clears pending targets; failure leaves the active Week snapshot intact
    /// @note       Restoring this archive creates a separate board rather than replacing Week
    ///
    func archiveWeekBoard()
    {


        let archived = PersonalCollection.archivedWeekBoard(
            lists: lists, savedCardIDs: savedCardIDs)  /* Retained copy of the current Week workspace    */
        let updated = collections + [archived]         /* Directory snapshot including the archived Week */

        do
        {


            // Persist the recovery copy before clearing the active Week snapshot.
            try PersonalCollectionStore.saveChecked(updated)
            collections = updated
            lists = []
            savedCardIDs = []
            boardTargetListID = nil
            boardTargetCardID = nil
            selectedDestination = .saved
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not archive the Week Board: \(error.localizedDescription) The board has not been removed.")
        }

    }


    ///
    /// @fcn        AppRootView.cleanDeletedMedia(_:)
    /// @brief      Clean saved removal candidates against all retained content
    /// @details    Includes in-memory and persisted Week/collections plus the retained undo
    ///             snapshot; unreadable persisted references block cleanup and produce an explicit
    ///             notice
    ///
    /// @param[in]  candidates  Filenames removed by a successfully saved mutation
    ///
    /// @return     (Void) clean saved removal candidates against all retained content
    ///
    func cleanDeletedMedia(_ candidates: Set<String>)
    {


        guard !isSwitchingWorkspace, !candidates.isEmpty else
        {


            return
        }


        do
        {


            let persistedWeek =
            try UserDefaults.standard.data(
                forKey: "Plenact.Board.v1"
            ) /* Stored Week lists protecting referenced media */
            .map
            {
                try JSONDecoder().decode([KanbanList].self, from: $0)
            }
            ?? []
            let persistedCollections =
            try UserDefaults.standard.data(
                forKey: "Plenact.PersonalCollections.v1"
            ) /* Stored personal collections protecting referenced media */
            .map
            {
                try JSONDecoder().decode([PersonalCollection].self, from: $0)
            }
            ?? []
            let undo = try UserDefaults.standard.data(
                forKey: "Plenact.ExampleLoadUndo.v1"
            ) /* Stored example-load recovery snapshot */
            .map
            {
                try JSONDecoder().decode(ExampleLoadUndoSnapshot.self, from: $0)
            }

            let calendarLists = try PlanningCalendarStore.load()?.weeks.flatMap
            {
                $0.collection.lists
            }
            ?? []
            let retained =
            calendarLists + lists + collections.flatMap(\.lists)
            + persistedWeek /* All snapshots whose media must remain available */
            + persistedCollections.flatMap(\.lists) + (undo?.lists ?? [])

            try CardAttachmentStore.removeDeletedFiles(candidates, keeping: CardAttachmentStore.fileNames(in: retained))
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Content was saved, but some unused media could not be removed: \(error.localizedDescription)")
        }

    }


    ///
    /// @fcn        AppRootView.deleteWeekContents()
    /// @brief      Clear confirmed Week content without removing the workspace
    /// @details    Keeps separate personal/archive copies and resets pending navigation
    ///
    /// @return     (Void) clear confirmed Week content without removing the workspace
    ///
    func deleteWeekContents()
    {


        do
        {


            try commitWeekDeletion([], [])
            boardTargetListID = nil
            boardTargetCardID = nil
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not delete Week contents: \(error.localizedDescription) They have been retained.")
        }

    }


    ///
    /// @fcn        AppRootView.commitWeekDeletion(_:_:)
    /// @brief      Persist confirmed Week removal before updating bindings
    /// @details    Cleans only saved removal candidates and preserves retained media references
    ///
    /// @param[in]  snapshot   Complete remaining Week snapshot
    /// @param[in]  bookmarks  Remaining Week bookmarks
    ///
    /// @return     (Void) persist confirmed Week removal before updating bindings
    ///
    /// @throws     Encoding or preference errors; visible state stays unchanged
    ///
    func commitWeekDeletion(_ snapshot: [KanbanList], _ bookmarks: Set<Int>) throws
    {


        let candidates = CardAttachmentStore.fileNames(in: lists).subtracting(
            CardAttachmentStore.fileNames(in: snapshot)) /* Media removed by clearing Week content */

        if var document = calendarDocument,
        var current = document.weeks.first(where:
            {
                $0.startKey == document.currentWeekKey
            })
        {

            current.collection.lists = snapshot;
            current.collection.savedCardIDs = bookmarks
            document.upsert(current)
            try PlanningCalendarStore.save(document)
            calendarDocument = document
        }

        try KanbanBoardPersistence.saveListsChecked(snapshot)
        lists = snapshot
        savedCardIDs = bookmarks
        SavedCardPersistence.save(bookmarks)
        cleanDeletedMedia(candidates)
    }


    ///
    /// @fcn        AppRootView.deletePersonalBoard(_:)
    /// @brief      Save removal of a confirmed personal collection before publishing it
    /// @details    Failure leaves the collection retained and reports an error
    ///
    /// @param[in]  id  Collection UUID, not a Board-local card ID
    ///
    /// @return     (Bool) whether the confirmed removal was saved and published successfully
    ///
    @discardableResult
    func deletePersonalBoard(_ id: UUID) -> Bool
    {


        let updated = collections.filter
        {
            $0.id != id
        }  /* Directory snapshot excluding the deleted collection */


        do
        {


            try PersonalCollectionStore.saveChecked(updated)
            collections = updated

            return true
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not delete the collection: \(error.localizedDescription) It has been retained.")

            return false
        }

    }


    ///
    /// @fcn        AppRootView.archiveWeekList(_:)
    /// @brief      Retain a Week list outside active navigation
    /// @details    Changes only its archive marker
    ///
    /// @param[in]  id  Week list identity
    ///
    /// @return     (Void) retain a Week list outside active navigation
    ///
    func archiveWeekList(_ id: Int)
    {


        if let index = lists.firstIndex(where:
            {  /* Position of the Week list to archive */


                $0.id == id
            })
        {

            lists[index].isArchived = true
        }

    }


    ///
    /// @fcn        AppRootView.deleteWeekList(_:)
    /// @brief      Remove confirmed Week list content and bookmarks
    /// @details    Applies the shared complete-snapshot deletion helper
    ///
    /// @param[in]  id  Week list identity
    ///
    /// @return     (Bool) whether the confirmed removal was saved and published successfully
    ///
    @discardableResult
    func deleteWeekList(_ id: Int) -> Bool
    {


        var snapshot = lists          /* Week snapshot for checked deletion         */
        var bookmarks = savedCardIDs  /* Bookmarks pruned alongside removed content */

        BoardContentDeletion.list(id, in: &snapshot, savedCardIDs: &bookmarks)

        do
        {


            try commitWeekDeletion(snapshot, bookmarks)

            return true
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not delete the list: \(error.localizedDescription) It has been retained.")

            return false
        }

    }


    ///
    /// @fcn        AppRootView.archiveWeekCard(_:)
    /// @brief      Archive a bookmarked Week card without removing its bookmark
    /// @details    Finds the owning list by Board-local identity
    ///
    /// @param[in]  id  Week card identity
    ///
    /// @return     (Void) archive a bookmarked Week card without removing its bookmark
    ///
    func archiveWeekCard(_ id: Int)
    {


        if let index = lists.firstIndex(where:
            {  /* Week list containing the card to archive */


                $0.cards.contains(where:
                    {
                        $0.id == id
                    })
            })
        {

            lists[index].archiveCard(id: id)
        }

    }


    ///
    /// @fcn        AppRootView.deleteWeekCard(_:)
    /// @brief      Permanently remove a confirmed bookmarked Week card
    /// @details    Includes archive partitions and removes its bookmark
    ///
    /// @param[in]  id  Week card identity
    ///
    /// @return     (Bool) whether the confirmed removal was saved and published successfully
    ///
    @discardableResult
    func deleteWeekCard(_ id: Int) -> Bool
    {


        var snapshot = lists          /* Week snapshot for checked deletion         */
        var bookmarks = savedCardIDs  /* Bookmarks pruned alongside removed content */

        BoardContentDeletion.card(id, in: &snapshot, savedCardIDs: &bookmarks)

        do
        {


            try commitWeekDeletion(snapshot, bookmarks)

            return true
        }
        catch
        {


            DatabaseActivity.shared.report(
                                    "Could not delete the card: \(error.localizedDescription) It has been retained.")

            return false
        }

    }

}
