"""Write/read a bounded, integrity-checked synthetic workspace and original-file package.

Supported User Data Model versions: 1.0 base; working 1.1 composition.
Package format plenact.synthetic-export-package version 1. Offline test tooling only.
No authentication, live-container discovery, source mutation, extraction or app import.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import zipfile
from appearance_contract import validate_workspace
from bind_synthetic_preview import SYNTHETIC_ACCOUNT
from validate_contract import ContractError, unique_object, finite_float, reject_constant

MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
MAX_ENTRIES = 10000


def encode(value):
    """Encode finite JSON deterministically while preserving strings, nulls and array order."""
    return (json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True,
                       separators=(',', ':')) + '\n').encode('utf-8')


def decode(data):
    """Reject duplicate JSON keys, nonfinite numbers and malformed encoding."""
    try:
        return json.loads(data.decode('utf-8'), object_pairs_hook=unique_object,
                          parse_float=finite_float, parse_constant=reject_constant)
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ContractError('invalid_package_json') from error


def digest(data):
    """Return an exact-byte checksum; this detects corruption, not authenticity."""
    return hashlib.sha256(data).hexdigest()


def validate_binding(binding, originals):
    """Require explicit synthetic ownership and an exact canonical Asset/original inventory."""
    if (not isinstance(binding, dict) or set(binding) != {'format', 'format_version', 'ownership_verified',
            'cloud_upload_allowed', 'workspace_export', 'evidence'}
            or binding['format'] != 'plenact.synthetic-assembly-test'
            or type(binding['format_version']) is not int or binding['format_version'] != 1
            or binding['ownership_verified'] is not False or binding['cloud_upload_allowed'] is not False):
        raise ContractError('synthetic_package_context_required')
    validate_workspace(binding['workspace_export'])
    base = binding['workspace_export']['base_workspace']
    if base['account']['id'] != SYNTHETIC_ACCOUNT:
        raise ContractError('synthetic_package_account_mismatch')
    evidence = binding['evidence']
    if not isinstance(evidence, dict) or set(evidence) != {'settings', 'studio', 'selections', 'assets',
                                                           'appearance', 'replaced_asset_placeholders'}:
        raise ContractError('invalid_package_evidence')
    preview = evidence['assets']
    entries = [] if preview is None else preview['entries']
    sources = {entry['asset_id']: entry for entry in entries}
    assets = base['planning']['assets']
    if len(sources) != len(entries) or set(sources) != {a['id'] for a in assets}:
        raise ContractError('package_asset_inventory_mismatch')
    paths = [e['source_path'] for e in entries]
    if len(paths) != len(set(paths)) or set(paths) != set(originals):
        raise ContractError('package_original_inventory_mismatch')
    for asset in assets:
        entry = sources[asset['id']]
        data = originals[entry['source_path']]
        payload = asset['payload']
        if (not isinstance(data, bytes) or payload['content_state'] != 'described'
                or payload['byte_length'] != str(len(data)) or payload['sha256'] != digest(data)
                or any(payload[key] != entry[key] for key in payload if key != 'account_id')):
            raise ContractError('package_original_integrity_mismatch')
    return entries


def package_bytes(binding, originals):
    """Build a reproducible archive without writing or modifying an input file."""
    entries = validate_binding(binding, originals)
    files = {'Assembly.json': encode(binding)}
    mapping = []
    for entry in entries:
        data = originals[entry['source_path']]
        blob = 'Originals/' + digest(data) + '.bin'
        files[blob] = data
        mapping.append({'asset_id': entry['asset_id'], 'source_path': entry['source_path'], 'blob': blob})
    manifest = {'format': 'plenact.synthetic-export-package', 'format_version': 1,
        'user_data_model_version': '1.1', 'ownership_verified': False, 'cloud_upload_allowed': False,
        'originals': mapping, 'files': [{'path': name, 'byte_length': len(data), 'sha256': digest(data)}
                                     for name, data in sorted(files.items())]}
    files['Manifest.json'] = encode(manifest)
    if (len(files) > MAX_ENTRIES or sum(map(len, files.values())) > MAX_TOTAL
            or any(len(data) > MAX_FILE for data in files.values())):
        raise ContractError('package_size_limit')
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o100600 << 16
            archive.writestr(info, data)
    result = output.getvalue()
    read_package(result)
    return result


def read_package(data):
    """Verify a closed archive in memory; never extract source-controlled paths to disk."""
    if not isinstance(data, bytes) or len(data) > MAX_TOTAL + MAX_ENTRIES * 256:
        raise ContractError('package_size_limit')
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            names = [i.filename for i in infos]
            if (len(infos) > MAX_ENTRIES or len(set(names)) != len(names)
                    or sum(i.file_size for i in infos) > MAX_TOTAL
                    or any(i.file_size > MAX_FILE or i.is_dir() or i.flag_bits & 1
                           or (i.external_attr >> 16) & 0o170000 == 0o120000 for i in infos)):
                raise ContractError('invalid_package_entries')
            allowed = lambda n: n in ('Manifest.json', 'Assembly.json') or (
                n.startswith('Originals/') and n.endswith('.bin') and len(n) == 78
                and all(c in '0123456789abcdef' for c in n[10:-4]))
            if not all(allowed(n) for n in names) or not {'Manifest.json', 'Assembly.json'} <= set(names):
                raise ContractError('invalid_package_path')
            files = {name: archive.read(name) for name in names}
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError) as error:
        raise ContractError('unreadable_export_package') from error
    manifest = decode(files.pop('Manifest.json'))
    if (not isinstance(manifest, dict) or set(manifest) != {'format', 'format_version', 'user_data_model_version',
            'ownership_verified', 'cloud_upload_allowed', 'originals', 'files'}
            or manifest['format'] != 'plenact.synthetic-export-package'
            or type(manifest['format_version']) is not int or manifest['format_version'] != 1
            or manifest['user_data_model_version'] != '1.1' or manifest['ownership_verified'] is not False
            or manifest['cloud_upload_allowed'] is not False or not isinstance(manifest['files'], list)
            or not isinstance(manifest['originals'], list)):
        raise ContractError('invalid_package_manifest')
    expected = [{'path': name, 'byte_length': len(blob), 'sha256': digest(blob)} for name, blob in sorted(files.items())]
    # Compare finite JSON types exactly: a Boolean cannot masquerade as a byte count.
    if encode(manifest['files']) != encode(expected):
        raise ContractError('package_file_integrity_mismatch')
    originals = {}
    ids = set()
    used = {'Assembly.json'}
    for entry in manifest['originals']:
        if (not isinstance(entry, dict) or set(entry) != {'asset_id', 'source_path', 'blob'}
                or not all(isinstance(v, str) for v in entry.values())
                or entry['source_path'] in originals or entry['asset_id'] in ids
                or entry['blob'] not in files or not entry['blob'].startswith('Originals/')):
            raise ContractError('invalid_package_original_mapping')
        blob = files[entry['blob']]
        if entry['blob'] != 'Originals/' + digest(blob) + '.bin':
            raise ContractError('package_blob_name_mismatch')
        originals[entry['source_path']] = blob
        ids.add(entry['asset_id'])
        used.add(entry['blob'])
    if used != set(files):
        raise ContractError('undeclared_package_blob')
    binding = decode(files['Assembly.json'])
    entries = validate_binding(binding, originals)
    if {e['asset_id']: e['source_path'] for e in entries} != {e['asset_id']: e['source_path'] for e in manifest['originals']}:
        raise ContractError('package_mapping_mismatch')
    return binding, originals


def write_package(destination, binding, originals):
    """Publish a new verified archive atomically, refusing any existing destination."""
    data = package_bytes(binding, originals)
    destination = Path(destination).absolute()
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix='.plenact-export-', delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if temporary.read_bytes() != data:
            raise ContractError('package_disk_write_mismatch')
        os.link(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink()
    return digest(data)
