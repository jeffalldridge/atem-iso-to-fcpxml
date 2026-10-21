# Architecture

Two implementations of the same five-stage conversion, with no runtime dependencies in the Mac app. The standard-library Python file is the reference; `Sources/ATEMConverter` is the Swift port, verified by byte-for-byte parity fixtures. See [app.md](app.md) for the SwiftUI state and window architecture. See [vendor-reference.md](vendor-reference.md) for official sources and the boundaries between specifications and observed behavior.

```
.drp + recording folder
   │
   ├─ load_drp / open_recording ─── read the log, find the media, read MP4 and WAV headers
   ├─ build_edit_list ───────────── replay the log onto the frame grid: cuts, dissolves, program fallbacks
   ├─ make_plan ─────────────────── which angles, which soundtrack, names (defaults or dialogs)
   ├─ build_fcpxml ──────────────── the XML shapes Final Cut accepts (docs/fcpxml-structure.md)
   └─ main ──────────────────────── command line, Finder dialogs, write exactly one file
```

- **Timing** is kept as Python `fractions.Fraction` or Swift `Rational` and only formatted as `N/Ds` at the end, so 59.94 fps recordings stay exact.
- **Media inspection** reads ISO BMFF boxes (`moov` → `trak` → `mdhd`, `hdlr`, `stsd`, `stts`, `stco`) to get size, rate, frame count, and the first timecode sample, and RIFF/RF64 chunks (`fmt `, `bext`, `data`) for WAVs. Picture and audio sample data are skipped; only structural metadata and the first timecode sample are read. WAV chunks after audio are inspected by seeking across the data, including RF64 sizes larger than 4 GiB. Metadata read sizes are bounded.
- **Supported ranges**: media outside these limits is rejected with a message rather than risking inexact or overflowing arithmetic. Both engines use the same values (`MAX_*` constants in the Python file, `MediaLimits` in Swift): MP4 timescale up to 1,000,000, at most 2^28 frames, duration up to 2^48 timescale units, frame rate 1 to 240 fps; WAV sample rate 8,000 to 768,000 Hz, up to 2^40 sample frames, time reference up to 2^48 samples. Real ATEM files are far inside them. Swift's `Rational` computes in 128 bits and reduces before narrowing. Differential fuzzing of header bytes found no signal exits or Python/Swift disagreements; `python3 scripts/fuzz_media_headers.py ITERATIONS SEED` repeats it (build `atem-convert` first); the run is described in [validation.md](validation.md), and it is not a proof.
- **State** from the log is merged sparsely: arrays are keyed by `_index_` and patches only touch the keys they name.
- **Safety**: media paths from the log must resolve inside the recording folder; the log is size-limited; outputs are never silently overwritten; nothing is written until the whole document is built and parsed back. New outputs use exclusive creation (including on exFAT); replacements use a temporary sibling and rename so hard links cannot cause recording bytes to be overwritten. Symbolic-link outputs are refused.
- **The Quick Action** is generated from the converter by `scripts/build_quick_action.py`, which embeds it in a zsh heredoc inside an Automator "Run Shell Script" action. CI checks the committed bundle is current.
