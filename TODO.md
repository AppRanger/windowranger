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

### WR-057 — Preserve each window through partial post-login recovery

- **Type:** Lifecycle recovery bug
- **Priority:** P1
- **Status:** Live validation
- **Diagnostic-backed:** On 2026-08-15, the signed WR-055 candidate correctly retained 13 managed
  windows and its Quick App at display sleep. At 06:45 local time, three wake attempts saw the
  tracked applications return successful but empty Accessibility window lists and completed safely
  in degraded mode. Three seconds later, one unrelated window became visible; that single nonempty
  global snapshot dropped the recovery guard and evicted 11 still-missing windows. When those apps
  became readable roughly five seconds later, they were rediscovered from the active workspaces;
  Ghostty was therefore tiled as an ordinary workspace window instead of retained as the Quick App.
  A later wake in the first WR-057 candidate preserved every window's screen and workspace, but one
  of three windows in a BSP partition became readable 261 milliseconds before its two peers. The
  background layout reconciled the saved tree against that one eligible leaf, expanded it to the
  full display, then appended the other two to the trimmed tree when they returned. All three frame
  writes succeeded, proving the changed positions came from a destructive partial-tree solve rather
  than macOS failing to accept the intended geometry.
- **Expected:** Recovery authority is per pre-sleep window and owning process. An exact returning
  window releases only itself and cannot make another process's empty or partial snapshot
  authoritative. A still-running process may confirm a genuinely missing window only with two
  matching successful snapshots after a 15-second wake grace; a failed read resets confirmation,
  while process termination remains immediately authoritative. A late-returning Quick App reapplies
  its retained presented or WindowRanger-owned application-hidden state before ordinary layout. A tiled partition containing
  any still-protected pre-sleep participant receives no tree reconciliation or geometry writes;
  unrelated complete partitions may recover immediately. Once every participant returns, or a
  missing participant becomes authoritative, the intact or deliberately pruned BSP tree is solved
  once. Wake geometry must not be interpreted as a manual tiled move or resize.
- **Acceptance:** Pure recovery tests cover global-empty wake, one-app-at-a-time return, a different
  same-process window, stable missing-window confirmation, failed reads, and process termination.
  Focused lifecycle/Quick App tests and the complete non-hosted suite pass. Repeat a two-display
  overnight lock/login with the Quick App hidden, an asymmetric BSP tree, and ordinary apps spread
  across inactive workspaces.
- **Automated evidence:** All 61 focused lifecycle/Quick App tests and all 586 non-hosted tests pass,
  including test isolation. Release static analysis, the unsigned universal Release build, and both
  Stable/Beta DMG smoke packages pass. The installed `bbac9b42ae32-dirty` candidate supplied the
  partial-BSP diagnostic evidence but does not contain the resulting partition guard. A replacement
  Apple Development universal Debug candidate builds and strictly verifies with CDHash
  `980e43044aaa1f19c1964ed8c810a00cd4ad16d1` and bundle identifier
  `dev.appranger.WindowRanger`; the two-display overnight lock/login check remains.
- **Installed evidence:** With explicit maintainer approval, the replacement signed universal Debug
  candidate for `bbac9b42ae32-dirty` is installed and running from
  `/Applications/WindowRanger.app`. Its Apple Development signature, Team ID `44NAD22AK6`, bundle
  identity, embedded revision, two architectures, running executable path, and exact CDHash
  `980e43044aaa1f19c1964ed8c810a00cd4ad16d1` were verified. The prior daily copy remains at the
  repository-defined non-launchable rollback path. Fresh diagnostics show live Accessibility
  discovery, a three-window asymmetric BSP solve, and successful frame writes; no lock/wake cycle
  has yet exercised the new partial-tree guard.

### WR-056 — Keep Accessibility permission status current in Settings

- **Type:** Settings state bug
- **Priority:** P2
- **Status:** Live validation
- **User-observed:** General Settings can continue to show Accessibility as Required after access
  has already been granted directly in macOS System Settings rather than through WindowRanger's
  Grant Access button.
- **Expected:** The status reflects the running app identity's current Accessibility trust whenever
  General Settings appears or WindowRanger becomes active. While the pane is visible and access is
  still missing, it performs a lightweight bounded-frequency trust check so an external grant is
  reflected without closing or reopening Settings. It must not repeat the system prompt.
- **Acceptance:** An injected monitor test proves false-to-true external grants and later revocation
  are reflected without requesting permission. Focused Settings tests, the complete non-hosted
  suite, and an unsigned universal app build pass; signed live validation remains required.
- **Automated evidence:** All 21 focused Utility Settings tests and all 577 non-hosted tests pass;
  test isolation and the unsigned universal Debug app build also pass. With explicit approval, the
  signed universal Debug candidate was installed, its signature/running path were verified, and its
  startup Accessibility geometry write succeeded. Live Settings status confirmation remains.

### WR-055 — Preserve workspace and Quick App ownership across screen lock

- **Type:** Lifecycle recovery bug
- **Priority:** P1
- **Status:** Live validation
- **Diagnostic-backed:** On 2026-08-14 the Mac remained awake while both displays turned off from
  20:31:04 to 20:33:44. During the display-off transition, Accessibility returned successful empty
  window lists for every tracked application. WindowRanger treated those snapshots as authoritative,
  evicted 13 tracked windows, and cleared the hidden Ghostty Quick App session as a display-topology
  change. Wake reconciliation then rediscovered Safari, Ghostty, and Codex as ordinary members of
  active workspace 2 and reported a zero-mismatch layout after tiling all three.
- **Expected:** Screen lock, session inactivity, and display sleep suspend background discovery and
  invalidate stale work before empty Accessibility snapshots can erase workspace membership. A
  coordinated wake must retain tracked windows across non-authoritative global-empty snapshots,
  preserve one exact Quick App session, and restore its presented or WindowRanger-owned
  application-hidden state before ordinary
  workspace layout. A genuine, repeated global-empty snapshot while fully active may still remove
  windows normally.
- **Acceptance:** Pure lifecycle tests cover session suspension, first-empty and wake-time snapshot
  deferral, later authoritative removal while active, and Quick App retention across display sleep
  and wake topology changes. The focused lifecycle/Quick App tests and complete non-hosted suite
  pass. Signed two-display lock/wake validation remains required before Done.
- **Automated evidence:** Test isolation, all 577 non-hosted tests, Release static analysis, the
  unsigned universal Release build, and both Stable/Beta DMG smoke packages pass. With explicit
  approval, signed universal Debug build `1ad56bb3d128-dirty` was installed and its startup recovery
  verified; the two-display lock/wake result still awaits user confirmation.

### WR-050 — Add a profile-aware Quick App

- **Type:** Feature
- **Priority:** P2
- **Status:** Live validation
- **Requested outcome:** Each profile may assign at most one application as a Quake-style Quick App.
  A configurable global shortcut, initially Control-Option-Backtick, presents that app over the
  current work and toggles it away. Moving focus to another application also hides it. The presented
  window optionally animates from a configurable screen edge, defaulting to the top, and uses a
  configurable proportion of the interaction display, defaulting to 80 percent.
- **Smallest useful scope:** Store one optional bundle identifier and one presentation-size setting
  in each reusable profile; store the shortcut in the existing global shortcut system. Resolve one
  unambiguous eligible standard window for the configured app, activate and place it on the current
  interaction display, and restore its prior frame/visibility state when toggled or when genuine
  user focus moves elsewhere. If no usable window exists, open the configured application and wait
  a short bounded interval for one eligible window. Do not choose among multiple ambiguous windows,
  change native macOS Spaces, or broaden normal window admission.
- **Safety boundaries:** The Quick App window remains outside ordinary workspace layout,
  inactive-workspace parking, focus cycling, reset, and persistence while presented. Profile changes,
  app/window termination,
  uncoordinated display changes, system sleep, shutdown, shortcut reconfiguration, and superseding
  commands must cancel or safely restore a current session. A lock/display-sleep transition instead
  retains the exact session until coordinated wake recovery. Programmatic activation must not be
  mistaken for a user focus departure. Tests stay behind injected adapters and never register a real
  hotkey or move live windows.
- **Acceptance:** Focused tests cover profile isolation, shortcut collisions, 80-percent default and
  clamping, toggle show/hide, focus-loss hide, exact-window ambiguity, geometry on non-origin and
  multi-display frames, interrupted animation/session generations, and restoration boundaries. The
  complete non-hosted suite and universal Debug build pass; final behavior remains in Live validation
  until a signed build is exercised with a real assigned app on at least two profiles.
- **Implemented:** Profile storage/clone/transfer, a unified Applications settings list where each
  bundle has either normal App Rules or the one optional Quick App, explicit confirmed conversion
  between modes, visible list summaries, an intent-led mode selector, shortcut and behavior context,
  a focused Quick App presentation editor, safer destructive actions, profile context, and a useful
  empty state. Application removal uses the one consistent delete control in the Applications list.
  The installed-app picker closes when an app is selected; Quick App provides 25–100
  percent height/width control and optional animation from the Top, Bottom, Left, or
  Right with Top enabled by default, global shortcut recording with Control-Option-Backtick default,
  an edge expansion/collapse that remains within the chosen display, contextual
  guidance for apps that do not resize smoothly, exact-window
  ambiguity feedback, focus-loss hide, focus restoration on shortcut hide, and engine exclusions for
  layout/parking/focus/reset/background persistence. Profile changes, sleep, termination, window
  disappearance, and newer animation generations clear or restore the session safely. When an
  authoritative refresh replaces the exact Quick App window during a native tab switch, ownership
  follows only one newly admitted same-process window for that bundle; ambiguous replacements still
  clear the session instead of guessing. Startup now claims one unambiguous configured Quick App
  before initial workspace layout: a meaningfully visible window is presented immediately on its
  current display, while an exact WindowRanger-owned window whose application remains hidden stays
  hidden. Multiple matching
  windows remain unclaimed.
- **Diagnostic-backed bug:** On 2026-08-14, switching tabs in a presented Ghostty Quick App replaced
  window `1081:94` with `1081:95`. The successful AX snapshot evicted the old identity, cleared the
  Quick App session, and the normal background layout then tiled the replacement into the active
  workspace. Chronicle pinned the visible reproduction timing; structured diagnostics established
  the identity transition and frame write.
- **Diagnostic-backed startup bug:** On 2026-08-14, restart session
  `FA37B094-DA96-45DD-842C-3FBCB81CA3E0` admitted Ghostty window `1081:95`, assigned it to active
  workspace 2, and changed its frame from `12,296;3336x1110` to the workspace's tiled
  `1683,34;1673x1380` before the first Quick App shortcut restored its presentation. The configured
  window must instead be claimed before the initial workspace layout.
- **User-observed hide/layout bug:** On 2026-08-19, Ghostty as the Bottom Quick App on the
  ultrawide accordion remained visible after hide and appeared to join that layout. Session
  `0C0397F2-7A28-43B1-BA64-865170E0E380` shows window `3006:9484` correctly excluded from
  accordion (3→2) while the session exists, then immediately re-entering as a third accordion
  member when Settings presentation edits emitted `configuration-changed` and cleared the
  session. A 1x1 off-union park candidate was tried and rejected: Ghostty clamped to a
  `3586x33` title-bar strip at `254,34`, which was worse than the original park. Same-bundle
  direction, size, and animation edits now keep the existing session instead of restoring the
  window into the current workspace layout.
- **Diagnostic-backed overhaul:** On 2026-08-20, Bottom hide reported a successful position write
  to `(3839,2638)` while Chronicle still showed Ghostty's title strip, proving that AX request
  acceptance was not the visibility postcondition. A portrait display to the left overlapped the
  old Left retraction path, so that path could move the Quick App onto the neighbouring monitor.
  Top with animation disabled logged `animated=false`, yet show still moved the window directly
  from its off-screen parked frame to the presented frame, allowing a receiving-app transition to
  remain visible. The first overhaul model stopped using off-screen parking: animation collapsed
  within the selected edge, hide minimized the exact owned window, and no-animation frame writes
  suppressed receiving-app position transitions. Minimize and final-frame results were read back
  into diagnostics, with a WindowServer-bound identity marker preventing arbitrary minimized-window
  claims after a crash.
- **Diagnostic-backed timing fix:** The first installed overhaul candidate showed that Ghostty accepts
  both minimize and unminimize requests before its Accessibility minimized state changes. Immediate
  readback therefore produced false hide/show failures even though the requested transition arrived
  shortly afterwards. Both paths now use the same generation-safe, bounded confirmation wait,
  restore a safe state on timeout, and log the number of confirmation attempts.
- **User-observed system-animation gap and implemented follow-up:** The exact-window hidden state was the native macOS Dock
  minimized state, so macOS still supplies its own minimize/restore animation even when Quick App
  animation is disabled. That does not meet the expected meaning of **No animation**. Accessibility
  does not expose a separate animation-free exact-window visibility state. Quick App now uses AppKit
  Hide/Unhide instead: the exact window remains the sole geometry, identity, and recovery target,
  while every window belonging to that application follows the application-wide hidden state.
  WindowRanger persists and restores only application hiding it confirmed and owns; legacy
  minimized-window markers never grant permission to unhide an application.
- **Diagnostic-backed Hide/Unhide timing fix:** In installed session
  `6A673870-B954-41BA-88C4-423D4B450FE7`, Ghostty returned `false` from both AppKit Hide and Unhide
  even though `isHidden` changed immediately afterwards. WindowRanger interpreted the method return
  as rejection, so the first shortcut changed background/hidden state but left the toggle
  incomplete and the second shortcut finished it. A matching live process and bundle now make the
  request dispatchable; only the bounded observed `isHidden` postcondition decides success.
- **User-observed focus-border sizing gap:** After the Hide/Unhide overhaul was accepted, the
  presented Quick App still used the complete display usable bounds while the optional focus border
  extended beyond that frame. Quick App presentation now reuses the focus border's established
  four-point screen-edge clearance when the border is enabled. The same safe bounds cover show,
  animation, startup, wake recovery, native-tab replacement, and hide-failure restoration; changing
  the border setting while Quick App is visible immediately reapplies its final frame without
  changing focus or session ownership.
- **Approved launch-on-shortcut follow-up:** On 2026-08-20, the maintainer changed the original
  no-launch boundary: pressing the shortcut with no usable configured-app window must launch the app
  and then present its first unambiguous eligible window. Launch Services is now asked to open and
  activate the app so applications whose normal reopen handling is foreground-dependent create a
  window. A generation-bound watchdog performs read-only discovery after
  200 ms and retries at most eight times at 150 ms intervals, allowing the exact window to be claimed
  before ordinary layout writes. Missing installations, launch errors, timeouts, profile changes,
  sleep, shutdown, and multiple eligible windows fail safely with explicit feedback.
- **Automated verification:** Focused DropDownAppTests cover same-bundle presentation edits,
  in-display collapse geometry for every edge, exact hidden-session recovery boundaries, and
  backward-compatible persistence, including bounded application Hide/Unhide confirmation and
  fail-closed handling of legacy minimized-window ownership. Border-aware presentation coverage
  proves that the four-point clearance applies only while the focus border is enabled and that the
  configured size fraction is calculated inside those safe bounds.
  Launch-watchdog policy coverage proves successful discovery and ambiguity return to the ordinary
  exact-window toggle path, missing windows retry with a decreasing budget, and the final attempt
  stops rather than polling forever. The launch contract also proves normal activation remains
  enabled so a windowless application receives its reopen behavior.
  All 27 focused tests, test isolation, and all 594 non-hosted tests pass; this safe
  verification did not build, launch, sign, install, stop, or automate WindowRanger.app.
- **Live validation:** The signed daily build was installed with explicit approval and Ghostty native
  tab replacement, focus-loss hide, and subsequent toggles were confirmed working. In signed
  universal Debug build `9402d3c594c4-dirty`, a visible Ghostty window was also claimed on restart
  and went directly to its Quick App presentation instead of first joining and reflowing the current
  workspace; the user confirmed the result. The final exact-window minimize overhaul candidate
  `4fde4ed99360-dirty` (CDHash `21f1986535ae61f9394e0b3ac78231cd826dae8c`) is installed as a
  signed universal Debug build and running from `/Applications/WindowRanger.app`. Fresh Ghostty
  diagnostics confirm Top with animation disabled hides as the exact minimized window, then shows
  at the exact requested frame with no animation; minimize and unminimize each required one bounded
  confirmation retry, with no false failure. That candidate was superseded after the user rejected
  the native Dock animations. The first Hide/Unhide candidate exposed AppKit's misleading `false`
  return values and was superseded. The corrected candidate `4fde4ed99360-dirty` (CDHash
  `e183c7b92dbcedb9b32e342a8a542e5f09f10d79`) is installed, strictly verified, and running from
  `/Applications/WindowRanger.app`; fresh startup diagnostics confirm Ghostty was claimed and placed
  as a visible Quick App without being hidden. Session `0DD9FF29-1721-4785-AD0A-18CF42D74934`
  then confirmed focus-loss hiding in one observation attempt with `isHidden == true`. The user
  confirmed the corrected behavior as perfect; the same session records one-press shortcut hide/show
  pairs for Bottom, Left, and Right, with animation both enabled and disabled, every transition
  confirming application visibility in one attempt and every show matching its requested frame.
  The focus-border sizing follow-up is installed in signed universal Debug build
  `fc5f92417713-dirty` (CDHash `d5480d67495e4ce75a9d9f1ba8d641dce6198320`) and running from
  `/Applications/WindowRanger.app`; startup session `F1A7DBFF-A4DD-41C8-A36C-79DBA9C33451`
  confirms focus-border monitoring started and the visible Ghostty Quick App accepted its startup
  geometry write. The same session records the expected inset Top frame at `4,34;3832x1266`,
  matching requested frames through repeated one-press hide/show pairs, and the user confirmed the
  result looks great. A live enable/disable resize was not separately observed.
  With explicit approval, the launch-on-shortcut follow-up is now installed in signed universal
  Debug build `73dcb53aa9ba-dirty` (CDHash
  `3ca219b97fe4ec11c89f25ae912312c2c1f0eb53`) and running from
  `/Applications/WindowRanger.app`. Its embedded revision, Apple Development signature, Team ID
  `44NAD22AK6`, bundle identity, two architectures, and running executable path were verified.
  Fresh startup session `493B3485-260E-4644-A52D-227F2D42F6F2` confirms the two-display topology,
  live Accessibility discovery, and a clean engine start. Launching and presenting Ghostty from a
  fully quit state then exposed the non-activating launch gap: correlations `action-e28a3612` and
  `action-fe25bdd8` each show Launch Services accepting the request and the watchdog exhausting with
  no eligible window, while the Ghostty process started at the first request. The launch request now
  permits normal activation so Ghostty receives the reopen behavior that creates its first window;
  the replacement signed universal Debug build remains `73dcb53aa9ba-dirty`, now with CDHash
  `0e101cfc47629c4bcbea036923d42f4fdac265a9`. Its signature, Team ID, bundle identity, two
  architectures, embedded revision, and running Applications path were verified. Fresh startup
  session `7005F9C3-9032-483F-9147-D67488B6925E` confirms a clean two-display engine start; the
  repeat fully-quit shortcut test remains required.
  Broader feature completion still requires exercising a
  real assigned app across at least two profiles. Hidden startup and ambiguous multiple-window
  startup remain automated, fail-closed coverage rather than separate live observations.

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

## Done — command wheel pass

### WR-047 — Keep Globe/Fn monitoring off the ordinary input path

- **Type:** Input-safety bug
- **Priority:** P1
- **Status:** Done
- **Diagnostic-backed cause:** With Hold Globe/Fn enabled, World of Warcraft kept a stable frame
  rate but delayed keyboard and mouse-button responses. The active session tap placed every ordinary
  input event behind WindowRanger's main run loop; Quartz timeouts then caused automatic re-enablement
  of the same blocking filter. Borderless play did not engage the native-fullscreen guard.
- **Implemented:** Ordinary input is now observed by a passive tap. A dedicated user-interactive run
  loop fast-passes ordinary keys and filters only the synthetic Globe event during an accepted hold;
  interruption stops and fails open. Publicly declared foreground games suspend the optional
  Globe/Fn and workspace-swipe monitors even when borderless, without broadening geometry safety.
- **Evidence:** The focused 120-test suite, complete 533-test suite, and universal Debug build pass.
  The signed Debug daily candidate `f143af57c9a1-dirty` was installed with verified identity,
  signature, revision, and running path. With Hold Globe/Fn enabled, the user repeated the World of
  Warcraft test and confirmed the input lag was fixed.

### WR-045 — Focus the pointer window before opening the command wheel

- **Type:** UX / interaction targeting
- **Priority:** P1
- **Status:** Done
- **User-observed:** The command wheel controlled the existing focused window even when the pointer
  was deliberately over a different window. The requested outcome is for opening the wheel to focus
  and target the controllable window directly under the pointer. Live validation then found that an
  already-focused pointer window opened normally, while an unfocused pointer window was raised but
  the wheel never appeared.
- **Diagnostic-backed follow-up:** The pointer-focus request successfully activated and confirmed
  the intended window, but the resulting `NSWorkspace` application-activation notification ran the
  global Globe/Fn and radial-trigger cancellation path before the delayed context presentation.
- **Implemented:** Press-to-Toggle and the accepted Hold-to-Show presentation now resolve the actual
  frontmost WindowServer surface beneath the current pointer. An eligible tracked normal window is
  sent through the established exact-focus pipeline before a fresh wheel context is captured. The
  resolver never clicks through a front panel or ineligible window; desktop, WindowRanger/transient
  UI, untracked or hidden windows, and failed focus safely retain the established focused-window
  fallback. The exact current application activation generated by that pointer-focus transaction
  preserves its pending Globe/Fn or shortcut gesture; a different process, expired deadline, or
  superseded focus generation still cancels. A second toggle or lifecycle cancellation invalidates
  an in-flight open request.
- **Automated evidence:** Pure front-to-back tests cover overlapping eligible windows, an ineligible
  front surface blocking a covered window, nonzero-layer panels, desktop misses, preservation of
  the current pointer-focus activation, and cancellation for a different process, expired deadline,
  or superseded generation. The focused diagnostic suite passes 45 tests; local quick verification
  passes all 525 non-hosted tests, and the unsigned universal Debug app compiles successfully.
- **Live result:** The signed Debug candidate was exercised against focused and unfocused pointer
  windows. After the activation-cancellation correction, the intended window comes forward and the
  wheel opens and controls it normally; the user confirmed the path was working.

### WR-044 — Add Loop-style Freeform window placement

- **Type:** UX / window command
- **Priority:** P2
- **Status:** Done
- **User-observed:** The contextual command wheel omitted Resize / Place while the active workspace
  was Freeform; the requested outcome is Loop-style visual movement for Freeform windows.
- **Implemented:** A focused eligible Freeform window now gets the same eight compass-positioned
  Place targets as the Tiled wheel. Edges resolve to usable-display halves and corners to quarters;
  hover shows the exact single-window target frame and performs no Accessibility write. Commit
  revalidates focused window, workspace, display bounds, frame and expiry, changes only that
  window's frame through the shared dispatcher, confirms the receiving app retained it, then updates
  saved Freeform geometry/display affinity and registers exact-frame Undo/Redo. It never creates or
  mutates a Tiled tree. Tiled structural placement and Accordion resize behavior are unchanged.
- **Automated evidence:** Pure frame tests cover halves, quarters, odd display dimensions and
  external-display origins; the focused command-wheel and visual suites pass 114 tests with
  contextual catalogue, preview, command and history coverage, and local quick verification passes all 522
  non-hosted tests.
- **Live result:** The signed Debug candidate exposed and executed the Freeform placement ring; the
  user confirmed the Loop-style movement was working before continuing with focus and visual work.

### WR-028 — Rework the Command Wheel experience

- **Type:** UX and interaction correction
- **Priority:** P1
- **Status:** Done
- **User-observed:** The centre was too small for its title/state content; workspace children showed
  blank boxes or repeated action symbols; and travelling naturally from an inner group on one side
  to one of its outer children on the other side could collapse or replace the group when the
  pointer crossed the centre or another inner wedge. Live testing of the installed Debug candidate
  also found that an accepted Globe/Fn hold closed the wheel by itself after about ten seconds. A
  later screenshot showed long generated labels painting across the inner/outer wedge boundaries,
  and the neutral centre X did not make its cancel meaning clear. Live review of the contained-label
  candidate then showed uneven optical alignment from mixed icon/text stack heights, disclosure
  marks pushing group symbols off-centre, and repeated profile glyphs that were not distinguishable.
  A further live screenshot showed every disclosure chevron pointing right rather than toward its
  wedge's outer-ring destination. The next installed candidate showed position-derived numeric
  badges even for letter-keyed workspaces, and direct Previous/Next attempts dismissed on Globe/Fn
  release without changing workspace. The same screenshot was captured in Freeform, where the
  contextual catalogue intentionally omitted Resize / Place. After the functional fixes passed live
  validation, the user selected the action-first icon exploration: framed half/corner occupancy for
  Place Window, distinct transfer/navigation metaphors, traversal-aware Previous/Next, layered
  Profiles, scoped reset symbols, and a split-pane Layout Type symbol. Live review of the first icon
  candidate then found that Layout Type remained generic instead of reflecting the workspace's
  current layout, and requested an Accordion glyph with a visibly wider central pane. Live testing
  of that candidate then found that many visible buttons appeared to do nothing when clicked while
  the wheel was open from a held Globe/Fn gesture.
- **Screenshot/code-supported cause:** The four supplied states showed the truncation and ambiguous
  symbols. The production tokens provided only an approximately 71-point centre, providers emitted
  literal `square` or the same move symbol for every workspace, and the pointer state discarded an
  open group as soon as another inner wedge won hover after a 110 ms dwell. Privacy-safe Debug
  diagnostics identified the long-hold dismissal as WindowRanger's own
  `globe-fn-gesture-safety-timeout`, not an Fn-up or external lifecycle event. Outer labels were
  centred in a fixed 116-point frame without wedge-local containment, so side labels could paint
  through the annulus or beyond the wheel; the neutral branch rendered a bare `xmark` with no text.
  Later privacy-safe diagnostics showed the direct arrows never reached command dispatch: with a
  submenu latched, crossing onto a direct inner item left it pending, so release resolved no command
  and dismissed with `trigger-released-without-action`. Privacy-safe diagnostics for the click
  report showed the wheel dismissing on `globe-fn-competing-systemDefined` before any radial action
  reached the shared dispatcher.
- **Implemented:** The panel, rings, and centre now have room for complete selected labels and state.
  Generated outer actions use meaningful fixed-centre symbols with their full label in the centre;
  workspace destinations use their configured alphanumeric key, profile destinations use stable
  numbered symbols, and current layouts retain their layout symbol with a separate checkmark. An
  open group stays latched across the neutral centre and
  other inner wedges; reaching its outer ring cancels the crossed-wedge switch, while a deliberate
  350 ms dwell switches to another group or direct item. Keyboard traversal, click precedence,
  context validation, and nonactivation are unchanged. An accepted Globe/Fn gesture now has no
  fixed duration; it remains open until actual release or an explicit competing/lifecycle cancel.
  Both rings now use fixed optical icon centres and the group disclosure chevron is overlaid rather
  than changing vertical alignment. Generated outer actions are icon-only, with complete text in the
  selected centre and accessibility; workspace destinations use their configured alphanumeric key,
  and profile destinations use stable numbered symbols rather than repeated placeholders. Releasing
  Hold-to-Show over a pending direct inner command now commits that command while preserving the
  latched group during pointer travel. Current layouts retain their semantic symbol, existing badge,
  and reapply detail. The neutral centre shows context without a persistent Cancel label; Escape and
  centre activation still cancel. Each group chevron now rotates and sits radially outward from its
  icon, so its direction matches the outer ring it reveals. Layout Type now resolves its inner-ring
  symbol from the current workspace layout, and Accordion uses a rounded three-pane treatment whose
  central pane is wider than its side panes. After a deliberate Globe/Fn hold has opened the wheel,
  mouse-button and companion system-defined events remain available to the wheel instead of
  cancelling it; the same inputs still disqualify the gesture before the hold threshold, and real
  key/modifier chords still cancel after opening.
  Command Wheel Settings now disables Add when every known command family is already saved, and its
  compact preview renders the production wheel itself with the saved order and representative
  contextual children instead of maintaining a visually divergent circle/capsule approximation.
- **Automated evidence:** The focused command-wheel and Settings checkpoint passes 111 tests and
  post-rebase local quick verification passes all 520 non-hosted tests. Coverage includes the exact
  group-to-centre-to-other-inner-to-outer travel path, stale dwell rejection, destination symbols,
  current-layout presentation, an accepted Globe/Fn hold with no scheduled expiry, and seven
  offscreen production render states. The selected action-first icon pass now has 116 focused tests,
  including distinct top-level silhouettes and exact compass-ordered occupancy symbols; local quick
  verification passes all 527 non-hosted tests, and an unsigned universal arm64/x86_64 Debug app
  build succeeds. A same-state, same-size reference/production comparison found no scoped P0/P1/P2
  icon mismatch.
  The focused suite also includes a dedicated Accordion production render and asserts that every
  Layout Type state inherits its current layout symbol. The click-cancellation correction passes
  117 focused tests and the complete local quick checkpoint passes all 529 non-hosted tests,
  including pre-threshold Fn-click rejection, accepted-hold pointer admission, native Globe-event
  suppression, and ordinary key/modifier cancellation. Catalogue exhaustion has pure coverage, and
  the Settings preview has a dedicated offscreen production render. The complete local quick
  checkpoint passes all 531 non-hosted tests after the Settings changes.
- **Installed evidence:** After a clean rebase onto current `origin/develop` at `e712590430b0`, the
  signed universal Debug daily candidate for `e712590430b0-dirty` is
  installed and running from `/Applications/WindowRanger.app`. Its Apple Development signature and
  Team ID `44NAD22AK6` pass strict deep verification. With explicit maintainer approval, this build
  includes the icon-only alignment, profile-symbol, neutral-centre, long-hold, and cross-wheel travel
  refinements, radial disclosure chevrons, Freeform placement/focus corrections, the selected
  action-first icon pass, the current-layout/Accordion icon correction, and the Globe/Fn click
  cancellation correction. The latest installed candidate also contains the catalogue Add-state and
  production-rendered Settings preview corrections. It has CDHash
  `94fb7dc647e232f20b4391a84f19b44570481da8`;
  the prior daily copy remains available at the
  repository-defined non-launchable backup path.
- **Live result:** Successive signed Debug candidates were tested throughout this pass. The user
  confirmed pointer focus, Freeform placement, direct and grouped commands, Globe/Fn clicks, the
  revised icon set, Accordion glyph, disabled exhausted Add menu, and production-rendered Settings
  preview were working or visibly improved, then explicitly closed the pass for merge.

## Live validation

### WR-052 — Move the application identity under AppRanger

- **Status:** Implementation and automated verification complete; live validation pending.
- **Requested:** 2026-08-13.
- **Smallest useful outcome:** use `dev.appranger.WindowRanger` for the application and test bundle
  identifiers while preserving existing local preferences, the current WindowServer recovery
  state, and the existing iCloud key-value store.
- **Acceptance boundary:** project, signing/export scripts, documentation, and bundle-dependent
  paths agree on the new identity; an automated migration copies missing preferences and recovery
  state without overwriting or deleting either identity's data; isolated tests pass. A signed
  installed build must still confirm the new provisioning profile, iCloud entitlement, fresh
  Accessibility approval, and launch-at-login behavior before this item can be Done.
- **Automated verification:** `./scripts/verify-local-ci.sh --quick` passed again on 2026-08-14
  with 555 tests and no failures. Stable Xcode archived build 3 as a universal app and an
  automatic Developer ID export passed strict code-signing verification with bundle identifier
  `dev.appranger.WindowRanger`, application identifier
  `44NAD22AK6.dev.appranger.WindowRanger`, and the preserved
  `44NAD22AK6.com.windowranger.WindowRanger` iCloud key-value entitlement. Installed-app migration,
  fresh Accessibility approval, and launch-at-login checks remain outstanding.

### WR-051 — Strengthen window-admission evidence and fixtures

- **Type:** Safety hardening / compatibility research
- **Priority:** P1
- **Status:** Live validation
- **Requested:** Compare established open-source macOS window managers and make WindowRanger's
  distinction between normal windows, dialogs, modal surfaces, floating panels, toolbars, and
  transient popups more robust.
- **User-observed:** On 2026-08-14 ChatGPT's Sparkle **Check for Updates** alert was moved to the
  Tiled workspace edge and inserted into the split instead of remaining a floating alert. The same
  class of failure has been seen with other Sparkle update alerts. A later Ghostty confirmation
  prompt reproduced the issue under the signed Debug build and produced a complete diagnostic trace.
- **Live evidence:** The signed Debug build classified the ChatGPT document window and updater as
  layer-0 `AXWindow` / `AXStandardWindow` surfaces. The document window exposed a Full Screen
  control. The 602 x 178 updater exposed Close but no Full Screen control; it accepted the requested
  position, rejected the requested size, and was then incorrectly reweighted into the Tiled tree.
  The Ghostty prompt was an `AXDialog` initially observed at WindowServer layer 8 with unsupported
  move/resize capability reads. It was admitted as an ambiguous normal window, rejected the requested
  size but accepted the position, and moved from `(1550, 314; 260 x 252)` to
  `(1683, 34; 260 x 252)`. Roughly 3.8 seconds later it reported layer 0 and was correctly floated,
  but its original position had already been lost; its layer then continued to alternate until close.
- **Expected:** A standard window proven movable but not resizable, with Close and no Full Screen
  control, floats automatically without using titles, dimensions, Sparkle-specific strings, or a
  whole-app exclusion. An explicit dialog on a known nonzero transient layer remains untouched until
  its layer settles. Missing layers or failed capability reads remain conservatively managed as
  normal, and a rejected resize cannot still move a fixed-size surface.
- **Research result:** AeroSpace's useful pattern is a real-window/dialog/popup classifier backed by
  captured Accessibility fixtures. yabai requires a root window and a narrow role/subrole set while
  recording move/resize capability; Amethyst requires a movable standard window. Preserve
  WindowRanger's central four-way admission boundary, privacy rules, title/size independence, and
  verified bundle-specific exceptions rather than copying broad app blacklists or heuristic lists.
- **Implemented:** Admission now records authoritative/unsupported/unavailable modal, focus,
  main-window, window-control, position-settable, and size-settable observations. Debug Settings
  presents that evidence and copies deterministic versioned JSON suitable for fixture capture. A
  table-driven corpus locks current standard, missing-subrole, sheet, system-dialog, dialog,
  floating-window, non-normal-layer, minimized, fullscreen, toolbar-role, and unknown-subrole
  decisions. The prior one-off Codex layer check is now the first versioned built-in compatibility
  profile. Profiles match bundle plus declared surface evidence, report their identifier in Debug
  Settings, logs, and snapshot JSON, and remain separate from personal App Rules. A narrowly gated
  standard window with Close present, Full Screen absent, position settable, and size not settable is
  now admitted as an automatically floating dialog. Capability failures remain normal-window
  admission, and ordinary document windows do not receive the additional support reads. A known
  nonzero-layer `AXDialog` is now deferred until its layer settles rather than being admitted to a
  layout. Frame application stops before position when its initial size write is rejected, preventing
  fixed-size surfaces from being partially moved after a failed resize.
- **Automated evidence:** Focused admission and workspace verification passes 119 tests. Local quick
  verification passes all 559 non-hosted tests, including test-isolation validation; it does not
  build, launch, sign, install, stop, or automate WindowRanger.app. Fixtures cover the captured
  ChatGPT document/updater distinction plus unavailable and immovable conservative fallbacks.
- **Live validation:** The signed Debug build from this branch kept the ordinary ChatGPT document
  window managed normally, classified the reopened Sparkle updater through the fixed-size path, and
  left the updater floating outside the Tiled tree. The user confirmed the result on 2026-08-14.
- **Follow-up live result:** The captured Ghostty confirmation prompt was reproduced against the
  changed signed app. It remained outside the managed split and retained its intended placement; the
  user confirmed the result before proceeding to the Quick App follow-ups. Other applications may
  expose different transient metadata, so the classifier remains fixture-backed and fail-closed
  rather than inferring from titles, dimensions, or broad application exclusions.

### WR-049 — Refine Command Wheel workspace-action icons

- **Type:** Visual refinement
- **Priority:** P2
- **Status:** Inbox
- **User-observed:** Go to Space, Place Window, Reset Windows in Space, Next Space, Previous Space,
  and Move to Space still needed clearer and more consistent iconography after the first Command
  Wheel visual pass. The user selected the first of three generated directions: framed-window
  transfer and placement symbols, a workspace grid with a navigation target, plain traversal
  arrows, and a single-window clockwise restore loop.
- **Implemented:** The six top-level actions now follow that selected grammar using monochrome SF
  Symbols and small system-symbol compositions that inherit the wheel's existing size, colour,
  selection, centre, accessibility, and Settings-preview behavior. Move and Place share a window
  silhouette but differ through transfer-arrow versus focus-frame treatment; Go combines the
  workspace grid with a small target; Previous/Next are plain opposing arrows; current-space reset
  encloses one window in a single clockwise loop, while Reset All retains its separate
  two-arrow silhouette. No wheel geometry, labels, commands, hit regions, or activation behavior
  changed.
- **Fidelity revision:** Live inspection showed the initial Option 1 approximation still differed
  visibly by a few pixels: Reset used the wrong loop geometry and an undersized browser-style
  window, the navigation arrows were short and heavy, and the framed/target compositions were
  optically small. The current candidate uses an explicit title-bar window made from native SF
  Symbols, a correctly oriented clockwise restore loop, longer regular-weight traversal arrows,
  and measured optical sizing for Move, Place, and Go. Enlarged source-versus-production crops now
  accompany the full 20-point wheel render; this revision has not been installed.
- **Product decision:** The current symbols are an intentionally provisional WIP checkpoint. The
  user wants to review the complete Command Wheel catalogue in Apple's SF Symbols app and prefer
  unchanged native symbols wherever they communicate the action clearly, combining or authoring a
  custom symbol only for the remaining gaps. That systematic visual pass is deferred; it does not
  block the already validated Command Wheel functionality.
- **Automated evidence:** The revised candidate's visual snapshot suites pass, and local quick
  verification passes all 535 non-hosted tests. Coverage fixes the six catalogue symbol
  identities, verifies every layered SF Symbol is available, and renders nine real production wheel
  states offscreen. A same-input comparison of the 1,254-pixel selected reference normalized beside
  the 1,240-pixel Retina production render, including equal-scale enlarged crops of each icon. An
  unsigned universal arm64/x86_64 Debug app build succeeds.
- **Installed evidence:** With explicit maintainer approval, the signed universal Debug daily build
  for `3868a49e8dc8-dirty` was installed and verified with CDHash
  `63998709b7486f80db4487361558c0583cd1fc06`. A separate daily installation from the WR-046
  worktree then replaced it with `f143af57c9a1-dirty` at 09:25; that running build contains the old
  icon identifiers. With fresh maintainer approval, the Option 1 build was reinstalled at 09:32 and
  is again running from `/Applications/WindowRanger.app`; its embedded revision, strict signature,
  two architectures, process path, and all four composite symbol identifiers were verified. The
  superseded WR-046 build is now retained at the non-launchable rollback path.
- **Next boundary:** Inventory every top-level, generated-child, layout, placement, and indicator
  symbol as Keep, Replace with native SF Symbol, or Custom Symbol required. Then compare the chosen
  family at live selected/unselected wheel scale and in Settings before completing WR-049.

### WR-048 — Protect global reset and cycle read-only focused windows

- **Type:** Command safety / focus compatibility bug
- **Priority:** P1
- **Status:** Done
- **User-observed:** Windows from several virtual spaces appeared together and Previous/Next window
  cycling stopped working. The expected behavior is that releasing a held Globe/Fn gesture cannot
  accidentally run a global recovery command, and every unambiguous managed window in the active
  workspace remains reachable through cycling.
- **Diagnostic-backed cause:** At 08:24:28 the held Command Wheel committed **Reset All Windows** on
  Globe/Fn release, which deliberately brought every managed window onscreen without changing its
  saved workspace assignment. Later, workspace 1 contained Chrome and NoteRanger, but NoteRanger
  exposed its ordinary layer-0 standard window as locally focused and main while making all three
  Accessibility focus attributes read-only. The shared candidate gate therefore excluded it and
  every cycle command ended with `no-candidate`.
- **Implemented:** In Hold-to-Show, **Reset All Windows** now requires an explicit click or Return;
  merely highlighting it and releasing Globe/Fn dismisses the wheel, with centre text and an
  accessibility hint explaining the confirmation. Press-to-Toggle behavior is unchanged. Focus
  candidate admission now permits the narrowly identifiable read-only case where a standard,
  visible, raiseable layer-0 window reports itself as both its application's focused and main
  window. Ambiguous and state-less read-only windows remain excluded, and the existing exact
  WindowServer verification remains authoritative after activation.
- **Automated evidence:** The focused diagnostic and Command Wheel suites pass 166 tests and local
  quick verification passes all 534 non-hosted tests. Coverage includes protected hold-release,
  explicit click availability, unchanged toggle behavior, the locally selected main-window fallback,
  and rejection of an ambiguous read-only window. The unsigned universal arm64/x86_64 Debug app
  also builds successfully.
- **Installed evidence:** With explicit maintainer approval, the signed universal Debug daily build
  for `3868a49e8dc8-dirty` is installed and running from `/Applications/WindowRanger.app`. Its Apple
  Development signature, Team ID `44NAD22AK6`, bundle identity, embedded revision, two architectures,
  strict code-signing verification, and running executable path were verified. Its CDHash is
  `437e2988e393780d909704e7dd59d4029883c116`; the prior daily copy remains at the repository-defined
  non-launchable rollback path.
- **Live result:** In the installed signed Debug build, Globe/Fn release over **Reset All Windows**
  no longer performs recovery, an explicit activation still does, and cycling through the affected
  workspace works again. The user confirmed the Command Wheel functionality works well and approved
  merging this checkpoint while keeping only the icon refinement as WIP.
- **Diagnostic-backed follow-up:** After restarting WindowRanger on 14 August 2026, repeated
  `cycle-window` commands in workspace 1 found Chrome and Claude visible on the interaction display
  but ended with `no-candidate`. Claude window `30331:8687` was an admitted, raiseable
  `AXStandardWindow` with a writable `AXMain` route, but WindowServer reported transient layer `-1`
  and `AXMain=false` until the user activated it directly; it then reported layer `0`, became main,
  and the existing exact-focus path could operate it.
- **Follow-up implemented:** The shared focus-candidate gate accepts a negative-layer standard
  window only when it is already tracked by the engine, meaningfully visible in the caller's scope,
  raiseable, and exposes a writable Accessibility focus route. Positive layers, negative-layer
  dialogs, and negative-layer read-only windows remain excluded; post-activation exact-window
  verification is unchanged.
- **Follow-up verification:** The focused diagnostic and workspace suites pass all 160 tests and
  local quick verification passes all 565 non-hosted tests. With explicit approval, signed universal
  Debug build `9402d3c594c4-dirty` is installed and running from
  `/Applications/WindowRanger.app`; its strict signature, embedded revision, two architectures, and
  running executable path were verified.
- **Follow-up live result:** After restarting WindowRanger while an inactive app shared the current
  workspace, cycling in both directions reached it before manual activation and continued through
  the workspace normally. The user confirmed the correction in the installed signed build.

### WR-036 — Swipe between workspaces

- **Type:** Feature
- **Priority:** P2
- **Status:** Live validation
- **Implemented:** General Settings now has an off-by-default, per-Mac three- or four-finger
  horizontal workspace swipe. A read-only HID event tap passes generic gesture contacts to a pure
  finger-count, coherence, axis, and threshold state machine. One accepted swipe dispatches the
  existing workspace-cycle command and latches until every finger lifts, so ordered wraparound and
  Independent Displays interaction routing remain owned by the existing engine. The monitor never
  suppresses or modifies events and suspends for full-screen games, system sleep, inactive login
  sessions, shortcut recording, and shutdown; display, profile, and app activation changes cancel
  an in-flight gesture. Settings reports a runtime issue when macOS does not expose the stream.
- **Automated evidence:** The unsigned Debug app target builds and local quick verification passes
  478 non-hosted tests. New coverage verifies left/right direction, three/four-finger admission,
  vertical and changed-contact rejection, one dispatch per gesture, monitor enable/suppression
  lifecycle, fail-closed availability, local-only persistence, and Settings search.
- **Installed evidence:** The signed universal Debug daily build for `b6d5762caeb7-dirty` is
  installed and running from `/Applications/WindowRanger.app`; its Apple Development signature,
  bundle identity, embedded revision, version `0.1.0 (1)`, and running executable path were verified.
- **Remaining validation:** Test three- and four-finger choices on the physical trackpad in both
  directions. Confirm one switch per swipe, wraparound at each end,
  interaction-display routing in Independent Displays, no interference with chosen macOS gestures,
  and safe pause/resume across a full-screen game and sleep/wake. The generic gesture event bridge is
  not a named public Core Graphics event type, so live behavior across supported macOS releases
  remains a required compatibility boundary.

### WR-035 — Use native glass for command feedback

- **Type:** Visual refinement
- **Priority:** P2
- **Status:** Live validation
- **Requested:** Make the centered command-feedback toast feel closer to the native macOS glass HUD
  without changing its short-lived, click-through, nonactivating behavior.
- **Implemented:** On macOS 26 and later, the toast uses Apple's public `NSGlassEffectView` with the
  regular style, a pill radius derived from half its live height, and its label installed through the
  glass-owned content view. It remains static rather than interactive because the panel deliberately
  ignores pointer events. macOS 14–25 retain the existing `NSVisualEffectView` HUD material with the
  same pill shape. The radius follows any display-driven height clamp. Placement, timing, coalescing,
  reduced-motion dismissal, VoiceOver announcements, shadow, and nonactivating panel policy are
  unchanged.
- **Automated evidence:** Local quick verification passes 470 tests, including native-glass versus
  fallback selection, correct content ownership, and pill curvature following a clamped live height.
- **Remaining validation:** Install a signed daily build on macOS 27 and compare short and wrapped
  feedback in light and dark appearances over varied backgrounds. Confirm the optical effect,
  curvature, text contrast, shadow, and dismissal feel native without stealing focus.

### WR-034 — Reconcile every split window after wake

- **Type:** Wake/layout bug
- **Priority:** P1
- **Status:** Live validation
- **User-observed:** After waking from sleep, some but not all windows in a Tiled split are
  occasionally returned to their expected frames. The report is intermittent; the available rotated
  diagnostics do not contain the failing physical sleep/wake sequence, so this remains
  user-observed rather than reproduced.
- **Expected:** Once displays and managed AX windows are ready after wake, every eligible Tiled or
  Accordion participant should match the layout calculated from the stable display snapshot. A
  temporarily unready app must not leave one split participant in stale geometry indefinitely.
- **Code-supported cause:** Wake reconciliation proved fresh `AXWindows` enumeration and performed
  one layout pass, but then accepted the immediately observed frames as its background-layout
  baseline. AX write success only means macOS accepted the attributes; it does not prove that the app
  retained the target frame. A late or ignored write could therefore become the baseline and suppress
  the normal background retry. The missing physical sleep/wake diagnostic means this remains the
  strongest code-supported cause rather than a reproduced cause.
- **Implemented:** Wake now retains the authoritative Tiled and Accordion solution, reads those
  frames back three times over a bounded period, and reapplies only mismatched windows that are still
  active layout participants. New lifecycle signals supersede the check. Deferred, full-screen,
  floating, removed, and newly ineligible windows receive no retry. A final mismatch is diagnostic
  and leaves the normal background layout baseline invalid so recovery can continue later.
- **Automated evidence:** Local quick verification passes 467 tests, including retained-frame,
  missing-frame, mismatch-tolerance, and bounded-verification policy coverage.
- **Remaining validation:** Install a signed daily build and exercise ordinary and topology-changing
  physical sleep/wake with multi-window Tiled and Accordion workspaces. Confirm every participant
  returns to its split, focus remains stable, and diagnostics show bounded verification rather than
  repeated layout traffic.

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
- **Private CI evidence:** [PR #7](https://github.com/AppRanger/windowranger/pull/7) uses WR-020's
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
  `dev.appranger.WindowRanger` bundle identifier but different designated requirements. macOS can
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
  - a future development-only identity does not alter the established public identity, migrated
    preferences and iCloud continuity, update continuity, or release provenance;
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

### WR-058 — Publish WindowRanger 0.1.0 Beta 5

- **Result:** Published
  [`v0.1.0-beta.5`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.5) as a
  GitHub prerelease on 15 August 2026. The protected annotated tag points to release commit
  `7b7c08df7b969a468383e64e51c3245f5997d223`, whose tree matches reviewed `develop` commit
  `ea8a9ea8a5d4da09a92d643ab19373c262005239`. The
  [release-branch CI run](https://github.com/AppRanger/windowranger/actions/runs/31901578794)
  passed 586 tests, static analysis, the unsigned universal Release build, both DMG smoke layouts,
  and artifact upload.
- **Streamlined Beta evidence:** The changed wake recovery, incomplete BSP partition, Quick App,
  menu-dismissal, and Accessibility-status paths had already passed signed daily testing and changed
  no packaging, signing, entitlement, bundle identity, migration, updater, or minimum-system
  boundary. The approved repeat-Beta path therefore skipped only the redundant packaged-app
  replacement install; all source, toolchain, signing, notarization, packaging, provenance,
  public-asset, and website gates still ran.
- **Distribution evidence:** Stable Xcode 26.6 produced universal Developer ID build `6` with bundle
  identifier `dev.appranger.WindowRanger`, Team ID `44NAD22AK6`, preserved iCloud key-value
  identifier `44NAD22AK6.com.windowranger.WindowRanger`, and CDHash
  `4147bd022d197bd59d5101392751b2d2c1a41cdd`. App notarization
  `ff732bbb-86d1-44de-9d97-cfcf3222e421` and DMG notarization
  `adab61ef-6db7-4d39-9601-73eba02d5d65` were accepted with zero logged issues. Both staples,
  Gatekeeper assessments, strict signatures, DMG verification, and packaged-app equality passed.
  The public DMG, ZIP, two checksum files, and provenance manifest were downloaded and round-trip
  verified after publication; the DMG SHA-256 is
  `c5f67245d5672c58e107285a4b75b5c90a14a9f04d511d0bbc8df47ac8c52ed9` and the ZIP SHA-256 is
  `45f886520d6990df340a73c324e75d9ff634601b0b86a796c17174280178755e`.
- **Website evidence:** [Website PR #4](https://github.com/AppRanger/windowranger-site/pull/4)
  merged as `5fa68ab47c8a3442d5de5487f4ad8d548c718e55` and deployed as Cloudflare version
  `574666f6-f0cc-4e6b-86c7-9fb87aab0ee0`; documentation-only
  [PR #5](https://github.com/AppRanger/windowranger-site/pull/5) recorded that deployment as
  `83f32e501701369610fb15e1a48a3e13c546ed87`. Both `windowranger.com` and
  `www.windowranger.com` show Download Beta 5 and link to the published release. Desktop and mobile
  browser checks found no horizontal overflow and zero console errors or warnings.

### WR-054 — Publish WindowRanger 0.1.0 Beta 4

- **Result:** Published
  [`v0.1.0-beta.4`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.4) as a
  GitHub prerelease on 14 August 2026. The protected annotated tag points to release commit
  `6720e6ee3ad7bbedd989c0dbfc60923f99d8eb4f`, whose tree matches reviewed `develop` commit
  `6ad179891b65ea8b6620184fdb66daf79dfad477`. The
  [release-branch CI run](https://github.com/AppRanger/windowranger/actions/runs/31791956933)
  passed 565 tests, static analysis, the unsigned universal Release build, both DMG smoke layouts,
  and artifact upload.
- **Streamlined Beta evidence:** The changed transient-dialog, Quick App, and app-cycling paths had
  already passed signed live testing before merge and changed no packaging, signing, entitlement,
  bundle identity, migration, updater, or minimum-system boundary. The approved repeat-Beta path
  therefore skipped only the redundant local replacement install; all source, toolchain, signing,
  notarization, packaging, provenance, public-asset, and website gates still ran.
- **Distribution evidence:** Stable Xcode 26.6 produced universal Developer ID build `5` with
  bundle identifier `dev.appranger.WindowRanger`, Team ID `44NAD22AK6`, preserved iCloud key-value
  identifier `44NAD22AK6.com.windowranger.WindowRanger`, and CDHash
  `1011c48c974953f843366bb4978855b24452d033`. App notarization
  `2d1f53a2-9593-42c0-8502-74f2ae11ebc6` and DMG notarization
  `3cf86dac-1b79-446b-97ef-c5a5cddc4fb0` were accepted with zero logged issues. Both staples,
  Gatekeeper assessments, strict signatures, DMG verification, and packaged-app equality passed.
  The public DMG, ZIP, two checksum files, and provenance manifest were downloaded and round-trip
  verified after publication; the DMG SHA-256 is
  `c9f9db3d332287cd860eba72f5987a1de08197bcf3dc4e7e28034eb7f460c8c1` and the ZIP SHA-256 is
  `eb186b770d6dbfbb3e47d402eaca6d08155588ace8694f379639459181167a6d`.
- **Website evidence:** [Website PR #2](https://github.com/AppRanger/windowranger-site/pull/2)
  merged as `b6fe6106820c6aa705d5187c1f4541b1ffc45f8f` and deployed as Cloudflare version
  `68ee44ea-8a6a-4841-bd47-654f77f47882`; documentation-only
  [PR #3](https://github.com/AppRanger/windowranger-site/pull/3) recorded that deployment as
  `91e9c754d709b3e58b1357f1b19401873e49617b`. Both `windowranger.com` and
  `www.windowranger.com` show Download Beta 4 and link to the published release. Desktop and mobile
  browser checks found no horizontal overflow and zero console errors or warnings.

### WR-053 — Publish WindowRanger 0.1.0 Beta 3

- **Result:** Published
  [`v0.1.0-beta.3`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.3) as a
  GitHub prerelease on 14 August 2026 after maintainer testing and explicit approval. The annotated
  tag points to release commit `63e09fb893114109fffda813654e0a92d0bc328b`; its
  [release-branch CI run](https://github.com/AppRanger/windowranger/actions/runs/31782291211)
  passed 556 tests, static analysis, the unsigned universal Release build, both DMG smoke layouts,
  and artifact upload.
- **Distribution evidence:** Stable Xcode 26.6 produced universal Developer ID build `4` with
  bundle identifier `dev.appranger.WindowRanger`, Team ID `44NAD22AK6`, and CDHash
  `34c6f294633331e853c43f4f5afa362760e3ff21`. App notarization
  `4721cd68-8636-4cd6-aa7e-db1c5629a4c5` and DMG notarization
  `2a33c480-d724-4057-8523-8c9a3fce03be` were accepted with zero logged issues. The stapled DMG,
  ZIP, two checksum files, and provenance manifest were uploaded and round-trip verified; the DMG
  SHA-256 is `c30a56a45d73197ade9a1f07ee60ade38df6049c6271591d9253947f36abf1ba`
  and the ZIP SHA-256 is
  `43ada185920908978602ad15a4f4e2416fa762d935d97840ca8882cd086661c9`.
- **Website evidence:** [Website PR #1](https://github.com/AppRanger/windowranger-site/pull/1)
  merged as `d0a6e1b8d1c7095b9b57c954504048b9f6bdab74` and was deployed as Cloudflare version
  `19ee21ce-cd88-4f07-be85-dbe2cb0f7b6c`. Both `windowranger.com` and `www.windowranger.com`
  serve the Beta 3 link and feature summary; desktop/mobile browser checks found no console errors
  or horizontal overflow, and the live Command Wheel asset matches the reviewed release render.

### WR-043 — Use system display groups for Compact and Medium menu-bar styles

- **Result:** Compact, Medium, and Full on macOS 27 now use one movable standard status item per
  logical display without a redundant app glyph. Compact adapts keys and names to the configured
  display symbol, Medium retains readable workspace chips, Settings embeds the same production
  views, and only Full exposes workspace switching and hover geometry. macOS 14–26 retain the
  established single-item compatibility path.
- **Evidence:** The focused 41-test menu-bar suite and all 517 non-hosted tests pass, the unsigned
  universal Debug app builds, and the four-symbol visual fixture covers horizontal, portrait,
  laptop, and combined-display key safe areas. The Apple Development-signed universal candidate was
  installed with its signature and embedded revision verified; the maintainer live-validated the
  final macOS 27 Compact layout and confirmed the symbol alignment looks correct.

### WR-037 — Publish WindowRanger 0.1.0 Beta 2

- **Result:** Published
  [`v0.1.0-beta.2`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.2) as a
  GitHub prerelease on 12 August 2026 after maintainer testing and explicit approval. The protected
  annotated tag points to reviewed release commit `82b2fa381ae4`; the Developer ID-signed,
  notarized, stapled DMG and ZIP plus checksums and provenance manifest were downloaded after
  publication and round-trip verified against that immutable source and the recorded SHA-256
  values. Remaining product live-validation items stay independently tracked.

### WR-042 — Match focused-report history by structured window fields

- **Type:** Diagnostics bug / Beta 2 release blocker
- **Status:** Done
- **Result:** Focused-window reports now decode retained diagnostics and match exact window tokens
  only in structured field values, with digit-and-colon boundaries preventing timestamps, metadata,
  and adjacent identifiers from admitting unrelated action groups. Focused regression tests and the
  complete 513-test local, public integration, and release-branch gates pass; the corrected change
  was reviewed before the final Beta 2 candidate was built.

### WR-041 — Choose or hide menu-bar display icons

- **Result:** Each profile display role now owns an Automatic, Horizontal Monitor, Vertical
  Monitor, Laptop, or None menu-bar icon choice while physical monitor bindings remain local to
  each Mac. Every presentation path and the Settings preview share the resolved configuration;
  None reclaims the icon width without removing workspace controls. A deferred AppDelegate update
  resolves configuration only after `@Published` profile, binding, or topology state commits,
  preventing the live menu bar from rendering the preceding selection.
- **Evidence:** All 512 isolated tests pass, universal Debug builds pass with the macOS 26.5 and
  macOS 27.0 SDKs, and a private Developer ID build was live-validated on macOS 27 across repeated
  independent changes to both display roles. Diagnostic capture proved model, persistence, role
  resolution, and rendered status-item values match; temporary mapping logs were removed from the
  final source.

### WR-040 — Preview and activate workspace apps from the menu bar

- **Result:** Full-mode workspace segments now highlight on hover and open a delayed nonactivating
  native-glass app shelf. The shelf handles empty and overflowing workspaces, survives pointer
  transfer in both directions, and delegates workspace switching plus exact managed-app focus to
  the engine without polling or private APIs. It now dismisses immediately when another application
  activates or a pointer button is pressed outside it; short-lived local/global mouse monitors exist
  only while presentation is pending or visible and are removed on every dismissal path.
- **Evidence:** The integrated 512-test suite passes with production-view, geometry, grouping, and
  exact-focus coverage. The macOS 27 Developer ID candidates were live-validated for rollover,
  empty/populated shelf layout, glass styling, scroller policy, pointer return, app selection, and
  unchanged workspace click routing. Follow-up policy tests cover inside, outside, inactive, and
  pending-presentation pointer dismissal. Local quick verification passes all 577 non-hosted tests,
  and the unsigned universal Debug app builds; updated live validation remains required.

### WR-039 — Restore Full menu-bar workspace clicks on macOS 27

- **Result:** macOS 27 Full mode uses one public status item per logical display group and resolves
  its workspace segments from the action-time global pointer position. Workspace primary clicks
  switch directly, secondary and fallback actions open the shared menu, each display block moves as
  a unit, and the redundant standalone app icon is hidden. Compact, Medium, and pre-macOS-27 Full
  retain their existing single-item path.
- **Evidence:** The integrated 512-test suite passes, including version policy, grouped planning,
  pointer routing, pressure, hover, menu fallback, and accessibility coverage. Matching signed
  candidates preserved macOS 26 behavior and live-validated ordering, group movement, workspace
  clicks, and right-click routing on macOS 27. The initial geometric-menu position jump remains a
  documented cosmetic macOS 27 beta limitation rather than a reason to reintroduce unsafe routing.

### WR-038 — Do not let stale parked-window focus undo a workspace switch

- **Result:** Candidate focus now succeeds from observed exact AX or active-app plus unambiguous
  WindowServer evidence, with a bounded one-shot AppKit activation fallback and exact retry. A
  same-app higher-layer window invalidates WindowServer proof, competing focus still aborts, and
  the border's verified-target handoff expires after three seconds. No per-app exception was added.
- **Evidence:** The complete local quick gate passes 489 non-hosted tests. The signed universal
  Debug daily build for `dea7fc77d216-dirty` was installed and verified, and the maintainer confirmed
  workspace return and cycling remain correct with Claude, Chrome, Activity Monitor, and Excel:
  focus borders remain present, background candidates do not advance, and workspaces do not jump.

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

- **Result:** Made `AppRanger/windowranger` public and published `v0.1.0-beta.1` as a GitHub
  prerelease on 10 August 2026, preserving the exact signed, notarized artifact tag and all five
  checksum/provenance-verified assets. Enabled private vulnerability reporting, secret scanning and
  push protection; protected `main`, `develop`, and `v*` tags.
- **Evidence:** The public release is
  [WindowRanger 0.1.0 Beta 1](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.1)
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
  [31363831170](https://github.com/AppRanger/windowranger/actions/runs/31363831170) completed with
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

- Menu-bar and Workspace Settings visual QA have no unresolved P0/P1/P2 mismatch. The earlier
  contextual radial-menu pass was superseded by the WR-028 screenshot-backed cleanup; its new
  offscreen states pass, while signed-app interaction remains under Live validation.
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
