#!/usr/bin/env python3
"""Package the built app as a drag-to-Applications disk image (no credentials)."""
import argparse
import platform
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAME = 'ATEM ISO to FCPXML'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    app = ROOT / 'build' / (NAME + '.app')
    if not (app / 'Contents/Resources/atem-engine/atem-engine').is_file():
        parser.error('Build with --bundle-python before packaging a download.')
    arch = 'Apple-Silicon' if platform.machine() == 'arm64' else 'Intel'
    output = (args.output or ROOT / 'dist' / f'ATEM-ISO-to-FCPXML-{arch}.dmg').resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='atem-dmg-') as tmp:
        stage = Path(tmp)
        shutil.copytree(app, stage / app.name, symlinks=True)
        (stage / 'Applications').symlink_to('/Applications')
        (stage / 'Read me.txt').write_text(
            'ATEM ISO to FCPXML\n\n'
            '1. Quit any older copy of the app.\n'
            '2. Drag the app to Applications. Choose Replace when updating.\n'
            '3. Open the app from Applications and choose your ATEM recording.\n\n'
            'Python is included. No developer tools are needed.\n'
            'For Finder integration, choose Install Finder Quick Action from the app menu.\n'
            'If you used the early source preview in your user Applications folder, move that old copy to Trash.\n\n'
            'https://jeffalldridge.github.io/atem-iso-to-fcpxml/\n', encoding='utf-8')
        subprocess.run(['hdiutil', 'create', '-volname', NAME, '-srcfolder', str(stage),
                        '-format', 'UDZO', '-ov', str(output)], check=True)
    print(output)


if __name__ == '__main__':
    main()
