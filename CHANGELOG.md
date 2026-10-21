# Changelog

## Unreleased

- Both engines reject media outside explicit supported ranges instead of risking overflow; Swift arithmetic is overflow-safe, and the Swift MP4 reader stops at the index like the Python one.
- The window says where the `.fcpxml` will be saved (and when it already exists). Failures have specific titles, failed conversions say the recording was not changed, and a recording with several sessions is explained instead of quoting command-line flags. Closing the window while only reading quits at once; only a conversion defers Quit. The File menu regains Close (⌘W) and gains Show in Finder and Open in Final Cut Pro. The empty window has one Choose Recording button.
- The Quick Action survives a failed hand-off, finds a renamed or moved app by bundle identifier, and carries its converter version.
- Website: direct installer link, plain-language fixes, and new transparent screenshots of the current window. Contributor, assistant, and issue and pull request guidance rewritten.

- Defer quitting until the current operation finishes; cancel quitting and restore the window on failure. Prevent overlapping Open sheets and preserve completed results when choices are unchanged.

- Reject malformed Swift CLI arguments, out-of-range media values, and invalid XML text without writing output; match Python's zero-delta timing fallback and no-extra-audio option precedence.
- Allow opening/converting when an unused microphone WAV is damaged; validate it only when selected.
- Stage Quick Action upgrades with rollback; require complete release credentials and consistent version declarations.
- Bound recording-note scrolling, refresh Open Recent state, and correct obsolete agent-facing documentation.

- Resizable native workspace with visible soundtrack and transition choices, system appearance, and restrained timeline colors.
- Extra audio is opt-in in both the app and Quick Action fallback; hidden audio selections are cleared when camera or soundtrack choices change.
- Native Open sheets, Return/⌘S conversion, preserved saved results after a failed open, and an explicit Download Updates menu link.
- Single-recording Quick Action handoff prevents silently ignoring extra selected files.
- Website screenshot alpha edges are preserved; GitHub, free availability, and manual update instructions are prominent.

## 1.1.0 (2026-10-21)

- A native Mac app: one universal Swift binary (macOS 15+), signed and notarized, distributed as a disk image. Drop the recording folder, check cameras and soundtrack, create the XML, open it in Final Cut Pro. No Python or developer tools needed. The window is laid out like Compressor (live switch on top, Cameras, Audio, and Options columns, the action in a bottom bar), uses Liquid Glass on macOS 26 and standard controls on macOS 15, and has an Icon Composer icon.
- The Swift engine is a port of the Python converter and is tested to write byte-identical XML on synthetic scenarios and on real recordings; the Python script remains the reference and the command-line tool.
- The Finder Quick Action hands off to the app when the app is installed and otherwise shows native checkbox dialogs; the 1.0.0 dialog error (-1728) is fixed.
- When the program recording is missing, the first selected camera stands in for keyed and faded sections with a marker instead of a silent gap.
- Hardened parsing: bounded media reads, version-aware MP4 headers, RF64 and trailing-BEXT WAVs, validated log containers, safer output writes, drop-frame midnight.
- American English spelling and Chicago style throughout the documentation, website, and messages.

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
