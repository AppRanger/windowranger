# Pre-release checklist

WindowRanger is the selected product name. Nothing in this checklist authorizes publishing,
packaging or distribution; those remain held until product and release decisions are made.

The [release-channel contract](release-channels-and-branching.md) defines Stable, Beta, and Dev
promotion and versioning. It is a design authority, not evidence that the release machinery exists.

## Product identity

- [x] Select the product name and complete preliminary clearance: **WindowRanger**.
- [x] Confirm the copyright line in `LICENSE` with the maintainer as part of the explicit
      first-publication approval.
- [x] Select `dev.appranger.WindowRanger` as the public bundle identifier.
- [x] Confirm Developer ID ownership and team `44NAD22AK6`.
- [x] Verify automatic Developer ID provisioning for `dev.appranger.WindowRanger`; a stable-Xcode
      archive/export produced a Developer ID-signed universal app with the expected designated
      requirement, public bundle identifier, and preserved iCloud key-value entitlement.
- [x] Finalize the first-Beta app icon, menu-bar identity, versioning and support language.

## Licensing and repository hygiene

- [x] Add the MIT license for the source project.
- [x] Audit all dependency/reference licenses and update `THIRD_PARTY_NOTICES.md`; the app uses only
      Apple SDK frameworks and vendors no third-party package or source.
- [x] Confirm the retained artwork was generated specifically for WindowRanger, contains no vendor
      branding, and has recorded provenance in `Brand/WindowRanger/README.md`.
- [x] Scan all 92 commits and current files for credentials, tokens, personal paths, logs, app
      bundles, DerivedData and private diagnostics. Gitleaks 8.30.1 reported only four false
      positives on two local settings keys; historical absolute-path hits are obsolete design
      provenance and privacy-scrubber fixtures, not secrets or shipped paths.
- [x] Add contribution guidelines, issue forms, a pull-request template, governance, support, and a
      code of conduct.
- [x] Enable GitHub private vulnerability reporting and link the private form from `SECURITY.md`.
- [x] Confirm the private form is active as the project-controlled conduct-reporting path documented
      in `CODE_OF_CONDUCT.md`.
- [x] Review commit authorship/privacy before making history public; all 92 commits use the intended
      maintainer identity.

## Build and verification

- [x] Generate the project from a clean release worktree with stable Xcode 26.6 and the documented
      XcodeGen toolchain.
- [x] Verify non-hosted test isolation and run the complete suite from a clean DerivedData state.
- [x] Run static analysis and address compiler warnings relevant to project code.
- [x] Build universal Release and verify bundle ID, architectures, entitlements and Developer ID
      signature.
- [x] Confirm the exact Beta Release omits the Debug menu labels, verbose diagnostic path, and
      internal-only copy while retaining the inert logging type required by shared code.
- [ ] Audit LaunchServices so validation leaves only intended products registered.
- [ ] Run a clean-machine installation/upgrade/uninstall test.

## Manual regression matrix

- [ ] First-run Accessibility denied, granted, retry and already-trusted flows.
- [ ] Unified and Independent Displays on one, two and three displays.
- [ ] External display disconnect/reconnect, dock/undock and sleep/wake.
- [ ] WindowServer/logout/reboot recovery and deliberate crash/debugger-stop recovery.
- [ ] Workspace switch/move/focus/reorder/resize across same-app windows and multiple displays.
- [ ] Freeform, Tiled and Accordion with floating/dialog/rule-excluded/keep-on-all windows.
- [ ] Ignored panels/popups, minimized/full-screen windows and apps that reject AX frame writes.
- [ ] Native full-screen game enter/exit, Command-Escape Game Overlay, workspace away/return, and
      zero WindowRanger frame writes while the session is active.
- [ ] Profile conversion/switching/triggers/iCloud sync and additive profile import/export preview,
      cancellation, invalid-file rejection, and safe Undo.
- [ ] Menu-bar Compact/Medium/Full pressure, notch, long names and VoiceOver.
- [ ] Command wheel Press/Hold, keyboard/pointer, edge clamping and stale-context cancellation.
- [ ] Settings search, workspace inspector, import panels, Undo, current-display routing and scaling.
- [ ] Graceful Quit restores every managed window to a visible safe frame.

## Accessibility and privacy review

- [ ] Review all permission prompts and Settings copy with a human.
- [ ] Test VoiceOver, full keyboard access, reduced motion, increased contrast and large text.
- [ ] Verify diagnostics redaction/rotation with representative apps and copied excerpts.
- [ ] Inspect runtime network activity and iCloud payload boundaries.
- [ ] Prepare final privacy policy/disclosure appropriate to the selected distribution channel.

## Packaging and updates — held

- [x] Define Stable, Beta, and Dev release channels and the Gitflow-style promotion model.
- [x] Create `develop`, make it the default integration branch, and run the required CI workflow.
- [x] Protect `main` and `develop` with pull-request, required-check, conversation-resolution,
      deletion, and force-push rules; protect `v*` tags with a maintainer-only active ruleset.
- [x] Choose the initial distribution: a signed, notarized channel-specific DMG attached to a
      GitHub prerelease, with a notarized ZIP fallback; Homebrew remains a later Stable channel.
- [x] Choose a local-first release pipeline: repository-managed local checks perform private-phase
      unprivileged verification; standard GitHub Actions independently repeat it when public or
      explicitly dispatched; and the maintainer's Mac performs Developer ID signing, notarization,
      stapling, and packaging.
- [x] Validate `scripts/build-distribution.sh` with the intended Developer ID identity and
      `WindowRanger` notary profile stored in an explicit file-based login Keychain; test the exact
      installed DMG on the maintainer's Mac.
- [ ] Test the exact packaged artifact on another supported Mac or a clean macOS user account.
- [x] Create and automatically verify the Stable and construction-themed Beta DMG layouts, including
      the `/Applications` shortcut and native drag-to-install instruction.
- [ ] Validate DMG install/uninstall behavior and Accessibility migration guidance on a clean machine
      or user account.
- [ ] Create and validate a Homebrew Cask for the signed, notarized Stable app, including immutable
      artifact/checksum provenance, Sparkle coexistence, install/upgrade/uninstall/zap behavior, and
      Accessibility permission guidance.
- [x] Integrate Sparkle 2.8.1 with a hard Dev-build exclusion, local Stable/Beta choice, manual
      checking, opt-in automatic checking/downloading, and deterministic channel/configuration tests.
- [x] Add the append-only public build-number ledger, reject unallocated/reused builds and an
      initial-feed bypass, recheck the single central allocation before appcast generation, and
      verify retained update URLs, stale-branch rejection and atomic local-feed failure.
- [ ] Provision the release EdDSA key, generate and host one appcast containing signed Stable and
      opt-in `beta` archives, and validate monotonic build numbers, signatures, rollback, and failure
      UX with packaged apps.
- [x] Choose and prove the local-first signing/notarization pipeline; keep credentials off ordinary
      GitHub Actions jobs.
- [ ] Finalize the Stable/Beta rollback policy before the public feed is activated or automatic
      checking is enabled by default.
- [x] Produce tracked release notes, SHA-256 checksums and a commit/toolchain provenance manifest;
      round-trip verify all five GitHub assets.
- [x] Developer ID-sign, notarize, staple, Gatekeeper-check, and verify the exact Beta app and DMG.
- [x] Define a streamlined repeat-Beta path that may skip only the redundant replacement install
      when the same product paths already passed signed daily validation and no distribution
      boundary changed; retain every automated, signing, notarization, packaging, provenance, and
      downloaded-asset verification gate. Stable and distribution-boundary changes still require
      exact packaged-artifact installation testing.
- [x] Publish `v0.1.0-beta.1` only after explicit maintainer approval, preserving its verified tag
      and five uploaded assets.
- [x] Publish `v0.1.0-beta.2` only after exact-artifact maintainer testing and explicit approval,
      preserving release commit `82b2fa381ae4` and its five round-trip-verified assets.
