// --------------------------------------------------------------------------------------------------
// @file       PlanningReviewTests2.swift
// @brief      Planning Review regression tests2
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
/// PlanningReview regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayInitialTaskFocusSkipsCompletedAndNonTaskFormatsWithoutReordering
    /// @brief      Verify that today Initial Task Focus Skips Completed And Non Task Formats Without Reordering
    /// @details    Checks `XCTAssertEqual(list.firstUncheckedTaskID, 5)`; `XCTAssertEqual(list.cards, cards)`.
    ///
    /// @return     (Void) no return value
    ///
    func testTodayInitialTaskFocusSkipsCompletedAndNonTaskFormatsWithoutReordering()
    {

        let cards = [
            KanbanCard(id: 1, word: "Done", listTitle: "Plans", isTitleChecked: true),
            KanbanCard(id: 2, word: "Note", listTitle: "Plans", presentation: .note),
            KanbanCard(id: 3, word: "---", listTitle: "Plans"),
            KanbanCard(id: 4, word: "Picture", listTitle: "Plans", listDisplayFormat: .picture),
            KanbanCard(id: 5, word: "Next task", listTitle: "Plans"),
            KanbanCard(id: 6, word: "Later task", listTitle: "Plans")
        ]
        var list = KanbanList(id: 0, title: "Plans", cards: cards)
        XCTAssertEqual(list.firstUncheckedTaskID, 5)
        XCTAssertEqual(list.cards, cards)
        list.cards[4].isTitleChecked = true
        XCTAssertEqual(list.firstUncheckedTaskID, 6)
        list.cards[5].isTitleChecked = true
        XCTAssertNil(list.firstUncheckedTaskID)
        list.cards = []
        XCTAssertNil(list.firstUncheckedTaskID)
        list.cards = cards
        list.isArchived = true
        XCTAssertNil(list.firstUncheckedTaskID)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testNewBoardListEditorSelectsTitleAndNextFocusesSubtitle
    /// @brief      Start naming a new Board list immediately and advance to its subtitle
    /// @details    Mounts the new-list editor, checks native first-responder and full-title selection, types a
    ///             replacement name, and invokes the keyboard return delegate. Focus changes must not call Save
    ///             or mutate the supplied list, and the title's return key must be labeled Next.
    ///
    /// @return     (Void) no return value
    /// @throws     XCTest setup failures or cancelled fixture delays
    ///
    @MainActor
    func testNewBoardListEditorSelectsTitleAndNextFocusesSubtitle() async throws
    {

        var list = KanbanList(id: 7, title: "New List 2", cards: [])
        list.subtitleOverride = "Initial subtitle"
        let original = list
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap
            {
                $0 as? UIWindowScene
            } .first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer
        {

            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }


        ///
        /// @fcn        testNewBoardListEditorSelectsTitleAndNextFocusesSubtitle.descendants
        /// @brief      Collect the native descendants of the hosted editor
        /// @details    Includes the supplied view so callers can find both single-line fields and the multiline
        ///             subtitle editor without relying on private SwiftUI container classes.
        ///
        /// @param[in]  view  Native subtree to inspect
        ///
        /// @return     ([UIView]) root and all descendant views in traversal order
        ///
        func descendants(_ view: UIView) -> [UIView]
        {
            [view] + view.subviews.flatMap(descendants)
        }

        var saveCalls = 0
        let host = UIHostingController(
            rootView: ListInfoEditorSheet(list: list, focusesTitleOnAppear: true)
            {
                _, _, _ in
                saveCalls += 1
                return true
            })
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        let titleField = try XCTUnwrap(
            descendants(host.view).compactMap
            {
                $0 as? UITextField
            } .first
            {
                $0.text == list.title
            })
        XCTAssertTrue(titleField.isFirstResponder)
        XCTAssertEqual(titleField.returnKeyType, .next)
        let selection = try XCTUnwrap(titleField.selectedTextRange)
        XCTAssertEqual(titleField.text(in: selection), list.title)
        titleField.insertText("Roadmap")
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(titleField.text, "Roadmap")
        _ = titleField.delegate?.textFieldShouldReturn?(titleField)
        try await Task.sleep(for: .milliseconds(150))
        let subtitle = try XCTUnwrap(
            descendants(host.view).first
            {
                view in
                (view as? UITextField)?.text == list.subtitle || (view as? UITextView)?.text == list.subtitle
            })
        XCTAssertTrue(subtitle.isFirstResponder)
        XCTAssertFalse(titleField.isFirstResponder)
        XCTAssertEqual(titleField.text, "Roadmap")
        XCTAssertEqual(saveCalls, 0)
        XCTAssertEqual(list, original)
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testStandardBoardHasEqualFifteenPointNeighborPreviews
    /// @brief      Verify that standard Board Has Equal Fifteen Point Neighbor Previews
    /// @details    Exercises `BoardPresentation.standard.columnWidth`. Checks `XCTAssertEqual(sideInset - 17,
    ///             15)`; `XCTAssertEqual(width + 2 * sideInset, viewport)`.
    ///
    /// @return     (Void) no return value
    ///
    func testStandardBoardHasEqualFifteenPointNeighborPreviews()
    {


        for viewport: CGFloat in [320, 360, 393, 414, 424]
        {

            let width = BoardPresentation.standard.columnWidth(viewportWidth: viewport, accessibilitySize: false)
            let sideInset = (viewport - width) / 2
            XCTAssertEqual(
                sideInset - 17, 15, accuracy: 0.001,
                                        "Each side must show 15 points of its neighbor after the 17-point gap")
            XCTAssertEqual(width + 2 * sideInset, viewport, accuracy: 0.001)
        }

    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testTodayFocusHasNoFallbackForUnavailableOrAmbiguousDay()
    /// @brief      Reject missing, renamed, archived, and duplicate current-day lists
    /// @details    Resolves a fixed Tuesday against synthetic snapshots without substituting Monday
    ///             or consulting manual selection preferences
    ///
    /// @return     (Void) records assertion failures for unintended fallback behavior
    ///
    /// @throws     Calendar fixture construction failures
    ///
    func testTodayFocusHasNoFallbackForUnavailableOrAmbiguousDay() throws
    {


        var calendar = Calendar(identifier: .gregorian) /* Fixed calendar for date assertions */

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 6)))  /* Date value for boundary checks        */
        let monday = KanbanList(id: 1, title: "Monday", cards: [])               /* Monday List fixture for weekday focus */
        let tuesday = KanbanList(id: 2, title: "Tuesday", cards: [])             /* Tuesday planning fixture              */
        var archived = tuesday                                                   /* Archived value for restoration checks */

        archived.isArchived = true

        XCTAssertNil(TodayListSelection.currentDayList(in: [], date: date, calendar: calendar))
        XCTAssertNil(TodayListSelection.currentDayList(in: [monday], date: date, calendar: calendar))
        XCTAssertNil(TodayListSelection.currentDayList(in: [monday, archived], date: date, calendar: calendar))
        XCTAssertNil(
            TodayListSelection.currentDayList(
                in: [monday, KanbanList(id: 2, title: "Renamed", cards: [])], date: date, calendar: calendar))
        XCTAssertNil(
            TodayListSelection.currentDayList(
                in: [tuesday, KanbanList(id: 3, title: "Tuesday", cards: [])], date: date, calendar: calendar))
        XCTAssertEqual(
            TodayListSelection.currentDayList(
                in: [monday, KanbanList(id: 2, title: " tUeSdAy ", cards: [])], date: date, calendar: calendar)?.id, 2)
    }

}
