# Code review — 2026-08-08

This review covers the current pre-release WindowManager codebase after the workspace Settings,
profiles, command wheel, menu-bar, recovery, layout, and shortcut-conflict milestones. It is a
source/static-analysis and deterministic-test review. It does not claim that macOS Accessibility
behavior, visual feel, or multi-display interactions have been live-validated.

## Method and scope

- Read all 29 production Swift files (about 21,000 lines) by subsystem, following mutations from
  the app and Settings entry points through shared model/policy code to Accessibility writes.
- Reviewed Accessibility admission/classification, ignored-window eviction, focus/activation,
  generation cancellation, parking/recovery, quit, sleep/wake, topology changes, and both display
  modes.
- Reviewed Freeform/Tiled/Accordion geometry, placement trees, floating/dialog/app-rule
  precedence, and frame-write retry/diff behavior.
- Reviewed hotkey conflict evaluation, Carbon registration ownership, suspend/reconfigure,
  recorder behavior, and command-wheel integration.
- Reviewed Settings selection/search/Undo, profile transitions and local-versus-synced storage,
  profile transfer validation/atomicity, and the Settings utility-window boundary.
- Reviewed menu-bar, radial-panel, and command-feedback lifecycle; notification/event-monitor
  removal; delayed work cancellation; weak captures; diagnostics redaction/rotation; Debug/Release
  gates; non-hosted test configuration; signing/build configuration; and LaunchServices hygiene.
- Ran the compiler's static analyzer against the non-hosted target and focused tests for each
  corrected defect. Final full-suite and signed-build evidence is recorded below.

## Findings

| ID | Severity | Finding and user impact | Evidence | Disposition |
| --- | --- | --- | --- | --- |
| CR-001 | High | A failed recovery-state write set the in-memory deduplication marker before the file existed. Every later save of the same state could then be skipped. The same happened if an external cleanup removed the cache file. After a crash or Xcode Stop, an inactive workspace window could therefore remain parked with no current recovery record. | `WorkspaceStateStore.save` previously compared only `lastScheduledState`; it did not track write completion or confirm the file still existed. | **Fixed.** Pending writes are tracked, failure clears the marker, an absent file forces a rewrite, writes remain atomic and mode `0600`, and oversized state is rejected before decoding. Deterministic tests cover failure/retry, external removal, size rejection, session rejection, atomic persistence, and permissions. Live crash/force-stop recovery remains pending. |
| CR-002 | Medium | A failed Carbon hotkey unregistration discarded its token and the next registration generation reused numeric event IDs. A stale OS-owned event could become inert indefinitely or be mistaken for a newer command if delivered through the shared handler. | `CarbonGlobalHotKeyRegistrationService.unregister` removed its reference before knowing whether `UnregisterEventHotKey` succeeded; `HotKeyManager.unregisterAll` dropped all tokens and restarted identifiers at 1. | **Fixed.** Failed tokens remain retryable, their actions are removed immediately, successful tokens are released, and event IDs are monotonic for the process. Tests cover failed cleanup, retry, replacement, suspend, and stale-ID separation without using Carbon. |
| CR-003 | Medium | Failure to install the Carbon event handler was ignored. Individual hotkey registrations could be reported as successful even though no handler could dispatch them. | `HotKeyManager.init` did not inspect `InstallEventHandler`'s result or verify the returned handler. | **Fixed.** Installation is injectable and checked. A missing/failed handler now fails closed, registers no hotkeys, reports each affected command as a nonfatal runtime issue, and logs only the safe status code in Debug. Other configuration validation remains available. |
| CR-004 | Low / hardening | Synced profile-library decoding validates the format version and normalizes identities/references, but does not impose the explicit document/count/name ceilings used by portable profile import. iCloud key-value storage has a platform limit, so this is bounded externally, but a pathological valid payload could still do unnecessary decode/normalization work. | `SettingsStore.decodedRemoteProfileLibrary` versus `ProfileTransferCodec.validate`. | **Open hardening item.** Do not reuse import limits automatically because existing profile-library limits are a product decision and a silent remote rejection could strand legitimate private-install data. Add explicit synced-library limits with migration/recovery UX before public release. |
| CR-005 | Low / Debug performance | Verbose Debug diagnostics serialize and append synchronously while holding the logger lock. This preserves ordered JSON Lines and does not exist in Release, but a slow filesystem could add Debug-only latency during a very noisy live session. | `DiagnosticLogger.log` and `RotatingFileDiagnosticSink.append`. | **Open measurement item.** Current bounded rotation and action-aware excerpts are correct. Measure a real slow session before moving writes to another queue; changing ordering during this safety review would reduce diagnostic reliability without evidence of a present bottleneck. |

## Reviewed invariants with no source defect found

- **Admission and privacy:** one central four-disposition classifier separates normal managed,
  automatic floating, deferred, and ignored windows. Verified non-normal Codex panels are rejected
  before membership, layout, focus, persistence, or recovery. Settings and command-feedback windows
  have explicit app-owned exclusions. Diagnostics sanitize field names/values and never intentionally
  include titles, documents, URLs, typed content, full paths, or window contents.
- **Focus and concurrency:** exact-focus work is generation-bound, validates the resulting window
  identity, cancels/supersedes older verification, and does not override a genuinely competing app.
  Delayed focus, wake, radial-menu, feedback, and presentation work uses cancellation plus weak
  captures. Event monitors and notification observers have paired teardown paths.
- **Recovery and displays:** wake reconciliation refreshes topology before Accessibility windows,
  coalesces notifications, uses bounded retries, and preserves abstract homes across disconnects.
  Changed WindowServer sessions discard unsafe window identities. Independent mode keeps separate
  active-workspace slots; Unified mode retains actual display affinity.
- **Layouts and rules:** only visible, eligible, non-excluded windows enter geometry. Freeform
  preserves frames. Tiled trees validate bounds and commit through one layout transaction; Accordion
  uses bounded visible edges. App exclusion, explicit per-window override, automatic dialog floating,
  and normal layout participation have a single documented precedence order.
- **Settings and profiles:** reusable definitions are iCloud-scoped while active selection,
  triggers, runtime workspace state, fingerprints, and role bindings remain local. Portable import
  fully validates before mutation, remaps every identity, adds rather than replaces, does not
  activate, and registers guarded Undo. The Settings coordinator reuses one app-owned utility
  window and excludes it from managed-window state.
- **UI surfaces:** one persistent status item owns all menu-bar modes; only typed Full-mode workspace
  buttons can switch workspaces. The radial panel and feedback overlay are nonactivating, dismiss on
  stale context/topology, and remove monitors/observers. Feedback coalesces rather than stacking.
- **Test/runtime separation:** the test bundle is non-hosted and compiles shared sources without
  `AppDelegate`. Tests inject Accessibility, hotkey, login-item, diagnostics, file-panel, file-access,
  and window-action seams. No production app is required for deterministic verification.

## Evidence boundary and remaining validation

Automated checks can prove model rules, mutation ordering, cancellation, storage boundaries, and the
absence of operational app entry points in tests. They cannot prove that every third-party app will
honor a successful Accessibility focus/frame request, that a particular monitor/notch arrangement
looks correct, or that rapid live input feels right. Normal Xcode Stop also cannot run synchronous
quit cleanup; startup recovery is the safety boundary for a hard stop.

The later live checkpoint should therefore cover: crash/Stop recovery with a parked inactive
window; a real shortcut collision with another app; rapid shortcut reconfiguration; two-display
focus/layout commands; sleep with a topology change; Settings resurfacing; profile switching;
Compact/Medium/Full transitions; and Press/Hold command-wheel interaction. Capture one bounded Debug
diagnostic excerpt for any mismatch rather than inferring from an Accessibility success code.

## Verification

- Focused recovery persistence tests: passed.
- Focused shortcut, recorder, Settings, and command-wheel tests: passed.
- Compiler static analysis of the non-hosted target: passed with no source findings.
- Test-isolation guard: passed; the Test action has no app dependency, host, or macro-expansion target.
- Complete non-hosted suite: **340 tests passed, 0 failures**. A later path-sanitization-only
  fixture edit also passed all 27 focused diagnostics tests.
- Canonical Debug: signed Apple Development build, `com.chris.WindowManager`, team `44NAD22AK6`,
  arm64. Canonical Release: same identity/team, universal `x86_64 arm64`.
- Release binary contains none of the checked Debug-only diagnostics menu/file/admission strings.
- The pre-existing system process (PID 709) and user Debug process (PID 46862) were unchanged after
  testing and builds; no Run action was used.
- LaunchServices contains only the canonical Xcode Debug and Release registrations for this bundle
  identifier. No temporary or workspace-local registration was created.
- Repository scan found no tracked build products, result bundles, logs, `.DS_Store`, secrets, or
  personal absolute home paths after sanitizing older design-QA provenance. Ignored `.build` and
  `DerivedData` directories remain local only.
