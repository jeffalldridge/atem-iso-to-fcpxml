#!/usr/bin/env python3
"""Differential fuzz of MP4 and WAV headers: the Swift engine against the Python reference.

Builds a small synthetic recording, corrupts bytes in the headers of its media files, and runs both
engines with --dry-run. The Swift command-line tool must never die on a signal (a trap), and the two
engines must agree on whether the recording is acceptable and, when it is, on what they would write.

    swift build --product atem-convert
    python3 scripts/fuzz_media_headers.py 500 1        # iterations, seed

This is a maintainer tool, not part of the test suite: it needs the built Swift binary and takes
minutes for large runs. A clean run is evidence, not proof, and says nothing about real recordings.
"""
from __future__ import annotations

import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))
import test_converter as fixtures  # noqa: E402

SWIFT = ROOT / ".build" / "debug" / "atem-convert"
PYTHON = ROOT / "atem_iso_to_fcpxml.py"
INTERESTING = [0x00, 0xFF, 0x7F, 0x80, 0x01, 0xFE]
EXTREMES = [b"\xff" * 8, b"\x7f" + b"\xff" * 7, b"\x80" + b"\x00" * 7, b"\x00" * 8, b"\x00\x00\x00\x01\x00\x00\x00\x00"]


def run(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=60)


def mutate(folder: Path, rng: random.Random) -> None:
    for _ in range(rng.choice([1, 1, 2, 3])):
        target = rng.choice([p for p in folder.rglob("*") if p.is_file() and p.suffix in (".mp4", ".wav")])
        data = bytearray(target.read_bytes())
        limit = min(len(data), 1500)  # the headers of the synthetic files
        for _ in range(rng.choice([1, 2, 4, 8])):
            data[rng.randrange(limit)] = rng.choice(INTERESTING) if rng.random() < 0.7 else rng.randrange(256)
        if rng.random() < 0.5:  # poke a whole field to an extreme value
            at = rng.randrange(limit - 8)
            data[at:at + 8] = rng.choice(EXTREMES)
        target.write_bytes(bytes(data))


def main() -> int:
    iterations, seed = int(sys.argv[1]), int(sys.argv[2])
    if not SWIFT.exists():
        print(f"Build the Swift tool first: swift build --product atem-convert ({SWIFT} is missing)", file=sys.stderr)
        return 2
    rng = random.Random(seed)
    base = fixtures.RecordingDir(frames=120, mode="1080p5994", tc="10:00:00;00", tc_fps=60, drop=True)
    base.write(base.rows + [fixtures.me("10:00:01;00", source=2)])
    work = Path(tempfile.mkdtemp(prefix="fuzz-"))
    accepted = rejected = 0
    problems: list[str] = []
    for n in range(iterations):
        case = work / "rec"
        if case.exists():
            shutil.rmtree(case)
        shutil.copytree(base.root, case)
        mutate(case, rng)
        drp = case / "Show.drp"
        py = run([sys.executable, str(PYTHON), str(drp), "--dry-run"])
        sw = run([str(SWIFT), str(drp), "--dry-run"])
        kept = None
        if sw.returncode < 0:
            problems.append(f"iteration {n}: Swift stopped on signal {-sw.returncode}")
            kept = "crash"
        elif (py.returncode == 0) != (sw.returncode == 0):
            problems.append(f"iteration {n}: Python exit {py.returncode}, Swift exit {sw.returncode}: "
                            f"{py.stderr.strip()[:90]!r} / {sw.stderr.strip()[:90]!r}")
            kept = "diverge"
        elif py.returncode == 0:
            accepted += 1
            if py.stdout.replace(str(case), "X").strip() != sw.stdout.replace(str(case), "X").strip():
                problems.append(f"iteration {n}: the dry-run summaries differ")
                kept = "output"
        else:
            rejected += 1
        if kept:
            shutil.copytree(case, work / f"{kept}-{n}")
    base.cleanup()
    print(f"{iterations} iterations (seed {seed}): {accepted} accepted by both, {rejected} rejected by both, {len(problems)} problems")
    for line in problems[:20]:
        print(" ", line)
    if problems:
        print(f"Failing recordings kept in {work}")
        return 1
    shutil.rmtree(work)
    return 0


if __name__ == "__main__":
    sys.exit(main())
