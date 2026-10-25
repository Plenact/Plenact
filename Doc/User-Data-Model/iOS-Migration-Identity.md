# Native migration identities and partial canonical preview

**Supported User Data Model versions:** 1.0. Local journal and preview format: 1.
**Status:** Working-branch implementation after the immutable Model 1.0 definition release; not a new server record or synchronization protocol.

## Durable identity

`MigrationIdentityJournal` retains a source-installation UUID, a **local preview** workspace UUID and entries mapping `(recordType, original owner namespace, legacyID, optional creation discriminator)` to portable UUIDs. Same-key retries reuse identity; different owners/types/source creations stay distinct. Titles, current List positions, email and display names are not identity keys. Neither installation nor preview UUID establishes authenticated ownership.

Original source ownership must remain stable through moves. Future content adapters must retain original provenance or explicit relocation evidence; passing a different current owner to the resolver is not a safe cross-owner move algorithm. No Card/List adapter or relocation alias ledger is claimed by this slice.

The journal is private device migration state at `Library/Application Support/PlenactMigration/source-identities-v1.json`. It is not a synchronized preference or credential. Writes compare exact expected bytes on the main actor and use atomic protected replacement. Validate supported versions/fields, bounded file size, UUID shape, unique sources/targets and immutable namespace/mappings before use. This is an app-local single-writer boundary, not a distributed lock or encrypted signed ledger. Corrupt or unknown journals remain intact for review.

Successful preview preparation persists mappings before returning output; canceling Files export retains those mappings for stable retries. A failed field conversion does not create/rewrite the journal. Native source backups now retain/hash existing journal bytes independently of whether they decode. Preview preparation checks any retained journal against the current namespace and mappings; it never restores or replaces device identity merely by opening a backup. A separate Simulator-only source recovery path now exists; production import/restore and verified account binding remain separate work.

## Converted slice

| Source | Canonical target | Preservation / rejection |
| --- | --- | --- |
| `Plenact.LabelLibrary.v1` categories | `label_category` | Exact names/order; string IDs mapped by source/type. |
| Same library labels | `label` | Exact names/colors; mapped category reference; duplicate IDs and missing categories fail. |
| Six explicit display keys | `workspace_display_preferences` | Board presentation, cover/Activity/Library choices; missing fields become null, Boolean false remains false. |

A source-only frozen backup is read after its preference/media digests are verified. Pending daily-review recovery blocks conversion. Native label decoding is paired with explicit source-field checks, avoiding default/example loaders and unknown-field loss. The converter uses complete canonical envelopes, lowercase UUIDs and explicit payload fields; it does not attach server revisions or claim a verified account.

## Export layout

```text
Plenact Backup/
├── Preferences.plist
├── NativePreflight.json
├── Documents/…                         Preserved original media
├── Library/Application Support/…       Preserved original media
├── Migration/IdentityJournal.json      Existing journal, when captured
└── MigrationPreview/
    ├── Records/…json                   Converted canonical metadata documents
    ├── Report.json                     Partial coverage, remaining work and local identity scope
    └── IdentityJournal.json            Latest durable mapping evidence
```

The preview is **not** a `workspace-export` document. Account/workspace records, content, calendar/planning/reviews, profile/preferences, selections, assets, complete semantic validation and production restore remain work. Device/recovery stores remain preserved evidence rather than future synchronization commands. Do not upload preview records as a verified private workspace.

The Python offline capture format 1 cannot represent the new migration evidence; its tool now rejects folders containing it before creating output. Keep the original native folder. A future capture-format revision must explicitly preserve/validate that evidence instead of silently omitting it.

## Validation and acceptance

Twenty-two focused iOS tests pass (seven source-backup plus fifteen identity/conversion tests). The native test attaches actual converted JSON; validate that array independently with:

```sh
python Tools/UserDataModel/validate_native_preview.py /path/to/native-migration-records.json
```

The Python suite has 67 regression tests including the independent preview checker and legacy-capture evidence guard. The original contract remains 48 schemas / 167 fixture expectations. No released tag or schema was changed.

Hands-on acceptance: prepare source backup, prepare preview, inspect/save the combined folder, cancel/retry saving, reopen the screen and repeat preparation with stable IDs. Also check missing/corrupt labels, large data, Files providers, background imports and device locking. Simulator unit tests do not prove these system UI/provider interactions. See [migration/export milestone](iOS-Migration-Export.md) and [next implementation plan](Integration-Plan.md).
