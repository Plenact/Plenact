// --------------------------------------------------------------------------------------------------
// @file       CreatedContentReveal.swift
// @brief      One-shot navigation to newly committed items
// @details    Retains owner-local identity and creation time until mounted rows can reveal
//             accepted content after layout settles.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Identifies newly created content awaiting reveal
///
/// @section    Purpose
///     Includes List ID, Card ID, and creation time so a one-shot request cannot accidentally match
///     a reused local identity.
///
struct CreatedContentTarget: Identifiable, Equatable
{


    let id = UUID()
    let listID:    Int
    let cardID:    Int
    let createdAt: Date


    ///
    /// @fcn        CreatedContentTarget.matches
    /// @brief      Match a reveal request to its destination list
    /// @details    Checks list ID, card ID, and creation timestamp together to avoid matching a reused numeric ID.
    ///
    /// @param[in]  list  List supplying the current content and metadata
    ///
    /// @return     (Bool) true only when list ID, card ID, and creation timestamp all match
    ///
    func matches(_ list: KanbanList) -> Bool
    {

        list.id == listID && list.cards.contains
        {
            $0.id == cardID && $0.createdAt == createdAt
        }

    }

}


///
/// Publishes a one-shot newly created content reveal request
///
/// @section    Purpose
///     Keeps List, Card, and creation-time identity together so mounted rows can consume the
///     correct request after composition ends.
///
@MainActor
final class CreatedContentReveal: ObservableObject
{


    static let shared = CreatedContentReveal()
    @Published private(set) var target: CreatedContentTarget?


    ///
    /// @fcn        CreatedContentReveal.request
    /// @brief      Queue a newly created card for scrolling into view
    /// @details    Stores its list, ID, and creation timestamp; cards without a timestamp do not replace the current
    ///             request.
    ///
    /// @param[in]  listID  Numeric list identity within its owner
    /// @param[in]  card    Card or note being inspected or changed
    ///
    /// @return     (Void) no return value
    ///
    func request(listID: Int, card: KanbanCard)
    {

        guard let createdAt = card.createdAt else
        {
            return
        }

        target = CreatedContentTarget(listID: listID, cardID: card.id, createdAt: createdAt)
    }


    ///
    /// @fcn        CreatedContentReveal.complete
    /// @brief      Consume the reveal request that just finished
    /// @details    Clears the pending target only if its identity still matches, preserving a newer request.
    ///
    /// @param[in]  request  Request supplied to this operation
    ///
    /// @return     (Void) no return value
    ///
    func complete(_ request: CreatedContentTarget)
    {

        if target?.id == request.id
        {
            target = nil
        }

    }

}


///
/// Reveals newly committed content after layout settles
///
/// @section    Purpose
///     Waits for row registration and composer dismissal and repeats measurement after the preview
///     reaches its final height.
///
struct RevealCreatedContent: ViewModifier
{


    let lists:         [KanbanList]
    var existingProxy: ScrollViewProxy? = nil
    @ObservedObject private var reveal = CreatedContentReveal.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var request: CreatedContentTarget?
    {

        reveal.target.flatMap
        {
            target in
            lists.contains(where: target.matches) ? target : nil
        }

    }


    ///
    /// @fcn        RevealCreatedContent.body
    /// @brief      Attach scrolling support for newly created content
    /// @details    Reuses an existing scroll proxy when supplied; otherwise installs its own ScrollViewReader.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) attach scrolling support for newly created content
    ///
    @ViewBuilder
    func body(content: Content) -> some View
    {

        if let existingProxy
        {

            revealing(content, using: existingProxy)
        }
        else
        {

            ScrollViewReader
            {
                proxy in
                revealing(content, using: proxy)
            }

        }

    }


    ///
    /// @fcn        RevealCreatedContent.revealing
    /// @brief      Scroll to a pending creation after layout settles
    /// @details    Checks cancellation and request identity around delayed scrolling, respects Reduce Motion, and
    ///             consumes only the completed request.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    /// @param[in]  proxy    Scroll proxy for the enclosing content reader
    ///
    /// @return     (some View) scroll to a pending creation after layout settles
    ///
    private func revealing(_ content: Content, using proxy: ScrollViewProxy) -> some View
    {

        content.task(id: request?.id)
        {

            guard let request else
            {
                return
            }

            do
            {

                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, reveal.target?.id == request.id else
                {
                    return
                }

                if reduceMotion
                {

                    proxy.scrollTo(request.cardID, anchor: .center)
                }
                else
                {

                    withAnimation(.easeInOut(duration: 0.25))
                    {
                        proxy.scrollTo(request.cardID, anchor: .center)
                    }

                }

                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, reveal.target?.id == request.id else
                {
                    return
                }

                proxy.scrollTo(request.cardID, anchor: .center)
                reveal.complete(request)
            }
            catch
            {  /* A changed destination or dismissed view cancels its reveal. */

            }

        }

    }

}
