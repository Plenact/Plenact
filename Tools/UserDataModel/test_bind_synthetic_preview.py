"""Offline binding regression tests. Supported User Data Model versions: 1.0, working 1.1."""
import copy
import unittest
from appearance_contract import CONTRACTS_11
from bind_synthetic_preview import bind_preview, SYNTHETIC_ACCOUNT
from validate_contract import ContractError, load_json


class SyntheticBindingTests(unittest.TestCase):
    def setUp(self):
        """Use synthetic label records and effective preference fields from the contract fixture."""
        base = load_json(CONTRACTS_11 / 'Fixtures/complete-workspace.json')['base_workspace']
        self.records = base['label_categories'] + base['labels']
        draft = copy.deepcopy(base['user_preferences'])
        draft['payload'].pop('account_id')
        draft['payload']['preferences']['default_list_id'] = None
        self.settings = {'format': 'plenact.ios-settings-preview', 'format_version': 1,
            'target_user_data_model_version': '1.0', 'account_binding_pending': True,
            'profile': None, 'preferences': {'id': draft['id'], 'payload': draft['payload']},
            'preferences_origin': 'saved_planning_preferences', 'defaulted_preference_fields': [],
            'defaulted_profile_fields': [], 'profile_preferences_shadowed': False,
            'unresolved_default_list_id': None, 'source_precision': [], 'issues': [], 'ready_for_binding': True}
        self.selections = {'format': 'plenact.ios-selection-preview', 'format_version': 1,
            'target_user_data_model_version': '1.0', 'account_binding_pending': True,
            'entries': [], 'issues': []}

    def test_settings_exact_payload_retry_and_input_independence(self):
        original = copy.deepcopy(self.settings)
        result = bind_preview(self.records, originals={}, settings=self.settings, selections=self.selections)
        self.assertFalse(result['ownership_verified'])
        self.assertFalse(result['cloud_upload_allowed'])
        base = result['workspace_export']['base_workspace']
        self.assertEqual(base['user_preferences']['payload'],
                         dict(self.settings['preferences']['payload'], account_id=SYNTHETIC_ACCOUNT))
        self.assertEqual(result, bind_preview(self.records, originals={}, settings=self.settings, selections=self.selections))
        result['evidence']['settings']['issues'].append('Changed result')
        self.assertEqual(self.settings, original)

    def test_settings_pending_review_blocks(self):
        self.settings.update(issues=['default_list_owner_requires_review'], ready_for_binding=False,
                             unresolved_default_list_id=99)
        with self.assertRaises(ContractError):
            bind_preview(self.records, originals={}, settings=self.settings)

    def test_unresolved_selection_never_becomes_false_or_zero(self):
        self.selections['entries'] = [{'source_collection_id': 'old-owner', 'source_owner_scope': None,
            'source_card_id': 1, 'card_id': None, 'bookmarked': None, 'importance': 3}]
        with self.assertRaises(ContractError):
            bind_preview(self.records, originals={}, selections=self.selections)

    def test_uninventoried_original_blocks(self):
        with self.assertRaises(ContractError):
            bind_preview(self.records, originals={'Documents/CardAttachments/file.bin': b'original'})

    def test_draft_cannot_override_account(self):
        self.settings['preferences']['payload']['account_id'] = '30000000-0000-4000-8000-000000000001'
        with self.assertRaises(ContractError):
            bind_preview(self.records, originals={}, settings=self.settings)


if __name__ == '__main__':
    unittest.main()
