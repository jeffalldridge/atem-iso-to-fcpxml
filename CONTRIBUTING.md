# Contributing

Small fixes and synthetic compatibility cases are welcome. Open an issue describing the model, firmware, video mode, converter version, expected result, and observed result. Review any diagnostic text for names and paths before posting it.

Never attach real church/event footage, source DRPs, graphics, WAVs, FCP libraries, or generated XML to a public issue. Reproduce the problem with invented metadata and generated test media. Ask the maintainer before arranging any private sample transfer.

Use Python 3.9 or newer and the standard library. Run:

```sh
python3 -m unittest discover -s tests -v
python3 -m py_compile atem_iso_to_fcpxml.py scripts/install_macos.py
```

A PR should explain the user-visible change, the relevant format evidence, and what was tested. Keep timing rational until serialization. Tests should cover actual failure modes, including malformed input, missing media, source containment, WAV replacement, and timing boundaries. Keep private acceptance outputs in ignored `local/`.

For native acceptance, create a separate Final Cut library and import the XML. Review the main WAV, alternate audio, camera switching, stills, program fallback boundaries, and end-of-recording alignment. Do not claim these checks from XML schema validation alone.
