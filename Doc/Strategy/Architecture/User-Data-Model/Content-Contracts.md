# Content contract guide

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

[Specification](Specification.md) defines complete Card/Note, List, Collection and selection records. Exact wire names and bounds are in the [field dictionary](Field-Dictionary.md) and [registry](Contracts/1.0/registry.json).

Canonical content documents and server revision frames are distinct. Lists retain ordered active/archived Card references; Collections retain ordered Lists. Moves and membership changes are atomic transactions against the affected records. Ownership is stable identity, never a title. Selections preserve bookmark and 0–5 importance independently from content. Explicit unavailable-reference records and retained tombstones preserve unresolved legacy and historical targets.

Nested checklists preserve active and retained inactive values. Existing rich-text and history encodings are documented in [Value types](Value-Types.md); unsupported content is preserved with unsafe writes blocked. History is user content, distinct from authoritative server revision provenance.

The Python reference suite validates schemas and semantic relationships. Swift/C# codecs preserve valid JSON examples; the web probe additionally checks structural expectations. These checks are not native migration, live authorization or end-to-end synchronization. See [Conformance](Conformance.md), [Migration](Migration.md) and [Synchronization](Synchronization.md).
