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
      <ref-clip ref="r12" name="Camera 1 - ISO + WAV" offset="0s" start="0s" duration="2798s"/>
    </mc-angle>
    <mc-angle name="Media Player 1" angleID="still-8-logo">
      <ref-clip ref="r13" name="Media Player 1 - Still" offset="0s" start="0s" duration="2798s"/>
    </mc-angle>
    <mc-angle name="MIC 1" angleID="audio-live-show-mic-1">
      <asset-clip ref="r8" name="MIC 1" offset="0s" start="36000s" duration="2798s" audioRole="dialogue"/>
    </mc-angle>
  </multicam>
</media>
```

`tcStart` is the ATEM's master timecode, so the multicam shows the same time-of-day timecode as the camera files. **Angle contents use offsets relative to the multicam origin (`0s`), not `tcStart`.** The multicam's browser and timeline instances still use `start=tcStart` (plus the edit offset). Adding `tcStart` to the angle offsets again makes Final Cut report hours of excess duration and display blank angle timelines, even though project playback works. The 2026-10-21 visibility round trip in [validation](validation.md) supersedes the original angle-offset example.

### Camera Angles Are Compound Clips

```xml
<media id="r12" name="Camera 1 - ISO + WAV">
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

The `video` component takes only the picture of the MP4 and the connected `asset-clip` supplies the WAV. The wrapper is required: putting that same `clip` directly inside `mc-angle`, or a `sync-clip` with `sync-source` elements, imports with the warning "Anchored items were ignored because this item does not support them", and the angle ends up with the MP4's AAC audio. The compound clip round-trips intact. A camera without a WAV uses a native `asset-clip` directly in its angle, retaining the MP4 picture and compressed audio. A connected `audio` under a plain angle `clip` is also dropped with the anchored-item warning; the native asset clip avoids it. The program picture angle uses `clip/video` to keep only its picture. The **ATEM live mix** soundtrack uses a separate `mc-angle` with a native `asset-clip srcEnable="audio"`, referencing the Program MP4 when it has audio, otherwise an audio-bearing selected ISO. It starts at source timecode with angle offset `0s`. The audio and picture angles share the same MP4 asset resource and browser source; selecting live mix does not force a Program picture angle. With no WAVs, this becomes the automatic soundtrack.

### Media Player Angles Are Shared Compounds

A still angle references a `media/sequence` compound named “Media Player 1 - Still.” Its spine contains the same `clip/video` still structure described above, using a zero-duration asset and rate-undefined format. This makes the graphic editable through the same browser-compound workflow as the cameras, while preserving the still representation Final Cut requires. The browser compound and multicam angle reference the same media resource.

The original image also has a browser `clip/video` referencing the same asset, named after the image file without its extension. Its clip duration spans the recording; the underlying image asset retains `duration="0s"`. Final Cut may normalize this browser clip to an `asset-clip` and assign a default image source timecode when exporting. Source identity is established by the shared asset reference, not by copying that normalized browser timecode into the compound.

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
- Sections where the ATEM showed something the angles cannot reproduce (keys, fade to black, generators) are `mc-clip`s on a `Program` angle holding the ATEM program recording, each with a marker. In 1.0.0, missing program recordings produced `gap`s with markers. Since 1.0.1, the first selected camera stands in instead, retaining the soundtrack and marker. The missing-program fallback has synthetic and DTD coverage; it has not had a separate native Final Cut playback test.
- The sequence starts at `0s` so exports begin at zero; the multicam keeps time-of-day timecode.

## Browser Items

The event holds the multicam clip, the project, a browser `ref-clip` for each camera/WAV or Media Player compound, and a browser clip for every selected MP4, WAV, and still image. Source browser items are deduplicated by resolved path. Browser compounds are named “Camera 1 - ISO + WAV” or “Media Player 1 - Still” using the input label. Generated separators are plain ASCII ` - `; source names and user labels retain their original characters. Their `ref` is the **same media resource** referenced by the multicam angle, with `start="0s"` and the compound duration; they are not separate copies of its contents. Opening one exposes the video and connected WAV. Edits propagate into the multicam and its project uses, as verified by a browser compound edit and event XML export.

```xml
<ref-clip ref="r12" name="Camera 1 - ISO + WAV" start="0s" duration="2798s"/>
```

The writer does not assign FCP-owned event or media UIDs. Final Cut assigns those on import. Matching event and clip names can invoke Final Cut's **Keep Both / Replace** dialog: in 12.4, Keep Both retains the event and adds numbered clip/project copies, while a distinct event name imports separately. Omitting UIDs does **not** guarantee a new event on every import or bypass name matching. The converter cannot inspect an existing library; it preserves readable event names and leaves conflict resolution to Final Cut.

Final Cut creates an event with the name given (`--event`, default the folder name). A file with no event element lands in an event named after today's date; Final Cut does not import into the selected event.

A conversion writes exactly one `project` and one browser `mc-clip`. They keep the established names “Show Live Edit” and “Show Multicam.” A legacy import named “Show — Live Edit” is a separate existing item; importing the current name does not replace or remove it. Compare project creation dates and contents before removing an older import. The converter never opens or edits a library itself.

## Things That Were Tried and Do Not Work

| Attempt | Result in Final Cut Pro 12.4 |
| --- | --- |
| `clip` with `video` + connected WAV directly in `mc-angle` | Connected audio dropped with a warning |
| `sync-clip` in `mc-angle` | Connected audio dropped with a warning |
| `audioStart`/`audioDuration` equal to the clip range, to suppress the audio crossfade | Attributes discarded; crossfade still added (and it turned out not to matter) |
| MP4 asset declared video-only | Final Cut re-adds the AAC track on import (found in 0.1.0) |
