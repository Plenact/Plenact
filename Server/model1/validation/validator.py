"""Private Model 1.0 validator process. JSON stdin only; no network or database access."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'dependencies'))
sys.path.insert(0, str(ROOT / 'Tools/UserDataModel'))
from validate_contract import (CONTRACTS, ContractError, unique_object, reject_constant,
                               finite_float, load_json, validate_instance)

CONTENT = {'collection': 'collections', 'list': 'lists', 'card': 'cards'}
PLANNING = {'calendar_index': 'calendar_indexes', 'calendar_week': 'weeks',
            'daily_plan': 'daily_plans', 'weekly_review': 'weekly_reviews',
            'periodic_review': 'periodic_reviews', 'planning_template': 'templates',
            'template_library': 'template_libraries', 'review_rhythm': 'review_rhythms', 'asset': 'assets'}
MANY = {'user_profile': 'profiles', 'label_category': 'label_categories', 'label': 'labels',
        'studio_artwork': 'artwork', 'content_selection': 'content_selections',
        'unavailable_reference': 'unavailable_references'}
ONE = {'account': 'account', 'workspace': 'workspace', 'user_preferences': 'user_preferences',
       'studio_settings': 'studio_settings', 'today_shortcuts': 'today_shortcuts',
       'workspace_display_preferences': 'display_preferences'}
REFERENCE_TYPES = {'card', 'collection', 'list', 'asset', 'label', 'label_category'}


def decode(raw):
    return json.loads(raw.decode('utf-8'), object_pairs_hook=unique_object,
                      parse_constant=reject_constant, parse_float=finite_float)


def validate_request(raw):
    if len(raw) > 8388608:
        raise ContractError('input_too_large')
    value = decode(raw)
    validate_instance(value, load_json(CONTRACTS / 'transaction-request.schema.json'), 'transaction-request.schema.json')
    return value


def validate_candidate(value):
    account, workspace = value['account_id'], value['workspace_id']
    heads = value['heads']
    content = {key: [] for key in CONTENT.values()}
    planning = {key: [] for key in PLANNING.values()}
    result = {key: [] for key in MANY.values()}
    result.update({key: None for key in ONE.values()})
    tombstones, seen, external, local_content = [], set(), set(), set()
    unavailable_targets = set()
    for head in heads.values():
        kind, identity = head['record_type'], head['record_id']
        if identity in seen or head['workspace_id'] != workspace:
            raise ContractError('duplicate_or_foreign_head')
        seen.add(identity)
        if bool(head['deleted']):
            # Canonical server envelopes, not editable documents, carry tombstones.
            stamp = head['stored_at_utc']
            if 'T' not in stamp:
                stamp = stamp.replace(' ', 'T')
                stamp = stamp.split('.')[0] + '.' + (stamp.split('.')[1] if '.' in stamp else '').ljust(3, '0')[:3] + 'Z'
            tombstone = {'user_data_model_version': '1.0', 'workspace_id': workspace,
                         'record_type': kind, 'record_id': identity, 'epoch': head['epoch'],
                         'revision': str(head['revision']), 'change_sequence': str(head['change_sequence']),
                         'stored_at_utc': stamp, 'stored_by_account_id': head['stored_by_account_id'],
                         'deleted': True, 'document': None, 'asset_content': None}
            validate_instance(tombstone, load_json(CONTRACTS/'server-record.schema.json'), 'server-record.schema.json')
            tombstones.append(tombstone)
            if kind in REFERENCE_TYPES:
                external.add((kind, identity))
                unavailable_targets.add((kind, identity))
            continue
        doc = decode(head['document'].encode('utf-8'))
        if doc['id'] != identity or doc['record_type'] != kind or doc['workspace_id'] != workspace:
            raise ContractError('record_identity_mismatch')
        if kind in CONTENT:
            content[CONTENT[kind]].append(doc)
            local_content.add((kind, identity))
        elif kind in PLANNING:
            planning[PLANNING[kind]].append(doc)
        elif kind in MANY:
            result[MANY[kind]].append(doc)
        elif kind in ONE:
            if result[ONE[kind]] is not None:
                raise ContractError('duplicate_singleton')
            result[ONE[kind]] = doc
        else:
            raise ContractError('unsupported_record_type')
        if kind in {'label', 'label_category', 'asset'}:
            external.add((kind, identity))
        if kind == 'unavailable_reference':
            target = (doc['payload']['target_type'], doc['payload']['target_id'])
            if target[0] in REFERENCE_TYPES:
                external.add(target)
                unavailable_targets.add(target)
    if result['account'] is None or result['workspace'] is None:
        raise ContractError('missing_account_or_workspace')
    if result['account']['id'] != account or result['workspace']['id'] != workspace:
        raise ContractError('owner_mismatch')
    version = {'user_data_model_version': '1.0', 'payload_schema_version': 1}
    content.update(version, workspace_id=workspace,
                   external_references=[{'record_type': k, 'id': i, 'status': 'unavailable' if (k, i) in unavailable_targets else 'external'} for k, i in sorted(external - local_content)])
    planning.update(version, workspace_id=workspace, account_id=account, content=content)
    result.update(version, planning=planning, tombstones=tombstones)
    validate_instance(result, load_json(CONTRACTS/'workspace-export.schema.json'), 'workspace-export.schema.json')
    return result


def main():
    try:
        raw = sys.stdin.buffer.read()
        if sys.argv[1:] == ['request']:
            validate_request(raw)
        elif sys.argv[1:] in (['purge-request'], ['account-deletion-request']):
            name = 'asset-purge-request.schema.json' if sys.argv[1] == 'purge-request' else 'account-deletion-request.schema.json'
            value = decode(raw)
            validate_instance(value, load_json(CONTRACTS/name), name)
        elif sys.argv[1:] == ['upload-commit']:
            value = decode(raw)
            validate_instance(value, load_json(CONTRACTS/'asset-upload-commit.schema.json'), 'asset-upload-commit.schema.json')
        elif sys.argv[1:] == ['upload-request']:
            value = decode(raw)
            validate_instance(value, load_json(CONTRACTS/'asset-upload-request.schema.json'), 'asset-upload-request.schema.json')
        elif sys.argv[1:] == ['offer']:
            value = decode(raw)
            validate_instance(value, load_json(CONTRACTS/'client-capabilities.schema.json'), 'client-capabilities.schema.json')
        elif sys.argv[1:] == ['graph']:
            validate_candidate(decode(raw))
        else:
            raise RuntimeError('Unsupported private operation')
        print('{"valid":true}')
        return 0
    except (ContractError, ValueError, KeyError, TypeError, RecursionError):
        print('{"valid":false,"category":"validation_failed"}')
        return 2
    except Exception:
        print('{"valid":false,"category":"validator_unavailable"}')
        return 3


if __name__ == '__main__':
    sys.exit(main())
