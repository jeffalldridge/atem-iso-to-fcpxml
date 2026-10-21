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

One resizable window. System appearance, accent color, toolbar, radio buttons, checkboxes, and segmented controls provide the chrome; media colors appear only in the timeline strip.

- **Empty window**: one **Choose Recording…** button (Return) and drag-and-drop. There is no action bar until a recording is open.
- **Recording**: name, format, duration, and a strip of the actual edit decisions (cut for cut, dissolves marked) with the soundtrack beneath. The strip is drawn from the same edit list the converter uses; it is not decoded video and not a waveform.
- **Camera angles**: inputs used live start checked. Each camera uses its paired WAV when there is one, and says so.
- **Soundtrack**: visible radio choices select the audio that plays across every cut.
- **Extra audio angles**: start unchecked. A WAV already paired with a selected camera, or chosen as the soundtrack, is not offered again, and a hidden choice is cleared so it cannot come back checked.
- **Transitions**: dissolves, cuts, or program video, with the program recording as an optional angle.
- **Action bar**: what will be made, and where (`<name>.fcpxml` next to the recording, noting an existing file that will need confirmation). **Create FCPXML** (Return or ⌘S) becomes **Details…**, **Show in Finder**, and **Open in Final Cut Pro** when it finishes. Changing a choice after a conversion makes the window ready to convert again; the saved file stays where it is, and replacing it asks first.

The camera, soundtrack, and extra-audio lists scroll independently, so eight cameras or many WAVs stay usable. The File menu has Open Recording… (⌘O), Open Recent, Close (⌘W), Create FCPXML (⌘S), Show in Finder (⌘R), and Open in Final Cut Pro.

Every failure names what failed in its title and says what to do; failed conversions also say the recording was not changed. A failed open leaves an already saved result alone. The Open sheet, drops, Finder Open With, and the Quick Action accept one recording at a time. Recordings with several sessions are not opened (see below).

## Closing during work

Only a conversion defers Quit, because it is the one operation that publishes a file. The conversion finishes before AppKit receives its reply, so quitting cannot interrupt output publication; success completes the quit, failure cancels it and brings the main window back with the error. Reading a recording is abandoned at once when the window closes or the app quits, since nothing has been written. While either operation runs, the app holds a Process Info activity so macOS neither suspends it nor automatically terminates it after its window closes.

Verified by driving the real app: closing the window during a slow load quits immediately; closing during a slow conversion publishes the complete file and then quits; closing during a conversion that fails brings the window back with the error and leaves the app usable. The slow cases used a synthetic recording padded with millions of empty MP4 boxes, not a real slow external drive.

## Recordings with several sessions

If the ATEM appended a second recording to the same `.drp`, the app refuses to open it and explains that the command line version can choose a session with `--session`. A native chooser is deliberately not offered yet: how later sessions name their media is inferred from the log, not verified on a real stop-and-start recording, and choosing a session silently, or showing a chooser whose media association was never confirmed, risks converting the wrong take. Add one only with a real multi-session recording to test against.

## Updates and the Quick Action

**Latest Release on GitHub…** in the app menu opens the releases page. Updates are manual and the app makes no network requests: quit the app, drag the new copy into the same Applications folder, and choose Replace. The bundle name and identifier stay stable. There is no background updater, no check, and no download.

The Quick Action hands the selected recording to the installed app: first `/Applications`, then `~/Applications`, then any copy LaunchServices finds by bundle identifier (a renamed or moved app, or one running from a disk image). If the hand-off fails, or no app is found, it runs its embedded Python converter with native dialogs. Keep one installed copy to avoid ambiguity. Replacing the app updates the Quick Action's native experience too. The embedded converter does not update itself; install the newer workflow over the old one. Finder's Get Info on the workflow shows which converter version it carries. Its extra audio choices also start unchecked, and its dialogs do not expose every option the app has; the options they share are held to byte-identical output by the parity tests.

## Building

```bash
make app                       # ad-hoc signed, for local use
DEV_ID="Developer ID Application: Tent Studios, LLC (TEAMID)" make app   # signed with the hardened runtime
make release                   # see docs/releasing.md
```

The app's version lives in `Resources/Info.plist`, `Sources/ATEMConverter/FCPXML.swift`, `atem_iso_to_fcpxml.py`, and `pyproject.toml`; the release workflow refuses a tag that does not match all of them.
