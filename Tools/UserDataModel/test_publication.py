"""Model 1.0 publication regression tests; no network or personal data access."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from publication_gate import package, verify_package, verify_source_snapshot, validate_links
from validate_contract import ContractError


class PublicationTests(unittest.TestCase):
    def test_source_mapping_targets_and_frozen_baseline(self):
        """Every captured field has a lifecycle and schema-target spelling remains valid."""
        self.assertEqual(verify_source_snapshot(check_hashes=False), (96, 379))

    def test_document_links(self):
        """Published local document references resolve before being pinned to the tag."""
        validate_links()

    def test_reproducible_package_excludes_dependencies(self):
        """Identical sources produce identical ZIP bytes with no runtime caches."""
        with tempfile.TemporaryDirectory() as directory, patch("publication_gate.check"):
            first = Path(directory) / "one.zip"
            second = Path(directory) / "two.zip"
            self.assertEqual(package(first), package(second))
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertGreater(verify_package(first), 200)
            with zipfile.ZipFile(first) as archive:
                self.assertFalse(any("node_modules" in n or "__pycache__" in n for n in archive.namelist()))
                text = archive.read("Doc/User-Data-Model/Source-Field-Catalogue.md").decode()
                self.assertIn("blob/user-data-model-v1.0/Src/", text)
            with self.assertRaises(ContractError):
                package(first)

    def test_modified_package_rejected(self):
        """A changed payload is rejected even when the ZIP itself is well formed."""
        with tempfile.TemporaryDirectory() as directory, patch("publication_gate.check"):
            original = Path(directory) / "original.zip"
            damaged = Path(directory) / "damaged.zip"
            package(original)
            with zipfile.ZipFile(original) as source, zipfile.ZipFile(damaged, "w") as output:
                for name in source.namelist():
                    content = source.read(name)
                    if name == "Doc/User-Data-Model/README.md":
                        content += b"changed"
                    output.writestr(name, content)
            with self.assertRaises(ContractError):
                verify_package(damaged)


if __name__ == "__main__":
    unittest.main()
