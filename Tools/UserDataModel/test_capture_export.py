"""Read-only export preflight tests; Model 1.0 target, capture format 1, final specification.

Supported User Data Model versions: 1.0 definitions only; captures retain legacy bytes.
All source workspaces are synthetic temporary directories. No live app data is read.
"""

import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import capture_export
from capture_export import capture, validate_capture
from validate_contract import CONTRACTS, ContractError, load_json, validate_instance


class ReadOnlyCaptureTests(unittest.TestCase):
    """Prove byte preservation, explicit diagnostics, private output and failure isolation."""

    def setUp(self):
        """Create an isolated frozen source with one synthetic Card and media file."""
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "snapshot"
        self.source.mkdir()
        media = self.source / "Documents/CardAttachments"
        media.mkdir(parents=True)
        (media / "example.bin").write_bytes(b"synthetic exact bytes\x00\xff")
        self.data = [{"id": 1, "title": "Example List", "cards": [{"id": 1, "fileName": "example.bin"}]}]
        self.preferences = {
            "Plenact.Board.v1": json.dumps(self.data).encode(),
            "Plenact.SavedCardIDs.v1": [1],
            "Plenact.CardCovers.enabled": False,
            "Plenact.LastViewedList.v1": 1,
        }
        self.write_preferences()

    def write_preferences(self):
        """Write synthetic fixture input before running the read-only subject."""
        (self.source / "Preferences.plist").write_bytes(plistlib.dumps(self.preferences, fmt=plistlib.FMT_BINARY))

    def fingerprint(self):
        """Hash all source files to detect accidental mutation or deletion."""
        return {p.relative_to(self.source).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.source.rglob("*") if p.is_file()}

    def test_capture_preserves_bytes_and_never_claims_conversion(self):
        """A verified legacy capture must not masquerade as portable Model 1.0 data."""
        before = self.fingerprint()
        output = self.root / "capture"
        manifest = capture(self.source, output)
        self.assertEqual(self.fingerprint(), before)
        self.assertEqual(manifest["status"], "captured")
        self.assertFalse(manifest["portable_conversion_complete"])
        self.assertEqual(validate_capture(output), manifest)
        entries = {e["key"]: e for e in manifest["stores"]}
        for key, original in self.preferences.items():
            restored = plistlib.loads((output / entries[key]["value_file"]).read_bytes())["value"]
            self.assertIs(type(restored), type(original))
            self.assertEqual(restored, original)
        self.assertEqual(output.stat().st_mode & 0o777, 0o700)
        self.assertEqual((output / "manifest.json").stat().st_mode & 0o777, 0o600)

    def test_wrong_saved_boolean_type_is_not_coerced(self):
        """A saved integer flag remains an integer and requires review rather than guessing."""
        self.preferences["Plenact.CardCovers.enabled"] = 1
        self.write_preferences()
        output = self.root / "capture"
        manifest = capture(self.source, output)
        self.assertIn("unexpected_native_store_type", [d["code"] for d in manifest["diagnostics"]])
        entry = next(e for e in manifest["stores"] if e["key"] == "Plenact.CardCovers.enabled")
        self.assertIs(type(plistlib.loads((output / entry["value_file"]).read_bytes())["value"]), int)

    def test_corrupt_json_is_retained_without_examples_or_defaults(self):
        """Unreadable saved bytes are preserved and marked for review, never replaced."""
        self.preferences["Plenact.Board.v1"] = b"not valid json"
        self.write_preferences()
        output = self.root / "capture"
        manifest = capture(self.source, output)
        self.assertEqual(manifest["status"], "needs_review")
        self.assertIn("unreadable_json_store", [e["code"] for e in manifest["diagnostics"]])
        entry = next(e for e in manifest["stores"] if e["key"] == "Plenact.Board.v1")
        self.assertEqual(plistlib.loads((output / entry["value_file"]).read_bytes())["value"], b"not valid json")

    def test_unknown_preferences_are_reported_without_copying_values(self):
        """Unclassified keys block completeness and potential credentials stay out."""
        self.preferences["Plenact.FutureSecret"] = "synthetic-secret-never-copy"
        self.write_preferences()
        output = self.root / "capture"
        manifest = capture(self.source, output)
        self.assertIn("Plenact.FutureSecret", manifest["excluded_keys"])
        self.assertEqual(manifest["status"], "needs_review")
        self.assertNotIn(b"synthetic-secret-never-copy", b"".join(p.read_bytes() for p in output.rglob("*") if p.is_file()))

    def test_pending_recovery_is_captured_but_not_executed(self):
        """Recovery state needs app-level handling; exporting must not run it."""
        journal = plistlib.dumps({"version": 1, "previous": {}})
        self.preferences["Plenact.DailyReviewTransaction.v1"] = journal
        self.write_preferences()
        before = self.fingerprint()
        manifest = capture(self.source, self.root / "capture")
        self.assertEqual(self.fingerprint(), before)
        self.assertIn("pending_recovery_transaction", [e["code"] for e in manifest["diagnostics"]])

    def test_missing_media_is_reported_without_deleting_metadata(self):
        """An unavailable original remains a reference, not an invented empty file."""
        (self.source / "Documents/CardAttachments/example.bin").unlink()
        manifest = capture(self.source, self.root / "capture")
        self.assertEqual(manifest["files"], [])
        self.assertIn("missing_media_file", [e["code"] for e in manifest["diagnostics"]])

    def test_missing_store_does_not_create_starter_data(self):
        """An absent calendar/profile remains absent in the capture inventory."""
        manifest = capture(self.source, self.root / "capture")
        keys = {e["key"] for e in manifest["stores"]}
        self.assertNotIn("Plenact.CalendarWeeks.v1", keys)
        self.assertNotIn("Plenact.LocalProfile.v1", keys)

    def test_existing_output_and_input_overlap_are_rejected(self):
        """Avoid overwriting prior captures or writing anything inside source data."""
        output = self.root / "capture"
        output.mkdir()
        with self.assertRaisesRegex(ContractError, "output_already_exists"):
            capture(self.source, output)
        with self.assertRaisesRegex(ContractError, "input_output_overlap"):
            capture(self.source, self.source / "capture")

    def test_symlink_source_media_is_rejected(self):
        """Never follow a media link into credentials or unrelated folders."""
        outside = self.root / "outside.txt"
        outside.write_text("not user media")
        (self.source / "Documents/CardAttachments/link").symlink_to(outside)
        with self.assertRaisesRegex(ContractError, "symlink_not_allowed"):
            capture(self.source, self.root / "capture")
        self.assertFalse((self.root / "capture").exists())

    def test_injected_copy_failure_removes_only_new_output(self):
        """A failed export leaves the frozen source byte-for-byte unchanged."""
        before = self.fingerprint()
        with patch.object(capture_export, "copy_media", side_effect=OSError("synthetic failure")):
            with self.assertRaises(OSError):
                capture(self.source, self.root / "capture")
        self.assertEqual(self.fingerprint(), before)
        self.assertFalse((self.root / "capture").exists())

    def test_truncated_export_fails_integrity_verification(self):
        """Detect corruption after capture rather than trusting manifest status."""
        output = self.root / "capture"
        manifest = capture(self.source, output)
        (output / manifest["files"][0]["blob_file"]).write_bytes(b"truncated")
        with self.assertRaisesRegex(ContractError, "capture_integrity_mismatch"):
            validate_capture(output)

    def test_manifest_cannot_read_outside_capture(self):
        """Reject manifest traversal even if other schema fields look valid."""
        output = self.root / "capture"
        manifest = capture(self.source, output)
        manifest["stores"][0]["value_file"] = "../snapshot/Preferences.plist"
        (output / "manifest.json").write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ContractError, "unsafe_capture_path"):
            validate_capture(output)

    def test_manifest_symlink_and_unsafe_source_paths_are_rejected(self):
        """Treat even the top-level manifest as untrusted filesystem input."""
        output = self.root / "capture"
        manifest = capture(self.source, output)
        manifest["files"][0]["source_relative_path"] = "../private.bin"
        (output / "manifest.json").write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ContractError, "unsafe_capture_path"):
            validate_capture(output)
        target = self.root / "outside-manifest.json"
        (output / "manifest.json").rename(target)
        (output / "manifest.json").symlink_to(target)
        with self.assertRaisesRegex(ContractError, "symlink_not_allowed"):
            validate_capture(output)

    def test_future_store_version_is_preserved_and_reported(self):
        """Do not decode unsupported documents through fallback defaults."""
        self.preferences["Plenact.DailyPlans.v1"] = b'{"version":99,"plans":{}}'
        self.write_preferences()
        manifest = capture(self.source, self.root / "capture")
        self.assertIn("unsupported_store_version", [e["code"] for e in manifest["diagnostics"]])

    def test_external_source_change_aborts_without_publishing_capture(self):
        """Do not publish success when a caller supplied a changing, non-frozen input."""
        original = capture_export.copy_media
        def changed_source(path, blobs):
            result = original(path, blobs)
            self.preferences["Plenact.SavedCardIDs.v1"] = []
            self.write_preferences()
            return result
        with patch.object(capture_export, "copy_media", side_effect=changed_source):
            with self.assertRaisesRegex(ContractError, "source_changed_during_capture"):
                capture(self.source, self.root / "capture")
        self.assertFalse((self.root / "capture").exists())
        self.assertEqual(plistlib.loads((self.source / "Preferences.plist").read_bytes())["Plenact.SavedCardIDs.v1"], [])

    def test_all_media_areas_preserve_duplicate_bytes_and_distinct_paths(self):
        """Capture all four owned media areas without conflating their source paths."""
        for relative in capture_export.MEDIA_ROOTS[1:]:
            directory = self.source / relative
            directory.mkdir(parents=True)
            (directory / "shared.bin").write_bytes(b"same bytes")
        manifest = capture(self.source, self.root / "capture")
        self.assertEqual(len(manifest["files"]), 4)
        paths = {entry["source_relative_path"] for entry in manifest["files"]}
        self.assertEqual(len(paths), 4)
        shared = [entry["blob_file"] for entry in manifest["files"] if entry["source_relative_path"].endswith("shared.bin")]
        self.assertEqual(len(set(shared)), 1)

    def test_new_workspace_definitions_are_closed_and_valid(self):
        """Validate full proposed workspace fixtures without implying an export adapter exists."""
        value = load_json(CONTRACTS / "Fixtures/complete-workspace-candidate.json")
        schema = load_json(CONTRACTS / "workspace-export.schema.json")
        validate_instance(value, schema, "workspace-export.schema.json")


if __name__ == "__main__":
    unittest.main()
