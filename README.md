# Plenact for iOS

Version: 1.3   (10/20/26)

Plenact is an iPhone planning and organization app being built around a calm, list-based daily workflow. The current revision provides a Today front door and a horizontally navigable kanban Board for tasks, routines, ideas, and open work

The product draws on lessons from successful traumatic brain injury recovery, with an emphasis on predictable navigation, readable information, and reduced cognitive load. Plenact may be useful to individuals, teams, and people in recovery settings, but it does not provide medical treatment and makes no clinical claims

## Query

This work today has been great, thank you, Alex. Hey how many lines of .swift source code does the Plenact application now have, excluding the test file and folder contents? Please do not include whitespace, comments, lines with only brackets or function signature bars please. And how many commits do we have now in the main branch of this repository? :)

Yes!! Great detail, can you help us implement this new feature? :)

This is beautiful, thank you Alex!! Can you help me with a good git commit message for these updates? :)

# Opens

- Adding a new list to a board enters with the title highlighted, and keyboard raised to enter name for it

- Tapping 'Add Card' at the bottom of the list enters text inline, with its right-hand '+' opening a card instead

- Three setup cards for OTB, ITQ & SR now load in read-only mode, from tapping that view's header title and don't show on list. with all sections hidden too, except for that description which is great - and maybe some checklists with guidance or examples!

!

Now I think I'm going to switch from developer to user, for awhile now, diligently taking notes and sharing with you throughout the day and applying updates or tests as you request

!!

- Tapping an important card's star, in the List view marks it not-important (with a star outline placeholder, to undo that if they want, as long as they stay in that view)

- History of edits to each card!!! ?

- Option for subtitles in italics?

- tapped today's focus list items glow on tap selection

- Begin a published revision history document

- Activity sections for init reference cards on On the Table, In the Queue and Scheduled have the Activity section removed or hidden by default

## Upcoming Development Work

- Giving other user the ability to view/share selected content &/or accounts

- A partner app for Plenact, that accesses and navigates your lists. Consider multiple apps, as different interfaces and tools into your core Plenact data and life plans

- Website Go!!! Android & Desktop applications too

  - Full app representation!! Win/Lin/Apple/Android/Web-Desktop/Web-Mobile

- Widget Extensions!

### Carryover

- aNote note / Trello card view sharing, overlap and use considerations for data organization and presentation in Plenact

	
Opens

- Ability to clear and reset and restart your database files

- style.swift updates
	Import leading statements in style.swift
	struct headers








- "This is beautiful! Hey, how many lines of .swift source code is this now? Please only count source code though, and make sure to not include in the count the white lines of no characters, function declarations, function header bars, comments or lines with only a bracket character on them

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

Personal collections use a separate local snapshot and do not replace the Week board. A List starts with one card column; a Board starts with Ideas, In progress, and Done columns. Both use the existing card editor and retain bookmarks within their own collection. Labels remain shared across the app. Today and global Search continue to use Week; Saved shows bookmarks from Week and active personal collections while keeping their local bookmark stores independent. Personal collection cards are created and edited within their collection. Load Example and its undo operate only on Week.