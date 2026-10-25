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
    if prefix == 'NativePackage':
        if len(base['profiles']) != 1 or len(base['planning']['daily_plans']) != 1 or len(base['content_selections']) != 1:
            raise ContractError('combined_native_fixture_missing_slice')
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
    args = parser.parse_args()
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
