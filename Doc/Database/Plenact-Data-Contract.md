# Current Plenact data contract — Model 1.0

**Supported User Data Model versions:** 1.0; Version 0 historical reference only.
**Updated:** October 24, 2026.

The authoritative definition is [User Data Model 1.0](../User-Data-Model/Specification.md), published as [user-data-model-v1.0](https://github.com/Plenact/Plenact/releases/tag/user-data-model-v1.0). The former shared-demo contract is preserved at [Version-0/Plenact-Data-Contract.md](Version-0/Plenact-Data-Contract.md).

Model 1.0 includes Collections/Boards, Lists, Cards/Notes, nested checklist/action content, comments/reactions/history, labels, calendar Weeks, daily plans, reviews/objectives, routine templates, profile, shared settings, Studio/artwork, bookmarks/importance, shortcuts, owned assets and explicit unavailable legacy references. Exact fields and nullability are in the [registry](../User-Data-Model/Contracts/1.0/registry.json) and [field dictionary](../User-Data-Model/Field-Dictionary.md).

Every canonical document carries model/payload versions, type, UUID, workspace UUID and payload. Server frames add epoch/revision/change sequence, authenticated provenance and deletion state. Per-type payload versions, application versions, database migration numbers and the historical demo wire schema are distinct.

The service verifies one private account/workspace owner. Complete revision-checked record transactions are atomic, with full-graph validation, exact request-byte idempotency, preserved conflicts, retained tombstones and fresh-epoch reconciliation after a potentially lossy server restore. Local offline edits never expire automatically.

JSON defines shared meaning; SQL/MySQL implements durable storage. See [storage plan](Model-1.0-MySQL-Plan.md), [synchronization](../User-Data-Model/Synchronization.md), [assets](../User-Data-Model/Assets.md), [privacy/retention](../User-Data-Model/Data-Lifecycle.md) and [migration](../User-Data-Model/Migration.md). The physical production schema and all application sync adapters still require implementation and acceptance testing.
