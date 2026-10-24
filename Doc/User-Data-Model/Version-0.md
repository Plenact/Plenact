# Version 0 – Getting Cloud Connection Established

**Supported User Data Model versions:** Version 0 only.
**Status:** Historical baseline; existing implementation, deployment reported by repository records.

## Purpose and boundaries

Establish HTTPS connectivity, authenticated accounts, and revision-checked storage using synthetic shared-demo content. This is the reference foundation for Version 1.0, not its private-user storage model.

The existing envelope contains `schema_version: 1`, `board_key: "shared-demo"`, `lists`, and `label_library`. Relational tables store accounts, sessions, Board head, immutable snapshot revisions, import batches, and migration history. One editor controls canonical content; members manage their own assignments. Local Profile identity is separate from the remote account.

Existing routes: login/logout through `auth.php`, user directory/account provisioning through `users.php`, Board reads/writes through `board.php`, and assignment mutations through `assignments.php`. Writes use the last read Board revision; stale writes are rejected. Requests and responses are limited to 1 MiB. Tokens belong in device secure storage; database credentials never belong in either client.

## Recorded deployment evidence

[SQL records](../../Server/SQL/README.md) and the [seed record](../Database/Initial-Demo-Import-Plan.md) report migration 001 applied October 3, 2026, seven InnoDB tables, and synthetic revision 1 containing seven Lists, forty-nine Cards, and thirteen labels. Editor/member login and readback were reported. These are repository records, not fresh live verification.

Member mutation authorization, stale-write behavior, seed retry, and backup/restore still require documented end-to-end evidence. Do not rerun migration 001 because an older document says undeployed.

## Compatibility and known drift

The [historical contract](../Database/Plenact-Data-Contract.md) describes date-only Cards and omits newer fields. Current Swift Codable types have evolved; some additional fields may pass through JSON snapshots without equivalent server validation. That does not establish supported cross-client compatibility.

Version 0 does not synchronize the complete calendar, personal collections, reviews, settings, bookmarks, importance, or media files. Preserve its existing wire schema number and API behavior during Version 1.0 preparation. It must not silently become a private-user service.
