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

None.

## Ready

### WR-005 — Measure Debug diagnostic logging under slow storage

- **Type:** Performance measurement
- **Priority:** P3
- **Status:** Ready
- **Source:** `docs/code-review-2026-08-08.md`, CR-005
- **Outcome:** Measure a noisy real Debug session on slow storage before deciding whether ordered
  synchronous JSONL writes need a queue. Preserve diagnostic ordering unless evidence justifies a
  change.

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

### WR-019 — Separate the local Xcode development identity

- **Type:** Development workflow / signing
- **Priority:** P2
- **Status:** Needs decision
- **Evidence:** User-observed and signing-requirement backed during the first Beta smoke test.
- **Current behavior:** Xcode Debug and the installed Developer ID app use the same
  `com.windowranger.WindowRanger` bundle identifier but different designated requirements. macOS can
  therefore treat them as separate Accessibility clients while LaunchServices still sees the same
  bundle identifier, making handoff and permission recovery ambiguous.
- **Smallest useful outcome:** Decide whether the local Xcode product should use a clearly named
  development-only bundle identifier and app name while Stable and Beta retain the canonical public
  identity.
- **Acceptance:**
  - the installed public app and Xcode development app are unambiguous in Accessibility settings,
    LaunchServices, process inspection, and menus;
  - the required development App ID, provisioning profile, and iCloud capability are configured
    before changing the project;
  - Xcode handoff scripts quit and resume only the intended product;
  - public Stable/Beta bundle identity, preferences, update continuity, and release provenance do
    not change;
  - migration guidance avoids global TCC or LaunchServices resets and is live-tested on the
    maintainer's Mac.

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
  ID-signed, notarized, stapled Beta DMG, notarized ZIP fallback, SHA-256 checksums, provenance
  manifest, reviewed release notes, and no claim of Sparkle or Stable support.
- **Implemented groundwork:** Unprivileged GitHub Actions verification, Hardened Runtime build
  setting, Developer ID export configuration, approved Stable and construction-themed Beta DMG
  artwork, deterministic headless DMG packaging, local build/notarize/package script, draft-release
  script with local/uploaded asset verification, tracked release notes, and first-release runbook.
- **Verified evidence:** Tag `v0.1.0-beta.1`, `develop`, and `release/0.1.0` resolve to exact artifact
  commit `04b5750b1fe3b183c1259d132a0a8e985f8b4e0e`. Stable Xcode 26.6 passed clean project
  generation, non-hosted tests, static analysis, universal archive/export, exact team/bundle/signing
  checks, app and DMG notarization with zero Apple log issues, stapling, Gatekeeper assessment, DMG
  structure verification, checksums, and provenance. Manually dispatched GitHub Actions run
  [31334467211](https://github.com/windowranger/windowranger/actions/runs/31334467211) independently
  passed isolation, committed tests, Release analysis/build, Stable/Beta DMG smoke verification, and
  artifact upload for the exact commit. The private draft contains the DMG, ZIP, both checksums, and
  manifest; all five assets were downloaded again and checksum-verified. The maintainer installed
  and ran the exact signed DMG successfully after recovering the separate Accessibility trust for
  the Developer ID copy. Release-hardening commit
  `e02b34eee5ef7b1dd2150ca4eacfee383a0d16be` independently started and passed automatic
  [push run 31336143953](https://github.com/windowranger/windowranger/actions/runs/31336143953) and
  [pull-request run 31336188662](https://github.com/windowranger/windowranger/actions/runs/31336188662),
  proving both configured event paths without manual dispatch.
- **Current blockers:**
  - complete the remaining product-identity, repository-publication, manual regression,
    accessibility, privacy, and clean-package gates in `docs/release-checklist.md`;
  - configure branch/tag protection when the repository is public or GitHub Pro makes it available.
- **Publication gate:** Creating the draft is not publication. Changing repository visibility and
  publishing the reviewed draft each require explicit maintainer action at the final checkpoint.

## Done

### WR-020 — Shift private hosted verification to local hooks

- **Result:** Automatic GitHub-hosted jobs now skip while the repository is private, with an
  explicit manual dispatch retained for a deliberately billable run. Public pull requests run the
  non-hosted suite without duplicate topic-branch pushes; selected integration/release pushes add
  analysis, unsigned Release, and Stable/Beta DMG checks. An opt-in repository-managed pre-push hook
  verifies the exact pushed commit in an isolated worktree, and a separate full local command covers
  the uncredentialed integration/release checkpoint without signing, notarizing, installing, or
  launching the app.
- **Automated evidence:** Shell syntax and diff checks passed; the local quick checkpoint passed all
  445 tests with test isolation intact; and stable Xcode 26.6 passed the full local test, static
  analysis, unsigned universal Release build, and both DMG creation/verification paths. Hook
  installation/removal and exact-commit execution passed. The topic-branch push created no workflow
  run, while private pull-request run
  [31363831170](https://github.com/windowranger/windowranger/actions/runs/31363831170) completed with
  the hosted job skipped before runner allocation.

### WR-004 — Bound synced profile-library input with recovery UX

- **Result:** The atomic iCloud profile-library value now has explicit byte, profile, nested-count,
  and user-facing-name limits with validation before decode/application. Invalid remote data never
  replaces or truncates local profiles; existing oversized private-install libraries remain local,
  writes are withheld visibly, and an eligible local copy replaces rejected cloud data only through
  an explicit General Settings recovery action.
- **Automated evidence:** Fifteen focused tests cover exact boundaries, every collection limit,
  oversized bytes, long names, malformed/future versions, local preservation, safe enablement,
  remote rejection and explicit recovery. Test isolation and the complete 445-test suite passed on
  10 August 2026.

### WR-017 — Copy a focused-window diagnostic report for bug reports

- **Result:** Option-click now exposes a distributable-build focused-window report captured before
  menu presentation. The 64 KB, schema-versioned report is read-only, distinguishes failed or
  unavailable AX reads from false values, includes privacy-safe admission/workspace/layout evidence
  plus only related bounded in-memory events, and receives a final fail-closed privacy scrub.
- **Automated evidence:** Nine deterministic report tests cover managed, ignored, deferred,
  floating, excluded, minimized, full-screen, parked, stale, failed-read, no-target, privacy,
  schema/bounds, release visibility, related-event filtering, and pure rendering. Test isolation,
  an unsigned universal Release build, and the complete 435-test Debug suite passed on 10 August
  2026. The bug-report template and privacy documentation describe generation and review.

### WR-016 — Reveal menu diagnostics only with Option-click

- **Result:** Debug status-menu diagnostics are hidden during an ordinary open and appear only while
  Option is held for that opening. The decision is stateless, the unavailable file action remains
  disabled, Release retains its compile-time exclusion, and support/privacy instructions now explain
  the Option-click route.
- **Automated evidence:** Deterministic policy tests cover normal, Option, repeated, unavailable-file,
  and Debug/Release compile-boundary cases; test isolation, the focused Debug and Release checks,
  and the complete 426-test Debug suite passed on 10 August 2026.

### WR-015 — Make iCloud settings sync opt-in

- **Result:** New installations now start local-only; saved enabled/disabled choices remain intact,
  disabling immediately gates every cloud read/write while retaining local and remote data, and
  re-enabling pushes the current reusable settings. Settings, README, and privacy copy document the
  opt-in and machine-local boundaries.
- **Automated evidence:** Test isolation, five focused first-run/saved-choice/off-state/no-store/
  re-enable tests, and the complete 422-test suite passed with no failures on 10 August 2026.

### WR-006 — Reconcile the future-systems brief with implemented Tiled manipulation

- **Result:** Updated the future-systems brief and README to distinguish implemented, deterministically
  tested manual split resizing, title-bar drag-to-swap, and radial edge/corner placement from
  research-only reusable presets and any future explicit overlay editor. Signed-app behavior remains
  covered by the existing live-validation queue.
- **Automated evidence:** Test isolation passed and all 36 focused `TiledLayoutTreeTests` passed with
  no failures on 9 August 2026.

## Scan notes — not queued again

- Menu-bar, Workspace Settings, and contextual radial-menu visual QA have no unresolved P0/P1/P2
  mismatch in `design-qa.md`.
- Portable profile transfer is described as implemented in the current README and reviewed code;
  its remaining live coverage belongs to WR-001/WR-013.
- Manual Tiled split resizing and drag-to-swap already have implementation/test evidence; their
  documentation correction is recorded under Done rather than queued as an implementation request.
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
