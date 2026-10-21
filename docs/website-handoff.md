# Tent Studios Website Handoff

Checked October 21, 2026. Recheck the release page before publishing version claims.

## Product Copy

**ATEM ISO to FCPXML** turns a Blackmagic ATEM Mini ISO recording into a Final Cut Pro multicam project: the live switch rebuilt as a timeline, with each camera's uncompressed WAV audio in place of the MP4 audio.

- Free and open source under MIT.
- A native Mac app: macOS 15 or later, Apple silicon and Intel, signed and notarized, about 2 MB, no dependencies (no Python, no Homebrew, no Resolve). Drag to Applications.
- Conversion runs locally and writes one `.fcpxml` beside the recording. It never changes or uploads footage.
- Importing the XML creates an event named after the recording folder containing the multicam clip, the Live Edit project, and the selected footage; it does not target the currently selected event.
- Verified with ATEM Mini Pro ISO recordings at 1080p60 in Final Cut Pro 12.4. Do not imply every ATEM ISO model or frame rate has been tested.
- A command-line version (one Python file) and a Finder Quick Action exist for people who want them; they are secondary.

Search phrases the page should answer: "ATEM ISO to Final Cut Pro," "open ATEM recording in Final Cut," "DRP to FCPXML," "ATEM Mini ISO multicam Final Cut," "convert DRP to Final Cut."

## Links

- Product site: https://jeffalldridge.github.io/atem-iso-to-fcpxml/
- Download (always the latest disk image): https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest/download/ATEM-ISO-to-FCPXML.dmg
- Release page: https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest
- Source: https://github.com/jeffalldridge/atem-iso-to-fcpxml
- Screenshots and the favicon: `docs/site/images/` and `docs/site/favicon.svg` in the repository (the screenshots show a synthetic "Live Show" recording, no real footage).

## Release State

Version 1.1.0 is the first release with the Mac app. Until the `v1.1.0` release exists on GitHub with `ATEM-ISO-to-FCPXML.dmg` attached, the download link above returns 404; link to the release page instead and say "coming soon." The 1.0.0 release only has a Finder Quick Action ZIP with a known dialog bug; do not link to it.
