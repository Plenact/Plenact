"""Validate and package the immutable Plenact User Data Model 1.0 specification.

Supported User Data Model versions: 1.0. Documentation/schema publication only.
Never deploys API routes, reads live app data or uploads a user workspace.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

from openapi_spec_validator import validate as validate_openapi
from validate_contract import CONTRACTS, ROOT, ContractError, load_json, run_fixtures


TAG = "user-data-model-v1.0"
DOCUMENTS = ROOT / "Doc/User-Data-Model"
TOOLS = ROOT / "Tools/UserDataModel"
ALLOWED = {".md", ".json", ".py", ".swift", ".cs", ".csproj", ".cjs", ".yaml", ".txt", ".sql"}


def included_files():
    """Select specification/tool/fixture files while excluding caches, dependencies and private captures."""
    files = []
    for root in (DOCUMENTS, TOOLS):
        for path in sorted(root.rglob("*")):
            relative = path.relative_to(ROOT)
            if any(part in {"node_modules", "__pycache__", "bin", "obj", ".pnpm"} for part in relative.parts):
                continue
            if path.is_symlink():
                raise ContractError("publication_symlink")
            if path.is_file() and (path.suffix in ALLOWED or ("Fixtures/AssetBytes/" in path.as_posix() and path.suffix in {".png", ".bin"})):
                files.append(path)
    return files


def verify_source_snapshot(check_hashes=True):
    """Check the frozen source baseline before first publication, without reading stored user data."""
    audit = load_json(DOCUMENTS / "Source-Coverage.json")
    if check_hashes:
        for relative, expected in audit["source_files"].items():
            if hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() != expected:
                raise ContractError("source_snapshot_changed")
    allowed = {"synchronized", "device_local", "recovery_local", "legacy_storage_wrapper", "version_0_transport", "credentials_or_version_0_auth"}
    for model in audit["models"]:
        if model["scope"] not in allowed or not model["target"]:
            raise ContractError("unclassified_source_model")
        if len({f["source_field"] for f in model["fields"]}) != len(model["fields"]):
            raise ContractError("duplicate_source_field")
    for model in audit["models"]:
        target = model["target"]
        if model["scope"] != "synchronized" or "#" not in target or not model["fields"]:
            continue
        name, pointer = target.split("#", 1)
        path = CONTRACTS / (name + ".schema.json")
        if not path.exists():
            raise ContractError("unknown_source_target")
        node = load_json(path)
        for segment in pointer.strip("/").split("/"):
            node = node[segment.replace("~1", "/").replace("~0", "~")]
        def properties(value):
            found = set(value.get("properties", {}))
            for keyword in ("oneOf", "anyOf", "allOf"):
                for variant in value.get(keyword, []):
                    found |= properties(variant)
            return found
        fields = properties(node)
        for field in model["fields"]:
            wire = field["target"]
            if any(character in wire for character in ":#@. /"):
                continue
            if wire not in fields:
                raise ContractError("unknown_source_field_target")
    return len(audit["models"]), sum(len(m["fields"]) for m in audit["models"])


def validate_links():
    """Resolve local Markdown links in the repository before packaging them for publication."""
    for path in DOCUMENTS.rglob("*.md"):
        text = path.read_text()
        if "**Supported User Data Model versions:**" not in text:
            raise ContractError("missing_document_version")
        for target in re.findall(r"\]\(([^)]+)\)", text):
            if "://" in target or target.startswith("#"):
                continue
            filename = target.split("#")[0]
            if not (path.parent / filename).exists():
                raise AssertionError(f"Broken document link: {path.name}: {target}")


def check():
    """Validate all schemas, semantic examples, API structure and publication metadata."""
    schemas, fixtures = run_fixtures()
    registry = load_json(CONTRACTS / "registry.json")
    resources = {p.name.replace(".schema.json", ""): load_json(p)["$id"] for p in CONTRACTS.glob("*.schema.json")}
    if registry["resources"] != resources or registry["specification_status"] != "final":
        raise ContractError("invalid_frozen_registry")
    actual_types = {}
    for path in CONTRACTS.glob("*.schema.json"):
        schema = load_json(path)
        if "Final specification" not in schema["$comment"]:
            raise ContractError("draft_schema_in_release")
        kind = schema.get("properties", {}).get("record_type", {}).get("const")
        if kind:
            actual_types[kind] = path.name.replace(".schema.json", "")
    if registry["record_types"] != actual_types:
        raise ContractError("record_registry_mismatch")
    api = load_json(CONTRACTS / "openapi.json")
    validate_openapi(api)
    def bundled_schema(value):
        if isinstance(value, dict):
            result = {}
            for key, child in value.items():
                if key in {"$id", "$schema", "$comment"}:
                    continue
                if key == "$ref" and child.startswith("urn:plenact:user-data:1.0:"):
                    name, *fragment = child[len("urn:plenact:user-data:1.0:"):].split("#", 1)
                    result[key] = "#/components/schemas/" + name.replace("-", "_") + (fragment[0] if fragment else "")
                else:
                    result[key] = bundled_schema(child)
            return result
        if isinstance(value, list):
            return [bundled_schema(child) for child in value]
        return value
    for path in CONTRACTS.glob("*.schema.json"):
        key = path.name.replace(".schema.json", "").replace("-", "_")
        if api["components"]["schemas"].get(key) != bundled_schema(load_json(path)):
            raise ContractError("openapi_schema_drift")
    manifest = load_json(CONTRACTS / "Fixtures/manifest.json")
    for pair in manifest.get("transaction_pair_cases", []):
        raw = (CONTRACTS / "Fixtures" / pair["request"]).read_bytes()
        request = json.loads(raw)
        receipt = load_json(CONTRACTS / "Fixtures" / pair["receipt"])
        if hashlib.sha256(raw).hexdigest() != receipt["request_sha256"] or request["transaction_id"] != receipt["transaction_id"]:
            raise ContractError("receipt_request_mismatch")
    validate_links()
    return schemas, fixtures


def package(output):
    """Build a deterministic documentation/schema ZIP with exact hashes and source links pinned to its tag."""
    output = Path(output)
    if output.exists():
        raise ContractError("publication_output_exists")
    check()
    files = included_files()
    names = {p.relative_to(ROOT).as_posix() for p in files}
    entries = {}
    for path in files:
        name = path.relative_to(ROOT).as_posix()
        data = path.read_bytes()
        if path.suffix == ".md":
            text = data.decode()
            def rewrite(match):
                target = match.group(1)
                if "://" in target or target.startswith("#"):
                    return match.group(0)
                filename, *fragment = target.split("#", 1)
                resolved = (path.parent / filename).resolve()
                try:
                    relative = resolved.relative_to(ROOT).as_posix()
                except ValueError:
                    raise ContractError("publication_link_outside_repository")
                if relative in names:
                    return match.group(0)
                url = f"https://github.com/Plenact/Plenact/blob/{TAG}/{relative}"
                if fragment:
                    url += "#" + fragment[0]
                return "](" + url + ")"
            data = re.sub(r"\]\(([^)]+)\)", rewrite, text).encode()
        entries[name] = data
    manifest = {"user_data_model_version": "1.0", "protocol_version": "1.0", "status": "final_specification",
                "git_tag": TAG, "clients": ["ios", "web", "windows"],
                "implementation_status": "specification and conformance tools; applications/API not integrated",
                "sha256": {name: hashlib.sha256(data).hexdigest() for name, data in sorted(entries.items())}}
    entries["MODEL-MANIFEST.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    verify_package(output)
    return hashlib.sha256(output.read_bytes()).hexdigest()


def verify_package(path):
    """Verify every bundled byte against the manifest and reject unknown/path-traversing entries."""
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or any(n.startswith("/") or ".." in Path(n).parts for n in names):
            raise ContractError("invalid_package_paths")
        manifest = json.loads(archive.read("MODEL-MANIFEST.json"))
        if set(names) != set(manifest["sha256"]) | {"MODEL-MANIFEST.json"}:
            raise ContractError("package_manifest_mismatch")
        for name, expected in manifest["sha256"].items():
            if hashlib.sha256(archive.read(name)).hexdigest() != expected:
                raise ContractError("package_integrity_mismatch")
    return len(names)


def main():
    """Run publication checks, optional source audit, or produce a new immutable release package."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-source", action="store_true")
    parser.add_argument("--package", type=Path)
    parser.add_argument("--verify-package", type=Path)
    args = parser.parse_args()
    if args.verify_package:
        print(f"Verified {verify_package(args.verify_package)} packaged files.")
        return
    counts = check()
    if args.check_source:
        print("Source coverage:", verify_source_snapshot())
    print("Validated schemas/fixtures:", counts)
    if args.package:
        print("Package SHA-256:", package(args.package))


if __name__ == "__main__":
    main()
