#!/usr/bin/env python3
"""Convert native ATEM ISO event-log DRPs to editable Final Cut Pro XML."""
from __future__ import annotations

import argparse
import copy
from dataclasses import dataclass
from fractions import Fraction
import json
from pathlib import Path
import re
import shutil
import subprocess
import struct
import sys
import xml.etree.ElementTree as ET

__version__ = "0.1.0"
MAX_DRP_BYTES = 16 * 1024 * 1024


class ConversionError(ValueError):
    """An input cannot safely be converted."""


def seconds(value: Fraction) -> str:
    value = Fraction(value)
    return f"{value.numerator}/{value.denominator}s" if value.denominator != 1 else f"{value.numerator}s"


def video_mode(mode: str) -> tuple[int, int, Fraction]:
    match = re.fullmatch(r"(720|1080)p(23\.98|23\.976|2398|24|25|29\.97|2997|30|50|59\.94|5994|60)", mode)
    if not match:
        raise ConversionError(f"Unsupported videoMode: {mode!r}; progressive 720/1080 only.")
    rates = {"23.98": Fraction(24000, 1001), "23.976": Fraction(24000, 1001),
             "2398": Fraction(24000, 1001), "29.97": Fraction(30000, 1001),
             "2997": Fraction(30000, 1001), "59.94": Fraction(60000, 1001),
             "5994": Fraction(60000, 1001)}
    rate = rates.get(match[2]) or Fraction(match[2])
    return (1920, 1080, rate) if match[1] == "1080" else (1280, 720, rate)


def timecode_frames(label: str, fps: Fraction) -> int:
    match = re.fullmatch(r"(\d{2}):(\d{2}):(\d{2})([:;])(\d{2})", label)
    if not match:
        raise ConversionError(f"Invalid timecode: {label!r}")
    h, m, s, sep, f = match.groups()
    h, m, s, f = map(int, (h, m, s, f))
    nominal = round(fps)
    if h >= 24 or m >= 60 or s >= 60 or f >= nominal:
        raise ConversionError(f"Out-of-range timecode: {label}")
    frames = ((h * 60 + m) * 60 + s) * nominal + f
    if sep == ";":
        if fps not in (Fraction(30000, 1001), Fraction(60000, 1001)):
            raise ConversionError("Drop-frame labels require 29.97 or 59.94 fps.")
        drop = 2 if nominal == 30 else 4
        if m % 10 and s == 0 and f < drop:
            raise ConversionError(f"Invalid dropped frame number: {label}")
        minutes = h * 60 + m
        frames -= drop * (minutes - minutes // 10)
    return frames


def merge_state(target: dict, patch: dict) -> None:
    """ATEM arrays are sparse indexed patches, not complete replacement lists."""
    for key, value in patch.items():
        if isinstance(value, dict):
            merge_state(target.setdefault(key, {}), value)
        elif isinstance(value, list) and all(isinstance(x, dict) and "_index_" in x for x in value):
            items = target.setdefault(key, [])
            for update in value:
                existing = next((x for x in items if x.get("_index_") == update["_index_"]), None)
                if existing is None:
                    items.append(copy.deepcopy(update))
                else:
                    merge_state(existing, update)
        else:
            target[key] = copy.deepcopy(value)


def load_drp(path: Path) -> list[dict]:
    if path.stat().st_size > MAX_DRP_BYTES:
        raise ConversionError("DRP exceeds the 16 MiB input limit.")
    try:
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    except (ValueError, UnicodeError) as exc:
        raise ConversionError("Expected a native ATEM newline-delimited JSON DRP; Resolve-exported archive DRPs are unsupported.") from exc
    if not rows or not all(isinstance(x, dict) for x in rows):
        raise ConversionError("DRP must contain JSON objects.")
    if rows[0].get("version") != 1 or not rows[0].get("sources"):
        raise ConversionError("Unsupported ATEM DRP header/version.")
    if any("version" in x or "sources" in x for x in rows[1:]):
        raise ConversionError("Multiple sessions or source-file changes require separate DRPs; conversion stopped.")
    return rows


def local_media(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ConversionError("Media path escapes the recording folder.")
    if not path.is_file():
        raise ConversionError(f"Missing media: {relative}")
    return path


def probe(path: Path, ffprobe: str) -> dict:
    try:
        run = subprocess.run([ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
                             capture_output=True, text=True, timeout=30, check=True)
        return json.loads(run.stdout)
    except (subprocess.SubprocessError, ValueError) as exc:
        raise ConversionError(f"Could not inspect media: {path.name}") from exc


def stream_duration(stream: dict) -> Fraction:
    if "duration_ts" in stream and "time_base" in stream:
        return Fraction(stream["duration_ts"]) * Fraction(stream["time_base"])
    if "duration" in stream:
        return Fraction(stream["duration"])
    raise ConversionError("Media has no measurable stream duration.")


def wave_start(path: Path, sample_rate: int) -> Fraction:
    """Read Broadcast WAV's 64-bit sample origin, which Final Cut honors on import.

    ffprobe may omit time_reference when ATEM's BEXT description is empty.
    Read only chunk headers and the BEXT time-reference bytes, never PCM data.
    """
    with path.open("rb") as handle:
        head = handle.read(12)
        if len(head) != 12 or head[:4] not in (b"RIFF", b"RF64") or head[8:] != b"WAVE":
            raise ConversionError(f"Expected RIFF/RF64 WAV: {path.name}")
        file_size = path.stat().st_size
        while handle.tell() + 8 <= file_size:
            chunk = handle.read(8)
            tag, size = struct.unpack("<4sI", chunk)
            position = handle.tell()
            if tag == b"data":
                return Fraction(0)
            if position + size > file_size:
                raise ConversionError(f"Truncated WAV metadata: {path.name}")
            if tag == b"bext":
                if size < 346:
                    raise ConversionError(f"Truncated Broadcast WAV time reference: {path.name}")
                handle.seek(position + 338)
                return Fraction(struct.unpack("<Q", handle.read(8))[0], sample_rate)
            handle.seek(position + size + size % 2)
        raise ConversionError(f"WAV has no audio data: {path.name}")


@dataclass
class Media:
    path: Path
    id: str
    start: Fraction
    duration: Fraction
    video: bool
    channels: int = 0
    rate: int = 0
    still: bool = False


@dataclass
class Segment:
    offset: int
    end: int
    source: int | None
    reason: str = ""


def picture_choice(state: dict, sources: dict) -> tuple[int | None, str]:
    blocks = [b for b in state.get("mixEffectBlocks", []) if b.get("onAir", False)]
    if len(blocks) != 1:
        return None, "multiple or inactive mix-effect blocks"
    block = blocks[0]
    if block.get("transitionActive"):
        return None, "ATEM transition"
    if block.get("fadeToBlack", "Inactive") != "Inactive":
        return None, "fade to black"
    if any(k.get("onAir") or k.get("isFlying") for k in block.get("upstreamKeys", [])):
        return None, "upstream key"
    if any(k.get("onAir") or k.get("faderState", "Idle") != "Idle" for k in state.get("downstreamKeys", [])):
        return None, "downstream key"
    source = block.get("source")
    if source not in sources:
        raise ConversionError(f"Unknown program source index: {source}")
    if sources[source].get("type") not in ("Video", "Still"):
        return None, f"ATEM {sources[source].get('type', 'unknown')} source"
    return source, ""


def edit_segments(rows: list[dict], fps: Fraction, total: int) -> list[Segment]:
    sources = {s["_index_"]: s for s in rows[0]["sources"]}
    state = copy.deepcopy(rows[0])
    origin = timecode_frames(rows[0]["masterTimecode"], fps)
    day = timecode_frames("23:59:59" + (";" if ";" in rows[0]["masterTimecode"] else ":") + f"{round(fps)-1:02d}", fps) + 1
    previous, wraps, cursor = origin, 0, 0
    choice = picture_choice(state, sources)
    segments = []
    ended = False
    for patch in rows[1:]:
        if "masterTimecode" not in patch:
            raise ConversionError("Event has no masterTimecode.")
        raw = timecode_frames(patch["masterTimecode"], fps)
        if raw < previous:
            if previous - raw < day // 2:
                raise ConversionError("Events are out of chronological order.")
            wraps += day
        at = raw + wraps - origin
        previous = raw
        if at > total + 1:
            raise ConversionError("DRP events exceed the program recording duration.")
        at = min(at, total)
        if ended:
            raise ConversionError("Events continue after recording end; possible multi-session DRP.")
        if at > cursor:
            segments.append(Segment(cursor, at, *choice))
        merge_state(state, patch)
        cursor = at
        active = any(b.get("onAir") for b in state.get("mixEffectBlocks", []))
        if not active:
            if abs(at - total) > 1:
                raise ConversionError("Recording end and program duration disagree.")
            ended = True
        else:
            choice = picture_choice(state, sources)
    if cursor < total:
        segments.append(Segment(cursor, total, *choice))
    merged = []
    for seg in segments:
        if merged and (merged[-1].source, merged[-1].reason) == (seg.source, seg.reason):
            merged[-1].end = seg.end
        else:
            merged.append(seg)
    return merged


def choose_audio(root: Path, default: str) -> str:
    names = sorted(p.name for p in (root / "Audio Source Files").glob("*.wav") if not p.name.startswith("._"))
    if not names:
        raise ConversionError("No WAV files in Audio Source Files.")
    default_name = next((n for n in names if n == default or Path(n).stem.endswith(" " + default)), names[0])
    script = '''on run argv
set selectedItem to choose from list (items 2 thru -1 of argv) with title "ATEM ISO to FCPXML" with prompt "Choose the continuous WAV soundtrack. All MP4 audio is disabled." default items {item 1 of argv}
if selectedItem is false then return ""
return item 1 of selectedItem
end run'''
    result = subprocess.run(["/usr/bin/osascript", "-e", script, default_name, *names], capture_output=True, text=True, check=True)
    if not result.stdout.strip():
        raise ConversionError("Conversion cancelled.")
    return result.stdout.strip()


def choose_cameras(drp: Path) -> list[int]:
    rows = load_drp(drp)
    sources = {s["_index_"]: s for s in rows[0]["sources"] if s["type"] == "Video"}
    used = {b["source"] for row in rows for b in row.get("mixEffectBlocks", []) if "source" in b and b["source"] in sources}
    labels = {f"Input {i}: {s['name']}": i for i, s in sources.items()}
    if not labels:
        raise ConversionError("No video inputs in this ATEM recording.")
    defaults = [label for label, i in labels.items() if i in used] or [next(iter(labels))]
    script = '''on run argv
set defaultCount to (item 1 of argv) as integer
set defaultItems to items 2 thru (defaultCount + 1) of argv
set allItems to items (defaultCount + 2) thru -1 of argv
set resultItems to choose from list allItems with title "ATEM ISO to FCPXML" with prompt "Choose camera inputs for the multicam clip (Command-click for multiple). Keep inputs used in the live edit." default items defaultItems with multiple selections allowed
if resultItems is false then return ""
set AppleScript's text item delimiters to linefeed
return resultItems as text
end run'''
    result = subprocess.run(["/usr/bin/osascript", "-e", script, str(len(defaults)), *defaults, *labels], capture_output=True, text=True, check=True)
    if not result.stdout.strip():
        raise ConversionError("Conversion cancelled.")
    return [labels[line] for line in result.stdout.strip().splitlines()]


def convert(drp: Path, audio: str = "CAM 1", ffprobe: str = "ffprobe", name: str | None = None,
            cameras: list[int] | None = None, extra_audio: list[str] | None = None) -> tuple[bytes, dict]:
    drp = drp.resolve()
    rows = load_drp(drp)
    header, root = rows[0], drp.parent
    width, height, fps = video_mode(header.get("videoMode", ""))
    origin = Fraction(timecode_frames(header["masterTimecode"], fps), 1) / fps
    program = local_media(root, drp.stem + ".mp4")
    program_info = probe(program, ffprobe)
    pv = next((s for s in program_info["streams"] if s["codec_type"] == "video"), None)
    if not pv:
        raise ConversionError("Program recording has no video.")
    if Fraction(pv["avg_frame_rate"]) != fps or (pv["width"], pv["height"]) != (width, height):
        raise ConversionError("Program video format and DRP videoMode disagree.")
    duration = stream_duration(pv)
    frame_count = duration * fps
    if frame_count.denominator != 1 or frame_count <= 0:
        raise ConversionError("Program duration is not a positive whole number of frames.")
    total = int(frame_count)
    segments = edit_segments(rows, fps, total)
    media: list[Media] = []

    def add(path: Path, start: Fraction, video: bool, still: bool = False) -> Media:
        found = next((m for m in media if m.path == path), None)
        if found:
            return found
        if still:
            item = Media(path, f"r{len(media)+2}", Fraction(0), duration, True, still=True)
        else:
            info = program_info if path == program else probe(path, ffprobe)
            stream = next((s for s in info["streams"] if s["codec_type"] == ("video" if video else "audio")), None)
            if not stream:
                raise ConversionError(f"Missing expected media stream: {path.name}")
            if video:
                if Fraction(stream["avg_frame_rate"]) != fps or (stream["width"], stream["height"]) != (width, height):
                    raise ConversionError(f"ISO format differs from the project: {path.name}")
                tag = stream.get("tags", {}).get("timecode")
                if tag and Fraction(timecode_frames(tag, fps), 1) / fps != start:
                    raise ConversionError(f"ISO timecode disagrees with DRP: {path.name}")
            elif stream.get("codec_name") not in ("pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le"):
                raise ConversionError(f"Expected uncompressed PCM WAV: {path.name}")
            item = Media(path, f"r{len(media)+2}", start, stream_duration(stream), video,
                         int(stream.get("channels", 0)), int(stream.get("sample_rate", 0)))
        if not video:
            item.start = wave_start(path, item.rate)
        media.append(item)
        return item

    by_source, pairs = {}, []
    sources = {s["_index_"]: s for s in header["sources"]}
    used = {s.source for s in segments if s.source is not None}
    if cameras is None:
        cameras = sorted(i for i in used if sources[i]["type"] == "Video")
    cameras = list(dict.fromkeys(cameras))
    if not cameras or any(i not in sources or sources[i]["type"] != "Video" for i in cameras):
        raise ConversionError("Select at least one valid camera input.")
    excluded = used - set(cameras)
    excluded = {i for i in excluded if sources[i]["type"] == "Video"}
    if excluded:
        raise ConversionError("Selected cameras exclude an input used by the live edit: " + ", ".join(map(str, sorted(excluded))))
    for source_id in sorted(used | set(cameras)):
        source = sources[source_id]
        still = source["type"] == "Still"
        start = Fraction(0) if still else Fraction(timecode_frames(source["startTimecode"], fps), 1) / fps
        video = add(local_media(root, source["file"]), start, True, still)
        by_source[source_id] = video
        if not still:
            wav = local_media(root, "Audio Source Files/" + Path(source["file"]).stem + ".wav")
            sound = add(wav, Fraction(0), False)
            if abs(sound.duration - video.duration) > 1 / fps:
                raise ConversionError(f"Camera MP4 and WAV lengths disagree: {wav.name}")
            if source_id in cameras:
                if video.start != origin or video.duration < duration or sound.duration < duration:
                    raise ConversionError("Multicam inputs must cover the complete ATEM session with matching start timecode.")
                pairs.append((source_id, source["name"], video, sound))
    audio_names = [p for p in (root / "Audio Source Files").glob("*.wav") if not p.name.startswith("._")]
    matches = [p for p in audio_names if p.name == audio or p.stem.endswith(" " + audio)]
    if len(matches) != 1:
        raise ConversionError(f"Audio source {audio!r} is missing or ambiguous; pass --audio with the exact WAV filename.")
    soundtrack = add(local_media(root, str(matches[0].relative_to(root))), Fraction(0), False)
    if soundtrack.rate != 48000:
        raise ConversionError("ATEM soundtrack must be 48 kHz PCM WAV.")
    if soundtrack.duration < duration or soundtrack.duration - duration > 1 / fps:
        raise ConversionError("Soundtrack and program lengths disagree; sync cannot be assumed.")
    extras = []
    if extra_audio is None:
        extra_audio = [suffix for suffix in ("MIC 1", "MIC 2") if any(p.stem.endswith(" " + suffix) for p in audio_names)]
    for suffix in extra_audio:
        selected = [p for p in audio_names if p.name == suffix or p.stem.endswith(" " + suffix)]
        if len(selected) != 1:
            raise ConversionError(f"Extra audio {suffix!r} is missing or ambiguous.")
        item = add(local_media(root, str(selected[0].relative_to(root))), Fraction(0), False)
        if item.duration < duration or item.rate != 48000:
            raise ConversionError(f"Extra audio does not cover the 48 kHz session: {item.path.name}")
        if item not in extras and all(item.path != pair[3].path for pair in pairs):
            extras.append(item)
    if all(soundtrack.path != pair[3].path for pair in pairs) and soundtrack not in extras:
        extras.append(soundtrack)
    pgm = add(program, origin, True) if any(s.source is None for s in segments) else None
    for seg in segments:
        item = pgm if seg.source is None else by_source[seg.source]
        source_in = Fraction(0) if item.still else origin + Fraction(seg.offset, 1) / fps - item.start
        if source_in < 0 or (not item.still and source_in + Fraction(seg.end-seg.offset, 1) / fps > item.duration):
            raise ConversionError(f"Media does not cover a scheduled range: {item.path.name}")

    xml = ET.Element("fcpxml", version="1.10")
    resources = ET.SubElement(xml, "resources")
    ET.SubElement(resources, "format", id="r1", frameDuration=seconds(1/fps), width=str(width), height=str(height), colorSpace="1-1-1 (Rec. 709)")
    for m in media:
        attrs = dict(id=m.id, name=m.path.name, start=seconds(m.start), duration=seconds(m.duration))
        if m.video:
            attrs.update(hasVideo="1", format="r1", videoSources="1")
        else:
            attrs.update(format="r1", hasAudio="1", audioSources="1", audioChannels=str(m.channels), audioRate=str(m.rate))
        asset = ET.SubElement(resources, "asset", attrs)
        ET.SubElement(asset, "media-rep", kind="original-media", src=m.path.as_uri())
    camera_media_ids = {}
    for source_id, label, video, sound in pairs:
        resource_id = f"camera{source_id}"
        camera_media_ids[source_id] = resource_id
        camera_media = ET.SubElement(resources, "media", id=resource_id, name=label + " — WAV audio")
        camera_sequence = ET.SubElement(camera_media, "sequence", format="r1", duration=seconds(duration), tcStart="0s", tcFormat="NDF", audioLayout="stereo", audioRate="48k")
        camera_spine = ET.SubElement(camera_sequence, "spine")
        picture = ET.SubElement(camera_spine, "clip", name=label, offset="0s", start=seconds(origin), duration=seconds(duration), format="r1")
        ET.SubElement(picture, "video", ref=video.id, offset=seconds(origin), start=seconds(origin), duration=seconds(duration))
        ET.SubElement(picture, "asset-clip", ref=sound.id, name=sound.path.stem, lane="-1", offset=seconds(origin), start=seconds(sound.start), duration=seconds(duration), format="r1", audioRole="dialogue")
    multicam_id = "multicam1"
    mc_media = ET.SubElement(resources, "media", id=multicam_id, name=(name or root.name) + " — Multicam")
    multicam = ET.SubElement(mc_media, "multicam", format="r1", tcStart="0s", tcFormat="NDF")
    for source_id, label, video, sound in pairs:
        angle = ET.SubElement(multicam, "mc-angle", name=label, angleID=f"cam{source_id}")
        ET.SubElement(angle, "ref-clip", ref=camera_media_ids[source_id], name=label + " — WAV audio", offset="0s", start="0s", duration=seconds(duration))
    for index, sound in enumerate(extras):
        angle = ET.SubElement(multicam, "mc-angle", name=sound.path.stem, angleID=f"audio{index}")
        ET.SubElement(angle, "asset-clip", ref=sound.id, name=sound.path.stem, offset="0s", start=seconds(sound.start), duration=seconds(duration), format="r1", audioRole="dialogue")
    event = ET.SubElement(xml, "event", name=name or root.name)
    for sound in (m for m in media if not m.video):
        ET.SubElement(event, "asset-clip", ref=sound.id, name=sound.path.stem, start=seconds(sound.start), duration=seconds(duration), format="r1", audioRole="dialogue")
    browser_mc = ET.SubElement(event, "mc-clip", ref=multicam_id, name=(name or root.name) + " — Multicam", start="0s", duration=seconds(duration))
    main_angle = next((f"cam{pair[0]}" for pair in pairs if pair[3].path == soundtrack.path), None)
    if main_angle is None:
        main_angle = f"audio{extras.index(soundtrack)}"
    if main_angle == f"cam{cameras[0]}":
        ET.SubElement(browser_mc, "mc-source", angleID=main_angle, srcEnable="all")
    else:
        ET.SubElement(browser_mc, "mc-source", angleID=f"cam{cameras[0]}", srcEnable="video")
        ET.SubElement(browser_mc, "mc-source", angleID=main_angle, srcEnable="audio")
    project = ET.SubElement(event, "project", name=(name or root.name) + " — Live Edit")
    sequence = ET.SubElement(project, "sequence", format="r1", duration=seconds(duration), tcStart=seconds(origin),
                             tcFormat="DF" if ";" in header["masterTimecode"] else "NDF", audioLayout="stereo", audioRate="48k")
    spine = ET.SubElement(sequence, "spine")
    fallbacks = []
    for index, seg in enumerate(segments):
        m = pgm if seg.source is None else by_source[seg.source]
        start = Fraction(0) if m.still else origin + Fraction(seg.offset, 1) / fps
        is_camera = seg.source in cameras
        if is_camera:
            start = Fraction(seg.offset, 1) / fps
            clip = ET.SubElement(spine, "mc-clip", ref=multicam_id, name=sources[seg.source]["name"],
                                 offset=seconds(Fraction(seg.offset, 1)/fps), start=seconds(start),
                                 duration=seconds(Fraction(seg.end-seg.offset, 1)/fps), srcEnable="video")
            ET.SubElement(clip, "mc-source", angleID=f"cam{seg.source}", srcEnable="video")
        else:
            clip = ET.SubElement(spine, "clip", name=("Program • " + seg.reason) if seg.reason else sources[seg.source]["name"],
                                 offset=seconds(Fraction(seg.offset, 1)/fps), start=seconds(start), duration=seconds(Fraction(seg.end-seg.offset, 1)/fps), format="r1")
            ET.SubElement(clip, "video", ref=m.id, offset=seconds(start), start=seconds(start), duration=seconds(Fraction(seg.end-seg.offset, 1)/fps))
        if index == 0:
            ET.SubElement(clip, "asset-clip", ref=soundtrack.id, name=soundtrack.path.stem + " — continuous WAV", lane="-1",
                          offset=seconds(start), start=seconds(soundtrack.start), duration=seconds(duration), format="r1", audioRole="dialogue")
        if seg.reason:
            ET.SubElement(clip, "marker", start=seconds(start), duration=seconds(1/fps), value="Program fallback: " + seg.reason)
            fallbacks.append(dict(start_frame=seg.offset, end_frame=seg.end, reason=seg.reason))
    ET.indent(xml, space="  ")
    payload = b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fcpxml>\n' + ET.tostring(xml, encoding="utf-8") + b"\n"
    report = dict(converter_version=__version__, fps=str(fps), total_frames=total, picture_segments=len(segments),
                  soundtrack=soundtrack.path.name, soundtrack_bwf_start=seconds(soundtrack.start), multicam_camera_inputs=cameras, extra_audio_angles=[m.path.name for m in extras], program_fallbacks=fallbacks,
                  notes=["All MP4 embedded audio is disabled.", "WAV is aligned to ATEM recording start; no waveform sync or hardware-delay correction.",
                         "Program fallback ranges preserve rendered effects, not editable effect parameters."])
    return payload, report


def write_exclusive(path: Path, data: bytes) -> None:
    # Never overwrite an existing file, including a symlink, even after a race.
    with path.open("xb") as handle:
        handle.write(data)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Native ATEM .drp or recording folder")
    parser.add_argument("--audio", default="CAM 1", help="WAV source suffix or exact filename (default: CAM 1)")
    parser.add_argument("--choose-audio", action="store_true", help="Show a macOS soundtrack picker")
    parser.add_argument("-o", "--output", type=Path, help="Output .fcpxml; defaults beside the DRP")
    parser.add_argument("--unique-output", action="store_true", help="Choose a numbered filename when output already exists")
    parser.add_argument("--ffprobe", default="ffprobe", help="Path to ffprobe")
    parser.add_argument("--cameras", help="Comma-separated camera input indexes; defaults to inputs used by the live edit")
    parser.add_argument("--extra-audio", action="append", help="Extra WAV suffix/filename as an audio angle; repeatable (default: available MIC 1 and MIC 2)")
    parser.add_argument("--no-extra-audio", action="store_true", help="Omit optional MIC audio angles")
    parser.add_argument("--name", help="Final Cut event and project name")
    parser.add_argument("--version", action="version", version=__version__)
    args = parser.parse_args(argv)
    try:
        drp = args.input.expanduser().resolve()
        if drp.is_dir():
            files = [p for p in drp.glob("*.drp") if not p.name.startswith("._")]
            if len(files) != 1:
                raise ConversionError("Select one .drp; the folder must contain exactly one.")
            drp = files[0]
        if drp.suffix.lower() != ".drp" or not drp.is_file():
            raise ConversionError("Select an existing ATEM .drp or recording folder.")
        output = args.output.expanduser().absolute() if args.output else drp.with_suffix(".fcpxml")
        if output.suffix.lower() != ".fcpxml":
            raise ConversionError("Output must use the .fcpxml extension.")
        if args.unique_output:
            requested = output
            count = 2
            while output.exists() or output.is_symlink() or output.with_suffix(".conversion.json").exists() or output.with_suffix(".conversion.json").is_symlink():
                output = requested.with_name(f"{requested.stem} ({count}).fcpxml")
                count += 1
        report_path = output.with_suffix(".conversion.json")
        if output.exists() or output.is_symlink() or report_path.exists() or report_path.is_symlink():
            raise ConversionError("Output or report already exists; choose a new output name.")
        ffprobe = shutil.which(args.ffprobe)
        if not ffprobe:
            raise ConversionError("ffprobe is required. On macOS: brew install ffmpeg")
        cameras = None
        if args.cameras:
            try:
                cameras = [int(x) for x in args.cameras.split(",")]
            except ValueError as exc:
                raise ConversionError("--cameras expects input numbers, for example 1,2") from exc
        if args.choose_audio and not args.cameras:
            cameras = choose_cameras(drp)
        audio = choose_audio(drp.parent, args.audio) if args.choose_audio else args.audio
        payload, report = convert(drp, audio, ffprobe, args.name, cameras, [] if args.no_extra_audio else args.extra_audio)
        # Validate and finish all conversion work before creating any output.
        ET.fromstring(payload)
        write_exclusive(report_path, (json.dumps(report, indent=2) + "\n").encode())
        try:
            write_exclusive(output, payload)
        except OSError:
            report_path.unlink()
            raise
        print(f"Created {output}\n{report['picture_segments']} picture segments; soundtrack: {report['soundtrack']}")
        print(f"Program fallback ranges: {len(report['program_fallbacks'])}; details: {report_path}")
        return 0
    except (ValueError, OSError, KeyError, TypeError, ZeroDivisionError, subprocess.SubprocessError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
