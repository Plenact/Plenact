# Application Source

This directory contains the SwiftUI application code and bundled resources for Plenact.

## Source Map

- [`App.swift`](App.swift): application entry point, Today/Board tab shell, and Today list selection.
- [`Features/Boards/`](Features/Boards/README.md): Board UI, card details, domain models, persistence, and checklist migration.
- [`Features/Profile/`](Features/Profile/README.md): local profile, Today avatar, preferences, and settings UI.
- [`../Test/`](../Test/README.md): active unit tests for persistence compatibility and domain behavior.
- [`Features/`](Features/README.md): focused label and attachment features.
- `Assets.xcassets/`: app icon and accent-color assets managed by Xcode.
- [`Preview Content/`](Preview%20Content/README.md): preview-only resources and guidance.

## Architecture

`AppRootView` owns the shared board-list snapshot used by Today and Board. The Board remains the source of truth for cards and lists. Mutations flow through SwiftUI bindings and callbacks, and changes are encoded through `KanbanBoardPersistence`.

The project is intentionally compact. Reuse existing models and helpers before adding a service, repository, or state-management layer. Extract responsibilities when doing so removes demonstrated complexity rather than in anticipation of future scope.

## Persistence Contract

- Board lists and cards are encoded as JSON in `UserDefaults` under a versioned key.
- The label library is encoded separately in `UserDefaults`.
- Attachment metadata is stored with cards; media bytes live in the app's private Documents directory.
- Today list choices use date-specific local preference keys.
- The optional local profile is encoded separately under `Plenact.LocalProfile.v1`.

Do not clear stored data to fix decoding problems. Codable changes require compatibility review, migration behavior, and focused tests. Attachment cleanup must preserve every filename still referenced by a card.

## Product Boundary

The source currently implements local-only behavior. There are no accounts, remote services, analytics, calendar integration, or multi-device/team synchronization. Members are free-text card assignments, not user accounts.

## Validation

Build and test the shared `Plenact` scheme for an installed iPhone simulator after source changes. The active `PlenactTests` target currently covers checklist-item migration and round-trip behavior; expand focused coverage with each domain or persistence change.