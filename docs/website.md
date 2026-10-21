# The Website

The project page is static HTML and CSS in `docs/site/`, published to GitHub Pages by `.github/workflows/pages.yml` on pushes to `main`. It uses no JavaScript, analytics, third-party fonts, or framework.

## Content

- Keep the dark charcoal and orange palette, system typography, and a single primary download action.
- State only what has been verified. Real-media testing covers ATEM Mini Pro ISO recordings at 1080p60 in Final Cut Pro 12.4; other models and frame rates are described as untested. See [validation.md](validation.md).
- Keep answers visible. Use headings and dividers, not dropdowns or accordions.
- The download button links to `releases/latest/download/ATEM-ISO-to-FCPXML.dmg`, so the release workflow must keep that asset name ([releasing.md](releasing.md)). The page states the download size (about 3 MB); recheck it when the disk image changes.
- The FAQ in the page and its `FAQPage` JSON-LD must match exactly.
- No invented reviews, ratings, or search-ranking claims.

## Metadata and Files

The page has a canonical URL, a description, Open Graph and Twitter card tags with a 1200 × 630 PNG, a sitemap, and linked JSON-LD for the site, page, image, application, source code, and FAQ. Schema correctness does not guarantee rich results.

`llms.txt` is a plain-text navigation aid for tools that read it. It is not a crawler policy and does not affect search ranking.

A `robots.txt` only takes effect at the root of a host, and this project site is served below `jeffalldridge.github.io/atem-iso-to-fcpxml/`, so it carries none. Submit `sitemap.xml` in Search Console if you want it indexed.

Regenerate the social card with `swift scripts/build_social_card.swift` and the icons with `make site-icons` when their source changes.

## Checks

```sh
python3 -m unittest discover -s tests -p test_site.py -v
```

These tests verify canonical and social metadata, declared image sizes, real PNG alpha in the screenshots, local links and accessibility references, the schema graph, exact FAQ parity, the installer link, and the sitemap. They do not verify rendering, accessibility with a screen reader, indexing, or social-platform previews; check those in a browser when the page changes.

## Screenshots

The three window screenshots in `docs/site/images/` come from the real app, using a synthetic "Live Show" recording with generic input names. No real footage, names, or paths appear in them.

1. `01-open.png`: the empty window.
2. `02-choices.png`: the live switch, cameras, soundtrack, an extra audio angle, and the save destination.
3. `03-done.png`: the finished conversion.

They are 1800 × 1308 lossless RGBA PNGs with genuinely transparent window corners. Capture with `screencapture -l <CGWindowID> -o -x file.png`; the window id comes from the window list, and `-o` omits the shadow that would otherwise be flattened into the image. Keep the window at its default size so the page's proportions hold. Never convert a JPEG, and never add CSS borders, rounded corners, or box shadows around a screenshot. Recapture whenever the window changes.

The icons in the hero's flow row were extracted from the installed applications and resized to 128 pixels with `sips`: Final Cut Pro's `AppIcon.icns` and `XML.icns` (`final-cut.png`, `fcpxml.png`), and DaVinci Resolve's `Resolve.icns` and `ResolveProject.icns` (`resolve.png`, `drp.png`). Final Cut Pro and its artwork belong to Apple, and DaVinci Resolve and its artwork belong to Blackmagic Design. They identify applications and file types, are not covered by this project's MIT license, and do not indicate affiliation or endorsement.
