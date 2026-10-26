# Security and Privacy

## Privacy

The converter runs entirely on your Mac. The conversion engine makes no network requests, reads only files inside the selected recording folder (media paths in the `.drp` that point outside it are refused), never modifies the recording, and writes one `.fcpxml` next to the `.drp`. The `.drp` is parsed with a 16 MiB size limit, and MP4 and WAV parsing reads headers only.

Generated `.fcpxml` files contain absolute paths to your media. Treat them as private.

## Supported versions

Security fixes are made in the latest release only.

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/jeffalldridge/atem-iso-to-fcpxml/security/advisories/new) rather than in a public issue. Do not include recordings, `.drp` files, or personal paths; a description or a synthetic reproduction is enough.

## Software updates

The Mac app uses Sparkle 2 for optional update checks and installation from GitHub Releases. Ed25519 signatures protect the feed and update archive, with archive verification required before extraction. Developer ID signing and notarization remain part of release packaging. System profiling is disabled; update requests never include recording contents or paths. The private update-signing key belongs only in the maintainer’s Keychain and the protected release environment, never in source or release assets.
