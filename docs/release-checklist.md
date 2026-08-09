# Pre-release checklist

WindowManager is a provisional internal name. Nothing in this checklist authorizes publishing,
packaging or distribution; those remain held until product and release decisions are made.

## Product identity

- [ ] Select and clear the permanent product name.
- [ ] Confirm the copyright line in `LICENSE` with the maintainer.
- [ ] Select the public bundle identifier and decide whether/how the private identity migrates.
- [ ] Confirm Developer ID ownership, signing team and designated requirement.
- [ ] Finalize app icon, menu-bar identity, versioning and support language.

## Licensing and repository hygiene

- [x] Add the MIT license for the source project.
- [ ] Audit all dependency/reference licenses and update `THIRD_PARTY_NOTICES.md`.
- [ ] Confirm no copied generated artwork, vendor branding or incompatible source is present.
- [ ] Scan tracked history and current files for credentials, tokens, personal paths, logs, app
      bundles, DerivedData and private diagnostics.
- [ ] Add the chosen public security-reporting channel and contribution/issue templates.
- [ ] Review commit authorship/privacy before making history public.

## Build and verification

- [ ] Generate the project from a clean checkout with the documented Xcode/XcodeGen versions.
- [ ] Verify non-hosted test isolation and run the complete suite from a clean DerivedData state.
- [ ] Run static analysis and address compiler warnings relevant to project code.
- [ ] Build universal Release and verify bundle ID, architectures, entitlements and signature.
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
      zero WindowManager frame writes while the session is active.
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

- [ ] Choose distribution: direct download, App Store or another reviewed channel.
- [ ] Choose packaging/install/uninstall behavior and Accessibility migration guidance.
- [ ] Choose update mechanism, signing/notarization pipeline and rollback policy.
- [ ] Produce reproducible release notes, checksums and provenance.
- [ ] Notarize and staple only after the preceding decisions and tests are complete.
- [ ] Publish only with explicit maintainer approval.
