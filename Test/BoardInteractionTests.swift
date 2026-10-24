// --------------------------------------------------------------------------------------------------
// @file       BoardInteractionTests.swift
// @brief      Board Interaction regression tests
// @details    Verifies related workspace behavior with synthetic fixtures and the shared
//             PlenactBoardDocumentTests helpers. Retains original test identities and checked
//             assertions while separating this coverage from unrelated feature tests.
//
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import AVFoundation
import PencilKit
import SwiftUI
import UserNotifications
import XCTest


///
/// BoardInteraction regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testRandomCardColorPreviewsRenderInLightAndDarkWithoutChangingRecords
    /// @brief      Verify that random Card Color Previews Render In Light And Dark Without Changing Records
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(cards, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testRandomCardColorPreviewsRenderInLightAndDarkWithoutChangingRecords() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        let list = KanbanList(id: 1, title: "Color examples", cards: [])
        let cards = [
            list.makeItem(
                id: 1, title: "Random header only",
                creationPreferences: LocalProfilePreferences(randomizesNewCardHeaders: true)),
            list.makeItem(
                id: 2, title: "Random background only",
                creationPreferences: LocalProfilePreferences(randomizesNewCardBackgrounds: true)),
            list.makeItem(
                id: 3, title: "Both colors",
                creationPreferences: LocalProfilePreferences(
                    randomizesNewCardHeaders: true, randomizesNewCardBackgrounds: true))
        ]
        let original = cards
        for scheme in [ColorScheme.light, .dark]
        {

            let view = VStack(spacing: 12)
            {

                ForEach(cards)
                {
                    card in
                    KanbanCardView(
                        card: card, height: 140, displaySettings: BoardDisplaySettings(), labelLibrary: .starter,
                        onUpdateCard:
                        {
                            _ in
                            XCTFail("Rendering must not edit")
                        }, onDeleteCard:
                        {

                        }, onArchiveCard:
                        {

                        },
                        onToggle:
                        {

                        })
                }

                BoardGalleryTile(card: cards[2])
            } .padding().background(Color(.systemGroupedBackground)).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-random-card-colors-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("RANDOM_CARD_COLORS_RENDER=" + url.path)
            XCTAssertEqual(cards, original)
        }

        let settings = UIHostingController(
            rootView: PlanSettingsView(lists: [list], onSaveProfile:
                {
                    _ in
                    XCTFail("Rendering must not save")
                }))
        window.rootViewController = settings
        try await Task.sleep(for: .milliseconds(200))
        let image = UIGraphicsImageRenderer(bounds: settings.view.bounds).image
        {
            _ in
            settings.view.drawHierarchy(in: settings.view.bounds, afterScreenUpdates: true)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                        "plenact-random-card-color-settings.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("RANDOM_CARD_COLORS_RENDER=" + url.path)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testListHeaderIconDefaultsAndExplicitChoicesPersist
    /// @brief      Verify that list Header Icon Defaults And Explicit Choices Persist
    /// @details    Exercises `custom.headerAppearance`, `legacy.headerAppearance`, `restored.headerAppearance`.
    ///             Checks `XCTAssertFalse(custom.showsIconInHeader)`; `XCTAssertNil(custom.headerAppearance())`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    func testListHeaderIconDefaultsAndExplicitChoicesPersist() throws
    {

        var custom = KanbanList(id: 7, title: "Custom list", cards: [])
        custom.appearance = ItemAppearance(icon: .tasks)
        XCTAssertFalse(custom.showsIconInHeader)
        XCTAssertNil(custom.headerAppearance())
        custom.appearance?.showsIconInHeader = true
        XCTAssertEqual(custom.headerAppearance()?.icon, .tasks)
        custom.appearance?.showsIconInHeader = false
        let roundTrip = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(custom))
        XCTAssertFalse(roundTrip.showsIconInHeader)
        let explicitOff = ItemAppearance(showsIconInHeader: false)
        XCTAssertFalse(explicitOff.isEmpty)
        for title in ["On the Table", "In the Queue", "Scheduled"]
        {

            var legacy = KanbanList(id: 1, title: title, cards: [])
            XCTAssertTrue(legacy.showsIconInHeader)
            XCTAssertNotNil(legacy.headerAppearance()?.icon)
            legacy.appearance = explicitOff
            let restored = try JSONDecoder().decode(KanbanList.self, from: JSONEncoder().encode(legacy))
            XCTAssertTrue(restored.hasFixedHeaderIcon)
            XCTAssertTrue(restored.showsIconInHeader)
            XCTAssertNotNil(restored.headerAppearance())
            XCTAssertTrue(DefaultListTutorial.makeStarter(title: title).lists[0].showsIconInHeader)
        }

        custom.appearance = ItemAppearance(showsIconInHeader: true)
        XCTAssertEqual(custom.headerAppearance(collectionIcon: .upcoming)?.icon, .upcoming)
        XCTAssertEqual(custom.headerAppearance()?.icon, .notes)
        custom.appearance?.showsIconInHeader = false
        XCTAssertNil(custom.headerAppearance(collectionIcon: .upcoming))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testToolbarRevisitMenuRendersWithoutChoosingOrChangingHistory
    /// @brief      Verify that toolbar Revisit Menu Renders Without Choosing Or Changing History
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(UserDefaults.standard.data(forKey:
    ///             ActivityRecentStore.key), history)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testToolbarRevisitMenuRendersWithoutChoosingOrChangingHistory() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        let history = UserDefaults.standard.data(forKey: ActivityRecentStore.key)
        for scheme in [ColorScheme.light, .dark]
        {

            let host = UIHostingController(
                rootView: ToolbarRevisitMenu
                {
                    _ in
                    XCTFail("Rendering must not navigate")
                }
                .background(.regularMaterial).preferredColorScheme(scheme))
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-revisit-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: path);
            print("REVISIT_RENDER=" + path.path)
        }

        XCTAssertEqual(UserDefaults.standard.data(forKey: ActivityRecentStore.key), history)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDayDistributionBannerRendersWithNoPlanWrites
    /// @brief      Verify that day Distribution Banner Renders With No Plan Writes
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(UserDefaults.standard.data(forKey:
    ///             DailyPlanStore.key), before)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDayDistributionBannerRendersWithNoPlanWrites() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        let before = UserDefaults.standard.data(forKey: DailyPlanStore.key)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let cards = (0 ..< 5).map
        {
            i in
            KanbanCard(
                id: i, word: "Planned activity", listTitle: "Today", isTitleChecked: i % 2 == 0,
                startDate: day.addingTimeInterval(Double(i + 7) * 3600),
                dueDate: day.addingTimeInterval(Double(i + 8) * 3600),
                labelIDs: [LabelLibrary.dayAreaLabels[i].id], startDateKind: .dateAndTime, dueDateKind: .dateAndTime)
        }

        for (name, items, scheme) in [
            ("populated", cards, ColorScheme.light), ("empty", [], .light), ("dark", cards, .dark)
        ]
        {

            let host = UIHostingController(
                rootView: ScrollView
                {

                    DayScheduleOverview(cards: items, labels: LabelLibrary.starter.includingDayAreas, day: day).padding(
                        16)
                } .preferredColorScheme(scheme))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-day-distribution-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: url);
            print("DAY_DISTRIBUTION_RENDER=" + url.path)
        }

        XCTAssertEqual(UserDefaults.standard.data(forKey: DailyPlanStore.key), before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayPerspectiveRendersWithoutMutatingPlansOrLists
    /// @brief      Verify that today Perspective Renders Without Mutating Plans Or Lists
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(UserDefaults.standard.data(forKey:
    ///             DailyPlanStore.key), beforePlans)`; `XCTAssertEqual(UserDefaults.standard.data(forKey:
    ///             ReviewRhythmStore.dismissalsKey), beforeRhythm)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayPerspectiveRendersWithoutMutatingPlansOrLists() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        let beforePlans = UserDefaults.standard.data(forKey: DailyPlanStore.key)
        let beforeRhythm = UserDefaults.standard.data(forKey: ReviewRhythmStore.dismissalsKey)
        let completed = [
            KanbanCard(id: 1, word: "Make time for family", listTitle: "Today", isTitleChecked: true, checklists: [])
        ]
        let tomorrow = KanbanList(
            id: 2, title: "Tomorrow",
            cards: [
                KanbanCard(id: 2, word: "A thoughtful start", listTitle: "Tomorrow", checklists: []),
                KanbanCard(id: 3, word: "A long walk and a little room to think", listTitle: "Tomorrow", checklists: [])
            ])
        for (name, done, next, scheme, width) in [
            ("populated", completed, Optional(tomorrow), ColorScheme.light, CGFloat(393)),
            ("quiet", [], nil, .light, 393),
            ("dark-tablet", completed, Optional(tomorrow), .dark, 820)
        ]
        {

            let view = ScrollView
            {

                TodayPerspectiveSection(
                    completed: done, tomorrowList: next,
                    onReview:
                    {
                        _ in
                        XCTFail("Rendering must not open review")
                    },
                    onSettings:
                    {
                        XCTFail("Rendering must not open settings")
                    },
                    onReflect:
                    {
                        XCTFail("Rendering must not open a plan")
                    },
                    onPrepare:
                    {
                        XCTFail("Rendering must not create a plan")
                    }
                )
                .padding(20)
            } .background(Color(.systemGroupedBackground)).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let path = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-perspective-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: path)
            print("PERSPECTIVE_RENDER=" + path.path)
        }

        XCTAssertEqual(UserDefaults.standard.data(forKey: DailyPlanStore.key), beforePlans)
        XCTAssertEqual(UserDefaults.standard.data(forKey: ReviewRhythmStore.dismissalsKey), beforeRhythm)
        XCTAssertTrue(completed[0].isTitleChecked)
        XCTAssertEqual(tomorrow.cards.count, 2)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusOverflowRetainsNativeScrollingToLastMatchingItem
    /// @brief      Verify that focus Overflow Retains Native Scrolling To Last Matching Item
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(entries.count, 9)`;
    ///             `XCTAssertTrue(inner.isScrollEnabled)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testFocusOverflowRetainsNativeScrollingToLastMatchingItem() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        let cards = (1 ... 9).map
        {
            KanbanCard(id: $0, word: "Focus task \($0)", listTitle: "Today", checklists: [])
        }

        let list = KanbanList(id: 1, title: "Today", cards: cards)
        let prefs = LocalProfilePreferences(todayFocusItemCount: 4)
        let entries = prefs.todayFocusEntries(in: cards)
        XCTAssertEqual(entries.count, 9)
        let host = UIHostingController(
            rootView: ScrollView
            {

                TodayFocusSection(
                    list: list, cards: cards, entries: entries, groupsBySection: false, chronological: false,
                    onToggleCard:
                    {
                        _ in
                        XCTFail("Scrolling must not edit")
                    }, onOpenCard:
                    {
                        _ in
                    },
                    onDeleteCard:
                    {
                        _ in
                        XCTFail("Scrolling must not delete");
                        return false
                    }, onOpenTodayList:
                    {

                    }
                )
                .padding(20)
            })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host;
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        // Recurse through parent scroll views as well as ordinary containers.


        ///
        /// @fcn        PlenactBoardDocumentTests.testFocusOverflowRetainsNativeScrollingToLastMatchingItem.allScrollViews
        /// @brief      Find all scroll views in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func allScrollViews(_ view: UIView) -> [UIScrollView]
        {

            var result = (view as? UIScrollView).map
            {
                [$0]
            }
            ?? []
            result += view.subviews.flatMap(allScrollViews)
            return result
        }

        let inner = try XCTUnwrap(
            allScrollViews(host.view).first
            {

                $0.bounds.height > 0 && $0.bounds.height < 350 && $0.contentSize.height > $0.bounds.height + 100
            })
        XCTAssertTrue(inner.isScrollEnabled)
        let end = inner.contentSize.height - inner.bounds.height + inner.adjustedContentInset.bottom
        inner.setContentOffset(CGPoint(x: 0, y: end), animated: false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(inner.contentOffset.y, 100)
        let settledEnd = inner.contentSize.height - inner.bounds.height + inner.adjustedContentInset.bottom
        inner.setContentOffset(CGPoint(x: 0, y: settledEnd), animated: false)
        XCTAssertEqual(inner.contentOffset.y, settledEnd, accuracy: 2)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testFocusShapeRendersDefaultGroupedAndCompletedPreviewsWithoutMutations
    /// @brief      Verify that focus Shape Renders Default Grouped And Completed Previews Without Mutations
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(list, original)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testFocusShapeRendersDefaultGroupedAndCompletedPreviewsWithoutMutations() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        var list = KanbanList(id: 1, title: "Monday", cards: [])
        list.cards = [
            KanbanCard(id: 90, word: "--- Looking forward to", listTitle: "Monday", isDivider: true, checklists: [])
        ]
        list.cards += (1 ... 6).map
        {

            KanbanCard(
                id: $0, word: "\($0 == 1 ? "Dinner with family" : "Make time for something meaningful")",
                listTitle: "Monday", isTitleChecked: $0 == 2, checklists: [])
        }

        list.cards.insert(
            KanbanCard(id: 91, word: "--- Must happen", listTitle: "Monday", isDivider: true, checklists: []), at: 4)
        list.cards[1].startDate = .now
        let original = list
        for (name, preference, scheme, width) in [
            ("default", LocalProfilePreferences(), ColorScheme.light, CGFloat(393)),
            (
                                "grouped",
                                LocalProfilePreferences(
                                    todayFocusItemCount: 0, todayFocusOrder: .chronological, todayFocusGroupsBySection: true,
                                    todayFocusHidesCompleted: false), .light, 393
            ),
            (
                                "dark-tablet", LocalProfilePreferences(todayFocusItemCount: 0, todayFocusGroupsBySection: true), .dark,
                                820
            ),
            ("up-next", LocalProfilePreferences(todayFocusIncludesUpNext: true), .light, 393),
            ("filtered-empty", LocalProfilePreferences(todayFocusIncludesImportant: true), .light, 393)
        ]
        {

            let view = ScrollView
            {

                TodayFocusSection(
                    list: list, cards: list.cards.filter
                    {
                        !$0.isSectionDivider
                    },
                    entries: preference.todayFocusEntries(in: list.cards),
                    groupsBySection: preference.todayFocusGroupsBySection,
                    chronological: preference.todayFocusOrder == .chronological,
                    includesImportant: preference.todayFocusIncludesImportant,
                    includesBookmarked: preference.todayFocusIncludesBookmarked,
                    includesUpNext: preference.todayFocusIncludesUpNext,
                    onToggleCard:
                    {
                        _ in
                        XCTFail("Rendering must not toggle")
                    }, onOpenCard:
                    {
                        _ in
                    },
                    onDeleteCard:
                    {
                        _ in
                        XCTFail("Rendering must not delete");
                        return false
                    }, onOpenTodayList:
                    {

                    }
                )
                .padding(20)
            } .background(Color(.systemGroupedBackground)).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-focus-shape-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("FOCUS_SHAPE_RENDER=" + url.path)
            XCTAssertEqual(list, original)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testLibraryHelpRendersGuidesWithoutChangingPlanningData
    /// @brief      Verify that library Help Renders Guides Without Changing Planning Data
    /// @details    Exercises `keys.map`, `UserDefaults.standard.data`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks `XCTAssertEqual(keys.map {
    ///             UserDefaults.standard.data(forKey: $0) }, before)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testLibraryHelpRendersGuidesWithoutChangingPlanningData() async throws
    {

        let keys = [
            DailyPlanStore.key, WeeklyReviewStore.key, PeriodicReviewStore.key, PlanningCalendarStore.key,
                            "Plenact.PersonalCollections.v1"
        ]
        let before = keys.map
        {
            UserDefaults.standard.data(forKey: $0)
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        let article = try XCTUnwrap(PlenactHelpCatalog.articles.first
            {
                $0.id == "rhythm"
            })
        let views: [AnyView] = [
            AnyView(NavigationStack
                {
                    List
                    {
                        LibraryHelpRows(query: "")
                    }

                }),
            AnyView(PlenactHelpArticleView(article: article))
        ]
        for (index, view) in views.enumerated()
        {

            let host = UIHostingController(rootView: view)
            window.rootViewController = host;
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852);

            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-help-\(index).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("HELP_RENDER=\(url.path)")
        }

        XCTAssertEqual(keys.map
            {
                UserDefaults.standard.data(forKey: $0)
            }, before)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPeriodicReviewRendersSetupAndAllStepsWithoutWriting
    /// @brief      Verify that periodic Review Renders Setup And All Steps Without Writing
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertEqual(defaults.data(forKey:
    ///             PeriodicReviewStore.key), bytes)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPeriodicReviewRendersSetupAndAllStepsWithoutWriting() async throws
    {

        let name = "PlenactTests.PeriodicRender." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        var baseline: PeriodicReviewRecord?
        for step in -1 ... 2
        {

            if step >= 0
            {

                var record =
                baseline
                ?? PeriodicReviewRecord(title: "A meaningful quarter", start: .now, end: .now, calendar: .current)
                record.step = step
                if record.objectives.isEmpty
                {

                    record.objectives = [ReviewObjective(title: "Build a sustainable routine")]
                }

                baseline = try PeriodicReviewStore.save(record, replacing: baseline, to: defaults)
            }

            let bytes = defaults.data(forKey: PeriodicReviewStore.key)
            let host = UIHostingController(
                rootView: PeriodicReviewView(
                    calendar: .current, defaults: defaults, initialReviewID: step < 0 ? nil : baseline?.id))
            window.rootViewController = host;
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852);

            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-periodic-\(step).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("PERIODIC_RENDER=\(url.path)")
            XCTAssertEqual(defaults.data(forKey: PeriodicReviewStore.key), bytes)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testReviewRhythmInvitationsAndSettingsRenderWithoutWritingOrRequestingPermission
    /// @brief      Verify that review Rhythm Invitations And Settings Render Without Writing Or Requesting Permission
    /// @details    Exercises `Calendar.current.component`, `ReviewRhythmStore.save`,
    ///             `UIApplication.shared.connectedScenes.compactMap`. Checks `XCTAssertEqual(defaults.data(forKey:
    ///             ReviewRhythmStore.key), bytes)`; `XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testReviewRhythmInvitationsAndSettingsRenderWithoutWritingOrRequestingPermission() async throws
    {

        let suite = "ReviewRhythmRender." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        var preferences = ReviewRhythmPreferences();
        preferences.dailyMinutes = 0;
        preferences.weeklyMinutes = 0
        preferences.weeklyWeekday = Calendar.current.component(.weekday, from: .now)
        try ReviewRhythmStore.save(preferences, to: defaults)
        let bytes = defaults.data(forKey: ReviewRhythmStore.key)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }

        for scheme in [ColorScheme.light, .dark]
        {

            let view = ScrollView
            {

                ReviewRhythmPanel(
                    onOpen:
                    {
                        _ in
                        XCTFail("Rendering must not open")
                    }, onSettings:
                    {

                    }, defaults: defaults
                )
                .padding(20)
            } .background(Color(.systemGroupedBackground)).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-review-rhythm-\(scheme).png")
            try XCTUnwrap(image.pngData()).write(to: url);
            print("REVIEW_RHYTHM_RENDER=" + url.path)
        }

        window.rootViewController = UIHostingController(rootView: ReviewRhythmSettingsView())
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(defaults.data(forKey: ReviewRhythmStore.key), bytes)
        XCTAssertNil(defaults.object(forKey: DailyPlanStore.key))
        XCTAssertNil(defaults.object(forKey: WeeklyReviewStore.key))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDailyHistoryRendersCurrentPastAndEmptyDaysWithoutWriting
    /// @brief      Verify that daily History Renders Current Past And Empty Days Without Writing
    /// @details    Exercises `plan.recordCheckIn`, `date.addingTimeInterval`, `CheckInMood.custom`. Checks
    ///             `XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), bytes)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testDailyHistoryRendersCurrentPastAndEmptyDaysWithoutWriting() async throws
    {

        let name = "PlenactTests.DailyHistoryRender." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer
        {
            defaults.removePersistentDomain(forName: name)
        }

        let calendar = Calendar.current
        let today = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let missing = calendar.date(byAdding: .day, value: -2, to: today)!
        for date in [today, yesterday]
        {

            var plan = DailyPlan(date: date)
            plan.intention = "Leave room for real life"
            plan.recordCheckIn(changed: "A useful start", sources: [], at: date, mood: CheckInMoodChoice.good.mood)
            plan.recordCheckIn(
                changed: "Adjusted my plan", sources: [], at: date.addingTimeInterval(60),
                mood: CheckInMood.custom(emoji: "🌤️", label: "Quietly hopeful"))
            _ = try DailyPlanStore.save(plan, replacing: nil, to: defaults)
        }

        let bytes = defaults.data(forKey: DailyPlanStore.key)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        for (index, date) in [today, yesterday, missing].enumerated()
        {

            let host = UIHostingController(
                rootView: DailyHistoryReviewView(date: date, calendar: calendar, defaults: defaults))
            window.rootViewController = host;
            window.frame = CGRect(x: 0, y: 0, width: 744, height: 1133);

            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                    "plenact-daily-history-\(index).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("DAILY_HISTORY_RENDER=\(url.path)")
            XCTAssertEqual(defaults.data(forKey: DailyPlanStore.key), bytes)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCheckInRendersWithoutSavingOrChangingSources
    /// @brief      Verify that check In Renders Without Saving Or Changing Sources
    /// @details    Exercises `DatedPlanningWeek.make`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertEqual(saves, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCheckInRendersWithoutSavingOrChangingSources() async throws
    {

        let week = DatedPlanningWeek.make(for: .now)
        let access = PlanningCalendarAccess(
            document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [],
            saveWeek:
            {
                _ in
                false
            }, openCurrentWeek:
            {

            }, openToday:
            {

            }, openLibraryCard:
            {
                _ in
            },
            saveLibrary:
            {
                _ in
                false
            })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        var saves = 0
        let host = UIHostingController(
            rootView: TodayCheckInView(
                plan: .constant(DailyPlan(date: .now)), date: .now,
                onSave:
                {

                    saves += 1;
                    return true
                }
            ).environment(\.planningCalendarAccess, access))
        window.rootViewController = host;
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852);

        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
        {
            _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-checkin.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("CHECKIN_RENDER=\(url.path)")
        XCTAssertEqual(saves, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testEveningReviewRendersAllStepsWithoutSaving
    /// @brief      Verify that evening Review Renders All Steps Without Saving
    /// @details    Exercises `DatedPlanningWeek.make`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertEqual(saves, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testEveningReviewRendersAllStepsWithoutSaving() async throws
    {

        let week = DatedPlanningWeek.make(for: .now)
        let access = PlanningCalendarAccess(
            document: PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week]), library: [],
            saveWeek:
            {
                _ in
                false
            }, openCurrentWeek:
            {

            }, openToday:
            {

            }, openLibraryCard:
            {
                _ in
            },
            saveLibrary:
            {
                _ in
                false
            })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        var saves = 0
        for step in 0 ... 2
        {

            var plan = DailyPlan(date: .now)
            plan.eveningReview = DailyEveningReview();
            plan.eveningReview?.step = step
            let host = UIHostingController(
                rootView: TodayReviewView(
                    plan: .constant(plan), date: .now, baseline: nil,
                    onSave:
                    {

                        saves += 1;
                        return true
                    }, onCommitted:
                    {
                        _ in
                        saves += 1
                    }
                ).environment(\.planningCalendarAccess, access))
            window.rootViewController = host;
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852);

            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-review-step-\(step).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("REVIEW_RENDER=\(url.path)")
        }

        XCTAssertEqual(saves, 0)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayVisionRendersMorningAndRealityStepsWithoutSaving
    /// @brief      Verify that today Vision Renders Morning And Reality Steps Without Saving
    /// @details    Exercises `DatedPlanningWeek.make`, `UIApplication.shared.connectedScenes.compactMap`,
    ///             `scene.windows.first`. Checks `XCTAssertEqual(saves, 0)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testTodayVisionRendersMorningAndRealityStepsWithoutSaving() async throws
    {

        let week = DatedPlanningWeek.make(for: .now)
        let document = PlanningCalendarDocument(currentWeekKey: week.startKey, weeks: [week])
        let access = PlanningCalendarAccess(
            document: document, library: [], saveWeek:
            {
                _ in
                false
            }, openCurrentWeek:
            {

            }, openToday:
            {

            },
            openLibraryCard:
            {
                _ in
            }, saveLibrary:
            {
                _ in
                false
            })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            previous?.makeKeyAndVisible()
        }

        var saves = 0
        for step in [0, 2]
        {

            var plan = DailyPlan(date: .now);
            plan.visionStep = step
            plan.intention = "One useful step"
            let host = UIHostingController(
                rootView: TodayVisionView(
                    plan: .constant(plan), date: .now,
                    onSave:
                    {

                        saves += 1;
                        return true
                    }
                ).environment(\.planningCalendarAccess, access))
            window.rootViewController = host
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {
                _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-vision-step-\(step).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("VISION_RENDER=\(url.path)")
        }

        XCTAssertEqual(saves, 0, "Opening a morning review must not save or move anything")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCreatedContentRevealScrollsLongDayListsInBothLayouts
    /// @brief      Verify that created Content Reveal Scrolls Long Day Lists In Both Layouts
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `CreatedContentReveal.shared.complete`. Checks `XCTAssertLessThan(native.contentOffset.y, 100)`;
    ///             `XCTAssertGreaterThan(native.contentOffset.y, 100)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCreatedContentRevealScrollsLongDayListsInBothLayouts() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            if let target = CreatedContentReveal.shared.target
            {
                CreatedContentReveal.shared.complete(target)
            }

            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testCreatedContentRevealScrollsLongDayListsInBothLayouts.collection
        /// @brief      Find collection in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UICollectionView. Returns the first qualifying match,
        ///             or nil when none is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UICollectionView?) matching or resolved value, or nil when unavailable
        ///
        func collection(in view: UIView) -> UICollectionView?
        {

            if let collection = view as? UICollectionView
            {
                return collection
            }

            return view.subviews.lazy.compactMap
            {
                collection(in: $0)
            } .first
        }

        for mode in SingleListViewMode.allCases
        {

            for width: CGFloat in [393, 820]
            {

                let owner = UUID()
                defer
                {

                    UserDefaults.standard.removeObject(
                        forKey: BoardViewportMemory.prefix + owner.uuidString + ".focused.8")
                }

                var list = KanbanList(id: 8, title: "Creation test", cards: [])
                list.cards = (0 ..< 40).map
                {

                    list.makeItem(id: $0, title: "Item \($0)", presentationOverride: mode == .noteList ? .note : .card)
                }

                list.setSingleListViewMode(mode)
                let target = try XCTUnwrap(list.cards.last)
                let view = TodayListDetailView(
                    lists: .constant([list]), reservedLists: [], labelLibrary: .constant(.starter),
                    savedCardIDs: .constant([]), listID: list.id, currentUserName: "Test", onClose:
                    {

                    }, onOpenWeek:
                    {

                    },
                    onPermanentDelete:
                    {
                        _ in
                        false
                    }
                )
                .environment(\.cardMovementSource, owner)
                let host = UIHostingController(rootView: view)
                window.frame = CGRect(x: 0, y: 0, width: width, height: width < 500 ? 852 : 1180)
                window.rootViewController = host;
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(250))
                let native = try XCTUnwrap(collection(in: host.view))
                XCTAssertLessThan(native.contentOffset.y, 100)
                CreatedContentReveal.shared.request(listID: list.id, card: target)
                try await Task.sleep(for: .milliseconds(1100))
                host.view.layoutIfNeeded()
                XCTAssertGreaterThan(
                    native.contentOffset.y, 100, "New item must be revealed in \(mode), width \(width)")
                XCTAssertLessThan(native.contentSize.height - native.contentOffset.y - native.bounds.height, 220)
                XCTAssertNil(CreatedContentReveal.shared.target)
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image
                {
                    _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }

                let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                                "plenact-created-\(mode.rawValue)-\(Int(width)).png")
                try XCTUnwrap(image.pngData()).write(to: url)
                print("CREATION_REVEAL_RENDER=" + url.path)
                window.rootViewController = nil
            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardCardSwipeRoutingUsesTheInitialPhysicalRightQuarter
    /// @brief      Verify the seventy-five percent boundary across preview sizes and positions
    /// @details    Uses actual Card coordinates rather than screen coordinates, with no ownership
    ///             change based on later finger travel. Invalid and out-of-Card starts are rejected.
    ///
    /// @return     (Void) records routing assertions
    ///
    func testBoardCardSwipeRoutingUsesTheInitialPhysicalRightQuarter()
    {

        for width: CGFloat in [100, 240, 320, 480]
        {

            let bounds = CGRect(x: 20, y: 10, width: width, height: 80)
            for fraction: CGFloat in [0, 0.25, 0.5, 0.749]
            {

                XCTAssertFalse(
                    BoardCardSwipeRouting.routesToBoard(start: CGPoint(x: 20 + width * fraction, y: 30), bounds: bounds)
                )
            }

            for fraction: CGFloat in [0.75, 0.85, 0.99]
            {

                XCTAssertTrue(
                    BoardCardSwipeRouting.routesToBoard(start: CGPoint(x: 20 + width * fraction, y: 30), bounds: bounds)
                )
            }

            XCTAssertFalse(
                BoardCardSwipeRouting.routesToBoard(start: CGPoint(x: bounds.maxX + 1, y: 30), bounds: bounds))
            XCTAssertFalse(BoardCardSwipeRouting.routesToBoard(start: CGPoint(x: bounds.midX, y: 100), bounds: bounds))
        }

        XCTAssertFalse(BoardCardSwipeRouting.routesToBoard(start: .zero, bounds: .zero))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testWeekAndLibraryBoardsPrioritizeInnerListSwipesWithoutDisablingScrolling
    /// @brief      Verify that week And Library Boards Prioritize Inner List Swipes Without Disabling Scrolling
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKeyAndVisible`. Checks `XCTAssertGreaterThan(BoardListSwipePriority.install(for:
    ///             list), 0)`; `XCTAssertTrue(list.isScrollEnabled)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testWeekAndLibraryBoardsPrioritizeInnerListSwipesWithoutDisablingScrolling() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testWeekAndLibraryBoardsPrioritizeInnerListSwipesWithoutDisablingScrolling.collections
        /// @brief      Find collections in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UICollectionView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UICollectionView]) resulting values in the ordering described above
        ///
        func collections(in view: UIView) -> [UICollectionView]
        {

            ((view as? UICollectionView).map
                {
                    [$0]
                }
                ?? []) + view.subviews.flatMap
            {
                collections(in: $0)
            }

        }

        for personal in [false, true]
        {

            let owner = UUID()
            defer
            {
                UserDefaults.standard.removeObject(forKey: BoardViewportMemory.prefix + owner.uuidString)
            }

            let cards = [
                KanbanCard(id: 1, word: "Card", listTitle: "First", checklists: []),
                KanbanCard(id: 2, word: "Note", listTitle: "First", checklists: [], presentation: .note)
            ]
            let lists = [KanbanList(id: 0, title: "First", cards: cards), KanbanList(id: 1, title: "Second", cards: [])]
            let host = UIHostingController(
                rootView: ContentView(
                    lists: .constant(lists), allowsAddingLists: false,
                    retainedAttachmentLists:
                    {
                        []
                    }, personalCollectionID: personal ? owner : nil,
                    viewportOwnerID: owner))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            let list = try XCTUnwrap(collections(in: host.view).first)
            XCTAssertGreaterThan(BoardListSwipePriority.install(for: list), 0)
            let gate = try XCTUnwrap(list.gestureRecognizers?.compactMap
                {
                    $0 as? BoardCardSwipeGate
                } .first)
            XCTAssertEqual(gate.markers.allObjects.count, 2)
            XCTAssertTrue(gate.markers.allObjects.allSatisfy
                {
                    $0.bounds.width > 0
                })
            XCTAssertFalse(gate.cancelsTouchesInView)
            XCTAssertTrue(list.isScrollEnabled)
            XCTAssertTrue(list.panGestureRecognizer.isEnabled)
            var ancestor = list.superview
            var board: UIScrollView?
            while let view = ancestor
            {

                if let candidate = view as? UIScrollView, candidate.contentSize.width > candidate.bounds.width + 1
                {

                    board = candidate;
                    break
                }

                ancestor = view.superview
            }

            XCTAssertTrue(try XCTUnwrap(board).isScrollEnabled)
            XCTAssertTrue(try XCTUnwrap(board).panGestureRecognizer.isEnabled)
            XCTAssertTrue(
                gate.gestureRecognizer(
                    gate, shouldRecognizeSimultaneouslyWith: try XCTUnwrap(board).panGestureRecognizer))
            XCTAssertFalse(gate.gestureRecognizer(gate, shouldRecognizeSimultaneouslyWith: list.panGestureRecognizer))
            if personal
            {

                let standalone = UIHostingController(
                    rootView: ContentView(
                        lists: .constant([lists[0]]), allowsAddingLists: false,
                        fillsAvailableListWidth: true, retainedAttachmentLists:
                        {
                            []
                        }, personalCollectionID: owner,
                        viewportOwnerID: owner))
                window.rootViewController = standalone
                try await Task.sleep(for: .milliseconds(350))
                let standaloneList = try XCTUnwrap(collections(in: standalone.view).first)
                XCTAssertFalse(
                    standaloneList.gestureRecognizers?.contains
                    {
                        $0 is BoardCardSwipeGate
                    }
                    == true,
                                                    "A standalone List must retain full-width native swipe-to-delete")
            }

            print(
                                    "BOARD_LIST_NATIVE_PANS="
                                    + (list.gestureRecognizers ?? []).map
                                    {
                                        String(describing: type(of: $0))
                                    } .joined(separator: ","))
            window.rootViewController = nil
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testSloganManualReadingAllowsOverscrollAndResumesWithoutJumping
    /// @brief      Verify that slogan Manual Reading Allows Overscroll And Resumes Without Jumping
    /// @details    Exercises `TodaySloganMotion.draggedPosition`, `TodaySloganMotion.position`. Checks
    ///             `XCTAssertEqual(TodaySloganMotion.draggedPosition(start: -100, translation: 500, viewport: 300,
    ///             textWidth: 700), 400)`; `XCTAssertEqual(TodaySloganMotion.draggedPosition(start: -100,
    ///             translation: -500, viewport: 300, textWidth: 700), -600)`.
    ///
    /// @return     (Void) no return value
    ///
    func testSloganManualReadingAllowsOverscrollAndResumesWithoutJumping()
    {

        XCTAssertEqual(
            TodaySloganMotion.draggedPosition(start: -100, translation: 500, viewport: 300, textWidth: 700), 400)
        XCTAssertEqual(
            TodaySloganMotion.draggedPosition(start: -100, translation: -500, viewport: 300, textWidth: 700), -600)
        XCTAssertEqual(
            TodaySloganMotion.draggedPosition(start: 0, translation: -50, viewport: 300, textWidth: 100), -50)
        XCTAssertEqual(
            TodaySloganMotion.draggedPosition(start: 400, translation: 5000, viewport: 300, textWidth: 700), 5400)
        XCTAssertEqual(
            TodaySloganMotion.draggedPosition(start: -600, translation: -5000, viewport: 300, textWidth: 700), -5600)
        XCTAssertEqual(TodaySloganMotion.position(elapsed: -1, start: -5600, viewport: 300, textWidth: 700), -5600)
        XCTAssertEqual(
            TodaySloganMotion.position(elapsed: 1, start: -5600, viewport: 300, textWidth: 700), 264.9, accuracy: 0.001)
        XCTAssertEqual(
            TodaySloganMotion.position(elapsed: 1, start: 5400, viewport: 300, textWidth: 700), 264.9, accuracy: 0.001)
        // A future resume date produces negative elapsed time throughout the reading pause.
        XCTAssertEqual(TodaySloganMotion.position(elapsed: -1, start: -150, viewport: 300, textWidth: 700), -150)
        XCTAssertEqual(TodaySloganMotion.position(elapsed: 0, start: -150, viewport: 300, textWidth: 700), -150)
        XCTAssertEqual(
            TodaySloganMotion.position(elapsed: 1, start: -150, viewport: 300, textWidth: 700), -185.1, accuracy: 0.001)
        // Once the text exits, the next pass enters from the right.
        XCTAssertEqual(
            TodaySloganMotion.position(elapsed: 1, start: -700, viewport: 300, textWidth: 700), 264.9, accuracy: 0.001)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCollectionBackgroundPresetsRenderOffline
    /// @brief      Verify that collection Background Presets Render Offline
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`, `.flexible`.
    ///             Uses the fixture and assertions below to verify collection Background Presets Render Offline.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCollectionBackgroundPresetsRenderOffline() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(
            rootView: LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12)
            {

                ForEach(CollectionBackgroundPreset.allCases.filter
                    {
                        $0 != .photo
                    })
                {
                    preset in
                    CollectionBackgroundSurface(background: CollectionBackground(preset: preset))
                    .frame(height: 160)
                    .overlay(alignment: .bottomLeading)
                    {

                        Text(preset.title).font(.headline).foregroundStyle(.white).padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

            } .padding(16).background(Color(.systemGroupedBackground)))
        host.safeAreaRegions = []
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 560)
        window.rootViewController = host;
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(200))
        host.view.frame = window.bounds;
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image
        {
            _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        let attachment = XCTAttachment(image: image);
        attachment.name = "Personal background presets";

        attachment.lifetime = .keepAlways;
        add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-background-presets.png")
        try image.pngData()?.write(to: url)
        print("BACKGROUND_PRESETS_PATH=\(url.path)")
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testPersonalBoardBackgroundAndWeekDefaultRenderSeparately
    /// @brief      Verify that personal Board Background And Week Default Render Separately
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`, `.constant`.
    ///             Uses the fixture and assertions below to verify personal Board Background And Week Default Render
    ///             Separately.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testPersonalBoardBackgroundAndWeekDefaultRenderSeparately() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let owner = PersonalCollection(title: "Garden plans", kind: .board)
        var appearance = BoardAppearance()
        appearance.collectionBackground = CollectionBackground(preset: .sage)
        for dated in [false, true]
        {

            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(
                rootView: ContentView(
                    lists: .constant(owner.lists), boardTitle: dated ? "Plenact" : "Garden plans",
                    boardSubtitle: dated ? "This Week" : "Board", onClose:
                    {

                    }, onListsChanged:
                    {
                        _ in
                    },
                    personalCollectionID: dated ? nil : owner.id, boardAppearance: .constant(appearance)))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            defer
            {
                window.isHidden = true;
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(250))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image
            {
                _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            let attachment = XCTAttachment(image: image);

            attachment.name = dated ? "Week keeps default" : "Personal Board sage background"
            attachment.lifetime = .keepAlways;
            add(attachment)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                dated ? "plenact-week-default.png" : "plenact-personal-background.png")
            try image.pngData()?.write(to: url)
            print("BOARD_BACKGROUND_PATH=\(url.path)")
        }

        previous?.makeKey()
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testBoardViewportMemoryRoundTripsAndKeepsOwnersSeparate
    /// @brief      Verify that board Viewport Memory Round Trips And Keeps Owners Separate
    /// @details    Exercises `first.record`, `first.flush`. Checks `XCTAssertEqual(reopened.state, first.state)`;
    ///             `XCTAssertEqual(other.state.scale, 1)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testBoardViewportMemoryRoundTripsAndKeepsOwnersSeparate() throws
    {

        let suite = "Plenact.ViewportTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let first = BoardViewportMemory(owner: "first", defaults: defaults)
        first.state.scale = 0.48;
        first.state.panoramic = true;
        first.state.gallery = true
        first.state.presentation = "overview";
        first.state.visibleListID = 8
        first.record(430, for: "horizontal");
        first.record(680, for: "list:8");
        first.flush()
        let reopened = BoardViewportMemory(owner: "first", defaults: defaults)
        XCTAssertEqual(reopened.state, first.state)
        let other = BoardViewportMemory(owner: "second", defaults: defaults)
        XCTAssertEqual(other.state.scale, 1)
        XCTAssertTrue(other.state.offsets.isEmpty)
        first.record(510, for: "list:9");
        first.flush()
        XCTAssertEqual(BoardViewportMemory(owner: "first", defaults: defaults).state.offsets["list:8"], 680)
        first.record(.infinity, for: "horizontal")
        XCTAssertEqual(first.state.offsets["horizontal"], 430)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testViewportProbeRestoresNativeOffsetsInBothDirections
    /// @brief      Verify that viewport Probe Restores Native Offsets In Both Directions
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(offset, 470)`;
    ///             `XCTAssertEqual(memory.state.offsets["position"], 470)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testViewportProbeRestoresNativeOffsetsInBothDirections() async throws
    {

        let suite = "Plenact.ScrollRestoreTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer
        {
            defaults.removePersistentDomain(forName: suite)
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        defer
        {
            previous?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testViewportProbeRestoresNativeOffsetsInBothDirections.nativeScroll
        /// @brief      Find native scroll in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns the first qualifying match, or
        ///             nil when none is present.
        ///
        /// @param[in]  view        Native view inspected or synchronized by the operation
        /// @param[in]  horizontal  Whether the probe observes the horizontal rather than vertical axis
        ///
        /// @return     (UIScrollView?) matching or resolved value, or nil when unavailable
        ///
        func nativeScroll(_ view: UIView, horizontal: Bool) -> UIScrollView?
        {

            if let scroll = view as? UIScrollView,
            horizontal
            ? scroll.contentSize.width > scroll.bounds.width + 1
            : scroll.contentSize.height > scroll.bounds.height + 1
            {

                return scroll
            }

            for child in view.subviews
            {
                if let found = nativeScroll(child, horizontal: horizontal)
                {
                    return found
                }

            }

            return nil
        }

        for horizontal in [true, false]
        {

            let owner = horizontal ? "horizontal-board" : "vertical-list"
            for reopening in [false, true]
            {

                let memory = BoardViewportMemory(owner: owner, defaults: defaults)
                let host = UIHostingController(
                    rootView: ScrollView(horizontal ? .horizontal : .vertical)
                    {

                        Color.gray.frame(width: horizontal ? 2200 : 220, height: horizontal ? 120 : 3000)
                        .background(
                            BoardViewportScrollProbe(memory: memory, key: "position", horizontal: horizontal))
                    } .frame(width: 260, height: 230))
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = host;
                window.makeKeyAndVisible()
                defer
                {
                    window.isHidden = true;
                    window.rootViewController = nil
                }

                try await Task.sleep(for: .milliseconds(250))
                host.view.layoutIfNeeded()
                let scroll = try XCTUnwrap(nativeScroll(host.view, horizontal: horizontal))
                if reopening
                {

                    let offset =
                    horizontal
                    ? scroll.contentOffset.x + scroll.adjustedContentInset.left
                    : scroll.contentOffset.y + scroll.adjustedContentInset.top
                    XCTAssertEqual(offset, 470, accuracy: 2)
                }
                else
                {

                    scroll.setContentOffset(horizontal ? CGPoint(x: 470, y: 0) : CGPoint(x: 0, y: 470), animated: false)
                    try await Task.sleep(for: .milliseconds(50))
                    memory.flush()
                    XCTAssertEqual(memory.state.offsets["position"], 470)
                }

            }

        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testZoomedBoardRestoresItsRealHorizontalViewport
    /// @brief      Verify that zoomed Board Restores Its Real Horizontal Viewport
    /// @details    Exercises `UserDefaults.standard.removeObject`, `initial.flush`, `(0..<10).map`. Checks
    ///             `XCTAssertEqual(scroll.contentOffset.x + scroll.adjustedContentInset.left, 420)`;
    ///             `XCTAssertEqual(list.contentOffset.y + list.adjustedContentInset.top, 350)`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testZoomedBoardRestoresItsRealHorizontalViewport() async throws
    {

        let owner = UUID()
        let key = BoardViewportMemory.prefix + owner.uuidString
        defer
        {
            UserDefaults.standard.removeObject(forKey: key)
        }

        let initial = BoardViewportMemory(owner: owner.uuidString)
        initial.state.scale = 0.62;
        initial.state.panoramic = true;
        initial.state.presentation = "standard"
        initial.flush()
        var lists = (0 ..< 10).map
        {
            KanbanList(id: $0, title: "List \($0)", cards: [])
        }

        lists[0].cards = (0 ..< 30).map
        {
            KanbanCard(id: $0, word: "Card \($0)", listTitle: lists[0].title)
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        defer
        {
            previous?.makeKey()
        }


        ///
        /// @fcn        PlenactBoardDocumentTests.testZoomedBoardRestoresItsRealHorizontalViewport.scrolls
        /// @brief      Find scrolls in the hosted view hierarchy
        /// @details    Recursively inspects native subviews for UIScrollView. Returns all collected matches in
        ///             hierarchy order.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     ([UIScrollView]) resulting values in the ordering described above
        ///
        func scrolls(_ view: UIView) -> [UIScrollView]
        {

            ((view as? UIScrollView).map
                {
                    [$0]
                }
                ?? []) + view.subviews.flatMap(scrolls)
        }

        for reopening in [false, true]
        {

            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(
                rootView: ContentView(
                    lists: .constant(lists), boardTitle: "Viewport test",
                    onListsChanged:
                    {
                        _ in
                    }, personalCollectionID: owner))
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host;
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(500))
            host.view.layoutIfNeeded()
            let scroll = try XCTUnwrap(
                scrolls(host.view).first
                {
                    !($0 is UICollectionView) && $0.contentSize.width > $0.bounds.width + 100
                })
            if reopening
            {

                XCTAssertEqual(scroll.contentOffset.x + scroll.adjustedContentInset.left, 420, accuracy: 3)
                scroll.setContentOffset(
                    CGPoint(x: -scroll.adjustedContentInset.left, y: scroll.contentOffset.y), animated: false)
                try await Task.sleep(for: .milliseconds(300))
                let vertical = scrolls(host.view).compactMap
                {
                    $0 as? UICollectionView
                } .first
                {

                    $0.contentSize.height > $0.bounds.height + 100
                }

                let list = try XCTUnwrap(vertical)
                XCTAssertEqual(list.contentOffset.y + list.adjustedContentInset.top, 350, accuracy: 3)
            }
            else
            {

                let vertical = scrolls(host.view).compactMap
                {
                    $0 as? UICollectionView
                } .first
                {

                    $0.contentSize.height > $0.bounds.height + 100
                }

                let list = try XCTUnwrap(vertical)
                list.setContentOffset(
                    CGPoint(x: list.contentOffset.x, y: 350 - list.adjustedContentInset.top), animated: false)
                try await Task.sleep(for: .milliseconds(450))
                XCTAssertEqual(
                    BoardViewportMemory(owner: owner.uuidString).state.offsets["list:0"] ?? -1, 350, accuracy: 3)
                scroll.setContentOffset(
                    CGPoint(x: 420 - scroll.adjustedContentInset.left, y: scroll.contentOffset.y), animated: false)
                try await Task.sleep(for: .milliseconds(450))
                XCTAssertEqual(
                    BoardViewportMemory(owner: owner.uuidString).state.offsets["horizontal"] ?? -1, 420, accuracy: 3)
            }

            window.isHidden = true;
            window.rootViewController = nil
            try await Task.sleep(for: .milliseconds(100))
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCustomListPreviewColorsRenderWithoutEditingContent
    /// @brief      Verify that custom List Preview Colors Render Without Editing Content
    /// @details    Exercises `UIApplication.shared.connectedScenes.compactMap`, `scene.windows.first`,
    ///             `previous?.makeKey`. Checks `XCTAssertEqual(originals, [card, note])`.
    ///
    /// @return     (Void) no return value
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    @MainActor
    func testCustomListPreviewColorsRenderWithoutEditingContent() async throws
    {

        var card = KanbanCard(id: 92, word: "Plan the garden", listTitle: "Garden")
        card.subtitleOverride = "Choose seeds and make room to grow"
        var note = KanbanCard(id: 93, word: "Garden reflections", listTitle: "Garden", presentation: .note)
        note.descriptionOverride = "A few ideas for next season, with space for something new."
        let originals = [card, note]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(
            rootView: VStack(spacing: 16)
            {

                ForEach(originals)
                {
                    item in
                    KanbanCardView(
                        card: item, height: 140, displaySettings: BoardDisplaySettings(),
                        titleColor: .teal, supportingTextColor: .plum, labelLibrary: .starter,
                        onUpdateCard:
                        {
                            _ in
                            XCTFail("Colors must not edit content")
                        },
                        onDeleteCard:
                        {
                            XCTFail("Colors must not delete")
                        },
                        onArchiveCard:
                        {
                            XCTFail("Colors must not archive")
                        },
                        onToggle:
                        {
                            XCTFail("Colors must not complete")
                        })
                }

            } .padding(20).background(Color(.systemGroupedBackground)))
        host.safeAreaRegions = []
        window.frame = CGRect(x: 0, y: 0, width: 340, height: 390)
        window.rootViewController = host;
        window.makeKeyAndVisible()
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        try await Task.sleep(for: .milliseconds(200))
        host.view.frame = window.bounds;
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image
        {
            _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        let attachment = XCTAttachment(image: image);
        attachment.name = "Custom List preview text colors";

        attachment.lifetime = .keepAlways;
        add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plenact-list-preview-colors.png")
        try image.pngData()?.write(to: url)
        print("LIST_COLOR_PREVIEW_PATH=\(url.path)")
        XCTAssertEqual(originals, [card, note])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testHostedSessionGuidanceUsesEntrySnapshotAndSurvivesListEdits
    /// @brief      Verify delayed guidance is tied to the visit rather than live emptiness
    /// @details    Hosts the real guidance view, changes its List after reveal, and opens a new
    ///             nonempty visit to check that later deletion cannot trigger guidance there.
    ///
    /// @return     (Void) records visit lifecycle assertions
    /// @throws     Propagates missing scene and asynchronous wait failures.
    ///
    @MainActor
    func testHostedSessionGuidanceUsesEntrySnapshotAndSurvivesListEdits() async throws
    {

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {
            window.isHidden = true;
            window.rootViewController = nil;
            previous?.makeKey()
        }

        var list = KanbanList(id: 4, title: "In the Queue", cards: [])
        let labels = LabelLibraryStore.load()
        var reveals = 0
        var footerStates: [Bool] = []
        let host = UIHostingController(
            rootView: SessionListGuidance(
                list: list, labels: labels, onReveal:
                {
                    reveals += 1
                },
                onPresentationChange:
                {
                    footerStates.append($0)
                }))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        XCTAssertEqual(reveals, 0)
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertEqual(reveals, 1)
        XCTAssertEqual(footerStates, [false, true])
        list.cards = [KanbanCard(id: 10, word: "My task", listTitle: list.title)]
        host.rootView = SessionListGuidance(
            list: list, labels: labels, onReveal:
            {
                reveals += 1
            }, onPresentationChange:
            {
                footerStates.append($0)
            })
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        list.cards = []
        host.rootView = SessionListGuidance(
            list: list, labels: labels, onReveal:
            {
                reveals += 1
            }, onPresentationChange:
            {
                footerStates.append($0)
            })
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(reveals, 1)
        list.cards = [KanbanCard(id: 11, word: "Already here", listTitle: list.title)]
        let nextVisit = UIHostingController(
            rootView: SessionListGuidance(
                list: list, labels: labels, onReveal:
                {
                    reveals += 1
                },
                onPresentationChange:
                {
                    footerStates.append($0)
                }))
        window.rootViewController = nextVisit
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        list.cards = []
        nextVisit.rootView = SessionListGuidance(
            list: list, labels: labels, onReveal:
            {
                reveals += 1
            }, onPresentationChange:
            {
                footerStates.append($0)
            })
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertEqual(reveals, 1)
        nextVisit.rootView = SessionListGuidance(
            list: list, labels: labels, onReveal:
            {
                reveals += 1
            }, toggleRequest: 1,
            onPresentationChange:
            {
                footerStates.append($0)
            })
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(reveals, 2, "The header can show guidance even for a visit that opened nonempty")
        nextVisit.rootView = SessionListGuidance(
            list: list, labels: labels, onReveal:
            {
                reveals += 1
            }, toggleRequest: 2,
            onPresentationChange:
            {
                footerStates.append($0)
            })
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(reveals, 2, "Retraction must not trigger another reveal")
        XCTAssertEqual(footerStates.last, true, "Capture remains available while the guide retracts")
        nextVisit.rootView = SessionListGuidance(
            list: list, labels: labels, onReveal:
            {
                reveals += 1
            }, toggleRequest: 3,
            onPresentationChange:
            {
                footerStates.append($0)
            })
        nextVisit.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(reveals, 3, "Another header tap can reverse an in-progress retraction")
        XCTAssertEqual(Array(footerStates.suffix(3)), [true, true, true])
    }

}
