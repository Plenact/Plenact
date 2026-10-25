"""Model 1.0 documentation follow-up: links and synthetic SQL/JSON examples, never live SQL."""

import json
import re
import unittest
from pathlib import Path

from validate_contract import ROOT, CONTRACTS, load_json, validate_instance


EXAMPLES = ROOT / "Doc/User-Data-Model/Doc/Examples"


class DocumentationExampleTests(unittest.TestCase):
    def test_document_links_resolve(self):
        """All Doc Markdown local file links resolve after the historical-path reconciliation."""
        for path in (ROOT / "Doc").rglob("*.md"):
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text()):
                if "://" in target or target.startswith(("#", "mailto:")):
                    continue
                self.assertTrue((path.parent / target.split("#")[0]).exists(), f"{path}: {target}")

    def test_versioned_json_examples(self):
        """Example values pass the same final structural and semantic contract as application data."""
        for filename, schema_name in (("complete-workspace.json", "workspace-export.schema.json"),
                                      ("card-server-record.json", "server-record.schema.json")):
            validate_instance(load_json(EXAMPLES / "1.0" / filename), load_json(CONTRACTS / schema_name), schema_name)

    def test_sql_seed_preserves_complete_workspace_records(self):
        """Decode illustrative SQL literals and compare every document/frame to the valid source export."""
        workspace = load_json(EXAMPLES / "1.0/complete-workspace.json")
        documents = {}
        def collect(value):
            if isinstance(value, dict):
                if all(k in value for k in ("record_type", "id", "payload", "workspace_id")):
                    documents[value["id"]] = value
                for child in value.values():
                    collect(child)
            elif isinstance(value, list):
                for child in value:
                    collect(child)
        collect(workspace)
        sql = (EXAMPLES / "1.0/illustrative-record-storage.sql").read_text()
        literals = re.findall(r"CONVERT\(0x([0-9a-f]+) USING utf8mb4\)", sql)
        self.assertEqual(len(literals), len(documents) * 2)
        seen = set()
        for index in range(0, len(literals), 2):
            document = json.loads(bytes.fromhex(literals[index]).decode())
            frame = json.loads(bytes.fromhex(literals[index + 1]).decode())
            self.assertEqual(document, documents[document["id"]])
            self.assertEqual(frame["document"], document)
            self.assertEqual(frame["change_sequence"], str(index // 2 + 1))
            validate_instance(frame, load_json(CONTRACTS / "server-record.schema.json"), "server-record.schema.json")
            seen.add(document["id"])
        self.assertEqual(seen, set(documents))
        self.assertEqual(sql.count("INSERT INTO example_changes"), len(documents))
        self.assertNotIn("DROP TABLE", sql)

    def test_version_zero_schema_retains_original_migration(self):
        """The archived SQL is the original migration plus an explicit historical version preamble."""
        copy = (EXAMPLES / "0/historical-demo-schema.sql").read_text().split("\n", 2)[2]
        self.assertEqual(copy, (ROOT / "Server/SQL/001_plenact_demo_core.sql").read_text())
