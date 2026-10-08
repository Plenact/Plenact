// --------------------------------------------------------------------------------------------------
// @file       PlenactBoardDocument.swift
// @brief      Versioned Board document exchanged with the shared demo API
// @details    Defines the Board shape used by the explicit shared-demo service flow; local Board
//             state is not implicitly uploaded
//
// --------------------------------------------------------------------------------------------------
import Foundation


// -------------------------------------- MARK: - Board Document ------------------------------- //


///
/// Complete Plenact Board payload for one immutable server snapshot
///
/// @section    Purpose
///     Define the app-owned JSON contract independently from database table layout
///
/// @note   Server revision, actor, storage time, and origin are response/envelope metadata
///
struct PlenactBoardDocument: Codable, Equatable {

    static let currentSchemaVersion = 1   /* Current supported Board document shape */

    var schemaVersion: Int          /* Board JSON schema version */
    var boardKey:      String       /* Stable shared Board key   */
    var lists:         [KanbanList] /* Ordered lists and cards   */
    var labelLibrary:  LabelLibrary /* Reusable label catalog   */


    ///
    /// Maps Board document properties to the shared-demo JSON contract
    ///
    /// @section    Purpose
    ///     Keep schema, board key, and label library field names explicit
    ///
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case boardKey      = "board_key"
        case lists
        case labelLibrary  = "label_library"
    }


    ///
    /// @fcn        PlenactBoardDocument.init(boardKey:lists:labelLibrary:)
    /// @brief      Create a versioned snapshot from current Plenact Board data
    /// @details    Bundles the complete list/card state and reusable labels under one shared Board key
    ///
    /// @param[in]  boardKey      Stable logical identifier for the shared demo Board
    /// @param[in]  lists         Current Board lists and nested cards
    /// @param[in]  labelLibrary  Current reusable label definitions
    ///
    /// @return     (PlenactBoardDocument) current version-one Board payload
    ///
    /// @post       The document stores the current schema version and supplied snapshot values
    ///
    init(boardKey: String = "shared-demo", lists: [KanbanList], labelLibrary: LabelLibrary) {

        self.schemaVersion = Self.currentSchemaVersion
        self.boardKey      = boardKey
        self.lists         = lists
        self.labelLibrary  = labelLibrary
    }

    ///
    /// @fcn        PlenactBoardDocument.validationMessage
    /// @brief      Validate stable identifiers and assignment content before synchronization
    /// @details    Rejects duplicate list/card IDs and malformed typed assignees; missing linked-card
    ///             targets remain allowed so the UI can display an unavailable reference
    ///
    /// @return     (String?) validation message or nil when the document is structurally valid
    ///
    /// @pre        lists, cards, and assignments contain the document's current snapshot data
    /// @post       The document remains unchanged
    ///
    var validationMessage: String? {   /* Snapshot validation result */

          guard schemaVersion == Self.currentSchemaVersion,
              boardKey == "shared-demo" else {
            return "Unsupported Board document version or missing board key."
        }

        var listIDs: Set<Int> = []   /* Unique list identifiers */
        var cardIDs: Set<Int> = []   /* Unique Board card IDs  */

        for list in lists {

            guard !list.isArchived else {

                return "Archived lists are stored locally and cannot be published to the shared Board."
            }

            guard list.archivedCards.isEmpty else {

                return "Archived cards are stored locally and cannot be published to the shared Board."
            }

            guard list.id >= 0,
                  listIDs.insert(list.id).inserted,
                  !list.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {

                return "Each Board list needs a unique nonnegative ID and a title."
            }

            for card in list.cards {

                guard card.id >= 0,
                      cardIDs.insert(card.id).inserted,
                      !card.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      card.listTitle == list.title else {

                    return "Each Board card needs a unique nonnegative ID, title, and matching list title."
                }

                for assignee in card.members {

                    let displayName = assignee.displayName.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized assignee label */

                    guard !displayName.isEmpty else {

                        return "Each card assignee needs a display name."
                    }

                    switch assignee.kind {

                        case .registeredUser:

                            guard let userID = assignee.userID, /* Registered account reference */
                                  UUID(uuidString: userID) != nil else {

                                return "Registered card assignees need a valid stable user ID."
                            }

                        case .manual:

                            guard assignee.userID == nil else {

                                return "Manual card assignees cannot contain a registered user ID."
                            }
                    }
                }
            }
        }

        return nil
    }
}


// -------------------------------------- MARK: - Snapshot Response ---------------------------- //


///
/// Carries one Board document with server-maintained revision provenance
///
/// @section    Purpose
///     Keep concurrency and storage context outside the editable Board payload
///
struct PlenactBoardSnapshotResponse: Decodable {

    let revision:     Int64                /* Current immutable revision   */
    let document:     PlenactBoardDocument /* Complete Board content       */
    let storedAtUTC:  String               /* Server storage timestamp     */
    let storedByUserID: String             /* Verified storage actor       */
    let storageOrigin: String              /* Controlled write origin      */


    ///
    /// Maps snapshot provenance fields to the server response names
    ///
    /// @section    Purpose
    ///     Decode revision and storage metadata independently of the Board document
    ///
    enum CodingKeys: String, CodingKey {
        case revision
        case document
        case storedAtUTC    = "stored_at_utc"
        case storedByUserID = "stored_by_user_id"
        case storageOrigin  = "storage_origin"
    }
}