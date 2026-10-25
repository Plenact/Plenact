"""Reproduce the first native migration timezone projection from pinned IANA data.

Supported User Data Model versions: 1.0; private timezone-projection format 1.
Supports America/Chicago and Etc/UTC only, 1900 through 2100. Not a general tzdb replacement.
The six-hour scan/binary search is deliberately scoped to these known zone histories.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from zoneinfo import ZoneInfo, reset_tzpath
import tzdata

ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / "Src/Persistence/MigrationTimeZoneRules.json"


def build():
    """Project exact-second offset transitions for the explicitly supported migration zones."""
    if tzdata.IANA_VERSION != "2025b":
        raise ValueError("Install the pinned tooling requirements before rebuilding migration rules")
    reset_tzpath([])
    start = int(datetime(1900, 1, 1, tzinfo=timezone.utc).timestamp())
    end = int(datetime(2101, 1, 1, tzinfo=timezone.utc).timestamp())
    zones = {}
    for name in ("America/Chicago", "Etc/UTC"):
        zone = ZoneInfo(name)
        def offset(instant):
            return int(datetime.fromtimestamp(instant, timezone.utc).astimezone(zone).utcoffset().total_seconds())
        rows = [[start, offset(start)]]
        instant = start
        while instant < end:
            following = min(end, instant + 21_600)
            if offset(following) != rows[-1][1]:
                left, right = instant, following
                while right - left > 1:
                    middle = (left + right) // 2
                    if offset(middle) == rows[-1][1]:
                        left = middle
                    else:
                        right = middle
                rows.append([right, offset(right)])
            instant = following
        zones[name] = rows
    return {"supported_user_data_model_versions": ["1.0"], "format": "plenact.migration-timezone-projection",
            "format_version": 1, "tzdb_version": "2025b", "start_epoch": start, "end_epoch": end, "zones": zones}


def main():
    """Check reproducibility by default, or explicitly replace only the generated source resource."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    data = (json.dumps(build(), separators=(",", ":")) + "\n").encode()
    if args.write:
        DESTINATION.write_bytes(data)
    elif DESTINATION.read_bytes() != data:
        raise ValueError("Migration timezone resource differs from pinned generation")
    print("Verified pinned native migration timezone projection (IANA 2025b).")


if __name__ == "__main__":
    main()
