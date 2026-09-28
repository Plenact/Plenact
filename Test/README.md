# Plenact Tests

This directory contains the active unit-test target for Plenact.

## Current Coverage

`ChecklistMigrationTests.swift` verifies that revision 0 string-based checklist data decodes into stable checklist-item records, preserves completion, receives repeatable migration IDs, and round-trips in the current format.

## Running Tests

Use the shared `Plenact` scheme with an installed iPhone simulator:

```sh
xcodebuild -project Plenact.xcodeproj -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Discover locally installed destinations with `xcodebuild -showdestinations -project Plenact.xcodeproj -scheme Plenact`.

Keep persistence fixtures focused on compatibility contracts. Do not use real customer, health, or private board data in tests.