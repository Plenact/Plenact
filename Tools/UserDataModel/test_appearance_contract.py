"""Model 1.1 appearance working-definition checks; no publication, network or personal data."""
import copy
import unittest
from appearance_contract import CONTRACTS_11, validate_workspace, validate_appearance_record, require_capability, downgrade
from validate_contract import CONTRACTS, ContractError, load_json, validate_instance


class AppearanceModelTests(unittest.TestCase):
    def fixture(self):
        return load_json(CONTRACTS_11 / 'Fixtures/complete-workspace.json')

    def test_composition_keeps_the_base_version_unchanged(self):
        value = self.fixture()
        self.assertTrue(validate_workspace(value))
        self.assertEqual(value['base_workspace']['user_data_model_version'], '1.0')
        self.assertEqual(validate_appearance_record(value['workspace_appearance']), 'workspace_appearance')
        self.assertEqual(validate_appearance_record(value['artwork_library']), 'artwork_library')
        with self.assertRaises(ContractError):
            validate_instance(value, load_json(CONTRACTS / 'workspace-export.schema.json'), 'workspace-export.schema.json')

    def test_global_default_and_explicit_empty_library(self):
        value = self.fixture()
        value['base_workspace']['artwork'] = []
        value['artwork_library']['payload']['artwork_ids'] = []
        self.assertTrue(validate_workspace(value))
        value['artwork_library'] = None
        self.assertTrue(validate_workspace(value))
        value['workspace_appearance']['payload']['week_board_defaults']['subtitle_italic'] = 0
        with self.assertRaises(ContractError):
            validate_workspace(value)

    def test_order_membership_workspace_and_identity(self):
        for mode in ('missing', 'duplicate', 'workspace', 'identity'):
            value = self.fixture()
            library = value['artwork_library']
            if mode == 'missing':
                library['payload']['artwork_ids'] = []
            elif mode == 'duplicate':
                library['payload']['artwork_ids'] *= 2
            elif mode == 'workspace':
                library['workspace_id'] = '92000000-0000-4000-8000-000000000001'
            else:
                library['id'] = value['workspace_appearance']['id']
            with self.assertRaises(ContractError):
                validate_workspace(value)

    def test_old_clients_cannot_strip_the_metadata(self):
        with self.assertRaises(ContractError):
            require_capability(['1.0'])
        with self.assertRaises(ContractError):
            require_capability(['1.1'], ['1.0'])
        require_capability(['1.0', '1.1'], ['1.1'])
        with self.assertRaisesRegex(ContractError, 'appearance_downgrade_would_lose_data'):
            downgrade(self.fixture())
        value = self.fixture()
        value['base_workspace']['artwork'] = []
        value['workspace_appearance'] = None
        value['artwork_library'] = None
        self.assertEqual(downgrade(value), value['base_workspace'])

    def test_base_and_new_records_do_not_mix_in_the_legacy_stream(self):
        from validate_native_preview import validate_records
        with self.assertRaises(ContractError):
            validate_records([self.fixture()['artwork_library']])

    def test_registry_and_all_examples(self):
        from appearance_contract import check_definition
        self.assertEqual(check_definition(), (3, 3))

    def test_authored_order_is_not_sorted_or_repainted(self):
        value = self.fixture()
        original = value['base_workspace']['artwork'][0]
        second = copy.deepcopy(original)
        second['id'] = '91000000-0000-4000-8000-000000000003'
        second['payload']['name'] = 'Second saved look'
        value['base_workspace']['artwork'].append(second)
        expected = [second['id'], original['id']]
        value['artwork_library']['payload']['artwork_ids'] = expected[:]
        before = copy.deepcopy(value['base_workspace'])
        self.assertTrue(validate_workspace(value))
        self.assertEqual(value['artwork_library']['payload']['artwork_ids'], expected)
        self.assertEqual(value['base_workspace'], before)


    def test_pending_local_deletions_retain_records_and_refuse_downgrade(self):
        value = self.fixture()
        card = value['base_workspace']['planning']['content']['cards'][0]['id']
        value['local_card_deletions'] = [card]
        self.assertTrue(validate_workspace(value))
        value['workspace_appearance'] = None
        value['artwork_library'] = None
        with self.assertRaises(ContractError):
            downgrade(value)
        value['local_card_deletions'] = [card, card]
        with self.assertRaises(ContractError):
            validate_workspace(value)
        value['local_card_deletions'] = ['ffffffff-ffff-4fff-8fff-ffffffffffff']
        with self.assertRaises(ContractError):
            validate_workspace(value)
