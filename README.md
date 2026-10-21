# ATEM ISO to FCPXML

**Turn a Blackmagic ATEM Mini ISO recording into a Final Cut Pro multicam project, with your live switch rebuilt as a timeline and every camera's uncompressed WAV audio in place of the MP4 audio.**

Open the recording folder from your ATEM SSD in the app, confirm which cameras and which soundtrack you want, and import the `.fcpxml` it writes into Final Cut Pro. No DaVinci Resolve, no transcoding, no uploads.

[![Tests](https://github.com/jeffalldridge/atem-iso-to-fcpxml/actions/workflows/tests.yml/badge.svg)](https://github.com/jeffalldridge/atem-iso-to-fcpxml/actions/workflows/tests.yml)
[![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Website: **https://jeffalldridge.github.io/atem-iso-to-fcpxml/**

## Download

**[Download ATEM ISO to FCPXML for Mac](https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest/download/ATEM-ISO-to-FCPXML.dmg)** (macOS 15 or later, Apple silicon and Intel, signed and notarized).

Open the disk image, drag the app to Applications, and open it. Then:

1. Mount the ATEM SSD and drop the recording folder on the window, or click **Choose Recording…**. Double-clicking the `.drp` inside the folder works too.
2. Check the cameras you used (the ones you switched to live are already checked), pick the WAV for the soundtrack, and add the mic inputs as extra angles if you want them.
3. Click **Create Final Cut XML**, then **Open in Final Cut Pro**.

Final Cut creates an event named after the recording folder containing the multicam clip, the Live Edit project, and every source file. Trim, fix a switch in the Angle Viewer, add titles, and export.

## What You Get in Final Cut Pro

- **A multicam clip** with one angle per camera input you chose. Each angle is the camera's high-quality ISO `.mp4` for picture and its 24-bit `.wav` for sound, so the compressed AAC audio inside the MP4 is never used (a camera without a matching WAV falls back to its MP4 audio, with a note).
- **A "Live Edit" project**: the switch you performed on the ATEM, cut for cut. ATEM mix transitions become real, editable Cross Dissolves. The soundtrack stays on one audio angle while the picture changes, exactly like a multicam edit made in Final Cut.
- **Extra audio-only angles** for the ATEM mic inputs, so switching the whole soundtrack to the sound board feed is one click in the Angle Viewer.
- **Media Player stills** as their own angle, so a graphic you put on air appears in the timeline too.
- **Every selected source file** as a browser clip.

The recording is never modified. The app writes exactly one new file, `<name>.fcpxml`, next to the `.drp`, and asks before replacing an existing one.

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

## Requirements and Limits

- The app needs macOS 15 or later. Final Cut Pro 10.6 or newer reads the XML (FCPXML 1.10); verified on Final Cut Pro 12.4.
- The recording folder as the ATEM wrote it: `<name>.drp`, `<name>.mp4`, `Video ISO Files/`, `Audio Source Files/`. You can rename the folder and move it to another drive; media is found relative to the `.drp`. Keep the files inside it as they are.
- One session per conversion. If the ATEM appended a second session to the same `.drp`, use the command line with `--session`.
- Keys are not rebuilt as Final Cut effects; the program recording stands in for them. Media Player graphics swapped during the recording are not reconstructed.
- The XML references the media where it is. Keep the SSD mounted while Final Cut imports (and copies, if your import settings copy media), or copy the recording folder to your edit drive first.
- Final Cut imports into the event named in the file, not the event you have selected. Move the items afterward if you want them elsewhere.

Tested on two real ATEM Mini Pro ISO recordings (1080p60, 46 and 95 minutes, with and without transitions). Other models, frame rates, and firmware versions follow the same documented format but have only synthetic test coverage; please report what you find.

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

The Mac app and the Python script share one design: the app's Swift engine is tested to produce byte-identical XML to the script on every synthetic scenario and on the real recordings. `python3 scripts/build_quick_action.py --install` also builds a Finder Quick Action that embeds the script (it hands off to the app when the app is installed).

Release downloads include `atem_iso_to_fcpxml.py` and `SHA256SUMS.txt`; verify with `shasum -a 256 -c --ignore-missing SHA256SUMS.txt` in the download folder.

## How It Works

The `.drp` is not a DaVinci Resolve project archive. It is a newline-delimited JSON log the switcher writes while recording: a header listing the inputs, media files, and video mode, then one sparse state update per switcher event. [docs/drp-format.md](docs/drp-format.md) describes it. The converter replays that log onto the recording's frame grid, reads the MP4 and WAV headers directly (no ffmpeg) to confirm frame counts and timecode, and writes FCPXML in the shapes Final Cut Pro actually accepts, which took some finding; see [docs/fcpxml-structure.md](docs/fcpxml-structure.md).

## Alternatives

- [ATEM TO FCP](https://www.marcobucci.eu/atem-to-fcpxml.html) is a commercial Mac App Store app that reads the same `.drp` and reconstructs keys and transitions in more detail.
- [ATEM Exporter](https://atemexporter.fcp.cafe/) logs the switcher live over the network instead of reading the `.drp`.
- [drp-trimmer](https://github.com/faithncode/drp-trimmer) trims `.drp` recordings and exports Premiere or Final Cut XML, with FFmpeg.

This project is the small, free, inspectable option: a native Mac app with no dependencies, WAV audio by default, and a one-file script that does the same thing.

## Building and Contributing

```bash
swift test && python3 -m unittest discover -s tests
make app
```

`make app` assembles the universal, ad-hoc signed app in `build/`. [docs/releasing.md](docs/releasing.md) covers signing, notarization, and the release workflow; [docs/app.md](docs/app.md) covers the app's structure. The maintainer notes start at [docs/vendor-reference.md](docs/vendor-reference.md).

Please never attach real recordings, `.drp` logs, generated `.fcpxml` files, or Final Cut libraries to an issue; they contain personal paths and often people. See [CONTRIBUTING.md](CONTRIBUTING.md).

MIT licensed. Not affiliated with Blackmagic Design or Apple; ATEM, Final Cut Pro, and DaVinci Resolve are their trademarks.
