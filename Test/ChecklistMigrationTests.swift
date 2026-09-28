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
}