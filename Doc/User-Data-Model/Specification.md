# Plenact User Data Model 1.0

**Supported User Data Model versions:** 1.0. **Protocol:** 1.0. **Specification status:** final.


**Title:** Defining Plenact’s User Data Model for cloud synchronization and synchronization between application versions on iOS, Plenact.com web, and Windows C#.
**Owner scope:** One private owner initially, Justin Reina, identified by a verified stable account UUID. The display name is not an authorization identifier.
**Implementation boundary:** This release defines the contract. It does not implement or deploy client migration, login, storage, synchronization or media transfer.

## 1. Authority and release identity

MUST, MUST NOT, SHOULD and MAY express implementation requirements. The schemas under `Contracts/1.0`, the semantic rules in this specification and its normative companion documents, and the conformance expectations together define Model 1.0. Passing a JSON Schema check alone does not establish identity, reference, authorization, date or concurrency validity.

Normative companions: [Value types](Value-Types.md), [Synchronization](Synchronization.md), [Assets](Assets.md), [Compatibility](Compatibility.md), [Data lifecycle](Data-Lifecycle.md), [logical cloud storage](Logical-Storage.md), [Migration](Migration.md), [source coverage](Source-Coverage.json), [registry](Contracts/1.0/registry.json), and [OpenAPI](Contracts/1.0/openapi.json). The [field dictionary](Field-Dictionary.md) provides source mapping context. Runtime/tooling evidence is recorded separately in [Conformance](Conformance.md).

Model `1.0`, protocol `1.0`, application versions, per-type payload version `1`, SQL migrations and server record revisions are separate namespaces. Version 0, “Getting Cloud Connection Established,” retains its existing `schema_version: 1` and migration `001`; neither is renamed into Model 1.0. Its shared-demo routes and data remain separate.

Published artifacts are identified by Git tag `user-data-model-v1.0`, the release asset checksums and resource URNs. Files in a published 1.0 package are immutable. Corrections that change acceptance, meaning or supported fields require a new version/release and explicit negotiation; no client may assume decimal version strings imply compatible structure.

## 2. Scope and lifecycle classification

The synchronized model includes committed Collections/Boards, Lists, Cards/Notes/dividers, metadata, sections, checklists, comments/reactions/history, archive state, labels, calendar Weeks, plans/reviews/objectives, templates, bookmarks/importance, profile/personalization, reusable artwork, shortcuts and owned asset metadata/binaries.

Preferences follow the user by default. Window geometry, viewport/navigation state, local OS permissions, scheduled notification requests, credential material, unfinished creation drafts, recent search/open history and recovery machinery are device-owned. These values are explicitly classified rather than omitted accidentally. A notification preference synchronizes; the local permission grant does not. A preferred maps provider survives unsupported-platform fallback without being overwritten.

[Source coverage](Source-Coverage.json) classifies every audited Codable declaration, stored field and Plenact key/prefix. It is a frozen source baseline, not a requirement to reproduce Swift storage layouts in other languages. Derived presentation strings and computed properties are not independent canonical records.

## 3. Canonical records and identity

The [registry](Contracts/1.0/registry.json) enumerates the complete persistent record types and all schema resource identities. Every canonical document has `user_data_model_version`, `payload_schema_version`, `record_type`, `id`, `workspace_id`, and `payload`. This includes user preferences and personal content selections; no synchronized preference is keyed only by an unqualified Card integer.

New content IDs SHOULD be cryptographically random UUIDs. Accepted UUID strings are lowercase, hyphenated, with a nonzero supported version and RFC variant. Legacy IDs require durable owner-qualified mapping. IDs remain stable through moves; copies and template application create fresh live identities, including owned nested content where identity must not be shared. Names, weekdays, email text and array positions never establish identity.

Account and workspace records are server-owned. A client cannot change account identity, workspace ownership or server lifecycle through ordinary record transactions. The profile is editable personal content; its original profile UUID, name and unverified email do not establish a remote account. There is one private workspace in the initial service contract. Sharing and tenancy roles are not implicitly enabled.

## 4. Relationships and ordering

Collections contain ordered List IDs. Lists contain separate ordered active and archived Card IDs. Cards identify their containing List. Both sides MUST agree. A current List/Card has one canonical parent. Transactions that move content MUST include all affected parent membership/order documents and the moved content document, with expected revisions for every changed record. The service validates the resulting graph atomically; it never leaves a Card in two Lists.

Ordering uses UUID arrays, not floating-point ranks or timestamps. Concurrent changes to the same List order conflict at the List revision. Unrelated records can change independently. Archives preserve content and order; archive is not deletion and does not implicitly overwrite descendant archive flags.

Special List titles are display/default behavior, not authorization or identity. Date-key-to-List mappings establish Day ownership. Enabling time ordering affects both Day Lists and Today’s Focus: clients order timed start values, otherwise timed due values, ahead of untimed items within existing section boundaries, preserving prior order for equal times. Zoned values use the owning Week’s timezone; time-only values remain local wall time. Date-only values are untimed. Canonical accepted arrays reflect explicit client reorder transactions; the server does not invent reorder writes from a date edit. Pending display order must not be mistaken for a successfully synchronized order.

## 5. Historical and unavailable content

Review priorities, decisions, check-ins and starting objectives are historical snapshots. Their titles/context must not be refreshed from live source Cards. Null history differs from empty history; unknown source dates/counts differ from invented defaults. The same objective ID may occur in starting and current snapshots with different values. Redundant active/retained checklist detail mirrors are allowed only when identical; inactive retained values remain preserved.

An `unavailable_reference` is an explicit owner-private record for an unresolved legacy target. It stores target type/ID, reason and optional display text. It neither creates the target nor grants permission to read it. Export-level external-reference indexes are derived from actual records, these explicit unresolved-reference records and tombstones. They are not authoritative access grants or a way to hide an orphaned current parent.

Tombstones preserve deletion identity. Review links, saved selections and other non-parent references may render unavailable when their target is tombstoned. A deleted List/Collection cannot retain live canonical children: the deleting transaction must move or delete the children and update membership consistently. Parent preference references may retain unavailable intent; clients offer a fallback without silently rewriting it.

## 6. Authorship and source provenance

Manual assignees use `identity_scope: manual` and null user ID. Retained Version 0 directory identities use `legacy_demo`; they are provenance, not authenticated Model 1.0 accounts. A new owner-account assignment uses `owner_account` and the verified owner UUID. Name matching never upgrades a manual/legacy assignee into an account.

Comments and reactions retain historical author labels/IDs and nullable `author_account_id`. Legacy attribution is null unless verified mapping establishes it. New authenticated authorship must match the workspace owner; display text is not proof. Source reaction-author UUIDs remain distinct from account IDs. Server revision actor/time metadata is authoritative and cannot be supplied by clients as editable content.

## 7. Dates, text, numbers and binary assets

[Value types](Value-Types.md) fully specify JSON, UUIDs, counters, enum tokens, date-only/time-only/zoned values, rich text, colors and null/default rules. [Assets](Assets.md) defines metadata completeness independently of remote-byte verification, resumable transfer, exact hashes, derivatives and explicit purge. Unsupported formats remain intact; a preview cannot replace an editable original.

## 8. Synchronization and compatibility

The [synchronization contract](Synchronization.md) defines an authenticated baseline, complete snapshots, ordered changes, atomic revision-checked writes, exact-byte idempotency, conflict resolution, deletion retention, restore epochs and finite cursor leases. Local content/outbox has no application-imposed expiration. Expiring credentials or cursors affect network exchange, not local usability.

All three clients implement the same wire semantics. Platform UI frameworks and local database layouts may differ. [Compatibility](Compatibility.md) defines capabilities, unknown-field behavior, browser durability and platform adaptation. Current application support is tracked separately from specification completeness.

## 9. Conformance and publication boundary

A conforming implementation MUST satisfy the structural schemas and semantic rules, preserve every supported field, enforce authenticated ownership and atomicity, pass relevant positive/negative cases, and demonstrate its own persistence/transport recovery. Codec probes alone cannot establish production synchronization conformance.

The definition is complete for Model 1.0’s stated scope. Implementation choices such as database indexes, UI widgets, framework package releases and account-session issuance belong behind defined interfaces; they do not change the wire model. No publication action enables the reserved API namespace or uploads a personal workspace.
