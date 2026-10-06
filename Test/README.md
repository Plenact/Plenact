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

Personal-list example tests verify all six template names, the 5–20-card requirement, distinct card IDs, ownership, empty date/personal-media/assignment fields, and Codable round trips. Three examples now include one original bundled cover each. Isolated-store tests check draft creation has no writes, repeated selections receive fresh collection IDs and collision-safe titles, renaming preserves card identities, and explicit append/save preserves retained collections and Week bytes. These model tests do not establish sheet dismissal or Cancel/Save interactions; exercise both Examples entry points, preview/select, cancel at each stage, repeated insertion, and narrow/large-text button layout on device.

Cover tests verify backward-compatible decoding and omitted nil keys; explicit photo-only selection; missing-ID/video/link/divider rejection; removal without fallback or photo deletion; archive/restore and independent-copy retention; actual bundled-resource loading; a synthetic 2400-by-1600 photo downsampled to exactly 960-by-640; and bounded Standard/Overview hosted rows with isolated visibility preferences. The synthetic API seed test verifies local cover and illustration metadata are omitted without contacting a server.

Cover device acceptance: add a new photo as a cover, choose/change an existing photo using the visual chooser, cancel selection, remove the cover from detail and row menus, remove selected/unrelated attachments, hide/re-enable covers in Board Settings, relaunch, copy a list, and archive/restore through Week and personal collections. Check large photos, unavailable files, photo-transfer errors, Remove Cover or replacement during a pending transfer, deletion with an in-flight import, landscape, large text, and VoiceOver. Automated model/layout checks do not establish picker or gesture behavior.

Offline library coverage verifies exactly six categories of eight illustrations, no missing/duplicate category membership, and all 48 files in the actual app bundle. Each decodes at exactly 960-by-480 pixels with distinct PNG bytes; total artwork stays below one MiB. The original three enum cases retain their names/order for demo compatibility.

Selection regressions cover all 48 choices, matching-attachment UUID reuse, personal-photo retention, replacing/removing/reselecting covers, unchanged descriptions, archive Codable round trips, independent copies, and divider rejection. Hosted library checks exercise narrow/landscape/accessibility layouts without selecting or attaching anything.

Library device acceptance: open Browse Cover Library from Week and personal card details, browse all six filters and All Covers, scroll to the last image, Cancel without changes, select/replace/remove/reselect, hide/re-enable row covers, and relaunch. Check retained photos, archive/restore, copying, large text, both landscape directions, VoiceOver category/preview/current-cover labels, and replacing a photo import that is still in flight. Hosted layout/model tests do not establish taps, sheet dismissal, or VoiceOver behavior.

Historical artwork-only validation on October 5, 2026 passed two focused bundle/demo tests before the chooser was implemented. That initial 27-image payload was 591,408 bytes; the completed 48-image payload is 978,105 bytes. Neither figure represents App Store download size.

Completed Cover Library validation on October 5, 2026: the focused run with `-only-testing:PlenactTests/PlenactBoardDocumentTests` passed **62 tests, 0 failures**, and the full command below passed **81 tests, 0 failures**. App/test targets built, the 48-image contact sheet was visually reviewed, editor diagnostics reported no errors in changed Swift files, and `git diff --check` passed. This local feature did not access a live service; PHP checks were not rerun. New chooser interactions and VoiceOver still require device acceptance.

## Running Tests

Use the shared `Plenact` scheme with an installed iPhone simulator:

```sh
xcodebuild test -project Plenact.xcodeproj -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' \
  -parallel-testing-enabled NO
```

Discover locally installed destinations with `xcodebuild -showdestinations -project Plenact.xcodeproj -scheme Plenact`

Archive/delete validation on October 5, 2026: the full command above passed **72 tests, 0 failures**. The focused run adding `-only-testing:PlenactTests/PlenactBoardDocumentTests` passed **53 tests, 0 failures**.

Card-cover validation later on October 5, 2026: the final full command above passed **78 tests, 0 failures**, including **59 Board tests**. An intermediate focused run passed **58 Board tests** before the additional large-local-photo regression. Editor diagnostics reported no errors in the changed Swift files, and `git diff --check` passed. Xcode emitted its metadata-extraction notice because these targets do not depend on AppIntents. No live service was accessed; PHP contract checks were not rerun for this local Swift feature.

Keep persistence fixtures focused on compatibility contracts. Do not use real customer, health, or private board data in tests