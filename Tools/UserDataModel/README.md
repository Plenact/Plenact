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
