# Security and Privacy

## Privacy

The converter runs entirely on your Mac. It makes no network requests, reads only files inside the selected recording folder (media paths in the `.drp` that point outside it are refused), never modifies the recording, and writes one `.fcpxml` next to the `.drp`. The `.drp` is parsed with a 16 MiB size limit, and MP4 and WAV parsing reads headers only.

Generated `.fcpxml` files contain absolute paths to your media. Treat them as private.

## Supported versions

Security fixes are made in the latest release only.

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/jeffalldridge/atem-iso-to-fcpxml/security/advisories/new) rather than in a public issue. Do not include recordings, `.drp` files, or personal paths; a description or a synthetic reproduction is enough.
