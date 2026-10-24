// --------------------------------------------------------------------------------------------------
// @file       BoardInteractions.swift
// @brief      Native Board drag, drop, and swipe routing
// @details    Coordinates native row interactions, insertion boundaries, and the reserved
//             Board-paging swipe region without replacing canonical content identities.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Coordinates native List swipe priority inside a Board
///
/// @section    Purpose
///     Makes enclosing horizontal paging wait for eligible native row pans while excluding the
///     routing gate to avoid dependency cycles.
///
@MainActor
enum BoardListSwipePriority
{


    ///
    /// @fcn        BoardListSwipePriority.install
    /// @brief      Prioritize native list row gestures over board paging
    /// @details    Finds a horizontal ancestor and makes its pan wait for the inner list's other pan gestures;
    ///             returns the number of dependencies installed.
    ///
    /// @param[in]  list  List supplying the current content and metadata
    ///
    /// @return     (Int) number of native row-pan gestures given priority over horizontal board paging
    ///
    @discardableResult
    static func install(for list: UIScrollView) -> Int
    {

        guard list is UICollectionView || list is UITableView else
        {
            return 0
        }

        var ancestor = list.superview
        while let view = ancestor
        {

            if let board = view as? UIScrollView,
            board.alwaysBounceHorizontal || board.contentSize.width > board.bounds.width + 1
            {

                // Leave the vertical scrolling pan independent; prioritize the
                // native row-action/editing pans before horizontal Board paging.
                let gestures = (list.gestureRecognizers ?? []).filter
                {

                    $0 is UIPanGestureRecognizer && $0 !== list.panGestureRecognizer && !($0 is BoardCardSwipeGate)
                }

                for gesture in gestures
                {
                    board.panGestureRecognizer.require(toFail: gesture)
                }

                return gestures.count
            }

            ancestor = view.superview
        }

        return 0
    }

}


///
/// Classifies a Card swipe by its starting coordinates
///
/// @section    Purpose
///     Reserves the rightmost quarter for Board paging and leaves the remaining width available to
///     native row swipe actions.
///
enum BoardCardSwipeRouting
{


    ///
    /// @fcn        BoardCardSwipeRouting.routesToBoard(start:bounds:)
    /// @brief      Reserve the rightmost quarter of a Card for Board navigation
    /// @details    Uses the physical Card bounds, independent of text direction or screen width.
    ///             Only a start inside the Card and at or beyond seventy-five percent is routed.
    ///
    /// @param[in]  start   Initial touch in the same coordinates as bounds
    /// @param[in]  bounds  Actual Card preview bounds
    ///
    /// @return     (Bool) true for the right quarter, false for the delete region or invalid bounds
    ///
    static func routesToBoard(start: CGPoint, bounds: CGRect) -> Bool
    {

        bounds.width > 0 && bounds.contains(start) && (start.x - bounds.minX) / bounds.width >= 0.75
    }

}


///
/// Arbitrates native row Delete and horizontal Board paging
///
/// @section    Purpose
///     Fails outside the reserved Card region and permits the Board pan to recognize alongside the
///     gate without replacing native delegates.
///
@MainActor
final class BoardCardSwipeGate: UIPanGestureRecognizer, UIGestureRecognizerDelegate
{


    let markers = NSHashTable<BoardCardSwipeZone.Marker>.weakObjects()
    weak var board: UIScrollView?


    ///
    /// @fcn        BoardCardSwipeGate.touchesBegan(_:with:)
    /// @brief      Choose the Card's swipe region at the beginning of a touch
    /// @details    Fails immediately outside enabled right-quarter markers, leaving native Delete
    ///             gestures unaffected elsewhere. Accepted touches still require leftward intent.
    ///
    /// @param[in]  touches  New native touches
    /// @param[in]  event    Native touch event
    ///
    /// @return     (Void) establishes whether the gesture may reserve Board navigation
    ///
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent)
    {

        super.touchesBegan(touches, with: event)
        guard let touch = touches.first,
        markers.allObjects.contains(where:
            {
                marker in
                marker.isEnabled && marker.window != nil
                && BoardCardSwipeRouting.routesToBoard(
                    start: touch.location(in: marker), bounds: marker.bounds)
            })
        else
        {
            state = .failed;
            return
        }

    }


    ///
    /// @fcn        BoardCardSwipeGate.gestureRecognizerShouldBegin(_:)
    /// @brief      Reserve only predominantly leftward horizontal movement
    /// @details    Vertical scrolling and rightward swipes keep their existing native behavior.
    ///
    /// @param[in]  gestureRecognizer  Gate whose movement is being evaluated
    ///
    /// @return     (Bool) true when the gesture is a left swipe
    ///
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    {

        let velocity = velocity(in: view)
        return velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
    }


    ///
    /// @fcn        BoardCardSwipeGate.gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)
    /// @brief      Allow the Board to scroll while its Delete-blocking gate is active
    /// @details    The gate never translates content itself or replaces a UIKit delegate.
    ///
    /// @param[in]  gestureRecognizer       This gate
    /// @param[in]  otherGestureRecognizer  Potential simultaneous recognizer
    ///
    /// @return     (Bool) true only for the enclosing Board pan
    ///
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool
    {

        otherGestureRecognizer === board?.panGestureRecognizer
    }


    ///
    /// @fcn        BoardCardSwipeGate.install(marker:)
    /// @brief      Attach one shared routing gate to an embedded native List
    /// @details    Requires a horizontal Board ancestor. Single List and Day views receive no gate.
    ///             Native row-action pans wait for it; Board paging may run simultaneously with it.
    ///
    /// @param[in]  marker  Card preview's geometry marker
    ///
    /// @return     (Void) registers geometry without changing native gesture delegates
    ///
    static func install(marker: BoardCardSwipeZone.Marker)
    {

        guard marker.window != nil else
        {
            return
        }

        var ancestor = marker.superview
        var list: UIScrollView?
        while let view = ancestor
        {

            if let scroll = view as? UIScrollView, scroll is UICollectionView || scroll is UITableView
            {

                list = scroll;
                break
            }

            ancestor = view.superview
        }

        guard let list else
        {
            return
        }

        ancestor = list.superview
        while let view = ancestor
        {

            if let board = view as? UIScrollView,
            board.alwaysBounceHorizontal || board.contentSize.width > board.bounds.width + 1
            {

                let gate: BoardCardSwipeGate
                if let existing = list.gestureRecognizers?.compactMap(
                    {
                        $0 as? BoardCardSwipeGate
                    }).first
                {

                    gate = existing
                }
                else
                {

                    gate = BoardCardSwipeGate(target: nil, action: nil)
                    gate.delegate = gate
                    gate.cancelsTouchesInView = false
                    gate.delaysTouchesBegan = false
                    gate.maximumNumberOfTouches = 1
                    gate.board = board
                    list.addGestureRecognizer(gate)
                }

                gate.board = board
                gate.markers.add(marker)
                for gesture in list.gestureRecognizers ?? []
                where gesture is UIPanGestureRecognizer
                && gesture !== list.panGestureRecognizer && gesture !== gate
                {

                    gesture.require(toFail: gate)
                }

                BoardListSwipePriority.install(for: list)
                return
            }

            ancestor = view.superview
        }

    }

}


///
/// Marks Card geometry for Board-only swipe routing
///
/// @section    Purpose
///     Installs the native routing gate after mounting and disables participation when the row's
///     editing context requires it.
///
struct BoardCardSwipeZone: UIViewRepresentable
{


    var enabled = true


    ///
    /// Marks a Board Card's native swipe-routing region
    ///
    /// @section    Purpose
    ///     Registers after window attachment and retains whether this row currently participates in
    ///     the Board's gesture split.
    ///
    final class Marker: UIView
    {


        var isEnabled = true


        ///
        /// @fcn        BoardCardSwipeZone.Marker.didMoveToWindow()
        /// @brief      Register the Card region after its native List hierarchy is mounted
        /// @details    Defers discovery so enclosing scroll views have completed their layout.
        ///
        /// @return     (Void) schedules native routing setup
        ///
        override func didMoveToWindow()
        {

            super.didMoveToWindow()
            DispatchQueue.main.async
            {
                [weak self] in
                if let self
                {
                    BoardCardSwipeGate.install(marker: self)
                }

            }

        }

    }


    ///
    /// @fcn        BoardCardSwipeZone.makeUIView(context:)
    /// @brief      Create a transparent noninteractive Card geometry marker
    /// @details    The enclosing List receives touches; this view only supplies the Card bounds.
    ///
    /// @param[in]  context  SwiftUI bridge context
    ///
    /// @return     (Marker) native geometry marker
    ///
    func makeUIView(context: Context) -> Marker
    {

        let marker = Marker()
        marker.isUserInteractionEnabled = false
        marker.isEnabled = enabled
        return marker
    }


    ///
    /// @fcn        BoardCardSwipeZone.updateUIView(_:context:)
    /// @brief      Refresh Edit-mode eligibility and native routing registration
    /// @details    Weak marker registration avoids retaining removed or recycled Card rows.
    ///
    /// @param[in]  marker   Existing Card marker
    /// @param[in]  context  SwiftUI bridge context
    ///
    /// @return     (Void) updates routing without intercepting taps or long presses
    ///
    func updateUIView(_ marker: Marker, context: Context)
    {

        marker.isEnabled = enabled
        DispatchQueue.main.async
        {
            [weak marker] in
            if let marker
            {
                BoardCardSwipeGate.install(marker: marker)
            }

        }

    }

}


///
/// Reports card frames for same-Board insertion boundaries
///
/// @section    Purpose
///     Locate visible card rows without copying their content into a drag payload
///
struct BoardCardFramePreferenceKey: PreferenceKey
{


    static var defaultValue: [Int: CGRect] = [:] /* Empty card-frame measurements before layout */


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
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect])
    {


        value.merge(nextValue(), uniquingKeysWith:
            {
                _, latest in
                latest
            })
    }

}


///
/// Collects the measured frames of visible Board list panels
///
/// @section    Purpose
///     Make list geometry available to Board-level drop-target hit testing
///
struct BoardListFramePreferenceKey: PreferenceKey
{


    static var defaultValue: [Int: CGRect] = [:] /* Empty list-frame measurements before layout */


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
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect])
    {


        value.merge(nextValue(), uniquingKeysWith:
            {
                _, latest in
                latest
            })
    }

}


///
/// Bridges native whole-Card dragging to owner movement
///
/// @section    Purpose
///     Installs drag interaction on the row content container, excludes marked importance controls,
///     and tracks cancellation separately from List reordering.
///
struct BoardCardDragSource: UIViewRepresentable
{


    static let contentType = UTType(
        exportedAs: "com.plenact.local-board-card", conformingTo: .data)  /* Private transfer type for local Board card drags      */
    let token:     String                                                 /* Board-session token carried by each drag item         */
    let onBegan:   (CGPoint) -> Void                                      /* Reports the initial global card-drag position         */
    let onChanged: (CGPoint) -> Void                                      /* Reports subsequent global card-drag positions         */
    let onEnded:   () -> Void                                             /* Clears parent state when the native drag session ends */


    ///
    /// Provides a UIKit view lifecycle hook for locating the enclosing card cell
    ///
    /// @section    Purpose
    ///     Install the native drag interaction only after the probe is attached to a window
    ///
    final class Probe: UIView
    {


        weak var coordinator: Coordinator? /* Drag owner notified when the probe attaches or detaches */


        ///
        /// @fcn        BoardCardDragSource.Probe.didMoveToWindow()
        /// @brief      Install the card drag source after the probe enters a window
        /// @details    Calls the superclass lifecycle hook, then asks the coordinator to locate the
        ///             enclosing card cell.
        ///
        /// @return     (Void) attempts native interaction installation
        ///
        override func didMoveToWindow()
        {


            super.didMoveToWindow()
            coordinator?.install(from: self)
        }

    }


    ///
    /// Coordinates the native drag interaction associated with one card-row container
    ///
    /// @section    Purpose
    ///     Own drag delegate state and forward location changes to the SwiftUI source callbacks
    ///
    final class Coordinator: NSObject, UIDragInteractionDelegate
    {


        var source:         BoardCardDragSource  /* Current parent callbacks and transfer token         */
        weak var container: UIView?              /* Collection cell hosting the native drag interaction */
        var interaction:    UIDragInteraction?   /* Native interaction retained through an active drag  */
        private(set) var isDragging = false      /* Whether a native drag session is in progress        */
        var isDetached = false                   /* Whether SwiftUI has dismantled the source probe     */


        ///
        /// @fcn        BoardCardDragSource.Coordinator.init(_:)
        /// @brief      Create a drag coordinator for one SwiftUI drag source
        /// @details    Retains the source callbacks used by the native interaction while leaving
        ///             container and interaction discovery to the later probe lifecycle hook
        ///
        /// @param[in]  source  SwiftUI drag source whose token and callbacks are coordinated
        ///
        /// @return     (BoardCardDragSource.Coordinator) initialized delegate coordinator
        ///
        init(_ source: BoardCardDragSource)
        {


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
        func install(from probe: UIView)
        {


            guard probe.window != nil else
            {


                return
            }


            var ancestor = probe.superview /* Next ancestor inspected for a hosting collection cell */

            while let view = ancestor
            {  /* Current ancestor in the collection-cell search */


                if let cell = view as? UICollectionViewCell
                {  /* Cell selected to host the native drag interaction */


                    guard container !== cell.contentView else
                    {


                        return
                    }


                    if let interaction
                    {  /* Previous drag interaction removed before reattachment */


                        container?.removeInteraction(interaction)
                    }


                    let drag = UIDragInteraction(
                        delegate: self) /* Native drag interaction installed on the hosting cell */

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
        func begin(at point: CGPoint) -> NSItemProvider
        {


            isDragging = true
            source.onBegan(point)

            let provider = NSItemProvider() /* Transfer provider advertising the local card token */

            provider.suggestedName = source.token

            let data = Data(source.token.utf8) /* UTF-8 payload identifying this Board drag session */

            provider.registerDataRepresentation(
                forTypeIdentifier: BoardCardDragSource.contentType.identifier,
                visibility: .ownProcess
            )
            {
                completion in
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
        func finish()
        {


            guard isDragging else
            {


                return
            }


            isDragging = false
            source.onEnded()

            if isDetached, let interaction
            {  /* Retained drag interaction removed after detached-session completion */


                container?.removeInteraction(interaction)
            }

        }


        ///
        /// @fcn        BoardCardDragSource.Coordinator.canBegin(at:in:)
        /// @brief      Reserve importance controls for their own tap-and-hold action
        /// @details    Declines a native lift before creating drag state or a payload when the
        ///             session starts on a star. The rest of the Card remains draggable.
        ///
        /// @param[in]  point            Initial native drag-session point
        /// @param[in]  coordinateSpace  View supplying that point's coordinates
        ///
        /// @return     (Bool) true for a mounted Card area outside importance controls
        ///
        func canBegin(at point: CGPoint, in coordinateSpace: UIView) -> Bool
        {

            guard let container else
            {
                return false
            }

            return !ImportanceInteractionRegion.contains(point, from: coordinateSpace, in: container)
        }


        ///
        /// @fcn        BoardCardDragSource.Coordinator.dragInteraction(_:itemsForBeginning:)
        /// @brief      Create a native drag item for an attached card source
        /// @details    Requires the interaction window and a start outside importance controls,
        ///             then begins the token-only session and retains the coordinator in localObject.
        ///
        /// @param[in]  interaction  Native interaction delivering this delegate callback
        /// @param[in]  session      Native drag or drop session delivering the callback
        ///
        /// @return     ([UIDragItem]) local drag item, or empty without a window or over an importance control
        ///
        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem]
        {


            guard let window = interaction.view?.window else
            {  /* Window defining the global drag-coordinate space */


                return []
            }


            let point = session.location(in: window)
            guard canBegin(at: point, in: window) else
            {
                return []
            }

            let item = UIDragItem(itemProvider: begin(at: point)) /* Native drag item carrying local source identity */

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
        func dragInteraction(_ interaction: UIDragInteraction, sessionDidMove session: UIDragSession)
        {


            guard let window = interaction.view?.window else
            {  /* Window used to report the current drag position */


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
        func dragInteraction(
            _ interaction: UIDragInteraction, session: UIDragSession,
            didEndWith operation: UIDropOperation
        )
        {


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
        func dragInteraction(
            _ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession
        ) -> Bool
        {


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
        func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession)
        -> Bool
        {


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
    func makeCoordinator() -> Coordinator
    {


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
    func makeUIView(context: Context) -> Probe
    {


        let probe = Probe() /* Lightweight UIKit anchor for attaching the drag interaction */

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
    func updateUIView(_ probe: Probe, context: Context)
    {


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
    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator)
    {


        // A live native session may outlast the source cell while the Board scrolls.
        coordinator.isDetached = true

        if !coordinator.isDragging, let interaction = coordinator.interaction
        {  /* Idle drag interaction safe to remove during dismantling */


            coordinator.container?.removeInteraction(interaction)
        }

    }

}


///
/// Hosts a native drop interaction over a Board list while preserving the collection view's
/// original drop delegate when the custom surface is disabled
///
/// @section    Purpose
///     Forward native drop locations to Board card movement without changing list reordering
///
struct BoardCardDropSurface: UIViewRepresentable
{


    let token: String                 /* Board-session token required for local drop acceptance      */
    var isEnabled = true              /* Whether this surface currently accepts card drops           */
    let onChanged: (CGPoint) -> Void  /* Reports the global pointer position during an accepted drop */
    let onDrop:    (CGPoint) -> Bool  /* Commits a drop at the reported global pointer position      */


    ///
    /// Retains the drop interaction together with the coordinator that serves as its delegate
    ///
    /// @section    Purpose
    ///     Keep native drop delegation alive for the lifetime of its list collection
    ///
    final class RetainedInteraction: UIDropInteraction
    {


        let receiver: Coordinator /* Strong delegate owner retained by the native drop interaction */


        ///
        /// @fcn        BoardCardDropSurface.RetainedInteraction.init(receiver:)
        /// @brief      Initialize a retained drop interaction with its delegate coordinator
        /// @details    Stores the receiver strongly because the interaction must retain the
        ///             delegate for its full attachment lifetime
        ///
        /// @param[in]  receiver  Coordinator that handles this native drop interaction
        ///
        /// @return     (BoardCardDropSurface.RetainedInteraction) configured interaction
        ///
        init(receiver: Coordinator)
        {


            self.receiver = receiver
            super.init(delegate: receiver)
        }

    }


    ///
    /// Provides a UIKit view lifecycle hook for locating the enclosing list collection
    ///
    /// @section    Purpose
    ///     Install or update the native drop receiver after the probe enters a window
    ///
    final class Probe: UIView
    {


        weak var coordinator: Coordinator? /* Drop owner notified when the probe moves between containers */


        ///
        /// @fcn        BoardCardDropSurface.Probe.didMoveToWindow()
        /// @brief      Install the list drop receiver after the probe enters a window
        /// @details    Calls the superclass lifecycle hook, then asks the coordinator to locate the
        ///             enclosing collection view.
        ///
        /// @return     (Void) attempts native receiver installation
        ///
        override func didMoveToWindow()
        {


            super.didMoveToWindow()
            coordinator?.install(from: self)
        }

    }


    ///
    /// Coordinates the drop receiver and collection-view delegate handoff for one list
    ///
    /// @section    Purpose
    ///     Route native drop callbacks to SwiftUI while restoring the original delegate when needed
    ///
    final class Coordinator: NSObject, UIDropInteractionDelegate, UICollectionViewDropDelegate
    {


        var surface:          BoardCardDropSurface  /* Current acceptance settings and parent drop callbacks */
        weak var container:   UICollectionView?     /* Collection view hosting drop handling                 */
        weak var interaction: UIDropInteraction?    /* Installed or reused native drop interaction           */
        weak var originalDropDelegate:
        (any UICollectionViewDropDelegate)? /* Prior collection delegate restored on detachment      */


        ///
        /// @fcn        BoardCardDropSurface.Coordinator.init(_:)
        /// @brief      Create a drop coordinator for one SwiftUI drop surface
        /// @details    Retains the surface callbacks and initial enabled state for installation on
        ///             the matching native list collection
        ///
        /// @param[in]  surface  SwiftUI drop surface whose token and callbacks are coordinated
        ///
        /// @return     (BoardCardDropSurface.Coordinator) initialized delegate coordinator
        ///
        init(_ surface: BoardCardDropSurface)
        {


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
        func install(from probe: UIView)
        {


            guard probe.window != nil else
            {


                return
            }


            var ancestor = probe.superview /* Next ancestor inspected for the hosting collection view */

            while let view = ancestor
            {  /* Current ancestor in the collection-view search */


                if let collection = view as? UICollectionView
                {  /* Collection surface selected for native drop handling */


                    if let existing = collection.interactions.compactMap(
                        {  /* Existing Board drop interaction reused on the collection */


                            $0 as? RetainedInteraction
                        }).first
                    {

                        existing.receiver.surface = surface
                        collection.dropDelegate =
                        surface.isEnabled ? existing.receiver : existing.receiver.originalDropDelegate
                        container = collection
                        interaction = existing

                        return
                    }


                    guard container !== collection else
                    {


                        return
                    }


                    let drop = RetainedInteraction(
                        receiver: self) /* New drop interaction retaining its delegate owner */

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
        func accepts(_ items: [UIDragItem]) -> Bool
        {


            surface.isEnabled && items.count == 1
            && items.allSatisfy
            {

                guard let source = $0.localObject as? BoardCardDragSource.Coordinator
                else
                {  /* Local card-drag owner used to validate Board provenance */


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
        func perform(_ items: [UIDragItem], at point: CGPoint) -> Bool
        {


            guard accepts(items) else
            {


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
        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool
        {


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
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession)
        -> UIDropProposal
        {


            guard accepts(session.items), let window = interaction.view?.window
            else
            {  /* Window used to report accepted drag-over coordinates */


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
        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession)
        {


            guard let window = interaction.view?.window else
            {  /* Window used to resolve the committed drop point */


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
        func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool
        {


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
        func collectionView(
            _ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
            withDestinationIndexPath destinationIndexPath: IndexPath?
        ) -> UICollectionViewDropProposal
        {


            guard accepts(session.items), let window = collectionView.window
            else
            {  /* Collection window defining drag-over coordinates */


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
        func collectionView(
            _ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator
        )
        {


            guard let window = collectionView.window else
            {  /* Collection window defining the final drop coordinates */


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
    func makeCoordinator() -> Coordinator
    {


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
    func makeUIView(context: Context) -> Probe
    {


        let probe = Probe() /* Lightweight UIKit anchor for discovering the drop collection */

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
    func updateUIView(_ probe: Probe, context: Context)
    {


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
    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator)
    {


    // The list retains its one receiver while individual rows are virtualized.

    }

}


///
/// Collects horizontal center measurements for Board lists
///
/// @section    Purpose
///     Identify the list nearest the visible viewport center
///
struct BoardListCenterPreferenceKey: PreferenceKey
{


    /// Current list-center reports keyed by list identity.
    static var defaultValue: [Int: CGFloat] = [:] /* Empty card-height measurements before layout */


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
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat])
    {


        value.merge(nextValue(), uniquingKeysWith:
            {
                _, latest in
                latest
            })
    }

}
