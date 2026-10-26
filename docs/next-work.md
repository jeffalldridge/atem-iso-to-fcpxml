# Maintainer Handoff and Future Considerations

Updated 2026-10-25 for the 1.3.0 updater work. This is a public handoff, not a promise to implement every idea below. Verify the current GitHub release and workflow results before reporting release status. The version in source alone does not establish that an installer has been published.

## Decisions to Preserve

- Keep the converter simple: one recording, one `.fcpxml`, one Live Edit project, and one multicam. Preserve Python/Swift byte parity and the dependency-free runtime. Read [AGENTS.md](../AGENTS.md) before changing behavior.
- Expose the compounds and sources in the Final Cut event browser. Camera/WAV and Media Player compounds share their resources with the multicam; editing their contents affects their uses. Shared-content edits were tested; replacing or relinking media has not been separately verified.
- Keep multicam angle offsets relative to the multicam origin (`0s`), while retaining original source timestamps and multicam `tcStart`. Repeating source timecode as an angle offset caused blank Angle Editor timelines and inflated duration.
- Keep WAV as the soundtrack default when available. **ATEM live mix** preserves the recorded mixed result, using Program audio or an audio-bearing selected ISO. Program picture is independent. No-WAV recordings use the mix automatically; silent MP4s cannot supply it.
- The initial Live Edit uses one continuous soundtrack angle. Final Cut supports multiple simultaneous audio angles; this is an output choice, not a Final Cut limitation. Optional extra WAV angles are available for editing and start unchecked in the app and dialog flow. CLI defaults are documented separately.
- The live mix contains the audible result of AFV, input on/off changes, levels, and processing. Changing picture cuts later does not recompute that recorded mix. Do not imply the converter reconstructs editable mixer automation or add a mixer UI without a new product decision.
- Use plain hyphens in generated compound names and preserve source names and input labels. Matching event and clip names can trigger Final Cut's Keep Both / Replace prompt. The converter cannot inspect a library for name collisions; reimporting does not guarantee a fresh event or remove legacy projects.

## Update Delivery (1.3.0, In Development)

The maintainer requested GitHub-backed update checking and automatic installation on 2026-10-25. The Mac app now uses Sparkle; the converter remains dependency-free. A dedicated update-signing key is configured in the release environment. This supersedes the manual-only update policy. The maintainer authorized the first updater-equipped release on 2026-10-25; older installed versions need one manual upgrade. See [releasing.md](releasing.md) for signed feed delivery and [validation.md](validation.md) for current evidence.

## Next Release Steps

The local 1.3.0 changes include the existing source-visibility fixes, Sparkle integration, update-signing configuration, and signed-feed release tooling. Checks and evidence are in [validation.md](validation.md). The latest published installer checked on 2026-10-25 is 1.1.1.

After maintainer-authorized commit/push and merge, a `v1.3.0` tag on `main` starts the signed release workflow. Follow [releasing.md](releasing.md): verify nested framework signing, notarization, stapling, checksums, the signed appcast, and draft assets. Check an installed signed build before publishing. The local notarization profile is not configured; use the established GitHub release workflow. Never move an existing release tag. Push, tagging, draft creation, and public release remain separate actions requiring authorization.

The Pages workflow deploys site changes merged to `main`. Its installer link follows the latest published release. Keep website and installer publication coordinated; the automatic-update feed is a GitHub release asset, independent of Pages.

## Validation Priorities

These are evidence gaps, not known failures. Record results and exact limits in [validation.md](validation.md).

1. Test the signed 1.3.0 installer, including replacement of an installed older app and Finder Quick Action lookup when several copies exist.
2. Play the ISO fallback for ATEM live mix in Final Cut with Program missing or silent. It has unit/parity coverage; native rendering currently covers the Program-backed mix.
3. Test source replacement and relinking inside an exposed camera or still compound, checking all uses in the multicam and Live Edit. Do not infer that behavior solely from the shared-content edit test.
4. Check lip sync over a long recording. Different media starts currently produce a warning, not automatic offset correction; any future correction needs native round-trip and playback evidence.
5. Broaden real recordings across ATEM ISO models, firmware, fractional frame rates, and drop-frame midnight. Synthetic coverage is not hardware validation. Real multi-session media naming remains unverified; the app intentionally refuses multi-session logs.
6. Check VoiceOver, Full Keyboard Access, macOS 15, Intel hardware, alternate appearance/accessibility settings, and physical slow/exFAT or failing destinations.

## Ideas Requiring a Separate Decision

- Editable AFV or multi-input mixer reconstruction would require reliable source automation evidence and new native validation. The recorded mix already covers the common “game audio plus microphone” workflow without that complexity.
- A session chooser, automatic synchronization, or library-aware import naming would expand the current scope. Establish a reproducible user need and inspect actual source evidence before designing them.

Never publish real logs, footage, generated XML, library bundles, screenshots of real recordings, or personal paths. Ignored local validation artifacts are useful evidence on one workstation, but future sessions must be able to understand the public decisions and limits without them.
