#!/usr/bin/env python3
"""Validate tagged changelog coverage and extract curated GitHub Release notes."""

import argparse
from datetime import date
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TAG = re.compile(r"v\d+\.\d+(?:\.\d+)?\Z")
HEADING = re.compile(r"^## (Unreleased|v\d+\.\d+(?:\.\d+)?)(?: — (\d{4}-\d{2}-\d{2}))?$", re.MULTILINE)


def entries(text):
    """Read distinct, dated release sections without including adjacent versions."""
    headings = list(HEADING.finditer(text))
    result = {}
    for index, heading in enumerate(headings):
        tag, stamp = heading.groups()
        if tag in result:
            raise ValueError(f"Duplicate changelog heading: {tag}")
        if tag != "Unreleased":
            if not stamp:
                raise ValueError(f"Missing version date: {tag}")
            date.fromisoformat(stamp)
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        body = text[heading.end():end].strip()
        if not body or not re.search(r"^- .+", body, re.MULTILINE):
            raise ValueError(f"Missing release details: {tag}")
        result[tag] = (stamp, body)
    return result


def main():
    """Check all local release tags, or extract exactly one existing tagged entry."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--changelog", type=Path, default=ROOT / "CHANGELOG.md")
    parser.add_argument("--check", action="store_true", help="Require notes for every local version tag")
    parser.add_argument("--tag", help="Existing repository tag whose notes should be extracted")
    parser.add_argument("--output", type=Path, help="Write extracted notes to this file")
    args = parser.parse_args()
    if not args.check and not args.tag:
        parser.error("Specify --check, --tag, or both")
    if args.output and not args.tag:
        parser.error("--output requires --tag")
    try:
        sections = entries(args.changelog.read_text(encoding="utf-8"))
        tags = set(subprocess.check_output(["git", "tag", "--list"], cwd=ROOT, text=True).splitlines())
        versions = {tag for tag in tags if TAG.fullmatch(tag)}
        if args.check:
            missing = versions - sections.keys()
            extra = sections.keys() - versions - {"Unreleased"}
            if missing or extra:
                raise ValueError(f"Missing tag notes: {sorted(missing)}; entries without tags: {sorted(extra)}")
            print(f"Validated {len(versions)} tagged versions.")
        if args.tag:
            if not TAG.fullmatch(args.tag) or args.tag not in tags:
                raise ValueError("--tag must name an existing vMAJOR.MINOR or vMAJOR.MINOR.PATCH tag")
            if args.tag not in sections:
                raise ValueError(f"No curated notes for {args.tag}")
            stamp, body = sections[args.tag]
            notes = f"Version date: {stamp} (tagged commit).\n\n{body}\n"
            if args.output:
                args.output.write_text(notes, encoding="utf-8")
            else:
                print(notes, end="")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release notes error: {error}\n")


if __name__ == "__main__":
    main()
