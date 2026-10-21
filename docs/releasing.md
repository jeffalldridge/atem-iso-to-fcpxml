# Releasing the utility

The deliverables are a single Python converter and its generated Finder Quick Action. Keep changes reviewable and do not include a recording, downloaded vendor manual, generated FCPXML, or local test library in a release.

## Before tagging

1. Review `git diff` and `git status`. Check that `AGENTS.md` and the documented Final Cut structures were respected.
2. Set the same release version in `atem_iso_to_fcpxml.py` and `pyproject.toml`. The website intentionally omits a version field so its evergreen download page cannot advertise an unreleased version. Move the Unreleased changelog notes under that version and date.
3. Run:

   ```sh
   python3 scripts/build_quick_action.py
   python3 -m unittest discover -s tests -v
   python3 scripts/build_quick_action.py --check
   git diff --check
   ```

4. On a Mac with Final Cut, confirm the DTD test actually ran rather than skipped. Linux CI cannot establish Final Cut compatibility.
5. Exercise the installed Quick Action: two camera inputs, a selected soundtrack, no extra audio, cancellation, existing-output refusal, and explicit replacement. Test a recording folder with spaces and a custom source label. Dialog compilation alone is not this check.
6. For XML shape changes, import into a scratch Final Cut library, play picture and audio across edits, export XML, compare timings and angles, and record the result in `docs/validation.md`. Check the beginning and tail as well as transitions. Never report this as done based on a unit test.
7. Commit the intended source, docs, tests, and regenerated bundle. Tag that reviewed commit with `v<version>` when ready to publish. Pushing the tag triggers the release workflow; pushing main can separately deploy website changes.

## What automation checks

The release workflow runs the synthetic suite, checks that the tag matches the converter version, verifies the generated bundle, creates the ZIP, copies the standalone Python file, and generates and verifies SHA-256 checksums for those two explicitly named files. Missing release files fail the upload step.

The ZIP builder uses fixed member order, timestamps and permissions, and includes only `Contents/Info.plist` and `Contents/document.wflow`. Repeated builds with the same source and Python/compression toolchain produce identical bytes. This is not a promise of identical compressed bytes across all zlib versions, nor a code-signing/notarization claim.

## After publishing

Download the release assets and verify them together with `shasum -a 256 -c SHA256SUMS.txt`. Install the downloaded ZIP on a clean user account if available; confirm the Quick Action is visible in Finder and gives an actionable message when a suitable Python interpreter is missing. Confirm the website's download button reaches the intended release.

A checksum confirms consistency with the published manifest, not publisher identity. Keep the validation ledger explicit about untested hardware, physical exFAT drives, older Final Cut versions, and actual Finder interaction.
