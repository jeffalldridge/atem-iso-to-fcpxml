# Tent Studios Website Handoff

Checked October 21, 2026. Recheck release state before publishing version claims.

## Product Copy

**ATEM ISO to FCPXML** converts a Blackmagic ATEM ISO recording into a Final Cut Pro multicam clip and live-edit project, using matching WAV audio when available.

- Free and open source under MIT.
- Finder Quick Action: macOS and Python 3.9 or later.
- No third-party Python packages; Python itself is required. Prefer this wording over “no dependencies.”
- Conversion runs locally and writes an XML beside the recording. It does not upload or transcode footage.
- Import creates an event containing the multicam, project, and selected footage; it does not target the selected event.
- Tested with ATEM Mini Pro ISO recordings at 1080p60 in Final Cut Pro 12.4. Do not imply every ATEM ISO model or frame rate has been tested.

## Links and Release State

- [Product site](https://jeffalldridge.github.io/atem-iso-to-fcpxml/)
- [Releases](https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest)
- [Troubleshooting](troubleshooting.md)
- [Validation](validation.md)
- [Vendor references](vendor-reference.md)

The published download is **1.0.0**, which has a Finder dialog bug (`promptText`, error -1728). **1.0.1 is source-only**, including the fix. Do not advertise 1.0.1 as released or present the 1.0.0 ZIP as a working Finder install. The troubleshooting page provides the current source-install workaround. Update this note once the patch is published and its downloaded artifact is verified.

## Useful Support Content

One practical “ATEM ISO to Final Cut Pro” guide is enough: requirements, installation, camera/audio choices, XML import, and the event destination. Include the native ATEM DRP versus Resolve-exported DRP distinction and link to troubleshooting. Avoid separate near-duplicate pages for each search phrase.

Keep implementation documentation in this repository and link to it. Use the product SVG as the icon source; preserve transparent corners when rasterizing. Leave ratings, reviews, and compatibility claims out of structured data unless supported by evidence.

The paid-app manifest repairs and portfolio checks mentioned by the website agent were not audited in this repository. This handoff does not validate those changes.

## Native App Preview and Visuals

The current site shows four actual SwiftUI app screenshots using a synthetic Sunday Service recording, with vendor app/file icons. Assets and provenance are in `docs/site/images/`. The app is still a source-build preview (macOS 13+ and Python 3.9+), so link to the README native-app build instructions rather than advertising a released app download. Extra audio is optional and does not mix into the soundtrack; camera WAVs already included with selected cameras stay labeled as such.
