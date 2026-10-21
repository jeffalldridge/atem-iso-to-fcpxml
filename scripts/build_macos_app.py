#!/usr/bin/env python3
"""Build the local SwiftUI app; --install also updates the Finder Quick Action.

Requires macOS 13+ and Apple Command Line Tools. The app still needs Python 3.9+.
Default builds are ad-hoc signed. --bundle-python creates a self-contained app;
--sign-identity applies Developer ID signing. Notarization is a separate release step.
"""
import argparse
import ast
import plistlib
import platform
import os
import sysconfig
import importlib.metadata
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
    parser.add_argument('--bundle-python', action='store_true', help='bundle the engine and Python using PyInstaller')
    parser.add_argument('--sign-identity', help='Developer ID Application identity; defaults to ad-hoc signing')
    args = parser.parse_args()
    if args.install and subprocess.run(
            ['/usr/bin/pgrep', '-x', 'ATEMConverter'], stdout=subprocess.DEVNULL).returncode == 0:
        parser.error('Quit ATEM ISO to FCPXML before installing the update, then run this command again.')
    app = ROOT / 'build' / (NAME + '.app')
    if app.exists():
        shutil.rmtree(app)  # Never retain files from a previous build mode.
    contents = app / 'Contents'
    executable = contents / 'MacOS' / 'ATEMConverter'
    resources = contents / 'Resources'
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-O', '-target',
                    ('arm64' if platform.machine() == 'arm64' else 'x86_64') + '-apple-macosx13.0',
                    str(ROOT / 'macos/AudioSelection.swift'), str(ROOT / 'macos/ATEMApp.swift'), '-o', str(executable)], check=True)
    if args.bundle_python:
        command = [sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean', '--onedir',
                   '--name', 'atem-engine', '--paths', str(ROOT),
                   '--distpath', str(ROOT / 'build/engine-dist'),
                   '--workpath', str(ROOT / 'build/engine-work'),
                   '--specpath', str(ROOT / 'build'), str(ROOT / 'macos/bridge.py')]
        if args.sign_identity:
            command += ['--codesign-identity', args.sign_identity]
        subprocess.run(command, check=True)
        shutil.copytree(ROOT / 'build/engine-dist/atem-engine', resources / 'atem-engine', symlinks=True)
        licenses = resources / 'Licenses'
        licenses.mkdir()
        shutil.copy2(ROOT / 'LICENSE', licenses / 'ATEM-ISO-to-FCPXML.txt')
        python_license = Path(sysconfig.get_path('stdlib')) / 'LICENSE.txt'
        if not python_license.is_file():
            raise SystemExit('Python distribution is missing LICENSE.txt; use a python.org or setup-python runtime.')
        shutil.copy2(python_license, licenses / 'Python.txt')
        distribution = importlib.metadata.distribution('pyinstaller')
        license_file = next(f for f in distribution.files if str(f).endswith('licenses/COPYING.txt'))
        shutil.copy2(distribution.locate_file(license_file), licenses / 'PyInstaller.txt')
    else:
        for source in (ROOT / 'atem_iso_to_fcpxml.py', ROOT / 'macos/bridge.py'):
            shutil.copy2(source, resources / source.name)
    subprocess.run([sys.executable, str(ROOT / 'scripts/build_quick_action.py')], check=True)
    shutil.copytree(ROOT / 'quick-action' / (NAME + '.workflow'), resources / (NAME + '.workflow'))
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
                CFBundleIconFile='AppIcon', CFBundleShortVersionString=version, CFBundleVersion=os.environ.get('GITHUB_RUN_NUMBER', '3'), LSMinimumSystemVersion='13.0',
                NSHighResolutionCapable=True, ATEMBundledEngine=args.bundle_python,
                CFBundleDocumentTypes=[dict(CFBundleTypeName='ATEM Recording', CFBundleTypeRole='Viewer',
                    LSHandlerRank='Alternate', CFBundleTypeExtensions=['drp'],
                    LSItemContentTypes=['public.folder', 'com.tentstudios.atem-recording-log'])],
                UTImportedTypeDeclarations=[dict(UTTypeIdentifier='com.tentstudios.atem-recording-log',
                    UTTypeConformsTo=['public.data'], UTTypeDescription='ATEM Recording Log',
                    UTTypeTagSpecification={'public.filename-extension': ['drp']})])
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    signing = ['codesign', '--force', '--sign', args.sign_identity or '-']
    if args.sign_identity:
        signing += ['--options', 'runtime', '--timestamp']
    subprocess.run(signing + [str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
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
