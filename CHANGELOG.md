# Changelog

## 1.0.1 (2026-10-21)

- When the program recording is missing, the first selected camera stands in for keyed and faded sections with a marker instead of a silent gap.
- American English spelling and Chicago style throughout the documentation, website, and messages.
- Preserve dissolves across unrelated sparse log updates; label dip-to-dissolve conversions as approximations.
- Read Broadcast Wave metadata after the audio chunk, validate RF64 sizes, and reject truncated audio instead of silently shortening it.
- Bound metadata reads, validate known log containers, and report XML-incompatible labels without a traceback.
- Generate reproducible Quick Action ZIPs with an explicit file allowlist; release the standalone Python file and verify checksums before upload.

- Protect output writes against symbolic links, hard links, concurrent creation, and failed replacement; retain exFAT-compatible exclusive creation.
- Correct 29.97/59.94 drop-frame midnight wrap and reject drop-frame labels at integer rates.
- Allow no extra audio in Finder dialogs, preserve multiline choices, reject empty camera lists and session zero, and discover uppercase DRP extensions.
- Enforce recording-folder containment for WAVs and program video; keep custom audio angle IDs unique.
- Warn about source-start mismatches and short media, reject mixed video formats, and handle malformed media headers more clearly.
- Add a vendor reference for maintainers and assistants; correct audio, import, and sync claims in public docs.

## 1.0.0 (2026-10-21)

A rewrite of the 0.1.0 alpha.

- Camera angles are compound clips pairing the ISO MP4 picture with the matching WAV; the MP4's AAC is never used.
- The live-switch timeline is a normal multicam edit: every clip takes its sound from one audio angle, so trimming the head or tail of the project no longer risks losing a connected soundtrack.
- ATEM mix transitions become editable Cross Dissolves centered on the switch point, verified audio-transparent in Final Cut Pro 12.4.
- Media Player stills and the program recording (for keys and fades) are angles, so the timeline stays one multicam clip.
- No ffprobe: MP4 and WAV headers, embedded timecode, and Broadcast Wave time references are read in pure Python.
- A self-contained Quick Action bundle that installs by double-click, built from the converter by `scripts/build_quick_action.py`.
- Extra audio angles are discovered generically (any WAV without a camera), not by hard-coded names.
- `--transitions`, `--event`, `--no-event`, `--session`, `--program-angle`, `--dry-run`, and `--force` options; no sidecar report file.
- Multi-session logs, missing WAVs, missing stills, and a missing program recording degrade with warnings instead of stopping.

## 0.1.0 (2026-10-21)

First alpha: compound-clip multicam, video-only timeline with a connected continuous WAV, ffprobe-based inspection.
