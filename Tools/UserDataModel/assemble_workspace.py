"""Assemble already-canonical records into a validated portable workspace in memory.

Supported User Data Model versions: 1.0 base, 1.1 working appearance extension.
This pure function does not authenticate owners, bind native migration drafts, discover
personal backups, upload files, or install data. Callers must establish ownership before
supplying canonical account-bound records. Synthetic tests establish no real ownership.
"""
import copy
from appearance_contract import validate_workspace
from validate_contract import ContractError

CONTENT = {'collection': 'collections', 'list': 'lists', 'card': 'cards'}
PLANNING = {
    'calendar_index': 'calendar_indexes', 'calendar_week': 'weeks',
    'daily_plan': 'daily_plans', 'weekly_review': 'weekly_reviews',
    'periodic_review': 'periodic_reviews', 'planning_template': 'templates',
    'template_library': 'template_libraries', 'review_rhythm': 'review_rhythms',
    'asset': 'assets',
}
MANY = {
    'user_profile': 'profiles', 'label_category': 'label_categories',
    'label': 'labels', 'studio_artwork': 'artwork',
    'content_selection': 'content_selections', 'unavailable_reference': 'unavailable_references',
}
ONE = {
    'account': 'account', 'workspace': 'workspace',
    'user_preferences': 'user_preferences', 'studio_settings': 'studio_settings',
    'today_shortcuts': 'today_shortcuts', 'workspace_display_preferences': 'display_preferences',
}
APPEARANCE = {'workspace_appearance', 'artwork_library'}


def assemble(records, external_references, tombstones=()):
    """Route every input exactly once, preserving payloads, array order and input bytes' values.

    Requires one canonical account and workspace; refuses draft/unknown record types,
    duplicate identities and mixed ownership through complete contract validation.
    Does not mint IDs, infer unavailable targets, remove evidence, or rewrite references.
    Media file verification is a separate prerequisite; Asset metadata alone is not proof.
    """
    records = copy.deepcopy(list(records))
    content = {key: [] for key in CONTENT.values()}
    planning = {key: [] for key in PLANNING.values()}
    base = {key: [] for key in MANY.values()}
    base.update({key: None for key in ONE.values()})
    appearance = {key: None for key in APPEARANCE}
    seen = set()
    for record in records:
        if not isinstance(record, dict):
            raise ContractError('invalid_assembly_record')
        kind = record.get('record_type')
        identity = record.get('id')
        if not isinstance(identity, str) or identity in seen:
            raise ContractError('duplicate_or_missing_assembly_identity')
        seen.add(identity)
        if kind in CONTENT:
            content[CONTENT[kind]].append(record)
        elif kind in PLANNING:
            planning[PLANNING[kind]].append(record)
        elif kind in MANY:
            base[MANY[kind]].append(record)
        elif kind in ONE or kind in APPEARANCE:
            target, key = (base, ONE[kind]) if kind in ONE else (appearance, kind)
            if target[key] is not None:
                raise ContractError('duplicate_assembly_singleton')
            target[key] = record
        else:
            raise ContractError('unsupported_assembly_record_type')
    if base['account'] is None or base['workspace'] is None:
        raise ContractError('missing_assembly_ownership')
    workspace = base['workspace']['id']
    version = {'user_data_model_version': '1.0', 'payload_schema_version': 1}
    content.update(version, workspace_id=workspace,
                   external_references=copy.deepcopy(list(external_references)))
    planning.update(version, workspace_id=workspace, account_id=base['account']['id'], content=content)
    base.update(version, planning=planning, tombstones=copy.deepcopy(list(tombstones)))
    result = {'user_data_model_version': '1.1', 'payload_schema_version': 1,
              'base_workspace': base, **appearance}
    validate_workspace(result)
    return result
