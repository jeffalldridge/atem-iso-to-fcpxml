# Validation

What has been checked, on what, and what has not. Unit tests, engine parity, XML well-formedness, DTD validation, native UI interaction, Final Cut import, signing, notarization, and Gatekeeper acceptance are different kinds of evidence; none substitutes for another. Dates are absolute. Earlier, finer-grained development notes are in the Git history of this file.

## Current Status

**Verified**

- Real ATEM Mini Pro ISO recordings at 1080p60, with and without mix transitions, convert, import into Final Cut Pro 12.4 without warnings, and round-trip with identical offsets, durations, and angle assignments (1.0.0 entry below).
- Final Cut's automatic audio crossfade is gain-neutral when both sides of a dissolve use the same audio angle (1.0.0).
- The Swift engine writes byte-identical XML to the Python reference on those recordings and on the synthetic parity scenarios (1.1.0, and every `swift test` run).
- The published 1.1.1 disk image opened on a Mac without a Gatekeeper warning (1.1.1).
- The app behaves as described in [app.md](app.md) in the cases listed under 1.1.1: opening, converting, existing-file confirmation, cancelling, error alerts, and closing the window during reads and conversions.

**Not yet verified**

- Other ATEM models (Extreme ISO, SDI ISO, Television Studio HD8 ISO) and other frame rates, especially 59.94 and 29.97 drop-frame, with real media. Synthetic coverage only.
- Keys, fade to black, and non-mix transitions on real recordings. The fallback to the program recording is exercised synthetically and has not been imported into Final Cut.
- A multi-session `.drp` from a real stop-and-start recording. How later sessions name their media is inferred from the log, which is why the app does not offer a session chooser.
- Lip sync by ear over a full-length recording. Alignment is by timecode and Broadcast Wave time reference, which matched exactly on the real recordings; no waveform analysis is done.
- Final Cut Pro versions older than 12.4.
- VoiceOver, Full Keyboard Access, light appearance, Reduce Motion and Reduce Transparency, drag and drop from Finder, a real slow or exFAT drive, read-only and full destinations, macOS 15, and Intel hardware.
- Replacing a running installation with a newer copy, and the Quick Action's lookup with several installed copies.

## 2026-10-21: Version 1.1.1

- **Tests:** 30 Swift tests and 78 Python, website, and release-tool tests pass. They cover supported media ranges (both engines), `Rational` intermediates beyond 64 bits, the MP4 scan stopping at `moov` (both engines), written audio matching the window's choices across four subset, soundtrack, and extras cases, the multi-session explanation, the destination note, and that only a conversion defers Quit. `build_quick_action.py --check`, `actionlint` on all workflows, `check_release.py`, `zsh -n` on the generated Quick Action script, and `git diff --check` pass.
- **Parity and DTD:** the XML the converter writes did not change. The Swift parity scenarios still match the Python script byte for byte, and the XML validates against the installed Final Cut Pro's FCPXML 1.10 DTD. No new Final Cut import was done.
- **Header fuzz:** `scripts/fuzz_media_headers.py` mutates MP4 and WAV header bytes of a synthetic recording and runs both engines with `--dry-run`. After the change: about 2,800 iterations over five seeds, no Swift signal exits, no disagreement about acceptance, no differing summaries. Against the earlier code, 600 iterations found six disagreements (a corrupt box after `moov` that only Swift walked) and no trap, so the overflow fix rests on explicit extreme-value tests. This is evidence about header bytes of synthetic files, not a proof, and it does not cover the `.drp`.
- **The app, driven through accessibility and Finder Open With:** the empty window; opening a `.drp` and a folder; Create and the existing-file confirmation (Cancel and Replace); Open Recent; cancelling the file picker with a saved result in place; a Resolve-archive lookalike and a two-session log each producing a titled alert while the saved result stayed; an eight-camera recording with long names and six extra WAVs scrolling correctly. Closing during a slow load quit at once; closing during a slow conversion published the complete file and then quit; closing during a failing conversion returned the window with the error. The slow cases used a recording padded with millions of empty MP4 boxes, not a slow drive.
- **Website:** rendered at desktop and 375 pixels wide with no horizontal overflow; static tests pass. Screenshots were captured from this build; their corners are transparent (corner alpha 0, centre alpha 255).
- **Release:** the Release workflow run for `v1.1.1` passed end to end on a hosted runner: version and tag-on-`main` checks, tests, Developer ID signing, notarization of the app and disk image, `spctl` and `stapler` checks on the mounted image, and a draft release created by the separate publish job. The maintainer then opened the downloaded disk image without a Gatekeeper warning. This does not cover a second machine or account.

## 2026-10-21: Version 1.1.0, the Mac app

- The Swift engine (`Sources/ATEMConverter`) writes byte-identical XML to `atem_iso_to_fcpxml.py` on the real recordings (compared with `cmp`) and on the five synthetic parity scenarios in `tests/ATEMConverterTests`: plain cuts; dissolves, a still, a downstream key, fade to black, and a color generator; wipes with explicit cameras, soundtrack, extras, name, no event, and the program angle in all three transition modes; a missing program recording and a missing WAV; drop-frame 59.94 across midnight with a custom input label.
- The universal (arm64 and x86_64) bundle passes `codesign --verify --deep --strict` and launches to its empty state. Opening a synthetic recording populated the choices with the expected cameras, soundtrack, and 32 clips and 31 dissolves.
- A Final Cut import of XML written by the app was not repeated: it is byte-identical to the Python output that was round-tripped for 1.0.0.

## 2026-10-21: Version 1.0.0, Final Cut Pro 12.4 on macOS 27.0

Real ATEM Mini Pro ISO recordings at 1080p60, two cameras used of four, two mic inputs, one Media Player still:

| Recording | Length | Switcher events | Result |
| --- | --- | --- | --- |
| A | 95 min 24 s | 85 cuts, no transitions, opened on a still | 86 clips, converts in under a second |
| B | 46 min 38 s | 31 mix transitions (0.5 s to 3.7 s), still at start and end | 32 clips, 31 dissolves |

Checks on recording B:

1. Both outputs validate against Apple's FCPXML 1.10 DTD (and 1.14) with `xmllint`.
2. Import into a scratch library produced no warnings. The event lists the multicam, the project, and all six source files.
3. The project opened in the timeline with the dissolves in place; the viewer at the first dissolve shows the camera blended with the still.
4. Export XML from Final Cut and compare: all 63 spine items (32 clips, 31 transitions) have identical offsets, starts, durations, and angle assignments. The multicam kept its compound angles, still angle, mic angles, and time-of-day `tcStart`.
5. Audio through a dissolve: two seconds around the first dissolve were exported from Final Cut and compared sample-aligned with the original camera WAV in 20 ms windows. Gain was −0.12 to +0.01 dB across the whole range including the dissolve, so Final Cut's automatic audio crossfade is gain-neutral when both sides use the same audio angle.
6. The pure-Python MP4 and WAV readers return the same frame counts, timecode, sample counts, and Broadcast Wave time references as `ffprobe` on all 8 MP4s and 12 WAVs of the recordings.
7. The Quick Action's embedded script runs the converter under Apple's Command Line Tools Python 3.9.6 (`--dry-run`).

## 2026-10-21: Version 0.1.0

The first alpha established that Final Cut rejects WAV clips whose XML `start` ignores the Broadcast Wave time reference, and that declaring an MP4 asset as video-only does not stop Final Cut from re-adding its AAC audio; explicit `video` components do.

## Superseded Development Builds

Before 1.1.0 the app went through several internal builds, including a bundled-Python preview built with PyInstaller and a macOS 13 JSON-bridge preview. Those packaging paths were abandoned for the pure-Swift app and do not describe the shipping product. What they established and still applies: Quick Action cancellation returns success to Automator (an empty Run Shell Script error otherwise); camera and extra-audio choices use native checkboxes, and extra audio starts unchecked; a failed open preserves an already saved result; the conditional rules for which WAVs are offered as extra angles were checked exhaustively over 128 camera-subset and soundtrack combinations.
