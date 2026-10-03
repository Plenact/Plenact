// -------------------------------------------------------------------------------------------------
// @file       ChecklistMigrationTests.swift
// @brief      Checklist-item persistence compatibility tests
// @details    Verifies revision 0 string migration and stable checklist-item round trips
//
// -------------------------------------------------------------------------------------------------
import XCTest
@testable import Plenact


///
/// Verifies compatibility between revision 0 checklist strings and stable checklist-item records
///
/// @section    Purpose
///     Protect saved board text, completion state, and identity while the checklist schema evolves
///
final class ChecklistMigrationTests: XCTestCase {

    ///
    /// @fcn        ChecklistMigrationTests.testLegacyBoardSnapshotDecodesChecklistItems
    /// @brief      Decode checklist actions from a complete revision 0 board snapshot
    /// @details    Exercises migration through list, card, and checklist nesting rather than decoding
    ///             only the checklist value in isolation
    ///
    /// @return     (Void) succeeds when legacy text and completion migrate without loss
    ///
    /// @throws     Decoding or unwrap failures when the legacy snapshot is incompatible
    ///
    func testLegacyBoardSnapshotDecodesChecklistItems() throws {

        let legacyJSON = """
        [
          {
            "id": 7,
            "title": "Sunday (9/27)",
            "cards": [
              {
                "id": 42,
                "word": "Laundry Session",
                "listTitle": "Sunday (9/27)",
                "isDivider": false,
                "isTitleChecked": false,
                "checklists": [
                  {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "title": "Laundry actions",
                    "items": ["Sort clothes", "Start washer", "Fold clothes"],
                    "completedItemIndices": [1]
                  }
                ],
                "comments": [],
                "members": [],
                "labelIDs": [],
                "dismissedActivityIDs": []
              }
            ]
          }
        ]
        """   /* Revision 0 board fixture */

        let lists     = try JSONDecoder().decode([KanbanList].self, from: Data(legacyJSON.utf8)) /* Migrated board */
        let checklist = try XCTUnwrap(lists.first?.cards.first?.checklists.first)                /* Nested checklist */

        XCTAssertEqual(checklist.items.map(\.title), ["Sort clothes", "Start washer", "Fold clothes"])
        XCTAssertEqual(checklist.completedItemIndices, [1])
        XCTAssertFalse(checklist.items[0].isCompleted)
        XCTAssertTrue(checklist.items[1].isCompleted)
        XCTAssertFalse(checklist.items[2].isCompleted)
    }

    ///
    /// @fcn        ChecklistMigrationTests.testLegacyMigrationProducesDeterministicItemIDs
    /// @brief      Verify legacy checklist items receive repeatable identities
    /// @details    Decodes the same revision 0 value twice and compares migrated item UUIDs
    ///
    /// @return     (Void) succeeds when IDs repeat across decodes and remain unique per item
    ///
    /// @throws     Decoding failures when the legacy checklist cannot be migrated
    ///
    func testLegacyMigrationProducesDeterministicItemIDs() throws {

        let legacyJSON = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "title": "Actions",
          "items": ["First", "Second"],
          "completedItemIndices": []
        }
        """   /* Revision 0 checklist fixture */

        let firstDecode  = try JSONDecoder().decode(KanbanChecklist.self, from: Data(legacyJSON.utf8)) /* First migration  */
        let secondDecode = try JSONDecoder().decode(KanbanChecklist.self, from: Data(legacyJSON.utf8)) /* Repeat migration */

        XCTAssertEqual(firstDecode.items.map(\.id), secondDecode.items.map(\.id))
        XCTAssertNotEqual(firstDecode.items[0].id, firstDecode.items[1].id)
    }

    ///
    /// @fcn        ChecklistMigrationTests.testExplicitCompletionIndicesPreserveItemIDs
    /// @brief      Preserve stable IDs while applying compatibility completion indices
    /// @details    Confirms arbitrary positional completion updates direct item state without replacement
    ///
    /// @return     (Void) succeeds when identity is unchanged and completion matches supplied positions
    ///
    func testExplicitCompletionIndicesPreserveItemIDs() {

        let firstID  = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!   /* First action ID  */
        let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!   /* Second action ID */
        let items = [                                                               /* Source actions   */
            KanbanChecklistItem(id: firstID,  title: "First",  isCompleted: true),
            KanbanChecklistItem(id: secondID, title: "Second", isCompleted: false)
        ]

        let checklist = KanbanChecklist(   /* Compatibility result */
            title:                "Actions",
            items:                items,
            completedItemIndices: [1]
        )

        XCTAssertEqual(checklist.items.map(\.id), [firstID, secondID])
        XCTAssertEqual(checklist.completedItemIndices, [1])
        XCTAssertFalse(checklist.items[0].isCompleted)
        XCTAssertTrue(checklist.items[1].isCompleted)
    }

    ///
    /// @fcn        ChecklistMigrationTests.testCurrentChecklistRoundTripUsesItemRecords
    /// @brief      Round-trip the current stable checklist-item format
    /// @details    Confirms new JSON contains item records, omits the legacy index field, and decodes equally
    ///
    /// @return     (Void) succeeds when the current checklist representation round-trips without loss
    ///
    /// @throws     Encoding, JSON inspection, decoding, or unwrap failures
    ///
    func testCurrentChecklistRoundTripUsesItemRecords() throws {

        let checklist = KanbanChecklist(   /* Current checklist */
            id:    UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "Actions",
            items: [
                KanbanChecklistItem(
                    id:          UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    title:       "Go do laundry",
                    isCompleted: true
                )
            ]
        )

        let encoded = try JSONEncoder().encode(checklist)                                      /* Current JSON     */
        let object  = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]) /* JSON object   */
        let items   = try XCTUnwrap(object["items"] as? [[String: Any]])                       /* Encoded actions */
        let decoded = try JSONDecoder().decode(KanbanChecklist.self, from: encoded)             /* Round-trip value */

        XCTAssertEqual(items.first?["title"] as? String, "Go do laundry")
        XCTAssertNil(object["completedItemIndices"])
        XCTAssertEqual(decoded, checklist)
    }

      ///
      /// @fcn        ChecklistMigrationTests.testEarlierStableItemDefaultsToStandardAction
      /// @brief      Decode a stable checklist item written before action content existed
      /// @details    Verifies the absent content field receives standard text behavior
      ///
      /// @return     (Void) succeeds when the earlier item remains readable and standard
      ///
      /// @throws     Decoding failures when the earlier item representation is incompatible
      ///
      func testEarlierStableItemDefaultsToStandardAction() throws {

        let earlierItemJSON = """
        {
          "id": "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
          "title": "Existing action",
          "isCompleted": false
        }
        """   /* Pre-content item fixture */

        let item = try JSONDecoder().decode(KanbanChecklistItem.self, from: Data(earlierItemJSON.utf8)) /* Decoded action */

        XCTAssertEqual(item.title, "Existing action")
        XCTAssertEqual(item.content, .standard)
      }

      ///
      /// @fcn        ChecklistMigrationTests.testRichActionContentRoundTrips
      /// @brief      Round-trip linked-card and Action Detail payloads
      /// @details    Protects stable card references and reduced owned content across board saves
      ///
      /// @return     (Void) succeeds when both rich action types round-trip without loss
      ///
      /// @throws     Encoding or decoding failures for rich checklist actions
      ///
      func testRichActionContentRoundTrips() throws {

        let detail = KanbanChecklistActionDetail(   /* Reduced detail */
          description: "Prepare the laundry session.",
          checklists:  [KanbanChecklist(title: "Steps", items: ["Sort clothes"])],
          comments:    [KanbanComment(author: "Plenact Demo", body: "Ready to begin.")]
        )
        let checklist = KanbanChecklist(             /* Rich action checklist */
          title: "Actions",
          items: [
            KanbanChecklistItem(title: "Open laundry card", content: .linkedCard(cardID: 42)),
            KanbanChecklistItem(title: "Prepare details", content: .actionDetail(detail))
          ]
        )

        let encoded = try JSONEncoder().encode(checklist)                            /* Rich JSON       */
        let decoded = try JSONDecoder().decode(KanbanChecklist.self, from: encoded)  /* Round-trip data */

        XCTAssertEqual(decoded, checklist)
      }

      ///
      /// @fcn        ChecklistMigrationTests.testEveryStarterCardDemonstratesRichActions
      /// @brief      Verify every seeded activity card demonstrates linked and detailed actions
      /// @details    Requires one resolvable cross-list card link and two Action Details while leaving
      ///             section-divider cards free of demonstration content
      ///
      /// @return     (Void) succeeds when the complete starter Board meets the demonstration contract
      ///
      func testEveryStarterCardDemonstratesRichActions() {

        let cardsByID = Dictionary(   /* Starter cards by ID */
          uniqueKeysWithValues: SampleData.lists.flatMap(\.cards).map { ($0.id, $0) }
        )

        for card in SampleData.lists.flatMap(\.cards) {

          if card.isSectionDivider {
            XCTAssertTrue(card.checklists.flatMap(\.items).allSatisfy { $0.content == .standard })
            continue
          }

          let actions = card.checklists.flatMap(\.items)   /* Card checklist actions */
          let linkedCardIDs = actions.compactMap { item -> Int? in /* Resolved linked-card target IDs */
            guard case .linkedCard(let cardID) = item.content else { return nil } /* Linked card ID */
            return cardID
          }
          let detailCount = actions.filter { item in /* Count reduced Action Details */
            guard case .actionDetail = item.content else { return false }
            return true
          }.count

          XCTAssertEqual(linkedCardIDs.count, 1, "\(card.word) should demonstrate one card link")
          XCTAssertEqual(detailCount, 2, "\(card.word) should demonstrate two Action Details")

          if let linkedCardID = linkedCardIDs.first { /* First seeded linked-card target */
            let linkedCard = cardsByID[linkedCardID]   /* Resolved sample target */

            XCTAssertNotNil(linkedCard, "\(card.word) link should resolve")
            XCTAssertNotEqual(linkedCard?.listTitle, card.listTitle, "\(card.word) should link across lists")
          }
        }
      }

      ///
      /// @fcn        ChecklistMigrationTests.testStarterBoardUsesWeekdayPlanningLists
      /// @brief      Verify the starter Board represents a complete planning week
      /// @details    Protects weekday ordering, daily card counts, divider placement, and representative
      ///             planning content from accidental regression
      ///
      /// @return     (Void) succeeds when all seven weekday lists meet the starter contract
      ///
      func testStarterBoardUsesWeekdayPlanningLists() {

        let expectedTitles = [   /* Ordered weekday titles */
          "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
        ]

        XCTAssertEqual(SampleData.lists.map(\.title), expectedTitles)

        for list in SampleData.lists {

          let activityCards = list.cards.filter { !$0.isSectionDivider }   /* Daily activity cards */
          let dividerCards  = list.cards.filter(\.isSectionDivider)        /* Daily dividers       */

          XCTAssertEqual(activityCards.count, 6, "\(list.title) should begin with six activities")
          XCTAssertEqual(dividerCards.count, 1, "\(list.title) should contain one divider")
          XCTAssertTrue(activityCards.allSatisfy { $0.listTitle == list.title })
        }

        XCTAssertTrue(SampleData.lists[0].cards.contains { $0.word == "Laundry session" })
        XCTAssertTrue(SampleData.lists[6].cards.contains { $0.word == "Review the upcoming calendar" })
      }

      ///
      /// @fcn        ChecklistMigrationTests.testLegacyCardMemberNamesBecomeManualAssignees
      /// @brief      Preserve revision 0 card member strings as manual assignments
      /// @details    Confirms old Board snapshots do not accidentally claim registered identities
      ///
      /// @return     (Void) succeeds when legacy names remain visible and are explicitly manual
      ///
      /// @throws     Decoding failures when the previous card member representation is incompatible
      ///
      func testLegacyCardMemberNamesBecomeManualAssignees() throws {

        let legacyJSON = """
        {
          "id": 9,
          "word": "Plan the week",
          "listTitle": "Monday",
          "isDivider": false,
          "isTitleChecked": false,
          "members": ["Jim", "Sally"]
        }
        """   /* Legacy member fixture */

        let card = try JSONDecoder().decode(KanbanCard.self, from: Data(legacyJSON.utf8))   /* Decoded card */

        XCTAssertEqual(card.members.map(\.displayName), ["Jim", "Sally"])
        XCTAssertTrue(card.members.allSatisfy { $0.kind == .manual && $0.userID == nil })
    }

    ///
    /// @fcn        ChecklistMigrationTests.testRegisteredCardAssigneeRoundTripsStableUserID
    /// @brief      Preserve registered identity separately from its display name
    /// @details    Verifies the Board Codable model stores a stable user ID for an assignee
    ///
    /// @return     (Void) succeeds when the encoded card restores the same registered account link
    ///
    /// @throws     Encoding or decoding failures for the card assignment
    ///
    func testRegisteredCardAssigneeRoundTripsStableUserID() throws {

        let userID = "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"   /* Stable demo user ID */
        let card = KanbanCard(   /* Card with directory assignment */
            id:        10,
            word:      "Prepare the week",
            listTitle: "Monday",
            members:   [.registered(userID: userID, displayName: "Jim")]
        )

        let encoded = try JSONEncoder().encode(card)   /* Encoded card */
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: encoded)   /* Round-trip card */

        XCTAssertEqual(decoded.members.count, 1)
        XCTAssertEqual(decoded.members[0].kind, .registeredUser)
        XCTAssertEqual(decoded.members[0].userID, userID)
        XCTAssertEqual(decoded.members[0].displayName, "Jim")
    }
}