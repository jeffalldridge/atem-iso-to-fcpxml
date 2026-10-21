"""Release and installation checks use temporary bundles, never installed applications."""
import importlib.util
import shutil
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReleaseToolsTests(unittest.TestCase):
    def test_all_version_declarations_are_checked(self):
        checker = load('check_release')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for relative in ('Resources/Info.plist', 'Sources/ATEMConverter/FCPXML.swift', 'atem_iso_to_fcpxml.py', 'pyproject.toml'):
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            version = plistlib.loads((root / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
            tag = 'v' + version
            checker.check(tag, root)
            with self.assertRaises(ValueError):
                checker.check('main', root)
            project = root / 'pyproject.toml'
            project.write_text(project.read_text().replace('version = "' + version + '"', 'version = "999.999.999"'))
            with self.assertRaisesRegex(ValueError, 'pyproject.toml'):
                checker.check(tag, root)

    def test_install_failure_keeps_working_bundle(self):
        installer = load('build_quick_action')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, target = root / 'source.workflow', root / 'installed.workflow'
            source.mkdir(); target.mkdir()
            (source / 'version').write_text('new')
            (target / 'version').write_text('old')
            (target / 'obsolete').write_text('old')
            with patch.object(installer.shutil, 'copytree', side_effect=OSError('disk full')):
                with self.assertRaises(OSError):
                    installer.install_bundle(source, target)
            self.assertEqual((target / 'version').read_text(), 'old')
            original_rename = Path.rename
            def fail_publish(path, destination):
                if path.name == 'new.workflow':
                    raise OSError('publish failed')
                return original_rename(path, destination)
            with patch.object(Path, 'rename', autospec=True, side_effect=fail_publish):
                with self.assertRaises(OSError):
                    installer.install_bundle(source, target)
            self.assertEqual((target / 'version').read_text(), 'old')
            installer.install_bundle(source, target)
            self.assertEqual((target / 'version').read_text(), 'new')
            self.assertFalse((target / 'obsolete').exists())
            self.assertEqual(sorted(p.name for p in root.iterdir()), ['installed.workflow', 'source.workflow'])
