# Releasing

A release is a git tag `vX.Y.Z` on `main`. The Release workflow builds the universal app, signs it with Developer ID, notarizes and staples the app and the disk image, and publishes a GitHub Release with four files:

- `ATEM-ISO-to-FCPXML.dmg` (the download the website links to; the name never changes so `releases/latest/download/` always works)
- `ATEM-ISO-to-FCPXML-Quick-Action.zip`
- `atem_iso_to_fcpxml.py`
- `SHA256SUMS.txt`

## One-time setup: repository secrets

The workflow uses the same secret names as macSubtitleOCR-gui, so the same values work for both repositories (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12` | Base64 of the Developer ID Application `.p12` export (certificate and private key) |
| `MACOS_CERT_PASSWORD` | The password used for that export |
| `KEYCHAIN_PASSWORD` | Any random string; it protects the temporary keychain on the runner |
| `DEV_ID` | The identity name, for example `Developer ID Application: Tent Studios, LLC (TEAMID)` |
| `NOTARY_KEY` | Base64 of the App Store Connect API key `.p8` |
| `NOTARY_KEY_ID` | The key's 10-character ID |
| `NOTARY_ISSUER_ID` | The issuer UUID |

## Before tagging

1. Set the new version in `Resources/Info.plist` (both version keys), `Sources/ATEMConverter/FCPXML.swift`, `atem_iso_to_fcpxml.py`, and `pyproject.toml`. Move the Unreleased changelog notes under that version and date.
2. Run `python3 scripts/build_quick_action.py` and commit the regenerated bundle.
3. Run `swift test`, `python3 -m unittest discover -s tests`, and `make app`, and open the app once with a real recording.
4. For any change to the XML shapes, do a Final Cut round trip and record it in [validation.md](validation.md).
5. Tag and push: `git tag -a v1.1.0 -m "v1.1.0" && git push origin v1.1.0`.

## Releasing from a Mac instead

With the Developer ID certificate in the login keychain and a notarytool profile stored once with `xcrun notarytool store-credentials atem-iso-to-fcpxml --key AuthKey.p8 --key-id ID --issuer UUID`:

```bash
DEV_ID="Developer ID Application: Tent Studios, LLC (TEAMID)" make release
```

`build/ATEM-ISO-to-FCPXML.dmg` is then signed, notarized, and stapled, and can be attached to a release by hand with `gh release create`. Use `NOTARY_PROFILE=name` to pick a different stored profile.

## After publishing

Download the disk image from the release page on a Mac that has never seen the build, open it, drag the app to Applications, and open it: no Gatekeeper warning should appear. Confirm the website's download button resolves to the new file.
