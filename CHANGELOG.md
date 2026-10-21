# Changelog

## 1.0.0 — 2026-10-21

A rewrite of the 0.1.0 alpha.

- Camera angles are compound clips pairing the ISO MP4 picture with the matching WAV; the MP4's AAC is never used.
- The live-switch timeline is a normal multicam edit: every clip takes its sound from one audio angle, so trimming the head or tail of the project no longer risks losing a connected soundtrack.
- ATEM mix transitions become editable Cross Dissolves centred on the switch point, verified audio-transparent in Final Cut Pro 12.4.
- Media Player stills and the program recording (for keys and fades) are angles, so the timeline stays one multicam clip.
- No ffprobe: MP4 and WAV headers, embedded timecode and Broadcast Wave time references are read in pure Python.
- A self-contained Quick Action bundle that installs by double-click, built from the converter by `scripts/build_quick_action.py`.
- Extra audio angles are discovered generically (any WAV without a camera), not by hard-coded names.
- `--transitions`, `--event`, `--no-event`, `--session`, `--program-angle`, `--dry-run` and `--force` options; no sidecar report file.
- Multi-session logs, missing WAVs, missing stills and a missing program recording degrade with warnings instead of stopping.

## 0.1.0 — 2026-10-21

First alpha: compound-clip multicam, video-only timeline with a connected continuous WAV, ffprobe-based inspection.
