"""Validate the Model 1.0 foundation contracts and shared fixtures.

Supported User Data Model versions: 1.0, final specification.
Status: local tooling only; no production sync or authorization implementation.
Requires Python 3.9+ and the adjacent requirements.txt. Never contacts a server.
"""

import argparse
from datetime import date, datetime, timezone
import json
import math
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, reset_tzpath

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
import tzdata

from protocol_contract import PROTOCOL_SCHEMAS, validate_protocol, check_unicode

from workspace_contract import validate_workspace_record, validate_workspace_candidate

from planning_contract import (PLANNING_SCHEMAS, validate_asset_bytes,
                               validate_planning_document, validate_planning_graph)


ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "Doc/User-Data-Model/Contracts/1.0"
MAX_JSON_BYTES = 8_388_608  # Tooling input guard, not a final API payload limit.


class ContractError(ValueError):
    """Carry a stable fixture error code without logging private input values."""

    def __init__(self, code):
        """Initialize a validation failure using its portable error identifier."""
        super().__init__(code)
        self.code = code


def unique_object(pairs):
    """Reject duplicate JSON object keys so parsers cannot disagree silently."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise ContractError("duplicate_key")
        result[key] = value
    return result


def reject_constant(value):
    """Reject JavaScript-style NaN/Infinity, which are not portable JSON values."""
    raise ContractError("nonfinite_number")


def finite_float(value):
    """Reject numeric exponents that overflow to infinity during JSON decoding."""
    result = float(value)
    if not math.isfinite(result):
        raise ContractError("nonfinite_number")
    return result


def load_json(path):
    """Decode bounded UTF-8 JSON with unique keys and finite numeric values."""
    data = Path(path).read_bytes()
    if len(data) > MAX_JSON_BYTES:
        raise ContractError("input_too_large")
    return json.loads(data.decode("utf-8"), object_pairs_hook=unique_object,
                      parse_constant=reject_constant, parse_float=finite_float)


def validate_date(value):
    """Check Gregorian validity and zone/offset/instant agreement using pinned IANA rules.

    Unique local times require occurrence=unique; repeated times require first or
    second. Gaps are rejected instead of being silently shifted by a library.
    """
    kind = value["kind"]
    if kind == "date":
        try:
            date.fromisoformat(value["date"])
        except ValueError as error:
            raise ContractError("invalid_gregorian_date") from error
        return
    if kind == "time":
        return  # Fixed-width, range-checked time syntax is enforced by the schema.
    if value["tzdb_version"] != tzdata.IANA_VERSION:
        raise ContractError("unsupported_tzdb")
    # Ignore host timezone data: all fixture consumers use this exact tzdata release.
    reset_tzpath([])
    try:
        zone = ZoneInfo(value["time_zone"])
    except (ZoneInfoNotFoundError, ValueError) as error:
        raise ContractError("unknown_time_zone") from error
    try:
        local = datetime.fromisoformat(value["local_date_time"])
        supplied_instant = datetime.fromisoformat(value["utc_instant"].replace("Z", "+00:00"))
    except ValueError as error:
        raise ContractError("invalid_gregorian_date") from error
    candidates = {}
    for fold in (0, 1):
        zoned = local.replace(tzinfo=zone, fold=fold)
        instant = zoned.astimezone(timezone.utc)
        if instant.astimezone(zone).replace(tzinfo=None) == local:
            candidates[instant] = zoned
    ordered = sorted(candidates)
    if not ordered:
        raise ContractError("nonexistent_local_time")
    occurrence = value["occurrence"]
    if len(ordered) == 2:
        if occurrence not in ("first", "second"):
            raise ContractError("ambiguous_occurrence")
        expected = ordered[0 if occurrence == "first" else 1]
    else:
        if occurrence != "unique":
            raise ContractError("unexpected_occurrence")
        expected = ordered[0]
    offset = candidates[expected].utcoffset()
    seconds = int(offset.total_seconds())
    canonical_offset = ("+" if seconds >= 0 else "-") + f"{abs(seconds) // 3600:02d}:{abs(seconds) % 3600 // 60:02d}"
    if seconds % 60 or value["utc_offset"] != canonical_offset:
        raise ContractError("offset_mismatch")
    if supplied_instant != expected:
        raise ContractError("instant_mismatch")


def compatibility(offer):
    """Negotiate exact model support; application-version ordering grants no capability."""
    readable = "1.0" in offer["read_model_versions"]
    writable = readable and "1.0" in offer["write_model_versions"]
    return {"can_read": readable, "can_write": writable}


def record_capabilities(offer, record_type):
    """Intersect model and record-type capabilities for an individual operation."""
    model = compatibility(offer)
    readable = model["can_read"] and record_type in offer["read_record_types"]
    writable = model["can_write"] and readable and record_type in offer["write_record_types"]
    return {"can_read": readable, "can_write": writable}


def schema_registry():
    """Register repository schema resources locally; never retrieve remote references."""
    registry = Registry()
    for path in CONTRACTS.glob("*.schema.json"):
        schema = load_json(path)
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    return registry


def walk_objects(value):
    """Yield nested objects without decoding opaque history bytes as live records."""
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_objects(child)


def identity_objects(value):
    """Traverse owned identities once when active detail also has an identical retained mirror."""
    if isinstance(value, dict):
        yield value
        active = value.get("content")
        mirror = None
        if isinstance(active, dict) and active.get("kind") == "action_detail":
            mirror = value.get("retained_detail")
            if mirror is not None and mirror != active["detail"]:
                raise ContractError("retained_detail_mismatch")
        if isinstance(active, dict) and active.get("kind") == "linked_card":
            retained = value.get("retained_card_id")
            if retained is not None and retained != active["card_id"]:
                raise ContractError("retained_card_mismatch")
        if isinstance(active, dict) and active.get("kind") == "web_link":
            retained = value.get("retained_url")
            if retained is not None and retained != active["url"]:
                raise ContractError("retained_url_mismatch")
        for key, child in value.items():
            if key == "retained_detail" and mirror is not None:
                continue
            yield from identity_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from identity_objects(child)


def validate_nested_content(payload):
    """Check dates, timestamps, nested identities, and canonical retained history bytes."""
    import base64
    seen = set()
    for node in identity_objects(payload):
        if "id" in node and isinstance(node["id"], str) and len(node["id"]) == 36 and node.get("provider") != "unsplash":
            if node["id"] in seen:
                raise ContractError("duplicate_nested_identity")
            seen.add(node["id"])
        if node.get("kind") in ("date", "time", "date_and_time"):
            validate_date(node)
        for key, value in node.items():
            if key.endswith("_utc") and value is not None:
                try:
                    datetime.fromisoformat(value.replace("Z", "+00:00"))
                except ValueError as error:
                    raise ContractError("invalid_gregorian_date") from error
        if node.get("encoding") == "base64":
            try:
                raw = base64.b64decode(node["data"], validate=True)
                if base64.b64encode(raw).decode("ascii") != node["data"]:
                    raise ValueError("noncanonical base64")
            except ValueError as error:
                raise ContractError("invalid_history_bytes") from error


def validate_card(document):
    """Validate complete Card content without rewriting inherited or retained values."""
    payload = document["payload"]
    validate_nested_content(payload)
    for node in walk_objects(payload):
        for field in ("description_override", "description", "body"):
            text = node.get(field)
            if isinstance(text, str) and text.startswith("plenact-rich-v1:"):
                import base64
                try:
                    data = base64.b64decode(text[len("plenact-rich-v1:"):], validate=True)
                    runs = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object, parse_float=finite_float, parse_constant=reject_constant)
                except (ValueError, UnicodeError):
                    continue  # The existing app treats an invalid prefix payload as literal text.
                try:
                    validate_instance(runs, load_json(CONTRACTS / "rich-text-runs.schema.json"), "rich-text-runs.schema.json")
                except ContractError as error:
                    raise ContractError("unsupported_rich_text") from error
    for field in ("start", "due"):
        if payload[field] is not None and payload[field]["kind"] != payload[field + "_kind"]:
            raise ContractError("date_kind_mismatch")
    attachments = payload["attachments"] or []
    cover = payload["cover_attachment_id"]
    if cover is not None:
        matches = [a for a in attachments if a["id"] == cover]
        if not matches or matches[0]["kind"] != "photo":
            raise ContractError("missing_cover_attachment")
    for attachment in attachments:
        if attachment["kind"] == "link" and (attachment["url"] is None or attachment["asset_id"] is not None
                                                 or attachment["drawing_asset_id"] is not None):
            raise ContractError("invalid_link_attachment")


def validate_list(document):
    """Reject a Card placed in both active and archived membership arrays."""
    payload = document["payload"]
    if set(payload["card_ids"]) & set(payload["archived_card_ids"]):
        raise ContractError("duplicate_card_membership")


def validate_collection(document):
    """Keep the preferred List reference inside its owning Collection."""
    payload = document["payload"]
    preferred = payload["preferred_focused_list_id"]
    if preferred is not None and preferred not in payload["list_ids"]:
        raise ContractError("focused_list_not_member")


def validate_graph(graph):
    """Check ownership/membership and explicit external reference evidence for a graph."""
    collections = graph["collections"]
    lists = graph["lists"]
    cards = graph["cards"]
    documents = collections + lists + cards
    ids = [d["id"] for d in documents]
    if len(set(ids)) != len(ids):
        raise ContractError("duplicate_record_identity")
    if any(d["workspace_id"] != graph["workspace_id"] for d in documents):
        raise ContractError("workspace_mismatch")
    for document in collections:
        validate_collection(document)
    for document in lists:
        validate_list(document)
    for document in cards:
        validate_card(document)
    collection_map = {d["id"]: d for d in collections}
    list_map = {d["id"]: d for d in lists}
    card_map = {d["id"]: d for d in cards}
    listed_lists = []
    for collection in collections:
        for list_id in collection["payload"]["list_ids"]:
            listed_lists.append(list_id)
            if list_id not in list_map or list_map[list_id]["payload"]["collection_id"] != collection["id"]:
                raise ContractError("list_membership_mismatch")
    if len(set(listed_lists)) != len(listed_lists) or set(listed_lists) != set(list_map):
        raise ContractError("list_membership_mismatch")
    listed_cards = []
    for document in lists:
        for key, archived in (("card_ids", False), ("archived_card_ids", True)):
            for card_id in document["payload"][key]:
                listed_cards.append(card_id)
                if card_id not in card_map or card_map[card_id]["payload"]["list_id"] != document["id"]:
                    raise ContractError("card_membership_mismatch")
                if card_map[card_id]["payload"]["archived"] != archived:
                    raise ContractError("archive_membership_mismatch")
    if len(set(listed_cards)) != len(listed_cards) or set(listed_cards) != set(card_map):
        raise ContractError("card_membership_mismatch")
    external = [(r["record_type"], r["id"]) for r in graph["external_references"]]
    if len(set(external)) != len(external):
        raise ContractError("duplicate_external_reference")
    known = {"card": set(card_map), "collection": set(collection_map), "label": set(), "asset": set(), "list": set(list_map), "label_category": set()}
    if any(record_id in known[kind] for kind, record_id in external):
        raise ContractError("external_reference_is_local")
    for kind, record_id in external:
        known[kind].add(record_id)
    for document in documents:
        for node in walk_objects(document["payload"]):
            for key, value in node.items():
                if value is None:
                    continue
                if key in ("card_id", "retained_card_id") and value not in known["card"]:
                    raise ContractError("unresolved_card_reference")
                if key == "linked_collection_id" and value not in known["collection"]:
                    raise ContractError("unresolved_collection_reference")
                if key in ("asset_id", "drawing_asset_id", "photo_asset_id") and value not in known["asset"]:
                    raise ContractError("unresolved_asset_reference")
                if key == "label_ids" and not set(value).issubset(known["label"]):
                    raise ContractError("unresolved_label_reference")


def validate_instance(value, schema, schema_name):
    """Apply a standards validator followed by the slice's explicit semantic rules."""
    check_unicode(value, ContractError)
    checker = FormatChecker()
    if list(Draft202012Validator(schema, registry=schema_registry(), format_checker=checker).iter_errors(value)):
        raise ContractError("schema_error")
    if schema_name in PROTOCOL_SCHEMAS:
        registry = load_json(CONTRACTS / "registry.json")["record_types"]
        def document_check(document):
            name = registry[document["record_type"]] + ".schema.json"
            validate_instance(document, load_json(CONTRACTS / name), name)
        validate_protocol(value, schema_name, ContractError, document_check)
    elif schema_name == "date-value.schema.json":
        validate_date(value)
    elif schema_name == "workspace-export.schema.json":
        for tombstone in value["tombstones"]:
            validate_instance(tombstone, load_json(CONTRACTS / "server-record.schema.json"), "server-record.schema.json")
        validate_workspace_candidate(value, ContractError,
            lambda graph: validate_planning_graph(graph, ContractError, validate_graph), validate_nested_content)
    elif schema_name in {"account.schema.json", "user-profile.schema.json", "label-category.schema.json",
                         "label.schema.json", "studio-settings.schema.json", "studio-artwork.schema.json",
                         "today-shortcuts.schema.json", "workspace-display-preferences.schema.json", "workspace.schema.json", "user-preferences.schema.json", "content-selection.schema.json", "unavailable-reference.schema.json"}:
        validate_workspace_record(value, ContractError, validate_nested_content)
    elif schema_name in PLANNING_SCHEMAS:
        validate_planning_document(value, ContractError)
    elif schema_name == "planning-graph.schema.json":
        validate_planning_graph(value, ContractError, validate_graph)
    elif schema_name == "card.schema.json":
        validate_card(value)
    elif schema_name == "list.schema.json":
        validate_list(value)
    elif schema_name == "collection.schema.json":
        validate_collection(value)
    elif schema_name == "content-graph.schema.json":
        validate_graph(value)
    elif schema_name == "client-capabilities.schema.json":
        if not set(value["write_model_versions"]).issubset(value["read_model_versions"]):
            raise ContractError("write_without_read")
        if not set(value["write_record_types"]).issubset(value["read_record_types"]):
            raise ContractError("write_type_without_read")


def run_fixtures():
    """Validate schemas and every manifest expectation; fail on unlisted fixture files."""
    manifest = load_json(CONTRACTS / "Fixtures/manifest.json")
    if manifest["tzdb_version"] != tzdata.IANA_VERSION:
        raise ContractError("fixture_tzdb_mismatch")
    schemas = {}
    for path in CONTRACTS.glob("*.schema.json"):
        schema = load_json(path)
        Draft202012Validator.check_schema(schema)
        schemas[path.name] = schema
    names = set()
    files = set()
    for case in manifest["cases"]:
        if case["name"] in names or case["file"] in files:
            raise ContractError("duplicate_fixture")
        names.add(case["name"])
        files.add(case["file"])
        if Path(case["file"]).name != case["file"]:
            raise ContractError("invalid_fixture_path")
        value = load_json(CONTRACTS / "Fixtures" / case["file"])
        actual_error = None
        try:
            validate_instance(value, schemas[case["schema"]], case["schema"])
        except ContractError as error:
            actual_error = error.code
        expected_error = case.get("expected_error")
        if (actual_error is None) != case["valid"] or actual_error != expected_error:
            raise AssertionError(f"{case['name']}: expected {expected_error}, received {actual_error}")
        if "compatibility" in case and compatibility(value) != case["compatibility"]:
            raise AssertionError(f"{case['name']}: compatibility mismatch")
        # Shared consumers compare JSON values, not formatting or object-key order.
        if json.loads(json.dumps(value, allow_nan=False)) != value:
            raise AssertionError(f"{case['name']}: round trip changed content")
    actual_files = {p.name for p in (CONTRACTS / "Fixtures").glob("*.json") if p.name != "manifest.json"}
    if files != actual_files:
        raise ContractError("unlisted_or_missing_fixture")
    validate_asset_bytes(CONTRACTS / "Fixtures", manifest, load_json, ContractError)
    return len(schemas), len(names)


def compare_roundtrips(directory):
    """Revalidate codec outputs and compare exact JSON values for all valid fixtures."""
    directory = Path(directory)
    manifest = load_json(CONTRACTS / "Fixtures/manifest.json")
    expected = {c["file"] for c in manifest["cases"] if c["valid"]}
    if {p.name for p in directory.glob("*.json")} != expected:
        raise ContractError("codec_fixture_set_mismatch")
    for case in manifest["cases"]:
        if not case["valid"]:
            continue
        original = load_json(CONTRACTS / "Fixtures" / case["file"])
        actual = load_json(directory / case["file"])
        schema = load_json(CONTRACTS / case["schema"])
        validate_instance(actual, schema, case["schema"])
        # bool and integer are distinct JSON types despite Python equality semantics.
        canonical_original = json.dumps(original, sort_keys=True, ensure_ascii=False, allow_nan=False)
        canonical_actual = json.dumps(actual, sort_keys=True, ensure_ascii=False, allow_nan=False)
        if canonical_original != canonical_actual:
            # JSON treats 1 and 1.0 as the same number; compare normalized numeric values
            # while still distinguishing booleans from numeric values recursively.
            if not equivalent_json(original, actual):
                raise AssertionError(f"{case['name']}: codec changed JSON content")
    return len(expected)


def equivalent_json(left, right):
    """Compare JSON semantic values, preserving Boolean/null and authored array ordering."""
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(equivalent_json(v, right[k]) for k, v in left.items())
    if isinstance(left, list):
        return len(left) == len(right) and all(equivalent_json(a, b) for a, b in zip(left, right))
    return left == right


def main():
    """Run repository fixtures and print counts without exposing fixture payloads."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compare-roundtrips", type=Path, help="Check a codec output folder")
    args = parser.parse_args()
    schemas, fixtures = run_fixtures()
    print(f"Validated {schemas} schemas and {fixtures} shared fixture expectations.")
    if args.compare_roundtrips is not None:
        count = compare_roundtrips(args.compare_roundtrips)
        print(f"Revalidated and compared {count} codec round trips.")


if __name__ == "__main__":
    main()
