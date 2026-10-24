"""Regression checks for Model 1.0 planning/assets, final specification.

Supported User Data Model versions: 1.0. Local contract tests only; not live sync.
"""

from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

from planning_contract import validate_asset_bytes
from validate_contract import (CONTRACTS, ContractError, load_json, validate_instance)


class PlanningContractTests(unittest.TestCase):
    """Protect historical snapshots, dated ownership and opaque media preservation."""

    def validate(self, value, name):
        """Apply the named repository schema and its associated semantic rules."""
        validate_instance(value, load_json(CONTRACTS / name), name)

    def test_historical_text_is_not_replaced_with_current_card_content(self):
        """Historical snapshots can differ from live titles and remain valid."""
        graph = load_json(CONTRACTS / "Fixtures/complete-planning-graph.json")
        priority = graph["daily_plans"][0]["payload"]["priorities"][0]
        self.assertNotEqual(priority["title"], graph["content"]["cards"][0]["payload"]["title"])
        self.validate(graph, "planning-graph.schema.json")

    def test_starting_and_current_objective_share_identity_but_not_progress(self):
        """A review retains both objective snapshots without treating them as duplicates."""
        value = load_json(CONTRACTS / "Fixtures/periodic-review-snapshots.json")
        start = value["payload"]["starting_objectives"][0]
        current = value["payload"]["objectives"][0]
        self.assertEqual(start["id"], current["id"])
        self.assertNotEqual(start["progress"], current["progress"])
        self.validate(value, "periodic-review.schema.json")

    def test_nullable_and_empty_history_remain_distinct(self):
        """Do not turn an absent legacy history into an explicitly empty history."""
        missing = load_json(CONTRACTS / "Fixtures/daily-plan-null-history.json")
        empty = load_json(CONTRACTS / "Fixtures/daily-plan-empty-history.json")
        self.assertIsNone(missing["payload"]["check_ins"])
        self.assertEqual(empty["payload"]["check_ins"], [])
        self.validate(missing, "daily-plan.schema.json")
        self.validate(empty, "daily-plan.schema.json")

    def test_unknown_plan_field_blocks_writes(self):
        """An older writer cannot silently discard a newer reflection field."""
        value = load_json(CONTRACTS / "Fixtures/daily-plan-history.json")
        value["payload"]["future_reflection"] = "Keep me"
        with self.assertRaisesRegex(ContractError, "schema_error"):
            self.validate(value, "daily-plan.schema.json")

    def test_week_retains_local_dates_across_daylight_saving(self):
        """Seven-day membership is calendar-day based rather than elapsed UTC hours."""
        value = load_json(CONTRACTS / "Fixtures/calendar-week.json")
        value["payload"]["start_date"] = "2026-11-01"
        value["payload"]["first_weekday"] = 1
        value["payload"]["day_lists"][0]["date"] = "2026-11-07"
        self.validate(value, "calendar-week.schema.json")
        value["payload"]["day_lists"][0]["date"] = "2026-11-08"
        with self.assertRaisesRegex(ContractError, "week_day_outside_range"):
            self.validate(value, "calendar-week.schema.json")

    def test_calendar_week_at_upper_date_bound_does_not_overflow(self):
        """Validate partial end-of-range Weeks using date differences, not overflowing addition."""
        from datetime import date
        value = load_json(CONTRACTS / "Fixtures/calendar-week.json")
        value["payload"]["start_date"] = "9999-12-31"
        value["payload"]["first_weekday"] = date(9999, 12, 31).isoweekday() % 7 + 1
        value["payload"]["day_lists"][0]["date"] = "9999-12-31"
        self.validate(value, "calendar-week.schema.json")

    def test_cross_week_checklist_link_cannot_resolve_to_two_cards(self):
        """Copied legacy checklist IDs require disambiguation before portable linking."""
        graph = load_json(CONTRACTS / "Fixtures/complete-planning-graph.json")
        duplicate = deepcopy(graph["content"]["cards"][0])
        duplicate["id"] = "90000000-0000-4000-8000-000000000001"
        graph["content"]["cards"].append(duplicate)
        graph["content"]["lists"][0]["payload"]["card_ids"].append(duplicate["id"])
        with self.assertRaisesRegex(ContractError, "ambiguous_checklist_reference"):
            self.validate(graph, "planning-graph.schema.json")

    def test_template_requires_independent_owner_and_library_membership(self):
        """Templates cannot disappear from their index while their content remains."""
        graph = load_json(CONTRACTS / "Fixtures/complete-planning-graph.json")
        graph["template_libraries"] = []
        with self.assertRaisesRegex(ContractError, "template_library_membership_mismatch"):
            self.validate(graph, "planning-graph.schema.json")

    def test_missing_asset_hash_is_not_an_empty_file(self):
        """Legacy unavailability is distinct from a described zero-byte asset."""
        value = load_json(CONTRACTS / "Fixtures/asset-unavailable.json")
        self.assertIsNone(value["payload"]["byte_length"])
        self.validate(value, "asset.schema.json")
        value["payload"]["byte_length"] = "0"
        with self.assertRaisesRegex(ContractError, "invalid_asset_metadata"):
            self.validate(value, "asset.schema.json")

    def test_asset_size_survives_above_double_integer_precision(self):
        """Byte length is a decimal string, never a lossy floating-point counter."""
        value = load_json(CONTRACTS / "Fixtures/asset-large-byte-count.json")
        self.assertEqual(value["payload"]["byte_length"], "9007199254740993")
        self.validate(value, "asset.schema.json")

    def test_unresolved_asset_derivation_is_rejected(self):
        """An original or preview reference must resolve or have explicit evidence."""
        graph = load_json(CONTRACTS / "Fixtures/complete-planning-graph.json")
        graph["assets"][0]["payload"]["derived_from_asset_id"] = "90000000-0000-4000-8000-000000000001"
        with self.assertRaisesRegex(ContractError, "unresolved_asset_reference"):
            self.validate(graph, "planning-graph.schema.json")

    def test_asset_names_are_not_local_paths(self):
        """Original display names must not become device-specific filesystem locators."""
        value = load_json(CONTRACTS / "Fixtures/asset-image.json")
        for name in ("/Documents/photo.png", "C:\\private\\photo.png", ".."):
            with self.subTest(name=name):
                value["payload"]["original_name"] = name
                with self.assertRaisesRegex(ContractError, "invalid_asset_name"):
                    self.validate(value, "asset.schema.json")

    def test_fixture_bytes_fail_when_truncated_or_replaced(self):
        """Metadata alone cannot prove that a downloaded asset has the right bytes."""
        fixture = load_json(CONTRACTS / "Fixtures/asset-image.json")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "asset.json").write_text(json.dumps(fixture))
            (root / "bytes.bin").write_bytes(b"wrong bytes")
            manifest = {"asset_byte_cases": [{"asset_fixture": "asset.json", "file": "bytes.bin"}]}
            with self.assertRaisesRegex(ContractError, "asset_integrity_mismatch"):
                validate_asset_bytes(root, manifest, load_json, ContractError)
            manifest["asset_byte_cases"][0]["file"] = "../outside.bin"
            with self.assertRaisesRegex(ContractError, "invalid_asset_fixture_path"):
                validate_asset_bytes(root, manifest, load_json, ContractError)


if __name__ == "__main__":
    unittest.main()
