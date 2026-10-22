# ATEM ISO to FCPXML

**Turn a Blackmagic ATEM Mini ISO recording into a Final Cut Pro multicam project, with your live switch rebuilt as a timeline and every camera's uncompressed WAV audio in place of the MP4 audio.**

Open the recording folder from your ATEM SSD in the app, confirm which cameras and which soundtrack you want, and import the `.fcpxml` it writes into Final Cut Pro. No DaVinci Resolve, no transcoding, no uploads.

[![Tests](https://github.com/jeffalldridge/atem-iso-to-fcpxml/actions/workflows/tests.yml/badge.svg)](https://github.com/jeffalldridge/atem-iso-to-fcpxml/actions/workflows/tests.yml)
[![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Website: **https://jeffalldridge.github.io/atem-iso-to-fcpxml/**

## Download

**[Download ATEM ISO to FCPXML for Mac](https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest/download/ATEM-ISO-to-FCPXML.dmg)** (macOS 15 or later, Apple silicon and Intel, signed and notarized, about 3 MB). The [release page](https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest) lists the other files. Free and open source under the MIT license.

Open the disk image, drag the app to Applications, and open it. Then:

1. Mount the ATEM SSD and drop the recording folder on the window, or click **Choose Recording…**. You can also select the `.drp` in Finder and use **Open With → ATEM ISO to FCPXML**.
2. Check the cameras you used (the ones you switched to live are already checked), pick a WAV or **ATEM live mix** for the soundtrack, and add the mic inputs as extra angles if you want them. The window shows where the file will be saved.
3. Click **Create FCPXML**, then **Open in Final Cut Pro**.

Final Cut creates an event named after the recording folder containing the multicam clip, the Live Edit project, the camera and Media Player compounds, and the source files. Trim, fix a switch in the Angle Viewer, add titles, and export.

## What You Get in Final Cut Pro

- **A multicam clip** with one angle per camera input you chose. Each angle is the camera's high-quality ISO `.mp4` for picture and its 24-bit `.wav` for sound, when available. A camera without a matching WAV falls back to its MP4 audio, with a note.
- **A "Live Edit" project**: the switch you performed on the ATEM, cut for cut. ATEM mix transitions become real, editable Cross Dissolves. The soundtrack stays on one audio angle while the picture changes, exactly like a multicam edit made in Final Cut.
- **Extra audio-only angles** for the ATEM mic inputs, available to switch to or mix in Final Cut. Adding an angle makes it available; it does not turn it on in the initial Live Edit.
- **Media Player stills** as their own angle, with a linked “Media Player 1 - Still” compound and the original image visible in the browser. Open the compound to edit the graphic used by the multicam.
- **Camera compounds in the browser**, named “Camera 1 - ISO + WAV” (or your input label). Each is the same compound used by its multicam angle, ready to open and edit.
- **Every selected MP4, WAV, and still image** as a browser clip.

The recording is never modified. The app writes exactly one new file, `<name>.fcpxml`, next to the `.drp`, and asks before replacing an existing one.

### Editing the Sources

Double-click the multicam in the browser to open the Angle Editor. Each angle shows its clip at the recording's original timecode. Double-click a camera or Media Player compound, either there or in the browser, to open its contents in a separate timeline. A camera compound contains the ISO picture and connected WAV; a Media Player compound contains the original still image. You can also select the compound and choose **Clip → Open Clip**. Edit the contents of that compound to update its uses in the multicam and Live Edit. The raw MP4 browser clips retain their original compressed audio; the compounds use the WAV.

These are shared clips: editing a compound changes its uses throughout the library.

The event keeps the recording folder's name. If you import again with matching event and clip names, Final Cut may ask **Keep Both** or **Replace**. Choose **Keep Both** to preserve your edits; in Final Cut Pro 12.4 this adds numbered copies in the existing event. A different event name keeps the imports separate (`--event` on the command line, or rename the recording folder before conversion). The converter cannot inspect names already in your Final Cut library. Each conversion writes exactly one Live Edit project and one multicam. Older imports with different names, including early development names with an em dash, remain separate items; a new import does not remove them.

## How ATEM Operations Are Translated

| On the ATEM | In the Final Cut timeline |
| --- | --- |
| Cut between inputs | Cut between multicam clips, frame-accurate to the switcher log |
| Mix (dissolve) transition, auto or T-bar | Cross Dissolve of the same length, centered on the switch |
| Dip, wipe, DVE, or stinger transition | Cross Dissolve plus a marker saying what the ATEM did (or the rendered program picture, if you choose that option) |
| Media Player still on air | The still as its own angle |
| Upstream or downstream key on air, fade to black, color generator | That stretch of the ATEM **program recording** as an angle, with a marker; if the program recording is missing, the first camera stands in, with a marker |
| Transition to the same input, or a key-only transition | No change |

Audio never follows the picture: every timeline clip plays the soundtrack angle, and dissolves are audio-transparent when both sides use the same angle (measured; see [validation](docs/validation.md)).

## Why WAV Instead of the MP4 Audio

The ATEM's ISO MP4s carry the switcher's **program mix** as AAC. The WAVs in `Audio Source Files` are each input's own 24-bit, 48 kHz audio before the ATEM mixer touches it. Using them gives you clean, per-source audio with full headroom for your own leveling, EQ, and compression in Final Cut, and lets a mic input become the soundtrack even if it was not in the stream mix.

Each WAV carries a Broadcast Wave time reference that matches the ATEM's master timecode, and every ISO MP4 carries that timecode too. The converter preserves those values and assumes the native files share a recording start. It warns about different start times or short media; it does not correct those offsets or analyze waveforms.

### What Happens to the Live Audio Mix?

The converter rebuilds the picture edit and uses **one selected audio source continuously**. Choose **ATEM live mix** to keep the recorded mix, or a WAV to use one isolated input. The converter does not reconstruct separate audio-follow-video (AFV), input on/off, fader, EQ, or dynamics automation. A camera WAV is that input's isolated recording, not the live mixed soundtrack. Choosing a WAV can therefore bring back sound that was off in the live mix, or omit other inputs that were on. Extra audio angles remain available for editing; they do not play automatically.

Final Cut supports audio from multiple multicam angles at once. Select a multicam clip in the project timeline, open the **Audio inspector**, and enable the additional angle components. Choose **Clip → Expand Audio Components** to adjust them individually. In the Angle Viewer, audio-only switching also lets you Option-Command-click an angle to add or remove its audio. These are Final Cut editing controls, not a reconstruction of the original ATEM mixer. See Apple's [multicam audio guidance](https://support.apple.com/guide/final-cut-pro/multicam-editing-tips-verb1160b2d/mac) and [audio switching instructions](https://support.apple.com/guide/final-cut-pro/cut-and-switch-camera-angles-ver23c76c9c/mac).

The recorded program audio contains the live mixed result. Preserving that recording preserves how the live AFV and mixer decisions sounded, but those decisions are baked into the mix rather than separately editable. Choose **ATEM live mix** under Soundtrack (or `--live-mix` on the command line). It uses the Program MP4 when it has audio, otherwise a selected ISO MP4 with audio. WAV remains the default when available; recordings with no WAVs use the live mix automatically. The optional **Program** angle supplies picture independently. Changing the picture edit later does not recompute AFV in an existing recorded mix.

## Requirements and Limits

- The app needs macOS 15 or later. Final Cut Pro 10.6 or newer reads the XML (FCPXML 1.10); verified on Final Cut Pro 12.4.
- The recording folder as the ATEM wrote it: `<name>.drp`, `<name>.mp4`, `Video ISO Files/`, `Audio Source Files/`. You can rename the folder and move it to another drive; media is found relative to the `.drp`. Keep the files inside it as they are.
- One session per conversion. If the ATEM appended a second session to the same `.drp`, the app tells you so and does not open it; use the command line with `--session`. Multi-session logs have only been tested with invented recordings.
- Keys are not rebuilt as Final Cut effects; the program recording stands in for them. Media Player graphics swapped during the recording are not reconstructed.
- The XML references the media where it is. Keep the SSD mounted while Final Cut imports (and copies, if your import settings copy media), or copy the recording folder to your edit drive first.
- Final Cut imports into the event named in the file, not the event you have selected. Move the items afterward if you want them elsewhere.

Tested with recordings from the ATEM Mini Pro ISO at 1080p60, with and without transitions, imported into Final Cut Pro 12.4. Other ATEM ISO models, frame rates, and firmware use the same format but have only been tested with synthetic recordings; reports are welcome.

### Updating

Open the [latest release](https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest) (**Latest Release on GitHub…** in the app menu opens it), quit the app, and drag the new version into the same Applications folder. Choose **Replace** when Finder asks. Keep one installed copy. Updates are manual: the app makes no network requests and does not check for new versions. If you also installed the optional Finder Quick Action, install the newer one over it, because it carries its own copy of the converter.

## Command Line and Automation

The same conversion is available as a single standard-library Python file for scripting, Linux, or anyone who prefers a terminal:

```bash
python3 atem_iso_to_fcpxml.py "/Volumes/ATEM SSD/Live Show"
```

```text
atem-iso-to-fcpxml RECORDING [options]

RECORDING                the .drp file, or the recording folder that contains it
-o, --output FILE        write here instead of next to the .drp
--cameras 1,2            inputs to include as angles (default: the inputs used in the live switch)
--audio "MIC 1"          soundtrack WAV, by suffix or file name (default: the first camera's WAV)
--live-mix               recorded ATEM mix instead of an isolated WAV; cannot combine with --audio
--extra-audio "CAM 3"    add an audio-only angle; repeatable (default: every WAV with no camera, i.e., the mics)
--no-extra-audio         no audio-only angles
--transitions MODE       dissolve (default), cut, or program
--program-angle          always include the ATEM program recording as an angle
--name NAME              base name for the multicam clip and project (default: the folder name)
--event NAME             Final Cut event to create (default: same as --name); --no-event files it under today's date
--session N              pick a session when one .drp holds several recordings
--force                  replace an existing .fcpxml
--dry-run                print what would be made and write nothing
```

The Mac app and the Python script share one design: the app's Swift engine is tested to produce byte-identical XML to the script on the parity scenarios listed in [validation](docs/validation.md), including real recordings. `python3 scripts/build_quick_action.py --install` also builds a Finder Quick Action that embeds the script (it hands off to the app when the app is installed).

Release downloads include `atem_iso_to_fcpxml.py` and `SHA256SUMS.txt`; verify with `shasum -a 256 -c --ignore-missing SHA256SUMS.txt` in the download folder.

## How It Works

The `.drp` is not a DaVinci Resolve project archive. It is a newline-delimited JSON log the switcher writes while recording: a header listing the inputs, media files, and video mode, then one sparse state update per switcher event. [docs/drp-format.md](docs/drp-format.md) describes it. The converter replays that log onto the recording's frame grid, reads the MP4 and WAV headers directly (no ffmpeg) to confirm frame counts and timecode, and writes FCPXML in the structures Final Cut Pro imports faithfully, established by import and export round trips; see [docs/fcpxml-structure.md](docs/fcpxml-structure.md).

## Alternatives

- [ATEM TO FCP](https://www.marcobucci.eu/atem-to-fcpxml.html) is a commercial Mac App Store app that reads the same `.drp` and reconstructs keys and transitions in more detail.
- [ATEM Exporter](https://atemexporter.fcp.cafe/) logs the switcher live over the network instead of reading the `.drp`.
- [drp-trimmer](https://github.com/faithncode/drp-trimmer) trims `.drp` recordings and exports Premiere or Final Cut XML, with FFmpeg.

This project is free and open source: a native Mac app with no dependencies, per-camera WAV audio, and a one-file script that does the same conversion.

## Contributing

Bug reports, synthetic reproductions, and focused fixes are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to build, test, and propose a change, and [SECURITY.md](SECURITY.md) covers privacy and vulnerability reports. Please never attach real recordings, `.drp` logs, generated `.fcpxml` files, or Final Cut libraries to an issue; they contain personal paths and often people.

```bash
swift test && python3 -m unittest discover -s tests
make app      # build/ATEM ISO to FCPXML.app, universal and ad-hoc signed
```

Technical documentation is in [docs/](docs/): [app structure](docs/app.md), [architecture](docs/architecture.md), the [maintainer handoff and future considerations](docs/next-work.md), the [`.drp` format](docs/drp-format.md), the [FCPXML structures](docs/fcpxml-structure.md), [validation](docs/validation.md), [vendor references](docs/vendor-reference.md), [releasing](docs/releasing.md), and the [website](docs/website.md).

MIT licensed. Not affiliated with Blackmagic Design or Apple; ATEM, Final Cut Pro, and DaVinci Resolve are their trademarks.
