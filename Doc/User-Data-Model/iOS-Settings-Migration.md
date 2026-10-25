# iOS profile, preferences and Today shortcut preparation

**Supported User Data Model versions:** 1.0. Local settings-preview format 1; source/preview format 1; private identity journal formats 1/2/3.
**Status:** Working-branch implementation with synthetic native and independent validation. Today shortcuts can be canonical records; personal profile/preferences remain account-unbound drafts. Complete workspace export/import and synchronization remain pending.

## What this slice converts

| Source | Output | Boundary |
| --- | --- | --- |
| `Plenact.TodayListShortcuts.v1` | Canonical `today_shortcuts` record | Exact order and owner-qualified Collection/List membership; explicitly saved empty lists remain empty. |
| `Plenact.LocalProfile.v1` | Local profile draft in `SettingsPreview.json` | Source profile UUID, creation time, exact name/email/context, avatar colors/icon and original avatar-file reference. No profile is invented when absent. |
| `Plenact.PlanPreferences.v1` or embedded profile preferences | Local preferences draft | All 19 Model 1.0 preference fields, with explicit effective-source/default provenance and pending account binding. |

This does not yet convert Studio settings/artwork metadata, Week appearance overrides, daily plans or review stores. Original files from owned media areas remain preserved and prepared by the preceding Asset adapter. Other personal preference/appearance domains stay in the remaining-source inventory until their adapters and complete-workspace integration are accepted.

## Preferences and precedence

The native app resolves valid standalone planning preferences before embedded profile preferences, then current application defaults. This adapter preserves that precedence without using live preference loaders or saving fallback values into the source. It records `preferences_origin` as `saved_planning_preferences`, `saved_profile_preferences` or `application_defaults`. A separate UI **Settings source** label shows the same distinction in plain language.

Missing or null compatible fields receive the native decoder's current defaults, listed explicitly in `defaulted_preference_fields`. These are current-build compatibility/default snapshots, not proof of historically saved values. A present malformed store blocks this settings slice rather than falling back over corrupt user data. Unknown source keys, wrong types, unsupported enums and out-of-range Focus row counts require review. Explicit false, zero, empty text and null retain their distinct meanings. No row count is silently clamped or reset to four.

`profile_preferences_shadowed` records that a present standalone store wins over the profile's embedded settings. The complete original source remains in `Preferences.plist`, including the shadowed values. Profile and preference payloads remain separate, as required by Model 1.0. `todayFocusOrder: dayList` maps explicitly to `day_list`; other wire fields use reviewed mappings, not inferred name conversion.

The numeric default Today List is resolved only under the saved current calendar Week's Collection. A matching numeric ID under another owner cannot satisfy it. If that context or target is missing, the local draft retains `unresolved_default_list_id` and an explicit review issue. Its target field is not treated as a successfully migrated unset choice: `ready_for_binding` is false until that source ambiguity is resolved. `ready_for_binding` describes source review only, not authenticated ownership.

## Local profile and avatar preservation

The source local profile UUID remains `source_profile_id`; it is never promoted to an authenticated account ID. Name, email and context are preserved exactly, without trimming, case changes or identity inference. Legacy avatar palette tokens retain explicit RGB values and legacy provenance. Missing older icon/foreground fields use native compatibility defaults listed in `defaulted_profile_fields`; invalid raw colors are rejected before normalization. Profile creation timestamps use canonical millisecond UTC formatting with finer source precision retained in the local `source_precision` evidence.

A saved avatar filename resolves through the existing `Documents/ProfileAvatars` path/digest identity namespace. Its pending Asset target is explicit in the canonical unavailable-reference evidence; `AssetPreview.json` links it to the actual profile draft through a `profile_avatar` field reference. The draft ID is a future canonical profile identity, not an account. Missing avatar files remain reviewable unavailable evidence. No new avatar file is synthesized and no remote image is downloaded.

## Shortcut conversion and failure behavior

The shortcut adapter reads raw saved references directly rather than calling the normalizing UI loader. More than six entries, duplicate owner/List pairs, unsupported fields, invalid storage or unresolved membership require review. It preserves source order and never deduplicates, truncates or seeds starter shortcuts during migration. A source shortcut store is marked converted only after its canonical record is emitted, including an explicitly empty record when the saved selection is empty. An absent store remains absent.

Settings preparation uses a candidate identity journal. On a malformed profile/preference/shortcut source, the settings slice and its identity allocations are discarded; previously valid content/calendar conversion remains available. `settings_blocker` and a visible review count explain that settings are pending. Originals remain preserved. An unresolved default List is instead retained as a reviewable draft with its exact numeric evidence and binding readiness disabled.

## Output and account boundary

`SettingsPreview.json` has format `plenact.ios-settings-preview`, format version 1, Model 1.0 target and `account_binding_pending: true`. Its `profile` is nullable, `preferences` contains the effective complete preference payload, and both draft wrappers retain stable destination IDs. Account-required canonical `user_profile` / `user_preferences` records are not emitted until verified ownership exists. No released schema is changed.

The UI/report separate settings/profile preparation from canonical shortcut conversion:

- **Settings source** identifies saved planning settings, saved profile settings, application defaults or required review.
- **Settings and profile prepared** counts one preferences draft plus a profile draft only when present.
- **Today shortcuts converted** counts source shortcut items, not extra canonical documents.
- **Settings review items** appears for source blockers or unresolved defaults.

`Report.json` adds `settings_profile_prepared_count`, `shortcut_item_count`, `settings_review_item_count`, `settings_blocker` and `settings_account_binding_pending`. Saved profile and preference stores remain in pending coverage until canonical ownership conversion is accepted. Asset verification and personal-selection preparation retain their existing separate counts.

## Verification and owner acceptance

The focused native suite passes **56 tests**, adding five settings cases to the previous 51. The model/tooling suite passes **80 checks**. Tests cover standalone/profile/default precedence, exact writing and false/zero values, legacy missing/null fields, current-Week default ownership, two different owners sharing numeric List ID 1, shortcut order, stable retries, avatar file linkage, unresolved defaults, malformed fields/ranges/colors/paths and duplicate/broken pins. Synthetic emitted settings, canonical records, source values and avatar original bytes are independently checked. No personal backup is imported or restored during automated testing.

Independent local-draft validation reuses the published profile/preference payload field constraints while explicitly excluding the as-yet-unbound account field. It does not claim these drafts pass a canonical account-owned record schema. Canonical shortcuts validate against the unchanged released schema and actual converted List/Collection membership. Avatar verification accepts the already-validated profile draft as additional local linkage evidence alongside canonical content records.

Manual check in **Plenact Import Test**:

1. Rebuild/run the current source.
2. Optionally change and save one planning preference so saved-value preservation is visible. A local profile need not be created merely for this test.
3. Prepare a fresh local backup, choose **Central — America/Chicago**, and prepare the migration preview.
4. Inspect the Settings source, settings/profile count, shortcut count and any review messages.
5. Save/export under a new name for source-by-source ZIP comparison, retaining previous backups.

Remaining Step 1 work includes Studio/other appearance and planning/review adapters, verified account/workspace binding, canonical personal selections/Assets/profile/preferences, complete portable export/import and whole-workspace recovery acceptance. This preview does not enable cloud synchronization.


### Additive appearance representation update

The global Week/theme and artwork-order gaps described at earlier checkpoints now have working Model 1.1 records, emitted separately from base records. See [versioned representation and compatibility](Version-1.1.md). Publication, ownership binding and complete workspace recovery remain pending.
