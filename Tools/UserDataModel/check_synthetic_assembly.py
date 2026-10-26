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
    if prefix == 'WeeklyReviewPackage':
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
    args = parser.parse_args()
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
