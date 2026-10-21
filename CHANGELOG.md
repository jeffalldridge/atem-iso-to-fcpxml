# Changelog

## 1.1.1 (2026-10-21)

### Changed

- The window states where the `.fcpxml` will be saved, and says up front when a file by that name already exists.
- Failures have specific titles and say what to do. A failed conversion says the recording was not changed. A recording whose `.drp` holds several sessions is explained in plain terms, and a missing recording suggests checking the drive.
- Closing the window while only reading a recording quits at once; only a conversion defers Quit, and it finishes first. While reading or writing, macOS no longer suspends or automatically terminates the app.
- The File menu has Close (⌘W), Show in Finder, and Open in Final Cut Pro. The empty window has one **Choose Recording…** button. Timeline labels are drawn only when the whole name fits.
- Extra audio starts unchecked in the app and in the Quick Action fallback. Hidden audio selections are cleared when camera or soundtrack choices change, and unchanged choices keep a completed result.
- Opening a recording ignores an unused damaged microphone WAV; it is checked only when selected.
- The menu item for updates is **Latest Release on GitHub…**; updates remain manual.
- The Quick Action tries both Applications folders, then the app's bundle identifier, before its embedded converter, and carries its converter version. Upgrades are staged with rollback, and a selection of more than one recording is refused.
- Release automation builds and signs in one job, creates a draft release in a separate job, and accepts tags on `main` only.
- Website: a direct installer link, new screenshots of the current window, and clearer copy. Contribution and security guidance rewritten.

### Fixed

- Corrupt media with extreme timescales, frame counts, sample rates, or time references could overflow the Swift engine. Both engines now reject media outside the same supported ranges, and Swift's rational arithmetic is overflow-safe.
- The Swift MP4 reader walked every top-level box instead of stopping at the index, taking about 33 seconds on a file with 12 million trailing boxes.
- Malformed Swift command-line arguments, out-of-range media values, and invalid XML text are rejected without writing output. Zero-delta timing and the order of `--no-extra-audio` now match the Python script.
- Open Recent refreshes when cleared, and long recording notes scroll instead of enlarging the window.

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
