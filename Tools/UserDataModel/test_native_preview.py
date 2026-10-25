"""Model 1.0 native-preview independent checker regression coverage; synthetic files only."""

import copy
import unittest
from validate_contract import CONTRACTS, ContractError, load_json
from validate_native_preview import validate_records


class NativePreviewValidatorTests(unittest.TestCase):
    def records(self):
        """Use frozen published category/label/display fixtures without app data."""
        return [load_json(CONTRACTS / "Fixtures" / name) for name in (
            "label-category-definition.json", "label-definition.json", "display-preferences-definition.json")]

    def test_shared_contract_values_validate(self):
        self.assertEqual(validate_records(self.records()), 3)
        self.assertEqual(validate_records([]), 0)

    def test_duplicate_identity_and_missing_category_rejected(self):
        records = self.records()
        with self.assertRaises(ContractError):
            validate_records(records + records[:1])
        with self.assertRaises(ContractError):
            validate_records(records[1:])

    def test_false_is_not_numeric_zero(self):
        records = self.records()
        records[2]["payload"]["card_covers_enabled"] = 0
        with self.assertRaises(ContractError):
            validate_records(records)

    def test_unsupported_slice_and_workspace_mismatch_rejected(self):
        records = self.records()
        with self.assertRaises(ContractError):
            validate_records([load_json(CONTRACTS / "Fixtures/account-definition.json")])
        records[2]["workspace_id"] = "90000000-0000-4000-8000-000000000009"
        with self.assertRaises(ContractError):
            validate_records(records)
