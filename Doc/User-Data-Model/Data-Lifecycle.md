# Model 1.0 ownership, privacy and retention

**Supported User Data Model versions:** 1.0. **Protocol:** 1.0. **Specification status:** final.


## Ownership and authentication

One verified stable account owns the initial private workspace. All record, snapshot, receipt, cursor and asset access is checked server-side. Profile labels, manual people, legacy directory IDs and device identifiers are not credentials. No cross-user sharing or public directory is implied. Identity-service session issuance, refresh and recent-authentication proof are implementation interfaces, not editable user content.

Store native credentials in platform secure storage and browser sessions in the protected cookie boundary. Keep database/provider keys outside clients and user exports. TLS is required. A schema-valid account_id submitted by a client must still match authenticated ownership. Version 0 demo users/assignments require explicit verified migration and cannot establish access by name/email matching.

## Retention decisions

| Data | Retention |
| --- | --- |
| Active user content and local pending work | No application age-based expiry. |
| Minimal record tombstones | Account lifetime; IDs never recycled. |
| Successful transaction/operation receipts | Account lifetime; compact results may retain only required proof/assigned metadata. |
| Incremental change events | 90 days; older cursors resnapshot without losing local work. |
| Frozen snapshot lease | 30 minutes. |
| Upload staging lease | 24 hours; unused staging cleanup after expiry plus seven days. |
| Owned committed media | No automatic garbage collection; explicit purge or account deletion. |
| Explicit asset purge | Primary bytes removed within 24 hours, backup copies within 30 days; tombstone retained. |
| Explicit cloud-account deletion | Access revoked immediately, primary data removed within 24 hours, backups within 30 days. |
| Local recovery journals/example backups | Device-owned until its existing explicit recovery/cleanup policy runs; never replayed through cloud sync. |

Local copies on an offline device cannot be erased by server policy. The application must explain and offer explicit local export/removal rather than pretending remote deletion wiped every device. Deleted account UUIDs are never reissued. A new account cannot automatically reclaim or upload old pending operations; that requires explicit import/ownership review.

## Delete/export operations

The authenticated owner may obtain complete snapshot pages and authorized media, or produce a local export. Exports include model/protocol/version metadata and integrity evidence; they remain private user data even though the specification is public. The read-only source capture is a separate legacy artifact, not a cloud-ready payload or a complete restore implementation.

Cloud-account deletion requires recent verified authentication, an operation UUID and the literal confirmation DELETE_MY_CLOUD_DATA. Use the same operation/Idempotency-Key for retries. Revoke active network sessions immediately. Issue a receipt with accepted time and concrete primary/backup deadlines. Deny future writes under that account; do not restore it from an old backup without applying the deletion ledger before reopening service.

## Backups and epochs

Backups must protect content, binary assets, ownership, migrations, tombstones and deduplication evidence. Verify recovery before real-data launch. A restore that can lose acknowledged state requires a new workspace epoch and client reconciliation, not silent replay. Account-deletion and purge commitments must also apply when restoring backups.

Minimum tombstones/receipts are retained for correctness while the account exists, not as a claim of unlimited detailed edit-history retention beyond authored data. Model 1.0 does not implement end-to-end encryption, legal-hold workflows, secure collaboration or production hosting by publication. Operators must meet the defined access/retention obligations before representing the service as conformant.
