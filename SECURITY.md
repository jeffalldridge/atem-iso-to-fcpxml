# Security and privacy

The converter runs entirely on your Mac. It makes no network requests, reads only files inside the selected recording folder (paths in the `.drp` that point outside it are refused), never modifies the recording, and writes one `.fcpxml` next to the `.drp`. The `.drp` is parsed with the standard JSON module with a 16 MiB size limit; MP4 and WAV parsing reads headers only.

Generated `.fcpxml` files contain absolute paths to your media. Treat them as private.

To report a vulnerability, use GitHub's private vulnerability reporting on this repository. Please do not include recordings or personal paths in a public issue.
