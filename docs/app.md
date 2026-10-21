# The Mac App

`ATEM ISO to FCPXML.app` is a SwiftUI application with no runtime dependencies: one universal Mach-O executable, an icon, and an Info.plist. It is built with Swift Package Manager; there is no Xcode project.

```
Package.swift
Sources/ATEMConverter/      The engine: a port of atem_iso_to_fcpxml.py (Rational, Timecode, DRP, Media, Recording, EditList, Plan, FCPXML, Converter)
Sources/ATEMISOtoFCPXML/    The app: ATEMApp (scene, menus, document opening), ConversionModel (state), ContentView (empty, choices, converting, done)
Sources/atem-convert/       A command-line front end with the Python script's options, used to compare outputs
tests/ATEMConverterTests/   XCTest: synthetic fixtures, unit tests, and parity tests that run the Python reference and compare bytes
Resources/                  Info.plist, entitlements
scripts/make-app.sh         Assembles the bundle (universal check, icon, signing, self-check)
scripts/make-icon.swift     Renders AppIcon.icns from the same artwork as the website favicon
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

The window has four states, each with a fixed size so the window follows the content:

1. **Empty**: a content-unavailable view that accepts a dropped folder or `.drp`, with a Choose Recording button. ⌘O and the Dock accept recordings too; the app registers the `.drp` document type.
2. **Choices**: a grouped form. Recording facts; camera checkboxes with "Used live" and "MP4 audio" hints; a soundtrack radio group; extra audio checkboxes for WAVs that are not already included; options for ATEM transitions and the program angle; any notes from the engine. The default selections are what the engine would choose on its own.
3. **Converting**: a progress indicator.
4. **Done**: Open in Final Cut Pro (default), Show in Finder, a Details disclosure with the engine's summary, Back, and Convert Another.

Errors are alerts with the engine's message. Replacing an existing `.fcpxml` asks first.

## Building

```bash
make app                       # ad-hoc signed, for local use
DEV_ID="Developer ID Application: Tent Studios, LLC (TEAMID)" make app   # signed with the hardened runtime
make release                   # see docs/releasing.md
```

The app's version lives in `Resources/Info.plist`, `Sources/ATEMConverter/FCPXML.swift`, `atem_iso_to_fcpxml.py`, and `pyproject.toml`; the release workflow refuses a tag that does not match all of them.
