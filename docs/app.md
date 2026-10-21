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

One resizable window. System appearance, accent, toolbar, radio buttons, checkboxes, and segmented controls provide the native chrome; media colors are confined to the timeline.

- **Recording**: name, format, duration, live-switch cuts, and a continuous soundtrack lane. The strip represents edit decisions, not decoded video or an audio waveform.
- **Camera angles**: inputs used live start checked. Each camera uses its paired WAV when available.
- **Soundtrack**: visible radio choices select the audio that plays across cuts. Extra audio angles start unchecked. WAVs already paired with a camera or used as the soundtrack are excluded, and stale hidden selections are cleared.
- **Transitions**: visible choices for dissolves, cuts, and program video; optional program angle beneath.
- **Action bar**: Create FCPXML (Return or ⌘S), then Details, Show in Finder, and Open in Final Cut Pro. Changing a choice requires a fresh conversion and confirms replacement of an existing file.

The window grows in both dimensions; camera, soundtrack, and extra-audio panes scroll independently. ⌘O opens a native file sheet, and Cancel leaves the current recording alone. A failed open preserves an already saved result. Drop, Finder Open With, and the Quick Action accept one recording at a time instead of silently discarding additional selections.

## Updates and the Quick Action

**Download Updates…** in the app menu opens the latest GitHub release. Updates are manual: quit the app, drag the new copy into the same Applications folder, and choose Replace. The bundle name and identifier remain stable. There is no background updater or automatic download.

The Quick Action opens the installed app from `/Applications`, then `~/Applications`. Keep one installed copy to avoid ambiguity. Replacing that app updates the Quick Action's native experience too. Without the app, the Quick Action uses its embedded Python converter and native dialogs; its extra audio choices also start unchecked. Install the latest workflow over the existing workflow to update that fallback. Conversion options shared by both engines are verified by byte-for-byte parity tests; the fallback dialogs do not expose every app option.

## Building

```bash
make app                       # ad-hoc signed, for local use
DEV_ID="Developer ID Application: Tent Studios, LLC (TEAMID)" make app   # signed with the hardened runtime
make release                   # see docs/releasing.md
```

The app's version lives in `Resources/Info.plist`, `Sources/ATEMConverter/FCPXML.swift`, `atem_iso_to_fcpxml.py`, and `pyproject.toml`; the release workflow refuses a tag that does not match all of them.
