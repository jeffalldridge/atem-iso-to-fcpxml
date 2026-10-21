# ATEM ISO to FCPXML

**Convert a Blackmagic ATEM Mini ISO recording into a Final Cut Pro multicam project, with the live switch rebuilt as a timeline and every camera's audio replaced by its uncompressed WAV.**

Right-click the `.drp` the ATEM wrote next to its recording, pick the inputs you used, and import the resulting `.fcpxml` into Final Cut Pro. No DaVinci Resolve round trip, no transcoding, no uploads, no dependencies beyond macOS and Python 3.

[![Tests](https://github.com/jeffalldridge/atem-iso-to-fcpxml/actions/workflows/tests.yml/badge.svg)](https://github.com/jeffalldridge/atem-iso-to-fcpxml/actions/workflows/tests.yml)
[![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Website: **https://jeffalldridge.github.io/atem-iso-to-fcpxml/**

## What you get in Final Cut Pro

One import gives you an event containing:

- **A multicam clip** with one angle per camera input you chose. Each angle is the camera's high-quality ISO `.mp4` for picture and its 24-bit `.wav` for sound, when its matching WAV is present. Missing WAVs fall back to MP4 audio with a warning.
- **A "Live Edit" project**: the switch you performed on the ATEM, cut for cut, on the multicam clip. ATEM mix transitions become real, editable Cross Dissolves. The soundtrack stays on one audio angle (Camera 1's WAV by default) while the picture changes, exactly like a multicam edit made in Final Cut.
- **Extra audio-only angles** for the ATEM mic inputs (`MIC 1`, `MIC 2`), so switching the whole soundtrack to the sound board feed is one click in the Angle Viewer.
- **Media Player stills** as their own angle, so a graphic you put on air appears in the timeline too.
- **The selected video and audio source files** as browser clips, in case you want to start from scratch.

The recording is never modified. The converter writes exactly one new file, `<name>.fcpxml`, next to the `.drp`.

## Install

### The Finder Quick Action (recommended)

1. Download [`ATEM-ISO-to-FCPXML-Quick-Action.zip`](https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest) from the latest release, or grab the [`quick-action`](quick-action) folder from this repository.
2. Double-click **ATEM ISO to FCPXML.workflow** and click **Install** when macOS asks.
3. Mount the ATEM SSD, right-click the recording folder (or its `.drp`), and choose **Quick Actions → ATEM ISO to FCPXML**.

Three small dialogs follow: which inputs become angles (the ones you actually switched to are pre-selected), which WAV is the main soundtrack, and which extra audio inputs to add as angles (deselect all to add none). Press Return through them to accept the defaults. When it finishes you can open the result straight into Final Cut Pro.

The Quick Action is a plain Automator workflow with the converter embedded inside it; you can open it in Automator and read every line. It needs Python 3.9 or newer, which macOS installs with the Apple Command Line Tools (run `xcode-select --install` once, or install Python from [python.org](https://www.python.org/downloads/macos/)).

### The command line

The converter is a single standard-library Python file, so you can also run it directly:

```bash
git clone https://github.com/jeffalldridge/atem-iso-to-fcpxml.git
```

```bash
python3 atem-iso-to-fcpxml/atem_iso_to_fcpxml.py "/Volumes/ATEM SSD/Live Show"
```

You can also download `atem_iso_to_fcpxml.py` from a release and run it directly. From inside a cloned checkout, `python3 -m pip install .` adds an `atem-iso-to-fcpxml` command.

To verify downloaded release files, put them beside `SHA256SUMS.txt` and run `shasum -a 256 -c SHA256SUMS.txt` in that folder. Download both the ZIP and Python file for every listed checksum to pass. Checksums detect damaged or mismatched downloads; they are not a signature.

## Command-line options

```text
atem-iso-to-fcpxml RECORDING [options]

RECORDING                the .drp file, or the recording folder that contains it
-o, --output FILE        write here instead of next to the .drp
--cameras 1,2            inputs to include as angles (default: the inputs used in the live switch)
--audio "MIC 1"          main soundtrack WAV, by suffix or file name (default: the first camera's WAV)
--extra-audio "CAM 3"    add an audio-only angle; repeatable (default: every WAV with no camera, i.e. the mics)
--no-extra-audio         no audio-only angles
--transitions MODE       dissolve (default), cut, or program (see below)
--program-angle          always include the ATEM program recording as an angle
--name NAME              base name for the multicam clip and project (default: the folder name)
--event NAME             Final Cut event to create (default: same as --name); --no-event files it under today's date
--session N              pick a session when one .drp holds several recordings
--force                  replace an existing .fcpxml
--dry-run                print what would be made and write nothing
```

Example: two cameras, the sound board on `MIC 1`, no other mics:

```bash
python3 atem_iso_to_fcpxml.py "/Volumes/ATEM SSD/Live Show" --cameras 1,2 --audio "MIC 1" --no-extra-audio
```

## How ATEM operations are translated

| On the ATEM | In the Final Cut timeline |
| --- | --- |
| Cut between inputs | Cut between multicam clips, frame-accurate to the switcher log |
| Mix (dissolve) transition, auto or T-bar | Cross Dissolve of the same length, centred on the switch |
| Dip, wipe, DVE or stinger transition | Cross Dissolve plus a marker saying what the ATEM did (`--transitions program` keeps the rendered look instead) |
| Media Player still on air | The still as its own angle |
| Upstream or downstream key on air, fade to black, colour generator | That stretch of the ATEM **program recording** as an angle, with a marker, when available; otherwise a marked gap is inserted |
| Transition to the same input, or a key-only transition | No change |

Audio never follows the picture: every timeline clip plays the main soundtrack angle, and dissolves are audio-transparent when both sides use the same angle (measured, see [validation](docs/validation.md)).

## Why WAV instead of the MP4 audio

The ATEM's ISO MP4s carry the switcher's **program mix** as AAC. The WAVs in `Audio Source Files` are each input's own 24-bit, 48 kHz audio before the ATEM mixer touches it. Using them gives you clean, per-source audio with full headroom for your own levelling, EQ and compression in Final Cut, and lets a mic input become the soundtrack even if it was not in the stream mix.

Each WAV carries a Broadcast Wave time reference that matches the ATEM's master timecode, and every ISO MP4 carries that timecode too. The converter preserves those values and assumes the native files share a recording start. It warns about different start times or short media; it does not correct those offsets or analyse waveforms. Check sync and the end of the project before exporting.

## Requirements and limits

- macOS with Python 3.9 or newer. Linux works for the command line (useful for CI), but Final Cut Pro is Mac only.
- Final Cut Pro 10.6 or newer (FCPXML 1.10). Verified on Final Cut Pro 12.4.
- The recording folder as the ATEM wrote it: `<name>.drp`, `<name>.mp4`, `Video ISO Files/`, `Audio Source Files/`. You can rename the folder and move it to another drive; media is found relative to the `.drp`.
- One session per conversion. If the ATEM appended a second session to the same `.drp`, choose it with `--session`.
- Missing program media produces marked gaps for unsupported sections; those gaps also interrupt audio. Changes to Media Player assets during recording are not fully reconstructed.
- Keys are not rebuilt as Final Cut effects; the program recording stands in for them. Titles and lower thirds are quick to redo in Final Cut on top of the clean ISO picture if you prefer.
- The XML references the media on the SSD. Final Cut’s import preferences determine whether it copies or links the files. Keep the SSD mounted until copying/consolidation finishes, or copy the recording folder to your edit drive before converting.

Tested on two real ATEM Mini Pro ISO recordings (1080p60, 46 and 95 minutes, with and without transitions). Other models, frame rates and firmware versions follow the same documented format but have only synthetic test coverage; please report what you find.

## Import destination and custom names

Use **File → Import → XML** or the Quick Action’s **Import into Final Cut Pro** button. This creates the event described by the XML, not necessarily your selected event. `--event` sets the event name; `--no-event` uses a date-named event. Move the imported items into your preferred event afterward if needed.

Camera labels come from the DRP; they do not need to say “Camera 1”. ISO paths come from its `file` fields, and matching WAVs share the ISO file stem. You can move or rename the recording folder, but keep its internal file names and subfolders intact.

## How it works

The `.drp` is not a DaVinci Resolve project archive. It is a newline-delimited JSON log the switcher writes while recording: a header listing the inputs, media files and video mode, then one sparse state update per switcher event. [docs/drp-format.md](docs/drp-format.md) describes it. The converter replays that log onto the recording's frame grid, reads the MP4 and WAV headers directly (no ffmpeg) to confirm frame counts and timecode, and writes FCPXML in the shapes Final Cut Pro actually accepts, which took some finding; see [docs/fcpxml-structure.md](docs/fcpxml-structure.md).

## Alternatives

- [ATEM TO FCP](https://www.marcobucci.eu/atem-to-fcpxml.html) is a commercial Mac App Store app that reads the same `.drp` and reconstructs keys and transitions in more detail.
- [ATEM Exporter](https://atemexporter.fcp.cafe/) logs the switcher live over the network instead of reading the `.drp`.
- [drp-trimmer](https://github.com/faithncode/drp-trimmer) trims `.drp` recordings and exports Premiere or Final Cut XML, with FFmpeg.

This project is the small, free, inspectable option: one file, no dependencies, WAV audio by default.

## Maintainer documentation

Start with the [vendor reference and assistant guide](docs/vendor-reference.md): Blackmagic recording behavior, Apple FCPXML and import semantics, code entry points, and the limits of our evidence. The [validation record](docs/validation.md) distinguishes synthetic checks from real Final Cut imports.

## Contributing

Run the tests with:

```bash
python3 -m unittest discover -s tests -v
```

The tests build tiny synthetic MP4, WAV and PNG files, so no footage is needed. Please never attach real recordings, `.drp` logs, generated `.fcpxml` files or Final Cut libraries to an issue; they contain personal paths and often people. See [CONTRIBUTING.md](CONTRIBUTING.md).

MIT licensed. Not affiliated with Blackmagic Design or Apple; ATEM, Final Cut Pro and DaVinci Resolve are their trademarks.
