"""Independently validate canonical records emitted by the native migration-preview tests.

Supported User Data Model versions: 1.0. Content and metadata slice only; not a complete workspace.
Reads synthetic exported JSON, never a live application container or remote account.
"""

import argparse
from pathlib import Path
from validate_contract import CONTRACTS, ContractError, load_json, validate_instance


SUPPORTED = {"label_category", "label", "workspace_display_preferences", "collection", "list", "card", "unavailable_reference", "calendar_week", "calendar_index", "planning_template", "template_library", "today_shortcuts", "studio_artwork", "daily_plan", "weekly_review", "periodic_review", "review_rhythm"}


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
    unavailable = {}
    for record in records:
        if record["record_type"] == "unavailable_reference":
            target = record["payload"]["target_id"]
            if target in seen or target in unavailable:
                raise ContractError("invalid_native_unavailable_reference")
            unavailable[target] = record["payload"]["target_type"]
    for record in records:
        if record["record_type"] == "label" and record["payload"]["category_id"] not in categories:
            raise ContractError("native_preview_missing_category")
    def artwork_targets(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key == 'photo_asset_id' and child is not None:
                    yield child
                yield from artwork_targets(child)
        elif isinstance(value, list):
            for child in value:
                yield from artwork_targets(child)
    for record in records:
        if record['record_type'] == 'studio_artwork':
            for target in artwork_targets(record['payload']):
                if unavailable.get(target) != 'asset':
                    raise ContractError('native_artwork_asset_unresolved')
    shortcuts = [r for r in records if r['record_type'] == 'today_shortcuts']
    if len(shortcuts) > 1:
        raise ContractError('duplicate_native_shortcut_document')
    for record in shortcuts:
        pairs = [(item['collection_id'], item['list_id']) for item in record['payload']['items']]
        if len(pairs) != len(set(pairs)):
            raise ContractError('duplicate_native_shortcut')
        for collection, target in pairs:
            if not any(r['record_type'] == 'list' and r['id'] == target and
                       r['payload']['collection_id'] == collection for r in records):
                raise ContractError('native_shortcut_membership_mismatch')
    content = [r for r in records if r["record_type"] in {"collection", "list", "card"}]
    metadata = [r for r in records if r["record_type"] in {
        "calendar_week", "calendar_index", "planning_template", "template_library",
        "daily_plan", "weekly_review", "periodic_review", "review_rhythm"}]
    if content or metadata:
        external = [{"record_type": r["record_type"], "id": r["id"], "status": "external"}
                    for r in records if r["record_type"] in {"label", "label_category"}]
        external += [{"record_type": kind, "id": target, "status": "unavailable"}
                     for target, kind in unavailable.items()]
        graph = {"user_data_model_version": "1.0", "payload_schema_version": 1,
                 "workspace_id": (content or metadata)[0]["workspace_id"], "external_references": external,
                 "collections": [r for r in content if r["record_type"] == "collection"],
                 "lists": [r for r in content if r["record_type"] == "list"],
                 "cards": [r for r in content if r["record_type"] == "card"]}
        name = "content-graph.schema.json"
        validate_instance(graph, load_json(CONTRACTS / name), name)
        if metadata:
            from planning_contract import validate_planning_graph
            # Relationship-only validation context; no planning graph or invented account is emitted.
            planning = {"workspace_id": (content or metadata)[0]["workspace_id"], "content": graph,
                        "account_id": None, "daily_plans": [], "weekly_reviews": [],
                        "periodic_reviews": [], "review_rhythms": [], "assets": []}
            for group, kind in (("weeks", "calendar_week"), ("calendar_indexes", "calendar_index"),
                                ("templates", "planning_template"), ("template_libraries", "template_library"),
                                ("daily_plans", "daily_plan"), ("weekly_reviews", "weekly_review"),
                                ("periodic_reviews", "periodic_review"), ("review_rhythms", "review_rhythm")):
                planning[group] = [r for r in metadata if r["record_type"] == kind]
            validate_planning_graph(planning, ContractError, lambda _: None)
            for index in planning["calendar_indexes"]:
                if not any(w["payload"]["start_date"] == index["payload"]["current_week_start_date"]
                           for w in planning["weeks"]):
                    raise ContractError("native_preview_current_week_missing")
    elif any(r["record_type"] in {"calendar_week", "calendar_index", "planning_template", "template_library"}
             for r in records):
        raise ContractError("native_preview_missing_content")
    return len(records)


def main():
    """Validate the native XCTest attachment and print only its record count."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("records", type=Path)
    args = parser.parse_args()
    print(f"Independently validated {validate_records(load_json(args.records))} native migration records.")


if __name__ == "__main__":
    main()


def validate_selection_preview(preview, records):
    """Verify local, account-unbound selection evidence without claiming canonical account ownership."""
    if (not isinstance(preview, dict) or set(preview) != {
            "format", "format_version", "target_user_data_model_version", "account_binding_pending", "entries", "issues"}
            or preview["format"] != "plenact.ios-selection-preview" or type(preview["format_version"]) is not int
            or preview["format_version"] != 1 or preview["target_user_data_model_version"] != "1.0"
            or preview["account_binding_pending"] is not True or not isinstance(preview["entries"], list)
            or not isinstance(preview["issues"], list)
            or any(not isinstance(i, str) or not i for i in preview["issues"])):
        raise ContractError("invalid_selection_preview")
    cards = {r["id"] for r in records if r["record_type"] == "card"}
    seen = set()
    for entry in preview["entries"]:
        if (not isinstance(entry, dict) or set(entry) != {"source_collection_id", "source_owner_scope", "source_card_id",
                "card_id", "bookmarked", "importance"} or not isinstance(entry["source_collection_id"], str)
                or type(entry["source_card_id"]) is not int
                or (entry["bookmarked"] is not None and type(entry["bookmarked"]) is not bool)
                or (entry["importance"] is not None and (type(entry["importance"]) is not int
                    or not 0 <= entry["importance"] <= 5))):
            raise ContractError("invalid_selection_entry")
        scope = entry["source_owner_scope"]
        if scope is not None and (not isinstance(scope, str) or not scope):
            raise ContractError("invalid_selection_owner")
        if entry["card_id"] is not None and (scope is None or entry["card_id"] not in cards):
            raise ContractError("invalid_selection_target")
        identity = (scope or entry["source_collection_id"], entry["source_card_id"])
        if identity in seen:
            raise ContractError("duplicate_selection_entry")
        seen.add(identity)
    return len(preview["entries"])


def validate_asset_preview(preview, records, original_files, additional_records=()):
    """Check local Asset evidence against exact original bytes and emitted content field pointers."""
    import hashlib
    import re
    import uuid
    roots = ('Documents/CardAttachments/', 'Documents/ProfileAvatars/',
             'Library/Application Support/PlenactStudioArtwork/',
             'Library/Application Support/PlenactCollectionBackgrounds/')
    expected_keys = {'format', 'format_version', 'target_user_data_model_version',
                     'account_binding_pending', 'entries', 'issues'}
    if (not isinstance(preview, dict) or set(preview) != expected_keys
            or preview['format'] != 'plenact.ios-asset-preview' or type(preview['format_version']) is not int
            or preview['format_version'] != 1 or preview['target_user_data_model_version'] != '1.0'
            or preview['account_binding_pending'] is not True or not isinstance(preview['entries'], list)
            or not isinstance(preview['issues'], list)
            or any(not isinstance(i, str) or not i for i in preview['issues'])):
        raise ContractError('invalid_asset_preview')
    entries = {}
    paths = set()
    described = set()
    references = set()
    for entry in preview['entries']:
        if not isinstance(entry, dict) or set(entry) != {
                'asset_id', 'source_path', 'kind', 'mime_type', 'original_name', 'content_state',
                'byte_length', 'sha256', 'source_format', 'derived_from_asset_id',
                'source_created_at_utc', 'attribution', 'type_evidence', 'references'}:
            raise ContractError('invalid_asset_entry')
        asset = entry['asset_id']
        try:
            if str(uuid.UUID(asset)) != asset:
                raise ValueError()
        except (ValueError, TypeError, AttributeError):
            raise ContractError('invalid_asset_identity')
        path = entry['source_path']
        if (not isinstance(path, str) or not path.startswith(roots) or '\\' in path
                or any(p in ('', '.', '..') for p in path.split('/'))
                or asset in entries or path in paths or entry['original_name'] != path.rsplit('/', 1)[-1]
                or entry['kind'] not in ('image', 'audio', 'video', 'drawing_original', 'binary')
                or not isinstance(entry['mime_type'], str)
                or not re.fullmatch(r'[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*', entry['mime_type'])
                or entry['type_evidence'] not in ('source_role', 'signature_hint', 'unknown')
                or entry['source_format'] not in (None, 'pencilkit')
                or entry['source_created_at_utc'] is not None or entry['attribution'] is not None
                or not isinstance(entry['references'], list)):
            raise ContractError('invalid_asset_metadata')
        entries[asset] = entry
        paths.add(path)
        if entry['content_state'] == 'described':
            data = original_files.get(path)
            if (not isinstance(data, bytes) or entry['byte_length'] != str(len(data))
                    or entry['sha256'] != hashlib.sha256(data).hexdigest()):
                raise ContractError('asset_original_integrity_mismatch')
            described.add(path)
        elif entry['content_state'] == 'unavailable':
            if (path in original_files or entry['byte_length'] is not None or entry['sha256'] is not None
                    or 'asset_original_unavailable:' + asset not in preview['issues']):
                raise ContractError('invalid_unavailable_asset')
        else:
            raise ContractError('invalid_asset_content_state')
        for reference in entry['references']:
            if not isinstance(reference, dict) or set(reference) != {'record_id', 'field_path', 'role'}:
                raise ContractError('invalid_asset_reference')
            if (not isinstance(reference['record_id'], str) or not isinstance(reference['field_path'], str)
                    or reference['role'] not in ('attachment_original', 'drawing_original', 'appearance_photo', 'profile_avatar')):
                raise ContractError('invalid_asset_reference')
            key = (asset, reference['record_id'], reference['field_path'], reference['role'])
            if key in references:
                raise ContractError('duplicate_asset_reference')
            references.add(key)
    if described != set(original_files):
        raise ContractError('asset_inventory_mismatch')
    actual = set()
    edges = set()

    def walk(value, record, path):
        if isinstance(value, dict):
            if isinstance(value.get('asset_id'), str) and isinstance(value.get('drawing_asset_id'), str):
                edges.add((value['asset_id'], value['drawing_asset_id']))
            for key, child in value.items():
                pointer = path + '/' + key
                if key in ('asset_id', 'drawing_asset_id', 'photo_asset_id', 'avatar_asset_id') and isinstance(child, str):
                    role = {'asset_id': 'attachment_original', 'drawing_asset_id': 'drawing_original',
                            'photo_asset_id': 'appearance_photo', 'avatar_asset_id': 'profile_avatar'}[key]
                    actual.add((child, record, pointer, role))
                walk(child, record, pointer)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, record, path + '/' + str(index))

    for record in list(records) + list(additional_records):
        if record['record_type'] != 'unavailable_reference':
            walk(record['payload'], record['id'], '/payload')
    if actual != references:
        raise ContractError('asset_reference_mismatch')
    for asset, entry in entries.items():
        parent = entry['derived_from_asset_id']
        if parent is not None and (parent not in entries or (asset, parent) not in edges):
            raise ContractError('invalid_asset_derivation')
    for asset in entries:
        seen = set()
        current = asset
        while current is not None:
            if current in seen:
                raise ContractError('asset_derivation_cycle')
            seen.add(current)
            current = entries[current]['derived_from_asset_id']
    return len(entries)


def validate_settings_preview(preview, records):
    """Check explicitly unbound settings payload constraints without assigning an account UUID."""
    import copy
    import uuid
    keys = {'format', 'format_version', 'target_user_data_model_version', 'account_binding_pending',
            'profile', 'preferences', 'preferences_origin', 'defaulted_preference_fields',
            'defaulted_profile_fields', 'profile_preferences_shadowed', 'unresolved_default_list_id',
            'source_precision', 'issues', 'ready_for_binding'}
    if (not isinstance(preview, dict) or set(preview) != keys
            or preview['format'] != 'plenact.ios-settings-preview' or type(preview['format_version']) is not int
            or preview['format_version'] != 1 or preview['target_user_data_model_version'] != '1.0'
            or preview['account_binding_pending'] is not True
            or preview['preferences_origin'] not in ('application_defaults', 'saved_planning_preferences', 'saved_profile_preferences')
            or type(preview['profile_preferences_shadowed']) is not bool
            or type(preview['ready_for_binding']) is not bool or not isinstance(preview['issues'], list)
            or any(not isinstance(i, str) or not i for i in preview['issues'])
            or preview['ready_for_binding'] != (not preview['issues'])
            or not isinstance(preview['source_precision'], list)):
        raise ContractError('invalid_settings_preview')
    ids = set()
    for field, filename in (('preferences', 'user-preferences.schema.json'), ('profile', 'user-profile.schema.json')):
        draft = preview[field]
        if draft is None and field == 'profile':
            continue
        if not isinstance(draft, dict) or set(draft) != {'id', 'payload'}:
            raise ContractError('invalid_settings_draft')
        try:
            if str(uuid.UUID(draft['id'])) != draft['id'] or draft['id'] in ids:
                raise ValueError()
        except (ValueError, TypeError, AttributeError):
            raise ContractError('invalid_settings_identity')
        ids.add(draft['id'])
        # Reuse field constraints for this explicitly local payload; released schemas are unchanged.
        payload_schema = copy.deepcopy(load_json(CONTRACTS / filename)['properties']['payload'])
        payload_schema['properties'].pop('account_id')
        payload_schema['required'].remove('account_id')
        validate_instance(draft['payload'], payload_schema, 'local-settings-payload')
    if (preview['preferences_origin'] == 'saved_profile_preferences' and preview['profile'] is None
            or preview['profile_preferences_shadowed'] and
            (preview['profile'] is None or preview['preferences_origin'] != 'saved_planning_preferences')):
        raise ContractError('invalid_settings_precedence')
    for key in ('defaulted_preference_fields', 'defaulted_profile_fields'):
        values = preview[key]
        if not isinstance(values, list) or any(not isinstance(v, str) or not v for v in values) or len(values) != len(set(values)):
            raise ContractError('invalid_settings_default_evidence')
    default = preview['preferences']['payload']['preferences']['default_list_id']
    if default is not None and not any(r['record_type'] == 'list' and r['id'] == default for r in records):
        raise ContractError('invalid_settings_default_list')
    unresolved = preview['unresolved_default_list_id']
    if unresolved is not None and (type(unresolved) is not int or default is not None
                                 or 'default_list_owner_requires_review' not in preview['issues']):
        raise ContractError('invalid_settings_default_review')
    if preview['profile'] is not None:
        avatar = preview['profile']['payload']['avatar_asset_id']
        if avatar is not None and not any(r['record_type'] == 'unavailable_reference'
                and r['payload']['target_type'] == 'asset' and r['payload']['target_id'] == avatar for r in records):
            raise ContractError('invalid_settings_avatar_target')
    return 1 + (preview['profile'] is not None)


def validate_studio_preview(preview, records, appearance_preview=None):
    """Verify local Studio/global-default evidence without inventing account or schema fields."""
    import copy
    import uuid
    keys = {'format', 'format_version', 'target_user_data_model_version', 'account_binding_pending',
            'studio_settings', 'global_week_appearance', 'artwork_ids', 'artwork_store_present',
            'issues', 'canonical_mapping_complete'}
    if isinstance(preview, dict) and preview.get('format_version') == 2:
        keys.add('appearance_model_version')
    if (not isinstance(preview, dict) or set(preview) != keys
            or preview['format'] != 'plenact.ios-studio-preview' or type(preview['format_version']) is not int
            or preview['format_version'] not in (1, 2) or preview['target_user_data_model_version'] != '1.0'
            or preview['account_binding_pending'] is not True or type(preview['artwork_store_present']) is not bool
            or not isinstance(preview['artwork_ids'], list) or not isinstance(preview['issues'], list)
            or any(not isinstance(i, str) or not i for i in preview['issues'])
            or type(preview['canonical_mapping_complete']) is not bool
            or preview['canonical_mapping_complete'] != (not preview['issues'])):
        raise ContractError('invalid_studio_preview')
    artwork = {r['id'] for r in records if r['record_type'] == 'studio_artwork'}
    if (len(preview['artwork_ids']) != len(set(preview['artwork_ids'])) or set(preview['artwork_ids']) != artwork
            or (not preview['artwork_store_present'] and artwork)):
        raise ContractError('invalid_studio_artwork_membership')
    if preview['format_version'] == 1 and len(artwork) > 1 and 'artwork_order_canonical_mapping_pending' not in preview['issues']:
        raise ContractError('studio_order_mapping_not_reported')
    extra = []
    for field, body in (('studio_settings', 'payload'), ('global_week_appearance', 'appearance')):
        draft = preview[field]
        if draft is None:
            continue
        if not isinstance(draft, dict) or set(draft) != {'id', body}:
            raise ContractError('invalid_studio_draft')
        try:
            if str(uuid.UUID(draft['id'])) != draft['id']:
                raise ValueError()
        except (ValueError, TypeError, AttributeError):
            raise ContractError('invalid_studio_identity')
        if field == 'studio_settings':
            schema = copy.deepcopy(load_json(CONTRACTS / 'studio-settings.schema.json')['properties']['payload'])
            schema['required'].remove('account_id')
            schema['properties'].pop('account_id')
            validate_instance(draft[body], schema, 'local-studio-payload')
            destinations = [v['destination'] for v in draft[body]['views']]
            if len(destinations) != len(set(destinations)):
                raise ContractError('duplicate_studio_destination')
        else:
            validate_instance(draft[body], {'$ref': 'urn:plenact:user-data:1.0:content-types#/$defs/board_appearance'},
                              'local-week-appearance')
            if preview['format_version'] == 1 and 'global_week_appearance_canonical_mapping_pending' not in preview['issues']:
                raise ContractError('global_week_mapping_not_reported')
        extra.append({'record_type': 'studio_settings_preview' if field == 'studio_settings' else 'week_appearance_preview',
                      'id': draft['id'], 'payload': draft[body]})
    if preview['format_version'] == 2:
        if preview['appearance_model_version'] != '1.1' or appearance_preview is None:
            raise ContractError('model_1_1_appearance_evidence_required')
        extra += validate_appearance_preview(appearance_preview, records)
        library = appearance_preview['artwork_library']
        global_week = appearance_preview['workspace_appearance']
        if ((library is not None) != preview['artwork_store_present']
                or library is not None and library['payload']['artwork_ids'] != preview['artwork_ids']
                or (global_week is not None) != (preview['global_week_appearance'] is not None)
                or global_week is not None and global_week['payload']['week_board_defaults'] !=
                    preview['global_week_appearance']['appearance']):
            raise ContractError('studio_model_1_1_source_mismatch')
    return extra


def validate_planning_preview(preview, records):
    """Check source-domain coverage and no-execution evidence around canonical history records."""
    keys = {'format', 'format_version', 'target_user_data_model_version', 'converted_source_stores',
            'source_store_versions', 'planning_record_count', 'unavailable_reference_count', 'source_precision',
            'review_actions_executed', 'notifications_scheduled'}
    stores = {'Plenact.DailyPlans.v1', 'Plenact.WeeklyReviews.v1', 'Plenact.PeriodicReviews.v1', 'Plenact.ReviewRhythm.v1'}
    if (not isinstance(preview, dict) or set(preview) != keys
            or preview['format'] != 'plenact.ios-planning-preview' or type(preview['format_version']) is not int
            or preview['format_version'] != 1 or preview['target_user_data_model_version'] != '1.0'
            or preview['review_actions_executed'] is not False or preview['notifications_scheduled'] is not False
            or not isinstance(preview['converted_source_stores'], list)
            or not all(isinstance(v, str) for v in preview['converted_source_stores'])
            or len(preview['converted_source_stores']) != len(set(preview['converted_source_stores']))
            or not set(preview['converted_source_stores']).issubset(stores)
            or not isinstance(preview['source_store_versions'], dict)
            or set(preview['source_store_versions']) != set(preview['converted_source_stores']) - {'Plenact.ReviewRhythm.v1'}
            or any(type(v) is not int or v != 1 for v in preview['source_store_versions'].values())
            or not isinstance(preview['source_precision'], list)
            or type(preview['planning_record_count']) is not int
            or type(preview['unavailable_reference_count']) is not int or preview['unavailable_reference_count'] < 0):
        raise ContractError('invalid_planning_preview')
    kinds = {'daily_plan': 'Plenact.DailyPlans.v1', 'weekly_review': 'Plenact.WeeklyReviews.v1',
             'periodic_review': 'Plenact.PeriodicReviews.v1', 'review_rhythm': 'Plenact.ReviewRhythm.v1'}
    planning = [r for r in records if r['record_type'] in kinds]
    if (len(planning) != preview['planning_record_count']
            or any(kinds[r['record_type']] not in preview['converted_source_stores'] for r in planning)
            or preview['unavailable_reference_count'] > sum(r['record_type'] == 'unavailable_reference' for r in records)):
        raise ContractError('planning_preview_coverage_mismatch')
    return len(planning)



def validate_appearance_preview(preview, records):
    """Validate the separately versioned local 1.1 metadata without weakening base record validation."""
    import uuid
    from appearance_contract import validate_links
    keys = {'format', 'format_version', 'target_user_data_model_version', 'base_user_data_model_version',
            'workspace_id', 'workspace_identity_scope', 'workspace_appearance', 'artwork_library'}
    if (not isinstance(preview, dict) or set(preview) != keys
            or preview['format'] != 'plenact.ios-appearance-preview' or type(preview['format_version']) is not int
            or preview['format_version'] != 1 or preview['target_user_data_model_version'] != '1.1'
            or preview['base_user_data_model_version'] != '1.0' or preview['workspace_identity_scope'] != 'local_preview'):
        raise ContractError('invalid_appearance_preview')
    try:
        if str(uuid.UUID(preview['workspace_id'])) != preview['workspace_id']:
            raise ValueError()
    except (ValueError, TypeError, AttributeError):
        raise ContractError('invalid_appearance_workspace')
    if any(r['workspace_id'] != preview['workspace_id'] for r in records):
        raise ContractError('appearance_base_workspace_mismatch')
    validate_links(preview['workspace_appearance'], preview['artwork_library'], records, preview['workspace_id'])
    return [r for r in (preview['workspace_appearance'], preview['artwork_library']) if r is not None]
