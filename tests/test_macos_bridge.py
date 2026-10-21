"""Exercise the native app's real JSON boundary with synthetic recordings."""
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from test_converter import RecordingDir

BRIDGE = Path(__file__).resolve().parents[1] / 'macos' / 'bridge.py'


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.fixture = RecordingDir(frames=600)
        self.addCleanup(self.fixture.cleanup)
        self.path = self.fixture.write()

    def call(self, action, **options):
        command = [os.environ['ATEM_TEST_ENGINE']] if os.environ.get('ATEM_TEST_ENGINE') else [sys.executable, str(BRIDGE)]
        environment = dict(os.environ, PYTHONHOME='', PYTHONPATH='')
        if os.environ.get('ATEM_TEST_ENGINE'):
            environment.update(PATH='', PYTHONHOME='/atem-test-no-system-python')
        result = subprocess.run(command, env=environment, input=json.dumps(dict(action=action, path=str(self.path), **options)), capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_inspect_convert_and_replace(self):
        original = self.path.read_bytes()
        inspected = self.call('inspect')
        self.assertTrue(inspected['ok'], inspected)
        rec = inspected['recording']
        self.assertEqual(rec['soundtrack'], 'Show CAM 1.wav')
        self.assertEqual(len(rec['cameras']), 4)
        output = self.path.with_suffix('.fcpxml')
        self.assertFalse(output.exists())
        choices = dict(cameras=[1, 2], soundtrack='Show MIC 1.wav', extras=[])
        converted = self.call('convert', **choices)
        self.assertTrue(converted['ok'], converted)
        self.assertIn('MIC 1', output.read_text())
        saved = output.read_bytes()
        self.assertFalse(self.call('convert', **choices)['ok'])
        self.assertEqual(output.read_bytes(), saved)
        self.assertTrue(self.call('convert', replace=True, **choices)['ok'])
        self.assertEqual(self.path.read_bytes(), original)

    def test_invalid_input_and_no_camera(self):
        self.assertFalse(self.call('convert', cameras=[])['ok'])
        self.path.write_text('not an ATEM log')
        self.assertFalse(self.call('inspect')['ok'])
