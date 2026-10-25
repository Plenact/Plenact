# MySQL implementation plan for Model 1.0

**Supported User Data Model versions:** 1.0; Version 0 historical reference only.
**Updated:** October 24, 2026.

**Status:** Physical implementation plan and synthetic examples; no production migration or deployment is claimed. The published wire contract remains unchanged.

Use an isolated Model 1.0 staging database/private media namespace after auditing the actual Bluehost database engine/version, grants, capacity and tested recovery. Use transactional InnoDB-compatible storage; validate host support rather than assuming a product version.

## Physical stores to implement

| Store | Essential responsibilities |
| --- | --- |
| Accounts/workspaces | Verified owner, stable workspace UUID, epoch and locked monotonic counter; separate session/credential service. |
| Record heads | Unique workspace + record UUID, immutable type, complete validated document or tombstone, latest revision/sequence and provenance. |
| Revisions/changes | Immutable server frames and a gap-free epoch sequence; delta retention 90 days. |
| Transaction/operation receipts | Exact request SHA-256, identities and original results retained for the account lifetime; unique constraints prevent duplicate mutation. |
| Snapshots | Frozen record set/fence, owner-bound page tokens and 30-minute expiry. |
| Assets/uploads | Declared metadata versus verified originals, resumable chunk state, 24-hour leases, explicit purge and backup deadlines. |
| Operational lifecycle | Auth sessions, CSRF/recent-auth proof, deletion jobs/guards, restore/migration ledger and recovery evidence. |

The [example SQL](../User-Data-Model/Doc/Examples/1.0/illustrative-record-storage.sql) demonstrates the record/revision/change subset using an internally consistent synthetic workspace. It deliberately omits auth, receipts, leases, deletion jobs and production transaction procedures; it cannot be used as the production Model 1.0 migration.

Use explicit utf8mb4 for authored text and exact/binary comparison for UUID/token/hash identities. Wire decimal-string revisions convert only through checked 64-bit arithmetic, never floating point. SQL constraints must support, not replace, complete schema/semantic/owner checks. Retain original request byte hashing outside JSON normalization. Parameterize runtime SQL; static example hex literals are not an API implementation.

Before deployment, prove row locking/compare-and-swap, all-or-none graph mutation, receipt uniqueness, cursor/snapshot behavior, counter overflow, offline-delete reconciliation, blob integrity, restore epochs and account/purge deadlines. The [logical storage contract](../User-Data-Model/Logical-Storage.md) and [integration acceptance plan](../User-Data-Model/Integration-Plan.md) are authoritative.
