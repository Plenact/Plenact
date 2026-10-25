"""Independently validate canonical records emitted by the native migration-preview tests.

Supported User Data Model versions: 1.0. Partial label/display slice only.
Reads synthetic exported JSON, never a live application container or remote account.
"""

import argparse
from pathlib import Path
from validate_contract import CONTRACTS, ContractError, load_json, validate_instance


SUPPORTED = {"label_category", "label", "workspace_display_preferences"}


def validate_records(records):
    """Revalidate each exact document and its slice-level identity/category relationships."""
    if not isinstance(records, list):
        raise ContractError("invalid_native_preview")
    registry = load_json(CONTRACTS / "registry.json")["record_types"]
    seen = set()
    workspaces = set()
    categories = set()
    for record in records:
        if not isinstance(record, dict) or record.get("record_type") not in SUPPORTED:
            raise ContractError("unsupported_native_preview_record")
        schema_name = registry[record["record_type"]] + ".schema.json"
        validate_instance(record, load_json(CONTRACTS / schema_name), schema_name)
        if record["id"] in seen:
            raise ContractError("duplicate_native_preview_id")
        seen.add(record["id"])
        workspaces.add(record["workspace_id"])
        if record["record_type"] == "label_category":
            categories.add(record["id"])
    if len(workspaces) > 1:
        raise ContractError("native_preview_workspace_mismatch")
    for record in records:
        if record["record_type"] == "label" and record["payload"]["category_id"] not in categories:
            raise ContractError("native_preview_missing_category")
    return len(records)


def main():
    """Validate the native XCTest attachment and print only its record count."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("records", type=Path)
    args = parser.parse_args()
    print(f"Independently validated {validate_records(load_json(args.records))} native migration records.")


if __name__ == "__main__":
    main()
