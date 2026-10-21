# Website Images

The images live in `docs/site/images/`. This note is kept outside the published site.

The screenshots are lossless Retina window captures of the Mac app (the revised workspace after 1.1.0, October 21, 2026) showing a synthetic "Live Show" recording made from generated media headers, with generic input names. No real footage, names, or paths appear in them.

1. `01-open.png`: the empty window that accepts a dropped recording.
2. `02-choices.png`: the live switch with its dissolves, cameras, a MIC 1 soundtrack, one extra audio angle, and the save destination.
3. `03-done.png`: the completed conversion with Open in Final Cut Pro.

They are 1800 × 1308 RGBA PNGs with genuinely transparent window corners. Capture with `screencapture -l <CGWindowID> -o -x file.png` (`-o` leaves out the shadow, which would otherwise be flattened into the image; the window id comes from the app's window list). Never convert a JPEG, never add CSS borders, radii, or box shadows, and keep the window at its default size so the page's proportions hold. `tests/test_site.py` checks that the files are PNG, RGBA, match the dimensions the page declares, and have a transparent corner pixel. Recapture whenever the window changes.

The PNG icons in the hero's flow row were extracted from the installed application resources and resized to 128 pixels with `sips`:

- `final-cut.png`: Final Cut Pro, `AppIcon.icns`.
- `fcpxml.png`: Final Cut Pro, `XML.icns`.
- `resolve.png`: DaVinci Resolve, `Resolve.icns`.
- `drp.png`: DaVinci Resolve, `ResolveProject.icns` (the registered DRP document artwork).

Final Cut Pro and its artwork belong to Apple; DaVinci Resolve and its artwork belong to Blackmagic Design. They identify applications and file types, are not covered by this project's MIT license, and do not indicate affiliation or endorsement.
