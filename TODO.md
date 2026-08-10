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

### WR-028 — Rework the Command Wheel experience

- **Type:** UX audit / potentially major change
- **Priority:** P1
- **Status:** Inbox
- **User-observed:** The current command wheel is functional and looks acceptable, but is not a
  good experience to use. Treat the next pass as an interaction and information-architecture review,
  not a cosmetic tidy-up; a major rework remains possible.
- **Expected:** Opening, understanding, navigating, and committing a contextual command should feel
  immediate and predictable while preserving truthful context validation and nonactivating behavior.
- **Next boundary:** Capture the current interaction at both levels with keyboard and pointer, then
  decide whether the existing radial model is worth refining before implementation.

### WR-030 — Investigate Battle.net focused-window compatibility

- **Type:** Compatibility research / possible bug
- **Priority:** P2
- **Status:** Inbox
- **Diagnostic-backed:** The live `net.battle.app` window is admitted as `managed-normal` with
  `AXWindow / AXStandardWindow`, WindowServer layer 0, standard controls, and successful frame and
  raise operations. Its separate App Rule excludes it from Tiled and Accordion, but that is not why
  the focus border is absent. After successful application activation, Battle.net exposes neither a
  settable window-focused attribute nor a settable application focused-window attribute, and live
  focus observation repeatedly returns no focused window. Exact focus verification therefore fails
  closed and the highlight controller cannot obtain the focused-window target it requires.
- **Expected:** Preserve the verified Codex transient-window exclusion and the central admission
  boundary. Before changing behavior, determine whether a narrowly proven fallback can identify the
  one main, visible, layer-0 window of an active application without guessing among multiple windows
  or weakening focus verification globally.
- **Next boundary:** Research and test a Battle.net-specific observation fixture or bounded generic
  fallback; do not implement it until its ambiguity and competition behavior are understood.

## Live validation

### WR-033 — Respect the auto-hidden Dock edge after leaving a game

- **Type:** Platform geometry bug
- **Priority:** P2
- **Status:** Live validation
- **Diagnostic-backed cause:** Leaving the Games workspace made AppKit reserve a 59-point bottom
  Dock reveal strip even though the user's Dock preference was auto-hide. WindowRanger correctly
  re-sampled that smaller `visibleFrame`, so this was not stale cached or restoration geometry.
- **Implemented:** Display refresh now makes the user's Dock hiding preference authoritative only
  for the configured bottom, left, or right Dock edge. Auto-hide restores that edge to the full
  display boundary while preserving AppKit's other menu-bar, camera, and safe-area exclusions. A
  visible Dock continues to use AppKit's exclusion. The existing layout signature detects preference
  changes during normal polling and reflows without a WindowRanger restart.
- **Automated evidence:** Pure bounds-policy tests cover the observed bottom inset, visible Dock,
  left/right Dock orientations, and a fail-safe unknown orientation.
- **Installed evidence:** The signed Debug daily build for `8b649ad3f3f9` was installed and
  relaunched from `/Applications/WindowRanger.app`; its Apple Development signature, embedded clean
  revision, version `0.1.0 (1)`, and running executable path were verified.
- **Remaining live boundary:** In a signed Debug build, verify auto-hide on fills the Dock edge,
  auto-hide off stops above the visible Dock, toggling either way reflows without relaunch, and a
  full-screen game exit cannot leave the 59-point strip behind on either monitor.

### WR-032 — Align Settings list actions and App Rule workspace values

- **Type:** Settings polish
- **Priority:** P2
- **Status:** Live validation
- **Implemented:** Profiles, Workspaces, and App Rules now use one regular native control size and
  shared vertical padding for their master-list action rows. Their shared native bordered-button
  component places every SF Symbol on the same 16-point canvas so the chrome has identical bounds.
  The App Rule workspace picker uses a fixed trailing-aligned control column matching the switches
  below it. The App Rule header now uses an explicit trailing control group so its Enabled label is
  right-aligned directly beside the native switch instead of stretching into the middle of the row.
- **Automated evidence:** Layout constants are covered alongside the existing Settings metrics;
  the complete 465-test non-hosted suite passes after the follow-up alignment changes.
- **Installed evidence:** The signed Debug daily build for `8b649ad3f3f9`, including all three
  alignment refinements, is installed and running from `/Applications/WindowRanger.app`.
- **Remaining live boundary:** In the installed merged build, compare all three master-list action
  rows and confirm their buttons have one visual height. Confirm short and long App Rule workspace
  names remain right-aligned at wide and compact Settings widths, and confirm the Enabled label
  remains adjacent to its switch, before marking this Done.

### WR-029 — Optionally highlight the focused window

- **Type:** Feature
- **Priority:** P1
- **Status:** Live validation
- **Implemented:** General Settings now has an off-by-default, per-Mac option with its own local
  border colour, defaulting to white. It monitors only while enabled and draws a nonactivating,
  click-through panel. Tiled and Accordion layouts reserve four points at screen edges while the
  option is enabled so the border remains visible; Freeform geometry stays user-controlled. Two
  independent local filters can restrict the border to Tiled workspaces and to workspaces containing
  multiple managed windows; unproven workspace context hides the border conservatively. A
  conservative OS-generation default controls the corner radius: macOS 27 and later use the
  maintainer-validated 16-point radius while earlier releases retain the 10-point fallback. Each App
  Rule can supply a local, non-synced radius override for its bundle identifier. Policy excludes
  WindowRanger-owned windows, apps identified as games through the same public bundle metadata used
  by full-screen safety, and any
  window whose non-full-screen state cannot be confirmed. Lifecycle wiring reconciles display
  changes and removes the border for full-screen game sessions, sleep, inactive login sessions,
  disabling, and quit.
- **Automated evidence:** The unsigned Debug app target builds, test isolation passes, and the full
  465-test non-hosted suite covers local enablement, colour, filter and per-app radius persistence,
  Settings search, OS-generation fallback and override precedence, independent and combined
  workspace-filter eligibility, declared-game exclusion, conservative missing-context and
  full-screen handling, coordinate conversion, the four-point managed layout inset, and the
  nonactivating panel policy.
- **Installed evidence:** The signed Debug daily build for `1edb85207be4-dirty`, including the
  dedicated colour picker, four-point layout margin, both workspace filters, automatic radius
  policy, and local per-app radius controls, was installed and relaunched from
  `/Applications/WindowRanger.app`; its Apple Development signature, version `0.1.0 (1)`, embedded
  revision, and running executable path were verified. The maintainer previously live-validated the
  initial white-border behavior and colour/margin refinement, then confirmed the workspace filters,
  per-app radius override, and 16-point macOS 27 automatic default work as intended. The follow-up
  declared-game exclusion is installed in the signed Debug daily build for `8b649ad3f3f9` but still
  needs live validation with a detected game window.
- **Remaining live boundary:** Enable **Highlight the focused window** in General Settings and
  confirm the border tracks real focus, movement, and resizing on both displays without taking focus
  or intercepting clicks. Confirm the white default and custom colours, the Tiled/Accordion edge
  margin on both displays, unchanged Freeform geometry, Settings, declared-game and full-screen
  exclusion, returning a per-app radius override to Automatic,
  disable/reenable, and sleep/wake before marking this Done.

### WR-005 — Measure Debug diagnostic logging under slow storage

- **Type:** Performance measurement
- **Priority:** P3
- **Status:** Live validation
- **Source:** `docs/code-review-2026-08-08.md`, CR-005
- **Controlled evidence:** A deterministic 100-record noisy action measured 4.2 ms with the memory
  sink and 311.5 ms with 2 ms latency injected into every ordered append (3.11 ms per record), while
  preserving exact JSONL sequence 1...100. This confirms synchronous cost tracks storage latency;
  it does not establish that the normal Debug log volume or the maintainer's filesystem causes a
  perceptible interaction problem.
- **Automated evidence:** Test isolation and the complete 446-test suite passed on 10 August 2026.
- **Private CI evidence:** [PR #7](https://github.com/windowranger/windowranger/pull/7) uses WR-020's
  exact-commit local pre-push gate; its hosted pull-request job skips successfully before runner
  allocation while the repository remains private.
- **Remaining live boundary:** Gracefully quit the installed copy, run the intended signed Debug
  build, reproduce a sustained noisy window/workspace session on the target slow-storage setup, and
  record command latency plus diagnostic event rate. Keep ordered synchronous writes unless that
  real session demonstrates a user-visible bottleneck.

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
- **Completed groundwork:** Public Beta distribution, local-first signing/notarization, release
  provenance, protected integration/stable branches and protected release tags.
- **Remaining scope:** Accessibility migration guidance, Sparkle, Homebrew Stable distribution, and
  update/rollback failure handling.
- **Gate:** Each later release still requires explicit maintainer approval.

## Done

### WR-031 — Prioritise open apps when adding an App Rule

- **Result:** The Add Application Rule picker groups open apps first and initializes a new rule from
  the app's existing workspace only when its managed windows agree on one unambiguous assignment;
  closed, windowless, invalid, and split-workspace cases retain **Use current workspace**.
- **Evidence:** Test isolation and all 461 non-hosted tests pass, the signed universal Debug daily
  build for `a39b372ee895-dirty` was installed and verified, and the maintainer confirmed the picker
  and inherited assignment behave as intended on 10 August 2026.

### WR-027 — Tidy Settings across wide and compact layouts

- **Result:** Settings now follows a consistent native macOS layout grammar with a permanent sidebar,
  common master-list widths, aligned controls and actions, compact list/detail navigation, semantic
  system surfaces, and stable two-line list rows after scrolling.
- **Evidence:** All seven panes render at wide and compact sizes, with wide Light and Dark fixtures;
  the complete 451-test non-hosted suite and local quick gate pass. The maintainer validated the full
  correction pass and recycled-row scrolling in the signed daily build on 10 August 2026.

### WR-025 — Reflow Settings across useful window sizes

- **Result:** Settings resize continuously down to 760 x 560. Wide collection panes retain their
  master/detail layouts; compact Profiles, Workspaces, and App Rules use disclosure rows and titled
  detail views with Back navigation; narrow controls reflow without clipping.
- **Evidence:** Deterministic layout and AppKit window-policy tests pass in the complete 451-test
  suite. The maintainer validated resizing, compact navigation, selection retention, and return to
  the wide layout in the signed daily build on 10 August 2026.

### WR-024 — Show exact build identity in Settings

- **Result:** Settings now shows the app version, build number, source commit, and Dev marker in an
  unobtrusive sidebar footer. Daily builds append `-dirty` when their working tree differs from the
  displayed commit; clean distributable builds embed their exact source commit.
- **Evidence:** The complete 451-test suite passed, an unsigned app build embedded the expected
  values, and the maintainer confirmed the footer in the signed daily build on 10 August 2026.

### WR-022 — Make the Settings window resizable and large enough for its content

- **Result:** Settings now uses stable explicit AppKit minimum/maximum constraints rather than
  allowing a tall active pane to replace them. The detail hierarchy follows available geometry,
  undersized restored frames grow safely, and larger frames remain user-controlled.
- **Evidence:** Focused AppKit/SwiftUI host regressions and the complete 451-test suite passed; the
  maintainer confirmed resizing and the corrected Profiles layout in the signed daily build on
  10 August 2026.

### WR-023 — Delegate windowranger.com DNS to Cloudflare

- **Result:** Added `windowranger.com` to Cloudflare on the Free plan, preserved the existing
  Namecheap parking and email-forwarding DNS records, and changed the registrar delegation to the
  assigned Cloudflare nameservers. DNSSEC remains disabled with no DS record.
- **Evidence:** Cloudflare reported the zone active on 10 August 2026. Cloudflare's API retained all
  eight discovered A, CNAME, MX, and TXT records; public recursive resolvers returned the assigned
  `carmelo.ns.cloudflare.com` and `magnolia.ns.cloudflare.com` delegation, the proxied apex and
  `www` addresses, all five Namecheap forwarding MX records, and the matching SPF TXT record.

### WR-021 — Allow manual workspace moves to override App Rules

- **Result:** App Rule workspace assignments now provide initial and reset placement without
  permanently locking an individual window. Manual moves survive routine refreshes; moving back
  clears the override; rule/profile changes, resets, and reopen boundaries reapply the assignment.
- **Evidence:** Deterministic tests cover the decision boundaries, the complete isolated 448-test
  suite passed, and the maintainer confirmed the behavior in the signed daily build on 10 August
  2026.

### WR-018 — Publish the first GitHub Beta

- **Result:** Made `windowranger/windowranger` public and published `v0.1.0-beta.1` as a GitHub
  prerelease on 10 August 2026, preserving the exact signed, notarized artifact tag and all five
  checksum/provenance-verified assets. Enabled private vulnerability reporting, secret scanning and
  push protection; protected `main`, `develop`, and `v*` tags.
- **Evidence:** The public release is
  [WindowRanger 0.1.0 Beta 1](https://github.com/windowranger/windowranger/releases/tag/v0.1.0-beta.1)
  at artifact commit `04b5750b1fe3b183c1259d132a0a8e985f8b4e0e`. Immediately before publication,
  the downloaded app and DMG passed checksums, provenance, signature, stapling, notarization, and
  Gatekeeper checks; the publication-preparation checkpoint passed all 446 tests.
- **Known Beta limitations:** Remaining manual regression, accessibility, privacy, clean-user,
  LaunchServices, update, and rollback work stays explicit in the release notes and checklist and is
  not Stable evidence.

### WR-011 — Product identity and public project hygiene

- **Result:** Confirmed first-Beta identity, copyright, artwork provenance, Apple-only dependencies,
  MIT reference notices, intended commit authorship, and a redacted all-history secret/privacy scan.
  Published contributor/governance/support documents and private security and conduct reporting
  paths before making the repository public.

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
