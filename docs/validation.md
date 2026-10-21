# Validation

What has actually been checked, on what, and what has not. Dates are absolute.

Current architecture: SwiftUI app and Swift engine, with the Python file as the reference. Entries about PyInstaller, a bundled Python interpreter, the macOS 13 preview, and its JSON bridge are historical experiments, not descriptions of the shipping app. For current packaging and release requirements use [app.md](app.md) and [releasing.md](releasing.md).

## 2026-10-21: Fresh review (local, unreleased)

What was run, and what each result does and does not establish.

- **Unit and regression tests:** 30 Swift tests and 78 Python, site, and release-tool tests pass. New: supported media ranges (both engines), `Rational` intermediates beyond 64 bits, MP4 scan stopping at `moov` (both engines), written audio matching the window's choices across four subset/soundtrack/extras cases, the multi-session explanation, the destination note, and that only a conversion defers Quit. `python3 scripts/build_quick_action.py --check`, `actionlint` on all three workflows, `scripts/check_release.py v1.1.0`, `zsh -n` on the generated Quick Action script, and `git diff --check` pass.
- **Engine parity:** the Swift parity scenarios still produce the same bytes as the Python script. The XML the converter writes was not changed, so the earlier real-recording comparisons and the Final Cut round trip in this file still describe it. No new Final Cut import was done.
- **DTD validation:** the installed Final Cut Pro's FCPXML 1.10 DTD test passes on this Mac.
- **Differential header fuzz:** `scripts/fuzz_media_headers.py` mutated MP4 and WAV header bytes of a synthetic recording and ran both engines with `--dry-run`. After the change: about 2,800 iterations over five seeds, no Swift signal exits, no disagreement about acceptance, no differing summaries. Against the code before the change, 600 iterations found six disagreements (a corrupt box after `moov` that only Swift walked) and no trap; the overflow fix rests on the explicit extreme-value tests. This is evidence about header bytes of synthetic files, not a proof, and it does not cover the `.drp`.
- **Real app, driven through accessibility and Finder Open With (a copy with its own bundle identifier, not the installed app):** empty state; opening a `.drp` and a folder; Create and the existing-file confirmation (Cancel and Replace); Open Recent contents; cancelling the file picker keeping a saved result; a Resolve-archive lookalike and a two-session log each giving a titled alert while the saved result stayed; an eight-camera, long-name, six-extra-WAV recording scrolling correctly. Close during a slow load quit at once. Close during a slow conversion published the complete file and then quit. Close during a conversion that failed returned the window with the error and a usable app. Slow cases used a recording padded with millions of empty MP4 boxes, not a real slow drive.
- **Website:** rendered in the built-in browser at desktop and 375 pixels wide with no horizontal overflow; static tests pass. The live site and the release's `releases/latest/download` redirect were checked by an independent review pass (HTTP status only; nothing was downloaded).
- **Screenshots:** captured from this build with `screencapture -l`, 1800 × 1308 RGBA, transparent corners confirmed by reading the pixels (corner alpha 0, centre alpha 255, only the rounded corners non-opaque).
- **Not run:** VoiceOver, Full Keyboard Access, light appearance, Reduce Motion and Transparency, drag and drop from Finder, Open in Final Cut Pro, a clean-download Gatekeeper launch, notarization, replacing a running installation, a real slow or exFAT disk, read-only and full destinations, macOS 15, Intel hardware, and any real recording. The v1.1.0 release workflow run skipped signing and publishing; its assets were attached separately, so the published disk image's signature is unverified here.

## 2026-10-21: Second audit pass (local, unreleased)

- 24 Swift tests and 73 Python/site/release-tool tests pass; generated Quick Action consistency and whitespace checks pass.
- Added tests for unchanged choice assignments preserving a saved result, success/failure completion notifications, and deferred termination with failure canceling the quit request.
- Open commands and drops are disabled while the native picker is presented, preventing duplicate sheets.
- The termination policy now waits for the active operation, allows quit on success, and requests the main window on failure. The policy is unit-tested; actual AppKit Close/Quit under slow I/O and SwiftUI window restoration have not been exercised in this pass.
- Built the universal app for review. No installed app replacement, release, deployment, or push was performed. Manual update and duplicate-installation limitations remain unchanged.


## 2026-10-21: Repository audit (local, unreleased)

- 22 Swift tests pass, including engine parity, malformed metadata/XML rejection, CLI subprocess argument handling, safe forced output, and the unused-damaged-microphone workflow.
- 73 Python/site/release-tool tests pass. Quick Action installation tests cover failed copying, failed publication with rollback, and replacement without obsolete files.
- Quick Action consistency, `actionlint` across all three workflows, release-version validation, and `git diff --check` pass.
- `make app` produces a universal arm64/x86_64 ad-hoc-signed bundle that passes signature verification and its self-check. The newly built bundle was not installed over the copy currently under owner review.
- No push, deployment, signed release, signing-secret change, new browser matrix, accessibility acceptance, exFAT hardware test, or Final Cut import was performed. Changes to the Swift XML writer add a well-formedness check without changing output shapes or valid parity bytes.
- Findings, withdrawn suspicion, and outstanding priorities are recorded in [the audit](audit-2026-10-21.md).


## 2026-10-21: Native UX review (unreleased)

- `swift test`: 14 tests passed, including byte-for-byte Python/Swift engine parity and two new application workflow tests. Audio selection reconciliation, opt-in extras, saved-result preservation after a failed open, and replacement confirmation are covered.
- `python3 -m unittest discover -s tests -v`: 71 tests passed, including fallback dialog defaults and website contracts.
- `python3 scripts/build_quick_action.py --check`: generated workflow matches source.
- `make app`: universal arm64/x86_64 bundle builds, passes signature verification and its self-check. This local test build is ad-hoc signed; it is not a new notarized release.
- Exercised the installed app with a synthetic Live Show folder: native Open sheet, Cancel back to the workspace, visible camera/soundtrack/extra controls, MIC 1 soundtrack with no extras, and successful output. Dark appearance was visually inspected. Full VoiceOver, light appearance, macOS 15, and Intel hardware acceptance remain unverified.
- Website checked in the local browser: GitHub link, corrected WAV fallback copy, and PNGs without CSS borders, shadows, or rounded clipping. Gallery images still depict released 1.1.0; new alpha-preserving captures are needed for the next release. The available automated native capture produced flattened JPEG, so it was not substituted for the existing transparent PNGs.
- The FCPXML engine shapes were not changed; this is not a new Final Cut import round trip.


## 2026-10-21: Self-Contained Mac Packaging

- Built the app with Python 3.13 and PyInstaller, signed it with Developer ID, and verified the nested signatures and hardened runtime. Installed this build locally and converted the synthetic demo through the actual UI, including the existing-file confirmation. The Finder Quick Action menu showed its replacement prompt and then confirmed successful installation.
- The bundled engine passed the inspection/conversion/replacement and invalid-input tests with an empty `PATH` and an unusable external `PYTHONHOME`. The engine is executed directly from the app; users of this build do not need Python installed.
- GitHub Actions run `39659903107` built and packaged both Apple silicon (`macos-15`) and Intel (`macos-15-intel`) previews. Both native jobs passed the audio matrix, bundled engine checks, and disk image creation. That run's Linux jobs exposed an older cancellation test that did not select the macOS path; the test now explicitly mocks that platform branch.
- The local 74-test Python suite, Quick Action consistency, workflow lint, and whitespace checks pass. Follow-up GitHub run `39660399175` passed all six jobs, including both architecture builds and both Python versions on macOS/Linux. App packaging includes Python/PyInstaller licenses; downloaded production builds are created on CI rather than this workstation.
- The release workflow requires signing secrets, notarizes and staples the app and DMG, and creates a draft only after both architectures succeed. Those notarization/publication steps have not been run. The three signing secrets were subsequently configured in the GitHub `release` environment with explicit user approval; the temporary private-key export was removed. Notarization credentials remain unconfigured. A local Developer ID signature does not establish notarization, Gatekeeper download acceptance, clean-account installation, minimum macOS support, or a new Final Cut round trip.

## 2026-10-21: UI and Accessibility Review

Three independent source reviews covered the native workflow, website, and accessibility. Applied fixes preserve selections/results on failed inspection, keep errors above the footer, add Return on the opening screen, expose section headings and audio inclusion reasons to accessibility, and identify camera MP4-audio fallback. Window height is capped to the current screen's usable area.

- Built and installed the updated app locally. In the actual app, Return opened the native recording picker; cancel returned normally. Opened the synthetic recording, selected MIC 1, then opened an invalid file. The recording and MIC 1 selection remained, with the error visibly above the action buttons. Accessibility inspection exposed the new headings and explicit inclusion descriptions.
- Website review removed the duplicated workflow section, made all four screenshots render at the same width, and supplied complete clone/change-directory/build commands. The README no longer recommends the known-broken release ZIP. Browser checks at 1280 and 320 pixels showed no horizontal document overflow; all four images loaded at equal widths within each layout. Narrow-screen build instructions remained readable and selectable.
- 71 Python tests, 128 Swift audio combinations, native compilation, generated-workflow consistency, and whitespace checks passed.
- These changes do not alter the conversion engine or XML structures. No new Final Cut round trip, VoiceOver speech/navigation acceptance, physical short-display test, or clean-account installation was performed. Long diagnostic scrolling remains to be exercised.

Remaining review follow-ups before public native distribution: verify interpreter availability/version instead of selecting the first executable Python path, test missing developer tools on a clean account, and exercise VoiceOver and window placement across displays. The preview is still an ad-hoc-signed source build.

## 2026-10-21: Conditional Audio and Website Captures

- The pure Swift inclusion rules pass 128 camera-subset/soundtrack combinations. The native UI was also exercised: select CAM 3 as extra, make CAM 3 the soundtrack, switch to MIC 1, and confirm CAM 3 returns unchecked. CAM 1 and CAM 2 remain labeled as included with their selected cameras. MIC 2 can be added separately.
- Installed the compact 520-point-wide app locally. Captured four actual app screens with a synthetic Sunday Service recording for the website; no real recording or personal path appears in the public images.
- 71 Python tests pass. Screenshot/icon presence and basic image metadata are checked alongside the existing schema, link, and FAQ checks. The Swift selection matrix now runs in Mac CI.

## 2026-10-21: Local SwiftUI App Preview

- Built and ad-hoc signed the native arm64 app on this Mac, then installed it in the user's Applications folder. The installed Finder workflow's exact shell step opens that app and exits successfully.
- Walked through the actual native UI with a synthetic recording: used-camera defaults, unchecking all cameras disables conversion, MIC 1 radio selection removes it from optional audio, optional MIC 2 selection, successful XML creation, replacement confirmation, and successful explicit replacement.
- Canceling replacement returns to the unchanged selection screen. Canceling the native file picker preserves the completed result. Cancel on the selection screen terminates the app without an error; app inventory confirms it is no longer running.
- Inspected the generated XML for camera and audio selections. The JSON bridge tests cover read-only inspection, no-camera rejection, invalid recordings, source preservation, refusing existing output, and explicit replacement.
- 70 Python tests pass, including installed Apple DTD validation. Quick Action consistency and Swift compilation pass. No new XML shapes were introduced.
- No new Final Cut import, physical-device compatibility survey, VoiceOver pass, Intel execution, notarization, or clean-account installation was performed. The UI preview is not a published release.

## 2026-10-21: Checkbox Dialogs and Cancellation

- Camera and optional audio selection now use AppKit checkboxes through macOS JavaScript for Automation. Optional audio also has a No extra audio button; the main soundtrack is not offered again as optional audio.
- Cancellation returns success to Automator, preventing its empty Run Shell Script error. A regression verifies cancellation does not call the output writer or show an error alert.
- 68 synthetic tests pass, including checkbox result mapping for empty, multiple, and unusual filenames, cancellation, and Apple DTD validation. The regenerated Quick Action passes its consistency check and was installed locally.
- The native dialog process reached its modal wait in a smoke test, but the UI automation tool could not attach to the osascript process. Checkbox interaction, keyboard navigation, scrolling, and Finder integration remain to be checked manually; mocked return values do not verify those interactions.

## 2026-10-21: Version 1.1.0, the Mac app

- The Swift engine (`Sources/ATEMConverter`) writes byte-identical XML to `atem_iso_to_fcpxml.py` on both real recordings (compared with `cmp`) and on the five synthetic parity scenarios in `tests/ATEMConverterTests` (plain cuts; dissolves, a still, a downstream key, fade to black, and a color generator; wipes with explicit cameras, soundtrack, extras, name, no event, and the program angle in all three transition modes; a missing program recording and a missing WAV; drop-frame 59.94 across midnight with a custom input label). 12 Swift tests pass.
- The app bundle assembled by `make app` is universal (arm64 and x86_64), 2 MB, passes `codesign --verify --deep --strict`, and launches to its empty state. Opening a synthetic recording folder through the system open route populated the choices form with the expected cameras, soundtrack, and 32 clips / 31 dissolves.
- Not re-verified in this pass: a Final Cut import of XML written by the app (it is byte-identical to the Python output that was round-tripped for 1.0.0, so the earlier evidence applies), Gatekeeper on a clean Mac, and Intel hardware.

## 2026-10-21: Review Fixes

- 61 synthetic tests pass under Apple's Python 3.9.6, including validation against the installed Apple FCPXML 1.10 DTD. Added regressions cover output links and failed replacement, exFAT-compatible creation without hard links, media containment, drop-frame midnight at 29.97 and 59.94, custom labels and audio ID collisions, dialog selection mapping, malformed headers, and invalid options.
- The second review pass adds regressions for sparse updates inside a dissolve, dip approximation markers, BWF metadata after audio, a sparse RF64 file over 4 GiB, truncated WAV rejection, bounded MP4 reads, malformed log containers, CLI subprocess behavior, input-file preservation, and deterministic release ZIPs. Source files with an unusual `.fcpxml` extension are also protected from output replacement.
- Rebuilt the Quick Action from the converter; `python3 scripts/build_quick_action.py --check` passes. Its generated zsh script passes `zsh -n`.
- Both list-dialog AppleScript variants compile with `osacompile`. Dialog return handling is unit-tested with mocked responses; Finder interaction was not exercised in this review.
- `git diff --check` passes. No real recordings or generated XML were added to Git.
- Existing compound, still, multicam, and transition XML shapes were retained. This review did **not** perform another Final Cut import/export or audible sync check; earlier round-trip evidence below remains scoped to those earlier outputs.
- Physical exFAT media was not tested. The regression confirms that fresh output creation does not require hard-link support. Forced replacement uses a transient same-directory file, removed on success or handled failure; no report or other sidecar is retained. Abrupt process or power loss can leave a partial new file or temporary replacement file.

Remaining behavior limits: mismatched source starts are reported but not automatically corrected; short media can end before the project. When the program video is missing, the first selected camera now stands in for those intervals with a marker, so the soundtrack continues (DTD-checked and unit-tested; not yet round-tripped in Final Cut). Media Player assets changed during a recording are not fully reconstructed from later source patches. These need focused synthetic fixtures and a new Final Cut round trip before broader support is claimed.

## 2026-10-21: Version 1.0.0, Final Cut Pro 12.4 on macOS 27.0

Two real ATEM Mini Pro ISO recordings, both 1080p60, two cameras used of four, two mic inputs, one Media Player still:

| Recording | Length | Switcher events | Result |
| --- | --- | --- | --- |
| A | 95 min 24 s | 85 cuts, no transitions, opened on a still | 86 clips, converts in under a second |
| B | 46 min 38 s | 31 mix transitions (0.5 s to 3.7 s), still at start and end | 32 clips, 31 dissolves |

Checks performed on recording B:

1. Both outputs validate against Apple's FCPXML 1.10 DTD (and 1.14) with `xmllint`.
2. Import into a scratch library produced no warnings. The event lists the multicam, the project, and all six source files.
3. The project opened in the timeline with the dissolves in place; the viewer at the first dissolve shows the camera blended with the still.
4. Export XML from Final Cut and compare: all 63 spine items (32 clips, 31 transitions) have identical offsets, starts, durations, and angle assignments. The multicam kept its compound angles, still angle, mic angles, and time-of-day `tcStart`.
5. Audio through a dissolve: two seconds around the first dissolve were exported from Final Cut and compared sample-aligned with the original camera WAV in 20 ms windows. Gain was −0.12 to +0.01 dB across the whole range including the dissolve, so Final Cut's automatic audio crossfade is gain-neutral when both sides use the same audio angle.
6. The pure-Python MP4 and WAV readers return the same frame counts, timecode, sample counts, and Broadcast Wave time references as `ffprobe` on all 8 MP4s and 12 WAVs of the two recordings.
7. The Quick Action's embedded script runs the converter under Apple's Command Line Tools Python 3.9.6 (`--dry-run`); the Finder dialogs were exercised manually in 0.1.0 but not re-run by automation for 1.0.0.

Synthetic tests (`python3 -m unittest discover -s tests`): 37 tests covering timecode (NDF and drop-frame round trips), video modes, sparse state merging, multi-session logs, MP4/WAV/PNG parsing, every edit-list branch (cuts, centered dissolves, odd lengths, same-source transitions, keys, fade to black, generators, deselected inputs, missing stills, missing program recording, midnight wrap, clamping), plan defaults, XML structure, drop-frame output, URL escaping, DTD validation, and the command line.

## Not Yet Verified

- Other ATEM models (Extreme ISO, SDI ISO, Television Studio HD8 ISO) and other frame rates, especially 59.94/29.97 drop-frame recordings, with real media. Synthetic coverage only.
- Keys, fade to black, and non-mix transitions on real recordings (the fallback to the program recording is exercised synthetically).
- A multi-session `.drp` from a real stop/start recording; the ISO file naming for later sessions is inferred from the log.
- Lip sync by ear over a full-length recording. The alignment is by timecode and Broadcast Wave time reference, which match exactly on the two recordings; no waveform analysis is done.
- Final Cut Pro versions older than 12.4.

## 2026-10-21: Version 0.1.0

Earlier the same day the first alpha established that Final Cut rejects WAV clips whose XML `start` ignores the Broadcast Wave time reference, and that declaring an MP4 asset as video-only does not stop Final Cut from re-adding its AAC audio; explicit `video` components do.
