#!/usr/bin/env python3
"""Notarize a signed app and disk image with credentials supplied by CI."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(args, check=True)


def main():
    required = ('NOTARY_PRIVATE_KEY', 'NOTARY_KEY_ID', 'NOTARY_ISSUER_ID', 'SIGNING_IDENTITY')
    for name in required:
        if not os.environ.get(name):
            raise SystemExit(f'Missing release credential: {name}')
    app = ROOT / 'build/ATEM ISO to FCPXML.app'
    with tempfile.TemporaryDirectory(prefix='atem-notary-') as tmp:
        key = Path(tmp) / 'AuthKey.p8'
        key.write_text(os.environ['NOTARY_PRIVATE_KEY'])
        key.chmod(0o600)
        auth = ['--key', str(key), '--key-id', os.environ['NOTARY_KEY_ID'],
                '--issuer', os.environ['NOTARY_ISSUER_ID']]
        archive = Path(tmp) / 'app.zip'
        run('ditto', '-c', '-k', '--keepParent', str(app), str(archive))
        run('xcrun', 'notarytool', 'submit', str(archive), *auth, '--wait', '--timeout', '20m')
        # A successful upload alone is insufficient; stapling/validation must pass.
        run('xcrun', 'stapler', 'staple', str(app))
        run('xcrun', 'stapler', 'validate', str(app))
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', str(app))
        run(sys.executable, str(ROOT / 'scripts/package_macos_app.py'))
        images = list((ROOT / 'dist').glob('ATEM-ISO-to-FCPXML-*.dmg'))
        if len(images) != 1:
            raise SystemExit('Expected exactly one disk image in dist.')
        dmg = str(images[0])
        run('codesign', '--force', '--timestamp', '--sign', os.environ['SIGNING_IDENTITY'], dmg)
        run('xcrun', 'notarytool', 'submit', dmg, *auth, '--wait', '--timeout', '20m')
        run('xcrun', 'stapler', 'staple', dmg)
        run('xcrun', 'stapler', 'validate', dmg)


if __name__ == '__main__':
    main()
