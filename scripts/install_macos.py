#!/usr/bin/env python3
"""Install a local Finder Quick Action. No administrator access or network needed."""
import argparse
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import uuid


def install(destination: Path, runtime: Path) -> None:
    destination = destination.expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parents[1] / "atem_iso_to_fcpxml.py"
    shutil.copy2(source, destination / source.name)
    launcher = destination / "convert.command"
    launcher.write_text('''#!/bin/zsh
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
if (( $# != 1 )); then
  /usr/bin/osascript -e 'display alert "Select one ATEM DRP or recording folder."'
  exit 2
fi
''' + 'result=$( ' + shlex.quote(str(runtime)) + ' ' + shlex.quote(str(destination / source.name)) + ' "$1" --choose-audio --unique-output 2>&1 )\nstatus_code=$?\n' + '''if (( status_code != 0 )); then
  /usr/bin/osascript -e 'on run argv' -e 'display alert "ATEM conversion stopped" message (item 1 of argv)' -e 'end run' "$result"
  exit "$status_code"
fi
/usr/bin/osascript -e 'on run argv' -e 'display dialog (item 1 of argv) with title "ATEM ISO to FCPXML" buttons {"OK"} default button "OK"' -e 'end run' "$result"
''')
    launcher.chmod(0o755)
    workflow = destination / "ATEM ISO to FCPXML.workflow"
    contents = workflow / "Contents"
    contents.mkdir(parents=True, exist_ok=True)
    script = shlex.quote(str(launcher)) + ' "$@"'
    action = {"action": {"AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.path"]},
        "AMActionVersion": "2.0.3", "AMApplication": ["Automator"], "AMParameterProperties": {"COMMAND_STRING": {}, "CheckedForUserDefaultShell": {}, "inputMethod": {}, "shell": {}},
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]}, "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script", "ActionParameters": {"COMMAND_STRING": script, "CheckedForUserDefaultShell": True, "inputMethod": 1, "shell": "/bin/zsh"},
        "BundleIdentifier": "com.apple.RunShellScript", "CFBundleVersion": "2.0.3", "CanShowSelectedItemsWhenRun": False,
        "CanShowWhenRun": True, "Category": ["AMCategoryUtilities"], "Class Name": "RunShellScriptAction", "InputUUID": str(uuid.uuid4()),
        "OutputUUID": str(uuid.uuid4()), "UUID": str(uuid.uuid4()), "isViewVisible": 1}, "isViewVisible": 1}
    document = {"AMApplicationBuild": "523", "AMApplicationVersion": "2.10", "AMDocumentVersion": "2", "actions": [action], "connectors": {},
        "workflowMetaData": {"applicationBundleID": "com.apple.finder", "applicationBundleIDsByPath": {"/System/Library/CoreServices/Finder.app": "com.apple.finder"},
            "applicationPath": "/System/Library/CoreServices/Finder.app", "applicationPaths": ["/System/Library/CoreServices/Finder.app"],
            "inputTypeIdentifier": "com.apple.Automator.fileSystemObject", "outputTypeIdentifier": "com.apple.Automator.nothing",
            "presentationMode": 15, "processesInput": 0, "serviceAcceptsInput": 1, "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing", "serviceProcessesInput": 0, "systemImageName": "NSTouchBarPlayTemplate", "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"}}
    (contents / "document.wflow").write_bytes(plistlib.dumps(document))
    info = {"NSServices": [{"NSMenuItem": {"default": "ATEM ISO to FCPXML"}, "NSMessage": "runWorkflowAsService",
            "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"}, "NSSendFileTypes": ["public.item"]}]}
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    print(f"Built {workflow}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path.home()/"Library/Application Support/ATEM ISO to FCPXML")
    parser.add_argument("--build-only", action="store_true", help="Build without registering the Quick Action")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("macOS is required")
    runtime = Path(sys.executable).resolve()
    install(args.destination, runtime)
    if not args.build_only:
        services = Path.home()/"Library/Services"
        services.mkdir(parents=True, exist_ok=True)
        target = services/"ATEM ISO to FCPXML.workflow"
        source = args.destination.expanduser().resolve()/target.name
        if target.exists() or target.is_symlink():
            if not target.is_symlink() or target.resolve() != source:
                parser.error(f"Refusing to replace an existing unrelated service: {target}")
        else:
            target.symlink_to(source)
        subprocess.run(["/System/Library/CoreServices/pbs", "-update"], check=False)
        print("Installed. Finder → right-click a DRP/folder → Quick Actions → ATEM ISO to FCPXML")


if __name__ == "__main__":
    main()
