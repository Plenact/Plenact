# Calendar, planning/review and asset contracts

**Supported User Data Model versions:** 1.0 final specification. Version 0 is reference only.
**Status:** Schemas, local semantic checks, synthetic fixtures and standalone Swift/C# codec probes implemented. No application migration, upload API or live synchronization.

## Coverage and record boundaries

| Schema | Purpose |
| --- | --- |
| [calendar-week](Contracts/1.0/calendar-week.schema.json) | Week date, independently mapped record identity, Collection reference, day-to-List mapping and save intent. |
| [calendar-index](Contracts/1.0/calendar-index.schema.json) | Calendar ordering references, preferred Week start, weekday convention and cross-week checklist links. |
| [planning-types](Contracts/1.0/planning-types.schema.json) | Priority snapshots, current check-in, submitted history, mood, review decisions/actions, evening review, objectives and template example markers. |
| [daily-plan](Contracts/1.0/daily-plan.schema.json) | Daily intentions, concerns/constraints, selected priorities, vision progress, check-ins and evening review. |
| [weekly-review](Contracts/1.0/weekly-review.schema.json) | Week context, reflection, decisions and completion. |
| [periodic-review](Contracts/1.0/periodic-review.schema.json) | Inclusive date range, starting/current objective snapshots and reflection. |
| [planning-template](Contracts/1.0/planning-template.schema.json) | Independent template Collection, source weekday mapping and example focus. |
| [template-library](Contracts/1.0/template-library.schema.json) | Ordered templates, default Week template and bundled-library provenance. |
| [review-rhythm](Contracts/1.0/review-rhythm.schema.json) | Shared invitation/notification preferences, excluding OS scheduling and permission. |
| [asset](Contracts/1.0/asset.schema.json) | Owned metadata, exact byte length/hash, source format, attribution and original/derivative reference. |
| [planning-graph](Contracts/1.0/planning-graph.schema.json) | Offline relationship-validation bundle joining this slice to the existing content graph. |

All records use the common complete-value envelope. This graph is a relationship-validation slice, not a backup or write request. The final [Specification](Specification.md), [Synchronization](Synchronization.md) and [Assets](Assets.md) define the complete workspace, server frames, operations and transfer contract.

## Calendar identity, timezone and dates

The current Swift `DatedPlanningWeek.id` is **computed as `collection.id`**, not a second stored UUID. Model 1.0 gives the Week metadata record and its Collection separate record identities. Migration retains their explicit relationship and the legacy collection identity in the mapping journal; it must not invent a second source identifier or duplicate the Collection's content.

| Source | Portable mapping |
| --- | --- |
| `DatedPlanningWeek.startKey` | `start_date`, a Gregorian calendar date. |
| `collection` | `collection_id` referencing separately stored Collection/List/Card content. |
| `dayListIDs` | Ordered `day_lists` entries containing a date and mapped List UUID. |
| `explicitlySaved` | `explicitly_saved`; distinct from server synchronization state. |
| `PlanningCalendarDocument.version` | `source_store_version`, not User Data Model or payload version. |
| `currentWeekKey` | `current_week_start_date`; preserve preference even if that Week is not materialized. |
| `firstWeekday` | `first_weekday`, Sunday=1 through Saturday=7. |
| `weeks` | Ordered `week_ids`; standalone Week records preserve their own date/context. |
| `checklistLinkWeeks` | Checklist-item UUID → target Week-record UUID entries. |

Week metadata introduces `first_weekday`, `time_zone` and `time_zone_source` explicitly. The legacy Week itself does not persist a zone. Migration must use proven source context/template context or user confirmation; do not substitute the migrating computer's timezone. If context cannot be established, preserve local data and report the unresolved conversion.

A Week starts on its declared weekday. Mapped dates must fall within its seven Gregorian dates, with no repeated date or List. Partial day mappings are allowed; missing days do not create invented Lists. A mapped List must belong to that Week's Collection and be active. Day membership uses calendar dates across daylight-saving changes, never fixed 168-hour arithmetic. Weeks keep their own first-weekday convention; changing a global preference must not silently reanchor historical Weeks.

The combined graph requires each Week to appear in the single calendar index; cross-week links must reference a retained checklist item and a known Week. A checklist UUID duplicated across Cards is ambiguous and must be remapped explicitly before linking. The preferred start date can describe an unmaterialized Week. Source ordering is preserved; no implicit chronological resort is part of serialization.

## Daily plans and historic snapshots

| Source fields | Portable mapping |
| --- | --- |
| `DailyPlan.id`, `timeZoneID` | `date`, `time_zone`; new document UUID comes from a durable map scoped to the source plan. |
| `intention`, `constraints`, `concerns`, `priorities` | Same authored meaning; ordered priority snapshot objects. |
| `updatedAt`, `visionStep`, `visionCompletedAt` | Nullable UTC timestamp, nullable 0–2 step, nullable vision completion time. |
| `checkIn`, `checkIns`, `eveningReview` | `check_in`, `check_ins`, `evening_review`; independently preserved. |
| `DailyPlanPriority.ownerID`, `cardID` | `source_collection_id`, mapped stable `card_id`. |
| `title`, `location`, `sourceCreatedAt` on a priority | Historical `title`, `source_location`, nullable source creation timestamp. `location` here is the List/Collection display context, **not the Card address**. |
| `DailyCheckIn.focus`, `changed`, `savedAt` | Nullable snapshot, authored text, nullable saved time. |
| `DailyCheckInEntry` fields | Preserve string ID, saved time, changed text, focus, intention/constraints/concerns, priorities, task/note/unavailable counts, legacy flag and optional mood. |
| `CheckInMood.emoji`, `label` | Preserve submitted emoji/text; no translation into a preset-only enum. |

A nullable `check_ins` array is distinct from an explicitly empty array. Legacy string IDs such as `legacy:2026-10-24` remain valid; do not generate new IDs on each read. Historical task counts can be unknown (null); a known zero means zero. Counts must be nonnegative, with completed ≤ total when both are known. Current saved check-in and history snapshots need not contain identical writing because later edits must not rewrite history.

Priorities are unique within each selection array by source Collection plus mapped Card identity. Repeated references across different historical snapshots are expected. The combined graph requires each source Card/Collection to be known or explicitly external/unavailable. It does not rewrite historical titles or insist that a moved Card still occupies its original Collection. Identity migration must resolve source creation discriminators before assigning portable references.

## Reviews and objectives

- `DailyEveningReview`: retain 0–2 step, nullable completion time, helped/difficult/tomorrow text, ordered decisions and achievement snapshots.
- `DailyReviewDecision`: retain UUID, source/result snapshots, action and recorded time. All eight actions are explicit: keep, keep_tomorrow, table, complete, archive, queue, tomorrow, or date with a real Gregorian target day. A stored decision records history; reading it must not execute the action again.
- `WeeklyReviewRecord`: retain source review key, start date, timezone, first weekday, step, highlights/learned/direction/constraints/risks, priorities, decisions and timestamps. The source review key is provenance, not a new cloud-account identifier.
- `PeriodicReviewRecord`: retain UUID, title, inclusive start/end dates, timezone, step, highlights/learned/direction/risks, starting objectives, current objectives, priorities and timestamps. End must not precede start.
- `ReviewObjective`: retain UUID, title, progress, next step and status. Legacy display statuses Active/Achieved/Paused/Let go map explicitly to active/achieved/paused/released.

Objective UUIDs must be unique **within each** objective array. The same objective can appear in starting and current arrays with different progress/status; these are deliberate snapshots, not duplicate live records. Review decision IDs are unique within each decision list. Step values preserve existing 0–2 behavior; nullable completion remains independent and must not be fabricated from step alone.

## Templates, library and review cadence

Templates preserve name/kind (day/week), anchor date, timezone, first weekday, Collection reference, weekday-to-List mapping and optional example focus. Their content ownership must be independent of live Week ownership. A Day template maps one source List; a Week template maps one to seven distinct weekdays/Lists. Example importance/bookmark/all-day markers must reference Cards in that template's Collection, including retained archived source content where present. Applying a template still requires fresh live identities in a later app adapter.

The template library retains source store version, ordered template IDs, nullable default Week-template ID and nullable bundled routine revision. The combined bundle requires template-library membership to cover the retained templates; the default must name a Week template. Bundled revision 5, local store version 1 and User Data Model 1.0 remain separate values.

Review-rhythm preferences retain all seven current fields: daily/weekly invitations, daily/weekly minute-of-day values (0–1439), weekly weekday (1–7), and daily/weekly notification intent. Permission grants, local request IDs, scheduled deliveries and device coordination state are not copied as user preferences. Duplicate notification coordination remains an integration task.

## Asset metadata and bytes

| Field | Meaning |
| --- | --- |
| Envelope `id`, `workspace_id` | Stable asset identity and workspace; never a device filename. |
| `account_id` | Owner reference; the server must verify it from authentication rather than trusting the payload. |
| `kind`, `mime_type` | image/video/audio/drawing_original/binary and declared lowercase media type; byte-format inspection is a separate runtime requirement. |
| `original_name` | Optional basename for display, not a local path or download destination. |
| `content_state` | `described` when both length and SHA-256 are known; `unavailable` when neither is known. This is metadata completeness, not an upload/download/verification promise. |
| `byte_length` | Nullable canonical decimal string, preserving values beyond floating-point integer precision. No final hosting quota is implied. |
| `sha256` | Nullable lowercase 64-digit digest of the exact bytes, not decoded pixels. |
| `source_format` | Optional original format token; preserve unsupported native formats opaquely. |
| `derived_from_asset_id` | Optional original asset reference for previews/derivatives; dependency cycles are invalid. |
| `source_created_at_utc` | Nullable historical creation time; never substitute upload time. |
| `attribution` | Optional provider/source ID, creator text/link and source link; no provider credential field. |

`unavailable` must not invent zero length or an empty-file hash. `described` does not imply the bytes are cached, uploaded, authorized for another account, or actually verified. Local cache state belongs to each device; server verification and resumable upload state follow [Assets](Assets.md), separately from declared metadata.

The combined graph checks workspace/account consistency and original/derivative references. Asset targets outside the bundle need explicit evidence. The metadata can preserve opaque drawing originals on Windows even if only a preview is rendered; preview availability does not authorize deleting or replacing the original.

The synthetic PNG and opaque original under `Contracts/1.0/Fixtures/AssetBytes/` exercise exact file length/hash checks. The opaque test bytes are **not a valid PencilKit drawing** and are not a native-format decoding test. These are fixtures, never real user attachments. No binary upload or file synchronization has been implemented.

## Verification and implementation

See [Conformance](Conformance.md) for current cross-language results. The full definition is final; native adapters, production upload routes and application synchronization remain implementation work. See [Integration plan](Integration-Plan.md).
