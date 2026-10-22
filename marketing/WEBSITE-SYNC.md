# Website Claims Contract

The converter's [product.yml](product.yml) records the quality-finishing claim. Check `make_plan` and `build_fcpxml` in `atem_iso_to_fcpxml.py` before changing what source media the output uses. Blackmagic's linked technical specifications establish recording bitrate behavior, not the converter's hardware coverage.

The corresponding Tent Studios files are:

- `src/data/projects.ts`: project-card description.
- `src/content/projectDocs/atem-iso-to-fcpxml.md`: feature explanation and its recording-quality qualification.
- `src/content/news/atem-iso-to-final-cut-multicam.md`: launch article.
- `docs/marketing/drafts/2026-10-21-atem-iso-to-fcpxml-show-and-tell.md`: outreach draft.
- `docs/marketing/social/social-posts.csv`: ATEM social entries; regenerate the scheduling workbook with `scripts/build-social-calendar.py` in the site repository.

Update the facts here before transcribing a changed capability to the site. Do not describe every program recording as a fixed low bitrate, every ISO as 70 Mb/s, or the converter as enhancing or re-encoding footage. Native Program stand-ins remain limited by their source recording. Drafts describing unreleased features must be checked against the published installer before posting.
