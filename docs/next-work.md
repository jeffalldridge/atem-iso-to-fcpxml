# Maintainer Handoff and Future Considerations

Updated 2026-10-21 for the 1.2.0 candidate. This is a public handoff, not a promise to implement every idea below. Verify the current GitHub release and workflow results before reporting release status. The version in source alone does not establish that an installer has been published.

## Decisions to Preserve

- Keep the converter simple: one recording, one `.fcpxml`, one Live Edit project, and one multicam. Preserve Python/Swift byte parity and the dependency-free runtime. Read [AGENTS.md](../AGENTS.md) before changing behavior.
- Expose the compounds and sources in the Final Cut event browser. Camera/WAV and Media Player compounds share their resources with the multicam; editing their contents affects their uses. Shared-content edits were tested; replacing or relinking media has not been separately verified.
- Keep multicam angle offsets relative to the multicam origin (`0s`), while retaining original source timestamps and multicam `tcStart`. Repeating source timecode as an angle offset caused blank Angle Editor timelines and inflated duration.
- Keep WAV as the soundtrack default when available. **ATEM live mix** preserves the recorded mixed result, using Program audio or an audio-bearing selected ISO. Program picture is independent. No-WAV recordings use the mix automatically; silent MP4s cannot supply it.
- The initial Live Edit uses one continuous soundtrack angle. Final Cut supports multiple simultaneous audio angles; this is an output choice, not a Final Cut limitation. Optional extra WAV angles are available for editing and start unchecked in the app and dialog flow. CLI defaults are documented separately.
- The live mix contains the audible result of AFV, input on/off changes, levels, and processing. Changing picture cuts later does not recompute that recorded mix. Do not imply the converter reconstructs editable mixer automation or add a mixer UI without a new product decision.
- Use plain hyphens in generated compound names and preserve source names and input labels. Matching event and clip names can trigger Final Cut's Keep Both / Replace prompt. The converter cannot inspect a library for name collisions; reimporting does not guarantee a fresh event or remove legacy projects.

## Next Release Steps

The 1.2.0 candidate has aligned version declarations, a finalized changelog, a regenerated Quick Action, a universal local build, and native launch with a real recording. Exact test and Final Cut evidence is in [validation.md](validation.md). The previously published installer is 1.1.1 at the time of this handoff; check GitHub for subsequent releases.

After merge, a maintainer-authorized `v1.2.0` tag on `main` starts the signed release workflow. Follow [releasing.md](releasing.md): verify signing, notarization, stapling, checksums, and the draft assets; check the installed app on a Mac before publishing. A green ordinary CI build uses ad-hoc signing and does not establish release-installer acceptance. Never move an existing release tag. Merge, tagging, draft creation, and public release are separate actions; obtain maintainer authorization for actions not already requested.

The existing Pages workflow deploys site changes merged to `main`. Its installer link points to the latest published release, so publishing the new installer and deploying updated copy are separate events. Recheck the advertised download size and consider refreshing the synthetic app screenshots after the new release is available.

## Validation Priorities

These are evidence gaps, not known failures. Record results and exact limits in [validation.md](validation.md).

1. Test the signed 1.2.0 installer, including replacement of an installed older app and Finder Quick Action lookup when several copies exist.
2. Play the ISO fallback for ATEM live mix in Final Cut with Program missing or silent. It has unit/parity coverage; native rendering currently covers the Program-backed mix.
3. Test source replacement and relinking inside an exposed camera or still compound, checking all uses in the multicam and Live Edit. Do not infer that behavior solely from the shared-content edit test.
4. Check lip sync over a long recording. Different media starts currently produce a warning, not automatic offset correction; any future correction needs native round-trip and playback evidence.
5. Broaden real recordings across ATEM ISO models, firmware, fractional frame rates, and drop-frame midnight. Synthetic coverage is not hardware validation. Real multi-session media naming remains unverified; the app intentionally refuses multi-session logs.
6. Check VoiceOver, Full Keyboard Access, macOS 15, Intel hardware, alternate appearance/accessibility settings, and physical slow/exFAT or failing destinations.

## Ideas Requiring a Separate Decision

- Editable AFV or multi-input mixer reconstruction would require reliable source automation evidence and new native validation. The recorded mix already covers the common “game audio plus microphone” workflow without that complexity.
- A session chooser, automatic synchronization, or library-aware import naming would expand the current scope. Establish a reproducible user need and inspect actual source evidence before designing them.

Never publish real logs, footage, generated XML, library bundles, screenshots of real recordings, or personal paths. Ignored local validation artifacts are useful evidence on one workstation, but future sessions must be able to understand the public decisions and limits without them.
