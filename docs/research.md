# Research and prior work

Checked October 21, 2026. These are original vendor/project sources, not an exhaustive market survey. No source code from these projects was copied into this implementation.

## Existing solutions

[ATEM TO FCP](https://www.marcobucci.eu/atem-to-fcpxml.html), by Marco Bucci, directly addresses native ATEM DRP conversion. Its official page describes multicam and flattened timelines, WAV audio choices, transitions, keys, effects, replacement camera media, and other advanced workflows. It is the closest existing product found. The page links to a Mac App Store listing. Its advertised feature coverage is broader than this utility; those claims were read, not independently tested. Price and regional availability were not verified.

[ATEM Exporter usage documentation](https://github.com/latenitefilms/ATEMExporter/blob/main/docs/how-to-use.md), by LateNite Films, describes connecting to the switcher over Ethernet and logging camera changes during production. It exports program-cut or multicam FCPXML. The public repository is its documentation site; its MIT license does not establish that the app's complete conversion engine is open source. Its documented workflow differs from converting a DRP already recorded on an SSD.

The focused search did not establish a maintained, complete open-source drop-in implementation of this exact SSD/DRP-to-Final-Cut workflow. That is a search limitation, not a claim none exists. A small open-source utility remains useful for people who want a transparent local script and can accept the narrower scope.

## Format authorities

[Apple's FCPXML Document Type Definition](https://developer.apple.com/documentation/professional-video-applications/document-type-definition) publishes the FCPXML 1.10 schema used by this utility. Local schema validation uses the DTD bundled with the installed Final Cut app; it is not redistributed here. Later Final Cut versions have newer XML revisions, but 1.10 provides the structures needed for this first version.

[EBU Tech 3285: Broadcast Wave Format](https://tech.ebu.ch/docs/tech/tech3285.pdf) specifies the BEXT sample-count time reference. Preserving it proved necessary during native Final Cut import: zero-based WAV in-points caused rejected nested audio edits, while correct BWF source origins imported successfully.

## Implementation evidence

The supplied ATEM recordings contained JSON event logs under the `.drp` extension, including a header with source files and video mode, followed by sparse timed state updates. This is an observed input format, not a guarantee about every switcher or firmware. Real source DRPs and media remain local; public tests use invented metadata.

The simple approach is direct event-log translation with ffprobe metadata inspection, WAV-aware camera compounds, and native multicam output. Reusing rendered program picture for difficult effect intervals keeps the first version bounded while preserving their appearance. It does not provide editable native effect parameters.
