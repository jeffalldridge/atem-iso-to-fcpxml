import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.install_bundle import install_bundle


class InstallTests(unittest.TestCase):
    def test_reinstall_replaces_old_files_without_duplicates(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, target = root / 'download', root / 'Applications' / 'Utility.app'
            source.mkdir()
            (source / 'version').write_text('old')
            (source / 'obsolete').write_text('old code')
            install_bundle(source, target)
            (source / 'obsolete').unlink()
            (source / 'version').write_text('new')
            install_bundle(source, target)
            self.assertEqual((target / 'version').read_text(), 'new')
            self.assertFalse((target / 'obsolete').exists())
            self.assertEqual(list(target.parent.iterdir()), [target])

    def test_failed_copy_or_rename_preserves_previous_installation(self):
        for operation in ('copy', 'rename'):
            with self.subTest(operation=operation), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source, target = root / 'source', root / 'installed'
                source.mkdir(); target.mkdir()
                (source / 'version').write_text('new')
                (target / 'version').write_text('old')
                real_replace = os.replace
                def replace(src, dst):
                    if Path(src).name == 'new':
                        raise OSError('simulated installation failure')
                    return real_replace(src, dst)
                mocked = patch('scripts.install_bundle.shutil.copytree', side_effect=OSError('copy failed')) if operation == 'copy' else patch('scripts.install_bundle.os.replace', side_effect=replace)
                with mocked, self.assertRaises(OSError):
                    install_bundle(source, target)
                self.assertEqual((target / 'version').read_text(), 'old')

    def test_symlink_destination_is_not_followed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'source'; source.mkdir()
            target = root / 'installed'; target.symlink_to(source)
            with self.assertRaises(ValueError):
                install_bundle(source, target)
            self.assertTrue(target.is_symlink())
