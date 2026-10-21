"""Replace one installed bundle without merging files from an older version."""
import os
import shutil
import tempfile
from pathlib import Path


def install_bundle(source: Path, target: Path) -> None:
    """Stage on the destination volume; roll back if the final rename fails.

    The target must be a real bundle directory. Never follow a destination
    symlink or silently replace an unrelated file. Callers must quit apps first.
    """
    if target.is_symlink() or (target.exists() and not target.is_dir()):
        raise ValueError(f"Installation destination is not a bundle directory: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    staging = tempfile.mkdtemp(prefix='.atem-install-', dir=target.parent)
    cleanup = True
    try:
        staged = Path(staging) / 'new'
        previous = Path(staging) / 'previous'
        shutil.copytree(source, staged, symlinks=True)
        had_previous = target.exists()
        if had_previous:
            os.replace(target, previous)
        try:
            os.replace(staged, target)
        except OSError:
            if had_previous:
                try:
                    os.replace(previous, target)
                except OSError:
                    cleanup = False  # Keep the old bundle for recovery.
                    raise RuntimeError(f"Could not restore installation; previous bundle retained at {previous}")
            raise
    finally:
        if cleanup:
            shutil.rmtree(staging)
