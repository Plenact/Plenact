# Plenact Protocol 1.0

**Supported User Data Model versions:** 1.0. **Protocol:** 1.0. **Specification status:** final.


## Endpoint and authentication boundary

The reserved API base is `https://plenact.com/api/user-data/v1`. Publication does not deploy these routes. Version 0’s existing PHP endpoints remain separate. [OpenAPI](Contracts/1.0/openapi.json) is the machine-readable route contract.

Every private route verifies an authenticated account and workspace owner on the server. Device IDs, display names, profile email and client ownership claims grant no access. The initial service exposes one private workspace and no shared-user directory. Session issuance/refresh/recent-authentication proof is the identity-service boundary: clients must not repurpose a Version 0 demo token without explicit verified account linking.

Native clients use opaque bearer sessions in platform secure storage. Browser sessions use Secure, HttpOnly, SameSite=Strict `__Host-plenact_session` cookies; all cookie-authenticated mutating requests also require an exact trusted Origin and a session-bound `X-CSRF-Token`. The identity service supplies the CSRF token. This contract requires those protections but does not prescribe a password/login implementation or expose credentials as user records.

Use HTTPS, no-store responses and generic authorization errors. Foreign and unknown record IDs share generic 404 behavior. Server-generated actor/time/revisions are outside editable documents. Schema validation is not authorization.

## Initial snapshot and local persistence

Authenticate, read capabilities/account/workspace, and negotiate an exact supported model. POST snapshots with the client offer. The service freezes the complete current record set and all tombstones at a fence sequence for 1,800 seconds. Pages are stable by `(record_type, record_id)` ascending, include no record newer than the fence, and must not duplicate a record across pages. Page tokens bind workspace, epoch, snapshot and authenticated account. An expired lease returns 410 `snapshot_expired`.

Only the final page returns `next_change_cursor`; intermediate pages return only `next_page_cursor`. The client stages all pages and installs a consistent baseline atomically with that final cursor. It must retain unsent local work, base versions and unresolved conflicts during a resnapshot; “absent from snapshot” must not turn an old update into a create.

Every accepted local edit and its outbox entry must be saved in one local transaction. Save immutable operation IDs, the base epoch/revisions, and exact UTF-8 request bytes before transmitting a transaction. Local success must not be represented as cloud success while pending, offline or conflicted. Credential expiry never clears the local workspace or outbox.

## Atomic transactions and conflicts

A transaction contains 1–100 complete put/delete operations with unique operation IDs and one operation per record. Its header `Idempotency-Key` equals transaction_id. Path/body workspace IDs must match. Client writes to server-owned account/workspace records are forbidden. All referenced owners, identities, payloads, affected membership and graph invariants are validated in one server transaction.

A create has null base_revision and a never-used record UUID. An update/delete has the exact live base revision. A put cannot resurrect a tombstone. A move includes source and destination memberships plus the moved record; deletion of a parent includes explicit consistent handling of its children. Archive is a normal revision-checked content edit.

All operations commit or none do. Each successful operation receives a new record revision and one consecutive workspace change sequence. A 409 conflict returns bounded current-revision/deletion summaries; fetch authorized current records for comparison. Preserve base/local/remote versions. No automatic last-write-wins, field merge, content replacement or discard is permitted. Resolution creates fresh operation/transaction IDs against newly read revisions. No-op successful puts are still revisions, so a receipt has a concrete sequence for every operation.

The service hashes the **exact decoded HTTP body bytes** using SHA-256; Content-Encoding other than identity is not supported for transaction bodies. Successful transaction receipts and operation IDs are retained for the account lifetime. The same transaction ID plus identical bytes returns the original receipt without another mutation. Different bytes, including different whitespace, return 409 idempotency_mismatch. Reusing a successful operation ID in another transaction also conflicts. Failed transactions have no successful receipt; retry may receive newer conflict information but must never partially apply.

A compacted receipt may discard bulky response copies but must retain request hash, transaction/operation identity and the original assigned revision/sequence/deletion results. Receipts are historical acknowledgements, not current record snapshots. Never advance a pull cursor merely to a receipt sequence: another device’s intervening changes still need to be pulled and applied.

## Ordered change retrieval

The change feed retains 90 days of ordered revision events. Within a workspace epoch, records in a page are exactly the consecutive sequences after `after_sequence` through `through_sequence`; no filtering silently skips unsupported record types. The next opaque cursor binds the same account/workspace/epoch. Empty pages keep the same sequence and cannot claim has_more. Page count is at most 100 and the whole JSON response must fit the byte limit.

Apply a page’s records and cursor atomically. Later records for an ID supersede earlier server revisions; never overwrite a newer local accepted server revision with an old receipt/page. Unsent local edits remain a separate overlay/base. If the cursor is older than retained changes, return 410 cursor_expired and resnapshot. Tombstones and accepted-write receipts are **not** removed with delta history.

## Indefinite offline use and restore epochs

There is no application-imposed expiration on local committed data, pending operations or cached owned originals. A returning device may need authentication, newer software, compatible timezone rules and a complete snapshot before network writes resume. None justifies deleting its pending local work.

Tombstones retain UUID/type/workspace, revision/sequence and server provenance for the account lifetime. IDs are not recycled. A stale update is never converted automatically into a create. Intentional recreation gets a fresh identity. Before replaying pending operations after resnapshot, compare their original base to current live/deleted state and expose conflicts. Retired devices can be marked operationally inactive, but their age does not justify deleting tombstones.

If a database restore could roll back previously acknowledged state or deduplication evidence, the operator **must issue a new workspace epoch**. All old-epoch writes receive 409 epoch_mismatch. Rebuild a consistent snapshot/change sequence in the new epoch, retain local outbox bytes and old receipts as recovery evidence, and require explicit reconciliation before constructing new-epoch operations. Merely replacing the epoch field on an old request is not reconciliation.

## Status and error mapping

| HTTP | Codes / meaning | Client action |
| --- | --- | --- |
| 400 / 415 / 422 | invalid_document, validation_failed; malformed JSON/media or semantic failure | Retain local input; report/repair explicitly. |
| 401 | unauthenticated | Reauthenticate for network exchange; keep local data. |
| 403 / 404 | forbidden / not_found | No owner/record enumeration; do not infer deletion from an unauthorized read. |
| 409 | conflict, idempotency_mismatch, epoch_mismatch | Resolve or resnapshot/reconcile; never overwrite blindly. |
| 410 | cursor_expired, snapshot_expired, upload_expired, account_deleted | Restart the appropriate lease/baseline; preserve pending work. |
| 413 / 426 | payload_too_large / unsupported_version | Keep source data; do not truncate or downgrade. |
| 422 | unsupported_timezone_rules, integrity_mismatch | Obtain compatible rules or correct the exact bytes; no silent reinterpretation. |
| 429 / 503 | rate_limited / temporary failure | Honor Retry-After; otherwise exponential retry with jitter, capped at five minutes. |

After a network failure retry immutable requests with the same IDs/bytes. A validation/conflict response requires explicit resolution before changing the request. Error messages are bounded human text; machine behavior uses the frozen code/recovery fields. Initial clients should poll while foregrounded approximately every 15 seconds, refresh on reconnect/focus, pause when hidden, and back off. Polling is an implementation preference, not a correctness dependency or a claim about current hosting capacity.

## Service obligations and examples

The implementation must enforce owner authorization, transaction isolation, counters within signed 64-bit range, membership invariants, receipt uniqueness, snapshot consistency and recoverable backups. SQL tables/indexes are implementation details; they may not weaken these guarantees. Hitting counter capacity requires an explicit new-epoch migration before reuse.

[Protocol examples](../../Tools/UserDataModel/protocol_examples.py) exercise retries, atomicity, conflict retention, cursor expiry, tombstones and byte verification in memory. They are not a production API/authentication/database. Their explicit graph-validator callback demonstrates the required pre-commit boundary; separate graph fixtures test the content relationships.
