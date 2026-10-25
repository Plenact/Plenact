"""Bind validated native drafts to an explicitly synthetic, offline assembly context.

Supported User Data Model versions: 1.0 base and working 1.1 appearance composition.
No production ownership, authentication, network access, filesystem import or app writes.
The returned evidence retains drafts and records replaced by verified Asset metadata.
"""
import copy
import uuid
from assemble_workspace import assemble
from validate_contract import ContractError
from validate_native_preview import (
    validate_records, validate_selection_preview, validate_asset_preview,
    validate_settings_preview, validate_studio_preview, validate_appearance_preview,
)

SYNTHETIC_ACCOUNT = 'f0000000-0000-4000-8000-000000000001'


def bind_preview(records, *, originals, settings=None, studio=None, selections=None,
                 assets=None, appearance=None):
    """Create a test-only complete export without modifying preview identities or originals.

    Every supplied draft is validated before use; review issues and uncertain selections
    block assembly. No missing bookmark/importance value is coerced into a default.
    Missing original files block this first recovery-ready path. Asset placeholders are
    replaced only for IDs backed by verified bytes; replacements survive in evidence.
    This does not certify that omitted draft categories were absent in a source backup.
    """
    records = copy.deepcopy(records)
    validate_records(records)
    workspaces = {r['workspace_id'] for r in records}
    if len(workspaces) != 1:
        raise ContractError('synthetic_binding_requires_one_preview_workspace')
    workspace = next(iter(workspaces))
    extra = []
    if settings is not None:
        validate_settings_preview(settings, records)
        if not settings['ready_for_binding']:
            raise ContractError('settings_review_required')
        if settings['profile'] is not None:
            extra.append({'record_type': 'user_profile_preview', **settings['profile']})
    if studio is not None:
        extra += validate_studio_preview(studio, records, appearance)
        if not studio['canonical_mapping_complete']:
            raise ContractError('studio_review_required')
    elif appearance is not None:
        extra += validate_appearance_preview(appearance, records)
    if selections is not None:
        validate_selection_preview(selections, records)
        if selections['issues'] or any(e[k] is None for e in selections['entries']
                                       for k in ('card_id', 'bookmarked', 'importance')):
            raise ContractError('selection_review_required')
    if assets is not None:
        validate_asset_preview(assets, records, originals, extra)
        if assets['issues'] or any(e['content_state'] != 'described' for e in assets['entries']):
            raise ContractError('asset_review_required')
    elif originals:
        raise ContractError('asset_preview_required')
    else:
        # Empty evidence still proves no emitted field silently refers to an unverified file.
        validate_asset_preview({'format': 'plenact.ios-asset-preview', 'format_version': 1,
            'target_user_data_model_version': '1.0', 'account_binding_pending': True,
            'entries': [], 'issues': []}, records, originals, extra)

    def document(kind, identity, payload):
        return {'user_data_model_version': '1.0', 'payload_schema_version': 1,
                'record_type': kind, 'id': identity, 'workspace_id': workspace,
                'payload': copy.deepcopy(payload)}

    def owned(kind, draft):
        return document(kind, draft['id'], dict(draft['payload'], account_id=SYNTHETIC_ACCOUNT))

    bound = []
    if settings is not None:
        bound.append(owned('user_preferences', settings['preferences']))
        if settings['profile'] is not None:
            bound.append(owned('user_profile', settings['profile']))
    if studio is not None and studio['studio_settings'] is not None:
        bound.append(owned('studio_settings', studio['studio_settings']))
    if selections is not None:
        for entry in selections['entries']:
            identity = str(uuid.uuid5(uuid.UUID(SYNTHETIC_ACCOUNT), 'content_selection:' + entry['card_id']))
            bound.append(document('content_selection', identity, {
                'account_id': SYNTHETIC_ACCOUNT, 'card_id': entry['card_id'],
                'bookmarked': entry['bookmarked'], 'importance': entry['importance']}))
    if assets is not None:
        for entry in assets['entries']:
            payload = {k: entry[k] for k in ('kind', 'mime_type', 'original_name', 'content_state',
                'byte_length', 'sha256', 'source_format', 'derived_from_asset_id',
                'source_created_at_utc', 'attribution')}
            bound.append(document('asset', entry['asset_id'], dict(payload, account_id=SYNTHETIC_ACCOUNT)))
    asset_ids = {r['id'] for r in bound if r['record_type'] == 'asset'}
    replaced = [r for r in records if r['record_type'] == 'unavailable_reference'
                and r['payload']['target_type'] == 'asset' and r['payload']['target_id'] in asset_ids]
    records = [r for r in records if r not in replaced]
    bound += [document('account', SYNTHETIC_ACCOUNT, {'display_name': 'Synthetic migration test owner',
        'account_kind': 'personal', 'created_at_utc': '2026-10-25T00:00:00.000Z'}),
        document('workspace', workspace, {'owner_account_id': SYNTHETIC_ACCOUNT,
        'display_name': 'Synthetic migration test workspace', 'calendar_system': 'gregorian', 'state': 'active'})]
    if appearance is not None:
        bound += [appearance[k] for k in ('workspace_appearance', 'artwork_library') if appearance[k] is not None]
    external = [{'record_type': r['record_type'], 'id': r['id'], 'status': 'external'}
                for r in records + bound if r['record_type'] in ('label', 'label_category', 'asset')]
    external += [{'record_type': r['payload']['target_type'], 'id': r['payload']['target_id'], 'status': 'unavailable'}
                 for r in records if r['record_type'] == 'unavailable_reference']
    result = assemble(records + bound, external)
    return {'format': 'plenact.synthetic-assembly-test', 'format_version': 1,
            'ownership_verified': False, 'cloud_upload_allowed': False,
            'workspace_export': result,
            'evidence': copy.deepcopy({'settings': settings, 'studio': studio, 'selections': selections,
                'assets': assets, 'appearance': appearance, 'replaced_asset_placeholders': replaced})}
