# Website maintenance and review

Reviewed 2026-10-21. The website remains static HTML and CSS on GitHub Pages: no runtime JavaScript, analytics, third-party fonts, framework or build dependency. `scripts/build_social_card.swift` is an optional macOS development tool for regenerating the committed PNG, not a converter or deployment dependency.

## Design and content

Keep the dark charcoal/orange palette, system typography, clear spacing and a single primary download action. Keep captions focused on what the tool does; avoid unnecessary explanatory disclaimers. Keep answers and command-line instructions visible by default, using headings and dividers rather than dropdowns or accordions. This follows the owner’s preference to avoid extra steps just to read information. Use balanced heading wraps, readable paragraph measures and a consistent type scale. Keep “Final Cut” together in the hero. Preserve keyboard focus styles, table headings and the skip link. Long filenames and command blocks must not widen mobile layouts.

The compatibility statement is deliberately narrower than hardware marketing: real-media verification is Mini Pro ISO, 1080p60, Final Cut Pro 12.4. Do not turn synthetic coverage into a claim of verified hardware support. The download links target the latest release page; no unreleased version is advertised in metadata.

## Search and agents

The page includes a canonical URL, description, Open Graph and large-image Twitter card metadata, a 1200×630 PNG, sitemap, and connected JSON-LD entities for WebSite, WebPage, ImageObject, SoftwareApplication, SoftwareSourceCode and FAQPage. FAQ questions and answers must match the HTML exactly. No fabricated reviews or ratings are included. Schema correctness is not a guarantee of rich results.

`llms.txt` is a linked project navigation aid, not a crawler policy, ranking signal, or substitute for the visible page. [Google's AI search guidance](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide) says special AI files are not required for inclusion. Keep information useful and discoverable through ordinary HTML links.

[Robots files belong at the host root](https://developers.google.com/crawling/docs/robots-txt/create-robots-txt). On this project site, `/atem-iso-to-fcpxml/robots.txt` does not govern crawling. The host-root `https://jeffalldridge.github.io/robots.txt` returned 404 during review, not a blocking directive. This repository cannot set a host-wide policy for the user's other projects. The sitemap can be submitted directly in Search Console by the property owner; do not claim this has been done.

## Checks and evidence

- The existing public page was inspected using Firecrawl raw HTML and links; it returned HTTP 200. Its missing social image, FAQ/content mismatch and invalid figure label reference were corrected locally.
- The latest-release destination returned HTTP 200. New technical-reference documents and social assets require publication before their public links become available.
- The final local page was visually reviewed at 1280px and 390px widths; document width also matched the 320px viewport. FAQ answers and command-line instructions remain visible without disclosure controls.
- The screenshot in ignored `local/site-review/typography.jpg` records the refined desktop hero. This is browser emulation, not physical-device or VoiceOver acceptance.
- `tests/test_site.py` checks canonical/social consistency, PNG dimensions, local links and accessibility references, schema graph references, exact FAQ parity, sitemap and assistant reference. The Pages workflow runs these before uploading the site.
- No Search Console indexing, ranking, Core Web Vitals, external rich-result validator, social-platform cache refresh, or post-deployment checks were performed. Do not report those as passed.

Run `python3 -m unittest discover -s tests -p test_site.py -v` after website edits. Regenerate the social image with `swift scripts/build_social_card.swift` if its copy or styling changes. Keep its committed image synchronized with metadata. The Pages workflow deploys `docs/site/` on relevant pushes to main; source edits alone are not a deployment.
