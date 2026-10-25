# iOS Studio, saved artwork and global Week appearance preview

**Supported User Data Model versions:** 1.0 base and working 1.1 appearance records. Local Studio-preview formats 1/2; appearance-preview format 1; private identity journal formats 1/2/3.
**Status:** Working-branch conversion. Global Week defaults and artwork order now map to separate working Model 1.1 records. Studio account binding, publication and complete workspace import/export remain pending. See [current versioned definition and acceptance](Version-1.1.md).

## Converted and preserved values

| Source store | Output | Preservation boundary |
| --- | --- | --- |
| `Plenact.Studio.Settings.v1` | Account-unbound draft in `StudioPreview.json` | Explicit view destinations/surfaces, nullable Card/Note creation defaults, variation flags and authored palette including repeated colors. |
| `Plenact.Studio.Artwork.v1` | Canonical `studio_artwork` records plus local ordered `artwork_ids` | Stable source artwork UUID mapping, exact names, full surfaces, nullable header/text/title colors and explicit false/null italic flags. |
| `Plenact.WeekAppearance.v1` | Local `global_week_appearance` evidence | Complete BoardAppearance-shaped global theme, kept separate from individual Collection overrides. |

Absent stores remain absent; no starter looks, wallpaper defaults or random colors are generated. An explicitly empty artwork array remains a present empty store. Studio view dictionaries become deterministic destination-sorted arrays without changing their per-view semantics. Palette and artwork arrays retain authored sequence. False, null, zero strength/readability and framing values remain explicit.

All supported surface materials retain their source tokens: plain, color, gradient, paper, linen, dots, grid, canvas, photo and Unsplash. Color strings must already be canonical uppercase six-digit values; the adapter does not silently recase invalid source colors. Native typed decoding and explicit checks reject unknown fields/destinations, malformed colors/palettes, unsupported enums, invalid ranges, unsafe filenames and duplicate artwork UUIDs. A failed appearance slice reports `studio_blocker` and discards only that candidate slice and its identity allocations; valid content/settings and preserved originals remain available.

## Original files and online credit

Studio photo references use the existing owned-media path/digest namespace under `Library/Application Support/PlenactStudioArtwork`; Collection background photos use `Library/Application Support/PlenactCollectionBackgrounds`. Reusing the same file in a view, creation default and saved look reuses the same Asset target. Already-declared unavailable references are reused rather than duplicated. `AssetPreview.json` records pointers from canonical artwork and local Studio/Week drafts to verified originals. Missing referenced originals retain explicit unavailable evidence. Unreferenced originals remain preserved.

Online photo source IDs, image/profile/source URLs, photographer credit and explicit Unsplash provider metadata stay in the surface description. The converter performs no downloads or network requests, and does not invent local photo files from remote URLs. Existing personal profile, Card, List and Collection appearance conversions remain independent; no descendant appearance is flattened into its inherited defaults.

## Historical Model 1.0 gaps, now mapped by working Model 1.1

The original base model lacks these two representations. The working 1.1 definition now supplies their mappings; the earlier local-format-1 behavior is retained below as historical context:

1. **Global Week appearance.** Model 1.0 has per-Collection Board appearance, but no dedicated global Week-theme field. Assigning this theme to every currently retained Week would lose its global/future-Week meaning and could overwrite stored Collection overrides. The adapter therefore retains a separate local appearance-shaped draft and reports `global_week_appearance_canonical_mapping_pending`.
2. **Saved artwork ordering.** Canonical artwork records preserve each look, but do not independently represent the source library array's ordering. `StudioPreview.json.artwork_ids` retains the exact sequence. With multiple looks, `artwork_order_canonical_mapping_pending` makes this integration gap visible instead of claiming complete canonical coverage.

The immutable released Model 1.0 schemas/tag are unchanged. A separately reviewed, versioned representation is needed for these remaining global/order semantics; local evidence is not an undisclosed schema extension. A single saved artwork has no relative-order ambiguity. These pending mappings are not malformed-source errors and do not prevent valid artwork payload conversion or original-file verification.

Studio settings additionally require a verified `account_id`; the local Studio draft explicitly has `account_binding_pending: true` and no account identity. `canonical_mapping_complete` only describes the listed structural mapping issues, not authenticated ownership. These source stores remain in pending coverage until whole-workspace integration is accepted.

## Output and interface

The local artifact is `MigrationPreview/StudioPreview.json`, format `plenact.ios-studio-preview`, local format version 1, target Model 1.0. It contains nullable Studio/global-Week drafts, ordered artwork IDs, explicit artwork-store presence and review issues. Local global-theme identifiers remain evidence IDs; no unsupported record payload is inserted into canonical Records.

The UI shows **Studio and Week looks prepared**, **Saved artwork converted** and nonzero **Appearance review items**. `Report.json` exposes `studio_prepared_count`, `studio_artwork_count`, `appearance_review_item_count` and `studio_blocker`. A saved global theme or multiple saved looks can legitimately produce mapping-review notices even when all values and files are preserved correctly. Account-bound Studio settings and complete workspace import remain pending regardless of zero review items.

## Verification and manual test

The focused suite passes **60 native tests** and **83 model/tooling checks**. Four Studio cases cover all ten material families, all seven view destinations, exact local/online surface metadata, repeated palette colors, false/null styling, stable retries, shared originals, absent stores, invalid shapes/colors/framing/paths/destinations, duplicate artwork and explicit global/order gaps. The native fixture contains signature-probe image bytes, not decoder/rendering fixtures. No real owner backup is imported or restored by automated tests.

Actual emitted artwork, Studio/global drafts, source values, identities and original bytes are checked independently. Local Studio payload validation reuses the published field constraints while explicitly excluding the unbound account field; it does not claim a canonical authenticated Studio settings record. Global appearance validation uses the published Board appearance shape only as local evidence, not as an invented global record type. Source values, source array ordering and file pointers are compared separately.

Manual acceptance in **Plenact Import Test**:

1. Rebuild/run the app.
2. In Plenact Studio, save one background change or a reusable look so a saved Studio source is present. Existing looks may also be used; no global Week-theme change is required merely to test conversion.
3. Prepare a fresh local backup, confirm **Central — America/Chicago**, then prepare the migration preview.
4. Inspect Studio/Week preparation, artwork, appearance-review and verified-file counts.
5. Save under a new name for source-by-source ZIP verification, retaining earlier backups.

Remaining Step 1 work includes daily-plan/review adapters, the explicit global/order representation decisions, verified account/workspace binding, canonical account-bound drafts, complete portable export/import and whole-workspace recovery acceptance. Cloud synchronization remains off.


## Current 1.1 checkpoint

`workspace_appearance` retains the global theme and `artwork_library` retains exact artwork order. They are emitted separately in `AppearancePreview.json`, while Studio local format 2 declares the 1.1 mapping and no longer reports those resolved gaps. This has 68 native and 93 model/tooling checks, with source/order/file verification. Account binding, definition publication and full recovery remain pending; see [Model 1.1](Version-1.1.md).
