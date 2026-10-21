# Research Notes

Checked 2026-10-21. Links are to primary sources where they exist. See [vendor-reference.md](vendor-reference.md) for the reviewed vendor sections, code mapping, and evidence boundaries.

## Blackmagic ATEM ISO Recording

- Models that record ISO: ATEM Mini Pro ISO, Mini Extreme ISO (and G2), SDI Pro ISO, SDI Extreme ISO, Television Studio HD8 ISO. All record at the switcher standard, which is 1080p only (23.98–60); none record 4K or interlaced ISO files. Sources: [ATEM Mini tech specs](https://www.blackmagicdesign.com/products/atemmini/techspecs/W-ABP-03), [ATEM SDI tech specs](https://www.blackmagicdesign.com/products/atemsdi/techspecs), [ATEM Television Studio tech specs](https://www.blackmagicdesign.com/products/atemtelevisionstudio/techspecs).
- The manual's "Recording ISO files" section describes the folder (`Video ISO Files`, `Audio Source Files`, `Media Files`), that ISO MP4s carry program audio, that the WAVs "exclude any processing or EQ from the built in audio mixer", that the timecode generator runs time of day by default, and that re-recording under the same name appends to the `.drp`.
- No official description of the `.drp` contents exists. Community work: [otio-drp-adapter](https://github.com/gilou/otio-drp-adapter) (cuts only), [a Go writer that mirrors the format](https://github.com/McHauge/Spout-Multi-Recorder/blob/main/internal/resolve/resolve.go), forum threads about `transitionActive` on the Extreme and `fadeToBlack` breaking Resolve imports. [docs/drp-format.md](drp-format.md) is our own description from real logs.

## Existing Converters

| Tool | Reads the `.drp` | WAV audio | Transitions | License |
| --- | --- | --- | --- | --- |
| [ATEM TO FCP](https://www.marcobucci.eu/atem-to-fcpxml.html) (Marco Bucci) | Yes | Syncs external WAV/BWF by LTC | Rebuilds program, keys, T-bar | Commercial, Mac App Store |
| [ATEM Exporter](https://atemexporter.fcp.cafe/) (LateNite Films) | No, logs the switcher live over Ethernet | No | Not stated | Commercial |
| [drp-trimmer](https://github.com/faithncode/drp-trimmer) | Yes | Picks a camera ISO as primary audio | Dissolves | MIT, needs FFmpeg |
| [otio-drp-adapter](https://github.com/gilou/otio-drp-adapter) | Yes | No | No | Open source |
| This project | Yes | Every camera's WAV by default, mics as angles | Dissolves, program fallback | MIT, no dependencies |

## Apple FCPXML

- [FCPXML reference](https://developer.apple.com/documentation/professional-video-applications/fcpxml-reference) and the DTDs bundled inside Final Cut Pro (`Final Cut Pro.app/Contents/Frameworks/Interchange.framework/Resources/FCPXMLv1_*.dtd`). The converter writes 1.10 (Final Cut 10.6, 2021). Final Cut 11 writes 1.13 and Final Cut 12 writes 1.14.
- [Multicam media](https://developer.apple.com/documentation/professional-video-applications/multicam-media): `mc-source` with `srcEnable` of `audio`, `video`, or `all` lets one `mc-clip` take picture and sound from different angles.
- [Transition](https://developer.apple.com/documentation/professional-video-applications/transition): the DTD comment describes overlap, but Final Cut's own exports butt-join the clips and center the transition on the cut, which is what we write.
- [Describing Final Cut Pro items in FCPXML](https://developer.apple.com/documentation/professional-video-applications/describing-final-cut-pro-items-in-fcpxml): items with no `event` element are imported into a new event named after the date.
- Final Cut Pro User Guide, [Fade audio in and out](https://support.apple.com/guide/final-cut-pro/ver66d503b23/mac): "+3 dB" is the default fade, which prompted the measurement in [validation.md](validation.md); the result was gain-neutral.
- [EBU Tech 3285](https://tech.ebu.ch/docs/tech/tech3285.pdf): the Broadcast Wave `bext` chunk and its 64-bit `TimeReference` in samples since midnight.

## macOS Quick Actions

A `.workflow` bundle double-clicked in Finder opens Automator's installer sheet (Open in Automator / Install) and lands in `~/Library/Services`. `/usr/bin/python3` on a fresh Mac is a shim that offers to install the Command Line Tools the first time it runs, which is why the Quick Action checks for Python and explains what to install.
