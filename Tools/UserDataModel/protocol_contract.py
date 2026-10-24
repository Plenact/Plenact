"""Executable semantic rules for the frozen Plenact User Data Model/Protocol 1.0.

Supported User Data Model versions: 1.0. Contract validation, not a production server.
"""

from datetime import datetime, timedelta
import json
import jcs


PROTOCOL_SCHEMAS = {
    "server-record.schema.json", "transaction-request.schema.json", "transaction-receipt.schema.json",
    "snapshot-page.schema.json", "changes-page.schema.json", "service-capabilities.schema.json",
    "api-error.schema.json", "asset-upload-request.schema.json", "asset-upload-session.schema.json",
    "asset-upload-commit.schema.json", "asset-purge-request.schema.json", "asset-purge-receipt.schema.json", "account-deletion-request.schema.json", "account-deletion-receipt.schema.json"
}
MAX_COUNTER = 9_223_372_036_854_775_807
MAX_ASSET_LENGTH = 18_446_744_073_709_551_615
MAX_JSON_BYTES = 8_388_608
MAX_DOCUMENT_BYTES = 4_194_304
SERVER_OWNED_TYPES = {"account", "workspace"}


def walk(value, depth=0):
    """Traverse JSON values and enforce the protocol's platform-neutral depth bound."""
    if depth > 64:
        raise ValueError("json_too_deep")
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child, depth + 1)


def check_unicode(value, fail, depth=0):
    """Reject unpaired surrogate code points without Unicode-normalizing user writing."""
    if depth > 64:
        raise fail("json_too_deep")
    if isinstance(value, str):
        if any(0xD800 <= ord(char) <= 0xDFFF for char in value):
            raise fail("invalid_unicode_scalar")
    elif isinstance(value, dict):
        for key, child in value.items():
            check_unicode(key, fail, depth + 1)
            check_unicode(child, fail, depth + 1)
    elif isinstance(value, list):
        for child in value:
            check_unicode(child, fail, depth + 1)


def counter(value, fail):
    """Parse a canonical decimal signed-64-bit sequence without using floating point."""
    if len(value) > 19 or int(value) > MAX_COUNTER:
        raise fail("counter_out_of_range")
    return int(value)


def unique(values, code, fail):
    """Reject repeated logical identities even when their JSON payloads differ."""
    if len(values) != len(set(values)):
        raise fail(code)


def instant(value):
    """Parse the schema-constrained UTC millisecond timestamp."""
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_server_record(value, fail, validate_document):
    """Check tombstone state, document identity and independent verified-asset metadata."""
    for key in ("revision", "change_sequence"):
        counter(value[key], fail)
    if value["deleted"] != (value["document"] is None):
        raise fail("invalid_tombstone")
    if value["deleted"]:
        if value["asset_content"] is not None:
            raise fail("invalid_tombstone")
        return
    document = value["document"]
    if (document["record_type"] != value["record_type"] or document["id"] != value["record_id"]
            or document["workspace_id"] != value["workspace_id"]):
        raise fail("record_identity_mismatch")
    validate_document(document)
    asset = value["asset_content"]
    if value["record_type"] != "asset" and asset is not None:
        raise fail("unexpected_asset_content")
    if value["record_type"] == "asset":
        if asset is None:
            raise fail("missing_asset_content_state")
        if asset["state"] == "verified":
            payload = document["payload"]
            if payload["content_state"] != "described" or asset["verified_at_utc"] is None:
                raise fail("invalid_verified_asset")
            if asset["byte_length"] != payload["byte_length"] or asset["sha256"] != payload["sha256"]:
                raise fail("invalid_verified_asset")
        elif any(asset[k] is not None for k in ("byte_length", "sha256", "verified_at_utc")):
            raise fail("invalid_unavailable_asset")


def validate_protocol(value, schema_name, fail, validate_document):
    """Validate protocol consistency in addition to the frozen structural schemas."""
    check_unicode(value, fail)
    try:
        nodes = list(walk(value))
    except ValueError as error:
        raise fail("json_too_deep") from error
    for node in nodes:
        for key, child in node.items():
            if key.endswith("_utc") and child is not None:
                try:
                    instant(child)
                except ValueError as error:
                    raise fail("invalid_gregorian_date") from error
            if key in {"revision", "base_revision", "change_sequence", "after_sequence", "through_sequence", "fence_sequence", "receipt_sequence", "current_revision", "asset_revision"} and child is not None:
                counter(child, fail)
            if key in {"byte_length", "max_upload_bytes"} and child is not None:
                if len(child) > 20 or int(child) > MAX_ASSET_LENGTH:
                    raise fail("asset_size_out_of_range")
    if schema_name == "server-record.schema.json":
        validate_server_record(value, fail, validate_document)
    elif schema_name == "transaction-request.schema.json":
        operations = value["operations"]
        unique([o["operation_id"] for o in operations], "duplicate_operation", fail)
        unique([(o["record_type"], o["record_id"]) for o in operations], "duplicate_record_operation", fail)
        for operation in operations:
            if operation["record_type"] in SERVER_OWNED_TYPES:
                raise fail("server_owned_record")
            if operation["kind"] == "put":
                document = operation["document"]
                if document["workspace_id"] != value["workspace_id"]:
                    raise fail("workspace_mismatch")
                if operation["record_type"] != document["record_type"] or operation["record_id"] != document["id"]:
                    raise fail("record_identity_mismatch")
                if len(jcs.canonicalize(document)) > MAX_DOCUMENT_BYTES:
                    raise fail("document_too_large")
                validate_document(document)
    elif schema_name == "transaction-receipt.schema.json":
        unique([r["operation_id"] for r in value["results"]], "duplicate_operation", fail)
        sequences = [counter(r["change_sequence"], fail) for r in value["results"]]
        if any(b != a + 1 for a, b in zip(sequences, sequences[1:])) or sequences[-1] != counter(value["receipt_sequence"], fail):
            raise fail("invalid_receipt_sequence")
    elif schema_name in {"snapshot-page.schema.json", "changes-page.schema.json"}:
        records = value["records"]
        for record in records:
            if record["workspace_id"] != value["workspace_id"] or record["epoch"] != value["epoch"]:
                raise fail("workspace_or_epoch_mismatch")
            validate_server_record(record, fail, validate_document)
        if schema_name == "snapshot-page.schema.json":
            if (value["next_page_cursor"] is None) == (value["next_change_cursor"] is None):
                raise fail("invalid_snapshot_cursor")
            unique([(r["record_type"], r["record_id"]) for r in records], "duplicate_snapshot_record", fail)
            if any(counter(r["change_sequence"], fail) > counter(value["fence_sequence"], fail) for r in records):
                raise fail("invalid_snapshot_fence")
        else:
            sequences = [counter(r["change_sequence"], fail) for r in records]
            after = counter(value["after_sequence"], fail)
            through = counter(value["through_sequence"], fail)
            if sequences != sorted(set(sequences)):
                raise fail("invalid_change_order")
            if through < after or any(s <= after or s > through for s in sequences):
                raise fail("invalid_change_watermark")
            if sequences and (sequences[0] != after + 1 or any(b != a + 1 for a, b in zip(sequences, sequences[1:]))):
                raise fail("invalid_change_gap")
            if sequences and sequences[-1] != through:
                raise fail("invalid_change_watermark")
            if not sequences and through != after:
                raise fail("invalid_change_watermark")
            if value["has_more"] and not sequences:
                raise fail("invalid_empty_change_page")
    elif schema_name == "asset-upload-session.schema.json":
        size = int(value["byte_length"])
        expected = (size + value["chunk_bytes"] - 1) // value["chunk_bytes"]
        if value["chunk_count"] != expected:
            raise fail("invalid_chunk_count")
        if any(i >= expected for i in value["received_chunks"]):
            raise fail("invalid_chunk_index")
    elif schema_name == "service-capabilities.schema.json":
        if not 1 <= int(value["max_upload_bytes"]) <= 1_073_741_824:
            raise fail("invalid_upload_limit")
    elif schema_name in {"account-deletion-receipt.schema.json", "asset-purge-receipt.schema.json"}:
        accepted = instant(value["accepted_at_utc"])
        primary = instant(value["primary_delete_deadline_utc"])
        backup = instant(value["backup_delete_deadline_utc"])
        if not accepted <= primary <= accepted + timedelta(hours=24) or not primary <= backup <= accepted + timedelta(days=30):
            raise fail("invalid_deletion_deadline")
