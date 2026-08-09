# WindowRanger work queue

This is the canonical queue for bugs, features, changes, validation, and release work. Add newly
reported items to **Inbox** first. Do not turn a report into a confirmed bug until it has been
reproduced or supported by diagnostics.

## Status and evidence

- **Inbox:** captured but not yet triaged.
- **Ready:** scoped well enough to implement or verify.
- **Needs decision:** product behavior or ownership must be chosen first.
- **Live validation:** implemented or automated-test verified, but still needs the signed app and
  real windows/displays/input.
- **Held:** deliberately blocked on a later product or release decision.
- **Done:** keep only a short completion record; durable detail belongs in the relevant docs.

For bugs, record the observed behavior, expected behavior, reproduction context, and whether the
evidence is user-observed, reproduced, or diagnostic-backed. For features and changes, record the
smallest useful outcome and acceptance boundary.

## Inbox

### WR-015 — Make iCloud settings sync opt-in

- **Type:** Feature / privacy default
- **Priority:** P2
- **Status:** Inbox
- **Evidence:** Requested
- **Current behavior:** General Settings already provides **Sync settings with iCloud**, and turning
  it off keeps settings local. New installations currently default the preference to on.
- **Requested outcome:** Make new installations local-only by default so iCloud is an explicit
  opt-in. Keep the existing visible toggle for people who want sync.
- **Acceptance:**
  - a new installation with no saved preference starts with iCloud sync disabled;
  - an existing installation preserves its saved enabled/disabled choice;
  - disabling sync immediately prevents cloud reads and writes while local profiles and preferences
    continue to persist normally;
  - disabling does not delete local settings or silently delete previously synced cloud data;
  - running without an available iCloud account/store remains fully functional and does not nag;
  - Settings and privacy copy explain which reusable settings sync and which machine/session state
    always remains local;
  - deterministic tests cover first-run default, migration, off-state isolation, and re-enabling.

### WR-016 — Reveal menu diagnostics only with Option-click

- **Type:** Feature / menu cleanup
- **Priority:** P2
- **Status:** Inbox
- **Evidence:** Requested
- **Current behavior:** Debug builds always show the **WindowRanger Debug**, **Copy Recent
  Diagnostics**, and **Reveal Diagnostics File** section in the primary status-item menu. Release
  builds already omit it.
- **Requested outcome:** Keep diagnostics out of the normal user menu. Holding Option while clicking
  the WindowRanger status item reveals the diagnostics section for that menu opening.
- **Acceptance:**
  - opening the Debug status menu normally shows no diagnostics header, separator, copy, or reveal
    items;
  - holding Option when opening the menu shows the existing diagnostics section without changing
    its actions, privacy boundary, or file-availability state;
  - the reveal decision is recalculated for each menu opening and never becomes a persisted/sticky
    preference;
  - releasing Option or reopening normally returns to the clean menu, without duplicate separators
    or menu items;
  - Release builds continue to contain no verbose diagnostics menu controls or file path;
  - the Debug-only Diagnostics destination in Settings remains available and is outside this menu
    change;
  - deterministic menu tests cover normal open, Option-open, repeated transitions, disabled Reveal
    state, and the Release compile-time boundary;
  - troubleshooting docs tell support/test users to Option-click before choosing **Copy Recent
    Diagnostics** or **Reveal Diagnostics File**.

### WR-017 — Copy a focused-window diagnostic report for bug reports

- **Type:** Feature / support diagnostics
- **Priority:** P1
- **Status:** Inbox
- **Evidence:** Requested
- **Current behavior:** Debug builds provide a rotating diagnostic log and a live admission view,
  but users cannot produce one self-contained report explaining why a particular window is being
  managed, ignored, floated, focused, parked, or laid out unexpectedly.
- **Requested outcome:** Let a user focus the misbehaving window, Option-click the WindowRanger menu,
  and copy a bounded, human-reviewable diagnostic report suitable for attaching to a bug report.
- **Capture boundary:**
  - target the last externally focused window captured before the status menu opens, so opening the
    menu cannot replace the subject with WindowRanger UI;
  - work for both managed and unmanaged/ignored candidate windows when Accessibility permits it;
  - read only; generating the report must not focus, raise, move, resize, unpark, admit, or otherwise
    mutate the target window or WindowRanger state;
  - represent unreadable/unsupported Accessibility attributes as unavailable or failed, never as a
    confident false value.
- **Report contents:**
  - a versioned report schema, timestamp, WindowRanger version/build, macOS version, and a short
    current WindowServer-session identifier;
  - target app bundle identifier and privacy-safe session-local window identity;
  - AX/CG role, subrole, layer and capability/read-result summary; focused, main, minimized and
    full-screen observations; current frame and resolved display/visible frame;
  - admission disposition and reasons, workspace/display membership, visibility/parking state,
    app-rule and floating precedence, layout eligibility, current layout/tree participation, and
    expected-versus-observed frame when applicable;
  - bounded recent commands, generation/correlation IDs, frame/focus attempts, AX result codes, and
    stale/cancellation reasons that relate to that window;
  - an explicit privacy header telling the user to review the report before sharing.
- **Privacy boundary:** Never include window titles, document names or paths, URLs, typed text,
  clipboard contents, screenshots/window pixels, full user paths, profile/workspace names, monitor
  serial numbers, unrelated windows, or an unbounded log tail. Apply the existing diagnostic
  sanitizer to the final serialized report as a fail-closed last step.
- **Availability and UX:**
  - expose **Copy Focused Window Diagnostic Report** only in the Option-revealed support section from
    WR-016;
  - make the privacy-safe focused-window report available in distributable builds without enabling
    the persistent verbose Debug log or **Reveal Diagnostics File**;
  - show a clear no-target/Accessibility-unavailable explanation instead of copying a misleading
    partial success report;
  - add a bug-report template field explaining how to generate, review, and attach/paste the report.
- **Acceptance:** Deterministic tests cover managed, ignored, deferred, floating, excluded,
  minimized, full-screen, parked, stale, failed-AX-read, and no-target cases; prove zero window/state
  mutations; verify bounds and schema stability; and inject forbidden privacy values through every
  source to prove none survive the final output.

## Ready

### WR-004 — Bound synced profile-library input with recovery UX

- **Type:** Hardening
- **Priority:** P2 — before public release
- **Status:** Ready
- **Source:** `docs/code-review-2026-08-08.md`, CR-004
- **Outcome:** Define explicit synced-library document, count, and name limits without silently
  rejecting legitimate existing private-install data. Include migration/recovery behavior and
  deterministic tests.

### WR-005 — Measure Debug diagnostic logging under slow storage

- **Type:** Performance measurement
- **Priority:** P3
- **Status:** Ready
- **Source:** `docs/code-review-2026-08-08.md`, CR-005
- **Outcome:** Measure a noisy real Debug session on slow storage before deciding whether ordered
  synchronous JSONL writes need a queue. Preserve diagnostic ordering unless evidence justifies a
  change.

### WR-006 — Reconcile the future-systems brief with implemented Tiled manipulation

- **Type:** Documentation change
- **Priority:** P2
- **Status:** Ready
- **Source:** `docs/future-workspace-systems-decisions.md` versus current
  `TiledLayoutTree`/`WorkspaceEngine` code and tests
- **Outcome:** Stop describing manual split resizing and drag-to-swap as wholly future work. Keep
  layout presets and any unimplemented overlay/editor behavior clearly separated and research-only.

## Live validation

### WR-001 — Run the signed-app stability checkpoint

- **Type:** Validation
- **Priority:** P1
- **Status:** Live validation
- **Sources:** `docs/code-review-2026-08-08.md`, `docs/release-checklist.md`
- **Scope:**
  - crash or Xcode Stop recovery with a parked inactive-workspace window;
  - a real shortcut collision and rapid shortcut reconfiguration;
  - two-display focus, movement, layout, profile switching, and Settings resurfacing;
  - sleep/wake while display topology changes;
  - Compact/Medium/Full transitions under realistic menu-bar pressure.
- **Evidence boundary:** Start by gracefully quitting the old build, then run the intended signed
  Debug product from Xcode. Capture one bounded Debug diagnostic excerpt for any mismatch.

### WR-002 — Tune and validate live command-wheel and Tiled placement input

- **Type:** Validation / tuning
- **Priority:** P1
- **Status:** Live validation
- **Sources:** `docs/radial-menu-design.md`, `docs/radial-tiled-placement.md`,
  `docs/two-arrow-tiled-placement-recommendation.md`
- **Scope:**
  - Press-to-Toggle and Hold-to-Show with keyboard and pointer;
  - optional Globe/Fn hold, quick-tap pass-through, chords, cancellation, and event-tap failure;
  - two-arrow physical-keyboard timing and feel around the current 200 ms threshold;
  - preview/commit fidelity with two, three, and several real windows in Unified and Independent
    Displays modes;
  - focus retention, edge clamping, stale-context cancellation, and honest one/two-window corners.
- **Outcome:** Record tuned thresholds or concrete bugs; do not change timing from preference alone.

### WR-003 — Validate native full-screen game safety

- **Type:** Safety validation
- **Priority:** P1
- **Status:** Live validation
- **Source:** `docs/release-checklist.md`
- **Scope:** Enter/exit native full screen, Command-Escape Game Overlay, workspace away/return, and
  confirm zero WindowRanger frame writes while the protected session is active.

## Needs product decision — research only

Nothing in this section is approved for implementation. Resolve the listed product boundary before
adding engineering tasks.

### WR-007 — Pinned-display mode

- **Type:** Feature research
- **Status:** Needs decision
- **Source:** `docs/future-workspace-systems-decisions.md`
- **Decision:** Profile-owned versus local pinning, staged-display cardinality, workspace-home
  semantics, Full-mode interaction, and whether all-pinned is valid.

### WR-008 — Named whole-desk arrangements

- **Type:** Feature research
- **Status:** Needs decision
- **Source:** `docs/future-workspace-systems-decisions.md`
- **Decision:** Launch behavior, same-app window matching, ownership/sync, captured data, unmatched
  windows, and merge versus replace semantics.

### WR-009 — Optional workspace/stage overview

- **Type:** Feature research
- **Status:** Needs decision
- **Source:** `docs/future-workspace-systems-decisions.md`
- **Decision:** Whether metadata-only is valuable first; whether thumbnails justify Screen
  Recording permission; placeholder/cache privacy; panel scope; click and drag semantics.

### WR-010 — Reusable layout presets

- **Type:** Feature research
- **Status:** Needs decision
- **Source:** `docs/future-workspace-systems-decisions.md`
- **Decision:** Global/profile/workspace ownership, initial presets and participant policy,
  Tiled-only versus Freeform, and what topology can persist without guessing window identity.

## Pre-release work

`docs/release-checklist.md` remains the detailed authority. These are queue-level epics, not a
second copy of that checklist.

### WR-011 — Product identity and public project hygiene

- **Type:** Release epic
- **Status:** Held
- **Completed groundwork:** Contributor workflow and safety rules, issue forms, pull-request template,
  CODEOWNERS review routing, governance, support, and code-of-conduct documents.
- **Remaining scope:** Copyright, Developer ID/signing ownership, final icon/version/support language,
  third-party licence audit, history/secret/privacy review, private security reporting, and a private
  project-controlled conduct contact.

### WR-012 — Clean build and package verification

- **Type:** Release epic
- **Status:** Held
- **Scope:** Clean-checkout generation, isolated suite, static analysis, universal Release identity
  and signature, Debug-boundary audit, LaunchServices hygiene, and clean-machine lifecycle testing.

### WR-013 — Full manual regression and accessibility/privacy review

- **Type:** Release epic
- **Status:** Held
- **Scope:** Complete the manual matrix, permission flows, VoiceOver and keyboard access, Reduced
  Motion/contrast/large text, diagnostics redaction, runtime network/iCloud inspection, and final
  human-reviewed permission/privacy copy.

### WR-014 — Distribution, updates, notarization, and publication

- **Type:** Release epic
- **Status:** Held
- **Decided:** Stable (`main`), Beta (`release/*`), and Dev (`develop`) channels using the documented
  Gitflow-style promotion model. Sparkle is the intended future updater for the default Stable and
  opt-in Beta channels; Dev remains outside auto-update feeds.
- **Updater feature boundary:**
  - integrate Sparkle as the signed update framework for distributable builds;
  - provide a clear Settings choice between **Stable** (default) and **Beta** (opt-in);
  - use one signed appcast with Stable on Sparkle's default channel and Beta on its `beta` channel;
  - Beta users may receive both eligible Beta builds and newer Stable builds; Stable users never
    receive Beta builds;
  - changing from Beta back to Stable must not silently downgrade an installed newer Beta. Explain
    that the app will remain on that build until a newer Stable is available, with any manual
    downgrade kept explicit;
  - keep Dev builds outside Sparkle and update them only through the documented development flow;
  - verify channel persistence, update eligibility, signatures, failed/cancelled updates, release
    notes, upgrade paths, and the Beta-to-Stable transition with deterministic and packaged-app
    tests.
- **Homebrew distribution boundary:**
  - distribute the signed, notarized Stable `.app` as a versioned Homebrew Cask, targeting
    `brew install --cask windowranger` when the project is eligible for the selected tap;
  - use the same immutable Stable artifact, version, and checksum as the direct-download release;
  - declare and document how Homebrew upgrades coexist with Sparkle self-updates so the two paths
    do not present contradictory update state;
  - verify install, launch, upgrade, reinstall, ordinary uninstall, and explicit `--zap` behavior on
    supported macOS versions and both shipped architectures;
  - ordinary uninstall must not unexpectedly erase user configuration, while any optional zap must
    list its removal scope clearly;
  - test and document Accessibility permission implications across Homebrew upgrade/reinstall rather
    than claiming they are preserved;
  - keep Beta and Dev packaging out of the initial Homebrew acceptance boundary unless separately
    approved.
- **Remaining scope:** Create/protect `develop`, choose distribution and packaging, Accessibility
  migration guidance, implement and secure Sparkle, create and validate the Homebrew Cask, define
  update/rollback failure handling, release provenance, signing/notarization, and publication.
- **Gate:** Requires explicit maintainer approval; this queue does not authorize publishing.

### WR-018 — Publish the first GitHub Beta

- **Type:** Release
- **Priority:** P1
- **Status:** Live validation
- **Outcome:** Publish `v0.1.0-beta.1` as a GitHub prerelease with the exact universal Developer
  ID-signed, notarized, stapled ZIP, SHA-256 checksum, provenance manifest, reviewed release notes,
  and no claim of Sparkle or Stable support.
- **Implemented groundwork:** Unprivileged GitHub Actions verification, Hardened Runtime build
  setting, Developer ID export configuration, local build/notarize/package script, draft-release
  script, release-notes template, and first-release runbook.
- **Automated evidence:** Stable Xcode 26.6 passes the non-hosted test-isolation check, all 415
  tests, Release static analysis, and an unsigned universal `arm64 x86_64` Release build with
  Hardened Runtime enabled. GitHub Actions run
  [31326683991](https://github.com/windowranger/windowranger/actions/runs/31326683991) independently
  passes the same isolation, 415-test, analysis, and unsigned Release-build gates on macOS 26 with
  Xcode 26.6. The intended `44NAD22AK6` team now has a local Developer ID Application identity with
  private key, an installed all-device Developer ID profile authorizing the public bundle ID and
  iCloud key-value entitlement through August 2044, and a validated `WindowRanger` notary Keychain
  profile. The credentialed archive/export/notarization path remains untested.
- **Current blockers:**
  - complete the remaining product-identity, repository-publication, manual regression,
    accessibility, privacy, and clean-package gates in `docs/release-checklist.md`;
  - build and test the exact artifact from a clean `release/0.1.0` branch using stable Xcode.
- **Publication gate:** Creating the draft is not publication. Changing repository visibility and
  publishing the reviewed draft each require explicit maintainer action at the final checkpoint.

## Scan notes — not queued again

- Menu-bar, Workspace Settings, and contextual radial-menu visual QA have no unresolved P0/P1/P2
  mismatch in `design-qa.md`.
- Portable profile transfer is described as implemented in the current README and reviewed code;
  its remaining live coverage belongs to WR-001/WR-013.
- Manual Tiled split resizing and drag-to-swap already have implementation/test evidence. WR-006 is
  the documentation correction; it is not a request to rebuild them.
- Native Spaces integration remains an explicit non-goal.

## New-item template

```markdown
### WR-XXX — Short title

- **Type:** Bug | Feature | Change | Validation | Research
- **Priority:** P0 | P1 | P2 | P3
- **Status:** Inbox
- **Evidence:** User-observed | Reproduced | Diagnostic-backed | Requested
- **Context:** App/build, workspace/layout, displays, focused app/window, and trigger
- **Observed/requested:**
- **Expected/outcome:**
- **Reproduction/acceptance:**
```
