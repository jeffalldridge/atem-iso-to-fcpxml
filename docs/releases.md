# Mac downloads and releases

The download build is a SwiftUI app with a bundled Python engine. Users need neither Python nor developer tools. The standalone converter remains one standard-library Python file. PyInstaller is a **build dependency**, not a service or a dependency users install.

Two DMGs are built: Apple silicon and Intel. Each contains the app, an Applications shortcut, and brief installation instructions. Drag the app to Applications; when updating, quit it and choose Replace. The app menu installs the bundled Finder Quick Action into the user’s Services folder and asks before replacing an existing copy. Installation stages the new bundle and restores the previous one if replacement fails. Opening an installed app records its location so the Quick Action uses that copy rather than an older source preview.

## Current status

The build and release workflows are implemented, and both architecture builds pass on GitHub. The Developer ID certificate, export password, and signing identity are configured in the repository’s `release` environment. The three notarization secrets still need configuration. A public notarized Mac app has **not** been released. Do not describe an unsigned CI artifact as a finished download. The older 1.0.0 release contains the broken dialog workflow.

## One-time signing setup

Create a GitHub environment named `release` in this repository. Limit deployment branches/tags to version tags and use a required reviewer if your GitHub plan supports it. Add these environment secrets (repository secrets also work):

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE` | Base64 of a password-protected `.p12` containing the **Developer ID Application** certificate and its private key. Export only this identity from Keychain Access. |
| `CERTIFICATE_PASSWORD` | Password used for that `.p12` export. |
| `SIGNING_IDENTITY` | Full Developer ID Application identity name. |
| `NOTARY_PRIVATE_KEY` | Contents of the App Store Connect team API key `.p8` used for notarization. |
| `NOTARY_KEY_ID` | That API key's key ID. |
| `NOTARY_ISSUER_ID` | The team's issuer ID. |

Use GitHub's secret form or `gh secret set` with stdin/file redirection. Do not paste signing material into chat, commit it, echo it in logs, or upload an entire keychain. Private key exports should be deleted after secure configuration. The workflow imports the identity into a temporary runner keychain and deletes it afterward. Signing credentials are only used by tag-triggered release jobs, never PR builds.

Apple Development and Apple Distribution certificates are not substitutes for Developer ID Application. This DMG flow does not require a Developer ID Installer certificate.

## Build locally

With a redistributable Python 3.13 environment:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements-macos-build.txt
.venv/bin/python scripts/build_macos_app.py --bundle-python
.venv/bin/python scripts/package_macos_app.py
```

This makes an ad-hoc-signed preview. For a Developer ID signature, pass `--sign-identity` to the app builder. Signing is not notarization. The builder includes Python and PyInstaller license notices and verifies the app signature. Builds must use the target architecture's Python; do not combine frozen executables with `lipo`.

## CI and publication

1. The Tests workflow builds and exercises the bundled engine on Apple silicon and Intel. Its artifacts are explicitly named **unsigned-preview**. They are for maintainers, not website download buttons.
2. Update the version in the converter and `pyproject.toml`, rebuild the Quick Action, and run the required checks. Push a matching `vX.Y.Z` tag only after signing secrets are configured.
3. Release builds test, sign the app and nested runtime, submit it with `notarytool`, staple and validate its ticket, and run Gatekeeper assessment. They then create, sign, notarize, and staple the DMG. Any failure blocks publication.
4. Both architectures must succeed before the release job uploads their DMGs, the standalone workflow/script, and checksums to a **draft** GitHub Release.
5. Download the draft artifacts. On clean Macs, test Gatekeeper, app launch, conversion without external Python, replacement of an older app, optional Quick Action installation/replacement, and Final Cut import. Check Intel and Apple silicon and the minimum supported macOS version. Automated builds do not establish this acceptance.
6. Publish the draft after review. Then change the website's primary action to **Download for Mac**, with clearly labeled Apple silicon and Intel links. Use `/releases/latest/download/ATEM-ISO-to-FCPXML-Apple-Silicon.dmg` and `...-Intel.dmg` only after both files are publicly available. Update the website/README requirements and structured download URL together, retaining source-build instructions for contributors.

The native app and standalone workflow have different requirements: downloaded apps bundle Python; the standalone workflow's fallback still needs Python 3.9+. There is no automatic update checker. Replacing the app updates its bundled engine; repeat the optional Quick Action install if its launcher changed.

## References

- [Apple: Developer ID distribution](https://developer.apple.com/developer-id/)
- [Apple: Customizing notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [GitHub: signing on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [GitHub: runner architectures](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [PyInstaller: macOS architecture and signing](https://pyinstaller.org/en/stable/feature-notes.html)

Checked 2026-10-21. Vendor guidance is reference material, not permission to export credentials or publish a release.
