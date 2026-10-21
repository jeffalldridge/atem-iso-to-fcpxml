# Website Images

The four JPEGs are direct window captures of the local SwiftUI app on October 21, 2026. They use a synthetic “Sunday Service” fixture at `/tmp/ATEM Demo/`, with generated media headers and no real footage. No personal names, recording paths, edits to the captured interface, or simulated Final Cut timeline are present. The site identifies the app as a source-build preview.

1. `01-open.jpg`: choose a recording.
2. `02-cameras.jpg`: camera defaults and available audio.
3. `03-audio.jpg`: MIC 1 soundtrack, MIC 2 optional; selected-camera WAVs remain visibly included.
4. `04-ready.jpg`: completed demo XML.

The PNG icons were extracted from the installed application resources and resized to 128 pixels with `sips`:

- `final-cut.png`: Final Cut Pro, `AppIcon.icns`.
- `fcpxml.png`: Final Cut Pro, `XML.icns`.
- `resolve.png`: DaVinci Resolve, `Resolve.icns`.
- `drp.png`: DaVinci Resolve, `ResolveProject.icns` (the registered DRP document artwork).

Final Cut Pro and its artwork belong to Apple; DaVinci Resolve and its artwork belong to Blackmagic Design. These vendor images identify applications and file types and are not covered by this project's MIT license. Their inclusion does not indicate affiliation or endorsement. The ATEM-native log and Resolve-exported project share an extension but have different contents; the converter only reads the ATEM-native log.

Capture updated screens from the actual app when behavior changes. Keep the matching screenshot captions, image dimensions, and preview installation instructions current.
