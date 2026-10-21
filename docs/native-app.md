# Native Mac App

The local SwiftUI preview replaces the sequence of AppleScript/AppKit dialogs with one window. It requires macOS 13+ and Python 3.9+. The build uses Apple Command Line Tools and produces the current Mac's architecture.

```sh
python3 scripts/build_macos_app.py --install
```

The app is installed into the user's Applications folder. The builder regenerates and installs the Finder Quick Action, which opens the app when present. Without the app, the workflow retains its embedded Python interface. The standalone CLI remains independent.

## Responsibilities

- `macos/ATEMApp.swift`: native file picker, camera checkboxes, soundtrack radio buttons, optional audio, progress, errors, replacement confirmation, and completion actions.
- `macos/bridge.py`: JSON on standard input/output; inspection uses the engine's defaults and conversion calls its existing CLI entry point. No shell interpolation of filenames, duplicate XML writer, or new media parser.
- `scripts/build_macos_app.py`: compile, bundle the Python files, generate the icon, ad-hoc sign, and optionally install.
- `macos/MakeIcon.swift`: vector icon matching the project's favicon palette and shapes.

Audio inclusion is defined in `macos/AudioSelection.swift`: the soundtrack takes priority, selected-camera WAVs are already included with their camera, and only other sources may be extra audio-only angles. Included sources remain visible with a reason. Changing cameras or soundtrack clears extras that are no longer optional; changing back does not silently reselect them. `AudioSelectionTests.swift` checks all 128 combinations of three cameras and four soundtrack sources.

The app uses a compact 520-point-wide window, with a shorter opening/completion state and a scrollable selection state.

The app runs the engine off the main thread. It drains process output before waiting so long warning reports cannot fill a pipe and freeze conversion. It prevents closing or replacing the active recording during a write. Cancel before conversion produces no file; stopping a write midway is deliberately not offered. Canceling a replacement sheet preserves the current selections and existing file.

One recording is accepted at a time. Multi-session logs currently show the engine's error and require the CLI's `--session` option. Conversion does not modify the recording. The existing engine protects media paths and handles exclusive creation and replacement.

## Distribution

This is an ad-hoc-signed local build, not a notarized public release. Python is not bundled. Before public distribution: validate the supported macOS/Python combinations, build both Mac architectures, sign and notarize, and exercise the downloaded artifact on a clean account. Do not claim those steps are complete based on local compilation.

The previous installed app is backed up under ignored `local/app-backups/` when rebuilding. Quit the app before installing a replacement. No recording, generated XML, or local UI screenshot should be committed.
