# Validation

What has actually been checked, on what, and what has not. Dates are absolute.

## 2026-10-21 — version 1.0.0, Final Cut Pro 12.4 on macOS 27.0

Two real ATEM Mini Pro ISO recordings, both 1080p60, two cameras used of four, two mic inputs, one Media Player still:

| Recording | Length | Switcher events | Result |
| --- | --- | --- | --- |
| A | 95 min 24 s | 85 cuts, no transitions, opened on a still | 86 clips, converts in under a second |
| B | 46 min 38 s | 31 mix transitions (0.5 s to 3.7 s), still at start and end | 32 clips, 31 dissolves |

Checks performed on recording B:

1. Both outputs validate against Apple's FCPXML 1.10 DTD (and 1.14) with `xmllint`.
2. Import into a scratch library produced no warnings. The event lists the multicam, the project and all six source files.
3. The project opened in the timeline with the dissolves in place; the viewer at the first dissolve shows the camera blended with the still.
4. Export XML from Final Cut and compare: all 63 spine items (32 clips, 31 transitions) have identical offsets, starts, durations and angle assignments. The multicam kept its compound angles, still angle, mic angles and time-of-day `tcStart`.
5. Audio through a dissolve: two seconds around the first dissolve were exported from Final Cut and compared sample-aligned with the original camera WAV in 20 ms windows. Gain was −0.12 to +0.01 dB across the whole range including the dissolve, so Final Cut's automatic audio crossfade is gain-neutral when both sides use the same audio angle.
6. The pure-Python MP4 and WAV readers return the same frame counts, timecode, sample counts and Broadcast Wave time references as `ffprobe` on all 8 MP4s and 12 WAVs of the two recordings.
7. The Quick Action's embedded script runs the converter under Apple's Command Line Tools Python 3.9.6 (`--dry-run`); the Finder dialogs were exercised manually in 0.1.0 but not re-run by automation for 1.0.0.

Synthetic tests (`python3 -m unittest discover -s tests`): 37 tests covering timecode (NDF and drop-frame round trips), video modes, sparse state merging, multi-session logs, MP4/WAV/PNG parsing, every edit-list branch (cuts, centred dissolves, odd lengths, same-source transitions, keys, fade to black, generators, deselected inputs, missing stills, missing program recording, midnight wrap, clamping), plan defaults, XML structure, drop-frame output, URL escaping, DTD validation, and the command line.

## Not yet verified

- Other ATEM models (Extreme ISO, SDI ISO, Television Studio HD8 ISO) and other frame rates, especially 59.94/29.97 drop-frame recordings, with real media. Synthetic coverage only.
- Keys, fade to black and non-mix transitions on real recordings (the fallback to the program recording is exercised synthetically).
- A multi-session `.drp` from a real stop/start recording; the ISO file naming for later sessions is inferred from the log.
- Lip sync by ear over a full service. The alignment is by timecode and Broadcast Wave time reference, which match exactly on the two recordings; no waveform analysis is done.
- Final Cut Pro versions older than 12.4.

## 2026-10-21 — version 0.1.0

Earlier the same day the first alpha established that Final Cut rejects WAV clips whose XML `start` ignores the Broadcast Wave time reference, and that declaring an MP4 asset as video-only does not stop Final Cut from re-adding its AAC audio; explicit `video` components do.
