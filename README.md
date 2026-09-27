# Plenact for iOS

Plenact is an iPhone planning and organization app being built around a calm, list-based daily workflow. The current revision provides a Today front door and a horizontally navigable kanban Board for tasks, routines, ideas, and open work.

The product draws on lessons from successful traumatic brain injury recovery, with an emphasis on predictable navigation, readable information, and reduced cognitive load. Plenact may be useful to individuals, teams, and people in recovery settings, but it does not provide medical treatment and makes no clinical claims.

## Current Product

Implemented today:

- A Today screen that lets the user choose an existing board list as the current day's plan.
- A Board with ordered lists, cards, section dividers, completion state, dates, checklists, comments, members, labels, and attachments.
- Direct navigation from Today to any existing board list.
- Local persistence for board data and the label library.
- Local photo and video files in the app's private Documents directory, plus web-link attachments.

Not currently implemented:

- Calendar synchronization or a structured calendar-event model.
- Accounts, cloud synchronization, multi-device synchronization, or a remote database.
- A web or desktop client.
- Clinical validation, treatment functionality, or regulatory compliance claims.

## For Customers and Curious Readers

The app is in an early development revision. The Board is the source of truth: users arrange cards within lists, and Today provides a simpler way into the list that matters now. The proposed Scheduled view is documented but not yet implemented.

See [Today View UI](Doc/Today-View-UI.md) for the current direction and [Board and Scheduled Views](Doc/Board-and-Scheduled-Views.md) for the relationship between planning surfaces.

## For Developers

Plenact is a SwiftUI app with one `Plenact` application target. The project currently targets iPhone, iOS 17.0, and Swift 5 language mode.

```sh
xcodebuild -project Plenact.xcodeproj -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Simulator availability varies by machine. Use `xcodebuild -showdestinations -project Plenact.xcodeproj -scheme Plenact` to discover an installed destination.

There is currently no active test target. Add persistence and behavior tests before making broad stored-model changes.

## Repository Guide

- [`Src/`](Src/README.md): application source, features, assets, and preview support.
- [`Doc/`](Doc/README.md): architecture, UI direction, demos, and coding-style references.
- [`Work/`](Work/README.md): product-discovery reference material; not runtime app data.
- `Plenact.xcodeproj/`: Xcode project configuration. Treat this as tool-managed project structure.
- `Plenact.code-workspace`: VS Code workspace configuration.
- `readme.txt`: early project notes and historical ideas; this README is the current repository entry point.

## Data and Privacy Boundary

Board and label data are stored locally on the installation. Attachment media is stored in the app's private container. Local storage should not be described as synchronization, cloud backup, secure sharing, or multi-user access. Persisted Codable models and attachment filenames are compatibility contracts and require deliberate migration when changed.