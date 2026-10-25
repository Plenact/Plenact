# Model 1.0 contract tooling

**Supported User Data Model versions:** 1.0 final specification.
**Status:** Schema/semantic validator, publication gate and standalone Swift/C#/JavaScript probes. No native app migration or sync integration.

The suite checks 48 schemas, 167 fixture expectations and two synthetic asset files. Swift, C# and JavaScript each preserve 67 valid examples; Python independently revalidates their outputs. See [conformance evidence](../../Doc/User-Data-Model/Conformance.md) for boundaries.

See [contract coverage](../../Doc/User-Data-Model/Contracts/1.0/README.md) and [verification boundaries](../../Doc/User-Data-Model/Content-Contracts.md). Run the Python fixture validator first; the probes only consume inputs marked valid and do not replace schema or authorization checks.

## Python validation

```sh
python3 -m venv /tmp/plenact-contract-checks
/tmp/plenact-contract-checks/bin/python -m pip install -r Tools/UserDataModel/requirements.txt
/tmp/plenact-contract-checks/bin/python Tools/UserDataModel/validate_contract.py
/tmp/plenact-contract-checks/bin/python -m unittest discover -s Tools/UserDataModel -p 'test_*.py'
```

## Swift codec probe

From the repository root with Swift/Foundation installed:

```sh
swiftc Tools/UserDataModel/Swift/ContractCodecProbe.swift -o /tmp/plenact-swift-contract-probe
/tmp/plenact-swift-contract-probe Doc/User-Data-Model/Contracts/1.0/Fixtures /tmp/plenact-swift-contract-results
/tmp/plenact-contract-checks/bin/python Tools/UserDataModel/validate_contract.py --compare-roundtrips /tmp/plenact-swift-contract-results
```

## C# codec probe

Use a .NET SDK supporting net8.0. This is a console probe, not WinUI or the Windows application repository. Build artifacts stay outside source:

```sh
dotnet build Tools/UserDataModel/DotNet/ContractCodecProbe.csproj -p:BaseIntermediateOutputPath=/tmp/plenact-contract-dotnet-obj/ -p:OutputPath=/tmp/plenact-contract-dotnet-bin/
dotnet /tmp/plenact-contract-dotnet-bin/ContractCodecProbe.dll Doc/User-Data-Model/Contracts/1.0/Fixtures /tmp/plenact-csharp-contract-results
/tmp/plenact-contract-checks/bin/python Tools/UserDataModel/validate_contract.py --compare-roundtrips /tmp/plenact-csharp-contract-results
```

These shell paths target macOS/Linux; on Windows choose equivalent temporary paths and run the same project, fixture folder and validator. A Python environment with requirements installed is required for independent verification.

The probes explicitly map content-envelope wire names and retain payloads as complete JSON, preserving nested/inactive fields. The Python comparison revalidates outputs, distinguishes Boolean from numeric values, retains array order, and checks the complete fixture set. Neither probe claims legacy field conversion, schema validation inside that language, account authorization or application synchronization.

Before each run use an empty temporary output directory, or one created by the same current fixture set; stale extra JSON files are rejected. All fixture files are synthetic. Do not point the probes at personal data or output into the fixture directory.

## Read-only frozen-backup capture

The [export milestone guide](../../Doc/User-Data-Model/Read-Only-Export.md) defines input layout, preserved values/files, classifications, issue codes and limitations. Use an explicit frozen backup; this tool does not find or stop the app for you.

```sh
python Tools/UserDataModel/capture_export.py --snapshot /path/to/frozen-backup --output /path/to/new-private-capture
python Tools/UserDataModel/capture_export.py --verify /path/to/new-private-capture
```

These commands retain legacy bytes and always declare portable conversion incomplete. They do not run Swift decoders, create examples, upload data, restore backups or edit the source. Inputs/outputs cannot overlap; existing output directories are rejected. Review status exits 2 with a report; fatal errors exit 1 without a successful artifact. All integration tests use synthetic temporary data.

## Web structural/codec probe

Install the pinned dependencies with pnpm in `Tools/UserDataModel/Web` (the lockfile is included), then return to the repository root:

```sh
node Tools/UserDataModel/Web/probe.cjs Doc/User-Data-Model/Contracts/1.0 /tmp/plenact-web-contract-results
python Tools/UserDataModel/validate_contract.py --compare-roundtrips /tmp/plenact-web-contract-results
```

AJV validates structural expectations; independent Python validation supplies the shared semantic checks. This is not browser persistence or live authorization testing.

## Frozen publication gate

```sh
python Tools/UserDataModel/publication_gate.py --check-source
python Tools/UserDataModel/publication_gate.py --package /tmp/plenact-user-data-model-1.0.zip
python Tools/UserDataModel/publication_gate.py --verify-package /tmp/plenact-user-data-model-1.0.zip
```

Use a new output archive path. Only reviewed definition/tool/fixture files are included; dependency/build caches and private capture outputs are excluded. The source-baseline check applies to the original release checkout. The ZIP manifest verifies internal integrity; compare the archive with the release's separately downloaded checksum too.

## Documentation follow-up checks

The regression suite now checks every local Markdown link under `Doc`, the versioned JSON examples and exact SQL-embedded record/frame values. These are synthetic SQL representations validated against the final JSON/semantic contract, not database execution tests. The source audit remains frozen to the original release: routine mapping tests check target consistency; explicit `--check-source` verifies hashes only when run from that release checkout.

## Native partial-converter verification

`validate_native_preview.py` checks an actual Swift-generated array of label/category/shared-display documents against the final schemas and slice relationships. The native migration tests retain that JSON as an XCTest attachment. This is independent verification of the first three converted types, not full workspace conversion or cloud authorization. Capture format 1 now refuses newer native migration evidence rather than silently dropping it; preserve the original native backup folder.

## Expanded content and pinned-rule verification

The native preview checker now accepts Collection/List/Card/unavailable-reference records in addition to the metadata slice and validates complete membership/archives/links from actual record evidence. Pinned timezone generation/checks live in `build_migration_time_zones.py`; supported local migration contexts remain Central/UTC, not the entire IANA database. See [content adapter limits](../../Doc/User-Data-Model/iOS-Content-Migration.md).


The native preview checker also exposes `validate_selection_preview(preview, records)` for the local, account-unbound selection artifact (Model 1.0 target, local format 1). It verifies the explicit pending-binding envelope, target existence, unique source owner/Card pairs, strict Boolean/integer values and bounded importance. This does not validate authenticated ownership or turn a draft into a canonical selection. The model/tooling suite now contains 71 tests.


The native preview checker now also accepts `calendar_week`, `calendar_index`, `planning_template` and `template_library`, validates each schema and checks planning relationships against the actual content slice. It additionally requires that the selected current Week exist. The internal relationship-only context has no authenticated account and is not emitted as a canonical planning graph. The model/tooling suite now contains 74 checks.


`validate_asset_preview(preview, records, original_files)` checks the local account-unbound Asset artifact against exact original-byte inputs. It requires complete inventory, strict source-relative paths and byte/hash agreement, and checks content field pointers plus drawing dependency membership/acyclicity. It does not establish account ownership or decoder/playback validity. Model/tooling coverage now contains 77 checks.


The native checker now accepts canonical `today_shortcuts` with exact parent membership and no duplicate owner/List pairs. `validate_settings_preview(preview, records)` validates explicitly account-unbound profile/preference drafts against local payload constraints, effective-source evidence and existing List/Asset targets; it does not establish account ownership. Avatar field links can be supplied to `validate_asset_preview` as additional records built from an already-validated profile draft. Current model/tooling coverage contains 80 checks.


The native checker accepts canonical `studio_artwork` payloads and verifies their declared Asset targets. `validate_studio_preview(preview, records)` checks local account-unbound Studio settings and global-Week evidence, exact artwork membership and visible global/order mapping gaps; it returns the local draft records used for independent Asset-pointer verification. It does not add a global-theme field to Model 1.0 or establish account ownership. Current coverage contains 83 model/tooling checks.


Native validation now accepts `daily_plan`, `weekly_review`, `periodic_review` and `review_rhythm` and checks their historical reference relationships in the planning slice, including unavailable original content. `validate_planning_preview(preview, records)` verifies local converted-store/version/count evidence and that migration neither executes review actions nor schedules notifications. Current coverage contains 86 checks.


`appearance_contract.py` checks the working Model 1.1 global appearance/ordered library definitions and complete composition over immutable Model 1.0. It requires explicit 1.1 capability and rejects metadata-losing downgrades. `validate_appearance_preview` checks the separate native appearance artifact; Studio local formats 1/2 remain distinguishable, and format 2 requires matching 1.1 evidence. These tools do not publish a release or deploy compatible protocol routes. Current model/tooling coverage contains 93 checks.


### Complete canonical record assembly

Supported User Data Model versions: 1.0 base, 1.1 working composition. `assemble_workspace.assemble(records, external_references, tombstones)` is a pure in-memory assembly function for already-canonical records. It validates the complete export and does not authenticate an account or convert native drafts. See [scope and remaining integration](../../Doc/User-Data-Model/Export-Assembly.md). Synthetic coverage is in `test_assemble_workspace.py`; no personal data or new command-line upload/import path is introduced.


### Synthetic native-draft binding

Supported User Data Model versions: 1.0 base and working 1.1 composition. `bind_synthetic_preview.bind_preview` is offline, in-memory test tooling with a fixed synthetic owner; it is not authentication or an application import API. It validates drafts and exact original bytes, retains mapping evidence and rejects unresolved selections/review issues. See [current scope](../../Doc/User-Data-Model/Export-Assembly.md).

To repeat acceptance checks against explicitly supplied synthetic XCTest attachments:

```sh
python Tools/UserDataModel/check_synthetic_assembly.py /absolute/path/to/synthetic-xcresult-attachments
```

The checker prints counts only and writes no files. Separate media, settings/profile and Studio cases are checked; it does not claim a combined complete personal backup or recoverability.


### Synthetic package creation and reopen

Supported User Data Model versions: 1.0 base, working 1.1 composition. `synthetic_export_package.package_bytes(binding, originals)` returns a verified reproducible archive. `read_package(data)` verifies and returns the exact synthetic assembly and original-byte dictionary without disk extraction. `write_package(destination, binding, originals)` atomically creates a new file and refuses overwrite. The explicitly synthetic wrapper is required; this is not a production import or authenticated export API. See [package boundaries and remaining integration](../../Doc/User-Data-Model/Export-Assembly.md). The native-evidence acceptance command above also checks package creation and reopening.


The combined native package can also be checked with `check_synthetic_assembly.py --native-package <synthetic-xcresult-attachments-directory>`. This validates actual Swift-emitted assembly/manifest bytes and original blobs, including cross-language UUIDv5 selection identities. See [the Simulator manual workflow](../../Doc/User-Data-Model/Export-Assembly.md).


### Imported native workspace backups

Supported User Data Model versions: 1.0 base and working 1.1. Native frozen-backup format 2 retains current editor stores and `PortableRuntime` canonical baseline/identity evidence. `capture_export.py` format-one capture refuses that evidence both at backup-root and application-support locations. Do not remove it to force capture. Fresh portable export after native editing requires the pending canonical reconciliation path; the original imported package is not an updated export.


Edited native export (supported versions: 1.0 base and working 1.1) can be checked from synthetic XCTest attachments with `check_synthetic_assembly.py ATTACHMENTS --edited-package`. This independently checks the complete edited package, manifest, original bytes, schemas, relationships and expected fixture changes. It never searches personal app containers. Current iOS edited export coverage and explicit limits are documented in `Doc/User-Data-Model/Editable-Import.md`.


Pending local deletion packages (working Model 1.1 overlay over unchanged 1.0 records) are independently checked with `check_synthetic_assembly.py ATTACHMENTS --deleted-package`. This checks retained canonical targets, pending intent, absence of fabricated server tombstones, full schema relationships, hashes and originals. Unknown/duplicate targets and downgrade loss are covered by `test_appearance_contract.py`.


Structural native test exports (1.0 records inside working 1.1) are checked with `check_synthetic_assembly.py ATTACHMENTS --structural-package`. This validates new List/Card records, ownership/order, full schemas and references, manifest integrity and originals from isolated XCTest evidence. It does not inspect personal app containers or publish definitions.


The structural artifact oracle now includes a rich newly created Card: photo, comment, four checklists/progress, completion and bookmark. `--structural-package` validates the complete canonical package and its newly added original as well as these fixture expectations. Supported models: immutable 1.0 base and working 1.1 composition; no account binding, publishing or upload is performed.


Existing imported-Card nested edits are independently checked with `check_synthetic_assembly.py ATTACHMENTS --existing-card-package`. The synthetic oracle verifies two comments, five checklists, two attachments, a member, reaction and cover, plus complete schema/reference/hash/original checks. Supported models remain 1.0 base and working 1.1; no publishing or account binding occurs.
