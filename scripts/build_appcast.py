#!/usr/bin/env python3
"""Create a signed Sparkle feed for the finished, notarized GitHub release DMG."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'https://github.com/jeffalldridge/atem-iso-to-fcpxml'
NAMESPACE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def validate_feed(path, version, archive):
    root = ET.parse(path).getroot()
    items = root.findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected exactly one release in the appcast.')
    item = items[0]
    enclosure = item.find('enclosure')
    expected_url = f'{REPOSITORY}/releases/download/v{version}/{archive.name}'
    if item.findtext(NAMESPACE + 'version') != version or enclosure is None:
        raise ValueError('Appcast version does not match the release.')
    if enclosure.get('url') != expected_url:
        raise ValueError('Appcast must download the versioned GitHub release asset.')
    if enclosure.get('length') != str(archive.stat().st_size) or not enclosure.get(NAMESPACE + 'edSignature'):
        raise ValueError('Appcast archive size or signature is missing.')
    if item.findtext(NAMESPACE + 'minimumSystemVersion') != '15.0':
        raise ValueError('Appcast must preserve the minimum macOS version.')
    if b'sparkle-signatures:' not in path.read_bytes():
        raise ValueError('The appcast itself must be signed.')


def build(archive, output):
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    version = info['CFBundleVersion']
    if not archive.is_file():
        raise ValueError('Build and notarize the disk image before generating its feed.')
    tool = ROOT / '.build/artifacts/sparkle/Sparkle/bin/generate_appcast'
    with tempfile.TemporaryDirectory(prefix='atem-appcast-') as directory:
        staging = Path(directory)
        shutil.copy2(archive, staging / archive.name)
        command = [str(tool), '--download-url-prefix', f'{REPOSITORY}/releases/download/v{version}/',
                   '--maximum-deltas', '0', '--link', f'{REPOSITORY}/releases/tag/v{version}',
                   '-o', str(staging / 'appcast.xml')]
        # Pass the CI key through stdin, never command arguments or log output.
        secret = os.environ.get('SPARKLE_PRIVATE_KEY')
        if secret:
            command += ['--ed-key-file', '-']
        else:
            command += ['--account', 'com.tentstudios.atem-iso-to-fcpxml']
        command.append(str(staging))
        subprocess.run(command, input=secret, text=True, check=True)
        validate_feed(staging / 'appcast.xml', version, archive)
        verifier = [str(tool.with_name('sign_update')), '--verify']
        verifier += ['--ed-key-file', '-'] if secret else ['--account', 'com.tentstudios.atem-iso-to-fcpxml']
        subprocess.run(verifier + [str(staging / 'appcast.xml')], input=secret, text=True, check=True)
        enclosure = ET.parse(staging / 'appcast.xml').find('./channel/item/enclosure')
        subprocess.run(verifier + [str(archive), enclosure.get(NAMESPACE + 'edSignature')],
                       input=secret, text=True, check=True)
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(staging / 'appcast.xml', output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=ROOT / 'build/ATEM-ISO-to-FCPXML.dmg')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/appcast.xml')
    args = parser.parse_args()
    build(args.archive.resolve(), args.output.resolve())
