# Model 1.0 GitHub publication

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

The immutable definition release is [Plenact User Data Model 1.0](https://github.com/Plenact/Plenact/releases/tag/user-data-model-v1.0), tagged **`user-data-model-v1.0`**. This namespace is separate from application tags such as `v1.4`.

Release assets comprise the complete documentation/schema/tool ZIP, a standalone OpenAPI JSON document and `SHA256SUMS`. The ZIP includes `MODEL-MANIFEST.json` with exact per-file SHA-256 values, version/status, client targets and implementation boundary. Links outside the ZIP are pinned to the release tag. Source is available in the same tag; no external schema fetch is required to validate the bundled URN registry.

Download assets from the release page, verify `SHA256SUMS`, extract to a new directory and follow [tool instructions](../../Tools/UserDataModel/README.md). Run `publication_gate.py --verify-package` on the downloaded ZIP. Hashes detect byte changes; release/checksum retrieval must use your trusted GitHub connection. This release does not include a separate cryptographic publisher signature.

The tag is the frozen 1.0 contract. Subsequent incompatible wire changes require a new model/type/protocol version under [Compatibility](Compatibility.md), not replacement of this release's files. Editorial corrections should be clearly identified in a new documentation release while preserving this tag.

Publication on GitHub does not deploy the reserved HTTP routes, enable app synchronization, publish a Plenact.com documentation site or upload personal data. The [integration plan](Integration-Plan.md) describes the next implementation milestone.
