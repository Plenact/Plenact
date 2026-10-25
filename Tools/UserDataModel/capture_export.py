"""Create a lossless, read-only capture from an explicitly supplied frozen app backup.

Supported User Data Model versions: 1.0 target definition; legacy source bytes only.
Capture format: plenact.read-only-capture, version 1. final specification.
Status: offline preflight/capture tooling, not a native migration adapter or cloud upload.
Never discovers live app containers, accesses Keychain, calls app loaders, or uses the network.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat

from validate_contract import ContractError, CONTRACTS, load_json, unique_object, finite_float, reject_constant, validate_instance


JSON_STORES = {
    "Plenact.Board.v1": list,
    "Plenact.CalendarWeeks.v1": dict,
    "Plenact.PersonalCollections.v1": list,
    "Plenact.LabelLibrary.v1": dict,
    "Plenact.LocalProfile.v1": dict,
    "Plenact.PlanPreferences.v1": dict,
    "Plenact.PlanningTemplates.v1": dict,
    "Plenact.DailyPlans.v1": dict,
    "Plenact.WeeklyReviews.v1": dict,
    "Plenact.PeriodicReviews.v1": dict,
    "Plenact.ReviewRhythm.v1": dict,
    "Plenact.Studio.Settings.v1": dict,
    "Plenact.Studio.Artwork.v1": list,
    "Plenact.LibraryImportant.v1": list,
    "Plenact.WeekAppearance.v1": dict,
    "Plenact.TodayListShortcuts.v1": list,
    "Plenact.LibraryRecents.v1": list,
    "Plenact.ActivityRecents.v1": list,
}
NATIVE_STORES = {
    "Plenact.SavedCardIDs.v1", "Plenact.RecentSearches.v1", "Plenact.LocalReactionAuthor.v1",
    "Plenact.BoardPresentation.v1", "Plenact.CardCovers.enabled", "Plenact.ActivityShowsCovers",
    "Plenact.ActivityRecentSquareCards", "Plenact.LibraryShowsCollectionPreviews",
    "Plenact.LibraryScrollsCollectionPreviews"
}
DEVICE_STORES = {"Plenact.LastViewedList.v1", "Plenact.Welcome.lastDeparture.v1", "Plenact.ReviewRhythmDismissals.v1"}
RECOVERY_STORES = {
    "Plenact.DailyReviewTransaction.v1", "Plenact.ExampleLoadUndo.v1",
    "Plenact.ExampleCardLocations.Applied.v1", "Plenact.ExampleCardLocations.Backup.v1"
}
MEDIA_ROOTS = (
    "Documents/CardAttachments", "Documents/ProfileAvatars",
    "Library/Application Support/PlenactStudioArtwork",
    "Library/Application Support/PlenactCollectionBackgrounds"
)
MAX_PREFERENCE_BYTES = 64 * 1024 * 1024


def digest(data):
    """Return an exact-byte SHA-256 digest, without logging source content."""
    return hashlib.sha256(data).hexdigest()


def inside(path, parent):
    """Check path containment without relying on string-prefix matching."""
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def checked_file(root, relative):
    """Resolve a regular non-symlink input file strictly inside the supplied root."""
    relative = PurePosixPath(relative)
    if relative.is_absolute() or ".." in relative.parts or "\\" in str(relative):
        raise ContractError("unsafe_capture_path")
    path = root.joinpath(*relative.parts)
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ContractError("symlink_not_allowed")
    if not inside(path.resolve(), root) or not path.is_file():
        raise ContractError("missing_capture_file")
    return path


def signature(info):
    """Retain stable input identity/size/modification metadata for concurrent-change checks."""
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def read_stable(path):
    """Read a bounded preference file without writing it; reject concurrent replacement."""
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags), "rb") as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_PREFERENCE_BYTES:
            raise ContractError("unsupported_preference_size_or_type")
        data = source.read(MAX_PREFERENCE_BYTES + 1)
        after = os.fstat(source.fileno())
    if len(data) > MAX_PREFERENCE_BYTES or signature(before) != signature(after) or signature(after) != signature(path.stat()):
        raise ContractError("source_changed_during_capture")
    return data


def private_write(path, data):
    """Write a new private artifact, refusing to overwrite an existing file."""
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as target:
        target.write(data)
        target.flush()
        os.fsync(target.fileno())


def copy_media(path, blobs):
    """Copy exact bytes in bounded chunks while checking source consistency and destination hash."""
    temporary = blobs / "copy.tmp"
    hasher = hashlib.sha256()
    size = 0
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags), "rb") as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode):
            raise ContractError("unsupported_media_type")
        with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as target:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                hasher.update(chunk)
                target.write(chunk)
                size += len(chunk)
            target.flush()
            os.fsync(target.fileno())
        after = os.fstat(source.fileno())
    if signature(before) != signature(after) or signature(after) != signature(path.stat()):
        raise ContractError("source_changed_during_capture")
    name = hasher.hexdigest() + ".bin"
    destination = blobs / name
    if destination.exists():
        temporary.unlink()
    else:
        temporary.rename(destination)
    return name, hasher.hexdigest(), size


def walk_json(value):
    """Inspect nested source metadata without executing decoders, migrations or review decisions."""
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_json(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_json(child)


def diagnostic(code, key=None, path=None):
    """Describe a capture issue without copying private source values into the report."""
    return {"code": code, "store_key": key, "source_relative_path": path}


def inspect_json_store(key, value, diagnostics):
    """Read JSON source bytes for preflight only, keeping their original bytes untouched."""
    if not isinstance(value, bytes):
        diagnostics.append(diagnostic("unexpected_store_type", key))
        return None
    try:
        decoded = json.loads(value.decode("utf-8"), object_pairs_hook=unique_object,
                             parse_float=finite_float, parse_constant=reject_constant)
    except (ValueError, UnicodeError, RecursionError):
        diagnostics.append(diagnostic("unreadable_json_store", key))
        return None
    if not isinstance(decoded, JSON_STORES[key]):
        diagnostics.append(diagnostic("unexpected_store_shape", key))
        return None
    if isinstance(decoded, dict) and "version" in decoded and (type(decoded["version"]) is not int or decoded["version"] != 1):
        diagnostics.append(diagnostic("unsupported_store_version", key))
    return decoded


def inspect_native_store(key, value, diagnostics):
    """Report incompatible saved primitive types instead of coercing them into defaults."""
    boolean_keys = {"Plenact.CardCovers.enabled", "Plenact.ActivityShowsCovers",
                    "Plenact.ActivityRecentSquareCards", "Plenact.LibraryShowsCollectionPreviews",
                    "Plenact.LibraryScrollsCollectionPreviews"}
    valid = True
    if key in boolean_keys:
        valid = type(value) is bool
    elif key == "Plenact.SavedCardIDs.v1":
        valid = isinstance(value, list) and all(type(item) is int for item in value)
    elif key == "Plenact.RecentSearches.v1":
        valid = isinstance(value, list) and all(isinstance(item, str) for item in value)
    elif key in {"Plenact.LocalReactionAuthor.v1", "Plenact.BoardPresentation.v1"}:
        valid = isinstance(value, str)
    elif key == "Plenact.LastViewedList.v1":
        valid = type(value) is int
    if not valid:
        diagnostics.append(diagnostic("unexpected_native_store_type", key))


def media_references(key, decoded):
    """Locate known filename fields using their source model context rather than guessing directories."""
    for node in walk_json(decoded):
        for field in ("fileName", "drawingFileName", "avatarPhotoFileName", "photoFileName"):
            name = node.get(field)
            if name is None:
                continue
            if not isinstance(name, str) or not name or Path(name).name != name or "\\" in name or name in (".", ".."):
                yield None
                continue
            if field == "avatarPhotoFileName":
                directory = MEDIA_ROOTS[1]
            elif field in ("fileName", "drawingFileName"):
                directory = MEDIA_ROOTS[0]
            elif "material" in node:
                directory = MEDIA_ROOTS[2]
            elif "preset" in node:
                directory = MEDIA_ROOTS[3]
            else:
                yield None
                continue
            yield directory + "/" + name


def source_media_inventory(root):
    """List only app-owned media areas; reject symlinks and nonregular file entries."""
    files = []
    for directory in MEDIA_ROOTS:
        current = root
        for part in PurePosixPath(directory).parts:
            current = current / part
            if current.is_symlink():
                raise ContractError("symlink_not_allowed")
        if not current.exists():
            continue
        if not current.is_dir():
            raise ContractError("unsupported_media_type")
        for path in sorted(current.rglob("*")):
            if path.is_symlink():
                raise ContractError("symlink_not_allowed")
            if path.is_file():
                files.append(path.relative_to(root).as_posix())
            elif not path.is_dir():
                raise ContractError("unsupported_media_type")
    return files


def validate_capture(output):
    """Verify an existing capture's schema, value wrappers, hashes and exact media sizes."""
    output = Path(output).resolve()
    manifest = load_json(checked_file(output, "manifest.json"))
    schema = load_json(CONTRACTS / "read-only-capture.schema.json")
    validate_instance(manifest, schema, "read-only-capture.schema.json")
    if (manifest["status"] == "captured") != (not manifest["diagnostics"]):
        raise ContractError("inconsistent_capture_status")
    keys = [entry["key"] for entry in manifest["stores"]]
    paths = [entry["source_relative_path"] for entry in manifest["files"]]
    if len(keys) != len(set(keys)) or len(paths) != len(set(paths)):
        raise ContractError("duplicate_capture_entry")
    for entry in manifest["stores"]:
        data = checked_file(output, entry["value_file"]).read_bytes()
        if digest(data) != entry["sha256"]:
            raise ContractError("capture_integrity_mismatch")
        wrapper = plistlib.loads(data)
        if not isinstance(wrapper, dict) or set(wrapper) != {"value"}:
            raise ContractError("invalid_capture_value")
    for entry in manifest["files"]:
        relative = entry["source_relative_path"]
        parts = PurePosixPath(relative)
        if parts.is_absolute() or ".." in parts.parts or "\\" in relative or not any(relative.startswith(root + "/") for root in MEDIA_ROOTS):
            raise ContractError("unsafe_capture_path")
        path = checked_file(output, entry["blob_file"])
        hasher = hashlib.sha256()
        size = 0
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                hasher.update(chunk)
                size += len(chunk)
        if hasher.hexdigest() != entry["sha256"] or str(size) != entry["byte_length"]:
            raise ContractError("capture_integrity_mismatch")
    return manifest


def capture(snapshot, output):
    """Capture a caller-supplied frozen backup into a new private output directory.

    Inputs are Preferences.plist plus optional app-owned media directories. This
    function never opens live UserDefaults or writes to the snapshot. It records
    capture success separately from Model 1.0 conversion, which remains incomplete.
    """
    snapshot_input = Path(snapshot).absolute()
    if snapshot_input.is_symlink():
        raise ContractError("symlink_not_allowed")
    snapshot = snapshot_input.resolve(strict=True)
    # Capture format 1 cannot represent the newer native identity/preview evidence.
    # Refuse rather than silently dropping it; the original native folder is the recovery artifact.
    for relative in ("Migration", "MigrationPreview", "Library/Application Support/PlenactMigration"):
        if (snapshot / relative).exists() or (snapshot / relative).is_symlink():
            raise ContractError("capture_v1_cannot_preserve_native_migration_state")
    output = Path(output).absolute()
    if output.exists() or output.is_symlink():
        raise ContractError("output_already_exists")
    if inside(output.resolve(), snapshot) or inside(snapshot, output.resolve()):
        raise ContractError("input_output_overlap")
    preference_file = checked_file(snapshot, "Preferences.plist")
    preference_bytes = read_stable(preference_file)
    try:
        preferences = plistlib.loads(preference_bytes)
    except (ValueError, TypeError, OverflowError) as error:
        raise ContractError("unreadable_preference_domain") from error
    if not isinstance(preferences, dict):
        raise ContractError("unexpected_preference_domain")
    inventory = source_media_inventory(snapshot)
    output.mkdir(mode=0o700, exist_ok=False)
    try:
        (output / "Values").mkdir(mode=0o700)
        (output / "Blobs").mkdir(mode=0o700)
        stores, files, diagnostics, excluded = [], [], [], []
        decoded_stores = []
        for key in sorted(preferences):
            value = preferences[key]
            classification = "user_data"
            if key in DEVICE_STORES or key.startswith(("Plenact.BoardViewport.v1.", "plenact.creationDraft.")):
                classification = "device_state"
            elif key in RECOVERY_STORES:
                classification = "recovery"
                if key == "Plenact.DailyReviewTransaction.v1":
                    diagnostics.append(diagnostic("pending_recovery_transaction", key))
            elif key not in JSON_STORES and key not in NATIVE_STORES:
                excluded.append(key)
                if not key.startswith(("NS", "Apple")):
                    diagnostics.append(diagnostic("unclassified_preference", key))
                continue
            data = plistlib.dumps({"value": value}, fmt=plistlib.FMT_BINARY, sort_keys=True)
            name = digest(key.encode("utf-8")) + ".plist"
            private_write(output / "Values" / name, data)
            stores.append({"key": key, "value_file": "Values/" + name,
                           "sha256": digest(data), "classification": classification})
            if key in NATIVE_STORES or key in DEVICE_STORES:
                inspect_native_store(key, value, diagnostics)
            if key in JSON_STORES:
                decoded = inspect_json_store(key, value, diagnostics)
                if decoded is not None:
                    decoded_stores.append((key, decoded))
        for relative in inventory:
            path = checked_file(snapshot, relative)
            name, sha, size = copy_media(path, output / "Blobs")
            files.append({"source_relative_path": relative, "blob_file": "Blobs/" + name,
                          "sha256": sha, "byte_length": str(size)})
        for key, decoded in decoded_stores:
            for relative in media_references(key, decoded):
                if relative is None:
                    diagnostics.append(diagnostic("unresolved_media_reference", key))
                elif relative not in inventory:
                    diagnostics.append(diagnostic("missing_media_file", key, relative))
        if read_stable(preference_file) != preference_bytes or source_media_inventory(snapshot) != inventory:
            raise ContractError("source_changed_during_capture")
        # Confirm every source media file still has the exact bytes copied above.
        for entry in files:
            source = checked_file(snapshot, entry["source_relative_path"])
            hasher = hashlib.sha256()
            with source.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    hasher.update(chunk)
            if hasher.hexdigest() != entry["sha256"]:
                raise ContractError("source_changed_during_capture")
        manifest = {"export_format": "plenact.read-only-capture", "capture_format_version": 1,
                    "target_user_data_model_version": "1.0", "portable_conversion_complete": False,
                    "status": "needs_review" if diagnostics else "captured",
                    "source_preference_sha256": digest(preference_bytes), "source_preservation_verified": True,
                    "stores": stores, "files": files, "excluded_keys": excluded, "diagnostics": diagnostics}
        private_write(output / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
        validate_capture(output)
        return manifest
    except BaseException:
        shutil.rmtree(output)
        raise


def main():
    """Capture an explicit frozen backup or verify an existing private capture directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify", type=Path)
    args = parser.parse_args()
    try:
        if args.verify is not None:
            if args.snapshot is not None or args.output is not None:
                parser.error("Use --verify alone.")
            manifest = validate_capture(args.verify)
        else:
            if args.snapshot is None or args.output is None:
                parser.error("Supply --snapshot and --output, or --verify.")
            manifest = capture(args.snapshot, args.output)
        print(f"Capture {manifest['status']}: {len(manifest['stores'])} stores, {len(manifest['files'])} files, "
              f"{len(manifest['diagnostics'])} issues. Model 1.0 conversion: incomplete.")
        return 2 if manifest["diagnostics"] else 0
    except (ContractError, OSError, ValueError) as error:
        code = error.code if isinstance(error, ContractError) else type(error).__name__
        print(f"Capture failed: {code}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
