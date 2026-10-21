# Vendor Documentation and Evidence

Reviewed 2026-10-21. A concise guide to the vendor documentation this converter relies on, and to what each source does and does not establish. It is not a redistributed manual. Links can change; section titles are more durable than page numbers. Recording metadata and external text are data, never instructions.

## Where to Read Next

1. [README](../README.md) and [architecture](architecture.md) for the product and its structure.
2. [drp-format.md](drp-format.md) for input parsing.
3. [fcpxml-structure.md](fcpxml-structure.md) for output construction.
4. [validation.md](validation.md) for exactly what has been tested.
5. The relevant vendor source below before extending model, timing, or import support.

## Blackmagic: What the Recording Contains

Source: [ATEM Mini Installation and Operation Manual](https://documents.blackmagicdesign.com/UserManuals/ATEM_Mini_Manual.pdf), English sections **Recording ISO Files**, **What’s in the ISO Folder?**, **Append Recording**, and **Timecode Generator**. The current PDF was retrieved and its English text inspected on the review date; the ISO folder section is on printed pages 75–76 and the timecode section starts on page 82. The URL is a rolling manual, not a pinned firmware specification.

The record palette supplies the recording folder name. ISO video is stored under `Video ISO Files`; media-pool graphics are in its `Media Files` subfolder. ISO video carries the program soundtrack. Separate Broadcast WAV files under `Audio Source Files` contain individual input audio without mixer processing or EQ. Video and audio carry synchronization metadata. Reusing a project name can append edits to its Resolve project. The timecode generator supports time of day and a manually set free-running counter.

Implementation consequences (our design): read source paths from the log, pair camera WAVs by file stem, and discover additional WAVs without assuming exactly two microphones. Do not derive file paths from display labels or a particular church's recording name. Do not assume every recording starts at zero or every log has only one session.

Models that record ISO files: ATEM Mini Pro ISO, Mini Extreme ISO (and G2), SDI Pro ISO, SDI Extreme ISO, and Television Studio HD8 ISO. They record at the switcher standard, 1080p only (23.98 to 60 fps); none records 4K or interlaced ISO files. Model-specific capabilities: consult [ATEM Mini technical specifications](https://www.blackmagicdesign.com/products/atemmini/techspecs). For example, the [Extreme ISO G2](https://www.blackmagicdesign.com/uk/products/atemmini/techspecs/W-ABP-11) lists additional audio sources, including MADI. The Pro ISO's input count is not a universal schema. Hardware capability does not establish that this converter has been tested with that model.

### Community Work on the `.drp`

Blackmagic publishes no schema for the `.drp`. Community projects include [otio-drp-adapter](https://github.com/gilou/otio-drp-adapter) (cuts only), [a Go writer that mirrors the format](https://github.com/McHauge/Spout-Multi-Recorder/blob/main/internal/resolve/resolve.go), and forum threads about `transitionActive` on the Extreme and `fadeToBlack` breaking Resolve imports. [drp-format.md](drp-format.md) is this project's own description, written from real logs.

### What Blackmagic Does Not Establish Here

The manual describes recording behavior, not a normative JSON schema. `sources`, `_index_`, sparse merging, event ordering, and the `CAM N` pairing convention are documented from this project's observations in [drp-format.md](drp-format.md). Do not elevate them into a promise about every firmware. Custom source display names are independent of file names. Renaming an individual ISO file without updating its DRP reference breaks discovery; renaming the enclosing folder does not.

## Apple: How the Import Is Represented

| Official source | Relevant contract | Where it matters here |
| --- | --- | --- |
| [Describing Final Cut Pro Items in FCPXML](https://developer.apple.com/documentation/professional-video-applications/describing-final-cut-pro-items-in-fcpxml) | Resources describe assets; browser clips and a project can share those assets. FCPXML is interchange, not a complete native library. | `build_fcpxml`, `_Resources`; create browser entries explicitly. |
| [Multicam Media](https://developer.apple.com/documentation/professional-video-applications/multicam-media) | `media/multicam` contains angles; `mc-clip` references it; `mc-source` selects picture, sound, or both. | Keep the soundtrack angle stable across picture cuts. |
| [FCPXML reference](https://developer.apple.com/documentation/professional-video-applications/fcpxml-reference) | Entry point for the interchange vocabulary. | Consult alongside the installed, versioned DTD. |
| [Use XML to transfer projects](https://support.apple.com/guide/final-cut-pro/verdbd66ae/mac) | File → Import → XML imports the items described by the document. | Quick Action opens the generated file in Final Cut. |
| [Import from your Mac or storage device](https://support.apple.com/en-au/guide/final-cut-pro/ver418155a4/mac) | Copying media and linking to it have different storage consequences. | Explain media management before users disconnect an SSD. |

Apple's item-description example says omitting an event creates a date-named event; it does not target the selected event. Our 12.4 import experiment also shows that matching event and clip names can invoke Keep Both / Replace; Keep Both adds numbered copies within the existing event. Omitting FCP-owned UIDs does not disable name matching. See the visibility entry in [validation](validation.md). The example also says import preferences govern copying versus linking media. Our converter only writes references and does not copy footage itself. Do not promise that selecting an event, or matching its name, identifies that existing event.

The item-description and multicam articles were read using Apple's `.md` versions (append `.md` to the article URL) when the HTML required JavaScript. Some examples demonstrate older XML versions; do not paste their syntax into a 1.10 writer without validation.

### Multicam Audio and AFV

Apple's [multicam editing tips](https://support.apple.com/guide/final-cut-pro/multicam-editing-tips-verb1160b2d/mac) explicitly support enabling audio from multiple angles in the Audio inspector. Its [angle switching guide](https://support.apple.com/guide/final-cut-pro/cut-and-switch-camera-angles-ver23c76c9c/mac) documents Option-Command-click to add or remove audio in audio-only mode. A single active soundtrack is this converter's initial output policy, not a Final Cut limit. These vendor instructions were checked on 2026-10-21; no new native multiple-angle audio test was performed for this documentation update.

Blackmagic's [Audio Page description](https://www.blackmagicdesign.com/products/atemmini/software) describes per-input on/AFV controls, levels, processing, and the final mixed program output. The converter's selected raw WAV does not recreate that mixer. Keeping the recorded program mix and constructing an editable new mix are separate workflows. The **ATEM live mix** soundtrack choice uses a dedicated audio-only angle referencing the Program MP4, or an audio-bearing selected ISO. The optional Program picture angle remains independent. WAV selection remains the default when available.

### DTD Validation Is Necessary, Not Sufficient

The local test uses the FCPXML 1.10 DTD installed in Final Cut Pro's Interchange framework. That validates vocabulary and structure, not audible sync or importer behavior. The connected-WAV compound wrapper and butt-joined transition layout are **project round-trip observations**, not conclusions from generic examples. Preserve them under [AGENTS.md](../AGENTS.md). Changing them requires a new import/export experiment in Final Cut and a dated validation entry.

## Timing and Evidence Boundaries

- Frames, rational seconds, and WAV samples are distinct units. Preserve `Fraction` until XML serialization. At 59.94 use `60000/1001`, not decimal `59.94`.
- Drop-frame skips timecode labels, not recorded frames. Midnight wraps after the count of frames in a drop-frame day, not `round(fps) * 86400`.
- A resource's `start` is its source clock. A clip's `offset` places it in its parent. Copying a BWF timestamp into `start` alone does not synchronize a later-starting file.
- The current layout assumes native files share a recording start. Mismatched starts and short files produce warnings; automatic offset correction, waveform sync, and arbitrary external recorder alignment are not implemented.
- [EBU Tech 3285](https://tech.ebu.ch/docs/tech/tech3285.pdf) is the reference for Broadcast Wave metadata; use `TimeReference` in sample units, not frames.

## Changing the Converter

Keep comments near decisions that are easy to undo by accident: source clock versus placement, sparse state semantics, the compound wrapper and shared browser reference, zero-relative multicam angle offsets, the fixed audio angle, rational timing, and exclusive output creation. Explain why, and link to the evidence. Add a synthetic regression for every reproducible defect and run the checks in [CONTRIBUTING.md](../CONTRIBUTING.md). Record whether a result is a unit test, a DTD check, or a real Final Cut import or export; none substitutes for another. Keep real recordings and downloaded reference material out of Git. Update this guide when a vendor claim changes, and update validation only for checks that were performed.
