#!/usr/bin/env python3
"""Build (and optionally install) the Finder Quick Action.

The Quick Action is an Automator workflow whose single "Run Shell Script" step contains the whole
converter, so the ``.workflow`` bundle is self-contained: double-click it and macOS offers to install it.

    python3 scripts/build_quick_action.py            # rebuild quick-action/ATEM ISO to FCPXML.workflow
    python3 scripts/build_quick_action.py --check    # fail if the committed bundle is out of date (CI)
    python3 scripts/build_quick_action.py --install  # copy it into ~/Library/Services
    python3 scripts/build_quick_action.py --zip dist/ATEM-ISO-to-FCPXML-Quick-Action.zip
"""
from __future__ import annotations

import argparse
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONVERTER = ROOT / "atem_iso_to_fcpxml.py"
NAME = "ATEM ISO to FCPXML"
BUNDLE = ROOT / "quick-action" / f"{NAME}.workflow"
NAMESPACE = uuid.UUID("5a0b9d1e-6c6e-4d5c-9a52-2f0f8c0e5a11")
HEREDOC = "ATEM_ISO_TO_FCPXML_PY"

SHELL = f'''#!/bin/zsh
# {NAME}: Finder Quick Action. Built by scripts/build_quick_action.py; do not edit by hand.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
if (( $# != 1 )); then
  /usr/bin/osascript -e 'display alert "{NAME}" message "Select one ATEM .drp file or its recording folder, then run the Quick Action."'
  exit 0
fi
# When the Mac app is installed, hand the recording to it; the embedded converter is the fallback.
# A copy that fails to open does not end the script, and a renamed or moved copy is found by its bundle identifier.
for app in "/Applications/{NAME}.app" "$HOME/Applications/{NAME}.app"; do
  if [[ -d "$app" ]] && /usr/bin/open -a "$app" "$@"; then
    exit 0
  fi
done
if /usr/bin/open -b com.tentstudios.atem-iso-to-fcpxml "$@" >/dev/null 2>&1; then
  exit 0
fi
if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
  /usr/bin/osascript -e 'display alert "Python 3.9 or newer is needed" message "Install the Apple Command Line Tools (open Terminal and run: xcode-select --install) or Python from python.org, then run the Quick Action again."'
  exit 1
fi
python3 - "$1" --interactive <<'{HEREDOC}'
%s
{HEREDOC}
'''


def converter_version(source: str) -> str:
    match = re.search(r'^__version__ = "([^"]+)"', source, re.MULTILINE)
    if not match:
        raise SystemExit("The converter must declare __version__")
    return match.group(1)


def build(destination: Path) -> None:
    source = CONVERTER.read_text(encoding="utf-8")
    if HEREDOC in source:
        raise SystemExit(f"The converter must not contain the heredoc marker {HEREDOC}")
    script = SHELL % source.rstrip("\n")
    action = {
        "action": {
            "AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.path"]},
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": {"COMMAND_STRING": {}, "CheckedForUserDefaultShell": {}, "inputMethod": {}, "shell": {}},
            "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": {"COMMAND_STRING": script, "CheckedForUserDefaultShell": True, "inputMethod": 1, "shell": "/bin/zsh"},
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": False,
            "CanShowWhenRun": True,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": str(uuid.uuid5(NAMESPACE, "input")).upper(),
            "OutputUUID": str(uuid.uuid5(NAMESPACE, "output")).upper(),
            "UUID": str(uuid.uuid5(NAMESPACE, "action")).upper(),
            "isViewVisible": 1,
        },
        "isViewVisible": 1,
    }
    document = {
        "AMApplicationBuild": "523",
        "AMApplicationVersion": "2.10",
        "AMDocumentVersion": "2",
        "actions": [action],
        "connectors": {},
        "workflowMetaData": {
            "applicationBundleID": "com.apple.finder",
            "applicationBundleIDsByPath": {"/System/Library/CoreServices/Finder.app": "com.apple.finder"},
            "applicationPath": "/System/Library/CoreServices/Finder.app",
            "applicationPaths": ["/System/Library/CoreServices/Finder.app"],
            "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "outputTypeIdentifier": "com.apple.Automator.nothing",
            "presentationMode": 15,
            "processesInput": 0,
            "serviceAcceptsInput": 1,
            "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": 0,
            "systemImageName": "NSTouchBarPlayTemplate",
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        },
    }
    version = converter_version(source)
    info = {
        # Finder's Get Info shows which converter this workflow embeds.
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "NSServices": [{
            "NSMenuItem": {"default": NAME},
            "NSMessage": "runWorkflowAsService",
            "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
            "NSSendFileTypes": ["public.item"],
        }]
    }
    contents = destination / "Contents"
    if destination.exists():
        shutil.rmtree(destination)
    contents.mkdir(parents=True)
    (contents / "document.wflow").write_bytes(plistlib.dumps(document, sort_keys=True))
    (contents / "Info.plist").write_bytes(plistlib.dumps(info, sort_keys=True))


def same_bundle(a: Path, b: Path) -> bool:
    for name in ("document.wflow", "Info.plist"):
        if not (a / "Contents" / name).is_file() or not (b / "Contents" / name).is_file():
            return False
        if (a / "Contents" / name).read_bytes() != (b / "Contents" / name).read_bytes():
            return False
    return True


def write_zip(bundle: Path, destination: Path) -> None:
    """Archive only generated bundle files, with stable metadata for reproducible releases."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in ("Info.plist", "document.wflow"):
            path = bundle / "Contents" / name
            item = zipfile.ZipInfo(f"{bundle.name}/Contents/{name}", date_time=(2020, 1, 1, 0, 0, 0))
            item.create_system = 3
            item.external_attr = 0o100644 << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, path.read_bytes())


def install_bundle(source: Path, target: Path) -> None:
    """Stage the replacement before moving the working workflow out of the way."""
    target.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".atem-install-", dir=target.parent))
    fresh, backup = staging / "new.workflow", staging / "previous.workflow"
    try:
        shutil.copytree(source, fresh)
        if target.exists() or target.is_symlink():
            target.rename(backup)
        try:
            fresh.rename(target)
        except OSError:
            if backup.exists() or backup.is_symlink():
                backup.rename(target)
            raise
        if backup.is_symlink() or backup.is_file():
            backup.unlink()
        elif backup.exists():
            shutil.rmtree(backup)
    finally:
        # If rollback itself failed, preserve the backup for recovery.
        if not backup.exists() and not backup.is_symlink():
            shutil.rmtree(staging)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="verify the committed bundle matches the converter")
    parser.add_argument("--install", action="store_true", help="copy the bundle into ~/Library/Services")
    parser.add_argument("--zip", type=Path, metavar="FILE", help="also write a zip of the bundle for distribution")
    args = parser.parse_args()

    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            fresh = Path(tmp) / BUNDLE.name
            build(fresh)
            if not BUNDLE.exists() or not same_bundle(fresh, BUNDLE):
                print(f"{BUNDLE.relative_to(ROOT)} is out of date; run python3 scripts/build_quick_action.py", file=sys.stderr)
                return 1
        print("Quick Action is up to date.")
        return 0

    build(BUNDLE)
    print(f"Built {BUNDLE.relative_to(ROOT)}")
    if args.zip:
        write_zip(BUNDLE, args.zip)
        print(f"Wrote {args.zip}")
    if args.install:
        if sys.platform != "darwin":
            parser.error("--install only works on macOS")
        target = Path.home() / "Library" / "Services" / BUNDLE.name
        install_bundle(BUNDLE, target)
        try:
            subprocess.run(["/System/Library/CoreServices/pbs", "-update"], check=False)
        except OSError:
            pass  # the new workflow still appears the next time Finder reads the Services folder
        print(f"Installed {target}\nFinder → right-click the .drp or its folder → Quick Actions → {NAME}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
