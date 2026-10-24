"""Calendar, planning/review and asset semantic checks for Model 1.0.

Supported User Data Model versions: 1.0, final specification.
Status: local contract tooling; not app migration, authentication or sync integration.
"""

from datetime import date, datetime
from pathlib import PurePosixPath
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, reset_tzpath


PLANNING_SCHEMAS = {
    "calendar-week.schema.json", "calendar-index.schema.json", "daily-plan.schema.json",
    "weekly-review.schema.json", "periodic-review.schema.json", "planning-template.schema.json",
    "template-library.schema.json", "review-rhythm.schema.json", "asset.schema.json"
}


def unique(values, code, fail):
    """Require unique logical identities even when duplicate objects have different text."""
    if len(values) != len(set(values)):
        raise fail(code)


def walk(value):
    """Yield nested objects while preserving snapshots as independent values."""
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def validate_zone(value, fail):
    """Resolve the source IANA zone using the pinned fixture timezone package."""
    reset_tzpath([])
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError) as error:
        raise fail("unknown_time_zone") from error


def validate_planning_document(document, fail):
    """Apply model invariants without conflating historical and current snapshots."""
    kind = document["record_type"]
    payload = document["payload"]
    if "time_zone" in payload:
        validate_zone(payload["time_zone"], fail)
    for node in walk(payload):
        for key, value in node.items():
            if key.endswith("_utc") and value is not None:
                try:
                    datetime.fromisoformat(value.replace("Z", "+00:00"))
                except ValueError as error:
                    raise fail("invalid_gregorian_date") from error
        for key in ("priorities", "achievements"):
            if key in node:
                unique([(p["source_collection_id"], p["card_id"]) for p in node[key]], "duplicate_priority", fail)
        if "decisions" in node:
            unique([d["id"] for d in node["decisions"]], "duplicate_review_decision", fail)
        if node.get("check_ins") is not None:
            unique([c["id"] for c in node["check_ins"]], "duplicate_check_in", fail)
        for key in ("starting_objectives", "objectives"):
            if key in node:
                # A starting objective and its current snapshot deliberately share an ID.
                unique([o["id"] for o in node[key]], "duplicate_objective", fail)
        if "completed_tasks" in node and node["completed_tasks"] is not None and node["total_tasks"] is not None:
            if node["completed_tasks"] > node["total_tasks"]:
                raise fail("invalid_progress_counts")
    if kind in ("calendar_week", "weekly_review"):
        start = date.fromisoformat(payload["start_date"])
        if start.isoweekday() % 7 + 1 != payload["first_weekday"]:
            raise fail("week_start_mismatch")
    if kind == "calendar_week":
        mappings = payload["day_lists"]
        unique([m["date"] for m in mappings], "duplicate_day_mapping", fail)
        unique([m["list_id"] for m in mappings], "duplicate_day_list", fail)
        if any(not 0 <= (date.fromisoformat(m["date"]) - start).days < 7 for m in mappings):
            raise fail("week_day_outside_range")
    elif kind == "calendar_index":
        unique([m["checklist_item_id"] for m in payload["checklist_link_weeks"]], "duplicate_checklist_week_link", fail)
    elif kind == "periodic_review":
        if payload["start_date"] > payload["end_date"]:
            raise fail("invalid_review_range")
    elif kind == "planning_template":
        unique([m["weekday"] for m in payload["weekdays"]], "duplicate_template_weekday", fail)
        unique([m["list_id"] for m in payload["weekdays"]], "duplicate_template_list", fail)
        if not payload["weekdays"] or (payload["kind"] == "day" and len(payload["weekdays"]) != 1):
            raise fail("invalid_day_template")
    elif kind == "template_library":
        if payload["default_week_id"] is not None and payload["default_week_id"] not in payload["template_ids"]:
            raise fail("invalid_default_template")
    elif kind == "asset":
        described = payload["content_state"] == "described"
        if described != (payload["byte_length"] is not None and payload["sha256"] is not None):
            raise fail("invalid_asset_metadata")
        if not described and (payload["byte_length"] is not None or payload["sha256"] is not None):
            raise fail("invalid_asset_metadata")
        if payload["derived_from_asset_id"] == document["id"]:
            raise fail("asset_derivation_cycle")
        name = payload["original_name"]
        if name is not None and ("/" in name or "\\" in name or name in (".", "..")):
            raise fail("invalid_asset_name")


def validate_planning_graph(graph, fail, validate_content_graph):
    """Verify dated/template ownership, historical references and asset dependency links."""
    content = graph["content"]
    if content["workspace_id"] != graph["workspace_id"]:
        raise fail("workspace_mismatch")
    validate_content_graph(content)
    groups = ("calendar_indexes", "weeks", "daily_plans", "weekly_reviews", "periodic_reviews",
              "templates", "template_libraries", "review_rhythms", "assets")
    documents = [d for group in groups for d in graph[group]]
    content_documents = content["collections"] + content["lists"] + content["cards"]
    unique([d["id"] for d in documents + content_documents], "duplicate_record_identity", fail)
    if any(d["workspace_id"] != graph["workspace_id"] for d in documents):
        raise fail("workspace_mismatch")
    for document in documents:
        validate_planning_document(document, fail)
    collections = {d["id"]: d for d in content["collections"]}
    lists = {d["id"]: d for d in content["lists"]}
    cards = {d["id"]: d for d in content["cards"]}
    weeks = {d["id"]: d for d in graph["weeks"]}
    templates = {d["id"]: d for d in graph["templates"]}
    assets = {d["id"]: d for d in graph["assets"]}
    unique([d["payload"]["collection_id"] for d in weeks.values()], "duplicate_week_owner", fail)
    unique([(d["payload"]["start_date"], d["payload"]["time_zone"]) for d in weeks.values()], "duplicate_week", fail)
    unique([(d["payload"]["date"], d["payload"]["time_zone"]) for d in graph["daily_plans"]], "duplicate_daily_plan", fail)
    unique([(d["payload"]["start_date"], d["payload"]["time_zone"], d["payload"]["first_weekday"]) for d in graph["weekly_reviews"]], "duplicate_weekly_review", fail)
    for week in weeks.values():
        payload = week["payload"]
        owner = collections.get(payload["collection_id"])
        if owner is None:
            raise fail("unresolved_week_collection")
        for mapping in payload["day_lists"]:
            if mapping["list_id"] not in owner["payload"]["list_ids"] or lists[mapping["list_id"]]["payload"]["archived"]:
                raise fail("week_list_membership_mismatch")
    indexed = []
    checklist_owners = {}
    for document in cards.values():
        item_ids = {node["id"] for node in walk(document["payload"])
                    if "id" in node and "retained_detail" in node and "content" in node}
        for item_id in item_ids:
            checklist_owners.setdefault(item_id, set()).add(document["id"])
    checklist_items = set(checklist_owners)
    for index in graph["calendar_indexes"]:
        indexed.extend(index["payload"]["week_ids"])
        for mapping in index["payload"]["checklist_link_weeks"]:
            if mapping["week_id"] not in weeks:
                raise fail("unresolved_week_reference")
            if mapping["checklist_item_id"] not in checklist_items:
                raise fail("unresolved_checklist_reference")
            if len(checklist_owners[mapping["checklist_item_id"]]) != 1:
                raise fail("ambiguous_checklist_reference")
    if len(set(indexed)) != len(indexed) or set(indexed) != set(weeks):
        raise fail("calendar_index_membership_mismatch")
    week_owners = {d["payload"]["collection_id"] for d in weeks.values()}
    unique([d["payload"]["collection_id"] for d in templates.values()], "duplicate_template_owner", fail)
    for template in templates.values():
        payload = template["payload"]
        if payload["collection_id"] in week_owners:
            raise fail("template_live_owner_overlap")
        owner = collections.get(payload["collection_id"])
        if owner is None:
            raise fail("unresolved_template_collection")
        if any(m["list_id"] not in owner["payload"]["list_ids"] for m in payload["weekdays"]):
            raise fail("template_list_membership_mismatch")
        member_cards = {card_id for list_id in owner["payload"]["list_ids"]
                        for key in ("card_ids", "archived_card_ids") for card_id in lists[list_id]["payload"][key]}
        if payload["example_focus"] is not None:
            if any(not set(values).issubset(member_cards) for values in payload["example_focus"].values()):
                raise fail("template_focus_not_member")
    for library in graph["template_libraries"]:
        payload = library["payload"]
        if not set(payload["template_ids"]).issubset(templates):
            raise fail("unresolved_template_reference")
        default = payload["default_week_id"]
        if default is not None and templates[default]["payload"]["kind"] != "week":
            raise fail("invalid_default_template")
    indexed_templates = [template_id for library in graph["template_libraries"]
                         for template_id in library["payload"]["template_ids"]]
    if len(set(indexed_templates)) != len(indexed_templates) or set(indexed_templates) != set(templates):
        raise fail("template_library_membership_mismatch")
    known_cards = set(cards) | {r["id"] for r in content["external_references"] if r["record_type"] == "card"}
    known_collections = set(collections) | {r["id"] for r in content["external_references"] if r["record_type"] == "collection"}
    for document in documents:
        for node in walk(document["payload"]):
            if "source_collection_id" in node and "card_id" in node:
                if node["card_id"] not in known_cards or node["source_collection_id"] not in known_collections:
                    raise fail("unresolved_priority_reference")
    known_assets = set(assets) | {r["id"] for r in content["external_references"] if r["record_type"] == "asset"}
    for asset in assets.values():
        payload = asset["payload"]
        if payload["account_id"] != graph["account_id"]:
            raise fail("asset_account_mismatch")
        parent = payload["derived_from_asset_id"]
        if parent is not None and parent not in known_assets:
            raise fail("unresolved_asset_reference")
        path = set()
        current = asset["id"]
        while current in assets:
            if current in path:
                raise fail("asset_derivation_cycle")
            path.add(current)
            current = assets[current]["payload"]["derived_from_asset_id"]


def validate_asset_bytes(root, manifest, load_json, fail):
    """Compare synthetic fixture files to declared byte lengths and SHA-256 digests."""
    import hashlib
    for case in manifest.get("asset_byte_cases", []):
        relative = PurePosixPath(case["file"])
        if relative.is_absolute() or ".." in relative.parts:
            raise fail("invalid_asset_fixture_path")
        if PurePosixPath(case["asset_fixture"]).name != case["asset_fixture"]:
            raise fail("invalid_asset_fixture_path")
        document = load_json(root / case["asset_fixture"])
        if document["record_type"] != "asset":
            raise fail("invalid_asset_fixture_type")
        data = (root / str(relative)).read_bytes()
        payload = document["payload"]
        if str(len(data)) != payload["byte_length"] or hashlib.sha256(data).hexdigest() != payload["sha256"]:
            raise fail("asset_integrity_mismatch")
