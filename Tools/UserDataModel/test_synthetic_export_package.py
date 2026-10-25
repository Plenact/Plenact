"""Package/reopen and corruption tests. Supported User Data Model versions: 1.0, working 1.1."""
import copy
import io
import tempfile
from pathlib import Path
import unittest
import zipfile
from bind_synthetic_preview import bind_preview
from synthetic_export_package import package_bytes, read_package, write_package, encode, decode, digest
import test_bind_synthetic_preview as binding_tests
from validate_contract import ContractError


class ExportPackageTests(unittest.TestCase):
    def setUp(self):
        """Build synthetic preferences plus two source paths sharing exact original bytes."""
        source = binding_tests.SyntheticBindingTests()
        source.setUp()
        self.originals = {'Documents/CardAttachments/one.bin': b'original\x00\xff',
                          'Documents/CardAttachments/two.bin': b'original\x00\xff'}
        entries = []
        for index, (path, data) in enumerate(self.originals.items(), 1):
            entries.append({'asset_id': f'90000000-0000-4000-8000-{index:012d}', 'source_path': path,
                'kind': 'binary', 'mime_type': 'application/octet-stream', 'original_name': path.split('/')[-1],
                'content_state': 'described', 'byte_length': str(len(data)), 'sha256': digest(data),
                'source_format': None, 'derived_from_asset_id': None, 'source_created_at_utc': None,
                'attribution': None, 'type_evidence': 'unknown', 'references': []})
        assets = {'format': 'plenact.ios-asset-preview', 'format_version': 1,
            'target_user_data_model_version': '1.0', 'account_binding_pending': True,
            'entries': entries, 'issues': []}
        self.binding = bind_preview(source.records, originals=self.originals, settings=source.settings, assets=assets)

    def rewrite(self, data, change):
        """Rewrite archive members with valid ZIP checksums to exercise package-level validation."""
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            members = {name: archive.read(name) for name in archive.namelist()}
        change(members)
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            for name, value in members.items():
                archive.writestr(name, value)
        return output.getvalue()

    def test_exact_reopen_deterministic_and_deduplicated(self):
        before = copy.deepcopy((self.binding, self.originals))
        data = package_bytes(self.binding, self.originals)
        self.assertEqual(read_package(data), before)
        self.assertEqual(data, package_bytes(self.binding, self.originals))
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            self.assertEqual(len([n for n in archive.namelist() if n.startswith('Originals/')]), 1)
        self.assertEqual((self.binding, self.originals), before)

    def test_corruption_of_original_or_assembly_rejected(self):
        data = package_bytes(self.binding, self.originals)
        for name in ('Assembly.json', 'Originals/' + digest(next(iter(self.originals.values()))) + '.bin'):
            changed = self.rewrite(data, lambda files: files.update({name: files[name] + b'changed'}))
            with self.assertRaises(ContractError):
                read_package(changed)

    def test_undeclared_unsafe_and_missing_members_rejected(self):
        data = package_bytes(self.binding, self.originals)
        for change in (lambda files: files.update({'../escape': b'bad'}),
                       lambda files: files.pop('Assembly.json'),
                       lambda files: files.update({'Originals/' + '0' * 64 + '.bin': b'extra'})):
            with self.assertRaises(ContractError):
                read_package(self.rewrite(data, change))

    def test_unknown_version_and_false_numeric_length_rejected(self):
        data = package_bytes(self.binding, self.originals)
        for mode in ('version', 'length'):
            def change(files):
                manifest = decode(files['Manifest.json'])
                if mode == 'version':
                    manifest['format_version'] = 2
                else:
                    manifest['files'][0]['byte_length'] = True
                files['Manifest.json'] = encode(manifest)
            with self.assertRaises(ContractError):
                read_package(self.rewrite(data, change))

    def test_mappings_cannot_drop_originals_or_change_owner(self):
        with self.assertRaises(ContractError):
            package_bytes(self.binding, {})
        self.binding['ownership_verified'] = True
        with self.assertRaises(ContractError):
            package_bytes(self.binding, self.originals)

    def test_atomic_write_refuses_overwrite_and_retains_source(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'workspace.zip'
            write_package(path, self.binding, self.originals)
            before = path.read_bytes()
            with self.assertRaises(FileExistsError):
                write_package(path, self.binding, self.originals)
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(list(Path(directory).iterdir()), [path])
            self.assertEqual(read_package(before), (self.binding, self.originals))

    def test_duplicate_member_rejected(self):
        data = package_bytes(self.binding, self.originals)
        output = io.BytesIO(data)
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(output, 'a') as archive:
                archive.writestr('Assembly.json', b'{}')
        with self.assertRaises(ContractError):
            read_package(output.getvalue())


if __name__ == '__main__':
    unittest.main()
