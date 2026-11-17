# Plenact Desktop Extension and Cloud Synchronization Plan

Based on Justin Reina’s Desktop Extension Plan, revision 4 (November 11, 2026). Status as of November 16, 2026.

## Objective

Extend Plenact from iOS to Windows so a user can create, edit, and find the same Cards and Notes on their Daily and Weekly Action boards on either device. Use a private Bluehost workspace for synchronization.

This effort covers iOS and Windows. Android, Web, Mac, and Linux are future targets.

## The four stages

| Stage | Work | Status |
| --- | --- | --- |
| 1. Enable Card and Note creation | Make both item types available in the normal Daily and Weekly planning flows. | Complete on iOS. |
| 2. Connect and synchronize with Bluehost | Build and verify the private database, API, iOS synchronization, and operational utilities. | Current. The Model 1.0 contract and MySQL plan are available. Private staging and iOS synchronization remain to be built and verified. |
| 3. Deliver Plenact for Windows | Connect the Windows desktop app to the same account, workspace, and dataset as iOS. | The local Windows beta exists. Cloud connectivity and cross-device verification remain. |
| 4. Share a common application, data, and experience model | Preserve the meaning and behavior of Cards, Notes, Lists, and Action boards across iOS and Windows, with interactions adapted to each device. | Verify against the shared contract and the cross-device workflow as Stage 3 progresses. |

## Stage 2 implementation

1. **Inventory Bluehost.** Verify the database engine and version, database grants, PHP runtime, private file storage, quotas, and backup and restore capabilities. Use the findings to define a staging database, HTTPS API path, and private storage area separate from the shared demo. This read-only inventory is the next task.
2. **Build private staging.** Pin Model 1.0 and its OpenAPI contract. Implement account-to-workspace binding, workspace authorization, and persistence for Card and Note identity, item type, and List placement. Implement retry handling that avoids duplicate writes, conflict handling for stale edits, and deletion synchronization.
3. **Build operational utilities.** Provide repeatable migrations and staging initialization, synthetic test data, diagnostics, and backup and restore procedures. Rehearse restoring the staging dataset and verify that it remains usable.
4. **Connect iOS through its normal workflows.** Create a Card and a Note from Today and another Card and Note from Week. Edit them offline, restart iOS while still offline, and verify that the pending changes survive. Reconnect and verify that the changes reach Bluehost and are retrievable through an independent authenticated client.
5. **Verify the service and record the handoff.** Check all four records for stable identity, correct type, and original List placement. Verify workspace isolation using a second test account, retry a write, submit a stale edit, and confirm that a deletion reaches the other client. Record the staging API and model versions, synthetic dataset, reproducible test steps, and backup and restore results for Windows. Verify the account-to-workspace binding before piloting with real data.

Stage 2 is complete when the four synthetic items round-trip between iOS and private Bluehost staging, the sync and ownership checks pass, and the backup and restore rehearsal is recorded. The existing shared PHP demo serves the older model. Its availability does not establish private Model 1.0 sync.

## Stages 3 and 4 acceptance demo

1. Create or retrieve the four synthetic items from the original Today and Week flows on iOS.
2. Sign in to the same staging workspace on Windows and open the same four items in their corresponding Lists.
3. Edit the items on Windows and verify those edits appear on iOS in the original Lists. Make a follow-up edit on iOS and verify it appears on Windows.
4. Confirm that both platforms preserve item identity, Card and Note type, and Action board and List placement. Verify that opening the same day through Today and Week exposes the same saved content on each platform.

## References

- [Plenact for Windows beta](../PlenactWin/README.md)
- [Plenact iOS server and shared demo status](../PlenactiOS/Server/README.md)
- [Model 1.0 MySQL implementation plan](../PlenactiOS/Doc/Database/Model-1.0-MySQL-Plan.md)
- [Model 1.0 OpenAPI contract](../PlenactiOS/Doc/Strategy/Architecture/User-Data-Model/Contracts/1.0/openapi.json)
- [Model 1.0 integration acceptance plan](../PlenactiOS/Doc/Strategy/Architecture/User-Data-Model/Integration-Plan.md)
