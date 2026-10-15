// --------------------------------------------------------------------------------------------------
// @file       DatabaseActivity.swift
// @brief      Shared database activity state and SwiftUI overlay
// @details    Publishes in-flight operation messages and dismissible errors for database requests
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


struct TransferConfirmation: Equatable {
    enum Action { case moved, copied }
    let title: String
    let destination: String
    var action: Action = .moved
    var message: String {
        "\(action == .moved ? "Moved" : "Copied") ‘\(title)’ to \(destination)."
    }
}

/// A noninteractive window keeps confirmations visible across sheets and full-screen editors.
@MainActor
final class TransferConfirmationPresenter {
    static let shared = TransferConfirmationPresenter()
    private var window: UIWindow?
    private var dismissTask: Task<Void, Never>?

    func dismiss() {
        dismissTask?.cancel()
        window?.isHidden = true
        window = nil
    }

    func show(_ confirmation: TransferConfirmation) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        dismissTask?.cancel()
        window?.isHidden = true
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

private final class TransferConfirmationWindow: UIWindow {
    override var canBecomeKey: Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

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
