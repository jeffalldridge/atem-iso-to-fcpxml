# Architecture

The runtime is one standard-library Python module plus ffprobe. The macOS installer only copies it and generates a Finder Quick Action; the conversion engine has no dependency on Finder, Resolve, or an AI service.

## Conversion pipeline

1. Read a size-limited, version-1 ATEM newline-delimited JSON DRP. Reject Resolve archives and multi-session/source-change logs.
2. Resolve source files relative to the selected DRP. The recorded volume and projectPath are historical metadata. Check canonical paths, including symlink targets, stay within the recording folder.
3. Inspect program and selected ISO/WAV media with ffprobe. Use exact stream durations, rates, and dimensions. The program stream establishes the recording's frame count.
4. Merge sparse `_index_` event patches without dropping unchanged nested state. Normalize midnight and drop-frame labels. Emit contiguous picture intervals with integer frame boundaries.
5. For straight camera/still sections, use the ISO or still. For transitions, keys, fades, and color generators, use the program picture over the corresponding interval and record the reason. Stop on missing required media instead of quietly substituting it.
6. Parse Broadcast WAV `bext` TimeReference directly as a 64-bit sample count. Final Cut honors this origin even when ffprobe omits the tag because other BEXT fields are empty. Resource starts and every WAV clip in-point must preserve that value. Recording-local offset zero and source timecode zero are different concepts.
7. Serialize FCPXML 1.10 with exact rational seconds and encoded file URLs. Finish conversion before writing anything. Create outputs exclusively and never overwrite an existing path or symlink.

## Final Cut structure

Each camera is a reusable media/sequence compound. Its primary clip contains an explicit `video` component referring to the ISO MP4 and a connected `asset-clip` referring to the matching WAV. Explicit video components prevent Final Cut from reintroducing embedded AAC when it discovers the MP4's actual streams during import.

The multicam references those compounds. Optional microphones are audio-only angles. The browser clip defaults to the selected main WAV's audio angle. The live timeline uses video-only multicam segments and a separate continuous main WAV connected to the first picture segment; camera changes therefore leave the main soundtrack alone. Program fallback segments contain explicit video components, so their embedded audio is excluded too.

Individual WAV browser clips make source audio available for editing. The generated report describes fallback ranges and selection; it is private because filenames can identify a recording.

## Verification boundaries

Unit tests verify synthetic parsing, rational timing, WAV origins, media selection, path safety, and output protection. Apple DTD validation verifies XML grammar. Native Final Cut import and re-export verify that the application retains the intended component structure. None of these alone establishes lip sync, perceived audio quality, full visual equivalence, or export performance.
