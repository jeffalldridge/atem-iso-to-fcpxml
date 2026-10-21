# ATEM ISO to FCPXML

Convert **Blackmagic ATEM Mini ISO recordings to Final Cut Pro** with the live edit, a native multicam clip, and uncompressed WAV audio. A small local Python utility with an optional macOS Finder Quick Action. No Resolve export step, transcoding, uploads, account, or Python package dependencies at runtime.

**Status: early alpha.** See [validation](docs/validation.md) for exactly what has been checked and what still needs review.

## The everyday workflow

1. Mount the ATEM recording SSD.
2. Right-click its native `.drp` file or recording folder → **Quick Actions → ATEM ISO to FCPXML**.
3. Select the camera inputs you want; the inputs used in the live edit are selected by default.
4. Choose the main WAV soundtrack; **CAM 1** is the default.
5. Import the generated `.fcpxml` using **File → Import → XML** in Final Cut Pro.

The recording stays where it is. Keep the SSD mounted while editing, or copy the whole recording folder before converting. XML contains file references, not copies of your recordings.

## Install

Requires **Python 3.9+**, **ffprobe** (part of FFmpeg), and Final Cut Pro with FCPXML 1.10 import support. The converter uses only the Python standard library. Python and FFmpeg must be installed separately; the Quick Action is not a standalone app.

With [Homebrew](https://brew.sh/) already installed:

```sh
brew install python ffmpeg
git clone https://github.com/jeffalldridge/atem-iso-to-fcpxml.git
cd atem-iso-to-fcpxml
python3 scripts/install_macos.py
```

This copies the converter into `~/Library/Application Support/ATEM ISO to FCPXML` and registers a Finder service in `~/Library/Services`. No administrator access is needed. Run the installer again after updating the source. Keep the Python installation used by the installer available.

If the action is hidden, enable it in macOS Services/Quick Actions settings; the location varies by macOS version. You can also run the command-line converter directly.

To uninstall, remove the `ATEM ISO to FCPXML.workflow` link from `~/Library/Services` and the `ATEM ISO to FCPXML` folder from `~/Library/Application Support`. This does not touch recordings or generated XML.

## Command line

```sh
python3 atem_iso_to_fcpxml.py "/Volumes/Recording SSD/Service/Service.drp"

# Choose inputs and audio explicitly.
python3 atem_iso_to_fcpxml.py "/Volumes/Recording SSD/Service" \
  --cameras 1,2 --audio "CAM 1"

# Exclude optional MIC angles, or use --extra-audio repeatedly to select them.
python3 atem_iso_to_fcpxml.py "/Volumes/Recording SSD/Service" \
  --cameras 1,2 --audio "MIC 1" --no-extra-audio \
  --output "$HOME/Desktop/Service.fcpxml"
```

By default, output is beside the DRP: `Service.fcpxml` and `Service.conversion.json`. Existing files are never overwritten. The Finder action chooses a numbered filename on repeat conversions. On the command line, use `--unique-output` or choose another filename with `--output`. The report lists the frame count, selected cameras, audio choice, and every program fallback range.

`pip install .` also installs the `atem-iso-to-fcpxml` command. The Finder installer does not require pip.

## What you get

- A **Live Edit** project with the recorded camera decisions applied to multicam segments. Switch camera angles or adjust the edit in Final Cut.
- A **Multicam** browser clip with only your selected video inputs.
- Each camera's MP4 paired with its matching uncompressed WAV through a reusable camera compound clip.
- A continuous main WAV soundtrack on the live timeline. MP4 embedded audio is excluded.
- Available **MIC 1** and **MIC 2** WAVs as separate audio-only multicam angles by default. They are alternatives, not automatically summed into the mix.
- Individual WAV clips in the event browser.
- Stills from the ATEM media folder where referenced by the DRP.

The main audio is connected to the first picture clip. When deleting that first clip, preserve or reconnect the soundtrack in Final Cut so you do not delete its connected audio accidentally.

WAV preserves the recorded PCM quality; it cannot undo clipping, change how the signal was originally recorded, or create additional headroom. The tool assumes ATEM-created WAVs begin with the corresponding ISO recording. It does not perform waveform sync or compensate for camera/mixer delays.

## Transitions and effects

Straight camera sections use the high-quality ISO MP4s. For a transition, active key, fade to black, or generated color source, this version uses the matching section of the **program MP4**, with a marker and report entry. This preserves the rendered visual while avoiding a guessed effect reconstruction. These short sections retain program-recording picture quality and have baked effects; their audio still comes from WAV.

This is a deliberate first-version tradeoff. Native editable dissolves and more complete effect translation can follow after import and timing acceptance.

## Supported inputs and limits

- Native ATEM **version 1 newline-delimited JSON DRPs**. A `.drp` exported by DaVinci Resolve is a different archive format and is rejected.
- One continuous session, progressive 720p/1080p, common integer and fractional frame rates. Fractional/drop-frame and midnight logic have synthetic tests; real-recording validation is narrower.
- Camera ISO files and their matching WAVs must cover the full session and use the expected ATEM names. Mismatched durations, missing required media, multiple sessions, source-file changes, segmented camera recordings, and unsupported formats stop conversion.
- Cameras used in the live edit must remain selected. You can omit unused inputs or include additional fully recorded inputs.
- Renamed recording folders work: media resolves relative to the selected DRP, ignoring the original volume/folder names stored in the log.
- ATEM Mini Pro ISO / Extreme ISO compatibility beyond the supplied recording format needs community testing. This is not a general Resolve project converter.

## Alternatives

If you prefer an existing commercial Mac app with broader effects and relinking features, evaluate [ATEM TO FCP](https://www.marcobucci.eu/atem-to-fcpxml.html). [ATEM Exporter](https://github.com/latenitefilms/ATEMExporter/blob/main/docs/how-to-use.md) logs switches over Ethernet during production and exports FCPXML. See the [research notes](docs/research.md) for the differences.

## Contributing and privacy

Run `python3 -m unittest discover -s tests -v`. See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) for development and assistant guidance. GPT, Claude, Gemini, and other tools share the same instructions; no agent service is required to use the converter.

Use synthetic examples in issues and pull requests. Keep real DRPs, audio, video, generated XML, conversion reports, screenshots, and Final Cut libraries local. `.gitignore` blocks these common file types and the entire `local/` directory. Generated XML includes absolute media paths and should be treated as private.

MIT licensed. Independent community utility; not affiliated with Blackmagic Design or Apple. Product names belong to their respective owners.
