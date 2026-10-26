# Contributing

Thank you for helping other ATEM owners get into Final Cut Pro faster. This is a small, focused utility, and it is meant to stay that way: it reads an ATEM ISO recording and writes one `.fcpxml`. Bug reports, synthetic reproductions, and focused fixes are the most useful contributions.

This project is maintained by one person in their spare time. Issues and pull requests are welcome and are read, but there is no support commitment or guaranteed response time.

## Reporting a problem

Open an [issue](https://github.com/jeffalldridge/atem-iso-to-fcpxml/issues/new/choose) and include:

- Your ATEM model and firmware, and the video mode (for example 1080p59.94).
- Your Final Cut Pro and macOS versions, and whether you used the Mac app, the Quick Action, or the command line.
- The app version (**ATEM ISO to FCPXML → About**) or `python3 atem_iso_to_fcpxml.py --version`.
- What you expected, and what happened. In the app, **Details…** after a conversion lists what was written; on the command line, `--dry-run` prints the same.

## Protect private recordings

Please do not attach recordings, `.drp` logs, generated `.fcpxml` files, Final Cut libraries, or screenshots of real footage. They contain full file paths, input names, and usually people. Removing paths does not anonymize a real log: labels, graphic names, and timestamps can still identify people or events. If a maintainer needs a sample, agree on a private way to share it first.

Before pasting any output, read it for names and paths you do not want public.

## Reproduce with synthetic files

The most helpful report is a minimal invented recording that shows the problem. The tests build one in a few lines:

- `tests/test_converter.py` has `RecordingDir`, which writes tiny MP4, WAV, and PNG files that contain valid headers and no real media, plus a hand-written `.drp`. Copy the closest existing test and change what differs.
- A `.drp` is newline-delimited JSON: a header line and sparse updates (see [docs/drp-format.md](docs/drp-format.md)). Create an invented log with generic names and paths for a public issue; do not post an excerpt from a real recording.

## Setting up

You need a Mac with macOS 15 or later and Xcode 26 or later (the app icon uses Icon Composer), plus Python 3.9 or later. Swift Package Manager downloads the pinned Sparkle binary package for the app updater. The converter itself has no dependencies.

```sh
git clone https://github.com/jeffalldridge/atem-iso-to-fcpxml.git
cd atem-iso-to-fcpxml
swift test                                    # Swift engine, app model, Python parity
python3 -m unittest discover -s tests -v      # Python converter, website, release tools
make app                                      # build/ATEM ISO to FCPXML.app, universal and ad-hoc signed
```

This is a Swift package, not an Xcode project. Open `Package.swift` in Xcode if you want an IDE.

## Which implementation is authoritative

| Path | Role |
| --- | --- |
| `atem_iso_to_fcpxml.py` | The specification and the command-line tool. Standard library only. |
| `Sources/ATEMConverter` | A Swift port that must write **byte-identical XML** for the same recording and options. |
| `Sources/ATEMISOtoFCPXML` | The SwiftUI app. It calls the Swift engine. |
| `quick-action/` | Generated from the Python file. Never edit it by hand. |

Change behavior in the Python file first, with a test. Then mirror it in Swift; `swift test` runs the Python script on synthetic recordings and compares the XML bytes, so a difference fails the build. The app and the command line do not share every default (the app starts with no extra audio angles; the command line includes WAVs that have no camera). The engine output is identical for identical options.

Keep timing exact: `Fraction` in Python and `Rational` in Swift until the XML is written. Never use floating point for times.

## Before you submit

Run all three; CI runs them too.

```sh
swift test
python3 -m unittest discover -s tests -v
python3 scripts/build_quick_action.py --check
```

If you changed `atem_iso_to_fcpxml.py`, rebuild the Quick Action with `python3 scripts/build_quick_action.py` and commit the result. If you changed the app's interface, run `make app`, open the app on a synthetic recording, and describe what you checked.

## Changes that need a Final Cut round trip

A passing parser or DTD check does not show that Final Cut imports the file the way you expect. Final Cut silently drops some valid structures. A round trip is required for anything that changes the XML the converter writes: element structure, clip or angle layout, transitions, audio wiring, or time values. It is not required for interface, parsing-error, or documentation changes.

To do one: import the file into a scratch library, open the multicam in the Angle Editor, play across a cut and a dissolve, then export the project as XML again and compare what Final Cut kept. [docs/fcpxml-structure.md](docs/fcpxml-structure.md) lists the structures that are known to work and the ones Final Cut drops. Record the result, with the Final Cut version, in [docs/validation.md](docs/validation.md).

## Proposing a change

For anything larger than a bug fix, open an issue first and describe the situation you want to handle. Features that would make the tool broader (other editors, rebuilding keys as Final Cut effects, audio sync by waveform) change what the project has to maintain and are unlikely to be accepted. Small, focused pull requests that include a test are easiest to review. In the description, say what changed for the user and what evidence supports it: a test, a log excerpt, or a Final Cut round trip.

## Releases

Maintainers use the [release checklist](docs/releasing.md). Contributors do not need to touch version numbers or release files.

## More reading

- [README.md](README.md): what the tool does and its limits.
- [docs/architecture.md](docs/architecture.md) and [docs/app.md](docs/app.md): how the converter and app are structured.
- [docs/validation.md](docs/validation.md): what has and has not been verified.
- [SECURITY.md](SECURITY.md): privacy and reporting a vulnerability.
- [AGENTS.md](AGENTS.md): the same rules for AI coding agents.
