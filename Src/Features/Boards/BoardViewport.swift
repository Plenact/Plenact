// --------------------------------------------------------------------------------------------------
// @file       BoardViewport.swift
// @brief      Board sizing, zoom, and retained scroll position
// @details    Keeps per-owner viewport preferences separate from content and bridges native scroll
//             observation and restoration.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Resolves zoom geometry for panoramic Board presentation
///
/// @section    Purpose
///     Supplies bounded zoom presets and related layout calculations separately from Card metadata
///     visibility settings.
///
enum BoardPanoramicZoom
{


    static let initial: CGFloat = 0.62


    ///
    /// @fcn        BoardPanoramicZoom.preset
    /// @brief      Choose the initial zoom for the selected board mode
    /// @details    Panoramic mode uses the overview scale; standard mode starts at a scale of one.
    ///
    /// @param[in]  panoramic  Whether the board is using its panoramic overview
    ///
    /// @return     (CGFloat) panoramic initial scale or one for standard mode
    ///
    static func preset(panoramic: Bool) -> CGFloat
    {
        panoramic ? initial : 1
    }

    static let minimum: CGFloat = 0.25
    static let maximum: CGFloat = 1.25


    ///
    /// @fcn        BoardPanoramicZoom.clamped
    /// @brief      Constrain a board zoom scale to supported bounds
    /// @details    Nonfinite input falls back to the initial scale; finite input is limited to the minimum and
    ///             maximum.
    ///
    /// @param[in]  scale  Proposed board magnification factor
    ///
    /// @return     (CGFloat) finite scale constrained to the supported minimum and maximum
    ///
    static func clamped(_ scale: CGFloat) -> CGFloat
    {

        guard scale.isFinite else
        {
            return initial
        }

        return min(maximum, max(minimum, scale))
    }


    ///
    /// @fcn        BoardPanoramicZoom.scale
    /// @brief      Apply a pinch magnification to the starting zoom
    /// @details    Invalid or nonpositive magnification preserves the clamped starting scale instead of propagating
    ///             an invalid value.
    ///
    /// @param[in]  start          Starting horizontal position or original vertical scroll offset in points
    /// @param[in]  magnification  Relative pinch multiplier applied to the starting scale
    ///
    /// @return     (CGFloat) clamped starting scale multiplied by a valid pinch magnification
    ///
    static func scale(start: CGFloat, magnification: CGFloat) -> CGFloat
    {

        guard magnification.isFinite, magnification > 0 else
        {
            return clamped(start)
        }

        return clamped(start * magnification)
    }

}


///
/// Resolves proportional Board sizing on tablets
///
/// @section    Purpose
///     Scales the complete standard List, including its typography and Cards, to retain the
///     intended phone-like proportions.
///
enum BoardTabletSizing
{


    ///
    /// @fcn        BoardTabletSizing.scale
    /// @brief      Calculate the optional tablet enlargement factor
    /// @details    Requires an enabled tablet layout and valid column width; otherwise returns one. The enlarged
    ///             baseline includes a ten percent reduction.
    ///
    /// @param[in]  viewportWidth  Available board viewport width in points
    /// @param[in]  columnWidth    Unscaled list-column width in points
    /// @param[in]  isTablet       Whether the current device uses the tablet layout
    /// @param[in]  enabled        Whether this optional behavior is enabled
    ///
    /// @return     (CGFloat) tablet enlargement factor of at least one, or one when enlargement is unavailable
    ///
    static func scale(viewportWidth: CGFloat, columnWidth: CGFloat, isTablet: Bool, enabled: Bool) -> CGFloat
    {

        guard isTablet, enabled, viewportWidth.isFinite, columnWidth.isFinite, columnWidth > 0 else
        {
            return 1
        }

        // Ease back ten percent from the near-full-width tablet baseline.
        return max(1, 0.9 * (viewportWidth - 30) / (columnWidth + 34))
    }

}


///
/// Retains presentation-only viewport positions
///
/// @section    Purpose
///     Keeps owner-specific horizontal and vertical scroll values out of the user's
///     planning-content snapshots.
///
struct BoardViewportState: Codable, Equatable
{


    var scale: Double = 1
    var panoramic = false
    var gallery = false
    var presentation:  String? = nil
    var visibleListID: Int? = nil
    var offsets:       [String: Double] = [:]
}


///
/// Retains per-owner Board viewport preferences
///
/// @section    Purpose
///     Tracks horizontal and vertical positions separately from planning content and debounces
///     writes to the supplied preferences store.
///
@MainActor
final class BoardViewportMemory
{


    static let prefix = "Plenact.BoardViewport.v1."
    let key:                 String
    private let defaults:    UserDefaults
    var state:               BoardViewportState
    private var pendingSave: DispatchWorkItem?
    var horizontalRestoreAllowed = true


    ///
    /// @fcn        BoardViewportMemory.init
    /// @brief      Restore viewport memory for a particular owner
    /// @details    Decodes saved state or uses defaults, clamps the zoom scale, and discards negative or nonfinite
    ///             offsets.
    ///
    /// @param[in]  owner     Owner identity used to qualify numeric item references
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (BoardViewportMemory) initialized instance
    ///
    init(owner: String, defaults: UserDefaults = .standard)
    {

        key = Self.prefix + owner
        self.defaults = defaults
        state =
        defaults.data(forKey: key).flatMap
        {
            try? JSONDecoder().decode(BoardViewportState.self, from: $0)
        }

        ?? BoardViewportState()
        state.scale = state.scale.isFinite ? Double(BoardPanoramicZoom.clamped(CGFloat(state.scale))) : 1
        state.offsets = state.offsets.filter
        {
            $0.value.isFinite && $0.value >= 0
        }

    }


    ///
    /// @fcn        BoardViewportMemory.record
    /// @brief      Record a normalized scroll offset
    /// @details    Rejects nonfinite input, clamps negative offsets to zero, and schedules a debounced save.
    ///
    /// @param[in]  offset  Relative section or photo movement, or normalized scroll displacement
    /// @param[in]  key     Storage key or stable lookup key used by this operation
    ///
    /// @return     (Void) no return value
    ///
    func record(_ offset: Double, for key: String)
    {

        guard offset.isFinite else
        {
            return
        }

        state.offsets[key] = max(0, offset)
        scheduleSave()
    }


    ///
    /// @fcn        BoardViewportMemory.scheduleSave
    /// @brief      Debounce persistence of viewport changes
    /// @details    Cancels the previous work item and schedules a weakly captured flush on the main queue after 0.35
    ///             seconds.
    ///
    /// @return     (Void) no return value
    ///
    func scheduleSave()
    {

        pendingSave?.cancel()
        let work = DispatchWorkItem
        {
            [weak self] in
            self?.flush()
        }

        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }


    ///
    /// @fcn        BoardViewportMemory.flush
    /// @brief      Persist changed viewport state immediately
    /// @details    Cancels pending work, encodes the state, and avoids rewriting identical stored data.
    ///
    /// @return     (Void) no return value
    ///
    func flush()
    {

        pendingSave?.cancel();
        pendingSave = nil
        guard let data = try? JSONEncoder().encode(state), defaults.data(forKey: key) != data else
        {
            return
        }

        defaults.set(data, forKey: key)
    }

}


///
/// Defines optional Board viewport memory in the environment
///
/// @section    Purpose
///     Defaults to no memory so standalone views do not save positions into an unrelated owner's
///     preference key.
///
struct BoardViewportMemoryKey: EnvironmentKey
{


    static let defaultValue: BoardViewportMemory? = nil
}


///
/// Exposes owner-specific viewport memory to descendants
///
/// @section    Purpose
///     Lets native scroll probes restore and retain position without passing storage ownership
///     through every view initializer.
///
extension EnvironmentValues
{


    var boardViewportMemory: BoardViewportMemory?
    {

        get
        {
            self[BoardViewportMemoryKey.self]
        }

        set
        {
            self[BoardViewportMemoryKey.self] = newValue
        }

    }

}


///
/// Bridges native scroll position to Board viewport memory
///
/// @section    Purpose
///     Discovers the relevant scroll view and delegates observation and restoration to a retained
///     coordinator.
///
struct BoardViewportScrollProbe: UIViewRepresentable
{


    let memory: BoardViewportMemory?
    let key:    String
    var horizontal = false


    ///
    /// Notifies the viewport probe after native attachment
    ///
    /// @section    Purpose
    ///     Invokes its attachment callback only once a window exists so scroll-ancestor discovery
    ///     has a mounted hierarchy.
    ///
    final class Marker: UIView
    {


        var attached: (() -> Void)?


        ///
        /// @fcn        BoardViewportScrollProbe.Marker.didMoveToWindow
        /// @brief      Notify the probe when its marker becomes attached
        /// @details    Calls the superclass implementation and invokes the attachment callback only when a window
        ///             exists.
        ///
        /// @return     (Void) no return value
        ///
        override func didMoveToWindow()
        {
            super.didMoveToWindow();
            if window != nil
            {
                attached?()
            }

        }

    }


    ///
    /// @fcn        BoardViewportScrollProbe.makeCoordinator
    /// @brief      Create the native bridge coordinator
    /// @details    Creates the coordinator retained by SwiftUI for BoardViewportScrollProbe so its delegate or
    ///             observation state can span view updates.
    ///
    /// @return     (Coordinator) retained native bridge coordinator
    ///
    func makeCoordinator() -> Coordinator
    {
        Coordinator()
    }


    ///
    /// @fcn        BoardViewportScrollProbe.makeUIView
    /// @brief      Create a noninteractive marker for native scroll discovery
    /// @details    Configures the coordinator and uses weak references in the marker's window attachment callback.
    ///
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (Marker) noninteractive marker that triggers native scroll-view discovery after attachment
    ///
    func makeUIView(context: Context) -> Marker
    {

        let view = Marker();
        view.isUserInteractionEnabled = false
        context.coordinator.configure(memory: memory, key: key, horizontal: horizontal)
        view.attached =
        {
            [weak view, weak coordinator = context.coordinator] in
            if let view
            {
                coordinator?.findScroll(from: view)
            }

        }

        return view
    }


    ///
    /// @fcn        BoardViewportScrollProbe.updateUIView
    /// @brief      Refresh the viewport probe's owner and scroll axis
    /// @details    Reconfigures the coordinator and attempts native scroll discovery once the marker is attached to a
    ///             window.
    ///
    /// @param[in]  view     Native view inspected or synchronized by the operation
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (Void) no return value
    ///
    func updateUIView(_ view: Marker, context: Context)
    {

        context.coordinator.configure(memory: memory, key: key, horizontal: horizontal)
        if view.window != nil
        {
            context.coordinator.findScroll(from: view)
        }

    }


    ///
    /// @fcn        BoardViewportScrollProbe.dismantleUIView
    /// @brief      Finish observing a departing native scroll view
    /// @details    Captures the final offset, invalidates observation, and flushes viewport memory through the
    ///             coordinator.
    ///
    /// @param[in]  view         Native view inspected or synchronized by the operation
    /// @param[in]  coordinator  Coordinator retaining the native bridge's observation or delegate state
    ///
    /// @return     (Void) no return value
    ///
    static func dismantleUIView(_ view: Marker, coordinator: Coordinator)
    {
        coordinator.finish()
    }


    ///
    /// Observes and restores one native Board scroll view
    ///
    /// @section    Purpose
    ///     Retains the viewport key and restoration target, observes offsets, and bounds discovery
    ///     retries without publishing per-frame SwiftUI state.
    ///
    @MainActor
    final class Coordinator
    {


        private var memory: BoardViewportMemory?
        private var key = ""
        private var horizontal = false
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var restored = false
        private var desired: Double?
        private var attempts = 0
        private var finding = false


        ///
        /// @fcn        BoardViewportScrollProbe.Coordinator.configure
        /// @brief      Switch the probe to a new viewport memory key
        /// @details    Finishes the previous observation before resetting the desired offset, restoration flag, and
        ///             discovery attempts.
        ///
        /// @param[in]  memory      Optional owner-scoped viewport state and persistence object
        /// @param[in]  key         Storage key or stable lookup key used by this operation
        /// @param[in]  horizontal  Whether the probe observes the horizontal rather than vertical axis
        ///
        /// @return     (Void) no return value
        ///
        func configure(memory: BoardViewportMemory?, key: String, horizontal: Bool)
        {

            guard self.memory !== memory || self.key != key else
            {
                return
            }

            finish()
            self.memory = memory;
            self.key = key;
            self.horizontal = horizontal
            desired = memory?.state.offsets[key]
            restored = false;
            attempts = 0
        }


        ///
        /// @fcn        BoardViewportScrollProbe.Coordinator.matches
        /// @brief      Check whether a native scroll view serves the requested axis
        /// @details    Horizontal probes require horizontal scrolling; vertical probes also recognize table and
        ///             collection views.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (Bool) true if the native scroll view is suitable for the probe's requested axis
        ///
        private func matches(_ view: UIScrollView) -> Bool
        {

            if horizontal
            {
                return view.alwaysBounceHorizontal || view.contentSize.width > view.bounds.width + 1
            }

            return view is UICollectionView || view is UITableView || view.alwaysBounceVertical
            || view.contentSize.height > view.bounds.height + 1
        }


        ///
        /// @fcn        BoardViewportScrollProbe.Coordinator.descendant
        /// @brief      Find the first suitable scroll view below a container
        /// @details    Searches descendants recursively and returns nil when no matching native scroller is present.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (UIScrollView?) first matching descendant scroller, or nil when none exists
        ///
        private func descendant(in view: UIView) -> UIScrollView?
        {

            for child in view.subviews
            {

                if let scroll = child as? UIScrollView
                {

                    if matches(scroll)
                    {
                        return scroll
                    }

                }
                else if let found = descendant(in: child)
                {

                    return found
                }

            }

            return nil
        }


        ///
        /// @fcn        BoardViewportScrollProbe.Coordinator.findScroll
        /// @brief      Locate the native scroller associated with the marker
        /// @details    Defers hierarchy inspection to the main queue, bounds discovery retries, and refreshes
        ///             inner-list swipe priority for an attached scroller.
        ///
        /// @param[in]  marker  Attached marker used to locate the enclosing native scroll view
        ///
        /// @return     (Void) no return value
        ///
        func findScroll(from marker: UIView)
        {

            if let scroll
            {

                // SwiftUI may install row actions after the first empty List layout.
                if !horizontal
                {
                    BoardListSwipePriority.install(for: scroll)
                }

                return
            }

            guard memory != nil, !finding, attempts < 16 else
            {
                return
            }

            finding = true
            DispatchQueue.main.async
            {
                [weak self, weak marker] in
                guard let self else
                {
                    return
                }

                self.finding = false
                guard let marker, marker.window != nil else
                {
                    return
                }

                self.attempts += 1
                var parent = marker.superview
                for _ in 0 ..< 10
                {

                    guard let view = parent else
                    {
                        break
                    }

                    if let native = view as? UIScrollView
                    {

                        if self.matches(native)
                        {
                            self.attach(native);
                            return
                        }

                        break  // Never pick a different column beyond the enclosing Board scroll.
                    }

                    if let native = self.descendant(in: view)
                    {
                        self.attach(native);
                        return
                    }

                    parent = view.superview
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05)
                {
                    [weak self, weak marker] in
                    if let marker
                    {
                        self?.findScroll(from: marker)
                    }

                }

            }

        }


        ///
        /// @fcn        BoardViewportScrollProbe.Coordinator.attach
        /// @brief      Observe a discovered native scroll view
        /// @details    Retains its content-offset observation and schedules restoration after the current layout
        ///             pass.
        ///
        /// @param[in]  scroll  Native scroll view to observe or restore
        ///
        /// @return     (Void) no return value
        ///
        private func attach(_ scroll: UIScrollView)
        {

            self.scroll = scroll
            observation = scroll.observe(\.contentOffset, options: [.new])
            {
                [weak self] _, _ in
                MainActor.assumeIsolated
                {
                    self?.capture()
                }

            }

            DispatchQueue.main.async
            {
                [weak self] in
                self?.restore()
            }

        }


        ///
        /// @fcn        BoardViewportScrollProbe.Coordinator.restore
        /// @brief      Restore the saved offset within the laid-out content bounds
        /// @details    Accounts for adjusted insets and the selected axis, respects disabled horizontal restoration
        ///             and active dragging, then enables offset capture.
        ///
        /// @return     (Void) no return value
        ///
        private func restore()
        {

            guard let scroll else
            {
                return
            }

            scroll.layoutIfNeeded()
            if !horizontal
            {
                BoardListSwipePriority.install(for: scroll)
            }

            if let desired, !(horizontal && memory?.horizontalRestoreAllowed == false), !scroll.isDragging
            {

                let inset = horizontal ? scroll.adjustedContentInset.left : scroll.adjustedContentInset.top
                let endInset = horizontal ? scroll.adjustedContentInset.right : scroll.adjustedContentInset.bottom
                let content = horizontal ? scroll.contentSize.width : scroll.contentSize.height
                let length = horizontal ? scroll.bounds.width : scroll.bounds.height
                let value = min(CGFloat(desired), max(0, content - length + inset + endInset)) - inset
                var point = scroll.contentOffset
                if horizontal
                {
                    point.x = value
                }
                else
                {
                    point.y = value
                }

                scroll.setContentOffset(point, animated: false)
            }

            restored = true
        }


        ///
        /// @fcn        BoardViewportScrollProbe.Coordinator.capture
        /// @brief      Capture the current inset-normalized scroll position
        /// @details    Records offsets only after restoration and while both the native scroll view and viewport
        ///             memory remain available.
        ///
        /// @return     (Void) no return value
        ///
        private func capture()
        {

            guard restored, let scroll, let memory else
            {
                return
            }

            let offset =
            horizontal
            ? scroll.contentOffset.x + scroll.adjustedContentInset.left
            : scroll.contentOffset.y + scroll.adjustedContentInset.top
            memory.record(Double(offset), for: key)
        }


        ///
        /// @fcn        BoardViewportScrollProbe.Coordinator.finish
        /// @brief      Release scroll observation and save the last viewport
        /// @details    Captures before invalidating observation, clears the native scroller reference, and flushes
        ///             memory.
        ///
        /// @return     (Void) no return value
        ///
        func finish()
        {

            capture();
            observation?.invalidate();
            observation = nil;
            scroll = nil
            memory?.flush()
        }

    }

}


///
/// Caches current drag hit-test geometry
///
/// @section    Purpose
///     Retains fresh Board measurements without forcing a SwiftUI Board redraw for every passive
///     scroll update.
///
final class BoardDragGeometryCache
{


    var centers:  [Int: CGFloat] = [:]
    var cards:    [Int: CGRect] = [:]
    var lists:    [Int: CGRect] = [:]
    var viewport: CGRect = .zero
}


///
/// Displays a temporary Board zoom hint
///
/// @section    Purpose
///     Shows the current percentage as noninteractive decoration and respects Reduce Motion when
///     removing the hint.
///
struct BoardZoomHint: View
{


    let percentage: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    var body: some View
    {

        Text("Pinch to zoom · \(percentage)%")
        .font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false).accessibilityHidden(true)
        .task
        {

            visible = true
            do
            {

                try await Task.sleep(for: .seconds(3))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7))
                {
                    visible = false
                }

            }
            catch
            {  /* Leaving the board cancels the hint timer. */

            }

        }

    }

}


///
/// Retains in-progress Board pinch state
///
/// @section    Purpose
///     Separates transient magnification and gesture activity from the committed zoom preference.
///
struct BoardPinchState
{


    var magnification: CGFloat = 1
    var active = false
}


///
/// Adapts Board scroll snapping to the zoom presentation
///
/// @section    Purpose
///     Uses view-aligned column snapping in standard mode and leaves panoramic scroll targets free.
///
struct BoardZoomScrollBehavior: ScrollTargetBehavior
{


    let panoramic: Bool


    ///
    /// @fcn        BoardZoomScrollBehavior.updateTarget
    /// @brief      Apply column snapping only in standard board mode
    /// @details    Delegates to SwiftUI's view-aligned behavior outside panoramic mode; panoramic scrolling retains
    ///             its proposed target.
    ///
    /// @param[in,out]  target   Proposed native scroll target, updated in place when the snapping rules apply
    /// @param[in]      context  Framework-supplied update context and coordinator access
    ///
    /// @return     (Void) no return value
    ///
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext)
    {

        if !panoramic
        {
            ViewAlignedScrollTargetBehavior().updateTarget(&target, context: context)
        }

    }

}
