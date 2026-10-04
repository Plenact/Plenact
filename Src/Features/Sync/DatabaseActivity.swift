import SwiftUI

@MainActor
final class DatabaseActivity: ObservableObject {
    static let shared = DatabaseActivity()

    @Published private(set) var operations: [(id: UUID, message: String)] = []
    @Published private(set) var errorMessage: String?

    var isWorking: Bool { !operations.isEmpty }
    var message: String? { operations.first?.message }

    @discardableResult
    func begin(_ message: String) -> UUID {
        let id = UUID()
        operations.append((id, message))
        return id
    }

    func end(_ id: UUID) {
        operations.removeAll { $0.id == id }
    }

    func report(_ message: String) {
        errorMessage = message
    }

    func dismissError() {
        errorMessage = nil
    }
}

private struct DatabaseActivityOverlay: ViewModifier {
    @ObservedObject private var activity = DatabaseActivity.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if activity.isWorking || activity.errorMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let message = activity.message {
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
                    if let errorMessage = activity.errorMessage {
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

extension View {
    func databaseActivityOverlay() -> some View {
        modifier(DatabaseActivityOverlay())
    }
}
