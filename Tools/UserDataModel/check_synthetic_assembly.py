"""Recheck explicitly supplied synthetic XCTest evidence through complete export assembly.

Supported User Data Model versions: 1.0 base and working 1.1 composition.
Input must be an xcresulttool attachments export from synthetic migration tests.
Reads only the supplied directory; never locates live app containers or imports data.
"""
import argparse
import base64
import copy
import io
import uuid
import zipfile
from pathlib import Path
from bind_synthetic_preview import bind_preview
from synthetic_export_package import package_bytes, read_package
from capture_export import checked_file
from validate_contract import ContractError, load_json


def check(directory):
    """Assemble native media/settings/Studio slices, prove stable retries and reject corruption."""
    root = Path(directory).resolve(strict=True)
    manifest = load_json(checked_file(root, 'manifest.json'))
    evidence = {}
    for test in manifest:
        for attachment in test['attachments']:
            if not attachment['exportedFileName'].endswith('.json'):
                continue
            name = attachment['suggestedHumanReadableName'].split('_0_')[0]
            if name in evidence:
                raise ContractError('duplicate_native_evidence_name')
            evidence[name] = load_json(checked_file(root, attachment['exportedFileName']))
    counts = {}
    for prefix, fields in (
        ('Media', {'assets': 'AssetPreview'}),
        ('Settings', {'settings': 'SettingsPreview', 'assets': 'AssetPreview'}),
        ('Studio', {'studio': 'StudioPreview', 'assets': 'AssetPreview', 'appearance': 'AppearancePreview'}),
    ):
        arguments = {key: evidence[prefix + '-' + value] for key, value in fields.items()}
        originals = {key: base64.b64decode(value, validate=True)
                     for key, value in evidence[prefix + '-Originals'].items()}
        records = evidence[prefix + '-Records']
        before = copy.deepcopy((records, arguments, originals))
        result = bind_preview(records, originals=originals, **arguments)
        if result != bind_preview(records, originals=originals, **arguments) or before != (records, arguments, originals):
            raise ContractError('unstable_or_mutating_binding')
        packed = package_bytes(result, originals)
        if read_package(packed) != (result, originals) or packed != package_bytes(result, originals):
            raise ContractError('package_roundtrip_mismatch')
        base = result['workspace_export']['base_workspace']
        for record in records:
            group = {'card': 'cards', 'list': 'lists', 'collection': 'collections'}.get(record['record_type'])
            if group is not None and record not in base['planning']['content'][group]:
                raise ContractError('content_changed_during_binding')
        if len(base['planning']['assets']) != len(originals):
            raise ContractError('bound_asset_inventory_mismatch')
        for path in originals:
            corrupt = dict(originals)
            corrupt[path] += b'corruption'
            try:
                bind_preview(records, originals=corrupt, **arguments)
            except ContractError as error:
                if error.code != 'asset_original_integrity_mismatch':
                    raise
            else:
                raise ContractError('corrupt_original_accepted')
        if prefix == 'Media':
            # Explicit synthetic selection exercises a real native Card identity; it is not
            # evidence for a bookmark in a personal backup or for native selection generation.
            card = base['planning']['content']['cards'][0]
            selection = {'format': 'plenact.ios-selection-preview', 'format_version': 1,
                'target_user_data_model_version': '1.0', 'account_binding_pending': True,
                'entries': [{'source_collection_id': 'synthetic-source', 'source_owner_scope': 'synthetic-source',
                    'source_card_id': 1, 'card_id': card['id'], 'bookmarked': True, 'importance': 4}], 'issues': []}
            selected = bind_preview(records, originals=originals, selections=selection, **arguments)
            payload = selected['workspace_export']['base_workspace']['content_selections'][0]['payload']
            if payload['importance'] != 4 or payload['bookmarked'] is not True or payload['card_id'] != card['id']:
                raise ContractError('selection_changed_during_binding')
        counts[prefix] = len(originals)
    return counts


def check_native_package(directory, prefix="NativePackage"):
    """Independently validate the combined native package exported by the isolated Swift test."""
    root = Path(directory).resolve(strict=True)
    evidence = {}
    for test in load_json(checked_file(root, 'manifest.json')):
        for attachment in test['attachments']:
            name = attachment['suggestedHumanReadableName'].split('_0_')[0]
            if name.startswith(prefix + '-'):
                if name in evidence:
                    raise ContractError('duplicate_native_package_evidence')
                evidence[name] = checked_file(root, attachment['exportedFileName']).read_bytes()
    import json
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as archive:
        for name in ('Assembly', 'Manifest'):
            archive.writestr(name + '.json', evidence[prefix + '-' + name])
        for name, encoded in json.loads(evidence[prefix + '-Blobs']).items():
            archive.writestr(name, base64.b64decode(encoded, validate=True))
    binding, originals = read_package(output.getvalue())
    base = binding['workspace_export']['base_workspace']
    for selection in base['content_selections']:
        expected = str(uuid.uuid5(uuid.UUID(base['account']['id']),
                                 'content_selection:' + selection['payload']['card_id']))
        if selection['id'] != expected:
            raise ContractError('native_selection_identity_mismatch')
    if prefix == 'TemplateReplacementPackage':
        export = binding['workspace_export']
        planning = base['planning']
        deleted = set(export.get('local_card_deletions', []))
        cards = {r['id']: r['payload'] for r in planning['content']['cards']}
        lists = {r['id']: r['payload'] for r in planning['content']['lists']}
        if len(deleted) != 2 or {cards[id]['title'] for id in deleted} != {'Retained template task', 'Retained Tuesday task'}:
            raise ContractError('template_replacement_fixture_missing_retained_targets')
        owner = planning['weeks'][0]['payload']['collection_id']
        if any(lists[cards[id]['list_id']]['collection_id'] != owner for id in deleted):
            raise ContractError('template_replacement_fixture_wrong_deleted_owner')
        archived = [r for r in cards.values() if r['title'] == 'Retained archived task']
        undated = [r for r in cards.values() if r['title'] == 'Retained undated task']
        if len(archived) != 1 or not archived[0]['archived'] or len(undated) != 1:
            raise ContractError('template_replacement_fixture_lost_preserved_work')
        copies = [r for id, r in cards.items() if id not in deleted and lists[r['list_id']]['collection_id'] == owner
                  and r['title'] in {'Retained template task', 'Applied link target'}]
        if len(copies) != 2 or not planning['weeks'][0]['payload']['explicitly_saved']:
            raise ContractError('template_replacement_fixture_missing_copies')
    elif prefix == 'TemplateApplicationPackage':
        planning = base['planning']
        week = planning['weeks'][0]['payload']
        parents = {r['id'] for r in planning['content']['lists'] if r['payload']['collection_id'] == week['collection_id']}
        cards = [r for r in planning['content']['cards'] if r['payload']['list_id'] in parents]
        targets = [r for r in cards if r['payload']['title'] == 'Applied link target']
        copies = [r for r in cards if r['payload']['title'] == 'Retained template task' and len(r['payload']['checklists']) == 2]
        if len(targets) != 2 or len(copies) != 2 or not week['explicitly_saved']:
            raise ContractError('template_application_fixture_missing_copies')
        target_ids = {r['id'] for r in targets}
        for card in copies:
            link = card['payload']['checklists'][-1]['items'][0]['content']
            if link['kind'] != 'linked_card' or link['card_id'] not in target_ids:
                raise ContractError('template_application_fixture_link_mismatch')
            selection = next(r['payload'] for r in base['content_selections'] if r['payload']['card_id'] == card['id'])
            if not selection['bookmarked'] or selection['importance'] != 1:
                raise ContractError('template_application_fixture_focus_mismatch')
        if len({r['payload']['checklists'][0]['id'] for r in copies}) != 2:
            raise ContractError('template_application_fixture_nested_identity_reused')
    elif prefix == 'TemplateItemDeletionPackage':
        export = binding['workspace_export']
        deleted = export.get('local_card_deletions', [])
        planning = base['planning']
        if len(deleted) != 1:
            raise ContractError('template_item_deletion_fixture_missing_overlay')
        card = next(r for r in planning['content']['cards'] if r['id'] == deleted[0])
        parent = next(r for r in planning['content']['lists'] if r['id'] == card['payload']['list_id'])
        owner = parent['payload']['collection_id']
        template = next(r for r in planning['templates'] if r['payload']['collection_id'] == owner)
        if template['payload']['name'] != 'First week' or deleted[0] not in parent['payload']['card_ids']:
            raise ContractError('template_item_deletion_fixture_lost_retained_membership')
        week_owners = {r['payload']['collection_id'] for r in planning['weeks']}
        if owner in week_owners or card['payload']['title'] != 'Retained template task':
            raise ContractError('template_item_deletion_fixture_owner_mismatch')
        if not any(r['payload']['collection_id'] in week_owners for r in planning['content']['lists']):
            raise ContractError('template_item_deletion_fixture_lost_live_week')
    elif prefix == 'TemplateItemCreationPackage':
        planning = base['planning']
        template = next(r for r in planning['templates'] if r['payload']['name'] == 'First week')
        owner = template['payload']['collection_id']
        lists = [r for r in planning['content']['lists'] if r['payload']['collection_id'] == owner]
        parents = {r['id'] for r in lists}
        cards = [r for r in planning['content']['cards'] if r['payload']['list_id'] in parents]
        new = [r for r in cards if r['payload']['title'] in {'New retained template Card', 'New retained template Note'}]
        if len(new) != 2 or len(cards) != 3 or any(not r['payload']['source_created_at_utc'] for r in new):
            raise ContractError('template_item_creation_fixture_missing_items')
        if owner in {r['payload']['collection_id'] for r in planning['weeks']}:
            raise ContractError('template_item_creation_fixture_owner_mismatch')
        ordered = lists[0]['payload']['card_ids']
        by_id = {r['id']: r['payload'] for r in cards}
        if [by_id[id]['title'] for id in ordered[-2:]] != ['New retained template Card', 'New retained template Note']:
            raise ContractError('template_item_creation_fixture_order_mismatch')
        if by_id[ordered[-1]]['presentation'] != 'note':
            raise ContractError('template_item_creation_fixture_note_mismatch')
    elif prefix == 'RetainedTemplateContentPackage':
        planning = base['planning']
        cards = planning['content']['cards']
        edited = [r for r in cards if r['payload']['title'] == 'Edited retained template task']
        if len(edited) != 1 or edited[0]['payload']['description_override'] != 'Edited template details':
            raise ContractError('retained_template_content_fixture_missing_edit')
        lists = {r['id']: r['payload']['collection_id'] for r in planning['content']['lists']}
        template_owners = {r['payload']['collection_id'] for r in planning['templates']}
        week_owners = {r['payload']['collection_id'] for r in planning['weeks']}
        owner = lists[edited[0]['payload']['list_id']]
        if owner not in template_owners or owner in week_owners:
            raise ContractError('retained_template_content_fixture_owner_mismatch')
        live = [r for r in cards if lists[r['payload']['list_id']] in week_owners]
        if not any(r['payload']['title'] == 'Retained template task' for r in live):
            raise ContractError('retained_template_content_fixture_changed_live_source')
    elif prefix == 'DeletedTemplatePackage':
        planning = base['planning']
        library = planning['template_libraries'][0]['payload']
        if planning['templates'] or library['template_ids'] or library['default_week_id'] is not None:
            raise ContractError('deleted_template_fixture_not_empty')
        if not planning['weeks'] or not planning['content']['cards']:
            raise ContractError('deleted_template_fixture_lost_live_week')
    elif prefix == 'NewTemplatePackage':
        templates = base['planning']['templates']
        if len(templates) != 6:
            raise ContractError('new_template_native_fixture_missing_templates')
        new = [r for r in templates if r['payload']['name'] in {
            'Captured Week', 'Captured Day', 'Duplicated template'}]
        if len(new) != 3:
            raise ContractError('new_template_native_fixture_missing_creations')
        cards = base['planning']['content']['cards']
        lists = base['planning']['content']['lists']
        for template in new:
            owner = template['payload']['collection_id']
            if owner != str(uuid.uuid5(uuid.UUID(template['workspace_id']), 'template_owner:' + template['id'])):
                raise ContractError('new_template_native_owner_identity_mismatch')
            parents = {r['id'] for r in lists if r['payload']['collection_id'] == owner}
            owned = [r for r in cards if r['payload']['list_id'] in parents]
            expected_count = 2 if template['payload']['name'] == 'Captured Week' else 1
            rich = [r for r in owned if r['payload']['title'] == 'Retained template task']
            if len(owned) != expected_count or len(rich) != 1 or rich[0]['payload']['checklists'][0]['title'] != 'Copied steps':
                raise ContractError('new_template_native_fixture_missing_nested_content')
        captured = next(r for r in new if r['payload']['name'] == 'Captured Week')
        library = base['planning']['template_libraries'][0]['payload']
        if library['default_week_id'] != captured['id'] or not captured['payload']['example_focus']['bookmarked']:
            raise ContractError('new_template_native_fixture_missing_default_focus')
    elif prefix == 'TemplateMetadataPackage':
        templates = {r['id']: r['payload'] for r in base['planning']['templates']}
        libraries = base['planning']['template_libraries']
        if len(templates) != 3 or len(libraries) != 1:
            raise ContractError('template_metadata_native_fixture_missing_library')
        library = libraries[0]['payload']
        if [templates[id]['name'] for id in library['template_ids']] != [
                'One day', 'Second week', 'Renamed retained week']:
            raise ContractError('template_metadata_native_fixture_missing_name_order')
        if templates[library['default_week_id']]['name'] != 'Second week':
            raise ContractError('template_metadata_native_fixture_missing_default')
    elif prefix == 'PeriodicReviewPackage':
        reviews = base['planning']['periodic_reviews']
        edited = [r['payload'] for r in reviews if r['payload']['title'] == 'Edited periodic title']
        added = [r for r in reviews if r['payload']['title'] == 'New periodic review']
        if len(reviews) != 2 or len(edited) != 1 or len(added) != 1:
            raise ContractError('periodic_native_fixture_missing_reviews')
        review = edited[0]
        if any(review[k] != 'Edited periodic ' + v for k, v in {
                'highlights': 'highlights', 'learned': 'learning', 'direction': 'direction', 'risks': 'risks'}.items()):
            raise ContractError('periodic_native_fixture_missing_writing')
        starting, current = review['starting_objectives'], review['objectives']
        if (review['step'] != 2 or not review['completed_at_utc'] or len(starting) != 1 or len(current) != 2
                or starting[0]['id'] != current[0]['id'] or starting[0]['status'] != 'active'
                or current[0]['status'] != 'achieved' or current[0]['progress'] != 'Updated objective progress'
                or current[0]['next_step'] != 'Updated objective next step' or current[1]['status'] != 'released'):
            raise ContractError('periodic_native_fixture_missing_objective_snapshots')
    elif prefix == 'WeeklyReviewPackage':
        reviews = base['planning']['weekly_reviews']
        edited = [r['payload'] for r in reviews if r['payload']['highlights'] == 'Edited weekly highlights']
        added = [r for r in reviews if r['payload']['highlights'] == 'New weekly highlights']
        if len(reviews) != 2 or len(edited) != 1 or len(added) != 1:
            raise ContractError('weekly_native_fixture_missing_changes')
        review = edited[0]
        if (review['learned'] != 'Edited weekly learning' or review['direction'] != 'Edited weekly direction'
                or review['constraints'] != 'Edited weekly constraints' or review['risks'] != 'Edited weekly risks'
                or review['step'] != 2 or len(review['decisions']) != 9 or len(review['priorities']) != 1
                or review['completed_at_utc'] != review['decisions'][-1]['recorded_at_utc']):
            raise ContractError('weekly_native_fixture_missing_history')
        record = added[0]
        if record['id'] != str(uuid.uuid5(uuid.UUID(record['workspace_id']),
                                        'weekly_review:' + record['payload']['source_review_key'])):
            raise ContractError('weekly_native_identity_mismatch')
    elif prefix == 'EveningReviewPackage':
        plans = base['planning']['daily_plans']
        reviews = [r['payload']['evening_review'] for r in plans]
        edited = [r for r in reviews if r and r['helped'] == 'Edited evening reflection']
        added = [r for r in reviews if r and r['helped'] == 'New evening reflection']
        if len(edited) != 1 or len(added) != 1:
            raise ContractError('evening_native_fixture_missing_reflections')
        review = edited[0]
        if (review['difficult'] != 'A synthetic difficulty' or review['tomorrow'] != 'A synthetic next step'
                or review['step'] != 2 or len(review['achievements']) != 1 or len(review['decisions']) != 9
                or review['decisions'][-1]['action'] != {'kind': 'date', 'date': '2026-10-28'}
                or review['completed_at_utc'] != review['decisions'][-1]['recorded_at_utc']):
            raise ContractError('evening_native_fixture_missing_history')
        if {d['action']['kind'] for d in review['decisions']} != {
                'keep', 'keep_tomorrow', 'table', 'complete', 'archive', 'queue', 'tomorrow', 'date'}:
            raise ContractError('evening_native_fixture_missing_actions')
    elif prefix == 'DailyPlanPackage':
        plans = base['planning']['daily_plans']
        edited = [r['payload'] for r in plans if r['payload']['intention'] == 'Edited synthetic intention']
        added = [r for r in plans if r['payload']['intention'] == 'New synthetic daily plan']
        if len(plans) != 3 or len(edited) != 1 or len(added) != 1:
            raise ContractError('daily_plan_native_fixture_missing_changes')
        history = edited[0]['check_ins']
        if (len(history) != 2 or history[0]['id'] != 'retained-history-id'
                or history[-1]['changed'] != 'New synthetic check-in'
                or history[-1]['intention'] != edited[0]['intention']
                or history[-1]['mood'] != {'emoji': '🌱', 'label': 'Steady'}):
            raise ContractError('daily_plan_native_fixture_missing_history')
        record = added[0]
        expected_id = str(uuid.uuid5(uuid.UUID(record['workspace_id']),
                                    'daily_plan:' + record['payload']['date'] + ':' + record['payload']['time_zone']))
        if record['id'] != expected_id:
            raise ContractError('daily_plan_native_identity_mismatch')
    elif prefix in ('NewRhythmPackage', 'RetainedRhythmPackage'):
        rhythms = base['planning']['review_rhythms']
        expected = {'daily_invitations': False, 'weekly_invitations': False,
                    'daily_minutes': 17, 'weekly_minutes': 1439, 'weekly_weekday': 7,
                    'daily_notifications': True, 'weekly_notifications': True}
        if len(rhythms) != 1 or any(rhythms[0]['payload'].get(k) != v for k, v in expected.items()):
            raise ContractError('rhythm_native_fixture_missing_choices')
        if prefix == 'NewRhythmPackage':
            record = rhythms[0]
            expected_id = str(uuid.uuid5(uuid.UUID(record['workspace_id']),
                                        'review_rhythm:Plenact.ReviewRhythm.v1'))
            if record['id'] != expected_id:
                raise ContractError('rhythm_native_identity_mismatch')
    elif prefix == 'NativePackage':
        if len(base['profiles']) != 1 or len(base['planning']['daily_plans']) != 1 or len(base['content_selections']) != 1:
            raise ContractError('combined_native_fixture_missing_slice')
    elif prefix == 'PersonalizationPackage':
        profiles = base['profiles']
        settings = base['studio_settings']['payload']
        today = next(v['surface'] for v in settings['views'] if v['destination'] == 'today')
        if (len(profiles) != 1 or profiles[0]['payload']['display_name'] != 'Synthetic profile'
                or profiles[0]['payload']['avatar_asset_id'] is None or today['material'] != 'photo'
                or today['photo_asset_id'] is None):
            raise ContractError('personalization_fixture_lost_profile_or_photo')
        library = binding['workspace_export']['artwork_library']['payload']['artwork_ids']
        art = {r['id']: r['payload'] for r in base['artwork']}
        if not library or art[library[0]]['name'] != 'New synthetic look':
            raise ContractError('personalization_fixture_lost_order')
        if binding['workspace_export']['workspace_appearance']['payload']['week_board_defaults']['subtitle_italic'] is not True:
            raise ContractError('personalization_fixture_lost_week_defaults')
    elif prefix == 'RolloverPackage':
        weeks = base['planning']['weeks']
        index = base['planning']['calendar_indexes'][0]['payload']
        if len(weeks) != 2 or len(index['week_ids']) != 2:
            raise ContractError('rollover_fixture_missing_week')
        if base['user_preferences']['payload']['preferences']['today_focus_item_count'] != 7:
            raise ContractError('rollover_fixture_lost_preferences')
        if not any(r['payload']['title'] == 'Rollover Card' for r in base['planning']['content']['cards']):
            raise ContractError('rollover_fixture_lost_card')
        incoming = [r for r in base['planning']['content']['collections']
                    if any(w['payload']['collection_id'] == r['id'] and
                           w['payload']['start_date'] == index['current_week_start_date'] for w in weeks)]
        parents = {r['id'] for r in base['planning']['content']['lists']
                   if r['payload']['collection_id'] == incoming[0]['id']}
        cards = {r['id'] for r in base['planning']['content']['cards'] if r['payload']['list_id'] in parents}
        saved = {r['payload']['card_id'] for r in base['content_selections']
                 if r['payload']['bookmarked'] and r['payload']['card_id'] in cards}
        if len(saved) != 7:
            raise ContractError('rollover_fixture_lost_bookmarks')
    elif prefix == 'PreferencesPackage':
        if base['user_preferences']['payload']['preferences']['today_focus_item_count'] != 7:
            raise ContractError('preferences_fixture_lost_edit')
    elif prefix == 'ExistingListPackage':
        content = base['planning']['content']
        lists = [r for r in content['lists'] if r['payload']['title'] == 'Renamed portable List']
        if len(lists) != 1:
            raise ContractError('existing_list_fixture_missing_target')
        value = lists[0]['payload']
        if (value['subtitle_override'] != 'Authored subtitle' or value['default_item_presentation'] != 'note'
                or value['appearance']['subtitle_italic'] is not True
                or value['appearance']['studio_surface']['material'] != 'gradient'):
            raise ContractError('existing_list_fixture_lost_metadata')
        owner = next(r['payload'] for r in content['collections'] if r['id'] == value['collection_id'])
        if (owner['title'] != 'Renamed portable Collection'
                or owner['description'] != 'Updated collection description'
                or owner['board_appearance']['subtitle_italic'] is not True):
            raise ContractError('existing_collection_fixture_lost_metadata')
    elif prefix == 'ExistingCardPackage':
        content = base['planning']['content']
        cards = [r['payload'] for r in content['cards'] if r['payload']['title'] == 'New structural Card']
        if len(cards) != 1:
            raise ContractError('existing_card_fixture_missing_target')
        rich = cards[0]
        if (len(rich['comments']) != 2 or rich['comments'][0]['body'] != 'Updated existing comment'
                or len(rich['checklists']) != 5 or len(rich['attachments'] or []) != 2
                or len(rich['members']) != 1 or len(rich['reactions'] or []) != 1
                or rich['cover_attachment_id'] != rich['attachments'][1]['id']):
            raise ContractError('existing_card_fixture_lost_edit')
    elif prefix == 'StructuralPackage':
        content = base['planning']['content']
        cards = content['cards']
        created = [r for r in cards if r['payload']['title'] == 'New structural Card']
        lists = [r for r in content['lists'] if r['payload']['title'] == 'New structural List']
        if len(cards) != 2 or len(created) != 1 or len(lists) != 1:
            raise ContractError('structural_native_fixture_missing_creation')
        rich = created[0]['payload']
        if len(rich['comments']) != 1 or len(rich['attachments'] or []) != 1 or len(rich['checklists']) != 4 or not rich['completed']:
            raise ContractError('rich_native_fixture_missing_content')
        selections = [r['payload'] for r in base['content_selections'] if r['payload']['card_id'] == created[0]['id']]
        if len(selections) != 1 or selections[0]['bookmarked'] is not True:
            raise ContractError('rich_native_fixture_missing_bookmark')
        parent = lists[0]
        if parent['payload']['card_ids'][0] != created[0]['id'] or parent['id'] != content['collections'][0]['payload']['list_ids'][0]:
            raise ContractError('structural_native_fixture_lost_order')
    elif prefix == 'DeletedPackage':
        cards = base['planning']['content']['cards']
        deleted = binding['workspace_export'].get('local_card_deletions', [])
        if len(cards) != 1 or deleted != [cards[0]['id']] or base['tombstones']:
            raise ContractError('deleted_native_fixture_missing_intent')
    else:
        cards = base['planning']['content']['cards']
        if len(cards) != 1 or cards[0]['payload']['title'] != 'Edited portable Card' or cards[0]['payload']['description_override'] != 'An edited description' or not cards[0]['payload']['edit_history']:
            raise ContractError('edited_native_fixture_missing_changes')
    return len(originals)


def main():
    """Print aggregate synthetic test counts without logging records or private source values."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('attachments', type=Path)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--native-package', action='store_true')
    modes.add_argument('--edited-package', action='store_true')
    modes.add_argument('--deleted-package', action='store_true')
    modes.add_argument('--structural-package', action='store_true')
    modes.add_argument('--existing-card-package', action='store_true')
    modes.add_argument('--existing-list-package', action='store_true')
    modes.add_argument('--preferences-package', action='store_true')
    modes.add_argument('--rollover-package', action='store_true')
    modes.add_argument('--personalization-package', action='store_true')
    modes.add_argument('--rhythm-package', action='store_true')
    modes.add_argument('--daily-plan-package', action='store_true')
    modes.add_argument('--evening-review-package', action='store_true')
    modes.add_argument('--weekly-review-package', action='store_true')
    modes.add_argument('--periodic-review-package', action='store_true')
    modes.add_argument('--template-metadata-package', action='store_true')
    modes.add_argument('--template-replacement-package', action='store_true')
    modes.add_argument('--template-application-package', action='store_true')
    modes.add_argument('--template-item-deletion-package', action='store_true')
    modes.add_argument('--template-item-creation-package', action='store_true')
    modes.add_argument('--retained-template-content-package', action='store_true')
    modes.add_argument('--deleted-template-package', action='store_true')
    modes.add_argument('--new-template-package', action='store_true')
    args = parser.parse_args()
    if args.template_replacement_package:
        count = check_native_package(args.attachments, prefix='TemplateReplacementPackage')
        print(f'Template replacement package passed independent validation: {count} original files.')
        return
    if args.template_application_package:
        count = check_native_package(args.attachments, prefix='TemplateApplicationPackage')
        print(f'Template application package passed independent validation: {count} original files.')
        return
    if args.template_item_deletion_package:
        count = check_native_package(args.attachments, prefix='TemplateItemDeletionPackage')
        print(f'Template item deletion package passed independent validation: {count} original files.')
        return
    if args.template_item_creation_package:
        count = check_native_package(args.attachments, prefix='TemplateItemCreationPackage')
        print(f'Template item creation package passed independent validation: {count} original files.')
        return
    if args.retained_template_content_package:
        count = check_native_package(args.attachments, prefix='RetainedTemplateContentPackage')
        print(f'Retained template content package passed independent validation: {count} original files.')
        return
    if args.deleted_template_package:
        count = check_native_package(args.attachments, prefix='DeletedTemplatePackage')
        print(f'Deleted template package passed independent validation: {count} original files.')
        return
    elif args.new_template_package:
        count = check_native_package(args.attachments, prefix='NewTemplatePackage')
        print(f'New template package passed independent validation: {count} original files.')
        return
    if args.template_metadata_package:
        count = check_native_package(args.attachments, prefix='TemplateMetadataPackage')
        print(f'Template metadata package passed independent validation: {count} original files.')
        return
    if args.periodic_review_package:
        count = check_native_package(args.attachments, prefix='PeriodicReviewPackage')
        print(f'Periodic review package passed independent validation: {count} original files.')
        return
    if args.weekly_review_package:
        count = check_native_package(args.attachments, prefix='WeeklyReviewPackage')
        print(f'Weekly review package passed independent validation: {count} original files.')
        return
    if args.evening_review_package:
        count = check_native_package(args.attachments, prefix='EveningReviewPackage')
        print(f'Evening review package passed independent validation: {count} original files.')
        return
    if args.daily_plan_package:
        count = check_native_package(args.attachments, prefix='DailyPlanPackage')
        print(f'Daily plan package passed independent validation: {count} original files.')
        return
    if args.rhythm_package:
        for prefix in ('NewRhythmPackage', 'RetainedRhythmPackage'):
            count = check_native_package(args.attachments, prefix=prefix)
            print(f'{prefix} passed independent validation: {count} original files.')
        return
    if args.personalization_package:
        count = check_native_package(args.attachments, prefix='PersonalizationPackage')
        print(f'Personalization package passed independent validation: {count} original files.')
        return
    if args.rollover_package:
        count = check_native_package(args.attachments, prefix='RolloverPackage')
        print(f'Rollover package passed independent validation: {count} original files.')
        return
    if args.preferences_package:
        count = check_native_package(args.attachments, prefix='PreferencesPackage')
        print(f'Preferences package passed independent validation: {count} original files.')
        return
    if args.existing_list_package:
        count = check_native_package(args.attachments, prefix='ExistingListPackage')
        print(f'Existing-List package passed independent validation: {count} original files.')
        return
    if args.existing_card_package:
        count = check_native_package(args.attachments, prefix='ExistingCardPackage')
        print(f'Existing-Card edited package passed independent validation: {count} original files.')
        return
    if args.structural_package:
        count = check_native_package(args.attachments, prefix='StructuralPackage')
        print(f'Structural native package passed independent validation: {count} original files.')
        return
    if args.deleted_package:
        count = check_native_package(args.attachments, prefix='DeletedPackage')
        print(f'Pending-deletion native package passed independent validation: {count} original files.')
        return
    if args.edited_package:
        count = check_native_package(args.attachments, prefix='EditedPackage')
        print(f'Edited native portable package passed independent validation: {count} original files.')
        return
    if args.native_package:
        count = check_native_package(args.attachments)
        print(f'Combined native portable test package passed independent validation: {count} original files.')
        return
    counts = check(args.attachments)
    print('Synthetic complete-export checks passed: ' + ', '.join(f'{key}: {value} original files' for key, value in counts.items()))


if __name__ == '__main__':
    main()
