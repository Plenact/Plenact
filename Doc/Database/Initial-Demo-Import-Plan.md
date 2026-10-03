**Status:** Proposed first data load. No schema has been applied and no content has been uploaded to Bluehost

## Goal

Populate the new shared-demo database with the deterministic weekday starter Board and register Jim as its initial editor and seed actor. Other active registered demo users can browse the Board and change only their own assignment; Jim can manage all assignments. This validates the Plenact contract before connecting normal Board persistence

## Source Boundary

The initial seed source is `SampleData` in `Src/Features/Boards/Models.swift`:

- Monday-through-Sunday lists, planning cards, and divider rows
- Standard, linked-card, and Action Detail checklist demonstrations
- The starter label library
- No local Profile data, personal Board snapshot, personal comments, or attachment files

The database is shared demo content, not private storage. Seed only synthetic information approved for all registered demo users to see. Existing on-device Boards remain untouched

## Jim Account

Jim is the canonical content editor and seed actor. Create the account through the private, invite/admin provisioning workflow and use its server-generated user ID in the shared Board metadata. Other registered users can browse and change assignments only

Never put passwords in SQL, app source, fixtures, logs, documentation, chat, or archives. A password was previously shared in conversation; treat it as compromised, rotate/revoke it if still valid, and set a new unique demo credential privately. Store only a server-generated password hash

## Snapshot Metadata

The initial import creates immutable Board snapshot revision `1` with:

- Board document `schema_version` and SQL migration version/checksum
- Server-generated `stored_at_utc`
- `stored_by_user_id` set to Jim's verified stable ID
- `storage_origin = demo_seed`
- Deterministic `import_batch_id`
- SHA-256 digest of the server-serialized JSON payload passed to the MySQL JSON column

Each future canonical Board save or assignment change appends a complete new snapshot revision and advances the Board head in one transaction. The API rejects stale expected revisions; it must not silently overwrite concurrent changes

## Idempotency And Mapping

- Derive one stable import-batch ID from the reviewed seed version/source
- Preserve list/card integer IDs and checklist UUIDs within the shared Board
- Resolve linked-card IDs after all canonical cards have been added to the snapshot
- Convert the known starter assignment for Jim only through an explicit seed mapping to Jim's registered user ID; never infer accounts from display names
- Keep every non-account assignee as a typed manual assignment
- Re-running the same batch must detect the prior completed batch and avoid creating a duplicate Board or revision

## Execution Sequence

1. Review [`Plenact-Data-Contract.md`](Plenact-Data-Contract.md), including snapshot revision, dates, placements, and assignment behavior
2. Confirm the new dedicated Bluehost database and separate administrator/runtime credentials through cPanel. Do not reuse the reference database or token
3. Test migration `001` on a disposable database with the same MySQL/Percona version as Bluehost
4. Take a backup, apply the migration once, and record its checksum/operator/UTC time
5. Provision Jim with a rotated unique demo credential; verify only the password hash is stored
6. Sign in as Jim in Account & Settings and explicitly initialize the shared Board from the app's `SampleData` action; the current local Board/profile/attachments are not uploaded or replaced
7. Verify the transaction created one `demo_seed` revision and deterministic import batch with actor, timestamp, schema version, and digest
8. Verify seven ordered weekday lists, cards/dividers, linked-card references, Action Details, labels, assignment IDs, and document decoding
9. Retry the same seed, test stale-revision conflict behavior, restore from backup, and verify existing local app data remains unchanged

## Acceptance Checks

- Jim can authenticate and is the only user able to write canonical Board content
- Another registered demo user can read the shared directory/Board and make assignment-only changes
- Assignment changes append an attributed snapshot revision and preserve canonical card content
- API responses never expose password hashes, tokens, private configuration, or hosting credentials
- Seed retries are idempotent and linked user/card IDs resolve
- No actual user Board or attachment data is uploaded without separate review and opt-in