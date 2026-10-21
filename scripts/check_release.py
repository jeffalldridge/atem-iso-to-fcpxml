#!/usr/bin/env python3
"""Require a version tag that agrees with every distributed version declaration."""
import plistlib
import re
import sys
from pathlib import Path


def check(tag, root):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Run releases from a vX.Y.Z tag, including manual dispatches.")
    expected = tag[1:]
    plist = plistlib.loads((root / "Resources/Info.plist").read_bytes())
    versions = {key: plist[key] for key in ("CFBundleShortVersionString", "CFBundleVersion")}
    for path, pattern in (
        ("atem_iso_to_fcpxml.py", r'^__version__ = "([^"]+)"'),
        ("Sources/ATEMConverter/FCPXML.swift", r'converterVersion = "([^"]+)"'),
        ("pyproject.toml", r'^version = "([^"]+)"'),
    ):
        match = re.search(pattern, (root / path).read_text(), re.MULTILINE)
        if not match:
            raise ValueError("Missing version in " + path)
        versions[path] = match.group(1)
    for location, version in versions.items():
        if version != expected:
            raise ValueError(f"{location}: {version} does not match {tag}")
    return versions


if __name__ == "__main__":
    try:
        check(sys.argv[1] if len(sys.argv) == 2 else "", Path(__file__).resolve().parents[1])
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
    print("Release versions match.")
