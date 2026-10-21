"""Tests with synthetic recordings only: tiny generated MP4/WAV/PNG files and invented logs.

No real footage, DRP, or personal path is needed or allowed here.
"""
from __future__ import annotations

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from fractions import Fraction as F
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import atem_iso_to_fcpxml as c  # noqa: E402

FCP_DTD = Path("/Applications/Final Cut Pro.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv1_10.dtd")


# ---------------------------------------------------------------- synthetic media

def box(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I4s", 8 + len(payload), kind) + payload


def make_mp4(path: Path, frames: int, timescale: int = 60, frame_duration: int = 1, width: int = 1920, height: int = 1080,
             tc_frames: int | None = None, tc_fps: int = 60, drop: bool = False, audio: bool = True) -> None:
    """Write a structurally valid MP4 index with no real picture data."""
    duration = frames * frame_duration
    mdat_payload = struct.pack(">I", tc_frames or 0) + b"\0" * 12
    # Layout: ftyp, moov, mdat. The moov size depends on itself only through stco, so build it twice.
    ftyp = box(b"ftyp", b"isom" + struct.pack(">I", 1) + b"isomiso4avc1")

    def tkhd(track_id: int, w: int, h: int) -> bytes:
        body = struct.pack(">I", 0) + struct.pack(">III", 0, 0, track_id) + b"\0" * 4 + struct.pack(">I", duration)
        body += b"\0" * 8 + struct.pack(">HHHH", 0, 0, 0x0100, 0) + b"\0" * 36 + struct.pack(">II", w << 16, h << 16)
        return box(b"tkhd", body)

    def mdhd(ts: int, dur: int) -> bytes:
        return box(b"mdhd", struct.pack(">I", 0) + struct.pack(">IIII", 0, 0, ts, dur) + struct.pack(">HH", 0x55C4, 0))

    def hdlr(kind: bytes) -> bytes:
        return box(b"hdlr", struct.pack(">I", 0) + b"\0" * 4 + kind + b"\0" * 12 + b"\0")

    def stbl(stsd_entry: bytes, sample_count: int, delta: int, chunk_offset: int) -> bytes:
        stsd = box(b"stsd", struct.pack(">II", 0, 1) + stsd_entry)
        stts = box(b"stts", struct.pack(">II", 0, 1) + struct.pack(">II", sample_count, delta))
        stsc = box(b"stsc", struct.pack(">II", 0, 1) + struct.pack(">III", 1, sample_count, 1))
        stsz = box(b"stsz", struct.pack(">III", 0, 4, sample_count))
        stco = box(b"stco", struct.pack(">II", 0, 1) + struct.pack(">I", chunk_offset))
        return box(b"stbl", stsd + stts + stsc + stsz + stco)

    def trak(track_id: int, kind: bytes, w: int, h: int, ts: int, dur: int, entry: bytes, count: int, delta: int, chunk: int) -> bytes:
        minf = box(b"minf", box(b"vmhd", b"\0" * 12) + box(b"dinf", box(b"dref", struct.pack(">II", 0, 1) + box(b"url ", struct.pack(">I", 1))))
                   + stbl(entry, count, delta, chunk))
        return box(b"trak", tkhd(track_id, w, h) + box(b"mdia", mdhd(ts, dur) + hdlr(kind) + minf))

    avc1 = box(b"avc1", b"\0" * 6 + struct.pack(">H", 1) + b"\0" * 16 + struct.pack(">HH", width, height) + b"\0" * 50)
    tc_flags = 0x1 if drop else 0x0
    tmcd = box(b"tmcd", b"\0" * 6 + struct.pack(">H", 1) + struct.pack(">I", 0) + struct.pack(">IIIB", tc_flags, tc_fps, 1, tc_fps) + b"\0")
    mp4a = box(b"mp4a", b"\0" * 6 + struct.pack(">H", 1) + b"\0" * 8 + struct.pack(">HHHH", 2, 16, 0, 0) + struct.pack(">I", 48000 << 16))

    def moov(chunk_offset: int) -> bytes:
        mvhd = box(b"mvhd", struct.pack(">I", 0) + struct.pack(">IIII", 0, 0, timescale, duration) + b"\0" * 80)
        tracks = trak(1, b"vide", width, height, timescale, duration, avc1, frames, frame_duration, chunk_offset + 4)
        if tc_frames is not None:
            tracks += trak(2, b"tmcd", width, 20, timescale, duration, tmcd, 1, duration, chunk_offset)
        if audio:
            tracks += trak(3, b"soun", 0, 0, 48000, frames * 800, mp4a, frames, 800, chunk_offset + 8)
        return box(b"moov", mvhd + tracks)

    first = moov(0)
    chunk_offset = len(ftyp) + len(first) + 8
    data = ftyp + moov(chunk_offset) + box(b"mdat", mdat_payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def make_wav(path: Path, sample_frames: int, time_reference: int | None = None, rate: int = 48000, channels: int = 2,
             bits: int = 24, with_data: bool = False) -> None:
    align = channels * bits // 8
    fmt = box_le(b"fmt ", struct.pack("<HHIIHH", 1, channels, rate, rate * align, align, bits))
    chunks = fmt
    if time_reference is not None:
        bext = bytes(256) + bytes(32) + bytes(32) + b"2026:01:01" + b"10:00:00" + struct.pack("<Q", time_reference) + bytes(2) + bytes(64) + bytes(10) + bytes(180)
        chunks += box_le(b"bext", bext)
    data_size = sample_frames * align
    chunks += struct.pack("<4sI", b"data", data_size)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + len(chunks) + data_size) + b"WAVE" + chunks)
        fh.truncate(fh.tell() + data_size)  # a sparse file: the parser reads headers, never samples


def box_le(tag: bytes, payload: bytes) -> bytes:
    return struct.pack("<4sI", tag, len(payload)) + payload + (b"\0" if len(payload) % 2 else b"")


def make_png(path: Path, width: int = 1920, height: int = 1080) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + ihdr + b"\0" * 4)


# ---------------------------------------------------------------- synthetic recording

def header(tc: str = "10:00:00:00", mode: str = "1080p60", name: str = "Show", first_source: int = 1,
           transition_type: str | None = "Mix") -> dict:
    block = dict(_index_=0, onAir=True, source=first_source, transitionActive=False, transitionPosition=1.0,
                 fadeToBlack="Inactive", upstreamKeys=[dict(_index_=0, keyType="Luma", onAir=False, fillSource=8)])
    if transition_type:
        block["transitionType"] = transition_type
    return dict(version=1, masterTimecode=tc, videoMode=mode, recordingId="00abcdef",
                sources=[dict(_index_=0, name="Black", type="Color"),
                         *[dict(_index_=i, name=f"Camera {i}", type="Video", volume="DISK", projectPath=name,
                                file=f"Video ISO Files/{name} CAM {i}.mp4", startTimecode=tc) for i in (1, 2, 3, 4)],
                         dict(_index_=5, name="Color Bars", type="ColorBars"),
                         dict(_index_=8, name="Media Player 1", type="Still", volume="DISK", projectPath=name,
                              file=f"Video ISO Files/Media Files/logo.png", startTimecode="00:00:00:00")],
                mixEffectBlocks=[block], downstreamKeys=[dict(_index_=0, onAir=False, faderState="Idle", fillSource=8)])


def me(tc: str, **changes) -> dict:
    return dict(masterTimecode=tc, mixEffectBlocks=[dict(_index_=0, **changes)])


class RecordingDir:
    """A fake ATEM recording folder on disk."""

    def __init__(self, tc: str = "10:00:00:00", frames: int = 1200, name: str = "Show", folder: str = "Show",
                 mode: str = "1080p60", tc_fps: int = 60, cameras=(1, 2, 3, 4), mics=("MIC 1", "MIC 2"), program: bool = True,
                 still: bool = True, drop: bool = False):
        self.tmp = tempfile.TemporaryDirectory(prefix="atem test & ")
        self.root = Path(self.tmp.name) / folder
        self.root.mkdir()
        self.name = name
        self.frames = frames
        self.fps = F(c.parse_video_mode(mode)[2])
        self.tc_frames = c.Timecode.parse(tc, self.fps).frames
        self.samples = int(frames * 48000 / self.fps)
        self.time_reference = int(self.tc_frames / self.fps * 48000)
        timescale = self.fps.numerator
        frame_duration = self.fps.denominator
        if program:
            make_mp4(self.root / f"{name}.mp4", frames, timescale, frame_duration, tc_frames=self.tc_frames, tc_fps=tc_fps, drop=drop)
        for i in cameras:
            make_mp4(self.root / "Video ISO Files" / f"{name} CAM {i}.mp4", frames, timescale, frame_duration, tc_frames=self.tc_frames, tc_fps=tc_fps, drop=drop)
            make_wav(self.root / "Audio Source Files" / f"{name} CAM {i}.wav", self.samples, self.time_reference)
        for mic in mics:
            make_wav(self.root / "Audio Source Files" / f"{name} {mic}.wav", self.samples, self.time_reference)
        if still:
            make_png(self.root / "Video ISO Files" / "Media Files" / "logo.png")
        self.drp = self.root / f"{name}.drp"
        self.rows = [header(tc, mode, name)]

    def write(self, rows=None) -> Path:
        rows = self.rows if rows is None else rows
        self.drp.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
        return self.drp

    def cleanup(self):
        self.tmp.cleanup()


def frames_to_tc(frames: int, fps: int = 60) -> str:
    s, f = divmod(frames, fps)
    return f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}:{f:02d}"


# ---------------------------------------------------------------------------- tests

class TimingTests(unittest.TestCase):
    def test_video_modes(self):
        self.assertEqual(c.parse_video_mode("1080p60"), (1080, False, F(60)))
        self.assertEqual(c.parse_video_mode("1080p5994")[2], F(60000, 1001))
        self.assertEqual(c.parse_video_mode("1080p29.97")[2], F(30000, 1001))
        self.assertEqual(c.parse_video_mode("1080p23.98")[2], F(24000, 1001))
        self.assertEqual(c.parse_video_mode("720p50"), (720, False, F(50)))
        self.assertEqual(c.parse_video_mode("1080i5994"), (1080, True, F(30000, 1001)))
        self.assertEqual(c.parse_video_mode("2160p25"), (2160, False, F(25)))
        for bad in ("", "1080x60", "1080p999", "pal"):
            with self.assertRaises(c.ConversionError):
                c.parse_video_mode(bad)

    def test_timecode_parse_and_label(self):
        self.assertEqual(c.Timecode.parse("10:00:00:00", F(60)).frames, 2160000)
        self.assertEqual(c.Timecode.parse("11:34:32:07", F(60)).frames, 2500327)
        self.assertEqual(c.Timecode.label(2500327, F(60), False), "11:34:32:07")
        self.assertEqual(c.Timecode.parse("00:10:00;00", F(30000, 1001)).frames, 17982)
        self.assertEqual(c.Timecode.parse("00:01:00;04", F(60000, 1001)).frames, 3600)
        for frames in (0, 1, 1799, 1800, 17982, 107892, 123456, 2589406):
            label = c.Timecode.label(frames, F(30000, 1001), True)
            self.assertEqual(c.Timecode.parse(label, F(30000, 1001)).frames, frames, label)
        for bad in ("24:00:00:00", "00:60:00:00", "00:00:00:60", "oops", "00:01:00;00"):
            with self.assertRaises(c.ConversionError):
                c.Timecode.parse(bad, F(60) if ";" not in bad else F(30000, 1001))

    def test_fmt_time(self):
        self.assertEqual(c.fmt_time(F(2798)), "2798s")
        self.assertEqual(c.fmt_time(F(1001, 60000)), "1001/60000s")
        self.assertEqual(c.fmt_time(F(2, 4)), "1/2s")


class StateTests(unittest.TestCase):
    def test_sparse_patch_keeps_nested_keys(self):
        state = dict(mixEffectBlocks=[dict(_index_=0, source=1, upstreamKeys=[dict(_index_=0, onAir=True)])])
        c.merge_state(state, dict(mixEffectBlocks=[dict(_index_=0, source=2)]))
        self.assertEqual(state["mixEffectBlocks"][0]["source"], 2)
        self.assertTrue(state["mixEffectBlocks"][0]["upstreamKeys"][0]["onAir"])
        c.merge_state(state, dict(downstreamKeys=[dict(_index_=1, onAir=True)]))
        self.assertEqual(state["downstreamKeys"], [dict(_index_=1, onAir=True)])

    def test_load_drp_rejects_resolve_archive_and_garbage(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.drp"
            path.write_bytes(b"PK\x03\x04junk")
            with self.assertRaisesRegex(c.ConversionError, "Resolve"):
                c.load_drp(path)
            path.write_text("not json\n")
            with self.assertRaises(c.ConversionError):
                c.load_drp(path)
            path.write_text(json.dumps(dict(masterTimecode="00:00:00:00")) + "\n")
            with self.assertRaises(c.ConversionError):
                c.load_drp(path)

    def test_multi_session_requires_choice(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.drp"
            rows = [header(), me("10:00:01:00", source=2), header("11:00:00:00"), me("11:00:05:00", source=3)]
            path.write_text("\n".join(json.dumps(r) for r in rows))
            with self.assertRaisesRegex(c.ConversionError, "2 recording sessions"):
                c.load_drp(path)
            second = c.load_drp(path, session=2)
            self.assertEqual(second.header["masterTimecode"], "11:00:00:00")
            self.assertEqual(len(second.events), 1)
            with self.assertRaises(c.ConversionError):
                c.load_drp(path, session=3)


class ProbeTests(unittest.TestCase):
    def test_mp4_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.mp4"
            make_mp4(path, 167880, 60, 1, tc_frames=2500327)
            info = c.probe_mp4(path)
            self.assertEqual((info.width, info.height, info.frame_rate, info.frames), (1920, 1080, F(60), 167880))
            self.assertEqual(info.duration, F(2798))
            self.assertEqual(info.timecode_frames, 2500327)
            self.assertTrue(info.has_audio)
            self.assertFalse(info.drop_frame)
            make_mp4(path, 100, 60000, 1001, tc_frames=10, tc_fps=60, drop=True, audio=False)
            info = c.probe_mp4(path)
            self.assertEqual(info.frame_rate, F(60000, 1001))
            self.assertTrue(info.drop_frame)
            self.assertFalse(info.has_audio)
            path.write_bytes(b"\0" * 64)
            with self.assertRaises(c.ConversionError):
                c.probe_mp4(path)

    def test_wav_headers(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.wav"
            make_wav(path, 134304000, 2000261600)
            info = c.probe_wav(path)
            self.assertEqual((info.channels, info.sample_rate, info.bits, info.sample_frames), (2, 48000, 24, 134304000))
            self.assertEqual(info.time_reference, 2000261600)
            self.assertEqual(info.duration, F(2798))
            make_wav(path, 48000, None, bits=16)
            info = c.probe_wav(path)
            self.assertIsNone(info.time_reference)
            self.assertEqual(info.sample_frames, 48000)
            path.write_bytes(b"RIFF" + struct.pack("<I", 4) + b"WAVE")
            with self.assertRaises(c.ConversionError):
                c.probe_wav(path)
            path.write_bytes(b"hello")
            with self.assertRaises(c.ConversionError):
                c.probe_wav(path)

    def test_png_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "logo.png"
            make_png(path, 1280, 720)
            self.assertEqual(c.probe_image_size(path), (1280, 720))
            path.write_bytes(b"GIF89a")
            self.assertIsNone(c.probe_image_size(path))


class EditListTests(unittest.TestCase):
    def setUp(self):
        self.rec_dir = RecordingDir(frames=1200)
        self.addCleanup(self.rec_dir.cleanup)

    def segments(self, rows, cameras=(1, 2), transitions="dissolve", **kwargs):
        self.rec_dir.write(rows)
        rec = c.open_recording(self.rec_dir.drp)
        edit = c.build_edit_list(rec, cameras, transitions)
        return rec, edit

    def test_plain_cuts_and_end_event(self):
        rows = [header(), me("10:00:05:00", source=2), me("10:00:12:00", source=1), me("10:00:20:00", onAir=False)]
        rec, edit = self.segments(rows)
        self.assertEqual([(x.start, x.end, x.picture.key) for x in edit.cuts], [(0, 300, "input-1"), (300, 720, "input-2"), (720, 1200, "input-1")])
        self.assertEqual(edit.angles_used, ["input-1", "input-2"])
        self.assertFalse(rec.warnings)

    def test_mix_transition_becomes_centered_dissolve(self):
        rows = [header(), me("10:00:05:00", transitionActive=True, transitionPosition=0.0),
                me("10:00:05:30", source=2, transitionActive=False, transitionPosition=1.0), me("10:00:20:00", onAir=False)]
        _, edit = self.segments(rows)
        self.assertEqual([(x.start, x.end, x.picture.key) for x in edit.cuts], [(0, 315, "input-1"), (315, 1200, "input-2")])
        t = edit.cuts[1].transition_in
        self.assertEqual((t.start, t.end, t.kind, t.approximated), (300, 330, "Mix", False))

    def test_odd_length_transition_is_rounded_to_even(self):
        rows = [header(), me("10:00:05:00", transitionActive=True), me("10:00:05:29", source=2, transitionActive=False)]
        _, edit = self.segments(rows)
        t = edit.cuts[1].transition_in
        self.assertEqual((t.start, t.end), (300, 330))
        self.assertEqual(edit.cuts[0].end, 315)

    def test_wipe_is_approximated_and_flagged(self):
        rows = [header(transition_type="Wipe"), me("10:00:05:00", transitionActive=True), me("10:00:06:00", source=2, transitionActive=False)]
        _, edit = self.segments(rows)
        self.assertTrue(edit.cuts[1].transition_in.approximated)
        self.assertEqual(edit.cuts[1].transition_in.kind, "Wipe")

    def test_transition_modes_cut_and_program(self):
        rows = [header(), me("10:00:05:00", transitionActive=True), me("10:00:05:30", source=2, transitionActive=False)]
        _, edit = self.segments(rows, transitions="cut")
        self.assertEqual([(x.start, x.end, x.picture.key) for x in edit.cuts], [(0, 315, "input-1"), (315, 1200, "input-2")])
        self.assertIsNone(edit.cuts[1].transition_in)
        _, edit = self.segments(rows, transitions="program")
        self.assertEqual([(x.start, x.end, x.picture.kind) for x in edit.cuts], [(0, 300, "angle"), (300, 330, "program"), (330, 1200, "angle")])
        self.assertIn("Mix transition", edit.cuts[1].picture.reason)

    def test_transition_back_to_same_source_is_ignored(self):
        rows = [header(), me("10:00:05:00", transitionActive=True), me("10:00:05:30", transitionActive=False)]
        _, edit = self.segments(rows)
        self.assertEqual([(x.start, x.end, x.picture.key) for x in edit.cuts], [(0, 1200, "input-1")])

    def test_keys_fade_and_generators_use_program_recording(self):
        rows = [header(), dict(masterTimecode="10:00:02:00", downstreamKeys=[dict(_index_=0, onAir=True)]),
                dict(masterTimecode="10:00:04:00", downstreamKeys=[dict(_index_=0, onAir=False)]),
                me("10:00:06:00", fadeToBlack="Active"), me("10:00:08:00", fadeToBlack="Inactive"),
                me("10:00:10:00", source=5), me("10:00:12:00", source=1),
                me("10:00:14:00", mixEffectBlocks=None) if False else dict(masterTimecode="10:00:14:00", mixEffectBlocks=[dict(_index_=0, upstreamKeys=[dict(_index_=0, onAir=True)])]),
                dict(masterTimecode="10:00:16:00", mixEffectBlocks=[dict(_index_=0, upstreamKeys=[dict(_index_=0, onAir=False)])])]
        _, edit = self.segments(rows)
        kinds = [(x.start, x.end, x.picture.kind, x.picture.reason) for x in edit.cuts]
        self.assertEqual(kinds[1], (120, 240, "program", "downstream key on air"))
        self.assertEqual(kinds[3], (360, 480, "program", "fade to black"))
        self.assertEqual(kinds[5], (600, 720, "program", "Color Bars generator"))
        self.assertEqual(kinds[7], (840, 960, "program", "upstream key on air"))
        self.assertEqual(kinds[8], (960, 1200, "angle", ""))

    def test_transition_into_key_falls_back_to_program(self):
        rows = [header(), me("10:00:05:00", transitionActive=True),
                dict(masterTimecode="10:00:05:30", mixEffectBlocks=[dict(_index_=0, source=2, transitionActive=False)], downstreamKeys=[dict(_index_=0, onAir=True)])]
        _, edit = self.segments(rows)
        self.assertEqual([(x.start, x.end, x.picture.kind) for x in edit.cuts],
                         [(0, 300, "angle"), (300, 330, "program"), (330, 1200, "program")])
        self.assertIsNone(edit.cuts[1].transition_in)
        self.assertEqual(edit.cuts[1].picture.reason, "ATEM Mix transition; downstream key on air")
        self.assertEqual(edit.cuts[2].picture.reason, "downstream key on air")

    def test_still_is_an_angle(self):
        rows = [header(first_source=8), me("10:00:05:00", source=1)]
        _, edit = self.segments(rows)
        self.assertEqual(edit.cuts[0].picture.key, "still-8-logo")
        self.assertIn("still-8-logo", edit.stills)
        self.assertEqual(edit.stills["still-8-logo"][1], "Media Player 1")

    def test_missing_still_uses_program(self):
        (self.rec_dir.root / "Video ISO Files" / "Media Files" / "logo.png").unlink()
        rows = [header(first_source=8), me("10:00:05:00", source=1)]
        rec, edit = self.segments(rows)
        self.assertEqual(edit.cuts[0].picture.kind, "program")
        self.assertIn("still image not found", edit.cuts[0].picture.reason)
        self.assertTrue(any("logo.png" in w for w in rec.warnings))

    def test_deselected_camera_uses_program_and_missing_program_uses_gap(self):
        rows = [header(), me("10:00:05:00", source=3), me("10:00:10:00", source=1)]
        _, edit = self.segments(rows, cameras=(1, 2))
        self.assertEqual((edit.cuts[1].picture.kind, edit.cuts[1].picture.reason), ("program", "Camera 3 not included in the multicam"))
        (self.rec_dir.root / "Show.mp4").unlink()
        rec, edit = self.segments(rows, cameras=(1, 2))
        self.assertEqual(edit.cuts[1].picture.kind, "gap")
        self.assertTrue(any("Program recording" in w for w in rec.warnings))

    def test_midnight_wrap_and_order(self):
        self.rec_dir.cleanup()
        self.rec_dir = RecordingDir(tc="23:59:55:00", frames=1200)
        rows = [header("23:59:55:00"), me("00:00:05:00", source=2), me("00:00:15:00", onAir=False)]
        _, edit = self.segments(rows)
        self.assertEqual([(x.start, x.end, x.picture.key) for x in edit.cuts], [(0, 600, "input-1"), (600, 1200, "input-2")])
        self.rec_dir.write([header("23:59:55:00"), me("00:00:05:00", source=2), me("23:59:58:00", source=1)])
        with self.assertRaisesRegex(c.ConversionError, "chronological"):
            c.build_edit_list(c.open_recording(self.rec_dir.drp), (1, 2))

    def test_events_past_the_media_are_clamped(self):
        rows = [header(), me("10:00:30:00", source=2), me("10:00:40:00", onAir=False)]
        rec, edit = self.segments(rows)
        self.assertEqual([(x.start, x.end) for x in edit.cuts], [(0, 1200)])
        self.assertTrue(any("frames" in w for w in rec.warnings))


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.rec_dir = RecordingDir(frames=600)
        self.addCleanup(self.rec_dir.cleanup)
        self.rec_dir.write([header(), me("10:00:03:00", source=2), me("10:00:06:00", source=1), me("10:00:10:00", onAir=False)])

    def test_defaults_follow_the_live_switch(self):
        plan = c.make_plan(c.open_recording(self.rec_dir.drp))
        self.assertEqual([(a.id, a.kind) for a in plan.angles],
                         [("input-1", "camera"), ("input-2", "camera"), ("audio-show-mic-1", "audio"), ("audio-show-mic-2", "audio")])
        self.assertEqual(plan.main_audio_angle, "input-1")
        self.assertEqual(plan.angles[2].name, "MIC 1")
        self.assertEqual((plan.name, plan.event), ("Show", "Show"))

    def test_explicit_choices(self):
        rec = c.open_recording(self.rec_dir.drp)
        plan = c.make_plan(rec, cameras=[1, 2, 3], audio="MIC 1", extra_audio=["CAM 4"], name="Demo", event="")
        self.assertEqual([a.id for a in plan.angles], ["input-1", "input-2", "input-3", "audio-show-mic-1", "audio-show-cam-4"])
        self.assertEqual(plan.main_audio_angle, "audio-show-mic-1")
        self.assertEqual(plan.event, "")
        with self.assertRaisesRegex(c.ConversionError, "no ISO recording"):
            c.make_plan(rec, cameras=[9])
        with self.assertRaisesRegex(c.ConversionError, "No WAV named"):
            c.make_plan(rec, audio="MIC 7")
        with self.assertRaisesRegex(c.ConversionError, "several"):
            c.make_plan(rec, audio="1")

    def test_camera_without_wav_keeps_mp4_audio(self):
        (self.rec_dir.root / "Audio Source Files" / "Show CAM 2.wav").unlink()
        rec = c.open_recording(self.rec_dir.drp)
        plan = c.make_plan(rec, extra_audio=[])
        self.assertIsNone(plan.angles[1].audio)
        self.assertTrue(any("no WAV" in w for w in rec.warnings))
        xml = ET.fromstring(c.build_fcpxml(plan))
        angle = xml.find(".//mc-angle[@angleID='input-2']/clip")
        self.assertIsNotNone(angle.find("audio"))

    def test_program_angle_only_when_needed(self):
        rec = c.open_recording(self.rec_dir.drp)
        self.assertNotIn("program", [a.id for a in c.make_plan(rec).angles])
        self.assertIn("program", [a.id for a in c.make_plan(rec, include_program=True).angles])
        self.assertIn("program", [a.id for a in c.make_plan(rec, cameras=[1]).angles])


class XmlTests(unittest.TestCase):
    def setUp(self):
        self.rec_dir = RecordingDir(frames=1200, folder="Live & Show")
        self.addCleanup(self.rec_dir.cleanup)
        self.rec_dir.write([header(first_source=8), me("10:00:02:00", transitionActive=True), me("10:00:02:30", source=1, transitionActive=False),
                            me("10:00:10:00", source=2), dict(masterTimecode="10:00:15:00", downstreamKeys=[dict(_index_=0, onAir=True)]),
                            dict(masterTimecode="10:00:17:00", downstreamKeys=[dict(_index_=0, onAir=False)]), me("10:00:20:00", onAir=False)])
        self.plan = c.make_plan(c.open_recording(self.rec_dir.drp))
        self.payload = c.build_fcpxml(self.plan)
        self.xml = ET.fromstring(self.payload)

    def test_resources_and_angles(self):
        fmt = self.xml.find("./resources/format")
        self.assertEqual((fmt.get("frameDuration"), fmt.get("width"), fmt.get("name")), ("1/60s", "1920", "FFVideoFormat1080p60"))
        angles = self.xml.findall("./resources/media/multicam/mc-angle")
        self.assertEqual([a.get("angleID") for a in angles], ["input-1", "input-2", "still-8-logo", "program", "audio-show-mic-1", "audio-show-mic-2"])
        self.assertEqual([a.get("name") for a in angles], ["Camera 1", "Camera 2", "Media Player 1", "Program", "MIC 1", "MIC 2"])
        multicam = self.xml.find("./resources/media/multicam")
        self.assertEqual(multicam.get("tcStart"), "36000s")
        # Camera angles reference a compound clip that pairs ISO video with the WAV.
        ref = angles[0].find("ref-clip")
        compound = self.xml.find(f"./resources/media[@id='{ref.get('ref')}']/sequence/spine/clip")
        self.assertEqual(compound.find("video").get("start"), "36000s")
        wav = compound.find("asset-clip")
        self.assertEqual((wav.get("lane"), wav.get("start")), ("-1", "36000s"))
        self.assertTrue(self.xml.find(f"./resources/asset[@id='{wav.get('ref')}']").get("name").endswith("CAM 1.wav"))
        self.assertIsNone(compound.find("audio"))
        # Stills get a rate-undefined format and a zero-length asset, program is video only, mics are audio only.
        still = angles[2].find("clip/video")
        still_asset = self.xml.find(f"./resources/asset[@id='{still.get('ref')}']")
        self.assertEqual(still_asset.get("duration"), "0s")
        self.assertEqual(self.xml.find(f"./resources/format[@id='{still_asset.get('format')}']").get("name"), "FFVideoFormatRateUndefined")
        self.assertIsNotNone(angles[3].find("clip/video"))
        self.assertIsNone(angles[3].find("clip/asset-clip"))
        self.assertEqual(angles[4].find("asset-clip").get("audioRole"), "dialogue")

    def test_urls_are_escaped(self):
        text = self.payload.decode()
        self.assertIn("Live%20%26%20Show", text)
        self.assertNotIn("Live & Show/", text)

    def test_event_and_browser_clips(self):
        event = self.xml.find("./event")
        self.assertEqual(event.get("name"), "Live & Show")
        names = [el.get("name") for el in event]
        self.assertEqual(names[0], "Live & Show Multicam")
        self.assertIn("Show CAM 1", names)
        self.assertIn("Show MIC 2", names)
        self.assertEqual(event.find("project").get("name"), "Live & Show Live Edit")

    def test_timeline(self):
        spine = self.xml.find("./event/project/sequence/spine")
        items = [(el.tag, el.get("offset"), el.get("start"), el.get("duration")) for el in spine]
        self.assertEqual(items[0], ("mc-clip", "0s", "36000s", "9/4s"))
        self.assertEqual(items[1], ("transition", "2s", None, "1/2s"))
        self.assertEqual(items[2], ("mc-clip", "9/4s", "144009/4s", "31/4s"))
        self.assertEqual([tuple(m.attrib.values()) for m in spine[0].findall("mc-source")], [("still-8-logo", "video"), ("input-1", "audio")])
        self.assertEqual([tuple(m.attrib.values()) for m in spine[2].findall("mc-source")], [("input-1", "all")])
        key_section = spine[4]
        self.assertEqual([tuple(m.attrib.values()) for m in key_section.findall("mc-source")], [("program", "video"), ("input-1", "audio")])
        self.assertIn("downstream key on air", key_section.find("marker").get("value"))
        self.assertEqual(spine[1].find("filter-video").get("name"), "Cross Dissolve")
        self.assertEqual(self.xml.find("./resources/effect").get("uid"), c.CROSS_DISSOLVE_UID)
        self.assertIn("1 cross dissolves", self.xml.find("./event/project/sequence/note").text)

    def test_drop_frame_and_fractional_rates(self):
        self.rec_dir.cleanup()
        self.rec_dir = RecordingDir(tc="10:00:00;00", frames=1800, mode="1080p5994", tc_fps=60, drop=True)
        self.rec_dir.write([header("10:00:00;00", "1080p5994"), me("10:00:10;00", source=2), me("10:00:30;02", onAir=False)])
        plan = c.make_plan(c.open_recording(self.rec_dir.drp))
        xml = ET.fromstring(c.build_fcpxml(plan))
        self.assertEqual(xml.find("./resources/format").get("frameDuration"), "1001/60000s")
        self.assertEqual(xml.find("./resources/format").get("name"), "FFVideoFormat1080p5994")
        self.assertEqual(xml.find("./resources/media/multicam").get("tcFormat"), "DF")
        clips = xml.findall("./event/project/sequence/spine/mc-clip")
        self.assertEqual(clips[1].get("offset"), c.fmt_time(F(600 * 1001, 60000)))

    def test_no_event_and_custom_names(self):
        plan = c.make_plan(c.open_recording(self.rec_dir.drp), name="Demo", event="")
        xml = ET.fromstring(c.build_fcpxml(plan))
        self.assertIsNone(xml.find("./event"))
        self.assertEqual(xml.find("./project").get("name"), "Demo Live Edit")
        self.assertEqual(xml.find("./mc-clip").get("name"), "Demo Multicam")

    @unittest.skipUnless(FCP_DTD.is_file() and shutil.which("xmllint"), "Final Cut Pro DTD and xmllint are only available on a Mac with Final Cut Pro")
    def test_validates_against_apple_dtd(self):
        with tempfile.TemporaryDirectory() as tmp:
            dtd = Path(tmp) / "fcpxml.dtd"
            shutil.copy(FCP_DTD, dtd)
            out = Path(tmp) / "out.fcpxml"
            out.write_bytes(self.payload)
            result = subprocess.run(["xmllint", "--noout", "--dtdvalid", str(dtd), str(out)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


class CliTests(unittest.TestCase):
    def setUp(self):
        self.rec_dir = RecordingDir(frames=600)
        self.addCleanup(self.rec_dir.cleanup)
        self.rec_dir.write([header(), me("10:00:05:00", source=2), me("10:00:10:00", onAir=False)])

    def run_main(self, *args):
        from io import StringIO
        import contextlib
        out, err = StringIO(), StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = c.main([str(a) for a in args])
        return code, out.getvalue(), err.getvalue()

    def test_folder_input_writes_beside_the_drp(self):
        code, out, _ = self.run_main(self.rec_dir.root)
        self.assertEqual(code, 0, out)
        output = self.rec_dir.root / "Show.fcpxml"
        self.assertTrue(output.is_file())
        self.assertIn("Wrote", out)
        self.assertIn("2 clips", out)
        code, _, err = self.run_main(self.rec_dir.root)
        self.assertEqual(code, 2)
        self.assertIn("already exists", err)
        self.assertEqual(self.run_main(self.rec_dir.root, "--force")[0], 0)

    def test_dry_run_writes_nothing(self):
        code, out, _ = self.run_main(self.rec_dir.drp, "--dry-run", "--cameras", "1,2,3", "--audio", "MIC 2", "--transitions", "cut")
        self.assertEqual(code, 0)
        self.assertFalse((self.rec_dir.root / "Show.fcpxml").exists())
        self.assertIn("Would write", out)
        self.assertIn("MIC 2", out)

    def test_bad_inputs(self):
        self.assertEqual(self.run_main(self.rec_dir.root / "missing.drp")[0], 2)
        self.assertEqual(self.run_main(self.rec_dir.drp, "--cameras", "one")[0], 2)
        self.assertEqual(self.run_main(self.rec_dir.drp, "-o", self.rec_dir.root / "out.xml")[0], 2)
        (self.rec_dir.root / "Second.drp").write_text("{}")
        self.assertEqual(self.run_main(self.rec_dir.root)[0], 2)

    def test_output_option_and_event(self):
        target = self.rec_dir.root / "custom.fcpxml"
        code, _, _ = self.run_main(self.rec_dir.drp, "-o", target, "--event", "Demo", "--no-extra-audio")
        self.assertEqual(code, 0)
        xml = ET.parse(target).getroot()
        self.assertEqual(xml.find("./event").get("name"), "Demo")
        self.assertEqual(len(xml.findall(".//mc-angle")), 2)


if __name__ == "__main__":
    unittest.main()
