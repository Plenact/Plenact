# Plenact User Data Model

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

Model **1.0** defines the complete private workspace contract for iOS, Plenact.com web and Windows C#. Start with the normative [Specification](Specification.md), then [Synchronization](Synchronization.md), [Assets](Assets.md) and [Compatibility](Compatibility.md). The [GitHub publication](Publication.md) freezes documentation, schemas, synthetic examples and conformance tools together.

This is a specification release. Normal application storage remains local; the iOS migration adapter, web/Windows integrations and Model 1.0 production API are not implemented by this release. No personal workspace was uploaded.

## Version namespaces

[Version 0 — Getting Cloud Connection Established](Version-0.md) names the earlier shared Board demo retrospectively. Its wire `schema_version: 1`, SQL migration `001` and local `.v1` keys retain their existing meanings. Model 1.0, protocol 1.0, per-type payload schema 1, record revisions and app releases are separate namespaces.

## Definition and evidence

| Document | Purpose |
| --- | --- |
| [Specification](Specification.md) | Authoritative scope, records, ownership and relationships. |
| [Value types](Value-Types.md) | Dates, text, rich formatting, numbers, enums and limits. |
| [Field dictionary](Field-Dictionary.md) | Exact schema-derived payload field index. |
| [Synchronization](Synchronization.md) | Snapshots, atomic writes, conflicts, retries, changes and offline recovery. |
| [Logical storage](Logical-Storage.md) | Required transactional stores and invariants without prescribing SQL. |
| [Assets](Assets.md) | Resumable verified bytes, retention and explicit purge. |
| [Lifecycle](Data-Lifecycle.md) | Privacy, account deletion, retention and restore. |
| [Compatibility](Compatibility.md) | Version negotiation and client responsibilities. |
| [Migration](Migration.md) | Source-to-portable conversion and recovery rules. |
| [Source catalogue](Source-Field-Catalogue.md) | 96 Codable declarations / 379 stored fields / 41 key-prefix segments. |
| [Storage inventory](Storage-Inventory.md) | Existing storage families and lifecycle classification. |
| [Contracts](Contracts/1.0/README.md) | 48 JSON Schemas, 24 canonical record types, OpenAPI and fixtures. |
| [Conformance](Conformance.md) | Reproducible checks and their practical boundaries. |
| [Read-only capture](Read-Only-Export.md) | Existing offline backup-preservation tool; not portable conversion. |
| [Integration plan](Integration-Plan.md) | Runtime work after definition publication. |

The historical demo deployment is reported in repository records for October 3, 2026, with synthetic data. This definition release does not establish the live host's present state or make the current personal workspace cloud-backed.

## Current implementation follow-up

See [native iOS backup/export](iOS-Migration-Export.md), [versioned SQL/JSON examples](Doc/Examples/README.md) and the [current application/data plan](../Application-Data-Plan.md). The frozen GitHub Model 1.0 release remains unchanged; this working-branch documentation records subsequent implementation progress.

Native implementation update: [durable identities and first canonical preview converters](iOS-Migration-Identity.md) are now available on the working branch. They do not complete workspace conversion or enable synchronization.

## Local recovery acceptance follow-up

A [Simulator-only reviewed source-restore test](iOS-Local-Restore-Test.md) is now available on the working branch. The owner chooses the backup and confirms installation into the separate test Simulator; previous destination data is retained for undo. This exercises local recovery, not full Model 1.0 conversion or cloud account import.
