# Validation and remaining acceptance

October 21, 2026 — alpha 0.1.0.

## Verified locally

- 22 synthetic unit tests pass on Python 3.9. They cover integer/fractional timing, drop-frame rules, midnight, event order, sparse nested state, exact transition ranges, BWF origins on every audio reference, camera selection, PCM pairing, missing/short media, renamed folders, path/symlink containment, unsupported input archives/sessions, and overwrite refusal.
- Package installation into an isolated virtual environment exposes the command and version successfully. Runtime Python package dependencies: none.
- Two private 1080p60 ATEM recordings convert: a 95:24 recording with 86 picture segments and no program fallback; a 46:38 recording with 63 picture segments, including 31 rendered program transition intervals.
- Generated FCPXML passes Apple's locally installed 1.10 DTD.
- Both sample recording workflows have imported into Final Cut Pro 12.4 on macOS 27.0.1 without warnings after preserving BWF timestamps. The final explicit-video compound structure was imported and re-exported for the 46:38 sample.
- Native angle-editor inspection showed exactly Camera 1 and Computer compounds, plus MIC 1 and MIC 2 audio-only angles, at the full recording duration.
- Re-export of the final 46:38 event confirmed all MP4 references occur only as explicit video components. Both camera compounds retain their matching WAV. The live project retains its continuous WAV and original full duration.
- The Quick Action installer produces valid property lists and shell syntax, installs the service, and Automator dispatch reaches the camera picker with the two used inputs selected. Completing both chooser dialogs through Finder has not been verified by automation.

Private XML exports, library files, and diagnostic evidence are under ignored local/. They are not public fixtures.

## Issues found and corrected

Early XML variants crashed Final Cut or imported with rejected WAV references. Native re-export exposed the WAVs' nonzero Broadcast Wave source time. Reading the BEXT sample reference and using it throughout corrected nested audio import. A subsequent native round trip also showed that merely declaring MP4 assets as video-only did not reliably exclude AAC; explicit video components in camera compounds fixed that. Regression tests cover BWF origins and explicit video/WAV compound structure.

Temporary import attempts have been consolidated in the separate validation library. Original recording files were not modified by conversion.

## Still requires user/community acceptance

- Listen and watch in Final Cut: confirm lip sync, levels, camera changes, stills, and transition boundaries at the start, middle, and end. There has not been a full-duration perceptual or podcast export acceptance pass.
- Complete the installed Finder Quick Action's two dialogs and import its generated file on a normal user run. macOS service visibility and automation permissions can vary.
- Test other hardware, firmware, frame rates, drop-frame recordings, and midnight sessions with actual recordings. These currently have broader synthetic coverage than real-media coverage.
- Native editable transitions, segmented recordings, multiple sessions, external camera relinking, waveform/LTC sync, and a signed standalone installer are future work.

Do not equate a schema pass or successful import with full editorial acceptance. Publish this as alpha source, not a notarized production release.
