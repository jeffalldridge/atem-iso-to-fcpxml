# Contributing

Thank you for helping other ATEM owners get into Final Cut faster.

## Reporting a problem

Open an issue with: your ATEM model and firmware, the video standard, the Final Cut Pro version, the converter version (`python3 atem_iso_to_fcpxml.py --version`), what you expected and what happened. The output of `--dry-run` is usually enough; review it for names you do not want public before pasting.

Please do not attach recordings, `.drp` logs, generated `.fcpxml` files, screenshots of the browser, or Final Cut libraries. They contain full file paths and usually people. If a maintainer needs a sample, agree a private way to share it first. Prefer a minimal invented JSON example that reproduces the problem. Removing paths alone does not anonymize a real log: labels, graphics names and timestamps may still identify people or events.

## Development

Python 3.9 or newer, standard library only, one file. Keep it that way: the Quick Action embeds `atem_iso_to_fcpxml.py` verbatim.

```sh
python3 -m unittest discover -s tests -v
python3 scripts/build_quick_action.py --check
```

Rebuild the committed Quick Action with `python3 scripts/build_quick_action.py` whenever the converter changes; CI fails otherwise.

Tests use synthetic MP4, WAV and PNG files generated in a temporary folder. Add a test for every parsing or timing change. When Final Cut Pro is installed the suite also validates the XML against Apple's bundled FCPXML DTD.

## Verifying in Final Cut Pro

A DTD pass is not an import pass. For anything that changes the XML shape, import into a scratch library, open the multicam in the Angle Editor, play across a cut and a dissolve, and export the project as XML again to see what Final Cut kept. [docs/fcpxml-structure.md](docs/fcpxml-structure.md) lists the structures that are known to work and the ones Final Cut silently drops.

## Releases

Use the [release checklist](docs/releasing.md) for version consistency, local verification, artifact checksums, and the distinction between automated checks and a Final Cut import.

## Pull requests

Describe the user-visible change, the evidence (log excerpt, DTD, Final Cut round trip), and what you tested on. Keep timing as `Fraction`s until the XML is written.
