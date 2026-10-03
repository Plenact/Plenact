All endpoints require HTTPS. UTF-8 JSON request and response bodies, including API envelopes, are limited to 1 MiB (1,048,576 bytes). Serialized Board snapshots use the same ceiling; oversized requests/documents are rejected, and oversized responses are replaced with a generic server error. Protected routes use `Authorization: Bearer <access_token>`; tokens are random per-session values stored on the server only as SHA-256 hashes. Responses are no-store JSON with generic errors

## Routes

- `POST auth.php`: login body is `{ "action": "login", "username": "...", "password": "..." }`. Logout uses `{ "action": "logout" }` with the bearer token. Login failures are throttled by a hash of the normalized username
- `GET users.php`: returns active users' stable IDs, usernames, and display names only
- `POST users.php`: Board-editor-only account creation. Body requires `username`, `display_name`, and a 12-character-minimum `password`; optional `email` is never returned by the directory. New accounts always receive the `member` role
- `GET board.php`: returns the current shared snapshot and server revision metadata
- `PUT board.php`: Jim-only full snapshot write. Existing revisions require `{ "expected_revision": N, "document": ... }`. Initial seed requires `expected_revision: 0` and `seed_kind: "sample_data_v1"`; it creates revision 1, a deterministic import batch, and the Board head in one transaction. This initial operation is available only to the provisioned Board editor
- `POST assignments.php`: body requires `expected_revision`, `card_id`, and `action` (`assign` or `unassign`). Members omit `user_id` and can change only their own assignment. Jim must supply an active directory `user_id` and may manage any member. Every effective change appends a full immutable revision

## Error Semantics

- `401`: missing, invalid, expired, revoked, or disabled-user session
- `403`: role or assignment-scope violation
- `409`: stale revision, duplicate account/email, or user limit reached
- `422`: invalid payload or unknown/inactive registered assignee
- `429`: login throttling

No endpoint accepts MySQL credentials or client-supplied actor/provenance fields. The API strips local photo/video attachment records from shared snapshots; it does not store binary media

The implementation requires PHP 8.1+ with PDO MySQL. It is deployed at `https://plenact.com/api/` on PHP 8.2. Authenticated editor and member login/readback succeeded; the editor initialized SampleData as revision 1. Assignment-only member permissions, stale-revision conflicts, seed-retry behavior, and backup/restore remain unverified
