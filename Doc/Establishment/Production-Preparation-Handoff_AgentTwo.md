# Plenact: Production Preparation and Release Handoff

**Prepared:** October 4, 2026  
**Purpose:** Give the next production-preparation agent a comprehensive, actionable transfer of product intent, implementation knowledge, accepted behavior, engineering lessons, verification evidence, and release-preparation work.  
**Repository:** `Plenact/Plenact`  
**Inspected application revision:** `5a39025f4f0b9c8d9e06b989472dc41ad23fdf30` (`5a39025`, comment updates).  
**Product owner:** Justin Reina, referred to as Jim in the shared-demo account documentation.  
**Audience:** The product owner, the next engineering agent, and anyone helping prepare a responsible iOS release.

> **The essential handoff:** Plenact already has a useful, local-first planning experience that the owner has repeatedly tested and enjoyed. Preserve that experience and its user data. Production preparation means proving reliability, clarifying the product promise, closing release-critical gaps, and delivering a trustworthy release. It does not mean replacing the app wholesale or silently turning a synthetic shared-demo backend into private customer storage.

---

## Contents

1. [How to use this handoff](#1-how-to-use-this-handoff)
2. [The vision and the experience worth protecting](#2-the-vision-and-the-experience-worth-protecting)
3. [What exists, what is experimental, and what is not implemented](#3-what-exists-what-is-experimental-and-what-is-not-implemented)
4. [Working with the product owner](#4-working-with-the-product-owner)
5. [Repository and build identity](#5-repository-and-build-identity)
6. [Source-file map and the duplicate-file trap](#6-source-file-map-and-the-duplicate-file-trap)
7. [Application architecture and state ownership](#7-application-architecture-and-state-ownership)
8. [Persistence inventory and durability boundaries](#8-persistence-inventory-and-durability-boundaries)
9. [Domain models, identity, and migration contracts](#9-domain-models-identity-and-migration-contracts)
10. [Today, navigation, capture, and selection](#10-today-navigation-capture-and-selection)
11. [Search, labels, Saved, and Calendar](#11-search-labels-saved-and-calendar)
12. [Personal lists and boards](#12-personal-lists-and-boards)
13. [Archive and restore: the accepted product contract](#13-archive-and-restore-the-accepted-product-contract)
14. [List and card reordering](#14-list-and-card-reordering)
15. [The List Actions Add card fix](#15-the-list-actions-add-card-fix)
16. [Card detail, checklist actions, and activity](#16-card-detail-checklist-actions-and-activity)
17. [Attachments and avatar media](#17-attachments-and-avatar-media)
18. [Local profiles and accessibility preferences](#18-local-profiles-and-accessibility-preferences)
19. [Database activity and error feedback](#19-database-activity-and-error-feedback)
20. [Shared-demo API and deployment evidence](#20-shared-demo-api-and-deployment-evidence)
21. [Documentation reconciliation](#21-documentation-reconciliation)
22. [What we changed and what we learned](#22-what-we-changed-and-what-we-learned)
23. [Fresh validation baseline and how to reproduce it](#23-fresh-validation-baseline-and-how-to-reproduce-it)
24. [Release-readiness investigation register](#24-release-readiness-investigation-register)
25. [Production data protection and migration strategy](#25-production-data-protection-and-migration-strategy)
26. [Accessibility, cognitive load, and device validation](#26-accessibility-cognitive-load-and-device-validation)
27. [Automated and manual acceptance matrix](#27-automated-and-manual-acceptance-matrix)
28. [Recommended production work phases](#28-recommended-production-work-phases)
29. [TestFlight and App Store preparation](#29-testflight-and-app-store-preparation)
30. [Operations, support, and post-release stewardship](#30-operations-support-and-post-release-stewardship)
31. [Explicit decisions for the owner](#31-explicit-decisions-for-the-owner)
32. [First assignment for the next agent](#32-first-assignment-for-the-next-agent)
33. [Reference index](#33-reference-index)
34. [Final transfer principles](#34-final-transfer-principles)

---

## 1. How to use this handoff

### 1.1 Evidence labels

This document intentionally separates several kinds of knowledge:

| Label | Meaning |
|---|---|
| **Verified source** | Observed in the repository during preparation of this handoff |
| **Fresh validation** | A command was run successfully for this handoff |
| **Historical validation** | A result from the earlier implementation conversation, not a fresh certification of every path |
| **Owner-confirmed behavior** | The owner personally tried an interaction and reported that it worked |
| **Repository-reported deployment** | A checked-in document records external deployment work; this handoff did not independently inspect the live host |
| **Investigation / recommendation** | Work to verify, decide, or implement before release; not a claim that a defect was proven or a feature already exists |

These distinctions matter. Passing unit tests does not prove that every touch interaction is reliable. A server deployment note does not prove current production authorization. A privacy principle does not establish legal compliance. A property in a preferences model does not prove that its setting visibly changes every relevant screen.

### 1.2 Read in two passes

**First pass, to orient quickly:** Sections 2, 3, 5, 6, 7, 13, 20, 23, 24, and 32.

**Second pass, before changing code:** Read the relevant behavior contracts and the current implementation. Use this handoff as a map, not as a substitute for code inspection.

Before implementing anything:

1. Inspect the current Git status and preserve changes not belonging to your task.
2. Confirm the app target's actual source membership.
3. Establish a reproducible baseline.
4. Agree the first-release scope with the owner.
5. Identify data-compatibility and user-visible behavior implications.
6. Add or adapt focused tests for the exact behavior being changed.
7. Implement one coherent change.
8. Verify both the new requirement and preserved behavior.
9. Update the directly related documentation.

### 1.3 Scope of this handoff

This is a product-and-engineering transfer, not:

- A production security assessment.
- A clinical or regulatory assessment.
- A legal determination.
- A successful App Store submission.
- A live-server health or permissions attestation.
- A commitment to a particular database, authentication provider, pricing model, or launch date.

The owner requested a detailed Markdown handoff. Preparing it does not authorize live database changes, credential changes, app submission, public release, or unrelated code refactoring.

### 1.4 Worktree state when preparation began

The previous implementation and the large function-header documentation changes had been committed by the owner. `HEAD` was `5a39025`.

There was one existing unstaged edit in [Doc/README.md](README.md), adding a link to this very filename. That edit was preserved rather than rewritten. This handoff supplies the linked document.

This preparation changed documentation, not application behavior. If more changes exist when you start, inspect them; do not assume this snapshot still describes the worktree.

---

## 2. The vision and the experience worth protecting

### 2.1 Product purpose

Plenact is an iPhone planning and organization app built around a calm, understandable, list-based daily workflow.

The key idea is not merely "another task database." It is a usable bridge between:

- Choosing what matters today.
- Capturing tasks, ideas, and supporting context.
- Organizing work across days and projects.
- Breaking activities into actions.
- Seeing and changing a plan without losing its structure.
- Putting completed or temporarily irrelevant work away without destroying it.
- Returning to that work when needed.

The owner has described daily scheduling, task management, personal projects, notes, ideas, and connecting plans with people as the broader direction. Team brainstorming, calendar integration, desktop/web access, and multiple planning contexts are exploratory ambitions, not commitments for the first release.

### 2.2 The originating planning method

The original reference workflow uses:

- A weekly kanban board.
- One ordered list for each day.
- Manually ordered cards expressing the sequence of the day.
- Divider cards marking sections.
- Open work and custom lists beyond the weekday convention.
- Card detail for context and checklists for concrete actions.

The supplied Trello-related references and exports informed this design. They are discovery material, not runtime data automatically imported by the application.

The weekday convention is helpful starter content, not a hard storage rule. A list title is editable. It is not a stable date or weekday assignment.

### 2.3 The information hierarchy

Use this language consistently:

> **Lists organize. Cards describe activities. Checklist items express actions.**

This distinction should guide both architecture and UI copy:

- Do not force every action to become a full Board card.
- Do not duplicate a task because it appears in Today.
- Do not introduce a separate Today-only completion store.
- Do not mistake a date on a task for a calendar event.
- Do not use an assigned person as a substitute for access control.
- Do not equate an archive with deletion.

### 2.4 Cognitive accessibility is central, not decorative

The [root README](../README.md) says the product draws on lessons from successful traumatic brain injury recovery, emphasizing predictable navigation, readability, and reduced cognitive load.

Potential audiences include individuals, teams, and people in recovery-oriented settings. This is a design motivation and audience hypothesis, not a claim of medical treatment or efficacy.

Preserve:

- Predictable screen names and paths.
- A calm Today front door.
- Explicit destinations when creating cards.
- Clear status during saving or waiting.
- Recoverable actions instead of unnecessary destructive ones.
- Visible alternatives to gesture-only interactions.
- User-controlled order.
- Plain, understandable error and empty-state copy.

Avoid:

- Dense dashboards added simply because data is available.
- Auto-changing priorities without the user's request.
- Surprise rearrangement.
- Unexplained spinners.
- Silent data replacement.
- Clinical, treatment, compliance, or guaranteed-recovery claims.

### 2.5 A reasonable first-release product hypothesis

**Recommendation, subject to owner approval:** First release a dependable local-first iPhone planner with Today, Week, personal collections, card context, and archive/restore.

This does not close off future synchronization. It reduces the temptation to make unvalidated identity, tenancy, privacy, and migration decisions merely to say the product is "cloud connected."

If remote accounts or sync are required for the first release, that is a materially different scope. Make the decision explicitly and fund the additional design, implementation, operational, and verification work.

---

## 3. What exists, what is experimental, and what is not implemented

### 3.1 Capability matrix

| Capability | Current state | Important boundary |
|---|---|---|
| Today launch screen | Implemented | Projects existing Week cards rather than duplicating them |
| Per-date Today list selection | Implemented | Local preference; not a structured schedule |
| Week Board | Implemented | Local ordered snapshot |
| Personal lists and boards | Implemented | Separate local collection snapshot |
| Card creation/editing/completion | Implemented | Shared Board values and caller-owned persistence |
| Card dates | Implemented | Optional `Date` values used in day-based UI |
| Calendar card-date browser | Implemented | Not EventKit, calendar import, reminders, or sync |
| Labels and categories | Implemented | App-wide local library referenced by stable IDs |
| Manual members | Implemented | Text assignments, not authenticated accounts |
| Typed registered assignee records | Implemented in model/client | Local member editor does not become an online people directory |
| Comments and activity display | Implemented | Some generated activity is synthetic display copy |
| Standard checklist actions | Implemented | Stable identity and completion |
| Linked-card checklist navigation | Implemented | References can become unavailable; creation controls are incomplete |
| Reduced Action Detail | Implemented editor/seed examples | Not a standalone card; draft Save/Cancel |
| Card archive/browser/restore | Implemented | Local retained records; remote schema does not support nonempty archives |
| List archive/browser/restore | Implemented | Restore appends to original Board |
| Full-board archive/browser/restore | Implemented | Saved contains archived full boards |
| Hold-and-drag list reordering | Implemented | Menu/VoiceOver alternatives remain |
| Local profile and avatar | Implemented | Not sign-in |
| Avatar photo/crop storage | Implemented | Private local files and profile metadata |
| Local busy/error banner | Implemented | Spinner is feedback, not proof of durable storage |
| HTTPS API and Keychain session source | Implemented | Shared synthetic demo boundary |
| Shared-demo deployment | Repository-reported | Not independently revalidated against live host here |
| Mounted shared-demo account UI | Not currently mounted | Existing client code does not equal customer-facing sync |
| Automatic local-to-cloud sync | Not implemented | No normal Board publication pipeline |
| Production private/team Boards | Not established | Requires ownership/authorization design |
| User-controlled full export/import | Exploratory | Not a current product promise |
| Scheduled agenda destination | Proposed | No implemented Scheduled tab |
| True calendar event/recurrence model | Not implemented | Separate product/data decision |
| Standalone Notes feature | Not implemented | Card descriptions exist, not a separate notes system |
| Web/desktop app | Not implemented | Roadmap only |
| iPad-specific release support | Not current app target | Target device family is iPhone |
| Clinical validation or treatment | Not established | Must not be claimed |

### 3.2 Important distinction: backend existence versus app integration

There are three different questions:

1. Does the repository contain backend/client code? **Yes.**
2. Do repository documents report a deployed synthetic shared demo? **Yes.**
3. Does normal Today/Week editing synchronize customer data through it? **No.**

Do not collapse these into a single "sync works" statement.

### 3.3 Feature presence versus feature completeness

A feature may be implemented but still need production hardening:

- Archive retention exists, but large-data durability and recovery need more evidence.
- Drag ordering exists, but simulator unit tests do not establish touch usability on every iPhone.
- Accessibility labels exist, but an end-to-end VoiceOver audit has not been established here.
- Avatar cropping has tests, but the complete real-device picker/cancellation workflow still needs release testing.
- The API validates contracts, but production accounts/tenancy are not inferred from that validator.

---

## 4. Working with the product owner

### 4.1 Communication preferences learned through this work

The owner responds well to:

- Direct implementation when the request is clear.
- Friendly but concise progress updates.
- Clear tables listing files changed and why.
- Plain explanations of causes and fixes.
- Honest distinctions between implementation, tests, and hands-on validation.
- Suggested commit messages after reviewing the actual staged contents.
- Full-detail documents when explicitly requested, as with this handoff.

The owner has repeatedly tested changes personally and reported enthusiasm when the workflow improved. Those reactions are meaningful product feedback, but not a substitute for a release acceptance plan.

### 4.2 Preserve the collaborative pattern

For a new change:

1. Explain the relevant cause or boundary.
2. Ask one focused question if behavior is genuinely ambiguous.
3. Implement the complete path, not just one UI entry point.
4. Validate the exact requirement.
5. Explain the result with a short change table when useful.
6. Leave staging/commit decisions to the owner unless explicitly requested.

Examples of decisions that were clarified rather than guessed:

- Archived cards should be viewable **and restorable**, not only listed.
- Full-board archive should include Week as well as personal boards.
- Restoring an archived Week Board should create a **separate copy**, not replace current Week.

### 4.3 Git safety

The owner often stages and commits between turns. Recheck status before describing something as staged.

An earlier worktree accidentally reversed a committed persistence change. We explained the difference between committed content and unstaged reversals and recommended a narrowly targeted recovery rather than a broad reset.

For the next agent:

- Never discard unrelated changes.
- Never assume a dirty file is safe to overwrite.
- Never use broad reset/checkout as cleanup.
- Do not amend commits without approval.
- Do not stage or commit merely because a commit message was requested.
- If making an authorized commit, follow the repository/session commit conventions.

### 4.4 Important restraint

Production preparation is not permission to:

- Provision or modify live infrastructure.
- Use real personal/health/customer records as fixtures.
- Retrieve or publish secrets.
- Run a destructive data migration.
- Submit a build to Apple.
- Claim the product treats or improves a medical condition.
- Add analytics, paid services, login, or sharing without explicit product approval.

---

## 5. Repository and build identity

### 5.1 Verified current configuration

| Item | Verified value / state |
|---|---|
| Repository | `Plenact/Plenact` |
| Application project | [Plenact.xcodeproj](../Plenact.xcodeproj/) |
| Shared scheme | `Plenact` |
| Application target | `Plenact` |
| Unit-test target | `PlenactTests` |
| Minimum iOS deployment target | `17.0` |
| Swift language setting | `5.0` |
| Targeted device family | `1` (iPhone) |
| Supported build platforms | `iphoneos`, `iphonesimulator` |
| Application bundle identifier | `com.plenact.Plenact02` |
| Test bundle identifier | `com.plenact.Plenact02Tests` |
| Marketing version | `1.0` |
| Build number | `1` |
| Signing style | Automatic |
| Info file | [Src/Info.plist](../Src/Info.plist) |
| API base build setting | `https://plenact.com/api/` |
| Toolchain observed for this handoff | Xcode 27.0, build `27A266a` |
| Fresh-test runtime | iOS Simulator 27.0 |

These are inspected build settings, not final release approvals.

Before release, confirm the intended final bundle identity and ownership of the corresponding Apple Developer/App Store Connect record. Do not casually change a shipping bundle identifier: it affects app identity, installation continuity, signing, container data, and session storage.

### 5.2 Current orientation configuration deserves reconciliation

The handwritten Info file lists portrait and landscape-left for iPhone. Project-generated Info settings also contain landscape-right. The app uses a handwritten Info file rather than a fully generated one.

**Investigation:** Inspect the built product's effective Info dictionary, choose the intended orientation policy, and test every supported orientation. Do not infer final behavior from one setting alone.

There are iPad-oriented keys in configuration, but the app target remains iPhone-only. Those keys do not establish a supported iPad product.

### 5.3 Observed release-resource inventory

Tracked sources include a 1024-by-1024 app icon entry and the Today paper asset.

No tracked resources matching the following were found during the inventory:

- `PrivacyInfo.xcprivacy`.
- Entitlement files.
- A UI-test target/source path.
- StoreKit configuration.
- Swift Package manifest or resolved dependency file.
- GitHub Actions workflow files.
- A license file under the searched conventional names.

Absence in tracked files is a starting point for investigation, not a determination that every item is required or that external setup does not exist.

Confirm App Store privacy-manifest obligations against the actual APIs and release requirements. Do not fabricate required-reason declarations. Decide licensing/provenance separately with the owner.

### 5.4 Source size context

Earlier on October 4, the app's fourteen compiled Swift files contained **6,959 counted source lines** under the owner's requested exclusions:

- Blank/whitespace-only lines omitted.
- Comments/header bars omitted.
- Function/initializer declaration lines and multiline signatures omitted.
- Bracket/brace/parenthesis-only lines omitted.

Tests contributed 699 similarly counted lines. Noncompiled legacy/template files contributed 1,364. This was a custom physical-line count, not complexity, test coverage, or a standard language-aware LOC metric.

The three heavily documented active files currently have approximately:

| File | Physical lines observed during this handoff |
|---|---:|
| [App.swift](../Src/App.swift) | 3,412 |
| [Board ContentView.swift](../Src/Features/Boards/ContentView.swift) | 3,054 |
| [Board CardDetailView.swift](../Src/Features/Boards/CardDetailView.swift) | 3,060 |

Their size includes substantial documentation. Do not use line count alone to justify a risky rewrite.

---

## 6. Source-file map and the duplicate-file trap

### 6.1 Compiled application files

| File | Primary responsibility |
|---|---|
| [Src/App.swift](../Src/App.swift) | Entry point; Today/Week/Lists/Saved shell; root state; Today capture/search/labels/calendar; personal collection directory and archive restore |
| [Boards/ContentView.swift](../Src/Features/Boards/ContentView.swift) | Shared Board; list/card rows; Board/member settings; archives; drag ordering; focused Today list |
| [Boards/CardDetailView.swift](../Src/Features/Boards/CardDetailView.swift) | Full card editor; checklists; reduced action editor; members; dates; attachments; activity and reusable rows |
| [Boards/Models.swift](../Src/Features/Boards/Models.swift) | Codable model tree; migration; local Board/collection/undo stores; sample data; reorder helpers |
| [Attachments/PhotoAttachments.swift](../Src/Features/Attachments/PhotoAttachments.swift) | Attachment metadata, local file storage, source chooser, links, thumbnails, previews |
| [Labels/LabelModels.swift](../Src/Features/Labels/LabelModels.swift) | Reusable labels/categories/colors, local library store, label chip |
| [Labels/CardLabelsSheet.swift](../Src/Features/Labels/CardLabelsSheet.swift) | Card label/catalog editing sheet |
| [Profile/ProfileModels.swift](../Src/Features/Profile/ProfileModels.swift) | Local profile, preferences, avatar tokens/colors, compatibility decoding |
| [Profile/LocalProfileStore.swift](../Src/Features/Profile/LocalProfileStore.swift) | Profile preferences storage and avatar photo file store |
| [Profile/AccountSettingsView.swift](../Src/Features/Profile/AccountSettingsView.swift) | Profile/settings UI, avatar editing/cropping, Load Example/Undo |
| [Sync/DatabaseActivity.swift](../Src/Features/Sync/DatabaseActivity.swift) | Shared busy tracking and persistent dismissible error banner |
| [Sync/PlenactBoardDocument.swift](../Src/Features/Sync/PlenactBoardDocument.swift) | Versioned remote document, validation, response provenance |
| [Sync/PlenactAPIClient.swift](../Src/Features/Sync/PlenactAPIClient.swift) | HTTPS transport, remote identity/session, Keychain, body limits, demo seed/write/assignments |
| [Sync/PlenactDemoAccountSection.swift](../Src/Features/Sync/PlenactDemoAccountSection.swift) | Shared-demo account/read/assignment UI source; currently not mounted in normal settings |

### 6.2 Noncompiled Swift files

The repository also contains:

- [Src/CardDetailView.swift](../Src/CardDetailView.swift).
- [Src/Models.swift](../Src/Models.swift).
- [Doc/Style/style.swift](Style/style.swift).

The first two are legacy/root duplicates. The active application uses the **Features/Boards** versions.

**Do not fix the wrong duplicate.** Before editing a file with one of these names, verify its path and project membership.

Do not delete legacy sources casually. Removing them is a separate cleanup decision after confirming that they are not needed as historical references or by any tooling.

### 6.3 Active tests

- [ChecklistMigrationTests.swift](../Test/ChecklistMigrationTests.swift).
- [LocalProfileStoreTests.swift](../Test/LocalProfileStoreTests.swift).
- [PlenactBoardDocumentTests.swift](../Test/PlenactBoardDocumentTests.swift).

### 6.4 Server source

- [Server/api/common.php](../Server/api/common.php): shared transport/configuration/validation/database helpers.
- [Server/api/auth.php](../Server/api/auth.php): login/logout.
- [Server/api/users.php](../Server/api/users.php): registered-user directory and editor-created members.
- [Server/api/board.php](../Server/api/board.php): shared Board read/write.
- [Server/api/assignments.php](../Server/api/assignments.php): assignment-only mutations.
- [Server/cli/provision_board_editor.php](../Server/cli/provision_board_editor.php): private operator provisioning.
- [Server/SQL/001_plenact_demo_core.sql](../Server/SQL/001_plenact_demo_core.sql): initial shared-demo migration.
- [Server/tests/board_contract_test.php](../Server/tests/board_contract_test.php): local pure contract checks.

Server source is part of the repository. It is not part of the iOS compilation target.

---

## 7. Application architecture and state ownership

### 7.1 Current shape

```text
Plenact (@main)
└── AppRootView
    ├── complete Week lists, including archived lists
    ├── personal collections, including archived boards
    ├── optional local profile
    ├── Week bookmark IDs
    ├── navigation targets and current destination
    │
    ├── TodayHomeView
    │   ├── active Week list selection and focus preview
    │   ├── quick capture / full composer
    │   ├── Account & Settings
    │   ├── local search / label browsing
    │   └── TodayListDetailView
    │
    ├── ContentView (Week)
    │   ├── activeLists / archivedLists projected bindings
    │   ├── KanbanListView
    │   │   ├── shared KanbanCardView rows
    │   │   └── list actions / new-card / archived-card UI
    │   ├── CardDetailView
    │   ├── BoardHeader / settings
    │   └── Calendar / archived-list sheets
    │
    ├── BoardListsView (Lists)
    │   ├── Week directory
    │   ├── active personal collections
    │   └── PersonalCollectionBoardView -> ContentView
    │
    └── SavedCardsView (Saved)
        ├── available Week bookmarks
        └── archived full boards and Restore actions
```

### 7.2 Root ownership prevents archive loss

The root owns the **complete** Week snapshot. Active surfaces receive projections:

- `Binding<[KanbanList]>.activeLists`.
- `Binding<[KanbanList]>.archivedLists`.

An active-only setter retains the archived portion. An archive setter retains the active portion and forces supplied archived entries' flags true.

The root persists the complete Week array, not an active-only slice. This is an intentional data-safety invariant.

When refactoring:

- Keep one authoritative snapshot.
- Avoid competing persistence observers that save different partitions.
- Preserve complete active/archive records through mutations.
- Keep identity-based routing separate from display order.
- Keep collection bookmarks scoped to their collection.

### 7.3 Shared Board versus personal collection adapters

`ContentView` is reused for Week and personal collections.

It accepts:

- Active and archived list bindings.
- Optional pending list/card target bindings.
- Board-specific bookmark binding.
- Title/subtitle.
- Whether adding lists is allowed.
- Optional Close and Archive Board callbacks.
- A list-change persistence callback.
- A retained-attachment-list provider.

The app root and personal collection adapter own persistence appropriate to their context. Default constructor values are convenient for standalone views/previews; they are not a replacement for wiring complete real-app state.

For example, the archived-list binding defaults to constant empty state. Persistent archive functionality requires a writable binding.

### 7.4 Card detail's callback name is narrower than its actual use

`CardDetailView.onTitleToggle` emits complete edited card snapshots. It is used for much more than checking the title:

- Text edits.
- Dates.
- Checklists/actions.
- Comments.
- Members.
- Labels.
- Attachments.
- Dismissed generated activity.

Treat it as a complete-card update contract. Renaming the callback may improve clarity later, but only as a separate safe refactor covering all callsites.

### 7.5 Architecture direction

A focused observable planner store may eventually simplify root/mutation/persistence ownership. The architecture documents recommend incremental extraction when necessary, not a generic repository/networking framework in advance of a real requirement.

Recommended sequencing:

1. Lock down behavior with tests.
2. Extract mutation logic or state ownership only where it materially improves reliability.
3. Keep persistence compatibility unchanged during a structural refactor.
4. Separate UI cleanup from a storage migration.
5. Validate the same user workflows after each extraction.

---

## 8. Persistence inventory and durability boundaries

### 8.1 Current local stores

| Data | Storage | Key / location | Ownership |
|---|---|---|---|
| Complete Week Board | JSON in `UserDefaults` | `Plenact.Board.v1` | Root snapshot; `KanbanBoardPersistence` |
| Personal collections and archived boards | JSON in `UserDefaults` | `Plenact.PersonalCollections.v1` | Root shared collections |
| Local profile | JSON in `UserDefaults` | `Plenact.LocalProfile.v1` | `LocalProfileStore` |
| Label library | JSON in `UserDefaults` | `Plenact.LabelLibrary.v1` | `LabelLibraryStore` |
| Week bookmark IDs | Integer array in `UserDefaults` | `Plenact.SavedCardIDs.v1` | Root; sorted persistence |
| Today selected list | Integer in `UserDefaults` | `Plenact.Today.List.<year>-<month>-<day>` | Today selection |
| Recent searches | String array in `UserDefaults` | `Plenact.RecentSearches.v1` | Search store |
| Last-viewed Week list | Integer in `UserDefaults` | `Plenact.LastViewedList.v1` | New-card destination resolution |
| Load Example undo snapshot | JSON in `UserDefaults` | `Plenact.ExampleLoadUndo.v1` | Week replacement/undo |
| Card photo/video bytes | Private Documents files | `CardAttachments/` | `CardAttachmentStore` |
| Avatar image bytes | Private Documents files | `ProfileAvatars/` | `ProfileAvatarPhotoStore` |
| Remote session | iOS Keychain | App-specific remote-session service/account | `PlenactSessionStore` |

Do not copy raw preference databases, credentials, or real attachment content into logs or shared reports.

### 8.2 Ordered background Week saves

Week JSON encoding/decoding and defaults access run on a serial queue:

```text
Plenact.Board.persistence
```

This addresses main-thread waiting and preserves the submission order of snapshots.

The model tree gained `Sendable` conformances so immutable value snapshots can move to the background queue safely.

Important properties:

- Initial Board loading is asynchronous.
- A blank app surface is shown until initial loading completes.
- Each queued save begins and ends a database-activity operation.
- Encoding failure reports an error and retains the previous stored snapshot.
- Multiple rapid edits do not run unordered encodes that allow an older save to finish last.

### 8.3 What "save-first" does and does not mean

`PersonalCollectionStore.saveChecked` encodes and calls `UserDefaults.set` before the archive operation returns updated state.

This prevents an **encoding failure** from removing a visible board before preserving its recovery copy. It does not provide an independently proven physical-disk transaction or power-loss guarantee.

Likewise:

- Serial queue order is not crash-proof persistence.
- `UserDefaults.set` is not a backup system.
- A spinner ending is not a successful fsync attestation.
- Encoding successfully does not establish recovery across every lifecycle interruption.

Release preparation should explicitly test backgrounding, process termination, upgrades, and large snapshots. If stronger durability is required, choose a storage strategy and tested migration deliberately.

### 8.4 Decode failure behavior is not uniform

Verified behaviors include:

- Background Week load reports corruption, retains stored bytes, and displays starter data.
- Synchronous Week helpers still use simpler fallback/`try?` patterns.
- Personal collection load can return an empty collection array after decode failure.
- Label load can return the starter library after decode failure.
- Local profile load can return no profile after decode failure.
- Some save helpers silently return on encode failure.

Do not generalize "the app reports all storage errors." It does not yet have a uniform recovery policy.

**High-priority production investigation:** Retaining corrupt bytes during initial load is helpful, but edits to fallback/sample state could later replace those bytes. Establish a recovery/quarantine/backup/write-gating policy before claiming robust user-data protection.

This handoff did not modify those behaviors.

### 8.5 Cross-store consistency

Week data, collection data, labels, bookmarks, and undo state are separate preference values.

A whole-Week archive first stores a recovery collection, then clears the Week and bookmark state. Separate observers persist the resulting local changes.

That ordering deliberately favors retaining a recovery copy, but it is not a transaction spanning all preference keys. Test termination between phases and define how duplicate or partial states are recognized and recovered.

---

## 9. Domain models, identity, and migration contracts

### 9.1 Model tree

The active [Models.swift](../Src/Features/Boards/Models.swift) owns the principal Board model tree:

- `KanbanList`.
- `KanbanCard`.
- `KanbanChecklist`.
- `KanbanChecklistItem`.
- Typed checklist content.
- Reduced `KanbanChecklistActionDetail`.
- `KanbanComment`.
- Typed `CardAssignee`.
- Personal collection models/stores.
- Board persistence and sample data.

Attachments, labels, and profiles have sibling model files.

### 9.2 Stable IDs

| Record | Identity behavior |
|---|---|
| List | Integer ID scoped to its Board |
| Card | Integer ID unique within its Board |
| Personal collection | UUID |
| Checklist | UUID |
| Checklist action | UUID independent of row position |
| Comment | UUID |
| Assignee record | Stable assignment identity plus optional registered-user ID |
| Registered user | Server-generated stable user ID |
| Label/category | Stable string ID |
| Attachment | Stable metadata identity plus local filename or URL |

Do not assume card/list integer IDs are globally unique across Week and every personal collection. A new personal Board starts list IDs from its own local sequence.

If designing global search, deep links, export, or synchronization, carry Board/collection provenance along with card IDs. Do not merge multiple Boards into a dictionary keyed only by card integer ID.

### 9.3 ID allocation includes archives

New list/card allocation reserves existing archived identities:

- Active lists.
- Archived lists.
- Active cards.
- Archived cards nested in any relevant list.

Today focused-list creation also includes reserved archived lists.

Otherwise, a restored archived card could collide with a newly created card. Preserve this invariant in every creation/copy path.

### 9.4 Revision-0 checklist migration

Old snapshots encoded checklist items as strings and completion as indices.

Current decoding:

1. Accepts current typed item records.
2. Supports earlier stable-item records without rich content.
3. Falls back to revision-0 string arrays.
4. Generates repeatable item UUIDs from checklist identity and legacy position.
5. Transfers legacy completion indices into per-item completion.

Current encoding writes item records rather than the legacy completion-index payload.

The storage key remains `Plenact.Board.v1` because decoding supports previous representations. A key suffix is not permission to discard old data.

### 9.5 Completion compatibility bridge

The UI still has index-based checklist callbacks and a computed `completedItemIndices` bridge.

This bridge reconstructs typed item completion while preserving item identity/content. Index validity matters: callbacks must use the **original** checklist index, not the filtered visible-row position.

`ChecklistBlock.visibleItems` retains each item's original offset for that reason.

### 9.6 Assignee migration

Legacy member strings decode as manual assignees.

Typed records distinguish:

- Manual display text.
- Registered users with stable IDs and cached display names.

A display name match must not silently convert a manual person into a registered account.

Assignment does not grant permission to read or edit a Board.

### 9.7 Archive compatibility

- Old lists default to no archived cards.
- Empty archived-card arrays are omitted from encoded JSON.
- List archive flags default to active when absent.
- Personal collection `isArchived` is optional; absent values mean active.

These choices were made to preserve legacy decode behavior and, where possible, the existing remote document shape.

Nonempty local archives are intentionally refused by the current shared-document validator.

### 9.8 Profile compatibility

Profile tests cover older preference defaults, older avatar fields, and legacy color tokens.

Do not rename persisted palette/icon tokens or change profile decoding without fixtures. Avatar files and their stored filenames are part of the same compatibility boundary.

---

## 10. Today, navigation, capture, and selection

### 10.1 Primary navigation

The visible destinations are:

- **Today**
- **Week**
- **Lists**
- **Saved**

The internal destination case for Week is still `board`. Code naming and UI naming differ; do not treat that as a second Board.

The custom lower bar also includes **New**.

### 10.2 Initial Today selection

`TodayListSelection.initialListID` resolves:

1. A saved per-date ID that exists among supplied active lists.
2. A profile default ID that exists.
3. A list titled Monday, case-insensitively.
4. The first supplied list.
5. Nil if there are no lists.

This is a user-approved defaulting behavior introduced after older UI proposal documents were written.

Once an explicit effective Today selection exists, the computed lookup does not continually pick a different list if that ID becomes unavailable. The user should be able to choose again rather than being silently redirected.

**Release check:** Date rollover, timezone/calendar changes, and app resume deserve explicit tests. Do not assume date-scoped preferences automatically refresh all in-memory state at midnight.

### 10.3 Today is a projection

Today uses active Week lists, not personal collection cards.

The selected card collection excludes dividers. The focus preview shows the first three incomplete cards in existing order. The full selected list remains the plan; the preview is not a replacement priority model.

The full focused list view preserves card order and displays divider structure.

### 10.4 New and quick capture

There are several creation surfaces:

| Surface | Destination behavior |
|---|---|
| Today inline quick capture | Current selected Today list |
| Today full composer request | Requires a Today selection, then presents destination-capable composer |
| Lower-bar New outside Today | Week composer resolving last-viewed list, then profile fallback, then first active list |
| List's direct Add card row | That exact list |
| List Actions Add card | That exact list after safe sheet handoff |
| Focused Today list inline Add | Focused list, reserving archived IDs |
| Personal collection Add | Within the opened collection |

Do not unexpectedly route lower-bar New into a personal Board merely because it was recently viewed. The current scope is Week-oriented.

### 10.5 Deferred composer presentation

When the full Today composer is requested without a destination:

1. Record a deferred composer request.
2. Open the Today list picker.
3. Save the chosen list/date preference.
4. Dismiss the picker.
5. Yield before presenting the composer.

This separates presentation lifecycles. Avoid reintroducing simultaneous sheet replacement/dismissal races.

### 10.6 Navigation uses identities

Week list navigation uses a stable list ID. Card search can supply both list ID and card ID.

`ContentView.openPendingBoardTarget`:

- Validates the list.
- Scrolls it into view.
- Opens a matching card when supplied.
- Clears pending targets.
- Does not mutate content.

A missing target should not accidentally open another card with a reused or unrelated ID.

---

## 11. Search, labels, Saved, and Calendar

### 11.1 Local search scope

Search currently indexes the supplied active Week snapshot.

Scopes:

- **All:** card/list title context, card description/subtitle, checklist text, comments, member display names, labels/categories.
- **Boards:** list titles/subtitles, including empty matching lists.
- **Labels:** resolved label/category names.
- **Users:** member display names.

Divider cards are excluded from card results.

Archived cards and archived lists are excluded through active snapshots and explicit model/UI boundaries.

Do not describe this as global search across every personal collection. That is a future scope decision requiring collection-aware IDs.

### 11.2 Recent searches

The recent-search store:

- Trims surrounding whitespace.
- Ignores empty queries.
- Deduplicates case-insensitively.
- Moves the newest term to the front.
- Retains at most ten terms.
- Supports clearing.

Search terms may reveal personal intent. Treat history as local user data, not harmless debug telemetry.

### 11.3 Labels

The label library is app-wide and local.

Cards store label IDs; the library owns name, category, and color. Missing definitions are omitted from display resolution rather than silently deleting stored assignment IDs.

Today displays used labels grouped in library order, with counts and matching-card navigation.

The starter library has six categories and thirteen labels.

**Investigation:** Multiple surfaces hold local library copies and persist them. Test whether changes made in one presentation are visible in another without stale-state overwrites.

### 11.4 Saved is not a universal collection-bookmark browser

Saved currently includes:

- Available active Week cards whose IDs are bookmarked.
- Archived full personal boards, including archived Week snapshots.

Personal collection bookmarks remain within the collection record and are supplied to its Board/detail UI. The Saved tab does not aggregate all collection bookmarks.

Stale Week bookmark IDs do not produce rows, but they are not necessarily pruned from storage.

Avoid broad product copy such as "all your saved items everywhere" unless that behavior is implemented.

### 11.5 Calendar is a card-date browser

The Calendar entry is on the Board header, not a primary bottom tab.

It:

- Uses the current calendar and locale.
- Orders weekday symbols by the configured first weekday.
- Builds month rows with leading/trailing placeholders.
- Marks days with starting/due cards.
- Displays one result per matching card, including a combined starts-and-due label.
- Routes to the containing list.

It does **not**:

- Read or write device calendars.
- Model events with start/end time and timezone.
- Create notifications.
- Synchronize calendar accounts.
- Infer structured times from card titles.

The model stores Foundation dates; product/date semantics should be clarified before converting these into a true event system.

---

## 12. Personal lists and boards

### 12.1 Collection kinds

A **List** begins with a single column.

A **Board** begins with:

- Ideas.
- In progress.
- Done.

Each personal collection has:

- UUID.
- Title.
- Kind.
- Icon.
- Color.
- Its own lists/cards.
- Its own bookmark set.
- Optional archive flag.

### 12.2 Directory behavior

The Lists tab contains:

- A separate Week Board directory.
- Active personal collections.
- Search.
- Create/edit settings.
- Starter names/icons.
- Confirmed deletion.
- Collection reordering when search is empty.

Reordering active collections retains archived entries rather than dropping them.

### 12.3 Single-list rename

Renaming a List-kind collection updates its column and active/archived card `listTitle` values while preserving identity and archive content.

Do not reconstruct only active cards and accidentally discard archived ones during a rename.

### 12.4 Scope boundaries

At present:

- Today is Week-based.
- Lower-bar New is Week-based.
- Global Today search is Week-based.
- Load Example/Undo is Week-based.
- Personal collection cards are accessed within their collection.
- Labels are app-wide.

These boundaries should be explicit in onboarding and release descriptions.

### 12.5 Deletion versus archive

Deleting a collection is a confirmed destructive operation. Full-board archive is the reversible alternative for Board-kind collections.

Archive Board is not offered as a full-board workflow for a List-kind collection. Do not promise that every collection type appears in Saved's Archived Boards section.

Single-list collection edge behavior deserves product review: list archival can leave an empty collection, and the shared header allows adding a list to an empty Board surface even when normal list addition is disabled.

---

## 13. Archive and restore: the accepted product contract

### 13.1 Why archive was changed

Earlier "archive" behavior actually removed cards and pruned media. The owner requested a real retained archive with browsing and restoration.

The accepted result is **reversible local retention**, not a renamed delete action.

Cards destroyed by the earlier implementation cannot be recovered from the new archive retroactively.

### 13.2 Card archive

Entry points:

- List Actions -> Archive completed cards.
- Card detail -> upper-right Card actions -> Archive Card.
- Compact card row -> actions menu -> Archive Card.

Coverage:

- Week.
- Personal collections through shared Board components.
- Focused Open today's list.

Rules:

- Completed and incomplete task cards may be individually archived.
- Section dividers are not individually archived.
- Archive completed cards leaves dividers intact.
- Full card content survives: ID, completion, dates, checklists, comments, assignments, labels, attachments, text overrides, dismissed activity.
- Card detail submits current working edits before archiving and dismissing.
- Compact-row archive does not require opening detail.

### 13.3 Card browser and restore

List Actions includes **View Archived Cards** above **Archive completed cards**.

Restore:

- Removes the archived record.
- Appends it to the end of its original list.
- Preserves its completion status.
- Preserves identity and content.
- Does not prune attachment references.

Do not automatically uncheck a restored card. That would change an owner-approved behavior.

### 13.4 List archive

List archive:

- Marks the complete list archived.
- Transfers it out of the active partition.
- Keeps active cards and nested archived cards.
- Retains identities and attachment references.

Board options includes **View Archived Lists**.

List restore appends to the end of the original Board. This is why list reordering became especially important: a restored Monday can be moved back to the left edge.

Do not promise restoration to a historical exact index; that is not the current behavior.

### 13.5 Full-board archive

The owner explicitly requested full-board archiving for:

- Week.
- Personal Board-kind collections.

The action requires confirmation.

The archive preserves:

- Active lists.
- Archived lists.
- Active cards.
- Archived cards.
- Bookmarks.
- Attachment references.
- Existing nested content and completion.

Archived boards disappear from the active Lists directory and appear in **Saved -> Archived Boards**.

### 13.6 Whole Week behavior

Archiving Week:

1. Creates an archived personal collection representing the complete Week.
2. Saves the recovery collection snapshot first.
3. Updates shared collections.
4. Clears current Week lists and bookmarks.
5. Clears pending navigation targets.
6. Selects Saved.

An empty persisted Week remains empty after relaunch. It is not replaced simply because its array is empty.

### 13.7 Week restore never replaces current Week

This was an explicit owner decision.

A Week archive restores as a separate personal Board with a unique title:

- `Week Board (Restored)`.
- `Week Board (Restored) (2)`.
- Further suffixes as necessary.

The current Week Board remains unchanged.

This is a deliberate product contract, not an implementation inconvenience to "fix."

### 13.8 Personal-board save-before-dismiss fix

A review found a medium-risk behavior: archiving a personal Board previously changed in-memory state and dismissed before persistence success was established.

The fix:

- Added throwing `PersonalCollectionStore.archiveBoard(id:in:to:)`.
- Builds a copied full collection array.
- Saves it before returning.
- Parent assigns returned state only after success.
- Board dismisses only after the throwing callback returns successfully.
- Failure leaves the Board open and active and displays an error.

Tests cover success, encoding failure, and a missing Board.

When designing other destructive transitions, reuse the principle:

> Preserve recoverable data before removing the user's visible access to it.

### 13.9 Remote archive boundary

Current shared-demo schema version 1 does not support:

- Archived lists.
- Nonempty archived-card collections.
- Full local personal-board archives.

The client validator rejects archived list/card content. Do not work around that by silently deleting archive fields before uploading a real local Board. A future sync design must explicitly version and support the intended semantics.

### 13.10 Archive is not backup

The archive is stored in the same installation's local data.

It helps reverse in-app organization actions. It does not by itself protect against:

- App deletion.
- Device loss.
- Storage corruption.
- A migration bug.
- Container wipe.
- Overwriting the complete stored snapshot.

Explain this distinction clearly to users and in release materials.

---

## 14. List and card reordering

### 14.1 Existing menu path remains

List Actions -> Move list -> Move earlier / Move later is retained.

VoiceOver actions on the list title provide equivalent movement.

Do not make hold-and-drag the only way to reorganize a Board.

### 14.2 Hold-and-drag list implementation

The gesture:

- Starts from title/header text, not every point in the panel.
- Requires a 0.45-second hold.
- Allows twelve points of movement during hold recognition.
- Sequences into a drag in the named `WeekListsViewport` coordinate space.
- Supplies selection haptic feedback.
- Shows a lift/scaling effect unless Reduce Motion is enabled.
- Disables ordinary horizontal scrolling while held.

Normal swipes before the hold threshold should continue to scroll.

### 14.3 Reordering geometry

List centers are measured on the **outer untransformed layout container**.

This matters: measuring the translated dragged child caused a potential coordinate feedback loop. Keep pointer tracking and stable layout geometry separate.

The grab offset preserves where the user touched within the title region.

Crossing a neighbor's center moves one position. The shared helper preserves the complete list record.

### 14.4 Edge movement

While holding near either viewport edge:

- Check every 550 milliseconds.
- Move one neighboring position.
- Yield to layout.
- Scroll the held list into view.

The edge width is:

```text
min(64 points, viewport width * 0.18)
```

Exact comparisons are strict: equality at the inner threshold is not beyond the edge.

Invalid/nonfinite geometry produces no direction.

The delayed scroll happens after a task yield so layout can reflect the new order.

### 14.5 Cancellation and Reduce Motion

- Release or disappearance clears drag state.
- The task keyed by the held identity is cancelled.
- Expected cancellation is not reported as a failure.
- Unexpected movement errors reach the activity banner.
- Reduce Motion suppresses lift scaling and reorder/edge-scroll animations.

### 14.6 Card ordering

Card rows support native list edit-mode reordering. Destination adjustment accounts for removal before insertion.

The Board mutation clamps requested card destinations to valid positions. Content and divider identities remain unchanged.

Sort list performs localized title sorting **within divider-separated sections**, retaining divider structure.

### 14.7 Verification limitations

Unit tests verify order preservation, invalid targets, complete records, and exact edge thresholds.

The owner also reported that list movement worked.

Real-device touch feel, interrupted gestures, accessibility text sizes, landscape, and edge traversal through large Boards still deserve a dedicated acceptance pass.

---

## 15. The List Actions Add card fix

### 15.1 Reported symptom

The owner observed that **List Actions -> Add card** did not add/open the expected card workflow for the selected Week list.

### 15.2 Root cause

The callback changed the parent sheet directly from actions to new-card while the child also dismissed. The dismissal could close the newly presented form.

This was a presentation lifecycle race, not an ID allocation or database failure.

### 15.3 Accepted fix

The parent list view now:

1. Sets `opensNewCardAfterDismissal`.
2. Clears `activeSheet`.
3. Waits for the sheet's `onDismiss`.
4. Consumes the pending flag.
5. Presents `.newCard`.

The child no longer performs the conflicting dismiss in the Add card action.

The direct Add card row remains unchanged and uses the same creation form.

### 15.4 General lesson

Use one clear owner for a modal transition. Do not replace a sheet and independently dismiss from another layer at the same moment.

A production UI test should cover:

- Opening list actions.
- Choosing Add card.
- Entering a title.
- Confirming creation in the original list.
- Cancelling creation without mutation.
- Repeating the sequence.
- Rapid dismissal and interrupted presentation.

---

## 16. Card detail, checklist actions, and activity

### 16.1 Main card editor behavior

The detail editor holds local working values seeded from the supplied snapshot.

Main card changes synchronize as they occur through the optional complete-card callback:

- Title.
- Subtitle.
- Description.
- Completion.
- Start/due date.
- Checklists.
- Comments.
- Assignments.
- Labels.
- Attachments.
- Dismissed generated activity.

Closing does not undo edits that have already been emitted.

This differs intentionally from the member and reduced-action draft sheets.

### 16.2 Date editing

- Date rows open a graphical date picker.
- An unset binding getter returns the current time.
- Selection updates local state and emits the snapshot, then closes the sheet.
- Reset uses explicit clear flags.
- Nil optional override alone does not mean "remove the date."

Preserve these distinctions if changing snapshot update APIs.

### 16.3 Standard checklist actions

Supported:

- Add checklist.
- Add standard action.
- Edit action title.
- Toggle completion.
- Delete action.
- Rename checklist.
- Delete checklist.
- Check/uncheck all.
- Move checklist to top/up/down/bottom.
- Collapse checklist.
- Hide completed actions.

Deleting an action adjusts legacy completion-index mapping while retaining other typed action records.

The main toggle helper guards checklist existence but relies on the caller for a valid item index. Validate those contracts if callback architecture changes.

### 16.4 Linked-card actions

A linked action stores a stable card ID and opens the resolved card.

Its completion state is independent from the target card's completion.

If the target is unavailable, show recoverable unavailable copy. Do not redirect to a different card or silently delete the action.

**Investigation:** The current detail lookup derives from `availableLists`, generally other lists. Verify same-list links, links after moves, links to archived content, and links in copied lists. The existence of linked-row UI does not prove every possible reference resolves.

### 16.5 Reduced Action Detail

An Action Detail:

- Belongs to its checklist item.
- Does not appear independently as a Board card.
- Has description, nested checklists, and comments.
- Uses a local draft editor.
- Saves explicitly, preserving stable detail identity.
- Cancels without submitting changes.

Starter nested actions are standard actions only.

Remaining authoring work includes:

- Creating/converting rich action types.
- Nested checklist authoring.
- Destructive removal confirmation for populated detail.
- Any deliberate promotion to a full Board card.

Do not advertise those authoring controls as complete.

### 16.6 Activity is not a complete audit log

There are stored comments and generated activity entries.

Generated entries include fixed display copy; the row timestamp currently reads **Today at 7:00 AM** rather than a persisted event time.

Dismissal stores generated-entry IDs on the card.

This is not a reliable per-edit history, forensic log, or collaboration audit trail.

### 16.7 Actor-name consistency

The main card comment composer currently creates comments with the fixed **Justin Reina** author name.

Generated activity and reduced Action Detail comments use `currentUserName`.

This was documented rather than changed during the header work.

Before release, decide how local profile identity should influence authorship and remove developer-specific defaults where appropriate. Preserve existing historical comments unless a deliberate migration is approved.

### 16.8 Custom deletion gestures

Checklist and activity rows:

- Require horizontal-dominant movement.
- Use a twelve-point drag recognition threshold.
- Clamp visible translation to 72 points.
- Reveal deletion beyond 36 points.
- Invoke deletion directly beyond 120 points.

There is no separate confirmation dialog for the full-swipe action. Accessibility labels on the destructive button exist; verify that the button is discoverable and usable without performing the gesture.

---

## 17. Attachments and avatar media

### 17.1 Card attachments

Supported:

- System-picked photos.
- System-picked videos.
- Validated HTTP/HTTPS links.
- Clipboard link entry.
- Local media preview.
- External link opening.

Some source options explicitly show coming-soon notices rather than importing content.

Do not advertise cloud-document or external-provider workflows as implemented.

### 17.2 Storage

Imported media is written atomically under unique filenames in private Documents storage.

Board JSON contains metadata, not embedded binary media.

Copying a card/list may share references to the same file. Therefore:

> Removing one record must not delete media still referenced by another active, archived, personal, or undo snapshot.

### 17.3 Partial import failure

Photo/video import processes selected items individually.

- Successful imports are retained.
- Failed transfers/saves cause a user notice.
- Selection and source presentation are cleared.
- The updated attachment collection is synchronized.

This is partial-success behavior, not an all-or-nothing transaction. Test both successful and mixed-result imports.

### 17.4 Retention set

Board pruning collects file references from:

- Current active lists.
- Current archived lists.
- All cards, including nested archived-card collections.
- Externally retained personal collections.
- Load Example undo snapshots.

Do not simplify the retention walk to `lists.flatMap(\.cards)`; that would lose archives and recovery snapshots.

### 17.5 Known cleanup asymmetry

Board update/delete paths may invoke pruning.

Focused Today update/delete helpers do not directly prune files.

Collection deletion and avatar cleanup have their own behavior.

**Investigation:** Design one consistent reachability-based media cleanup policy and test every mutation entry point. Do not "fix" orphan accumulation by eager deletion that destroys referenced files.

Cleanup errors currently use silent/best-effort paths in some stores. A production policy should distinguish harmless delayed cleanup from user-visible failures to save/load content.

### 17.6 Avatar files

Profile avatar images use `ProfileAvatars/` and stored filenames.

Current tests include:

- File round trip/removal.
- Crop pan constraints.
- Bounded JPEG export.

Verify picker cancellation, replacing a photo, removing a profile, large source images, and file-recovery behavior on physical devices.

### 17.7 Privacy boundary

Private-container storage is local storage. It is not a guarantee of:

- Explicit encryption.
- Multi-device backup.
- Shared access controls.
- Cloud media sync.
- Secure collaboration.

External links leave the app's local data boundary and may contact third-party sites. Product copy and privacy explanations should reflect that.

---

## 18. Local profiles and accessibility preferences

### 18.1 Local identity

The local profile includes:

- UUID and creation date.
- Display name.
- Optional local email/context text.
- Avatar colors/icon/photo.
- Preferred Today list.
- Reduced-content preference.
- Larger-controls preference.
- Navigation-label visibility preference.

The email is unverified local text. It is not an authentication identity.

### 18.2 Removal semantics

Removing the local profile removes profile data and associated profile photo through the relevant settings path.

It must not remove:

- Week lists/cards.
- Personal collections.
- Labels.
- Card attachments.
- Comments.
- Today choices.

Existing tests verify profile removal does not clear unrelated preferences.

### 18.3 Preference effectiveness must be measured

There are model values and settings toggles for reduced content and larger controls. Some earlier documentation describes their intended effects.

**Investigation:** Verify their current use on each actual UI control. A stored flag or computed height helper is not evidence that the complete current Today layout responds visibly.

System Dynamic Type, VoiceOver, contrast, and Reduce Motion remain authoritative. A custom "larger controls" preference should not replace system accessibility support.

### 18.4 Future online identity

If online accounts are added:

- Keep local profile and remote authentication concepts separate.
- Define linking explicitly.
- Do not promote a local email string to a verified account.
- Do not convert a manual assignee by matching display name.
- Preserve offline local usage if that remains part of the product promise.
- Define account removal separately from local profile removal and Board deletion.

---

## 19. Database activity and error feedback

### 19.1 Owner request

The owner noticed UI freezing or waiting during database responses and asked for a busy spinning-wheel notifier so users knew to be patient.

Investigation found both:

- Local Board encode/decode work affecting UI responsiveness.
- Remote API source needing request activity tracking.

The owner chose feedback for both.

### 19.2 Shared operation accounting

`DatabaseActivity` is a main-actor observable singleton.

Each operation:

1. Begins with a UUID and message.
2. Remains in an operations array.
3. Ends by its own UUID.

The spinner remains active until **all** tracked operations finish.

One request must not hide another request's spinner.

### 19.3 Banner behavior

- Displays the first active operation's message.
- Says "Please wait a moment."
- Does not block normal interaction just because work is ongoing.
- Combines its accessibility content.
- Exposes a `databaseActivity` accessibility identifier.
- Can also display a persistent error.
- Errors remain until dismissed.

The banner may cover top content on small screens; validate layout and focus effects rather than assuming overlays are harmless.

### 19.4 Remote request lifecycle

All future callers of the API client participate in the same activity accounting.

Transport success, failure, and cancellation end their operation.

Remote mutation controls are intended to remain disabled through mutation and follow-up refresh.

The shared-demo settings UI being absent means remote activity integration does not expose online sync automatically.

### 19.5 Future performance work

Do not add a spinner as a substitute for fixing main-thread work.

Measure:

- Encoding duration and queued snapshot volume.
- Main-thread frame stalls.
- Save frequency during typing.
- Large archives and collection arrays.
- Media thumbnail/preview memory.
- Startup cost.
- Whether synchronous collection/label/profile stores become noticeable.

If debouncing/coalescing saves, define lifecycle flushing and failure recovery first. An optimization that drops the final edit is not an improvement.

---

## 20. Shared-demo API and deployment evidence

### 20.1 Source-level boundary

The remote document contains:

- `schema_version`.
- `board_key`.
- Ordered lists/cards.
- `label_library`.

Server revision, actor, time, and origin live in response metadata, not editable client content.

The current logical board key is `shared-demo`, schema version 1.

### 20.2 Transport and session

The client:

- Requires a valid HTTPS base URL.
- Uses a configured API directory.
- Has a twenty-second request timeout in the inspected request path.
- Uses bearer sessions.
- Stores remote sessions in Keychain.
- Validates encoded body size.
- Rejects plain HTTP configuration.
- Tracks database activity.

Request/response JSON and serialized Board documents use a **1,048,576-byte (1 MiB)** ceiling in the documented contract.

Test exact byte boundaries, including envelopes. Character count is not UTF-8 byte count.

### 20.3 Routes

| Route | Purpose | Permission model |
|---|---|---|
| `POST auth.php` | Login/logout | Per-user session |
| `GET users.php` | Active directory | Authenticated demo users |
| `POST users.php` | Create member account | Board editor |
| `GET board.php` | Read shared snapshot | Authenticated active demo users |
| `PUT board.php` | Write full canonical snapshot / approved first seed | Board editor |
| `POST assignments.php` | Assignment-only change | Member's own assignment; editor may manage active users |

Writes carry expected revision. Stale revisions should conflict rather than silently overwrite.

### 20.4 Shared-demo ownership

Jim is the sole canonical Board-content editor.

Other active members may browse shared demo data and manage their own registered assignment. Assignment is not canonical content-edit permission.

The directory and Board are intentionally shared among authenticated demo users. They are **not private** from those users.

Use only approved synthetic, nonsensitive data.

### 20.5 Seed boundary

The initial seed uses synthetic `SampleData`, not:

- Current local Week.
- Personal collections.
- Local profile.
- Personal comments.
- Card photo/video bytes.
- Private local filenames as remotely usable media.

The known starter manual assignment is mapped to the editor's verified user ID through an explicit rule. Do not generalize this into display-name identity matching.

### 20.6 Repository-reported deployment

The newer [Server README](../Server/README.md), [SQL README](../Server/SQL/README.md), and [initial import record](Database/Initial-Demo-Import-Plan.md) report:

- Initial migration applied on October 3, 2026 after a disposable-database compatibility test.
- Seven expected InnoDB tables.
- Bluehost server version reported as `5.7.44-48`.
- PHP API deployed at the configured HTTPS endpoint on PHP 8.2.
- Editor provisioning.
- Synthetic Board seed revision 1.
- Seven lists, forty-nine cards including dividers, and thirteen labels.
- Editor/member sign-in and readback.
- Local app data reported unchanged.

**This handoff did not contact the host or independently confirm those live facts.**

Do not rerun migration 001 because an older document still says undeployed. Inspect deployment records and obtain authorized live evidence first.

### 20.7 Remaining demo verification

Repository records list remaining checks:

- Assignment-only member write restrictions.
- Editor versus member canonical-write permissions.
- Stale revision conflicts.
- Seed retry/idempotency.
- Linked-card reference validation.
- Backup/restore.

These are not replaced by the local PHP pure-validator test.

### 20.8 Production is a separate architecture decision

Before handling real remotely stored user data, decide:

- Private versus shared ownership.
- Board/organization membership.
- Per-record authorization.
- Directory visibility and consent.
- Identity/provider strategy.
- Session/recovery/deletion workflows.
- Data export/retention.
- Audit/provenance semantics.
- Conflict resolution/offline edits.
- Media storage and deletion.
- Environment separation.
- Backup and operational ownership.

A shared demo with a single editor does not establish production multi-tenancy.

### 20.9 Secret handling

Never place passwords, tokens, database credentials, private configuration, or authenticated hosting URLs in this document, source, fixtures, logs, screenshots, or chat.

Keep runtime configuration outside the web root and separate administrative provisioning from runtime access.

Existing documentation warns that any previously exposed credential must be rotated/revoked privately if still valid. Do not reproduce it.

A production security review should be a separate authorized work item with concrete scope. This handoff is not that review.

---

## 21. Documentation reconciliation

### 21.1 Known conflicts

| Documentation area | Older statement | Current evidence / action |
|---|---|---|
| Root README and older architecture | No remote database/account system | Accurate for mounted normal local UI, incomplete for repository/demo infrastructure |
| Database overview / data-contract status | Migration/API not deployed | Newer Server/SQL/import documents report deployment; do not rerun based on stale status |
| Users overview | Client exists but no deployment | Reconcile against newer deployment records |
| Today UI proposal | Two tabs and no inferred starter selection | Current app has four destinations and approved saved/default/Monday/first resolution |
| Today navigation proposal | Open selected list in Board | Current Open today's list has a dedicated focused vertical view, with Open in Week |
| Board product boundary | Members are only free text | Active models support typed manual/registered records; local editor remains manual-oriented |
| Model description | List contains only ID/title/cards | Now includes archived cards and list archive state |
| Profile documentation | Basic initials/palette profile | Source/tests include avatar icons, richer color compatibility, photo/crop behavior |

### 21.2 Reconciliation approach

Do not simply delete old architecture documents.

For each:

1. Identify whether it is a proposal, historical record, or current behavior reference.
2. Add a clear status/date.
3. Update implemented behavior.
4. Preserve useful future design principles.
5. Link to current source/contracts.
6. Keep deployment facts qualified until live evidence is available.

### 21.3 Style and headers

The owner requested detailed file/function documentation following [style.swift](Style/style.swift).

Completed header work:

- 90 explicit functions/initializers/computed declarations in the app shell.
- 67 in the active Board ContentView.
- 63 in the active Board CardDetailView.

These counts exclude synthesized memberwise initializers and ordinary closure bodies. Preview documentation is separate where present.

Headers include:

- `@fcn`.
- `@brief`.
- `@details`.
- Input parameters.
- Return type/meaning.
- Relevant preconditions/postconditions.
- Notes for edge cases and ownership.

The documentation-only changes were checked against executable lines to prove they did not change behavior. Preserve accurate contracts; do not add boilerplate guarantees that the implementation cannot support.

---

## 22. What we changed and what we learned

### 22.1 Recent delivered work

| Commit | Subject / area |
|---|---|
| `5ddce3a` | Show database activity and move Board persistence off the UI thread |
| `bf1aa4c` | Persistent archive and restore for cards, lists, and boards |
| `c8e0ccb` | Archive Card in Board and Today compact-row menus |
| `17257c6` | Hold-and-drag list reordering |
| `e273b46` | Correct List Actions -> Add card presentation |
| `5a39025` | Detailed comment/header updates |

Earlier related commits in inspected history include personal collections, Today Monday defaults/New destination behavior, Calendar/Lists navigation, Load Example, and filtered direct-card search.

Use actual Git history rather than relying on earlier conversation hash references, which may no longer match current history.

### 22.2 Lessons from the busy indicator

- Diagnose where work actually happens before assuming remote database latency.
- Feedback and background execution solve different problems.
- Track overlapping operations by identity, not one boolean.
- Clean up activity on cancellation/failure as well as success.
- Keep snapshot ordering deterministic.
- Fix concurrency typing rather than hiding warnings with unsafe assertions.

### 22.3 Lessons from archive work

- "Archive" has a product meaning: retained, discoverable, restorable.
- Wire every relevant surface: detail, compact rows, focused Today, Week, personal collections.
- Archives must participate in ID allocation and media reachability.
- Model decode compatibility and empty-field encoding matter.
- Archive state belongs with retained content.
- Active-only presentation must not become active-only persistence.
- Restore destination/title/order must be explicitly chosen.
- Save recovery content before removing visible access.

### 22.4 Lessons from testing

- Do not infer sample completion state; one early test incorrectly assumed a sample card was incomplete.
- Make fixture state explicit for the behavior being tested.
- Parallel simulator testing stalled once; disabling parallel testing produced reliable runs.
- Test exact geometry/body-size thresholds, not merely "near the edge" or "large enough."
- Unit helpers do not prove presentation lifecycle behavior.
- Hands-on owner confirmation complements tests but does not establish the entire release matrix.

### 22.5 Lessons from drag geometry

- Measure stable layout, not already translated views.
- Preserve the initial grab offset.
- Separate normal scrolling from active list drag.
- Yield for layout before targeted scrolling after reorder.
- Provide non-gesture alternatives.
- Treat cancellation as expected control flow.

### 22.6 Lessons from sheet handoff

- Modal ownership must be explicit.
- Parent presentation state and child dismissal can conflict.
- Dismiss-then-present is safer than replacement plus independent dismissal for this workflow.
- Test actual form appearance and destination, not just whether a callback exists.

### 22.7 Lessons from documentation

- Detailed headers exposed real ownership and default-value nuances.
- Document actual behavior rather than aspirational guarantees.
- Existing comments can be stale even when code compiles.
- Large documentation patches can be verified mechanically as comments-only.
- The next agent should benefit from these contracts, but still validate them before changing behavior.

---

## 23. Fresh validation baseline and how to reproduce it

### 23.1 Fresh results for this handoff

On October 4, 2026:

| Validation | Result |
|---|---|
| Full shared-scheme iOS unit tests | **57 tests, 0 failures** |
| Checklist migration suite | 10 tests within the full run |
| Local profile suite | 9 tests within the full run |
| Board document/activity/archive/reorder suite | 38 tests within the full run |
| PHP pure contract-validator script | **Board contract tests passed** |

The full iOS run built and tested the current app/test code using Xcode 27.0 and the installed iPhone 17 simulator on iOS 27.0.

The log included App Intents metadata extraction warnings stating that there was no AppIntents framework dependency. Those are not evidence that app functionality failed; preserve and assess actual build output rather than claiming an entirely warning-free toolchain.

### 23.2 Reproduce the full iOS run

From repository root:

```sh
xcodebuild -showdestinations \
  -project Plenact.xcodeproj \
  -scheme Plenact
```

Use an installed destination. The known working destination on this machine was:

```sh
xcodebuild \
  -project Plenact.xcodeproj \
  -scheme Plenact \
  -destination 'platform=iOS Simulator,id=0B8E40D1-3620-48AC-BAC2-38B1F2B81CBC' \
  -parallel-testing-enabled NO \
  test
```

The simulator UUID is machine-specific. Discover it rather than hardcoding it into shared CI.

### 23.3 Focused test run

For Board/archive/activity/reorder changes:

```sh
xcodebuild \
  -project Plenact.xcodeproj \
  -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:PlenactTests/PlenactBoardDocumentTests \
  test
```

For a model compatibility change, include the checklist suite in the same runner:

```sh
xcodebuild \
  -project Plenact.xcodeproj \
  -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:PlenactTests/PlenactBoardDocumentTests \
  -only-testing:PlenactTests/ChecklistMigrationTests \
  test
```

Use the smallest relevant test selection during iteration, then run the full suite for a release candidate.

### 23.4 PHP contract run

```sh
php Server/tests/board_contract_test.php
```

This uses pure helpers and synthetic fixtures. It does not require a database connection and does not prove deployed route authorization, MySQL transactions, credential grants, or backup recovery.

### 23.5 Existing coverage

The suites cover, among other things:

- Legacy checklist and member migration.
- Rich checklist round trips.
- Starter weekday content and references.
- Profile preference/avatar compatibility.
- Avatar file/crop helpers.
- Recent search and scope behavior.
- Last-viewed and initial Today selection.
- Example-load undo snapshots.
- Personal collection order/rename/persistence.
- Stable remote identity validation.
- Plain HTTP rejection.
- Exact JSON body limit.
- Mocked API activity success/failure/cancellation.
- Overlapping spinner accounting and error dismissal.
- Ordered background saves.
- Encode/decode failure preservation.
- Card/list/board archives and restore.
- Save-first personal-board failure behavior.
- Archive ID reservations and search exclusions.
- List reorder record preservation and exact edge thresholds.

### 23.6 What the fresh run did not prove

It did not establish:

- Minimum-iOS-17 runtime behavior.
- Physical-device responsiveness.
- UI automation of sheets, drag, and menus.
- VoiceOver usability.
- Every Dynamic Type/contrast/orientation combination.
- Release signing or an App Store archive.
- Real deployed API permissions.
- Production privacy/account compliance.
- Large-data memory/performance.
- Reliable recovery after crash between separate preference writes.
- Successful TestFlight installation or upgrade.

These remain explicit release gates.

---

## 24. Release-readiness investigation register

The following are **investigation priorities**, not vulnerability findings or a claim that every item is a confirmed defect.

### 24.1 Release-gating reliability and product-boundary work

| Priority | Area | Why it matters | Required evidence |
|---|---|---|---|
| Gate | First-release scope | Local-only and connected products have different obligations | Owner-approved capability/non-capability statement |
| Gate | Data recovery | Fallback states and silent decode paths can obscure user data | Corrupt/legacy/upgrade fixtures plus recoverable UI/write policy |
| Gate | Archive durability | Separate preference writes are not one transaction | Termination/relaunch tests around every archive phase |
| Gate | Customer data export/recovery promise | Local archives are not backups | Explicit product policy and tested workflow if promised |
| Gate | Signing/App Store identity | Current development identifier may or may not be final | Owner-confirmed Developer/App Store Connect mapping |
| Gate | Privacy declarations | Local profile, media, preferences, dormant network code all matter | Actual data-flow inventory and current Apple requirement review |
| Gate if remote ships | Production account/authorization design | Shared demo is not private tenancy | Approved design and independent verification |
| Gate | Accessibility basics | Central to intended usefulness | Device-based VoiceOver/Dynamic Type/contrast results |
| Gate | Minimum OS support | Tests ran on newer runtime, not iOS 17 | Supported-version device/simulator evidence |

### 24.2 High-value behavioral investigations

- Date rollover and persisted Today selection on resume.
- Removing/archiving today's selected list while its focused view is open.
- Stale navigation targets after mutation.
- Same-list, copied-list, moved, deleted, and archived linked-card targets.
- Label catalog updates across multiple view-held copies.
- Actor-name consistency and developer-specific defaults.
- Invalid/blank title handling in inline detail editing versus validated composers.
- Consistent media cleanup across Week, Today, collections, and undo.
- Orphan avatar files after failed/cancelled replacement.
- Very long card titles, comments, and labels.
- Large archives and high-frequency typing saves.
- Single-list personal collection archive/empty-state behavior.
- Bookmark visibility after archive and restore.
- Whether reduced-content/larger-controls settings affect current rendered surfaces.
- Copy-list metadata expectations: active cards copy, archives do not; list defaults may differ.
- Generated activity/time copy that could mislead users.
- Screen overlays hiding important controls on small displays.

### 24.3 Do not conflate investigation with implementation

For each item:

1. Reproduce or measure the behavior.
2. Establish the intended product contract.
3. Add a regression test where practical.
4. Fix the root cause.
5. Record evidence.

Avoid adding speculative workarounds just because an item appears in this register.

---

## 25. Production data protection and migration strategy

### 25.1 The first obligation is preservation

Existing local data may already be valuable to the owner. Release preparation must not wipe it to make a cleaner first-launch experience.

Never:

- Replace a valid Board with revised sample data.
- Clear defaults to work around decode errors.
- Delete media before computing complete retained references.
- Change ID meaning without migration.
- Upload local content simply because an API exists.

### 25.2 Proposed recovery baseline

**Recommendation:** Establish a recovery design before a public release with meaningful user data.

Consider:

- A known-good previous snapshot.
- A quarantine copy of unreadable bytes.
- Explicit error/recovery UI.
- Separation between "no data exists" and "data exists but could not be loaded."
- Gating saves from fallback/sample state until recovery is understood.
- Exporting recoverable data through an approved user action.
- A crash-safe write sequence if migrating beyond preferences.

The owner must decide the user-visible recovery/export policy. Do not imply a backup exists before implementing it.

### 25.3 If moving away from UserDefaults

Possible storage choices should be evaluated against concrete needs, not fashion.

Decision criteria:

- Atomic update requirements.
- Data volume.
- Query needs.
- Archive size.
- Media-reference consistency.
- Migration complexity.
- Offline behavior.
- Testability.
- Supported OS/toolchain.
- Export/recovery.

A migration should:

1. Read supported old formats without modifying them.
2. Validate identities and links.
3. Include active and archived content.
4. Include collection bookmarks and relevant preferences.
5. Preserve media filenames or migrate them with a mapping.
6. Write the new store atomically where supported.
7. Verify round-trip counts and full content.
8. Record migration completion independently.
9. Retain rollback/recovery material until policy allows cleanup.
10. Handle interruption and retry idempotently.

Do not combine a storage migration with a broad UI rewrite.

### 25.4 If adding export/import

Define:

- Complete versus selected-board export.
- Schema/version envelope.
- Media inclusion/packaging.
- Privacy warning.
- ID collision handling.
- Labels/catalog merge behavior.
- Archive retention.
- Imported bookmarks.
- Inactive/missing linked targets.
- Validation and size limits.
- Partial versus atomic import.
- Recovery on failure.

JSON alone is not a complete backup if it contains filenames pointing to unexported media.

### 25.5 If adding synchronization

Decide:

- Local authority versus remote authority.
- Offline mutation queue.
- Conflict resolution.
- Board-scoped identities.
- Archive semantics.
- Media upload/download.
- Deletion tombstones and retention.
- Account unlink/logout effects on local data.
- Initial opt-in migration.
- Retry/idempotency.
- Schema/version negotiation.

Do not silently filter out local archives to make the current remote validator accept a Board.

---

## 26. Accessibility, cognitive load, and device validation

### 26.1 Accessible success criteria

A user should be able to:

- Understand where they are.
- Find today's selected list.
- Create a card in the intended destination.
- Complete or reopen work.
- Read full context.
- Archive and restore without fear of unintended deletion.
- Reorder without relying on one gesture.
- Know whether the app is saving or has failed.
- Recover from unavailable content.

Validate these jobs, not merely the presence of accessibility modifiers.

### 26.2 Dynamic Type

Test:

- Default size.
- Large standard sizes.
- Accessibility sizes.
- Long localized/user-entered text.

Fixed quarter-screen card heights and line-limited summaries may be acceptable previews, but they must not make essential controls or text unreachable.

Verify detail access is obvious, title/action buttons do not overlap, and lower-bar New does not cover content.

### 26.3 VoiceOver

Review:

- Navigation order.
- Meaningful labels for icons.
- Completion state.
- Card/list context.
- Archive versus delete distinction.
- Restore destination.
- Move earlier/later actions.
- Missing linked-card announcements.
- Busy and error feedback.
- Destructive buttons inside custom swipe containers.
- Focus after sheets close.

### 26.4 Reduce Motion and contrast

Verify:

- Drag lift/animation behavior.
- Edge scrolling.
- Lower-bar shake/phase animation.
- Header fade transitions.
- Material surfaces over paper textures.
- White card/background assumptions in dark mode.
- Color-independent meaning for labels/completion.

Do not assume every animation already honors Reduce Motion because list drag does.

### 26.5 Touch targets and gesture alternatives

Aim for comfortable, generally 44-point targets where practical. Review small metadata and menu controls individually.

Existing list movement alternatives are a good pattern.

Potential improvements should retain the owner's compact scan-friendly design without making important actions hidden or swipe-only.

### 26.6 Device matrix

At minimum choose:

- Small supported iPhone.
- Standard-size iPhone.
- Large iPhone.
- Oldest supported runtime/device combination.
- Current runtime/device.
- Portrait and each supported landscape orientation.
- A real device for photo/video and gesture work.

If expanding to iPad, that is a separate design/release change, not a checkbox.

---

## 27. Automated and manual acceptance matrix

### 27.1 Data and lifecycle

| Scenario | Expected result | Evidence needed |
|---|---|---|
| Fresh installation | Weekday starter Board; usable Today selection | Device/UI check plus fixture tests |
| Existing valid snapshot | Loads unchanged | Upgrade fixture and relaunch |
| Explicit empty Week | Stays empty | Existing helper test plus real lifecycle |
| Corrupt Week JSON | Visible recoverable error; original bytes preserved | Existing test plus future overwrite/recovery test |
| Corrupt collections/labels/profile | Clear recovery policy, not unnoticed loss | New tests after policy decision |
| Rapid edits | Latest submitted state survives | Existing ordered-save test plus lifecycle stress |
| Background/force termination | Defined final-save behavior | Physical-device or controlled lifecycle test |
| Upgrade from older models | IDs/content preserved | Migration fixtures |

### 27.2 Creation and navigation

| Scenario | Expected result |
|---|---|
| Today inline capture | Selected Today list receives one trimmed card |
| Blank quick capture | No card created |
| No Today selection -> full composer | Choose destination, then show composer |
| Lower New outside Today | Week destination resolves predictably |
| List Actions -> Add card | Form appears after actions dismissal for the same list |
| Cancel new-card form | No mutation |
| Search card result | Exact card detail in exact list |
| Search Board/list result | Exact existing list, including empty matching lists |
| Missing target | Safe unavailable/selection path, not wrong content |

### 27.3 Archive and restore

| Scenario | Expected result |
|---|---|
| Archive incomplete card | Retained, disappears from active views |
| Archive completed cards | Only completed non-divider tasks transfer |
| Archive from compact row | Same model path as detail, without opening detail |
| Archive from edited detail | Latest edits retained before dismissal |
| Restore card | Appends to original list; remains complete if previously complete |
| Archive list | All nested content retained; hidden from active views |
| Restore list | Appends to original Board |
| Archive full Week | Recovery Board appears in Saved; Week becomes empty |
| Restore Week archive | Separate unique personal Board; current Week unchanged |
| Archive personal Board encode failure | Open/active Board remains, error visible |
| Repeated archive/restore | Stable IDs, no duplicated/lost records |
| Relaunch after archive/restore | Complete state survives |
| Archive containing media | All referenced files remain readable |

### 27.4 Ordering

| Scenario | Expected result |
|---|---|
| Move earlier/later menu | Correct bounded change |
| Hold title then drag | Held list follows pointer and reorders |
| Swipe without hold | Ordinary horizontal scrolling |
| Hold near edge | One-position movement every 550 ms with layout-safe scroll |
| Release/interruption | No orphaned held state or ongoing edge movement |
| Reduce Motion | No drag lift scaling/reorder animation |
| VoiceOver movement | Equivalent menu/action capability |
| Card reorder | Correct destination after source removal |
| Sort with dividers | Each section sorted; divider structure retained |

### 27.5 Detail and media

| Scenario | Expected result |
|---|---|
| Main detail text edit | Same canonical card updates |
| Member Cancel | No submitted assignment change |
| Member Save with pending valid draft | Draft included once after normalization |
| Reduced Action Detail Cancel | No persisted change |
| Reduced Action Detail Save | Stable detail/item IDs retained |
| Linked target deleted | Unavailable state, no silent retarget |
| Mixed media import success/failure | Successful media kept; notice for failures |
| Remove shared/copied media reference | File survives while any retained reference exists |
| Avatar replace/cancel/remove | Defined file lifecycle, no broken visible profile |
| Invalid clipboard link | Notice; no attachment added |

### 27.6 Remote checks, only if approved and in a disposable environment

- Editor/member login and logout.
- Disabled/expired session behavior.
- Directory field minimization.
- Member cannot write canonical content.
- Member cannot manage another user's assignment.
- Editor assignment scope.
- Stale expected-revision rejection.
- Initial seed retry behavior.
- Exact size limits.
- Unavailable media handling.
- Recovery after transport timeout.
- Backup restoration.
- No local Board mutation/upload without explicit action.

Do not run mutation tests against live data without owner authorization and recovery preparation.

---

## 28. Recommended production work phases

### Phase 0: Establish the release contract

Deliver:

- One-page first-release scope.
- Supported devices/OS/orientations.
- Data/privacy promise.
- Local-only versus connected decision.
- Intended audience and nonmedical language.
- App identity/distribution ownership.
- Explicit out-of-scope features.

Exit criterion: the owner approves what the product will honestly ship.

### Phase 1: Baseline and data safety

Deliver:

- Reproducible build/test commands.
- Current release-build evidence.
- Fixture inventory.
- Recovery/error policy.
- Lifecycle/large-data tests.
- Archive preservation and media reachability tests.
- Migration plan if storage changes.

Exit criterion: critical user-data failure cases have defined, tested behavior.

### Phase 2: Product polish and workflow reliability

Deliver:

- Fix verified release-blocking UX issues.
- Remove or contextualize developer-specific/synthetic copy.
- Verify creation destinations and sheet transitions.
- Validate archive/restore and ordering on device.
- Make settings demonstrably effective or hide/defer unsupported controls with approval.
- Reconcile feature status documentation.

Exit criterion: core user jobs work predictably without misleading promises.

### Phase 3: Accessibility and performance

Deliver:

- Device/accessibility matrix results.
- Measured main-thread/startup/save performance.
- Media memory findings.
- Long-text/layout results.
- Focus and gesture alternatives.

Exit criterion: supported users/devices can complete core jobs comfortably.

### Phase 4: Distribution readiness

Deliver:

- Signed Release archive.
- Final version/build numbering.
- Required privacy manifests/declarations based on actual data flows.
- Store listing/assets/support/privacy URLs.
- TestFlight plan and review notes.
- Recovery/rollback plan for builds and data.

Exit criterion: a tested candidate installs through the intended distribution channel.

### Phase 5: Beta validation

Deliver:

- Structured tester tasks.
- Known-limitations note.
- Triage process.
- Regression fixes and evidence.
- Explicit release/no-release recommendation.

Exit criterion: owner-approved confidence based on real beta evidence.

### Phase 6: Release and stewardship

Deliver:

- Owner-approved submission/release.
- Support and incident-response procedure.
- Post-release observation plan.
- Safe migration/version strategy for the next update.

Exit criterion: the product can be supported, not merely uploaded.

### Parallel remote track, only if first-release scope requires it

Production account/sync work should have separate approved architecture and verification milestones. Do not let a demo endpoint bypass those milestones.

---

## 29. TestFlight and App Store preparation

### 29.1 Confirm externally, do not assume

The next agent should verify with the owner:

- Apple Developer program access.
- Team and signing authority.
- App Store Connect app record.
- Final bundle identifier.
- App name and availability.
- Distribution role/access.
- TestFlight tester approach.
- Privacy/support website ownership.

No successful submission or distribution is established by this handoff.

### 29.2 Candidate build procedure

Recommended:

1. Start from an understood revision/worktree.
2. Run focused tests for changes and full suite for candidate.
3. Build Release for simulator/device as appropriate.
4. Produce a signed archive through the approved Xcode workflow.
5. Validate archive.
6. Install/distribute only with authorization.
7. Run upgrade and smoke tests on the distributed build.
8. Record revision, version, build number, toolchain, and outcomes.

Do not confuse a Debug simulator test success with a signed Release candidate.

### 29.3 Privacy and permission review

Inventory actual use of:

- UserDefaults and other required-reason APIs.
- Local profile fields.
- Card content and comments.
- Search history.
- Photo/video picker and avatar processing.
- Clipboard reads.
- External links.
- Keychain sessions.
- Network routes and dormant demo code.
- Logs and diagnostics.

Check Apple's current requirements from authoritative sources at the time of submission. Requirements may change; this document is not an evergreen legal checklist.

System photo-picker use does not automatically imply broad photo-library access. Inspect the exact APIs before adding permission descriptions.

If online accounts become customer-facing, review current account-deletion and related requirements against actual behavior.

### 29.4 Listing language

Good first-release claims, if fully verified:

- Organize daily plans with ordered lists and cards.
- Capture tasks and supporting context.
- Break work into checklist actions.
- Browse card dates.
- Archive and restore cards, lists, and boards.
- Keep the implemented local workflow usable without an online account.

Do not claim:

- Calendar synchronization.
- Guaranteed backup.
- Private team collaboration.
- Multi-device sync.
- Production account recovery.
- Medical benefit.
- Clinical validation.
- Encryption or compliance not established.
- Desktop/web availability.

### 29.5 Screenshots and onboarding

Use respectful synthetic content.

Show:

- Today orientation.
- Week list organization.
- A readable card detail.
- Personal Board organization.
- Archive/restore.

Onboarding should explain:

- Today versus Week versus personal collections.
- Where New creates a card.
- Archive versus delete.
- Local storage limitations.
- How to restore archived boards.
- That the Calendar view displays card dates rather than device-calendar events.

Avoid placing real private/health details in screenshots or demos.

### 29.6 Beta tasks

Give testers job-oriented tasks, not only "try the app":

1. Choose today's list and add a card.
2. Complete a card and reopen it.
3. Add a checklist action.
4. Archive and restore a card.
5. Archive/restore a list and move it back into position.
6. Create a personal Board.
7. Archive and restore that Board.
8. Archive Week and verify restoring creates a separate Board.
9. Add/view/remove media.
10. Relaunch and verify state.
11. Repeat important tasks with larger text and VoiceOver.

Ask where they felt uncertain, not only whether they encountered crashes.

---

## 30. Operations, support, and post-release stewardship

### 30.1 Local-first support

Support needs to explain:

- What data is local.
- What archive can and cannot recover.
- What happens on reinstall.
- Whether a user-controlled export/backup exists.
- How to report a problem without disclosing private Board content.

Prefer minimal diagnostic metadata over full user-data dumps.

If crash reporting or analytics is introduced, make a separate privacy/product decision. Do not add a service merely to populate a dashboard.

### 30.2 Incident response

Define a procedure for:

- Suspected lost data.
- Failed migration.
- Broken archive restore.
- Repeated saving errors.
- Attachment failures.
- Distribution regression.
- Remote incident, if remote features ship.

The first response should preserve evidence/data, not instruct the user to reset the app.

### 30.3 Backup and restore

For local storage, determine what support can realistically recover.

For any server-backed release:

- Establish actual backups.
- Perform a restore drill.
- Define recovery objectives.
- Separate demo and production environments.
- Identify responsible operators.
- Review grants and credential lifecycle.

An immutable revision table does not itself prove backup recovery or prevent operational deletion.

### 30.4 CI direction

No tracked GitHub Actions workflow was found in the inspected inventory.

A useful next CI increment would:

- Build the app on an approved macOS/Xcode runner.
- Run current unit tests.
- Run PHP contract tests.
- Keep test fixtures synthetic.
- Preserve test result artifacts.
- Avoid leaking credentials or Board contents.
- Separate signing secrets from ordinary pull-request checks.

Add tooling only to satisfy a concrete requirement. Do not introduce multiple new frameworks while release reliability is still being established.

### 30.5 Release discipline

For each release:

- Record version/build/revision.
- Maintain compatibility notes.
- Test upgrade from the previous distributed build.
- Validate archive/restore/media retention.
- Keep known limitations honest.
- Have an owner-approved rollback/mitigation plan.

---

## 31. Explicit decisions for the owner

The next agent should ask these **one at a time**, with context and a recommendation where useful:

1. Is the first public release local-first, or must it include remote accounts/synchronization?
2. Which users and daily jobs are the first-release priority?
3. Is `com.plenact.Plenact02` the intended final app identity?
4. Which iPhones, iOS versions, and orientations are supported?
5. Is user-controlled export/backup required before public release?
6. What should users see/do when saved content cannot be decoded?
7. Should personal collection cards participate in Today/global search/Saved?
8. How should local profile identity affect comments and activity names?
9. Which synthetic/demo content remains in production onboarding?
10. Are rich checklist creation/conversion controls in release scope?
11. What privacy/support URLs and product terms will be provided?
12. Is monetization part of the first release?
13. Which beta audience and success criteria will guide release approval?
14. Who authorizes and operates any production infrastructure?

Do not ask all of these as one overwhelming questionnaire. Resolve the decisions that block the next concrete work item.

---

## 32. First assignment for the next agent

The following can be used as the initial production-agent brief:

```text
You are continuing Plenact's production preparation.

Read Doc/Production-Preparation-Handoff.md and inspect current repository status.
Preserve the established Today/Week/Lists/Saved experience, archive/restore semantics,
stable IDs, migration compatibility, and local media references.

Use Src/Features/Boards/ContentView.swift, CardDetailView.swift, and Models.swift as
the active Board implementation; the similarly named Src root files are not compiled.

Establish a current build/test baseline. The handoff's baseline was 57 passing iOS
unit tests plus passing PHP pure contract checks on October 4, 2026.

First clarify the public-release scope with the owner: dependable local-first app
versus a release requiring production online accounts/sync. The deployed backend
is repository-reported synthetic shared-demo infrastructure, not proven private
customer storage, and the normal account UI does not currently mount that demo.

Produce a prioritized, evidence-based release plan, then implement approved
release-gating work incrementally. Prioritize data preservation/recovery, lifecycle
durability, workflow consistency, accessibility, Release signing, and honest
privacy/product declarations.

Do not silently replace saved data, upload local Boards, remove archived content,
change Week restore into replacement, modify live databases, stage/commit unrelated
work, or submit/release the app without explicit authorization.

For each change, test the exact requirement, preserve existing behavior, update
directly related documentation, and explain outcomes with concise change tables.
Separate verified facts, recommendations, and unverified external deployment claims.
```

### Suggested first working session

1. Read status and recent history.
2. Confirm active source/project membership.
3. Read the product and persistence sections of this handoff.
4. Confirm the first-release scope.
5. Build/test the current baseline.
6. Inspect Release configuration and effective Info/privacy resources.
7. Reproduce the highest-priority data-recovery/lifecycle concerns with synthetic fixtures.
8. Agree the first bounded implementation.
9. Make the change and validate it.
10. Report exactly what is ready and what is not.

A useful first outcome is a trustworthy scope and a validated recovery improvement, not an impressive list of speculative new features.

---

## 33. Reference index

### Product and architecture

- [Repository README](../README.md).
- [Documentation index](README.md).
- [Today architecture](Today-View-Architecture.md).
- [Today UI proposal](Today-View-UI.md).
- [Board and Scheduled views](Board-and-Scheduled-Views.md).
- [Checklist actions architecture](Checklist-Actions-Architecture.md).
- [Local profile architecture](Local-Profile-Architecture.md).
- [Historical product opens](../Work/Opens.md).

Read status caveats in this handoff when older proposals conflict with current source.

### Feature documentation

- [Source guide](../Src/README.md).
- [Feature guide](../Src/Features/README.md).
- [Boards](../Src/Features/Boards/README.md).
- [Attachments](../Src/Features/Attachments/README.md).
- [Labels](../Src/Features/Labels/README.md).
- [Profiles](../Src/Features/Profile/README.md).
- [Sync and activity](../Src/Features/Sync/README.md).
- [Tests](../Test/README.md).

### Server and data contract

- [Server overview](../Server/README.md).
- [API route contract](../Server/api/README.md).
- [SQL migration status](../Server/SQL/README.md).
- [Database overview](Database/README.md).
- [Board data contract](Database/Plenact-Data-Contract.md).
- [Initial seed execution record](Database/Initial-Demo-Import-Plan.md).
- [Users/account design](Users/README.md).

The newer deployment records report applied/deployed demo state; several older status introductions still need reconciliation.

### Implementation and conventions

- [Application shell](../Src/App.swift).
- [Active Board view](../Src/Features/Boards/ContentView.swift).
- [Active card detail](../Src/Features/Boards/CardDetailView.swift).
- [Active Board models](../Src/Features/Boards/Models.swift).
- [Database activity](../Src/Features/Sync/DatabaseActivity.swift).
- [Swift style template](Style/style.swift).
- [Style guide](Style/README.md).
- [Xcode project](../Plenact.xcodeproj/).
- [Shared scheme](../Plenact.xcodeproj/xcshareddata/xcschemes/Plenact.xcscheme).

---

## 34. Final transfer principles

Plenact has moved from an idea into a working planning experience. The owner has found real value in the improvements and has repeatedly confirmed that the implemented workflows feel good.

The next stage should protect that momentum through disciplined release work:

1. **Preserve the plan.** Today, Week, and detail views must keep projecting the same canonical content.
2. **Preserve the person’s work.** Compatibility, archives, media references, recovery, and save ordering are release-critical.
3. **Be explicit about scope.** Local profile is not login; card dates are not calendar sync; archives are not backups; a shared demo is not private production collaboration.
4. **Prefer recoverable interactions.** Archive and restore are valuable because they reduce fear of losing work.
5. **Keep the experience understandable.** Status, error messages, destinations, and empty states should reduce uncertainty.
6. **Measure rather than assume.** Test exact thresholds, real destinations, runtime lifecycles, and accessibility jobs.
7. **Refactor incrementally.** A production release does not require replacing every large file before proving existing behavior.
8. **Separate evidence from aspiration.** Document what was inspected, what passed, what the owner tried, and what remains unverified.
9. **Ask before irreversible or scope-changing work.** Infrastructure, authentication, data upload, destructive migration, and release submission need approval.
10. **Build a product that can be supported.** A successful release includes recovery, privacy, honest claims, operational ownership, and a safe next update.

The goal is not simply to get Plenact onto the App Store. It is to bring a useful, meaningful, dependable planning tool into people’s daily lives without compromising the trust they place in their plans.
