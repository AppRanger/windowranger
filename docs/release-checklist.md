# Pre-release checklist

WindowRanger is the selected product name. Nothing in this checklist authorizes publishing,
packaging or distribution; those remain held until product and release decisions are made.

The [release-channel contract](release-channels-and-branching.md) defines Stable, Beta, and Dev
promotion and versioning. It is a design authority, not evidence that the release machinery exists.

## Product identity

- [x] Select the product name and complete preliminary clearance: **WindowRanger**.
- [ ] Confirm the copyright line in `LICENSE` with the maintainer.
- [x] Select `com.windowranger.WindowRanger` as the public bundle identifier; the private development
      identity intentionally does not migrate.
- [x] Confirm Developer ID ownership and team `44NAD22AK6`; verify the exported app's Developer ID
      designated requirement and public bundle identifier.
- [ ] Finalize app icon, menu-bar identity, versioning and support language.

## Licensing and repository hygiene

- [x] Add the MIT license for the source project.
- [ ] Audit all dependency/reference licenses and update `THIRD_PARTY_NOTICES.md`.
- [ ] Confirm no copied generated artwork, vendor branding or incompatible source is present.
- [ ] Scan tracked history and current files for credentials, tokens, personal paths, logs, app
      bundles, DerivedData and private diagnostics.
- [x] Add contribution guidelines, issue forms, a pull-request template, governance, support, and a
      code of conduct.
- [ ] Enable GitHub private vulnerability reporting or publish another verified private security
      contact, then update `SECURITY.md`.
- [ ] Publish a private project-controlled conduct-reporting contact in `CODE_OF_CONDUCT.md`.
- [ ] Review commit authorship/privacy before making history public.

## Build and verification

- [x] Generate the project from a clean release worktree with stable Xcode 26.6 and the documented
      XcodeGen toolchain.
- [x] Verify non-hosted test isolation and run the complete suite from a clean DerivedData state.
- [x] Run static analysis and address compiler warnings relevant to project code.
- [x] Build universal Release and verify bundle ID, architectures, entitlements and Developer ID
      signature.
- [ ] Confirm Release omits Debug menus, verbose diagnostic paths and internal-only copy.
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
- [ ] Protect `main`, `develop`, and release tags once GitHub Pro is enabled or the repository is
      made public; the current private plan rejects rulesets and branch protection.
- [x] Choose the initial distribution: a signed, notarized channel-specific DMG attached to a
      GitHub prerelease, with a notarized ZIP fallback; Homebrew remains a later Stable channel.
- [x] Choose a local-first release pipeline: repository-managed local checks perform private-phase
      unprivileged verification; standard GitHub Actions independently repeat it when public or
      explicitly dispatched; and the maintainer's Mac performs Developer ID signing, notarization,
      stapling, and packaging.
- [x] Validate `scripts/build-distribution.sh` with the intended Developer ID identity and
      `WindowRanger` notary profile; test the exact installed DMG on the maintainer's Mac.
- [ ] Test the exact packaged artifact on another supported Mac or a clean macOS user account.
- [x] Create and automatically verify the Stable and construction-themed Beta DMG layouts, including
      the `/Applications` shortcut and native drag-to-install instruction.
- [ ] Validate DMG install/uninstall behavior and Accessibility migration guidance on a clean machine
      or user account.
- [ ] Create and validate a Homebrew Cask for the signed, notarized Stable app, including immutable
      artifact/checksum provenance, Sparkle coexistence, install/upgrade/uninstall/zap behavior, and
      Accessibility permission guidance.
- [x] Select Sparkle as the intended future Stable/Beta update framework; implementation remains
      held.
- [ ] Design and implement one signed Sparkle appcast with default Stable and opt-in `beta` channel,
      including channel switching, monotonic build numbers, signatures, rollback, and failure UX.
- [x] Choose and prove the local-first signing/notarization pipeline; keep credentials off ordinary
      GitHub Actions jobs.
- [ ] Finalize the Stable/Beta rollback policy before automatic updates are implemented.
- [x] Produce tracked release notes, SHA-256 checksums and a commit/toolchain provenance manifest;
      round-trip verify all five GitHub assets.
- [x] Developer ID-sign, notarize, staple, Gatekeeper-check, and verify the exact Beta app and DMG.
- [ ] Publish only with explicit maintainer approval.
