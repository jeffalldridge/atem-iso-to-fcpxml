# The Mac App

`ATEM ISO to FCPXML.app` is a SwiftUI application with no runtime dependencies: one universal Mach-O executable, an icon, and an Info.plist. It is built with Swift Package Manager; there is no Xcode project.

```
Package.swift
Sources/ATEMConverter/      The engine: a port of atem_iso_to_fcpxml.py (Rational, Timecode, DRP, Media, Recording, EditList, Plan, FCPXML, Converter)
Sources/ATEMISOtoFCPXML/    The app: ATEMApp (scene, menus), ConversionModel (state), ContentView, RecordingHeader, ChoiceColumns, ActionBar, Theme
Sources/atem-convert/       A command-line front end with the Python script's options, used to compare outputs
tests/ATEMConverterTests/   XCTest: synthetic fixtures, unit tests, and parity tests that run the Python reference and compare bytes
Resources/                  Info.plist, entitlements
scripts/make-app.sh         Assembles the bundle (universal check, icon, signing, self-check)
Resources/AppIcon.icon      The Icon Composer source (icon.json plus SVG layers); make-app.sh compiles it with actool into Assets.car and AppIcon.icns
scripts/render-icon.swift   Renders the installed app's icon as macOS draws it into the website PNGs (make site-icons)
Makefile                    build, test, app, dmg, notarize, release, clean
```

## The one rule

The Python script is the specification. The Swift engine must produce exactly the same bytes for the same recording and options. `swift test` runs five parity scenarios against `atem_iso_to_fcpxml.py` (skipped when `python3` is not available), and on a Mac with real recordings you can compare them yourself:

```bash
swift build --product atem-convert
.build/debug/atem-convert "/Volumes/ATEM SSD/Live Show" -o /tmp/swift.fcpxml --force
python3 atem_iso_to_fcpxml.py "/Volumes/ATEM SSD/Live Show" -o /tmp/python.fcpxml --force
cmp /tmp/swift.fcpxml /tmp/python.fcpxml
```

Change behavior in the Python script first, with a test, then mirror it in Swift and let the parity tests prove it.

## User interface

One window, laid out like Compressor: the recording and its live switch across the top, the choices in three columns under it, and the action in a bar along the bottom. Every band has a fixed height and the columns scroll inside themselves, so the window resizes sideways only and never shows empty space. The chrome is the system's dark appearance; the app shares only its accent and angle colors with the website.

- **Header**: the recording's name, format, and duration; a video lane colored by angle with a tick at each dissolve; the soundtrack lane; a ruler line with the start and end timecodes, a legend, and the clip and dissolve counts.
- **Cameras**: a checkbox per ISO input with its lane color. Inputs the switcher never cut to are marked "Not in the switch" and start unchecked.
- **Audio**: the soundtrack WAV (a popup) and checkboxes for the other WAVs, which become audio-only angles.
- **Options**: transitions (dissolves, cuts, or the program video), the program recording as an angle, where the file saves, and any notes from the engine.
- **Action bar**: one line saying what the choices make, and Create FCPXML (⌘S). While converting it shows progress; afterward it shows the saved file with Details, Show in Finder, and Open in Final Cut Pro. Changing any choice after a conversion brings Create FCPXML back.

Before a recording is open the same frame shows a drop target and a Choose Recording button. ⌘O, Open Recent, the Dock, and double-clicking a `.drp` open recordings too. Errors are alerts with the engine's message, and replacing an existing `.fcpxml` asks first.

On macOS 26 the buttons and bars are Liquid Glass; on macOS 15 they are the standard bordered controls. `Theme.swift` holds the colors, the measurements, and the two helpers (`prominentButton()` and `glassButton()`) that pick the style at run time.

## Building

```bash
make app                       # ad-hoc signed, for local use
DEV_ID="Developer ID Application: Tent Studios, LLC (TEAMID)" make app   # signed with the hardened runtime
make release                   # see docs/releasing.md
```

The app's version lives in `Resources/Info.plist`, `Sources/ATEMConverter/FCPXML.swift`, `atem_iso_to_fcpxml.py`, and `pyproject.toml`; the release workflow refuses a tag that does not match all of them.
