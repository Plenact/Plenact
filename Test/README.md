# Plenact Tests

This directory contains the active unit-test target for Plenact.

## Current Coverage

`ChecklistMigrationTests.swift` verifies revision 0 string migration, earlier stable-item compatibility, repeatable migration IDs, rich action round trips, and the linked-card/Action Detail contract for every seeded activity card.

## Running Tests

Use the shared `Plenact` scheme with an installed iPhone simulator:

```sh
xcodebuild -project Plenact.xcodeproj -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Discover locally installed destinations with `xcodebuild -showdestinations -project Plenact.xcodeproj -scheme Plenact`.

Keep persistence fixtures focused on compatibility contracts. Do not use real customer, health, or private board data in tests.