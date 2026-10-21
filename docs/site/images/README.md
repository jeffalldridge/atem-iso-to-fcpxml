# Website Images

The four screenshot PNGs contain real alpha channels. They show the local SwiftUI app on October 21, 2026 using a synthetic “Sunday Service” fixture with generated media headers and no real footage.

1. `01-open.png`: choose a recording.
2. `02-cameras.png`: camera defaults and available audio.
3. `03-audio.png`: MIC 1 soundtrack, MIC 2 optional; selected-camera WAVs remain visibly included.
4. `04-ready.png`: completed demo XML.

The capture provider flattened the original windows to JPEG. `scripts/prepare_screenshot.py` converted them to RGBA PNG and masked only the outside corner matte; it did not redraw or resize the interface. The original lossy encoding cannot be recovered by conversion. Source JPEGs stay under ignored `local/`; the public site contains no JPEG copies or SVG screenshot wrappers. Prefer lossless captures with native transparency for future replacements. Do not add CSS rounding or a second card around the windows.

The PNG icons were extracted from the installed application resources and resized to 128 pixels with `sips`:

- `final-cut.png`: Final Cut Pro, `AppIcon.icns`.
- `fcpxml.png`: Final Cut Pro, `XML.icns`.
- `resolve.png`: DaVinci Resolve, `Resolve.icns`.
- `drp.png`: DaVinci Resolve, `ResolveProject.icns` (the registered DRP document artwork).

Final Cut Pro and its artwork belong to Apple; DaVinci Resolve and its artwork belong to Blackmagic Design. These vendor images identify applications and file types and are not covered by this project's MIT license. Their inclusion does not indicate affiliation or endorsement. The ATEM-native log and Resolve-exported project share an extension but have different contents; the converter only reads the ATEM-native log.

Capture updated screens from the actual app when behavior changes. Keep the matching screenshot captions, image dimensions, and preview installation instructions current.
