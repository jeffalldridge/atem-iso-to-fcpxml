#!/usr/bin/env python3
"""Build the local SwiftUI app; --install also updates the Finder Quick Action.

Requires macOS 13+ and Apple Command Line Tools. The app still needs Python 3.9+.
This development build is ad-hoc signed, not notarized for public distribution.
"""
import argparse
import ast
import plistlib
import platform
import shutil
import subprocess
import sys
from pathlib import Path

if __package__:
    from .install_bundle import install_bundle
else:
    from install_bundle import install_bundle

ROOT = Path(__file__).resolve().parents[1]
NAME = 'ATEM ISO to FCPXML'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    if args.install and subprocess.run(
            ['/usr/bin/pgrep', '-x', 'ATEMConverter'], stdout=subprocess.DEVNULL).returncode == 0:
        parser.error('Quit ATEM ISO to FCPXML before installing the update, then run this command again.')
    app = ROOT / 'build' / (NAME + '.app')
    contents = app / 'Contents'
    executable = contents / 'MacOS' / 'ATEMConverter'
    resources = contents / 'Resources'
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-O', '-target',
                    ('arm64' if platform.machine() == 'arm64' else 'x86_64') + '-apple-macosx13.0',
                    str(ROOT / 'macos/AudioSelection.swift'), str(ROOT / 'macos/ATEMApp.swift'), '-o', str(executable)], check=True)
    for source in (ROOT / 'atem_iso_to_fcpxml.py', ROOT / 'macos/bridge.py'):
        shutil.copy2(source, resources / source.name)
    iconset = ROOT / 'build' / 'AppIcon.iconset'
    iconset.mkdir(exist_ok=True)
    master = ROOT / 'build' / 'app-icon.png'
    subprocess.run(['xcrun', 'swift', str(ROOT / 'macos/MakeIcon.swift'), str(master)], check=True)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
            subprocess.run(['sips', '-z', str(size * scale), str(size * scale), str(master),
                            '--out', str(iconset / name)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'AppIcon.icns')], check=True)
    module = ast.parse((ROOT / 'atem_iso_to_fcpxml.py').read_text())
    version = next(node.value.value for node in module.body if isinstance(node, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == '__version__' for t in node.targets))
    info = dict(CFBundleName=NAME, CFBundleDisplayName=NAME, CFBundleExecutable='ATEMConverter',
                CFBundleIdentifier='com.tentstudios.atem-iso-to-fcpxml', CFBundlePackageType='APPL',
                CFBundleIconFile='AppIcon', CFBundleShortVersionString=version, CFBundleVersion='2', LSMinimumSystemVersion='13.0',
                NSHighResolutionCapable=True,
                CFBundleDocumentTypes=[dict(CFBundleTypeName='ATEM Recording', CFBundleTypeRole='Viewer',
                    LSHandlerRank='Alternate', CFBundleTypeExtensions=['drp'],
                    LSItemContentTypes=['public.folder', 'com.tentstudios.atem-recording-log'])],
                UTImportedTypeDeclarations=[dict(UTTypeIdentifier='com.tentstudios.atem-recording-log',
                    UTTypeConformsTo=['public.data'], UTTypeDescription='ATEM Recording Log',
                    UTTypeTagSpecification={'public.filename-extension': ['drp']})])
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    if args.install:
        target = Path.home() / 'Applications' / app.name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink() or (target.exists() and not target.is_dir()):
            parser.error(f'Installation destination is not an app directory: {target}')
        if target.exists():
            backup = ROOT / 'local' / 'app-backups' / app.name
            backup.parent.mkdir(parents=True, exist_ok=True)
            if backup.exists():
                shutil.rmtree(backup)
            shutil.copytree(target, backup)
        install_bundle(app, target)
        subprocess.run([sys.executable, str(ROOT / 'scripts/build_quick_action.py'), '--install'], check=True)
        print('Installed', target)
    else:
        print('Built', app)


if __name__ == '__main__':
    main()
