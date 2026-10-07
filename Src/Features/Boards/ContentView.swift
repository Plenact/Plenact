// --------------------------------------------------------------------------------------------------
// @file       ContentView.swift
// @brief      Kanban board screen and reusable board views
// @details    Composes horizontally paged Week/personal boards and the focused Today list.
//             Provides shared card rows, creation/editing forms, board/member settings, and
//             list/card archive browsers. Coordinates list/card movement, hold-and-drag list
//             reordering, detail navigation, label persistence, and attachment retention
//
// @notes      Board data flows through caller-owned bindings; onListsChanged controls active-list
//             persistence. App-root callers retain and save complete active/archive snapshots.
//             Board presentation is a local preference; badge settings, list tint/watch state,
//             and member colors are transient view state.
//             Archive operations retain card records and files; deletion may trigger file pruning
//
// @section    Opens
//     Consider extracting board settings, archive browsers, and card/list forms into focused files
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UniformTypeIdentifiers

///
/// Adds active and archived projections to a complete Board-list binding
///
/// @section    Purpose
///     Let child views update one partition without discarding the other
///
extension Binding where Value == [KanbanList] {

    ///
    /// @fcn        Binding.activeLists
    /// @brief      Expose the active partition of a complete Board list binding
    /// @details    Getter filters archived lists; setter replaces the active portion while retaining
    ///             current archived entries after it. Supplied active entries are not normalized
    ///
    /// @return     (Binding<[KanbanList]>) projected active-list binding
    /// @pre        Setter values represent active lists with isArchived false
    /// @post       Constructing the projection does not mutate the underlying snapshot
    ///
    var activeLists: Binding<[KanbanList]> {
        Binding(
            get: { wrappedValue.filter { !$0.isArchived } },
            set: { wrappedValue = $0 + wrappedValue.filter(\.isArchived) }
        )
    }

    ///
    /// @fcn        Binding.archivedLists
    /// @brief      Expose the archived partition of a complete Board list binding
    /// @details    Getter filters archived entries; setter retains active entries first and
    ///             replaces the archive portion, forcing every supplied entry's archive flag true
    ///
    /// @return     (Binding<[KanbanList]>) projected archived-list binding
    /// @post       Setter writes preserve the active portion; constructing the projection does not write
    ///
    var archivedLists: Binding<[KanbanList]> {
        Binding(
            get: { wrappedValue.filter(\.isArchived) },
            set: { archived in
                wrappedValue = wrappedValue.filter { !$0.isArchived } + archived.map { list in
                    var archivedList = list
                    archivedList.isArchived = true
                    return archivedList
                }
            }
        )
    }
}


///
/// Stores optional presentation controls for cards on the Board
///
/// @section    Purpose
///     Keep card progress, comment, and date visibility preferences together
///
struct BoardDisplaySettings {
    /// Whether cards show checklist completion progress.
    var showChecklistProgress = true    /* Display checklist progress on cards */
    /// Whether cards show their comment count.
    var showCommentCounts     = true    /* Display comment counts on cards     */
    /// Whether cards show due-date badges.
    var showDueDateBadges     = true    /* Display due date badges on cards    */
}

///
/// Selects the density and width behavior of Board columns
///
/// @section    Purpose
///     Offer a readable Standard layout and a compact Overview layout
///
enum BoardPresentation: String, CaseIterable, Identifiable {
    case standard
    case overview

    /// User-defaults key for the locally stored Board presentation selection.
    static let storageKey = "Plenact.BoardPresentation.v1"

    ///
    /// @fcn        BoardPresentation.id
    /// @brief      Identify a Board presentation option
    /// @details    Uses the stable raw case value for SwiftUI selection identity
    ///
    /// @return     (String) presentation identity
    /// @post       No presentation preference is changed
    ///
    var id: String { rawValue }

    ///
    /// @fcn        BoardPresentation.title
    /// @brief      Provide the user-facing name of a presentation option
    /// @details    Maps each layout case to its menu label
    ///
    /// @return     (String) Standard or Overview
    /// @post       The selected presentation remains unchanged
    ///
    var title: String { self == .standard ? "Standard" : "Overview" }

    ///
    /// @fcn        BoardPresentation.minimumCardHeight
    /// @brief      Provide the minimum card height for this layout
    /// @details    Standard cards retain more vertical space than Overview cards
    ///
    /// @return     (CGFloat) minimum card height in points
    /// @post       No view or preference state is modified
    ///
    var minimumCardHeight: CGFloat { self == .standard ? 112 : 80 }

    ///
    /// @fcn        BoardPresentation.columnWidth(viewportWidth:accessibilitySize:)
    /// @brief      Calculate the column width for this presentation
    /// @details    Accessibility text sizing receives all usable width; other sizes use a
    ///             layout-specific maximum while retaining horizontal margins
    ///
    /// @param[in]  viewportWidth      Available viewport width in points
    /// @param[in]  accessibilitySize  Whether the current text size is an accessibility size
    ///
    /// @return     (CGFloat) column width in points
    ///
    /// @pre        Widths at or below the horizontal inset are treated as invalid
    /// @post       No Board state is modified
    ///
    func columnWidth(viewportWidth: CGFloat, accessibilitySize: Bool) -> CGFloat {

        guard viewportWidth.isFinite, viewportWidth > 28 else {

            return 1
        }

        let available = viewportWidth - 28

        if accessibilitySize {

            return available
        }

        return min(available, self == .standard ? 360 : 240)
    }
}

///
/// Collects measured card heights from list-card views
///
/// @section    Purpose
///     Let a list calculate its vertical card-collection size from rendered content
///
private struct BoardCardHeightPreferenceKey: PreferenceKey {
    /// Current card-height reports keyed by card identity.
    static var defaultValue: [Int: CGFloat] = [:]

    ///
    /// @fcn        BoardCardHeightPreferenceKey.reduce(value:nextValue:)
    /// @brief      Merge card-height reports from child views
    /// @details    The latest value replaces an earlier report for the same card identity
    ///
    /// @param[in,out] value      Accumulated card-height map
    /// @param[in]     nextValue  Provider of the next child height map
    ///
    /// @return     (Void) merges the next report into value
    ///
    /// @post       Card identities not reported by nextValue remain in the map
    ///
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {

        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}


///
/// Reports card frames for same-Board insertion boundaries
///
/// @section    Purpose
///     Locate visible card rows without copying their content into a drag payload
///
private struct BoardCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    ///
    /// @fcn        BoardCardFramePreferenceKey.reduce(value:nextValue:)
    /// @brief      Merge visible card-frame reports by card identity
    /// @details    Uses the latest child report for each identity so drop targeting follows current
    ///             row geometry.
    ///
    /// @param[in,out] value      Accumulated preference values updated in place
    /// @param[in]     nextValue  Provider of the next child preference report
    ///
    /// @return     (Void) merges the next report into the accumulated frame map
    ///
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {

        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct BoardListFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    ///
    /// @fcn        BoardListFramePreferenceKey.reduce(value:nextValue:)
    /// @brief      Merge Board list-panel frame reports by list identity
    /// @details    Keeps the latest frame for each list so hit testing uses the currently measured
    ///             panels.
    ///
    /// @param[in,out] value      Accumulated preference values updated in place
    /// @param[in]     nextValue  Provider of the next child preference report
    ///
    /// @return     (Void) merges the next report into the accumulated frame map
    ///
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {

        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// Install a native drag interaction on the row's content container, separate from List reordering.
struct BoardCardDragSource: UIViewRepresentable {
    static let contentType = UTType(exportedAs: "com.plenact.local-board-card", conformingTo: .data)
    let token: String
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    final class Probe: UIView {
        weak var coordinator: Coordinator?

        ///
        /// @fcn        BoardCardDragSource.Probe.didMoveToWindow()
        /// @brief      Install the card drag source after the probe enters a window
        /// @details    Calls the superclass lifecycle hook, then asks the coordinator to locate the
        ///             enclosing card cell.
        ///
        /// @return     (Void) attempts native interaction installation
        ///
        override func didMoveToWindow() {

            super.didMoveToWindow()
            coordinator?.install(from: self)
        }
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var source: BoardCardDragSource
        weak var container: UIView?
        var interaction: UIDragInteraction?
        private(set) var isDragging = false
        var isDetached = false

        init(_ source: BoardCardDragSource) {

            self.source = source
        }

        ///
        /// @fcn        BoardCardDragSource.Coordinator.install(from:)
        /// @brief      Attach an enabled native drag interaction to the enclosing card cell
        /// @details    Walks probe ancestors only after window attachment, reuses the current
        ///             content container, and removes an earlier interaction when the container
        ///             changes.
        ///
        /// @param[in]  probe  Row probe used to locate the enclosing native container
        ///
        /// @return     (Void) installs or retains the card-cell interaction
        ///
        func install(from probe: UIView) {

            guard probe.window != nil else {

                return
            }

            var ancestor = probe.superview

            while let view = ancestor {

                if let cell = view as? UICollectionViewCell {

                    guard container !== cell.contentView else {

                        return
                    }

                    if let interaction {

                        container?.removeInteraction(interaction)
                    }

                    let drag = UIDragInteraction(delegate: self)

                    drag.isEnabled = true
                    cell.contentView.addInteraction(drag)
                    container = cell.contentView
                    interaction = drag

                    return
                }

                ancestor = view.superview
            }
        }

        ///
        /// @fcn        BoardCardDragSource.Coordinator.begin(at:)
        /// @brief      Begin a local card session and construct its token-only provider
        /// @details    Marks the source active and reports the starting point. Registers only the
        ///             Board token bytes with own-process visibility; card content and attachment
        ///             references are excluded.
        ///
        /// @param[in]  point  Pointer location in the Board window coordinate space
        ///
        /// @return     (NSItemProvider) provider carrying the local Board token
        ///
        func begin(at point: CGPoint) -> NSItemProvider {

            isDragging = true
            source.onBegan(point)

            let provider = NSItemProvider()

            provider.suggestedName = source.token

            let data = Data(source.token.utf8)

            provider.registerDataRepresentation(forTypeIdentifier: BoardCardDragSource.contentType.identifier,
                                                visibility: .ownProcess) { completion in
                completion(data, nil)

                return nil
            }

            return provider
        }

        ///
        /// @fcn        BoardCardDragSource.Coordinator.finish()
        /// @brief      End an active native drag session exactly once
        /// @details    Ignores repeated completion, reports session termination, and removes the
        ///             interaction if its source probe was detached.
        ///
        /// @return     (Void) clears active-session state and performs deferred cleanup
        ///
        func finish() {

            guard isDragging else {

                return
            }

            isDragging = false
            source.onEnded()

            if isDetached, let interaction {

                container?.removeInteraction(interaction)
            }
        }

        ///
        /// @fcn        BoardCardDragSource.Coordinator.dragInteraction(_:itemsForBeginning:)
        /// @brief      Create a native drag item for an attached card source
        /// @details    Requires the interaction window, begins the token-only source session, and
        ///             retains this coordinator through the item localObject.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        ///
        /// @return     ([UIDragItem]) single local drag item, or an empty array without a window
        ///
        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {

            guard let window = interaction.view?.window else {

                return []
            }

            let item = UIDragItem(itemProvider: begin(at: session.location(in: window)))

            item.localObject = self

            return [item]
        }

        ///
        /// @fcn        BoardCardDragSource.Coordinator.dragInteraction(_:sessionDidMove:)
        /// @brief      Forward the native drag pointer to Board hover state
        /// @details    Converts the session point through the interaction window; ignores movement
        ///             when the source has no window.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        ///
        /// @return     (Void) reports the current pointer without editing card records
        ///
        func dragInteraction(_ interaction: UIDragInteraction, sessionDidMove session: UIDragSession) {

            guard let window = interaction.view?.window else {

                return
            }

            source.onChanged(session.location(in: window))
        }

        ///
        /// @fcn        BoardCardDragSource.Coordinator.dragInteraction(_:session:didEndWith:)
        /// @brief      Clean up the source when UIKit ends the native session
        /// @details    Uses the registered session-end delegate signature and forwards completion
        ///             to the idempotent finish path regardless of drop operation.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        /// @param[in]  operation    Final native drop operation; cleanup is independent of its
        ///             value
        ///
        /// @return     (Void) ends the active source session at most once
        ///
        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession,
                             didEndWith operation: UIDropOperation) {
            finish()
        }

        ///
        /// @fcn        BoardCardDragSource.Coordinator.dragInteraction(_:sessionIsRestrictedToDraggingApplication:)
        /// @brief      Restrict native card dragging to this application
        /// @details    Keeps Board-token sessions inside Plenact rather than offering them to other
        ///             apps.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        ///
        /// @return     (Bool) true to restrict the session to the originating application
        ///
        func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool {

            true
        }

        ///
        /// @fcn        BoardCardDragSource.Coordinator.dragInteraction(_:sessionAllowsMoveOperation:)
        /// @brief      Allow native move proposals for local card sessions
        /// @details    Enables UIKit move semantics; canonical movement still validates the
        ///             destination at drop time.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        ///
        /// @return     (Bool) true to allow the move operation
        ///
        func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession) -> Bool {

            true
        }
    }

    ///
    /// @fcn        BoardCardDragSource.makeCoordinator()
    /// @brief      Create the native card-drag coordinator
    /// @details    Captures this representable so UIKit callbacks can forward session lifecycle and
    ///             location updates.
    ///
    /// @return     (Coordinator) coordinator configured with this drag source
    ///
    func makeCoordinator() -> Coordinator {

        Coordinator(self)
    }

    ///
    /// @fcn        BoardCardDragSource.makeUIView(context:)
    /// @brief      Create a noninteractive probe for native card-drag installation
    /// @details    Connects the probe to the SwiftUI coordinator without intercepting touches on
    ///             the card.
    ///
    /// @param[in]  context  SwiftUI context containing the retained coordinator
    ///
    /// @return     (Probe) probe associated with the current coordinator
    ///
    func makeUIView(context: Context) -> Probe {

        let probe = Probe()

        probe.isUserInteractionEnabled = false
        probe.coordinator = context.coordinator

        return probe
    }

    ///
    /// @fcn        BoardCardDragSource.updateUIView(_:context:)
    /// @brief      Refresh the drag coordinator and retry cell installation
    /// @details    Replaces callback and token state with the current representable before locating
    ///             the enclosing cell.
    ///
    /// @param[in]  probe    Row probe used to locate the enclosing native container
    /// @param[in]  context  SwiftUI context containing the retained coordinator
    ///
    /// @return     (Void) updates the source and its native interaction
    ///
    func updateUIView(_ probe: Probe, context: Context) {

        context.coordinator.source = self
        context.coordinator.install(from: probe)
    }

    ///
    /// @fcn        BoardCardDragSource.dismantleUIView(_:coordinator:)
    /// @brief      Detach the probe without canceling a live native drag
    /// @details    Marks the coordinator detached. Removes an idle interaction immediately; an
    ///             active session retains its source and defers removal until finish.
    ///
    /// @param[in]  probe        Row probe used to locate the enclosing native container
    /// @param[in]  coordinator  Coordinator associated with the native session or representable
    ///
    /// @return     (Void) detaches the source while preserving active-session cleanup
    ///
    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        // A live native session may outlast the source cell while the Board scrolls.
        coordinator.isDetached = true

        if !coordinator.isDragging, let interaction = coordinator.interaction {

            coordinator.container?.removeInteraction(interaction)
        }
    }
}

struct BoardCardDropSurface: UIViewRepresentable {
    let token: String
    var isEnabled = true
    let onChanged: (CGPoint) -> Void
    let onDrop: (CGPoint) -> Bool

    final class RetainedInteraction: UIDropInteraction {
        let receiver: Coordinator

        init(receiver: Coordinator) {

            self.receiver = receiver
            super.init(delegate: receiver)
        }
    }

    final class Probe: UIView {
        weak var coordinator: Coordinator?
        ///
        /// @fcn        BoardCardDropSurface.Probe.didMoveToWindow()
        /// @brief      Install the list drop receiver after the probe enters a window
        /// @details    Calls the superclass lifecycle hook, then asks the coordinator to locate the
        ///             enclosing collection view.
        ///
        /// @return     (Void) attempts native receiver installation
        ///
        override func didMoveToWindow() {

            super.didMoveToWindow()
            coordinator?.install(from: self)
        }
    }

    final class Coordinator: NSObject, UIDropInteractionDelegate, UICollectionViewDropDelegate {
        var surface: BoardCardDropSurface
        weak var container: UICollectionView?
        weak var interaction: UIDropInteraction?
        weak var originalDropDelegate: (any UICollectionViewDropDelegate)?

        init(_ surface: BoardCardDropSurface) {

            self.surface = surface
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.install(from:)
        /// @brief      Install or update one retained native receiver per list collection
        /// @details    Walks probe ancestors to find the collection view and reuses its retained
        ///             receiver. Enables native drop delegation in normal mode and restores the
        ///             original delegate when disabled.
        ///
        /// @param[in]  probe  Row probe used to locate the enclosing native container
        ///
        /// @return     (Void) updates the collection interaction and drop delegate
        ///
        func install(from probe: UIView) {

            guard probe.window != nil else {

                return
            }

            var ancestor = probe.superview

            while let view = ancestor {

                if let collection = view as? UICollectionView {

                    if let existing = collection.interactions.compactMap({

                        $0 as? RetainedInteraction
                    }).first {
                        existing.receiver.surface = surface
                        collection.dropDelegate = surface.isEnabled ? existing.receiver : existing.receiver.originalDropDelegate
                        container = collection
                        interaction = existing

                        return
                    }

                    guard container !== collection else {

                        return
                    }

                    let drop = RetainedInteraction(receiver: self)

                    originalDropDelegate = collection.dropDelegate
                    collection.addInteraction(drop)
                    collection.dropDelegate = surface.isEnabled ? self : originalDropDelegate
                    container = collection
                    interaction = drop

                    return
                }

                ancestor = view.superview
            }
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.accepts(_:)
        /// @brief      Validate a single active drag from the same local Board
        /// @details    Requires an enabled surface, exactly one item, a local drag-source
        ///             coordinator, an active source session, and a matching Board token.
        ///
        /// @param[in]  items  Native drag items to validate against the active local Board
        ///
        /// @return     (Bool) whether the items belong to an accepted local session
        ///
        func accepts(_ items: [UIDragItem]) -> Bool {

            surface.isEnabled && items.count == 1 && items.allSatisfy {
                guard let source = $0.localObject as? BoardCardDragSource.Coordinator else {

                    return false
                }

                return source.isDragging && source.source.token == surface.token
            }
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.perform(_:at:)
        /// @brief      Forward an accepted native drop to canonical Board movement
        /// @details    Rejects invalid items before forwarding the final location and invoking the
        ///             Board drop callback.
        ///
        /// @param[in]  items  Native drag items to validate against the active local Board
        /// @param[in]  point  Pointer location in the Board window coordinate space
        ///
        /// @return     (Bool) whether the accepted drop callback performed movement
        ///
        @discardableResult
        func perform(_ items: [UIDragItem], at point: CGPoint) -> Bool {

            guard accepts(items) else {

                return false
            }

            surface.onChanged(point)

            return surface.onDrop(point)
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.dropInteraction(_:canHandle:)
        /// @brief      Accept only a validated local Board drag session
        /// @details    Requires a local native drag session and the shared single-item,
        ///             active-source, matching-token validation.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        ///
        /// @return     (Bool) whether this receiver can handle the local session
        ///
        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {

            session.localDragSession != nil && accepts(session.items)
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.dropInteraction(_:sessionDidUpdate:)
        /// @brief      Update hover geometry and propose a validated local move
        /// @details    Returns a forbidden proposal without accepted items or an attached window.
        ///             Otherwise forwards the window-coordinate pointer to Board targeting and
        ///             proposes a move.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        ///
        /// @return     (UIDropProposal) move proposal for an accepted session, otherwise a
        ///             forbidden proposal
        ///
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {

            guard accepts(session.items), let window = interaction.view?.window else {

                return UIDropProposal(operation: .forbidden)
            }

            surface.onChanged(session.location(in: window))

            return UIDropProposal(operation: .move)
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.dropInteraction(_:performDrop:)
        /// @brief      Forward the final native drop point to the shared receiver
        /// @details    Requires an attached window and invokes the same accepted-item commit path
        ///             used by the other native drop delegate.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        ///
        /// @return     (Void) attempts canonical movement for the validated native items
        ///
        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {

            guard let window = interaction.view?.window else {

                return
            }

            perform(session.items, at: session.location(in: window))
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.collectionView(_:canHandle:)
        /// @brief      Accept only a validated local Board drag session
        /// @details    Requires a local native drag session and the shared single-item,
        ///             active-source, matching-token validation.
        ///
        /// @param[in]  collectionView  List collection view delivering the drop callback
        /// @param[in]  session         Native drag or drop session delivering the callback
        ///
        /// @return     (Bool) whether this receiver can handle the local session
        ///
        func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {

            session.localDragSession != nil && accepts(session.items)
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.collectionView(_:dropSessionDidUpdate:withDestinationIndexPath:)
        /// @brief      Update hover geometry and propose a validated local move
        /// @details    Returns a forbidden proposal without accepted items or an attached window.
        ///             Otherwise forwards the window-coordinate pointer to Board targeting and
        ///             proposes a move.
        ///
        /// @param[in]  collectionView        List collection view delivering the drop callback
        /// @param[in]  session               Native drag or drop session delivering the callback
        /// @param[in]  destinationIndexPath  UIKit destination hint; canonical targeting uses
        ///             pointer geometry instead
        ///
        /// @return     (UICollectionViewDropProposal) move proposal for an accepted session,
        ///             otherwise a forbidden proposal
        ///
        func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                            withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
            guard accepts(session.items), let window = collectionView.window else {

                return UICollectionViewDropProposal(operation: .forbidden)
            }

            surface.onChanged(session.location(in: window))

            return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
        }

        ///
        /// @fcn        BoardCardDropSurface.Coordinator.collectionView(_:performDropWith:)
        /// @brief      Forward the final native drop point to the shared receiver
        /// @details    Requires an attached window and invokes the same accepted-item commit path
        ///             used by the other native drop delegate.
        ///
        /// @param[in]  collectionView  List collection view delivering the drop callback
        /// @param[in]  coordinator     Coordinator associated with the native session or
        ///             representable
        ///
        /// @return     (Void) attempts canonical movement for the validated native items
        ///
        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

            guard let window = collectionView.window else {

                return
            }

            perform(coordinator.session.items, at: coordinator.session.location(in: window))
        }
    }

    ///
    /// @fcn        BoardCardDropSurface.makeCoordinator()
    /// @brief      Create the native list-drop coordinator
    /// @details    Captures this surface so collection and interaction delegates share its current
    ///             token and callbacks.
    ///
    /// @return     (Coordinator) coordinator configured with this drop surface
    ///
    func makeCoordinator() -> Coordinator {

        Coordinator(self)
    }

    ///
    /// @fcn        BoardCardDropSurface.makeUIView(context:)
    /// @brief      Create a noninteractive probe for native list-drop installation
    /// @details    Associates the probe with the SwiftUI coordinator without adding a touch target
    ///             over list content.
    ///
    /// @param[in]  context  SwiftUI context containing the retained coordinator
    ///
    /// @return     (Probe) probe associated with the current coordinator
    ///
    func makeUIView(context: Context) -> Probe {

        let probe = Probe()

        probe.isUserInteractionEnabled = false
        probe.coordinator = context.coordinator

        return probe
    }

    ///
    /// @fcn        BoardCardDropSurface.updateUIView(_:context:)
    /// @brief      Refresh the drop surface and its retained native receiver
    /// @details    Copies current token, enablement, and callbacks into the coordinator before
    ///             locating the list collection.
    ///
    /// @param[in]  probe    Row probe used to locate the enclosing native container
    /// @param[in]  context  SwiftUI context containing the retained coordinator
    ///
    /// @return     (Void) updates receiver state and collection delegation
    ///
    func updateUIView(_ probe: Probe, context: Context) {

        context.coordinator.surface = self
        context.coordinator.install(from: probe)
    }

    ///
    /// @fcn        BoardCardDropSurface.dismantleUIView(_:coordinator:)
    /// @brief      Leave the collection-owned receiver installed during row virtualization
    /// @details    Individual row probes can disappear while the list remains visible. The
    ///             collection retains its shared receiver, so this hook intentionally performs no
    ///             removal.
    ///
    /// @param[in]  probe        Row probe used to locate the enclosing native container
    /// @param[in]  coordinator  Coordinator associated with the native session or representable
    ///
    /// @return     (Void) leaves the shared native receiver unchanged
    ///
    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        // The list retains its one receiver while individual rows are virtualized.
    }
}

///
/// Collects horizontal center measurements for Board lists
///
/// @section    Purpose
///     Identify the list nearest the visible viewport center
///
private struct BoardListCenterPreferenceKey: PreferenceKey {
    /// Current list-center reports keyed by list identity.
    static var defaultValue: [Int: CGFloat] = [:]

    ///
    /// @fcn        BoardListCenterPreferenceKey.reduce(value:nextValue:)
    /// @brief      Merge list-center geometry from child panels
    /// @details    Keeps the latest horizontal center when multiple reports share a list identity
    ///
    /// @param[in,out] value      Accumulated list-ID-to-center map
    /// @param[in]     nextValue  Provider of the next child geometry map
    ///
    /// @return     (Void) merges the next report into value
    ///
    /// @post       Unreported accumulated identities remain in the map
    ///
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {

        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}


// -------------------------------------- MARK: - Board View ------------------------------------ //

///
/// Displays the horizontally scrollable Plenact kanban board
///
/// @section    Purpose
///     Install the board background, header, paged list surface, and navigation path into card details
///
struct ContentView: View {

    @Binding private var lists: [KanbanList]                                                /* Shared kanban board lists                        */
    /// Archived lists belonging to the same board.
    @Binding private var archivedLists: [KanbanList]
    @Binding private var boardTargetListID: Int?                                            /* Requested list to reveal after board navigation  */
    /// Optional card identity to open after navigating to its containing list.
    @Binding private var boardTargetCardID: Int?
    /// Explicit parent requests to return from Card Detail to this Board's root.
    let boardRootRequest: Int
    @Binding private var savedCardIDs: Set<Int>                                             /* Locally bookmarked card identities                */
    /// Reports which list is nearest the center of the visible board.
    let onListViewed: (Int) -> Void
    /// Title displayed in the board header.
    let boardTitle: String
    /// Supporting text displayed beneath the board title.
    let boardSubtitle: String
    /// Whether the board header offers the Add list action.
    let allowsAddingLists: Bool
    /// Optional action that returns to the parent collection view.
    let onClose: (() -> Void)?
    /// Optional parent-owned action for archiving the complete board.
    let onArchiveBoard: (() -> Void)?
    /// Optional parent-owned permanent Board deletion.
    let onDeleteBoard: (() -> Void)?
    /// Names the special Week clearing action without implying removal of its tab.
    let deleteBoardTitle: String
    /// Optional save-first boundary for confirmed card/list removal.
    let onCommitDeletion: (([KanbanList], Set<Int>) throws -> Void)?
    /// Receives active-list snapshots for caller-owned persistence.
    let onListsChanged: @MainActor ([KanbanList]) -> Void
    /// Supplies other retained snapshots whose attachment files must not be pruned.
    let retainedAttachmentLists: () -> [KanbanList]
    /// Controls presentation of the calendar sheet.
    @State private var showsCalendar = false
    /// Controls presentation of archived lists.
    @State private var showsArchivedLists = false
    /// Navigation stack path for card-detail destinations.
    @State private var navigationPath = NavigationPath()
    /// Last visible list identity sent through `onListViewed`.
    @State private var lastReportedVisibleListID: Int?
    /// Currently centered list identity.
    @State private var visibleListID: Int?
    /// List identity currently being dragged for reordering.
    @State private var draggedListID: Int?
    /// Measured horizontal centers keyed by list identity.
    @State private var listCenters: [Int: CGFloat] = [:]
    /// Current horizontal location of an active list drag.
    @State private var listDragLocation: CGFloat?
    /// Horizontal offset between the drag start and the grabbed list center.
    @State private var listDragGrabOffset: CGFloat = 0
    @State private var draggedCardID: Int?
    @State private var cardDragLocation: CGPoint?
    @State private var cardFrames: [Int: CGRect] = [:]
    @State private var listFrames: [Int: CGRect] = [:]
    @State private var cardDragViewportFrame: CGRect = .zero
    @State private var cardDragToken = UUID().uuidString
    /// Environment preference used to reduce or remove animated transitions.
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    /// Current Dynamic Type size used when selecting Board dimensions.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    /// Locally persisted choice between Standard and Overview Board layouts.
    @AppStorage(BoardPresentation.storageKey) private var presentation = BoardPresentation.standard
    @State private var labelLibrary                  = LabelLibraryStore.load()             /* Label library containing all available labels    */
    @State private var displaySettings               = BoardDisplaySettings()               /* Board display settings                           */
    @State private var memberColors: [String: Color] = [:]                                  /* Mapping of member names to their assigned colors */
    @State private var currentUserName               = "Justin Reina"                       /* Current user's name                              */


    ///
    /// @fcn        ContentView.init
    /// @brief      Configure the shared Board surface, routing, and mutation callbacks
    /// @details    Accepts caller-owned active/archive partitions and optional list/card targets.
    ///             Defaults support standalone Week previews; app-root and personal-board callers
    ///             override persistence and retained attachment references for their complete snapshots
    ///
    /// @param[in]  lists                    Binding to active Board lists
    /// @param[in]  archivedLists            Binding to archived Board lists
    /// @param[in]  boardTargetListID        Pending active list ID to reveal
    /// @param[in]  boardTargetCardID        Pending card ID to open within the target list
    /// @param[in]  boardRootRequest         Changing request value returns navigation to the Board root
    /// @param[in]  savedCardIDs             Binding to this Board's bookmarked card identities
    /// @param[in]  onListViewed             Callback reporting the nearest visible list
    /// @param[in]  boardTitle               Header title
    /// @param[in]  boardSubtitle            Header supporting text
    /// @param[in]  allowsAddingLists        Whether the header normally offers list creation
    /// @param[in]  onClose                  Optional action returning to the collection directory
    /// @param[in]  onArchiveBoard           Optional parent-owned full-board archive action
    /// @param[in]  onListsChanged           Main-actor callback receiving active-list changes
    /// @param[in]  retainedAttachmentLists  Provider of other snapshots whose photo files must survive pruning
    ///
    /// @return     (ContentView) configured kanban board screen
    ///
    /// @pre        lists contains the board state to display
    /// @post       Bindings and callbacks are installed without editing Board content
    /// @note       The archive binding defaults to constant empty state; persistent archives require
    ///             a writable binding. An empty board exposes Add list even when normally disabled
    ///
    init(
        lists: Binding<[KanbanList]>,
        archivedLists: Binding<[KanbanList]>  = .constant([]),
        boardTargetListID: Binding<Int?>      = .constant(nil),
        boardTargetCardID: Binding<Int?>      = .constant(nil),
        boardRootRequest: Int                 = 0,
        savedCardIDs: Binding<Set<Int>>       = .constant([]),
        onListViewed: @escaping (Int) -> Void = { _ in },
        boardTitle: String                    = "Plenact",
        boardSubtitle: String                 = "Work Week Board",
        allowsAddingLists: Bool               = true,
        onClose: (() -> Void)?                = nil,
        onArchiveBoard: (() -> Void)?         = nil,
        onDeleteBoard: (() -> Void)?          = nil,
        deleteBoardTitle: String              = "Delete Board",

        onCommitDeletion: (([KanbanList], Set<Int>) throws -> Void)? = nil,
        onListsChanged: @escaping @MainActor ([KanbanList]) -> Void = KanbanBoardPersistence.saveListsInBackground,

        retainedAttachmentLists: @escaping () -> [KanbanList] = {
                                                                    PersonalCollectionStore.load().flatMap(\.lists) + (ExampleLoadUndoStore.load()?.lists ?? [])
                                                                }
    ) {
        _lists                       = lists
        _archivedLists               = archivedLists
        _boardTargetListID           = boardTargetListID
        _boardTargetCardID           = boardTargetCardID
        self.boardRootRequest        = boardRootRequest
        _savedCardIDs                = savedCardIDs
        self.onListViewed            = onListViewed
        self.boardTitle              = boardTitle
        self.boardSubtitle           = boardSubtitle
        self.allowsAddingLists       = allowsAddingLists
        self.onClose                 = onClose
        self.onArchiveBoard          = onArchiveBoard
        self.onDeleteBoard           = onDeleteBoard
        self.deleteBoardTitle        = deleteBoardTitle
        self.onCommitDeletion        = onCommitDeletion
        self.onListsChanged          = onListsChanged
        self.retainedAttachmentLists = retainedAttachmentLists
    }


    ///
    /// @fcn        ContentView.openPendingBoardTarget(using:)
    /// @brief      Consume a pending list/card navigation request
    /// @details    Scrolls an existing active list into view and, for an existing target card,
    ///             replaces the detail path with that card. Missing lists invalidate both targets
    ///
    /// @param[in]  listProxy  Proxy for the horizontal list viewport
    ///
    /// @return     (Void) updates scroll position and optional card navigation
    ///
    /// @post       Both pending targets are cleared; a missing card leaves the existing path
    ///             unchanged
    ///
    private func openPendingBoardTarget(using listProxy: ScrollViewProxy) {

        guard let targetListID = boardTargetListID,
              lists.contains(where: { $0.id == targetListID }) else {
            boardTargetListID = nil
            boardTargetCardID = nil

            return
        }

        visibleListID = targetListID
        listProxy.scrollTo(targetListID, anchor: .leading)

        if let targetCardID = boardTargetCardID,
           let card = lists.first(where: { $0.id == targetListID })?.cards.first(where: { $0.id == targetCardID }) {
            navigationPath = NavigationPath()
            navigationPath.append(card)
        }

        boardTargetListID = nil
        boardTargetCardID = nil
    }


    ///
    /// @fcn        ContentView.activeMembers
    /// @brief      Return unique users assigned to active cards
    /// @details    Traverses cards in board order, excludes divider items, trims surrounding whitespace,
    ///             and retains the first occurrence of each member name using case-insensitive matching
    ///
    /// @return     ([String]) ordered member names currently assigned to non-divider cards
    ///
    /// @pre        lists contains the current in-memory board state
    /// @post       No board data is modified; duplicate and empty names are omitted from the result
    ///
    private var activeMembers: [String] { /* Unique names assigned to non-divider cards */

        var seenMembers: Set<String> = []       /* Track unique members to avoid duplicates */

        return lists
            .flatMap(\.cards)
            .filter { !$0.isSectionDivider }
            .flatMap(\.members)
            .compactMap { assignee in

                let trimmedMember    = assignee.displayName.trimmingCharacters(in: .whitespacesAndNewlines) /* Display name */
                let normalizedMember = trimmedMember.lowercased()                               /* Normalize the member name for case-insensitive comparison */

                guard !trimmedMember.isEmpty, seenMembers.insert(normalizedMember).inserted else {

                    return nil
                }

                return trimmedMember
            }
    }

    
    ///
    /// @fcn        ContentView.renameMember(from:to:)
    /// @brief      Rename a member across the board
    /// @details    Renames matching manual assignments and comment authors on active cards, trims
    ///             assignment names, and deduplicates manual names or registered-user identities.
    ///             Updates the current author and migrates its icon color when applicable
    ///
    /// @param[in]  currentName   Existing member name to replace
    /// @param[in]  proposedName  Proposed new name; surrounding whitespace is trimmed
    ///
    /// @return     (Void) updates card assignments, authored comments, current-user display, and
    ///             color mapping
    ///
    /// @pre        currentName identifies the member being renamed
    /// @post       Registered-user identities/display names are not renamed, beyond whitespace
    ///             trimming; archived content is untouched. Blank proposals leave all state
    ///             unchanged
    /// @note       An empty proposed name is ignored; if the new name already has a color, that
    ///             color is retained
    ///
    private func renameMember(from currentName: String, to proposedName: String) {

        let updatedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines) /* Trimmed replacement name */

        guard !updatedName.isEmpty else {

            return
        }

        let currentKey = currentName.lowercased()       /* Normalized key for the current member name */
        let updatedKey = updatedName.lowercased()       /* Normalized key for the updated member name */    

        for listIndex in lists.indices {

            for cardIndex in lists[listIndex].cards.indices {

                var updatedCard            = lists[listIndex].cards[cardIndex]  /* Copy of the current card for in-place updates     */
                var seenNames: Set<String> = []                                 /* Track unique member names within the current card */

                updatedCard.members = updatedCard.members.compactMap { assignee in

                    let trimmedMember = assignee.displayName.trimmingCharacters(in: .whitespacesAndNewlines) /* Existing display name */
                    let renamedMember = assignee.kind == .manual && trimmedMember.lowercased() == currentKey /* Match only manual names */
                        ? updatedName
                        : trimmedMember /* Name retained or updated for this assignment */
                    let normalizedName = assignee.kind == .registeredUser /* Namespace stable IDs separately from names */
                        ? "user:\(assignee.userID ?? assignee.id.uuidString)"
                        : "manual:\(renamedMember.lowercased())" /* Stable deduplication key */

                    guard !renamedMember.isEmpty, seenNames.insert(normalizedName).inserted else {

                        return nil
                    }

                    return CardAssignee(
                        id:          assignee.id,
                        kind:        assignee.kind,
                        userID:      assignee.userID,
                        displayName: renamedMember
                    )
                }

                updatedCard.comments = updatedCard.comments.map { comment in

                    guard comment.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentKey else {

                        return comment
                    }

                    return KanbanComment(
                        id:        comment.id,
                        author:    updatedName,
                        body:      comment.body,
                        createdAt: comment.createdAt
                    )
                }

                lists[listIndex].cards[cardIndex] = updatedCard
            }
        }

        if currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentKey {

            currentUserName = updatedName
        }

        if currentKey != updatedKey, let existingColor = memberColors.removeValue(forKey: currentKey) { /* Preserve the old icon color */

            memberColors[updatedKey] = memberColors[updatedKey] ?? existingColor
        }
    }


    ///
    /// @fcn        ContentView.removeMember(_:)
    /// @brief      Remove a member from board assignments
    /// @details    Removes matching names from active cards and clears their board icon color while
    ///             preserving historical comments
    ///
    /// @param[in]  memberName  Member name to remove; comparison ignores surrounding whitespace and
    ///             case
    ///
    /// @return     (Void) updates the board and member color state
    ///
    /// @pre        memberName identifies a member currently assigned to at least one card
    /// @post       Matching active-card assignments are removed; comments and archives remain
    ///             unchanged. Removing the current author name resets its display value to You
    ///
    private func removeMember(_ memberName: String) {

        let normalizedMemberName = memberName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() /* Normalized removal key */

        guard !normalizedMemberName.isEmpty else {

            return
        }

        for listIndex in lists.indices {

            for cardIndex in lists[listIndex].cards.indices {

                lists[listIndex].cards[cardIndex].members.removeAll { member in

                    member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedMemberName
                }
            }
        }

        memberColors.removeValue(forKey: normalizedMemberName)

        if currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedMemberName {

            currentUserName = "You"
        }
    }


    ///
    /// @fcn        ContentView.setMemberColor(_:color:)
    /// @brief      Store the shared icon color for a member
    /// @details    Writes the selected color under the member's lowercased name so all matching
    ///             icons resolve consistently
    ///
    /// @param[in]  memberName  Name of the member whose icon color is being changed
    /// @param[in]  color       New color selected for that member
    ///
    /// @return     (Void) updates the board-level member color mapping
    ///
    /// @pre        memberName identifies an active member
    /// @post       Views using the normalized member key receive the selected color
    ///
    private func setMemberColor(_ memberName: String, color: Color) {

        memberColors[memberName.lowercased()] = color
    }


    ///
    /// @fcn        ContentView.addList()
    /// @brief      Append a new empty list to the board
    /// @details    Reserves identifiers across active and archived lists, then generates a New List
    ///             title that does not case-insensitively duplicate an active list name
    ///
    /// @return     (Void) updates the board's in-memory list collection
    ///
    /// @pre        The board list collection has been initialized
    /// @post       A uniquely identified empty list is appended to the board
    ///
    private func addList() {

        let nextListID     = ((lists + archivedLists).map(\.id).max() ?? -1) + 1 /* Board-wide next list ID */
        let existingTitles = Set(lists.map { $0.title.lowercased() }) /* Normalized current titles */
        var newTitle       = "New List" /* First candidate list name */
        var suffix         = 2 /* Duplicate-title suffix */

        while existingTitles.contains(newTitle.lowercased()) {

            newTitle = "New List \(suffix)"
            suffix  += 1
        }

        lists.append(KanbanList(id: nextListID, title: newTitle, cards: []))
    }


    ///
    /// @fcn        ContentView.addCard(to:title:description:)
    /// @brief      Add a completed card form to the end of the selected list
    /// @details    Allocates an identifier across active and archived cards/lists, stores the
    ///             supplied title/description, and recognizes divider-marker titles
    ///
    /// @param[in]  listID       Stable identifier of the list receiving the card
    /// @param[in]  title        User-entered card title
    /// @param[in]  description  User-entered card description
    ///
    /// @return     (Void) updates the matching list in the board state
    ///
    /// @pre        The caller validates and trims the title and description
    /// @post       The new card appears last; a missing destination leaves Board state unchanged
    ///
    private func addCard(to listID: Int, title: String, description: String) {

        guard let listIndex = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        } /* Destination list index */

        let nextCardID  = ((lists + archivedLists).flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1 /* Board-wide next card ID */
        var updatedList = lists[listIndex] /* Mutable destination-list copy */

        /// Append the new card to the list's cards array
        updatedList.cards.append(
            KanbanCard(
                id:                  nextCardID,
                word:                title,
                listTitle:           updatedList.title,
                isDivider:           KanbanCard.isDividerTitle(title),
                descriptionOverride: description
            )
        )

        lists[listIndex] = updatedList
    }


    ///
    /// @fcn        ContentView.deleteCard(_:)
    /// @brief      Remove one confirmed card from this Board
    /// @details    Includes active/archive partitions and delegates save-first removal to the
    ///             owner; media cleanup occurs only after persistence succeeds
    ///
    /// @param[in]  cardID  Stable identifier of the card to delete
    ///
    /// @return     (Bool) whether the card and bookmark were successfully removed
    ///
    /// @post       Failed saves leave the canonical records unchanged
    ///
    @discardableResult
    private func deleteCard(_ cardID: Int) -> Bool {

        var snapshot = lists + archivedLists
        var bookmarks = savedCardIDs

        BoardContentDeletion.card(cardID, in: &snapshot, savedCardIDs: &bookmarks)

        return commitDeletion(snapshot, bookmarks: bookmarks)
    }

    ///
    /// @fcn        ContentView.deleteList(_:)
    /// @brief      Permanently remove a confirmed list and its retained cards
    /// @details    Updates both partitions and removes only this Board's contained bookmarks
    ///
    /// @param[in]  id  List identity in this Board
    ///
    /// @return     (Void) updates caller-owned state without pruning unsaved media references
    ///
    private func deleteList(_ id: Int) {

        var snapshot = lists + archivedLists
        var bookmarks = savedCardIDs

        BoardContentDeletion.list(id, in: &snapshot, savedCardIDs: &bookmarks)
        commitDeletion(snapshot, bookmarks: bookmarks)
    }

    ///
    /// @fcn        ContentView.commitDeletion(_:bookmarks:)
    /// @brief      Delegate permanent removal to the owner's save-first boundary
    /// @details    Production callers persist the complete snapshot before publishing state
    ///
    /// @param[in]  snapshot   Proposed remaining lists including archives
    /// @param[in]  bookmarks  Remaining Board-local bookmarks
    ///
    /// @return     (Bool) successful persistence/publication, or false after a reported error
    ///
    @discardableResult
    private func commitDeletion(_ snapshot: [KanbanList], bookmarks: Set<Int>) -> Bool {

        do {

            if let onCommitDeletion {

                try onCommitDeletion(snapshot, bookmarks)
            } else {
                lists = snapshot.filter { !$0.isArchived }
                archivedLists = snapshot.filter(\.isArchived)
                savedCardIDs = bookmarks
            }

            return true
        } catch {
            DatabaseActivity.shared.report("Could not delete content: \(error.localizedDescription) It has been retained.")

            return false
        }
    }

    ///
    /// @fcn        ContentView.moveCard(in:cardID:toIndex:)
    /// @brief      Reorder one card within a board list
    /// @details    Removes the source card and inserts it at the target card's position
    ///
    /// @param[in]  listID            Stable identifier of the list to reorder
    /// @param[in]  cardID            Stable identifier of the card being moved
    /// @param[in]  destinationIndex  Zero-based destination index in the list
    ///
    /// @return     (Void) updates the card order in the selected list
    ///
    /// @pre        listID identifies a list containing cardID
    /// @post       The card occupies the clamped valid destination; missing IDs or unchanged
    ///             positions do nothing. Card content remains unchanged
    ///
    private func moveCard(in listID: Int, cardID: Int, toIndex destinationIndex: Int) {

        guard let listIndex = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        } /* List being reordered */

        var cards = lists[listIndex].cards /* Mutable card-order copy */

        guard let sourceIndex = cards.firstIndex(where: {

            $0.id == cardID
        }), !cards.isEmpty else {
            return
        } /* Original card position */

        let safeDestinationIndex = min(max(destinationIndex, 0), cards.count - 1) /* Clamped insertion position */

        guard sourceIndex != safeDestinationIndex else {

            return
        }

        let movedCard = cards.remove(at: sourceIndex) /* Card removed before reinsertion */

        cards.insert(movedCard, at: safeDestinationIndex)

        // Update the list with the reordered cards, animating the change for a smooth user experience
        withAnimation(.easeInOut(duration: 0.2)) {
            lists[listIndex].cards = cards
        }
    }


    ///
    /// @fcn        ContentView.copyList(with:)
    /// @brief      Insert a copy of the selected list beside its source
    /// @details    Reserves new IDs across active/archive content and copies active cards with
    ///             their full state and shared attachment references. Archived cards and list
    ///             metadata are not copied; the new list uses model defaults and a Copy title
    ///             suffix
    ///
    /// @param[in]  listID  Stable identifier of the list to copy
    ///
    /// @return     (Void) inserts the copied list immediately after the source list
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The board contains a distinct copy with unique list and card identifiers
    ///
    private func copyList(with listID: Int) {

        guard let sourceIndex = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        } /* Source list position */

        let source       = lists[sourceIndex] /* Source list snapshot */
        let copiedTitle  = "\(source.title) Copy" /* New list display title */
        let copiedListID = ((lists + archivedLists).map(\.id).max() ?? -1) + 1 /* New list identity */
        var nextCardID   = ((lists + archivedLists).flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1 /* Next unique card identity */

        let copiedCards = source.cards.map { card /* Source card being copied */ in
        
            let copy = KanbanCard( /* New card retaining source content */
                id:                   nextCardID,
                word:                 card.word,
                listTitle:            copiedTitle,
                isDivider:            card.isSectionDivider,
                isTitleChecked:       card.isTitleChecked,
                startDate:            card.startDate,
                dueDate:              card.dueDate,
                checklists:           card.checklists,
                comments:             card.comments,
                members:              card.members,
                labelIDs:             card.labelIDs,
                attachments:          card.attachments,
                coverAttachmentID:    card.coverAttachmentID,
                dismissedActivityIDs: card.dismissedActivityIDs,
                descriptionOverride:  card.descriptionOverride,
                subtitleOverride:     card.subtitleOverride
            )

            nextCardID += 1
            
            return copy
        }

        lists.insert(KanbanList(id: copiedListID, title: copiedTitle, cards: copiedCards), at: sourceIndex + 1)
    }


    ///
    /// @fcn        ContentView.moveList(with:by:)
    /// @brief      Move a list relative to its current board position
    /// @details    Removes the matching list and reinserts it at the index specified by the offset
    ///
    /// @param[in]  listID  Stable identifier of the list to move
    /// @param[in]  offset  Number of positions to move; negative moves earlier and positive moves
    ///             later
    ///
    /// @return     (Void) reorders the board when the destination index is valid
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The list occupies its destination index, or the board is unchanged for an
    ///             invalid destination
    ///
    private func moveList(with listID: Int, by offset: Int) {

        guard let sourceIndex = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        } /* Source list position */

        let destinationIndex = sourceIndex + offset /* Requested destination position */

        guard lists.indices.contains(destinationIndex) else {

            return
        }

        BoardListReordering.move(listID, to: destinationIndex, in: &lists)
    }


    ///
    /// @fcn        ContentView.updateListDrag(_:value:)
    /// @brief      Track a held list and reorder it when the pointer crosses a neighbor
    /// @details    Claims the first list, captures its grab offset on the first drag value, and
    ///             moves at most one neighboring position per update using viewport centers
    ///
    /// @param[in]  listID  List whose title-area gesture is reporting
    /// @param[in]  value   Optional drag geometry; nil can claim the hold without moving
    ///
    /// @return     (Void) updates drag state and potentially active-list order
    ///
    /// @post       Reports for another held list are ignored; reorder animation honors Reduce
    ///             Motion
    ///
    private func updateListDrag(_ listID: Int, value: DragGesture.Value?) {

        guard draggedCardID == nil else {

            return
        }

        if draggedListID == nil {

            draggedListID = listID
        }

        guard draggedListID == listID, let value else {

            return
        }

        if listDragLocation == nil {

            listDragGrabOffset = value.startLocation.x - (listCenters[listID] ?? value.startLocation.x)
        }

        listDragLocation = value.location.x

        guard let source = lists.firstIndex(where: {

            $0.id == listID
        }),
              let center = listCenters[listID] else { return }
        let direction = value.location.x > center ? 1 : -1
        let destination = source + direction

        guard lists.indices.contains(destination),
              let targetCenter = listCenters[lists[destination].id],
              direction > 0 ? value.location.x > targetCenter : value.location.x < targetCenter else { return }
        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2)) {
            _ = BoardListReordering.move(listID, to: destination, in: &lists)
        }
    }


    ///
    /// @fcn        ContentView.endListDrag(_:)
    /// @brief      Release drag state for the currently held list
    /// @details    Clears the held identity, pointer location, and grab offset only for the
    ///             matching list
    ///
    /// @param[in]  listID  Identity ending its hold/drag interaction
    ///
    /// @return     (Void) resets transient drag tracking
    ///
    /// @post       List order stays as last updated; clearing the identity cancels edge-scrolling
    ///             work
    ///
    private func endListDrag(_ listID: Int) {

        guard draggedListID == listID else {

            return
        }

        draggedListID = nil
        listDragLocation = nil
        listDragGrabOffset = 0
    }


    ///
    /// @fcn        ContentView.listDragOffset(for:)
    /// @brief      Calculate the visual translation of the held list
    /// @details    Subtracts the current layout center and captured grab offset from pointer
    ///             position
    ///
    /// @param[in]  listID  List whose horizontal translation is requested
    ///
    /// @return     (CGFloat) translation in points, or zero without matching drag/geometry state
    ///
    /// @post       Layout and drag state remain unchanged
    ///
    private func listDragOffset(for listID: Int) -> CGFloat {

        guard draggedListID == listID, let location = listDragLocation,
              let center = listCenters[listID] else { return 0 }
        return location - center - listDragGrabOffset
    }


    ///
    /// @fcn        ContentView.sortList(with:ascending:)
    /// @brief      Sort a list's cards by their titles
    /// @details    Uses localized standard title comparison within divider-separated sections;
    ///             divider positions and section membership are preserved
    ///
    /// @param[in]  listID     Stable identifier of the list to sort
    /// @param[in]  ascending  Whether to sort from A to Z; false sorts from Z to A
    ///
    /// @return     (Void) replaces the card order in the matching board list
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       Each non-divider section is sorted in the requested direction; archive content
    ///             is unchanged
    ///
    private func sortList(with listID: Int, ascending: Bool) {

        guard let listIndex = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        } /* List being sorted */

        var updatedList = lists[listIndex] /* Mutable list copy */

        var sortedCards:    [KanbanCard] = [] /* Cards emitted in sorted order */
        var currentSection: [KanbanCard] = [] /* Cards before the next divider */

        // Iterate through each card in the list, grouping them by sections and sorting within each section
        for card in updatedList.cards { /* Preserve divider-separated sections */

            guard card.isSectionDivider else {

                currentSection.append(card)
                continue
            }

            // When encountering a section divider, sort the current section and append it to the sorted 
            // cards before adding the divider itself
            sortedCards.append(contentsOf: currentSection.sorted {
                let comparison = $0.word.localizedStandardCompare($1.word) /* Locale-aware title ordering */
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            })
            currentSection.removeAll()
            sortedCards.append(card)
        }

        sortedCards.append(contentsOf: currentSection.sorted {

            let comparison = $0.word.localizedStandardCompare($1.word) /* Locale-aware title ordering */

            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        })

        updatedList.cards = sortedCards
        
        lists[listIndex] = updatedList
    }


    ///
    /// @fcn        ContentView.archiveCompletedCards(in:)
    /// @brief      Move completed cards into the list's saved archive
    /// @details    Retains complete card records and attachments for later restoration
    ///
    /// @param[in]  listID  Stable identifier of the list to update
    ///
    /// @return     (Void) updates the matching list in the board state
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       Completed non-divider cards leave the active list; section dividers stay in
    ///             place
    ///
    private func archiveCompletedCards(in listID: Int) {

        guard let listIndex = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        } /* List being archived */

        lists[listIndex].archiveCompletedCards()
    }


    ///
    /// @fcn        ContentView.restoreArchivedCard(in:cardID:)
    /// @brief      Return a saved card to the end of its active list
    /// @details    Delegates to the model archive helper, preserving identity, completion, and
    ///             content
    ///
    /// @param[in]  listID  Active list containing the card archive
    /// @param[in]  cardID  Archived card identity to restore
    ///
    /// @return     (Void) transfers the archived record into active cards when found
    ///
    /// @post       Missing identities do nothing; no attachment files are pruned
    ///
    private func restoreArchivedCard(in listID: Int, cardID: Int) {

        guard let listIndex = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        }
        lists[listIndex].restoreArchivedCard(id: cardID)
    }


    ///
    /// @fcn        ContentView.archiveCard(_:)
    /// @brief      Move one active task card into its containing list's archive
    /// @details    Finds the first containing active list and delegates record retention to the
    ///             model helper
    ///
    /// @param[in]  cardID  Board-unique active card identity
    ///
    /// @return     (Void) archives a matching non-divider card
    ///
    /// @post       Missing IDs and divider cards do nothing; card state and attachment references
    ///             survive
    ///
    private func archiveCard(_ cardID: Int) {

        guard let listIndex = lists.firstIndex(where: {

            $0.cards.contains(where: { $0.id == cardID })
        }) else {
            return
        }
        lists[listIndex].archiveCard(id: cardID)
    }

    ///
    /// @fcn        ContentView.archiveList(with:)
    /// @brief      Remove a list from the active board
    /// @details    Retains the list and all its cards for restoration through Board options
    ///
    /// @param[in]  listID  Stable identifier of the list to remove
    ///
    /// @return     (Void) updates the board's in-memory list collection
    ///
    /// @pre        listID identifies a list in the current board
    /// @post       The list and its cards no longer appear on the active board
    ///
    private func archiveList(with listID: Int) {

        guard let index = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        }

        var archived = lists[index]

        archived.isArchived = true
        archivedLists.append(archived)
        lists.removeAll { $0.id == listID }
    }


    ///
    /// @fcn        ContentView.restoreArchivedList(_:)
    /// @brief      Append an archived list to the active Board
    /// @details    Clears the list archive flag, appends its complete record, and removes its
    ///             archived entry
    ///
    /// @param[in]  listID  Archived list identity to restore
    ///
    /// @return     (Void) transfers a matching list between partitions
    ///
    /// @pre        Active/archive bindings are writable partitions of the same Board
    /// @post       Nested card archives and all identities survive; an absent ID leaves state
    ///             unchanged
    ///
    private func restoreArchivedList(_ listID: Int) {

        guard let index = archivedLists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        }

        var restored = archivedLists[index]

        restored.isArchived = false
        lists.append(restored)
        archivedLists.removeAll { $0.id == listID }
    }


    ///
    /// @fcn        ContentView.toggleCardTitle(in:cardID:)
    /// @brief      Toggle the selected state for one board card title checkbox
    /// @details    Finds the matching card within the selected list and flips its persisted checked
    ///             state so the root board view and detail view stay in sync
    ///
    /// @param[in]  listIndex  Zero-based index of the list containing the card
    /// @param[in]  cardID     Stable identifier of the card whose title checkbox is toggled
    ///
    /// @return     (Void) updates the local board state in place
    ///
    /// @pre        listIndex must reference a valid list in the board state
    /// @post       The selected card's checked state is inverted and the board re-renders
    ///
    private func toggleCardTitle(in listIndex: Int, cardID: Int) {

        guard lists.indices.contains(listIndex) else {

            return
        }

        var updatedList     = lists[listIndex] /* Mutable list copy */

        guard let cardIndex = updatedList.cards.firstIndex(where: {

            $0.id == cardID
        }) else {
            return
        } /* Matching card position */

        var updatedCard     = updatedList.cards[cardIndex] /* Mutable card copy */

        updatedCard.isTitleChecked.toggle()

        updatedList.cards[cardIndex] = updatedCard
        lists[listIndex]             = updatedList
    }


    ///
    /// @fcn        ContentView.updateCard(_:)
    /// @brief      Replace an existing card with the latest edited version
    /// @details    Scans the current board data for the matching card identifier and stores the
    ///             latest value so navigation changes persist across list and detail views
    ///
    /// @param[in]  updatedCard  Card instance containing the latest state to save
    ///
    /// @return     (Void) updates the board's in-memory card collection
    ///
    /// @pre        updatedCard must contain a valid id that exists within the board state
    /// @post       The matching card in the list state reflects the updated values
    ///
    private func updateCard(_ updatedCard: KanbanCard) {

        for listIndex in lists.indices {

            var updatedList = lists[listIndex] /* Mutable list being searched */

            guard let cardIndex = updatedList.cards.firstIndex(where: {

                $0.id == updatedCard.id
            }) else { /* Matching card position */
                continue
            }

            updatedList.cards[cardIndex] = updatedCard
            lists[listIndex]             = updatedList

            pruneUnreferencedAttachments()

            return
        }
    }


    ///
    /// @fcn        ContentView.pruneUnreferencedAttachments()
    /// @brief      Remove stored photo files that are no longer assigned to any card
    /// @details    Collects filenames from active/archived lists and cards plus the caller's
    ///             retained snapshots, then asks the attachment store to remove files outside that
    ///             combined set
    ///
    /// @return     (Void) cleans unreferenced image files from the app's attachment directory
    ///
    /// @pre        lists reflects the current board state after a card or list mutation
    /// @post       Files referenced by cards remain available; unreferenced files are removed when
    ///             possible
    /// @note       File-system cleanup failures are ignored by CardAttachmentStore
    ///
    private func pruneUnreferencedAttachments() {
        
        let referencedFileNames = Set( /* Attachment files retained by current Board cards */
            (lists + archivedLists + retainedAttachmentLists())
                .flatMap(\.allCards)
                .flatMap { $0.attachments ?? [] }
                .compactMap(\.fileName)
        )

        CardAttachmentStore.removeUnreferencedFiles(keeping: referencedFileNames)
    }


    ///
    /// @fcn        ContentView.moveCard(_:toListID:)
    /// @brief      Move an existing card into a different board list
    /// @details    Finds the card by its stable identifier, removes it from its current list,
    ///             updates its list title, and appends it to the destination list while retaining
    ///             its state
    ///
    /// @param[in]  cardID             Stable identifier of the card being moved
    /// @param[in]  destinationListID  Stable identifier of the list receiving the card
    ///
    /// @return     (Void) updates the source and destination lists in the board state
    ///
    /// @pre        cardID exists in a board list and destinationListID identifies another list
    /// @post       The card is removed from its source list and appears at the end of the
    ///             destination list with its existing card data preserved
    /// @note       The operation leaves board state unchanged if the card or destination is
    ///             missing, or if the destination is the card's current list
    ///
    private func moveCard(_ cardID: Int, toListID destinationListID: Int) {

        guard !lists.contains(where: {

            $0.id == destinationListID && $0.cards.contains(where: { $0.id == cardID })
        }) else {
            return
        }

        do {

            try BoardCardMovement.move(cardID, to: destinationListID, in: &lists)
        } catch {
            DatabaseActivity.shared.report("Could not move this card: \(error.localizedDescription) Its content has been retained.")
        }
    }

    private var cardDropTarget: BoardCardDropTarget? {
        guard let location = cardDragLocation, let draggedCardID else {

            return nil
        }

        return BoardCardMovement.target(for: draggedCardID, at: location, viewport: cardDragViewportFrame,
                                        lists: lists, listFrames: listFrames, cardFrames: cardFrames)
    }

    ///
    /// @fcn        ContentView.updateCardDrag(_:location:)
    /// @brief      Update the pointer location for the currently claimed card session
    /// @details    Ignores callbacks whose card identity does not match the active drag; hovering
    ///             does not modify Board records.
    ///
    /// @param[in]  cardID    Board-local identity of the card being dragged or moved
    /// @param[in]  location  Current or final pointer position in global Board geometry
    ///
    /// @return     (Void) updates only matching drag-location state
    ///
    private func updateCardDrag(_ cardID: Int, location: CGPoint) {

        guard draggedCardID == cardID else {

            return
        }

        cardDragLocation = location
    }

    ///
    /// @fcn        ContentView.beginCardDrag(_:location:)
    /// @brief      Claim an idle Board for a native card drag
    /// @details    Records the card identity and starting location only when neither a list drag
    ///             nor another card drag is active.
    ///
    /// @param[in]  cardID    Board-local identity of the card being dragged or moved
    /// @param[in]  location  Current or final pointer position in global Board geometry
    ///
    /// @return     (Void) starts drag presentation without moving card records
    ///
    private func beginCardDrag(_ cardID: Int, location: CGPoint) {

        guard draggedListID == nil, draggedCardID == nil else {

            return
        }

        draggedCardID = cardID
        cardDragLocation = location
    }

    ///
    /// @fcn        ContentView.endCardDrag(_:commit:location:)
    /// @brief      Finish a matching card session and optionally commit its final drop
    /// @details    Validates the release point against measured Board geometry and moves the
    ///             canonical card. Clears matching session state on exit; movement errors retain
    ///             content and reach the database-activity banner.
    ///
    /// @param[in]  cardID    Board-local identity of the card being dragged or moved
    /// @param[in]  commit    Whether to attempt movement after validating the destination
    /// @param[in]  location  Current or final pointer position in global Board geometry
    ///
    /// @return     (Bool) whether canonical card movement changed the Board
    ///
    /// @post       Matching drag state is cleared even when validation fails or movement reports an
    ///             error
    ///
    @discardableResult
    private func endCardDrag(_ cardID: Int, commit: Bool, location: CGPoint? = nil) -> Bool {

        guard draggedCardID == cardID else {

            return false
        }

        if let location {

            cardDragLocation = location
        }

        defer {

            draggedCardID = nil
            cardDragLocation = nil
        }

        guard commit, let target = location.map({

            BoardCardMovement.target(for: cardID, at: $0, viewport: cardDragViewportFrame,
                                     lists: lists, listFrames: listFrames, cardFrames: cardFrames)
        }) ?? cardDropTarget else { return false }
        do {

            return try BoardCardMovement.move(cardID, to: target.listID, before: target.beforeCardID, in: &lists)
        } catch {
            DatabaseActivity.shared.report("Could not move this card: \(error.localizedDescription) Its content has been retained.")

            return false
        }
    }
    

    ///
    /// @fcn        ContentView.body
    /// @brief      Compose the Board scene, horizontal list viewport, and detail navigation
    /// @details    Wires list/card actions, geometry-based visible-list reporting, pending targets,
    ///             archive/calendar sheets, and title-hold reordering. A held list disables normal
    ///             scrolling and moves/scrolls at viewport edges every 550 milliseconds
    ///
    /// @return     (some View) Board navigation stack and shared list panels
    /// @pre        Caller supplies consistent active/archive bindings and Board-unique IDs
    /// @post       Active-list changes invoke onListsChanged; label changes save locally.
    ///             Drag release/disappearance cancels edge work; unexpected movement errors reach the banner
    /// @note       Reduce Motion suppresses drag lift scaling and reorder/edge-scroll animations
    ///
    var body: some View { /* Board scene and list collection */

        NavigationStack(path: $navigationPath) {
            
            GeometryReader { _ in

                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.18, blue: 0.25), Color(red: 0.22, green: 0.34, blue: 0.38)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {

                        BoardHeader(
                            settings:         $displaySettings,
                            presentation:     $presentation,
                            activeMembers:    activeMembers,
                            memberColors:     memberColors,
                            onRenameMember:   renameMember,
                            onDeleteMember:   removeMember,
                            onSetMemberColor: setMemberColor,
                            onOpenCalendar:   { showsCalendar = true },
                            title: boardTitle,
                            subtitle: boardSubtitle,
                            allowsAddingLists: allowsAddingLists || lists.isEmpty,
                            onClose: onClose,
                            onViewArchivedLists: { showsArchivedLists = true },
                            onArchiveBoard: onArchiveBoard,
                            onDeleteBoard: onDeleteBoard,
                            deleteBoardTitle: deleteBoardTitle,
                            onAddList:        addList
                        )

                        GeometryReader { listArea in
                        ScrollViewReader { listProxy in

                            ScrollView(.horizontal, showsIndicators: false) {

                                HStack(alignment: .top, spacing: 12) {

                                    ForEach(Array(lists.enumerated()), id: \.element.id) { listIndex, list in

                                        ZStack {
                                        KanbanListView(
                                            list:               list,
                                            availableListHeight: listArea.size.height,
                                            displaySettings:    displaySettings,
                                            presentation:       presentation,
                                            labelLibrary:       labelLibrary,
                                            toggleCardTitle:    { cardID in toggleCardTitle(in: listIndex, cardID: cardID)
                                            },
                                            canMoveEarlier:     listIndex > 0,
                                            canMoveLater:       listIndex < lists.count - 1,
                                            onAddCard:          { title, description in addCard(to: list.id, title: title, description: description)
                                            },
                                            onCopyList:         { copyList(with: list.id) },
                                            onMoveList:         { offset in moveList(with: list.id, by: offset) },
                                            onSortList:         { ascending in sortList(with: list.id, ascending: ascending) },
                                            onArchiveCompleted: { archiveCompletedCards(in: list.id) },
                                            archivedCards: Binding(
                                                get: { lists.first(where: { $0.id == list.id })?.archivedCards ?? [] },
                                                set: { archivedCards in
                                                    guard let index = lists.firstIndex(where: {

                                                        $0.id == list.id
                                                    }) else {
                                                        return
                                                    }
                                                    lists[index].archivedCards = archivedCards
                                                }
                                            ),
                                            onRestoreArchivedCard: { cardID in
                                                restoreArchivedCard(in: list.id, cardID: cardID)
                                            },
                                            onDeleteArchivedCard: { cardID in deleteCard(cardID) },
                                            onArchiveList:      { archiveList(with: list.id) },
                                            onDeleteList:       { deleteList(list.id) },
                                            onDeleteCard:       { cardID in deleteCard(cardID) },
                                            onArchiveCard:      archiveCard,
                                            onUpdateCard:       updateCard,
                                            onMoveCard:         { cardID, destinationIndex in moveCard(in: list.id, cardID: cardID, toIndex: destinationIndex)
                                            },
                                            onListDragChanged: { value in updateListDrag(list.id, value: value) },
                                            onListDragEnded: { endListDrag(list.id) },
                                            draggedCardID: draggedCardID,
                                            dropBeforeCardID: cardDropTarget?.listID == list.id ? cardDropTarget?.beforeCardID : nil,
                                            isCardDropTarget: cardDropTarget?.listID == list.id,
                                            onCardDragBegan: beginCardDrag,
                                            onCardDragChanged: updateCardDrag,
                                            onCardDragEnded: { cardID, commit, point in
                                                endCardDrag(cardID, commit: commit, location: point)
                                            },
                                            cardDragToken: cardDragToken,
                                            onCardDrop: { point in
                                                guard let cardID = draggedCardID else {

                                                    return false
                                                }
                                                return endCardDrag(cardID, commit: true, location: point)
                                            },
                                            cardMoveDestinations: lists.filter { $0.id != list.id },
                                            onMoveCardToList: { cardID, listID in moveCard(cardID, toListID: listID) }
                                        )
                                        .frame(
                                            width: presentation.columnWidth(viewportWidth: listArea.size.width, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
                                        )
                                        .scaleEffect(draggedListID == list.id && !reducesMotion ? 1.025 : 1)
                                        .shadow(color: .black.opacity(draggedListID == list.id ? 0.4 : 0), radius: 18, y: 8)
                                        .offset(x: listDragOffset(for: list.id))
                                        }

                                        .frame(width: presentation.columnWidth(viewportWidth: listArea.size.width, accessibilitySize: dynamicTypeSize.isAccessibilitySize))
                                        .background {
                                            GeometryReader { geometry in
                                                Color.clear.preference(
                                                    key: BoardListCenterPreferenceKey.self,
                                                    value: [list.id: geometry.frame(in: .named("WeekListsViewport")).midX]
                                                )
                                                .preference(key: BoardListFramePreferenceKey.self,
                                                                    value: [list.id: geometry.frame(in: .global)])
                                            }
                                        }

                                        .id(list.id)
                                        .zIndex(draggedListID == list.id ? 1 : 0)
                                    }
                                }

                                .frame(maxHeight: .infinity, alignment: .top)
                                .scrollTargetLayout()
                                .padding(.horizontal, 14)
                            }

                            .scrollTargetBehavior(.viewAligned)
                            .scrollPosition(id: $visibleListID, anchor: .leading)
                            .scrollDisabled(draggedListID != nil)
                            .coordinateSpace(name: "WeekListsViewport")
                            .onPreferenceChange(BoardListCenterPreferenceKey.self) { centers in
                                listCenters = centers
                            }

                            .onPreferenceChange(BoardListFramePreferenceKey.self) { listFrames = $0 }
                            .onPreferenceChange(BoardCardFramePreferenceKey.self) { cardFrames = $0 }
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.onAppear {
                                        cardDragViewportFrame = geometry.frame(in: .global)
                                    }

                                    .onChange(of: geometry.frame(in: .global)) { _, frame in
                                        cardDragViewportFrame = frame
                                    }
                                }
                            }

                            .onChange(of: visibleListID) { _, listID in
                                guard draggedListID == nil, let listID,
                                      lists.contains(where: { $0.id == listID }),
                                      listID != lastReportedVisibleListID else { return }
                                lastReportedVisibleListID = listID
                                onListViewed(listID)
                            }

                            .onChange(of: presentation) { _, _ in
                                if let listID = draggedListID {

                                    endListDrag(listID)
                                }

                                if let cardID = draggedCardID {

                                    endCardDrag(cardID, commit: false)
                                }
                            }

                            .onChange(of: scenePhase) { _, phase in
                                if phase != .active, let cardID = draggedCardID {

                                    endCardDrag(cardID, commit: false)
                                }
                            }

                            .onChange(of: listArea.size) { _, _ in
                                if let listID = draggedListID {

                                    endListDrag(listID)
                                }

                                if let cardID = draggedCardID {

                                    endCardDrag(cardID, commit: false)
                                }
                            }

                            .onChange(of: boardTargetListID) { _, targetListID in
                                guard targetListID != nil else {

                                    return
                                }

                                withAnimation(.easeInOut(duration: 0.25)) {
                                    openPendingBoardTarget(using: listProxy)
                                }
                            }

                            .onChange(of: boardTargetCardID) { _, cardID in
                                guard cardID != nil else {

                                    return
                                }

                                withAnimation(.easeInOut(duration: 0.25)) {
                                    openPendingBoardTarget(using: listProxy)
                                }
                            }
                            .onAppear {
                                if visibleListID == nil {

                                    visibleListID = lists.first?.id
                                }

                                openPendingBoardTarget(using: listProxy)
                            }

                            .task(id: draggedListID) {
                                guard let listID = draggedListID else {

                                    return
                                }

                                do {

                                    while !Task.isCancelled {

                                        try await Task.sleep(for: .milliseconds(550))

                                        guard draggedListID == listID, let location = listDragLocation,
                                              let source = lists.firstIndex(where: { $0.id == listID }) else { continue }
                                        let direction = BoardListReordering.edgeDirection(at: location, viewportWidth: listArea.size.width)
                                        let destination = source + direction

                                        guard direction != 0, lists.indices.contains(destination) else {

                                            continue
                                        }

                                        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2)) {
                                            _ = BoardListReordering.move(listID, to: destination, in: &lists)
                                        }

                                        await Task.yield()

                                        guard !Task.isCancelled, draggedListID == listID else {

                                            return
                                        }

                                        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2)) {
                                            listProxy.scrollTo(listID, anchor: .center)
                                        }
                                    }
                                } catch is CancellationError {
                                    // Releasing the header cancels edge scrolling.
                                } catch {
                                    DatabaseActivity.shared.report("Could not move the list: \(error.localizedDescription)")
                                }
                            }

                            .task(id: draggedCardID) {
                                guard let cardID = draggedCardID else {

                                    return
                                }

                                do {

                                    while !Task.isCancelled {

                                        try await Task.sleep(for: .milliseconds(550))

                                        guard draggedCardID == cardID, let location = cardDragLocation else {

                                            continue
                                        }

                                        let direction = BoardListReordering.edgeDirection(
                                            at: location.x - cardDragViewportFrame.minX,
                                            viewportWidth: cardDragViewportFrame.width
                                        )
                                        guard direction != 0,
                                              let current = lists.firstIndex(where: { $0.id == visibleListID }),

                                              lists.indices.contains(current + direction) else { continue }
                                        let nextID = lists[current + direction].id

                                        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.2)) {
                                            listProxy.scrollTo(nextID, anchor: .leading)
                                            visibleListID = nextID
                                        }
                                    }
                                } catch is CancellationError {
                                    // Release or cancellation stops edge scrolling without moving a card.
                                } catch {
                                    DatabaseActivity.shared.report("Could not scroll while moving the card: \(error.localizedDescription)")
                                }
                            }
                            .onDisappear {
                                if let listID = draggedListID {

                                    endListDrag(listID)
                                }

                                if let cardID = draggedCardID {

                                    endCardDrag(cardID, commit: false)
                                }
                            }
                        }
                        }

                        .padding(.bottom, 32)
                    }
                }
            }

            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: boardRootRequest) { _, _ in
                navigationPath = NavigationPath()
            }
            .navigationDestination(for: KanbanCard.self) { card in
                CardDetailView(
                    card:           card,
                    labelLibrary:   $labelLibrary,
                    availableLists: lists.filter { list in
                        !list.cards.contains(where: { $0.id == card.id })
                    },
                    memberColors:    memberColors,
                    currentUserName: currentUserName,
                    savedCardIDs:    $savedCardIDs,
                    onTitleToggle:   { updatedCard in
                        updateCard(updatedCard)
                    },
                    onMoveToList:    { destinationListID in
                        moveCard(card.id, toListID: destinationListID)
                    },
                    onArchive: {
                        archiveCard(card.id)
                    },
                    onDelete: {
                        deleteCard(card.id)
                    }
                )
            }

            .sheet(isPresented: $showsCalendar) {
                TodayCalendarView(
                    lists: lists,
                    onArchiveCard: archiveCard,
                    onDeleteCard: { deleteCard($0) }
                ) { listID in
                    showsCalendar = false
                    boardTargetCardID = nil
                    boardTargetListID = listID
                }

                .presentationDetents([.large])
            }

            .sheet(isPresented: $showsArchivedLists) {
                ArchivedListsView(
                    lists: $archivedLists, onRestore: restoreArchivedList, onDelete: deleteList,
                    onDeleteCard: { _, cardID in deleteCard(cardID) }
                )
                    .databaseActivityOverlay()
            }

            .onChange(of: lists) { _, updatedLists in
                onListsChanged(updatedLists)
            }

            .onChange(of: labelLibrary) { _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }
        }
    }
}


// -------------------------------------- MARK: - Board Header ---------------------------------- //

///
/// Displays the board title and board-level actions
///
/// @section    Purpose
///     Establish the visual identity of the board and expose board-level controls
///
struct BoardHeader: View {

    @Binding var settings: BoardDisplaySettings      /* Board display settings                              */
    /// Shared Standard/Overview selection displayed in the Board options menu.
    @Binding var presentation: BoardPresentation
    let activeMembers:     [String]                  /* Unique users assigned to active cards               */
    let memberColors:      [String: Color]           /* Icon colors keyed by normalized member name         */
    let onRenameMember:    (String, String) -> Void  /* Rename a member across all card assignments         */
    let onDeleteMember:    (String) -> Void          /* Remove a member from all card assignments           */
    let onSetMemberColor:  (String, Color) -> Void   /* Update a member's shared icon color                 */
    /// Opens the calendar view for the current board.
    let onOpenCalendar: () -> Void
    /// Board name shown in the header.
    let title: String
    /// Supporting board description shown in the header.
    let subtitle: String
    /// Whether to expose list creation in the header.
    let allowsAddingLists: Bool
    /// Optional action returning to the owning collection.
    let onClose: (() -> Void)?
    /// Opens the archived-list browser.
    let onViewArchivedLists: () -> Void
    /// Optional callback that archives the board after confirmation.
    let onArchiveBoard: (() -> Void)?
    let onDeleteBoard: (() -> Void)? /* Confirmed parent-owned Board removal */
    let deleteBoardTitle: String /* Week content clearing or personal Board deletion label */

    let onAddList: () -> Void                        /* Callback for adding a new list                      */

    @State private var showingSettings = false       /* Controls the visibility of the board settings sheet */
    /// Controls confirmation before archiving the complete board.
    @State private var confirmsArchiveBoard = false
    @State private var confirmsDeleteBoard = false /* Permanent Board deletion confirmation */


    ///
    /// @fcn        BoardHeader.body
    /// @brief      Present Board identity and global actions
    /// @details    Composes optional back/list-creation controls, calendar access, settings,
    ///             archived-list browsing, and an optional confirmed full-board archive action
    ///
    /// @return     (some View) Board title/action row and settings presentation
    /// @post       User actions invoke supplied callbacks; archive is requested only after confirmation.
    ///             Display settings change through the shared binding, not a separate persisted draft
    ///
    var body: some View { /* Board header and global actions */

        HStack {

            if let onClose {

                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 44)
                }

                .foregroundStyle(.white)
                .accessibilityLabel("Back to Library")
            }

            VStack(alignment: .leading, spacing: 2) {

                Text(title)
                    .font(onClose == nil ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            Button(action: onOpenCalendar) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }

            .buttonStyle(.plain)
            .accessibilityLabel("Open Calendar")

            if allowsAddingLists {
            Menu {
                
                Button("Add blank list", systemImage: "rectangle.stack.badge.plus", action: onAddList)
                
            } label: {
                
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            .accessibilityLabel("Add list")
            }

            Menu {
                Picker("Board presentation", selection: $presentation) {
                    ForEach(BoardPresentation.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Button("Board Settings", systemImage: "gearshape") { showingSettings = true }
                Button("View Archived Lists", systemImage: "archivebox", action: onViewArchivedLists)

                if onArchiveBoard != nil {

                    Button("Archive Board", systemImage: "archivebox") { confirmsArchiveBoard = true }
                }

                if onDeleteBoard != nil {

                    Button(deleteBoardTitle, systemImage: "trash", role: .destructive) { confirmsDeleteBoard = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            .accessibilityLabel("Board options")
        }

        .padding(.horizontal, 18)
        .padding(.top,        12)
        .padding(.bottom,     10)
        .confirmationDialog("Archive this board?", isPresented: $confirmsArchiveBoard, titleVisibility: .visible) {
            Button("Archive Board") { onArchiveBoard?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All lists and cards will be kept on this device. Restore the board from Saved.")
        }

        .confirmationDialog(deleteBoardTitle + "?", isPresented: $confirmsDeleteBoard, titleVisibility: .visible) {
            Button(deleteBoardTitle, role: .destructive) { onDeleteBoard?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes all active and archived lists, cards, and bookmarks in this board. This cannot be undone. Other boards and retained archive copies are unchanged.")
        }

        .sheet(isPresented: $showingSettings) {
            
            BoardSettingsView(
                settings:         $settings,
                presentation:     $presentation,
                activeMembers:    activeMembers,
                memberColors:     memberColors,
                onRenameMember:   onRenameMember,
                onDeleteMember:   onDeleteMember,
                onSetMemberColor: onSetMemberColor
            )
        }

    }
}


///
/// Presents the archived lists belonging to one board
///
/// @section    Purpose
///     Let the user restore a list without deleting its retained cards
///
private struct ArchivedListsView: View {

    /// Archived lists available for restoration.
    @Binding var lists: [KanbanList]
    /// Requests restoration of a list by identity.
    let onRestore: (Int) -> Void
    let onDelete: (Int) -> Void /* Permanently remove a confirmed archived list */
    let onDeleteCard: (Int, Int) -> Void /* Remove a card within the archived list */
    @State private var deletingList: KanbanList? /* List awaiting permanent deletion */
    /// Dismiss action for the archive browser.
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        ArchivedListsView.body
    /// @brief      Browse lists archived from the current Board
    /// @details    Shows each list's active non-divider count and archived-card count,
    ///             with Restore controls and an empty-state explanation
    ///
    /// @return     (some View) archived-list navigation sheet with Close action
    /// @post       Restore delegates the list identity to onRestore; Close dismisses without changes
    ///
    var body: some View {
        NavigationStack {
            List {
                ForEach(lists) { list in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            NavigationLink(list.title) {
                                ArchivedListContentsView(
                                    lists: $lists, listID: list.id,
                                    onDeleteCard: { onDeleteCard(list.id, $0) },
                                    onDeleteList: { onDelete(list.id) }
                                )
                            }

                            .font(.headline)
                            Text("\(list.cards.filter { !$0.isSectionDivider }.count) cards · \(list.archivedCards.count) archived cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                        Button("Restore") { onRestore(list.id) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Restore \(list.title)")
                        Button("Delete", systemImage: "trash", role: .destructive) { deletingList = list }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Delete \(list.title)")
                    }
                }
            }
            .overlay {
                if lists.isEmpty {

                    ContentUnavailableView(
                        "No Archived Lists", systemImage: "archivebox",
                        description: Text("Lists archived from this board will appear here.")
                    )
                    .allowsHitTesting(false)
                }
            }

            .navigationTitle("Archived Lists")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete \(deletingList?.title ?? "list")?", isPresented: Binding(
                get: { deletingList != nil }, set: { if !$0 { deletingList = nil } }
            ), titleVisibility: .visible) {
                Button("Delete List", role: .destructive) {
                    if let deletingList {

                        onDelete(deletingList.id)
                    }

                    deletingList = nil
                }

                Button("Cancel", role: .cancel) { deletingList = nil }
            } message: {
                Text("This permanently deletes the list, all its active and archived cards, and their bookmarks. This cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

///
/// Makes the contents of an archived list inspectable without restoring it
///
/// @section    Purpose
///     Offer confirmed card deletion for both retained card partitions
///
private struct ArchivedListContentsView: View {
    @Binding var lists: [KanbanList] /* Canonical retained lists */
    let listID: Int /* Archived list identity */
    let onDeleteCard: (Int) -> Void /* Owner removes confirmed cards */
    let onDeleteList: () -> Void /* Owner removes the confirmed list */
    @State private var deletingCard: KanbanCard? /* Card awaiting permanent removal */
    @State private var confirmsDeleteList = false /* Complete retained list deletion */
    @Environment(\.dismiss) private var dismiss /* Close a deleted list */

    ///
    /// @fcn        ArchivedListContentsView.list
    /// @brief      Resolve the current archived list by identity
    /// @details    Failed saves keep the original rows visible rather than hiding snapshot records
    /// @return     (KanbanList?) current retained list
    ///
    private var list: KanbanList? { lists.first { $0.id == listID } }

    ///
    /// @fcn        ArchivedListContentsView.body
    /// @brief      Browse all retained cards and offer permanent removal
    /// @details    Leaves the list archived and does not create editable copies of its cards
    /// @return     (some View) retained-content list with confirmation
    ///
    var body: some View {
        List(list?.allCards ?? []) { card in
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink(card.word) {
                    ArchivedCardInspectionView(card: card) {
                        onDeleteCard(card.id)

                        return !(list?.allCards.contains { $0.id == card.id } ?? false)
                    }
                }

                .font(.headline)
                Text(card.funParagraph).foregroundStyle(.secondary)
                Button("Delete Card", systemImage: "trash", role: .destructive) { deletingCard = card }
            }
        }

        .navigationTitle(list?.title ?? "List unavailable")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Delete List", systemImage: "trash", role: .destructive) { confirmsDeleteList = true }
            }
        }

        .confirmationDialog("Delete this list?", isPresented: $confirmsDeleteList, titleVisibility: .visible) {
            Button("Delete List", role: .destructive) {
                onDeleteList()

                if list == nil {

                    dismiss()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently deletes this list, all retained cards, and bookmarks. This cannot be undone.")
        }

        .confirmationDialog("Delete \(deletingCard?.word ?? "card")?", isPresented: Binding(
            get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) {
                if let deletingCard {

                    onDeleteCard(deletingCard.id)
                }

                deletingCard = nil
            }

            Button("Cancel", role: .cancel) { deletingCard = nil }
        } message: {
            Text("Permanently deletes this card, its details, and its bookmark. This cannot be undone.")
        }
    }
}

///
/// Displays retained card content without synchronizing an editable snapshot
///
/// @section    Purpose
///     Allow inspection and confirmed permanent deletion before restoration
///
struct ArchivedCardInspectionView: View {
    let card: KanbanCard /* Retained card snapshot */
    let onDelete: () -> Bool /* Owner reports successful save-first removal */
    @State private var confirmsDelete = false /* Permanent deletion confirmation */
    @Environment(\.dismiss) private var dismiss /* Return after deletion */

    ///
    /// @fcn        ArchivedCardInspectionView.body
    /// @brief      Inspect retained description, checklist actions, comments, and media references
    /// @details    This read-only view never writes stale card state on disappearance
    /// @return     (some View) archived card detail with a confirmed Delete Card action
    ///
    var body: some View {
        List {
            if let cover = card.coverAttachment {

                Section("Card Cover") { CardCoverPreview(attachment: cover) }
            }

            Section("Description") { Text(card.funParagraph) }
            ForEach(card.checklists) { checklist in
                Section(checklist.title) {
                    ForEach(checklist.items) { item in
                        Label(item.title, systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    }
                }
            }

            Section("Attachments") {
                ForEach(card.attachments ?? []) { attachment in
                    if let url = attachment.url {

                        Link("Open link", destination: url)
                    } else if let url = CardAttachmentStore.fileURL(for: attachment) {
                        ShareLink(item: url) {
                            Label(attachment.fileName ?? "Attachment", systemImage: "paperclip")
                        }
                    }
                }
            }

            Section("Comments") {
                ForEach(card.comments) { comment in
                    VStack(alignment: .leading) {
                        Text(comment.author).font(.headline)
                        Text(comment.body)
                    }
                }
            }

            Button("Delete Card", systemImage: "trash", role: .destructive) { confirmsDelete = true }
        }

        .navigationTitle(card.word)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(card.word)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) { if onDelete() { dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently deletes this card, its details, and its bookmark. This cannot be undone. Other retained copies are unchanged.")
        }
    }
}

///
/// Provides consistent archive/delete context actions for canonical projection rows
///
/// @section    Purpose
///     Keep Search, labels, Calendar, and list pickers from owning duplicate content
///
struct ContentLifecycleActions: ViewModifier {
    let title: String /* Canonical content name used for confirmation */
    let kind: String /* Card or List */
    let onArchive: (() -> Void)? /* Optional retention action; dividers support deletion only */
    let onDelete: () -> Bool /* Owner reports saved removal of the confirmed record */
    @State private var confirmsDelete = false /* Permanent removal confirmation */
    @Environment(\.dismiss) private var dismiss /* Close snapshot projections after mutation */

    ///
    /// @fcn        ContentLifecycleActions.body(content:)
    /// @brief      Add accessible lifecycle actions and permanent deletion confirmation
    /// @details    Delegates mutations to the canonical owner and closes the snapshot projection
    ///
    /// @param[in]  content  Projection row to decorate
    ///
    /// @return     (some View) contextual archive/delete actions
    ///
    func body(content: Content) -> some View {

        content
            .contextMenu {
                if let onArchive {

                    Button("Archive \(kind)", systemImage: "archivebox") { onArchive(); dismiss() }
                }

                Button("Delete \(kind)", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            }
            .accessibilityActions {
                if let onArchive {

                    Button("Archive \(kind)") { onArchive(); dismiss() }
                }

                Button("Delete \(kind)") { confirmsDelete = true }
            }

            .confirmationDialog("Delete \(title)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete \(kind)", role: .destructive) { if onDelete() { dismiss() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently deletes this \(kind.lowercased()) and its contents and bookmarks. This cannot be undone. Other retained copies are unchanged.")
            }
    }
}


///
/// Presents controls for Board card metadata and layout preferences
///
/// @section    Purpose
///     Let the user control which metadata badges appear on board cards
///
/// @note   Settings are bound to ContentView and take effect immediately
///
private struct BoardSettingsView: View {

    @AppStorage("Plenact.CardCovers.enabled") private var showsCardCovers = true /* Device-only visibility */
    @Binding var settings: BoardDisplaySettings             /* Bound to the board's display preferences        */
    /// Shared presentation choice updated immediately from Board settings.
    @Binding var presentation: BoardPresentation

    @Environment(\.dismiss) private var dismiss             /* Dismiss action for the settings sheet           */

    let activeMembers:     [String]                         /* Active assigned users in board order            */        
    let memberColors:      [String: Color]                  /* Member icon colors keyed by normalized name     */
    let onRenameMember:    (String, String)   -> Void       /* Rename a member across all assigned cards       */
    let onDeleteMember:    (String)           -> Void       /* Remove a member from all assigned cards         */
    let onSetMemberColor:  (String, Color)    -> Void       /* Update a member's shared icon color             */

    @State private var memberNameDraft  = ""                /* Draft name for renaming a member                */
    @State private var isRenamingMember = false             /* Flag indicating if member rename in progress    */

    @State private var editingMember: String?               /* Currently edited member name                    */
    @State private var memberToDelete: String?              /* Member slated for deletion                      */
    @State private var selectedMemberColor: MemberColorTarget?  /* Target member for color selection           */


    ///
    /// @fcn        BoardSettingsView.trimmedMemberNameDraft
    /// @brief      Normalize the proposed member name for validation
    /// @details    Removes surrounding whitespace/newlines without changing the editable draft
    ///
    /// @return     (String) trimmed name, which may be empty
    /// @post       Member assignments and draft text remain unchanged
    ///
    private var trimmedMemberNameDraft: String { /* Normalized member rename input */
        memberNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    ///
    /// @fcn        BoardSettingsView.body
    /// @brief      Build the board settings form
    /// @details    Presents immediate badge-visibility toggles and member color/rename/removal controls.
    ///             Rename validates a nonblank name; removal requires confirmation and preserves comments
    ///
    /// @return     (some View) settings sheet content with a Done action
    ///
    /// @pre        settings is bound to the board's display preferences
    /// @post       Toggle changes update the binding; member actions invoke parent callbacks.
    ///             Done dismisses without reverting already applied settings
    ///
    var body: some View { /* Board settings and member management form */

        NavigationStack {

            Form {

                Section {
                    Picker("Board presentation", selection: $presentation) {
                        ForEach(BoardPresentation.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    .pickerStyle(.segmented)
                } header: {
                    Text("Presentation")
                } footer: {
                    Text("Standard shows supporting summaries. Overview shows narrower lists and concise cards. This preference applies to Week and personal boards on this device; it does not change your content.")
                }

                Section("Card badges") {
                    Toggle("Checklist progress", isOn: $settings.showChecklistProgress)
                    Toggle("Comment counts",     isOn: $settings.showCommentCounts)
                    Toggle("Due-date badges",    isOn: $settings.showDueDateBadges)
                }
                Section {
                    Toggle("Show card covers", isOn: $showsCardCovers)
                } footer: {
                    Text("Applies to Board and Today card rows on this device. Turning this off keeps every cover selection and attachment.")
                }

                Section("Members") {

                    if activeMembers.isEmpty {

                        Text("No active members")
                            .foregroundStyle(.secondary)

                    } else {

                        ForEach(activeMembers, id: \.self) { member in

                            HStack(spacing: 12) {

                                let memberColor = memberColors[member.lowercased()] ?? .accentColor     /* Fallback to accent color if no custom color is set */

                                Button {
                                    selectedMemberColor = MemberColorTarget(member: member, color: memberColor)

                                } label: {

                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(memberColor)
                                        .frame(width: 36, height: 36)
                                        .contentShape(Rectangle())

                                }

                                .buttonStyle(.plain)
                                .accessibilityLabel("Change icon color for \(member)")

                                Text(member)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    editingMember    = member
                                    memberNameDraft  = member
                                    isRenamingMember = true

                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }

                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit \(member)")
                            }

                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                                Button(role: .destructive) {
                                    memberToDelete = member

                                } label: {
                                    Label("Remove", systemImage: "person.crop.circle.badge.minus")
                                }
                            }
                        }
                    }
                }
            }

            .navigationTitle("Board Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }

            .alert("Edit member", isPresented: $isRenamingMember) {

                TextField("Name or email", text: $memberNameDraft)
                    .textInputAutocapitalization(.never)

                Button("Cancel", role: .cancel) {}

                Button("Save") {
                    guard let editingMember else {

                        return
                    } /* Member currently being renamed */

                    onRenameMember(editingMember, trimmedMemberNameDraft)
                }

                .disabled(trimmedMemberNameDraft.isEmpty)
            } message: {

                Text("This updates the member name on every assigned card.")
            }

            .confirmationDialog(

                "Remove \(memberToDelete ?? "member") from the board?",

                isPresented: Binding(
                    get: { memberToDelete != nil },
                    set: { if !$0 { memberToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove member", role: .destructive) {

                    guard let memberToDelete else {

                        return
                    } /* Member confirmed for removal */

                    onDeleteMember(memberToDelete)

                    self.memberToDelete = nil
                }

                Button("Cancel", role: .cancel) {
                    memberToDelete = nil
                }

            } message: {
                Text("This removes the member from all card assignments. Existing comments are kept.")
            }

            .sheet(item: $selectedMemberColor) { target in

                MemberColorEditorSheet(memberName: target.member, initialColor: target.color) { color in
                    onSetMemberColor(target.member, color)
                }
            }
        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


///
/// Carries the selected member and current color while the color editor sheet is presented
///
/// @section    Purpose
///     Provide a stable identifiable sheet item containing the values needed to edit a member icon color
///
/// @details    The member's lowercased name is used as the sheet identity, and the current color seeds the editor
///
/// @note       This is transient presentation state; saving is handled by MemberColorEditorSheet
///
private struct MemberColorTarget: Identifiable {

    let member: String                          /* The name of the member whose color is being edited */    
    let color: Color                            /* The current color of the member's icon             */

    ///
    /// @fcn        MemberColorTarget.id
    /// @brief      Identify the member's color-edit presentation
    /// @details    Uses a lowercased member name for case-insensitive sheet identity
    ///
    /// @return     (String) normalized presentation identity
    /// @post       The member name and seed color remain unchanged
    ///
    var id: String { member.lowercased() }      /* Use the lowercased member name as the unique identifier for the sheet */
}


///
/// Presents the system color picker for one member's icon
///
/// @section    Purpose
///     Let the user preview, change, save, or cancel a member's shared icon color
///
/// @details    Holds the selected color locally until Save invokes onSave; Cancel dismisses without applying changes
///
/// @note       Opacity selection is disabled so the icon remains fully visible
///
///
/// Presents the color editor for one Board member
///
/// @section    Purpose
///     Let the user preview and save a member's icon color
///
private struct MemberColorEditorSheet: View {

    let memberName: String              /* The name of the member whose color is being edited         */
    let onSave: (Color) -> Void         /* The closure to call when the user saves the selected color */

    @Environment(\.dismiss) private var dismiss /* Dismiss action for the color editor */
    @State private var selectedColor: Color /* Draft member icon color */


    ///
    /// @fcn        MemberColorEditorSheet.init(memberName:initialColor:onSave:)
    /// @brief      Seed a member-icon color editing draft
    /// @details    Holds the initial color in local State and installs the submission callback
    ///
    /// @param[in]  memberName Member whose icon color is being edited
    /// @param[in]  initialColor Current color shown when the editor opens
    /// @param[in]  onSave Callback receiving the selected color
    ///
    /// @return     (MemberColorEditorSheet) configured editor
    /// @post       No shared member color is changed until Save invokes onSave
    ///
    init(memberName: String, initialColor: Color, onSave: @escaping (Color) -> Void) {

        self.memberName = memberName
        self.onSave     = onSave
        _selectedColor  = State(initialValue: initialColor)
    }


    ///
    /// @fcn        MemberColorEditorSheet.body
    /// @brief      Present a non-opacity color picker for one member icon
    /// @details    Save submits the draft color and dismisses; Cancel only dismisses
    ///
    /// @return     (some View) medium-sheet member color form
    /// @post       Applying/persisting the chosen color belongs to the onSave caller
    ///
    var body: some View { /* Member icon color editor */

        NavigationStack {

            Form {
                Section(memberName) {
                    ColorPicker("Icon color", selection: $selectedColor, supportsOpacity: false)
                }
            }

            .navigationTitle("Member icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedColor)
                        dismiss()
                    }
                }
            }
        }

        .presentationDetents([.medium])
    }
}


// -------------------------------------- MARK: - Kanban List ----------------------------------- //

///
/// Displays one kanban list and its cards
///
/// @section    Purpose
///     Keep a list title, list metadata, add-card action, and vertically scrollable card collection together
///
struct KanbanListView: View {

    /// Identifies the modal sheet currently presented by a kanban list
    ///
    /// @section    Purpose
    ///     Distinguish list actions from new-card entry
    ///
    private enum ActiveSheet: String, Identifiable {
        case listActions
        case newCard

        ///
        /// @fcn        KanbanListView.ActiveSheet.id
        /// @brief      Identify the list's active modal presentation
        /// @details    Uses the enum raw value to distinguish actions from new-card entry
        ///
        /// @return     (String) stable sheet identity
        /// @post       Presentation state remains unchanged
        ///
        var id: String { rawValue } /* Stable sheet identity */
    }

    let list: KanbanList                        /* The kanban list data rendered by the view                      */
    /// Maximum vertical space available to the list's card collection.
    let availableListHeight: CGFloat
    let displaySettings: BoardDisplaySettings   /* The board's display settings affecting card and list rendering */
    /// Layout preset that controls the list's card dimensions.
    let presentation: BoardPresentation
    let labelLibrary: LabelLibrary              /* Shared categorized labels available to the cards               */
    let toggleCardTitle: (Int) -> Void          /* The action invoked to toggle the title of a card               */
    let canMoveEarlier: Bool                    /* Indicates whether the list can be moved earlier in the board   */
    let canMoveLater:  Bool                     /* Indicates whether the list can be moved later in the board     */
    let onAddCard: (String, String) -> Void     /* The action invoked to add a new card to the list               */
    let onCopyList: () -> Void                  /* The action invoked to copy the list                            */
    let onMoveList: (Int) -> Void               /* The action invoked to move the list by a specified offset      */
    let onSortList: (Bool) -> Void              /* The action invoked to sort the list based on a specified order */
    let onArchiveCompleted: () -> Void          /* The action invoked to archive all completed cards in the list  */
    /// Archived cards retained by this list.
    @Binding var archivedCards: [KanbanCard]
    /// Requests restoration of an archived card by identity.
    let onRestoreArchivedCard: (Int) -> Void
    let onDeleteArchivedCard: (Int) -> Void /* Confirmed removal of a retained card */
    let onArchiveList: () -> Void               /* The action invoked to archive the entire list                  */
    let onDeleteList: () -> Void /* Confirmed removal of this list and its retained content */
    let onDeleteCard: (Int) -> Void             /* The action invoked to delete a card at a specified index       */
    /// Requests archival of an active card by identity.
    let onArchiveCard: (Int) -> Void
    let onUpdateCard: (KanbanCard) -> Void      /* The action invoked to save edited card information             */
    let onMoveCard: (Int, Int) -> Void          /* Move a card to a destination index in this list                */
    /// Reports list-reorder drag updates to the owning board.
    let onListDragChanged: (DragGesture.Value?) -> Void
    /// Reports completion or cancellation of a list-reorder drag.
    let onListDragEnded: () -> Void
    var draggedCardID: Int? = nil
    var dropBeforeCardID: Int? = nil
    var isCardDropTarget = false
    var onCardDragBegan: (Int, CGPoint) -> Void = { _, _ in }
    var onCardDragChanged: (Int, CGPoint) -> Void = { _, _ in }
    var onCardDragEnded: (Int, Bool, CGPoint?) -> Void = { _, _, _ in }
    var cardDragToken = ""
    var onCardDrop: (CGPoint) -> Bool = { _ in false }
    var cardMoveDestinations: [KanbanList] = []
    var onMoveCardToList: (Int, Int) -> Void = { _, _ in }

    @State private var activeSheet: ActiveSheet?            /* The currently active sheet presented modally        */
    /// Opens card creation after the active list-actions sheet has dismissed.
    @State private var opensNewCardAfterDismissal = false
    @State private var isWatching               = false     /* Indicates whether the user is watching the list     */
    @State private var listTint: KanbanListTint = .neutral  /* The tint color applied to the list header and cards */
    @State private var editMode: EditMode       = .inactive /* Indicates whether the list is in edit mode          */
    @State private var deletingCard: KanbanCard? /* Swipe deletion awaiting confirmation */
    /// Measured height of the list header used to size its card collection.
    @State private var headerHeight: CGFloat = 72
    /// Measured card heights keyed by stable card identity.
    @State private var measuredCardHeights: [Int: CGFloat] = [:]
    /// Dynamic Type scaling factor applied to card content.
    @ScaledMetric(relativeTo: .body) private var cardScale = 1.0
    /// Transient state indicating a list title is being held for reordering.
    @GestureState private var isHoldingList = false


    ///
    /// @fcn        KanbanListView.listReorderGesture
    /// @brief      Sequence a title-area hold into horizontal Board-list dragging
    /// @details    Requires a 0.45-second hold within twelve points, then reports zero-threshold
    ///             drag geometry in the WeekListsViewport coordinate space
    ///
    /// @return     (some Gesture) hold/drag sequence with transient holding-state updates
    /// @post       Successful holds report optional drag values; ending calls onListDragEnded
    ///
    private var listReorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("WeekListsViewport")))
            .updating($isHoldingList) { value, state, _ in
                if case .second(true, _) = value {

                    state = true
                }
            }
            .onChanged { value in
                if case .second(true, let drag) = value {

                    onListDragChanged(drag)
                }
            }
            .onEnded { _ in onListDragEnded() }
    }


    ///
    /// @fcn        KanbanListView.cardHeight
    /// @brief      Calculate a Dynamic Type-scaled minimum height for card rows
    /// @details    Uses the local presentation preset rather than a fraction of screen height
    ///
    /// @return     (CGFloat) finite target height of at least one point
    /// @post       Screen geometry and list content remain unchanged
    ///
    private var cardHeight: CGFloat {
        presentation.minimumCardHeight * cardScale
    }


    ///
    /// @fcn        KanbanListView.cardCollectionContentHeight
    /// @brief      Estimate the vertical space required by this list's rows
    /// @details    Uses measured card heights when available, scaled minimums for unmeasured rows,
    ///             44 points for dividers, and an allowance for the Add card row and spacing
    ///
    /// @return     (CGFloat) estimated collection height in points
    /// @post       No card order or layout state is modified
    ///
    private var cardCollectionContentHeight: CGFloat {
        let rowHeight = list.cards.reduce(CGFloat.zero) { height, card in
            height + (card.isSectionDivider ? 44 : max(measuredCardHeights[card.id] ?? 0, cardHeight) + 8)
        }

        return max(88, rowHeight + 64)
    }


    ///
    /// @fcn        KanbanListView.cardCollectionHeight
    /// @brief      Fit the card collection within remaining panel space
    /// @details    Subtracts the measured header and 24-point bottom allowance from available height,
    ///             clamps remaining space to at least one point, and caps it by estimated content height
    ///
    /// @return     (CGFloat) visible card-collection height
    /// @post       Header measurement and card content remain unchanged
    ///
    private var cardCollectionHeight: CGFloat {
        let availableHeight = max(1, availableListHeight - headerHeight - 24)

        return min(cardCollectionContentHeight, availableHeight)
    }

    ///
    /// @fcn        KanbanListView.cardInsertionMarker(before:)
    /// @brief      Render the insertion boundary for the current card-drop target
    /// @details    Shows an accent line only when this list and boundary match the active
    ///             destination. The marker is noninteractive and hidden from accessibility.
    ///
    /// @param[in]  cardID  Board-local identity of the card being dragged or moved
    ///
    /// @return     (some View) insertion line or empty view for an inactive boundary
    ///
    @ViewBuilder
    private func cardInsertionMarker(before cardID: Int?) -> some View {

        if isCardDropTarget && dropBeforeCardID == cardID {

            Rectangle().fill(Color.accentColor).frame(height: 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var cardDropSurface: some View {
        BoardCardDropSurface(token: cardDragToken,
                             isEnabled: editMode != .active,
                             onChanged: { point in
                                 if let cardID = draggedCardID {

                                     onCardDragChanged(cardID, point)
                                 }
                             },
                             onDrop: onCardDrop)
    }

    ///
    /// @fcn        KanbanListView.body
    /// @brief      Compose a list panel with card rows, ordering, and action sheets
    /// @details    Measures the title header, supports hold-to-drag and accessible list movement,
    ///             and wires card completion/edit/archive/delete plus native row reordering.
    ///             List Actions Add card dismisses that sheet before presenting the creation form
    ///
    /// @return     (some View) tinted, height-limited list panel with modal actions
    /// @pre        The parent installs KanbanCard destinations and supplies consistent list callbacks
    /// @post       Content edits delegate to the parent; tint/watch and edit mode remain local.
    ///             Ending the hold resets drag through the parent callback
    ///
    var body: some View { /* List panel and card collection */

        VStack(spacing: 0) {

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(list.title)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    Text("\(list.cards.filter { !$0.isSectionDivider }.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                .contentShape(Rectangle())
                .gesture(listReorderGesture)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Touch and hold to drag this list. Keep holding near either screen edge to move across the board.")
                .accessibilityAction(named: "Move earlier") {
                    if canMoveEarlier {

                        onMoveList(-1)
                    }
                }

                .accessibilityAction(named: "Move later") {
                    if canMoveLater {

                        onMoveList(1)
                    }
                }

                .onChange(of: isHoldingList) { _, holding in
                    if !holding {

                        onListDragEnded()
                    }
                }

                .sensoryFeedback(.selection, trigger: isHoldingList)
                HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {

                    if presentation == .standard {

                        Text(list.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }

                .frame(maxWidth: .infinity, alignment: .leading)

                Button {

                    withAnimation(.easeInOut(duration: 0.2)) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                } label: {

                    Image(systemName: editMode == .active ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }

                .buttonStyle(.plain)
                .accessibilityLabel(editMode == .active ? "Done reordering cards" : "Reorder cards")

                if isWatching {

                    Image(systemName: "eye.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    activeSheet = .listActions
                } label: {

                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }

                .buttonStyle(.plain)
                .accessibilityLabel("\(list.title) list actions")
                }
            }

            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background {
                GeometryReader { header in
                    Color.clear
                        .onAppear { headerHeight = header.size.height }
                        .onChange(of: header.size.height) { _, height in headerHeight = height }
                }
            }

            List {

                ForEach(list.cards) { card in

                    if card.isSectionDivider {

                        NavigationLink(value: card) {

                            Rectangle()
                                .fill(Color.secondary.opacity(0.45))
                                .frame(height: 2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }

                        .buttonStyle(.plain)
                        .modifier(HideNavigationLinkIndicator())
                        .accessibilityLabel("Open section divider")
                        .overlay(alignment: .top) { cardInsertionMarker(before: card.id) }
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: BoardCardFramePreferenceKey.self,
                                value: [card.id: geometry.frame(in: .global)])
                            }
                        }
                        .background { cardDropSurface }
                        .contextMenu {
                            Button("Delete Divider", systemImage: "trash", role: .destructive) { deletingCard = card }
                        }

                        .accessibilityAction(named: "Delete Divider") { deletingCard = card }
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {

                            NavigationLink(value: card) {

                                KanbanCardView(
                                    card:            card,
                                    height:          cardHeight,
                                    displaySettings: displaySettings,
                                    presentation:    presentation,
                                    labelLibrary:    labelLibrary,
                                    onUpdateCard:    onUpdateCard,
                                    onDeleteCard:    { onDeleteCard(card.id) },
                                    onArchiveCard:   { onArchiveCard(card.id) }
                                ) {
                                    toggleCardTitle(card.id)
                                }
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: BoardCardHeightPreferenceKey.self,
                                            value: [card.id: geometry.size.height]
                                        )
                                    }
                                }
                            }

                            .buttonStyle(.plain)
                            .modifier(HideNavigationLinkIndicator())
                            .background {
                                if editMode != .active {

                                    BoardCardDragSource(token: cardDragToken,
                                                        onBegan: { onCardDragBegan(card.id, $0) },
                                                        onChanged: { onCardDragChanged(card.id, $0) },
                                                        onEnded: { onCardDragEnded(card.id, false, nil) })
                                }
                            }
                        .accessibilityActions {
                            ForEach(cardMoveDestinations) { list in
                                Button("Move to \(list.title)") { onMoveCardToList(card.id, list.id) }
                            }
                        }

                        .opacity(draggedCardID == card.id ? 0.45 : 1)
                        .overlay(alignment: .top) { cardInsertionMarker(before: card.id) }
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: BoardCardFramePreferenceKey.self,
                                value: [card.id: geometry.frame(in: .global)])
                            }
                        }
                        .background { cardDropSurface }
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deletingCard = card
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove { sourceOffsets, destinationOffset in

                    guard editMode == .active else {

                        return
                    }

                    guard let sourceIndex = sourceOffsets.first, /* Original drag source row */
                          list.cards.indices.contains(sourceIndex) else {
                        return
                    }

                    let finalIndex = sourceIndex < destinationOffset ? destinationOffset - 1 : destinationOffset /* Destination after source removal */

                    onMoveCard(list.cards[sourceIndex].id, finalIndex)
                }

                .moveDisabled(editMode != .active)

                Button {
                    activeSheet = .newCard
                } label: {
                    Label("Add card", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .background { cardDropSurface }
                .overlay(alignment: .top) { cardInsertionMarker(before: nil) }
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .contentMargins(.bottom, cardCollectionContentHeight > cardCollectionHeight ? 80 : 0, for: .scrollContent)
            .background(.clear)
            .frame(height: cardCollectionHeight)
            .onPreferenceChange(BoardCardHeightPreferenceKey.self) { heights in
                measuredCardHeights.merge(heights, uniquingKeysWith: { _, latest in latest })
            }

            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }

        .background(listTint.color)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isCardDropTarget ? Color.accentColor : .clear, lineWidth: 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }

        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .confirmationDialog("Delete \(deletingCard?.word ?? "card")?", isPresented: Binding(
            get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) {
                if let deletingCard {

                    onDeleteCard(deletingCard.id)
                }

                deletingCard = nil
            }

            Button("Cancel", role: .cancel) { deletingCard = nil }
        } message: {
            Text("Permanently deletes this card, its details, and its bookmark. This cannot be undone.")
        }

        .sheet(item: $activeSheet, onDismiss: {
            guard opensNewCardAfterDismissal else {

                return
            }
            opensNewCardAfterDismissal = false
            activeSheet = .newCard
        }) { presentedSheet in
            switch presentedSheet {
            case .listActions:
                KanbanListActionsSheet(
                    list:               list,
                    canMoveEarlier:     canMoveEarlier,
                    canMoveLater:       canMoveLater,
                    isWatching:         $isWatching,
                    listTint:           $listTint,
                    onAddCard: {
                        opensNewCardAfterDismissal = true
                        activeSheet = nil
                    },
                    onCopyList:         onCopyList,
                    onMoveList:         onMoveList,
                    onSortList:         onSortList,
                    onArchiveCompleted: onArchiveCompleted,
                    archivedCards: $archivedCards,
                    onRestoreArchivedCard: onRestoreArchivedCard,
                    onDeleteArchivedCard: onDeleteArchivedCard,
                    onArchiveList:      onArchiveList,
                    onDeleteList: onDeleteList
                )
                .databaseActivityOverlay()
            case .newCard:
                NewKanbanCardSheet(listTitle: list.title, onCreate: onAddCard)
                    .databaseActivityOverlay()
            }
        }
    }
}


///
/// Hides the automatic trailing indicator on navigation links when supported
///
/// @section    Purpose
///     Keep list rows fully tappable without displaying a redundant disclosure chevron
///
/// @details    Uses SwiftUI's navigation indicator visibility API on iOS 18 and later, while
///             preserving content on earlier versions
///
/// @note       Apply this modifier to navigation links whose destination is indicated by the row itself
///
private struct HideNavigationLinkIndicator: ViewModifier {

    ///
    /// @fcn        HideNavigationLinkIndicator.body(content:)
    /// @brief      Configure navigation indicator visibility for the modified content
    /// @details    Hides navigation link indicators on iOS 18 and later; earlier iOS versions
    ///             receive the content unchanged
    ///
    /// @param[in]  content  View content to which this modifier is applied
    ///
    /// @return     (some View) modified content with the navigation indicator hidden when supported
    ///
    /// @pre        SwiftUI invokes this function when the modifier is applied to a view
    /// @post       The original content is preserved, with supported navigation indicators hidden
    ///
    @ViewBuilder
    func body(content: Content) -> some View {

        if #available(iOS 18.0, *) {

            content.navigationLinkIndicatorVisibility(.hidden)
            
        } else {

            content
        }
    }
}


///
/// Presents a form for creating a card in the selected kanban list
///
/// @section    Purpose
///     Collect a card title and optional description, then return the trimmed values to the
///     owning list view
///
/// @details    The title field also accepts the divider marker, allowing the list to create a
///             movable section divider
///
/// @note       Dismissing with Cancel does not invoke the creation callback
///
private struct NewKanbanCardSheet: View {

    let listTitle: String                               /* Title of the kanban list to which the new card will be added                             */
    let onCreate: (String, String) -> Void              /* Callback invoked with the trimmed title and description when the user creates a new card */

    @Environment(\.dismiss) private var dismiss         /* Environment variable to dismiss the current view */
    @State private var title       = ""                 /* User-entered card title                          */
    @State private var description = ""                 /* User-entered card description                    */


    ///
    /// @fcn        NewKanbanCardSheet.trimmedTitle
    /// @brief      Normalize the new-card title for validation and creation
    /// @details    Removes surrounding whitespace/newlines without changing internal text or the draft
    ///
    /// @return     (String) trimmed title, potentially empty
    /// @post       No card is created and draft text remains unchanged
    ///
    private var trimmedTitle: String { /* Normalized new-card title */
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        NewKanbanCardSheet.body
    /// @brief      Collect a nonblank card title and optional description
    /// @details    Accepts divider-marker titles; Add submits both trimmed fields and dismisses,
    ///             while Cancel dismisses without invoking the creation callback
    ///
    /// @return     (some View) new-card navigation form with medium/large sheet detents
    /// @post       Blank titles disable Add; card allocation and persistence belong to onCreate
    ///
    var body: some View { /* New-card form and submission controls */

        NavigationStack {

            Form {

                Section("Card details") {
                    TextField("Title (or --- for divider)", text: $title)
                        .textInputAutocapitalization(.never)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
            }

            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .cancellationAction) {
                    
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    
                    Button("Add") {
                        onCreate(trimmedTitle, description.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }

                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


///
/// Defines the selectable background tints for kanban lists
///
/// @section    Purpose
///     Provide consistent, subtle colors that help distinguish lists without changing their card content
///
/// @details    Each case exposes a stable raw-value identity, a user-facing title, and a
///             corresponding list background color
///
/// @note       Case ordering controls the options presented by the list color picker
///
private enum KanbanListTint: String, CaseIterable, Identifiable {
    case neutral
    case blue
    case green
    case orange
    case red

    ///
    /// @fcn        KanbanListTint.id
    /// @brief      Identify a selectable list tint
    /// @details    Uses the raw enum value for consistent menu identity
    ///
    /// @return     (String) tint identity
    /// @post       The selected tint is unchanged
    ///
    var id: String { rawValue } /* Stable tint identity */

    ///
    /// @fcn        KanbanListTint.title
    /// @brief      Resolve the user-facing list tint label
    /// @details    Names each color choice, with neutral displayed as Default
    ///
    /// @return     (String) tint menu label
    /// @post       No view or model state is modified
    ///
    var title: String { /* User-facing tint label */
        switch self {

            case .neutral: "Default"
            case .blue:    "Blue"
            case .green:   "Green"
            case .orange:  "Orange"
            case .red:     "Red"
        }
    }

    ///
    /// @fcn        KanbanListTint.color
    /// @brief      Resolve the subtle list-panel background color
    /// @details    Uses system gray for neutral and twelve-percent opacity for named accent colors
    ///
    /// @return     (Color) panel background color
    /// @post       The tint selection and list data remain unchanged
    ///
    var color: Color { /* Subtle list background color */
        switch self {

            case .neutral: Color(.systemGray6)
            case .blue:    Color.blue.opacity(0.12)
            case .green:   Color.green.opacity(0.12)
            case .orange:  Color.orange.opacity(0.12)
            case .red:     Color.red.opacity(0.12)
        }
    }
}


///
/// Presents actions for copying, moving, organizing, and archiving one list
///
/// @section    Purpose
///     Keep list-level operations together in a dedicated action sheet
///
private struct KanbanListActionsSheet: View {

    let list: KanbanList                   /* The Kanban list this sheet is associated with                                 */
    let canMoveEarlier: Bool               /* Indicates if the list can be moved earlier                                    */
    let canMoveLater: Bool                 /* Indicates if the list can be moved later                                      */
    @Binding var isWatching: Bool          /* Indicates if the user is watching the list                                    */
    @Binding var listTint: KanbanListTint  /* The current tint color of the list                                            */
    let onAddCard: () -> Void              /* Action to perform when adding a card                                          */
    let onCopyList: () -> Void             /* Action to perform when copying the list                                       */
    let onMoveList: (Int) -> Void          /* Action to perform when moving the list by a given offset                      */
    let onSortList: (Bool) -> Void         /* Action to perform when sorting the list; true for A to Z, false for Z to A    */
    let onArchiveCompleted: () -> Void     /* Action to perform when archiving completed cards                              */
    /// Archived cards available to restore to the active list.
    @Binding var archivedCards: [KanbanCard]
    /// Restores an archived card by stable card identity.
    let onRestoreArchivedCard: (Int) -> Void
    let onDeleteArchivedCard: (Int) -> Void /* Permanently remove a confirmed archived card */
    let onArchiveList: () -> Void          /* Action to perform when archiving the entire list                              */
    let onDeleteList: () -> Void /* Permanently remove this list after confirmation */

    @Environment(\.dismiss) private var dismiss /* Dismiss action for list operations */
    @State private var confirmingArchive = false /* Archive confirmation presentation state */
    @State private var confirmingDelete = false /* Permanent list deletion confirmation */


    ///
    /// @fcn        KanbanListActionsSheet.body
    /// @brief      Present creation, organization, appearance, and archive actions for one list
    /// @details    Offers copy, bounded earlier/later movement, section-aware sorting, tint/watch
    ///             controls, archived-card browsing, completed-card archival, and confirmed list archival
    ///
    /// @return     (some View) list-actions navigation sheet
    /// @post       Mutation callbacks belong to the parent. Add card delegates sheet handoff without
    ///             calling dismiss here; copy/move/sort/archive actions dismiss after invoking callbacks
    /// @note       Tint/watch controls update their bindings immediately and do not persist Board metadata
    ///
    var body: some View { /* List operation menu */
        
        NavigationStack {

            List {

                Section {

                    Button {
                        onAddCard()
                    } label: {
                        Label("Add card", systemImage: "plus")
                    }

                    Button {
                        onCopyList()
                        dismiss()
                    } label: {
                        Label("Copy list", systemImage: "doc.on.doc")
                    }

                    Menu {
                        Button("Move earlier") {
                            onMoveList(-1)
                            dismiss()
                        }

                        .disabled(!canMoveEarlier)

                        Button("Move later") {
                            onMoveList(1)
                            dismiss()
                        }

                        .disabled(!canMoveLater)
                        
                    } label: {
                        
                        Label("Move list", systemImage: "arrow.left.arrow.right")
                            .foregroundStyle(.primary)
                    }

                    Menu {
                        Button("Title A to Z") {
                            onSortList(true)
                            dismiss()
                        }

                        Button("Title Z to A") {
                            onSortList(false)
                            dismiss()
                        }
                    } label: {
                        Label("Sort list", systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(.primary)
                    }

                    Menu {
                        ForEach(KanbanListTint.allCases) { tint in
                            Button {
                                listTint = tint
                            } label: {
                                Label(tint.title, systemImage: listTint == tint ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    } label: {
                        Label("Change list color", systemImage: "paintpalette")
                            .foregroundStyle(.primary)
                    }

                    Button {
                        isWatching.toggle()
                        
                    } label: {
                        Label(isWatching ? "Unwatch" : "Watch", systemImage: isWatching ? "eye.slash" : "eye")
                    }
                }

                Section {
                    NavigationLink {
                        ArchivedCardsView(
                            listTitle: list.title,
                            cards: $archivedCards,
                            onRestore: onRestoreArchivedCard,
                            onDelete: onDeleteArchivedCard
                        )
                    } label: {
                        Label("View Archived Cards", systemImage: "archivebox")
                    }

                    Button {
                        onArchiveCompleted()
                        dismiss()
                        
                    } label: {
                        Label("Archive completed cards", systemImage: "archivebox")
                    }

                    Button(role: .destructive) {
                        confirmingArchive = true
                        
                    } label: {
                        Label("Archive list", systemImage: "archivebox")
                    }

                    Button("Delete List", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }

            .listStyle(.insetGrouped)
            .navigationTitle("List actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }

            .confirmationDialog("Archive \(list.title)?", isPresented: $confirmingArchive, titleVisibility: .visible) {

                Button("Archive list", role: .destructive) {
                    onArchiveList()
                    dismiss()
                }

                .confirmationDialog("Delete \(list.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete List", role: .destructive) {
                        onDeleteList()
                        dismiss()
                    }

                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Permanently deletes this list, all active and archived cards, and their bookmarks. This cannot be undone.")
                }
            }
        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}


// -------------------------------------- MARK: - Kanban Card ----------------------------------- //

///
/// Presents cards retained in a list's archive
///
/// @section    Purpose
///     Let the user restore archived cards while preserving their stored card state
///
private struct ArchivedCardsView: View {

    /// Title of the list whose archived cards are being browsed.
    let listTitle: String
    /// Archived card snapshot supplied by the owning list.
    @Binding var cards: [KanbanCard]
    /// Requests restoration of an archived card by identity.
    let onRestore: (Int) -> Void
    let onDelete: (Int) -> Void /* Owner removes confirmed archived cards */
    @State private var deletingCard: KanbanCard? /* Archived card awaiting deletion */


    ///
    /// @fcn        ArchivedCardsView.body
    /// @brief      Browse saved card records for one list
    /// @details    Displays titles and up to three lines of supporting copy, with Restore controls,
    ///             an empty-state explanation, and a reminder that completion state is preserved
    ///
    /// @return     (some View) archived-card navigation list
    /// @post       Restore invokes onRestore with the card identity; record movement belongs to the parent
    ///
    var body: some View {
        List {
            Section {
                ForEach(cards) { card in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            NavigationLink(card.word) {
                                ArchivedCardInspectionView(card: card) {
                                    onDelete(card.id)

                                    return !cards.contains { $0.id == card.id }
                                }
                            }

                            .font(.headline)

                            if !card.funParagraph.isEmpty {

                                Text(card.funParagraph)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }

                        Spacer()
                        Button("Restore") {
                            onRestore(card.id)
                        }

                        .buttonStyle(.bordered)
                        .accessibilityLabel("Restore \(card.word)")
                        Button("Delete", systemImage: "trash", role: .destructive) { deletingCard = card }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Delete \(card.word)")
                    }
                }
            } header: {
                Text(listTitle)
            } footer: {
                if !cards.isEmpty {

                    Text("Restored cards return to the end of this list and keep their completion status.")
                }
            }
        }
        .overlay {
            if cards.isEmpty {

                ContentUnavailableView(
                    "No Archived Cards",
                    systemImage: "archivebox",
                    description: Text("Cards you archive from this list will appear here.")
                )
                .allowsHitTesting(false)
            }
        }

        .navigationTitle("Archived Cards")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(deletingCard?.word ?? "card")?", isPresented: Binding(
            get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) {
                if let deletingCard {

                    onDelete(deletingCard.id)
                }

                deletingCard = nil
            }

            Button("Cancel", role: .cancel) { deletingCard = nil }
        } message: {
            Text("Permanently deletes this card, its details, and its bookmark. This cannot be undone.")
        }
    }
}


///
/// Displays a compact summary of a kanban card
///
/// @section    Purpose
///     Present the title, supporting copy, and compact metadata used to scan cards on the board
///
struct KanbanCardView: View {

    @AppStorage("Plenact.CardCovers.enabled") private var showsCardCovers = true /* Shared display-only preference */
    let card: KanbanCard                            /* The kanban card being displayed                               */
    let height: CGFloat                             /* Minimum card height; content may grow                         */
    let displaySettings: BoardDisplaySettings       /* Settings controlling which elements of the card are displayed */
    /// Layout preset used to select compact card dimensions.
    var presentation: BoardPresentation = .standard
    let labelLibrary: LabelLibrary                  /* Shared label catalog used to resolve card label IDs           */
    let onUpdateCard: (KanbanCard) -> Void          /* The action invoked when card details are updated              */
    let onDeleteCard: () -> Void                    /* The action invoked when this card is deleted                  */
    /// Requests archival of the displayed card.
    let onArchiveCard: () -> Void
    let onToggle: () -> Void                        /* Callback invoked when the card's title checkbox is toggled    */

    @State private var renameDraft        = ""      /* Draft text for the rename operation                           */
    @State private var isRenaming         = false   /* Flag indicating if the rename operation is active             */
    @State private var isEditingInfo      = false   /* Flag indicating if the card info editing mode is active       */
    @State private var isConfirmingDelete = false   /* Flag indicating if the delete confirmation dialog is shown    */
    /// Current Dynamic Type size used to adapt the compact card layout.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize


    ///
    /// @fcn        KanbanCardView.trimmedRenameDraft
    /// @brief      Normalize the proposed card name
    /// @details    Trims outer whitespace/newlines for validation and submission without editing the draft
    ///
    /// @return     (String) normalized rename text
    /// @post       Card content and draft state remain unchanged
    ///
    private var trimmedRenameDraft: String { /* Normalized rename input */
        renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    ///
    /// @fcn        KanbanCardView.cardLabels
    /// @brief      Resolve assigned label identities into display definitions
    /// @details    Preserves card label-ID order and omits IDs absent from the supplied library
    ///
    /// @return     ([KanbanLabel]) resolved labels for card badges
    /// @post       Unresolved IDs are not removed from the card
    ///
    private var cardLabels: [KanbanLabel] { /* Resolved labels shown on this card */
        card.labelIDs.compactMap { labelID in
            labelLibrary.labels.first(where: { $0.id == labelID })
        }
    }


    ///
    /// @fcn        KanbanCardView.cardUpdated(title:subtitle:description:)
    /// @brief      Create a card snapshot containing edited display information
    /// @details    Replaces the title, subtitle, and description while preserving the card's
    ///             identity and other state
    ///
    /// @param[in]  title        Updated card title
    /// @param[in]  subtitle     Optional board subtitle override
    /// @param[in]  description  Updated detail description
    ///
    /// @return     (KanbanCard) updated card retaining its dates, checklist, comments, completion,
    ///             and activity state
    ///
    /// @pre        Values come from the current card edit operation
    /// @post       The original card remains unchanged; the returned snapshot contains the
    ///             requested display values
    ///
    private func cardUpdated(title: String, subtitle: String?, description: String?) -> KanbanCard {

        KanbanCard(
            id:                   card.id,
            word:                 title,
            listTitle:            card.listTitle,
            isDivider:            card.isDivider,
            isTitleChecked:       card.isTitleChecked,
            startDate:            card.startDate,
            dueDate:              card.dueDate,
            checklists:           card.checklists,
            comments:             card.comments,
            members:              card.members,
            labelIDs:             card.labelIDs,
            attachments:          card.attachments,
            coverAttachmentID:    card.coverAttachmentID,
            dismissedActivityIDs: card.dismissedActivityIDs,
            descriptionOverride:  description,
            subtitleOverride:     subtitle
        )
    }


    ///
    /// @fcn        KanbanCardView.renameCard()
    /// @brief      Submit the renamed card title
    /// @details    Trims the title draft, ignores an empty result, and sends the updated card to
    ///             the board callback
    ///
    /// @return     (Void) requests a card update when the trimmed title is not empty
    ///
    /// @pre        renameDraft contains the title entered in the Rename Card alert
    /// @post       A valid title is synchronized to board state; an empty title causes no change
    ///
    private func renameCard() {
        
        guard !trimmedRenameDraft.isEmpty else {

            return
        }

        onUpdateCard(cardUpdated(
            title:       trimmedRenameDraft,
            subtitle:    card.subtitleOverride,
            description: card.descriptionOverride
        ))
    }


    ///
    /// @fcn        KanbanCardView.body
    /// @brief      Render a content-fitting card summary and card action menu
    /// @details    Shows completion, supporting text, up to three label chips plus overflow,
    ///             and preference-controlled metadata badges. Provides archive, confirmed delete,
    ///             validated rename, and full display-text editing
    ///
    /// @return     (some View) card summary with alerts and information-editor presentation
    /// @post       All card mutations delegate to parent callbacks; local state controls presentations only
    /// @note       The due-date badge uses the existing Today label whenever hasDueDate is true;
    ///             this row does not compare the due date with the current calendar day
    ///
    var body: some View { /* Compact card summary and card actions */

        VStack(alignment: .leading, spacing: 9) {

            if showsCardCovers, let cover = card.coverAttachment {

                CardCoverPreview(attachment: cover, height: presentation == .overview ? 72 : 128)
            }

            HStack(alignment: .center, spacing: 8) {

                Button {
                    onToggle()
                } label: {
                    Image(systemName: card.isTitleChecked ? "checkmark.square.fill" : "square")
                        .font(.headline)
                        .foregroundStyle(card.isTitleChecked ? .green : .secondary)
                        .frame(width: 44, height: 44)
                }

                .buttonStyle(.plain)
                .accessibilityLabel(card.isTitleChecked ? "Uncheck card title" : "Check card title")

                Text(card.word)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : (presentation == .overview ? 2 : 3))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }

            if presentation == .standard && !card.subtitle.isEmpty {

                Text(card.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if presentation == .standard && !cardLabels.isEmpty {

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        ForEach(cardLabels.prefix(3)) { label in
                            KanbanLabelChip(label: label)
                        }

                        if cardLabels.count > 3 {

                            Text("+\(cardLabels.count - 3)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    .fixedSize(horizontal: true, vertical: false)
                    Text("\(cardLabels.count) labels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .center, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    if !dynamicTypeSize.isAccessibilitySize {

                        HStack(spacing: 10) { cardBadges }
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        cardBadges
                    }
                }

                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                cardActions
            }
        }

        .fixedSize(horizontal: false, vertical: true)
        .padding(presentation == .overview ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: height, alignment: .top)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
        .padding(.horizontal, 4)
        .alert("Rename Card", isPresented: $isRenaming) {
            
            TextField("Card title", text: $renameDraft)
                .textInputAutocapitalization(.never)
            
            Button("Cancel", role: .cancel) {}
            
            Button("Rename", action: renameCard)
                .disabled(trimmedRenameDraft.isEmpty)
            
        } message: {
            
            Text("Enter a new title for this card.")
        }

        .confirmationDialog("Delete \(card.word)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            
            Button("Delete Card", role: .destructive, action: onDeleteCard)
            Button("Cancel", role: .cancel) {}
        }

        .sheet(isPresented: $isEditingInfo) {
            CardInfoEditorSheet(card: card) { title, subtitle, description in
                onUpdateCard(cardUpdated(title: title, subtitle: subtitle, description: description))
            }

            .databaseActivityOverlay()
        }
    }

    ///
    /// @fcn        KanbanCardView.cardActions
    /// @brief      Provide the card's archive, delete, rename, and edit actions
    /// @details    Builds the ellipsis menu and delegates each operation to the card callbacks
    ///
    /// @return     (some View) accessible card-action menu
    /// @post       Card state changes only after a selected action is invoked
    ///
    private var cardActions: some View {
        Menu {
            if card.coverAttachmentID != nil {

                Button("Remove Cover", systemImage: "photo.badge.minus") {
                    var updated = card

                    updated.coverAttachmentID = nil
                    onUpdateCard(updated)
                }
            }

            Button(action: onArchiveCard) {
                Label("Archive Card", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Card", systemImage: "trash")
            }
            Button {
                renameDraft = card.word
                isRenaming = true
            } label: {
                Label("Rename Card", systemImage: "pencil")
            }
            Button {
                isEditingInfo = true
            } label: {
                Label("Update Card Info", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }

        .buttonStyle(.plain)
        .accessibilityLabel("Card actions")
    }

    ///
    /// @fcn        KanbanCardView.cardBadges
    /// @brief      Build the card metadata badges selected in Board settings
    /// @details    Conditionally presents comment count, checklist progress, and due-date indicators
    ///
    /// @return     (some View) zero or more enabled card badges
    /// @post       Card data and display settings remain unchanged
    ///
    @ViewBuilder
    private var cardBadges: some View {
        if displaySettings.showCommentCounts {

            Label("\(card.commentCount)", systemImage: "text.bubble")
        }

        if displaySettings.showChecklistProgress {

            Label("\(card.completedChecklistItems)/\(card.checklistItems.count)", systemImage: "checklist")
        }

        if displaySettings.showDueDateBadges && card.hasDueDate {

            Label("Today", systemImage: "calendar")
        }
    }
}


/// Presents the full editor for a card's title, board subtitle, and detail description
///
/// @section    Purpose
///     Collect card display text and submit the completed values through the supplied save callback
///
/// @note   The parent card view owns persistence; cancel dismisses without invoking the callback
///
private struct CardInfoEditorSheet: View {

    let onSave: (String, String, String) -> Void /* Callback receiving the edited card text */

    @Environment(\.dismiss) private var dismiss     /* Dismiss action for the sheet         */
    @State private var title:       String          /* Draft text for the title field       */
    @State private var subtitle:    String          /* Draft text for the subtitle field    */
    @State private var description: String          /* Draft text for the description field */


    ///
    /// @fcn        CardInfoEditorSheet.trimmedTitle
    /// @brief      Return the title draft without surrounding whitespace
    /// @details    Trims leading and trailing whitespace and newline characters before validation or saving
    ///
    /// @return     (String) normalized title draft; may be empty when the input contains only whitespace
    ///
    /// @pre        title contains the current text-field value
    /// @post       The stored title draft is unchanged
    ///
    private var trimmedTitle: String { /* Normalized card title draft */
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        CardInfoEditorSheet.init(card:onSave:)
    /// @brief      Initialize the card information editor
    /// @details    Seeds the title, subtitle, and description fields from the selected card and
    ///             stores its save callback
    ///
    /// @param[in]  card    Card whose information will be edited
    /// @param[in]  onSave  Callback that applies the edited title, subtitle, and description
    ///
    /// @return     (CardInfoEditorSheet) configured card information form
    ///
    /// @pre        card contains the current values to present in the form
    /// @post       All editable fields begin with the selected card's current display values
    ///
    init(card: KanbanCard, onSave: @escaping (String, String, String) -> Void) {

        self.onSave  = onSave
        _title       = State(initialValue: card.word)
        _subtitle    = State(initialValue: card.subtitle)
        _description = State(initialValue: card.funParagraph)
    }
    

    ///
    /// @fcn        CardInfoEditorSheet.body
    /// @brief      Build the card information editing form
    /// @details    Presents title, subtitle, and description fields with Cancel and validated Save.
    ///             Only the title is trimmed; subtitle/description are submitted exactly as entered
    ///
    /// @return     (some View) modal form for updating card display information
    ///
    /// @pre        Editor state has been initialized from the selected card
    /// @post       Save invokes onSave with the edited values; Cancel dismisses without applying them
    ///
    var body: some View { /* Card title, subtitle, and description form */

        NavigationStack {

            Form {
                Section("Card details") {
                    
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.never)
                    
                    TextField("Subtitle", text: $subtitle)
                        .textInputAutocapitalization(.never)
                }

                Section("Description") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(4...12)
                }
            }

            .navigationTitle("Update Card Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedTitle, subtitle, description)
                        dismiss()
                    }

                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


///
/// Presents one Today list vertically while sharing its cards with the Week Board
///
/// @section    Purpose
///     Provide focused-list capture and card actions against the shared Board snapshot
///
struct TodayListDetailView: View {

    @Binding var lists: [KanbanList] /* Shared local Board snapshot */
    /// Archived lists and cards retained to reserve identities during creation.
    let reservedLists: [KanbanList]
    @Binding var labelLibrary: LabelLibrary /* Shared reusable label library */
    @Binding var savedCardIDs: Set<Int> /* Device-local saved cards */

    let listID: Int /* Focused list identity */
    let currentUserName: String /* Current activity author */
    let onClose: () -> Void /* Return to Today */
    let onOpenWeek: () -> Void /* Open this list in the Week workspace */
    let onPermanentDelete: (Int) -> Bool /* Parent's save-first Week deletion result */

    @State private var newCardTitle = "" /* Inline card-creation draft */


    ///
    /// @fcn        TodayListDetailView.focusedList
    /// @brief      Resolve the focused Today list in the shared active snapshot
    /// @details    Finds the first list matching listID without selecting a fallback
    ///
    /// @return     (KanbanList?) current list value, or nil after removal/archive
    /// @post       Selection and shared Board data remain unchanged
    ///
    private var focusedList: KanbanList? {
        lists.first { $0.id == listID }
    }


    ///
    /// @fcn        TodayListDetailView.body
    /// @brief      Present today's selected list vertically with shared Week card actions
    /// @details    Reuses compact card rows and detail navigation, displays dividers without
    ///             detail links, and offers inline card capture. Missing lists show an unavailable state
    ///
    /// @return     (some View) focused-list navigation stack with activity feedback
    /// @pre        lists is the writable active Week partition; reservedLists retains archived ID reservations
    /// @post       Card edits mutate the shared binding for caller-owned persistence; label changes
    ///             save locally. Toolbar actions delegate Today/Week routing to supplied callbacks
    ///
    var body: some View {

        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color(.systemGray6).ignoresSafeArea()

                    if let focusedList {

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(focusedList.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                ForEach(focusedList.cards) { card in
                                    if card.isSectionDivider {

                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.45))
                                            .modifier(ContentLifecycleActions(
                                                title: "Divider", kind: "Card", onArchive: nil,
                                                onDelete: { deleteCard(card.id) }
                                            ))
                                            .frame(height: 2)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                    } else {
                                        NavigationLink(value: card) {
                                            KanbanCardView(
                                                card: card,
                                                height: BoardPresentation.standard.minimumCardHeight,
                                                displaySettings: BoardDisplaySettings(),
                                                labelLibrary: labelLibrary,
                                                onUpdateCard: updateCard,
                                                onDeleteCard: { deleteCard(card.id) },
                                                onArchiveCard: { archiveCard(card.id) }
                                            ) {
                                                toggleCard(card.id)
                                            }
                                        }

                                        .buttonStyle(.plain)
                                    }
                                }

                                HStack(spacing: 10) {
                                    TextField("Add a card to \(focusedList.title)…", text: $newCardTitle)
                                        .submitLabel(.done)
                                        .onSubmit(addCard)

                                    Button(action: addCard) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                    }

                                    .disabled(newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityLabel("Add card to \(focusedList.title)")
                                }

                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }

                            .padding(16)
                        }

                        .background(.clear)
                    } else {
                        ContentUnavailableView("List unavailable", systemImage: "list.bullet")
                    }
                }
            }

            .navigationTitle(focusedList?.title ?? "Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Today", systemImage: "chevron.left", action: onClose)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Open in Week", action: onOpenWeek)
                }
            }

            .navigationDestination(for: KanbanCard.self) { card in
                CardDetailView(
                    card: card,
                    labelLibrary: $labelLibrary,
                    availableLists: lists.filter { $0.id != listID },
                    currentUserName: currentUserName,
                    savedCardIDs: $savedCardIDs,
                    onTitleToggle: updateCard,
                    onMoveToList: { destinationListID in
                        moveCard(card.id, toListID: destinationListID)
                    },
                    onArchive: {
                        archiveCard(card.id)
                    },
                    onDelete: {
                        deleteCard(card.id)
                    }
                )
            }

            .onChange(of: labelLibrary) { _, updatedLibrary in
                LabelLibraryStore.save(updatedLibrary)
            }
        }

        .databaseActivityOverlay()
    }


    ///
    /// @fcn        TodayListDetailView.toggleCard(_:)
    /// @brief      Toggle one focused-list card's title completion
    /// @details    Resolves the focused list and active card by ID before flipping its completion
    ///             flag
    ///
    /// @param[in]  cardID  Card identity within the focused list
    ///
    /// @return     (Void) updates shared completion state
    ///
    /// @post       Missing list/card identities leave state unchanged; caller observation owns
    ///             persistence
    ///
    private func toggleCard(_ cardID: Int) {

        guard let listIndex = lists.firstIndex(where: {

            $0.id == listID
        }),
              let cardIndex = lists[listIndex].cards.firstIndex(where: { $0.id == cardID }) else { return }
        lists[listIndex].cards[cardIndex].isTitleChecked.toggle()
    }


    ///
    /// @fcn        TodayListDetailView.archiveCard(_:)
    /// @brief      Archive a task card in the shared Week snapshot
    /// @details    Finds the first active list containing the identity and delegates to the model
    ///             helper; it is not restricted to the focused list after a card moves
    ///
    /// @param[in]  cardID  Board-unique active card identity
    ///
    /// @return     (Void) transfers a matching non-divider card to its list's archive
    ///
    /// @post       Missing IDs/dividers do nothing; full content and attachments are retained
    ///
    private func archiveCard(_ cardID: Int) {

        guard let listIndex = lists.firstIndex(where: {

            $0.cards.contains(where: { $0.id == cardID })
        }) else {
            return
        }
        lists[listIndex].archiveCard(id: cardID)
    }


    ///
    /// @fcn        TodayListDetailView.updateCard(_:)
    /// @brief      Replace a shared active card with its edited snapshot
    /// @details    Searches all supplied active lists by identity so edits can resolve after list
    ///             movement
    ///
    /// @param[in]  updatedCard  Complete edited card value with an existing Board identity
    ///
    /// @return     (Void) replaces the first matching active record
    ///
    /// @post       Unknown IDs do nothing; this helper does not prune attachment files
    ///
    private func updateCard(_ updatedCard: KanbanCard) {

        guard let listIndex = lists.firstIndex(where: {

            $0.cards.contains(where: { $0.id == updatedCard.id })
        }),
              let cardIndex = lists[listIndex].cards.firstIndex(where: { $0.id == updatedCard.id }) else { return }
        lists[listIndex].cards[cardIndex] = updatedCard
    }


    ///
    /// @fcn        TodayListDetailView.deleteCard(_:)
    /// @brief      Remove a card from the focused list
    /// @details    Delegates complete active/archive record and bookmark removal to the Week owner
    ///
    /// @param[in]  cardID  Identity to remove from the focused list
    ///
    /// @return     (Bool) successful checked save and canonical removal
    ///
    /// @post       Failed persistence leaves content, bookmarks, and detail drafts retained
    ///
    @discardableResult
    private func deleteCard(_ cardID: Int) -> Bool {

        onPermanentDelete(cardID)
    }


    ///
    /// @fcn        TodayListDetailView.moveCard(_:toListID:)
    /// @brief      Move a focused-list card to another active Week list
    /// @details    Removes the source record, updates its containing-list title, and appends it to
    ///             the destination while preserving all remaining card state
    ///
    /// @param[in]  cardID             Card identity in the focused source list
    /// @param[in]  destinationListID  Different active list identity receiving the card
    ///
    /// @return     (Void) updates source and destination in the shared binding
    ///
    /// @post       Missing identities or a same-list destination leave state unchanged
    ///
    private func moveCard(_ cardID: Int, toListID destinationListID: Int) {

        guard let sourceListIndex = lists.firstIndex(where: {

            $0.id == listID
        }),
              let destinationListIndex = lists.firstIndex(where: { $0.id == destinationListID }),
              sourceListIndex != destinationListIndex,
              let cardIndex = lists[sourceListIndex].cards.firstIndex(where: { $0.id == cardID }) else { return }

        var movedCard = lists[sourceListIndex].cards.remove(at: cardIndex)

        movedCard.listTitle = lists[destinationListIndex].title
        lists[destinationListIndex].cards.append(movedCard)
    }
    

    ///
    /// @fcn        TodayListDetailView.addCard()
    /// @brief      Submit the inline title to the focused list
    /// @details    Trims whitespace, reserves IDs across active and archived cards/lists, and
    ///             recognizes divider-marker titles before appending a new record
    ///
    /// @return     (Void) appends the card and clears newCardTitle after successful insertion
    ///
    /// @post       Blank input or an unavailable list leaves the draft and Board unchanged;
    ///             persistence follows the caller's shared-state observation
    ///
    private func addCard() {

        let title = newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, let listIndex = lists.firstIndex(where: {

            $0.id == listID
        }) else {
            return
        }

        let nextCardID = ((lists + reservedLists).flatMap { $0.allCards.map(\.id) }.max() ?? -1) + 1
        lists[listIndex].cards.append(
            KanbanCard(
                id: nextCardID,
                word: title,
                listTitle: lists[listIndex].title,
                isDivider: KanbanCard.isDividerTitle(title)
            )
        )
        newCardTitle = ""
    }
}


// -------------------------------------- MARK: - Previews -------------------------------------- //

/// Preview the complete board presentation with deterministic sample data
#Preview {
    ContentView(lists: .constant(SampleData.lists))
}
