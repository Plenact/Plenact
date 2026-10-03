**Status:** Draft for review. The local SQL draft is not deployed. No Bluehost database has received this schema or Board content

## Scope

The first database-backed Plenact phase is a shared, non-private demo. Invite/admin-created registered users can discover one another and appear as card assignees alongside manually entered people. All active registered users can browse the shared Board. Jim is its only canonical content editor; other users may add or remove card assignments

Members can add or remove only their own directory-backed assignment; Jim can assign or unassign any active registered user. This is not production multi-tenancy, private Boards, or secure collaboration. Store only synthetic, non-sensitive demo data

## Domain Principles

- Lists organize activities; weekday names are a useful starter experience, not a storage limit
- Cards are canonical activities or notes and may be undated or have date-only planning values
- A card currently belongs to one list in the snapshot; multi-list placements are deferred
- Checklist actions are standard text, references to cards, or reduced Action Details
- Registered-user assignments use stable user IDs; manual names remain explicitly manual
- Assignment does not itself grant permission to edit the card
- Scheduled events and recurring plans are separate from card deadlines and are deferred

## Initial Storage Model

The first shared Board is stored as an **immutable, versioned Plenact Board snapshot**. This matches the current SwiftUI workflow, which loads and edits one complete Board value. It does not reuse the Database Demo's Planner document or schema

Relational tables own account identity, login sessions, the shared Board head, immutable revisions, migration history, and import batches. Each revision's JSON document contains the current Board lists/cards/checklists/comments/assignees/labels. The API drops device-local photo/video attachment references; web links may remain

An illustrative envelope is:

```json
{
  "schema_version": 1,
  "board_key": "shared-demo",
  "lists": [],
  "label_library": {}
}
```

`lists` and nested values follow the reviewed Swift Codable contract. `label_library` contains reusable categories and labels. Registered assignee entries carry stable user IDs; the server verifies every referenced ID is active. Manual assignees carry display text and are never treated as accounts

The shared Board has one revision counter. Jim's content edits and member-assignment changes each append a complete Board revision. A write includes the revision the client last read; stale writes receive a conflict instead of silently overwriting newer work. Previous revisions are immutable

This aggregate model makes Board save/load atomic and retains reviewable history, but individual cards are not SQL-queryable in v1. Add relational projections only if real filtering, scale, or collaboration needs justify the added synchronization complexity

## Domain Payload

- **List:** stable integer ID, title, order, and cards
- **Card:** stable integer ID within the Board, title, divider/completion state, optional start/due date, description/subtitle, checklists, comments, assignees, label IDs, attachment metadata, and dismissed activity IDs
- **Checklist action:** stable UUID, title, completion, and standard/linked-card/Action Detail content
- **Registered assignee:** stable user ID and cached display name for offline rendering
- **Manual assignee:** stable local assignment ID and display name, without a user ID
- **Label library:** stable categories and labels referenced from cards

The snapshot includes metadata needed to reconstruct the current app model. Photo/video bytes are not part of the initial import; local Documents filenames are not remotely accessible. Do not claim attachments are synchronized until a separate binary-storage design exists

## User And Access Model

- `demo_users` stores a server-generated UUID, normalized unique handle, display name, optional private email, password hash, account status, and `board_editor` or `member` role
- Jim's stable account ID is stored as the shared Board's `content_editor_user_id`
- Only the Board editor may change canonical Board content
- Active registered members may read the shared Board/user directory and add/remove only their own registered assignment. Jim may manage any active user's assignment
- Registration is invite/admin-created; no open signup endpoint is planned for v1
- Local Profile data remains local and separate from the authenticated remote account/session

Passwords are accepted only over HTTPS and stored only as server-generated password hashes. Session bearer tokens are random, returned once, stored hashed on the server, and stored in iOS Keychain on device. Never use the shared app token from the reference project as a user identity

## Revision And Storage Context

Every immutable Board revision records:

- Payload `schema_version`, distinct from SQL migration version
- Monotonic Board `revision`, starting at 1
- Server-generated UTC `stored_at_utc`
- Stable `stored_by_user_id` verified from the session
- Controlled `storage_origin`, such as `demo_seed`, `jim_edit`, `member_assignment`, or `migration`
- Optional deterministic `import_batch_id`.
- SHA-256 digest of the server-serialized JSON payload passed to MySQL's JSON column for integrity diagnostics. MySQL may normalize its internal JSON representation

User-account rows also carry creation/update timestamps, actor IDs, row revision, schema version, and storage origin. Snapshot revisions preserve prior full Board states; they are not per-card revision numbers. Retention and restore UX remain explicit future decisions

## Initial Seed And Local Migration

The first database seed is deterministic `SampleData` only: Monday–Sunday lists, starter cards/dividers, checklist demonstrations, and the label library. It is not a user's existing `Plenact.Board.v1` snapshot, local profile, personal comments, or attachment files

Seed/import rules:

1. Register Jim through the private account-provisioning flow and use his stable server-generated ID as editor and seed actor
2. Map the known starter assignment to Jim only through an explicit import rule; never infer identity by display-name matching
3. Preserve local integer list/card IDs within the single Board and checklist UUIDs. Validate all linked-card references after import
4. Record a deterministic import batch ID and make repeated seed attempts idempotent
5. Create snapshot revision 1 with origin `demo_seed`; verify its content digest and counts
6. Leave all existing local Board snapshots and attachment files untouched

A later opt-in migration of saved local Boards needs a backup, user confirmation, stable ID mapping, member-resolution review, and round-trip tests before upload

## Date And Recurrence Boundary

The initial schema stores optional date-only card fields; it does not model timed events or recurrence. The meanings of **Required**, **Target**, and **Expected** dates are not yet final and are not separate columns in migration 001. A future scheduled event needs explicit start/end, timezone, and all-day behavior. Recurrence and exceptions remain deferred

## Open Decisions

- Whether user assignment and mention/reference are distinct actions
- Exact date-intent semantics and timezone/all-day event behavior
- Whether Board snapshot size needs a bound and how restore/history is exposed
- Whether future production needs per-organization ownership or per-card query tables
