"""Deterministic protocol examples for User Data Model 1.0.

Supported User Data Model versions: 1.0. In-memory conformance models only.
Not a database, authentication service, production sync engine or deployable API.
"""

from copy import deepcopy
import hashlib
import json

from validate_contract import CONTRACTS, ContractError, load_json, unique_object, finite_float, reject_constant, validate_instance


class RevisionExample:
    """Exercise revision/retry/deletion rules independently of hosting or app storage."""

    def __init__(self, account_id, workspace_id, epoch, validate_state):
        """Bind verified test identity/context and an explicit post-transaction graph validator."""
        self.account_id = account_id
        self.workspace_id = workspace_id
        self.epoch = epoch
        self.validate_state = validate_state
        self.rows = {}
        self.receipts = {}
        self.operation_ids = set()
        self.sequence = 0
        self.change_log = []
        self.expired_before = 0

    def apply(self, raw_request, authenticated_account):
        """Commit a complete transaction or nothing; retain exact-byte successful receipts."""
        if authenticated_account != self.account_id:
            raise ContractError("forbidden")
        if len(raw_request) > 8_388_608:
            raise ContractError("payload_too_large")
        value = json.loads(raw_request.decode("utf-8"), object_pairs_hook=unique_object,
                           parse_float=finite_float, parse_constant=reject_constant)
        validate_instance(value, load_json(CONTRACTS / "transaction-request.schema.json"), "transaction-request.schema.json")
        if value["workspace_id"] != self.workspace_id:
            raise ContractError("forbidden")
        if value["epoch"] != self.epoch:
            raise ContractError("epoch_mismatch")
        request_hash = hashlib.sha256(raw_request).hexdigest()
        transaction_id = value["transaction_id"]
        if transaction_id in self.receipts:
            receipt = self.receipts[transaction_id]
            if receipt["request_sha256"] != request_hash:
                raise ContractError("idempotency_mismatch")
            return deepcopy(receipt)
        if any(op["operation_id"] in self.operation_ids for op in value["operations"]):
            raise ContractError("idempotency_mismatch")
        proposed = deepcopy(self.rows)
        results = []
        changes = []
        sequence = self.sequence
        for operation in value["operations"]:
            key = (operation["record_type"], operation["record_id"])
            previous = proposed.get(key)
            if any(record_id == key[1] and record_type != key[0] for record_type, record_id in proposed):
                raise ContractError("conflict")
            base = operation["base_revision"]
            if base is None:
                if previous is not None:
                    raise ContractError("conflict")
            elif previous is None or previous["deleted"] or previous["revision"] != base:
                raise ContractError("conflict")
            document = operation["document"]
            if document is not None and document["payload"].get("account_id", self.account_id) != self.account_id:
                raise ContractError("forbidden")
            sequence += 1
            revision = str(int(previous["revision"]) + 1) if previous is not None else "1"
            row = {"user_data_model_version": "1.0", "workspace_id": self.workspace_id,
                   "record_type": key[0], "record_id": key[1], "epoch": self.epoch,
                   "revision": revision, "change_sequence": str(sequence),
                   "stored_at_utc": "2026-10-24T12:00:00.000Z", "stored_by_account_id": self.account_id,
                   "deleted": operation["kind"] == "delete", "document": deepcopy(document),
                   "asset_content": None}
            if key[0] == "asset" and not row["deleted"]:
                row["asset_content"] = deepcopy(previous["asset_content"]) if previous is not None else {
                    "state": "unavailable", "byte_length": None, "sha256": None, "verified_at_utc": None}
            proposed[key] = row
            changes.append(row)
            results.append({"operation_id": operation["operation_id"], "record_type": key[0], "record_id": key[1],
                            "revision": revision, "change_sequence": str(sequence), "deleted": row["deleted"]})
        # Graph/ownership violations are checked before any durable state changes in this example.
        self.validate_state(proposed)
        receipt = {"protocol_version": "1.0", "workspace_id": self.workspace_id, "epoch": self.epoch,
                   "transaction_id": transaction_id, "request_sha256": request_hash,
                   "receipt_sequence": str(sequence), "stored_at_utc": "2026-10-24T12:00:00.000Z", "results": results}
        self.rows = proposed
        self.sequence = sequence
        self.change_log.extend(deepcopy(changes))
        self.operation_ids.update(op["operation_id"] for op in value["operations"])
        self.receipts[transaction_id] = deepcopy(receipt)
        return receipt

    def snapshot(self):
        """Freeze current rows and all deletion markers without changing pending client work."""
        return {"epoch": self.epoch, "fence": self.sequence,
                "records": [deepcopy(self.rows[key]) for key in sorted(self.rows)]}

    def expire_delta_history(self):
        """Compact only the change log; receipts and tombstones remain available indefinitely."""
        self.expired_before = self.sequence
        self.change_log = []

    def changes(self, after):
        """Demonstrate cursor expiry without imposing an expiry on local user data."""
        if after < self.expired_before:
            raise ContractError("cursor_expired")
        return [deepcopy(r) for r in self.change_log if int(r["change_sequence"]) > after]


class ChunkExample:
    """Exercise resumable exact-byte chunk integrity, not storage or file-format validation."""

    def __init__(self, size, sha256, chunk_bytes=262144):
        """Retain immutable upload expectations and initially unverified chunks."""
        self.size = size
        self.sha256 = sha256
        self.chunk_bytes = chunk_bytes
        self.parts = {}
        self.verified = False

    def put(self, index, data, chunk_sha256):
        """Accept an identical retry; reject wrong length/hash or replacement at the same index."""
        count = (self.size + self.chunk_bytes - 1) // self.chunk_bytes
        if not 0 <= index < count:
            raise ContractError("invalid_chunk_index")
        expected = min(self.chunk_bytes, self.size - index * self.chunk_bytes)
        if len(data) != expected or hashlib.sha256(data).hexdigest() != chunk_sha256:
            raise ContractError("integrity_mismatch")
        if index in self.parts and self.parts[index] != data:
            raise ContractError("conflict")
        self.parts[index] = bytes(data)

    def commit(self):
        """Verify the concatenated original bytes before reporting any successful completion."""
        count = (self.size + self.chunk_bytes - 1) // self.chunk_bytes
        if set(self.parts) != set(range(count)):
            raise ContractError("incomplete_upload")
        data = b"".join(self.parts[index] for index in range(count))
        if len(data) != self.size or hashlib.sha256(data).hexdigest() != self.sha256:
            raise ContractError("integrity_mismatch")
        self.verified = True
        return data
