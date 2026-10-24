"""Remaining workspace record checks for Model 1.0 final specification.

Supported User Data Model versions: 1.0. Local contract definitions only; no authentication.
"""


def validate_workspace_record(value, fail, validate_nested):
    """Check source timestamps and unique view/pin identities without inventing defaults."""
    payload = value["payload"]
    validate_nested(payload)
    if value["record_type"] == "studio_settings":
        keys = [v["destination"] for v in payload["views"]]
        if len(set(keys)) != len(keys):
            raise fail("duplicate_studio_destination")
    if value["record_type"] == "today_shortcuts":
        keys = [(v["collection_id"], v["list_id"]) for v in payload["items"]]
        if len(set(keys)) != len(keys):
            raise fail("duplicate_shortcut")


def validate_workspace_candidate(value, fail, validate_planning, validate_nested):
    """Require ownership and label/asset/shortcut references across the whole proposed bundle."""
    planning = value["planning"]
    validate_planning(planning)
    account = value["account"]
    workspace_record = value["workspace"]
    account_id = account["id"]
    workspace = planning["workspace_id"]
    if workspace_record["id"] != planning["workspace_id"] or workspace_record["payload"]["owner_account_id"] != account_id:
        raise fail("account_mismatch")
    if planning["account_id"] != account_id:
        raise fail("account_mismatch")
    records = [account, workspace_record] + value["unavailable_references"] + value["content_selections"] + value["profiles"] + value["label_categories"] + value["labels"] + value["artwork"]
    records += [value[k] for k in ("studio_settings", "today_shortcuts", "display_preferences", "user_preferences") if value[k] is not None]
    if any(r["workspace_id"] != workspace for r in records):
        raise fail("workspace_mismatch")
    ids = [r["id"] for r in records] + [r["record_id"] for r in value["tombstones"]]
    content = planning["content"]
    ids += [r["id"] for key in ("collections", "lists", "cards") for r in content[key]]
    ids += [r["id"] for key in ("calendar_indexes", "weeks", "daily_plans", "weekly_reviews", "periodic_reviews", "templates", "template_libraries", "review_rhythms", "assets") for r in planning[key]]
    if len(set(ids)) != len(ids):
        raise fail("duplicate_record_identity")
    for record in records:
        validate_workspace_record(record, fail, validate_nested)
        if "account_id" in record["payload"] and record["payload"]["account_id"] != account_id:
            raise fail("account_mismatch")
    unavailable = {(r["payload"]["target_type"], r["payload"]["target_id"]) for r in value["unavailable_references"]}
    deleted = set()
    for tombstone in value["tombstones"]:
        if not tombstone["deleted"] or tombstone["document"] is not None or tombstone["workspace_id"] != workspace:
            raise fail("invalid_export_tombstone")
        deleted.add((tombstone["record_type"], tombstone["record_id"]))
    categories = {r["id"] for r in value["label_categories"]} | {i for kind, i in unavailable | deleted if kind == "label_category"}
    labels = {r["id"] for r in value["labels"]} | {i for kind, i in unavailable | deleted if kind == "label"}
    if any(r["payload"]["category_id"] not in categories for r in value["labels"]):
        raise fail("unresolved_label_category")
    if any(not set(r["payload"]["label_ids"]).issubset(labels) for r in content["cards"]):
        raise fail("unresolved_label_reference")
    collections = {r["id"]: r for r in content["collections"]}
    lists = {r["id"]: r for r in content["lists"]}
    cards = {r["id"] for r in content["cards"]} | {i for kind, i in unavailable | deleted if kind == "card"}
    assets = {r["id"] for r in planning["assets"]} | {i for kind, i in unavailable | deleted if kind == "asset"}
    selections = []
    for selection in value["content_selections"]:
        if selection["payload"]["account_id"] != account_id:
            raise fail("account_mismatch")
        if selection["workspace_id"] != workspace:
            raise fail("workspace_mismatch")
        if selection["payload"]["card_id"] not in cards:
            raise fail("unresolved_selection_reference")
        selections.append(selection["payload"]["card_id"])
    if len(set(selections)) != len(selections):
        raise fail("duplicate_content_selection")
    preferences = value["user_preferences"]
    if preferences is not None:
        target = preferences["payload"]["preferences"]["default_list_id"]
        if target is not None and target not in lists and ("list", target) not in unavailable | deleted:
            raise fail("unresolved_default_list")
    shortcuts = value["today_shortcuts"]
    if shortcuts is not None:
        for item in shortcuts["payload"]["items"]:
            if item["collection_id"] not in collections or item["list_id"] not in collections[item["collection_id"]]["payload"]["list_ids"]:
                raise fail("unresolved_shortcut_reference")
    actual = {("card", r["id"]) for r in content["cards"]} | {("collection", r["id"]) for r in content["collections"]} | {("list", r["id"]) for r in content["lists"]} | {("asset", r["id"]) for r in planning["assets"]} | {("label", r["id"]) for r in value["labels"]} | {("label_category", r["id"]) for r in value["label_categories"]}
    if unavailable & actual or unavailable & deleted:
        raise fail("redundant_unavailable_reference")
    for entry in content["external_references"]:
        target = (entry["record_type"], entry["id"])
        if target not in actual | unavailable | deleted:
            raise fail("unproven_external_reference")
    from planning_contract import walk
    for record in records + content["cards"]:
        for node in walk(record["payload"]):
            if node.get("author_account_id") is not None and node["author_account_id"] != account_id:
                raise fail("account_mismatch")
            if node.get("identity_scope") == "owner_account" and node["user_id"] != account_id:
                raise fail("account_mismatch")
            for key, reference in node.items():
                if key in ("avatar_asset_id", "photo_asset_id") and reference is not None and reference not in assets:
                    raise fail("unresolved_asset_reference")
