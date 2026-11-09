// --------------------------------------------------------------------------------------------------
// @file       PlanSettingsTests.swift
// @brief      Modular settings layout and shared-draft editing regression coverage
// @details    Uses synthetic bindings and automated-Simulator windows. Rendering never saves or
//             requests notification permission; attachments contain synthetic settings only
// --------------------------------------------------------------------------------------------------
import SwiftUI
import XCTest
@testable import Plenact


/// Verifies readable module heights and draft continuity across settings destinations
/// @section Purpose
///     Catch oversized preference pages and controls that accidentally write while browsing
@MainActor
final class PlanSettingsTests: XCTestCase
{

    /// Verify a saved layout seeds new Cards and respects explicit layouts and other item types
    func testDefaultCardLayoutSeedsNewCardsAndResetsForFutureCards() throws
    {

        let suite    = "Plenact.NewCardLayout.Tests." + UUID().uuidString /* Isolated settings */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))     /* Test storage */
        let layout   = CardSectionLayout(order: [.checklists, .details], hidden: [.activity, .media])
        let settings = LocalProfilePreferences()

        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(NewCardLayoutStore.load(from: defaults))
        XCTAssertTrue(NewCardLayoutStore.save(layout, to: defaults))
        XCTAssertEqual(NewCardLayoutStore.load(from: defaults), layout)

        var card    = KanbanCard(id: 1, word: "New Card", listTitle: "Synthetic List")
        var note    = KanbanCard(id: 2, word: "New Note", listTitle: "Synthetic List", presentation: .note,
            appearance: ItemAppearance(studioSurface: StudioSurface(material: .plain)))
        var divider = KanbanCard(id: 3, word: "Section", listTitle: "Synthetic List", isDivider: true)
        var custom  = KanbanCard(id: 4, word: "Template Card", listTitle: "Synthetic List",
            sectionLayout: CardSectionLayout(hidden: [.details]))
        let authored = custom.sectionLayout /* Explicit Card override */

        NewCardAppearanceDefaults.apply(to: &card, preferences: settings, defaults: defaults)
        NewCardAppearanceDefaults.apply(to: &note, preferences: settings, defaults: defaults)
        NewCardAppearanceDefaults.apply(to: &divider, preferences: settings, defaults: defaults)
        NewCardAppearanceDefaults.apply(to: &custom, preferences: settings, defaults: defaults)

        XCTAssertEqual(card.sectionLayout, layout)
        XCTAssertNil(note.sectionLayout)
        XCTAssertNil(divider.sectionLayout)
        XCTAssertEqual(custom.sectionLayout, authored)
        XCTAssertEqual(try JSONDecoder().decode(KanbanCard.self, from: JSONEncoder().encode(card)).sectionLayout, layout)

        XCTAssertTrue(NewCardLayoutStore.save(CardSectionLayout(), to: defaults))
        XCTAssertNil(NewCardLayoutStore.load(from: defaults))
        var next = KanbanCard(id: 5, word: "After reset", listTitle: "Synthetic List")

        NewCardAppearanceDefaults.apply(to: &next, preferences: settings, defaults: defaults)
        XCTAssertNil(next.sectionLayout)
        XCTAssertEqual(card.sectionLayout, layout)
    }


    private final class Draft: ObservableObject
    {

        @Published var preferences = LocalProfilePreferences() /* Planning and display choices */
        @Published var weekday     = 2                         /* Calendar weekday number      */
        var saves                  = 0                         /* Number of requested saves    */

    }


    /// Binds the same synthetic draft into each focused page
    private struct Page: View
    {

        @ObservedObject var draft: Draft /* Local editing draft          */
        let page: PlanSettingsPage       /* Current settings destination */

        var body: some View /* Page layout */
        {

            NavigationStack
            {

                PlanSettingsModulePage(page: page, preferences: $draft.preferences,
                    firstWeekday: $draft.weekday, lists: [KanbanList(id: 1, title: "Synthetic List", cards: [])],
                    onSave: {

                        draft.saves += 1

                    }, onStudio: {}, onTemplates: {}, onShortcuts: {})
            }
        }
    }


    /// @fcn PlanSettingsTests.descendants
    /// @brief Collect native controls or scrollers beneath a rendered SwiftUI page
    /// @param[in] view Root to inspect
    /// @param[in] type Native view type to collect
    /// @return Matching views including the root
    private func descendants<T: UIView>(_ view: UIView, of type: T.Type) -> [T]
    {

        ((view as? T).map { [$0] } ?? [])
            + view.subviews.flatMap { descendants($0, of: type) }
    }


    /// @fcn PlanSettingsTests.testFocusedPagesFitPhoneWithoutSaving
    /// @brief Keep normal-size preference modules within one-and-a-half screens
    /// @throws Window or rendering failures
    func testFocusedPagesFitPhoneWithoutSaving() async throws
    {

        let scene    = /* Owning window scene */
            try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow) /* Prior key window        */
        let window   = UIWindow(windowScene: scene)              /* Synthetic scene window  */
        let draft    = Draft()                                   /* Local editing draft     */
        let original = PlanPreferencesStore.load()               /* Baseline before changes */

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)

        defer
        {

            window.isHidden = true
            window.rootViewController = nil

            previous?.makeKeyAndVisible()
        }

        for page in PlanSettingsPage.allCases where page != .review
        {

            let host = /* Synthetic SwiftUI host */
                UIHostingController(rootView: Page(draft: draft, page: page)
                .environment(\.dynamicTypeSize, .large))

            window.rootViewController = host

            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()

            let scroll = /* Native scroll view */
                try XCTUnwrap(descendants(host.view, of: UIScrollView.self)
                .filter { $0.bounds.height > 100 }.max { $0.bounds.height < $1.bounds.height })
            let fullHeight = /* Full height */
                scroll.contentSize.height + scroll.adjustedContentInset.top
                + scroll.adjustedContentInset.bottom

            print("SETTINGS_PAGE_HEIGHT", page.rawValue, fullHeight, "viewport", scroll.bounds.height)
            XCTAssertLessThanOrEqual(fullHeight, scroll.bounds.height * 1.5 + 2, page.title)

            let image = /* Image used by this operation */
                UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {

                _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image) /* Synthetic test evidence */

            attachment.name = "PlanSettings-" + page.rawValue
            attachment.lifetime = .keepAlways

            add(attachment)
        }

        XCTAssertEqual(draft.preferences, LocalProfilePreferences())
        XCTAssertEqual(draft.weekday, 2)
        XCTAssertEqual(draft.saves, 0)
        XCTAssertEqual(PlanPreferencesStore.load(), original)
    }


    /// @fcn PlanSettingsTests.testDirectoriesAndReminderEditorFitPhone
    /// @brief Keep the main menu, Studio directory and review editor compact without saving
    /// @throws Window or rendering failures
    func testDirectoriesAndReminderEditorFitPhone() async throws
    {

        let scene                      = /* Owning window scene */
            try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous                   = /* Prior key window */
            scene.windows.first(where: \.isKeyWindow)
        let window                     = UIWindow(windowScene: scene) /* Synthetic scene window */
        let original                   = PlanPreferencesStore.load() /* Baseline before changes */
        let views: [(String, AnyView)] = [ /* Rendered or configured views */
            ("menu", AnyView(PlanSettingsView(lists: [], onSaveProfile: { _ in XCTFail("Rendering must not save") }))),
            ("studio", AnyView(NavigationStack { StudioSettingsView() })),
            ("review", AnyView(ReviewRhythmSettingsView()))
        ]

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)

        defer
        {

            window.isHidden = true
            window.rootViewController = nil

            previous?.makeKeyAndVisible()
        }

        for (name, view) in views
        {

            let host = /* Synthetic SwiftUI host */
                UIHostingController(rootView: view.environment(\.dynamicTypeSize, .large))

            window.rootViewController = host

            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            host.view.layoutIfNeeded()

            let scroll = /* Native scroll view */
                try XCTUnwrap(descendants(host.view, of: UIScrollView.self)
                .filter { $0.bounds.height > 100 }.max { $0.bounds.height < $1.bounds.height })
            let fullHeight = /* Full height */
                scroll.contentSize.height + scroll.adjustedContentInset.top
                + scroll.adjustedContentInset.bottom

            print("SETTINGS_PAGE_HEIGHT", name, fullHeight, "viewport", scroll.bounds.height)
            XCTAssertLessThanOrEqual(fullHeight, scroll.bounds.height * 1.5 + 2, name)

            let image = /* Image used by this operation */
                UIGraphicsImageRenderer(bounds: host.view.bounds).image
            {

                _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image) /* Synthetic test evidence */

            attachment.name = "PlanSettings-" + name
            attachment.lifetime = .keepAlways

            add(attachment)
        }

        XCTAssertEqual(PlanPreferencesStore.load(), original)
    }


    /// @fcn PlanSettingsTests.testEditingAndSwitchingModulesRetainsUnsavedDraft
    /// @brief A native toggle changes only the shared draft and survives visiting another module
    /// @throws Window, control or rendering failures
    func testEditingAndSwitchingModulesRetainsUnsavedDraft() async throws
    {

        let scene    = /* Owning window scene */
            try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow) /* Prior key window        */
        let window   = UIWindow(windowScene: scene)              /* Synthetic scene window  */
        let draft    = Draft()                                   /* Local editing draft     */
        let original = PlanPreferencesStore.load()               /* Baseline before changes */
        let host     =                                           /* Synthetic SwiftUI host  */
            UIHostingController(rootView: Page(draft: draft, page: .navigation))

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host

        window.makeKeyAndVisible()
        defer
        {

            window.isHidden = true
            window.rootViewController = nil

            previous?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(250))
        host.view.layoutIfNeeded()

        let control = /* Native input control */
            try XCTUnwrap(descendants(host.view, of: UISwitch.self).first)
        let before  = draft.preferences /* State before the operation */

        control.setOn(!control.isOn, animated: false)
        control.sendActions(for: .valueChanged)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNotEqual(draft.preferences, before)

        let edited = draft.preferences /* Snapshot after requested edits */

        host.rootView = Page(draft: draft, page: .maps)

        try await Task.sleep(for: .milliseconds(150))

        host.rootView = Page(draft: draft, page: .navigation)

        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(draft.preferences, edited)
        XCTAssertEqual(draft.saves, 0)
        XCTAssertEqual(PlanPreferencesStore.load(), original)
    }
}
