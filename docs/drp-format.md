# The ATEM `.drp` Switcher Log

Blackmagic documents the `.drp` only as "a DaVinci Resolve project file". In practice it is a newline-delimited JSON log of the switcher state during the recording, written by the ATEM firmware. DaVinci Resolve knows how to read it; nothing else officially does. This page records what real ATEM Mini Pro ISO recordings (firmware from mid and late 2026) contained. Field names are quoted exactly; values are invented.

## Layout

Line 1 is the header, a complete snapshot at the moment recording started. Every following line is a sparse patch: only the keys that changed, each with the `masterTimecode` at which they changed. Arrays are keyed by `_index_`, and a patch to an array element contains only the changed keys of that element.

```json
{"version":1,"masterTimecode":"10:00:00:00","videoMode":"1080p60","sources":[...],"mixEffectBlocks":[...],"downstreamKeys":[...],"recordingId":"00a1b2c3"}
{"masterTimecode":"10:00:05:00","mixEffectBlocks":[{"source":2,"_index_":0}]}
{"masterTimecode":"10:00:20:00","mixEffectBlocks":[{"transitionActive":true,"transitionPosition":0.0,"_index_":0}]}
{"masterTimecode":"10:00:20:30","mixEffectBlocks":[{"source":1,"transitionActive":false,"transitionPosition":1.0,"_index_":0}]}
{"masterTimecode":"10:46:38:00","mixEffectBlocks":[{"onAir":false,"_index_":0}]}
```

If you stop and start recording under the same name the ATEM may append another header line, so a file can hold several sessions.

## Header Fields

| Key | Meaning |
| --- | --- |
| `version` | `1` on every log seen so far. |
| `masterTimecode` | Switcher timecode when the recording started, `HH:MM:SS:FF`. The ATEM runs time-of-day timecode by default; the embedded MP4 timecode track and the Broadcast Wave time reference of every WAV match this value exactly. |
| `videoMode` | The switcher standard, e.g., `1080p60`. Only integer rates have been seen in the wild; the converter also accepts `1080p5994`, `1080p29.97` and similar spellings and, in any case, trusts the MP4's own frame rate. |
| `sources` | Every input the switcher could put on air; see below. |
| `mixEffectBlocks` | One entry (`_index_` 0) on the Mini range. |
| `downstreamKeys` | One entry on the Mini range. |
| `recordingId` | Eight hex characters; also stored in the MP4s as `com.blackmagic-design.camera.timelineID`. |

### `sources`

| `type` | Example | Notes |
| --- | --- | --- |
| `Color` | `{"name":"Black","type":"Color","color":{"h":0,"s":0,"l":0},"_index_":0}` | Index 0 is Black. Color generators `Color 1`/`Color 2` follow the cameras. |
| `Video` | `{"name":"Camera 1","type":"Video","volume":"ATEM SSD","projectPath":"Live Show","file":"Video ISO Files/Live Show CAM 1.mp4","startTimecode":"10:00:00:00","_index_":1}` | `name` is the input label from ATEM Software Control, so it can be anything (`Computer`, `Stage`). `file` is relative to the recording folder and is what the converter uses; `volume` and `projectPath` are where the folder was when recorded and are ignored, so you can rename or move the folder. |
| `ColorBars` | `{"name":"Color Bars","type":"ColorBars","_index_":5}` | |
| `Still` | `{"name":"Media Player 1","type":"Still","file":"Video ISO Files/Media Files/logo.png","startTimecode":"00:00:00:00","_index_":8}` | The still loaded in the media player when recording started. |

Input numbering: 1–4 on an ATEM Mini, 1–8 on the Extreme and HD8 models.

### `mixEffectBlocks[0]`

| Key | Meaning |
| --- | --- |
| `onAir` | `true` while recording. The final line sets it to `false`; its timecode minus `masterTimecode` equals the recording length. |
| `source` | The `_index_` of the program source. |
| `transitionActive`, `transitionPosition` | An auto or T-bar transition in progress. The log writes `true`/`0.0` when it starts and `false`/`1.0` together with the new `source` when it completes. Intermediate T-bar positions are not logged. |
| `transitionType` | `Mix` on newer firmware; absent on older logs (treated as Mix). Other values are `Dip`, `Wipe`, `DVE`, `Stinger`. |
| `transitionBackground`, `transitionWipeParameters`, `transitionDVEParameters` | What the next transition would affect and its settings. |
| `fadeToBlack`, `ftbSource` | `Inactive` normally. |
| `upstreamKeys[0]` | `keyType`, `onAir`, `fillSource`, `keySource`, fly-key position and size. |

### `downstreamKeys[0]`

`onAir`, `isTied`, `fillSource`, `keySource`, `faderState` (`Idle` while not transitioning).

## What the Converter Does with It

1. Replays the patches onto the header to get the full state between every pair of events.
2. Classifies each interval: a camera or still that is on air cleanly becomes an angle; a key, fade to black, generator, unknown source, or deselected input becomes a stretch of the program recording.
3. Resolves transition intervals against their neighbors: a change of picture becomes a Cross Dissolve (or a cut or program stretch, depending on `--transitions`); a transition that ends on the same picture is ignored.
4. Clamps everything to the frame count of the program MP4 and warns if the log disagrees by more than two frames.

## Companion Files

```
Live Show/                        ← record folder, named after the record palette
├── Live Show.drp                 ← this log
├── Live Show.mp4                 ← program recording (H.264 ~6–7 Mb/s, AAC program mix, timecode track)
├── Video ISO Files/
│   ├── Live Show CAM 1.mp4       ← per-input ISO (H.264 up to ~70–120 Mb/s, AAC *program* mix, timecode track)
│   ├── …
│   └── Media Files/logo.png           ← media pool graphics that were used
└── Audio Source Files/
    ├── Live Show CAM 1.wav       ← each input's own audio, 24-bit 48 kHz, unprocessed, with a bext time reference
    ├── …
    ├── Live Show MIC 1.wav
    └── Live Show MIC 2.wav
```

The WAV with the same stem as an ISO MP4 is that camera's audio. WAVs without a matching MP4 are the switcher's own audio inputs.
