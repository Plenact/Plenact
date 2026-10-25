"""Synthetic complete-export assembly tests. Supported User Data Model versions: 1.0, 1.1."""
import copy
import unittest
from appearance_contract import CONTRACTS_11
from assemble_workspace import assemble, CONTENT, PLANNING, MANY, ONE
from validate_contract import ContractError, load_json


class AssemblyTests(unittest.TestCase):
    def setUp(self):
        """Flatten a published-shape synthetic fixture without inventing personal identities."""
        self.expected = load_json(CONTRACTS_11 / 'Fixtures/complete-workspace.json')
        base = self.expected['base_workspace']
        self.records = [base[key] for key in ONE.values() if base[key] is not None]
        self.records += [r for key in MANY.values() for r in base[key]]
        self.records += [r for key in CONTENT.values() for r in base['planning']['content'][key]]
        self.records += [r for key in PLANNING.values() for r in base['planning'][key]]
        self.records += [self.expected[key] for key in ('workspace_appearance', 'artwork_library')
                         if self.expected[key] is not None]
        self.external = base['planning']['content']['external_references']
        self.tombstones = base['tombstones']

    def test_exact_roundtrip_and_no_input_mutation(self):
        original = copy.deepcopy(self.records)
        result = assemble(self.records, self.external, self.tombstones)
        self.assertEqual(result, self.expected)
        self.assertEqual(self.records, original)
        result['base_workspace']['account']['payload']['display_name'] = 'Changed output'
        self.assertEqual(self.records, original)

    def test_rejects_unknown_drafts_and_duplicate_ids(self):
        for extra in (self.records[0], dict(self.records[0], id='92000000-0000-4000-8000-000000000001', record_type='profile_draft')):
            with self.assertRaises(ContractError):
                assemble(self.records + [extra], self.external, self.tombstones)

    def test_missing_owner_and_mixed_workspace(self):
        with self.assertRaises(ContractError):
            assemble([r for r in self.records if r['record_type'] != 'account'], self.external)
        self.records[0]['workspace_id'] = '92000000-0000-4000-8000-000000000001'
        with self.assertRaises(ContractError):
            assemble(self.records, self.external, self.tombstones)

    def test_rejects_unresolved_artwork_membership(self):
        for record in self.records:
            if record['record_type'] == 'artwork_library':
                record['payload']['artwork_ids'] = []
        with self.assertRaises(ContractError):
            assemble(self.records, self.external, self.tombstones)

    def test_rejects_second_owner_even_with_distinct_identity(self):
        account = next(r for r in self.records if r['record_type'] == 'account')
        extra = dict(account, id='92000000-0000-4000-8000-000000000001')
        with self.assertRaises(ContractError):
            assemble(self.records + [extra], self.external, self.tombstones)


if __name__ == '__main__':
    unittest.main()
