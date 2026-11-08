# Migration mapping index

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

The final migration rules are [Migration.md](Migration.md). Every source Codable declaration and stored field is indexed in [Source-Field-Catalogue.md](Source-Field-Catalogue.md), with source hashes and lifecycle/target mappings in [Source-Coverage.json](Source-Coverage.json).

Mappings require native legacy decoding, durable owner-qualified IDs, timezone provenance, projection reconciliation, retained unknown/history bytes and exact original media hashes. No generic snake_case conversion or display-name account matching is allowed. The source audit records coverage; it is not an executable migration adapter.

The [read-only capture tool](Read-Only-Export.md) preserves an explicit frozen backup and always reports portable conversion incomplete. Implementation must prove complete conversion and rollback before any opted-in personal-data upload. Offline pending work never expires automatically; server epochs, deletion evidence and exact request receipts govern recovery after cloud writes.
