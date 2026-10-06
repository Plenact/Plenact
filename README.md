# Plenact for iOS

Plenact is an iPhone planning and organization app being built around a calm, list-based daily workflow. The current revision provides a Today front door and a horizontally navigable kanban Board for tasks, routines, ideas, and open work

The product draws on lessons from successful traumatic brain injury recovery, with an emphasis on predictable navigation, readable information, and reduced cognitive load. Plenact may be useful to individuals, teams, and people in recovery settings, but it does not provide medical treatment and makes no clinical claims

## Development Work

- Lists/Notes Interface Idea

- Kanban Look & Feel Idea
	- List Zoom like Trello!!!
	- Panoramic like Trello!

- Kanban Card/Note Representation Concept

- Calendar Idea

### Carryover

- aNote note / Trello card view sharing, overlap and use considerations for data organization and presentation in Plenact

- Today View

- Trello Boards

- Website Go!!!

	
Opens

- Ability to clear and reset and restart your database files

- style.swift updates
	Import leading statements in style.swift
	struct headers

- New File Menu App Review
	- add to New Installs Reset Procedure iff
	
Opens now:

- Quick capture keyboard raise bug!

- Have Alex capture his "hundreds" of tests in written, reproducible form that also produces results, so we can begin to consistently test and verify our app is working

- "This is beautiful! Hey, how many lines of .swift source code is this now? Please only count source code though, and make sure to not include in the count the white lines of no characters, function declarations, function header bars, comments or lines with only a bracket character on them

//................................................................................//

- List submenus!!!
	Card List Actions
	List Actions
	Board Actions
	App Menus
	Account Tab 
	Settings tab

- Calendar page test, expose, expand and prepare

- Able to load from a selection of App demos (e.g. Personal, Work, Recovery, Studies or Therapy)

	- finalize load demos idea

- Real phone init freeze quietly will database init loads

- Quick capture keyboard loads and unexpectedly raises lower toolbar!


### Coming Next

- CLEAN data encapsulation

- RELIABLE, versioned database record

- Full app representation!! Win/Lin/Apple/Android/Web-Desktop/Web-Mobile

// -------------------------------------------------------------------------------------------//

## Current Product

Implemented today:

- A Today screen that lets the user choose an existing board list as the current day's plan
- An optional local profile with a discreet Today avatar, Account & Settings, and personalization
- A Board with ordered lists, cards, section dividers, completion state, dates, checklists, comments, members, labels, and attachments
- A Monday-through-Sunday starter Board with realistic daily-planning examples for new installations
- Seeded checklist demonstrations that link to existing cards and open reduced Action Details
- Direct navigation from Today to any existing board list
- A Lists library with a separate Week Board directory and locally saved personal lists and boards
- Personal collection creation, optional starter templates, renaming, icons, colors, reordering, and confirmed deletion
- Local persistence for board data and the label library
- Local photo and video files in the app's private Documents directory, plus web-link attachments

Not currently implemented:

- Calendar synchronization or a structured calendar-event model
- Online accounts, cloud synchronization, multi-device synchronization, or a remote database
- A web or desktop client
- Clinical validation, treatment functionality, or regulatory compliance claims

## For Customers and Curious Readers

The app is in an early development revision. The Board is the source of truth: users arrange cards within lists, and Today provides a simpler way into the list that matters now. The proposed Scheduled view is documented but not yet implemented

See [Today View UI](Doc/Today-View-UI.md) for the current direction and [Board and Scheduled Views](Doc/Board-and-Scheduled-Views.md) for the relationship between planning surfaces

## Product Direction

Plenact is intended to grow across several related planning jobs:

- Daily scheduling and routine planning
- Task and personal-project organization
- Capturing notes, ideas, and useful context
- Brainstorming and coordinating work with others
- Connecting plans to the actions needed to move them forward

The emerging product model is **Lists organize; Cards describe activities; checklist items express actions**. Today and Week should present the same underlying planning records, while a possible weekly review would help people reconsider those plans without automatically changing them. This model and its implementation boundaries are documented in [Plenact Life Planning & Management Model](Doc/Life-Planning-Model.md); weekly review is not currently implemented.

Potential audiences include individuals, teams, therapy and recovery centers, and people recovering from traumatic brain injuries or with similar accessibility needs. These are product-design audiences, not claims that Plenact provides treatment or has clinical validation

The earlier question of a parent surface for Planner, Labels, Notes, and Attachments is now taking shape through Today as the front door and Board as the current source of truth. Schedule, Projects, Notes, and Team remain possible future destinations rather than implemented navigation

## Exploratory Roadmap

The following ideas came from revision-0 planning and require separate product, privacy, data-model, and testing decisions before implementation:

- Importing and exporting user-controlled data, potentially including JSON
- Distinct personal, office, or other planning profiles
- A structured schedule and optional calendar integration
- Standalone notes and idea capture
- Accounts and collaborative/team workflows
- TestFlight distribution and production-release preparation
- A database or other storage architecture beyond the current local snapshot
- Tablet support and possible desktop or web experiences

Current development should not describe these roadmap items as available features. Cloud services, accounts, calendar permissions, and sharing require explicit approval and privacy review

## Open Design Questions

- Should board cards use a different banner or summary height?
- How should attached hyperlinks appear more cleanly while remaining obvious and accessible?

## Project History

Revision 0 began as a direct continuation of the earlier [Plenact Cards & Lists](https://github.com/Plenact/Plenact-Cards-Lists) reference application. The current repository is establishing the Today, Board, persistence, accessibility, and checklist-action foundations for the broader Plenact product

## For Developers

Plenact is a SwiftUI app with one `Plenact` application target. The project currently targets iPhone, iOS 17.0, and Swift 5 language mode

```sh
xcodebuild -project Plenact.xcodeproj -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Simulator availability varies by machine. Use `xcodebuild -showdestinations -project Plenact.xcodeproj -scheme Plenact` to discover an installed destination

The shared `Plenact` scheme includes an active `PlenactTests` unit-test target. Run tests with the same simulator destination by replacing `build` with `test` in the command above. Current coverage establishes checklist persistence compatibility; additional product behavior still needs focused tests as features expand

## Repository Guide

- [`Src/`](Src/README.md): application source, features, assets, and preview support
- [`Doc/`](Doc/README.md): architecture, UI direction, demos, and coding-style references
- [`Work/`](Work/README.md): product-discovery reference material; not runtime app data
- [`Test/`](Test/README.md): active unit tests and persistence compatibility fixtures
- `Plenact.xcodeproj/`: Xcode project configuration. Treat this as tool-managed project structure
- `Plenact.code-workspace`: VS Code workspace configuration

## Data and Privacy Boundary

Board and label data are stored locally on the installation. Attachment media is stored in the app's private container. Local storage should not be described as synchronization, cloud backup, secure sharing, or multi-user access. Persisted Codable models and attachment filenames are compatibility contracts and require deliberate migration when changed

Personal collections use a separate local snapshot and do not replace the Week board. A List starts with one card column; a Board starts with Ideas, In progress, and Done columns. Both use the existing card editor and retain bookmarks within their own collection. Labels remain shared across the app. Today, the lower-bar New action, global Search, and Saved continue to use Week; personal collection cards are accessed and created within their collection. Load Example and its undo operate only on Week.