# Model 1.0 asset lifecycle

**Supported User Data Model versions:** 1.0. **Protocol:** 1.0. **Specification status:** final.


## Meaning of asset data

An Asset document owns stable identity, account/workspace, declared kind/MIME, optional original basename, completeness state, exact byte length/SHA-256, source format, optional original/derivative reference, source timestamp and attribution. No local path, provider credential, signed download URL or cloud bucket locator belongs in user content.

`described` means both exact length and digest are known, not that bytes have reached the server. `unavailable` means both remain unknown; zero is a known empty file, not a substitute for missing bytes. Length is a canonical unsigned decimal string. Each service advertises max_upload_bytes between 1 and 1,073,741,824; quota/capability failures leave originals local and unsynchronized. Metadata may retain an oversized source description without promising upload.

The server-record asset_content descriptor is separate: unavailable has null length/hash/verified time; verified has exact matching metadata and a verified timestamp. Only the server can establish remote-byte verification. A non-asset record has null asset_content. Tombstones contain no live document or asset-content descriptor.

## Resumable transfer

1. Create/update an Asset metadata document through an ordinary revision-checked transaction. It must belong to the authenticated workspace owner. A verified Asset’s byte length/hash are immutable; changed original bytes get a fresh Asset UUID.
2. POST asset uploads with workspace/epoch/asset ID/revision and the same declared length/hash. The service creates a 24-hour temporary staging lease. Retrying this lease creation can produce another temporary lease; it cannot duplicate committed content.
3. Stage chunks of exactly 262,144 bytes except the final shorter chunk. Indexes start at zero. Zero-byte content has no chunks. Each PUT includes its own exact SHA-256. Repeating the same chunk succeeds; different bytes at an already accepted index conflict. GET the session to resume accepted indexes.
4. Commit with the upload ID and a fresh operation UUID; Idempotency-Key equals operation_id. Check current epoch, unchanged Asset revision, all indexes, total length and SHA-256 of concatenated bytes. Incomplete/corrupt data never becomes verified.
5. Atomically publish the verified immutable blob and a new Asset revision/change with its verified descriptor. Exact commit retries return the same historical result. A new metadata revision during staging requires explicit reconciliation/restart; it must not publish against the wrong base.

Uncommitted staging chunks may be removed seven days after lease expiry. This does not purge an owned original or make the client discard its source; an expired upload restarts under a new lease. Operation/commit deduplication evidence survives for the account lifetime.

## Retrieval and local storage

Only authenticated authorized requests can download bytes. Return a strong SHA-256 ETag, correct length, nosniff and safe attachment disposition. HTTP Range/If-Range supports resumption; a changed ETag requires a clean restart. Verify the complete final file’s length/hash before installing it atomically in local storage. Do not treat a partial/truncated file as an available original.

Previously downloaded owned originals have no application-imposed expiry. Unsynced originals must not be evicted automatically. Users may explicitly clear downloaded media when its remote verification is known; render honest offline/unavailable placeholders until it is fetched again. Platform/browser storage loss is distinct from an intentional application retention policy.

Derivatives refer to their original Asset and cannot form cycles. Preserve editable originals even when a client only renders the preview. Unsupported native formats, including PencilKit, are opaque bytes on platforms without an editor. A client must not overwrite them with a raster image. Declared MIME/source format is not proof of byte validity; the implementation validates formats it renders and otherwise offers safe download/pass-through behavior.

## Retention and explicit removal

Model 1.0 does not automatically garbage-collect owned unreferenced assets. Unlinking a cover/attachment/background is not immediate physical deletion. History, older clients and recovery need an explicit lifecycle.

A client first tombstones the Asset in a transaction that removes all live typed references. The server rejects inconsistent references. Physical purge is a separate owner-confirmed request against that tombstone revision, with confirmation PURGE_UNREFERENCED_ASSET and explicit acknowledgement that opaque history media may become unavailable. Reject a purge if live typed references remain. Remove primary bytes within 24 hours and backup copies within 30 days; retain the minimal Asset tombstone and purge receipt until account deletion. No automatic history-byte interpretation or reference guessing is permitted.

Account deletion follows the separate data-lifecycle policy. Attribution/provider IDs and source links survive normal metadata moves/copies. API keys never enter the model. The synthetic opaque original in the conformance suite is not a real PencilKit file; its test establishes byte preservation, not native decoding.
