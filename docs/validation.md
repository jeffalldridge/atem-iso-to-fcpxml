# Validation

What has been checked, on what, and what has not. Unit tests, engine parity, XML well-formedness, DTD validation, native UI interaction, Final Cut import, signing, notarization, and Gatekeeper acceptance are different kinds of evidence; none substitutes for another. Dates are absolute. Earlier, finer-grained development notes are in the Git history of this file.

## Current Status

**Verified**

- Camera/WAV compounds are visible browser items linked to the multicam angles; all angle kinds have populated Angle Editor timelines and the correct recording duration (unreleased visibility round trip below).
- The recorded-live-mix choice preserves both synthetic audio sources through a native Final Cut render (unreleased live-mix entry below).
- Real ATEM Mini Pro ISO recordings at 1080p60, with and without mix transitions, convert, import into Final Cut Pro 12.4 without warnings, and round-trip with identical offsets, durations, and angle assignments (1.0.0 entry below).
- Final Cut's automatic audio crossfade is gain-neutral when both sides of a dissolve use the same audio angle (1.0.0).
- The Swift engine writes byte-identical XML to the Python reference on those recordings and on the synthetic parity scenarios (1.1.0, and every `swift test` run).
- The published 1.1.1 disk image opened on a Mac without a Gatekeeper warning (1.1.1).
- The app behaves as described in [app.md](app.md) in the cases listed under 1.1.1: opening, converting, existing-file confirmation, cancelling, error alerts, and closing the window during reads and conversions.

**Not yet verified**

- Other ATEM models (Extreme ISO, SDI ISO, Television Studio HD8 ISO) and other frame rates, especially 59.94 and 29.97 drop-frame, with real media. Synthetic coverage only.
- Keys, fade to black, and non-mix transitions on real recordings. Native synthetic tests cover Program stand-in sections; they do not establish behavior across those operations on real hardware recordings.
- A multi-session `.drp` from a real stop-and-start recording. How later sessions name their media is inferred from the log, which is why the app does not offer a session chooser.
- Lip sync by ear over a full-length recording. Alignment is by timecode and Broadcast Wave time reference, which matched exactly on the real recordings; no waveform analysis is done.
- Final Cut Pro versions older than 12.4.
- VoiceOver, Full Keyboard Access, light appearance, Reduce Motion and Reduce Transparency, drag and drop from Finder, a real slow or exFAT drive, read-only and full destinations, macOS 15, and Intel hardware.
- Replacing a running installation with a newer copy, and the Quick Action's lookup with several installed copies.

## 2026-10-21: Version 1.2.0 Release Candidate

Release preparation updates all version declarations and the generated Quick Action to 1.2.0. The candidate passes 37 Swift tests, 89 Python converter/site/release-tool tests, version consistency, Quick Action freshness, and diff checks. The universal app rebuild passes ad-hoc signature verification and engine self-check. Native launch confirms version 1.2.0 in About; opening a real ATEM recording shows its 86 edits, the unchanged Camera 1 WAV default, and the live-mix choice. No output was written during that read-only inspection. The XML behavior and native Final Cut evidence below are unchanged by the version update. Signing, notarization, and installer acceptance for 1.2.0 remain pending the release workflow.

## 2026-10-21: Unreleased, Recorded Live Mix

- **Decision:** preserve the isolated WAV default and add **ATEM live mix** to the existing soundtrack choices in the app, Python dialogs, and both command-line tools (`--live-mix`). The mix uses Program audio, falling back to an audio-bearing selected ISO. It preserves the recorded result of AFV and mixer changes; it does not reconstruct their automation. Program picture remains independent. A recording without WAVs selects live mix automatically. Silent MP4s cannot be selected as a usable soundtrack.
- **Native import, Final Cut Pro 12.4:** imported a 20-second synthetic recording with three camera angles, a still compound, Program picture, and a separate live-mix angle, without an import warning. The project opens with seven clips and one dissolve. Exported the event back to XML: exact rational clip and transition offsets, starts, durations, and audio/video assignments are unchanged; one project, one browser multicam, and all six angles remain. Program picture and live mix reference the same MP4 asset. Final Cut normalizes away the mix angle asset-clip's `srcEnable="audio"`; the project's audio-only `mc-source` assignments remain intact.
- **Rendered audio:** exported that project from Final Cut as H.264/AAC. The synthetic Program recording contains 440 Hz and 880 Hz tones together, while the default camera WAV contains only 440 Hz. Both tones remain present in a three-second rendered segment spanning the picture dissolve, with their amplitude ratio preserved. This verifies both sources survive the recorded-mix workflow, not mixer automation reconstruction or lossless audio gain.
- **Native app:** rebuilt the universal app, opened that synthetic folder, confirmed Camera 1 WAV remains selected by default, selected ATEM live mix, created XML, and checked that it contains the dedicated mix angle. The action bar displays the recording-note count after saving. Workflow tests also cover camera availability changes, a temporary empty camera selection, no-WAV defaults, reconversion, and independent Program picture selection.
- **Checks:** 37 Swift tests, including engine parity and 12 app workflow tests; 89 Python converter, website, and release-tool tests; Quick Action regeneration and freshness; installed Apple FCPXML 1.10 DTD validation; workflow `actionlint`; release version consistency; and `git diff --check`. The universal app builds and passes ad-hoc signature verification and engine self-check. No new Developer ID signing, notarization, Gatekeeper acceptance, hardware capture, or release was performed. ISO fallback has unit/parity coverage; it has not had a separate native playback test.

## 2026-10-21: Unreleased, Media Player Visibility and Import Inventory

- **Omission corrected:** the preceding visibility change exposed camera compounds but left the Media Player still out of the browser. The writer now creates a shared “Media Player 1 - Still” compound plus an original-image browser clip. Camera compounds use plain ASCII separators, such as “Camera 1 - ISO + WAV.” Established project and multicam naming is unchanged. Source names and user labels are preserved.
- **Native import and inventory, Final Cut Pro 12.4:** the 20-second synthetic six-angle recording imported without warnings into a fresh event. The event lists exactly 13 items: one Live Edit project, one multicam, three compounds (two camera/WAV, one still), four MP4s, three WAVs, and one PNG. Opening the Media Player compound exposes the image. Disabling that inner image changes the opening still section of Live Edit to black; the still was reenabled afterward. The raw PNG is separately visible in the browser.
- **Round trip:** exported the synthetic event after the temporary still edit. It retains one project, one browser multicam, three browser compounds linked to their corresponding angle resources, and six angles. The still compound's disabled inner clip and the original browser image reference the same image asset. All seven project clips and the dissolve retain exact rational offsets, starts, durations, and audio/video angle assignments. Final Cut normalizes the original image browser item and assigns its own image source timecode; the shared asset reference is preserved. This verifies shared-content editing, not a relink or replacement-media operation.
- **Two-project investigation:** read-only export of an existing event showed an earlier import with the legacy em-dash name alongside a current import. Both cover the same recording duration. The earlier project starts at recording timecode, puts its opening still directly in the project, and uses a zero-origin multicam with extra mic angles. The current project starts at zero and puts the still in its time-of-day multicam. The extra project was retained from the earlier import, not emitted a second time by the current writer. Existing projects were not removed or altered. A new regression asserts exactly one event, one project, one browser multicam, and one multicam resource per conversion.
- **Checks:** 30 Swift tests including byte parity, 83 Python/site/release-tool tests, XML well-formedness, installed FCPXML 1.10 DTD validation, regenerated Quick Action freshness, and `git diff --check` pass. Tests verify every selected asset has exactly one browser representation, and that the original still and shared compound use the same resource. A universal local app build passed ad-hoc signature verification and engine self-check. No release signing, notarization, Gatekeeper, new real-media playback, or hardware test was performed.

## 2026-10-21: Unreleased, Visible Camera Compounds and Angle Timelines

Final Cut Pro 12.4, using playable synthetic 1080p60 color/tone media, 20 seconds long, with MP4 timecode and WAV Broadcast Wave references at 10:00:00:00. Tests used the existing scratch validation library; no user library contents were edited.

- **Reproduction:** the previous angle offsets (`offset=tcStart`) produced a 10:00:20:00 multicam duration for 20 seconds of material, with blank angle rows at the recording's displayed timecode. Project playback and XML preservation had passed earlier checks, so those checks did not establish Angle Editor usability. Setting angle offsets to `0s`, retaining multicam `tcStart`, source timestamps, and project `mc-clip` starts, produces the correct 20-second duration and visible angle clips. This supersedes the original angle-offset layout and its interpretation.
- **Browser compounds and shared editing:** the event explicitly lists “Camera 1 — ISO + WAV” and “Camera 2 — ISO + WAV.” Double-clicking a browser compound opens its video and connected WAV. Temporarily disabling the inner Camera 1 clip changed both Camera 1 sections in Live Edit. The event exports before and after the edit contain one shared compound resource per camera, referenced by both the browser and multicam; the edited resource retained its UID and gained `enabled="0"`. The edit was undone afterward. This verifies a shared content edit; it was not a relink or replacement-media experiment.
- **All angle kinds:** the final converter output imported without warnings. Its six angles contain two camera/WAV compounds, a camera with no WAV using a native MP4 `asset-clip`, a Media Player still, video-only Program, and audio-only MIC 1. Each angle has a visible 20-second clip at the multicam origin. The earlier missing-WAV `clip/audio` layout triggered the unsupported anchored-item warning; the native asset clip removes it and survives export with audio enabled.
- **Timeline and round trip:** played the synthetic Live Edit across its cuts and dissolve, and inspected the dissolve midpoint (red and blue blend to purple). Exported the event as FCPXML 1.14. Exact rational comparison confirms all seven `mc-clip`s and the transition keep their offsets, source starts, durations, and video/audio angle selections. All six angle IDs, names, element kinds, zero-relative offsets, and durations survive export. Browser compounds and angles retain the same resource references. Final Cut adds its normal audio crossfade and color-conform data. No new audio gain measurement or real-recording listening test was performed.
- **Name collisions:** a distinct event name imported separately, even with the same camera compound names and source files in other events. Reimporting identical event and clip names invoked Final Cut's **Keep Both / Replace** dialog. Keep Both preserved the existing items and added numbered compound, multicam, and project copies in that event; it did not create another event. No replacement was authorized or tested. The writer continues to omit FCP-owned UIDs and cannot preflight a user's library. Matching names therefore remain an explicit native import choice, not a promise of a new event on every import.
- **Automated checks:** 30 Swift tests, including Python/Swift byte parity, and 81 Python, website, and release-tool tests pass. Regression coverage checks shared browser/angle resource references, nonzero source clocks with zero-relative angle offsets, missing-WAV native clips, and compounds with no event wrapper. XML well-formedness and the installed FCPXML 1.10 DTD validation pass. The regenerated Quick Action passes `build_quick_action.py --check`; `git diff --check` passes.
- **Local app build:** `make app DEV_ID=` produced a universal arm64/x86_64 app, passed ad-hoc signature verification and the engine self-check. No new Developer ID signing, notarization, Gatekeeper acceptance, release, or installation was performed.

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
