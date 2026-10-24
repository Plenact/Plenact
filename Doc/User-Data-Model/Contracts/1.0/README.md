# Plenact User Data Model 1.0 contracts

**Supported User Data Model versions:** 1.0 final specification; protocol 1.0.
**Status:** Definition and conformance tools complete. Application/API integration is separate.

The [Specification](../../Specification.md) is normative together with these schemas and its linked rules. The [registry](registry.json) lists all 48 local schema resources and 24 canonical record types. The [OpenAPI document](openapi.json) specifies the reserved HTTP interface, not a deployed service. The [fixture manifest](Fixtures/manifest.json) contains 167 expectations, with 67 valid examples.

| Schema | Title |
| --- | --- |
| [account-deletion-receipt](account-deletion-receipt.schema.json) | account-deletion-receipt.schema |
| [account-deletion-request](account-deletion-request.schema.json) | account-deletion-request.schema |
| [account](account.schema.json) | account.schema |
| [api-error](api-error.schema.json) | api-error.schema |
| [asset-purge-receipt](asset-purge-receipt.schema.json) | asset-purge-receipt.schema |
| [asset-purge-request](asset-purge-request.schema.json) | asset-purge-request.schema |
| [asset-upload-commit](asset-upload-commit.schema.json) | asset-upload-commit.schema |
| [asset-upload-request](asset-upload-request.schema.json) | asset-upload-request.schema |
| [asset-upload-session](asset-upload-session.schema.json) | asset-upload-session.schema |
| [asset](asset.schema.json) | Portable asset metadata; no local paths, credentials or implicit upload endpoint |
| [calendar-index](calendar-index.schema.json) | Calendar selection and cross-week checklist-link ownership |
| [calendar-week](calendar-week.schema.json) | Week metadata referencing a separately defined Collection |
| [card](card.schema.json) | Complete Card/Note content document, not a server revision envelope |
| [changes-page](changes-page.schema.json) | changes-page.schema |
| [client-capabilities](client-capabilities.schema.json) | Client capability offer, not an endpoint |
| [collection](collection.schema.json) | Complete Collection content document; bookmarks are separate personal selections |
| [content-graph](content-graph.schema.json) | Offline content graph fixture/export slice; not a synchronization API envelope |
| [content-selection](content-selection.schema.json) | content-selection.schema |
| [content-types](content-types.schema.json) | Nested portable content types; not a standalone user record |
| [daily-plan](daily-plan.schema.json) | Daily intention, check-in history and evening review |
| [date-value](date-value.schema.json) | Plenact date value |
| [label-category](label-category.schema.json) | label-category.schema |
| [label](label.schema.json) | label.schema |
| [list](list.schema.json) | Complete List content document |
| [periodic-review](periodic-review.schema.json) | Private periodic reflection with separate starting/current objectives |
| [planning-graph](planning-graph.schema.json) | Calendar/planning/media metadata graph slice; not a sync request or complete backup |
| [planning-template](planning-template.schema.json) | Independent template-owned Collection and source-day mappings |
| [planning-types](planning-types.schema.json) | Planning/review nested values; not a sync record |
| [protocol-types](protocol-types.schema.json) | Protocol value definitions |
| [read-only-capture](read-only-capture.schema.json) | read-only-capture.schema |
| [review-rhythm](review-rhythm.schema.json) | Shared invitation/notification intent; OS permissions and scheduling remain device local |
| [rich-text-runs](rich-text-runs.schema.json) | rich-text-runs.schema |
| [server-record](server-record.schema.json) | server-record.schema |
| [service-capabilities](service-capabilities.schema.json) | service-capabilities.schema |
| [snapshot-page](snapshot-page.schema.json) | snapshot-page.schema |
| [studio-artwork](studio-artwork.schema.json) | studio-artwork.schema |
| [studio-settings](studio-settings.schema.json) | studio-settings.schema |
| [template-library](template-library.schema.json) | Template ordering, selected default and separate bundled revision provenance |
| [today-shortcuts](today-shortcuts.schema.json) | today-shortcuts.schema |
| [transaction-receipt](transaction-receipt.schema.json) | transaction-receipt.schema |
| [transaction-request](transaction-request.schema.json) | transaction-request.schema |
| [unavailable-reference](unavailable-reference.schema.json) | unavailable-reference.schema |
| [user-preferences](user-preferences.schema.json) | user-preferences.schema |
| [user-profile](user-profile.schema.json) | user-profile.schema |
| [weekly-review](weekly-review.schema.json) | Private weekly reflection and decisions |
| [workspace-display-preferences](workspace-display-preferences.schema.json) | workspace-display-preferences.schema |
| [workspace-export](workspace-export.schema.json) | workspace-export.schema |
| [workspace](workspace.schema.json) | workspace.schema |

Schema `$comment` headers declare supported versions. Fixtures inherit their version/status from the manifest; invalid fixtures must be rejected, not sent as production content. URN references resolve from this bundle. Nested values and transport messages are not independently persistent records.

Python checks structural and semantic rules; Swift/C#/JavaScript probes verify their stated boundaries. See [Conformance](../../Conformance.md) and [tool instructions](../../../../Tools/UserDataModel/README.md). No live data, app conversion or production API is included.
