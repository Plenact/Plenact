# Model 1.0 value types

**Supported User Data Model versions:** 1.0. **Protocol:** 1.0. **Specification status:** final.


## JSON and limits

Use UTF-8 JSON with unique object keys and Unicode scalar strings. Reject duplicate keys (including escaped equivalents), NaN/Infinity, unpaired surrogates and malformed UTF-8. Do not Unicode-normalize, trim, translate or case-fold authored writing. Object key order and insignificant whitespace do not affect document meaning; authored array order does. Request idempotency is stricter: retries reuse the exact original UTF-8 bytes.

Protocol message limit: 8,388,608 bytes. Canonical document limit within a transaction: 4,194,304 bytes when serialized with [RFC 8785 JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785). This fixes cross-language float/string/key serialization differences for the size check; it does not change the exact-byte request retry rule. The actual complete message must also fit its byte limit. Maximum JSON value-path depth is 64, with root depth 0 and each property value/array element consuming one level. A transaction has 1–100 operations and a page at most 100 records. Oversized source data remains preserved locally with an explicit error; implementations must never truncate it to fit.

JSON integer-valued fields are at most 2,147,483,647 unless a smaller schema bound applies. Revision/change counters are canonical decimal **strings**, 1 through 9,223,372,036,854,775,807; fence/after counters may be `0`. Asset byte lengths are canonical unsigned decimal strings through 18,446,744,073,709,551,615. They are never routed through a JavaScript Number. Metadata may describe a larger file than the service’s upload capability; that does not promise its transfer will be accepted. Floats must be finite and inside their explicit appearance bounds.

## Null, absence and legacy defaults

Complete document payloads contain every declared required field. Explicit null clears a nullable override or preserves unknown/absent source meaning. Empty string, empty array, false and zero remain distinct. There is no patch/null conflation in Protocol 1.0: clients send complete documents against a base revision. Legacy missing-field defaults are applied only by a compatible migration reader; they are not server instructions to manufacture examples.

## Stable tokens and appearance

Wire enum tokens are exactly those enumerated by each schema. Examples: Card/Note `card`/`note`; collection `list`/`board`; date kind `date`/`time`/`date_and_time`; action content `standard`/`linked_card`/`action_detail`/`web_link`; objective `active`/`achieved`/`paused`/`released`; star style `tucked`/`fanned`; maps `apple`/`google`; focus order `day_list`/`chronological`; List view `cards`/`note_list`. Legacy display strings/camelCase map explicitly; labels are never wire enums by inference.

The source catalogue records every source enum case. SF Symbol names, font names, provider photo IDs, source format names and bundled illustration identifiers are retained source tokens, not portable platform API calls. A client uses a suitable fallback renderer without overwriting an unsupported token. Unknown schema-defined enum cases block writes to that record until the client supports its model version.

RGB components, List opacity, surface strength/readability/vertical position are 0–1. Surface zoom is 1–2. Hex palette colors are uppercase six-digit sRGB. `legacy_token` preserves original color provenance; it must not override an explicit RGB value in the wire object. Nullable appearance properties preserve inheritance; explicit false can override true inherited italics. Effective styling is Card → List → Board → application default. Do not serialize a resolved appearance in place of its original overrides.

## Calendar dates and times

A `date` contains exactly `YYYY-MM-DD`, a valid proleptic Gregorian date in years 0001–9999. It has no timezone or UTC instant. A `time` contains exactly `HH:mm:ss.SSS`, a wall-clock time with no invented date or zone. Seconds range 00–59; no leap seconds or 24:00 values. Both retain intent across travel.

A `date_and_time` contains local `YYYY-MM-DDTHH:mm:ss.SSS`, IANA zone, IANA rules release, UTC instant with the same fixed millisecond precision and `Z`, signed `HH:mm` offset, and occurrence `unique`, `first` or `second`. Zone/offset/local time/instant must agree under the declared rules. A repeated time requires first/second in UTC order; a nonexistent spring-forward time is rejected, not silently shifted. Ordinary times require unique.

The service advertises accepted timezone-rules releases. New or deliberately edited timed values must use an advertised release. Clients preserve a historical timed value unchanged even if their installed rules differ; use its saved instant/offset for a safe read-only fallback. Do not silently rewrite values when timezone legislation changes. Editing requires compatible rules and explicit user intent. A non-date metadata edit may retain an identical historical date value already accepted at the base revision without reinterpreting it under newer rules.

The reference fixtures pin IANA 2025b for deterministic DST checks. This fixture dependency is not a permanent product restriction. Production timezone-package distribution is an implementation requirement; newly supported rule releases are advertised as capabilities without changing Model 1.0 structure.

Source Weeks lack a separately stored timezone. Migration needs source/template evidence or user confirmation. Preserve original epoch/date-kind bytes when intent is ambiguous. Submillisecond source precision must stay in private migration evidence if the millisecond wire field cannot represent it. No application may guess a historic timezone or silently drop precision to declare conversion complete.

## Rich text

Rich-capable fields are Card/Note description overrides, Action Detail descriptions and comment bodies, including those inside templates. Other titles/labels/reflections remain literal strings unless their UI explicitly supports this format. Every string’s original bytes must survive round trips.

The retained explicit format is `plenact-rich-v1:` followed by standard base64 of UTF-8 JSON runs. The [run schema](Contracts/1.0/rich-text-runs.schema.json) defines text, required bold/italic Booleans, optional color/fontName/fontSize attributes. Runs are ordered and concatenate to plain display text. Optional font size is positive and at most 512 points. Color/font names are tokens; unavailable fonts fall back without modifying stored attributes.

A prefix whose base64/JSON cannot decode is literal text, matching the existing app. A decodable run sequence containing unsupported attributes is preserved opaquely and read-only; it is not flattened into a new plain string or silently restyled on save. Explicit user replacement is a new edit. Render plain text/runs as text, never executable HTML. The model is not tied to UIKit attributed-string serialization.

## Nested identity and history

Checklist/action/comment/reaction/history UUIDs identify owned nested values. Preserve inactive retained action data. A redundant active detail and its identical retained mirror are validated once; divergent mirrors require explicit resolution. Cross-week checklist links require an unambiguous mapped item identity.

Legacy history values use canonical base64 plus explicit `swift_codable_json` / `local_legacy` tags. They remain opaque source values until a tested typed converter exists. Do not execute them, interpret them as current user-data records, or create new history merely by importing remote state. Server revisions and per-Card history entries are different concepts.

## Source enum tokens

[Source coverage](Source-Coverage.json) and the [catalogue](Source-Field-Catalogue.md) enumerate frozen source tokens, including illustration names and legacy transport cases. The schema registry is authoritative for wire tokens. Adding a new source enum case does not silently extend a frozen wire enum.
