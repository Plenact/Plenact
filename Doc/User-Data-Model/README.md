# Plenact User Data Model

**Supported User Data Model versions:** 1.0 published base; 1.1 working appearance composition; Version 0 is historical reference only.
**Status:** Model 1.0 remains published/frozen. Additive Model 1.1 is a working definition with native preview support; publication and complete application/API integration remain pending.

Model **1.0** is the published private-workspace base for iOS, Plenact.com web and Windows C#. [Working Model 1.1](Version-1.1.md) adds explicit global Week appearance and saved-artwork order without changing released 1.0 records. Start with the normative [Specification](Specification.md), then [Synchronization](Synchronization.md), [Assets](Assets.md) and [Compatibility](Compatibility.md). The [GitHub publication](Publication.md) freezes documentation, schemas, synthetic examples and conformance tools together.

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

## Expanded content conversion

The working branch now includes [Board/List/Card content conversion](iOS-Content-Migration.md), with explicit timezone selection, owner-qualified template copies, archive/history/media-reference preservation and independent graph checks. Full workspace conversion and cloud integration remain pending. The earlier first-slice status above is historical; the new guide is the current content-adapter evidence.


### Label and personal-selection preview update

Supported User Data Model versions: 1.0. The content preview now records an explicit current-build default label catalog only when the saved catalog is absent. It also prepares owner-qualified bookmarks/importance in local `SelectionPreview.json`, with unresolved targets and conflicts reported. These drafts remain pending verified account binding; they are not yet canonical selections. See [content and selection evidence](iOS-Content-Migration.md). Full workspace export/import and synchronization remain pending.


### Calendar and template metadata update

Supported User Data Model versions: 1.0. Native previews now convert saved Week/index and template/library metadata with explicit original owner mappings, template order/defaults and cross-Week checklist ownership. See [calendar/template conversion evidence and manual test](iOS-Calendar-Template-Migration.md). Other planning/review data, canonical account-bound selections and complete workspace export/import remain pending.


### Verified original-file and Asset preparation update

Supported User Data Model versions: 1.0. Native preview now emits account-unbound `AssetPreview.json`, linking attachment/background references and all preserved originals to stable media identities with verified size/checksum, explicit missing-file review and drawing derivation. Canonical account-owned Assets and cloud transfers remain pending. See [file verification and manual test](iOS-Asset-Migration.md). The current focused suites pass 51 native tests and 77 model/tooling checks; earlier counts describe prior checkpoints.


### Profile/preferences and Today shortcut checkpoint

Supported User Data Model versions: 1.0. Native previews now prepare local profile/effective preference drafts with explicit source/default provenance and avatar links, and convert saved Today shortcuts using exact owner-qualified membership/order. Account-required profile/preferences remain unbound; Studio and other appearance/planning/review adapters remain pending. See [current settings mapping and acceptance](iOS-Settings-Migration.md). Current focused checks pass 56 native tests and 80 model/tooling tests.


### Studio and remaining appearance preparation

Supported User Data Model versions: 1.0. Previews now convert saved artwork payloads and prepare Studio/global Week appearance with exact surface/file references. Global Week defaults and multi-artwork ordering lack complete canonical destinations in the immutable released contract; they are retained in local evidence with explicit mapping-review notices, not silently merged or dropped. See [Studio mapping, representation gaps and acceptance](iOS-Studio-Migration.md). Current focused checks pass 60 native tests and 83 model/tooling tests. These representation gaps, account binding, daily plans/reviews and complete workspace recovery remain pending.


### Daily plans, check-ins and review history checkpoint

Supported User Data Model versions: 1.0. Native previews now convert daily plans, weekly/periodic reviews and reminder intent while retaining historical writing/progress, exact source-creation references and nullable history. Missing/deleted targets stay explicit; review decisions and notifications are never executed. See [planning mapping and acceptance](iOS-Planning-Review-Migration.md). Current focused coverage passes 65 native tests and 86 model/tooling checks. Appearance representation gaps, verified ownership and complete portable recovery remain pending.
