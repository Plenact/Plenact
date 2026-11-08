# iOS calendar and template metadata preview

**Supported User Data Model versions:** 1.0. Native backup/preview format 1; private identity journal formats 1/2/3.
**Status:** Working-branch implementation with synthetic native and independent contract verification. Complete workspace export/import, verified account binding and synchronization remain pending.

## Converted metadata

The content converter now emits four additional canonical record types alongside the existing Collection/List/Card records:

| Source | Canonical target | Preserved relationships |
| --- | --- | --- |
| Each retained calendar Week | `calendar_week` | Original start key, actual Collection, first weekday, confirmed original timezone, explicit day-to-List mapping and explicitly-saved flag. |
| Calendar document | `calendar_index` | Store version, first weekday, current Week start, authored Week ordering and saved cross-Week checklist-item ownership. |
| Each saved routine | `planning_template` | Exact name, Day/Week kind, anchor date, source timezone, first weekday, independent template-owned Collection, explicit weekday/List mapping and nullable example Focus markers. |
| Routine library | `template_library` | Store version, authored template ordering, nullable selected default Week and separate nullable bundled-routine revision. |

Week metadata uses the caller-confirmed live-calendar timezone even after converting template snapshots with their own zones. No timezone is inferred from the device or from the last converted template. Template timezone support remains the same bounded Chicago/UTC projection (including recognized GMT aliases) as the content converter. Civil source day keys are validated exactly as Gregorian dates during 1900–2100; normalized dates such as February 30 are rejected. Week starts must match the saved first weekday, mapped days must lie within that Week, and live day mappings must reference distinct, existing, active Lists. No missing day mapping is invented from a List title or position.

Template mappings must have distinct valid weekdays and List targets; a Day template must have one mapping. Example important/bookmarked/all-day markers map only to Cards within that template's original owner scope. These example markers remain template metadata, separate from a user's personal selection drafts. The selected default must exist and be a Week template; absent defaults stay null. Invalid revisions, ambiguous identities, missing targets and unsupported dates/zones block this atomic content/metadata slice. Original source bytes remain in the backup and the report exposes the blocker.

## Stable identity and cross-Week links

Existing Collection/List/Card mappings remain unchanged. Calendar Week IDs use original Collection UUID provenance in a separate `calendar_week` namespace; template metadata IDs use original Template UUIDs. The index and library use stable source-store identities. Independent template snapshots remain qualified by Template UUID even when they retain the same legacy Collection UUID. Repeated preparation reuses the private journal's identities.

A saved calendar `checklistLinkWeeks` override takes precedence over a checklist item's implicit/local owner while converting a live Week's linked Card and retained Card references. The override is also converted into the canonical calendar index. It is not applied to personal collections or template copies. A source checklist UUID must resolve to exactly one currently converted live-Week checklist item; stale journal entries, template copies and unrelated personal copies cannot satisfy it. An absent target Week, ambiguous item or duplicate saved mapping requires review. Missing/pending references elsewhere continue to use the content converter's explicit unavailable-reference mechanism.

## Output and coverage

The UI and `Report.json` now show `calendar_template_record_count` / **Calendar and template records** separately. These records contribute to the total converted-preview count; the existing content count continues to count the content slice rather than the new metadata. A snapshot containing one Week and six templates normally adds nine records: one Week, one index, six templates and one library.

Calendar, personal-collection and template stores remain classified as partial while canonical personal selections or other workspace integration is pending. Preparing metadata does not imply that bookmarks have acquired authenticated ownership. `SelectionPreview.json` remains a separate account-unbound review artifact. No account, full planning graph or complete workspace export is manufactured to satisfy a schema.

Independent checking validates each metadata record against the immutable Model 1.0 schemas, then checks relationships against the exact emitted content using the published planning semantics. Its internal relationship-check context has no bound account and emits no planning-graph artifact. Checks include Week/index membership, current Week existence, template ownership/defaults, example Focus membership and checklist/Week targets. The released schemas and tag are unchanged.

## Verification and manual acceptance

The focused native run passes 47 tests: 17 content/calendar/template/selection tests, 15 metadata/identity tests, seven source-backup tests, six restore tests and two dataset-recovery regressions. New cases cover nine metadata records, preserved Central-time context despite GMT templates, retry identity, invalid civil/day/weekday/default/focus/revision values, and a two-Week checklist override with a matching numeric Card in the local Week. Independent validation accepts the actual 181-record full synthetic fixture, 188-record default-catalog fixture and 192-record cross-Week fixture. The model/tooling suite passes 74 checks. These fixtures are synthetic; no personal backup is restored or converted by automated tests.

In **Plenact Import Test**:

1. Rebuild/run the current source.
2. Open Today → Settings → Your data → Local backup.
3. Prepare a fresh local backup and choose **Central — America/Chicago**.
4. Prepare the migration preview and inspect **Calendar and template records**, personal-selection counts and any review guidance.
5. Save/export under a new name, keeping earlier backups, for source-by-source ZIP verification.

Remaining Step 1 work includes the other planning/review stores, preferences/profile/shortcuts, owned Assets, verified account/workspace binding, complete portable export/import and full migration/recovery acceptance. Cloud staging, synchronization and other clients remain separate later steps.


### Additive appearance representation update

The global Week/theme and artwork-order gaps described at earlier checkpoints now have working Model 1.1 records, emitted separately from base records. See [versioned representation and compatibility](Version-1.1.md). Publication, ownership binding and complete workspace recovery remain pending.
