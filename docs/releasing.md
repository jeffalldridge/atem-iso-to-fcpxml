# Releasing

A release is a git tag `vX.Y.Z` on a commit that is on `main`; the workflow refuses any other tag. The Release workflow has two jobs. **Build** (read-only repository access, the signing credentials, the `release` environment) builds the universal app, signs it with Developer ID, notarizes and staples the app and the disk image, checks them with `spctl` and `stapler`, and uploads four files as a workflow artifact. **Publish** (the only job with `contents: write`, no credentials) checks the checksums and creates a **draft** GitHub Release with the files. Nothing is public, and nothing becomes "latest", until you open the draft, check it, and press Publish. The four files are:

- `ATEM-ISO-to-FCPXML.dmg` (the download the website and README link to directly as `releases/latest/download/ATEM-ISO-to-FCPXML.dmg`; keep the name unchanged or those links break)
- `ATEM-ISO-to-FCPXML-Quick-Action.zip`
- `atem_iso_to_fcpxml.py`
- `SHA256SUMS.txt`

## Workflow status

The `v1.1.1` workflow completed on a hosted runner: version and tag checks, tests, Developer ID signing, app and disk-image notarization, Gatekeeper and stapler checks, and draft release creation. The maintainer then opened the downloaded disk image without a Gatekeeper warning. See [validation.md](validation.md) for the scope of that verification; it did not cover a second machine or account.

The workflow requires the six credentials below. The successful run establishes that they were available for that release, not that their configuration or validity has been checked since. Do not change signing credentials as part of ordinary development.

## Credential setup

For a new repository or intentional credential rotation, configure these under Settings → Secrets and variables → Actions, or in the `release` environment. GitHub never shows a secret's value again, so copy them from wherever you keep the original certificate export and App Store Connect key. The runner's keychain password is generated inside the job, so `KEYCHAIN_PASSWORD` is not needed. The build job also declares the `release` environment, so you can later add a required reviewer there without changing the workflow.

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12` | Base64 of the Developer ID Application `.p12` export (certificate and private key) |
| `MACOS_CERT_PASSWORD` | The password used for that export |
| `DEV_ID` | The identity name, for example `Developer ID Application: Tent Studios, LLC (TEAMID)` |
| `NOTARY_KEY` | Base64 of the App Store Connect API key `.p8` |
| `NOTARY_KEY_ID` | The key's 10-character ID |
| `NOTARY_ISSUER_ID` | The issuer UUID |

A manual workflow dispatch must also select a `vX.Y.Z` tag. Branch dispatches are rejected. Missing credentials fail the job; a green run must not mean that publishing was silently skipped. The job removes its temporary signing keychain and key files even after a failure.

The runner-selected Xcode must be version 26 or newer for Icon Composer assets. The workflow checks the installed toolchain instead of guessing version-specific application paths.

## Before tagging

1. Run `python3 scripts/check_release.py vX.Y.Z` to verify all declarations after setting the new version in `Resources/Info.plist` (both version keys), `Sources/ATEMConverter/FCPXML.swift`, `atem_iso_to_fcpxml.py`, and `pyproject.toml`. Move the Unreleased changelog notes under that version and date.
2. Run `python3 scripts/build_quick_action.py` and commit the regenerated bundle.
3. Run `swift test`, `python3 -m unittest discover -s tests`, and `make app`, and open the app once with a real recording.
4. For any change to the XML shapes, do a Final Cut round trip and record it in [validation.md](validation.md).
5. Make sure the commit is on `main`, then tag and push: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z` (substitute the new version; never move an existing release tag). The workflow creates a draft.

## Releasing from a Mac instead

With the Developer ID certificate in the login keychain and a notarytool profile stored once with `xcrun notarytool store-credentials atem-iso-to-fcpxml --key AuthKey.p8 --key-id ID --issuer UUID`:

```bash
DEV_ID="Developer ID Application: Tent Studios, LLC (TEAMID)" make release
```

`build/ATEM-ISO-to-FCPXML.dmg` is then signed, notarized, and stapled. To publish by hand, also produce the other three assets and create the release (draft first, so you can check it before it becomes "latest"):

```bash
python3 scripts/build_quick_action.py --zip build/ATEM-ISO-to-FCPXML-Quick-Action.zip
cp atem_iso_to_fcpxml.py build/
(cd build && shasum -a 256 ATEM-ISO-to-FCPXML.dmg ATEM-ISO-to-FCPXML-Quick-Action.zip atem_iso_to_fcpxml.py > SHA256SUMS.txt)
gh release create vX.Y.Z --draft --title "vX.Y.Z" --notes-file notes.md build/ATEM-ISO-to-FCPXML.dmg build/ATEM-ISO-to-FCPXML-Quick-Action.zip build/atem_iso_to_fcpxml.py build/SHA256SUMS.txt
```

Use `NOTARY_PROFILE=name` to pick a different stored profile.

## Before publishing the draft

Download the disk image from the draft from the release page on a Mac that has never seen the build, open it, drag the app to Applications, and open it: no Gatekeeper warning should appear. Then press Publish. Confirm `https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest/download/ATEM-ISO-to-FCPXML.dmg` redirects to the new file, and that the size the website states (about 3 MB) is still right.
