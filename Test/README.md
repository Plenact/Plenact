# Plenact Tests

This directory contains the active unit-test target for Plenact

## Current Coverage

`ChecklistMigrationTests.swift` verifies revision 0 string and card-member migration, stable registered-user assignee round trips, repeatable migration IDs, rich action round trips, the Monday-through-Sunday starter-board contract, and linked-card/Action Detail coverage for every seeded activity card

`LocalProfileStoreTests.swift` verifies isolated local profile persistence, removal, personalization, and avatar initials without reading production preferences

`PlenactBoardDocumentTests.swift` also verifies overlapping database activity, persistent error feedback, ordered background Board saves, preservation of unreadable saved data, and API activity cleanup after success, timeout, and cancellation. Persistence tests use isolated UserDefaults suites; API tests intercept synthetic requests without contacting a server.

Archive coverage verifies legacy list decoding, unchanged JSON shape for empty archives, full-card archive/restore round trips, divider retention, reserved archived IDs, exclusion from active search, local-only shared-Board validation, and archive preservation when renaming personal lists.

List/board archive coverage verifies active/archive binding partitions, list restoration ordering, complete Week snapshots, preserved bookmarks and nested archives, backward-compatible board flags, unique restored titles, and personal-board persistence through archive and restore.

Personal-board archive failure tests verify save-before-update ordering, unchanged active state and stored data on encoding failure, and rejection of missing boards.

Permanent-deletion regressions cover canonical active/archive card removal, Board-local bookmarks and independent copies, complete list removal and surviving order, safe empty-Board encoding, personal-list archive save failure, and success-only queued-save completion. Checked Week deletion waits behind earlier saves and leaves persisted bytes unchanged when the remaining snapshot cannot be encoded.

Synthetic media tests remove only explicit candidate files, protect archived/shared references, preserve unrelated files, and reject empty, dot-directory, and parent/path filenames. Tests create uniquely named files and clean only those fixtures; no customer content or production preferences are used.

These regressions do not establish gesture/confirmation behavior. On a device, exercise Cancel and confirmed Delete from every entry point in the [lifecycle matrix](../Src/Features/Boards/README.md#archive-and-permanent-deletion), relaunch after deletion, inspect/restore retained content, delete with focused draft text and an in-flight photo import, and verify shared attachment copies, large text, VoiceOver, and error feedback. The corrupt-store recovery blocker remains outside this milestone.

List-reordering tests verify movement in both directions, persistence of order and complete list contents, invalid/missing targets, and exact viewport-edge thresholds used for hold-and-drag edge scrolling.

Board-presentation tests verify exact Standard/Overview widths, portrait/landscape capacity, invalid/narrow geometry, accessibility sizing, and local preference persistence without changing saved Board/collection snapshots. Hosted card tests measure actual content-fitting heights and accessibility growth. Hosted Board re-layout checks retain active/archived content and bookmarks without requesting a Board save. These tests do not replace physical rotation, modal-draft, gesture, or VoiceOver checks listed in [Board Presentation](../Doc/Board-Presentation.md).

Card-layout regressions also compare short/tall height proposals and measure actual navigation-linked List rows to catch excessive vertical expansion in the scrolling container. Landscape root-toolbar appearance and keyboard overlay behavior still need a hands-on check.

Library row coverage hosts a long synthetic collection title at portrait/landscape widths and checks content-fitting growth at accessibility text sizes. On-device acceptance still needs Library navigation, search, create/cancel, edit/reorder, Saved restoration, VoiceOver, and both landscape directions. This presentation update does not introduce standalone notes or a new persistence format.

Personal-list example tests verify all six template names, the 5–20-card requirement, distinct card IDs, ownership, empty date/media/assignment fields, and Codable round trips. Isolated-store tests check draft creation has no writes, repeated selections receive fresh collection IDs and collision-safe titles, renaming preserves card identities, and explicit append/save preserves retained collections and Week bytes. These model tests do not establish sheet dismissal or Cancel/Save interactions; exercise both Examples entry points, preview/select, cancel at each stage, repeated insertion, and narrow/large-text button layout on device.

## Running Tests

Use the shared `Plenact` scheme with an installed iPhone simulator:

```sh
xcodebuild test -project Plenact.xcodeproj -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' \
  -parallel-testing-enabled NO
```

Discover locally installed destinations with `xcodebuild -showdestinations -project Plenact.xcodeproj -scheme Plenact`

Validation on October 5, 2026: the full command above passed **72 tests, 0 failures**. The focused run adding `-only-testing:PlenactTests/PlenactBoardDocumentTests` passed **53 tests, 0 failures**. Editor diagnostics reported no errors in the changed Swift files, and `git diff --check` passed. Xcode emitted its metadata-extraction notice because these targets do not depend on AppIntents. PHP contract checks were not rerun for this Swift-only milestone.

Keep persistence fixtures focused on compatibility contracts. Do not use real customer, health, or private board data in tests