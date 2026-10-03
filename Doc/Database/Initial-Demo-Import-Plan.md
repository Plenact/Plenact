**Status:** Initial synthetic seed completed on 2026-10-03. Migration `001` is applied and recorded in the dedicated `justirl2_plenact` database; the Board-editor account was provisioned and the iOS app published `SampleData` as revision 1. Database readback confirms schema version 1, `demo_seed`, a completed import batch, 49 source/result cards, 7 lists, and 13 labels. Both editor and member sign-in/readback succeed, and the app reported that local data was unchanged. Assignment authorization, stale-write, seed-retry, and restore checks remain

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

## Execution Record And Remaining Checks

Completed: reviewed the v1 contract; tested migration `001` on the matching disposable Bluehost database; applied it once and recorded its checksum/operator/UTC time; provisioned Jim; and initialized the shared Board from the app's synthetic `SampleData`. Database provenance/count readback and app revision-1 readback both succeeded, with local data unchanged

Remaining: independently verify linked-card references; test assignment-only member writes, stale-revision conflicts, and seed retry behavior; verify backup/restore. Do not upload a local personal Board or attachments

## Acceptance Checks

- Jim can authenticate and is the only user able to write canonical Board content
- Another registered demo user can read the shared directory/Board and make assignment-only changes
- Assignment changes append an attributed snapshot revision and preserve canonical card content
- API responses never expose password hashes, tokens, private configuration, or hosting credentials
- Seed retries are idempotent and linked user/card IDs resolve
- No actual user Board or attachment data is uploaded without separate review and opt-in