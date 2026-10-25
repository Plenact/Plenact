"""Additive Model 1.1 appearance definitions over immutable Model 1.0.

Supported User Data Model versions: 1.0 base and 1.1 composition. Working definition,
not a published release or deployed sync API. Never strips required appearance metadata.
"""
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Resource
from validate_contract import CONTRACTS, ContractError, load_json, schema_registry, validate_instance

CONTRACTS_11 = CONTRACTS.parent / '1.1'
KINDS = {'workspace_appearance': 'workspace-appearance', 'artwork_library': 'artwork-library'}


def registry():
    """Resolve both explicit version namespaces locally without network retrieval."""
    result = schema_registry()
    for path in CONTRACTS_11.glob('*.schema.json'):
        value = load_json(path)
        result = result.with_resource(value['$id'], Resource.from_contents(value))
    return result


def validate_appearance_record(record):
    """Check a new 1.1 record shape; base records keep their own 1.0 version."""
    if not isinstance(record, dict) or record.get('record_type') not in KINDS:
        raise ContractError('unsupported_appearance_record')
    schema = load_json(CONTRACTS_11 / (KINDS[record['record_type']] + '.schema.json'))
    if list(Draft202012Validator(schema, registry=registry(), format_checker=FormatChecker()).iter_errors(record)):
        raise ContractError('appearance_schema_error')
    return record['record_type']


def validate_links(appearance, library, records, workspace, tombstones=()):
    """Require exact artwork membership, one workspace, unique IDs and declared background Assets."""
    ids = {r['id'] for r in records} | {r['record_id'] for r in tombstones}
    targets = {r['payload']['target_id'] for r in records if r['record_type'] == 'unavailable_reference'
               and r['payload']['target_type'] == 'asset'} | {r['id'] for r in records if r['record_type'] == 'asset'} | {r['record_id'] for r in tombstones if r['record_type'] == 'asset'}
    new_ids = set()
    for record in (appearance, library):
        if record is None:
            continue
        validate_appearance_record(record)
        if record['workspace_id'] != workspace or record['id'] in ids or record['id'] in new_ids:
            raise ContractError('appearance_workspace_or_identity_mismatch')
        new_ids.add(record['id'])
    artworks = {r['id'] for r in records if r['record_type'] == 'studio_artwork'}
    if library is None:
        if artworks:
            raise ContractError('missing_artwork_library')
    elif library['record_type'] != 'artwork_library' or set(library['payload']['artwork_ids']) != artworks:
        raise ContractError('artwork_library_membership_mismatch')
    if appearance is not None:
        if appearance['record_type'] != 'workspace_appearance':
            raise ContractError('invalid_workspace_appearance_type')
        def walk(value):
            if isinstance(value, dict):
                for key, child in value.items():
                    if key == 'photo_asset_id' and child is not None and child not in targets:
                        raise ContractError('unresolved_appearance_asset')
                    walk(child)
            elif isinstance(value, list):
                for child in value:
                    walk(child)
        walk(appearance['payload'])


def validate_workspace(value):
    """Validate an explicit 1.1 export containing an unchanged complete 1.0 base workspace."""
    schema = load_json(CONTRACTS_11 / 'workspace-export.schema.json')
    if list(Draft202012Validator(schema, registry=registry(), format_checker=FormatChecker()).iter_errors(value)):
        raise ContractError('appearance_workspace_schema_error')
    base = value['base_workspace']
    validate_instance(base, load_json(CONTRACTS / 'workspace-export.schema.json'), 'workspace-export.schema.json')
    def documents(value):
        if isinstance(value, dict):
            if 'record_type' in value and 'workspace_id' in value and 'payload' in value:
                yield value
            else:
                for child in value.values():
                    yield from documents(child)
        elif isinstance(value, list):
            for child in value:
                yield from documents(child)
    validate_links(value['workspace_appearance'], value['artwork_library'], list(documents(base)), base['planning']['workspace_id'], base['tombstones'])
    retained_cards = {r['id'] for r in base['planning']['content']['cards']}
    if not set(value.get('local_card_deletions', [])).issubset(retained_cards):
        raise ContractError('unresolved_local_card_deletion')
    return True


def require_capability(read_versions, write_versions=None):
    """Gate the composite export on explicit 1.1 support; never infer support from app version."""
    if '1.1' not in read_versions or write_versions is not None and '1.1' not in write_versions:
        raise ContractError('model_1_1_capability_required')


def downgrade(value):
    """Refuse metadata loss; a metadata-free composition alone may yield its unchanged base."""
    validate_workspace(value)
    if value['workspace_appearance'] is not None or value['artwork_library'] is not None or value.get('local_card_deletions'):
        raise ContractError('appearance_downgrade_would_lose_data')
    return value['base_workspace']


def check_definition():
    """Check every working 1.1 resource and its versioned examples without publishing anything."""
    import json
    resources = {}
    for path in CONTRACTS_11.glob('*.schema.json'):
        schema = load_json(path)
        Draft202012Validator.check_schema(schema)
        resources[path.name.replace('.schema.json', '')] = schema['$id']
    definition = load_json(CONTRACTS_11 / 'registry.json')
    if (definition['resources'] != resources or definition['record_types'] != KINDS
            or definition['supported_user_data_model_versions'] != ['1.1']
            or definition['base_user_data_model_versions'] != ['1.0']
            or definition['specification_status'] != 'working_definition'):
        raise ContractError('invalid_model_1_1_registry')
    workspace = load_json(CONTRACTS_11 / 'Fixtures/complete-workspace.json')
    validate_workspace(workspace)
    for filename, field in (('global-week-defaults.json', 'workspace_appearance'),
                            ('ordered-artwork-library.json', 'artwork_library')):
        example = load_json(CONTRACTS_11 / 'Fixtures' / filename)
        validate_appearance_record(example)
        if example != workspace[field]:
            raise ContractError('appearance_fixture_mismatch')
    return len(resources), 3


if __name__ == '__main__':
    print('Validated Model 1.1 working definition (schemas, examples):', check_definition())
