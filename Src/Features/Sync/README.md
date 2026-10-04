# Board Synchronization

This feature defines Plenact's versioned Board document and client boundary for the shared demo API

## Current Foundation

`PlenactBoardDocument` bundles all Board lists/cards and the label library under schema version 1. Its validator protects stable IDs and typed user/manual assignees before network submission. `PlenactBoardSnapshotResponse` keeps server revision and provenance separate from editable content

`PlenactAPIClient` uses HTTPS for login, the registered-user directory, shared Board reads, revision-checked canonical writes, and assignment mutations. Session tokens are stored in Keychain; local Profile data remains separate. `PlenactDemoAccountSection` provides controls to initialize the shared Board from synthetic `SampleData`, browse it, and change the signed-in user's own assignment. The first seed is explicitly marked and only accepted at revision zero

## Compatibility

Local `Plenact.Board.v1` persistence remains authoritative and is not replaced by remote snapshots. Existing Board data and local attachments are never uploaded by the SampleData seed. The server strips device-local photo/video references; photo/video bytes require a separately approved remote-storage design. Set the `PLENACT_API_BASE_URL` Xcode build setting to the deployed HTTPS API directory ending in `/` before sign-in can work

## Busy Feedback

`DatabaseActivity` tracks overlapping local Board operations and shared API requests independently. A non-blocking spinner banner says what is happening and asks the user to wait; it clears only when the tracked work finishes, including transport failures and cancellation. API errors continue through the existing account error alerts. Remote editing controls remain disabled throughout mutations and their follow-up refreshes.

The shared-demo section is currently not mounted in Account & Settings; busy feedback does not enable remote login or synchronization. All future callers of `PlenactAPIClient` automatically participate in the same activity state.