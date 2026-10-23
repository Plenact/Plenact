// --------------------------------------------------------------------------------------------------
// @file       DatabaseActivity.swift
// @brief      Database activity presentation and content-transfer confirmations
// @details    Publishes active database requests and dismissible errors through a shared observable
//             state. Hosts transient move or copy notices and guarded section-move Undo using
//             windows and overlays that limit interception to the interactive notice panel.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Tracks active shared-database operations and a dismissible error message
///
/// @section    Purpose
///     Expose shared synchronization progress and failures to the SwiftUI presentation layer
///
@MainActor
final class DatabaseActivity: ObservableObject {

    /// Process-wide activity state observed by database-backed views.
    static let shared = DatabaseActivity() /* Process-wide activity state observed by database-backed views */

    /// Active operation identifiers paired with their visible progress messages.
    @Published private(set) var operations: [(id: UUID, message: String)] = [] /* Active operation identifiers and visible progress messages */

    /// Latest error message awaiting dismissal.
    @Published private(set) var errorMessage: String? /* Latest database error awaiting dismissal */

    ///
    /// @fcn        DatabaseActivity.isWorking
    /// @brief      Report whether any database operation is active
    /// @details    Derives activity from the current operation collection
    ///
    /// @return     (Bool) true while at least one operation is active
    ///
    var isWorking: Bool { !operations.isEmpty } /* Whether database work is active */

    ///
    /// @fcn        DatabaseActivity.message
    /// @brief      Return the visible message for the earliest active operation
    /// @details    Uses the first operation in the current activity sequence
    ///
    /// @return     (String?) active message, or nil when no operation is active
    ///
    var message: String? { operations.first?.message } /* Earliest active operation message */


    ///
    /// @fcn        DatabaseActivity.begin(_:)
    /// @brief      Register a database operation as active
    /// @details    Adds a new operation entry so views can show progress until it is ended
    ///
    /// @param[in]  message  Progress text associated with the operation
    ///
    /// @return     (UUID) identifier required to end this operation
    ///
    @discardableResult
    func begin(_ message: String) -> UUID {

        let id = UUID() /* Identifier for this active operation */

        operations.append((id, message))

        return id
    }


    ///
    /// @fcn        DatabaseActivity.end(_:)
    /// @brief      Remove an operation from the active set
    /// @details    Removes every active entry carrying the supplied identifier
    ///
    /// @param[in]  id  Operation identifier returned by begin(_:)
    ///
    /// @return     (Void) updates the active operation collection
    ///
    func end(_ id: UUID) {

        operations.removeAll { $0.id == id }
    }


    ///
    /// @fcn        DatabaseActivity.report(_:)
    /// @brief      Publish an error message for the shared database UI
    /// @details    Replaces the currently visible error text
    ///
    /// @param[in]  message  Error text to present
    ///
    /// @return     (Void) updates errorMessage
    ///
    func report(_ message: String) {

        errorMessage = message
    }


    ///
    /// @fcn        DatabaseActivity.dismissError()
    /// @brief      Clear the currently visible database error
    /// @details    Resets the published error state after user dismissal
    ///
    /// @return     (Void) clears errorMessage
    ///
    func dismissError() {

        errorMessage = nil
    }
}


///
/// Adds shared-database progress and error presentation to a view
///
/// @section    Purpose
///     Render active operation status and a dismissible database error above modified content
///
private struct DatabaseActivityOverlay: ViewModifier {

    /// Shared database activity observed by this modifier.
    @ObservedObject private var activity = DatabaseActivity.shared /* Shared activity source rendered by this overlay */


    ///
    /// @fcn        DatabaseActivityOverlay.body(content:)
    /// @brief      Overlay current database activity on the modified content
    /// @details    Shows progress while work is active and exposes any reported error for dismissal
    ///
    /// @param[in]  content  View to decorate with activity feedback
    ///
    /// @return     (some View) content with a top-aligned activity or error overlay
    ///
    func body(content: Content) -> some View {

        content.overlay(alignment: .top) {

            if activity.isWorking || activity.errorMessage != nil {

                VStack(alignment: .leading, spacing: 8) {

                    if let message = activity.message { /* Active operation progress text */

                        HStack(spacing: 12) {

                            ProgressView()

                            VStack(alignment: .leading, spacing: 2) {

                                Text(message).font(.subheadline.weight(.semibold))
                                Text("Please wait a moment.").font(.caption)
                            }
                        }

                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("databaseActivity")
                        .allowsHitTesting(false)
                    }

                    if let errorMessage = activity.errorMessage { /* Reported database error text */

                        HStack(alignment: .top, spacing: 12) {
                            Text(errorMessage).font(.subheadline)
                            Button("Dismiss", systemImage: "xmark") {
                                activity.dismissError()
                            }

                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Dismiss database error")
                        }
                    }
                }

                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 4, y: 2)
                .padding()
                .allowsHitTesting(activity.errorMessage != nil)
            }
        }
    }
}


///
/// Provides the database-activity overlay convenience to SwiftUI views
///
/// @section    Purpose
///     Keep activity presentation attachment concise at view call sites
///
extension View {


    ///
    /// @fcn        View.databaseActivityOverlay()
    /// @brief      Attach the shared database activity overlay
    /// @details    Applies DatabaseActivityOverlay to the receiving view
    ///
    /// @return     (some View) modified view with database activity feedback
    ///
    func databaseActivityOverlay() -> some View {

        modifier(DatabaseActivityOverlay())
    }
}


///
/// Describes a completed content transfer
///
/// @section    Purpose
///     Combines title, destination, and move-or-copy action into a confirmation message without
///     retaining mutable workspace content.
///
struct TransferConfirmation: Equatable {


    ///
    /// Distinguishes successful moves from copies
    ///
    /// @section    Purpose
    ///     Selects the verb in transfer confirmation messages without affecting the completed
    ///     operation.
    ///
    enum Action { case moved, copied }
    let title:       String
    let destination: String
    var action:      Action = .moved
    var message:     String {
        "\(action == .moved ? "Moved" : "Copied") ‘\(title)’ to \(destination)."
    }
}


///
/// Presents transfer confirmations above active editors
///
/// @section    Purpose
///     Uses a noninteractive notice window and a narrowly interactive Undo overlay so unrelated
///     workspace touches continue to reach their views.
///
@MainActor
final class TransferConfirmationPresenter {

    static let shared = TransferConfirmationPresenter()
    private var window:      UIWindow?
    private var dismissTask: Task<Void, Never>?
    private var undoOverlay: TransferUndoOverlay?
    private var undoHost:    UIViewController?


    ///
    /// @fcn        TransferConfirmationPresenter.dismiss
    /// @brief      Remove the current transfer feedback presentation
    /// @details    Cancels its maintenance task and clears the retained overlay, hosting controller, and any
    ///             transient feedback window.
    ///
    /// @return     (Void) no return value
    ///
    func dismiss() {
        dismissTask?.cancel()
        window?.isHidden = true
        window = nil
        undoOverlay?.removeFromSuperview()
        undoOverlay = nil
        undoHost = nil
    }


    ///
    /// @fcn        TransferConfirmationPresenter.showUndo
    /// @brief      Show a persistent section-transfer Undo notice
    /// @details    Hosts the notice in the existing key window and keeps it above later presentations; Undo uses the
    ///             supplied checked callback and can report a failed restoration.
    ///
    /// @param[in]  confirmation  Transfer message and action metadata to present
    /// @param[in]  undo          Checked restoration callback; false keeps feedback available for a failed Undo
    ///
    /// @return     (Void) no return value
    ///
    /// @note       Unlike the transient confirmation, this remains available across navigation until used or
    ///             dismissed.
    ///
    func showUndo(_ confirmation: TransferConfirmation, undo: @escaping () -> Bool) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let mainWindow = scene.windows.first(where: \.isKeyWindow) else { return }
        dismiss()
        // Keep native drag sessions in their original window. A second, persistent
        // UIWindow can intercept the system's drag routing even when taps pass through.
        let overlay = TransferUndoOverlay(frame: mainWindow.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .clear
        overlay.accessibilityIdentifier = "section.move.undo.overlay"
        let host = UIHostingController(rootView: SectionUndoToast(message: confirmation.message,
            undo: { [weak self] in
                let succeeded = undo()
                if succeeded { self?.dismiss() }
                return succeeded
            }, close: { [weak self] in self?.dismiss() },
            onFrame: { [weak overlay] in overlay?.touchRegion = $0 }))
        host.view.backgroundColor = .clear
        host.view.frame = overlay.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addSubview(host.view)
        mainWindow.addSubview(overlay)
        undoOverlay = overlay
        undoHost = host
        UIAccessibility.post(notification: .announcement, argument: confirmation.message + " Undo available.")
        // UIKit may add a presentation above the root view during navigation.
        // Retain the same panel and bring it above that presentation, without another window.
        dismissTask = Task { [weak self, weak overlay, weak mainWindow] in
            while !Task.isCancelled {
                guard let self, let overlay, let mainWindow, self.undoOverlay === overlay else { return }
                if mainWindow.subviews.last !== overlay { mainWindow.bringSubviewToFront(overlay) }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }


    ///
    /// @fcn        TransferConfirmationPresenter.show
    /// @brief      Show a short-lived transfer confirmation
    /// @details    Replaces previous feedback with a noninteractive presentation that dismisses after its display
    ///             interval.
    ///
    /// @param[in]  confirmation  Transfer message and action metadata to present
    ///
    /// @return     (Void) no return value
    ///
    func show(_ confirmation: TransferConfirmation) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        dismiss()
        let window = TransferConfirmationWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = UIHostingController(rootView: TransferConfirmationToast(message: confirmation.message))
        window.rootViewController?.view.backgroundColor = .clear
        self.window = window
        window.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: confirmation.message)
        dismissTask = Task { [weak self, weak window] in
            do { try await Task.sleep(for: .milliseconds(3400)) } catch { return }
            guard let self, let window, self.window === window else { return }
            window.isHidden = true
            self.window = nil
        }
    }
}


///
/// Restricts Undo-overlay interaction to its notice panel
///
/// @section    Purpose
///     Passes touches outside the retained panel rectangle through to the existing application
///     interface.
///
private final class TransferUndoOverlay: UIView {

    var touchRegion: CGRect = .zero


    ///
    /// @fcn        TransferUndoOverlay.hitTest
    /// @brief      Restrict the Undo overlay to its hosted notice panel
    /// @details    Returns a normal child hit only inside the retained panel rectangle; touches outside pass through
    ///             to the existing application window.
    ///
    /// @param[in]  point  Touch or drop location in the operation's coordinate space
    /// @param[in]  event  Optional UIKit event accompanying hit testing
    ///
    /// @return     (UIView?) hit-tested notice subview, or nil to pass touches outside the notice through
    ///
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard touchRegion.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}


///
/// Hosts a non-key transfer confirmation window
///
/// @section    Purpose
///     Returns no touch hit so notices remain visible across presentations without intercepting
///     underlying interactions.
///
private final class TransferConfirmationWindow: UIWindow {

    var touchRegion:           CGRect = .zero
    override var canBecomeKey: Bool { false }


    ///
    /// @fcn        TransferConfirmationWindow.hitTest
    /// @brief      Keep transient confirmation windows noninteractive
    /// @details    Returns nil so underlying application content continues receiving touches.
    ///
    /// @param[in]  point  Touch or drop location in the operation's coordinate space
    /// @param[in]  event  Optional UIKit event accompanying hit testing
    ///
    /// @return     (UIView?) nil so the transient feedback window never consumes application touches
    ///
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard touchRegion.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}


///
/// Displays a transient successful-transfer notice
///
/// @section    Purpose
///     Animates the supplied message while respecting Reduce Motion and leaving application content
///     interactive.
///
private struct TransferConfirmationToast: View {

    let message: String
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.title3)
                Text(message).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: 520, alignment: .leading)
            .background(Color(red: 0.18, green: 0.39, blue: 0.29), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .opacity(visible ? 1 : 0)
            .offset(y: reduceMotion || visible ? 0 : 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .allowsHitTesting(false)
        .task {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { visible = true }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { visible = false }
        }
    }
}


///
/// Presents the single-action section-move Undo notice
///
/// @section    Purpose
///     Delegates Undo and dismissal, reports its interactive frame, and displays failure without
///     discarding current content.
///
private struct SectionUndoToast: View {

    let message: String
    let undo:    () -> Bool
    let close:   () -> Void
    let onFrame: (CGRect) -> Void
    @State private var failed = false
    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text(failed ? "Couldn't undo this move. Your current content has been retained." : message).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Undo", systemImage: "arrow.uturn.backward") { failed = !undo() }
                        .font(.headline).frame(minHeight: 44)
                        .accessibilityIdentifier("section.move.undo")
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Dismiss move confirmation")
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: 520, alignment: .leading)
            .background(Color(red: 0.18, green: 0.39, blue: 0.29), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
}
