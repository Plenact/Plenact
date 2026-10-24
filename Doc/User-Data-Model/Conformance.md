# Model 1.0 conformance evidence

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

The release gate validates **48 JSON Schemas**, **24 canonical persistent record types** and **167 synthetic fixture expectations**, including **67 valid examples**. Invalid cases are deliberately retained as rejection tests. All release examples and asset bytes are synthetic.

| Check | Evidence and boundary |
| --- | --- |
| Python reference validator | Draft 2020-12 with format assertions plus dates, ownership/reference graph, rich text, protocol semantics, exact asset bytes and capability checks. |
| Regression suite | 58 passing tests: read-only capture, semantic rejection, conflicts, idempotency, atomicity, deletion, upload integrity and deterministic publication packaging. Run the command below for the exact current test count. |
| JavaScript / Node | AJV 2020 structural expectations for all 167 cases, strict JSON guards and JSON round trips for all 67 valid cases. Semantic validation of emitted files is performed independently by Python. |
| Swift / Foundation | Typed canonical envelope plus retained JSON payloads; all 67 valid examples round-trip and are independently revalidated/value-compared. |
| C# / System.Text.Json | The same 67 valid examples round-trip, independently revalidated/value-compared. Console probe built for net8.0; not the Windows UI application. |
| OpenAPI | OpenAPI 3.1.1 validates, and embedded schema components must match the standalone schemas exactly. |
| Source audit | SwiftSyntax inventory: 96 Codable declarations, 379 stored fields and 41 literal key/prefix segments; frozen source hashes and lifecycle mappings. |
| Release artifact | Deterministic ZIP, pinned source links, per-file SHA-256 manifest and separately published archive checksum. |

Reference verification used Python 3.9, Apple Swift 6.4, .NET SDK 8.0.426 and Node 24.22.1. Tool dependencies are pinned. The timezone examples use tzdata 2025.2 / IANA 2025b. Runtime clients must negotiate accepted timezone releases rather than hard-code this fixture release forever.

## Reproduce

Use the [tool instructions](../../Tools/UserDataModel/README.md) to install dependencies and run all three probes. From the repository root:

```sh
python Tools/UserDataModel/validate_contract.py
python -m unittest discover -s Tools/UserDataModel -p 'test_*.py'
python Tools/UserDataModel/publication_gate.py --check-source
python Tools/UserDataModel/publication_gate.py --package /tmp/plenact-user-data-model-1.0.zip
python Tools/UserDataModel/publication_gate.py --verify-package /tmp/plenact-user-data-model-1.0.zip
```

`--check-source` compares the original frozen source baseline and is intended for the initial release checkout; later app source changes need not match that historical baseline. The package verifier checks consistency against a local manifest, not a cryptographic publisher signature. Verify the archive against the separately retrieved release checksum as well.

## Practical limits

Passing these tests establishes specification/example consistency and portable JSON preservation. It does **not** establish native legacy conversion, live service authentication/authorization, PHP database transactions, browser storage durability, native UI behavior, account provisioning, server backup recovery or end-to-end cross-device convergence. The protocol examples are in-memory demonstrations, not a production API. The source inventory records syntax and reviewed mappings, not a proof that a migration adapter exists.

Each application/API implementation must pass the same fixtures, semantic invariants and [runtime acceptance scenarios](Integration-Plan.md), including adversarial owner isolation and crash/retry behavior, before claiming Model 1.0 integration.
