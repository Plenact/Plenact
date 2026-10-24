"""Model 1.0 final specification tooling tests; local validation only, not sync support."""

from copy import deepcopy
import re
from pathlib import Path
import tempfile
import unittest

from validate_contract import (CONTRACTS, ContractError, compatibility, load_json,
                               equivalent_json, record_capabilities, run_fixtures, validate_instance)


class ContractTests(unittest.TestCase):
    """Protect portable decoding, boundary cases, and fixture expectations."""

    def test_shared_fixtures(self):
        """Exercise positive, negative, timezone, and negotiation cases together."""
        self.assertGreaterEqual(run_fixtures()[1], 154)

    def test_card_coding_keys_have_explicit_transport_mapping(self):
        """Fail if a new persisted Card field is absent from the reviewed mapping."""
        source = (CONTRACTS.parents[3] / "Src/Models/KanbanCard.swift").read_text()
        keys = set(re.findall(r"case (\w+)", source.split("private enum CodingKeys: String, CodingKey")[1].split("    }")[0]))
        mapping = {
            "id": None, "listTitle": None, "word": "title", "editHistory": "edit_history",
            "isDivider": "is_divider", "isTitleChecked": "completed", "editingLocked": "editing_locked",
            "members": "members", "labelIDs": "label_ids", "startDate": "start", "location": "location",
            "dueDate": "due", "createdAt": "source_created_at_utc", "descriptionOverride": "description_override",
            "startDateKind": "start_kind", "dueDateKind": "due_kind", "showsDueDateInList": "shows_due_date_in_list",
            "sectionLayout": "section_layout", "subtitleOverride": "subtitle_override", "checklists": "checklists",
            "showsReactionsInPreviews": "shows_reactions_in_previews", "reactions": "reactions", "comments": "comments",
            "attachments": "attachments", "coverAttachmentID": "cover_attachment_id", "appearance": "appearance",
            "dismissedActivityIDs": "dismissed_activity_ids", "listDisplayFormat": "display_format",
            "itemPresentation": "presentation"
        }
        self.assertEqual(keys, set(mapping))
        payload = load_json(CONTRACTS / "card.schema.json")["properties"]["payload"]["properties"]
        self.assertEqual(set(payload), {value for value in mapping.values() if value} | {"list_id", "archived"})

    def test_json_equivalence_keeps_null_false_and_order_distinct(self):
        """Do not confuse false with numeric zero or reorder authored arrays."""
        self.assertFalse(equivalent_json({"flag": False}, {"flag": 0}))
        self.assertFalse(equivalent_json({"subtitle": None}, {"subtitle": ""}))
        self.assertFalse(equivalent_json([1, 2], [2, 1]))
        self.assertTrue(equivalent_json({"zoom": 1}, {"zoom": 1.0}))

    def test_graph_references_require_explicit_external_evidence(self):
        """A syntactically valid UUID is insufficient for linked content or asset ownership."""
        graph = load_json(CONTRACTS / "Fixtures/complete-content-graph.json")
        schema = load_json(CONTRACTS / "content-graph.schema.json")
        for record_type, error in [("asset", "unresolved_asset_reference"),
                                   ("label", "unresolved_label_reference")]:
            with self.subTest(record_type=record_type):
                candidate = deepcopy(graph)
                candidate["external_references"] = [r for r in graph["external_references"] if r["record_type"] != record_type]
                with self.assertRaisesRegex(ContractError, error):
                    validate_instance(candidate, schema, "content-graph.schema.json")

    def test_parent_membership_must_agree_in_both_directions(self):
        """Prevent orphan Lists and wrong parent references even when all IDs are UUIDs."""
        graph = load_json(CONTRACTS / "Fixtures/complete-content-graph.json")
        schema = load_json(CONTRACTS / "content-graph.schema.json")
        graph["collections"][0]["payload"]["list_ids"] = []
        graph["collections"][0]["payload"]["preferred_focused_list_id"] = None
        with self.assertRaisesRegex(ContractError, "list_membership_mismatch"):
            validate_instance(graph, schema, "content-graph.schema.json")

    def test_json_parser_rejects_ambiguous_and_nonportable_values(self):
        """Reject duplicate keys, nonfinite numbers, oversized input, and bad UTF-8."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.json"
            for data, error in [(b'{"id":1,"id":2}', "duplicate_key"),
                                (b'{"n":NaN}', "nonfinite_number"),
                                (b'{"n":1e999}', "nonfinite_number"),
                                (b' ' * 8_388_609, "input_too_large")]:
                with self.subTest(error=error):
                    path.write_bytes(data)
                    with self.assertRaisesRegex(ContractError, error):
                        load_json(path)
            path.write_bytes(b'\xff')
            with self.assertRaises(UnicodeDecodeError):
                load_json(path)

    def test_record_write_support_requires_read_support(self):
        """Block a client that advertises writing a type it cannot read."""
        value = load_json(CONTRACTS / "Fixtures/ios-capabilities.json")
        value["write_record_types"].append("unknown_future_type")
        schema = load_json(CONTRACTS / "client-capabilities.schema.json")
        with self.assertRaisesRegex(ContractError, "write_type_without_read"):
            validate_instance(value, schema, "client-capabilities.schema.json")

    def test_unknown_record_type_does_not_inherit_model_write_access(self):
        """Block an unknown record even when the overall model version is supported."""
        value = load_json(CONTRACTS / "Fixtures/ios-capabilities.json")
        self.assertEqual(record_capabilities(value, "future_record"),
                         {"can_read": False, "can_write": False})
        self.assertEqual(record_capabilities(value, "content_selection"),
                         {"can_read": True, "can_write": True})

    def test_explicit_model_support_beats_app_version(self):
        """A larger application version alone never enables incompatible model writes."""
        value = load_json(CONTRACTS / "Fixtures/newer-client-no-fallback.json")
        value["application_version"] = "999.0"
        self.assertEqual(compatibility(value), {"can_read": False, "can_write": False})

    def test_timezone_database_is_not_silently_substituted(self):
        """Preserve the declared rules version rather than using an arbitrary host copy."""
        value = load_json(CONTRACTS / "Fixtures/timed-chicago.json")
        value["tzdb_version"] = "2024a"
        schema = load_json(CONTRACTS / "date-value.schema.json")
        with self.assertRaisesRegex(ContractError, "unsupported_tzdb"):
            validate_instance(value, schema, "date-value.schema.json")

    def test_repeated_occurrence_cannot_be_applied_to_unique_time(self):
        """Require an explicit unique marker outside a repeated wall-clock interval."""
        value = load_json(CONTRACTS / "Fixtures/timed-chicago.json")
        value["occurrence"] = "first"
        schema = load_json(CONTRACTS / "date-value.schema.json")
        with self.assertRaisesRegex(ContractError, "unexpected_occurrence"):
            validate_instance(value, schema, "date-value.schema.json")


if __name__ == "__main__":
    unittest.main()
