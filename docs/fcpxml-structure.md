# What the Converter Writes, and Why

FCPXML lets you describe the same edit in several ways. Final Cut Pro accepts only some of them, and it often degrades the others silently with a warning in the import sheet. The shapes below were established by importing into Final Cut Pro 12.4 and exporting the result as XML again (Final Cut writes FCPXML 1.14; the converter writes 1.10, which Final Cut 10.6 and later read).

## Resources

- One `format` for the recording, named after Apple's presets when the size and rate match (`FFVideoFormat1080p60`, `FFVideoFormat1080p5994`, …).
- One `asset` per MP4 with `start` set to its embedded timecode and `duration` to its frame count, declaring both video and audio because Final Cut rediscovers the AAC track anyway.
- One `asset` per WAV with `start` set to the **Broadcast Wave time reference**. Final Cut reads that reference from the file; if the XML disagrees, every clip that uses the WAV is offset or rejected.
- Stills: a `duration="0s"` asset with a `FFVideoFormatRateUndefined` format carrying the pixel size.
- A `Cross Dissolve` effect resource (`FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265`) when any dissolve is used.

## The Multicam

```xml
<media id="r11" name="Live Show Multicam">
  <multicam format="r1" tcStart="36000s" tcFormat="NDF">
    <mc-angle name="Camera 1" angleID="input-1">
      <ref-clip ref="r12" name="Camera 1" offset="36000s" start="0s" duration="2798s"/>
    </mc-angle>
    <mc-angle name="Media Player 1" angleID="still-8-logo">
      <clip name="Media Player 1" offset="36000s" start="0s" duration="2798s" format="r1" tcFormat="NDF">
        <video ref="r6" offset="0s" start="0s" duration="2798s"/>
      </clip>
    </mc-angle>
    <mc-angle name="MIC 1" angleID="audio-live-show-mic-1">
      <asset-clip ref="r8" name="MIC 1" offset="36000s" start="36000s" duration="2798s" audioRole="dialogue"/>
    </mc-angle>
  </multicam>
</media>
```

`tcStart` is the ATEM's master timecode, so the multicam shows the same time-of-day timecode as the camera files.

### Camera Angles Are Compound Clips

```xml
<media id="r12" name="Camera 1">
  <sequence format="r1" duration="2798s" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
    <spine>
      <clip name="Camera 1" offset="0s" start="0s" duration="2798s" format="r1" tcFormat="NDF">
        <video ref="r2" offset="0s" start="36000s" duration="2798s"/>
        <asset-clip ref="r3" lane="-1" offset="0s" name="Live Show CAM 1" start="36000s" duration="2798s" audioRole="dialogue"/>
      </clip>
    </spine>
  </sequence>
</media>
```

The `video` component takes only the picture of the MP4 and the connected `asset-clip` supplies the WAV. The wrapper is required: putting that same `clip` directly inside `mc-angle`, or a `sync-clip` with `sync-source` elements, imports with the warning "Anchored items were ignored because this item does not support them", and the angle ends up with the MP4's AAC audio. The compound clip round-trips intact.

## The Timeline

```xml
<project name="Live Show Live Edit">
  <sequence format="r1" duration="2798s" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
    <spine>
      <mc-clip ref="r11" name="Live Show Multicam" offset="0s" start="36000s" duration="8143/60s">
        <mc-source angleID="input-1" srcEnable="all"/>
      </mc-clip>
      <transition name="Cross Dissolve" offset="2032/15s" duration="1/2s">
        <filter-video ref="r10" name="Cross Dissolve"/>
      </transition>
      <mc-clip ref="r11" name="Live Show Multicam" offset="8143/60s" start="250847/6s" duration="31/4s">
        <mc-source angleID="still-8-logo" srcEnable="video"/>
        <mc-source angleID="input-1" srcEnable="audio"/>
      </mc-clip>
```

- Every clip names a video angle and the main audio angle. When they are the same angle, one `mc-source srcEnable="all"` is used.
- Adjacent clips butt-join. A transition of *n* frames gets `offset = cut − n/2` and sits between them; Final Cut pulls the handles from the continuous ISO media. Odd ATEM transition lengths are rounded up to an even frame count so the cut lands on a frame. This matches what Final Cut exports for its own dissolves; the DTD comment describing clip overlap does not.
- Final Cut adds `<filter-audio name="Audio Crossfade"/>` to every transition on import. With the same audio angle on both sides the measured output gain through the dissolve is flat (−0.1 dB, the AAC export's own loss), so the soundtrack is untouched.
- Sections where the ATEM showed something the angles cannot reproduce (keys, fade to black, generators) are `mc-clip`s on a `Program` angle holding the ATEM program recording, each with a marker. If there is no program recording they become `gap`s with markers.
- The sequence starts at `0s` so exports begin at zero; the multicam keeps time-of-day timecode.

## Browser Items

The event holds the multicam clip, the project, and an `asset-clip` for every MP4 and WAV so the raw files are visible. Final Cut creates an event with the name given (`--event`, default the folder name). A file with no event element lands in an event named after today's date; Final Cut does not import into the selected event.

## Things That Were Tried and Do Not Work

| Attempt | Result in Final Cut Pro 12.4 |
| --- | --- |
| `clip` with `video` + connected WAV directly in `mc-angle` | Connected audio dropped with a warning |
| `sync-clip` in `mc-angle` | Connected audio dropped with a warning |
| `audioStart`/`audioDuration` equal to the clip range, to suppress the audio crossfade | Attributes discarded; crossfade still added (and it turned out not to matter) |
| MP4 asset declared video-only | Final Cut re-adds the AAC track on import (found in 0.1.0) |
