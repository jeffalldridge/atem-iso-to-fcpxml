# Product Copy for Other Sites

Plain facts for describing the app on another website. Check the [release page](https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest) before quoting a version or size.

**ATEM ISO to FCPXML** turns a Blackmagic ATEM Mini ISO recording into a Final Cut Pro multicam project: the live switch rebuilt as a timeline, with each camera's uncompressed WAV audio in place of the MP4 audio.

- Free and open source under MIT.
- A native Mac app: macOS 15 or later, Apple silicon and Intel, signed and notarized, about 3 MB, no dependencies (no Python, no Homebrew, no Resolve). Drag it to Applications.
- Conversion runs locally and writes one `.fcpxml` beside the recording. It never changes or uploads footage.
- Importing the XML creates an event named after the recording folder with the multicam clip, the Live Edit project, and the selected footage. It does not target the currently selected event.
- Verified with ATEM Mini Pro ISO recordings at 1080p60 in Final Cut Pro 12.4. Other models and frame rates have only synthetic coverage; do not imply they are tested.
- A recording whose `.drp` holds several sessions is not opened by the app; the command-line version can pick one.
- A command-line version (one Python file) and an optional Finder Quick Action exist for people who want them; they are secondary.

Search phrases the page should answer: "ATEM ISO to Final Cut Pro," "open ATEM recording in Final Cut," "DRP to FCPXML," "ATEM Mini ISO multicam Final Cut," "convert DRP to Final Cut."

## Links

- Product site: https://jeffalldridge.github.io/atem-iso-to-fcpxml/
- Download (the disk image): https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest/download/ATEM-ISO-to-FCPXML.dmg
- Release page: https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest
- Source: https://github.com/jeffalldridge/atem-iso-to-fcpxml
- App icon: `docs/site/app-icon-1024.png` in the repository, rendered by macOS from the Icon Composer source `Resources/AppIcon.icon`. Screenshots: `docs/site/images/` (a synthetic "Live Show" recording, no real footage).
