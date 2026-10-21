#!/usr/bin/env python3
"""Convert a Blackmagic ATEM Mini ISO recording (.drp) into Final Cut Pro XML.

The ATEM writes a ``.drp`` next to its program recording. That file is not a
DaVinci Resolve project archive: it is a newline-delimited JSON log of the
switcher state during the recording. This script reads that log, pairs every
camera's ISO MP4 with its uncompressed WAV, and writes one ``.fcpxml`` that
Final Cut Pro imports as a multicam clip plus a timeline of the live switch.

Python 3.9+ standard library only. No ffmpeg, no Resolve, no network.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from fractions import Fraction
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple
import xml.etree.ElementTree as ET

__version__ = "1.1.0"

FCPXML_VERSION = "1.10"  # Final Cut Pro 10.6 and later; 12.x re-exports as 1.14
CROSS_DISSOLVE_UID = "FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265"
MAX_DRP_BYTES = 16 * 1024 * 1024
MAX_METADATA_BYTES = 16 * 1024 * 1024
VIDEO_ISO_DIR = "Video ISO Files"
AUDIO_DIR = "Audio Source Files"
NTSC_RATES = {"2398": (24000, 1001), "23.98": (24000, 1001), "23.976": (24000, 1001),
              "2997": (30000, 1001), "29.97": (30000, 1001),
              "5994": (60000, 1001), "59.94": (60000, 1001),
              "4795": (48000, 1001), "47.95": (48000, 1001)}


class ConversionError(Exception):
    """The recording cannot be converted; the message is meant for the user."""


# --------------------------------------------------------------------------- time

def fmt_time(value: Fraction) -> str:
    """Rational seconds in FCPXML form: ``2798s`` or ``1001/60000s``."""
    value = Fraction(value)
    if value.denominator == 1:
        return f"{value.numerator}s"
    return f"{value.numerator}/{value.denominator}s"


def parse_video_mode(mode: str) -> Tuple[Optional[int], bool, Fraction]:
    """Return (lines, interlaced, frame rate) for an ATEM videoMode such as ``1080p60``.

    ``lines`` is only informational; the real frame size comes from the media.
    """
    if not isinstance(mode, str):
        raise ConversionError("The log videoMode must be text.")
    match = re.fullmatch(r"\s*(\d{3,4})([pi])(\d{2,4}(?:\.\d+)?)\s*", mode or "", re.IGNORECASE)
    if not match:
        raise ConversionError(f"Unrecognized ATEM videoMode {mode!r}.")
    lines, scan, rate_text = int(match[1]), match[2].lower(), match[3]
    if rate_text in NTSC_RATES:
        rate = Fraction(*NTSC_RATES[rate_text])
    else:
        rate = Fraction(rate_text)
        if rate.denominator != 1 or not 20 <= rate <= 120:
            raise ConversionError(f"Unsupported frame rate in videoMode {mode!r}.")
    if scan == "i":
        rate = rate / 2  # 1080i59.94 is 29.97 frames per second
    return lines, scan == "i", rate


@dataclass(frozen=True)
class Timecode:
    """Frame-accurate SMPTE timecode at a nominal (rounded) frame rate."""

    frames: int  # real frame index since midnight, drop-frame already resolved
    drop: bool

    @classmethod
    def parse(cls, label: str, fps: Fraction) -> "Timecode":
        if not isinstance(label, str):
            raise ConversionError("The log timecode must be text.")
        match = re.fullmatch(r"(\d{1,2}):(\d{2}):(\d{2})([:;.,])(\d{1,3})", (label or "").strip())
        if not match:
            raise ConversionError(f"Invalid timecode {label!r}.")
        h, m, s, f = int(match[1]), int(match[2]), int(match[3]), int(match[5])
        drop = match[4] in ";,"
        nominal = round(fps)
        if h >= 24 or m >= 60 or s >= 60 or f >= nominal:
            raise ConversionError(f"Timecode {label!r} is out of range for {float(fps):g} fps.")
        frames = ((h * 60 + m) * 60 + s) * nominal + f
        if drop:
            if fps not in (Fraction(30000, 1001), Fraction(60000, 1001)):
                raise ConversionError("Drop-frame timecode requires a 29.97 or 59.94 fps mode.")
            dropped = 2 * (nominal // 30)
            if m % 10 and s == 0 and f < dropped:
                raise ConversionError(f"Timecode {label!r} names a frame number that drop-frame counting skips.")
            minutes = h * 60 + m
            frames -= dropped * (minutes - minutes // 10)
        return cls(frames, drop)

    @staticmethod
    def frames_per_day(fps: Fraction, drop: bool) -> int:
        nominal = round(fps)
        return nominal * 86400 - (2 * (nominal // 30) * 1296 if drop else 0)

    @staticmethod
    def label(frames: int, fps: Fraction, drop: bool) -> str:
        nominal = round(fps)
        frames = frames % Timecode.frames_per_day(fps, drop)
        if drop and nominal % 30 == 0:
            dropped = 2 * (nominal // 30)  # frame numbers skipped at the start of each non-tenth minute
            per_minute = nominal * 60 - dropped
            per_ten = per_minute * 10 + dropped
            tens, rest = divmod(frames, per_ten)
            extra = 0 if rest < dropped else (rest - dropped) // per_minute
            frames += dropped * (tens * 9 + extra)
        f = frames % nominal
        total_seconds = frames // nominal
        sep = ";" if drop else ":"
        return f"{total_seconds // 3600:02d}:{total_seconds % 3600 // 60:02d}:{total_seconds % 60:02d}{sep}{f:02d}"


# ---------------------------------------------------------------------------- DRP

def merge_state(target: dict, patch: dict) -> None:
    """Apply a sparse ATEM state patch; arrays are keyed by ``_index_``."""
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge_state(target[key], value)
        elif isinstance(value, list) and value and all(isinstance(x, dict) and "_index_" in x for x in value):
            items = target.setdefault(key, [])
            if not isinstance(items, list):
                target[key] = items = []
            for update in value:
                existing = next((x for x in items if isinstance(x, dict) and x.get("_index_") == update["_index_"]), None)
                if existing is None:
                    items.append(copy.deepcopy(update))
                else:
                    merge_state(existing, update)
        else:
            target[key] = copy.deepcopy(value)


@dataclass
class Drp:
    path: Path
    header: dict
    events: List[dict]

    @property
    def sources(self) -> Dict[int, dict]:
        return {s["_index_"]: s for s in self.header.get("sources", []) if isinstance(s, dict) and "_index_" in s}


def _validate_state_shape(row: dict) -> None:
    """Validate containers we replay, leaving unknown firmware fields untouched."""
    for key in ("masterTimecode", "videoMode"):
        if key in row and not isinstance(row[key], str):
            raise ConversionError(f"The log field {key} must be text.")
    for key in ("sources", "mixEffectBlocks", "downstreamKeys", "upstreamKeys"):
        if key not in row:
            continue
        items = row[key]
        if not isinstance(items, list):
            raise ConversionError(f"The log field {key} must be an array.")
        indices = set()
        for item in items:
            if not isinstance(item, dict) or type(item.get("_index_")) is not int:
                raise ConversionError(f"Each {key} entry must have an integer _index_.")
            if item["_index_"] in indices:
                raise ConversionError(f"Duplicate _index_ in log field {key}.")
            indices.add(item["_index_"])
            for field_name in ("file", "name", "type"):
                if field_name in item and not isinstance(item[field_name], str):
                    raise ConversionError(f"The log field {key}.{field_name} must be text.")
            if key == "mixEffectBlocks":
                _validate_state_shape(item)


def load_drp(path: Path, session: Optional[int] = None) -> Drp:
    """Read the ATEM log. A log can hold several sessions if the same name was recorded twice."""
    if path.stat().st_size > MAX_DRP_BYTES:
        raise ConversionError("The .drp is larger than 16 MiB; that is not an ATEM switcher log.")
    with path.open("rb") as fh:
        raw = fh.read(MAX_DRP_BYTES + 1)
    if len(raw) > MAX_DRP_BYTES:
        raise ConversionError("The .drp exceeds the 16 MiB limit.")
    if raw[:2] == b"PK":
        raise ConversionError("This .drp is a DaVinci Resolve project archive, not the ATEM switcher log. "
                              "Use the .drp the ATEM wrote next to its recording.")
    try:
        text = raw.decode("utf-8-sig")
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
    except (UnicodeDecodeError, ValueError, RecursionError) as exc:
        raise ConversionError("The .drp is not an ATEM newline-delimited JSON log.") from exc
    if not rows or not all(isinstance(r, dict) for r in rows):
        raise ConversionError("The .drp contains no JSON objects.")
    sessions: List[List[dict]] = []
    for row in rows:
        _validate_state_shape(row)
        if "sources" in row and "videoMode" in row:
            sessions.append([row])
        elif sessions:
            sessions[-1].append(row)
    if not sessions:
        raise ConversionError("The first line of the .drp is missing sources, masterTimecode or videoMode.")
    if len(sessions) > 1 and session is None:
        raise ConversionError(f"This .drp holds {len(sessions)} recording sessions. Pick one with --session 1"
                              f" to --session {len(sessions)}, then check that the ISO file names match that session.")
    selected = 1 if session is None else session
    chosen = sessions[selected - 1] if 1 <= selected <= len(sessions) else None
    if chosen is None:
        raise ConversionError(f"--session must be between 1 and {len(sessions)}.")
    header = chosen[0]
    if "masterTimecode" not in header:
        raise ConversionError("The session header is missing masterTimecode.")
    if header.get("version") not in (None, 1):
        raise ConversionError(f"Unsupported ATEM log version {header.get('version')!r}; only version 1 is known.")
    return Drp(path, header, chosen[1:])


# -------------------------------------------------------------------------- media

@dataclass
class Mp4Info:
    width: int
    height: int
    frame_rate: Fraction
    frames: int
    duration: Fraction
    codec: str
    has_audio: bool
    timecode_frames: Optional[int]
    drop_frame: bool


@dataclass
class WavInfo:
    channels: int
    sample_rate: int
    bits: int
    sample_frames: int
    time_reference: Optional[int]  # BEXT TimeReference in samples since midnight

    @property
    def duration(self) -> Fraction:
        return Fraction(self.sample_frames, self.sample_rate)


def _boxes(fh, start: int, end: int):
    pos = start
    while pos + 8 <= end:
        fh.seek(pos)
        head = fh.read(8)
        if len(head) < 8:
            return
        size, kind = struct.unpack(">I4s", head)
        header = 8
        if size == 1:
            size = struct.unpack(">Q", _read(fh, pos + 8, 8))[0]
            header = 16
        elif size == 0:
            size = end - pos
        if size < header or pos + size > end:
            raise ConversionError("Invalid or truncated MP4 box.")
        yield kind, pos + header, pos + size
        pos += size


def _read(fh, pos: int, size: int, end: Optional[int] = None) -> bytes:
    # Lengths in media headers are untrusted. A tiny corrupt file must not cause
    # a multi-gigabyte allocation, or borrow bytes from the next sibling box.
    if size < 0 or size > MAX_METADATA_BYTES or (end is not None and pos + size > end):
        raise ConversionError("Invalid or oversized media metadata field.")
    fh.seek(pos)
    data = fh.read(size)
    if len(data) != size:
        raise ConversionError("Unexpected end of file while reading MP4 structure.")
    return data


def probe_mp4(path: Path) -> Mp4Info:
    """Read the MP4 (ISO BMFF) index without touching the media payload."""
    size = path.stat().st_size
    tracks = []
    with path.open("rb") as fh:
        moov = next(((s, e) for kind, s, e in _boxes(fh, 0, size) if kind == b"moov"), None)
        if moov is None:
            raise ConversionError(f"No MP4 index (moov) found in {path.name}; the recording may be incomplete.")
        for kind, s, e in _boxes(fh, *moov):
            if kind != b"trak":
                continue
            track: dict = {}
            for k2, s2, e2 in _boxes(fh, s, e):
                if k2 == b"tkhd":
                    version = _read(fh, s2, 1, e2)[0]
                    dimensions = s2 + (88 if version == 1 else 76)
                    w, h = struct.unpack(">II", _read(fh, dimensions, 8, e2))
                    track["width"], track["height"] = w >> 16, h >> 16
                elif k2 == b"mdia":
                    for k3, s3, e3 in _boxes(fh, s2, e2):
                        if k3 == b"mdhd":
                            version = _read(fh, s3, 1, e3)[0]
                            if version == 1:
                                track["timescale"], track["duration"] = struct.unpack(">IQ", _read(fh, s3 + 20, 12, e3))
                            else:
                                track["timescale"], track["duration"] = struct.unpack(">II", _read(fh, s3 + 12, 8, e3))
                        elif k3 == b"hdlr":
                            track["handler"] = _read(fh, s3 + 8, 4, e3)
                        elif k3 == b"minf":
                            for k4, s4, e4 in _boxes(fh, s3, e3):
                                if k4 == b"stbl":
                                    _read_stbl(fh, s4, e4, track)
            tracks.append(track)
        video = next((t for t in tracks if t.get("handler") == b"vide"), None)
        if not video or not video.get("timescale") or not video.get("samples") or not video.get("duration"):
            raise ConversionError(f"{path.name} has no video track.")
        frames = video["samples"]
        if video.get("stts_uniform"):
            frame_rate = Fraction(video["timescale"], video["stts_uniform"])
        else:
            frame_rate = Fraction(frames * video["timescale"], video["duration"])
        duration = Fraction(video["duration"], video["timescale"])
        timecode_frames = None
        drop = False
        tc = next((t for t in tracks if t.get("handler") == b"tmcd" and "tc" in t), None)
        if tc and tc.get("first_chunk") is not None:
            timecode_frames = struct.unpack(">I", _read(fh, tc["first_chunk"], 4))[0]
            drop = bool(tc["tc"]["flags"] & 1)
    return Mp4Info(video.get("width", 0), video.get("height", 0), frame_rate, frames, duration,
                   video.get("codec", "?"), any(t.get("handler") == b"soun" for t in tracks), timecode_frames, drop)


def _read_stbl(fh, start: int, end: int, track: dict) -> None:
    for kind, s, e in _boxes(fh, start, end):
        if kind == b"stsd":
            count = struct.unpack(">I", _read(fh, s + 4, 4, e))[0]
            if count:
                entry_size, entry_type = struct.unpack(">I4s", _read(fh, s + 8, 8, e))
                if entry_size < 8 or s + 8 + entry_size > e:
                    raise ConversionError("Invalid MP4 sample description length.")
                track["codec"] = entry_type.decode("latin-1")
                if entry_type == b"tmcd" and entry_size >= 34:
                    body = _read(fh, s + 16, 25, e)
                    flags, timescale, frame_duration, number_of_frames = struct.unpack(">IIIB", body[12:25])
                    track["tc"] = dict(flags=flags, timescale=timescale, frame_duration=frame_duration,
                                       number_of_frames=number_of_frames)
        elif kind == b"stts":
            count = struct.unpack(">I", _read(fh, s + 4, 4, e))[0]
            if count > (e - s - 8) // 8:
                raise ConversionError("Truncated MP4 sample timing table.")
            data = _read(fh, s + 8, count * 8, e)
            entries = [struct.unpack(">II", data[i * 8:i * 8 + 8]) for i in range(count)]
            track["samples"] = sum(n for n, _ in entries)
            if len(entries) == 1 or (len(entries) == 2 and entries[1][0] == 1):
                track["stts_uniform"] = entries[0][1]
        elif kind in (b"stco", b"co64"):
            count = struct.unpack(">I", _read(fh, s + 4, 4, e))[0]
            if count:
                fmt, width = (">I", 4) if kind == b"stco" else (">Q", 8)
                track["first_chunk"] = struct.unpack(fmt, _read(fh, s + 8, width, e))[0]


def probe_wav(path: Path) -> WavInfo:
    """Read RIFF/RF64 WAV headers, including the Broadcast WAV time reference."""
    size = path.stat().st_size
    with path.open("rb") as fh:
        head = fh.read(12)
        if len(head) < 12 or head[:4] not in (b"RIFF", b"RF64") or head[8:12] != b"WAVE":
            raise ConversionError(f"{path.name} is not a WAV file.")
        info: dict = {}
        pos = 12
        while pos + 8 <= size:
            fh.seek(pos)
            tag, chunk_size = struct.unpack("<4sI", fh.read(8))
            body = pos + 8
            if tag != b"data" and body + chunk_size > size:
                raise ConversionError(f"{path.name} has a truncated WAV chunk.")
            if tag == b"ds64" and chunk_size >= 16:
                _, data_size = struct.unpack("<QQ", fh.read(16))
                info["ds64_data"] = data_size
            elif tag == b"fmt " and chunk_size >= 16:
                fmt, channels, rate, _, align, bits = struct.unpack("<HHIIHH", fh.read(16))
                if fmt == 0xFFFE and chunk_size >= 26:  # WAVE_FORMAT_EXTENSIBLE
                    fh.seek(body + 24)
                    fmt = struct.unpack("<H", fh.read(2))[0]
                if fmt not in (1, 3):
                    raise ConversionError(f"{path.name} is not PCM; ATEM WAVs should be uncompressed.")
                info.update(channels=channels, rate=rate, align=align or (channels * bits // 8), bits=bits)
            elif tag == b"bext" and chunk_size >= 346:
                fh.seek(body + 338)
                info["time_reference"] = struct.unpack("<Q", fh.read(8))[0]
            elif tag == b"data":
                data_size = chunk_size
                if chunk_size == 0xFFFFFFFF and "ds64_data" in info:
                    data_size = info["ds64_data"]
                if data_size > size - body:
                    raise ConversionError(f"{path.name} has truncated WAV audio data; finish recording or restore the file first.")
                info["data_size"] = data_size
                chunk_size = data_size  # RF64 uses ds64, not the 32-bit sentinel.
                # BWF metadata may follow data. Seek over samples, never read them.
            if body + chunk_size > size:
                raise ConversionError(f"{path.name} has a truncated WAV chunk.")
            pos = body + chunk_size + (chunk_size & 1)
    if "rate" not in info or "data_size" not in info:
        raise ConversionError(f"{path.name} is missing its fmt or data chunk.")
    if not all(info[k] > 0 for k in ("channels", "rate", "bits", "align")):
        raise ConversionError(f"{path.name} has invalid WAV format values.")
    return WavInfo(info["channels"], info["rate"], info["bits"], info["data_size"] // info["align"],
                   info.get("time_reference"))


def probe_image_size(path: Path) -> Optional[Tuple[int, int]]:
    """Pixel size of a PNG or JPEG still from the ATEM media pool; None if unknown."""
    try:
        with path.open("rb") as fh:
            head = fh.read(32)
            if head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
                return struct.unpack(">II", head[16:24])
            if head[:2] == b"\xff\xd8":
                fh.seek(2)
                while True:
                    marker = fh.read(2)
                    if len(marker) < 2 or marker[0] != 0xFF:
                        return None
                    if marker[1] in (0xC0, 0xC1, 0xC2):
                        fh.read(3)
                        height, width = struct.unpack(">HH", fh.read(4))
                        return width, height
                    size = struct.unpack(">H", fh.read(2))[0]
                    if size < 2:
                        return None  # Require forward progress through JPEG segments.
                    fh.seek(size - 2, 1)
    except (OSError, struct.error):
        return None
    return None


# ------------------------------------------------------------------------ recording

@dataclass
class VideoSource:
    index: int
    name: str
    kind: str  # Video | Still
    mp4: Optional[Path]
    wav: Optional[Path]
    relative: str
    mp4_info: Optional[Mp4Info] = None
    wav_info: Optional[WavInfo] = None


@dataclass
class Recording:
    drp: Drp
    root: Path
    name: str
    frame_rate: Fraction
    frame_duration: Fraction
    interlaced: bool
    width: int
    height: int
    drop_frame: bool
    start_frames: int  # master timecode as a frame index since midnight
    total_frames: int
    program_mp4: Optional[Path]
    program_info: Optional[Mp4Info]
    sources: Dict[int, VideoSource]
    audio_files: Dict[str, Path]  # all WAVs in Audio Source Files keyed by stem
    warnings: List[str] = field(default_factory=list)

    @property
    def start_time(self) -> Fraction:
        return self.start_frames * self.frame_duration

    @property
    def duration(self) -> Fraction:
        return self.total_frames * self.frame_duration

    def timecode(self, frame: int) -> str:
        return Timecode.label(self.start_frames + frame, self.frame_rate, self.drop_frame)


def contained_path(root: Path, relative: str) -> Path:
    """Resolve a DRP-relative media path, refusing anything outside the recording folder."""
    if not relative or relative.startswith(("/", "\\")) or ".." in Path(relative).parts:
        raise ConversionError(f"Refusing media path outside the recording folder: {relative!r}")
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ConversionError(f"Refusing media path outside the recording folder: {relative!r}")
    return path


def list_wavs(root: Path) -> Dict[str, Path]:
    folder = root / AUDIO_DIR
    if not folder.is_dir():
        return {}
    return {p.stem: contained_path(root, str(p.relative_to(root))) for p in sorted(folder.iterdir())
            if p.suffix.lower() == ".wav" and not p.name.startswith("._") and p.is_file()}


def open_recording(drp_path: Path, session: Optional[int] = None) -> Recording:
    drp = load_drp(drp_path, session)
    root = drp_path.parent
    header = drp.header
    _, interlaced, frame_rate = parse_video_mode(header["videoMode"])
    master = Timecode.parse(header["masterTimecode"], frame_rate)
    warnings: List[str] = []

    program_mp4: Optional[Path] = None
    program_info = None
    iso_stems = [Path(s["file"]).stem for s in drp.sources.values() if s.get("type") == "Video" and s.get("file")]
    prefixes = [re.sub(r" CAM \d+$", "", stem) for stem in iso_stems if re.search(r" CAM \d+$", stem)]
    for candidate in [drp_path.stem] + prefixes:
        path = contained_path(root, f"{candidate}.mp4")
        if path.is_file():
            program_mp4, program_info = path, probe_mp4(path)
            break
    if program_mp4 is None:
        warnings.append(f"Program recording {drp_path.stem}.mp4 not found; transitions and keys cannot fall back to it.")

    sources: Dict[int, VideoSource] = {}
    for index, source in drp.sources.items():
        kind = source.get("type")
        if kind not in ("Video", "Still") or not source.get("file"):
            continue
        try:
            path = contained_path(root, source["file"])
        except ConversionError as exc:
            warnings.append(str(exc))
            continue
        item = VideoSource(index, str(source.get("name") or f"Input {index}"), kind,
                           path if path.is_file() else None, None, source["file"])
        if item.mp4 is None:
            warnings.append(f"{item.name}: file not found: {source['file']}")
        sources[index] = item

    audio_files = list_wavs(root)
    for item in sources.values():
        if item.kind == "Video":
            item.wav = audio_files.get(Path(item.relative).stem)

    # The authoritative frame size and rate come from the media itself.
    reference = program_info or next((probe_mp4(s.mp4) for s in sources.values() if s.kind == "Video" and s.mp4), None)
    if reference is None:
        raise ConversionError("No ISO or program MP4 files were found next to the .drp.")
    if reference.frame_rate != frame_rate:
        warnings.append(f"videoMode says {float(frame_rate):g} fps but the recording is {float(reference.frame_rate):g} fps; using the recording.")
        frame_rate = reference.frame_rate
    master = Timecode.parse(header["masterTimecode"], frame_rate)
    frame_duration = 1 / frame_rate
    drop = master.drop or reference.drop_frame
    start_frames = master.frames
    if reference.timecode_frames is not None and reference.timecode_frames != master.frames:
        warnings.append(f"Program timecode {Timecode.label(reference.timecode_frames, frame_rate, drop)} differs from the log's master timecode; using the log.")

    total_frames = reference.frames
    end_event = next((e for e in reversed(drp.events) if _recording_stopped(e)), None)
    if end_event is not None:
        end = Timecode.parse(end_event["masterTimecode"], frame_rate).frames
        log_frames = end - start_frames
        if log_frames < 0:
            log_frames += Timecode.frames_per_day(frame_rate, master.drop)
        if abs(log_frames - total_frames) > 2:
            warnings.append(f"The log says the recording is {log_frames} frames but the media has {total_frames}; using the media.")
    return Recording(drp, root, drp_path.stem, frame_rate, frame_duration, interlaced, reference.width, reference.height,
                     drop, start_frames, total_frames, program_mp4, program_info, sources, audio_files, warnings)


def _recording_stopped(event: dict) -> bool:
    blocks = event.get("mixEffectBlocks")
    return isinstance(blocks, list) and any(isinstance(b, dict) and b.get("onAir") is False for b in blocks)


# ----------------------------------------------------------------------- edit list

@dataclass
class Picture:
    """What the program output showed during an interval."""

    kind: str  # angle | program | gap
    key: str = ""  # angle id for kind == angle
    reason: str = ""  # why the program recording is used

    def __eq__(self, other):
        return isinstance(other, Picture) and (self.kind, self.key) == (other.kind, other.key)


@dataclass
class Cut:
    start: int  # frame offset from recording start (inclusive)
    end: int  # exclusive
    picture: Picture
    transition_in: Optional["Transition"] = None


@dataclass
class Transition:
    start: int
    end: int
    kind: str  # ATEM transition type, Mix by default
    approximated: bool = False


@dataclass
class EditList:
    cuts: List[Cut]
    angles_used: List[str]
    stills: Dict[str, Tuple[int, str, str]]  # angle id -> (source index, name, relative file)


def angle_id(source: dict, index: int) -> str:
    if source.get("type") == "Still":
        return f"still-{index}-{re.sub(r'[^A-Za-z0-9]+', '-', Path(source.get('file', '')).stem)}"
    return f"input-{index}"


def _picture_for(state: dict, selected: set, fallback) -> Picture:
    blocks = [b for b in state.get("mixEffectBlocks", []) if isinstance(b, dict)]
    block = next((b for b in blocks if b.get("_index_") == 0), blocks[0] if blocks else {})
    sources = {s["_index_"]: s for s in state.get("sources", []) if isinstance(s, dict) and "_index_" in s}
    reasons = []
    ftb = block.get("fadeToBlack", "Inactive")
    if ftb not in ("Inactive", False, None, 0):
        reasons.append("fade to black")
    if any(k.get("onAir") for k in block.get("upstreamKeys", []) if isinstance(k, dict)):
        reasons.append("upstream key on air")
    if any(k.get("onAir") or k.get("faderState", "Idle") not in ("Idle", None)
           for k in state.get("downstreamKeys", []) if isinstance(k, dict)):
        reasons.append("downstream key on air")
    index = block.get("source")
    source = sources.get(index)
    if source is None:
        reasons.append(f"unknown program source {index}")
    elif source.get("type") not in ("Video", "Still"):
        reasons.append(f"{source.get('name') or source.get('type')} generator")
    elif angle_id(source, index) not in selected:
        if source.get("type") == "Still":
            reasons.append(f"{source.get('name')} still image not found")
        else:
            reasons.append(f"{source.get('name')} not included in the multicam")
    if reasons:
        return fallback("; ".join(reasons))
    return Picture("angle", angle_id(source, index))


def build_edit_list(rec: Recording, cameras: Sequence[int], transitions: str = "dissolve") -> EditList:
    """Turn the ATEM event log into cuts and transitions on a frame grid."""
    fps = rec.frame_rate
    day = Timecode.frames_per_day(fps, rec.drop_frame)
    state = copy.deepcopy(rec.drp.header)
    sources = rec.drp.sources
    selected = {f"input-{i}" for i in cameras}
    stills: Dict[str, Tuple[int, str, str]] = {}
    for index, source in sources.items():
        if source.get("type") == "Still" and index in rec.sources and rec.sources[index].mp4:
            selected.add(angle_id(source, index))
            stills[angle_id(source, index)] = (index, str(source.get("name") or f"Media Player {index}"), source["file"])
    allow_program = rec.program_mp4 is not None
    first_camera = next((f"input-{i}" for i in cameras if rec.sources.get(i) and rec.sources[i].mp4), None)

    def fallback(reason: str) -> Picture:
        """What stands in when the angles cannot show what the ATEM put on air."""
        if allow_program:
            return Picture("program", reason=reason)
        if first_camera:
            # No program recording: keep the soundtrack running on the first camera rather than a silent gap.
            return Picture("angle", first_camera, reason=f"{reason}; program recording not found, showing {rec.sources[int(first_camera[6:])].name}")
        return Picture("gap", reason=reason)

    # 1. Replay the log into (start, end, state snapshot) intervals on the frame grid.
    intervals: List[Tuple[int, int, dict]] = []
    previous_raw = rec.start_frames
    wraps = cursor = 0
    for event in rec.drp.events:
        if not isinstance(event, dict) or "masterTimecode" not in event:
            continue
        raw = Timecode.parse(event["masterTimecode"], fps).frames
        delta = raw - previous_raw
        if delta < -day // 2:
            wraps += day  # the clock passed midnight
        elif delta < 0 or delta > day // 2:
            raise ConversionError("Events in the .drp are not in chronological order.")
        previous_raw = raw
        at = min(max(raw + wraps - rec.start_frames, 0), rec.total_frames)
        if at > cursor:
            intervals.append((cursor, at, copy.deepcopy(state)))
            cursor = at
        merge_state(state, event)
        if _recording_stopped(event):
            break
    if cursor < rec.total_frames:
        intervals.append((cursor, rec.total_frames, copy.deepcopy(state)))

    # 2. Classify every interval: what was on the program output, and was a transition running?
    classified: List[Tuple[int, int, Picture, bool, str]] = []
    for start, end, snap in intervals:
        blocks = [b for b in snap.get("mixEffectBlocks", []) if isinstance(b, dict)]
        block = next((b for b in blocks if b.get("_index_") == 0), blocks[0] if blocks else {})
        classified.append((start, end, _picture_for(snap, selected, fallback), bool(block.get("transitionActive")),
                           str(block.get("transitionType") or "Mix")))

    # Unrelated sparse updates (e.g. an input label) can split an active mix.
    # Treat a contiguous run with unchanged picture/type as one transition,
    # otherwise the next active interval is mistaken for the finished picture.
    joined: List[Tuple[int, int, Picture, bool, str]] = []
    for interval in classified:
        if (joined and interval[3] and joined[-1][3] and joined[-1][1] == interval[0]
                and joined[-1][2] == interval[2] and joined[-1][2].reason == interval[2].reason
                and joined[-1][4] == interval[4]):
            previous = joined[-1]
            joined[-1] = (previous[0], interval[1], previous[2], True, previous[4])
        else:
            joined.append(interval)
    classified = joined

    # 3. Resolve transition intervals against their neighbors and merge equal pictures.
    cuts: List[Cut] = []

    def append(start: int, end: int, picture: Picture, transition: Optional[Transition] = None) -> None:
        last = cuts[-1] if cuts else None
        if (last and transition is None and last.picture == picture and last.picture.reason == picture.reason
                and last.end == start):
            last.end = end
        elif end > start:
            cuts.append(Cut(start, end, picture, transition))

    for i, (start, end, picture, in_transition, kind) in enumerate(classified):
        if not in_transition:
            append(start, end, picture)
            continue
        before = cuts[-1].picture if cuts else None
        after = classified[i + 1][2] if i + 1 < len(classified) else None
        reason = f"ATEM {kind} transition"
        if before is not None and after is not None and before == after and before.kind == "angle":
            append(start, end, before)  # a transition back to the same picture changes nothing
        elif before is None or after is None or before.kind != "angle" or after.kind != "angle" or before.reason or after.reason:
            extra = after.reason if after is not None and after.reason else ""
            append(start, end, fallback(reason + (f"; {extra}" if extra else "")))
        elif transitions == "program":
            append(start, end, fallback(reason))
        else:
            length = end - start
            if transitions == "dissolve" and length % 2:
                length += 1  # Final Cut centres the dissolve on the cut, so keep it an even number of frames
            half = length // 2
            cut_point = start + half
            next_length = classified[i + 1][1] - classified[i + 1][0]
            if transitions == "cut" or cuts[-1].end - cuts[-1].start < half or end - start + next_length < length:
                cuts[-1].end = cut_point
                append(cut_point, end, after)
            else:
                cuts[-1].end = cut_point
                approximated = kind.lower() != "mix"
                append(cut_point, end, after, Transition(cut_point - half, cut_point + half, kind, approximated))

    cuts = [c for c in cuts if c.end > c.start]
    used: List[str] = []
    for cut in cuts:
        if cut.picture.kind == "angle" and cut.picture.key not in used:
            used.append(cut.picture.key)
    return EditList(cuts, used, stills)


# ----------------------------------------------------------------------------- plan

@dataclass
class Angle:
    id: str
    name: str
    kind: str  # camera | still | program | audio
    video: Optional[Path] = None
    audio: Optional[Path] = None
    source_index: Optional[int] = None


@dataclass
class Plan:
    rec: Recording
    edit: EditList
    angles: List[Angle]
    main_audio_angle: str
    name: str
    event: Optional[str]
    transitions: str

    def summary(self) -> List[str]:
        rec = self.rec
        lines = [f"Recording: {rec.name} ({rec.width}x{rec.height}, {float(rec.frame_rate):g} fps, "
                 f"{rec.total_frames} frames, {rec.timecode(0)} to {rec.timecode(rec.total_frames)})"]
        for angle in self.angles:
            detail = angle.kind
            if angle.video and angle.audio:
                detail = f"{angle.video.name} + {angle.audio.name}"
            elif angle.video:
                detail = angle.video.name
            elif angle.audio:
                detail = angle.audio.name
            tag = "  (main soundtrack)" if angle.id == self.main_audio_angle else ""
            lines.append(f"Angle {angle.name}: {detail}{tag}")
        dissolves = sum(1 for c in self.edit.cuts if c.transition_in)
        fallbacks = [c for c in self.edit.cuts if c.picture.kind != "angle" or c.picture.reason]
        lines.append(f"Timeline: {len(self.edit.cuts)} clips, {dissolves} cross dissolves, {len(fallbacks)} stand-in sections")
        for cut in fallbacks:
            lines.append(f"  {rec.timecode(cut.start)}–{rec.timecode(cut.end)}: {cut.picture.reason}")
        for cut in self.edit.cuts:
            if cut.transition_in and cut.transition_in.approximated:
                lines.append(f"  {rec.timecode(cut.transition_in.start)}: ATEM {cut.transition_in.kind} transition shown as a cross dissolve")
        for warning in rec.warnings:
            lines.append(f"Warning: {warning}")
        return lines


def resolve_audio(rec: Recording, label: Optional[str]) -> Optional[Path]:
    """Find a WAV by exact filename, stem, or suffix such as ``MIC 1``."""
    if not label:
        return None
    wanted = label.strip()
    for stem, path in rec.audio_files.items():
        if wanted in (path.name, stem):
            return path
    matches = [p for stem, p in rec.audio_files.items() if stem.lower().endswith(" " + wanted.lower())]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise ConversionError(f"No WAV named {label!r} in {AUDIO_DIR}. Available: " + ", ".join(rec.audio_files) + ".")
    raise ConversionError(f"{label!r} matches several WAVs: " + ", ".join(p.name for p in matches) + ".")


def make_plan(rec: Recording, cameras: Optional[Sequence[int]] = None, audio: Optional[str] = None,
              extra_audio: Optional[Sequence[str]] = None, transitions: str = "dissolve",
              name: Optional[str] = None, event: Optional[str] = None, include_program: bool = False) -> Plan:
    if transitions not in ("dissolve", "cut", "program"):
        raise ConversionError("transitions must be dissolve, cut or program.")
    cameras_available = [i for i, s in sorted(rec.sources.items()) if s.kind == "Video" and s.mp4]
    if not cameras_available:
        raise ConversionError(f"No camera ISO files were found in {VIDEO_ISO_DIR}.")
    if cameras is None:
        probe = build_edit_list(rec, cameras_available, "cut")
        cameras = [i for i in cameras_available if f"input-{i}" in probe.angles_used] or cameras_available[:1]
    cameras = list(dict.fromkeys(int(c) for c in cameras))
    if not cameras:
        raise ConversionError("Choose at least one camera input.")
    missing = [c for c in cameras if c not in cameras_available]
    if missing:
        raise ConversionError("These inputs have no ISO recording: " + ", ".join(map(str, missing))
                              + ". Available: " + ", ".join(map(str, cameras_available)) + ".")

    edit = build_edit_list(rec, cameras, transitions)
    angles: List[Angle] = []
    for index in cameras:
        source = rec.sources[index]
        source.mp4_info = probe_mp4(source.mp4)
        if source.wav:
            source.wav_info = probe_wav(source.wav)
        else:
            rec.warnings.append(f"{source.name}: no WAV named '{Path(source.relative).stem}.wav' in {AUDIO_DIR}; using the MP4's compressed audio.")
        angles.append(Angle(f"input-{index}", source.name, "camera", source.mp4, source.wav, index))
    for key, (index, label, _) in edit.stills.items():
        if key in edit.angles_used:
            angles.append(Angle(key, label, "still", rec.sources[index].mp4, None, index))
    if rec.program_mp4 and (include_program or any(c.picture.kind == "program" for c in edit.cuts)):
        angles.append(Angle("program", "Program", "program", rec.program_mp4, None))

    main_path = resolve_audio(rec, audio) if audio else None
    if main_path is None:
        first = rec.sources[cameras[0]]
        main_path = first.wav or next((p for p in rec.audio_files.values()), None)
    camera_wavs = {a.audio for a in angles if a.audio}
    if extra_audio is None:
        paired = {Path(s.relative).stem for s in rec.sources.values() if s.kind == "Video"}
        extras = [p for stem, p in rec.audio_files.items() if stem not in paired]
    else:
        extras = [resolve_audio(rec, label) for label in extra_audio]
    if main_path is not None and main_path not in camera_wavs and main_path not in extras:
        extras.insert(0, main_path)
    for path in extras:
        if path in camera_wavs or any(a.audio == path for a in angles):
            continue
        probe_wav(path)
        label = path.stem
        prefix = rec.name + " "
        if label.startswith(prefix) and len(label) > len(prefix):
            label = label[len(prefix):]
        base_id = "audio-" + re.sub(r"[^A-Za-z0-9]+", "-", path.stem).strip("-").lower()
        unique_id = base_id
        suffix = 2
        while any(a.id == unique_id for a in angles):
            unique_id = f"{base_id}-{suffix}"
            suffix += 1
        angles.append(Angle(unique_id, label, "audio", None, path))

    main_angle = next((a.id for a in angles if main_path is not None and a.audio == main_path), None)
    if main_angle is None:
        main_angle = next((a.id for a in angles if a.kind == "camera"), angles[0].id)
        rec.warnings.append("No WAV files found; the main soundtrack is the first camera's MP4 audio.")
    # Asset start describes a source's own clock; it does NOT align two files
    # placed at the same offset. Native ATEM files should share the start.
    # Keep the round-tripped XML shape; flag mismatches for manual sync instead
    # of claiming that merely copying BWF/timecode metadata corrected them.
    for angle in angles:
        if angle.audio:
            info = probe_wav(angle.audio)
            if info.time_reference is None:
                rec.warnings.append(f"{angle.audio.name}: no Broadcast Wave time reference; assuming a common recording start. Check sync.")
            elif abs(Fraction(info.time_reference, info.sample_rate) - rec.start_time) > rec.frame_duration:
                rec.warnings.append(f"{angle.audio.name}: start time differs from the log; automatic offset correction is not supported. Check sync in Final Cut.")
            if info.duration + rec.frame_duration < rec.duration:
                rec.warnings.append(f"{angle.audio.name}: audio ends before the project; check the tail for silence.")
        if angle.video and angle.kind != "still":
            info = probe_mp4(angle.video)
            if info.frame_rate != rec.frame_rate or (info.width, info.height) != (rec.width, rec.height):
                raise ConversionError(f"{angle.video.name}: video format differs from the recording. Mixed formats are not supported.")
            if info.timecode_frames is not None and info.timecode_frames != rec.start_frames:
                rec.warnings.append(f"{angle.video.name}: start time differs from the log; automatic offset correction is not supported. Check sync in Final Cut.")
            if info.frames < rec.total_frames:
                rec.warnings.append(f"{angle.video.name}: video ends before the project; check the tail for missing picture.")
    base = name or rec.root.name
    return Plan(rec, edit, angles, main_angle, base, base if event is None else event, transitions)


# --------------------------------------------------------------------------- fcpxml

class _Resources:
    def __init__(self, parent: ET.Element):
        self.parent = parent
        self.count = 0
        self.assets: Dict[Path, str] = {}

    def next_id(self) -> str:
        self.count += 1
        return f"r{self.count}"


def _format_name(rec: Recording) -> Optional[str]:
    rate = {Fraction(24000, 1001): "2398", Fraction(30000, 1001): "2997", Fraction(60000, 1001): "5994"}.get(rec.frame_rate)
    if rate is None:
        if rec.frame_rate.denominator != 1:
            return None
        rate = str(rec.frame_rate.numerator)
    if (rec.width, rec.height) in ((1920, 1080), (1280, 720), (3840, 2160)):
        return f"FFVideoFormat{rec.height}{'i' if rec.interlaced else 'p'}{rate}"
    return None


def build_fcpxml(plan: Plan) -> bytes:
    rec = plan.rec
    fd = rec.frame_duration
    t0 = rec.start_time
    duration = rec.duration
    tc_format = "DF" if rec.drop_frame else "NDF"

    root = ET.Element("fcpxml", version=FCPXML_VERSION)
    resources_el = ET.SubElement(root, "resources")
    res = _Resources(resources_el)
    fmt_attrs = dict(id=res.next_id(), frameDuration=fmt_time(fd), width=str(rec.width), height=str(rec.height),
                     colorSpace="1-1-1 (Rec. 709)")
    name = _format_name(rec)
    if name:
        fmt_attrs["name"] = name
    if rec.interlaced:
        fmt_attrs["fieldOrder"] = "upper first"
    ET.SubElement(resources_el, "format", fmt_attrs)
    format_id = fmt_attrs["id"]

    def video_asset(path: Path, info: Optional[Mp4Info], still: bool = False) -> Tuple[str, Fraction, Fraction]:
        """Register an asset; returns (id, asset start, asset duration)."""
        if path in res.assets:
            start, length = asset_times[path]
            return res.assets[path], start, length
        if still:
            start, length = Fraction(0), Fraction(0)
            attrs = dict(id=res.next_id(), name=path.name, start="0s", duration="0s", hasVideo="1", videoSources="1")
            size = probe_image_size(path)
            if size:
                if "still" not in still_formats:
                    still_formats["still"] = res.next_id()
                    ET.SubElement(resources_el, "format", id=still_formats["still"], name="FFVideoFormatRateUndefined",
                                  width=str(size[0]), height=str(size[1]), colorSpace="1-13-1")
                attrs["format"] = still_formats["still"]
        else:
            assert info is not None
            start = (info.timecode_frames or 0) * fd
            length = info.frames * fd
            attrs = dict(id=res.next_id(), name=path.name, start=fmt_time(start), duration=fmt_time(length),
                         hasVideo="1", format=format_id, videoSources="1")
            if info.has_audio:
                attrs.update(hasAudio="1", audioSources="1", audioChannels="2", audioRate="48000")
        asset = ET.SubElement(resources_el, "asset", attrs)
        ET.SubElement(asset, "media-rep", kind="original-media", src=path.as_uri())
        res.assets[path] = attrs["id"]
        asset_times[path] = (start, length)
        return attrs["id"], start, length

    def audio_asset(path: Path) -> Tuple[str, Fraction, Fraction]:
        if path in res.assets:
            start, length = asset_times[path]
            return res.assets[path], start, length
        info = probe_wav(path)
        start = Fraction(info.time_reference or 0, info.sample_rate)
        length = info.duration
        attrs = dict(id=res.next_id(), name=path.name, start=fmt_time(start), duration=fmt_time(length), hasAudio="1",
                     audioSources="1", audioChannels=str(info.channels), audioRate=str(info.sample_rate))
        asset = ET.SubElement(resources_el, "asset", attrs)
        ET.SubElement(asset, "media-rep", kind="original-media", src=path.as_uri())
        res.assets[path] = attrs["id"]
        asset_times[path] = (start, length)
        return attrs["id"], start, length

    asset_times: Dict[Path, Tuple[Fraction, Fraction]] = {}
    still_formats: Dict[str, str] = {}

    # Assets first so the file reads top-down.
    for angle in plan.angles:
        if angle.video and angle.kind == "still":
            video_asset(angle.video, None, still=True)
        elif angle.video:
            source = rec.sources.get(angle.source_index) if angle.source_index is not None else None
            info = source.mp4_info if source and source.mp4_info else (rec.program_info if angle.kind == "program" else probe_mp4(angle.video))
            video_asset(angle.video, info)
        if angle.audio:
            audio_asset(angle.audio)

    dissolve_id = None
    if any(c.transition_in for c in plan.edit.cuts):
        dissolve_id = res.next_id()
        ET.SubElement(resources_el, "effect", id=dissolve_id, name="Cross Dissolve", uid=CROSS_DISSOLVE_UID)

    # Multicam clip: one angle per selected camera (ISO video + its WAV), stills, program, extra audio.
    multicam_id = res.next_id()
    media = ET.SubElement(resources_el, "media", id=multicam_id, name=f"{plan.name} Multicam")
    multicam = ET.SubElement(media, "multicam", format=format_id, tcStart=fmt_time(t0), tcFormat=tc_format)
    for angle in plan.angles:
        mc_angle = ET.SubElement(multicam, "mc-angle", name=angle.name, angleID=angle.id)
        if angle.kind in ("camera", "program"):
            video_id, video_start, video_length = video_asset(angle.video, None)
            clip_length = min(duration, video_length)
            if angle.audio:
                # Final Cut accepts a connected audio clip inside a multicam angle only through a compound clip
                # (media/sequence). A plain clip or sync-clip in an angle silently drops its connected items.
                compound_id = res.next_id()
                compound = ET.SubElement(resources_el, "media", id=compound_id, name=angle.name)
                sequence = ET.SubElement(compound, "sequence", format=format_id, duration=fmt_time(clip_length), tcStart="0s",
                                         tcFormat=tc_format, audioLayout="stereo", audioRate="48k")
                spine = ET.SubElement(sequence, "spine")
                clip = ET.SubElement(spine, "clip", name=angle.name, offset="0s", start="0s", duration=fmt_time(clip_length),
                                     format=format_id, tcFormat=tc_format)
                ET.SubElement(clip, "video", ref=video_id, offset="0s", start=fmt_time(video_start), duration=fmt_time(clip_length))
                audio_id, audio_start, audio_length = audio_asset(angle.audio)
                ET.SubElement(clip, "asset-clip", ref=audio_id, lane="-1", offset="0s", name=angle.audio.stem,
                              start=fmt_time(audio_start), duration=fmt_time(min(clip_length, audio_length)), audioRole="dialogue")
                ET.SubElement(mc_angle, "ref-clip", ref=compound_id, name=angle.name, offset=fmt_time(t0), start="0s",
                              duration=fmt_time(clip_length))
            else:
                clip = ET.SubElement(mc_angle, "clip", name=angle.name, offset=fmt_time(t0), start="0s",
                                     duration=fmt_time(clip_length), format=format_id, tcFormat=tc_format)
                ET.SubElement(clip, "video", ref=video_id, offset="0s", start=fmt_time(video_start), duration=fmt_time(clip_length))
                if angle.kind == "camera":
                    ET.SubElement(clip, "audio", ref=video_id, lane="-1", offset="0s", start=fmt_time(video_start),
                                  duration=fmt_time(clip_length), role="dialogue")
        elif angle.kind == "still":
            still_id, _, _ = video_asset(angle.video, None, still=True)
            clip = ET.SubElement(mc_angle, "clip", name=angle.name, offset=fmt_time(t0), start="0s", duration=fmt_time(duration),
                                 format=format_id, tcFormat=tc_format)
            ET.SubElement(clip, "video", ref=still_id, offset="0s", start="0s", duration=fmt_time(duration))
        else:
            audio_id, audio_start, audio_length = audio_asset(angle.audio)
            ET.SubElement(mc_angle, "asset-clip", ref=audio_id, name=angle.name, offset=fmt_time(t0), start=fmt_time(audio_start),
                          duration=fmt_time(min(duration, audio_length)), audioRole="dialogue")

    container = root
    if plan.event:
        container = ET.SubElement(root, "event", name=plan.event)

    first_camera = next((a.id for a in plan.angles if a.kind == "camera"), plan.angles[0].id)

    def mc_sources(parent: ET.Element, video_angle: str) -> None:
        if video_angle == plan.main_audio_angle:
            ET.SubElement(parent, "mc-source", angleID=video_angle, srcEnable="all")
        else:
            ET.SubElement(parent, "mc-source", angleID=video_angle, srcEnable="video")
            ET.SubElement(parent, "mc-source", angleID=plan.main_audio_angle, srcEnable="audio")

    # Browser clips: the multicam and every source file.
    browser = ET.SubElement(container, "mc-clip", ref=multicam_id, name=f"{plan.name} Multicam", start=fmt_time(t0), duration=fmt_time(duration))
    mc_sources(browser, first_camera)
    for angle in plan.angles:
        for path in (angle.video, angle.audio):
            if path is None or angle.kind == "still":
                continue
            asset_id = res.assets[path]
            start, length = asset_times[path]
            attrs = dict(ref=asset_id, name=path.stem, start=fmt_time(start), duration=fmt_time(length))
            if path == angle.video:
                attrs["format"] = format_id
                attrs["tcFormat"] = tc_format
            else:
                attrs["audioRole"] = "dialogue"
            ET.SubElement(container, "asset-clip", attrs)

    # The live switch as a timeline.
    project = ET.SubElement(container, "project", name=f"{plan.name} Live Edit")
    sequence = ET.SubElement(project, "sequence", format=format_id, duration=fmt_time(duration), tcStart="0s",
                             tcFormat=tc_format, audioLayout="stereo", audioRate="48k")
    notes = [f"Converted from {rec.name}.drp by atem-iso-to-fcpxml {__version__}."]
    notes += plan.summary()[1:]
    ET.SubElement(sequence, "note").text = "\n".join(notes)
    spine = ET.SubElement(sequence, "spine")
    program_asset = res.assets.get(rec.program_mp4) if rec.program_mp4 else None
    for cut in plan.edit.cuts:
        offset = cut.start * fd
        length = (cut.end - cut.start) * fd
        if cut.transition_in and dissolve_id:
            transition = ET.SubElement(spine, "transition", name="Cross Dissolve", offset=fmt_time(cut.transition_in.start * fd),
                                       duration=fmt_time((cut.transition_in.end - cut.transition_in.start) * fd))
            ET.SubElement(transition, "filter-video", ref=dissolve_id, name="Cross Dissolve")
        if cut.picture.kind == "angle" or (cut.picture.kind == "program" and program_asset):
            attrs = dict(ref=multicam_id, name=f"{plan.name} Multicam", offset=fmt_time(offset), start=fmt_time(t0 + offset),
                         duration=fmt_time(length))
            clip = ET.SubElement(spine, "mc-clip", attrs)
            mc_sources(clip, cut.picture.key if cut.picture.kind == "angle" else "program")
        else:
            clip = ET.SubElement(spine, "gap", name="Gap", offset=fmt_time(offset), start=fmt_time(t0 + offset), duration=fmt_time(length))
        if cut.picture.kind != "angle" or cut.picture.reason:
            suffix = {"program": " (program recording)", "gap": " (no program recording or camera found)"}.get(cut.picture.kind, "")
            ET.SubElement(clip, "marker", start=fmt_time(t0 + offset), duration=fmt_time(fd), value=f"ATEM: {cut.picture.reason}{suffix}")
        elif cut.transition_in and cut.transition_in.approximated:
            ET.SubElement(clip, "marker", start=fmt_time(t0 + offset), duration=fmt_time(fd),
                          value=f"ATEM {cut.transition_in.kind} transition shown as a cross dissolve")

    ET.indent(root, space="    ")
    body = ET.tostring(root, encoding="unicode")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fcpxml>\n\n' + body + "\n").encode("utf-8")


# ----------------------------------------------------------------------------- macOS

def _osascript(script: str, *args: str, language: str = "AppleScript") -> str:
    result = subprocess.run(["/usr/bin/osascript", "-l", language, "-", *args], input=script, capture_output=True, text=True)
    if result.returncode != 0:
        raise ConversionError(result.stderr.strip() or "The dialog could not be shown.")
    return result.stdout.rstrip("\n")


def choose_from_list(prompt: str, items: Sequence[str], defaults: Sequence[str], multiple: bool, allow_empty: bool = False) -> List[str]:
    script = f'''on run argv
set promptText to item 1 of argv
set n to (item 2 of argv) as integer
set theDefaults to {{}}
if n > 0 then set theDefaults to items 3 thru (n + 2) of argv
set theItems to items (n + 3) thru -1 of argv
set answer to choose from list theItems with title "ATEM ISO to FCPXML" with prompt promptText default items theDefaults {"with multiple selections allowed" if multiple else "without multiple selections allowed"} {"with" if allow_empty else "without"} empty selection allowed
if answer is false then error number -128
set indices to {{}}
repeat with i from 1 to count theItems
if item i of theItems is in answer then set end of indices to i
end repeat
set AppleScript's text item delimiters to ","
return indices as text
end run'''
    try:
        out = _osascript(script, prompt, str(len(defaults)), *defaults, *items)
    except ConversionError as exc:
        if "-128" in str(exc) or "User canceled" in str(exc):
            raise ConversionError("Canceled.") from None
        raise
    return [items[int(index) - 1] for index in out.split(",") if index]



def choose_checkboxes(items: Sequence[str], defaults: Sequence[str], *, title: str, prompt: str, allow_empty: bool = False) -> List[str]:
    """Native AppKit checkboxes via macOS JXA; no Python GUI dependency.

    Pass filenames as JSON data, never executable script text. Return indices so
    punctuation, Unicode, and newlines in filenames cannot change selection parsing.
    """
    script = r'''ObjC.import('AppKit');
function run(argv) {
    const data = JSON.parse(argv[0]);
    const app = $.NSApplication.sharedApplication;
    app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
    const alert = $.NSAlert.alloc.init;
    alert.messageText = data.title;
    alert.informativeText = data.prompt;
    alert.addButtonWithTitle('Continue');
    alert.addButtonWithTitle('Cancel');
    if (data.allowEmpty) alert.addButtonWithTitle('No extra audio');
    const height = Math.max(32, data.items.length * 32);
    const view = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, 440, height));
    const boxes = data.items.map(function (name, index) {
        const box = $.NSButton.alloc.initWithFrame($.NSMakeRect(0, height - (index + 1) * 32, 420, 28));
        box.setButtonType($.NSSwitchButton);
        box.title = name;
        box.toolTip = name;
        box.state = data.defaults.indexOf(name) >= 0 ? $.NSOnState : $.NSOffState;
        view.addSubview(box);
        return box;
    });
    // Keep long recordings with many sources within the screen height.
    const scroll = $.NSScrollView.alloc.initWithFrame($.NSMakeRect(0, 0, 440, Math.min(height, 256)));
    scroll.hasVerticalScroller = true;
    scroll.documentView = view;
    view.scrollPoint($.NSMakePoint(0, height));
    alert.accessoryView = scroll;
    app.activateIgnoringOtherApps(true);
    while (true) {
        const response = alert.runModal;
        if (data.allowEmpty && response === $.NSAlertThirdButtonReturn) return '[]';
        if (response !== $.NSAlertFirstButtonReturn) return 'cancel';
        const selected = boxes.reduce(function (result, box, index) {
            if (box.state === $.NSOnState) result.push(index);
            return result;
        }, []);
        if (data.allowEmpty || selected.length) return JSON.stringify(selected);
        alert.informativeText = 'Select at least one camera to continue.';
    }
}
'''
    out = _osascript(script, json.dumps({"items": list(items), "defaults": list(defaults), "title": title, "prompt": prompt, "allowEmpty": allow_empty}), language="JavaScript")
    if out == "cancel":
        raise ConversionError("Canceled.")
    return [items[index] for index in json.loads(out)]


def ask_buttons(message: str, buttons: Sequence[str], default: str, title: str = "ATEM ISO to FCPXML") -> str:
    script = f'''on run argv
set answer to display dialog (item 1 of argv) with title (item 2 of argv) buttons {{{", ".join(json.dumps(b) for b in buttons)}}} default button {json.dumps(default)}
return button returned of answer
end run'''
    try:
        return _osascript(script, message, title)
    except ConversionError as exc:
        if "-128" in str(exc) or "User canceled" in str(exc):
            raise ConversionError("Canceled.") from None
        raise


def show_alert(message: str, title: str = "ATEM ISO to FCPXML") -> None:
    subprocess.run(["/usr/bin/osascript", "-e", "on run argv", "-e", "display alert (item 1 of argv) message (item 2 of argv) as critical",
                    "-e", "end run", title, message], capture_output=True, text=True)


def interactive_choices(rec: Recording) -> Tuple[List[int], Optional[str], List[str]]:
    """Ask which inputs, which main soundtrack, and which extra WAVs to use."""
    cameras = [i for i, s in sorted(rec.sources.items()) if s.kind == "Video" and s.mp4]
    probe = build_edit_list(rec, cameras, "cut")
    used = [i for i in cameras if f"input-{i}" in probe.angles_used]
    labels = {f"Input {i}: {rec.sources[i].name}" + ("  (used in the live switch)" if i in used else ""): i for i in cameras}
    defaults = [label for label, i in labels.items() if i in used] or list(labels)[:1]
    chosen = choose_checkboxes(list(labels), defaults, title="Camera angles",
                               prompt="Select the cameras to include. Inputs used in the live switch are checked.")
    selected = [labels[c] for c in chosen]
    if not selected:
        raise ConversionError("Choose at least one input.")

    wavs = list(rec.audio_files.values())
    if not wavs:
        return selected, None, []
    first = rec.sources[selected[0]]
    default_main = first.wav.name if first.wav else wavs[0].name
    main = choose_from_list("Which WAV is the main soundtrack for the timeline?\n\nYou can switch audio angles later in Final Cut Pro.",
                            [w.name for w in wavs], [default_main], False)[0]

    selected_stems = {Path(s.relative).stem for s in rec.sources.values() if s.kind == "Video" and s.index in selected}
    camera_stems = {Path(s.relative).stem for s in rec.sources.values() if s.kind == "Video"}
    candidates = [w for w in wavs if w.stem not in selected_stems and w.name != main]
    extras: List[str] = []
    if candidates:
        suggested = [w.name for w in candidates if w.stem not in camera_stems]
        extras = choose_checkboxes([w.name for w in candidates], suggested, title="Extra audio angles",
                                   prompt="Check WAVs to add as separate audio angles. Your main soundtrack is already included.",
                                   allow_empty=True)
    return selected, main, extras


# ------------------------------------------------------------------------------- CLI

def locate_drp(target: Path) -> Path:
    target = target.expanduser()
    if target.is_dir():
        candidates = [p for p in sorted(target.iterdir()) if p.suffix.lower() == ".drp" and p.is_file() and not p.name.startswith("._")]
        if len(candidates) != 1:
            raise ConversionError(f"Expected exactly one .drp in {target.name}; found {len(candidates)}.")
        return candidates[0].resolve()
    if target.suffix.lower() == ".mp4" and target.with_suffix(".drp").is_file():
        return target.with_suffix(".drp").resolve()
    if target.suffix.lower() != ".drp" or not target.is_file():
        raise ConversionError(f"Select the ATEM .drp file (or its folder): {target}")
    return target.resolve()


def parse_cameras(text: Optional[str]) -> Optional[List[int]]:
    if text is None:
        return None
    try:
        return [int(part) for part in re.split(r"[\s,]+", text.strip()) if part]
    except ValueError as exc:
        raise ConversionError("--cameras expects input numbers such as 1,2") from exc


def write_output(output: Path, payload: bytes, replace: bool = False) -> None:
    """Publish complete XML without following output links or truncating existing files."""
    if output.is_symlink():
        raise ConversionError("Refusing a symbolic link as the output file; choose a new .fcpxml name.")
    if not replace:
        # Exclusive creation works on exFAT ATEM disks too (hard links do not).
        # It also closes the race between the earlier existence check and writing.
        try:
            fh = output.open("xb")
        except FileExistsError:
            raise ConversionError(f"{output} already exists. Use --force to replace it.") from None
        try:
            with fh:
                fh.write(payload)
                fh.flush()
                os.fsync(fh.fileno())
        except OSError:
            output.unlink(missing_ok=True)
            raise
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix=".atem-", suffix=".tmp", delete=False) as fh:
            temporary = Path(fh.name)
            fh.write(payload)
            fh.flush()
            os.fsync(fh.fileno())
        # Replace the directory entry, never truncate its inode: even a hard link
        # to a recording cannot damage that recording. Same-directory rename
        # also preserves the old XML if preparing the replacement fails.
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="atem-iso-to-fcpxml",
                                     description="Convert an ATEM Mini ISO recording (.drp) to Final Cut Pro XML.")
    parser.add_argument("input", type=Path, help="the ATEM .drp file or its recording folder")
    parser.add_argument("-o", "--output", type=Path, help="where to write the .fcpxml (default: next to the .drp)")
    parser.add_argument("--cameras", metavar="LIST", help="inputs to include as angles, e.g. 1,2 (default: inputs used in the live switch)")
    parser.add_argument("--audio", metavar="WAV", help="main soundtrack: a WAV name or suffix such as 'CAM 1' or 'MIC 1' (default: first camera's WAV)")
    parser.add_argument("--extra-audio", metavar="WAV", action="append", help="extra audio-only angle; repeatable (default: every WAV without a camera, e.g. MIC 1 and MIC 2)")
    parser.add_argument("--no-extra-audio", action="store_true", help="do not add audio-only angles")
    parser.add_argument("--transitions", choices=("dissolve", "cut", "program"), default="dissolve",
                        help="ATEM transitions become cross dissolves (default), hard cuts, or sections of the program recording")
    parser.add_argument("--program-angle", action="store_true", help="always include the program recording as an angle")
    parser.add_argument("--name", help="base name for the multicam clip and project (default: the recording folder's name)")
    parser.add_argument("--event", metavar="NAME", help="name of the Final Cut event to create (default: same as --name)")
    parser.add_argument("--no-event", action="store_true", help="omit the event; Final Cut then files everything under today's date")
    parser.add_argument("--session", type=int, metavar="N", help="which session to convert when one .drp holds several recordings")
    parser.add_argument("--force", action="store_true", help="overwrite an existing .fcpxml")
    parser.add_argument("--dry-run", action="store_true", help="print the plan without writing anything")
    parser.add_argument("--interactive", action="store_true", help="ask with macOS dialogs (used by the Finder Quick Action)")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    args = parser.parse_args(argv)

    interactive = args.interactive and sys.platform == "darwin"
    try:
        drp_path = locate_drp(args.input)
        rec = open_recording(drp_path, args.session)
        cameras = parse_cameras(args.cameras)
        audio = args.audio
        extra = [] if args.no_extra_audio else args.extra_audio
        if interactive:
            cameras, audio, chosen = interactive_choices(rec)
            extra = chosen
        plan = make_plan(rec, cameras, audio, extra, args.transitions, args.name, "" if args.no_event else args.event, args.program_angle)
        payload = build_fcpxml(plan)
        try:
            ET.fromstring(payload)  # Reject control characters before touching output.
        except ET.ParseError as exc:
            raise ConversionError("A recording name or log label contains characters that XML cannot represent. Rename it or correct the label.") from exc

        output = (args.output.expanduser() if args.output else drp_path.with_suffix(".fcpxml")).absolute()
        if output.suffix.lower() != ".fcpxml":
            raise ConversionError("The output name must end in .fcpxml")
        if args.dry_run:
            print("\n".join(plan.summary()))
            print(f"Would write {output}")
            return 0
        replace = args.force
        if output.exists() and not replace:
            if interactive:
                answer = ask_buttons(f"{output.name} already exists in this folder. Replace it?", ["Cancel", "Replace"], "Replace")
                if answer != "Replace":
                    raise ConversionError("Canceled.")
                replace = True
            else:
                raise ConversionError(f"{output} already exists. Use --force to replace it or --output for a new name.")
        protected = {drp_path.resolve()}
        protected.update(p.resolve() for p in rec.audio_files.values())
        protected.update(source.mp4.resolve() for source in rec.sources.values() if source.mp4)
        if rec.program_mp4:
            protected.add(rec.program_mp4.resolve())
        if output.resolve() in protected:
            raise ConversionError("Refusing to overwrite the .drp or recording media.")
        write_output(output, payload, replace)

        summary = plan.summary()
        print(f"Wrote {output}")
        print("\n".join(summary))
        if interactive:
            answer = ask_buttons(f"Created {output.name}\n\n" + "\n".join(summary), ["Show in Finder", "Import into Final Cut Pro"],
                                 "Import into Final Cut Pro")
            if answer == "Import into Final Cut Pro":
                subprocess.run(["/usr/bin/open", "-a", "Final Cut Pro", str(output)], check=False)
            else:
                subprocess.run(["/usr/bin/open", "-R", str(output)], check=False)
        return 0
    except ConversionError as exc:
        if str(exc) == "Canceled.":
            # Automator treats nonzero status as a failed Run Shell Script action.
            return 0
        print(f"Error: {exc}", file=sys.stderr)
        if interactive:
            show_alert(str(exc))
        return 2
    except (OSError, KeyError, TypeError, ValueError, struct.error) as exc:
        message = f"Unexpected problem: {exc!r}"
        print(message, file=sys.stderr)
        if interactive:
            show_alert(message)
        return 2


if __name__ == "__main__":
    sys.exit(main())
