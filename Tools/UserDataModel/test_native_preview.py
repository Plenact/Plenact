"""Model 1.0 native-preview independent checker regression coverage; synthetic files only."""

import copy
import unittest
import uuid
from datetime import datetime, timezone
from zoneinfo import ZoneInfo, reset_tzpath
import tzdata
from validate_contract import CONTRACTS, ContractError, load_json
from validate_native_preview import validate_records


class NativePreviewValidatorTests(unittest.TestCase):
    def records(self):
        """Use frozen published category/label/display fixtures without app data."""
        return [load_json(CONTRACTS / "Fixtures" / name) for name in (
            "label-category-definition.json", "label-definition.json", "display-preferences-definition.json")]

    def test_shared_contract_values_validate(self):
        self.assertEqual(validate_records(self.records()), 3)
        self.assertEqual(validate_records([]), 0)

    def test_duplicate_identity_and_missing_category_rejected(self):
        records = self.records()
        with self.assertRaises(ContractError):
            validate_records(records + records[:1])
        with self.assertRaises(ContractError):
            validate_records(records[1:])

    def test_false_is_not_numeric_zero(self):
        records = self.records()
        records[2]["payload"]["card_covers_enabled"] = 0
        with self.assertRaises(ContractError):
            validate_records(records)

    def test_unsupported_slice_and_workspace_mismatch_rejected(self):
        records = self.records()
        with self.assertRaises(ContractError):
            validate_records([load_json(CONTRACTS / "Fixtures/account-definition.json")])
        records[2]["workspace_id"] = "90000000-0000-4000-8000-000000000009"
        with self.assertRaises(ContractError):
            validate_records(records)


    def content_records(self):
        """Build a valid synthetic content slice with explicit evidence for every external target."""
        graph = load_json(CONTRACTS / "Fixtures/complete-content-graph.json")
        records = graph["collections"] + graph["lists"] + graph["cards"]
        for reference in graph["external_references"]:
            records.append({"user_data_model_version": "1.0", "payload_schema_version": 1,
                "record_type": "unavailable_reference", "workspace_id": graph["workspace_id"],
                "id": str(uuid.uuid5(uuid.NAMESPACE_URL, reference["record_type"] + reference["id"])),
                "payload": {"target_type": reference["record_type"], "target_id": reference["id"],
                    "reason": "legacy_unresolved", "display_text": None}})
        return records

    def test_content_membership_and_external_evidence(self):
        records = self.content_records()
        self.assertEqual(validate_records(records), len(records))
        without_parent = [r for r in records if r["record_type"] != "collection"]
        with self.assertRaises(ContractError):
            validate_records(without_parent)
        card = next(r for r in records if r["record_type"] == "card")
        card["payload"]["archived"] = not card["payload"]["archived"]
        with self.assertRaises(ContractError):
            validate_records(records)

    def test_unavailable_target_cannot_impersonate_a_real_record(self):
        records = self.content_records()
        declaration = next(r for r in records if r["record_type"] == "unavailable_reference")
        declaration["payload"]["target_id"] = records[0]["id"]
        with self.assertRaises(ContractError):
            validate_records(records)

    def test_pinned_transition_projection_matches_reference_rules(self):
        reset_tzpath([])
        rules = load_json(CONTRACTS.parents[3] / "Src/Persistence/MigrationTimeZoneRules.json")
        self.assertEqual(rules["tzdb_version"], tzdata.IANA_VERSION)
        for name, transitions in rules["zones"].items():
            zone = ZoneInfo(name)
            self.assertEqual(transitions[0][0], rules["start_epoch"])
            self.assertEqual(sorted({r[0] for r in transitions}), [r[0] for r in transitions])
            for index, (instant, offset) in enumerate(transitions):
                end = transitions[index + 1][0] if index + 1 < len(transitions) else rules["end_epoch"]
                for sample in (instant, (instant + end) // 2, end - 1):
                    actual = datetime.fromtimestamp(sample, timezone.utc).astimezone(zone).utcoffset().total_seconds()
                    self.assertEqual(actual, offset, (name, sample))


class SelectionPreviewTests(unittest.TestCase):
    """Local selection evidence must never masquerade as a bound account selection."""

    def test_unbound_entries_and_invalid_target(self):
        from validate_native_preview import validate_selection_preview
        records = NativePreviewValidatorTests().content_records()
        card = next(r for r in records if r['record_type'] == 'card')
        entry = {'source_collection_id': 'legacy-owner', 'source_owner_scope': 'owner:1', 'source_card_id': 1,
                 'card_id': card['id'], 'bookmarked': True, 'importance': 5}
        preview = {'format': 'plenact.ios-selection-preview', 'format_version': 1,
                   'target_user_data_model_version': '1.0', 'account_binding_pending': True,
                   'entries': [entry], 'issues': []}
        self.assertEqual(validate_selection_preview(preview, records), 1)
        for key, value in [('importance', 6), ('importance', True), ('bookmarked', 1), ('card_id', 'missing')]:
            changed = copy.deepcopy(preview)
            changed['entries'][0][key] = value
            with self.assertRaises(ContractError):
                validate_selection_preview(changed, records)
        changed = copy.deepcopy(preview)
        changed['entries'].append(copy.deepcopy(entry))
        with self.assertRaises(ContractError):
            validate_selection_preview(changed, records)
        preview['account_binding_pending'] = False
        with self.assertRaises(ContractError):
            validate_selection_preview(preview, records)


class CalendarTemplatePreviewTests(unittest.TestCase):
    """Verify account-unbound metadata against real content membership and planning invariants."""

    def records(self):
        """Use the frozen planning graph as an independently authored positive slice."""
        graph = load_json(CONTRACTS / 'Fixtures/complete-planning-graph.json')
        content = graph['content']
        records = content['collections'] + content['lists'] + content['cards']
        for reference in content['external_references']:
            records.append({'user_data_model_version': '1.0', 'payload_schema_version': 1,
                            'record_type': 'unavailable_reference', 'workspace_id': graph['workspace_id'],
                            'id': str(uuid.uuid5(uuid.NAMESPACE_URL, reference['record_type'] + reference['id'])),
                            'payload': {'target_type': reference['record_type'], 'target_id': reference['id'],
                                        'reason': 'legacy_unresolved', 'display_text': None}})
        for key in ('calendar_indexes', 'weeks', 'templates', 'template_libraries'):
            records += graph[key]
        return records

    def test_metadata_slice_validates_without_an_invented_account(self):
        records = self.records()
        self.assertEqual(validate_records(records), len(records))
        self.assertFalse(any('account_id' in r['payload'] for r in records))

    def test_metadata_rejects_wrong_owner_and_missing_current_week(self):
        records = self.records()
        index = next(r for r in records if r['record_type'] == 'calendar_index')
        index['payload']['current_week_start_date'] = '2026-11-02'
        with self.assertRaisesRegex(ContractError, 'native_preview_current_week_missing'):
            validate_records(records)
        records = self.records()
        week = next(r for r in records if r['record_type'] == 'calendar_week')
        week['payload']['collection_id'] = '90000000-0000-4000-8000-000000000009'
        with self.assertRaises(ContractError):
            validate_records(records)

    def test_metadata_rejects_dangling_default_focus_and_checklist_links(self):
        for kind, field, value in (
                ('template_library', 'default_week_id', '90000000-0000-4000-8000-000000000009'),
                ('planning_template', 'example_focus', {'important': ['90000000-0000-4000-8000-000000000009'],
                                                       'bookmarked': [], 'all_day': []}),
                ('calendar_index', 'checklist_link_weeks', [{'checklist_item_id': '90000000-0000-4000-8000-000000000009',
                                                            'week_id': '30000000-0000-4000-8000-000000000002'}])):
            records = self.records()
            next(r for r in records if r['record_type'] == kind)['payload'][field] = value
            with self.assertRaises(ContractError):
                validate_records(records)


class AssetPreviewTests(unittest.TestCase):
    """Check original bytes, strict local evidence and actual content field linkage."""

    def fixture(self):
        import hashlib
        asset = '90000000-0000-4000-8000-000000000001'
        card = '90000000-0000-4000-8000-000000000002'
        path = 'Documents/CardAttachments/original.bin'
        data = b'\x00\xff'
        entry = {'asset_id': asset, 'source_path': path, 'kind': 'binary', 'mime_type': 'application/octet-stream',
                 'original_name': 'original.bin', 'content_state': 'described', 'byte_length': '2',
                 'sha256': hashlib.sha256(data).hexdigest(), 'source_format': None,
                 'derived_from_asset_id': None, 'source_created_at_utc': None, 'attribution': None,
                 'type_evidence': 'unknown', 'references': [{'record_id': card,
                    'field_path': '/payload/attachments/0/asset_id', 'role': 'attachment_original'}]}
        preview = {'format': 'plenact.ios-asset-preview', 'format_version': 1,
                   'target_user_data_model_version': '1.0', 'account_binding_pending': True,
                   'entries': [entry], 'issues': []}
        records = [{'record_type': 'card', 'id': card, 'payload': {'attachments': [{'asset_id': asset}]}}]
        return preview, records, {path: data}

    def test_bytes_and_content_reference_must_match(self):
        from validate_native_preview import validate_asset_preview
        preview, records, files = self.fixture()
        self.assertEqual(validate_asset_preview(preview, records, files), 1)
        for mutation in ('bytes', 'path', 'reference', 'owner', 'duplicate'):
            candidate, content, originals = copy.deepcopy((preview, records, files))
            if mutation == 'bytes':
                originals[next(iter(originals))] = b'changed'
            elif mutation == 'path':
                candidate['entries'][0]['source_path'] = '../outside.bin'
            elif mutation == 'reference':
                candidate['entries'][0]['references'] = []
            elif mutation == 'owner':
                candidate['account_binding_pending'] = False
            else:
                candidate['entries'].append(copy.deepcopy(candidate['entries'][0]))
            with self.assertRaises(ContractError):
                validate_asset_preview(candidate, content, originals)

    def test_missing_original_has_no_fabricated_hash(self):
        from validate_native_preview import validate_asset_preview
        preview, records, files = self.fixture()
        entry = preview['entries'][0]
        entry.update(content_state='unavailable', byte_length=None, sha256=None)
        preview['issues'] = ['asset_original_unavailable:' + entry['asset_id']]
        self.assertEqual(validate_asset_preview(preview, records, {}), 1)
        with self.assertRaises(ContractError):
            validate_asset_preview(preview, records, files)
        entry['sha256'] = '0' * 64
        with self.assertRaises(ContractError):
            validate_asset_preview(preview, records, {})

    def test_preserved_unreferenced_file_cannot_disappear(self):
        from validate_native_preview import validate_asset_preview
        preview, records, files = self.fixture()
        files['Documents/ProfileAvatars/avatar.png'] = b'preserved'
        with self.assertRaisesRegex(ContractError, 'asset_inventory_mismatch'):
            validate_asset_preview(preview, records, files)


class SettingsPreviewTests(unittest.TestCase):
    """Check draft payload constraints and Today shortcut membership independently of Swift."""

    def fixture(self):
        import copy
        schema = load_json(CONTRACTS / 'user-preferences.schema.json')
        fields = schema['properties']['payload']['properties']['preferences']['properties']
        preferences = {}
        for name, rule in fields.items():
            preferences[name] = rule['enum'][0] if 'enum' in rule else False
        preferences['default_list_id'] = None
        preferences['today_focus_item_count'] = 0
        return {'format': 'plenact.ios-settings-preview', 'format_version': 1,
                'target_user_data_model_version': '1.0', 'account_binding_pending': True, 'profile': None,
                'preferences': {'id': '90000000-0000-4000-8000-000000000001', 'payload': {'preferences': preferences}},
                'preferences_origin': 'application_defaults', 'defaulted_preference_fields': [],
                'defaulted_profile_fields': [], 'profile_preferences_shadowed': False,
                'unresolved_default_list_id': None, 'source_precision': [], 'issues': [], 'ready_for_binding': True}

    def test_settings_constraints_and_account_boundary(self):
        from validate_native_preview import validate_settings_preview
        preview = self.fixture()
        self.assertEqual(validate_settings_preview(preview, []), 1)
        for key, value in [('today_focus_item_count', 13), ('shows_navigation_labels', 0),
                           ('importance_star_style', 'numeric'), ('preferred_maps_app', 'unknown')]:
            changed = copy.deepcopy(preview)
            changed['preferences']['payload']['preferences'][key] = value
            with self.assertRaises(ContractError):
                validate_settings_preview(changed, [])
        preview['preferences']['payload']['account_id'] = '90000000-0000-4000-8000-000000000002'
        with self.assertRaises(ContractError):
            validate_settings_preview(preview, [])

    def test_unresolved_default_must_remain_explicit_review(self):
        from validate_native_preview import validate_settings_preview
        preview = self.fixture()
        preview.update(unresolved_default_list_id=999, issues=['default_list_owner_requires_review'], ready_for_binding=False)
        self.assertEqual(validate_settings_preview(preview, []), 1)
        preview['issues'] = []
        preview['ready_for_binding'] = True
        with self.assertRaises(ContractError):
            validate_settings_preview(preview, [])

    def test_shortcuts_require_the_actual_list_owner(self):
        records = NativePreviewValidatorTests().content_records()
        collection = next(r for r in records if r['record_type'] == 'collection')
        target = next(r for r in records if r['record_type'] == 'list' and r['payload']['collection_id'] == collection['id'])
        shortcut = {'user_data_model_version': '1.0', 'payload_schema_version': 1,
                    'record_type': 'today_shortcuts', 'workspace_id': collection['workspace_id'],
                    'id': '90000000-0000-4000-8000-000000000001',
                    'payload': {'items': [{'collection_id': collection['id'], 'list_id': target['id']}]}}
        records.append(shortcut)
        self.assertEqual(validate_records(records), len(records))
        shortcut['payload']['items'][0]['collection_id'] = '90000000-0000-4000-8000-000000000002'
        with self.assertRaises(ContractError):
            validate_records(records)


class StudioPreviewTests(unittest.TestCase):
    """Protect explicit global appearance gaps and canonical artwork references."""

    def fixture(self):
        artwork = load_json(CONTRACTS / 'Fixtures/studio-artwork-definition.json')
        preview = {'format': 'plenact.ios-studio-preview', 'format_version': 1,
                   'target_user_data_model_version': '1.0', 'account_binding_pending': True,
                   'studio_settings': None, 'global_week_appearance': None,
                   'artwork_ids': [artwork['id']], 'artwork_store_present': True,
                   'issues': [], 'canonical_mapping_complete': True}
        return preview, [artwork]

    def test_artwork_membership_and_explicit_empty_source(self):
        from validate_native_preview import validate_studio_preview
        preview, records = self.fixture()
        self.assertEqual(validate_studio_preview(preview, records), [])
        preview['artwork_ids'] = []
        with self.assertRaises(ContractError):
            validate_studio_preview(preview, records)
        preview['artwork_store_present'] = False
        self.assertEqual(validate_studio_preview(preview, []), [])

    def test_studio_payload_and_account_boundary(self):
        from validate_native_preview import validate_studio_preview
        preview, records = self.fixture()
        payload = copy.deepcopy(load_json(CONTRACTS / 'Fixtures/studio-settings-definition.json')['payload'])
        payload.pop('account_id')
        preview['studio_settings'] = {'id': '90000000-0000-4000-8000-000000000001', 'payload': payload}
        self.assertEqual(len(validate_studio_preview(preview, records)), 1)
        payload['palette'] = ['abcdef']
        with self.assertRaises(ContractError):
            validate_studio_preview(preview, records)

    def test_global_theme_mapping_gap_cannot_be_hidden(self):
        from validate_native_preview import validate_studio_preview
        preview, records = self.fixture()
        appearance = load_json(CONTRACTS / 'Fixtures/complete-content-graph.json')['collections'][0]['payload']['board_appearance']
        if appearance is None:
            appearance = {k: None for k in load_json(CONTRACTS / 'content-types.schema.json')['$defs']['board_appearance']['required']}
        preview['global_week_appearance'] = {'id': '90000000-0000-4000-8000-000000000001', 'appearance': appearance}
        with self.assertRaisesRegex(ContractError, 'global_week_mapping_not_reported'):
            validate_studio_preview(preview, records)
        preview['issues'] = ['global_week_appearance_canonical_mapping_pending']
        preview['canonical_mapping_complete'] = False
        self.assertEqual(len(validate_studio_preview(preview, records)), 1)


class PlanningHistoryPreviewTests(unittest.TestCase):
    """Check immutable reflection snapshots and explicit missing-reference boundaries."""

    def fixture(self):
        records = CalendarTemplatePreviewTests().records()
        graph = load_json(CONTRACTS / 'Fixtures/complete-planning-graph.json')
        for key in ('daily_plans', 'weekly_reviews', 'periodic_reviews', 'review_rhythms'):
            records += graph[key]
        return records

    def test_planning_history_schema_and_relationships(self):
        records = self.fixture()
        self.assertEqual(validate_records(records), len(records))
        daily = next(r for r in records if r['record_type'] == 'daily_plan')
        daily['payload']['priorities'][0]['card_id'] = '90000000-0000-4000-8000-000000000009'
        with self.assertRaises(ContractError):
            validate_records(records)

    def test_progress_and_historical_counts_are_not_normalized(self):
        records = self.fixture()
        review = next(r for r in records if r['record_type'] == 'periodic_review')
        review['payload']['step'] = 3
        with self.assertRaises(ContractError):
            validate_records(records)
        records = self.fixture()
        review = next(r for r in records if r['record_type'] == 'weekly_review')
        review['payload']['start_date'] = '2026-02-30'
        with self.assertRaises(ContractError):
            validate_records(records)

    def test_empty_coverage_does_not_claim_actions_or_scheduling(self):
        from validate_native_preview import validate_planning_preview
        preview = {'format': 'plenact.ios-planning-preview', 'format_version': 1,
                   'target_user_data_model_version': '1.0', 'converted_source_stores': ['Plenact.DailyPlans.v1'],
                   'source_store_versions': {'Plenact.DailyPlans.v1': 1}, 'planning_record_count': 0,
                   'unavailable_reference_count': 0, 'source_precision': [],
                   'review_actions_executed': False, 'notifications_scheduled': False}
        self.assertEqual(validate_planning_preview(preview, []), 0)
        preview['review_actions_executed'] = True
        with self.assertRaises(ContractError):
            validate_planning_preview(preview, [])
