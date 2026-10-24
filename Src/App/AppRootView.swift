// --------------------------------------------------------------------------------------------------
// @file       AppRootView.swift
// @brief      Workspace composition and view-owned presentation state
// @details    Composes retained owners, navigation destinations, and child callbacks while related
//             operations remain in focused extensions.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Owns the application's workspace and navigation composition
///
/// @section    Purpose
///     Coordinates calendar and Library persistence, recovery, capture, search, and tab
///     destinations while passing checked mutation callbacks to child views.
///
struct AppRootView: View
{


    @AppStorage(PlanPreferencesStore.key) var planPreferencesData = Data()
    @StateObject var welcomeCue = TodayWelcomeCue()
    @Environment(\.accessibilityReduceMotion) var reduceLaunchMotion

    @State var isSwitchingWorkspace = false
    @State var isRestoringWorkspace = false
    @State var workspaceRecoveryError: String?
    @State var workspaceGeneration = UUID()
    @State var confirmsExampleMonth = false
    @State var confirmsRestoreUserData = false
    @State var workspaceNotice: String?
    @State var lists:           [KanbanList] = []                    /* Complete in-memory Week snapshot  */
    @State var collections = TodayListPins.loadInitialCollections()  /* Device-local personal collections */
    @State var calendarDocument:        PlanningCalendarDocument?
    @State var displayedPlanningWeek:   DatedPlanningWeek?
    @State var displayedPlanningListID: Int?
    @ObservedObject var reviewNotifications = ReviewRhythmNotifications.shared
    @AppStorage(ReviewRhythmStore.key) var reviewRhythmPreferencesData = Data()
    @Environment(\.scenePhase) var scenePhase
    @State var launchShadowFading = false
    @State var launchProgress = PlenactLaunchProgress()
    @State var hasLoadedBoard = false                              /* Whether the initial Week snapshot has loaded */
    @State var profile = LocalProfileStore.load()                  /* Optional local identity and settings         */
    @State var selectedDestination:       AppDestination = .today  /* Currently selected primary destination       */
    @State var bottomNavigationSafeInset: CGFloat = 34
    var bottomToolbarLayout:              BottomToolbarLayout
    {

        .configuration(isTablet: UIDevice.current.userInterfaceIdiom == .pad, compact: verticalSizeClass == .compact)
    }

    var bottomNavigationHeight: CGFloat
    {

        bottomToolbarLayout.reservedHeight(bottomInset: bottomNavigationSafeInset)
    }

    @State var visibleNoteIDs: Set<UUID> = []
    var isNotePresented:       Bool
    {
        !visibleNoteIDs.isEmpty
    }

    @State var weekRootRequest = 0                         /* Explicit Week toolbar taps return to the Board root */
    @State var savedCardIDs = SavedCardPersistence.load()  /* Device-local saved cards                            */
    @State var savedPersonalCardTarget:
    PersonalSavedCardTarget? /* Personal bookmark requested from Saved              */
    @State var newLibraryListRequest = 0
    @State var quickCreateRequest = 0           /* Center-bar quick-create request          */
    @State var showsCenterNewCardSheet = false  /* Destination picker for New outside Today */
    @State var centerNewPresentation:    ItemPresentation = .card
    @State var centerNewListID:          Int?
    @State var toolbarCollectionRequest: PersonalCollectionKind?
    @State var showsToolbarTodayPlan = false
    @State var showsToolbarCalendar = false
    @State var showsToolbarSearch = false
    @State var showsToolbarRevisit = false
    @State var activityRevisitDestination: ToolbarRevisitDestination?

    @State var boardTargetListID:         Int?           /* List requested by a Today-to-Board navigation     */
    @State var boardTargetCardID:         Int?           /* Card requested by a Today-to-Board navigation     */
    @State var activePersonalListNewNote: (() -> Void)?  /* Callback to create a new note in active pers list */

    @Environment(\.verticalSizeClass) var verticalSizeClass /* Layout size class used to compact the landscape bar */


    ///
    /// @fcn        AppRootView.body
    /// @brief      Load the Week snapshot before exposing the navigation shell
    /// @details    Presents a background surface until asynchronous local loading completes,
    ///             then installs navigation content; database activity feedback covers both states
    ///
    /// @return     (some View) loading surface or configured app navigation
    /// @post       The task assigns the loaded snapshot and marks initial loading complete
    ///
    var body: some View
    {  /* Primary Today and Board navigation shell */


        Group
        {

            if let workspaceRecoveryError
            {

                VStack(spacing: 20)
                {

                    Text("Your saved data needs recovery").font(.headline)
                    Text(workspaceRecoveryError).foregroundStyle(.secondary)
                    Button("Retry recovery")
                    {
                        recoverWorkspace()
                    } .disabled(isSwitchingWorkspace)
                } .padding()
            }
            else if isSwitchingWorkspace
            {

                ProgressView("Preparing your workspace…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task
                {
                    await performMonthExampleSwitch(restoring: isRestoringWorkspace)
                }

            }
            else if hasLoadedBoard
            {


                navigationContent
                .id(workspaceGeneration)
                .transition(.opacity)
            }
            else
            {

                PlenactLoadingView(fadesShadow: launchShadowFading, progress: launchProgress)
                .transition(.opacity)
            }

        }

        .animation(reduceLaunchMotion ? nil : .easeInOut(duration: 0.45), value: hasLoadedBoard)
        .environmentObject(welcomeCue)
        .databaseActivityOverlay()
        .confirmationDialog("Load an example month?", isPresented: $confirmsExampleMonth, titleVisibility: .visible)
        {

            Button("Back Up and Load Example Month")
            {
                switchMonthExample(restoring: false)
            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text(
                                    "Your current Plenact data and local files will first be copied to an offline backup. The example month will replace your active plans. To return, choose Library + → Examples → Restore User Data. An existing original backup will be kept."
            )
        }
        .confirmationDialog(
                        "Restore your saved data?", isPresented: $confirmsRestoreUserData, titleVisibility: .visible
        )
        {

            Button("Restore User Data")
            {
                switchMonthExample(restoring: true)
            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text(
                                    "Restores the complete offline copy saved before the example month. Changes made in the example workspace will be replaced."
            )
        }
        .alert(
                        "Plenact workspace",
                        isPresented: Binding(get:
                            {
                                workspaceNotice != nil
                            }, set:
                            {
                                if !$0
                                {
                                    workspaceNotice = nil
                                }

                            })
        )
        {

            Button("OK")
            {
                workspaceNotice = nil
            }

        }
        message:
        {

            Text(workspaceNotice ?? "")
        }
        .onChange(of: scenePhase)
        {
            _, phase in
            if phase == .active
            {

                welcomeCue.becameActive();
                advancePlanningWeekIfNeeded()
                Task
                {
                    try? await ReviewRhythmNotifications.shared.synchronize()
                }

            }
            else
            {

                welcomeCue.leftForeground()
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
        {
            _ in
            advancePlanningWeekIfNeeded()
        }
        .onChange(of: reviewRhythmPreferencesData)
        {
            _, _ in
            Task
            {
                try? await ReviewRhythmNotifications.shared.synchronize()
            }

        }
        .onReceive(reviewNotifications.$pending)
        {
            route in
            if route != nil
            {
                selectedDestination = .today
            }

        }
        .task
        {

            PlenactKeyboard.shared.install()
            Task
            {
                try? await ReviewRhythmNotifications.shared.synchronize()
            }

            if scenePhase == .active
            {
                welcomeCue.becameActive()
            }

            guard !hasLoadedBoard else
            {


                return
            }


            let launchDeadline = ContinuousClock.now.advanced(by: .milliseconds(900))
            launchProgress = PlenactLaunchProgress()
            launchShadowFading = false
            let legacy = await KanbanBoardPersistence.loadListsInBackground()
            launchProgress.stage = .plans
            await Task.yield()
            var seedsFreshDemoImportance = false
            var preparedDocument: PlanningCalendarDocument?
            var preparedWeek: DatedPlanningWeek?
            do
            {

                if var document = try PlanningCalendarStore.load()
                {

                    try document.repairLegacyMondayFirstLayout()
                    let previous = document.weeks.first
                    {
                        $0.startKey == document.currentWeekKey
                    }!
                    let newWeek =
                    document.week(for: .now) == nil
                    ? try PlanningRoutineStore.newWeek(for: .now, calendar: document.calendar) : nil
                    preparedWeek = document.rollForward(
                        to: .now, currentLists: previous.collection.lists, saved: previous.collection.savedCardIDs,
                        newWeek: newWeek)
                    preparedDocument = document
                }
                else
                {

                    if let data = UserDefaults.standard.data(forKey: "Plenact.Board.v1")
                    {

                        _ = try JSONDecoder().decode([KanbanList].self, from: data)
                    }

                    var calendar = Calendar.current
                    calendar.firstWeekday = 2
                    seedsFreshDemoImportance = UserDefaults.standard.data(forKey: "Plenact.Board.v1") == nil
                    let current =
                    UserDefaults.standard.data(forKey: "Plenact.Board.v1") == nil
                    ? try PlanningRoutineStore.newWeek(for: .now, calendar: calendar)
                    : DatedPlanningWeek.make(for: .now, lists: legacy, saved: savedCardIDs, calendar: calendar)
                    preparedWeek = current
                    preparedDocument = PlanningCalendarDocument(
                        currentWeekKey: current.startKey, firstWeekday: 2, weeks: [current])
                }

            }
            catch
            {

                lists = legacy
                DatabaseActivity.shared.report(
                                                "Could not open your calendar weeks: \(error.localizedDescription) Your saved data has been retained."
                )
            }

            launchProgress.stage = .ready
            await Task.yield()
            if let document = preparedDocument, let current = preparedWeek
            {

                do
                {

                    try DailyReviewTransaction.perform
                    {

                        try PlanningCalendarStore.save(document)
                        try KanbanBoardPersistence.saveListsChecked(current.collection.lists)
                    }

                    lists = current.collection.lists
                    savedCardIDs = current.collection.savedCardIDs
                    calendarDocument = document
                    if seedsFreshDemoImportance
                    {

                        let defaults = UserDefaults.standard
                        defaults.set(
                            LibraryImportanceSelection.demoData(
                                in: [current.collection],
                                preserving: defaults.data(forKey: LibraryImportanceSelection.key) ?? Data()),
                            forKey: LibraryImportanceSelection.key)
                    }

                }
                catch
                {

                    lists = legacy
                    DatabaseActivity.shared.report(
                                                            "Could not open your calendar weeks: \(error.localizedDescription) Your saved data has been retained."
                    )
                }

            }

            SavedCardPersistence.save(savedCardIDs)
            launchProgress.stage = .welcome
            await Task.yield()
            // Preparation is complete; keep the steady icons visible during the existing minimum launch time.
            launchProgress.finished = true
            do
            {
                try await ContinuousClock().sleep(until: launchDeadline)
            }
            catch
            {
                return
            }

            // Finish with a full second of shadow fade before revealing the workspace.
            launchShadowFading = true
            do
            {
                try await Task.sleep(for: .seconds(1))
            }
            catch
            {
                return
            }

            // Briefly hold the shadow-free logo before revealing the workspace.
            do
            {
                try await Task.sleep(for: .milliseconds(250))
            }
            catch
            {
                return
            }

            hasLoadedBoard = true
            applyDayListOrderingPreference()
        }

    }


    ///
    /// @fcn        AppRootView.navigationContent
    /// @brief      Compose the four primary destinations and persistence observers
    /// @details    Supplies active/archive list partitions, shared collections, profile callbacks,
    ///             bookmarks, and navigation targets; saves complete snapshots when state changes
    ///
    /// @return     (some View) tab shell, custom navigation bar, and new-card sheet
    ///
    /// @pre        Initial Week loading has completed
    /// @post       User edits flow through shared bindings; collection-save errors reach the activity banner
    ///
    var navigationContent: some View
    {  /* Active tab with shared navigation chrome */


        TabView(selection: $selectedDestination)
        {


            TodayHomeView(
                lists: $lists.activeLists,
                archivedLists: $lists.archivedLists,
                savedCardIDs: $savedCardIDs,
                profile: profile,
                onSaveProfile:
                {
                    updatedProfile in
                    profile = updatedProfile
                    LocalProfileStore.save(updatedProfile)
                },
                onRemoveProfile:
                {

                    profile = nil
                    LocalProfileStore.remove()
                },
                onAddCard:
                {
                    listID, title, description, subtitle, presentation, actions in
                    addCard(
                        to: listID, title: title, description: description, subtitle: subtitle,
                        presentation: presentation, actions: actions)
                },
                onAddCapture:
                {
                    capture in
                    addCard(
                        to: capture.listID, title: capture.title, description: capture.body, subtitle: capture.subtitle,
                        presentation: capture.presentation, actions: capture.actions, attachments: capture.attachments,
                        schedule: capture.schedule, checkedSave: true)
                },
                onToggleCardCompletion: toggleCardCompletion,
                onOpenBoardList: openBoardList,
                onOpenBoardCard: openBoardCard,
                onArchiveCard: archiveWeekCard,
                onDeleteCard: deleteWeekCard,
                onArchiveList: archiveWeekList,
                onDeleteList: deleteWeekList,
                quickCreateRequest: quickCreateRequest
            )
            .tabItem
            {

                Label("Today", systemImage: "sun.max")
            }

            .environment(
                \.cardMovementSource,
                calendarDocument?.weeks.first
                {
                    $0.startKey == calendarDocument?.currentWeekKey
                }?.id
            )
            .tag(AppDestination.today)
            .toolbar(.hidden, for: .tabBar)

            Group
            {

                if let displayedPlanningWeek
                {

                    PlanningCalendarWeekView(
                        week: displayedPlanningWeek, initialDayID: nil, initialCardID: nil,
                        onLeaveForHome:
                        {
                            self.displayedPlanningWeek = nil
                        }, isWeekTab: true,
                        initialBoardListID: displayedPlanningListID
                    )
                    .id(displayedPlanningWeek.startKey)
                }
                else
                {

                    ContentView(
                        lists: $lists.activeLists,
                        archivedLists: $lists.archivedLists,
                        boardTargetListID: $boardTargetListID,
                        boardTargetCardID: $boardTargetCardID,
                        boardRootRequest: weekRootRequest,
                        savedCardIDs: $savedCardIDs,
                        onListViewed: rememberLastViewedList,
                        boardSubtitle: "This Week • "
                        + (calendarDocument?.weeks.first
                            {
                                $0.startKey == calendarDocument?.currentWeekKey
                            }?
                            .compactRangeTitle ?? ""),
                        onArchiveBoard: archiveWeekBoard,
                        onDeleteBoard: deleteWeekContents,
                        deleteBoardTitle: "Delete Week contents",
                        onCommitDeletion: commitWeekDeletion,
                        onListsChanged:
                        {
                            _ in
                        },
                        viewportOwnerID: calendarDocument?.weeks.first
                        {

                            $0.startKey == calendarDocument?.currentWeekKey
                        }?.id
                    )
                    .id(calendarDocument?.currentWeekKey ?? "week.current")
                }

            }
            .tabItem
            {

                Label("Board", systemImage: "rectangle.3.group")
            }

            .tag(AppDestination.board)
            .toolbar(.hidden, for: .tabBar)

            libraryTab

            SavedCardsView(
                planningDocument: calendarDocument,
                revisitDestination: $activityRevisitDestination,
                lists: lists.filter
                {
                    !$0.isArchived
                },
                savedCardIDs: savedCardIDs,
                collections: $collections,
                onOpenBoardCard: openBoardCard,
                onOpenPersonalCard:
                {
                    target in
                    savedPersonalCardTarget = target
                    selectedDestination = .lists
                },
                onRestoreBoard: restoreBoard,
                onDeleteBoard: deletePersonalBoard,
                onArchiveCard: archiveWeekCard,
                onDeleteCard: deleteWeekCard
            )
            .tabItem
            {

                Label("Activity", systemImage: "clock.arrow.circlepath")
            }

            .tag(AppDestination.saved)
            .toolbar(.hidden, for: .tabBar)
        }

        .safeAreaInset(edge: .bottom, spacing: 0)
        {

            Color.clear
            .frame(height: isNotePresented ? 0 : bottomNavigationHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay
        {

            GeometryReader
            {
                geometry in
                VStack(spacing: 0)
                {

                    Spacer(minLength: 0)
                    if !isNotePresented
                    {
                        bottomNavigationBar
                    }

                }
                .onAppear
                {
                    bottomNavigationSafeInset = geometry.safeAreaInsets.bottom
                }
                .onChange(of: geometry.safeAreaInsets.bottom)
                {
                    _, inset in
                    bottomNavigationSafeInset = inset
                }

            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }

        .environment(
            \.workspaceNoteVisibility,
            {
                id, visible in
                if visible
                {
                    visibleNoteIDs.insert(id)
                }
                else
                {
                    visibleNoteIDs.remove(id)
                }

            }
        )
        .environment(\.workspaceBottomBarHeight, isNotePresented ? 0 : bottomNavigationHeight)
        .environment(\.cardMovementAccess, cardMovementAccess)
        .environment(\.planningCalendarAccess, planningCalendarAccess)
        .environment(\.calendar, calendarDocument?.calendar ?? .current)
        .modifier(
            OwnerImportanceControls(
                ownerID: calendarDocument?.weeks.first
                {

                    $0.startKey == calendarDocument?.currentWeekKey
                }?.id)
        )

        .onChange(of: planPreferencesData)
        {
            _, _ in
            applyDayListOrderingPreference()
        }
        .onChange(of: savedCardIDs)
        {
            _, updatedIDs in
            SavedCardPersistence.save(updatedIDs)
            persistCurrentPlanningWeek()
        }

        .onChange(of: lists)
        {
            old, updated in
            guard hasLoadedBoard else
            {


                return
            }


            let candidates = CardAttachmentStore.fileNames(in: old).subtracting(
                CardAttachmentStore.fileNames(in: updated)) /* Media removed by the collection update */

            persistCurrentPlanningWeek()
            KanbanBoardPersistence.enqueueSave(lists, onSuccess:
                {
                    cleanDeletedMedia(candidates)
                })
        }

        .onChange(of: collections)
        {
            old, updated in
            do
            {


                try PersonalCollectionStore.saveChecked(updated)
                cleanDeletedMedia(
                    CardAttachmentStore.fileNames(in: old.flatMap(\.lists))
                    .subtracting(CardAttachmentStore.fileNames(in: updated.flatMap(\.lists))))
            }
            catch
            {

                DatabaseActivity.shared.report("Could not save your boards: \(error.localizedDescription)")
            }

        }

        .modifier(PlanningSharedSearchPresentation(isPresented: $showsToolbarSearch))
        .sheet(isPresented: $showsToolbarTodayPlan)
        {

            TodayPlanView(calendar: calendarDocument?.calendar ?? .current)
        }
        .sheet(isPresented: $showsToolbarCalendar)
        {

            PlanningCalendarView(onLeaveForHome:
                {
                    showsToolbarCalendar = false
                })
        }
        .sheet(isPresented: $showsCenterNewCardSheet)
        {

            QuickNoteComposer(
                lists: $lists.activeLists,
                initialListID: centerNewListID
                ?? LastViewedListStore.resolve(
                    in: lists.filter
                    {
                        !$0.isArchived
                    }, fallback: PlanPreferencesStore.load().defaultListID),
                initialPresentation: centerNewPresentation,
                onSaveCapture:
                {
                    capture in
                    addCard(
                        to: capture.listID, title: capture.title, description: capture.body,
                        subtitle: capture.subtitle, presentation: capture.presentation, actions: capture.actions,
                        attachments: capture.attachments, schedule: capture.schedule, checkedSave: true)
                }
            )
            {
                listID, title, description, subtitle, presentation, actions in
                addCard(
                    to: listID, title: title, description: description, subtitle: subtitle, presentation: presentation,
                    actions: actions)
            }

            .databaseActivityOverlay()
        }

    }


    var planningCalendarAccess: PlanningCalendarAccess?
    {

        guard let document = calendarDocument else
        {
            return nil
        }

        return PlanningCalendarAccess(
            document: document, library: collections, saveWeek: savePlanningWeek,
            openCurrentWeek:
            {

                displayedPlanningListID = nil
                displayedPlanningWeek = nil
                selectedDestination = .board
                weekRootRequest += 1
                boardTargetListID = nil;
                boardTargetCardID = nil
            }, openToday:
            {
                selectedDestination = .today
            },
            openLibraryCard:
            {
                target in
                savedPersonalCardTarget = target;
                selectedDestination = .lists
            },
            saveLibrary:
            {
                collection in
                guard let index = collections.firstIndex(where:
                    {
                        $0.id == collection.id
                    }) else
                {
                    return false
                }

                var snapshot = collections;
                snapshot[index] = collection
                do
                {
                    try PersonalCollectionStore.saveChecked(snapshot);
                    collections = snapshot;
                    return true
                }
                catch
                {

                    DatabaseActivity.shared.report(
                                                            "Could not save this Plans collection: \(error.localizedDescription)");

                    return false
                }

            }, applyWeeklyReview: applyWeeklyReview, applyDailyReview: applyDailyReview,
            moveForDailyPlan: movePriorityForVision, setFirstWeekday: setPlanningFirstWeekday,
            openWeek:
            {
                requestedWeek in
                guard let week = preparePlanningWeek(requestedWeek) else
                {
                    return
                }

                displayedPlanningListID = nil
                weekRootRequest += 1
                displayedPlanningWeek = week.startKey == calendarDocument?.currentWeekKey ? nil : week
                boardTargetListID = nil;
                boardTargetCardID = nil
                selectedDestination = .board
            }, moveList: movePlanningList,
            openWeekOnDay:
            {
                requestedWeek, date in
                guard let week = preparePlanningWeek(requestedWeek) else
                {
                    return
                }

                let listID = week.dayListIDs[PlanningDate.key(date, calendar: document.calendar)]
                weekRootRequest += 1
                displayedPlanningListID = listID
                displayedPlanningWeek = week.startKey == calendarDocument?.currentWeekKey ? nil : week
                boardTargetCardID = nil
                boardTargetListID = week.startKey == calendarDocument?.currentWeekKey ? listID : nil
                selectedDestination = .board
            },
            saveExampleWeek:
            {
                week, importantIDs in
                savePlanningWeek(week, exampleImportantIDs: importantIDs)
            })
    }


    var cardMovementAccess: CardMovementAccess
    {

        let currentID = calendarDocument?.weeks.first
        {
            $0.startKey == calendarDocument?.currentWeekKey
        }?.id
        let weekDestinations = lists.filter
        {
            !$0.isArchived
        } .map
        {

            CardMoveDestination(collectionID: nil, listID: $0.id, title: $0.title, group: "Week")
        }

        let calendarDestinations = (calendarDocument?.weeks ?? []).filter
        {
            $0.id != currentID
        } .flatMap
        {
            week in
            week.collection.lists.filter
            {
                !$0.isArchived
            } .map
            {

                CardMoveDestination(
                    collectionID: week.id, listID: $0.id, title: "\(week.rangeTitle) / \($0.title)", group: "Calendar",
                    columnTitle: $0.title)
            }

        }

        let libraryDestinations = collections.filter(\.isActive).flatMap
        {
            collection in
            collection.lists.filter
            {
                !$0.isArchived
            } .map
            {

                CardMoveDestination(
                    collectionID: collection.id, listID: $0.id,
                    title: collection.kind == .list ? collection.title : "\(collection.title) / \($0.title)",
                    group: "Plans", columnTitle: $0.title)
            }

        }

        return CardMovementAccess(
            destinations: weekDestinations + calendarDestinations + libraryDestinations,
            move:
            {
                card, source, destination in
                movePlanningCard(card, source: source, destination: destination)
            },
            moveToDate:
            {
                card, source, date in
                guard var document = calendarDocument else
                {
                    return false
                }

                var week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: document.calendar)
                let listID = week.prepareDay(date)
                guard let list = week.collection.lists.first(where:
                    {
                        $0.id == listID
                    }) else
                {
                    return false
                }

                document.upsert(week)
                return movePlanningCard(
                    card, source: source,
                    destination: CardMoveDestination(
                        collectionID: week.id, listID: list.id, title: "\(week.rangeTitle) / \(list.title)",
                        group: "Calendar"),
                    documentOverride: document)
            },
            moveSection:
            {
                heading, source, destination, shift in
                movePlanningSection(heading, source: source, destination: destination, shiftDates: shift)
            },
            moveSectionToDate:
            {
                heading, source, date, shift in
                guard var document = calendarDocument else
                {
                    return false
                }

                var week = document.week(for: date) ?? DatedPlanningWeek.make(for: date, calendar: document.calendar)
                let listID = week.prepareDay(date)
                document.upsert(week)
                return movePlanningSection(
                    heading, source: source,
                    destination: CardMoveDestination(
                        collectionID: week.id, listID: listID,
                        title: date.formatted(date: .abbreviated, time: .omitted), group: "Calendar"),
                    shiftDates: shift, documentOverride: document)
            })
    }


    var libraryTab: some View
    {  /* Personal collection directory and creation actions */


        BoardListsView(
            retainedWeekLists: lists + (calendarDocument?.weeks.flatMap
                {
                    $0.collection.lists
                }
                ?? []),
            collections: $collections,
            newListRequest: newLibraryListRequest,
            toolbarCollectionRequest: $toolbarCollectionRequest,
            registerListNewNote: registerPersonalListNewNote,
            onOpenSaved: openSavedDestination,
            onLoadExampleWeek: loadExampleWeek,
            onUndoExampleWeek: undoExampleWeek,
            onLoadExampleMonth:
            {
                confirmsExampleMonth = true
            },
            onRestoreUserData:
            {
                confirmsRestoreUserData = true
            },
            hasUserDataBackup: (try? FullMonthExampleStore.live().hasUserData) ?? false,
            savedPersonalCardTarget: savedPersonalCardTarget,
            onClearSavedPersonalCardTarget:
            {
                savedPersonalCardTarget = nil
            }
        )
        .tabItem
        {

            Label("Plans", systemImage: "books.vertical")
        }
        .tag(AppDestination.lists)
        .toolbar(.hidden, for: .tabBar)
    }


    ///
    /// @fcn        AppRootView.bottomNavigationBar
    /// @brief      Build the custom destination bar and central New control
    /// @details    Honors navigation-label preferences and remains anchored at the screen bottom
    ///             while the keyboard overlays it. The decorative background extends through the
    ///             bottom safe area using an explicit device allowance, even if a sheet transition
    ///             temporarily reports zero inherited inset. The preset top gap lets New overlap
    ///             the surface without moving the controls.
    ///             New creates Cards from Today, Week and Activity, or a List from Plans;
    ///             a long press offers explicit Note, Card, List, and Board creation
    ///
    /// @return     (some View) paper-backed navigation controls
    /// @post       Button and gesture callbacks update navigation and creation-request state
    ///
    var bottomNavigationBar: some View
    {  /* Shared tab and quick-creation controls */

        let layout = bottomToolbarLayout
        let isCompact = layout.horizontalLabels /* Landscape-height navigation layout */

        return ZStack(alignment: isCompact ? .center : .top)
        {

            HStack(spacing: layout.rowSpacing)
            {

                tabButton(.today, title: "Today", systemImage: "sun.max.fill")
                tabButton(.board, title: "Week", systemImage: "rectangle.3.group.fill")

                Color.clear
                .frame(maxWidth: .infinity, minHeight: layout.tabMinimumHeight)
                .accessibilityHidden(true)

                tabButton(.lists, title: "Plans", systemImage: "books.vertical.fill")
                tabButton(.saved, title: "Activity", systemImage: "clock.arrow.circlepath")
            }

            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, layout.topPadding)
            .padding(.bottom, layout.bottomPadding)
            .frame(maxWidth: .infinity)
            .offset(y: layout.tabsOffset)

            let newLayout =
            isCompact /* Adaptive arrangement of creation actions */
            ? AnyLayout(HStackLayout(spacing: layout.newLabelSpacing))
            : AnyLayout(VStackLayout(spacing: layout.newLabelSpacing))
            newLayout
            {

                Button
                {

                    if selectedDestination == .today
                    {

                        quickCreateRequest += 1
                    }
                    else if selectedDestination == .lists
                    {

                        newLibraryListRequest += 1
                    }
                    else
                    {

                        centerNewPresentation = .card
                        centerNewListID = nil
                        showsCenterNewCardSheet = true
                    }

                }
                label:
                {

                    Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: layout.newIconSize, weight: .medium))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-7))
                    .frame(width: layout.newButtonSize, height: layout.newButtonSize)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: Color.black.opacity(0.22), radius: 8, x: 2, y: 4)
                    .contentShape(Circle())
                }

                .buttonStyle(.plain)
                .contextMenu
                {

                    Button("New Note", systemImage: "note.text")
                    {
                        openToolbarItem(.note)
                    }

                    Button("New Card", systemImage: "rectangle.stack")
                    {
                        openToolbarItem(.card)
                    }

                    Divider()
                    Button("New List", systemImage: "list.bullet.rectangle")
                    {
                        openToolbarCollection(.list)
                    }

                    Button("New Board", systemImage: "rectangle.split.3x1")
                    {
                        openToolbarCollection(.board)
                    }

                }
                .accessibilityLabel(selectedDestination == .lists ? "Create a new List" : "Create a new Card")
                .accessibilityHint("Tap for contextual creation. Touch and hold for New Note, Card, List, or Board.")
                .accessibilityIdentifier("toolbar.new")

                if PlanPreferencesStore.load().showsNavigationLabels
                {


                    Text("New")
                    .font(.system(layout.labelStyle))
                    .foregroundStyle(.white.opacity(0.92))
                }

            }

            .offset(y: layout.newOffset)
            .zIndex(2)
        }

        .frame(maxWidth: .infinity)
        .frame(height: bottomNavigationHeight, alignment: isCompact ? .center : .top)
        .background(alignment: .bottom)
        {

            BottomToolbarBackground(
                topInset: layout.backgroundTopInset,
                bottomInset: max(bottomNavigationSafeInset, layout.safeAreaAllowance)
            )
        }

        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: -4)
    }

}
