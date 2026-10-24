// --------------------------------------------------------------------------------------------------
// @file       WorkspaceContentActions.swift
// @brief      Workspace content creation and restoration actions
// @details    Restores Boards, targets canonical Cards, and creates content through the existing
//             owner and recovery boundaries.
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
    /// @fcn        AppRootView.restoreBoard(_:)
    /// @brief      Reactivate an archived board under a unique title
    /// @details    Computes the restored collection snapshot and saves it before updating the UI;
    ///             archived Week copies remain separate from the current Week workspace
    ///
    /// @param[in]  id  Archived collection identity
    ///
    /// @return     (Void) updates collections after successful persistence
    ///
    /// @post       Missing/nonarchived IDs do nothing; save failures leave state unchanged and show
    ///             an error
    ///
    func restoreBoard(_ id: UUID)
    {


        guard
        let index = collections.firstIndex(where:
            {  /* Position of the archived Board to restore */


                $0.id == id && $0.isArchived == true
            })
        else
        {


            return
        }


        var updated = collections /* Directory snapshot carrying the restored Board */

        updated[index].restore(existingTitles: ["Week Board"] + collections.filter
            {
                $0.id != id
            } .map(\.title))
        do
        {


            try PersonalCollectionStore.saveChecked(updated)
            collections = updated
        }
        catch
        {


            DatabaseActivity.shared.report("Could not restore the board: \(error.localizedDescription)")
        }

    }


    ///
    /// @fcn        AppRootView.openBoardCard(listID:cardID:)
    /// @brief      Request a list and card detail destination in Week
    /// @details    Remembers the list and supplies stable targets for ContentView to validate and
    ///             open
    ///
    /// @param[in]  listID  Containing Week list identity
    /// @param[in]  cardID  Card identity to open within the list
    ///
    /// @return     (Void) selects Week and updates both navigation targets
    ///
    /// @post       No card or list content is modified
    ///
    func openBoardCard(listID: Int, cardID: Int)
    {

        displayedPlanningWeek = nil

        rememberLastViewedList(listID)
        boardTargetCardID = cardID
        boardTargetListID = listID
        selectedDestination = .board
    }


    ///
    /// @fcn        AppRootView.rememberLastViewedList(_:)
    /// @brief      Persist an existing Week list as the last-viewed destination
    /// @details    Avoids redundant preference writes and ignores IDs absent from the complete
    ///             snapshot
    ///
    /// @param[in]  listID  List identity reported by navigation or the Board viewport
    ///
    /// @return     (Void) updates the last-viewed preference when necessary
    ///
    /// @post       Board content and current navigation remain unchanged
    ///
    func rememberLastViewedList(_ listID: Int)
    {


        guard
        lists.contains(where:
            {


                $0.id == listID
            }), LastViewedListStore.load() != listID
        else
        {


            return
        }


        LastViewedListStore.save(listID)
    }


    ///
    /// @fcn        AppRootView.toggleCardCompletion(in:cardID:)
    /// @brief      Toggle completion of a card in the shared Week snapshot
    /// @details    Locates list and active-card indices by ID; root state observation handles
    ///             persistence
    ///
    /// @param[in]  listID  Containing list identity
    /// @param[in]  cardID  Active card identity
    ///
    /// @return     (Void) flips the title-completion flag
    ///
    /// @post       Missing list/card identities leave state unchanged
    ///
    func toggleCardCompletion(in listID: Int, cardID: Int)
    {


        guard
        let listIndex = lists.firstIndex(where:
            {  /* Position of the card's containing Week list */


                $0.id == listID
            }),
        let cardIndex = lists[listIndex].cards.firstIndex(where:
            {
                $0.id == cardID
            })
        else
        {  /* Position of the requested Week card */


            return
        }


        guard !lists[listIndex].cards[cardIndex].isEditingLocked else
        {
            return
        }

        lists[listIndex].cards[cardIndex].isTitleChecked.toggle()
    }


    ///
    /// @fcn        AppRootView.addWeekList()
    /// @brief      Append a uniquely identified blank Week list and reveal it
    /// @details    Reserves IDs across active and archived lists and chooses an unused
    ///             case-insensitive New List title, adding a numeric suffix when necessary
    ///
    /// @return     (Void) appends the list and selects Week with a pending list target
    ///
    /// @post       Existing list/card contents remain unchanged; root observation saves the new
    ///             snapshot
    ///
    func addWeekList()
    {


        let nextListID = (lists.map(\.id).max() ?? -1) + 1 /* Board-wide next list ID    */
        let existingTitles = Set(lists.map
            {
                $0.title.lowercased()
            })                  /* Existing normalized titles */
        var title = "New List"  /* First candidate list title */
        var suffix = 2          /* Duplicate-title suffix     */

        while existingTitles.contains(title.lowercased())
        {


            title = "New List \(suffix)"
            suffix += 1
        }


        lists.append(KanbanList(id: nextListID, title: title, cards: []))
        displayedPlanningWeek = nil
        boardTargetListID = nextListID
        selectedDestination = .board
    }


    ///
    /// @fcn        AppRootView.addCard(to:title:description:)
    /// @brief      Create full capture content in the active Week List
    /// @details    Builds destination-local items with the submitted presentation, writing,
    ///             actions, attachments, and schedule. Explicit checked saves, media, or
    ///             scheduling persist calendar and Board snapshots through a recovery
    ///             transaction before publication; failure returns false and retains the draft.
    ///
    /// @param[in]  listID        Existing destination list identity
    /// @param[in]  title         Card title supplied by the composer or quick capture
    /// @param[in]  description   Optional supporting text; empty text becomes nil
    ///
    /// @param[in]  subtitle      Supporting preview subtitle supplied by the creation draft
    /// @param[in]  presentation  Card or Note presentation requested for the new item
    /// @param[in]  actions       Optional checklist action titles supplied by the capture mode
    /// @param[in]  attachments   Retained media attachment records committed for the new item
    /// @param[in]  schedule      Optional validated start and stop values applied during creation
    /// @param[in]  checkedSave   Whether creation must complete checked persistence before
    ///             publishing the result
    ///
    /// @return     (Bool) true when valid content was accepted and published; false for an
    ///             unavailable destination or failed checked save
    ///
    ///
    @discardableResult
    func addCard(
        to listID: Int, title: String, description: String, subtitle: String, presentation: ItemPresentation? = nil,
        actions: [String]? = nil, attachments: [KanbanAttachment] = [], schedule: QuickCaptureSchedule? = nil,
        checkedSave: Bool = false
    ) -> Bool
    {


        guard
        let listIndex = lists.firstIndex(where:
            {  /* Destination list index */


                $0.id == listID
            })
        else
        {


            return false
        }


        let nextCardID = (lists.flatMap
            {
                $0.allCards.map(\.id)
            } .max() ?? -1) + 1             /* Board-wide next card ID       */
        var updatedList = lists[listIndex]  /* Mutable destination-list copy */

        var created = updatedList.makeItems(
            startingAt: nextCardID, titles: title, description: description.isEmpty ? nil : description,
            subtitle: subtitle, presentation: presentation, actions: actions
        )
        guard !created.isEmpty, schedule?.isValid() != false else
        {
            return false
        }

        for index in created.indices
        {
            schedule?.apply(to: &created[index])
        }

        if !attachments.isEmpty
        {

            created[0].attachments = attachments;

            created[0].coverAttachmentID = attachments.first(where:
                {
                    $0.kind == .photo
                })?.id
        }

        updatedList.cards.append(contentsOf: created)
        if let first = created.first
        {
            DaySections.reveal(first.id, in: &updatedList.cards)
        }

        var updatedLists = lists
        updatedLists[listIndex] = updatedList
        if checkedSave || !attachments.isEmpty || schedule != nil
        {

            guard var document = calendarDocument,
            let weekIndex = document.weeks.firstIndex(where:
                {
                    $0.startKey == document.currentWeekKey
                })
            else
            {
                return false
            }

            document.weeks[weekIndex].collection.lists = updatedLists
            do
            {

                try DailyReviewTransaction.perform
                {

                    try PlanningCalendarStore.save(document)
                    try KanbanBoardPersistence.saveListsChecked(updatedLists)
                }

                calendarDocument = document
            }
            catch
            {

                if UserDefaults.standard.object(forKey: DailyReviewTransaction.key) != nil
                {

                    workspaceRecoveryError = "The capture could not be saved. Retry recovery before continuing."
                }

                return false
            }

        }

        lists = updatedLists
        if let card = created.first
        {

            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            CreatedContentReveal.shared.request(listID: listID, card: card)
            openBoardList(listID)
        }

        return true
    }

}
