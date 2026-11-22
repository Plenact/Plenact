#!/usr/bin/env python3
# --------------------------------------------------------------------------------------------------
# @file       verify_contract.py
# @brief      Verify the exact published Model 1.0 inputs pinned for private staging implementation
# --------------------------------------------------------------------------------------------------
import hashlib
import json
from pathlib import Path
import sys


# @fcn verify_contract
# @brief Compare pinned files and the complete contract file set without modifying either.
def verify_contract(root: Path, manifest: dict) -> list[str]:
    errors = []
    directory = root / manifest['contract_directory']
    actual = {str(path.relative_to(root)) for path in directory.rglob('*.json')}
    expected = set(manifest['sha256'])
    for name in sorted(actual ^ expected):
        errors.append(f'Contract file set changed: {name}')
    for name, digest in manifest['sha256'].items():
        path = root / name
        if root.resolve() not in path.resolve().parents:
            errors.append('Pin contains a path outside the repository')
            continue
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            errors.append(f'Contract bytes changed: {name}')
    return errors


# @fcn main
# @brief Report whether staging still targets the reviewed Model 1.0 source contract.
def main() -> int:
    root = Path(__file__).resolve().parents[2]
    manifest = json.loads(Path(__file__).with_name('contract-pin.json').read_text())
    errors = verify_contract(root, manifest)
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f"Model {manifest['user_data_model_version']} / protocol {manifest['protocol_version']}: "
          f"{len(manifest['sha256'])} pinned JSON files verified. No deployment implied.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
