# Source formats to Model 1.0

**Supported User Data Model versions:** 1.0. **Protocol:** 1.0. **Specification status:** final.


## Source audit and boundaries

[Source coverage](Source-Coverage.json) freezes an audit of 96 Codable declarations, 379 stored fields and 41 key/prefix segments. It includes rich-text runs, nested storage wrappers, recovery/device-only data and Version 0 transport. [Source catalogue](Source-Field-Catalogue.md) explains each lifecycle and target. This coverage is a definition audit, not an implemented field converter.

Keep existing local preference names/versions and Version 0 wire contracts unchanged. Read actual saved bytes through compatible decoders; never treat sample/fallback output as saved content. Preserve a frozen private source capture and media hashes before conversion. A corrupt/unsupported store is a blocking report, not an empty/default replacement. Unclassified keys require explicit lifecycle classification before a complete migration can be claimed.

## Stable identity mapping

Persist the mapping journal before exporting canonical IDs. Qualify source records by source installation/export namespace, source owner, record kind, legacy ID and source creation discriminator where needed. Keep the same mapping through retries. Moves preserve canonical identity; copies/template application allocate fresh live ownership identities. Never merge by title, weekday, email or an unqualified integer.

Source Week.id is computed as its Collection.id. Give the Week metadata document its own mapped identity and retain the Collection reference; do not invent a second stored legacy ID or duplicate the embedded content. The active Board can be a projection of a stored Week. Deduplicate only when source ownership and content establish that fact; divergent snapshots remain preserved for explicit resolution.

Map label/category string IDs and all bookmarks/importance/default List/shortcut/checklist/review references under the same owner-aware journal. Restore source-origin text and unknown creation times exactly. Ambiguous/dangling legacy references become explicit unavailable_reference records with mapped target IDs and preserved private journal evidence, never fabricated live Cards. Repeated checklist UUIDs across owners require disambiguation before cross-week linking.

## Content, dates and authorship

Preserve null/empty/false/inheritance, inactive retained action content, archive order, reactions, captions, rich text and opaque history. A first portable document includes all required fields after compatible source decoding; it does not reset omissions using another platform’s current defaults.

Use source/template timezone evidence or user confirmation for historic dates. Keep the original epoch, kind and submillisecond bytes in the journal. Do not guess device-current timezone. Step counts, check-in IDs and objective snapshot identities retain their meanings. Historical titles/context do not update when a live Card changes.

Keep manual names manual. Version 0 registered assignments retain legacy_demo scope unless verified account linking establishes owner_account. Historical comment/reaction author_account_id is null unless the source-to-owner mapping is proven. No name/email comparison confers account access.

## Assets and settings

Hash exact originals and associate portable Asset IDs without deleting filenames or source-format evidence from the private journal. Missing bytes stay unavailable, not empty. Preserve editable drawings and derivatives independently. Provider attribution follows the metadata; credentials never become a user record.

Preferences follow the user, while source recent-history, viewport, unfinished drafts, local reaction identity and OS scheduling/recovery stay device-local. Preserve those local values during conversion instead of copying them as cross-device commands. Standalone planning preferences take precedence under the source resolver; retain conflicting profile preference bytes for inspection. Do not coerce wrong stored Boolean/native types into defaults.

## Completion and rollback

A complete migration requires: all synchronized source fields accounted for; references resolved or explicitly unavailable; no unexplained count/content/hash loss; compatible timezone decisions; valid complete workspace-export; durable ID mapping; and recovery evidence. Unresolved conversion must not be advertised as cloud-synchronized.

Before upload, restoring the private captured bytes can recover source state; a restore tool must itself be implemented and tested. After network writes, restoring local bytes alone is not a server rollback. Reconcile against server epochs/revisions and preserve receipts/outbox evidence. The current capture tool intentionally reports portable_conversion_complete=false; changing that flag is not an adapter.

## Current implementation follow-up

See [native iOS backup/export](iOS-Migration-Export.md), [versioned SQL/JSON examples](Doc/Examples/README.md) and the [current application/data plan](../Application-Data-Plan.md). The frozen GitHub Model 1.0 release remains unchanged; this working-branch documentation records subsequent implementation progress.

## Native identity and first converters

The working branch implements a durable private identity journal plus label/category and shared-display preview conversion. See [native identity/preview status](iOS-Migration-Identity.md). The source audit above remains the frozen definition-release baseline; new native journal types are device migration machinery, not additional synchronized record types. Full workspace conversion and verified account binding remain pending.
