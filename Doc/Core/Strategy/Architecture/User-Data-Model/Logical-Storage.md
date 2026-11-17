# Model 1.0 logical cloud storage

**Supported User Data Model versions:** 1.0. **Protocol:** 1.0. **Specification status:** final.

These are implementation-independent storage obligations, not a deployed SQL migration. The existing Version 0 database/schema remains separate. iOS, web and Windows access the same HTTPS contract; no client connects directly to MySQL.

| Logical store | Required identity and invariants |
| --- | --- |
| Accounts / private workspaces | Verified server account UUID; one personal workspace; immutable ownership; current epoch and monotonic workspace counter. Credentials/session issuance are separate operational storage. |
| Record heads | Unique workspace + record UUID, with immutable record type. Latest document or tombstone, record revision, change sequence, actor/time and optional authoritative Asset verification state. |
| Immutable revisions | Prior accepted complete server envelopes, identified by workspace/epoch/record/revision. User Card history remains distinct editable content. The change feed may compact old events, but current heads/tombstones remain. |
| Change log | Unique workspace/epoch/sequence, consecutive for accepted changes, referencing the exact immutable envelope. Retained 90 days; no filtering that breaks cursor semantics. |
| Transaction / operation receipts | Unique request identities and SHA-256 of exact request bytes, results and assigned revisions/sequences. Preserve successful deduplication proof for the account lifetime. |
| Snapshot leases | Authenticated owner/workspace/epoch, immutable fence and record set/page order, expiry after 30 minutes. A page token cannot change owner, epoch or snapshot. |
| Asset metadata / verified blobs | Portable metadata in ordinary records. Private operational locator and verified size/digest/availability outside user payload. Equal digests do not authorize cross-account access. No client path or upload credential becomes canonical content. |
| Upload leases / chunks | Owner/workspace/epoch/Asset base revision, fixed expectations, indexed chunk digests, received indexes and expiry. Temporary unverified bytes are not published originals. |
| Device/cursor operational state | Authenticated account association, lease/cursor progress and capability offer. Device UUID alone grants no access. This is not a synchronized user preference. |
| Migration / restore ledger | Applied database migrations, version transitions, source identity maps as appropriate, restore epoch changes and recoverable operator evidence. Never rerun Version 0 migration 001 to “upgrade” it into this model. |
| Deletion/purge jobs and guards | Accepted explicit confirmation, ownership/recent-authentication evidence, concrete deadlines and backup cleanup. Apply deletion guards before reopening restored service. Remove operational personal data according to the published deletion commitments. |

## Atomicity and validation

A transaction must lock/compare the appropriate workspace/record versions, validate the complete resulting membership graph, append all revisions/change sequences and store its receipt in one atomic database transaction. It must not write a receipt before content commits or increment visible counters for a failed content transaction. Asset commit must atomically connect verified bytes to the resulting Asset revision.

Database uniqueness and foreign-key constraints support the contract but cannot replace request-level authorization, typed JSON validation, semantic graph checks or receipt hashing. A physical schema must enforce the logical invariants even if a hosting/database version lacks a particular CHECK feature. Choice of normalized projections/indexes is an implementation detail; the canonical JSON documents and their meaning are not.

## Private storage and recovery

Use owner-authorized object/file access and least-privilege runtime credentials. Back up document state, original bytes, tombstones and deduplication evidence together. A physical restore that may lose acknowledged history gets a new epoch; old device outboxes cannot be replayed by merely changing their epoch field. Preserve the recovery evidence and require reconciliation.

Primary/backup deletion deadlines, indefinite tombstone/receipt retention while an account exists, staging cleanup and user-controlled local copies are defined in [Data lifecycle](Data-Lifecycle.md). Logical completeness does not prove the current Bluehost deployment satisfies these obligations; deployment and recovery verification are separate implementation gates.
