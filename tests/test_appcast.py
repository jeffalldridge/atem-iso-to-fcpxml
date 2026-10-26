"""Reject mismatched update metadata before it can be attached to a release."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_appcast', ROOT / 'scripts/build_appcast.py')
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class AppcastTests(unittest.TestCase):
    def test_release_metadata_is_bound_to_versioned_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'ATEM-ISO-to-FCPXML.dmg'
            archive.write_bytes(b'fixture')
            feed = Path(directory) / 'appcast.xml'
            valid = '''<!-- sparkle-signatures: fixture -->
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>1.3.0</sparkle:version><sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
<enclosure url="https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/download/v1.3.0/ATEM-ISO-to-FCPXML.dmg" length="7" sparkle:edSignature="fixture"/>
</item></channel></rss>'''
            feed.write_text(valid)
            appcast.validate_feed(feed, '1.3.0', archive)
            for invalid in [valid.replace('v1.3.0/', 'latest/'), valid.replace('length="7"', 'length="9"'),
                            valid.replace('sparkle:edSignature="fixture"', ''), valid.replace('>15.0<', '>14.0<'),
                            valid.replace('>1.3.0<', '>1.2.0<'), valid.replace('sparkle-signatures:', 'unsigned')]:
                feed.write_text(invalid)
                with self.assertRaises(ValueError):
                    appcast.validate_feed(feed, '1.3.0', archive)
