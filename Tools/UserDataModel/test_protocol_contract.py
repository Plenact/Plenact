"""Executable Protocol 1.0 conformance examples; no live user data or server access.

Supported User Data Model versions: 1.0. These are reference rules, not production services.
"""
from copy import deepcopy
import hashlib
import json
import unittest
import uuid

from protocol_examples import RevisionExample, ChunkExample
from validate_contract import CONTRACTS, ContractError, load_json, validate_instance


class ProtocolTests(unittest.TestCase):
    """Protect atomicity, exact retry semantics, long-offline retention and upload integrity."""

    def setUp(self):
        """Use only synthetic record documents and explicit no-op graph validation for transport tests."""
        self.tx = load_json(CONTRACTS / "Fixtures/transaction-create.json")
        self.account = "70000000-0000-4000-8000-000000000002"
        self.model = RevisionExample(self.account, self.tx["workspace_id"], self.tx["epoch"], lambda rows: None)

    def raw(self, transaction):
        """Represent the immutable bytes a client must save in its outbox before sending."""
        return json.dumps(transaction, ensure_ascii=False, separators=(",", ":")).encode()

    def edit(self, base="1"):
        """Construct a fresh operation identity for an explicit edit against a known revision."""
        value = deepcopy(self.tx)
        value["transaction_id"] = str(uuid.uuid4())
        value["operations"][0]["operation_id"] = str(uuid.uuid4())
        value["operations"][0]["base_revision"] = base
        value["operations"][0]["document"]["payload"]["title"] = "A deliberate edit"
        return value

    def test_lost_response_retry_returns_same_receipt_without_extra_revision(self):
        """Network ambiguity must not duplicate a successful content change."""
        data = self.raw(self.tx)
        first = self.model.apply(data, self.account)
        second = self.model.apply(data, self.account)
        self.assertEqual(first, second)
        self.assertEqual(self.model.sequence, 1)
        self.assertEqual(len(self.model.rows), 1)
        validate_instance(first, load_json(CONTRACTS / "transaction-receipt.schema.json"), "transaction-receipt.schema.json")

    def test_same_key_with_different_formatting_is_a_mismatch(self):
        """Even logically equivalent requests must reuse their original exact request bytes."""
        self.model.apply(self.raw(self.tx), self.account)
        with self.assertRaisesRegex(ContractError, "idempotency_mismatch"):
            self.model.apply(json.dumps(self.tx, indent=2).encode(), self.account)
        self.assertEqual(self.model.sequence, 1)

    def test_concurrent_record_edits_keep_second_local_edit_for_resolution(self):
        """A stale writer never silently overwrites the winning revision."""
        self.model.apply(self.raw(self.tx), self.account)
        first = self.edit()
        second = self.edit()
        second["operations"][0]["document"]["payload"]["title"] = "Retain my local version"
        original = self.raw(second)
        self.model.apply(self.raw(first), self.account)
        with self.assertRaisesRegex(ContractError, "conflict"):
            self.model.apply(original, self.account)
        self.assertEqual(original, self.raw(second))
        self.assertEqual(self.model.sequence, 2)

    def test_multi_record_failure_commits_nothing(self):
        """A later conflict cannot leave an earlier operation partially applied."""
        self.model.apply(self.raw(self.tx), self.account)
        value = self.edit()
        second = deepcopy(value["operations"][0])
        second["operation_id"] = str(uuid.uuid4())
        second["record_id"] = str(uuid.uuid4())
        second["document"]["id"] = second["record_id"]
        value["operations"].append(second)
        before = self.model.snapshot()
        with self.assertRaisesRegex(ContractError, "conflict"):
            self.model.apply(self.raw(value), self.account)
        self.assertEqual(self.model.snapshot(), before)

    def test_graph_callback_failure_is_atomic(self):
        """Transport validation is not a substitute for the service's required graph validation."""
        def reject(rows):
            raise ContractError("validation_failed")
        self.model.validate_state = reject
        with self.assertRaisesRegex(ContractError, "validation_failed"):
            self.model.apply(self.raw(self.tx), self.account)
        self.assertEqual(self.model.sequence, 0)
        self.assertEqual(self.model.receipts, {})

    def test_delete_marker_prevents_stale_recreation_after_cursor_expiry(self):
        """An indefinitely offline device can resnapshot but cannot resurrect a deleted ID."""
        self.model.apply(self.raw(self.tx), self.account)
        deletion = self.edit()
        deletion["operations"][0].update(kind="delete", document=None)
        self.model.apply(self.raw(deletion), self.account)
        self.model.expire_delta_history()
        with self.assertRaisesRegex(ContractError, "cursor_expired"):
            self.model.changes(0)
        self.assertTrue(self.model.snapshot()["records"][0]["deleted"])
        recreation = self.edit(base=None)
        with self.assertRaisesRegex(ContractError, "conflict"):
            self.model.apply(self.raw(recreation), self.account)

    def test_receipts_survive_change_log_compaction(self):
        """Long-offline retry safety cannot depend on the finite change-feed retention window."""
        data = self.raw(self.tx)
        receipt = self.model.apply(data, self.account)
        self.model.expire_delta_history()
        self.assertEqual(self.model.apply(data, self.account), receipt)

    def test_restored_server_epoch_blocks_old_outbox_replay(self):
        """A restored database must require reconciliation rather than accepting stale epochs."""
        self.model.epoch = str(uuid.uuid4())
        with self.assertRaisesRegex(ContractError, "epoch_mismatch"):
            self.model.apply(self.raw(self.tx), self.account)
        self.assertEqual(self.model.rows, {})

    def test_device_id_is_not_authorization(self):
        """A valid device UUID never grants another principal access to this workspace."""
        with self.assertRaisesRegex(ContractError, "forbidden"):
            self.model.apply(self.raw(self.tx), str(uuid.uuid4()))

    def test_operation_id_cannot_be_reused_in_a_new_transaction(self):
        """Operation identity is durable across request-level idempotency keys."""
        self.model.apply(self.raw(self.tx), self.account)
        transaction = deepcopy(self.tx)
        transaction["transaction_id"] = str(uuid.uuid4())
        with self.assertRaisesRegex(ContractError, "idempotency_mismatch"):
            self.model.apply(self.raw(transaction), self.account)

    def test_upload_identical_retry_and_integrity(self):
        """Resume at an existing chunk without changing its bytes or falsely duplicating it."""
        data = b"abc" * 100000
        upload = ChunkExample(len(data), hashlib.sha256(data).hexdigest())
        chunks = [data[i:i+262144] for i in range(0, len(data), 262144)]
        for index, chunk in enumerate(chunks):
            sha = hashlib.sha256(chunk).hexdigest()
            upload.put(index, chunk, sha)
            upload.put(index, chunk, sha)
        self.assertEqual(upload.commit(), data)
        self.assertTrue(upload.verified)

    def test_truncated_or_replaced_chunks_never_become_verified(self):
        """Reject bad bytes and incomplete uploads before claiming successful transfer."""
        upload = ChunkExample(3, hashlib.sha256(b"abc").hexdigest())
        with self.assertRaisesRegex(ContractError, "integrity_mismatch"):
            upload.put(0, b"ab", hashlib.sha256(b"ab").hexdigest())
        with self.assertRaisesRegex(ContractError, "incomplete_upload"):
            upload.commit()
        upload.put(0, b"bad", hashlib.sha256(b"bad").hexdigest())
        with self.assertRaisesRegex(ContractError, "conflict"):
            upload.put(0, b"abc", hashlib.sha256(b"abc").hexdigest())
        with self.assertRaisesRegex(ContractError, "integrity_mismatch"):
            upload.commit()
        self.assertFalse(upload.verified)

    def test_zero_byte_asset_is_verified_only_against_empty_digest(self):
        """Known empty content is different from unknown/unavailable source bytes."""
        upload = ChunkExample(0, hashlib.sha256(b"").hexdigest())
        self.assertEqual(upload.commit(), b"")
        self.assertTrue(upload.verified)


if __name__ == "__main__":
    unittest.main()
